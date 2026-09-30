import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { describe, it, expect } from "vitest";

// Cross-artifact contract for the #9176 inngest provision-failure page, mirroring the sibling
// `sentry-*-alert-op-contract.test.ts` convention.
//
// `inngest_provision_failure` pages on `stage in <warning stages>` AND `detail nc
// why=inngest_pull_fatal`. The stages are emitted by the dedicated inngest host's
// soleur-inngest-provision script (cloud-init-inngest.yml): the on_exit trap emits
// provision_attempt_failed with `why=<last_stage>` for every non-zero exit, and a degraded
// bootstrap emits bootstrap_done_degraded. A rename on either side — the emitter's stage literal
// or `detail` format, or the rule's filter value — would dark the page while the emitter's own
// suite (which reads the emitted line, not the rule) stays green. This binds the two sides. The
// rule-side assertions are scoped to THIS resource block, and whole-line comments are stripped,
// so a literal in a comment or a sibling rule cannot satisfy an anchor that pins code.

const here = dirname(fileURLToPath(import.meta.url));
const stripComments = (text: string): string =>
  text
    .split("\n")
    .filter((l) => !/^\s*#/.test(l))
    .join("\n");
const read = (rel: string): string => stripComments(readFileSync(join(here, rel), "utf8"));

const tf = read("../infra/sentry/issue-alerts.tf");
const inngestInit = read("../infra/cloud-init-inngest.yml");
const webInit = read("../infra/cloud-init.yml");
// Every .tf in the Sentry root, for the frequency-uniqueness row (Sentry dedups on action shape +
// filter match + frequency, so two rules at one frequency can collapse at POST time).
const sentryRoot = ["issue-alerts.tf", "cron-monitor-alerts.tf", "cron-monitors.tf", "uptime-monitors.tf", "main.tf"]
  .map((f) => read(`../infra/sentry/${f}`))
  .join("\n");

function tfBlockFor(resourceName: string): string {
  const decl = `resource "sentry_alert" "${resourceName}"`;
  const start = tf.indexOf(decl);
  if (start === -1) return "";
  const next = tf.indexOf("\nresource ", start + decl.length);
  return tf.slice(start, next === -1 ? undefined : next);
}

// The soleur-inngest-provision write_files entry, up to the next write_files entry.
function provisionBlock(): string {
  const start = inngestInit.indexOf("path: /usr/local/bin/soleur-inngest-provision\n");
  if (start === -1) return "";
  const next = inngestInit.indexOf("\n  - path:", start);
  return inngestInit.slice(start, next === -1 ? undefined : next);
}

const count = (hay: string, needle: string): number => hay.split(needle).length - 1;

// Parses `{ tagged_event = { key = "<k>", match = "<m>", value = "<v>" } }` rows by key, so the
// order of the conditions in the block is irrelevant.
function taggedEvent(block: string, key: string): { match: string; value: string } | null {
  const re = new RegExp(
    `tagged_event\\s*=\\s*\\{\\s*key\\s*=\\s*"${key}",\\s*match\\s*=\\s*"([^"]*)",\\s*value\\s*=\\s*"([^"]*)"\\s*\\}`,
    "g",
  );
  const hits = [...block.matchAll(re)];
  if (hits.length !== 1) return null;
  return { match: hits[0][1], value: hits[0][2] };
}

describe("inngest_provision_failure alert ↔ soleur-inngest-provision emitter contract (#9176)", () => {
  const block = tfBlockFor("inngest_provision_failure");
  const provision = provisionBlock();

  it("T1: declares the resource and finds the provision script", () => {
    expect(block).toContain('resource "sentry_alert" "inngest_provision_failure"');
    expect(block).toContain('name              = "inngest-provision-failure"');
    expect(provision).toContain("on_exit() {");
  });

  it("T2: both filters must hold (under `any` the nc row alone matches every boot stage)", () => {
    expect(block).toMatch(/^\s*logic_type\s*=\s*"all"\s*$/m);
  });

  it("T3: the stage set equals every warning stage the provision script emits (derived, literal-only)", () => {
    // A wrapper (`soleur-boot-emit "$1" …`) would hide stages from this derivation, so any
    // non-literal call inside the provision block is itself a failure.
    expect(provision).not.toMatch(/soleur-boot-emit\s+["$]/);
    const emitted = new Set(
      [...provision.matchAll(/soleur-boot-emit\s+([A-Za-z0-9_]+)\s+warning\b/g)].map((m) => m[1]),
    );
    expect(emitted.size).toBeGreaterThan(0);
    expect(emitted.has("provision_attempt_failed")).toBe(true);

    const stage = taggedEvent(block, "stage");
    expect(stage).not.toBeNull();
    expect(stage!.match).toBe("in");
    const ruled = new Set(stage!.value.split(","));
    expect([...ruled].sort()).toEqual([...emitted].sort());
  });

  it("T4: pull misses are excluded by detail not-contains why=inngest_pull_fatal", () => {
    expect(taggedEvent(block, "detail")).toEqual({ match: "nc", value: "why=inngest_pull_fatal" });
  });

  it("T5: the emitter still carries why=<stage> in detail, through a charset that keeps = and _", () => {
    expect(provision).toContain(
      'soleur-boot-emit provision_attempt_failed warning "rc=$rc.attempt=$attempt.why=$last_stage.iid=$IID"',
    );
    expect(provision).toContain('soleur-boot-emit bootstrap_done_degraded warning "why=$_degraded.');
    expect(inngestInit).toContain("LC_ALL=C tr -cd 'A-Za-z0-9=.:_-'");
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

  it("T8: each paged stage is emitted by the inngest host only (no host_name filter needed)", () => {
    const stage = taggedEvent(block, "stage");
    expect(stage).not.toBeNull();
    for (const s of stage!.value.split(",")) {
      expect(count(inngestInit, `soleur-boot-emit ${s} `)).toBeGreaterThan(0);
      expect(count(webInit, `soleur-boot-emit ${s}`)).toBe(0);
    }
  });
});
