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


TUWF::get qr{/$RE{uid}\.css}, sub {
    my $u = tuwf->dbRowi('
        SELECT u.id, pubskin_can, pubskin_enabled, customcss
          FROM users u
          JOIN users_prefs up ON up.id = u.id
         WHERE u.id =', \tuwf->capture('id'));
    return tuwf->resNotFound if !$u->{id};
    return tuwf->resDenied if !($u->{pubskin_can} && $u->{pubskin_enabled}) && !(auth && auth->uid eq $u->{id});
    tuwf->resHeader('Content-type', 'text/css; charset=UTF8');
    tuwf->resHeader('Cache-Control', 'max-age=31536000'); # invalidation is done by adding a checksum to the URL.
    lit_ _sanitize_css $u->{customcss};
};

1;
