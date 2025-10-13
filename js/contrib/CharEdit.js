const Names = vnode => {
    const data = vnode.attrs.data;
    let idx = 0;
    data.names.forEach(a => a._idx = ++idx);
    // XXX: Doesn't update when VNs are added/removed in the form, but that's not a common action.
    const langs = new Set(data.vnstate.flatMap(v => v.rels.flatMap(r => r.lang)));

    const add = new DS(
        {
            opts: { width: 250 },
            list: (src, str, cb) => DS.ScriptLang.list(src, str, lst => cb(lst.filter(o => langs.has(o.id)))),
            view: DS.ScriptLang.view
        }, {
            onselect: obj => data.names.push({ lang: obj.id, name: '', latin: '', _new: true, _idx: ++idx }),
            props: obj => data.names.some(n => n.lang === obj.id) ? { selectable: false, append: m('small', ' (already listed)') } : {},
        }
    );
    return { view: vnode => m('fieldset',
        m('label', 'Name(s)'),
        m('table.chare_names',
            m('thead', m('tr',
                m('td'),
                m('td.tc_name', 'Name (original script)'),
                m('td.tc_name', 'Romanization'),
                m('td'),
            )),
            m('tbody', data.names.map(a => m('tr', {key: a._idx},
                m('td', LangIcon(a.lang)),
                m('td.tc_name', m(Input, { data: a, field: 'name', maxlength: 100, required: true, focus: a._new })),
                m('td.tc_name', !a.latin && !mayRomanize.test(a.name) ? null : m(Input, {
                    data: a, field: 'latin', required: mustRomanize.test(a.name), maxlength: 100,
                    invalid: a.latin === a.name || mustRomanize.test(a.latin) ? 'Romanization should only contain characters in the latin alphabet.' : null,
                })),
                m('td',
                    // Empty 'langs' can happen when the VN has no releases. The default olang name entry is still usable.
                    langs.size ? m(Button.Del, { onclick: () => data.names = data.names.filter(x => x !== a) }) : null
                ),
            ))),
            [...langs.values()].some(l => !data.names.some(n => n.lang === l))
            ?  m('tfoot', m('tr', m('td[colspan=3]', m(DS.Button, { ds: add }, 'Add name')))) : null
        )
    )};
};

const Alias = vnode => {
    const data = vnode.attrs.data;
    let idx = 0;
    data.alias.forEach(a => a._idx = ++idx);
    return { view: vnode => m('fieldset',
        m('label', 'Aliases'),
        m('table.chare_names',
            m('thead', m('tr',
                m('td.tc_name', 'Name (original script)'),
                m('td.tc_name', 'Romanization'),
                m('td', ''),
            )),
            m('tbody', data.alias.map(a => m('tr', {key: a._idx},
                m('td.tc_name',
                    m(Input, { data: a, field: 'name', maxlength: 100, required: true, focus: a._new }),
                    a.name !== '' && data.names.some(n => n.name === a.name || n.latin === a.name) ? m('p.invalid', 'Already listed under Name(s)') : null,
                ),
                m('td.tc_name', !a.latin && !mayRomanize.test(a.name) ? null : m(Input, {
                    /* Many old entries are missing romanization - let's not force people to romanize existing aliases */
                    data: a, field: 'latin', required: a._new && mustRomanize.test(a.name), maxlength: 100,
                    invalid: a.latin === a.name || mustRomanize.test(a.latin) ? 'Romanization should only contain characters in the latin alphabet.' : null,
                })),
                m('td',
                    m(Select, { data: a, field: 'spoil', options: spoilLevels }),
                    m(Button.Del, { onclick: () => data.alias = data.alias.filter(x => x !== a) }),
                ),
            ))),
            m('tfoot', m('tr', m('td[colspan=3]',
                data.alias.anyDup(({name,latin}) => [name,latin===''?null:latin])
                ? m('p.invalid', 'There are duplicate aliases.') : null,
                data.alias.length > 25 ? null : m('button[type=button]', { onclick: () => data.alias.push({
                    name: '', latin: '', spoil: 0, _idx: ++idx, _new: true
                }) }, 'Add alias'),
            )))
        )
    )};
};

const GenInfo = vnode => {
    const data = vnode.attrs.data;

    const defGender = {'':'n', 'm':'f', 'f':'m', 'b':'o', 'n':'o'};

    const sexAdd = {
        m: ' (has penis)',
        f: ' (has vagina)',
        b: ' (has penis + vagina)',
        n: ' (has neither)',
    };
    const sexOpts = vndbTypes.charSex.map(([k,v]) => [k,v + (sexAdd[k]||'')]);

    let main = data.main !== null;
    const mainDs = new DS(DS.Chars, {
        onselect: obj => { data.main = obj.id; data.main_name = obj.title; },
        props: obj => obj.id === data.id ? { selectable: false, append: m('small', ' (this character)') } :
                      obj.main !== null ? { selectable: false } : {},
    });

    const view = () => [ m('fieldset.form',
        m(Names, {data}),
        m(Alias, {data}),
        m('fieldset',
            m('label[for=description]', 'Description'),
            m(TextPreview, {
                data, field: 'description',
                header: m('b', '(English please!)'),
                attrs: { id: 'description', rows: 10, maxlength: 5000 },
            }),
        ),
        m('fieldset',
            m('label[for=bmonth]', 'Birthday'),
            m(Select, {
                id: 'bmonth',
                options: range(0, 12).map(m => [m, m ? m + ' (' + RDate.months[m-1] + ')' : 'Unknown']),
                value: Math.trunc(data.birthday / 100),
                oninput: v => data.birthday = v * 100 + (v === 0 ? 0 : data.birthday % 100),
            }),
            data.birthday === 0 ? null : m(Select, {
                class: 'sw',
                options: range(0, 31).map(m => [m,m === 0 ? 'day' : m]),
                value: data.birthday % 100,
                oninput: v => data.birthday = Math.trunc(data.birthday / 100)*100 + v,
            }),
            data.birthday !== 0 && (data.birthday % 100) === 0 ? m('p.invalid', 'Day is required.') : null,
        ),
        m('fieldset',
            m('label[for=age]', 'Age'),
            m(Input, { id: 'age', data, field: 'age', class: 'sw', type: 'number', empty: null, max: 32767 }),
            ' years'
        )
    ), m('fieldset.form',
        m('legend', 'Sex & gender identity'),
        m('fieldset',
            'To avoid confusion: ', m('strong', 'Sex'), ' relates to the physical body while ', m('strong', 'Gender identity'), ' relates to the personality.',
        ),
        m('fieldset',
            m('label[for=sex]', 'Sex', HelpButton('sex')),
            m(Select, { id: 'sex', data, field: 'sex', class: 'mw', options: sexOpts }),
            m('label.check',
                ' ',
                m('input[type=checkbox]', {
                    checked: data.spoil_sex !== null,
                    onclick: ev => data.spoil_sex = ev.target.checked ? data.sex : null,
                }),
                ' spoiler'
            ),
            data.spoil_sex === null ? null : m('div',
                '▲ apparent (non-spoiler) sex', m('br'),
                '▼ actual (spoiler) sex', m('br'),
                m(Select, { data, field: 'spoil_sex', class: 'mw', options: sexOpts }),
            )
        ),
        Help('sex',
            m('p', 'The physical sex of the character, i.e. what they have between their legs.'),
            m('dl',
                m('dt', 'Unknown'),
                m('dd', 'Use this for characters whose physical sex is never shown or mentioned, and who have an unclear or ambiguous gender.',
                ),
                m('dt', 'Male'),
                m('dd', 'The character (most likely) has a penis.'),
                m('dt', 'Female'),
                m('dd', 'The character (most likely) has a vagina.'),
                m('dt', 'Both'),
                m('dd', 'The character has both a penis and a vagina, e.g. a futanari.'),
                m('dt', 'Sexless'),
                m('dd', 'The character has neither a penis nor a vagina, e.g. a robot or a plant.'),
            ),
            m('p',
                'If the genitals are never explicitely mentioned but there is no strong indication that the character might not be cisgender, ',
                'you should assume that the character\'s sex equals their gender.'
            ),
            m('p',
                'Do not confuse physical sex with biological sex (i.e. the genitals that the character has been born with). ',
                'For a character that had a gender reassignment surgery, their post-op genitals should be considered their physical sex.',
            ),
            m('p',
                'If a character changes sex through the story (through magic, surgery or otherwise), ',
                'it may be worth creating a separate instance. See ', m('a[href=/d12#2][target=_blank]', 'd12#2'), ' for more information.',
            ),
        ),
        m('fieldset',
            m('label[for=genderc]', 'Gender identity', HelpButton('gender')),
            m('label.check',
                m('input[type=checkbox]', {
                    checked: data.gender !== null,
                    oninput: () => data.gender = data.gender === null ? defGender[data.sex] : null,
                }), ' Different from sex'
            ),
        ),
        data.gender === null ? null : m('fieldset',
            m(Select, { id: 'gender', data, field: 'gender', class: 'mw', options: vndbTypes.charGender }),
            m('label.check',
                ' ',
                m('input[type=checkbox]', {
                    checked: data.spoil_gender !== null,
                    onclick: ev => data.spoil_gender = ev.target.checked ? data.gender : null,
                }),
                ' spoiler'
            ),
            data.spoil_gender === null ? null : m('div',
                '▲ apparent (non-spoiler) gender', m('br'),
                '▼ actual (spoiler) gender', m('br'),
                m(Select, { data, field: 'spoil_gender', class: 'mw', options: vndbTypes.charGender }),
            ),
        ),
        Help('gender',
            m('p',
                'Gender identity of the character. A character\'s gender is different from their sex ', m('strong', 'only'), ' in the following cases:',
            ),
            m('ul',
                m('li',
                    'The story explicitely mentions that the character is transgender.', m('br'),
                    'This may be done by an omniscient narrator, the character themselves, or people close to the character in question. ',
                    'Such a statement is sufficient to treat the character as transgender, ',
                    'even if they do not display any other typical characteristics or behaviour associated with it.'
                ),
                m('li',
                    'The character\'s sex is neither "Male" nor "Female", ',
                    'but their outward appearance or behavior conforms to typical male or female stereotypes, ',
                    'or their gender can be inferred from pronouns used thourough the story.'
                ),
                m('li',
                    'There are strong hints that the character identifies differently from their sex. Some of the hints associated with recognizing such characters are:',
                    m('ul',
                        m('li', 'The use of pronouns that do not correspond to the gender they were assigned at birth.'),
                        m('li', 'Engaging in social, legal or medical transition.'),
                        m('li', 'Assuming or trying to assume a traditionally feminine/masculine role in the society, that contradicts their assigned gender at birth.'),
                        m('li', 'Dressing in clothing that contradicts their assigned gender at birth (cross-dressing)'),
                        m('li',
                            'Character expresses discomfort with their own masculinity/femininity (gender dysphoria).', m('br'),
                            'This might happen through verbal statements that focus on the ugliness of their body or ',
                            'the weird itch beneath the skin they cannot scratch, or physical actions ',
                            'like avoiding mirrors, wearing bulky clothing and avoiding sexual interactions.'
                        ),
                    ),
                ),
            ),
            m('p', m('strong', 'IMPORTANT:')),
            m('ul',
                m('li',
                    'Characters should ', m('strong', 'NOT'), ' be treated as transgender based solely on outward appearance or behavior. ',
                    'Cross-dressing does not automatically mean a character is transgender!'
                ),
                m('li',
                    'Characters who are turned into their opposite sex through magic or advanced tech should not be treated as transgender ',
                    'in the absence of any other associated behaviour. Instead, a separate instance of the character should be created, ',
                    'and both instances should be initially treated as cisgender.'
                ),
                m('li',
                    'Characters who undergo forced feminization/masculinization should be examined on a case by case basis and their ',
                    'feelings and statements should be closely examined. In a fictional setting it\'s common that the character will ',
                    'eventually align with their forcibly imprinted gender and then become transgender.'
                ),
            ),
            m('p', 'The following options can be selected:'),
            m('dl',
                m('dt', 'Man'),
                m('dd', 'The character identifies as a man.'),
                m('dt', 'Woman'),
                m('dd', 'The character identifies as a woman.'),
                m('dt', 'Non-binary'),
                m('dd',
                    'The character does not identify as a binary "man" or "woman". ',
                    'This applies to agender characters, characters conforming to some sort of third gender or anything in between.',
                ),
                m('dt', 'Ambiguous'),
                m('dd',
                    'The character\'s gender is intentionally left ambiguous in the story. ',
                    'Only use this option if there is a strong suggestion that the character may not identify with their sex, ',
                    'for example when their outward appearance or behavior does not conform to typical male or female stereotypes, ',
                    'but there is no clear confirmation in the story that points to their actual gender.',
                ),
            ),
        ),
    ), m('fieldset.form',
        m('legend', 'Body'),
        m('fieldset',
            m('label[for=sbust]', 'Bust'),
            m(Input, { id: 'sbust', data, field: 's_bust', class: 'sw', type: 'number', max: 32767 }),
            ' cm',
        ),
        m('fieldset',
            m('label[for=swaist]', 'Waist'),
            m(Input, { id: 'swaist', data, field: 's_waist', class: 'sw', type: 'number', max: 32767 }),
            ' cm',
        ),
        m('fieldset',
            m('label[for=ship]', 'Hips'),
            m(Input, { id: 'ship', data, field: 's_hip', class: 'sw', type: 'number', max: 32767 }),
            ' cm',
        ),
        m('fieldset',
            m('label[for=height]', 'Height'),
            m(Input, { id: 'height', data, field: 'height', class: 'sw', type: 'number', max: 32767 }),
            ' cm',
        ),
        m('fieldset',
            m('label[for=weight]', 'Weight'),
            m(Input, { id: 'weight', data, field: 'weight', class: 'sw', type: 'number', empty: null, max: 32767 }),
            ' kg',
        ),
        m('fieldset',
            m('label[for=bloodt]', 'Blood type'),
            m(Select, { id: 'bloodt', data, field: 'bloodt', class: 'mw', options: vndbTypes.bloodType }),
        ),
        m('fieldset',
            m('label[for=cupsize]', 'Cup size'),
            m(Select, { id: 'cupsize', data, field: 'cup_size', class: 'mw', options: vndbTypes.cupSize }),
        ),
    ), m('fieldset.form',
        m('legend', 'Instance'),
        data.main_ref ? m('fieldset',
            'This character is already used as an instance for another character. If you want to link more characters to this one, please edit the other characters instead.',
        ) : m('fieldset',
            m('label.check',
                m('input[type=checkbox]', { checked: main, onclick: () => { main = !main; if (!main) data.main = null } }),
                ' This character is an instance of another character.',
            ),
        ),
        main ? m('fieldset',
            m(Select, { class: 'mw', data, field: 'main_spoil', options: spoilLevels }),
        ) : null,
        main ? m('fieldset',
            m(DS.Button, { ds: mainDs, class: 'mw' }, 'Set character'),
            data.main === null ? m('p.invalid', 'No character selected.') : m('span', ' ',
                m('small', data.main, ': '),
                m('a[target=_blank]', { href: '/' + data.main }, data.main_name),
            ),
        ) : null,
    )];
    return {view};
};

const Image = vnode => {
    const data = vnode.attrs.data;

    const imageApi = new Api('Image');
    const imageData = {id:''};
    const imageSubmit = ev => {
        ev.stopPropagation();
        ev.preventDefault();
        const d = {id: imagePatternId('ch', imageData.id)};
        imageApi.call(d, nfo => {
            imageData.id = '';
            data.image = nfo.id;
            data.image_info = nfo;
        });
    };

    const uploadApi = new Api('ImageUpload');
    const uploadSubmit = ev => {
        ev.stopPropagation();
        ev.preventDefault();
        const form = new FormData();
        form.append('type', 'ch');
        form.append('img', $('#file').files[0]);
        uploadApi.call(form, r => {
            data.image = r.id;
            data.image_info = r;
        });
    };

    const view = () => m('table', m('tr', { key: data.image||'e' },
        m('td[style=width:270px;text-align:center]', data.image === null ? null : m('img',
            { width: data.image_info.width, height: data.image_info.height, src: imgurl(data.image) }
        )),
        m('td',
            data.image === null ? [] : [
                m('p',
                    m(Button.Del, { onclick: () => data.image = null }),
                    ' ', m('small', data.image, ' / '), data.image_info.width, 'x', data.image_info.height,
                ),
                m(ImageFlag, { img: data.image_info }),
                m('br'), m('br'),
            ],
            m('strong', 'File upload'), m('br'),
            m(Form, { onsubmit: uploadSubmit },
                m('input#file[type=file][required]', { accept: imageAccept, oninput: uploadSubmit }),
                uploadApi.Status(),
            ),
            m('p', imageFormats),
            m('p', 'Images larger than 256x300 are automatically resized.'),
            m('br'), m('br'),
            m('strong', 'Image ID'), m('br'),
            m(Form, { onsubmit: imageSubmit, api: imageApi },
                m(Input, { class: 'lw', data: imageData, field: 'id', pattern: imagePattern('ch'), oninput: () => imageApi.abort() }),
                m('button[type=submit]', 'Edit'),
                imageApi.Status(),
            ),
        ),
    ));
    return {view};
};

const Traits = vnode => {
    const data = vnode.attrs.data;
    let added = [];
    const ds = new DS(DS.Traits, {
        keep: true,
        props: obj => data.traits.find(x => x.tid === obj.id) ?
               {selectable: false, append: m('small', ' (already selected)')} :
               {selectable: obj.applicable && !obj.hidden},
        onselect: obj => {
            added.push(obj.id);
            data.traits.push({
                tid: obj.id,
                spoil: obj.defaultspoil,
                lie: false,
                name: obj.name,
                group: obj.group_name,
                hidden: obj.hidden,
                locked: obj.locked,
                applicable: obj.applicable,
                _new: true
            });
        },
    });

    let selt = null;
    let selid = null;
    const but = (t,id,lbl,cond,set) => m('a[href=#]', {
        title: lbl,
        onmouseover: () => { selt = t.tid; selid = id },
        onmouseout: () => selt = null,
        class: (selt === t.tid && selid === id) || (cond && (selt !== t.tid || selid == 'sl')) ? id : null,
        onclick: ev => set(ev.preventDefault()),
    });

    const trait = t => m('tr',
        m('td', { class: t.applicable && !t.hidden ? null : 'linethrough' },
            t.group ? m('small', t.group, ' / ') : null,
            m('a[target=_blank]', { href: '/'+t.tid }, t.name),
            t.hidden && !t.locked ? m('b', ' (awaiting moderation)') :
            t.hidden ? m('b', ' (deleted)') :
            !t.applicable ? m('b', ' (not applicable)') : null,
        ),
        m('td',
            but(t, 's0', 'Not a spoiler', t.spoil === 0, () => t.spoil = 0),
            but(t, 's1', 'Minor spoiler', t.spoil === 1, () => t.spoil = 1),
            but(t, 's2', 'Major spoiler', t.spoil === 2, () => t.spoil = 2),
            but(t, 'sl', 'Lie',           t.lie,         () => t.lie = !t.lie),
        ),
        m('td',
            selt !== t.tid ? m('a[href=#]',
                { onclick: ev => {
                    added = added.filter(x => x !== t.tid);
                    data.traits = data.traits.filter(x => x !== t);
                    ev.preventDefault();
                } }, 'remove') :
            selid === 's0' ? 'Not a spoiler' :
            selid === 's1' ? 'Minor spoiler' :
            selid === 's2' ? 'Major spoiler' : 'This turns out to be false'
        ),
    );

    const view = () => m('table.chare_traits',
        data.traits.length > added.length ? [
            m('tr', m('td[colspan=3]', 'Current traits')),
            data.traits.filter(x => !x._new).map(trait),
        ] : [],
        added.length > 0 ? [
            m('tr', m('td[colspan=3]', 'Newly added traits')),
            (l => added.map(id => trait(l[id])))(Object.fromEntries(data.traits.filter(x => x._new).map(x => [x.tid,x])))
        ] : [],
        m('tr', m('td[colspan=3]',
            m(DS.Button, {ds}, 'Add trait'),
        )),
    );
    return {view};
};

const VNs = vnode => {
    const data = vnode.attrs.data;
    const vnstate = Object.fromEntries(data.vnstate.map(({id,rels,prods,title}) => [id,{
        id, rels, prods, title,
        adv: data.vns.find(x => x.vid === id && x.rid !== null),
    }]));

    const ds = new DS(DS.VNs, {
        onselect: obj => {
            data.vns.push({ vid: obj.id, rid: null, spoil: 0, role: 'primary' })
            const l = new Api('Release');
            l.call({vid: obj.id, charlink:true}, r => vnstate[obj.id].rels = r.results);
            const p = new Api('VNCharProducers');
            p.call({vid: obj.id}, r => vnstate[obj.id].prods = r.results);
            vnstate[obj.id] = {
                id: obj.id,
                title: obj.title,
                rels: [],
                adv: false,
                rload: l,
            };
        },
        props: obj => vnstate[obj.id] ? {selectable: false, append: m('small', ' (already selected)')} : {},
    });

    const rds = r => new DS(
        DS.New(DS.Releases(vnstate[r.vid].rels), () => ({id:''}), () => 'Default'),
        { onselect: obj => r.rid = obj.id === '' ? null : obj.id }
    );

    const allprods = Object.fromEntries(data.vnstate.flatMap(({prods}) => prods.map(({id,title}) => [id,title])));

    const vn = (v,rels) => m('fieldset.form',
        m('legend',
            m(Button.Del, { onclick: () => { data.vns = data.vns.filter(x => x.vid !== v.id); delete vnstate[v.id]; } }),
            m('small', ' ', v.id, ': '),
            m('a[target=_blank]', { href: '/'+v.id }, v.title)
        ),
        v.rload && v.prods && !v.prods.find(({id}) => allprods[id]) ? m('div.warning',
            m('h2', 'No common publishers'),
            m('p',
                'A single character entry should NOT be linked to visual novels from different publishers. ',
                'You may want to create a separate instance instead, see ', m('a[target=_blank][href=/d12#2]', 'the instance guidelines'), ' for more information.',
            ),
            m('p',
                m('br'),
                'If this visual novel was indeed created by the same developer or published by the same publisher, ',
                'but under a different producer entry, then feel free to ignore this warning.',
            ),
            m('p',
                m('br'),
                'Existing producers: ', Object.keys(allprods).map(id => m('a[target=_blank]', { href: '/'+id }, allprods[id])).intersperse(', '),
                m('br'),
                'Producers of this VN: ', v.prods.map(({id,title}) => m('a[target=_blank]', { href: '/'+id }, title)).intersperse(', '),
            ),
        ) : null,
        v.adv ? [
            m('table.full.chare_vnrel',
                m('tr.top', m('td',
                    m('b', 'Important: '),
                    'only select specific releases if the character has a significantly different role in those releases.',
                    m('br'),
                    "If the character's role is roughly the same in every (non-trial) release, switch back to ",
                    m('a[href=#]', { onclick: ev => {
                        v.adv = false;
                        ev.preventDefault();
                        const first = data.vns.find(x => x.vid === v.id);
                        first.rid = null;
                        data.vns = data.vns.filter(x => x.vid !== v.id || x === first);
                    } }, 'single-role mode.'),
                )),
                v.rload && (v.rload.loading() || v.rload.error) ? m('tr.top', m('td', v.rload.Status())) : rels.flatMap(r => [
                    m('tr.top', { key: 't'+(r.rid||'') }, m('td',
                        rels.length === 1 ? null : m(Button.Del, {
                            onclick: () => data.vns = data.vns.filter(x => x !== r),
                        }), ' ',
                        (() => {
                            if (!r._ds) r._ds = rds(r);
                            const x = r.rid && v.rels.find(x => x.id === r.rid);
                            return m(DS.Button, {ds: r._ds, class: 'xw'},
                                !r.rid ? 'Default' : !x ? 'Unknown/moved release: '+r.rid : Release(x,true)
                            );
                        })(),
                    )),
                    m('tr.opt', { key: 'o'+(r.rid||'') }, m('td',
                        m(Select, { class: 'mw', data: r, field: 'role', options: vndbTypes.charRole }),
                        m('br'),
                        m(Select, { class: 'mw', data: r, field: 'spoil', options: spoilLevels }),
                    )),
                ]),
                m('tr.top', m('td',
                    rels.anyDup(x => x.rid) ? m('p.invalid', 'The same release is listed multiple times.') : null,
                    m('button[type=button]', { onclick: () => data.vns.push({
                        vid: v.id, rid: null, spoil: 0, role: 'primary'
                    }) }, 'Add release'),
                )),
            ),
        ] : [
            m('fieldset',
                m('label', { for: v.id+'-role' }, 'Role'),
                m(Select, { id: v.id+'-role', class: 'mw', data: rels[0], field: 'role', options: vndbTypes.charRole }),
            ),
            m('fieldset',
                m('label', { for: v.id+'-spoil' }, 'Spoiler level'),
                m(Select, { id: v.id+'-spoil', class: 'mw', data: rels[0], field: 'spoil', options: spoilLevels }),
            ),
            m('fieldset',
                m('a[href=#]', { onclick: ev => { v.adv = true; ev.preventDefault(); } }, 'Release-specific roles »'),
            ),
        ],
    );

    const view = () => {
        const vns = [];
        const rels = {};
        for (const v of data.vns) {
            if (!(v.vid in rels)) {
                rels[v.vid] = [v];
                vns.push(vnstate[v.vid]);
            } else rels[v.vid].push(v);
        }
        return [
            vns.length === 0 ? [
                m('p.invalid', 'No visual novels selected.'),
            ] : vns.map(v => vn(v, rels[v.id])),
            m('fieldset.form',
                m(DS.Button, {ds}, 'Add visual novel'),
            ),
        ];
    };
    return {view};
};

widget('CharEdit', vnode => {
    const data = vnode.attrs.data;
    const api = new Api('CharEdit');

    const tabs = [
        [ 'gen', 'General info', () => [ m('h1', 'General info'), m(GenInfo, {data}) ] ],
        [ 'img', 'Image', () => [ m('h1', 'Image'), m(Image, {data}) ] ],
        [ 'traits', 'Traits', () => [ m('h1', 'Traits'), m(Traits, {data}) ] ],
        [ 'vn', 'Visual novels', () => [ m('h1', 'Visual novels'), m(VNs, {data}) ] ],
    ];

    const view = () => m(Form, {api, onsubmit: () => api.call(data)},
        m(FormTabs, {tabs}),
        m(EditSum, {data,api,type:'c'}),
    );
    return {view};
});
