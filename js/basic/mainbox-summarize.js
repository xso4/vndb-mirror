// Adds a "more"/"less" link to the bottom of a mainbox depending on the
// height of its contents.
//
// Usage:
//
//   <article data-mainbox-summarize="200"> .. </div>

const set = (d, h) => {
    let expanded = true;
    const a = document.createElement('a');
    a.href = '#';
    a.onclick = ev => {
        ev && ev.preventDefault();
        expanded = !expanded;
        d.style.maxHeight = expanded ? null : h+'px';
        d.style.overflowY = expanded ? null : 'hidden';
        a.textContent = expanded ? '⇑ less ⇑' : '⇓ more ⇓';
    };

    const t = document.createElement('div');
    t.className = 'summarize_more';
    t.appendChild(a);
    d.parentNode.insertBefore(t, d.nextSibling);
    a.click();
};

$$('article[data-mainbox-summarize]').forEach(d => {
    const h = Math.floor(d.getAttribute('data-mainbox-summarize'));
    if(d.offsetHeight > h+100)
        set(d, h)
});
