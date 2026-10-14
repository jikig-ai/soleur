# Tasks — feat-8322-affected-test-gate

Plan: `knowledge-base/project/plans/2026-09-18-feat-test-all-affected-gate-default-plan.md`
Spec: `knowledge-base/project/specs/feat-8322-affected-test-gate/spec.md`

## Phase 0 — Preconditions

- [x] 0.1 Re-verify insertion anchors: `run_suite` (`test-all.sh:~905`), `skip_suite` (`:~1067`), `_shard_selects` (`:~835`), flag-parse chain (`:175-211`), `_diff_names`/`_diff_touches`/`_diff_detect_ok`/`_diff_head_ok`/`_infra_in_diff` (`:1133-1221`), refusals (`:690`, `:1379`), infra arm (`:2797`), enumerate terminator (`:2879`), epilogue (`:3043-3112`).
- [x] 0.2 Live counts: `bash scripts/test-all.sh --enumerate-commands` + `--enumerate scripts`; record totals.
- [x] 0.3 Re-verify ADR-227 free across `git branch -a` + `git tag`.
- [x] 0.4 Live reproduction of the `TEST_GROUP=infra` P0 on a non-infra diff (green-over-zero + false `_infra_ran`) to confirm the defect before fixing.

## Phase 1 — Declarations + census (RED first)

- [x] 1.1 Create `scripts/lib/test-affected-paths.sh` — declarations only: `ALWAYS_ON_SUITES`, `AFFECTED_<LABEL>_PATHS` (infra label positively edge-derived on its two prefixes), prefix rules; self-inclusion; how-to header; cross-ref to `test-relevance-paths.sh`. NO token edges (cut — plan §Edge index). The five existing `*_PATHS` arrays are *consumed*, not re-declared.
- [x] 1.2 Census rows in `scripts/lint-orphan-test-suites.sh`: consume `--print-affected-set` for classification; `|ALWAYS_ON| ≥ count(*-live)` floor over `--enumerate-commands`; repo-wide-idiom grep arm (`git ls-files` unscoped, `grep -r`, `find .` → must be ALWAYS_ON or declared edge); unclassified → RED naming the label.
- [x] 1.3 Resolve the two unregistered `test-*.sh` files (`tests/scripts/test-sentry-brownout-retry.sh`, `tests/hooks/test_drop_sentinel_parity.sh`) — register (preferred) or tracked exclusion; note the `*.test.sh` producer blind spot.

## Phase 2 — Runner mechanics (TDD)

- [x] 2.1 RED: `scripts/test-all-affected.test.sh` — Guard 2 mutation matrix rows a–p (incl. both diff-flag arms, infra explicit-ask P0 row, below-floor row, trailing-flag row, missing-lib row, runner-changed row, both refusal arms + degraded-full).
- [x] 2.2 Flags at `:175-211`: `while`-loop over leading flags; `--affected` (default locally), `--full` (affected off + `_diff_touches` FORCE_ALL arm + infra-arm conjunct at `:2797`), `--print-affected-set` (`_PRINT_AFFECTED` + `_ENUMERATE` plumbing — NOT early-exit), `--help`; `$# > 1` → exit 2; `--affected --full` conflict → exit 2. `CI` inert; `FORCE_ALL`+affected → degrade to full.
- [x] 2.3 Classification `_affected_class_of` (lazy, ordinal-indexed arrays — **bash 3.2, no `declare -A`**): always-on → declared/derived edges (argv literals via nested `$0 --enumerate-commands` self-call incl. `-c`-string greps; source/import closure resolving `$HERE` indirection; name-stem) → `_infra_in_diff` → explicit-group ask → runner/index self-edge → unclassified→selected.
- [x] 2.4 Chokepoint after `_shard_selects` + enumerate short-circuit: counted `not-affected` decline (`suites++`, distinct `_affected_declined`, compact one-line `[skip]`; the `--full` recovery lever is printed once in the epilogue, not per-suite); `MODE=affected|full` banner; per-registration `AFFECTED_CLASS` receipt lines.
- [x] 2.5 Fallback arms (executing-mode only, never under enumerate): `_diff_detect_ok==0` OR `_diff_head_ok==0` → `AFFECTED_FALLBACK reason=undecidable-diff`; runner/index diff → `reason=runner-changed`; missing lib → `reason=index-missing`; below-`*-live`-floor or zero-executed → `AFFECTED_UNRESOLVED` rc=4; unscoped `git ls-files --others` for untracked.
- [x] 2.6 Refusal exemptions on BOTH arms (`:690` SUBAGENT, `:1379` sibling census): affected proceeds; `--full` refuses; post-derivation degraded-full re-checks refusal → rc=4; `SOLEUR_ALLOW_FULL_GATE` unchanged for full; advice strings name `--full`.
- [x] 2.7 Epilogue `N not-affected` (breakdown gate includes not-affected-only runs; reconcile `_relevance_declined` callsite increments); recovery lever prints `--full`; header + `--help` disclosure. GREEN 2.1.

## Phase 3 — Caller audit + pin re-spec

- [x] 3.1 `lefthook.yml:332` → `bash scripts/test-all.sh --affected` (drop `SOLEUR_ALLOW_FULL_GATE` — exempt by construction); re-pin `lefthook-bun-test-merge-skip.test.sh`.
- [x] 3.2 `ship/SKILL.md` — Phase 4 dispatch (`/ship --full` → `--full` outranking SKIPPABLE; else OWED/not-42 → `--affected`), detached literal `:441`, checklist `:489`, prescription `:336`, interpretation/disclosure block.
- [x] 3.3 `work/SKILL.md` §9 — single `--affected`; rewrite shard-map prose; fix "lead runs this gate, not a delegate" (`:1011-1015`); state `TEST_GROUP=<g>` explicit-ask semantics.
- [x] 3.4 `grok-pre-push-gate.sh:165` → `--affected`; re-label step text.
- [x] 3.5 `scripts/hooks/pre-push` — supersede body → `--affected`; keep bun-absent + empty-diff skips; header re-word (minutes-scale, refusable-in-full).
- [x] 3.6 `battery-owed.sh` — header re-word (OWED → `--affected`, not "full local run").
- [x] 3.7 `fullsuite-merge-gate.test.ts` — re-pin imperative/CEILING/FLOOR; `QUERY_FLAGS` += `--print-affected-set`; detector learns mode flags.
- [x] 3.8 `fanout-suite-scope.test.sh` — refusal arms: SUBAGENT/sibling × affected/full + degraded-full.
- [x] 3.9 `ship-battery-owed.test.sh` — consumer-contract rows (OWED→affected, opt-in→full, not-42→run).
- [x] 3.10 Re-baseline sandboxed runner-SUT suites where they pin affected internals (≥7 lib-mirror sites kept working by the index-missing degrade).

## Phase 4 — ADR + disclosure

- [x] 4.1 `knowledge-base/engineering/architecture/decisions/ADR-242-*.md` — default flip; amends ADR-181, ADR-133, ADR-183, ADR-196 (Decision 6's hook-hatch claim is false post-#8322); records the enumerate interpretation + token-edge deferral + dual-axis subsumption note. (ADR-227 was claimed by a sibling branch between plan and Phase 0; ADR-229 was claimed by #8301 mid-review — renumbered to ADR-230, then to ADR-233 after upstream claimed 230-232 mid-pipeline, then to ADR-234 when the next sync claimed 233, and to ADR-237 when the one after that claimed 234, and to ADR-238 when the post-merge sync claimed 237, and to ADR-240 when the #8596 merge claimed 238, and to ADR-242 when the #8612 merge claimed 240 — the #8301 ship-note precedent.)
- [x] 4.2 Disclosure sweep: `test-all.sh` header/`--help`, `ship` Phase 4, `work` §9 — affected+ratchets does not test suite×suite interaction; CI sharded full is the backstop; retired middle mode documented.

## Phase 5 — Verification

- [x] 5.1 Mutation matrix executed (rows a–p, RED→GREEN evidence).
- [x] 5.2 Enumerate consumers green: `battery-tag-authorship.test.sh`, `scripts-shard-totality.test.sh`, `lint-orphan-test-suites.sh`.
- [x] 5.3 `c4-count-parity.test.sh` green; `gitleaks-staged`; `migrated-rule-id-lint`; `skill-security-scan-advisory`; `plugin-component-test`.
- [x] 5.4 Human review of live `bash scripts/test-all.sh --print-affected-set` on this diff before push.
