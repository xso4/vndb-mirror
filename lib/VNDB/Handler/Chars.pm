
package VNDB::Handler::Chars;

use strict;
use warnings;
use TUWF ':html', 'uri_escape';
use Exporter 'import';
use VNDB::Func;
use VNDB::Types;

our @EXPORT = ('charBrowseTable');

TUWF::register(
  qr{old/c/([a-z0]|all)} => \&list,
);


sub list {
  my($self, $fch) = @_;

  my $f = $self->formValidate(
    { get => 'p',   required => 0, default => 1, template => 'page' },
    { get => 'q',   required => 0, default => '' },
    { get => 'fil', required => 0, default => '' },
  );
  return $self->resNotFound if $f->{_err};

  my($list, $np) = $self->filFetchDB(char => $f->{fil}, {
    tagspoil => $self->authPref('spoilers')||0,
  }, {
    $fch ne 'all' ? ( char => $fch ) : (),
    $f->{q} ? ( search => $f->{q} ) : (),
    results => 50,
    page => $f->{p},
    what => 'vns',
  });

  $self->htmlHeader(title => 'Browse characters');

  my $quri = uri_escape($f->{q});
  form action => '/old/c/all', 'accept-charset' => 'UTF-8', method => 'get';
  div class => 'mainbox';
   h1 'Browse characters';
   $self->htmlSearchBox('c', $f->{q});
   p class => 'browseopts';
    for ('all', 'a'..'z', 0) {
      a href => "/old/c/$_?q=$quri;fil=$f->{fil}", $_ eq $fch ? (class => 'optselected') : (), $_ eq 'all' ? 'ALL' : $_ ? uc $_ : '#';
    }
   end;

   p class => 'filselect';
    a id => 'filselect', href => '#c';
     lit '<i>&#9656;</i> Filters<i></i>';
    end;
   end;
   input type => 'hidden', class => 'hidden', name => 'fil', id => 'fil', value => $f->{fil};
  end;
  end 'form';

  if(!@$list) {
    div class => 'mainbox';
     h1 'No results';
     p 'No characters found that matched your criteria.';
    end;
  }

  @$list && $self->charBrowseTable($list, $np, $f, "/old/c/$fch?q=$quri;fil=$f->{fil}");

  $self->htmlFooter;
}


# Also used on Handler::Traits
sub charBrowseTable {
  my($self, $list, $np, $f, $uri) = @_;

  $self->htmlBrowse(
    class    => 'charb',
    items    => $list,
    options  => $f,
    nextpage => $np,
    pageurl  => $uri,
    sorturl  => $uri,
    header   => [ [ '' ], [ '' ] ],
    row      => sub {
      my($s, $n, $l) = @_;
      Tr;
       td class => 'tc1';
        cssicon "gen $l->{gender}", $GENDER{$l->{gender}} if $l->{gender} ne 'unknown';
       end;
       td class => 'tc2';
        a href => "/c$l->{id}", title => $l->{original}||$l->{name}, shorten $l->{name}, 50;
        b class => 'grayedout';
         my $i = 1;
         my %vns;
         for (@{$l->{vns}}) {
           next if $_->{spoil} || $vns{$_->{vid}}++;
           last if $i++ > 4;
           txt ', ' if $i > 2;
           a href => "/v$_->{vid}/chars", title => $_->{vntitle}, shorten $_->{vntitle}, 30;
         }
        end;
       end;
      end;
    }
  )
}


1;

