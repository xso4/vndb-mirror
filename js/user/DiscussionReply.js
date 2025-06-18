let data;
let focus = null;

const addreply = id => {
    if (data.msg.length > 0 && !data.msg.match(/\n$/)) data.msg += "\n";
    data.msg += id + ': ';
    focus = v => {
        v.dom.value = data.msg;
        v.dom.focus();
        v.dom.selectionStart = data.msg.length;
        focus = null;
    };
    m.redraw();
};

$$('.js-post-reply').forEach(l => l.onclick = ev => {
    ev.preventDefault();
    addreply(l.getAttribute('data-id'));
});

widget('DiscussionReply', vnode => {
    data = vnode.attrs.data;
    data.msg = '';
    const api = new Api(data.tid ? 'DiscussionReply' : 'ReviewComment');

    if (location.hash.match(/#reply-(.+)/)) addreply(location.hash.substring(7));

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
                attrs: { rows: 4, cols: 50, required: true, maxlength: 32768, focus, onupdate: focus },
                header: [
                    m('strong', 'Quick reply'),
                    m('b', ' (English please!) '),
                    m('a[href=/d9#4][target=_blank]', 'Formatting'),
                ],
            }),
            m('input[type=submit][value=Submit]'),
            api.Status(),
        ]
    ));
    return {view};
});
