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
        m('legend', 'Titles & languages', HelpButton('titles')),
        Help('titles',
            m('p', 'List of languages that this release is available in.'),
            m('p',
                'The main language is the language that the script was originally authored in, ',
                'or for translations, the primary language of the publisher.'
            ),
            m('p',
                'A release can have different titles for different languages. ',
                'The main language should always have a title, but this field can be left empty for other languages if their title is the same as that of the main language.'
            ),
        ),
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

const Status = initVnode => {
    const {data} = initVnode.attrs;
    const view = () => m('fieldset.form',
        m('legend', 'Status'),
        m('fieldset', m('label.check',
            m('input[type=checkbox]', { checked: data.official, oninput: ev => data.official = ev.target.checked }),
            ' Official ', HelpButton('official'),
        )),
        Help('official',
            'Whether the release is official, i.e. made or sanctioned by the original developer. ',
            'The official status is in relation to the visual novel that the release is linked to, ',
            'so even if the visual novel itself is an unofficial fanfic in some franchise, the release can still be official.'
        ),
        m('fieldset', m('label.check',
            m('input[type=checkbox]', { checked: data.patch, oninput: ev => data.patch = ev.target.checked }),
            ' Patch (*)', HelpButton('patch'),
        )),
        Help('patch',
            'A patch is not a standalone release, but instead requires another release in order to be used. ',
            'It may be helpful to indicate which releases this patch applies to in the notes.'
        ),
        m('fieldset', m('label.check',
            m('input[type=checkbox]', { checked: data.freeware, oninput: ev => data.freeware = ev.target.checked }),
            ' Freeware'
        )),
        m('fieldset', m('label.check',
            m('input[type=checkbox]', { checked: data.has_ero, oninput: ev => data.has_ero = ev.target.checked }),
            ' Contains erotic scenes (*)'
        )),
        m('fieldset',
            m('label[for=minage]', 'Age rating'),
            m('select.mw', { oninput: ev => data.minage = ev.target.selectedIndex === 0 ? null : vndbTypes.ageRating[ev.target.selectedIndex-1][0] },
                m('option', { selected: data.minage === null }, 'Unknown'),
                vndbTypes.ageRating.map(([id,label]) => m('option', { selected: id === data.minage }, label))
            )
        ),
        m('fieldset',
            m('label[for=released]', 'Release date'),
            m(RDate, { id: 'released', value: data.released, oninput: v => data.released = v }),
        ),
    );
    return {view};
}

widget('ReleaseEdit', initVnode => {
    const data = initVnode.attrs.data;
    const api = new Api('ReleaseEdit');
    const view = () => m(Form, {api, onsubmit: () => api.call(data)},
        m('article',
            m('h1', 'General info'),
            m(Titles, {data}),
            m(Status, {data}),
        ),
        m(EditSum, {data,api}),
    );
    return {view};
});
