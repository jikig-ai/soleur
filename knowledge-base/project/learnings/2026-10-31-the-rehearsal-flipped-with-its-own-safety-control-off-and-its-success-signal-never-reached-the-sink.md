# Learning: the rehearsal flipped with its own safety control off, and its success signal never reached the log sink

## Problem

Rehearsal 2 of the git-data flip-then-rollback (#8211, 2026-10-31) reached Level 2 and read clear, but three defects in how we ran it were found only by looking:

1. **A precondition that lived in prose was read as a value, not a verdict.** The runbook says no `mode=flip` is safe until the new-sessions pause is on and read back on both hosts. R0 read the control line (`newSessionsPaused=false` on both hosts) and reported it as a fact. R1 was dispatched with the pause off, and the `Flip preconditions` step did not refuse, because it does not check the control. The pause went on about 5 minutes after the flag write (09:43:29Z to about 09:48Z). No real-user conversation started in the window (a post-deletion count of conversations created in it read 0), so nothing was lost, but only by luck.
2. **The success signal was logged at a level that never reaches the sink.** The CTO ruling for the INCONCLUSIVE R3 read said "require a `git-data replication push complete` row". That row is logged at info (30). Zero level-30 rows from any app context reached Better Stack in 15 minutes: only warn and error ship, which is why the startup markers are emitted at level 40. The only way to see that the session replicated was `refs_assert` after the rollback.
3. **The R3 clause "zero overlay fallback rows" can never read clean for a first session.** The store repository is created only by the session-end provision. Connecting the repository before (or inside) the window provisions nothing, so the first session's session-start fetch always logs `does not exist (provision it first)` as a level-50 `ensure-workspace-repo silent fallback`, op `git-data-overlay`.

Around the rehearsal, four CI cycles on PR #11567 each exposed a different repo-global ratchet a file-selected local run could not see, and `main` itself was red for hours (inngest pin drift, with the fix PR stalled behind a runner-timeout flake, #11669).

## Solution

- Tracked as one consolidated issue (#11704): make the flip preconditions refuse unless `newSessionsPaused=true` on both hosts; classify the expected first-session overlay miss as info; emit a warn-level, counts-only replication-success marker.
- The runbook now carries the Rehearsal 2 record and an "R3 first-session reading" paragraph (the CTO ruling of 2026-10-31): the expected overlay row does not disqualify, replication is confirmed by `refs_assert` after the rollback, and the store cannot be read inside the window because `refs_assert` and `proof` refuse while the flag is on.
- R4 proceeded on the ruling to close the window rather than hold it open for a second session; the store read after it (`refs_assert`) confirmed `repos=1 refs=1 heads=1` with a tip equal to the GitHub tip, and the exit read after the account deletion was `clear`.

## Key Insight

A control the procedure says must be ON is only a precondition if the thing that dispatches the dangerous step checks it. A reader who is asked to "read the control line" returns a value and moves on; the gate has to turn the value into a refusal. And before relying on a log row as positive evidence, spend one query on whether rows of that level reach the sink at all: the absence of a success row is evidence only for sinks that carry success rows.

## Tags

category: workflow-patterns
module: git-data-cutover, rehearsal

## Session Errors

1. **R0 read `newSessionsPaused=false` and did not treat it as a blocker; R1 was dispatched with the pause off** — Recovery: owner turned the pause on about 5 minutes after the flag write; a post-window DB count showed no real-user conversation — **Prevention:** the `Flip preconditions` step refuses unless the pause reads `true` on both hosts (tracked #11704 item 1); until then R0 must record "pause: true on both hosts" as a pass/fail line, not a reading.
2. **Assumed info-level app rows reach Better Stack (the CTO ruling's premise)** — Recovery: measured zero level-30 rows in 15 minutes, fell back to `refs_assert` after the rollback — **Prevention:** one `betterstack-query.sh --grep '"level":30'` before treating a missing success row as a signal; warn-level success marker tracked in #11704 item 3.
3. **Four CI cycles each exposed a repo-global ratchet that a file-selected local run cannot see** (the precheck suite's exact-env pin, the ancestor-signal scanner baseline, `grep-q-pipe-guard`, `fixture-env-adoption`, and affected-index accept rows) — Recovery: fixed each in the next push — **Prevention:** already documented (work Phase 2 §9 "a file-selected suite set cannot see a repo-global ratchet"); the new part is that merging main's workflow edit changes the *line count* a suite's mutants pin, so grep the suites that read a changed workflow (`git grep -l <workflow-name> -- '*.test.sh'`) and run them before the first push.
4. **Read the slowest CI leg (`test-scripts (1/8)`) as hung and cancelled it three times by pushing** — Recovery: read its log tail (it was advancing alphabetically through the suites), then let one finish — **Prevention:** before concluding a leg is hung, read the cancelled run's log tail; a leg that takes 45+ minutes while the others take 30 is slow, not hung.
5. **A bound-fix PR (#11676) for a runner-timeout flake could not merge ahead of the pin-drift fix it was meant to unblock** — Recovery: the pin bump landed on its own after retries — **Prevention:** before opening a fix PR for a red check, confirm the PR itself can go green on the red `main` it targets (here its own leg 4/4 failed on the same drift).
6. **Hook rejections:** a heredoc and `gh issue create` in one call (body file unreadable at hook time), two `gh pr merge` invocations in one command, `--match-head-commit` with extra operands, a `git stash list` — Recovery: wrote the body file in a separate call, used a single bare `gh pr merge <N>` under the lock — **Prevention:** already hook-enforced; no change.
7. **No TTY for the owner-typed `flip.sh` command on a remote-control session** — Recovery: Flagsmith dashboard toggle by the owner, then two named Doppler mirror writes — **Prevention:** none needed; the TTY requirement is deliberate (ADR-249), and the dashboard is a human acknowledgement.
8. **Stale Playwright refs after navigation, and stale or duplicate monitors** — Recovery: re-snapshot before acting; `TaskStop` the old monitor when re-arming — **Prevention:** snapshot immediately before a ref-based action on a page that just navigated.
