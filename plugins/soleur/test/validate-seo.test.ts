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

  // Per-page canonical-host gate (2026-06-12 GSC duplicate-canonical plan) — extends
  // the sitemap host-consistency invariant to each page's <link rel="canonical"> href.
  // A page whose canonical points at a different host than the sitemap (e.g. a www
  // variant while the sitemap/apex is canonical) 301-redirects in prod and induces the
  // GSC "Duplicate, Google chose different canonical than user" cluster. The expected
  // host is DERIVED from the sitemap's single <loc> host (no second literal pin to
  // drift), so the invariant is "every page canonical host == sitemap canonical host".

  test("fails when a page canonical host differs from the sitemap host", async () => {
    setupSite(); // sitemap + default pages all on example.com
    // Add a page whose canonical points at the www variant — otherwise fully valid,
    // so the host mismatch is the sole failure (single sitemap host keeps every
    // other check green).
    writeFileSync(
      `${TMP_DIR}/pages/rogue.html`,
      validHtml.replace(
        '<link rel="canonical" href="https://example.com/">',
        '<link rel="canonical" href="https://www.example.com/rogue/">',
      ),
    );
    const proc = Bun.spawn(["bash", SCRIPT, TMP_DIR], { stdout: "pipe", stderr: "pipe" });
    const exitCode = await proc.exited;
    const stdout = await new Response(proc.stdout).text();
    expect(exitCode).toBe(1);
    expect(stdout).toContain("differs from sitemap canonical host");
  });

  test("passes when all page canonical hosts match the sitemap host", async () => {
    setupSite();
    const proc = Bun.spawn(["bash", SCRIPT, TMP_DIR], { stdout: "pipe", stderr: "pipe" });
    const exitCode = await proc.exited;
    const stdout = await new Response(proc.stdout).text();
    expect(exitCode).toBe(0);
    expect(stdout).toContain("canonical host matches sitemap host");
  });

  test("fails when a SECOND rogue canonical tag points at a different host", async () => {
    setupSite();
    // The page declares the correct apex canonical first, then a rogue www one — the
    // exact duplicate-canonical failure mode. Checking only the first tag would let
    // this through; the gate must inspect EVERY canonical host.
    writeFileSync(
      `${TMP_DIR}/pages/double.html`,
      validHtml.replace(
        '<link rel="canonical" href="https://example.com/">',
        '<link rel="canonical" href="https://example.com/double/">\n<link rel="canonical" href="https://www.example.com/double/">',
      ),
    );
    const proc = Bun.spawn(["bash", SCRIPT, TMP_DIR], { stdout: "pipe", stderr: "pipe" });
    const exitCode = await proc.exited;
    const stdout = await new Response(proc.stdout).text();
    expect(exitCode).toBe(1);
    expect(stdout).toContain("differs from sitemap canonical host");
  });

  test("a relative-only canonical href is skipped (no pipefail abort, later pages still validated)", async () => {
    setupSite();
    // A relative canonical has no absolute host to compare. Under `set -euo pipefail`
    // an unguarded extraction would abort the whole run; the gate must skip cleanly so
    // this page and every subsequent page still get their other checks.
    writeFileSync(
      `${TMP_DIR}/pages/relative.html`,
      validHtml.replace(
        '<link rel="canonical" href="https://example.com/">',
        '<link rel="canonical" href="/relative/">',
      ),
    );
    const proc = Bun.spawn(["bash", SCRIPT, TMP_DIR], { stdout: "pipe", stderr: "pipe" });
    const exitCode = await proc.exited;
    const stdout = await new Response(proc.stdout).text();
    expect(exitCode).toBe(0);
    // The matching-host pages still emit their PASS line — proves the run was not aborted.
    expect(stdout).toContain("canonical host matches sitemap host");
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

  // Redirect-stub gate — guards the GSC `Page with redirect` cluster on the PATH
  // axis (sibling of the host-axis canonical-host gate above). Redirect stubs live
  // at /pages/*.html (meta-refresh + canonical-to-clean-URL, generated by
  // page-redirects.njk with eleventyExcludeFromCollections) and must NEVER appear
  // in the sitemap. The leak <loc> is synthesized from pageRedirects.js's shape.
  // See the 2026-06-01 GSC sitemap-redirect-leak plan.

  test("sitemap.xml with a /pages/*.html redirect stub fails", async () => {
    setupSite();
    // setupSite() writes a CLEAN default sitemap and has no content override —
    // overwrite it directly to inject the leak. Single host + lastmod keep every
    // OTHER sitemap check green so the redirect-stub gate is the sole failure.
    writeFileSync(
      `${TMP_DIR}/sitemap.xml`,
      '<urlset><url><loc>https://example.com/pages/pricing.html</loc><lastmod>2026-01-01</lastmod></url></urlset>',
    );
    const proc = Bun.spawn(["bash", SCRIPT, TMP_DIR], { stdout: "pipe", stderr: "pipe" });
    const exitCode = await proc.exited;
    const stdout = await new Response(proc.stdout).text();
    expect(exitCode).toBe(1);
    expect(stdout).toContain("contains redirecting URLs");
  });

  test("sitemap.xml with a root-level *.html (no /pages/) redirect URL fails", async () => {
    setupSite();
    // The gate predicate is an OR of two shapes: `\.html$` OR `/pages/`. The
    // /pages/*.html fixture above satisfies BOTH arms at once, so it cannot
    // detect a regression that narrows the regex to just `/pages/`. This case
    // exercises the `\.html$` arm in isolation (root-level .html, no /pages/).
    writeFileSync(
      `${TMP_DIR}/sitemap.xml`,
      '<urlset><url><loc>https://example.com/about.html</loc><lastmod>2026-01-01</lastmod></url></urlset>',
    );
    const proc = Bun.spawn(["bash", SCRIPT, TMP_DIR], { stdout: "pipe", stderr: "pipe" });
    const exitCode = await proc.exited;
    const stdout = await new Response(proc.stdout).text();
    expect(exitCode).toBe(1);
    expect(stdout).toContain("contains redirecting URLs");
  });

  test("sitemap.xml with only clean trailing-slash URLs passes the redirect-stub gate", async () => {
    setupSite(); // default fixture sitemap is a single trailing-slash <loc>
    const proc = Bun.spawn(["bash", SCRIPT, TMP_DIR], { stdout: "pipe", stderr: "pipe" });
    const exitCode = await proc.exited;
    const stdout = await new Response(proc.stdout).text();
    expect(exitCode).toBe(0);
    expect(stdout).toContain("no redirecting URLs");
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
