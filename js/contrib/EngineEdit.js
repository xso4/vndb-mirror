widget('EngineEdit', vnode => {
    const data = vnode.attrs.data;
    const api = new Api('EngineEdit');
    const view = () => m(Form, {api, onsubmit: () => api.call(data)}, m('article',
        m('h1', 'Edit Engine: '+data.name),
        m('fieldset.form',
            m('fieldset',
                m('label[for=name]', 'Name'),
                m(Input, { id: 'name', class: 'mw', required: true, maxlength: 128, data, field: 'name' }),
                m('p', 'Warning: changing the name affects all releases that have this engine assigned to it, including older revisions.'),
            ),
            m('fieldset',
                m('label', 'State'),
                m('label.check', m('input[type=radio]', { checked: data.state === 0, oninput: () => data.state = 0 }), ' New '),
                m('label.check', m('input[type=radio]', { checked: data.state === 1, oninput: () => data.state = 1 }), ' Approved '),
                m('label.check', m('input[type=radio]', { checked: data.state === 2, oninput: () => data.state = 2 }), ' Deleted'),
                m('p', '"New" and "Approved" are functionally the same thing, but the distinction may be helpful with moderating new entries.'),
                m('p', '"Deleted" entries are not available when editing a release entry, but may still be associated with existing releases and older revisions.'),
            ),
            m('fieldset',
                m('label[for=description]', 'Description'),
                m(TextPreview, {
                    attrs: { id: 'description', maxlength: 10240, rows: 5 },
                    data, field: 'description',
                }),
            ),
            m('fieldset',
                m('input[type=submit][value=Save]'),
                m('input[type=button][value=Cancel]', { onclick: () => location.href = '/r/engines?'+data.ref }),
                api.Status(),
            ),
        ),
    ));
    return {view};
});
