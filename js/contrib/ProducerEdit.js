widget('ProducerEdit', initVnode => {
    const data = initVnode.attrs.data;
    const api = new Api('ProducerEdit');

    const dupApi = new Api('Producers');
    let dupCheck = !data.id;
    const names = () => ([data.name, data.latin].concat(data.alias.split("\n")).map(s => s?s.trim():'').filter(s => s.length > 0));
    const nameChange = () => {dupCheck = !!dupCheck};
    const onsubmit = () => !dupCheck ? api.call(data) : dupApi.call(
        {search: names()},
        res => dupCheck = res.results.length ? res.results : false,
    );

    const lang = new DS(DS.LocLang, {onselect: obj => data.lang = obj.id});
    const wikidata = { v: data.l_wikidata === null ? '' : 'Q'+data.l_wikidata };
    const fields = () => [
        m('fieldset',
            m('label[for=type]', 'Type'),
            m('select.mw[id=type]', { oninput: ev => data.type = vndbTypes.producerType[ev.target.selectedIndex][0] },
                vndbTypes.producerType.map(([v,t]) => m('option', { selected: v === data.type }, t))
            ),
        ),
        m('fieldset',
            m('label[for=lang]', { class: data.lang ? null : 'invalid' }, 'Primary language'),
            m(DS.Button, {class: 'mw', ds:lang}, data.lang ? Object.fromEntries(vndbTypes.language)[data.lang] : '-- select --'),
            data.lang ? null : m('p.invalid', 'No language selected.'),
        ),
        m('fieldset',
            m('label[for=website]', 'Website'),
            m(Input, { id: 'website', class: 'xw', type: 'weburl', data, field: 'website' }),
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
            m('label[for=description]', 'Description'),
            m(TextPreview, {
                data, field: 'description',
                header: m('b', '(English please!)'),
                attrs: { id: 'description', rows: 6, maxlength: 5000 },
            }),
        ),
    ];

    const prod = new DS(DS.Producers, {
        onselect: obj => data.relations.push({pid: obj.id, name: obj.name, relation: 'old' }),
        props: obj =>
            obj.id === data.id ? { selectable: false, append: m('small', ' (this producer)') } :
            data.relations.find(p => p.pid === obj.id) ? { selectable: false, append: m('small', ' (already listed)') } : {},
    });
    const relations = () => m('fieldset',
        m('label', 'Related producers'),
        data.relations.length === 0
        ? m('p', 'No producers selected.')
        : m('table', data.relations.map(p => m('tr', {key: p.pid},
            m('td',
                m(Button.Del, { onclick: () => data.relations = data.relations.filter(x => x !== p) }), ' ',
                m('select', { oninput: ev => p.relation = vndbTypes.producerRelation[ev.target.selectedIndex][0] },
                    vndbTypes.producerRelation.map(([id,lbl]) => m('option', { selected: id === p.relation }, lbl))
                ),
            ),
            m('td', m('small', p.pid, ': '), m('a[target=_blank]', { href: '/'+p.pid }, p.name)),
        ))),
        m(DS.Button, { ds: prod, class: 'mw' }, 'Add producer'),
    );

    const view = () => m(Form, {api: dupCheck ? dupApi : api, onsubmit},
        m('article',
            m('h1', data.id ? 'Edit producer' : 'Add producer'),
            m('fieldset.form',
                m('fieldset',
                    m('label[for=name]', 'Name (original)'),
                    m(Input, { class: 'xw', required: true, maxlength: 200, data, field: 'name', oninput: nameChange }),
                ),
                !data.latin && !mayRomanize.test(data.name) ? null : m('fieldset',
                    m('label[for=name]', 'Name (latin)'),
                    m(Input, {
                        class: 'xw', required: mustRomanize.test(data.name), maxlength: 200, data, field: 'latin', placeholder: 'Romanization', oninput: nameChange,
                        invalid: mayRomanize.test(data.latin) ? 'Romanization should only contain characters in the latin alphabet.' : null,
                    }),
                ),
                m('fieldset',
                    m('label[for=alias]', 'Aliases'),
                    m(Input, {
                        class: 'xw', type: 'textarea', rows: 3, maxlength: 500, data, field: 'alias', oninput: nameChange,
                        invalid: names().anyDup() ? 'List contains duplicate aliases.' : '',
                    }),
                    m('p', '(Un)official aliases, separated by a newline.'),
                ),
                dupCheck === false ? fields() : [],
            ),
            dupCheck === false ? m('fieldset.form',
                m('legend', 'Database relations'),
                relations()
            ) : null,
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
                    'The following is a list of producers that match the name(s) you gave. ',
                    'Please check this list to avoid creating a duplicate producer entry.',
                ),
                m('ul', dupCheck.map(p => m('li', m('a[target=_blank]', { href: '/'+p.id }, p.name)))),
            ),
            m('article.submit',
                m('input[type=button][value=Continue anyway]', { onclick: () => dupCheck = false }),
            ),
        ],
    );
    return {view};
});
