package VNWeb::User::PassReset;

use VNWeb::Prelude;

FU::get '/u/newpass' => sub {
    fu->redirect(temp => '/') if auth || config->{read_only};
    framework_ title => 'Password reset', sub {
        div_ widget(UserPassReset => {}), '';
    };
};


js_api UserPassReset => {
    email => { email => 1 },
}, sub {
    my $data = shift;

    # Throttle exists to prevent email sending abuse
    my $ip = norm_ip fu->ip;
    my $tm = fu->sql('SELECT greatest(timeout, now()) FROM reset_throttle WHERE ip = $1', $ip)->val || time;
    return 'Too many password reset attempts, try again later.' if $tm-time() > config->{reset_throttle}[1];

    my $upd = {ip => $ip, timeout => $tm + config->{reset_throttle}[0]};
    fu->SQL('INSERT INTO reset_throttle', VALUES($upd), 'ON CONFLICT (ip) DO UPDATE', SET $upd)->exec;

    # Do nothing if the email is blacklisted
    return +{} if fu->sql('SELECT email_optout_check($1)', $data->{email})->val;

    my($id, $mail, $token) = auth->resetpass($data->{email});
    my $name = $id ? fu->sql('SELECT username FROM users WHERE id = $1', $id)->val : $data->{email};
    my $body = $id ?
         "Hello $name,"
        ."\n"
        ."\nYou can set a new password for your VNDB.org account by following the link below:"
        ."\n"
        ."\n".config->{url}."/$id/setpass/".bin2hex($token)
        ."\n"
        ."\nNow don't forget your password again! :-)"
        ."\n"
        ."\nvndb.org"
    :   "Hello,"
       ."\n"
       ."\nSomeone has requested a password reset for the VNDB account associated with this email address."
       ."\nIf this was not done by you, feel free to ignore this email."
       ."\n"
       ."\nThere is no VNDB account associated with this email address, perhaps you used another address to sign up?"
       ."\n"
       ."\nvndb.org";

    VNWeb::Validation::sendmail($body,
        To => $mail // $data->{email},
        Subject => "Password reset for $name",
    );
    +{}
};

1;
