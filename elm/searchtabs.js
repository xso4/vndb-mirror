document.querySelectorAll('#searchtabs a').forEach(function(l) {
    l.onclick = function() {
        var str = document.getElementById('q').value;
        if(str.length > 0) {
            if(this.href.indexOf('/g') >= 0 || this.href.indexOf('/i') >= 0)
                this.href += '/list';
            this.href += '?q=' + encodeURIComponent(str);
        }
        return true;
    };
});
