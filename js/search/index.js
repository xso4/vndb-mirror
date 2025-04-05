// @license magnet:?xt=urn:btih:0b31508aeb0634b347b8270c7bee4d411b5d4109&dn=agpl-3.0.txt AGPL-3.0-only
// @source: https://code.blicky.net/yorhel/vndb/src/branch/master/js
// SPDX-License-Identifier: AGPL-3.0-only
"use strict";

// For sharing configuration & database object info between fields.
let globalData;

const fiedList = {
    v: [],
    r: [],
    c: [],
    s: [],
    p: [],
};


// A "set" field can hold a set of values that are AND or OR'ed together.
// Internally represented as an object with members:
//   values:  Set of active values
//   op:      0: OR  1:AND  2:!OR  3:!AND
// (AND does not make sense for every set field)

const setToQuery = id => set => {
    const lst = set.keys().map(v => [id, set.op & 2 ? '!=' : '=', v]);
    return lst.length === 0 ? null
         : lst.length === 1 ? lst[0]
         : [ set.op === 0 || set.op === 3 ? 'or' : 'and', ...lst ];
};

const setFromQuery = id => q =>
    q[0] === id ? { values: new Set([q[2]]), op: q[1] === '!=' ? 2 : 0 } :
    (q[0] === 'or' || q[0] === 'and') && q.slice(1).every(x => x[0] === id && x[1] === q[1][1]) ? {
        values: new Set(q.slice(1).map(x => x[2])),
        op: q[0] === 'or' ? (q[1][1] === '=' ? 0 : 3) : (q[1][1] === '=' ? 1 : 2),
    } : null;



// TODO: Support other operation lists
const opDs = new DS({
    list: (src, str, cb) => cb([
        {id: 0, sym: 'OR',  lbl: 'Matches any selected value'},
        {id: 1, sym: 'AND', lbl: 'Matches all selected values'},
        {id: 2, sym: 'OR',  lbl: 'Does not match any selected value'},
        {id: 3, sym: 'AND', lbl: 'Does not match all selected values'},
    ]),
    view: o => [m('strong', { class: o.id >= 2 ? 'not' : null }, o.sym), ': ', o.lbl],
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
        m('button[type=button]', {
            onclick: () => {
                if (tab === 1) inst._ds.open(opDs.opener);
                else {
                    opDs.width = $('#ds').offsetWidth;
                    opDs._inst = inst;
                    opDs.open(inst._ds.opener);
                }
            },
            class: inst.op >= 2 ? 'not' : null,
        }, inst.op & 1 ? 'AND' : 'OR'),
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
//   qtype
//   label
//   title
//   init: () => instance
//   fromquery: query => instance
//   toquery: instance => query
//   button: instance => html
const vnlang = {
    qtype: 'v',
    label: 'Language',
    title: 'Language this visual novel is available in',
    ds: inst => new DS(DS.ScriptLang, {
        keep: true,
        checked: o => inst.values.has(o.id),
        onselect: (o,c) => c ? inst.values.add(o.id) : inst.values.delete(o.id),
        uncheckall: () => inst.values.clear(),
    }),
    fromquery: setFromQuery(2),
    toquery: setToQuery(2),
    button: inst => '', // TODO
};

// Field instance
const vnlanginst = vnlang.fromquery([2,"=","en"]);
vnlanginst._def = vnlang;
vnlanginst._ds = vnlang.ds(vnlanginst);
vnlanginst._ds.header = fieldHeader(vnlanginst);



widget('AdvSearch', initvnode => {
    const data = initvnode.attrs.data;
    // We currently only ever have a single instance of this widget on a page,
    // so can keep this simple.
    globalData = data;

    const view = () => m(DS.Button, {ds:vnlanginst._ds}, vnlang.button(vnlanginst));
    return {view};
});

// @license-end
