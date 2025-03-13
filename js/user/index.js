// @license magnet:?xt=urn:btih:0b31508aeb0634b347b8270c7bee4d411b5d4109&dn=agpl-3.0.txt AGPL-3.0-only
// @source: https://code.blicky.net/yorhel/vndb/src/branch/master/js
// SPDX-License-Identifier: AGPL-3.0-only
"use strict";

const username_reqs = [
    'Username requirements:', m('br'),
    '- Between 2 and 15 characters long.', m('br'),
    '- Permitted characters: alphabetic, numbers and dash (-).', m('br'),
    '- No spaces, diacritics or fancy Unicode characters.', m('br'),
    '- May not look like a VNDB identifier (i.e. an alphabetic character followed only by numbers).',
];

const EmailInput = initVnode => {
    const domain = v => v.attrs.data[v.attrs.field].split('@')[1] || '';
    const fixdomain = v => domain(v).toLowerCase()
        // The many ways people misspell their email address...
        .replace(/\.c[uoi][nm]?.?$/, '.com') // also matches .c[uio], which are all valid but rare
        .replace(/\.cmo?$/, '.com')
        .replace(/\.om$/, '.com')
        .replace(/\.c.om$/, '.com')
        .replace(/\.co.m$/, '.com')
        .replace(/\.c.m$/, '.com')
        .replace(/^g[nm]?aa?[uio][il]{1,3}\.com$/, 'gmail.com')
        .replace(/^g[nm]aa?[il]{1,3}\.com$/, 'gmail.com')
        .replace(/^gaa?[nm][uio][il]{1,3}\.com$/, 'gmail.com')
        .replace(/^g[nm][uio]a[il]{1,3}\.com$/, 'gmail.com')
        .replace(/^[nm]ga[uio][il]{1,3}\.com$/, 'gmail.com')
        .replace(/^yhoo\.com$/, 'yahoo.com');
    const setfixed = v => v.attrs.data[v.attrs.field] = v.attrs.data[v.attrs.field].replace(domain(v), fixdomain(v));
    return {view: v => [
        m(Input, { type: 'email', ...v.attrs }),
        domain(v) !== fixdomain(v) ? m('span',
            ' Did you mean "@', fixdomain(v), '"? ',
            m('button[type=button]', { onclick: () => setfixed(v) }, 'fix'),
        ) : null,
    ]};
};


@include .gen/user.js
@include Subscribe.js
@include UserLogin.js
@include UserEdit.js
@include UserRegister.js
@include UserPassReset.js
@include UserPassSet.js
@include UserAdmin.js
@include DiscussionReply.js
@include DiscussionEdit.js
@include PostEdit.js
@include ReviewComment.js
@include ReviewEdit.js
@include ReviewsVote.js
@include QuoteEdit.js
@include QuoteVote.js
@include VNLengthVote.js
@include List.js
@include ListManageLabels.js
@include vn-image-vote.js

// @license-end
