import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { fileURLToPath } from "node:url";
import { unstable_dev } from "wrangler";

async function render() {
  const worker = await unstable_dev(fileURLToPath(new URL("../dist/server/index.js", import.meta.url)), {
    config: fileURLToPath(new URL("../dist/server/wrangler.json", import.meta.url)),
    local: true,
    ip: "127.0.0.1",
    port: 0,
    inspectorPort: 0,
    persist: false,
    logLevel: "error",
    experimental: { disableExperimentalWarning: true, disableDevRegistry: true },
  });
  try {
    const response = await worker.fetch("/", { headers: { accept: "text/html" } });
    return new Response(await response.text(), { status: response.status, headers: Object.fromEntries(response.headers) });
  } finally {
    await worker.stop();
  }
}

test("server-renders Clip support and privacy content", async () => {
  const response = await render();
  assert.equal(response.status, 200);
  assert.match(response.headers.get("content-type") ?? "", /^text\/html\b/i);

  const html = await response.text();
  assert.match(html, /<title>Clip — Listen, read, keep the good parts<\/title>/i);
  assert.match(html, /Your audiobook and ebook, in the same place/);
  assert.match(html, /say <strong>“Clip that.”<\/strong>/);
  assert.match(html, /id="privacy"/);
  assert.match(html, /Effective October 27, 2026/);
  assert.match(html, /mdemps9190@hotmail\.com/);
  assert.doesNotMatch(html, /codex-preview|react-loading-skeleton/);
});

test("keeps release-critical copy and metadata in source", async () => {
  const [page, layout, packageJson] = await Promise.all([
    readFile(new URL("../app/page.tsx", import.meta.url), "utf8"),
    readFile(new URL("../app/layout.tsx", import.meta.url), "utf8"),
    readFile(new URL("../package.json", import.meta.url), "utf8"),
  ]);

  assert.match(page, /DRM-free EPUB/);
  assert.match(page, /Apple Keychain/);
  assert.match(page, /Clip does not send data to/);
  assert.match(page, /Readwise access token/);
  assert.match(layout, /\/og\.png/);
  assert.match(layout, /x-forwarded-host/);
  assert.doesNotMatch(packageJson, /react-loading-skeleton/);
});

test("GitHub Pages build contains public support and privacy destinations", async () => {
  const [html, privacy, support, css] = await Promise.all([
    readFile(new URL("../../docs/index.html", import.meta.url), "utf8"),
    readFile(new URL("../../docs/privacy/index.html", import.meta.url), "utf8"),
    readFile(new URL("../../docs/support/index.html", import.meta.url), "utf8"),
    readFile(new URL("../../docs/styles.css", import.meta.url), "utf8"),
  ]);

  assert.match(html, /<meta property="og:url" content="https:\/\/mhdempsey\.github\.io\/clip\/">/);
  assert.match(html, /id="privacy"/);
  assert.match(html, /id="support"/);
  assert.match(html, /say <strong>“Clip that\.”<\/strong>/);
  assert.match(html, /Clip-Demo\.clipbook\.zip/);
  assert.match(privacy, /<title>Privacy Policy — Clip<\/title>/);
  assert.match(privacy, /Apple Keychain/);
  assert.match(support, /<title>Support — Clip<\/title>/);
  assert.match(support, /Email Clip support/);
  assert.match(css, /@media \(max-width: 520px\)/);
  assert.doesNotMatch(`${html}${privacy}${support}`, /localhost|codex-preview/);
});
