import { describe, test, expect } from "vitest";
import { readFileSync, existsSync } from "node:fs";
import path from "node:path";
import {
  extractResourceBody,
  extractRuleBlocks,
  quotedAttr,
  stripHclComments,
} from "./lib/terraform-hcl-blocks";

// Source-text pin for `cloudflare_ruleset.seo_page_redirects` — the zone-level
// http_request_dynamic_redirect phase owner in
// apps/web-platform/infra/seo-rulesets.tf. (#8364, guard gap 3)
//
// A `kind = "zone"` ruleset owns its phase entrypoint as a whole-list
// replacement at apply time, so this resource's source text IS the live edge
// redirect set — and until this suite nothing in CI pinned it (the sibling
// seo-rulesets-noindex.test.ts pins a DIFFERENT ruleset in the same file).
// The ruleset carries exactly 10 rules — the Cloudflare Free-tier per-phase
// cap — in load-bearing order:
//
//   Rules 1-8: /pages/<slug>.html → /<slug>/ SEO 301s for the high-traffic
//              legacy pages, each scoped to the two marketing hosts so a
//              legacy www deep-link collapses to the clean apex URL in a
//              single hop (2026-05-18 apex reconcile, #4577).
//   Rule 9:    /pages/legal/terms-of-service.html →
//              /legal/terms-and-conditions/ — the slug rename that was the
//              file's only confirmed GSC 404 bucket entry pre-fix.
//   Rule 10:   HTTPS catch-all with the ACME exclusion, positioned LAST so
//              the specific path rules match first (otherwise every legacy
//              hit would double-redirect: http → https → target). Its
//              `not (… /.well-known/acme-challenge/ …)` clause keeps Let's
//              Encrypt HTTP-01 renewal working for the GitHub Pages cert on
//              apex+www — `skip` cannot express it on this phase (CF API
//              error 20016), so it lives as a negative match in the
//              expression.
//
// Failure modes pinned, each independently load-bearing: a silently dropped
// rules {} block (count), a reordered catch-all (ordering), a weakened
// status_code (301→302), a lost ACME carve-out (cert renewal breaks), and any
// retargeted destination. The mutation battery at the bottom proves each edit
// trips the pin.
//
// Technique: brace-counted extraction via the shared
// test/lib/terraform-hcl-blocks helpers — there is no HCL parser in the
// toolchain (precedent: seo-rulesets-noindex.test.ts). Expression assertions
// compare DECODED text (HCL \" escapes resolved) so the pin names the logical
// filter, not its serialization — and expression scope is pinned by EXACT
// equality, the seo-config-rules.test.ts idiom: a deny-list constrains
// spelling, not scope, and an expression edit SHOULD require a deliberate
// test update.

const REPO_ROOT = path.resolve(__dirname, "../../..");
const TF_PATH = path.join(
  REPO_ROOT,
  "apps/web-platform/infra/seo-rulesets.tf",
);

const RESOURCE_NAME = "seo_page_redirects";

/**
 * The host set every page-redirect rule must match. Both hosts redirect
 * apex-ward per the 2026-05-18 fix; a one-host expression would strand legacy
 * www deep-links, and a widened one would catch hosts that never served the
 * /pages/*.html surface.
 */
const HOST_SET = '{"soleur.ai" "www.soleur.ai"}';

/**
 * Rule 10's expression, verbatim and decoded. Exact equality pins `not ssl`,
 * the ACME carve-out, and its two-host scope in one assertion.
 */
const CATCH_ALL_EXPRESSION = `(not ssl) and not (http.host in ${HOST_SET} and starts_with(http.request.uri.path, "/.well-known/acme-challenge/"))`;

/**
 * Rule 10's target_url expression — host-PRESERVING (no www/apex literal), so
 * the upgrade is canonical-agnostic by design (#4577).
 */
const CATCH_ALL_TARGET =
  'concat("https://", http.host, http.request.uri.path)';

/** Rules 1-8: legacy /pages/<slug>.html sources, in declared order. */
const PAGE_SLUGS = [
  "agents",
  "skills",
  "vision",
  "community",
  "getting-started",
  "legal",
  "pricing",
  "changelog",
] as const;

/** Rule 9: the terms-of-service → terms-and-conditions slug rename. */
const RENAME_RULE = {
  source: "/pages/legal/terms-of-service.html",
  target: "https://soleur.ai/legal/terms-and-conditions/",
} as const;

/** Decode HCL backslash escapes so expressions compare in logical form. */
function decode(src: string): string {
  return src.replace(/\\(.)/g, "$1");
}

function tf(): string {
  return readFileSync(TF_PATH, "utf-8");
}

/**
 * The ruleset body extracted from COMMENT-STRIPPED source — a `rules {}`
 * block wrapped in `/* * /` or `#`-commented lines must not count toward the
 * pin (#8364 review: raw-text extraction let a commented-out rule satisfy
 * every assertion).
 */
function rulesetBody(): string {
  return extractResourceBody(stripHclComments(tf()), RESOURCE_NAME);
}

function ruleBlocks(): string[] {
  return extractRuleBlocks(rulesetBody());
}

/** The canonical decoded expression for a page-redirect rule. */
function pageRuleExpression(sourcePath: string): string {
  return `(http.host in ${HOST_SET} and http.request.uri.path eq "${sourcePath}")`;
}

/**
 * Every load-bearing property of one positional redirect rule: redirect
 * action, enabled, exact two-host path-match expression, permanent status,
 * and the exact target URL.
 */
function checkPageRule(
  block: string | undefined,
  index: number,
  source: string,
  target: string,
): void {
  const label = `rule ${index + 1} (${source} → ${target})`;
  expect(block, `${label} is missing`).toBeTruthy();
  const rule = block as string;
  expect(rule, `${label} must use action "redirect"`).toMatch(
    /action\s*=\s*"redirect"/,
  );
  expect(rule, `${label} must be enabled`).toMatch(/enabled\s*=\s*true/);
  expect(
    quotedAttr(rule, "expression"),
    `${label} expression must be exactly the two-host ${source} match`,
  ).toBe(pageRuleExpression(source));
  expect(rule, `${label} must be a permanent redirect (301)`).toMatch(
    /status_code\s*=\s*301/,
  );
  expect(quotedAttr(rule, "value"), `${label} must target ${target}`).toBe(
    target,
  );
}

/**
 * Rule 10: the HTTPS catch-all. Ordering is pinned positionally — it is only
 * checked at index 9, so moving it earlier both displaces a page rule and
 * leaves a non-catch-all in the last slot.
 */
function checkCatchAllRule(block: string | undefined): void {
  expect(block, "rule 10 (HTTPS catch-all) is missing").toBeTruthy();
  const rule = block as string;
  expect(rule, "rule 10 must use action \"redirect\"").toMatch(
    /action\s*=\s*"redirect"/,
  );
  expect(rule, "rule 10 must be enabled").toMatch(/enabled\s*=\s*true/);
  expect(
    quotedAttr(rule, "expression"),
    "rule 10 must be the HTTPS catch-all with the ACME carve-out — and LAST",
  ).toBe(CATCH_ALL_EXPRESSION);
  expect(rule, "rule 10 must be a permanent redirect (301)").toMatch(
    /status_code\s*=\s*301/,
  );
  // preserve_query_string is load-bearing for UTM campaign links (file comment).
  expect(rule, "rule 10 must preserve the query string").toMatch(
    /preserve_query_string\s*=\s*true/,
  );
  expect(
    decode(rule),
    "rule 10 target must be the host-preserving concat() upgrade",
  ).toContain(`expression = "${CATCH_ALL_TARGET}"`);
}

/**
 * The whole pinned shape as throwing assertions — the single oracle the
 * mutation battery validates against, so the battery can never drift from the
 * pin it exercises.
 */
function assertPinnedShape(resourceBody: string): void {
  expect(resourceBody, 'kind must be "zone"').toMatch(/kind\s*=\s*"zone"/);
  expect(resourceBody, 'phase must be "http_request_dynamic_redirect"').toMatch(
    /phase\s*=\s*"http_request_dynamic_redirect"/,
  );
  expect(resourceBody, "must bind the zone via var.cf_zone_id").toMatch(
    /zone_id\s*=\s*var\.cf_zone_id/,
  );
  expect(resourceBody, "must use the rulesets provider alias").toMatch(
    /provider\s*=\s*cloudflare\.rulesets/,
  );
  const blocks = extractRuleBlocks(resourceBody);
  expect(
    blocks,
    "seo_page_redirects must declare exactly 10 rules {} blocks",
  ).toHaveLength(10);
  PAGE_SLUGS.forEach((slug, i) =>
    checkPageRule(
      blocks[i],
      i,
      `/pages/${slug}.html`,
      `https://soleur.ai/${slug}/`,
    ),
  );
  checkPageRule(blocks[8], 8, RENAME_RULE.source, RENAME_RULE.target);
  checkCatchAllRule(blocks[9]);
}

describe("seo-rulesets.tf seo_page_redirects pin (#8364)", () => {
  test("seo-rulesets.tf exists and declares the seo_page_redirects ruleset", () => {
    expect(existsSync(TF_PATH), `missing ${TF_PATH}`).toBe(true);
    expect(tf()).toContain(`resource "cloudflare_ruleset" "${RESOURCE_NAME}"`);
  });

  // The phase is what makes these Single Redirects rather than header
  // transforms or config settings; `zone` kind is what makes the source text
  // a whole-list replacement for the live phase entrypoint.
  test("ruleset is kind zone on the http_request_dynamic_redirect phase", () => {
    const body = rulesetBody();
    expect(body).toMatch(/kind\s*=\s*"zone"/);
    expect(body).toMatch(/phase\s*=\s*"http_request_dynamic_redirect"/);
  });

  // Cardinality is load-bearing: a zone ruleset is a whole-list replacement
  // at apply, so a dropped rules {} block deletes a live 301 — and 10 is also
  // the Free-tier per-phase cap, so an eleventh rule cannot land anyway.
  test("ruleset declares exactly 10 rules", () => {
    expect(ruleBlocks()).toHaveLength(10);
  });

  test("rules 1-8 are the /pages/<slug>.html → /<slug>/ 301s, in order", () => {
    const blocks = ruleBlocks();
    PAGE_SLUGS.forEach((slug, i) =>
      checkPageRule(
        blocks[i],
        i,
        `/pages/${slug}.html`,
        `https://soleur.ai/${slug}/`,
      ),
    );
  });

  test("rule 9 is the terms-of-service → terms-and-conditions rename", () => {
    checkPageRule(ruleBlocks()[8], 8, RENAME_RULE.source, RENAME_RULE.target);
  });

  test("rule 10 is last: HTTPS catch-all with the ACME carve-out", () => {
    checkCatchAllRule(ruleBlocks()[9]);
  });

  // Secondary host assertion (sibling-suite idiom): strictly weaker than the
  // exact-expression pins above, kept because its failure names the host set
  // directly rather than diffing a whole expression.
  test("page-rule expressions keep the { soleur.ai, www.soleur.ai } host set", () => {
    for (const block of ruleBlocks().slice(0, 9)) {
      expect(decode(block)).toContain(`http.host in ${HOST_SET}`);
    }
  });
});

/**
 * Rebuild a resource body from edited rule-block bodies, keeping everything
 * before the first `rules {` (kind, phase, provider, comments) intact so each
 * mutation below trips exactly the assertion it targets. Operates on a COPY —
 * the committed tf is never modified.
 */
function reassemble(resourceBody: string, blocks: string[]): string {
  const first = resourceBody.search(/\brules\s*\{/);
  const prefix = first === -1 ? resourceBody : resourceBody.slice(0, first);
  return `${prefix}${blocks.map((b) => `rules {${b}}`).join("\n")}\n`;
}

describe("mutation battery — each edit must trip the pin", () => {
  // Control: the unmutated body must satisfy the oracle, so a passing
  // mutation arm is never vacuous.
  test("control: the committed ruleset satisfies the pin", () => {
    assertPinnedShape(rulesetBody());
  });

  const mutations: ReadonlyArray<{
    label: string;
    failure: RegExp;
    mutate: (blocks: string[]) => string[];
  }> = [
    {
      label: "deleting a rules {} block",
      failure: /exactly 10 rules/,
      mutate: (b) => b.slice(1),
    },
    {
      label: "moving rule 10 ahead of the page rules",
      failure: /rule 1/,
      mutate: (b) => [b[9], ...b.slice(0, 9)],
    },
    {
      label: "301 → 302 on a page rule",
      failure: /301/,
      mutate: (b) =>
        b.map((x, i) =>
          i === 0
            ? x.replace(/status_code(\s*)=(\s*)301/, "status_code$1=$2302")
            : x,
        ),
    },
    {
      label: "removing the ACME carve-out from rule 10",
      failure: /catch-all|ACME/i,
      mutate: (b) =>
        b.map((x, i) =>
          i === 9
            ? x.replace(
                / and not \(http\.host in \{[^}]*\} and starts_with\([^)]*\)\)/,
                "",
              )
            : x,
        ),
    },
    {
      label: "changing a page rule's target",
      failure: /must target/,
      mutate: (b) =>
        b.map((x, i) =>
          i === 2
            ? x.replace(
                'value = "https://soleur.ai/vision/"',
                'value = "https://soleur.ai/vision-legacy/"',
              )
            : x,
        ),
    },
  ];

  for (const { label, failure, mutate } of mutations) {
    test(label, () => {
      const mutated = reassemble(rulesetBody(), mutate(ruleBlocks()));
      expect(() => assertPinnedShape(mutated)).toThrow(failure);
    });
  }

  // Raw-source arms: the block-level battery above cannot express mutations
  // that land in the RAW tf (comments, the resource header itself). These run
  // the full pipeline — strip → extract → pin — so a rule hidden inside a
  // comment is proven dead.
  const rawMutations: ReadonlyArray<{
    label: string;
    failure: RegExp;
    mutate: (raw: string) => string;
  }> = [
    {
      label: "wrapping the first page rule in a /* */ comment",
      failure: /exactly 10 rules/,
      mutate: (raw) => {
        const i = raw.indexOf("  rules {");
        const j = raw.indexOf("\n  }", i);
        expect(i, "first rules block not found").toBeGreaterThan(-1);
        expect(j, "first rules block close not found").toBeGreaterThan(i);
        return `${raw.slice(0, i)}  /*\n${raw.slice(i, j + 4)}\n  */${raw.slice(j + 4)}`;
      },
    },
    {
      label: "commenting out the resource declaration with # lines",
      failure: /not found/,
      mutate: (raw) =>
        raw.replace(
          /^resource "cloudflare_ruleset" "seo_page_redirects" \{/m,
          "# resource disabled\n# resource \"cloudflare_ruleset\" \"seo_page_redirects\" {",
        ),
    },
  ];

  for (const { label, failure, mutate } of rawMutations) {
    test(label, () => {
      const raw = mutate(tf());
      expect(raw, `${label}: mutation did not land`).not.toBe(tf());
      expect(() =>
        assertPinnedShape(
          extractResourceBody(stripHclComments(raw), RESOURCE_NAME),
        ),
      ).toThrow(failure);
    });
  }
});
