# VNDB utility scripts

(Only interesting scripts are documented here)

dbdump.pl
:   Can generate various database dumps, refer to its help text for details.

devdump.pl
:   Generates a tarball containing a [small subset of the
    database](https://vndb.org/d8#3) for development purposes.

hibp-dl.pl
:   Utility to fetch the [Pwned
    Passwords](https://haveibeenpwned.com/Passwords) database and store it in
    `$VNDB_VAR/hibp`. The web backend can use this to warn about compromised
    passwords.

multi.pl
:   Runs the background service for the old API and various maintenance tasks.
    The actual code for the service lives in */lib/Multi/*.

unusedimages.pl
:   Purges unreferenced images from the database and scans `$VNDB_VAR/static/`
    for files to be deleted.

vndb.pl
:   This is the main entry point of the web backend. This script does some
    setup and loads all the code from */lib/VNWeb/*. Can be started from CGI or
    FastCGI context. When run on the command line it will spawn a simple
    single-threaded web server on port 3000.

vndb-dev-server.pl
:   A handy wrapper around *vndb.pl* for development use. Spawns a web server
    on port 3000 that will automatically run `make` and reload the backend code
    on changes.


## imgproc.c

*imgproc.c* this is a tool that wraps [libvips](https://www.libvips.org/) image
processing operations used by VNDB in a simple CLI. It can be built in two ways:

The default *imgproc* links against your system-provided libvips and should be
portable across various systems.

`make gen/imgproc-custom` builds and links against a custom build of libvips
with support for better JPEG compression through jpegli. It also enables fairly
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
