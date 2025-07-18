package VNTask::Maintenance;

use v5.36;
use VNTask::Core;
use POSIX 'strftime';


sub cron($delay, $div, $off, $name, $sub) {
    task $name, delay => $delay, align_div => $div, align_add => $off, ref $sub eq 'CODE' ? $sub : sub($task) {
        $task->{txn}->exec($sub);
    };
}
#sub hourly { cron '45m',  '1h', @_ }
sub daily  { cron '20h', '24h', @_ }


daily '00:01:00', logrotate => sub {
    my $today = strftime '%Y%m%d', gmtime;
    my $oldest = strftime '%Y%m%d', gmtime(time - 30*24*3600);

    my $dir = config->{var_path}.'/log';
    opendir my $D, $dir or die "Unable to read $dir: $!";
    while (local $_ = readdir $D) {
        next if /^\./ || /~$/ || !-f "$dir/$_";
        if (/-([0-9]{8})$/) {
            unlink "$dir/$_" or warn "Unable to rm $dir/$_: $!" if $1 lt $oldest;
        } elsif (!-f "$dir/$_-$today") {
            rename "$dir/$_", "$dir/$_-$today" or warn "Unable to move $dir/$_: $!";
        }
    }
};


# VN cache uses current date to determine which releases have been "released", so should be updated daily.
# (Can be limited to only update VNs with releases around the current date, but this is fast enough)
daily '00:30:00', vncache => 'SELECT update_vncache(NULL)';


# Delete tags assigned to Multi that also have (possibly inherited) votes from other users.
daily '07:30:00', cleanmultitags => q{
    WITH RECURSIVE
      t_votes(tag,vid,uid) AS (SELECT tv.tag, tv.vid, tv.uid FROM tags_vn tv LEFT JOIN users u ON u.id = tv.uid WHERE tv.uid IS DISTINCT FROM 'u1' AND (u.id IS NULL OR u.perm_tag)),
      t_inherit(tag,vid,uid) AS (SELECT * FROM t_votes UNION SELECT tp.parent, th.vid, th.uid FROM t_inherit th JOIN tags_parents tp ON tp.id = th.tag),
      t_nonmulti(tag,vid) AS (SELECT DISTINCT tag, vid FROM t_inherit),
      t_del(tag,vid) AS (SELECT tv.tag, tv.vid FROM tags_vn tv JOIN t_nonmulti tn ON (tn.tag,tn.vid) = (tv.tag,tv.vid) WHERE tv.uid = 'u1')
    DELETE FROM tags_vn tv WHERE tv.uid = 'u1' AND EXISTS(SELECT 1 FROM t_del td WHERE (td.tag,td.vid) = (tv.tag,tv.vid))
};

daily '07:30:00.1', vnvotestats => 'SELECT update_vnvotestats()';

# These caches are only partially updated through triggers. Some actions (e.g.
# tag/trait tree changes, user permission changes, etc) do not trigger a cache
# refresh, so these must be run periodically.
daily '07:30:01', tagcache => 'SELECT tag_vn_calc(NULL)';
daily '07:30:02', traitcache => 'SELECT traits_chars_calc(NULL)';
daily '07:30:03', lengthcache => 'SELECT update_vn_length_cache(NULL)';
daily '07:30:04', imagecache => 'SELECT update_images_cache(NULL)';
daily '07:30:05', reviewcache => 'SELECT update_reviews_votes_cache(NULL)';
daily '07:30:06', quotescache => 'SELECT quotes_rand_calc()';

daily '07:30:07', deleteusers => 'SELECT user_delete()';
daily '07:30:08', rmunconfirmusers => "DELETE FROM users WHERE registered < NOW()-'1 week'::interval AND NOT email_confirmed";
daily '07:30:09', cleansessions => "DELETE FROM sessions WHERE expires < NOW() AND type <> 'api2'";

daily '07:30:10', cleannotifications => q{
    DELETE FROM notifications WHERE read < NOW()-'1 month'::interval;
    DELETE FROM notifications WHERE id IN (
        SELECT id FROM (SELECT id, row_number() OVER (PARTITION BY uid ORDER BY id DESC) > 500 from notifications) AS x(id,del) WHERE x.del
    );
};

daily '07:30:11', cleanthrottle => q{
    DELETE FROM login_throttle WHERE timeout < NOW();
    DELETE FROM reset_throttle WHERE timeout < NOW();
    DELETE FROM registration_throttle WHERE timeout < NOW();
};

# Shouldn't be necessary, but it's fast anyway
daily '07:30:12', statcache => 'SELECT update_stats_cache_full()';

1;
