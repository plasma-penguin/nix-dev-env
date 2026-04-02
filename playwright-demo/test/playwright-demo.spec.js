const { test, expect } = require('@playwright/test');

test('screenshot google.com', async ({ page }) => {
  await page.goto('https://www.google.com', { waitUntil: 'networkidle' });

  const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
  const filename = `google-${timestamp}.png`;

  await page.screenshot({ path: filename, fullPage: true });

  const title = await page.title();
  expect(title).toContain('Google');
});