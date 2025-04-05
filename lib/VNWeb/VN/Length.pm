package VNWeb::VN::Length;

use VNWeb::Prelude;
use VNWeb::Releases::Lib;

# Also used from VN::Page
sub can_vote { auth->permDbmod || (auth->permLengthvote && !global_settings->{lockdown_edit}) }

sub opts {
    my($mode) = @_;
    tableopts
        date     => { name => 'Date',   sort_id => 0, sort_sql => 'l.date', sort_default => 'desc' },
        length   => { name => 'Time',   sort_id => 1, sort_sql => 'l.length' },
        speed    => { name => 'Speed',  sort_id => 2, sort_sql => 'l.speed ?o NULLS LAST, l.length' },
        $mode ne 'u' ? (
        username => { name => 'User',   sort_id => 3, sort_sql => 'u.username' } ) : (),
        $mode ne 'v' ? (
        title    => { name => 'Title',  sort_id => 4, sort_sql => 'v.sorttitle' } ) : ()
}
my %TABLEOPTS = map +($_, opts $_), '', 'v', 'u';


sub listing_ {
    my($opt, $url, $count, $list, $mode) = @_;

    paginate_ $url, $opt->{p}, [$count, $opt->{s}->results], 't';
    article_ class => 'browse lengthlist', sub {
        table_ class => 'stripe', sub {
            thead_ sub { tr_ sub {
                td_ class => 'tc1', sub { txt_ 'Date';   sortable_ 'date', $opt, $url };
                td_ class => 'tc2', sub { txt_ 'User';   sortable_ 'username', $opt, $url } if $mode ne 'u';
                td_ class => 'tc2', sub { txt_ 'Title';  sortable_ 'title', $opt, $url } if $mode ne 'v';
                td_ class => 'tc3', sub { txt_ 'Time';   sortable_ 'length', $opt, $url };
                td_ class => 'tc4', sub { txt_ 'Speed';  sortable_ 'speed', $opt, $url };
                td_ class => 'tc5', 'Rel';
                td_ class => 'tc6', 'Notes';
                td_ class => 'tc7', sub {
                    input_ type => 'submit', class => 'submit', value => 'Update', undef;
                } if auth->permDbmod;
            } };
            tr_ sub {
                td_ class => 'tc1', fmtdate $_->{date};
                td_ class => 'tc2', sub { user_ $_ } if $mode ne 'u';
                td_ class => 'tc2', sub {
                    a_ href => "/$_->{vid}", tattr $_;
                } if $mode ne 'v';
                td_ class => 'tc3'.($_->{ignore}?' grayedout':''), sub { vnlength_ $_->{length} };
                td_ class => 'tc4'.($_->{ignore}?' grayedout':''), ['Slow','Normal','Fast','-']->[$_->{speed}//3];
                td_ class => 'tc5', sub {
                    my %l = map +($_,1), map $_->{lang}->@*, $_->{rel}->@*;
                    abbr_ class => "icon-lang-$_", title => $LANGUAGE{$_}{txt}, '' for sort keys %l;
                    join_ ',', sub { a_ href => "/$_->{id}", $_->{id} }, sort { idcmp $a->{id}, $b->{id} } $_->{rel}->@*;
                };
                td_ class => 'tc6'.($_->{ignore}?' grayedout':''), sub {
                    small_ '(private) ' if $_->{private};
                    lit_ bb_format $_->{notes}, inline => 1;
                };
                td_ class => 'tc7', sub {
                    select_ name => "lv$_->{id}", sub {
                        option_ value => '', '--';
                        option_ value => 's0', 'slow';
                        option_ value => 's1', 'normal';
                        option_ value => 's2', 'fast';
                        option_ value => 'sn', 'uncounted';
                    };
                } if auth->permDbmod;
            } for @$list;
        };
    };
    paginate_ $url, $opt->{p}, [$count, $opt->{s}->results], 'b';
}


sub stats_ {
    my($o) = @_;
    my $stats = tuwf->dbAlli('
        SELECT speed, count(*) as count, avg(l.length) as avg
             , stddev_pop(l.length::real)::int as stddev
             , percentile_cont(', \0.5, ') WITHIN GROUP (ORDER BY l.length) AS median
          FROM vn_length_votes l
          LEFT JOIN users u ON u.id = l.uid
         WHERE u.perm_lengthvote IS DISTINCT FROM false AND l.speed IS NOT NULL AND NOT l.private AND l.vid =', \$o->{id}, '
         GROUP BY GROUPING SETS ((speed),()) ORDER BY speed'
    );
    return if !$stats->[0]{count};

    table_ style => 'margin: 0 auto', sub {
        thead_ sub { tr_ sub {
                td_ 'Speed';
                td_ 'Median';
                td_ 'Average';
                td_ 'Stddev';
                td_ '# Votes';
            } };
        tr_ sub {
            td_ ['Slow', 'Normal', 'Fast', 'Total']->[$_->{speed}//3];
            td_ sub { vnlength_ $_->{median} };
            td_ sub { vnlength_ $_->{avg} };
            td_ sub { vnlength_ $_->{stddev} if $_->{stddev} };
            td_ $_->{count};
        } for @$stats;
    };
}


TUWF::get qr{/(?:(?<thing>$RE{vid}|$RE{uid})/)?lengthvotes}, sub {
    my $thing = tuwf->capture('thing');
    my $o = $thing && dbobj $thing;
    return tuwf->resNotFound if $thing && (!$o->{id} || ($o->{entry_hidden} && !auth->isMod));
    my $mode = !$thing ? '' : $o->{id} =~ /^v/ ? 'v' : 'u';

    my $opt = tuwf->validate(get =>
        ign => { default => undef, enum => [0,1] },
        p   => { page => 1 },
        s   => { tableopts => $TABLEOPTS{$mode} },
    )->data;

    my sub url { '?'.query_encode({%$opt, @_}) }

    my $where = sql_and
        $mode ? sql($mode eq 'v' ? 'l.vid =' : 'l.uid =', \$o->{id}) : (),
        $mode eq 'u' && auth && $o->{id} eq auth->uid ? () : 'NOT l.private',
        defined $opt->{ign} ? sql('l.speed IS', $opt->{ign} ? 'NULL' : 'NOT NULL') : ();
    my $count = tuwf->dbVali('SELECT COUNT(*) FROM vn_length_votes l WHERE', $where);

    my $lst = tuwf->dbPagei({results => $opt->{s}->results, page => $opt->{p}},
      'SELECT l.id, l.uid, l.vid, l.length, l.speed, l.notes, l.private, l.rid::text[] AS rel, '
            , sql_totime('l.date'), 'AS date, u.perm_lengthvote IS NOT DISTINCT FROM false AS ignore',
              $mode ne 'u' ? (', ', sql_user()) : (),
              $mode ne 'v' ? ', v.title' : (), '
         FROM vn_length_votes l
         LEFT JOIN users u ON u.id = l.uid',
         $mode ne 'v' ? ('JOIN', vnt, 'v ON v.id = l.vid') : (),
       'WHERE', $where,
       'ORDER BY', $opt->{s}->sql_order(),
    );
    $_->{rel} = [ map +{ id => $_ }, $_->{rel}->@* ] for @$lst;
    enrich_flatten lang => id => id => 'SELECT id, lang FROM releases_titles WHERE id IN', map $_->{rel}, @$lst;

    my $title = 'Length votes'.($mode ? ($mode eq 'v' ? ' for ' : ' by ').$o->{title}[1] : '');
    framework_ title => $title, dbobj => $o, sub {
        article_ sub {
            h1_ $title;
            p_ 'Nothing to list. :(' if !@$lst;
            stats_ $o if $mode eq 'v' && @$lst;
            p_ class => 'browseopts', sub {
                a_ href => url(p => undef, ign => undef), class => defined $opt->{ign} ? undef : 'optselected', 'All';
                a_ href => url(p => undef, ign => 0), class => defined $opt->{ign} && !$opt->{ign} ? 'optselected' : undef, 'Active';
                a_ href => url(p => undef, ign => 1), class => defined $opt->{ign} &&  $opt->{ign} ? 'optselected' : undef, 'Ignored';
            } if auth->permDbmod;
        };

        return if !@$lst;
        if(auth->permDbmod) {
            form_ method => 'post', action => '/lengthvotes-edit', sub {
                input_ type => 'hidden', class => 'hidden', name => 'url', value => tuwf->reqPath.tuwf->reqQuery, undef;
                listing_ $opt, \&url, $count, $lst, $mode;
            };
        } else {
            listing_ $opt, \&url, $count, $lst, $mode;
        }
    };
};


TUWF::post '/lengthvotes-edit', sub {
    return tuwf->resDenied if !auth->permDbmod || !samesite;

    my @actions;
    for my $k (tuwf->reqPosts) {
        next if $k !~ /^lv$RE{num}$/;
        my $id = $+{num};
        my $act = tuwf->reqPost($k);
        next if !$act;
        my $r = tuwf->dbRowi('
            UPDATE vn_length_votes SET',
               $act eq 'sn' ? 'speed = NULL' :
               $act eq 's0' ? 'speed = 0' :
               $act eq 's1' ? 'speed = 1' :
               $act eq 's2' ? ('speed =', \2) : die,
           'WHERE id =', \$id, 'RETURNING vid, uid'
        );
        push @actions, "$r->{vid}-".($r->{uid}//'anon')."-$act";
    }
    auth->audit(undef, 'lengthvote edit', join ', ', sort @actions) if @actions;
    tuwf->resRedirect(tuwf->reqPost('url'), 'post');
};



my($FORM_IN, $FORM_OUT) = form_compile 'in', 'out', {
    vid      => { vndbid => 'v' },
    vote     => { type => 'hash', default => undef, keys => {
        rid      => { type => 'array', minlength => 1, values => { vndbid => 'r' } },
        length   => { uint => 1, range => [1,26159] }, # 435h59m, largest round-ish number where the 'fast' speed adjustment doesn't overflow a smallint
        speed    => { default => undef, uint => 1, enum => [0,1,2] },
        private  => { anybool => 1 },
        notes    => { default => '' },
    }},
    title    => { _when => 'out' },
    maycount => { _when => 'out', anybool => 1 },
    releases => { _when => 'out', aoh => $RELSCHEMA },
};


TUWF::get qr{/$RE{vid}/lengthvote}, sub {
    my $v = tuwf->dbRowi('SELECT id, title[1+1], devstatus FROM', vnt, 'v WHERE NOT hidden AND id =', \tuwf->capture('id'));
    return tuwf->resNotFound if !$v->{id};
    return tuwf->resDenied if !can_vote;

    my $my = tuwf->dbRowi('SELECT rid::text[] AS rid, length, speed, private, notes FROM vn_length_votes WHERE vid =', \$v->{id}, 'AND uid =', \auth->uid);

    my $today = strftime '%Y%m%d', gmtime;
    my $rels = [ grep $_->{released} <= $today, releases_by_vn($v->{id})->@* ];
    my $hasnontrial = grep $_->{rtype} ne 'trial', @$rels;
    # Voting on trials is only allowed if development has been cancelled and there's no other release.
    $rels = [ grep $_->{rtype} ne 'trial' || ($v->{devstatus} == 2 && !$hasnontrial), @$rels ];

    framework_ title => "Edit play time for $v->{title}", sub {
        if (@$rels || $my->{rid}) {
            div_ widget('VNLengthVote', $FORM_OUT, {
                vid      => $v->{id},
                vote     => $my->{rid} ? $my : undef,
                title    => $v->{title},
                maycount => $v->{devstatus} != 1,
                releases => $rels,
            }), '';
        } else {
            article_ sub {
                h1_ 'Play time submission not (yet) available for this title';
                div_ class => 'warning', sub {
                    a_ href => "/$v->{id}", $v->{title};
                    lit_ ' does not have any releases that are eligible for voting.';
                };
            };
        }
    };
};


js_api VNLengthVote => $FORM_IN, sub ($data) {
    return tuwf->resDenied if !can_vote;
    my %where = ( uid => auth->uid, vid => $data->{vid} );

    if ($data->{vote}) {
        my %fields = (
            $data->{vote}->%*,
            rid => sql sql_array($data->{vote}{rid}->@*), '::vndbid[]'
        );
        $fields{speed} = undef if $fields{private};
        tuwf->dbExeci(
            'INSERT INTO vn_length_votes', { %where, %fields },
            'ON CONFLICT (uid, vid) DO UPDATE SET', \%fields
        );
    } else {
        tuwf->dbExeci('DELETE FROM vn_length_votes WHERE', \%where);
    }
    +{};
};

1;
