package VNWeb::ULists::Lib;

use VNWeb::Prelude;
use Exporter 'import';

our @EXPORT = qw/ulists_own enrich_ulists_widget ulists_widget_/;

# Do we have "ownership" access to this users' list (i.e. can we edit and see private stuff)?
sub ulists_own {
    auth->permUsermod || (auth && auth->uid eq shift)
}


# Enrich a list of VNs with data necessary for ulist_widget_.
sub enrich_ulists_widget {
    enrich_merge id => sql('SELECT vid AS id, true AS on_vnlist FROM ulist_vns WHERE uid =', \auth->uid, 'AND vid IN'), @_ if auth;

    enrich vnlist_labels => id => vid => sub { sql '
        SELECT uvl.vid, ul.id, ul.label
          FROM ulist_vns_labels uvl
          JOIN ulist_labels ul ON ul.uid = uvl.uid AND ul.id = uvl.lbl
         WHERE uvl.uid =', \auth->uid, 'AND uvl.vid IN', $_[0], '
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
    } if auth;
}

1;
