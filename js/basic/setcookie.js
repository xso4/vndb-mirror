/* Usage:
 *   <a href="/path" data-setcookie="cookie=value">..</a>
 *
 * Causes a short-lived cookie to be set when the link is followed.
 * Used by VNWeb::Validation::viewget / viewset().
 */
$$('a[data-setcookie]').forEach(a => a.onclick = () => {
    document.cookie = a.getAttribute('data-setcookie')+'; max-age=60';
    // Make sure we do a reload if the location is the same as current page; browsers tend to not do that if the href has a hash.
    if (a.pathname === location.pathname && a.search === location.search) {
        location.reload();
        return false;
    } else {
        return true;
    }
});
