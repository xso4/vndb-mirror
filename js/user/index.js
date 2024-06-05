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
@include Subscribe.js
@include UserLogin.js
@include UserEdit.js
@include UserRegister.js
@include UserPassReset.js
@include UserPassSet.js
@include UserAdmin.js
@include DiscussionReply.js
@include PostEdit.js
@include ReviewComment.js
@include ReviewEdit.js
@include ReviewsVote.js
@include QuoteEdit.js
@include QuoteVote.js
@include vn-image-vote.js

// @license-end
