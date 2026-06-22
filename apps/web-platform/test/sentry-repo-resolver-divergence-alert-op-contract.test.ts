import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { describe, it, expect } from "vitest";

// Cross-artifact contract test (this PR — dispatch-time repo-resolver divergence).
//
// The `repo-resolver-divergence` Sentry issue-alert filters on
// `feature == "repo-resolver-divergence"` ONLY (no `op` filter). Every op the
// emitter declares (non-member-claim-reset / self-heal-failed /
// connected-null-install-at-dispatch / reprovision-non-member-claim-reset)
// carries that feature tag and is operator-actionable. Feature-only matching
// covers them ALL and future-proofs against new ops.
//
// AC6 — the load-bearing invariant: because the filter is feature-only, adding a
// new `RepoResolverDivergenceOp` member can NEVER dark the alert. This test pins
// that the alert block contains NO `op`-scoped filter (which WOULD dark a new
// op), so a future "scope the alert by op" edit breaks CI instead of silently
// dropping the previously-dark dispatch signal this PR just made observable.

const here = dirname(fileURLToPath(import.meta.url));
const tf = readFileSync(join(here, "../infra/sentry/issue-alerts.tf"), "utf8");
const emitter = readFileSync(
  join(here, "../server/repo-resolver-divergence.ts"),
  "utf8",
);

const FEATURE_TAG = "repo-resolver-divergence";

// Every op the emitter's RepoResolverDivergenceOp union declares. Feature-only
// matching must cover all of them — keep this list in lockstep with the union in
// server/repo-resolver-divergence.ts when adding an op (the "declared in union"
// case below is the tripwire that forces it).
const OPS = [
  "non-member-claim-reset",
  "self-heal-failed",
  "connected-null-install-at-dispatch",
  "reprovision-non-member-claim-reset",
];

// Guard against the substring trap: "non-member-claim-reset" is a substring of
// "reprovision-non-member-claim-reset", so a bare `emitter.toContain(op)` cannot
// distinguish them. Assert the new op is present as a DISTINCT quoted union
// member, not merely as a substring of the older one.
const DISTINCT_OPS_GUARD = "reprovision-non-member-claim-reset";

/** Extract the body of the repo_resolver_divergence resource block. */
function divergenceAlertBlock(): string {
  const start = tf.indexOf(
    'resource "sentry_issue_alert" "repo_resolver_divergence"',
  );
  expect(start).toBeGreaterThanOrEqual(0);
  // Read to the next top-level `resource "` declaration (or EOF).
  const rest = tf.slice(start + 1);
  const nextResource = rest.indexOf('\nresource "');
  return nextResource === -1 ? rest : rest.slice(0, nextResource);
}

describe("repo-resolver-divergence alert feature contract", () => {
  it("the feature tag appears in the emitter (reportRepoResolverDivergence)", () => {
    expect(emitter).toContain(FEATURE_TAG);
  });

  it("the feature tag appears in the alert filter in issue-alerts.tf", () => {
    expect(tf).toContain(FEATURE_TAG);
  });

  it("issue-alerts.tf declares the repo_resolver_divergence alert resource", () => {
    expect(tf).toContain(
      'resource "sentry_issue_alert" "repo_resolver_divergence"',
    );
  });

  it("every RepoResolverDivergenceOp member is declared in the emitter union", () => {
    // Assert the QUOTED literal so a substring (e.g. "non-member-claim-reset"
    // inside "reprovision-non-member-claim-reset") cannot satisfy a sibling op.
    for (const op of OPS) expect(emitter).toContain(`"${op}"`);
  });

  it("the reprovision-path op (ADR-044 PR-3) is a distinct quoted union member", () => {
    expect(emitter).toContain(`"${DISTINCT_OPS_GUARD}"`);
  });

  it("AC6: the alert is feature-only — no op-scoped filter can dark a new op", () => {
    const block = divergenceAlertBlock();
    // The block filters on feature; it must NOT carry an `op` tagged_event
    // filter (which would silently exclude ops not in its allow-list).
    // Whitespace-tolerant so a `terraform fmt` re-alignment of the attribute
    // does not false-fail the contract (mirrors the negative `op` check below).
    expect(block).toMatch(/value\s*=\s*"repo-resolver-divergence"/);
    expect(block).not.toMatch(/key\s*=\s*"op"/);
  });
});
