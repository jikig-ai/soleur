# Learning: report at error level on the FINAL recoverability outcome, not the first failure

## Problem

Production Sentry error `9ccf1d861b3b4c8595772bd116b931e8` (web-platform, prod,
`level=error`, `feature=pino-mirror`) paged the operator from the
`workspace-reconcile-on-push` Inngest function on **every push**:

```
Error: Command failed: git -c credential.helper= pull --ff-only
error: Your local changes to the following files would be overwritten by merge:
    knowledge-base/engineering/architecture/diagrams/model.likec4.json
fatal: Cannot fast-forward your working tree. Aborting
```

The platform **already self-heals** this exact condition (`classifyGitSyncError`
routes "would be overwritten by merge" → `non_fast_forward`, and
`selfHealNonFastForward` runs a gated `reset --hard origin/<default>` when the
clone holds zero un-pushed commits, per PR #4901). So the workspace recovered —
yet the operator got a high-priority alert email anyway.

## Root cause

`syncWorkspace` (`apps/web-platform/server/workspace-sync.ts`) emitted
`log.error({ err: syncError, … })` **and** `reportSilentFallback(…)`
**unconditionally on the first `git pull --ff-only` failure, before the self-heal
ran**. The pino `log.error` carries an `err` key, so `server/logger.ts:71-75`
mirrors it to Sentry via `Sentry.captureException(err, { tags: { feature:
"pino-mirror" } })` at `level=error`. Because the report fired *before* recovery,
a benign, self-healed condition paged on every push.

The dirty file's source: the new Layer-2 LikeC4 re-render (`c4-writer.ts` →
`c4-render.ts`, shipped the same day in #4963/#4965/#4967) writes the regenerated
`model.likec4.json` **onto the tracked working-tree path** (validated temp →
`rename` onto `<diagramsDir>/model.likec4.json`), which collides with the
subsequent `pull --ff-only` (and a failed `rerenderAndCommit` strands the dirty
file into the *next* push reconcile). Source-hardening deferred to **#4976** —
after the de-noise fix the churn is benign and silent.

## Solution

Split the `syncWorkspace` catch **by recoverability**:

- **Self-healable (`non_fast_forward`, incl. dirty-tree):** log only a pino
  `info` breadcrumb (Better Stack drain — below the WARN+ Sentry-mirror
  threshold, no `err` key) and delegate to `selfHealNonFastForward`, which
  already owns Sentry escalation: `op:self-heal-aborted-dirty` /
  `op:self-heal-failed` on a real (un-recovered) freeze, `op:self-heal-reset`
  warn on recovery.
- **Non-self-healable (`sync_failed`):** keep the error-level
  `log.error({ err })` + `reportSilentFallback(op:workspace-sync-${op})`.

The reconcile caller's aggregate `op:sync` mirror already only fires when
`syncResult.ok === false`, so a recovered self-heal (`{ok:true, recovered:true}`)
is not double-reported. Two regression tests assert a self-healed dirty-tree /
non-FF abort emits NO error mirror (no `log.error`, no `reportSilentFallback`) —
only the info breadcrumb + the `op:self-heal-reset` warn. Reviewed sound by
`silent-failure-hunter` + `observability-coverage-reviewer` (every un-recovered
failure still surfaces to Sentry without SSH).

## Key Insight

**When a failure has a recovery attempt downstream, gate error-level reporting
on the FINAL recoverability outcome — not the first failure.** An
unconditional error log/mirror placed *before* a self-heal turns benign,
recovered churn into a per-occurrence page. Let the recovery routine own
escalation: it knows whether the outcome was recovery (info/warn) or a genuine
freeze (error). The corollary is the prior reconcile-noise rule
(`plan-workspace-reconcile-push-noise.md`): **"benign + self-healing ⇒ pino
breadcrumb, not a Sentry error issue."** That rule must be applied at *every*
error-emitting site, not just the one where it was first learned — here it
resurfaced at a sibling site (`syncWorkspace`) the moment a new dirty-tree
source (the c4 re-render) started exercising it. `cq-silent-fallback-must-mirror-
to-sentry` is NOT violated: the demoted branch is a *transition into a recovery*,
not a terminal silent fallback; the genuine-failure branches all still mirror,
and the demoted line carries no `err` key (the correct "breadcrumb, not swallowed
error" signal).

Generalizable check for any `try { risky() } catch { report(); recover() }`: if
`recover()` can succeed, `report()` at error level is premature — move it into
the failure branches of `recover()`.

## Session Errors

1. **Planning subagent API `529 Overloaded` (×3).** The `general-purpose`
   plan+deepen subagent returned `529 Overloaded` three times (first after 24
   tool calls, then twice with 0). **Recovery:** ran the planning + the small,
   well-scoped implementation inline in the parent (the one-shot documented
   fallback for subagent failure); subagents recovered by the review phase (both
   reviewers ran fine). **Prevention:** already covered — one-shot's Steps 1-2
   fallback says to run plan/deepen inline when the subagent fails; transient
   server-side overload needs no workflow change. One-off.
2. **`gh issue create` denied — missing `--milestone`.** A PreToolUse hook
   blocked the deferred follow-up issue. **Recovery:** re-ran with
   `--milestone "Post-MVP / Later"`. **Prevention:** already hook-enforced (the
   hook printed the exact remediation). No change needed. Recurring but covered.

## Tags
category: runtime-errors
module: apps/web-platform/server/workspace-sync.ts
related_prs: [4878, 4901, 4963, 4965, 4967]
related_issues: [4976]
related_learnings:
  - plan-workspace-reconcile-push-noise.md
  - 2026-06-03-self-heal-reset-must-gate-on-actual-repo-state-not-assumed-mirror.md
