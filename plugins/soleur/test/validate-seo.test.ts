import { describe, test, expect, beforeEach, afterEach } from "bun:test";
import { mkdirSync, writeFileSync, rmSync } from "fs";
import { resolve } from "path";

const SCRIPT = resolve(import.meta.dir, "../skills/seo-aeo/scripts/validate-seo.sh");
const TMP_DIR = resolve(import.meta.dir, "../test/.tmp-seo-test-site");

// Minimal valid HTML that passes all checks (per PR #2973 — base.njk now requires
// no <base>, exactly one <h1>, non-empty meta description; FAQPage parity only
// fires when class="faq-(item|question|answer|list)" is rendered)
const validHtml = `<!DOCTYPE html>
<html>
<head>
<meta name="description" content="Test page description">
<link rel="canonical" href="https://example.com/">
<meta property="og:title" content="Test">
<meta name="twitter:card" content="summary_large_image">
<script type="application/ld+json">{"@type":"WebPage"}</script>
</head>
<body><h1>Test page</h1></body>
</html>`;

const homepageHtml = `<!DOCTYPE html>
<html>
<head>
<meta name="description" content="Homepage description">
<link rel="canonical" href="https://example.com/">
<meta property="og:title" content="Test">
<meta name="twitter:card" content="summary_large_image">
<script type="application/ld+json">{"@type":"WebPage","SoftwareApplication":"yes"}</script>
</head>
<body><h1>Homepage</h1></body>
</html>`;

function setupSite(overrides?: { skipLlms?: boolean; skipCanonical?: boolean; skipSitemap?: boolean; skipRobots?: boolean; robotsContent?: string }) {
  mkdirSync(`${TMP_DIR}/pages`, { recursive: true });
  if (!overrides?.skipLlms) {
    writeFileSync(`${TMP_DIR}/llms.txt`, "# Test\n> description\n");
  }
  if (!overrides?.skipRobots) {
    writeFileSync(`${TMP_DIR}/robots.txt`, overrides?.robotsContent ?? "User-agent: *\nAllow: /\n");
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

  // Canonical-host gate (#3297) — guards the GSC `Page with redirect` cluster
  // root cause where sitemap declared apex while live infra 301'd apex→www.

  test("fails when sitemap mixes multiple canonical hosts", async () => {
    setupSite();
    writeFileSync(
      `${TMP_DIR}/sitemap.xml`,
      '<urlset><url><loc>https://example.com/</loc><lastmod>2026-01-01</lastmod></url><url><loc>https://www.example.com/about/</loc><lastmod>2026-01-01</lastmod></url></urlset>',
    );
    const proc = Bun.spawn(["bash", SCRIPT, TMP_DIR], { stdout: "pipe", stderr: "pipe" });
    const exitCode = await proc.exited;
    const stdout = await new Response(proc.stdout).text();
    expect(exitCode).toBe(1);
    expect(stdout).toContain("sitemap.xml mixes multiple hosts");
  });

  test("fails when sitemap host disagrees with robots.txt Sitemap line", async () => {
    setupSite({
      robotsContent: "User-agent: *\nAllow: /\nSitemap: https://www.example.com/sitemap.xml\n",
    });
    // Default fixture sitemap uses https://example.com/ which does NOT match the www variant above.
    const proc = Bun.spawn(["bash", SCRIPT, TMP_DIR], { stdout: "pipe", stderr: "pipe" });
    const exitCode = await proc.exited;
    const stdout = await new Response(proc.stdout).text();
    expect(exitCode).toBe(1);
    expect(stdout).toContain("does not match robots.txt Sitemap line");
  });

  test("fails when sitemap has zero <loc> entries", async () => {
    setupSite();
    writeFileSync(
      `${TMP_DIR}/sitemap.xml`,
      '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"></urlset>',
    );
    const proc = Bun.spawn(["bash", SCRIPT, TMP_DIR], { stdout: "pipe", stderr: "pipe" });
    const exitCode = await proc.exited;
    const stdout = await new Response(proc.stdout).text();
    expect(exitCode).toBe(1);
    expect(stdout).toContain("sitemap.xml has no <loc> entries");
  });

  test("passes when sitemap host matches robots.txt Sitemap line", async () => {
    setupSite({
      robotsContent: "User-agent: *\nAllow: /\nSitemap: https://example.com/sitemap.xml\n",
    });
    const proc = Bun.spawn(["bash", SCRIPT, TMP_DIR], { stdout: "pipe", stderr: "pipe" });
    const exitCode = await proc.exited;
    const stdout = await new Response(proc.stdout).text();
    expect(exitCode).toBe(0);
    expect(stdout).toContain("sitemap host matches robots.txt Sitemap line");
  });

  test("fails when robots.txt is missing", async () => {
    setupSite({ skipRobots: true });
    const proc = Bun.spawn(["bash", SCRIPT, TMP_DIR], { stdout: "pipe", stderr: "pipe" });
    const exitCode = await proc.exited;
    const stdout = await new Response(proc.stdout).text();
    expect(exitCode).toBe(1);
    expect(stdout).toContain("robots.txt missing");
  });

  test("fails when robots.txt blocks an AI bot", async () => {
    setupSite({ robotsContent: "User-agent: GPTBot\nDisallow: /\n" });
    const proc = Bun.spawn(["bash", SCRIPT, TMP_DIR], { stdout: "pipe", stderr: "pipe" });
    const exitCode = await proc.exited;
    const stdout = await new Response(proc.stdout).text();
    expect(exitCode).toBe(1);
    expect(stdout).toContain("robots.txt blocks GPTBot");
  });

  test("does not flag wildcard User-agent block (known limitation)", async () => {
    setupSite({ robotsContent: "User-agent: *\nDisallow: /\n" });
    const proc = Bun.spawn(["bash", SCRIPT, TMP_DIR], { stdout: "pipe", stderr: "pipe" });
    const exitCode = await proc.exited;
    // Script only checks named AI bots, not wildcard rules
    expect(exitCode).toBe(0);
  });

  test("passes when robots.txt has partial path block (not root)", async () => {
    setupSite({ robotsContent: "User-agent: GPTBot\nDisallow: /private/\n" });
    const proc = Bun.spawn(["bash", SCRIPT, TMP_DIR], { stdout: "pipe", stderr: "pipe" });
    const exitCode = await proc.exited;
    const stdout = await new Response(proc.stdout).text();
    expect(exitCode).toBe(0);
    expect(stdout).toContain("robots.txt does not block GPTBot");
  });

  test("passes when an instant redirect page is present (meta refresh content=0)", async () => {
    setupSite();
    writeFileSync(
      `${TMP_DIR}/pages/articles.html`,
      '<!DOCTYPE html>\n<html><head><meta http-equiv="refresh" content="0;url=/blog/"></head></html>'
    );
    const proc = Bun.spawn(["bash", SCRIPT, TMP_DIR], { stdout: "pipe", stderr: "pipe" });
    const exitCode = await proc.exited;
    const stdout = await new Response(proc.stdout).text();
    expect(exitCode).toBe(0);
    expect(stdout).toContain("is a redirect (skipped SEO checks)");
  });

  test("fails when a delayed redirect page lacks SEO metadata (meta refresh content=5)", async () => {
    setupSite();
    writeFileSync(
      `${TMP_DIR}/pages/slow-redirect.html`,
      '<!DOCTYPE html>\n<html><head><meta http-equiv="refresh" content="5;url=/blog/"></head><body><p>Redirecting...</p></body></html>'
    );
    const proc = Bun.spawn(["bash", SCRIPT, TMP_DIR], { stdout: "pipe", stderr: "pipe" });
    const exitCode = await proc.exited;
    const stdout = await new Response(proc.stdout).text();
    expect(exitCode).toBe(1);
    expect(stdout).toContain("slow-redirect.html missing canonical URL");
  });
});
