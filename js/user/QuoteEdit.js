widget('QuoteEdit', vnode => {
    const data = vnode.attrs.data;
    const api = new Api('QuoteEdit');
    const chr = new DS({
        list: (src, str, cb) => cb(data.chars.filter(c =>
            (c.title + ' ' + c.alttitle).toLowerCase().includes(str.toLowerCase())
        )),
        view: c => [ m('small', c.id, ': '), c.title, m('small', ' ', c.alttitle) ],
    }, { onselect: obj => {
        data.cid = obj.id;
        data.title = obj.title;
        data.alttitle = obj.alttitle;
    }});

    let del = false;
    const delApi = new Api('QuoteDel');

    const redir = () => location.href = '/'+data.vid+'/quotes#quotes';
    return {view: () => [
        m(Form, {api, onsubmit: () => api.call(data, redir) }, m('fieldset.form',
            m('fieldset',
                m('label[for=quote]', 'Quote'),
                m(Input, {id: 'quote', class: 'xw', data, field: 'quote', required: true, maxlength: 170 }),
            ),
            m('fieldset',
                m('label', 'Character', HelpButton('chr')),
                !data.cid ? [] : [
                    m(Button.Del, {onclick: () => data.cid = null }), ' ',
                    m('a[target=_blank]', { href: '/'+data.cid, title: data.alttitle }, data.title),
                    m('br'),
                ],
                m(DS.Button, {ds:chr}, 'Set character'),
            ),
            Help('chr', 'Story character who said this quote. Leave empty for narration or quotes that involve multiple characters.'),
            !pageVars.dbmod ? null : m('fieldset',
                m('label', 'State'),
                m('label.check', m('input[type=radio]', { checked: !data.hidden, oninput: () => data.hidden = false }), ' Visible '),
                m('label.check', m('input[type=radio]', { checked:  data.hidden, oninput: () => data.hidden = true }), ' Deleted '),
            ),
            m('input[type=submit][value=Submit]'),
            m('span.spinner', { class: api.loading() ? '' : 'invisible' }),
            api.error ? m('p.formerror', api.error) : null,

        )), !data.delete ? null : m(Form, {api: delApi, onsubmit: () => delApi.call({id:data.id}, redir) }, m('fieldset.form',
            m('fieldset',
                m('input[type=checkbox]', { checked: del, onclick: ev => del = ev.target.checked }),
                ' Delete this quote',
            ),
            !del ? null : m('fieldset',
                m('input[type=submit][value=Delete]'),
                m('span.spinner', { class: delApi.loading() ? '' : 'invisible' }),
                delApi.error ? m('p.formerror', delApi.error) : null,
            ),
        )),
    ]};
});
