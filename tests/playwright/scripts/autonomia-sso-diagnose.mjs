import fs from 'node:fs/promises';
import path from 'node:path';
import { chromium } from 'playwright';

const baseUrl = process.env.AUTONOMIA_CHAT_URL || 'https://agents.autonomia.site';
const email = process.env.AUTONOMIA_TEST_EMAIL;
const password = process.env.AUTONOMIA_TEST_PASSWORD;
const headless = process.env.HEADLESS !== 'false';
const artifactsDir = path.resolve(
  process.cwd(),
  process.env.SSO_ARTIFACTS_DIR || 'artifacts/autonomia-sso'
);

if (!email || !password) {
  console.error('Missing AUTONOMIA_TEST_EMAIL or AUTONOMIA_TEST_PASSWORD.');
  process.exit(2);
}

const redact = value =>
  value
    .replaceAll(password, '[REDACTED_PASSWORD]')
    .replaceAll(email, '[REDACTED_EMAIL]')
    .replace(/(accessToken|idToken|refreshToken|Authorization)"?\s*[:=]\s*"[^"]+/gi, '$1="[REDACTED_TOKEN]');

const log = (events, type, data = {}) => {
  events.push({
    type,
    at: new Date().toISOString(),
    ...data,
  });
};

const firstVisible = async (page, selectors) => {
  for (const selector of selectors) {
    const locator = page.locator(selector).first();
    try {
      if (await locator.isVisible({ timeout: 1000 })) return locator;
    } catch {
      // Keep trying alternate selectors; the Auth UI has changed a few times.
    }
  }
  return null;
};

const clickAutonomiaSso = async page => {
  const candidates = [
    page.getByRole('button', { name: /autonom/i }),
    page.getByRole('link', { name: /autonom/i }),
    page.getByText(/sign in with autonomia/i),
    page.getByText(/login with autonomia/i),
    page.getByText(/entrar com autonomia/i),
    page.getByText(/autonom\.ia/i),
  ];

  for (const candidate of candidates) {
    try {
      if (await candidate.first().isVisible({ timeout: 1500 })) {
        await candidate.first().click();
        return true;
      }
    } catch {
      // Try the next label.
    }
  }

  return false;
};

const fillAuthLogin = async page => {
  const emailInput = await firstVisible(page, [
    'input[type="email"]',
    'input[name="email"]',
    'input[name="username"]',
    'input[autocomplete="username"]',
    'input[placeholder*="email" i]',
  ]);

  if (emailInput) {
    await emailInput.fill(email);
  }

  const passwordInput = await firstVisible(page, [
    'input[type="password"]',
    'input[name="password"]',
    'input[autocomplete="current-password"]',
    'input[placeholder*="password" i]',
    'input[placeholder*="senha" i]',
  ]);

  if (passwordInput) {
    await passwordInput.fill(password);
  }

  const submitButton = await firstVisible(page, [
    'button[type="submit"]',
    'input[type="submit"]',
    'button:has-text("Login")',
    'button:has-text("Entrar")',
    'button:has-text("Sign in")',
    'button:has-text("Continuar")',
  ]);

  if (submitButton) {
    await submitButton.click();
  }

  return Boolean(emailInput && passwordInput && submitButton);
};

const clickIfVisible = async (page, label, locators) => {
  for (const locator of locators) {
    try {
      if (await locator.first().isVisible({ timeout: 1500 })) {
        await locator.first().click();
        return true;
      }
    } catch {
      // Try the next locator.
    }
  }
  return false;
};

const clearAuthPrompts = async (page, events) => {
  for (let attempt = 0; attempt < 4; attempt += 1) {
    const skippedPasskey = await clickIfVisible(page, 'skip-passkey', [
      page.getByRole('button', { name: /agora não/i }),
      page.getByRole('link', { name: /agora não/i }),
      page.getByText(/agora não/i),
      page.getByRole('button', { name: /not now/i }),
      page.getByText(/not now/i),
    ]);

    if (skippedPasskey) {
      log(events, 'auth-prompt-clicked', { prompt: 'skip-passkey' });
      await page.waitForLoadState('networkidle', { timeout: 10000 }).catch(() => {});
      await page.waitForTimeout(1500);
      continue;
    }

    const continued = await clickIfVisible(page, 'continue', [
      page.getByRole('button', { name: /^continuar$/i }),
      page.getByRole('button', { name: /^continue$/i }),
      page.getByText(/^continuar$/i),
    ]);

    if (continued) {
      log(events, 'auth-prompt-clicked', { prompt: 'continue' });
      await page.waitForLoadState('networkidle', { timeout: 10000 }).catch(() => {});
      await page.waitForTimeout(1500);
      continue;
    }

    break;
  }
};

const summarizeAuthorizeResponse = async response => {
  const status = response.status();
  const url = response.url();
  const contentType = response.headers()['content-type'] || '';
  const summary = { status, url, contentType };

  if (!contentType.includes('application/json')) return summary;

  try {
    const body = await response.json();
    summary.jsonKeys = Object.keys(body);
    summary.hasCode = Boolean(body.code);
    summary.hasState = Boolean(body.state);
    summary.redirectUri = body.redirectUri;
  } catch {
    summary.jsonParseError = true;
  }

  return summary;
};

const main = async () => {
  await fs.mkdir(artifactsDir, { recursive: true });

  const events = [];
  const browser = await chromium.launch({ headless });
  const context = await browser.newContext({
    viewport: { width: 1440, height: 1080 },
    ignoreHTTPSErrors: true,
  });
  const page = await context.newPage();

  page.on('framenavigated', frame => {
    if (frame === page.mainFrame()) {
      log(events, 'navigation', { url: redact(frame.url()) });
    }
  });
  page.on('console', message => {
    log(events, 'console', {
      level: message.type(),
      text: redact(message.text()).slice(0, 500),
    });
  });
  page.on('pageerror', error => {
    log(events, 'pageerror', { message: redact(error.message) });
  });
  page.on('requestfailed', request => {
    log(events, 'requestfailed', {
      url: redact(request.url()),
      failure: request.failure()?.errorText,
    });
  });
  page.on('response', async response => {
    const url = response.url();
    if (url.includes('/oauth/authorize') || url.includes('/auth/autonomia') || url.includes('/auth/sign_in')) {
      log(events, 'response', await summarizeAuthorizeResponse(response));
    }
  });

  try {
    await page.goto(baseUrl, { waitUntil: 'domcontentloaded', timeout: 45000 });
    await page.waitForLoadState('networkidle', { timeout: 15000 }).catch(() => {});

    const clicked = await clickAutonomiaSso(page);
    log(events, 'clicked-autonomia-sso', { clicked });

    await page.waitForLoadState('domcontentloaded', { timeout: 30000 }).catch(() => {});
    await page.waitForTimeout(1500);

    if (page.url().includes('auth.autonomia.site')) {
      const filled = await fillAuthLogin(page);
      log(events, 'filled-auth-login', { filled });
      await page.waitForLoadState('networkidle', { timeout: 20000 }).catch(() => {});
      await page.waitForTimeout(1500);
      await clearAuthPrompts(page, events);
    }

    await page.waitForTimeout(10000);

    const finalUrl = page.url();
    const visibleText = await page.locator('body').innerText({ timeout: 5000 }).catch(() => '');
    const storage = await context.cookies();
    const chatwootCookies = storage
      .filter(cookie => cookie.domain.includes('agents.autonomia.site'))
      .map(cookie => cookie.name);

    log(events, 'final-state', {
      url: redact(finalUrl),
      title: await page.title().catch(() => ''),
      bodySnippet: redact(visibleText).replace(/\s+/g, ' ').slice(0, 1200),
      chatwootCookies,
      isLoggedIn: /\/app\/accounts\/\d+/.test(finalUrl),
      isStillOnLogin: /\/app\/login/.test(finalUrl),
      isOnAuth: finalUrl.includes('auth.autonomia.site'),
    });

    await page.screenshot({
      path: path.join(artifactsDir, 'final.png'),
      fullPage: true,
    });
  } finally {
    await fs.writeFile(
      path.join(artifactsDir, 'events.json'),
      `${JSON.stringify(events, null, 2)}\n`
    );
    await browser.close();
  }

  const final = events.findLast(event => event.type === 'final-state');
  console.log(JSON.stringify(final, null, 2));
  console.log(`Artifacts: ${artifactsDir}`);

  if (!final?.isLoggedIn) process.exit(1);
};

main().catch(error => {
  console.error(redact(error.stack || error.message));
  process.exit(1);
});
