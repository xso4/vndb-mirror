widget('Subscribe', vnode => {
    let {id, subnum, subreview, subapply, noti} = vnode.attrs.data;
    let open = false;
    let saveApi = new Api('Subscribe');
    const t = id.substring(0,1);

    const toggle = (ev) => {
        if (open && vnode.dom.nextSibling.contains(ev.target)) return;
        open = !open;
        // Defer the listener, otherwise this current event will trigger it.
        if (open) requestAnimationFrame(() => document.addEventListener('click', toggle));
        else document.removeEventListener('click', toggle);
        m.redraw();
    };

    const msg = txt => m('p', txt, ' These can be disabled globally in your ', m('a[href=/u/notifies]', 'notification settings'), '.');

    const save = f => () => {
        f();
        saveApi.call({ id, subnum, subreview, subapply });
    };

    const view = () => [
        m('a[href=#]', {
            onclick: (ev) => { ev.preventDefault(); toggle(ev) },
            class: (noti > 0 && subnum !== false) || subnum === true || subreview || subapply ? 'active' : 'inactive',
        }, '🔔'),
        !open ? null : m('div', m('div',
            m('h4',
                saveApi.loading() ? m('span.spinner[style=float:right]') : null,
                'Manage Notifications'
            ),

            t == 't' && noti == 1 ? msg("You receive notifications for replies because you have posted in this thread.") :
            t == 't' && noti == 2 ? msg("You receive notifications for replies because this thread is linked to your personal board.") :
            t == 't' && noti == 3 ? msg("You receive notifications for replies because you have posted in this thread and it is linked to your personal board.") :
            t == 'w' && noti == 1 ? msg("You receive notifications for new comments because you have commented on this review.") :
            t == 'w' && noti == 2 ? msg("You receive notifications for new comments because this is your review.") :
            t == 'w' && noti == 3 ? msg("You receive notifications for new comments because this is your review and you have commented it.") :
                        noti == 1 ? msg("You receive edit notifications for this entry because you have contributed to it.") :
                                    null,

            noti == 0 ? null : m('label',
                m('input[type=checkbox][tabindex=10]', { checked: subnum === false, oninput: save(() => subnum = subnum === false ? null : false) }),
                t == 't' ? ' Disable notifications only for this thread.' :
                t == 'w' ? ' Disable notifications only for this review.'
                         : ' Disable edit notifications only for this entry.'
            ),

            m('label',
                m('input[type=checkbox][tabindex=10]', { checked: subnum === true, oninput: save(() => subnum = subnum === true ? null : true) }),
                t == 't' ? ' Enable notifications for new replies' :
                t == 'w' ? ' Enable notifications for new comments'
                         : ' Enable notifications for new edits',
                noti == 0 ? '.' : ', regardless of the global setting.'
            ),

            t == 'v' ? m('label',
                m('input[type=checkbox][tabindex=10]', { checked: subreview, oninput: save(() => subreview = !subreview) }),
                ' Enable notifications for new reviews.'
            ) : null,

            t == 'i' ? m('label',
                m('input[type=checkbox][tabindex=10]', { checked: subapply, oninput: save(() => subapply = !subapply) }),
                ' Enable notifications when this trait is applied or removed from a character.'
            ) : null,

            saveApi.error ? m('b', saveApi.error) : null,
        )),
    ];

    return {view};
})
