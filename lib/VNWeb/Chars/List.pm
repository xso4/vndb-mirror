package VNWeb::Chars::List;

use VNWeb::Prelude;
use VNWeb::AdvSearch;
use VNWeb::Filters;
use VNWeb::Images::Lib;

our $TABLEOPTS = tableopts
    _pref => 'tableopts_c',
    _views => [qw|rows cards grid|];


# Also used by VNWeb::TT::TraitPage
sub listing_ {
    my($opt, $list, $count) = @_;

    my sub url { '?'.query_encode %$opt, @_ }
    paginate_ \&url, $opt->{p}, [$count, $opt->{s}->results], 't', $opt->{s};

    article_ class => 'browse charb', sub {
        table_ class => 'stripe', sub {
            tr_ sub {
                td_ class => 'tc1', sub {
                    abbr_ class => "icon-gen-$_->{gender}", title => $GENDER{$_->{gender}}, '' if $_->{gender} ne 'unknown';
                };
                td_ class => 'tc2', sub {
                    a_ href => "/$_->{id}", tattr $_;
                    small_ sub {
                        join_ ', ', sub { a_ href => "/$_->{id}", tattr $_ }, $_->{vn}->@*;
                    };
                };
            } for @$list;
        }
    } if $opt->{s}->rows;

    article_ class => 'charbcard', sub {
        my($w,$h) = (90,120);
        div_ sub {
            div_ sub {
                if($_->{image}) {
                    my($iw,$ih) = imgsize $_->{image}{width}*100, $_->{image}{height}*100, $w, $h;
                    image_ $_->{image}, alt => $_->{title}[1], width => $iw, height => $ih, url => "/$_->{id}", overlay => undef;
                } else {
                    txt_ 'no image';
                }
            };
            div_ sub {
                abbr_ class => "icon-gen-$_->{gender}", title => $GENDER{$_->{gender}}, '' if $_->{gender} ne 'unknown';
                a_ href => "/$_->{id}", tattr $_;
                br_;
                small_ sub {
                    join_ ', ', sub { a_ href => "/$_->{id}", tattr $_ }, $_->{vn}->@*;
                };
            };
        } for @$list;
    } if $opt->{s}->cards;


    article_ class => 'charbgrid', sub {
        a_ href => "/$_->{id}", title => $_->{title}[3],
            !$_->{image} || image_hidden($_->{image}) ? () : (style => 'background-image: url("'.imgurl($_->{image}{id}).'")'),
        sub {
            span_ $_->{title}[1];
        } for @$list;
    } if $opt->{s}->grid;

    paginate_ \&url, $opt->{p}, [$count, $opt->{s}->results], 'b';
}


# Also used by VNWeb::TT::TraitPage
sub enrich_listing {
    enrich vn => id => cid => sub { sql '
        SELECT DISTINCT cv.id AS cid, v.id, v.title, v.sorttitle
          FROM chars_vns cv
          JOIN', vnt, 'v ON v.id = cv.vid
         WHERE NOT v.hidden AND cv.spoil = 0 AND cv.id IN', $_, '
         ORDER BY v.sorttitle'
    }, @_;
}


TUWF::get qr{/c(?:/(?<char>all|[a-z0]))?}, sub {
    my $opt = tuwf->validate(get =>
        q => { searchquery => 1 },
        p => { upage => 1 },
        f => { advsearch_err => 'c' },
        ch=> { onerror => [], type => 'array', scalar => 1, values => { onerror => undef, enum => ['0', 'a'..'z'] } },
        fil=>{ onerror => '' },
        s => { tableopts => $TABLEOPTS },
    )->data;
    $opt->{ch} = $opt->{ch}[0];

    # compat with old URLs
    my $oldch = tuwf->capture('char');
    $opt->{ch} //= $oldch if defined $oldch && $oldch ne 'all';

    # URL compatibility with old filters
    if(!$opt->{f}->{query} && $opt->{fil}) {
        my $q = eval {
            my $f = filter_char_adv filter_parse c => $opt->{fil};
            tuwf->compile({ advsearch => 'c' })->validate(@$f > 1 ? $f : undef)->data;
        };
        return tuwf->resRedirect(tuwf->reqPath().'?'.query_encode(%$opt, fil => undef, f => $q), 'perm') if $q;
    }

    $opt->{f} = advsearch_default 'c' if !$opt->{f}{query} && !defined tuwf->reqGet('f');

    my $where = sql_and
        'NOT c.hidden', $opt->{f}->sql_where(),
        defined($opt->{ch}) ? sql 'match_firstchar(c.sorttitle, ', \$opt->{ch}, ')' : ();

    my $time = time;
    my($count, $list);
    db_maytimeout {
        $count = tuwf->dbVali('SELECT count(*) FROM', charst, 'c WHERE', sql_and $where, $opt->{q}->sql_where('c', 'c.id'));
        $list = $count ? tuwf->dbPagei({results => $opt->{s}->results(), page => $opt->{p}}, '
            SELECT c.id, c.title, c.gender, c.image
              FROM', charst, 'c', $opt->{q}->sql_join('c', 'c.id'), '
             WHERE', $where, '
             ORDER BY', $opt->{q} ? 'sc.score DESC, ' : (), 'c.sorttitle, c.id'
        ) : [];
    } || (($count, $list) = (undef, []));

    enrich_listing $list;
    enrich_image_obj image => $list if !$opt->{s}->rows;
    $time = time - $time;

    framework_ title => 'Browse characters', sub {
        form_ action => '/c', method => 'get', sub {
            article_ sub {
                h1_ 'Browse characters';
                searchbox_ c => $opt->{q}//'';
                p_ class => 'browseopts', sub {
                    button_ type => 'submit', name => 'ch', value => ($_//''), ($_//'') eq ($opt->{ch}//'') ? (class => 'optselected') : (), !defined $_ ? 'ALL' : $_ ? uc $_ : '#'
                    for (undef, 'a'..'z', 0);
                };
                input_ type => 'hidden', name => 'ch', value => $opt->{ch}//'';
                $opt->{f}->elm_($count, $time);
            };
            listing_ $opt, $list, $count if $count;
        }
    };
};

1;
