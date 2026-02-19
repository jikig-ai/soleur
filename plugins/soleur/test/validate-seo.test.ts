import { describe, test, expect, beforeEach, afterEach } from "bun:test";
import { mkdirSync, writeFileSync, rmSync } from "fs";
import { resolve } from "path";

const SCRIPT = resolve(import.meta.dir, "../skills/seo-aeo/scripts/validate-seo.sh");
const TMP_DIR = resolve(import.meta.dir, "../test/.tmp-seo-test-site");

// Minimal valid HTML that passes all checks
const validHtml = `<!DOCTYPE html>
<html>
<head>
<link rel="canonical" href="https://example.com/">
<meta property="og:title" content="Test">
<meta name="twitter:card" content="summary_large_image">
<script type="application/ld+json">{"@type":"WebPage"}</script>
</head>
<body></body>
</html>`;

const homepageHtml = `<!DOCTYPE html>
<html>
<head>
<link rel="canonical" href="https://example.com/">
<meta property="og:title" content="Test">
<meta name="twitter:card" content="summary_large_image">
<script type="application/ld+json">{"@type":"WebPage","SoftwareApplication":"yes"}</script>
</head>
<body></body>
</html>`;

function setupSite(overrides?: { skipLlms?: boolean; skipCanonical?: boolean; skipSitemap?: boolean }) {
  mkdirSync(`${TMP_DIR}/pages`, { recursive: true });
  if (!overrides?.skipLlms) {
    writeFileSync(`${TMP_DIR}/llms.txt`, "# Test\n> description\n");
  }
  if (!overrides?.skipSitemap) {
    writeFileSync(`${TMP_DIR}/sitemap.xml`, '<urlset><url><loc>https://example.com/</loc><lastmod>2026-01-01</lastmod></url></urlset>');
  }
  const html = overrides?.skipCanonical
    ? validHtml.replace('<link rel="canonical" href="https://example.com/">', '')
    : validHtml;
  writeFileSync(`${TMP_DIR}/index.html`, homepageHtml.replace('"SoftwareApplication":"yes"', '"@type":"SoftwareApplication"'));
  writeFileSync(`${TMP_DIR}/pages/changelog.html`, html.replace("</body>", "<h2>v1.0.0</h2></body>"));
}

beforeEach(() => {
  rmSync(TMP_DIR, { recursive: true, force: true });
});

afterEach(() => {
  rmSync(TMP_DIR, { recursive: true, force: true });
});

describe("validate-seo.sh", () => {
  test("passes with all required elements", async () => {
    setupSite();
    const proc = Bun.spawn(["bash", SCRIPT, TMP_DIR], { stdout: "pipe", stderr: "pipe" });
    const exitCode = await proc.exited;
    expect(exitCode).toBe(0);
  });

  test("fails when llms.txt is missing", async () => {
    setupSite({ skipLlms: true });
    const proc = Bun.spawn(["bash", SCRIPT, TMP_DIR], { stdout: "pipe", stderr: "pipe" });
    const exitCode = await proc.exited;
    const stdout = await new Response(proc.stdout).text();
    expect(exitCode).toBe(1);
    expect(stdout).toContain("llms.txt missing");
  });

  test("fails when canonical URL is missing from a page", async () => {
    setupSite({ skipCanonical: true });
    const proc = Bun.spawn(["bash", SCRIPT, TMP_DIR], { stdout: "pipe", stderr: "pipe" });
    const exitCode = await proc.exited;
    const stdout = await new Response(proc.stdout).text();
    expect(exitCode).toBe(1);
    expect(stdout).toContain("missing canonical URL");
  });

  test("fails when sitemap has no lastmod", async () => {
    setupSite();
    writeFileSync(`${TMP_DIR}/sitemap.xml`, '<urlset><url><loc>https://example.com/</loc></url></urlset>');
    const proc = Bun.spawn(["bash", SCRIPT, TMP_DIR], { stdout: "pipe", stderr: "pipe" });
    const exitCode = await proc.exited;
    const stdout = await new Response(proc.stdout).text();
    expect(exitCode).toBe(1);
    expect(stdout).toContain("missing lastmod");
  });
});
