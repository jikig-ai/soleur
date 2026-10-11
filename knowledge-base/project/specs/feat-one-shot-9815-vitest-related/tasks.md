# Tasks: feat: webplat vitest `related` narrowing on local affected runs (#9815)

Plan: `knowledge-base/project/plans/2026-10-11-feat-one-shot-9815-vitest-related-plan.md`

## Phase 1: Lib functions + wrapper + suite (RED first)

- [x] 1.1 Write `apps/web-platform/test/vitest-related.test.sh` (RED — SUT absent). Synthesized-project fixture in `mktemp -d` (src/a→test/a, src/b→a→test/b, uncovered test/c + src/orphan) with `node_modules` symlinked to the app install (real vitest 4.1.11). Arms:
  - [x] 1.1.1 A1 narrow: `WEBPLAT_RELATED=src/a.ts` → only importers run, `outcome=related`, rc propagates
  - [x] 1.1.2 A2 zero: uncovered input → `No test files found` detected → full run, `outcome=full-zero`
  - [x] 1.1.3 A3 empty: `WEBPLAT_RELATED=""` → today's exact full invocation, `outcome=full-empty`
  - [x] 1.1.4 A4 bundle: `repo-wide` full ALWAYS runs + `component` narrows; both-halves-run rc aggregation (component red fails; repo-wide red still runs component)
  - [x] 1.1.5 A5 test-file input runs itself; A6 `VITEST_SHARD` forwarded to full invocations only
  - [x] 1.1.6 A7 related-RED propagates with NO full re-run
  - [x] 1.1.7 A8 real-binary marker pin: `No test files found` literal present in real 4.1.11 output
  - [x] 1.1.8 A9 lib units: `webplat_related_files`/`webplat_related_meta_hit` on synthetic blobs (R100 rows, `M\t` rows, non-app tokens filtered)
  - [x] 1.1.9 B1–B5 static arms: `WEBPLAT_RELATED=` env on both registrations, two-line shape, eligibility conjuncts, no `_diff_touches` literal / no column-0 `fi` in the computation, META derivation from `vitest.config.ts`+disk vs array, every META entry exists
  - [x] 1.1.10 M1–M6 mutants per Guard-1/Guard-2 matrices (drop marker grep; drop `--run`; drop a META member; drop CI/`_aff_fallback`/FORCE_ALL conjuncts; `&&` reorder; META-drift)
  - [x] 1.1.11 Suite shell constraints: one owning `trap … EXIT` for all mktemp, provably-absolute fixture root, per-arm `env -u TEST_GROUP` scrubs, anti-vacuity assertion floor
- [x] 1.2 Implement `WEBPLAT_RELATED_META` + `webplat_related_meta_hit` + `webplat_related_files` in `scripts/lib/test-relevance-paths.sh` beside `WEBPLAT_APP_PATHS` (:329) → GREEN (pure functions of the diff blob; `IFS=$' \t' read -ra` tokenization; `apps/web-platform/` prefix → app-relative; `LC_ALL=C sort -u`)
- [x] 1.3 Implement `apps/web-platform/scripts/vitest-related.sh` (`unit`/`bundle` modes; `cd "$(dirname "$0")/.."`; `mapfile -t`; `node_modules/.bin/vitest related … --run --project`; tee-capture + marker grep; full fallback via `npm run test:ci -- --project … ${VITEST_SHARD:+--shard=…}`; `VITEST_RELATED<TAB>` receipts; bundle = repo-wide full then component narrow-or-full, both rcs captured)

## Phase 2: Runner wiring (`scripts/test-all.sh`, inside `want_webplat`)

- [x] 2.1 Computation block after the node_modules precondition (~:6324), before the first `run_suite`: `_webplat_related=""` + eligibility conjuncts (`_ENUMERATE==0`, `-z CI`, `FORCE_ALL!=1`, both `_diff_*_ok`, `TEST_GROUP==affected` OR (`_AFFECTED==1` AND `-z _aff_fallback`)) + meta-hit banner + `webplat_related_files` call. No `_diff_touches` literal; nested `fi` indented
- [x] 2.2 Retarget both registrations to the wrapper with `env VITEST_SHARD=… WEBPLAT_RELATED="${_webplat_related:-}"` — each kept to exactly two lines (m2 `,+1d` anchor)
- [x] 2.3 Sanity: `bash -n scripts/test-all.sh`; `scripts/test-all-webplat-gate.test.sh` green (A1–A4, M1/M2 unchanged)

## Phase 3: Registration + classification

- [x] 3.1 `run_suite "apps/web-platform/test/vitest-related.test.sh" bash apps/web-platform/test/vitest-related.test.sh` inside the same arm (destroy-ask-mutation precedent — needs `node_modules`)
- [x] 3.2 `AFFECTED_APPS_WEB_PLATFORM_TEST_VITEST_RELATED_PATHS` block in `scripts/lib/test-affected-paths.sh` (suite, wrapper, `scripts/test-all.sh`, `scripts/lib/test-relevance-paths.sh`, `apps/web-platform/vitest.config.ts`, self-inclusion)
- [x] 3.3 `scripts/lint-orphan-test-suites.sh` census green; enumerate parity (shard-totality) green

## Phase 4: Measurement + ADR-242 amendment

- [x] 4.1 Record before/after into the spec measurements file: baseline rows (bundle 81,554 ms; unit ~82 s) vs related runs (already measured: lru-cache 133 files/19.97 s; redaction-allowlist 203/44.47; button.tsx component 185/44.24) + a real affected-gate run receipt check
- [x] 4.2 Append `## Amendment — 2026-10-11 (#9815)` to `ADR-242-the-local-gate-defaults-to-affected-suites-and-always-on-ratchets.md` (intra-suite narrowing extends decision-3 doctrine; corrected subcommand spelling; meta set; `_aff_fallback` reuse; rejected alternatives)

## Phase 5: Verify

- [x] 5.1 `bash apps/web-platform/test/vitest-related.test.sh` green (all arms + mutants kill)
- [x] 5.2 `bash scripts/test-all-webplat-gate.test.sh` green
- [x] 5.3 `bash scripts/test-all-group-affected.test.sh` + `bash scripts/test-all-affected.test.sh` green
- [x] 5.4 `bash scripts/lint-orphan-test-suites.sh` green
- [x] 5.5 `bash scripts/battery-tag-authorship.test.sh` + `bash scripts/lint-integration-env-gates.test.sh` green (new argv classifies; adjust the `npm run test:ci` OUT_OF_CLASS ledger entry if unmatched — re-measure, don't carry forward)
- [x] 5.6 QG-6 consumer sweep: `git grep -lE 'test:ci|web-platform \[unit\]|repo-wide\+component|WEBPLAT_RELATED|vitest-related' -- scripts apps/web-platform plugins/soleur/test` — run every hit's suite
- [x] 5.7 `python3 scripts/lint-guard-contract.py` green against the plan's Guard Contract
- [x] 5.8 End-to-end on a scratch app-only diff: receipts show `outcome=related`; meta-diff shows `outcome=full-empty`+banner; zero-resolution shows `outcome=full-zero`
- [x] 5.9 Commit and push
