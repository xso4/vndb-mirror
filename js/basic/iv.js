/* Simple image viewer widget. Usage:
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
 * ivInit() should be called when links with "data-iv" attributes are
 * dynamically added or removed from the DOM.
 */

// Cache of image categories and the list of associated link objects. Used to
// quickly generate the next/prev links.
var cats;

// DOM elements, lazily initialized in create_div()
var ivparent = null;
var ivimg;
var ivfull;
var ivnext;
var ivprev;
var ivhovernext;
var ivhoverprev;
var ivload;
var ivflag;

var imgw;
var imgh;

function create_div() {
    if(ivparent)
        return;
    ivparent = document.createElement('div');
    ivparent.className = 'ivview';
    ivparent.style.display = 'none';
    ivparent.onclick = function(ev) { ev.stopPropagation(); return true };

    ivload = document.createElement('div');
    ivload.className = 'spinner';
    ivload.style.display = 'none';
    ivparent.appendChild(ivload);

    ivimg = document.createElement('div');
    ivparent.appendChild(ivimg);

    var ivlinks = document.createElement('div');
    ivparent.appendChild(ivlinks);

    ivfull = document.createElement('a');
    ivlinks.appendChild(ivfull);

    ivprev = document.createElement('a');
    ivprev.onclick = show;
    ivprev.textContent = '« previous';
    ivlinks.appendChild(ivprev);

    ivnext = document.createElement('a');
    ivnext.onclick = show;
    ivnext.textContent = 'next »';
    ivlinks.appendChild(ivnext);

    ivhoverprev = document.createElement('a');
    ivhoverprev.onclick = show;
    ivhoverprev.className = "left-pane";
    ivimg.appendChild(ivhoverprev);

    ivhovernext = document.createElement('a');
    ivhovernext.onclick = show;
    ivhovernext.className = "right-pane";
    ivimg.appendChild(ivhovernext);

    ivflag = document.createElement('a');
    ivlinks.appendChild(ivflag);

    document.querySelector('body').appendChild(ivparent);
}


// Find the next (dir=1) or previous (dir=-1) non-hidden link object for the category.
function findnav(cat, i, dir) {
    for(var j=i+dir; j>=0 && j<cats[cat].length; j+=dir)
        if(cats[cat][j].offsetWidth > 0 && cats[cat][j].offsetHeight > 0)
            return cats[cat][j];
    return 0
}


// fix properties of the prev/next links
function fixnav(lnk, cat, i, dir) {
    var a = cat ? findnav(cat, i, dir) : 0;
    lnk.style.visibility = a ? 'visible' : 'hidden';
    lnk.href             = a ? a.href    : '#';
    lnk.iv_i             = a ? a.iv_i    : 0;
    lnk.setAttribute('data-iv', a ? a.getAttribute('data-iv') : '');
}


function keydown(e) {
    if(e.key == 'ArrowLeft' && ivprev.style.visibility == 'visible')
        ivprev.click();
    else if(e.key == 'ArrowRight' && ivnext.style.visibility == 'visible')
        ivnext.click();
    else if(e.key == 'Escape' || e.key == 'Esc')
        ivClose();
}


function resize() {
    var w = imgw;
    var h = imgh;
    var ww = typeof(window.innerWidth)  == 'number' ? window.innerWidth  : document.documentElement.clientWidth;
    var wh = typeof(window.innerHeight) == 'number' ? window.innerHeight : document.documentElement.clientHeight;
    if(w+100 > ww || imgh+70 > wh) {
        ivfull.textContent = w+'x'+h;
        ivfull.style.visibility = 'visible';
        if(w/h > ww/wh) { // width++
            h *= (ww-100)/w;
            w = ww-100;
        } else { // height++
            w *= (wh-70)/h;
            h = wh-70;
        }
    } else
        ivfull.style.visibility = 'hidden';
    var dw = w;
    var dh = h+20;
    dw = dw < 200 ? 200 : dw;

    ivparent.style.width = dw+'px';
    ivparent.style.height = dh+'px';
    ivparent.style.left = ((ww - dw) / 2 - 10)+'px';
    ivparent.style.top = ((wh - dh) / 2 - 20)+'px';
    var img = ivimg.querySelector('img');
    img.style.width = w+'px';
    img.style.height = h+'px';
}


function show(ev) {
    var u = this.href;
    var opt = this.getAttribute('data-iv').split(':'); // 0:reso, 1:category, 2:flagging
    var idx = this.iv_i;
    imgw = Math.floor(opt[0].split('x')[0]);
    imgh = Math.floor(opt[0].split('x')[1]);

    create_div();
    var imgs = ivimg.getElementsByTagName("img")
    if (imgs.length !== 0)
        ivimg.getElementsByTagName("img")[0].remove()

    var img = document.createElement('img');
    img.src = u;
    ivfull.href = u;
    img.onclick = ivClose;
    img.onload = function() { ivload.style.display = 'none' };
    ivimg.appendChild(img);

    var flag = opt[2] ? opt[2].match(/^([0-2])([0-2])([0-9]+)$/) : null;
    var imgid = u.match(/\/([a-z]{2})\/[0-9]{2}\/([0-9]+)\./);
    if(flag && imgid) {
        ivflag.href = '/img/'+imgid[1]+imgid[2];
        ivflag.textContent = flag[3] == 0 ? 'Not flagged' :
            (flag[1] == 0 ? 'Safe' : flag[1] == 1 ? 'Suggestive' : 'Explicit') + ' / ' +
            (flag[2] == 0 ? 'Tame' : flag[2] == 1 ? 'Violent'    : 'Brutal'  ) + ' (' + flag[3] + ')';
        ivflag.style.visibility = 'visible';
    } else
        ivflag.style.visibility = 'hidden';

    ivparent.style.display = 'block';
    ivload.style.display = 'block';
    fixnav(ivprev, opt[1], idx, -1);
    fixnav(ivnext, opt[1], idx, 1);
    fixnav(ivhoverprev, opt[1], idx, -1);
    fixnav(ivhovernext, opt[1], idx, 1);
    resize();

    document.addEventListener('click', ivClose);
    document.addEventListener('keydown', keydown);
    window.addEventListener('resize', resize);
    ev.preventDefault();
}


window.ivClose = function(ev) {
    var targetlink = ev ? ev.target : null;
    while(targetlink && targetlink.nodeName.toLowerCase() != 'a')
        targetlink = targetlink.parentNode;
    if(targetlink && targetlink.getAttribute('data-iv'))
        return false;
    document.removeEventListener('click', ivClose);
    document.removeEventListener('keydown', keydown);
    window.removeEventListener('resize', resize);
    ivparent.style.display = 'none';
    var imgs = ivimg.getElementsByTagName("img")
    if (imgs.length !== 0)
        ivimg.getElementsByTagName("img")[0].remove()
    return false;
};


window.ivInit = function() {
    cats = {};
    document.querySelectorAll('a[data-iv]').forEach(function(o) {
        if(o == ivnext || o == ivprev || o == ivfull || o == ivhoverprev || o == ivhovernext)
            return;
        o.addEventListener('click', show);
        var cat = o.getAttribute('data-iv').split(':')[1];
        if(cat) {
            if(!cats[cat])
                cats[cat] = [];
            o.iv_i = cats[cat].length;
            cats[cat].push(o);
        }
    });
};
ivInit();
