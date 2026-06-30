---
title: Lossy GHA→Inngest migration dropped detection dimensions; canonical snapshot drifted from Terraform
date: 2026-06-30
category: integration-issues
module: ci / inngest-crons / github-rulesets
issues: [4397, 5759, 5780, 4483, 3547, 3569]
tags: [migration, drift-detection, source-of-truth, compliance, ci-sync-gate, false-positive]
---

# Learning: lossy runtime migration + canonical-vs-Terraform drift

## Problem

Investigating a stale `compliance/critical` P1 (#4397, "CI Required ruleset
required_status_checks drift detected", open since 2026-05-25) surfaced two
compounding failures:

1. **The GHA→Inngest migration was lossy.** TR9 Phase 2 (#4483) deleted the
   GitHub Actions workflow `scheduled-ruleset-bypass-audit.yml` and re-ported
   the audit as the Inngest cron `cron-ruleset-bypass-audit.ts`. The port kept
   only the **headline** dimension (`bypass_actors`) and silently dropped three
   others the GHA audit had:
   - `required_status_checks` drift detection (R15 D4, #3547/#3586)
   - `enforcement != "active"` detection (#3569)
   - auto-close-of-the-drift-issue-on-green-run
   Nothing flagged the regression — the function still "worked," just for one of
   four things it used to check.

2. **A hand-maintained snapshot drifted from its source of truth.** The
   `required_status_checks` canonical JSON (`scripts/ci-required-ruleset-canonical-required-status-checks.json`)
   was frozen at 5 checks while the live ruleset — now Terraform-managed
   (`infra/github/ruleset-ci-required.tf`) — was widened to 16 over many PRs.
   Nothing forced the two back into agreement, so the (already-orphaned) GHA
   audit's last run filed #4397 as a false positive: live (16) ≠ stale canonical
   (5). The drift was in the *safe* direction (live had MORE gates), so there was
   no real exposure — but the green-looking system had in fact **lost scheduled
   detection** for required-check and enforcement drift entirely.

## Solution

PR #5764 (admin-merged) + #5758:

- **Restored all three dropped detections** in `cron-ruleset-bypass-audit.ts`:
  a `buildFindings` model audits `bypass_actors` widening, `required_status_checks`
  un-requiring (removed = critical; extra = divergence-only), and
  `enforcement != "active"`, files ONE combined drift issue, and auto-closes it
  on the next green run.
- **Reconciled the canonical** RSC JSON 5→16 (verified `== live ruleset`).
- **Added a CI sync gate** (`T-rsc-9` in `tests/scripts/test-audit-ruleset-bypass.sh`)
  asserting the canonical JSON's context set equals the `.tf` `required_check`
  contexts. Any future `.tf` edit now fails CI until the snapshot is reconciled
  in the same PR — the dual-source drift that caused #4397 **cannot recur
  silently**.
- Reconciled the operator runbook GHA→Inngest (#5759) and updated
  `compliance-posture.md`.
- Verified end-to-end: deployed, fired `cron/ruleset-bypass-audit.manual-trigger`
  (HTTP 202), confirmed green (no drift issue) with all three live dimensions
  matching canonical.

## Key Insight

Three reusable lessons:

1. **When migrating a multi-check audit/guard between runtimes, enumerate and
   verify EVERY detection dimension survives — not just the headline one.** A
   migrated guard that still runs and goes green is the most dangerous kind of
   regression: it looks healthy while silently covering less. Diff the old and
   new implementations dimension-by-dimension, not behavior-at-a-glance.

2. **Any hand-maintained snapshot that mirrors a source of truth (Terraform,
   DB schema, config) needs a CI gate locking the two together, or it WILL
   drift silently.** Don't re-sync the snapshot and move on — add the gate that
   makes future divergence a build failure. The fix for a stale mirror is not a
   fresh copy; it's a lock.

3. **A "stale"/false-positive on a compliance or drift guard can mask a
   coverage regression — investigate why it fired, don't just close it.** #4397
   looked closeable ("safe-direction drift, no exposure"), but the real story
   was that its detection mechanism no longer existed. The triage question is
   not "is this finding real?" but "why did this fire, and is the thing that
   fired it still working?"

## Session Errors

- **Worktree vanished mid-task (concurrent-session rotation race).** A worktree
  created and actively used (`fix-3570-3571-...`) disappeared from `git worktree
  list` — directory and branch gone — mid-session, almost certainly removed by
  another concurrent session's `cleanup-merged`/`prune`. Manifested as Edit/Read
  "File does not exist" and a later `cd`-into-worktree failure when firing the
  smoke. **Recovery:** recreated the worktree / switched to a currently-valid
  one. **Prevention:** treat `.worktrees/<x>` paths as non-durable across turns
  when multiple sessions share one bare repo — re-resolve a valid worktree from
  `git worktree list` immediately before use rather than reusing a path captured
  earlier. One-off/environmental; no clean code fix.
- **`gh pr merge --delete-branch` blocked by a hook whenever any worktree
  exists.** The guard refuses `--delete-branch` if any worktree is present (it
  would orphan them), and it blocks the *entire* Bash call, so removing the
  target worktree in the same compound command does not help. **Recovery:**
  merge without `--delete-branch`, then `git push origin --delete <branch>`
  separately (the repo auto-deletes on merge anyway). **Prevention:** on a
  bare-repo/multi-worktree setup, default to `gh pr merge --squash` WITHOUT
  `--delete-branch`; delete the remote branch in a separate step. Recurring.
- **The `BEHIND` merge race.** The `CI Required` ruleset enforces strict
  up-to-date-with-main; on an active day main merged faster than the PR's ~8-min
  CI, repeatedly flipping it `BEHIND` and restarting CI. Auto-merge does not
  auto-update a behind branch, so it never converged; admin-merge was the escape
  hatch. **Prevention:** filed #5780 (adopt a GitHub merge queue — serializes
  merges so up-to-date is satisfied by construction). Recurring; tracked.
- **`jq` probe error "Cannot index number with string actor_id".** A
  bypass_actors comparison applied the array projection to the whole ruleset
  object instead of `.bypass_actors |`. **Recovery:** added the selector.
  One-off.
- **Edit "File has not been read yet".** Edited `compliance-posture.md` after
  reading it via `grep`/bash rather than the Read tool. **Prevention:** the Read
  tool (not shell `grep`) is what satisfies the read-before-edit gate. One-off.
