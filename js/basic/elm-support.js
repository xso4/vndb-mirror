if(!pageVars.elm) return;

// See Lib/Ffi.elm
window.elmFfi_innerHtml = (wrap) => s => ({$: 'a2', n: 'innerHTML', o: wrap(s)});
window.elmFfi_elemCall = (wrap,call) => call;
window.elmFfi_fmtFloat = () => val => prec => val.toLocaleString('en-US', { minimumFractionDigits: prec, maximumFractionDigits: prec });
window.elmFfi_urlStatic = () => urlStatic;



var preload_urls = {};

const ports = Object.entries({
    // ImageFlagging
    preload: () => url => imgPreload(url),

    // UList.LabelEdit
    ulistLabelChanged: flags => pub => {
        const l = $('#ulist_public_'+flags.vid);
        if (l) {
            l.setAttribute('data-publabel', pub?1:'');
            l.classList.toggle('invisible', !((l.getAttribute('data-voted') && !pageVars.voteprivate) || l.getAttribute('data-publabel')))
        }
    },

    // UList.Opt
    ulistVNDeleted: flags => b => {
        const e = $('#ulist_tr_'+flags.vid);
        e.parentNode.removeChild(e.nextElementSibling);
        e.parentNode.removeChild(e);

        // Have to restripe after deletion :(
        const rows = $$('.ulist > table > tbody > tr');
        for(var i=0; i<rows.length; i++)
            rows[i].classList.toggle('odd', Math.floor(i/2) % 2 == 0);
    },

    ulistNotesChanged: flags => n => {
        $('#ulist_notes_'+flags.vid).innerText = n;
    },

    ulistRelChanged: flags => rels => {
        const e = $('#ulist_relsum_'+flags.vid);
        e.classList.toggle('todo', rels[0] != rels[1]);
        e.classList.toggle('done', rels[1] > 0 && rels[0] == rels[1]);
        e.innerText = rels[0] + '/' + rels[1];
    },

    // UList.VoteEdit
    ulistVoteChanged: flags => voted => {
        const l = $('#ulist_public_'+flags.vid);
        if (l) {
            l.setAttribute('data-voted', voted?1:'');
            l.classList.toggle('invisible', !((l.getAttribute('data-voted') && !pageVars.voteprivate) || l.getAttribute('data-publabel')))
        }
    },
});


// Some modules need a wrapper around their init() method.
const wrap = {
    ImageFlagging: (init, opt) => {
        opt.flags.pWidth  = window.innerWidth  || document.documentElement.clientWidth  || document.body.clientWidth;
        opt.flags.pHeight = window.innerHeight || document.documentElement.clientHeight || document.body.clientHeight;
        init(opt);
    },

    'UList.LabelEdit': (init, opt) => {
        opt.flags.labels = pageVars.labels.map(([id,label,p]) => ({id,label,'private':p}));
        init(opt);
    },

    // This module is typically hidden, lazily load it only when the module is visible to speed up page load time.
    'UList.Opt': (init, opt) => {
        const e = $('#collapse_vid'+opt.flags.vid);
        if(e.checked) init(opt);
        else e.addEventListener('click', () => init(opt), { once: true });
    },
}


pageVars.elm.forEach((e,i) => {
    const mod = e[0].split('.').reduce((p, c) => p[c], window.Elm);
    const node = $('#elm'+i);
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
