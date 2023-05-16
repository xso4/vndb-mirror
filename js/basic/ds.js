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

const close = ev => {
    if (!activeInstance) return;
    if (ev && (globalObj.contains(ev.target) || ev.target === activeInstance.opener)) return;
    if (!ev) activeInstance.opener.focus();
    activeInstance.abort();
    activeInstance = null;
    document.removeEventListener('click', close);
    document.removeEventListener('keydown', keydown);
    m.redraw();
};


// Constructor options (all optional):
// - anchor
//    where to place the box w.r.t. the element that triggers its opening.
//    'bl' -> bottom left, 'br' -> bottom right
// - xoff / yoff
//    x & y offsets for positioning
// - width
// - placeholder
// - source
//     Source object, see below
// - onselect(obj)
//     Called when an item has been selected
//
// Actual positioning and size of the box may differ from the given options in
// order to adjust for different window sizes; but that hasn't been implemented
// yet.
//
// TODO:
// - Make sure the box is inside the browsers' viewport
// - Better handling of large lists (scrolling?)
// - "Create new entry" option (e.g. for engines and labels)
// - Multiselection?
class DS {
    constructor(opts) {
        this.anchor = 'bl';
        this.width = 300;
        this.input = '';
        Object.assign(this, opts);
        this.open = this.open.bind(this);
        this.list = [];
    }

    open(ev) {
        ev.preventDefault();
        setupObj();
        activeInstance = this;
        this.opener = ev.target;
        // BUG: this doesn't work if ev.target is inside a positioned element
        const rect = ev.target.getBoundingClientRect();
        this.left = rect.x + window.scrollX + (this.xoff||0) + (this.anchor == 'br' ? rect.width - this.width : 0);
        this.top  = rect.y + window.scrollY + (this.yoff||0) + rect.height;
        this.focus = v => { this.focus = null; v.dom.focus() };
        document.addEventListener('click', close);
        document.addEventListener('keydown', keydown);
        this.setInput(this.input);
    }

    select() {
        const obj = this.list.find(e => e.id === this.selId);
        if (!obj) return;
        close();
        this.onselect && this.onselect(obj);
        this.setInput('');
        this.selId = null;
    }

    keydown(ev) {
        const i = this.list.findIndex(e => e.id === this.selId);
        if (ev.key == 'ArrowDown') {
            if (i >= 0 && i+1 < this.list.length) this.selId = this.list[i+1].id;
            ev.preventDefault();
        } else if (ev.key == 'ArrowUp') {
            if (i > 0) this.selId = this.list[i-1].id;
            ev.preventDefault();
        } else if (ev.key == 'Escape' || ev.key == 'Esc') {
            close();
        } else if (ev.key == 'Tab') {
            ev.shiftKey || i == -1 ? close() : this.select();
            ev.preventDefault();
        }
    }

    setList(lst) {
        this.list = lst;
        if(!lst.find(e => e.id === this.selId)) this.selId = lst.length > 0 ? lst[0].id : null;
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

    view() {
        const loading = this.loadingTimer || (this.source.api && this.source.api.loading());
        return m('form#ds', {
                style: { left: this.left+'px', top: this.top+'px', width: this.width+'px' },
                onsubmit: ev => { ev.preventDefault(); this.select() },
            }, m('div',
                m('input[type=text]', {
                    oncreate: this.focus, onupdate: this.focus,
                    value: this.input,
                    oninput: ev => this.setInput(ev.target.value),
                    placeholder: this.placeholder,
                }),
                loading ? m('span.spinner') : null,
            ),
            this.source.api && this.source.api.error
            ? m('b', this.source.api.error)
            : !loading && this.input.trim() !== '' && this.list.length == 0
            ? m('em', 'No results')
            : m('ul',
                this.list.map(e => m('li', {
                    key: e.id,
                    class: this.selId === e.id ? 'active' : null,
                    onmouseover: () => this.selId = e.id,
                    onclick: () => this.select(this.selId = e.id),
                }, m('span', '» '), this.source.view(e)))
            ),
        );
    }
};


// Source interface:
// - cache
//     Optional cache object, will be used to memoize calls to list()
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

DS.Tags = {
    cache: {'':[]},
    api: new Api('Tags'),
    list: (src, str, cb) => src.api.call({ search: str }, res => res && cb(res.results)),
    view: obj => [ obj.name,
        obj.hidden && !obj.locked ? m('small', ' (awaiting approval)') : obj.hidden ? m('small', ' (deleted)') :
        !obj.searchable && !obj.applicable ? m('small', ' (meta)') :
        !obj.searchable ? m('small', ' (not searchable)') : !obj.applicable ? m('small', ' (not applicable)') : null ]
};

DS.Engines = {
    api: new Api('Engines'),
    init: (src, cb) => src.api.call({}, res => res && cb(src.res = res.results, src.api = null)),
    list: (src, str, cb) => cb(src.res.filter(e => e.id.toLowerCase().indexOf(str.toLowerCase()) !== -1).slice(0,15)),
    view: obj => [ obj.id, m('small', ' ('+obj.count+')') ],
};

window.DS = DS;
