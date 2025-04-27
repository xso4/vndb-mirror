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
use Exporter 'import';

use Carp 'croak';
use Digest::SHA qw|sha1 sha1_hex|;
use Crypt::URandom 'urandom';
use Crypt::ScryptKDF 'scrypt_raw';
use MIME::Base64 'encode_base64url';
use POSIX 'strftime';

use VNDB::Func 'norm_ip';
use VNDB::Config;
use VNWeb::DB;

our @EXPORT = ('auth');

sub auth {
    fu->{auth} ||= do {
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
            my($uid, $token_e) = $cookie =~ /^([a-fA-F0-9]{40})\.?u?(\d+)$/ ? ('u'.$2, sha1_hex pack 'H*', $1) : (0, '');
            $auth->_load_session($uid, $token_e);
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
    timezone skin customcss_csum titles::text
    notify_dbedit notify_post notify_comment
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
    unpack 'H*', pack 'NCCa8a*', $N, $r, $p, $salt, scrypt_raw($utf8pass, $self->{scrypt_salt} . $salt, $N, $r, $p, 32);
}


# Hash a password with the same scrypt parameters as the users' current password.
sub _encpass {
    my($self, $uid, $pass) = @_;

    my $args = fu->dbVali('SELECT user_getscryptargs(id) FROM users WHERE id =', \$uid);
    return undef if !$args || length($args) != 14;

    my($N, $r, $p, $salt) = unpack 'NCCa8', $args;
    $self->_preparepass($pass, $salt, $N, $r, $p);
}


# Arguments: self, uid, encpass
# Returns: 0 on error, 1 on success, token on !pretend && deleted account
sub _create_session {
    my($self, $uid, $encpass, $pretend) = @_;

    my $token = urandom 20;
    my $token_db = sha1_hex $token;
    return 0 if !fu->dbVali('SELECT ',
        sql_func(user_login => \$uid, \'web', sql_fromhex($encpass), sql_fromhex $token_db)
    );

    if($pretend) {
        fu->dbExeci('SELECT', sql_func user_logout => \$uid, sql_fromhex $token_db);
        return 1;
    } else {
        fu->set_cookie(config->{cookie_prefix}.auth => unpack('H*', $token).'.'.$uid, config->{cookie_defaults}->%*, httponly => 1, expires => time + 31536000);
        return $self->_load_session($uid, $token_db) ? 1 : $token_db;
    }
}


sub _load_session {
    my($self, $uid, $token_db) = @_;

    my $user = $uid ? fu->dbRowi(
        'SELECT ', sql_user(), ',', sql_comma(@pref_columns, map "perm_$_", @perms), '
           FROM users u
           JOIN users_shadow us ON us.id = u.id
           JOIN users_prefs up ON up.id = u.id
          WHERE u.id = ', \$uid, '
            AND us.delete_at IS NULL
            AND', sql_func(user_validate_session => 'u.id', sql_fromhex($token_db), \'web'), 'IS DISTINCT FROM NULL'
    ) : {};

    # Drop the cookie if it's not valid
    fu->set_cookie(config->{cookie_prefix}.'auth' => '', 'max-age' => 0) if !$user->{user_id} && fu->cookie(config->{cookie_prefix}.'auth');

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


# Returns 1 on success, 0 on failure
# When $pretend is true, it only tests if the uid/pass combination is correct,
# but doesn't actually create a session.
sub login {
    my($self, $uid, $pass, $pretend) = @_;
    return 0 if $self->uid || !$uid || !$pass;
    my $encpass = $self->_encpass($uid, $pass);
    return 0 if !$encpass;
    $self->_create_session($uid, $encpass, $pretend);
}


sub logout {
    my $self = shift;
    return if !$self->uid;
    fu->dbExeci('SELECT', sql_func user_logout => \$self->uid, sql_fromhex $self->{token});
    $self->_load_session();
}


sub wasteTime {
    my $self = shift;
    $self->_preparepass(urandom(20));
}


# Create a random token that can be used to reset the password.
# Returns ($uid, $email, $token) if the email address is found in the DB, () otherwise.
sub resetpass {
    my(undef, $mail) = @_;
    my $token = unpack 'H*', urandom(20);
    my $u = fu->dbRowi(
        'SELECT uid, mail FROM', sql_func(user_resetpass => \$mail, sql_fromhex sha1_hex lc $token), 'x(uid, mail)'
    );
    return $u->{uid} ? ($u->{uid}, $u->{mail}, $token) : ();
}


# Checks if the password reset token is valid
sub isvalidtoken {
    my(undef, $uid, $token) = @_;
    fu->dbVali('SELECT', sql_func(user_validate_session => \$uid, sql_fromhex(sha1_hex lc $token), \'pass'), 'IS DISTINCT FROM NULL');
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
    return 0 if !fu->dbVali(
        select => sql_func user_setpass => \$uid, sql_fromhex($code), sql_fromhex($encpass)
    );
    $self->_create_session($uid, $encpass);
}


sub setmail_token {
    my($self, $mail) = @_;
    my $token = unpack 'H*', urandom(20);
    fu->dbExeci(select => sql_func user_setmail_token => \$self->uid, sql_fromhex($self->token), sql_fromhex(sha1_hex lc $token), \$mail);
    $token;
}


sub setmail_confirm {
    my(undef, $uid, $token) = @_;
    fu->dbVali(select => sql_func user_setmail_confirm => \$uid, sql_fromhex sha1_hex lc $token);
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
        $self->{token} || norm_ip(fu->ip),      # User secret
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


sub pref {
    my($self, $key) = @_;
    return undef if !$self->uid;
    croak "Pref key not loaded: $key" if !exists $self->{user}{$key};
    $self->{user}{$key};
}


# Mark any notifications for a particular item for the current user as read.
# Arguments: $vndbid, $num||[@nums]||<missing>
sub notiRead {
    my($self, $id, $num) = @_;
    fu->dbExeci('
        UPDATE notifications SET read = NOW() WHERE read IS NULL AND uid =', \$self->uid, 'AND iid =', \$id,
        @_ == 2 ? () : !defined $num ? 'AND num IS NULL' : !ref $num ? sql 'AND num =', \$num : sql 'AND num IN', $num
    ) if $self->uid;
}


# Add an entry to the audit log.
sub audit {
    my($self, $affected_uid, $action, $detail) = @_;
    fu->dbExeci('INSERT INTO audit_log', {
        by_uid  => $self->uid(),
        by_name => $self->{user}{user_name},
        by_ip   => VNWeb::Validation::ipinfo(),
        affected_uid  => $affected_uid||undef,
        affected_name => $affected_uid ? sql('(SELECT username FROM users WHERE id =', \$affected_uid, ')') : undef,
        action => $action,
        detail => $detail,
    });
}



my $api2_alpha = "ybndrfg8ejkmcpqxot1uwisza345h769"; # z-base-32

# Converts from hex to encoded form
sub _api2_encode {
    state %l = map +(substr(unpack('B*', chr $_), 3, 8), substr($api2_alpha, $_, 1)), 0..(length($api2_alpha)-1);
    (unpack('B*', pack('H*', $_[0])) =~ s/(.....)/$l{$1}/erg)
        =~ s/(....)(.....)(.....)(....)(.....)(.....)(....)/$1-$2-$3-$4-$5-$6-$7/r;
}
# Converts from encoded form to hex
sub _api2_decode {
    state %l = ('-', '', map +(substr($api2_alpha, $_, 1), substr unpack('B*', chr $_), 3, 8), 0..(length($api2_alpha)-1));
    unpack 'H*', pack 'B*', $_[0] =~ s{(.)}{$l{$1} // return}erg
}

# Takes a UID, returns hex value
sub _api2_gen_token {
    # Scramble for cosmetic reasons. This bytewise scramble still leaves an obvious pattern, but w/e.
    unpack 'H*', (pack('N', $_[0] =~ s/^u//r).urandom(16))
        =~ s/^(.)(.)(.)(.)(..)(....)(....)(....)(..)$/$5$1$6$2$7$3$8$4$9/sr;
}

# Extract UID from hex-encoded token
sub _api2_get_uid {
    my $n = unpack 'N', pack('H*', $_[0]) =~ s/^..(.)....(.)....(.)....(.)..$/$1$2$3$4/sr;
    $n >= 1 && $n < 10_000_000 && "u$n"
}


sub _load_api2 {
    my($self, $header) = @_;
    return if !$header;
    return VNWeb::API::err(401, 'Invalid Authorization header format.') if $header !~ /^(?i:Token) +([-$api2_alpha]+)$/;
    my $token_enc = $1;
    return VNWeb::API::err(401, 'Invalid token format.') if length($token_enc =~ s/-//rg) != 32 || !length(my $token = _api2_decode $token_enc);
    my $uid = _api2_get_uid $token or return VNWeb::API::err(401, 'Invalid token.');
    my $user = fu->dbRowi(
        'SELECT ', sql_user(), ', x.listread, x.listwrite
           FROM users u, users_shadow us, ', sql_func(user_validate_session => \$uid, sql_fromhex($token), \'api2'), 'x
          WHERE u.id = ', \$uid, 'AND x.uid = u.id AND us.id = u.id AND us.delete_at IS NULL'
    );
    return VNWeb::API::err(401, 'Invalid token.') if !$user->{user_id};
    $self->{token} = $token;
    $self->{user} = $user;
    $self->{api2} = 1;
}

sub api2_tokens {
    my($self, $uid) = @_;
	return [] if !$self;
	my $r = fu->dbAlli("
        SELECT coalesce(notes, '') AS notes, listread, listwrite, added::date,", sql_tohex('token'), "AS token
             , (CASE WHEN expires = added THEN '' ELSE expires::date::text END) AS lastused
          FROM", sql_func(user_api2_tokens => \$uid, \$self->uid, sql_fromhex($self->{token})), '
         ORDER BY added');
     $_->{token} = _api2_encode($_->{token}) for @$r;
     $r;
}

sub api2_set_token {
    my($self, $uid, %o) = @_;
    return if !auth;
    my $token = $o{token} ? _api2_decode($o{token}) : _api2_gen_token($uid);
    fu->dbExeci(select => sql_func user_api2_set_token => \$uid, \$self->uid, sql_fromhex($self->{token}),
        sql_fromhex($token), \$o{notes}, \($o{listread}//0), \($o{listwrite}//0));
    _api2_encode($token);
}

sub api2_del_token {
    my($self, $uid, $token) = @_;
    return if !$self;
    fu->dbExeci(select => sql_func user_api2_del_token => \$uid, \$self->uid, sql_fromhex($self->{token}), sql_fromhex(_api2_decode($token)));
}


# API-specific permission checks
# (Always return true for cookie-based auth)
sub api2Listread  { $_[0]{user}{user_id} && (!$_[1] || $_[0]{user}{user_id} eq $_[1]) && (!$_[0]{api2} || $_[0]{user}{listread}) }
sub api2Listwrite { $_[0]{user}{user_id} && (!$_[1] || $_[0]{user}{user_id} eq $_[1]) && (!$_[0]{api2} || $_[0]{user}{listwrite}) }

1;
