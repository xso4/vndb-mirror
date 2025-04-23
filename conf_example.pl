# This file is a Perl script that should return a hashref with config options.
# The full list of available options can be found in lib/VNDB/Config.pm.
{
    # Canonical URL of this site
    url          => 'http://localhost:3000',
    # And of the static files (leave unset to use `url`)
    #url_static   => 'http://localhost:3000',

    # Salt used to generate the CSRF tokens
    form_salt   => '<some unique string>',
    # Global salt used to hash user passwords (used in addition to a user-specific salt)
    scrypt_salt => '<another unique string>',

    # Use the more secure imgproc
    #imgproc_path      => "$main::ROOT/imgproc/imgproc-custom",

    tuwf => {
        db_login        => [ 'dbi:Pg:dbname=vndb', 'vndb_site', 'vndb_site' ],
    },
    debug           => 1,
    cookie_prefix   => 'vndb_',
    cookie_defaults => { domain => 'localhost', path => '/' },
    mail_sendmail   => 'log',

    # Options for Multi, the background server.
    Multi => {
        # Each module in lib/Multi/ can be enabled and configured here.
        Core => {
            db_login => { dbname => 'vndb', user => 'vndb_multi', password => 'vndb_multi' },
        },
        #API => {},
        #IRC => {
        #    nick      => 'MyVNDBBot',
        #    server    => 'irc.synirc.net',
        #    channels  => [ '#vndb' ],
        #    pass      => '<nickserv-password>',
        #    masters   => [ 'yorhel!~Ayo@your.hell' ],
        #},
    },
}
