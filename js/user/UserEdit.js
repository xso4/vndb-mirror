const DSTimeZone = {
    list: (src, str, cb) => cb(timeZones.filter(z => z.toLowerCase().includes(str)).map(id => ({id}))),
    view: ({id}) => {
        const [,region,place] = id.replace('_', ' ').match(/([^\/]+)\/(.+)/) || [0,'',id];
        return [ region ? m('small', region, ' / ') : null, place ];
    },
};

const Username = () => {
    let edit = false, old = '';
    return {view: v => m('fieldset.form',
        m('legend', 'Username'),
        m('fieldset', !edit ? [
            m('label', 'Current'),
            v.attrs.data.username,
            ' ',
            v.attrs.data.username_throttled
            ? m('small', '(changed within the past 24 hours)')
            : m('input[type=button][value=Edit]', { onclick: () => { old = v.attrs.data.username; edit = true } }),
        ] : [
            m('label[for=username]', 'New username'),
            m('input#username.mw[type=text]', {
                oninput: e => {
                    v.attrs.data.username = e.target.value;
                    e.target.setCustomValidity('');
                },
                oncreate: n => {
                    n.dom.value = v.attrs.data.username;
                    n.dom.focus();
                },
                ...formVals.username }),
            m('input[type=button][value=Cancel]', { onclick: () => { v.attrs.data.username = old; edit = false } }),
            m('p',
                'Things to keep in mind:', m('br'),
                '- Your old username(s) will be displayed on your profile for a month after the change.', m('br'),
                '- You will not be able to log in with your old username(s).', m('br'),
                '- Your old username will become available for other people to claim.', m('br'),
                '- You may only change your username at once per day.',
            ),
        ]),
    )};
};

const Email = () => {
    let edit = false, old = '';
    return {view: v => m('fieldset.form',
        m('legend', 'E-Mail'),
        m('fieldset', !edit ? [
            m('label', 'Current'), v.attrs.data.email, ' ',
            m('input[type=button][value=Edit]', { onclick: () => { old = v.attrs.data.email; edit = true } }),
        ] : [
            m('label[for=email]', 'New email'),
            m('input#email.mw[type=text]', {
                oninput: e => {
                    v.attrs.data.email = e.target.value;
                    e.target.setCustomValidity('');
                },
                oncreate: n => {
                    n.dom.value = v.attrs.data.email;
                    n.dom.focus();
                },
                ...formVals.email }),
            m('input[type=button][value=Cancel]', { onclick: () => { v.attrs.data.email = old; edit = false } }),
            m('p', 'A verification mail will be send to your new address.'),
        ]),
    )};
};

const Password = () => {
    let edit = false, repeat = '';
    return {view: v => m('fieldset.form',
        m('legend', 'Password'),
        m('label.check',
            m('input[type=checkbox]', { oninput: e => {
                edit = e.target.checked;
                if (!edit) {
                    v.attrs.data.password = null;
                    repeat = '';
                } else
                    v.attrs.data.password = { old: '', new: '' };
            }}),
            ' Change password'
        ),
        !edit ? [] : [
            m('fieldset',
                m('label[for=opass]', 'Current password'),
                m('input#opass.mw[type=password]', {
                    oninput: e => {
                        v.attrs.data.password.old = e.target.value;
                        e.target.setCustomValidity('');
                    },
                    oncreate: v => v.dom.focus(),
                    ...formVals.password
                }),
            ),
            m('fieldset',
                m('label[for=npass]', 'New password'),
                m('input#npass.mw[type=password]', {
                    oninput: e => {
                        v.attrs.data.password.new = e.target.value;
                        e.target.setCustomValidity('');
                    },
                    ...formVals.password
                }),
            ),
            m('fieldset',
                m('label[for=rpass]', 'Repeat'),
                m('input#rpass.mw[type=password]', {
                    oninput: e => repeat = e.target.value,
                    onupdate: n => n.dom.setCustomValidity(v.attrs.data.password.new === repeat ? '' : 'Passwords do not match.'),
                    ...formVals.password
                }),
            ),
        ]
    )};
};

const Support = initVnode => {
    const data = initVnode.attrs.data;
    return {view: () => data.editor_usermod || data.nodistract_can || data.support_can || data.uniname_can || data.pubskin_can ? m('fieldset.form',
        m('legend', 'Supporter options⭐'),
        data.editor_usermod ? m('p',
            'Enabled options: ' + (['nodistract', 'support', 'uniname', 'pubskin'].filter(x => data[x+'_can']).join(', ')||'none') + '.'
        ) : null,
        data.editor_usermod || data.nodistract_can ? m('fieldset',
            m('label.check',
                m('input[type=checkbox]', { checked: data.nodistract_noads, oninput: e => data.nodistract_noads = e.target.checked }),
                ' Disable advertising and other distractions (only hides the support box for the moment)',
            ),
            m('br'),
            m('label.check',
                m('input[type=checkbox]', { checked: data.nodistract_nofancy, oninput: e => data.nodistract_nofancy = e.target.checked }),
                ' Disable supporters badges, custom display names and profile skins',
            ),
        ) : null,
        data.editor_usermod || data.support_can ? m('fieldset',
            m('label.check',
                m('input[type=checkbox]', { checked: data.support_enabled, oninput: e => data.support_enabled = e.target.checked }),
                ' Display my supporters badge',
            )
        ) : null,
        data.editor_usermod || data.pubskin_can ? m('fieldset',
            m('label.check',
                m('input[type=checkbox]', { checked: data.pubskin_enabled, oninput: e => data.pubskin_enabled = e.target.checked }),
                ' Apply my skin and custom CSS when others visit my profile',
            )
        ) : null,
        data.editor_usermod || data.uniname_can ? m('fieldset',
            m('label[for=uniname]', 'Display name'),
            m('input#uniname[type=text][pattern=^.{2,15}$]', {
                value: data.uniname,
                placeholder: data.username,
                oninput: e => { e.target.setCustomValidity(''); data.uniname = e.target.value },
            }),
            m('p', 'Between 2 and 15 characters, all unicode characters are accepted.'),
        ) : null,
    ) : null};
};

const Traits = initVnode => {
    const data = initVnode.attrs.data;
    const lookup = Object.fromEntries(data.traits.map(x => [x.tid,true]));
    const ds = new DS(DS.Traits, {
        props: obj =>
            lookup[obj.id]
            ? { selectable: false, append: m('small', ' (already listed)') }
            : obj.hidden ? null : { selectable: obj.applicable },
        onselect: obj => {
            lookup[obj.id] = true;
            data.traits.push({ tid: obj.id, group: obj.group_name, name: obj.name });
        },
    });
    return {view: () => m('fieldset.form',
        m('label', 'Traits'),
        m('p', 'You can add up to 100 ', m('a[href=/i][target=_blank]', 'character traits'), ' to your account. These are displayed on your public profile.'),
        m('table.stripe',
            m('tbody', data.traits.map(t => m('tr', { key: t.tid },
                m('td', m(Button.Del, {onclick: () => {
                    delete lookup[t.tid];
                    data.traits = data.traits.filter(x => x.tid !== t.tid);
                }})),
                m('td', t.group ? m('small', t.group, ' / ') : null, m('a[target=_blank]', { href: '/'+t.tid }, t.name)),
            ))),
            m('tfoot', m('tr', m('td[colspan=2]',
                data.traits.length >= 100
                ? 'Maximum number of traits reached.'
                : m('input[type=button][value=Add trait]', { onclick: ds.open })
            ))),
        ),
    )}
};


const Titles = initVnode => {
    const lst = initVnode.attrs.lst;
    const langs = Object.fromEntries(vndbTypes.language);
    const nonlatin = Object.fromEntries(vndbTypes.language.filter(l => !l[2]).map(l => [l[0],true]).concat([['',true]]));
    const ds = new DS(DS.Lang, { onselect: obj => {
        const o = lst.pop();
        lst.push({lang: obj.id, latin: false, official: true });
        lst.push(o);
    }});
    return {view: () => m('table.stripe',
        m('tbody', lst.map((t,n) => m('tr',
            m('td', '#'+(n+1)),
            m('td', t.lang ? [LangIcon(t.lang), langs[t.lang]] : ['Original language']),
            m('td', nonlatin[t.lang || ''] ? m('label',
                m('input[type=checkbox]', { checked: t.latin, oninput: ev => t.latin = ev.target.checked }),
                ' romanized'
            ) : null),
            m('td', t.lang ? m('select.mw', { oninput: ev => t.official = [null, true, false][ev.target.selectedIndex] },
                m('option', { selected: t.official === null  }, 'Original only'),
                m('option', { selected: t.official === true  }, 'Official only'),
                m('option', { selected: t.official === false }, 'Any'),
            ) : null),
            m('td',
                m(Button.Up, {visible: t.lang && n > 0, onclick: () => {
                    lst[n] = lst[n-1];
                    lst[n-1] = t;
                }}),
                m(Button.Down, {visible: n < lst.length-2, onclick: () => {
                    lst[n] = lst[n+1];
                    lst[n+1] = t;
                }}),
                m(Button.Del, {visible: !!t.lang, onclick: () => lst.splice(n,1)}),
            ),
        ))),
        m('tfoot', m('tr', m('td[colspan=5]',
            lst.length >= 5 ? null
            : m('input[type=button][value=Add language]', {onclick: ds.open}),
        )))
    )};
};

const display = data => {
    const tz = new DS(DSTimeZone, { onselect: ({id}) => data.timezone = id });
    const brtz = (e => timeZones.includes(e) && e)(window.Intl && Intl.DateTimeFormat().resolvedOptions().timeZone);

    const vl = new DS(DS.Lang, {
        checked: ({id}) => data.vnrel_langs.includes(id),
        onselect: ({id},sel) => {if (sel) data.vnrel_langs.push(id); else data.vnrel_langs = data.vnrel_langs.filter(x => x !== id)},
        checkall: () => data.vnrel_langs = vndbTypes.language.map(([x])=>x),
        uncheckall: () => data.vnrel_langs = [],
    });
    let vlangs = data.vnrel_langs || [];

    const sl = new DS(DS.Lang, {
        checked: ({id}) => data.staffed_langs.includes(id),
        onselect: ({id},sel) => {if (sel) data.staffed_langs.push(id); else data.staffed_langs = data.staffed_langs.filter(x => x !== id)},
        checkall: () => data.staffed_langs = vndbTypes.language.map(([x])=>x),
        uncheckall: () => data.staffed_langs = [],
    });
    let slangs = data.staffed_langs || [];

    return () => [
        m('h1', 'Display preferences'),
        m('fieldset.form',
            m('legend', 'Global'),
            m('fieldset',
                m('label[for=skin]', 'Skin'),
                m('select#skin.lw', { oninput: ev => {
                        data.skin = vndbSkins[ev.target.selectedIndex][0];
                        (s => s.href = s.href.replace(/[^\/]+\.css/, data.skin+'.css'))($('link[rel=stylesheet]'));
                    } },
                    vndbSkins.map(([id,name]) => m('option', {selected: data.skin === id}, name))
                ), ' ',
                m('label.check', m('input[type=checkbox]', { checked: data.customcss_csum, oninput: ev => data.customcss_csum = ev.target.checked }), 'Custom css'),
            ),
            data.customcss_csum ? m('fieldset',
                m('label[for=customcss]', 'Custom CSS'),
                m('textarea#customcss.xw[rows=5][cols=60]', { oninput: ev => data.customcss = ev.target.value }, data.customcss),
                m('p.grayedout', '(@import statements do not work; future site updates may break your customizations)'),
            ) : null,
            m('fieldset',
                m('label', 'Time zone'),
                m('input.mw[type=button]', { value: data.timezone, onclick: tz.open }),
                ' ', brtz && brtz != data.timezone
                ? m('a[href=#]', { onclick: ev => { ev.preventDefault(); data.timezone = brtz }}, 'Set to '+brtz)
                : null,
                m('p', 'Select the city that is nearest to you in terms of time zone and all dates & times on the site are adjusted.'),
            ),
            m('fieldset',
                m('label', 'Image display'),
                m('label.check', m('input[type=checkbox]',
                    { checked: data.max_sexual === -1, oninput: ev => data.max_sexual = ev.target.checked ? -1 : 0 }),
                    ' Hide all images by default'
                ),
            ),
            data.max_sexual === -1 ? null : m('fieldset',
                'Maximum sexual level:', m('br'),
                m('label.check', m('input[type=radio]', { checked: data.max_sexual === 0, onchange: () => data.max_sexual = 0 }), ' Safe'), m('br'),
                m('label.check', m('input[type=radio]', { checked: data.max_sexual === 1, onchange: () => data.max_sexual = 1 }), ' Suggestive'), m('br'),
                m('label.check', m('input[type=radio]', { checked: data.max_sexual === 2, onchange: () => data.max_sexual = 2 }), ' Explicit'),
            ),
            data.max_sexual === -1 ? null : m('fieldset',
                'Maximum violence level:', m('br'),
                m('label.check', m('input[type=radio]', { checked: data.max_violence === 0, onchange: () => data.max_violence = 0 }), ' Tame'), m('br'),
                m('label.check', m('input[type=radio]', { checked: data.max_violence === 1, onchange: () => data.max_violence = 1 }), ' Violent'), m('br'),
                m('label.check', m('input[type=radio]', { checked: data.max_violence === 2, onchange: () => data.max_violence = 2 }), ' Brutal'),
            ),
            m('fieldset',
                m('label', 'Spoiler level'),
                m('label.check', m('input[type=radio]', { checked: data.spoilers === 0, onchange: () => data.spoilers = 0 }), ' No spoilers'), m('br'),
                m('label.check', m('input[type=radio]', { checked: data.spoilers === 1, onchange: () => data.spoilers = 1 }), ' Minor spoilers'), m('br'),
                m('label.check', m('input[type=radio]', { checked: data.spoilers === 2, onchange: () => data.spoilers = 2 }), ' Major spoilers'),
            ),
        ),
        // XXX: This could *really* use some help text.
        m('fieldset.form',
            m('legend', 'Titles'),
            m('fieldset',
                m('label', 'Title'),
                m(Titles, {lst: data.titles}),
            ),
            m('fieldset',
                m('label', 'Alternative title'),
                m('p', 'The alternative title is used as tooltip for links or displayed next to the main title.'),
                m(Titles, {lst: data.alttitles}),
            )
        ),
        m('fieldset.form',
            m('legend', 'Visual novel pages'),
            m('label', 'Tags'),
            m('fieldset', m('label.check', m('input[type=checkbox]',
                { checked: data.tags_all, onchange: ev => data.tags_all = ev.target.checked },
                ), " Show all tags by default (don't summarize)"
            )),
            m('fieldset',
                'Default tag categories:', m('br'),
                m('label.check', m('input[type=checkbox]', { checked: data.tags_cont, onchange: ev => data.tags_cont = ev.target.checked }), ' Content'), m('br'),
                m('label.check', m('input[type=checkbox]', { checked: data.tags_ero,  onchange: ev => data.tags_ero  = ev.target.checked }), ' Sexual content'), m('br'),
                m('label.check', m('input[type=checkbox]', { checked: data.tags_tech, onchange: ev => data.tags_tech = ev.target.checked }), ' Technical'),
            ),

            m('fieldset',
                m('label', 'Releases'),
                m('label.check', m('input[type=checkbox]',
                    { checked: data.vnrel_langs === null, onchange: ev => {
                        if (ev.target.checked) { vlangs = data.vnrel_langs; data.vnrel_langs = null }
                        else data.vnrel_langs = vlangs
                    }}),
                    ' Expand all languages'
                ),
            ),
            data.vnrel_langs === null ? null : m('fieldset',
                m('input[type=button][value=Select languages]', { onclick: vl.open }),
                data.vnrel_langs.map(LangIcon)
            ),
            m('fieldset',
                data.vnrel_langs === null ? null : m('label.check', m('input[type=checkbox]',
                    { checked: data.vnrel_olang, onchange: ev => data.vnrel_olang = ev.target.checked }),
                    ' Always expand original language', m('br'),
                ),
                m('label.check', m('input[type=checkbox]', { checked: data.vnrel_mtl, onchange: ev => data.vnrel_mtl = ev.target.checked }), ' Expand machine translations'),
            ),

            m('fieldset',
                m('label', 'Staff'),
                m('label.check', m('input[type=checkbox]',
                    { checked: data.staffed_langs === null, onchange: ev => {
                        if (ev.target.checked) { slangs = data.staffed_langs; data.staffed_langs = null }
                        else data.staffed_langs = slangs
                    }}),
                    ' Expand all languages'
                ),
            ),
            data.staffed_langs === null ? null : m('fieldset',
                m('input[type=button][value=Select languages]', { onclick: sl.open }),
                data.staffed_langs.map(LangIcon)
            ),
            m('fieldset',
                data.staffed_langs === null ? null : m('label.check', m('input[type=checkbox]',
                    { checked: data.staffed_olang, onchange: ev => data.staffed_olang = ev.target.checked }),
                    ' Always expand original edition', m('br'),
                ),
                m('label.check', m('input[type=checkbox]', { checked: data.staffed_unoff, onchange: ev => data.staffed_unoff = ev.target.checked }), ' Expand unofficial editions'),
            ),
        ),
        m('fieldset.form',
            m('legend', 'Other pages'),
            m('fieldset',
                m('label', 'Characters'),
                m('label.check', m('input[type=checkbox]',
                    { checked: data.traits_sexual, onchange: ev => data.traits_sexual = ev.target.checked }),
                    ' Display sexual traits by default'
                ),
            ),
            m('fieldset',
                m('label', 'Producers'),
                'Default tab:', m('br'),
                m('label.check', m('input[type=radio]', { checked: !data.prodrelexpand, onchange: () => data.prodrelexpand = false }), ' Visual novels'), m('br'),
                m('label.check', m('input[type=radio]', { checked:  data.prodrelexpand, onchange: () => data.prodrelexpand = true }), ' Releases'),
            ),
        ),
    ];
};

const TTPrefs = initVnode => {
    const {data,prefix} = initVnode.attrs;
    const pref = prefix === 'g' ? 'tagprefs' : 'traitprefs';
    const ds = new DS(prefix === 'g' ? DS.Tags : DS.Traits, {
        onselect: obj => data[pref].push({tid: obj.id, name: obj.name, group: obj.group_name, spoil: null, color: null, childs: true }),
        props: obj => data[pref].find(o => obj.id === o.tid) ? { selectable: false, append: m('small', ' (already listed)') } : {},
    });
    return {view: () => m('fieldset.form',
        m('legend', prefix === 'g' ? 'Tags' : 'Traits'),
        m('table.full.stripe',
            m('tbody', data[pref].map(t => m('tr', {key: t.tid},
                m('td', m(Button.Del, { onclick: () => data[pref] = data[pref].filter(o => o.tid !== t.tid) })),
                m('td',
                    t.group ? m('small', t.group + ' / ') : null,
                    m('a[target=_blank]', { href: '/'+t.tid }, t.name)
                ),
                m('td', m('select.mw', { onchange: ev => t.spoil = [null,0,1,2,3][ev.target.selectedIndex] },
                    m('option', { selected: t.spoil === null }, 'Keep spoiler level'),
                    m('option', { selected: t.spoil === 0    }, 'Always show'),
                    m('option', { selected: t.spoil === 1    }, 'Force minor spoiler'),
                    m('option', { selected: t.spoil === 2    }, 'Force major spoiler'),
                    m('option', { selected: t.spoil === 3    }, 'Always hide'),
                )),
                m('td', t.spoil === 3 ? null : m('select.mw',
                    { onchange: ev => t.color = [null,'standout','grayedout','#ffffff'][ev.target.selectedIndex] },
                    m('option', { selected: t.color === null        }, "Don't highlight"),
                    m('option', { selected: t.color === 'standout'  }, 'Stand out'),
                    m('option', { selected: t.color === 'grayedout' }, 'Grayed out'),
                    m('option', { selected: t.color && t.color.startsWith('#') }, 'Custom color'),
                )),
                m('td', t.spoil === 3 || !t.color || !t.color.startsWith('#') ? null :
                    m('input[type=color]', { value: t.color, oninput: ev => t.color = ev.target.value })
                ),
                m('td', m('label.check',
                    m('input[type=checkbox]', { checked: t.childs, oninput: ev => t.childs = ev.target.checked }),
                    ' also apply to child ', prefix === 'g' ? 'tags' : 'traits',
                )),
            ))),
            m('tfoot', m('tr', m('td[colspan=6]',
                data[pref].length >= 500 ? null
                : m('input[type=button]', {value: prefix === 'g' ? 'Add tag' : 'Add trait', onclick: ds.open})
            ))),
        ),
    )};
};

const applications = data => {
    const api = new Api('UserApi2New');
    const clip = navigator.clipboard;
    let copied;
    return () => [
        m('h1', 'Applications'),
        m('p.description',
            'Here you can create and manage tokens for use with ', m('a[href=/d11][target=_blank]', 'the API'), '.', m('br'),
            "It's strongly recommended that you create a separate token for each application that you use,",
            " so that you can easily change or revoke permissions on a per-application level.", m('br'),
            'Tokens without permissions can still be used for identification.'
        ),
        data.api2.map(t => m('fieldset.form', {key: t.token},
            m('legend', t.notes || (t.token.replace(/-.+/, '')+'-...')),
            t.delete ? [ m('fieldset',
                m('p',
                    'This token is deleted on form submission. ',
                    m('a[href=#]', { onclick: ev => { ev.preventDefault(); t.delete = false } }, 'Undo'), '.'
                ),
            )] : [ m('fieldset',
                m('label', 'Token'),
                m('input.lw.monospace.obscured[type=text][readonly]', {
                    value: t.token,
                    onfocus: ev => { ev.target.select(); ev.target.classList.remove('obscured') },
                    onblur: ev => ev.target.classList.add('obscured'),
                }),
                clip ? m(Button.Copy, { onclick: () => clip.writeText(t.token).then(() => { copied = t.token; m.redraw() }) }) : null,
                copied === t.token ? 'copied!' : null,
            ),
            m('fieldset',
                m('label', 'Name'),
                m('input.mw[type=text][maxlength=200]',
                    { value: t.notes, oninput: ev => t.notes = ev.target.value }
                ), ' (optional, for personal use)'
            ),
            m('fieldset',
                m('label', 'Permissions'),
                m('label.check', m('input[type=checkbox]',
                    { checked: t.listread, oninput: ev => { t.listread = ev.target.checked; if (!t.listread) t.listwrite = false } }),
                    ' Access private items on my list'
                ), m('br'),
                m('label.check', m('input[type=checkbox]',
                    { checked: t.listwrite, oninput: ev => { t.listwrite = ev.target.checked; if (t.listwrite) t.listread = true } }),
                    ' Add/remove/edit items on my list',
                ),
            ),
            m('fieldset',
                m(Button.Del, { onclick: () => t.delete = true }),
                m('small', ' Created on ', t.added, ', ', t.lastused ? 'last used on '+t.lastused : 'never used', '.')
            ),
            ],
        )),
        m('fieldset.form', { disabled: api.loading() },
            m('input[type=button][value=Create new token]', { onclick: () => api.call({id:data.id}, res =>
                res && data.api2.push({token: res.token, added: res.added, notes: '', listread: false, listwrite: false })
            )}),
            api.loading() ? m('span.spinner') : null,
            api.error ? m('b', m('br'), api.error) : null,
        ),
    ];
};

widget('UserEdit', initVnode => {
    let msg = '';
    const data = initVnode.attrs.data;
    const api = new Api('UserEdit');
    const onsubmit = ev => api.call(data, res => {
        msg = !res ? '' : res.email
              ? 'A confirmation email has been sent to your new address. Your address will be updated after following the instructions in that mail.'
              : 'Saved!';
        data.api2 = data.api2.filter(x => !x.delete);
        // XXX: Timeout is ugly, better remove the message on user interaction with the form.
        if (msg) setTimeout(() => { msg = ''; m.redraw() }, 5000);
    });

    const account = () => [
        m('h1', 'Account'),
        m(Username, {data}),
        m(Email, {data}),
        m(Password, {data}),
        m(Support, {data}),
    ];

    const tt = () => [
        m('h1', 'Tags & traits'),
        m('p.description',
            "Here you can set display preferences for individual tags & traits.",
            " This feature can be used to completely hide tags/traits you'd rather not see at all or you'd like to highlight as a possible trigger warning instead.",
            m('br'),
            "These settings are applied on visual novel and character pages, other listings on the site are unaffected."
        ),
        m(TTPrefs, {data, prefix: 'g'}),
        m(TTPrefs, {data, prefix: 'i'}),
    ];

    const tabs = [
        [ 'account', 'Account', account ],
        [ 'profile', 'Public Profile', () => [ m('h1', 'Public Profile'), m(Traits, {data}) ] ],
        [ 'display', 'Display Preferences', display(data) ],
        [ 'tt',      'Tags & Traits', tt ],
        [ 'api',     'Applications', applications(data) ],
    ];
    const view = () => m(Form, {onsubmit,api},
        m(FormTabs, {tabs}),
        m('article.submit',
            m('input[type=submit][value=Submit]'),
            m('span.spinner', { class: api.loading() ? '' : 'invisible' }),
            msg ? m('p', msg) : api.error ? m('b', m('br'), api.error) : null,
        ),
    );
    return {view};
});
