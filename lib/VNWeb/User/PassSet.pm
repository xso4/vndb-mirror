package VNWeb::User::PassSet;

use VNWeb::Prelude;

FU::get qr{/$RE{uid}/setpass/([a-f0-9]{40})}, sub($id, $token) {
    fu->redirect(temp => '/') if auth || config->{read_only};

    my $name = fu->sql('SELECT username FROM users WHERE id = $1', $id)->val;
    fu->notfound if !$name || !auth->isvalidtoken($id, hex2bin $token);

    framework_ title => 'Set password', sub {
        div_ widget(UserPassSet => { uid => $id, token => $token }), '';
    };
};


js_api UserPassSet => {
    uid      => { vndbid => 'u' },
    token    => { regex => qr/^[a-f0-9]{40}$/ },
    password => { password => 1 },
}, sub {
    my($data) = @_;

    return +{ insecure => 1, _err => 'Your new password is in a public database of leaked passwords, please choose a different password.' }
        if is_insecurepass($data->{password});
    return 'Invalid token.' if !auth->setpass($data->{uid}, hex2bin($data->{token}), undef, $data->{password});
    fu->sql('UPDATE users SET email_confirmed = true WHERE id = $1', $data->{uid})->exec;
    auth->audit($data->{uid}, 'password change', 'with email token');
    +{ _redir => '/' }
};

1;
