import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { beforeAll, describe, it, expect } from "vitest";

// Cross-artifact contract test for the zot mirror-staleness fallback-rate alarm
// (#6278 / ADR-096 "Loud, no-SSH signal").
//
// The `zot-mirror-fallback-rate` Sentry issue-alert pages on the FIRST zot degrade or
// terminal inngest-boot pull event (event_frequency count > 0 / 1h, #6285), matching the OR
// of TWO signals (logic_type "any-short"):
//   - registry == "zot-gate-degraded"  (ci-deploy.sh rolling-deploy degrade beacon)
//   - stage    == "inngest_pull_fatal" (cloud-init-inngest.yml + cloud-init.yml's colocated
//                                       block: a TERMINAL inngest fresh boot — NOT a fallback)
// The rule keeps its historical name; see its comment block in issue-alerts.tf (AP-021).
//
// RETIRED, pinned residual-zero below: #8036 1c removed `registry == "ghcr-fallback"` (no GHCR
// leg in ci-deploy.sh); #8036 1d removed `app_ghcr_fallback` / `app_ghcr_served` (the web seed
// block's GHCR arm is gone) and RENAMED `inngest_ghcr_fallback` → `inngest_pull_fatal` (fatal).
// The alarm's conditions, the soak's FAIL_QUERIES and the soak's runtime cardinality floor moved
// together in each PR — which is what the parity legs below now pin at 2.
//
// The inngest boot events carry only `stage` (no feature/op), so the filter is
// `any` over the tag-VALUES, not `all` over feature+op. Each tag string is pinned
// in BOTH its emit site AND issue-alerts.tf so a rename in either — which would
// silently DARK the alert (the operator-only-finds-out-post-cutover failure mode
// this alarm exists to prevent) — breaks CI instead.

const here = dirname(fileURLToPath(import.meta.url));
const tf = readFileSync(join(here, "../infra/sentry/issue-alerts.tf"), "utf8");
const ciDeploy = readFileSync(join(here, "../infra/ci-deploy.sh"), "utf8");
const cloudInit = readFileSync(join(here, "../infra/cloud-init.yml"), "utf8");
const cloudInitInngest = readFileSync(join(here, "../infra/cloud-init-inngest.yml"), "utf8");
// Repo root is three levels up from apps/web-platform/test.
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
  const start = tf.indexOf('resource "sentry_alert" "zot_mirror_fallback_rate"');
  if (start === -1) throw new Error("zot_mirror_fallback_rate resource not found in issue-alerts.tf");
  const resource = tf.slice(start);
  // `filters_v2 = [` became `conditions = [` INSIDE `action_filters` when this
  // rule was adopted as `sentry_alert` (#7650 Phase 2). Same contents — the
  // `tagged_event` regex below is unchanged — only the containing block renamed.
  //
  // Anchor through `action_filters` FIRST. A bare indexOf("conditions = [")
  // matches `trigger_conditions = [`, which appears EARLIER in the block and
  // holds no `tagged_event` — so the extractor returned an empty set and the
  // parity assertion below failed at its own non-vacuity floor rather than
  // silently comparing nothing. (It caught this; that floor is why.)
  const afStart = resource.indexOf("action_filters = [");
  if (afStart === -1) throw new Error("action_filters block not found on zot_mirror_fallback_rate");
  const filtersStart = resource.indexOf("conditions = [", afStart);
  if (filtersStart === -1) throw new Error("action_filters[].conditions block not found on zot_mirror_fallback_rate");
  // Indentation-tolerant for the same reason as soakFailQueries: a hard-coded "\n  ]" is
  // coupled to `terraform fmt`'s current two-space output. A reindent would not return -1 —
  // it would find the NEXT column-2 `]` (actions_v2's), silently widening the block. Harmless
  // only by luck today (actions_v2 holds no tagged_event); a future quoted filter there would
  // over-collect into the watched set and make this parity assertion noise.
  const filtersRest = resource.slice(filtersStart);
  const filtersEnd = filtersRest.search(/\n[ \t]*\]/);
  if (filtersEnd === -1) throw new Error("action_filters[].conditions block is not closed");
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

// Comment lines stripped (a line whose first non-blank character is `#`). Every emit-site and
// residual-zero leg below reads CODE only: the templates and the soak discuss the retired values
// in prose on purpose, and a bare-token assertion would red on the comment that explains the
// deletion — failing for the opposite of the right reason.
const codeLines = (text: string): string =>
  text
    .split("\n")
    .filter((l) => !/^\s*#/.test(l))
    .join("\n");

// Every stage a boot template EMITS, from its call sites on code lines: the host-local and
// bootstrap-defined `soleur-boot-emit <stage>`, the inngest Better Stack phone-home
// `inngest-boot-phone-home.sh <stage>`, and cloud-init.yml's `_emit "<msg>" <stage>`. A stage
// passed as a variable (`"$1"`, `"$STAGE"`) is skipped — it names no literal.
function emittedStages(text: string): string[] {
  const code = codeLines(text);
  const out: string[] = [];
  const res = [
    /soleur-boot-emit\s+"?([A-Za-z][A-Za-z0-9_-]*)/g,
    /inngest-boot-phone-home\.sh\s+"?([A-Za-z][A-Za-z0-9_-]*)/g,
    /_emit\s+"[^"]*"\s+"?([A-Za-z][A-Za-z0-9_-]*)/g,
  ];
  for (const re of res) for (const m of code.matchAll(re)) out.push(m[1]);
  return out;
}

const RETIRED = ["app_ghcr_fallback", "app_ghcr_served", "inngest_ghcr_fallback"] as const;

const observability = readFileSync(join(here, "../server/observability.ts"), "utf8");

// Scope a `resource "sentry_alert" "<name>"` BODY out of issue-alerts.tf —
// from its header to its own column-0 closing brace.
//
// The lower bound is load-bearing, not tidiness. Terminating at the NEXT `\nresource `
// header (the obvious shape, and what this did first) runs past the resource's own `}`
// and swallows the following rule's entire leading comment block. That made the
// boot-fatal GROUPING-anchor assertion vacuous: zot's scope contained web_terminal_boot_fatal's
// `# GROUPING NOTE (mirrors ...)` POINTER, which satisfied a /^#\s*GROUPING\b/m intended to
// find the paragraph the pointer names — so deleting the real paragraph still passed.
// Nested HCL braces are indented, so a column-0 `\n}` is unambiguously the resource's own.
function _scopeHeader(name: string): number {
  // Every rule is a `sentry_alert` since #8451 adopted the last two
  // `sentry_issue_alert` blocks (the legacy alert-rule API answers 410). A
  // `sentry_issue_alert` header is therefore "not found" here — which is the
  // correct failure, not a helper gap.
  return tf.indexOf(`resource "sentry_alert" "${name}"`);
}

function scopeResource(name: string): string {
  const start = _scopeHeader(name);
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
  const start = _scopeHeader(name);
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
  it("ci-deploy.sh emits the supply-chain image-pull tags + the surviving registry value", () => {
    expect(ciDeploy).toContain(`feature: "supply-chain"`);
    expect(ciDeploy).toContain(`op: "image-pull"`);
    // Pin the exact EMIT FORM, not the bare tag literal: `zot-gate-degraded` also appears in
    // ci-deploy.sh comments, so a bare `toContain("zot-gate-degraded")` would stay GREEN even
    // if the emit CALL were renamed — the silent-DARK failure this guard exists to catch.
    expect(ciDeploy).toContain(`registry: "zot-gate-degraded"`);
  });

  // #8036 1c, the OTHER direction — and the one that is not a restatement. The leg above pins
  // that a surviving emitter is still there; this pins that the RETIRED one cannot come back.
  // Anchored on the CALL SITE (`registry_pull_event ghcr-fallback`), never on the bare token:
  // ci-deploy.sh still discusses the retirement in prose, and a bare-token assertion would red
  // on the comment that explains the deletion — failing for the opposite of the right reason.
  it("ci-deploy.sh has no ghcr-fallback emit site left (#8036 1c residual-zero)", () => {
    expect(ciDeploy).not.toContain("registry_pull_event ghcr-fallback");
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
    // cloud-init.yml `_emit` -> tags:{stage,image_ref,host_id,detail,...}; emits app_ghcr_fallback.
    // Open prefix, not closed with `}`: #8651 APPENDED host_name after detail (ADR-147: add tags,
    // never rename) so the boot trail can attribute a fresh-boot event to its host. The prefix
    // still fails on a `stage` rename, a reorder, or a dropped tag — it tolerates only appends.
    expect(cloudInit).toContain('"tags":{"stage":"%s","image_ref":"%s","host_id":"%s","detail":"%s"');
    expect(cloudInit).toContain('"detail":"%s","host_name":"${host_name}"}}');
    // soleur-host-bootstrap.sh `soleur-boot-emit` -> tags:{stage,host_id,region,...}; emits
    // inngest_ghcr_fallback. A separate emitter that happens to share the no-feature/op gap.
    //
    // Deliberately NOT terminated with `}`: #6969/ADR-147 APPENDS host_name and detail tags to
    // this emitter, and ADR-147's design rule is "add tags, never rename". Pinning the closing
    // brace would forbid the additive case the rule explicitly allows, while adding nothing to
    // the anti-rename guarantee this test exists for. The open-ended prefix still fails on
    // `stage` -> `boot_stage`, on reordering, and on dropping host_id/region — it tolerates only
    // appended tags.
    const bootstrap = readFileSync(join(here, "../infra/soleur-host-bootstrap.sh"), "utf8");
    expect(bootstrap).toContain('"tags":{"stage":"%s","host_id":"%s","region":"cloud-init"');
  });

  // #8036 1d: BOTH inngest boot templates emit the terminal stage, at fatal, from a CODE line.
  // Two emitters for one value: the dedicated host's host-local `soleur-boot-emit` in
  // cloud-init-inngest.yml, and cloud-init.yml's gated colocated block (dead while
  // web_colocate_inngest=false, but a toggle flip must not resurrect an unwatched name). One
  // leg per file, so a rename that lands in one template only reds its own leg (Guard 2 row 2).
  // Pinned on the CALL FORM with the level, on comment-stripped text: the templates' rationale
  // prose names the stage, and prose must not satisfy an emit-site pin.
  it("cloud-init-inngest.yml emits inngest_pull_fatal at fatal (the dedicated host's miss arm)", () => {
    expect(codeLines(cloudInitInngest)).toContain("soleur-boot-emit inngest_pull_fatal fatal");
  });
  it("cloud-init.yml's colocated inngest block emits inngest_pull_fatal at fatal", () => {
    expect(codeLines(cloudInit)).toContain("soleur-boot-emit inngest_pull_fatal fatal");
  });

  // #6462: the fresh-boot DENOMINATOR. Since #8036 1d app_zot is the ONLY success arm of a web
  // fresh boot (app_ghcr_served retired with the GHCR arm), so it is the soak's proof the web
  // boot path was observed at all.
  //
  // EXISTENCE, pinned here, is deliberately SEPARATE from ORDERING (pinned in
  // cloud-init-user-data-size.test.ts). An indexOf-based ordering assert returns -1 on a
  // miss and -1 < everything, so ordering-alone PASSES on a tree with no beacon at all —
  // it cannot carry existence. Two ACs, two files, neither vacuously carrying the other.
  //
  // Pin the CALL FORM, not the bare stage token: rationale prose names the stage, so a bare
  // toContain() would be satisfied by a comment.
  it("cloud-init.yml emits the app_zot fresh-boot beacon (#6462 denominator)", () => {
    expect(cloudInit).toContain(`"app_zot" info`);
  });

  it("issue-alerts.tf pins both signal tag-values (any-match OR)", () => {
    // Anchored on the `tagged_event` CONSTRUCT, not a bare toContain: the rule's comment block
    // enumerates both values (and the retired ones) in prose, and prose cannot produce
    // `tagged_event = { … value = "…" }`. The migrated shape puts the value INLINE, so a
    // line-anchored `^\\s*value =` would match nothing.
    expect(tf).toMatch(/tagged_event\s*=\s*\{[^}]*key\s*=\s*"registry"[^}]*value\s*=\s*"zot-gate-degraded"/);
    expect(tf).toMatch(/tagged_event\s*=\s*\{[^}]*key\s*=\s*"stage"[^}]*value\s*=\s*"inngest_pull_fatal"/);
  });

  // apply-sentry-infra.yml plans the sentry root FULL (no `-target=` allowlist), so
  // the plan universe is `state UNION config`: declaring the resource IS what applies
  // it, and deleting this block is what destroys the live rule. Declaration is
  // therefore the whole apply contract — there is no separate "wired into the apply
  // list" condition left to assert.
  it("issue-alerts.tf declares the zot_mirror_fallback_rate resource with an any-match event_frequency rule", () => {
    expect(tf).toContain(
      'resource "sentry_alert" "zot_mirror_fallback_rate"',
    );
    // Fire-on-first intent: event_frequency count > 0 within 1h (#6285). value MUST stay 0 —
    // any value > 0 is fleet-shape-dependent and silently unreachable whenever the per-group
    // event count cannot exceed it. See the resource comment in issue-alerts.tf for the
    // mechanism. (web_terminal_boot_fatal is also value = 0 since #8036 1d.)
    const block = tf.slice(
      tf.indexOf('resource "sentry_alert" "zot_mirror_fallback_rate"'),
    );
    const resourceEnd = block.indexOf("\nresource ");
    const scoped = resourceEnd === -1 ? block : block.slice(0, resourceEnd);
    // `any-short` is the provider's spelling for OR on
    // `action_filters[].logic_type` (short-circuiting). Semantics are
    // identical to the old `filter_match = "any"`; only the spelling moved.
    expect(scoped).toMatch(/logic_type\s*=\s*"any-short"/);
    expect(scoped).toContain("event_frequency");
// The count-vs-percent discriminator moved from a `comparison_type` FIELD to
    // the attribute NAME: `{ event_frequency_count = { interval, value } }`.
    // Same semantics, and still unsatisfiable by prose.
    expect(scoped).toMatch(/event_frequency_count\s*=/);
    expect(scoped).toMatch(/value\s*=\s*0/);
    expect(scoped).toMatch(/interval\s*=\s*"1h"/);
    // Pin the no-SSH page target: a silent removal of the notify action would
    // make the alarm fire-but-page-nobody (the exact Branch-B failure the CTO
    // ruling avoided). IssueOwners→ActiveMembers reaches the solo founder.
    //
    // Anchored on the HCL assignment, NOT toContain(). This file carries in-BODY
    // comments naming both literals (":260" explains IssueOwners' fallthrough), so a
    // bare toContain() is satisfied by that prose — mutation-testing proved the whole
    // actions_v2 block could be deleted with the suite still 10/10 green. Prose cannot
    // produce `^\s*target_type =`.
    // The email action moved inline and lowercase on `sentry_alert`:
    // `{ email = { target_type = "issue_owners", fallthrough_type = ... } }`.
    // A line-anchored `^\\s*target_type =` therefore matches nothing, and the
    // CamelCase literal is gone. Anchored on the `email = {` construct so the
    // surrounding comments (which name both literals) still cannot satisfy it.
    expect(scoped).toMatch(/email\s*=\s*\{[^}]*target_type\s*=\s*"issue_owners"/);
    expect(scoped).toMatch(/email\s*=\s*\{[^}]*fallthrough_type\s*=\s*"ActiveMembers"/);
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
    // Guard against a vacuous pass if either extraction silently yields nothing (the
    // non-vacuity floor: an extractor that returns ∅ must red here, never compare ∅ = ∅).
    // 4 -> 5 with #6462's app_ghcr_served, 5 -> 4 with #8036 1c's retirement of
    // `ghcr-fallback`, 4 -> 2 with #8036 1d. The soak's RUNTIME cardinality floor
    // (zot-soak-6122.sh `${#FAIL_QUERIES[@]} != 2`) must move in lockstep: CI parses the
    // source, the sweeper executes it, and both must agree — a floor left at 4 over a 2-entry
    // array makes every sweep a permanent `exit 2` TRANSIENT, which nothing but these pins
    // catch before the sweeper does, a day later, as a comment on the tracker.
    expect(alarm.size).toBeGreaterThan(0);
    expect(alarm.size).toBe(2);
    expect(soakFailQueries().size).toBe(2);
    const floor = soak.match(/^if \(\( \$\{#FAIL_QUERIES\[@\]\} != (\d+) \)\); then$/m);
    expect(floor, "the soak's runtime FAIL_QUERIES floor literal was not found").not.toBeNull();
    expect(Number(floor![1])).toBe(soakFailQueries().size);
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
  it("pins the WHOLE query string for both signals (the prefix trap)", () => {
    expect(soakQueryFor("zot-gate-degraded")).toBe(
      'feature:supply-chain op:image-pull registry:"zot-gate-degraded"',
    );
    // BARE — no feature/op. `soleur-boot-emit` writes {stage,host_id,region,host_name,detail}
    // only, so a prefix here matches zero events forever. See the asymmetry note above.
    expect(soakQueryFor("inngest_pull_fatal")).toBe('stage:"inngest_pull_fatal"');
  });

  // #8036 1d, the OTHER direction: the three retired values cannot come back on ANY side — the
  // rule's conditions, the soak (array AND every code line), or either boot template's code.
  // Residual-zero on the rule is read from the EXTRACTED condition set, not the file: the
  // rule's comment block names the retired values on purpose.
  it("the three retired values are gone from the rule, the soak and both templates (residual-zero)", () => {
    const alarm = alarmFilterSet();
    const soakCode = codeLines(soak);
    // Non-vacuity floor for the scans below: each scanned text must be substantial CODE, so
    // pointing a scan at an empty/misread file reds instead of trivially "containing nothing".
    for (const [label, text] of [
      ["soak", soakCode],
      ["cloud-init.yml", codeLines(cloudInit)],
      ["cloud-init-inngest.yml", codeLines(cloudInitInngest)],
    ] as const) {
      expect(text.split("\n").length, `${label} code scan is vacuous`).toBeGreaterThan(100);
    }
    for (const v of RETIRED) {
      expect(alarm.has(`stage:${v}`), `rule still watches ${v}`).toBe(false);
      expect(soakFailQueries().has(v), `soak FAIL_QUERIES still counts ${v}`).toBe(false);
      expect(soakCode, `a soak code line still names ${v}`).not.toContain(v);
      expect(codeLines(cloudInit), `cloud-init.yml code still names ${v}`).not.toContain(v);
      expect(codeLines(cloudInitInngest), `cloud-init-inngest.yml code still names ${v}`).not.toContain(v);
    }
  });

  // Guard 2 residual (#8036 1d): a failure stage must not EXTEND the success stage's name.
  // Better Stack is searched by SUBSTRING (`--grep 'stage=inngest_zot'`, and the 7462/7674
  // probes' `count_stage inngest_zot`), so an `inngest_zot_miss` would be counted as a
  // zot-served boot there. Every emitted stage beginning with `inngest_zot` must BE inngest_zot.
  it("no emitted stage in either template begins with inngest_zot other than inngest_zot itself", () => {
    for (const [label, text] of [
      ["cloud-init.yml", cloudInit],
      ["cloud-init-inngest.yml", cloudInitInngest],
    ] as const) {
      const stages = emittedStages(text);
      const zotPrefixed = stages.filter((st) => st.startsWith("inngest_zot"));
      // Non-vacuity: the success stage itself must be found, or the extractor saw nothing.
      expect(zotPrefixed, `${label}: no inngest_zot emit found — extractor is blind`).toContain("inngest_zot");
      expect(zotPrefixed.filter((st) => st !== "inngest_zot"), `${label}: a stage extends inngest_zot`).toEqual([]);
    }
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
  it("keeps the distinct-USER trigger class, carried by type while the provider cannot model it (#8451)", () => {
    // BODY ONLY. Since #8451 the rule is a frozen `sentry_alert`: pinned provider
    // v0.15.7 cannot express `event_unique_user_frequency_count` natively, so the
    // HCL carries the trigger TYPE in `legacy_trigger_conditions` and the live
    // threshold (`{value = 2, interval = "1h"}`, strict `>`) is not in config at all.
    // The threshold is pinned by the live probe against the committed capture
    // (scripts/sentry-alert-live-fidelity.sh), not by this file.
    //
    // Guard the condition CLASS: the discriminator vs the zot rule (RR-1). If this
    // ever became event_frequency, the count would be events-per-group rather than
    // distinct tenants. Anchored on the assignment so the rationale prose above the
    // block (which names the type) cannot satisfy it.
    const body = scopeResource("sandbox_startup_failure");
    expect(body).toMatch(
      /^\s*legacy_trigger_conditions\s*=\s*\["event_unique_user_frequency_count"\]/m,
    );
  });

  it("states the strict-`>` semantics inline so the 2 cannot be 'corrected' to 3", () => {
    // Separate from the threshold assertion above on purpose: this one SHOULD read the
    // comment. An unexplained `2` beside prose promising ">=3" reads as a typo and
    // invites a fix straight back into the off-by-one — the zot sibling documents the
    // same semantics for the same reason.
    const withComment = scopeResourceWithComment("sandbox_startup_failure");
    // /strict/i alone is inert — the inline comment on the `value` line carries "STRICT",
    // so it passed even with this whole paragraph deleted. The paragraph-level claim is
    // what this pins. Deliberately NOT asserting the exact `current_value > value` quote:
    // that pins Sentry's INTERNAL variable naming into a regex over our comment, so an
    // upstream rename would force the comment to stay stale to keep the test green.
    expect(withComment).toMatch(/BaseEventFrequencyCondition/);
    expect(withComment).toMatch(/strict/i);
  });

  it("pins the no-SSH page target (fire-but-page-nobody guard)", () => {
    const scoped = scopeResource("sandbox_startup_failure");
    // Anchored on the `email = {` construct, not toContain() — see the zot sibling
    // above: prose naming both literals must not satisfy it. `sentry_alert` spells the
    // action inline and lowercase (#8451 moved this rule off `sentry_issue_alert`).
    expect(scoped).toMatch(/email\s*=\s*\{[^}]*target_type\s*=\s*"issue_owners"/);
    expect(scoped).toMatch(/email\s*=\s*\{[^}]*fallthrough_type\s*=\s*"ActiveMembers"/);
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
      // Anchor on the FUNCTION, not the first `instanceof Error` in the file — there are
      // four, and the others (warnSilentFallback et al.) do NOT pass `user`. Anchoring
      // positionally means "whatever check comes first", which is not what this guards.
      observability.indexOf("export function reportSilentFallback"),
    );
    expect(observability.indexOf("export function reportSilentFallback")).toBeGreaterThan(-1);
    const armEnd = errorArm.indexOf("} else if");
    const scoped = armEnd === -1 ? errorArm : errorArm.slice(0, armEnd);
    // Pin the CALL, not the bare symbol. `toContain("Sentry.captureException")` is inert:
    // the arm also holds a `typeof Sentry.captureException === "function"` guard line, so
    // it passed even under the captureMessage mutation — only the `.not` below caught it.
    expect(scoped).toMatch(/Sentry\.captureException\(\s*err/);
    expect(scoped).not.toContain("Sentry.captureMessage");
    // event_unique_user_frequency counts DISTINCT `event.user` — with no user
    // scope every tenant collapses into one identity and the threshold can never
    // be crossed by a fleet-wide outage.
    // Pin the shorthand property, not the bare word — `toContain("user")` is satisfied by
    // any `user`-containing identifier or comment in the slice (e.g. renaming
    // `transformedExtra` to `userExtra` would silence it while `, user` was dropped).
    expect(scoped).toMatch(/,\s*user\s*\}/);
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

// ── #8451: the two FROZEN rules ──────────────────────────────────────────────
// `auth_per_user_loop` and `sandbox_startup_failure` were adopted as `sentry_alert`
// under `lifecycle { ignore_changes = all }`, because any Create/Update from provider
// v0.15.7 re-sends their legacy trigger with `comparison: true` and destroys the paging
// threshold. Under the freeze an edit to these blocks plans "0 changes" — it LOOKS
// applied and is not. This is the static half of Guard 4: the frozen literals must
// equal the committed live capture, so a stale or edited block reds here instead of
// silently documenting a rule that does not exist. The live half (enabled, detector,
// threshold, action) is scripts/sentry-alert-live-fidelity.sh.
// A trigger/condition `comparison` is POLYMORPHIC in both the capture and the live
// API: `true` for the lifecycle and high-priority triggers, an ARRAY for
// `seer_activity_trigger` (`["pr_ready_for_review"]`), and an object for
// `event_frequency_count` / `event_unique_user_frequency_count` / `tagged_event`.
// Declaring it as one object shape was a cast that the other entries falsify, so the
// two use sites below narrow through an ASSERTED guard instead.
type FrequencyComparison = { value: number; interval: string };
type TagComparison = { key: string; match: string; value: string };
type Comparison = boolean | unknown[] | Record<string, unknown>;
const isFrequency = (c: Comparison): c is FrequencyComparison =>
  typeof c === "object" &&
  c !== null &&
  !Array.isArray(c) &&
  typeof (c as Record<string, unknown>).value === "number" &&
  typeof (c as Record<string, unknown>).interval === "string";
const isTag = (c: Comparison): c is TagComparison =>
  typeof c === "object" &&
  c !== null &&
  !Array.isArray(c) &&
  typeof (c as Record<string, unknown>).key === "string" &&
  typeof (c as Record<string, unknown>).match === "string" &&
  typeof (c as Record<string, unknown>).value === "string";

const CAPTURE = JSON.parse(
  readFileSync(
    join(
      here,
      "../../../knowledge-base/project/specs/fix-7650-sentry-alert-migration/phase34-live-workflows-capture-2026-09-09.json",
    ),
    "utf8",
  ),
) as Array<{
  id: string;
  name: string;
  enabled: boolean;
  detectorIds: string[];
  config: { frequency: number };
  triggers: { conditions: Array<{ type: string; comparison: Comparison }> };
  actionFilters: Array<{
    logicType: string;
    conditions: Array<{ type: string; comparison: Comparison }>;
    actions: Array<{ type: string; config: { targetType: string }; data: { fallthroughType: string } }>;
  }>;
}>;

const FROZEN = [
  { label: "auth_per_user_loop", id: "566671" },
  { label: "sandbox_startup_failure", id: "669246" },
] as const;

describe("frozen legacy-trigger rules equal the committed capture (#8451, Guard 4 static half)", () => {
  for (const { label, id } of FROZEN) {
    describe(label, () => {
      // Resolved lazily, inside each it(): a missing block must red THESE rows,
      // not abort collection of the whole file (which reports "no tests").
      let body = "";
      // The body with every comment line removed: a commented-out HCL line
      // must not satisfy an equality (review M18).
      let code = "";
      let nameInTf = "";
      let entry: (typeof CAPTURE)[number] | undefined;
      beforeAll(() => {
        body = scopeResource(label);
        code = body
          .split("\n")
          .filter((l) => !/^\s*#/.test(l))
          .join("\n");
        const m = body.match(/^\s*name\s*=\s*"([^"]*)"/m);
        if (!m) throw new Error(`${label}: no name assignment`);
        nameInTf = m[1];
        entry = CAPTURE.find((w) => w.name === nameInTf);
      });

      it("has a capture entry for its name, and that entry is the imported workflow id", () => {
        expect(entry, `no capture entry named ${nameInTf}`).toBeDefined();
        expect(entry!.id).toBe(id);
        // The import block must adopt THAT id — a wrong id is a plausible number that
        // adopts a different object (issue-alerts.tf "THE ID IS A WORKFLOW ID").
        expect(tf).toMatch(
          new RegExp(
            `import\\s*\\{\\s*to\\s*=\\s*sentry_alert\\.${label}\\s*id\\s*=\\s*"\\$\\{var\\.sentry_org\\}/${id}"`,
          ),
        );
        expect(tf).toMatch(
          new RegExp(
            `removed\\s*\\{\\s*from\\s*=\\s*sentry_issue_alert\\.${label}\\s*lifecycle\\s*\\{\\s*destroy\\s*=\\s*false`,
          ),
        );
      });

      it("frequency_minutes equals the capture", () => {
        const m = code.match(/^\s*frequency_minutes\s*=\s*(\d+)/m);
        expect(m, `${label}: no frequency_minutes`).not.toBeNull();
        expect(Number(m![1])).toBe(entry!.config.frequency);
      });

      it("action filter (logic, tag conditions, email action) equals the capture", () => {
        expect(entry!.actionFilters).toHaveLength(1);
        const af = entry!.actionFilters[0];
        expect(code).toMatch(new RegExp(`^\\s*logic_type\\s*=\\s*"${af.logicType}"`, "m"));
        const tfTags = [
          ...code.matchAll(
            /tagged_event\s*=\s*\{\s*key\s*=\s*"([^"]*)",\s*match\s*=\s*"([^"]*)",\s*value\s*=\s*"([^"]*)"\s*\}/g,
          ),
        ].map((m) => `${m[1]}|${m[2]}|${m[3]}`);
        const tagConditions = af.conditions.filter((c) => c.type === "tagged_event");
        // Assert the shape before mapping, never skip an element silently: a
        // `tagged_event` whose comparison is not {key, match, value} must RED here
        // rather than vanish from the comparison set.
        expect(tagConditions.every((c) => isTag(c.comparison))).toBe(true);
        const capTags = tagConditions.map((c) => {
          if (!isTag(c.comparison)) throw new Error(`${label}: tagged_event comparison is not {key, match, value}`);
          return `${c.comparison.key}|${c.comparison.match}|${c.comparison.value}`;
        });
        // Guard against a vacuous equality of two empty lists.
        expect(capTags.length).toBeGreaterThan(0);
        expect(af.conditions).toHaveLength(capTags.length);
        expect(tfTags.sort()).toEqual(capTags.sort());
        const tfEmail = [
          ...code.matchAll(
            /email\s*=\s*\{\s*target_type\s*=\s*"([^"]*)",\s*fallthrough_type\s*=\s*"([^"]*)"\s*\}/g,
          ),
        ].map((m) => `${m[1]}|${m[2]}`);
        const capEmail = af.actions
          .filter((a) => a.type === "email")
          .map((a) => `${a.config.targetType}|${a.data.fallthroughType}`);
        expect(capEmail.length).toBeGreaterThan(0);
        expect(af.actions).toHaveLength(capEmail.length);
        expect(tfEmail).toEqual(capEmail);
      });

      it("enabled and the detector binding match the capture (review M15/M16)", () => {
        expect(entry!.enabled).toBe(true);
        expect(code).toMatch(/^\s*enabled\s*=\s*true\s*$/m);
        // The capture binds the project issue-stream detector; the block must
        // bind the data source that resolves to it, and nothing else.
        expect(entry!.detectorIds).toHaveLength(1);
        expect(code).toMatch(
          /^\s*monitor_ids\s*=\s*\[data\.sentry_project_issue_stream_monitor\.web_platform\.id\]\s*$/m,
        );
      });

      it("the recorded live threshold (the value #7985 must restore) equals the capture (review M17)", () => {
        const trig = entry!.triggers.conditions.filter(
          (c) => c.type === "event_unique_user_frequency_count",
        );
        expect(trig).toHaveLength(1);
        // Narrow through the guard, asserted: the frozen rules' threshold trigger
        // carries {value, interval}; anything else must red rather than destructure
        // two `undefined`s into a passing comparison.
        // Throw-only here: it narrows for TypeScript AND carries the label. The tag
        // site above keeps an up-front `.every()` expect as well, because there the
        // assertion is over the WHOLE filtered set before any mapping — a different
        // property from "this one element has the right shape".
        if (!isFrequency(trig[0].comparison)) throw new Error(`${label}: threshold comparison is not {value, interval}`);
        const { value, interval } = trig[0].comparison;
        const recorded = body.match(
          /^#?\s*#\s*Live trigger: event_unique_user_frequency_count \{value = (\d+), interval = "([^"]+)"\}/m,
        );
        expect(recorded, `${label}: no '# Live trigger:' comment`).not.toBeNull();
        expect(Number(recorded![1])).toBe(value);
        expect(recorded![2]).toBe(interval);
      });

      it("is frozen: legacy trigger by type, ignore_changes = all, and the INERT warning", () => {
        expect(body).toMatch(
          /^\s*legacy_trigger_conditions\s*=\s*\["event_unique_user_frequency_count"\]/m,
        );
        expect(body).toMatch(/^\s*trigger_conditions\s*=\s*\[\]/m);
        expect(body).toMatch(/lifecycle\s*\{\s*ignore_changes\s*=\s*all\s*\}/);
        expect(scopeResourceWithComment(label)).toMatch(
          /^#\s*EDITS TO THIS BLOCK ARE INERT until #7985 \(ignore_changes = all\)/m,
        );
      });
    });
  }
});
