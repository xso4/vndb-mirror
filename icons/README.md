# VNDB Icons

This directory contains SVG and PNG icons that are merged into a single
*icons.svg* and *icons.png*, respectively, through *util/svgsprite.pl* and
*util/pngsprite.pl*. These icons can be imported by the front-end with the
respective *icon-* classes. For example, to reference a platform icon in
*plat/*, the following HTML will work:

```html
<abbr class="icon-plat-lin">
```

Not all the necessary CSS for the icons is auto-generated, some properties
still need to be set in *css/v2.css*.

This icon sprite approach is just a silly optimization to improve compression
efficiency and reduce the number of HTTP requests. It works fine for small
and/or commonly used images to improve page loads, but less common or larger
images are better thrown in *static/f/* instead.


## SVG Icons

*svgsprite.pl* is very picky about the format of SVG icons; they must adhere to
the following rules:

- Must have a global `viewBox` property that starts at (0,0)
- The viewbox dimensions must match the pixel dimensions when rendered on the site
- Must have at most one `<defs>` element
- Must not have any `<style>` elements
- Must not have any 'xlink' properties (plain 'href' works fine)
- The drawing elements don't go too far outside of the global viewbox

Converting existing images to adhere to these rules can be somewhat tricky, my
general approach is as follows:

- Open image in Inkscape to simplify paths, remove excess drawing elements and
  convert some shapes into paths when that reduces file size
- Simplify the SVG through SVGO ([SVGOMG](https://svgomg.net/) is handy)
- Convert any CSS and styles to plain SVG attributes
- Move the viewbox to the (0,0) coordinates by adding a top-level
  `<g transform="translate(-x -y)">` element
- Adjust the size of the viewbox to the pixel dimensions we want by adding a top-level
  `<g transform="scale(..)">` element
- Run the file through SVGO again to propagate the above transforms into the paths
- Manually remove attributes that don't affect the visual output (may take some
  trial and error to see which attributes are necessary)
