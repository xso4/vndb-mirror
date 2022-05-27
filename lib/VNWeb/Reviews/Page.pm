package VNWeb::Reviews::Page;

use VNWeb::Prelude;
use VNWeb::Releases::Lib;
use VNWeb::Reviews::Lib;


my $COMMENT = form_compile any => {
    id  => { vndbid => 'w' },
    msg => { maxlength => 32768 }
};

elm_api ReviewsComment => undef, $COMMENT, sub {
    my($data) = @_;
    my $w = tuwf->dbRowi('SELECT id, locked FROM reviews WHERE id =', \$data->{id});
    return tuwf->resNotFound if !$w->{id};
    return elm_Unauth if !can_edit t => $w;

    my $num = sql 'COALESCE((SELECT MAX(num)+1 FROM reviews_posts WHERE id =', \$data->{id}, '),1)';
    my $msg = bb_subst_links $data->{msg};
    $num = tuwf->dbVali('INSERT INTO reviews_posts', { id => $w->{id}, num => $num, uid => auth->uid, msg => $msg }, 'RETURNING num');
    elm_Redirect "/$w->{id}.$num#last";
};



sub review_ {
    my($w) = @_;

    input_ type => 'checkbox', class => 'visuallyhidden', id => 'reviewspoil', (auth->pref('spoilers')||0) == 2 ? ('checked', 'checked') : (), undef;
    my @spoil = $w->{spoiler} ? (class => 'reviewspoil') : ();
    table_ class => 'fullreview', sub {
        tr_ sub {
            td_ 'Subject';
            td_ sub {
                a_ href => "/$w->{vid}", title => $w->{alttitle}||$w->{title}, $w->{title};
                if($w->{rid}) {
                    br_;
                    platform_ $_ for $w->{platforms}->@*;
                    abbr_ class => "icons lang $_", title => $LANGUAGE{$_}, '' for $w->{lang}->@*;
                    abbr_ class => "icons rt$w->{rtype}", title => $w->{rtype}, '';
                    a_ href => "/$w->{rid}", title => $w->{roriginal}||$w->{rtitle}, $w->{rtitle};
                }
            };
        };
        tr_ sub {
            td_ 'By';
            td_ sub {
                span_ style => 'float: right; padding-left: 25px; text-align: right', sub {
                    txt_ 'Helpfulness: '.reviews_helpfulness($w);
                    br_;
                    b_ 'Vote: '.fmtvote($w->{vote}) if $w->{vote};
                };
                user_ $w;
                my($date, $lastmod) = map $_&&fmtdate($_,'compact'), $w->@{'date', 'lastmod'};
                txt_ " on $date";
                b_ class => 'grayedout', " last updated on $lastmod" if $lastmod && $date ne $lastmod;
                br_ if $w->{c_flagged} || $w->{locked} || ($w->{spoiler} && (auth->pref('spoilers')||0) == 2);
                if($w->{c_flagged}) {
                    br_;
                    b_ class => 'grayedout', 'Flagged: this review is below the voting threshold and not visible on the VN page.';
                }
                if($w->{locked}) {
                    br_;
                    b_ class => 'grayedout', 'Locked: commenting on this review has been disabled.';
                }
                if($w->{spoiler} && (auth->pref('spoilers')||0) == 2) {
                    br_;
                    b_ 'This review contains spoilers.';
                }
            }
        };
        tr_ sub {
            td_ 'Moderator note';
            td_ sub { lit_ bb_format $w->{modnote} };
        } if $w->{modnote};
        tr_ class => 'reviewnotspoil', sub {
            td_ '';
            td_ sub {
                label_ class => 'fake_link', for => 'reviewspoil', 'This review contains spoilers, click to view.';
            };
        } if $w->{spoiler};
        tr_ @spoil, sub {
            td_ 'Review';
            td_ sub { lit_ reviews_format $w }
        };
        tr_ @spoil, sub {
            td_ '';
            td_ style => 'text-align: right', sub {
                reviews_vote_ $w;
            };
        };
    }
}


TUWF::get qr{/$RE{wid}(?:(?<sep>[\./])$RE{num})?}, sub {
    my($id, $sep, $num) = (tuwf->capture('id'), tuwf->capture('sep')||'', tuwf->capture('num'));
    my $w = tuwf->dbRowi(
        'SELECT r.id, r.vid, r.rid, r.isfull, r.modnote, r.text, r.spoiler, r.locked, COALESCE(c.count,0) AS count, r.c_flagged, r.c_up, r.c_down, uv.vote, rm.id IS NULL AS can
              , v.title, v.alttitle, rel.title AS rtitle, rel.original AS roriginal, relv.rtype, rv.vote AS my, COALESCE(rv.overrule,false) AS overrule
              , ', sql_user(), ',', sql_totime('r.date'), 'AS date,', sql_totime('r.lastmod'), 'AS lastmod
           FROM reviews r
           JOIN vnt v ON v.id = r.vid
           LEFT JOIN releases rel ON rel.id = r.rid
           LEFT JOIN releases_vn relv ON relv.id = r.rid AND relv.vid = r.vid
           LEFT JOIN users u ON u.id = r.uid
           LEFT JOIN ulist_vns uv ON uv.uid = r.uid AND uv.vid = r.vid
           LEFT JOIN (SELECT id, COUNT(*) FROM reviews_posts GROUP BY id) AS c(id,count) ON c.id = r.id
           LEFT JOIN reviews_votes rv ON rv.id = r.id AND', auth ? ('rv.uid =', \auth->uid) : ('rv.ip =', \norm_ip tuwf->reqIP), '
           LEFT JOIN reviews rm ON rm.vid = r.vid AND rm.uid =', \auth->uid, '
          WHERE r.id =', \$id
    );
    return tuwf->resNotFound if !$w->{id};

    enrich_flatten lang => rid => id => sub { sql 'SELECT id, lang FROM releases_lang WHERE id IN', $_, 'ORDER BY id, lang' }, $w;
    enrich_flatten platforms => rid => id => sub { sql 'SELECT id, platform FROM releases_platforms WHERE id IN', $_, 'ORDER BY id, platform' }, $w;

    my $page = $sep eq '/' ? $num||1 : $sep ne '.' ? 1
        : ceil((tuwf->dbVali('SELECT COUNT(*) FROM reviews_posts WHERE num <=', \$num, 'AND id =', \$id)||9999)/25);
    $num = 0 if $sep ne '.';

    my $posts = tuwf->dbPagei({ results => 25, page => $page },
        'SELECT rp.id, rp.num, rp.hidden, rp.msg',
             ',', sql_user(),
             ',', sql_totime('rp.date'), ' as date',
             ',', sql_totime('rp.edited'), ' as edited
           FROM reviews_posts rp
           LEFT JOIN users u ON rp.uid = u.id
          WHERE rp.id =', \$id, '
          ORDER BY rp.num'
    );
    return tuwf->resNotFound if $num && !grep $_->{num} == $num, @$posts;

    auth->notiRead($id, undef);
    auth->notiRead($id, [ map $_->{num}, $posts->@* ]) if @$posts;

    my $newreview = auth && auth->uid eq $w->{user_id} && tuwf->reqGet('submit');

    my $title = "Review of $w->{title}";
    framework_ title => $title, index => 1, dbobj => $w,
        $num||$page>1 ? (pagevars => {sethash=>$num?$num:'threadstart'}) : (),
    sub {
        div_ class => 'mainbox', sub {
            itemmsg_ $w;
            h1_ $title;
            div_ class => 'notice', sub {
                b_ 'Review has been successfully submitted! ';
                a_ href => "/$w->{id}", "dismiss";
            } if $newreview;
            review_ $w;
        };
        if(grep !defined $_->{hidden}, @$posts) {
            h1_ class => 'boxtitle', 'Comments';
            VNWeb::Discussions::Thread::posts_($w, $posts, $page);
        } else {
            div_ id => 'threadstart', '';
        }
        elm_ 'Reviews.Comment' => $COMMENT, { id => $w->{id}, msg => '' } if !$newreview && $w->{count} <= $page*25 && can_edit t => $w;
    };
};

1;
