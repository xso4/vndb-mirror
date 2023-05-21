const buttons = ['managelabels', 'savedefault', 'exportlist'];

buttons.forEach(but => $$('#'+but).forEach(b => b.onclick = ev => {
    ev.preventDefault();
    buttons.forEach(but2 => $$('.'+but2).forEach(e => e.classList.toggle('hidden', but !== but2)))
}))
