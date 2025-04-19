#!/usr/bin/perl

use v5.36;
use Cwd 'abs_path';
use JSON::XS;
use TUWF;
use Time::HiRes 'time';
use FU::XMLWriter ':html5_';

$|=1; # Disable buffering on STDOUT, otherwise vndb-dev-server.pl won't pick up our readyness notification.

# Force the pure-perl AnyEvent backend; More lightweight and we don't need the
# performance of EV. Fixes an issue with subprocess spawning under TUWF's
# built-in web server that I haven't been able to track down.
BEGIN { $ENV{PERL_ANYEVENT_MODEL} = 'Perl'; }

our $ROOT;
BEGIN { ($ROOT = abs_path $0) =~ s{/util/vndb\.pl$}{} }

use lib $ROOT.'/lib';
use VNDB::Config;
use VNWeb::Auth;
use VNWeb::HTML ();
use VNWeb::Validation ();
use VNWeb::TitlePrefs ();
use VNWeb::TimeZone ();

$ENV{TZ} = 'UTC';
TUWF::set %{ config->{tuwf} };
TUWF::set import_modules => 0;
TUWF::set db_login => sub {
    DBI->connect(config->{tuwf}{db_login}->@*, { PrintError => 0, RaiseError => 1, AutoCommit => 0, pg_enable_utf8 => 1, ReadOnly => 1 })
} if config->{read_only};


TUWF::hook before => sub {
    return if VNWeb::Validation::is_api;

    # Serve static files from www/
    if(tuwf->resFile(config->{var_path}.'/www', tuwf->reqPath)) {
        tuwf->resHeader('Cache-Control' => 'max-age=86400');
        tuwf->done;
    }

    # If we're running standalone, serve static/ too.
    if(tuwf->{_TUWF}{http} && (
            tuwf->resFile(config->{var_path}.'/static', tuwf->reqPath) ||
            tuwf->resFile(config->{gen_path}.'/static', tuwf->reqPath) ||
            tuwf->resFile("$ROOT/static", tuwf->reqPath)
    )) {
        tuwf->resHeader('Cache-Control' => 'max-age=31536000');
        tuwf->done;
    }

    # Load the 'moe' schema if we're in moe mode
    tuwf->dbExeci('SET search_path TO moe, public') if config->{moe};

    # Use a 'SameSite=Strict' cookie to determine whether this page was loaded from internal or external.
    # Ought to be more reliable than checking the Referer header, but it's unfortunately a bit uglier.
    tuwf->resCookie(samesite => 1, httponly => 1, samesite => 'Strict')
        if !VNWeb::Validation::samesite && !tuwf->reqHeader('sec-fetch-site');

    tuwf->req->{trace_start} = time if config->{trace_log};
} if config->{api} ne 'only';


# Provide a default /robots.txt
TUWF::get '/robots.txt', sub {
    tuwf->resHeader('Content-Type' => 'text/plain');
    tuwf->resBinary("User-agent: *\nDisallow: /\n");
};


TUWF::set error_400_handler => sub {
    return eval { VNWeb::API::err(400, 'Invalid request (most likely: invalid JSON or non-UTF8 data).') } if VNWeb::Validation::is_api;
    TUWF::_error_400();
};

TUWF::set error_404_handler => sub {
    return eval { VNWeb::API::err(404, 'Not found.') } if VNWeb::Validation::is_api;
    tuwf->resStatus(404);
    VNWeb::HTML::framework_ title => 'Page Not Found', noindex => 1, sub {
        article_ sub {
            h1_ 'Page not found';
            div_ class => 'warning', sub {
                h2_ 'Oops!';
                p_ sub {
                    txt_ 'It seems the page you were looking for does not exist,';
                    br_;
                    txt_ 'you may want to try using the menu on your left to find what you are looking for.';
                };
            }
        }
    }
};

TUWF::set error_500_handler => sub {
    return eval { VNWeb::API::err(500, 'Internal server error. Can be temporary, but usually points to a server bug.') } if VNWeb::Validation::is_api;
    TUWF::_error_500();
};


sub TUWF::Object::resDenied {
    tuwf->resStatus(403);
    VNWeb::HTML::framework_ title => 'Access Denied', noindex => 1, sub {
        article_ sub {
            h1_ 'Access Denied';
            div_ class => 'warning', sub {
                if(!auth) {
                    h2_ 'You need to be logged in to perform this action.';
                    p_ sub {
                        txt_ 'Please ';
                        a_ href => '/u/login', 'login';
                        txt_ ' or ';
                        a_ href => '/u/register', 'create an account';
                        txt_ " if you don't have one yet.";
                    }
                } elsif(VNWeb::DB::global_settings()->{lockdown_edit} || VNWeb::DB::global_settings()->{lockdown_board}) {
                    h2_ 'The database is in temporary lockdown.';
                } else {
                    h2_ 'You are not allowed to perform this action.';
                    p_ 'You do not have the proper rights to perform the action you wanted to perform.';
                }
            }
        }
    }
}


# Intercept TUWF::any() to figure out which module is processing the request.
# Used by VNWeb::HTML::framework_ and trace logging.
{
    no warnings 'redefine';
    my $f = \&TUWF::any;
    *TUWF::any = sub($meth, $path, $sub) {
        my $i = 0;
        my $loc = ['',0];
        while(my($pack, undef, $line, undef, undef, undef, undef, $is_require) = caller($i++)) {
            last if $is_require;
            $loc = [$pack,$line];
        }
        $f->($meth, $path, sub { tuwf->req->{trace_loc} = $loc; $sub->(@_) });
    };
}

if(config->{api} eq 'only') {
    require VNWeb::API;
} else {
    TUWF::load_recursive('VNWeb');
}

TUWF::hook after => sub {
    return if rand() > config->{trace_log} || !tuwf->req->{trace_start};
    my $sqlt = List::Util::sum(map $_->[2], tuwf->{_TUWF}{DB}{queries}->@*);
    my %js = (
        (map +("$_.js",1), keys tuwf->req->{js}->%*),
        (map +($_,1), keys tuwf->req->{pagevars}{widget}->%*),
    );
    tuwf->dbExeci('INSERT INTO trace_log', {
        method    => tuwf->reqMethod(),
        path      => tuwf->reqPath(),
        query     => tuwf->reqQuery(),
        module    => tuwf->req->{trace_loc}[0],
        line      => tuwf->req->{trace_loc}[1],
        sql_num   => scalar grep($_->[0] ne 'ping/rollback' && $_->[0] ne 'commit', tuwf->{_TUWF}{DB}{queries}->@*),
        sql_time  => $sqlt,
        perl_time => time() - tuwf->req->{trace_start},
        has_txn   => VNWeb::DB::sql('txid_current_if_assigned() IS NOT NULL'),
        loggedin  => auth?1:0,
        js        => '{'.join(',', sort keys %js).'}'
    });
} if config->{trace_log};

TUWF::run;
