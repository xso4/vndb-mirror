package VNWeb::Chars::VNTab;

use VNWeb::Prelude;

sub chars_ {
    my($v) = @_;
    my $view = viewget;
    my $chars = VNWeb::Chars::Page::fetch_chars($v->{id}, sql('id IN(SELECT id FROM chars_vns WHERE vid =', \$v->{id}, ')'));
    return if !@$chars;

    my $max_spoil = max(
        map max(
            (map $_->{override}//($_->{lie}?2:$_->{spoil}), grep !$_->{hidden} && !(($_->{override}//0) == 3), $_->{traits}->@*),
            (map $_->{spoil}, $_->{vns}->@*),
            defined $_->{spoil_gender} ? 2 : 0,
            $_->{description} =~ /\[spoiler\]/i ? 2 : 0,
        ), @$chars
    );
    $chars = [ grep +grep($_->{spoil} <= $view->{spoilers}, $_->{vns}->@*), @$chars ];
    my $has_sex = grep !$_->{hidden} && $_->{sexual} && ($_->{override}//$_->{spoil}) <= $view->{spoilers}, map $_->{traits}->@*, @$chars;

    my sub opts_ {
        p_ class => 'mainopts', sub {
            debug_ $chars;
            if($max_spoil) {
                a_ mkclass(checked => $view->{spoilers} == 0), href => '?view='.viewset(spoilers=>0,traits_sexual=>$view->{traits_sexual}).'#chars', 'Hide spoilers';
                a_ mkclass(checked => $view->{spoilers} == 1), href => '?view='.viewset(spoilers=>1,traits_sexual=>$view->{traits_sexual}).'#chars', 'Show minor spoilers';
                a_ mkclass(standout =>$view->{spoilers} == 2), href => '?view='.viewset(spoilers=>2,traits_sexual=>$view->{traits_sexual}).'#chars', 'Spoil me!' if $max_spoil == 2;
            }
            small_ ' | ' if $has_sex && $max_spoil;
            a_ mkclass(checked => $view->{traits_sexual}), href => '?view='.viewset(spoilers=>$view->{spoilers},traits_sexual=>!$view->{traits_sexual}).'#chars', 'Show sexual traits' if $has_sex;
        };
    }

    my %done;
    my $first = 0;
    for my $r (keys %CHAR_ROLE) {
        my @c = grep grep($_->{role} eq $r, $_->{vns}->@*) && !$done{$_->{id}}++, @$chars;
        next if !@c;
        article_ sub {
            opts_ if !$first++;
            h1_ $CHAR_ROLE{$r}{ @c > 1 ? 'plural' : 'txt' };
            VNWeb::Chars::Page::chartable_($_, 1, $_ != $c[0], 1) for @c;
        }
    }

    article_ sub {
        opts_;
        h1_ '(Characters hidden by spoiler settings)';
    } if !$first;
}


TUWF::get qr{/$RE{vid}/chars}, sub {
    my $v = db_entry tuwf->capture('id');
    return tuwf->resNotFound if !$v;

    VNWeb::VN::Page::enrich_vn($v);

    framework_ title => $v->{title}[1], index => 1, dbobj => $v, hiddenmsg => 1,
    sub {
        VNWeb::VN::Page::infobox_($v);
        VNWeb::VN::Page::tabs_($v, 'chars');
        chars_ $v;
    };
};

1;
