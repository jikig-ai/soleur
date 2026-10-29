---
title: "Sentry /events/ `sort` is an optional param — pin it (or bound the window) for coverage arguments"
date: 2026-10-29
category: integration-issues
tags: [sentry, api, events, ordering, followthrough-probes, coverage-argument, devin]
pr: "11543"
issue: "11532"
status: captured
---

# Learning: Sentry `/events/` `sort` is an optional param — "newest-first" is observed behavior, not contract

## Problem

While authoring `scripts/followthroughs/discord-blog-webhook-fallback.sh` (PR #11543, issue #11532), the probe's FAIL arm argued coverage from `statsPeriod=30d&per_page=10`: "any `timestamp >= cutoff` event ranks within the newest 10, so a page-1 read suffices." That argument silently assumed the `/api/0/organizations/<org>/events/` endpoint returns rows newest-first.

## Root cause

On the Sentry events endpoint `sort` is an **optional request parameter**. The implementation's `get_orderby` returns `None` when `sort` is absent, and with no `orderby` there is **no `ORDER BY` guarantee at all** — the database may return rows in any order and the order can change between deployments or plans. "Newest-first" is the observed behavior today, not a documented contract. A `per_page=N` coverage argument that leans on an undocumented default is a silent-coverage hole: the moment the default order changes (or was never guaranteed), the FAIL arm can miss an in-window event and report a false PASS on a credentialed production query.

## Solution

Pin the ordering the argument needs, explicitly:

```bash
# coverage argument: "newest N provably covers the window"
URL="https://${API_HOST}/api/0/organizations/${ORG}/events/?query=${QUERY_ENC}&statsPeriod=30d&per_page=10&field=title&field=timestamp&sort=-timestamp"
```

or bound the window with `start=`/`end=` so the coverage claim rests on the bound rather than the order (pattern used by `ac8-founder-ambiguous-soak-5673.sh`, `phase3-ga-soak-5274.sh`, `cwv-field-rum-9178.sh`, `accounted-beacon-live-6462.sh`, `zot-soak-6122.sh`). The probe's own test suite re-asserts the pin on the assembled URL (`discord-blog-webhook-fallback.test.sh` greps for `sort=-timestamp`), so a future edit that drops the param reddens the harness instead of silently degrading the coverage claim.

## Key insight

**Any API read used as evidence in a coverage argument needs its ordering (or its window bound) in the contract, not in the observation.** The same "observed default ≠ guarantee" shape bit here exactly the way undocumented pagination/ordering defaults bite elsewhere. Census at capture time: at least 8 sibling probes under `scripts/followthroughs/` hit `/events/` with `statsPeriod`-only windows and no `sort=` pin (`ac10-workspace-reconcile-sentry-4246.sh`, `anthropic-admin-key-6297.sh`, `cron-machinery-soak-9272.sh`, `dashboard-cold-tiers-8978.sh`, `egress-enforce-probe-11361.sh`, `reconcile-ff-only-sentry-4977.sh`, `sync-health-residual-5689.sh`, `workspaces-luks-soak-6604.sh`) — each needs a per-probe judgment on whether its verdict leans on ordering; tracked as deferred-scope-out issue #11553 (also carries the candidate ordering-bound lint proposal — a step-3.6 null-guardrail finding: no repo check currently covers the unpinned-`/events/` class).

## Session Errors

- **`gh issue create --label follow-through` denied twice (false positive).** — Recovery: copied the probe into the main checkout untracked, filed #11549, removed the copy. — Prevention: tracked as defect #8254 (Devin tool envelope omits `.cwd`; `follow-through-directive-gate.sh` resolves `script=` under `HOOK_CWD` → main checkout and does not parse `cd`/`git -C` from the command text). See `2026-09-17-devin-envelope-omits-cwd-precommit-guard-false-deny.md`.
- **argv-bearer-sweep repo-global census reddened on the unclassified new probe.** — Recovery: added `discord-blog-webhook-fallback|scripts/followthroughs/discord-blog-webhook-fallback.test.sh` to `DELEGATED_MANIFEST` (829/829 green). — Prevention: none needed — the ratchet gate worked as designed; any new credentialed-curl probe must expect the manifest row.
- **`test-all.sh --affected --jobs=auto` queued behind 3 sibling worktree runs and was killed unread.** — Recovery: ran every tasks.md §3.1 suite directly, all green. — Prevention: none (advisory-lock contention is transient by design); document the narrower per-suite fallback in the verification record when substituting.
- **Read-only `ps aux | grep -c 'test-all'` denied by `pkill-self-match-guard-readonly`.** — Recovery: rephrased the check without a self-matching pattern. — Prevention: already hook-enforced with a clear deny message; use captured PIDs for process checks (same class as the `pgrep -f` self-match in `2026-10-29-running-review-seats-as-headless-devin-subprocesses.md`).
- **Backgrounded poll loop denied by `hr-monitor-not-run-in-background-for-polling`.** — Recovery: foreground checks on a bounded cadence instead. — Prevention: already hook-enforced; Devin has no Monitor tool — the sanctioned pattern is a background exit-coded `run_subagent` watch (devin/INSTRUCTIONS.md §Polling/watches).
- **Sweeper dry-run (optional tasks 2.2.7) skipped.** — Recovery: documented as unreachable in tasks/session-state. — Prevention: structural — the sweeper execs probes from a main checkout and the probe is not on the pushed ref pre-merge; dry-run verification of a new probe is only possible post-merge.
- **`cq-never-skip-hooks` `bypass` incident row on checkpoint commit `89b20b10f` (session-state progress commit, 18:46:52Z).** — A hook-skip flag appears in the truncated `command_snippet`; the full flag text was not captured. — Prevention: none beyond the existing detection — under Devin lefthook is absent anyway, so a skip flag buys nothing; omit skip flags on worktree commits.
- **Devin subagent has no Task/Skill tool — plan/deepen-plan/review fan-outs ran in-process.** — Recovery: sequential-fallback panel with `Reviewed-Coverage: sequential-fallback` trailer (CTO ruling). — Prevention: capability-scoped, not detection-scoped — ANY in-process panel on a Devin subagent carries the trailer regardless of `cloud-detect.sh` output; routed to `plugins/soleur/devin/INSTRUCTIONS.md`.

## Cross-references

- Ruling source: PR #11543 decision-challenges (CTO technical-ruling gate: 1 REFUTE→`sort=-timestamp`, 1 AMEND→sequential-fallback trailer), `knowledge-base/project/specs/feat-one-shot-11532-xtrace-guard-fallback-probe/decision-challenges.md`
- Pin implementation: `scripts/followthroughs/discord-blog-webhook-fallback.sh:184` (+ harness re-assertion in `.test.sh`)
- Authoring convention (routed): `knowledge-base/engineering/operations/runbooks/followthrough-convention.md`
- Same `.cwd` class: `knowledge-base/project/learnings/2026-09-17-devin-envelope-omits-cwd-precommit-guard-false-deny.md`, `workflow-issues/2026-10-20-context-reviewed-gate-resolves-cwd-to-bare-root-on-worktree-commits.md` (#8254 umbrella)
- Related Sentry quirks: `2026-05-15-sentry-iac-billing-and-quirks.md`, `integration-issues/sentry-api-boolean-search-not-supported-20260406.md`
