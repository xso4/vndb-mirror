package VNWeb::JS;

use TUWF;
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

1;
