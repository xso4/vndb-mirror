# all (default)
#   Create all the necessary directories, javascript, css, etc.
#
# prod
#   Create static assets for production. Requires the following additional dependencies:
#   - uglifyjs
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
	${GEN}/imgproc \
	${JS_OUT} \
	${CSS_OUT}

prod: all \
	${GEN}/api-nyan.html ${GEN}/api-kana.html \
	${GEN}/static/icons.svg.gz ${GEN}/static/icons.svg.br \
	${JS_OUT:js=min.js} ${JS_OUT:js=min.js} \
	${JS_OUT:js=min.js.gz} ${JS_OUT:js=min.js.gz} \
	${JS_OUT:js=min.js.br} ${JS_OUT:js=min.js.br} \
	${CSS_OUT:css=css.gz} ${CSS_OUT:css=css.br}

clean:
	rm -rf "${GEN}"

%.gz: %
	gzip -fk9 $<

%.br: %
	brotli -f $<
	@touch $@

${GEN} ${GEN}/static ${GEN}/js:
	mkdir -p $@

${GEN}/editfunc.sql: util/sqleditfunc.pl sql/schema.sql | ${GEN}
	util/sqleditfunc.pl >$@

${GEN}/api-%.html: api-%.md | ${GEN}
	$T DOC
	$Q pandoc "$<" -st html5 --toc -o "$@"

test: all
	prove -Ilib




###### Icons & CSS #####

# Single rule for svg & png sprites. This uses a GNU multiple pattern rule in
# order to have it parallelize correctly - splitting this up into two
# individual rules is buggy.
${GEN}/%.css ${GEN}/static/icons.%: util/%sprite.pl icons icons/* icons/*/* | ${GEN}/static
	$<

${GEN}/static/png.css ${GEN}/static/icons.png: ${GEN}/imgproc

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

JPEGLI_VER := 038935426df9cb037ddddd2ed01e92f6fa3a5867
JPEGLI_DIR := ${GEN}/build/jpegli-${JPEGLI_VER}

${GEN}/imgproc-custom: util/imgproc.c ${GEN}/lib/libjpeg.so Makefile
	${CC} ${CFLAGS} $< `pkg-config --cflags --libs libseccomp vips` -DCUSTOM_JPEGLI -L${GEN}/lib '-Wl,-rpath,$$ORIGIN/lib' -ljpeg -o $@

${JPEGLI_DIR}:
	mkdir -p ${JPEGLI_DIR}

${GEN}/lib/libjpeg.so: | ${JPEGLI_DIR}
	cd ${JPEGLI_DIR} && \
		git clone https://github.com/google/jpegli .  && \
		git reset --hard ${JPEGLI_VER} && \
		git submodule update --init --recursive --depth 1 --recommend-shallow
	echo 'extern "C" { extern void vndb_jpeg_is_jpegli(void) {} }' >>${JPEGLI_DIR}/lib/jpegli/libjpeg_wrapper.cc
	cd ${JPEGLI_DIR} && cmake -L \
		-DCMAKE_BUILD_TYPE=Release \
		-DBUILD_TESTING=OFF \
		-DBUILD_SHARED_LIBS=ON \
		-DCMAKE_INSTALL_PREFIX="$(realpath ${GEN})/build/inst" \
		-DJPEGXL_FORCE_SYSTEM_HWY=ON \
		-DJPEGXL_FORCE_SYSTEM_BROTLI=ON \
		-DJPEGXL_FORCE_SYSTEM_LCMS2=ON \
		-DJPEGXL_ENABLE_MANPAGES=OFF \
		-DJPEGXL_ENABLE_BENCHMARK=OFF \
		-DJPEGXL_ENABLE_DOXYGEN=OFF \
		-DJPEGXL_ENABLE_FUZZERS=OFF \
		-DJPEGXL_ENABLE_JPEGLI_LIBJPEG=ON \
		-DJPEGXL_INSTALL_JPEGLI_LIBJPEG=OFF \
		-DJPEGXL_ENABLE_TOOLS=OFF .
	cd ${JPEGLI_DIR} && make -j`nproc`
	mkdir -p ${GEN}/lib
	mv ${JPEGLI_DIR}/lib/jpegli/libjpeg.so* ${GEN}/lib




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
	$Q curl -s 'https://code.blicky.net/yorhel/mithril-vndb/raw/branch/main/mithril.js' -o $@

# TODO: Custom bundle with only the stuff we use
${GEN}/d3.js:
	$T FETCH
	$Q curl -s 'https://d3js.org/d3.v7.min.js' -o $@

${GEN}/types.js: util/jsgen.pl lib/VNDB/Types.pm lib/VNDB/ExtLinks.pm lib/VNWeb/Validation.pm
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
