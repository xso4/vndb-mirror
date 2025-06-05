package VNWeb::VN::Quotes;

use VNWeb::Prelude;

sub deletable($q) {
    !$q->{hidden} && $q->{addedby} && auth && $q->{addedby} eq auth->uid && auth->permEdit && $q->{added} > time()-5*24*3600;
}

sub editable {
    auth->permDbmod || deletable @_;
}

sub submittable($vid) {
    auth->permDbmod || (auth->permEdit && fu->SQL("SELECT COUNT(*) FROM quotes WHERE added > NOW() - '1 day'::interval AND addedby =", auth->uid)->val < 5);
}

# Also used by Chars::Page
sub votething_($q) {
    if (auth) {
        span_ class => 'quote-score', widget(QuoteVote => [@{$q}{qw/id score vote/}, $_->{hidden} ? \1 : \0, editable($q) ? \1 : \0]), '';
    } else {
        span_ $q->{score};
    }
}

FU::get qr{/$RE{vid}/quotes}, sub($id) {
    not_moe;
    my $v = db_entry $id;
    fu->notfound if !$v->{id} || $v->{entry_hidden};
    VNWeb::VN::Page::enrich_vn($v);

    my $lst = fu->SQL('
        SELECT q.id, q.score, q.quote, q.added, q.addedby, q.cid, c.title, v.spoil
          FROM quotes q
          LEFT JOIN', CHARST, 'c ON c.id = q.cid
          LEFT JOIN (SELECT id, MIN(spoil) FROM chars_vns WHERE vid =', $v->{id}, 'GROUP BY id) v(id,spoil) ON c.id = v.id
         WHERE NOT q.hidden
           AND vid =', $v->{id}, '
         ORDER BY q.score DESC, q.quote
    ')->allh;
    fu->enrich(set => 'vote', SQL('SELECT id, vote FROM quotes_votes WHERE uid =', auth->uid, 'AND id'), $lst) if auth;

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
                    a_ class => $view->{spoilers} == 0 ? 'checked' : undef, viewset(fu->path.'#quotes', spoilers=>0), 'Hide spoilers';
                    a_ class => $view->{spoilers} == 1 ? 'checked' : undef, viewset(fu->path.'#quotes', spoilers=>1), 'Show minor spoilers';
                    a_ class => $view->{spoilers} == 2 ? 'standout': undef, viewset(fu->path.'#quotes', spoilers=>2), 'Spoil me!' if $max_spoil == 2;
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


sub listing_($lst, $count, $opt, $url) {
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

sub opts_($opt) {
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

    my sub opt_($key, $val, $label) {
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

FU::get '/v/quotes', sub {
    fu->denied if !auth;
    my $opt = fu->query(
        v  => { default => undef, vndbid => 'v' },
        u  => { default => undef, vndbid => 'u' },
        h  => { default => undef, enum => [0,1] },
        c  => { default => undef, enum => [0,1] },
        s  => { default => 'added', enum => [qw/added lastmod top bottom/] },
        p  => { upage => 1 },
    );
    $opt->{h} = 0 if !auth->permDbmod;

    my $u = $opt->{u} && fu->SQL('SELECT id,', USER, 'FROM users u WHERE id =', $opt->{u})->rowh;
    fu->notfound if $opt->{u} && (!$u || (!defined $u->{user_name} && !auth->isMod));

    my $where = AND
        $opt->{v} ? SQL('q.vid =', $opt->{v}) : (),
        $opt->{u} ? SQL('q.addedby =', $opt->{u}) : (),
        defined $opt->{h} ? SQL($opt->{h} ? '' : 'NOT', 'q.hidden') : (),
        defined $opt->{c} ? SQL('q.cid', $opt->{c} ? 'IS NOT NULL' : 'IS NULL') : ();

    my $count = fu->SQL('SELECT COUNT(*) FROM quotes q WHERE', $where)->val;
    my $lst = !$count ? [] : fu->SQL('
        SELECT q.id, q.hidden, q.score, q.quote, q.added, q.addedby, q.vid, q.cid
             , v.title, c.title AS char,', USER(), '
          FROM quotes q
          JOIN', VNT, 'v ON v.id = q.vid
          LEFT JOIN', CHARST, 'c ON c.id = q.cid
          LEFT JOIN users u ON u.id = q.addedby
          ', $opt->{s} eq 'lastmod' ? 'LEFT JOIN (
            SELECT id, MAX(date) FROM quotes_log GROUP BY id
          ) l (id, latest) ON l.id = q.id' : (), '
         WHERE', $where, '
         ORDER BY ', RAW {
             added   => 'q.id DESC',
             lastmod => 'l.latest DESC, q.id DESC',
             top     => 'q.score DESC, q.id',
             bottom  => 'q.score, q.id',
         }->{$opt->{s}}, '
         LIMIT 50 OFFSET', 50*($opt->{p}-1)
    )->allh;
    fu->enrich(set => 'vote', SQL('SELECT id, vote FROM quotes_votes WHERE uid =', auth->uid, 'AND id'), $lst) if auth;

    my sub url { '?'.query_encode({%$opt, @_}) }

    framework_ title => 'Quotes browser', sub {
        article_ sub {
            h1_ 'Quotes browser';
            opts_ $opt;
        };
        listing_ $lst, $count, $opt, \&url if @$lst;
    };
};


my($FORM_IN, $FORM_OUT) = form_compile 'in', 'out', {
    id       => { vndbid => 'q', default => undef },
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

FU::get qr{/(?:$RE{vid}/addquote|editquote/$RE{qid})}, sub($vid, $qid=undef) {
    my $q = $qid && fu->SQL('
        SELECT q.id, q.vid, q.hidden, q.quote, q.added, q.addedby, q.cid, c.title
          FROM quotes q
          LEFT JOIN', CHARST, 'c ON c.id = q.cid
         WHERE q.id = ', $qid
    )->rowh;
    fu->notfound if $qid && !$q;
    $vid ||= $q->{vid};

    my $v = $vid && dbobj $vid;
    fu->notfound if $vid && (!$v->{id} || $v->{entry_hidden});
    fu->denied if $qid ? !editable $q : !submittable $vid;

    my $log = $qid && fu->SQL('
        SELECT q.date, q.action,', USER, '
          FROM quotes_log q
          LEFT JOIN users u ON u.id = q.uid
         WHERE q.id = ', $qid, '
         ORDER BY q.date DESC
    ')->allh;

    my $chars = fu->SQL('
        SELECT id, title[2], title[4] AS alttitle
          FROM ', CHARST, '
         WHERE NOT hidden AND id IN(SELECT id FROM chars_vns WHERE vid =', $v->{id}, ')
         ORDER BY sorttitle, id
    ')->allh;

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
            ) : $FORM_OUT->empty->%*, chars => $chars, vid => $vid, delete => deletable($q) }), '';
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

js_api QuoteEdit => $FORM_IN, sub($data) {
    my $v = dbobj $data->{vid};
    fu->notfound if !$v->{id} || $v->{entry_hidden};

    my $q = $data->{id} && fu->SQL('SELECT id, hidden, quote, added, addedby, cid FROM quotes WHERE id = ', $data->{id})->rowh;
    fu->denied if $data->{id} && (!$q || !editable $q);

    if ($data->{id}) {
        my %set = (
            !$data->{hidden} ne !$q->{hidden} ? (hidden => $data->{hidden}) : (),
            $data->{quote} ne $q->{quote} ? (quote => $data->{quote}) : (),
            ($data->{cid}//'') ne ($q->{cid}//'') ? (cid => $data->{cid}) : (),
        );
        fu->SQL('UPDATE quotes', SET(\%set), 'WHERE id =', $data->{id})->exec if keys %set;
        fu->SQL('INSERT INTO quotes_log', VALUES {
            id => $data->{id}, uid => auth->uid,
            action => join '; ',
                exists $set{hidden} ? "State: ".($q->{hidden}?"Deleted":"New")." -> ".($data->{hidden}?"Deleted":"New") : (),
                exists $set{cid} ? "Character: ".($q->{cid}||'empty')." -> ".($data->{cid}||'empty') : (),
                exists $set{quote} ? "Quote: \"[i][raw]$q->{quote} [/raw][/i]\" -> \"[i][raw]$data->{quote} [/raw][/i]\"" : (),
        })->exec if keys %set;

    } else {
        return 'You have already submitted 5 quotes today, try again tomorrow.' if !submittable($data->{vid});
        my sub norm { SQL 'lower(regexp_replace(', $_[0], q{, '[\s",.]+', '', 'g'))} }
        return 'This quote has already been submitted.'
            if fu->SQL('SELECT 1 FROM quotes WHERE vid =', $data->{vid}, 'AND', norm($data->{quote}), '=', norm('quote'))->val;

        my $id = fu->SQL('INSERT INTO quotes', VALUES({
            vid     => $v->{id},
            cid     => $data->{cid},
            addedby => auth->uid,
            quote   => $data->{quote},
            auth->permDbmod ? (hidden => $data->{hidden}) : (),
        }), 'RETURNING id')->val;
        fu->SQL('INSERT INTO quotes_votes', VALUES {id => $id, uid => auth->uid, vote => 1})->exec;
        fu->SQL('INSERT INTO quotes_log', VALUES {id => $id, uid => auth->uid, action => 'Submitted'})->exec;
    }
    +{}
};

js_api QuoteDel => { id => { vndbid => 'q' } }, sub($data) {
    my $q = fu->SQL('SELECT id, hidden, added, addedby FROM quotes WHERE id = ', $data->{id})->rowh;
    fu->denied if !$q || !deletable $q;
    fu->SQL('DELETE FROM quotes WHERE id =', $q->{id})->exec;
    +{}
};

js_api QuoteVote => { id => { vndbid => 'q' }, vote => { default => undef, enum => [-1,1] } }, sub($data) {
    fu->denied if !auth;
    fu->SQL('DELETE FROM quotes_votes', WHERE { uid => auth->uid, id => $data->{id} })->exec if !$data->{vote};
    $data->{uid} = auth->uid;
    fu->SQL('INSERT INTO quotes_votes', VALUES($data), 'ON CONFLICT (id, uid) DO UPDATE SET vote =', $data->{vote})->exec if $data->{vote};
    +{}
};

1;
