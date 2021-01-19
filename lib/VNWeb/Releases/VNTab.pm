# TODO: This code is kind of obsolete. It's not been updated with recently
# added release fields and all fields are already displayed more concisely in
# the releases box on the main VN page. The filtering and display options on
# this page can still be useful, though, so need to figure out what to do with
# this in the future.
# Maybe update/modernize this page with the latest fields and icons and
# shorten/simplify the long list of releases on the main VN page? Or expand the
# list on VN pages with filters and display options?

package VNWeb::Releases::VNTab;

use VNWeb::Prelude;
use VNWeb::Releases::Lib 'enrich_release';


# Description of each column, field:
#   id:            Identifier used in URLs
#   sort_field:    Name of the field when sorting
#   sort_sql:      ORDER BY clause when sorting
#   column_string: String to use as column header
#   column_width:  Maximum width (in pixels) of the column in 'restricted width' mode
#   button_string: String to use for the hide/unhide button
#   na_for_patch:  When the field is N/A for patch releases
#   default:       Set when it's visible by default
#   has_data:      Subroutine called with a release object, should return true if the release has data for the column
#   draw:          Subroutine called with a release object, should draw its column contents
my @rel_cols = (
  {    # Title
    id            => 'tit',
    sort_field    => 'title',
    sort_sql      => 'r.title %s, r.released %1$s',
    column_string => 'Title',
    draw          => sub { a_ href => "/r$_[0]{id}", $_[0]{title} },
  }, { # Type
    id            => 'typ',
    sort_field    => 'type',
    sort_sql      => 'r.patch %s, r.type %1$s, r.released %1$s, r.title %1$s',
    button_string => 'Type',
    default       => 1,
    draw          => sub { abbr_ class => "icons rt$_[0]{type}", title => $_[0]{type}, ''; txt_ '(patch)' if $_[0]{patch} },
  }, { # Languages
    id            => 'lan',
    button_string => 'Language',
    default       => 1,
    has_data      => sub { !!@{$_[0]{lang}} },
    draw          => sub { join_ \&br_, sub { abbr_ class => "icons lang $_", title => $LANGUAGE{$_}, ''; }, $_[0]{lang}->@* },
  }, { # Publication
    id            => 'pub',
    sort_field    => 'publication',
    sort_sql      => 'r.doujin %s, r.freeware %1$s,   r.patch %1$s, r.released %1$s, r.title %1$s',
    column_string => 'Publication',
    column_width  => 70,
    button_string => 'Publication',
    default       => 1,
    draw          => sub { txt_ join ', ', $_[0]{freeware} ? 'Freeware' : 'Non-free', $_[0]{patch} ? () : ($_[0]{doujin} ? 'doujin' : 'commercial') },
  }, { # Platforms
    id             => 'pla',
    button_string => 'Platforms',
    default       => 1,
    has_data      => sub { !!@{$_[0]{platforms}} },
    draw          => sub {
        join_ \&br_, sub { abbr_ class => "icons $_", title => $PLATFORM{$_}, ''; }, $_[0]{platforms}->@*;
        txt_ 'Unknown' if !$_[0]{platforms}->@*;
    },
  }, { # Media
    id            => 'med',
    column_string => 'Media',
    button_string => 'Media',
    has_data      => sub { !!@{$_[0]{media}} },
    draw          => sub {
        join_ \&br_, sub { txt_ fmtmedia $_->{medium}, $_->{qty} }, $_[0]{media}->@*;
        txt_ 'Unknown' if !$_[0]{media}->@*;
    },
  }, { # Resolution
    id            => 'res',
    sort_field    => 'resolution',
    sort_sql      => 'r.reso_x %s, r.reso_y %1$s,     r.patch %1$s, r.released %1$s, r.title %1$s',
    column_string => 'Resolution',
    button_string => 'Resolution',
    na_for_patch  => 1,
    default       => 1,
    has_data      => sub { !!$_[0]{reso_y} },
    draw          => sub { txt_ resolution($_[0]) || 'Unknown' },
  }, { # Voiced
    id            => 'voi',
    sort_field    => 'voiced',
    sort_sql      => 'r.voiced %s,                    r.patch %1$s, r.released %1$s, r.title %1$s',
    column_string => 'Voiced',
    column_width  => 70,
    button_string => 'Voiced',
    na_for_patch  => 1,
    default       => 1,
    has_data      => sub { !!$_[0]{voiced} },
    draw          => sub { txt_ $VOICED{$_[0]{voiced}}{txt} },
  }, { # Animation
    id            => 'ani',
    sort_field    => 'ani_ero',
    sort_sql      => 'r.ani_story %s, r.ani_ero %1$s, r.patch %1$s, r.released %1$s, r.title %1$s',
    column_string => 'Animation',
    column_width  => 110,
    button_string => 'Animation',
    na_for_patch  => '1',
    has_data      => sub { !!($_[0]{ani_story} || $_[0]{ani_ero}) },
    draw          => sub {
      txt_ join ', ',
        $_[0]{ani_story} ? "Story: $ANIMATED{$_[0]{ani_story}}{txt}"   :(),
        $_[0]{ani_ero}   ? "Ero scenes: $ANIMATED{$_[0]{ani_ero}}{txt}":();
      txt_ 'Unknown' if !$_[0]{ani_story} && !$_[0]{ani_ero};
    },
  }, { # Released
    id            => 'rel',
    sort_field    => 'released',
    sort_sql      => 'r.released %s, r.id %1$s',
    column_string => 'Released',
    button_string => 'Released',
    default       => 1,
    draw          => sub { rdate_ $_[0]{released} },
  }, { # Age rating
    id            => 'min',
    sort_field    => 'minage',
    sort_sql      => 'r.minage %s,                                  r.released %1$s, r.title %1$s',
    button_string => 'Age rating',
    default       => 1,
    has_data      => sub { $_[0]{minage} != -1 },
    draw          => sub { txt_ minage $_[0]{minage} },
  }, { # Notes
    id            => 'not',
    sort_field    => 'notes',
    sort_sql      => 'r.notes %s,                                   r.released %1$s, r.title %1$s',
    column_string => 'Notes',
    column_width  => 400,
    button_string => 'Notes',
    default       => 1,
    has_data      => sub { !!$_[0]{notes} },
    draw          => sub { lit_ bb_format $_[0]{notes} },
  }
);



sub buttons_ {
    my($opt, $url, $r) = @_;

    # Column visibility
    p_ class => 'browseopts', sub {
        a_ href => $url->($_->{id}, $opt->{$_->{id}} ? 0 : 1), $opt->{$_->{id}} ? (class => 'optselected') : (), $_->{button_string}
        for grep $_->{button_string}, @rel_cols;
    };

    # Misc options
    my $all_selected   = !grep $_->{button_string} && !$opt->{$_->{id}}, @rel_cols;
    my $all_unselected = !grep $_->{button_string} &&  $opt->{$_->{id}}, @rel_cols;
    my $all_url = sub { $url->(map +($_->{id},$_[0]), grep $_->{button_string}, @rel_cols); };
    p_ class => 'browseopts', sub {
        a_ href => $all_url->(1),                    $all_selected   ? (class => 'optselected') : (), 'All on';
        a_ href => $all_url->(0),                    $all_unselected ? (class => 'optselected') : (), 'All off';
        a_ href => $url->('cw', $opt->{cw} ? 0 : 1), $opt->{cw}      ? (class => 'optselected') : (), 'Restrict column width';
    };

    my sub pl {
        my($row, $option, $txt, $csscat) = @_;
        my %opts = map +($_,1), map $_->{$row}->@*, @$r;
        return if !keys %opts;
        p_ class => 'browseopts', sub {
            a_ href => $url->($option, $_), $_ eq $opt->{$option} ? (class => 'optselected') : (), sub {
                $_ eq 'all' ? txt_ 'All' : abbr_ class => "icons $csscat $_", title => $txt->{$_}, '';
            } for ('all', sort keys %opts);
        }
    };
    pl 'platforms', 'os', \%PLATFORM, ''     if $opt->{pla};
    pl 'lang',     'lang',\%LANGUAGE, 'lang' if $opt->{lan};
}


sub listing_ {
    my($opt, $url, $r) = @_;

    # Apply language and platform filters
    my @r = grep +
        ($opt->{os}   eq 'all' || ($_->{platforms} && grep $_ eq $opt->{os},   $_->{platforms}->@*)) &&
        ($opt->{lang} eq 'all' || ($_->{lang}      && grep $_ eq $opt->{lang}, $_->{lang}->@*)), @$r;

    # Figure out which columns to display
    my @col;
    for my $c (@rel_cols) {
        next if $c->{button_string} && !$opt->{$c->{id}}; # Hidden by settings
        push @col, $c if !@r || !$c->{has_data} || grep $c->{has_data}->($_), @r; # Must have relevant data
    }

    div_ class => 'mainbox releases_compare', sub {
        table_ sub {
            thead_ sub { tr_ sub {
                td_ class => 'key', sub {
                    txt_ $_->{column_string} if $_->{column_string};
                    sortable_ $_->{sort_field}, $opt, $url if $_->{sort_field};
                } for @col;
            } };
            tr_ sub {
                my $r = $_;
                # Combine "N/A for patches" columns
                my $cspan = 1;
                for my $c (0..$#col) {
                    if($r->{patch} && $col[$c]{na_for_patch} && $c < $#col && $col[$c+1]{na_for_patch}) {
                        $cspan++;
                        next;
                    }
                    td_ $cspan > 1 ? (colspan => $cspan) : (),
                    $col[$c]{column_width} && $opt->{cw} ? (style => "max-width: $col[$c]{column_width}px") : ();
                    if($r->{patch} && $col[$c]{na_for_patch}) {
                        txt_ 'NA for patches';
                    } else {
                        $col[$c]{draw}->($r);
                    }
                    end_;
                    $cspan = 1;
                }
            } for @r;
        }
    }
}


TUWF::get qr{/$RE{vid}/releases} => sub {
    my $v = dbobj v => tuwf->capture('id');
    return tuwf->resNotFound if !$v->{id};

    my $opt = tuwf->validate(get =>
        cw   => { anybool => 1 },
        o    => { onerror => 'a', enum => [0,1,'d','a'] },
        s    => { onerror => 'released', enum => [ map $_->{sort_field}, grep $_->{sort_field}, @rel_cols ]},
        os   => { onerror => 'all',      enum => [ 'all', keys %PLATFORM ] },
        lang => { onerror => 'all',      enum => [ 'all', keys %LANGUAGE ] },
        map +($_->{id}, { anybool => 1, default => $_->{default} }), grep $_->{button_string}, @rel_cols
    )->data;
    # Compat with old URLs
    $opt->{o} = 'a' if $opt->{o} eq 0;
    $opt->{o} = 'd' if $opt->{o} eq 1;

    my $r = tuwf->dbAlli('
        SELECT r.id, r.type, r.patch, r.released, r.gtin
          FROM releases r
          JOIN releases_vn rv ON rv.id = r.id
         WHERE NOT hidden AND rv.vid =', \$v->{id}, '
         ORDER BY', sprintf(+(grep $opt->{s} eq ($_->{sort_field}//''), @rel_cols)[0]{sort_sql}, $opt->{o} eq 'a' ? 'ASC' : 'DESC')
    );
    enrich_release $r;

    my sub url { '?'.query_encode %$opt, @_ }

    framework_ title => "Releases for $v->{title}", type => 'v', dbobj => $v, tab => 'releases', sub {
        div_ class => 'mainbox releases_compare', sub {
            h1_ "Releases for $v->{title}";
            if(!@$r) {
                p_ 'We don\'t have any information about releases of this visual novel yet...';
            } else {
                buttons_($opt, \&url, $r);
            }
        };
        listing_ $opt, \&url, $r if @$r;
    };
};


1;
