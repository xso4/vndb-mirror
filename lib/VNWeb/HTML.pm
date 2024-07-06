package VNWeb::HTML;

use v5.36;
use utf8;
use Algorithm::Diff::XS 'sdiff', 'compact_diff';
use JSON::XS;
use TUWF ':html5_', 'uri_escape', 'html_escape', 'mkclass';
use Exporter 'import';
use POSIX 'ceil', 'floor', 'strftime';
use Carp 'croak';
use Digest::SHA;
use JSON::XS;
use VNDB::Config;
use VNDB::BBCode;
use VNDB::Skins;
use VNDB::Types;
use VNWeb::Auth;
use VNWeb::Validation;
use VNWeb::DB;
use VNDB::Func 'fmtdate', 'rdate', 'tattr';

our @EXPORT = qw/
    clearfloat_
    platform_
    debug_
    join_
    user_maybebanned_ user_ user_displayname
    rdate_
    vnlength_
    spoil_
    elm_ widget
    framework_
    revision_patrolled_ revision_
    paginate_
    sortable_
    searchbox_
    itemmsg_
    editmsg_
/;


# Ugly hack to move rendering down below the float object.
sub clearfloat_ { div_ class => 'clearfloat', '' }


# Platform icon
sub platform_ {
    abbr_ class => "icon-plat-$_[0]", title => $PLATFORM{$_[0]}, '';
}


# Throw any data structure on the page for inspection.
sub debug_ {
    return if !tuwf->debug;
    # This provides a nice JSON browser in FF, not sure how other browsers render it.
    my $data = uri_escape(JSON::XS->new->canonical->allow_nonref->encode($_[0]));
    a_ style => 'margin: 0 5px', title => 'Debug', href => 'data:application/json,'.$data, ' ⚙ ';
}


# Similar to join($sep, map $f->(), @list), but works for HTML generation functions.
#   join_ ', ', sub { a_ href => '#', $_ }, @list;
#   join_ \&br_, \&txt_, @list;
sub join_ :prototype($&@) {
    my($sep, $f, @list) = @_;
    for my $i (0..$#list) {
        ref $sep ? $sep->() : txt_ $sep if $i > 0;
        local $_ = $list[$i];
        $f->();
    }
}


sub user_maybebanned_ {
    my($obj) = shift;
    my($prefix) = shift||'user_';
    my sub f :prototype($) { $obj->{"${prefix}$_[0]"} }
    span_ title => join("\n",
        !f 'perm_board' ? "Banned from posting" : (),
        !f 'perm_edit' ? "Banned from editing" : (),
    ), '🚫' if defined f 'perm_board' && (!f 'perm_board' || !f 'perm_edit');
}


# Display a user link, the given object must have the columns as fetched using DB::sql_user().
# Args: $object, $prefix, $capital
sub user_ {
    my $obj = shift;
    my $prefix = shift||'user_';
    my $capital = shift;
    my sub f :prototype($) { $obj->{"${prefix}$_[0]"} }

    my $softdel = !defined f 'name';
    return small_ 'anonymous' if ($softdel && !auth->isMod) || !f 'id';
    my $fancy = !(auth->pref('nodistract_can') && auth->pref('nodistract_nofancy'));
    my $uniname = f 'uniname_can' && f 'uniname';
    a_ href => '/'.f('id'),
        $softdel ? (class => 'grayedout') : (),
        $fancy && $uniname ? (title => f('name'), $uniname) :
        (!$fancy && $uniname ? (title => $uniname) : (), ($capital ? f 'name' : f 'name') // f 'id');
    txt_ '⭐' if $fancy && f 'support_can' && f 'support_enabled';
    user_maybebanned_ $obj, $prefix;
}


# Similar to user_(), but just returns a string. Mainly for use in titles.
sub user_displayname {
    my $obj = shift;
    my $prefix = shift||'user_';
    my sub f :prototype($) { $obj->{"${prefix}$_[0]"} }

    return 'anonymous' if !f 'id';
    my $fancy = !(auth->pref('nodistract_can') && auth->pref('nodistract_nofancy'));
    $fancy && f 'uniname_can' && f 'uniname' ? f 'uniname' : f('name') // f 'id'
}

# Display a release date.
sub rdate_ {
    my $str = rdate $_[0];
    $_[0] > strftime('%Y%m%d', gmtime) ? b_ class => 'future', $str : txt_ $str;
}


sub vnlength_ {
    my($l) = @_;
    my $h = floor($l/60);
    my $m = $l % 60;
    txt_ "${h}h" if $h;
    span_ class => 'small', "${m}m" if $h && $m;
    txt_ "${m}m" if !$h && $m;
}


# Spoiler indication supscript (used for tags & traits)
sub spoil_ {
    sup_ title => 'Minor spoiler', 'S' if $_[0] == 1;
    sup_ title => 'Major spoiler', class => 'standout', 'S' if $_[0] == 2;
}


# Instantiate an Elm module.
# $schema can be set to the string 'raw' to encode the JSON directly, without a normalizing through a schema.
sub elm_ {
    my($mod, $schema, $data, $placeholder) = @_;
    die "Elm data without a schema" if defined $data && !defined $schema;
    tuwf->req->{js}{elm} = 1;
    push tuwf->req->{pagevars}{elm}->@*, [ $mod, $data ? ($schema eq 'raw' ? $data : $schema->analyze->coerce_for_json($data, unknown => 'remove')) : () ];
    my @arg = (id => sprintf 'elm%d', $#{ tuwf->req->{pagevars}{elm} });
    $placeholder ? $placeholder->(@arg) : div_ @arg, '';
}


# Instantiate a JS widget.
# Used as attribute to a html tag, which will then be used as parent node for the widget.
# $schema is optional, if present it is used to normalize the data.
sub widget {
    my($name, $schema, $data) = @_;
    $data = $data ? $schema->analyze->coerce_for_json($data, unknown => 'remove') : $schema;
    tuwf->req->{widget_id} //= 0;
    tuwf->req->{js}{ VNWeb::JS::widgets()->{$name} // die "No bundle found for widget '$name'" } = 1;
    my $id = ++tuwf->req->{widget_id};
    push tuwf->req->{pagevars}{widget}{$name}->@*, [ $id, $data ];
    (id => sprintf 'widget%d', $id)
}


# Generate a url to a file in gen/static/ and append a checksum.
sub _staticurl {
    my($file) = @_;
    state %urls;
    $urls{$file} //= do {
        my sub g { config->{gen_path}.'/static/'.$_[0] }
        my $min = $file =~ s/\.js/.min.js/r;
        my $fn = -e g($min) && (stat g $min)[9] >= (stat g $file)[9] ? $min : $file;
        my $c = Digest::SHA->new('sha1');
        $c->addfile(g $fn);
        sprintf '%s/%s?%s', config->{url_static}, $fn, substr $c->hexdigest(), 0, 8;
    };
}


sub _head_ {
    my $o = shift;

    my $fancy = !(auth->pref('nodistract_can') && auth->pref('nodistract_nofancy'));
    my $pubskin = $fancy && $o->{dbobj} && $o->{dbobj}{id} =~ /^u/ ? tuwf->dbRowi(
        'SELECT u.id, customcss_csum, skin FROM users u JOIN users_prefs up ON up.id = u.id WHERE pubskin_can AND pubskin_enabled AND u.id =', \$o->{dbobj}{id}
    ) : {};
    my $skin = tuwf->reqGet('skin') || $pubskin->{skin} || auth->pref('skin') || '';
    $skin = config->{skin_default} if !skins->{$skin};
    my $customcss = $pubskin->{customcss_csum} ? [ $pubskin->{id}, $pubskin->{customcss_csum} ] :
                  auth->pref('customcss_csum') ? [ auth->uid, auth->pref('customcss_csum') ] : undef;

    meta_ charset => 'utf-8';
    title_ $o->{title}.' | vndb';
    base_ href => tuwf->reqURI();
    link_ rel => 'shortcut icon', href => '/favicon.ico', type => 'image/x-icon';
    link_ rel => 'stylesheet', href => _staticurl("$skin.css"), type => 'text/css', media => 'all';
    link_ rel => 'search', type => 'application/opensearchdescription+xml', title => 'VNDB Visual Novel Search', href => tuwf->reqBaseURI().'/opensearch.xml';
    link_ rel => 'stylesheet', href => sprintf '/%s.css?%x', $customcss->[0], $customcss->[1] if $customcss;
    meta_ name => 'viewport', content => 'width=device-width, initial-scale=1.0, user-scalable=yes' if tuwf->reqGet('mobile-test');
    if($o->{feeds}) {
        link_ rel => 'alternate', type => 'application/atom+xml', href => "/feeds/announcements.atom", title => 'Site Announcements';
        link_ rel => 'alternate', type => 'application/atom+xml', href => "/feeds/changes.atom",       title => 'Recent Changes';
        link_ rel => 'alternate', type => 'application/atom+xml', href => "/feeds/posts.atom",         title => 'Recent Posts';
    }
    meta_ name => 'robots', content => 'noindex' if !$o->{index} || tuwf->reqGet('view');

    # Opengraph metadata
    if($o->{og}) {
        $o->{og}{site_name} ||= 'The Visual Novel Database';
        $o->{og}{type}      ||= 'object';
        $o->{og}{image}     ||= config->{placeholder_img};
        $o->{og}{url}       ||= tuwf->reqURI;
        $o->{og}{title}     ||= $o->{title};
        meta_ property => "og:$_", content => ($o->{og}{$_} =~ s/\n/ /gr) for sort keys $o->{og}->%*;
    }
}


sub _menu_ {
    my $o = shift;

    div_ id => 'support', sub {
        strong_ 'Support VNDB';
        p_ sub {
            a_ href => 'https://www.patreon.com/vndb', 'Patreon';
            a_ href => 'https://www.subscribestar.com/vndb', 'SubscribeStar';
        }
    } if !(auth->pref('nodistract_can') && auth->pref('nodistract_noads'));

    article_ sub {
        h2_ 'Menu';
        div_ sub {
            a_ href => '/',      'Home'; br_;
            a_ href => '/v',     'Visual novels'; br_;
            small_ '> '; a_ href => '/g', 'Tags'; br_;
            a_ href => '/r',     'Releases'; br_;
            a_ href => '/p',     'Producers'; br_;
            a_ href => '/s',     'Staff'; br_;
            a_ href => '/c',     'Characters'; br_;
            small_ '> '; a_ href => '/i', 'Traits'; br_;
            a_ href => '/u/all', 'Users'; br_;
            a_ href => '/hist',  'Recent changes'; br_;
            a_ href => '/t',     'Discussion board'; br_;
            a_ href => '/d6',    'FAQ'; br_;
            a_ href => '/v/rand','Random visual novel'; br_;
            a_ href => '/d11',   'API'; lit_ ' - ';
            a_ href => '/d14',   'Dumps'; lit_ ' - ';
            a_ href => 'https://query.vndb.org/about', 'Query';
        };
        form_ action => '/v', method => 'get', sub {
            fieldset_ sub {
                input_ type => 'text', class => 'text', id => 'sq', name => 'sq', value => $o->{search}||'', placeholder => 'search';
                input_ type => 'submit', class => 'hidden', value => 'Search';
            }
        }
    };

    article_ sub {
        my $uid = '/'.auth->uid;
        h2_ sub { user_ auth->user, 'user_', 1 };
        div_ sub {
            a_ href => "$uid/edit", 'My Profile'; txt_ '⭐' if auth->pref('nodistract_can') && !auth->pref('nodistract_nofancy'); br_;
            a_ href => "$uid/ulist?vnlist=1", 'My Visual Novel List'; br_;
            a_ href => "$uid/ulist?votes=1",'My Votes'; br_;
            a_ href => "$uid/ulist?wishlist=1", 'My Wishlist'; br_;
            a_ href => "$uid/notifies", $o->{unread_noti} ? (class => 'notifyget') : (), 'My Notifications'.($o->{unread_noti}?" ($o->{unread_noti})":''); br_;
            a_ href => "$uid/hist", 'My Recent Changes'; br_;
            a_ href => '/g/links?u='.auth->uid, 'My Tags'; br_;
            br_;
            if(VNWeb::Images::Vote::can_vote()) {
                a_ href => '/img/vote', 'Image Flagging'; br_;
            }
            if(can_edit v => {}) {
                a_ href => '/v/add', 'Add Visual Novel'; br_;
                a_ href => '/p/add', 'Add Producer'; br_;
                a_ href => '/s/new', 'Add Staff'; br_;
            }
            if(auth->isMod) {
                my $stats = tuwf->dbRowi("SELECT
                    (SELECT count(*) FROM reports WHERE status = 'new') as new,
                    (SELECT count(*) FROM reports WHERE status = 'new' AND date > (SELECT last_reports FROM users_prefs WHERE id =", \auth->uid, ")) AS unseen,
                    (SELECT count(*) FROM reports WHERE lastmod > (SELECT last_reports FROM users_prefs WHERE id =", \auth->uid, ")) AS upd
                ");
                a_ $stats->{unseen} ? (class => 'standout') : (), href => '/report/list?status=new', sprintf 'Reports %d/%d', $stats->{unseen}, $stats->{new};
                small_ ' | ';
                a_ href => '/report/list?s=lastmod', sprintf '%d upd', $stats->{upd};
                br_;
                a_ global_settings->{lockdown_edit} || global_settings->{lockdown_board} || global_settings->{lockdown_registration} ? (class => 'standout') : (), href => '/lockdown', 'Lockdown';
                br_;
            }
            br_;
            form_ action => "$uid/logout", method => 'post', sub {
                input_ type => 'hidden', class => 'hidden', name => 'csrf', value => auth->csrftoken;
                input_ type => 'submit', class => 'logout', value => 'Logout';
            };
        }
    } if auth;

    article_ sub {
        h2_ 'User menu';
        div_ sub {
            my $ref = uri_escape(tuwf->reqGet('ref') || tuwf->reqPath().tuwf->reqQuery());
            a_ href => "/u/login?ref=$ref", 'Login'; br_;
            a_ href => '/u/register', 'Register'; br_;
        }
    } if !auth && !config->{read_only};

    article_ sub {
        h2_ 'Database Statistics';
        div_ sub {
            dl_ sub {
                my %stats = map +($_->{section}, $_->{count}), tuwf->dbAll('SELECT * FROM stats_cache')->@*;
                dt_ 'Visual Novels'; dd_ $stats{vn};
                dt_ sub { small_ '> '; lit_ 'Tags' };
                                     dd_ $stats{tags};
                dt_ 'Releases';      dd_ $stats{releases};
                dt_ 'Producers';     dd_ $stats{producers};
                dt_ 'Staff';         dd_ $stats{staff};
                dt_ 'Characters';    dd_ $stats{chars};
                dt_ sub { small_ '> '; lit_ 'Traits' };
                                     dd_ $stats{traits};
            };
            clearfloat_;
        }
    };
}


sub _footer_ {
    my($o) = @_;
    my $q = tuwf->dbRow('SELECT vid, quote FROM quotes WHERE rand <= (SELECT random()) ORDER BY rand DESC LIMIT 1');
    span_ sub {
        lit_ '"';
        a_ href => "/$q->{vid}", $q->{quote};
        txt_ '" ';
        br_;
    } if $q && $q->{vid};
    a_ href => config->{source_url}, config->{version};
    txt_ ' | ';
    a_ href => '/d17', 'privacy & content policy';
    txt_ ' | ';
    a_ href => '/d7', 'about us';
    lit_ ' | ';
    a_ href => '/.env', 'security';
    lit_ ' | ';
    a_ href => '/ads.txt', 'advertising';
    lit_ ' | ';
    a_ href => sprintf('mailto:%s', config->{admin_email}), config->{admin_email};

    if(tuwf->debug) {
        lit_ ' | ';
        debug_ tuwf->req->{pagevars};
        br_;
        tuwf->dbCommit; # Hack to measure the commit time

        my(@sql_r, @sql_i) = ();
        for (tuwf->{_TUWF}{DB}{queries}->@*) {
            my($sql, $params, $time) = @$_;
            my @params = sort { $a =~ /^[0-9]+$/ && $b =~ /^[0-9]+$/ ? $a <=> $b : $a cmp $b } keys %$params;
            my $prefix = sprintf "  [%6.2fms] ", $time*1000;
            push @sql_r, sprintf "%s%s | %s", $prefix, $sql, join ', ', map "$_:".DBI::neat($params->{$_}), @params;
            my $i=1;
            push @sql_i, $prefix.($sql =~ s/\?/tuwf->dbh->quote($params->{$i++})/egr);
        }
        my $sql_r = join "\n", @sql_r;
        my $sql_i = join "\n", @sql_i;
        my $modules = join "\n", sort keys %INC;
        details_ sub {
            summary_ 'debug info';
            pre_ style => 'text-align: left; color: black; background: white',
                "SQL (with placeholders):\n$sql_r\n\nSQL (interpolated, possibly buggy):\n$sql_i\n\nMODULES:\n$modules";
        };
    }
}


sub _maintabs_subscribe_ {
    my($o, $id) = @_;
    return if !auth || $id !~ /^[twvrpcsdig]/;

    my $noti =
        $id =~ /^t/ ? tuwf->dbVali('SELECT SUM(x) FROM (
                 SELECT 1 FROM threads_posts tp, users u WHERE u.id =', \auth->uid, 'AND tp.uid =', \auth->uid, 'AND tp.tid =', \$id, ' AND u.notify_post
           UNION SELECT 1+1 FROM threads_boards tb WHERE tb.tid =', \$id, 'AND tb.type = \'u\' AND tb.iid =', \auth->uid, '
           ) x(x)')

      : $id =~ /^w/ ? (auth->pref('notify_post') || auth->pref('notify_comment')) && tuwf->dbVali('SELECT SUM(x) FROM (
                 SELECT 1 FROM reviews_posts wp, users u WHERE u.id =', \auth->uid, 'AND wp.uid =', \auth->uid, 'AND wp.id =', \$id, 'AND u.notify_post
           UNION SELECT 1+1 FROM reviews w, users u WHERE u.id =', \auth->uid, 'AND w.uid =', \auth->uid, 'AND w.id =', \$id, 'AND u.notify_comment
           ) x(x)')

      : $id =~ /^[vrpcsdgi]/ && auth->pref('notify_dbedit') && tuwf->dbVali('
           SELECT 1 FROM changes WHERE itemid =', \$id, 'AND requester =', \auth->uid);

    my $sub = tuwf->dbRowi('SELECT subnum, subreview, subapply FROM notification_subs WHERE uid =', \auth->uid, 'AND iid =', \$id);

    li_ widget(Subscribe => $VNWeb::User::Notifications::SUB, {
        id        => $id,
        noti      => $noti||0,
        subnum    => $sub->{subnum},
        subreview => $sub->{subreview}||0,
        subapply  => $sub->{subapply}||0,
    }), class => 'maintabs-dd subscribe', sub {
        a_ href => '#', class => ($noti && (!defined $sub->{subnum} || $sub->{subnum})) || $sub->{subnum} || $sub->{subreview} || $sub->{subapply} ? 'active' : 'inactive', '🔔';
    };
}


sub _maintabs_ {
    my $opt = shift;
    my($o, $sel) = @{$opt}{qw/dbobj tab/};

    my $id = $o ? $o->{id} : '';
    my($t) = $o ? $id =~ /^(.)/ : '';

    my sub t {
        my($tabname, $url, $text) = @_;
        li_ mkclass(tabselected => $tabname eq ($sel||'')), sub {
            a_ href => $url, $text;
        };
    };

    nav_ sub {
        label_ for => 'mainmenu', sub {
            lit_ 'Menu';
            b_ " ($opt->{unread_noti})" if $opt->{unread_noti};
        };
        menu_ sub {
            t '' => "/$id", $id if $o && $t ne 't';

            t rg => "/$id/rg", 'relations'
                if $t =~ /[vp]/ && tuwf->dbVali('SELECT 1 FROM', $t eq 'v' ? 'vn_relations' : 'producers_relations', 'WHERE id =', \$o->{id}, 'LIMIT 1');

            t releases => "/$id/releases", 'releases' if $t eq 'v';
            t edit => "/$id/edit", 'edit' if $o && $t ne 't' && can_edit $t, $o;
            t copy => "/$id/copy", 'copy' if $t =~ /[rc]/ && can_edit $t, $o;
            t tagmod => "/$id/tagmod", 'modify tags' if $t eq 'v' && auth->permTag && !$o->{entry_hidden};

            do {
                t admin => "/$id/admin", 'admin' if auth->isMod;
                t list  => "/$id/ulist?vnlist=1", 'list';
                t votes => "/$id/ulist?votes=1", 'votes';
                t wish  => "/$id/ulist?wishlist=1", 'wishlist';
                t reviews => "/w?u=$o->{id}", 'reviews';
                t posts => "/$id/posts", 'posts';
            } if $t eq 'u';

            if($t =~ /[uvp]/) {
                my $cnt = tuwf->dbVali(q{
                    SELECT COUNT(*)
                    FROM threads_boards tb
                    JOIN threads t ON t.id = tb.tid
                    WHERE tb.type =}, \$t, 'AND tb.iid =', \$o->{id}, ' AND', VNWeb::Discussions::Lib::sql_visible_threads());
                t disc => "/t/$id", "discussions ($cnt)";
            };

            t hist => "/$id/hist", 'history' if $t =~ /[uvrpcsdgi]/;
            _maintabs_subscribe_ $o, $id;
        }
    }
}


# Attempt to figure out the board id from a database entry
sub _board_id {
    my($obj) = @_;
    $obj->{id} =~ /^[vp]/ ? $obj->{id} :
       $obj->{id} =~ /^r/ && $obj->{vn}  && $obj->{vn}->@*  ? $obj->{vn}[0]{vid} :
       $obj->{id} =~ /^c/ && $obj->{vns} && $obj->{vns}->@* ? $obj->{vns}[0]{vid} : 'db';
}


# Returns 1 if the page contents should be hidden.
sub _hidden_msg_ {
    my $o = shift;

    die "Can't use hiddenmsg on an object that is missing 'entry_hidden' or 'entry_locked'"
        if !exists $o->{dbobj}{entry_hidden} || !exists $o->{dbobj}{entry_locked};

    return 0 if !$o->{dbobj}{entry_hidden};

    # Awaiting moderation
    if(!$o->{dbobj}{entry_locked}) {
        article_ sub {
            h1_ $o->{title};
            div_ class => 'notice', sub {
                h2_ 'Waiting for approval';
                p_ 'This entry is waiting for a moderator to approve it.';
            }
        };
        return 0;
    }

    # Deleted.
    my $msg = tuwf->dbRowi(
        'SELECT comments, rev
           FROM changes
          WHERE itemid =', \$o->{dbobj}{id},
         'ORDER BY id DESC LIMIT 1'
    );
    article_ sub {
        h1_ $o->{title};
        div_ class => 'warning', sub {
            h2_ 'Item deleted';
            p_ sub {
                if($o->{dbobj}{id} =~ /^r/ && $o->{dbobj}{vn}) {
                    txt_ 'This was a release entry for ';
                    join_ ',', sub { a_ href => "/$_->{vid}", tattr $_ }, $o->{dbobj}{vn}->@*;
                    txt_ '.';
                    br_;
                }
                txt_ 'This item has been deleted from the database. You may file a request on the ';
                a_ href => '/t/'._board_id($o->{dbobj}), "discussion board";
                txt_ ' if you believe that this entry should be restored.';
                if($msg->{rev} > 1) {
                    br_;
                    br_;
                    lit_ bb_format $msg->{comments};
                }
            }
        }
    };
    $o->{dbobj}{id} !~ /^[gi]/ && !auth->permDbmod # tags/traits are still visible, dbmods can still see all pages
}


# Options:
#   title      => $title
#   index      => 1/0, default 0
#   feeds      => 1/0
#   js         => 1/0, set to 1 to ensure 'basic.js' is included on the page even if no elm_() modules or JS widgets are loaded.
#   search     => $query
#   og         => { opengraph metadata }
#   dbobj      => Database entry object (used for the main tabs & hidden message)
#                 Recognized object fields: id, entry_hidden, entry_locked
#   tab        => Current tab, or empty for the main tab
#   hiddenmsg  => 1/0, if true and dbobj is 'hidden', a message will be displayed
#                      and the content function may not be called.
#   sub { content }
sub framework_ {
    my $cont = pop;
    my %o = @_;
    tuwf->req->{pagevars} = { tuwf->req->{pagevars} ? tuwf->req->{pagevars}->%* : (), $o{pagevars}->%* } if $o{pagevars};
    $o{unread_noti} = auth && tuwf->dbVali('SELECT count(*) FROM notifications WHERE uid =', \auth->uid, 'AND read IS NULL');

    lit_ "<!--\n"
        ."  This HTML is an unreadable auto-generated mess, sorry for that.\n"
        ."  The full source code of this site can be found at ".config->{source_url}."\n"
        .(tuwf->req->{trace_loc}[0] ?
         "  This particular page was generated by ".config->{source_url}."/src/branch/master/lib/".(tuwf->req->{trace_loc}[0] =~ s/::/\//rg).".pm\n" : '')
        ."-->\n";
    html_ lang => 'en', sub {
        head_ sub { _head_ \%o };
        body_ sub {
            input_ type => 'checkbox', class => 'hidden', id => 'mainmenu', name => 'mainmenu';
            header_ sub {
                div_ id => 'bgright', ' ';
                div_ id => 'readonlymode', config->{read_only} eq 1 ? 'The site is in read-only mode, account functionality is currently disabled.' : config->{read_only} if config->{read_only};
                h1_ sub { a_ href => '/', 'the visual novel database' };
                _maintabs_ \%o;
            };
            nav_ sub { _menu_ \%o };
            main_ sub {
                $cont->() unless $o{hiddenmsg} && _hidden_msg_ \%o;
                footer_ sub { _footer_ \%o };
            };

            # 'basic' bundle is always included if there's any JS at all
            tuwf->req->{js}{basic} = 1 if tuwf->req->{js}{elm} || tuwf->req->{pagevars}{widget} || $o{js};
            # 'dbmod' value is used by various widgets
            tuwf->req->{pagevars}{dbmod} = 1 if tuwf->req->{pagevars}{widget} && auth->permDbmod;

            script_ type => 'application/json', id => 'pagevars', sub {
                # Escaping rules for a JSON <script> context are kinda weird, but more efficient than regular xml_escape().
                lit_(JSON::XS->new->canonical->encode(tuwf->req->{pagevars}) =~ s{</}{<\\/}rg =~ s/<!--/<\\u0021--/rg);
            } if keys tuwf->req->{pagevars}->%*;

            script_ defer => 'defer', src => _staticurl("$_.js"), '' for grep tuwf->req->{js}{$_}, qw/elm basic user contrib graph/;
        }
    }
}



sub revision_patrolled_ {
    my($r) = @_;
    return span_ class => 'done', title =>
        "Patrolled by ".join(', ', map user_displayname($_), $r->{rev_patrolled}->@*), '✓'
        if $r->{rev_patrolled}->@*;
    return lit_ '✓' if $r->{rev_dbmod};
    small_ '#';
}


sub _revision_header_ {
    my($obj) = @_;
    strong_ "Revision $obj->{chrev}";
    debug_ $obj;
    if(auth) {
        lit_ ' (';
        a_ href => "/$obj->{id}.$obj->{chrev}/edit", $obj->{chrev} == $obj->{maxrev} ? 'edit' : 'revert to';
        if($obj->{rev_user_id}) {
            lit_ ' / ';
            a_ href => "/t/$obj->{rev_user_id}/new?title=Regarding%20$obj->{id}.$obj->{chrev}", 'msg user';
        }
        if(auth->permDbmod) {
            lit_ ' / ';
            revision_patrolled_ $obj;
            if($obj->{rev_user_id} && $obj->{rev_user_id} eq auth->uid) {}
            elsif(grep $_->{user_id} eq auth->uid, $obj->{rev_patrolled}->@*) {
                a_ href => "?unpatrolled=$obj->{chid}", 'unmark';
            } else {
                a_ href => "?patrolled=$obj->{chid}", 'mark patrolled';
            }
        }
        lit_ ')';
    }
    br_;
    lit_ 'By ';
    user_ $obj, 'rev_user_';
    lit_ ' on ';
    txt_ fmtdate $obj->{rev_added}, 'full';
}


sub _revision_fmtval_ {
    my($opt, $val, $obj) = @_;
    return em_ '[empty]' if !defined $val || (defined $opt->{empty} ? $val eq $opt->{empty} : !length $val);
    return lit_ html_escape $val if !$opt->{fmt};
    if(ref $opt->{fmt} eq 'HASH') {
        my $h = $opt->{fmt}{$val};
        return txt_ ref $h eq 'HASH' ? $h->{txt} : $h || '[unknown]';
    }
    return txt_ $val ? 'True' : 'False' if $opt->{fmt} eq 'bool';
    local $_ = $val;
    $opt->{fmt}->($obj);
}


sub _revision_fmtcol_ {
    my($opt, $i, $l, $obj) = @_;

    my $ctx = 100; # Number of characters of context in textual diffs
    my sub sep_ { b_ '<...>' }; # Context separator

    td_ class => 'tcval', sub {
        em_ '[empty]' if @$l > 1 && (($i == 1 && !grep $_->[0] ne '+', @$l) || ($i == 2 && !grep $_->[0] ne '-', @$l));
        join_ $opt->{join}||\&br_, sub {
            my($ch, $old, $new, $diff) = @$_;
            my $val = $_->[$i];

            if($diff) {
                my $lastchunk = int (($#$diff-2)/2);
                for my $n (0..$lastchunk) {
                    utf8::decode(my $a = join '', @{$old}[ $diff->[$n*2]   .. $diff->[$n*2+2]-1 ]);
                    utf8::decode(my $b = join '', @{$new}[ $diff->[$n*2+1] .. $diff->[$n*2+3]-1 ]);

                    # Difference, highlight and display in full
                    if($n % 2) {
                        span_ class => $i == 1 ? 'diff_del' : 'diff_add', sub { lit_ html_escape $i == 1 ? $a : $b };
                    # Short context, display in full
                    } elsif(length $a < $ctx*3) {
                        lit_ html_escape $a;
                    # Longer context, abbreviate
                    } elsif($n == 0) {
                        sep_; br_; lit_ html_escape substr $a, -$ctx;
                    } elsif($n == $lastchunk) {
                        lit_ html_escape substr $a, 0, $ctx; br_; sep_;
                    } else {
                        lit_ html_escape substr $a, 0, $ctx;
                        br_; br_; sep_; br_; br_;
                        lit_ html_escape substr $a, -$ctx;
                    }
                }

            } elsif(@$l > 1 && $i == 2 && ($ch eq '+' || $ch eq 'c')) {
                span_ class => 'diff_add', sub { _revision_fmtval_ $opt, $val, $obj };
            } elsif(@$l > 1 && $i == 1 && ($ch eq '-' || $ch eq 'c')) {
                span_ class => 'diff_del', sub { _revision_fmtval_ $opt, $val, $obj };
            } elsif($ch eq 'u' || @$l == 1) {
                _revision_fmtval_ $opt, $val, $obj;
            }
        }, @$l;
    };
}


# Recursively stringify scalars. This is generally a no-op, except when
# serializing the data structure to JSON this will cause all numbers to be
# formatted as strings.  Not very useful for data exchange, but this allows for
# creating proper canonicalized JSON where equivalent data structures serialize
# to the same string. (TODO: Might as well write a function that hashes
# recursive data structures and use that for comparison - a little bit more
# work but less magical)
sub _stringify_scalars_rec {
    defined($_[0]) && !ref $_[0] ? "$_[0]" :
            ref $_[0] eq 'HASH'  ? map _stringify_scalars_rec($_), values $_[0]->%* :
            ref $_[0] eq 'ARRAY' ? map _stringify_scalars_rec($_), $_[0]->@* : undef;
}

sub _revision_diff_ {
    my($old, $new, $field, $name, %opt) = @_;

    # First do a diff on the raw field elements.
    # (if the field is a scalar, it's considered a single element and the diff just tests equality)
    my @old = ref $old->{$field} eq 'ARRAY' ? $old->{$field}->@* : ($old->{$field});
    my @new = ref $new->{$field} eq 'ARRAY' ? $new->{$field}->@* : ($new->{$field});

    @old = map $opt{txt}->(), @old if $opt{txt};
    @new = map $opt{txt}->(), @new if $opt{txt};

    my $JS = JSON::XS->new->utf8->canonical->allow_nonref;
    my $l = sdiff \@old, \@new, sub { _stringify_scalars_rec($_[0]); $JS->encode($_[0]) };
    return if !grep $_->[0] ne 'u', @$l;

    # Now check if we should do a textual diff on the changed items.
    for my $item (@$l) {
        last if $opt{fmt};
        next if $item->[0] ne 'c' || ref $item->[1] || ref $item->[2];
        next if !defined $item->[1] || !defined $item->[2];
        next if length $item->[1] < 10 || length $item->[2] < 10;

        # Do a word-based diff if this is a large chunk of text, otherwise character-based.
        my $split = length $item->[1] > 1024 ? qr/([ ,\n]+)/ : qr//;
        $item->[1] = [map { utf8::encode($_); $_ } split $split, $item->[1]];
        $item->[2] = [map { utf8::encode($_); $_ } split $split, $item->[2]];
        $item->[3] = compact_diff $item->[1], $item->[2];
    }

    tr_ sub {
        td_ $name;
        _revision_fmtcol_ \%opt, 1, $l, $old;
        _revision_fmtcol_ \%opt, 2, $l, $new;
    }
}


sub _revision_cmp_ {
    my($old, $new, @fields) = @_;

    local $old->{_entry_state} = ($old->{hidden}?2:0) + ($old->{locked}?1:0);
    local $new->{_entry_state} = ($new->{hidden}?2:0) + ($new->{locked}?1:0);

    table_ class => 'stripe', sub {
        thead_ sub {
            tr_ sub {
                td_ ' ';
                td_ sub { _revision_header_ $old };
                td_ sub { _revision_header_ $new };
            };
            tr_ sub {
                td_ ' ';
                td_ colspan => 2, sub {
                    strong_ "Edit summary for revision $new->{chrev}";
                    br_;
                    br_;
                    lit_ bb_format $new->{rev_comments}||'-';
                };
            };
        };
        _revision_diff_ $old, $new, @$_ for(
            [ _entry_state => 'State', fmt => {0 => 'Normal', 1 => 'Locked', 2 => 'Awaiting approval', 3 => 'Deleted'} ],
            @fields,
        );
    };
}


# Revision info box.
#
# Arguments: $object, \&enrich_for_diff, @fields
#
# The given $object is assumed to originate from VNWeb::DB::db_entry() and
# should have the 'id', 'hidden', 'locked', 'chrev' and 'maxrev' fields in
# addition to those specified in @fields.
#
# \&enrich_for_diff is a subroutine that is given an earlier revision returned
# by db_entry() and should enrich this object with information necessary for
# diffing. $object is assumed to have already been enriched in this way (it is
# assumed that a page will need to fetch and enrich such an $object for its own
# display purposes anyway).
#
# @fields is a list of arrayrefs with the following form:
#
#   [ field_name, display_name, %options ]
#
# Options:
#   fmt     => 'bool'||\%HASH||sub {$_}  - Formatting function for individual values.
#                 If not given, the field is rendered as plain text and changes are highlighted with a diff.
#                 \%HASH -> Look the field up in the hash table (values should be string or {txt=>string}.
#                 sub($value) {$_} -> Custom formatting function, should output TUWF::XML data HTML.
#   txt     => sub{$_} - Text formatting function for individual values.
#                 Alternative to 'fmt' above; the returned value is treated as a text field with diffing support.
#   join    => sub{}  - HTML to join multi-value fields, defaults to \&br_.
#   empty   => str    - What value should be considered "empty", e.g. (empty => 0) for integer fields.
#                 undef or empty string are always considered empty values.
sub revision_ {
    my($new, $enrich, @fields) = @_;

    my $old = $new->{chrev} == 1 ? undef : db_entry $new->{id}, $new->{chrev} - 1;
    $enrich->($old) if $old;

    if(auth->permDbmod) {
        my $f = tuwf->validate(get =>
            patrolled   => { default => 0, uint => 1 },
            unpatrolled => { default => 0, uint => 1 },
        )->data;
        tuwf->dbExeci('INSERT INTO changes_patrolled', {id => $f->{patrolled}, uid => auth->uid}, 'ON CONFLICT (id,uid) DO NOTHING') if $f->{patrolled};
        tuwf->dbExeci('DELETE FROM changes_patrolled WHERE', {id => $f->{unpatrolled}, uid => auth->uid}) if $f->{unpatrolled};
    }

    enrich_merge chid => sql(
        'SELECT c.id AS chid, c.comments as rev_comments,', sql_totime('c.added'), 'as rev_added, ', sql_user('u', 'rev_user_'), ', u.perm_dbmod AS rev_dbmod
           FROM changes c LEFT JOIN users u ON u.id = c.requester
          WHERE c.id IN'),
        $new, $old||();

    enrich rev_patrolled => chid => id =>
        sql('SELECT c.id,', sql_user(), 'FROM changes_patrolled c JOIN users u ON u.id = c.uid WHERE c.id IN'),
        $new, $old||()
        if auth->permDbmod;

    article_ class => 'revision', sub {
        h1_ "Revision $new->{chrev}";

        a_ class => 'prev', href => sprintf('/%s.%d', $new->{id}, $new->{chrev}-1), '<- earlier revision' if $new->{chrev} > 1;
        a_ class => 'next', href => sprintf('/%s.%d', $new->{id}, $new->{chrev}+1), 'later revision ->' if $new->{chrev} < $new->{maxrev};
        p_ class => 'center', sub { a_ href => "/$new->{id}", $new->{id} };

        div_ class => 'rev', sub {
            _revision_header_ $new;
            br_;
            strong_ 'Edit summary';
            br_; br_;
            lit_ bb_format $new->{rev_comments}||'-';
        } if !$old;

        _revision_cmp_ $old, $new, @fields if $old;
    };
}


# Creates next/previous buttons (tabs), if needed.
# Arguments:
#   url generator (code reference that takes ('p', $pagenumber) as arguments with $_=$pagenumber and returns a url for that page).
#   current page number (1..n),
#   nextpage (0/1 or, if the full count is known: [$total, $perpage]),
#   alignment (t/b)
#   tableopts obj
sub paginate_ {
    my($url, $p, $np, $al, $tbl) = @_;
    my($cnt, $pp) = ref($np) ? @$np : ($p+$np, 1);
    return if !$tbl && $p == 1 && $cnt <= $pp;

    my sub tab_ {
        my($page, $label) = @_;
        li_ sub {
            local $_ = $page;
            my $u = $url->(p => $page);
            a_ href => $u,
                class => $page == $p ? 'highlightselected' : undef,
                rel => $label && $label =~ /next/ ? 'next' : $label && $label =~ /prev/ ? 'prev' : undef,
                $label//$page;
        }
    }
    my sub ell_ {
        li_ mkclass(ellipsis => 1), '⋯';
    }

    nav_ class => $al eq 't' ? undef : 'bottom', sub {
        my $n = ceil($cnt/$pp);
        my $l = $n-$p+1;
        menu_ class => 'browsetabs', sub {
            $p > 1 and tab_ $p-1, '‹ previous';
            if(ref $np) {
                $p > 3 and tab_ 1;
                $p > 4 and ell_;
                $_ > 0 and $_ <= $n and tab_ $_ for ($p-2..$p+2);
                $l > 4 and ell_;
                $l > 3 and tab_ $n;
            }
            $l > 1 and tab_ $p+1, 'next ›';
        };

        $tbl->widget_($url) if $tbl;
    }
}


# Generate sort buttons for a table header. This function assumes that sorting
# options are given either as a TableOpts parameter in 's' or as two query
# parameters: 's' for the $column_name to sort on and 'o' for order ('a'/'d').
# Options: $column_title, $column_name, $opt, $url
# Where $url is a function that is given ('p', undef, 's', $column_name, 'o', $order) and returns a URL.
sub sortable_ {
    my($name, $opt, $url, $space) = @_;
    txt_ ' ' if $space || !defined $space;
    if(ref $opt->{s}) {
        my $o = $opt->{s}->sorted($name);
        $o eq 'a' ? txt_ '▴' : a_ href => $url->(p => undef, s => $opt->{s}->sort_param($name, 'a')), '▴';
        $o eq 'd' ? txt_ '▾' : a_ href => $url->(p => undef, s => $opt->{s}->sort_param($name, 'd')), '▾';
    } else {
        $opt->{s} eq $name && $opt->{o} eq 'a' ? txt_ '▴' : a_ href => $url->(p => undef, s => $name, o => 'a'), '▴';
        $opt->{s} eq $name && $opt->{o} eq 'd' ? txt_ '▾' : a_ href => $url->(p => undef, s => $name, o => 'd'), '▾';
    }
}


sub searchbox_ {
      my($sel, $q) = @_;
      tuwf->req->{js}{basic} = 1;

      # Only fetch counts for queries that can use the trigram index
      # (This length requirement is not ideal for Kanji, but pg_trgm doesn't
      # discriminate between scripts)
      my %counts = $q && (grep length($_)>=3, $q->words->@*) ?
          map +($_->{type}, $_->{cnt}), tuwf->dbAlli('
              SELECT vndbid_type(id) AS type, count(*) AS cnt
                FROM (
                  SELECT DISTINCT id
                    FROM search_cache sc
                   WHERE', sql_and($q->where()), "
                     AND NOT (id BETWEEN '${sel}1' AND vndbid_max('$sel'))
                ) x
               GROUP BY vndbid_type(id)
          ")->@* : ();

      my sub lnk_ {
          my($type, $label) = @_;
          a_ href => "/$type", $sel eq $type ? (class => 'sel') : (), sub {
              txt_ $label;
              sup_ class => 'standout', $counts{$type} if $counts{$type};
          };
      }

      fieldset_ class => 'search', sub {
          p_ id => 'searchtabs', sub {
              lnk_ v => 'Visual novels';
              lnk_ r => 'Releases';
              lnk_ p => 'Producers';
              lnk_ s => 'Staff';
              lnk_ c => 'Characters';
              lnk_ g => 'Tags';
              lnk_ i => 'Traits';
          };
          input_ type => 'text', name => 'q', id => 'q', class => 'text', value => "$q";
          input_ type => 'submit', class => 'submit', name => 'sb', value => 'Search!';
      };
}


# Generate a message to display on an entry page to report the entry and to indicate it has been locked or the user can't edit it.
sub itemmsg_ {
    my($obj) = @_;
    p_ class => 'itemmsg', sub {
        if($obj->{id} !~ /^[dwu]/) {
            if($obj->{entry_locked} && !$obj->{entry_hidden}) {
                txt_ 'Locked for editing. ';
            } elsif(auth && !can_edit(($obj->{id} =~ /^(.)/), $obj)) {
                txt_ 'You can not edit this page. ';
            }
        }
        a_ href => "/report/$obj->{id}", $obj->{id} =~ /^u/ ? 'report user' : 'Report an issue on this page.';
    } if !config->{read_only};
}


# Generate the initial box when adding or editing a database entry, with a
# friendly message pointing to the guidelines and stuff.
# Args: $type ('v','r', etc), $obj (from db_entry(), or undef for new page), $page_title, $is_this_a_copy?
sub editmsg_ {
    my($type, $obj, $title, $copy) = @_;
    my $typename   = {v => 'visual novel', r => 'release', p => 'producer', c => 'character', s => 'person'}->{$type};
    my $guidelines = {v => 2,              r => 3,         p => 4,          c => 12,          s => 16      }->{$type};
    croak "Unknown type: $type" if !$typename;

    article_ sub {
        h1_ sub {
            txt_ $title;
            debug_ $obj if $obj;
        };
        if($obj && config->{data_requests}{$obj->{id}}) {
            div_ class => 'warning', sub {
                h2_ '## DATA REMOVAL/CHANGE REQUEST ##';
                br_;
                p_ sub { lit_ config->{data_requests}{$obj->{id}} };
                br_;
                h2_ '## DATA REMOVAL/CHANGE REQUEST ##';
            };
        }
        if($copy) {
            div_ class => 'warning', sub {
                h2_ "You're not editing an entry!";
                p_ sub {;
                    txt_ "You're about to insert a new entry into the database with information based on ";
                    a_ href => "/$obj->{id}", $obj->{id};
                    txt_ '.';
                    br_;
                    txt_ "Hit the 'edit' tab on the right-top if you intended to edit the entry instead of creating a new one.";
                }
            }
        }
        if($obj && $obj->{maxrev} != $obj->{chrev}) {
            div_ class => 'warning', sub {
                h2_ 'Reverting';
                p_ "You are editing an old revision of this $typename. If you save it, all changes made after this revision will be reverted!";
            }
        }
        div_ class => 'notice', sub {
            h2_ 'Before editing:';
            ul_ sub {
                li_ sub {
                    txt_ 'Read the ';
                    a_ href=> "/d$guidelines", 'guidelines';
                    txt_ '!';
                };
                if($obj) {
                    li_ sub {
                        txt_ 'Check for any existing discussions on the ';
                        a_ href => '/t/'._board_id($obj), 'discussion board';
                    };
                } elsif($type ne 'r') {
                    li_ sub {
                        a_ href => "/$type/all", 'Search the database';
                        txt_ " to see if we already have information about this $typename.";
                    }
                }
                li_ 'Fields marked with (*) may cause other fields to become (un)available depending on the selection.' if $type eq 'r';
            }
        };
    };
    VNWeb::Misc::History::tablebox_($obj->{id}, {p=>1}, results => 10, nopage => 1) if $obj && !$copy;
}

1;
