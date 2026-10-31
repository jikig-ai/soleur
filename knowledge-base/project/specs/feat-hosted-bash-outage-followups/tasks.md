# Tasks: hosted Bash outage follow-ups

Plan: knowledge-base/project/plans/2026-10-31-fix-hosted-bash-outage-followups-plan.md. All PRs use `Ref #10455`, never `Closes`.

## PR 1a — cross-tenant read channel (first)

- 1.1 Parameterize the hardcoded `prompt: "run it"` in `runBash` (G2) and add per-run synthesized needles for prompt and tool result
- 1.2 Run session A under the real vendored CLI in the production posture (`outer_wrap=false`, shared HOME); diff `$HOME`, `AGENT_SESSION_TMP_ROOT`, `/tmp` before and after A to list what it persisted
- 1.3 Session B single-pass search (`grep -rIlF -e ...`); print `NEEDLE_PATHS` per class
- 1.4 CONTROL arm per needle: needle visible at a named path on the host, else report `not_exercisable`
- 1.5 Confirm G2 executed in CI (not skipped); record wall time
- 1.6 File-tool arm: Read/Grep/Glob (absolute, `../`) and a symlink at `$HOME/.claude/history.jsonl` through `createSandboxHook`; check subagent (Task) and Notebook tools are matched
- 1.7 If red: stop rule (freeze dependents, CLO same day, fix behind a flag)
- 1.8 (CTO ruled 2026-10-31: documented residual, NOT relocated; only if a relocation trigger fires) If red: relocate CLI state with `CLAUDE_CONFIG_DIR` under `claudeTmpDir`; settle auth, `settings.json`, and session-resume decisions with evidence; thread the key through every `buildAgentEnv` consumer; add it to the `sdk_wrapper_shim_prodtuple` smoke tuple
- 1.9 Operator-authorized only: counts-only production-HOME census, then (separately) purge of already-persisted shared data (CLO sizes the window first)

## PR 1b — alert, coupling, records

- 2.1 `reportSilentFallback(null, ...)` at `agent-runner-sandbox-config.ts:566-572` with constant message, tag, `extra.code`
- 2.2 `sentry_alert "tenant_deny_root_missing"` (unused `frequency_minutes`) + `alert-reference.json` entry
- 2.3 Contract assertion in `test/agent-sandbox-tenant-deny.test.ts`, scoped to `reportSilentFallback` calls (skip the `log.info` at `:641`)
- 2.4 `scripts/tenant-deny-alert-discoverability.sh` (prints `TENANT_DENY_ALERT_PATH_OK`)
- 2.5 Coupling assertion: dirs from the helpers under matching stubbed env are inside `denyRead`; source scan of `env.<KEY>` reads
- 2.6 Each Guard Contract row shown red once
- 2.7 ADR-075 addendum, one breach-register row, one comment on #10455
- 2.8 Post-merge: Sentry apply succeeded, rule live

## PR 3 — plain-language Bash failure (before PR 2)

- 3.1 Locate the client row that renders the tool error
- 3.2 Plain sentence for classified sandbox-setup failures, non-transient copy, raw text behind details
- 3.3 Classify `prctl`/`seccomp` EPERM helper steps in the classifier and alert filter, real-shaped fixtures, alert AC per class

## PR 2 — promote the smoke to blocking (operator authorization to merge)

- 4.1 Flap review (numeric) and `memory.peak`/`oom_kill` gates
- 4.2 Remove `|| true` (`ci-deploy.sh:5477`); route `sdk_bash_smoke_failed` to `DEPLOY_ROLLBACK`; keep `smoke_infra_error` non-rolling-back
- 4.3 One rollback only; red rollback target freezes deploys and pages
- 4.4 `deploy_rolled_back_sdk_bash` alert before deleting `faithful_canary_sandbox_broken`
- 4.5 Staging forced-red run; audit lenient branches; ADR-079 addendum

## PR 4 — Slack wake path (investigation first)

- 5.1 Read ADR-260 and `var.betterstack_paid_tier`
- 5.2 Per sandbox alert: test page reaches Slack, or an issue with owner and date
- 5.3 PR only if a gap is found
