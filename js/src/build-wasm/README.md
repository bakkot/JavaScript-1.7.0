# SpiderMonkey 1.7 — WebAssembly build

This builds the SpiderMonkey 1.7.0 standalone JS shell (`js`) to WebAssembly
with Emscripten. The engine sources are **unmodified**; the entire port lives in
`../build-wasm.sh` plus the files in this directory. There are two link targets
from the same objects: a **Node** build (`out/js.js`) and a **browser** build
(`out/js-web.js`), the latter driven by the `demo/` playground.

## Quick start

```sh
cd js/src
./build-wasm.sh                 # -> out/js.js (node) + out/js-web.js (browser)

cd build-wasm
./js script.js                  # run a file        (wrapper around `node out/js.js`)
./js -i                         # interactive REPL
./js -v 170 -f prog.js          # enable JS 1.7 syntax, then run prog.js
echo 'print(1+2)' | ./js
./test/run.sh                   # run the test suite

./demo/serve.sh                 # browser playground at http://localhost:8000/demo/
```

Requirements: a working `emcc` on `PATH` (developed against Emscripten 5.0.7)
and `node`. The browser demo additionally needs `python3` (for `serve.sh`) and
any modern browser. Nothing from the native `Darwin_*.OBJ` tree is needed.

## What's in this directory

All build artifacts go under `out/`, which is gitignored. The committed files
live at the top level:

| Path          | Notes |
|---------------|-------|
| `out/`        | **artifact** — everything `../build-wasm.sh` produces (`js.js`+`js.wasm` for node, `js-web.js`+`js-web.wasm` for the browser, `*.o`, the `jscpucfg`/`jskwgen` helpers, generated `jsautocfg.h`/`jsautokw.h`). Gitignored; safe to delete and rebuild. |
| `js`          | committed — wrapper that runs `node out/js.js "$@"` |
| `README.md`   | committed — this file |
| `test/`       | committed — golden-output test suite (see below) |
| `demo/`       | committed — browser playground (`index.html`, `serve.sh`) |

There is no `clean` target; `rm -rf out` does it.

## Why these particular choices (the things that will bite you)

These are the non-obvious decisions in `../build-wasm.sh`. Most "why won't it
work" questions are answered here.

1. **`jsautocfg.h` is regenerated for wasm32 — do NOT reuse the native one.**
   `jscpucfg.c` is a probe program that emits CPU/ABI facts (type sizes,
   endianness, stack-growth direction) as `#define`s. The native macOS build
   produces an **LP64** header (`long`/pointer = 8 bytes). wasm32 is **ILP32**
   (`long`/pointer = 4 bytes). Using the wrong one silently corrupts every
   tagged-pointer/`jsval` operation in the engine. The script compiles
   `jscpucfg.c` with `emcc` and runs it **under Node**, so the values describe
   the actual wasm target — including `JS_STACK_GROWTH_DIRECTION = -1`, which
   the shell's stack-overflow guard depends on (see #5).

2. **`jsautokw.h` is also regenerated** (keyword perfect-hash, from
   `jskeyword.tbl`). It happens to be platform-independent, but regenerating it
   via `emcc`+Node keeps the build self-contained — it needs nothing from the
   native tree.

3. **`-DXP_UNIX -DDARWIN`.** Emscripten is a unix-like clang target, so
   `XP_UNIX` selects the right OS paths (e.g. the standard 2-arg `gettimeofday`
   in `prmjtime.c`). `DARWIN` is defined only to satisfy `jsosdep.h`, where it
   is the branch that defines `JS_HAVE_LONG_LONG`; `DARWIN` appears **nowhere
   else** in the sources, so it pulls in no Mac-specific behavior.

4. **K&R warning relaxation.** This is 2006 C; clang 16+ promotes implicit
   function declarations, implicit `int`, and old-style prototypes to hard
   errors. The build passes `-Wno-implicit-function-declaration
   -Wno-implicit-int -Wno-deprecated-non-prototype -Wno-int-conversion` to
   demote them back to warnings. (The native macOS build does the same via
   `config/Darwin.mk`.)

5. **`-sSTACK_SIZE=8MB` vs. the engine's 500 KB soft limit.** `js.c` installs a
   *soft* recursion guard at `gStackBase ± gMaxStackSize` (default
   `gMaxStackSize = 500000`). When JS recursion approaches that, the engine
   throws a catchable `InternalError: too much recursion` instead of letting
   the real C stack overflow. The link gives wasm an 8 MB stack so the *soft*
   limit always trips first — otherwise deep recursion would trap the VM. Note
   the 500 KB default means fairly shallow JS recursion (~2000 frames in this
   debug build) throws; that is **identical to the native build**, not a wasm
   regression. `js -S <bytes>` overrides `gMaxStackSize` (0 disables the guard).

6. **No editline.** `js.c` falls back to plain `fgets` when `EDITLINE` is not
   defined, so the interactive REPL needs no tty/termios support. The
   `editline/` library is not compiled for wasm.

7. **Link flags.** `-sNODERAWFS=1` gives the shell direct access to the real
   filesystem and stdin under Node (so file arguments and piped input work);
   `-sALLOW_MEMORY_GROWTH=1` lets the heap grow; `-sEXIT_RUNTIME=1` makes the
   shell's exit codes propagate to the `node` process.

## Running JavaScript 1.7 syntax

Generators (`yield`), `let` blocks, destructuring, and array comprehensions are
1.7 features that only **parse** when the version is set to 170 *before* the
file is compiled. Calling `version(170)` at the top of a script is too late —
the whole file is parsed first. Use the command line instead:

```sh
./js -v 170 -f prog.js
```

## Test suite (`test/`)

`test/run.sh` runs each `test/*.js` through the wasm shell and diffs stdout
against the committed `test/*.expected` golden file.

```sh
./test/run.sh                # run all
./test/run.sh smoke.js       # run one
./test/run.sh --record       # regenerate .expected from current output
```

Conventions:
- A test `foo.js` is compared to `foo.expected`.
- An optional first line `// FLAGS: ...` is passed to the shell (e.g.
  `// FLAGS: -v 170` in `lang17.js`).
- The debug build prints a GC-stats line (`before N, after N, break ADDR`) to
  stdout whose break address is nondeterministic; the harness strips it before
  comparing. If you ever build with different GC/debug settings and that line
  disappears or changes format, update the `strip_gc` filter in `run.sh`.

Current tests: `smoke.js` (alloc+GC, strings, regex, sort, Math, Date,
exceptions, closures, `uneval`), `lang17.js` (1.7 language features), and
`recursion.js` (the stack-overflow guard from #5).

## Browser playground (`demo/`)

`demo/index.html` is a small page that runs user-typed JS in the wasm engine.
It expects `js-web.js` and `js-web.wasm` to sit **next to it**. `serve.sh` copies
those in from `out/` (the copies are gitignored) and serves the directory over
HTTP — browsers won't `fetch` `.wasm` over `file://`:

```sh
./demo/serve.sh            # copies artifacts in, python3 -m http.server, root = demo/
# -> http://localhost:8000/
```

### Deploying to GitHub Pages

The colocated layout is exactly what Pages serves, so point Pages at the `demo/`
directory. Because `js-web.js`/`js-web.wasm` are gitignored build artifacts, you
must get them into the published tree one of two ways:

- **Commit them:** `git add -f demo/js-web.js demo/js-web.wasm` (after running
  `serve.sh` or copying them in), or
- **Build in CI:** run `build-wasm.sh` and copy `out/js-web.{js,wasm}` into the
  deploy artifact in a GitHub Actions workflow.

How it drives the engine — note the `out/js-web.js` target differs from the
node one in exactly these link flags:

- **No `NODERAWFS`** (which needs Node's `fs`); it uses in-memory `MEMFS` plus
  `-sFORCE_FILESYSTEM=1`.
- **`-sMODULARIZE=1 -sEXPORT_NAME=createJsShell`** — a plain `<script>` tag then
  exposes a global `createJsShell(opts)` factory returning a promise of a module
  instance. (Default, non-ES6 module, so no bundler needed.)
- **`-sINVOKE_RUN=0 -sEXIT_RUNTIME=0`** and `-sEXPORTED_RUNTIME_METHODS=callMain,FS`
  so the page controls execution: each Run does
  `FS.writeFile('/input.js', code)` then `callMain(['-v','170','-f','/input.js'])`.

The page creates a **fresh module instance per Run** so each run starts with
clean engine state (like a new process); the browser caches the `.wasm` fetch.
`print()`/errors are captured via the `print`/`printErr` callbacks. The "JS 1.7
syntax" checkbox just prepends `-v 170` (required *before* parse — see above).

## Known limitations / possible future work

- **Single-threaded.** Not built `JS_THREADSAFE`; there is no NSPR. Fine for
  the shell.
- **Debug-ish build.** Compiled `-O2` but with the engine's debug code paths
  active (hence the GC-stats output). Defining `-DNDEBUG` and dropping debug
  prints would shrink and speed it up; verify the test suite still passes (and
  refresh the goldens, since the GC line may vanish).
