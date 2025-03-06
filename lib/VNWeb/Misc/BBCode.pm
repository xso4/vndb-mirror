package VNWeb::Misc::BBCode;

use VNWeb::Prelude;

js_api BBCode => {
    content => { default => '' }
}, sub {
    +{ html => bb_format bb_subst_links shift->{content} };
};

1;
