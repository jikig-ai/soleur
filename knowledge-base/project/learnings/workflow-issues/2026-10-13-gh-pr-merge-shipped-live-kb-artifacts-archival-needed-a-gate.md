---
title: "A prose archival step in one arm of ship let gh pr merge carry live KB artifacts onto main"
date: 2026-10-13
category: workflow-issues
module: Ship Pipeline
problem_type: workflow_issue
component: development_workflow
symptoms:
  - "PR #10064 merged to main with its spec dir still live under knowledge-base/project/specs/"
  - "1540 of 1751 live spec dirs belonged to already-merged PRs (archive/ held only 652)"
  - "ship's archival step ran in only one phase arm — create-arm merges reached gh pr merge unarchived"
  - "archive-kb.sh branch-diff discovery was blind to uncommitted and untracked artifacts"
root_cause: missing_workflow_step
resolution_type: workflow_improvement
severity: high
status: open
rule_id: wg-kb-artifacts-archived-in-pr
pr: 10161
branch: kb-archive-gate
tags: [ship-pipeline, kb-archival, pretooluse-hook, gh-pr-merge, merge-gate, fail-open-scope]
---

# Troubleshooting: `gh pr merge` could ship live KB artifacts because archival was a checklist line, not a gate

## Problem

Knowledge-base archival existed only as prose: compound Step E asked for it, and ship carried it in one arm of Phase 6. A merge that skipped the step — or a `gh pr merge` typed directly — landed live `specs/`/`plans/`/`brainstorms/` on main. PR #10064 did exactly this; the accumulated backlog measured 1540 live spec dirs belonging to merged PRs against 652 archived.

## Solution

Three-part fix on PR #10161:

1. **A PreToolUse deny hook** (`.claude/hooks/ship-kb-archive-gate.sh`, rule `wg-kb-artifacts-archived-in-pr`) intercepts `gh pr merge`, resolves the actual merge head — `--match-head-commit` sha, then `refs/pull/N/head` pinned via `ls-remote`, then the pushed `origin/<branch>` — and fails closed when a census of `diff origin/main...<head>` carries added/modified live artifacts. Learnings are deliberately out of census scope.
2. **A named ship phase** (`Phase 6.45` in `ship/SKILL.md`) makes archival a required, checklisted step before push/merge instead of a note inside one arm.
3. **A report-only post-merge sweep** (`postmerge` Phase 5.8) reads the merge commit's range-diff and reports residual live artifacts without blocking completion.

## What Didn't Work

**Censusing local HEAD for the flag-only merge arm:** `gh pr merge` merges `origin/<branch>`, not local HEAD — a branch behind its remote under-measures the leak. Fixed by resolving the pushed head.

**`rev-parse FETCH_HEAD` after the pull-ref fetch:** FETCH_HEAD is shared mutable state; a concurrent fetch substitutes a different oid. Fixed by pinning the head via `git ls-remote` before fetching.

**Trigger boundary tuned to `gh pr merge` only:** the first regex missed `gh <global-flags> pr merge`, `xargs`-fed invocations, and `$(...)` nesting; review expanded the boundary to command-word matching plus an explicit xargs deny.

**`--diff-filter=AM` for the leak census:** misses a rename *to* a live path; widened to `AMRCT`.

## Key Insight

A merge-time gate that inspects the *resolved merge head* cannot be fooled by local state, operand spellings (`$PR_NUM`, `~/`, numbered vs bare), or shell composition (`&&`, `;`, subshells) — but each of those reachability classes must be enumerated deliberately: the 84-case suite exists because the composition surface (`cd`-rebinding, multi-invocation ordering, foreign `-R` inside quoted `--body` text, non-repo `cd`) is where false-pass and false-deny hide. Generalizing: **when a guard's correctness depends on resolving operands, test the operand-resolution lattice, not just the happy path.**

## Session Errors

This session's error inventory (compound Phase 0.5), each with its prevention:

1. **`TOTAL=$((FAIL + 1))` typo** corrupted the suite's case counter mid-development.
   - **Recovery:** the printed `PASS+FAIL != TOTAL` summary exposed it; fixed at the typo site.
   - **Prevention:** keep the end-of-suite `PASS+FAIL == TOTAL` identity check — it caught this in seconds; a suite without an accounting self-check lets a counter bug masquerade as coverage.

2. **Fixture ordering defects** (T54 cloned before `clean-b` was pushed; an accidental `init_git_repo` redefinition no-op'd a helper; T14 regressed when an arm moved).
   - **Recovery:** red suite rows pointed at the exact arms.
   - **Prevention:** after reordering fixture/scaffold helpers, re-run the suite before composing the next case; fixture helpers that look pure but sequence against remote state are order-sensitive.

3. **Edited AND committed the worktree while `scripts/test-all.sh` was running — twice.** Each time the repo-write boundary FATAL fired: it samples `[head]`/`[refs]`/worktree at first suite vs end, and any mid-run delta reads as "a suite wrote to the live repository". Two ~2h runs were spent this way.
   - **Recovery:** committed pending fixes, waited for suite children to drain, re-ran clean.
   - **Prevention:** treat a launched shard as read-only time — stage fix notes in the message buffer or a scratch file OUTSIDE the worktree (`/tmp`), never in the tree; if a fix is unavoidable, commit first and restart the run, because a dirty-at-end run is never valid evidence. Three prose reminders already exist (work §9, review, ship); this session proves prose saturation — a battery-in-flight lease + hook arm is the durable fix (below).

4. **New-hook registration surfaces discovered one shard-cycle at a time.** The hook + suite tripped, in sequence: `battery-tag-authorship` (fixture `git fetch` missing `--no-tags`), `grep-q-pipe-guard` (`producer | grep -q` inside a policy hook), `lint-trap-tempfile-ownership` (`mktemp` with no owning `trap … EXIT`), `fixture-dir-operand-assert` (41 `git -C "$work"` writes missing in-function `assert_fixture_dir`), `fixture-relative-assert` (baseline needed `--write-baseline` in the same commit), `hook-input-contract` A18 (hook sourcing `lib/hook-input.sh` must join `INSCOPE21`/`REWRITERS`), plus the pre-shard set (settings.json matcher, `.devin/config.json` twin, `devin-dispositions.tsv` row, `suite-shard-legs.tsv` + manifests, `PROMOTED_FILES` promotion — which reads `git ls-files` and is blind to untracked files until staged).
   - **Recovery:** each suite's FAIL line named its own surface; all fixed and re-verified standalone.
   - **Prevention:** the enumerated checklist belongs in `.claude/hooks/README.md` beside "Adding a hook test suite" (which covers only suite-side surfaces); every surface is a standalone suite runnable in seconds — the 2h cost was discovery latency, not test latency. A future `hook-surface-census` lint could compress file→registration closure into one check.

5. **Nested `test-all.sh` sandbox copies inherit outer-run selection env.** `test-all-orphan-log-retention` and `fanout-suite-scope` were green standalone but red inside `TEST_GROUP=affected MODE=full`: their inner `bash sandbox/test-all.sh` runs inherited `TEST_GROUP=affected`, selected zero suites, and exited 0 where the arms measured refusal paths.
   - **Recovery:** added `env -u TEST_GROUP -u MODE -u SCRIPTS_SHARD -u SOLEUR_TEST_FORCE_ALL` to both suites' sandbox invocations (empty-assignments fail rc=2 — `TEST_GROUP=` is not equivalent to unset; unsets are required, and arm-supplied `TEST_GROUP=affected` still wins since env applies later args last).
   - **Prevention:** the runner-side fix is `export -n` on the selection vars where `test-all.sh` already unsets `SCRIPTS_SHARD` (~line 1284) — "one edit at the point of coupling rather than `env -u` at N call sites," the file's own stated rationale. Suites spawning nested runners should scrub selection state exactly as they already scrub `SOLEUR_SUBAGENT`.

6. **Ambient orphans from another session's deleted worktree** tripped `orphan-process-reaper`'s AC40 safety arm (3 processes, live parent `claude` session — not mine to reap).
   - **Recovery:** `ORPHAN_SUITE_SKIP_LIVE=1` — the suite's documented seam for exactly this shared-box condition.
   - **Prevention:** check `scripts/test-all.sh --capacity` AND the live-process scan before a shard run; the seam exists because the suite deliberately refuses to signal bystanders.

7. **Post-rebase push rejected** (init commit preceded the rebase on the remote).
   - **Recovery:** `--force-with-lease` after confirming remote tip was my own commit.
   - **Prevention:** after any rebase of a pushed branch, expect `--force-with-lease`; check `git log origin/<branch>` first — lease is safe only when the remote tip is still your own commit.

8. **Rule-body and markdown-lint overages** (rule body 982B > 600B cap; MD038 pipes inside code spans in a table cell).
   - **Recovery:** trimmed prose to budget; reworded the cell.
   - **Prevention:** run `python3 scripts/lint-agents-rule-budget.py AGENTS.md AGENTS.rules.md` and the markdown linter before committing corpus/rule edits — both verdicts are seconds, not shard-costly.

## Prevention (durable, proposed)

- **New-hook checklist** → `.claude/hooks/README.md` new "Adding a policy hook" section with the ordered standalone commands (each surface's own suite), plus a pointer line in `devin-dispositions.tsv`'s header — the file every hook author must touch. Tracked by this learning; candidate for a follow-up PR.
- **Battery-in-flight lease** → `test-all.sh` writes a worktree-keyed lease inside the lock-hold region; an arm on the existing `worktree-write-guard.sh`/`guardrails.sh` (no new registrations) warns on Edit/Write/commit while a lease is live.
- **Runner-side env scrub** → `export -n TEST_GROUP SOLEUR_TEST_FORCE_ALL SOLEUR_ENUM_DEADLINE_S` beside the existing `SCRIPTS_SHARD` unexport in `test-all.sh`; the two per-suite scrubs shipped here converge onto it.
- **README roster drift** → `ship-kb-archive-gate` is registered but absent from the hook roster table; nothing asserts roster completeness — add the row (this PR) and consider a census arm (follow-up).

## Cross-References

- `knowledge-base/project/learnings/2026-09-28-an-exported-session-env-var-forked-nested-runner-behavior.md` — the identical env-inheritance mechanism (SOLEUR_SCRATCH_SESSION_ROOT → nested runners), #8940; "when N unrelated suites fail at once, look for the shared inherited precondition."
- `knowledge-base/project/learnings/2026-10-01-an-ambient-ci-variable-is-inherited-by-every-nested-runner-and-a-gate-on-it-needs-a-scrub.md` — the class again (GITHUB_EVENT_NAME), plus the fixture-relative-assert + vacuity-floor surfaces in one prior incident.
- `knowledge-base/project/learnings/workflow-issues/2026-09-19-the-shard-i-left-for-ship-was-the-one-that-read-every-file.md` — a prior new-guard PR red-on-shard on the same corpus-inclusion surfaces.
- `knowledge-base/project/learnings/2026-09-18-every-instrument-i-waited-on-was-counting-itself.md` (item: own mid-run commits trip the boundary FATAL) and `…/2026-09-19-the-explained-pin-was-columns-not-members.md` (addendum item 22, identical mid-run-commit FATAL).
- `knowledge-base/project/learnings/test-failures/2026-10-06-a-new-anti-vacuity-floor-joins-the-meta-guard-and-a-fix-pass-must-be-audited-in-every-run.md` — the `PROMOTED_FILES` contract (stage before measure; last assignment wins).
- `.claude/hooks/README.md` §"Adding a hook test suite" — the existing suite-side registration checklist this learning extends to the hook side.
- ADR-223 (per-harness hook registries + disposition ledger), ADR-207 (repo-write-boundary harm partition), ADR-240 + `scripts/suite-shard-legs.tsv` (shard registration).
- Issues: #8940, #8993, #7553, #7652, #7702, #7810, #8616, #9217 (mechanism precedents); #7383 (archive-kb untracked-discovery gap partially closed here); #10064 (motivating leak).

## Tags

ship-pipeline, kb-archival, pretooluse-hook, gh-pr-merge, merge-gate, fail-open-scope
