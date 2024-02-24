package VNWeb::VN::Quotes;

use VNWeb::Prelude;

my @ST = qw/New Approved Deleted/;

sub editable {
    my($q) = @_;
    auth->permDbmod || ($q->{state} == 0 && $q->{addedby} && auth && $q->{addedby} eq auth->uid && auth->permEdit);
}

sub submittable {
    my($vid) = @_;
    auth->permDbmod || (auth->permEdit && tuwf->dbVali('SELECT COUNT(*) FROM quotes WHERE vid =', \$vid, 'AND addedby =', \auth->uid, 'AND state = 0') < 3);
}

sub votething_ {
    my($q) = @_;
    if (auth) {
        $q->{id} *= 1;
        span_ class => 'quote-score', widget(QuoteVote => [@{$q}{qw/id score state vote/}, editable($q) ? \1 : \0]), '';
    } else {
        [\&small_, \&txt_, \&b_]->[$q->{state}]->($q->{score});
    }
}

TUWF::get qr{/$RE{vid}/quotes}, sub {
    my $v = db_entry tuwf->capture('id');
    return tuwf->resNotFound if !$v->{id} || $v->{entry_hidden};
    VNWeb::VN::Page::enrich_vn($v);

    my $lst = tuwf->dbAlli('
        SELECT q.id, q.state, q.score, q.quote, q.addedby, q.cid, c.title
          FROM quotes q
          LEFT JOIN', charst, 'c ON c.id = q.cid
         WHERE state <> 1+1
           AND vid =', \$v->{id}, '
         ORDER BY q.state DESC, q.score DESC, q.quote
    ');
    enrich_merge id => sql('SELECT id, vote FROM quotes_votes WHERE uid =', \auth->uid, 'AND id IN'), $lst if auth;

    framework_ title => "Quotes for $v->{title}[1]", dbobj => $v, hiddenmsg => 1, sub {
        VNWeb::VN::Page::infobox_($v);
        VNWeb::VN::Page::tabs_($v, 'quotes');
        article_ sub {
            h1_ "Quotes";
            p_ submittable($v->{id}) ? sub {
                txt_ 'No quotes yet, maybe ';
                a_ href => "/$v->{id}/addquote", 'submit a quote yourself';
                txt_ '?';
            } : sub {
                txt_ 'No quotes yet.';
            };
        } if !@$lst;
        article_ sub {
            p_ class => 'mainopts', sub {
                if (auth->permDbmod) {
                    a_ href => "/v/quotes?v=$v->{id}", 'details';
                    small_ ' | ';
                }
                a_ href => "/$v->{id}/addquote", 'submit a quote';
            } if submittable($v->{id});
            h1_ "Quotes";
            table_ sub {
                tr_ sub {
                    td_ sub { votething_ $_ };
                    td_ sub {
                        if ($_->{cid}) {
                            small_ '[';
                            a_ href => "/$_->{cid}", tattr $_;
                            small_ '] ';
                        }
                        txt_ $_->{quote};
                    };
                } for @$lst;
            };
        } if @$lst;
    };
};


sub listing_ {
    my($lst, $count, $opt, $url) = @_;
    paginate_ $url, $opt->{p}, [$count, 50], 't';
    article_ class => 'browse quotes', sub {
        table_ class => 'stripe', sub {
            tr_ sub {
                td_ class => 'tc1', sub { votething_ $_ };
                td_ class => 'tc2', sub { txt_ fmtdate $_->{added}, 'full' };
                td_ class => 'tc3', sub {
                    a_ href => $url->(u => $_->{addedby}, p=>undef), class => 'setfil', '> ' if $_->{addedby} && !defined $opt->{u};
                    user_ $_;
                };
                td_ sub {
                    a_ href => $url->(v => $_->{vid}, p=>undef), class => 'setfil', '> ' if !defined $opt->{v};
                    a_ href => "/$_->{vid}/quotes#quotes", tattr $_;
                    br_;
                    if ($_->{cid}) {
                        small_ '[';
                        a_ href => "/$_->{cid}", tattr $_->{char};
                        small_ '] ';
                    }
                    txt_ $_->{quote};
                };
            } for @$lst;
        };
    };
    paginate_ $url, $opt->{p}, [$count, 50], 'b';
}

sub opts_ {
    my($opt) = @_;

    my sub obj_ {
        my($key, $label) = @_;
        my $v = $opt->{$key} // return;
        my $o = dbobj $v;
        tr_ sub {
            td_ "$label:";
            td_ sub {
                input_ type => 'checkbox', name => $key, value => $v, checked => 'checked';
                lit_ ' ';
                a_ href => "/$v", $o && $o->{id} && $o->{title}[1] ? tattr $o : $v;
            };
        };
    }

    my sub opt_ {
        my($key, $val, $label) = @_;
        label_ sub {
            lit_ ' ';
            input_ type => 'radio', name => $key, value => $val//'',
                checked => ($opt->{$key}//'undef') eq ($val//'undef') ? 'checked' : undef;
            lit_ ' ';
            txt_ $label;
        };
    };

    form_ sub {
        table_ style => 'margin: auto', sub {
            obj_ v => 'VN';
            obj_ u => 'User';
            tr_ sub {
                td_ 'State:';
                td_ sub {
                    opt_ st => undef, 'any';
                    opt_ st => 0 => lc $ST[0];
                    opt_ st => 1 => lc $ST[1];
                    opt_ st => 2 => lc $ST[2] if auth->permDbmod;
                };
            };
            tr_ sub {
                td_ 'Has char:';
                td_ sub {
                    opt_ c => undef, 'any';
                    opt_ c => 0, 'no';
                    opt_ c => 1, 'yes';
                };
            };
            tr_ sub {
                td_ 'Order by:';
                td_ sub {
                    opt_ s => added => 'date added';
                    opt_ s => lastmod => 'last modified';
                    opt_ s => top => 'highest score';
                    opt_ s => bottom => 'lowest score';
                };
            };
            tr_ sub {
                td_ '';
                td_ sub { input_ type => 'submit', class => 'submit', value => 'Update' };
            }
        };
    };
}

TUWF::get '/v/quotes', sub {
    return tuwf->resDenied if !auth;
    my $opt = tuwf->validate(get =>
        v  => { default => undef, vndbid => 'v' },
        u  => { default => undef, vndbid => 'u' },
        st => { default => undef, enum => [0,1,2] },
        c  => { undefbool => 1 },
        s  => { default => 'added', enum => [qw/added lastmod top bottom/] },
        p  => { upage => 1 },
    )->data;
    $opt->{st} = undef if $opt->{st} && $opt->{st} == 2 && !auth->permDbmod;

    my $where = sql_and
        $opt->{v} ? sql('q.vid =', \$opt->{v}) : (),
        $opt->{u} ? sql('q.addedby =', \$opt->{u}) : (),
        defined $opt->{st} ? sql('q.state =', \$opt->{st}) : auth->permDbmod ? () : ('q.state <> 1+1'),
        defined $opt->{c} ? sql('q.cid', $opt->{c} ? 'IS NOT NULL' : 'IS NULL') : ();

    my $count = tuwf->dbVali('SELECT COUNT(*) FROM quotes q WHERE', $where);
    my $lst = !$count ? [] : tuwf->dbPagei({ results => 50, page => $opt->{p} }, '
        SELECT q.id, q.state, q.score, q.quote, q.addedby, q.vid, q.cid
             , v.title, c.title AS char,', sql_user(), '
             , ', sql_totime('l.earliest'), 'added, ', sql_totime('l.latest'), 'lastmod
          FROM quotes q
          JOIN', vnt, 'v ON v.id = q.vid
          LEFT JOIN', charst, 'c ON c.id = q.cid
          LEFT JOIN users u ON u.id = q.addedby
          JOIN (
            SELECT id, MIN(date), MAX(date) FROM quotes_log GROUP BY id
          ) l (id, earliest, latest) ON l.id = q.id
         WHERE', $where, '
         ORDER BY ', {
             added   => 'q.id DESC',
             lastmod => 'l.latest DESC, q.id DESC',
             top     => 'q.score DESC, q.id',
             bottom  => 'q.score, q.id',
         }->{$opt->{s}}
    );
    enrich_merge id => sql('SELECT id, vote FROM quotes_votes WHERE uid =', \auth->uid, 'AND id IN'), $lst if auth;

    my sub url { '?'.query_encode %$opt, @_ }

    framework_ title => 'Quotes browser', sub {
        article_ sub {
            h1_ 'Quotes browser';
            opts_ $opt;
        };
        listing_ $lst, $count, $opt, \&url if @$lst;
    };
};


my $FORM = {
    id       => { uint => 1, default => undef },
    vid      => { vndbid => 'v' },
    state    => { uint => 1, range => [0,2] },
    quote    => { sl => 1, maxlength => 170 },
    cid      => { vndbid => 'c', default => undef },
    title    => { _when => 'out' },
    alttitle => { _when => 'out' },
    chars    => { _when => 'out', aoh => {
        id       => { vndbid => 'c' },
        title    => {},
        alttitle => {},
    } },
};

my $FORM_IN  = form_compile in  => $FORM;
my $FORM_OUT = form_compile out => $FORM;

TUWF::get qr{/(?:$RE{vid}/addquote|editquote/$RE{num})}, sub {
    my($vid, $qid) = tuwf->captures('id', 'num');

    my $q = $qid && tuwf->dbRowi('
        SELECT q.id, q.vid, q.state, q.quote, q.addedby, q.cid, c.title
          FROM quotes q
          LEFT JOIN', charst, 'c ON c.id = q.cid
         WHERE q.id = ', \$qid
    );
    return tuwf->resNotFound if $qid && !$q->{id};
    $vid ||= $q->{vid};

    my $v = $vid && dbobj $vid;
    return tuwf->resNotFound if $vid && (!$v->{id} || $v->{entry_hidden});
    return tuwf->resDenied if $qid ? !editable $q : !submittable $vid;

    my $log = $qid && tuwf->dbAlli('
        SELECT ', sql_totime('q.date'), 'date, q.action,', sql_user(), '
          FROM quotes_log q
          LEFT JOIN users u ON u.id = q.uid
         WHERE q.id = ', \$qid, '
         ORDER BY q.date DESC
    ');

    my $chars = tuwf->dbAlli('
        SELECT id, title[1+1] AS title, title[1+1+1+1] AS alttitle
          FROM ', charst, '
         WHERE id IN(SELECT id FROM chars_vns WHERE vid =', \$v->{id}, ')
         ORDER BY sorttitle, id
    ');

    my $title = ($qid ? 'Edit' : 'Add')." quote for $v->{title}[1]";
    framework_ title => $title, dbobj => $v, sub {
        article_ sub {
            h1_ $title;
            h2_ 'Some rules:';
            ul_ sub {
                li_ 'Quotes must be in English. You may use your own translation.';
                li_ 'You can submit up to 3 quotes per visual novel. This limit resets when your quotes are approved by a moderator.';
                li_ 'Quotes should be interesting, funny and/or insightful out of context.';
                li_ 'Quotes must come from an actual release of the visual novel.';
                li_ 'Quotes may not contain spoilers.';
                li_ 'At most 170 characters per quote, but shorter quotes are preferred.';
                li_ "This quotes feature is more of a silly gimmick than a proper database feature, keep your expectations low.";
            };
            br_;
            div_ widget(QuoteEdit => $FORM_OUT, { $qid ? (
                id => $q->{id}, state => $q->{state}, quote => $q->{quote},
                cid => $q->{cid}, title => $q->{title}[1], alttitle => $q->{title}[3],
            ) : elm_empty($FORM_OUT)->%*, chars => $chars, vid => $vid }), '';
        };
        if ($log && @$log) {
            nav_ sub {
                h1_ 'Log';
            };
            article_ class => 'browse', sub {
                table_ class => 'stripe', sub {
                    thead_ sub { tr_ sub {
                        td_ class => 'tc1', 'Date';
                        td_ 'User';
                        td_ 'Action';
                    } };
                    tr_ sub {
                        td_ class => 'tc1', fmtdate $_->{date}, 'full';
                        td_ sub { user_ $_; };
                        td_ sub {
                            lit_ bb_format $_->{action}, inline => 1;
                        };
                    } for @$log;
                };
            };
        }
    };
};

js_api QuoteEdit => $FORM_IN, sub {
    my($data) = @_;

    my $v = dbobj $data->{vid};
    return tuwf->resNotFound if !$v->{id} || $v->{entry_hidden};

    my $q = $data->{id} && tuwf->dbRowi('SELECT id, state, quote, addedby, cid FROM quotes WHERE id = ', \$data->{id});
    return tuwf->resDenied if $data->{id} && (!$q->{id} || !editable $q);

    if ($data->{id}) {
        my %set = map +($_, $data->{$_}), grep +($data->{$_}//'') ne ($q->{$_}//''), qw/state quote cid/;
        tuwf->dbExeci('UPDATE quotes SET', \%set, 'WHERE id =', \$data->{id}) if keys %set;
        tuwf->dbExeci('INSERT INTO quotes_log', {
            id => $data->{id}, uid => auth->uid,
            action => join '; ',
                exists $set{state} ? "State: $ST[$q->{state}] -> $ST[$data->{state}]" : (),
                exists $set{cid} ? "Character: ".($q->{cid}||'empty')." -> ".($data->{cid}||'empty') : (),
                exists $set{quote} ? "Quote: \"[i][raw]$q->{quote} [/raw][/i]\" -> \"[i][raw]$q->{quote} [/raw][/i]\"" : (),
        }) if keys %set;

    } else {
        return 'You have already submitted 3 quotes for this VN.' if !submittable($data->{vid});
        my sub norm { sql 'lower(regexp_replace(', $_[0], q{, '[\s",.]+', '', 'g'))} }
        return 'This quote has already been submitted.'
            if tuwf->dbVali('SELECT 1 FROM quotes WHERE vid =', \$data->{vid}, 'AND', norm(\$data->{quote}), '=', norm('quote'));

        my $id = tuwf->dbVali('INSERT INTO quotes', {
            vid     => $v->{id},
            cid     => $data->{cid},
            addedby => auth->uid,
            quote   => $data->{quote},
            auth->permDbmod ? (state => $data->{state}) : (),
        }, 'RETURNING id');
        tuwf->dbExeci('INSERT INTO quotes_votes', {id => $id, uid => auth->uid, vote => 1});
        tuwf->dbExeci('INSERT INTO quotes_log', {id => $id, uid => auth->uid, action => 'Submitted'});
    }
    +{}
};

js_api QuoteVote => { id => { uint => 1 }, vote => { default => undef, enum => [-1,1] } }, sub {
    my($data) = @_;
    tuwf->dbExeci('DELETE FROM quotes_votes WHERE', { uid => auth->uid, id => $data->{id} }) if !$data->{vote};
    $data->{uid} = auth->uid;
    tuwf->dbExeci('INSERT INTO quotes_votes', $data, 'ON CONFLICT (id, uid) DO UPDATE SET vote =', \$data->{vote}) if $data->{vote};
    +{}
};

1;
