
package VNDB::Handler::VNBrowse;

use strict;
use warnings;
use TUWF ':html', 'uri_escape';
use VNDB::Func;
use VNDB::Types;


TUWF::register(
  qr{old/v/([a-z0]|all)}  => \&list,
);


sub list {
  my($self, $char) = @_;

  my $f = $self->formValidate(
    { get => 's', required => 0, default => 'tagscore', enum => [ qw|title rel pop tagscore rating| ] },
    { get => 'o', required => 0, enum => [ 'a','d' ] },
    { get => 'p', required => 0, default => 1, template => 'page' },
    { get => 'q', required => 0, default => '' },
    { get => 'sq', required => 0, default => '' },
    { get => 'fil',required => 0 },
    { get => 'rfil', required => 0, default => '' },
    { get => 'cfil', required => 0, default => '' },
    { get => 'vnlist', required => 0, default => 2, enum => [ '0', '1' ] }, # 2: use pref
  );
  return $self->resNotFound if $f->{_err};
  $f->{q} ||= $f->{sq};
  $f->{fil} //= $self->authPref('filter_vn');
  my %compat = _fil_compat($self);
  my $uid = $self->authInfo->{id};

  my $read_write_pref = sub {
    my($type, $pref_name) = @_;

    return 0 if !$uid; # no data to display anyway
    return $self->authPref($pref_name)?1:0 if $f->{$type} == 2;

    $self->authPref($pref_name => $f->{$type}?1:0) if ($self->authPref($pref_name)?1:0) != $f->{$type};
    return $f->{$type};
  };

  $f->{vnlist} = $read_write_pref->('vnlist', 'vn_list_own');

  return $self->resRedirect('/'.$1.$2.(!$3 ? '' : $1 eq 'd' ? '#'.$3 : '.'.$3), 'temp')
    if $f->{q} && $f->{q} =~ /^([gvrptudcis])([0-9]+)(?:\.([0-9]+))?$/;

  $f->{s} = 'title' if $f->{fil} !~ /tag_inc-/ && $f->{s} eq 'tagscore';
  $f->{o} = $f->{s} eq 'tagscore' ? 'd' : 'a' if !$f->{o};

  my $rfil = fil_parse $f->{rfil}, @{$VNDB::Util::Misc::filfields{release}};
  $self->filCompat(release => $rfil);
  $f->{rfil} = fil_serialize $rfil, @{$VNDB::Util::Misc::filfields{release}};

  my $cfil = fil_parse $f->{cfil}, @{$VNDB::Util::Misc::filfields{char}};
  $cfil->{tagspoil} //= $self->authPref('spoilers')||0 if keys %$cfil;

  my($list, $np) = $self->filFetchDB(vn => $f->{fil}, {
    %compat,
    tagspoil => $self->authPref('spoilers')||0,
  }, {
    what => ' rating'.($f->{vnlist} ? ' vnlist' : ''),
    $char ne 'all' ? ( char    => $char   ) : (),
    $f->{q}        ? ( search  => $f->{q} ) : (),
    keys %$rfil    ? ( release => $rfil   ) : (),
    keys %$cfil    ? ( character => $cfil ) : (),
    results => 50,
    page => $f->{p},
    sort => $f->{s}, reverse => $f->{o} eq 'd',
  });

  $self->resRedirect('/v'.$list->[0]{id}, 'temp')
    if $f->{q} && @$list == 1 && $f->{p} == 1;

  $self->htmlHeader(title => 'Browse visual novels', search => $f->{q});

  my $quri = uri_escape($f->{q});
  form action => '/old/v/all', 'accept-charset' => 'UTF-8', method => 'get';

  # url generator
  my $url = sub {
    my($char, $toggle) = @_;

    return "/old/v/$char?q=$quri;fil=$f->{fil};rfil=$f->{rfil};cfil=$f->{cfil};s=$f->{s};o=$f->{o}" .
           ($toggle ? ";$toggle=".($f->{$toggle}?0:1) : '');
  };

  div class => 'mainbox';
   h1 'Browse visual novels';
   $self->htmlSearchBox('v', $f->{q});
   p class => 'browseopts';
    for ('all', 'a'..'z', 0) {
      a href => $url->($_), $_ eq $char ? (class => 'optselected') : (), $_ eq 'all' ? 'ALL' : $_ ? uc $_ : '#';
    }
   end;
   if($uid) {
     p class => 'browseopts';
      a href => $url->($char, 'vnlist'), $f->{vnlist} ? (class => 'optselected') : (), 'User VN list';
     end 'p';
   }

   p class => 'filselect';
    a id => 'filselect', href => '#v';
     lit '<i>&#9656;</i> Visual Novel Filters<i></i>';
    end;
    a id => 'rfilselect', href => '#r';
     lit '<i>&#9656;</i> Release filters<i></i>';
    end;
    a id => 'cfilselect', href => '#c';
     lit '<i>&#9656;</i> Character filters<i></i>';
    end;
   end;
   input type => 'hidden', class => 'hidden', name => $_, id => $_, value => $f->{$_}
     for (qw{fil rfil cfil s o});
  end;
  end 'form';

  $self->htmlBrowseVN($list, $f, $np, "/old/v/$char?q=$quri;fil=$f->{fil};rfil=$f->{rfil};cfil=$f->{cfil}", $f->{fil} =~ /tag_inc-/);
  $self->htmlFooter(pref_code => 1);
}


sub _fil_compat {
  my $self = shift;
  my %c;
  my $f = $self->formValidate(
    { get => 'ln', required => 0, multi => 1, enum => [ keys %LANGUAGE ], default => '' },
    { get => 'pl', required => 0, multi => 1, enum => [ keys %PLATFORM ], default => '' },
    { get => 'sp', required => 0, default => ($self->reqCookie('tagspoil')||'') =~ /^([0-2])$/ ? $1 : 0, enum => [0..2] },
  );
  return () if $f->{_err};
  $c{lang}     //= $f->{ln} if $f->{ln}[0];
  $c{plat}     //= $f->{pl} if $f->{pl}[0];
  $c{tagspoil} //= $f->{sp};
  return %c;
}


1;

