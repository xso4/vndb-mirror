
package VNDB::Handler::VNPage;

use strict;
use warnings;
use TUWF ':html';
use VNDB::Func;
use VNDB::Types;


TUWF::register(
  qr{old/v([1-9]\d*)/releases}          => \&releases,
);


# Description of each column, field:
#   id:            Identifier used in URLs
#   sort_field:    Name of the field when sorting
#   what:          Required dbReleaseGet 'what' flag
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
    column_string => 'Title',
    draw          => sub { a href => "/r$_[0]{id}", shorten $_[0]{title}, 60 },
  }, { # Type
    id            => 'typ',
    sort_field    => 'type',
    button_string => 'Type',
    default       => 1,
    draw          => sub { cssicon "rt$_[0]{type}", $_[0]{type}; txt '(patch)' if $_[0]{patch} },
  }, { # Languages
    id            => 'lan',
    button_string => 'Language',
    default       => 1,
    has_data      => sub { !!@{$_[0]{languages}} },
    draw          => sub {
      for(@{$_[0]{languages}}) {
        cssicon "lang $_", $LANGUAGE{$_};
        br if $_ ne $_[0]{languages}[$#{$_[0]{languages}}];
      }
    },
  }, { # Publication
    id            => 'pub',
    sort_field    => 'publication',
    column_string => 'Publication',
    column_width  => 70,
    button_string => 'Publication',
    default       => 1,
    what          => 'extended',
    draw          => sub { txt join ', ', $_[0]{freeware} ? 'Freeware' : 'Non-free', $_[0]{patch} ? () : ($_[0]{doujin} ? 'doujin' : 'commercial') },
  }, { # Platforms
    id             => 'pla',
    button_string => 'Platforms',
    default       => 1,
    what          => 'platforms',
    has_data      => sub { !!@{$_[0]{platforms}} },
    draw          => sub {
      for(@{$_[0]{platforms}}) {
        cssicon $_, $PLATFORM{$_};
        br if $_ ne $_[0]{platforms}[$#{$_[0]{platforms}}];
      }
      txt 'Unknown' if !@{$_[0]{platforms}};
    },
  }, { # Media
    id            => 'med',
    column_string => 'Media',
    button_string => 'Media',
    what          => 'media',
    has_data      => sub { !!@{$_[0]{media}} },
    draw          => sub {
      for(@{$_[0]{media}}) {
        txt fmtmedia($_->{medium}, $_->{qty});
        br if $_ ne $_[0]{media}[$#{$_[0]{media}}];
      }
      txt 'Unknown' if !@{$_[0]{media}};
    },
  }, { # Resolution
    id            => 'res',
    sort_field    => 'resolution',
    column_string => 'Resolution',
    button_string => 'Resolution',
    na_for_patch  => 1,
    default       => 1,
    what          => 'extended',
    has_data      => sub { !!$_[0]{reso_y} },
    draw          => sub { txt resolution($_[0]) || 'Unknown' },
  }, { # Voiced
    id            => 'voi',
    sort_field    => 'voiced',
    column_string => 'Voiced',
    column_width  => 70,
    button_string => 'Voiced',
    na_for_patch  => 1,
    default       => 1,
    what          => 'extended',
    has_data      => sub { !!$_[0]{voiced} },
    draw          => sub { txt $VOICED{$_[0]{voiced}}{txt} },
  }, { # Animation
    id            => 'ani',
    sort_field    => 'ani_ero',
    column_string => 'Animation',
    column_width  => 110,
    button_string => 'Animation',
    na_for_patch  => '1',
    what          => 'extended',
    has_data      => sub { !!($_[0]{ani_story} || $_[0]{ani_ero}) },
    draw          => sub {
      txt join ', ',
        $_[0]{ani_story} ? "Story: $ANIMATED{$_[0]{ani_story}}{txt}"   :(),
        $_[0]{ani_ero}   ? "Ero scenes: $ANIMATED{$_[0]{ani_ero}}{txt}":();
      txt 'Unknown' if !$_[0]{ani_story} && !$_[0]{ani_ero};
    },
  }, { # Released
    id            => 'rel',
    sort_field    => 'released',
    column_string => 'Released',
    button_string => 'Released',
    default       => 1,
    draw          => sub { lit fmtdatestr $_[0]{released} },
  }, { # Age rating
    id            => 'min',
    sort_field    => 'minage',
    button_string => 'Age rating',
    default       => 1,
    has_data      => sub { $_[0]{minage} != -1 },
    draw          => sub { txt minage $_[0]{minage} },
  }, { # Notes
    id            => 'not',
    sort_field    => 'notes',
    column_string => 'Notes',
    column_width  => 400,
    button_string => 'Notes',
    default       => 1,
    what          => 'extended',
    has_data      => sub { !!$_[0]{notes} },
    draw          => sub { lit bb_format $_[0]{notes} },
  }
);


sub releases {
  my($self, $vid) = @_;

  my $v = $self->dbVNGet(id => $vid)->[0];
  return $self->resNotFound if !$v->{id};

  my $title = "Releases for $v->{title}";
  $self->htmlHeader(title => $title);
  $self->htmlMainTabs('v', $v, 'releases');

  my $f = $self->formValidate(
    map({ get => $_->{id}, required => 0, default => $_->{default}||0, enum => [0,1] }, grep $_->{button_string}, @rel_cols),
    { get => 'cw',   required => 0, default => 0, enum => [0,1] },
    { get => 'o',    required => 0, default => 0, enum => [0,1] },
    { get => 's',    required => 0, default => 'released', enum => [ map $_->{sort_field}, grep $_->{sort_field}, @rel_cols ]},
    { get => 'os',   required => 0, default => 'all',      enum => [ 'all', keys %PLATFORM ] },
    { get => 'lang', required => 0, default => 'all',      enum => [ 'all', keys %LANGUAGE ] },
  );
  return $self->resNotFound if $f->{_err};

  # Get the release info
  my %what = map +($_->{what}, 1), grep $_->{what} && $f->{$_->{id}}, @rel_cols;
  my $r = $self->dbReleaseGet(vid => $vid, what => join(' ', keys %what), sort => $f->{s}, reverse => $f->{o}, results => 200);

  # url generator
  my $url = sub {
    my %u = (%$f, @_);
    return "/v$vid/releases?".join(';', map "$_=$u{$_}", sort keys %u);
  };

  div class => 'mainbox releases_compare';
   h1 $title;

   if(!@$r) {
     td 'We don\'t have any information about releases of this visual novel yet...';
   } else {
     _releases_buttons($self, $f, $url, $r);
   }
  end 'div';

  _releases_table($self, $f, $url, $r) if @$r;
  $self->htmlFooter;
}


sub _releases_buttons {
  my($self, $f, $url, $r) = @_;

  # Column visibility
  p class => 'browseopts';
   a href => $url->($_->{id}, $f->{$_->{id}} ? 0 : 1), $f->{$_->{id}} ? (class => 'optselected') : (), $_->{button_string}
     for (grep $_->{button_string}, @rel_cols);
  end;

  # Misc options
  my $all_selected   = !grep $_->{button_string} && !$f->{$_->{id}}, @rel_cols;
  my $all_unselected = !grep $_->{button_string} &&  $f->{$_->{id}}, @rel_cols;
  my $all_url = sub { $url->(map +($_->{id},$_[0]), grep $_->{button_string}, @rel_cols); };
  p class => 'browseopts';
   a href => $all_url->(1),                  $all_selected   ? (class => 'optselected') : (), 'All on';
   a href => $all_url->(0),                  $all_unselected ? (class => 'optselected') : (), 'All off';
   a href => $url->('cw', $f->{cw} ? 0 : 1), $f->{cw}        ? (class => 'optselected') : (), 'Restrict column width';
  end;

  # Platform/language filters
  my $plat_lang_draw = sub {
    my($row, $option, $txt, $csscat) = @_;
    my %opts = map +($_,1), map @{$_->{$row}}, @$r;
    return if !keys %opts;
    p class => 'browseopts';
     for('all', sort keys %opts) {
       a href => $url->($option, $_), $_ eq $f->{$option} ? (class => 'optselected') : ();
        $_ eq 'all' ? txt 'All' : cssicon "$csscat $_", $txt->{$_};
       end 'a';
     }
    end 'p';
  };
  $plat_lang_draw->('platforms', 'os',  \%PLATFORM, '')     if $f->{pla};
  $plat_lang_draw->('languages', 'lang',\%LANGUAGE, 'lang') if $f->{lan};
}


sub _releases_table {
  my($self, $f, $url, $r) = @_;

  # Apply language and platform filters
  my @r = grep +
    ($f->{os}   eq 'all' || ($_->{platforms} && grep $_ eq $f->{os}, @{$_->{platforms}})) &&
    ($f->{lang} eq 'all' || ($_->{languages} && grep $_ eq $f->{lang}, @{$_->{languages}})), @$r;

  # Figure out which columns to display
  my @col;
  for my $c (@rel_cols) {
    next if $c->{button_string} && !$f->{$c->{id}}; # Hidden by settings
    push @col, $c if !@r || !$c->{has_data} || grep $c->{has_data}->($_), @r; # Must have relevant data
  }

  div class => 'mainbox releases_compare';
   table;

    thead;
     Tr;
      for my $c (@col) {
        td class => 'key';
         txt $c->{column_string} if $c->{column_string};
         for($c->{sort_field} ? (0,1) : ()) {
           my $active = $f->{s} eq $c->{sort_field} && !$f->{o} == !$_;
           a href => $url->(o => $_, s => $c->{sort_field}) if !$active;
            lit $_ ? "\x{25BE}" : "\x{25B4}";
           end 'a' if !$active;
         }
        end 'td';
      }
     end 'tr';
    end 'thead';

    for my $r (@r) {
      Tr;
       # Combine "N/A for patches" columns
       my $cspan = 1;
       for my $c (0..$#col) {
         if($r->{patch} && $col[$c]{na_for_patch} && $c < $#col && $col[$c+1]{na_for_patch}) {
           $cspan++;
           next;
         }
         td $cspan > 1 ? (colspan => $cspan) : (),
            $col[$c]{column_width} && $f->{cw} ? (style => "max-width: $col[$c]{column_width}px") : ();
          if($r->{patch} && $col[$c]{na_for_patch}) {
            txt 'NA for patches';
          } else {
            $col[$c]{draw}->($r);
          }
         end;
         $cspan = 1;
       }
      end;
    }
   end 'table';
  end 'div';
}



1;

