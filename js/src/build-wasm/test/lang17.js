// FLAGS: -v 170
// JavaScript 1.7-era features (the version this engine shipped): generators,
// destructuring assignment, let blocks, and array comprehensions. These only
// parse when the version is set to 170 *before* the file is compiled, hence
// the FLAGS line above (run.sh passes it on the command line).
function gen(){ for (var i=0;i<3;i++) yield i*i; }
var g = gen(), out=[];
for (var v in g) out.push(v);
print("gen=" + out.join(","));

var [a,b] = [10,20];
print("destr=" + (a+b));

let (x=5) { print("let=" + x); }

print("comp=" + [i*2 for (i in [0,1,2,3])].join(","));
