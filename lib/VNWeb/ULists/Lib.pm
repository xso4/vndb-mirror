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

    my $l = tuwf->dbAlli(
        'SELECT l.id, l.label, l.private', $count ? ', coalesce(x.count, 0) as count' : (),
          'FROM ulist_labels l',
           $count ? ('LEFT JOIN (
              SELECT x.id, COUNT(*)
                FROM ulist_vns uv, unnest(uv.labels) x(id)
               WHERE uid =', \$uid, $own ? () : 'AND NOT uv.c_private', '
               GROUP BY x.id
            ) x(id, count) ON x.id = l.id') : (), '
          WHERE l.uid =', \$uid, $own ? () : 'AND (NOT l.private OR l.id = 10-1-1-1)', # XXX: 'Voted' (7) is always visibible
         'ORDER BY CASE WHEN l.id < 10 THEN l.id ELSE 10 END, l.label'
    );

    # Virtual 'No label' label, only ever has private VNs.
    push @$l, {
        id => 0, label => 'No label', private => 1,
        $count ? (count => tuwf->dbVali("SELECT count(*) FROM ulist_vns WHERE labels IN('{}','{7}') AND uid =", \$uid)) : (),
    } if $own;

    $l
}


# Enrich a list of VNs with basic data necessary for ulist_widget_.
sub enrich_ulists_widget {
    enrich_merge id => sql('SELECT vid AS id, true AS on_vnlist FROM ulist_vns WHERE uid =', \auth->uid, 'AND vid IN'), @_ if auth;

    enrich_flatten vnlist_labels => id => vid => sub { sql '
        SELECT uv.vid, ul.id
          FROM ulist_vns uv, unnest(uv.labels) l(id), ulist_labels ul
         WHERE ul.uid =', \auth->uid, 'AND uv.uid =', \auth->uid, 'AND ul.id = l.id AND uv.vid IN', $_[0], '
         ORDER BY CASE WHEN ul.id < 10 THEN ul.id ELSE 10 END, ul.label'
    }, @_ if auth;
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
    my $lst = tuwf->dbRowi('SELECT vid, vote, notes, started, finished, labels FROM ulist_vns WHERE uid =', \auth->uid, 'AND vid =', \$v->{id});
    my $review = tuwf->dbVali('SELECT id FROM reviews WHERE uid =', \auth->uid, 'AND vid =', \$v->{id});
    $canvote //= sprintf('%08d', $v->{c_released}||99999999) <= strftime '%Y%m%d', gmtime;
    +{
        vid       => $v->{id},
        labels    => $lst->{vid} ? [ map 1*$_, $lst->{labels}->@* ] : undef,
        canvote   => $lst->{vote} || $canvote || 0 ? \1 : \0,
        canreview => $review || ($canvote && can_edit(w => {})) || 0 ? \1 : \0,
        vote      => $lst->{vote} && fmtvote($lst->{vote}),
        review    => $review,
        notes     => $lst->{notes}||'',
        started   => int(($lst->{started}||0) =~ s/-//rg),
        finished  => int(($lst->{finished}||0) =~ s/-//rg),
        $vnpage ? () : (
            title     => $v->{title}[1],
            releases  => releases_by_vn($v->{id}),
            rlist     => tuwf->dbAlli('SELECT rid AS id, status FROM rlists WHERE uid =', \auth->uid, 'AND rid IN(SELECT id FROM releases_vn WHERE vid =', \$v->{id}, ')'),
        ),
    };
}

1;
