// @license magnet:?xt=urn:btih:0b31508aeb0634b347b8270c7bee4d411b5d4109&dn=agpl-3.0.txt AGPL-3.0-only
// @source: https://code.blicky.net/yorhel/vndb/src/branch/master/js
// @license magnet:?xt=urn:btih:d3d9a9a6595521f9666a5e94cc830dab83b65699&dn=expat.txt Expat
// @source: https://github.com/preactjs/preact
// @license magnet:?xt=urn:btih:8e4f440f4c65981c5bf93c76d35135ba5064d8b7&dn=apache-2.0.txt Apache-2.0
// @source: https://github.com/developit/htm
// SPDX-License-Identifier: AGPL-3.0-only AND Expat AND Apache-2.0

// ^ LibreJS browser plugin only recognizes the first license tag in the file,
// so it's kind of incorrect. Their spec doesn't appear to support bundling.

"use strict";

// This preact-htm.js is postprocessed by our Makefile to export directly into
// `window`, so we can use h(), html``, render(), etc. without any imports.
// XXX: Disabled for now, we don't have any preact components (yet).
//@include .gen/preact-htm.js

// Load global page-wide variables from <script id="pagevars">...</script> and
// store them into window.pageVars.
window.pageVars = (e => e ? JSON.parse(e.innerHTML) : {})(document.getElementById('pagevars'));

// We used to use localStorage for some client-side preferences in the past.
// Only clear the most recent one (the stupid April fools joke), the last use
// of localStorage before that was long enough ago that it's most likely been
// cleared for everyone already (43ef1a26d68f2b5dbc8b5ac3cc30e27b7bf89ca3).
if(window.localStorage) localStorage.removeItem('fools6');

// A bunch of old fashioned DOM manipulation features.
@include basic/checkall.js
@include basic/checkhidden.js
@include basic/mainbox-summarize.js
@include basic/searchtabs.js
@include basic/sethash.js
@include basic/ulist-actiontabs.js
@include basic/ulist-labelfilters.js

@include basic/elm-support.js

// Image viewer; after loading Elm modules to ensure it sees the screenshots in VNEdit.
@include basic/iv.js

// @license-end
