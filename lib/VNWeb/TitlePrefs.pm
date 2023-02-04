package VNWeb::TitlePrefs;

use v5.26;
use TUWF;
use VNDB::Types;
use VNWeb::Auth;
use VNWeb::DB;
use VNWeb::Validation;
use Exporter 'import';

our @EXPORT = qw/
    titleprefs_obj
    titleprefs_swap
    vnt
    releasest
    producerst
    item_info
/;

our @EXPORT_OK = qw/
    titleprefs_parse
    titleprefs_fmt
    $DEFAULT_TITLE_PREFS
/;


# Parse a string representation of the 'titleprefs' SQL type for use in Perl & Elm.
# (Could also use Postgres row_to_json() to simplify this a bit, but it wouldn't save much)
sub titleprefs_parse {
    return undef if !defined $_[0];
    state $L = qr/([^,]*)/;
    state $B = qr/([tf])/;
    state $O = qr/([tf]?)/;
    state $RE = qr/^\(
        $L,$L,$L,$L,     #  1.. 4 -> t1_lang .. t4_lang
        $L,$L,$L,$L,     #  5.. 8 -> a1_lang .. a4_lang
        $B,$B,$B,$B,$B,  #  9..13 -> t1_latin .. to_latin
        $B,$B,$B,$B,$B,  # 14..18 -> a1_latin .. ao_latin
        $O,$O,$O,$O,     # 19..22 -> t1_official .. t4_official
        $O,$O,$O,$O      # 23..26 -> a1_official .. a4_official
    \)$/x;
    die $_[0] if $_[0] !~ $RE;
    sub b($) { !$_[0] ? undef : $_[0] eq 't' }
    sub l($) { !$_[0] ? undef : $_[0] }
    [
        [ $1 ? { lang => l $1, latin => b $9,  official => b $19 } : ()
        , $2 ? { lang => l $2, latin => b $10, official => b $20 } : ()
        , $3 ? { lang => l $3, latin => b $11, official => b $21 } : ()
        , $4 ? { lang => l $4, latin => b $12, official => b $22 } : ()
        ,      { lang => undef,latin => b $13, official => undef } ],
        [ $5 ? { lang => l $5, latin => b $14, official => b $23 } : ()
        , $6 ? { lang => l $6, latin => b $15, official => b $24 } : ()
        , $7 ? { lang => l $7, latin => b $16, official => b $25 } : ()
        , $8 ? { lang => l $8, latin => b $17, official => b $26 } : ()
        ,      { lang => undef,latin => b $18, official => undef } ],
    ]
}


sub titleprefs_fmt {
    my($p) = @_;
    return undef if !defined $p;
    my sub val { my $v = $p->[$_[0]][$_[1]]; $v && $v->{lang} ? $v->{$_[2]} : undef }
    my sub l($$) { val @_, 'lang' }
    my sub b($$) { my $v = val @_, 'latin'; $v ? 't' : 'f' }
    my sub o($$) { my $v = val @_, 'official'; !defined $v ? '' : $v ? 't' : 'f' }
    '('.join(',',
        l(0,0), l(0,1), l(0,2), l(0,3),
        l(1,0), l(1,1), l(1,2), l(1,3),
        b(0,0), b(0,1), b(0,2), b(0,3), $p->[0][$#{$p->[0]}]{latin} ? 't' : 'f',
        b(1,0), b(1,1), b(1,2), b(1,3), $p->[1][$#{$p->[1]}]{latin} ? 't' : 'f',
        o(0,0), o(0,1), o(0,2), o(0,3),
        o(1,0), o(1,1), o(1,2), o(1,3)
    ).')'
}


# This validation only covers half of the titleprefs, i.e. just the main or alternative title.
TUWF::set('custom_validations')->{titleprefs} = {
    type => 'array',
    maxlength => 5,
    values => { type => 'hash', keys => {
        lang     => { required => 0, enum => \%LANGUAGE }, # undef referring to the original title language
        latin    => { anybool => 1 },
        official => { undefbool => 1 },
    }},
    func => sub {
        # Last one must be olang if n==5.
        return 0 if $_[0]->@* == 5 && $_[0][4]{lang};
        # undef lang is only allowed as sentinel
        return 0 if $_[0]->@* >= 2 && grep !$_[0][$_]{lang}, 0..($_[0]->@*-2);
        # ensure we have an undef lang
        push $_[0]->@*, { lang => undef, latin => '', official => undef } if !grep !$_->{lang}, $_[0]->@*;

        # Remove duplicate languages that will never be matched.
        my %l;
        $_[0] = [ grep {
            my $prio = !defined $_->{official} ? 3 : $_->{official} ? 2 : 1;
            my $dupe = $l{$_->{lang}} && $l{$_->{lang}} <= $prio;
            $l{$_->{lang}} = $prio if !$dupe;
            !$dupe
        } $_[0]->@* ];

        # (XXX: we can also merge adjacent duplicates at this stage)

        # Expand 'Chinese' to the scripts if we have enough free slots.
        # (this is a hack and should ideally be handled in the title selection
        # algorithm, but that selection code has multiple implementations and
        # is already subject to potential performance issues, so I'd rather
        # keep it simple)
        $_[0] = [ map $_->{lang} eq 'zh' ? ($_, {%$_,lang=>'zh-Hant'}, {%$_,lang=>'zh-Hans'}) : ($_), $_[0]->@* ]
            if $_[0]->@* <= 3 && !grep $_->{lang} && $_->{lang} =~ /^zh-/, $_[0]->@*;
        1;
    },
};


our $DEFAULT_TITLE_PREFS = [
    [ { lang => undef, latin => 1, official => undef } ],
    [ { lang => undef, latin => '', official => undef } ],
];

sub pref { tuwf->req->{titleprefs} //= !is_api() && titleprefs_parse(auth->pref('titles')) }


# Returns the preferred (title, alttitle) given an array of
# (vn|releases)_titles-like objects. Same functionality as the SQL view, except
# implemented in perl.
sub titleprefs_obj {
    my($olang, $titles) = @_;
    my $p = pref || $DEFAULT_TITLE_PREFS;
    my %l = map +($_->{lang},$_), $titles->@*;

    my @title = ('','');
    for my $t (0,1) {
        for ($p->[$t]->@*) {
            my $o = $l{$_->{lang} // $olang} or next;
            next if !defined $_->{official} && $o->{lang} ne $olang;
            next if $_->{official} && defined $o->{official} && !$o->{official};
            next if !defined $o->{title};
            $title[$t] = $_->{latin} && length $o->{latin} ? $o->{latin} : $o->{title};
            last;
        }
    }
    return @title;
}


# Returns the preferred (name, alttitle) given a language, latin title and original title.
# For DB entries that only have (title, original) fields.
sub titleprefs_swap {
    my($olang, $title, $original) = @_;
    my $p = pref || $DEFAULT_TITLE_PREFS;

    my @title = ('','');
    for my $t (0,1) {
        for ($p->[$t]->@*) {
            next if $_->{lang} && $_->{lang} ne $olang;
            $title[$t] = $_->{latin} ? $title : $original//$title;
            last;
        }
    }
    return @title;
}


sub gen_sql {
    my($has_official, $tbl_main, $tbl_titles, $join_col) = @_;
    my $p = pref || $DEFAULT_TITLE_PREFS;

    sub id { (!defined $_[0]{official}?'r':$_[0]{official}?'o':'u').($_[0]{lang}//'') }

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
        map +($_->{latin} ? ($joins{ id($_) }.'.latin') : (), $joins{ id($_) }.'.title'), $p->[1]->@*
    ).')';

    sql "(SELECT x.*, $title AS title, $sorttitle AS sorttitle, $alttitle AS alttitle FROM $tbl_main x", @joins, ')';
}


sub vnt()        { tuwf->req->{titleprefs_v} //= pref ? gen_sql 1, 'vn',       'vn_titles',       'id' : 'vnt'       }
sub releasest()  { tuwf->req->{titleprefs_r} //= pref ? gen_sql 0, 'releases', 'releases_titles', 'id' : 'releasest' }
sub producerst() { tuwf->req->{titleprefs_p} //= pref ? sql 'producerst(', \tuwf->req->{auth}{user}{titles}, ')' : 'producerst' }

# (Not currently used)
#sub vnt_hist { gen_sql 1, 'vn_hist', 'vn_titles_hist', 'chid' }
#sub releasest_hist { gen_sql 0, 'releases_hist', 'releases_titles_hist', 'chid' }

# Wrapper around SQL's item_info() with the user's preference applied.
sub item_info($$) { sql 'item_info(', \((tuwf->req->{auth} && tuwf->req->{auth}{user}{titles}) || undef), ',', $_[0], ',', $_[1], ')' }

1;
