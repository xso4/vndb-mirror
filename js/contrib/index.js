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
const _cjk = '\u3100-\u5f60\u5f62-\u9fff\u{20000}-\u{323af}'; // Whole range of CJK blocks (excluding _special)
const _special = '\u5f61'; // Characters sometimes used for styling, may or may not need romanization
const mustRomanize = new RegExp('[' +                     _cyrillic + _arabic + _thai + _hangul + _canadian + _kana + _cjk + ']', 'u');
const mayRomanize  = new RegExp('[' + _greek + _special + _cyrillic + _arabic + _thai + _hangul + _canadian + _kana + _cjk + ']', 'u');


const imageAccept = '.jpg,.jpeg,.png,.webp,.avif,.jxl,image/jpeg,image/png,image/webp,image/avif,image/jxl';
const imageFormats = 'Supported file types: JPEG, PNG, WebP, AVIF or JXL, at most 10 MiB.';

const imagePattern = t => '^(?:.+/)?(?:' + t + '([0-9]+)|' + t + '/[0-9][0-9]/([0-9]+)\.jpg).*';
const imagePatternId = (t,v) => t + v.match(new RegExp(imagePattern(t))).filter(x => x !== undefined)[1];

const spoilLevels = [
    [0, 'No spoiler'],
    [1, 'Minor spoiler'],
    [2, 'Major spoiler'],
];


const imgsize = (img, w, h) => {
    if (img.width <= w && img.height <= h)
        return { width: img.width, height: img.height };
    if (img.width/img.height > w/h)
        return { width: w, height: Math.round(img.height * (w/img.width)) };
    return { height: h, width: Math.round(img.width * (h/img.height)) };
};


// Edit summary & submit button box for DB entry edit forms.
// Attrs:
// - data     -> form data containing editsum, hidden & locked
// - api      -> Api object for loading & error status
// - type     -> vndbid type
const EditSum = vnode => {
    let {api,data,type} = vnode.attrs;
    const rad = (l,h,lab) => m('label',
        m('input[type=radio]', {
            checked: l === data.locked && h === data.hidden,
            oninput: () => { data.locked = l; data.hidden = h }
        }), lab
    );
    const approval = type === 'g' || type === 'i';
    const mod = 'authmod' in data ? data.authmod : pageVars.dbmod;
    const view = () => m('article.submit',
        mod ? m('fieldset',
            rad(false, false, ' Normal '),
            rad(true , false, ' Locked '),
            rad(true , true , ' Deleted '),
            approval ? rad(false, true, ' Awaiting approval ') : null,
            data.locked && data.hidden ? m('span',
                m('br'), 'Note: edit summary of the last edit should indicate the reason for the deletion.', m('br')
            ) : null,
        ) : null,
        m(TextPreview, {
            data, field: 'editsum',
            attrs: {
                rows: 4, cols: 50, minlength: 2, maxlength: 5000, required: true,
                invalid: /^[!@#$%^&\*\(\)\-_=\+\[\];:'",<.>/\?\\\|]+$/.test(data.editsum) ? "Please type something meaningful!" : null,
            },
            header: [
                data.id ? 'What did you change and why? Which source(s) did you use? Links are always welcome!'
                : type === 'v' ? [ 'Which source(s) did you use? Does the visual novel match our ', m('a[href=/d2#1][target=_blank]', 'inclusion criteria'), '?' ]
                : type === 'p' ? 'For which visual novel(s) are you adding this producer entry? Which source(s) did you use?'
                : type === 's' ? 'For which visual novel(s) are you adding this staff entry? Which source(s) did you use?'
                : type === 'c' ? 'What source did you use for information about this character?'
                : type === 'r' ? 'What source did you use for information about this release?'
                : type === 'g' ? 'Why should this tag be included in the database?'
                : type === 'i' ? 'Why should this trait be included in the database?'
                : null,
            ]
        }),
        m('input[type=submit][value=Submit]'),
        api.Status(),
        api.error ? null : m('p.formerror', 'The form contains errors'),
    );
    return {view};
};



const ExtLinks = initVnode => {
    const links = initVnode.attrs.links;
    const extlinks = vndbTypes.extLinks.flatMap(
        ([site,ent,label],i) => ent.toLowerCase().includes(initVnode.attrs.type) ? [{
            site, label,
            multi: ent.includes(initVnode.attrs.type.toUpperCase()),
            fmt: extLinksExt[i][0],
            patt: extLinksExt[i][1],
            regex: extLinksExt[i][2],
        }] : []);
    const extlinksMap = Object.fromEntries(extlinks.map(x => [x.site,x]));
    const split = (fmt,v) => fmt.split(/(%[0-9]*[sd])/)
        .map((p,i) => i !== 1 ? p : String(v).padStart(p.match(/%(?:0([0-9]+))?/)[1]||0, '0'));

    let inp = {str: ''};
    let web = {str: (l => l ? l.value : '')(links.find(l => l.site === 'website'))};
    const add = o => {
        if (o.lnk.multi || !links.find(l => l.site === o.lnk.site))
            links.push({ site: o.lnk.site, value: o.val });
        else links.forEach(l => { if(l.site === o.lnk.site) l.value = o.val });
        o.str = '';
        o.lnk = o.val = null;
        o.dup = false;
    };
    const set = (o,v) => {
        if (v !== null) o.str = v;
        o.lnk = extlinks.find(l => new RegExp(l.regex).test(o.str));
        o.val = o.lnk && o.str.match(new RegExp(o.lnk.regex)).filter(x => x !== undefined)[1];
        o.dup = o.lnk && links.find(l => l.site === o.lnk.site && l.value === o.val);
        if (o.lnk && !o.dup && (o.lnk.multi || !links.find(l => l.site === o.lnk.site))) add(o);
    };
    const Msg = (o,isinp) =>
        isinp && o.str.length > 0 && !o.lnk ? [ m('p', ('small', '>>> '), m('b.invalid', 'Invalid or unrecognized URL.')) ] :
        o.dup ? [ m('p', m('small', '>>> '), m('b.invalid', ' URL already listed.')) ] :
        o.lnk ? [
            m('p', m('input[type=button][value=Update]', { onclick: () => add(o) }), m('span.invalid', ' URL recognized as: ', o.lnk.label)),
            m('p.invalid', 'Did you mean to update the URL?'),
        ] : null;
    const Website = () => extlinksMap.website ? m('fieldset',
        m('label[for=website]', 'Website'),
        m(Input, { id: 'website', class: 'xw', type: 'weburl', data: web, field: 'str', oninput: v => {
            const l = links.find(l => l.site === 'website');
            if(l) links.splice(links.indexOf(l), 1);
            set(web,v);
            if(!web.lnk && web.str.length > 0) links.push({ site: 'website', value: v });
        }}),
        Msg(web),
    ) : null;

    const view = () => [ Website(), m('fieldset',
        m('label[for=extlinks]', 'External links', HelpButton('extlinks')),
        m('table', links.filter(l => extlinksMap[l.site]).map(l => m('tr', {key: l.site+'-'+l.value},
            m('td', m(Button.Del, {onclick: () => { links.splice(links.indexOf(l), 1); set(inp,null)}})),
            m('td', m('a[target=_blank]', { href: split(extlinksMap[l.site].fmt, l.value).join('') }, extlinksMap[l.site].label)),
            m('td', split(extlinksMap[l.site].fmt, l.value).map((p,i) => m(i === 1 ? 'span' : 'small', p))),
        ))),
        m('form', { onsubmit: ev => { ev.preventDefault(); if (inp.lnk && !inp.dup) add(inp); } },
            m('input#extlinks.xw[type=text][placeholder=Add URL...]', { value: inp.str, oninput: ev => set(inp, ev.target.value)}),
            Msg(inp,1),
        ),
        Help('extlinks',
            m('p', 'Links to external websites. The following sites and URL formats are supported:'),
            m('dl', extlinks.filter(l => extlinksMap[l.site]).flatMap(e => [
                m('dt', e.label),
                m('dd', e.patt.map((p,i) => m(i % 2 ? 'strong' : 'span', p))),
            ])),
            m('p', 'Links to sites that are not in the above list can still be added in the notes field below.'),
        ),
    )];
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
@include VNEdit.js
@include Tagmod.js
@include DRMEdit.js
@include ProducerEdit.js
@include StaffEdit.js
@include DocEdit.js
@include CharEdit.js
@include TagEdit.js
@include TraitEdit.js
@include ImageFlagging.js
@include Report.js

// @license-end
