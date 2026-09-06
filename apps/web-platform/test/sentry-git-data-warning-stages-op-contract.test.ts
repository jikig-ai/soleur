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
// NOT COVERED: population growth. WARNING_STAGES is a literal, so adding a THIRD warning stage to
// the emitter without routing it would not fail here — the new stage is simply unknown to this
// file. That is the same limitation the fatal sibling has, and closing it means deriving the set
// from the emitter, which is the general extraction engine this suite is explicitly not allowed
// to become (it would scope-creep the pre-existing nine-fatal-stage reconciliation). The
// mitigation is procedural and lives in cloud-init-git-data.yml's own comment: git-data-emit's
// stage vocabulary is a closed set that two files must agree on, and adding to it means adding
// here too.
//
// The closed set of git-data stages that emit at level WARNING.
const WARNING_STAGES = [
  "betterstack_ingest",
  "gitdata_nftables_metadata_warn",
] as const;

// The fatal-side name for the same runcmd item. STAGE is whatever was last assigned when the
// top-armed trap fires, so a death anywhere in that item reports THIS value, not the _warn one.
const NFT_FATAL_STAGE = "gitdata_nftables_metadata";

function scopeResource(src: string, name: string): string {
  const marker = `resource "sentry_issue_alert" "${name}"`;
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

  it("every warning stage is routed by the low-severity rule", () => {
    const scoped = scopeResource(tf, "git_data_boot_warning");
    for (const stage of WARNING_STAGES) {
      expect(scoped, `warning stage ${stage} is not routed`).toContain(stage);
    }
    expect(scoped).toMatch(/match\s*=\s*"IS_IN"/);
    expect(scoped).toMatch(/key\s*=\s*"stage"/);
  });

  it("the warning rule fires per occurrence and does NOT page", () => {
    const scoped = scopeResource(tf, "git_data_boot_warning");
    // event_frequency > 0, NOT first_seen_event: soleur-boot-emit sends one shared message for
    // every stage, so all boot events land in ONE perpetually-active issue group. first_seen
    // would fire once ever and then go inert for exactly the repeat failures worth seeing.
    expect(scoped).toContain("event_frequency");
    expect(scoped).not.toContain("first_seen_event");
    expect(scoped).toMatch(/comparison_type\s*=\s*"count"/);
    expect(scoped).toMatch(/value\s*=\s*0/);
    // NoOne is what makes this non-paging. ActiveMembers here would page the solo founder for a
    // host that booted fine — the severity split is the whole point of a second rule.
    expect(scoped).toContain("NoOne");
    expect(scoped).not.toContain("ActiveMembers");
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
    expect(tf).toContain('resource "sentry_issue_alert" "git_data_boot_warning"');
    expect(tf).toContain('resource "sentry_issue_alert" "git_data_boot_fatal"');
    expect(tf).toContain('name         = "git-data-boot-warning"');
    expect(tf).toContain('name         = "git-data-boot-fatal"');
  });
});
