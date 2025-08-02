#!/usr/bin/env perl

use v5.36;
use lib 'lib';
use FU::Validate;
use FU::Util 'json_format';
use VNWeb::Validation ();
use VNWeb::TimeZone;
use VNDB::ExtLinks '%LINKS', 'extlink_printf';
use VNDB::Skins;
use VNDB::Types;
use VNDB::Func 'fmtrating';

my @LINKS = grep $_ eq 'website' || $LINKS{$_}{parse}, sort keys %LINKS;


# Attempts to convert a stringified Perl regex into something that is compatible with JS.
# - @ should not be escaped
# - (?^: is a perl alias for (?d-imnsx:
# - Javascript doesn't officially support embedded modifiers in the first place, so these are removed
# Regexes compiled with any of /imsx will not work properly.
sub re_compat($re) { $re =~ s/\\@/@/gr =~ s{\(\?\^?[alupimnsx]*(?:-[imnsx]+)?(?=[:\)])}{(?}gr =~ s/^\(\?:(.+)\)$/$1/r; }

sub tojson($obj) { json_format $obj, pretty => 1, canonical => 1 }


sub validations {
    print 'window.formVals = '.tojson({
        email => re_compat($FU::Validate::re_email),
        weburl => re_compat($FU::Validate::re_weburl),
    }).";\n";
}

sub types {
    print 'window.vndbTypes = '.tojson({
        language => [ map [$_, $LANGUAGE{$_}{txt}, $LANGUAGE{$_}{latin}?\1:\0, $LANGUAGE{$_}{rank}], keys %LANGUAGE ],
        platform => [ map [$_, $PLATFORM{$_} ], keys %PLATFORM ],
        medium   => [ map [$_, $MEDIUM{$_}{txt}, $MEDIUM{$_}{qty}?\1:\0 ], keys %MEDIUM ],
        voiced   => [ map [$VOICED{$_}{txt}], keys %VOICED ],
        ageRating =>[ map [1*$_, $AGE_RATING{$_}{txt}.($AGE_RATING{$_}{ex}?" ($AGE_RATING{$_}{ex})":'')], keys %AGE_RATING ],
        ratings  => [ map fmtrating($_), 1..10 ],
        animated => [ map $ANIMATED{$_}{txt}, keys %ANIMATED ],
        releaseType => [ map [$_, $RELEASE_TYPE{$_}], keys %RELEASE_TYPE ],
        releaseImageType => [ map [$_, $RELEASE_IMAGE_TYPE{$_}{txt}], keys %RELEASE_IMAGE_TYPE ],
        rlistStatus => [ values %RLIST_STATUS ],
        drmProperty => [ map [$_, $DRM_PROPERTY{$_}], keys %DRM_PROPERTY ],
        producerType => [ map [$_, $PRODUCER_TYPE{$_}], keys %PRODUCER_TYPE ],
        producerRelation => [ map [$_, $PRODUCER_RELATION{$_}{txt}], keys %PRODUCER_RELATION ],
        vnRelation => [ map [$_, $VN_RELATION{$_}{txt}, $VN_RELATION{$_}{reverse}, $VN_RELATION{$_}{pref}], keys %VN_RELATION ],
        vnLength  => [ map [1*$_, $VN_LENGTH{$_}{txt}.($VN_LENGTH{$_}{time}?" ($VN_LENGTH{$_}{time})":'')], keys %VN_LENGTH ],
        creditType=> [ map [$_, $CREDIT_TYPE{$_}], keys %CREDIT_TYPE ],
        devStatus => [ map [1*$_, $DEVSTATUS{$_} ], keys %DEVSTATUS ],
        tagCategory => [ map [$_, $TAG_CATEGORY{$_}], keys %TAG_CATEGORY ],
        boardType => [ map [$_, $BOARD_TYPE{$_}{txt}], keys %BOARD_TYPE ],
        bloodType => [ map [$_, $BLOOD_TYPE{$_}], keys %BLOOD_TYPE ],
        staffType => [ map [$_, $STAFF_TYPE{$_}], keys %STAFF_TYPE ],
        charSex   => [ map [$_, $CHAR_SEX{$_}], keys %CHAR_SEX ],
        charGender=> [ map [$_, $CHAR_GENDER{$_}], keys %CHAR_GENDER ],
        charRole  => [ map [$_, $CHAR_ROLE{$_}{txt}], keys %CHAR_ROLE ],
        cupSize   => [ map [$_, $CUP_SIZE{$_}], keys %CUP_SIZE ],
        extLinks  => [ map [$_, $LINKS{$_}{ent}, $LINKS{$_}{label}], @LINKS ],
    }).";\n";
}

sub zones {
    print 'window.timeZones = '.tojson(\@ZONES).";\n";
}

sub vskins {
    print 'window.vndbSkins = '.tojson([ map [$_, skins->{$_}{name}], sort { skins->{$a}{name} cmp skins->{$b}{name} } keys skins->%*]).";\n";
}

sub extlinks {
    print 'window.extLinksPatt = '.tojson([
        map $LINKS{$_}{parse} ? [ split /(<[^>]+>)/, $LINKS{$_}{patt} || ((extlink_printf($_, 0))[0] =~ s/%s/<code>/rg =~ s/%[0-9]*d/<number>/rg) ] : undef,
        @LINKS
    ])."\n";
}

if ($ARGV[0] eq 'types') { validations; types; }
if ($ARGV[0] eq 'user') { zones; vskins; }
if ($ARGV[0] eq 'extlinks') { extlinks; }
