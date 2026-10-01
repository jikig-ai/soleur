import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { describe, it, expect } from "vitest";

// Cross-artifact contract for the GHCR bridge-egress deny alert (#9275, ADR-096 5.3b-iii),
// mirroring the sibling `sentry-image-verify-alert-op-contract.test.ts` convention.
//
// cron-egress-resolve.sh probes ghcr.io / docker.pkg.github.com from INSIDE the app container
// every ~5 minutes and emits two error events, `op=ghcr_deny_lost` (a bridge container reached
// a Packages frontend) and `op=ghcr_deny_probe_blind` (the probe could not decide for ~1 hour).
// They are routed by the EXISTING `sentry_alert.egress_blocked` rule (`cron-egress-blocked`) by
// widening its `op in "..."` filter; no new rule (the two-PR rule for new monitors forbids routing
// one in the same PR, and a detector no rule routes emails nobody: ADR-031). Renaming an op on
// either side, or dropping one from the filter, would dark the page, and the host-script tests read
// the emitted event, not the rule, so neither change would red them. This binds the two sides,
// and binds the static-message and runbook-decode literals that make the page actionable.
// The filter-side assertions are scoped to THIS resource block, so a token in a comment or a sibling
// rule cannot mask its removal from the rule. The committed `alert-reference.json` entry for the rule
// is read too and must carry the same op list: `sentry-alert-reference-gate.sh` (plan_pr) requires the
// committed reference to equal the plan projection, so a widened `.tf` filter with a stale reference
// reds the PR job and a vitest-only run would not have said so (mirrors
// `sentry-git-data-pin-fault-alert-op-contract.test.ts`).

const here = dirname(fileURLToPath(import.meta.url));
const repoRoot = join(here, "../../..");
// Whole-line `#` comments are stripped from the code artifacts, so a comment naming a literal
// cannot satisfy an anchor that exists to pin the CODE (cq-assert-anchor-not-bare-token).
const stripComments = (text: string): string =>
  text
    .split("\n")
    .filter((l) => !/^\s*#/.test(l))
    .join("\n");
const read = (rel: string): string => readFileSync(join(repoRoot, rel), "utf8");

const tf = stripComments(read("apps/web-platform/infra/sentry/issue-alerts.tf"));
const resolver = stripComments(read("apps/web-platform/infra/cron-egress-resolve.sh"));
const postApply = stripComments(read("apps/web-platform/infra/cron-egress-postapply-assert.sh"));
const generator = stripComments(read("apps/web-platform/infra/scripts/gen-github-egress-cidr.sh"));
// The runbook is markdown: its `#` lines are headings, so it is NOT comment-stripped.
const runbook = read("knowledge-base/engineering/operations/runbooks/cron-egress-blocked.md");
// The committed projection of every sentry_alert (JSON has no comments to strip).
const reference = JSON.parse(read("apps/web-platform/infra/sentry/alert-reference.json")) as Record<
  string,
  {
    enabled: boolean;
    frequency: number;
    actionFilters: Array<{
      logicType: string;
      conditions: Array<{ type: string; comparison: { key: string; match: string; value: string } }>;
    }>;
  }
>;

const GHCR_OPS = ["ghcr_deny_lost", "ghcr_deny_probe_blind"] as const;
const ROUTED_OPS = ["egress_blocked", ...GHCR_OPS] as const;
const ASSERT_NAMES = [
  "ghcr-carve-header-absent",
  "ghcr-carve-live-set",
  "ghcr-frontend-reachable",
] as const;
const GENERATOR_DIE = "ghcr-carve-would-cut-github";
// The generator also dies when zero effective Packages holes remain (the refresh freezes and the
// stale carved file keeps serving); the runbook decodes it in a table row.
const GENERATOR_NO_HOLES_DIE = "ghcr-carve-no-effective-holes";
const RUNBOOK_ANCHOR = "ghcr-carve-9275";

function tfBlockFor(resourceName: string): string {
  const decl = `resource "sentry_alert" "${resourceName}"`;
  const start = tf.indexOf(decl);
  if (start === -1) return "";
  const next = tf.indexOf("\nresource ", start + decl.length);
  return tf.slice(start, next === -1 ? undefined : next);
}

// The reference entry's op list for the rule: the comma-separated value of its `op` tagged_event.
// Reads the condition list itself, so a dropped or duplicated op condition is an error, not a pass.
function referenceOpFilter(): string[] {
  const entry = reference["cron-egress-blocked"];
  if (!entry) throw new Error("fixture: cron-egress-blocked missing from alert-reference.json");
  expect(entry.actionFilters).toHaveLength(1);
  const ops = entry.actionFilters[0].conditions.filter((c) => c.comparison.key === "op");
  if (ops.length !== 1) throw new Error(`fixture: expected exactly one op condition, read ${ops.length}`);
  expect(ops[0].type).toBe("tagged_event");
  expect(ops[0].comparison.match).toBe("in");
  return ops[0].comparison.value.split(",");
}

// The rule's op filter: the comma-separated value of the `op` tagged_event, inside THIS resource.
function ruleOpFilter(block: string): string[] | null {
  const m = block.match(/key\s*=\s*"op",\s*match\s*=\s*"in",\s*value\s*=\s*"([^"]*)"/);
  return m ? m[1].split(",") : null;
}

// Every `sentry_event <msg> <op> <extra>` call in the resolver. The arguments span lines joined
// by a backslash-newline; the message and op are double-quoted literals, extra is the rest.
function resolverEvents(): { message: string; op: string }[] {
  const out: { message: string; op: string }[] = [];
  const re = /sentry_event(?:\s|\\)+"((?:[^"\\]|\\.)*)"(?:\s|\\)+"([A-Za-z0-9_]+)"/g;
  let m: RegExpExecArray | null;
  while ((m = re.exec(resolver)) !== null) out.push({ message: m[1], op: m[2] });
  return out;
}

// GitHub heading slug: lowercase, drop everything but word chars, spaces and hyphens, spaces to hyphens.
const slug = (h: string): string =>
  h
    .toLowerCase()
    .replace(/[^\w\s-]/g, "")
    .trim()
    .replace(/\s+/g, "-");

describe("cron-egress-blocked alert op filter <-> cron-egress-resolve.sh GHCR probe events (#9275)", () => {
  const block = tfBlockFor("egress_blocked");
  const filter = ruleOpFilter(block);
  const events = resolverEvents();
  const emittedOps = new Set(events.map((e) => e.op));

  it("declares the rule, the resolver emitter and a non-vacuous event extraction", () => {
    expect(block).toContain('resource "sentry_alert" "egress_blocked"');
    expect(block).toMatch(/^\s*name\s*=\s*"cron-egress-blocked"/m);
    expect(resolver).toContain("sentry_event() {");
    // Instrument floor: the existing emitters (resolve_host_failed, enforcement_missing,
    // egress_blocked) alone make three calls; an extractor that finds fewer is broken.
    expect(events.length).toBeGreaterThanOrEqual(3);
    expect(emittedOps.has("egress_blocked")).toBe(true);
  });

  it("the rule is scoped to the firewall feature and keeps the live frequency", () => {
    expect(block).toContain('logic_type = "all"');
    expect(block).toMatch(/key\s*=\s*"feature",\s*match\s*=\s*"eq",\s*value\s*=\s*"cron-egress-firewall"/);
    expect(block).toMatch(/^\s*frequency_minutes\s*=\s*30\b/m);
  });

  it("the op filter is exactly the routed set (egress_blocked + the two GHCR ops)", () => {
    expect(filter).not.toBeNull();
    expect([...filter!].sort()).toEqual([...ROUTED_OPS].sort());
    // Deliberately NOT routed: a different failure (the enforcement self-heal) tracked by #9392;
    // widening an alert filter for an unexamined recurring event is a separate decision.
    expect(filter).not.toContain("enforcement_missing");
  });

  it("the committed alert-reference.json entry carries exactly the .tf op filter, in the same order", () => {
    // The reference is the projection of the plan (value strings are not re-sorted), so the lists
    // must be equal as written, not merely as sets.
    expect(referenceOpFilter()).toEqual(filter);
    // The rest of the entry is held by sentry-alert-reference-gate.sh in CI (plan_pr); the
    // feature condition, frequency and enabled flag are pinned here so a vitest-only run cannot
    // pass a stale reference.
    const entry = reference["cron-egress-blocked"];
    const feature = entry.actionFilters[0].conditions.filter((c) => c.comparison.key === "feature");
    expect(feature.map((c) => [c.comparison.match, c.comparison.value])).toEqual([["eq", "cron-egress-firewall"]]);
    expect(entry.enabled).toBe(true);
    expect(entry.frequency).toBe(30);
    expect(entry.actionFilters[0].logicType).toBe("all");
  });

  it("each GHCR op literal is emitted by the resolver AND is a filter value", () => {
    for (const op of GHCR_OPS) {
      expect(emittedOps.has(op), `resolver must emit op ${op} via sentry_event`).toBe(true);
      expect(filter, `rule filter must route op ${op}`).toContain(op);
    }
  });

  it("any ghcr_deny_* op the resolver emits is routed (a new op cannot ship dark)", () => {
    const ghcrEmitted = [...emittedOps].filter((o) => o.startsWith("ghcr_deny_"));
    expect(ghcrEmitted.length).toBeGreaterThanOrEqual(GHCR_OPS.length);
    for (const op of ghcrEmitted) expect(filter, `unrouted op ${op}`).toContain(op);
  });

  it("every filter value is an op the resolver emits (no dead filter entries)", () => {
    for (const op of filter ?? []) expect(emittedOps.has(op), `filter value ${op} is not emitted`).toBe(true);
  });

  it("the GHCR op messages are static: no interpolation, no IP, distinct per op", () => {
    const msgs = new Map<string, string[]>();
    for (const op of GHCR_OPS) msgs.set(op, events.filter((e) => e.op === op).map((e) => e.message));
    for (const op of GHCR_OPS) {
      const list = msgs.get(op)!;
      expect(list.length, `no sentry_event call found for ${op}`).toBeGreaterThanOrEqual(1);
      for (const m of list) {
        expect(m.length, `${op} message is empty`).toBeGreaterThan(0);
        // A `$` or backtick interpolates a name/IP/count and would open a new Sentry issue per value.
        expect(m, `${op} message interpolates (\$ or backtick)`).not.toMatch(/[$`]/);
        expect(m, `${op} message embeds an IPv4`).not.toMatch(/\b\d{1,3}(?:\.\d{1,3}){3}\b/);
      }
    }
    // Two ops, two issue groups: the first-seen trigger of each must fire independently.
    const lost = new Set(msgs.get("ghcr_deny_lost"));
    const blind = new Set(msgs.get("ghcr_deny_probe_blind"));
    for (const m of lost) expect(blind.has(m), "lost and blind messages must differ").toBe(false);
  });

  it("the loss event carries the runbook anchor in its remediation text", () => {
    expect(resolver).toContain(`cron-egress-blocked.md#${RUNBOOK_ANCHOR}`);
  });
});

describe("GHCR carve sentinel / die literals <-> the runbook decode rows (#9275)", () => {
  it("the post-apply assertion emits each ASSERT-FAILED name", () => {
    for (const name of ASSERT_NAMES) {
      expect(postApply, `ASSERT-FAILED: ${name} missing from the post-apply assertion`).toMatch(
        new RegExp(`echo "?'?ASSERT-FAILED: ${name}\\b`),
      );
    }
  });

  it("the generator refuses to write with the distinct die literals", () => {
    expect(generator).toMatch(new RegExp(`(?:die|echo|printf|fail).*${GENERATOR_DIE}`));
    expect(generator).toMatch(new RegExp(`(?:die|echo|printf|fail).*${GENERATOR_NO_HOLES_DIE}`));
  });

  it("the runbook has the GHCR carve section anchor", () => {
    const headings = runbook
      .split("\n")
      .filter((l) => /^#{1,6}\s+/.test(l))
      .map((l) => slug(l.replace(/^#{1,6}\s+/, "")));
    const explicit = new RegExp(`(?:id|name)="${RUNBOOK_ANCHOR}"`).test(runbook);
    expect(headings.includes(RUNBOOK_ANCHOR) || explicit, `no heading slugging to ${RUNBOOK_ANCHOR}`).toBe(true);
  });

  it("the runbook decodes every sentinel, die literal and op in a table row", () => {
    const rows = runbook.split("\n").filter((l) => /^\s*\|/.test(l));
    expect(rows.length).toBeGreaterThan(5); // instrument floor: the decode tables exist at all
    // `ghcr-frontend-inconclusive` is the apply-time probe's loud WARNING (not an ASSERT-FAILED).
    const literals = [...ASSERT_NAMES, "ghcr-frontend-inconclusive", GENERATOR_DIE, GENERATOR_NO_HOLES_DIE, ...GHCR_OPS];
    for (const lit of literals) {
      expect(
        rows.some((r) => r.includes(lit)),
        `runbook has no decode table row naming ${lit}`,
      ).toBe(true);
    }
  });
});
