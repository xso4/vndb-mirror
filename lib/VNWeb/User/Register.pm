package VNWeb::User::Register;

use VNWeb::Prelude;


TUWF::get '/u/register', sub {
    return tuwf->resRedirect('/', 'temp') if auth;
    framework_ title => 'Register', sub {
        if(global_settings->{lockdown_registration} || config->{read_only}) {
            article_ sub {
                h1_ 'Create an account';
                p_ 'Account registration is temporarily disabled. Try again later.';
            }
        } else {
            div_ widget('UserRegister'), '';
        }
    };
};


js_api UserRegister => {
    username => { username => 1 },
    email    => { email => 1 },
}, sub {
    my $data = shift;
    return 'Registration disabled.' if global_settings->{lockdown_registration};

    return +{ _field => 'username', _err => 'Username already taken' } if !is_unique_username $data->{username};
    return +{ _field => 'email', _err => 'E-Mail address already in use by another account' }
        if tuwf->dbVali('SELECT 1 FROM user_emailtoid(', \$data->{email}, ') x');

    my $ip = tuwf->reqIP;
    return 'You can only register one account from the same IP within 24 hours.'
        if tuwf->dbVali('SELECT 1 FROM registration_throttle WHERE timeout > NOW() AND ip =', \norm_ip($ip));
    my %throttle = (timeout => sql("NOW()+'1 day'::interval"), ip => norm_ip($ip));
    tuwf->dbExeci('INSERT INTO registration_throttle', \%throttle, 'ON CONFLICT (ip) DO UPDATE SET', \%throttle);

    my $id = tuwf->dbVali('INSERT INTO users', {username => $data->{username}}, 'RETURNING id');
    tuwf->dbExeci('INSERT INTO users_prefs', {id => $id});
    tuwf->dbExeci('INSERT INTO users_shadow', {id => $id, ip => ipinfo(), mail => $data->{email}});

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
    +{ ok => 1 }
};

1;
