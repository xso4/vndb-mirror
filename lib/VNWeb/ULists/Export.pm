package VNWeb::ULists::Export;

use VNWeb::Prelude;
use VNWeb::ULists::Lib;
use FU::XMLWriter 'xml_', 'tag_';

# XXX: Reading someone's entire list into memory (multiple times even) is not
# the most efficient way to implement an export function. Might want to switch
# to an async background process for this to reduce the footprint of web
# workers.

sub data($uid) {
    # We'd like ISO7601/RFC3339 timestamps in UTC with accuracy to the second.
    my sub TZ($col,$name) { RAW qq{to_char($col at time zone 'utc', 'YYYY-MM-DD"T"HH24:MM:SS"Z"') as $name} }

    # XXX: This keeps the old "title"/"original" fields for compatibility, but
    # should the export take user title preferences into account instead? Or
    # export all known titles?
    my $d = {
        'export-date' => fu->SQL(select => TZ('NOW()', 'now'))->val,
        user   => fu->sql('SELECT id, username as name FROM users WHERE id = $1', $uid)->rowh,
        labels => fu->sql('SELECT id, label, private FROM ulist_labels WHERE uid = $1 ORDER BY id', $uid)->allh,
        vns    => fu->SQL('
            SELECT v.id, v.title, uv.vote, uv.started, uv.finished, uv.notes, uv.c_private, uv.labels,',
                   COMMA(TZ('uv.added', 'added'), TZ('uv.lastmod', 'lastmod'), TZ('uv.vote_date', 'vote_date')), '
              FROM ulist_vns uv
              JOIN vnt v ON v.id = uv.vid
             WHERE uv.uid =', $uid, '
             ORDER BY v.sorttitle')->allh,
        'length-votes' => fu->SQL('
            SELECT v.id, v.title, l.length, l.speed, l.private, l.notes, l.rid AS releases, ', TZ('l.date', 'date'), '
              FROM vn_length_votes l
              JOIN vnt v ON v.id = l.vid
             WHERE l.uid =', $uid, '
             ORDER BY v.sorttitle')->allh,
    };
    fu->enrich(aoh => 'releases', sub { SQL '
        SELECT rv.vid, r.id, r.title, r.released, rl.status, ', TZ('rl.added', 'added'), '
          FROM rlists rl
          JOIN releasest r ON r.id = rl.rid
          JOIN releases_vn rv ON rv.id = rl.rid
         WHERE rl.uid =', $uid, '
         ORDER BY r.released, r.id'
    }, $d->{vns});
    fu->enrich(merge => 1, sub { SQL '
        SELECT id, title, released FROM releasest WHERE id', IN $_, 'ORDER BY released, id'
    }, [map +($_->{releases} = [map +{id=>$_}, $_->{releases}->@*])->@*, $d->{'length-votes'}->@*]);
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


FU::get qr{/$RE{uid}/list-export/xml}, sub($uid) {
    fu->denied if !ulists_priv $uid;
    my $d = data $uid;
    fu->notfound if !$d->{user}{id};

    my %labels = map +($_->{id}, $_), $d->{labels}->@*;

    fu->set_header('content-disposition', sprintf 'attachment; filename="%s"', filename $d, 'xml');
    fu->set_header('content-type', 'application/xml');
    fu->set_body(xml_ {
    tag_ 'vndb-export' => version => '1.0', date => $d->{'export-date'}, sub {
        lit_ "\n";
        tag_ user => sub {
            tag_ name => $d->{user}{name};
            tag_ url => config->{url}.'/'.$d->{user}{id};
        };
        lit_ "\n";
        tag_ labels => sub {
            tag_ label => id => $_->{id}, label => $_->{label}, private => $_->{private}?'true':'false', undef for $d->{labels}->@*;
        };
        lit_ "\n";
        tag_ vns => sub {
            lit_ "\n";
            tag_ vn => id => $_->{id}, private => $_->{c_private}?'true':'false', sub {
                tag_ title => title($_->{title});
                tag_ label => id => $_, label => $labels{$_}{label}, undef for sort { $a <=> $b } $_->{labels}->@*;
                tag_ added => $_->{added};
                tag_ modified => $_->{lastmod} if $_->{added} ne $_->{lastmod};
                tag_ vote => timestamp => $_->{vote_date}, fmtvote $_->{vote} if $_->{vote};
                tag_ started => $_->{started} if $_->{started};
                tag_ finished => $_->{finished} if $_->{finished};
                tag_ notes => $_->{notes} if length $_->{notes};
                tag_ release => id => $_->{id}, sub {
                    tag_ title => title($_->{title});
                    tag_ 'release-date' => rdate $_->{released};
                    tag_ status => $RLIST_STATUS{$_->{status}};
                    tag_ added => $_->{added};
                } for $_->{releases}->@*;
                lit_ "\n";
            } for $d->{vns}->@*;
        };
        lit_ "\n";
        tag_ 'length-votes', sub {
            lit_ "\n";
            tag_ vn => id => $_->{id}, private => $_->{private}?'true':'false', sub {
                tag_ title => title($_->{title});
                tag_ date => $_->{date};
                tag_ minutes => $_->{length};
                tag_ speed => [qw/slow normal fast/]->[$_->{speed}] if defined $_->{speed};
                tag_ notes => $_->{notes} if length $_->{notes};
                tag_ release => id => $_->{id}, sub {
                    tag_ title => title($_->{title});
                    tag_ 'release-date' => rdate $_->{released};
                } for $_->{releases}->@*;
                lit_ "\n";
            } for $d->{'length-votes'}->@*;
        };
    }});
};

1;
