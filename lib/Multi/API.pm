
#
#  Multi::API  -  The public VNDB API
#

package Multi::API;

use v5.26;
use warnings;
use Multi::Core;
use Socket 'SO_KEEPALIVE', 'SOL_SOCKET', 'IPPROTO_TCP';
use AnyEvent::Socket;
use AnyEvent::Handle;
use POE::Filter::VNDBAPI 'encode_filters';
use Encode 'encode_utf8', 'decode_utf8';
use Crypt::URandom 'urandom';
use Crypt::ScryptKDF 'scrypt_raw';;
use VNDB::Func 'imgurl', 'imgsize', 'norm_ip', 'resolution';
use VNDB::Types;
use VNDB::Config;
use JSON::XS;
use PWLookup;
use VNDB::ExtLinks 'sql_extlinks';

# Linux-specific, not exported by the Socket module.
sub TCP_KEEPIDLE  () { 4 }
sub TCP_KEEPINTVL () { 5 }
sub TCP_KEEPCNT   () { 6 }

# what our JSON encoder considers 'true' or 'false'
sub TRUE  () { JSON::XS::true }
sub FALSE () { JSON::XS::false }

my %O = (
  port => 19534,
  tls_port => 19535,  # Only used when tls_options is set
  logfile => config->{Multi}{Core}{log_dir}.'/api.log',
  conn_per_ip => 10,
  max_results => 25, # For get vn/release/producer/character
  max_results_lists => 100, # For get votelist/vnlist/wishlist
  default_results => 10,
  throttle_cmd => [ 3, 200 ], # interval between each command, allowed burst
  throttle_sql => [ 60, 1 ],  # sql time multiplier, allowed burst (in sql time)
  throttle_thr => [ 1, 20 ],  # interval between "throttled" replies, allowed burst
  tls_options => undef, # Set to AnyEvent::TLS options to enable TLS
);


my %C;
my $connid = 0;


sub writelog {
  my $c = ref $_[0] && shift;
  my($msg, @args) = @_;
  if(open(my $F, '>>:utf8', $O{logfile})) {
    printf $F "[%s] %s: %s\n", scalar localtime,
      $c ? sprintf('%d %s:%d%s', $c->{id}, $c->{ip}, $c->{port}, $c->{tls} ? 'S' : '') : 'global',
      @args ? sprintf $msg, @args : $msg;
    close $F;
  }
}


sub run {
  shift;
  %O = (%O, @_);

  push_watcher tcp_server '::', $O{port}, sub { newconn(0, @_) };;
  # The following tcp_server will fail if the above already bound to IPv4.
  eval {
    push_watcher tcp_server 0, $O{port}, sub { newconn(0, @_) };
  };

  if($O{tls_options}) {
    push_watcher tcp_server '::', $O{tls_port}, sub { newconn(1, @_) };
    eval {
      push_watcher tcp_server 0, $O{tls_port}, sub { newconn(1, @_) };
    };
  }

  writelog 'API starting up on port %d (TLS %s)', $O{port}, $O{tls_options} ? "on port $O{tls_port}" : 'disabled';
}


sub unload {
  $C{$_}{h}->destroy() for keys %C;
  %C = ();
}


sub newconn {
  my $c = {
    tls   => $_[0],
    fh    => $_[1],
    ip    => $_[2],
    port  => $_[3],
    id    => ++$connid,
    cid   => norm_ip($_[2]),
    filt  => POE::Filter::VNDBAPI->new(),
  };

  if($O{conn_per_ip} <= grep $c->{ip} eq $C{$_}{ip}, keys %C) {
    writelog $c, 'Connection denied, limit of %d connections per IP reached', $O{conn_per_ip};
    close $c->{fh};
    return;
  }

  eval {
    setsockopt($c->{fh}, SOL_SOCKET,  SO_KEEPALIVE,   1);
    setsockopt($c->{fh}, IPPROTO_TCP, TCP_KEEPIDLE, 120);
    setsockopt($c->{fh}, IPPROTO_TCP, TCP_KEEPINTVL, 30);
    setsockopt($c->{fh}, IPPROTO_TCP, TCP_KEEPCNT,   10);
  };

  writelog $c, 'Connected';
  $C{$connid} = $c;

  $c->{h} = AnyEvent::Handle->new(
    rbuf_max =>     50*1024, # Commands aren't very huge, a 50k read buffer should suffice.
    wbuf_max => 5*1024*1024,
    fh       => $c->{fh},
    keepalive=> 1, # Kinda redundant with setsockopt(), but w/e
    on_error => sub {
      writelog $c, 'IO error: %s', $_[2];
      $c->{h}->destroy;
      delete $C{$c->{id}};
    },
    on_eof => sub {
      writelog $c, 'Disconnected';
      $c->{h}->destroy;
      delete $C{$c->{id}};
    },
    $c->{tls} ? (
      tls => 'accept',
      tls_ctx => $O{tls_options},
    ) : (),
  );
  cmd_read($c);
}


sub cres {
  my($c, $msg, $log, @arg) = @_;
  $msg = $c->{filt}->put([$msg])->[0];
  $c->{h}->push_write($msg);
  writelog $c, '[%2d/%4.0fms %5.0f] %s',
    $c->{sqlq}, $c->{sqlt}*1000, length($msg),
    @arg ? sprintf $log, @arg : $log;
  if($c->{disconnect}) { $c->{h}->push_shutdown() }
  else { cmd_read($c); }
}


sub cerr {
  my($c, $id, $msg, %o) = @_;
  cres $c, [ error => { id => $id, msg => $msg, %o } ], "Error: %s, %s", $id, $msg;
  return undef;
}


# Wrapper around pg_cmd() that updates the SQL throttle for the client and
# sends an error response if the query error'ed. The callback is not called on
# error.
sub cpg {
  my($c, $q, $a, $cb) = @_;
  pg_cmd $q, $a, sub {
    my($res, $time) = @_;
    $c->{sqlq}++;
    $c->{sqlt} += $time;
    return cerr $c, internal => 'SQL error' if pg_expect $res;
    throttle $O{throttle_sql}, "api_sql_$c->{cid}", $time;
    $cb->($res);
  };
}


sub cmd_read {
  my $c = shift;

  # Prolly should make POE::Filter::VNDBAPI aware of AnyEvent::Handle stuff, so
  # this code wouldn't require a few protocol specific chunks.
  $c->{h}->push_read(line => "\x04", sub {
    my $cmd = $c->{filt}->get([$_[1], "\x04"]);
    die "None or too many commands in a single message" if @$cmd != 1;

    my @arg;
    ($cmd, @arg) = @{$cmd->[0]};

    # log raw message (except login command, which may include a password)
    (my $msg = $_[1]) =~ s/[\r\n]*/ /;
    $msg =~ s/^[\s\r\n\t]+//;
    $msg =~ s/[\s\r\n\t]+$//;
    writelog $c, decode_utf8 "< $msg" if $cmd && $cmd ne 'login';

    # Stats for the current cmd
    $c->{sqlt} = $c->{sqlq} = 0;

    # parse error
    return cerr $c, $arg[0]{id}, $arg[0]{msg} if !defined $cmd;

    # check for thottle rule violation
    for ('cmd', 'sql') {
      my $left = throttle $O{"throttle_$_"}, "api_${_}_$c->{cid}", 0;
      next if !$left;

      # Too many throttle rule violations? Misbehaving client, disconnect.
      if(throttle $O{throttle_thr}, "api_thr_$c->{cid}") {
        writelog $c, 'Too many throttled replies, disconnecting.';
        $c->{h}->destroy;
        delete $C{$c->{id}};
        return;
      }

      return cerr $c, throttled => 'Throttle limit reached.', type => $_,
          minwait  => int(10*($left))/10+1,
          fullwait => int(10*($left + $O{"throttle_$_"}[0] * $O{"throttle_$_"}[1]))/10+1;
    }

    # update commands/second throttle
    throttle $O{throttle_cmd}, "api_cmd_$c->{cid}";
    cmd_handle($c, $cmd, @arg);
  });
}


sub cmd_handle {
  my($c, $cmd, @arg) = @_;

  # login
  return login($c, @arg) if $cmd eq 'login';
  return cerr $c, needlogin => 'Not logged in.' if !$c->{client};

  # logout
  if($cmd eq 'logout') {
    return cerr $c, parse => 'Too many arguments to logout command' if @arg > 0;
    return cerr $c, needlogin => 'No session token associated with this connection' if !$c->{sessiontoken};
    return pg_cmd 'SELECT user_logout($1, decode($2, \'hex\'))', [ $c->{uid}, $c->{sessiontoken} ], sub {
      $c->{disconnect} = 1;
      cres $c, ['ok'], 'Logged out, session invalidated';
    }
  }

  # dbstats
  if($cmd eq 'dbstats') {
    return cerr $c, parse => 'Too many arguments to dbstats command' if @arg > 0;
    return dbstats($c);
  }

  # get
  if($cmd eq 'get') {
    return get($c, @arg);
  }

  # set
  if($cmd eq 'set') {
    return set($c, @arg);
  }

  # unknown command
  cerr $c, 'parse', "Unknown command '$cmd'";
}


sub login {
  my($c, @arg) = @_;

  # validation (bah)
  return cerr $c, parse => 'Argument to login must be a single JSON object' if @arg != 1 || ref($arg[0]) ne 'HASH';
  my $arg = $arg[0];
  return cerr $c, loggedin => 'Already logged in, please reconnect to start a new session' if $c->{client};

  !exists $arg->{$_} && return cerr $c, missing => "Required field '$_' is missing", field => $_
    for(qw|protocol client clientver|);
  for(qw|protocol client clientver username password sessiontoken|) {
    exists $arg->{$_} && !defined $arg->{$_} && return cerr $c, badarg  => "Field '$_' cannot be null", field => $_;
    exists $arg->{$_} && ref $arg->{$_}      && return cerr $c, badarg  => "Field '$_' must be a scalar", field => $_;
  }
  return cerr $c, badarg => 'Unknown protocol version', field => 'protocol' if $arg->{protocol}  ne '1';
  return cerr $c, badarg => 'Invalid client name', field => 'client'        if $arg->{client}    !~ /^[a-zA-Z0-9 _-]{3,50}$/;
  return cerr $c, badarg => 'Invalid client version', field => 'clientver'  if $arg->{clientver} !~ /^[a-zA-Z0-9_.\/-]{1,25}$/;

  return cerr $c, badarg => '"createsession" can only be used when logging in with a password.' if !exists $arg->{password} && exists $arg->{createsession};
  return cerr $c, badarg => 'Missing "username" field.', field => 'username' if !exists $arg->{username} && (exists $arg->{password} || exists $arg->{sessiontoken});

  if(!exists $arg->{username}) {
    $c->{client} = $arg->{client};
    $c->{clientver} = $arg->{clientver};
    cres $c, ['ok'], 'Login using client "%s" ver. %s', $c->{client}, $c->{clientver};

  } elsif(exists $arg->{password}) {
    return cerr $c, auth => "Password too weak, please log in on the site and change your password"
      if config->{password_db} && PWLookup::lookup(config->{password_db}, $arg->{password});
    login_auth($c, $arg);

  } elsif(exists $arg->{sessiontoken}) {
    return cerr $c, badarg => 'Invalid session token', field => 'sessiontoken' if $arg->{sessiontoken} !~ /^[a-fA-F0-9]{40}$/;
    cpg $c, 'SELECT id, username FROM users WHERE lower(username) = lower($1) AND user_isvalidsession(id, decode($2, \'hex\'), \'api\')',
      [ $arg->{username}, $arg->{sessiontoken} ], sub {
      if($_[0]->nRows == 1) {
        $c->{uid} = $_[0]->value(0,0);
        $c->{username} = $_[0]->value(0,1);
        $c->{client} = $arg->{client};
        $c->{clientver} = $arg->{clientver};
        $c->{sessiontoken} = $arg->{sessiontoken};
        cres $c, ['ok'], 'Successful login with session by %s (%s) using client "%s" ver. %s', $c->{username}, $c->{uid}, $c->{client}, $c->{clientver};
      } else {
        cerr $c, auth => "Wrong session token for user '$arg->{username}'";
      }
    };

  } else {
    return cerr $c, badarg => 'Missing "password" or "sessiontoken" field.';
  }
}


sub login_auth {
  my($c, $arg) = @_;

  # check login throttle (also used when logging in with a session... oh well)
  cpg $c, 'SELECT extract(\'epoch\' from timeout) FROM login_throttle WHERE ip = $1', [ norm_ip($c->{ip}) ], sub {
    my $tm = $_[0]->nRows ? $_[0]->value(0,0) : AE::time;
    return cerr $c, auth => "Too many failed login attempts"
      if $tm-AE::time() > config->{login_throttle}[1];

    # Fetch user info
    cpg $c, 'SELECT id, username, encode(user_getscryptargs(id), \'hex\') FROM users WHERE lower(username) = lower($1)', [ $arg->{username} ], sub {
      login_verify($c, $arg, $tm, $_[0]);
    };
  };
}


sub login_verify {
  my($c, $arg, $tm, $res) = @_;

  return cerr $c, auth => "No user with the name '$arg->{username}'" if $res->nRows == 0;
  my $uid = $res->value(0,0);
  my $username = $res->value(0,1);
  my $sargs = $res->value(0,2);
  return cerr $c, auth => "Account disabled" if !$sargs || length($sargs) != 14*2;

  my $token = unpack 'H*', urandom(20);
  my($N, $r, $p, $salt) = unpack 'NCCa8', pack 'H*', $sargs;
  my $passwd = pack 'NCCa8a*', $N, $r, $p, $salt, scrypt_raw(encode_utf8($arg->{password}), config->{scrypt_salt} . $salt, $N, $r, $p, 32);

  cpg $c, 'SELECT user_login($1, \'api\', decode($2, \'hex\'), decode($3, \'hex\'))', [ $uid, unpack('H*', $passwd), $token ], sub {
    if($_[0]->nRows == 1 && ($_[0]->value(0,0)||'') =~ /t/) {
      $c->{uid} = $uid;
      $c->{username} = $username;
      $c->{client} = $arg->{client};
      $c->{clientver} = $arg->{clientver};
      if($arg->{createsession}) {
        $c->{sessiontoken} = $token;
        cres $c, ['session', $token], 'Successful login with password+session by %s (%s) using client "%s" ver. %s', $username, $c->{uid}, $c->{client}, $c->{clientver};
      } else {
        pg_cmd 'SELECT user_logout($1, decode($2, \'hex\'))', [ $uid, $token ];
        cres $c, ['ok'], 'Successful login with password by %s (%s) using client "%s" ver. %s', $username, $c->{uid}, $c->{client}, $c->{clientver};
      }
    } else {
      my @a = ( $tm + config->{login_throttle}[0], norm_ip($c->{ip}) );
      pg_cmd 'UPDATE login_throttle SET timeout = to_timestamp($1) WHERE ip = $2', \@a;
      pg_cmd 'INSERT INTO login_throttle (ip, timeout) SELECT $2, to_timestamp($1) WHERE NOT EXISTS(SELECT 1 FROM login_throttle WHERE ip = $2)', \@a;
      cerr $c, auth => "Wrong password for user '$username'";
    }
  };
}


sub dbstats {
  my $c = shift;

  cpg $c, 'SELECT section, count FROM stats_cache', undef, sub {
    my $res = shift;
    cres $c, [ dbstats => { users => 0, threads => 0, posts => 0, map {
      ($_->{section}, 1*$_->{count})
    } $res->rowsAsHashes } ], 'dbstats';
  };
}


sub formatdate {
  return undef if $_[0] == 0;
  (local $_ = sprintf '%08d', $_[0]) =~
    s/^(\d{4})(\d{2})(\d{2})$/$1 == 9999 ? 'tba' : $2 == 99 ? $1 : $3 == 99 ? "$1-$2" : "$1-$2-$3"/e;
  return $_;
}


sub parsedate {
  return 0 if !defined $_[0];
  return \'Invalid date value' if $_[0] !~ /^(?:tba|\d{4}(?:-\d{2}(?:-\d{2})?)?)$/;
  my @v = split /-/, $_[0];
  return $v[0] eq 'tba' ? 99999999 : @v==1 ? "$v[0]9999" : @v==2 ? "$v[0]$v[1]99" : $v[0].$v[1].$v[2];
}


sub formatwd { $_[0] ? "Q$_[0]" : undef }

sub idnum { defined $_[0] ? 1*($_[0] =~ s/^[a-z]+//r) : undef }


sub splitarray {
  (my $s = shift) =~ s/^{(.*)}$/$1/;
  return [ split /,/, $s ];
}


# Returns an image flagging structure or undef if $image is false.
# Assumes $obj has c_votecount, c_sexual_avg and c_violence_avg.
# Those fields are removed from $obj.
sub image_flagging {
  my($image, $obj) = @_;
  my $flag = {
    votecount    => delete $obj->{c_votecount},
    sexual_avg   => delete $obj->{c_sexual_avg},
    violence_avg => delete $obj->{c_violence_avg},
  };
  $flag->{votecount}    *= 1 if defined $flag->{votecount};
  $flag->{sexual_avg}   /= 100 if defined $flag->{sexual_avg};
  $flag->{violence_avg} /= 100 if defined $flag->{violence_avg};
  $image ? $flag : undef;
}


# sql     => str: Main sql query, three printf args: select, where part, order by and limit clauses
# sqluser => str: Alternative to 'sql' if the user is logged in. One additional printf arg: user id.
#            If sql is undef and sqluser isn't, the command is only available to logged in users.
# select  => str: string to add to the select part of the main query
# proc    => &sub->($row): called on each row of the main query
# sorts   => { sort_key => sql_string }, %s is replaced with 'ASC/DESC' in sql_string
# sortdef => str: default sort (as per 'sorts')
# islist  => bool: Whether this is a vnlist/wishlist/votelist thing (determines max results)
# flags   => {
#   flag_name => {
#     select    => str: string to add to the select part of the main query
#     proc      => &sub->($row): same as parent proc
#     fetch     => [ [
#       idx:  str: name of the field from the main query to get the id list from,
#       sql:  str: SQL query to fetch more data. %s is replaced with the list of ID's based on fetchidx
#       proc: &sub->($rows, $fetchrows)
#     ], .. ],
#   }
# }
# filters => filters args for get_filters() (TODO: Document)
my %GET_VN = (
  sql     => 'SELECT %s FROM vnt v LEFT JOIN images i ON i.id = v.image WHERE NOT v.hidden AND (%s) %s',
  select  => 'v.id',
  proc    => sub {
    $_[0]{id} = idnum $_[0]{id};
  },
  sortdef => 'id',
  sorts   => {
    id => 'v.id %s',
    title => 'v.title %s, v.id',
    released => 'v.c_released %s, v.id',
    popularity => '-v.c_pop_rank %s NULLS LAST, v.id',
    rating => '-v.c_rat_rank %s NULLS LAST, v.id',
    votecount => 'v.c_votecount %s, v.id',
  },
  flags  => {
    basic => {
      select => 'v.title, v.alttitle AS original, v.c_released, v.c_languages, v.olang, v.c_platforms',
      proc   => sub {
        $_[0]{original}  ||= undef;
        $_[0]{platforms} = splitarray delete $_[0]{c_platforms};
        $_[0]{languages} = splitarray delete $_[0]{c_languages};
        $_[0]{orig_lang} = [ delete $_[0]{olang} ];
        $_[0]{released}  = formatdate delete $_[0]{c_released};
      },
    },
    details => {
      select => 'v.image, i.c_sexual_avg, i.c_violence_avg, i.c_votecount, i.width AS image_width, i.height AS image_height, v.alias AS aliases,
            v.length, v.c_length AS length_minutes, v.c_lengthnum AS length_votes, v.desc AS description, v.l_wp, v.l_encubed, v.l_renai, l_wikidata',
      proc   => sub {
        $_[0]{aliases}     ||= undef;
        $_[0]{length}      *= 1;
        $_[0]{length}      ||= undef;
        $_[0]{length_votes}*= 1;
        $_[0]{length_minutes}*=1 if defined $_[0]{length_minutes};
        $_[0]{description} ||= undef;
        $_[0]{links} = {
          wikipedia => delete($_[0]{l_wp})     ||undef,
          encubed   => delete($_[0]{l_encubed})||undef,
          renai     => delete($_[0]{l_renai})  ||undef,
          wikidata  => formatwd(delete $_[0]{l_wikidata}),
        };
        $_[0]{image} = $_[0]{image} ? imgurl $_[0]{image} : undef;
        $_[0]{image_nsfw}  = !$_[0]{image} ? FALSE : !$_[0]{c_votecount} || $_[0]{c_sexual_avg} > 40 || $_[0]{c_violence_avg} > 40 ? TRUE : FALSE;
        $_[0]{image_flagging} = image_flagging $_[0]{image}, $_[0];
        $_[0]{image_width} *= 1 if defined $_[0]{image_width};
        $_[0]{image_height} *= 1 if defined $_[0]{image_height};
      },
    },
    stats => {
      select => 'v.c_popularity, v.c_rating, v.c_votecount as votecount',
      proc => sub {
        $_[0]{popularity} = 1 * sprintf '%.2f', (delete $_[0]{c_popularity} or 0)/100;
        $_[0]{rating}     = 1 * sprintf '%.2f', (delete $_[0]{c_rating} or 0)/100;
        $_[0]{votecount}  *= 1;
      },
    },
    titles => {
      fetch => [[ 'id', 'SELECT id, lang, title, latin, official FROM vn_titles WHERE id IN(%s)',
        sub { my($r, $n) = @_;
          for my $i (@$r) {
            $i->{titles} = [ grep $i->{id} eq $_->{id}, @$n ];
          }
          for (@$n) {
            delete $_->{id};
            $_->{official} = $_->{official} =~ /t/ ? TRUE : FALSE,
          }
        }
      ]],
    },
    anime => {
      fetch => [[ 'id', 'SELECT va.id AS vid, a.id, a.year, a.ann_id, a.nfo_id, a.type, a.title_romaji, a.title_kanji
                     FROM anime a JOIN vn_anime va ON va.aid = a.id WHERE va.id IN(%s)',
        sub { my($r, $n) = @_;
          # link
          for my $i (@$r) {
            $i->{anime} = [ grep $i->{id} eq $_->{vid}, @$n ];
          }
          # cleanup
          for (@$n) {
            $_->{id}     *= 1;
            $_->{year}   *= 1 if defined $_->{year};
            $_->{ann_id} *= 1 if defined $_->{ann_id};
            delete $_->{vid};
          }
        }
      ]],
    },
    relations => {
      fetch => [[ 'id', 'SELECT vr.id AS vid, v.id, vr.relation, v.title, v.alttitle AS original, vr.official FROM vn_relations vr
                     JOIN vnt v ON v.id = vr.vid WHERE vr.id IN(%s)',
        sub { my($r, $n) = @_;
          for my $i (@$r) {
            $i->{relations} = [ grep $i->{id} eq $_->{vid}, @$n ];
          }
          for (@$n) {
            $_->{id} = idnum $_->{id};
            $_->{original} ||= undef;
            $_->{official} = $_->{official} =~ /t/ ? TRUE : FALSE,
            delete $_->{vid};
          }
        }
      ]],
    },
    tags => {
      fetch => [[ 'id', 'SELECT vid, tag AS id, avg(CASE WHEN ignore THEN NULL ELSE vote END) as score,
                          COALESCE(avg(CASE WHEN ignore THEN NULL ELSE spoiler END), 0) as spoiler
                     FROM tags_vn tv WHERE vid IN(%s) GROUP BY vid, id
                   HAVING avg(CASE WHEN ignore THEN NULL ELSE vote END) > 0',
        sub { my($r, $n) = @_;
          for my $i (@$r) {
            $i->{tags} = [ map
              [ idnum($_->{id}), 1*sprintf('%.2f', $_->{score}), 1*sprintf('%.0f', $_->{spoiler}) ],
              grep $i->{id} eq $_->{vid}, @$n ];
          }
        },
      ]],
    },
    screens => {
      fetch => [[ 'id', 'SELECT vs.id AS vid, vs.scr, vs.rid, s.width, s.height, s.c_sexual_avg, s.c_violence_avg, s.c_votecount
                      FROM vn_screenshots vs JOIN images s ON s.id = vs.scr WHERE vs.id IN(%s)',
        sub { my($r, $n) = @_;
          for my $i (@$r) {
            $i->{screens} = [ grep $i->{id} eq $_->{vid}, @$n ];
          }
          for (@$n) {
            $_->{id} = $_->{scr};
            $_->{thumbnail} = imgurl($_->{scr}, 1);
            $_->{image} = imgurl delete $_->{scr};
            $_->{rid} = idnum $_->{rid};
            $_->{nsfw} = !$_->{c_votecount} || $_->{c_sexual_avg} > 40 || $_->{c_violence_avg} > 40 ? TRUE : FALSE;
            $_->{width} *= 1;
            $_->{height} *= 1;
            ($_->{thumbnail_width}, $_->{thumbnail_height}) = imgsize $_->{width}, $_->{height}, config->{scr_size}->@*;
            $_->{flagging} = image_flagging(1, $_);
            delete $_->{vid};
          }
        },
      ]]
    },
    staff => {
      fetch => [[ 'id', 'SELECT vs.id, vs.aid, vs.role, vs.note, sa.id AS sid, sa.name, sa.original
                      FROM vn_staff vs JOIN staff_alias sa ON sa.aid = vs.aid JOIN staff s ON s.id = sa.id
                      WHERE vs.id IN(%s) AND NOT s.hidden',
        sub { my($r, $n) = @_;
          for my $i (@$r) {
            $i->{staff} = [ grep $i->{id} eq $_->{id}, @$n ];
          }
          for (@$n) {
            $_->{aid} *= 1;
            $_->{sid} = idnum $_->{sid};
            $_->{original} ||= undef;
            $_->{note} ||= undef;
            delete $_->{id};
          }
        }
      ]],
    },
  },
  filters => {
    id => [
      [ 'int' => 'v.id :op: :value:', {qw|= =  != <>  > >  < <  <= <=  >= >=|}, process => \'v' ],
      [ inta  => 'v.id :op:(:value:)', {'=' => 'IN', '!= ' => 'NOT IN'}, process => \'v', join => ',' ],
    ],
    title => [
      [ str   => 'v.title :op: :value:', {qw|= =  != <>|} ],
      [ str   => 'v.title ILIKE :value:', {'~',1}, process => \'like' ],
    ],
    original => [
      [ undef,   "v.alttitle :op: ''", {qw|= =  != <>|} ],
      [ str   => 'v.alttitle :op: :value:', {qw|= =  != <>|} ],
      [ str   => 'v.alttitle ILIKE :value:', {'~',1}, process => \'like' ]
    ],
    firstchar => [
      [ undef,   ':op: match_firstchar(v.title, \'0\')', {'=', '', '!=', 'NOT'} ],
      [ str   => ':op: match_firstchar(v.title, :value:)', {'=', '', '!=', 'NOT'}, process => sub { shift =~ /^([a-z])$/ ? $1 : \'Invalid character' } ],
    ],
    released => [
      [ undef,   'v.c_released :op: 0', {qw|= =  != <>|} ],
      [ str   => 'v.c_released :op: :value:', {qw|= =  != <>  > >  < <  <= <=  >= >=|}, process => \&parsedate ],
    ],
    platforms => [
      [ undef,   "v.c_platforms :op: '{}'", {qw|= =  != <>|} ],
      [ str   => ':op: (v.c_platforms && ARRAY[:value:]::platform[])', {'=' => '', '!=' => 'NOT'}, process => \'plat' ],
      [ stra  => ':op: (v.c_platforms && ARRAY[:value:]::platform[])', {'=' => '', '!=' => 'NOT'}, join => ',', process => \'plat' ],
    ],
    languages => [
      [ undef,   "v.c_languages :op: '{}'", {qw|= =  != <>|} ],
      [ str   => ':op: (v.c_languages && ARRAY[:value:]::language[])', {'=' => '', '!=' => 'NOT'}, process => \'lang' ],
      [ stra  => ':op: (v.c_languages && ARRAY[:value:]::language[])', {'=' => '', '!=' => 'NOT'}, join => ',', process => \'lang' ],
    ],
    orig_lang => [
      [ str   => 'v.olang :op: :value:', {qw|= =  != <>|}, process => \'lang' ],
      [ stra  => 'v.olang :op:(:value:)', {'=' => 'IN', '!=' => 'NOT IN'}, join => ',', process => \'lang' ],
    ],
    search => [
      [ str   => 'v.c_search LIKE ALL (search_query(:value:))', {'~',1} ],
    ],
    tags => [
      [ int   => 'v.id :op:(SELECT vid FROM tags_vn_inherit WHERE tag = :value:)',   {'=' => 'IN', '!=' => 'NOT IN'}, process => \'g' ],
      [ inta  => 'v.id :op:(SELECT vid FROM tags_vn_inherit WHERE tag IN(:value:))', {'=' => 'IN', '!=' => 'NOT IN'}, join => ',', process => \'g' ],
    ],
  },
);

my %GET_RELEASE = (
  sql     => 'SELECT %s FROM releasest r WHERE NOT hidden AND (%s) %s',
  select  => 'r.id',
  sortdef => 'id',
  sorts   => {
    id => 'r.id %s',
    title => 'r.sorttitle %s, r.id',
    released => 'r.released %s, r.id',
  },
  proc    => sub {
    $_[0]{id} = idnum $_[0]{id};
  },
  flags => {
    basic => {
      select => 'r.title, r.alttitle AS original, r.released, r.patch, r.freeware, r.doujin, r.official',
      proc   => sub {
        $_[0]{original} ||= undef;
        $_[0]{released} = formatdate($_[0]{released});
        $_[0]{patch}    = $_[0]{patch}    =~ /^t/ ? TRUE : FALSE;
        $_[0]{freeware} = $_[0]{freeware} =~ /^t/ ? TRUE : FALSE;
        $_[0]{doujin}   = $_[0]{doujin}   =~ /^t/ ? TRUE : FALSE;
        $_[0]{official} = $_[0]{official} =~ /^t/ ? TRUE : FALSE;
      },
      fetch => [[ 'id', 'SELECT id, lang FROM releases_titles WHERE id IN(%s)',
        sub { my($n, $r) = @_;
          for my $i (@$n) {
            $i->{languages} = [ map $i->{id} eq $_->{id} ? $_->{lang} : (), @$r ];
          }
        },
      ], ['id', 'SELECT id, MAX(rtype) AS type FROM releases_vn WHERE id IN(%s) GROUP BY id',
        sub { my($n, $r) = @_;
          my %t = map +($_->{id},$_->{type}), @$r;
          $_->{type} = $t{$_->{id}} for @$n;
        },
      ]],
    },
    details => {
      select => 'r.website, r.notes, r.minage, r.gtin, r.catalog, r.reso_x, r.reso_y, r.voiced, r.ani_story, r.ani_ero',
      proc   => sub {
        $_[0]{website}  ||= undef;
        $_[0]{notes}    ||= undef;
        $_[0]{minage}   *= 1 if defined $_[0]{minage};
        $_[0]{gtin}     ||= undef;
        $_[0]{catalog}  ||= undef;
        $_[0]{resolution} = resolution $_[0];
        $_[0]{voiced}     = $_[0]{voiced}     ? $_[0]{voiced}*1    : undef;
        $_[0]{animation}  = [
          $_[0]{ani_story} ? $_[0]{ani_story}*1 : undef,
          $_[0]{ani_ero}   ? $_[0]{ani_ero}*1   : undef
        ];
        delete($_[0]{ani_story});
        delete($_[0]{ani_ero});
        delete($_[0]{reso_x});
        delete($_[0]{reso_y});
      },
      fetch => [
        [ 'id', 'SELECT id, platform FROM releases_platforms WHERE id IN(%s)',
          sub { my($n, $r) = @_;
            for my $i (@$n) {
               $i->{platforms} = [ map $i->{id} eq $_->{id} ? $_->{platform} : (), @$r ];
            }
          } ],
        [ 'id', 'SELECT id, medium, qty FROM releases_media WHERE id IN(%s)',
          sub { my($n, $r) = @_;
            for my $i (@$n) {
              $i->{media} = [ grep $i->{id} eq $_->{id}, @$r ];
            }
            for (@$r) {
              delete $_->{id};
              $_->{qty} = $MEDIUM{$_->{medium}}{qty} ? $_->{qty}*1 : undef;
            }
          } ],
      ]
    },
    lang => {
      fetch => [[ 'id', 'SELECT rt.id, rt.lang, rt.title, rt.latin, rt.mtl, rt.lang = r.olang AS main
                    FROM releases_titles rt JOIN releases r ON r.id = rt.id WHERE rt.id IN(%s)',
        sub { my($r, $n) = @_;
          for my $i (@$r) {
            $i->{lang} = [ grep $i->{id} eq $_->{id}, @$n ];
          }
          for (@$n) {
            delete $_->{id};
            $_->{mtl} = $_->{mtl} =~ /t/ ? TRUE : FALSE,
            $_->{main} = $_->{main} =~ /t/ ? TRUE : FALSE,
          }
        }
      ]],
    },
    vn => {
      fetch => [[ 'id', 'SELECT rv.id AS rid, rv.rtype, v.id, v.title, v.alttitle AS original FROM releases_vn rv JOIN vnt v ON v.id = rv.vid
                    WHERE NOT v.hidden AND rv.id IN(%s)',
        sub { my($n, $r) = @_;
          for my $i (@$n) {
            $i->{vn} = [ grep $i->{id} eq $_->{rid}, @$r ];
          }
          for (@$r) {
            $_->{id} = idnum $_->{id};
            $_->{original} ||= undef;
            delete $_->{rid};
          }
        }
      ]],
    },
    producers => {
      fetch => [[ 'id', 'SELECT rp.id AS rid, rp.developer, rp.publisher, p.id, p.type, p.name, p.original FROM releases_producers rp
                    JOIN producers p ON p.id = rp.pid WHERE NOT p.hidden AND rp.id IN(%s)',
        sub { my($n, $r) = @_;
          for my $i (@$n) {
            $i->{producers} = [ grep $i->{id} eq $_->{rid}, @$r ];
          }
          for (@$r) {
            $_->{id} = idnum $_->{id};
            $_->{original}  ||= undef;
            $_->{developer} = $_->{developer} =~ /^t/ ? TRUE : FALSE;
            $_->{publisher} = $_->{publisher} =~ /^t/ ? TRUE : FALSE;
            delete $_->{rid};
          }
        }
      ]],
    },
    links => {
      select => sql_extlinks('r'),
      proc => sub {
        my($e) = @_;
        $e->{links} = [];
        for my $l (keys $VNDB::ExtLinks::LINKS{r}->%*) {
          my $i = $VNDB::ExtLinks::LINKS{r}{$l};
          my $v = $e->{$l};
          push $e->{links}->@*,
            map +{ label => $i->{label}, url => sprintf($i->{fmt}, $_) },
            !$v || $v eq '{}' ? () : $v =~ /^{(.+)}$/ ? split /,/, $1 : ($v);
          delete $e->{$l};
        }
      },
    },
  },
  filters => {
    id => [
      [ 'int' => 'r.id :op: :value:', {qw|= =  != <>  > >  >= >=  < <  <= <=|}, process => \'r' ],
      [ inta  => 'r.id :op:(:value:)', {'=' => 'IN', '!=' => 'NOT IN'}, join => ',', process => \'r' ],
    ],
    vn => [
      [ 'int' => 'r.id :op:(SELECT rv.id FROM releases_vn rv WHERE rv.vid = :value:)', {'=' => 'IN', '!=' => 'NOT IN'}, process => \'v' ],
      [ inta  => 'r.id :op:(SELECT rv.id FROM releases_vn rv WHERE rv.vid IN(:value:))', {'=' => 'IN', '!=' => 'NOT IN'}, join => ',', process => \'v' ],
    ],
    producer => [
      [ 'int' => 'r.id IN(SELECT rp.id FROM releases_producers rp WHERE rp.pid = :value:)', {'=',1}, process => \'p' ],
    ],
    title => [
      [ str   => 'r.title :op: :value:', {qw|= =  != <>|} ],
      [ str   => 'r.title ILIKE :value:', {'~',1}, process => \'like' ],
    ],
    original => [
      [ undef,   "r.original :op: ''", {qw|= =  != <>|} ],
      [ str   => 'r.original :op: :value:', {qw|= =  != <>|} ],
      [ str   => 'r.original ILIKE :value:', {'~',1}, process => \'like' ]
    ],
    released => [
      [ undef,   'r.released :op: 0', {qw|= =  != <>|} ],
      [ str   => 'r.released :op: :value:', {qw|= =  != <>  > >  < <  <= <=  >= >=|}, process => \&parsedate ],
    ],
    patch    => [ [ bool => 'r.patch = :value:',    {'=',1} ] ],
    freeware => [ [ bool => 'r.freeware = :value:', {'=',1} ] ],
    doujin   => [ [ bool => 'r.doujin = :value:',   {'=',1} ] ],
    type => [
      [ str   => 'r.id :op:(SELECT rv.id FROM releases_vn rv WHERE rv.rtype = :value:)', {'=' => 'IN', '!=' => 'NOT IN'},
        process => sub { !$RELEASE_TYPE{$_[0]} ? \'No such release type' : $_[0] } ],
    ],
    gtin => [
      [ 'int' => 'r.gtin :op: :value:', {qw|= =  != <>|}, process => sub { length($_[0]) > 14 ? \'Too long GTIN code' : $_[0] } ],
    ],
    catalog => [
      [ str   => 'r.catalog :op: :value:', {qw|= =  != <>|} ],
    ],
    languages => [
      [ str   => 'r.id :op:(SELECT rl.id FROM releases_titles rl WHERE rl.lang = :value:)', {'=' => 'IN', '!=' => 'NOT IN'}, process => \'lang' ],
      [ stra  => 'r.id :op:(SELECT rl.id FROM releases_titles rl WHERE rl.lang IN(:value:))', {'=' => 'IN', '!=' => 'NOT IN'}, join => ',', process => \'lang' ],
    ],
    platforms => [
      [ str   => 'r.id :op:(SELECT rp.id FROM releases_platforms rp WHERE rp.platform = :value:)', {'=' => 'IN', '!=' => 'NOT IN'}, process => \'plat' ],
      [ stra  => 'r.id :op:(SELECT rp.id FROM releases_platforms rp WHERE rp.platform IN(:value:))', {'=' => 'IN', '!=' => 'NOT IN'}, join => ',', process => \'plat' ],
    ],
  },
);

my %GET_PRODUCER = (
  sql     => 'SELECT %s FROM producers p WHERE NOT p.hidden AND (%s) %s',
  select  => 'p.id',
  proc    => sub {
    $_[0]{id} = idnum $_[0]{id}
  },
  sortdef => 'id',
  sorts   => {
    id => 'p.id %s',
    name => 'p.name %s, p.id',
  },
  flags  => {
    basic => {
      select => 'p.type, p.name, p.original, p.lang AS language',
      proc => sub {
        $_[0]{original}    ||= undef;
      },
    },
    details => {
      select => 'p.website, p.l_wp, p.l_wikidata, p.desc AS description, p.alias AS aliases',
      proc => sub {
        $_[0]{description} ||= undef;
        $_[0]{aliases}     ||= undef;
        $_[0]{links} = {
          homepage  => delete($_[0]{website})||undef,
          wikipedia => delete $_[0]{l_wp},
          wikidata  => formatwd(delete $_[0]{l_wikidata}),
        };
      },
    },
    relations => {
      fetch => [[ 'id', 'SELECT pl.id AS pid, p.id, pl.relation, p.name, p.original FROM producers_relations pl
                    JOIN producers p ON p.id = pl.pid WHERE pl.id IN(%s)',
        sub { my($n, $r) = @_;
          for my $i (@$n) {
            $i->{relations} = [ grep $i->{id} eq $_->{pid}, @$r ];
          }
          for (@$r) {
            $_->{id} = idnum $_->{id};
            $_->{original} ||= undef;
            delete $_->{pid};
          }
        },
      ]],
    },
  },
  filters => {
    id => [
      [ 'int' => 'p.id :op: :value:', {qw|= =  != <>  > >  < <  <= <=  >= >=|}, process => \'p' ],
      [ inta  => 'p.id :op:(:value:)', {'=' => 'IN', '!=' => 'NOT IN'}, join => ',', process => \'p' ],
    ],
    name => [
      [ str   => 'p.name :op: :value:', {qw|= =  != <>|} ],
      [ str   => 'p.name ILIKE :value:', {'~',1}, process => \'like' ],
    ],
    original => [
      [ undef,   "p.original :op: ''", {qw|= =  != <>|} ],
      [ str   => 'p.original :op: :value:', {qw|= =  != <>|} ],
      [ str   => 'p.original ILIKE :value:', {'~',1}, process => \'like' ]
    ],
    type => [
      [ str   => 'p.type :op: :value:', {qw|= =  != <>|},
        process => sub { !$PRODUCER_TYPE{$_[0]} ? \'No such producer type' : $_[0] } ],
    ],
    language => [
      [ str   => 'p.lang :op: :value:', {qw|= =  != <>|}, process => \'lang' ],
      [ stra  => 'p.lang :op:(:value:)', {'=' => 'IN', '!=' => 'NOT IN'}, join => ',', process => \'lang' ],
    ],
    search => [
      [ str   => 'p.c_search LIKE ALL (search_query(:value:))', {'~',1} ],
    ],
  },
);

my %GET_CHARACTER = (
  sql     => 'SELECT %s FROM chars c LEFT JOIN images i ON i.id = c.image WHERE NOT c.hidden AND (%s) %s',
  select  => 'c.id',
  proc    => sub {
    $_[0]{id} = idnum $_[0]{id};
  },
  sortdef => 'id',
  sorts   => {
    id => 'c.id %s',
    name => 'c.name %s, c.id',
  },
  flags  => {
    basic => {
      select => 'c.name, c.original, c.gender, c.spoil_gender, c.bloodt, c.b_day, c.b_month',
      proc => sub {
        $_[0]{original} ||= undef;
        $_[0]{gender}   = undef if $_[0]{gender} eq 'unknown';
        $_[0]{bloodt}   = undef if $_[0]{bloodt} eq 'unknown';
        $_[0]{birthday} = [ delete($_[0]{b_day})*1||undef, delete($_[0]{b_month})*1||undef ];
      },
    },
    details => {
      select => 'c.alias AS aliases, c.image, i.c_sexual_avg, i.c_violence_avg, i.c_votecount, i.width AS image_width, i.height AS image_height, c."desc" AS description, c.age',
      proc => sub {
        $_[0]{aliases}     ||= undef;
        $_[0]{description} ||= undef;
        $_[0]{image}       = $_[0]{image} ? imgurl $_[0]{image} : undef;
        $_[0]{image_flagging} = image_flagging $_[0]{image}, $_[0];
        $_[0]{image_width}  *=1 if defined $_[0]{image_width};
        $_[0]{image_height} *=1 if defined $_[0]{image_height};
        $_[0]{age}*=1 if defined $_[0]{age};
      },
    },
    meas => {
      select => 'c.s_bust AS bust, c.s_waist AS waist, c.s_hip AS hip, c.height, c.weight, c.cup_size',
      proc => sub {
        $_[0]{$_} = $_[0]{$_} ? $_[0]{$_}*1 : undef for(qw|bust waist hip height weight|);
        $_[0]{cup_size} ||= undef;
      },
    },
    traits => {
      fetch => [[ 'id', 'SELECT id, tid, spoil FROM chars_traits WHERE id IN(%s)',
        sub { my($n, $r) = @_;
          for my $i (@$n) {
            $i->{traits} = [ map [ idnum($_->{tid}), $_->{spoil}*1 ], grep $i->{id} eq $_->{id}, @$r ];
          }
        },
      ]],
    },
    vns => {
      fetch => [[ 'id', 'SELECT id, vid, rid, spoil, role FROM chars_vns WHERE id IN(%s)',
        sub { my($n, $r) = @_;
          for my $i (@$n) {
            $i->{vns} = [ map [ idnum($_->{vid}), idnum($_->{rid}||0), $_->{spoil}*1, $_->{role} ], grep $i->{id} eq $_->{id}, @$r ];
          }
        },
      ]],
    },
    voiced => {
      fetch => [[ 'id', 'SELECT vs.cid, sa.id, sa.aid, vs.id AS vid, vs.note
          FROM vn_seiyuu vs JOIN staff_alias sa ON sa.aid = vs.aid JOIN vn v ON v.id = vs.id JOIN staff s ON s.id = sa.id
          WHERE vs.cid IN(%s) AND NOT v.hidden AND NOT s.hidden',
        sub { my($n, $r) = @_;
          for my $i (@$n) {
            $i->{voiced} = [ grep $i->{id} eq $_->{cid}, @$r ];
          }
          for (@$r) {
            $_->{id}  = idnum $_->{id};
            $_->{aid}*=1;
            $_->{vid} = idnum $_->{vid};
            $_->{note} ||= undef;
            delete $_->{cid};
          }
        },
      ]]
    },
    instances => {
      fetch => [[ 'id', 'SELECT c2.id AS cid, c.id, c.name, c.original, c2.main_spoil AS spoiler FROM chars c2 JOIN chars c ON c.id = c2.main OR c.main = c2.main WHERE c2.id IN(%s)
                  UNION SELECT c.main AS cid, c.id, c.name, c.original,  c.main_spoil AS spoiler FROM chars c WHERE c.main IN(%1$s)',
        sub { my($n, $r) = @_;
          for my $i (@$n) {
            $i->{instances} = [ grep $i->{id} eq $_->{cid} && $_->{id} ne $i->{id}, @$r ];
          }
          for (@$r) {
            $_->{id} = idnum $_->{id};
            $_->{original} ||= undef;
            $_->{spoiler}*=1;
            delete $_->{cid};
          }
        }
      ]]
    },
  },
  filters => {
    id => [
      [ 'int' => 'c.id :op: :value:', {qw|= =  != <>  > >  < <  <= <=  >= >=|}, process => \'c' ],
      [ inta  => 'c.id :op:(:value:)', {'=' => 'IN', '!=' => 'NOT IN'}, process => \'c', join => ',' ],
    ],
    name => [
      [ str   => 'c.name :op: :value:', {qw|= =  != <>|} ],
      [ str   => 'c.name ILIKE :value:', {'~',1}, process => \'like' ],
    ],
    original => [
      [ undef,   "c.original :op: ''", {qw|= =  != <>|} ],
      [ str   => 'c.original :op: :value:', {qw|= =  != <>|} ],
      [ str   => 'c.original ILIKE :value:', {'~',1}, process => \'like' ]
    ],
    search => [
      [ str   => 'c.c_search LIKE ALL (search_query(:value:))', {'~',1} ],
    ],
    vn => [
      [ 'int' => 'c.id IN(SELECT cv.id FROM chars_vns cv WHERE cv.vid = :value:)', {'=',1}, process => \'v' ],
      [ inta  => 'c.id IN(SELECT cv.id FROM chars_vns cv WHERE cv.vid IN(:value:))', {'=',1}, process => \'v', join => ',' ],
    ],
    traits => [
      [ int   => 'c.id :op:(SELECT tc.cid FROM traits_chars tc WHERE tc.tid = :value:)',   {'=' => 'IN', '!=' => 'NOT IN'}, process => \'i' ],
      [ inta  => 'c.id :op:(SELECT tc.cid FROM traits_chars tc WHERE tc.tid IN(:value:))', {'=' => 'IN', '!=' => 'NOT IN'}, join => ',', process => \'i' ],
    ],
  },
);


my %GET_STAFF = (
  sql     => 'SELECT %s FROM staff s JOIN staff_alias sa ON sa.aid = s.aid WHERE NOT s.hidden AND (%s) %s',
  select  => 's.id',
  proc    => sub {
    $_[0]{id} = idnum $_[0]{id};
  },
  sortdef => 'id',
  sorts   => {
    id => 's.id %s'
  },
  flags  => {
    basic => {
      select => 'sa.name, sa.original, s.gender, s.lang AS language',
      proc => sub {
        $_[0]{original} ||= undef;
        $_[0]{gender}   = undef if $_[0]{gender} eq 'unknown';
      },
    },
    details => {
      select => 's."desc" AS description, s.l_wp, s.l_site, s.l_twitter, s.l_anidb, s.l_wikidata, s.l_pixiv',
      proc => sub {
        $_[0]{description} ||= undef;
        $_[0]{links} = {
          wikipedia => delete($_[0]{l_wp})     ||undef,
          homepage  => delete($_[0]{l_site})   ||undef,
          twitter   => delete($_[0]{l_twitter})||undef,
          anidb     => (delete($_[0]{l_anidb})||0)*1||undef,
          wikidata  => formatwd(delete $_[0]{l_wikidata}),
          pixiv     => delete($_[0]{l_pixiv})*1||undef,
        };
      },
    },
    aliases => {
      select => 's.aid',
      proc => sub {
        $_[0]{main_alias} = delete($_[0]{aid})*1;
      },
      fetch => [[ 'id', 'SELECT id, aid, name, original FROM staff_alias WHERE id IN(%s)',
        sub { my($n, $r) = @_;
          for my $i (@$n) {
            $i->{aliases} = [ map [ $_->{aid}*1, $_->{name}, $_->{original}||undef ], grep $i->{id} eq $_->{id}, @$r ];
          }
        },
      ]],
    },
    vns => {
      fetch => [[ 'id', 'SELECT sa.id AS sid, sa.aid, vs.id, vs.role, vs.note
          FROM staff_alias sa JOIN vn_staff vs ON vs.aid = sa.aid JOIN vn v ON v.id = vs.id
          WHERE sa.id IN(%s) AND NOT v.hidden',
        sub { my($n, $r) = @_;
          for my $i (@$n) {
            $i->{vns} = [ grep $i->{id} eq $_->{sid}, @$r ];
          }
          for (@$r) {
            $_->{id} = idnum $_->{id};
            $_->{aid}*=1;
            $_->{note} ||= undef;
            delete $_->{sid};
          }
        },
      ]]
    },
    voiced => {
      fetch => [[ 'id', 'SELECT sa.id AS sid, sa.aid, vs.id, vs.cid, vs.note
          FROM staff_alias sa JOIN vn_seiyuu vs ON vs.aid = sa.aid JOIN vn v ON v.id = vs.id
          WHERE sa.id IN(%s) AND NOT v.hidden',
        sub { my($n, $r) = @_;
          for my $i (@$n) {
            $i->{voiced} = [ grep $i->{id} eq $_->{sid}, @$r ];
          }
          for (@$r) {
            $_->{id} = idnum $_->{id};
            $_->{aid}*=1;
            $_->{cid} = idnum $_->{cid};
            $_->{note} ||= undef;
            delete $_->{sid};
          }
        },
      ]]
    }
  },
  filters => {
    id => [
      [ 'int' => 's.id :op: :value:', {qw|= =  != <>  > >  < <  <= <=  >= >=|}, process => \'s' ],
      [ inta  => 's.id :op:(:value:)', {'=' => 'IN', '!=' => 'NOT IN'}, join => ',', process => \'s' ],
    ],
    aid => [
      [ 'int' => 's.id IN(SELECT sa.id FROM staff_alias sa WHERE sa.aid = :value:)', {'=',1}, range => [1,1e6] ],
      [ inta  => 's.id IN(SELECT sa.id FROM staff_alias sa WHERE sa.aid IN(:value:))', {'=',1}, range => [1,1e6], join => ',' ],
    ],
    search => [
      [ str   => 's.id IN(SELECT sa.id FROM staff_alias sa WHERE sa.c_search LIKE ALL (search_query(:value:)))', {'~',1} ],
    ],
  },
);


my %GET_QUOTE = (
  sql     => "SELECT %s FROM quotes q JOIN vnt v ON v.id = q.vid WHERE NOT v.hidden AND (%s) %s",
  select  => "v.id, v.title, q.quote",
  proc    => sub {
    $_[0]{id} = idnum $_[0]{id};
  },
  sortdef => 'random',
  sorts   => { id => 'q.vid %s', random => 'RANDOM() %s' },
  flags   => { basic => {} },
  filters => {
    id => [
      [ 'int' => 'q.vid :op: :value:', {qw|= =  != <>  > >  >= >=  < <  <= <=|}, process => \'v' ],
      [ inta  => 'q.vid :op:(:value:)', {'=' => 'IN', '!=' => 'NOT IN'}, join => ',', process => \'v' ],
    ]
  },
);


# All user ID filters consider uid=0 to be the logged in user. Needs a special processing function to handle that.
sub subst_user_id { my($id, $c) = @_; $id && $id =~ /^[1-9][0-9]{0,6}$/ ? "u$id" : ($c->{uid} || \'Not logged in.') }

my %GET_USER = (
  sql     => "SELECT %s FROM users u WHERE (%s) %s",
  select  => "id, username",
  proc    => sub {
    $_[0]{id} = idnum $_[0]{id};
  },
  sortdef => 'id',
  sorts   => { id => 'id %s' },
  flags   => { basic => {} },
  filters => {
    id => [
      [ 'int' => 'u.id :op: :value:', {qw|= =|}, process => \&subst_user_id ],
      [ inta  => 'u.id IN(:value:)', {'=',1}, join => ',', process => \&subst_user_id ],
    ],
    username => [
      [ str   => 'u.username :op: :value:', {qw|= =  != <>|} ],
      [ str   => 'u.username ILIKE :value:', {'~',1}, process => \'like' ],
      [ stra  => 'u.username IN(:value:)', {'=',1}, join => ',' ],
    ],
  },
);


# the uid filter for votelist/vnlist/wishlist
my $UID_FILTER = [ 'int' => 'uv.uid :op: :value:', {qw|= =|}, process => \&subst_user_id ];

# Similarly, a filter for 'vid'
my $VN_FILTER = [
  [ 'int' => 'uv.vid :op: :value:', {qw|= =  != <>  > >  < <  <= <=  >= >=|}, process => \'v' ],
  [ inta  => 'uv.vid :op:(:value:)', {'=' => 'IN', '!=' => 'NOT IN'}, process => \'v', join => ',' ],
];

my $UV_PUBLIC = 'EXISTS(SELECT 1 FROM ulist_vns_labels uvl JOIN ulist_labels ul ON ul.uid = uvl.uid AND ul.id = uvl.lbl WHERE uvl.uid = uv.uid AND uvl.vid = uv.vid AND NOT ul.private)';


my %GET_VOTELIST = (
  islist  => 1,
  sql     => "SELECT %s FROM ulist_vns uv WHERE uv.vote IS NOT NULL AND (%s) AND $UV_PUBLIC %s",
  sqluser => "SELECT %1\$s FROM ulist_vns uv WHERE uv.vote IS NOT NULL AND (%2\$s) AND (uid = %4\$s OR $UV_PUBLIC) %3\$s",
  select  => "uid AS uid, vid as vn, vote, extract('epoch' from vote_date) AS added",
  proc    => sub {
    $_[0]{uid} = idnum $_[0]{uid};
    $_[0]{vn}  = idnum $_[0]{vn};
    $_[0]{vote}*=1;
    $_[0]{added} = int $_[0]{added};
  },
  sortdef => 'vn',
  sorts   => { vn => 'vid %s' },
  flags   => { basic => {} },
  filters => { uid => [ $UID_FILTER ], vn => $VN_FILTER }
);

my $SQL_VNLIST = 'FROM ulist_vns uv LEFT JOIN ulist_vns_labels uvl ON uvl.uid = uv.uid AND uvl.vid = uv.vid AND uvl.lbl IN(1,2,3,4)'
              .' WHERE (EXISTS(SELECT 1 FROM ulist_vns_labels uvl WHERE uvl.uid = uv.uid AND uvl.vid = uv.vid AND uvl.lbl IN(1,2,3,4))'
              .' OR NOT EXISTS(SELECT 1 FROM ulist_vns_labels uvl WHERE uvl.uid = uv.uid AND uvl.vid = uv.vid))';

my %GET_VNLIST = (
  islist  => 1,
  sql     => "SELECT %s    $SQL_VNLIST AND (%s)    AND                    $UV_PUBLIC  GROUP BY uv.uid, uv.vid, uv.added, uv.notes %s",
  sqluser => "SELECT %1\$s $SQL_VNLIST AND (%2\$s) AND (uv.uid = %4\$s OR $UV_PUBLIC) GROUP BY uv.uid, uv.vid, uv.added, uv.notes %3\$s",
  select  => "uv.uid AS uid, uv.vid as vn, MAX(uvl.lbl) AS status, extract('epoch' from uv.added) AS added, uv.notes",
  proc    => sub {
    $_[0]{uid} = idnum $_[0]{uid};
    $_[0]{vn}  = idnum $_[0]{vn};
    $_[0]{status} = defined $_[0]{status} ? $_[0]{status}*1 : 0;
    $_[0]{added} = int $_[0]{added};
    $_[0]{notes} ||= undef;
  },
  sortdef => 'vn',
  sorts   => { vn => 'uv.vid %s' },
  flags   => { basic => {} },
  filters => { uid => [ $UID_FILTER ], vn => $VN_FILTER }
);

my $SQL_WISHLIST = "FROM ulist_vns uv JOIN ulist_vns_labels uvl ON uvl.uid = uv.uid AND uvl.vid = uv.vid JOIN ulist_labels ul ON ul.uid = uv.uid AND ul.id = uvl.lbl"
                ." WHERE (uvl.lbl IN(5,6) OR ul.label IN('Wishlist-Low','Wishlist-Medium','Wishlist-High'))";

my %GET_WISHLIST = (
  islist  => 1,
  sql     => "SELECT %s    $SQL_WISHLIST AND (%s)    AND                    NOT ul.private  GROUP BY uv.uid, uv.vid, uv.added %s",
  sqluser => "SELECT %1\$s $SQL_WISHLIST AND (%2\$s) AND (uv.uid = %4\$s OR NOT ul.private) GROUP BY uv.uid, uv.vid, uv.added %3\$s",
  select  => "uv.uid AS uid, uv.vid AS vn, MAX(ul.label) AS priority, extract('epoch' from uv.added) AS added",
  proc    => sub {
    $_[0]{uid} = idnum $_[0]{uid};
    $_[0]{vn}  = idnum $_[0]{vn};
    $_[0]{priority} = {'Wishlist-High' => 0, 'Wishlist-Medium' => 1, 'Wishlist-Low' => 2, 'Blacklist' => 3}->{$_[0]{priority}}//1;
    $_[0]{added} = int $_[0]{added};
  },
  sortdef => 'vn',
  sorts   => { vn => 'uv.vid %s' },
  flags   => { basic => {} },
  filters => { uid => [ $UID_FILTER ], vn => $VN_FILTER }
);

my %GET_ULIST_LABELS = (
  islist  => 1,
  sql     => 'SELECT %s FROM ulist_labels uv WHERE (%s) AND NOT uv.private %s',
  sqluser => 'SELECT %1$s FROM ulist_labels uv WHERE (%2$s) AND (uv.uid = %4$s OR NOT uv.private) %3$s',
  select  => 'uid AS uid, id, label, private',
  proc    => sub {
    $_[0]{uid} = idnum $_[0]{uid};
    $_[0]{id}  = idnum $_[0]{id};
    $_[0]{private} = $_[0]{private} =~ /^t/ ? TRUE : FALSE;
  },
  sortdef => 'id',
  sorts   => { id => 'id %s', label => 'label %s' },
  flags   => { basic => {} },
  filters => { uid => [ $UID_FILTER ] },
);

my $ULIST_PUBLIC = 'EXISTS(SELECT 1 FROM ulist_vns_labels uvl JOIN ulist_labels ul ON ul.uid = uvl.uid AND ul.id = uvl.lbl WHERE uvl.uid = uv.uid AND uvl.vid = uv.vid AND NOT ul.private)';
my %GET_ULIST = (
  islist  => 1,
  sql     => "SELECT %s FROM ulist_vns uv WHERE (%s) AND ($ULIST_PUBLIC) %s",
  sqluser => "SELECT %1\$s FROM ulist_vns uv WHERE (%2\$s) AND (uv.uid = %4\$s OR $ULIST_PUBLIC) %3\$s",
  select  => "uid AS uid, vid as vn, extract('epoch' from added) AS added, extract('epoch' from lastmod) AS lastmod, extract('epoch' from vote_date) AS voted, vote, started, finished, notes",
  proc    => sub {
    $_[0]{uid} = idnum $_[0]{uid};
    $_[0]{vn}  = idnum $_[0]{vn};
    $_[0]{added} = int $_[0]{added};
    $_[0]{lastmod} = int $_[0]{lastmod};
    $_[0]{voted} = int $_[0]{voted} if $_[0]{voted};
    $_[0]{vote}*=1 if $_[0]{vote};
    $_[0]{notes} ||= '';
  },
  sortdef => 'vn',
  sorts   => {
    uid     => 'uid %s',
    vn      => 'vid %s',
    added   => 'added %s',
    lastmod => 'lastmod %s',
    voted   => 'vote_date %s',
    vote    => 'vote %s',
  },
  flags   => {
    basic  => {},
    labels => {
      fetch => [[ ['uid','vn'], 'SELECT uvl.uid, uvl.vid, ul.id, ul.label
               FROM ulist_vns_labels uvl JOIN ulist_labels ul ON ul.uid = uvl.uid AND ul.id = uvl.lbl
              WHERE (uvl.uid,uvl.vid) IN(%s) AND (NOT ul.private OR uvl.uid = %s OR uvl.lbl = 7)',
        sub { my($n, $r) = @_;
          for my $i (@$n) {
            $i->{labels} = [ grep $i->{uid} eq $_->{uid} && $i->{vn} eq $_->{vid}, @$r ];
          }
          for (@$r) {
            $_->{id} = idnum $_->{id};
            delete $_->{uid};
            delete $_->{vid};
          }
        },
      ]]
    }
  },
  filters => {
    uid   => [ $UID_FILTER ],
    vn    => $VN_FILTER,
    label => [
      [ 'int' => 'EXISTS(SELECT 1 FROM ulist_vns_labels uvl JOIN ulist_labels ul ON ul.uid = uvl.uid AND ul.id = uvl.lbl
                          WHERE uvl.uid = uv.uid AND uvl.vid = uv.vid AND uvl.lbl = :value: AND (uvl.lbl = 7 OR NOT ul.private))', {'=',1}, range => [1,1e6] ],
    ],
  },
);


my %GET = (
  vn        => \%GET_VN,
  release   => \%GET_RELEASE,
  producer  => \%GET_PRODUCER,
  character => \%GET_CHARACTER,
  staff     => \%GET_STAFF,
  quote     => \%GET_QUOTE,
  user      => \%GET_USER,
  votelist  => \%GET_VOTELIST,
  vnlist    => \%GET_VNLIST,
  wishlist  => \%GET_WISHLIST,
  'ulist-labels' => \%GET_ULIST_LABELS,
  ulist     => \%GET_ULIST,
);


sub get {
  my($c, @arg) = @_;

  return cerr $c, parse => 'Invalid arguments to get command' if @arg < 3 || @arg > 4
    || ref($arg[0]) || ref($arg[1]) || ref($arg[2]) ne 'POE::Filter::VNDBAPI::filter'
    || exists($arg[3]) && ref($arg[3]) ne 'HASH';
  my $opt = $arg[3] || {};
  return cerr $c, badarg => 'Invalid argument for the "page" option', field => 'page'
    if defined($opt->{page}) && (ref($opt->{page}) || $opt->{page} !~ /^\d+$/ || $opt->{page} < 1 || $opt->{page} > 1e3);
  return cerr $c, badarg => '"reverse" option must be boolean', field => 'reverse'
    if defined($opt->{reverse}) && !JSON::XS::is_bool($opt->{reverse});

  my $type = $GET{$arg[0]};
  return cerr $c, 'gettype', "Unknown get type: '$arg[0]'" if !$type;
  return cerr $c, badarg => 'Invalid argument for the "results" option', field => 'results'
    if defined($opt->{results}) && (ref($opt->{results}) || $opt->{results} !~ /^\d+$/ || $opt->{results} < 1
        || $opt->{results} > ($type->{islist} ? $O{max_results_lists} : $O{max_results}));
  return cerr $c, badarg => 'Unknown sort field', field => 'sort'
    if defined($opt->{sort}) && (ref($opt->{sort}) || !$type->{sorts}{$opt->{sort}});

  my @flags = split /,/, $arg[1];
  return cerr $c, getinfo => 'No info flags specified' if !@flags;
  return cerr $c, getinfo => "Unknown info flag '$_'", flag => $_
    for (grep !$type->{flags}{$_}, @flags);

  $opt->{page} = $opt->{page}||1;
  $opt->{results} = $opt->{results}||$O{default_results};
  $opt->{sort} ||= $type->{sortdef};
  $opt->{reverse} = defined($opt->{reverse}) && $opt->{reverse};

  get_mainsql($c, $type, {type => $arg[0], info => \@flags, filters => $arg[2], opt => $opt});
}


sub get_filters {
  my($c, $p, $t, $field, $op, $value) = ($_[1], $_[2], $_[3], @{$_[0]});
  my %e = ( field => $field, op => $op, value => $value );

  # get the field that matches
  $t = $t->{$field};
  return cerr $c, filter => "Unknown field '$field'", %e if !$t;

  # get the type that matches
  $t = (grep +(
    # wrong operator? don't even look further!
    !defined($_->[2]{$op}) ? 0
    # undef
    : !defined($_->[0]) ? !defined($value)
    # int
    : $_->[0] eq 'int'  ? (defined($value) && !ref($value) && $value =~ /^-?\d+$/)
    # str
    : $_->[0] eq 'str'  ? defined($value) && !ref($value)
    # inta
    : $_->[0] eq 'inta' ? ref($value) eq 'ARRAY' && @$value && !grep(!defined($_) || ref($_) || $_ !~ /^-?\d+$/, @$value)
    # stra
    : $_->[0] eq 'stra' ? ref($value) eq 'ARRAY' && @$value && !grep(!defined($_) || ref($_), @$value)
    # bool
    : $_->[0] eq 'bool' ? defined($value) && JSON::XS::is_bool($value)
    # oops
    : die "Invalid filter type $_->[0]"
  ), @$t)[0];
  return cerr $c, filter => 'Wrong field/operator/expression type combination', %e if !$t;

  my($type, $sql, $ops, %o) = @$t;

  # substistute :op: in $sql, which is the same for all types
  $sql =~ s/:op:/$ops->{$op}/g;

  # no further processing required for type=undef
  return $sql if !defined $type;

  # split a string into an array of strings
  if($type eq 'str' && $o{split}) {
    $value = [ $o{split}->($value) ];
    # assume that this match failed if the function doesn't return anything useful
    return 'false' if !@$value || grep(!defined($_) || ref($_), @$value);
    $type = 'stra';
  }

  # pre-process the argument(s)
  my @values = ref($value) eq 'ARRAY' ? @$value : $value;
  for my $v (!$o{process} ? () : @values) {
    if(!ref $o{process}) {
      $v = sprintf $o{process}, $v;
    } elsif(ref($o{process}) eq 'CODE') {
      $v = $o{process}->($v, $c);
      return cerr $c, filter => $$v, %e if ref($v) eq 'SCALAR';
    } elsif(${$o{process}} eq 'like') {
      y/%//;
      $v = "%$v%";
    } elsif(${$o{process}} eq 'lang') {
      return cerr $c, filter => 'Invalid language code', %e if !$LANGUAGE{$v};
    } elsif(${$o{process}} eq 'plat') {
      return cerr $c, filter => 'Invalid platform code', %e if !$PLATFORM{$v};
    } elsif(length ${$o{process}} == 1) {
      return cerr $c, filter => 'Invalid identifier', %e if $v !~ /^[1-9][0-9]{0,6}$/;
      $v = ${$o{process}}.$v;
    }
  }

  # type=bool and no processing done? convert bool to what DBD::Pg wants
  $values[0] = $values[0] ? 1 : 0 if $type eq 'bool' && !$o{process};

  # Ensure that integers stay within their range
  for($o{range} ? @values : ()) {
    return cerr $c, filter => 'Integer out of range', %e if $_ < $o{range}[0] || $_ > $o{range}[1];
  }

  # type=str, int and bool are now quite simple
  if(!ref $value) {
    $sql =~ s/:value:/push @$p, $values[0]; '$'.scalar @$p/eg;
    return $sql;
  }

  # and do some processing for type=stra and type=inta
  my @parameters;
  if($o{serialize}) {
    for(@values) {
      my $v = $o{serialize};
      $v =~ s/:op:/$ops->{$op}/g;
      $v =~ s/:value:/push @$p, $_; '$'.scalar @$p/eg;
      $_ = $v;
    }
  } else {
    for(@values) {
      push @$p, $_;
      $_ = '$'.scalar @$p;
    }
  }
  my $joined = join defined $o{join} ? $o{join} : '', @values;
  $sql =~ s/:value:/$joined/eg;
  return $sql;
}


sub get_mainsql {
  my($c, $type, $get) = @_;

  my $select = join ', ',
    $type->{select} ? $type->{select} : (),
    map $type->{flags}{$_}{select} ? $type->{flags}{$_}{select} : (), @{$get->{info}};

  my @placeholders;
  my $where = encode_filters $get->{filters}, \&get_filters, $c, \@placeholders, $type->{filters};
  return if !$where;

  my $col = $type->{sorts}{ $get->{opt}{sort} };
  my $last = sprintf 'ORDER BY %s LIMIT %d OFFSET %d',
    sprintf($col, $get->{opt}{reverse} ? 'DESC' : 'ASC'),
    $get->{opt}{results}+1, $get->{opt}{results}*($get->{opt}{page}-1);

  my $sql = $type->{sql};
  return cerr $c, needlogin => 'Not logged in as a user' if !$sql && !$c->{uid};
  $sql = $type->{sqluser} if $c->{uid} && $type->{sqluser};

  no if $] >= 5.022, warnings => 'redundant';
  cpg $c, sprintf($sql, $select, $where, $last, $c->{uid} ? "'$c->{uid}'" : 'NULL'), \@placeholders, sub {
    my @res = $_[0]->rowsAsHashes;
    $get->{more} = pop(@res)&&1 if @res > $get->{opt}{results};
    $get->{list} = \@res;

    get_fetch($c, $type, $get);
  };
}


sub get_fetch {
  my($c, $type, $get) = @_;

  my @need = map { my $f = $type->{flags}{$_}{fetch}; $f ? @$f : () } @{$get->{info}};
  return get_final($c, $type, $get) if !@need || !@{$get->{list}};

  # Turn into a hash for easy self-deletion
  my %need = map +($_, $need[$_]), 0..$#need;

  for my $n (keys %need) {
    my $field = $need{$n}[0];
    my $ref = 1;
    my @ids = map { my $d=$_; ref $field ? @{$d}{@$field} : ($d->{$field}) } @{$get->{list}};
    my $ids = join ',', map { ref $field ? '('.join(',', map '$'.$ref++, @$field).')' : '$'.$ref++ } 1..@{$get->{list}};
    no warnings 'redundant';
    cpg $c, sprintf($need{$n}[1], $ids, $c->{uid} ? "'$c->{uid}'" : 'NULL'), \@ids, sub {
      $get->{fetched}{$n} = [ $need{$n}[2], [$_[0]->rowsAsHashes] ];
      delete $need{$n};
      get_final($c, $type, $get) if !keys %need;
    };
  }
}


sub get_final {
  my($c, $type, $get) = @_;

  # Run process callbacks (fetchprocs first, so that they have access to fields that may get deleted in later procs)
  for my $n (values %{$get->{fetched}}) {
    $n->[0]->($get->{list}, $n->[1]);
  }

  for my $p (
    $type->{proc} || (),
    map $type->{flags}{$_}{proc} || (), @{$get->{info}}
  ) {
    $p->($_) for @{$get->{list}};
  }

  my $num = @{$get->{list}};
  cres $c, [ results => { num => $num , more => $get->{more} ? TRUE : FALSE, items => $get->{list} }],
    'R:%2d  get %s %s %s {%s %s, page %d}', $num, $get->{type}, join(',', @{$get->{info}}), encode_filters($get->{filters}),
    $get->{opt}{sort}, $get->{opt}{reverse}?'desc':'asc', $get->{opt}{page};
}



sub set {
  my($c, @arg) = @_;

  my %types = (
    votelist => \&set_votelist,
    vnlist   => \&set_vnlist,
    wishlist => \&set_wishlist,
    ulist    => \&set_ulist,
  );

  return cerr $c, parse => 'Invalid arguments to set command' if @arg < 2 || @arg > 3 || ref($arg[0])
    || ref($arg[1]) || $arg[1] !~ /^\d+$/ || $arg[1] < 1 || $arg[1] > 1e6 || (defined($arg[2]) && ref($arg[2]) ne 'HASH');
  return cerr $c, 'settype', "Unknown set type: '$arg[0]'" if !$types{$arg[0]};
  return cerr $c, needlogin => 'Not logged in as a user' if !$c->{uid};

  my %obj = (
    c    => $c,
    type => $arg[0],
    id   => $arg[1],
    opt  => $arg[2]
  );
  $types{$obj{type}}->($c, \%obj);
}


# Wrapper around cpg that calls cres for a set command. First argument is the $obj created in set().
sub setpg {
  my($obj, $sql, $a) = @_;

  cpg $obj->{c}, $sql, $a, sub {
    my $args = $obj->{opt} ? JSON::XS->new->encode($obj->{opt}) : 'delete';
    cres $obj->{c}, ['ok'], 'R:%2d  set %s %d %s', $_[0]->cmdRows(), $obj->{type}, $obj->{id}, $args;
  };
}

sub set_ulist_ret {
  my($c, $obj) = @_;
  setpg $obj, 'SELECT update_users_ulist_stats($1)', [ $c->{uid} ]; # XXX: This can be deferred, to speed up batch updates over the same connection
}


sub set_votelist {
  my($c, $obj) = @_;

  return cpg $c, 'UPDATE ulist_vns SET vote = NULL, vote_date = NULL WHERE uid = $1 AND vid = $2', [ $c->{uid}, 'v'.$obj->{id} ], sub {
    set_ulist_ret $c, $obj
  } if !$obj->{opt};

  my($ev, $vv) = (exists($obj->{opt}{vote}), $obj->{opt}{vote});
  return cerr $c, missing => 'No vote given', field => 'vote' if !$ev;
  return cerr $c, badarg => 'Invalid vote', field => 'vote' if ref($vv) || !defined($vv) || $vv !~ /^\d+$/ || $vv < 10 || $vv > 100;

  cpg $c, 'INSERT INTO ulist_vns (uid, vid, vote, vote_date) VALUES ($1, $2, $3, NOW()) ON CONFLICT (uid, vid) DO UPDATE SET vote = $3, vote_date = NOW(), lastmod = NOW()',
    [ $c->{uid}, 'v'.$obj->{id}, $vv ], sub { set_ulist_ret $c, $obj; }
}


sub set_vnlist {
  my($c, $obj) = @_;

  # Bug: Also removes from wishlist and votelist.
  return cpg $c, 'DELETE FROM ulist_vns WHERE uid = $1 AND vid = $2', [ $c->{uid}, 'v'.$obj->{id} ], sub {
    set_ulist_ret $c, $obj;
  } if !$obj->{opt};

  my($es, $en, $vs, $vn) = (exists($obj->{opt}{status}), exists($obj->{opt}{notes}), $obj->{opt}{status}, $obj->{opt}{notes});
  return cerr $c, missing => 'No status or notes given', field => 'status,notes' if !$es && !$en;
  return cerr $c, badarg => 'Invalid status', field => 'status' if $es && (!defined($vs) || ref($vs) || $vs !~ /^[0-4]$/);
  return cerr $c, badarg => 'Invalid notes', field => 'notes' if $en && (ref($vn) || (defined($vn) && $vn =~ /[\r\n]/));

  $vs ||= 0;
  $vn ||= '';

  cpg $c, 'INSERT INTO ulist_vns (uid, vid, notes) VALUES ($1, $2, $3) ON CONFLICT (uid, vid) DO UPDATE SET lastmod = NOW()'.($en ? ', notes = $3' : ''),
    [ $c->{uid}, 'v'.$obj->{id}, $vn ], sub {
    if($es) {
      cpg $c, 'DELETE FROM ulist_vns_labels WHERE uid = $1 AND vid = $2 AND lbl IN(1,2,3,4)', [ $c->{uid}, 'v'.$obj->{id} ], sub {
        if($vs) {
          cpg $c, 'INSERT INTO ulist_vns_labels (uid, vid, lbl) VALUES($1, $2, $3)', [ $c->{uid}, 'v'.$obj->{id}, $vs ], sub {
            set_ulist_ret $c, $obj;
          }
        } else {
          set_ulist_ret $c, $obj;
        }
      }
    } else {
      set_ulist_ret $c, $obj;
    }
  }
}


sub set_wishlist {
  my($c, $obj) = @_;

  my $sql_label = "(lbl IN(5,6) OR lbl IN(SELECT id FROM ulist_labels WHERE uid = \$1 AND label IN('Wishlist-Low','Wishlist-High','Wishlist-Medium')))";

  # Bug: This will make it appear in the vnlist
  return cpg $c, "DELETE FROM ulist_vns_labels WHERE uid = \$1 AND vid = \$2 AND $sql_label",
    [ $c->{uid}, 'v'.$obj->{id} ], sub {
    set_ulist_ret $c, $obj;
  } if !$obj->{opt};

  my($ep, $vp) = (exists($obj->{opt}{priority}), $obj->{opt}{priority});
  return cerr $c, missing => 'No priority given', field => 'priority' if !$ep;
  return cerr $c, badarg => 'Invalid priority', field => 'priority' if ref($vp) || !defined($vp) || $vp !~ /^[0-3]$/;

  # Bug: High/Med/Low statuses are only set if a Wishlist-(High|Medium|Low) label exists; These should probably be created if they don't.
  cpg $c, 'INSERT INTO ulist_vns (uid, vid) VALUES ($1, $2) ON CONFLICT DO NOTHING', [ $c->{uid}, 'v'.$obj->{id} ], sub {
    cpg $c, "DELETE FROM ulist_vns_labels WHERE uid = \$1 AND vid = \$2 AND $sql_label", [ $c->{uid}, 'v'.$obj->{id} ], sub {
      cpg $c, 'INSERT INTO ulist_vns_labels (uid, vid, lbl) VALUES($1, $2, $3)', [ $c->{uid}, 'v'.$obj->{id}, $vp == 3 ? 6 : 5 ], sub {
        if($vp != 3) {
          cpg $c, 'INSERT INTO ulist_vns_labels (uid, vid, lbl) SELECT $1, $2, id FROM ulist_labels WHERE uid = $1 AND label = $3',
            [ $c->{uid}, 'v'.$obj->{id}, ['Wishlist-High', 'Wishlist-Medium', 'Wishlist-Low']->[$vp] ], sub {
            set_ulist_ret $c, $obj;
          }
        } else {
          set_ulist_ret $c, $obj;
        }
      }
    }
  }
}

sub set_ulist {
  my($c, $obj) = @_;

  return cpg $c, 'DELETE FROM ulist_vns WHERE uid = $1 AND vid = $2', [ $c->{uid}, 'v'.$obj->{id} ], sub {
    set_ulist_ret $c, $obj;
  } if !$obj->{opt};

  my $opt = $obj->{opt};
  my @set;
  my @bind = ($c->{uid}, 'v'.$obj->{id});

  if(exists $opt->{vote}) {
    return cerr $c, badarg => 'Invalid vote', field => 'vote' if defined($opt->{vote}) && (ref $opt->{vote} || $opt->{vote} !~ /^[0-9]+$/ || $opt->{vote} < 10 || $opt->{vote} > 100);
    if($opt->{vote}) {
      push @bind, $opt->{vote};
      push @set, 'vote_date = NOW()', 'vote = $'.@bind;
    } else {
      push @set, 'vote_date = NULL', 'vote = NULL';
    }
  }

  if(exists $opt->{notes}) {
    return cerr $c, badarg => 'Invalid notes', field => 'notes' if ref $opt->{notes};
    push @bind, $opt->{notes} // '';
    push @set, 'notes = $'.@bind;
  }

  for my $f ('started', 'finished') {
    if(exists $opt->{$f}) {
      return cerr $c, badarg => "Invalid $f date", field => $f if defined $opt->{$f} && (ref $opt->{$f} || $opt->{$f} !~ /^[0-9]{4}-[0-9]{2}-[0-9]{2}$/);
      push @bind, $opt->{$f};
      push @set, "$f = \$".@bind;
    }
  }

  if(exists $opt->{labels}) {
    return cerr $c, badarg => "Labels field expects an array", field => 'labels' if ref $opt->{labels} ne 'ARRAY';
    return cerr $c, badarg => "Invalid label: '$_'", field => 'labels' for grep !defined($_) || ref($_) || !/^[0-9]+$/, $opt->{labels}->@*;
    my %l = map +($_,1), grep $_ != 7, $opt->{labels}->@*;
    # XXX: This is ugly. Errors (especially: unknown labels) are ignored and
    # the entire set operation ought to run in a single transaction.
    pg_cmd 'SELECT lbl FROM ulist_vns_labels WHERE uid = $1 AND vid = $2', [ $c->{uid}, 'v'.$obj->{id} ], sub {
      return if pg_expect $_[0];
      my %ids = map +($_->{lbl}, 1), $_[0]->rowsAsHashes;
      pg_cmd 'INSERT INTO ulist_vns_labels (uid, vid, lbl) VALUES ($1,$2,$3)', [ $c->{uid}, 'v'.$obj->{id}, $_ ] for grep !$ids{$_}, keys %l;
      pg_cmd 'DELETE FROM ulist_vns_labels WHERE uid = $1 AND vid = $2 AND lbl = $3', [ $c->{uid}, 'v'.$obj->{id}, $_ ] for grep !$l{$_}, keys %ids;
    };
  }

  push @set, 'lastmod = NOW()' if @set || $opt->{labels};
  return cerr $c, missing => 'No fields to change' if !@set;

  cpg $c, 'INSERT INTO ulist_vns (uid, vid) VALUES ($1, $2) ON CONFLICT (uid, vid) DO NOTHING', [ $c->{uid}, 'v'.$obj->{id} ], sub {
    cpg $c, 'UPDATE ulist_vns SET '.join(',', @set).' WHERE uid = $1 AND vid = $2', \@bind, sub {
      set_ulist_ret $c, $obj;
    }
  };
}

1;
