
package VNDB::Handler::Releases;

use strict;
use warnings;
use TUWF ':html', ':xml', 'uri_escape';
use VNDB::Func;
use VNDB::Types;


TUWF::register(
  qr{old/r}                            => \&browse,
  qr{r/engines}                    => \&engines,
  qr{xml/engines.xml}              => \&enginexml,
);


sub browse {
  my $self = shift;

  my $f = $self->formValidate(
    { get => 'p',  required => 0, default => 1, template => 'page' },
    { get => 'o',  required => 0, default => 'a', enum => ['a', 'd'] },
    { get => 'q',  required => 0, default => '', maxlength => 500 },
    { get => 's',  required => 0, default => 'title', enum => [qw|released minage title|] },
    { get => 'fil',required => 0 },
  );
  return $self->resNotFound if $f->{_err};
  $f->{fil} //= $self->authPref('filter_release');

  my %compat = _fil_compat($self);
  my($list, $np) = !$f->{q} && !$f->{fil} && !keys %compat ? ([], 0) : $self->filFetchDB(release => $f->{fil}, \%compat, {
    sort => $f->{s}, reverse => $f->{o} eq 'd',
    page => $f->{p},
    results => 50,
    what => 'platforms',
    $f->{q} ? ( search => $f->{q} ) : (),
  });

  $self->htmlHeader(title => 'Browse releases');

  form method => 'get', action => '/old/r', 'accept-charset' => 'UTF-8';
  div class => 'mainbox';
   h1 'Browse releases';
   $self->htmlSearchBox('r', $f->{q});
   p class => 'filselect';
    a id => 'filselect', href => '#r';
     lit '<i>&#9656;</i> Filters<i></i>';
    end;
   end;
   input type => 'hidden', class => 'hidden', name => 'fil', id => 'fil', value => $f->{fil};
  end;
  end 'form';

  my $uri = sprintf '/old/r?q=%s;fil=%s', uri_escape($f->{q}), $f->{fil};
  $self->htmlBrowse(
    class    => 'relbrowse',
    items    => $list,
    options  => $f,
    nextpage => $np,
    pageurl  => "$uri;s=$f->{s};o=$f->{o}",
    sorturl  => $uri,
    header   => [
      [ 'Released', 'released' ],
      [ 'Rating',   'minage' ],
      [ '',         '' ],
      [ 'Title',    'title' ],
    ],
    row      => sub {
      my($s, $n, $l) = @_;
      Tr;
       td class => 'tc1';
        lit fmtdatestr $l->{released};
       end;
       td class => 'tc2', $l->{minage} < 0 ? '' : minage $l->{minage};
       td class => 'tc3';
        $_ ne 'oth' && cssicon $_, $PLATFORM{$_} for (@{$l->{platforms}});
        cssicon "lang $_", $LANGUAGE{$_} for (@{$l->{languages}});
        cssicon "rt$l->{type}", $l->{type};
       end;
       td class => 'tc4';
        a href => "/r$l->{id}", title => $l->{original}||$l->{title}, shorten $l->{title}, 90;
        b class => 'grayedout', ' (patch)' if $l->{patch};
       end;
      end 'tr';
    },
  ) if @$list;
  if(($f->{q} || $f->{fil}) && !@$list) {
    div class => 'mainbox';
     h1 'No results found';
     div class => 'notice';
      p;
       txt 'Sorry, couldn\'t find anything that comes through your filters. You might want to disable a few filters to get more results.';
       br; br;
       txt 'Also, keep in mind that we don\'t have all information about all releases.'
          .' So e.g. filtering on screen resolution will exclude all releases of which we don\'t know it\'s resolution,'
          .' even though it might in fact be in the resolution you\'re looking for.';
      end
     end;
    end;
  }
  $self->htmlFooter(pref_code => 1);
}


# provide compatibility with old URLs
sub _fil_compat {
  my $self = shift;
  my %c;
  my $f = $self->formValidate(
    { get => 'ln', required => 0, multi => 1, default => '', enum => [ keys %LANGUAGE ] },
    { get => 'pl', required => 0, multi => 1, default => '', enum => [ keys %PLATFORM ] },
    { get => 'me', required => 0, multi => 1, default => '', enum => [ keys %MEDIUM ] },
    { get => 'tp', required => 0, default => '', enum => [ '', keys %RELEASE_TYPE ] },
    { get => 'pa', required => 0, default => 0, enum => [ 0..2 ] },
    { get => 'fw', required => 0, default => 0, enum => [ 0..2 ] },
    { get => 'do', required => 0, default => 0, enum => [ 0..2 ] },
    { get => 'ma_m', required => 0, default => 0, enum => [ 0, 1 ] },
    { get => 'ma_a', required => 0, default => 0, enum => [ keys %AGE_RATING ] },
    { get => 'mi', required => 0, default => 0, template => 'uint' },
    { get => 'ma', required => 0, default => 99999999, template => 'uint' },
  );
  return () if $f->{_err};
  $c{minage} = [ grep $_ >= 0 && ($f->{ma_m} ? $f->{ma_a} >= $_ : $f->{ma_a} <= $_), keys %AGE_RATING ] if $f->{ma_a} || $f->{ma_m};
  $c{date_after} = $f->{mi}  if $f->{mi};
  $c{date_before} = $f->{ma} if $f->{ma} < 99990000;
  $c{plat} = $f->{pl}        if $f->{pl}[0];
  $c{lang} = $f->{ln}        if $f->{ln}[0];
  $c{med} = $f->{me}         if $f->{me}[0];
  $c{type} = $f->{tp}        if $f->{tp};
  $c{patch} = $f->{pa} == 2 ? 0 : 1 if $f->{pa};
  $c{freeware} = $f->{fw} == 2 ? 0 : 1 if $f->{fw};
  $c{doujin} = $f->{do} == 2 ? 0 : 1 if $f->{do};
  return %c;
}


sub engines {
  my $self = shift;
  my $lst = $self->dbReleaseEngines();
  $self->htmlHeader(title => 'Engine list', noindex => 1);

  div class => 'mainbox';
   h1 'Engine list';
   p;
    lit q{
     This is a list of all engines currently associated with releases. This
     list can be used as reference when filling out the engine field for a
     release and to find inconsistencies in the engine names. See the <a
     href="/d3#3">releases guidelines</a> for more information.
    };
   end;
   ul;
    for my $e (@$lst) {
      li;
       # TODO: link to new advsearch listing
       a href => '/old/r?fil='.fil_serialize({engine => $e->{engine}}), $e->{engine};
       b class => 'grayedout', " $e->{cnt}";
      end;
    }
   end;

  end;
}


sub enginexml {
  my $self = shift;

  # The list of engines happens to be small enough for this to make sense, and
  # fetching all unique engines from the releases table also happens to be fast
  # enough right now, but this may need a separate cache or index in the future.
  my $lst = $self->dbReleaseEngines();

  my $f = $self->formValidate(
    { get => 'q', required => 1, maxlength => 500 },
  );
  return $self->resNotFound if $f->{_err};

  $self->resHeader('Content-type' => 'text/xml; charset=UTF-8');
  xml;
  tag 'engines';
   for(grep $lst->[$_]{engine} =~ /\Q$f->{q}\E/i, 0..$#$lst) {
     tag 'item', count => $lst->[$_]{cnt}, id => $_+1, $lst->[$_]{engine};
   }
  end;
}

1;

