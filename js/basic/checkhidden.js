/* "checkhidden" checkbox, usage:
 *
 *    <input type="checkbox" class="checkhidden" value="$somename">
 *
 * Checking that will toggle the 'hidden' class of all elements with the "$somename" class.
 */
document.querySelectorAll('input[type=checkbox].checkhidden').forEach(function(el) {
    var f = function() {
        document.querySelectorAll('.'+el.value).forEach(function(el2) {
            el2.classList.toggle('hidden', !el.checked);
        });
    };
    f();
    el.addEventListener('click', f);
});
