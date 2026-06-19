var ProcessBuilder = Java.type('java.lang.ProcessBuilder');
var pb = new ProcessBuilder('/bin/bash', '/Users/plebdev/Desktop/Projects/frostr-infra/apps/igloo-mobile/scripts/runtime-stop-relay.sh');
pb.inheritIO();
var process = pb.start();
var code = process.waitFor();
if (code !== 0) {
  throw new Error('runtime-stop-relay.sh failed: ' + code);
}
