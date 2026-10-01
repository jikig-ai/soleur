---
created: 2026-09-23
branch: feat-ci-duration-aware-shards
planning-tool: plan
skill_version: "1.0"
status: draft
---

# feat-ci-duration-aware-shards plan

## Required Checklist (from the skill)

- [x] 0.5 — This plan lives in `knowledge-base/project/plans/` with date prefix ✓
- [x] 1.2 — Safety: not on main/master; `feat-ci-duration-aware-shards` stacked on `b61ee7b8f3` (green `feat-ci-test-shard-speedup` head); prior branch pushed, never stashed
- [x] 1.3 — KB context consulted (learnings fan-out + ADR-235/ADR-238 read)
- [x] 1.5 — Premises validated (all Stage-0 items below)
- [x] 1.7.1–1.7.5 — Research fan-out (repo agent + learnings agent) + overlap check
- [x] 3 — Plan-review subagent — verdict: sound; 5 concrete errors + understates folded in (timing schema field-swap, byte-identical call-site anchors, MIN_ROWS floor, heavy-glob leak, parse-insertion point, TEST_GROUP gate, env-seam semantics)
- [x] 4 — Plan artifact + tasks.md complete (`specs/feat-ci-duration-aware-shards/tasks.md`, 5 phases)
- [x] 5 — Handoff to work (implementation begins on this branch)

## Problem

The five-way light-group partition is positional (`ordinal % 5`): leg membership is decided by registration order, not cost. Measured on run `35840517639`, leg 5/5 carried 797s of suite time — three network-bound suites (betterstack 165s, playwright-redact 149s, git-data-birth 112s) happened to land adjacent — vs 237s on the best leg. Worst `test-scripts*` leg is 13m50s wall clock; ~9min is achievable with duration-aware assignment (LPT over measured timings gives a flat ~450s/leg + ~90s setup).

## Stage 0 — premise validation (DONE)

| Premise | Result |
|---|---|
| Per-suite timings exist in CI artifacts | ✓ `suite-timings-scripts-{0..4}` + `-heavy-{0..2}` from run 35840517639; schema (verified at test-all.sh:947/:1026/:1096): `label<TAB>ms[<TAB>FAIL|KILLED|TRIPWIRE|skip=reason][<TAB>tmp_delta=N]`; `__run_boundary_*` rows carry ms=0 — exclude on field-3 prefix AND boundary labels |
| LPT worth it on real data | ✓ light group: 487 suites, 2248s total, LPT → 450s/leg flat (measured: 237–797s) |
| `_shard_selects` takes no args | ✓ bare `|| return 0` at :920/:1084; ordinal `:845-855`; zero-refusal `:3102` |
| Totality guard independent of partition mechanism | ✓ verified: reference = static awk extraction + `--print-suite-globs`; legs enumerated via real `SCRIPTS_SHARD=k/N` runs; **no `ordinal % N` simulation anywhere** — mechanism-agnostic by construction |
| Totality must hold for any K | ✓ altK rows enumerate `k/2`, `k/3`, `k/5` — a manifest bound to one N must degrade gracefully under other N |
| Bash constraint | ✓ **bash 3.2** — `test-all.sh:2944` avoids `declare -A`; use indexed arrays / `case` tables (`_suite_budget_ms` :789 precedent) |
| `#8006` analysis | ✓ runtime LPT rejected (no insertion stability; chokepoint can't compute); label-keyed partition + 6-row battery pre-designed |
| Enumerate purity | ✓ `--enumerate` takes no lock, writes nothing, runs inside the advisory lock the gate holds — manifest read must be a pure read-only parse |
| Heavy group | ✓ 3 suites (351/371/484s) on 3 legs is already optimal; positional suffices — manifest is **light-group only** |

## Design (decisions taken)

### Runner — two modes at the chokepoint

`_shard_selects "$label"` (arity-checked: `$# -ge 1` else exit 2 — makes the arg-drop mutation loud):

- **Manifest inactive** → today's positional `ordinal % N` block **preserved verbatim** (ROW1/ROW4 anchor on it; refactoring it into a helper silently rots the rows). Inactive when: `SCRIPTS_SHARD` unset (no-op anyway), `SOLEUR_SHARD_MANIFEST=off`, default file absent (stderr notice), `manifest.n != _SHARD_N` (stderr notice), or `TEST_GROUP != scripts` (manifest is light-group only — gates `SCRIPTS_SHARD=4/5`-under-scripts-heavy activating on heavy labels).
- **Manifest active** → label lookup (linear scan over parallel indexed arrays); label absent → **deterministic hash fallback** `(cksum(label) % N) + 1` — insertion-stable, locale-independent (learnings agent: a second ordinal counter reintroduces the insertion-order sensitivity the manifest exists to remove). `cksum` output is `<crc> <bytes>` — take field 1; input via `printf '%s' "$label" | cksum` (a file operand appends the filename). ~0.3-0.7s fork cost per enumerate, only for untabled labels — acceptable; pure-bash hash is a later optimization if it hurts.
- `_shard_ordinal`/`_shard_assigned` keep incrementing in BOTH modes (the refusal message :3103 and enumerate-complete line :3120 read them).
- Parse once **after :259** (ROW8's mutation anchor spans :250-252) and above the `unset` at :692 — enumerate mode shares this path (argv shift :178-214 → parse :231). bash 3.2 loader: `while IFS=$'\t' read -r`, no `mapfile`. Refuse (exit 2) on: malformed row, duplicate label, leg ∉ [1..n]. Manifest path resolution: default = `$(dirname "${BASH_SOURCE[0]}")/suite-shard-legs.tsv` (sibling of the script — cwd-independent; lib-sourcing precedent at :451/:560/:590).
- Call sites: `_shard_selects "$label" || return 0` in both `run_suite` (:920) and `skip_suite` (:1084) — the two sites become **byte-identical**, so mutation anchors must stay multi-line (see Guards).
- Env seam `SOLEUR_SHARD_MANIFEST`: unset → default path; `off` → disabled (quiet); `""` (set-but-empty) → exit 2 (SCRIPTS_SHARD set-empty precedent); set path missing → exit 2; set path must be **absolute** (runner never normalises cwd). Consumed-and-unset at :692 alongside SCRIPTS_SHARD — a fixture path into a deleted `$WORK` must not be inherited by nested runners. Propagates through `env SCRIPTS_SHARD=…` (env preserves environment) — verified through the guard's `guard_rc` → `enumerate_leg` → `env` chain.

### Manifest — `scripts/suite-shard-legs.tsv` (committed)

- Header comment lines: `n=<K>`, `generated-from-run=<id>`, `generated-at=<ts>`, `generator=<ver>`, regen command. Rows: `label<TAB>leg`, sorted by label (diff stability — the ADR-235/rule-metrics conflict learnings demand minimal, stable diffs).
- Light-group labels only, and only labels with a measured green timing (boundary markers `__run_boundary_*`, FAIL/KILLED rows, and never-measured suites stay untabled → hash fallback).
- Product artifact per ADR-235 → committed; merge conflicts resolve by **regeneration, not hand-merge** (runbook step).

### Generator — `scripts/regenerate-shard-manifest.py` (stdlib only, manual `--write` convention)

- Input: `--run <id>` (or latest green main `ci.yml` run); downloads **`suite-timings-scripts-[0-9]*`** artifacts via `gh` — NOT `suite-timings-scripts-*` (that glob also matches `suite-timings-scripts-heavy-*`, whose labels aren't registered under `want_scripts` and would red the ⊆ lint). Merges label→max-ms (dupes across legs = anomaly → warn + max); excludes `__run_boundary_*` labels, `skip=*` rows, and FAIL/KILLED/TRIPWIRE verdicts (partial timings). Computes **sticky-LPT**: sort desc by duration (ties → label asc); assign each label to least-loaded leg, but keep incumbent leg when its projected load ≤ min-load + ε (ε = 5% of mean) — minimizes manifest churn per refresh.
- Reads light-matrix N from `ci.yml` (single source). Emits deterministic output (sorted labels); `--write` updates the committed file; without it, prints diff + predicted per-leg totals.
- Refresh model: manual command + runbook (repo convention is explicit `--write` + scheduled detect-and-file monitors, NOT auto-PRs — stale-bot-PR learning). Stretch: skew probe filing an issue when implied worst-leg > threshold × mean.

### Guards

- **Totality guard**: unchanged machinery (mechanism-agnostic); altK rows now exercise both modes for free (k/5 = manifest path; k/2, k/3 = positional).
- **New lint suite** `plugins/soleur/test/scripts-shard-manifest.test.sh` (registered in test-all.sh): well-formed TSV; header `n` == ci.yml light leg count (drift pin); legs ∈ [1..n]; no dup labels; labels ⊆ registered scripts labels — **strict** (forces regen on rename; error names the regen command); every leg has ≥1 pin; provenance fields present. Must satisfy `guard-vacuity-floor` harness obligations (ADR-193): call-site case counter, conservation check, literal floor, instrument self-test, byte-identical `assert_fixture_dir` if it makes fixture dirs.
- **Mutation battery** (`scripts-shard-totality-mutations.sh`):
  - ROW1/ROW4 (mod-expression anchors): keep — wrap with `export SOLEUR_SHARD_MANIFEST=off` so they still measure positional mode; **unset immediately after** (a leaked `off` silently turns every later row's guard run positional — false PASS/SURVIVOR confusion).
  - ROW7 anchor: re-anchor as a **multi-line block** — post-change both call sites read `_shard_selects "$label" || return 0` byte-identically; the anchor must include the following `skip_suite`-specific lines (existing anchor at :335-338 already disambiguates this way).
  - ROW8's anchor spans test-all.sh:250-252 — manifest parse must go after :259.
  - **MIN_ROWS floor :455 → ≥21** (13 + 6 new + margin).
  - Six new rows per #8006: (M1) absent label → GREEN via fallback; (M2) phantom row → GREEN (inert); (M3) empty table → GREEN (all-hash, totality intact); (M4) two untabled labels land on distinct legs — bespoke enumerate check (not `row()`), and the label pair must be **verified** to cksum-hash to distinct residues, not guessed; (M5) drop `"$label"` arg → arity check exit 2 → enumerate empty → RED; (M6) mutate a `skip_suite` label → enumerate emits phantom → union mismatch → RED (label parity was already load-bearing — the row pins it).
  - Fixture manifests live in `$WORK` (absolute paths into the env seam; cq-test-fixtures-synthesized-only).
- **Unchanged**: ci.yml (no job changes — manifest is data), aggregator, fullsuite-merge-gate, ship-battery-owed, c4-pin-parity, enumerate-toolchain (no registration-count assertions — MIN_CASES derives from group count).

### Docs

- **ADR-239**: shard assignment as checked-in derived data (manifest + sticky offline generator + runtime lookup/fallback); ADR-235 classification (product → committed, regenerate-on-conflict); why runtime LPT stays rejected.
- Runbook `ci-test-scripts-sharding.md`: manifest section, regen recipe, conflict=regen, `SOLEUR_SHARD_MANIFEST` seam.
- `test-all.sh`: rewrite the shard-selection comment block (locale caveat shrinks — manifest assignments are collation-independent).
- `work/SKILL.md` §9 + any positional-prose sweep.
- #8006: follow-through `ci-leg-durations-8006.sh` stays (worst-leg ≤900s should now measure ~540s); note manifest arm on the issue.

### Bootstrap + verification

- v1 manifest generated from run 35840517639 artifacts (already in `/tmp/timings`); refresh from first green post-merge main run.
- Expected: worst light leg ~450s + ~90s setup ≈ **9min** (vs 13m50s).
- No `.ts` files in the diff → the bun-test hook won't fire; verification = targeted suites locally (totality, mutations battery, manifest lint, enumerate-toolchain, aggregator, ship-battery-owed, fullsuite-merge-gate) + authoritative CI.

## Risks

| Risk | Mitigation |
|---|---|
| Manifest staleness | hash fallback covers new labels; lint pins labels ⊆ registered |
| K bumped without regen | positional + notice at runtime; manifest-n==ci-K lint row reds |
| Rename without regen | strict ⊆ lint reds, names regen command |
| Generator bug | skew only, never coverage (totality guard mechanism-agnostic); follow-through probe bounds worst leg |
| Merge conflict on tsv | regenerate (runbook); sorted+sticky output minimizes rate |
| ROW1/ROW4 measure dead path | `SOLEUR_SHARD_MANIFEST=off` wrap keeps positional measured |
| `_shard_selects` arg dropped silently | arity check → exit 2 → enumerate empty → RED |

## Test plan

- [ ] enumerate smoke per group/mode (manifest active, `off`, n-mismatch, absent)
- [ ] `scripts-shard-totality.test.sh` green (35/35 + new registrations)
- [ ] `scripts-shard-manifest.test.sh` green
- [ ] mutations battery: control + all rows incl. 6 new
- [ ] enumerate-toolchain / aggregator / ship-battery-owed / fullsuite-merge-gate / required-checks-parity
- [ ] generator unit test (LPT determinism, stickiness, dup-label warn)
- [ ] shellcheck/shfmt on touched .sh
- [ ] CI: all `test-scripts*` legs green, worst leg ≈9min, `test` aggregator green
