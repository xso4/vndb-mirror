package VNWeb::ULists::Lib;

use VNWeb::Prelude;
use VNWeb::Releases::Lib 'releases_by_vn';
use Exporter 'import';

our @EXPORT = qw/ulists_own ulist_filtlabels enrich_ulists_widget ulists_widget_ ulists_widget_full_data/;

# Do we have "ownership" access to this users' list (i.e. can we edit and see private stuff)?
sub ulists_own {
    auth->permUsermod || auth->api2Listread(shift)
}


sub ulist_filtlabels {
    my($uid, $count) = @_;
    my $own = ulists_own $uid;

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


# Enrich a list of VNs with data necessary for ulist_widget_.
sub enrich_ulists_widget {
    enrich_merge id => sql('SELECT vid AS id, true AS on_vnlist FROM ulist_vns WHERE uid =', \auth->uid, 'AND vid IN'), @_ if auth;

    enrich vnlist_labels => id => vid => sub { sql '
        SELECT uv.vid, ul.id, ul.label
          FROM ulist_vns uv, unnest(uv.labels) l(id), ulist_labels ul
         WHERE ul.uid =', \auth->uid, 'AND uv.uid =', \auth->uid, 'AND ul.id = l.id AND uv.vid IN', $_[0], '
         ORDER BY CASE WHEN ul.id < 10 THEN ul.id ELSE 10 END, ul.label'
    }, @_ if auth;
}

sub ulists_widget_ {
    my($v) = @_;
    elm_ 'UList.Widget', $VNWeb::ULists::Elm::WIDGET, {
        uid    => auth->uid,
        vid    => $v->{id},
        labels => $v->{on_vnlist} ? $v->{vnlist_labels} : undef,
        full   => undef,
    }, sub {
        my $img = !$v->{on_vnlist} ? 'add' :
            (reverse sort map "l$_->{id}", grep $_->{id} >= 1 && $_->{id} <= 6, $v->{vnlist_labels}->@*)[0] || 'unknown';
        img_ @_, src => config->{url_static}.'/f/list-'.$img.'.svg', class => "ulist-widget-icon liststatus_icon $img";
    } if auth && exists $v->{vnlist_labels};
}


# Returns the data structure for the elm_UListWidget API response for the given VN.
sub ulists_widget_full_data {
    my($v, $uid, $vnpage, $canvote) = @_;
    my $lst = tuwf->dbRowi('SELECT vid, vote, notes, started, finished, labels FROM ulist_vns WHERE uid =', \$uid, 'AND vid =', \$v->{id});
    my $review = tuwf->dbVali('SELECT id FROM reviews WHERE uid =', \$uid, 'AND vid =', \$v->{id});
    $canvote //= sprintf('%08d', $v->{c_released}||99999999) <= strftime '%Y%m%d', gmtime;
    +{
        uid    => $uid,
        vid    => $v->{id},
        labels => $lst->{vid} ? [ map +{ id => $_, label => '' }, $lst->{labels}->@* ] : undef,
        full   => {
            title     => $vnpage ? '' : $v->{title}[1],
            labels    => tuwf->dbAlli('SELECT id, label, private FROM ulist_labels WHERE uid =', \$uid, 'ORDER BY CASE WHEN id < 10 THEN id ELSE 10 END, label'),
            canvote   => $lst->{vote} || $canvote || 0,
            canreview => $review || ($canvote && can_edit(w => {})) || 0,
            vote      => fmtvote($lst->{vote}),
            review    => $review,
            notes     => $lst->{notes}||'',
            started   => $lst->{started}||'',
            finished  => $lst->{finished}||'',
            releases  => $vnpage ? [] : releases_by_vn($v->{id}),
            rlist     => $vnpage ? [] : tuwf->dbAlli('SELECT rid AS id, status FROM rlists WHERE uid =', \$uid, 'AND rid IN(SELECT id FROM releases_vn WHERE vid =', \$v->{id}, ')'),
        },
    };

}

1;
