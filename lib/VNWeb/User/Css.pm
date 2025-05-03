package VNWeb::User::Css;

use VNWeb::Prelude;


sub _sanitize_css {
    # This function is attempting to do the impossible: Sanitize user provided
    # CSS against various attacks.  I'm not expecting this to be bullet-proof.
    # Fortunately, we also have CSP in place to mitigate some problems if they
    # arise, but I'd rather not rely on it.  I'd *love* to disable support for
    # external url()'s, but unfortunately many people use that to load images.
    # I'm afraid the only way to work around that is to fetch and cache those
    # URLs on the server.
    local $_ = $_[0];
    s/\\//g; # Get rid of backslashes, could be used to bypass the other regexes.
    s/@(import|charset|font-face)[^\n\;]*.//ig;
    s/javascript\s*://ig; # Not sure 'javascript:' URLs do anything, but just in case.
    s/expression\s*\(//ig; # An old IE thing I guess.
    s/binding\s*://ig; # Definitely don't want bindings.
    $_;
}


FU::get qr{/$RE{uid}\.css}, sub($uid) {
    my $u = fu->sql('
        SELECT u.id, pubskin_can, pubskin_enabled, customcss
          FROM users u
          JOIN users_prefs up ON up.id = u.id
         WHERE u.id = $1', $uid
    )->rowh;
    fu->notfound if !$u->{id};
    fu->denied if !($u->{pubskin_can} && $u->{pubskin_enabled}) && !(auth && auth->uid eq $u->{id});
    fu->set_header('content-type', 'text/css');
    fu->set_header('cache-control', 'max-age=31536000'); # invalidation is done by adding a checksum to the URL.
    my $body = _sanitize_css $u->{customcss};
    utf8::encode($body);
    fu->set_body($body);
};

1;
