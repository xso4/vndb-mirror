package VNWeb::ULists::Lib;

use VNWeb::Prelude;
use VNWeb::Releases::Lib 'releases_by_vn';
use Exporter 'import';

our @EXPORT = qw/
    ulists_priv ulist_filtlabels
    enrich_ulists_widget ulists_rlist_counts_ ulists_widget_
    ulists_widget_full_data
/;

# Can we see private stuff on this user's list?
# Only used to determine whether we can *view* private stuff on the list, editing is still restricted to the currently logged-in user.
sub ulists_priv {
    auth->permUsermod || auth->api2Listread(shift)
}


sub ulist_filtlabels($uid,$count=0) {
    my $own = ulists_priv $uid;

    my $l = fu->SQL(
        'SELECT l.id, l.label, l.private', $count ? ', coalesce(x.count, 0) as count' : (),
          'FROM ulist_labels l',
           $count ? ('LEFT JOIN (
              SELECT x.id, COUNT(*)
                FROM ulist_vns uv, unnest(uv.labels) x(id)
               WHERE uid =', $uid, $own ? () : 'AND NOT uv.c_private', '
               GROUP BY x.id
            ) x(id, count) ON x.id = l.id') : (), '
          WHERE l.uid =', $uid, $own ? () : 'AND (NOT l.private OR l.id = 7)', # XXX: 'Voted' (7) is always visibible
         'ORDER BY CASE WHEN l.id < 10 THEN l.id ELSE 10 END, l.label'
    )->allh;

    # Virtual 'No label' label, only ever has private VNs.
    push @$l, {
        id => 0, label => 'No label', private => 1,
        $count ? (count => fu->SQL("SELECT count(*) FROM ulist_vns WHERE labels IN('{}','{7}') AND uid =", $uid)->val) : (),
    } if $own;

    $l
}


# Enrich a list of VNs with basic data necessary for ulist_widget_.
sub enrich_ulists_widget($l) {
    fu->enrich(set => 'on_vnlist', SQL('SELECT vid, true FROM ulist_vns WHERE uid =', auth->uid, 'AND vid'), $l) if auth;
    fu->enrich(aov => 'vnlist_labels', sub { SQL '
        SELECT uv.vid, ul.id
          FROM ulist_vns uv, unnest(uv.labels) l(id), ulist_labels ul
         WHERE ul.uid =', auth->uid, 'AND uv.uid =', auth->uid, 'AND ul.id = l.id AND uv.vid', IN($_), '
         ORDER BY CASE WHEN ul.id < 10 THEN ul.id ELSE 10 END, ul.label'
    }, $l) if auth;
}


sub ulists_rlist_counts_($v) {
    return if !$v->{rlist};
    my $total = sum $v->{rlist}->@*;
    span_ class => $v->{rlist}[2] == $total ? 'done' : $v->{rlist}[2] < $total ? 'todo' : undef,
          (map +('+', "rlist_$_"), grep $v->{rlist}[$_], 0..$#{$v->{rlist}}),
          title => join(', ', map "$RLIST_STATUS{$_} ($v->{rlist}[$_])", grep $v->{rlist}[$_], 0..$#{$v->{rlist}}),
    $total ? sprintf ' %d/%d', $v->{rlist}[2], $total : '';
}


sub ulists_widget_($v) {
    span_ widget(UListWidget => {
        vid    => $v->{id},
        labels => $v->{on_vnlist} ? [ map 1*$_, $v->{vnlist_labels}->@* ] : undef,
    }), sub {
        my $img = !$v->{on_vnlist} ? 'add' :
            (reverse sort map "l$_", grep $_ >= 1 && $_ <= 6, $v->{vnlist_labels}->@*)[0] || 'unknown';
        abbr_ class => "icon-list-$img ulist-widget-icon", '';
        ulists_rlist_counts_ $v;
    } if auth && exists $v->{vnlist_labels};
}


# Returns the full UListWidget data structure for the given VN.
sub ulists_widget_full_data($v, $vnpage=0, $canvote=undef) {
    my $lst = fu->SQL('SELECT vid, vote, notes, started, finished, labels FROM ulist_vns WHERE uid =', auth->uid, 'AND vid =', $v->{id})->rowh;
    my $review = exists $v->{myreview} ? $v->{myreview} : fu->SQL('SELECT id FROM reviews WHERE uid =', auth->uid, 'AND vid =', $v->{id})->val;
    my $length = !$vnpage && fu->SQL('SELECT sum(length::int), count(*) FROM vn_length_votes WHERE vid =', $v->{id}, 'AND uid =', auth->uid)->rowa;
    my $rel = !$vnpage && releases_by_vn $v->{id};
    my $today = strftime '%Y%m%d', gmtime;
    $canvote //= grep $_->{released} && $_->{released} <= $today, @$rel if $rel;
    # More strict but faster fallback
    $canvote //= sprintf('%08d', $v->{c_released}||99999999) <= $today;
    +{
        vid       => $v->{id},
        labels    => $lst->{vid} ? [ map 1*$_, $lst->{labels}->@* ] : undef,
        canvote   => $lst->{vote} || $canvote ? \1 : \0,
        canreview => $review || ($canvote && can_edit(w => {})) || 0 ? \1 : \0,
        vote      => $lst->{vote} && fmtvote($lst->{vote}),
        review    => $review,
        notes     => $lst->{notes}||'',
        started   => int(($lst->{started}||0) =~ s/-//rg),
        finished  => int(($lst->{finished}||0) =~ s/-//rg),
        $vnpage ? () : (
            title     => $v->{title}[1],
            length    => $length->[0] ? fragment { vnlength_ @$length } : undef,
            releases  => $rel,
            rlist     => fu->SQL('SELECT rid AS id, status FROM rlists WHERE uid =', auth->uid, 'AND rid IN(SELECT id FROM releases_vn WHERE vid =', $v->{id}, ')')->allh,
        ),
    };
}

1;
