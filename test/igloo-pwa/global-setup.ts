import { runTestPrebuild } from '../shared/test-prebuild';

export default async function globalSetup() {
  // The igloo-pwa Playwright suite does not exercise the igloo-home Tauri
  // binary or the demo compose stack. Prebuild only the pwa browser-wasm
  // artifacts so fast/live tiers do not pay for a Tauri debug build.
  runTestPrebuild(['pwa']);
}
