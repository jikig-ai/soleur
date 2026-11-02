---
title: "docs: mark the Better Stack write-token scope as verified in the LUKS cutover runbook"
type: docs
date: 2026-11-02
slug: luks-runbook-betterstack-write-scope-verified
branch: feat-one-shot-luks-runbook-betterstack-write-scope-verified
issue: 11869
lane: cross-domain
---

# docs: mark the Better Stack write-token scope as verified in the LUKS cutover runbook

Spec lacks a `lane:` (no spec.md existed for this branch) — defaulted to cross-domain (TR2 fail-closed). The change itself is a single-paragraph docs edit.

## Overview

Section 5 of `knowledge-base/engineering/operations/runbooks/workspaces-luks-cutover-6604.md` ("Resolve the stuck Better Stack incident") still tells the reader that the write token's scope on `POST /api/v2/incidents/<id>/resolve` is UNVERIFIED and "has not been exercised from this repo". That is now false: the 22:32 UTC comment on open issue #11869 records that the `BETTERSTACK_API_TOKEN` write token returned HTTP 200 on that exact endpoint and the incident went to `resolved_at` 2026-11-02T22:32:29Z. The comment itself says the runbook sentence "can be updated in a later docs change". This plan is that change.

Replace the stale sentence with a verified-on-2026-11-02 note citing that comment. Keep the stop rule ("If the API answers 401 or 403, stop, record the status code on #11631, and do not retry with a different token without a fresh authorization") exactly as it is.

## Research Insights

**Premise Validation.** Checked and held: (1) the stale sentence is at lines 1123-1125 of the runbook on `origin/main` (the only scope-UNVERIFIED hit in section 5; the other `UNVERIFIED` at line 1027 is an unrelated sentence about absent probe values and must stay); (2) #11869 is OPEN and its last comment (2026-11-02T22:32:43Z) carries the HTTP 200 and `resolved_at` 2026-11-02T22:32:29Z evidence verbatim; (3) draft PR #11926 exists on this branch. Observed, not acted on: #11631 (named by the stop rule as the place to record a 401/403) is now CLOSED — the owner said keep the stop rule unchanged, so it stays. Collision pre-check: open PR #11893 names #11869 but touches `betterstack-logs-alerts.tf`, its test, `betterstack-log-query.md` and `inngest-server.md` — no file overlap with this change (it pauses an alert predicate, which this PR must not do); a foreign `test-all.sh` process is from another worktree and is not ours.

**Property List.**

1. A reader of section 5 learns the write token's scope on the resolve endpoint has been exercised and works, with the date and evidence.
2. The stop rule on a 401/403 answer is unchanged, so a future token rotation or scope loss still halts the procedure.
3. Nothing else in the runbook, no alert predicate and no `.tf` file moves.

**Cut List.** None — no mechanism is proposed; the change is one paragraph of prose.

**Learnings / ADR corpus.** No mechanism proposed, so no ADR conflict. Relevant rules: `cq-cite-content-anchor-not-line-number` (cite the 22:32 UTC comment on #11869 by content, not by a link whose number can drift), `hr-before-asserting-github-issue-status` (status above read live via `gh`).

## Files to Edit

- `knowledge-base/engineering/operations/runbooks/workspaces-luks-cutover-6604.md` — section 5, the three-line sentence starting `**The write token's scope for this endpoint is UNVERIFIED**` (anchor on that text, not on the line numbers).

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-luks-runbook-betterstack-write-scope-verified/tasks.md` (task breakdown, this planning phase)

## Implementation

Replace, inside the existing paragraph, the span from `**The write token's scope for this endpoint is UNVERIFIED**` through `has not been exercised from this repo.` with this note (wording may be re-flowed to the 120-column wrap of the surrounding paragraph):

> **The write token's scope for this endpoint is verified (2026-11-02):** `BETTERSTACK_API_TOKEN`'s write scope works on `POST /api/v2/incidents/<id>/resolve` (HTTP 200, `resolved_at` 2026-11-02T22:32:29Z; evidence: the 22:32 UTC comment on #11869). Verified scope is not authorization: the production-write rule in this section's heading still applies to every run.

Everything after it is untouched, starting at `If the API answers 401 or 403, stop, record the status code on #11631,` and ending at `` `TARGET=<target> bash resolve-incident.sh`. ``. The reference to Better Stack's public API reference is dropped with the stale sentence; the verified note supersedes it.

Do NOT touch: the four "clears on its own" places in other runbooks and comments (owner decision), any alert predicate or `.tf` file, the resolve script block, or any other runbook text.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "replace the stale sentence \"The write token's scope for this endpoint is UNVERIFIED ... has not been exercised from this repo\" with a verified-on-2026-11-02 note" [brief] | Files to Edit / Implementation | mapped |
| 2 | "BETTERSTACK_API_TOKEN write scope works on POST /api/v2/incidents/<id>/resolve (HTTP 200, resolved_at 2026-11-02T22:32:29Z), citing the 22:32 UTC comment on open issue #11869" [brief] | Implementation (note text) | mapped |
| 3 | "Keep the existing \"If the API answers 401 or 403, stop, record the status code\" stop rule unchanged" [brief] | Implementation (untouched span) + AC3 | mapped |
| 4 | "Docs-only: touch no alert predicate, no .tf file, no other runbook wording" [brief] | AC4, AC5 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Edit to runbook section 5 | "replace the stale sentence" | asked |
| Sentence "Verified scope is not authorization ..." | — | inferred — justification: the heading says "production write: authorize the exact command"; a bare "verified" could be read as standing authorization, which `hr-menu-option-ack-not-prod-write-auth` forbids |
| tasks.md | asks 1-4 | asked |

### Split Assessment

- Subsystems touched: 1 — knowledge-base/engineering/operations/runbooks
- Planned files: 2 | Estimated changed lines: ~6
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1: `git grep -c "scope for this endpoint is UNVERIFIED" -- knowledge-base/engineering/operations/runbooks/workspaces-luks-cutover-6604.md` finds nothing (exit 1), and `git grep -c "has not been exercised from this repo"` on the same file finds nothing. The unrelated `UNVERIFIED` at the probe-values sentence (line ~1027) is still present — do not assert a bare-token zero.
- [ ] AC2: The file contains the new note: `git grep -n "write token's scope for this endpoint is verified (2026-11-02)"` returns exactly 1 hit, and the same paragraph carries `HTTP 200`, `2026-11-02T22:32:29Z` and `#11869`.
- [ ] AC3: `git grep -n "If the API answers 401 or 403, stop, record the status code on #11631, and do not retry with a different token without a fresh authorization" -- <runbook>` returns exactly 1 hit (the stop rule is byte-identical).
- [ ] AC4: `git diff --name-only origin/main...HEAD` lists only the runbook plus files under `knowledge-base/project/{plans,specs}/` — no `.tf`, no other runbook, no workflow or script.
- [ ] AC5: `git diff -U0 origin/main...HEAD -- <runbook>` has exactly one hunk, within section 5, removing at most 3 lines and adding at most 6; the section 5 code block and the `clears on its own` wording elsewhere are unchanged.
- [ ] AC6: markdownlint passes on the runbook (`npx markdownlint-cli2 <runbook>` using the repo `.markdownlint.json`), and the repo-global ratchet lane `bash scripts/pre-push-ratchet-lane.sh` is green before the push.
- [ ] AC7: PR #11926 (existing draft) is the PR; its body uses `Ref #11869` (not `Closes`, since #11869 is closed by the incident mirror, not by this docs change) and notes that no alert, `.tf` file or Better Stack/Hetzner/Doppler write was made.

### Post-merge

- [ ] AC8: Read the merged runbook by the merge SHA (`git show <merge-sha>:<runbook>`), never local `main`, and confirm AC1-AC3 hold there. Run postmerge from a detached `origin/main` worktree.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing user-facing; an operator reading section 5 could be misled about whether the resolve call has ever worked, and either skip a needed resolve or distrust a working token.
- **If this leaks, the user's data / workflow / money is exposed via:** no vector — the note contains an incident timestamp and an issue number only; no token value, secret, name or email.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** docs-only edit to an internal runbook with no secret, no code path and no alert change, so a mistake costs an operator a re-read, not a user an incident.

*Scope-out override:* `threshold: none, reason: the touched path is an internal operator runbook under knowledge-base/, not an auth, schema, API or user-data surface.`

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling documentation change. Not UI, no Product/UX Gate; no regulated-data surface (GDPR gate skipped); no new infrastructure (IaC gate skipped); no architectural decision (ADR/C4 gate skipped); no guard (Guard Contract skipped); pure-docs so the Observability section is skipped per Phase 2.9.

## Test Scenarios

- Read-only checks only: the AC1-AC5 `git grep` / `git diff` commands, each of which can fail (they assert presence of the new note, absence of the stale text, and byte-identity of the stop rule). No test suite changes; the repo-global ratchets in AC6 run as the gate.

## Sharp Edges

- Anchor the edit on the sentence text, not on line numbers; other PRs (#11893) touch neighbouring runbooks and line numbers drift.
- The stop rule names #11631, which is closed. Leave it: the owner directed it unchanged, and re-pointing it is a separate decision.
- Do not write to Better Stack, Hetzner or Doppler, dispatch `apply_target=inngest-host-replace`, touch A5/A6, close the LUKS epic, or pause/edit any alert predicate. The evidence is already on #11869; this PR reads nothing live.
- Git hygiene for the work phase: no `git stash`; separate `git add` and `git commit` calls; commit message via `-F <file>`; no `$()` in ship-skill Bash calls (use a script file); `Monitor`, not background runs, for polling.
