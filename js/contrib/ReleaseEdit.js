const Titles = initVnode => {
    const {data} = initVnode.attrs;
    const ds = new DS(DS.ScriptLang, {
        onselect: obj => {
            const p = data.vntitles.find(t => t.lang === obj.id);
            data.titles.push({ lang: obj.id, mtl: false, title: p?p.title:'', latin: p?p.latin:'', new: true });
            if (data.titles.length === 1) data.olang = data.titles[0].lang;
        },
        props: obj => data.titles.find(t => t.lang === obj.id) ? { selectable: false, append: m('small', ' (already listed)') } : {},
    });
    const langs = Object.fromEntries(vndbTypes.language);
    const view = () => m('fieldset.form',
        m('legend', 'Titles & languages', HelpButton('titles')),
        Help('titles',
            m('p', 'List of languages that this release is available in.'),
            m('p',
                'The main language is the language that the script was originally authored in, ',
                'or for translations, the primary language of the publisher.'
            ),
            m('p',
                'A release can have different titles for different languages. ',
                'The main language should always have a title, but this field can be left empty for other languages if their title is the same as that of the main language.'
            ),
        ),
        data.titles.map(t => m('fieldset', {key: t.lang},
            m('label', { for: 'title-'+t.lang }, LangIcon(t.lang), langs[t.lang]),
            m(Input, {
                id: 'title-'+t.lang, class: 'xw',
                maxlength: 300, required: t.lang === data.olang,
                placeholder: t.lang === data.olang ? 'Title (in the original script)' : 'Title (leave empty if equivalent to the main title)',
                data: t, field: 'title', focus: t.new,
            }),
            !t.latin && !nonLatin.test(t.title) ? [] : [
                m('br'),
                m(Input, {
                    class: 'xw', maxlength: 300, required: true,
                    data: t, field: 'latin', placeholder: 'Romanization',
                    invalid: nonLatin.test(t.latin) ? 'Romanization should only contain characters in the latin alphabet.' : null,
                }),
            ],
            m('br'),
            data.titles.length === 1 ? [] : [
                m('span', m('label.check',
                    m('input[type=radio]', { checked: t.lang === data.olang, oninput: ev => data.olang = t.lang }),
                    ' Main title '
                )),
            ],
            m('span', m('label.check',
                m('input[type=checkbox]', { checked: t.mtl, oninput: ev => t.mtl = ev.target.checked }),
                ' Machine translation '
            )),
            m('input[type=button][value=Remove]', {
                class: t.lang === data.olang ? 'invisible' : null,
                onclick: () => data.titles = data.titles.filter(x => x !== t)
            }),
        )),
        m(DSButton, { onclick: ds.open }, 'Add language'),
        data.titles.length > 0 ? null : m('p.invalid', 'At least one language must be selected.'),
    );
    return {view};
};


const Status = initVnode => {
    const {data} = initVnode.attrs;
    const view = () => m('fieldset.form',
        m('legend', 'Status'),
        m('fieldset', m('label.check',
            m('input[type=checkbox]', { checked: data.official, oninput: ev => data.official = ev.target.checked }),
            ' Official ', HelpButton('official'),
        )),
        Help('official',
            'Whether the release is official, i.e. made or sanctioned by the original developer. ',
            'The official status is in relation to the visual novel that the release is linked to, ',
            'so even if the visual novel itself is an unofficial fanfic in some franchise, the release can still be official.'
        ),
        m('fieldset', m('label.check',
            m('input[type=checkbox]', { checked: data.patch, oninput: ev => data.patch = ev.target.checked }),
            ' Patch (*)', HelpButton('patch'),
        )),
        Help('patch',
            'A patch is not a standalone release, but instead requires another release in order to be used. ',
            'It may be helpful to indicate which releases this patch applies to in the notes.'
        ),
        m('fieldset', m('label.check',
            m('input[type=checkbox]', { checked: data.freeware, oninput: ev => data.freeware = ev.target.checked }),
            ' Freeware'
        )),
        m('fieldset', m('label.check',
            m('input[type=checkbox]', { checked: data.has_ero, oninput: ev => data.has_ero = ev.target.checked }),
            ' Contains erotic scenes (*)'
        )),
        m('fieldset',
            m('label[for=minage]', 'Age rating'),
            m('select.mw', { oninput: ev => data.minage = ev.target.selectedIndex === 0 ? null : vndbTypes.ageRating[ev.target.selectedIndex-1][0] },
                m('option', { selected: data.minage === null }, 'Unknown'),
                vndbTypes.ageRating.map(([id,label]) => m('option', { selected: id === data.minage }, label))
            )
        ),
        m('fieldset',
            m('label[for=released]', 'Release date'),
            m(RDate, { id: 'released', value: data.released, oninput: v => data.released = v }),
        ),
    );
    return {view};
}


const Format = initVnode => {
    const {data} = initVnode.attrs;
    const plat = new DS(DS.Platforms, {
        checked: ({id}) => !!data.platforms.find(p => p.platform === id),
        onselect: ({id},sel) => { if (sel) data.platforms.push({platform:id}); else data.platforms = data.platforms.filter(p => p.platform !== id)},
        checkall: () => data.platforms = vndbTypes.platform.map(([platform]) => ({platform})),
        uncheckall: () => data.platforms = [],
    });
    const media = Object.fromEntries(vndbTypes.medium.map(([id,label,qty]) => [id,{label,qty}]));

    const engines = new DS(DS.New(DS.Engines,
        id => ({id}),
        obj => m('em', obj.id ? 'Add new engine: ' + obj.id : 'Empty / unknown'),
    ), { onselect: obj => data.engine = obj.id });

    const resoParse = str => {
        const v = str.toLowerCase().replaceAll('*', 'x').replaceAll('×', 'x').replace(/[-\s]+/g, '');
        if (v === '' || v === 'unknown') return [0,0];
        if (v === 'nonstandard') return [0,1];
        const a = /^([0-9]+)x([0-9]+)$/.exec(v);
        if (!a) return null;
        const r = [Math.floor(a[1]), Math.floor(a[2])];
        return r[0] > 0 && r[0] <= 32767 && r[1] > 0 && r[1] <= 32767 ? r : null;
    };
    const resoFmt = (x,y) => x ? x+'x'+y : y ? 'Non-standard' : '';

    const resolutions = new DS(DS.New(DS.Resolutions,
        str => { const r = resoParse(str); return r ? {id:resoFmt(...r)} : null },
        obj => m('em', obj.id ? 'Custom resolution: ' + resoFmt(...resoParse(obj.id)) : 'Empty / unknown'),
    ), {
        onselect: obj => { const r = resoParse(obj.id); data.reso_x = r?r[0]:0; data.reso_y = r?r[1]:0; },
    });

    const view = () => m('fieldset.form',
        m('legend', 'Format'),
        m('fieldset',
            m('label', 'Platforms'),
            m(DSButton, { class: 'xw', onclick: plat.open },
                data.platforms.length === 0 ? 'No platforms selected' :
                data.platforms.map(p => m('span', PlatIcon(p.platform), vndbTypes.platform.find(([x]) => x === p.platform)[1])).intersperse(' '),
            ),
        ),
        m('fieldset',
            m('label', 'Media'),
            data.media.map(x => m('div',
                m(Button.Del, { onclick: () => data.media = data.media.filter(y => x !== y) }), ' ',
                m('select.sw', { oninput: ev => x.qty = ev.target.selectedIndex+1, class: media[x.medium].qty ? null : 'invisible' },
                    range(1, 40).map(i => m('option', { selected: i === x.qty }, i))
                ), ' ',
                media[x.medium].label, m('br'),
            )),
            m('select.mw', { oninput: ev => ev.target.selectedIndex > 0 && data.media.push({medium: vndbTypes.medium[ev.target.selectedIndex-1][0], qty:1}) },
                m('option[selected]', '- Add medium -'),
                vndbTypes.medium.map(([,label]) => m('option', label)),
            ),
            data.media.anyDup(({medium,qty}) => [medium, media[medium].qty ? qty : null])
            ?  m('p.invalid', 'List contains duplicates') : null,
        ),
        m('fieldset',
            m('label', 'Engine'),
            m(DSButton, { onclick: engines.open, class: 'mw' }, data.engine),
        ),
        m('fieldset',
            m('label', 'Resolution'),
            m(DSButton, { onclick: resolutions.open, class: 'mw' }, resoFmt(data.reso_x, data.reso_y)),
        ),
        m('fieldset',
            m('label[for=voiced]', 'Voiced'),
            m('select#voiced.mw', { oninput: ev => data.voiced = ev.target.selectedIndex },
                vndbTypes.voiced.map((l,i) => m('option', { selected: i === data.voiced }, l))
            )
        ),
        data.has_ero ? m('fieldset',
            m('label[for=uncensored]', 'Censoring'),
            m('select#uncensored.mw', { oninput: ev => data.uncensored = [null,false,true][ev.target.selectedIndex] },
                m('option', { selected: data.uncensored === null }, 'Unknown'),
                m('option', { selected: data.uncensored === false }, 'Censored graphics'),
                m('option', { selected: data.uncensored === true }, 'Uncensored graphcs'),
            ),
        ) : null,
    );
    return {view};
};


const Animation = initVnode => {
    const {data} = initVnode.attrs;
    const hasAni = v => v !== null && v !== 0 && v !== 1;
    let some = hasAni(data.ani_story_sp) || hasAni(data.ani_story_cg) || hasAni(data.ani_cutscene)
            || hasAni(data.ani_ero_sp)   || hasAni(data.ani_ero_cg)
            || (data.ani_face !== null && data.ani_face !== null)
            || (data.ani_bg   !== null && data.ani_bg   !== null);

    const flagmask = 4+8+16+32;
    const freqmask = 256+512;
    const lbl = (key, bit, name) => m('label.check',
        { class: data[key] === null || data[key] === bit || (bit > 2 && data[key] > 2) ? null : 'grayedout' },
        m('input[type=checkbox]', {
            checked: data[key] === bit || (bit > 2 && (data[key] & bit) > 0),
            onclick: ev => data[key] = bit <= 2
                ? (ev.target.checked ? bit : null)
                : (ev.target.checked ? ((data[key]||0) & ~3) | bit : ((data[key]||0) & flagmask) === bit ? null : ((data[key]||0) & ~bit))
        }),
        ' ', name, m('br')
    );
    const ani = (key, na) => ([
        key === 'ani_cutscene' ? null : lbl(key, 0, 'Not animated'),
        lbl(key,  1, na),
        lbl(key,  4, 'Hand drawn'),
        lbl(key,  8, 'Vectorial'),
        lbl(key, 16, '3D'),
        lbl(key, 32, 'Live action'),
        key === 'ani_cutscene' || data[key] === null || data[key] <= 2 ? null : m('select.mw',
            { oninput: ev => data[key] = (data[key] & ~freqmask) | (ev.target.selectedIndex * 256) },
            m('option', { selected: (data[key] & freqmask) === 0 }, '- frequency -'),
            m('option', { selected: (data[key] & freqmask) === 256 }, 'Some scenes'),
            m('option', { selected: (data[key] & freqmask) === 512 }, 'All scenes'),
        ),
    ]);

    const view = () => m('fieldset.form',
        m('legend', 'Animation'),
        m('fieldset',
            m('label', 'Preset'),
            m('label.check',
                m('input[type=radio]', { checked: !some && data.ani_face === null, onclick: () => { some = false; Object.assign(data, {
                    ani_story_sp: null, ani_story_cg: null, ani_cutscene: null,
                    ani_ero_sp: null, ani_ero_cg: null, ani_face: null, ani_bg: null
                })}}),
                ' Unknown'
            ),
            ' / ',
            m('label.check',
                m('input[type=radio]', { checked: !some && data.ani_face === false, onclick: () => { some = false; Object.assign(data, {
                    ani_story_sp: 0, ani_story_cg: 0, ani_cutscene: 1,
                    ani_ero_sp: data.has_ero ? 1 : null, ani_ero_cg: data.has_ero ? 0 : null,
                    ani_face: false, ani_bg: false
                })}}),
                ' No animation'
            ),
            ' / ',
            m('label.check',
                m('input[type=radio]', { checked: some, onclick: () => some = true }),
                ' Some animation'
            ),
        ),
        !some ? [] : [
        m('fieldset',
            m('label', 'Story scenes'),
            m('table.release-animation', m('tr',
                m('td', m('strong', 'Character sprites:'), m('br'), ani('ani_story_sp', 'No sprites')),
                m('td', m('strong', 'CGs:'), m('br'), ani('ani_story_cg', 'No CGs')),
                m('td', m('strong', 'Cutscenes:'), m('br'), ani('ani_cutscene', 'No cutscenes')),
            )),
        ),
        data.has_ero ? m('fieldset',
            m('label', 'Erotic scenes'),
            m('table.release-animation', m('tr',
                m('td', m('strong', 'Character sprites:'), m('br'), ani('ani_ero_sp', 'No sprites')),
                m('td', m('strong', 'CGs:'), m('br'), ani('ani_ero_cg', 'No CGs')),
            )),
        ) : null,
        m('fieldset',
            m('label', 'Effects'),
            m('table',
                m('tr', m('td', 'Character lip movement and/or eye blink:'), m('td',
                    m('label.check', m('input[type=radio]', { checked: data.ani_face === null,  onclick: () => data.ani_face = null  }), ' Unknown or N/A'), ' / ',
                    m('label.check', m('input[type=radio]', { checked: data.ani_face === false, onclick: () => data.ani_face = false }), ' No'), ' / ',
                    m('label.check', m('input[type=radio]', { checked: data.ani_face === true,  onclick: () => data.ani_face = true  }), ' Yes'),
                )),
                m('tr', m('td', 'Background effects:'), m('td',
                    m('label.check', m('input[type=radio]', { checked: data.ani_bg === null,  onclick: () => data.ani_bg = null  }), ' Unknown or N/A'), ' / ',
                    m('label.check', m('input[type=radio]', { checked: data.ani_bg === false, onclick: () => data.ani_bg = false }), ' No'), ' / ',
                    m('label.check', m('input[type=radio]', { checked: data.ani_bg === true,  onclick: () => data.ani_bg = true  }), ' Yes'),
                )),
            ),
        ),
        ]
    );
    return {view};
};


const ExtLinks = initVnode => {
    const links = initVnode.attrs.data.extlinks;
    const extlinks = extLinks.release;
    const split = (fmt,v) => fmt.split(/(%[0-9]*[sd])/)
        .map((p,i) => i !== 1 ? p : String(v).padStart(p.match(/%(?:0([0-9]+))?/)[1]||0, '0'));
    let str = ''; // input string
    let lnk = null; // link object, if matched
    let val = null; // extracted value, if matched
    let dup = false; // if link is already present
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
                    m('td', m(Button.Del, {onclick: () => links[l.id] = l.multi ? links[l.id].filter(x => x !== v) : l.int ? 0 : ''})),
                    m('td', m('a[target=_blank]', { href: split(l.fmt, v).join('') }, l.name)),
                    m('td', split(l.fmt, v).map((p,i) => m(i === 1 ? 'span' : 'small', p))),
                )
            )
        )),
        m('form', { onsubmit: ev => { ev.preventDefault(); if (lnk && !dup) add(); } },
            m('input#extlinks.xw[type=text][placeholder=Add URL...]', { value: str, oninput: ev => {
                str = ev.target.value;
                lnk = extlinks.find(l => new RegExp(l.regex).test(str));
                val = lnk && (v => lnk.int ? v>>0 : ''+v)(str.match(new RegExp(lnk.regex))[1]);
                dup = lnk && (lnk.multi ? links[lnk.id].find(x => x === val) : links[lnk.id] === val);
                if (lnk && !dup && (lnk.multi || links[lnk.id] === 0 || links[lnk.id] === '')) add();
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


const VNs = initVnode => {
    const {data} = initVnode.attrs;
    const ds = new DS(DS.VNs, {
        onselect: obj => data.vn.push({vid: obj.id, title: obj.title, rtype: 'complete' }),
    });
    const view = () => m('fieldset',
        m('label', 'Visual novels'),
        data.vn.length === 0
        ? m('p.invalid', 'No visual novels selected.')
        : m('table', data.vn.map(v => m('tr', {key: v.vid},
            m('td',
                m(Button.Del, { onclick: () => data.vn = data.vn.filter(x => x !== v) }), ' ',
                m('select', { oninput: ev => v.rtype = vndbTypes.releaseType[ev.target.selectedIndex][0] },
                    vndbTypes.releaseType.map(([id,lbl]) => m('option', { selected: id === v.rtype }, lbl))
                ),
            ),
            m('td', m('small', v.vid, ': '), m('a[target=_blank]', { href: '/'+v.vid }, v.title)),
        ))),
        m(DSButton, { class: 'mw', onclick: ds.open }, 'Add visual novel'),
    );
    return {view};
};


const Producers = initVnode => {
    const {data} = initVnode.attrs;
    const ds = new DS(DS.Producers, {
        onselect: obj => data.producers.push({pid: obj.id, name: obj.name, developer: true, publisher: true }),
    });
    const view = () => m('fieldset',
        m('label', 'Producers'),
        m('table', data.producers.map(p => m('tr', {key: p.pid},
            m('td',
                m(Button.Del, { onclick: () => data.producers = data.producers.filter(x => x !== p) }), ' ',
                m('select', { oninput: ev => {
                    const i = ev.target.selectedIndex;
                    p.developer = i === 0 || i === 2;
                    p.publisher = i === 1 || i === 2;
                }},
                    m('option', { selected: p.developer && !p.publisher }, 'Developer'),
                    m('option', { selected: !p.developer && p.publisher }, 'Publisher'),
                    m('option', { selected: p.developer && p.publisher }, 'Both'),
                ),
            ),
            m('td', m('small', p.pid, ': '), m('a[target=_blank]', { href: '/'+p.pid }, p.name)),
        ))),
        m(DSButton, { class: 'mw', onclick: ds.open }, 'Add producer'),
    );
    return {view};
};


widget('ReleaseEdit', initVnode => {
    const data = initVnode.attrs.data;
    const api = new Api('ReleaseEdit');
    const gtin = {v: data.gtin === '0' ? '' : data.gtin};
    const view = () => m(Form, {api, onsubmit: () => api.call(data)},
        m('article',
            m('h1', 'General info'),
            m(Titles, {data}),
            m(Status, {data}),
            m(Format, {data}),
            m(Animation, {data}),
            m('fieldset.form',
                m('legend', 'External identifiers & links'),
                m('fieldset',
                    m('label[for=gtin]', 'JAN/UPC/EAN'),
                    m(Input, {
                        id: 'gtin', class: 'mw', type: 'number', data: gtin, field: 'v',
                        oninput: v => { data.gtin = v; gtin.v = v === 0 ? '' : v },
                    }),
                ),
                m('fieldset',
                    m('label[for=catalog]', 'Catalog number'),
                    m(Input, { id: 'catalog', class: 'mw', maxlength: 50, data, field: 'catalog' }),
                ),
                m('fieldset',
                    m('label[for=website]', 'Website'),
                    m(Input, { id: 'website', class: 'xw', type: 'weburl', data, field: 'website' }),
                ),
                m(ExtLinks, {data}),
            ),
            m('fieldset.form',
                m('legend', 'Database relations'),
                m(VNs, {data}),
                m(Producers, {data}),
            ),
            m('fieldset.form',
                m('label[for=notes]', 'Notes'),
                m(TextPreview, {
                    data, field: 'notes',
                    header: m('b', '(English please!)'),
                    attrs: { id: 'notes', rows: 5 },
                }),
            ),
        ),
        m(EditSum, {data,api}),
    );
    return {view};
});
