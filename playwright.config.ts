import { defineConfig, devices } from '@playwright/test';

export default defineConfig({
  testDir: './suites/e2e',
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  workers: process.env.CI ? 1 : undefined,
  timeout: 30000,

  reporter: [
    ['list'],
    ['allure-playwright', {
      detail: true,
      outputFolder: '/tmp/allure-results',
      suiteTitle: true,
    }],
    ['json', { outputFile: '/tmp/playwright-results.json' }],
  ],

  use: {
    baseURL: process.env.VENOM_URL || 'https://venom.s60dev.cz',
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
    video: 'on-first-retry',
  },

  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
    },
  ],
});
