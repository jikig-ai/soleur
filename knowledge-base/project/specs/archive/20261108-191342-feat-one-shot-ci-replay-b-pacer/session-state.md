# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-11-08-ci-replay-b-pacer-plan.md
- Status: complete

### Errors
- No spawn tool inside the planning subagent: all prescribed fan-outs ran sequential-fallback inline; technical rows recorded `pending - assumed:` in decision-challenges.md (batched CTO gate follows).
- precommit simulation guard blocked two git commits; repaired via separate `git add` calls.

### Decisions
- Item B reframed by measurement: pristine row_scan_ops ~4.8s — the 47.3s site cost is mutant-side runaway. Plan: per-scan give_up inside cpu(), cheapest-condemner ordering + early exits, text axis ~16KB→~256KB, tighter line-event cap.
- Load-bearing constraints kept: 400k-path corpus and 150k-line baseline untouched; site 350 unchanged.
- row_sym cheap win: parameterize run_sut `timeout 30` → `REPLAY_SUT_TIMEOUT`, row_sym sets 10s (~20s drop on site 225).
- Item A: re-price -a 1033094→160004 + drop ledger-inconsistent exemption row; regen via `--incremental --durations`. -b/-c stale prices out of scope (#11679 umbrella).
- Adjacency: PR #12412 bumps DECLARED_TOTAL→477 / FLOOR_ASSERTIONS→1115 and +1 ordinal shift — re-verify by name after rebase.

### Components Invoked
- soleur:plan, soleur:deepen-plan (sequential-fallback roles inline)
- regenerate-shard-manifest.py --incremental --durations (dry-run), collision-precheck.sh, lint-guard-contract.py
- instrumented /tmp/row_scan_ops_i.py timing run
- Commits: 4e3e61b655, d4ac647af4

## Operator Constraints

- constraint: Repo edits only in .worktrees/ via worktree-manager (bare root CWD).
- constraint: Merge queue governs; arm `gh pr merge --auto` (no --squash). Queued branches reject pushes; dequeue via GraphQL dequeuePullRequest, push, re-arm.
- constraint: The queue ejects entries between batches with no warning; re-arm when OPEN/CLEAN and not queued.
- constraint: Ratchet discipline: edge declarations only for genuinely-read files; anchor-keyed accept rows (12-hex sha256 of whitespace-collapsed line, ordinal in canonical read order) with one of the six typed kinds; verify locally with `python3 -I scripts/ci-pr-affected-replay.py ratchet` before pushing.
- constraint: Non-goals: no .github/workflows/* edits, no oracle-lane work (#12393 sibling, #12418 filed), no #9729 stage-4 activation, no CI_PR_AFFECTED/PR_AFFECTED_LOCKED changes, -b/-c stale prices out of scope (#11679 umbrella).

## Technical Rulings
- cto_spawns=1 (batched, 9 rows): all assumed defaults confirmed, zero dissents; rows rewritten to `Ruled by CTO agent, 2026-11-08` in decision-challenges.md.

## Review Phase (step 4, sequential-fallback)

Panel executed inline — no subagent spawn path in this environment. Seats run
in order: git-history, pattern-recognition, architecture, security,
code-quality, test-design, shellcheck (semgrep substitute — bash-only diff),
structural-enumeration. Tier: `none` (plan-declared + scope-out); class `code`.
Skipped per tier-`none` trigger-gating: performance-oracle,
data-integrity-guardian, agent-native-reviewer (no path-map match); semgrep-sast
(bash-only → shellcheck, clean); user-impact/gdpr/anti-slop/rails/migrations.

Independent verifications: `shellcheck -S error` clean; leg-a `--rows 1-158`
→ 794 assertions, 158/158 killed (FLOOR math 1112-476+158=794 consistent);
corpus-weight-budget 14/14; shard-manifest 50/50; re-price run IDs
42447940669/42442159415/42439386564 live-verified as merge_group successes.

### Rulings (no operator asks — technical, ruled per evidence)

1. **P1 merge conflict** — `mergeable: CONFLICTING`/`DIRTY` since #12377 landed
   `FLOOR_ASSERTIONS=1127` + `DECLARED_TOTAL=484`. One conflict hunk (the floor
   line). Resolution is determinate: merge main, `FLOOR_ASSERTIONS=1129`
   (1127+2 unconditional), re-measure per the comment contract; DECLARED_TOTAL
   auto-merges to 484 (we add no `^mutate` sites) and leg-c `--rows 317-484`
   auto-merges — consistent. tasks.md 3.4 prescribes this recipe (written for
   #12412; #12377 landed first with the same class). #12412 itself is now stale
   vs main's 484/1127 — whichever lands second re-measures. DIRTY suppresses
   every `pull_request` check — the PR's green set is CodeQL/CLA-only evidence.
2. **P3 "shrink-only" claim false** — `run_sut` comment (:249) and row comment
   (:759) assert "never widen"; `REPLAY_SUT_TIMEOUT=3600` passes the regex and
   widens the bound 120x. Ruling: clamp `(( tmo > 30 )) && tmo=30` OR reword
   both comments. pr-introduced → fix-inline (Step 5).
3. **P3 census spelling-limited + self-satisfying** — `REPLAY_SUT_TIMEOUT=[0-9A-Za-z]+`
   misses `$VAR`/`"10"`/`$((x))` setters; the expected-set literal contains all
   4 tokens so deleting a real site stays green (harmless direction — pinned
   for the grow direction only, which is its purpose; the grow direction works).
   pr-introduced → fix-inline (Step 5), e.g. `^[[:space:]]*REPLAY_SUT_TIMEOUT=`
   line-anchor.
4. **P3 pre-existing note** — `mutant_outcome` invokes `"$row"` directly
   (:3432), so `row_scan_ops` carries no wall-clock bound: a hang inside ONE
   `scan_text` call emits no line events (settrace blind) and give_up only
   checks between reps → bounded only by the CI job timeout. Pre-existing,
   narrowed but not closed by this PR. Recorded; Step 5 may wrap the row
   invocation in `timeout` or document as accepted.
5. `/usr/bin/timeout` in the tmostub shim — fails loudly (rc 127≠124) if absent;
   consistent with suite GNU-isms. wontfix-grade note.

give_up invariant verified: every abort path returns elapsed/reps strictly
> give_up ≥ the caller's verdict bound → over-bound, never a pass. Ordering,
per-leg checkpoints, cap margin (16*len vs pristine 12.125/byte at every
fixture), RUN_ENV last-wins, and the 16x text window all verified clean.
