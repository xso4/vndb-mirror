package VNWeb::User::PassReset;

use VNWeb::Prelude;

TUWF::get '/u/newpass' => sub {
    return tuwf->resRedirect('/', 'temp') if auth || config->{read_only};
    framework_ title => 'Password reset', sub {
        div_ widget(UserPassReset => {}), '';
    };
};


js_api UserPassReset => {
    email => { email => 1 },
}, sub {
    my $data = shift;

    # Throttle exists to prevent email sending abuse
    my $ip = norm_ip tuwf->reqIP;
    my $tm = tuwf->dbVali(
        'SELECT', sql_totime('greatest(timeout, now())'), 'FROM reset_throttle WHERE ip =', \$ip
    ) || time;
    return 'Too many password reset attempts, try again later.' if $tm-time() > config->{reset_throttle}[1];

    my $upd = {ip => $ip, timeout => sql_fromtime $tm + config->{reset_throttle}[0]};
    tuwf->dbExeci('INSERT INTO reset_throttle', $upd, 'ON CONFLICT (ip) DO UPDATE SET', $upd);

    my($id, $token) = auth->resetpass($data->{email});
    my $name = $id ? tuwf->dbVali('SELECT username FROM users WHERE id =', \$id) : $data->{email};
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
        $name, tuwf->reqBaseURI()."/$id/setpass/$token"
    :   "Hello,"
       ."\n"
       ."\nSomeone has requested a password reset for the VNDB account associated with this email address."
       ."\nIf this was not done by you, feel free to ignore this email."
       ."\n"
       ."\nThere is no VNDB account associated with this email address, perhaps you used another address to sign up?"
       ."\n"
       ."\nvndb.org";

    tuwf->mail($body,
      To => $data->{email},
      From => 'VNDB <noreply@vndb.org>',
      Subject => "Password reset for $name",
    );
    +{}
};

1;
