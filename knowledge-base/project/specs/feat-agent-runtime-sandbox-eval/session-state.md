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

## Next

1. Task 2.2: run each by-hand Guard row once (Guard 1 rows 1 to 5, Guard 2 rows 2, 6, 8, Guard 3 row 4) as a mutated copy dispatched through `egress-injector-spike.yml` (`workflow_dispatch` on a throwaway branch, one mutation per branch; Guard 3 row 4 can run locally with `docker` shadowed on PATH). Record which reddened, the run URL and the message. Expected survivors to label: Guard 1 row 1 (the Read tool refuses `/proc` files and bwrap hides `/proc`), Guard 2 row 8 (the hook still rejects; check what it observes).
2. Task 2.3: write `injector-spike-results.md` (three plain opening sentences, per-criterion verdicts and raw outcomes, labels, re-measure trigger, `canonical_action` per write class, per-client pending-message record (R15: git shows only "remote end hung up"), NO_PROXY arm A finding, `gh` carriage finding, confused-deputy residual, CHECK change for #11637, the findings list in `tasks.md`, #12585).
3. Phase 3 (ADR-324 via `soleur:architecture`, GO addendum to ADR-311 worded "on merge of PR #12518", issue edits #9845 and #9859, demand-side telemetry issue, `spec.md` edits, roadmap handoff note), then Phase 4 and the review, compound and ship pipeline.
