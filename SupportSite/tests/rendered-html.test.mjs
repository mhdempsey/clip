import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

async function render() {
  const workerUrl = new URL("../dist/server/index.js", import.meta.url);
  workerUrl.searchParams.set("test", `${process.pid}-${Date.now()}`);
  const { default: worker } = await import(workerUrl.href);

  return worker.fetch(
    new Request("http://localhost/", {
      headers: { accept: "text/html" },
    }),
    {
      ASSETS: {
        fetch: async () => new Response("Not found", { status: 404 }),
      },
    },
    {
      waitUntil() {},
      passThroughOnException() {},
    },
  );
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
  assert.match(html, /Effective July 19, 2026/);
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
