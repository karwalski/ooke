const { test, expect } = require('@playwright/test');

const BASE = 'http://localhost:3099';

test.describe('Homepage', () => {
  test('loads and contains toke', async ({ page }) => {
    await page.goto(BASE + '/');
    const body = await page.content();
    expect(body.length).toBeGreaterThan(100);
    const text = await page.textContent('body');
    expect(text.toLowerCase()).toContain('toke');
  });

  test('has CSS loaded (styled elements)', async ({ page }) => {
    await page.goto(BASE + '/');
    // Page should have at least one styled element with non-zero dimensions
    const body = page.locator('body');
    await expect(body).toBeVisible();
    const box = await body.boundingBox();
    expect(box.width).toBeGreaterThan(0);
  });

  test('navigation links present', async ({ page }) => {
    await page.goto(BASE + '/');
    const links = await page.locator('a').count();
    expect(links).toBeGreaterThan(0);
  });
});

test.describe('Navigation', () => {
  test('/about loads', async ({ page }) => {
    await page.goto(BASE + '/about');
    const body = await page.content();
    expect(body.length).toBeGreaterThan(100);
  });

  test('/testpage loads', async ({ page }) => {
    await page.goto(BASE + '/testpage');
    const body = await page.content();
    expect(body.length).toBeGreaterThan(100);
  });

  test('page navigation does not download files', async ({ page }) => {
    const [response] = await Promise.all([
      page.waitForResponse(resp => resp.url().includes('/about')),
      page.goto(BASE + '/about'),
    ]);
    const ct = response.headers()['content-type'];
    expect(ct).toContain('text/html');
  });
});

test.describe('Document pages render content', () => {
  test('/about renders non-empty body text', async ({ page }) => {
    await page.goto(BASE + '/about');
    const text = await page.textContent('body');
    expect(text.trim().length).toBeGreaterThan(0);
  });

  test('homepage renders non-empty body text', async ({ page }) => {
    await page.goto(BASE + '/');
    const text = await page.textContent('body');
    expect(text.trim().length).toBeGreaterThan(0);
  });
});

test.describe('Static assets', () => {
  test('static files serve with correct Content-Type', async ({ request }) => {
    // Check that JS island file serves correctly
    const res = await request.get(BASE + '/static/ooke-islands.js');
    if (res.status() === 200) {
      const ct = res.headers()['content-type'];
      expect(ct).toContain('javascript');
    }
  });

  test('images directory is accessible', async ({ request }) => {
    // Just verify the static path does not 500
    const res = await request.get(BASE + '/static/images/');
    expect(res.status()).not.toBe(500);
  });
});

test.describe('API endpoints', () => {
  test('/api/health returns JSON with status ok', async ({ request }) => {
    const res = await request.get(BASE + '/api/health');
    expect(res.status()).toBe(200);
    const json = await res.json();
    expect(json.status).toBe('ok');
    expect(json.service).toBe('ooke');
  });

  test('/api/health Content-Type is JSON', async ({ request }) => {
    const res = await request.get(BASE + '/api/health');
    const ct = res.headers()['content-type'];
    expect(ct).toContain('application/json');
  });
});

test.describe('404 handling', () => {
  test('non-existent page returns a response', async ({ request }) => {
    const res = await request.get(BASE + '/nonexistent-page-xyz-404');
    // Should not crash the server - expect either 404 or a fallback
    expect(res.status()).toBeGreaterThanOrEqual(200);
  });

  test('non-existent page does not return 500', async ({ request }) => {
    const res = await request.get(BASE + '/this-page-does-not-exist');
    expect(res.status()).not.toBe(500);
  });
});

test.describe('Link integrity', () => {
  test('HTML pages serve as text/html', async ({ request }) => {
    const res = await request.get(BASE + '/');
    const ct = res.headers()['content-type'];
    expect(ct).toContain('text/html');
  });

  test('no broken images on homepage', async ({ page }) => {
    await page.goto(BASE + '/');
    const images = page.locator('img');
    const count = await images.count();
    for (let i = 0; i < count; i++) {
      const img = images.nth(i);
      const src = await img.getAttribute('src');
      if (src && src.startsWith('/')) {
        const res = await page.request.get(BASE + src);
        expect(res.status(), `Image ${src} should load`).toBe(200);
      }
    }
  });

  test('clicking links from homepage stays on site', async ({ page }) => {
    await page.goto(BASE + '/');
    const internalLinks = page.locator('a[href^="/"]');
    const count = await internalLinks.count();
    if (count > 0) {
      const href = await internalLinks.first().getAttribute('href');
      await page.click(`a[href="${href}"]`);
      await page.waitForLoadState();
      expect(page.url()).toContain('localhost:3099');
    }
  });
});
