// @license magnet:?xt=urn:btih:0b31508aeb0634b347b8270c7bee4d411b5d4109&dn=agpl-3.0.txt AGPL-3.0-only
// @source: https://code.blicky.net/yorhel/vndb/src/branch/master/js
// SPDX-License-Identifier: AGPL-3.0-only
"use strict";

const nonLatin = /[\u0400-\u04ff\u0600-\u06ff\u0e00-\u0e7f\u1100-\u11ff\u1400-\u167f\u3040-\u3099\u30a1-\u30fa\u3100-\u9fff\uac00-\ud7af\uff66-\uffdc]/;


// Edit summary & submit button box for DB entry edit forms.
// Attrs:
// - data  -> form data containing editsum, hidden & locked
// - api   -> Api object for loading & error status
//
// TODO: Support for "awaiting approval" state.
// TODO: Better feedback on pointless edit summaries like "-", "..", etc
const EditSum = vnode => {
    const {api,data} = vnode.attrs;
    const rad = (l,h,lab) => m('label',
        m('input[type=radio]', {
            checked: l === data.locked && h === data.hidden,
            oninput: () => { data.locked = l; data.hidden = h }
        }), lab
    );
    const view = () => m('article.submit',
        pageVars.dbmod ? m('fieldset',
            rad(false, false, ' Normal '),
            rad(true , false, ' Locked '),
            rad(true , true , ' Deleted '),
            data.locked && data.hidden ? m('span',
                m('br'), 'Note: edit summary of the last edit should indicate the reason for the deletion.', m('br')
            ) : null,
        ) : null,
        m(TextPreview, {
            data, field: 'editsum',
            attrs: { rows: 4, cols: 50, minlength: 2, maxlength: 5000, required: true },
            header: [
                m('strong', 'Edit summary'),
                m('b', ' (English please!)'),
                m('br'),
                'Summarize the changes you have made, including links to source(s).',
            ]
        }),
        m('input[type=submit][value=Submit]'),
        api.loading() ? m('span.spinner') : null,
        api.error ? m('b', m('br'), api.error) : null,
        m('p.formerror', 'The form contains errors'),
    );
    return {view};
};


@include .gen/extlinks.js
@include contrib/ReleaseEdit.js

// @license-end
