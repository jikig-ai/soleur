import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { describe, it, expect } from "vitest";

// Cross-artifact contract tests for the two #6512 Sentry issue-alerts, mirroring the sibling
// `sentry-*-alert-op-contract.test.ts` convention (kb_db_error, zot_mirror_fallback_rate, …).
//
// Both alerts use `filter_match = "all"` with a single `tagged_event` on a string the EMITTER must
// produce as a Sentry tag. A rename of the tag value on EITHER side — the emitter (ci-deploy.sh's
// `registry_pull_event "local-cache"`, or seccomp-unenforced-alert.sh's `op: "seccomp-remediation-
// failed"`) or the `.tf` filter value — would silently zero the alert's matches and dark the page,
// while both the emitter-side bash tests and CI stay green (the #4658 / silent-dark-page class).
// These tests bind the two sides together.
//
// Substring match only: each token is an inline string literal at its emit site; a whole-file
// match finds it. Filter-side assertions are scoped to the specific resource BLOCK so a token
// lingering in a comment or a sibling rule cannot mask its removal from THIS rule.

const here = dirname(fileURLToPath(import.meta.url));
const tf = readFileSync(join(here, "../infra/sentry/issue-alerts.tf"), "utf8");
const ciDeploy = readFileSync(join(here, "../infra/ci-deploy.sh"), "utf8");
const alertScript = readFileSync(
  join(here, "../../../scripts/seccomp-unenforced-alert.sh"),
  "utf8",
);

function tfBlockFor(resourceName: string): string {
  const decl = `resource "sentry_issue_alert" "${resourceName}"`;
  const start = tf.indexOf(decl);
  if (start === -1) return "";
  const next = tf.indexOf("\nresource ", start + decl.length);
  return tf.slice(start, next === -1 ? undefined : next);
}

// The rule's frequency (from its own block) must be unique across every real `frequency = N`
// HCL attribute line in the file (line-anchored so a comment mention like `frequency = 26` in
// prose cannot inflate the count — the drift-guard false-fail class).
function assertUniqueFrequency(block: string): void {
  const m = block.match(/^\s*frequency\s*=\s*(\d+)/m);
  expect(m).not.toBeNull();
  const freq = m![1];
  const all = tf.match(new RegExp(`^\\s*frequency\\s*=\\s*${freq}\\b`, "gm")) ?? [];
  expect(all.length).toBe(1);
}

describe("local_cache_reload_rate alert ↔ ci-deploy.sh registry tag contract (#6512 Fix 1)", () => {
  const block = tfBlockFor("local_cache_reload_rate");

  it("declares the resource", () => {
    expect(block).toContain(
      'resource "sentry_issue_alert" "local_cache_reload_rate"',
    );
  });

  it("the `local-cache` registry tag appears in BOTH the emitter and the filter block", () => {
    // Emit side: the tier calls `registry_pull_event "local-cache" …`, and registry_pull_event
    // maps its first arg into `tags.registry` — so the literal must exist as that call.
    expect(ciDeploy).toContain('registry_pull_event "local-cache"');
    // Filter side: the same literal must be in THIS rule's block.
    expect(block).toContain("local-cache");
  });

  it("ANDs its filter on registry == local-cache (structural pins)", () => {
    expect(block).toContain('filter_match = "all"');
    expect(block).toMatch(/key\s*=\s*"registry"[\s\S]*?match\s*=\s*"EQUAL"/);
    expect(block).toMatch(/value\s*=\s*"local-cache"/);
  });

  it("has a unique frequency", () => assertUniqueFrequency(block));
});

describe("seccomp_remediation_failed alert ↔ seccomp-unenforced-alert.sh op tag contract (#6512 Fix 2a)", () => {
  const block = tfBlockFor("seccomp_remediation_failed");

  it("declares the resource", () => {
    expect(block).toContain(
      'resource "sentry_issue_alert" "seccomp_remediation_failed"',
    );
  });

  it("the `seccomp-remediation-failed` op tag appears in BOTH the emitter and the filter block", () => {
    // Emit side: the alert script's jq payload sets `op: "seccomp-remediation-failed"` under tags.
    expect(alertScript).toContain('op: "seccomp-remediation-failed"');
    // Filter side: the same literal must be in THIS rule's block.
    expect(block).toContain("seccomp-remediation-failed");
  });

  it("ANDs its filter on op == seccomp-remediation-failed (structural pins)", () => {
    expect(block).toContain('filter_match = "all"');
    expect(block).toMatch(/key\s*=\s*"op"[\s\S]*?match\s*=\s*"EQUAL"/);
    expect(block).toMatch(/value\s*=\s*"seccomp-remediation-failed"/);
  });

  it("has a unique frequency", () => assertUniqueFrequency(block));
});
