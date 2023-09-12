widget('UserPassSet', vnode => {
    const api = new Api('UserPassSet');
    const data = vnode.attrs.data;
    data.password = data.repeat = '';
    const onsubmit = () => api.call(data, null,
        err => err && err.insecure && $('#password').focus()
    );
    const view = () => m(Form, {api, onsubmit}, m('article',
        m('h1', 'Set your password'),
        m('fieldset.form',
            m('p', 'Now you can set a password for your account. You will be logged in automatically after your password has been saved.'),
            m('fieldset',
                m('label[for=password]', 'New password'),
                m(Input, {
                    id: 'password', class: 'mw', type: 'password', required: true, data, field: 'password',
                    oninput: () => api.abort(),
                }),
            ),
            m('fieldset',
                m('label[for=repeat]', 'Repeat'),
                m(Input, {
                    id: 'repeat', class: 'mw', type: 'password', required: true, data, field: 'repeat',
                    invalid: data.password !== '' && data.password === data.repeat ? '' : 'Passwords do not match.',
                }),
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
