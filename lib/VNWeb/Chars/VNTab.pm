package VNWeb::Chars::VNTab;

use VNWeb::Prelude;

sub chars_ {
    my($v) = @_;
    my $view = viewget;
    my $chars = VNWeb::Chars::Page::fetch_chars($v->{id}, sql('id IN(SELECT id FROM chars_vns WHERE vid =', \$v->{id}, ')'));
    return if !@$chars;

    my $max_spoil = max(
        map max(
            (map $_->{spoil}, grep !$_->{hidden}, $_->{traits}->@*),
            (map $_->{spoil}, $_->{vns}->@*),
            defined $_->{spoil_gender} ? 2 : 0,
            $_->{desc} =~ /\[spoiler\]/i ? 2 : 0,
        ), @$chars
    );
    $chars = [ grep +grep($_->{spoil} <= $view->{spoilers}, $_->{vns}->@*), @$chars ];
    my $has_sex = grep !$_->{hidden} && $_->{spoil} <= $view->{spoilers} && $_->{sexual}, map $_->{traits}->@*, @$chars;

    my %done;
    my $first = 0;
    for my $r (keys %CHAR_ROLE) {
        my @c = grep grep($_->{role} eq $r, $_->{vns}->@*) && !$done{$_->{id}}++, @$chars;
        next if !@c;
        div_ class => 'mainbox', sub {

            p_ class => 'mainopts', sub {
                if($max_spoil) {
                    a_ mkclass(checked => $view->{spoilers} == 0), href => '?view='.viewset(spoilers=>0,traits_sexual=>$view->{traits_sexual}).'#chars', 'Hide spoilers';
                    a_ mkclass(checked => $view->{spoilers} == 1), href => '?view='.viewset(spoilers=>1,traits_sexual=>$view->{traits_sexual}).'#chars', 'Show minor spoilers';
                    a_ mkclass(standout =>$view->{spoilers} == 2), href => '?view='.viewset(spoilers=>2,traits_sexual=>$view->{traits_sexual}).'#chars', 'Spoil me!' if $max_spoil == 2;
                }
                b_ class => 'grayedout', ' | ' if $has_sex && $max_spoil;
                a_ mkclass(checked => $view->{traits_sexual}), href => '?view='.viewset(spoilers=>$view->{spoilers},traits_sexual=>!$view->{traits_sexual}).'#chars', 'Show sexual traits' if $has_sex;
            } if !$first++;

            h1_ $CHAR_ROLE{$r}{ @c > 1 ? 'plural' : 'txt' };
            VNWeb::Chars::Page::chartable_($_, 1, $_ != $c[0], 1) for @c;
        }
    }
}


TUWF::get qr{/$RE{vid}/chars}, sub {
    my $v = db_entry tuwf->capture('id');
    return tuwf->resNotFound if !$v;

    VNWeb::VN::Page::enrich_vn($v);

    framework_ title => $v->{title}, index => 1, dbobj => $v, hiddenmsg => 1,
    sub {
        VNWeb::VN::Page::infobox_($v);
        VNWeb::VN::Page::tabs_($v, 'chars');
        chars_ $v;
    };
};

1;
