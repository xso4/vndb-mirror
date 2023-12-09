widget('DocEdit', initVnode => {
    const data = initVnode.attrs.data;
    const api = new Api('DocEdit');
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
