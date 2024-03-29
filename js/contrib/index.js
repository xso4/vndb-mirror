// @license magnet:?xt=urn:btih:0b31508aeb0634b347b8270c7bee4d411b5d4109&dn=agpl-3.0.txt AGPL-3.0-only
// @source: https://code.blicky.net/yorhel/vndb/src/branch/master/js
// SPDX-License-Identifier: AGPL-3.0-only
"use strict";

@include .gen/extlinks.js


// This list is incomplete, just an assortment of names and titles found in the DB
const _greek = '\u0370-\u03ff\u1f00-\u1fff';
const _cyrillic = '\u0400-\u04ff';
const _arabic = '\u0600-\u06ff';
const _thai = '\u0e00-\u0e7f';
const _hangul = '\u1100-\u11ff\uac00-\ud7af';
const _canadian = '\u1400-\u167f'; // Unified Canadian Aboriginal Syllabics, we have an actual Inuktitut title in the database
const _kana = '\u3040-\u3099\u30a1-\u30fa\uff66-\uffdc'; // Hiragana + Katakana + Half/Full-width forms
const _cjk = '\u3100-\u9fff\u{20000}-\u{323af}'; // Whole range of CJK blocks
const mustRomanize = new RegExp('[' +          _cyrillic + _arabic + _thai + _hangul + _canadian + _kana + _cjk + ']', 'u');
// Greek characters are often used for styling and don't always need romanizing.
const mayRomanize  = new RegExp('[' + _greek + _cyrillic + _arabic + _thai + _hangul + _canadian + _kana + _cjk + ']', 'u');



// Edit summary & submit button box for DB entry edit forms.
// Attrs:
// - data     -> form data containing editsum, hidden & locked
// - api      -> Api object for loading & error status
// - approval -> null for entries that don't require approval, otherwise a boolean indicating mod status
//
// TODO: Better feedback on pointless edit summaries like "-", "..", etc
const EditSum = vnode => {
    let {api,data,approval} = vnode.attrs;
    const rad = (l,h,lab) => m('label',
        m('input[type=radio]', {
            checked: l === data.locked && h === data.hidden,
            oninput: () => { data.locked = l; data.hidden = h }
        }), lab
    );
    if (typeof approval !== 'boolean') approval = null;
    const mod = approval === null ? pageVars.dbmod : approval;
    const view = () => m('article.submit',
        mod ? m('fieldset',
            rad(false, false, ' Normal '),
            rad(true , false, ' Locked '),
            rad(true , true , ' Deleted '),
            approval === null ? null : rad(false, true, ' Awaiting approval '),
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



const ExtLinks = initVnode => {
    const links = initVnode.attrs.data;
    const extlinks = extLinks[initVnode.attrs.type];
    const split = (fmt,v) => fmt.split(/(%[0-9]*[sd])/)
        .map((p,i) => i !== 1 ? p : String(v).padStart(p.match(/%(?:0([0-9]+))?/)[1]||0, '0'));
    let str = ''; // input string
    let lnk = null; // link object, if matched
    let val = null; // extracted value, if matched
    let dup = false; // if link is already present
    extlinks.forEach(l => l.multi = Array.isArray(l.default));
    const add = () => {
        if (lnk.multi) links[lnk.id].push(val);
        else links[lnk.id] = val;
        str = '';
        lnk = val = null;
        dup = false;
    };
    const view = () => m('fieldset',
        m('label[for=extlinks]', 'External links', HelpButton('extlinks')),
        m('table', extlinks.flatMap(l =>
            (l.multi ? links[l.id] : links[l.id] ? [links[l.id]] : []).map(v =>
                m('tr', {key: l.id + '-' + v },
                    m('td', m(Button.Del, {onclick: () => links[l.id] = l.multi ? links[l.id].filter(x => x !== v) : l.default})),
                    m('td', m('a[target=_blank]', { href: split(l.fmt, v).join('') }, l.name)),
                    m('td', split(l.fmt, v).map((p,i) => m(i === 1 ? 'span' : 'small', p))),
                )
            )
        )),
        m('form', { onsubmit: ev => { ev.preventDefault(); if (lnk && !dup) add(); } },
            m('input#extlinks.xw[type=text][placeholder=Add URL...]', { value: str, oninput: ev => {
                str = ev.target.value;
                lnk = extlinks.find(l => new RegExp(l.regex).test(str));
                val = lnk && (v => lnk.int ? +v : ''+v)(str.match(new RegExp(lnk.regex)).filter(x => x !== undefined)[1]);
                dup = lnk && (lnk.multi ? links[lnk.id].find(x => x === val) : links[lnk.id] === val);
                if (lnk && !dup && (lnk.multi || links[lnk.id] === null || links[lnk.id] === 0 || links[lnk.id] === '')) add();
            }}),
            str.length > 0 && !lnk ? [ m('p', ('small', '>>> '), m('b.invalid', 'Invalid or unrecognized URL.')) ] :
            dup ? [ m('p', m('small', '>>> '), m('b.invalid', ' URL already listed.')) ] :
            lnk ? [
                m('p', m('input[type=submit][value=Update]'), m('span.invalid', ' URL recognized as: ', lnk.name)),
                m('p.invalid', 'Did you mean to update the URL?'),
            ] : [],
        ),
        Help('extlinks',
            m('p', 'Links to external websites. The following sites and URL formats are supported:'),
            m('dl', extlinks.flatMap(e => [
                m('dt', e.name),
                m('dd', e.patt.map((p,i) => m(i % 2 ? 'strong' : 'span', p))),
            ])),
            m('p', 'Links to sites that are not in the above list can still be added in the notes field below.'),
        ),
    );
    return {view};
};



@include ReleaseEdit.js
@include DRMEdit.js
@include ProducerEdit.js
@include StaffEdit.js
@include DocEdit.js
@include TagEdit.js
@include Report.js

// @license-end
