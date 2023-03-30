/* My first experiments with mithril.js, let's see if it's usable. */

if(!window.m || !window.localStorage || window.innerWidth < 500 || window.innerHeight < 400) return;

const storageKey = 'fools6';
var data = window.localStorage.getItem(storageKey);
data = data ? JSON.parse(data) : {
    nogluten: false,
    lowsugar: false,
    nopeanuts: false,
    childlabor: false,
    digital: false,
    saved: null,
};

var opened = data.saved === null;

function toggle() {
    opened = !opened;
    if(!opened) {
        if(data.saved === null) data.saved = false;
        window.localStorage.setItem(storageKey, JSON.stringify(data));
    }
    return false;
}

var Button = { view: function() {
    return m("a.fools-button[href=#]", {
        class: data.saved === true ? "" : "unsaved",
        onclick: toggle,
    }, "Cookie preferences");
} };

var Check = { view: function(vnode) {
    return m("label",
        { class: vnode.attrs.disabled ? "grayedout" : "" },
        m("input[type=checkbox]", {
            oninput: function(e) { data[vnode.attrs.name] = e.target.checked },
            disabled: vnode.attrs.disabled,
            checked: data[vnode.attrs.name]}),
        " " + vnode.attrs.label,
        m("br"),
    )
} };

var Overlay = { view: function() {
    if (!opened) return;
    return m("div.fools-overlay", { onclick: toggle },
        m("form", {
            onclick: function(ev) { ev.stopPropagation() },
            onsubmit: function(ev) { data.saved = true; return toggle() },
        }, [
            m("h2", "We Care About Cookies"),
            m("p", "Like every other website, VNDB generates an excess amount of cookies as side effect of"
              + " your visit. We care about providing everyone with a healthy cookie diet and therefore"
              + " need a few seconds of your time so we can adjust the baking process specially for you."),
            m("br"),
            m("b", " Select your preferences below."),
            m("br"),
            m(Check, { name: "nogluten", label: "Gluten-free cookies", disabled: data.digital }),
            m(Check, { name: "nopeanuts", label: "No peanuts, please", disabled: data.digital }),
            m(Check, { name: "lowsugar", label: "Use artificial sweeteners instead of sugar", disabled: data.digital }),
            m(Check, { name: "childlabor", label: "Ingredients must be sourced with unpaid child labor", disabled: data.digital }),
            m(Check, { name: "digital", label: "I have no physical body and only accept digital cookies" }),
            m("input.submit[type=submit][value=Save]"),
        ])
    );
} };

m.mount(document.body.appendChild(document.createElement('div')), Button);
m.mount(document.body.appendChild(document.createElement('div')), Overlay);
