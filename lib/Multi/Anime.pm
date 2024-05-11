
#
#  Multi::Anime  -  Fetches anime info from AniDB
#

package Multi::Anime;

use v5.36;
use Multi::Core;
use AnyEvent::Socket;
use AnyEvent::Util;
use AnyEvent::HTTP;
use Encode 'decode_utf8', 'encode_utf8';
use VNDB::Types;
use VNDB::Config;


use constant {
    LOGIN_ACCEPTED         => 200,
    LOGIN_ACCEPTED_NEW_VER => 201,
    ANIME                  => 230,
    NO_SUCH_ANIME          => 330,
    NOT_LOGGED_IN          => 403,
    LOGIN_FIRST            => 501,
    CLIENT_BANNED          => 504,
    INVALID_SESSION        => 506,
    BANNED                 => 555,
    ANIDB_OUT_OF_SERVICE   => 601,
    SERVER_BUSY            => 602,
};

my @handled_codes = (
  LOGIN_ACCEPTED, LOGIN_ACCEPTED_NEW_VER, ANIME, NO_SUCH_ANIME, NOT_LOGGED_IN,
  LOGIN_FIRST,CLIENT_BANNED, INVALID_SESSION, BANNED, ANIDB_OUT_OF_SERVICE, SERVER_BUSY
);


my %O = (
  titlesurl => 'https://anidb.net/api/anime-titles.dat.gz',
  apihost => 'api.anidb.net',
  apiport => 9000,
  # AniDB UDP API options
  client => 'multi',
  clientver => 1,
  # Misc settings
  msgdelay => 30,
  timeout => 30,
  timeoutdelay => 0.4, # $delay = $msgdelay ** (1 + $tm*$timeoutdelay)
  maxtimeoutdelay => 2*3600,
  check_delay => 3600,
  resolve_delay => 3*3600,
  titles_delay => 48*3600,
  cachetime => '3 months',
);


my %C = (
  sock => undef,
  io => undef,
  tw => undef,# timer guard
  s => '',    # session key, '' = not logged in
  tm => 0,    # number of repeated timeouts
  lm => 0,    # timestamp of last outgoing message
  aid => 0,   # anime ID of the last sent ANIME command
  tag => int(rand()*50000),
);


sub run {
  shift;
  $O{ua} = sprintf 'VNDB.org Anime Fetcher (Multi v%s; contact@vndb.org)', config->{version};
  %O = (%O, @_);
  die "No AniDB user/pass configured!" if !$O{user} || !$O{pass};

  push_watcher schedule 0, $O{titles_delay}, \&titles_import;
  push_watcher schedule 0, $O{resolve_delay}, \&resolve;
  resolve();
}


sub unload {
  undef $C{tw};
}



# BUGs, kind of:
# - If the 'ja' title is not present in the titles dump, the title_kanji column will not be set to NULL.
# - This doesn't attempt to delete rows from the anime table that aren't present in the titles dump.
# Both can be 'solved' by periodically pruning unreferenced rows from the anime
# table and setting all title_kanji columns to NULL.

my %T;

sub titles_import {
  %T = (
    titles => 0,
    updates => 0,
    start_dl => AE::now(),
  );
  http_get $O{titlesurl}, headers => {'User-Agent' => $O{ua} }, timeout => 60, sub {
    my($body, $hdr) = @_;
    return AE::log warn => "Error fetching titles dump: $hdr->{Status} $hdr->{Reason}" if $hdr->{Status} !~ /^2/;

    $T{start_insert} = AE::now();
    if(!open $T{fh}, '<:gzip:utf8', \$body) {
      AE::log warn => "Error parsing titles dump: $!";
      return;
    }
    titles_insert();
  };
}

sub titles_next {
  my $F = $T{fh};
  while(local $_ = <$F>) {
    chomp;
    next if /^#/;
    my($id,$type,$lang,$title) = split /\|/, $_, 4;
    return (0, $id, $title) if $type eq '1';
    return (1, $id, $title) if $type eq '4' && $lang eq 'ja';
  }
  ()
}

sub titles_insert {
  my($orig, $id, $title) = titles_next();

  if(!defined $orig) {
    AE::log info => sprintf 'AniDB title import: %d titles, %d updates in %.1fs (fetch) + %.1fs (insert)',
      $T{titles}, $T{updates}, $T{start_insert}-$T{start_dl}, AE::now()-$T{start_insert};
    %T = ();
    return;
  }

  my $col = $orig ? 'title_kanji' : 'title_romaji';
  pg_cmd "INSERT INTO anime (id, $col) VALUES (\$1, \$2) ON CONFLICT (id) DO UPDATE SET $col = excluded.$col WHERE anime.$col IS DISTINCT FROM excluded.$col", [ $id, $title ], sub {
    my($res) = @_;
    return if pg_expect $res, 0;
    $T{titles}++;
    $T{updates} += $res->cmdRows;
    titles_insert();
  }
}





sub resolve {
  AnyEvent::Socket::resolve_sockaddr $O{apihost}, $O{apiport}, 'udp', 0, undef, sub {
    if(!@_) {
      AE::log warn => "Unable to resolve '$O{apihost}'";
      return; # Re-use old socket address or try again after resolve_delay.
    }
    my($fam, $type, $proto, $saddr) = @{$_[0]};
    my $sock;
    socket $sock, $fam, $type, $proto or die "Can't create UDP socket: $!";
    connect $sock, $saddr or die "Can't connect() UDP socket: $!";
    fh_nonblocking $sock, 1;

    if(!$C{sock}) {
      my($p, $h) = AnyEvent::Socket::unpack_sockaddr($saddr);
      AE::log info => sprintf "AniDB API client started, communicating with %s:%d", format_address($h), $p if !$C{sock};
      push_watcher pg->listen(anime => on_notify => \&check_anime);
      push_watcher schedule 0, $O{check_delay}, \&check_anime;
      check_anime();
    }

    $C{sock} = $sock;
    $C{io} = AE::io $C{sock}, 0, \&receivemsg;
  };
}


sub check_anime {
  return if $C{aid} || $C{tw};
  pg_cmd 'SELECT id FROM anime
           WHERE EXISTS(SELECT 1 FROM vn_anime WHERE aid = anime.id)
             AND (lastfetch IS NULL OR lastfetch < NOW() - $1::interval)
           ORDER BY lastfetch DESC NULLS FIRST LIMIT 1', [ $O{cachetime} ], sub {
    my $res = shift;
    return if pg_expect $res, 1 or $C{aid} or $C{tw} or !$res->rows;
    $C{aid} = $res->value(0,0);
    nextcmd();
  };
}


sub nextcmd {
  return if $C{tw}; # don't send a command if we're waiting for a reply or timeout.
  return if !$C{aid}; # don't send a command if we've got nothing to fetch...

  my %cmd = !$C{s} ?
    ( # not logged in, get a session
      command => 'AUTH',
      user => $O{user},
      pass => $O{pass},
      protover => 3,
      client => $O{client},
      clientver => $O{clientver},
      enc => 'UTF-8',
    ) : ( # logged in, get anime
      command => 'ANIME',
      aid => $C{aid},
      # aid, year, type, ann, nfo
      amask => sprintf('%02x%02x%02x%02x%02x%02x%02x', 128+32+16, 0, 0, 0, 64+16, 0, 0),
    );

  # XXX: We don't have a writability watcher, but since we're only ever sending
  # out one packet at a time, I assume (or rather, hope) that the kernel buffer
  # always has space for it. If not, the timeout code will retry the command
  # anyway.
  my $cmd = fmtcmd(%cmd);
  AE::log debug => "Sending command: $cmd";
  $cmd = encode_utf8 $cmd;
  my $n = syswrite $C{sock}, $cmd;
  AE::log warn => sprintf "Didn't write command: only sent %d of %d bytes: %s", $n, length($cmd), $! if $n != length($cmd);

  $C{tw} = AE::timer $O{timeout}, 0, \&handletimeout;
  $C{lm} = AE::now;
}


sub fmtcmd {
  my %cmd = @_;
  my $cmd = delete $cmd{command};
  $cmd{tag} = ++$C{tag};
  $cmd{s} = $C{s} if $C{s};
  return $cmd.' '.join('&', map {
    $cmd{$_} =~ s/&/&amp;/g;
    $cmd{$_} =~ s/\r?\n/<br \/>/g;
    $_.'='.$cmd{$_}
  } keys %cmd);
}


sub receivemsg {
  my $buf = '';
  my $n = sysread $C{sock}, $buf, 4096;
  return AE::log warn => "sysread() failed: $!" if $n < 0;

  $buf = decode_utf8 $buf;
  my $time = AE::now-$C{lm};
  AE::log debug => sprintf "Received message in %.2fs: %s", $time, $buf;

  my @r = split /\n/, $buf;
  my($tag, $code, $msg) = ($1, $2, $3) if $r[0] =~ /^([0-9]+) ([0-9]+) (.+)$/;

  return AE::log warn => "Ignoring message due to incorrect tag: $buf"
    if !$tag || $tag != $C{tag};
  return AE::log warn => "Ignoring message with unknown code: $buf"
    if !grep $_ == $code, @handled_codes;

  # Now we have a message we can handle, reset timer
  undef $C{tw};

  # Consider some codes to be equivalent to a timeout
  if($code == CLIENT_BANNED || $code == BANNED || $code == ANIDB_OUT_OF_SERVICE || $code == SERVER_BUSY) {
    # Might want to look into these...
    AE::log warn => "AniDB doesn't seem to like me: $buf" if $code == CLIENT_BANNED || $code == BANNED;
    handletimeout();
    return;
  }

  handlemsg($tag, $code, $msg, @r);
}


sub handlemsg {
  my($tag, $code, $msg, @r) = @_;
  my $f;

  # our session isn't valid, discard it and call nextcmd to get a new one
  if($code == NOT_LOGGED_IN || $code == LOGIN_FIRST || $code == INVALID_SESSION) {
    $C{s} = '';
    $f = \&nextcmd;
    AE::log info => 'Our session was invalid, logging in again...';
  }

  # we received a session ID, call nextcmd again to fetch anime info
  elsif($code == LOGIN_ACCEPTED || $code == LOGIN_ACCEPTED_NEW_VER) {
    $C{s} = $1 if $msg =~ /^\s*([a-zA-Z0-9]{4,8}) /;
    $f = \&nextcmd;
    AE::log info => 'Successfully logged in to AniDB.';
  }

  # we now know something about the anime we requested, update DB
  elsif($code == NO_SUCH_ANIME) {
    AE::log info => "No anime found with id = $C{aid}";
    pg_cmd 'UPDATE anime SET lastfetch = NOW() WHERE id = $1', [ $C{aid} ];
    $f = \&check_anime;
    $C{aid} = 0;

  } else {
    update_anime($r[1]);
    $f = \&check_anime;
    $C{aid} = 0;
  }

  $C{tw} = AE::timer $O{msgdelay}, 0, sub { undef $C{tw}; $f->() };
}


sub update_anime {
  my $r = shift;

  # aid, year, type, ann, nfo
  my @col = split(/\|/, $r, 5);
  for(@col) {
    $_ =~ s/<br \/>/\n/g;
    $_ =~ s/`/'/g;
  }
  if($col[0] ne $C{aid}) {
    AE::log warn => sprintf 'Received from aid (%s) for a%d', $col[0], $C{aid};
    return;
  }
  $col[1] = $col[1] =~ /^([0-9]+)/ ? $1 : undef;
  ($col[2]) = grep lc($col[2]) eq lc($ANIME_TYPE{$_}{anidb}), keys %ANIME_TYPE;
  $col[3] = undef if !$col[3];
  $col[4] = undef if !$col[4] || $col[2] =~ /^0,/;

  pg_cmd 'UPDATE anime
    SET id = $1, year = $2, type = $3, ann_id = $4, nfo_id = $5, lastfetch = NOW()
    WHERE id = $1', \@col;
  AE::log info => "Fetched anime info for a$C{aid}";
}


sub handletimeout {
  $C{tm}++;
  my $delay = $O{msgdelay}**(1 + $C{tm}*$O{timeoutdelay});
  $delay = $O{maxtimeoutdelay} if $delay > $O{maxtimeoutdelay};
  AE::log info => 'Reply timed out, delaying %.0fs.', $delay;
  $C{tw} = AE::timer $delay, 0, sub { undef $C{tw}; nextcmd() };
}

1;
