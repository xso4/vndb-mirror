# VNDB image processing tool

*imgproc.c* this is a tool that wraps [libvips](https://www.libvips.org/) image
processing operations used by VNDB in a simple CLI. It can be built in two ways:

*imgproc-portable* links against your system-provided libvips and should, as
the name suggest, be portable across various systems.

*imgproc-custom* builds and links against a custom build of libvips with
support for better JPEG compression through jpegli. It also enables fairly
restrictive seccomp rules for secure sandboxing, to protect against potential
vulnerabilities in the used image codecs. This version likely only works on
x86\_64 Linux with glibc.

The top-level Makefile builds *imgproc-portable* by default and the web backend
makes use of that. To use the custom version, do a `make imgproc-custom` and
update `imgproc_path` in your conf.pl.

## Build Requirements

For *imgproc-portable*:

- C & C++ build system
- libvips (with support for jpeg and whatever else you want to use)

For *imgproc-custom*:

- C & C++ build system
- Linux x86\_64 with glibc
- meson
- cmake
- glib
- lcms
- libexpat
- libheif (with libaom for AVIF support)
- libpng
- libseccomp
- libwebp
