#!/usr/bin/perl

use v5.12;
use warnings;
use Cwd 'abs_path';

our($ROOT, %S);
BEGIN { ($ROOT = abs_path $0) =~ s{/util/skingen\.pl$}{}; }

use lib "$ROOT/lib";
use VNDB::Skins;


my $iconcss = do {
  open my $F, '<', "$ROOT/data/icons/icons.css" or die $!;
  local $/=undef;
  <$F>;
};


sub imgsize {
  open my $IMG, '<', $_[0] or die $!;
  sysread $IMG, my $buf, 1024 or die $!;
  $buf =~ /\xFF\xC0...(....)/s ? unpack('nn', $1) : $buf =~ /IHDR(.{8})/s ? unpack('NN', $1) : die;
}


sub rdcolor {
  length $_[0] == 4 ? map hex($_)/15,  $_[0] =~ /#(.)(.)(.)/ : #RGB
  length $_[0] == 7 ? map hex($_)/255, $_[0] =~ /#(..)(..)(..)/ : #RRGGBB
  length $_[0] == 9 ? map hex($_)/255, $_[0] =~ /#(..)(..)(..)(..)/ : #RRGGBBAA
  die;
}


sub blend {
  my($f, $b) = @_;
  my @f = rdcolor $f;
  my @b = rdcolor $b;
  $f[3] //= 1;
  sprintf '#%02x%02x%02x',
    ($f[0] * $f[3] + $b[0] * (1 - $f[3]))*255,
    ($f[1] * $f[3] + $b[1] * (1 - $f[3]))*255,
    ($f[2] * $f[3] + $b[2] * (1 - $f[3]))*255;
}

sub mtime($) { [stat("$ROOT/static$_[0]")]->[9] }


sub writeskin { # $name
  my $name = shift;
  my %o = skins->{$name}->%*;
  $o{iconcss} = $iconcss;

  # get the right top image
  if($o{imgrighttop}) {
    my $path = "/s/$name/$o{imgrighttop}";
    my($h, $w) = imgsize "$ROOT/static$path";
    $o{_bgright} = sprintf 'background: url(%s?%s) no-repeat; width: %dpx; height: %dpx', $path, mtime $path, $w, $h;
  } else {
    $o{_bgright} = 'display: none';
  }

  # body background
  if($o{imglefttop}) {
    my $path = "/s/$name/$o{imglefttop}";
    $o{_bodybg} = sprintf 'background: %s url(%s?%s) no-repeat', $o{bodybg}, $path, mtime $path;
  } else {
    $o{_bodybg} = sprintf 'background-color: %s', $o{bodybg};
  }

  # boxbg blended with bodybg
  $o{_blendbg} = blend $o{boxbg}, $o{bodybg};

  # version
  $o{icons_version} = mtime '/f/icons.png';

  # write the CSS
  open my $CSS, '<', "$ROOT/data/style.css" or die $!;
  local $/=undef;
  my $css = <$CSS>;
  close $CSS;

  my $f = "$ROOT/static/s/$name/style.css";
  open my $SKIN, '>', "$f~" or die $!;
  print $SKIN $css =~ s{\$([a-z_]+)\$}{$o{$1} // die "Unknown variable $1"}egr;
  close $SKIN;

  rename "$f~", $f;
}


if(@ARGV) {
  writeskin($_) for (@ARGV);
} else {
  writeskin($_) for (keys skins->%*);
}


