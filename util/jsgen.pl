#!/usr/bin/perl

use strict;
use warnings;
use Encode 'encode_utf8';
use Cwd 'abs_path';
use JSON::XS;

my $ROOT;
BEGIN { ($ROOT = abs_path $0) =~ s{/util/jsgen\.pl$}{}; }

use lib "$ROOT/lib";
use VNDB::Config;
use VNDB::Types;


sub vars {
  my %vars = (
    rlist_status  => [ map [ $_, $RLIST_STATUS{$_} ], keys %RLIST_STATUS ],
    cookie_prefix => config->{tuwf}{cookie_prefix},
    age_ratings   => [ map [ $_, $AGE_RATING{$_}{txt}], keys %AGE_RATING ],
    languages     => [ map [ $_, $LANGUAGE{$_} ], sort { $LANGUAGE{$a} cmp $LANGUAGE{$b} } keys %LANGUAGE ],
    platforms     => [ map [ $_, $PLATFORM{$_} ], keys %PLATFORM ],
    char_roles    => [ map [ $_, $CHAR_ROLE{$_}{txt} ], keys %CHAR_ROLE ],
    media         => [ map [ $_, $MEDIUM{$_}{txt}, $MEDIUM{$_}{qty} ], keys %MEDIUM ],
    release_types => [ map [ $_, $RELEASE_TYPE{$_} ], keys %RELEASE_TYPE ],
    animated      => [ map [ $_, $ANIMATED{$_}{txt} ], keys %ANIMATED ],
    voiced        => [ map [ $_, $VOICED{$_}{txt} ], keys %VOICED ],
    vn_lengths    => [ map [ $_, $VN_LENGTH{$_}{txt} ], keys %VN_LENGTH ],
    blood_types   => [ map [ $_, $BLOOD_TYPE{$_} ], keys %BLOOD_TYPE ],
    genders       => [ map [ $_, $GENDER{$_} ], keys %GENDER ],
    credit_type   => [ map [ $_, $CREDIT_TYPE{$_} ], keys %CREDIT_TYPE ],
    cup_size      => [ grep $_, keys %CUP_SIZE ],
  );
  JSON::XS->new->encode(\%vars);
}


# Reads main.js and any included files.
sub readjs {
  my $f = shift || 'main.js';
  open my $JS, '<:utf8', "$ROOT/data/js/$f" or die $!;
  local $/ = undef;
  local $_ = <$JS>;
  close $JS;
  s{^//include (.+)$}{'(function(){'.readjs($1).'})();'}meg;
  $_;
}


sub save {
  my($f, $body) = @_;
  open my $F, '>', "$f~" or die $!;
  print $F encode_utf8($body);
  close $F;
  rename "$f~", $f or die $!;
}


my $js = readjs;
$js =~ s{/\*VARS\*/}{vars()}eg;
save "$ROOT/static/g/vndb.js", $js;
