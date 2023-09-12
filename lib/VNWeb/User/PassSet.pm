package VNWeb::User::PassSet;

use VNWeb::Prelude;

TUWF::get qr{/$RE{uid}/setpass/(?<token>[a-f0-9]{40})}, sub {
    return tuwf->resRedirect('/', 'temp') if auth || config->{read_only};

    my $id = tuwf->capture('id');
    my $token = tuwf->capture('token');
    my $name = tuwf->dbVali('SELECT username FROM users WHERE id =', \$id);

    return tuwf->resNotFound if !$name || !auth->isvalidtoken($id, $token);

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
    return +{ _err => 'Invalid token.' }
        if !auth->setpass($data->{uid}, $data->{token}, undef, $data->{password});
    tuwf->dbExeci('UPDATE users SET email_confirmed = true WHERE id =', \$data->{uid});
    auth->audit($data->{uid}, 'password change', 'with email token');
    +{ _redir => '/' }
};

1;
