# Learning: a cleanup brief written the day before had two of its three premises already false on main

## Problem

A resume brief asked for three cleanup items after the Bun 1.4.4 pair PR: add accept rows for 11 `affected-index-ratchet` new-pair findings, extend `work/SKILL.md` bullet 6.7, and file a follow-up for a missing GitHub-token pattern in `digest-scrub.sh`. Planning found:

- Item 1 was already done. The accept rows landed in `cffdf2705a` (22 `refresh-stage-a` rows are on main) and the merge_group ratchet printed `SOLEUR_PR_AFFECTED_RATCHET exit=0 reason=pass live=0 baseline=0` (run 42178975746). The "13 findings, 11 from the pair PR" figure described the ratchet at `04fc68d782`, not main at dispatch time.
- Item 3's premise was false. `digest-scrub.sh` already has a `github_token` class, and the checkout persists no credential. The token reaches `.git/config` only through claude-code-action's own git auth step.
- Item 2 could not land in `work/SKILL.md` (12 bytes of body-budget headroom, ceilings only move down). It landed in `work/references/work-test-harness-sharp-edges.md` at zero SKILL.md cost.

The PR therefore shrank from "edit a 3,000-row accept TSV and file an issue" to one 5-line reference bullet. Editing the TSV would only have collided with two open PRs that touch the same file.

## Solution

Treat each item of a resume brief as a precondition to measure, not as work to do. The cheap measurements here were one ratchet log read, `git grep -c refresh-stage-a origin/main -- scripts/ci-pr-affected-audit.accept.tsv`, and `sed -n 51p digest-scrub.sh`. The CTO agent ruled each fork (verify-only, reference-file placement, do not file) and recorded the rulings in `decision-challenges.md`.

## Key Insight

The brief's unresolved-notes list was the most reliable part of it, and its work-to-do list was the least. A brief is written by the session that finished the previous arc, so its counts describe the moment that session stopped. Re-measure each count against current `origin/main` before spending a worktree, a plan and a panel on it. This repeats the existing rule in `work/SKILL.md` Phase 1 about resume briefs, and the rule held: no new rule is needed.

## Session Errors

1. **The brief's item 1 and item 3 premises were stale or wrong** (13 findings; "no GitHub-token pattern"). Recovery: planner re-measured against main and the CTO ruled verify-only and do-not-file. **Prevention:** already covered by the resume-brief precondition rule in `work/SKILL.md`; the check that worked was a one-line `git grep` or log read per item, run before planning.
2. **Two closing messages were blocked by the unkept-promise stop hook** because they ended on a first-person future action ("I'll synthesize...") while review seats were still running. Recovery: ended the turn with a single `Paused:` sentence naming the external event. **Prevention:** when waiting on background seats, end with the `Paused:` line instead of describing the next step in the future tense.
3. **Session started from the bare repo root** (`SOLEUR_BARE_ROOT_CWD` marker). Recovery: routed through one-shot, which created the worktree. **Prevention:** none needed, the redirect worked as designed.

## Tags

category: workflow-patterns
module: soleur:go, soleur:one-shot, soleur:plan
