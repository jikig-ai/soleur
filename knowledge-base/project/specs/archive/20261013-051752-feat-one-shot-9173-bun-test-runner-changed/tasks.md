# Tasks: fix: bun-test pre-commit gate selects from the staged set — runner-changed no longer degrades every commit on a runner-diff branch

Plan: `knowledge-base/project/plans/2026-09-29-fix-bun-test-hook-runner-changed-plan.md` (Closes #9173; Ref #8045)

## Phase 1: Runner flag + staged diff source (`scripts/test-all.sh`)

- [x] 1.1 Add `--affected-scope=<branch|staged>` to the flag-parse `while/case` and to `--help` (enum validated; default `branch`).
- [x] 1.2 Post-parse validation: unknown value, `--full` combination, or a non-affected `TEST_GROUP` (`all`-default excepted — `--affected`, local default, and `TEST_GROUP=affected` are the valid axes) → `exit 2` with usage.
- [x] 1.3 In the `_diff_names` assembly, branch on scope: under `staged`, derive from `git -c core.quotePath=false diff --cached --name-only` + `git diff --cached --name-status -M`; set `_diff_detect_ok`/`_diff_head_ok` from those commands' success; skip the `HEAD`, `origin/main...HEAD`, and untracked appends. Detection failure arms `undecidable-diff`.
- [x] 1.4 Emit `AFFECTED_SCOPE scope=staged` once per staged-scope run beside the `MODE=` line.
- [x] 1.5 Verify: `--print-affected-set` under staged scope emits receipts keyed on the index.

## Phase 2: Scope-aware runner-changed + hook wiring

- [x] 2.1 In the affected pre-pass, give the `runner-changed` arm a scope conjunct: `branch` → existing full-battery fallback unchanged; `staged` → leave `_aff_fallback` empty, emit the scoped runner-in-scope note (e.g. `AFFECTED_RUNNER_IN_SCOPE reason=runner-changed`), proceed with normal edge selection.
- [x] 2.2 `lefthook.yml` `bun-test` stanza: `run:` becomes `TC_LOCK_TIMEOUT=300 bash scripts/test-all.sh --affected --affected-scope=staged`; update the stanza comment to state the commit-scope contract (staged diff; bounded queue via `LOCK_CONTENDED_PROCEEDING`; CI is the authoritative full net). Keep `skip: merge` and the `*.{ts,tsx,js,jsx}` glob byte-stable.
- [x] 2.3 Verify on a scratch branch: `test-all.sh` in the branch diff + staged `*.test.ts` → `MODE=affected` + `AFFECTED_SCOPE scope=staged`, no `AFFECTED_FALLBACK`.

## Phase 3: Mutation coverage, stanza pin, ADR amendment (write failing arms FIRST)

- [x] 3.1 `scripts/test-all-affected.test.sh`: add the `SANDBOX_STAGED_NAMES`-class seam at the staged-diff derivation point (same shape as `SANDBOX_DIFF_NAMES`; do NOT reuse `build_census_sandbox()`'s `cp -al`/`ln -sfn` pattern — #8800 write-through hazard).
- [x] 3.2 New arms (RED before Phase 1/2 land, GREEN after): staged-only ts on runner-branch → no runner-changed fallback; staged runner+ts → bounded selection + note; staged detection failure → `undecidable-diff`; flag+`--full` / bad enum / non-affected `TEST_GROUP` → `exit 2`; `--affected-scope=branch` accepted; `TEST_GROUP=affected` + flag scopes the heuristic axis.
- [x] 3.2b Wiring arm (deepen-plan addition): pin the staged branch's `git diff --cached` invocation at source level (or a real-repo arm) — the `SANDBOX_*` seam substitutes names and cannot observe the git call; assert the branch-only diff sources do not execute under staged scope.
- [x] 3.3 Update `plugins/soleur/test/lefthook-bun-test-merge-skip.test.sh` for the new `run:` line (keep the `skip: merge` assertion).
- [x] 3.4 Amend `knowledge-base/engineering/architecture/decisions/ADR-242-the-local-gate-defaults-to-affected-suites-and-always-on-ratchets.md`: Decision gains the scope axis + staged-scope `runner-changed` semantics + flag-not-env rationale; Alternatives Considered records options (b)/(c)/(d) with rejection reasons.

## Phase 4: Verification

- [x] 4.1 Full `scripts/test-all-affected.test.sh` green (new + existing arms — branch-scope behavior byte-identical).
- [x] 4.2 `bash plugins/soleur/test/lefthook-bun-test-merge-skip.test.sh` green.
- [x] 4.3 Sanity-run the touched shards per `soleur:work` Phase 2 (scripts shard) and confirm no `runner-changed` degradation on a synthetic branch shaped like #9136's.
