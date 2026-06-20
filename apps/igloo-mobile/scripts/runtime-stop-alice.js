var ProcessBuilder = Java.type('java.lang.ProcessBuilder');
var pb = new ProcessBuilder('/bin/bash', '/Users/plebdev/Desktop/Projects/frostr-infra/apps/igloo-mobile/scripts/runtime-stop-alice.sh');
pb.inheritIO();
var process = pb.start();
var code = process.waitFor();
if (code !== 0) {
  throw new Error('runtime-stop-alice.sh failed: ' + code);
}
