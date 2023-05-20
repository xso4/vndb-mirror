package VNWeb::JS;

use v5.26;
use TUWF;
use VNDB::Config;
use VNWeb::Validation ();
use Exporter 'import';

our @EXPORT = qw/js_api/;


# Provide a '/js/<endpoint>.json' API for the JS front-end.
# The $fun callback is given the validated json request object as argument.
# It should return a string on error or a hash on success.
sub js_api {
    my($endpoint, $schema, $fun) = @_;
    $schema = tuwf->compile({ type => 'hash', keys => $schema }) if ref $schema eq 'HASH';

    TUWF::post qr{/js/\Q$endpoint\E\.json} => sub {
        my $data = tuwf->validate(json => $schema);
        if(!$data) {
            warn "JSON validation failed\ninput: " . JSON::XS->new->allow_nonref->pretty->canonical->encode(tuwf->reqJSON) . "\nerror: " . JSON::XS->new->encode($data->err) . "\n";
            return tuwf->resJSON({_err => 'Invalid request body, please report a bug.'});
        }
        my $res = $fun->($data->data);
        tuwf->resJSON(ref $res ? $res : {_err => $res});
    };
}


# Log errors from JS.
TUWF::post qr{/js-error}, sub {
    my($ev, $source, $lineno, $colno, $stack) = map tuwf->reqPost($_)//'-', qw/ev source lineno colno stack/;
    return if $source =~ /elm\.js/ && $ev =~ /InvalidStateError/;
    my $msg = sprintf
          "\nMessage:  %s"
         ."\nSource:   %s %s:%s\n", $ev, $source, $lineno, $colno;
    $msg .= "Referer:  ".tuwf->reqHeader('referer')."\n" if tuwf->reqHeader('referer');
    $msg .= "Browser:  ".tuwf->reqHeader('user-agent')."\n" if tuwf->reqHeader('user-agent');
    $msg .= ($stack =~ s/[\r\n]+$//r)."\n" if $stack ne '-' && $stack ne 'undefined' && $stack ne 'null';
    warn $msg;
};


# Returns a hashref with widget_name => bundle_name.
sub widgets {
    state $w ||= do {
        my %w;
        my sub grab {
            $w{$1} = $_[0] if $_[1] =~ /(?:^|\W)widget\s*\(\s*['"]([^'"]+)['"]/;
        }
        for my $index (glob config->{root}."/js/*/index.js") {
            my $bundle = $index =~ s#.+/([^/]+)/index\.js$#$1#r;
            my @f;
            {
                open my $F, '<', $index or die $!;
                while(<$F>) {
                    grab($bundle, $_);
                    push @f, $1 if /^\@include (.+)/;
                }
            };
            for (@f) {
                open my $F, '<', config->{root}."/js/$_" or die $1;
                grab($bundle, $_) while (<$F>);
            }
        }
        \%w;
    };
}

1;
