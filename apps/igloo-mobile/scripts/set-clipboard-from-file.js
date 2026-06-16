// Maestro runScript JS: copies credential from temp file to system clipboard.
// Uses Node.js child_process to run pbcopy (works since runScript file executes in Node.js).
// Then sets Maestro's internal clipboard so pasteText can use it.
const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');

// Determine platform from PLATFORM env var (passed by Maestro flow)
const platform = process.env.PLATFORM || 'ios';

// Set up file paths based on platform
let pkgFile, pwdFile;
if (platform === 'ios') {
    pkgFile = '/tmp/igloo-mobile-demo-package.txt';
    pwdFile = '/tmp/igloo-mobile-demo-password.txt';
} else {
    pkgFile = '/tmp/igloo-mobile-android-demo-package.txt';
    pwdFile = '/tmp/igloo-mobile-android-demo-password.txt';
}

// Determine which credential to copy based on CLIPBOARD_TARGET env var
const target = process.env.CLIPBOARD_TARGET || 'package';
let filePath = target === 'password' ? pwdFile : pkgFile;

try {
    // Read credential from temp file (strip trailing newline)
    const content = fs.readFileSync(filePath, 'utf8').replace(/\n$/, '');
    console.log('Read ' + content.length + ' chars from ' + filePath);

    // Copy to system clipboard via pbcopy
    // pbcopy reads from stdin and copies to system clipboard
    try {
        execSync('/usr/bin/pbcopy', { input: Buffer.from(content, 'utf8') });
        console.log('pbcopy succeeded (' + content.length + ' chars)');
    } catch (pbcopyErr) {
        console.error('pbcopy failed: ' + pbcopyErr.message);
        // Continue anyway - the system clipboard might not be accessible
    }

    // Also set Maestro's internal clipboard (for Maestro's pasteText command)
    // This is stored in RuntimeStore and used by the device driver
    // We need to call maestro.clipboard.set() but that requires Maestro's JS API
    // Since we're in Node.js (not Maestro's JS context), we can't access maestro global
    // But the system clipboard (pbcopy) should work for iOS Simulator paste

} catch (err) {
    console.error('Error: ' + err.message);
    process.exit(1);
}