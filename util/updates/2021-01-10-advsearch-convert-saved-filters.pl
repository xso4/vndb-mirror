#!/usr/bin/perl

use v5.24;
use warnings;
use TUWF;
use Cwd 'abs_path';

my $ROOT;
BEGIN { ($ROOT = abs_path $0) =~ s{/util/updates/[^/]+.pl$}{}; }

use lib $ROOT.'/lib';
use VNDB::Config;

BEGIN { TUWF::set %{ config->{tuwf} } };

use VNWeb::AdvSearch;
use VNWeb::Filters;

for my $r (tuwf->dbAlli('SELECT id, filter_vn AS fil FROM users WHERE filter_vn <> \'\' AND NOT EXISTS(SELECT 1 FROM saved_queries WHERE uid = id AND name = \'\' AND qtype = \'v\') ORDER BY id')->@*) {
    next if $r->{fil} =~ /^tagspoil-\d+$/;

    # HACK: trick VNWeb code into thinking we're logged in as the user owning the filter.
    tuwf->{_TUWF}{request_data}{auth} = bless { user => { user_id => $r->{id} } }, 'VNWeb::Auth';

    my $q = eval { tuwf->compile({advsearch => 'v'})->validate(filter_vn_adv filter_parse v => $r->{fil})->data };
    if(!$q) {
        warn "Unable to convert VN filter for u$r->{id}, \"$r->{fil}\": $@";
        next;
    }
    my $qs = $q->query_encode;
    tuwf->dbExeci('INSERT INTO saved_queries', { uid => $r->{id}, qtype => 'v', name => '', query => $qs }) if $qs;
}

for my $r (tuwf->dbAlli('SELECT id, filter_release AS fil FROM users WHERE filter_release <> \'\' AND NOT EXISTS(SELECT 1 FROM saved_queries WHERE uid = id AND name = \'\' AND qtype = \'r\') ORDER BY id')->@*) {
    tuwf->{_TUWF}{request_data}{auth} = bless { user => { user_id => $r->{id} } }, 'VNWeb::Auth';

    my $q = eval { tuwf->compile({advsearch => 'r'})->validate(filter_release_adv filter_parse r => $r->{fil})->data };
    if(!$q) {
        warn "Unable to convert release filter for u$r->{id}, \"$r->{fil}\": $@";
        next;
    }
    my $qs = $q->query_encode;
    tuwf->dbExeci('INSERT INTO saved_queries', { uid => $r->{id}, qtype => 'r', name => '', query => $qs }) if $qs;
}

tuwf->dbCommit;
