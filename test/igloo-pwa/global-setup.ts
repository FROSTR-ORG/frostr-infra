import { runTestPrebuild, targetsForClient } from '../shared/test-prebuild';

export default async function globalSetup() {
  runTestPrebuild(targetsForClient('pwa'));
}
