---
title: Sentry fallback-rate alarm — pre-bootstrap emitter, issue-alert notify targets, and shared-message grouping
date: 2026-07-09
category: integration-issues
module: apps/web-platform/infra/sentry, apps/web-platform/infra/cloud-init.yml
issue: 6278
pr: 6281
tags: [sentry, observability, terraform, cloud-init, zot, adr-096]
---

# Learning: provisioning a Sentry fallback-rate alarm (#6278)

Three non-obvious constraints surfaced while provisioning ADR-096's "Loud, no-SSH signal"
fallback-rate alarm. Each is generalizable to any future Sentry alarm + boot-emit work.

## Problem

Wire a `>3/1h` Sentry alarm that pages on zot→GHCR mirror fallbacks across four runtime
signals (two `ci-deploy.sh` emits + two cloud-init fresh-boot emits), plus add a boot
breadcrumb for the app-image fresh-boot fallback path.

## Key Insights

### 1. `sentry_metric_alert` is NOT autonomously deployable in a TF root with no resolvable notify target

The plan's primary design was a `sentry_metric_alert` (true cross-signal aggregate — the
correct sensitivity). But metric-alert `trigger.action` requires a **concrete numeric
`target_identifier`** (team-id or member-id) — there is **no** `IssueOwners → ActiveMembers`
symbolic fallthrough for metric alerts (that construct exists ONLY on
`sentry_issue_alert.actions_v2.notify_email`). This Sentry TF root has zero resolvable numeric
targets (no `sentry_team` data source, no `owner=`), and the token to mint one
(`SENTRY_IAC_AUTH_TOKEN`) is CI-only (ADR-031, not in Doppler). So a metric alert could not be
resolved/verified in an autonomous session → risk of shipping a safety control that **pages
nobody**. The CTO agent ruled to ship a `sentry_issue_alert` + `event_frequency` (symbolic
notify, config-verifiable), accepting the per-issue-group sensitivity, with a filed follow-up
(#6285) to upgrade once a numeric target exists (first non-founder Sentry seat).

**Generalizable rule:** before choosing `sentry_metric_alert` over `sentry_issue_alert`, check
whether the TF root has a resolvable numeric notify target. If not, the metric alert is not
autonomously deployable and the issue-alert (symbolic `IssueOwners→ActiveMembers`) is the
correct default. Verifiability of the notify PATH dominates aggregate sensitivity for a safety
control.

### 2. A cloud-init boot breadcrumb's emitter depends on WHERE in the boot sequence it fires

`cloud-init.yml` runcmd concatenates ALL `- |` blocks into ONE `/bin/sh` process (proven by
the top-armed `on_err` trap + `STAGE=` variable persisting across blocks). Two emitters exist:

- **Baked `_emit <msg> <stage> <level>`** — defined at the TOP of runcmd (~:301), available
  everywhere below, POSTs to Sentry via the baked `${sentry_dsn}`.
- **`/usr/local/bin/soleur-boot-emit <stage> <level>`** — authored by `soleur-host-bootstrap.sh`,
  which only runs LATER in runcmd (~:520).

So a call site's correct emitter is position-dependent: the **app-image pull (~:496) runs
BEFORE host-bootstrap** → must use `_emit`; the **inngest pull (~:650) runs after** → uses
`soleur-boot-emit`. The plan prescribed `soleur-boot-emit` at :496 "symmetric with the inngest
path" — that would have been `command not found` (silent no-op, since runcmd has no `set -e`).
Both emitters set a `stage` tag, so the alarm filter (`stage:app_ghcr_fallback`) matches either.

**Generalizable rule:** before adding a `soleur-boot-emit` call in cloud-init, confirm the call
site is AFTER `soleur-host-bootstrap.sh` runs (grep the invocation line number). Pre-bootstrap
sites use the baked `_emit`.

### 3. Sentry issue-alert `event_frequency` counts the whole issue-GROUP — a shared static message makes it over-loud

`sentry_issue_alert` `event_frequency` (`count > N in interval`) counts events in the Sentry
**issue-group**, and Sentry groups message-type events by their **message string**. `filters_v2`
(`tagged_event`) only gate whether the triggering event evaluates the rule — they do NOT scope
the count. Consequence: a signal whose emitter uses a **shared static message** shares one group
with unrelated events, so its `event_frequency` is effectively always hot → it pages on the
FIRST occurrence, not at a sustained rate.

Concretely: `soleur-boot-emit` hard-codes `message="soleur-cloud-init boot stage"` for every
stage (stage is a tag), so `inngest_ghcr_fallback` shares a group with all routine boot stages
→ over-loud (safe direction, but not "sustained"). The other three signals use per-content
messages (`registry_pull_event` includes registry+image+tag; `zot_gate_degraded_event` includes
the reason; the new `_emit` uses a dedicated message), so their thresholds are meaningful.

**Generalizable rule:** for a per-rate Sentry issue-alert, each watched signal needs its OWN
message-group (a distinct message or an explicit `fingerprint`). A signal emitted via a shared
static message will page on first occurrence — document it or give it a dedicated message.

## Session Errors

1. **Draft-PR push rejected ("reference already exists")** — stale empty remote branch from a prior aborted run. Recovery: verified init-commit-only + no live PR, created draft PR directly. **Prevention:** `worktree-manager.sh create` auto-heals stale EMPTY branches; a `draft-pr` push conflict on a branch with only the init commit is benign — verify `gh pr list --head` + `git rev-list origin/main..origin/<branch>` before treating it as a collision.
2. **`terraform providers schema`/`validate` needs S3 backend-init in the real dir** — Recovery: scratch-dir `filesystem_mirror` pointed at the cached provider binary + `terraform init -backend=false`. **Prevention:** for provider-schema/validate work without backend creds, always use a scratch dir + filesystem_mirror (never init the real backend-bound dir).
3. **Plan's Phase-1b emitter was placement-wrong** (`soleur-boot-emit` pre-bootstrap → command-not-found). Recovery: traced boot sequence, used `_emit`. **Prevention:** Insight #2 above; a plan prescribing an emitter is authoritative for INTENT (emit stage X), never for the exact binary at a position-dependent call site.
4. **Branch decision inverted from plan primary** — routed the fork to the CTO agent (not the operator; not decided unilaterally). **Prevention:** working as designed (architectural-fork gate).
5. **Vacuous op-contract assertions** (review-caught) — bare `toContain("ghcr-fallback")` matched comments. Recovery: pinned emit-CALL forms; verified non-vacuous via simulated-rename RED. **Prevention:** recurrence of `2026-06-17-grep-assertion-over-script-body-false-matches-own-comments.md` — a source-grep contract assertion MUST anchor on the emit/call construct, never a bare literal the file also names in a comment.
6. **inngest signal over-loud** (review-caught) — Insight #3. Recovery: disclosed in the SENSITIVITY NOTE. **Prevention:** Insight #3 above.
7. **`git stash list` blocked by guardrails hook** (read-only). Recovery: used `git log`/`diff`. **Prevention:** known — never invoke any `git stash` form in a worktree; use `git show <commit>:<path>`.
8. **Behind-origin/main (ADR-105 appeared deleted)** — sibling #6282 merged mid-session. Recovery: staged only my files, merged origin/main. **Prevention:** known bare-repo stale-base; stage explicit file lists (never `git add -A`), diff-verify before commit.

## Tags
category: integration-issues
module: sentry-observability, cloud-init
