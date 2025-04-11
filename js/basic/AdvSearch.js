const AND = 0;
const OR = 1;


// Field definition members:
//   label         (optional, unlisted when missing)
//   title         (optional, same as label when missing)
//   init          query => instance  (query=null to init an empty field)
//   toquery       instance => query
//   opstyle       supported operators, 'set', 'eq' or 'ord'
//   ds            instance => new DS(..)
//   button        instance => html
//   ptype/qtype   parent type and query type, only used for nestfields

// Field instance members:
//   ds            DS Instance
//   def           Reference to the field definition
//   parent        Parent field (always a nestfield)
//   ...           Additional field-specific members


// For sharing configuration & database object info between fields.
let globalData;


// A "set" field can hold a set of values that are AND or OR'ed together.
// Uses the following field instance members:
//   values:  Set of active values
//   op:      opList.id
const setField = (id, opstyle, source) => ({
    opstyle,
    ds: inst => new DS(source, {
        checked: o => inst.values.has(o.id),
        onselect: (o,c) => c ? inst.values.add(o.id) : inst.values.delete(o.id),
        uncheckall: () => inst.values.clear(),
    }),
    init: q =>
        !q ? { values: new Set(), op: 0 } :
        q[0] === id ? { values: new Set([q[2]]), op: q[1] === '!=' ? 2 : 0 } :
        (q[0] <= 1) && q.length > 1 && q.slice(1).every(x => x[0] === id && x[1] === q[1][1]) ? {
            values: new Set(q.slice(1).map(x => x[2])),
            op: q[0] === OR ? (q[1][1] === '=' ? 0 : 3) : (q[1][1] === '=' ? 1 : 2),
        } : null,
    toquery: inst => {
        const lst = [ ...inst.values.keys().map(v => [id, inst.op & 2 ? '!=' : '=', v]) ];
        return lst.length === 0 ? null
             : lst.length === 1 ? lst[0]
             : [ inst.op === 0 || inst.op === 3 ? OR : AND, ...lst ];
    }
});

const langField = (id, opstyle, source, label, title, prefix='') => ({
    label, title,
    ...setField(id, opstyle, source),
    button: inst => inst.values.size === 0 ? m('small', label) : [
        prefix,
        opFmt(inst.op, inst.values.size === 1), ' ',
        vndbTypes.language.anySort(([,,,rank]) => 99-rank).map(([v,l]) => inst.values.has(v) ? [ LangIcon(v), inst.values.size === 1 ? l : null ] : null)
    ],
});


const opList = [
    {id: 0, sym: 'OR',  lbl: 'Matches any selected value'},
    {id: 1, sym: 'AND', lbl: 'Matches all selected values'},
    {id: 2, sym: 'OR',  neg: true, lbl: 'Does not match any selected value'},
    {id: 3, sym: 'AND', neg: true, lbl: 'Does not match all selected values'},
];

const opFmt = (i,single=false) =>
    single ? (opList[i].neg ? m('b', '≠') : null) :
    m('span', { class: opList[i].neg ? 'op_neg' : null }, opList[i].sym);


const opDs = new DS({
    list: (src, str, cb) => cb(opList.filter(o => opDs._inst.def.opstyle === 'set' || o.sym === 'OR')),
    view: o => [m('strong', opFmt(o.id)), ': ', o.lbl],
}, {
    nosearch: true, keep: true,
    header: () => fieldHeader(opDs._inst, 1),
    onselect: o => {
        opDs._inst.op = o.id;
        opDs._inst.ds.open(opDs.opener);
    },
});



const fieldHeader = (inst, tab=0) => m('div.xsearch_opts',
    m('div',
        inst.def.opstyle ? m('button[type=button]', { onclick: () => {
            if (tab === 1) inst.ds.open(opDs.opener);
            else {
                opDs.width = $('#ds').offsetWidth;
                opDs._inst = inst;
                opDs.open(inst.ds.opener);
            }
        }}, opFmt(inst.op)) : null,
        //m('button', 'SPL'), // Spoiler, for tags & traits
    ),
    m('strong', { onclick: () => { if (tab !== 0) inst.ds.open(inst.ds.opener) } }, inst.def.title),
    m('div',
        inst.parent.parent && inst.parent.parent.parent && inst.parent.def.ptype === inst.parent.def.qtype ? m(Button.Unbranch, { onclick: () => {
            DS.close();
            const idx = inst.parent.parent.childs.findIndex(n => n === inst.parent);
            if (inst.parent.childs.length === 1) inst.parent.parent.childs[idx] = inst;
            else {
                inst.parent.parent.childs.splice(idx, 0, inst);
                inst.parent.childs = inst.parent.childs.filter(n => n !== inst);
            }
        }}) : null,
        m(Button.Branch, { onclick: () => {
            DS.close();
            const newpar = instantiateField(andorField[inst.parent.def.qtype], null);
            newpar.op = inst.parent.op === 0 ? 1 : 0;
            newpar.childs = [inst];
            inst.parent.childs.forEach((v,i,l) => { if (v === inst) l[i] = newpar });
        }}),
        inst.parent.parent ? m(Button.Del, { onclick: () => {
            DS.close();
            inst.parent.childs = inst.parent.childs.filter(n => n !== inst);
        }}) : null,
    ),
);


const unknownField = {
    title: 'Unrecognized filter',
    button: () => m('small', 'Unrecognized'),
    ds: inst => new DS(null, {
        width: 300,
        header: () => m('p',
            "This interface does not support editing filters of this type, but the filter is still applied to the listing below.",
            m('br'), m('br'), m('small', 'Raw query: ', JSON.stringify(inst.q)),
        ),
    }),
    init: q => ({q}),
    toquery: ({q}) => q,
};

const nestField = (ptype, qtype=ptype, id, label='And/Or', button, yes, no) => {
    const andor = inst => new DS({
        list: (src, str, cb) => cb([{id:0},{id:1}]),
        view: o => [m('strong', o.id?'Or':'And'), ': ', o.id?'At least one filter must match':'All filters must match'],
    }, {
        keep: false, nosearch: true, width: 300,
        onselect: o => inst.op = o.id
    });
    const init = q => {
        const inst = {op:0, eq:'=', childs: []};
        if (id) inst.andords = andor(inst);
        if (!q) return inst;

        if (id) {
            if (q[0] !== id) return null;
            inst.eq = q[1];
            q = [0,q[2]];
        }
        if (q[0] > 1) return null;
        inst.op = q[0];
        inst.childs = q.slice(1).map(n => fromQuery(qtype, n));
        // If all childs are unknown, consider this whole query as a single unknown.
        if (!id && inst.childs.length > 0 && !inst.childs.find(n => n.def !== unknownField)) return null;
        // Merge nested and/or
        while (id && inst.childs.length === 1 && inst.childs[0].def.qtype && inst.childs[0].def.qtype === inst.childs[0].def.ptype) {
            inst.op = inst.childs[0].op;
            inst.childs = inst.childs[0].childs;
        }
        return inst;
    };
    const toquery = inst => {
        const lst = [...inst.childs.map(n => n.def.toquery(n)).filter(n => n !== null)];
        if (lst.length === 0) return null;
        const q = lst.length === 1 ? lst[0] : [inst.op, ...lst];
        return id ? [id,inst.eq,q] : q;
    };
    // The "main" ds is the one with the field header. For same-type nests,
    // that is the And/Or selection button, for different-type nests, that's
    // the 'not' button.
    const ds = !id ? andor : inst => new DS({
        list: (src, str, cb) => cb([{id:'='},{id:'!='}]),
        view: o => o.id === '=' ? yes : no,
    }, {
        keep: false, nosearch: true,
        onselect: o => inst.eq = o.id,
    });
    return {ptype, qtype, label, init, toquery, button, ds};
};


const fieldAdd = {};
const fieldList = {};
const fieldSubnest = {};
const andorField = {};

const regType = (t, name, fields) => {
    andorField[t] = nestField(t);
    fieldList[t] = [unknownField, andorField[t], ...fields];
    fieldSubnest[t] = Object.fromEntries(fields.filter(d => d.qtype && d.qtype !== d.ptype).map(d => [d.qtype,d]));
    fieldSubnest[t][''] = name;

    fieldAdd[t] = (() => {
        const ds = new DS({
            list: (src, str, cb) => cb(fieldList[ds._types.at(-1)].filter(d => {
                if (!d.label) return false;
                if (!d.qtype || d.qtype === d.ptype) return true;
                if (ds._types.includes(d.qtype) && ds._types.at(-1) !== d.qtype) return false;
                for (let inst = ds._inst; inst; inst = inst.parent) if (inst.def.qtype !== inst.def.ptype && inst.def.ptype === d.qtype) return false;
                return true;
            }).map((d,i) => ({id:i,d}))),
            view: o => [ o.d.label, o.d.qtype !== o.d.ptype ? ' »' : null ],
        }, {
            width: 150, maxCols: 2, nosearch: true, keep: true,
            header: () => [
                m('div.xsearch_opts', m('strong', 'Add field'), ds._types),
                ds._types.length === 1 ? null : m('div.xsearch_nest', ds._types.map((qt,i) => {
                    const lbl = i ? fieldSubnest[ds._types[i-1]][qt].button : fieldSubnest[qt][''];
                    return i === ds._types.length - 1 ? m('strong', lbl)
                        : m('a[href=#]', { onclick: ev => { ev.preventDefault(); ds._types.splice(i+1); ds.setInput('') } }, lbl)
                }).intersperse(' » ')),
            ],
            onselect: o => {
                if (o.d.qtype !== o.d.ptype) {
                    ds._types.push(o.d.qtype);
                } else {
                    DS.close();
                    let f = instantiateField(o.d);
                    for (let i=ds._types.length-2; i>=0; i--) {
                        const pt = ds._types[i];
                        const qt = ds._types[i+1];
                        const n = instantiateField(fieldSubnest[pt][qt], null);
                        if (!f.def.qtype || f.def.qtype !== f.def.ptype) n.childs = [f];
                        f = n;
                    }
                    ds._inst.childs.push(f);
                }
            },
        });
        return ds;
    })();
};

regType('v', 'VN', [
    nestField('v', 'r', 50, 'Release', 'Rel', 'Has a release that matches these filters', 'Does not have a release that matches these filters'),
    nestField('v', 's', 52, 'Staff', 'Staff', 'Has staff that matches these filters', 'Does not have staff that matches these filters'),
    nestField('v', 'c', 51, 'Character', 'Char', 'Has a character that matches these filters', 'Does not have a character that matches these filters'),
    nestField('v', 'p', 55, 'Developer', 'Dev', 'Has a developer that matches these filters', 'Does not have a developer that matches these filters'),
    langField(2, 'set', DS.ScriptLang, 'Language', 'Language the visual novel is available in', 'L '),
    langField(3, 'eq',  DS.ScriptLang, 'Original language', 'Language the visual novel is originally written in', 'O '),
]);

regType('r', 'Release', [
    nestField('r', 'v', 53, 'Visual Novel', 'VN', 'Linked to a visual novel that matches these filters', 'Not linked to a visual novel that matches these filters'),
    nestField('r', 'p', 55, 'Producer', 'Prod', 'Has a producer that matches these filters', 'Does not have a producer that matches these filters'),
    langField(2, 'set', DS.ScriptLang, 'Language', 'Language the release is available in'),
]),

regType('c', 'Char', [
    nestField('c', 's', 52, 'Voice Actor', 'VA', 'Has a voice actor that matches these filters', 'Does not have a voice actor that matches these filters'),
    nestField('c', 'v', 53, 'Visual Novel', 'VN', 'Linked to a visual novel that matches these filters', 'Not linked to a visual novel that matches these filters'),
    {
        label: 'Role',
        ...setField(2, 'eq', {
            list: (src, str, cb) => cb(vndbTypes.charRole.map(([id,lbl]) => ({id,lbl}))),
            view: o => o.lbl,
            opts: { width: 250, nosearch: true },
        }),
        button: inst => inst.values.size === 0 ? m('small', 'Role') : [
            opFmt(inst.op, true), ' ',
            inst.values.size === 1 ? vndbTypes.charRole.find(r => r[0] === inst.values.keys().next().value)[1] : 'Role ('+inst.values.size+')',
        ],
    },
]);

regType('s', 'Staff', [
    langField(2, 'eq', DS.LocLang, 'Language', 'Primary language of the staff'),
]);

regType('p', 'Producer', [
    langField(2, 'eq', DS.LocLang, 'Language', 'Primary language of the producer'),
]);


const instantiateField = (def, q) => {
    if (!('title' in def)) def.title = def.label;

    const inst = def.init(q);
    if (!inst) return null;
    inst.def = def;
    inst.ds = def.ds(inst);
    if (!('keep' in inst.ds)) inst.ds.keep = true;
    const hd = inst.ds.header;
    inst.ds.header = () => [ fieldHeader(inst), hd ? hd() : null ];
    return inst;
};


const renderField = (inst, par) => {
    inst.parent = par;
    if (!inst.def.qtype) return m(DS.Button, { ds: inst.ds, class: 'field' }, m('span', inst.def.button(inst)));

    const pre = [
        inst.andords ? m(DS.Button, { ds: inst.ds }, opFmt(inst.eq === '=' ? 0 : 2, true), ' ', inst.def.button) : null,
        !inst.andords || inst.childs.length > 1 ? m(DS.Button, { ds: inst.andords || inst.ds }, inst.op ? 'Or' : 'And') : null,
    ];
    const plus = m('button[type=button]', { onclick: function() {
        DS.close(); // So that we can open the dropdown while it is active on another button.
        const ds = fieldAdd[inst.def.qtype];
        ds._inst = inst;
        ds._types = [inst.def.qtype];
        ds.open(this, null);
    }}, '+');

    return inst.childs.find(n => n.def.qtype) ? m('table',
        inst.childs.map((f,i) => m('tr',
            m('td', i === 0 ? pre : null),
            m('td.lines', { class: i === 0 ? 'start' : 'mid' }, m('div'), m('span')),
            m('td', renderField(f, inst)),
        )),
        m('tr', m('td'), m('td.lines.end', m('div'), m('span')), m('td', plus))
    ) : m('table', m('tr',
        m('td', pre, m('small', ' → ')),
        m('td', inst.childs.map(f => renderField(f, inst)), plus),
    ));
};

const fromQuery = (qtype, q) => {
    for(const f of fieldList[qtype].slice().reverse()) {
        const inst = instantiateField(f, q);
        if (!inst) continue;
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
        if (q === null) return '';
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

    let root = fromQuery(data.qtype, data.query || [0]);
    // Root must be an And/Or field, otherwise there's no UI to add/remove fields.
    if (!root.def.qtype || root.def.qtype !== root.def.ptype) {
        const n = instantiateField(andorField[data.qtype], null);
        n.childs = [root];
        root = n;
    }
    // The actual root field is wrapped inside a fake "or" node that is never
    // rendered, so that the branching buttons always have a parent field to
    // work with.
    root = { op: 1, parent: null, childs: [root], def: { qtype: data.qtype, ptype: data.qtype } };

    const view = () => m('div.xsearch',
        m('input[type=hidden][id=f][name=f]', { value: encodeQuery(root.childs[0].def.toquery(root.childs[0])) }),
        renderField(root.childs[0], root),
    );
    return {view};
});
