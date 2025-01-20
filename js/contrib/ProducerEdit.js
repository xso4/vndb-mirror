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
    const fields = () => [
        m('fieldset',
            m('label[for=type]', 'Type'),
            m(Select, { id: 'type', class: 'mw', data, field: 'type', options: vndbTypes.producerType }),
        ),
        m('fieldset',
            m('label[for=lang]', { class: data.lang ? null : 'invalid' }, 'Primary language'),
            m(DS.Button, {class: 'mw', ds:lang}, data.lang ? Object.fromEntries(vndbTypes.language)[data.lang] : '-- select --'),
            data.lang ? null : m('p.invalid', 'No language selected.'),
        ),
        m('fieldset',
            m('label[for=description]', 'Description'),
            m(TextPreview, {
                data, field: 'description',
                header: m('b', '(English please!)'),
                attrs: { id: 'description', rows: 6, maxlength: 5000 },
            }),
        ),
        m(ExtLinks, {type: 'producer', links: data.extlinks}),
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
                m(Select, { data: p, field: 'relation', options: vndbTypes.producerRelation }),
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
                        invalid: data.latin === data.name || mustRomanize.test(data.latin) ? 'Romanization should only contain characters in the latin alphabet.' : null,
                    }),
                ),
                m('fieldset',
                    m('label[for=alias]', 'Aliases'),
                    m(Input, {
                        class: 'xw', type: 'textarea', rows: 3, maxlength: 500, data, field: 'alias', oninput: nameChange,
                        invalid: names().anyDup() ? 'List contains duplicate aliases.' : '',
                    }),
                    data.alias.match(/,/) ? m('p', 'Reminder: one alias per line!') : null,
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
            m(EditSum, {data,api,type:'p'})
        ] : dupCheck === true ? [m('article.submit',
            m('input[type=submit][value=Continue]'),
            dupApi.Status(),
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
