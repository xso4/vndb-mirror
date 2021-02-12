package VNWeb::Images::List;

use VNWeb::Prelude;


sub graph_ {
    my($i, $opt) = @_;
    my($gw, $go) = (150, 40); # histogram width, x offset

    sub clamp { $_[0] > $_[2] ? $_[0] : $_[1] < $_[2] ? $_[1] : $_[2] }

    my $y;
    my sub line_ {
        my($lbl, $left, $mid, $right) = @_;
        tag_ 'text', x => 0, y => $y+9, $lbl;
        tag_ 'line', class => 'errorbar', x1 => $go+clamp(0, $gw, $left*$gw/2), y1 => $y+5, x2 => $go+clamp(0, $gw, $right*$gw/2), y2 => $y+5, undef;
        tag_ 'rect', width => 5, height => 10, x => $go+clamp(0, $gw-5, $mid*$gw/2-2), y => $y, undef;
        $y += 12;
    }

    my sub subgraph_ {
        my($left, $right, $avg, $stddev, $my, $user) = @_;
        tag_ 'text', x => $go-2,   y => 10, $left;
        tag_ 'text', x => $go+$gw, y => 10, 'text-anchor' => 'end', $right;
        tag_ 'line', class => 'ruler', x1 => $go,       y1 => 12, x2 => $go,       y2 => 46, undef;
        tag_ 'line', class => 'ruler', x1 => $go+$gw/2, y1 => 12, x2 => $go+$gw/2, y2 => 46, undef;
        tag_ 'line', class => 'ruler', x1 => $go+$gw-2, y1 => 12, x2 => $go+$gw-2, y2 => 46, undef;

        $y = 13;
        line_ 'Avg', $avg-$stddev, $avg, $avg+$stddev if defined $avg;
        line_ 'User', $user, $user, $avg if defined $user;
        line_ 'My', $my, $my, $avg if defined $my && $opt->{u} ne $opt->{u2};
    }

    tag_ 'svg', width => '190px', height => '100px', viewBox => '0 0 190 100', sub {
        tag_ 'g', sub {
            subgraph_ 'Safe', 'Explicit', $i->{c_sexual_avg}, $i->{c_sexual_stddev}, $i->{my_sexual}, $i->{user_sexual}
        };
        tag_ 'g', transform => 'translate(0,51)', sub {
            subgraph_ 'Tame', 'Brutal', $i->{c_violence_avg}, $i->{c_violence_stddev}, $i->{my_violence}, $i->{user_violence}
        };
    };
}


sub listing_ {
    my($lst, $np, $opt, $url) = @_;

    my $view = viewset(show_nsfw => 1);
    paginate_ $url, $opt->{p}, $np, 't';
    div_ class => 'mainbox imagebrowse', sub {
        div_ class => 'imagecard', sub {
            a_ href => "/img/$_->{id}?view=$view", style => 'background-image: url('.imgurl($_->{id}, 1).')', '';
            div_ sub {
                a_ href => "/img/$_->{id}?view=$view", $_->{id};
                txt_ sprintf ' / %d', $_->{c_votecount},;
                b_ class => 'grayedout', sprintf ' / w%.1f', $_->{c_weight};
                br_;
                graph_ $_, $opt;
            };
        } for @$lst;
    };
    paginate_ $url, $opt->{p}, $np, 'b';
}


sub opts_ {
    my($opt, $u) = @_;

    my sub opt_ {
        my($type, $key, $val, $label, $checked) = @_;
        input_ type => $type, name => $key, id => "form_${key}{$val}", value => $val,
            $checked // $opt->{$key} eq $val ? (checked => 'checked') : ();
        label_ for => "form_${key}{$val}", $label;
    };

    form_ sub {
        input_ type => 'hidden', class => 'hidden', name => 'u', value => $opt->{u} if $opt->{u};
        input_ type => 'hidden', class => 'hidden', name => 'u2', value => $opt->{u2} if $opt->{u2} ne (auth->uid||'');
        input_ type => 'hidden', class => 'hidden', name => 'view', value => viewset(show_nsfw => viewget('show_nsfw'));
        table_ style => 'margin: auto', sub {
            tr_ sub {
                td_ 'User:';
                td_ sub { user_ $u };
            } if $u;
            tr_ sub {
                td_ 'Image types:';
                td_ class => 'linkradio', sub {
                    opt_ checkbox => t => 'ch', 'Character images', $opt->{t}->@* == 0 || in ch => $opt->{t}; em_ ' / ';
                    opt_ checkbox => t => 'cv', 'VN images',        $opt->{t}->@* == 0 || in cv => $opt->{t}; em_ ' / ';
                    opt_ checkbox => t => 'sf', 'Screenshots',      $opt->{t}->@* == 0 || in sf => $opt->{t};
                };
            };
            tr_ sub {
                td_ 'Minimum votes:';
                td_ class => 'linkradio', sub { join_ sub { em_ ' / ' }, sub { opt_ radio => m => $_, $_ }, 0..10 };
            };
            tr_ sub {
                td_ '';
                td_ class => 'linkradio', sub { opt_ checkbox => my => 1, 'Only images I voted on' };
            } if auth && $opt->{u} ne $opt->{u2};
            tr_ sub {
                td_ 'Time filter';
                td_ class => 'linkradio', sub {
                    opt_ radio => d => 1,  'Last 24h'; em_ ' / ';
                    opt_ radio => d => 7,  'Last 7d'; em_ ' / ';
                    opt_ radio => d => 30, 'Last 30d'; em_ ' / ';
                    opt_ radio => d => 0,  'Any time';
                }
            } if $opt->{u};
            tr_ sub {
                td_ 'Order by:';
                td_ class => 'linkradio', sub {
                    if($u) {
                        opt_ radio => s => 'date', 'Recent'; em_ ' / ';
                        opt_ radio => s => 'diff', 'Vote difference'; em_ ' / ';
                    }
                    opt_ radio => s => 'weight', 'Weight'; em_ ' / ';
                    opt_ radio => s => 'sdev', 'Sexual stddev'; em_ ' / ';
                    opt_ radio => s => 'vdev', 'Violence stddev';
                }
            };
            tr_ sub {
                td_ '';
                td_ sub { input_ type => 'submit', class => 'submit', value => 'Update' };
            }
        }
    }
}


TUWF::get qr{/img/list}, sub {
    # TODO filters: sexual / violence?
    my $opt = tuwf->validate(get =>
        s  => { onerror => 'date', enum => [qw/ weight sdev vdev date diff/] },
        t  => { onerror => [], scalar => 1, type => 'array', values => { enum => [qw/ ch cv sf /] } },
        m  => { onerror => 0, range => [0,10] },
        d  => { onerror => 0, range => [0,10000] },
        u  => { onerror => '', vndbid => 'u' },
        u2 => { onerror => '', vndbid => 'u' }, # Hidden option, allows comparing two users by overriding the 'My' user.
        my => { anybool => 1 },
        p  => { page => 1 },
    )->data;

    $opt->{u2} ||= auth->uid || '';
    $opt->{s} = 'weight' if !$opt->{u} && ($opt->{s} eq 'date' || $opt->{s} eq 'diff');
    $opt->{t} = [ List::Util::uniq sort $opt->{t}->@* ];
    $opt->{t} = [] if $opt->{t}->@* == 3;
    $opt->{d} = 0 if !$opt->{u};

    my $u = $opt->{u} && tuwf->dbRowi('SELECT id, ', sql_user(), 'FROM users u WHERE id =', \$opt->{u});
    return tuwf->resNotFound if $opt->{u} && !$u->{user_id};

    my $where = sql_and
        $opt->{t}->@* ? sql_or(map sql('i.id BETWEEN vndbid(',\"$_",',1) AND vndbid_max(',\"$_",')'), $opt->{t}->@*) : (),
        $opt->{m} ? sql('i.c_votecount >=', \$opt->{m}) : (),
        $opt->{d} ? sql('iu.date > NOW()-', \"$opt->{d} days", '::interval') : ();

    my($lst, $np) = tuwf->dbPagei({ results => 100, page => $opt->{p} }, '
        SELECT i.id, i.width, i.height, i.c_votecount, i.c_weight
             , i.c_sexual_avg, i.c_sexual_stddev, i.c_violence_avg, i.c_violence_stddev
             , iv.sexual as my_sexual, iv.violence as my_violence',
          $opt->{u} ? ', iu.sexual as user_sexual, iu.violence as user_violence' : (), '
          FROM images i',
          $opt->{u} ? ('JOIN image_votes iu ON iu.uid =', \$opt->{u}, ' AND iu.id = i.id') : (),
          $opt->{my} ? () : 'LEFT', 'JOIN image_votes iv ON iv.uid =', \($opt->{u2}||undef), ' AND iv.id = i.id
         WHERE', $where, '
         ORDER BY', {
             weight => 'i.c_weight DESC',
             sdev   => 'i.c_sexual_stddev DESC NULLS LAST',
             vdev   => 'i.c_violence_stddev DESC NULLS LAST',
             date   => 'iu.date DESC',
             diff   => 'abs(iu.sexual-i.c_sexual_avg) + abs(iu.violence-i.c_violence_avg) DESC',
         }->{$opt->{s}}, ', i.id'
    );

    my sub url { '?'.query_encode %$opt, @_ }

    my $title = $u ? 'Images flagged by '.user_displayname($u) : 'Image browser';

    framework_ title => $title, sub {
        div_ class => 'mainbox', sub {
            h1_ $title;
            opts_ $opt, $u;
        };
        my $nsfw = viewget->{show_nsfw};
        listing_ $lst, $np, $opt, \&url if $nsfw && @$lst;
        div_ class => 'mainbox', sub {
            div_ class => 'warning', sub {
                h2_ 'NSFW Warning';
                p_ sub {
                    txt_ 'This listing contains images that may contain sexual content or violence. ';
                    a_ href => url(view => viewset show_nsfw => 1), 'I understand, show me.';
                    br_;
                    txt_ '(This warning can be disabled in your profile)';
                };
            };
        } if !$nsfw && @$lst;
    };
};

1;
