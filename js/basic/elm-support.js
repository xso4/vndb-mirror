if(!pageVars.elm) return;

// See Lib/Ffi.elm
window.elmFfi_innerHtml = (wrap) => s => ({$: 'a2', n: 'innerHTML', o: wrap(s)});
window.elmFfi_elemCall = (wrap,call) => call;
window.elmFfi_fmtFloat = () => val => prec => val.toLocaleString('en-US', { minimumFractionDigits: prec, maximumFractionDigits: prec });
window.elmFfi_urlStatic = () => urlStatic;


const ports = Object.entries({
    // ImageFlagging
    preload: () => url => imgPreload(url),
});


// Some modules need a wrapper around their init() method.
const wrap = {
    ImageFlagging: (init, opt) => {
        opt.flags.pWidth  = window.innerWidth  || document.documentElement.clientWidth  || document.body.clientWidth;
        opt.flags.pHeight = window.innerHeight || document.documentElement.clientHeight || document.body.clientHeight;
        init(opt);
    },

    'AdvSearch.Main': (init, opt) => {
        opt.flags.labels = pageVars.labels ? pageVars.labels.map(([id,label,p]) => ({id,label})) : [];
        init(opt);
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
