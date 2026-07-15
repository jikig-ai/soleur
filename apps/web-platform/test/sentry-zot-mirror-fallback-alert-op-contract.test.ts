import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { describe, it, expect } from "vitest";

// Cross-artifact contract test for the zot mirror-staleness fallback-rate alarm
// (#6278 / ADR-096 "Loud, no-SSH signal").
//
// The `zot-mirror-fallback-rate` Sentry issue-alert pages on the FIRST runtime
// zot→GHCR fallback / gate-degrade event (event_frequency count > 0 / 1h, #6285),
// matching the OR of FOUR runtime signals (filter_match="any"):
//   - registry == "ghcr-fallback"      (ci-deploy.sh rolling-deploy pull fallback)
//   - registry == "zot-gate-degraded"  (ci-deploy.sh dark-gate degrade beacon)
//   - stage    == "inngest_ghcr_fallback" (cloud-init.yml inngest fresh-boot pull)
//   - stage    == "app_ghcr_fallback"     (cloud-init.yml app-image fresh-boot pull, #6278 Phase 1b)
//
// The inngest/app boot events carry only `stage` (no feature/op), so the filter is
// `any` over the tag-VALUES, not `all` over feature+op. Each tag string is pinned
// in BOTH its emit site AND issue-alerts.tf so a rename in either — which would
// silently DARK the alert (the operator-only-finds-out-post-cutover failure mode
// this alarm exists to prevent) — breaks CI instead.

const here = dirname(fileURLToPath(import.meta.url));
const tf = readFileSync(join(here, "../infra/sentry/issue-alerts.tf"), "utf8");
const ciDeploy = readFileSync(join(here, "../infra/ci-deploy.sh"), "utf8");
const cloudInit = readFileSync(join(here, "../infra/cloud-init.yml"), "utf8");
<<<<<<< HEAD
// Repo root is three levels up from apps/web-platform/test (precedent: the
// apply-sentry-infra.yml read in the last leg of this file).
const soak = readFileSync(
  join(here, "../../../scripts/followthroughs/zot-soak-6122.sh"),
  "utf8",
);

// --- Derived extraction: the alarm's watched signal set -----------------------
//
// Scoped to the `filters_v2 = [ ... ]` block, NOT the whole resource block. A
// value-only regex over the resource returns the right four today only
// INCIDENTALLY (event_frequency's `value = 0` is unquoted and actions_v2 uses
// `target_type`), and would over-collect the first time a quoted filter of any
// other kind is added — which is how a test gets deleted instead of fixed.
function alarmFilterSet(): Set<string> {
  const start = tf.indexOf('resource "sentry_issue_alert" "zot_mirror_fallback_rate"');
  if (start === -1) throw new Error("zot_mirror_fallback_rate resource not found in issue-alerts.tf");
  const resource = tf.slice(start);
  const filtersStart = resource.indexOf("filters_v2 = [");
  if (filtersStart === -1) throw new Error("filters_v2 block not found on zot_mirror_fallback_rate");
  // Indentation-tolerant for the same reason as soakFailQueries: a hard-coded "\n  ]" is
  // coupled to `terraform fmt`'s current two-space output. A reindent would not return -1 —
  // it would find the NEXT column-2 `]` (actions_v2's), silently widening the block. Harmless
  // only by luck today (actions_v2 holds no tagged_event); a future quoted filter there would
  // over-collect into the watched set and make this parity assertion noise.
  const filtersRest = resource.slice(filtersStart);
  const filtersEnd = filtersRest.search(/\n[ \t]*\]/);
  if (filtersEnd === -1) throw new Error("filters_v2 block is not closed");
  const block = filtersRest.slice(0, filtersEnd);
  const set = new Set<string>();
  const re = /tagged_event\s*=\s*\{[^}]*?key\s*=\s*"([^"]+)"[^}]*?value\s*=\s*"([^"]+)"[^}]*?\}/g;
  for (const m of block.matchAll(re)) set.add(`${m[1]}:${m[2]}`);
  return set;
}

// --- Derived extraction: the soak's FAIL set ---------------------------------
//
// Parses the `declare -A FAIL_QUERIES=( ... )` block.
//
// What actually excludes the script's header prose is the REGEX SHAPE below
// (`[key]='...'`), not the block scoping — the header names all four signal
// literals, but in prose that the regex cannot match, so a whole-file scope
// would yield 0 and go RED, not vacuously green. (An earlier version of this
// comment claimed the opposite, and also claimed "a comment cannot live inside
// the array" — bash accepts comments inside an array assignment. Both were
// wrong, and crediting the scoping for safety it does not provide is what made
// a fragile scope implementation look adequate.)
//
// The block scoping's real and load-bearing job is excluding SIBLING ARRAYS:
// a `WARN_QUERIES` next door must not be counted as part of the FAIL set, or
// this test reports coverage the script's summing loop does not have.
function soakFailQueries(): Map<string, string> {
  const start = soak.indexOf("declare -A FAIL_QUERIES=(");
  // Fail LOUD on a missing/renamed block rather than silently widening. `indexOf` returns -1
  // when the anchor moves (e.g. the closing paren gets indented), and `slice(start, -1)` would
  // then scope the "array block" to nearly the whole FILE — where the header prose names all
  // four signal literals, so the extraction could pass while the array is gone. That is the
  // vacuity this test exists to prevent, so it must not be reachable through the test itself.
  if (start === -1) throw new Error("FAIL_QUERIES array block not found in zot-soak-6122.sh");
  // Stop at the FIRST closing paren at any indentation. A literal indexOf("\n)") does NOT
  // merely risk -1 — if FAIL_QUERIES' own paren is indented, it SKIPS PAST IT and lands on
  // the next column-0 paren, i.e. a SIBLING array's. The block then swallows both arrays and
  // this test reports all four signals while the script's loop sums only the ones actually in
  // FAIL_QUERIES. That is #6435 reintroduced THROUGH ITS OWN REGRESSION TEST, green all the
  // way. Verified: the indexOf form extracts 4 from a 2-entry FAIL_QUERIES + 2-entry sibling.
  const rest = soak.slice(start);
  const end = rest.search(/\n[ \t]*\)/);
  if (end === -1) throw new Error("FAIL_QUERIES array block is not closed");
  const block = rest.slice(0, end);
  const out = new Map<string, string>();
  for (const m of block.matchAll(/^\s*\[[a-z_]+\]='([^']+)'/gm)) {
    const query = m[1];
    // Exactly one tag in each query is quoted — the signal tag. feature:supply-chain
    // and op:image-pull are bare, so this projection cannot pick them up.
    const sig = query.match(/([a-z_]+):"([^"]+)"/);
    if (sig) out.set(sig[2], query);
  }
  return out;
}

function soakFailSet(): Set<string> {
  const set = new Set<string>();
  for (const [, query] of soakFailQueries()) {
    const m = query.match(/([a-z_]+):"([^"]+)"/);
    if (m) set.add(`${m[1]}:${m[2]}`);
  }
  return set;
}

const soakQueryFor = (signal: string) => soakFailQueries().get(signal);

const observability = readFileSync(join(here, "../server/observability.ts"), "utf8");

// Scope a `resource "sentry_issue_alert" "<name>"` BODY out of issue-alerts.tf —
// from its header to its own column-0 closing brace.
//
// The lower bound is load-bearing, not tidiness. Terminating at the NEXT `\nresource `
// header (the obvious shape, and what this did first) runs past the resource's own `}`
// and swallows the following rule's entire leading comment block. That made the
// boot-fatal GROUPING-anchor assertion vacuous: zot's scope contained web_terminal_boot_fatal's
// `# GROUPING NOTE (mirrors ...)` POINTER, which satisfied a /^#\s*GROUPING\b/m intended to
// find the paragraph the pointer names — so deleting the real paragraph still passed.
// Nested HCL braces are indented, so a column-0 `\n}` is unambiguously the resource's own.
function scopeResource(name: string): string {
  const header = `resource "sentry_issue_alert" "${name}"`;
  const start = tf.indexOf(header);
  if (start === -1) throw new Error(`resource not found in issue-alerts.tf: ${name}`);
  const block = tf.slice(start);
  const end = block.search(/\n\}\n/);
  if (end === -1) throw new Error(`resource block is not closed: ${name}`);
  return block.slice(0, end);
}

// Every rule's rationale lives in the contiguous `#` comment block ABOVE its
// `resource` header, so scopeResource() cannot see it. Walk back to the top of
// that block. Assertions about comment anchors MUST use this — slicing from the
// header alone silently yields a near-empty string, and a `not.toMatch()` against
// it passes vacuously (the exact false-green this file's subject matter is about).
function scopeResourceWithComment(name: string): string {
  const header = `resource "sentry_issue_alert" "${name}"`;
  const start = tf.indexOf(header);
  if (start === -1) throw new Error(`resource not found in issue-alerts.tf: ${name}`);
  const lines = tf.slice(0, start).split("\n");
  let i = lines.length - 1;
  while (i > 0 && (lines[i - 1].startsWith("#") || lines[i - 1].trim() === "#")) i--;
  const comment = lines.slice(i).join("\n");
  if (!comment.trim().startsWith("#")) {
    throw new Error(`no leading comment block found for resource: ${name}`);
  }
  return `${comment}\n${scopeResource(name)}`;
}

describe("zot-mirror-fallback-rate alert op contract", () => {
  it("ci-deploy.sh emits the supply-chain image-pull tags + both registry values", () => {
    expect(ciDeploy).toContain(`feature: "supply-chain"`);
    expect(ciDeploy).toContain(`op: "image-pull"`);
    // Pin the exact EMIT forms, not the bare tag literals: `ghcr-fallback` also
    // appears in several ci-deploy.sh comments, so a bare `toContain("ghcr-fallback")`
    // would stay GREEN even if the emit CALL were renamed — the silent-DARK failure
    // this guard exists to catch. `registry_pull_event ghcr-fallback` (the call site)
    // and `registry: "zot-gate-degraded"` (the jq tag literal) are emit-only.
    expect(ciDeploy).toContain("registry_pull_event ghcr-fallback");
    expect(ciDeploy).toContain(`registry: "zot-gate-degraded"`);
  });

  // The soak's bare `stage:"..."` queries depend on the TAG KEY being literally `stage` in
  // both boot emitters. Nothing else pins that key: the legs below pin each emit CALL form and
  // the parity legs pin the query STRING, so renaming the key (stage -> boot_stage) while
  // keeping the value literal leaves every other assertion GREEN — and the soak's stage:
  // queries then match zero events FOREVER.
  //
  // That is a silent false-PASS route on an irreversible action, and unlike the registry:
  // queries there is no canary: registry: shares its feature/op prefix with the ZOT_WEB/
  // ZOT_INNGEST sample queries, so a broken prefix drives the sample to 0 and FAILs the soak.
  // The stage: queries have no such self-validation, so the key is pinned here instead.
  it("both boot emitters tag with the literal key `stage` (the soak's bare stage: queries depend on it)", () => {
    // cloud-init.yml `_emit` -> tags:{stage,image_ref,host_id,detail}; emits app_ghcr_fallback.
    expect(cloudInit).toContain('"tags":{"stage":"%s","image_ref":"%s","host_id":"%s","detail":"%s"}');
    // soleur-host-bootstrap.sh `soleur-boot-emit` -> tags:{stage,host_id,region}; emits
    // inngest_ghcr_fallback. A separate emitter that happens to share the no-feature/op gap.
    const bootstrap = readFileSync(join(here, "../infra/soleur-host-bootstrap.sh"), "utf8");
    expect(bootstrap).toContain('"tags":{"stage":"%s","host_id":"%s","region":"cloud-init"}');
  });

  it("cloud-init.yml emits both fresh-boot fallback stages (inngest + app-image)", () => {
    // Pin the exact emit CALL forms — `app_ghcr_fallback` also appears in this PR's
    // Phase-1b explanatory comment, so pinning the bare stage would be vacuous.
    expect(cloudInit).toContain("soleur-boot-emit inngest_ghcr_fallback warning");
    expect(cloudInit).toContain(`"app_ghcr_fallback" warning`);
  });

  it("issue-alerts.tf pins all four signal tag-values (any-match OR)", () => {
    expect(tf).toContain(`value = "ghcr-fallback"`);
    expect(tf).toContain(`value = "zot-gate-degraded"`);
    expect(tf).toContain(`value = "inngest_ghcr_fallback"`);
    expect(tf).toContain(`value = "app_ghcr_fallback"`);
  });

  it("issue-alerts.tf declares the zot_mirror_fallback_rate resource with an any-match event_frequency rule", () => {
    expect(tf).toContain(
      'resource "sentry_issue_alert" "zot_mirror_fallback_rate"',
    );
    // Fire-on-first intent: event_frequency count > 0 within 1h (#6285). value MUST stay 0 —
    // any value > 0 is fleet-shape-dependent and silently unreachable whenever the per-group
    // event count cannot exceed it. See the resource comment in issue-alerts.tf for the
    // mechanism; do NOT "normalize" this to the value = 1 used by web_terminal_boot_fatal.
    const block = tf.slice(
      tf.indexOf('resource "sentry_issue_alert" "zot_mirror_fallback_rate"'),
    );
    const resourceEnd = block.indexOf("\nresource ");
    const scoped = resourceEnd === -1 ? block : block.slice(0, resourceEnd);
    expect(scoped).toMatch(/filter_match\s*=\s*"any"/);
    expect(scoped).toContain("event_frequency");
    expect(scoped).toMatch(/comparison_type\s*=\s*"count"/);
    expect(scoped).toMatch(/value\s*=\s*0/);
    expect(scoped).toMatch(/interval\s*=\s*"1h"/);
    // Pin the no-SSH page target: a silent removal of the notify action would
    // make the alarm fire-but-page-nobody (the exact Branch-B failure the CTO
    // ruling avoided). IssueOwners→ActiveMembers reaches the solo founder.
    expect(scoped).toContain("IssueOwners");
    expect(scoped).toContain("ActiveMembers");
  });

  // --- Parity: the soak gate must count every signal the alarm watches -------
  //
  // #6435: zot-soak-6122.sh queried only 2 of the 4 signals in the alarm's filter
  // set. registry:"zot-gate-degraded" and stage:"app_ghcr_fallback" were counted by
  // NOTHING, so an intermittently-degraded fleet produced FALLBACKS=0 with a
  // sufficient zot sample => PASS => GHCR retired (ADR-096 5.3-5.5, which rotates
  // AND revokes the PAT — no rollback) while the fleet was intermittently GHCR-served.
  //
  // The alarm and the soak are the two consumers of the same four literals; the emit
  // sites are pinned by the legs above. This leg makes the soak — the only unpinned
  // consumer, and the one gating an irreversible action — drift-proof.
  it("the soak gate's FAIL set equals the alarm's watched signal set (derived, both sides)", () => {
    const alarm = alarmFilterSet();
    // Guard against a vacuous pass if either extraction silently yields nothing.
    expect(alarm.size).toBe(4);
    expect(soakFailQueries().size).toBe(4);
    // Derived equality on BOTH sides — deliberately no canonical list here. A
    // WATCHED constant would be a third source of truth, not a parity test; this
    // shape gives "a 5th signal added to the alarm breaks CI" for free.
    expect(soakFailSet()).toEqual(alarm);
  });

  // The set-equality leg above projects each query down to its (key, value) pair,
  // which STRUCTURALLY DISCARDS the query prefix — so it cannot catch a prefix that
  // silently matches zero events forever. These four flat pins are the only thing
  // that can. Keep them flat and duplicated: a loop over a table hides a missing
  // entry, which is exactly how the 2-of-4 blindness survived review in the first
  // place. Duplication beats cleverness in a pin.
  //
  // THE PREFIX ASYMMETRY IS DELIBERATE AND LOAD-BEARING:
  //   ci-deploy.sh's jq payload carries feature+op, so the registry: queries are prefixed.
  //   cloud-init.yml's _emit writes only {stage,image_ref,host_id,detail} — NO feature/op —
  //   so the stage: queries MUST be bare. Sentry tag matching is exact: prefixing a
  //   stage: query makes it match zero events FOREVER, silently restoring the very
  //   blindness this PR removes. Proven live: stage:"bootstrap_complete" => 9 events,
  //   feature:supply-chain op:image-pull stage:"bootstrap_complete" => 0.
  it("pins the WHOLE query string for all four signals (the prefix trap)", () => {
    expect(soakQueryFor("ghcr-fallback")).toBe(
      'feature:supply-chain op:image-pull registry:"ghcr-fallback"',
    );
    expect(soakQueryFor("zot-gate-degraded")).toBe(
      'feature:supply-chain op:image-pull registry:"zot-gate-degraded"',
    );
    // BARE — no feature/op. See the asymmetry note above.
    expect(soakQueryFor("inngest_ghcr_fallback")).toBe(
      'stage:"inngest_ghcr_fallback"',
    );
    expect(soakQueryFor("app_ghcr_fallback")).toBe(
      'stage:"app_ghcr_fallback"',
    );
  });

  it("the -target wiring guards that the apply workflow creates the rule", () => {
    const wf = readFileSync(
      join(here, "../../../.github/workflows/apply-sentry-infra.yml"),
      "utf8",
    );
    expect(wf).toContain(
      "-target=sentry_issue_alert.zot_mirror_fallback_rate",
    );
  });
});

// ── #6429 ────────────────────────────────────────────────────────────────────
// The filed issue claimed `sandbox_startup_failure` shared the zot rule's
// `event_frequency` defect. It does not: it uses `event_unique_user_frequency`,
// whose group is stack-keyed (captureException), not message-keyed — so the
// high-cardinality-message unreachability that broke the zot rule cannot apply.
// The REAL defect is an off-by-one between the rule's stated intent and its
// config. Both Sentry conditions extend BaseEventFrequencyCondition, whose
// `passes()` compares with a STRICT `current_value > value`
// (sentry/rules/conditions/event_frequency.py) — the same semantics
// zot_mirror_fallback_rate's comment already documents.
describe("sandbox-startup-failure alert op contract (#6429)", () => {
  it("fires at its STATED intent: >2 distinct tenants == the comment's >=3", () => {
    // BODY ONLY — deliberately not scopeResourceWithComment(). The rule's rationale
    // comment necessarily spells out "value = 2 and not 3", so a bare /value\s*=\s*2/
    // over comment+body matches the PROSE and stays green with the config reverted to
    // 3. That false-pass was caught by mutation-testing this very assertion. Anchor on
    // the HCL assignment at line-start: a comment line begins with `#` and can never
    // match `^\s*value`.
    const body = scopeResource("sandbox_startup_failure");
    // Guard the condition CLASS: the discriminator vs the zot rule (RR-1). If this
    // ever became event_frequency, the count would be events-per-group rather than
    // distinct tenants and the threshold below would mean something else entirely.
    expect(body).toContain("event_unique_user_frequency");
    expect(body).toMatch(/comparison_type\s*=\s*"count"/);
    expect(body).toMatch(/interval\s*=\s*"1h"/);
    // RED pre-fix: value = 3 under a strict `>` fires at >=4 tenants, contradicting
    // the resource comment's ">=3 distinct tenants".
    expect(body).toMatch(/^\s*value\s*=\s*2\b/m);
    expect(body).not.toMatch(/^\s*value\s*=\s*3\b/m);
  });

  it("states the strict-`>` semantics inline so the 2 cannot be 'corrected' to 3", () => {
    // Separate from the threshold assertion above on purpose: this one SHOULD read the
    // comment. An unexplained `2` beside prose promising ">=3" reads as a typo and
    // invites a fix straight back into the off-by-one — the zot sibling documents the
    // same semantics for the same reason.
    const withComment = scopeResourceWithComment("sandbox_startup_failure");
    expect(withComment).toMatch(/strict/i);
    expect(withComment).toMatch(/current_value > value/);
  });

  it("pins the no-SSH page target (fire-but-page-nobody guard)", () => {
    const scoped = scopeResource("sandbox_startup_failure");
    expect(scoped).toContain("IssueOwners");
    expect(scoped).toContain("ActiveMembers");
  });

  it("keeps the sandbox emitter EXCEPTION-shaped so its issue-group stays stack-keyed", () => {
    // Capture-shape rule (RR-4): a message-event (captureMessage / a raw /store/
    // POST carrying `message:`) is grouped ON THE MESSAGE, so a high-cardinality
    // token in it mints a fresh group per event and ANY threshold > 0 becomes
    // unreachable — the zot rule's defect. An exception-event is stack-keyed and
    // its group is stable, which is what makes this rule's `> 2` meaningful.
    //
    // Both emit sites (agent-runner.ts, cc-dispatcher.ts) hand a caught `err`
    // straight to reportSilentFallback, so the branch below decides the shape.
    // T3: switching the Error arm to captureMessage must fail this.
    const errorArm = observability.slice(
      observability.indexOf("if (err instanceof Error)"),
    );
    const armEnd = errorArm.indexOf("} else if");
    const scoped = armEnd === -1 ? errorArm : errorArm.slice(0, armEnd);
    expect(scoped).toContain("Sentry.captureException");
    expect(scoped).not.toContain("Sentry.captureMessage");
    // event_unique_user_frequency counts DISTINCT `event.user` — with no user
    // scope every tenant collapses into one identity and the threshold can never
    // be crossed by a fleet-wide outage.
    expect(scoped).toContain("user");
  });
});

describe("web-host-terminal-boot-fatal comment anchors (#6429 / #6424 repeat-offence)", () => {
  it("anchors its GROUPING NOTE on the paragraph NAME, not a rottable line number", () => {
    const scoped = scopeResourceWithComment("web_terminal_boot_fatal");
    const noteAt = scoped.indexOf("GROUPING NOTE");
    // Fail loud rather than slicing from -1 — a negative index yields the last
    // character and turns every assertion below into a vacuous pass.
    expect(noteAt).toBeGreaterThan(-1);
    const note = scoped.slice(noteAt);
    // #6424 "repaired" this reference TO THE WRONG LINE (:1364 is the last line of
    // the CHANGE-TRIGGER paragraph; GROUPING starts two lines later) inside the very
    // PR whose purpose was fixing comment rot. A line number cannot survive an edit
    // above it; a paragraph name can. This is the fix, not a guard around the rot.
    expect(note).not.toMatch(/zot_mirror_fallback_rate:\d+/);
    expect(note).toMatch(/GROUPING paragraph/i);
    // The named paragraph must actually exist in the sibling it points at —
    // otherwise the anchor is just a prettier flavour of the same rot.
    expect(scopeResourceWithComment("zot_mirror_fallback_rate")).toMatch(
      /^#\s*GROUPING\b/m,
    );
  });
});
