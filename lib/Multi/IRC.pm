
#
#  Multi::IRC  -  HMX-12 Multi, the IRC bot
#

package Multi::IRC;

use strict;
use warnings;
use Multi::Core;
use AnyEvent::IRC::Client;
use AnyEvent::IRC::Util 'prefix_nick';
use VNDB::Func 'normalize_query';
use VNDB::Config;
use TUWF::Misc 'uri_escape';
use POSIX 'strftime';
use Encode 'decode_utf8', 'encode_utf8';


# long subquery used in several places
my $GETBOARDS = q{array_to_string(array(
      SELECT tb.type||COALESCE(':'||COALESCE(u.username, v.title, p.name), '')
      FROM threads_boards tb
      LEFT JOIN vn v ON tb.type = 'v' AND v.id = tb.iid
      LEFT JOIN producers p ON tb.type = 'p' AND p.id = tb.iid
      LEFT JOIN users u ON tb.type = 'u' AND u.id = tb.iid
      WHERE tb.tid = t.id
      ORDER BY tb.type, tb.iid
    ), ', ') AS boards};

my $LIGHT_BLUE = "\x0312";
my $RED = "\x0304";
my $BOLD = "\x02";
my $NORMAL = "\x0f";
my $LIGHT_GREY = "\x0315";


my $irc;
my $connecttimer;
my %lastnotify;


my %O = (
  nick => 'Multi_test'.$$,
  server => 'irc.synirc.net',
  port => 6667,
  ircname => 'VNDB.org Multi',
  channels => [ '#vndb' ],
  masters => [ 'Yorhel!~Ayo@your.hell' ],
  throt_sameid => [ 60, 0 ], # spamming the same vndbid
  throt_vndbid => [ 5,  5 ], # spamming vndbids in general
  throt_cmd    => [ 10, 2 ], # handling commands from a single user
  nick_check_interval => 600,
);


sub run {
  shift;
  %O = (%O, @_);
  $irc = AnyEvent::IRC::Client->new;

  set_cbs();
  set_logger();
  set_notify();
  ircconnect();

  # Watchdog to see if we still have our nick.
  push_watcher schedule 0, $O{nick_check_interval}, sub {
    return if !$irc->is_connected() || $irc->is_my_nick($O{nick});
    $irc->send_msg(PRIVMSG => NickServ => "GHOST $O{nick} $O{pass}");
    my $t; $t = AE::timer 5, 0, sub {
      undef $t;
      return if !$irc->is_connected() || $irc->is_my_nick($O{nick});
      AE::log warn => 'Lost our nick, trying to reclaim.';
      $irc->send_msg(NICK => $O{nick});
      $t = AE::timer 5, 0, sub {
        undef $t;
        return if !$irc->is_connected() || !$irc->is_my_nick($O{nick});
        $irc->send_msg(PRIVMSG => NickServ => "IDENTIFY $O{pass}");
      };
    };
  } if $O{pass};
}


sub unload {
  # TODO: Wait until we've nicely disconnected?
  $irc->disconnect('Closing...');
  undef $connecttimer;
  undef $irc;
}


sub ircconnect {
  $irc->connect($O{server}, $O{port}, { nick => $O{nick}, user => 'u1', real => $O{ircname} });
}


sub reconnect {
  $connecttimer = AE::timer 60, 0, sub {
    ircconnect();
    undef $connecttimer;
  };
}


sub set_cbs {
  $irc->reg_cb(connect => sub {
    return if !$_[1];
    AE::log warn => "IRC connection error: $_[1]";
    reconnect();
  });
  $irc->reg_cb(registered => sub {
    AE::log info => 'Connected to IRC';
    $irc->enable_ping(60);
    $irc->send_msg(PRIVMSG => NickServ => "IDENTIFY $O{pass}") if $O{pass} && $irc->is_my_nick($O{nick});
    $irc->send_msg(JOIN => join ',', @{$O{channels}});
  });

  $irc->reg_cb(disconnect => sub {
    AE::log info => 'Disconnected from IRC';
    reconnect();
  });

  $irc->ctcp_auto_reply(VERSION => ['VERSION', join ':', $O{ircname}, config->{version}, 'AnyEvent']);
  $irc->ctcp_auto_reply(USERINFO => ['USERINFO', ":$O{ircname}"]);

  $irc->reg_cb(publicmsg => sub { my @a = (prefix_nick($_[2]->{prefix}), $_[1], $_[2]->{params}[1]); command(@a) || vndbid(@a); });
  $irc->reg_cb(privatemsg => sub { my $n = prefix_nick($_[2]->{prefix}); command($n, $n, $_[2]->{params}[1]) });
  $irc->reg_cb(ctcp_action => sub { vndbid($_[1], $_[2], $_[3]) });
}


sub set_logger {
  # Uses the same logging format as Component::IRC::Plugin::Logger
  # Only logs channel chat, joins, quits, kicks and topic/nick changes
  my $l = sub {
    my($chan, $msg, @arg) = @_;
    return if !grep $chan eq $_, @{$O{channels}};
    open my $F, '>>', config->{Multi}{Core}{log_dir}."/$chan.log" or die $!;
    print $F strftime('%Y-%m-%d %H:%M:%S', localtime).' '.sprintf($msg, @arg)."\n";
  };

  $irc->reg_cb(join => sub {
    my(undef, $nick, $chan) = @_;
    $l->($chan, '--> %s (%s) joins %s', $nick, $irc->nick_ident($nick)||'', $chan);
  });
  $irc->reg_cb(channel_remove => sub {
    my(undef, $msg, $chan, @nicks) = @_;
    return if !defined $msg;
    $msg = $msg->{params}[$#{$msg->{params}}]||'';
    $l->($chan, '<-- %s (%s) quits (%s)', $_, $irc->nick_ident($_)||'', $msg) for(@nicks);
  });
  $irc->reg_cb(channel_change => sub {
    my(undef, undef, $chan, $old, $new) = @_;
    $l->($chan, '--- %s is now known as %s', $old, $new);
  });
  $irc->reg_cb(channel_topic => sub {
    my(undef, $chan, $topic, $nick) = @_;
    $l->($chan, '--- %s changes the topic to: %s', $nick||'server', $topic);
  });
  $irc->reg_cb(publicmsg => sub {
    my(undef, $chan, $msg) = @_;
    $l->($chan, '<%s> %s', prefix_nick($msg->{prefix}), $msg->{params}[1]);
  });
  $irc->reg_cb(ctcp_action => sub {
    my(undef, $nick, $chan, $msg) = @_;
    $l->($chan, '* %s %s', $nick, $msg);
  });
  $irc->reg_cb(sent => sub {
    my(undef, $prefix, $cmd, @args) = @_;
    # XXX: Doesn't handle CTCP ACTION
    $l->($args[0], '<%s> %s', $irc->nick(), $args[1]) if lc $cmd eq 'privmsg';
  });
}


sub set_notify {
  pg_cmd q{SELECT
    (SELECT id FROM changes ORDER BY id DESC LIMIT 1) AS rev,
    (SELECT date FROM threads_posts ORDER BY date DESC LIMIT 1) AS post,
    (SELECT id FROM reviews ORDER BY id DESC LIMIT 1) AS review
  }, undef, sub {
    return if pg_expect $_[0], 1;
    %lastnotify = %{($_[0]->rowsAsHashes())[0]};
    push_watcher pg->listen($_, on_notify => \&notify) for qw{newrevision newpost newreview};
  };
}


# formats and posts database items listed in @res, where each item is a hashref with:
#   id        database id
#   title     main name or title of the DB entry
#   rev       (optional) revision, post number
#   username  (optional) relevant username
#   boards    (optional) board titles the thread has been posted in
#   comments  (optional) edit summary
sub formatid {
  my($res, $dest, $notify) = @_;

  my $c = $notify ? $LIGHT_BLUE : $RED;

  # only the types for which creation/edit announcements matter
  my %types = (
    v => 'visual novel',
    p => 'producer',
    r => 'release',
    c => 'character',
    s => 'staff',
    g => 'tag',
    i => 'trait',
    t => 'thread',
    d => 'doc',
    w => 'review',
  );

  for (@$res) {
    my $id = $_->{id} . ($_->{rev} ? '.'.$_->{rev} : '');
    my $type = $types{ substr $id, 0, 1 };

    # (always) [x+.+]
    my @msg = ("$BOLD$c"."[$NORMAL$BOLD$id$c]$NORMAL");

    # (only if username key is present) Edit of / New item / reply to / whatever
    push @msg, $c.(
      $id =~ /^w/ && !$_->{rev} ? 'Review of' :
      $id =~ /^w/ ? 'Comment to review of' :
      ($_->{rev}||1) == 1 ? "New $type" :
      $id =~ /^t/ ? 'Reply to' : 'Edit of'
    ).$NORMAL if exists $_->{username};

    # (always) main title
    push @msg, $_->{title};

    # (only if boards key is present) Posted in [boards]
    push @msg, $c."Posted in$NORMAL $_->{boards}" if $_->{boards};

    # (only if username key is present) By [username]
    push @msg, $c."By$NORMAL ".($_->{username}//'deleted') if exists $_->{username};

    # (only if comments key is present) Summary:
    $_->{comments} =~ s/\n/ /g if $_->{comments};
    push @msg, $c."Summary:$NORMAL ".(
      length $_->{comments} > 40 ? substr($_->{comments}, 0, 37).'...' : $_->{comments}
    ) if defined $_->{comments};

    # (always) @ URL
    push @msg, $c."@ $NORMAL$LIGHT_GREY".config->{url}."/$id$NORMAL";

    # now post it
    $irc->send_msg(PRIVMSG => $dest, encode_utf8 join ' ', @msg);
  }
}


sub handleid {
  my($chan, $id, $rev) = @_;

  # Some common exceptions
  return if grep $id eq $_, qw|v1 v2 v3 v4 u2 i3 i5 i7 c64|;

  return if throttle $O{throt_vndbid}, 'irc_vndbid';
  return if throttle $O{throt_sameid}, "irc_sameid_$id.$rev";

  my $c = sub {
    return if pg_expect $_[0], 1;
    formatid([$_[0]->rowsAsHashes], $chan, 0) if $_[0]->nRows;
  };

  # plain vn/user/producer/thread/tag/trait/release
  pg_cmd 'SELECT $1::vndbid AS id, '.(
    $id =~ /^t/ ? 'title, '.$GETBOARDS.' FROM threads t WHERE NOT t.hidden AND NOT t.private AND t.id = $1' :
    $id =~ /^w/ ? 'v.title, u.username FROM reviews w JOIN vn v ON v.id = w.vid LEFT JOIN users u ON u.id = w.uid WHERE w.id = $1' :
                  'title FROM item_info($1,NULL) x'),
    [ $id ], $c if !$rev && $id =~ /^[dvprtugicsw]/;

  # edit/insert of vn/release/producer or discussion board post
  pg_cmd 'SELECT $1::vndbid AS id, $2::integer AS rev, '.(
    $id =~ /^t/ ? 't.title, u.username, '.$GETBOARDS.' FROM threads t JOIN threads_posts tp ON tp.tid = t.id LEFT JOIN users u ON u.id = tp.uid WHERE NOT t.hidden AND NOT t.private AND t.id = $1 AND tp.num = $2' :
    $id =~ /^w/ ? 'v.title, u.username FROM reviews_posts wp JOIN reviews w ON w.id = wp.id JOIN vn v ON v.id = w.vid LEFT JOIN users u ON u.id = wp.uid WHERE wp.id = $1 AND wp.num = $2' :
                  'x.title, u.username, c.comments FROM changes c JOIN item_info($1,$2) x ON true JOIN users u ON u.id = c.requester WHERE c.itemid = $1 AND c.rev = $2'),
    [ $id, $rev], $c if $rev && $id =~ /^[dvprtcsgiw]/;
}


sub vndbid {
  my($nick, $chan, $msg) = @_;

  return if $msg =~ /^\Q$BOLD/; # Never reply to another multi's spam. And ignore idiots who use bold. :D

  my @id; # [ type, id, ref ]
  for (split /[, ]/, $msg) {
    next if length > 15 or m{[a-z]{3,6}://}i; # weed out URLs and too long things
    push @id, /^(?:.*[^\w]|)([wdvprtcsgi][1-9][0-9]*)\.([1-9][0-9]*)(?:[^\w].*|)$/ ? [ $1, $2 ] # x+.+
            : /^(?:.*[^\w]|)([wdvprtcsgiu][1-9][0-9]*)(?:[^\w].*|)$/ ? [ $1, '' ] : ();         # x+
  }
  handleid($chan, @$_) for @id;
}




sub notify {
  my(undef, $sel) = @_;
  my $k = {qw|newrevision rev  newpost post  newreview review|}->{$sel};
  return if !$k || !$lastnotify{$k};

  my $q = {
  rev => q{
    SELECT c.rev, c.comments, c.id AS lastid, c.itemid AS id, x.title, u.username
    FROM changes c
    JOIN item_info(c.itemid, c.rev) x ON true
    JOIN users u ON u.id = c.requester
    WHERE c.id > $1 AND c.requester <> 'u1'
    ORDER BY c.id},
  post => q{
    SELECT tp.tid AS id, tp.num AS rev, t.title, COALESCE(u.username, 'deleted') AS username, tp.date AS lastid, }.$GETBOARDS.q{
    FROM threads_posts tp
    JOIN threads t ON t.id = tp.tid
    LEFT JOIN users u ON u.id = tp.uid
    WHERE tp.date > $1 AND tp.num = 1 AND NOT t.hidden AND NOT t.private
    ORDER BY tp.date},
  review => q{
    SELECT w.id, v.title, u.username, w.id AS lastid
    FROM reviews w
    JOIN vn v ON v.id = w.vid
    LEFT JOIN users u ON u.id = w.uid
    WHERE w.id > $1
    ORDER BY w.id}
  }->{$k};

  pg_cmd $q, [ $lastnotify{$k} ], sub {
    my $res = shift;
    return if pg_expect $res, 1;
    my @res = $res->rowsAsHashes;
    $lastnotify{$k} = $_->{lastid} for (@res);
    formatid \@res, $O{channels}[0], 1;
  };
}




# command => [ admin_only, need_bot_prefix, sub->(nick, chan, cmd_args) ]
my %cmds = (

info => [ 0, 0, sub {
  $irc->send_msg(PRIVMSG => $_[1], 
    'Hi! I am HMX-12 Multi '.config->{version}.', the IRC bot of '.config->{url}.'/, written by the great master Yorhel!');
}],

list => [ 0, 0, sub {
  $irc->send_msg(PRIVMSG => $_[1],
    $irc->is_channel_name($_[1]) ? 'This is not a warez channel!' : 'I am not a warez bot!');
}],

quote => [ 1, 0, sub {
  my(undef, $chan) = @_;
  pg_cmd 'SELECT quote FROM quotes ORDER BY random() LIMIT 1', undef, sub {
    return if pg_expect $_[0], 1 or !$_[0]->nRows;
    $irc->send_msg(PRIVMSG => $chan, encode_utf8 $_[0]->value(0,0));
  };
} ],

vn => [ 0, 0, sub {
  my($nick, $chan, $q) = @_;
  return $irc->send_msg(PRIVMSG => $chan, 'You forgot the search query, dummy~~!') if !$q;

  my @q = normalize_query($q);
  return $irc->send_msg(PRIVMSG => $chan,
    "Couldn't do anything with that search query, you might want to add quotes or use longer words.") if !@q;

  my $w = join ' AND ', map "c_search LIKE \$$_", 1..@q;
  pg_cmd qq{
    SELECT id, title
      FROM vn
     WHERE NOT hidden AND $w
     ORDER BY title
     LIMIT 6
  }, [ map "%$_%", @q ], sub {
    my $res = shift;
    return if pg_expect $res, 1;
    return $irc->send_msg(PRIVMSG => $chan, 'No visual novels found.') if !$res->nRows;
    return $irc->send_msg(PRIVMSG => $chan,
      sprintf 'Too many results found, see %s/v?q=%s', config->{url}, uri_escape($q)) if $res->nRows > 5;
    formatid([$res->rowsAsHashes()], $chan, 0);
  };
}],

p => [ 0, 0, sub {
  my($nick, $chan, $q) = @_;
  return $irc->send_msg(PRIVMSG => $chan, 'You forgot the search query, dummy~~!') if !$q;
  pg_cmd q{
    SELECT id, name AS title
    FROM producers p
    WHERE hidden = FALSE AND (name ILIKE $1 OR original ILIKE $1 OR alias ILIKE $1)
    ORDER BY name
    LIMIT 6
  }, [ "%$q%" ], sub {
    my $res = shift;
    return if pg_expect $res, 1;
    return $irc->send_msg(PRIVMSG => $chan, 'No producers novels found.') if !$res->nRows;
    return $irc->send_msg(PRIVMSG => $chan,
      sprintf 'Too many results found, see %s/p/all?q=%s', config->{url}, uri_escape($q)) if $res->nRows > 5;
    formatid([$res->rowsAsHashes()], $chan, 0);
  };
}],

die => [ 1, 1, sub {
  kill 'TERM', 0;
}],
);


# Returns 1 if there was a valid command (or something that looked like it)
sub command {
  my($nick, $chan, $msg) = @_;
  $msg = decode_utf8($msg);

  my $me = $irc->nick();
  my $addressed = !$irc->is_channel_name($chan) || $msg =~ s/^\s*\Q$me\E[:,;.!?~]?\s*//;
  return 0 if !$addressed && !($msg =~ s/^\s*!//);

  return 0 if $msg !~ /^([a-z]+)(?:\s+(.+))?$/;
  my($cmd, $arg) = ($cmds{$1}, $2);

  return 0 if !$cmd && !$addressed;
  return 0 if $cmd && $cmd->[1] && !$addressed;

  return 1 if throttle $O{throt_cmd}, "irc_cmd_$nick";

  if(!$cmd && $addressed) {
    $irc->send_msg(PRIVMSG => $chan, 'Please make sense.');
    return 1;
  }

  my $id = lc $irc->nick_ident($nick);
  if($cmd->[0] && !grep $id eq lc $_, @{$O{masters}}) {
    $irc->send_msg(PRIVMSG => $chan, 'You are not my master!');
    return 1;
  }
  $cmd->[2]->($nick, $chan, $arg);
  return 1;
}

1;
