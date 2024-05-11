
#
#  Multi::Core  -  handles spawning and logging
#

package Multi::Core;

use v5.36;
use AnyEvent;
use AnyEvent::Log;
use AnyEvent::Pg::Pool;
use Pg::PQ ':pgres';
use DBI;
use Fcntl 'LOCK_EX', 'LOCK_NB';
use Exporter 'import';
use VNDB::Config;

our @EXPORT = qw|pg pg_cmd pg_expect schedule push_watcher throttle|;


my $PG;
my %throttle; # id => timeout
my @watchers;


sub pg :prototype() { $PG }


# Pushes a watcher to the list of watchers that need to be kept alive for as
# long as Multi keeps running.
sub push_watcher {
  push @watchers, shift;
}


sub load_pg {
  $PG = AnyEvent::Pg::Pool->new(
    config->{Multi}{Core}{db_login},
    timeout => 600, # Some maintenance queries can take a while to run...
    on_error => sub { die "Lost connection to PostgreSQL\n"; },
    on_connect_error => sub { die "Lost connection to PostgreSQL\n"; },
  );

  # Test that we're connected, so that a connection failure results in a failure to start Multi.
  my $cv = AE::cv;
  my $w = pg->push_query(
    query => 'SELECT 1',
    on_result => sub { $_[2]->status == PGRES_TUPLES_OK ? $cv->send : die "Test query failed."; },
  );
  $cv->recv;
}


sub load_mods {
  for(keys %{ config->{Multi} }) {
    next if /^Core$/;
    my($mod, $args) = ($_, config->{Multi}{$_});
    next if !$args || ref($args) ne 'HASH';
    require "Multi/$mod.pm";
    # I'm surprised the strict pagma isn't complaining about this
    "Multi::$mod"->run(%$args);
  }
}


sub unload {
  AE::log info => 'Shutting down';
  @watchers = ();

  for(keys %{ config->{Multi} }) {
    next if /^Core$/;
    my($mod, $args) = ($_, config->{Multi}{$_});
    next if !$args || ref($args) ne 'HASH';
    no strict 'refs';
    ${"Multi::$mod\::"}{unload} && "Multi::$mod"->unload();
  }
}


sub run {
  my($quiet) = @_;

  open my $LOCK, '>', config->{var_path}.'/multi.lock' or die "multi.lock: $!\n";
  flock $LOCK, LOCK_EX|LOCK_NB or die "multi.lock: $!\n";

  my $stopcv = AE::cv;
  AnyEvent::Log::ctx('Multi')->attach(AnyEvent::Log::Ctx->new(level => config->{Multi}{Core}{log_level}||'trace',
    # Don't use log_to_file, it doesn't accept perl's unicode strings (and, in fact, crashes on them without logging anything).
    log_cb => sub {
      open(my $F, '>>:utf8', config->{Multi}{Core}{log_dir}.'/multi.log');
      print $F $_[0];
      print $_[0] unless $quiet;
    }
  ));
  $AnyEvent::Log::FILTER->level('fatal');

  load_pg;
  load_mods;
  push_watcher AE::signal TERM => sub { $stopcv->send };
  push_watcher AE::signal INT  => sub { $stopcv->send };
  AE::log info => "Starting Multi ".config->{version};
  push_watcher(schedule(60, 10*60, \&throttle_gc));

  $stopcv->recv;
  unload;
}


# Handy wrapper around AE::timer to schedule a function to be run at a fixed time.
# Args: offset, interval, sub.
# Eg. daily at 12:00 GMT: schedule 24*3600, 12*3600, sub { .. }.
sub schedule {
  my($o, $i, $s) = @_;
  AE::timer($i - ((AE::time() - $o) % $i), $i, $s);
}


# Args: Pg::PQ::Result, expected, identifier
#   expected =  0, PGRES_COMMAND_OK
#   expected != 0, PGRES_TUPLES_OK
#   expected = undef, either of the above
# Logs any unexpected results and returns 0 if the expectations were met.
sub pg_expect {
  my($res, $exp, $id) = @_;
  return 0 if !$exp && $res && $res->status == PGRES_COMMAND_OK;
  return 0 if ($exp || !defined $exp) && $res && $res->status == PGRES_TUPLES_OK;
  my $loc = sprintf '%s:%d%s', (caller)[0,2], $id ? ":$id" : '';
  AE::log alert => !$res
    ? sprintf 'AnyEvent::Pg error at %s', $loc : $res->errorMessage
    ? sprintf 'SQL error at %s: %s', $loc, $res->errorMessage
    : sprintf 'Unexpected status at %s: %s', $loc, $res->statusMessage;
  return 1;
}


# Wrapper around pg->push_query().
# Args: $query, \@args, sub {}
# The sub will be called on either on_error or on_done, and has two args: The
# result and the running time. Only a single on_result is expected. The result
# argument is undef on error.
# If no sub is provided or the sub argument is a string, a default sub will be
# used that just calls pg_expect and logs any errors.
# Unlike most AE watchers, this function does not return a watcher object and
# can not be cancelled.
sub pg_cmd {
  my($q, $a, $s) = @_;
  my $r;

  #AE::log debug => sprintf "%s:%d: %s | %s", (caller)[0,2], $q, $a ? join ', ', @$a : '';

  my $sub = !$s || !ref $s ? do {
    my $loc = sprintf '%s:%d%s', (caller)[0,2], $s ? ":$s" : '';
    sub { pg_expect $_[0], undef, $loc }
  } : $s;

  my $w; $w = pg->push_query(
    query => $q,
    $a ? (args => $a) : (),
    on_error => sub {
      undef $w;
      $sub->(undef, 0);
    },
    on_result => sub {
      if($r) {
        AE::log warn => "Received more than one result for query: $q";
        undef $w;
        $sub->(undef, 0);
      } else {
        $r = $_[2];
      }
    },
    on_done => sub {
      undef $w;
      $sub->($r, AE::now-$_[1]->last_query_start_time);
    },
  );
}


# Generic throttling function, returns the time before the action can be
# performed again if the action is throttled, or 0 if it's not throttled.
# Using a weight of 0 will just check the throttle without affecting it.
sub throttle {
  my($config, $id, $weight) = @_;
  my($interval, $burst) = @$config;
  $weight //= 1;
  my $n = AE::now;
  $throttle{$id} = $n if !$throttle{$id} || $throttle{$id} < $n;
  my $left = ($throttle{$id}-$n) - ($burst*$interval);
  return $left if $left > 0;
  $throttle{$id} += $interval*$weight;
  return 0;
}


sub throttle_gc {
  my $n = AE::now;
  delete $throttle{$_} for grep $throttle{$_} < $n, keys %throttle;
}



# Tiny class for forwarding output for STDERR/STDOUT to the log file using tie().
package Multi::Core::STDIO;

use base 'Tie::Handle';
sub TIEHANDLE { return bless \"$_[1]", $_[0] }
sub WRITE     {
  my($s, $msg) = @_;
  AE::log warn => "$$s: $msg";
}


1;

