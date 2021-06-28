package VNWeb::User::Register;

use VNWeb::Prelude;


TUWF::get '/u/register', sub {
    return tuwf->resRedirect('/', 'temp') if auth;
    framework_ title => 'Register', sub {
        if(global_settings->{lockdown_registration}) {
            div_ class => 'mainbox', sub {
                h1_ 'Create an account';
                p_ 'Account registration is temporarily disabled. Try again later.';
            }
        } else {
            elm_ 'User.Register';
        }
    };
};


elm_api UserRegister => undef, {
    username => { username => 1 },
    email    => { email => 1 },
    vns      => { int => 1 },
}, sub {
    my $data = shift;
    return elm_Unauth if global_settings->{lockdown_registration};

    my $num = tuwf->dbVali("SELECT count FROM stats_cache WHERE section = 'vn'");
    return elm_Bot         if $data->{vns} < $num*0.995 || $data->{vns} > $num*1.005;
    return elm_Taken       if tuwf->dbVali('SELECT 1 FROM users WHERE username =', \$data->{username});
    return elm_DoubleEmail if tuwf->dbVali('SELECT 1 FROM user_emailtoid(', \$data->{email}, ') x');

    my $ip = tuwf->reqIP;
    return elm_DoubleIP if tuwf->dbVali(
        q{SELECT 1 FROM users WHERE registered >= NOW()-'1 day'::interval AND ip <<},
        $ip =~ /:/ ? \"$ip/48" : \"$ip/30"
    );

    my $id = tuwf->dbVali('INSERT INTO users', {username => $data->{username}, ip => $ip}, 'RETURNING id');
    tuwf->dbExeci('INSERT INTO users_shadow', {id => $id, mail => $data->{email}});
    my(undef, $token) = auth->resetpass($data->{email});

    my $body = sprintf
         "Hello %s,"
        ."\n\n"
        ."Someone has registered an account on VNDB.org with your email address. To confirm your registration, follow the link below."
        ."\n\n"
        ."%s"
        ."\n\n"
        ."If you don't remember creating an account on VNDB.org recently, please ignore this e-mail."
        ."\n\n"
        ."vndb.org",
        $data->{username}, tuwf->reqBaseURI()."/$id/setpass/$token";

    tuwf->mail($body,
        To => $data->{email},
        From => 'VNDB <noreply@vndb.org>',
        Subject => "Confirm registration for $data->{username}",
    );
    elm_Success
};

1;
