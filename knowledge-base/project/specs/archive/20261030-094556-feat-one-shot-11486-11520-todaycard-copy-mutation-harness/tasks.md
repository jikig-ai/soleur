# Tasks: today-card send-error copy, live messages UPDATE-policy check, shared mutation harness

Plan: `knowledge-base/project/plans/2026-10-29-chore-todaycard-send-copy-and-mutation-harness-plan.md`
Branch: `feat-one-shot-11486-11520-todaycard-copy-mutation-harness` | Draft PR 11566 | Closes #11486, Closes #11520

## Phase 1: Live policy read (read-only)

- 1.1 Run the plan's A.1 command (Doppler prd, `BEGIN READ ONLY; ... ROLLBACK;`, DSN never printed); capture policy names, cmd, roles, permissive flag, RLS flags only.
- 1.2 Post the result as a comment on #11486; keep a one-line summary for the PR body.
- 1.3 Branch on the verdict: present -> done; unverified (blocked) -> `Ref #11486` and SQL in the PR body; missing -> file one P1 issue (`priority/p1-high`, `type/bug`, `domain/engineering`), write a learning, NO migration, NO 403-copy change.

## Phase 2: Copy and `reason` field (tests first)

- 2.1 RED: update `use-action-send.test.tsx` (six states, both `reason` values, absent, unknown, non-string), `today-card.click.test.tsx` (503 regex; new Edit-409 test, plus 500 and other-409 keep `Edit failed (NNN)`), `send-route.replay.test.ts` (`reason: "expired"` in the `toStrictEqual` body; `future_clicked_at` body assertion).
- 2.2 GREEN: `decide-replay.ts` exports `StaleReplayReason` BELOW `REPLAY_MAX_AGE_MS`; `refuseStaleReplay` adds `reason`; `failureCopy` splits on `json.reason` (type-only import); `today-card.tsx` edit branch parses the 409 body (with a `.catch`) and sets the approval string; update the stale 503 comment above `failureCopy`.
- 2.3 Run AC4 and AC5 greps; `tsc --noEmit` in the same command as vitest (touched files).
- 2.4 One phone-width screenshot of the card error line and the modal `role="alert"` line.

## Phase 3: Harness extraction (pure refactor)

- 3.1 Capture ledger labels of a full pristine run of each probe suite to the scratchpad.
- 3.2 Create `scripts/lib/mutation-harness.sh` (mode 100644, functions only, `mh_caught`, `mh_floor <MIN_FIXTURE> <MIN_BATTERY> <suite-arg>`); replace the duplicated blocks in both suites; keep the five one-liners, globals, h1 to h5, m-rows, `MIN_*`, `LEDGER MISMATCH` and the banner in each suite; source via `$REPO`, exit 4 if missing.
- 3.3 Re-run both suites; diff labels (identical), `MIN_*` unchanged; `bash -n` and shellcheck on the lib; a `--no-battery` run exits 0.

## Phase 4: Scorer controls and declarations

- 4.1 Add four capture-only controls and the teeth row to each suite; `mutate_run` calls `mh_caught`.
- 4.2 Raise `MIN_BATTERY` by exactly 5 per suite (from the label diff).
- 4.3 Hand-run AC9 (a), (b), (c) against scratch copies of the lib; both suites red each time; restore.
- 4.4 Add `scripts/lib/mutation-harness.sh` as one line to the 11211 and 11265 `AFFECTED_*_PATHS` arrays in `scripts/lib/test-affected-paths.sh`. Do not touch `scripts/test-all.sh`.
- 4.5 File the single deferral issue "#11520 remainder: items 3 to 7" (label `deferred-scope-out`, roadmap milestone).

## Phase 5: Pre-push ratchets and ship prep

- 5.1 `bash scripts/lint-supabase-deprecated-endpoints.sh`; `bash tests/scripts/test-lint-supabase-deprecated-endpoints.sh`
- 5.2 `bash scripts/lint-betterstack-emitter-read.sh`; `bash scripts/lint-betterstack-emitter-read.test.sh`
- 5.3 `bash scripts/test-affected-kb-consumers.test.sh`; `bash .claude/hooks/grep-q-pipe-guard.test.sh`
- 5.4 `bash scripts/followthrough-exec-bit.test.sh`; `bash tests/scripts/test-argv-bearer-sweep.sh`; `bash scripts/lint-orphan-test-suites.sh`; `python3 scripts/lint-guard-contract.py <plan>`; `bash plugins/soleur/skills/ship/scripts/technical-ruling-gate.sh --branch`
- 5.5 Check the affected-paths audit (`scripts/ci-pr-affected-audit.accept.tsv` / replay ratchet) for the lib edit. `lint-skill-body-budget.py` is not applicable (no skill body edit).
- 5.6 Commit by explicit pathspec (never `git add -A`); commits end with `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`; PR body: `Closes #11486`, `Closes #11520` on separate lines, no "fix" next to an issue number, ends with the generated-with line.
