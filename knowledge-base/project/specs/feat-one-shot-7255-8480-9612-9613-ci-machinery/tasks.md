# Tasks — fix-ci-machinery-sweep

Plan: `knowledge-base/project/plans/2026-10-06-fix-ci-machinery-sweep-plan.md`
Branch: `feat-one-shot-7255-8480-9612-9613-ci-machinery` | PR #9635

## Phase 1 — #7255 liveness repoint

- [x] 1.1 `plugins/soleur/test/test-helpers.sh`: `make_gh_stub`/`make_gh_stub_sleep` serve `pr list` (check other consumers first); stub records argv to `$stub_dir/argv.log`.
- [x] 1.2 `plugins/soleur/test/notice-frontmatter.test.sh` + `_base-notice-frontmatter.test.sh`: TS-cron-* on new stub shape; add argv pin (contains `pr list` + `head:ci/vendor-attest`, no `run list`).
- [x] 1.3 `plugins/soleur/test/fixtures/gdpr-gate-stale/gh-stub/gh`: `run list` arm → `pr list`.
- [x] 1.4 `notice-frontmatter.sh`: rewrite `cmd_cron_run_stale` query to `gh pr list --search "head:ci/vendor-attest" --state all --limit 10 --json createdAt --jq '[.[].createdAt] | max // empty'`; drop ⚠️ block + header caveat; guards unchanged.
- [x] 1.5 `gdpr-gate.sh` :118-128 comment + `gdpr-gate/SKILL.md` :326-332 rewrite (dead-workflow literal → zero in both).
- [x] 1.6 `gdpr-gate-self-test.test.sh`: refresh stale :136-137 comment; verify parity check lands on "retired from both" arm.
- [x] 1.7 Live smoke: `GH_TOKEN=$(gh auth token) bash plugins/soleur/skills/gdpr-gate/scripts/notice-frontmatter.sh cron-run-stale` → small integer or 999, never abort.

## Phase 2 — #8480 hook reorder

- [x] 2.1 `new-scheduled-cron-prefer-inngest.test.sh`: add case (g) — `CLAUDE_PROJECT_DIR=$PWD`, `file_path=$PWD/.worktrees/feat-x/.github/workflows/<existing scheduled>.yml` Edit adding `cron:` → `allow`; control: same prefix, filename NOT on origin/main → `deny`. Run red.
- [x] 2.2 Swap the two `rel_path` case arms (basename arm first).
- [x] 2.3 Suite green.

## Phase 3 — #9612 sentinel + dedupe normalization

- [x] 3.1 `scripts/lint-gh-argv-arg.test.sh`: fixture tree (must-fire: mid-argv, post-`--jq`, continuation-joined, inside `$(…)`; must-not-fire: post-pipe `jq --arg`, `#` comments, quoted token, non-gh cmd) + verify-the-verifier + MIN_ASSERTIONS floor. Run red (no linter yet).
- [x] 3.2 `scripts/lint-gh-argv-arg.py` (mirroring `lint-workflow-errexit-capture.py` shape); fixtures green.
- [x] 3.3 Normalize 13 sites in `scheduled-zot-restart-loop.yml` (:240 :293 :432 :480 :516) and `scheduled-inngest-health.yml` (:510 :537 :566 :586 :606 :633 :1052 :1354) to `if ! VAR="$(gh … | jq …)"; then echo "::error::…"; VAR=""; fi`. Keep `search_rc` fail-closed at zot ~:391.
- [x] 3.4 Live scan green; register `scripts/lint-gh-argv-arg` + `scripts/lint-gh-argv-arg-live` in `scripts/test-all.sh` near :4599-4627.

## Phase 4 — #9613 doppler_call()

- [x] 4.1 `workspaces-luks-verify.yml`: write `doppler_call()` in the marker step (2>&1 capture → sanitized `[doppler-stderr]` diag on failure; stdout printed only on success). Route `set`/`get`-readback/`delete` + `marker_state`'s `get` through it; keep `>/dev/null` on set/delete; keep `|| { … }` handlers; absent-classify stays in `marker_state`.
- [x] 4.2 `workspaces-luks-verify-workflow.test.sh`: structural checks → `doppler_call` spellings (:1450/:1454); census `VERB` regex gains `doppler_call` (ALLOWED_SITES stays 2); `g3_sub` anchors rows 3 + 17g re-anchored; new scenarios S57 (set-fault → `[doppler-stderr]` + refusal name) + S58 (delete-fault → same) registered in `G3_EXPECTED_IDS` and folded into 17g's id list.
- [x] 4.3 Suite green end-to-end (`bash apps/web-platform/infra/workspaces-luks-verify-workflow.test.sh`).

## Phase 5 — verification

- [x] 5.1 `bash -n` all edited shell bodies; run: notice-frontmatter ×2, gdpr-gate-self-test, hook suite, lint-gh-argv-arg pair, workspaces-luks-verify-workflow.
- [x] 5.2 `git diff` sweep for stale comments; PR body updated with the four `Closes #` lines.
