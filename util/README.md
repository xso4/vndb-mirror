# VNDB utility scripts

## imgproc.c

*imgproc.c* this is a tool that wraps [libvips](https://www.libvips.org/) image
processing operations used by VNDB in a simple CLI. It can be built in two ways:

The default *imgproc* links against your system-provided libvips and should be
portable across various systems.

`make imgproc-custom` builds and links against a custom build of libvips with
support for better JPEG compression through jpegli. It also enables fairly
restrictive seccomp rules for secure sandboxing, to protect against potential
vulnerabilities in the used image codecs. This version likely only works on
x86\_64 Linux with glibc. To use this custom version, update `imgproc_path` in
your conf.pl.

Build requirements for *imgproc-custom*:

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
