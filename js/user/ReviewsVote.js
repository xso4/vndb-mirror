widget('ReviewsVote', vnode => {
    const data = vnode.attrs.data;
    const api = new Api('ReviewsVote');
    const but = (v,label) =>
        m('a[href=#].votebut', {
            class: data.my === v ? 'myvote' : null,
            onclick: ev => { ev.preventDefault(); data.my = data.my === v ? null : v; api.call(data) },
        }, label);
    const view = () => [
        api.loading() ? m('span.spinner') :
        api.error ? m('b', api.error) : 'Was this review helpful?',
        ' ',
        but(true, 'yes'),
        ' / ',
        but(false, 'no'),
        data.mod ? [
            ' / ',
            m('label',
                m('input[type=checkbox]', { checked: data.overrule, oninput: ev => { data.overrule = ev.target.checked; data.my !== null && api.call(data); } }),
                ' O'
            ),
        ] : null,
    ];
    return {view};
});
