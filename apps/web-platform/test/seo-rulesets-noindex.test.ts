import { describe, test, expect } from "vitest";
import { readFileSync, existsSync } from "node:fs";
import path from "node:path";

// Source-text regression guard for the X-Robots-Tag noindex Transform Rules.
//
// Context (#4575): the `api.soleur.ai` and `deploy.soleur.ai` subdomains were
// reported leaking into the `sc-domain:soleur.ai` Search Console coverage
// report. The fix the issue asks for — an `X-Robots-Tag: noindex` Transform
// Rule at those edges — already shipped via PR #3296 (closed #3297) and lives
// in `apps/web-platform/infra/seo-rulesets.tf` under
// `cloudflare_ruleset.seo_response_headers`. Live `curl -sI` confirms
// `deploy.soleur.ai` returns `x-robots-tag: noindex, nofollow`; the
// `api.soleur.ai` rule is intentionally dormant (DNS-only CNAME bypasses the
// soleur.ai edge — owned by OPEN tracker #3379), but retained so a future
// proxy flip activates it without a code change.
//
// The live `deploy.` noindex was protected by NOTHING in CI before this guard.
// A future refactor of seo-rulesets.tf (e.g., a Bulk-Redirects consolidation,
// already foreshadowed in the file's comments) could silently drop the rewrite
// rule and re-expose `deploy.` to indexing. This test locks both rules in at
// the source level so that regression fails CI instead of shipping silently.
//
// Mirrors the canonical source-text-assertion precedent
// `apps/web-platform/test/github-app-manifest-parity.test.ts` (vitest +
// readFileSync of a committed infra/*.tf, asserts load-bearing literals rather
// than parsing the format — there is no HCL parser in the toolchain).
//
// Ref #4575. Tracker for the api. no-op: #3379.

const REPO_ROOT = path.resolve(__dirname, "../../..");
const TF_PATH = path.join(
  REPO_ROOT,
  "apps/web-platform/infra/seo-rulesets.tf",
);

const RESOURCE_NAME = "seo_response_headers";

/**
 * Extract the body of a `resource "cloudflare_ruleset" "<name>" { ... }` block
 * by brace-counting from the resource declaration. Returns the substring
 * between the opening `{` and its matching `}` (exclusive). Throws if the
 * resource is absent so a deleted-resource regression fails loudly rather than
 * silently passing on an empty string.
 */
function extractResourceBody(src: string, name: string): string {
  const marker = `resource "cloudflare_ruleset" "${name}"`;
  const start = src.indexOf(marker);
  if (start === -1) {
    throw new Error(`resource "cloudflare_ruleset" "${name}" not found in ${TF_PATH}`);
  }
  const openBrace = src.indexOf("{", start);
  if (openBrace === -1) {
    throw new Error(`opening brace for resource "${name}" not found`);
  }
  let depth = 0;
  for (let i = openBrace; i < src.length; i++) {
    const ch = src[i];
    if (ch === "{") depth++;
    else if (ch === "}") {
      depth--;
      if (depth === 0) return src.slice(openBrace + 1, i);
    }
  }
  throw new Error(`unbalanced braces in resource "${name}"`);
}

/**
 * Within a resource body, return the `rules { ... }` block whose body contains
 * the given host literal. Brace-counts each `rules {` so action_parameters /
 * headers nesting is captured in full. Throws if no matching rule is found.
 */
function extractRuleBlockForHost(resourceBody: string, host: string): string {
  // Anchor on the `rules {` block opener specifically — NOT the bare word
  // "rules", which also appears in `provider = cloudflare.rulesets`, in prose
  // ("locks both rules into source"), and in the developers.cloudflare.com/rules/
  // URL. Matching `rules\s*{` prevents a future comment with a stray `{` before
  // the first real rules block from desyncing the brace count and binding the
  // wrong rule.
  const opener = /\brules\s*\{/g;
  let m: RegExpExecArray | null;
  while ((m = opener.exec(resourceBody)) !== null) {
    const openBrace = resourceBody.indexOf("{", m.index);
    let depth = 0;
    let end = -1;
    for (let i = openBrace; i < resourceBody.length; i++) {
      const ch = resourceBody[i];
      if (ch === "{") depth++;
      else if (ch === "}") {
        depth--;
        if (depth === 0) {
          end = i;
          break;
        }
      }
    }
    if (end === -1) break;
    const block = resourceBody.slice(openBrace + 1, end);
    if (block.includes(`http.host eq \\"${host}\\"`)) {
      return block;
    }
    opener.lastIndex = end + 1;
  }
  throw new Error(`no rules block matching host "${host}" found in ${RESOURCE_NAME}`);
}

describe("seo-rulesets.tf X-Robots-Tag noindex guard (#4575)", () => {
  test("seo-rulesets.tf exists and declares the seo_response_headers ruleset", () => {
    expect(existsSync(TF_PATH), `missing ${TF_PATH}`).toBe(true);
    const tf = readFileSync(TF_PATH, "utf-8");
    expect(tf).toContain(`resource "cloudflare_ruleset" "${RESOURCE_NAME}"`);
  });

  // AC1 — both subdomain rules present in source.
  test("deploy.soleur.ai rewrite rule is present in seo_response_headers", () => {
    const tf = readFileSync(TF_PATH, "utf-8");
    const body = extractResourceBody(tf, RESOURCE_NAME);
    const rule = extractRuleBlockForHost(body, "deploy.soleur.ai");
    expect(rule).toContain(`action`);
    expect(rule).toContain(`"rewrite"`);
    expect(rule).toContain(`X-Robots-Tag`);
  });

  test("api.soleur.ai rewrite rule is present in seo_response_headers (dormant, retained — #3379)", () => {
    const tf = readFileSync(TF_PATH, "utf-8");
    const body = extractResourceBody(tf, RESOURCE_NAME);
    const rule = extractRuleBlockForHost(body, "api.soleur.ai");
    expect(rule).toContain(`"rewrite"`);
    expect(rule).toContain(`X-Robots-Tag`);
  });

  // GSC "Indexed, though blocked by robots.txt" on https://app.soleur.ai/:
  // app.soleur.ai is the login-gated product host. Its bare URL was indexed
  // despite a robots.txt Disallow (which blocks crawling, not indexing, and
  // prevented Google from seeing any noindex). The fix is a host-wide
  // X-Robots-Tag: noindex, nofollow edge rule (this resource) + allow-crawl in
  // app/robots.ts. app.soleur.ai is proxied (dns.tf cloudflare_record.app
  // proxied = true), so unlike api.soleur.ai this rule fires live.
  test("app.soleur.ai rewrite rule is present in seo_response_headers", () => {
    const tf = readFileSync(TF_PATH, "utf-8");
    const body = extractResourceBody(tf, RESOURCE_NAME);
    const rule = extractRuleBlockForHost(body, "app.soleur.ai");
    expect(rule).toContain(`action`);
    expect(rule).toContain(`"rewrite"`);
    expect(rule).toContain(`X-Robots-Tag`);
  });

  // AC2 — deploy. rule pins the EXACT live header value `noindex, nofollow`,
  // not just substring `noindex`, so dropping `nofollow` is caught.
  test("deploy.soleur.ai rule sets X-Robots-Tag to exactly 'noindex, nofollow'", () => {
    const tf = readFileSync(TF_PATH, "utf-8");
    const body = extractResourceBody(tf, RESOURCE_NAME);
    const rule = extractRuleBlockForHost(body, "deploy.soleur.ai");
    // The header value line inside this rule's action_parameters.headers block.
    expect(rule).toMatch(/name\s*=\s*"X-Robots-Tag"/);
    expect(rule).toMatch(/value\s*=\s*"noindex, nofollow"/);
  });

  // app.soleur.ai must pin the EXACT value — a future weakening that drops
  // `nofollow` (or otherwise mutates the value) must fail CI, same parity as
  // the deploy/api rules above.
  test("app.soleur.ai rule sets X-Robots-Tag to exactly 'noindex, nofollow'", () => {
    const tf = readFileSync(TF_PATH, "utf-8");
    const body = extractResourceBody(tf, RESOURCE_NAME);
    const rule = extractRuleBlockForHost(body, "app.soleur.ai");
    expect(rule).toMatch(/name\s*=\s*"X-Robots-Tag"/);
    expect(rule).toMatch(/value\s*=\s*"noindex, nofollow"/);
  });

  test("api.soleur.ai rule sets X-Robots-Tag to exactly 'noindex, nofollow'", () => {
    // Pin the EXACT value, not just substring `noindex`. The api. rule is
    // dormant today (DNS-only CNAME — #3379), but it is retained so a future
    // proxy flip activates it without a code change; if it ever fires it must
    // carry the same `noindex, nofollow` as deploy. A loose `noindex*` match
    // would let the retained rule be silently weakened to a no-snippet-only
    // `noindex` ahead of that flip.
    const tf = readFileSync(TF_PATH, "utf-8");
    const body = extractResourceBody(tf, RESOURCE_NAME);
    const rule = extractRuleBlockForHost(body, "api.soleur.ai");
    expect(rule).toMatch(/name\s*=\s*"X-Robots-Tag"/);
    expect(rule).toMatch(/value\s*=\s*"noindex, nofollow"/);
  });

  // Every host rewrite rule must stay enabled — a silent `enabled = false` is
  // as bad as a deletion (the header stops firing live).
  test("all subdomain rewrite rules are enabled", () => {
    const tf = readFileSync(TF_PATH, "utf-8");
    const body = extractResourceBody(tf, RESOURCE_NAME);
    for (const host of ["deploy.soleur.ai", "api.soleur.ai", "app.soleur.ai"]) {
      const rule = extractRuleBlockForHost(body, host);
      expect(rule, `${host} rule must be enabled`).toMatch(/enabled\s*=\s*true/);
    }
  });

  // AC3 — cross-link comments name both the existing tracker (#3379) and this
  // issue (#4575) so the api. no-op rationale stays discoverable. Scope the
  // match to the seo_response_headers resource body (not the whole file) and
  // forbid a trailing digit so `#33790` / `#45751` can't satisfy it — the
  // cross-link must live with the rule rationale, not anywhere in the file.
  test("seo_response_headers comment references both #3379 and #4575 trackers", () => {
    const tf = readFileSync(TF_PATH, "utf-8");
    const body = extractResourceBody(tf, RESOURCE_NAME);
    expect(body).toMatch(/#3379(?!\d)/);
    expect(body).toMatch(/#4575(?!\d)/);
  });
});
