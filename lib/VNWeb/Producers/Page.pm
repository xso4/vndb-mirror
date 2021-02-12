package VNWeb::Producers::Page;

use VNWeb::Prelude;
use VNWeb::Releases::Lib;


sub enrich_item {
    my($p) = @_;
    enrich_extlinks p => $p;
    enrich_merge pid => 'SELECT id AS pid, name, original FROM producers WHERE id IN', $p->{relations};
    $p->{relations} = [ sort { $a->{name} cmp $b->{name} || $a->{pid} <=> $b->{pid} } $p->{relations}->@* ];
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
            a_ href => "/$_->{pid}", title => $_->{original}||$_->{name}, $_->{name};
        } ],
        revision_extlinks 'p'
}


sub info_ {
    my($p) = @_;
    h1_ $p->{name};
    h2_ class => 'alttitle', lang => $p->{lang}, $p->{original} if length $p->{original};

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
        join_ ' - ', sub { a_ href => $_->[1], $_->[0] }, $p->{extlinks}->@*;
    };

    p_ class => 'center', sub {
        my %rel;
        push $rel{$_->{relation}}->@*, $_ for $p->{relations}->@*;
        br_;
        join_ \&br_, sub {
            txt_ $PRODUCER_RELATION{$_}{txt}.': ';
            join_ ', ', sub {
                a_ href => "/$_->{pid}", title => $_->{original}||$_->{name}, $_->{name};
            }, $rel{$_}->@*;
        }, grep $rel{$_}, keys %PRODUCER_RELATION;
    } if $p->{relations}->@*;

    p_ class => 'description', sub { lit_ bb_format $p->{desc} } if length $p->{desc};
}


sub rel_ {
    my($p) = @_;

    my $r = tuwf->dbAlli('
        SELECT r.id, r.type, r.patch, r.released, r.gtin, rp.publisher, rp.developer, ', sql_extlinks(r => 'r.'), '
          FROM releases r
          JOIN releases_producers rp ON rp.id = r.id
         WHERE rp.pid =', \$p->{id}, ' AND NOT r.hidden
         ORDER BY r.released, r.id
    ');
    enrich_extlinks r => $r;
    enrich_release $r;
    enrich vn => id => rid => sub { sql '
        SELECT rv.id as rid, v.id, v.title, v.original
          FROM vn v
          JOIN releases_vn rv ON rv.vid = v.id
         WHERE NOT v.hidden AND rv.id IN', $_, '
         ORDER BY v.title
    '}, $r;

    my(%vn, @vn);
    for my $rel (@$r) {
        for ($rel->{vn}->@*) {
            push @vn, $_ if !$vn{$_->{id}};
            push $vn{$_->{id}}->@*, $rel;
        }
    }

    h1_ 'Releases';
    debug_ $r;
    table_ class => 'releases', sub {
        for my $v (@vn) {
            tr_ class => 'vn', sub {
                # TODO: VN list status & management
                td_ colspan => 8, sub {
                    a_ href => "/$v->{id}", title => $v->{original}||$v->{title}, $v->{title};
                };
                my $ropt = { id => $v->{id}, prod => 1, lang => 1 };
                release_row_ $_, $ropt for $vn{$v->{id}}->@*;
            };
        }
    } if @$r;
    p_ 'This producer has no releases in the database.' if !@$r;
}


sub vns_ {
    my($p) = @_;
    my $v = tuwf->dbAlli(q{
        SELECT v.id, v.title, v.original, rels.developer, rels.publisher, rels.released
          FROM vn v
          JOIN (
               SELECT rv.vid, bool_or(rp.developer), bool_or(rp.publisher)
                    , COALESCE(MIN(r.released) FILTER(WHERE r.type <> 'trial'), MIN(r.released))
                 FROM releases_vn rv
                 JOIN releases r ON r.id = rv.id
                 JOIN releases_producers rp ON rp.id = rv.id
                WHERE NOT r.hidden AND rp.pid =}, \$p->{id}, '
                GROUP BY rv.vid
               ) rels(vid, developer, publisher, released) ON rels.vid = v.id
         WHERE NOT v.hidden
         ORDER BY rels.released
    ');

    h1_ 'Visual Novels';
    debug_ $v;
    # TODO: Perhaps something more table-like, also showing languages, platforms & VN list status
    ul_ class => 'prodvns', sub {
        li_ sub {
            span_ sub { rdate_ $_->{released} };
            a_ href => "/$_->{id}", title => $_->{original}||$_->{title}, $_->{title};
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

    my $pref = tuwf->reqCookie('prodrelexpand') ? 'vn' : 'rel';
    my $tab = tuwf->capture('tab') || $pref;
    tuwf->resCookie(prodrelexpand => $tab eq 'vn' ? 1 : undef, expires => time + 315360000) if $tab && $tab ne $pref;
    $tab = 'rel' if !$tab;

    framework_ title => $p->{name}, index => !tuwf->capture('rev'), dbobj => $p, hiddenmsg => 1,
    og => {
        title       => $p->{name},
        description => bb_format($p->{desc}, text => 1),
    },
    sub {
        rev_ $p if tuwf->capture('rev');
        div_ class => 'mainbox', sub {
            itemmsg_ $p;
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
