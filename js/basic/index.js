// @license magnet:?xt=urn:btih:0b31508aeb0634b347b8270c7bee4d411b5d4109&dn=agpl-3.0.txt AGPL-3.0-only
// @source: https://code.blicky.net/yorhel/vndb/src/branch/master/js
// @license magnet:?xt=urn:btih:d3d9a9a6595521f9666a5e94cc830dab83b65699&dn=expat.txt Expat
// @source: https://code.blicky.net/yorhel/mithril-vndb
// SPDX-License-Identifier: AGPL-3.0-only AND Expat

// ^ LibreJS browser plugin only recognizes the first license tag in the file,
// so it's kind of incorrect. Their spec doesn't appear to support bundling.

"use strict";

// Log errors to the server. This intentionally uses old-ish syntax and APIs.
window.onerror = function(ev, source, lineno, colno, error) {
    if (/\/g\/[a-z]+\.js/.test(source)
        // No clue what's up with these, sometimes happens in FF. Is Elm being initialized before the DOM is ready or something?
        && !(/elm\.js/.test(source) && /InvalidStateError/.test(ev))
    ) {
        var h = new XMLHttpRequest();
        var e = encodeURIComponent;
        h.open('POST', '/js-error?2', true);
        h.send('ev='+e(ev)+'&source='+e(source)+'&lineno='+e(lineno)+'&colno='+e(colno)+'&stack='+e(error.stack));
        window.onerror = null; // One error per page is enough
    }
    return false;
};

@include .gen/mithril.js
@include basic/api.js

// Load global page-wide variables from <script id="pagevars">...</script> and
// store them into window.pageVars.
window.pageVars = (e => e ? JSON.parse(e.innerHTML) : {})(document.getElementById('pagevars'));

// Widget initialization, see README.md
window.widget = (name, fun) =>
    ((pageVars.widget || {})[name] || []).forEach(([id, data]) =>
        m.mount(document.getElementById('widget'+id), {view: ()=>m(fun, {data})}));

// We used to use localStorage for some client-side preferences in the past.
// Only clear the most recent one (the stupid April fools joke), the last use
// of localStorage before that was long enough ago that it's most likely been
// cleared for everyone already (43ef1a26d68f2b5dbc8b5ac3cc30e27b7bf89ca3).
try { localStorage.removeItem('fools6') } catch (e) {}

// A bunch of old fashioned DOM manipulation features.
@include basic/checkall.js
@include basic/checkhidden.js
@include basic/mainbox-summarize.js
@include basic/searchtabs.js
@include basic/sethash.js
@include basic/ulist-actiontabs.js
@include basic/ulist-labelfilters.js

@include basic/elm-support.js

// Widgets
@include basic/Subscribe.js

// Image viewer; after loading Elm modules to ensure it sees the screenshots in VNEdit.
@include basic/iv.js

// @license-end
