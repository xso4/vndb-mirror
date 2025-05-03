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


# Registration throttle is also used for email address changes in User::Edit.
sub throttle {
    my $ip = norm_ip fu->ip;
    my $tm = fu->sql('SELECT greatest(timeout, now()) FROM registration_throttle WHERE ip = $1', $ip)->val || time;
    return 1 if $tm-time() > 24*3600;
    my $upd = { ip => $ip, timeout => $tm + 24*3600 };
    fu->SQL('INSERT INTO registration_throttle', VALUES($upd), 'ON CONFLICT (ip) DO UPDATE', SET $upd)->exec;
    return 0;
}


js_api UserRegister => {
    username => { username => 1 },
    email    => { email => 1 },
}, sub($data) {
    return 'Registration disabled.' if global_settings->{lockdown_registration};

    return +{ err => 'username' } if !is_unique_username $data->{username};

    # Throttle before checking for duplicate email, wouldn't want to be sending too many emails.
    return 'You can only register one account from the same IP within 24 hours.' if throttle;

    return 'Registration disabled for the given email address.'
        if fu->sql('SELECT email_optout_check($1)', $data->{email})->val;

    # Check for duplicate email
    my $dupe = fu->sql('SELECT u.username FROM users u, user_emailtoid($1) x(id) WHERE x.id = u.id', $data->{email})->val;
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

    my $id = fu->sql('INSERT INTO users (username) VALUES ($1) RETURNING id', $data->{username})->val;
    fu->sql('INSERT INTO users_prefs (id) VALUES ($1)', $id)->exec;
    fu->sql('INSERT INTO users_shadow (id, ip, mail) VALUES ($1, $2::text::ipinfo, $3)', $id, ipinfo, $data->{email})->exec;

    my(undef, undef, $token) = auth->resetpass($data->{email});
    VNWeb::Validation::sendmail(
         "Hello $data->{username},"
        ."\n"
        ."\nSomeone has registered an account on VNDB.org with your email address. To confirm your registration, follow the link below."
        ."\n"
        ."\n".config->{url}."/$id/setpass/".bin2hex($token)
        ."\n"
        ."\nIf you don't remember creating an account on VNDB.org recently, please ignore this e-mail."
        ."\n"
        ."\nvndb.org",
        To => $data->{email},
        Subject => "Confirm registration for $data->{username}",
    );
    +{ ok => 1 }
};

1;
