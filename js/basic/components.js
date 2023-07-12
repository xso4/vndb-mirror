const langs = Object.fromEntries(vndbTypes.language);
window.LangIcon = id => m('abbr', { class: 'icon-lang-'+id, title: langs[id] });


// SVG icons from: https://lucide.dev/
// License: MIT
// The nice thing about these is that they all have the same viewbox and fill/stroke options.
// Icon size should be set in CSS.
const icon = svg => m.trust('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><g fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">'+svg+'</g></svg>');
window.Icon = {
    ArrowBigDown: icon('<path d="M15 6v6h4l-7 7-7-7h4V6h6z"/>'),
    ArrowBigUp:   icon('<path d="M9 18v-6H5l7-7 7 7h-4v6H9z"/>'),
    ArrowDownUp:  icon('<path d="m3 16 4 4 4-4"></path><path d="M7 20V4"></path><path d="m21 8-4-4-4 4"></path><path d="M17 4v16"></path>'),
    CheckSquare:  icon('<polyline points="9 11 12 14 22 4"/><path d="M21 12v7a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h11"/>'),
    ChevronDown:  icon('<polyline points="6 9 12 15 18 9">'),
    Copy:         icon('<rect width="14" height="14" x="8" y="8" rx="2" ry="2"></rect><path d="M4 16c-1.1 0-2-.9-2-2V4c0-1.1.9-2 2-2h10c1.1 0 2 .9 2 2"></path>'),
    Eye:          icon('<path d="M2 12s3-7 10-7 10 7 10 7-3 7-10 7-10-7-10-7Z"></path><circle cx="12" cy="12" r="3"></circle>'),
    Info:         icon('<circle cx="12" cy="12" r="10"/><path d="M12 16v-4"/><path d="M12 8h.01"/>'),
    MinusSquare:  icon('<rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><line x1="8" x2="16" y1="12" y2="12"/>'),
    Save:         icon('<path d="M19 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h11l5 5v11a2 2 0 0 1-2 2z"></path><polyline points="17 21 17 13 7 13 7 21"></polyline><polyline points="7 3 7 8 15 8"></polyline>'),
    Search:       icon('<circle cx="11" cy="11" r="8"/><line x1="21" x2="16.65" y1="21" y2="16.65"/>'),
    Trash2:       icon('<path d="M3 6h18M19 6v14c0 1-1 2-2 2H7c-1 0-2-1-2-2V6M8 6V4c0-1 1-2 2-2h4c1 0 2 1 2 2v2M10 11v6M14 11v6"/>'),
    X:            icon('<line x1="18" x2="6" y1="6" y2="18"/><line x1="6" x2="18" y1="6" y2="18"/>'),
};

const but = (icon, title) => ({view: vnode => m('button[type=button].icon', { title,
        onclick: ev => { ev.preventDefault(); vnode.attrs.onclick(ev) },
        style: !('visible' in vnode.attrs) || vnode.attrs.visible ? null : 'visibility:hidden',
    }, icon
)});
window.Button = {
    Del:        but(Icon.Trash2,       'Delete item'),
    Up:         but(Icon.ArrowBigUp,   'Move up'),
    Down:       but(Icon.ArrowBigDown, 'Move down'),
    Copy:       but(Icon.Copy,         'Copy'),
    CheckAll:   but(Icon.CheckSquare,  'Check all'),
    UncheckAll: but(Icon.MinusSquare,  'Uncheck all'),
};

window.DSButton = {view: vnode => m('button.ds[type=button]', {
        class: vnode.attrs.class,
        onclick: ev => { ev.preventDefault(); vnode.attrs.onclick(ev) },
    }, vnode.children, Icon.ChevronDown
)};

const helpState = {};
window.HelpButton = id => m('a.help[href=#][title=Info]',
    { onclick: ev => { ev.preventDefault(); helpState[id] = !helpState[id]; } },
    Icon.Info
);
window.Help = (id, ...content) => helpState[id] ? m('section.help',
    { oncreate: vnode => vnode.dom.scrollIntoView({behavior: 'smooth', block: 'nearest', inline: 'nearest'}) },
    m('a[href=#]', { onclick: ev => { ev.preventDefault(); helpState[id] = false; } }, Icon.X),
    content
) : null;



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


// Release dates are integers with the following format: 0, 1 or yyyymmdd
// Special values
//          0 -> unknown
//          1 -> "today" (only used as filter)
//   99999999 -> TBA
//   yyyy9999 -> year known, month & day unknown
//   yyyymm99 -> year & month known, day unknown
//
// This component provides a friendly input for such dates.
// Attrs:
// - value
// - oninput  -> callback accepting the new value
// - id       -> id of the first select input
// - today    -> bool, whether "today" should be accepted as an option
// - unknown  -> bool, whether "unknown" should be accepted as an option
window.RDate = () => {
    const expand = v => ({
        y: Math.floor(v / 10000),
        m: Math.floor(v / 100) % 100,
        d: v % 100,
    });
    const compact = ({y,m,d}) => y * 10000 + m * 100 + d;
    const maxDay = ({y,m}) => new Date(y, m, 0).getDate();
    const normalize = ({y,m,d}) =>
        y ===    0 ? { y: 0, m: 0, d: d?1:0 } :
        y === 9999 ? { y: 9999, m: 99, d: 99 } :
        m ===    0 || m === 99 ? { y, m: 99, d: 99 } :
        { y,m, d: d === 0 || d === 99 ? 99 : Math.min(d, maxDay({y,m})) };
    const range = (start,end,f) => new Array(end-start+1).fill(0).map((x,i) => f(start+i));
    const months = [ 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec' ];
    const view = vnode => {
        const v = expand(vnode.attrs.value);
        const oninput = ev => vnode.attrs.oninput && vnode.attrs.oninput(Math.floor(ev.target.options[ev.target.selectedIndex].value));
        const o = (e,l) => {
            const value = compact(normalize({...v, ...e}));
            return m('option', { value, selected: value === vnode.attrs.value }, l);
        };
        return [
            m('select', {oninput, id: vnode.attrs.id},
                vnode.attrs.today ? o({y:1}, 'Today') : null,
                vnode.attrs.unknown ? o({y:0}, 'Unknown') : null,
                o({y:9999}, 'TBA'),
                range(1980, new Date().getFullYear()+5, y => o({y},y)).reverse(),
            ),
            v.y > 0 && v.y < 9999 ? m('select', {oninput},
                o({m:99}, '- month -'),
                range(1, 12, m => o({m}, m + ' (' + months[m-1] + ')')),
            ) : null,
            v.m > 0 && v.m < 99 ? m('select', {oninput},
                o({d:99}, '- day -'),
                range(1, maxDay(v), d => o({d},d)),
            ) : null,
        ];
    };
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
