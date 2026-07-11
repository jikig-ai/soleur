# Agent Instructions — Index

Pointer index; bodies in `AGENTS.{core,docs,rest}.md`, injected per change-class by the SessionStart hook (multi-class/empty → all, fail-closed).

## Hard Rules

- [id: hr-never-git-stash-in-worktrees] → core
- [id: hr-mcp-tools-playwright-etc-resolve-paths] → core
- [id: hr-when-a-command-exits-non-zero-or-prints] → core
- [id: hr-always-read-a-file-before-editing-it] → core
- [id: hr-when-a-plan-specifies-relative-paths-e-g] → core
- [id: hr-the-host-terminal-is-warp] → core
- [id: hr-the-bash-tool-runs-in-a-non-interactive] → core
- [id: hr-exhaust-all-automated-options-before] → core
- [id: hr-never-label-any-step-as-manual-without] → core
- [id: hr-multi-step-post-merge-bootstrap-script] → core
- [id: hr-tagged-build-workflow-needs-initial-tag-push] → core
- [id: hr-ship-message-no-operator-checklist] → core
- [id: hr-when-triaging-a-batch-of-issues-never] → core
- [id: hr-all-infrastructure-provisioning-servers] → core
- [id: hr-fresh-host-provisioning-reachable-from-terraform-apply] → core
- [id: hr-prod-host-config-change-immutable-redeploy] → core
- [id: hr-autonomous-loop-skill-api-budget-disclosure] → core
- [id: hr-every-new-terraform-root-must-include-an] → core
- [id: hr-tf-variable-no-operator-mint-default] → core
- [id: hr-new-skills-agents-or-user-facing] → core
- [id: hr-before-shipping-ship-phase-5-5-runs] → core
- [id: hr-when-a-workflow-concludes-with-an] → core
- [id: hr-before-asserting-github-issue-status] → core
- [id: hr-never-run-commands-with-unbounded-output] → core
- [id: hr-never-write-to-claude-code-memory-claude] → core
- [id: hr-when-in-a-worktree-never-read-from-bare] → core
- [id: hr-github-api-endpoints-with-enum] → core
- [id: hr-menu-option-ack-not-prod-write-auth] → core
- [id: hr-ssh-diagnosis-verify-firewall] → core
- [id: hr-never-git-add-a-in-user-repo-agents] → core
- [id: hr-dev-prd-distinct-supabase-projects] → core
- [id: hr-weigh-every-decision-against-target-user-impact] → core
- [id: hr-never-paste-secrets-via-bang-prefix] → core
- [id: hr-gdpr-gate-on-regulated-data-surfaces] → core
- [id: hr-type-widening-cross-consumer-grep] → core
- [id: hr-write-boundary-sentinel-sweep-all-write-sites] → core
- [id: hr-bulk-delete-per-item-live-infra-role-check] → core
- [id: hr-no-dashboard-eyeball-pull-data-yourself] → core
- [id: hr-observability-as-plan-quality-gate] → core
- [id: hr-no-ssh-fallback-in-runbooks] → core
- [id: hr-observability-layer-citation] → core
- [id: hr-github-app-auth-not-pat] → core
- [id: hr-monitor-not-run-in-background-for-polling] → core
- [id: hr-verify-repo-capability-claim-before-assert] → core
- [id: hr-pipeline-skills-never-inline-after-go-route] → core

## Workflow Gates

- [id: wg-every-feature-listed-in-a-roadmap-phase] → rest
- [id: wg-when-closing-a-phase-milestone-update] → rest
- [id: wg-when-fixing-a-workflow-gates-detection] → rest
- [id: wg-zero-agents-until-user-confirms] → core
- [id: wg-verified-work-ships-without-asking] → rest
- [id: wg-never-bump-version-files-in-feature] → rest
- [id: wg-after-marking-a-pr-ready-run-gh-pr-merge] → rest
- [id: wg-ship-push-before-merge] → rest
- [id: wg-cla-signed-author-before-merge] → rest
- [id: wg-after-a-pr-merges-to-main-verify-all] → rest
- [id: wg-dark-launch-deploy-gates] → rest
- [id: wg-at-session-start-run-bash-plugins-soleur] → core
- [id: wg-at-session-start-after-cleanup-merged] → core
- [id: wg-when-a-test-runner-crashes-segfault-oom] → rest
- [id: wg-when-tests-fail-and-are-confirmed-pre] → rest
- [id: wg-when-an-audit-identifies-pre-existing] → rest
- [id: wg-when-deferring-a-capability-create-a] → rest
- [id: wg-defer-only-after-inline-triage] → rest
- [id: wg-when-a-workflow-gap-causes-a-mistake-fix] → rest
- [id: wg-every-session-error-must-produce-either] → rest
- [id: wg-use-closes-n-in-pr-body-not-title-to] → rest
- [id: wg-after-merging-a-pr-that-adds-or-modifies] → rest
- [id: wg-plan-prescribed-skills-must-run-inline] → rest
- [id: wg-architecture-decision-is-a-plan-deliverable] → rest
- [id: wg-end-of-work-emit-resume-prompt] → rest
- [id: wg-block-pr-ready-on-undeferred-operator-steps] → core
- [id: wg-pm-class-followthrough-for-operator-dogfood] → rest
- [id: wg-record-recurring-vendor-expense-before-ready] → rest
- [id: wg-ui-feature-requires-pen-wireframe] → docs-only

## Code Quality

- [id: cq-write-failing-tests-before] → rest
- [id: cq-before-pushing-package-json-changes] → rest
- [id: cq-rule-ids-are-immutable] → docs-only
- [id: cq-agents-md-why-single-line] → docs-only
- [id: cq-agents-md-tier-gate] → docs-only
- [id: cq-nextjs-route-files-http-only-exports] → rest
- [id: cq-silent-fallback-must-mirror-to-sentry] → rest
- [id: cq-ref-removal-sweep-cleanup-closures] → rest
- [id: cq-union-widening-grep-three-patterns] → rest
- [id: cq-pg-security-definer-search-path-pin-pg-temp] → core
- [id: cq-eleventy-critical-css-screenshot-gate] → docs-only
- [id: cq-skill-description-budget-headroom] → docs-only
- [id: cq-test-fixtures-synthesized-only] → rest
- [id: cq-regex-unicode-separators-escape-only] → rest

## Review & Feedback

- [id: rf-after-merging-read-files-from-the-merged] → rest
- [id: rf-never-skip-qa-review-before-merging] → rest
- [id: rf-before-spawning-review-agents-push-the] → rest
- [id: rf-before-shipping-verify-1-review-comments] → rest
- [id: rf-when-a-reviewer-or-user-says-to-keep-a] → rest
- [id: rf-review-finding-default-fix-inline] → rest

## Passive Domain Routing

- [id: pdr-when-a-user-message-contains-a-clear] → core
- [id: pdr-do-not-route-on-trivial-messages-yes] → core

## Communication

- [id: cm-challenge-reasoning-instead-of] → core
- [id: cm-delegate-verbose-exploration-3-file] → core
- [id: cm-when-proposing-to-clear-context-or] → rest
