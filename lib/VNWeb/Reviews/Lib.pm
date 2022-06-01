package VNWeb::Reviews::Lib;

use VNWeb::Prelude;
use Exporter 'import';
our @EXPORT = qw/reviews_helpfulness reviews_vote_ reviews_format/;

sub reviews_helpfulness {
    my($w) = @_;
    my ($uup, $aup, $udown, $adown) = (floor($w->{c_up}/100), $w->{c_up}%100, floor($w->{c_down}/100), $w->{c_down}%100);
    return sprintf '%.0f', max 0, ($uup + 0.3*$aup) - ($udown + 0.3*$adown);
}

sub reviews_vote_ {
    my($w) = @_;
    span_ sub {
        elm_ 'Reviews.Vote' => $VNWeb::Reviews::Elm::VOTE_OUT, {%$w, mod => auth->permBoardmod||0} if !config->{read_only} && ($w->{can} || auth->permBoardmod);
        my $p = reviews_helpfulness $w;
        b_ class => 'grayedout', sprintf ' %d point%s', $p, $p == 1 ? '' : 's';
        b_ class => 'grayedout', sprintf ' %.2f/%.2f', $w->{c_up}/100, $w->{c_down}/100 if auth->permBoardmod;
    }
}

# Mini-reviews don't expand vndbids on submission, so they need an extra bb_subst_links() pass.
sub reviews_format {
    my($w, @opt) = @_;
    bb_format($w->{isfull} ? $w->{text} : bb_subst_links($w->{text}), @opt);
}

1;
