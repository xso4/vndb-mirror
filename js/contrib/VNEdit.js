const Titles = initVnode => {
    const {data} = initVnode.attrs;
    const ds = new DS(DS.ScriptLang, {
        onselect: obj => {
            data.titles.push({ lang: obj.id, official: true, title: '', latin: '', new: true });
            if (data.titles.length === 1) data.olang = obj.id;
        },
        props: obj => data.titles.find(t => t.lang === obj.id) ? { selectable: false, append: m('small', ' (already listed)') } : {},
    });
    const langs = Object.fromEntries(vndbTypes.language);
    const relLangs = data.id ? Object.fromEntries(data.releases.flatMap(r => r.lang.map(l => [l,true]))) : langs;
    const relTitles = Object.fromEntries(data.reltitles.map(s => [s,true]));

    const aliasInvalid = () => {
        const lst = data.alias.toLowerCase().split("\n").map(s => s?s.trim():'').filter(s => s.length > 0);
        if (lst.anyDup()) return 'List contains duplicates.';
        const titles = Object.fromEntries(data.titles.flatMap(x => [x.title, x.latin]).map(s => s?s.toLowerCase().trim():'').filter(s => s.length > 0).map(s => [s,1]));
        const tit = lst.find(x => titles[x]);
        if (tit) return 'Already listed as a title: '+tit+'.';
        const rtit = lst.find(x => relTitles[x]);
        if (rtit) return 'Already listed as a release title: '+rtit+'.';
        return null;
    };
    const view = () => m('fieldset.form',
        m('legend', 'Titles & Languages', HelpButton('titles')),
        Help('titles',
            m('p',
                'List of titles for this visual novel, one for each language it is available in.', m('br'),
                'Each title must correspond to an existing release. Titles that are not attributed to a certain release should be included as aliases instead.',
            ),
            m('p', m('strong', 'Main title: '),
                'The title for the language that the script was originally authored in.',
            ),
            m('p', m('strong', 'Official title: '),
                'Should be checked if the title comes from an official release, unchecked for fan translations.'
            ),
        ),
        data.titles.map(t => m('fieldset', {key: t.lang},
            m('label', { for: 'title-'+t.lang }, LangIcon(t.lang), langs[t.lang]),
            relLangs[t.lang] ? null : m('p', m('b', 'WARNING: '),
                'There is no corresponding release for this language. ',
                'If the visual novel is available in this language, please update the releases section to reflect that. ',
                'If not, this title should be moved to the aliases below instead.'
            ),
            m(Input, {
                id: 'title-'+t.lang, class: 'xw', maxlength: 300, required: true,
                placeholder: 'Title (in the original script)',
                data: t, field: 'title', focus: t.new,
            }),
            !t.latin && !mayRomanize.test(t.title) ? m('br') : m('span',
                m('br'),
                m(Input, {
                    class: 'xw', maxlength: 300, required: mustRomanize.test(t.title),
                    data: t, field: 'latin', placeholder: 'Romanization',
                    invalid: t.latin === t.title || mustRomanize.test(t.latin) ? 'Romanization should only contain characters in the latin alphabet.' : null,
                }),
            ),
            data.titles.length === 1 ? null : m('p',
                m('span', m('label.check',
                    m('input[type=radio]', { checked: t.lang === data.olang, oninput: ev => data.olang = t.lang }),
                    ' Main title '
                )),
                data.olang === t.lang ? null : m('span', m('label.check',
                    m('input[type=checkbox]', { checked: t.official, oninput: ev => t.official = ev.target.checked }),
                    ' Official title '
                )),
                t.lang === data.olang ? null : m('input[type=button][value=Remove]', {
                    onclick: () => data.titles = data.titles.filter(x => x !== t)
                }),
            ),
        )),
        m(DS.Button, {ds}, 'Add language'),
        data.titles.length > 0 ? null : m('p.invalid', 'At least one language must be selected.'),
        m('fieldset',
            m('br'),
            m('label[for=alias]', 'Aliases', HelpButton('alias')),
            m(Input, { id: 'alias', class: 'xw', rows: 4, type: 'textarea', data, field: 'alias', invalid: aliasInvalid() }),
            data.alias.match(/,/) ? m('p', 'Reminder: one alias per line!') : null,
        ),
        Help('alias', m('p',
            'List of additional titles or abbreviations. One line for each alias. ', m('br'),
            'Can include both official titles and unofficial titles used around net. ', m('br'),
            'Titles that are listed above or used for releases should not be added here!'
        )),
    );
    return {view};
};


const Relations = initVnode => {
    const {data} = initVnode.attrs;
    const ds = new DS(DS.VNs, {
        onselect: obj => data.relations.push({vid: obj.id, relation: 'sequel', official: true, title: obj.title}),
        props: obj =>
            obj.id === data.id ? { selectable: false, append: m('small', ' (this entry)') } :
            data.relations.find(v => v.vid === obj.id) ? { selectable: false, append: m('small', ' (already listed)') } : {},
    });
    const view = () => m('fieldset',
        m('label', 'Related VNs'),
        m('table', data.relations.map(v => m('tr', {key: v.vid},
            m('td', m(Button.Del, { onclick: () => data.relations = data.relations.filter(x => x !== v) })),
            m('td', m('small', v.vid, ': '), m('a[target=_blank]', { href: '/'+v.vid }, v.title)),
            m('td',
                'is an ',
                m('label',
                    m('input[type=checkbox]', { checked: v.official, oninput: e => v.official = e.target.checked }),
                    ' official '
                ),
                m(Select, { data: v, field: 'relation', options: vndbTypes.vnRelation }),
                ' of this VN',
            ),
        ))),
        m(DS.Button, { ds, class: 'mw' }, 'Add visual novel'),
    );
    return {view};
};


const Anime = initVnode => {
    const {data} = initVnode.attrs;
    const ds = new DS(DS.Anime(false), {
        onselect: obj => data.anime.push({aid: obj.id, title_romaji: obj.title_romaji, title_kanji: obj.title_kanji}),
        props: obj => data.anime.find(a => a.aid === obj.id) ? { selectable: false, append: m('small', ' (already listed)') } : {},
    });
    const view = () => m('fieldset',
        m('label', 'Related anime'),
        m('table', data.anime.map(a => m('tr', {key: a.aid},
            m('td', m(Button.Del, { onclick: () => data.anime = data.anime.filter(x => x !== a) })),
            m('td', m('small', 'a', a.aid, ': '), m('a[target=_blank]', { href: 'https://anidb.net/anime/'+a.aid }, a.title_romaji)),
        ))),
        m(DS.Button, { ds, class: 'mw' }, 'Add anime'),
    );
    return {view};
};


const Staff = initVnode => {
    const {data} = initVnode.attrs;
    let id = 0;
    data.staff.forEach(s => s._id = ++id);

    const newds = eid => new DS(DS.Staff, {
        onselect: obj => data.staff.push({sid: obj.sid, aid: obj.id, title: obj.title, alttitle: obj.alttitle, eid, role: 'staff', note: '', _id: ++id}),
    });
    const ds = Object.fromEntries([null].concat(data.editions).map(e => [e?e.eid:'', newds(e?e.eid:null)]));

    const view = () => [ [null].concat(data.editions).map(e => m('fieldset.form', {key: e?e.eid:''},
        m('legend', !e ? 'Original edition' : e.name === '' ? 'Unnamed edition' : e.name),
        e ? m('fieldset.full',
            m(Input, { data: e, field: 'name', maxlength: 150, required: true, placeholder: 'Edition title', class: 'lw' }),
            m(Select, { data: e, field: 'lang', class: 'mw', options: [[null,'Original language']].concat(vndbTypes.language) }),
            m('label.check', ' ',
                m('input[type=checkbox]', { checked: e.official, oninput: ev => e.official = ev.target.checked }),
                ' official'
            ),
            m('button[type=button][style=margin-left:30px]', { onclick: () => {
                data.staff = data.staff.filter(s => s.eid !== e.eid);
                data.editions = data.editions.filter(x => x !== e);
            }}, 'remove edition'),
        ) : null,
        m('table.full.stripe',
            m('thead', m('tr',
                m('td'),
                m('td', 'Staff'),
                m('td', 'Role'),
                m('td', 'Note'),
                m('td'),
            )),
            m('tbody', data.staff.filter(s => s.eid === (e?e.eid:null)).map(s => m('tr', {key: s._id},
                m('td', m('small', s.sid)),
                m('td', m('a[target=_blank]', { href: '/'+s.sid }, s.title), ' ', s.title !== s.alttitle ? s.alttitle : ''),
                m('td', m(Select, { data: s, field: 'role', options: vndbTypes.creditType })),
                m('td', m(Input, { data: s, field: 'note', maxlength: 250, class: 'lw' })),
                m('td', m(Button.Del, { onclick: () => data.staff = data.staff.filter(x => x !== s) })),
            ))),
            m('tfoot', m('tr', m('td'), m('td[colspan=4]',
                data.staff.filter(s => s.eid === (e?e.eid:null)).anyDup(s => [s.aid,s.role])
                ? m('p.invalid', 'List contains duplicate staff with the same role.') : null,
                m(DS.Button, { ds: ds[e?e.eid:''] }, 'Add staff'),
            ))),
        ),
    )), m('fieldset.form', m('fieldset.full',
        m('button[type=button]', { onclick: () => {
            const eid = range(0,500).find(n => !data.editions.find(e => e.eid === n));
            data.editions.push({ eid, name: '', lang: null, official: true });
            ds[eid] = newds(eid);
        }}, 'Add edition'),
    ))];
    return {view};
};


const Cast = initVnode => {
    const {data} = initVnode.attrs;
    let id = 0;
    data.seiyuu.forEach(s => s._id = ++id);
    let newcid = {v: data.chars.length > 0 ? data.chars[0].id : null };

    const ds = new DS(DS.Staff, {
        onselect: obj => data.seiyuu.push({ aid: obj.id, sid: obj.sid, cid: newcid.v, note: '', title: obj.title, alttitle: obj.alttitle, _id: ++id }),
    });
    const charOptions = data.chars.map(c => [c.id, c.title + ' ('+c.id+')']);
    const charIds = Object.fromEntries(data.chars.map(c => [c.id,true]));
    const view = () => m('fieldset.form',
        !data.id ? m('p',
            'Voice actors can be added to this visual novel only after character entries have been created for it. ', m('br'),
            'To do so, continue to create this entry without cast, then create appropriate character entries, and finally come back to this form to edit the visual novel.',
        ) : data.chars.length === 0 ? m('p',
            'This visual novel does yet not have any characters associated with it. First ',
            m('a[target=_blank]', { href: '/'+data.id+'/addchar' }, 'add the appropriate character entries'),
            ' and then come back to this form to assign voice actors.',
        ) : m('table.full.stripe',
            m('thead', m('tr',
                m('td', 'Character'),
                m('td', 'Cast'),
                m('td', 'Note'),
                m('td'),
            )),
            m('tbody', data.seiyuu.map(s => m('tr', {key:s._id},
                m('td', m(Select, { data: s, field: 'cid', options:
                    charOptions.concat(charIds[s.cid] ? [] : [[s.cid, '(deleted or moved character: '+s.cid+')']]) })),
                m('td', m('small', s.sid, ': '), m('a[target=_blank]', {href: '/'+s.sid}, s.title), ' ', s.alttitle && s.title !== s.alttitle ? s.alttitle : null),
                m('td', m(Input, { data: s, field: 'note', maxlength: 250, class: 'lw' })),
                m('td', m(Button.Del, { onclick: () => data.seiyuu = data.seiyuu.filter(x => x !== s) })),
            ))),
            m('tfoot', m('tr', m('td[colspan=4]',
                data.seiyuu.anyDup(s => [s.aid,s.cid]) ? m('p.invalid', 'List contains duplicate cast roles') : null,
                m('br'),
                m('strong', 'Add cast'),
                m('br'),
                m(Select, { data: newcid, field: 'v', options: charOptions }),
                ' voiced by ',
                m(DS.Button, { ds }, 'select voice actor'),
            ))),
        )
    );
    return {view};
};


const Screenshots = initVnode => {
    const {data} = initVnode.attrs;
    const newds = s => new DS(DS.Releases(data.releases), { onselect: obj => s.rid = obj.id });
    const ds = Object.fromEntries(data.screenshots.map(s => [s.scr,newds(s)]));
    let addrel = null;
    const addds = new DS(DS.Releases(data.releases), { onselect: obj => addrel = obj });

    const uploadApi = new ImageUploadApi('sf', img => data.screenshots.push({ scr: img.id, rid: addrel.id, info: img }));
    const uploadSubmit = ev => {
        ev.stopPropagation();
        ev.preventDefault();
        uploadApi.submit($('#file'), 10 - data.screenshots.length);
    };

    const view = () => m('fieldset.form',
        !data.id ? m('p',
            'Screenshots can be added to this visual novel only after release entries have been created for it. ', m('br'),
            'To do so, continue to create this entry without screenshots, then create appropriate release entries, and finally come back to this form to edit the visual novel.',
        ) : data.releases.length === 0 ? m('p',
            'This visual novel does yet not have any releases associated with it. First ',
            m('a[target=_blank]', { href: '/'+data.id+'/add' }, 'add the appropriate release entries'),
            ' and then come back to this form to upload screenshots.',
        ) : m('table.full.stripe',
            m('tbody', data.screenshots.map(s => m('tr', {key: s.scr},
                m('td[style=text-align:right;width:140px]', m(IVLink, { img: s.info, cat: 'scr' },
                    m('img', { ...imgsize(s.info, 136, 102), src: imgurl(s.info.id, 't') }),
                )),
                m('td',
                    m('p',
                        m(Button.Del, { onclick: () => data.screenshots = data.screenshots.filter(x => s !== x) }),
                        ' ', m('small', s.scr, ' / '),
                        ((res, rel) => [
                            rel ? 'image: ' : null, res,
                            rel ? [ ', release: ', rel ] : null,
                            rel === res ? ' ✔' : rel ? [ ' ❌',
                                m('br'),
                                m('b', 'WARNING: Resolutions do not match, please take screenshots with the correct resolution and make sure to crop them correctly!'),
                                m('br'),
                                '(Yes, your screenshots will likely get deleted even if they are off by 1 pixel, we can be anal about this stuff)'
                            ] : data.screenshots.find(x => x.rid === s.rid && (x.info.width !== s.info.width || x.info.height !== s.info.height)) ? [ ' ❌',
                                m('br'),
                                m('b', 'WARNING: Inconsistent image resolutions for the same release, please take screenshots with the correct resolution and make sure to crop them correctly!'),
                                m('br'),
                                '(Yes, your screenshots will likely get deleted even if they are off by 1 pixel, we can be anal about this stuff)'
                            ] : null,
                        ])(
                            s.info.width + 'x' + s.info.height,
                            (r => r && r.reso_x > 0 ? r.reso_x + 'x' + r.reso_y : null)(data.releases.find(r => r.id === s.rid))
                        ),
                    ),
                    m(DS.Button, { ds: ds[s.scr], class: 'xw' }, !s.rid ? m('b.invalid', 'No release selected') : (r =>
                        r ? m('span', Release(r,1)) : 'Moved or deleted release: '+s.rid
                    )(data.releases.find(r => r.id == s.rid))),
                    m(ImageFlag, { img: s.info }),
                ),
            ))),
            m('tfoot', m('tr', m('td'), m('td', m('br'), (free => [
                uploadApi.loading() ? uploadApi.Status() : free <= 0 ? m('p',
                    m('strong', 'Enough screenshots'), m('br'),
                    'The limit of 10 screenshots per visual novel has been reached. ',
                    'If you want to add a new screenshot, you need to remove one first, but please do not replace screenshots without a very good reason.',
                ) : m('p',
                    m('strong', 'Upload screenshots'), m('br'),
                    free, ' more screenshot', free === 1 ? '' : 's', ' can be added.', m('br'),
                    m(DS.Button, { ds: addds, class: 'xw' }, addrel ? m('span', Release(addrel,1)) : '-- select release --'),
                ),
                !uploadApi.loading() && free > 0 && addrel ? m(Form, { onsubmit: uploadSubmit },
                    m('input#file[type=file][required][multiple]', { accept: imageAccept, oninput: uploadSubmit }),
                    uploadApi.Status(),
                    m('p',
                        m('br'), m('strong', 'Important reminder'),
                        m('ul',
                          m('li', 'Screenshots must be in the native resolution of the game'),
                          m('li', 'Screenshots must not include window borders and should not have copyright markings'),
                          m('li', "Don't only upload event CGs"),
                        ),
                        'Read the ', m('a[target=_blank][href=/d2#6]', 'full guidelines'), ' for more information.'
                    ),
                ) : null,
            ])(10 - data.screenshots.length)))),
        ),
    );
    return {view};
};


widget('VNEdit', initVnode => {
    const data = initVnode.attrs.data;
    const api = new Api('VNEdit');

    const dupApi = new Api('VN');
    let dupCheck = !data.id;
    const dupData = () => ({
        hidden: true,
        search: data.titles.flatMap(t => [t.title,t.latin]).concat(data.alias.split("\n")).map(s => s?s.trim():'').filter(s => s.length > 0)
    });
    const onsubmit = () => !dupCheck ? api.call(data) : dupApi.call(dupData(),
        res => dupCheck = res.results.length ? res.results : false,
    );

    const hasCompleteRelease = data.releases.find(r => r.rtype === 'complete' && r.released <= RDate.today);

    const wikidata = { v: data.l_wikidata === null ? '' : 'Q'+data.l_wikidata };
    const geninfo = () => [
        m('h1', 'General info'),
        m(Titles, {data}),
        m('fieldset.form',
            m('legend', 'General info'),
            m('fieldset',
                m('label[for=description]', 'Description'),
                m(TextPreview, {
                    data, field: 'description',
                    header: m('b', '(English please!)'),
                    attrs: { id: 'description', rows: 8, maxlength: 10240 },
                }),
                m('p',
                    "Short description of the main story. ",
                    "Please do not include spoilers, and don't forget to list the source in case you didn't write the description yourself."
                ),
            ),
            m('fieldset',
                m('label[for=devstatus]', 'Development status'),
                m(Select, { id: 'devstatus', class: 'mw', data, field: 'devstatus', options: vndbTypes.devStatus }),
                data.devstatus === 0 && data.releases.length > 0 && !hasCompleteRelease ? m('p', m('b', 'WARNING: '),
                    'Development is marked as finished, but there is no complete release in the database.', m('br'),
                    'Please adjust the development status or ensure there is a completed release entry.', m('br'),
                    m('b', '"In development" should always be selected when the game is not yet available, even if the developer announced that development has finished!'),
                ) : data.devstatus !== 0 && hasCompleteRelease ? m('p', m('b', 'WARNING: '),
                    'Development is not marked as finished, but there is a complete release in the database.', m('br'),
                    'Please adjust the development status or set the release to partial or TBA.',
                ) : null,
            ),
            data.devstatus !== 1 ? m('fieldset',
                m('label[for=length]', 'Length'),
                m(Select, { id: 'length', class: 'mw', data, field: 'length', options: vndbTypes.vnLength }),
                ' (only displayed if there are no length votes)',
            ) : null,
            m('fieldset',
                m('label[for=wikidata]', 'Wikidata ID'),
                m(Input, { id: 'wikidata', class: 'mw',
                    data: wikidata, field: 'v',
                    pattern: '^Q?[1-9][0-9]{0,8}$',
                    oninput: v => { v = v.replace(/[^0-9]/g, ''); data.l_wikidata = v?v:null; wikidata.v = v?'Q'+v:''; },
                }),
            ),
            m('fieldset',
                m('label[for=renai]', 'Renai.us link'),
                'https://renai.us/game/',
                m(Input, { id: 'renai', class: 'mw', data, field: 'l_renai', maxlength: 100 }),
                '.shtml',
            ),
        ),
        m('fieldset.form',
            m('legend', 'Database relations'),
            m(Relations, {data}),
            m(Anime, {data}),
        ),
    ];

    const tabs = [
        [ 'gen', 'General info', geninfo ],
        [ 'staff', 'Staff', () => [ m('h1', 'Staff'), m(Staff, {data}) ] ],
        [ 'cast', 'Cast', () => [ m('h1', 'Cast'), m(Cast, {data}) ] ],
        [ 'screenshots', 'Screenshots', () => [ m('h1', 'Screenshots'), m(Screenshots, {data}) ] ],
    ];

    const view = () => dupCheck ? m(Form, {api: dupApi, onsubmit},
        m('article',
            m('h1', 'Add visual novel'),
            m(Titles, {data}),
        ),
        dupCheck === true || !dupApi.saved(dupData()) ? null : m('article',
            m('h1', 'Possible duplicates'),
            m('p',
                'The following is a list of visual novels that match the titles(s) you gave. ',
                'Please check this list to avoid creating a duplicate visual novel entry.', m('br'),
                'Be especially wary of items that have been deleted! To see why an entry has been deleted, click on its title.'
            ),
            m('ul', dupCheck.map(v => m('li', {key: v.id},
                m('a[target=_blank]', { href: '/'+v.id }, v.title),
                v.hidden ? m('b', ' (deleted)') : null,
            ))),
        ),
        m('article.submit',
            dupCheck === true || !dupApi.saved(dupData())
            ? m('input[type=submit][value=Continue]')
            : m('input[type=button][value=Continue anyway]', { onclick: () => dupCheck = false }),
            dupApi.Status(),
        ),
    ) : m(Form, {api, onsubmit},
        m(FormTabs, {tabs}),
        m(EditSum, {data,api}),
    );
    return {view};
});
