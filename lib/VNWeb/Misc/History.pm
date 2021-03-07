package VNWeb::Misc::History;

use VNWeb::Prelude;


# Also used by Misc::HomePage and Misc::Feeds
sub fetch {
    my($id, $filt, $opt) = @_;

    my $where = sql_and
         !$id ? ()
         : $id =~ /^u/ ? sql 'c.requester =', \$id
         : $id =~ /^v/ && $filt->{r} ? sql 'c.itemid =', \$id, 'OR c.id IN(SELECT chid FROM releases_vn_hist WHERE vid =', \$id, ')' # This may need an index on releases_vn_hist.vid
         : sql('c.itemid =', \$id),

         $filt->{t} && $filt->{t}->@* ? sql_or map sql('c.itemid BETWEEN vndbid(', \"$_", ',1) AND vndbid_max(', \"$_", ')'), $filt->{t}->@* : (),
         $filt->{m} ? sql 'c.requester IS DISTINCT FROM \'u1\'' : (),

         $filt->{e} && $filt->{e} == 1 ? sql 'c.rev <> 1' : (),
         $filt->{e} && $filt->{e} ==-1 ? sql 'c.rev = 1' : (),

         $filt->{h} ? sql $filt->{h} == 1 ? 'NOT' : '',
            'EXISTS(SELECT 1 FROM changes c_i
                WHERE c_i.itemid = c.itemid AND c_i.ihid
                  AND c_i.rev = (SELECT MAX(c_ii.rev) FROM changes c_ii WHERE c_ii.itemid = c.itemid))' : ();

    my($lst, $np) = tuwf->dbPagei({ page => $filt->{p}, results => $opt->{results}||50 }, q{
        SELECT c.id, c.itemid, c.comments, c.rev,}, sql_totime('c.added'), q{ AS added, }, sql_user(), q{
          FROM changes c
          LEFT JOIN users u ON c.requester = u.id
         WHERE}, $where, q{
         ORDER BY c.id DESC
    });

    # Fetching the titles in a separate query is faster, for some reason.
    enrich_merge id => sql(q{
        SELECT id, title, original FROM (
                      SELECT chid, title, original FROM vn_hist
            UNION ALL SELECT chid, title, original FROM releases_hist
            UNION ALL SELECT chid, name,  original FROM producers_hist
            UNION ALL SELECT chid, name,  original FROM chars_hist
            UNION ALL SELECT chid, title, '' AS original FROM docs_hist
            UNION ALL SELECT sh.chid, name, original FROM staff_hist sh JOIN staff_alias_hist sah ON sah.chid = sh.chid AND sah.aid = sh.aid
            UNION ALL SELECT chid, name, '' AS original FROM tags_hist
                ) t(id, title, original)
        WHERE id IN}), $lst;
    ($lst, $np)
}


# Also used by User::Page.
# %opt: nopage => 1/0, results => $num
sub tablebox_ {
    my($id, $filt, %opt) = @_;

    my($lst, $np) = fetch $id, $filt, \%opt;

    my sub url { '?'.query_encode %$filt, p => $_ }

    paginate_ \&url, $filt->{p}, $np, 't' unless $opt{nopage};
    div_ class => 'mainbox browse history mainbox-overflow-hack', sub {
        table_ class => 'stripe', sub {
            thead_ sub { tr_ sub {
                td_ class => 'tc1_1', 'Rev.';
                td_ class => 'tc1_2', '';
                td_ class => 'tc2', 'Date';
                td_ class => 'tc3', 'User';
                td_ class => 'tc4', sub { txt_ 'Page'; debug_ $lst; };
            }};
            tr_ sub {
                my $i = $_;
                my $revurl = "/$i->{itemid}.$i->{rev}";

                td_ class => 'tc1_1', sub { a_ href => $revurl, $i->{itemid} };
                td_ class => 'tc1_2', sub { a_ href => $revurl, ".$i->{rev}" };
                td_ class => 'tc2', fmtdate $i->{added}, 'full';
                td_ class => 'tc3', sub { user_ $i };
                td_ class => 'tc4', sub {
                    a_ href => $revurl, title => $i->{original}, shorten $i->{title}, 80;
                    b_ class => 'grayedout', sub { lit_ bb_format $i->{comments}, maxlength => 150, inline => 1 };
                };
            } for @$lst;
        };
    };
    paginate_ \&url, $filt->{p}, $np, 'b' unless $opt{nopage};
}


sub filters_ {
    my($type) = @_;

    my @types = (
        [ v => 'Visual novels' ],
        [ g => 'Tags' ],
        [ r => 'Releases' ],
        [ p => 'Producers' ],
        [ s => 'Staff' ],
        [ c => 'Characters' ],
        [ d => 'Docs' ],
    );

    state $schema = tuwf->compile({ type => 'hash', keys => {
        # Types
        t => { type => 'array', scalar => 1, onerror => [map $_->[0], @types], values => { enum => [(map $_->[0], @types), 'a'] } },
        m => { onerror => undef, enum => [ 0, 1 ] }, # Automated edits
        h => { onerror => 0, enum => [ -1..1 ] }, # Hidden items
        e => { onerror => 0, enum => [ -1..1 ] }, # Existing/new items
        r => { onerror => 0, enum => [ 0, 1 ] },  # Include releases
        p => { page => 1 },
    }});
    my $filt = tuwf->validate(get => $schema)->data;

    $filt->{m} //= $type ? 0 : 1; # Exclude automated edits by default on the main 'recent changes' view.

    # For compat with old URLs, 't=a' means "everything except characters". Let's also weed out duplicates
    my %t = map +($_, 1), map $_ eq 'a' ? (qw|v r p s d|) : ($_), $filt->{t}->@*;
    $filt->{t} = keys %t == @types ? [] : [ keys %t ];

    # Not all filters apply everywhere
    delete @{$filt}{qw/ t e h /} if $type && $type ne 'u';
    delete $filt->{m} if $type eq 'u';
    delete $filt->{r} if $type ne 'v';

    my sub opt_ {
        my($type, $key, $val, $label, $checked) = @_;
        input_ type => $type, name => $key, id => "form_${key}{$val}", value => $val,
            $checked // $filt->{$key} eq $val ? (checked => 'checked') : ();
        label_ for => "form_${key}{$val}", $label;
    };

    form_ method => 'get', action => tuwf->reqPath(), sub {
        table_ style => 'margin: 0 auto', sub { tr_ sub {
            td_ style => 'padding: 10px', sub {
                p_ class => 'linkradio', sub {
                    join_ \&br_, sub {
                        opt_ checkbox => t => $_->[0], $_->[1], $t{$_->[0]}||0;
                    }, @types;
                }
            } if exists $filt->{t};

            td_ style => 'padding: 10px', sub {
                p_ class => 'linkradio', sub {
                    opt_ radio => e => 0, 'All'; em_ ' | ';
                    opt_ radio => e => 1, 'Only changes to existing items'; em_ ' | ';
                    opt_ radio => e =>-1, 'Only newly created items';
                } if exists $filt->{e};
                p_ class => 'linkradio', sub {
                    opt_ radio => h => 0, 'All'; em_ ' | ';
                    opt_ radio => h => 1, 'Only non-deleted items'; em_ ' | ';
                    opt_ radio => h =>-1, 'Only deleted';
                } if exists $filt->{h};
                p_ class => 'linkradio', sub {
                    opt_ checkbox => m => 0, 'Show automated edits' if !$type;
                    opt_ checkbox => m => 1, 'Hide automated edits' if $type;
                } if exists $filt->{m};
                p_ class => 'linkradio', sub {
                    opt_ checkbox => r => 1, 'Include releases'
                } if exists $filt->{r};
                input_ type => 'submit', class => 'submit', value => 'Update';
                debug_ $filt;
            };
        }};
    };
    $filt;
}


TUWF::get qr{/(?:([upvrcsdg][1-9][0-9]{0,6})/)?hist} => sub {
    my $id = tuwf->capture(1)||'';
    my $obj = dbobj $id;

    return tuwf->resNotFound if $id && !$obj->{id};

    my $title = $id ? "Edit history of $obj->{title}" : 'Recent changes';
    framework_ title => $title, dbobj => $obj, tab => 'hist',
    sub {
        my $filt;
        div_ class => 'mainbox', sub {
            h1_ $title;
            $filt = filters_($id =~ /^(.)/ or '');
        };
        tablebox_ $id, $filt;
    };
};

1;
