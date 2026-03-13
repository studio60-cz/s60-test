import { test, expect } from '../../../lib/auth-fixture';

/**
 * Navigation tests — Venom CRM
 * Testuje přechody mezi sekcemi a základní layout.
 * Vyžaduje: TEST_TOKEN nebo TEST_EMAIL+TEST_PASSWORD v env.
 */

test.describe('Navigation', () => {
  test.beforeEach(async ({ authedPage }) => {
    await authedPage.goto('/');
    await authedPage.waitForLoadState('networkidle');
  });

  test('loads without JS error', async ({ authedPage }) => {
    const errors: string[] = [];
    authedPage.on('pageerror', err => errors.push(err.message));
    await authedPage.reload();
    await authedPage.waitForLoadState('networkidle');
    expect(errors.filter(e => !e.includes('ResizeObserver'))).toHaveLength(0);
  });

  test('shows main layout with navigation', async ({ authedPage }) => {
    const nav = authedPage.locator('nav, [data-testid="sidebar"], aside');
    await expect(nav.first()).toBeVisible({ timeout: 10000 });
  });

  test('navigates to Applications section', async ({ authedPage }) => {
    const link = authedPage.getByRole('link', { name: /přihlášky|applications/i })
      .or(authedPage.getByRole('button', { name: /přihlášky|applications/i }));
    await link.first().click();
    await authedPage.waitForLoadState('networkidle');

    // Tabulka nebo heading viditelné
    const heading = authedPage.locator('h1, h2').filter({ hasText: /přihlášky|applications/i });
    const table = authedPage.locator('table, [data-testid="applications-list"]');
    await expect(heading.or(table).first()).toBeVisible({ timeout: 8000 });
  });

  test('navigates to Courses section', async ({ authedPage }) => {
    const link = authedPage.getByRole('link', { name: /kurzy|courses/i })
      .or(authedPage.getByRole('button', { name: /kurzy|courses/i }));
    await link.first().click();
    await authedPage.waitForLoadState('networkidle');
    await expect(authedPage.locator('h1, h2').filter({ hasText: /kurzy|courses/i }).first()).toBeVisible({ timeout: 8000 });
  });

  test('navigates to Clients section', async ({ authedPage }) => {
    const link = authedPage.getByRole('link', { name: /klienti|clients/i })
      .or(authedPage.getByRole('button', { name: /klienti|clients/i }));
    await link.first().click();
    await authedPage.waitForLoadState('networkidle');
    await expect(authedPage.locator('h1, h2').filter({ hasText: /klienti|clients/i }).first()).toBeVisible({ timeout: 8000 });
  });
});
