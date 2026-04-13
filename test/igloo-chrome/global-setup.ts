import { runTestPrebuild } from '../shared/test-prebuild';

export default async function globalSetup() {
  runTestPrebuild(['chrome', 'home', 'demo']);
}
