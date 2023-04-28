package VNWeb::Misc::Lockdown;

use VNWeb::Prelude;

TUWF::get '/lockdown', sub {
    return tuwf->resDenied if !auth->isMod;

    sub chk_ {
        my($name, $lbl) = @_;
        label_ sub {
            input_ type => 'checkbox', name => $name, global_settings->{$name} ? (checked => 'checked') : ();
            txt_ $lbl;
        };
        br_;
    }

    framework_ title => 'Database lockdown', sub {
        article_ sub {
            h1_ 'Database lockdown';

            p_ sub {
                txt_ 'This form provides a sledghehammer approach to dealing with
                targeted vandalism or spam attacks on the site. The goal of
                these options is to put the website in a temporary lockdown
                while waiting for Yorhel to wake up or while a better solution
                is being worked on.';
                br_;
                txt_ 'Moderators can keep using the site as usual regardless of these settings.';
            };

            form_ action => '/lockdown', method => 'post', style => 'margin: 20px', sub {
                chk_ lockdown_registration => ' Disable account creation.';
                chk_ lockdown_edit => ' Disable database editing globally. Also disables image and tag voting.';
                chk_ lockdown_board => ' Disable forum and review posting globally.';
                input_ type => 'submit', name => 'submit', class => 'submit', value => 'Submit';
            };
        };
    };
};


TUWF::post '/lockdown', sub {
    return auth->resDenied if !auth->isMod || !samesite;
    my $frm = tuwf->validate(post =>
        lockdown_registration => { anybool => 1 },
        lockdown_edit         => { anybool => 1 },
        lockdown_board        => { anybool => 1 },
    )->data;
    tuwf->dbExeci('UPDATE global_settings SET', $frm);
    auth->audit(0, 'lockdown', JSON::XS->new->encode($frm));
    tuwf->resRedirect('/lockdown', 'post');
};

1;
