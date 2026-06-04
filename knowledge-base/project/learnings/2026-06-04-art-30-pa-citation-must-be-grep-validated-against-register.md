---
title: "Art. 30 PA citation in a legal-disclosure PR must be grep-validated against the register, not inherited from the plan's premise"
date: 2026-06-04
category: legal-compliance
modules:
  - knowledge-base/legal/compliance-posture.md
  - knowledge-base/legal/article-30-register.md
  - plugins/soleur/skills/plan
  - plugins/soleur/skills/review
issues:
  - 4952
prs:
  - 4954
related:
  - 2026-05-23-legal-disclosure-prose-must-be-grep-validated-against-actual-migration.md
---

# Learning: Art. 30 PA citation must be grep-validated against the register

## Problem

PR #4954 disclosed the Web Platform agent's autonomous (auto-run) shell-command
surface (shipped by #4949) in the AUP / T&C and recorded an Art. 30 disposition
in `compliance-posture.md`. The plan asserted the autonomous-execution runtime
was **"already registered as PA 21 (Autonomous-acknowledgment runtime) / PA 22
(Autonomous AI leader-prompt runtime)"** and concluded "no new PA." Both `/work`
and the deepen pass carried that premise forward verbatim into the
compliance-posture entry.

It was **factually wrong**. PA 21/22 are the **Inngest `agent.spawn.requested`
TodayCard leader-prompt runtime** — an operator clicks a TodayCard, an Inngest
loop posts a GitHub artifact. The feature actually disclosed (#4949) is the
**interactive Concierge chat runtime** (`cc-dispatcher` / `permission-callback`,
persisting tool-call metadata), which is registered as a *different* activity:
**PA-2 — Conversation Data (Messages, Turns, Usage Telemetry)**. An auditor
following the PA-21/22 citation would find an Inngest runtime that does not
describe interactive bash auto-run at all, and the "covered" claim collapses.

Caught only by the `legal-compliance-auditor` agent reading the register
PA-by-PA at review time (single-agent P1). Five other review agents — including
ones that verified the legal prose against `BLOCKED_BASH_PATTERNS` and the
banner — took the "no new PA" claim at face value because none of them looked up
the PA *numbers* in the register.

## Root cause

The plan's PA-number attribution is a **hypothesis authored from a conceptual
narrative** ("autonomous execution → the autonomous-* PAs"), not a fact derived
from reading the register. PA names that *sound* like the feature ("Autonomous-
acknowledgment runtime", "Autonomous AI leader-prompt runtime") are a false
match: in this codebase "autonomous" spans at least two unrelated runtimes
(server-side Inngest spawn vs. interactive chat), registered under different PAs.

## Solution

Re-anchored the disposition to PA-2 and made the substantive "no new PA" argument
on the correct limb. Critically, also verified the *deeper* question the plan's
wrong citation had buried: does removing the per-command human-approval step
(default-ON autonomy) narrow a registered Art. 32 §(g) TOM? Read PA-2's 12
§(g) measures (RLS, per-user JWT mint, write-boundary sentinel, data-minimisation,
attachment isolation, DSAR redaction) — **none gates shell-command approval**.
The per-command approval step is a workspace-safety control on the operator's
*own* systems, not a registered TOM protecting third-party data subjects → its
removal narrows no registered TOM → no PA-2 limb amendment. Citation fixed; the
"no new PA" conclusion survives on the correct limb.

## Key Insight

This is the **PA-attribution sibling** of
[[2026-05-23-legal-disclosure-prose-must-be-grep-validated-against-actual-migration]]:
the same grep-validation discipline that applies to migration column-names in
legal prose applies to the **Art. 30 PA-number** in `compliance-posture.md`.

When a legal-disclosure PR claims "no new PA — covered by existing PA N":
1. **Grep the register for the implementing surface, not the PA name.** Identify
   the actual code surface the feature lives in (here: `cc-dispatcher` /
   `permission-callback` → the runtime that persists tool-call metadata), then
   find which PA's `(b) Purposes` / `(g) TOMs` *cite that surface*. Do NOT match
   on the PA's title.
2. **A "no limb amendment" claim requires reading the cited PA's actual
   `(g) TOMs`.** If the change removes/alters a control, confirm that control is
   not one of the cited PA's registered Art. 32 measures. A safety control on the
   user's own systems is not automatically a GDPR TOM.
3. The plan's PA-number is a precondition to verify, never a fact — same class as
   `hr-when-a-plan-specifies-relative-paths-e-g` for file paths.

## Session Errors

- **Art. 30 PA misattribution (P1)** — Recovery: legal-compliance-auditor read the
  register; re-anchored compliance-posture.md to PA-2 + verified no §(g) TOM moves.
  Prevention: plan/review skill bullets (this learning) instructing PA-number
  grep-validation against the register's `(b)/(g)` limbs, not the PA title.
- **test-all.sh exited 1 masked as "exit 0"** by a wrapper `echo EXIT=$?` — the
  harness reported the *wrapper's* exit. Recovery: explicit `grep "^EXIT="` on the
  log surfaced the real `99/100 suites passed`. Root cause was a pre-existing
  cross-test file-pollution race (`dsar-worm-guc-sites.test.ts` reads the real
  `supabase/migrations/` dir while `run-migrations-unmerged-gate.test.ts` writes
  + unlinks a synthetic `zzz_unmerged_gate_*.sql` fixture there). Filed #4957.
  Prevention: re-confirms [[2026-05-18-test-all-tail-masking-and-monitor-exit-condition-tightness]]
  — always capture `rc=$?` and inspect it, never trust a piped/wrapped exit.
- **Edit-before-Read** — viewing a file via Bash `sed` does not satisfy the
  Read-before-Edit harness requirement. Recovery: Read tool first. One-off.
- **Planning subagent OverloadedError** (transient) — re-spawned fresh; one-shot's
  fallback path handled it. One-off.
