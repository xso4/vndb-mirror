# all (default)
#   Create all the necessary directories, javascript, css, etc.
#
# prod
#   Create static assets for production. Requires the following additional dependencies:
#   - uglifyjs
#   - zopfli
#   - zopflipng
#   - brotli
#   - pandoc
#
# test
#   Run the few unit tests that we do have.

.PHONY: all prod clean test multi-stop multi-start multi-restart
.DELETE_ON_ERROR:

VNDB_GEN ?= gen
export VNDB_GEN
GEN=${VNDB_GEN}

CFLAGS ?= -O3 -Wall

ifdef V
Q=
T=@\#
E=@\#
else
Q=@
E=@echo
T=@printf "%s $@\n"
endif

JS_OUT=$(patsubst js/%/index.js,${GEN}/static/%.js,$(wildcard js/*/index.js))
CSS_OUT=$(patsubst css/skins/%.sass,${GEN}/static/%.css,$(wildcard css/skins/*.sass))

all: \
	${GEN}/editfunc.sql \
	${GEN}/static/icons.svg \
	${GEN}/static/icons.png \
	${GEN}/static/elm.js \
	${GEN}/imgproc \
	${JS_OUT} \
	${CSS_OUT}

prod: all \
	${GEN}/api-nyan.html ${GEN}/api-kana.html \
	${GEN}/static/icons.svg.gz ${GEN}/static/icons.svg.br \
	${GEN}/static/icons.opt.png \
	${GEN}/static/elm.min.js ${GEN}/static/elm.min.js.gz ${GEN}/static/elm.min.js.br \
	${JS_OUT:js=min.js} ${JS_OUT:js=min.js} \
	${JS_OUT:js=min.js.gz} ${JS_OUT:js=min.js.gz} \
	${JS_OUT:js=min.js.br} ${JS_OUT:js=min.js.br} \
	${CSS_OUT:css=css.gz} ${CSS_OUT:css=css.br}

clean:
	rm -rf "${GEN}"

%.gz: %
	zopfli $<

%.br: %
	brotli -f $<
	@touch $@

${GEN} ${GEN}/static ${GEN}/js ${GEN}/elm/Gen:
	mkdir -p $@

${GEN}/editfunc.sql: util/sqleditfunc.pl sql/schema.sql | ${GEN}
	util/sqleditfunc.pl >$@

${GEN}/api-%.html: api-%.md | ${GEN}
	$T DOC
	$Q pandoc "$<" -st html5 --toc -o "$@"

test: all
	prove util/test/bbcode.pl
	if [ -e ${GEN}/imgproc-custom ]; then util/test/imgproc-custom.pl; fi




###### Icons & CSS #####

# Single rule for svg & png sprites. This uses a GNU multiple pattern rule in
# order to have it parallelize correctly - splitting this up into two
# individual rules is buggy.
${GEN}/%.css ${GEN}/static/icons.%: util/%sprite.pl icons icons/* icons/*/* | ${GEN}/static
	$<

${GEN}/static/png.css ${GEN}/static/icons.png: ${GEN}/imgproc

${GEN}/static/icons.opt.png: ${GEN}/static/icons.png
	$T PNGOPT
	$Q zopflipng -ym --lossy_transparent "$<" "$@" >/dev/null

${GEN}/static/%.css: css/skins/%.sass css/*.css ${GEN}/png.css ${GEN}/svg.css
	$T SASS
	$Q ( echo '$$png-version: "$(shell sha1sum ${GEN}/static/icons.png | head -c8)";'; \
	  echo '$$svg-version: "$(shell sha1sum ${GEN}/static/icons.svg | head -c8)";'; \
	  echo '@import "css/skins/$*";'; \
	  echo '@import "${GEN}/png";'; \
	  echo '@import "${GEN}/svg";'; \
	) | sassc --stdin -I. --style compressed >$@




###### imgproc #####

${GEN}/imgproc: util/imgproc.c
	$T CC
	$Q ${CC} ${CFLAGS} $< -DDISABLE_SECCOMP `pkg-config --cflags --libs vips` -o $@

VIPS_VER := 8.15.1
# TODO: switch to a proper release when it includes this commit
JXL_VER := 5e7560d9e431b40159cf688b9d9be6c0f2e229a1

VIPS_DIR := ${GEN}/build/vips-${VIPS_VER}
JXL_DIR := ${GEN}/build/libjxl-${JXL_VER}

${GEN}/imgproc-custom: util/imgproc.c ${VIPS_DIR}/done Makefile
	${CC} ${CFLAGS} $< `pkg-config --cflags --libs libseccomp` `PKG_CONFIG_PATH="$(realpath ${GEN})/build/inst/lib64/pkgconfig" pkg-config --cflags --libs vips` -o $@
	@# Make sure we're not accidentally linking against system libjpeg
	! ldd $@ | grep -q libjpeg

# jpeg, jpgeg-xl and highway are provided by jxl
${VIPS_DIR}/done: ${JXL_DIR}/done
	mkdir -p ${VIPS_DIR}
	curl -Ls https://github.com/libvips/libvips/releases/download/v${VIPS_VER}/vips-${VIPS_VER}.tar.xz | tar -C ${VIPS_DIR} --strip-components 1 -xJf-
	PKG_CONFIG_PATH="$(realpath ${GEN})/build/inst/lib64/pkgconfig" meson \
		setup --wipe --default-library=static --prefix="$(realpath ${GEN})/build/inst" \
		-Dpng=enabled -Djpeg=enabled -Djpeg-xl=enabled -Dwebp=enabled -Dheif=enabled -Dlcms=enabled -Dhighway=enabled \
		-Ddeprecated=false -Dexamples=false -Dcplusplus=false \
		-Dmodules=disabled -Dintrospection=disabled -Dcfitsio=disabled -Dcgif=disabled \
		-Dexif=disabled -Dfftw=disabled -Dfontconfig=disabled -Darchive=disabled \
		-Dimagequant=disabled -Dmagick=disabled -Dmatio=disabled -Dnifti=disabled -Dopenjpeg=disabled \
		-Dopenslide=disabled -Dorc=disabled -Dpangocairo=disabled \
		-Dpdfium=disabled -Dpoppler=disabled -Dquantizr=disabled -Drsvg=disabled \
		-Dspng=disabled -Dtiff=disabled -Dzlib=disabled \
		-Dnsgif=false -Dppm=false -Danalyze=false -Dradiance=false \
		${VIPS_DIR}/build ${VIPS_DIR}
	cd ${VIPS_DIR}/build && meson compile && meson install
	touch $@

${JXL_DIR}/done:
	mkdir -p ${JXL_DIR}
	@#curl -Ls https://github.com/libjxl/libjxl/archive/refs/tags/v${JXL_VER}.tar.gz | tar -C $@ --strip-components 1 -xzf-
	curl -Ls https://github.com/libjxl/libjxl/tarball/${JXL_VER} | tar -C ${JXL_DIR} --strip-components 1 -xzf-
	cd ${JXL_DIR} && ./deps.sh
	@# there's no option to build a static jpegli, patch the cmake file instead
	sed -i 's/add_library(jpeg SHARED/add_library(jpeg STATIC/' ${JXL_DIR}/lib/jpegli.cmake
	cd ${JXL_DIR} && cmake -L \
		-DCMAKE_BUILD_TYPE=Release \
		-DBUILD_TESTING=OFF \
		-DBUILD_SHARED_LIBS=OFF \
		-DCMAKE_INSTALL_PREFIX="$(realpath ${GEN})/build/inst" \
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
		-DJPEGXL_ENABLE_TOOLS=OFF .
	cd ${JXL_DIR} && cmake --build . -- -j`nproc`
	cd ${JXL_DIR} && cmake --install .
	@# jxl doesn't install a libjpeg.pc
	@# It doesn't even install a static libjpeg.a at all, so we'll just grab it from the build dir directly.
	@( \
		echo "Name: libjpeg"; \
		echo "Description: Actually jpegli"; \
		echo "Version: 1.0"; \
		echo "Libs: -L$(realpath ${JXL_DIR})/lib -L$(realpath ${GEN})/build/inst/lib64 -ljpeg -ljpegli-static -lhwy -lm -lstdc++"; \
		echo "Cflags: -I$(realpath ${JXL_DIR})/lib/include/jpegli" \
	) >${GEN}/build/inst/lib64/pkgconfig/libjpeg.pc
	@# Additionally, pkg-config doesn't know we're linking these libs statically, so
	@# make sure that libs in Requires.private are also included.
	sed -i 's/Requires.private/Requires/' ${GEN}/build/inst/lib64/pkgconfig/*.pc
	touch $@




###### Elm #####

ELM_FILES=elm/elm.json $(wildcard elm/*.elm elm/*/*.elm)
ELM_CPFILES=${ELM_FILES:%=${GEN}/%}
ELM_MODULES=$(shell grep -l '^main =' ${ELM_FILES} | sed 's/^elm\///')

# Patch the Javascript generated by Elm:
# - Add @license and @source comments
# - Redirect calls from Lib.Ffi.* to window.elmFfi_*
# - Patch the virtualdom diffing algorithm to always apply the 'selected' attribute
# - Patch the Regex library to always enable the 'u' flag
define fix-elm
	$Q ( echo '// @license magnet:?xt=urn:btih:0b31508aeb0634b347b8270c7bee4d411b5d4109&dn=agpl-3.0.txt AGPL-3.0-only'; \
	  echo '// @license magnet:?xt=urn:btih:c80d50af7d3db9be66a4d0a86db0286e4fd33292&dn=bsd-3-clause.txt BSD-3-Clause'; \
	  echo '// @source: https://code.blicky.net/yorhel/vndb/src/branch/master/elm'; \
	  echo '// SPDX-License-Identifier: AGPL-3.0-only and BSD-3-Clause'; \
	  cat $@; \
	  echo; \
	  echo '// @license-end' \
	)   | sed 's/var \$$author\$$project\$$Lib\$$Ffi\$$/var __unused__/g' \
		| sed -E 's/\$$author\$$project\$$Lib\$$Ffi\$$([a-zA-Z0-9_]+)/window.elmFfi_\1(_Json_wrap,_Browser_call)/g' \
		| sed -E "s/([^ ]+) !== 'checked'/\\1 !== 'checked' \&\& \\1 !== 'selected'/g" \
		| sed -E "s/var flags = 'g'/var flags = 'gu'/g" >$@~
	$Q mv $@~ $@
endef

${ELM_CPFILES}: ${GEN}/%: %
	$Q mkdir -p $(dir $@)
	$Q cp $< $@

${GEN}/elm/Gen/.generated: lib/VNWeb/*.pm lib/VNWeb/*/*.pm lib/VNDB/Types.pm lib/VNDB/ExtLinks.pm | ${GEN}/elm/Gen
	util/vndb.pl elmgen

${GEN}/static/elm.js: ${ELM_CPFILES} ${GEN}/elm/Gen/.generated | ${GEN}/static
	$T ELM
	$Q cd ${GEN}/elm && ELM_HOME=elm-stuff elm make ${ELM_MODULES} --output ../static/elm.js >/dev/null
	${fix-elm}

${GEN}/static/elm.min.js: ${ELM_CPFILES} ${GEN}/elm/Gen/.generated | ${GEN}/static
	$T ELM
	$Q cd ${GEN}/elm && ELM_HOME=elm-stuff elm make --optimize ${ELM_MODULES} --output ../static/elm.min.js >/dev/null
	${fix-elm}
	$T MINIFY
	$Q uglifyjs $@ --comments '/(@license|@source|SPDX-)/' --compress \
		'pure_funcs="F2,F3,F4,F5,F6,F7,F8,F9,A2,A3,A4,A5,A6,A7,A8,A9",pure_getters,keep_fargs=false,unsafe_comps,unsafe'\
		| uglifyjs --mangle --comments all -o $@~
	$Q mv $@~ $@




###### Javascript #####

${GEN}/jsdeps.mk: js/*/index.js | ${GEN}
	$E JSDEP
	$Q for f in $(patsubst js/%/index.js,%,$(wildcard js/*/index.js)); do \
		deps=$$(grep '^@include ' js/$$f/index.js | sed -e "s/@include / js\\/$$f\\//" -e "s/js\\/$$f\\/\.gen/\$${GEN}/" | tr -d '\n'); \
		echo "\$${GEN}/static/$$f.js: js/$$f/index.js$$deps";echo; \
	done >$@

include ${GEN}/jsdeps.mk

${GEN}/mithril.js:
	$T FETCH
	$Q curl -s 'https://code.blicky.net/yorhel/mithril-vndb/raw/branch/next/mithril.js' -o $@

# TODO: Custom bundle with only the stuff we use
${GEN}/d3.js:
	$T FETCH
	$Q curl -s 'https://d3js.org/d3.v7.min.js' -o $@

${GEN}/types.js: util/jsgen.pl lib/VNDB/Types.pm lib/VNWeb/Validation.pm
	util/jsgen.pl types >$@

${GEN}/user.js: util/jsgen.pl lib/VNWeb/TimeZone.pm
	util/jsgen.pl user >$@

${GEN}/extlinks.js: util/jsgen.pl lib/VNDB/ExtLinks.pm
	util/jsgen.pl extlinks >$@

${JS_OUT}: ${GEN}/static/%.js: | ${GEN}/static
	$T JS
	$Q perl -Mautodie -pe 'if(/^\@include (.+)/) { #\
		$$n=$$1; open F, $$n =~ m#^\.gen/# ? $$n =~ s#^\.gen/#$$ENV{VNDB_GEN}/#r : "js/$*/$$n"; #\
		local$$/=undef; $$_="/* start of $$n */\n(()=>{\n".<F>."})();\n/* end of $$1 */\n\n" #\
	}' js/$*/index.js >$@

${JS_OUT:js=min.js}: %.min.js: %.js
	$T MINIFY
	$Q uglifyjs $< --comments '/(@license|@source|SPDX-)/' --compress 'pure_getters,keep_fargs=false,unsafe_comps,unsafe' | uglifyjs --mangle --comments all -o $@
