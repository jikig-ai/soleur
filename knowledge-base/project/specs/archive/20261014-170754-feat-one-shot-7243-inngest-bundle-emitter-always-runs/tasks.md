# Tasks: fix build-inngest-config-bundle mirror emitter (Ref #7243, epic #10205)

Plan: `knowledge-base/project/plans/2026-10-14-fix-inngest-config-bundle-mirror-emitter-always-runs-plan.md`

## Phase 0: RED first

- 0.1 Write `plugins/soleur/test/inngest-config-bundle-mirror.test.sh` (structural leg, behavioural arms 1-7, mutation battery, tight `MIN_ASSERTIONS`).
- 0.2 Run it against the UNCHANGED workflow; capture the failing verdict lines for the PR body.

## Phase 1: The step (`.github/workflows/build-inngest-config-bundle.yml`)

- 1.1 Add `id: zot_mirror`; change the step `if:` to `steps.docker_build.outcome == 'success'`; keep `continue-on-error: true`.
- 1.2 Add `BRIDGE_OUTCOME: ${{ steps.zot_bridge.outcome }}` to the step env.
- 1.3 Add `degraded()` (outputs, one `::warning::`, one prose summary bullet, `exit 0`) with the literals on single lines and nowhere in comments.
- 1.4 Branch on `"${BRIDGE_OUTCOME:-}" != "success"` before any crane work.
- 1.5 Route the install group (`&&`-chained) and the `retry crane copy` with `|| degraded`; write `mirror_status=ok` last.
- 1.6 Rewrite the step comment (the #6416 reason; sibling-step caveat; pointer to the suite). Leave `CRANE_VERSION` / `CRANE_SHA256` lines byte-identical.
- 1.7 `actionlint` the workflow; `bash -n` the extracted body.

## Phase 2: Make the suite GREEN

- 2.1 Stubs: `curl`, `sudo`, `sha256sum` (reads stdin), `crane` (per-subcommand knobs and counters), `sleep`; log to files, never stdout.
- 2.2 Mutation battery rows 1-9 with a `! cmp -s` guard per mutant; two must-pass variants; wrong-extractor harness row.
- 2.3 Trap placed before any `source test-helpers.sh`; here-strings instead of `printf | grep -q`.

## Phase 3: Wiring

- 3.1 Commit the suite, then run `bash scripts/lint-orphan-test-suites.sh`.
- 3.2 Add `AFFECTED_PLUGINS_SOLEUR_TEST_INNGEST_CONFIG_BUNDLE_MIRROR_TEST_SH_PATHS` in `scripts/lib/test-affected-paths.sh` only if the census or the selection dry run requires it.
- 3.3 `python3 scripts/regenerate-shard-manifest.py --incremental --write`; keep only the new suite's rows in `scripts/suite-durations.tsv` and `scripts/suite-shard-legs.tsv`.
- 3.4 With only the bundle workflow staged, confirm `bash scripts/test-all.sh --affected --affected-scope=staged` selects the suite.

## Phase 4: Verify before push

- 4.1 Run the new suite, the reusable-release retry suite and `inngest-bootstrap-mirror-only.test.sh`.
- 4.2 Run `.claude/hooks/grep-q-pipe-guard.test.sh`, fixture-relative-assert, fixture-dir-operand-assert, guard-vacuity-floor, lint-trap-tempfile-ownership, lint-shell-capture-exit (with `--baseline`).
- 4.3 Re-check `BASELINE_DECLARED_PROBES` (66) against `origin/main`.
- 4.4 Run the Observability probe (`grep -cF mirror_status=degraded .github/workflows/build-inngest-config-bundle.yml` prints `1`).
- 4.5 markdownlint the plan and this file.

## Phase 5: Ship

- 5.1 File ONE tracking issue for the cut items (digest parity check, ERR trap, digest-summary row, automated zot backfill).
- 5.2 PR body: first line "merging alone does not mutate production" with trigger-path evidence, `Ref #7243`, `## Changelog`, pre-fix RED evidence, plan cited by archived path.
- 5.3 Rebase onto `origin/main` (never merge); no syncs once armed in the merge queue; C.9 flake: re-arm ONCE, a second dequeue means stop and report the run URL.
- 5.4 Run `compound` before `ship`.
- 5.5 From a detached `origin/main` worktree run `deploy-arm.sh find --wait <full-sha>` then `served <full-sha>`; record the verdicts.
- 5.6 Tick the #7243 checkbox in epic #10205 and re-read the epic body.
