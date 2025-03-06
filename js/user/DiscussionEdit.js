widget('DiscussionEdit', vnode => {
    const data = vnode.attrs.data;
    const api = new Api('DiscussionEdit');

    const delApi = new Api('DiscussionDelete');
    let del = false;

    const check = (field, label) => m('fieldset', m('label.check',
        m('input[type=checkbox]', { checked: data[field], onclick: ev => data[field] = ev.target.checked }),
        ' ', label
    ));
    const title = () => [
        m('fieldset',
            m('label[for=title]', 'Thread title'),
            m(Input, { class: 'xw', id: 'title', data, field: 'title', maxlength: 50 }),
        ),
        data.can_mod ? check('locked', 'Locked') : null,
        data.can_mod ? check('hidden', 'Hidden') : null,
        data.can_mod ? check('private', 'Private') : null,
        data.can_mod && data.tid ? check('nolastmod', "Don't update last modification timestamp") : null,
    ];

    const boardDs = new DS(DS.Boards, {
        onselect: obj => data.boards.push(obj),
        props: obj => data.boards.find(x => x.id === obj.id) ? { selectable: false, append: m('small', ' (already listed)') } : {},
    });
    const boards = () => m('fieldset',
        m('label[for=addboard]', 'Boards'),
        data.can_mod ? check('boards_locked', 'Lock boards') : null,
        data.boards_locked ? m('p',
            'The boards are locked, only a moderator can move this thread.',
        ) : m('p',
            'You can link this thread to multiple boards. Every visual novel, producer and user in the database has its own board,',
            ' but you can also use the \"General Discussions\" and \"VNDB Discussions\" boards for threads that do not fit at a particular database entry.',
        ),
        m('table', data.boards.map(b => m('tr', {key: b.id}, m('td',
            data.boards_locked ? '-' : m(Button.Del, { onclick: () => data.boards = data.boards.filter(x => x !== b) }),
            ' ', vndbTypes.boardType.find(x => x[0] === b.btype)[1],
            b.iid ? [
                ' > ', m('small', b.iid, ': '),
                m('a', {href:'/'+b.iid}, b.title && b.title !== b.iid ? b.title : '(deleted)'),
            ] : null,
        )))),
        data.boards_locked ? null : m(DS.Button, {ds:boardDs}, 'Add board'),
        data.boards.length === 0 ? m('p.invalid', 'No boards selected.') : null,
    );

    const msg = () => m('fieldset',
        m('label[for=msg]', 'Message'),
        m(TextPreview, {
            data, field: 'msg',
            attrs: { rows: 12, cols: 50, required: true, maxlength: 32768 },
            header: [
                m('b', ' (English please!) '),
                m('a[href=/d9#4][target=_blank]', 'Formatting'),
            ],
        }),
    );

    const poll = data.poll || { question: '', options: ['',''], max_options: 1 };
    const haspoll = !!data.poll;
    const pollv = () => [
        m('fieldset', m('label.check',
            m('input[type=checkbox]', { checked: !!data.poll, onclick: ev => data.poll = ev.target.checked ? poll : null }),
            ' Enable poll',
        )),
        haspoll ? m('fieldset', m('p.standout', 'Existing votes will be reset if any changes are made to these options!')) : null,
        data.poll ? m('fieldset',
            m('label[for=pollq]', 'Poll question'),
            m(Input, { class: 'xw', id: 'pollq', data: poll, field: 'question', required: true, maxlength: 100 }),
        ) : null,
        data.poll ? m('fieldset',
            m('label', 'Options'),
            m('table', poll.options.map((v,i) => m('tr', m('td',
                '#', i+1, ' ',
                m(Input, { class: 'xw', data: poll.options, field: i, maxlength: 100, required: true }),
                poll.options.length > 2 ? m(Button.Del, { onclick: () => {
                    poll.options.splice(i,1);
                    if (poll.max_options > poll.options.length) poll.max_options = poll.options.length;
                } }) : null,
            )))),
            poll.options.length < 20 ? m('button[type=button]', { onclick: () => poll.options.push('') }, 'Add option') : null,
        ) : null,
        data.poll ? m('fieldset',
            m(Select, { class: 'sw', data: poll, field: 'max_options', options: range(1, poll.options.length).map(x=>[x,x]) }),
            ' Number of options people are allowed to choose.',
        ) : null,
    ];

    const view = () => [ m(Form, {api, onsubmit: () => api.call(data)},
        m('article',
            m('h1', data.tid ? 'Edit thread' : 'Create new thread'),
            m('fieldset.form', title(), boards()),
            m('fieldset.form', msg()),
            m('fieldset.form', pollv()),
        ),
        m('article.submit',
            m('input[type=submit][value=Submit]'),
            api.Status(),
        ),
    ), data.tid && data.can_mod ? m(Form, { api: delApi, onsubmit: () => delApi.call({id: data.tid}) },
        m('article',
            m('fieldset.form',
                m('legend', 'Delete thread'),
                m('fieldset', m('label.check',
                    m('input[type=checkbox]', { checked: del, oninput: ev => del = ev.target.checked }),
                    ' Delete this thread'
                )),
                del ? m('fieldset',
                    m('b', 'WARNING:'), ' Deleting a thread is a permanent action and cannot be reverted!', m('br'),
                    m('input[type=submit][value=Submit]'),
                    delApi.Status(),
                ) : null,
            )
        ),
    ) : null];
    return {view};
});
