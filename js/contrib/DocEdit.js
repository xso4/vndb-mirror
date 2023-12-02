widget('DocEdit', initVnode => {
    const data = initVnode.attrs.data;
    const api = new Api('DocEdit');

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

    const view = () => m(Form, {api, onsubmit: () => api.call(data) },
        m('article',
            m('h1', 'Edit '+data.id),
            m('fieldset.form',
                m('fieldset',
                    m('label[for=title]', 'Title'),
                    m(Input, { class: 'xw', required: true, maxlength: 200, data, field: 'title' }),
                ),
            ),
            m('fieldset.form', m(TextPreview, {
                data, field: 'content',
                type: 'markdown', full: true,
                attrs: { rows: 50 },
                header: [
                    'HTML and MultiMarkdown supported, which is ',
                    m('a[href=https://daringfireball.net/projects/markdown/basics][target=_blank]', 'Markdown'),
                    ' with some ',
                    m('a[href=http://fletcher.github.io/MultiMarkdown-5/syntax.html][target=_blank]', 'extensions'),
                    '.'
                ]
            })),
        ),
        m(EditSum, {data,api}),
    );
    return {view};
});
