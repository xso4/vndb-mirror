const Titles = initVnode => {
    const {data} = initVnode.attrs;
    const ds = new DS(DS.Lang, {
        onselect: obj => {
            const p = data.vntitles.find(t => t.lang === obj.id);
            data.titles.push({ lang: obj.id, mtl: false, title: p?p.title:'', latin: p?p.latin:'', new: true });
        },
        props: obj => data.titles.find(t => t.lang === obj.id) ? { selectable: false, append: m('small', ' (already listed)') } : {},
    });
    const langs = Object.fromEntries(vndbTypes.language);
    const view = () => m('fieldset.form',
        m('legend', 'Titles & languages'),
        data.titles.map(t => m('fieldset', {key: t.lang},
            m('label', LangIcon(t.lang), langs[t.lang]),
            m('input.xw[type=text][maxlength=300]', {
                required: t.lang === data.olang,
                placeholder: t.lang === data.olang ? 'Title (in the original script)' : 'Title (leave empty if equivalent to the main title)',
                value: t.title, oninput: ev => t.title = ev.target.value,
                oncreate: t.new ? v => { t.new = false; v.dom.focus() } : null,
            }),
            !t.latin && !nonLatin.test(t.title) ? [] : [
                m('br'),
                m('input.xw[type=text][maxlength=300][required]', {
                    placeholder: 'Romanization',
                    value: t.latin, oninput: ev => t.latin = ev.target.value,
                    onupdate: v => v.dom.setCustomValidity(nonLatin.test(t.latin) ? 'Romanization should only contain characters in the latin alphabet.' : ''),
                }),
            ],
            m('br'),
            data.titles.length === 1 ? [] : [
                m('span', m('label.check',
                    m('input[type=radio]', { checked: t.lang === data.olang, oninput: ev => data.olang = t.lang }),
                    ' Main title '
                )),
            ],
            m('span', m('label.check',
                m('input[type=checkbox]', { checked: t.mtl, oninput: ev => t.mtl = ev.target.checked }),
                ' Machine translation '
            )),
            m('input[type=button][value=Remove]', {
                class: t.lang === data.olang ? 'invisible' : null,
                onclick: () => data.titles = data.titles.filter(x => x !== t)
            }),
        )),
        // TODO: Form error if there's no languages (happens only when creating a new release entry)
        m(DSButton, { onclick: ds.open }, 'Add language'),
    );
    return {view};
};

widget('ReleaseEdit', initVnode => {
    const data = initVnode.attrs.data;
    const api = new Api('ReleaseEdit');
    const view = () => m(Form, {api, onsubmit: () => api.call(data)},
        m('article',
            m(Titles, {data}),
        ),
        m(EditSum, {data,api}),
    );
    return {view};
});
