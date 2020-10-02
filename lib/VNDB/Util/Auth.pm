# Compatibility shim around VNWeb::Auth, new code should use that instead.
package VNDB::Util::Auth;


use strict;
use warnings;
use Exporter 'import';
use TUWF ':html';
use VNWeb::Auth;


our @EXPORT = qw|
  authInfo authCan authGetCode authCheckCode authPref
|;


sub authInfo {
  # Used to return a lot more, but only the id is still used now.
  # (code using other fields has been migrated)
  +{ id => auth->uid }
}


# returns whether the currently loggedin or anonymous user can perform
# a certain action.
sub authCan {
  my(undef, $act) = @_;
  auth && auth->{user}{"perm_$act"}
}


# Generate a code to be used later on to validate that the form was indeed
# submitted from our site and by the same user/visitor. Not limited to
# logged-in users.
# Arguments:
#   form-id (ignored nowadyas)
#   time (also ignored)
sub authGetCode {
  auth->csrftoken;
}


# Validates the correctness of the returned code, creates an error page and
# returns false if it's invalid, returns true otherwise. Codes are valid for at
# least two and at most three hours.
# Arguments:
#   [ form-id, [ code ] ]
# If the code is not given, uses the 'formcode' form parameter instead. If
# form-id is not given, the path of the current requests is used.
sub authCheckCode {
  my $self = shift;
  my $id = shift;
  my $code = shift || $self->reqParam('formcode');
  return _incorrectcode($self) if !auth->csrfcheck($code);
  1;
}


sub _incorrectcode {
  my $self = shift;
  $self->resInit;
  $self->htmlHeader(title => 'Validation code expired', noindex => 1);

  div class => 'mainbox';
   h1 'Validation code expired';
   div class => 'warning';
    p 'Please hit the back-button of your browser, refresh the page and try again.';
   end;
  end;

  $self->htmlFooter;
  return 0;
}


sub authPref {
  my(undef, $key, $val) = @_;
  @_ == 2 ? auth->pref($key)||'' : auth->prefSet($key, $val);
}

1;
