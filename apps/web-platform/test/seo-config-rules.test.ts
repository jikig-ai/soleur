import { describe, test, expect } from "vitest";
import { readFileSync, existsSync } from "node:fs";
import path from "node:path";

// Source-text regression guard for the host-scoped Email Obfuscation
// Configuration Rule.
//
// The full rationale — the GSC "Not found (404)" report, the 30-href census,
// why not robots.txt, why not zone-wide, and what the change trades away —
// lives in the header of the artifact this guards:
//   apps/web-platform/infra/seo-config-rules.tf
// It is deliberately NOT restated here; a duplicated rationale drifts the
// moment one copy is edited.
//
// What this file guards: the rule exists, is live, disables the feature, is
// registered for auto-apply, and — the load-bearing part — is scoped to
// EXACTLY the two marketing hosts.
//
// The scope assertion is exact-equality against a canonical expression rather
// than a deny-list of forbidden hostnames. That is deliberate: a deny-list
// constrains SPELLING, not SCOPE, and review demonstrated three separate
// mutants that name no forbidden host yet widen the rule to every subdomain
// in the zone (`or ends_with(http.host, ".soleur.ai")`,
// `or (http.zone_name eq "soleur.ai")`, a tautological disjunct). Each of
// those reintroduces the rejected zone-wide option through a guard whose
// stated purpose is to prevent it. Exact equality is appropriate here because
// the value is committed source text with zero measurement variance — there is
// no flake surface, and an expression edit SHOULD require a deliberate test
// update.
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

/**
 * The one expression the rule is permitted to carry, in DECODED form (HCL
 * backslash escapes resolved). Changing the rule's scope is a deliberate,
 * reviewed act — updating this constant alongside it is the feature, not
 * friction.
 */
const CANONICAL_EXPRESSION = '(http.host in {"soleur.ai" "www.soleur.ai"})';

/** Hosts the rule MUST cover. */
const IN_SCOPE_HOSTS = ["soleur.ai", "www.soleur.ai"];

/**
 * Hosts that MUST NOT be caught. `app.` is the login-gated product host,
 * `deploy.` the Cloudflare Access surface, `api.` the Supabase REST root —
 * none serve marketing copy.
 */
const OUT_OF_SCOPE_HOSTS = [
  "app.soleur.ai",
  "deploy.soleur.ai",
  "api.soleur.ai",
];

/**
 * Strip HCL comments — `#` and `//` line comments AND `/* *\/` block comments —
 * while respecting double-quoted strings.
 *
 * Block-comment handling is load-bearing for the EXTRACTION helpers below, not
 * for the assertions. `extractResourceBody` and `extractRuleBlocks` brace-count
 * over raw text, so a commented-out `rules { }` block would otherwise be
 * indistinguishable from a live one: review demonstrated a mutant that wraps
 * the real rule in a block comment and adds a live wider rule beside it, which
 * passed the whole suite because the extractor bound to the dead block. An
 * unbalanced brace inside a block comment breaks brace-counting in the other
 * direction, failing the suite for no reason.
 *
 * Note this is NOT what isolates the scope assertions from the .tf file's own
 * rationale comment (which names every out-of-scope host to explain why they
 * are excluded) — that isolation comes from `quotedAttr`, which reads the
 * expression's quoted attribute value, somewhere a comment cannot appear.
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
    if (ch === "/" && src[i + 1] === "*") {
      // Block comment: skip to the closing delimiter, preserving newlines so
      // line structure is unchanged.
      i += 2;
      while (i < src.length && !(src[i] === "*" && src[i + 1] === "/")) {
        if (src[i] === "\n") out += "\n";
        i++;
      }
      i++; // land on the '/' of the closer; loop's i++ steps past it
      continue;
    }
    if (ch === "#" || (ch === "/" && src[i + 1] === "/")) {
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
 * by brace-counting. Throws if absent so a deleted-resource regression fails
 * loudly rather than passing on an empty string.
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
 * Return EVERY `rules { ... }` block body within a resource body, brace-counted
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
 * Read a quoted attribute value (`name = "..."`), decoding HCL's backslash
 * escapes so a Cloudflare filter expression such as
 * `"(http.host in {\"soleur.ai\"})"` is compared in its logical form.
 */
function quotedAttr(block: string, name: string): string | null {
  const re = new RegExp(`\\b${name}\\s*=\\s*"((?:[^"\\\\]|\\\\.)*)"`);
  const m = re.exec(block);
  if (!m) return null;
  return m[1].replace(/\\(.)/g, "$1");
}

/**
 * Escape every regex metacharacter so an interpolated literal matches itself.
 * Escaping only `.` leaves `\` unescaped, which lets the input alter the
 * pattern's meaning rather than being matched verbatim (CodeQL
 * js/incomplete-sanitization).
 */
function escapeRegExp(literal: string): string {
  return literal.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

/** Every rules block in the ruleset, comment-stripped. */
function allRuleBlocks(): string[] {
  const tf = stripHclComments(readFileSync(TF_PATH, "utf-8"));
  return extractRuleBlocks(extractResourceBody(tf, RESOURCE_NAME));
}

describe("seo-config-rules.tf Email Obfuscation Configuration Rule guard", () => {
  test("seo-config-rules.tf exists and declares the seo_config_settings ruleset", () => {
    expect(existsSync(TF_PATH), `missing ${TF_PATH}`).toBe(true);
    const tf = stripHclComments(readFileSync(TF_PATH, "utf-8"));
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

  // Cardinality is load-bearing. Cloudflare evaluates EVERY rule in a ruleset,
  // so a second rule has full production effect; a guard that inspects only the
  // first `set_config` block would never see it. Pinning the count forces any
  // future rule to arrive with a deliberate test update.
  test("ruleset declares exactly one rule", () => {
    expect(allRuleBlocks()).toHaveLength(1);
  });

  test("the rule disables email obfuscation via set_config and is enabled", () => {
    const [rule] = allRuleBlocks();
    expect(rule).toMatch(/action\s*=\s*"set_config"/);
    expect(rule).toMatch(/email_obfuscation\s*=\s*false/);
    expect(rule).toMatch(/enabled\s*=\s*true/);
  });

  // The load-bearing scope assertion. Exact equality, not a forbidden-host
  // deny-list — see the header comment for the mutants that motivated it.
  test("rule expression is exactly the canonical two-host scope", () => {
    const [rule] = allRuleBlocks();
    expect(quotedAttr(rule, "expression")).toBe(CANONICAL_EXPRESSION);
  });

  // Secondary assertions: strictly weaker than the exact-equality test above,
  // kept because they produce a far more legible failure message naming the
  // specific host that was gained or lost.
  test("rule expression covers both marketing hosts and no others", () => {
    for (const rule of allRuleBlocks()) {
      const expression = quotedAttr(rule, "expression");
      expect(expression, "rule has no expression").not.toBeNull();
      for (const host of IN_SCOPE_HOSTS) {
        expect(
          expression,
          `expression must cover in-scope host ${host}`,
        ).toContain(`"${host}"`);
      }
      for (const host of OUT_OF_SCOPE_HOSTS) {
        expect(
          expression,
          `expression must NOT reach out-of-scope host ${host}`,
        ).not.toContain(host);
      }
    }
  });

  // A resource absent from the auto-apply allow-list is committed but never
  // applied — the silent-no-op class that tracker #3379 documents for a sibling
  // rule on this same zone.
  test("resource is present in the apply workflow -target allow-list", () => {
    expect(existsSync(WORKFLOW_PATH), `missing ${WORKFLOW_PATH}`).toBe(true);
    const workflow = readFileSync(WORKFLOW_PATH, "utf-8");
    // Drop YAML-commented lines before scanning: a `#`-commented -target entry
    // is inert, and the workflow carries a long header comment block that is
    // in scope for a naive whole-file substring scan.
    const liveLines = workflow
      .split("\n")
      .filter((line) => !/^\s*#/.test(line))
      .join("\n");
    // Trailing boundary forbids a longer resource name (e.g.
    // `..._settings_v2`) from satisfying the assertion.
    const targetRe = new RegExp(
      `-target=${escapeRegExp(RESOURCE_ADDRESS)}(?![\\w.])`,
    );
    expect(
      liveLines,
      `${RESOURCE_ADDRESS} must appear in the -target allow-list`,
    ).toMatch(targetRe);
  });
});
