import { runTestPrebuild } from '../shared/test-prebuild';

type PrebuildTier = 'fast' | 'live' | 'demo';

function detectTier(): PrebuildTier {
  // The demo tier is signalled by test:e2e:igloo-chrome:demo via
  // IGLOO_DEMO_LIVE_REPRO=1. That script also passes explicit spec paths
  // rather than --grep args, so check it first.
  if (process.env.IGLOO_DEMO_LIVE_REPRO === '1') {
    return 'demo';
  }

  // Playwright forwards its CLI args into the Node process. Inspect argv for
  // --grep / --grep-invert to decide between the fast and live tiers.
  const argv = process.argv.slice(2);
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === '--grep-invert' || arg.startsWith('--grep-invert=')) {
      const value = arg.includes('=') ? arg.split('=').slice(1).join('=') : argv[i + 1];
      if (value && value.includes('@live')) {
        return 'fast';
      }
    }
    if (arg === '--grep' || (arg.startsWith('--grep=') && !arg.startsWith('--grep-invert'))) {
      const value = arg.includes('=') ? arg.split('=').slice(1).join('=') : argv[i + 1];
      if (value && value.includes('@live')) {
        return 'live';
      }
    }
  }

  // Unspecified invocation (e.g. `playwright test` without a grep flag)
  // conservatively prebuilds the full live-tier surface so any live-tagged
  // spec still has its binaries. It does not pull in the demo stack.
  return 'live';
}

const TIER_TARGETS: Record<PrebuildTier, string[]> = {
  fast: ['chrome'],
  live: ['chrome', 'home'],
  demo: ['chrome', 'home', 'demo'],
};

export default async function globalSetup() {
  const tier = detectTier();
  runTestPrebuild(TIER_TARGETS[tier]);
}
