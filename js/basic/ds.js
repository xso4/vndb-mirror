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
// - onselect(obj)
//     Called when an item has been selected
// - props(obj)
//     Called on each displayed object, should return null if the object should
//     be filtered out or an object otherwise. The object supports the
//     following options:
//     - selectable: boolean, default true
//     - append: vdom node to append to the item
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
    constructor(source, opts) {
        this.anchor = 'bl';
        this.width = 400;
        this.input = '';
        this.source = source;
        if (source.opts) Object.assign(this, source.opts);
        if (opts) Object.assign(this, opts);
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

    setSel(dir=1) {
        let i = this.list.findIndex(e => e.id === this.selId) + dir;
        for (; i >= 0 && i < this.list.length; i+=dir)
            if (this.list[i]._props.selectable) {
                this.selId = this.list[i].id;
                return;
            }
    }

    keydown(ev) {
        const i = this.list.findIndex(e => e.id === this.selId);
        if (ev.key == 'ArrowDown') {
            this.setSel();
            ev.preventDefault();
        } else if (ev.key == 'ArrowUp') {
            this.setSel(-1);
            ev.preventDefault();
        } else if (ev.key == 'Escape' || ev.key == 'Esc') {
            close();
        } else if (ev.key == 'Tab') {
            ev.shiftKey || i == -1 ? close() : this.select();
            ev.preventDefault();
        }
    }

    setList(lst) {
        this.list = [];
        let hasSel = false;
        for (const e of lst) {
            e._props = this.props ? this.props(e) : {};
            if (e._props === null) continue;
            if (!('selectable' in e._props)) e._props.selectable = true;
            this.list.push(e);
            if (e.id === this.selId) hasSel = true;
        }
        if(!hasSel) this.setSel();
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
        const item = e => {
            const p = e._props;
            return m('li', {
                key: e.id,
                class: this.selId === e.id ? 'active' : !p.selectable ? 'unselectable' : null,
                onmouseover: p.selectable ? () => this.selId = e.id : null,
                onclick: p.selectable ? () => this.select(this.selId = e.id) : null,
            }, m('span', p.selectable ? '» ' : 'x '),
                this.source.view(e),
                p.append,
            );
        };
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
            : m('ul', this.list.map(item)),
        );
    }
};


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
    list: (src, str, cb) => src.api.call({ search: str }, res => res && cb(res.results)),
    view: tt_view,
};

DS.Traits = {
    cache: {'':[]},
    opts: { placeholder: 'Search traits...' },
    api: new Api('Traits'),
    list: (src, str, cb) => src.api.call({ search: str }, res => res && cb(res.results)),
    view: tt_view,
};

DS.Engines = {
    api: new Api('Engines'),
    init: (src, cb) => src.api.call({}, res => res && cb(src.res = res.results, src.api = null)),
    list: (src, str, cb) => cb(src.res.filter(e => e.id.toLowerCase().indexOf(str.toLowerCase()) !== -1).slice(0,15)),
    view: obj => [ obj.id, m('small', ' ('+obj.count+')') ],
};

window.DS = DS;
