// @license magnet:?xt=urn:btih:0b31508aeb0634b347b8270c7bee4d411b5d4109&dn=agpl-3.0.txt AGPL-3.0-only
// @source: https://code.blicky.net/yorhel/vndb/src/branch/master/js
// SPDX-License-Identifier: AGPL-3.0-only
"use strict";

// This list is incomplete, just an assortment of names and titles found in the DB
const _greek = '\u0370-\u03ff\u1f00-\u1fff';
const _cyrillic = '\u0400-\u04ff';
const _arabic = '\u0600-\u06ff';
const _thai = '\u0e00-\u0e7f';
const _hangul = '\u1100-\u11ff\uac00-\ud7af';
const _canadian = '\u1400-\u167f'; // Unified Canadian Aboriginal Syllabics, we have an actual Inuktitut title in the database
const _kana = '\u3040-\u3099\u30a1-\u30fa\uff66-\uffdc'; // Hiragana + Katakana + Half/Full-width forms
const _cjk = '\u3100-\u9fff'; // Whole range of CJK blocks
const mustRomanize = new RegExp('[' +          _cyrillic + _arabic + _thai + _hangul + _canadian + _kana + _cjk + ']');
// Greek characters are often used for styling and don't always need romanizing.
const mayRomanize  = new RegExp('[' + _greek + _cyrillic + _arabic + _thai + _hangul + _canadian + _kana + _cjk + ']');


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
        api.error
        ? m('b', m('br'), api.error)
        : m('p.formerror', 'The form contains errors'),
    );
    return {view};
};


@include .gen/extlinks.js
@include contrib/ReleaseEdit.js
@include contrib/DRMEdit.js
@include contrib/ProducerEdit.js
@include contrib/StaffEdit.js
@include contrib/DocEdit.js

// @license-end
