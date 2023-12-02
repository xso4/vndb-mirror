widget('UserRegister', vnode => {
    let c18 = false, cpolicy = false, ccheck = false, success = false;
    const api = new Api('UserRegister');
    const data = { username: '', email: '' };
    const dupnames = {};
    const onsubmit = ev => api.call(data, res => {
        if (res && res.err === 'username') dupnames[data.username] = true;
        success = res && res.ok;
    });
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
                m(Input, {
                    id: 'username', type: 'username', class: 'mw', required: true, data, field: 'username',
                    invalid: dupnames[data.username] ? 'Username already taken' : null,
                }),
                m('p', username_reqs),
            ),
            m('fieldset',
                m('label[for=email]', 'E-Mail'),
                m(Input, {
                    id: 'email', type: 'email', class: 'mw', required: true, data, field: 'email',
                }),
                m('p',
                    'A valid address is required in order to activate and use your account. ',
                    'Other than that, your address is only used in case you lose your password, ',
                    'we will never send spam or newsletters unless you explicitly ask us for it or we get hacked.',
                ),
            ),
            m('fieldset',
                m('label.check',
                    m('input#c18[type=checkbox]', { checked: c18, oninput: ev => c18 = ev.target.checked }),
                    ' I am 18 years or older.'
                ),
                c18 ? null : m('p.invalid', 'You must be 18 years or older to use this site.'),
            ),
            m('fieldset',
                m('label.check',
                    m('input#cpolicy[type=checkbox]', { checked: cpolicy, oninput: ev => cpolicy = ev.target.checked }),
                    ' I have read the ', m('a[href=/d17]', 'privacy policy and contributor license agreement'), '.'
                ),
                cpolicy ? null : m('p.invalid', "You can at least pretend you've read it."),
            ),
            m('fieldset',
                m('label.check',
                    m('input#ccheck[type=checkbox]', { checked: ccheck, oninput: ev => ccheck = ev.target.checked }),
                    ' I click checkboxes without reading the label.'
                ),
                ccheck ? m('p.invalid', "*sigh* don't do that.") : null,
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
