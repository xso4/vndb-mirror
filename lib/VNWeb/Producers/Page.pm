package VNWeb::Producers::Page;

use VNWeb::Prelude;
use VNWeb::Releases::Lib;
use VNWeb::ULists::Lib;


sub enrich_item {
    my($p) = @_;
    enrich_extlinks p => 0, $p;
    enrich_merge pid => sql('SELECT id AS pid, title, sorttitle FROM', producerst, 'p WHERE id IN'), $p->{relations};
    $p->{relations} = [ sort { $a->{sorttitle} cmp $b->{sorttitle} || idcmp($a->{pid}, $b->{pid}) } $p->{relations}->@* ];
}


sub rev_ {
    my($p) = @_;
    revision_ $p, \&enrich_item,
        [ name       => 'Name'           ],
        [ original   => 'Original name'  ],
        [ alias      => 'Aliases'        ],
        [ desc       => 'Description'    ],
        [ type       => 'Type',          fmt => \%PRODUCER_TYPE ],
        [ lang       => 'Language',      fmt => \%LANGUAGE ],
        [ relations  => 'Relations',     fmt => sub {
            txt_ $PRODUCER_RELATION{$_->{relation}}{txt}.': ';
            a_ href => "/$_->{pid}", tattr $_;
        } ],
        revision_extlinks 'p'
}


sub info_ {
    my($p) = @_;

    p_ class => 'center', sub {
        txt_ $PRODUCER_TYPE{$p->{type}};
        br_;
        txt_ "Primary language: $LANGUAGE{$p->{lang}}";
        if(length $p->{alias}) {
            br_;
            txt_ 'a.k.a. ';
            txt_ $p->{alias} =~ s/\n/, /gr;
        }
        br_ if $p->{extlinks}->@*;
        join_ ' - ', sub { a_ href => $_->{url2}, $_->{label} }, $p->{extlinks}->@*;
    };

    p_ class => 'center', sub {
        my %rel;
        push $rel{$_->{relation}}->@*, $_ for $p->{relations}->@*;
        br_;
        join_ \&br_, sub {
            txt_ $PRODUCER_RELATION{$_}{txt}.': ';
            join_ ', ', sub { a_ href => "/$_->{pid}", tattr $_ }, $rel{$_}->@*;
        }, grep $rel{$_}, keys %PRODUCER_RELATION;
    } if $p->{relations}->@*;

    div_ class => 'description', sub { lit_ bb_format $p->{desc} } if length $p->{desc};
}


sub rel_ {
    my($p) = @_;

    my $r = tuwf->dbAlli('
        SELECT r.id, r.patch, r.released, r.gtin, rp.publisher, rp.developer, ', sql_extlinks(r => 'r.'), '
          FROM releases r
          JOIN releases_producers rp ON rp.id = r.id
         WHERE rp.pid =', \$p->{id}, ' AND NOT r.hidden
         ORDER BY r.released
    ');
    $_->{rtype} = 1 for @$r; # prevent enrich_release() from fetching rtypes
    enrich_extlinks r => 0, $r;
    enrich_release $r;
    enrich vn => id => rid => sub { sql '
        SELECT rv.id as rid, rv.rtype, v.id, v.title
          FROM', vnt, 'v
          JOIN releases_vn rv ON rv.vid = v.id
         WHERE NOT v.hidden AND rv.id IN', $_, '
         ORDER BY v.title
    '}, $r;

    my(%vn, @vn);
    for my $rel (@$r) {
        for ($rel->{vn}->@*) {
            push @vn, $_ if !$vn{$_->{id}};
            push $vn{$_->{id}}->@*, [ $_->{rtype}, $rel ];
        }
    }
    enrich_ulists_widget \@vn;

    h1_ 'Releases';
    debug_ $r;
    table_ class => 'releases', sub {
        for my $v (@vn) {
            tr_ class => 'vn', sub {
                td_ colspan => 8, sub {
                    ulists_widget_ $v;
                    a_ href => "/$v->{id}", tattr $v;
                };
                my $ropt = { id => $v->{id}, prod => 1 };
                release_row_ $_, $ropt for sort_releases(
                    [ map { $_->[1]{rtype} = $_->[0]; $_->[1] } $vn{$v->{id}}->@* ]
                )->@*;
            };
        }
    } if @$r;
    p_ 'This producer has no releases in the database.' if !@$r;
}


sub vns_ {
    my($p) = @_;
    my $v = tuwf->dbAlli(q{
        SELECT v.id, v.title, rels.developer, rels.publisher, rels.released
          FROM}, vnt, q{v
          JOIN (
               SELECT rv.vid, bool_or(rp.developer), bool_or(rp.publisher)
                    , COALESCE(MIN(r.released) FILTER(WHERE rv.rtype <> 'trial'), MIN(r.released))
                 FROM releases_vn rv
                 JOIN releases r ON r.id = rv.id
                 JOIN releases_producers rp ON rp.id = rv.id
                WHERE NOT r.hidden AND rp.pid =}, \$p->{id}, '
                GROUP BY rv.vid
               ) rels(vid, developer, publisher, released) ON rels.vid = v.id
         WHERE NOT v.hidden
         ORDER BY rels.released, v.sorttitle
    ');

    h1_ 'Visual Novels';
    debug_ $v;
    enrich_ulists_widget $v;
    # TODO: Perhaps something more table-like, also showing languages, platforms & VN list status
    ul_ class => 'prodvns', sub {
        li_ sub {
            span_ sub { rdate_ $_->{released} };
            ulists_widget_ $_;
            a_ href => "/$_->{id}", tattr $_;
            span_ join ' & ',
                $_->{publisher} ? 'Publisher' : (),
                $_->{developer} ? 'Developer' : ();
        } for @$v;
    };
    p_ 'This producer has no releases in the database.' if !@$v;
}


TUWF::get qr{/$RE{prev}(?:/(?<tab>vn|rel))?}, sub {
    my $p = db_entry tuwf->captures('id', 'rev');
    return tuwf->resNotFound if !$p;
    enrich_item $p;

    my $tab = tuwf->capture('tab')
        || (auth && (tuwf->dbVali('SELECT prodrelexpand FROM users_prefs WHERE id=', \auth->uid) ? 'rel' : 'vn'))
        || 'rel';

    my $title = titleprefs_swap @{$p}{qw/ lang name original /};
    framework_ title => $title->[1], index => !tuwf->capture('rev'), dbobj => $p, hiddenmsg => 1,
    og => {
        title       => $title->[1],
        description => bb_format($p->{desc}, text => 1),
    },
    sub {
        rev_ $p if tuwf->capture('rev');
        div_ class => 'mainbox', sub {
            itemmsg_ $p;
            h1_ tlang(@{$title}[0,1]), $title->[1];
            h2_ class => 'alttitle', tlang(@{$title}[2,3]), $title->[3] if $title->[3] && $title->[3] ne $title->[1];
            info_ $p;
        };
        div_ class => 'maintabs right', sub {
            ul_ sub {
                li_ mkclass(tabselected => $tab eq 'vn'),  sub { a_ href => "/$p->{id}/vn",  'Visual Novels' };
                li_ mkclass(tabselected => $tab eq 'rel'), sub { a_ href => "/$p->{id}/rel", 'Releases' };
            };
        };
        div_ class => 'mainbox', sub { rel_ $p } if $tab eq 'rel';
        div_ class => 'mainbox', sub { vns_ $p } if $tab eq 'vn';
    }
};

1;
