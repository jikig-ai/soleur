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
// `adopt_seo_config_entrypoint` lives here, not in seo-config-rules.tf: 50 of
// the root's 51 variables are declared in variables.tf and the one outlier was
// drift.
const VARIABLES_PATH = path.join(
  REPO_ROOT,
  "apps/web-platform/infra/variables.tf",
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

/**
 * The pre-existing dashboard-created rule this resource had to ADOPT, and the
 * ID of the ruleset it lives in. Not this PR's work: a `kind = "zone"` ruleset
 * owns its phase entrypoint as a whole-list replacement, so leaving this rule
 * out of the config would have DELETED it from production rather than left it
 * alone, dropping app.soleur.ai to the zone-level SSL mode. See #6767.
 */
const ADOPTED_SSL_EXPRESSION = '(http.host eq "app.soleur.ai")';
const ADOPTED_RULESET_ID = "a21ac79d368f425a95c895c43a090d57";
const ADOPTED_SSL_REF = "dcb85b75bc3c4f4aa2a8c13a080bf854";

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
  const re = new RegExp(`\\b${escapeRegExp(name)}\\s*=\\s*"((?:[^"\\\\]|\\\\.)*)"`);
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

/**
 * The ruleset carries two rules with opposite host scopes, so every scope
 * assertion has to name which one it means. Selecting on the action parameter
 * rather than on position means reordering the blocks cannot silently point an
 * assertion at the wrong rule.
 */
function ruleWithParam(param: RegExp): string {
  const matches = allRuleBlocks().filter((r) => param.test(r));
  expect(
    matches,
    `expected exactly one rule matching ${param}`,
  ).toHaveLength(1);
  return matches[0];
}

/** This PR's rule: disables Email Obfuscation on the marketing hosts. */
function obfuscationRule(): string {
  return ruleWithParam(/email_obfuscation\s*=/);
}

/** The adopted pre-existing rule: Flexible SSL on app.soleur.ai. */
function flexibleSslRule(): string {
  return ruleWithParam(/ssl\s*=\s*"flexible"/);
}

/**
 * The `import` block's body, brace-matched.
 *
 * A `[^}]*` scan cannot be used here: the block contains `${var.cf_zone_id}`,
 * whose `}` terminates the class early. That made an earlier version of these
 * assertions depend on `to` happening to precede `id` — reordering two
 * order-independent HCL arguments broke a green build for no semantic reason.
 */
function importBlockBody(): string | null {
  const tf = stripHclComments(readFileSync(TF_PATH, "utf-8"));
  const open = tf.indexOf("import {");
  if (open === -1) return null;
  let depth = 0;
  for (let i = tf.indexOf("{", open); i < tf.length; i++) {
    if (tf[i] === "{") depth++;
    else if (tf[i] === "}") {
      depth--;
      if (depth === 0) return tf.slice(tf.indexOf("{", open) + 1, i);
    }
  }
  return null;
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
  //
  // The count is TWO, not one, and the second is not this PR's: a `kind="zone"`
  // ruleset owns its phase entrypoint as a whole-list replacement, so the
  // pre-existing dashboard-created Flexible SSL rule had to be adopted into
  // this resource or applying would have deleted it (#6767).
  test("ruleset declares exactly two rules", () => {
    expect(allRuleBlocks()).toHaveLength(2);
  });

  test("the rule disables email obfuscation via set_config and is enabled", () => {
    const rule = obfuscationRule();
    expect(rule).toMatch(/action\s*=\s*"set_config"/);
    expect(rule).toMatch(/email_obfuscation\s*=\s*false/);
    expect(rule).toMatch(/enabled\s*=\s*true/);
  });

  // Blast radius is measured in EFFECTS, not just hosts.
  //
  // The scope assertions above bound which requests the rule matches; they say
  // nothing about what it does to them. `set_config` can set any of ~24 edge
  // settings, so a rule that keeps the exact canonical host expression can still
  // widen production impact — adding `ssl = "off"` alongside `email_obfuscation`
  // would drop the marketing hosts to a plaintext origin, and it survived every
  // other assertion in this file. Pin the parameter SET, not just membership.
  test("each rule's action_parameters set exactly one expected setting", () => {
    const cases: ReadonlyArray<readonly [string, string, string]> = [
      ["obfuscation", obfuscationRule(), "email_obfuscation"],
      ["adopted Flexible SSL", flexibleSslRule(), "ssl"],
    ];
    for (const [label, rule, expected] of cases) {
      const params = rule.match(/action_parameters\s*\{([^}]*)\}/)?.[1];
      expect(params, `${label} rule has no action_parameters block`).toBeTruthy();
      const keys = (params as string)
        .split("\n")
        .map((l) => l.trim().match(/^([a-z_]+)\s*=/)?.[1])
        .filter((k): k is string => Boolean(k));
      expect(
        keys,
        `${label} rule must set exactly ["${expected}"] — a second setting widens its effect`,
      ).toEqual([expected]);
    }
  });

  // The load-bearing scope assertion. Exact equality, not a forbidden-host
  // deny-list — see the header comment for the mutants that motivated it.
  test("rule expression is exactly the canonical two-host scope", () => {
    expect(quotedAttr(obfuscationRule(), "expression")).toBe(
      CANONICAL_EXPRESSION,
    );
  });

  // Guards the adoption itself. This rule is NOT this PR's work — it is a live
  // production rule reproduced verbatim so that applying this resource does not
  // delete it. The failure mode being pinned is a future edit "tidying up" a
  // rule that looks unrelated to this file's stated purpose; doing so would
  // drop app.soleur.ai to the zone-level SSL mode. Both the expression and the
  // action parameter are pinned, because silently changing `flexible` to
  // `full`/`strict` breaks the origin just as effectively as deleting it.
  test("the adopted Flexible SSL rule is preserved verbatim", () => {
    const rule = flexibleSslRule();
    expect(quotedAttr(rule, "expression")).toBe(ADOPTED_SSL_EXPRESSION);
    expect(rule).toMatch(/action\s*=\s*"set_config"/);
    expect(rule).toMatch(/ssl\s*=\s*"flexible"/);
    expect(rule).toMatch(/enabled\s*=\s*true/);
    // `ref` is the live rule's existing ref. The v4 provider preserves rule IDs
    // across a whole-list PUT by matching on it, so dropping it re-randomises
    // both rules' IDs on every future edit — and makes "verbatim" untrue.
    expect(quotedAttr(rule, "ref")).toBe(ADOPTED_SSL_REF);
  });

  // Without a REACHABLE import block Terraform CREATES this resource, and
  // creating a zone entrypoint that already exists replaces its whole rule list.
  //
  // Every assertion here is mutation-motivated: an earlier version checked only
  // that an `import {` block existed mentioning the resource, plus that the
  // ruleset ID appeared somewhere in the file. Three independent reviewers
  // showed that version stayed 10/10 green while the import was disabled
  // (`for_each = toset([])`), inverted, stripped of its `provider`, or switched
  // to the v5 `zones/` prefix — i.e. it pinned the block's EXISTENCE and never
  // its EFFECT.
  test("the import block is present, reachable, and correctly addressed", () => {
    const body = importBlockBody();
    expect(body, "no import block found in seo-config-rules.tf").toBeTruthy();

    // Addressed at this resource.
    expect(body).toMatch(
      new RegExp(`to\\s*=\\s*${escapeRegExp(RESOURCE_ADDRESS)}`),
    );

    // REACHABLE: the gate must actually consume the variable, and the truthy
    // branch must be the non-empty set. `for_each = toset([])` is the mutation
    // that silently restores the create-instead-of-import path.
    expect(
      body,
      "for_each must consume var.adopt_seo_config_entrypoint",
    ).toMatch(/for_each\s*=\s*var\.adopt_seo_config_entrypoint\s*\?/);
    expect(
      body,
      'the truthy branch must be the NON-empty set (toset(["adopt"]))',
    ).toMatch(
      /var\.adopt_seo_config_entrypoint\s*\?\s*toset\(\[\s*"adopt"\s*\]\)\s*:\s*toset\(\[\s*\]\)/,
    );

    // Explicit provider. Not required — an import block inherits its target
    // resource's provider (measured: with this line removed and the default
    // provider's token replaced by garbage, the plan still reported `1 to
    // import`) — but pinned so it cannot be dropped silently.
    expect(body).toMatch(/provider\s*=\s*cloudflare\.rulesets/);

    // SINGULAR `zone/`. The v5/plural `zones/` form is what the provider's
    // published docs show, and on v4 it silently routes to the ACCOUNT path and
    // reports `Authentication error (10000)` — an error that names
    // authentication and sends you re-probing a credential that is fine.
    expect(body, "import ID must use the v4 singular `zone/` prefix").toMatch(
      new RegExp(
        `id\\s*=\\s*"zone/\\$\\{var\\.cf_zone_id\\}/${ADOPTED_RULESET_ID}"`,
      ),
    );
  });

  // The gate exists so the credential-free `terraform test` leg can opt out —
  // `mock_provider` does NOT mock import blocks, so Terraform issues a real API
  // read even under test. That escape hatch is only safe while the default is
  // true. Declared in variables.tf, not here (50 of 51 root vars live there).
  test("entrypoint adoption defaults to true", () => {
    const vars = stripHclComments(readFileSync(VARIABLES_PATH, "utf-8"));
    const block = vars.match(
      /variable\s+"adopt_seo_config_entrypoint"\s*\{[^}]*\}/,
    )?.[0];
    expect(
      block,
      "adopt_seo_config_entrypoint must be declared in variables.tf",
    ).toBeTruthy();
    expect(block).toMatch(/default\s*=\s*true/);
  });

  // Secondary assertions: strictly weaker than the exact-equality test above,
  // kept because they produce a far more legible failure message naming the
  // specific host that was gained or lost.
  //
  // Scoped to the obfuscation rule ONLY. It cannot iterate every rule any more:
  // the adopted Flexible SSL rule legitimately targets app.soleur.ai, which is
  // in OUT_OF_SCOPE_HOSTS. Running this over both rules would fail on the rule
  // it is not about — a false positive that would push someone toward
  // "fixing" it by deleting the adopted rule, which is the production
  // regression this whole file now guards against.
  test("rule expression covers both marketing hosts and no others", () => {
    const expression = quotedAttr(obfuscationRule(), "expression");
    expect(expression, "rule has no expression").not.toBeNull();
    for (const host of IN_SCOPE_HOSTS) {
      expect(expression, `expression must cover in-scope host ${host}`).toContain(
        `"${host}"`,
      );
    }
    for (const host of OUT_OF_SCOPE_HOSTS) {
      expect(
        expression,
        `expression must NOT reach out-of-scope host ${host}`,
      ).not.toContain(host);
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
