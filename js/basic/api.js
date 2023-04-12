// Simple wrapper around XHR to call into the backend, provide friendly error
// messages and integrate with mithril.js.
// Can only handle one request at a time.
// Reports results back with a plain old callback instead of a promise, because
// VNDB's XHR use is too simple for anything more complex to add much value.
class Api {
    constructor(endpoint) {
        this.endpoint = endpoint;
        this.error = null;
    }

    loading() {
        return this.xhr && this.xhr.readyState != 4;
    }

    _err(cb, msg) {
        this.error = msg;
        cb && cb();
        m.redraw();
    }

    _load(cb, xhr) {
        if (xhr.status == 403) return this._err(cb, 'Permission denied. Your session may have expired, try reloading the page.');
        if (xhr.status == 413) return this._err(cb, 'File upload too large.');
        if (xhr.status == 429) return this._err(cb, 'Action throttled, please try again later.');
        if (xhr.status != 200) return this._err(cb, 'Server error '+xhr.status+', please try again later or report a bug if this persists.');
        if (xhr.response === null || "object" != typeof xhr.response) return this._err(cb, 'Invalid response from the server, please report a bug.');
        if (xhr.response._err) return this._err(cb, xhr.response._err);
        this.error = null;
        cb && cb(xhr.response);
        m.redraw();
    }

    // Runs the given callback when done. On success, the parsed response JSON
    // is passed as argument to the callback.
    call(data, cb) {
        this.error = null;
        if (this.xhr) this.xhr.abort();

        var xhr = new XMLHttpRequest();
        xhr.ontimeout = () => this._err(cb, 'Network timeout, please try again later.');
        xhr.onerror = () => this._err(cb, 'Network error, please try again later.');
        xhr.onload = () => this._load(cb, xhr);
        xhr.open('POST', '/js/'+this.endpoint+'.json', true);
        xhr.setRequestHeader('Content-Type', 'application/json');
        xhr.responseType = 'json';
        xhr.send(JSON.stringify(data));
        this.xhr = xhr;
    }
};
window.Api = Api;
