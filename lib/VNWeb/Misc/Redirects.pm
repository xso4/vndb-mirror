package VNWeb::Misc::Redirects;

use VNWeb::Prelude;
use VNWeb::AdvSearch;

sub query { length fu->query ? '?'.fu->query : '' }

# VNDB URLs don't have a trailing /, redirect if we get one.
FU::get qr{(/.+?)/+}, sub($p) { fu->redirect(perm => $p.query) };

# These two are ancient.
FU::get '/notes', sub { fu->redirect(perm => '/d8') };
FU::get '/faq',   sub { fu->redirect(perm => '/d6') };

FU::get '/v/search', sub { fu->redirect(perm => '/v'.query) };

FU::get qr{/$RE{uid}/tags},  sub($id) { fu->redirect(perm => "/g/links?u=$id") };

FU::get qr{/$RE{vid}/staff}, sub($id) { fu->redirect(perm => "/$id#staff") };
FU::get qr{/$RE{vid}/stats}, sub($id) { fu->redirect(perm => "/$id#stats") };
FU::get qr{/$RE{vid}/scr},   sub($id) { fu->redirect(perm => "/$id#screenshots") };
FU::get qr{/img/$RE{imgid}}, sub($id) { fu->redirect(perm => "/$id".query) };

FU::get '/u/tokens', sub { fu->redirect(temp => auth ? '/'.auth->uid.'/edit#api' : '/u/login?ref=/u/tokens') };


FU::get '/v/rand', sub {
    state $stats  ||= fu->sql('SELECT COUNT(*) AS total, COUNT(*) FILTER(WHERE NOT hidden) AS subset FROM vn')->cache(0)->rowh;
    fu->notfound if !$stats->{subset};
    state $sample ||= 100*min 1, (1000 / $stats->{subset}) * ($stats->{total} / $stats->{subset});

    my $filt = advsearch_default 'v';
    my $vn = fu->dbVali('
        SELECT id
          FROM vn v', $filt->{query} || config->{moe} ? '' : ('TABLESAMPLE SYSTEM (', \$sample, ')'), '
         WHERE NOT hidden AND', $filt->sql_where(), '
         ORDER BY random() LIMIT 1'
    );
    fu->notfound if !$vn;
    fu->redirect(temp => "/$vn");
};

1;
