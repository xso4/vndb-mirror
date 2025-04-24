package VNWeb::Docs::Edit;

use VNWeb::Prelude;
use VNWeb::Docs::Lib;


my($FORM_IN, $FORM_OUT) = form_compile 'in', 'out', {
    id      => { vndbid => 'd' },
    title   => { sl => 1, maxlength => 200 },
    content => { default => '' },
    hidden  => { anybool => 1 },
    locked  => { anybool => 1 },

    editsum => { editsum => 1 },
};


FU::get qr{/$RE{drev}/edit} => sub($id,$rev=0) {
    my $d = db_entry $id, $rev or fu->notfound;
    fu->denied if !can_edit d => $d;

    $d->{editsum} = $d->{chrev} == $d->{maxrev} ? '' : "Reverted to revision $d->{id}.$d->{chrev}";

    framework_ title => "Edit $d->{title}", dbobj => $d, tab => 'edit',
    sub {
        div_ widget(DocEdit => $FORM_OUT, $d), '';
    };
};


js_api DocEdit => $FORM_IN, sub {
    my $data = shift;
    my $doc = db_entry $data->{id} or fu->notfound;

    fu->denied if !can_edit d => $doc;
    $data->{html} = md2html $data->{content};

    my $c = db_edit d => $doc->{id}, $data;
    return 'No changes' if !$c->{nitemid};
    +{ _redir => "/$c->{nitemid}.$c->{nrev}" };
};


js_api Markdown => {
    content => { default => '' }
}, sub {
    fu->denied if !auth->permDbmod;
    +{ html => enrich_html md2html shift->{content} };
};


1;
