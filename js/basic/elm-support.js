if(!pageVars.elm) return;

// See Lib/Ffi.elm
window.elmFfi_innerHtml = (wrap) => s => ({$: 'a2', n: 'innerHTML', o: wrap(s)});
window.elmFfi_elemCall = (wrap,call) => call;
window.elmFfi_fmtFloat = () => val => prec => val.toLocaleString('en-US', { minimumFractionDigits: prec, maximumFractionDigits: prec });

const url_static = document.querySelector('link[rel=stylesheet]').href.replace(/^(https?:\/\/[^/]+)\/.*$/, '$1');
window.elmFfi_urlStatic = () => url_static;



// Add the X-CSRF-Token header to every POST request. Based on:
// https://stackoverflow.com/questions/24196140/adding-x-csrf-token-header-globally-to-all-instances-of-xmlhttprequest/24196317#24196317
// TODO: This can be removed, we can just rely on CORS.
(() => {
    const open = XMLHttpRequest.prototype.open,
        token = document.querySelector('meta[name=csrf-token]').content;

    XMLHttpRequest.prototype.open = function(method, url) {
        var ret = open.apply(this, arguments);
        this.dataUrl = url;
        if(method.toLowerCase() == 'post' && /^\//.test(url))
            this.setRequestHeader('X-CSRF-Token', token);
        return ret;
    };
})();


var preload_urls = {};

const ports = Object.entries({
    // ImageFlagging
    preload: () => url => {
        if(Object.keys(preload_urls).length > 100)
            preload_urls = {};
        if(!preload_urls[url]) {
            preload_urls[url] = new Image();
            preload_urls[url].src = url;
        }
    },

    // UList.LabelEdit
    ulistLabelChanged: flags => pub => {
        const l = document.getElementById('ulist_public_'+flags.vid);
        l.setAttribute('data-publabel', pub?1:'');
        l.classList.toggle('invisible', !((l.getAttribute('data-voted') && !pageVars.voteprivate) || l.getAttribute('data-publabel')))
    },

    // UList.Opt
    ulistVNDeleted: flags => b => {
        const e = document.getElementById('ulist_tr_'+flags.vid);
        e.parentNode.removeChild(e.nextElementSibling);
        e.parentNode.removeChild(e);

        // Have to restripe after deletion :(
        const rows = document.querySelectorAll('.ulist > table > tbody > tr');
        for(var i=0; i<rows.length; i++)
            rows[i].classList.toggle('odd', Math.floor(i/2) % 2 == 0);
    },

    ulistNotesChanged: flags => n => {
        document.getElementById('ulist_notes_'+flags.vid).innerText = n;
    },

    ulistRelChanged: flags => rels => {
        const e = document.getElementById('ulist_relsum_'+flags.vid);
        e.classList.toggle('todo', rels[0] != rels[1]);
        e.classList.toggle('done', rels[1] > 0 && rels[0] == rels[1]);
        e.innerText = rels[0] + '/' + rels[1];
    },

    // UList.VoteEdit
    ulistVoteChanged: flags => voted => {
        const l = document.getElementById('ulist_public_'+flags.vid);
        l.setAttribute('data-voted', voted?1:'');
        l.classList.toggle('invisible', !((l.getAttribute('data-voted') && !pageVars.voteprivate) || l.getAttribute('data-publabel')))
    },

    // User.Edit
    skinChange: () => skin => {
        const sheet = document.querySelector('link[rel=stylesheet]');
        sheet.href = sheet.href.replace(/[^\/]+\.css/, skin+'.css');
    },

    selectText: () => id => setTimeout(()=>document.getElementById(id).select(), 50),

    // VNEdit
    ivRefresh: () => () => setTimeout(ivInit, 10),
});


// Some modules need a wrapper around their init() method.
const wrap = {
    ImageFlagging: (init, opt) => {
        opt.flags.pWidth  = window.innerWidth  || document.documentElement.clientWidth  || document.body.clientWidth;
        opt.flags.pHeight = window.innerHeight || document.documentElement.clientHeight || document.body.clientHeight;
        init(opt);
    },

    'UList.LabelEdit': (init, opt) => {
        opt.flags.uid = pageVars.uid;
        opt.flags.labels = pageVars.labels;
        init(opt);
    },

    'UList.ManageLabels': (init, opt) => {
        opt.flags = { uid: pageVars.uid, labels: pageVars.labels };
        init(opt);
    },

    // This module is typically hidden, lazily load it only when the module is visible to speed up page load time.
    'UList.Opt': (init, opt) => {
        const e = document.getElementById('collapse_vid'+opt.flags.vid);
        if(e.checked) init(opt);
        else e.addEventListener('click', () => init(opt), { once: true });
    },

    'User.Edit': (init, opt) => {
        const tz = window.Intl ? Intl.DateTimeFormat().resolvedOptions().timeZone : '';
        if(tz) opt.flags.browsertimezone = tz;
        init(opt);
    }
}


pageVars.elm.forEach((e,i) => {
    const mod = e[0].split('.').reduce((p, c) => p[c], window.Elm);
    const node = document.getElementById('elm'+i);
    var opt = { node };
    if (e.length > 1) opt.flags = e[1];
    const init = o => {
        var app = mod.init(o);
        ports.forEach(([port, callback]) => {
            if (app.ports[port]) app.ports[port].subscribe(callback(opt.flags));
        });
    };
    wrap[e[0]] ? wrap[e[0]](init, opt) : init(opt)
});
