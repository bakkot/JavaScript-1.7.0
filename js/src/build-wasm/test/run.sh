#!/bin/sh
# Run every test/*.js through the wasm JS shell and diff its stdout against the
# committed test/*.expected golden file.
#
#   ./run.sh              run all tests
#   ./run.sh --record     (re)generate the .expected files from current output
#   ./run.sh foo.js bar   run only the named tests
#
# Conventions:
#   * A test "foo.js" is compared against "foo.expected".
#   * An optional first-line "// FLAGS: ..." in the .js is passed to the shell
#     (e.g. "-v 170" to enable JavaScript 1.7 syntax before the file is parsed).
#   * The debug build's GC-stats line ("before N, after N, break ADDR") is
#     stripped before comparison since the break address is nondeterministic.
set -e
cd "$(dirname "$0")"

JS=../out/js.js
[ -f "$JS" ] || { echo "error: $JS not found - run ../../build-wasm.sh first" >&2; exit 2; }

record=0
case "$1" in --record) record=1; shift;; esac

if [ $# -gt 0 ]; then tests="$*"; else tests="$(ls *.js)"; fi

strip_gc() { grep -v '^before [0-9].*break [0-9a-f]*$' || true; }

pass=0; fail=0
for js in $tests; do
    js="${js%.js}.js"                       # tolerate names with or without .js
    base="${js%.js}"
    flags=$(sed -n 's:^// FLAGS\: *::p' "$js" | head -1)
    out=$(node "$JS" $flags -f "$js" 2>&1 | strip_gc)

    if [ "$record" = 1 ]; then
        printf '%s\n' "$out" > "$base.expected"
        echo "RECORDED $js"
        continue
    fi

    if [ ! -f "$base.expected" ]; then
        echo "MISSING  $js (no $base.expected; run --record)"; fail=$((fail+1)); continue
    fi
    if [ "$out" = "$(cat "$base.expected")" ]; then
        echo "PASS     $js"; pass=$((pass+1))
    else
        echo "FAIL     $js"; fail=$((fail+1))
        diff -u "$base.expected" - <<EOF || true
$out
EOF
    fi
done

[ "$record" = 1 ] && exit 0
echo "-----"
echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
