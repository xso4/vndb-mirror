package VNWeb::User::Login;

use VNWeb::Prelude;


FU::get '/u/login' => sub {
    not_moe;
    fu->redirect(temp => '/') if auth || config->{read_only};

    my $ref = fu->query(ref => {onerror => ''});
    $ref = '/' if !$ref || $ref !~ /^\//;

    framework_ title => 'Login', sub {
        div_ widget(UserLogin => {ref => $ref}), '';
    };
};


js_api UserLogin => {
    username => {},
    password => { password => 1 }
}, sub {
    my $data = shift;

    my $ip = norm_ip fu->ip;
    my $tm = fu->sql('SELECT greatest(timeout, now()) FROM login_throttle WHERE ip = $1', $ip)->val || time;
    return +{ _err => 'Too many failed login attempts, please use the password reset form or try again later.' }
        if $tm-time() > config->{login_throttle}[1];

    my $ismail = $data->{username} =~ /@/;
    my $mailmsg = 'Invalid username or password.';

    my $u = fu->sql(
        'SELECT id, user_getscryptargs(id) x FROM users WHERE '.($ismail
            ? 'id IN(SELECT uid FROM user_emailtoid($1))'
            : 'lower(username) = lower($1)'
        ), $data->{username}
    )->allh;

    # Receiving more than one row only possible when logging in with email.
    # Address normalization has changed over time, so sign-up with a now-duplicate address was possible.
    return 'Multiple accounts exist with that email address, please login with username instead.' if @$u > 1;
    $u = $u->[0];

    # When logging in with an email, make sure we don't disclose whether or not an account with that email exists.
    if ($ismail && !$u) {
        auth->wasteTime; # make timing attacks a bit harder (not 100% perfect, DB lookups & different scrypt args can still influence timing)
        return $mailmsg;
    }
    return 'No user with that name.' if !$u;
    return 'Account disabled, please use the password reset form to re-activate your account.' if !$u->{x};

    my $insecure = is_insecurepass $data->{password};
    my $ret = auth->login($u->{id}, $data->{password}, $insecure);

    # Failed login
    if (!$ret) {
        auth->audit($u->{id}, 'bad password', 'failed login attempt');
        my $upd = {
            ip      => $ip,
            timeout => $tm + config->{login_throttle}[0]
        };
        fu->SQL('INSERT INTO login_throttle', VALUES($upd), 'ON CONFLICT (ip) DO UPDATE', SET($upd))->exec;
        return $ismail ? $mailmsg : 'Incorrect password.';

    # Insecure password
    } elsif ($insecure) {
        return +{ insecurepass => 1, uid => $u->{id} };

    # Account marked for deletion
    } elsif (20 == length $ret) {
        return +{ _redir => "/$u->{id}/del/".bin2hex($ret) };

    # Successful login
    } elsif ($ret) {
        auth->audit(auth->uid, 'login');
        return +{ ok => 1 };
    }
};


js_api UserChangePass => {
    uid      => { vndbid => 'u' },
    oldpass  => { password => 1 },
    newpass  => { password => 1 },
}, sub {
    my $data = shift;
    return +{ _err => 'Your new password has also been leaked.' } if is_insecurepass $data->{newpass};
    die if !auth->setpass($data->{uid}, undef, $data->{oldpass}, $data->{newpass}); # oldpass should already have been verified.
    auth->audit($data->{uid}, 'password change', 'after login with an insecure password');
    {}
};


FU::post qr{/$RE{uid}/logout}, sub($uid) {
    fu->notfound if !auth || auth->uid ne $uid || fu->formdata('csrf', { onerror => '' }) ne auth->csrftoken;
    auth->logout;
    fu->redirect(tempget => '/');
};

1;
