widget('VNLengthVote', initVnode => {
    const data = initVnode.attrs.data;
    const api = new Api('VNLengthVote');
    const hasvote = !!data.vote;
    const vote = data.vote || {
        rid: data.releases.length === 1 ? [data.releases[0].id] : [],
        length: 0,
        speed: data.maycount ? -1 : null,
        private: false,
        notes: '',
    };

    const langs = Object.fromEntries(vndbTypes.language);
    const availableLangs = () => new Set(data.releases.flatMap(r => vote.rid.includes(r.id) ? r.lang : []));
    const setlang = () => {
        const l = availableLangs();
        if (l.size === 1) vote.lang = [availableLangs().values().next().value];
        if (!vote.lang) vote.lang = [];
        vote.lang = vote.lang.filter(v => l.has(v));
    };
    setlang();

    const relDs = data.releases.length === 1 && vote.rid.length === 1 && vote.rid[0] === data.releases[0].id ? null : new DS(DS.Releases(data.releases), {
        keep: false,
        onselect: (obj,c) => {
            if (c && !vote.rid.includes(obj.id)) vote.rid.push(obj.id);
            else vote.rid = vote.rid.filter(x => x !== obj.id);
            setlang();
        },
        checked: obj => vote.rid.includes(obj.id),
    });

    const length = { hours: Math.floor(vote.length / 60), mins: vote.length % 60 };
    const setlength = () => {
        vote.length = (length.hours||0) * 60 + (length.mins||0);
        if (length.hours === 0) length.hours = '';
        if (length.mins === 0) length.mins = '';
    };
    setlength();

    const redir = () => location.href = '/'+data.vid;
    const view = () => m(Form, { api, onsubmit: () => api.call(Object.assign(data, {vote}), redir) },
        m('article',
            m('h1', 'Edit your play time'),
            m('fieldset.form',
                m('fieldset',
                    m('label', 'Visual novel'),
                    m('small', data.vid, ': '),
                    m('a[target=_blank]', { href: '/'+data.vid }, data.title),
                ),
                m('fieldset',
                    m('label[for=rel]', 'Release(s)'),
                    vote.rid.length === 0 ? m('div', 'Which release did you play?') : null,
                    vote.rid.map(id => (r => m('div', {key: id},
                        relDs ? m(Button.Del, { onclick: () => setlang(vote.rid = vote.rid.filter(x => x !== id)) }) : null,
                        ' ',
                        r ? Release(r,1) : 'Moved or deleted release: '+id
                    ))(data.releases.find(r => r.id == id))),
                    relDs ? m(DS.Button, { ds: relDs, id: 'rel' }, 'Select release') : null,
                    vote.rid.length === 0 ? m('p.invalid', 'Please select a release') : null,
                ),
                vote.rid.length === 0 ? null : m('fieldset',
                    m('label', 'Language(s)'),
                    availableLangs().size === 1 ? [LangIcon(vote.lang[0]), langs[vote.lang[0]]] :
                        [...availableLangs().values()].map(l => m('label.check',
                            m('input[type=checkbox]', { checked: vote.lang.includes(l), onclick: ev => {
                                if (ev.target.checked) vote.lang.push(l);
                                else vote.lang = vote.lang.filter(x => x !== l);
                            }}), ' ', LangIcon(l), langs[l]
                        )).intersperse(m('small', ' / ')),
                    vote.lang.length === 0 ? m('p.invalid', 'No language selected.') : null,
                ),
            ), m('fieldset.form',
                m('fieldset',
                    m('label[for=hour]', 'Play time'),
                    m('p', 'How long did you take to finish this VN?'),
                    m('p', 'Exact measurements are preferred, but a rough estimate will do as well.'),
                    m(Input, { id: 'hour', class: 'sw', type: 'number', data: length, field: 'hours', oninput: setlength }),
                    ' hours ',
                    m(Input, { class: 'sw', type: 'number', data: length, field: 'mins', oninput: setlength }),
                    ' minutes',
                    vote.length === 0 ? m('p.invalid', 'Please input a play time') :
                    length.hours > 435 ? m('p.invalid', "That's way too long.") :
                    length.mins >= 60 ? m('p.invalid', 'An hour only has 60 minutes.') : null,
                ),
            ), m('fieldset.form',
                m('fieldset',
                    m('label', 'Vote type'),
                    data.maycount ? [
                        m('label.check',
                            m('input[type=radio]', { checked: !vote.private && vote.speed !== null, onclick: () => { vote.private = false; vote.speed = -1 } }), ' Counted',
                            m('small', ' - Your play time is counted towards the public average'),
                        ),
                        m('br'),
                    ] : [
                        m('p', "This visual novel is still in development, your play time will not count towards the game's average."),
                    ],
                    m('label.check',
                        m('input[type=radio]', { checked: !vote.private && vote.speed === null, onclick: () => { vote.private = false; vote.speed = null } }), ' Uncounted',
                        m('small', ' - Your play time is still listed but does not count towards the average'),
                    ),
                    m('br'),
                    m('label.check',
                        m('input[type=radio]', { checked: vote.private, onclick: () => { vote.private = true; vote.speed = null } }), ' Private',
                        m('small', ' - Your play time does not count and is not publicly visible'),
                    ),
                    !vote.private && vote.speed !== null ? m('p',
                        m('br'),
                        'Only vote if you have completed all normal/true endings!',
                        m('br'),
                        'If you have not completed the game yet, select the "Uncounted" option instead.'
                    ) : null,
                ),
            ), !vote.private && vote.speed !== null ? m('fieldset.form',
                m('fieldset',
                    m('label', 'Reading speed'),
                    m('label.check',
                        m('input[type=radio]', { checked: vote.speed === 0, onclick: () => vote.speed = 0 }), ' Slow',
                        m('small', ' - e.g. low language proficiency or extra time spent on gameplay'),
                    ),
                    m('br'),
                    m('label.check',
                        m('input[type=radio]', { checked: vote.speed === 1, onclick: () => vote.speed = 1 }), ' Normal',
                        m('small', ' - no content skipped, all voices listened to end'),
                    ),
                    m('br'),
                    m('label.check',
                        m('input[type=radio]', { checked: vote.speed === 2, onclick: () => vote.speed = 2 }), ' Fast',
                        m('small', ' - fast reader or skipping through voices and gameplay'),
                    ),
                    vote.speed === -1 ? m('p.invalid', 'Please select a reading speed') : null,
                ),
            ) : null,
            m('fieldset.form',
                m('fieldset',
                    m('label[for=notes]', 'Notes'),
                    m(Input, {
                        type: 'textarea', id: 'notes', class: 'xw', rows: 4, data: vote, field: 'notes',
                        placeholder: '(Optional) comments that may be helpful. Did you complete all the bad endings, did you use a walkthrough, how did you measure? etc.'
                    }),
                )
            ),
        ),
        m('article.submit',
            m('input[type=submit][value=Submit]'),
            ' ',
            m('input[type=button][value=Cancel]', { onclick: redir }),
            ' ',
            hasvote ? m('input[type=button][value=Delete my play time]', { onclick: () => api.call(Object.assign(data, {vote:null}), redir) }) : null,
            api.Status(),
        ),
    );
    return {view};
});
