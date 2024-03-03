package VNWeb::VN::Quotes;

use VNWeb::Prelude;

sub deletable {
    my($q) = @_;
    !$q->{hidden} && $q->{addedby} && auth && $q->{addedby} eq auth->uid && auth->permEdit && $q->{added} > time()-5*24*3600;
}

sub editable {
    auth->permDbmod || deletable @_;
}

sub submittable {
    my($vid) = @_;
    auth->permDbmod || (auth->permEdit && tuwf->dbVali(q{SELECT COUNT(*) FROM quotes WHERE added > NOW() - '1 day'::interval AND addedby =}, \auth->uid) < 5);
}

sub votething_ {
    my($q) = @_;
    if (auth) {
        $q->{id} *= 1;
        span_ class => 'quote-score', widget(QuoteVote => [@{$q}{qw/id score vote/}, $_->{hidden} ? \1 : \0, editable($q) ? \1 : \0]), '';
    } else {
        span_ $q->{score};
    }
}

TUWF::get qr{/$RE{vid}/quotes}, sub {
    my $v = db_entry tuwf->capture('id');
    return tuwf->resNotFound if !$v->{id} || $v->{entry_hidden};
    VNWeb::VN::Page::enrich_vn($v);

    my $lst = tuwf->dbAlli('
        SELECT q.id, q.score, q.quote,', sql_totime('q.added'), 'AS added, q.addedby, q.cid, c.title, v.spoil
          FROM quotes q
          LEFT JOIN', charst, 'c ON c.id = q.cid
          LEFT JOIN (SELECT id, MIN(spoil) FROM chars_vns WHERE vid =', \$v->{id}, 'GROUP BY id) v(id,spoil) ON c.id = v.id
         WHERE NOT q.hidden
           AND vid =', \$v->{id}, '
         ORDER BY q.score DESC, q.quote
    ');
    enrich_merge id => sql('SELECT id, vote FROM quotes_votes WHERE uid =', \auth->uid, 'AND id IN'), $lst if auth;

    my $view = viewget;
    my $max_spoil = max 0, grep $_, map $_->{spoil}, @$lst;

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
                if ($max_spoil) {
                    a_ mkclass(checked => $view->{spoilers} == 0), href => '?view='.viewset(spoilers=>0).'#quotes', 'Hide spoilers';
                    a_ mkclass(checked => $view->{spoilers} == 1), href => '?view='.viewset(spoilers=>1).'#quotes', 'Show minor spoilers';
                    a_ mkclass(standout =>$view->{spoilers} == 2), href => '?view='.viewset(spoilers=>2).'#quotes', 'Spoil me!' if $max_spoil == 2;
                    small_ ' | ';
                }
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
                        if ($_->{cid} && ($_->{spoil}||0) <= $view->{spoilers}) {
                            small_ '[';
                            a_ href => "/$_->{cid}", tattr $_;
                            small_ '] ';
                        }
                        txt_ $_->{quote};
                    };
                } for @$lst;
            };
            p_ sub {
                small_ 'Vote to like/dislike a quote, typos and other errors should be reported on the forums.';
            } if auth;
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
                    opt_ h => undef, 'any';
                    opt_ h => 0 => 'Visible';
                    opt_ h => 1 => 'Deleted';
                };
            } if auth->permDbmod;
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
        h  => { undefbool => 1 },
        c  => { undefbool => 1 },
        s  => { default => 'added', enum => [qw/added lastmod top bottom/] },
        p  => { upage => 1 },
    )->data;
    $opt->{h} = 0 if !auth->permDbmod;

    my $where = sql_and
        $opt->{v} ? sql('q.vid =', \$opt->{v}) : (),
        $opt->{u} ? sql('q.addedby =', \$opt->{u}) : (),
        defined $opt->{h} ? sql($opt->{h} ? '' : 'NOT', 'q.hidden') : (),
        defined $opt->{c} ? sql('q.cid', $opt->{c} ? 'IS NOT NULL' : 'IS NULL') : ();

    my $count = tuwf->dbVali('SELECT COUNT(*) FROM quotes q WHERE', $where);
    my $lst = !$count ? [] : tuwf->dbPagei({ results => 50, page => $opt->{p} }, '
        SELECT q.id, q.hidden, q.score, q.quote, q.addedby, q.vid, q.cid
             , v.title, c.title AS char,', sql_user(), '
             , ', sql_totime('q.added'), 'added
          FROM quotes q
          JOIN', vnt, 'v ON v.id = q.vid
          LEFT JOIN', charst, 'c ON c.id = q.cid
          LEFT JOIN users u ON u.id = q.addedby
          ', $opt->{s} eq 'lastmod' ? 'LEFT JOIN (
            SELECT id, MAX(date) FROM quotes_log GROUP BY id
          ) l (id, latest) ON l.id = q.id' : (), '
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
    hidden   => { anybool => 1 },
    quote    => { sl => 1, maxlength => 170 },
    cid      => { vndbid => 'c', default => undef },
    title    => { _when => 'out' },
    alttitle => { _when => 'out' },
    chars    => { _when => 'out', aoh => {
        id       => { vndbid => 'c' },
        title    => {},
        alttitle => {},
    } },
    delete   => { anybool => 1 },
};

my $FORM_IN  = form_compile in  => $FORM;
my $FORM_OUT = form_compile out => $FORM;

TUWF::get qr{/(?:$RE{vid}/addquote|editquote/$RE{num})}, sub {
    my($vid, $qid) = tuwf->captures('id', 'num');

    my $q = $qid && tuwf->dbRowi('
        SELECT q.id, q.vid, q.hidden, q.quote,', sql_totime('q.added'), 'added, q.addedby, q.cid, c.title
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
         WHERE NOT hidden AND id IN(SELECT id FROM chars_vns WHERE vid =', \$v->{id}, ')
         ORDER BY sorttitle, id
    ');

    my $title = ($qid ? 'Edit' : 'Add')." quote for $v->{title}[1]";
    framework_ title => $title, dbobj => $v, sub {
        article_ sub {
            h1_ $title;
            h2_ 'Some rules:';
            ul_ sub {
                li_ 'Quotes must be in English. You may use your own translation.';
                li_ 'Quotes should be interesting, funny and/or insightful out of context.';
                li_ 'Quotes must come from an actual release of the visual novel.';
                li_ 'Quotes may not contain spoilers.';
                li_ 'At most 170 characters per quote, but shorter quotes are preferred.';
                li_ 'You may submit at most 5 quotes per day.';
                li_ "This quotes feature is more of a silly gimmick than a proper database feature, keep your expectations low.";
            };
            br_;
            div_ widget(QuoteEdit => $FORM_OUT, { $qid ? (
                id => $q->{id}, hidden => $q->{hidden}, quote => $q->{quote},
                cid => $q->{cid}, title => $q->{title}[1], alttitle => $q->{title}[3],
            ) : elm_empty($FORM_OUT)->%*, chars => $chars, vid => $vid, delete => deletable($q) }), '';
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

    my $q = $data->{id} && tuwf->dbRowi('SELECT id, hidden, quote,', sql_totime('added'), 'added, addedby, cid FROM quotes WHERE id = ', \$data->{id});
    return tuwf->resDenied if $data->{id} && (!$q->{id} || !editable $q);

    if ($data->{id}) {
        my %set = (
            !$data->{hidden} ne !$q->{hidden} ? (hidden => $data->{hidden}) : (),
            $data->{quote} ne $q->{quote} ? (quote => $data->{quote}) : (),
            ($data->{cid}//'') ne ($q->{cid}//'') ? (cid => $data->{cid}) : (),
        );
        tuwf->dbExeci('UPDATE quotes SET', \%set, 'WHERE id =', \$data->{id}) if keys %set;
        tuwf->dbExeci('INSERT INTO quotes_log', {
            id => $data->{id}, uid => auth->uid,
            action => join '; ',
                exists $set{hidden} ? "State: ".($q->{hidden}?"Deleted":"New")." -> ".($data->{hidden}?"Deleted":"New") : (),
                exists $set{cid} ? "Character: ".($q->{cid}||'empty')." -> ".($data->{cid}||'empty') : (),
                exists $set{quote} ? "Quote: \"[i][raw]$q->{quote} [/raw][/i]\" -> \"[i][raw]$data->{quote} [/raw][/i]\"" : (),
        }) if keys %set;

    } else {
        return 'You have already submitted 5 quotes today, try again tomorrow.' if !submittable($data->{vid});
        my sub norm { sql 'lower(regexp_replace(', $_[0], q{, '[\s",.]+', '', 'g'))} }
        return 'This quote has already been submitted.'
            if tuwf->dbVali('SELECT 1 FROM quotes WHERE vid =', \$data->{vid}, 'AND', norm(\$data->{quote}), '=', norm('quote'));

        my $id = tuwf->dbVali('INSERT INTO quotes', {
            vid     => $v->{id},
            cid     => $data->{cid},
            addedby => auth->uid,
            quote   => $data->{quote},
            auth->permDbmod ? (hidden => $data->{hidden}) : (),
        }, 'RETURNING id');
        tuwf->dbExeci('INSERT INTO quotes_votes', {id => $id, uid => auth->uid, vote => 1});
        tuwf->dbExeci('INSERT INTO quotes_log', {id => $id, uid => auth->uid, action => 'Submitted'});
    }
    +{}
};

js_api QuoteDel => { id => { uint => 1 } }, sub {
    my $q = tuwf->dbRowi('SELECT id, hidden,', sql_totime('added'), 'added, addedby FROM quotes WHERE id = ', \$_[0]{id});
    return tuwf->resDenied if !$q->{id} || !deletable $q;
    tuwf->dbExeci('DELETE FROM quotes WHERE id =', \$q->{id});
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
