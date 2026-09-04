// Suites whose SUBJECT is the whole repository, not this app.
//
// `test-all.sh` gates the app-local vitest projects on a diff touching
// `apps/web-platform/`. These files would be WRONG to gate that way: they read
// files outside the app (plugin scripts, workflow YAML, the knowledge base) and
// exist to catch drift in exactly the diffs that touch nothing here. Gated,
// they would be declined on the commits they guard, and the decline would read
// as intentional in the run summary.
//
// So they run ALWAYS, as their own vitest project.
//
// MEMBERSHIP IS NOT HAND-MAINTAINED. `test/repo-wide-containment.test.ts`
// recomputes this set from disk on every run and fails if it drifts, naming the
// files to add or remove. Adding a test that escapes the app without updating
// this list turns that guard red — which is the point: the alternative is a new
// repo-reading test landing in the gated project and silently never running.
//
// The predicate is depth-aware, NOT a grep for `../../..`. A flat grep is
// unsound in BOTH directions, and this repo has been bitten each way:
//   * over-match — `join(__dirname, "..", "..")` from `test/server/` lands ON
//     `apps/web-platform`, so it is app-local despite reading two levels up.
//     `test/c4-render.test.ts` names `knowledge-base/...` only as a synthetic
//     `/workspaces/ws-1/...` constant and reads nothing.
//   * under-match — `test/git-lock-marker-telemetry.test.ts` reaches the repo
//     via `"../../../plugins/soleur/..."`, which a `readFileSync`-plus-literal
//     heuristic misses entirely.
// A file escapes only when its longest `..` run EXCEEDS its depth below
// `apps/web-platform`, or it names a repo-root helper (GIT_ROOT, repoRoot, …).
export const REPO_WIDE_SUITES: readonly string[] = [
  "test/agent-runner-system-prompt.test.ts",
  "test/c4-diagram-path-scope.test.ts",
  "test/c4-likec4-version-pin.test.ts",
  "test/c4-project-route.test.ts",
  "test/cc-dispatcher-concierge-context.test.ts",
  "test/cla-evidence/allowlist.test.ts",
  "test/cla-evidence/hash.test.ts",
  "test/cla-evidence/roster-entry-gate.test.ts",
  "test/context-injection.test.ts",
  "test/context-queries-hook.test.ts",
  "test/context-queries-shell-parity.test.ts",
  "test/conversations-update-grep-detector.test.ts",
  "test/dsar-worm-guc-sites.test.ts",
  "test/eslint-config.test.ts",
  "test/git-lock-marker-telemetry.test.ts",
  "test/github-app-manifest-parity.test.ts",
  "test/kb-content-binary.test.ts",
  "test/kb-delete.test.ts",
  "test/kb-reader.test.ts",
  "test/kb-rename.test.ts",
  "test/kb-route-helpers.test.ts",
  "test/kb-serve.test.ts",
  "test/kb-upload.test.ts",
  "test/leader-document-resolver.test.ts",
  "test/legal-doc-consistency.test.ts",
  "test/legal-doc-shas-guard.test.ts",
  "test/phase-surface-hint-shell-parity.test.ts",
  "test/phase-surface-map-parity.test.ts",
  "test/plugin-root-anchoring.test.ts",
  "test/plugin-root-list-carveout-coupling.test.ts",
  "test/repo-wide-containment.test.ts",
  "test/safe-bash.test.ts",
  "test/safe-return-to.test.ts",
  "test/sandbox-relative-paths.test.ts",
  "test/sandbox.test.ts",
  "test/scripts/run-migrations-unmerged-gate.test.ts",
  "test/sentry-seccomp-alerts-op-contract.test.ts",
  "test/sentry-zot-mirror-fallback-alert-op-contract.test.ts",
  "test/seo-config-rules.test.ts",
  "test/seo-rulesets-noindex.test.ts",
  "test/server/inngest/cron-claude-eval-mcp-flags.test.ts",
  "test/server/inngest/cron-community-monitor-collector-status.test.ts",
  "test/server/inngest/cron-compound-promote.test.ts",
  "test/server/inngest/cron-plausible-goals.test.ts",
  "test/server/inngest/cron-safe-commit-parity.test.ts",
  "test/server/inngest/cron-weekly-release-digest.test.ts",
  "test/server/inngest/leader-prompts/tool-surface.test.ts",
  "test/server/inngest/rule-body-gate-recursion-invariant.test.ts",
  "test/server/inngest/sentry-monitor-iac-parity.test.ts",
  "test/service-tools.test.ts",
  "test/supabase-migrations/117-reconcile-ownership-rpc-comments-multi-owner.test.ts",
  "test/workspace-cleanup.test.ts",
  "test/workspace-resolver-id-shape-guard.test.ts",
  "test/worktree-id-validation.test.ts",
  "test/ws-context-validation.test.ts",
  "test/ws-resume-by-context-path.test.ts",
];
