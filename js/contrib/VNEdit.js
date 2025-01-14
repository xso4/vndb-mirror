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
    ];

    const tabs = [
        [ 'gen', 'General info', geninfo ],
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
