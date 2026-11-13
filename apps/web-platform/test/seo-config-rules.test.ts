import { describe, test, expect } from "vitest";
import { readFileSync, existsSync, readdirSync } from "node:fs";
import path from "node:path";
import {
  escapeRegExp,
  extractResourceBody,
  extractRuleBlocks,
  quotedAttr,
  stripHclComments,
} from "./lib/terraform-hcl-blocks";

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
 * ID of the ruleset it lives in. A `kind = "zone"` ruleset owns its phase
 * entrypoint as a whole-list replacement, so leaving this rule out of the
 * config would DELETE it from production rather than leave it alone (#6767).
 *
 * Adopted `flexible` on `app.soleur.ai` + `lb-staging.soleur.ai` on 2026-07-20;
 * made `strict` on `app.soleur.ai` only by the origin-TLS cleanup (ADR-321
 * item 13, #10479), which also removed the canary and strict-flip rules. The
 * rule is selected by its pinned `ref`, never by its `ssl` value: the value is
 * what a rollback changes, so it cannot also be the selector. A rollback to
 * `flexible` is a reviewed forward PR that edits these constants in the same
 * diff (runbooks/origin-tls-strict-flip.md "Rollback").
 */
const ADOPTED_SSL_EXPRESSION = '(http.host eq "app.soleur.ai")';
const ADOPTED_SSL_DESCRIPTION = "Strict SSL for app.soleur.ai (ADR-321, #10479)";
const ADOPTED_SSL_MODE = "strict";
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

// Comment-stripping (`stripHclComments`), decoded attribute reads
// (`quotedAttr`), and literal escaping (`escapeRegExp`) now live in
// ./lib/terraform-hcl-blocks — the lifted copies (#8364 review). The
// block-comment arm is load-bearing for the extraction helpers: brace
// counting cannot see comments, and a `/* rules { … } */`-wrapped rule
// otherwise still counts toward the pin.
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

/** The adopted pre-existing rule (strict SSL on app.soleur.ai), selected by its pinned ref. */
function adoptedSslRule(): string {
  return ruleWithParam(new RegExp(`ref\\s*=\\s*"${ADOPTED_SSL_REF}"`));
}

/**
 * The 2026-08-16 outage mitigation: `ssl = "full"` on the marketing hosts so the
 * edge accepts the expired GitHub Pages origin cert.
 *
 * Selected on `"full"` specifically, never on a bare /ssl\s*=/ — that would also
 * match the adopted `"strict"` rule and make `ruleWithParam`'s
 * exactly-one assertion fail confusingly. It also means a mutant that widens
 * this to `"off"` (plaintext to origin) does not silently satisfy this helper:
 * it fails the exactly-one assertion instead of passing under a laxer regex.
 */
function apexFullSslRule(): string {
  return ruleWithParam(/ssl\s*=\s*"full"/);
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

/** The resource body, comment-stripped. */
function body(): string {
  return extractResourceBody(stripHclComments(readFileSync(TF_PATH, "utf-8")), RESOURCE_NAME);
}
/** The `ssl` value a rule sets, or null when it sets none. */
function sslValue(rule: string): string | null {
  return rule.match(/^\s*ssl\s*=\s*"([^"]*)"\s*$/m)?.[1] ?? null;
}
/** Every .tf / .tftest.hcl file under apps/web-platform/infra (recursive; .terraform and node_modules skipped). */
function infraTerraformFiles(): string[] {
  const out: string[] = [];
  const walk = (d: string) => {
    for (const e of readdirSync(d, { withFileTypes: true })) {
      const full = path.join(d, e.name);
      if (e.isDirectory()) {
        if (e.name !== ".terraform" && e.name !== "node_modules") walk(full);
      } else if (/\.tf$|\.tftest\.hcl$/.test(e.name)) {
        out.push(full);
      }
    }
  };
  walk(path.join(REPO_ROOT, "apps/web-platform/infra"));
  return out;
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
  // THIRD rule added 2026-08-16 (apex outage): `ssl = "full"` on the marketing
  // hosts, so Cloudflare accepts the expired GitHub Pages origin cert instead of
  // serving 526. This count is the guard that forced this update to be
  // deliberate rather than incidental — working as designed. When the Pages cert
  // is valid again and that rule is removed, this goes back to 2.
  // The two ORIGIN-TLS rules (ADR-321 canary and strict flip) made it FIVE from #10479's flip PRs until the
  // cleanup (ADR-321 item 13, 2026-11-13) removed both and made the adopted rule itself strict: back to THREE.
  // An exact count is also the dispatch guard: a renamed resource yields 0 rules and must fail here, never
  // pass "0 checked" through the per-rule property rows below.
  test("ruleset declares exactly three rules (adopted strict SSL, email obfuscation, apex full)", () => {
    expect(allRuleBlocks()).toHaveLength(3);
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
      ["adopted strict SSL", adoptedSslRule(), "ssl"],
      ["apex Full SSL mitigation", apexFullSslRule(), "ssl"],
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

  // The outage mitigation relaxes CERTIFICATE VALIDATION on the hosts it
  // matches, so its scope carries the same weight as the obfuscation rule's and
  // is pinned the same way — exact equality against the canonical two-host set.
  // A mutant that widens this one to the zone would silently drop strict
  // validation from `deploy.`/`ssh.`/`registry.` too, which is precisely the
  // zone-wide option that was considered and rejected.
  test("apex Full SSL mitigation is scoped to exactly the canonical two hosts", () => {
    expect(quotedAttr(apexFullSslRule(), "expression")).toBe(
      CANONICAL_EXPRESSION,
    );
  });

  // `full` and `off` are one word apart and worlds apart: `full` still encrypts
  // CF→origin (it only skips cert VALIDATION), while `off` sends plaintext to
  // the origin. Pin the exact value so a "simplification" cannot downgrade the
  // transport while keeping every other assertion in this file green.
  test("apex Full SSL mitigation sets full, never off or flexible", () => {
    const rule = apexFullSslRule();
    expect(rule).toMatch(/ssl\s*=\s*"full"/);
    expect(rule).not.toMatch(/ssl\s*=\s*"off"/);
    expect(rule).toMatch(/action\s*=\s*"set_config"/);
    expect(rule).toMatch(/enabled\s*=\s*true/);
  });

  // This rule is TEMPORARY and its removal condition lives in a comment that a
  // future reader must actually find. Pinning the marker keeps the rule
  // self-identifying as removable, so it is not mistaken for permanent posture
  // once the incident is out of living memory.
  test("apex Full SSL mitigation declares itself temporary", () => {
    expect(quotedAttr(apexFullSslRule(), "description")).toMatch(/TEMPORARY/);
  });

  // Guard 1 (ADR-321 item 13, #10479): the adopted rule is strict, enabled,
  // ref-pinned, and its expression and description are exact. Deleting it
  // drops app.soleur.ai to the zone-level SSL mode; changing its `ssl` value
  // changes the origin transport for every user. Both are reviewed acts that
  // must edit the constants above in the same diff.
  test("the adopted rule is strict, enabled, ref-pinned, expression and description exact", () => {
    const rule = adoptedSslRule();
    expect(quotedAttr(rule, "expression")).toBe(ADOPTED_SSL_EXPRESSION);
    expect(quotedAttr(rule, "description")).toBe(ADOPTED_SSL_DESCRIPTION);
    expect(rule).toMatch(/action\s*=\s*"set_config"/);
    expect(sslValue(rule)).toBe(ADOPTED_SSL_MODE);
    expect(rule).toMatch(/^\s*enabled\s*=\s*true\s*$/m);
    // `ref` is the live rule's existing ref. The v4 provider preserves rule IDs
    // across a whole-list PUT by matching on it, so dropping it re-randomises
    // every rule's ID on every future edit.
    expect(quotedAttr(rule, "ref")).toBe(ADOPTED_SSL_REF);
  });

  // Guard 1 property, position-agnostic. `set_config` is non-terminating and the
  // LAST match wins, so a later ssl rule that matches app.soleur.ai would
  // override the adopted one whatever the adopted rule says. Hence: exactly one
  // rule sets `ssl = "strict"` and it is the adopted rule; every other
  // ssl-setting rule is the apex `full` rule on the canonical marketing
  // expression. Order between the obfuscation and apex rules is not pinned.
  // Keyed on ADOPTED_SSL_MODE ("strict") rather than a second literal, so the
  // reviewed rollback to `flexible` edits the constants only (simulated
  // 2026-11-13, runbooks/origin-tls-strict-flip.md "Rollback").
  test(`exactly one rule sets ssl = "${ADOPTED_SSL_MODE}", and it is the adopted rule`, () => {
    const same = allRuleBlocks().filter((r) => sslValue(r) === ADOPTED_SSL_MODE);
    expect(same).toHaveLength(1);
    expect(quotedAttr(same[0], "ref")).toBe(ADOPTED_SSL_REF);
  });

  test("every other ssl-setting rule is the apex full rule on the canonical marketing expression", () => {
    const others = allRuleBlocks().filter(
      (r) => sslValue(r) !== null && quotedAttr(r, "ref") !== ADOPTED_SSL_REF,
    );
    expect(others).toHaveLength(1);
    for (const r of others) {
      expect(sslValue(r)).toBe("full");
      expect(quotedAttr(r, "expression")).toBe(CANONICAL_EXPRESSION);
    }
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
  // the adopted strict SSL rule legitimately targets app.soleur.ai, which is
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

// ORIGIN-TLS CLEANUP TOMBSTONES (ADR-321 item 13, #10479). The canary and strict-flip rules, and the two Doppler-backed
// switches that set their `enabled` flags, were deleted by the cleanup that made the adopted rule strict. The rows below keep
// them deleted: a re-introduced switch or ORIGIN-TLS rule is a second app-host SSL path that Guard 1 above would have to
// reason about, and a rollback is a reviewed forward PR on the adopted rule, never a switch.
describe("seo-config-rules.tf origin-TLS cleanup tombstones (ADR-321 item 13)", () => {
  test("the resource declares NO dynamic rules block", () => {
    expect(body()).not.toMatch(/\bdynamic\s+"rules"/);
  });

  test("the resource carries no count/for_each of its own", () => {
    expect(body()).not.toMatch(/^\s*(count|for_each)\s*=/m);
  });

  test("no var.enable_origin_tls_ reference anywhere under apps/web-platform/infra/", () => {
    const offenders = infraTerraformFiles().filter((f) =>
      /var\.enable_origin_tls_/.test(stripHclComments(readFileSync(f, "utf-8"))),
    );
    expect(offenders.map((f) => path.relative(REPO_ROOT, f))).toEqual([]);
  });

  test("neither origin-TLS switch variable is declared (variables.tf or any other .tf)", () => {
    const vars = stripHclComments(readFileSync(VARIABLES_PATH, "utf-8"));
    expect(vars).not.toMatch(/variable\s+"enable_origin_tls_canary_rule"/);
    expect(vars).not.toMatch(/variable\s+"enable_origin_tls_strict"/);
    const offenders = infraTerraformFiles().filter((f) =>
      /variable\s+"enable_origin_tls_/.test(stripHclComments(readFileSync(f, "utf-8"))),
    );
    expect(offenders.map((f) => path.relative(REPO_ROOT, f))).toEqual([]);
  });

  test("no rule description starts with ORIGIN-TLS", () => {
    const offenders = allRuleBlocks().filter((r) => /^ORIGIN-TLS/.test(quotedAttr(r, "description") ?? ""));
    expect(offenders).toEqual([]);
  });

  // PLUMBING. Kept after the cleanup: they still guard a RE-INTRODUCED switch. A tfvars file or a workflow line that sets an
  // origin-TLS variable would let an SSL-mode change reach production without the reviewed rule edit Guard 1 pins.
  test("no tfvars file under apps/web-platform/infra can set a switch", () => {
    const dir = path.join(REPO_ROOT, "apps/web-platform/infra");
    const offenders: string[] = [];
    const walk = (d: string) => {
      for (const e of readdirSync(d, { withFileTypes: true })) {
        const full = path.join(d, e.name);
        if (e.isDirectory()) {
          if (e.name !== ".terraform" && e.name !== "node_modules") walk(full);
        } else if (/(^|\.)(auto\.)?tfvars(\.json)?$/.test(e.name) || /\.auto\.tfvars(\.json)?$/.test(e.name)) {
          offenders.push(path.relative(REPO_ROOT, full));
        }
      }
    };
    walk(dir);
    expect(offenders, "a tfvars file could set enable_origin_tls_* without a Doppler change").toEqual([]);
  });

  test("no workflow sets either switch (TF_VAR_enable_origin_tls_* or -var enable_origin_tls_*)", () => {
    const dir = path.join(REPO_ROOT, ".github/workflows");
    const offenders: string[] = [];
    for (const f of readdirSync(dir).filter((n) => /\.ya?ml$/.test(n))) {
      const live = readFileSync(path.join(dir, f), "utf-8")
        .split("\n")
        .filter((l) => !/^\s*#/.test(l));
      live.forEach((l, i) => {
        if (/TF_VAR_enable_origin_tls_|-var[ =]["']?enable_origin_tls_|ENABLE_ORIGIN_TLS_/.test(l)) {
          offenders.push(`${f}:${i + 1}`);
        }
      });
    }
    expect(offenders, "a workflow must not set the origin-TLS switches; they are Doppler-only").toEqual([]);
  });

  // The archived plan's "Guard 1 - strict-flip precondition test" (knowledge-base/project/plans/archive/20261105-200240-...-plan.md)
  // asked for a tree-level property: a tree with an app-host strict rule also contains the preconditions that make strict safe.
  // The adopted rule is strict in every tree since the cleanup, so the property is asserted unconditionally. The 443 publish at the
  // prod and first-boot docker-run sites is already mutation-pinned by infra/docker-run-tuple.test.sh (K24e, K27i); what was
  // unpinned was the LB monitor: an http/:80 monitor stays green on a broken :443 and the B1 fallback hides it.
  test("strict-flip precondition: the LB monitor probes https/443 with certificate validation", () => {
    const lb = stripHclComments(
      readFileSync(path.join(REPO_ROOT, "apps/web-platform/infra/cloudflare-lb.tf"), "utf-8"),
    );
    const m = lb.match(/resource\s+"cloudflare_load_balancer_monitor"\s+"web"\s*\{([\s\S]*?)\n\}/);
    expect(m, "cloudflare_load_balancer_monitor.web must exist").not.toBeNull();
    expect(m![1]).toMatch(/^\s*type\s*=\s*"https"\s*$/m);
    expect(m![1]).toMatch(/^\s*port\s*=\s*443\s*$/m);
    expect(m![1]).toMatch(/^\s*allow_insecure\s*=\s*false\s*$/m);
  });

  // The canary header is retired with the canary rule (`origin-tls-probe.sh --canary` now exits 64 and sends nothing).
  test("origin-tls-probe.sh no longer sends x-origin-tls-probe, and no rule expression matches it", () => {
    const probe = readFileSync(path.join(REPO_ROOT, "apps/web-platform/infra/origin-tls-probe.sh"), "utf-8");
    expect(probe).not.toContain("x-origin-tls-probe");
    const offenders = allRuleBlocks().filter((r) => (quotedAttr(r, "expression") ?? "").includes("x-origin-tls-probe"));
    expect(offenders).toEqual([]);
  });
});
