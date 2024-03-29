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
        map +($_, { tuwf->compile({ $_ => 1 })->analyze->html5_validation() }->{pattern}),
        qw/ email weburl /
    }).";\n";
}

sub types {
    print 'window.vndbTypes = '.$js->encode({
        language => [ map [$_, $LANGUAGE{$_}{txt}, $LANGUAGE{$_}{latin}?\1:\0, $LANGUAGE{$_}{rank}], keys %LANGUAGE ],
        platform => [ map [$_, $PLATFORM{$_} ], keys %PLATFORM ],
        medium   => [ map [$_, $MEDIUM{$_}{txt}, $MEDIUM{$_}{qty}?\1:\0 ], keys %MEDIUM ],
        voiced   => [ map [$VOICED{$_}{txt}], keys %VOICED ],
        ageRating => [ map [1*$_, $AGE_RATING{$_}{txt}.($AGE_RATING{$_}{ex}?" ($AGE_RATING{$_}{ex})":'')], keys %AGE_RATING ],
        releaseType => [ map [$_, $RELEASE_TYPE{$_}], keys %RELEASE_TYPE ],
        drmProperty => [ map [$_, $DRM_PROPERTY{$_}], keys %DRM_PROPERTY ],
        producerType => [ map [$_, $PRODUCER_TYPE{$_}], keys %PRODUCER_TYPE ],
        producerRelation => [ map [$_, $PRODUCER_RELATION{$_}{txt}], keys %PRODUCER_RELATION ],
        vnRelation => [ map [$_, $VN_RELATION{$_}{txt}, $VN_RELATION{$_}{reverse}, $VN_RELATION{$_}{pref}], keys %VN_RELATION ],
        tagCategory => [ map [$_, $TAG_CATEGORY{$_}], keys %TAG_CATEGORY ],
    }).";\n";
}

sub zones {
    print 'window.timeZones = '.$js->encode(\@ZONES).";\n";
}

sub vskins {
    print 'window.vndbSkins = '.$js->encode([ map [$_, skins->{$_}{name}], sort { skins->{$a}{name} cmp skins->{$b}{name} } keys skins->%*]).";\n";
}

sub extlinks {
    sub t {
        [ map +{
            id      => $_->{id},
            name    => $_->{name},
            fmt     => $_->{fmt},
            default => $_->{default},
            int     => $_->{int},
            regex   => TUWF::Validate::Interop::_re_compat($_->{regex}),
            patt    => $_->{pattern},
        }, VNDB::ExtLinks::extlinks_sites($_[0]) ]
    }
    print 'window.extLinks = '.$js->encode({
        release => t('r'),
        staff   => t('s'),
    }).";\n";
}

if ($ARGV[0] eq 'types') { validations; types; }
if ($ARGV[0] eq 'user') { zones; vskins; }
if ($ARGV[0] eq 'extlinks') { extlinks; }
