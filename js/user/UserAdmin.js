widget('UserAdmin', initVnode => {
    const data = initVnode.attrs.data;
    const api = new Api('UserAdmin');
    const chk = (opt, perm, label, dis) => !data['editor_'+perm] ? null : m('label.check',
        m('input[type=checkbox]', { disabled: dis, checked: data['perm_'+opt], oninput: e => data['perm_'+opt] = e.target.checked }),
        ' ', opt, m('small', ' (', label, ')'), m('br')
    );
    const none = {
        perm_board: false, perm_review: false, perm_edit: false, perm_imgvote: false, perm_lengthvote: false, perm_tag: false,
        perm_boardmod: false, perm_usermod: data.perm_usermod, perm_tagmod: false, perm_dbmod: false
    };
    const def = {
        perm_board: true, perm_review: true, perm_edit: true, perm_imgvote: true, perm_lengthvote: true, perm_tag: true,
        perm_boardmod: false, perm_usermod: data.perm_usermod, perm_tagmod: false, perm_dbmod: false
    };
    const view = () => m(Form, {api, onsubmit: () => api.call(data)},
        m('article',
            m('h1', 'Admin settings for '+(data.username||data.id)),
            m('fieldset.form',
                m('fieldset',
                    m('label', 'Preset'),
                    m('input[type=button][value=None]', { onclick: () => Object.assign(data, none) }),
                    m('input[type=button][value=Default]', { onclick: () => Object.assign(data, def) }),
                ),
                m('fieldset',
                    m('label', data.editor_usermod ? 'User perms' : 'Permissions'),
                    chk('board',      'boardmod', 'creating new threads and replying to existing threads and reviews'),
                    chk('review',     'boardmod', 'submitting new reviews'),
                    chk('edit',       'dbmod',    'database editing & tag voting'),
                    chk('imgvote',    'dbmod',    'flagging images - existing votes stop counting when unset'),
                    chk('lengthvote', 'dbmod',    'submitting VN play times - existing votes stop counting when unset'),
                    chk('tag',        'tagmod',   'voting on VN tags - existing votes stop counting when unset'),
                ),
                !data.editor_usermod ? null : m('fieldset',
                    m('label', 'Mod perms'),
                    chk('dbmod',      'usermod',  'database moderation'),
                    chk('tagmod',     'usermod',  'tags'),
                    chk('boardmod',   'usermod',  'forums & reviews'),
                    chk('usermod',    'usermod',  'full user editing - this flag can only be changed through SQL', true),
                ),
                !data.editor_usermod ? null : m('fieldset',
                    m('label', 'Other'),
                    m('label.check',
                        m('input[type=checkbox]', { checked: data.ign_votes, oninput: e => data.ign_votes = e.target.checked }),
                        ' Ignore votes in VN statistics'
                    ),
                ),
                m('fieldset',
                    m('input[type=submit][value=Update]'),
                    api.Status(),
                    api.saved(data) ? 'Saved!' : null
                ),
            )
        )
    );
    return {view};
});
