// Dialog/Dropdown Select/Search.
// i.e. a selection thingy component.

// global dialog element, initialized lazily, reused by different instances as
// there can only be one dialog open at a time.
let globalObj;
// Points to the DS object that is currently active (or null).
let activeInstance;

const setupObj = () => {
    if (globalObj) return;
    globalObj = document.createElement('div');
    document.body.appendChild(globalObj);
    m.mount(globalObj, {
        view: v => activeInstance ? activeInstance.view(v) : [],
    });
};

const keydown = ev => {
    if (activeInstance) activeInstance.keydown(ev);
    m.redraw();
};

const position = () => {
    const obj = $('#ds');
    if(!obj) return;

    const margin = 5;

    const inst = activeInstance;
    const opener = inst.opener.getBoundingClientRect(); // BUG: this doesn't work if ev.target is inside a positioned element
    const header = obj.children[0].getBoundingClientRect().height;
    const cols = Math.max(1, Math.min(Math.floor((window.innerWidth - margin*2) / inst.width), inst.maxCols||1));
    const width = Math.min(window.innerWidth - margin*2, inst.width*cols);
    const left = Math.max(margin,
        opener.x + opener.width - width,
        Math.min(window.innerWidth - width - 2*margin, opener.x),
    );

    const top = opener.y + opener.height;
    const height = Math.max(header + 20, Math.min(window.innerHeight - margin*2, window.innerHeight - top - margin));

    obj.style.top  = (top  + window.scrollY) + 'px';
    obj.style.left = (left + window.scrollX) + 'px';
    obj.style.width = width + 'px';
    const d = obj.children[1];
    if (d && d.tagName == 'DIV') {
        d.style.maxHeight = (height - header) + 'px';
        d.children[0].style.columnCount = cols;
    }

    const e = obj.querySelector('li.active');
    if (e) d.scrollTop = Math.max(Math.min(e.offsetTop, d.scrollTop), e.offsetTop + e.offsetHeight - d.offsetHeight);
};

const close = ev => {
    if (!activeInstance) return;
    if (ev && (globalObj.contains(ev.target) || activeInstance.opener.contains(ev.target))) return;
    if (!ev) activeInstance.opener.focus();
    if (activeInstance) activeInstance.abort();
    activeInstance = null;
    document.removeEventListener('click', close);
    document.removeEventListener('keydown', keydown);
    document.removeEventListener('scroll', position);
    removeEventListener('resize', position);
    m.redraw();
};


// Constructor options (all optional):
// - width
// - maxCols
// - placeholder
// - more
//     Adds a "type for more options" as last option if search is empty.
// - nosearch
//     Disable search input
// - keep
//     Keep box active but cleared on item select.
// - onselect(obj,checked)
//     Called when an item has been selected. 'checked' is always true for
//     single-selection dropdowns.
// - props(obj)
//     Called on each displayed object, should return null if the object should
//     be filtered out or an object otherwise. The object supports the
//     following options:
//     - selectable: boolean, default true
//     - append: vdom node to append to the item
// - checked(obj)
//     Set for multiselection dropdowns.
//     Called on each displayed object, should return whether this item is
//     checked or not.
// - checkall()
//     Adds a "check all" button.
// - uncheckall()
//     Adds an "uncheck all" button.
//
// To use a DS object as a selection dropdown:
//   m(DS.Button, {ds}, ...)
// Or to autocomplete an input field:
//   m(DS.Input, {ds, ...})
// Most of the above constructor options are ignored for autocompletion.
class DS {
    constructor(source, opts) {
        this.width = 400;
        this.input = '';
        this.source = source;
        if (source.opts) Object.assign(this, source.opts);
        if (opts) Object.assign(this, opts);
        this.open = this.open.bind(this);
        this.list = [];
    }

    open(opener, autocomplete) {
        if (activeInstance === this) return close();
        setupObj();
        activeInstance = this;
        this.autocomplete = autocomplete;
        this.opener = opener;
        this.focus = v => { this.focus = null; v.dom.focus() };
        document.addEventListener('click', close);
        document.addEventListener('keydown', keydown);
        document.addEventListener('scroll', position);
        addEventListener('resize', position);
        this.setInput(this.input);
    }

    select() {
        const obj = this.list.find(e => e.id === this.selId);
        if (!obj) return;
        if (this.checked || this.keep) this.focus = v => { this.focus = null; v.dom.focus() };
        if (this.autocomplete) this.autocomplete(this.source.stringify ? this.source.stringify(obj) : obj.id);
        else if (this.onselect) this.onselect(obj, !this.checked || !this.checked(obj));
        if (!this.checked) {
            if (!this.keep) close();
            this.setInput('');
            this.selId = null;
        }
    }

    setSel(dir=1) {
        let i = this.list.findIndex(e => e.id === this.selId) + dir;
        for (; i >= 0 && i < this.list.length; i+=dir)
            if (this.list[i]._props.selectable) {
                this.selId = this.list[i].id;
                return;
            }
    }

    // Ignore the hover event for 200ms after calling this. In some cases a
    // redraw/reselect is done that changes the positioning of the item
    // currently under the cursor; that will fire an onmouseover event without
    // it being the user's intent.
    // The 200ms is a weird magic number that will not work reliably.
    // This is an ugly hack, I'd rather see a better solution. :/
    skipHover() {
        this.doSkipHover = new Date();
    }

    keydown(ev) {
        if (ev.key == 'ArrowDown') {
            this.setSel();
            this.skipHover();
            ev.preventDefault();
        } else if (ev.key == 'ArrowUp') {
            this.setSel(-1);
            this.skipHover();
            ev.preventDefault();
        } else if (ev.key == 'Escape' || ev.key == 'Esc') {
            close();
        } else if (ev.key == 'Tab') {
            const f = this.list.find(e => e.id === this.selId);
            ev.shiftKey || !f ? close() : this.select();
            if (this.keep || this.checked) close(); // Tab always closes, even on multiselection boxes
            if (!this.autocomplete) ev.preventDefault();
        }
    }

    setList(lst) {
        this.list = [];
        this.skipHover();
        let hasSel = false;
        for (const e of lst) {
            e._props = this.props ? this.props(e) : {};
            if (e._props === null) continue;
            if (!('selectable' in e._props)) e._props.selectable = true;
            this.list.push(e);
            if (e.id === this.selId) hasSel = true;
        }
        if(!hasSel && (!this.autocomplete || this.input !== '')) this.setSel();
    }

    abort() {
        clearTimeout(this.loadingTimer);
        this.loadingStr = this.loadingTimer = null;
        if (this.source.api) this.source.api.abort();
    }

    setInput(str_, skipTimer) {
        this.input = str_;
        if (activeInstance !== this) return;
        const src = this.source;
        const str = str_.trim();
        if (src.init && src._initState !== 2) {
            src._initState = 1;
            src.init(src, () => {
                src._initState = 2;
                this.setInput(this.input);
            });
            return;
        }
        if (this.loadingStr === str && !skipTimer) return;
        this.abort();
        if (src.cache && src.cache[str]) {
            this.setList(src.cache[str]);
            return;
        }
        this.loadingStr = str;
        if (src.api && !skipTimer) {
            this.loadingTimer = setTimeout(() => { this.setInput(this.input, true); m.redraw() }, 500);
            return;
        }
        src.list(src, str, res => {
            this.loadingStr = null;
            this.setList(res);
            if (src.cache) src.cache[str] = res;
        });
    }

    loading() {
        return this.loadingTimer || (this.source.api && this.source.api.loading());
    }

    view() {
        const item = e => {
            const p = e._props;
            return m('li', {
                key: e.id,
                class: this.selId === e.id ? 'active' : !p.selectable ? 'unselectable' : null,
                onmouseover: p.selectable ? () => {
                    if (this.doSkipHover && ((new Date()).getTime()-this.doSkipHover.getTime()) < 200) return;
                    this.selId = e.id;
                } : null,
                onclick: p.selectable ? () => this.select(this.selId = e.id) : null,
            }, m('span', p.selectable ? '» ' : 'x '),
                this.checked ? [ m('input[type=checkbox]', { style: { visible: p.selectable ? 'visible' : 'hidden' }, checked: this.checked(e) }), ' ' ] : null,
                this.source.view(e),
                p.append,
            );
        };
        return m('form#ds', {
                onsubmit: ev => { ev.preventDefault(); this.select() },
                onupdate: position,
                oncreate: position,
            }, m('div', this.nosearch || this.autocomplete ? [] : [
                m('div',
                    m('input[type=text]', {
                        oncreate: this.focus, onupdate: this.focus,
                        value: this.input,
                        oninput: ev => this.setInput(ev.target.value),
                        placeholder: this.placeholder,
                    }),
                    m('span', {class: this.loading() ? 'spinner' : ''}, this.loading() ? null : m(Icon.Search)),
                ),
                this.checkall   ? m('div', m(Button.CheckAll,   { onclick: this.checkall   })) : null,
                this.uncheckall ? m('div', m(Button.UncheckAll, { onclick: this.uncheckall })) : null,
            ]),
            this.source.api && this.source.api.error
            ? m('b', this.source.api.error)
            : this.autocomplete && this.loading() ? m('span.spinner')
            : !this.loading() && this.input.trim() !== '' && this.list.length == 0
            ? m('em', 'No results')
            : m('div', m('ul',
                this.list.map(item),
                this.more && this.input === '' ? m('li', m('small', 'Type for more options')) : null,
            )),
        );
    }
};


DS.Button = {view: vnode => m('button.ds[type=button]', {
        class: vnode.attrs.invalid ? 'invalid ' + (vnode.attrs.class||'') : vnode.attrs.class,
        onclick: function(ev) { ev.preventDefault(); vnode.attrs.onclick ? vnode.attrs.onclick(ev) : vnode.attrs.ds && vnode.attrs.ds.open(this, null) },
    }, vnode.children, m('span.invisible', 'X'), m(Icon.ChevronDown)
)};


// Wrapper around an Input component, accepts the same attrs as an Input in
// addition to a 'ds' attribute to provide autocompletion.
DS.Input = {view: vnode => {
    const a = vnode.attrs;
    const open = () => {
        a.ds.setInput(a.data[a.field]);
        a.ds.open(vnode.dom.childNodes[0], v => {
            a.data[a.field] = v;
            a.oninput && a.oninput(v);
        });
    };
    return m('form.ds', {
        onsubmit: ev => {
            ev.preventDefault();
            const par = ev.target.parentNode.closest('form');
            if (activeInstance === a.ds) { activeInstance.select(); close(); }
            // requestSubmit() is a fairly recent browser addition, need to test for it.
            // Browsers without it will simply ignore the enter key, which is 'kay-ish as well.
            else if (par && par.requestSubmit) par.requestSubmit();
        } },
        m(Input, {
            ...a,
            onfocus: ev => {
                open();
                a.ds.selId = null; // Don't select anything yet, we don't want tabbing in and out of the input to change anything
                a.ds.setInput(''); // Pretend the input is empty, so we get the default listing when the input hasn't been modified
                a.onfocus && a.onfocus(ev);
            },
            oninput: v => {
                if (activeInstance !== a.ds) open();
                a.ds.setInput(v);
                a.oninput && a.oninput(v);
            },
        }),
    );
}};


// Source interface:
// - cache
//     Optional cache object, will be used to memoize calls to list()
// - opts
//     Default DS constructor options.
// - api
//     Optional Api object.
//     Used for a loading indicator & error reporting.
//     abort() is called whenever the input is changed.
//     If present, calls to list() will be delayed/throttled.
// - init(source, callback)
//     Optional, called when the source is first used.
//     Should call callback() to signal that list() is ready to be used.
// - list(source, str, callback)
//     Should run callback([objects]).
//     Each object must have a string 'id'
// - view(obj)
//     Should return a vnode for the given object
// - stringify(obj)
//     Should return a string representation of the given object.
//     Only used for autocompletion, defaults to obj.id.

const tt_view = obj => [
    obj.group_name ? m('small', obj.group_name, ' / ') : null,
    obj.name,
    obj.hidden && !obj.locked ? m('small', ' (awaiting approval)') : obj.hidden ? m('small', ' (deleted)') :
    !obj.searchable && !obj.applicable ? m('small', ' (meta)') :
    !obj.searchable ? m('small', ' (not searchable)') : !obj.applicable ? m('small', ' (not applicable)') : null
];

DS.Tags = {
    cache: {'':[]},
    opts: { placeholder: 'Search tags...' },
    api: new Api('Tags'),
    list: (src, str, cb) => src.api.call({ search: str }, res => cb(res.results)),
    view: tt_view,
};

DS.Traits = {
    cache: {'':[]},
    opts: { placeholder: 'Search traits...' },
    api: new Api('Traits'),
    list: (src, str, cb) => src.api.call({ search: str }, res => cb(res.results)),
    view: tt_view,
};

DS.VNs = {
    cache: {'':[]},
    opts: { placeholder: 'Search visual novels...' },
    api: new Api('VN'),
    list: (src, str, cb) => src.api.call({ search: [str] }, res => cb(res.results)),
    view: obj => [ m('small', obj.id, ': '), obj.title ],
};

DS.Anime = ref => ({
    cache: {'':[]},
    opts: { placeholder: 'Search anime...' },
    api: new Api('Anime'),
    list: (src, str, cb) => src.api.call({ search: str, ref }, res => cb(res.results)),
    view: obj => [ m('small', 'a', obj.id, ': '), obj.title_romaji ],
});

DS.Producers = {
    cache: {'':[]},
    opts: { placeholder: 'Search producers...' },
    api: new Api('Producers'),
    list: (src, str, cb) => src.api.call({ search: [str] }, res => cb(res.results)),
    view: obj => [ m('small', obj.id, ': '), obj.name ],
};

DS.Staff = {
    cache: {'':[]},
    opts: { placeholder: 'Search staff...' },
    api: new Api('Staff'),
    list: (src, str, cb) => src.api.call({ search: [str] }, res => cb(res.results)),
    view: obj => [ m('small', obj.sid, ': '), obj.title ],
};

DS.Chars = {
    cache: {'':[]},
    opts: { placeholder: 'Search characters...' },
    api: new Api('Chars'),
    list: (src, str, cb) => src.api.call({ search: str }, res => cb(res.results)),
    view: obj => [
        m('small', obj.id, ': '), obj.title,
        obj.main ? m('small', ' (instance of ' + obj.main.id + ': ' + obj.main.title + ')') : null,
    ],
};

DS.Engines = {
    api: new Api('Engines'),
    opts: { width: 250 },
    init: (src, cb) => src.api.call({}, res => cb(src.res = res.results, src.api = null)),
    list: (src, str, cb) => cb(src.res.filter(e => e.id.toLowerCase().includes(str.toLowerCase())).slice(0,30)),
    view: obj => [ obj.id, m('small', ' ('+obj.count+')') ],
};

DS.DRM = {
    api: new Api('DRM'),
    opts: { width: 250 },
    init: (src, cb) => src.api.call({}, res => cb(src.res = res.results, src.api = null)),
    list: (src, str, cb) => cb(src.res.filter(e => e.id.toLowerCase().includes(str.toLowerCase())).slice(0,30)),
    view: obj => [ obj.id, m('small', obj.state === 2 ? ' (deleted)' : ' ('+obj.count+')') ],
};

DS.Resolutions = {
    api: new Api('Resolutions'),
    opts: { width: 200 },
    init: (src, cb) => src.api.call({}, res => cb(src.res = res.results, src.api = null)),
    list: (src, str, cb) => cb(src.res.filter(e => e.id.toLowerCase().includes(str.toLowerCase())).slice(0,30)),
    view: obj => [ obj.id, m('small', ' ('+obj.count+')') ],
};

const Lang = f => ({
    opts: { width: 250, maxCols: 3 },
    list: (src, str, cb) => cb(vndbTypes.language
        .filter(([id,label]) => f(id) && (str === id.toLowerCase() || label.toLowerCase().includes(str.toLowerCase())))
        .anySort(([id,label,,rank]) => [id.toLowerCase() !== str.toLowerCase(), !label.toLowerCase().startsWith(str.toLowerCase()), 99-rank])
        .map(([id,label]) => ({id,label}))
    ),
    view: obj => [ LangIcon(obj.id), obj.label ]
});

DS.Lang = Lang(() => true);
// Chinese has separate language entries for the scripts
DS.ScriptLang = Lang(l => l !== 'zh');
DS.LocLang = Lang(l => l !== 'zh-Hans' && l !== 'zh-Hant');

DS.Platforms = {
    opts: { width: 250, maxCols: 3 },
    list: (src, str, cb) => cb(vndbTypes.platform
        .filter(([id,label]) => str.toLowerCase() === id.toLowerCase() || label.toLowerCase().includes(str.toLowerCase()))
        .anySort(([id,label]) => str ? [id.toLowerCase() !== str.toLowerCase(), !label.toLowerCase().startsWith(str.toLowerCase()), label] : 0)
        .map(([id,label]) => ({id,label}))
    ),
    view: obj => [ PlatIcon(obj.id), obj.label ]
};

DS.Releases = lst => ({
    opts: { width: 800 },
    list: (src, str, cb) => cb(lst.filter(r =>
        (r.id + ' ' + RDate.fmt(RDate.expand(r.released)) + ' ' + r.title).toLowerCase().includes(str.toLowerCase())
    )),
    view: obj => Release(obj,true),
});


// Wrap a source to add a "Create new entry" option.
// Args:
// - source
// - createobj: (str) => obj, should return an obj to add an option or null to not add anything.
// - view: obj => html
DS.New = (src, createobj, view) => ({...src,
    list: (x, str, cb) => src.list(x, str, lst => {
        const obj = createobj(str);
        if (obj && !lst.find(o => o.id === obj.id)) lst.unshift({...obj, _create:true});
        cb(lst);
    }),
    view: obj => obj._create === true ? view(obj) : src.view(obj),
});

window.DS = DS;
