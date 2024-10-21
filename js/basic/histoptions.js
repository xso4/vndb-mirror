// Used by VNWeb::Misc::History to show/hide the appropriate chflags selector.

const t = $('#histoptions-t');
if (!t) return;
t.onchange = () => [...t.options].forEach(o =>
    $('#histoptions-cf'+o.value).classList.toggle('hidden', t.selectedOptions.length != 1 || !o.selected));
