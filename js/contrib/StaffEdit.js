widget('StaffEdit', initVnode => {
    const data = initVnode.attrs.data;
    const api = new Api('StaffEdit');
    if (!data.l_pixiv) data.l_pixiv = '';

    const dupApi = new Api('Staff');
    let dupCheck = !data.id;
    const nameChange = () => {dupCheck = !!dupCheck};
    const onsubmit = () => !dupCheck ? api.call(data) : dupApi.call(
        {search: data.alias.flatMap(({name,latin}) => [name,latin]).filter(x => x)},
        res => dupCheck = res.results.length ? res.results : false,
    );

    const names = () => m('table.names',
        m('thead', m('tr',
            m('td'),
            m('td.tc_name', 'Name (original script)'),
            m('td.tc_name', 'Romanization'),
            m('td'),
        )),
        m('tfoot', m('tr.alias_new',
            m('td'),
            m('td[colspan=3]',
                data.alias.anyDup(({name,latin}) => [name,latin])
                ? m('p.invalid', 'There are duplicate aliases.') : null,
                m('a[href=#]', { onclick: () => {
                    data.alias.push({
                        aid: Math.min(0, ...data.alias.map(a => a.aid)) - 1,
                        name: '',
                        latin: '',
                        focus: true,
                    });
                    return false;
                }}, 'Add alias'),
            ),
        )),
        m('tbody', data.alias.map(a => m('tr', {key: a.aid},
            m('td', m('input[type=radio]', { checked: a.aid === data.aid, onclick: () => data.aid = a.aid })),
            m('td.tc_name', m(Input,
                { required: true, maxlength: 200, data: a, field: 'name', oninput: nameChange, focus: a.focus }
            )),
            m('td.tc_name', !a.latin && !mayRomanize.test(a.name) ? m('br') : m('span', m(Input, {
                required: mustRomanize.test(a.name), maxlength: 200, data: a, field: 'latin', placeholder: 'Romanization', oninput: nameChange,
                invalid: mayRomanize.test(a.latin) ? 'Romanization should only contain characters in the latin alphabet.' : null,
            }))),
            m('td',
                a.aid === data.aid ? m('small', 'primary') :
                a.wantdel ? m('b', 'still referenced') :
                a.inuse ? m('small', 'referenced') :
                m(Button.Del, { onclick: () => nameChange(data.alias = data.alias.filter(x => x !== a)) }),
            ),
        ))),
    );

    const lang = new DS(DS.LocLang, {onselect: obj => data.lang = obj.id});
    const wikidata = { v: data.l_wikidata === null ? '' : 'Q'+data.l_wikidata };
    const fields = () => [
        m('fieldset',
            m('label[for=description]', 'Biography'),
            m(TextPreview, {
                data, field: 'description',
                header: m('b', '(English please!)'),
                attrs: { id: 'description', rows: 6, maxlength: 5000 },
            }),
        ),
        m('fieldset',
            m('label[for=gender]', 'Gender'),
            m('select.mw', { oninput: ev => data.gender = ['unknown','m','f'][ev.target.selectedIndex] },
                m('option', { selected: data.gender === 'unknown' }, 'Unknown or N/A'),
                m('option', { selected: data.gender === 'm' }, 'Male'),
                m('option', { selected: data.gender === 'f' }, 'Female'),
            )
        ),
        m('fieldset',
            m('label[for=lang]', { class: data.lang ? null : 'invalid' }, 'Primary language'),
            m(DS.Button, {class: 'mw', ds:lang}, data.lang ? Object.fromEntries(vndbTypes.language)[data.lang] : '-- select --'),
            data.lang ? null : m('p.invalid', 'No language selected.'),
        ),
        m('fieldset',
            m('label[for=l_site]', 'Website'),
            m(Input, { id: 'l_site', class: 'xw', type: 'weburl', data, field: 'l_site' }),
        ),
        m('fieldset',
            m('label[for=wikidata]', 'Wikidata ID'),
            m(Input, { id: 'wikidata', class: 'mw',
                data: wikidata, field: 'v',
                pattern: '^Q?[1-9][0-9]{0,8}$',
                oninput: v => { v = v.replace(/[^0-9]/g, ''); data.l_wikidata = v?v:null; wikidata.v = v?'Q'+v:''; },
            }),
        ),
        m('fieldset',
            m('label[for=twitter]', 'Twitter handle'),
            m(Input, { id: 'twitter', class: 'mw', data, field: 'l_twitter', maxlength: 16, pattern: /^\S+$/ }),
        ),
        m('fieldset',
            m('label[for=anidb]', 'AniDB Creator ID'),
            m(Input, { id: 'anidb', class: 'mw', data, field: 'l_anidb', type: 'number', oninput: v => data.l_anidb = v > 0 ? v : null }),
        ),
        m('fieldset',
            m('label[for=pixiv]', 'Pixiv ID'),
            m(Input, { id: 'pixiv', class: 'mw', data, field: 'l_pixiv', type: 'number', oninput: v => data.l_pixiv = v > 0 ? v : '' }),
        ),
    ];

    const view = () => m(Form, {api: dupCheck ? dupApi : api, onsubmit},
        m('article.staffedit',
            m('h1', data.id ? 'Edit staff' : 'Add staff'),
            m('fieldset.form',
                m('fieldset',
                    m('label', 'Names'),
                    names(),
                ),
                dupCheck === false ? fields() : [],
            ),
        ),
        dupCheck === false ? [
            m(EditSum, {data,api})
        ] : dupCheck === true ? [m('article.submit',
            m('input[type=submit][value=Continue]'),
            dupApi.loading() ? m('span.spinner') : null,
            dupApi.error ? m('b', m('br'), dupApi.error) : null,
        )] : [
            m('article',
                m('h1', 'Possible duplicates'),
                m('p',
                    'The following is a list of staff that match the name(s) you gave. ',
                    'Please check this list to avoid creating a duplicate staff entry.',
                ),
                m('ul', dupCheck.map(s => m('li',
                    m('a[target=_blank]', { href: '/'+s.id }, s.title),
                    s.alttitle ? m('small', ' (', s.alttitle, ')') : null,
                ))),
            ),
            m('article.submit',
                m('input[type=button][value=Continue anyway]', { onclick: () => dupCheck = false }),
            ),
        ],
    );
    return {view};
});
