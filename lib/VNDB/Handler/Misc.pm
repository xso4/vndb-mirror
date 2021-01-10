
package VNDB::Handler::Misc;


use strict;
use warnings;
use TUWF ':html', ':xml', 'uri_escape';
use VNDB::Func;
use VNDB::Types;


TUWF::register(
  qr{nospam},                         \&nospam,
  qr{xml/prefs\.xml},                 \&prefs,
);


sub nospam {
  my $self = shift;
  $self->htmlHeader(title => 'Could not send form', noindex => 1);

  div class => 'mainbox';
   h1 'Could not send form';
   div class => 'warning';
    h2 'Error';
    p 'The form could not be sent, please make sure you have Javascript enabled in your browser.';
   end;
  end;

  $self->htmlFooter;
}


sub prefs {
  my $self = shift;
  return if !$self->authCheckCode;
  return $self->resNotFound if !$self->authInfo->{id};
  my $f = $self->formValidate(
    { get => 'key',   enum => [qw|filter_vn filter_release|] },
    { get => 'value', required => 0, maxlength => 2000 },
  );
  return $self->resNotFound if $f->{_err};
  $self->authPref($f->{key}, $f->{value});

  # doesn't really matter what we return, as long as it's XML
  $self->resHeader('Content-type' => 'text/xml');
  xml;
  tag 'done', '';
}


1;

