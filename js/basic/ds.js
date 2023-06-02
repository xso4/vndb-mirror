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

    // XXX: The actual height of the box is dynamic, but we'd rather not have
    // it jump around on user input so better reserve some space.
    const minHeight = 200;
    const margin = 5;

    const inst = activeInstance;
    const opener = inst.opener.getBoundingClientRect(); // BUG: this doesn't work if ev.target is inside a positioned element
    const header = obj.children[0].getBoundingClientRect().height;
    const left = Math.max(margin, Math.min(
        window.innerWidth - inst.width - 2*margin,
        opener.x + (inst.xoff||0) + (inst.anchor == 'br' ? opener.width - inst.width : 0)
    ));
    const width = Math.min(window.innerWidth - margin*2, inst.width);

    const top = Math.max(margin, Math.min(
        window.innerHeight - minHeight - margin,
        opener.y + (inst.yoff||0) + opener.height
    ));
    const height = Math.max(header + 20, Math.min(window.innerHeight - margin*2, window.innerHeight - top - margin));

    obj.style.top  = (top  + window.scrollY) + 'px';
    obj.style.left = (left + window.scrollX) + 'px';
    obj.style.width = width + 'px';
    const l = obj.children[1];
    if (l && l.tagName == 'UL') l.style.maxHeight = (height - header) + 'px';

    // Special case: if we've moved the box above the opener, make sure to
    // expand the box even if there's nothing to select. Otherwise there's a
    // weird disconnected floating input.
    obj.style.minHeight = Math.max(0, opener.top - top) + 'px';

    const e = obj.querySelector('li.active');
    if (e) e.scrollIntoView({block: 'nearest'});
};

const close = ev => {
    if (!activeInstance) return;
    if (ev && (globalObj.contains(ev.target) || ev.target === activeInstance.opener)) return;
    if (!ev) activeInstance.opener.focus();
    activeInstance.abort();
    activeInstance = null;
    document.removeEventListener('click', close);
    document.removeEventListener('keydown', keydown);
    document.removeEventListener('scroll', position);
    removeEventListener('resize', position);
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
//
// Actual positioning and size of the box may differ from the given options in
// order to adjust for different window sizes.
//
// TODO:
// - "Create new entry" option (e.g. for engines and labels)
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
        this.onselect && this.onselect(obj, !this.checked || !this.checked(obj));
        if (!this.checked) {
            close();
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
        const i = this.list.findIndex(e => e.id === this.selId);
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
            ev.shiftKey || i == -1 ? close() : this.select();
            ev.preventDefault();
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
        const str = str_.trim().toLowerCase();
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
            }, m('div',
                m('div',
                    m('input[type=text]', {
                        oncreate: this.focus, onupdate: this.focus,
                        value: this.input,
                        oninput: ev => this.setInput(ev.target.value),
                        placeholder: this.placeholder,
                    }),
                    loading ? m('span.spinner') : null,
                ),
                this.checkall   ? m('div', m(CheckAllButton,   { onclick: this.checkall   })) : null,
                this.uncheckall ? m('div', m(UncheckAllButton, { onclick: this.uncheckall })) : null,
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
    list: (src, str, cb) => cb(src.res.filter(e => e.id.toLowerCase().includes(str)).slice(0,30)),
    view: obj => [ obj.id, m('small', ' ('+obj.count+')') ],
};

DS.Lang = {
    opts: { width: 250 },
    list: (src, str, cb) => cb(vndbTypes.language
        .filter(([id,label]) => str === id.toLowerCase() || label.toLowerCase().includes(str))
        // Sorting considerations: id match > prefix match > rank > label
        .sort(([aid,alabel,,arank],[bid,blabel,,brank]) =>
            aid === bid ? 0 : aid.toLowerCase() === str ? -1 : bid.toLowerCase() === str ? 1
            : alabel.toLowerCase().startsWith(str) && !blabel.toLowerCase().startsWith(str) ? -1
            : !alabel.toLowerCase().startsWith(str) && blabel.toLowerCase().startsWith(str) ? 1
            : brank - arank) // sort() is stable so no need to compare label
        .map(([id,label]) => ({id,label}))
    ),
    view: obj => [ LangIcon(obj.id), obj.label ]
};

window.DS = DS;
