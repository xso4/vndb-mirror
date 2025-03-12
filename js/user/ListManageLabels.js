widget('UListManageLabels', () => {
    let labels = JSON.parse(JSON.stringify(pageVars.labels)).filter(l => l.id > 0);
    const api = new Api('UListManageLabels');
    const onsubmit = () => api.call({ labels: labels }, () => location.reload());

    const lbl = l => m('tr', { key: l.id },
        m('td', l.count || ''),
        m('td.stealth', l.id > 0 && l.id < 10 ? l.label :
            m(Input, { type: 'text', data: l, field: 'label', required: true, placeholder: 'New label...', maxlength: 50, focus: l.id < 0 }),
        ),
        m('td', m('label',
            m('input[type=checkbox]', { checked: l.private, onclick: ev => l.private = ev.target.checked }),
            ' private'
        )),
        m('td.stealth',
            l.id === 7 ? m('small', 'applied when you vote') :
            l.id > 0 && l.id < 10 ? m('small', 'built-in') :
            l.delete === null ? m('span[title=Delete label]', { onclick: () => {
                if (l.id < 0) labels = labels.filter(x => l !== x);
                else l.delete = 1;
            } }, m(Icon.Trash2)) :
            m(Select, { data: l, field: 'delete', options: [
                [ null, 'Keep label' ],
                [ 1, 'Delete label but keep VNs in my list' ],
                [ 2, 'Delete label and VNs with only this label' ],
                [ 3, 'Delete label and all VNs with this label '],
            ]}),
        ),
    );
    const view = () => m(Form, {api,onsubmit},
        m('div',
            m('strong', 'How to use labels'),
            m('ul',
                m('li', 'You can assign multiple labels to a visual novel'),
                m('li', 'You can use the built-in labels or create custom labels for your own organization'),
                m('li', 'Private labels are not visible to other users'),
                m('li', 'Your vote and notes are public when the visual novel has at least one non-private label'),
            ),
        ),
        m('table.stripe',
            m('thead', m('tr',
                m('td', 'VNs'),
                m('td', 'Label'),
                m('td', 'Private'),
                m('td'),
            )),
            m('tbody.compact', labels.map(lbl)),
            m('tfoot',
                labels.find(l => l.id === 7 && l.private) && labels.find(l => !l.private) ? m('tr', m('td[colspan=4]',
                    m('b', 'WARNING: '),
                    'Your vote is still public if you assign a non-private label to the visual novel.'
                )) : null,
                labels.anyDup(l => l.label) ? m('tr', m('td[colspan=4]',
                    m('p.invalid', 'You have duplicate labels'),
                )) : null,
                m('tr', m('td'), m('td[colspan=3]',
                    labels.length < 500 ? m('button[type=button]', {
                        onclick: () => labels.push({
                            id: Math.min(0, ...labels.map(l => l.id))-1,
                            private: !labels.find(l => !l.private),
                            label: '', count: 0, delete: null,
                        }),
                    }, 'Add label') : null,
                    m('input[type=submit][value=Save changes]'),
                    api.Status(),
                )),
            ),
        ),
    );
    return {view};
});
