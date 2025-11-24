# This package provides an 'auth' function and a useful object for dealing with
# VNDB sessions. Usage:
#
#   use VNWeb::Auth;
#
#   if(auth) {
#     ..user is logged in
#   }
#
#   my $success = auth->login($uid, $pass);
#   auth->logout;
#
#   my $uid = auth->uid;
#   my $wants_spoilers = auth->pref('spoilers');
#   ..etc
#
#   die "You're not allowed to post!" if !auth->permBoard;
#
package VNWeb::Auth;

use v5.36;
use FU;
use FU::SQL;
use Exporter 'import';

use Carp 'croak';
use Digest::SHA qw|sha1 sha1_hex|;
use Crypt::URandom 'urandom';
use Crypt::ScryptKDF 'scrypt_raw';
use MIME::Base64 'encode_base64url';
use POSIX 'strftime';

use VNDB::Func qw/norm_ip hex2bin bin2hex/;
use VNDB::Config;
use VNWeb::DB;

our @EXPORT = ('auth');

sub auth {
    fu->{auth} //= do {
        my $auth = __PACKAGE__->new();
        if(config->{read_only} || config->{moe}) {
            # Account functionality disabled in read-only or moe mode.

        # API requests have two authentication methods:
        # - If the origin equals the site, use the same Cookie auth as the rest of the site (handy for userscripts)
        # - Otherwise, a custom token-based auth, but this hasn't been implemented yet
        } elsif(VNWeb::Validation::is_api() && (fu->header('origin')//'_') ne config->{url}) {
            # XXX: User prefs and permissions are not loaded in this case - they're not used.
            $auth->_load_api2(fu->header('authorization'));

        } else {
            my $cookie = fu->cookie(config->{cookie_prefix}.'auth' => { accept_array => 'first', onerror => '' });
            my($uid, $token_db) = $cookie =~ /^([a-fA-F0-9]{40})\.?u?(\d+)$/ ? ('u'.$2, sha1 hex2bin $1) : (0, '');
            $auth->_load_session($uid, $token_db);
        }
        $auth
    };
}



use overload bool => sub { defined shift->{user}{user_id} };

sub uid   { shift->{user}{user_id} }
sub user  { shift->{user} }
sub token { shift->{token} }
sub isMod { auth->permUsermod || auth->permDbmod || auth->permBoardmod || auth->permTagmod }



my @perms = qw/board boardmod edit imgvote tag dbmod tagmod usermod review lengthvote/;

sub listPerms { @perms }

# Create a read-only accessor to check if the current user is authorized to
# perform a particular action.
for my $perm (@perms) {
    no strict 'refs';
    *{ 'perm'.ucfirst($perm) } = sub { shift->{user}{"perm_$perm"} }
}



# Pref(erences) are like permissions, we load these columns eagerly so they can
# be accessed through auth->pref().
my @pref_columns = qw/
    timezone skin customcss_csum titles notifyopts
    c_noti_low c_noti_mid c_noti_high
    vnimage tags_all tags_cont tags_ero tags_tech
    spoilers traits_sexual max_sexual max_violence
    tableopts_c tableopts_v tableopts_vt
    nodistract_can nodistract_noads nodistract_nofancy
/;


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
    utf8::encode(my $utf8pass = $pass);
    pack 'NCCa8a*', $N, $r, $p, $salt, scrypt_raw($utf8pass, $self->{scrypt_salt} . $salt, $N, $r, $p, 32);
}


# Hash a password with the same scrypt parameters as the users' current password.
sub _encpass($self, $uid, $pass) {
    my $args = fu->sql('SELECT user_getscryptargs(id) FROM users WHERE id = $1', $uid)->val;
    return undef if !$args || length($args) != 14;

    my($N, $r, $p, $salt) = unpack 'NCCa8', $args;
    $self->_preparepass($pass, $salt, $N, $r, $p);
}


# Arguments: self, uid, encpass
# Returns: 0 on error, 1 on success, token on !pretend && deleted account
sub _create_session($self, $uid, $encpass, $pretend=0) {
    my $token_pub = urandom 20;
    my $token_db = sha1 $token_pub;
    return 0 if !fu->sql(q{SELECT user_login($1, 'web', $2, $3)}, $uid, $encpass, $token_db)->val;

    if($pretend) {
        fu->sql('SELECT user_logout($1, $2)', $uid, $token_db)->exec;
        return 1;
    } else {
        fu->set_cookie(config->{cookie_prefix}.auth => bin2hex($token_pub).'.'.$uid, config->{cookie_defaults}->%*, httponly => 1, expires => time + 31536000);
        return $self->_load_session($uid, $token_db) ? 1 : $token_db;
    }
}


sub _load_session($self, $uid=0, $token_db='') {
    my $user = ($uid && fu->SQL(
        'SELECT ', USER, ',', RAW(join ',', @pref_columns, map "perm_$_", @perms), '
           FROM users u
           JOIN users_shadow us ON us.id = u.id
           JOIN users_prefs up ON up.id = u.id
          WHERE u.id = ', $uid, "
            AND us.delete_at IS NULL
            AND user_validate_session(u.id, ", $token_db, ", 'web') IS DISTINCT FROM NULL"
    )->rowh) || {};

    # Drop the cookie if it's not valid
    fu->set_cookie(config->{cookie_prefix}.'auth' => '', config->{cookie_defaults}->%*, httponly => 1, 'max-age' => 0)
        if !$user->{user_id} && fu->cookie(config->{cookie_prefix}.'auth');

    $self->{user}  = $user;
    $self->{token} = $token_db;
    $user->{user_id};
}


sub new {
    bless {
        scrypt_salt => config->{scrypt_salt}||die(),
        scrypt_args => config->{scrypt_args}||[ 65536, 8, 1 ],
        csrf_key    => config->{form_salt}||die(),
        user        => {},
    }, shift;
}


# Returns 1 on success, 0 on failure, session token when account has been deleted.
# When $pretend is true, it only tests if the uid/pass combination is correct,
# but doesn't actually create a session.
sub login($self, $uid, $pass, $pretend=0) {
    return 0 if $self->uid;
    my $encpass = $self->_encpass($uid, $pass);
    return 0 if !$encpass;
    $self->_create_session($uid, $encpass, $pretend);
}


sub logout($self) {
    return if !$self->uid;
    fu->sql('SELECT user_logout($1, $2)', $self->uid, $self->{token})->exec;
    $self->_load_session();
}


sub wasteTime($self) {
    $self->_preparepass(urandom(20));
}


# Create a random token that can be used to reset the password.
# Returns ($uid, $email, $token) if the email address is found in the DB, () otherwise.
sub resetpass($self, $mail) {
    my $token = urandom(20);
    my $u = fu->sql('SELECT uid, mail FROM user_resetpass($1, $2) x(uid, mail)', $mail, sha1 $token)->rowh;
    return $u ? ($u->{uid}, $u->{mail}, $token) : ();
}


# Checks if the password reset token is valid
sub isvalidtoken($self, $uid, $token) {
    fu->sql(q{SELECT user_validate_session($1, $2, 'pass') IS DISTINCT FROM NULL}, $uid, sha1 $token)->val
}


# Change the users' password, drop all existing sessions and create a new session.
# Requires either the current password or a reset token.
# Returns 1 on success, 0 on failure.
sub setpass($self, $uid, $token, $oldpass, $newpass) {
    my $code = $token
        ? sha1 $token
        : $self->_encpass($uid, $oldpass);
    return 0 if !$code;

    my $encpass = $self->_preparepass($newpass);
    return 0 if !fu->sql('SELECT user_setpass($1, $2, $3)', $uid, $code, $encpass)->val;
    $self->_create_session($uid, $encpass);
}


sub setmail_token($self, $mail) {
    my $token = urandom(20);
    fu->sql('SELECT user_setmail_token($1, $2, $3, $4)', $self->uid, $self->token, sha1($token), $mail)->exec;
    $token;
}


sub setmail_confirm($self, $uid, $token) {
    fu->sql('SELECT user_setmail_confirm($1, $2)', $uid, sha1($token))->val
}


# Generate an CSRF token for this user, also works for anonymous users (albeit
# less secure). The key is only valid for the current hour, tokens for previous
# hours can be generated by passing a negative $hour_offset.
sub csrftoken($self, $hour_offset=0, $purpose='') {
    # 6 bytes (8 characters in base64) gives 48 bits of security; That's
    # not the 160 bits of a full sha1 hash, but still more than good enough
    # to make random guesses impractical.
    encode_base64url substr sha1(sprintf 'p=%s;k=%s;s=%s;t=%d;',
        $purpose,                           # Purpose
        $self->{csrf_key} || 'csrf-token',  # Server secret
        ($self->{token} ? lc bin2hex $self->{token} : norm_ip(fu->ip)), # User secret
        (time/3600)+$hour_offset            # Time limitation
    ), 0, 6
}


# Returns 1 if the given CSRF token is still valid (meaning: created for this
# user within the past 12 hours), 0 otherwise.
sub csrfcheck($self, $token, $purpose='') {
    $self->csrftoken($_, $purpose) eq $token && return 1 for reverse -11..0;
    return 0;
}


sub pref($self, $key) {
    return undef if !$self->uid;
    croak "Pref key not loaded: $key" if !exists $self->{user}{$key};
    $self->{user}{$key};
}


# Mark any notifications for a particular item for the current user as read.
# Arguments: $vndbid, $num||[@nums]||<missing>
sub notiRead {
    my($self, $id, $num) = @_;
    return if !$self->uid;
    my $upd = fu->SQL('
        UPDATE notifications SET read = NOW() WHERE read IS NULL AND uid =', $self->uid, 'AND iid =', $id,
        @_ == 2 ? () : !defined $num ? 'AND num IS NULL' : !ref $num ? ('AND num =', $num) : ('AND num', IN $num)
    )->exec;
    $self->{user}{c_noti_low} = undef if $upd; # Force updating the cached counts
}


# Add an entry to the audit log.
sub audit($self, $affected_uid, $action, $detail='') {
    fu->SQL('INSERT INTO audit_log', VALUES {
        by_uid  => $self->uid,
        by_name => $self->{user}{user_name},
        by_ip   => VNWeb::Validation::ipinfo(),
        affected_uid  => $affected_uid||undef,
        affected_name => $affected_uid ? SQL('(SELECT username FROM users WHERE id =', $affected_uid, ')') : undef,
        action => $action,
        detail => $detail,
    })->exec;
}



my $api2_alpha = "ybndrfg8ejkmcpqxot1uwisza345h769"; # z-base-32

# Converts from bin to encoded form
sub _api2_encode($bin) {
    state %l = map +(substr(unpack('B*', chr $_), 3, 8), substr($api2_alpha, $_, 1)), 0..(length($api2_alpha)-1);
    (unpack('B*', $bin) =~ s/(.....)/$l{$1}/erg)
        =~ s/(....)(.....)(.....)(....)(.....)(.....)(....)/$1-$2-$3-$4-$5-$6-$7/r;
}
# Converts from encoded form to bin
sub _api2_decode($token) {
    state %l = ('-', '', map +(substr($api2_alpha, $_, 1), substr unpack('B*', chr $_), 3, 8), 0..(length($api2_alpha)-1));
    pack 'B*', $token =~ s{(.)}{$l{$1} // return}erg
}

# Takes a UID, returns bin value
sub _api2_gen_token($uid) {
    # Scramble for cosmetic reasons. This bytewise scramble still leaves an obvious pattern, but w/e.
    (pack('N', $uid =~ s/^u//r).urandom(16)) =~ s/^(.)(.)(.)(.)(..)(....)(....)(....)(..)$/$5$1$6$2$7$3$8$4$9/sr;
}

# Extract UID from binary token
sub _api2_get_uid($token) {
    my $n = unpack 'N', $token =~ s/^..(.)....(.)....(.)....(.)..$/$1$2$3$4/sr;
    $n >= 1 && $n < 10_000_000 && "u$n"
}


sub _load_api2 {
    my($self, $header) = @_;
    return if !$header;
    return VNWeb::API::err(401, 'Invalid Authorization header format.') if $header !~ /^(?i:Token) +([-$api2_alpha]+)$/;
    my $token_enc = $1;
    return VNWeb::API::err(401, 'Invalid token format.') if length($token_enc =~ s/-//rg) != 32 || !length(my $token = _api2_decode $token_enc);
    my $uid = _api2_get_uid $token or return VNWeb::API::err(401, 'Invalid token.');
    my $user = fu->SQL(
        'SELECT ', USER, ', x.listread, x.listwrite
           FROM users u, users_shadow us, user_validate_session(', $uid, ',', $token, ", 'api2') x
          WHERE u.id =", $uid, 'AND x.uid = u.id AND us.id = u.id AND us.delete_at IS NULL'
    )->rowh;
    return VNWeb::API::err(401, 'Invalid token.') if !$user;
    $self->{token} = $token;
    $self->{user} = $user;
    $self->{api2} = 1;
}

sub api2_tokens($self, $uid) {
	return [] if !$self;
	my $r = fu->sql(q{
        SELECT coalesce(notes, '') AS notes, listread, listwrite, added::date, token
             , (CASE WHEN expires = added THEN '' ELSE expires::date::text END) AS lastused
          FROM user_api2_tokens($1, $2, $3)
         ORDER BY added}, $uid, $self->uid, $self->token)->allh;
     $_->{token} = _api2_encode($_->{token}) for @$r;
     $r;
}

sub api2_set_token($self, $uid, %o) {
    return if !auth;
    my $token = $o{token} ? _api2_decode($o{token}) : _api2_gen_token($uid);
    fu->sql('SELECT user_api2_set_token($1, $2, $3, $4, $5, $6, $7)',
        $uid, $self->uid, $self->{token}, $token, $o{notes}, $o{listread}//0, $o{listwrite}//0
    )->exec;
    _api2_encode($token);
}

sub api2_del_token($self, $uid, $token) {
    return if !$self;
    fu->sql('SELECT user_api2_del_token($1, $2, $3, $4)', $uid, $self->uid, $self->{token}, _api2_decode($token))->exec;
}


# API-specific permission checks
# (Always return true for cookie-based auth)
sub api2Listread  { $_[0]{user}{user_id} && (!$_[1] || $_[0]{user}{user_id} eq $_[1]) && (!$_[0]{api2} || $_[0]{user}{listread}) }
sub api2Listwrite { $_[0]{user}{user_id} && (!$_[1] || $_[0]{user}{user_id} eq $_[1]) && (!$_[0]{api2} || $_[0]{user}{listwrite}) }

1;
