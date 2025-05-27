package VNWeb::Reviews::Page;

use VNWeb::Prelude;
use VNWeb::Releases::Lib;
use VNWeb::Reviews::Lib;


my $COMMENT = form_compile any => {
    id  => { vndbid => 'w' },
    msg => { maxlength => 32768 }
};

js_api ReviewComment => $COMMENT, sub($data) {
    my $w = fu->sql('SELECT id, locked FROM reviews WHERE id = $1', $data->{id})->rowh or fu->notfound;
    fu->denied if !can_edit t => $w;

    my $num = SQL 'COALESCE((SELECT MAX(num)+1 FROM reviews_posts WHERE id =', $data->{id}, '),1)';
    my $msg = bb_subst_links $data->{msg};
    $num = fu->SQL('INSERT INTO reviews_posts', VALUES({ id => $w->{id}, num => $num, uid => auth->uid, msg => $msg }), 'RETURNING num')->val;
    +{ _redir => "/$w->{id}.$num#last" };
};



sub review_ {
    my($w) = @_;

    input_ type => 'checkbox', class => 'hidden', id => 'reviewspoil', (auth->pref('spoilers')||0) == 2 ? ('checked', 'checked') : (), undef;
    my @spoil = $w->{spoiler} ? (class => 'reviewspoil') : ();
    table_ class => 'fullreview', sub {
        tr_ sub {
            td_ 'Subject';
            td_ sub {
                a_ href => "/$w->{vid}", tattr $w;
                if($w->{rid}) {
                    br_;
                    platform_ $_ for $w->{platforms}->@*;
                    abbr_ class => "icon-lang-$_", title => $LANGUAGE{$_}{txt}, '' for $w->{lang}->@*;
                    abbr_ class => "icon-rt$w->{rtype}", title => $w->{rtype}, '' if $w->{rtype};
                    a_ href => "/$w->{rid}", tattr $w->{rtitle};
                    b_ ' (different visual novel)' if !$w->{rtype};
                }
            };
        };
        tr_ sub {
            td_ 'By';
            td_ sub {
                span_ style => 'float: right; padding-left: 25px; text-align: right', sub {
                    txt_ 'Helpfulness: '.reviews_helpfulness($w);
                    br_;
                    strong_ 'Vote: '.fmtvote($w->{vote}) if $w->{vote};
                };
                user_ $w;
                my($date, $lastmod) = map $_&&fmtdate($_,'compact'), $w->@{'date', 'lastmod'};
                txt_ " on $date";
                small_ " last updated on $lastmod" if $lastmod && $date ne $lastmod;
                br_ if $w->{c_flagged} || $w->{locked} || ($w->{spoiler} && (auth->pref('spoilers')||0) == 2);
                if($w->{c_flagged}) {
                    br_;
                    small_ 'Flagged: this review is below the voting threshold and not visible on the VN page.';
                }
                if($w->{locked}) {
                    br_;
                    small_ 'Locked: commenting on this review has been disabled.';
                }
                if($w->{spoiler} && (auth->pref('spoilers')||0) == 2) {
                    br_;
                    strong_ 'This review contains spoilers.';
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
            td_ sub { lit_ bb_format bb_subst_links $w->{text} }
        };
        tr_ @spoil, sub {
            td_ '';
            td_ style => 'text-align: right', sub {
                reviews_vote_ $w;
            };
        };
    }
}


FU::get qr{/$RE{wid}(?:([\./])($RE{num}))?}, sub($id, $sep='', $num=0) {
    VNWeb::Discussions::Thread::mark_patrolled($id, $num) if $sep eq '.';

    my $w = fu->SQL(
        'SELECT r.id, r.vid, r.rid, r.length, r.modnote, r.text, r.spoiler, r.locked, COALESCE(c.count,0) AS count, r.c_flagged, r.c_up, r.c_down, uv.vote
              , v.title, rel.title AS rtitle, relv.rtype, rv.vote AS my, COALESCE(rv.overrule,false) AS overrule, ', USER, ', r.date, r.lastmod
           FROM reviews r
           JOIN', VNT, 'v ON v.id = r.vid
           LEFT JOIN', RELEASEST, 'rel ON rel.id = r.rid
           LEFT JOIN releases_vn relv ON relv.id = r.rid AND relv.vid = r.vid
           LEFT JOIN users u ON u.id = r.uid
           LEFT JOIN ulist_vns uv ON uv.uid = r.uid AND uv.vid = r.vid
           LEFT JOIN (SELECT id, COUNT(*) FROM reviews_posts GROUP BY id) AS c(id,count) ON c.id = r.id
           LEFT JOIN reviews_votes rv ON rv.id = r.id AND', auth ? ('rv.uid =', auth->uid) : ('rv.ip =', norm_ip fu->ip), '
          WHERE r.id =', $id
    )->rowh or fu->notfound;

    $w->{lang} = fu->sql('SELECT lang FROM releases_titles WHERE id = $1 ORDER BY lang', $w->{rid})->flat;
    $w->{platforms} = fu->sql('SELECT platform FROM releases_platforms WHERE id = $1 ORDER BY platform', $w->{rid})->flat;

    my $page = $sep eq '/' ? $num||1 : $sep ne '.' ? 1
        : ceil((fu->SQL('SELECT COUNT(*) FROM reviews_posts WHERE num <=', $num, 'AND id =', $id)->val||9999)/25);
    $num = 0 if $sep ne '.';

    my $posts = fu->SQL(
        'SELECT rp.id, rp.num, rp.hidden, rp.msg, rp.date, rp.edited, ', USER, '
           FROM reviews_posts rp
           LEFT JOIN users u ON rp.uid = u.id
          WHERE rp.id =', $id, '
          ORDER BY rp.num
          LIMIT 25 OFFSET', 25*($page-1)
    )->allh;
    fu->notfound if $num && !grep $_->{num} == $num, @$posts;

    auth->notiRead($id, undef);
    auth->notiRead($id, [ map $_->{num}, $posts->@* ]) if @$posts;

    my $newreview = auth && $w->{user_id} && auth->uid eq $w->{user_id} && fu->query('submit');

    my $title = "Review of $w->{title}[1]";
    framework_ title => $title, index => 1, dbobj => $w,
        $num||$page>1 ? (pagevars => {sethash=>$num?"p$num":'threadstart'}) : (),
    sub {
        article_ sub {
            itemmsg_ $w;
            h1_ $title;
            div_ class => 'notice', sub {
                h2_ 'Review has been successfully submitted! ';
                a_ href => "/$w->{id}", "dismiss";
            } if $newreview;
            review_ $w;
        };
        if(grep !defined $_->{hidden}, @$posts) {
            nav_ sub {
                h1_ 'Comments';
            };
            VNWeb::Discussions::Thread::posts_($w, $posts, $page);
        } else {
            div_ id => 'threadstart', '';
        }
        div_ widget(ReviewComment => $COMMENT, { id => $w->{id}, msg => '' }), '' if !$newreview && $w->{count} <= $page*25 && can_edit t => $w;
    };
};

1;
