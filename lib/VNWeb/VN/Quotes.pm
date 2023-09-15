package VNWeb::VN::Quotes;

use VNWeb::Prelude;

TUWF::any ['GET', 'POST'], qr{/$RE{vid}/quotes}, sub {
    my $v = dbobj tuwf->capture(1);
    return tuwf->resNotFound if !$v->{id} || $v->{entry_hidden};

    framework_ title => "Quotes for $v->{title}[1]", dbobj => $v, tab => 'quotes', sub {
        article_ sub {
            h1_ "Quotes for $v->{title}[1]";

            my $lst = tuwf->dbAlli('SELECT quote FROM quotes WHERE approved AND vid =', \$v->{id}, 'ORDER BY quote');
            if (@$lst) {
                h2_ 'Approved quotes';
                ul_ sub {
                    li_ $_->{quote} for @$lst;
                };
            } else {
                p_ 'This VN has no (approved) quotes yet.';
            }
        };
        article_ sub {
            h1_ 'Submit quote';

            if (tuwf->reqMethod eq 'POST') {
                my $quote = tuwf->validate(post => quote => { maxlength => 170 });
                if ($quote->err) {
                    div_ class => 'warning', 'Invalid quote.';
                } else {
                    tuwf->dbExeci('INSERT INTO quotes', {vid => $v->{id}, quote => $quote->data}, 'ON CONFLICT (vid, quote) DO NOTHING');
                    auth->audit(undef, 'submit quote', "$v->{id}: ".$quote->data);
                    div_ class => 'notice', 'Quote submitted!';
                }
            }

            h2_ 'Some rules:';
            ul_ sub {
                li_ 'Quotes must be in English. You can use your own translation.';
                li_ "Quotes must be approved in order to be visible. This process can take a long time and you'll not get any feedback.";
                li_ 'Quotes should be funny and/or insightful out of context.';
                li_ 'Quotes must come from an actual release of the visual novel.';
                li_ 'At most 170 characters per quote, but shorter quotes are preferred.';
                li_ "VNDB's quote list is more of a stupid gimmick than a proper database feature, keep your expectations low and don't go overboard by submitting lots of quotes.";
            };
            form_ method => 'POST', action => "/$v->{id}/quotes", sub {
                fieldset_ class => 'form', sub {
                    fieldset_ sub {
                        input_ type => 'text', class => 'xw', name => 'quote', required => 'required', maxlength => 170;
                    };
                    fieldset_ sub {
                        input_ type => 'submit', value => 'Submit';
                    }
                };
            }
        } if auth->permEdit;
    };
};

1;
