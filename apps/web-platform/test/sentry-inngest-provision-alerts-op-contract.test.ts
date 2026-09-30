import { readFileSync, readdirSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { describe, it, expect } from "vitest";

// Cross-artifact contract for the two inngest provision pages, mirroring the sibling
// `sentry-*-alert-op-contract.test.ts` convention.
//
// The dedicated inngest host's soleur-inngest-provision script (cloud-init-inngest.yml) emits two
// warning stages: the on_exit trap emits provision_attempt_failed with `why=<last_stage>` for every
// non-zero exit once the trap is armed (repeating while the unit retries), and a degraded bootstrap
// emits bootstrap_done_degraded once per boot. They page through two rules because Sentry throttles
// per rule per issue group and both stages land in one group: under one shared throttle (#9176) a
// failure page swallowed the once-only degraded page that followed it (#9299).
//
// - `inngest_provision_failure` pages on `stage eq provision_attempt_failed` AND
//   `detail nc why=inngest_pull_fatal`.
// - `inngest_provision_degraded` pages on `stage eq bootstrap_done_degraded` alone.
//
// A rename on either side — the emitter's stage literal or `detail` format, or a rule's filter
// value — would dark a page while the emitter's own suite (which reads the emitted line, not the
// rule) stays green. This binds the two sides, requires the two rules to partition the emitted
// warning stages, and pins what must be ABSENT as well as present: one extra AND-ed condition, a
// second action filter, a disabled rule, a dropped action or a create-time `environment` each
// silence or widen a page. Whole-line comments (`#` and `//`) are stripped, so a literal in a
// comment cannot satisfy an anchor that pins code.

const here = dirname(fileURLToPath(import.meta.url));
const stripComments = (text: string): string =>
  text
    .split("\n")
    .filter((l) => !/^\s*(#|\/\/)/.test(l))
    .join("\n");
const read = (rel: string): string => stripComments(readFileSync(join(here, rel), "utf8"));

const INFRA = join(here, "../infra");
const SENTRY_DIR = join(INFRA, "sentry");
const tf = read("../infra/sentry/issue-alerts.tf");
const inngestInit = read("../infra/cloud-init-inngest.yml");
// Every .tf in the Sentry root, for the frequency-uniqueness rows (Sentry dedups on action shape +
// filter match + frequency, so two rules at one frequency can collapse at POST time).
const sentryRoot = readdirSync(SENTRY_DIR)
  .filter((f) => f.endsWith(".tf"))
  .map((f) => read(`../infra/sentry/${f}`))
  .join("\n");
const reference = JSON.parse(readFileSync(join(SENTRY_DIR, "alert-reference.json"), "utf8"));

function tfBlockFor(resourceName: string): string {
  const decl = `resource "sentry_alert" "${resourceName}"`;
  const start = tf.indexOf(decl);
  if (start === -1) return "";
  const next = tf.indexOf("\nresource ", start + decl.length);
  return tf.slice(start, next === -1 ? undefined : next);
}

const PROVISION_PATH = "path: /usr/local/bin/soleur-inngest-provision\n";
// The soleur-inngest-provision write_files entry, up to the next write_files entry.
function provisionBlock(): string {
  const start = inngestInit.indexOf(PROVISION_PATH);
  if (start === -1) return "";
  const next = inngestInit.indexOf("\n  - path:", start);
  return inngestInit.slice(start, next === -1 ? undefined : next);
}

const count = (hay: string, needle: string): number => hay.split(needle).length - 1;

// Every `tagged_event = { … }` row in the block, parsed field-order-insensitively.
function taggedEvents(block: string): Array<Record<string, string>> {
  return [...block.matchAll(/tagged_event\s*=\s*\{([^}]*)\}/g)].map((m) =>
    Object.fromEntries([...m[1].matchAll(/(\w+)\s*=\s*"([^"]*)"/g)].map((f) => [f[1], f[2]])),
  );
}

// A soleur-boot-emit call whose stage and level are both bare literals, on one line. Anything else
// (a quoted/variable stage or level, a line continuation, a wrapper) cannot be attributed by this
// guard and is therefore a failure, not a silent miss. The stage charset mirrors the emitter's own
// STAGE filter (`tr -cd 'A-Za-z0-9_-'`).
const WELL_FORMED_EMIT = /(?:^|[\s;&|(])soleur-boot-emit ([A-Za-z0-9_-]+) (info|warning|fatal)(?:\s|$)/;

const MONITOR_BINDING = /^\s*monitor_ids\s*=\s*\[data\.sentry_project_issue_stream_monitor\.web_platform\.id\]\s*$/m;
const EMAIL_ACTION =
  /email\s*=\s*\{\s*target_type\s*=\s*"issue_owners",\s*fallthrough_type\s*=\s*"ActiveMembers"\s*\}/;
const FIRST_EVENT_TRIGGER = /event_frequency_count\s*=\s*\{\s*interval\s*=\s*"1h",\s*value\s*=\s*0\s*\}/;
// An `environment` set in the block binds the rule at CREATE time, before `ignore_changes` applies,
// and the reference projection omits the field, so no other gate sees it.
const ENVIRONMENT_LINE = /^\s*environment\s*=/m;
const EMAIL_REF_ACTION = {
  fallthroughType: "ActiveMembers",
  targetIdentifier: null,
  targetType: "issue_owners",
  type: "email",
};
const FIRST_EVENT_REF_TRIGGER = [{ comparison: { interval: "1h", value: 0 }, type: "event_frequency_count" }];

describe("inngest provision alerts ↔ soleur-inngest-provision emitter contract (#9176, #9299)", () => {
  const block = tfBlockFor("inngest_provision_failure");
  const degraded = tfBlockFor("inngest_provision_degraded");
  const provision = provisionBlock();
  const rows = taggedEvents(block);
  const degradedRows = taggedEvents(degraded);
  const ref = reference["inngest-provision-failure"];
  const degradedRef = reference["inngest-provision-degraded"];

  it("T1: declares exactly one enabled failure resource and exactly one provision script", () => {
    expect(count(tf, 'resource "sentry_alert" "inngest_provision_failure"')).toBe(1);
    expect(block).toMatch(/^\s*name\s*=\s*"inngest-provision-failure"\s*$/m);
    expect(block).toMatch(/^\s*enabled\s*=\s*true\s*$/m);
    expect(block).toMatch(MONITOR_BINDING);
    expect(block).not.toMatch(ENVIRONMENT_LINE);
    expect(count(inngestInit, PROVISION_PATH)).toBe(1);
    expect(provision).toContain("on_exit() {");
  });

  it("T1b: declares exactly one enabled degraded resource, with no create-time environment", () => {
    expect(count(tf, 'resource "sentry_alert" "inngest_provision_degraded"')).toBe(1);
    expect(degraded).toMatch(/^\s*name\s*=\s*"inngest-provision-degraded"\s*$/m);
    expect(degraded).toMatch(/^\s*enabled\s*=\s*true\s*$/m);
    expect(degraded).toMatch(MONITOR_BINDING);
    expect(degraded).not.toMatch(ENVIRONMENT_LINE);
  });

  it("T2: failure rule has exactly one action filter, and it ANDs its conditions (under `any` the nc row alone matches every boot stage)", () => {
    expect(block.match(/^\s*logic_type\s*=/gm) ?? []).toHaveLength(1);
    expect(block).toMatch(/^\s*logic_type\s*=\s*"all"\s*$/m);
    expect(rows).toHaveLength(2);
    expect(block.match(/\{\s*email\s*=\s*\{/g) ?? []).toHaveLength(1);
    expect(block).toMatch(EMAIL_ACTION);
  });

  it("T2b: degraded rule has exactly one action filter with exactly one condition row", () => {
    expect(degraded.match(/^\s*logic_type\s*=/gm) ?? []).toHaveLength(1);
    expect(degraded).toMatch(/^\s*logic_type\s*=\s*"all"\s*$/m);
    expect(degradedRows).toHaveLength(1);
    expect(degraded.match(/\{\s*email\s*=\s*\{/g) ?? []).toHaveLength(1);
    expect(degraded).toMatch(EMAIL_ACTION);
  });

  it("T3: every provision-block emit is attributable, and the two rules partition its literal warning stages", () => {
    const calls = provision.split("\n").filter((l) => l.includes("soleur-boot-emit"));
    const unattributable = calls.filter((l) => !WELL_FORMED_EMIT.test(l));
    expect(unattributable).toEqual([]);
    const emitted = new Set(
      calls
        .map((l) => l.match(WELL_FORMED_EMIT))
        .filter((m): m is RegExpMatchArray => m !== null && m[2] === "warning")
        .map((m) => m[1]),
    );

    const failureStage = rows.filter((r) => r.key === "stage");
    const degradedStage = degradedRows.filter((r) => r.key === "stage");
    expect(failureStage).toEqual([{ key: "stage", match: "eq", value: "provision_attempt_failed" }]);
    expect(degradedStage).toEqual([{ key: "stage", match: "eq", value: "bootstrap_done_degraded" }]);
    // One equality: the emitted set is non-empty, every emitted warning stage is paged, and the two
    // rules are disjoint (a shared stage would appear twice on the left).
    expect([failureStage[0].value, degradedStage[0].value].sort()).toEqual([...emitted].sort());
  });

  it("T4: pull misses are excluded by detail not-contains why=inngest_pull_fatal", () => {
    expect(rows.filter((r) => r.key === "detail")).toEqual([
      { key: "detail", match: "nc", value: "why=inngest_pull_fatal" },
    ]);
  });

  it("T4b: the committed failure reference (held equal to the plan by the apply gate) is exactly this rule", () => {
    expect(ref).toEqual({
      actionFilters: [
        {
          actions: [EMAIL_REF_ACTION],
          conditions: [
            { comparison: { key: "detail", match: "nc", value: "why=inngest_pull_fatal" }, type: "tagged_event" },
            { comparison: { key: "stage", match: "eq", value: "provision_attempt_failed" }, type: "tagged_event" },
          ],
          logicType: "all",
        },
      ],
      detectorIds: ["1213799"],
      enabled: true,
      frequency: 120,
      name: "inngest-provision-failure",
      triggerConditions: FIRST_EVENT_REF_TRIGGER,
      triggerLogicType: "single",
    });
  });

  it("T4c: the committed degraded reference is exactly this rule", () => {
    expect(degradedRef).toEqual({
      actionFilters: [
        {
          actions: [EMAIL_REF_ACTION],
          conditions: [
            { comparison: { key: "stage", match: "eq", value: "bootstrap_done_degraded" }, type: "tagged_event" },
          ],
          logicType: "all",
        },
      ],
      detectorIds: ["1213799"],
      enabled: true,
      frequency: 33,
      name: "inngest-provision-degraded",
      triggerConditions: FIRST_EVENT_REF_TRIGGER,
      triggerLogicType: "single",
    });
  });

  it("T5: on_exit runs the why=<stage> emit, through a DETAIL charset that keeps = and _", () => {
    const start = provision.indexOf("on_exit() {");
    const body = provision.slice(start, provision.indexOf("\n      }\n", start));
    expect(body).toMatch(
      /^\s+soleur-boot-emit provision_attempt_failed warning "rc=\$rc\.attempt=\$attempt\.why=\$last_stage\.iid=\$IID"$/m,
    );
    expect(provision).toMatch(/^\s+soleur-boot-emit bootstrap_done_degraded warning "why=\$_degraded\./m);
    expect(inngestInit).toMatch(/^\s+DETAIL=\$\(printf '%s' "\$3" \| LC_ALL=C tr -cd 'A-Za-z0-9=\.:_-' \|/m);
  });

  it("T6: every attempt the nc row excludes has already emitted the fatal stage the zot rule pages", () => {
    expect(count(provision, "last_stage=inngest_pull_fatal")).toBe(2);
    expect(count(provision, "soleur-boot-emit inngest_pull_fatal fatal")).toBe(2);
  });

  it("T7: failure rule pages on the first event, at a frequency no other rule in the root uses", () => {
    expect(block).toMatch(FIRST_EVENT_TRIGGER);
    expect(block).toMatch(/^\s*frequency_minutes\s*=\s*120\b/m);
    expect(sentryRoot.match(/^\s*frequency_minutes\s*=\s*120\b/gm) ?? []).toHaveLength(1);
  });

  it("T7b: degraded rule pages on the first event, at a frequency no other rule in the root uses", () => {
    expect(degraded).toMatch(FIRST_EVENT_TRIGGER);
    expect(degraded).toMatch(/^\s*frequency_minutes\s*=\s*33\b/m);
    expect(sentryRoot.match(/^\s*frequency_minutes\s*=\s*33\b/gm) ?? []).toHaveLength(1);
  });

  it("T8: no other infra file names a paged stage (so no host_name filter is needed)", () => {
    const stages = [...rows, ...degradedRows].filter((r) => r.key === "stage").map((r) => r.value);
    expect(stages).toHaveLength(2);
    const others = (readdirSync(INFRA, { recursive: true }) as string[]).filter(
      (f) =>
        f !== "cloud-init-inngest.yml" &&
        !f.startsWith("sentry/") &&
        !f.endsWith(".test.sh") &&
        !f.includes("node_modules"),
    );
    expect(others.length).toBeGreaterThan(20);
    const offenders: string[] = [];
    for (const f of others) {
      let text: string;
      try {
        text = readFileSync(join(INFRA, f), "utf8");
      } catch {
        continue; // a directory entry
      }
      for (const s of stages) if (text.includes(s)) offenders.push(`${f}: ${s}`);
    }
    expect(offenders).toEqual([]);
  });
});
