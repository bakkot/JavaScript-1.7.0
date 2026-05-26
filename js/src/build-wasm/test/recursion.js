// The engine's soft stack-overflow guard (gStackBase +/- gMaxStackSize, set up
// in js.c ProcessFile) must turn unbounded recursion into a catchable JS error
// rather than letting the C stack overflow and trap the wasm VM. This is why
// jsautocfg.h's JS_STACK_GROWTH_DIRECTION has to be generated for wasm32 (-1),
// and why the link uses a STACK_SIZE comfortably larger than gMaxStackSize.
function rec(n){ return rec(n+1); }
try {
    rec(0);
    print("FAIL: recursion was not guarded");
} catch (e) {
    print("guarded=" + (e instanceof InternalError) + " name=" + e.name);
}
