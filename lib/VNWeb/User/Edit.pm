package VNWeb::User::Edit;

use VNWeb::Prelude;
use VNDB::Skins;
use VNWeb::TitlePrefs '/./';
use VNWeb::TimeZone;

use Digest::SHA 'sha1';


my($FORM_IN, $FORM_OUT) = form_compile 'in', 'out', {
    id             => { vndbid => 'u' },
    username       => { username => 1 },
    username_throttled => { _when => 'out', anybool => 1 },
    email          => { email => 1 },
    password       => { default => undef, type => 'hash', keys => {
        old          => { password => 1 },
        new          => { password => 1 }
    } },

    # Supporter options available to this user
    editor_usermod  => { anybool => 1 },
    nodistract_can  => { _when => 'out', anybool => 1 },
    support_can     => { _when => 'out', anybool => 1 },
    uniname_can     => { _when => 'out', anybool => 1 },
    pubskin_can     => { _when => 'out', anybool => 1 },
    # Supporter options
    nodistract_noads   => { anybool => 1 },
    nodistract_nofancy => { anybool => 1 },
    support_enabled => { anybool => 1 },
    uniname         => { default => '', sl => 1, length => [2,15] },
    pubskin_enabled => { anybool => 1 },

    traits          => { sort_keys => 'tid', maxlength => 100, aoh => {
        tid     => { vndbid => 'i' },
        name    => { _when => 'out' },
        group   => { _when => 'out', default => undef },
    } },

    timezone        => { default => '', enum => \%ZONES },
    max_sexual      => {  int => 1, range => [-1, 2 ] },
    max_violence    => { uint => 1, range => [ 0, 2 ] },
    spoilers        => { uint => 1, range => [ 0, 2 ] },
    titles          => { titleprefs => 1 },
    alttitles       => { titleprefs => 1 },
    tags_all        => { anybool => 1 },
    tags_cont       => { anybool => 1 },
    tags_ero        => { anybool => 1 },
    tags_tech       => { anybool => 1 },
    vnrel_langs     => { default => undef, elems => { enum => \%LANGUAGE }, sort => 'str', unique => 1 },
    vnrel_olang     => { anybool => 1 },
    vnrel_mtl       => { anybool => 1 },
    vnimage         => { uint => 1, range => [0,2] },
    staffed_langs   => { default => undef, elems => { enum => \%LANGUAGE }, sort => 'str', unique => 1 },
    staffed_olang   => { anybool => 1 },
    staffed_unoff   => { anybool => 1 },
    traits_sexual   => { anybool => 1 },
    prodrelexpand   => { anybool => 1 },
    skin            => { enum => skins },
    customcss       => { default => '', maxlength => 256*1024 },
    customcss_csum  => { anybool => 1 },

    tagprefs        => { sort_keys => 'tid', maxlength => 500, aoh => {
        tid     => { vndbid => 'g' },
        spoil   => { default => undef, int => 1, range => [ 0, 3 ] },
        color   => { default => undef, regex => qr/^(standout|grayedout|#[a-fA-F0-9]{6})$/ },
        childs  => { anybool => 1 },
        name    => {},
    } },

    traitprefs      => { sort_keys => 'tid', maxlength => 500, aoh => {
        tid     => { vndbid => 'i' },
        spoil   => { default => undef, int => 1, range => [ 0, 3 ] },
        color   => { default => undef, regex => qr/^(standout|grayedout|#[a-fA-F0-9]{6})$/ },
        childs  => { anybool => 1 },
        name    => {},
        group   => { default => undef },
    } },

    api2            => { maxlength => 64, sort_keys => 'token', aoh => {
        token     => {},
        added     => {},
        lastused  => { default => '' },
        notes     => { default => '', sl => 1, maxlength => 200 },
        listread  => { anybool => 1 },
        listwrite => { anybool => 1 },
        delete    => { anybool => 1 },
    } },
};


sub _getmail($uid) {
    fu->dbVali(select => sql_func user_getmail => \$uid, \auth->uid, sql_fromhex auth->token);
}

sub _namethrottled($uid) {
    !auth->permUsermod && fu->dbVali('SELECT 1 FROM users_username_hist WHERE id =', \$uid, 'AND date > NOW()-\'1 day\'::interval')
}

FU::get qr{/$RE{uid}/edit}, sub($uid) {
    my $u = fu->dbRowi(
        'SELECT u.id, username, max_sexual, max_violence, traits_sexual, tags_all, tags_cont, tags_ero, tags_tech, prodrelexpand
              , vnrel_langs::text[], vnrel_olang, vnrel_mtl, vnimage, staffed_langs::text[], staffed_olang, staffed_unoff
              , spoilers, skin, customcss, customcss_csum, timezone, titles::text
              , nodistract_can, support_can, uniname_can, pubskin_can
              , nodistract_noads, nodistract_nofancy, support_enabled, uniname, pubskin_enabled
           FROM users u JOIN users_prefs up ON up.id = u.id WHERE u.id =', \$uid
    );
    fu->notfound if !$u->{id} || !can_edit u => $u;

    $u->{editor_usermod}     = $u->{id} ne auth->uid;
    $u->{username_throttled} = _namethrottled $u->{id};
    $u->{email}              = _getmail $u->{id};
    $u->{password}           = undef;

    $u->{traits} = fu->dbAlli('SELECT u.tid, t.name, g.name AS "group" FROM users_traits u JOIN traits t ON t.id = u.tid LEFT JOIN traits g ON g.id = t.gid WHERE u.id =', \$u->{id}, 'ORDER BY g.gorder, t.name');
    $u->{timezone} ||= 'UTC';
    @{$u}{'titles','alttitles'} = @{ titleprefs_parse($u->{titles}) // $DEFAULT_TITLE_PREFS };
    $u->{skin} ||= config->{skin_default};

    $u->{tagprefs} = fu->dbAlli('SELECT u.tid, u.spoil, u.color, u.childs, t.name FROM users_prefs_tags u JOIN tags t ON t.id = u.tid WHERE u.id =', \$u->{id}, 'ORDER BY t.name');
    $u->{traitprefs} = fu->dbAlli('SELECT u.tid, u.spoil, u.color, u.childs, t.name, g.name as "group" FROM users_prefs_traits u JOIN traits t ON t.id = u.tid LEFT JOIN traits g ON g.id = t.gid WHERE u.id =', \$u->{id}, 'ORDER BY g.gorder, t.name');

    $u->{api2} = auth->api2_tokens($u->{id});

    my $title = $u->{id} eq auth->uid ? 'My Account' : "Edit $u->{username}";
    framework_ title => $title, dbobj => $u, tab => 'edit',
    sub {
        article_ sub {
            h1_ $title;
        };
        div_ widget(UserEdit => $FORM_OUT, $u), '';
    };
};


js_api UserEdit => $FORM_IN, sub($data) {
    my $u = fu->dbRowi('SELECT id, username FROM users WHERE id =', \$data->{id});
    fu->notfound if !$u->{id};
    fu->denied if !can_edit u => $u;

    my(%set, %setp);

    $data->{uniname} = '' if $data->{uniname} eq $u->{username};
    return +{ code => 'uniname', _err => 'Display name already taken.' }
        if $data->{uniname} && fu->dbVali('SELECT 1 FROM users WHERE id <>', \$data->{id}, 'AND lower(username) =', \lc($data->{uniname}));

    $data->{skin} = '' if $data->{skin} eq config->{skin_default};
    $data->{timezone} = '' if $data->{timezone} eq 'UTC';
    $data->{titles} = titleprefs_fmt [ $data->{titles}, delete $data->{alttitles} ];
    $data->{titles} = undef if $data->{titles} eq titleprefs_fmt $DEFAULT_TITLE_PREFS;

    $data->{vnrel_langs}    = !$data->{vnrel_langs} || $data->{vnrel_langs}->@* == keys %LANGUAGE ? undef : '{'.join(',',$data->{vnrel_langs}->@*).'}';
    $data->{staffed_langs}  = !$data->{staffed_langs} || $data->{staffed_langs}->@* == keys %LANGUAGE ? undef : '{'.join(',',$data->{staffed_langs}->@*).'}';

    $set{$_} = $data->{$_} for qw/nodistract_noads nodistract_nofancy support_enabled uniname pubskin_enabled/;
    $setp{$_} = $data->{$_} for qw/
        tags_all tags_cont tags_ero tags_tech
        vnrel_langs vnrel_olang vnrel_mtl vnimage staffed_langs staffed_olang staffed_unoff
        skin customcss timezone max_sexual max_violence spoilers traits_sexual prodrelexpand titles
    /;
    $setp{customcss_csum} = $data->{customcss_csum} && length $data->{customcss} ? unpack 'q', sha1 do { utf8::encode(local $_=$data->{customcss}); $_ } : 0;

    if($data->{username} ne $u->{username}) {
        return +{ _err => 'You can only change your username once a day.' } if _namethrottled $data->{id};
        return +{ code => 'username_taken', _err => 'Username already taken.' } if !is_unique_username $data->{username}, $data->{id};
        $set{username} = $data->{username};
        auth->audit($data->{id}, 'username change', "old=$u->{username}; new=$data->{username}");
        fu->dbExeci('INSERT INTO users_username_hist', { id => $data->{id}, old => $u->{username}, new => $data->{username} });
    }

    if($data->{password}) {
        return +{ code => 'npass', _err => 'Your new password is in a public database of leaked passwords, please choose a different password.' }
            if is_insecurepass $data->{password}{new};
        my $ok = auth->setpass($data->{id}, undef, $data->{password}{old}, $data->{password}{new});
        auth->audit($data->{id}, $ok ? 'password change' : 'bad password', 'at user edit form');
        return +{ code => 'opass', _err => 'Incorrect password' } if !$ok;
    }

    my $ret = {ok=>1};

    my $oldmail = _getmail $data->{id};
    if ($oldmail ne $data->{email}) {
        my $other = fu->dbVali('SELECT u.username FROM users u, user_emailtoid(', \$data->{email}, ') x(id) WHERE u.id = x.id AND x.id <>', \$data->{id});
        if (VNWeb::User::Register::throttle()) {
            return 'You may only change your email address once a day.';
        } elsif (length $other) {
            VNWeb::Validation::sendmail(
                "Hello $other,"
                ."\n"
                ."\nAnother user on VNDB.org has attempted to change their email address to yours."
                ."\nThis is a reminder that you already have an account with this address: $other."
                ."\n"
                ."\nIf you have no idea why you're getting this mail, get in touch with contact\@vndb.org."
                ."\n"
                ."\nvndb.org",
                To => $data->{email},
                Subject => "E-mail change attempt",
            );
            auth->audit($data->{id}, 'email change attempt to other user', "new=$data->{email}");
            $ret = {email=>1};
        } elsif (fu->dbVali('SELECT email_optout_check(', \$data->{email}, ')')) {
            auth->audit($data->{id}, 'email change attempt to blacklist', "new=$data->{email}");
            return 'Registration disabled for the given email address';
        } elsif ($data->{id} ne auth->uid) {
            auth->audit($data->{id}, 'email change', "old=$oldmail; new=$data->{email}");
            fu->dbExeci(select => sql_func user_admin_setmail => \$data->{id}, \auth->uid, sql_fromhex(auth->token), \$data->{email});
            $set{email_confirmed} = 1;
        } else {
            auth->audit($data->{id}, 'email change request', "old=$oldmail; new=$data->{email}");
            my $token = auth->setmail_token($data->{email});
            VNWeb::Validation::sendmail(
                "Hello $u->{username},"
                ."\n"
                ."\nTo confirm that you want to change the email address associated with your VNDB.org account from $oldmail to $data->{email}, click the link below:"
                ."\n"
                ."\n".config->{url}."/$data->{id}/setmail/$token"
                ."\n"
                ."\nvndb.org",
                To => $data->{email},
                Subject => "Confirm e-mail change for $u->{username}",
            );
            $ret = {email=>1};
        }
    }

    fu->dbExeci('DELETE FROM users_traits WHERE id =', \$data->{id});
    fu->dbExeci('INSERT INTO users_traits', { id => $data->{id}, tid => $_->{tid} }) for $data->{traits}->@*;

    fu->dbExeci('DELETE FROM users_prefs_tags WHERE id =', \$data->{id});
    fu->dbExeci('INSERT INTO users_prefs_tags', { id => $data->{id}, %{$_}{qw|tid spoil color childs|} }) for $data->{tagprefs}->@*;

    fu->dbExeci('DELETE FROM users_prefs_traits WHERE id =', \$data->{id});
    fu->dbExeci('INSERT INTO users_prefs_traits', { id => $data->{id}, %{$_}{qw|tid spoil color childs|} }) for $data->{traitprefs}->@*;

    my %tokens = map +($_->{token},$_), $data->{api2}->@*;
    for (auth->api2_tokens($data->{id})->@*) {
        my $t = $tokens{$_->{token}} // next;
        $t->{listwrite} = 0 if !$t->{listread};
        if($t->{delete}) {
            auth->api2_del_token($data->{id}, $t->{token});
        } elsif($t->{notes} ne $_->{notes}
                || !$t->{listread} ne !$_->{listread}
                || !$t->{listwrite} ne !$_->{listwrite}) {
            auth->api2_set_token($data->{id}, %$t);
        }
    }

    my $old = fu->dbRowi('SELECT', sql_comma(keys %set, keys %setp), 'FROM users u JOIN users_prefs up ON up.id = u.id WHERE u.id =', \$data->{id});
    fu->dbExeci('UPDATE users SET', \%set, 'WHERE id =', \$data->{id}) if keys %set;
    fu->dbExeci('UPDATE users_prefs SET', \%setp, 'WHERE id =', \$data->{id}) if keys %setp;
    my $new = fu->dbRowi('SELECT', sql_comma(keys %set, keys %setp), 'FROM users u JOIN users_prefs up ON up.id = u.id WHERE u.id =', \$data->{id});

    if (auth->uid ne $data->{id}) {
        $_ = FU::Util::json_format($_) for values %$old, %$new;
        my @diff = grep $old->{$_} ne $new->{$_}, keys %set, keys %setp;
        auth->audit($data->{id}, 'user edit', join '; ', map "$_: $old->{$_} -> $new->{$_}", @diff) if @diff;
    }

    return $ret;
};


FU::get qr{/$RE{uid}/setmail/([a-f0-9]{40})}, sub($uid, $token) {
    my $success = auth->setmail_confirm($uid, $token);
    my $title = $success ? 'E-mail confirmed' : 'Error confirming email';
    auth->audit($uid, 'email change confirmed') if $success;
    framework_ title => $title, sub {
        article_ sub {
            h1_ $title;
            div_ class => $success ? 'notice' : 'warning', sub {
                p_ "Your e-mail address has been updated!" if $success;
                p_ "Invalid or expired confirmation link." if !$success;
            };
        };
    };
};


js_api UserApi2New => { id => { vndbid => 'u' }}, sub {
    +{ token => auth->api2_set_token($_[0]{id}), added => strftime '%Y-%m-%d', localtime }
};

1;
