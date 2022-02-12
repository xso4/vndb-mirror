package VNWeb::LangPref;

use v5.26;
use TUWF;
use VNDB::Types;
use VNWeb::Auth;
use VNWeb::DB;
use VNWeb::Validation;
use Exporter 'import';

our @EXPORT = qw/
    langpref_parse
    langpref_fmt
    $DEFAULT_TITLE_LANGS
    $DEFAULT_ALTTITLE_LANGS
/;

TUWF::set('custom_validations')->{langpref} = { type => 'array', maxlength => 3, values => { type => 'hash', keys => {
    lang     => { required => 0, enum => \%LANGUAGE }, # undef referring to the original title language
    latin    => { anybool => 1 },
    official => { anybool => 1 },
}}};

my $LANGPREF = tuwf->compile({langpref=>1});

sub langpref_parse { defined $_[0] ? $LANGPREF->validate(JSON::XS->new->decode($_[0]))->data : undef }
sub langpref_fmt { defined $_[0] ? JSON::XS->new->canonical(1)->encode($LANGPREF->analyze->coerce_for_json($_[0])) : undef }

our $DEFAULT_TITLE_LANGS    = [{ lang => undef, latin => 1, official => 1 }];
our $DEFAULT_ALTTITLE_LANGS = [{ lang => undef, latin => 0, official => 1 }];


my $current = '';

TUWF::hook before => sub {
    my $titles    = langpref_parse(auth->pref('title_langs'))    // $DEFAULT_TITLE_LANGS;
    my $alttitles = langpref_parse(auth->pref('alttitle_langs')) // $DEFAULT_ALTTITLE_LANGS;

    my $new = langpref_fmt($titles).langpref_fmt($alttitles);
    return if $new eq $current;
    $current = $new;

    sub id { ($_[0]{official}?'o':'u').($_[0]{lang}//'') }

    my %joins = map +(id($_),1), @$titles, @$alttitles;
    my $var = 'a';
    $joins{$_} = 'vnt_'.$var++ for sort keys %joins;
    my @joins = map sql(
        "LEFT JOIN vn_titles $joins{$_} ON $joins{$_}.id = v.id
               AND $joins{$_}.lang =", length($_) > 1 ? \(''.substr($_,1)) : 'v.olang',
         $_ =~ /^o./ ? "AND $joins{$_}.official" : (),
    ), sort keys %joins;

    my $title = 'COALESCE('.join(',',
        map +($_->{latin} ? ($joins{ id($_) }.'.latin') : (), $joins{ id($_) }.'.title'), @$titles
    ).')';
    my $alttitle = 'COALESCE('.join(',',
        (map +($_->{latin} ? ($joins{ id($_) }.'.latin') : (), $joins{ id($_) }.'.title'), @$alttitles), "''"
    ).')';

    tuwf->dbExeci("CREATE OR REPLACE TEMPORARY VIEW vnt AS
        SELECT v.*, $title AS title, $alttitle AS alttitle
          FROM vn v", @joins);
};

1;
