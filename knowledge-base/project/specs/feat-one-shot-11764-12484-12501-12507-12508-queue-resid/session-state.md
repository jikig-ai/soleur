# Session State

## Plan Phase
- Plan file: /data/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-11764-12484-12501-12507-12508-queue-resid/knowledge-base/project/plans/2026-11-09-fix-merge-queue-residual-batch-plan.md
- Status: complete

### Errors
None blocking. Notes: (1) `precommit-guard.sh` exits 0 as a validator only — the commit itself was run separately after the guard passed. (2) Every prescribed parallel fan-out (research agents, domain leaders, SpecFlow, plan-review panel, deepen-plan per-section/review agents, CTO ruling spawns) was discharged **sequentially inline** — no Skill/Task/spawn tool exists in that seat; disclosed as `sequential-fallback` in the plan's Enhancement Summary and in `decision-challenges.md`'s header caveat (ship-phase should spawn the real CTO to re-confirm the ruling rows). (3) Plan-review ran as a focused inline self-review rather than the multi-agent panel, for the same reason.

### Decisions
- **#12508**: explicit `enqueuePullRequest` (no `jump`) in `bump-inngest-bootstrap-pin.sh` after the `--auto --squash` arm, as the already-minted soleur-infra App token — `update-branch` rejected (re-BEHINDs on next main advance), drift-check hush rejected (hides a correct red); ADR-270's "self-enqueue" claim falsified by #12489's live `isInMergeQueue: false` / BLOCKED measurement → ADR-270 addendum is a plan deliverable.
- **#11764**: three-arm fix — repo-owned producers get traps/`TMPDIR`-at-owned-sandbox (test-helpers `export TMPDIR` is the single-lever change), spawned agents get `env.TMPDIR = claudeTmpDir` in `agent-env.ts` (routes external `srt-*`/`claude-http-*` producers under `/tmp/.cs`), and `tmpfs-guard.sh` gains a `.cs` owned-base age arm (48h floor; ADR-250's shared-`/tmp` heuristic-reap rejection does not apply to a repo-owned base) → ADR-250 addendum.
- **#12507**: adopt the issue's architecture-strategist ruling — correlate the flagged head's `merge_group` ci.yml run via existing `fetch_runs`/oid-join machinery and age from `run.created_at`; old head with no run still files. Diff confined to the run body; rebase vs PR #12495 expected.
- **#12501/#12484**: strict mirrors of landed precedents — `EVENT_MSGS_JSON`+`POLICY_MSGS` concat at the four sibling reader sites (anchored regex literals byte-identical so regex-parity stays green) and the #12480 `PR_BASE_REF`→`refs/heads/` fetch→merge-base three-dot shape into `ci-pr-selection.sh`; pinned-shape test snapshots (`test-apply-github-infra-mint-shape.sh`, sentry adoption-guard count) updated in-diff.
- Premise validation held for all five issues (all OPEN; only open PR naming them is #12510, this pipeline's own draft); collision precheck, cited-file existence, and ADR-corpus checks all verified on `origin/main` 2026-11-09.

### Components Invoked
- `soleur:plan` SKILL.md — full phase pipeline inline (premise validation 0.6, minimality 0.6b, skeleton 0.7, research 1–1.7.5, scope-check 2.4, domain review 2.5, user-brand 2.6, IaC 2.8-skip, observability 2.9, ADR 2.10, guard-contract 2.12, templates, sharp-edges verification, plan-review fallback)
- `soleur:deepen-plan` SKILL.md — halt gates 4.6/4.7/4.8/4.9/4.10/4.11 (`lint-guard-contract.py` green)/4.12/4.13 verified inline; Enhancement Summary + AC refinements applied
- `plugins/soleur/agents/engineering/cto.md` — Rule-interface rubric applied inline for five `technical` ruling rows (recorded in `decision-challenges.md` with the no-spawn caveat)
- Scripts: `collision-precheck.sh` (5×), `precommit-guard.sh` (2×), `lint-guard-contract.py`, `markdownlint-cli2`
- Artifacts: plan file + `specs/feat-one-shot-11764-12484-12501-12507-12508-queue-resid/{tasks.md,decision-challenges.md}` — commits `98b7af6a4a` + `498de75af9`, pushed to origin

## Operator Constraints

- constraint: Fix all five issues (11764, 12484, 12501, 12507, 12508) in ONE PR.
- constraint: Do not touch work claimed by a parallel session (12403/PR-12498, 12269/PR-12495, 12008/PR-12497, 12288-12290/PR-12462, 11544/PR-12476, 12365/PR-12438, 9729 NO-GO, 12418 merged, 12506 pin-bump PR-12489).

## Pipeline Position (implementation committed)
- Branch feat-one-shot-11764-12484-12501-12507-12508-queue-resid, draft PR #12510, tip b817157324 pushed to origin.
- Six commits: 0838d0a436 (#12484), d8e834a6e3 (#12501), 2ed4f3fcbd (#12507), c284ce6988 (#12508), 0c50749c66 (#11764), b817157324 (docs/tasks).
- All five issues implemented via Tier-B fan-out (5 subagent_general seats, all green); agents report per-suite greens + ratchets green.
- Affected gate (gate-or-skip.sh) running background shell 0bcd0e at commit time.
- GDPR gate skipped: 0 diff paths match canonical regulated-data globs.
- NEXT: review panel (10 seats, parent-spawned; subagents cannot nest on Devin) → resolve P1-P3 → fix-round → qa (no UI Test Scenarios — likely skips) → compound → ship → DONE.
- Ship notes: PR body needs 5x `Closes #N` own-line + census histogram (tmp-census.md) + blast-radius line; KB archive gate (archive-kb.sh) applies to plans/specs at Phase 6.45; sibling PR #12495 also edits merge-queue-stall-check.yml + test — expect rebase; PR #12489 pin-bump still open (#12506 owner).
- Commit contract: `git -C <worktree>` for all commits (envelope has no cwd), literal absolute paths only, `git add` in separate call from commit, run precommit-guard.sh (PLUGIN_ROOT/scripts/) before each commit; configured identity jean.deruelle@jikigai.com (CLA-allowlisted) — no -c overrides, never devin-bot.
- PLUGIN_ROOT=/home/jean/.local/share/devin/cli/plugins/cache/github.com_jikig-ai_soleur_plugins_soleur-5a09ea60/0.0.0-unversioned

## Review panel result (10 seats): SHIP-WITH-FIXES
Verdicts: SHIP (code-simplicity, performance) / SHIP-WITH-FIXES (security, observability, architecture, data-integrity, agent-native, test-design, code-quality, pattern-recognition).
Fixer subagent 93230f6d is applying round-1 fixes (sentinel test row, verified delete count, timeout 30 fetch, timeout 60 gh pr view, notice reword, agent-env comment, ack-attribution comments, plan phrasing).
Lead already applied inline: `_FRESH_TOP[__built__]` fail-closed check in scripts/tmpfs-guard.sh reap_owned_cs_base (~:929).

## Consolidated fix list — round 2 (apply before merge)
1. P1 scripts/ci-pr-selection.test.sh: `BASE_ROWS=4629` -> `4591` (floor mis-derived; deterministic red).
2. P1 scripts/ci-pr-affected-audit.accept.tsv: add anchor-keyed accept row for `7811c4a3878a/1` (affected-index-ratchet new-pair red; precedent row at accept.tsv:721 `bda4d6953877/1`).
3. P2 agent-env.ts: direct buildAgentEnv unit assertion in agent-env.test.ts (TMPDIR===claudeTmpDir + ambient-TMPDIR arm); tighten comment (tmpfs mask; agent-outer-wrap.ts:458 re-pins TMPDIR=/tmp); consider `mkdirSync(claudeTmpDir,{recursive:true,mode:0o700})`.
4. P2 tmpfs-guard.sh: `TMPFS_GUARD_CS_BASE` constrain to "$TMP_ROOT"/.cs via case pin (skip arm otherwise).
5. P3 cs arm: `.soleur-owned` parity continue; rung2 comment reword (RETURN trap covers early returns not signal/errexit); tmp-census.md "shape-pinned" -> variable-bound rm -rf; test comment nits (row_advanced_base, C47 rationale); cs arm max_reap cap optional.
6. P3 defer: cron buildSpawnEnv TMPDIR residual -> document in PR body; Reaper-2 _FRESH_TOP sentinel backfill + `.cs` protect-list -> follow-up issue; oracle-lane timeout divergence -> record deliberate in ci-oracle-lane.md.
7. Ship: PR body = 5x `Closes #N` own-line + census histogram + blast-radius line (workflows inert until next matching push; pr-selection lever dark); expect rebase vs PR #12495 hunks.

## Outstanding
- Affected gate: background shell 0bcd0e (check before ship).
- After fixes: commit+push, verification pass over fix range, qa (skip - no UI), compound, ship -> DONE.
