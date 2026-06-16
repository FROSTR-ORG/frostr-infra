// Maestro runScript: reads credentials from temp files and sets Maestro clipboard.
// Used for reliable credential entry in onboarding Maestro flows.
const fs = require('fs');
const path = require('path');

// Determine platform from environment variable
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

// Read the target credential based on CLIPBOARD_TARGET env var
const target = process.env.CLIPBOARD_TARGET || 'package';
let filePath = target === 'password' ? pwdFile : pkgFile;

try {
    // Read file content and strip trailing newline
    const content = fs.readFileSync(filePath, 'utf8').replace(/\n$/, '');
    console.log(`Read ${content.length} chars from ${filePath}`);

    // Set Maestro clipboard via the Maestro global API
    // This sets Maestro's internal clipboard state, which pasteText uses
    maestro.clipboard.set(content);
    console.log(`Set clipboard to ${content.length} chars (${target})`);
} catch (err) {
    console.error(`Error: ${err.message}`);
    process.exit(1);
}