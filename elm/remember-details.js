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
