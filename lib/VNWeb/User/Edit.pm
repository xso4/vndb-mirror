package VNWeb::User::Edit;

use VNWeb::Prelude;
use VNDB::Skins;


my $FORM = {
    id             => { vndbid => 'u' },
    title          => { _when => 'out' },
    username       => { username => 1 }, # Can only be modified with perm_usermod

    opts => { _when => 'out', type => 'hash', keys => {
        # Supporter options available to this user
        nodistract_can => { _when => 'out', anybool => 1 },
        support_can    => { _when => 'out', anybool => 1 },
        uniname_can    => { _when => 'out', anybool => 1 },
        pubskin_can    => { _when => 'out', anybool => 1 },

        # Permissions of the user editing this account
        perm_dbmod     => { _when => 'out', anybool => 1 },
        perm_usermod   => { _when => 'out', anybool => 1 },
        perm_tagmod    => { _when => 'out', anybool => 1 },
        perm_boardmod  => { _when => 'out', anybool => 1 },
    } },

    # Settings that require at least one perm_*mod
    admin => { required => 0, type => 'hash', keys => {
        ign_votes => { anybool => 1 },
        map +("perm_$_" => { anybool => 1 }), VNWeb::Auth::listPerms
    } },

    # Settings that can only be read/modified by the user itself or a perm_usermod
    prefs => { required => 0, type => 'hash', keys => {
        email           => { email => 1 },
        max_sexual      => {  int => 1, range => [-1, 2 ] },
        max_violence    => { uint => 1, range => [ 0, 2 ] },
        traits_sexual   => { anybool => 1 },
        tags_all        => { anybool => 1 },
        tags_cont       => { anybool => 1 },
        tags_ero        => { anybool => 1 },
        tags_tech       => { anybool => 1 },
        spoilers        => { uint => 1, range => [ 0, 2 ] },
        skin            => { enum => skins },
        customcss       => { required => 0, default => '', maxlength => 2000 },

        # Supporter options
        nodistract_noads   => { anybool => 1 },
        nodistract_nofancy => { anybool => 1 },
        support_enabled => { anybool => 1 },
        uniname         => { required => 0, default => '', regex => qr/^.{2,15}$/ }, # Use regex to check length, HTML5 `maxlength` attribute counts UTF-16 code units...
        pubskin_enabled => { anybool => 1 },
    } },

    password  => { _when => 'in', required => 0, type => 'hash', keys => {
        old   => { password => 1 },
        new   => { password => 1 }
    } },
};

my $FORM_IN  = form_compile in  => $FORM;
my $FORM_OUT = form_compile out => $FORM;



sub _getmail {
    my $uid = shift;
    tuwf->dbVali(select => sql_func user_getmail => \$uid, \auth->uid, sql_fromhex auth->token);
}

TUWF::get qr{/$RE{uid}/edit}, sub {
    my $u = tuwf->dbRowi('SELECT id, username FROM users WHERE id =', \tuwf->capture('id'));
    return tuwf->resNotFound if !$u->{id} || !can_edit u => $u;

    $u->{opts} = tuwf->dbRowi('SELECT nodistract_can, support_can, uniname_can, pubskin_can FROM users WHERE id =', \$u->{id});
    $u->{opts}{perm_dbmod}    = auth->permDbmod;
    $u->{opts}{perm_usermod}  = auth->permUsermod;
    $u->{opts}{perm_tagmod}   = auth->permTagmod;
    $u->{opts}{perm_boardmod} = auth->permBoardmod;

    $u->{prefs} = $u->{id} eq auth->uid || auth->permUsermod ?
        tuwf->dbRowi(
            'SELECT max_sexual, max_violence, traits_sexual, tags_all, tags_cont, tags_ero, tags_tech, spoilers, skin, customcss
                  , nodistract_noads, nodistract_nofancy, support_enabled, uniname, pubskin_enabled
               FROM users WHERE id =', \$u->{id}
        ) : undef;
    $u->{prefs}{email} = _getmail $u->{id} if $u->{prefs};
    $u->{prefs}{skin} ||= config->{skin_default} if $u->{prefs};

    $u->{admin} = auth->permDbmod || auth->permUsermod || auth->permTagmod || auth->permBoardmod ?
        tuwf->dbRowi('SELECT ign_votes, ', sql_comma(map "perm_$_", auth->listPerms), 'FROM users u JOIN users_shadow us ON us.id = u.id WHERE u.id =', \$u->{id}) : undef;

    $u->{password} = undef;

    $u->{title} = $u->{id} eq auth->uid ? 'My Account' : "Edit $u->{username}";
    framework_ title => $u->{title}, dbobj => $u, tab => 'edit',
    sub {
        elm_ 'User.Edit', $FORM_OUT, $u;
    };
};


elm_api UserEdit => $FORM_OUT, $FORM_IN, sub {
    my $data = shift;

    my $username = tuwf->dbVali('SELECT username FROM users WHERE id =', \$data->{id});
    return tuwf->resNotFound if !$username;
    return elm_Unauth if !can_edit u => $data;

    my $own = $data->{id} eq auth->uid || auth->permUsermod;
    my %set;

    if($own) {
        my $p = $data->{prefs};
        $p->{skin} = '' if $p->{skin} eq config->{skin_default};
        $p->{uniname} = '' if $p->{uniname} eq $username;
        return elm_Taken if $p->{uniname} && tuwf->dbVali('SELECT 1 FROM users WHERE id <>', \$data->{id}, 'AND username =', \lc($p->{uniname}));

        $set{$_} = $p->{$_} for qw/
            max_sexual max_violence traits_sexual tags_all tags_cont tags_ero tags_tech spoilers skin customcss
            nodistract_noads nodistract_nofancy support_enabled uniname pubskin_enabled
        /;
    }

    if(auth->permUsermod) {
        $set{username} = $data->{username};
        $set{ign_votes} = $data->{admin}{ign_votes};
        $set{email_confirmed} = 1;
        tuwf->dbExeci(select => sql_func user_setperm_usermod => \$data->{id}, \auth->uid, sql_fromhex(auth->token), \$data->{admin}{perm_usermod});
        $set{"perm_$_"} = $data->{admin}{"perm_$_"} for grep $_ ne 'usermod', auth->listPerms;
    }
    $set{perm_board}      = $data->{admin}{perm_board}      if auth->permBoardmod;
    $set{perm_review}     = $data->{admin}{perm_review}     if auth->permBoardmod;
    $set{perm_edit}       = $data->{admin}{perm_edit}       if auth->permDbmod;
    $set{perm_imgvote}    = $data->{admin}{perm_imgvote}    if auth->permDbmod;
    $set{perm_lengthvote} = $data->{admin}{perm_lengthvote} if auth->permDbmod;
    $set{perm_tag}        = $data->{admin}{perm_tag}        if auth->permTagmod;

    if($own && $data->{password}) {
        return elm_InsecurePass if is_insecurepass $data->{password}{new};

        my $ok = 1;
        if(auth->uid eq $data->{id}) {
            $ok = 0 if !auth->setpass($data->{id}, undef, $data->{password}{old}, $data->{password}{new});
        } else {
            tuwf->dbExeci(select => sql_func user_admin_setpass => \$data->{id}, \auth->uid,
                sql_fromhex(auth->token), sql_fromhex auth->_preparepass($data->{password}{new})
            );
        }
        auth->audit($data->{id}, $ok ? 'password change' : 'bad password', 'at user edit form');
        return elm_BadCurPass if !$ok;
    }

    my $ret = \&elm_Success;

    my $newmail = $own && $data->{prefs}{email};
    my $oldmail = $own && _getmail $data->{id};
    if($own && $newmail ne $oldmail) {
        return elm_DoubleEmail if tuwf->dbVali('SELECT 1 FROM user_emailtoid(', \$newmail, ') x(id) WHERE id <>', \$data->{id});
        auth->audit($data->{id}, 'email change', "old=$oldmail; new=$newmail");
        if(auth->permUsermod) {
            tuwf->dbExeci(select => sql_func user_admin_setmail => \$data->{id}, \auth->uid, sql_fromhex(auth->token), \$newmail);
        } else {
            my $token = auth->setmail_token($newmail);
            my $body = sprintf
                "Hello %s,"
                ."\n\n"
                ."To confirm that you want to change the email address associated with your VNDB.org account from %s to %s, click the link below:"
                ."\n\n"
                ."%s"
                ."\n\n"
                ."vndb.org",
                $username, $oldmail, $newmail, tuwf->reqBaseURI()."/$data->{id}/setmail/$token";

            tuwf->mail($body,
                To => $newmail,
                From => 'VNDB <noreply@vndb.org>',
                Subject => "Confirm e-mail change for $username",
            );
            $ret = \&elm_MailChange;
        }
    }

    my $old = tuwf->dbRowi('SELECT', sql_comma(keys %set), 'FROM users WHERE id =', \$data->{id});
    tuwf->dbExeci('UPDATE users SET', \%set, 'WHERE id =', \$data->{id});
    my $new = tuwf->dbRowi('SELECT', sql_comma(keys %set), 'FROM users WHERE id =', \$data->{id});

    $_ = JSON::XS->new->allow_nonref->encode($_) for values %$old, %$new;
    my @diff = grep $old->{$_} ne $new->{$_}, keys %set;
    auth->audit($data->{id}, 'user edit', join '; ', map "$_: $old->{$_} -> $new->{$_}", @diff)
        if @diff && (auth->uid ne $data->{id} || grep /^(perm_|ign_votes|username)/, @diff);

    $ret->();
};


TUWF::get qr{/$RE{uid}/setmail/(?<token>[a-f0-9]{40})}, sub {
    my $success = auth->setmail_confirm(tuwf->capture('id'), tuwf->capture('token'));
    my $title = $success ? 'E-mail confirmed' : 'Error confirming email';
    framework_ title => $title, sub {
        div_ class => 'mainbox', sub {
            h1_ $title;
            div_ class => $success ? 'notice' : 'warning', sub {
                p_ "Your e-mail address has been updated!" if $success;
                p_ "Invalid or expired confirmation link." if !$success;
            };
        };
    };
};

1;
