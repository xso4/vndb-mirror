const tsStart = Date.now();
// milliseconds since page load
const now = window.performance ? () => window.performance.now() : () => (Date.now() - tsStart)/1000;
const apiGet = new Api("NNMGet");
const apiSubmit = new Api("NNMSubmit");

const fetch_interval = 50000;
const submit_interval = 60000;

var list = [];
var settings = { enabled: true, expand: true, color: null, lastsubmit: 0 };
var lastfetch = 0;
var fetchtimer;

const animate = () => {
    if (!settings.enabled) return;
    const t = now();
    const w = window.innerWidth;
    list.forEach(n => {
        const wait = (n.t - t) / 1000; // seconds till display
        if (wait > -10 && wait <= 0) {
            if (!n.dom) {
                n.dom = document.createElement('span');
                n.dom.className = 'nnm-msg';
                n.dom.style.top = (n.id / 2147483648 * 90) + '%';
                if (n.color) n.dom.style.color = n.color;
                n.dom.innerText = n.message;
                document.body.appendChild(n.dom);
            }
            n.dom.style.left = w + (wait*500) + 'px'; // 500px/s
        } else if (n.dom) {
            document.body.removeChild(n.dom);
            n.dom = null;
        }
    });
    requestAnimationFrame(animate);
};

const stopFetch = () => {
    if (fetchtimer) clearTimeout(fetchtimer);
    fetchtimer = null;
};

const fetch = () => {
    stopFetch();
    if (lastfetch > now() - fetch_interval + 3000) {
        fetchtimer = setTimeout(fetch, lastfetch + fetch_interval - now());
        return;
    }
    fetchtimer = setTimeout(fetch, fetch_interval);
    lastfetch = now();

    apiGet.call({}, data => {
        const ids = Object.fromEntries(list.map(n => [n.id,true]));
        const t = now();
        data.list.forEach(n => {
            if (!ids[n.id]) {
                n.t = t + n.wait;
                list.push(n);
            }
        });
        list = list.filter(n => n.dom || (n.t - t) > -10000);
    });
};

const save = () => {
    try {
        window.localStorage.setItem('nnm', JSON.stringify(settings));
    } catch {};
};

widget('NNM', initVnode => {
    list = initVnode.attrs.data;
    //list.push({id:12485235, message: 'This is a                            test message!', wait: -1000});
    //list.push({id:131248523, message: '(It loads on every page)', wait: 100, color: '#ff0000'});
    const t = lastfetch = now();
    list.forEach(n => n.t = t + n.wait);

    try {
        const v = window.localStorage.getItem('nnm');
        if (v) settings = JSON.parse(v);
    } catch {};

    if (settings.enabled) {
        fetch();
        animate();
    }
    var tab = settings.expand ? 0 : 4;

    if (settings.lastsubmit > Date.now()-submit_interval)
        setTimeout(() => m.redraw(), Date.now() - settings.lastsubmit + submit_interval);

    document.addEventListener("visibilitychange", () => {
        if (document.visibilityState === 'hidden') stopFetch()
        else if (settings.enabled) fetch();
    });

    const view = () => m('form', { onsubmit: ev => {
            ev.preventDefault();
            apiSubmit.call({
                color: ev.target.querySelector('input[type=color]').value,
                message: ev.target.querySelector('input[type=text]').value,
            }, () => {
                save(settings.lastsubmit = Date.now());
                setTimeout(() => m.redraw(), submit_interval);
            });
        } },
        m('input[type=checkbox][title=Enable/disable chat overlay]', { checked: settings.enabled, onclick: ev => {
            settings.enabled = ev.target.checked;
            save();
            if (settings.enabled) {
                fetch();
                animate();
            } else {
                stopFetch();
                list.forEach(n => {
                    if (n.dom) document.body.removeChild(n.dom);
                    n.dom = null;
                });
            }
        } }),
        !settings.enabled ? [] : [
            m('button[type=button]',
                { onclick: () => {
                    if (++tab == 5) tab = 0;
                    save(settings.expand = tab != 4);
                } },
                tab == 0 ? '?' : tab == 3 ? '«' : tab == 4 ? '»' : tab
            ),
        ].concat(tab == 0 && apiSubmit.loading() ? [
            m('p', m('span.spinner')),
        ] : tab == 0 && apiSubmit.error ? [
            m('p', m('b', apiSubmit.error)),
        ] : tab == 0 && settings.lastsubmit > Date.now()-submit_interval ? [
            m('p', "Message submitted ...wait for it! (or don't, takes a minute)"),
        ] : tab == 0 ? [
            m('input[type=color][title=Message color]', { value: settings.color || '#ffffff', oninput: ev => save(settings.color = ev.target.value) }),
            m('input[type=text][placeholder=Say hi!][required][maxlength=200]'),
            m('input[type=submit][value=Submit]'),
        ] : tab == 1 ? [
            m('p', 'Your message is displayed on every page after a one minute delay.')
        ] : tab == 2 ? [
            m('p', 'You may only submit one message per minute.')
        ] : tab == 3 ? [
            m('p', 'The checkbox on the left completely disables message display.')
        ] : []),
    );
    return {view};
});
