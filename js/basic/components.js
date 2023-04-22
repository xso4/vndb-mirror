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
