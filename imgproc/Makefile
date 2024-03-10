.PHONY: clean distclean

VIPS_VER := 8.15.1
VIPS_DIR := vips-${VIPS_VER}

# TODO: switch to a proper release when it includes this commit
JXL_VER := 5e7560d9e431b40159cf688b9d9be6c0f2e229a1
JXL_DIR := libjxl-${JXL_VER}

CFLAGS := -O3 -Wall

imgproc-portable: imgproc.c
	${CC} ${CFLAGS} $< -DDISABLE_SECCOMP `pkg-config --cflags --libs vips` -o $@

imgproc-custom: imgproc.c build/done-vips Makefile
	${CC} ${CFLAGS} $< `pkg-config --cflags --libs libseccomp` `PKG_CONFIG_PATH="${CURDIR}/build/inst/lib64/pkgconfig" pkg-config --cflags --libs vips` -o $@
	@# Make sure we're not accidentally linking against system libjpeg
	! ldd $@ | grep -q libjpeg

src/${VIPS_DIR}:
	mkdir -p $@
	curl -Ls https://github.com/libvips/libvips/releases/download/v${VIPS_VER}/vips-${VIPS_VER}.tar.xz | tar -C $@ --strip-components 1 -xJf-
	touch $@

src/${JXL_DIR}:
	mkdir -p $@
	@#curl -Ls https://github.com/libjxl/libjxl/archive/refs/tags/v${JXL_VER}.tar.gz | tar -C $@ --strip-components 1 -xzf-
	curl -Ls https://github.com/libjxl/libjxl/tarball/${JXL_VER} | tar -C $@ --strip-components 1 -xzf-
	cd src/${JXL_DIR} && ./deps.sh
	sed -i 's/add_library(jpeg SHARED/add_library(jpeg STATIC/' src/${JXL_DIR}/lib/jpegli.cmake
	touch $@

build/done-jxl: | src/${JXL_DIR}
	mkdir -p build/jxl
	cd build/jxl && cmake -L \
		-DCMAKE_BUILD_TYPE=Release \
		-DBUILD_TESTING=OFF \
		-DBUILD_SHARED_LIBS=OFF \
		-DCMAKE_INSTALL_PREFIX="${CURDIR}/build/inst" \
		-DJPEGXL_ENABLE_BENCHMARK=OFF \
		-DJPEGXL_ENABLE_DOXYGEN=OFF \
		-DJPEGXL_ENABLE_EXAMPLES=OFF \
		-DJPEGXL_ENABLE_FUZZERS=OFF \
		-DJPEGXL_ENABLE_JNI=OFF \
		-DJPEGXL_ENABLE_JPEGLI=ON \
		-DJPEGXL_ENABLE_JPEGLI_LIBJPEG=ON \
		-DJPEGXL_INSTALL_JPEGLI_LIBJPEG=OFF \
		-DJPEGXL_ENABLE_MANPAGES=OFF \
		-DJPEGXL_ENABLE_OPENEXR=OFF \
		-DJPEGXL_ENABLE_PLUGINS=OFF \
		-DJPEGXL_ENABLE_SJPEG=OFF \
		-DJPEGXL_ENABLE_TOOLS=OFF \
		../../src/${JXL_DIR}
	cd build/jxl && cmake --build . -- -j`nproc`
	cd build/jxl && cmake --install .
	touch $@

# jxl doesn't install a libjpeg.pc
# It doesn't even install a static libjpeg.a at all, so we'll just grab it from the build dir directly.
# Additionally, pkg-config doesn't know we're linking these libs statically, so
# make sure that libs in Requires.private are also included.
build/done-pkgconfig: build/done-jxl
	mkdir -p build/inst/lib64/pkgconfig
	@( \
		echo "Name: libjpeg"; \
		echo "Description: Actually jpegli"; \
		echo "Version: 1.0"; \
		echo "Libs: -L${CURDIR}/build/jxl/lib -L${CURDIR}/build/inst/lib64 -ljpeg -ljpegli-static -lhwy -lm -lstdc++"; \
		echo "Cflags: -I${CURDIR}/build/jxl/lib/include/jpegli" \
	) >build/inst/lib64/pkgconfig/libjpeg.pc
	sed -i 's/Requires.private/Requires/' build/inst/lib64/pkgconfig/*.pc
	touch $@

# jpeg, jpgeg-xl and highway are provided by jxl
build/done-vips: build/done-pkgconfig | src/${VIPS_DIR}
	PKG_CONFIG_PATH="${CURDIR}/build/inst/lib64/pkgconfig" meson \
		setup --wipe --default-library=static --prefix="${CURDIR}/build/inst" \
		-Dpng=enabled -Djpeg=enabled -Djpeg-xl=enabled -Dwebp=enabled -Dheif=enabled -Dlcms=enabled -Dhighway=enabled \
		-Ddeprecated=false -Dexamples=false -Dcplusplus=false \
		-Dmodules=disabled -Dintrospection=disabled -Dcfitsio=disabled -Dcgif=disabled \
		-Dexif=disabled -Dfftw=disabled -Dfontconfig=disabled -Darchive=disabled \
		-Dimagequant=disabled -Dmagick=disabled -Dmatio=disabled -Dnifti=disabled -Dopenjpeg=disabled \
		-Dopenslide=disabled -Dorc=disabled -Dpangocairo=disabled \
		-Dpdfium=disabled -Dpoppler=disabled -Dquantizr=disabled -Drsvg=disabled \
		-Dspng=disabled -Dtiff=disabled -Dzlib=disabled \
		-Dnsgif=false -Dppm=false -Danalyze=false -Dradiance=false \
		build/vips src/${VIPS_DIR}
	cd build/vips && meson compile && meson install
	touch $@

clean:
	rm -rf build
	rm -f imgproc-portable imgproc-custom

distclean: clean
	rm -rf src
