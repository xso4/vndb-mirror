# VNDB's JavaScript Mess

(Because there's no way to do JS without it being a mess)

This is very much a work in progress.


## Organization

Each subdirectory represents a JS bundle. Each bundle has an `index.js` file
which is processed by the top-level Makefile and then converted into
`static/g/<bundle>.js`. `index.js` can include other files with `@include
file.js` lines, these are substituted with the contents of `file.js` and
wrapped inside anonymous JS functions for scoping. File names are resolved
relative to this `js` directory.

Scripts use the global `window` object to share functions and data, but apart
from a bit of common library code, most scripts ought to be fairly
self-contained.

It's up to `index.js` to ensure dependent scripts are included in the proper
order and it's up to the Perl backend to load the bundles in the proper order.
This is somewhat brittle, but such is life.

(Why this weird setup instead of CJS or ES6 modules and a proper bundler?
Because I'm very picky about the software that I run on my dev system and
there's no bundler included in my Linux distro's package repositories.)


## Compatibility

All JS code should be compatible with any 3-year old version of Firefox,
Chrome, Blink and Safari, and a recent version of Pale Moon. The latter tends
to be the most limiting, but they've been doing a lot of catching up on modern
web standards. ES6 is generally no problem.

Specific features to avoid:

- class fields (not supported by Pale Moon 32.1)


## Bundles

- `basic`: Primary bundle for functionality and library code common to popular
  pages on the site. The goal is to keep this below 50kB minified+gzipped.


## Widgets

...is the name I chose for components that can be instantiated from the Perl
backend by adding a `widget($name, $data)` attribute to a HTML tag. They're
similar to "modules" in Elm.

A widget is a mithril.js component that can be registered anywhere in JS with
the following line:

```js
widget('Name', vnode => {
    let data = vnode.attrs.data;
    // ...rest of the mithril component
});
```

Where `data` is whatever the Perl backend passed to it. Objects and arrays
referenced by `data` are not used elsewhere and can be freely mutated.
