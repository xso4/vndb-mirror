const Titles = initVnode => {
    const {data} = initVnode.attrs;
    const ds = new DS(DS.ScriptLang, {
        onselect: obj => {
            const p = data.vntitles.find(t => t.lang === obj.id);
            data.titles.push({ lang: obj.id, mtl: false, title: p?p.title:'', latin: p?p.latin:'', new: true });
            if (data.titles.length === 1) data.olang = data.titles[0].lang;
        },
        props: obj => data.titles.find(t => t.lang === obj.id) ? { selectable: false, append: m('small', ' (already listed)') } : {},
    });
    const langs = Object.fromEntries(vndbTypes.language);
    const view = () => m('fieldset.form',
        m('legend', 'Titles & languages', HelpButton('titles')),
        Help('titles',
            m('p', 'List of languages that this release is available in.'),
            m('p',
                'A release can have different titles for different languages. ',
                'The main language should always have a title, but this field can be left empty for other languages if it is the same as the main title.'
            ),
            m('p', m('strong', 'Main title: '),
                'The title for the language that the script was originally authored in, ',
                'or for translations, the primary language of the publisher.'
            ),
            m('p', m('strong', 'Machine translation: '),
                'Should be checked if automated programs, such as AI tools, were used to implement support for this language, either partially or fully. ',
                'Should be checked even if the translation has been edited by a human. ',
                'Should NOT be checked if the translation was entirely done by humans, even when its quality happens to be worse than machine translation.'
            ),
        ),
        data.titles.map(t => m('fieldset', {key: t.lang},
            m('label', { for: 'title-'+t.lang }, LangIcon(t.lang), langs[t.lang]),
            m(Input, {
                id: 'title-'+t.lang, class: 'xw',
                maxlength: 300, required: t.lang === data.olang,
                placeholder: t.lang === data.olang ? 'Title (in the original script)' : 'Title (leave empty if equivalent to the main title)',
                data: t, field: 'title', focus: t.new,
            }),
            !t.latin && !mayRomanize.test(t.title) ? m('br') : m('span',
                m('br'),
                m(Input, {
                    class: 'xw', maxlength: 300, required: mustRomanize.test(t.title),
                    data: t, field: 'latin', placeholder: 'Romanization',
                    invalid: t.latin === t.title || mustRomanize.test(t.latin) ? 'Romanization should only contain characters in the latin alphabet.' : null,
                }),
                m('br'),
            ),
            data.titles.length === 1 ? [] : [
                m('span', m('label.check',
                    m('input[type=radio]', { checked: t.lang === data.olang, oninput: ev => data.olang = t.lang }),
                    ' Main title '
                )),
            ],
            m('span', m('label.check',
                m('input[type=checkbox]', { checked: t.mtl, oninput: ev => t.mtl = ev.target.checked }),
                ' Machine translation '
            )),
            m('input[type=button][value=Remove]', {
                class: t.lang === data.olang ? 'invisible' : null,
                onclick: () => data.titles = data.titles.filter(x => x !== t)
            }),
        )),
        m(DS.Button, {ds}, 'Add language'),
        data.titles.length > 0 ? null : m('p.invalid', 'At least one language must be selected.'),
    );
    return {view};
};


const Status = initVnode => {
    const {data} = initVnode.attrs;
    const view = () => m('fieldset.form',
        m('legend', 'Status'),
        m('fieldset', m('label.check',
            m('input[type=checkbox]', { checked: data.official, oninput: ev => data.official = ev.target.checked }),
            ' Official ', HelpButton('official'),
        )),
        Help('official',
            'Whether the release is official, i.e. made or sanctioned by the original developer. ',
            'The official status is in relation to the visual novel that the release is linked to, ',
            'so even if the visual novel itself is an unofficial fanfic in some franchise, the release can still be official.'
        ),
        m('fieldset', m('label.check',
            m('input[type=checkbox]', { checked: data.patch, oninput: ev => data.patch = ev.target.checked }),
            ' Patch (*)', HelpButton('patch'),
        )),
        Help('patch',
            m('p',
                'A patch is not a standalone release, but instead requires another release in order to be used. ',
                'It may be helpful to indicate which releases this patch applies to in the notes.'
            ),
            m('p',
                '*) The following release fields are unavailable for patch releases: Engine, Resolution, Voiced and Animation. ',
                'These fields are automatically reset on form submission when the patch flag is set.'
            ),
        ),
        m('fieldset', m('label.check',
            m('input[type=checkbox]', { checked: data.freeware, oninput: ev => data.freeware = ev.target.checked }),
            ' Freeware', HelpButton('freeware'),
        )),
        Help('freeware', 'Set if this release is available at no cost.'),
        m('fieldset', m('label.check',
            m('input[type=checkbox]', { checked: data.has_ero, oninput: ev => data.has_ero = ev.target.checked }),
            ' Contains erotic scenes (*)', HelpButton('has_ero'),
        )),
        Help('has_ero',
            m('p',
                'Not all 18+ titles have erotic content and not all sub-18+ titles are free of it, ',
                'hence the presence of a checkbox which signals that the game contains erotic content. ',
                'Refer to the ', m('a[href=/d3#2.1][target=_blank]', 'detailed guidelines'), ' for what should (not) be considered "erotic scenes".'
            ),
            m('p',
                '*) The censoring and erotic scene animation fields are only available for releases that contain erotic scenes. ',
                'These fields are automatically reset on form submission when the checkbox is unset.'
            ),
        ),
        m('fieldset',
            m('label[for=minage]', 'Age rating', HelpButton('minage')),
            m(Select, { id: 'minage', class: 'mw', data, field: 'minage', options: [[ null, 'Unknown' ]].concat(vndbTypes.ageRating) }),
        ),
        Help('minage',
            m('p',
                'The minimum official age rating for the release. For most releases, this is specified on the packaging or on product web pages. ',
                'For indie or doujin projects, this is usually a recommended age stated by a developer or publisher. ',
            ),
            m('p', 'ONLY use official sources for this field - don\'t just assume "All ages" just because there\'s no erotic content!'),
        ),
        m('fieldset',
            m('label[for=released]', 'Release date'),
            m(RDate, { id: 'released', value: data.released, oninput: v => data.released = v }),
        ),
    );
    return {view};
}


const Format = initVnode => {
    const {data} = initVnode.attrs;

    let unknownMedia = data.id && data.media.length == 0;
    let unknownPlat = data.id && data.platforms.length == 0;
    const plat = new DS(DS.New(DS.Platforms,
        id => ({id: '_unk_'}),
        obj => 'Unknown',
    ), {
        checked: ({id}) => (id === '_unk_' && unknownPlat) || !!data.platforms.find(p => p.platform === id),
        onselect: ({id},sel) => {
            if (id === '_unk_') {
                unknownPlat = sel;
                if (sel) data.platforms = [];
            } else {
                if (sel) {
                    data.platforms.push({platform:id});
                    unknownPlat = false;
                } else data.platforms = data.platforms.filter(p => p.platform !== id)
            }
        },
        checkall: () => data.platforms = vndbTypes.platform.map(([platform]) => ({platform})),
        uncheckall: () => data.platforms = [],
    });
    const media = Object.fromEntries(vndbTypes.medium.map(([id,label,qty]) => [id,{label,qty}]));

    const engines = new DS(DS.New(DS.Engines,
        id => ({id}),
        obj => m('em', obj.id ? 'Add new engine: ' + obj.id : 'Empty / unknown'),
    ), { more: true });

    const resoParse = str => {
        const v = str.toLowerCase().replace(/\*/g, 'x').replace(/×/g, 'x').replace(/[-\s]+/g, '');
        if (v === '' || v === 'unknown') return [0,0];
        if (v === 'nonstandard') return [0,1];
        const a = /^([0-9]+)x([0-9]+)$/.exec(v);
        if (!a) return null;
        const r = [Math.floor(a[1]), Math.floor(a[2])];
        return r[0] > 0 && r[0] <= 32767 && r[1] > 0 && r[1] <= 32767 ? r : null;
    };
    const resoFmt = (x,y) => x ? x+'x'+y : y ? 'Non-standard' : '';

    const resolutions = new DS(DS.New(DS.Resolutions,
        str => { const r = resoParse(str); return r ? {id:resoFmt(...r)} : null },
        obj => m('em', obj.id ? 'Custom resolution: ' + resoFmt(...resoParse(obj.id)) : 'Empty / unknown'),
    ), { more: true });
    const resolution = {v:resoFmt(data.reso_x,data.reso_y)};

    const view = () => m('fieldset.form',
        m('legend', 'Format'),
        m('fieldset',
            m('label', { class: !unknownPlat && data.platforms.length === 0 ? 'invalid' : null }, 'Platforms'),
            m(DS.Button, { class: 'xw', ds: plat, invalid: !unknownPlat && data.platforms.length === 0 },
                unknownPlat ? 'Unknown' : data.platforms.length === 0 ? 'No platforms selected' :
                data.platforms.map(p => m('span.nowrap', PlatIcon(p.platform), vndbTypes.platform.find(([x]) => x === p.platform)[1])).intersperse(' '),
            ),
        ),
        m('fieldset',
            m('label[for=addmedia]', { class: !unknownMedia && data.media.length === 0 ? 'invalid' : null }, 'Media'),
            data.media.length == 0 && !unknownMedia ? m('p.invalid', 'No media selected.') : null,
            data.media.map(x => m('div',
                m(Button.Del, { onclick: () => data.media = data.media.filter(y => x !== y) }), ' ',
                m(Select, { class: media[x.medium].qty ? 'sw' : 'sw invisible', data: x, field: 'qty', options: range(1, 40).map(i=>[i,i]).concat([[0, 'Unknown quantity']]) }), ' ',
                media[x.medium].label, m('br'),
            )),
            m(Select, {
                class: 'mw', id: 'addmedia', value: unknownMedia ? 'unk' : null,
                oninput: v => {
                    if (v === 'unk') unknownMedia = true;
                    else if (v !== null) {
                        data.media.push({medium: v, qty:1});
                        unknownMedia = false;
                    }
                },
                options: [[null, '- Add medium -']].concat(data.media.length === 0 ? [['unk', 'Unknown']] : []).concat(vndbTypes.medium)
            }),
            data.media.anyDup(({medium,qty}) => [medium, media[medium].qty ? qty : null])
            ?  m('p.invalid', 'List contains duplicates') : null,
        ),
        m('fieldset',
            m('label[for=engine]', 'Engine'),
            m(DS.Input, { id: 'engine', class: 'mw', maxlength: 50, ds: engines, data, field: 'engine', onfocus: ev => ev.target.select() }),
        ),
        data.patch ? null : m('fieldset',
            m('label[for=resolution]', 'Resolution'),
            m(DS.Input, {
                id: 'resolution', class: 'mw', data: resolution, field: 'v', ds: resolutions,
                placeholder: 'width x height',
                onfocus: ev => ev.target.select(),
                oninput: v => { const r = resoParse(v); data.reso_x = r?r[0]:0; data.reso_y = r?r[1]:0; },
                invalid: resoParse(resolution.v) ? null : 'Invalid resolution, expected format is "{width}x{height}".',
            }),
        ),
        data.patch ? null : m('fieldset',
            m('label[for=voiced]', 'Voiced'),
            m(Select, { id: 'voiced', class: 'mw', data, field: 'voiced', options: vndbTypes.voiced.map((l,i)=>[i,l]) }),
        ),
        data.has_ero ? m('fieldset',
            m('label[for=uncensored]', 'Censoring'),
            m(Select, { id: 'uncensored', class: 'mw', data, field: 'uncensored', options: [
                [ null,  'Unknown' ],
                [ false, 'Censored graphics' ],
                [ true,  'Uncensored graphics' ],
            ]}),
        ) : null,
    );
    return {view};
};


const DRM = initVnode => {
    const {data} = initVnode.attrs;
    const ds = new DS(DS.New(DS.DRM,
        id => id.length > 0 && id.length <= 128 ? {id,create:true} : null,
        obj => m('em', 'Add new DRM: ' + obj.id),
    ), {
        more: true,
        placeholder: 'Search or add new DRM',
        props: obj =>
            obj.state === 2 ? { selectable: false } :
            data.drm.find(d => d.name === obj.id) ? { selectable: false, append: m('small', ' (already listed)') } : {},
        onselect: obj => data.drm.push({ create: obj.create, name: obj.id, ...Object.fromEntries(vndbTypes.drmProperty.map(([id])=>[id,false])) }),
    });
    const view = () => m('fieldset.form',
        m('legend', 'DRM'),
        m('table', data.drm.map(d => m('tr',
            m('td', m(Button.Del, {onclick: () => data.drm = data.drm.filter(x => x !== d)})),
            m('td.nowrap', d.create ? d.name : m('a[target=_blank]', { href: '/r/drm?s='+encodeURIComponent(d.name) }, d.name)),
            m('td.lw',
                m(Input, { class: 'lw', placeholder: 'Notes (optional)', data: d, field: 'notes' }),
                !d.create ? [] : [
                    m('br'),
                    m('strong', 'New DRM implementation will be added when you submit the form.'),
                    m('br'),
                    'Please check the properties that apply:',
                    vndbTypes.drmProperty.map(([id,name]) => [ m('br'), m('label.check',
                        m('input[type=checkbox]', { checked: d[id], oninput: ev => d[id] = ev.target.checked }),
                        ' ', name
                    )]),
                    m('br'),
                    m(Input, {class: 'lw', rows: 2, type: 'textarea', data: d, field: 'description', placeholder: 'Description (optional)'}),
                ],
            ),
        ))),
        m(DS.Button, {ds}, 'Add DRM'),
    );
    return {view};
};


const Animation = initVnode => {
    const {data} = initVnode.attrs;
    const hasAni = v => v !== null && v !== 0 && v !== 1;
    let some = hasAni(data.ani_story_sp) || hasAni(data.ani_story_cg) || hasAni(data.ani_cutscene)
            || hasAni(data.ani_ero_sp)   || hasAni(data.ani_ero_cg)
            || (data.ani_face !== null && data.ani_face)
            || (data.ani_bg   !== null && data.ani_bg);

    const flagmask = 4+8+16+32;
    const freqmask = 256+512;
    const lbl = (key, bit, name) => m('label.check',
        { class: data[key] === null || data[key] === bit || (bit > 2 && data[key] > 2) ? null : 'grayedout' },
        m('input[type=checkbox]', {
            checked: data[key] === bit || (bit > 2 && (data[key] & bit) > 0),
            onclick: ev => data[key] = bit <= 2
                ? (ev.target.checked ? bit : null)
                : (ev.target.checked ? ((data[key]||0) & ~3) | bit : ((data[key]||0) & flagmask) === bit ? null : ((data[key]||0) & ~bit))
        }),
        ' ', name, m('br')
    );
    const ani = (key, na) => ([
        key === 'ani_cutscene' ? null : lbl(key, 0, 'Not animated'),
        lbl(key,  1, na),
        lbl(key,  4, 'Hand drawn'),
        lbl(key,  8, 'Vectorial'),
        lbl(key, 16, '3D'),
        lbl(key, 32, 'Live action'),
        key === 'ani_cutscene' || data[key] === null || data[key] <= 2 ? null : m(Select, { class: 'mw',
            oninput: v => data[key] = (data[key] & ~freqmask) | v,
            value: data[key] & freqmask,
            options: [ [0, '- frequency -'], [256, 'Some scenes'], [512, 'All scenes'] ]
        }),
    ]);

    const view = () => data.patch ? null : m('fieldset.form',
        m('legend', 'Animation'),
        m('fieldset',
            m('label', 'Preset'),
            m('label.check',
                m('input[type=radio]', { checked: !some && data.ani_face === null, onclick: () => { some = false; Object.assign(data, {
                    ani_story_sp: null, ani_story_cg: null, ani_cutscene: null,
                    ani_ero_sp: null, ani_ero_cg: null, ani_face: null, ani_bg: null
                })}}),
                ' Unknown'
            ),
            ' / ',
            m('label.check',
                m('input[type=radio]', { checked: !some && data.ani_face === false, onclick: () => { some = false; Object.assign(data, {
                    ani_story_sp: 0, ani_story_cg: 0, ani_cutscene: 1,
                    ani_ero_sp: data.has_ero ? 1 : null, ani_ero_cg: data.has_ero ? 0 : null,
                    ani_face: false, ani_bg: false
                })}}),
                ' No animation'
            ),
            ' / ',
            m('label.check',
                m('input[type=radio]', { checked: some, onclick: () => some = true }),
                ' Some animation'
            ),
        ),
        !some ? [] : [
        m('fieldset',
            m('label', 'Story scenes'),
            m('table.release-animation', m('tr',
                m('td', m('strong', 'Character sprites:'), m('br'), ani('ani_story_sp', 'No sprites')),
                m('td', m('strong', 'CGs:'), m('br'), ani('ani_story_cg', 'No CGs')),
                m('td', m('strong', 'Cutscenes:'), m('br'), ani('ani_cutscene', 'No cutscenes')),
            )),
        ),
        data.has_ero ? m('fieldset',
            m('label', 'Erotic scenes'),
            m('table.release-animation', m('tr',
                m('td', m('strong', 'Character sprites:'), m('br'), ani('ani_ero_sp', 'No sprites')),
                m('td', m('strong', 'CGs:'), m('br'), ani('ani_ero_cg', 'No CGs')),
            )),
        ) : null,
        m('fieldset',
            m('label', 'Effects'),
            m('table',
                m('tr', m('td', 'Character lip movement and/or eye blink:'), m('td',
                    m('label.check', m('input[type=radio]', { checked: data.ani_face === null,  onclick: () => data.ani_face = null  }), ' Unknown or N/A'), ' / ',
                    m('label.check', m('input[type=radio]', { checked: data.ani_face === false, onclick: () => data.ani_face = false }), ' No'), ' / ',
                    m('label.check', m('input[type=radio]', { checked: data.ani_face === true,  onclick: () => data.ani_face = true  }), ' Yes'),
                )),
                m('tr', m('td', 'Background effects:'), m('td',
                    m('label.check', m('input[type=radio]', { checked: data.ani_bg === null,  onclick: () => data.ani_bg = null  }), ' Unknown or N/A'), ' / ',
                    m('label.check', m('input[type=radio]', { checked: data.ani_bg === false, onclick: () => data.ani_bg = false }), ' No'), ' / ',
                    m('label.check', m('input[type=radio]', { checked: data.ani_bg === true,  onclick: () => data.ani_bg = true  }), ' Yes'),
                )),
            ),
        ),
        ]
    );
    return {view};
};


const VNs = initVnode => {
    const {data} = initVnode.attrs;
    const ds = new DS(DS.VNs, {
        onselect: obj => {
            data._vn_added = true;
            data.vn.push({vid: obj.id, title: obj.title, rtype: 'complete' });
        },
        props: obj => data.vn.find(v => v.vid === obj.id) ? { selectable: false, append: m('small', ' (already listed)') } : {},
    });
    const view = () => m('fieldset',
        m('label', 'Visual novels'),
        data.vn.length === 0
        ? m('p.invalid', 'No visual novels selected.')
        : m('table', data.vn.map(v => m('tr', {key: v.vid},
            m('td',
                m(Button.Del, { onclick: () => data.vn = data.vn.filter(x => x !== v) }), ' ',
                m(Select, { data: v, field: 'rtype', options: vndbTypes.releaseType }),
            ),
            m('td', m('small', v.vid, ': '), m('a[target=_blank]', { href: '/'+v.vid }, v.title)),
        ))),
        m(DS.Button, { ds, class: 'mw' }, 'Add visual novel'),
    );
    return {view};
};


const Producers = initVnode => {
    const {data} = initVnode.attrs;
    const ds = new DS(DS.Producers, {
        onselect: obj => data.producers.push({pid: obj.id, name: obj.name, developer: data.official, publisher: true }),
        props: obj => data.producers.find(p => p.pid === obj.id) ? { selectable: false, append: m('small', ' (already listed)') } : {},
    });
    const view = () => m('fieldset',
        m('label', 'Producers'),
        m('table', data.producers.map(p => m('tr', {key: p.pid},
            m('td',
                m(Button.Del, { onclick: () => data.producers = data.producers.filter(x => x !== p) }), ' ',
                !(data.official || p.developer) ? null : m(Select, {
                    oninput: v => { p.developer = v[0]; p.publisher = v[1] },
                    value: [p.developer,p.publisher],
                    options: [
                        [ [true, false], 'Developer' ],
                        [ [false, true], 'Publisher' ],
                        [ [true, true ], 'Both' ],
                    ],
                }),
            ),
            m('td', m('small', p.pid, ': '), m('a[target=_blank]', { href: '/'+p.pid }, p.name)),
        ))),
        m(DS.Button, { ds, class: 'mw' }, 'Add producer'),
    );
    return {view};
};


const Supersedes = initVnode => {
    const {data} = initVnode.attrs;
    const ds = new DS(DS.Releases(data.vnreleases), {
        onselect: obj => data.supersedes.push({rid: obj.id}),
        props: obj => data.supersedes.find(r => r.rid === obj.id) ? { selectable: false, append: m('small', ' (already listed)') } : {},
    });
    const view = () => [ m('fieldset',
        m('label', 'Supersedes', HelpButton('supersedes')),
        m('table', data.supersedes.map(({rid}) => m('tr',
            m('td', m(Button.Del, { onclick: () => data.supersedes = data.supersedes.filter(x => x.rid !== rid) })),
            m('td', (r => !r ? [
                m('a[target=_blank]', { href: '/'+rid }, rid),
                m('b.invalid', ' deleted or moved release.'),
            ] : Release(r))(data.vnreleases.find(r => r.id === rid))),
        ))),
        m(DS.Button, { ds, class: 'mw' }, 'Add release'),
    ), Help('supersedes',
        m('p',
            'List of other releases that are superseded/replaced by this release. ',
            'In other words, the current release is an updated version of the other releases listed here.',
        ),
        m('p',
            'Only add direct relations: if release A is superseded by release B ',
            'and release B is superseded by the current release, only release B should be listed here. ',
            'Release A in turn should be mentioned as "Supersedes" in release B.',
        ),
        m('p',
            'This feature should only be used to mark releases from the same publisher. ',
            'For example, an official release that adds a new language supersedes any older releases with fewer languages by the same publisher, ',
            'but an unofficial translation project never supersedes an official release.',
        ),
    ) ];
    return {view};
};


const Images = initVnode => {
    const {data} = initVnode.attrs;
    let addsrc = null;

    const vnimages = () => data.vnimages.filter(i => !data.images.find(x => x.img === i.id));
    const langs = Object.fromEntries(vndbTypes.language);

    const thumbsize = img => img.width > img.height ? { width: 150, height: img.height * (150/img.width) } : { height: 150, width: img.width * (150/img.height) };
    const thumburl = img => imgurl(img.id, img.width <= 256 && img.height <= 400 ? null : 't');
    const Thumb = { view: v => m(IVLink, { img: v.attrs.img },
        m('img', {...thumbsize(v.attrs.img), src: thumburl(v.attrs.img)})
    ) };

    // Filter out image types
    // - physical options only available when the release has the appropriate media
    const imgTypes = cur => vndbTypes.releaseImageType.filter(([t]) => cur === t || t == 'dig' || (
        (data.media.length === 0 || data.media.find(e => e.medium !== 'in') || !t.match(/^pkg/))
    ));
    const addImg = nfo => {
        const vns = nfo.entries.filter(e => e.id.match(/^v/));
        const vid = data.vn.length > 1 && vns.length === 1 ? vns[0].id : null;
        const typ = imgTypes(null);
        const itype = typ.length === 1 ? typ[0][0] : vns.length > 0 && typ.find(([t]) => t === 'pkgfront') ? 'pkgfront' : null;
        data.images.push({img: nfo.id, nfo, vid, itype, lang: []});
        addsrc = null;
    };

    const imageApi = new Api('Image');
    const imageData = {id:''};
    const imageSubmit = ev => {
        ev.stopPropagation();
        ev.preventDefault();
        const d = {id: imagePatternId('cv', imageData.id)};
        imageApi.call(d, nfo => {
            if (data.images.find(x => x.img === nfo.id))
                imageApi.error = 'Image already selected.';
            else {
                imageData.id = '';
                addImg(nfo);
            }
        });
    };

    const uploadApi = new Api('ImageUpload');
    let uploadQueue = [];
    const uploadOne = () => {
        const form = new FormData();
        form.append('type', 'cv');
        form.append('img', uploadQueue.shift());
        uploadApi.call(form, r => {
            addImg(r);
            if (uploadQueue.length > 0) uploadOne();
        });
    };
    const uploadSubmit = ev => {
        ev.stopPropagation();
        ev.preventDefault();
        uploadQueue = [...$('#file').files];
        if (!uploadQueue.length)
            uploadApi.error = 'No file selected';
        else
            uploadOne();
    };

    const view = () => !data.official ? [
        m('p', 'This release has not been marked as "official". We currently do not allow images for unofficial releases.')
    ] : [ m('fieldset.form',
        m('legend', 'Images'),
        data.images.length === 0
        ? m('p', 'No images assigned to this release.')
        : m('table.full.stripe[style=width:100%]', m('tbody', data.images.map(e => m('tr', {key: e.img},
            m('td[style=text-align:right;width:170px]', m(Thumb, {img:e.nfo})),
            m('td',
                m('p',
                    m(Button.Del, { onclick: () => data.images = data.images.filter(x => e !== x) }),
                    ' ', m('small', e.img, ' / '), e.nfo.width, 'x', e.nfo.height,
                ),
                data.media.length === 0 ?  m('p.invalid', 'Please set a medium for this release in the "General info" tab.') : m('div',
                    m(Select, { data: e, field: 'itype', class: 'lw', options: [[null, '-- Type --']].concat(imgTypes(e.itype)) }),
                    typeof e.itype !== 'string' ? m('p.invalid', 'Type is required.') : !imgTypes(null).find(([x]) => x === e.itype) ? m('p.invalid', 'Invalid type for the release medium.') : null,
                    e.itype === 'dig' ? [] : [ m('br'), m('label.check',
                        m('input[type=checkbox]', { checked: e.photo, oninput: ev => e.photo = ev.target.checked }),
                        ' This is a photo.',
                    ) ],
                ),
                data.vn.length <= 1 ? [] : [
                    m('br'),
                    m(Select, {
                        data: e, field: 'vid', class: 'xw',
                        options: [[null, '-- not specific to a VN --']].concat(data.vn.map(v => [v.vid, v.title])),
                    }),
                ],
                data.titles.length <= 1 ? [] : [
                    m('br'),
                    data.titles.map(t => m('label.check',
                        m('input[type=checkbox]', {
                            checked: e.lang.includes(t.lang),
                            onclick: ev => ev.target.checked ? e.lang.push(t.lang) : (e.lang = e.lang.filter(x => x !== t.lang))
                        }), ' ', LangIcon(t.lang), langs[t.lang]
                    )).intersperse(' / '),
                ],
                m(ImageFlag, { img: e.nfo }),
            ),
        )))),
    ), m('fieldset.form',
        m('legend', 'Add image'),
        m('fieldset',
            m('label[for=file]', 'File upload', HelpButton('imgupl')),
            m(Form, { onsubmit: uploadSubmit },
                m('input#file[type=file][required][multiple]', { accept: imageAccept, oninput: uploadSubmit }),
                uploadApi.Status(),
            ),
        ),
        Help('imgupl', m('p', imageFormats)),
        m('fieldset', m('label', m('small', '-- or --'))),
        m('fieldset',
            m('label[for=imgid]', 'Image ID', HelpButton('imgid')),
            m(Form, { onsubmit: imageSubmit, api: imageApi },
                m(Input, { id: 'imgid', class: 'lw', data: imageData, field: 'id', pattern: imagePattern('cv'), oninput: () => imageApi.abort() }),
                m('button[type=submit]', 'Add'),
                imageApi.Status(),
            ),
        ), Help('imgid',
            m('p', 'Select an image that is already on the server. Supported formats:'),
            m('ul',
                m('li', 'cv###'),
                m('li', location.origin+'/cv###'),
                m('li', imgurl('cv7432').replace('/32/7432', '/##/###')),
            ),
        ),
        m('fieldset', m('label', m('small', '-- or --'))),
        m('fieldset',
            m('label', 'Related image'),
            m('details',
                m('summary', 'Select an image from another release'),
                data._vn_added ? m('p', 'Images associated with VN(s) that you just added in the "General info" tab do not yet show up here, you can use the "Image ID" selector instead.') : null,
                vnimages().length === 0 ? m('p', 'No (more) images associated with this visual novel.') : m('table', vnimages().map(img => m('tr',
                    m('td[style=text-align:right]', m(Thumb, {img})),
                    m('td',
                        m('button[type=button]', { onclick: () => addImg(img) }, 'Select image'),
                        m('p', img.width, 'x', img.height),
                        m('p', 'Used for:'),
                        img.entries.map(e => m('p',
                            e.id.match(/^v/) ? 'VN: ' : 'Release: ',
                            m('small', e.id, ' / '),
                            m('a[target=_blank]', { href: '/'+e.id }, e.title),
                            // TODO: Type would be nice to include here
                        )),
                    ),
                ))),
            ),
        ),
    ) ];
    return {view};
};


widget('ReleaseEdit', initVnode => {
    const data = initVnode.attrs.data;
    const api = new Api('ReleaseEdit');
    const gtin = {v: data.gtin === '0' ? '' : data.gtin};

    // Lazy port of VNDB::Func::gtintype()
    const validateGtin = v => {
        if (!/^[0-9]{10,13}$/.test(v)) return false;
        v = v.padStart(13, '0'); // GTIN-13

        const n = v.split('').reverse();
        let check = +n.shift();
        n.forEach((v,i) => check += v * ((i % 2) !== 0 ? 1 : 3));
        if ((check % 10) !== 0) return false;

        if (/^4[59]/.test(v)) return true;
        if (/^(?:0[01]|0[6-9]|13|75[45])/.test(v)) return true;
        if (/^97[89]/.test(v)) return true;
        if (/^(?:0[2-5]|2|9[6-9])/.test(v)) return false;
        return true;
    };

    const geninfo = () => [
        m('h1', 'General info'),
        m(Titles, {data}),
        m(Status, {data}),
        m(Format, {data}),
        m(DRM, {data}),
        m(Animation, {data}),
        m('fieldset.form',
            m('legend', 'External identifiers & links'),
            m('fieldset',
                m('label[for=gtin]', 'JAN/UPC/EAN/ISBN'),
                m(Input, {
                    id: 'gtin', class: 'mw', type: 'number', data: gtin, field: 'v',
                    oninput: v => { data.gtin = v; gtin.v = v === 0 ? '' : v },
                    invalid: data.gtin !== '' && data.gtin !== '0' && data.gtin !== 0 && !validateGtin(String(data.gtin)) ? 'Invalid JAN/UPC/EAN/ISBN code.' : '',
                }),
            ),
            m('fieldset',
                m('label[for=catalog]', 'Catalog number'),
                m(Input, { id: 'catalog', class: 'mw', maxlength: 50, data, field: 'catalog' }),
            ),
            m('fieldset',
                m('label[for=website]', 'Website'),
                m(Input, { id: 'website', class: 'xw', type: 'weburl', data, field: 'website' }),
            ),
            m(ExtLinks, {type: 'release', data}),
        ),
        m('fieldset.form',
            m('legend', 'Database relations'),
            m(VNs, {data}),
            m(Producers, {data}),
            m(Supersedes, {data}),
        ),
        m('fieldset.form',
            m('label[for=notes]', 'Notes'),
            m(TextPreview, {
                data, field: 'notes',
                header: m('b', '(English please!)'),
                attrs: { id: 'notes', rows: 5, maxlength: 10240 },
            }),
        ),
    ];

    const tabs = [
        [ 'gen', 'General info', geninfo ],
        [ 'img', 'Images', () => [ m('h1', 'Images'), m(Images, {data}) ] ],
    ];

    const view = () => m(Form, {api, onsubmit: () => api.call(data)},
        m(FormTabs, {tabs}),
        m(EditSum, {data,api}),
    );
    return {view};
});
