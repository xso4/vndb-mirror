let needChange = false;
let username = '';
let password = '';

const ChangePass = vnode => {
    let newpass1 = '', newpass2 = '';
    const ref = vnode.attrs.data.ref;
    const api = new Api('UserChangePass');
    const onsubmit = () => api.call({ username, oldpass: password, newpass: newpass1}, res => { if(res) location.href = ref });
    const set = () => document.getElementById('newpass2').setCustomValidity(newpass1 === newpass2 ? '' : 'Passwords do not match.');
    const view = () => m(Form, {api,onsubmit}, m('article',
        m('h1', 'Change password'),
        m('div.warning',
            m('h2', 'Your current password is insecure.'),
            'Your password is listed in a ',
            m('a[href=https://haveibeenpwned.com/][target=blank]', 'database of leaked passwords'),
            ', please set a new password to continue using your account.'
        ),
        m('fieldset.form',
            m('fieldset',
                m('label[for=newpass1]', 'New password'),
                m('input#newpass1.mw[type=password]', {
                    value: newpass1, oninput: e => set(newpass1 = e.target.value), ...formVals.password,
                    oncreate: v => v.dom.focus(),
                }),
            ),
            m('fieldset',
                m('label[for=newpass2]', 'Repeat'),
                m('input#newpass2.mw[type=password]', { value: newpass2, oninput: e => set(newpass2 = e.target.value), ...formVals.password }),
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
    const ref = vnode.attrs.data.ref;
    const api = new Api('UserLogin');
    const onsubmit = ev => {
        // Some crappy password manager autofill implementations don't trigger
        // oninput events, so make sure to read the fields again.
        username = document.getElementById('username').value;
        password = document.getElementById('password').value;
        // And they probably also don't trigger validation, so just to be sure:
        if (!ev.target.checkValidity())
            ev.target.reportValidity();
        else
            api.call({username, password}, res => {
                needChange = res && res.insecurepass;
                if (res && res.ok) location.href = ref;
            });
    };
    const view = () => m(Form, {onsubmit, api}, m('article',
        m('h1', 'Login'),
        m('fieldset.form',
            m('fieldset',
                m('label[for=username]', 'Username'),
                m('input#username.mw[type=text][tabindex=1]',
                    { value: username, oninput: e => username = e.target.value, ...formVals.username }),
                m('p', m('a[href=/u/register]', 'No account yet?')),
            ),
            m('fieldset',
                m('label[for=password]', 'Password'),
                m('input#password.mw[type=password][tabindex=1][required]',
                    { value: password, oninput: e => password = e.target.value, ...formVals.password }),
                m('p', m('a[href=/u/newpass]', 'Lost your username or password?')),
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
