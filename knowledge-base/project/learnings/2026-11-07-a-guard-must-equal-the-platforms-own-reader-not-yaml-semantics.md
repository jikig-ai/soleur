# Learning: a duplicate-key guard must equal the PLATFORM's reader, not YAML semantics

## Problem

A merge candidate's `ci.yml` carried two `fetch-depth` keys in one `with:` mapping. Git merged it cleanly, GitHub recorded a failed `push` run for the file on the queue temp ref and never created the `merge_group` run, so the required `test` context never reported and the queue stalled 175 minutes (#12283). The PR (#12295) adds a duplicate-key-strict guard as a `quality-guards` member and teaches the stall check to name the workflow whose load failed.

## Solution

- The guard (`.github/scripts/check-workflow-duplicate-keys.py`) walks the composed YAML node graph and compares keys the way GitHub's reader does: key text with ASCII letters upper-cased, the merge key an ordinary key, and a plain scalar key that reads as a YAML 1.2 null/bool/int/float a finding in its own right (CTO D13/D19).
- The stall check names a workflow only when a failed `push` run whose name equals its path has no `merge_group` run of the same `workflow_id` on the PR's latest temp ref AND the workflow has merge_group history at all; the wording is "LIKELY CAUSE (inferred)" (D3/D4/D16).

## Key Insight

**A validator that claims to mirror a platform's rejection rule has to be checked against the platform's own reader source, not against the YAML spec or documentation.** The plan (and the CTO ruling it rested on) treated case-insensitivity as a residual limited to `with:`/`env:`. Two independent review seats fetched `actions/runner` `TemplateReader.cs` (lines 180 and 307: the per-mapping key set is `StringComparer.OrdinalIgnoreCase`) and showed it holds on every mapping, and a third found that GitHub also stringifies plain null/bool/number keys before the check (`1` and `1.0` collide, `~` and `null` collide). One fetch, three corrections.

Smaller insights from the same PR:

- PyYAML's C loader reports `style == ''` for a plain scalar where the pure loader reports `None`: test `not node.style`, never `is None`. Only running the real tree under both loaders exposed it.
- "The log shows no `Collecting pyyaml`" does not prove PyYAML is preinstalled when sibling steps install it quietly (`2>/dev/null || true`). Print the version in the guard's own output so every run carries the evidence.
- An unwindowed "this workflow has ever had a `merge_group` run" lookup separates "unloadable and gates the queue" from "unloadable but irrelevant"; the windowed form would have un-named the very incident on a one-entry queue.
- A unit suite that scores a mutant as KILLED because the named row failed cannot tell a semantic kill from a crash (jq compile error swallowed by `2>/dev/null`, an unbound variable only reachable on the finding path). Score a verdict-less crash UNRESOLVED and give the harness a control per crash class.

## Session Errors

1. **Plan phase left `pending - assumed` and bad-shape rows in `decision-challenges.md`, failing the pre-work ruling gate on 5 rows.** Recovery: one batched CTO call rewrote them. **Prevention:** the plan skill already instructs a CTO spawn for technical rows; the planning subagent had the Agent tool and still wrote placeholders. The work-phase technical-ruling gate caught it, so no new rule; keep running that gate before `soleur:work`.
2. **A `git commit` was hook-blocked as "committing to main" because the shell cwd had reset to the bare root.** Recovery: re-issue the commit with the command starting `cd <worktree> &&`. **Prevention:** start every commit command with `cd <worktree-abs-path> &&` after any Bash call that printed a "Shell cwd was reset" notice.
3. **A Monitor watch used `pgrep -f` and was blocked by the self-match hook.** Recovery: poll a log/rc file instead. **Prevention:** already hook-enforced (`pkill-self-match-guard.sh`); wait on rc files.
4. **The affected-test gate returned `rc=6` budget-deferred behind a sibling worktree's full-gate lock and SIGTERM'd 4 unrelated suites.** Recovery: ran the targeted suites and lints directly; CI is the authoritative gate. **Prevention:** read `scripts/test-all.sh --capacity` before launching and use the targeted suites when it reports a queue.
5. **The round-1 stall-check fix agent ended on an interim "waiting on my own monitor" with unfinished work and a stale `EXPECTED_PASSES` (96, real 131); it sat idle about 45 minutes.** Recovery: `SendMessage` to make it report, then ran the suite and set the floor myself. **Prevention:** brief fix agents (not only review seats) to run suites in the foreground with `timeout` and never end a turn on a background monitor; routed as a bullet in `risk-tier-and-fix-rounds.md`.
6. **My inline `10#` edit broke a literal mutation anchor in the stall suite.** Recovery: the suite's "mutation anchor not found" guard failed loudly; updated the anchor. **Prevention:** none needed, the guard worked; grep the suite for the literal before editing a workflow line it mutates.
7. **An unresolved-merge index made `git ls-files` triple-count a conflicted file, so the independent-count row read 116 against the guard's 114.** Recovery: `git add` the resolution. **Prevention:** already documented (regenerate or count only after the merge commit exists); stage the resolution before running count-based suites.
8. **The premise "PyYAML preinstalled, verified in run 42341892616's log" entered binding ruling D2 unmeasured.** Recovery: history seat falsified it; D17 prints the version. **Prevention:** already covered by "a factual premise inside a ruling request is a claim to run before it is copied".
9. **The PR went `DIRTY` after `main` moved during review; only the QA mergeability read caught it.** Recovery: merged `origin/main`, kept `main`'s `source …/umbrella-member.sh` line plus our member row. **Prevention:** `merge-tree` at review start passed; re-run `git merge-tree --write-tree origin/main HEAD` immediately before QA and ship.

## Tags
category: ci
module: merge-queue, quality-guards
