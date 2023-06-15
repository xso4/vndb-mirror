widget('UserRegister', vnode => {
    let success = false;
    const api = new Api('UserRegister');
    const onsubmit = ev => {
        let username = $('#username').value;
        let email = $('#email').value;
        let c18 = $('#c18').checked;
        let cpolicy = $('#cpolicy').checked;
        let ccheck = $('#ccheck').checked;
        // HTML5 validity API should take care of this, but mobile browsers may not do that properly.
        // (username & email are also validated on the server, so those have a fallback already)
        if (!c18 || !cpolicy || ccheck) return;
        api.call({username, email}, res => success = res && res.ok);
    };
    const donemsg = m('article',
        m('h1', 'Account created'),
        m('div.notice', m('p',
            'Your account has been created!', m('br'),
            'Check your inbox for an email with instructions to activate your account.', m('br'),
            "(also make sure to check your spam box if it doesn't seem to be arriving)"
        ))
    );
    const view = () => success ? donemsg : m(Form, {onsubmit, api}, m('article',
        m('h1', 'Create an account'),
        m('fieldset.form',
            m('fieldset',
                m('label[for=username]', 'Username'),
                m('input#username.mw[type=text]', formVals.username),
                m('p', username_reqs),
            ),
            m('fieldset',
                m('label[for=email]', 'E-Mail'),
                m('input#email.mw[type=email][required]', formVals.email),
                m('p',
                    'A valid address is required in order to activate and use your account. ',
                    'Other than that, your address is only used in case you lose your password, ',
                    'we will never send spam or newsletters unless you explicitly ask us for it or we get hacked.',
                ),
            ),
            m('fieldset',
                m('label.check',
                    m('input#c18[type=checkbox][required]'),
                    ' I am 18 years or older.'
                ),
            ),
            m('fieldset',
                m('label.check',
                    m('input#cpolicy[type=checkbox][required]'),
                    ' I have read the ', m('a[href=/d17]', 'privacy policy and contributor license agreement'), '.'
                ),
            ),
            m('fieldset',
                m('label.check',
                    m('input#ccheck[type=checkbox]', { oninput: ev => ev.target.setCustomValidity(ev.target.checked ? 'Sigh.' : '') }),
                    ' I click checkboxes without reading their label.'
                ),
            ),
            m('fieldset',
                m('input[type=submit][value=Submit]'),
                api.loading() ? m('span.spinner') : null,
                api.error ? m('b', m('br'), api.error) : null,
            ),
        ),
    ));
    return {view};
});
