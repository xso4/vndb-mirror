/* Simple script to remember the open/closed state of <details> elements.
 * Usage:
 *
 *   <details data-remember-id=".."> .. </details>
 *
 * This does have the downside of causing a DOM reflow if the elements' default
 * state differs from the one stored by the user, and the preference is stored
 * in the users' browser rather than their account, so it doesn't transfer.
 */
document.querySelectorAll('details[data-remember-id]').forEach(function(el) {
    var sid = 'remember-details-'+el.getAttribute('data-remember-id');
    el.addEventListener('toggle', function() {
        window.localStorage.setItem(sid, el.open ? '1' : '');
    });
    var val = window.localStorage.getItem(sid);
    if(val != null)
        el.open = val == '1' ? true : false;
});


/* Alternative to the above, for users who are logged in.
 * Usage:
 *
 *   <details data-save-id=".."> .. </details>
 *
 * State changes will be saved with an AJAX call to /js/save-pref.
 * Preferences are already assumed to be loaded by server-side code, so this
 * approach does not cause a DOM reflow.
 */
document.querySelectorAll('details[data-save-id]').forEach(function(el) {
    el.addEventListener('toggle', function() {
        var xhr = new XMLHttpRequest();
        xhr.open('POST', '/js/save-pref');
        xhr.setRequestHeader('Content-Type', 'application/json');
        var obj = {};
        obj[el.getAttribute('data-save-id')] = el.open;
        xhr.send(JSON.stringify(obj));
    });
});
