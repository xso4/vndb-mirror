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
    my $tm = fu->dbVali(
        'SELECT', sql_totime('greatest(timeout, now())'), 'FROM reset_throttle WHERE ip =', \$ip
    ) || time;
    return 'Too many password reset attempts, try again later.' if $tm-time() > config->{reset_throttle}[1];

    my $upd = {ip => $ip, timeout => sql_fromtime $tm + config->{reset_throttle}[0]};
    fu->dbExeci('INSERT INTO reset_throttle', $upd, 'ON CONFLICT (ip) DO UPDATE SET', $upd);

    # Do nothing if the email is blacklisted
    return +{} if fu->dbVali('SELECT email_optout_check(', \$data->{email}, ')');

    my($id, $mail, $token) = auth->resetpass($data->{email});
    my $name = $id ? fu->dbVali('SELECT username FROM users WHERE id =', \$id) : $data->{email};
    my $body = $id ? sprintf
         "Hello %s,"
        ."\n"
        ."\nYou can set a new password for your VNDB.org account by following the link below:"
        ."\n"
        ."\n%s"
        ."\n"
        ."\nNow don't forget your password again! :-)"
        ."\n"
        ."\nvndb.org",
        $name, config->{url}."/$id/setpass/$token"
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
