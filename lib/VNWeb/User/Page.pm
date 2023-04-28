package VNWeb::User::Page;

use VNWeb::Prelude;
use VNWeb::Misc::History;


sub _info_table_ {
    my($u, $own) = @_;

    my sub sup {
        strong_ ' ⭐supporter⭐' if $u->{user_support_can} && $u->{user_support_enabled};
    }

    tr_ sub {
        td_ class => 'key', 'Display name';
        td_ sub {
            txt_ $u->{user_uniname};
            sup;
        };
    } if $u->{user_uniname_can} && $u->{user_uniname};
    tr_ sub {
        my $old = tuwf->dbAlli('SELECT date::date, old FROM users_username_hist WHERE id =', \$u->{id},
            auth->permUsermod ? () : 'AND date > NOW()-\'1 month\'::interval', 'ORDER BY date DESC');
        td_ class => 'key', 'Username';
        td_ sub {
            txt_ $u->{user_name};
            user_maybebanned_ $u;
            txt_ ' ('; a_ href => "/$u->{id}", $u->{id};
            txt_ ')';
            debug_ $u;
            sup if !($u->{user_uniname_can} && $u->{user_uniname});
            for(@$old) {
                br_;
                small_ "Changed from '$_->{old}' on $_->{date}.";
            }
        };
    };
    tr_ sub {
        td_ 'Registered';
        td_ fmtdate $u->{registered};
    };
    tr_ sub {
        td_ 'Edits';
        td_ !$u->{c_changes} ? '-' : sub {
            a_ href => "/$u->{id}/hist", $u->{c_changes}
        };
    };
    tr_ sub {
        my $num = sum map $_->{votes}, $u->{votes}->@*;
        my $sum = sum map $_->{total}, $u->{votes}->@*;
        td_ 'Votes';
        td_ !$num ? '-' : sub {
            txt_ sprintf '%d vote%s, %.2f average. ', $num, $num == 1 ? '' : 's', $sum/$num/10;
            a_ href => "/$u->{id}/ulist?votes=1", 'Browse votes »';
        }
    };
    my $lengthvotes = tuwf->dbRowi('SELECT count(*) AS count, sum(length) AS sum, bool_or(not private) as haspub FROM vn_length_votes WHERE uid =', \$u->{id});
    tr_ sub {
        td_ 'Play times';
        td_ sub {
            vnlength_ $lengthvotes->{sum};
            txt_ sprintf ' from %d submitted play times. ', $lengthvotes->{count};
            a_ href => "/$u->{id}/lengthvotes", 'Browse votes »' if $own || $lengthvotes->{haspub};
        };
    } if $lengthvotes->{count};
    tr_ sub {
        my $vns = tuwf->dbVali(
            'SELECT COUNT(vid) FROM ulist_vns
              WHERE NOT (labels && ARRAY[', \5, ',', \6, ']::smallint[]) AND uid =', \$u->{id}, $own ? () : 'AND NOT c_private'
        )||0;
        my $privrel = $own ? '1=1' : 'EXISTS(
            SELECT 1 FROM releases_vn rv JOIN ulist_vns uv ON uv.vid = rv.vid WHERE uv.uid = r.uid AND rv.id = r.rid AND NOT uv.c_private
        )';
        my $rel = tuwf->dbVali('SELECT COUNT(*) FROM rlists r WHERE', $privrel, 'AND r.uid =', \$u->{id})||0;
        td_ 'List stats';
        td_ !$vns && !$rel ? '-' : sub {
            txt_ sprintf '%d release%s of %d visual novel%s. ',
                $rel, $rel == 1 ? '' : 's',
                $vns, $vns == 1 ? '' : 's';
            a_ href => "/$u->{id}/ulist?vnlist=1", 'Browse list »';
        };
    };
    tr_ sub {
        my $cnt = tuwf->dbVali('SELECT COUNT(*) FROM reviews WHERE uid =', \$u->{id});
        td_ 'Reviews';
        td_ !$cnt ? '-' : sub {
            txt_ sprintf '%d review%s. ', $cnt, $cnt == 1 ? '' : 's';
            a_ href => "/w?u=$u->{id}", 'Browse reviews »';
        };
    };
    tr_ sub {
        my $stats = tuwf->dbRowi('SELECT COUNT(DISTINCT tag) AS tags, COUNT(DISTINCT vid) AS vns FROM tags_vn WHERE uid =', \$u->{id});
        td_ 'Tags';
        td_ !$u->{c_tags} ? '-' : !$stats->{tags} ? '-' : sub {
            txt_ sprintf '%d vote%s on %d distinct tag%s and %d visual novel%s. ',
                $u->{c_tags},   $u->{c_tags}   == 1 ? '' : 's',
                $stats->{tags}, $stats->{tags} == 1 ? '' : 's',
                $stats->{vns},  $stats->{vns}  == 1 ? '' : 's';
            a_ href => "/g/links?u=$u->{id}", 'Browse tags »';
        };
    };
    tr_ sub {
        td_ 'Images';
        td_ sub {
            txt_ sprintf '%d images flagged. ', $u->{c_imgvotes};
            a_ href => "/img/list?u=$u->{id}", 'Browse image votes »';
        };
    } if $u->{c_imgvotes};
    tr_ sub {
        my $stats = tuwf->dbRowi('SELECT COUNT(*) AS posts, COUNT(*) FILTER (WHERE num = 1) AS threads FROM threads_posts WHERE uid =', \$u->{id});
        $stats->{posts} += tuwf->dbVali('SELECT COUNT(*) FROM reviews_posts WHERE uid =', \$u->{id});
        td_ 'Forum stats';
        td_ !$stats->{posts} ? '-' : sub {
            txt_ sprintf '%d post%s, %d new thread%s. ',
                $stats->{posts},   $stats->{posts}   == 1 ? '' : 's',
                $stats->{threads}, $stats->{threads} == 1 ? '' : 's';
            a_ href => "/$u->{id}/posts", 'Browse posts »';
        };
    };

    my $traits = tuwf->dbAlli('SELECT u.tid, t.name, g.id as "group", g.name AS groupname FROM users_traits u JOIN traits t ON t.id = u.tid LEFT JOIN traits g ON g.id = t.gid WHERE u.id =', \$u->{id}, 'ORDER BY g.gorder, t.name');
    my @groups;
    for (@$traits) {
        push @groups, $_ if !@groups || $groups[$#groups]{group} ne $_->{group};
        push $groups[$#groups]{traits}->@*, $_;
    }
    tr_ sub {
        td_ class => 'key', sub { a_ href => "/$_->{group}", $_->{groupname} };
        td_ sub { join_ ', ', sub { a_ href => "/$_->{tid}", $_->{name} }, $_->{traits}->@* };
    } for @groups;
}


sub _votestats_ {
    my($u, $own) = @_;

    my $sum = sum map $_->{total}, $u->{votes}->@*;
    my $max = max map $_->{votes}, $u->{votes}->@*;
    my $num = sum map $_->{votes}, $u->{votes}->@*;

    table_ class => 'votegraph', sub {
        thead_ sub { tr_ sub { td_ colspan => 2, 'Vote stats' } };
        tfoot_ sub { tr_ sub { td_ colspan => 2, sprintf '%d vote%s total, average %.2f', $num, $num == 1 ? '' : 's', $sum/$num/10 } };
        tr_ sub {
            my $num = $_;
            my $votes = [grep $num == $_->{idx}, $u->{votes}->@*]->[0]{votes} || 0;
            td_ class => 'number', $num;
            td_ class => 'graph', sub {
                div_ style => sprintf('width: %dpx', ($votes||0)/$max*250), ' ';
                txt_ $votes||0;
            };
        } for (reverse 1..10);
    };

    my $recent = tuwf->dbAlli('
        SELECT v.id, v.title, uv.vote,', sql_totime('uv.vote_date'), 'AS date
          FROM ulist_vns uv
          JOIN', vnt, 'v ON v.id = uv.vid
         WHERE uv.vote IS NOT NULL AND uv.uid =', \$u->{id}, $own ? () : ('AND NOT uv.c_private AND NOT v.hidden'), '
         ORDER BY uv.vote_date DESC LIMIT', \8
    );

    table_ class => 'recentvotes stripe', sub {
        thead_ sub { tr_ sub { td_ colspan => 3, sub {
            txt_ 'Recent votes';
            span_ sub { txt_ '('; a_ href => "/$u->{id}/ulist?votes=1", 'show all'; txt_ ')' };
        } } };
        tr_ sub {
            my $v = $_;
            td_ sub { a_ href => "/$v->{id}", tattr $v; };
            td_ fmtvote $v->{vote};
            td_ fmtdate $v->{date};
        } for @$recent;
    };

    clearfloat_;
}


TUWF::get qr{/$RE{uid}}, sub {
    my $u = tuwf->dbRowi(q{
        SELECT id, c_changes, c_votes, c_tags, c_imgvotes
             ,}, sql_totime('registered'), q{ AS registered
             ,}, sql_user(), q{
          FROM users u
         WHERE id =}, \tuwf->capture('id')
    );
    return tuwf->resNotFound if !$u->{id};

    my $own = (auth && auth->uid eq $u->{id}) || auth->permUsermod;

    $u->{votes} = tuwf->dbAlli('
        SELECT (uv.vote::numeric/10)::int AS idx, COUNT(uv.vote) as votes, SUM(uv.vote) AS total
          FROM ulist_vns uv
         WHERE uv.vote IS NOT NULL AND uv.uid =', \$u->{id}, $own ? () : 'AND NOT uv.c_private', '
         GROUP BY (uv.vote::numeric/10)::int
    ');

    my $title = user_displayname($u)."'s profile";
    framework_ title => $title, dbobj => $u,
    sub {
        article_ class => 'userpage', sub {
            h1_ $title;
            table_ class => 'stripe', sub { _info_table_ $u, $own };
        };

        article_ sub {
            h1_ 'Vote statistics';
            div_ class => 'votestats', sub { _votestats_ $u, $own };
        } if grep $_->{votes} > 0, $u->{votes}->@*;

        if($u->{c_changes}) {
            h1_ class => 'boxtitle', sub { a_ href => "/$u->{id}/hist", 'Recent changes' };
            VNWeb::Misc::History::tablebox_ $u->{id}, {p=>1}, nopage => 1, results => 10;
        }
    };
};

1;
