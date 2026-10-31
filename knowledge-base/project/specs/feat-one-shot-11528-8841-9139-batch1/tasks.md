# Tasks — feat-one-shot-11528-8841-9139-batch1

Plan: `knowledge-base/project/plans/2026-10-31-infra-inngest-batch1-guard-deadletter-posture-plan.md`
Issues: Closes #11528, #8841, #9139 (epic #10390 batch-1)

## Phase 1 — Premise sync

- [ ] 1.1 `git fetch origin main` and sync the worktree forward (3 commits behind) so `apps/web-platform/test/infra/inngest-luks-key-probe-alert.test.sh` is present locally.
- [ ] 1.2 Re-run `gh issue view 11653 --json state`; if it landed, re-baseline the wrong-volume guard inputs on re-push (race note, plan Risks).

## Phase 2 — WS-A: #11528 guard hardening

- [ ] 2.1 Rewrite `apps/web-platform/test/infra/inngest-luks-wrong-volume-alert.test.sh` onto sibling conventions: `sql_local`+`tr -d` extraction → `WRONGVOLUME_CANON` equality; `res_block`/`param()` pins (exploration + alert + escalation + runbook); `VAR_BLOCK` opener count==1; `PRESENCE_ROWS`/`MUT_ROWS` constants; `_red_verdict`/`mutate_green`/`mutate_floor_red`; negative `count|for_each|lifecycle|ignore_changes` rows; scrub-immunity row over `vector.toml`.
- [ ] 2.2 Add the new mutation rows per Guard 1 matrix (decoy heredoc, decoy var block, commented `paused`, `count(*)`→`0`, source repoint, `WHERE…BETWEEN` drop, operator/value flip, window widens, lifecycle/for_each/count add, `$$` escape, inline tautology, runbook-in-comment, floor self-mutation, ≥2 must-PASS).
- [ ] 2.3 Update the file's header contract text (what it now proves).
- [ ] 2.4 `.github/workflows/infra-validation.yml`: `env -u MUT_SKIP -u LUKS_GUARD_TF -u LUKS_GUARD_VARS -u LUKS_GUARD_WF` on the wrong-volume run line; `env -u MUT_SKIP -u KEYPROBE_GUARD_{TF,WF,FLIP,CI,RB,VT}` on the key-probe run line.
- [ ] 2.5 `bash apps/web-platform/test/infra/inngest-luks-wrong-volume-alert.test.sh` → `0 failed`; `env MUT_SKIP=1 bash …` → `0 failed` (AC1–AC6).

## Phase 3 — WS-B: #8841 once-per-replay report

- [ ] 3.1 Move `reportSpawnDeadLetter` in `persistFailure` to after the `persist-failure` try/catch, before `return`; update the ordering comment (`agent-on-spawn-requested.ts`, AC8).
- [ ] 3.2 Add replay regression test(s) in `agent-on-spawn-lifecycle.test.ts`: `runLikeInngest`-driven `agentOnSpawnRequestedHandler` to a `persistFailure` path (no-notify arm required; notify arm if `check-runtime-pause` is reachable with existing fakes), asserting `deadLetters().length === 1` and `invocations >= 2` (AC9).
- [ ] 3.3 `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/agent-on-spawn-lifecycle.test.ts` green.

## Phase 4 — WS-C: #9139 ledger amendment

- [ ] 4.1 Amend `connections[6]` in `scripts/encryption-posture-ledger.json`: `enforced_at` += `app/api/inngest/route.ts (serveOrigin: SERVE_HOST)`; `tls`/`does_not_defend` model the two hops explicitly (AC10).
- [ ] 4.2 `python3 scripts/lint-encryption-posture.py` and `bash scripts/lint-encryption-posture.test.sh` green.

## Phase 5 — Close-out

- [ ] 5.1 `gh issue create` the family remainder (comment/decoy extraction + env-pin spread across remaining MUT_SKIP-idiom guards, naming each file) (AC12).
- [ ] 5.2 Verify ACs incl. AC11 residual-zero grep and AC14 diff-scope check; PR body `Closes #11528` / `Closes #8841` / `Closes #9139`.
