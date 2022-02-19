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
    sql_vn_hist
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

my $DEFAULT_SESSION = langpref_fmt($DEFAULT_TITLE_LANGS).langpref_fmt($DEFAULT_ALTTITLE_LANGS);
my $CURRENT_SESSION = $DEFAULT_SESSION;


sub pref {
    my $titles    = langpref_parse(auth->pref('title_langs'))    // $DEFAULT_TITLE_LANGS;
    my $alttitles = langpref_parse(auth->pref('alttitle_langs')) // $DEFAULT_ALTTITLE_LANGS;
    tuwf->req->{langpref} //= [ $titles, $alttitles, langpref_fmt($titles).langpref_fmt($alttitles) ];
}


sub gen_sql {
    my($tbl_main, $tbl_titles, $join_col) = @_;
    my $p = pref;

    sub id { ($_[0]{official}?'o':'u').($_[0]{lang}//'') }

    my %joins = map +(id($_),1), $p->[0]->@*, $p->[1]->@*;
    my $var = 'a';
    $joins{$_} = 'x_'.$var++ for sort keys %joins;
    my @joins = map sql(
        "LEFT JOIN $tbl_titles $joins{$_} ON $joins{$_}.$join_col = x.$join_col
               AND $joins{$_}.lang =", length($_) > 1 ? \(''.substr($_,1)) : 'x.olang',
         $_ =~ /^o./ ? "AND $joins{$_}.official" : (),
    ), sort keys %joins;

    my $title = 'COALESCE('.join(',',
        map +($_->{latin} ? ($joins{ id($_) }.'.latin') : (), $joins{ id($_) }.'.title'), $p->[0]->@*
    ).')';
    my $sorttitle = 'COALESCE('.join(',',
        map +($joins{ id($_) }.'.latin', $joins{ id($_) }.'.title'), $p->[0]->@*
    ).')';
    my $alttitle = 'COALESCE('.join(',',
        (map +($_->{latin} ? ($joins{ id($_) }.'.latin') : (), $joins{ id($_) }.'.title'), $p->[1]->@*), "''"
    ).')';

    sql "SELECT x.*, $title AS title, $sorttitle AS sorttitle, $alttitle AS alttitle FROM $tbl_main x", @joins;
}


# Similar to the 'vnt' VIEW, except for vn_hist and it generates a SELECT query for inline use.
sub sql_vn_hist { gen_sql 'vn_hist', 'vn_titles_hist', 'chid' }


# Run the given subroutine with the default language preferences, by
# temporarily disabling any user preferences in the current database session.
# (This function is a hack)
sub run_with_defaults {
    my($f) = @_;
    return $f->() if $CURRENT_SESSION eq $DEFAULT_SESSION;
    tuwf->dbExeci('SET search_path TO public,pg_temp');
    my $r;
    my $e = eval { $r = $f->(); 1 };
    my $s = $@;
    tuwf->dbExeci('SET search_path TO public');
    die $s if !$e;
    $r;
}

TUWF::hook db_connect => sub { $CURRENT_SESSION = $DEFAULT_SESSION };

TUWF::hook before => sub {
    my $p = pref;
    return if $p->[2] eq $CURRENT_SESSION;
    $CURRENT_SESSION = $p->[2];
    tuwf->dbExeci('CREATE OR REPLACE TEMPORARY VIEW vnt AS', gen_sql('vn', 'vn_titles', 'id'));
};

1;
