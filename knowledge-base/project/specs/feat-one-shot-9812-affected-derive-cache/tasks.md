# Tasks — feat-one-shot-9812-affected-derive-cache

Plan: `knowledge-base/project/plans/2026-10-09-feat-affected-derive-cache-plan.md`
Issue: #9812 — cache the affected-derive across local runs

## Phase 1 — Cache lib + recording instrumentation

- [ ] 1.1 Create `scripts/lib/test-affected-derive-cache.sh`: `_ADC_SCHEMA` constant, record/validate/replay/write/prune functions, `SOLEUR_AFFECTED_DERIVE_CACHE=0` kill switch, atomic tmp+mv writes, `git hash-object --no-filters --stdin-paths` batching with the `env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE` scrub idiom, bash-3.2-compatible (no `declare -A`/`declare -n`), chmod 700 dir / 0600 files.
- [ ] 1.2 In `scripts/test-all.sh`: source the lib beside the `_REL_LIB`/`_AFF_LIB` block (degrade-never-block class, like `_AFF_LIB`).
- [ ] 1.3 Add recording hooks at every derive probe/read site: `_affected_add_edge` (`-e`), `_affected_buf_add` (`-e`), `_affected_edge_token` (`! -e` dotted module), `_affected_file_edges` (`-f` gate + read-set append at entry), `_affected_derive` (`-f`/`! -e`/closure-enqueue sites). Name `[[ -d "$PWD" ]]` (`_wt_missing_die`) exempt.
- [ ] 1.4 Route the walk's `_affected_classify` call (the `SUITE_COMMAND` arm of the `_aff_stream` loop) through the cache wrapper: key = hash(schema + derive-code hash + label + argv); validate recorded inputs; replay `_AC_CLASS` + ordered `_AC_EDGES` + rebuilt `_AC_ESET` + cleared `_AC_SUITE_FILE` on hit; record + atomic write on miss.
- [ ] 1.5 Emit `AFFECTED_DERIVE_CACHE hits=<n> misses=<n> derived=<n>` at walk end.
- [ ] 1.6 Add `AFFECTED_TEST_AFFECTED_DERIVE_CACHE_PATHS` declared edges in `scripts/lib/test-affected-paths.sh` (`scripts/lib/test-affected-derive-cache.sh`, `scripts/test-all.sh`, `scripts/test-affected-derive-cache.test.sh`).

## Phase 2 — Test arm

- [ ] 2.1 Create `scripts/test-affected-derive-cache.test.sh` (extract-and-eval harness shape per `scripts/test-affected-derive.test.sh`; owning `trap` before `source` of helpers; counted skips fail under CI).
- [ ] 2.2 Rows: byte-identical replay (class + ordered edges + `_AC_ESET`); in-closure file edit → re-derive; file created at recorded-miss path → invalidate; unrelated edit → hit; corrupt entry → fall back; wrong schema → fall back; `SOLEUR_AFFECTED_DERIVE_CACHE=0` → full derive; argv change → miss; unwritable `.soleur/` → degrade with identical selection.
- [ ] 2.3 Probe-site census row: derive the `-e`/`-f` probe set from the extracted derive block; fail on any site neither recorded nor named-exempt.
- [ ] 2.4 Register the suite via `run_suite` in `scripts/test-all.sh`; run `scripts/lint-orphan-test-suites.sh` to confirm registration.

## Phase 3 — Measure + ADR + acceptance bench

- [ ] 3.1 Measure before/after `--print-selection --paths=README.md` wall-clock on an idle host (cold + warm runs); write `knowledge-base/project/specs/feat-one-shot-9812-affected-derive-cache/measurements-derive-cache.md`.
- [ ] 3.2 Amend `knowledge-base/engineering/architecture/decisions/ADR-242-the-local-gate-defaults-to-affected-suites-and-always-on-ratchets.md` with a new numbered decision (provisional 21; run `scripts/check-adr-ordinals.sh`).
- [ ] 3.3 Run `bash scripts/affected-prepass-bench.sh --base <merge-base> --added-edges scripts/lib/test-affected-derive-cache.sh` — must exit 0.
- [ ] 3.4 Verify ACs 1–8; commit `Closes #9812` shape per ship conventions.
