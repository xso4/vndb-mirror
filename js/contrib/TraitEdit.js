widget('TraitEdit', vnode => {
    const data = vnode.attrs.data;
    const api = new Api('TraitEdit');
    var dups = [];

    const parentDS = new DS(DS.Traits, {
        onselect: obj => data.parents.push({parent: obj.id, name: obj.name, group: obj.group_name, main: data.parents.length === 0}),
        props: obj =>
            obj.id === data.id ? { selectable: false, append: m('small', ' (this trait)') } :
            data.parents.find(x => x.parent === obj.id) ? { selectable: false, append: m('small', ' (already listed)') } : {},
    });

    const names = () => m('fieldset.form',
        m('fieldset',
            m('label[for=name]', 'Primary name'),
            m(Input, { class: 'lw', id: 'name', data, field: 'name', required: true, maxlength: 250 }),
        ),
        m('fieldset',
            m('label[for=alias]', 'Aliases'),
            m(Input, { class: 'lw', rows: 5, type: 'textarea', id: 'alias', data, field: 'alias', maxlength: 1024 }),
            m('p', 'Name and aliases must be self-describing and unique within the same group.'),
            (l => l.length === 0 ? '' : m('p.invalid',
                'The following trait names are already in the same group:',
                l.map(d => [m('br'), m('a[target=_blank]', {href: '/'+d.id}, d.name)]),
            ))([data.name].concat(data.alias.split("\n")).flatMap(s => dups.filter(d => d.name.toLowerCase() === s.trim().toLowerCase())))
        ),
    );

    const properties = () => m('fieldset.form',
        m('fieldset', m('label.check',
            m('input[type=checkbox]', { checked: data.searchable, oninput: e => data.searchable = e.target.checked }),
            ' Searchable (people can use this trait to find VNs)',
        )),
        m('fieldset', m('label.check',
            m('input[type=checkbox]', { checked: data.applicable, oninput: e => data.applicable = e.target.checked }),
            ' Applicable (people can apply this trait to VNs)',
        )),
        m('fieldset', m('label.check',
            m('input[type=checkbox]', { checked: data.sexual, oninput: e => data.sexual = e.target.checked }),
            ' Indicates sexual content',
        )),
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
            m('p', 'What should the trait be used for? Having a good description helps users choose which traits to link to characters.'),
        ),
    );

    const parents = () => m('fieldset.form', m('fieldset',
        m('label', 'Parent traits'),
        data.parents.length === 0
        ? m('p', 'No parent traits selected, which makes this a top-level trait.')
        : m('table', data.parents.map(g => m('tr', {key: g.parent},
            m('td', m(Button.Del, { onclick: () => {
                data.parents = data.parents.filter(x => x !== g);
                if (data.parents.length > 0 && !data.parents.find(x => x.main))
                    data.parents[0].main = true;
            }})),
            m('td',
                m('small', g.parent, ': '),
                g.group ? m('small', g.group, ' / ') : '',
                m('a[target=_blank]', { href: '/'+g.parent }, g.name),
            ),
            m('td', m('label',
                m('input[type=radio]', { checked: g.main, onclick: () => data.parents.forEach(x => x.main = x === g) }),
                ' primary'
            )),
        ))),
        m(DS.Button, { ds: parentDS, class: 'mw' }, 'Add parent trait'),
    ), data.parents.length === 0 ? m('fieldset', 
        m('label[for=gorder]', 'Group order'),
        m(Input, { type: 'number', id: 'gorder', class: 'sw', data, field: 'gorder' }),
        m('p',
          ' Only meaningful if this trait is a "group", i.e. a trait without any parents.',
          ' This number determines the order in which the groups are displayed on character pages.'
        ),
    ) : null);

    const onsubmit = () => api.call(data, r => dups = r.dups);
    const view = () => m(Form, {api,onsubmit},
        m('article',
            m('h1', data.id ? 'Edit trait: '+data.name : 'Submit new trait'),
            names(),
            properties(),
            parents(),
        ),
        m(EditSum, {data,api, approval: data.authmod }),
    );
    return {view};
});
