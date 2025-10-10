package VNWeb::TitlePrefs;

use v5.36;
use builtin qw/true false/;
use FU;
use FU::SQL;
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
    charst
    staff_aliast
    VNT
    RELEASEST
    PRODUCERST
    CHARST
    STAFF_ALIAST
    ITEM_INFO
    item_info
/;

our @EXPORT_OK = qw/
    $DEFAULT_TITLE_PREFS
    titleprefs_is_default
/;


# Corresponds to the SQL 'titleprefs' type.
$FU::Validate::default_validations{titleprefs} = {
    keys => {
        to_latin => { anybool => 1 },
        ao_latin => { anybool => 1 },
        map +(
            "${_}_lang"     => { default => undef, enum => \%LANGUAGE },
            "${_}_latin"    => { anybool => 1 },
            "${_}_official" => { undefbool => 1 },
        ), 't1'..'t4', 'a1'..'a4'
    },
    func => sub {
        my $p = $_[0];
        for my $t ('t', 'a') {
            my @l = grep $_->[0], map [@{$p}{ "$t${_}_lang", "$t${_}_latin", "$t${_}_official" }], 1..4;

            # Remove duplicate languages that will never match
            my %l;
            @l = grep {
                my $prio = !defined $_->[2] ? 3 : $_->[2] ? 2 : 1;
                ($l{$_->[0]}||9) <= $prio ? 0 : ($l{$_->[0]} = $prio)
            } @l;

            # Expand 'Chinese' to the scripts if we have enough free slots.
            # (this is a hack and should ideally be handled in the title selection
            # algorithm, but that selection code has multiple implementations and
            # is already subject to potential performance issues, so I'd rather
            # keep it simple)
            @l = map $_->[0] eq 'zh' ? ($_, ['zh-Hant', $_->[1], $_->[2]], ['zh-Hans', $_->[1], $_->[2]]) : ($_), @l
                if @l <= 2 && !grep $_->[0] =~ /^zh-/, @l;

            @{$p}{ "$t${_}_lang", "$t${_}_latin", "$t${_}_official" } = $_ <= @l ? $l[$_-1]->@* : (undef, false, undef) for (1..4);
        }
        1;
    },
};


our $DEFAULT_TITLE_PREFS = { FU::Validate->compile({titleprefs => 1})->empty->%*, to_latin => true };

sub titleprefs_is_default($p) { $p->{to_latin} && !$p->{ao_latin} && !$p->{t1_lang} && !$p->{a1_lang} }

sub pref { !is_api() && auth->pref('titles') }


# Returns the preferred title array given an array of (vn|releases)_titles-like
# objects. Same functionality as the SQL view, except implemented in perl.
sub titleprefs_obj($olang, $titles) {
    my $p = pref;
    my %l = map +($_->{lang},$_), @$titles;

    my @title = (
        $olang, (!$p || $p->{to_latin}) && length $l{$olang}{latin} ? $l{$olang}{latin} : $l{$olang}{title},
        $olang, ( $p && $p->{ao_latin}) && length $l{$olang}{latin} ? $l{$olang}{latin} : $l{$olang}{title},
    );
    for my $t ($p ? ('t','a') : ()) {
        for (1..4) {
            my $o = $l{ $p->{"$t${_}_lang"}||'' } or next;
            next if !defined $p->{"$t${_}_official"} && $o->{lang} ne $olang;
            next if $p->{"$t${_}_official"} && exists $o->{official} && !$o->{official};
            next if !defined $o->{title};
            $title[$t eq 't' ? 0 : 2] = $o->{lang};
            $title[$t eq 't' ? 1 : 3] = $p->{"$t${_}_latin"} && length $o->{latin} ? $o->{latin} : $o->{title};
            last;
        }
    }
    \@title;
}


# Returns the preferred title array given a language, latin title and original title.
# For DB entries that only have (title, latin) fields.
sub titleprefs_swap($olang, $title, $latin) {
    my $p = pref;

    my @title = (
        $olang, (!$p || $p->{to_latin}) && length $latin ? $latin : $title,
        $olang, ( $p && $p->{ao_latin}) && length $latin ? $latin : $title,
    );
    for my $t ($p ? ('t','a') : ()) {
        for (1..4) {
            next if ($p->{"$t${_}_lang"}||'') ne $olang;
            $title[$t eq 't' ? 1 : 3] = $p->{"$t${_}_latin"} && length $latin ? $latin : $title;
            last;
        }
    }
    \@title;
}


sub gen_sql($has_official, $tbl_main, $tbl_titles, $join_col) {
    my $p = pref;
    return undef if !$p || titleprefs_is_default $p;

    my sub id($t,$i) {
        !$i ? 'xo' : sprintf 'x%s_%s',
            !defined $p->{"$t${i}_official"} ? 'r' : $has_official && $p->{"$t${i}_official"} ? 'o' : 'u',
            lc $p->{"$t${i}_lang"} =~ s/-//rg
    }

    my $sql = '(SELECT x.*, ';

    for my $t ('t', 'a') {
        $sql .= '||' if $t eq 'a';
        my $orig = 'ARRAY[xo.lang::text,' . ($p->{"${t}o_latin"} ? 'COALESCE(xo.latin, xo.title)' : 'xo.title') . ']';
        if (!$p->{"${t}1_lang"}) {
            $sql .= $orig;
            next;
        }
        $sql .= 'CASE';
        for (1..4) {
            last if !$p->{"$t${_}_lang"};
            my $id = id $t, $_;
            $sql .= " WHEN $id.title IS NOT NULL THEN ARRAY['".$p->{"$t${_}_lang"}."'," . ($p->{"$t${_}_latin"} ? "COALESCE($id.latin, $id.title)" : "$id.title") . ']';
        }
        $sql .= " ELSE $orig END";
    }
    $sql .= " title, COALESCE(";

    for (1..4) {
        last if !$p->{"t${_}_lang"};
        my $id = id 't', $_;
        $sql .= "$id.latin, $id.title, ";
    }

    $sql .= "xo.latin, xo.title) sorttitle FROM $tbl_main x JOIN $tbl_titles xo ON xo.$join_col = x.$join_col AND xo.lang = x.olang";

    my %joins;
    for my $t ('t', 'a') {
        for (1..4) {
            last if !$p->{"$t${_}_lang"};
            my $id = id $t, $_;
            next if $joins{$id}++;
            $sql .= " LEFT JOIN $tbl_titles $id ON $id.$join_col = x.$join_col AND $id.lang = '".$p->{"$t${_}_lang"}."'"
                .(!defined $p->{"$t${_}_official"} ? " AND $id.lang = x.olang" : $has_official && $p->{"$t${_}_official"} ? " AND $id.official" : '');
        }
    }

    $sql .= ')';
    $sql;
}


sub VNT :prototype()          { fu->{titleprefs_v} //= RAW(gen_sql(1, 'vn',       'vn_titles',       'id') || 'vnt')       }
sub RELEASEST :prototype()    { fu->{titleprefs_r} //= RAW(gen_sql(0, 'releases', 'releases_titles', 'id') || 'releasest') }
sub PRODUCERST :prototype()   { fu->{titleprefs_p} //= pref ? SQL 'producerst(',   pref, ')' : RAW 'producerst' }
sub CHARST :prototype()       { fu->{titleprefs_c} //= pref ? SQL 'charst(',       pref, ')' : RAW 'charst' }
sub STAFF_ALIAST :prototype() { fu->{titleprefs_s} //= pref ? SQL 'staff_aliast(', pref, ')' : RAW 'staff_aliast' }
sub ITEM_INFO                 { SQL 'item_info(', pref, ',', $_[0], ',', $_[1], ')' }

1;
