/* "checkhidden" checkbox, usage:
 *
 *    <input type="checkbox" class="checkhidden" value="$somename">
 *
 * Checking that will toggle the 'hidden' class of all elements with the "$somename" class.
 */
$$('input[type=checkbox].checkhidden').forEach(el => {
    const f = () => $$('.'+el.value).forEach(el2 => el2.classList.toggle('hidden', !el.checked));
    f();
    el.addEventListener('click', f);
});
