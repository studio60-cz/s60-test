import { test as base, BrowserContext, Page } from '@playwright/test';
import * as fs from 'fs';
import * as path from 'path';

const AUTH_URL = process.env.AUTH_URL || 'https://auth.s60dev.cz';
const STORAGE_STATE_PATH = '/tmp/s60-test-auth-state.json';

/**
 * Získá token z env nebo se přihlásí přes S60Auth password grant.
 * Výsledek uloží do storageState pro opakované použití.
 */
async function getAuthToken(): Promise<string | null> {
  // 1. Přímý token z env
  if (process.env.TEST_TOKEN) {
    return process.env.TEST_TOKEN;
  }

  // 2. Credentials z env → password grant
  const email = process.env.TEST_EMAIL;
  const password = process.env.TEST_PASSWORD;

  if (!email || !password) {
    return null;
  }

  try {
    const response = await fetch(`${AUTH_URL}/api/auth/token`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        grant_type: 'password',
        email,
        password,
      }),
    });

    if (!response.ok) return null;

    const data = await response.json() as { access_token?: string };
    return data.access_token || null;
  } catch {
    return null;
  }
}

/**
 * Playwright fixture: autentizovaný page.
 * Pokud není token dostupný, test se přeskočí.
 */
export const test = base.extend<{
  authedPage: Page;
  authToken: string;
}>({
  authToken: async ({}, use) => {
    const token = await getAuthToken();
    if (!token) {
      test.skip(true, 'Auth credentials not available. Set TEST_TOKEN or TEST_EMAIL+TEST_PASSWORD in env.');
      return;
    }
    await use(token);
  },

  authedPage: async ({ page, authToken }, use) => {
    // Nastav Authorization header pro všechny requesty
    await page.setExtraHTTPHeaders({
      'Authorization': `Bearer ${authToken}`,
    });
    await use(page);
  },
});

export { expect } from '@playwright/test';
