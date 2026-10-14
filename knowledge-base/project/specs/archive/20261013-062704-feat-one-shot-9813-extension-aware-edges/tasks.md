# Tasks — feat-one-shot-9813-extension-aware-edges

Plan: `knowledge-base/project/plans/2026-10-10-chore-extension-aware-affected-edges-plan.md`
Issue: #9813 — extension-aware affected edges for `*.sh` corpus walkers

Every task is test-first: write the failing row, see it red, then change the code.
Guard-contract matrices live in the plan's `## Guard Contract`; each row below
names which matrix it lands.

## Phase 1 — Matcher + mint arms (`scripts/test-all.sh`)

- [x] 1.1 RED rows first: `scripts/test-affected-derive.test.sh` R-rows asserting a `glob:knowledge-base/**.sh` declared entry mints `^glob:knowledge-base/**.sh`; missing head dir mints `^knowledge-base/`; malformed entry (`glob:x` no `*/`-head / `?`/`[` / `*`-less tail) mints `^glob:<verbatim>`; `glob:` with no metachar recurses as literal; `^glob:` appears verbatim in `AFFECTED_SELECTED` receipts.
- [x] 1.2 `scripts/test-all-affected.test.sh` t-rows over `SANDBOX_DIFF_NAMES`: kb `.md` misses `^glob:knowledge-base/**.sh`; kb `.sh` hits at specs depth AND at head root AND nested `a/b/c.sh`; `R100\told.sh\tnew` hits via the rename-source line; `^glob:bad` (malformed) matches (never narrows).
- [x] 1.3 Add the `glob:` arm to `_affected_add_edge` BEFORE the `[[ -e ]]` probe: well-formed+head dir → `^glob:<pattern>`; head dir missing → `^<head>/`; malformed → `^glob:<entry verbatim>`; no-metachar → recurse literal. All existence probes via `_affected_probe` (the derive-cache input census fails on a bare `[[ -d ]]`).
- [x] 1.4 Add the `glob:*)` arm to `_diff_edge_hit` before `*/)`: malformed → `return 0`; head pre-check `[[ "$_n" == *"${_NL}<head>"* ]]`; non-empty-line loop over `_DEH_N` matching `[[ "$line" == $pattern ]]`.
- [x] 1.5 Header comments on both functions: third entry kind + the degrade ladder.

## Phase 2 — Index + grammar consumers

- [x] 2.1 `scripts/lib/test-affected-paths.sh`: header documents three declared kinds (file, dir-prefix, `glob:`); swap `knowledge-base/` → `glob:knowledge-base/**.sh` in `AFFECTED_PLUGINS_SOLEUR_TEST_OPERATOR_ACK_GUARD_TEST_SH_PATHS`, `…OPERATOR_SCRIPT_TEST_SH_PATHS`, `…OPERATOR_AGENT_RUNNABLE_TEST_SH_PATHS`, `AFFECTED_SCRIPTS_LINT_SHELL_CAPTURE_EXIT_LIVE_PATHS`, `AFFECTED_SCRIPTS_LINT_SHELL_TRACE_CREDENTIAL_REFUSAL_PATHS`; trap-tempfile gets the seven-entry set (`**.sh`, `**.bash`, `**.py`, `**.ts`, `**.mjs`, `**.js`, `*bunfig.toml`); `AFFECTED_SCRIPTS_TEST_AFFECTED_KB_CONSUMERS_PATHS` keeps `knowledge-base/`; note at `AFFECTED_CONSUMED_EDGES` that `glob:` is declared-array-only (consumed entries are verbatim substrings).
- [x] 2.2 G3 awk: add `GLOBENT` `^  "glob:[-A-Za-z0-9_./]*\*[-A-Za-z0-9_./*]*"( +#.*)?$`; admit beside `ENT` at the in-block member check and both INDEX-ANCHOR preceding-line sites; `ALWAYS_ON_SUITES` member regex unchanged.
- [x] 2.3 `scripts/lint-orphan-test-suites.sh`: `glob:` arm in the declared-member census — head ends `/` + `[[ -d ]]`, tail non-empty with `*` and no `?[`.
- [x] 2.4 `scripts/test-affected-kb-consumers.test.sh`: `covers()` `^glob:` arm — file ref `fnmatch(p, g)`; dir ref covered iff `p`/`head` nest.

## Phase 3 — Mutation + fixture arms

- [x] 3.1 `scripts/test-all-affected.test.sh` awk mutation rows: `glob:` entry in added array → `registration-only`; `glob:` with `?`/`[` → `semantic`; `glob:` line inside `ALWAYS_ON_SUITES` → `semantic`; added array opened below a `glob:` entry → anchor accepted (Guard 4).
- [x] 3.2 `scripts/lint-orphan-test-suites.test.sh`: mirror the census arm in its fixture census AND add mutation rows — missing head dir RED; `*`-less tail RED; `?`/`[` RED; valid GREEN; bad entry after a compliant first RED; zero-checked vacuous-walk row (Guard 3).
- [x] 3.3 New rows follow the fixture idiom: scratch-root per-process dirs + `assert_fixture_dir` twice, no second `EXIT` trap (#8659), `env -u TEST_GROUP -u CI` on nested runner rows, no new shared-inode write paths (#8800).
- [x] 3.4 Verify `plugins/soleur/test/fanout-suite-scope.test.sh` still passes with `glob:` entries in the copied index; fix forward (fixture dir or arm ordering) if its sandbox flags them.
- [x] 3.5 Hand-apply each mutation-matrix row once and confirm it reds before finalizing.

## Phase 4 — Verification + decision record

- [x] 4.1 `bash scripts/test-all.sh --print-selection --paths=knowledge-base/project/specs/foo.md` → `selected=112`, six walker labels absent from selected rows, `scripts/test-affected-kb-consumers` present (FR-1, FR-3).
- [x] 4.2 `--paths=knowledge-base/project/specs/feat-sdd-implementation-mirror-guard/bootstrap.sh` → the six walkers select (FR-2).
- [x] 4.3 Stream-diff `AFFECTED_SELECTED` origin/main vs HEAD per FR-5: non-six rows byte-identical on every probe; six rows differ only in the kb-edge token + selected-bit on kb-md only.
- [x] 4.4 `bash scripts/affected-prepass-bench.sh --base origin/main --runs 1` for interleaved timing + walker fidelity line.
- [x] 4.5 Amend `knowledge-base/engineering/architecture/decisions/ADR-242-the-local-gate-defaults-to-affected-suites-and-always-on-ratchets.md`: new decision 22 (`glob:` kind, degrade ladder, G3 `GLOBENT`, per-suite dispositions) + alternatives rows; add `#9813` to the related-issues line.
- [ ] 4.6 Run `apps/web-platform/test/c4-code-syntax.test.ts` + `c4-render.test.ts` after the ADR edit; run the touched suites + `bash scripts/lint-orphan-test-suites.sh`; the full battery runs because runner+index are touched (`runner-changed` — expected, budgeted).
- [ ] 4.7 PR body: `Closes #9813`; record that the local full battery ran (runner touched → degraded-full) and that `git diff --quiet origin/main...HEAD -- .github/workflows/` is clean (NFR-1).
