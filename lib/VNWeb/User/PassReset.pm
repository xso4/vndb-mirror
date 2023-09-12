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

    my($id, $token) = auth->resetpass($data->{email});
    return +{ _err => 'Unknown email address.' } if !$id;

    my $name = tuwf->dbVali('SELECT username FROM users WHERE id =', \$id);
    my $body = sprintf
         "Hello %s,"
        ."\n\n"
        ."You can set a new password for your VNDB.org account by following the link below:"
        ."\n\n"
        ."%s"
        ."\n\n"
        ."Now don't forget your password again! :-)"
        ."\n\n"
        ."vndb.org",
        $name, tuwf->reqBaseURI()."/$id/setpass/$token";

    tuwf->mail($body,
      To => $data->{email},
      From => 'VNDB <noreply@vndb.org>',
      Subject => "Password reset for $name",
    );
    +{}
};

1;
