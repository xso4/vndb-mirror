//order:9 - After Elm initialization

/* "checkall" checkbox, usage:
 *
 *    <input type="checkbox" class="checkall" name="$somename">
 *
 *  Checking that will synchronize all other checkboxes with name="$somename".
 *  The "x-checkall" attribute may also be used instead of "name".
 */
document.querySelectorAll('input[type=checkbox].checkall').forEach(function(el) {
    el.addEventListener('click', function() {
        var name = el.getAttribute('x-checkall') || el.name;
        document.querySelectorAll('input[type=checkbox][name="'+name+'"], input[type=checkbox][x-checkall="'+name+'"]').forEach(function(el2) {
            if(el2.checked != el.checked)
                el2.click();
        });
    });
});
