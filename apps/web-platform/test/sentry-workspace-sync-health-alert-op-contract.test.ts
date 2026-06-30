import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { describe, it, expect } from "vitest";

// Cross-artifact contract test (#4882).
//
// The `workspace-sync-health` Sentry issue-alert filters on
// `feature == "workspace-sync-health"` ONLY (no `op` filter). Every event the
// `cron-workspace-sync-health` probe emits carries that feature tag and is
// operator-actionable — the 3 findings (ready-null-installation /
// stale-sync-failed / went-quiet) AND the 4 probe-self-failure ops (scan /
// scan-stale / scan-went-quiet / went-quiet-probe), which are the ONLY signal
// when arms 2/3 swallow a scan error the heartbeat misses. Feature-only matching
// covers them all and future-proofs against new cron arms.
//
// Because the match is feature-only, the single load-bearing cross-artifact
// contract is the `feature` tag itself: a rename of `SENTRY_FEATURE` in the cron
// OR of the filter value in issue-alerts.tf would silently zero the alert's
// matches, recreating the user-reports-it-before-we-know failure mode the
// KB-sync-stale PIR (#4878) is about. This test pins that one string in both
// artifacts so the rename breaks CI instead.
//
// Substring match only (mirrors sentry-chat-alert-op-contract.test.ts): the
// cron declares `const SENTRY_FEATURE = "workspace-sync-health"` and the tf
// carries it as the feature filter value — a whole-file match finds both.

const here = dirname(fileURLToPath(import.meta.url));
const tf = readFileSync(join(here, "../infra/sentry/issue-alerts.tf"), "utf8");
const cron = readFileSync(
  join(here, "../server/inngest/functions/cron-workspace-sync-health.ts"),
  "utf8",
);
const reconcileOnPush = readFileSync(
  join(here, "../server/inngest/functions/workspace-reconcile-on-push.ts"),
  "utf8",
);

const FEATURE_TAG = "workspace-sync-health";

describe("workspace-sync-health alert feature contract", () => {
  it("the feature tag appears in the cron emit site (SENTRY_FEATURE const)", () => {
    expect(cron).toContain(FEATURE_TAG);
  });

  it("the feature tag appears in the alert filter in issue-alerts.tf", () => {
    expect(tf).toContain(FEATURE_TAG);
  });

  it("issue-alerts.tf declares the workspace_sync_health alert resource", () => {
    expect(tf).toContain('resource "sentry_issue_alert" "workspace_sync_health"');
  });
});

// The push-reconcile readiness gate moved from dir-existence to worktree
// VALIDITY + re-clone (ADR-044 amendment 2026-06-29). The OLD gate fired
// `reportSilentFallback(op:"skip-not-ready")` for every dir-absent workspace —
// a paging signal. The reclone path eliminates it (dir-absent now routes to
// `ensureWorkspaceRepoCloned`, whose own mirrors page on genuine failure). If
// any Sentry alert / Better Stack monitor keyed on `skip-not-ready`, this change
// darks it; pin the REMOVAL so a regression that re-introduces the dead op
// breaks CI (data-integrity-review P2).
describe("workspace-reconcile-on-push — skip-not-ready op is removed (data-integrity P2)", () => {
  it("the reconcile handler no longer emits op:\"skip-not-ready\"", () => {
    expect(reconcileOnPush).not.toContain("skip-not-ready");
  });
});
