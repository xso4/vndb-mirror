widget('ImageFlagging', initvnode => {
    const data = initvnode.attrs.data;
    let img_idx = data.single ? 0 : data.images.length;

    let fullscreen = false;
    let show_votes = data.single ? data.images[0].id : '';
    let excl_voted = true;
    let load_done = false;
    const loadApi = new Api('Images');
    const load = () => {
        if (data.single) return;
        if (loadApi.loading()) return;
        if (img_idx < data.images.length - 3) return;
        if (load_done) return;
        loadApi.call({excl_voted}, r => {
            load_done = r.results.length < 30;
            data.images.push(...r.results);
            if (data.images.length > 1000) {
                data.images.splice(0, 100);
                img_idx -= 100;
            }
        });
    };

    let saveQueue = {};
    let saveTimer;
    const saveApi = new Api('ImageVote');
    const saveCall = () => {
        saveTimer = null;
        saveApi.call({ votes: Object.values(saveQueue).map(({id,token,my_sexual,my_violence,my_overrule}) => ({id,token,my_sexual,my_violence,my_overrule})) });
        saveQueue = {};
        m.redraw();
    };
    const save = i => {
        if (!i.token) return;
        if (i.my_sexual === null || i.my_violence === null) delete saveQueue[i.id];
        else if (!saveQueue[i.id]) {
            data.my_votes++;
            saveQueue[i.id] = i;
            if (!data.single) load(img_idx++);
        }
        if (!saveTimer) saveTimer = setTimeout(saveCall, data.single ? 500 : 5000);
    };

    const keydown = ev => {
        if (data.my_votes < 100) return;
        const i = data.images[img_idx];
        if (!i) return;
        switch(ev.key) {
            case 'ArrowLeft': if (img_idx > 0) img_idx--; break;
            case 'ArrowRight': if (!data.single) load(img_idx++); break;
            case 'v': fullscreen = !fullscreen; break;
            case 'Escape': fullscreen = false; break;
            case '1': i.my_sexual = 0; i.my_violence = 0; save(i); break;
            case '2': i.my_sexual = 0; i.my_violence = 1; save(i); break;
            case '3': i.my_sexual = 0; i.my_violence = 2; save(i); break;
            case '4': i.my_sexual = 1; i.my_violence = 0; save(i); break;
            case '5': i.my_sexual = 1; i.my_violence = 1; save(i); break;
            case '6': i.my_sexual = 1; i.my_violence = 2; save(i); break;
            case '7': i.my_sexual = 2; i.my_violence = 0; save(i); break;
            case '8': i.my_sexual = 2; i.my_violence = 1; save(i); break;
            case '9': i.my_sexual = 2; i.my_violence = 2; save(i); break;
            case 's': i.my_sexual = 0; save(i); break;
            case 'd': i.my_sexual = 1; save(i); break;
            case 'f': i.my_sexual = 2; save(i); break;
            case 'j': i.my_violence = 0; save(i); break;
            case 'k': i.my_violence = 1; save(i); break;
            case 'l': i.my_violence = 2; save(i); break;
        }
        m.redraw();
    };
    document.addEventListener('keydown', keydown);

    let selected = ''; // field + val + id
    const but = (i, field, val, lbl) => m('li',
        { class: i[field] === val || selected === field+val+i.id ? 'sel' : null },
        m('label',
            { onmouseover: () => selected = field+val+i.id, onmouseout: () => selected = '' },
            m('input[type=radio]', {
                onclick: () => save(i, i[field] = val),
                checked: i[field] === val,
                onfocus: function() { this.blur() }, // Prevent arrow keys from changing selection
            }),
            ' ', lbl
        )
    );

    const stat = (avg, dev) => avg === null || dev === null ? '-'
        : avg.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFactionDigits: 2 })
        + ' σ '
        + dev.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFactionDigits: 2 });

    const img = i => [
        m('div',
            m('button[type=button]', {class: img_idx === 0 ? 'invisible' : null, onclick: () => img_idx = Math.max(0, img_idx-1) }, '««'),
            m('span', i.entries.length === 0 ? null : [
                m('small', i.entries[0].id, ':'),
                m('a[target=_blank]', { href: '/'+i.entries[0].id }, i.entries[0].title),
            ]),
            m('button[type=button]', {class: data.single ? 'invisible' : null, onclick: () => load(img_idx++) }, '»»'),
        ),
        m('div',
            m('a[target=_blank]', { href: imgurl(i.id) },
                m('img', {
                    key: i.id, src: imgurl(i.id),
                    onload: () => data.images[img_idx+1] && imgPreload(imgurl(data.images[img_idx+1].id)),
                }),
            ),
        ),
        m('div',
            m('span',
                saveApi.error ? m('b', 'Save failed: ', saveApi.error) : [
                    m('span.spinner', { class: saveApi.loading() ? null : 'invisible' }),
                    Object.keys(saveQueue).length > 0 ? m('small', 'Unsaved votes: ', Object.keys(saveQueue).length) : null,
                ],
            ),
            m('span',
                m('a[target=_blank]', { href: '/'+i.id }, i.id),
                m('small', ' / '),
                m('a[target=_blank]', { href: imgurl(i.id) }, i.width + 'x' + i.height),
            ),
        ),
        m('div', !i.token ? null : [
            m('p', (s =>
                s === 0 ? [
                    m('strong', 'Safe'), m('br'),
                    '- No nudity', m('br'),
                    '- No (implied) sexual actions', m('br'),
                    '- No suggestive clothing or visible underwear', m('br'),
                    '- No sex toys'
                ] : s === 1 ? [
                    m('strong', 'Suggestive'), m('br'),
                    '- Visible underwear or skimpy clothing', m('br'),
                    '- Erotic posing', m('br'),
                    '- Sex toys (but not visibly being used)', m('br'),
                    '- No visible genitals or female nipples'
                ] : s === 2 ? [
                    m('strong', 'Explicit'), m('br'),
                    '- Visible genitals or female nipples', m('br'),
                    '- Penetrative sex (regardless of clothing)', m('br'),
                    '- Visible use of sex toys'
                ] : null
            )(selected.startsWith('my_sexual') && selected.endsWith(i.id) ? Math.floor(selected.slice(9, 10)) : i.my_sexual)),
            m('ul',
                m('li', m('strong', 'Sexual')),
                but(i, 'my_sexual', 0, 'Safe'),
                but(i, 'my_sexual', 1, 'Suggestive'),
                but(i, 'my_sexual', 2, 'Explicit'),
                data.mod ? m('li.overrule', m('label', m('input[type=checkbox]',
                    { checked: i.my_overrule, onclick: ev => save(i, i.my_overrule = ev.target.checked) },
                ), ' Overrule')) : null,
            ),
            m('ul',
                m('li', m('strong', 'Violence')),
                but(i, 'my_violence', 0, 'Tame'),
                but(i, 'my_violence', 1, 'Violent'),
                but(i, 'my_violence', 2, 'Brutal'),
            ),
            m('p', (s =>
                s === 0 ? [
                    m('strong', 'Tame'), m('br'),
                    '- No visible violence', m('br'),
                    '- Tame slapstick comedy', m('br'),
                    '- Weapons, but not used to harm anyone', m('br'),
                    '- Only very minor visible blood or bruises'
                ] : s === 1 ? [
                    m('strong', 'Violent'), m('br'),
                    '- Visible blood', m('br'),
                    '- Non-comedic fight scenes', m('br'),
                    '- Physically harmful activities'
                ] : s === 2 ? [
                    m('strong', 'Brutal'), m('br'),
                    '- Excessive amounts of blood', m('br'),
                    '- Cut off limbs', m('br'),
                    '- Sliced-open bodies', m('br'),
                    '- Harmful activities leading to death'
                ] : null
            )(selected.startsWith('my_violence') && selected.endsWith(i.id) ? Math.floor(selected.slice(11, 12)) : i.my_violence)),
        ]),
        m('p.center', !i.token ? null : [
            'Not sure? Read the ', m('a[href=/d19][target=_blank]', 'full guidelines'), ' for more detailed guidance.',
            data.my_votes < 100 ? null : m('span', ' (', m('a[target=_blank]', { href: urlStatic+'/f/imgvote-keybindings.svg' }, 'keyboard shortcuts'), ')'),
        ]),
        m('div',
            i.votes.length === 0 ? m('p.center', 'No other votes on this image yet.') :
            show_votes !== i.id && i.my_sexual === null && i.my_violence === null ? m('p.center',
                i.votes.length, i.votes.length === 1 ? ' vote' : ' votes', ', ',
                m('a[href=#]', { onclick: ev => { ev.preventDefault(); show_votes = i.id; } }, 'show »'),
            ) : [
                m('p.center',
                    i.votes.length, i.votes.length === 1 ? ' vote' : ' votes',
                    m('small', ' / '), ['safe', 'suggestive', 'explicit'][i.sexual], ': ', stat(i.sexual_avg, i.sexual_stddev),
                    m('small', ' / '), ['tame', 'violent', 'brutal'][i.violence], ': ', stat(i.sexual_avg, i.sexual_stddev),
                ),
                m('table', i.votes.map((v,n) => m('tr', {key: i.id+'-'+n, class: v.ignore ? 'ignored' : null},
                    m('td', m.trust(v.user)),
                    m('td', ['Safe', 'Suggestive', 'Explicit'][v.sexual]),
                    m('td', ['Tame', 'Violent', 'Brutal'][v.violence]),
                    m('td', v.uid ? m('a[target=_blank]', { href: '/img/list?view='+data.nsfw_token+'&u='+v.uid }, 'votes') : null),
                ))),
            ],
        ),
        fullscreen ? m('div.fullscreen', { style: 'background-image: url('+imgurl(i.id)+')', onclick: () => fullscreen = false }) : null
    ];

    const view = () => [
        m('h1', 'Image flagging'),
        m('div.imageflag', data.warn ? [
            m('ul',
                m('li', 'Make sure you are familiar with the ', m('a[href=/d19][target=_blank]', 'image flagging guidelines'), '.'),
                m('li', m('b', 'WARNING: '), 'Images shown may include spoilers, be highly offensive and/or contain very explicit depictions of sexual acts.'),
            ),
            m('br'),
            data.single ? null : m('label',
                m('input[type=checkbox]', { checked: !excl_voted, onclick: ev => excl_voted = !ev.target.checked }),
                ' Include images I already voted on.',
                m('br'),
            ),
            m('button[type=button]', {onclick: () => { data.warn = false; if (!data.images.single) load() }}, 'Continue')
        ] : data.images[img_idx] ? img(data.images[img_idx]) : loadApi.error || loadApi.loading() ? loadApi.Status() : 'No more images to vote on!')
    ];
    return {view};
});
