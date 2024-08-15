widget('TagEdit', vnode => {
    const data = vnode.attrs.data;
    const api = new Api('TagEdit');
    var dups = [];

    const dsProps = obj =>
        obj.id === data.id ? { selectable: false, append: m('small', ' (this tag)') } :
        data.parents.find(x => x.parent === obj.id) ? { selectable: false, append: m('small', ' (already listed)') } : {};

    const parentDS = new DS(DS.Tags, {
        onselect: obj => data.parents.push({parent: obj.id, name: obj.name, main: data.parents.length === 0}),
        props: dsProps,
    });

    const mergeDS = new DS(DS.Tags, {
        onselect: obj => data.merge.push(obj),
        props: dsProps,
    });

    const names = () => m('fieldset.form',
        m('fieldset',
            m('label[for=name]', 'Primary name'),
            m(Input, { class: 'lw', id: 'name', data, field: 'name', required: true, maxlength: 250 }),
        ),
        m('fieldset',
            m('label[for=alias]', 'Aliases'),
            m(Input, { class: 'lw', rows: 5, type: 'textarea', id: 'alias', data, field: 'alias', maxlength: 1024 }),
            m('p', 'Tag name and aliases must be unique and self-describing.'),
            (l => l.length === 0 ? '' : m('p.invalid',
                'The following tag names are already in the database:',
                l.map(d => [m('br'), m('a[target=_blank]', {href: '/'+d.id}, d.name)]),
            ))([data.name].concat(data.alias.split("\n")).flatMap(s => dups.filter(d => d.name.toLowerCase() === s.trim().toLowerCase())))
        ),
    );

    const properties = () => m('fieldset.form',
        m('fieldset', m('label.check',
            m('input[type=checkbox]', { checked: data.searchable, oninput: e => data.searchable = e.target.checked }),
            ' Searchable (people can use this tag to find VNs)',
        )),
        m('fieldset', m('label.check',
            m('input[type=checkbox]', { checked: data.applicable, oninput: e => data.applicable = e.target.checked }),
            ' Applicable (people can apply this tag to VNs)',
        )),
        m('fieldset',
            m('label[for=cat]', 'Category'),
            m(Select, { class: 'mw', id: 'cat', data, field: 'cat', options: vndbTypes.tagCategory }),
        ),
        m('fieldset',
            m('label[for=defaultspoil]', 'Default spoiler level'),
            m(Select, { class: 'mw', id: 'defaultspoil', data, field: 'defaultspoil', options: spoilLevels }),
        ),
        m('fieldset',
            m('label[for=description]', 'Description'),
            m(TextPreview, {
                data, field: 'description',
                attrs: { id: 'description', required: true, rows: 12, maxlength: 10240 },
            }),
            m('p', 'What should the tag be used for? Having a good description helps users choose which tags to link to a VN.'),
        ),
    );

    const parents = () => m('fieldset.form', m('fieldset',
        m('label', 'Parent tags'),
        data.parents.length === 0
        ? m('p', 'No parent tags selected, which makes this a top-level tag.')
        : m('table', data.parents.map(g => m('tr', {key: g.parent},
            m('td', m(Button.Del, { onclick: () => {
                data.parents = data.parents.filter(x => x !== g);
                if (data.parents.length > 0 && !data.parents.find(x => x.main))
                    data.parents[0].main = true;
            }})),
            m('td', m('small', g.parent, ': '), m('a[target=_blank]', { href: '/'+g.parent }, g.name)),
            m('td', m('label',
                m('input[type=radio]', { checked: g.main, onclick: () => data.parents.forEach(x => x.main = x === g) }),
                ' primary'
            )),
        ))),
        m(DS.Button, { ds: parentDS, class: 'mw' }, 'Add parent tag'),
    ));

    const danger = () => [
        m('fieldset.form',
            m('legend', 'DANGER ZONE'),
            m('p', 'The options below affect tag votes and are therefore not visible in the edit history.'),
            m('p', 'Your edit summary is not visible anywhere unless you also changed something in the above fields.'),
        ),
        m('fieldset.form', m('fieldset',
            m('input[type=checkbox]', { checked: data.wipevotes, onclick: e => data.wipevotes = e.target.checked }),
            ' Delete all direct votes on this tag. WARNING: cannot be undone!',
            m('br'),
            m('small', 'Does not affect votes on child tags. Old votes may still show up for 24 hours due to database caching.'),
        )),
        m('fieldset.form', m('fieldset',
            m('label', 'Merge votes'),
            m('p', 'All direct votes on the listed tags will be moved to this tag. WARNING: cannot be undone!'),
            data.merge.length === 0 ? null : m('table', data.merge.map(g => m('tr', {key: g.id},
                m('td', m(Button.Del, { onclick: () => data.merge = data.merge.filter(x => x !== g)})),
                m('td', m('small', g.id, ': '), m('a[target=_blank]', { href: '/'+g.id }, g.name)),
            ))),
            m(DS.Button, { ds: mergeDS, class: 'mw' }, 'Add tag to merge'),
        )),
    ];

    const onsubmit = () => api.call(data, r => dups = r.dups);
    const view = () => m(Form, {api,onsubmit},
        m('article',
            m('h1', data.id ? 'Edit tag: '+data.name : 'Submit new tag'),
            names(),
            properties(),
            parents(),
            data.id && data.authmod ? danger() : null,
        ),
        m(EditSum, {data,api, approval: data.authmod }),
    );
    return {view};
});
