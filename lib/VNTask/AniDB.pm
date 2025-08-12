package VNTask::AniDB;

use v5.36;
use VNTask::Core;
use VNDB::Types '%ANIME_TYPE';
use IO::Uncompress::Gunzip;


task 'anidb-titles', delay => '36h', align_div => '1d', align_add => '4h', sub($task) {
    my %titles; # id => [ romaji, kanji ]
    {
        my $res = http_get 'https://anidb.net/api/anime-titles.dat.gz', task => 'Anime Fetcher';
        $res->expect(200);

        my $rd = IO::Uncompress::Gunzip->new(\$res->body);
        while (my $line = $rd->getline) {
            chomp $line;
            next if $line =~ /^#/ || !length $line;
            utf8::decode($line);
            my($id, $type, $lang, $title) = split /\|/, $line, 4;
            $titles{$id}[0] = $title if $type eq 1;
            $titles{$id}[1] = $title if $type eq 4 && $lang eq 'ja';
        }
    }

    my($unref, $updated, $off, $total) = (0,0,0, scalar keys %titles);
    while (1) {
        my $lst = $task->sql('SELECT id, title_romaji, title_kanji FROM anime WHERE id > $1 ORDER BY id LIMIT 50', $off)->flat;
        last if !@$lst;
        for my ($id, $romaji, $kanji) (@$lst) {
            $off = $id;
            my ($nromaji, $nkanji) = $titles{$id} ? $titles{$id}->@* : ();
            delete $titles{$id};
            if (!defined $nromaji) {
                my $rm = $task->sql('DELETE FROM anime WHERE id = $1 AND NOT EXISTS(SELECT 1 FROM vn_anime_hist WHERE aid = $1)', $id)->exec;
                # Still being referenced is not always an error, could be an old revision or deleted entry.
                warn $rm ? "Deleted a$id\n" : "a$id not found in titles dump, but still referenced.\n";
                $unref++;
            } elsif (($romaji//'') ne ($nromaji//'') || ($kanji//'') ne ($nkanji//'')) {
                $task->sql('UPDATE anime SET title_romaji = $1, title_kanji = $2 WHERE id = $3', $nromaji, $nkanji, $id)->exec;
                $updated++;
            }
        }
    }

    $task->sql('INSERT INTO anime (id, title_romaji, title_kanji) VALUES ($1, $2, $3)', $_, $titles{$_}[0], $titles{$_}[1])->exec
        for (keys %titles);

    $task->done('%d anime, %d new, %d updated, %d not found', $total, scalar keys %titles, $updated, $unref);
};


my $freq = 30*24*3600;

task 'anidb-info', delay => '10m', sub($task) {
    my($id, $lastfetch, undef, $next) = $task->sql("
        SELECT id, lastfetch
          FROM anime
         WHERE id IN(SELECT va.aid FROM vn_anime va JOIN vn v ON v.id = va.id WHERE NOT v.hidden)
         ORDER BY lastfetch NULLS FIRST LIMIT 2
    ")->flat->@*;

    return $task->done('no referenced anime in the database') if !$id;
    if ($lastfetch && $lastfetch + $freq > time) {
        $task->{nextrun} = $lastfetch + $freq;
        return $task->done('nothing to do yet');
    }
    $task->item($id);

    my $uri = sprintf 'http://api.anidb.net:9001/httpapi?request=anime&client=vnmulti&clientver=1&protover=1&aid=%d', $id;
    my $res = http_get $uri, task => 'Anime Fetcher';
    $res->expect(200);

    # Meh, I don't want to use a proper XML parser.
    my $body = $res->text;
    my $error = $body =~ m{<error[^>]*>(.+?)</error>} ? $1 : '';
    my $type = $body =~ m{<type[^>]*>(.+?)</type>} ? $1 : '';
    ($type) = (grep $ANIME_TYPE{$_} eq $type, keys %ANIME_TYPE)[0];
    my $year = $body =~ m{<startdate[^>]*>([0-9]{4})-} ? $1 : undef;

    # Dumb way to extract <identifier>s for a given type. Doesn't handle cases where an entity can have multiple identifiers or a <url>.
    my sub extractids($n) {
         return () if $body !~ m{<resource[^>]+type="$n">(.+?)</resource>}s;
         $1 =~ m{<identifier>(.+?)</identifier>}g;
    }
    my @ann = extractids 1;
    my @mal = extractids 2;

    $task->sql(
        'UPDATE anime SET lastfetch = NOW(), year = $1, type = $2, ann_id = $3, mal_id = $4 WHERE id = $5',
        $year, $type, @ann ? \@ann : undef, @mal ? \@mal : undef, $id
    )->exec;
    $task->done($error ? "ERROR: $error" : sprintf '%s-%s ann=%s  mal=%s', $type||'unknown', $year||'-', join(',',@ann), join(',',@mal));
    $next ||= $lastfetch;
    $task->{nextrun} = $next ? $next + $freq : time;
};

1;
