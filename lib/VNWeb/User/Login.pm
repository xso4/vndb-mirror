package VNWeb::User::Login;

use VNWeb::Prelude;


TUWF::get '/u/login' => sub {
    return tuwf->resRedirect('/', 'temp') if auth || config->{read_only};

    my $ref = tuwf->reqGet('ref');
    $ref = '/' if !$ref || $ref !~ /^\//;

    framework_ title => 'Login', sub {
        elm_ 'User.Login' => tuwf->compile({}), $ref;
    };
};


elm_api UserLogin => undef, {
    username => { username => 1 },
    password => { password => 1 }
}, sub {
    my $data = shift;

    my $ip = norm_ip tuwf->reqIP;
    my $tm = tuwf->dbVali(
        'SELECT', sql_totime('greatest(timeout, now())'), 'FROM login_throttle WHERE ip =', \$ip
    ) || time;
    return elm_LoginThrottle if $tm-time() > config->{login_throttle}[1];

    my $insecure = is_insecurepass $data->{password};
    if(auth->login($data->{username}, $data->{password}, $insecure)) {
        auth->audit(auth->uid, 'login') if !$insecure;
        return $insecure ? elm_InsecurePass : elm_Success
    }

    # Failed login, log and update throttle.
    auth->audit(tuwf->dbVali('SELECT id FROM users WHERE lower(username) = lower(', \$data->{username}, ')'), 'bad password', 'failed login attempt');
    my $upd = {
        ip      => \$ip,
        timeout => sql_fromtime $tm + config->{login_throttle}[0]
    };
    tuwf->dbExeci('INSERT INTO login_throttle', $upd, 'ON CONFLICT (ip) DO UPDATE SET', $upd);
    elm_BadLogin
};


elm_api UserChangePass => undef, {
    username => { username => 1 },
    oldpass  => { password => 1 },
    newpass  => { password => 1 },
}, sub {
    my $data = shift;
    my $uid = tuwf->dbVali('SELECT id FROM users WHERE lower(username) = lower(', \$data->{username}, ')');
    die if !$uid;
    return elm_InsecurePass if is_insecurepass $data->{newpass};
    auth->audit($uid, 'password change', 'after login with an insecure password');
    die if !auth->setpass($uid, undef, $data->{oldpass}, $data->{newpass}); # oldpass should already have been verified.
    elm_Success
};


TUWF::post qr{/$RE{uid}/logout}, sub {
    return tuwf->resNotFound if !auth || auth->uid ne tuwf->capture('id') || (tuwf->reqPost('csrf')||'') ne auth->csrftoken;
    auth->logout;
    tuwf->resRedirect('/', 'post');
};

1;
