package VNWeb::User::Admin;

use VNWeb::Prelude;

my($FORM_IN, $FORM_OUT) = form_compile 'in', 'out', {
    id       => { vndbid => 'u' },
    username => { default => '' },

    # Permissions of the user editing this account
    editor_dbmod     => { _when => 'out', anybool => 1 },
    editor_usermod   => { _when => 'out', anybool => 1 },
    editor_tagmod    => { _when => 'out', anybool => 1 },
    editor_boardmod  => { _when => 'out', anybool => 1 },

    ign_votes => { anybool => 1 },
    map +("perm_$_" => { anybool => 1 }), VNWeb::Auth::listPerms
};

sub _cols {
    auth->permUsermod ? ('ign_votes', map "perm_$_", grep $_ ne 'usermod', auth->listPerms) : (
        auth->permBoardmod ? qw/perm_board perm_review/ : (),
        auth->permDbmod    ? qw/perm_edit perm_imgvote perm_lengthvote/ : (),
        auth->permTagmod   ? qw/perm_tag/ : (),
    );
}

sub _userinfo($id) {
    fu->denied if !auth->isMod;
    fu->sql('
        SELECT u.id, username, '.join(',', _cols).'
          FROM users u
          LEFT JOIN users_shadow us ON us.id = u.id
         WHERE u.id = $1', $id
    )->rowh or fu->notfound;
}


FU::get qr{/$RE{uid}/admin}, sub($id) {
    my $u = _userinfo $id;

    $u->{editor_dbmod}    = auth->permDbmod;
    $u->{editor_usermod}  = auth->permUsermod;
    $u->{editor_tagmod}   = auth->permTagmod;
    $u->{editor_boardmod} = auth->permBoardmod;

    framework_ title => "Admin settings for ".($u->{username}//$u->{id}), dbobj => $u, tab => 'admin',
    sub {
        div_ widget(UserAdmin => $FORM_OUT, $u), '';
    };
};


js_api UserAdmin => $FORM_IN, sub {
    my($data) = @_;
    my $u = _userinfo $data->{id};

    fu->SQL('UPDATE users', SET({ map +($_, $data->{$_}), _cols }), 'WHERE id =', $u->{id})->exec;

    my $new = _userinfo $u->{id};
    my @diff = grep $u->{$_} ne $new->{$_}, _cols;
    auth->audit($data->{id}, 'user admin', join '; ', map "$_: $u->{$_} -> $new->{$_}", @diff) if @diff;
    +{ ok => 1 }
};

1;
