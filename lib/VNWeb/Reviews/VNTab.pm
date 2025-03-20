package VNWeb::Reviews::VNTab;

use VNWeb::Prelude;
use VNWeb::Reviews::Lib;


sub reviews_($v, $mini) {
    my $length = tuwf->validate(get =>
        l => { onerror => $mini ? 0 : undef, enum => [0,1,2] },
    )->data;

    article_ sub {
        h1_ 'Reviews';
        p_ class => 'browseopts', sub {
            a_ href => "/$v->{id}/reviews?l=0#review", ($length//3) == 0 ? (class => 'optselected') : (), sprintf 'Short (%d)',  $v->{reviews}{short};
            a_ href => "/$v->{id}/reviews?l=1#review", ($length//3) == 1 ? (class => 'optselected') : (), sprintf 'Medium (%d)', $v->{reviews}{medium};
            a_ href => "/$v->{id}/reviews?l=2#review", ($length//3) == 2 ? (class => 'optselected') : (), sprintf 'Long (%d)',   $v->{reviews}{long};
            a_ href => "/$v->{id}/reviews#review",     !defined $length  ? (class => 'optselected') : (), sprintf 'All (%d)',    $v->{reviews}{total};
        };
    };

    my $lst = tuwf->dbAlli(
        'SELECT r.id, r.rid, r.modnote, r.text, r.length, r.spoiler, r.c_count, r.c_up, r.c_down, uv.vote
              , rv.vote AS my, COALESCE(rv.overrule,false) AS overrule
            , ', sql_totime('r.date'), 'AS date, ', sql_user(), '
           FROM reviews r
           LEFT JOIN users u ON r.uid = u.id
           LEFT JOIN ulist_vns uv ON uv.uid = r.uid AND uv.vid = r.vid
           LEFT JOIN reviews_votes rv ON rv.id = r.id AND', auth ? ('rv.uid =', \auth->uid) : ('rv.ip =', \norm_ip tuwf->reqIP), '
          WhERE NOT r.c_flagged AND r.vid =', \$v->{id},
                defined $length ? ('AND r.length =', \$length) : (), '
          ORDER BY r.c_up-r.c_down DESC'
    );
    return if !@$lst;

    div_ class => 'reviews', sub {
        article_ sub {
            my $r = $_;
            div_ sub {
                span_ sub {
                    txt_ ['Short ', 'Medium ', 'Long ']->[$r->{length}];
                    txt_ 'by '; user_ $r; txt_ ' on '.fmtdate $r->{date}, 'compact';
                    small_ ' contains spoilers' if $r->{spoiler} && (auth->pref('spoilers')||0) == 2;
                };
                a_ href => "/$r->{rid}", $r->{rid} if $r->{rid};
                span_ fmtvote($r->{vote}).'/10' if $r->{vote};
            };
            div_ sub {
                p_ sub { lit_ bb_format $r->{modnote} } if $r->{modnote};
            };
            div_ sub {
                span_ sub {
                    txt_ '<';
                    if(can_edit w => $r) {
                        a_ href => "/$r->{id}/edit", 'edit';
                        txt_ ' - ';
                    }
                    a_ href => "/report/$r->{id}", 'report';
                    txt_ '>';
                };
                my $html = bb_format bb_subst_links($r->{text}), maxlength => $r->{length} ? 700 : undef;
                $html .= fragment sub { txt_ '... '; a_ href => "/$r->{id}#review", ' Read more »' } if $r->{length};
                if($r->{spoiler}) {
                    label_ class => 'review_spoil', sub {
                        input_ type => 'checkbox', class => 'hidden', (auth->pref('spoilers')||0) == 2 ? ('checked', 'checked') : (), undef;
                        div_ sub { lit_ $html };
                        span_ class => 'fake_link', 'This review contains spoilers, click to view.';
                    }
                } else {
                    lit_ $html;
                }
            };
            div_ sub {
                a_ href => "/$r->{id}#threadstart", $r->{c_count} == 1 ? '1 comment' : "$r->{c_count} comments";
                reviews_vote_ $r;
            };
        } for @$lst;
    };
}


TUWF::get qr{/$RE{vid}/(?<mini>mini|full)?reviews}, sub {
    my $mini = !tuwf->capture('mini') ? undef : tuwf->capture('mini') eq 'mini' ? 1 : 0;
    my $v = db_entry tuwf->capture('id');
    return tuwf->resNotFound if !$v;
    VNWeb::VN::Page::enrich_vn($v);

    framework_ title => "Reviews for $v->{title}[1]", index => 1, dbobj => $v, hiddenmsg => 1,
    sub {
        VNWeb::VN::Page::infobox_($v);
        VNWeb::VN::Page::tabs_($v, 'reviews');
        reviews_ $v, $mini;
    };
};

1;
