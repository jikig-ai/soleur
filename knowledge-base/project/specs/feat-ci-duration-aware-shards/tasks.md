# Tasks — feat(ci): duration-aware shard assignment via checked-in `label→leg` manifest

lane: cross-domain
Plan: `knowledge-base/project/plans/2026-09-23-feat-ci-duration-aware-shards-plan.md`
Refs #8006 (delivers the label-keyed partition mechanism — the issue's deferred arm; PR may `Closes #8006` only if the follow-through probe semantics are preserved/transferred).

Locate all constructs by content anchor, not line number — line numbers were verified against `b61ee7b8f3` on 2026-09-23 and will drift. No `.ts` files in this diff → the bun-test hook will not fire; verification = targeted suites + authoritative CI.

## Phase 1 — Runner (`scripts/test-all.sh`)

- [x] 1.1 Manifest load block, inserted AFTER the `SCRIPTS_SHARD` parse block (after the `_SHARD_K=$(( 10#…`/`_SHARD_N=$((…` assignments — ROW8's mutation anchor spans the parse tail, do not split it) and BEFORE the `unset SCRIPTS_SHARD` at the carrier-consumption site. Semantics:
  - `SOLEUR_SHARD_MANIFEST` unset → default `$(dirname "${BASH_SOURCE[0]}")/suite-shard-legs.tsv`; `off` → disabled (quiet); `""` set-but-empty → exit 2 (SCRIPTS_SHARD set-empty precedent); set path non-absolute or missing → exit 2.
  - Only attempt load when `_SHARD_N > 0` AND `TEST_GROUP == "scripts"` (manifest is light-group only; a `4/5` spec under scripts-heavy with n=5 would otherwise activate on heavy labels).
  - Default file absent → `_shard_manifest_active=0` + one stderr notice (not stdout — `SUITE_REGISTRATION` stream stays pure).
  - Parse header `n=`; `n != _SHARD_N` → inactive + stderr notice naming both values. Malformed row / duplicate label / leg ∉ [1..n] → exit 2 with sentinel vocabulary.
  - Load rows into parallel indexed arrays (`_shard_m_labels[]`, `_shard_m_legs[]`) via `while IFS=$'\t' read -r` — bash 3.2, no `mapfile`, no `declare -A` (:2944 documents why).
  - `unset SOLEUR_SHARD_MANIFEST` alongside `unset SCRIPTS_SHARD` — fixture paths must not be inherited by nested runners.
- [x] 1.2 `_shard_selects` gains `"$label"` (arity check `$# -ge 1` → exit 2; makes the arg-drop mutation loud). Two modes:
  - inactive → today's positional block `(( _SHARD_N > 0 )) && (( (_shard_ordinal - 1) % _SHARD_N != _SHARD_K - 1 ))` **preserved verbatim** (ROW1/ROW4 anchor on it).
  - active → linear scan of the label arrays; hit → leg; miss → `cksum` hash fallback `($(printf '%s' "$label" | cksum | cut -d' ' -f1) % _SHARD_N + 1)`. Compare leg to `_SHARD_K`; select → `_shard_assigned++`.
  - `_shard_ordinal`/`_shard_assigned` keep incrementing in BOTH modes (:3103 refusal + :3120 enumerate-complete read them).
- [x] 1.3 Both call sites: `_shard_selects || return 0` → `_shard_selects "$label" || return 0` (`run_suite` ~:920, `skip_suite` ~:1084 — the sites become byte-identical; that is expected, mutation anchors go multi-line).
- [x] 1.4 Rewrite the shard-selection comment block (:810-844): manifest-first story, hash fallback, mode table, locale caveat shrinks (manifest+hash assignments are collation-independent; only positional mode retains the LC_COLLATE caveat). Keep the non-selection-is-not-a-decline paragraph verbatim.
- [x] 1.5 Smoke: `SCRIPTS_SHARD=k/5 TEST_GROUP=scripts --enumerate` matches the manifest's leg-k set; `SOLEUR_SHARD_MANIFEST=off` → positional; bogus/absent/empty-string env → exit 2; n-mismatch → positional + notice; `SCRIPTS_SHARD=k/3 TEST_GROUP=scripts-heavy` → positional + notice.

## Phase 2 — Manifest + generator

- [x] 2.1 `scripts/regenerate-shard-manifest.py` (stdlib only): `--run <id>` (default: latest green `ci.yml` run on `main`), `--write` flag (without it: print predicted per-leg totals + diff). Downloads `suite-timings-scripts-[0-9]*` artifacts via `gh run download --name` — NOT `suite-timings-scripts-*` (matches `-heavy-`, whose labels aren't registered under `want_scripts` → ⊆ lint red). TSV parse: field1=label, field2=ms; drop `__run_boundary_*` labels, `skip=*` rows, FAIL/KILLED/TRIPWIRE verdicts; dup label across legs → warn + max.
- [x] 2.2 Sticky-LPT: sort desc by ms (ties → label asc); least-loaded leg wins, but keep incumbent leg when its projected load ≤ min-load + ε (ε = 5% of mean). N read from ci.yml `test-scripts` matrix (single source). Deterministic output: `label<TAB>leg` sorted by label, `#`-comment header carrying `n`, `generated-from-run`, `generated-at`, generator version, regen command.
- [x] 2.3 Generate v1 manifest from run `35840517639` artifacts (local copies in `/tmp/timings`); commit `scripts/suite-shard-legs.tsv`. Expect each leg ≈450s.
- [ ] 2.4 Generator unit test `plugins/soleur/test/regenerate-shard-manifest.test.sh` (or `.py`-invoking harness matching sibling conventions): deterministic output, sticky preference bounds churn, dup-label warn, boundary/verdict exclusions, n-from-ci.yml.

## Phase 3 — Guards

- [x] 3.1 New lint suite `plugins/soleur/test/scripts-shard-manifest.test.sh`, registered in test-all.sh (literal `run_suite` label — the totality reference extractor requires literal labels): TSV well-formed; header `n` == ci.yml light-matrix leg count; legs ∈ [1..n]; no dup labels; labels ⊆ registered scripts labels (strict — error names the regen command); every leg has ≥1 pin; provenance fields present. Satisfy guard-vacuity-floor obligations (ADR-193): case counter, conservation check, literal floor, instrument self-test.
- [ ] 3.2 `plugins/soleur/test/scripts-shard-totality-mutations.sh`:
  - ROW7 re-anchor as multi-line block (post-change call sites are byte-identical — keep the skip_suite-specific following lines in the anchor).
  - ROW1/ROW4: wrap `guard_rc` invocation with `export SOLEUR_SHARD_MANIFEST=off`, unset immediately after (leak → later rows silently measure positional).
  - Six new rows: M1 absent-label→GREEN (fallback); M2 phantom-row→GREEN (inert); M3 empty-table→GREEN (all-hash totality); M4 two untabled labels land on distinct legs — bespoke enumerate check, verify the pair's cksum residues differ first; M5 drop `"$label"` arg → exit 2 → RED; M6 mutate a `skip_suite` label → union mismatch → RED.
  - Fixture manifests in `$WORK`, absolute paths via env seam (cq-test-fixtures-synthesized-only).
  - `MIN_ROWS` (:455 area) → ≥21, re-derived per the file's itemized-floor discipline.
- [ ] 3.3 `plugins/soleur/test/scripts-shard-totality.test.sh`: verify unchanged-green (mechanism-agnostic); altK k/2,k/3 rows exercise positional mode, k/5 exercises manifest mode — no edits expected unless enumerate output format changes.

## Phase 4 — Docs

- [x] 4.1 ADR-239 (via soleur:architecture): "Shard assignment is checked-in derived data" — manifest + sticky offline generator + runtime lookup/fallback; ADR-235 classification (product → committed, regenerate-on-conflict); why runtime LPT stays rejected (#8006's two defects).
- [x] 4.2 Runbook `ci-test-scripts-sharding.md`: manifest section — regen recipe, merge-conflict=regenerate, `SOLEUR_SHARD_MANIFEST` seam, staleness posture (regen when legs skew; follow-through probe bounds worst leg).
- [x] 4.3 `plugins/soleur/skills/work/SKILL.md` §9 + grep-driven stale-prose sweep for "positional"/"round-robin" descriptions of the partition.
- [x] 4.4 #8006: comment that the manifest arm shipped + confirm `ci-leg-durations-8006.sh` probe semantics still correct (worst leg ≤900s; expected ~540s).

## Phase 5 — Verify + ship

- [ ] 5.1 Targeted suites green: shard-totality, shard-manifest lint, totality-mutations battery (control + all rows), enumerate-toolchain, aggregator-diagnosis, ship-battery-owed, fullsuite-merge-gate, required-checks-parity, lint-orphan-test-suites, generator unit test. shellcheck/shfmt on touched .sh.
- [ ] 5.2 Push `feat-ci-duration-aware-shards`; CI green: all `test-scripts*` legs pass, worst light leg ≈9min (vs 13m50s), `test` aggregator green. Record leg timings + manifest source run in PR body.
- [ ] 5.3 Post-merge: regen manifest from first green main run if timings shifted; probe continues per its own cadence.
