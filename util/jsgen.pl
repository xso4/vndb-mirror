#!/usr/bin/perl

use Cwd 'abs_path';
our $ROOT;
BEGIN { ($ROOT = abs_path $0) =~ s{/util/jsgen\.pl$}{}; }

use lib "$ROOT/lib";
use TUWF;
use JSON::XS;
use VNWeb::Validation ();
use VNDB::Types;

my $js = JSON::XS->new->pretty->canonical;

sub validations {
    print 'window.formVals = '.$js->encode({
        map +($_, { tuwf->compile({ $_ => 1 })->analyze->html5_validation() }),
        qw/ username password email weburl /
    }).";\n";
}

sub types {
    print 'window.vndbTypes = '.$js->encode({
        language => [ map [$_, $LANGUAGE{$_}{txt}, $LANGUAGE{$_}{latin}?\1:\0, $LANGUAGE{$_}{rank}], keys %LANGUAGE ],
    }).";\n";
}

if ($ARGV[0] eq 'types') {
    validations;
    types;
}
