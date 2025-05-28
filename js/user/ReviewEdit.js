widget('ReviewEdit', initVnode => {
    const data = initVnode.attrs.data;
    const api = new Api('ReviewEdit');

    const delApi = new Api('ReviewDelete');
    let del = false;

    const relDs = new DS(DS.New(
        DS.Releases(data.releases),
        () => ({id:0}),
        () => 'No release',
    ), {
        onselect: obj => data.rid = obj.id ? obj.id : null,
    });

    const view = () => [ m(Form, { api, onsubmit: () => api.call(data) },
        m('article',
            m('h1', data.id ? 'Edit review' : 'Submit review'),
            m('p', m('strong', 'Rules')),
            m('ul',
                m('li', 'Submit only reviews you have written yourself!'),
                m('li', 'Reviews must be in English.'),
                m('li', 'Try to be somewhat objective.'),
                m('li',
                    'If you have published the review elsewhere (e.g. a personal blog),',
                    ' feel free to include a link at the end of the review. Formatting tip: ',
                    m('em', '[Originally published at <link>]')
                ),
                m('li', 'Your vote (if any) will be displayed alongside the review, even if you have marked your list as private.'),
            ),
        ),
        m('article',
            m('fieldset.form',
                m('fieldset',
                    m('label', 'Subject'),
                    m('a[target=_blank]', { href: '/'+data.vid }, data.vntitle),
                ),
                m('fieldset',
                    m('label[for=rid]', 'Release'),
                    m(DS.Button, { ds:relDs, class: 'xw' }, !data.rid ? m('i', 'No release selected') : (r =>
                        r ? m('span', Release(r,1)) : 'Moved or deleted release: '+data.rid
                    )(data.releases.find(r => r.id == data.rid))),
                ),
            ),
            m('fieldset.form',
                m('fieldset',
                    m('label.check',
                        m('input[type=checkbox]', { checked: data.spoiler, oninput: ev => data.spoiler = ev.target.checked }),
                        ' This review contains spoilers',
                    ),
                    m('br'),
                    m('small', 'You do not have to check this option if all spoilers in your review are marked with [spoiler] tags.'),
                ),
                !data.mod ? [] : [
                m('fieldset',
                    m('label.check',
                        m('input[type=checkbox]', { checked: data.locked, oninput: ev => data.locked = ev.target.checked }),
                        ' Locked for commenting.',
                    ),
                ),
                m('fieldset',
                    m('label[for=modnote]', 'Mod note'),
                    m(Input, { id: 'modnote', class: 'xw', maxlength: 1024, data, field: 'modnote' }),
                    m('small', m('br'), 'Moderation note intended to inform readers of the review that its author may be biased and failed to disclose that.'),
                )],
            ),
            m('fieldset.form',
                m('fieldset',
                    m('label[for=text]', 'Review'),
                    m(TextPreview, {
                        data, field: 'text',
                        attrs: {
                            id: 'text', required: true,
                            minlength: 200,
                            maxlength: 100000,
                            rows: 30,
                        },
                        header: [
                            m('a[href=/d9#4][target=_blank]', 'BBCode formatting supported'),
                            ' - ',
                            m('b', 'Review must be in English!'),
                        ],
                        footer: m('div[style=text-align:right]', (l => [
                            l, ' / ',
                            l < 200 ? m('b.invalid', 'too short') : l <= 800 ? 'short' : l <= 2500 ? 'medium' : l <= 100000 ? 'long' : m('b.invalid', 'too long')
                        ])(data.text.trim().length)),
                    }),
                )
            ),
        ),
        m('article.submit',
            m('input[type=submit][value=Submit]'),
            api.Status(),
        ),
    ), !data.id ? null : m(Form, { api: delApi, onsubmit: () => delApi.call({id: data.id}) },
        m('article',
            m('fieldset.form',
                m('legend', 'Delete review'),
                m('fieldset',
                    m('label.check',
                        m('input[type=checkbox]', { checked: del, oninput: ev => del = ev.target.checked }),
                        ' Delete this review'
                    )
                ),
                !del ? [] : [m('fieldset',
                    m('b', 'WARNING:'),
                    ' Deleting a review is a permanent action and cannot be reverted!',
                    m('br'),
                    'Comments and votes on this review, if any, are also permanently deleted.',
                    m('br'),
                    m('input[type=submit][value=Submit]'),
                    delApi.Status(),
                )],
            )
        ),
    )];
    return {view};
});
