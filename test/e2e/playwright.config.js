const { defineConfig } = require('@playwright/test');

// Story 127.562: the port comes from the environment. run_playwright.sh picks
// a free one, serves ooke on it and exports OOKE_E2E_PORT; there is no fixed
// default, so a run without it cannot reach some other server on 3099.
const port = process.env.OOKE_E2E_PORT;
if (!/^[0-9]+$/.test(port || '')) {
  throw new Error('OOKE_E2E_PORT is not set: run test/e2e/run_playwright.sh, which starts ooke on a free port');
}

module.exports = defineConfig({
  testDir: '.',
  timeout: 30000,
  use: {
    baseURL: 'http://127.0.0.1:' + port,
  },
});
