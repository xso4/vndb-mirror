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
    langpref_titles
    $DEFAULT_TITLE_LANGS
    $DEFAULT_ALTTITLE_LANGS
/;

TUWF::set('custom_validations')->{langpref} = { type => 'array', maxlength => 5, values => { type => 'hash', keys => {
    lang     => { required => 0, enum => \%LANGUAGE }, # undef referring to the original title language
    latin    => { anybool => 1 },
    original => { anybool => 1 },
    official => { anybool => 1 },
}}};

my $LANGPREF = tuwf->compile({langpref=>1});

sub langpref_parse {
    return undef if !defined $_[0];
    my $p = $LANGPREF->validate(JSON::XS->new->decode($_[0]))->data;
    for (@$p) {
        $_->{official} = $_->{original} = 1 if !defined $_->{lang};
    }
    $p
}

sub langpref_fmt {
    return undef if !defined $_[0];
    JSON::XS->new->canonical(1)->encode([ map +{
        lang => $_->{lang},
        $_->{latin} ? (latin => \1) : (),
        $_->{lang} && $_->{original} ? (original => \1) : (),
        $_->{lang} && $_->{official} ? (official => \1) : (),
    }, $_[0]->@*]);
}


# Returns the preferred (title, alttitle) given an array of
# (vn|releases)_titles-like objects. Same functionality as the SQL view, except
# implemented in perl.
sub langpref_titles {
    my($olang, $titles) = @_;
    my $p = pref();
    my %l = map +($_->{lang},$_), $titles->@*;

    my @title = ('','');
    for my $t (0,1) {
        for ($p->[$t]->@*) {
            next if $_->{original} && $_->{lang} && $_->{lang} ne $olang;
            my $o = $l{ $_->{lang} // $olang } or next;
            next if $_->{official} && defined $o->{official} && !$o->{official};
            $title[$t] = $_->{latin} && length $o->{latin} ? $o->{latin} : $o->{title};
            last;
        }
    }
    return @title;
}


our $DEFAULT_TITLE_LANGS    = [{ lang => undef, latin => 1, official => 1, original => 1 }];
our $DEFAULT_ALTTITLE_LANGS = [{ lang => undef, latin => 0, official => 1, original => 1 }];

my $DEFAULT_SESSION = langpref_fmt($DEFAULT_TITLE_LANGS).langpref_fmt($DEFAULT_ALTTITLE_LANGS);
my $CURRENT_SESSION = $DEFAULT_SESSION;


sub pref {
    my $titles    = langpref_parse(auth->pref('title_langs'))    // $DEFAULT_TITLE_LANGS;
    my $alttitles = langpref_parse(auth->pref('alttitle_langs')) // $DEFAULT_ALTTITLE_LANGS;
    tuwf->req->{langpref} //= [ $titles, $alttitles, langpref_fmt($titles).langpref_fmt($alttitles) ];
}


sub gen_sql {
    my($has_official, $tbl_main, $tbl_titles, $join_col) = @_;
    my $p = pref;

    sub id { ($_[0]{original}?'r':$_[0]{official}?'o':'u').($_[0]{lang}//'') }

    my %joins = map +(id($_),1), $p->[0]->@*, $p->[1]->@*;
    my $var = 'a';
    $joins{$_} = 'x_'.$var++ for sort keys %joins;
    my @joins = map sql(
        "LEFT JOIN $tbl_titles $joins{$_} ON", sql_and
            "$joins{$_}.$join_col = x.$join_col",
            $_ =~ /^r/ ? "$joins{$_}.lang = x.olang" : (),
            length($_) > 1 ? sql("$joins{$_}.lang =", \(''.substr($_,1))) : (),
            $has_official && $_ =~ /^o./ ? "$joins{$_}.official" : (),
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
# (These functions are not currently used)
sub sql_vn_hist { gen_sql 1, 'vn_hist', 'vn_titles_hist', 'chid' }
sub sql_releases_hist { gen_sql 0, 'releases_hist', 'releases_titles_hist', 'chid' }


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
    tuwf->dbExeci('CREATE OR REPLACE TEMPORARY VIEW vnt AS', gen_sql(1, 'vn', 'vn_titles', 'id'));
    tuwf->dbExeci('CREATE OR REPLACE TEMPORARY VIEW releasest AS', gen_sql(0, 'releases', 'releases_titles', 'id'));
};

1;
