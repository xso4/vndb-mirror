// @license magnet:?xt=urn:btih:0b31508aeb0634b347b8270c7bee4d411b5d4109&dn=agpl-3.0.txt AGPL-3.0-only
// @source: https://code.blicky.net/yorhel/vndb/src/branch/master/js
// @license magnet:?xt=urn:btih:d3d9a9a6595521f9666a5e94cc830dab83b65699&dn=expat.txt Expat
// @source: https://code.blicky.net/yorhel/mithril-vndb
// SPDX-License-Identifier: AGPL-3.0-only AND Expat

// ^ LibreJS browser plugin only recognizes the first license tag in the file,
// so it's kind of incorrect. Their spec doesn't appear to support bundling.

"use strict";

// Log errors to the server. This intentionally uses old-ish syntax and APIs.
// (though it still won't catch parsing/syntax errors in this bundle...)
window.onerror = function(ev, source, lineno, colno, error) {
    if (/\/(basic|contrib|graph|user)\.js/.test(source)) {
        var h = new XMLHttpRequest();
        var e = encodeURIComponent;
        h.open('POST', '/js-error?2', true);
        h.send('ev='+e(ev)+'&source='+e(source)+'&lineno='+e(lineno)+'&colno='+e(colno)+'&stack='+e(error.stack));
        window.onerror = null; // One error per page is enough
    }
    return false;
};

@include .gen/mithril.js
@include .gen/types.js
@include polyfills.js

// Library stuff
@include utils.js
@include api.js
@include components.js
@include ds.js
@include iv.js

// A bunch of old fashioned DOM manipulation features.
@include checkall.js
@include checkhidden.js
@include mainbox-summarize.js
@include searchtabs.js
@include sethash.js
@include ulist-actiontabs.js
@include ulist-labelfilters.js
@include histoptions.js

// Widgets
@include TableOpts.js

// @license-end
