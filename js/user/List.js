const lblicon = (n, l) => m('abbr', {
    class: 'icon-list-'+(n === -1 ? 'add' : n >= 1 && n <= 6 ? 'l'+n : 'unknown'),
    title: l
});

let widgetParent;
let widgetCur;

const isPublic = obj => obj.labels && obj.labels.find(n => pageVars.labels.find(l => l[0] === n && !l[2]));

const reviewLink = obj =>
    !obj.canreview || obj.vote === null ? null :
        obj.review ? m('a', { href: '/'+obj.review+'/edit' }, ' edit review »')
                   : m('a', { href: '/'+obj.vid+'/addreview' }, ' write a review »');


const statusRender = obj =>
    obj.labels === null ? m('small', 'not on your list') :
    obj._del === false ? [
        m('button[type=button]', { onclick: () => {
            obj._del = new Api('UListDel');
            obj._del.call({vid: obj.vid}, () => {
                delete obj._del;
                obj.labels = null;
                obj.notes = obj.started = obj.finished = '';
                obj.rlist = [];
                widgetCur = null;
                // TODO: remove VN from page if we're on the user's list
            });
        } }, 'Delete from my list'), ' ',
        m('button[type=button]', { onclick: () => delete obj._del }, 'Cancel'),
    ] : obj._del ? obj._del.Status() : [
        isPublic(obj) ? m('span', '👁 Public ') : m('small', 'Private '),
        m(Button.Del, { onclick: () => obj._del = false }),
    ];


const labelRender = obj => {
    const set = (id,c) => {
        if (!obj.labels) obj.labels = [];
        // Unset progress labels when setting another one.
        // TODO: Do this with wish/blacklist as well? Can't find a use case to have both checked...
        if (c && id >= 1 && id <= 4) obj.labels = obj.labels.filter(n => !(n >= 1 && n <= 4));
        if (c) obj.labels.push(id)
        else obj.labels = obj.labels.filter(n => n !== id)
    };

    if (!obj._labelDs) obj._labelDs = new DS({
        list: (src, str, cb) => cb(
            pageVars.labels.filter(l => l[0] !== 7 && l[1].toLowerCase().includes(str.toLowerCase()))
            .anySort(([id,lbl]) => str && !lbl.toLowerCase().startsWith(str.toLowerCase()))
            .map(([id,lbl]) => ({id,lbl}))
            .concat(!str || pageVars.labels.find(l => l[1].toLowerCase() == str.toLowerCase()) ? [] : [{id:-1, lbl: str}])
        ),
        view: l => [
            l.id >= 1 && l.id <= 6 ? lblicon(l.id, l.lbl) : null, ' ',
            l.id > 0 ? l.lbl : [l.lbl, m('small', ' (new label)')],
        ],
    }, {
        width: 300, placeholder: 'Add label...',
        checked: l => obj.labels && obj.labels.includes(l.id),
        onselect: (l,c) => {
            // Adding a new label is tricky business, need to prevent further interaction while loading.
            if (l.id < 0) {
                obj._labelAdd = new Api('UListLabelAdd');
                obj._labelAdd.call({vid: obj.vid, label: l.lbl}, res => {
                    if (!pageVars.labels.find(([id]) => id === res.id))
                        pageVars.labels.push([res.id,l.lbl,res.priv]);
                    set(res.id, true);
                    obj._labelAdd = null;
                });
                obj._labelDs.setInput('');
                DS.close();
                return;
            }

            set(l.id, c);
            if (!obj._labelApi) obj._labelApi = new Api('UListLabelEdit');
            obj._labelApi.call({vid: obj.vid, labels: obj.labels});
        },
    });

    let labels = obj.labels ? obj.labels.filter(n => n !== 7) : [];
    return m(DS.Button, { ds: obj._labelAdd ? null : obj._labelDs },
        !labels.length ? '- select label -' :
            pageVars.labels.filter(l => labels.includes(l[0]))
            .map(l => [ l[0] <= 6 ? lblicon(l[0], l[1]) : null, ' ', l[1] ])
            .intersperse(', '),
        obj._labelApi && obj._labelApi.Status(),
        obj._labelAdd && obj._labelAdd.Status()
    );
};


const voteRender = obj => {
    const valid = s => /^(-|[1-9]|10|[1-9]\.[0-9]|10\.0)$/.test(s);
    if (!obj._voteDs) obj._voteDs = new DS({
        list: (src, str, cb) => cb(
            (str ? [{id:str.replace(/\.$/, '')}] : range(1,10).reverse().map(i => ({id:i})))
            .concat(str === '-' || !obj.vote ? [] : [{id:'-'}])
        ),
        view: ({id}) =>
            id === '-' ? m('em', 'Remove vote') :
            /^(10|[1-9])$/.test(id) ? id + ' (' + vndbTypes.ratings[id-1] + ')' :
            valid(id) ? id : m('b', 'Invalid number'),
    }, {
        width: 180, placeholder: 'Vote (1.0 - 10.0)',
        props: ({id}) => ({ selectable: valid(id) }),
        onselect: ({id}) => {
            if (!obj._voteApi) obj._voteApi = new Api('UListVoteEdit');
            obj._voteApi.call({vid: obj.vid, vote: id});
            obj.vote = id === '-' ? null : id;
            if (id !== '-') {
                if (!obj.labels) obj.labels = [7];
                else obj.labels.push(7);
            } else if (obj.labels)
                obj.labels = obj.labels.filter(n => n !== 7);
        },
    });
    return [
        m(DS.Button, { ds: obj._voteDs }, obj.vote ? obj.vote : '- vote -'),
        obj._voteApi && obj._voteApi.Status(),
    ];
};


const dateRender = (obj,field) => [
    m(RDate, {
        value: obj[field], today: 1, unknown: 1, full: 1, notba: 1, maxyear: new Date().getFullYear(),
        oninput: v => {
            if (!obj['_api'+field]) obj['_api'+field] = new Api('UListDateEdit');
            // XXX: Debounce / save on blur?
            obj['_api'+field].call({ vid: obj.vid, date: v, start: field === 'started' });
            obj[field] = v;
            if (!obj.labels) obj.labels = [];
        },
    }),
    obj['_api'+field] && obj['_api'+field].Status(),
];


const notesRender = obj => {
    const save = () => {
        if (obj._notesLast === obj.notes) return;
        obj._notesLast = obj.notes;
        if (obj._notesTimer) clearTimeout(obj._notesTimer);
        delete obj._notesTimer;
        if (obj.notes.length > 2000) return;
        if (!obj._notesApi) obj._notesApi = new Api('UListVNNotes');
        obj._notesApi.call({ vid: obj.vid, notes: obj.notes });
        m.redraw();
    };
    return [
        m(Input, {
            type: 'textarea', data: obj, field: 'notes', rows: 2, maxlength: 2000,
            oncreate: () => obj._notesLast = obj.notes,
            oninput: () => {
                if (obj._notesTimer) clearTimeout(obj._notesTimer);
                obj._notesTimer = setTimeout(save, 1000);
            },
            onblur: save,
        }),
        obj._notesApi && obj._notesApi.Status()
    ];
};


const rstatusSave = (r, obj) => {
    if (obj && !obj.labels) obj.labels = [];
    if (!r._api) r._api = new Api('UListRStatus');
    r._api.call({rid: r.id, status: r.status}, () => {
        if (obj && r.status === null) obj.rlist = obj.rlist.filter(x => x !== r);
        delete r._api;
    });
};

const rstatusRender = (r, obj) => [
    r._api && r._api.loading() ? (r.status === null ? 'deleting...' : m('span.spinner')) :
    r._api && r._api.error ? m('b', r._api.error) : m(Select, {
        data: r, field: 'status',
        options: vndbTypes.rlistStatus.map((x,i) => [i,x]).concat([[null, '- remove -']]),
        oninput: () => rstatusSave(r, obj),
    }),
];


// TODO: Include play time vote
const widgetRender = obj => {
    if (!obj.full_loading && !obj._releaseDs) obj._releaseDs = new DS(DS.Releases(obj.releases), {
        props: r => ({ selectable: !obj.rlist.find(l => l.id === r.id) }),
        onselect: r => {
            const o = { id: r.id, status: 2 };
            obj.rlist.push(o);
            rstatusSave(o, obj);
        },
    });
    return m('form.invalid-form.ulist-widget',
        { onclick: ev => { if (!$('#ulist-widget-box').contains(ev.target)) widgetCur = null } },
        m('div#ulist-widget-box', obj.full_loading ? obj.full_loading.Status() : [
            m('div.status', statusRender(obj)),
            m('h2', obj.title),
            m('table',
                m('tr', m('td', 'Labels'), m('td.labels', labelRender(obj))),
                m('tr', m('td', 'Vote'), m('td.vote', voteRender(obj), reviewLink(obj))),
                m('tr', m('td', 'Start date'), m('td', dateRender(obj, 'started'))),
                m('tr', m('td', 'Finish date'), m('td', dateRender(obj, 'finished'))),
                m('tr', m('td', 'Notes'), m('td.notes', notesRender(obj))),
            ),
            !obj.releases.length ? null : [
                m('h2', 'Releases'),
                m('table.rel',
                    obj.rlist.map(l => m('tr', {key: l.id},
                        m('td', rstatusRender(l, obj)),
                        m('td', Release(obj.releases.find(r => r.id === l.id))),
                    )),
                    m('tfoot', m('tr', m('td'), m('td[colspan=2]',
                        m(DS.Button, { ds: obj._releaseDs }, '- add release -'),
                    ))),
                ),
            ],
        ]),
    );
};


const widgetOpen = obj => {
    if (!widgetParent) {
        widgetParent = document.createElement('div');
        document.body.appendChild(widgetParent);
        m.mount(widgetParent, { view: () => widgetCur ? widgetRender(widgetCur) : null });
    }
    widgetCur = obj;
    if (!('title' in obj)) {
        obj.full_loading = new Api('UListWidget');
        obj.full_loading.call({vid: obj.vid}, res => { Object.assign(obj, res.results); obj.full_loading = null });
    }
};


widget('UListWidget', { view: vnode => m('span.ulist-widget-icon',
    { onclick: () => widgetOpen(vnode.attrs.data), },
    vnode.attrs.data.labels ? lblicon(
        Math.max(0, ...vnode.attrs.data.labels.filter(n => n >= 1 && n <= 6)),
        vnode.attrs.data.labels.flatMap(n =>
            n === 7 ? [] : [ pageVars.labels.find(([id]) => id === n)[1] ]
        ).join(', ')
    ) : lblicon(-1, 'Add to list')
)});


widget('UListVNPage', initvnode => {
    const view = () => 'hi';
    return {view};
});
