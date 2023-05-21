$$('#searchtabs a').forEach(l => l.onclick = ev => {
    const str = $('#q').value;
    const el = ev.target;
    if(str.length > 0) {
        if(el.href.indexOf('/g') >= 0 || el.href.indexOf('/i') >= 0)
            el.href += '/list';
        el.href += '?q=' + encodeURIComponent(str);
    }
});
