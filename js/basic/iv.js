/* Simple image viewer widget. Usage from HTML:
 *
 *   <a href="full_image.jpg" data-iv="{width}x{height}:{category}:{flagging}">..</a>
 *
 * Clicking on the above link will cause the image viewer to open
 * full_image.jpg. The {category} part can be empty or absent. If it is not
 * empty, next/previous links will show up to point to the other images within
 * the same category. The {flagging} part can also be empty or absent,
 * otherwise it should be a string in the format "svn", where s and v indicate
 * the sexual/violence scores (0-2) and n the number of votes.
 *
 * Alternative usage from Mithril.js:
 *
 *   m(IVLink, { img: $ImageResultFromPerl, cat: $Category }, ..contents)
 */

let globalObj;
let activeUrl;
let activeFields;
let loading;

const setupObj = () => {
    if (globalObj) return;
    globalObj = document.createElement('div');
    document.body.appendChild(globalObj);
    m.mount(globalObj, { view: v => render() });
};


const getFields = o => o.getAttribute('data-iv').split(':');


// Find the next (dir=1) or previous (dir=-1) non-hidden link object for the category.
const findnav = dir => {
    if (!activeUrl || !activeFields[1]) return null;
    let last;
    for (let o of $$('a[data-iv]')) {
        if (activeFields[1] !== getFields(o)[1]) continue;
        if (!(o.offsetWidth > 0 && o.offsetHeight > 0)) continue;
        if (globalObj.contains(o)) continue;
        if (dir === -1) {
            if (o.href === activeUrl) return last;
            last = o;
        } else {
            if (last) return o;
            if (o.href === activeUrl) last = true;
        }
    }
    return null;
};


const resize = () => m.redraw();

const keydown = ev => {
    if (ev.key === 'ArrowLeft') {
        const p = findnav(-1);
        if (p) p.click();
    } else if (ev.key === 'ArrowRight') {
        const n = findnav(1);
        if (n) n.click();
    } else if (ev.key === 'Escape' || ev.key === 'Esc')
        close();
};

const closeOutside = ev => {
    if (!globalObj.contains(ev.target) && !ev.target.closest('a[data-iv]')) close();
};

const close = () => {
    activeUrl = activeFields = null;
    document.removeEventListener('keydown', keydown);
    document.removeEventListener('click', closeOutside);
    removeEventListener('resize', resize);
    m.redraw();
};


const open = ev => {
    ev.preventDefault();
    setupObj();
    let t = ev.target.closest('a[data-iv]');
    if (!t || activeUrl === t.href) return close();
    activeUrl = t.href;
    activeFields = getFields(t);
    loading = true;
    document.addEventListener('keydown', keydown);
    document.addEventListener('click', closeOutside);
    addEventListener('resize', resize);
    m.redraw();
};

const render = () => {
    if (!activeUrl) return null;

    let [w,h] = activeFields[0].split('x').map(v => Math.floor(v));
    const ww = window.innerWidth;
    const wh = window.innerHeight;
    if(w+100 > ww || h+70 > wh) {
        if(w/h > ww/wh) { // width++
            h *= (ww-100)/w;
            w = ww-100;
        } else { // height++
            w *= (wh-70)/h;
            h = wh-70;
        }
    }
    let dw = Math.max(w, 200);
    let dh = h+20;

    let nprop = o => o ? { href: o.href, 'data-iv': o.getAttribute('data-iv'), onclick: open } : { class: 'invisible' };
    let prev = nprop(findnav(-1));
    let next = nprop(findnav(1));

    const flag = activeFields[2] ? activeFields[2].match(/^([0-2])([0-2])([0-9]+)$/) : null;
    const imgid = activeUrl.match(/\/([a-z]{2})\/[0-9]{2}\/([0-9]+)\./);

    return m('div.ivview', { style: { width: dw+'px', height: dh+'px', left: ((ww-dw)/2 - 10)+'px', top: ((wh-dh)/2 - 20)+'px' } },
        m('div.spinner', { class: loading ? null : 'hidden' }),
        m('div',
            m('a.left-pane', { key: 'p', ...prev }),
            m('a.right-pane', { key: 'n', ...next }),
            m('img', {
                key: activeUrl, /* Don't reuse the <img> object for different URLs */
                onclick: close,
                onload: () => { loading = false; next.href && imgPreload(next.href) },
                src: activeUrl,
                style: { width: w+'px', height: h+'px' },
            }),
        ),
        m('div',
            m('a[target=_blank]', { class: activeFields[0] === w+'x'+h ? 'invisible' : null, href: activeUrl }, activeFields[0]),
            m('a', prev, '« previous'),
            m('a', next, 'next »'),
            m('a', ...(flag && imgid ? [
                { href: '/'+imgid[1]+imgid[2] },
                 flag[3] == 0 ? 'Not flagged' :
                (flag[1] == 0 ? 'Safe' : flag[1] == 1 ? 'Suggestive' : 'Explicit') + ' / ' +
                (flag[2] == 0 ? 'Tame' : flag[2] == 1 ? 'Violent'    : 'Brutal'  ) + ' (' + flag[3] + ')'
            ] : [{ class: 'invisible' }, ''])),
        )
    );
};

window.IVLink = { view: vnode => m('a[target=_blank]', {
    href: imgurl(vnode.attrs.img.id),
    'data-iv': vnode.attrs.img.width+'x'+vnode.attrs.img.height+':'+(vnode.attrs.cat||'')+':'+vnode.attrs.img.sexual+vnode.attrs.img.violence+vnode.attrs.img.votecount,
    onclick: open,
}, vnode.children) };

$$('a[data-iv]').forEach(o => o.addEventListener('click', open));
