package VNWeb::User::PassSet;

use VNWeb::Prelude;

my $FORM = {
    uid      => { vndbid => 'u' },
    token    => { regex => qr/[a-f0-9]{40}/ },
    password => { _when => 'in', password => 1 },
};

my $FORM_IN  = form_compile in  => $FORM;
my $FORM_OUT = form_compile out => $FORM;


TUWF::get qr{/$RE{uid}/setpass/(?<token>[a-f0-9]{40})}, sub {
    return tuwf->resRedirect('/', 'temp') if auth;

    my $id = tuwf->capture('id');
    my $token = tuwf->capture('token');
    my $name = tuwf->dbVali('SELECT username FROM users WHERE id =', \$id);

    return tuwf->resNotFound if !$name || !auth->isvalidtoken($id, $token);

    framework_ title => 'Set password', sub {
        elm_ 'User.PassSet', $FORM_OUT, { uid => $id, token => $token };
    };
};


elm_api UserPassSet => $FORM_OUT, $FORM_IN, sub {
    my($data) = @_;

    return elm_InsecurePass if is_insecurepass($data->{password});
    # "CSRF" is kind of wrong here, but the message advices to reload the page,
    # which will give a 404, which should be a good enough indication that the
    # token has expired. This case won't happen often.
    return elm_CSRF if !auth->setpass($data->{uid}, $data->{token}, undef, $data->{password});
    tuwf->dbExeci('UPDATE users SET email_confirmed = true WHERE id =', \$data->{uid});
    auth->audit($data->{uid}, 'password change', 'with email token');
    elm_Success
};

1;
