package VNWeb::User::Login;

use VNWeb::Prelude;


TUWF::get '/u/login' => sub {
    not_moe;
    return tuwf->resRedirect('/', 'temp') if auth || config->{read_only};

    my $ref = tuwf->reqGet('ref');
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

    my $ip = norm_ip tuwf->reqIP;
    my $tm = tuwf->dbVali(
        'SELECT', sql_totime('greatest(timeout, now())'), 'FROM login_throttle WHERE ip =', \$ip
    ) || time;
    return +{ _err => 'Too many failed login attempts, please use the password reset form or try again later.' }
        if $tm-time() > config->{login_throttle}[1];

    my $ismail = $data->{username} =~ /@/;
    my $mailmsg = 'Invalid username or password.';

    my $u = tuwf->dbRowi('SELECT id, user_getscryptargs(id) x FROM users WHERE',
        $ismail ? sql('id IN(SELECT uid FROM user_emailtoid(', \$data->{username}, '))')
                : sql('lower(username) = lower(', \$data->{username}, ')')
    );
    # When logging in with an email, make sure we don't disclose whether or not an account with that email exists.
    if ($ismail && !$u->{id}) {
        auth->wasteTime; # make timing attacks a bit harder (not 100% perfect, DB lookups & different scrypt args can still influence timing)
        return +{ _err => $mailmsg };
    }
    return +{ _err => 'No user with that name.' } if !$u->{id};
    return +{ _err => 'Account disabled, please use the password reset form to re-activate your account.' } if !$u->{x};

    my $insecure = is_insecurepass $data->{password};
    my $ret = auth->login($u->{id}, $data->{password}, $insecure);

    # Failed login
    if (!$ret) {
        auth->audit($u->{id}, 'bad password', 'failed login attempt');
        my $upd = {
            ip      => \$ip,
            timeout => sql_fromtime $tm + config->{login_throttle}[0]
        };
        tuwf->dbExeci('INSERT INTO login_throttle', $upd, 'ON CONFLICT (ip) DO UPDATE SET', $upd);
        return +{ _err => $ismail ? $mailmsg : 'Incorrect password.' }

    # Insecure password
    } elsif ($insecure) {
        return +{ insecurepass => 1, uid => $u->{id} };

    # Account marked for deletion
    } elsif (40 == length $ret) {
        return +{ _redir => "/$u->{id}/del/$ret" };

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


TUWF::post qr{/$RE{uid}/logout}, sub {
    return tuwf->resNotFound if !auth || auth->uid ne tuwf->capture('id') || (tuwf->reqPost('csrf')||'') ne auth->csrftoken;
    auth->logout;
    tuwf->resRedirect('/', 'post');
};

1;
