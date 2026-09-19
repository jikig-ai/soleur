# Session State

## Plan Phase
- Plan file: /data/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-auto-inngest-pin-bump/knowledge-base/project/plans/2026-09-19-feat-auto-bump-inngest-bootstrap-pin-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)
- Issue: #8359 (OPEN; collision re-probe post-planning clean — no linked/open/merged PRs on scope)

### Errors
None. No fatal command errors; several bounded searches truncated to overflow files and were resolved by narrower greps/reads.

### Decisions
- Digest cross-check is tag-conditioned: sign step runs under `mirror_only` and re-signs the dispatched tag, so a non-max backfill legitimately produces signed_digest != semver-max digest — script compares only when signed_tag == target (Guard 1 rows 5/5b, task 1.2.3).
- Rewrite anchor verified: exactly 4 compound literals `soleur-inngest-bootstrap:vX.Y.Z@sha256:<64hex>` (2/file at cloud-init.yml:736,742 + cloud-init-inngest.yml:1358,1402); ZIREF sites carry variable prefixes ($ZURL, $ZOT_EP) so the script substitutes the suffix only, with a per-file ==2 replacement-count rail.
- PAT-absence assert: literal `GH_TOKEN_PAT`/`secrets\.[A-Z_]*PAT` (bare `PAT` false-positives on `dispatch`) — Guard 2 row 3.
- Path: `.github/scripts/` is canonical (no `scripts/bump-inngest-bootstrap-pin.sh` exists).
- Auto-merge premise verified: cloud-init-inngest.yml:1386-1387 records AP-016's revoked GHCR read PAT; `allow_auto_merge`/`allow_squash_merge` both true on repo.

### Components Invoked
- `plan` skill (inline — research, sharp-edges catalogue, plan-review panel, Save Tasks); `plan-review` + `deepen-plan` (inline, sequential-fallback — `Reviewed-Coverage: sequential-fallback`)
- Commits: e50cdeaed (plan + tasks.md), 86dd751ef (deepen-pass verification record + review corrections)

## Work Phase
- Status: implementation complete; verification green (2026-09-19)
- Delivered: `.github/scripts/bump-inngest-bootstrap-pin.sh` + fixture suite `test-bump-inngest-bootstrap-pin.sh` (126 assertions, MIN_ASSERTIONS=45 floor); `build-inngest-bootstrap-image.yml` gains `build.outputs.{tag,digest,mirror_status}` + `bump-cloud-init-pin` job (App-JWT mint, installation 122213433); ADR-230 (provisional); `model.c4`/`views.c4` write-back documented on the `github -> soleurMarketplace` App-write edge — LikeC4 rejects self-relations ("Invalid parent-child relationship"), so `github -> github` is unrepresentable.
- Verified: new suite 126/0; `run-all.sh` ALL PASS (12 suites ≥ MIN_SUITES=11); `cloud-init-inngest-bootstrap.test.sh` 160/160 (pins untouched); c4-code-syntax + c4-render vitest 23/23; `c4-model-freshness.test.sh` 3/3 (model.likec4.json regenerated, byte-fresh); lint-shell-trace-credential-refusal clean (xtrace refusal precedes every traced command incl. `export LC_ALL=C`); `bash -n` both scripts; workflow YAML parses.
- Deferred by design: AC14 end-to-end proof — first post-merge `vinngest-v*` publish (workflow can't be dispatch-tested from a feature branch); recorded for PR body.

### Errors
- Harness bugs fixed during RED→GREEN: `--author` misplacement in `push_branch_to_origin`; `env MOCK_GH_MERGE_FAIL=1 run_bump` (env can't call a bash function); stub-state accumulation across fixtures; sed `\|` alternation-vs-literal in the gh stub; `export LC_ALL=C` traced before the xtrace refusal (lint Rule A) — moved below it.
- `github -> github` self-edge rejected by LikeC4 — fell back to extending the App-write edge description (plan-sanctioned).

## Review Phase (in progress)
- Mode: local. Seats run so far: design-validity + architecture-strategist (sequential). Remaining panel (9 seats) pending on the settled diff.
- Findings applied (all verified independently before fixing):
  - P1: bump job had NO GHCR auth — package is private, build job's docker login doesn't cross job boundaries → every live bump would die at `crane digest`. Fixed: `packages: read` + `docker/login-action` in `bump-cloud-init-pin`.
  - P2: merge arm conditioned on `SIGNED_TAG == TARGET && MIRROR_STATUS == ok` (mirror_status attests the triggered tag, not the target). Same gate on PR-body hold note + summary.
  - P2: `--limit 200` on the supersede `gh pr list`; pr-list failure now warns rather than silently degrading to `[]`.
  - P2: `soleur/inngest-pin-` added to `BOT_PR_HEAD_PREFIXES` (watchdog rot-scan) + 3 tests.
  - P2: crane-defer — digest unresolvable while signed≠target → `result=skipped` (in-flight publish race), `resolve` fatal only when signed==target.
  - P2/P3: inline App-JWT mint extracted to `.github/actions/mint-soleur-ai-app-token` (4th copy crossed threshold).
  - P3: dead `--dry-run` removed; `command -v gh` assert; `grep -oE | wc -l` counts; `.author.login // .commit.author.email` tip-author (no extra fetch); summary block simplified; stage vocab aligned (`mint` = workflow-level, not a script stage).
- Re-verified: fixture suite 153/0 (MIN_ASSERTIONS=60); run-all.sh ALL PASS; drift guard 160/160; watchdog vitest 63/63; shellcheck clean; workflow+action YAML parse.
- Docs synced: ADR-230 §3/§5/§6 + Verification; tasks.md Phase 5; plan §dry-run note.
- Fixture-safety remediation (lefthook test-all run under sibling contention): the new files tripped three corpus guards. Fixes, all verified:
  - `fixture-env-adoption` [UNACCOUNTED] → suite now sources `plugins/soleur/test/lib/git-fixture-env.sh` (arms the #7833 tripwire) and calls `git_fixture_env "$TMP" || exit 2` after mktemp. Root cause of the lefthook failures: inherited `GIT_AUTHOR_*`/`GIT_COMMITTER_*` re-authored fixture commits as the developer; the helper scrubs/pins identity. Proven: suite 153/0 under deliberately injected dev identity env.
  - Script now pins `GIT_AUTHOR_*`/`GIT_COMMITTER_*` to the bot at env level — the "commits authored as soleur-ai[bot]" contract no longer depends on ambient caller env.
  - `fixture-relative-assert` (5 sites): redirects now write directly to `$GITHUB_OUTPUT`/`$GITHUB_STEP_SUMMARY` (CI_SINK_VARS name exemption — aliases read as possibly-relative); `write_fixture_cloud_inits` carries `assert_fixture_dir "$dir"` (canonical byte-identical copy inlined).
  - `fixture-dir-operand-assert` (7 sites): `: "${REPO_DIR:?...}"` empty-operand guard after the `cd && pwd` resolution.
  - Re-verified: suite 153/0 (clean + contaminated env + run-all.sh ALL PASS); adoption 25/0; relative 62/0 (baseline unchanged at 1526/294 — sites cleared, not re-baselined); operand 71/0; drift guard 160/160; watchdog vitest 63/63; shellcheck clean.
