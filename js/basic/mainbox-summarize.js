// Adds a "more"/"less" link to the bottom of a mainbox depending on the
// height of its contents.
//
// Usage:
//
//   <article data-mainbox-summarize="200"> .. </div>

function set(d, h) {
    var expanded = true;
    var a = document.createElement('a');
    a.href = '#';

    var toggle = function() {
        expanded = !expanded;
        d.style.maxHeight = expanded ? null : h+'px';
        d.style.overflowY = expanded ? null : 'hidden';
        a.textContent = expanded ? '⇑ less ⇑' : '⇓ more ⇓';
        return false;
    };

    a.onclick = toggle;
    var t = document.createElement('div');
    t.className = 'summarize_more';
    t.appendChild(a);
    d.parentNode.insertBefore(t, d.nextSibling);
    toggle();
}

document.querySelectorAll('article[data-mainbox-summarize]').forEach(function(d) {
    var h = Math.floor(d.getAttribute('data-mainbox-summarize'));
    if(d.offsetHeight > h+100)
        set(d, h)
});
