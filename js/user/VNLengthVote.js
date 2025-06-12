widget('VNLengthVote', initVnode => {
    const data = initVnode.attrs.data;
    const api = new Api('VNLengthVote');

    const langs = Object.fromEntries(vndbTypes.language);
    const availableLangs = v => new Set(data.releases.flatMap(r => v.rid.includes(r.id) ? r.lang : []));
    const setlang = v => {
        const l = availableLangs(v);
        if (l.size === 1) v.lang = [l.values().next().value];
        if (!v.lang) v.lang = [];
        v.lang = v.lang.filter(x => l.has(x));
    };
    data.votes.forEach(setlang);

    const setlength = v => {
        v.length = (v.hours||0) * 60 + (v.mins||0);
        if (length.hours === 0) v.hours = '';
        if (length.mins === 0) v.mins = '';
    };
    data.votes.forEach(v => {
        v.hours = Math.floor(v.length / 60);
        v.mins = v.length % 60;
        setlength(v);
    });

    const relDs = {};
    const setds = v => relDs[v.id] = data.releases.length === 1 && v.rid.length === 1 && v.rid[0] === data.releases[0].id ? null : new DS(DS.Releases(data.releases), {
        keep: false,
        onselect: (obj,c) => {
            if (c && !v.rid.includes(obj.id)) v.rid.push(obj.id);
            else v.rid = v.rid.filter(x => x !== obj.id);
            setlang(v);
        },
        checked: obj => v.rid.includes(obj.id),
    });
    data.votes.forEach(setds);

    let newid = -1;
    const addvote = () => {
        const v = {
            id: newid,
            rid: data.releases.length === 1 ? [data.releases[0].id] : [],
            hours: '', mins: '', length: 0,
            speed: data.maycount ? -1 : null,
            private: false,
            notes: '',
        };
        setlang(v);
        setds(v);
        newid--;
        data.votes.push(v);
    };
    if (data.votes.length === 0) addvote();

    const form = (v,i) => m('div', {key:v.id},
        m('fieldset.form',
            data.votes.length > 1 ? m('legend', 'Playthrough #'+(i+1)) : null,
            m('fieldset',
                m('label', 'Visual novel'),
                m('small', data.vid, ': '),
                m('a[target=_blank]', { href: '/'+data.vid }, data.title),
            ),
            m('fieldset',
                m('label[for=rel]', 'Release(s)'),
                v.rid.length === 0 ? m('div', 'Which release did you play?') : null,
                v.rid.map(id => (r => m('div', {key: id},
                    relDs[v.id] ? m(Button.Del, { onclick: () => setlang(v, v.rid = v.rid.filter(x => x !== id)) }) : null,
                    ' ',
                    r ? Release(r,1) : 'Moved or deleted release: '+id
                ))(data.releases.find(r => r.id == id))),
                relDs[v.id] ? m(DS.Button, { ds: relDs[v.id], id: 'rel' }, 'Select release') : null,
                v.rid.length === 0 ? m('p.invalid', 'Please select a release') : null,
            ),
            v.rid.length === 0 ? null : m('fieldset',
                m('label', 'Language(s)'),
                availableLangs(v).size === 1 ? [LangIcon(v.lang[0]), langs[v.lang[0]]] :
                    [...availableLangs(v).values()].map(l => m('label.check',
                        m('input[type=checkbox]', { checked: v.lang.includes(l), onclick: ev => {
                            if (ev.target.checked) v.lang.push(l);
                            else v.lang = v.lang.filter(x => x !== l);
                        }}), ' ', LangIcon(l), langs[l]
                    )).intersperse(m('small', ' / ')),
                v.lang.length === 0 ? m('p.invalid', 'No language selected.') : null,
            ),
        ),

        m('fieldset.form',
                m('fieldset',
                m('label[for=hour]', 'Play time'),
                m('p', 'How long did you take to finish this VN?'),
                m('p', 'Exact measurements are preferred, but a rough estimate will do as well.'),
                m(Input, { id: 'hour', class: 'sw', type: 'number', data: v, field: 'hours', oninput: () => setlength(v) }),
                ' hours ',
                m(Input, { class: 'sw', type: 'number', data: v, field: 'mins', oninput: () => setlength(v) }),
                ' minutes',
                v.length === 0 ? m('p.invalid', 'Please input a play time') :
                v.hours > 435 ? m('p.invalid', "That's way too long.") :
                v.mins >= 60 ? m('p.invalid', 'An hour only has 60 minutes.') : null,
            ),
        ),

        m('fieldset.form',
            m('fieldset',
                m('label', 'Vote type'),
                data.maycount ? [
                    m('label.check',
                        m('input[type=radio]', { checked: !v.private && v.speed !== null, onclick: () => { v.private = false; v.speed = -1 } }), ' Counted',
                        m('small', ' - Your play time is counted towards the public average'),
                    ),
                    m('br'),
                ] : [
                    m('p', "This visual novel is still in development, your play time will not count towards the game's average."),
                ],
                m('label.check',
                    m('input[type=radio]', { checked: !v.private && v.speed === null, onclick: () => { v.private = false; v.speed = null } }), ' Uncounted',
                    m('small', ' - Your play time is still listed but does not count towards the average'),
                ),
                m('br'),
                m('label.check',
                    m('input[type=radio]', { checked: v.private, onclick: () => { v.private = true; v.speed = null } }), ' Private',
                    m('small', ' - Your play time does not count and is not publicly visible'),
                ),
                !v.private && v.speed !== null ? m('p',
                    m('br'),
                    'Only vote if you have completed all normal/true endings!',
                    m('br'),
                    'If you have not completed the game yet, select the "Uncounted" option instead.'
                ) : null,
            ),
        ),

        !v.private && v.speed !== null ? m('fieldset.form',
            m('fieldset',
                m('label', 'Reading speed'),
                m('label.check',
                    m('input[type=radio]', { checked: v.speed === 0, onclick: () => v.speed = 0 }), ' Slow',
                    m('small', ' - e.g. low language proficiency or extra time spent on gameplay'),
                ),
                m('br'),
                m('label.check',
                    m('input[type=radio]', { checked: v.speed === 1, onclick: () => v.speed = 1 }), ' Normal',
                    m('small', ' - no content skipped, all voices listened to end'),
                ),
                m('br'),
                m('label.check',
                    m('input[type=radio]', { checked: v.speed === 2, onclick: () => v.speed = 2 }), ' Fast',
                    m('small', ' - fast reader or skipping through voices and gameplay'),
                ),
                v.speed === -1 ? m('p.invalid', 'Please select a reading speed') : null,
            ),
        ) : null,

        m('fieldset.form',
            m('fieldset',
                m('label[for=notes]', 'Notes'),
                m(Input, {
                    type: 'textarea', id: 'notes', class: 'xw', rows: 4, data: v, field: 'notes',
                    placeholder: '(Optional) comments that may be helpful. Did you complete all the bad endings, did you use a walkthrough, how did you measure? etc.'
                }),
            ),
            m('fieldset',
                m('input[type=button][value=Delete this playthrough]', { onclick: () => data.votes = data.votes.filter(x => x !== v) }),
            ),
        ),
    );

    const redir = () => location.href = '/'+data.vid;
    const view = () => m(Form, { api, onsubmit: () => api.call(data, redir) },
        m('article',
            m('h1', 'Edit your play time'),
            data.votes.map(form),
            m('p',
                data.votes.length === 0 ? m('p', 'No playthroughs.') : null,
                data.votes.length < 5 ? m('input[type=button][value=Add playthrough]', { onclick: addvote }) : null,
            ),
        ),
        m('article.submit',
            m('input[type=submit][value=Submit]'),
            ' ',
            m('input[type=button][value=Cancel]', { onclick: redir }),
            ' ',
            api.Status(),
        ),
    );
    return {view};
});
