// @license magnet:?xt=urn:btih:0b31508aeb0634b347b8270c7bee4d411b5d4109&dn=agpl-3.0.txt AGPL-3.0-only
// @source: https://code.blicky.net/yorhel/vndb/src/branch/master/js
// SPDX-License-Identifier: AGPL-3.0-only
"use strict";


const AND = 0;
const OR = 1;


// For sharing configuration & database object info between fields.
let globalData;


// A "set" field can hold a set of values that are AND or OR'ed together.
// Internally represented as an object with members:
//   values:  Set of active values
//   op:      opList.id

const setToQuery = id => set => {
    const lst = [ ...set.values.keys().map(v => [id, set.op & 2 ? '!=' : '=', v]) ];
    return lst.length === 0 ? null
         : lst.length === 1 ? lst[0]
         : [ set.op === 0 || set.op === 3 ? OR : AND, ...lst ];
};

const setFromQuery = id => q =>
    q[0] === id ? { values: new Set([q[2]]), op: q[1] === '!=' ? 2 : 0 } :
    (q[0] <= 1) && q.slice(1).every(x => x[0] === id && x[1] === q[1][1]) ? {
        values: new Set(q.slice(1).map(x => x[2])),
        op: q[0] === OR ? (q[1][1] === '=' ? 0 : 3) : (q[1][1] === '=' ? 1 : 2),
    } : null;



const opList = [
    {id: 0, sym: 'OR',  lbl: 'Matches any selected value'},
    {id: 1, sym: 'AND', lbl: 'Matches all selected values'},
    {id: 2, sym: 'OR',  neg: true, lbl: 'Does not match any selected value'},
    {id: 3, sym: 'AND', neg: true, lbl: 'Does not match all selected values'},
];

const opFmt = (i,single=false) =>
    single ? (opList[i].neg ? m('b', '≠') : null) :
    m('span', { class: opList[i].neg ? 'op_neg' : null }, opList[i].sym);


// TODO: Support other operation lists
const opDs = new DS({
    list: (src, str, cb) => cb(opList),
    view: o => [m('strong', opFmt(o.id)), ': ', o.lbl],
}, {
    nosearch: true, keep: true,
    header: () => fieldHeader(opDs._inst, 1)(),
    onselect: o => {
        opDs._inst.op = o.id;
        opDs._inst._ds.open(opDs.opener);
    },
});

const fieldHeader = (inst, tab=0) => () => m('div.xsearch_opts',
    m('div',
        inst._def.opstyle === 'set' ? m('button[type=button]', { onclick: () => {
            if (tab === 1) inst._ds.open(opDs.opener);
            else {
                opDs.width = $('#ds').offsetWidth;
                opDs._inst = inst;
                opDs.open(inst._ds.opener);
            }
        }}, opFmt(inst.op)) : null,
        //m('button', 'SPL'), // Spoiler, for tags & traits
    ),
    m('strong', { onclick: () => { if (tab !== 0) inst._ds.open(inst._ds.opener) } }, inst._def.title),
    m('div',
        m(Button.Unbranch),
        m(Button.Branch),
        m(Button.Del),
    ),
);


// Field definition:
//   label   (optional, unlisted when missing)
//   title   (optional, same as label when missing)
//   init: () => instance     (optional, unlisted when missing)
//   fromquery: query => instance
//   toquery: instance => query
//   opstyle:   Supported operators, 'set', 'eq' or 'ord'
//   ds: instance => new DS(..)
//   button: instance => html

const unknownField = {
    title: 'Unrecognized filter',
    button: () => 'Unrecognized filter',
    ds: inst => new DS(null, {
        width: 300,
        header: () => m('p',
            "This interface does not support editing filters of this type, but the filter is still applied to the listing below.",
            m('br'), m('br'), m('small', 'Raw query: ', JSON.stringify(inst.q)),
        ),
    }),
    fromquery: q => ({q}),
    toquery: ({q}) => q,
};

const fieldList = {
v: [
    unknownField,
    {
        label: 'Language',
        title: 'Language the visual novel is available in',
        ds: inst => new DS(DS.ScriptLang, {
            checked: o => inst.values.has(o.id),
            onselect: (o,c) => c ? inst.values.add(o.id) : inst.values.delete(o.id),
            uncheckall: () => inst.values.clear(),
        }),
        fromquery: setFromQuery(2),
        toquery: setToQuery(2),
        opstyle: 'set',
        button: inst => inst.values.size === 0 ? m('small', 'Language') : [
            opFmt(inst.op, inst.values.size === 1), ' ',
            vndbTypes.language.anySort(([,,,rank]) => 99-rank).map(([v,l]) => inst.values.has(v) ? [ LangIcon(v), inst.values.size === 1 ? l : null ] : null)
        ],
    }
],
r: [
    unknownField,
],
c: [
    unknownField,
],
s: [
    unknownField,
],
p: [
    unknownField,
]};


const fromQuery = (qtype, q) => {
    for(const f of fieldList[qtype].slice().reverse()) {
        const inst = f.fromquery(q);
        if (!inst) continue;
        if (!('title' in f)) f.title = f.label;
        inst._def = f;
        inst._ds = f.ds(inst);
        inst._ds.keep = true;
        const hd = inst._ds.header;
        inst._ds.header = hd ? () => [ fieldHeader(inst)(), hd() ] : fieldHeader(inst);
        return inst;
    }
};

const encodeQuery = (() => {
    const alpha = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_-";
    const esc = new Map(" !\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~".split('').map((c,i) => [c,i]));
    // XXX: Bit silly to do this mapping when we can work directly with the integers.
    const ops = new Map([['=',0], ['!=',1], ['>=',2], ['>', 3], ['<=', 4], ['<', 5]]);
    const eint = v => {
        const n = parseInt(v, 10);
        if (n < 0 || n !== parseFloat(v)) return null;
        if (n < 49) return alpha[n];
        if (n < 689) return alpha[49 + Math.floor((n-49)/64)] + alpha[(n-49)%64];
        const r = (l,v) => (l > 1 ? r(l-1, Math.floor(v/64)) : '') + alpha[v%64];
        if (n <        4785) return 'X'+r(2, n -        689);
        if (n <      266929) return 'Y'+r(3, n -       4785);
        if (n <    17044145) return 'Z'+r(4, n -     266929);
        if (n <  1090785969) return '_'+r(5, n -   17044145);
        if (n < 69810262705) return '-'+r(6, n - 1090785969);
        return null;
    };
    const estr = s => String(s).replaceAll(/./g, c => esc.has(c) ? '_'+alpha[esc.get(c)] : c);

    const equery = q => {
        if (q[0] <= 1) return alpha[q[0]] + eint(q.length-1) + q.slice(1).map(encodeQuery).join('');
        const r = t => eint(q[0]) + eint(ops.get(q[1]) + 8*t);
        if (typeof q[2] === 'object' && q[2].length === 2 && /^[0-9]+$/.match(q[2][1])) return r(5) + eint(q[2][0]) + eint(q[2][1]);
        if (typeof q[2] === 'object') return r(1) + equery(q[2]);
        const i = eint(q[2]);
        if (i !== null) return r(0) + i;
        const e = estr(q[2]);
        if (e.length === 2) return r(2)+e;
        if (e.length === 3) return r(3)+e;
        return r(4)+e+'-';
    };
    return equery;
})();


widget('AdvSearch', initvnode => {
    const data = initvnode.attrs.data;
    // We currently only ever have a single instance of this widget on a page,
    // so can keep this simple.
    globalData = data;

    const root = data.query && fromQuery(data.qtype, data.query);

    const view = () => !root ? null : m('div.xsearch',
        m('input[type=hidden][id=f][name=f]', { value: encodeQuery(root._def.toquery(root)) }),
        m(DS.Button, {ds:root._ds, title: root._def.title, class: 'field' }, m('span', root._def.button(root)))
    );
    return {view};
});

// @license-end
