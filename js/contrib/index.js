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


const imageAccept = '.jpg,.jpeg,.png,.webp,.avif,.jxl,image/jpeg,image/png,image/webp,image/avif,image/jxl';
const imageFormats = 'Supported file types: JPEG, PNG, WebP, AVIF or JXL, at most 10 MiB.';

const imagePattern = t => '^(?:.+/)?(?:' + t + '([0-9]+)|' + t + '/[0-9][0-9]/([0-9]+)\.jpg).*';
const imagePatternId = (t,v) => t + v.match(new RegExp(imagePattern(t))).filter(x => x !== undefined)[1];

const spoilLevels = [
    [0, 'No spoiler'],
    [1, 'Minor spoiler'],
    [2, 'Major spoiler'],
];


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
        api.Status(),
        api.error ? null : m('p.formerror', 'The form contains errors'),
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



const ImageFlag = initVnode => {
    const img = initVnode.attrs.img;
    const api = new Api('ImageVote');
    const sex = ['Safe', 'Suggestive', 'Explicit'];
    const vio = ['Tame', 'Violent', 'Brutal'];

    let editing = img.token && img.votecount == 0;
    let saved_sex = img.my_sexual;
    let saved_vio = img.my_violence;
    let timer = null;

    const save = () => {
        clearTimeout(timer);
        timer = null;
        if (saved_sex !== img.my_sexual || saved_vio !== img.my_violence) {
            saved_sex = img.my_sexual;
            saved_vio = img.my_violence;
            api.call({votes: [img]}, d => Object.assign(img, d[0]));
        }
    };

    const edit = () => {
        clearTimeout(timer);
        timer = setTimeout(() => {
            if (img.my_sexual !== null && img.my_violence !== null) save();
            m.redraw();
        }, 1000);
    };

    const view = () => [
        m('p',
            api.loading() ? m('span.spinner')
            : editing ? m(Button.Save, { onclick: () => {
                if (img.my_sexual === null || img.my_violence === null)
                    api.error = 'Please indicate both the sexual and violence ratings.';
                else
                    save(editing = false);
              }})
            : img.token ? m(Button.Edit, { onclick: () => editing = true }) : null,
            ' ',
            img.votecount === 0
            ? m('span', 'Not yet flagged.')
            : sex[img.sexual] + ' / ' + vio[img.violence] + ' (' + img.votecount + ' vote' + (img.votecount === 1 ? '' : 's') + ').'
        ),
        api.error ? m('p.standout', api.error) : null,
        !editing ? null : m('table[style=margin-left:30px]',
            m('thead', m('tr',
                m('td', 'Sexual'),
                m('td', 'Violence'),
            )), m('tbody', range(0, 2).map(i => m('tr',
                m('td', m('label.check', m('input[type=radio]', { checked: img.my_sexual   === i, onclick: () => edit(img.my_sexual   = i) }), ' ', sex[i])),
                m('td', m('label.check', m('input[type=radio]', { checked: img.my_violence === i, onclick: () => edit(img.my_violence = i) }), ' ', vio[i])),
            )))
        ),
    ];
    return {view};
};



@include ReleaseEdit.js
@include DRMEdit.js
@include ProducerEdit.js
@include StaffEdit.js
@include DocEdit.js
@include CharEdit.js
@include TagEdit.js
@include TraitEdit.js
@include Report.js

// @license-end
