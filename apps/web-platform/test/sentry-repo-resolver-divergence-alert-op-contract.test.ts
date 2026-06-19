import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { describe, it, expect } from "vitest";

// Cross-artifact contract test (this PR — dispatch-time repo-resolver divergence).
//
// The `repo-resolver-divergence` Sentry issue-alert filters on
// `feature == "repo-resolver-divergence"` ONLY (no `op` filter). Every op the
// emitter declares (non-member-claim-reset / self-heal-failed /
// connected-null-install-at-dispatch) carries that feature tag and is
// operator-actionable. Feature-only matching covers them ALL and future-proofs
// against new ops.
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
// matching must cover all of them.
const OPS = [
  "non-member-claim-reset",
  "self-heal-failed",
  "connected-null-install-at-dispatch",
];

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
    for (const op of OPS) expect(emitter).toContain(op);
  });

  it("AC6: the alert is feature-only — no op-scoped filter can dark a new op", () => {
    const block = divergenceAlertBlock();
    // The block filters on feature; it must NOT carry an `op` tagged_event
    // filter (which would silently exclude ops not in its allow-list).
    expect(block).toContain('value = "repo-resolver-divergence"');
    expect(block).not.toMatch(/key\s*=\s*"op"/);
  });
});
