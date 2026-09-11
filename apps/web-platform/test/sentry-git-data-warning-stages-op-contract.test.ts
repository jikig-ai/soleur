import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { describe, it, expect } from "vitest";

// Cross-artifact contract test for git-data's WARNING stage routing (#7772 item C).
//
// THE CLASS THIS CLOSES. git-data-emit's stage vocabulary is a closed set that two independent
// files must agree on: the cloud-init template EMITS a stage string, and issue-alerts.tf ROUTES
// it. A stage that matches no rule is a WRITE-ONLY event — it reaches Sentry, is queryable, and
// notifies nobody. issue-alerts.tf's own comment names that outcome as "the dead host paged
// nobody". Until #7772 BOTH of git-data's warning stages were in exactly that state:
// `betterstack_ingest` (shipped #7460) and, had it shipped unrouted,
// `gitdata_nftables_metadata_warn`.
//
// WHY A SEPARATE SUITE FROM THE FATAL SIBLING. The fatal router pages; this one deliberately does
// not (fallthrough_type "NoOne"). Asserting both severities in one file would make it easy to
// "fix" a failure by moving a stage across the severity boundary, which is the paging-policy
// change ADR-198 says must not be made silently.
//
// Modelled on sentry-web-terminal-boot-fatal-op-contract.test.ts: a literal stage list plus a
// loop, two readFileSync calls, assertions in BOTH directions. Deliberately NOT a general
// extraction engine — that would scope-creep the pre-existing nine-fatal-stage reconciliation,
// which this PR does not touch.

const here = dirname(fileURLToPath(import.meta.url));
const tf = readFileSync(join(here, "../infra/sentry/issue-alerts.tf"), "utf8");
const cloudInit = readFileSync(join(here, "../infra/cloud-init-git-data.yml"), "utf8");

// THE ORDERING ASSERTIONS QUANTIFY OVER CODE, NOT PROSE — and this is not hypothetical
// tidiness. The first version of the nearest-preceding-STAGE check below searched the RAW
// template, and a later comment in that template quoted the emit's own literal
// (`git-data-emit "$${STAGE}_warn" warning`) while explaining why the unit carries no
// SyslogIdentifier. `indexOf` found the PROSE copy first, ~400 lines above the real emit and
// above every STAGE= assignment, and the arm failed with "the _warn emit has no STAGE
// assignment before it" against a template that was entirely correct.
//
// That is `cq-assert-anchor-not-bare-token` one level up: it is not enough for the ANCHOR to
// be a construct rather than a token if the CORPUS still contains commentary quoting that
// construct. Stripping whole-line `#` comments is also the more faithful corpus: ADR-152's
// render-time rationale strip removes exactly these lines, so what remains is what the host
// actually receives. Line structure is preserved (comments become empty lines) so no index
// comparison silently shifts.
const cloudInitCode = cloudInit
  .split("\n")
  .map((l) => (/^\s*#/.test(l) ? "" : l))
  .join("\n");

// MUTATION-PROVEN, with one axis deliberately NOT covered and one that was CLAIMED and was
// not — stated so neither is mistaken for coverage.
//
// THE CLAIM THAT WAS FALSE, kept here rather than quietly corrected: the original header
// said seven mutations across six axes all went RED. The fatal-side paging axis did not.
// `toContain("ActiveMembers")` was satisfied by two comments inside the slice, so flipping
// the fatal router to "NoOne" -- de-paging every dark-host fatal on the host holding every
// user's source -- passed 5/0. Review mutation-proved it; both the anchor and the slice
// boundary are fixed above, and the mutation now reds.
//
// (#7772 review) TWO FURTHER SURVIVORS, both now closed by the nearest-preceding-assignment
// assertion in the first `it`: interposing a second STAGE= between the assignment and the emit
// (Q3), and renaming the emitting assignment to a PREFIX-EXTENDED name (Q4). Both left the
// suite 5/0 while shipping a host whose nftables-arm failure routes nowhere.
//
// The mutations that DO go RED: dropping a stage from the IS_IN set,
// flipping NoOne to ActiveMembers, swapping event_frequency for first_seen_event (scoped to the
// warning resource), re-pointing the fatal-side stage value, renaming the runcmd STAGE
// assignment, dropping the `_warn` suffix from the emit, and renaming the resource itself (which
// hits scopeResource's miss-guard with a named message rather than a slice(-1) silent pass).
//
// POPULATION GROWTH IS NOW COVERED, in both directions (#8043 F11, Guard 2). This header used to
// say it was not: WARNING_STAGES was a literal checked with `toContain`, which proved only
// `WARNING_STAGES ⊆ tf`, so a THIRD warning stage emitted by the template and routed by nothing
// shipped 5/5 green — and that is exactly what happened: `sshd_config_warn` was emitted twice
// by the sshd stage and matched nothing in issue-alerts.tf, so the very row that carried the
// F11 measurement paged nobody. Three set-equality assertions close it: (a) the tf `in` list
// set-equals WARNING_STAGES; (b) the EMITTER's warning-level vocabulary — derived from the
// comment-stripped template, warning-level emits only — set-equals WARNING_STAGES ∪ the named
// fatal-routed exceptions; (c) each named exception really is a `value = "…"` on the fatal
// rule, so the exception literal cannot become a dumping ground for unrouted stages.
//
// The derivation stays inside this file's boundary: it extracts WARNING-level emits only (the
// call shape with a literal `warning` level), never the fatal set, so it is not the general
// extraction engine the nine-fatal-stage reconciliation was kept away from.
//
// The closed set of git-data stages that emit at level WARNING and route to the NON-paging rule.
const WARNING_STAGES = [
  "betterstack_ingest",
  "gitdata_nftables_metadata_warn",
  "sshd_config_warn",
] as const;

// Warning-level emits that ROUTE TO THE FATAL RULE. `gc_timer` is emitted at level warning
// (`git-data-emit "SOLEUR_GIT_DATA_GC timer failed to arm" "$STAGE" warning` under
// STAGE=gc_timer) and the fatal rule filters on `stage` only, never on `level` — so a
// timer-arm failure PAGES today. That is a pre-existing paging-policy fact this suite pins
// rather than changes (ADR-198: a stage must not move across the severity boundary silently);
// whether it SHOULD page is filed as a policy decision, not fixed here. Assertion (c) proves
// every member is actually on the fatal rule.
const WARNING_EMITS_ROUTED_BY_FATAL_RULE = ["gc_timer"] as const;

// The fatal-side name for the same runcmd item. STAGE is whatever was last assigned when the
// top-armed trap fires, so a death anywhere in that item reports THIS value, not the _warn one.
const NFT_FATAL_STAGE = "gitdata_nftables_metadata";

function scopeResource(src: string, name: string): string {
  // BOTH types. This file holds 29 `sentry_alert` rules and 2
  // `sentry_issue_alert` ones. This suite no longer spans the boundary —
  // `git_data_boot_fatal` migrated in #7650 Phase 2 and `git_data_boot_warning`
  // in Phase 3.4 (#7985) — but the helper stays type-agnostic because the two
  // survivors migrate the moment the provider ships upstream 950. Hardcoding either type
  // makes the other throw "resource not found".
  const marker = [
    `resource "sentry_alert" "${name}"`,
    `resource "sentry_issue_alert" "${name}"`,
  ].find((m) => tf.includes(m)) ?? `resource "sentry_alert" "${name}"`;
  const start = src.indexOf(marker);
  // An indexOf miss returns -1, and slice(-1) yields the LAST CHARACTER — every subsequent
  // assertion would then pass or fail for reasons unrelated to the resource. Fail loudly first.
  expect(start, `resource ${name} not found in issue-alerts.tf`).toBeGreaterThan(-1);
  const rest = src.slice(start + 1);
  const next = rest.indexOf("\nresource ");
  if (next === -1) return src.slice(start);
  // STOP AT THE NEIGHBOUR'S COMMENT BLOCK, not at its `resource` keyword. A slice that ends at
  // the keyword swallows the next resource's entire leading rationale, so every toContain/
  // not.toContain in this file would quantify over prose belonging to a DIFFERENT rule. That is
  // not hypothetical: this PR's own warning-rule comment explains why the fatal router pages,
  // and it contains the literal "ActiveMembers" -- see the anchor note on that assertion.
  let end = start + 1 + next;
  const lines = src.slice(start, end).split("\n");
  while (lines.length && /^\s*(#|$)/.test(lines[lines.length - 1])) lines.pop();
  end = start + lines.join("\n").length;
  return src.slice(start, end);
}

describe("git-data warning-stage routing op contract", () => {
  it("the template emits both warning stages at level warning", () => {
    // Anchored on the EMIT CALL SHAPE, not a bare token: both names also appear in prose in this
    // template, and a bare-token grep would stay green after the emit itself was deleted
    // (cq-assert-anchor-not-bare-token).
    // betterstack_ingest is emitted by the mirror inside git-data-emit, as a JSON tag pair on a
    // level:warning body -- NOT via the emitter's positional `<stage> warning` form. Anchor on
    // that construct: the name also appears in prose in this template and in git-data-luks.tf.
    expect(cloudInit).toContain('"level":"warning"');
    expect(cloudInit).toContain('"stage":"betterstack_ingest"');
    const emitAt = cloudInitCode.indexOf('"$${STAGE}_warn" warning');
    expect(emitAt, "the _warn emit is absent from the template").toBeGreaterThan(-1);

    // ...and that the _warn suffix is built from THIS stage. CO-PRESENCE IS NOT LOCALITY, and
    // the previous form here was `toContain(\`STAGE=${NFT_FATAL_STAGE}\`)` — an unanchored
    // substring test over a 1050-line file that already carries ten STAGE= assignments. Two
    // mutations were MEASURED to survive it, both of which ship a host whose failures route
    // nowhere:
    //
    //   Q3  insert `STAGE=some_other_window` BETWEEN the assignment and the emit. STAGE is
    //       whatever was last assigned when the emit runs, so the arm reports
    //       `stage:some_other_window_warn` — matching no IS_IN value in the very rule this
    //       suite exists to pin. Survived: the old assertion only asked whether the string
    //       appeared SOMEWHERE.
    //   Q4  rename the emitting assignment to `STAGE=gitdata_nftables_metadata_v2`. toContain
    //       is a substring test, so every `gitdata_nftables_metadata*` name satisfies it —
    //       while the FATAL router's EQUAL filter stops matching. A dark fatal, green suite.
    //
    // Both close by asserting the pair as ONE construct: find the NEAREST PRECEDING whole-line
    // STAGE assignment and require it to be exactly this stage. That is the same shape the
    // runcmd suite's R3(2) arm uses for its own ordering property ("co-presence is not
    // ordering"), one directory over.
    const assignments = [...cloudInitCode.matchAll(/^\s*STAGE=([A-Za-z0-9_]+)\s*$/gm)];
    expect(assignments.length, "no whole-line STAGE= assignments found").toBeGreaterThan(0);
    const preceding = assignments.filter((m) => m.index! < emitAt);
    expect(preceding.length, "the _warn emit has no STAGE assignment before it").toBeGreaterThan(0);
    const nearest = preceding[preceding.length - 1];
    expect(
      nearest[1],
      `the _warn emit resolves to "${nearest[1]}_warn", not "${NFT_FATAL_STAGE}_warn" — ` +
        "STAGE is whatever was last assigned when the emit runs, so an assignment interposed " +
        "between them re-points the stage and the warning rule stops routing it",
    ).toBe(NFT_FATAL_STAGE);
  });

  it("every warning stage is routed by the low-severity rule — and only those (set equality)", () => {
    const scoped = scopeResource(tf, "git_data_boot_warning");
    // (a) tf ⊇ AND ⊆ WARNING_STAGES. The old `toContain` per stage proved one direction only.
    const inMatch = scoped.match(/key\s*=\s*"stage",\s*match\s*=\s*"in",\s*value\s*=\s*"([^"]+)"/);
    expect(inMatch, "the warning rule has no stage `in` list").not.toBeNull();
    const inList = inMatch![1].split(",").map((x) => x.trim()).sort();
    expect(inList).toEqual([...WARNING_STAGES].sort());
    // `in`, the `sentry_alert` spelling of the old `IS_IN`. Still asserting a SET match
    // rather than `eq`: an `eq` here would route exactly one stage and silently drop the rest.
    expect(scoped).toMatch(/match\s*=\s*"in"/);
    expect(scoped, "a set match, never equality").not.toMatch(/match\s*=\s*"eq"/);
    expect(scoped).toMatch(/key\s*=\s*"stage"/);
  });

  it("the warning rule fires per occurrence and does NOT page", () => {
    const scoped = scopeResource(tf, "git_data_boot_warning");
    // event_frequency > 0, NOT first_seen_event: soleur-boot-emit sends one shared message for
    // every stage, so all boot events land in ONE perpetually-active issue group. first_seen
    // would fire once ever and then go inert for exactly the repeat failures worth seeing.
    // `event_frequency_count` is the `sentry_alert` spelling of the old
    // `event_frequency { comparison_type = "count" }`. The property is unchanged: a COUNT
    // over an interval, so it re-fires per occurrence.
    expect(scoped).toContain("event_frequency_count");
    expect(scoped).not.toContain("first_seen_event");
    expect(scoped).toMatch(/interval\s*=\s*"1h"/);
    expect(scoped).toMatch(/value\s*=\s*0/);
    // NoOne is what makes this non-paging. ActiveMembers here would page the solo founder for a
    // host that booted fine — the severity split is the whole point of a second rule.
    expect(scoped).toContain("NoOne");
    expect(scoped).not.toContain("ActiveMembers");
  });

  it("the EMITTER's warning vocabulary set-equals the routed set plus the named fatal-routed exceptions", () => {
    // (b) Derived from the template, warning-level emits only. Backslash continuations are
    // joined first: one emit's stage+level sit on the continued line. The corpus is the
    // comment-stripped one for the reason the first `it` records — a prose line quotes an emit.
    const joined = cloudInitCode.replace(/\\\n\s*/g, " ");
    const assignments = [...joined.matchAll(/^\s*STAGE=([A-Za-z0-9_]+)\s*$/gm)];
    const nearestStageBefore = (idx: number): string => {
      const preceding = assignments.filter((m) => m.index! < idx);
      expect(preceding.length, "a warning emit has no STAGE= assignment before it").toBeGreaterThan(0);
      return preceding[preceding.length - 1][1];
    };
    const emits = [...joined.matchAll(/git-data-emit\s+"[^"]*"\s+("?[^"\s]+"?)\s+warning\b/g)];
    // FLOOR: with the regex mis-anchored the derived set is empty and the equality below reds
    // anyway, but the floor turns that into a named failure rather than a confusing diff.
    expect(emits.length, "fewer than 3 warning-level emit calls found in the template").toBeGreaterThanOrEqual(3);
    const resolved = new Set<string>();
    for (const m of emits) {
      const tok = m[1].replace(/^"|"$/g, "");
      if (tok === "$STAGE" || tok === "${STAGE}") resolved.add(nearestStageBefore(m.index!));
      else if (tok === "$${STAGE}_warn" || tok === "${STAGE}_warn") resolved.add(`${nearestStageBefore(m.index!)}_warn`);
      else resolved.add(tok); // a bare literal stage string
    }
    // Plus the emitter-internal mirror construct, which emits a warning body as a JSON tag pair
    // rather than through the positional form.
    for (const m of joined.matchAll(/"level":"warning","tags":\{"stage":"([A-Za-z0-9_]+)"/g)) resolved.add(m[1]);
    expect([...resolved].sort()).toEqual(
      [...WARNING_STAGES, ...WARNING_EMITS_ROUTED_BY_FATAL_RULE].sort(),
    );
    // (c) every named exception is REALLY on the fatal rule — the literal cannot absorb an
    // unrouted stage.
    const fatal = scopeResource(tf, "git_data_boot_fatal");
    for (const stage of WARNING_EMITS_ROUTED_BY_FATAL_RULE) {
      expect(fatal, `${stage} is named as fatal-routed but is not on the fatal rule`).toMatch(
        new RegExp(`value\\s*=\\s*"${stage}"`),
      );
    }
  });

  it("the fatal-side nftables stage is routed by the FATAL rule, and the _warn name is not", () => {
    const fatal = scopeResource(tf, "git_data_boot_fatal");
    expect(fatal).toContain(`value = "${NFT_FATAL_STAGE}"`);
    // The severity boundary, asserted in the direction that actually rots: folding the warning
    // name into the fatal router is a paging-policy change that no other assertion here would
    // catch, because the warning rule would still contain it too.
    // ANCHORED ON THE HCL CONSTRUCT, not the bare name. The comment inside this very resource
    // explains why the _warn value is routed elsewhere, so a bare-token assertion fails against
    // correct code -- and would have been "fixed" by deleting the explanation
    // (cq-assert-anchor-not-bare-token). This caught itself on first run.
    expect(fatal).not.toMatch(/value\s*=\s*"gitdata_nftables_metadata_warn"/);
    // ANCHORED ON THE CONSTRUCT. `toContain("ActiveMembers")` was MUTATION-PROVEN to false-pass:
    // flipping this very rule's fallthrough_type to "NoOne" -- silently de-paging every git-data
    // dark-host fatal, the most consequential mutation available in this file -- left the suite
    // 5/0 green, because the bare token also occurs in two comments. One of those comments was
    // added by this PR. The lesson was applied to the not.toMatch on the line above and not to
    // this line; the header's "seven mutations across six axes" claim was false for the axis
    // that matters most. Both halves are now fixed: this anchor, and scopeResource's boundary.
    expect(fatal).toMatch(/fallthrough_type\s*=\s*"ActiveMembers"/);
  });

  it("the two rules are distinct resources with distinct names", () => {
    // A single rule cannot carry both severities; collapsing them is the likeliest future
    // "simplification" and would silently start paging on warnings.
    // BOTH are `sentry_alert` since Phase 3.4 (#7985) migrated the warning rule;
    // the fatal one was adopted by #7650 Phase 2. The type asymmetry this block
    // used to assert is GONE, so asserting it would now be asserting history.
    // What must survive is that they remain TWO DISTINCT resources: collapsing
    // them into one is the likeliest future "simplification" and would start
    // paging on warnings, which is the exact severity split these rules exist for.
    expect(tf).toContain('resource "sentry_alert" "git_data_boot_warning"');
    expect(tf).toContain('resource "sentry_alert" "git_data_boot_fatal"');
    expect(
      tf,
      "the warning rule must not regress onto the deprecated type",
    ).not.toContain('resource "sentry_issue_alert" "git_data_boot_warning"');
    // Whitespace-TOLERANT. `terraform fmt` aligns `=` to the longest attribute
    // name in the block, so the column depends on the block's OTHER attributes:
    // the migrated `sentry_alert` shape carries `frequency_minutes`, which is
    // longer than anything in the old `sentry_issue_alert` block and shifts every
    // `=` right. A hardcoded run of spaces asserts the formatter's arithmetic,
    // not the rule's name.
    expect(tf).toMatch(/^\s*name\s*=\s*"git-data-boot-warning"$/m);
    expect(tf).toMatch(/^\s*name\s*=\s*"git-data-boot-fatal"$/m);
  });
});
