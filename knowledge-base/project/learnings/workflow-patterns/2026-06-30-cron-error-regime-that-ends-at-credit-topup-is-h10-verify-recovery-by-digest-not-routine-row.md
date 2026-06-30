# Learning: a cron `error` regime that ends exactly at a credit top-up IS H10 — verify recovery by the downstream artifact (digest issue), not the routine_runs terminal row

category: workflow-patterns
module: inngest-cron-substrate / observability
date: 2026-06-30
refs: #5732, #5728, #5674; runbook cloud-scheduled-tasks.md H10/H11; learning 2026-06-30-verify-the-fixed-code-path-actually-executes-on-the-affected-surface.md; learning workflow-patterns/2026-06-29-cron-failing-since-alert-reconcile-against-checkin-layer-not-digest.md

## Problem

`#5732` filed `cron-community-monitor` as fast-failing daily: a `?status=error`
check-in 2026-06-22→06-29 with a handler wall-clock of ~300 ms — far too fast for
the ~50-min inline `claude-eval`, so "the digest is likely not being generated."
The deepened plan built a strong, concrete leading hypothesis (**H-B**: a clone
fast-fail because `codeload.github.com` — where `git clone --depth=1` redirects —
is absent from `cron-egress-allowlist.txt`, kernel-dropped by the nftables
default-drop → ~300 ms), plus **H-A** (ENOSPC from orphaned workspaces). Both are
plausible *code* fixes. The plan also carried **H-C** (Anthropic credit, said to be
already resolved by the operator's 06-29 top-up).

The temptation was to ship H-B (add codeload to the allowlist) — it explains the
300 ms precisely on paper.

## Solution / Key Insight

**Investigation-first (Phase 0 hard gate) refuted both code hypotheses with one
live fire.** A single allowlisted manual trigger (`cron/community-monitor.manual-trigger`,
derived from `EXPECTED_CRON_FUNCTIONS` — already allowlisted; the plan's "not in
trigger-cron" note was wrong) produced the decisive evidence:

- The post-top-up clone **succeeded** and logged `claude-eval spawned` → **H-B
  refuted** (codeload not dropped; the allowlist gap is *latent*, resolving inside
  the `github.com` CIDR set today). No `op:setup-ephemeral-workspace` Sentry
  exception existed (queried by the **`op:` TAG**, not free text — the issue title
  would be the clone stderr, so free-text is a guaranteed false-negative).
- `cron-workspace-gc` ran a clean 6 h cadence with zero gaps → **H-A refuted** (no
  8-day disk fill).
- The fire produced **real digest issues** (`#5737`, `#5740`) → recovery confirmed.

So the `error` regime that ended the moment credit was topped up **was H10
(credit)** — exactly what H-C predicted. No code fix was warranted. Shipping H-B
would have been a wrong-layer fix for a cause that had already self-resolved (the
headline risk in `2026-06-30-verify-the-fixed-code-path...`).

**Three reusable rules:**

1. **A recurring cron `error`/fast-fail regime whose onset/offset lines up with a
   credit event IS H10 until a live fire proves otherwise.** A concrete, well-cited
   egress/disk hypothesis is still a *hypothesis* — fire one post-remediation run
   and read whether the clone succeeded before touching the allowlist or the GC.

2. **Verify cron recovery by the DOWNSTREAM ARTIFACT (the `[Scheduled] …` digest
   issue), not the `routine_runs` terminal row.** On the recovered fire the digest
   issues landed within minutes, but `routine_runs` still showed no terminal row
   and the check-in was `missed` — because terminal-row + heartbeat *delivery* is a
   separate concern (the **#5728** class, fix `b1c560dad`). Reading "no terminal
   row" as "still broken" misdiagnoses a recovered cron. The digest issue is the
   ground truth for "did the eval run and produce output."

3. **One symptom can have two stacked defects in different layers.** #5732
   (fast-fail / generation) and #5728 (heartbeat delivery / `missed`) coexisted on
   the same monitor; resolving the generation layer (credit) surfaced the residual
   delivery layer. Keep them as distinct issues — do not absorb the residual into
   the resolved one.

## Why it matters

Phase 0's read-only pulls cost minutes; an H-B PR would have shipped an egress
change + ADR-052 amendment for a non-reproduced cause, and the latent codeload gap
would have looked "fixed" while the real recovery driver (credit) went unrecorded.
The investigation IS the deliverable when the root cause is external — record the
verdict and close, do not manufacture a code fix.
