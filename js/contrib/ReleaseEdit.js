const Titles = initVnode => {
    const {data} = initVnode.attrs;
    const ds = new DS(DS.Lang, {
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
            m('label', LangIcon(t.lang), langs[t.lang]),
            m('input.xw[type=text][maxlength=300]', {
                required: t.lang === data.olang,
                placeholder: t.lang === data.olang ? 'Title (in the original script)' : 'Title (leave empty if equivalent to the main title)',
                value: t.title, oninput: ev => t.title = ev.target.value,
                oncreate: t.new ? v => { t.new = false; v.dom.focus() } : null,
            }),
            !t.latin && !nonLatin.test(t.title) ? [] : [
                m('br'),
                m('input.xw[type=text][maxlength=300][required]', {
                    placeholder: 'Romanization',
                    value: t.latin, oninput: ev => t.latin = ev.target.value,
                    onupdate: v => v.dom.setCustomValidity(nonLatin.test(t.latin) ? 'Romanization should only contain characters in the latin alphabet.' : ''),
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
        (str, obj) => obj.id === str,
        str => m('em', 'Add new engine: ' + str),
    ), {
        onselect: obj => data.engine = obj.id,
        erase: () => data.engine = '',
    });

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
        (str, obj) => { const a = resoParse(obj.id); const b = resoParse(str); return b && a[0] === b[0] && a[1] === b[1] },
        str => { const r = resoParse(str); return r ? m('em', 'Custom resolution: ' + resoFmt(r[0],r[1])) : null },
    ), {
        onselect: obj => { const r = resoParse(obj.id); data.reso_x = r?r[0]:0; data.reso_y = r?r[1]:0; },
        erase: () => { data.reso_x = 0; data.reso_y = 0; },
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


widget('ReleaseEdit', initVnode => {
    const data = initVnode.attrs.data;
    const api = new Api('ReleaseEdit');
    const view = () => m(Form, {api, onsubmit: () => api.call(data)},
        m('article',
            m('h1', 'General info'),
            m(Titles, {data}),
            m(Status, {data}),
            m(Format, {data}),
        ),
        m(EditSum, {data,api}),
    );
    return {view};
});
