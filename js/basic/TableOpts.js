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
    let saved = false;

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

    // SVG icons from Wordpress Dashicons, GPLv2.
    // Except for the floppy icon, that's from Fork Awesome, SIL OFL 1.1.
    const view = () => [
        m('li.hidden', m('input[type=hidden][name=s]', { value: opts.encode() })),
        !conf.save ? null : m('li.maintabs-dd.tableopts-save', m(MainTabsDD, {
            a_body: m.trust('<svg height=13 width=13 viewbox="0 0 1700 1700"><path d="M384 1536h768v-384H384v384zm896 0h128V640c0-19-17-60-30-73l-281-281c-14-14-53-30-73-30v416c0 53-43 96-96 96H352c-53 0-96-43-96-96V256H128v1280h128v-416c0-53 43-96 96-96h832c53 0 96 43 96 96v416zM896 608V288c0-17-15-32-32-32H672c-17 0-32 15-32 32v320c0 17 15 32 32 32h192c17 0 32-15 32-32zm640 32v928c0 53-43 96-96 96H96c-53 0-96-43-96-96V224c0-53 43-96 96-96h928c53 0 126 30 164 68l280 280c38 38 68 111 68 164z"/></svg>'),
            a_attrs: { title: 'save display settings' },
            content: () => [
                m('h4', 'save display settings'),
                saved ? 'Saved!'
                : save.loading() ? m('span.spinner')
                : save.error ? m('b', save.error)
                : m('input[type=button]', {
                    value: 'Save current settings as default',
                    onclick: () => save.call(
                        { save: conf.save, value: opts.n },
                        () => { saved = true },
                    )
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
            a_body: m.trust('<svg height=13 width=13 viewbox="0 0 20 20"><path d="M10 5.09c3.98 0 7.4 2.25 9 5.5-1.6 3.25-5.02 5.5-9 5.5s-7.4-2.25-9-5.5c1.6-3.25 5.02-5.5 9-5.5zm2.35 3.1c0-.59-.39-1.08-.92-1.24-.16-.02-.32-.03-.49-.04-.65.05-1.17.6-1.17 1.28 0 .71.58 1.29 1.29 1.29.72 0 1.29-.58 1.29-1.29zM10 14.89c3.36 0 6.25-1.88 7.6-4.3-.93-1.67-2.6-2.81-4.65-3.35a4.042 4.042 0 0 1-2.95 6.8 4.042 4.042 0 0 1-2.95-6.8C5 7.78 3.33 8.92 2.4 10.59c1.35 2.42 4.24 4.3 7.6 4.3z"/></svg>'),
            a_attrs: { title: 'visible columns' },
            content: () => [
                m('h4', 'visible columns'),
                conf.vis.map(c => m('label', c.name, ' ', m('input[type=checkbox]', {
                    checked: opts.isVis(c.id),
                    oninput: function() { saved = false; opts.setVis(c.id, this.checked) },
                }))),
                m('input[type=submit][value=Update]'),
            ]
        })),
        conf.sorts.length == 0 ? null : m('li.maintabs-dd.tableopts-sort', m(MainTabsDD, {
            a_body: m.trust('<svg height=13 width=13 viewbox="0 0 20 20"><path d="M11 7H1l5 7zm-2 7h10l-5-7z"/></svg>'),
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
