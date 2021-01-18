
package VNDB::Handler::Staff;

use strict;
use warnings;
use TUWF qw(:html :xml uri_escape);
use VNDB::Func;
use VNDB::Types;
use List::Util qw(first);

TUWF::register(
  qr{old/s/([a-z0]|all)}               => \&list,
  qr{xml/staff\.xml}               => \&staffxml,
);


sub list {
  my ($self, $char) = @_;

  my $f = $self->formValidate(
    { get => 'p', required => 0, default => 1, template => 'page' },
    { get => 'q', required => 0, default => '' },
    { get => 'fil', required => 0, default => '' },
  );
  return $self->resNotFound if $f->{_err};

  my ($list, $np) = $self->filFetchDB(staff => $f->{fil}, {}, {
    $char ne 'all' ? ( char => $char ) : (),
    $f->{q} ? ($f->{q} =~ /^=(.+)$/ ? (exact => $1) : (search => $f->{q})) : (),
    results => 150,
    page => $f->{p}
  });

  return $self->resRedirect('/s'.$list->[0]{id}, 'temp')
    if $f->{q} && @$list && (!first { $_->{id} != $list->[0]{id} } @$list) && $f->{p} == 1 && !$f->{fil};
    # redirect to the staff page if all results refer to the same entry

  my $quri = join(';', $f->{q} ? 'q='.uri_escape($f->{q}) : (), $f->{fil} ? "fil=$f->{fil}" : ());
  $quri = '?'.$quri if $quri;
  my $pageurl = "/old/s/$char$quri";

  $self->htmlHeader(title => 'Browse staff');

  form action => '/old/s/all', 'accept-charset' => 'UTF-8', method => 'get';
   div class => 'mainbox';
    h1 'Browse staff';
    $self->htmlSearchBox('s', $f->{q});
    p class => 'browseopts';
    for ('all', 'a'..'z', 0) {
      a href => "/old/s/$_$quri", $_ eq $char ? (class => 'optselected') : (), $_ eq 'all' ? 'ALL' : $_ ? uc $_ : '#';
    }
    end;

    p class => 'filselect';
     a id => 'filselect', href => '#s';
      lit '<i>&#9656;</i> Filters<i></i>';
     end;
    end;
    input type => 'hidden', class => 'hidden', name => 'fil', id => 'fil', value => $f->{fil};
   end;
  end 'form';

  $self->htmlBrowseNavigate($pageurl, $f->{p}, $np, 't');
  div class => 'mainbox staffbrowse';
    h1 $f->{q} ? 'Search results' : 'Staff list';
    if(!@$list) {
      p 'No results found';
    } else {
      # spread the results over 3 equivalent-sized lists
      my $perlist = @$list/3 < 1 ? 1 : @$list/3;
      for my $c (0..(@$list < 3 ? $#$list : 2)) {
        ul;
        for ($perlist*$c..($perlist*($c+1))-1) {
          li;
            cssicon 'lang '.$list->[$_]{lang}, $LANGUAGE{$list->[$_]{lang}};
            a href => "/s$list->[$_]{id}",
              title => $list->[$_]{original}, $list->[$_]{name};
          end;
        }
        end;
      }
    }
    clearfloat;
  end 'div';
  $self->htmlBrowseNavigate($pageurl, $f->{p}, $np, 'b');
  $self->htmlFooter;
}


sub staffxml {
  my $self = shift;

  my $f = $self->formValidate(
    { get => 'q', required => 0, maxlength => 500 },
    { get => 'id', required => 0, multi => 1, template => 'id' },
    { get => 'staffid', required => 0, default => 0 }, # The returned id = staff id when set, otherwise it's the alias id
    { get => 'r', required => 0, template => 'uint', min => 1, max => 50, default => 10 },
  );
  return $self->resNotFound if $f->{_err} || (!$f->{q} && !$f->{id} && !$f->{id}[0]);

  my($list, $np) = $self->dbStaffGet(
    !$f->{q} ? () : $f->{q} =~ /^s([1-9]\d*)/ ? (id => $1) : $f->{q} =~ /^=(.+)/ ? (exact => $1) : (search => $f->{q}, sort => 'search'),
    $f->{id} && $f->{id}[0] ? (id => $f->{id}) : (),
    results => $f->{r}, page => 1,
  );

  $self->resHeader('Content-type' => 'text/xml; charset=UTF-8');
  xml;
  tag 'staff', more => $np ? 'yes' : 'no';
   for(@$list) {
     tag 'item', sid => $_->{id}, id => $f->{staffid} ? $_->{id} : $_->{aid}, orig => $_->{original}, $_->{name};
   }
  end;
}

1;
