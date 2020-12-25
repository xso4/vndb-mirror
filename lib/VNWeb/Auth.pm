# This package provides an 'auth' function and a useful object for dealing with
# VNDB sessions. Usage:
#
#   use VNWeb::Auth;
#
#   if(auth) {
#     ..user is logged in
#   }
#
#   my $success = auth->login($user, $pass);
#   auth->logout;
#
#   my $uid = auth->uid;
#   my $wants_spoilers = auth->pref('spoilers');
#   ..etc
#
#   die "You're not allowed to post!" if !auth->permBoard;
#
package VNWeb::Auth;

use v5.24;
use warnings;
use TUWF;
use Exporter 'import';

use Digest::SHA qw|sha1 sha1_hex|;
use Crypt::URandom 'urandom';
use Crypt::ScryptKDF 'scrypt_raw';
use Encode 'encode_utf8';
use MIME::Base64 'encode_base64url';

use VNDBUtil 'norm_ip';
use VNDB::Config;
use VNWeb::DB;

our @EXPORT = ('auth');

sub auth {
    tuwf->req->{auth} ||= do {
        my $cookie = tuwf->reqCookie('auth')||'';
        my($uid, $token_e) = $cookie =~ /^([a-fA-F0-9]{40})\.?(\d+)$/ ? ($2, sha1_hex pack 'H*', $1) : (0, '');

        my $auth = __PACKAGE__->new();
        $auth->_load_session($uid, $token_e);
        $auth
    };
    tuwf->req->{auth};
}


# log user IDs (necessary for determining performance issues, user preferences
# have a lot of influence in this)
TUWF::set log_format => sub {
    my(undef, $uri, $msg) = @_;
    sprintf "[%s] %s %s: %s\n", scalar localtime(), $uri, tuwf->req && auth ? 'u'.auth->uid : '-', $msg;
};



use overload bool => sub { defined shift->{user}{user_id} };

sub uid   { shift->{user}{user_id} }
sub user  { shift->{user} }
sub token { shift->{token} }
sub isMod { auth->permUsermod || auth->permDbmod || auth->permImgmod || auth->permBoardmod || auth->permTagmod }



my @perms = qw/board boardmod edit imgvote imgmod tag dbmod tagmod usermod review/;

sub listPerms { @perms }

# Create a read-only accessor to check if the current user is authorized to
# perform a particular action.
for my $perm (@perms) {
    no strict 'refs';
    *{ 'perm'.ucfirst($perm) } = sub { shift->{user}{"perm_$perm"} }
}


sub _randomascii {
    return join '', map chr($_%92+33), unpack 'C*', urandom shift;
}


# Prepares a plaintext password for database storage
# Arguments: pass, optionally: salt, N, r, p
# Returns: hashed password (hex coded)
sub _preparepass {
    my($self, $pass, $salt, $N, $r, $p) = @_;
    ($N, $r, $p) = @{$self->{scrypt_args}} if !$N;
    $salt ||= urandom(8);
    unpack 'H*', pack 'NCCa8a*', $N, $r, $p, $salt, scrypt_raw(encode_utf8($pass), $self->{scrypt_salt} . $salt, $N, $r, $p, 32);
}


# Hash a password with the same scrypt parameters as the users' current password.
sub _encpass {
    my($self, $uid, $pass) = @_;

    my $args = tuwf->dbVali('SELECT user_getscryptargs(id) FROM users WHERE id =', \$uid);
    return undef if !$args || length($args) != 14;

    my($N, $r, $p, $salt) = unpack 'NCCa8', $args;
    $self->_preparepass($pass, $salt, $N, $r, $p);
}


# Arguments: self, uid, encpass
# Returns: 0 on error, 1 on success
sub _create_session {
    my($self, $uid, $encpass, $pretend) = @_;

    my $token = urandom 20;
    my $token_db = sha1_hex $token;
    return 0 if !tuwf->dbVali('SELECT ',
        sql_func(user_login => \$uid, sql_fromhex($encpass), sql_fromhex $token_db)
    );

    if($pretend) {
        tuwf->dbExeci('SELECT', sql_func user_logout => \$uid, sql_fromhex $token_db);
    } else {
        tuwf->resCookie(auth => unpack('H*', $token).'.'.$uid, httponly => 1, expires => time + 31536000);
        $self->_load_session($uid, $token_db);
    }
    return 1;
}


sub _load_session {
    my($self, $uid, $token_db) = @_;

    my $user = $uid ? tuwf->dbRowi(
        'SELECT ', sql_user(), ',', sql_comma(map "perm_$_", @perms), '
           FROM users u
          WHERE id = ', \$uid,
           'AND', sql_func(user_isvalidsession => 'id', sql_fromhex($token_db), \'web')
    ) : {};

    # Drop the cookie if it's not valid
    tuwf->resCookie(auth => undef) if !$user->{user_id} && tuwf->reqCookie('auth');

    $self->{user}  = $user;
    $self->{token} = $token_db;
    delete $self->{pref};
}


sub new {
    bless {
        scrypt_salt => config->{scrypt_salt}||die(),
        scrypt_args => config->{scrypt_args}||[ 65536, 8, 1 ],
        csrf_key    => config->{form_salt}||die(),
    }, shift;
}


# Returns 1 on success, 0 on failure
# When $pretend is true, it only tests if the user/pass combination is correct,
# but doesn't actually create a session.
sub login {
    my($self, $user, $pass, $pretend) = @_;
    return 0 if $self->uid || !$user || !$pass;

    my $uid = tuwf->dbVali('SELECT id FROM users WHERE username =', \$user);
    return 0 if !$uid;
    my $encpass = $self->_encpass($uid, $pass);
    return 0 if !$encpass;
    $self->_create_session($uid, $encpass, $pretend);
}


sub logout {
    my $self = shift;
    return if !$self->uid;
    tuwf->dbExeci('SELECT', sql_func user_logout => \$self->uid, sql_fromhex $self->{token});
    $self->_load_session();
}


# Create a random token that can be used to reset the password.
# Returns ($uid, $token) if the email address is found in the DB, () otherwise.
sub resetpass {
    my(undef, $mail) = @_;
    my $token = unpack 'H*', urandom(20);
    my $id = tuwf->dbVali(
        select => sql_func(user_resetpass => \$mail, sql_fromhex sha1_hex lc $token)
    );
    return $id ? ($id, $token) : ();
}


# Checks if the password reset token is valid
sub isvalidtoken {
    my(undef, $uid, $token) = @_;
    tuwf->dbVali(
        select => sql_func(user_isvalidsession => \$uid, sql_fromhex(sha1_hex lc $token), \'pass')
    );
}


# Change the users' password, drop all existing sessions and create a new session.
# Requires either the current password or a reset token.
# Returns 1 on success, 0 on failure.
sub setpass {
    my($self, $uid, $token, $oldpass, $newpass) = @_;

    my $code = $token
        ? sha1_hex lc $token
        : $self->_encpass($uid, $oldpass);
    return 0 if !$code;

    my $encpass = $self->_preparepass($newpass);
    return 0 if !tuwf->dbVali(
        select => sql_func user_setpass => \$uid, sql_fromhex($code), sql_fromhex($encpass)
    );
    $self->_create_session($uid, $encpass);
}


sub setmail_token {
    my($self, $mail) = @_;
    my $token = unpack 'H*', urandom(20);
    tuwf->dbExeci(select => sql_func user_setmail_token => \$self->uid, sql_fromhex($self->token), sql_fromhex(sha1_hex lc $token), \$mail);
    $token;
}


sub setmail_confirm {
    my(undef, $uid, $token) = @_;
    tuwf->dbVali(select => sql_func user_setmail_confirm => \$uid, sql_fromhex sha1_hex lc $token);
}


# Generate an CSRF token for this user, also works for anonymous users (albeit
# less secure). The key is only valid for the current hour, tokens for previous
# hours can be generated by passing a negative $hour_offset.
sub csrftoken {
    my($self, $hour_offset, $purpose) = @_;
    # 6 bytes (8 characters in base64) gives 48 bits of security; That's
    # not the 160 bits of a full sha1 hash, but still more than good enough
    # to make random guesses impractical.
    encode_base64url substr sha1(sprintf 'p=%s;k=%s;s=%s;t=%d;',
        $purpose||'',                           # Purpose
        $self->{csrf_key} || 'csrf-token',      # Server secret
        $self->{token} || norm_ip(tuwf->reqIP), # User secret
        (time/3600)+($hour_offset||0)           # Time limitation
    ), 0, 6
}


# Returns 1 if the given CSRF token is still valid (meaning: created for this
# user within the past 12 hours), 0 otherwise.
sub csrfcheck {
    my($self, $token, $purpose) = @_;
    $self->csrftoken($_, $purpose) eq $token && return 1 for reverse -11..0;
    return 0;
}


# TODO: Measure global usage of the pref() and prefSet() calls to see if this cache is actually necessary.

my @pref_columns = qw/
    email_confirmed skin customcss filter_vn filter_release
    notify_dbedit notify_announce notify_post notify_comment
    vn_list_own vn_list_wish tags_all tags_cont tags_ero tags_tech spoilers traits_sexual
    max_sexual max_violence nodistract_can nodistract_noads nodistract_nofancy
/;

# Returns a user preference column for the current user. Lazily loads all
# preferences to speed of subsequent calls.
sub pref {
    my($self, $key) = @_;
    return undef if !$self->uid;

    $self->{pref} ||= tuwf->dbRowi('SELECT', sql_comma(map "\"$_\"", @pref_columns), 'FROM users WHERE id =', \$self->uid);
    $self->{pref}{$key};
}


sub prefSet {
    my($self, $key, $value, $uid) = @_;
    die "Unknown pref key: $_" if !grep $key eq $_, @pref_columns;
    $uid //= $self->uid;
    $self->{pref}{$key} = $value;
    tuwf->dbExeci(qq{UPDATE users SET "$key" =}, \$value, 'WHERE id =', \$self->uid);
}


# Mark any notifications for a particular item for the current user as read.
# Arguments: $vndbid, $num||[@nums]||<missing>
sub notiRead {
    my($self, $id, $num) = @_;
    tuwf->dbExeci('
        UPDATE notifications SET read = NOW() WHERE read IS NULL AND uid =', \$self->uid, 'AND iid =', \$id,
        @_ == 2 ? () : !defined $num ? 'AND num IS NULL' : !ref $num ? sql 'AND num =', \$num : sql 'AND num IN', $num
    ) if $self->uid;
}


# Add an entry to the audit log.
sub audit {
    my($self, $affected_uid, $action, $detail) = @_;
    tuwf->dbExeci('INSERT INTO audit_log', {
        by_uid  => $self->uid(),
        by_name => $self->{user}{user_name},
        by_ip   => tuwf->reqIP(),
        affected_uid  => $affected_uid||undef,
        affected_name => $affected_uid ? sql('(SELECT username FROM users WHERE id =', \$affected_uid, ')') : undef,
        action => $action,
        detail => $detail,
    });
}

1;
