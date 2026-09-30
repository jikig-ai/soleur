import { readFileSync, readdirSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { describe, it, expect } from "vitest";

// Cross-artifact contract for the #9176 inngest provision-failure page, mirroring the sibling
// `sentry-*-alert-op-contract.test.ts` convention.
//
// `inngest_provision_failure` pages on `stage in <warning stages>` AND `detail nc
// why=inngest_pull_fatal`. The stages are emitted by the dedicated inngest host's
// soleur-inngest-provision script (cloud-init-inngest.yml): the on_exit trap emits
// provision_attempt_failed with `why=<last_stage>` for every non-zero exit once the trap is armed,
// and a degraded bootstrap emits bootstrap_done_degraded. A rename on either side — the emitter's
// stage literal or `detail` format, or the rule's filter value — would dark the page while the
// emitter's own suite (which reads the emitted line, not the rule) stays green. This binds the two
// sides, and pins what must be ABSENT as well as present: one extra AND-ed condition, a second
// action filter, a disabled rule or a dropped action each silence or widen the page. Whole-line
// comments are stripped, so a literal in a comment cannot satisfy an anchor that pins code.

const here = dirname(fileURLToPath(import.meta.url));
const stripComments = (text: string): string =>
  text
    .split("\n")
    .filter((l) => !/^\s*#/.test(l))
    .join("\n");
const read = (rel: string): string => stripComments(readFileSync(join(here, rel), "utf8"));

const INFRA = join(here, "../infra");
const SENTRY_DIR = join(INFRA, "sentry");
const tf = read("../infra/sentry/issue-alerts.tf");
const inngestInit = read("../infra/cloud-init-inngest.yml");
// Every .tf in the Sentry root, for the frequency-uniqueness row (Sentry dedups on action shape +
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

describe("inngest_provision_failure alert ↔ soleur-inngest-provision emitter contract (#9176)", () => {
  const block = tfBlockFor("inngest_provision_failure");
  const provision = provisionBlock();
  const rows = taggedEvents(block);
  const ref = reference["inngest-provision-failure"];

  it("T1: declares exactly one enabled resource and exactly one provision script", () => {
    expect(count(tf, 'resource "sentry_alert" "inngest_provision_failure"')).toBe(1);
    expect(block).toMatch(/^\s*name\s*=\s*"inngest-provision-failure"\s*$/m);
    expect(block).toMatch(/^\s*enabled\s*=\s*true\s*$/m);
    expect(block).toMatch(
      /^\s*monitor_ids\s*=\s*\[data\.sentry_project_issue_stream_monitor\.web_platform\.id\]\s*$/m,
    );
    expect(count(inngestInit, PROVISION_PATH)).toBe(1);
    expect(provision).toContain("on_exit() {");
  });

  it("T2: exactly one action filter, and it ANDs its conditions (under `any` the nc row alone matches every boot stage)", () => {
    expect(block.match(/^\s*logic_type\s*=/gm) ?? []).toHaveLength(1);
    expect(block).toMatch(/^\s*logic_type\s*=\s*"all"\s*$/m);
    expect(rows).toHaveLength(2);
    expect(block.match(/\{\s*email\s*=\s*\{/g) ?? []).toHaveLength(1);
    expect(block).toMatch(
      /email\s*=\s*\{\s*target_type\s*=\s*"issue_owners",\s*fallthrough_type\s*=\s*"ActiveMembers"\s*\}/,
    );
  });

  it("T3: every provision-block emit is attributable, and the stage set equals its literal warning stages", () => {
    const calls = provision.split("\n").filter((l) => l.includes("soleur-boot-emit"));
    const unattributable = calls.filter((l) => !WELL_FORMED_EMIT.test(l));
    expect(unattributable).toEqual([]);
    const emitted = new Set(
      calls
        .map((l) => l.match(WELL_FORMED_EMIT))
        .filter((m): m is RegExpMatchArray => m !== null && m[2] === "warning")
        .map((m) => m[1]),
    );
    expect(emitted.size).toBeGreaterThan(0);
    expect(emitted.has("provision_attempt_failed")).toBe(true);

    const stage = rows.filter((r) => r.key === "stage");
    expect(stage).toHaveLength(1);
    expect(stage[0].match).toBe("in");
    expect(stage[0].value.split(",").sort()).toEqual([...emitted].sort());
  });

  it("T4: pull misses are excluded by detail not-contains why=inngest_pull_fatal", () => {
    expect(rows.filter((r) => r.key === "detail")).toEqual([
      { key: "detail", match: "nc", value: "why=inngest_pull_fatal" },
    ]);
  });

  it("T4b: the committed reference (held equal to the plan by the apply gate) is exactly this rule", () => {
    expect(ref).toEqual({
      actionFilters: [
        {
          actions: [
            { fallthroughType: "ActiveMembers", targetIdentifier: null, targetType: "issue_owners", type: "email" },
          ],
          conditions: [
            { comparison: { key: "detail", match: "nc", value: "why=inngest_pull_fatal" }, type: "tagged_event" },
            {
              comparison: { key: "stage", match: "in", value: "bootstrap_done_degraded,provision_attempt_failed" },
              type: "tagged_event",
            },
          ],
          logicType: "all",
        },
      ],
      detectorIds: ["1213799"],
      enabled: true,
      frequency: 120,
      name: "inngest-provision-failure",
      triggerConditions: [{ comparison: { interval: "1h", value: 0 }, type: "event_frequency_count" }],
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

  it("T7: pages on the first event, at a frequency no other rule in the root uses", () => {
    expect(block).toMatch(/event_frequency_count\s*=\s*\{\s*interval\s*=\s*"1h",\s*value\s*=\s*0\s*\}/);
    expect(block).toMatch(/^\s*frequency_minutes\s*=\s*120\b/m);
    expect(sentryRoot.match(/^\s*frequency_minutes\s*=\s*120\b/gm) ?? []).toHaveLength(1);
  });

  it("T8: no other infra file names a paged stage (so no host_name filter is needed)", () => {
    const stage = rows.find((r) => r.key === "stage");
    expect(stage).toBeDefined();
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
      for (const s of stage!.value.split(",")) if (text.includes(s)) offenders.push(`${f}: ${s}`);
    }
    expect(offenders).toEqual([]);
  });
});
