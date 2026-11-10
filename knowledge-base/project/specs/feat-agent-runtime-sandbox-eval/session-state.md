# Session state: feat-agent-runtime-sandbox-eval (2026-11-10)

Plan: `knowledge-base/project/plans/2026-11-09-feat-agent-runtime-sandbox-eval-injector-first-plan.md`. Tasks: `tasks.md` here. CTO rulings: `decision-challenges.md` here (F-a..F-g, R1..R35, D1..D4; R28..R35 added 2026-11-10).

## Done (verified)

- Phase 1 complete. All nine arms built (`apps/web-platform/test/infra/egress-injector-spike/`: `lib/bringup.sh`, `lib/arms.sh`, `lib/iron-audit.py`, `probes/session-up.sh`, `probes/sdk-egress-driver.mts`, `probes/hook-client.mjs`), hook R28 tunnel guard and per-session TTL with hermetic rows (91 tests green).
- CI run 42816918299 (commit 8b0d247411) measured **GO**: criteria 1 to 9 pass. Raw results committed as `injector-spike-results.json`; `print-verdict.sh` prints `verdict=GO`, exit 0. Later commits touch only docs and the brainstorm skill, so the results describe the current spike code.
- Filed #12585 (`type/security`, Phase 4): production `createCanUseTool` denies the SDK's `SandboxNetworkAccess` request as an unknown tool. #11637 is blocked by #12585 (verified).
- Branch-owned CI reds fixed (brainstorm SKILL.md byte ceiling, `gh pr list -L`, CTO link text). Remaining reds are main-side with open fixes: ADR-276 MD032 (#12559), inngest pin v1.1.72 (#12562); re-merge main after they land.

## Superseded result (2026-11-10, later the same day)

- A defect found after the GO run: the REST canonical action dropped literal path segments, so `POST /repos/o/r/pulls` and `POST /repos/o/r/issues` with the same body shared a hash. Fixed in `policy.mjs` (hermetic row, RED before the fix) and probed in criterion 7. The GO of run 42816918299 predates the fix; the re-measure on the fixed head replaces `injector-spike-results.json`.
- Task 2.2 in flight: eight Guard mutation runs dispatched on `spike-mut/*` branches (base 6b9a0cb43b, scratch worktree `/var/tmp/spike-mut-wt`; remove both when recorded). Guard 3 row 4 measured locally: caught (FAIL DOCKER_UNAVAILABLE, exit 1, INCONCLUSIVE).

## Phase 2 done (2026-11-10)

- Final GO: run 42823659776 (head 3396c15847): criteria 1 to 9 pass; `injector-spike-results.json` and `injector-spike-results.md` committed. Guard rows: 8 caught, 1 equivalent survivor; throwaway `spike-mut/*` branches and the scratch worktree removed.

## Next

1. Phase 3: ADR-324 via `soleur:architecture` (status `adopting`, the plan's "Decision record (ADR-324)" content, `## Measured outcome — injector` citing the results note, `soleur:architecture assess` for the NFR register); the GO addendum to ADR-311 worded "on merge of PR #12518"; edit #9845 (linked section) and #9859 (Arm D widened with the Phase 4 trial requirements); file the demand-side session telemetry issue (Phase 4 milestone); edit `spec.md` (FR3 to the sibling PR, criteria mapping 7 to 1-9, TR1 and TR2 wording, the 36/42 baseline, the verdict set); leave the roadmap handoff note.
2. Phase 4: tasks 4.1 to 4.4, then `soleur:review`, `soleur:compound`, `soleur:ship`. Re-merge main once #12559 (ADR-276 MD032) and #12562 (inngest pin) land.
