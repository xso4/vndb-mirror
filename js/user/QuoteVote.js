widget('QuoteVote', vnode => {
    let [id,score,vote,hidden,edit] = vnode.attrs.data;
    const api = new Api('QuoteVote');
    const set = v => () => {
        if (vote) score -= vote;
        vote = vote === v ? null : v;
        if (vote) score += v;
        api.call({id: id, vote: vote});
        return false;
    };
    return {view: () => [
        m('a[title=Edit]', { href: '/editquote/'+id, class: edit ? '' : 'invisible' }, m(Icon.Pencil)),
        ' ',
        m('a[title=Upvote][href=#]', { class: vote === 1 ? 'active' : null, onclick: set(1) }, m(Icon.ArrowBigUp)),
        m(hidden ? 'small[title=Deleted]' : 'span', score),
        m('a[title=Downvote][href=#]', { class: vote === -1 ? 'active' : null, onclick: set(-1) }, m(Icon.ArrowBigDown)),
    ]};
});
