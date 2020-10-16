
package VNDB::Handler::Producers;

use strict;
use warnings;
use TUWF ':html', ':xml';
use VNDB::Func;
use VNDB::Types;


TUWF::register(
  qr{xml/producers\.xml}           => \&pxml,
);


# peforms a (simple) search and returns the results in XML format
sub pxml {
  my $self = shift;

  my $f = $self->formValidate(
    { get => 'q', required => 0, maxlength => 500 },
    { get => 'id', required => 0, multi => 1, template => 'id' },
    { get => 'r', required => 0, template => 'uint', min => 1, max => 50, default => 10 },
  );
  return $self->resNotFound if $f->{_err} || (!$f->{q} && !$f->{id} && !$f->{id}[0]);

  my($list, $np) = $self->dbProducerGet(
    !$f->{q} ? () : $f->{q} =~ /^p([1-9]\d*)/ ? (id => $1) : (search => $f->{q}, sort => 'search'),
    $f->{id} && $f->{id}[0] ? (id => $f->{id}) : (),
    results => $f->{r},
    page => 1,
  );

  $self->resHeader('Content-type' => 'text/xml; charset=UTF-8');
  xml;
  tag 'producers', more => $np ? 'yes' : 'no', query => $f->{q}||'';
   for(@$list) {
     tag 'item', id => $_->{id}, $_->{name};
   }
  end;
}


1;

