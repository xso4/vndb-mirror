const p = $('.labelfilters');
if(!p) return;
const multi = $('#form_l_multi');
multi.parentNode.classList.remove('hidden');

const l = $$('.labelfilters input[name=l]');
l.forEach(el => el.addEventListener('click', () => {
    if(multi.checked) return true;
    l.forEach(el2 => el2.checked = el2 == el);
    el.closest('form').submit();
}));
