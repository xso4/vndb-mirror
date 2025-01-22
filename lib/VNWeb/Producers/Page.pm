package VNWeb::Producers::Page;

use VNWeb::Prelude;
use VNWeb::Releases::Lib;
use VNWeb::ULists::Lib;


sub rev_ {
    my($p) = @_;
    revision_ $p, sub{},
        [ name       => 'Name'           ],
        [ latin      => 'Name (latin)'   ],
        [ alias      => 'Aliases'        ],
        [ description=> 'Description'    ],
        [ type       => 'Type',          fmt => \%PRODUCER_TYPE ],
        [ lang       => 'Language',      fmt => \%LANGUAGE ],
        [ relations  => 'Relations',     fmt => sub {
            txt_ $PRODUCER_RELATION{$_->{relation}}{txt}.': ';
            a_ href => "/$_->{pid}", tattr $_;
        } ],
        $VNDB::ExtLinks::REVISION
}


sub info_ {
    my($p) = @_;

    p_ class => 'center', sub {
        txt_ $PRODUCER_TYPE{$p->{type}};
        br_;
        txt_ "Primary language: $LANGUAGE{$p->{lang}}{txt}";
        if(length $p->{alias}) {
            br_;
            txt_ 'a.k.a. ';
            txt_ $p->{alias} =~ s/\n/, /gr;
        }
        br_ if $p->{vislinks}->@*;
        join_ ' - ', sub { a_ href => $_->{url2}, $_->{label} }, $p->{vislinks}->@*;
    };

    my $s = tuwf->dbRowi('SELECT id, title FROM', staff_aliast, 'WHERE aid = main AND prod =', \$p->{id});
    my @rel;
    push @rel, [ 'Staff entry', [[ $s->{id}, $s ]] ] if $s->{id};

    my %rel;
    push $rel{$_->{relation}}->@*, $_ for $p->{relations}->@*;
    push @rel, map
        [ $PRODUCER_RELATION{$_}{txt}, [ map [ $_->{pid}, $_ ], $rel{$_}->@* ] ],
        grep $rel{$_}, keys %PRODUCER_RELATION
        if %rel;

    p_ class => 'center', sub {
        br_;
        join_ \&br_, sub {
            txt_ "$_->[0]: ";
            join_ ', ', sub { a_ href => "/$_->[0]", tattr $_->[1] }, $_->[1]->@*
        }, @rel;
    } if @rel;

    div_ class => 'description', sub { lit_ bb_format $p->{description} } if length $p->{description};
}


sub rel_ {
    my($p) = @_;

    my $r = tuwf->dbAlli('
        SELECT r.id, r.patch, r.released, rp.publisher, rp.developer
          FROM releases r
          JOIN releases_producers rp ON rp.id = r.id
         WHERE rp.pid =', \$p->{id}, ' AND NOT r.hidden
         ORDER BY r.released
    ');
    $_->{rtype} = 1 for @$r; # prevent enrich_release() from fetching rtypes
    enrich_vislinks r => 0, $r;
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
    enrich_vislinks p => 0, $p;

    my $tab = tuwf->capture('tab')
        || (auth && (tuwf->dbVali('SELECT prodrelexpand FROM users_prefs WHERE id=', \auth->uid) ? 'rel' : 'vn'))
        || 'rel';

    my $title = titleprefs_swap @{$p}{qw/ lang name latin /};
    framework_ title => $title->[1], index => !tuwf->capture('rev'), dbobj => $p, hiddenmsg => 1,
    og => {
        title       => $title->[1],
        description => bb_format($p->{description}, text => 1),
    },
    sub {
        rev_ $p if tuwf->capture('rev');
        article_ sub {
            itemmsg_ $p;
            h1_ tlang(@{$title}[0,1]), $title->[1];
            h2_ class => 'alttitle', tlang(@{$title}[2,3]), $title->[3] if $title->[3] && $title->[3] ne $title->[1];
            info_ $p;
        };
        nav_ class => 'right', sub {
            menu_ sub {
                li_ class => $tab eq 'vn'  ? 'tabselected' : undef, sub { a_ href => "/$p->{id}/vn",  'Visual Novels' };
                li_ class => $tab eq 'rel' ? 'tabselected' : undef, sub { a_ href => "/$p->{id}/rel", 'Releases' };
            };
        };
        article_ sub { rel_ $p } if $tab eq 'rel';
        article_ sub { vns_ $p } if $tab eq 'vn';
    }
};

1;
