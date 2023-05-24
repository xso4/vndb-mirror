const Username = () => {
    let edit = false, old = '';
    return {view: v => m('fieldset.form',
        m('legend', 'Username'),
        m('fieldset', !edit ? [
            m('label', 'Current'),
            v.attrs.data.username,
            ' ',
            v.attrs.data.username_throttled
            ? m('small', '(changed within the past 24 hours)')
            : m('input[type=button][value=Edit]', { onclick: () => { old = v.attrs.data.username; edit = true } }),
        ] : [
            m('label[for=username]', 'New username'),
            m('input#username.mw[type=text]', {
                oninput: e => {
                    v.attrs.data.username = e.target.value;
                    e.target.setCustomValidity('');
                },
                oncreate: n => {
                    n.dom.value = v.attrs.data.username;
                    n.dom.focus();
                },
                ...formVals.username }),
            m('input[type=button][value=Cancel]', { onclick: () => { v.attrs.data.username = old; edit = false } }),
            m('p',
                'Things to keep in mind:', m('br'),
                '- Your old username(s) will be displayed on your profile for a month after the change.', m('br'),
                '- You will not be able to log in with your old username(s).', m('br'),
                '- Your old username will become available for other people to claim.', m('br'),
                '- You may only change your username at once per day.',
            ),
        ]),
    )};
};

const Email = () => {
    let edit = false, old = '';
    return {view: v => m('fieldset.form',
        m('legend', 'E-Mail'),
        m('fieldset', !edit ? [
            m('label', 'Current'), v.attrs.data.email, ' ',
            m('input[type=button][value=Edit]', { onclick: () => { old = v.attrs.data.email; edit = true } }),
        ] : [
            m('label[for=email]', 'New email'),
            m('input#email.mw[type=text]', {
                oninput: e => {
                    v.attrs.data.email = e.target.value;
                    e.target.setCustomValidity('');
                },
                oncreate: n => {
                    n.dom.value = v.attrs.data.email;
                    n.dom.focus();
                },
                ...formVals.email }),
            m('input[type=button][value=Cancel]', { onclick: () => { v.attrs.data.email = old; edit = false } }),
            m('p', 'A verification mail will be send to your new address.'),
        ]),
    )};
};

const Password = () => {
    let edit = false, repeat = '';
    return {view: v => m('fieldset.form',
        m('legend', 'Password'),
        m('label.check',
            m('input[type=checkbox]', { oninput: e => {
                edit = e.target.checked;
                if (!edit) {
                    v.attrs.data.password = null;
                    repeat = '';
                } else
                    v.attrs.data.password = { old: '', new: '' };
            }}),
            ' Change password'
        ),
        !edit ? [] : [
            m('fieldset',
                m('label[for=opass]', 'Current password'),
                m('input#opass.mw[type=password]', {
                    oninput: e => {
                        v.attrs.data.password.old = e.target.value;
                        e.target.setCustomValidity('');
                    },
                    oncreate: v => v.dom.focus(),
                    ...formVals.password
                }),
            ),
            m('fieldset',
                m('label[for=npass]', 'New password'),
                m('input#npass.mw[type=password]', {
                    oninput: e => {
                        v.attrs.data.password.new = e.target.value;
                        e.target.setCustomValidity('');
                    },
                    ...formVals.password
                }),
            ),
            m('fieldset',
                m('label[for=rpass]', 'Repeat'),
                m('input#rpass.mw[type=password]', {
                    oninput: e => repeat = e.target.value,
                    onupdate: n => n.dom.setCustomValidity(v.attrs.data.password.new === repeat ? '' : 'Passwords do not match.'),
                    ...formVals.password
                }),
            ),
        ]
    )};
};

const Support = initVnode => {
    const data = initVnode.attrs.data;
    return {view: () => data.editor_usermod || data.nodistract_can || data.support_can || data.uniname_can || data.pubskin_can ? m('fieldset.form',
        m('legend', 'Supporter options⭐'),
        data.editor_usermod ? m('p',
            'Enabled options: ' + (['nodistract', 'support', 'uniname', 'pubskin'].filter(x => data[x+'_can']).join(', ')||'none') + '.'
        ) : null,
        data.editor_usermod || data.nodistract_can ? m('fieldset',
            m('label.check',
                m('input[type=checkbox]', { checked: data.nodistract_noads, oninput: e => data.nodistract_noads = e.target.checked }),
                ' Disable advertising and other distractions (only hides the support box for the moment)',
            ),
            m('br'),
            m('label.check',
                m('input[type=checkbox]', { checked: data.nodistract_nofancy, oninput: e => data.nodistract_nofancy = e.target.checked }),
                ' Disable supporters badges, custom display names and profile skins',
            ),
        ) : null,
        data.editor_usermod || data.support_can ? m('fieldset',
            m('label.check',
                m('input[type=checkbox]', { checked: data.support_enabled, oninput: e => data.support_enabled = e.target.checked }),
                ' Display my supporters badge',
            )
        ) : null,
        data.editor_usermod || data.pubskin_can ? m('fieldset',
            m('label.check',
                m('input[type=checkbox]', { checked: data.pubskin_enabled, oninput: e => data.pubskin_enabled = e.target.checked }),
                ' Apply my skin and custom CSS when others visit my profile',
            )
        ) : null,
        data.editor_usermod || data.uniname_can ? m('fieldset',
            m('label[for=uniname]', 'Display name'),
            m('input#uniname[type=text][pattern=^.{2,15}$]', {
                value: data.uniname,
                placeholder: data.username,
                oninput: e => { e.target.setCustomValidity(''); data.uniname = e.target.value },
            }),
            m('p', 'Between 2 and 15 characters, all unicode characters are accepted.'),
        ) : null,
    ) : null};
};

widget('UserEdit', initVnode => {
    let msg = '';
    const data = initVnode.attrs.data;
    const api = new Api('UserEdit');
    const onsubmit = ev => api.call(data, res => {
        msg = !res ? '' : res.email
              ? 'A confirmation email has been sent to your new address. Your address will be updated after following the instructions in that mail.'
              : 'Saved!';
        // XXX: Timeout is ugly, better remove the message on user interaction with the form.
        if (msg) setTimeout(() => { msg = ''; m.redraw() }, 5000);
    });

    const account = () => [
        m('h1', 'Account'),
        m(Username, {data}),
        m(Email, {data}),
        m(Password, {data}),
        m(Support, {data}),
    ];

    const display = () => [
        m('h1', 'Display preferences'),
    ];

    const tabs = [
        [ 'account', 'Account', account ],
        [ 'display', 'Display Preferences', display ],
    ];
    const view = () => m(Form, {onsubmit,api},
        m(FormTabs, {tabs}),
        m('article.submit',
            m('input[type=submit][value=Submit]'),
            m('span.spinner', { class: api.loading() ? '' : 'invisible' }),
            msg ? m('p', msg) : api.error ? m('b', m('br'), api.error) : null,
        ),
    );
    return {view};
});
