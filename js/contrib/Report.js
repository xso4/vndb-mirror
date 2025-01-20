const editable = /^[vrpcs]/;
const hasimage = /^[vrc]/;
// Name, Objtypes, cansubmit, msg
const reasons = [
    [ '-- Select --' ],
    [ 'Spam', /^[^dgiu]/, true ],
    [ 'Typo', /^[dgi]/, true ],
    [ 'Broken link', /^[dgi]/, true ],
    [ 'Wrong location in the tag tree', /^g/, false, () =>
        'Please report suggestions about a better tag organization on the forums, so that other people have a chance to chime in as well.',
    ],
    [ 'Wrong location in the trait tree', /^i/, false, () =>
        'Please report suggestions about a better tag organization on the forums, so that other people have a chance to chime in as well.',
    ],
    [ 'Confusing or incorrect tag description', /^g/, false, () =>
        'Please report tag improvement suggestions on the forums, so that other people have a chance to chime in as well.',
    ],
    [ 'Confusing or incorrect trait description', /^i/, false, () =>
        'Please report trait improvement suggestions on the forums, so that other people have a chance to chime in as well.',
    ],
    [ 'Sexual content involving minors', hasimage, true, () => [
        m('strong', 'DO NOT report:'), m('br'),
        '- Lolicon or shotacon with anime-style art.', m('br'),
        '- Text-only sexual content.', m('br'),
        m('strong', 'DO report:'), m('br'),
        '- Semi-realistic 3D art, realistic looking AI-generated art or actual photos.',
    ] ],
    [ 'Links to piracy or illegal content', /^[^udgi]/, true ],
    [ 'Off-topic', /^[tw]/, true ],
    [ 'Unwelcome behavior', /^[tw]/, true ],
    [ 'Unmarked spoilers', /^[^u]/, true, id => (editable.test(id) ? [
        'VNDB is an open wiki, it is often easier if you removed the spoilers yourself by ',
        m('a', { href: '/'+id+'/edit' }, 'editing the entry'),
        '. You likely know more about this entry than our moderators, after all.',
        m('br'),
        "If you're not sure whether something is a spoiler or if you need help with editing, you can also report this issue on the ",
        m('a[href=/t/db]', 'discussion board'),
        ' so that others may be able to help you.',
    ] : 'Please clearly explain what the spoiler is.') ],
    [ 'Unmarked or improperly flagged NSFW image', hasimage, true ],
    [ 'Incorrect information', editable, false, id => [
        'VNDB is an open wiki, you can correct the information in this database yourself by ',
        m('a', { href: '/'+id+'/edit' }, 'editing the entry'),
        '. You likely know more about this entry than our moderators, after all.',
        m('br'),
        'If you need help with editing, you can also report this issue on the ',
        m('a[href=/t/db]', 'discussion board'),
        ' so that others may be able to help you.'
    ] ],
    [ 'Missing information', editable, false, () => [
        'VNDB is an open wiki, you can add any missing information to this database yourself. ',
        'You likely know more about this entry than our moderators, after all.',
        m('br'),
        'If you need help with contributing information, feel free to ask around on the ',
        m('a[href=/t/db]', 'discussion board'),
        ' so that others may be able to help you.'
    ] ],
    [ 'Not a visual novel', /^v/, false, () => [
        'If you suspect that this entry does not adhere to our ',
        m('a[href=/d2#1]', 'Inclusion criteria'),
        ', please report it in ',
        m('a[href=/t2108]', 'this thread'),
        ', so that other users have a chance to provide feedback before a moderator makes their decision.',
    ] ],
    [ 'Does not belong here', /^[rpcs]/, true ],
    [ 'Duplicate entry', editable, true, () => 'Please include a link to the entry that this is a duplicate of.' ],
    [ 'Personal information removal request', editable, false, () => [
        "If the page contains personal information about you (as a developer, translator or otherwise) ",
        "that you're not comfortable with, please contact us at contact@vndb.org."
    ] ],
    [ 'Engages in vote manipulation', /^u/, true ],
    [ 'Other', null, true, id => editable.test(id) ? [
        'Keep in mind that VNDB is an open wiki, you can edit most of the information in this database.',
        m('br'),
        'Reports for issues that do not require a moderator to get involved will most likely be ignored.',
        m('br'),
        'If you need help with contributing to the database, feel free to ask around on the ',
        m('a[href=/t/db]', 'discussion board', '.'),
    ] : null ],
];


widget('Report', vnode => {
    const data = vnode.attrs.data;
    const api = new Api('Report');
    const list = reasons.filter(([_,re]) => !re || re.test(data.object));

    var ok = false;
    const onsubmit = () => api.call(data, () => ok = true);
    const view = () => m(Form, {api, onsubmit}, m('article',
        m('h1', 'Submit report'),
        ok
        ? m('p', 'Your report has been submitted, a moderator will look at it as soon as possible.')
        : m('fieldset.form',
            m('fieldset',
                m('label', 'Subject'),
                m.trust(data.title),
                m('br'),
                'Your report will be forwarded to a moderator.',
                m('br'),
                data.loggedin
                ? 'We usually do not provide feedback on reports, but a moderator may contact you for clarification.'
                : 'We usually do not provide feedback on reports, but you may leave your email address in the message if you wish to be available for clarification.',
                m('br'),
                'Keep in mind that not every report is acted upon, we may decide that the problem you ',
                'reported is does not violate any rules or does not require moderator intervention.',
            ),
            m('fieldset',
                m('label[for=reason]', 'Reason'),
                m(Select, { id: 'reason', class: 'xw', data, field: 'reason', options: list.map(([t]) => [t,t]) }),
            ),
            (([a,b,cansubmit,msg]) => [
                msg ? m('fieldset', msg(data.object)) : null,
                cansubmit ? m('fieldset',
                    m('label[for=message]', 'Message'),
                    m(Input, { id: 'message', class: 'xw', type: 'textarea', rows: 5, data, field: 'message' }),
                ) : null,
                cansubmit ? [
                    m('input[type=submit][value=Submit]'),
                    api.Status(),
                ] : [],
            ])(list.filter(([l]) => l === data.reason)[0] || reasons[0]),
        ),
    ));
    return {view};
});
