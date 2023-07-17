// JS Widget corresponding to VNWeb::TableOpts, see the Perl implementation for
// encoding & option details.

// Simple wrapper to abstract away the bitwise crap.
// These operate on 32bit integers, BigInts are a bit too recent to use I
// think, but we don't need those yet.
class Opts {
    constructor(num) { this.n = num }

    //get view()    { return this.n & 3 }
    get results() { return (this.n >> 2) & 7 }
    get order()   { return (this.n & 32) > 0 }
    get sortCol() { return (this.n >> 6) & 63 }
    isVis(v)      { return (this.n & (1 << (v + 12))) > 0 }

    //set view(v)    { this.n = (this.n & ~3) | v }
    set results(v) { this.n = (this.n & ~28) | (v << 2) }
    set order(v)   { this.n = v ? (this.n | 32) : (this.n & ~32) }
    set sortCol(v) { this.n = (this.n & ~4032) | (v << 6) }
    setVis(v,b)    { this.n = b ? (this.n | (1 << (v + 12))) : (this.n & ~(1 << (v + 12))) }

    encode() {
        const alpha = '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_-';
        let n = this.n;
        let v = n ? '' : alpha[0];
        while(n > 0) {
            v = alpha[n & 63].concat(v);
            n >>= 6;
        }
        return v;
    }
}

const resultOptions = [50,10,25,100,200];

widget('TableOpts', (vnode) => {
    const conf = vnode.attrs.data;
    const opts = new Opts(conf.value);
    const save = new Api('TableOptsSave');

    // This widget is loaded into an <ul> that contains a hidden input element
    // - which we don't need, we create our own - and potentially some view
    // buttons that we do like to keep. This is an ugly hack to load the
    // pre-existing elements into our vdom by going through an HTML parse.
    // Would be nicer if we can just pass DOM nodes directly to the vdom, but
    // Mithril doesn't support that. Maybe contribute that as a new feature?
    // Doesn't sound too complicated given that "trust" nodes already have the
    // infrastructure for it.
    const oldNodes = m.trust(vnode.attrs.oldContents.filter(e => !e.querySelector('input[name=s]')).map(e => e.outerHTML).join(''));

    const submit = (o) => {
        const e = vnode.dom.parentNode.querySelector('input[name=s]');
        e.value = o.encode();
        e.form.submit();
    };

    const sortBut = (s,desc) => m('a[href=#]', {
        onclick: ev => {
            ev.preventDefault();
            let o = new Opts(opts.n);
            o.sortCol = s.id;
            o.order = desc;
            submit(o);
        },
        class: opts.sortCol == s.id && opts.order == desc ? 'checked' : null,
        title: s.name + ' ' + (desc ? 'descending' : 'ascending'),
    }, s.num ? (desc ? '9→1' : '1→9') : (desc ? 'Z→A' : 'A→Z'));

    const view = () => [
        m('li.hidden', m('input[type=hidden][name=s]', { value: opts.encode() })),
        !conf.save ? null : m('li.maintabs-dd.tableopts-save', m(MainTabsDD, {
            a_body: Icon.Save,
            a_attrs: { title: 'save display settings' },
            content: () => [
                m('h4', 'save display settings'),
                save.saved({ save: conf.save, value: opts.n }) ? 'Saved!'
                : save.loading() ? m('span.spinner')
                : save.error ? m('b', save.error)
                : m('input[type=button]', {
                    value: 'Save current settings as default',
                    onclick: () => save.call({ save: conf.save, value: opts.n })
                }),
                conf.default == opts.n ? null : m('input[type=button]', {
                    value: 'Load default view',
                    onclick: () => submit(new Opts(conf.default)),
                }),
                conf.usaved === null || conf.usaved == opts.n ? null : m('input[type=button]', {
                    value: 'Load my saved settings',
                    onclick: () => submit(new Opts(conf.usaved)),
                }),
            ],
        })),
        m('li.maintabs-dd.tableopts-results', m(MainTabsDD, {
            a_body: resultOptions[opts.results],
            a_attrs: { title: 'results per page' },
            content: () => [
                m('h4', 'results per page'),
                [1,2,0,3,4].flatMap(n => [' | ',
                    m('a[href=#]', {
                        onclick: (ev) => { ev.preventDefault(); let o = new Opts(opts.n); o.results = n; submit(o) },
                    }, resultOptions[n])
                ]).slice(1),
            ]
        })),
        conf.vis.length == 0 ? null : m('li.maintabs-dd.tableopts-cols', m(MainTabsDD, {
            a_body: Icon.Eye,
            a_attrs: { title: 'visible columns' },
            content: () => [
                m('h4', 'visible columns'),
                conf.vis.map(c => m('label', c.name, ' ', m('input[type=checkbox]', {
                    checked: opts.isVis(c.id),
                    oninput: ev => opts.setVis(c.id, ev.target.checked),
                }))),
                m('input[type=submit][value=Update]'),
            ]
        })),
        conf.sorts.length == 0 ? null : m('li.maintabs-dd.tableopts-sort', m(MainTabsDD, {
            a_body: Icon.ArrowDownUp,
            a_attrs: { title: 'sort options' },
            content: () => [
                m('h4', 'sort options'),
                m('table', conf.sorts.map(s => m('tr',
                    m('td', s.name),
                    m('td', sortBut(s,false)),
                    m('td', sortBut(s,true)),
                ))),
            ]
        })),
        oldNodes,
    ];
    return {view};
})
