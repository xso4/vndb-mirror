widget('UserPassReset', () => {
    const api = new Api('UserPassReset');
    const data = {email:''};
    let done = false;
    const onsubmit = () => api.call(data, () => done = true);
    const view = () => m(Form, {api, onsubmit}, m('article',
        m('h1', 'Forgot password'),
        done ? m('div.notice',
            m('h2', 'Check your email'),
            m('p', 'Instructions to set a new password should reach your mailbox in a few minutes.'),
            m('p', '(make sure to check your spam box if the mail doesn\'t seem to be arriving)'),
        ) : m('fieldset.form',
            m('p',
                'Forgot your password and can\'t login to VNDB anymore? ',
                'Don\'t worry! Just give us the email address you used to register on VNDB ',
                ' and we\'ll send you instructions to set a new password within a few minutes!'
            ),
            m('fieldset',
                m('label[for=email]', 'E-Mail'),
                m(EmailInput, { id: 'email', class: 'mw', required: true, data, field: 'email' }),
            ),
            m('fieldset',
                m('input[type=submit][value=Submit]'),
                api.Status(),
            ),
        )
    ));
    return {view};
});
