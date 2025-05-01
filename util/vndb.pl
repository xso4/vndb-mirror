#!/usr/bin/perl

use v5.36;

use Cwd 'abs_path';
our $ROOT;
BEGIN {
    $ROOT = abs_path($0) =~ s{/util/vndb\.pl$}{}r;
    $ENV{TZ} = 'UTC';
    # Force the pure-perl AnyEvent backend; More lightweight and we don't need the
    # performance of EV.
    $ENV{PERL_ANYEVENT_MODEL} = 'Perl';
}
use lib $ROOT.'/lib';
use VNDB::Config;
use FU::Log;

# Set debug & log config before importing FU, so the supervisor uses the right config
BEGIN {
    $ENV{FU_DEBUG} = 1 if config->{debug};
    FU::Log::set_file(config->{logfile}) if config->{logfile};
}

use FU -spawn, -procname => config->{moe} ? 'vndb-moe' : config->{api} eq 'only' ? 'vndb-api' : !config->{api} ? 'vndb-web' : 'vndb';
use FU::XMLWriter ':html5_';
use FU::Pg;
use VNWeb::Auth;
use VNWeb::HTML ();
use VNWeb::Validation ();
use VNWeb::TitlePrefs ();
use VNWeb::TimeZone ();

FU::debug_info(config->{fu_debug_path}, config->{var_path}.'/tmp');

FU::log_slow_reqs(config->{log_slow_pages}) if config->{log_slow_pages};
FU::Log::set_fmt(sub($msg) {
    FU::Log::default_fmt($msg,
        fu->{auth} ? auth->uid : '-',
        fu->path && fu->method ? fu->method.' '.fu->path.(fu->query?'?'.fu->query:'') : '[global]',
    );
});


FU::monitor_path 'changes.log', map config->{gen_path}.'/'.$_, qw/static api-kana.html api-nyan.html abc/;
FU::monitor_check {
    my $out = `make -j4 2>&1` =~ s/make: Nothing to be done for 'all'\.//r =~ s/^\s*//r =~ s/\s*$//r;
    print "$out\n" if $out;
    0;
};


FU::init_db sub {
    my $db = FU::Pg->connect(config->{db_site}//'');
    $db->set_type(date => '$date_str');
    $db->exec(sprintf 'SET statement_timeout = %d', config->{statement_timeout}*1000) if config->{statement_timeout};
    $db->exec('SET search_path TO moe, public') if config->{moe};
    $db;
};



FU::before_request {
    return if VNWeb::Validation::is_api;

    # Serve static files from www/
    my $id = $FU::REQ->{trace_id};
    delete $FU::REQ->{trace_id};
    fu->set_header('cache-control', 'max-age=86400');
    fu->send_file(config->{var_path}.'/www', fu->path);

    # If we're running standalone, serve static/ too.
    if(!$FU::REQ->{fcgi}) {
        fu->send_file(config->{var_path}.'/static', fu->path);
        fu->send_file(config->{gen_path}.'/static', fu->path);
        fu->send_file("$ROOT/static", fu->path);
    }
    fu->reset;
    $FU::REQ->{trace_id} = $id;

    # Use a 'SameSite=Strict' cookie to determine whether this page was loaded from internal or external.
    # Ought to be more reliable than checking the Referer header, but it's unfortunately a bit uglier.
    fu->set_cookie(config->{cookie_prefix}.'samesite' => 1, config->{cookie_defaults}->%*, httponly => 1, samesite => 'Strict')
        if !VNWeb::Validation::samesite && !fu->header('sec-fetch-site');
} if config->{api} ne 'only';


# Provide a default /robots.txt
FU::get '/robots.txt', sub {
    fu->set_header('content-type', 'text/plain');
    fu->set_body("User-agent: *\nDisallow: /\n");
};


FU::on_error 400 => sub {
    VNWeb::API::err(400, 'Invalid request (most likely: invalid JSON or non-UTF8 data).') if VNWeb::Validation::is_api;
    fu->_error_page(400, '400 - Bad Request', 'The server was not happy with your offer.');
};

FU::on_error 403 => sub {
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
};

FU::on_error 404 => sub {
    VNWeb::API::err(404, 'Not found.') if VNWeb::Validation::is_api;
    fu->status(404);
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

FU::on_error 500 => sub {
    VNWeb::API::err(500, 'Internal server error. Can be temporary, but usually points to a server bug.') if VNWeb::Validation::is_api;
    FU::_err_500;
};


if(config->{api} eq 'only') {
    require VNWeb::API;
} else {
    require $_ =~ s{^\Q$ROOT\E/lib/}{}r for (glob("$ROOT/lib/VNWeb/*.pm"), glob("$ROOT/lib/VNWeb/*/*.pm"));
}

FU::run;
