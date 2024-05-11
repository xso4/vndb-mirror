package VNDB::Config;

use v5.36;
use Exporter 'import';
use Cwd 'abs_path';
our @EXPORT = ('config');

my $ROOT = ($INC{'VNDB/Config.pm'} =~ s{lib/VNDB/Config\.pm$}{}r =~ s{/$}{}r) || '.';
my $GEN = abs_path($ENV{VNDB_GEN} // "$ROOT/gen");
my $VAR = abs_path($ENV{VNDB_VAR} // "$ROOT/var");
$ROOT = abs_path $ROOT;

# Default config options
my $config = {
    gen_path          => $GEN,
    var_path          => $VAR,

    url               => 'http://localhost:3000',

    tuwf => {
        db_login      => [ 'dbi:Pg:dbname=vndb', 'vndb_site', undef ],
        cookie_prefix => 'vndb_',
    },

    skin_default      => 'angel',
    placeholder_img   => 'https://s.vndb.org/s/angel-bg.jpg', # Used in the og:image meta tag
    scrypt_args       => [ 65536, 8, 1 ], # N, r, p
    scrypt_salt       => 'another-random-string',
    form_salt         => 'a-private-string-here',
    source_url        => 'https://code.blicky.net/yorhel/vndb',
    admin_email       => 'contact@vndb.org',
    login_throttle    => [ 24*3600/10, 24*3600 ], # interval between attempts, max burst (10 a day)
    reset_throttle    => [ 24*3600/2,  24*3600 ], # interval between attempts, max burst (2 a day)
    board_edit_time   => 7*24*3600, # Time after which posts become immutable
    graphviz_path     => '/usr/bin/dot',
    imgproc_path      => "$GEN/imgproc",
    trace_log         => 0,
    # Put the site in full read-only mode; Login is disabled and nothing is written to the DB. Handy for migrations.
    read_only         => 0,

    location_db       => undef, # Optional path to a libloc database for IP geolocation

    scr_size          => [ 136, 102 ], # w*h of screenshot thumbnails
    ch_size           => [ 256, 300 ], # max. w*h of char images
    cv_size           => [ 256, 400 ], # max. w*h of cover images

    api_throttle      => [ 60, 5 ], # execution time multiplier, allowed burst

    Multi => {
        Core        => {},
        Maintenance => {},
    },
};


my $config_file = -e "$VAR/conf.pl" ? do("$VAR/conf.pl") || die $! : {};
my $config_merged;

sub config {
    $config_merged ||= do {
        my $c = $config;
        $c->{$_} = $config_file->{$_} for grep !/^(Multi|tuwf)$/, keys %$config_file;
        $c->{Multi}{$_} = $config_file->{Multi}{$_} for keys %{ $config_file->{Multi} || {} };
        $c->{tuwf}{$_}  = $config_file->{tuwf}{$_}  for keys %{ $config_file->{tuwf}  || {} };

        $c->{url_static} ||= $c->{url};
        $c->{version} ||= `git -C "$ROOT" describe` =~ s/\-g[0-9a-f]+$//rg =~ s/\r?\n//rg;
        $c->{root} = $ROOT;
        $c->{Multi}{Core}{log_level} ||= 'debug';
        $c->{Multi}{Core}{log_dir}   ||= $VAR.'/log';
        $c
    };
    $config_merged
}

1;

