
#
#  Multi::Maintenance  -  General maintenance functions
#

package Multi::Maintenance;

use strict;
use warnings;
use Multi::Core;
use POSIX 'strftime';
use VNDB::Config;


my $monthly;


sub run {
  push_watcher schedule 57*60, 3600, \&hourly; # Every hour at xx:57
  push_watcher schedule 7*3600+1800, 24*3600, \&daily; # 7:30 UTC, 30 minutes before the daily DB dumps are created
  set_monthly();
  logrotate();
}


sub unload {
  undef $monthly;
}


sub set_monthly {
  # Calculate the UNIX timestamp of 12:00 GMT of the first day of the next month.
  # We do this by simply incrementing the timestamp with one day and checking gmtime()
  # for a month change. This might not be very reliable, but should be enough for
  # our purposes.
  my $nextday = int((time+3)/86400+1)*86400 + 12*3600;
  my $thismonth = (gmtime)[5]*100+(gmtime)[4]; # year*100 + month, for easy comparing
  $nextday += 86400 while (gmtime $nextday)[5]*100+(gmtime $nextday)[4] <= $thismonth;
  $monthly = AE::timer $nextday-time(), 0, \&monthly;
}


sub log_res {
  my($id, $res, $time) = @_;
  return if pg_expect $res, undef, $id;
  AE::log info => sprintf 'Finished %s in %.3fs (%d rows)', $id, $time, $res->cmdRows;
}


sub hourly {
  pg_cmd 'SELECT update_vnvotestats()', undef, sub { log_res vnstats => @_ };
}



#
#  D A I L Y   J O B S
#


sub logrotate {
    my $today = strftime '%Y%m%d', localtime;
    my $oldest = strftime '%Y%m%d', localtime(time() - 30*24*3600);

    my $dir = config->{Multi}{Core}{log_dir};
    opendir my $D, $dir or AE::log warn => "Unable to read $dir: $!";
    while (local $_ = readdir $D) {
        next if /^\./ || /~$/ || !-f "$dir/$_";
        if (/-([0-9]{8})$/) {
            unlink "$dir/$_" or AE::log warn => "Unable to rm $dir/$_: $!" if $1 lt $oldest;
        } elsif (!-f "$dir/$_-$today") {
            rename "$dir/$_", "$dir/$_-$today" or AE::log warn => "Unable to move $dir/$_: $!";
        }
    }
    AE::log info => 'Logs rotated.';
}


my %dailies = (
  # Delete tags assigned to Multi that also have (possibly inherited) votes from other users.
  cleanmultitags => q|
    WITH RECURSIVE
      t_votes(tag,vid,uid) AS (SELECT tv.tag, tv.vid, tv.uid FROM tags_vn tv LEFT JOIN users u ON u.id = tv.uid WHERE tv.uid IS DISTINCT FROM 'u1' AND (u.id IS NULL OR u.perm_tag)),
      t_inherit(tag,vid,uid) AS (SELECT * FROM t_votes UNION SELECT tp.parent, th.vid, th.uid FROM t_inherit th JOIN tags_parents tp ON tp.id = th.tag),
      t_nonmulti(tag,vid) AS (SELECT DISTINCT tag, vid FROM t_inherit),
      t_del(tag,vid) AS (SELECT tv.tag, tv.vid FROM tags_vn tv JOIN t_nonmulti tn ON (tn.tag,tn.vid) = (tv.tag,tv.vid) WHERE tv.uid = 'u1')
    DELETE FROM tags_vn tv WHERE tv.uid = 'u1' AND EXISTS(SELECT 1 FROM t_del td WHERE (td.tag,td.vid) = (tv.tag,tv.vid))|,

  # takes about 50ms to 500ms to complete, depending on how many releases have been released within the past 5 days
  vncache_inc => q|
    SELECT update_vncache(id)
      FROM (
        SELECT DISTINCT rv.vid
          FROM releases r
          JOIN releases_vn rv ON rv.id = r.id
         WHERE r.released  > TO_CHAR(NOW() - '5 days'::interval, 'YYYYMMDD')::integer
           AND r.released <= TO_CHAR(NOW(), 'YYYYMMDD')::integer
      ) AS r(id)|,

  # takes about 6 seconds, OK
  tagcache => 'SELECT tag_vn_calc(NULL)',

  # takes about 11 seconds, OK
  traitcache => 'SELECT traits_chars_calc(NULL)',

  lengthcache => 'SELECT update_vn_length_cache(NULL)',

  # takes about 10 seconds, OK
  imagecache => 'SELECT update_images_cache(NULL)',

  reviewcache => 'SELECT update_reviews_votes_cache(NULL)',

  quotescache => 'SELECT quotes_rand_calc()',

  deleteusers        => q|SELECT user_delete()|,
  cleansessions      => q|DELETE FROM sessions       WHERE expires    < NOW() AND type <> 'api2'|,
  cleannotifications => q|DELETE FROM notifications  WHERE read       < NOW()-'1 month'::interval|,
  cleannotifications2=> q|DELETE FROM notifications  WHERE id IN (
    SELECT id FROM (SELECT id, row_number() OVER (PARTITION BY uid ORDER BY id DESC) > 500 from notifications) AS x(id,del) WHERE x.del)|,
  rmunconfirmusers   => q|DELETE FROM users          WHERE registered < NOW()-'1 week'::interval AND NOT email_confirmed|,
  cleanthrottle      => q|DELETE FROM login_throttle WHERE timeout    < NOW()|,
  cleanresthrottle   => q|DELETE FROM reset_throttle WHERE timeout    < NOW()|,
  cleanregthrottle   => q|DELETE FROM registration_throttle WHERE timeout < NOW()|,
);


sub run_daily {
  my($d, $sub) = @_;
  pg_cmd $dailies{$d}, undef, sub {
    log_res $d, @_;
    $sub->() if $sub;
  };
}


sub daily {
  my @l = sort keys %dailies;
  my $s; $s = sub {
    run_daily shift(@l), $s if @l;
  };
  $s->();
  logrotate;
}




#
#  M O N T H L Y   J O B S
#


my %monthlies = (
  # This only takes about 3 seconds to complete
  vncache_full => 'SELECT update_vncache(id) FROM vn',

  # This shouldn't really be necessary, the triggers in PgSQL should keep
  # these up-to-date nicely. But it takes less than a second, anyway.
  stats_cache  => 'SELECT update_stats_cache_full()',
);


sub run_monthly {
  my($d, $sub) = @_;
  pg_cmd $monthlies{$d}, undef, sub {
    log_res $d, @_;
    $sub->() if $sub;
  };
}


sub monthly {
  my @l = sort keys %monthlies;
  my $s; $s = sub {
    run_monthly shift(@l), $s if @l;
  };
  $s->();
  set_monthly;
}


1;
