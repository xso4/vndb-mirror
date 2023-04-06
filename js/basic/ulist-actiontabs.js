var buttons = ['managelabels', 'savedefault', 'exportlist'];

buttons.forEach(function(but) {
    document.querySelectorAll('#'+but).forEach(function(b) {
        b.onclick = function() {
            buttons.forEach(function(but2) {
                document.querySelectorAll('.'+but2).forEach(function(e) {
                    if(but == but2)
                        e.classList.toggle('hidden');
                    else
                        e.classList.add('hidden')
                })
            })
            return false;
        }
    })
})
