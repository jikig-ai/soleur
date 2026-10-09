---
title: "test-all: cache the affected-derive across local runs"
type: feat
date: 2026-10-09
slug: affected-derive-cache
branch: feat-one-shot-9812-affected-derive-cache
issue: 9812
closes: 9812
lane: single-domain
---

# test-all: cache the affected-derive across local runs

## Overview

Every local `--affected` run of `scripts/test-all.sh` pays the affected pre-pass — a per-registration `_affected_classify` derive over ~585 records — before the first suite starts. On the #9763 idle docs arm (4.40 min) the pre-pass is ~2.5 min of it, ~55% of the local fast tier and larger than all 111 always-on suites combined (~1.9 min measured local). The derive is a pure function of enumerable inputs, so its per-record output (class + ordered edge set) can be cached across runs and re-validated cheaply, leaving the diff-vs-edges verdict (`_diff_touches`) to run fresh each time. This plan adds a per-worktree, gitignored, advisory derive cache; the `affected-prepass-bench` selection-identity contract (ADR-242 decision 16) is the acceptance gate.

## Problem Statement / Motivation

Measured on 2026-10-09 (contended host; proportions, not absolutes — instrumentation detail in `knowledge-base/project/specs/feat-one-shot-9763-local-test-speed/measurements-continuation-2026-10-09.md`, merged via PR #9816):

- `bash scripts/test-all.sh --print-selection --paths=README.md` total: **2m31s**
- nested `--enumerate-commands` child: **0.85s** — negligible
- the `_affected_classify` loop over 585 records: **~150s** — the entire residual cost (~256ms/record; worst single derives: `render-c4-model` ~16s, `community-argv` ~10s)

The classify phase is **diff-independent**: `_affected_classify` computes class + edge set from suite argv, file contents, and path existence only; `_diff_touches` applies the diff afterward (measured ~0, memoized string compares). That split is what makes a derive cache structurally different from the twice-rejected suite-result memo (#7454 item 2, #9804 Proposal 2): those cached verdicts, which ambient state defeats; this caches selection metadata.

## Proposed Solution

A new sourced lib, `scripts/lib/test-affected-derive-cache.sh`, implements a per-record derive cache at `.soleur/cache/affected-derive/v<schema>/` — `.soleur/` is the repo's gitignored local-state root (`.gitignore` "Local state (since-id, caches — do not commit)"; `plugins/soleur/skills/kb-search/scripts/kb-search-cache.sh` precedent — and is per-worktree by construction, so sibling worktrees never share). The selection walk's per-record `_affected_classify` call site (the `SUITE_COMMAND` arm of the `_aff_stream` loop) routes through a cache wrapper.

**Cache key per record:** hash of (schema constant, derive-code hash, label, verbatim argv text). The derive-code hash is the content hash of `scripts/test-all.sh` + `scripts/lib/test-affected-paths.sh` + `scripts/lib/test-relevance-paths.sh` + the new cache lib itself — those files carry `_affected_classify`/`_affected_derive`, the `AFFECTED_*_PATHS`/`AFFECTED_CONSUMED_EDGES`/`ALWAYS_ON_SUITES`/`CLOSURE_LEAF_FILES` inputs, and the cache machinery; any edit to any of them invalidates every record by changing the key.

**Cache entry body** (one file per record, atomic `tmp`-then-`mv` write):

- `schema`, `worktree` (repo root path — belt on top of the per-worktree location; a moved/renamed worktree refuses its own records), `label`, `argv_sha`, `class`
- `edge` lines — the ordered `_AC_EDGES` payload, replayed verbatim so the `_PRINT_SELECTION` report stays byte-identical
- `read` lines — every file the derive consulted (recorded at `_affected_file_edges` entry, which covers both fresh reads and `_FE_FILES` memo replays) with its `git hash-object --no-filters` blob id
- `probe` lines — every filesystem existence probe the derive made, with probe kind (`e`/`f`/`d`) and outcome (`hit`/`miss`); a file later created at a recorded-miss path MUST invalidate

**Validation per record** (hit path): re-hash each `read` file (`git hash-object --no-filters --stdin-paths`, batched to one fork per record — portable where `sha256sum` is not) and re-run each recorded probe (`[[ -e ]]`/`[[ -f ]]`/`[[ -d ]]`, ~30 per suite); any mismatch → re-derive that record only and rewrite its entry. Absent/corrupt/malformed/wrong-schema entry → miss → full derive for that record. The cache is advisory: no read path ever narrows selection below what a fresh derive computes, and `unclassified` records (which select unconditionally) replay as `unclassified`.

**Kill switch:** `SOLEUR_AFFECTED_DERIVE_CACHE=0` disables cache reads and writes (repo convention: `SOLEUR_TEST_FORCE_ALL`, `SOLEUR_DISABLE_*`).

## Technical Considerations

- **Probe census (the load-bearing enumeration).** Every probe inside the derive span (`_AC_CLASS=""` through end of `_affected_classify`) must record during a recording run: `_affected_add_edge` (`-e`), `_affected_buf_add` (`-e`), `_affected_edge_token`'s dotted-module `! -e`, `_affected_file_edges`'s `-f` gate, and `_affected_derive`'s four `-f`/`-e` sites (argv `*.sh`-family suite-file checks, dotted-module `_mod.py`, closure enqueue `-f`). The `[[ -d "$PWD" ]]` liveness probe (`_wt_missing_die`) is named-exempt — it is not an edge input. A census arm in the new test suite greps the extracted derive block for `-e`/`-f` probe shapes and asserts each is either routed through the recorder or on a named exempt list — a probe site added later without recording fails the suite rather than silently weakening invalidation.
- **Replay completeness.** A cached replay must restore `_AC_CLASS`, `_AC_EDGES`, the `_AC_ESET` shadow set (rebuilt via the same `_affected_resolve_edges` idiom — eval-by-name for bash 3.2), and `_AC_SUITE_FILE` (stored or cleared — never left stale from a prior record). Edge ORDER is preserved verbatim: the print-selection report joins edges in order.
- **Recording mode.** The wrapper sets a recording flag before calling `_affected_classify`; the probe/read sites append to per-record `_AC_REC_PROBES`/`_AC_REC_READS` only when it is set. Non-walk callers (`_affected_emit_receipt` under `--print-affected-set`, `TEST_GROUP` rungs) never see the flag — receipt mode's class is the same but its edge set is deliberately partial (the union derive is skipped under `_PRINT_AFFECTED==1`), so receipt mode may never WRITE cache records.
- **Concurrency and interruption.** Concurrent `test-all` runs in one worktree write the same deterministic content to the same keys; atomic per-record writes make last-writer-wins safe, and a killed run leaves a partial cache that still validates next run. Cache writes that fail (unwritable `.soleur/`, preflight Check 10's read-only-repo bwrap sandbox) degrade to plain derive with at most one stderr note — never a nonzero exit.
- **CI.** `CI=1`/`--affected` CI runs get a cold cache each time; the mechanism is transparent there and changes nothing about merge gating (`--affected` already narrows only locally). No CI workflow or gate changes.
- **The enumerate child stays uncached** (0.85s — measured negligible); it produces the live registration stream every run, so added/removed/changed registrations are seen naturally: a new argv hashes to a new key (miss → derive), a stale record is unreachable (key mismatch).
- **GC.** The cache dir is bounded by registration count (~600 small files); a `find -mtime +30 -delete` sweep on write keeps churn from accumulating. Bash 3.2/BSD-compatible (no `sha256sum`, no `date -d`, no `readlink -f` anywhere in the lib — `git hash-object` is already a runner dependency).
- **Bench interplay.** The new `source scripts/lib/test-affected-derive-cache.sh` line in test-all.sh is a real load edge on a closure-leaf file (ADR-242 decision 18), so the acceptance bench invocation is `bash scripts/affected-prepass-bench.sh --base <merge-base> --added-edges scripts/lib/test-affected-derive-cache.sh`. The bench runs each side in a scratch worktree — cold cache on first probe, warm thereafter, which also exercises both paths.

## Research Reconciliation — Spec vs. Codebase

| Issue/arc claim | Codebase reality (verified 2026-10-09) | Plan response |
|---|---|---|
| pre-pass ~55% of fast tier; ~2.5 min of the 4.40 min docs arm | Held — `measurements-continuation-2026-10-09.md` (on main via #9816): classify loop ~150s, enumerate child 0.85s, `_diff_touches` ~0 | Adopt figures; re-measure before/after on the idle host per AC1 |
| `affected-prepass-bench.sh --base <merge-base>` is the acceptance contract | Held — exists, operator-run, byte-compares `AFFECTED_SELECTED` streams; ADR-242 d16 names it the gate | AC2 uses it, plus `--added-edges` for the new source line |
| miss set recordable at `_affected_buf_add`'s `-e` check | Partially — that is one of SEVEN probe sites (see Technical Considerations); recording only there would leave argv/stem/closure probes unrecorded | Census all probe sites; the issue's mechanism survives, its named site is widened to the full set |
| `_FE_FILES` memo enumerates the positive read set | Held — but it is a per-PROCESS memo across all records; a per-record read set needs recording at `_affected_file_edges` entry | Record per-record at that entry point |
| `.cache/` or `$XDG_CACHE_HOME/soleur/<worktree-id>` | Repo precedent is `.soleur/` (gitignored "Local state", kb-search cache): per-worktree by construction, chmod 700 convention shipped | `.soleur/cache/affected-derive/` — see Alternative Approaches |

## Research Insights

**Premise Validation (Phase 0.6):** #9812 OPEN; #9763 CLOSED (measurements arc, landed); PR #9816 MERGED (measurements doc on main); #9307 OPEN (umbrella, referenced not scoped); #7454/#9804 confirm the suite-result memo was rejected (this design caches selection metadata, not verdicts); #9762 CLOSED (pyramid audit — demotions explicitly out of scope here). All cited files/symbols verified on the branch: `scripts/test-all.sh` (`_affected_classify` :3085, `_affected_buf_add` :2778, `_FE_FILES` :2768, walk call site :3607), `scripts/lib/test-affected-paths.sh` (`ALWAYS_ON_SUITES` :94), `scripts/lib/test-relevance-paths.sh`, `scripts/affected-prepass-bench.sh`, ADR-242 decisions 16–20.

**Property List (Phase 0.6b):**

1. Warm-cache `--print-selection`/pre-pass wall-clock drops from ~2.5 min to seconds.
2. Selection stays byte-identical (bench exit 0).
3. Invalidation is exact: an input change re-derives only the affected record(s).
4. The cache is advisory: absence/corruption/schema drift falls back to full derive, never to a narrowed selection.
5. CI merge gating is unchanged.

**Cut List (Phase 0.6b):**

- `$XDG_CACHE_HOME/soleur/<worktree-id>` → property "per-worktree, siblings never share" → already covered by `.soleur/` (worktree-rooted, gitignored, shipped convention). The XDG form would need a worktree-id derivation layer for the same property — cut.
- Caching the `--enumerate-commands` child stream → property 1 only weakly (0.85s measured) → cut; live enumeration also gets added/removed-registration correctness free.
- Caching selection verdicts → rejected twice (#7454, #9804); never proposed here.
- TTL-based expiry of records → property 3 is exact invalidation, not staleness; a TTL would only buy GC, which the 30-day prune covers without a second mechanism — cut.

**Value-proposition measurement (Phase 0.6c):** the saving is measured, not asserted — `bash scripts/test-all.sh --print-selection --paths=README.md` instrumented with `EPOCHREALTIME` around classify (procedure in the measurements doc): ~150s classify on a contended host; ~2.5 min of the 4.40 min idle docs arm. Validation-per-record estimate: ~30 `[[ -e ]]` probes + one batched `git hash-object` fork — seconds for the whole walk.

**Relevant institutional learnings:** `2026-10-04-a-flag-from-one-probe-gated-rows-that-needed-another-and-a-sha-does-not-survive-a-rebase.md` (probe populations must enumerate every site class); `2026-09-29-my-elif-arm-ate-the-selection-walk...` (emit/branch placement inside the walk is load-bearing); `2026-10-01-anchoring-a-matcher-flips-its-error-direction...` (a new suite is REGISTERED — run `lint-orphan-test-suites.sh` — and its own derive cost counted); `2026-09-30-print-affected-set-prints-classes-not-selection` (receipt class ≠ selection verdict).

**Conventions:** bash 3.2-compatible runner (no `declare -A`/`declare -n`; eval-by-name array idiom); libs sourced via `$(dirname "${BASH_SOURCE[0]}")/lib/`; `git` calls scrub `GIT_DIR`/`GIT_WORK_TREE`/`GIT_INDEX_FILE`/`GIT_CONFIG*` per the `_aff_rd_hash` idiom (:2167); probes resolve repo-relative against the runner's repo-root cwd; `.soleur/` caches chmod 700 dir / 0600 files.

## Implementation Phases

### Phase 1: Cache lib + recording instrumentation

- Create `scripts/lib/test-affected-derive-cache.sh`: `_ADC_SCHEMA` constant (asserted by its own reader), record/validate/replay/write/prune functions, kill-switch check, atomic write, `git hash-object` batching with the env-scrub idiom.
- In `scripts/test-all.sh`: source the lib beside the existing `_AFF_LIB`/`_REL_LIB` block; add recording hooks at every derive probe/read site (census above); route the walk's `_affected_classify` call site through the wrapper; emit `AFFECTED_DERIVE_CACHE hits=<n> misses=<n> derived=<n>` at walk end.
- Add `AFFECTED_TEST_AFFECTED_DERIVE_CACHE_PATHS` declared edges in `scripts/lib/test-affected-paths.sh` covering `scripts/lib/test-affected-derive-cache.sh`, `scripts/test-all.sh`, and the test file (the stem convention already reaches `scripts/lib/`; the declaration is explicit cover, honest under the census linter).

### Phase 2: Test arm

- Create `scripts/test-affected-derive-cache.test.sh` (same extract-and-eval harness shape as `scripts/test-affected-derive.test.sh`; owning `trap` BEFORE `source` of test helpers; counted skip rows fail under CI): byte-identical replay (class + ordered edges + shadow set), in-closure edit → re-derive, file created at a recorded-miss path → invalidate, unrelated edit → hit, corrupt entry → fall back, wrong schema → fall back, kill switch → full derive, argv change → miss, probe-site census row.
- Register it via a `run_suite` line in `scripts/test-all.sh` (registration-only runner edit per ADR-242 decision 20); verify registration with `scripts/lint-orphan-test-suites.sh`.

### Phase 3: Measure + ADR amendment

- Measure before/after `--print-selection --paths=README.md` wall-clock on an idle host; record in `knowledge-base/project/specs/feat-one-shot-9812-affected-derive-cache/measurements-derive-cache.md`.
- Amend ADR-242 with a new decision recording the derive-cache contract (key inputs, advisory fallback, bench gate) and run `scripts/check-adr-ordinals.sh`.
- Run the acceptance bench: `bash scripts/affected-prepass-bench.sh --base <merge-base> --added-edges scripts/lib/test-affected-derive-cache.sh` (exit 0).

## Files to Create

- `scripts/lib/test-affected-derive-cache.sh`
- `scripts/test-affected-derive-cache.test.sh`
- `knowledge-base/project/specs/feat-one-shot-9812-affected-derive-cache/measurements-derive-cache.md`
- `knowledge-base/project/specs/feat-one-shot-9812-affected-derive-cache/tasks.md` (workflow-generated)

## Files to Edit

- `scripts/test-all.sh` (source lib, probe recording, walk wrapper, emit line, suite registration)
- `scripts/lib/test-affected-paths.sh` (declared edges for the new suite)
- `knowledge-base/engineering/architecture/decisions/ADR-242-the-local-gate-defaults-to-affected-suites-and-always-on-ratchets.md` (new numbered decision)
- Pipeline-written, not authored: `knowledge-base/INDEX.md`, `knowledge-base/project/specs/feat-one-shot-9812-affected-derive-cache/session-state.md`

## Open Code-Review Overlap

- #8659 (`test-all.sh`, test-helpers EXIT-trap composition) — **acknowledge**: different concern; the cache touches no trap machinery.
- #7942 (`test-all.sh`, mutation-battery naming) — **acknowledge**: unrelated registration metadata.
- #8800 (`test-affected-paths.sh`, census-sandbox inode sharing) — **acknowledge**: the cache's declared-edge addition does not touch the sandbox fixture.

## User-Brand Impact

- **If this lands broken, the user experiences:** a local `test-all` run whose affected selection is wrong — mitigated structurally: a bad entry can only over-select (stale edges run more suites) or under-select is refused by the bench gate + the zero-selected refusal; worst deployable case is lost speed, never lost coverage.
- **If this leaks, the user's [data / workflow / money] is exposed via:** nothing — the cache stores repo-relative paths and blob hashes of the public tree under `chmod 700` `.soleur/`, gitignored.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** internal dev-tooling performance with a byte-identical-selection acceptance contract; no user-facing surface.

## Observability

```yaml
liveness_signal:
  what: AFFECTED_DERIVE_CACHE summary line (hits/misses/derived) emitted at the end of every selection walk
  cadence: per local --affected/--print-selection run
  alert_target: none — local dev tooling; the line is operator-visible in run output
  configured_in: scripts/test-all.sh (walk epilogue)
error_reporting:
  destination: stderr of the invoking run (repo convention for the runner)
  fail_loud: cache read/write/parse failures degrade to a miss + at most one stderr note; never a nonzero exit — that is the designed loudness ceiling for an advisory cache
failure_modes:
  - mode: entries never validate (e.g. code-hash churn bug)
    detection: AFFECTED_DERIVE_CACHE reports misses ~= records across two consecutive unchanged-tree runs
    alert_route: operator reads the run output; the cache-lib unit test's hit arm is the CI-visible cover
  - mode: cache dir unwritable (read-only sandbox)
    detection: single stderr degrade note; run proceeds at uncached speed
    alert_route: none — advisory
logs:
  where: the AFFECTED_DERIVE_CACHE line on stdout/stderr of the run
  retention: run lifetime (no persistent log)
discoverability_test:
  command: rg -n AFFECTED_DERIVE_CACHE scripts/test-all.sh
  expected_output: AFFECTED_DERIVE_CACHE
```

## Encryption Posture

```yaml
at_rest:
  - store: .soleur/cache/affected-derive/ (operator-local filesystem, per-worktree, gitignored)
    mechanism: plaintext-exception
    evidence: the writer in scripts/lib/test-affected-derive-cache.sh — contents are repo-relative path names and git blob ids of the tracked public tree; no credential, no user data, no PII
    defends_against: nothing — there is nothing to defend (content is derivable from the checkout itself)
    does_not_defend: a reader with filesystem access to the worktree sees which paths the derive touched — all already present in the public repo
    disclosed_as: not-publicly-claimed
    live_verification: available — `ls .soleur/cache/affected-derive/` after any --affected run
in_transit: []
exception:
  justification: the store is an operator-local disposable cache of public-repo path names and content hashes; plaintext is the correct posture, there is no confidential payload
  tracking_issue: "#9812"
  reevaluate_when: the cache ever stores content that is not derivable from the public tree
  expires_on: 2027-01-07
```

## Guard Contract

### Guard 1 — cache validation refuses stale inputs

**Property.** A cached record whose recorded inputs no longer match the tree is never replayed; every input change (read-file content, probe outcome, argv, derive code, schema) falls back to a fresh derive for exactly that record.

**Assembly.** Every validation rung in `scripts/lib/test-affected-derive-cache.sh`'s validate path AND every probe/read recording site in the derive span of `scripts/test-all.sh` — the two halves must cover the same input set; the census row in `scripts/test-affected-derive-cache.test.sh` derives the probe set from the extracted derive block (not a hand list) and refuses an unrecorded probe site.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Edit a file inside a cached record's read set | RED — that record re-derives |
| 2 | Create a file at a recorded-miss probe path | RED — invalidated |
| 3 | Flip one bit in a stored `class` field (corrupt entry) | RED — record rejected, full derive |
| 4 | Remove the recorder call at one probe site (guard's own dispatch) | RED — census row counts a probe site outside the recorded/exempt set |
| 5 | Add a SECOND `-e` probe inside the derive span after the existing ones (second member) | RED — census sees an unrecorded probe |
| 6 | Corrupt the suite's expected-hit report (harness row: assertion count must move) | RED |
| 7 | Edit a file NO record reads (must-PASS control, differing as the contract permits) | PASS — every record hits |

### Guard 2 — advisory-only fallback

**Property.** Any failure of the cache layer (absent dir, unreadable record, schema mismatch, unwritable FS, kill switch) produces the identical selection a cold tree produces — never an error exit and never a narrowed set.

**Assembly.** Every entry and exit of the cache wrapper around the `_affected_classify` call site in the `_aff_stream` walk, plus the lib's open/parse/hash/probe failure arms.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Pre-create `.soleur/cache/affected-derive/` read-only (unwritable) | RED — suite asserts run completes with identical selection |
| 2 | Truncate a record file mid-body | RED — parse refuses; derive substitutes |
| 3 | Bump `_ADC_SCHEMA` with stale records present | RED — all records miss, re-derive |
| 4 | Neuter the fallback arm so a corrupt entry yields empty edges (guard's own dispatch) | RED — zero-selected refusal / class-mismatch fires in suite |
| 5 | Make the reader accept a record with HALF its `read` files hashed (second member = partial validation) | RED — an edited second file must still invalidate |
| 6 | `SOLEUR_AFFECTED_DERIVE_CACHE=0` (must-PASS: documented off switch, differs as the contract permits — derive fresh, selection identical) | PASS |

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change to the repo-local test runner. Mechanical UI-surface scan: `## Files to Create`/`## Files to Edit` contain no UI-surface paths (no `components/**/*.tsx`, `app/**/page.tsx`, `app/**/layout.tsx`, or ui-surface term matches), so the Product/UX override does not fire.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Warm-cache `--print-selection` wall-clock drops from ~2.5 min to seconds; measured before/after on an idle host, recorded in the spec dir." | Phase 3 + AC1 + `measurements-derive-cache.md` | mapped |
| 2 | "Selection is byte-identical: `scripts/affected-prepass-bench.sh --base <merge-base>` exits 0" | Phase 3 + AC2 | mapped |
| 3 | "A test arm proves invalidation: edit a file in a suite's closure → that record re-derives; create a file at a recorded-miss path → invalidate; edit an unrelated file → cache hits." | Phase 2 + Guard 1 + AC3 | mapped |
| 4 | "Cache is advisory only: corruption/absence/wrong schema falls back to full derive, never to a narrowed selection." | Guard 2 + AC4 | mapped |
| 5 | "No change to CI merge gating" | Technical Considerations + AC5 | mapped |
| 6 | "per-worktree, gitignored … key includes the worktree path so siblings never share" | Proposed Solution (`.soleur/` + `worktree` field) + AC6 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `scripts/lib/test-affected-derive-cache.sh` | asks 1–4 | asked |
| `scripts/test-all.sh` edits | asks 1, 2 | asked |
| `scripts/test-affected-derive-cache.test.sh` | ask 3 | asked |
| `measurements-derive-cache.md` | ask 1 | asked |
| `AFFECTED_TEST_AFFECTED_DERIVE_CACHE_PATHS` declared array | — | inferred — justification: without declared edges the new suite's own selection is under-reached by the runner it exercises (the `runner-changed` fallback covers diffs TO the runner, not the lib-only case) |
| ADR-242 amendment (decision 21) | — | inferred — justification: `wg-architecture-decision-is-a-plan-deliverable`; a cross-run cache of gate inputs is a decision future readers must find in the ADR |
| `SOLEUR_AFFECTED_DERIVE_CACHE=0` kill switch | — | inferred — justification: repo convention for advisory mechanisms (`SOLEUR_TEST_FORCE_ALL`, `SOLEUR_DISABLE_*`); the only honest exit if the cache misbehaves on an unusual host |
| Probe-site census row in the test suite | — | inferred — justification: a probe site added later without recording silently breaks invalidation; the property needs a census, not a named list (membership drifts) |
| `AFFECTED_DERIVE_CACHE` emit line | — | inferred — justification: observability gate (hit-rate telemetry is the only way a never-hits regression surfaces) |

### Split Assessment

- Subsystems touched: 2 — `scripts/`, `knowledge-base/`
- Planned files: 7 | Estimated changed lines: ~700
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

- [ ] AC1 — Warm-cache `bash scripts/test-all.sh --print-selection --paths=README.md` wall-clock measured before/after on an idle host and recorded in `knowledge-base/project/specs/feat-one-shot-9812-affected-derive-cache/measurements-derive-cache.md`; warm run is in seconds (not minutes). Deterministic leg (not ambient-load-dependent): on a second consecutive unchanged-tree run the emitted `AFFECTED_DERIVE_CACHE` line reports `misses=0` over the served records.
- [ ] AC2 — `bash scripts/affected-prepass-bench.sh --base <merge-base> --added-edges scripts/lib/test-affected-derive-cache.sh` exits 0 (byte-identical `AFFECTED_SELECTED` selection).
- [ ] AC3 — `bash scripts/test-affected-derive-cache.test.sh` exits 0 and covers: in-closure edit → record re-derives; file created at recorded-miss path → invalidates; unrelated edit → cache hits; byte-identical replay of class + ordered edges.
- [ ] AC4 — Advisory-only: suite rows prove absent dir, corrupt record, wrong schema, unwritable dir, and `SOLEUR_AFFECTED_DERIVE_CACHE=0` each yield the identical selection as a cold run with no error exit.
- [ ] AC5 — No CI merge-gating change: `git diff --quiet origin/main...HEAD -- .github/` succeeds (no workflow/required-check edits).
- [ ] AC6 — Cache lives under `.soleur/cache/affected-derive/` (gitignored); each record carries the worktree path and mismatched records are refused.
- [ ] AC7 — Probe-site census: the suite derives the `-e`/`-f` probe set from the extracted derive block and fails on any site neither recorded nor named-exempt.
- [ ] AC8 — Registration: `scripts/lint-orphan-test-suites.sh` reports the new suite registered; `AFFECTED_DERIVE_CACHE hits=` line present in run output.

## Test Scenarios

- Given a warm cache and unchanged tree, when `--print-selection --paths=README.md` runs, then wall-clock is seconds and the AFFECTED_SELECTED stream equals the cold-run stream. (`e2e` — `pyramid-justified: the property is end-to-end wall-clock on the real runner`)
- Given a cached record, when a file in its recorded read set is edited, then that record alone re-derives. (`unit` — suite row in test-affected-derive-cache.test.sh)
- Given a cached record, when a file is created at a recorded-miss probe path, then the record invalidates. (`unit`)
- Given a cached record, when an unrelated file changes, then the record serves from cache. (`unit`)
- Given a corrupt/truncated/schema-mismatched record, when the walk runs, then selection equals a cold run and exit is 0. (`unit`)
- Given a read-only `.soleur/` or `SOLEUR_AFFECTED_DERIVE_CACHE=0`, when the walk runs, then identical selection, no nonzero exit. (`unit`)

## Success Metrics

- Warm `--print-selection` wall-clock: from ~2.5 min to seconds (idle host).
- Cache hit rate across consecutive unchanged-tree runs: misses ~= 0.
- Zero selection drift: bench exit 0 on the acceptance invocation.

## Dependencies & Risks

- **Risk: an unrecorded probe/read site silently weakens invalidation.** Mitigated by AC7's census row (derived probe set, named-exempt list) and the bench gate.
- **Risk: per-record hashing cost creeps back toward the derive.** Validation is `[[ -e ]]` probes + one batched `git hash-object` per record — bounded by design; AC1 measures it.
- **Risk: edge-order or shadow-set drift on replay.** Replay restores `_AC_EDGES` verbatim and rebuilds `_AC_ESET` through the same `_affected_resolve_edges` idiom; AC3 asserts byte-identical replay.
- **Risk: concurrent writers.** Deterministic content + atomic tmp/mv per record; worst case redundant re-derive.
- **New suite's own cost:** the suite must stay in the committed-weight envelope; its derive adds one record to the pre-pass — counted, per the 2026-10-01 learning.
- **Deferral tracking:** none — no deferred items in this plan (pyramid demotions are out of scope by issue text and tracked by the #9762 arc, not deferred from here).

## Alternative Approaches Considered

| Approach | Why not |
|---|---|
| `$XDG_CACHE_HOME/soleur/<worktree-id>` | Needs a worktree-id derivation layer for a property `.soleur/` already provides by construction (per-worktree, gitignored); XDG also lives outside the tree, so preflight-style read-only-repo sandboxes and `git clean` semantics diverge from the shipped convention (`kb-search-cache.sh` notes no `~/.cache/soleur/` exists). |
| Suite-result memo (#7454/#9804 Proposal 2) | Rejected twice: ambient env/machine state and untracked producer/consumer pairs defeat a verdict key. This plan caches derive inputs/outputs only. |
| Cache the enumerate child stream | Measured 0.85s — not the cost; live enumeration gets registration churn right for free. |
| TTL/time-based expiry instead of input hashing | Staleness without exactness — an expired-but-valid entry re-derives (waste) and a fresh-but-stale entry serves (wrong); the issue's hash-the-inputs model is exact. |
| Inline the cache into `test-all.sh` instead of a lib | Possible, but the lib shape matches `test-affected-paths.sh`/`test-relevance-paths.sh` precedent and keeps a 5900-line file from growing; cost is one `--added-edges` flag on the bench. |

## Architecture Decision (ADR/C4)

### ADR

- Amend `knowledge-base/engineering/architecture/decisions/ADR-242-the-local-gate-defaults-to-affected-suites-and-always-on-ratchets.md` with a new numbered decision (provisional **21** — renumber if a sibling claims it; `scripts/check-adr-ordinals.sh` and ship's ordinal gate apply): the affected derive's outputs are cached per-record across local runs keyed on schema + derive-code hash + argv, validated by hashing recorded reads and re-running recorded probes, advisory-only with full-derive fallback, and certified by the affected-prepass-bench selection-identity contract plus `--added-edges`.

### C4 views

No C4 impact. Enumeration per the completeness mandate (all three files read — `model.c4`, `views.c4`, `spec.c4`): (a) external human actors — none new (the operator running `test-all` locally is the existing `founder`/`contributor` surface); (b) external systems/vendors — none (a local filesystem cache); (c) containers/data-stores — `.soleur/cache/` is operator-local dev state, not a platform store (the repo's own test runner is not a modelled element); (d) actor↔surface relationships — unchanged.

### Sequencing

The ADR amendment lands in this PR with `status`-equivalent wording of the shipped behavior (the decision is true when the cache lands, no soak).

## Sharp Edges (applied this pass)

- Portability: no `sha256sum`/`timeout`/`date -d`/`readlink -f` in the lib — `git hash-object --no-filters --stdin-paths` is already a runner dependency (the `_aff_rd_hash` env-scrub idiom is reused verbatim).
- New suite registration: verify with `lint-orphan-test-suites.sh` once the file is tracked, and count the suite's own derive cost — per `2026-10-01-anchoring-a-matcher-flips-its-error-direction...`.
- `discoverability_test.command` is probe-verb-allowlisted (`rg`) with a literal `expected_output` token and no shell metacharacters — verified runnable in the Check-10 sandbox shape.
- Diff-scope AC (AC5) is merge-base (`origin/main...HEAD`), not moving-tip.
- No `SOLEUR_*` marker is introduced — `AFFECTED_DERIVE_CACHE` extends the runner's existing `AFFECTED_*` vocabulary in `scripts/` (outside the `skills/*/scripts/` marker census).

## References & Research

- Issue: #9812 (spec); arc: #9763 + PR #9816 (measurements); umbrella #9307; rejected precedent #7454 item 2 / #9804 Proposal 2.
- Measurements: `knowledge-base/project/specs/feat-one-shot-9763-local-test-speed/measurements-continuation-2026-10-09.md`
- ADR: `knowledge-base/engineering/architecture/decisions/ADR-242-the-local-gate-defaults-to-affected-suites-and-always-on-ratchets.md` (decisions 16, 18, 20)
- Cache-location precedent: `plugins/soleur/skills/kb-search/scripts/kb-search-cache.sh` (`.soleur/cache/` + chmod 700 + override-refusal)
- Hashing idiom: `scripts/test-all.sh` `_aff_rd_hash` (env-scrubbed `git hash-object --no-filters`)
- Bench contract: `scripts/affected-prepass-bench.sh` header (flags `--base`, `--added-edges`, `--leaf-files`, `--compare-only`)
