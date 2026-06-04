---
title: "Cron-clone ENOSPC froze the org-workspace KB reconcile (zero sync rows)"
date: 2026-06-03
severity: SEV-3
brand_survival_threshold: single-user incident
status: resolved
art_33_breach: false
art_34_notification: false
gdpr_rationale: "No personal-data exposure. The affected content is the user's own Knowledge Base (their own git repo), visible only to them; the failure mode is under-display (stale/frozen sync), not over-exposure. The reclaimed data is the platform's OWN ephemeral repo clones (jikig-ai/soleur), never user content. No Art. 33/34 clock."
related_prs: [4770, 4878, 4886, 4895, 4901]
related_issues: [4882]
sibling_pir: kb-sync-stale-no-manual-recovery-postmortem.md
root_cause_corrected: true
---

# Post-Incident Report: cron-clone ENOSPC froze the org-workspace KB reconcile

> ## ⚠️ ROOT-CAUSE CORRECTION (2026-06-03, after deeper no-SSH diagnosis)
>
> **The freeze was NOT caused by cron-clone ENOSPC.** That mechanism came from the
> initial incident report and was never confirmed — a no-SSH Sentry-issue read
> (`SENTRY_IAC_AUTH_TOKEN`) later showed **zero** `cron-workspace-low-disk` / ENOSPC
> warns in the window, and the reconcile's ACTUAL error (Sentry `WEB-PLATFORM-1V`,
> count 39):
>
> ```
> error: Your local changes to the following files would be overwritten by merge:
> 	.claude/settings.json
> Please commit your changes or stash them before you merge. Aborting
> ```
>
> The org-KB **mirror clone had an uncommitted local edit to `.claude/settings.json`**,
> so `git pull --ff-only` aborted on EVERY push (a **dirty-working-tree** failure,
> NOT ENOSPC and NOT the #4878 non-fast-forward class), and the reconcile froze.
>
> **Actual fix: PR #4901** — `classifyGitSyncError` now routes the dirty-tree abort
> to the same gated `reset --hard origin/<default>` self-heal (#4878), which discards
> the spurious mirror edit while the un-pushed-commit gate protects real session work.
>
> The cron-clone GC + isolation work below (#4886/#4895) is **real defense-in-depth**
> for a genuine leak class, but it did **not** cause or fix this freeze. The sections
> below are retained for that GC history; treat their "Root cause"/"Resolution" as the
> *hypothesis that motivated the GC*, superseded by this correction.
>
> **Process lesson:** don't trust an incident report's stated mechanism — pull the
> producer's actual error via the no-SSH toolchain first
> (`hr-no-dashboard-eyeball-pull-data-yourself`). See
> `knowledge-base/project/learnings/workflow-patterns/2026-06-03-no-ssh-prod-signal-toolchain-never-hand-the-operator-an-ssh-task.md`.

## Summary

The org-workspace Knowledge Base reconcile **silently stopped** at
**2026-06-02 07:46 UTC**: the last `users.kb_sync_history` `webhook_push` row was
written then, and **zero** rows of any kind since (confirmed against prod via
Doppler `DATABASE_URL_POOLER`). Unlike the sibling incident
([kb-sync-stale-no-manual-recovery](./kb-sync-stale-no-manual-recovery-postmortem.md),
PR #4878 — a diverged-clone git-logic failure that still wrote `ok:false` rows),
this freeze wrote **no row at all**: the reconcile's `git pull` hit **ENOSPC** and
the handler's error path could not even record the failure.

## Impact

- **Scope:** single-user (the org workspace whose KB the agent reads); any cron
  that clones the repo also degraded once the volume filled.
- **Effect:** pushes to the connected repo never reached the KB the agent reads,
  so the agent acted on weeks-old context **with no error surfaced** — the
  parent-incident class (#4706, the founder's own KB froze ~5 weeks). No data
  was lost (content is intact on `origin/main`); this was a freshness/freeze
  failure, not data loss or exposure.
- **Duration:** from 2026-06-02 07:46 until the disk was reclaimed.

## Timeline (UTC)

- **2026-05-?? (PR #4770)** — `ci-deploy.sh` wires
  `CRON_WORKSPACE_ROOT=/workspaces` to move the ~100 MB `--depth=1` cron repo
  clones off the 256 MB `/tmp` tmpfs (#4684/#4689). But `/workspaces` is the
  container view of `/mnt/data/workspaces` — the **same 20 GB Hetzner volume**
  that holds the persistent UUID-named KB workspace clones.
- **2026-06-02 07:46** — last `webhook_push` `kb_sync_history` row written; the
  volume crosses the ENOSPC threshold around this point.
- **2026-06-02 07:46 → 2026-06-03** — every reconcile `git pull` ENOSPCs; zero
  rows written; the KB freezes silently.
- **2026-06-03** — freeze detected via a prod `kb_sync_history` query (0 rows
  since 07:46); root cause traced to leaked `soleur-*` cron clones on the shared
  volume; fix authored (PR #4886).

## Root cause

Every cron that clones the repo does
`mkdtemp(join(resolveCronWorkspaceRoot(), "soleur-${cronName}-"))`. Cleanup is a
caller-side `finally { rm }` — which **OOM / ENOSPC / SIGKILL bypass by
definition**. Leaked `soleur-*` clones (~100 MB each) accumulated on the shared
20 GB `hcloud_volume.workspaces` until it filled. The reconcile reads/writes the
persistent UUID workspace dirs on that **same** volume, so once it was full the
reconcile's `git pull` ENOSPC'd — and because the failure happened before the
handler could write, **no `kb_sync_history` row (not even `ok:false`) was
recorded**, making the freeze invisible to the per-attempt mirror that the
sibling incident relied on.

This is a **third, distinct layer** from the sibling PIR's two (diverged-clone
git-logic + missing UI affordance, fixed by #4878). #4878 is correct and stays;
it could not have prevented this freeze, which is a disk-capacity failure, not a
git-state failure.

## Detection

Not alerted — found by querying prod `users.kb_sync_history` directly (0 rows
since 07:46). The ENOSPC error path could not write a row, so neither the
`ok:false` mirror nor any age-based DB signal fired. This is the detection gap
the resolution closes with an **out-of-band** Sentry signal that does not depend
on a DB write succeeding.

## Resolution (PR #4886)

1. **`cron-workspace-gc` Inngest function** — a scheduled (6-hourly) in-process
   cron that statfs-reports the cron-clone root to Sentry, sweeps aged
   `soleur-*` dirs (prefix + `maxdepth 1` + age>1h, per-dir fail-soft `rm`),
   statfs again, and posts a Sentry Crons heartbeat. This is the disk-reclaim
   lever that un-wedges the volume **with zero SSH**, and it is fireable on
   demand via `/soleur:trigger-cron` (`cron/workspace-gc.manual-trigger`).
2. **Isolation** — `CRON_WORKSPACE_ROOT=/workspaces/.cron` (both docker-run
   sites) namespaces cron clones into a dedicated subdir, one level below the
   persistent UUID workspace dirs, so a future leak cannot starve the path the
   reconcile reads.
3. **Out-of-band alerting** — the `scheduled-workspace-gc` Sentry Crons monitor
   (`failure_issue_threshold=1`) pages on a missed check-in (GC stopped), and a
   `warnSilentFallback` fires when free space is still below floor after a full
   sweep — neither depends on the wedged DB write path that hid this freeze.

The GC is the load-bearing safeguard: isolation alone cannot stop a leak from
filling a shared 20 GB volume.

## Resolution complication — the isolation deadlocked its own deploy (follow-up fix)

PR #4886's **isolation** part (2, above) backfired: it added
`sudo mkdir -p /mnt/data/workspaces/.cron` to `ci-deploy.sh`'s critical path. On
the **already-full** volume (the exact incident state), that `mkdir` ENOSPC-failed
under `set -e` → `ci-deploy.sh` exited `reason=unhandled` → the **Web Platform
Release v0.102.0 deploy FAILED**, so the container carrying the GC never shipped —
a deadlock where the fix could not deploy because the thing it fixes was still
broken. It also broke *every subsequent merge's* deploy. Worse, with isolation the
GC swept `/workspaces/.cron` while the existing leak lives at `/workspaces/soleur-*`
(the pre-isolation path), so firing the GC would have reclaimed nothing.

The follow-up fix **reverts the isolation**: remove the `mkdir`/`chown`, point
`CRON_WORKSPACE_ROOT` back to `/workspaces`. The GC now sweeps `/workspaces`
directly — unblocking the deploy AND making the GC reclaim the *actual* leak. The
`soleur-` prefix guard (UUID dirs are 36-char hex, never `soleur-*`) is the
load-bearing protection, not the subdir. Dedicated-volume isolation is deferred to
#4891. **Lesson:** never put a volume-writing command (mkdir/touch/cp) in a deploy
critical path under `set -e` when the volume may be full — the deploy that delivers
the fix is exactly the one that cannot afford to fail on the broken resource.

## Follow-ups

- [ ] Stale/diverged-clone divergence alert (content drift, distinct from
      capacity) — owned by **#4882** (open). This PIR's reclaim is capacity-only.
- [ ] Evaluate a dedicated `hcloud_volume` for cron clones (true capacity
      isolation vs the subdir MVP) — re-eval if the GC `freedMb`/`freeMbAfter`
      Sentry trend shows the shared volume still pressured after 2 weeks. → file
      as a tracking issue.

## Lessons

- A cleanup that lives in a caller-side `finally` is bypassed by OOM/ENOSPC/
  SIGKILL — an external sweeper is the only thing that survives a killed clone.
- Sharing one volume between ephemeral churn and persistent user data couples
  their failure domains: a leak in the cheap thing wedges the precious thing.
- A failure whose error path needs the very resource that failed (here: a DB
  write blocked by the disk that ENOSPC'd) is invisible to any signal that
  depends on that resource. The durable signal must be **out-of-band** (a Sentry
  heartbeat/event), not an in-band DB row.
- Moving ephemeral clones onto a roomier volume (#4770) fixed one ENOSPC (/tmp)
  by creating another (the shared persistent volume) — "more space" is not
  "isolated space."
