package VNWeb::Misc::History;

use VNWeb::Prelude;


# Also used by Misc::HomePage and Misc::Feeds
sub fetch {
    my($id, $filt, $opt) = @_;
    my $num = $opt->{results}||50;

    my $where = sql_and
         !$id ? ()
         : $id =~ /^u/ ? sql 'c.requester =', \$id
         : $id =~ /^v/ && $filt->{r} ? sql 'c.itemid =', \$id, 'OR c.id IN(SELECT chid FROM releases_vn_hist WHERE vid =', \$id, ')' # This may need an index on releases_vn_hist.vid
         : sql('c.itemid =', \$id),

         $filt->{t} && $filt->{t}->@* ? sql_or map sql('c.itemid BETWEEN vndbid(', \"$_", ',1) AND vndbid_max(', \"$_", ')'), $filt->{t}->@* : (),
         $filt->{m} ? sql 'c.requester IS DISTINCT FROM \'u1\'' : (),

         $filt->{e} && $filt->{e} == 1 ? sql 'c.rev <> 1' : (),
         $filt->{e} && $filt->{e} ==-1 ? sql 'c.rev = 1' : (),

         # -2 = awaiting mod, -1 = deleted, 0 = all, 1 = approved
         $filt->{h} ? sql
            'EXISTS(SELECT 1 FROM changes c_i
                WHERE c_i.itemid = c.itemid AND',
                    $filt->{h} == -2 ? 'c_i.ihid AND NOT c_i.ilock' :
                    $filt->{h} == -1 ? 'c_i.ihid AND c_i.ilock' : 'NOT c_i.ihid', '
                  AND c_i.rev = (SELECT MAX(c_ii.rev) FROM changes c_ii WHERE c_ii.itemid = c.itemid))' : (),

         (map $filt->{"cf$_"} && $filt->{"cf$_"}->@* > 0 ? sql
             '(c.c_chflags & ', \sum(map 1<<$_, $filt->{"cf$_"}->@*), '> 0
                OR c.itemid NOT BETWEEN vndbid(', \"$_", ', 1) AND vndbid_max(', \"$_", '))' : (), keys %CHFLAGS);

    my $lst = tuwf->dbAlli('
        SELECT c.id, c.itemid, c.comments, c.rev,', sql_totime('c.added'), 'AS added,', sql_user(), ', x.title, u.perm_dbmod AS rev_dbmod
          FROM (SELECT * FROM changes c WHERE', $where, ' ORDER BY c.id DESC LIMIT', \($num+1), 'OFFSET', \($num*($filt->{p}-1)), ') c
          JOIN item_info(NULL, c.itemid, c.rev) x ON true
          LEFT JOIN users u ON c.requester = u.id
         ORDER BY c.id DESC'
    );
    enrich rev_patrolled => id => id =>
        sql('SELECT c.id,', sql_user(), 'FROM changes_patrolled c JOIN users u ON u.id = c.uid WHERE c.id IN'), $lst
        if auth->permDbmod;
    my $np = @$lst > $num ? pop(@$lst)&&1 : 0;
    ($lst, $np)
}


# Also used by User::Page and VNWeb::HTML.
# %opt: nopage => 1/0, nouser => 1/0, results => $num
sub tablebox_ {
    my($id, $filt, %opt) = @_;

    my($lst, $np) = fetch $id, $filt, \%opt;

    my sub url { '?'.query_encode({%$filt, p => $_}) }

    paginate_ \&url, $filt->{p}, $np, 't' unless $opt{nopage};
    article_ class => 'browse history overflow-hack', sub {
        table_ class => 'stripe', sub {
            thead_ sub { tr_ sub {
                td_ class => 'tc1_0', '' if auth->permDbmod;
                td_ class => 'tc1_1', 'Rev.';
                td_ class => 'tc1_2', '';
                td_ class => 'tc2', 'Date';
                td_ class => 'tc3', 'User' unless $opt{nouser};
                td_ class => 'tc4', sub { txt_ 'Page'; debug_ $lst; };
            }};
            tr_ sub {
                my $i = $_;
                my $revurl = "/$i->{itemid}.$i->{rev}";

                td_ class => 'tc1_0', sub {
                    a_ href => "$revurl?patrolled=$i->{id}", sub {
                        revision_patrolled_ $i;
                    }
                } if auth->permDbmod;
                td_ class => 'tc1_1', sub { a_ href => $revurl, $i->{itemid} };
                td_ class => 'tc1_2', sub { a_ href => $revurl, ".$i->{rev}" };
                td_ class => 'tc2', fmtdate $i->{added}, 'full';
                td_ class => 'tc3', sub { user_ $i } unless $opt{nouser};
                td_ class => 'tc4', sub {
                    a_ href => $revurl, tattr $i;
                    small_ sub { lit_ bb_format $i->{comments}, maxlength => 150, inline => 1 };
                };
            } for @$lst;
        };
    };
    paginate_ \&url, $filt->{p}, $np, 'b' unless $opt{nopage};
}


sub filters_ {
    my($id, $type) = @_;

    my @types = (
        [ v => 'Visual novels' ],
        [ g => 'Tags' ],
        [ r => 'Releases' ],
        [ p => 'Producers' ],
        [ s => 'Staff' ],
        [ c => 'Characters' ],
        [ i => 'Traits' ],
        [ d => 'Docs' ],
    );

    state $schema = tuwf->compile({ type => 'hash', keys => {
        # Types
        t => { type => 'array', scalar => 1, onerror => [map $_->[0], @types], values => { enum => [(map $_->[0], @types), 'a'] } },
        m => { onerror => undef, enum => [ 0, 1 ] }, # Automated edits
        h => { onerror => 0, enum => [ -2..1 ] }, # Item status (the numbers dont make sense)
        e => { onerror => 0, enum => [ -1..1 ] }, # Existing/new items
        r => { onerror => 0, enum => [ 0, 1 ] },  # Include releases
        p => { page => 1 },
        (map +("cf$_" => { onerror => [], type => 'array', scalar => 1, values => { enum => [0..$#{$CHFLAGS{$_}}] } }), keys %CHFLAGS)
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
        table_ class => 'histoptions', sub { tr_ sub {
            td_ sub {
                select_ multiple => 1, size => scalar @types, name => 't', id => 'histoptions-t', sub {
                    option_ $t{$_->[0]} ? (selected => 1) : (), value => $_->[0], $_->[1] for @types;
                }
            } if exists $filt->{t};

            td_ class => $type eq $_ || ($filt->{t} && $filt->{t}->@* == 1 && $filt->{t}[0] eq $_) ? undef : 'hidden', id => "histoptions-cf$_", sub {
                my $k = $_;
                my $v = sum 0, map 1<<$_, $filt->{"cf$k"}->@*;
                my @lst = sort { $a->[1] cmp $b->[1] } map [$_, $CHFLAGS{$k}[$_]], 0..$#{$CHFLAGS{$k}};
                if ($type eq $k) {
                    my $available = tuwf->dbVali('SELECT bit_or(c_chflags) FROM changes WHERE itemid =', \$id)||~0;
                    @lst = grep $available & (1<<$_->[0]), @lst;
                }
                select_ multiple => 1, size => min(scalar @lst, scalar @types), name => "cf$k", sub {
                    option_ selected => $v & (1<<$_->[0]) ? 1 : undef, value => $_->[0], $_->[1] for (@lst);
                }
            } for (grep !$type || $type eq 'u' || $type eq $_, keys %CHFLAGS);

            td_ sub {
                p_ class => 'linkradio', sub {
                    opt_ radio => e => 0, 'All'; em_ ' | ';
                    opt_ radio => e => 1, 'Only changes to existing items'; em_ ' | ';
                    opt_ radio => e =>-1, 'Only newly created items';
                } if exists $filt->{e};
                p_ class => 'linkradio', sub {
                    opt_ radio => h => 0, 'All'; em_ ' | ';
                    opt_ radio => h => 1, 'Only public items'; em_ ' | ';
                    opt_ radio => h =>-1, 'Only deleted'; em_ ' | ';
                    opt_ radio => h =>-2, 'Only unapproved';
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


TUWF::get qr{/(?:([upvrcsdgi][1-9][0-9]{0,6})/)?hist} => sub {
    my $id = tuwf->capture(1)||'';
    my $obj = dbobj $id;

    return tuwf->resNotFound if $id && !$obj->{id};
    return tuwf->resNotFound if $id =~ /^u/ && $obj->{entry_hidden} && !auth->isMod;

    my $title = $id ? "Edit history of $obj->{title}[1]" : 'Recent changes';
    framework_ title => $title, dbobj => $obj, tab => 'hist', js => !!($id =~ /^(u|$)/),
    sub {
        my $filt;
        article_ sub {
            h1_ $title;
            $filt = filters_($id, $id =~ /^(.)/ ? $1 : '');
        };
        tablebox_ $id, $filt, nouser => scalar $id =~ /^u/;
    };
};

1;
