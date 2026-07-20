import { describe, test, expect } from "vitest";
import { readFileSync, existsSync } from "node:fs";
import path from "node:path";

// Source-text regression guard for the host-scoped Email Obfuscation
// Configuration Rule.
//
// Context: Google Search Console's "Not found (404)" report (validation export
// 2026-07-20) failed on `https://soleur.ai/cdn-cgi/l/email-protection`.
// Cloudflare's Email Obfuscation feature rewrites every `mailto:` href and
// plaintext address in the served marketing HTML into a
// `/cdn-cgi/l/email-protection#<xor>` link. That path only resolves for the
// JS-decoded click path — a bare Googlebot crawl gets a 404. The census at
// implementation time found 30 such hrefs across the marketing pages
// (privacy-policy alone accounted for 20).
//
// The remedy is a Configuration Rule (`http_config_settings` phase) that turns
// the feature OFF for the two marketing hosts, removing the hrefs at source.
//
// Why not `Disallow: /cdn-cgi/` in robots.txt: Google explicitly advises
// against using robots.txt to block 404s, robots.txt cannot de-index, and the
// 30 internal links supply the precondition for "Indexed, though blocked by
// robots.txt" — the exact trap
// `knowledge-base/project/learnings/2026-06-14-gsc-indexed-though-blocked-by-robots-is-a-real-misconfig-not-benign.md`
// documents on this same zone.
//
// Why not zone-wide (`cloudflare_zone_settings_override`): the bounded host
// scope is the property that keeps this off `app.` / `deploy.` / `api.`. That
// scope is asserted explicitly below, in BOTH directions — it is the load-
// bearing difference between this remedy and the rejected zone-wide one.
//
// Mirrors the sibling source-text-assertion precedent
// `apps/web-platform/test/seo-rulesets-noindex.test.ts` (vitest + readFileSync
// of a committed infra/*.tf, asserting load-bearing literals rather than
// parsing the format — there is no HCL parser in the toolchain).

const REPO_ROOT = path.resolve(__dirname, "../../..");
const TF_PATH = path.join(
  REPO_ROOT,
  "apps/web-platform/infra/seo-config-rules.tf",
);
const WORKFLOW_PATH = path.join(
  REPO_ROOT,
  ".github/workflows/apply-web-platform-infra.yml",
);

const RESOURCE_NAME = "seo_config_settings";
const RESOURCE_ADDRESS = `cloudflare_ruleset.${RESOURCE_NAME}`;

/** The two marketing hosts the rule is scoped to. */
const IN_SCOPE_HOSTS = ["soleur.ai", "www.soleur.ai"];

/**
 * Hosts that MUST NOT be caught by the rule. `app.` is the login-gated product
 * host, `deploy.` the Cloudflare Access surface, `api.` the Supabase REST root
 * — none of them serve marketing copy, and widening the rule to cover them
 * would silently re-create the rejected zone-wide option.
 */
const OUT_OF_SCOPE_HOSTS = [
  "app.soleur.ai",
  "deploy.soleur.ai",
  "api.soleur.ai",
];

/**
 * Strip HCL line comments (`#` and `//`) while respecting double-quoted
 * strings, so an explanatory comment can freely name `app.soleur.ai` or
 * `robots.txt` without satisfying — or breaking — an assertion meant to bind
 * to real configuration.
 *
 * This is load-bearing: the negative blast-radius assertions below would
 * false-FAIL on the file's own rationale comment (which names every
 * out-of-scope host to explain why they are excluded) if comments survived.
 * Anchoring on syntax rather than bare tokens is the rule that keeps a
 * drift-guard honest — see AGENTS.md `cq-assert-anchor-not-bare-token`.
 */
function stripHclComments(src: string): string {
  let out = "";
  let inString = false;
  for (let i = 0; i < src.length; i++) {
    const ch = src[i];
    if (inString) {
      out += ch;
      if (ch === "\\") {
        // Preserve the escaped character verbatim; it cannot close the string.
        if (i + 1 < src.length) {
          out += src[i + 1];
          i++;
        }
      } else if (ch === '"') {
        inString = false;
      }
      continue;
    }
    if (ch === '"') {
      inString = true;
      out += ch;
      continue;
    }
    const isHashComment = ch === "#";
    const isSlashComment = ch === "/" && src[i + 1] === "/";
    if (isHashComment || isSlashComment) {
      // Skip to end of line, preserving the newline so line structure (and
      // therefore any line-oriented assertion) is unchanged.
      while (i < src.length && src[i] !== "\n") i++;
      out += "\n";
      continue;
    }
    out += ch;
  }
  return out;
}

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
    throw new Error(
      `resource "cloudflare_ruleset" "${name}" not found in ${TF_PATH}`,
    );
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
 * Return every `rules { ... }` block body within a resource body, brace-counted
 * so nested `action_parameters { ... }` is captured in full. Anchors on
 * `rules\s*\{` (the block opener) rather than the bare word "rules", which also
 * appears in `provider = cloudflare.rulesets`.
 */
function extractRuleBlocks(resourceBody: string): string[] {
  const opener = /\brules\s*\{/g;
  const blocks: string[] = [];
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
    blocks.push(resourceBody.slice(openBrace + 1, end));
    opener.lastIndex = end + 1;
  }
  return blocks;
}

/**
 * Read a quoted attribute value (`name = "..."`) out of a block, decoding
 * HCL's backslash escapes so a Cloudflare filter expression such as
 * `"(http.host in {\"soleur.ai\"})"` is compared in its logical form
 * `(http.host in {"soleur.ai"})` rather than its escaped source form.
 */
function quotedAttr(block: string, name: string): string | null {
  const re = new RegExp(`\\b${name}\\s*=\\s*"((?:[^"\\\\]|\\\\.)*)"`);
  const m = re.exec(block);
  if (!m) return null;
  return m[1].replace(/\\(.)/g, "$1");
}

/** The single rule that turns Email Obfuscation off. */
function extractSetConfigRule(): string {
  const tf = stripHclComments(readFileSync(TF_PATH, "utf-8"));
  const body = extractResourceBody(tf, RESOURCE_NAME);
  const rules = extractRuleBlocks(body);
  // Minimum-cardinality guard: a resource that parsed but yielded zero rules
  // would make every downstream `.find()` assertion vacuous.
  expect(rules.length, "expected at least one rules block").toBeGreaterThan(0);
  const rule = rules.find((r) => /action\s*=\s*"set_config"/.test(r));
  if (!rule) {
    throw new Error(
      `no rules block with action = "set_config" found in ${RESOURCE_NAME}`,
    );
  }
  return rule;
}

describe("seo-config-rules.tf Email Obfuscation Configuration Rule guard", () => {
  test("seo-config-rules.tf exists and declares the seo_config_settings ruleset", () => {
    expect(existsSync(TF_PATH), `missing ${TF_PATH}`).toBe(true);
    const tf = readFileSync(TF_PATH, "utf-8");
    expect(tf).toContain(`resource "cloudflare_ruleset" "${RESOURCE_NAME}"`);
  });

  // The phase is what makes this a Configuration Rule rather than a redirect or
  // header transform. `http_config_settings` is the only phase on the pinned
  // provider (4.52.7) that accepts `set_config`.
  test("ruleset declares the http_config_settings phase at zone kind", () => {
    const tf = stripHclComments(readFileSync(TF_PATH, "utf-8"));
    const body = extractResourceBody(tf, RESOURCE_NAME);
    expect(body).toMatch(/phase\s*=\s*"http_config_settings"/);
    expect(body).toMatch(/kind\s*=\s*"zone"/);
  });

  // The rule must actually turn the feature OFF and be live. `email_obfuscation
  // = true` (or a disabled rule) would leave the 404-producing hrefs in place
  // while the file still looked correct.
  test("set_config rule disables email obfuscation and is enabled", () => {
    const rule = extractSetConfigRule();
    expect(rule).toMatch(/email_obfuscation\s*=\s*false/);
    expect(rule).toMatch(/enabled\s*=\s*true/);
  });

  // Blast radius, positive direction: both marketing hosts must be covered.
  // Asserted on the QUOTED host literal so `"soleur.ai"` is not satisfied by
  // the `soleur.ai` tail of `"www.soleur.ai"`.
  test("rule expression covers both marketing hosts", () => {
    const rule = extractSetConfigRule();
    const expression = quotedAttr(rule, "expression");
    expect(expression, "set_config rule has no expression").not.toBeNull();
    for (const host of IN_SCOPE_HOSTS) {
      expect(
        expression,
        `expression must cover in-scope host ${host}`,
      ).toContain(`"${host}"`);
    }
  });

  // Blast radius, negative direction — the load-bearing one. This is what
  // distinguishes the host-scoped remedy from the rejected zone-wide
  // `cloudflare_zone_settings_override`. Asserted against the decoded
  // expression only, so the file's rationale comment may name these hosts.
  test("rule expression does not reach non-marketing hosts", () => {
    const rule = extractSetConfigRule();
    const expression = quotedAttr(rule, "expression");
    expect(expression, "set_config rule has no expression").not.toBeNull();
    for (const host of OUT_OF_SCOPE_HOSTS) {
      expect(
        expression,
        `expression must NOT reach out-of-scope host ${host}`,
      ).not.toContain(host);
    }
  });

  // A resource absent from the auto-apply allow-list is committed but never
  // applied — the silent-no-op class that tracker #3379 already documents for
  // a sibling rule on this same zone.
  test("resource is present in the apply workflow -target allow-list", () => {
    expect(existsSync(WORKFLOW_PATH), `missing ${WORKFLOW_PATH}`).toBe(true);
    const workflow = readFileSync(WORKFLOW_PATH, "utf-8");
    // Trailing boundary forbids a longer resource name (e.g.
    // `..._settings_v2`) from satisfying the assertion.
    const targetRe = new RegExp(
      `-target=${RESOURCE_ADDRESS.replace(/\./g, "\\.")}(?![\\w.])`,
    );
    expect(
      workflow,
      `${RESOURCE_ADDRESS} must appear in the -target allow-list`,
    ).toMatch(targetRe);
  });
});
