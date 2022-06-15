wrap_elm_init('User.Edit', function(init, opt) {
    var app = init(opt);
    app.ports.skinChange.subscribe(function(skin) {
        var sheet = document.querySelector('link[rel=stylesheet]');
        sheet.href = sheet.href.replace(/[^\/]+\.css/, skin+'.css');
    });
});
