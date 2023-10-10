package VNWeb::Docs::Edit;

use VNWeb::Prelude;
use VNWeb::Docs::Lib;


my $FORM = {
    id      => { vndbid => 'd' },
    title   => { maxlength => 200 },
    content => { default => '' },
    hidden  => { anybool => 1 },
    locked  => { anybool => 1 },

    editsum => { _when => 'in out', editsum => 1 },
};

my $FORM_OUT = form_compile out => $FORM;
my $FORM_IN  = form_compile in  => $FORM;
my $FORM_CMP = form_compile cmp => $FORM;


TUWF::get qr{/$RE{drev}/edit} => sub {
    my $d = db_entry tuwf->captures('id', 'rev') or return tuwf->resNotFound;
    return tuwf->resDenied if !can_edit d => $d;

    $d->{editsum} = $d->{chrev} == $d->{maxrev} ? '' : "Reverted to revision $d->{id}.$d->{chrev}";

    framework_ title => "Edit $d->{title}", dbobj => $d, tab => 'edit',
    sub {
        elm_ DocEdit => $FORM_OUT, $d;
    };
};


elm_api DocEdit => $FORM_OUT, $FORM_IN, sub {
    my $data = shift;
    my $doc = db_entry $data->{id} or return tuwf->resNotFound;

    return elm_Unauth if !can_edit d => $doc;
    return elm_Unchanged if !form_changed $FORM_CMP, $data, $doc;

    $data->{html} = md2html $data->{content};
    my $c = db_edit d => $doc->{id}, $data;
    elm_Redirect "/$c->{nitemid}.$c->{nrev}";
};


elm_api Markdown => undef, {
    content => { default => '' }
}, sub {
    return elm_Unauth if !auth->permDbmod;
    elm_Content enrich_html md2html shift->{content};
};


1;
