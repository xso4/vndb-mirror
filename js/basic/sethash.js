// Emulate setting a location.hash if none has been set.
if(pageVars.sethash && location.hash.length <= 1) {
    var e = document.getElementById(pageVars.sethash);
    if(e) {
        e.scrollIntoView();
        e.classList.add('target');
    }
}
