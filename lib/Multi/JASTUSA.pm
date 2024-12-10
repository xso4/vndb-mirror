package Multi::JASTUSA;

use v5.36;
use Multi::Core;
use AnyEvent::HTTP;
use JSON::XS 'decode_json';
use VNDB::Config;


my %C = (
    sync_timeout => 6*3600,
    url => 'https://app.jastusa.com/api/v2/shop/es?channelCode=JASTUSA&currency=USD&limit=50&localeCode=en_US&sale=false&sort=newest&zone=US&page=%d',
);


sub run {
    shift;
    $C{ua} = sprintf 'VNDB.org Affiliate Crawler (Multi v%s; contact@vndb.org)', config->{version};
    %C = (%C, @_);

    push_watcher schedule 35*60, $C{sync_timeout}, sub { fetch(1) };
}


sub slug {
    # The slug is not included in the API, so presumably generated in JS.
    # This is reverse engineering attempt based on titles in the store, most likely missing a whole lot of symbols.
    lc($_[0]) =~ s/[-, \[\]]+/-/rg =~ s/^-//r =~ s/-$//r  =~ s/&/and/rg =~ s/♥/love/rg =~ tr/–ωé”“＊³★･;\/?/-we""/rd
}


sub item {
    my($prefix, $p) = @_;
    return 'Invalid object' if !$p->{code} || !$p->{variants}[0] || !$p->{translations}{en_US}{name};
    my $slug = slug $p->{translations}{en_US}{name};
    my $var = $p->{variants}[0];
    return 'Not in stock' if !$var->{inStock};
    return 'No price info' if !defined $var->{price};
    my $price = $var->{price} ? sprintf 'US$ %.2f', $var->{price}/100 : 'free';
    AE::log info => "$prefix $p->{code} at $slug for $price";
    pg_cmd q{UPDATE extlinks SET lastfetch = NOW(), deadsince = NULL, price = $1, data = $2 WHERE site = 'jastusa' AND value = $3},
        [ $price, $slug, $p->{code} ];
    0
}


sub data {
    my($page, $time, $body, $hdr) = @_;
    my $prefix = sprintf '[%.1fs] %d', $time, $page;
    return AE::log warn => "$prefix ERROR: $hdr->{Status} $hdr->{Reason}" if $hdr->{Status} !~ /^2/;
    my $nfo = decode_json $body;
    return AE::log warn => "$prefix ERROR: $hdr->{Status} $hdr->{Reason}" if ref $nfo ne 'HASH' || !$nfo->{pages};

    for my $p ($nfo->{products}->@*) {
        my $r = item($prefix, $p);
        AE::log warn => "$prefix $p->{code}: $r" if $r;
    }

    if($page < $nfo->{pages}) {
        fetch($page+1);
    } else {
        pg_cmd "UPDATE extlinks SET deadsince = NOW(), price = '' WHERE site = 'jastusa' AND deadsince IS NULL AND (lastfetch IS NULL OR lastfetch < NOW()-'1 hour'::interval)";
    }
}


sub fetch {
    my($page) = @_;
    my $ts = AE::now;
    http_get sprintf($C{url}, $page),
        headers => {'User-Agent' => $C{ua}},
        timeout => 60,
        sub { data($page, AE::now-$ts, @_) };
}

1;
