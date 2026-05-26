#!/bin/sh
# Build the SpiderMonkey 1.7 JS shell for WebAssembly with Emscripten.
# Output: build-wasm/js.js (+ js.wasm), runnable under node.
set -e

cd "$(dirname "$0")"
OUT=build-wasm/out
mkdir -p "$OUT"

# 2006-era K&R C: demote clang's now-fatal diagnostics back to warnings.
WARN="-Wno-implicit-function-declaration -Wno-implicit-int -Wno-deprecated-non-prototype -Wno-int-conversion"
# Emscripten is a unix-like clang target; DARWIN just gives JS_HAVE_LONG_LONG
# in jsosdep.h (it is referenced nowhere else in the sources).
DEFS="-DXP_UNIX -DDARWIN"
CFLAGS="-O2 $DEFS $WARN -I. -I$OUT"

# --- generated headers -------------------------------------------------------
# jsautocfg.h must reflect the *wasm32* ABI (ILP32, little-endian, stack grows
# down), so generate it by running jscpucfg under node rather than reusing the
# native (LP64) one.
emcc $CFLAGS jscpucfg.c -o "$OUT/jscpucfg.js"
node "$OUT/jscpucfg.js" > "$OUT/jsautocfg.h"

# jsautokw.h (keyword perfect-hash) is platform independent, but regenerate it
# too so the build needs nothing from the native tree. jskwgen writes argv[1].
emcc $CFLAGS -sNODERAWFS=1 jskwgen.c -o "$OUT/jskwgen.js"
node "$OUT/jskwgen.js" "$OUT/jsautokw.h"

# --- engine + shell ----------------------------------------------------------
SRCS="jsapi.c jsarena.c jsarray.c jsatom.c jsbool.c jscntxt.c jsdate.c \
jsdbgapi.c jsdhash.c jsdtoa.c jsemit.c jsexn.c jsfun.c jsgc.c jshash.c \
jsinterp.c jsiter.c jslock.c jslog2.c jslong.c jsmath.c jsnum.c jsobj.c \
jsopcode.c jsparse.c jsprf.c jsregexp.c jsscan.c jsscope.c jsscript.c \
jsstr.c jsutil.c jsxdrapi.c jsxml.c prmjtime.c js.c"

OBJS=""
for src in $SRCS; do
    obj="$OUT/${src%.c}.o"
    echo "  CC  $src"
    emcc $CFLAGS -c "$src" -o "$obj"
    OBJS="$OBJS $obj"
done

# Node target: NODERAWFS gives the shell the real filesystem + stdin.
echo "  LINK $OUT/js.js (node)"
emcc $CFLAGS $OBJS -o "$OUT/js.js" \
    -sALLOW_MEMORY_GROWTH=1 \
    -sNODERAWFS=1 \
    -sEXIT_RUNTIME=1 \
    -sSTACK_SIZE=8MB

# Browser target: same objects, but no NODERAWFS (uses in-memory MEMFS). Exposed
# as a MODULARIZE factory (createJsShell) with callMain + FS so a page can write
# a snippet to a virtual file and run it. See demo/index.html.
echo "  LINK $OUT/js-web.js (browser)"
emcc $CFLAGS $OBJS -o "$OUT/js-web.js" \
    -sALLOW_MEMORY_GROWTH=1 \
    -sSTACK_SIZE=8MB \
    -sMODULARIZE=1 \
    -sEXPORT_NAME=createJsShell \
    -sFORCE_FILESYSTEM=1 \
    -sINVOKE_RUN=0 \
    -sEXIT_RUNTIME=0 \
    -sEXPORTED_RUNTIME_METHODS=callMain,FS

echo "Done: $OUT/js.js (node), $OUT/js-web.js (browser)"
