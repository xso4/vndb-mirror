package VNWeb::User::Login;

use VNWeb::Prelude;


TUWF::get '/u/login' => sub {
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

    my $insecure = is_insecurepass $data->{password};

    my $u = tuwf->dbRowi('SELECT id, user_getscryptargs(id) x FROM users WHERE',
        $data->{username} =~ /@/ ? sql('id IN(SELECT * FROM user_emailtoid(', \$data->{username}, '))')
                                 : sql('lower(username) = lower(', \$data->{username}, ')')
    );
    return +{ _err => 'No user with that name or email.' } if !$u->{id};
    return +{ _err => 'Account disabled, please use the password reset form to re-activate your account.' } if !$u->{x};

    if(auth->login($u->{id}, $data->{password}, $insecure)) {
        auth->audit(auth->uid, 'login') if !$insecure;
        return $insecure ? { insecurepass => 1, uid => $u->{id} } : { ok => 1 };
    }

    # Failed login, log and update throttle.
    auth->audit($u->{id}, 'bad password', 'failed login attempt');
    my $upd = {
        ip      => \$ip,
        timeout => sql_fromtime $tm + config->{login_throttle}[0]
    };
    tuwf->dbExeci('INSERT INTO login_throttle', $upd, 'ON CONFLICT (ip) DO UPDATE SET', $upd);
    +{ _err => 'Incorrect password.' }
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
