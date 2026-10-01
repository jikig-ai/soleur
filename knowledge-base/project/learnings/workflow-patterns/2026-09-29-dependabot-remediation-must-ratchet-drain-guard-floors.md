---
title: Dependabot remediation PRs must ratchet assert-dependabot-drain.py floors in the same diff
date: 2026-09-29
feature: feat-one-shot-dependabot-alerts
pr: 9198
tags: [dependabot, lockfile, security, guards, assert-dependabot-drain]
---

# Dependabot remediation PRs must ratchet `assert-dependabot-drain.py` floors in the same diff

## Problem

A one-shot remediation of 9 open Dependabot alerts (fast-uri 3.1.5→3.1.8,
ip-address 10.5.0→10.7.2 across `apps/web-platform` and
`pencil-setup/scripts` lockfiles) planned and implemented cleanly — but the
plan never touched `scripts/assert-dependabot-drain.py`, the committed
merge-time drain guard (ADR-191, #7084). Its `REQUIRED` rows and
`FLOOR_ANCHORS` still pinned `fast-uri ≥3.1.5` and `ip-address ≥10.3.1`, so a
post-merge regression to a *still-vulnerable* version (3.1.5–3.1.6,
≤10.5.0) would have passed the guard silently. The file's own header says
"Add an anchor whenever an advisory forces a floor up" — the obligation was
documented in the guard but not in the plan template, so the plan omitted it.
Caught by the `git-history-analyzer` review seat, fixed inline.

## Solution

- Ratchet `REQUIRED` rows AND `FLOOR_ANCHORS` to the advisory's strictest
  `first_patched_version` (fast-uri → `3.1.7`, ip-address → `10.5.1`), in the
  same commit as the lockfile bump.
- Verify: `python3 scripts/assert-dependabot-drain.py` (resolves rows against
  the bumped lockfiles) and `bash scripts/assert-dependabot-drain.test.sh`
  (24-assertion mutation suite; proves reverting to the stale floors REDs).
- **Workflow fix shipped in the same PR:** `work-lockfile-bumps.md` (the
  reference `soleur:plan` consults for dependency remediation) now carries a
  "Ratchet the drain guard in the same PR" directive, so future plans inherit
  the step.

## Session Errors

1. **Idempotency probe misread.** The plan's Phase 4.2 says
   `npm install --package-lock-only` then `git diff --exit-code` — I ran it
   before committing the bump, so `git diff` vs HEAD necessarily showed the
   bump itself and read as "DIFF REMAINS". The check is meaningful only as a
   before/after on the regenerated file (hash-stability) or post-commit.
   **Prevention:** when a plan's verify step asserts a clean `git diff`,
   establish the baseline snapshot BEFORE running the mutating command, or run
   it after the increment is committed.
2. **`pgrep -f` self-match blocked by hook.** Attempted `pgrep/pkill -f
   test-all.sh` to stop a background battery; the guardrails hook denied it
   (self-matching argv) and named the remedy (`proc.sh` `kill_mine`).
   **Prevention:** already enforced — `source plugins/soleur/scripts/lib/proc.sh`
   + `kill_mine <pattern>` is the sanctioned path.

## Key Insight

A remediation that bumps a package past an advisory floor without ratcheting
the repo's drain guard leaves the guard asserting a floor *below* the
vulnerability — protection-shaped but inert. The ratchet is part of the fix,
not follow-up hygiene.

## Tags

dependabot, package-lock.json, assert-dependabot-drain, floor ratchet, security
