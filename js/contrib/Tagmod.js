widget('Tagmod', initvnode => {
    const data = initvnode.attrs.data;
    const api = new Api('Tagmod');

    let tagMsg = null; /* false = notes input */
    let tagId = null;

    data.tags.forEach(t => {
        /* Add an 'only' field indicating that we're the only vote on it and can thus delete the tag */
        t.only = t.count === 1 && t.vote !== 0;
        /* Copy current vote state so we can compare for changes */
        t.svote = t.vote;
        t.sspoil = t.spoil;
        t.slie = t.lie;
        t.soverrule = t.overrule;
        t.snotes = t.notes;
    });
    let _hasChanges = false;
    const _numTags = data.tags.length;
    const unloadHandler = ev => {
        ev.preventDefault();
        ev.returnValue = true;
    };
    const hasChanges = () => {
        if (tagId) return _hasChanges;
        _hasChanges = _numTags !== data.tags.length || data.tags.find(t =>
            t.svote !== t.vote || t.sspoil !== t.spoil || t.slie !== t.lie || t.soverrule !== t.overrule || t.snotes !== t.notes
        );
        (_hasChanges && !api.loading() ? addEventListener : removeEventListener)("beforeunload", unloadHandler);
        return _hasChanges;
    };
    const hasUnvoted = () => data.tags.find(t => t.cat === 'new' && ('_vote' in t ? t._vote : t.vote) === 0);
    const onsubmit = () => {
        window.removeEventListener("beforeunload", unloadHandler);
        api.call(data);
    };

    const cntNeg = data.tags.filter(t => t.rating <= 0).length;
    let showNeg = false;

    const ds = new DS(DS.Tags, {
        keep: true,
        onselect: obj => data.tags.push({...obj, cat: 'new', count: 0, vote: 0, spoil: null, lie: null, overrule: false, notes: '', only: true }),
        props: obj =>
            data.tags.find(x => x.id === obj.id) ?
                { selectable: false, append: m('small', ' (already listed)') } :
                { selectable: obj.applicable && !(obj.hidden && obj.locked) },
    });

    const but = (t, klass, classen, field, value, title, msg=title) => m('a[href=#]', {
        class: classen ? klass : null, title,
        onclick: ev => { ev.preventDefault(); api.error = null; delete t['_'+field]; t[field] = value },
        onmouseover: () => { if (tagMsg !== false) { tagId = t.id; tagMsg = msg; t['_'+field] = t[field]; t[field] = value; } },
        onmouseout: () => { if (tagMsg !== false) { tagId = null; if ('_'+field in t) { t[field] = t['_'+field]; delete t['_'+field]; } } },
    });

    const tag = (t, avote) => m('tr', { key: t.id },
        m('td.tc_tagname',
            m('a[target=_blank]', {href:'/'+t.id, class: t.applicable && !(t.hidden && t.locked) ? null : 'linethrough' }, t.name),
            t.hidden && !t.locked ? m('small', ' (awaiting approval)') :
            t.hidden ? m('small', ' (deleted)') :
            !t.applicable ? m('small', ' (not applicable)') : null
        ),
        m('td.tc_myvote.buts',
            but(t, 'ld', t.vote <  0, 'vote', -3, 'Downvote'),
            but(t, 'l0', t.vote == 0, 'vote',  0, 'Remove vote'),
            but(t, 'l1', t.vote >= 1, 'vote',  1, '+1', 'Vote +1'),
            but(t, 'l2', t.vote >= 2, 'vote',  2, '+2', 'Vote +2'),
            but(t, 'l3', t.vote == 3, 'vote',  3, '+3', 'Vote +3'),
        ),
        t.vote === 0 && t.count === 0 ? m('td[colspan=3]', "<- don't forget to rate") : [
            m('td.tc_myover buts', avote === 0 ? null :
                but(t, 'ov', t.overrule, 'overrule', !('_overrule' in t ? t._overrule : t.overrule), 'Mod overrule (only your vote counts)')
            ),
            m('td.tc_myspoil buts', avote <= 0 ? null : [
                but(t, 'sn', t.spoil === null, 'spoil', null, 'Unknown', 'Spoiler status not known'),
                but(t, 's0', t.spoil ===    0, 'spoil',    0, 'Not a spoiler', 'This is not a spoiler'),
                but(t, 's1', t.spoil ===    1, 'spoil',    1, 'Minor spoiler', 'This is a minor spoiler'),
                but(t, 's2', t.spoil ===    2, 'spoil',    2, 'Major spoiler', 'This is a major spoiler'),
            ]),
            m('td.tc_mylie buts', avote <= 0 ? null : [
                but(t, 'fn', t.lie === null,  'lie', null,  'Unknown', 'Truth status not known'),
                but(t, 'f0', t.lie === false, 'lie', false, 'This tag is not a lie', 'This tag is not a lie'),
                but(t, 'f1', t.lie === true,  'lie', true,  'This tag is a lie', 'This tag turns out to be false'),
            ]),
        ],
        m('td.tc_mynote',
            m('span[title=Set note]', {
                class: avote === 0 ? 'invisible' : t.notes === '' ? null : 'sel',
                onmouseover: () => { if (tagMsg !== false) { tagId = t.id; tagMsg = t.notes === '' ? 'Set note' : t.notes } },
                onmouseout: () => { if (tagMsg !== false) { tagId = null } },
                onclick: () => { if (tagId === t.id && tagMsg === false) { tagId = null } else { tagId = t.id; tagMsg = false } },
            }, '💬'),
            ' ',
            m('span[title=Remove vote]', {
                class: t.cat === 'new' || avote !== 0 ? '' : 'invisible',
                onmouseover: () => { if (tagMsg !== false) { tagId = t.id; tagMsg = 'Remove my vote' } },
                onmouseout: () => { if (tagMsg !== false) { tagId = null } },
                onclick: () => { if (t.only) { tagId = null; data.tags = data.tags.filter(x => x !== t) } else { t.vote = 0 } },
            }, m(Icon.Trash2)),
        ),
        tagId === t.id ? m('td[colspan=4].tc_msg', m('div',
            tagMsg === false ? m('form', { onsubmit: ev => { ev.preventDefault(); tagId = null; tagMsg = null } },
                m(Input, {
                    data: t, field: 'notes', placeholder: 'Set note...', maxlength: 1000,
                    focus: 1, onblur: () => { tagId = null; tagMsg = null },
                }),
            ) : tagMsg
        )) : t.count === 0 ? m('td[colspan=4]') : [
            m('td.tc_allvote',
                m.trust(t.tagscore),
                t.overruled ? m('strong.standout[title=Tag overruled. All votes other than that of the moderator who overruled it are ignored.]', '!') : null,
            ),
            m('td.tc_allspoil', t.spoiler),
            m('td.tc_alllie', t.islie ? 'lie' : ''),
            m('td.tc_allwho',
                m('span', t.othnotes === '' ? { class: 'invisible' } : { title: t.othnotes }, '💬 '),
                m('a[target=_blank]', { href: '/g/links/?v='+data.id+'&t='+t.id }, 'Who?'),
            ),
        ],
    );

    const tagcat = (cat, lbl) => (l => l.length == 0 ? null : [
        m('tr.cat',
            m('td', lbl),
            m('td[colspan=5].tc_you'),
            m('td[colspan=4].tc_others'),
        ),
        l.map(t => tag(t, '_vote' in t ? t._vote : t.vote))
    ])(data.tags.filter(t => t.cat === cat && (cat === 'new' || t.rating > 0 || t.vote > 0 || showNeg)));

    const view = () => m(Form, {api, onsubmit}, m('table#tagmod.stripe',
        m('thead',
            m('tr',
                m('td.toggle', cntNeg ? m('label',
                    m('input[type=checkbox]', { checked: showNeg, onclick: () => showNeg = !showNeg }),
                    ' show downvoted tags (', cntNeg, ')'
                ) : null),
                m('td[colspan=5].tc_you', 'You'),
                m('td[colspan=4].tc_others', 'Total'),
            ),
            m('tr',
                m('td.tc_tagname',  'Tag'),
                m('td.tc_myvote',   'Rating'),
                m('td.tc_myover',   data.mod ? 'O' : null),
                m('td.tc_myspoil',  'Spoiler'),
                m('td.tc_mylie',    'Lie'),
                m('td.tc_mynote'),
                m('td.tc_allvote',  'Rating'),
                m('td.tc_allspoil', 'Spoiler'),
                m('td.tc_alllie'),
                m('td.tc_allwho'),
            ),
        ),
        m('tbody',
            tagcat('cont', 'Content'),
            tagcat('ero',  'Sexual content'),
            tagcat('tech', 'Technical'),
            tagcat('new',  'Newly added tags'),
        ),
        m('tfoot', m('tr',
            m('td[colspan=5]',
                m(DS.Button, {ds}, 'Add tag'),
                ' Discover all tags by browsing the ', m('a[href=/g][target=_blank]', 'tag tree'), '.',
            ),
            m('td[colspan=3]',
                api.loading() ? m('span.spinner') :
                api.error ? m('b', api.error) :
                hasChanges() ? m('b', 'You have unsaved changes') : null,
            ),
            m('td[colspan=2]', m('button[type=submit]', 'Save changes')),
        )),
    ));
    return {view};
});
