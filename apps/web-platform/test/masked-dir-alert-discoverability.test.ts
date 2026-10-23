// scripts/masked-dir-alert-discoverability.sh answers one question without credentials or network: is there a LIVE path from a failed
// masked-dir pre-create to a human? It prints MASKED_DIR_ALERT_PATH_OK only for an uncommented emit plus ONE enabled sentry_alert block
// (a monitor, an event_frequency_count trigger at value 0, and ONE action-filter entry with logic_type "all", feature eq agent-sandbox,
// op eq masked-dir-precreate and an issue_owners email that is not NoOne). This suite runs the SAME script (MASKED_DIR_ALERT_SERVER_DIR /
// MASKED_DIR_ALERT_SENTRY_DIR point it at temp copies) once on the canonical files (the control) and once per mutation, each of which must
// make it exit non-zero without printing the OK line. A run through the seam NEVER prints the OK token (Preflight matches it by substring):
// it prints MASKED_DIR_ALERT_OVERRIDE and ends with MASKED_DIR_ALERT_SEAM_PASS, which is what the controls below assert.
import { spawnSync } from "node:child_process";
import { copyFileSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { afterAll, describe, expect, it } from "vitest";

const APP = join(dirname(fileURLToPath(import.meta.url)), "..");
const SCRIPT = join(APP, "..", "..", "scripts", "masked-dir-alert-discoverability.sh");
const EMIT_FILE = "agent-runner-sandbox-config.ts";
const REAL_EMIT = readFileSync(join(APP, "server", EMIT_FILE), "utf8");
const REAL_TF = readFileSync(join(APP, "infra", "sentry", "issue-alerts.tf"), "utf8");
const OK = "MASKED_DIR_ALERT_PATH_OK";
const SEAM_PASS = "MASKED_DIR_ALERT_SEAM_PASS";

const RULE_START = REAL_TF.indexOf('resource "sentry_alert" "masked_dir_precreate_failed" {');
const RULE_END = REAL_TF.indexOf("\n}\n", RULE_START) + 3;
const RULE = REAL_TF.slice(RULE_START, RULE_END);

const roots: string[] = [];
afterAll(() => {
  for (const r of roots) rmSync(r, { recursive: true, force: true });
});

function run(emit: { name: string; src: string }, tf: string) {
  const root = mkdtempSync(join(tmpdir(), "masked-dir-alert-"));
  roots.push(root);
  const server = join(root, "server");
  const sentry = join(root, "sentry");
  mkdirSync(join(server, "lib"), { recursive: true });
  mkdirSync(sentry);
  writeFileSync(join(server, "lib", emit.name), emit.src);
  writeFileSync(join(sentry, "issue-alerts.tf"), tf);
  const r = spawnSync("bash", [SCRIPT], { env: { PATH: process.env.PATH ?? "", MASKED_DIR_ALERT_SERVER_DIR: server, MASKED_DIR_ALERT_SENTRY_DIR: sentry }, encoding: "utf8", timeout: 20000 });
  return { rc: r.status, out: r.stdout };
}
const canonical = () => run({ name: EMIT_FILE, src: REAL_EMIT }, REAL_TF);
const withRule = (mut: (rule: string) => string) => {
  const rule = mut(RULE);
  expect(rule, "the rule mutation did not change the block").not.toBe(RULE);
  return REAL_TF.slice(0, RULE_START) + rule + REAL_TF.slice(RULE_END);
};
const EMIT_LINE = REAL_EMIT.split("\n").find((l) => /op:\s*"masked-dir-precreate"/.test(l))!;
const withEmit = (mut: (src: string) => string) => {
  const src = mut(REAL_EMIT);
  expect(src, "the emit mutation did not change the source").not.toBe(REAL_EMIT);
  return src;
};

describe("masked-dir-alert-discoverability.sh", () => {
  it("CONTROL: the canonical files, through the seam, pass with the SEAM token, announce the override, and never print the OK token", () => {
    const r = canonical();
    expect(r.rc).toBe(0);
    expect(r.out).toContain(SEAM_PASS);
    expect(r.out).toContain("MASKED_DIR_ALERT_OVERRIDE");
    expect(r.out).not.toContain(OK);
    expect(r.out).toContain("rule: sentry_alert.masked_dir_precreate_failed");
  });

  it("CONTROL: the real repo (no override) prints OK, no override line and no seam token", () => {
    const r = spawnSync("bash", [SCRIPT], { env: { PATH: process.env.PATH ?? "" }, encoding: "utf8", timeout: 60000 });
    expect(r.status).toBe(0);
    expect(r.stdout).toContain(OK);
    expect(r.stdout).not.toContain("MASKED_DIR_ALERT_OVERRIDE");
    expect(r.stdout).not.toContain(SEAM_PASS);
  });

  it("either seam variable alone (or set empty) is an override: the override line, the SEAM token and no OK token", () => {
    const base = { PATH: process.env.PATH ?? "" };
    const realServer = join(APP, "server");
    const realSentry = join(APP, "infra", "sentry");
    for (const [label, env] of [
      ["server dir only", { MASKED_DIR_ALERT_SERVER_DIR: realServer }],
      ["sentry dir only", { MASKED_DIR_ALERT_SENTRY_DIR: realSentry }],
      ["server dir set empty", { MASKED_DIR_ALERT_SERVER_DIR: "" }],
      ["sentry dir set empty", { MASKED_DIR_ALERT_SENTRY_DIR: "" }],
    ] as const) {
      const r = spawnSync("bash", [SCRIPT], { env: { ...base, ...env }, encoding: "utf8", timeout: 60000 });
      expect(r.status, label).toBe(0);
      expect(r.stdout, label).toContain("MASKED_DIR_ALERT_OVERRIDE");
      expect(r.stdout, label).toContain(SEAM_PASS);
      expect(r.stdout, label).not.toContain(OK);
    }
  });

  it("a reformatted but equivalent rule still passes: a multi-line non-empty monitor_ids list, a reordered action filter", () => {
    const multi = withRule((r) => r.replace(/monitor_ids\s*=\s*\[(.*)\]/, "monitor_ids = [\n    $1,\n  ]"));
    const a = run({ name: EMIT_FILE, src: REAL_EMIT }, multi);
    expect(a.rc, a.out).toBe(0);
    expect(a.out).toContain(SEAM_PASS);
    const reordered = withRule((r) => r.replace(/(\s*)(logic_type = "all"\n)(\s*conditions = \[[\s\S]*?\n\s*\]\n)(\s*actions = \[[\s\S]*?\n\s*\]\n)/, "$1$4$3$2"));
    const b = run({ name: EMIT_FILE, src: REAL_EMIT }, reordered);
    expect(b.rc, b.out).toBe(0);
    expect(b.out).toContain(SEAM_PASS);
  });

  const tfRows: Array<[string, (rule: string) => string]> = [
    ["enabled = false", (r) => r.replace("enabled           = true", "enabled           = false")],
    ['enabled = false with a trailing comment that says true', (r) => r.replace("enabled           = true", "enabled           = false # = true")],
    ["enabled line removed", (r) => r.replace(/^\s*enabled\s*=\s*true\n/m, "")],
    ['logic_type = "none"', (r) => r.replace('logic_type = "all"', 'logic_type = "none"')],
    ["logic_type line removed", (r) => r.replace(/^\s*logic_type\s*=\s*"all"\n/m, "")],
    ["logic_type = \"any-short\"", (r) => r.replace('logic_type = "all"', 'logic_type = "any-short"')],
    ['fallthrough_type = "NoOne"', (r) => r.replace('fallthrough_type = "ActiveMembers"', 'fallthrough_type = "NoOne"')],
    ["email action removed", (r) => r.replace(/^\s*\{ email = .*\n/m, "")],
    ["op condition removed", (r) => r.replace(/^\s*\{ tagged_event = \{ key = "op".*\n/m, "")],
    ["op value renamed", (r) => r.replace('value = "masked-dir-precreate"', 'value = "masked-dir-precreate-x"')],
    ["op match not eq", (r) => r.replace('key = "op", match = "eq"', 'key = "op", match = "co"')],
    ["feature value renamed", (r) => r.replace('value = "agent-sandbox"', 'value = "agent-sandbox-x"')],
    ["feature condition removed", (r) => r.replace(/^\s*\{ tagged_event = \{ key = "feature".*\n/m, "")],
    ["the op condition commented out with #", (r) => r.replace(/^(\s*)(\{ tagged_event = \{ key = "op".*)$/m, "$1# $2")],
    ["the op condition commented out with //", (r) => r.replace(/^(\s*)(\{ tagged_event = \{ key = "op".*)$/m, "$1// $2")],
    ["the email action commented out", (r) => r.replace(/^(\s*)(\{ email = .*)$/m, "$1# $2")],
    ["the whole rule commented out with #", (r) => r.split("\n").map((l) => `# ${l}`).join("\n")],
    ["the whole rule inside a block comment", (r) => `/*\n${r}*/\n`],
    ["monitor_ids = []", (r) => r.replace(/monitor_ids\s*=\s*\[.*\]/, "monitor_ids       = []")],
    ["monitor_ids = [ ] spread over two lines", (r) => r.replace(/monitor_ids\s*=\s*\[.*\]/, "monitor_ids       = [\n  ]")],
    ["monitor_ids line removed", (r) => r.replace(/^\s*monitor_ids\s*=.*\n/m, "")],
    ["trigger_conditions attribute removed", (r) => r.replace(/\n\s*trigger_conditions = \[\n[\s\S]*?\n\s*\]\n/, "\n")],
    ["trigger_conditions empty", (r) => r.replace(/\{ event_frequency_count = .*\},?\n/, "")],
    ["trigger threshold 100000 (a single failure never reaches it)", (r) => r.replace("value = 0 }", "value = 100000 }")],
    ["trigger threshold 1", (r) => r.replace("value = 0 }", "value = 1 }")],
    [
      "a second trigger entry with an absurd threshold beside the value-0 one",
      (r) => r.replace(/(\s*)(\{ event_frequency_count = .*\},?\n)/, '$1$2$1{ event_frequency_count = { interval = "1h", value = 100000 } },\n'),
    ],
    ["trigger is a different condition type (first_seen_event)", (r) => r.replace(/\{ event_frequency_count = .*\}/, "{ first_seen_event = {} }")],
    ['email target_type = "member"', (r) => r.replace('target_type = "issue_owners"', 'target_type = "member"')],
    ["email target_type missing", (r) => r.replace('target_type = "issue_owners", ', "")],
    [
      "actions = [] on the op entry while an email sits in a SECOND entry conditioned on another feature (rule-level tracking would pass)",
      (r) =>
        r.replace(
          /actions = \[\n\s*\{ email = .*\n\s*\]\n(\s*)\},\n(\s*)\]/,
          'actions = []\n$1},\n$1{\n$1  logic_type = "all"\n$1  conditions = [\n$1    { tagged_event = { key = "feature", match = "eq", value = "other-feature" } },\n$1  ]\n$1  actions = [\n$1    { email = { target_type = "issue_owners", fallthrough_type = "ActiveMembers" } },\n$1  ]\n$1},\n$2]',
        ),
    ],
    [
      "the op conditions in one entry and the email in another entry that only has the feature condition",
      (r) =>
        r.replace(
          /actions = \[\n\s*\{ email = .*\n\s*\]\n(\s*)\},\n(\s*)\]/,
          'actions = []\n$1},\n$1{\n$1  logic_type = "all"\n$1  conditions = [\n$1    { tagged_event = { key = "feature", match = "eq", value = "agent-sandbox" } },\n$1  ]\n$1  actions = [\n$1    { email = { target_type = "issue_owners", fallthrough_type = "ActiveMembers" } },\n$1  ]\n$1},\n$2]',
        ),
    ],
    [
      "the email action in a DIFFERENT resource block than the op filter",
      (r) => r.replace(/^(\s*)actions = \[/m, '}\n\nresource "sentry_alert" "other_rule" {\n$1actions = ['),
    ],
  ];
  for (const [name, mut] of tfRows) {
    it(`NEGATIVE: ${name} -> fails and does not print OK`, () => {
      const r = run({ name: EMIT_FILE, src: REAL_EMIT }, withRule(mut));
      expect(r.rc, r.out).toBe(1);
      expect(r.out).not.toContain(OK);
      expect(r.out).toContain("MASKED_DIR_ALERT_PATH_FAIL");
    });
  }

  const emitRows: Array<[string, (src: string) => string]> = [
    ["the emit commented out with //", (s) => s.replace(EMIT_LINE, `// ${EMIT_LINE.trim()}`)],
    ["the emit inside a /* block comment */", (s) => s.replace(EMIT_LINE, `/* ${EMIT_LINE.trim()} */`)],
    ["the emit on a multi-line block comment", (s) => s.replace(EMIT_LINE, `/*\n${EMIT_LINE}\n*/`)],
    ["the op renamed", (s) => s.replace(EMIT_LINE, EMIT_LINE.replace("masked-dir-precreate", "masked-dir-precreate-x"))],
    ["the op behind an indirection (a constant, no literal)", (s) => s.replace(EMIT_LINE, EMIT_LINE.replace(/"masked-dir-precreate"/, "OP_NAME"))],
  ];
  for (const [name, mut] of emitRows) {
    it(`NEGATIVE: ${name} -> fails and does not print OK`, () => {
      const r = run({ name: EMIT_FILE, src: withEmit(mut) }, REAL_TF);
      expect(r.rc, r.out).toBe(1);
      expect(r.out).not.toContain(OK);
    });
  }

  it("NEGATIVE: an emit that lives only in a test file does not count", () => {
    for (const name of ["agent-runner-sandbox-config.test.ts", "x.spec.ts"]) {
      const r = run({ name, src: REAL_EMIT }, REAL_TF);
      expect(r.rc, name).toBe(1);
      expect(r.out).not.toContain(OK);
    }
  });

  it("NEGATIVE: no Terraform files at all, and a missing server dir, fail", () => {
    const root = mkdtempSync(join(tmpdir(), "masked-dir-alert-empty-"));
    roots.push(root);
    mkdirSync(join(root, "sentry"));
    mkdirSync(join(root, "server"));
    copyFileSync(join(APP, "server", EMIT_FILE), join(root, "server", EMIT_FILE));
    const r = spawnSync("bash", [SCRIPT], { env: { PATH: process.env.PATH ?? "", MASKED_DIR_ALERT_SERVER_DIR: join(root, "server"), MASKED_DIR_ALERT_SENTRY_DIR: join(root, "sentry") }, encoding: "utf8" });
    expect(r.status).toBe(1);
    expect(r.stdout).not.toContain(OK);
    const r2 = spawnSync("bash", [SCRIPT], { env: { PATH: process.env.PATH ?? "", MASKED_DIR_ALERT_SERVER_DIR: join(root, "no-such"), MASKED_DIR_ALERT_SENTRY_DIR: join(root, "sentry") }, encoding: "utf8" });
    expect(r2.status).toBe(1);
    expect(r2.stdout).not.toContain(OK);
  });
});
