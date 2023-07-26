#!/usr/bin/perl

use Cwd 'abs_path';
our $ROOT;
BEGIN { ($ROOT = abs_path $0) =~ s{/util/jsgen\.pl$}{}; }

use lib "$ROOT/lib";
use TUWF;
use TUWF::Validate::Interop;
use JSON::XS;
use VNWeb::Validation ();
use VNWeb::TimeZone;
use VNDB::ExtLinks ();
use VNDB::Skins;
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
        platform => [ map [$_, $PLATFORM{$_} ], keys %PLATFORM ],
        medium   => [ map [$_, $MEDIUM{$_}{txt}, $MEDIUM{$_}{qty}?\1:\0 ], keys %MEDIUM ],
        voiced   => [ map [$VOICED{$_}{txt}], keys %VOICED ],
        ageRating => [ map [1*$_, $AGE_RATING{$_}{txt}.($AGE_RATING{$_}{ex}?" ($AGE_RATING{$_}{ex})":'')], keys %AGE_RATING ],
    }).";\n";
}

sub zones {
    print 'window.timeZones = '.$js->encode(\@ZONES).";\n";
}

sub vskins {
    print 'window.vndbSkins = '.$js->encode([ map [$_, skins->{$_}{name}], sort { skins->{$a}{name} cmp skins->{$b}{name} } keys skins->%*]).";\n";
}

sub extlinks {
    print 'window.extLinks = '.$js->encode({release => [ map +{
        id     => $_->{id},
        name   => $_->{name},
        fmt    => $_->{fmt},
        regex  => TUWF::Validate::Interop::_re_compat($_->{regex}),
        multi  => $_->{multi}?\1:\0,
        int    => $_->{int}?\1:\0,
        patt   => $_->{pattern},
    }, VNDB::ExtLinks::extlinks_sites('r') ]}).";\n";
}

if ($ARGV[0] eq 'types') { validations; types; }
if ($ARGV[0] eq 'user') { zones; vskins; }
if ($ARGV[0] eq 'extlinks') { extlinks; }
