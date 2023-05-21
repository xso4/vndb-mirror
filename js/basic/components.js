// Dropdown box for use in a <li class="maintabs-dd">.
// (This would be trivial enough to inline if it weren't for how tricky it is
// to get the toggle functionality working as it should)
window.MainTabsDD = (initVnode) => {
    let open = false;

    const toggle = (ev) => {
        if (open && initVnode.dom.nextSibling.contains(ev.target)) return;
        open = !open;
        // Defer the listener, otherwise this current event will trigger it.
        if (open) requestAnimationFrame(() => document.addEventListener('click', toggle));
        else document.removeEventListener('click', toggle);
        m.redraw();
    };

    const view = vnode => [
        m('a[href=#]', {
            onclick: (ev) => { ev.preventDefault(); toggle(ev) },
            ...vnode.attrs.a_attrs,
        }, vnode.attrs.a_body),
        open ? m('div', m('div', vnode.attrs.content())) : null,
    ];

    return {view};
};


// Wrapper around a <form> with a <fieldset> element. Attrs:
// - onsubmit    - submit event, already has preventDefault()
// - disabled    - set 'disabled' attribute on the fieldset
// - api         - Api object, sets 'disabled' when api.loading()
// The .invalid class is set on an invalid <form> *after* the user attempts to
// submit it, to help with styling invalid inputs.
window.Form = () => {
    let invalid = false;
    return { view: vnode =>
        m('form', {
            onsubmit: ev => { ev.preventDefault(); const x = vnode.attrs.onsubmit; x && x(ev) },
            // Need a custom listener here to make sure we capture events of child nodes; the 'invalid' event doesn't bubble.
            oncreate: v => v.dom.addEventListener('invalid', () => { invalid = !v.dom.valid; m.redraw() }, true),
            class: invalid ? 'invalid' : ''
        }, m('fieldset',
            { disabled: vnode.attrs.disabled || vnode.attrs.api && vnode.attrs.api.loading() },
            vnode.children
        ))
    };
};


// BBCode (TODO: & Markdown) editor with preview button.
// Attrs:
// - data + field -> raw text is read from and written to data[field]
// - header       -> element to draw at the top-left
// - attrs        -> attrs to add to the textarea
window.TextPreview = initVnode => {
    var preview = false;
    var html = null;
    const {data,field} = initVnode.attrs;
    const api = new Api('BBCode');

    const unload = () => {
        api.abort();
        preview = false;
        return false;
    };

    const load = () => {
        if (html) {
            preview = true;
        } else {
            api.call({content: data[field]}, res => {
                html = res ? res.html : '<b>'+api.error+'</b>';
                preview = true;
            });
        }
        return false;
    };

    const view = vnode => m('div.textpreview',
        m('div',
            m('div', vnode.attrs.header),
            m('div', data[field].length == 0 ? {class:'invisible'}:null,
                api.loading() ? m('span.spinner') : null,
                preview ? m('a[href=#]', {onclick: unload}, 'Edit') : m('span', 'Edit'),
                preview ? m('span', 'Preview') : m('a[href=#]', {onclick: load}, 'Preview'),
            ),
        ),
        m('textarea', {
            class: preview ? 'hidden' : null,
            oninput: e => { html = null; data[field] = e.target.value },
            ...vnode.attrs.attrs
        }, data[field]),
        m('div.preview', { class: preview ? null : 'hidden' }, m.trust(html)),
    );
    return {view};
};


// Edit summary & submit button box for DB entry edit forms.
// Attrs:
// - data  -> form data containing editsum, hidden & locked
// - api   -> Api object for loading & error status
//
// TODO: Support for "awaiting approval" state.
window.EditSum = vnode => {
    const {api,data} = vnode.attrs;
    const rad = (l,h,lab) => m('label',
        m('input[type=radio]', {
            checked: l === data.locked && h === data.hidden,
            oninput: () => { data.locked = l; data.hidden = h }
        }), lab
    );
    const view = () => m('article.submit',
        pageVars.dbmod ? m('fieldset',
            rad(false, false, ' Normal '),
            rad(true , false, ' Locked '),
            rad(true , true , ' Deleted '),
            data.locked && data.hidden ? m('span',
                m('br'), 'Note: edit summary of the last edit should indicate the reason for the deletion.', m('br')
            ) : null,
        ) : null,
        m(TextPreview, {
            data, field: 'editsum',
            attrs: { rows: 4, cols: 50, minlength: 2, maxlength: 5000, required: true },
            header: [
                m('strong', 'Edit summary'),
                m('b', ' (English please!)'),
                m('br'),
                'Summarize the changes you have made, including links to source(s).',
            ]
        }),
        m('input[type=submit][value=Submit]'),
        api.loading() ? m('span.spinner') : null,
        api.error ? m('b', m('br'), api.error) : null,
    );
    return {view};
};
