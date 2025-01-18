// Simple wrapper around XHR to call into the backend, provide friendly error
// messages and integrate with mithril.js.
// Can only handle one request at a time.
// Reports results back with a plain old callback instead of a promise, because
// VNDB's XHR use is too simple for anything more complex to add much value.
class Api {
    constructor(endpoint) {
        this.endpoint = endpoint;
        this.abort();
    }

    loading() {
        return this.xhr && this.xhr.readyState != 4;
    }

    Status() {
        return [
            m('span.spinner', { class: this.loading() ? '' : 'invisible' }),
            this.error ? m('b', m('br'), this.error) : null,
        ];
    }

    abort() {
        this.error = null;
        if (this.xhr) this.xhr.abort();
        this.xhr = null;
        this._saved = false;
        this._lastdata = null;
    }

    _err(cb, msg) {
        this.error = msg;
        cb && cb(this.xhr && this.xhr.response);
        m.redraw();
    }

    _load(cb, errcb, xhr) {
        if (xhr.status == 403) return this._err(errcb, 'Permission denied. Your session may have expired, try reloading the page.');
        if (xhr.status == 413) return this._err(errcb, 'File upload too large.');
        if (xhr.status == 429) return this._err(errcb, 'Action throttled, please try again later.');
        if (xhr.status != 200) return this._err(errcb, 'Server error '+xhr.status+', please try again later or report a bug if this persists.');
        if (xhr.response === null || "object" != typeof xhr.response) return this._err(errcb, 'Invalid response from the server, please report a bug.');
        if (xhr.response._err) return this._err(errcb, xhr.response._err);
        if (xhr.response._redir) { location.href = xhr.response._redir; return }
        this.error = null;
        this._saved = this._lastdata;
        cb && cb(xhr.response);
        m.redraw();
    }

    // The parsed response JSON is passed as argument to the callback.
    call(data, cb, errcb) {
        this.abort();
        var xhr = new XMLHttpRequest();
        xhr.ontimeout = () => this._err(errcb, 'Network timeout, please try again later.');
        xhr.onerror = () => this._err(errcb, 'Network error, please try again later.');
        xhr.onload = () => this._load(cb, errcb, xhr);
        xhr.open('POST', '/js/'+this.endpoint+'.json', true);
        xhr.responseType = 'json';
        if (data instanceof FormData) {
            xhr.send(data);
            this._lastdata = null;
        } else {
            xhr.setRequestHeader('Content-Type', 'application/json');
            xhr.send(this._lastdata = JSON.stringify(data));
        }
        this.xhr = xhr;
    }

    // Returns true if the given 'data' has been "saved" by the most recent
    // successful call().  This is level-triggered, once the 'data' is seen as
    // being different it will remember that state till the next call().
    saved(data) {
        if (this._saved === false) return false;
        if (this._saved !== JSON.stringify(data)) return (this._saved = false);
        return true;
    }

    // Manually override the data that's considered as "saved".
    setsaved(data) {
        this._saved = JSON.stringify(data);
    }
};
window.Api = Api;


// Image upload API that can queue multiple files.
class ImageUploadApi {
    constructor(t, cb) {
        this.api = new Api('ImageUpload');
        this.queue = [];
        this.type = t;
        this.cb = cb;
    }

    abort() {
        this.api.abort();
        this.queue = [];
    }

    submit(elem, max) {
        const queue = [...elem.files];
        if (!queue.length)
            this.api.error = 'No file selected';
        else if (queue.length > max)
            this.api.error = 'Too many files selected';
        else {
            this.queue = queue;
            this._one();
        }
    }

    _one() {
        const form = new FormData();
        const obj = this;
        form.append('type', obj.type);
        form.append('img', obj.queue.shift());
        obj.api.call(form, r => {
            obj.cb(r);
            if (obj.queue.length > 0) obj._one();
        });
    }

    loading() {
        return this.api.loading();
    }

    Status() {
        return this.api.Status();
    }
};
window.ImageUploadApi = ImageUploadApi;
