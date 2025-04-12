widget('StaffEdit', initVnode => {
    const data = initVnode.attrs.data;
    const api = new Api('StaffEdit');
    if (!data.l_pixiv) data.l_pixiv = '';

    const dupApi = new Api('Staff');
    let dupCheck = !data.id;
    const nameChange = () => {dupCheck = !!dupCheck};
    const onsubmit = () => !dupCheck ? api.call(data) : dupApi.call(
        {search: data.alias.flatMap(({name,latin}) => [name,latin]).filter(x => x)},
        res => dupCheck = res.results.length ? res.results : false,
    );

    const names = () => m('table.names',
        m('thead', m('tr',
            m('td'),
            m('td.tc_name', 'Name (original script)'),
            m('td.tc_name', 'Romanization'),
            m('td'),
        )),
        m('tfoot', m('tr.alias_new',
            m('td'),
            m('td[colspan=3]',
                data.alias.anyDup(({name,latin}) => [name,latin===''?null:latin])
                ? m('p.invalid', 'There are duplicate aliases.') : null,
                m('a[href=#]', { onclick: () => {
                    data.alias.push({
                        aid: Math.min(0, ...data.alias.map(a => a.aid)) - 1,
                        name: '',
                        latin: '',
                        focus: true,
                    });
                    return false;
                }}, 'Add alias'),
            ),
        )),
        m('tbody', data.alias.flatMap(a => [
            m('tr', {key: a.aid},
                m('td', m('input[type=radio]', { checked: a.aid === data.main, onclick: () => data.main = a.aid })),
                m('td.tc_name', a.editable || !a.inuse ? m('span', m(Input,
                    { required: true, maxlength: 200, data: a, field: 'name', oninput: nameChange, focus: a.focus }
                )) : a.name),
                m('td.tc_name', !a.latin && !mayRomanize.test(a.name) ? m('br') : a.editable || !a.inuse ? m('span', m(Input, {
                    required: mustRomanize.test(a.name), maxlength: 200, data: a, field: 'latin', placeholder: 'Romanization', oninput: nameChange,
                    invalid: a.latin === a.name || mustRomanize.test(a.latin) ? 'Romanization should only contain characters in the latin alphabet.' : null,
                })) : a.latin),
                m('td',
                    a.editable ? m(Button.Cancel, { onclick: () => { a.name = a.orig_name; a.latin = a.orig_latin; a.editable = false } }) :
                    a.inuse ? m(Button.Edit, { onclick: () => { a.orig_name = a.name; a.orig_latin = a.latin; a.editable = true } }) : null,
                    a.aid === data.main ? m('small', ' primary') :
                    a.wantdel ? m('b', ' still referenced') :
                    a.inuse ? m('small', ' referenced') :
                    m(Button.Del, { onclick: () => nameChange(data.alias = data.alias.filter(x => x !== a)) }),
                ),
            ),
            a.editable ? m('tr', {key: 'w'+a.aid},
                m('td'),
                m('td[colspan=3]',
                    m('b', 'WARNING: '),
                    'You are editing an alias that is used in the credits of a visual novel. ',
                    'Changing this name also changes the credits. Only do this for simple corrections!'
                ),
            ) : null,
        ]).filter(x => x)),
    );

    const prod = new DS(DS.Producers, { onselect: o => {
        data.prod = o.id;
        data.prod_title = [ '', o.name, '', o.altname ];
    }});
    const lang = new DS(DS.LocLang, {onselect: obj => data.lang = obj.id});
    const fields = () => [
        m('fieldset',
            m('label[for=gender]', 'Gender'),
            m(Select, { id: 'gender', class: 'mw', data, field: 'gender', options: [
                [ '',  'Unknown or N/A' ],
                [ 'm', 'Male' ],
                [ 'f', 'Female' ],
            ] }),
        ),
        m('fieldset',
            m('label', { class: data.lang ? null : 'invalid' }, 'Primary language'),
            m(DS.Button, {class: 'mw', ds:lang}, data.lang ? Object.fromEntries(vndbTypes.language)[data.lang] : '-- select --'),
            data.lang ? null : m('p.invalid', 'No language selected.'),
        ),
        m('fieldset',
            m('label', 'Same as', HelpButton('prod')),
            m(DS.Button, { class: 'lw', ds:prod}, data.prod
                ? [ m('small', data.prod, ': '), data.prod_title[1] ]
                : m('em', 'No producer entry')
            ),
            data.prod ? m(Button.Del, {onclick: () => data.prod = null}) : null,
        ),
        Help('prod',
            m('p', 'Producer entry for this person, if there is one.'),
            m('p', 'Only set this if the producer and this staff entry are one and the same, not just when this staff happens to work for the producer.'),
        ),
        m(ExtLinks, {type: 's', links: data.extlinks}),
        m('fieldset',
            m('label[for=description]', 'Notes / Biography'),
            m(TextPreview, {
                data, field: 'description',
                header: m('b', '(English please!)'),
                attrs: { id: 'description', rows: 6, maxlength: 5000 },
            }),
        ),
    ];

    const view = () => m(Form, {api: dupCheck ? dupApi : api, onsubmit},
        m('article.staffedit',
            m('h1', data.id ? 'Edit staff' : 'Add staff'),
            m('fieldset.form',
                m('fieldset',
                    m('label', 'Names'),
                    names(),
                ),
                dupCheck === false ? fields() : [],
            ),
        ),
        dupCheck === false ? [
            m(EditSum, {data,api,type:'s'})
        ] : dupCheck === true ? [m('article.submit',
            m('input[type=submit][value=Continue]'),
            dupApi.Status(),
        )] : [
            m('article',
                m('h1', 'Possible duplicates'),
                m('p',
                    'The following is a list of staff that match the name(s) you gave. ',
                    'Please check this list to avoid creating a duplicate staff entry.',
                ),
                m('ul', dupCheck.map(s => m('li',
                    m('a[target=_blank]', { href: '/'+s.sid }, s.title),
                    s.alttitle ? m('small', ' (', s.alttitle, ')') : null,
                ))),
            ),
            m('article.submit',
                m('input[type=button][value=Continue anyway]', { onclick: () => dupCheck = false }),
            ),
        ],
    );
    return {view};
});
