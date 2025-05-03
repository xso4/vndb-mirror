package VNWeb::User::Delete;

use VNWeb::Prelude;


sub _getmail {
    fu->sql('SELECT user_getmail($1, $1, $2)', auth->uid, auth->token)->val;
}

sub set_delete {
    return 0 if fu->method ne 'POST';
    my $pwd = fu->formdata(password => { password => 1, onerror => undef }) // return 1;
    return 1 if !VNWeb::Auth->new->login(auth->uid, $pwd, 1);

    fu->sql('SELECT user_setdelete($1, $2, true)', auth->uid, auth->token)->exec;
    auth->audit(auth->uid, 'mark for deletion');

    my $path = '/'.auth->uid.'/del/'.bin2hex auth->token;
    VNWeb::Validation::sendmail(
        "Hello ".auth->user->{user_name}.","
       ."\n"
       ."\nAs per your request, your account is scheduled for deletion in approximately 7 days."
       ."\nTo view the status of your request or to cancel the deletion, visit the link below before the timer expires:"
       ."\n"
       ."\n".config->{url}.$path
       ."\n"
       ."\nvndb.org",
        To => _getmail(),
        Subject => 'Account deletion for '.auth->user->{user_name},
    );
    fu->redirect(tempget => $path);
}


sub delpage($uid) {
    fu->notfound if !auth || $uid ne auth->uid;

    my $invalid = set_delete;

    framework_ title => 'Account deletion', sub {
        article_ sub {
            h1_ 'Account deletion';
            div_ class => 'warning', 'Account deletion is permanent and your data cannot be restored. Proceed with care!';

            h2_ 'E-mail opt-out';
            p_ sub {
                txt_ 'You can NOT register a new account in the future with the email address associated with this account: ';
                strong_ _getmail;
                txt_ '.';
            };

            my $vns = fu->sql('SELECT COUNT(*) FROM ulist_vns WHERE uid = $1', $uid)->val;
            if ($vns) {
                h2_ 'Visual novel list';
                p_ sub {
                    a_ href => "/$uid/ulist", 'Your visual novel list';
                    txt_ ' will be deleted with your account.';
                };
                p_ sub {
                    txt_ 'Your list currently holds ';
                    strong_ $vns;
                    txt_ ' visual novels, consider making a local backup through the "Export" button before proceeding with the deletion.';
                };
            }

            my $posts = fu->sql('SELECT
                (SELECT COUNT(*)
                   FROM threads_posts tp
                  WHERE hidden IS NULL AND uid = $1
                    AND EXISTS(SELECT 1 FROM threads t WHERE t.id = tp.tid AND NOT t.hidden)
                ) +
                (SELECT COUNT(*) FROM reviews_posts WHERE hidden IS NULL AND uid = $1)', $uid)->val;
            if ($posts) {
                h2_ 'Forum posts';
                p_ sub {
                    a_ href => "/$uid/posts", sub {
                        txt_ 'Your ';
                        strong_ $posts;
                        txt_ ' forum posts';
                    };
                    txt_ ' will remain after your account has been deleted.';
                };
                p_ 'Please send an email to '.config->{admin_email}.' if these contain sensitive information that you wish to have deleted.';
            }

            my $edits = fu->sql('SELECT COUNT(*) FROM changes WHERE requester = $1', $uid)->val;
            if ($edits) {
                h2_ 'Database edits';
                p_ sub {
                    a_ href => "/$uid/hist", sub {
                        txt_ 'Your ';
                        strong_ $edits;
                        txt_ ' database edits';
                    };
                    txt_ ' will remain after your account has been deleted.';
                };
                p_ 'Please send an email to '.config->{admin_email}.' if these contain sensitive information that you wish to have deleted.';
            }

            my $reviews = fu->sql('SELECT COUNT(*) FROM reviews WHERE uid = $1', $uid)->val;
            if ($reviews) {
                h2_ 'Reviews';
                p_ sub {
                    a_ href => "/w?u=$uid", sub {
                        txt_ 'Your ';
                        strong_ $reviews;
                        txt_ ' reviews';
                    };
                    txt_ ' will remain after your account has been deleted.';
                };
                p_ "If you don't want this, make sure to delete the reviews by going through the edit form.";
            }

            my $lengthvotes = fu->sql('SELECT COUNT(*) FROM vn_length_votes WHERE NOT private AND uid = $1', $uid)->val;
            my $imgvotes = fu->sql('SELECT COUNT(*) FROM image_votes WHERE uid = $1', $uid)->val;
            my $tags = fu->sql('SELECT COUNT(*) FROM tags_vn WHERE uid = $1', $uid)->val;
            my $quotes => fu->sql('SELECT COUNT(*) FROM quotes WHERE addedby = $1', $uid)->val;
            if ($lengthvotes || $imgvotes || $tags || $quotes) {
                h2_ 'Misc. database contributions';
                p_ 'Your database contributions will remain after your account has been deleted, these include:';
                ul_ sub {
                    li_ sub { strong_ $lengthvotes; txt_ ' visual novel play times.'; } if $lengthvotes;
                    li_ sub { strong_ $imgvotes; txt_ ' image flagging votes.'; } if $imgvotes;
                    li_ sub { strong_ $tags; txt_ ' visual novel tags.'; } if $tags;
                    li_ sub { strong_ $quotes; txt_ ' visual novel quotes.'; } if $quotes;
                };
            }

            br_;
            h2_ 'Confirm account deletion';
            form_ method => 'POST', class => 'invalid-form', sub {
                fieldset_ class => 'form', sub {
                    fieldset_ sub {
                        label_ for => 'password', 'Password';
                        input_ type => 'password', id => 'password', name => 'password', required => 1, class => 'mw';
                        p_ class => 'invalid', 'Invalid password.' if $invalid;
                    };
                    fieldset_ sub {
                        input_ type => 'submit', value => 'Delete my account';
                        p_ 'Your account will be deleted approximately 7 days after confirmation. You can cancel the deletion before that time.';
                    };
                };
            };
        };
    };
}
FU::get qr{/$RE{uid}/del}, \&delpage;
FU::post qr{/$RE{uid}/del}, \&delpage;


sub delstatus($uid, $token) {
    fu->redirect(temp => '/') if auth && auth->uid ne $uid;

    my $u = fu->SQL('
      SELECT us.delete_at, ', USER, '
           , user_validate_session(u.id,', hex2bin($token), ", 'web') IS DISTINCT FROM NULL AS valid
        FROM users u
        JOIN users_shadow us ON us.id = u.id
       WHERE u.id =", $uid
    )->rowh;

    my $cancelled;
    if (fu->method eq 'POST' && $u && $u->{valid} && $u->{delete_at}) {
        # TODO: Ideally this should just auto-login and redirect, but doing so
        # with the current session token is a bad idea and I'm too lazy to code
        # a session token renewal thing.
        # TODO: This should really invalidate all existing session tokens,
        # given that we could also have reached this page with a fresh token on
        # login.
        fu->sql('SELECT user_setdelete($1, $2, false)', $uid, hex2bin $token)->exec;
        fu->sql('SELECT user_logout($1, $2)', $uid, hex2bin $token)->exec;
        auth->audit($uid, 'cancel deletion');
        $cancelled = 1;
    }

    framework_ title => 'Account deletion', sub {
        article_ $cancelled ? sub {
            h1_ 'Account deletion cancelled';
            p_ sub {
                txt_ 'Your account is no longer scheduled for deletion. You can now ';
                a_ href => '/u/login', 'login to your account again';
                txt_ '.';
            };
        } : !$u ? sub {
            h1_ 'No such user';
            p_ 'No user found with that ID, perhaps the account has been deleted already.';
        } : !$u->{valid} ? sub {
            h1_ 'Invalid token';
        } : !$u->{delete_at} ? sub {
            h1_ 'No account deletion pending';
            p_ 'Your account is not scheduled to be deleted.';
        } : sub {
            h1_ 'Account deletion pending';
            p_ sub {
                my $days = sprintf '%.0f', ($u->{delete_at}-time())/(24*3600);
                txt_ 'Your account is scheduled to be deleted ';
                txt_ $days < 1 ? 'in less than 24 hours.' :
                     $days < 2 ? 'tomorrow.' : "in approximately $days days.";
            };
            form_ method => 'POST', sub {
                p_ sub {
                    input_ type => 'submit', value => 'Cancel account deletion';
                };
            };
        };
    };
}
FU::get qr{/$RE{uid}/del/([a-fA-F0-9]{40})}, \&delstatus;
FU::post qr{/$RE{uid}/del/([a-fA-F0-9]{40})}, \&delstatus;

1;
