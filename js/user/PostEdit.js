widget('PostEdit', initvnode => {
    const api = new Api('PostEdit');
    const data = initvnode.attrs.data;
    const view = () => m(Form, {api, onsubmit: () => api.call(data)},
        m('article',
            m('h1', 'Edit post'),
            m('fieldset.form',
                m('fieldset',
                    m('label', 'Post'),
                    m('a[target=_blank]', { href: '/'+data.id+'.'+data.num }, '#', data.num, ' on ', data.id),
                ),
                !data.can_mod ? null : m('fieldset',
                    m('label.check',
                        m('input[type=checkbox]', { checked: data.hidden !== null, oninput: ev => data.hidden = ev.target.checked ? '' : null }),
                        ' Hidden'
                    ),
                ),
                !data.can_mod || data.hidden === null ? null : m('fieldset',
                    m('label[for=hidden]', 'Deletion reason'),
                    m(Input, { id: 'hidden', class: 'lw', data, field: 'hidden' }),
                ),
                !data.can_mod ? null : m('fieldset',
                    m('label.check',
                        m('input[type=checkbox]', { checked: data.nolastmod, oninput: ev => data.nolastmod = ev.target.checked }),
                        " Don't update last modification timestamp"
                    ),
                ),
            ),
            m('fieldset.form',
                m('fieldset',
                    m('label[for=msg]', 'Message'),
                    m(TextPreview, {
                        data, field: 'msg',
                        attrs: { id: 'msg', required: true, maxlength: 32768, rows: 12 },
                        header: m('b', ' (English please!)'),
                    }),
                ),
            ),
            !data.can_mod ? null : m('fieldset.form',
                m('legend', 'DANGER ZONE'),
                m('fieldset',
                    m('input[type=checkbox]', { checked: data.delete, oninput: ev => data.delete = ev.target.checked }),
                    ' Permanently delete this post. This action can not be reverted, only do this with obvious spam!',
                )
            ),
        ),
        m('article.submit',
            m('input[type=submit][value=Submit]'),
            api.Status(),
        ),
    );
    return {view};
});
