#!/usr/bin/perl

use v5.36;
use lib 'lib';
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
        releaseImageType => [ map [$_, $RELEASE_IMAGE_TYPE{$_}{txt}], keys %RELEASE_IMAGE_TYPE ],
        drmProperty => [ map [$_, $DRM_PROPERTY{$_}], keys %DRM_PROPERTY ],
        producerType => [ map [$_, $PRODUCER_TYPE{$_}], keys %PRODUCER_TYPE ],
        producerRelation => [ map [$_, $PRODUCER_RELATION{$_}{txt}], keys %PRODUCER_RELATION ],
        vnRelation => [ map [$_, $VN_RELATION{$_}{txt}, $VN_RELATION{$_}{reverse}, $VN_RELATION{$_}{pref}], keys %VN_RELATION ],
        tagCategory => [ map [$_, $TAG_CATEGORY{$_}], keys %TAG_CATEGORY ],
        bloodType => [ map [$_, $BLOOD_TYPE{$_}], keys %BLOOD_TYPE ],
        charSex   => [ map [$_, $CHAR_SEX{$_}], keys %CHAR_SEX ],
        charGender=> [ map [$_, $CHAR_GENDER{$_}], keys %CHAR_GENDER ],
        charRole  => [ map [$_, $CHAR_ROLE{$_}{txt}], keys %CHAR_ROLE ],
        cupSize   => [ map [$_, $CUP_SIZE{$_}], keys %CUP_SIZE ],
    }).";\n";
}

sub zones {
    print 'window.timeZones = '.$js->encode(\@ZONES).";\n";
}

sub vskins {
    print 'window.vndbSkins = '.$js->encode([ map [$_, skins->{$_}{name}], sort { skins->{$a}{name} cmp skins->{$b}{name} } keys skins->%*]).";\n";
}

sub extlinks {
    sub t($t) {
        my $L = \%VNDB::ExtLinks::LINKS;
        [ map +{
            site    => $_,
            label   => $L->{$_}{label},
            fmt     => $L->{$_}{fmt},
            patt    => [ split /(<[^>]+>)/, $L->{$_}{patt} || ($L->{$_}{fmt} =~ s/%s/<code>/rg =~ s/%[0-9]*d/<number>/rg) ],
            $L->{$_}{regex} ? (regex => TUWF::Validate::Interop::_re_compat($L->{$_}{full_regex})) : (),
            $L->{$_}{ent} =~ /\U$t/ ? (multi => 1) : (),
        }, grep $L->{$_}{ent} =~ /$t/i, sort keys %$L ]
    }
    print 'window.extLinks = '.$js->encode({
        release => t('r'),
        staff   => t('s'),
    }).";\n";
}

if ($ARGV[0] eq 'types') { validations; types; }
if ($ARGV[0] eq 'user') { zones; vskins; }
if ($ARGV[0] eq 'extlinks') { extlinks; }
