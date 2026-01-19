/*
 * USAGE: imgproc [commands] <input.png
 *
 * Commands:
 *
 *   size         - Output image dimensions to standard error.
 *   jpeg n       - Write a jpeg to fd n.
 *   fit x y      - Resize the image to fit within the given dimensions. Does not upscale.
 *   composite    - For util/pngsprite.pl, must be first and only command.
                    Combine multiple input images and write a png to stdout.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#ifndef DISABLE_SECCOMP
#include <seccomp.h>
#include <fcntl.h>
#include <locale.h>
#include <sys/mman.h>
#include <sys/prctl.h>
#include <sys/ioctl.h>
#include <malloc.h>
#endif

#include <vips/vips.h>

#define MAX_INPUT_SIZE (10*1024*1024)

char input_buffer[MAX_INPUT_SIZE];
size_t input_len;


/* Ensure we didn't accidentally load system libjpeg */
#if CUSTOM_JPEGLI
extern void vndb_jpeg_is_jpegli(void);
#endif


#ifndef DISABLE_SECCOMP

static void setup_seccomp() {
    scmp_filter_ctx ctx = seccomp_init(SCMP_ACT_KILL_PROCESS);
    if (ctx == NULL) goto err;

    if (seccomp_rule_add(ctx, SCMP_ACT_ALLOW, SCMP_SYS(exit_group), 0)) goto err;
    if (seccomp_rule_add(ctx, SCMP_ACT_ALLOW, SCMP_SYS(exit), 0)) goto err;
    if (seccomp_rule_add(ctx, SCMP_ACT_ALLOW, SCMP_SYS(brk), 0)) goto err;
    if (seccomp_rule_add(ctx, SCMP_ACT_ALLOW, SCMP_SYS(mmap), 2,
        SCMP_A2_32(SCMP_CMP_EQ, PROT_READ|PROT_WRITE),
        SCMP_A4_32(SCMP_CMP_EQ, -1)
    )) goto err;
    if (seccomp_rule_add(ctx, SCMP_ACT_ALLOW, SCMP_SYS(mremap), 0)) goto err;
    if (seccomp_rule_add(ctx, SCMP_ACT_ALLOW, SCMP_SYS(munmap), 0)) goto err;
    if (seccomp_rule_add(ctx, SCMP_ACT_ALLOW, SCMP_SYS(madvise), 1, SCMP_A2_32(SCMP_CMP_EQ, MADV_DONTNEED))) goto err;

    /* (nearly) impossible to prevent glibc from trying to read /proc and /sys
     * stuff, just block the attempts and have it use fallback code instead. */
    if (seccomp_rule_add(ctx, SCMP_ACT_ERRNO(ENOSYS), SCMP_SYS(openat), 0)) goto err;

    /* Threading, very fiddly :(
     * These are likely specific to a particular glibc version on x86_64.
     * I made an attempt to patch libvips to not use threads, but that turned out to be far more challenging.
     */
    if (seccomp_rule_add(ctx, SCMP_ACT_ALLOW, SCMP_SYS(futex), 0)) goto err;
    if (seccomp_rule_add(ctx, SCMP_ACT_ALLOW, SCMP_SYS(clone3), 0)) goto err;
    if (seccomp_rule_add(ctx, SCMP_ACT_ALLOW, SCMP_SYS(rseq), 0)) goto err;
    if (seccomp_rule_add(ctx, SCMP_ACT_ALLOW, SCMP_SYS(set_robust_list), 0)) goto err;
    if (seccomp_rule_add(ctx, SCMP_ACT_ALLOW, SCMP_SYS(mmap), 3,
        SCMP_A2_32(SCMP_CMP_EQ, PROT_NONE),
        SCMP_A3_32(SCMP_CMP_MASKED_EQ, MAP_PRIVATE&MAP_ANONYMOUS, MAP_PRIVATE|MAP_ANONYMOUS),
        SCMP_A4_32(SCMP_CMP_EQ, -1)
    )) goto err;
    if (seccomp_rule_add(ctx, SCMP_ACT_ALLOW, SCMP_SYS(mprotect), 1, SCMP_A2_32(SCMP_CMP_EQ, PROT_READ|PROT_WRITE))) goto err;
    if (seccomp_rule_add(ctx, SCMP_ACT_ALLOW, SCMP_SYS(prctl), 1, SCMP_A0_32(SCMP_CMP_EQ, PR_SET_NAME))) goto err;
    if (seccomp_rule_add(ctx, SCMP_ACT_ALLOW, SCMP_SYS(sched_getaffinity), 0)) goto err;

    if (seccomp_rule_add(ctx, SCMP_ACT_ALLOW, SCMP_SYS(rt_sigaction), 0)) goto err;
    if (seccomp_rule_add(ctx, SCMP_ACT_ALLOW, SCMP_SYS(rt_sigprocmask), 0)) goto err;

    if (seccomp_rule_add(ctx, SCMP_ACT_ALLOW, SCMP_SYS(close), 0)) goto err;
    if (seccomp_rule_add(ctx, SCMP_ACT_ALLOW, SCMP_SYS(dup), 0)) goto err;
    if (seccomp_rule_add(ctx, SCMP_ACT_ALLOW, SCMP_SYS(read), 1, SCMP_A0(SCMP_CMP_EQ, 0))) goto err;
    if (seccomp_rule_add(ctx, SCMP_ACT_ALLOW, SCMP_SYS(write), 0)) goto err;

    if (seccomp_load(ctx) < 0) goto err;
    seccomp_release(ctx);
    return;
err:
    perror("setting up seccomp");
    exit(1);
}

#endif


/* The default glib logging handler attempt to do charset conversion, color
 * detection and other unnecessary crap that complicates parsing and sandboxing. */
static void log_func(const gchar *log_domain, GLogLevelFlags log_level, const gchar *message, gpointer user_data) {
    if (g_log_writer_default_would_drop(log_level, log_domain)) return;
    /* Pointless libpng warning for some images */
    if (strstr(message, "PCS illuminant is not D50")) return;
    fprintf(stderr, "[%s#%d] %s\n", log_domain, (int)log_level, message);
}


static int composite(void) {
    if (input_len < 8) return 1;

    int offset = 0;
#define RDINT ({ offset += 4; *((int *)(input_buffer+offset-4)); })

    int width = RDINT;
    int height = RDINT;
    /*fprintf(stderr, "Output of %dx%d\n", width, height);*/
    VipsImage *img;
    vips_black(&img, width, height, "bands", 4, NULL);

    while (input_len - offset > 12) {
        int x = RDINT;
        int y = RDINT;
        int bytes = RDINT;
        /*fprintf(stderr, "Image at %dx%d of %d bytes\n", x, y, bytes);*/
        if (input_len - offset < bytes) return 1;
        VipsImage *sub = vips_image_new_from_buffer(input_buffer+offset, bytes, "", NULL);
        if (!img) vips_error_exit(NULL);
        offset += bytes;

        VipsImage *tmp;
        if (!vips_image_hasalpha(sub)) {
            if (vips_addalpha(sub, &tmp, NULL)) vips_error_exit(NULL);
            VIPS_UNREF(sub);
            sub = tmp;
        }

        if (vips_insert(img, sub, &tmp, x, y, NULL)) vips_error_exit(NULL);
        VIPS_UNREF(img);
        VIPS_UNREF(sub);
        img = tmp;
    }

    VipsTarget *target = vips_target_new_to_descriptor(1);
    if (vips_pngsave_target(img, target, "strip", TRUE, NULL))
        vips_error_exit(NULL);
    VIPS_UNREF(target);
    return 0;
}


int main(int argc, char **argv) {
#if CUSTOM_JPEGLI
    vndb_jpeg_is_jpegli();
#endif

#ifndef DISABLE_SECCOMP
    /* don't write to temporary files when working with large images,
       unless we need more than 1g, then we'll just crash. */
    putenv("VIPS_DISC_THRESHOLD=1g");

    /* error messages go through gettext(), prevent that from loading translation files */
    putenv("LANGUAGE=C");

    /* Timezone initialization loads data from disk */
    putenv("TZ=");
    tzset();
#endif

    if (VIPS_INIT(argv[0])) vips_error_exit(NULL);
    g_log_set_default_handler(log_func, NULL);

#ifndef DISABLE_SECCOMP
    /* vips error logging attempt to do charset stuff
       (must be a UTF-8 locale otherwise it tries to load iconv modules, sigh) */
    setlocale(LC_ALL, "C.utf8");
    g_get_charset(NULL);

    setup_seccomp();

    if (argc == 2 && strcmp(argv[1], "seccomp-test") == 0) return read(1, input_buffer, 1);
#endif

    /* Reading into a buffer allows for more strict seccomp rules than using vips_source_new_from_descriptor() */
    int r = 0;
    while ((r = read(0, input_buffer + input_len, MAX_INPUT_SIZE - input_len)) > 0)
        input_len += r;
    if (input_len >= MAX_INPUT_SIZE) {
        fprintf(stderr, "Input too large.\n");
        exit(1);
    }
    if (r < 0) {
        perror("reading input");
        exit(1);
    }

    if (argc == 2 && strcmp(argv[1], "composite") == 0) return composite();

    VipsImage *img = vips_image_new_from_buffer(input_buffer, input_len, "", NULL);
    if (!img) vips_error_exit(NULL);

    /* Remove alpha channel */
    VipsImage *tmp;
    if (vips_image_hasalpha(img)) {
        /* "white" is 256 for 8-bit images and 65536 for 16-bit, the latter works for both.
           (where is this documented!?) */
        VipsArrayDouble *white = vips_array_double_newv(1, 65536.0);
        if (vips_flatten(img, &tmp, "background", white, NULL)) vips_error_exit(NULL);
        VIPS_UNREF(img);
        img = tmp;
    }

    /* This approach to processing CLI arguments is sloppy and unsafe, but the
     * CLI is considered trusted input. */
    while (*++argv) {
        if (strcmp(*argv, "size") == 0)
            fprintf(stderr, "%dx%d\n", vips_image_get_width(img), vips_image_get_height(img));

        else if (strcmp(*argv, "jpeg") == 0) {
            int fd = atoi(*++argv);

            /* Always save as sRGB (suboptimal for greyscale images... do we have those?) */
            if (vips_colourspace(img, &tmp, VIPS_INTERPRETATION_sRGB, NULL))
                vips_error_exit(NULL);

            /* Ignore DPI values from the original image, enforce a consistent 72 DPI */
            vips_copy(tmp, &img, "xres", 2.83, "yres", 2.83, NULL);
            VIPS_UNREF(tmp);

            VipsTarget *target = vips_target_new_to_descriptor(fd);
            if (vips_jpegsave_target(img, target, "Q", 90, "optimize_coding", TRUE, "strip", TRUE, NULL))
                vips_error_exit(NULL);
            VIPS_UNREF(target);

        } else if (strcmp(*argv, "fit") == 0) {
            int width = atoi(*++argv);
            int height = atoi(*++argv);
            if (width >= vips_image_get_width(img) && height >= vips_image_get_height(img))
                continue;

            /* The "linear" option is supposedly quite slow (haven't benchmarked, seems
               fast enough) but it offers a very significant quality boost. */
            if (vips_thumbnail_image(img, &tmp, width, "height", height, "linear", TRUE, NULL))
                vips_error_exit(NULL);
            VIPS_UNREF(img);
            img = tmp;

            /* The lanczos3 kernel used by vips_thumbnail tends to be overly blurry for small images.
               Ideally we should use a sharper downscaler instead, but I couldn't find any in VIPS,
               so just use a sharpen post-processing filter for now. */
            if (width * height < 400*400) {
                if (vips_sharpen(img, &tmp, "m2", 2.0, NULL)) vips_error_exit(NULL);
                VIPS_UNREF(img);
                img = tmp;
            }

        } else {
            fprintf(stderr, "Unknown argument: %s\n", *argv);
            return 1;
        }
    }

    return 0;
}
