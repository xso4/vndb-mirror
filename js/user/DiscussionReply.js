widget('DiscussionReply', vnode => {
    const data = vnode.attrs.data;
    data.msg = '';
    const api = new Api('DiscussionReply');
    const view = () => m(Form, {api, onsubmit: () => api.call(data)}, m('article.submit',
        data.old ? [ m('p.center',
            'This thread has not seen any activity for more than 6 months, but you may still ',
            m('a[href=#]', { onclick: ev => {ev.preventDefault(); data.old = false} }, 'reply'),
            ' if you have something relevant to add.',
            m('br'),
            'If your message is not directly relevant to this thread, perhaps it\'s better to ',
            m('a[href=/t/ge/new]', 'create a new thread'), ' instead.'
        )] : [
            m(TextPreview, {
                data, field: 'msg',
                attrs: { rows: 4, cols: 50, required: true, maxlength: 32768 },
                header: [
                    m('strong', 'Quick reply'),
                    m('b', ' (English please!) '),
                    m('a[href=/d9#4][target=_blank]', 'Formatting'),
                ],
            }),
            m('input[type=submit][value=Submit]'),
            m('span.spinner', { class: api.loading() ? '' : 'invisible' }),
            api.error ? m('p.formerror', api.error) : null,
        ]
    ));
    return {view};
});
