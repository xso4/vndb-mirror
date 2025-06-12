package VNWeb::VN::Length;

use VNWeb::Prelude;
use VNWeb::Releases::Lib;

# Also used from VN::Page
sub can_vote { auth->permDbmod || (auth->permLengthvote && !global_settings->{lockdown_edit}) }

sub opts($mode) {
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


sub listing_($opt, $url, $count, $list, $mode) {
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
                    if ($_->{lang}) {
                        abbr_ class => "icon-lang-$_", title => $LANGUAGE{$_}{txt}, '' for sort $_->{lang}->@*;
                    } else {
                        my %l = map +($_,1), map $_->{lang}->@*, $_->{rel}->@*;
                        abbr_ class => "icon-lang-$_", title => $LANGUAGE{$_}{txt}, '' for sort keys %l;
                    }
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


sub stats_($o) {
    my $stats = fu->SQL('
        SELECT speed, count(*) as count, avg(l.length)::smallint as avg
             , stddev_pop(l.length::real)::int as stddev
             , percentile_cont(0.5) WITHIN GROUP (ORDER BY l.length) AS median
          FROM vn_length_votes l
          LEFT JOIN users u ON u.id = l.uid
         WHERE u.perm_lengthvote IS DISTINCT FROM false AND l.speed IS NOT NULL AND NOT l.private AND l.vid =', $o->{id}, '
         GROUP BY GROUPING SETS ((speed),()) ORDER BY speed'
    )->allh;
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


FU::get qr{/(?:$RE{vid}/|$RE{uid}/)?lengthvotes}, sub($vid=undef, $uid=undef) {
    my $thing = $vid || $uid;
    my $o = $thing && dbobj $thing;
    fu->notfound if $thing && (!$o->{id} || ($o->{entry_hidden} && !auth->isMod));
    my $mode = $vid ? 'v' : $uid ? 'u' : '';

    my $opt = fu->query(
        ign => { default => undef, enum => [0,1] },
        p   => { page => 1 },
        s   => { tableopts => $TABLEOPTS{$mode} },
    );

    my sub url { '?'.query_encode({%$opt, @_}) }

    my $where = AND
        $mode ? SQL($mode eq 'v' ? 'l.vid =' : 'l.uid =', $o->{id}) : (),
        $mode eq 'u' && auth && $o->{id} eq auth->uid ? () : 'NOT l.private',
        defined $opt->{ign} ? SQL('l.speed IS', $opt->{ign} ? 'NULL' : 'NOT NULL') : ();
    my $count = fu->SQL('SELECT COUNT(*) FROM vn_length_votes l', WHERE $where)->val;

    my $lst = fu->SQL(
      'SELECT l.id, l.uid, l.vid, l.length, l.speed, l.notes, l.private, l.rid AS rel, l.lang, l.date
            , u.perm_lengthvote IS NOT DISTINCT FROM false AS ignore',
              $mode ne 'u' ? (', ', USER) : (),
              $mode ne 'v' ? ', v.title' : (), '
         FROM vn_length_votes l
         LEFT JOIN users u ON u.id = l.uid',
         $mode ne 'v' ? ('JOIN', VNT, 'v ON v.id = l.vid') : (),
        WHERE($where),
       'ORDER BY', $opt->{s}->ORDER,
       'LIMIT', $opt->{s}->results, 'OFFSET', $opt->{s}->results*($opt->{p}-1),
    )->allh;
    $_->{rel} = [ map +{ id => $_ }, $_->{rel}->@* ] for @$lst;
    fu->enrich(aov => 'lang', 'SELECT id, lang FROM releases_titles WHERE id', [ map $_->{rel}->@*, @$lst ]);

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
                input_ type => 'hidden', class => 'hidden', name => 'url', value => fu->path.'?'.(fu->query||''), undef;
                listing_ $opt, \&url, $count, $lst, $mode;
            };
        } else {
            listing_ $opt, \&url, $count, $lst, $mode;
        }
    };
};


FU::post '/lengthvotes-edit', sub {
    fu->denied if !auth->permDbmod || !samesite;

    my $data = fu->formdata({ type => 'hash' });

    my @actions;
    for my ($k, $act) (%$data) {
        next if $k !~ /^lv($RE{num})$/;
        next if !$act || ref $act;
        my($vid, $uid) = fu->SQL('
            UPDATE vn_length_votes SET',
               $act eq 'sn' ? 'speed = NULL' :
               $act eq 's0' ? 'speed = 0' :
               $act eq 's1' ? 'speed = 1' :
               $act eq 's2' ? 'speed = 2' : die,
           'WHERE id =', $1, 'RETURNING vid, uid'
        )->rowl;
        push @actions, "$vid-".($uid//'anon')."-$act";
    }
    auth->audit(undef, 'lengthvote edit', join ', ', sort @actions) if @actions;
    fu->redirect(tempget => $data->{url});
};



my($FORM_IN, $FORM_OUT) = form_compile 'in', 'out', {
    vid      => { vndbid => 'v' },
    votes    => { sort_keys => 'id', aoh => {
        id       => { int => 1 },
        rid      => { minlength => 1, elems => { vndbid => 'r' } },
        lang     => { minlength => 1, elems => { enum => \%LANGUAGE } },
        length   => { uint => 1, range => [1,26159] }, # 435h59m, largest round-ish number where the 'fast' speed adjustment doesn't overflow a smallint
        speed    => { default => undef, uint => 1, enum => [0,1,2] },
        private  => { anybool => 1 },
        notes    => { default => '' },
    }},
    title    => { _when => 'out' },
    maycount => { _when => 'out', anybool => 1 },
    releases => { _when => 'out', aoh => $RELSCHEMA },
};


sub available_releases($v) {
    my $rels = releases_by_vn $v->{id}, released => 1;
    my $hasnontrial = grep $_->{rtype} ne 'trial', @$rels;
    # Voting on trials is only allowed if development has been cancelled and there's no other release.
    [ grep $_->{rtype} ne 'trial' || ($v->{devstatus} == 2 && !$hasnontrial), @$rels ];
}


FU::get qr{/$RE{vid}/lengthvote}, sub($id) {
    my $v = fu->SQL('SELECT id, title[2], devstatus FROM', VNT, 'v WHERE NOT hidden AND id =', $id)->rowh || fu->notfound;
    fu->denied if !can_vote;

    my $my = fu->SQL('
        SELECT id, rid, lang, length, speed, private, notes
          FROM vn_length_votes WHERE vid =', $v->{id}, 'AND uid =', auth->uid, '
         ORDER BY id'
    )->allh;
    my $rels = available_releases $v;

    framework_ title => "Edit play time for $v->{title}", sub {
        if (@$rels || $my) {
            div_ widget('VNLengthVote', $FORM_OUT, {
                vid      => $v->{id},
                votes    => $my,
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
    fu->denied if !can_vote;

    fu->SQL(
        'DELETE FROM vn_length_votes WHERE uid=', auth->uid, 'AND vid=', $data->{vid},
           'AND NOT id', IN [grep $_>0, map $_->{id}, $data->{votes}->@*]
    )->exec;

    my $v = fu->SQL('SELECT id, devstatus FROM', VNT, 'v WHERE NOT hidden AND id =', $data->{vid})->rowh || fu->notfound;
    my $rels = available_releases $v;
    my %rels = map +($_->{id},$_), @$rels;

    for my $v ($data->{votes}->@*) {
        my %fields = map +($_, $v->{$_}), qw/ length speed private notes /;
        $fields{speed} = undef if $fields{private};

        $fields{rid} = [ grep $rels{$_}, $v->{rid}->@* ];
        return 'No valid releases selected' if !$fields{rid}->@*;

        my %langs = map +($_,1), map $rels{$_}{lang}->@*, $fields{rid}->@*;
        $fields{lang} = [ grep $langs{$_}, $v->{lang}->@* ];
        return 'No valid language selected' if !$fields{lang}->@*;

        if ($v->{id} > 0) {
            fu->SQL('UPDATE vn_length_votes', SET(\%fields), 'WHERE uid =', auth->uid, 'AND id =', $v->{id})->exec;
        } else {
            $fields{uid} = auth->uid;
            $fields{vid} = $data->{vid};
            fu->SQL('INSERT INTO vn_length_votes', VALUES \%fields)->exec;
        }
    }
    +{};
};

1;
