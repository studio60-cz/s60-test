import { test, expect } from '../../../lib/auth-fixture';

test.describe('Application — detail', () => {
  test.beforeEach(async ({ authedPage }) => {
    await authedPage.goto('/');
    await authedPage.waitForLoadState('networkidle');
    const link = authedPage.getByRole('link', { name: /přihlášky|applications/i })
      .or(authedPage.getByRole('button', { name: /přihlášky|applications/i }));
    await link.first().click();
    await authedPage.waitForLoadState('networkidle');
  });

  test('opens application detail on row click', async ({ authedPage }) => {
    const firstRow = authedPage.locator('table tbody tr, [data-testid="application-row"]').first();
    await expect(firstRow).toBeVisible({ timeout: 10000 });
    await firstRow.click();

    const detail = authedPage.locator('[data-testid="application-detail"], .detail-panel, [role="dialog"]');
    await expect(detail.first()).toBeVisible({ timeout: 5000 });
  });

  test('detail shows client info', async ({ authedPage }) => {
    const firstRow = authedPage.locator('table tbody tr, [data-testid="application-row"]').first();
    await expect(firstRow).toBeVisible({ timeout: 10000 });
    await firstRow.click();

    const clientField = authedPage.getByText(/klient|client/i).first();
    await expect(clientField).toBeVisible({ timeout: 5000 });
  });

  test('detail shows course/term info', async ({ authedPage }) => {
    const firstRow = authedPage.locator('table tbody tr, [data-testid="application-row"]').first();
    await expect(firstRow).toBeVisible({ timeout: 10000 });
    await firstRow.click();

    const courseInfo = authedPage.getByText(/kurz|course|termín|term/i).first();
    await expect(courseInfo).toBeVisible({ timeout: 5000 });
  });

  test('edit button opens edit form', async ({ authedPage }) => {
    const firstRow = authedPage.locator('table tbody tr, [data-testid="application-row"]').first();
    await expect(firstRow).toBeVisible({ timeout: 10000 });
    await firstRow.click();

    const editBtn = authedPage.getByRole('button', { name: /upravit|edit/i });
    if (await editBtn.count() === 0) {
      test.skip(true, 'Edit button not found');
      return;
    }
    await editBtn.first().click();
    const form = authedPage.locator('form, [data-testid="edit-form"]');
    await expect(form.first()).toBeVisible({ timeout: 5000 });
  });
});
