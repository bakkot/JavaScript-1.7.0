// Core engine smoke test: allocation + GC, strings, regex, sort, Math, Date,
// exceptions, closures, uneval. Output must be byte-for-byte deterministic
// (the run.sh harness strips the debug GC-stats line that gc() prints).
var a = [];
for (var i = 0; i < 10000; i++) a.push("str" + i);
gc();
var s = a.join(",");
print("len=" + s.length);
print("regex=" + (/str9999/.test(s)));
print("sort=" + [3,1,2,10].sort(function(x,y){return x-y}).join(""));
print("math=" + (Math.sqrt(16) + Math.pow(2,10)));
print("date=" + (new Date(0)).getUTCFullYear());
try { throw new Error("boom"); } catch(e) { print("caught=" + e.message); }
function mk(n){ return function(){ return n*2; } } print("closure=" + mk(21)());
print("uneval=" + uneval({x:1,y:[2,3]}));
print("OK");
