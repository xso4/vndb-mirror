/* "checkall" checkbox, usage:
 *
 *    <input type="checkbox" class="checkall" name="$somename">
 *
 *  Checking that will synchronize all other checkboxes with name="$somename".
 *  The "x-checkall" attribute may also be used instead of "name".
 */
$$('input[type=checkbox].checkall').forEach(el =>
    el.addEventListener('click', () => {
        const name = el.getAttribute('x-checkall') || el.name;
        $$('input[type=checkbox][name="'+name+'"], input[type=checkbox][x-checkall="'+name+'"]').forEach(el2 => {
            if(el2.checked != el.checked)
                el2.click();
        });
    })
);
