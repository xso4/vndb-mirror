package VNWeb::Reviews::Lib;

use VNWeb::Prelude;
use Exporter 'import';
our @EXPORT = qw/reviews_helpfulness reviews_vote_ reviews_format/;

sub reviews_helpfulness {
    my($w) = @_;
    my ($uup, $aup, $udown, $adown) = (floor($w->{c_up}/100), $w->{c_up}%100, floor($w->{c_down}/100), $w->{c_down}%100);
    return sprintf '%.0f', max 0, ($uup + 0.3*$aup) - ($udown + 0.3*$adown);
}

sub reviews_vote_($w) {
    span_ sub {
        span_ widget(ReviewsVote => $VNWeb::Reviews::JS::VOTE, {%$w, mod => auth->permBoardmod||0}), '' if !config->{read_only} && ($w->{user_id}//'u') ne (auth->uid//'');
        my $p = reviews_helpfulness $w;
        small_ sprintf ' %d point%s', $p, $p == 1 ? '' : 's';
        small_ sprintf ' %.2f/%.2f', $w->{c_up}/100, $w->{c_down}/100 if auth->permBoardmod;
    }
}

1;
