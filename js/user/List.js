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
                delete obj._expand;
                obj.labels = obj.vote = null;
                obj.notes = obj.started = obj.finished = '';
                obj.rlist = [];
                widgetCur = null;
                // remove from listing if we're on the user's list
                const e = $('#ulist_vid_'+obj.vid);
                if (e) e.parentNode.removeChild(e);
            });
        } }, 'Delete from my list'), ' ',
        m('button[type=button]', { onclick: () => delete obj._del }, 'Cancel'),
    ] : obj._del ? obj._del.Status() : [
        isPublic(obj) ? m('span', '👁 Public ') : m('small', 'Private '),
        m(Button.Del, { onclick: () => obj._del = false }),
    ];


const labelRender = (obj, empty='- select label -', icons=1) => {
    const set = (id,c) => {
        if (!obj.labels) obj.labels = [];
        // Unset progress labels when setting another one.
        // TODO: Do this with wish/blacklist as well? Can't find a use case to have both checked...
        if (c && id >= 1 && id <= 4) obj.labels = obj.labels.filter(n => !(n >= 1 && n <= 4));
        if (c) obj.labels.push(id)
        else obj.labels = obj.labels.filter(n => n !== id)
    };

    if (!obj._labelDs) {
        const src = DS.Labels(pageVars.labels.filter(l => l[0] !== 7));
        obj._labelDs = new DS({...src,
            list: (x, str, cb) => src.list(x, str, lst => {
                if (str && pageVars.labels.length < 250 && !lst.find(o => o.lbl.toLowerCase() === str.toLowerCase())) lst.push({id:-1, lbl: str});
                cb(lst);
            }),
            view: obj => [ src.view(obj), obj.id < 0 ? m('small', [...obj.lbl].length >= 50 ? ' (too long)' : ' (new label)') : null ],
        }, {
            placeholder: 'Add label...',
            checked: l => obj.labels && obj.labels.includes(l.id),
            onselect: (l,c) => {
                // Adding a new label is tricky business, need to prevent further interaction while loading.
                if (l.id < 0) {
                    if ([...l.lbl].length >= 50) return;
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
    }

    let labels = obj.labels ? obj.labels.filter(n => n !== 7) : [];
    return m(DS.Button, { ds: obj._labelAdd ? null : obj._labelDs },
        !labels.length ? empty :
            pageVars.labels.filter(l => labels.includes(l[0]))
            .map(l => [ icons && l[0] <= 6 ? labelIcon(l[0], l[1]) : null, ' ', l[1] ])
            .intersperse(', '),
        obj._labelApi && obj._labelApi.Status(),
        obj._labelAdd && obj._labelAdd.Status()
    );
};


const voteRender = (obj, empty) => {
    const valid = s => /^(-|[1-9]|10|[1-9]\.[0-9]|10\.0)$/.test(s);
    if (!obj._voteDs) obj._voteDs = new DS({
        list: (src, str, cb) => {
            obj._voteDs.selId = null; /* Do not remember selection when changing input */
            cb((str ? [{id:str.replace(/\.$/, '')}] : range(1,10).reverse().map(i => ({id:i})))
                .concat(str === '-' || !obj.vote ? [] : [{id:'-'}]))
        },
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
        m(DS.Button, { ds: obj._voteDs },
            obj._voteApi && obj._voteApi.loading() ? m('span.spinner')
            : obj.vote ? obj.vote : empty || '- vote -'
        ),
        obj._voteApi && obj._voteApi.error && m('b', obj._voteApi.error),
    ];
};


const dateRender = (obj,field) => [
    m(RDate, {
        value: obj[field], today: 1, unknown: 1, full: 1, notba: 1, maxyear: new Date().getFullYear(),
        oninput: v => {
            if (v === 1) v = (d => d.getFullYear()*10000 + (d.getMonth()+1)*100 + d.getDate())(new Date);
            if (!obj['_api'+field]) obj['_api'+field] = new Api('UListDateEdit');
            // XXX: Debounce / save on blur?
            obj['_api'+field].call({ vid: obj.vid, date: v, start: field === 'started' });
            obj[field] = v;
            if (!obj.labels) obj.labels = [];

            // Update the date in grid & card view
            const e = $('#ulist_'+field+'_'+obj.vid);
            if (e) e.innerText = v ? RDate.fmt(RDate.expand(v)) : '-';
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
        if (!obj.labels) obj.labels = [];
        obj._notesApi.call({ vid: obj.vid, notes: obj.notes });
        m.redraw();

        const e = $('#ulist_notes_'+obj.vid);
        if (e) e.innerText = obj.notes;
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

const rstatusRender = (r, obj, empty) => [
    r._api && r._api.loading() ? (r.status === null ? 'deleting...' : m('span.spinner')) :
    r._api && r._api.error ? m('b', r._api.error) : m(Select, {
        data: r, field: 'status',
        options: vndbTypes.rlistStatus.map((x,i) => [i,x]).concat([[null, r.status === null && empty ? empty : '- remove -']]),
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
                !obj.canvote ? null :
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


// Connect multiple instances of the same VN together.
if (pageVars && pageVars.widget) {
    const vids = {};
    [ 'UListWidget', 'UListVote', 'UListLabels', 'UListStartDate', 'UListFinishDate' ].forEach(w => {
        pageVars.widget[w] && pageVars.widget[w].forEach(o => {
            if (!vids[o[1].vid]) vids[o[1].vid] = o[1];
            else {
                Object.assign(vids[o[1].vid], o[1]);
                o[1] = vids[o[1].vid];
            }
        });
    });
}


widget('UListWidget', { view: vnode => [
    m('abbr.ulist-widget-icon',
        { onclick: () => widgetOpen(vnode.attrs.data), },
        vnode.attrs.data.labels ? labelIcon(
            Math.max(0, ...vnode.attrs.data.labels.filter(n => n >= 1 && n <= 6)),
            vnode.attrs.data.labels.flatMap(n => {
                const l = pageVars.labels.find(([id]) => id === n);
                return n === 7 || !l ? [] : [ l[1] ];
            }).join(', ')
        ) : labelIcon(-1, 'Add to list'),
        vnode.attrs.oldContents.length === 1 ? null : (rlist =>
            rlist ? ((total, st) =>
                total > 0
                ? m('span', {
                    class: (total && st[2] === total ? ['done'] : st[2] < total ? ['todo'] : [])
                           .concat(st.flatMap((s,i) => s === 0 ? [] : ['rlist_'+i])).join(' '),
                    title: st.flatMap((s,i) => s === 0 ? [] : [vndbTypes.rlistStatus[i]+' ('+s+')']).join(', '),
                  }, ' ', st[2], '/', total)
                : null
            )(rlist.length, rlist.reduce((a,r) => { a[r.status]++; return a }, [0,0,0,0,0]))
            : m.trust(vnode.attrs.oldContents[1].outerHTML)
        )(vnode.attrs.data.rlist)
    ),
]});


widget('UListVNPage', initvnode => {
    const obj = initvnode.attrs.data;
    obj._expand = obj.notes !== '' || obj.started !== 0 || obj.finished !== 0;
    const expandbut = () => m('a[href=#]', { onclick: ev => { ev.preventDefault(); obj._expand = !obj._expand } }, '💬');
    const wide = {colspan: obj.canvote ? 1 : 2};
    const view = () => m('form.invalid-form.ulistvn',
        m('span', statusRender(obj)),
        m('strong', 'User options'),
        m('table.compact',
            m('tr.odd',
                m('td.key', 'My labels'),
                m('td.labels', labelRender(obj)),
                obj.canvote ? null : m('td', expandbut()),
            ),
            obj.canvote ? m('tr', m('td', 'My vote'), m('td.vote',
                voteRender(obj),
                ' ', expandbut(),
                reviewLink(obj),
            )) : null,
            obj._expand ? [
                m('tr',
                    m('td', 'Notes'),
                    m('td.notes', wide, notesRender(obj)),
                ),
                m('tr', m('td', 'Start date'), m('td', wide, dateRender(obj, 'started'))),
                m('tr', m('td', 'Finish date'), m('td', wide, dateRender(obj, 'finished'))),
            ] : null,
        ),
    );
    return {view};
});


widget('UListVote', { view: vnode => vnode.attrs.data.canvote ? voteRender(vnode.attrs.data, '-') : null });
widget('UListLabels', { view: vnode => labelRender(vnode.attrs.data, '-', 0) });

const dateWidget = field => initvnode => {
    const data = initvnode.attrs.data;
    let open;
    const close = ev => {
        if (ev && open.contains(ev.target)) return;
        open = null;
        document.removeEventListener('click', close);
        m.redraw();
    };
    const view = () => m('div', { onclick: function(ev) { open = this; document.addEventListener('click', close) } },
        open ? m('div', dateRender(data, field)) : null,
        data[field] ? RDate.fmt(RDate.expand(data[field])) : '-',
        ' ', m(Icon.Pencil),
    );
    return {view};
};

widget('UListStartDate', dateWidget('started'));
widget('UListFinishDate', dateWidget('finished'));


widget('UListRelease', { view: vnode => rstatusRender(vnode.attrs.data, null, 'not on your list') });


// Connect multiple instances of the same release together
if (pageVars && pageVars.widget && pageVars.widget.UListRelDD) {
    const rids = {};
    pageVars.widget.UListRelDD.forEach(o => {
        if (!rids[o[1].id]) rids[o[1].id] = o[1];
        else o[1] = rids[o[1].id];
    });
}

widget('UListRelDD', initvnode => {
    const r = initvnode.attrs.data;
    let open;
    const close = ev => {
        if (ev && open.contains(ev.target)) return;
        open = null;
        document.removeEventListener('click', close);
        m.redraw();
    };
    const save = v => ev => {
        ev.preventDefault();
        r.status = v;
        close();
        rstatusSave(r);
    };
    const view = () => [
        open ? m('ul',
            vndbTypes.rlistStatus.map((x,i) => m('li',
                m('a[href=#]', { onclick: save(i) }, x)
            )),
            r.status === null ? null : m('li',
                m('a[href=#]', { onclick: save(null) }, '- remove -')
            ),
        ) : null,
        m('div', { onclick: function() { if (open) close(); else { open = this; document.addEventListener('click', close) } } },
            r._api && r._api.loading() ? m('span.spinner') :
            r._api && r._api.error ? m('b', r._api.error) :
            r.status === null ? '--' : vndbTypes.rlistStatus[r.status],
            m('span', ' ▾'),
        )
    ];
    return {view};
});
