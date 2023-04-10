package VNWeb::Misc::JS;

use VNWeb::Prelude;

TUWF::post qr{/js-error}, sub {
    my $msg = sprintf
          "\nMessage:  %s"
         ."\nSource:   %s %s:%s\n", map tuwf->reqPost($_)//'-', qw/ev source lineno colno/;
    $msg .= "Referer:  ".tuwf->reqHeader('referer')."\n" if tuwf->reqHeader('referer');
    $msg .= "Browser:  ".tuwf->reqHeader('user-agent')."\n" if tuwf->reqHeader('user-agent');
    my $stack = tuwf->reqPost('stack');
    $msg .= ($stack =~ s/[\r\n]+$//r)."\n" if $stack && $stack ne 'undefined' && $stack ne 'null';
    warn $msg;
};

1;
