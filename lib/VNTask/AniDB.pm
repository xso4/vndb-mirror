package VNTask::AniDB;

use v5.36;
use VNTask::Core;
use IO::Uncompress::Gunzip;


task 'anidb-titles', delay => '36h', align_div => '1d', align_add => '4h', sub($task) {
    my %titles; # id => [ romaji, kanji ]
    {
        my $res = http_get 'https://anidb.net/api/anime-titles.dat.gz', task => 'Anime Fetcher';
        die "ERROR fetching dump: $res->{Status} $res->{Reason}\n" if $res->{Status} ne 200;

        my $rd = IO::Uncompress::Gunzip->new(\$res->{Body});
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

1;
