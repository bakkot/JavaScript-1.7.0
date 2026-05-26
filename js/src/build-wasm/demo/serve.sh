#!/bin/sh
# Copy the browser artifacts next to index.html and serve this directory over
# HTTP (browsers refuse to fetch .wasm over file://). index.html expects
# js-web.js / js-web.wasm to be colocated, so this mirrors a GitHub Pages layout.
# Usage: ./serve.sh [port]   then open the printed URL.
set -e
cd "$(dirname "$0")"          # -> build-wasm/demo/
if [ ! -f ../out/js-web.js ]; then
    echo "../out/js-web.js not found - run ../../build-wasm.sh first" >&2
    exit 2
fi
cp ../out/js-web.js ../out/js-web.wasm .   # gitignored copies (see ../.gitignore)
port="${1:-8000}"
echo "Serving at http://localhost:$port/  (Ctrl-C to stop)"
exec python3 -m http.server "$port"
