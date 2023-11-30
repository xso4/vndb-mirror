const langs = Object.fromEntries(vndbTypes.language);
const plats = Object.fromEntries(vndbTypes.platform);
window.LangIcon = id => m('abbr', { class: 'icon-lang-'+id, title: langs[id] });
window.PlatIcon = id => m('abbr', { class: 'icon-plat-'+id, title: plats[id] });


// SVG icons from: https://lucide.dev/
// License: MIT
// The nice thing about these is that they all have the same viewbox and fill/stroke options.
// Icon size should be set in CSS.
const icon = svg => ({
    view: () => m.trust('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><g fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">'+svg+'</g></svg>'),
    raw: svg,
});
window.Icon = {
    ArrowBigDown: icon('<path d="M15 6v6h4l-7 7-7-7h4V6h6z"/>'),
    ArrowBigUp:   icon('<path d="M9 18v-6H5l7-7 7 7h-4v6H9z"/>'),
    ArrowDownUp:  icon('<path d="m3 16 4 4 4-4"></path><path d="M7 20V4"></path><path d="m21 8-4-4-4 4"></path><path d="M17 4v16"></path>'),
    CheckSquare:  icon('<polyline points="9 11 12 14 22 4"/><path d="M21 12v7a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h11"/>'),
    ChevronDown:  icon('<polyline points="6 9 12 15 18 9">'),
    Copy:         icon('<rect width="14" height="14" x="8" y="8" rx="2" ry="2"></rect><path d="M4 16c-1.1 0-2-.9-2-2V4c0-1.1.9-2 2-2h10c1.1 0 2 .9 2 2"></path>'),
    Eye:          icon('<path d="M2 12s3-7 10-7 10 7 10 7-3 7-10 7-10-7-10-7Z"></path><circle cx="12" cy="12" r="3"></circle>'),
    FolderHeart:  icon('<path d="M11 20H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h3.9a2 2 0 0 1 1.69.9l.81 1.2a2 2 0 0 0 1.67.9H20a2 2 0 0 1 2 2v1.5"/><path d="M13.9 17.45c-1.2-1.2-1.14-2.8-.2-3.73a2.43 2.43 0 0 1 3.44 0l.36.34.34-.34a2.43 2.43 0 0 1 3.45-.01v0c.95.95 1 2.53-.2 3.74L17.5 21Z"/>'),
    Globe:        icon('<circle cx="12" cy="12" r="10"/><path d="M12 2a14.5 14.5 0 0 0 0 20 14.5 14.5 0 0 0 0-20"/><path d="M2 12h20"/>'),
    Info:         icon('<circle cx="12" cy="12" r="10"/><path d="M12 16v-4"/><path d="M12 8h.01"/>'),
    MinusSquare:  icon('<rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><line x1="8" x2="16" y1="12" y2="12"/>'),
    Redo2:        icon('<path d="m15 14 5-5-5-5"/><path d="M20 9H9.5A5.5 5.5 0 0 0 4 14.5v0A5.5 5.5 0 0 0 9.5 20H13"/>'),
    Replace:      icon('<path d="M14 4c0-1.1.9-2 2-2"/><path d="M20 2c1.1 0 2 .9 2 2"/><path d="M22 8c0 1.1-.9 2-2 2"/><path d="M16 10c-1.1 0-2-.9-2-2"/><path d="m3 7 3 3 3-3"/><path d="M6 10V5c0-1.7 1.3-3 3-3h1"/><rect width="8" height="8" x="2" y="14" rx="2"/>'),
    Save:         icon('<path d="M19 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h11l5 5v11a2 2 0 0 1-2 2z"></path><polyline points="17 21 17 13 7 13 7 21"></polyline><polyline points="7 3 7 8 15 8"></polyline>'),
    Search:       icon('<circle cx="11" cy="11" r="8"/><line x1="21" x2="16.65" y1="21" y2="16.65"/>'),
    StepForward:  icon('<line x1="6" x2="6" y1="4" y2="20"/><polygon points="10,4 20,12 10,20"/>'),
    Trash2:       icon('<path d="M3 6h18M19 6v14c0 1-1 2-2 2H7c-1 0-2-1-2-2V6M8 6V4c0-1 1-2 2-2h4c1 0 2 1 2 2v2M10 11v6M14 11v6"/>'),
    Tv:           icon('<rect width="20" height="15" x="2" y="7" rx="2" ry="2"/><polyline points="17 2 12 7 7 2"/>'),
    Users2:       icon('<path d="M14 19a6 6 0 0 0-12 0"/><circle cx="8" cy="9" r="4"/><path d="M22 19a6 6 0 0 0-6-6 4 4 0 1 0 0-8"/>'),
    X:            icon('<line x1="18" x2="6" y1="6" y2="18"/><line x1="6" x2="18" y1="6" y2="18"/>'),
};

const but = (icon, title) => ({view: vnode => m('button[type=button].icon', { title,
        onclick: ev => { ev.preventDefault(); vnode.attrs.onclick(ev) },
        style: !('visible' in vnode.attrs) || vnode.attrs.visible ? null : 'visibility:hidden',
    }, m(icon)
)});
window.Button = {
    Del:        but(Icon.Trash2,       'Delete item'),
    Up:         but(Icon.ArrowBigUp,   'Move up'),
    Down:       but(Icon.ArrowBigDown, 'Move down'),
    Copy:       but(Icon.Copy,         'Copy'),
    CheckAll:   but(Icon.CheckSquare,  'Check all'),
    UncheckAll: but(Icon.MinusSquare,  'Uncheck all'),
};

const helpState = {};
window.HelpButton = id => m('a.help[href=#][title=Info]',
    { onclick: ev => { ev.preventDefault(); helpState[id] = !helpState[id]; } },
    m(Icon.Info)
);
window.Help = (id, ...content) => helpState[id] ? m('section.help',
    { oncreate: vnode => vnode.dom.scrollIntoView({behavior: 'smooth', block: 'nearest', inline: 'nearest'}) },
    m('a[href=#]', { onclick: ev => { ev.preventDefault(); helpState[id] = false; } }, m(Icon.X)),
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


const focusElem = el => {
    if (el.tagName === 'LABEL' && el.htmlFor) el = $('#'+el.htmlFor);
    if (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA' || el.tagName === 'SELECT') el.focus();
    else el.scrollIntoView({behavior: 'smooth', block: 'nearest', inline: 'nearest'});
};

// Wrapper around a <form> with a <fieldset> element and some magic.
// Attrs:
// - onsubmit    - submit event, already has preventDefault()
// - disabled    - set 'disabled' attribute on the fieldset
// - api         - Api object, see below, also sets 'disabled' when api.loading()
//
// The .invalid-form class is set on an invalid <form> *after* the user
// attempts to submit it, to help with styling invalid inputs. The onsubmit
// event is not dispatched when the form contains a .invalid element.
window.Form = () => {
    let submitted = false, report;
    return { view: vnode => {
        const api = vnode.attrs.api;
        return m('form[novalidate]', {
            onsubmit: ev => {
                ev.preventDefault();
                report = true;
                submitted = api;
                if (ev.target.querySelector('.invalid')) return;
                const x = vnode.attrs.onsubmit;
                x && x(ev);
            },
            onupdate: v => requestAnimationFrame(() => {
                const inv = v.dom.querySelector('.invalid');
                v.dom.classList.toggle('invalid-form', submitted === api && (inv || (api && api.error)));
                if (inv && report) {
                    // If we have a FormTabs child, let that component do the reporting.
                    const t = $('#js-formtabs');
                    if (t) t.dispatchEvent(new Event('formerror'));
                    else focusElem(inv);
                }
                report = false;
            }),
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
// The tabs integrate with a parent Form component to properly report errors:
// on submission and if there's no error on the currently opened tab, it
// automatically switches to the first tab with an error and focuses the
// .invalid element.
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
    const onformerror = ev => {
        report = true;
        // Make sure we have a tab open with an error
        if (tabs.length > 1 && sel !== 'all' && !$('#formtabs_'+sel+' .invalid')) {
            for (const t of tabs) {
                if (sel === t[0]) continue;
                if ($('#formtabs_'+t[0]+' .invalid')) {
                    set(t[0]);
                    break;
                }
            }
        }
    };
    const view = () => [
        tabs.length > 1 ? m('nav', {id: 'js-formtabs', onformerror}, m('menu',
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
    const onupdate = () => requestAnimationFrame(() => {
        // Set the 'invalid-tab' class on the tabs. The form state is not known
        // during the view function, so this has to be done in an onupdate hook.
        let inv;
        if (tabs.length > 1)
            for (const t of tabs) {
                const el = $('#formtabs_'+t[0]+' .invalid');
                if (!inv && (sel === 'all' || t[0] === sel)) inv = el;
                $('#formtabst_'+t[0]).classList.toggle('invalid-tab', !!el);
            }
        if (report && inv) requestAnimationFrame(() => focusElem(inv));
        report = false;
    });
    return {view,onupdate};
};



// Text input field.
// Attrs:
// - class
// - id
// - tabindex
// - placeholder
// - type
//     'email', 'password', 'username', 'weburl'
//     'number'      -> Only digits allowed
//     'textarea'    -> <textarea>
//     otherwise     -> regular text input field
// - invalid       -> Custom HTML validation message
// - data + field  -> input value is read from and written to 'data[field]'
// - oninput       -> called after 'data[field]' has been modified, takes new value as argument
// - required / minlength / maxlength / pattern
//   HTML5 validation properties, except with a custom implementation.
//   The length is properly counted in Unicode points rather than UTF-16 digits.
// - focus         -> Bool, set input focus on create
// - rows / cols   -> For texarea
// - onfocus
//
// The HTML5 validity API has some annoying limitations and is not always
// honored, so this component simply re-implements validation and reporting of
// errors. When the field fails validation, the following happens:
// - The input element gets a .invalid class
// - The input element is followed by a 'p.invalid' element containing the message
// - If a 'label[for=$id]' exists, that label is also given the .invalid class
//
// The Form and FormTabs components detect and handle .invalid inputs.
window.Input = () => {
    const validate = a => {
        const v_ = a.data[a.field];
        const v = v_ === null ? '' : String(v_).trim();
        if (a.invalid) return a.invalid;
        if (!v.length) return a.required ? 'This field is required.' : '';
        if (a.type === 'username') { a.minlength = 2; a.maxlength = 15; }
        if (a.type === 'password') { a.minlength = 4; a.maxlength = 500; }
        if (a.minlength && [...v].length < a.minlength) return 'Please use at least '+a.minlength+' characters.';
        if (a.maxlength && [...v].length > a.maxlength) return 'Please use at most '+a.maxlength+' characters.';
        if (a.type === 'username') {
            if (/^[a-zA-Z][0-9]+$/.test(v)) return 'Username must not look like a VNDB identifier (single alphabetic character followed only by digits).';
            const dup = {};
            const chrs = v.replace(/[a-zA-Z0-9-]/g, '').split('').sort().filter(c => !dup[c] && (dup[c]=1));
            if (chrs.length === 1) return 'The character "'+chrs[0]+'" can not be used.';
            if (chrs.length) return 'The following characters can not be used: '+chrs.join(', ')+'.';
        }
        if (a.type === 'email' && !new RegExp(formVals.email).test(v)) return 'Invalid email address.';
        if (a.type === 'weburl') {
            if (!/^https?:\/\//.test(v)) return 'URL must start with http:// or https://.';
            if (/^https?:\/\/[^/]+$/.test(v)) return "URL must have a path component (hint: add a '/'?).";
            if (!new RegExp(formVals.weburl).test(v)) return 'Invalid URL.';
        }
        if (a.pattern && !new RegExp(a.pattern).test(v)) return 'Invalid format.';
        return '';
    };
    const view = vnode => {
        const a = vnode.attrs;
        const invalid = validate(a);
        const attrs = {
            id: a.id, tabindex: a.tabindex, placeholder: a.placeholder,
            rows: a.rows, cols: a.cols, onfocus: a.onfocus,
            class: (a.class||'') + (invalid ? ' invalid' : ''),
            oninput: ev => {
                let v = ev.target.value;
                if (a.type === 'number') v = Math.floor(v.replace(/[^0-9]+/g, '')||0);
                a.data[a.field] = v;
                a.oninput && a.oninput(v);
            },
            oncreate: a.focus ? v => v.dom.focus() : null,
        };
        return [
            a.type === 'textarea'
            ? m('textarea', { ...attrs }, a.data[a.field])
            : m('input', { ...attrs, value: a.data[a.field] === null ? '' : a.data[a.field],
                type: a.type === 'email' ? 'email' : a.type === 'password' ? 'password' : 'text',
            }),
            invalid ? m('p.invalid', invalid) : null,
        ];
    };
    // Searching the DOM for labels on every update isn't very optimal, but it hasn't been an issue so far.
    const onupdate = vnode => vnode.attrs.id && $$('label[for='+vnode.attrs.id+']')
        .map(el => el.classList.toggle('invalid', !!validate(vnode.attrs)));
    return {view,onupdate};
};



// BBCode (TODO: & Markdown) editor with preview button.
// Attrs:
// - data + field -> raw text is read from and written to data[field]
// - header       -> element to draw at the top-left
// - attrs        -> attrs to add to the Input
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
            api.call({content: data[field]},
                res => { preview = true; html = res.html; },
                () => { preview = true; html = '<b>'+api.error+'</b>'; },
            );
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
        m(Input, { ...vnode.attrs.attrs,
            type: 'textarea',
            class: (vnode.attrs.attrs.class||'') + (preview ? ' hidden' : ''),
            data, field, oninput: e => html = null
        }),
        preview ? m('div.preview', m.trust(html)) : null,
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
window.RDate = {
    expand: v => ({
        y: Math.floor(v / 10000),
        m: Math.floor(v / 100) % 100,
        d: v % 100,
    }),
    compact: ({y,m,d}) => y * 10000 + m * 100 + d,
    maxDay: ({y,m}) => new Date(y, m, 0).getDate(),
    normalize: ({y,m,d}) =>
        y ===    0 ? { y: 0, m: 0, d: d?1:0 } :
        y === 9999 ? { y: 9999, m: 99, d: 99 } :
        m ===    0 || m === 99 ? { y, m: 99, d: 99 } :
        { y,m, d: d === 0 || d === 99 ? 99 : Math.min(d, RDate.maxDay({y,m})) },
    months: [ 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec' ],
    fmt: ({y,m,d}) =>
        y ===    0 ? (d ? 'Today' : 'Unknown') :
        y === 9999 ? 'TBA' :
        String(y) + (m === 0 ? '' : '-'+String(m).padStart(2,0) + (d === 0 ? '' : '-'+String(d).padStart(2,0))),
    view: vnode => {
        const v = RDate.expand(vnode.attrs.value);
        const oninput = ev => vnode.attrs.oninput && vnode.attrs.oninput(Math.floor(ev.target.options[ev.target.selectedIndex].value));
        const o = (e,l) => {
            const value = RDate.compact(RDate.normalize({...v, ...e}));
            return m('option', { value, selected: value === vnode.attrs.value }, l);
        };
        return [
            m('select', {oninput, id: vnode.attrs.id},
                vnode.attrs.today ? o({y:1}, 'Today') : null,
                vnode.attrs.unknown ? o({y:0}, 'Unknown') : null,
                o({y:9999}, 'TBA'),
                range(new Date().getFullYear()+5, 1980, -1).map(y => o({y},y)),
            ),
            v.y > 0 && v.y < 9999 ? m('select', {oninput},
                o({m:99}, '- month -'),
                range(1, 12).map(m => o({m}, m + ' (' + RDate.months[m-1] + ')')),
            ) : null,
            v.m > 0 && v.m < 99 ? m('select', {oninput},
                o({d:99}, '- day -'),
                range(1, RDate.maxDay(v)).map(d => o({d},d)),
            ) : null,
        ];
    },
};
