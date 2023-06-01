const langs = Object.fromEntries(vndbTypes.language);
window.LangIcon = id => m('abbr', { class: 'icon-lang-'+id, title: langs[id] });


const but = (title, svg) => ({view: vnode => m('button.icon', { title,
        onclick: ev => { ev.preventDefault(); vnode.attrs.onclick(ev) },
        style: { visibility: !('visible' in vnode.attrs) || vnode.attrs.visible ? 'visible' : 'hidden' },
    }, m.trust(svg)
)});

// SVG icons from: https://lucide.dev/
// License: MIT
window.DelButton  = but('Delete item', '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="none" stroke="currentColor" stroke-linecap="round" stroke-width="2" d="M3 6h18M19 6v14c0 1-1 2-2 2H7c-1 0-2-1-2-2V6M8 6V4c0-1 1-2 2-2h4c1 0 2 1 2 2v2M10 11v6M14 11v6"/></svg>');
window.UpButton   = but('Move up',     '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="none" stroke="currentColor" stroke-linecap="round" stroke-width="2" d="M9 18v-6H5l7-7 7 7h-4v6H9z"></path></svg>');
window.DownButton = but('Move down',   '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="none" stroke="currentColor" stroke-linecap="round" stroke-width="2" d="M15 6v6h4l-7 7-7-7h4V6h6z"/></svg>');


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


// Wrapper around a <form> with a <fieldset> element and some magic.
// Attrs:
// - onsubmit    - submit event, already has preventDefault()
// - disabled    - set 'disabled' attribute on the fieldset
// - api         - Api object, see below, also sets 'disabled' when api.loading()
//
// The .invalid class is set on an invalid <form> *after* the user attempts to
// submit it, to help with styling invalid inputs.
//
// The api object is monitored for errors. If the error response includes a
// '_field' member, then a setCustomValidity() and reportValidity() is
// performed on the element with that ID. It is up to the form code to reset
// the error in response to an 'oninput' event.
window.Form = () => {
    let invalid = false, lasterr;
    return { view: vnode => {
        const api = vnode.attrs.api;
        return m('form', {
            class: invalid ? 'invalid' : '',
            onsubmit: ev => { ev.preventDefault(); const x = vnode.attrs.onsubmit; x && x(ev) },
            // Need a custom listener here to make sure we capture events of child nodes; the 'invalid' event doesn't bubble.
            oncreate: v => v.dom.addEventListener('invalid', () => { invalid = !v.dom.valid; m.redraw() }, true),
            onupdate: v => {
                if (!api || lasterr === api.error) return;
                lasterr = api.error;
                const res = api.xhr && api.xhr.response;
                if (api.error && res !== null && 'object' === typeof res && res._field) {
                    $('#'+res._field).setCustomValidity(res._fielderr || api.error);
                    // reportValidity() will synchronously run all 'invalid'
                    // events, but those aren't necessarily written to be
                    // called during a m.render context, so delay it for a bit.
                    requestAnimationFrame(() => v.dom.reportValidity());
                }
            },
        }, m('fieldset',
            { disabled: vnode.attrs.disabled || (api && api.loading()) },
            vnode.children
        ))
    }};
};


// Draw a form with multiple tabs, attrs:
// - tabs    - Array of tabs, each tab is a 3-element arrays:
//     [ id, label, func ]
//   func should return the contents of the tab.
// - sel     - Id of initially selected tab.
//
// The currently selected tab is tracked in location.hash, so linking to a
// specific tab is possible.
//
// There's a fair bit of magic going on to integrate with form validation: when
// a validation error is reported, this component automatically switches to the
// first tab containing the error. Tab headers also indicate which tabs contain
// errors.
//
// The list of tabs must be static and known at component creation time,
// dynamically adding/removing tabs is not supported.
window.FormTabs = initVnode => {
    const tabs = initVnode.attrs.tabs;
    const h = location.hash.replace('#', '');
    let sel = initVnode.attrs.sel || (
        h && (h === 'all' || tabs.find(t => t[0] === h)) ? h : tabs[0][0]
    );
    let report;
    const set = n => location.replace('#'+(sel=n));
    const onclick = ev => {
        ev.preventDefault();
        set(ev.target.href.replace(/^.+#/, ''));
    };
    // If there is a form validation error, we have to make sure that the field
    // being reported is actually visible. If not, switch to the first invalid
    // tab and re-report the error.
    // Assumption: reportValidity() is always only used on the global form and
    // not on individual elements, and it always reports the first invalid
    // field in the DOM.
    const oninvalid = () => {
        // XXX: Validation on fieldsets is weird. No errors are reported
        // through the JS validation API, but the :invalid CSS selector still
        // matches. Let's just abuse that.
        if(sel === 'all' || $('#formtabs_'+sel+':invalid')) return;
        for (const t of tabs) {
            if (sel === t[0] || $('#formtabs_'+t[0]+':valid')) continue;
            set(t[0]);
            report = true;
            m.redraw();
            return;
        }
    };
    const view = () => [
        tabs.length > 1 ? m('nav', m('menu',
            tabs.concat([['all', 'All items']]).map(t =>
                m('li', { key: t[0], id: 'formtabst_'+t[0], class: sel === t[0] ? 'tabselected' : ''},
                    m('a', {onclick, href: '#'+t[0]}, t[1])
                )
            ),
        )) : null,
        tabs.map(t => m('article',
            { key: t[0], class: sel === t[0] || sel === 'all' ? '' : 'hidden' },
            m('fieldset', {id: 'formtabs_'+t[0]}, t[2]())
        )),
    ];
    const oncreate = v => v.dom.closest('form').addEventListener('invalid', oninvalid, true);
    const onupdate = v => requestAnimationFrame(() => {
        if (report) requestAnimationFrame(() => v.dom.closest('form').reportValidity());
        report = false;
        // Set the 'invalid' class on the tabs. The form state is not known
        // during the view function, so this has to be done in an onupdate hook.
        if (tabs.length > 1)
            for (const t of tabs)
                $('#formtabst_'+t[0]).classList.toggle('invalid', !!$('#formtabs_'+t[0]+':invalid'));
    });
    return {view,oncreate,onupdate};
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
