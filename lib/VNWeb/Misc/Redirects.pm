package VNWeb::Misc::Redirects;

use VNWeb::Prelude;
use VNWeb::AdvSearch;


# VNDB URLs don't have a trailing /, redirect if we get one.
TUWF::get qr{(/.+?)/+}, sub { tuwf->resRedirect(tuwf->capture(1).tuwf->reqQuery(), 'perm') };

# These two are ancient.
TUWF::get qr{/notes}, sub { tuwf->resRedirect('/d8', 'perm') };
TUWF::get qr{/faq},   sub { tuwf->resRedirect('/d6', 'perm') };

TUWF::get qr{/v/search}, sub { tuwf->resRedirect('/v'.tuwf->reqQuery(), 'perm') };

TUWF::get qr{/experimental/v}, sub { tuwf->resRedirect('/v'.tuwf->reqQuery(), 'perm') };
TUWF::get qr{/experimental/r}, sub { tuwf->resRedirect('/r'.tuwf->reqQuery(), 'perm') };

TUWF::get qr{/u/list(/[a-z0]|/all)?}, sub { tuwf->resRedirect('/u'.(tuwf->capture(1)//'/all'), 'perm') };

TUWF::get qr{/$RE{uid}/tags},  sub { tuwf->resRedirect('/g/links?u='.tuwf->capture('id'), 'perm') };

TUWF::get qr{/$RE{vid}/staff}, sub { tuwf->resRedirect(sprintf '/%s#staff',       tuwf->capture('id')) };
TUWF::get qr{/$RE{vid}/stats}, sub { tuwf->resRedirect(sprintf '/%s#stats',       tuwf->capture('id')) };
TUWF::get qr{/$RE{vid}/scr},   sub { tuwf->resRedirect(sprintf '/%s#screenshots', tuwf->capture('id')) };


TUWF::get qr{/v/rand}, sub {
    state $stats  ||= tuwf->dbRowi('SELECT COUNT(*) AS total, COUNT(*) FILTER(WHERE NOT hidden) AS subset FROM vn');
    state $sample ||= 100*min 1, (100 / $stats->{subset}) * ($stats->{total} / $stats->{subset});

    my $filt = advsearch_default 'v';
    my $vn = tuwf->dbVali('
        SELECT id
          FROM vn v', $filt->{query} ? '' : ('TABLESAMPLE SYSTEM (', \$sample, ')'), '
         WHERE NOT hidden AND', $filt->sql_where(), '
         ORDER BY random() LIMIT 1'
    );
    return tuwf->resNotFound if !$vn;
    tuwf->resRedirect("/$vn", 'temp');
};

1;
