let needChange = false, uid, password;

const ChangePass = vnode => {
    let data = { pass1: '', pass2: '' };
    const ref = vnode.attrs.data.ref;
    const api = new Api('UserChangePass');
    const onsubmit = () => api.call({ uid, oldpass: password, newpass: data.pass1 }, res => { if(res) location.href = ref });
    const view = () => m(Form, {api,onsubmit}, m('article',
        m('h1', 'Change password'),
        m('div.warning',
            m('h2', 'Your current password is insecure.'),
            'Your password is listed in a ',
            m('a[href=https://haveibeenpwned.com/][target=_blank]', 'database of leaked passwords'),
            ', please set a new password to continue using your account.'
        ),
        m('fieldset.form',
            m('fieldset',
                m('label[for=pass1]', 'New password'),
                m(Input, { id: 'pass1', class: 'mw', type: 'password', required: 'true', data, field: 'pass1', focus: 1 }),
            ),
            m('fieldset',
                m('label[for=pass2]', 'Repeat'),
                m(Input, { id: 'pass2', class: 'mw', type: 'password', required: 'true', data, field: 'pass2' }),
                data.pass1 !== data.pass2 ? m('p.invalid', 'Passwords do not match') : null,
            ),
            m('fieldset',
                m('input[type=submit][value=Update]'),
                api.loading() ? m('span.spinner') : null,
                api.error ? m('b', m('br'), api.error) : null,
            ),
        ),
    ));
    return {view};
};

const Login = vnode => {
    let data = { username: '', password: '' };
    const ref = vnode.attrs.data.ref;
    const api = new Api('UserLogin');
    const onsubmit = () => api.call(data, res => {
        needChange = res && res.insecurepass;
        uid = res && res.uid;
        password = data.password;
        if (res && res.ok) location.href = ref;
    });
    const view = () => m(Form, {onsubmit, api}, m('article',
        m('h1', 'Login'),
        m('fieldset.form',
            m('fieldset',
                m('label[for=username]', 'Username or email'),
                m(Input, { id: 'username', class: 'mw', tabindex: 1, required: true, data, field: 'username' }),
                m('p', m('a[href=/u/register]', 'No account yet?')),
            ),
            m('fieldset',
                m('label[for=password]', 'Password'),
                m(Input, { id: 'password', class: 'mw', tabindex: 1, required: true, type: 'password', data, field: 'password' }),
                m('p', m('a[href=/u/newpass]', 'Lost your password?')),
            ),
            m('fieldset',
                m('input[type=submit][value=Submit][tabindex=1]'),
                api.loading() ? m('span.spinner') : null,
                api.error ? m('b', m('br'), api.error) : null,
            ),
        ),
    ));
    return {view};
};

widget('UserLogin', { view: v => m(needChange ? ChangePass : Login, v.attrs) });
