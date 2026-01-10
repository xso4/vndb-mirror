const AND = 0;
const OR = 1;

// For sharing configuration & database object info between fields.
let globalData;


// Field definition members:
//   label         (optional, unlisted when missing)
//   title         (optional, same as label when missing)
//   init          query => instance  (query=null to init an empty field)
//   toquery       instance => query
//   opstyle       supported operators, 'set', 'eq' or 'ord'
//   spoilstyle    enable spoiler setting selector, 'bool', 'lie'
//   ds            instance => new DS(..)
//   button        instance => html
//   nestonly      set for fields that don't make much sense as top-level filter
//   loggedin      requires the user to be logged in
//   ptype/qtype   parent type and query type, only used for nestfields
//   group         only set for special grouping fields, these are never instantiated directly

// Field instance members:
//   ds            DS Instance
//   def           Reference to the field definition
//   parent        Parent field (always a nestfield)
//   focus         Set when the field has just been added
//   ...           Additional field-specific members


const boolField = (id, label, yes, no) => ({
    label,
    init: q => !q ? {op:'='} : q[0] === id ? {op:q[1]} : null,
    toquery: inst => [id,inst.op,1],
    ds: inst => new DS({
        list: (src, str, cb) => cb([{id:'='},{id:'!='}]),
        view: o => o.id === '=' ? yes : no,
    }, { nosearch: true, width: 200, onselect: o => inst.op = o.id }),
    button: inst => inst.op === '=' ? yes : no,
});


// A "set" field can hold a set (or map) of values that are AND or OR'ed together.
// Uses the following field instance members:
//   values:  Set of active values
//   op:      opList.id
//
// For non-trivial fields:
//   id: used for the default toquery and fromquery, unused when those are set.
//   fromq: q => null or {key,op,val,spoil,direct}
//   toq: (key,op,val,inst) => q
const setField = (id, opstyle, source, fromq, toq, defop=0) => {
    if (!fromq) fromq = q => q[0] === id ? {key:q[2], op:q[1]} : null;
    if (!toq) toq = (key,op,val,inst) => [id,op,key];

    const init = q => {
        if (!q) return { values: new Map(), op: defop, spoil: globalData.spoilers, direct: false };
        const lst = q[0] > 1 ? [q] : q.slice(1);
        if (lst.length === 0) return null;
        const inst = { values: new Map() };
        for (const x of lst) {
            const v = fromq(x);
            if (!v) return null;
            inst.values.set(v.key, 'val' in v ? v.val : true);
            v.op = q[0] > 1 ? defop+(v.op === '=' ? 0 : 2)
                 : q[0] === OR ? (v.op === '=' ? 0 : 3) : (v.op === '=' ? 1 : 2);
            for (const f of ['op', 'spoil', 'direct']) {
                if (f in v) {
                    if (!(f in inst)) inst[f] = v[f];
                    else if (inst[f] !== v[f]) return null;
                }
            }
        }
        return inst;
    };

    const toquery = inst => {
        const lst = [...inst.values.entries()].map(([k,v]) => toq(k, inst.op & 2 ? '!=' : '=', v, inst));
        return lst.length === 0 ? null
             : lst.length === 1 ? lst[0]
             : [ inst.op === 0 || inst.op === 3 ? OR : AND, ...lst ];
    };

    const ds = inst => new DS(source, {
        checked: o => inst.values.has(o.id),
        onselect: (o,c) => c ? inst.values.set(o.id,true) : inst.values.delete(o.id),
        uncheckall: () => inst.values.clear(),
    });
    return {opstyle,ds,init,toquery};
};


// Set field for a list of [id,label,butlabel=label] options
const simpleSetField = (id, opstyle, list, label, title, spoilstyle, fromq, toq) => ({
    label, title, spoilstyle,
    ...setField(id, opstyle, {
        list: (src, str, cb) => cb(list.map(([id,lbl]) => ({id,lbl}))),
        view: o => o.lbl,
        opts: { width: 300, nosearch: true }
    }, fromq, toq),
    button: inst => inst.values.size === 0 ? m('small', label) : [
        opFmt(inst.op, true), ' ',
        inst.values.size === 1 ? (v => v[2]||v[1])(list.find(r => r[0] === inst.values.keys().next().value)) : label + ' ('+inst.values.size+')',
    ],
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


const extlinksField = (id, type) => ({
    label: 'External links',
    ...setField(id, 'set', {
        list: (src, str, cb) => cb(vndbTypes
            .extLinks.map(([id,ent,lbl]) => ({id,ent,lbl}))
            .filter(o => o.ent.toLowerCase().includes(type))),
        view: o => o.lbl,
        opts: { width: 210, nosearch: true, maxCols: 2 }
    }),
    button: inst => inst.values.size === 0 ? m('small', 'External links') : [
        opFmt(inst.op, true), ' ',
        inst.values.size === 1 ? vndbTypes.extLinks.find(([id]) => id === inst.values.keys().next().value)[2]
                               : 'Links ('+inst.values.size+')'
    ],
});


const platformField = { // Works for both VNs and releases
    label: 'Platform',
    title: 'Platform availability',
    ...setField(4, 'set', DS.Platforms),
    button: inst => inst.values.size === 0 ? m('small', 'Platform') : [
        opFmt(inst.op, inst.values.size === 1), ' ',
        vndbTypes.platform.map(([v,l]) => inst.values.has(v) ? [ PlatIcon(v), inst.values.size === 1 ? l : null ] : null)
    ],
};


const labelField = {
    label: 'My Labels',
    loggedin: true,
    // Assumption: backend always normalizes to [uid,label]
    ...setField(12, 'set', DS.Labels(pageVars.labels||[]),
        q => q[0] === 12 && typeof q[2] === 'object'
            && q[2][0] === Math.floor(globalData.uid.replace(/^u/, ''))
            && pageVars.labels.find(([id]) => id === q[2][1]) ? {key:q[2][1], op:q[1]} : null
    ),
    button: inst => inst.values.size === 0 ? m('small', 'My Labels') : [
        opFmt(inst.op, true), ' ',
        inst.values.size === 1 ? pageVars.labels.find(([id]) => id === inst.values.keys().next().value)[1]
                               : 'My Labels ('+inst.values.size+')'
    ],
};


// A special case of setField where values need to be searched for.
const searchField = (opstyle, source, label, cache, fmtlst, fmtbut, fromq, toq, defop=0, direct, levels) => {
    const objid = source === DS.Staff ? 'sid' : 'id';
    const inf = id => cache ? globalData[cache].find(x => id === x[objid]) : id;
    const field = setField(null, opstyle, null, fromq, toq, defop);
    field.label = label;
    field.ds = inst => new DS(source, {
        onselect: o => {
            if (cache && !inf(o[objid])) globalData[cache].push(o);
            inst.values.set(o[objid], 0);
        },
        width: 400,
        header: () => [
            direct ? m('div.xsearch_opts', m('span'), m('label',
                m('input[type=checkbox]', { checked: !inst.direct, onclick: ev => inst.direct = !ev.target.checked }),
                ' ', direct
            )) : null,
            m('ul.xsearch_list', [...inst.values.entries()].map(([key,val]) => m('li', {key},
                m(Button.Del, { onclick: () => inst.values.delete(key) }),
                levels ? m(Select, { value: val, oninput: v => inst.values.set(key,v), options: levels }) : null,
                ' ', fmtlst(inf(key)),
            ))),
        ],
    });
    field.button = inst => inst.values.size === 0 ? m('small', label) : [
        opFmt(inst.op, true), ' ',
        inst.values.size === 1 ? fmtbut(inf(inst.values.keys().next().value))
                               : label+' ('+inst.values.size+')'
    ];
    return field;
};

const tagField = (() => {
    const fromq = q => {
        if (q[0] !== 8 && q[0] !== 14) return null;
        const [tag,v] = typeof q[2] === 'number' ? [q[2],0] : q[2];
        const spoil = (v % 3) + ((v % 3) === 2 && v > 16*3 ? 1 : 0);
        const minlevel = Math.floor((v / 3) % 16);
        return {key: 'g'+tag, op: q[1], val: minlevel, spoil, direct: q[0] === 14};
    };
    const toq = (key,op,val,inst) => {
        const tag = Math.floor(String(key).replace(/^g/, ''));
        return [ inst.direct ? 14 : 8, op, inst.spoil === 0 && val === 0 ? tag
            : [tag, (inst.spoil >= 3 ? 2+16*3 : inst.spoil) + val*3] ];
    };
    const fmtlst = o => [m('small', o.id, ':'), m('a[target=_blank]', { href: '/'+o.id }, o.name)];
    const fmtbut = o => [m('small', o.id, ':'), o.name];
    const levels = [
        [ 0,'any' ],[ 1,'0.2+'],[ 2,'0.4+'],[ 3,'0.6+'],[ 4,'0.8+'],
        [ 5,'1.0+'],[ 6,'1.2+'],[ 7,'1.4+'],[ 8,'1.6+'],[ 9,'1.8+'],
        [10,'2.0+'],[11,'2.2+'],[12,'2.4+'],[13,'2.6+'],[14,'2.8+'],[15,'3.0']
    ];
    const field = searchField('set', DS.Tags, 'Tags', 'tags', fmtlst, fmtbut, fromq, toq, 1, 'also match child tags', levels);
    field.spoilstyle = 'lie';
    return field;
})();


const traitField = (() => {
    const fromq = q => {
        if (q[0] !== 13 && q[0] !== 15) return null;
        const [trait,v] = typeof q[2] === 'number' ? [q[2],0] : q[2];
        return {key: 'i'+trait, op: q[1], spoil: v>2?3:v, direct: q[0] === 15};
    };
    const toq = (key,op,val,inst) => {
        const trait = Math.floor(String(key).replace(/^i/, ''));
        return [ inst.direct ? 15 : 13, op, inst.spoil === 0 ? trait : [trait, inst.spoil === 3 ? 5 : inst.spoil] ];
    };
    const fmtlst = o => [m('small', o.id, ': ', o.group_name ? [o.group_name, ' / '] : null), m('a[target=_blank]', { href: '/'+o.id }, o.name)];
    const fmtbut = o => [m('small', o.id, ':'), o.name];
    const field = searchField('set', DS.Traits, 'Traits', 'traits', fmtlst, fmtbut, fromq, toq, 1, 'also match child traits');
    field.spoilstyle = 'lie';
    return field;
})();


const animeField = (() => {
    const fromq = q => q[0] === 13 ? {op:q[1],key:q[2]} : null;
    const toq = (key,op) => [13,op,key];
    const fmt = o => [ m('small', 'a', o.id, ':'), o.title_romaji ];
    return searchField('set', DS.Anime(1), 'Anime', 'anime', fmt, fmt, fromq, toq);
})();


const drmField = (() => {
    const fromq = q => q[0] === 20 ? {op:q[1],key:q[2]} : null;
    const toq = (key,op) => [20,op,key];
    const fmt = o => o;
    return searchField('set', DS.DRM, 'DRM', null, fmt, fmt, fromq, toq);
})();


const engineField = (() => {
    const fromq = q => q[0] === 15 ? {op:q[1],key:q[2]} : null;
    const toq = (key,op) => [15,op,key];
    const fmt = o => o || 'Engine: unknown';
    const source = DS.New(DS.Engines,
        str => str ? null : {id:''},
        o => m('em', 'Unknown / not set')
    );
    return searchField('eq', source, 'Engine', null, fmt, fmt, fromq, toq);
})();


const staffField = (() => {
    const fromq = q => q[0] === 3 ? {op:q[1],key:'s'+q[2]} : null;
    const toq = (key,op) => [3,op,Math.floor(String(key).replace(/^s/, ''))];
    const fmtlst = o => [m('small', o.sid, ':'), m('a[target=_blank]', { href: '/'+o.sid }, o.title)];
    const fmtbut = o => [ m('small', o.sid, ':'), o.title ];
    const field = searchField('eq', DS.Staff, 'Name', 'staff', fmtlst, fmtbut, fromq, toq);
    field.nestonly = true;
    return field;
})();


const producerField = (() => {
    const fromq = q => q[0] === 3 ? {op:q[1],key:'p'+q[2]} : null;
    const toq = (key,op) => [3,op,Math.floor(String(key).replace(/^p/, ''))];
    const fmtlst = o => [m('small', o.id, ':'), m('a[target=_blank]', { href: '/'+o.id }, o.name)];
    const fmtbut = o => [ m('small', o.id, ':'), o.name ];
    const field = searchField('eq', DS.Producers, 'Name', 'producers', fmtlst, fmtbut, fromq, toq);
    field.nestonly = true;
    return field;
})();



const rangeOp = new Map([['=', '='], ['!=','≠'], ['<=','≤'], ['<','<'],['>=','≥'],['>','>']]);
const rangeOpSel = (inst, onlyeq) => m('div', [...rangeOp.entries()].map((op,i) =>
    onlyeq && i > 1 ? null
    : inst.op === op[0] ? m('strong', op[1])
    : m('a[href=#]', { onclick: ev => { ev.preventDefault(); inst.op = op[0] } }, op[1])
));


// defval=[op,value], list=[[id,label],..]
const rangeField = (id, label, defval, unknown, list) => ({
    label,
    init: q => !q ? { op: defval[0], val: defval[1] } : q[0] === id ? { op: q[1], val: q[2] } : null,
    toquery: inst => [id,inst.op,inst.val],
    ds: inst => new DS(null, { width: 300, header: () => m('div.xsearch_range',
        m('div',
            rangeOpSel(inst, inst.val === ''),
            unknown ? m('label',
                m('input[type=checkbox]', { checked: inst.val === '', onclick: ev => {
                    inst.val = ev.target.checked ? '' : defval[1];
                    if (inst.val === '' && inst.op !== '=' && inst.op !== '!=') inst.op = '=';
                    if (inst.val !== '') inst.op = defval[0];
                }}),
                ' unknown'
            ) : null,
        ),
        inst.val === '' ? m('p', label, ' is ', inst.op === '=' ? 'unknown/unset.' : 'known/set.') : m('div',
            m('small', list[0][1]),
            m('strong', list.find(v => v[0] === inst.val)[1]),
            m('small', list[list.length-1][1]),
        ),
        inst.val === '' ? null : m('input[type=range][min=0]', {
            max: list.length-1,
            value: list.findIndex(v => v[0] === inst.val),
            oninput: ev => inst.val = list[ev.target.value][0]
        }),
    )}),
    button: inst => [ label, ' ', rangeOp.get(inst.op), ' ', inst.val === '' ? 'Unknown' : list.find(v => v[0] === inst.val)[1] ],
});


const rdateField = (() => { // works for VNs and releases
    const onlyeq = d => d === 99999999 || d === 0;
    const id = 7;
    const init = q => {
        if (!q) return {op:'<', fuzzy:true, date: 1};
        if (q[0] === id) {
            const e = RDate.expand(q[2]);
            return {op:q[1], date: q[2], fuzzy: e.y === 0 || e.y === 9999 || e.d !== 99 || q[1] === '>' || q[1] === '<='};
        }
        // Fuzzy range match (only recognizes filters created by 'toquery' below)
        if (q[0] > 1 || q.length !== 3 || q[1][0] !== id || q[2][0] !== id) return null;
        const op = q[0] === AND && q[1][1] === '>=' && q[2][1] === '<=' ? '=' :
                   q[0] === OR  && q[1][1] === '<'  && q[2][1] === '>'  ? '!=' : null;
        const se = RDate.expand(q[1][2]);
        const ee = RDate.expand(q[2][2]);
        return op && se.y === ee.y && (ee.m < 99 || se.m === 1) && se.d === 1 && ee.d === 99 ? {op,date:q[2][2],fuzzy:true} : null;
    };
    const toquery = inst => {
        const e = RDate.expand(inst.date);
        if (!inst.fuzzy || e.y === 0 || e.y === 9999 || e.d !== 99)
            return [id, inst.op, inst.date];
        // Inexact inst.date represents the END of the month/year, for fuzzy matching we also need the start.
        const start = RDate.compact({y:e.y, m: e.m === 99 ? 1 : e.m, d:1});
               // Fuzzy (in)equality turns into a date range
        return inst.op === '='  ? [AND, [id,'>=',start],[id,'<=',inst.date]] :
               inst.op === '!=' ? [OR,  [id,'<', start],[id,'>', inst.date]] :
               // Fuzzy >= and < just need the date adjusted to the correct boundary
               inst.op === '>=' ? [id,'>=',start] :
               inst.op === '<'  ? [id,'<', start] : [id,inst.op,inst.date];
    };
    const ds = inst => new DS(null, { header: () => m('div.xsearch_range',
        m('div', rangeOpSel(inst, onlyeq(inst.date))),
        m(RDate, { value: inst.date, unknown: true, today: true, oninput: v => {
            if (onlyeq(v) && inst.op !== '=' && inst.op !== '!=') inst.op = '=';
            inst.date = v;
        }}),
        onlyeq(inst.date) || RDate.expand(inst.date).d !== 99 ? null : m('p',
            m('label',
                m('input[type=checkbox]', { checked: inst.fuzzy, oninput: ev => inst.fuzzy = ev.target.checked }),
                ' Fuzzy matching'
            ),
            m('br'),
            m('small',
                'Without fuzzy matching, partial dates always match ', m('em', 'after'), ' the last date of the chosen time period, ',
                'e.g. "< 2010-10" also matches anything released in that month while "= 2010-10" only matches releases for which we don\'t know the exact date.',
                ' Fuzzy match adjusts the query to do what you mean.'
            ),
        ),
    )});
    const button = inst => [ rangeOp.get(inst.op), ' ', RDate.fmt(RDate.expand(inst.date)) ];
    return {label: 'Release date', init, toquery, ds, button};
})();


const resolutionField = (() => {
    const init = q => !q ? {op:'=', aspect: false, x: 0, y: 0} :
        q[0] === 8 ? {op:q[1], aspect: false, x: q[2][0], y: q[2][1] } :
        q[0] === 9 ? {op:q[1], aspect: true, x: q[2][0], y: q[2][1] } : null;
    const toquery = inst => [inst.aspect?9:8, inst.op, [inst.x,inst.y]];
    const source = DS.New(DS.Resolutions,
        str => resoParse(str) ? {id:str} : null,
        o => m('em', o.id ? o.id : 'Unknown'),
    );
    const ds = inst => new DS(source, {
        width: 300,
        header: () => m('div.xsearch_range', m('div',
            rangeOpSel(inst, inst.x === 0),
            inst.op === '=' || inst.op === '!=' ? null : m('label',
                m('input[type=checkbox]', { checked: inst.aspect, oninput: ev => inst.aspect = ev.target.checked }),
                ' match aspect ratio'
            ),
        )),
        onselect: o => {
            const r = resoParse(o.id)||[0,0];
            inst.x = r[0];
            inst.y = r[1];
            inst.ds.setInput(o.id);
        },
    });
    const butlbl = inst => inst.x === 0 ? 'Unknown resolution' : resoFmt(inst.x, inst.y).replace('x', inst.aspect ? ':' : 'x');
    const button = inst => [ rangeOp.get(inst.op), ' ', butlbl(inst) ];
    return {label: 'Resolution', init, toquery, ds, button};
})();


const birthdayField = (() => {
    const init = q => !q ? {op:'=', month:0, day: 0} : q[0] === 14 ? {op:q[1], month: q[2][0], day: q[2][1]} : null;
    const toquery = inst => [14,inst.op,[inst.month,inst.month === 0 ? 0 : inst.day]];
    const ds = inst => new DS(null, { width: 200, header: () => m('div.xsearch_range',
        m('div', rangeOpSel(inst, true)),
        m(Select, { data: inst, field: 'month', options: [[0,'Unknown']].concat(RDate.months.map((v,i) => [i+1,i+1+' ('+v+')'])) }),
        inst.month === 0 ? null : m(Select, { data: inst, field: 'day', options: range(0,31).map(v => [v, v === 0 ? '- day -' : v]) }),
    )});
    const button = inst => [
        opFmt(inst.op === '=' ? 0 : 2,true), ' ',
        inst.month === 0 ? 'Birthday unknown' : RDate.months[inst.month-1],
        ' ', inst.day === 0 ? null : inst.day
    ];
    return {label: 'Birthday', init, toquery, ds, button};
})();


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


const spoilList = [
    {id: 0, icon: () => [m('small','SPL')  ], bool: true,  lie: true, lbl: 'Exclude spoilers'},
    {id: 1, icon: () => ['SPL'             ], bool: false, lie: true, lbl: 'Minor spoilers'},
    {id: 2, icon: () => [m('b', 'SPL')     ], bool: true,  lie: true, lbl: 'Major spoilers'},
    {id: 3, icon: () => [m('b', 'SPL'),'-l'], bool: false, lie: true, lbl: 'Major spoilers (exclude lies)'},
];

const spoilDs = new DS({
    list: (src, str, cb) => cb(spoilList.filter(o => o[spoilDs._inst.def.spoilstyle])),
    view: o => [ o.icon(), ': ', o.lbl ],
}, {
    nosearch: true, keep: true,
    header: () => fieldHeader(spoilDs._inst, 2),
    onselect: o => {
        spoilDs._inst.spoil = o.id;
        spoilDs._inst.ds.open(spoilDs.opener);
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
        inst.def.spoilstyle ? m('button[type=button]', { onclick: () => {
            if (tab === 2) inst.ds.open(spoilDs.opener);
            else {
                spoilDs.width = $('#ds').offsetWidth;
                spoilDs._inst = inst;
                spoilDs.open(inst.ds.opener);
            }
        }}, spoilList.find(x => x.id === inst.spoil).icon()) : null,
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
            const newpar = instantiateField(types[inst.parent.def.qtype].andor, null);
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


const types = {}; // v: { name, deffields, fields, add, andor, $x: subnestfield }

const regType = (t, name, deffields, fields) => {
    types[t] = Object.fromEntries(fields.filter(d => d.qtype && d.qtype !== d.ptype).map(d => [d.qtype,d]));
    types[t].name = name;
    types[t].deffields = deffields;
    types[t].andor = nestField(t);
    types[t].fields = [unknownField, types[t].andor, ...fields];
    types[t].add = (() => {
        const ds = new DS({
            list: (src, str, cb) => {
                const tail = ds._types.at(-1);
                const fields = typeof tail === 'object' ? tail.fields : types[tail].fields;
                cb(fields.filter(d => {
                    if (d.group) return true;
                    if (!d.label) return false;
                    if (d.nestonly && ds._types.length === 1) return false;
                    if (d.loggedin && !globalData.uid) return false;
                    if (!d.qtype || d.qtype === d.ptype) return true;
                    if (ds._types.includes(d.qtype) && ds._types.at(-1) !== d.qtype) return false;
                    for (let inst = ds._inst; inst; inst = inst.parent) if (inst.def.qtype !== inst.def.ptype && inst.def.ptype === d.qtype) return false;
                    return true;
                }).map((d,i) => ({id:i,d})));
            },
            view: o => [ o.d.group || o.d.label, o.d.group || o.d.qtype !== o.d.ptype ? ' »' : null ],
        }, {
            width: 150, maxCols: 2, nosearch: true, keep: true,
            header: () => [
                m('div.xsearch_opts', m('strong', 'Add field')),
                ds._types.length === 1 ? null : m('div.xsearch_nest', ds._types.map((qt,i) => {
                    const lbl = !i ? types[qt].name : typeof qt === 'object' ? qt.group : types[ds._types[i-1]] ? types[ds._types[i-1]][qt].button : types[qt].name;
                    return i === ds._types.length - 1 ? m('strong', lbl)
                        : m('a[href=#]', { onclick: ev => { ev.preventDefault(); ds._types.splice(i+1); ds.setInput('') } }, lbl)
                }).intersperse(' » ')),
            ],
            onselect: o => {
                if (o.d.group) {
                    ds._types.push(o.d);
                } else if (o.d.qtype !== o.d.ptype) {
                    ds._types.push(o.d.qtype);
                } else {
                    DS.close();
                    let f = instantiateField(o.d);
                    f.focus = true;
                    for (let i=ds._types.length-2; i>=0; i--) {
                        const pt = ds._types[i];
                        const qt = ds._types[i+1];
                        if (typeof qt === 'object') continue;
                        const n = instantiateField(types[pt][qt], null);
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

regType('v', 'VN', [ 'Language', 'Original language', 'Platform', 'Tags' ], [
    nestField('v', 'r', 50, 'Release', 'Rel', 'Has a release that matches these filters', 'Does not have a release that matches these filters'),
    nestField('v', 's', 52, 'Staff', 'Staff', 'Has staff that matches these filters', 'Does not have staff that matches these filters'),
    nestField('v', 'c', 51, 'Character', 'Char', 'Has a character that matches these filters', 'Does not have a character that matches these filters'),
    nestField('v', 'p', 55, 'Developer', 'Dev', 'Has a developer that matches these filters', 'Does not have a developer that matches these filters'),
    langField(2, 'set', DS.ScriptLang, 'Language', 'Language the visual novel is available in', 'L '),
    langField(3, 'eq',  DS.ScriptLang, 'Original language', 'Language the visual novel is originally written in', 'O '),
    platformField,
    tagField,
    labelField,
    { ...boolField(65, 'My List', 'On my list', 'Not on my list'), loggedin: true },
    simpleSetField(5, 'eq', vndbTypes.vnLength, 'Length', 'Length (estimated play time)'),
    simpleSetField(66, 'eq', vndbTypes.devStatus, 'Dev status', 'Development status'),
    rdateField,
    rangeField(10, 'Rating', ['>=', 40], false, range(10, 100).map(v => [v,v/10])),
    rangeField(11, '# Votes', ['>=', 10], false, [ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100, 200, 300, 400, 500, 600, 700, 800, 900, 1000, 2000, 3000, 4000, 5000 ].map(v => [v,v])),
    animeField,
    boolField(61, 'Has description', 'Has description',    'No description'),
    boolField(62, 'Has anime',       'Has anime relation', 'No anime relation'),
    boolField(63, 'Has screenshot',  'Has screenshot(s)',  'No screenshot(s)'),
    boolField(64, 'Has review',      'Has review(s)',      'No review(s)'),
]);

const aniFlags = (prefix,cut) => [['', 'Unknown']].concat(cut ? [] : [['no', 'Not animated']]).concat(
        [['na', 'Not applicable'], ['hand', 'Hand drawn'], ['vect', 'Vectorial'], ['3d', '3D'], ['live', 'Live action']]
    ).map(([id,lbl]) => [id,lbl,prefix+lbl]);

regType('r', 'Release', [ 'Language', 'Platform', 'Type' ], [
    nestField('r', 'v', 53, 'Visual Novel', 'VN', 'Linked to a visual novel that matches these filters', 'Not linked to a visual novel that matches these filters'),
    nestField('r', 'p', 55, 'Producer', 'Prod', 'Has a producer that matches these filters', 'Does not have a producer that matches these filters'),
    langField(2, 'set', DS.ScriptLang, 'Language', 'Language the release is available in'),
    platformField,
    simpleSetField(16, 'eq', vndbTypes.releaseType, 'Type'),
    boolField(61, 'Patch',         'Patch to another release', 'Standalone release'),
    boolField(62, 'Freeware',      'Freeware',                 'Non-free'),
    boolField(66, 'Erotic scenes', 'Has erotic scenes',        'No erotic scenes'),
    boolField(64, 'Uncensored',    'Uncensored (no mosaic)',   'Censored (or no erotic content to censor)'),
    boolField(65, 'Official',      'Official',                 'Unofficial'),
    rdateField,
    resolutionField,
    rangeField(10, 'Age rating', [ '<', 13 ], true, vndbTypes.ageRating),
    simpleSetField(11, 'set', [['', 'Unknown', 'Medium: Unknown']].concat(vndbTypes.medium.map(m => [m[0],m[1]])), 'Medium'),
    simpleSetField(12, 'eq', vndbTypes.voiced.map((v,i) => [i,v]), 'Voiced'),
    { group: 'Animation', fields: [
        simpleSetField(14, 'eq', vndbTypes.animated.map((v,i) => [i,v,'Story: '+v]), 'Story (general)', 'Story animation'),
        simpleSetField(70, 'eq', aniFlags('S sprites: '), 'Story: sprites', 'Story Sprite Animation'),
        simpleSetField(71, 'eq', aniFlags('S CG: '), 'Story: CGs', 'Story CG Animation'),
        simpleSetField(72, 'eq', aniFlags('Cutscene: ', 1), 'Cutscenes', 'Cutscene Animation'),
        simpleSetField(75, 'eq', [['', 'Unknown', 'Backgr effects: unknown'], [0, 'No background effects'], [1, 'Animated background effects']], 'Background effects'),
        simpleSetField(13, 'eq', vndbTypes.animated.map((v,i) => [i,v,'Ero: '+v]), 'Ero (general)', 'Ero animation'),
        simpleSetField(73, 'eq', aniFlags('E sprites: '), 'Ero: sprites', 'Ero Sprite Animation'),
        simpleSetField(74, 'eq', aniFlags('E CG: '), 'Ero: CGs', 'Ero CG Animation'),
        simpleSetField(76, 'eq', [['', 'Unknown', 'Facial ani: unknown'], [0, 'No facial animation'], [1, 'Lip movement and/or eye blink']], 'Facial animation'),
    ]},
    engineField,
    drmField,
    extlinksField(19, 'r'),
    simpleSetField(67, 'set', [['', 'No image']].concat(vndbTypes.releaseImageType), 'Has image'),
    { ...simpleSetField(18, 'eq', vndbTypes.rlistStatus.map((v,i) => [i,v,i===0?'List: unknown':v]), 'My List'), loggedin: true },
]),

regType('c', 'Char', [ 'Role', 'Sex', 'Traits' ], [
    nestField('c', 's', 52, 'Voice Actor', 'VA', 'Has a voice actor that matches these filters', 'Does not have a voice actor that matches these filters'),
    nestField('c', 'v', 53, 'Visual Novel', 'VN', 'Linked to a visual novel that matches these filters', 'Not linked to a visual novel that matches these filters'),
    simpleSetField(2, 'eq', vndbTypes.charRole, 'Role'),
    rangeField(12, 'Age', ['>=', 17], true, range(0, 121).map(v => [v,v === 1 ? '1 year' : v+' years'])),
    birthdayField,
    simpleSetField(null, 'eq', vndbTypes.charSex.map(([k,v]) => [k,v,k===''?'Sex: '+v:v]),
        'Sex', null, 'bool',
        q => q[0] === 4 || q[0] === 5 ? {key:q[2], op:q[1], spoil: q[0]===4?0:2} : null,
        (key,op,val,inst) => [inst.spoil ? 5 : 4, op, key]
    ),
    simpleSetField(null, 'eq', vndbTypes.charGender.map(([k,v]) => [k,v,k===''?'Gender: '+v:v]),
        'Gender', null, 'bool',
        q => q[0] === 16 || q[0] === 17 ? {key:q[2], op:q[1], spoil: q[0]===16?0:2} : null,
        (key,op,val,inst) => [inst.spoil ? 17 : 16, op, key]
    ),
    traitField,
    simpleSetField(3, 'eq', vndbTypes.bloodType.map(([k,v]) => [k,v,'Blood type: '+v]), 'Blood type'),
    rangeField(6, 'Height', ['>=',150], true, range(1, 300).map(v => [v,v+'cm'])),
    rangeField(7, 'Weight', ['>=',60], true, range(0, 400).map(v => [v,v+'kg'])),
    rangeField(8, 'Bust', ['>=',40], true, range(20,120).map(v => [v,v+'cm'])),
    rangeField(9, 'Waist', ['>=',40], true, range(20,120).map(v => [v,v+'cm'])),
    rangeField(10, 'Hips', ['>=',40], true, range(20,120).map(v => [v,v+'cm'])),
    rangeField(11, 'Cup size', ['>=','B'], true, vndbTypes.cupSize.slice(1)),
]);

regType('s', 'Staff', [ 'Language', 'Type', 'Gender', 'Role' ], [
    staffField,
    langField(2, 'eq', DS.LocLang, 'Language', 'Primary language of the staff'),
    simpleSetField(7, 'eq', vndbTypes.staffType, 'Type', 'Staff type'),
    simpleSetField(4, 'eq', [['','Unknown','Gender: unknown'],['m','Male'],['f','Female']], 'Gender'),
    simpleSetField(5, 'set', [['seiyuu', 'Voice actor']].concat(vndbTypes.creditType), 'Role'),
    extlinksField(6, 's'),
]);

regType('p', 'Producer', [ 'Language', 'Type' ], [
    producerField,
    langField(2, 'eq', DS.LocLang, 'Language', 'Primary language of the producer'),
    simpleSetField(4, 'eq', vndbTypes.producerType, 'Type'),
    extlinksField(5, 'p'),
]);


const instantiateField = (def, q) => {
    if (!def.title) def.title = def.label;

    if (def.loggedin && !globalData.uid) return null;
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
    if (!inst.def.qtype) return m(DS.Button, {
            ds: inst.ds, class: 'field',
            oncreate: v => { if (inst.focus) { delete inst.focus; inst.ds.open(v.dom) } },
        }, m('span', inst.def.button(inst)));

    const pre = [
        inst.andords ? m(DS.Button, { ds: inst.ds }, opFmt(inst.eq === '=' ? 0 : 2, true), ' ', inst.def.button) : null,
        !inst.andords || inst.childs.length > 1 ? m(DS.Button, { ds: inst.andords || inst.ds }, inst.op ? 'Or' : 'And') : null,
    ];
    const plus = m('button[type=button]', { onclick: function() {
        DS.close(); // So that we can open the dropdown while it is active on another button.
        const ds = types[inst.def.qtype].add;
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
    for(const f of types[qtype].fields.slice().reverse()) {
        if (f.group) {
            for (const sf of f.fields) {
                const inst = instantiateField(sf, q);
                if (inst) return inst;
            }
        } else {
            const inst = instantiateField(f, q);
            if (inst) return inst;
        }
    }
};

const encodeQuery = (() => {
    const alpha = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_-";
    const esc = new Map(" !\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~".split('').map((c,i) => [c,i]));
    // XXX: Bit silly to do this mapping when we can work directly with the integers.
    const ops = new Map([['=',0], ['!=',1], ['>=',2], ['>', 3], ['<=', 4], ['<', 5]]);
    const eint = v => {
        if (!String(v).match(/^[0-9]+$/)) return null;
        const n = parseInt(v, 10);
        if (n !== parseFloat(v)) return null;
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
        if (typeof q[2] === 'object' && q[2].length === 2 && String(q[2][1]).match(/^[0-9]+$/)) return r(5) + eint(q[2][0]) + eint(q[2][1]);
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


const normalizeRoot = (t, root) => {
    // Root must be an And/Or field, otherwise there's no UI to add/remove fields.
    if (!root.def.qtype || root.def.qtype !== root.def.ptype) {
        const n = instantiateField(types[t].andor, null);
        n.childs = [root];
        root = n;
    }

    // Instantiate some default fields when applicable
    const rootFields = new Map();
    for (const f of root.childs) {
        if (!types[t].deffields.includes(f.def.label)) return root;
        if (rootFields.has(f.def.label)) return root;
        rootFields.set(f.def.label, f);
    }
    root.childs = types[t].deffields.map(n => rootFields.has(n)
        ? rootFields.get(n)
        : instantiateField(types[t].fields.find(x => x.label === n), null));
    return root;
};


widget('AdvSearch', initvnode => {
    const data = initvnode.attrs.data;
    // We currently only ever have a single instance of this widget on a page,
    // so can keep this simple.
    globalData = data;

    let root = normalizeRoot(data.qtype, fromQuery(data.qtype, data.query || [0]));

    // The actual root field is wrapped inside a fake "or" node that is never
    // rendered, so that the branching buttons always have a parent field to
    // work with.
    root = { op: 1, parent: null, childs: [root], def: { qtype: data.qtype, ptype: data.qtype } };

    const encode = () => encodeQuery(root.childs[0].def.toquery(root.childs[0]));
    const initial = encode();

    let saveLoad = null;
    const dsHeader = () => m('div.xsearch_range', m('div',
        [['Save', dsSave], ['Load', dsLoad], ['Delete', dsDel], ['Default', dsDefault]].map(([lbl,ds]) =>
         ds === saveLoad ? m('strong', lbl) : m('a[href=#]', { onclick: ev => { ev.preventDefault(); const o = saveLoad.opener; saveLoad = ds; ds.open(o) } }, lbl)
    )));
    const savedSrc = { list: (src, str, cb) => {
        const lst = data.saved.filter(o => o.id && o.id.toLowerCase().includes(str.toLowerCase()));
        cb((str && !lst.find(o => o.id === str) ? [{id:str,n:1}] : []).concat(lst));
        dsSave.selId = null;
    }, view: o => o.id.length > 50 ? m('b', 'Input too long') : [ o.id, o.n ? m('small', ' (new filter)') : null ] };

    const dsLoad = new DS(savedSrc, {
        width: 300, nosearch: true,
        header: () => [
            dsHeader(),
            data.saved.length === 0 ? m('p', m('em', 'No saved filters.')) :
            encode() !== initial ? m('p', m('em', 'Unsaved changes to your current filters will be lost when loading a saved filter.')) : null,
        ],
        onselect: o => { if (o.id) { $('#f').value = o.query; $('#f').form.submit(); } },
    });

    // God, this UI is awkward.
    const saveApi = new Api('AdvSearchSave');
    const saveV = {v:''};
    const dsSave = new DS(savedSrc, { nosearch: false, keep: true, width: 300,
        header: () => [
            dsHeader(),
            encode() === '' ? m('p', m('em', 'Nothing to save.')) : m('div.xsearch_opts',
                m('div', saveApi.Status()),
                m('button[type=button]', {
                    class: saveApi.loading() || !dsSave.input ? 'invisible' : null,
                    onclick: () => saveApi.call({name: dsSave.input, qtype: data.qtype, query: encode()}, () => {
                        DS.close();
                    }),
                }, 'Save'),
            ),
        ],
        onselect: o => dsSave.setInput(o.id),
    });

    const todel = new Set();
    const delApi = new Api('AdvSearchDel');
    const dsDel = new DS(savedSrc, {
        width: 300, nosearch: true,
        header: () => [
            dsHeader(),
            delApi.loading() || delApi.error ? delApi.Status() : m('div.xsearch_opts',
                todel.size, ' filter', todel.size === 1 ? null : 's', ' selected.',
                m('button[type=button]', {
                    class: todel.size > 0 ? null : 'invisible',
                    onclick: () => {
                        if (todel.size === 0) return;
                        delApi.call({qtype: data.qtype, name: [...todel.keys()]});
                        data.saved = data.saved.filter(o => !todel.has(o.id));
                        todel.clear();
                        dsDel.setInput('');
                    }
                }, 'Delete selected'),
            ),
        ],
        checked: o => todel.has(o.id),
        onselect: (o,c) => c ? todel.add(o.id) : todel.delete(o.id),
    });

    let defquery = data.saved.find(o => !o.id);
    if (defquery) defquery = defquery.query;
    const dsDefault = new DS(null, { width: 300, header: () => [
        dsHeader(),
        m('p', data.qtype === 'v' ? [
                'You can set a default filter that is automatically applied to most listings on the site,',
                ' including the "Random visual novel" button, lists on the homepage, tag pages, etc.',
                ' This feature is mainly useful to filter out tags, languages or platforms that you are not interested in seeing.',
           ] : data.qtype === 'r' ? [
                'You can set a default filter that is automatically applied to this release browser and the listings on the homepage.',
                ' This feature is mainly useful to filter out tags, languages or platforms that you are not interested in seeing.',
           ] : 'You can set a default filter that is automatically applied when you open this listing.'
        ),
        m('p.center',
            delApi.Status(), saveApi.Status(), m('br'),
            defquery ? [
                m('button[type=button]',
                    { onclick: () => { $('#f').value = defquery; $('#f').form.submit(); } },
                    'Load my default filters'
                ),
                m('br'), m('br'),
                m('button[type=button]',
                    { onclick: () => delApi.call({qtype: data.qtype, name: ['']}, () => defquery = null) },
                    'Reset my default filters'
                )
            ] : m('p', "You don't have a default filter set."),
            encode() === '' ? null : m('button[type=button]',
                { onclick: () => saveApi.call({qtype: data.qtype, name: '', query: encode()}, () => defquery = encode()) },
                'Save current filters as default',
            ),
        ),
    ]});

    const view = () => m('div.xsearch',
        data.uid ? m('button[type=button]', { onclick: function() {
            if (!saveLoad) saveLoad = data.saved.length > 0 && encode() === initial ? dsLoad : dsSave;
            saveLoad.open(this)
        } }, m(Icon.Save)) : null,
        m('input[type=hidden][id=f][name=f]', { value: encode() }),
        renderField(root.childs[0], root),
    );
    return {view};
});
