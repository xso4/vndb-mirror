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
@include .gen/user.js
@include user/Subscribe.js
@include user/UserLogin.js
@include user/UserEdit.js
@include user/UserRegister.js
@include user/UserPassReset.js
@include user/UserPassSet.js
@include user/UserAdmin.js
@include user/DiscussionReply.js
@include user/ReviewComment.js
@include user/ReviewsVote.js
@include user/QuoteEdit.js
@include user/QuoteVote.js

// @license-end
