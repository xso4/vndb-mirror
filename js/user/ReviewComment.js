widget('ReviewComment', vnode => {
    const data = vnode.attrs.data;
    data.msg = '';
    const api = new Api('ReviewComment');
    const view = () => m(Form, {api, onsubmit: () => api.call(data)}, m('article.submit',
        m(TextPreview, {
            data, field: 'msg',
            attrs: { rows: 4, cols: 50, required: true, maxlength: 32768 },
            header: [
                m('strong', 'Comment'),
                m('b', ' (English please!) '),
                m('a[href=/d9#4][target=_blank]', 'Formatting'),
            ],
        }),
        m('input[type=submit][value=Submit]'),
        m('span.spinner', { class: api.loading() ? '' : 'invisible' }),
        api.error ? m('p.formerror', api.error) : null,
    ));
    return {view};
});

