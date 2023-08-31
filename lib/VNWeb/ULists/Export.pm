package VNWeb::ULists::Export;

use TUWF::XML ':xml';
use VNWeb::Prelude;
use VNWeb::ULists::Lib;

# XXX: Reading someone's entire list into memory (multiple times even) is not
# the most efficient way to implement an export function. Might want to switch
# to an async background process for this to reduce the footprint of web
# workers.

sub data {
    my($uid) = @_;

    # We'd like ISO7601/RFC3339 timestamps in UTC with accuracy to the second.
    my sub tz { sql 'to_char(', $_[0], ' at time zone \'utc\',', \'YYYY-MM-DD"T"HH24:MM:SS"Z"', ') as', $_[1] }

    # XXX: This keeps the old "title"/"original" fields for compatibility, but
    # should the export take user title preferences into account instead? Or
    # export all known titles?
    my $d = {
        'export-date' => tuwf->dbVali(select => tz('NOW()', 'now')),
        user   => tuwf->dbRowi('SELECT id, username as name FROM users WHERE id =', \$uid),
        labels => tuwf->dbAlli('SELECT id, label, private FROM ulist_labels WHERE uid =', \$uid, 'ORDER BY id'),
        vns    => tuwf->dbAlli('
            SELECT v.id, v.title, uv.vote, uv.started, uv.finished, uv.notes, uv.c_private, uv.labels,',
                   sql_comma(tz('uv.added', 'added'), tz('uv.lastmod', 'lastmod'), tz('uv.vote_date', 'vote_date')), '
              FROM ulist_vns uv
              JOIN vnt v ON v.id = uv.vid
             WHERE uv.uid =', \$uid, '
             ORDER BY v.sorttitle'),
        'length-votes' => tuwf->dbAlli('
            SELECT v.id, v.title, l.length, l.speed, l.private, l.notes, l.rid::text[] AS releases, ', tz('l.date', 'date'), '
              FROM vn_length_votes l
              JOIN vnt v ON v.id = l.vid
             WHERE l.uid =', \$uid, '
             ORDER BY v.sorttitle'),
    };
    enrich releases => id => vid => sub { sql '
        SELECT rv.vid, r.id, r.title, r.released, rl.status, ', tz('rl.added', 'added'), '
          FROM rlists rl
          JOIN releasest r ON r.id = rl.rid
          JOIN releases_vn rv ON rv.id = rl.rid
         WHERE rl.uid =', \$uid, '
         ORDER BY r.released, r.id'
    }, $d->{vns};
    enrich_merge id => sub { sql '
        SELECT id, title, released FROM releasest WHERE id IN', $_, 'ORDER BY released, id'
    }, map +($_->{releases} = [map +{id=>$_}, $_->{releases}->@*]), $d->{'length-votes'}->@*;
    $d
}


sub filename {
    my($d, $ext) = @_;
    my $date = $d->{'export-date'} =~ s/[-TZ:]//rg;
    "vndb-list-export-$d->{user}{name}-$date.$ext"
}


sub title {
    my(@t) = $_[0]->@*;
    return (length($t[3]) && $t[3] ne $t[1] ? (original => $t[3]) : (), $t[1]);
}


TUWF::get qr{/$RE{uid}/list-export/xml}, sub {
    my $uid = tuwf->capture('id');
    return tuwf->resDenied if !ulists_own $uid;
    my $d = data $uid;
    return tuwf->resNotFound if !$d->{user}{id};

    tuwf->resHeader('Content-Disposition', sprintf 'attachment; filename="%s"', filename $d, 'xml');
    tuwf->resHeader('Content-Type', 'application/xml; charset=UTF-8');

    my %labels = map +($_->{id}, $_), $d->{labels}->@*;

    my $fd = tuwf->resFd;
    TUWF::XML->new(
        write  => sub { print $fd $_ for @_ },
        pretty => 2,
        default => 1,
    );
    xml;
    tag 'vndb-export' => version => '1.0', date => $d->{'export-date'}, sub {
        tag user => sub {
            tag name => $d->{user}{name};
            tag url => config->{url}.'/'.$d->{user}{id};
        };
        tag labels => sub {
            tag label => id => $_->{id}, label => $_->{label}, private => $_->{private}?'true':'false', undef for $d->{labels}->@*;
        };
        tag vns => sub {
            tag vn => id => $_->{id}, private => $_->{c_private}?'true':'false', sub {
                tag title => title($_->{title});
                tag label => id => $_, label => $labels{$_}{label}, undef for sort { $a <=> $b } $_->{labels}->@*;
                tag added => $_->{added};
                tag modified => $_->{lastmod} if $_->{added} ne $_->{lastmod};
                tag vote => timestamp => $_->{vote_date}, fmtvote $_->{vote} if $_->{vote};
                tag started => $_->{started} if $_->{started};
                tag finished => $_->{finished} if $_->{finished};
                tag notes => $_->{notes} if length $_->{notes};
                tag release => id => $_->{id}, sub {
                    tag title => title($_->{title});
                    tag 'release-date' => rdate $_->{released};
                    tag status => $RLIST_STATUS{$_->{status}};
                    tag added => $_->{added};
                } for $_->{releases}->@*;
            } for $d->{vns}->@*;
        };
        tag 'length-votes', sub {
            tag vn => id => $_->{id}, private => $_->{private}?'true':'false', sub {
                tag title => title($_->{title});
                tag date => $_->{date};
                tag hours => $_->{length};
                tag speed => [qw/slow normal fast/]->[$_->{speed}] if defined $_->{speed};
                tag notes => $_->{notes} if length $_->{notes};
                tag release => id => $_->{id}, sub {
                    tag title => title($_->{title});
                    tag 'release-date' => rdate $_->{released};
                } for $_->{releases}->@*;
            } for $d->{'length-votes'}->@*;
        };
    };
};

1;
