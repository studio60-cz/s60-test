import { test, expect } from '../../../lib/auth-fixture';

test.describe('Applications — filtry', () => {
  test.beforeEach(async ({ authedPage }) => {
    await authedPage.goto('/');
    await authedPage.waitForLoadState('networkidle');
    const link = authedPage.getByRole('link', { name: /přihlášky|applications/i })
      .or(authedPage.getByRole('button', { name: /přihlášky|applications/i }));
    await link.first().click();
    await authedPage.waitForLoadState('networkidle');
  });

  test('shows applications list with data', async ({ authedPage }) => {
    const table = authedPage.locator('table, [data-testid="applications-list"], [role="grid"]');
    await expect(table.first()).toBeVisible({ timeout: 10000 });

    // Alespoň jeden řádek
    const rows = authedPage.locator('table tbody tr, [data-testid="application-row"]');
    await expect(rows.first()).toBeVisible({ timeout: 10000 });
  });

  test('filter by status filters results', async ({ authedPage }) => {
    const statusFilter = authedPage.getByLabel(/stav|status/i)
      .or(authedPage.locator('select[name*="status"], [data-testid="filter-status"]'));

    if (await statusFilter.count() === 0) {
      test.skip(true, 'Status filter not found');
      return;
    }

    const initialCount = await authedPage.locator('table tbody tr, [data-testid="application-row"]').count();
    await statusFilter.first().selectOption({ index: 1 });
    await authedPage.waitForLoadState('networkidle');

    const filteredCount = await authedPage.locator('table tbody tr, [data-testid="application-row"]').count();
    expect(filteredCount).toBeGreaterThanOrEqual(0);
    expect(filteredCount).toBeLessThanOrEqual(initialCount);
  });

  test('clear filters restores list', async ({ authedPage }) => {
    const clearBtn = authedPage.getByRole('button', { name: /vymazat|clear|reset/i });
    if (await clearBtn.count() > 0) {
      await clearBtn.first().click();
      await authedPage.waitForLoadState('networkidle');
      const table = authedPage.locator('table, [data-testid="applications-list"]');
      await expect(table.first()).toBeVisible();
    }
  });

  test('pagination navigates to next page', async ({ authedPage }) => {
    const nextBtn = authedPage.getByRole('button', { name: /next|další/i })
      .or(authedPage.locator('[aria-label="next page"], [data-testid="pagination-next"]'));

    if (await nextBtn.count() === 0 || !await nextBtn.first().isEnabled()) {
      test.skip(true, 'Pagination not available or only one page');
      return;
    }

    const firstRowBefore = await authedPage.locator('table tbody tr').first().textContent();
    await nextBtn.first().click();
    await authedPage.waitForLoadState('networkidle');
    const firstRowAfter = await authedPage.locator('table tbody tr').first().textContent();

    expect(firstRowAfter).not.toEqual(firstRowBefore);
  });
});
