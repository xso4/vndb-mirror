// Because I'm lazy.
window.$ = sel => document.querySelector(sel);
window.$$ = sel => Array.from(document.querySelectorAll(sel));


// Load global page-wide variables from <script id="pagevars">...</script> and
// store them into window.pageVars.
window.pageVars = (e => e ? JSON.parse(e.innerHTML) : {})($('#pagevars'));

window.urlStatic = $('link[rel=stylesheet]').href.replace(/^(https?:\/\/[^/]+)\/.*$/, '$1');


// Like VNDB::Func::imgurl(), but without the fmt argument because we don't need that for now.
window.imgurl = (id, dir) => urlStatic + '/' +
    id.replace(/[0-9]+/, '') + (dir ? '.' + dir : '') + '/' +
    id.replace(/^.*?([0-9]?[0-9])$/, '$1').padStart(2, '0') + '/' +
    id.replace(/^[a-z]+/, '') + '.jpg';


// Widget initialization, see README.md
window.widget = (name, fun) =>
    ((pageVars.widget || {})[name] || []).forEach(([id, data]) => {
        const e = $('#widget'+id);
        // m.mount() instantly wipes the contents of e, let's make a copy in case the widget needs something from it.
        const oldContents = Array.from(e.childNodes);
        m.mount(e, {view: ()=>m(fun, {data, oldContents})})
    });


// Return an array for the given (inclusive) range.
window.range = (start, end, skip=1) => {
    let a = [];
    for (; skip > 0 ? start <= end : end <= start; start += skip) a.push(start);
    return a;
};


// Compare two JS values, for the purpose of sorting.
// Should only be used to compare values of identical types (or null).
// Supports arrays, numbers, strings, bools and null.
// Recurses into arrays.
// Null always sorts last.
const anyCmp = (a, b) => {
    if (a === b) return 0;
    if (a === null && b !== null) return 1;
    if (b === null && a !== null) return -1;
    if (typeof a === typeof b && (typeof a === 'number' || typeof a === 'string' || typeof a === 'boolean'))
        return a < b ? -1 : 1;
    if (Array.isArray(a) && Array.isArray(b)) {
        let r = 0;
        for (let i=0; !r && i<a.length && i<b.length; i++)
            r = anyCmp(a[i], b[i]);
        return r || anyCmp(a.length, b.length);
    }
    throw new Error('anyCmp(' + a + ', ' + b + ')');
};


// Return a sorted array according to anyCmp().
// The optional 'f' argument can be used to transform elements for comparison.
Array.prototype.anySort = function(f=x=>x) { return [...this].sort((a,b) => anyCmp(f(a),f(b))) };

// Check whether an array has duplicates according to anyCmp().
// Also accepts an optional 'f' argument.
Array.prototype.anyDup = function(f=x=>x) {
    const lst = this.anySort(f);
    for (let i=1; i<lst.length; i++)
        if (!anyCmp(f(lst[i-1]), f(lst[i]))) return true;
    return false;
};

Array.prototype.intersperse = function(sep) { return this.reduce((a,v)=>[...a,v,sep],[]).slice(0,-1) };
