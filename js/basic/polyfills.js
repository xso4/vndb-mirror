if (!Object.fromEntries)
        Object.fromEntries = lst => {
                let obj = {};
                for (let [key, value] of lst) obj[key] = value;
                return obj;
        };

if (!Array.prototype.flat)
    Array.prototype.flat = function (depth=1) {
        return depth < 1 ? this.slice() : this.reduce((acc,val) =>
            acc.concat(Array.isArray(val) ? Array.prototype.flat.call(val, depth-1) : val),
        []);
    };

if (!Array.prototype.flatMap)
    Array.prototype.flatMap = function(f) { return this.map(f).flat(1) };
