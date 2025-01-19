package VNWeb::Misc::Changes;

use VNWeb::Prelude;


# [ 0:date, 1:id, 2:raw, 3:html ]
# Also used by Misc::HomePage.
sub changes {
    state $log = do {
        my @log;
        open my $F, '<:utf8', config->{root}.'/changes.log';
        while (<$F>) {
            chomp;
            next if /^\s*#/;
            if (/^([0-9]+)(.*)/) {
                push @log, [ $1, undef, $2 ];
            } elsif (/^\s+(.+)/) {
                $log[$#log][2] .= "\n$1";
            } else {
                die "Unknown line in changes.log: $_";
            }
        }
        my($l,$n)=(0,0);
        for (reverse @log) {
            $n = 0 if $l != $_->[0];
            $l = $_->[0];
            $_->[1] = "$_->[0].".++$n;
            $_->[2] =~ s/^\s+//r;
            $_->[3] = bb_format $_->[2];
        }
        \@log;
    }
}

TUWF::get '/changes' => sub {
    framework_ title => 'VNDB Changelog', sub {
        article_ sub {
            h1_ 'VNDB Changelog';
            p_ sub {
                txt_ 'This page lists the recent '; strong_ 'user-visible'; txt_ ' changes to the VNDB website code.';
                br_;
                txt_ 'Changes to the API are not listed here, refer to the '; a_ href => 'https://api.vndb.org/kana#change-log', 'API change log'; txt_ ' instead.';
                br_;
                txt_ 'Changes to the database schema (which affect the ';
                a_ href => '/d14#5', 'public database dumps'; txt_ ' and the ';
                a_ href => 'https://query.vndb.org/about', 'query interface';
                txt_ ') are also not listed here.';
                br_;
                txt_ 'There is often a lot of code refactoring and performance improvement work going on in the backgound; ';
                txt_ "such changes are also not listed here because they're not supposed to be visible, ";
                txt_ 'but sometimes they can unintentionally have user-visible side effects anyway. ';
                txt_ 'The full list of all code changes can be found at the '; a_ href => config->{source_url}, 'source repository'; txt_ '.';
            };
        };
        article_ class => 'browse', sub {
            table_ class => 'stripe', sub {
                tr_ id => $_->[1], sub {
                    td_ class => 'tc1 nowrap', style => 'width: 110px', sub {
                        a_ href => "#$_->[1]", sub { rdate_ $_->[0] }
                    };
                    td_ sub { lit_ $_->[3] };
                } for changes->@*;
            }
        };
    };
};

1;
