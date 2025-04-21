package VNWeb::User::Register;

use VNWeb::Prelude;


FU::get '/u/register', sub {
    not_moe;
    fu->redirect(temp => '/') if auth;
    framework_ title => 'Register', sub {
        if(global_settings->{lockdown_registration} || config->{read_only}) {
            article_ sub {
                h1_ 'Create an account';
                p_ 'Account registration is temporarily disabled. Try again later.';
            }
        } else {
            div_ widget('UserRegister', {}), '';
        }
    };
};


js_api UserRegister => {
    username => { username => 1 },
    email    => { email => 1 },
}, sub {
    my $data = shift;
    return 'Registration disabled.' if global_settings->{lockdown_registration};

    return +{ err => 'username' } if !is_unique_username $data->{username};

    # Throttle before checking for duplicate email, wouldn't want to be sending too many emails.
    my $ip = fu->ip;
    return 'You can only register one account from the same IP within 24 hours.'
        if fu->dbVali('SELECT 1 FROM registration_throttle WHERE timeout > NOW() AND ip =', \norm_ip($ip));
    my %throttle = (timeout => sql("NOW()+'1 day'::interval"), ip => norm_ip($ip));
    fu->dbExeci('INSERT INTO registration_throttle', \%throttle, 'ON CONFLICT (ip) DO UPDATE SET', \%throttle);

    # Check for opt-out. Returning 'ok' here sucks balls, but otherwise we'd be vulnerable to email enumeration.
    return +{ ok => 1 } if fu->dbVali('SELECT email_optout_check(', \$data->{email}, ')');

    # Check for duplicate email
    my $dupe = fu->dbVali('SELECT u.username FROM users u, user_emailtoid(', \$data->{email}, ') x(id) WHERE x.id = u.id');
    if (defined $dupe) {
        VNWeb::Validation::sendmail(
             "Hello $data->{username},"
            ."\n"
            ."\nSomeone has attempted to register an account on VNDB.org with your email address,"
            ."\nbut you already have an account on VNDB with the username '$dupe'."
            ."\n"
            ."\nIf you forgot your password, you can recover access to your account through the following link:"
            ."\n".config->{url}."/u/newpass"
            ."\n"
            ."\nIf you don't remember creating an account on VNDB.org recently, please ignore this e-mail."
            ."\n"
            ."\nvndb.org",
            To => $data->{email},
            Subject => "Duplicate registration for $data->{username}",
        );
        return +{ ok => 1 };
    }

    my $id = fu->dbVali('INSERT INTO users', {username => $data->{username}}, 'RETURNING id');
    fu->dbExeci('INSERT INTO users_prefs', {id => $id});
    fu->dbExeci('INSERT INTO users_shadow', {id => $id, ip => ipinfo(), mail => $data->{email}});

    my(undef, undef, $token) = auth->resetpass($data->{email});

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
        $data->{username}, config->{url}."/$id/setpass/$token";

    VNWeb::Validation::sendmail($body,
        To => $data->{email},
        Subject => "Confirm registration for $data->{username}",
    );
    +{ ok => 1 }
};

1;
