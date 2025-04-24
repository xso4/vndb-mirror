package VNWeb::JS;

use v5.36;
use FU;
use VNDB::Config;
use VNWeb::Validation ();
use Exporter 'import';

our @EXPORT = qw/js_api/;


# Provide a '/js/<endpoint>.json' API for the JS front-end.
# The $fun callback is given the validated json request object as argument.
# It should return a string on error or a hash on success.
sub js_api {
    my($endpoint, $schema, $fun) = @_;
    $schema = FU::Validate->compile({ keys => $schema }) if ref $schema eq 'HASH';

    FU::post "/js/$endpoint.json" => sub {
        my $data = eval { fu->json($schema) };
        if(!$data) {
            my $err = $@;
            my $key = $err isa 'FU::Validate::err' && ($err->{errors}[0]//{})->{key};
            warn "JSON validation failed\ninput: " . fu->json . "\nerror: $err\n";
            fu->send_json({_err => 'Form validation failed'.($key ? " ($key)." : '.')});
        }
        my $res = $fun->($data);
        fu->send_json(ref $res ? $res : {_err => $res});
    };
}


# Log errors from JS.
FU::post '/js-error', sub {
    my($ev, $source, $lineno, $colno, $stack) = map fu->formdata($_, {onerror=>'-'}), qw/ev source lineno colno stack/;
    my $msg = sprintf
          "\nMessage:  %s"
         ."\nSource:   %s %s:%s\n", $ev, $source, $lineno, $colno;
    $msg .= "Referer:  ".fu->header('referer')."\n" if fu->header('referer');
    $msg .= "Browser:  ".fu->header('user-agent')."\n" if fu->header('user-agent');
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
                while (local $_ = <$F>) {
                    grab($bundle, $_);
                    push @f, $1 if /^\@include (.+)/ && !/ \.gen\//;
                }
            };
            for (@f) {
                open my $F, '<', config->{root}."/js/$bundle/$_" or die $!;
                grab($bundle, $_) while (<$F>);
            }
        }
        \%w;
    };
}

1;
