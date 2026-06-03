---
title: "KB sync stale + no manual recovery affordance"
date: 2026-06-03
severity: SEV-3
brand_survival_threshold: single-user incident
status: resolved
art_33_breach: false
art_34_notification: false
gdpr_rationale: "No personal-data exposure. The affected content is the user's own Knowledge Base (their own repo), visible only to them; the failure mode is under-display (a missing file), not over-exposure. No Art. 33/34 clock."
related_prs: [4810, 4846, 4878]
related_issues: [2244]
---

# Post-Incident Report: KB sync stale + no manual recovery affordance

## Summary

A workspace Owner reported (2026-06-03, via screenshot) that their platform
Knowledge Base view was missing a post-mortem
(`chat-rls-workspace-id-outage-postmortem.md`) that had been merged to
`origin/main` the previous day (PR #4846, 2026-06-02 21:10 UTC). The file was
present and pushed on `origin/main` but absent from the platform server's
workspace clone, and the user had **no in-product way to trigger a re-sync**.

## Impact

- **Scope:** single-user (the reporting Owner; potentially any workspace whose
  clone diverged from `origin/<default>`).
- **Effect:** the KB tree silently omitted a merged document; the Owner's
  reasonable inference is "the platform drops my data." No data was lost
  (the file is intact on `origin/main`); this was an under-display /
  freshness failure, not data loss or exposure.
- **Duration:** the stale state persisted from the failed/absent reconcile
  until manual recovery; the missing manual affordance meant the user could
  not self-recover at all on a fresh KB landing.

## Timeline (UTC)

- **2026-06-02 19:15** — PR #4810 (single nav rail drill-in) merges; the only
  manual "Sync now" affordance (`KbSyncStatus`) is left mounted **only** inside
  `KbContentHeader` (file-open route). The rail + empty-state landing lose the
  self-recovery valve.
- **2026-06-02 21:10** — PR #4846 merges the chat-RLS PIR to `origin/main`.
- **2026-06-03 ~11:06** — Owner reports the PIR missing from the KB view.
- **2026-06-03** — investigation confirms the file is on `origin/main` but
  absent from the server clone (KB tree is a fresh FS walk — no view cache),
  i.e. a sync/reconcile failure compounded by the missing manual affordance.
- **2026-06-03** — fix authored (PR #4878).

## Root cause (two layers)

1. **UI regression (PR #4810).** The manual sync affordance was reachable only
   after opening a file. On a fresh/empty KB landing there was no way to
   trigger a re-sync — the self-recovery path needed to recover from exactly
   this class of incident was removed.
2. **Silent, mis-classified server reconcile.** `syncWorkspace`'s
   `git pull --ff-only` fails on a diverged (non-fast-forward) clone but
   labeled every failure `sync_failed` and never recovered. The
   `ERROR_CLASS_NON_FAST_FORWARD` constant existed and was fixtured in tests
   but had **no producer** — the diverged-clone path was unreachable, so a
   diverged clone stayed stale indefinitely.

## Detection

User-reported (screenshot), not alerted. The reconcile failure DID record an
`ok:false` row to `kb_sync_history` + mirror to Sentry, but mis-classified as
`sync_failed` and with no recovery; there was no alert specific to "clone
diverged / KB stale beyond N hours."

## Resolution (PR #4878)

- **Fix A:** mounted the existing `KbSyncStatus` in the always-mounted
  `KbSidebarShell` footer, rendered in all rail branches incl. the empty-tree
  landing — restoring the self-recovery valve without a file open.
- **Fix B:** `syncWorkspace` now classifies the git failure (`syncWorkspace`
  is the first producer of `non_fast_forward`), propagates the real
  `error_class` to both `kb_sync_history` write sites, and performs a **gated,
  observable self-heal**: on `non_fast_forward` it resets to
  `origin/<default>` **only** when the clone holds zero un-pushed local commits
  (`git rev-list --count @{u}..HEAD == 0`; fail-safe on parse failure),
  otherwise it aborts without destroying un-pushed agent-session work and pages
  via `reportSilentFallback`.
- Folded in the sibling upload-path inline-pull bug (Closes #2244).

## Follow-ups

- [ ] Alerting gap: add a liveness/age alert for "workspace clone diverged
      from origin OR KB stale > N hours" so this class is detected before a
      user reports it (currently only `ok:false`-per-attempt mirrors). → file
      as its own issue.
- [ ] AC-P2: post-deploy, confirm a real `non_fast_forward` now records the
      correct `error_class` via Sentry/observability (not a dashboard eyeball).
- [ ] AC-P1: trigger a re-sync for the affected Owner's workspace and confirm
      the PIR renders in the KB tree.

## Lessons

- A self-recovery affordance that lives on only one route is one refactor away
  from disappearing; affordances for recovery belong on always-mounted chrome.
- A defined-but-never-produced error class is a latent bug: grep for a
  constant's assignment sites, not just its declaration.
- See `knowledge-base/project/learnings/2026-06-03-self-heal-reset-must-gate-on-actual-repo-state-not-assumed-mirror.md`.
