$$('.vnimagevote').forEach(el => {
    const api = new Api('VNImageVote');
    const d = el.dataset.voting.split(',');
    const data = {
        vid: d[0],
        img: d[1],
        vote: d[2] === '1',
    };
    const upd = () => {
        el.classList.toggle('voted', data.vote);
        el.innerHTML =
            api.loading() ? '<span class="spinner"></span>' :
            api.error ? '<b>error</b>' :
            data.vote ? '★' : '☆';
    };
    el.onclick = () => upd(api.call(
        {...data, vote: !data.vote},
        () => upd(data.vote = !data.vote),
        upd,
    ));
    el.title = 'Vote to make this the main cover image for this visual novel.';
    upd();
});
