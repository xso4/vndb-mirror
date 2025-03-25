if(!pageVars.elm) return;

// See Lib/Ffi.elm
window.elmFfi_innerHtml = (wrap) => s => ({$: 'a2', n: 'innerHTML', o: wrap(s)});
window.elmFfi_elemCall = (wrap,call) => call;
window.elmFfi_fmtFloat = () => val => prec => val.toLocaleString('en-US', { minimumFractionDigits: prec, maximumFractionDigits: prec });


// Some modules need a wrapper around their init() method.
const wrap = {
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
    wrap[e[0]] ? wrap[e[0]](mod.init, opt) : mod.init(opt)
});
