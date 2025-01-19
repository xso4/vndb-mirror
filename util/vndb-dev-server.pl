#!/usr/bin/perl

use v5.36;
use AE;
use AnyEvent::Util;
use AnyEvent::Socket;
use AnyEvent::Handle;
use File::Find;
use Time::HiRes 'time';

use Cwd 'abs_path';
(my $ROOT = abs_path $0) =~ s{/util/vndb-dev-server\.pl$}{};

chdir $ROOT;

my $listen_port = $ENV{TUWF_HTTP_SERVER_PORT} || 3000;
$ENV{TUWF_HTTP_SERVER_PORT} = $listen_port+1;

$ENV{VNDB_GEN} //= 'gen';
$ENV{VNDB_VAR} //= 'var';

my($pid, $prog, $killed);

sub prog_start {
    $killed = AE::cv;
    my $started = AE::cv;
    my $output = sub {
        my $d = shift || return;
        if($started && $d =~ /^TUWF::http: You can connect to your server at/) {
            $started->send;
            return;
        }
        print $d;
    };
    $prog = run_cmd 'util/vndb.pl',
        '$$' => \$pid,
        '>'  => $output,
        '2>' => $output;
    $prog->cb(sub {
        $started->send if $started;
        $killed->send;
        $prog = undef;
        $pid = undef;
    });
    $started->recv;
}

sub prog_stop {
    kill 'TERM', $pid if $pid;
    $killed->recv if $killed;
    $prog = undef;
    $pid = undef;
    $killed = undef;
}


sub make_run {
    my $newline = 0;
    my $out = sub {
        my $d = shift||'';
        return if !$d || $d =~ /Nothing to be done for 'all'/;
        print "\n" if !$newline++;
        print $d;
    };
    my $cb = run_cmd 'make -j4', '>', $out, '2>', $out;
    $cb->recv;
    print "\n" if $newline;
}


sub pipe_fhs($a_fh, $b_fh) {
    my($a, $b);
    my $done = AE::cv;
    $done->begin;
    $a = AnyEvent::Handle->new(
        fh => $a_fh,
        on_read => sub { $b->push_write($a->{rbuf}); $a->{rbuf} = '' },
        on_error => sub { if($_[1]) { $b->push_shutdown; $done->end } },
    );
    $done->begin;
    $b = AnyEvent::Handle->new(
        fh => $b_fh,
        on_read => sub { $a->push_write($b->{rbuf}); $b->{rbuf} = '' },
        on_error => sub { if($_[1]) { $a->push_shutdown; $done->end } },
    );
    $done->recv;
}


END { prog_stop; }


my $lastmod = time;
sub checkmod {
    my $newlastmod = 0;
    my $check = sub {
        my $mtime = (stat($_[0]))[9];
        $newlastmod = $mtime if $mtime > $newlastmod;
    };

    find sub {
        $check->($_) if /\.pm$/ && $_ ne 'Multi';
    }, 'lib';
    find sub {
        $check->($_) if /\.js$/;
    }, "$ENV{VNDB_GEN}/static";

    $check->('util/vndb.pl');
    $check->("$ENV{VNDB_VAR}/conf.pl");
    $check->('changes.log');

    my $ismod = $newlastmod > $lastmod;
    $lastmod = $newlastmod;
    return $ismod;
}


my $conn = AE::cv;
my @conn;
tcp_server undef, $listen_port,
    sub { push @conn, shift; $conn->send },
    sub {
        print "VNDB development server running at http://localhost:$listen_port/\n";
        print "\n";
        print "This server will automatically regenerate static assets and\n";
        print "reload itself whenever the VNDB source code has been edited.\n";
        print "Errors and debugging information will be shown in this console.\n";
        print "\n";
    };


my $needcheck = 0;

while(1) {
    $conn->recv;
    my $serv_fh = shift @conn;
    $conn = AE::cv if !@conn;

    # Only check for modifications at most once every 2 seconds, so that assets
    # beloning to the same page view don't cause expensive checks and reloads.
    if($needcheck+2 < time) {
        make_run;
        if(checkmod) {
            print "\nFile has been modified, restarting server.\n\n";
            prog_stop;
            prog_start;
        } elsif(!$prog) {
            prog_start;
        }
        $needcheck = time;
    }
    next if !$prog;

    my $prog_conn = AE::cv;
    tcp_connect '127.0.0.1', $ENV{TUWF_HTTP_SERVER_PORT}, sub { $prog_conn->send(shift); };
    my $prog_fh = $prog_conn->recv || die "Unable to connect to vndb.pl? $!";
    pipe_fhs($serv_fh, $prog_fh);
}
