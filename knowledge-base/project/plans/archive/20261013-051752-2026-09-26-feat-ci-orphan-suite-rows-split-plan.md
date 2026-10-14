---
title: "ci: split lint-orphan-test-suites-mutations across two shard legs via --rows"
date: 2026-09-26
slug: feat-ci-orphan-suite-rows-split
branch: feat-ci-orphan-suite-rows-split
issue: 8864
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

## Overview

The `test-scripts` light group's worst leg is one atomic suite,
`lint-orphan-test-suites-mutations` (~9.8 min of 588.8 s measured on run
36125573947). Add a `--rows A-B` range gate to its battery — copying the
`DECLARED_TOTAL` semantics of `plugins/soleur/test/scripts-shard-totality-mutations.sh` —
register two half-suites in `scripts/test-all.sh` so the duration-aware
manifest distributes them, add a tiling guard that fails if the registered
ranges stop covering 1..DECLARED_TOTAL, and fix the stale "six legs" comment.

## Research Insights

**Premise validation (Phase 0.6).** #8864 is OPEN; its collision constraint
(PR `feat-one-shot-8736-deploy-script-tests-parallel`, #8763) is MERGED
2026-09-25 — the `want_scripts` registration region is unfrozen. The battery
file exists with no `--rows` flag (build, not patch). The mechanism appears in
no ADR's rejected-alternatives table: ADR-240 (checked-in manifest), ADR-193
(anti-vacuity floor contract), ADR-181 (command-anchored extraction) are all
compatible. **Verified:** `scripts/test-all.sh:4592` reads "the lighter
scripts group fans out over six legs" (comment is stale; matrix is `["1/7"…"7/7"]`).

**Property List.**
- P1 — worst light leg < ~9.5 min suite time (the issue's trigger).
- P2 — zero silent coverage loss: every declared mutation row executes on
  exactly one leg, provably.
- P3 — comments/numerals in the edited regions describe reality (six→seven
  legs; "eleven rows" → actual count).

**Cut List.**
- Move-to-`want_scripts_heavy` → serves no property (relocates the same
  ~9.8 min floor onto a heavier toolchain, +1 runner, extra TSV) — cut at
  brainstorm D-NG1.
- `registry-gate-mutation-battery` row-split → P1 for a different suite;
  separately tracked, sequenced after this lands — cut at brainstorm NG2.
- Dedicated ci.yml matrix job (the `shard-totality-mutations` shape) → P1 is
  already served by the duration-aware manifest, which rebalances by
  measurement; a fixed 2-leg job bypasses LPT — cut.
- Raising `SOLEUR_ORPHAN_MUT_JOBS` (pool already oversubscribed at 8 on
  ~4-vCPU runners; cannot shorten a single dominant row regardless of
  pool width) — cut.
- Central `declare -A ROW_ASSERT_FLOOR` table → supplanted by the
  co-located 4th `.rc` field on locality grounds — cut at plan review.

**Value measurement (Phase 0.6c).** Suite time 588.8 s on run 36125573947
(suite-timings artifact; cited in #8864 body + the sharding runbook's
2026-09-25 entry). Post-split predicted halves ≈ 4–6 min each → worst leg
~6.5 min incl. ~0.4 min setup. Source: `scripts/suite-shard-legs.tsv` header
`generated-from-run=36125573947`.

**Mechanics — the battery (`scripts/lint-orphan-test-suites.test.sh`, 721 lines).**
- 19 counted row sites: `ROW_IDS="C0 M1 … M16"` (17, dispatched under a
  bounded-parallel `wait` pool at :609-633) + serial greps R1 (:669) and
  R1b (:687). Each worker writes `PASS FAIL GLOB_MEMBER_N` to
  `$TMP/rows/<id>.rc`; a missing `.rc` is `harness_die` — so the range gate
  must select the dispatch set AND the replay/aggregation loops iterate that
  same set. Skipped rows must never be dispatched, never replayed.
- `MIN_ROWS=18` (:706) already under-pins: 19 sites vs floor 18 — deleting R1
  or R1b does NOT fire the FATAL today (latent slack; the DECLARED_TOTAL
  conversion fixes it as a side effect).
- `MIN_ASSERTIONS=$(( MIN_FIXED + 2*GLOB_MEMBER_N ))` (:708-709) is derived,
  and `GLOB_MEMBER_N` is populated ONLY by worker M5 — when M5 is out of range
  the floor silently loosens. Range-scoping needs a per-row declared-assertion
  table (or equivalent subset sum), plus `2*GLOB_MEMBER_N` only when M5
  executes. The :643-645 comment's arithmetic (49+3=52) already disagrees
  with `MIN_FIXED=51` — recompute from the table, not the comment.
- CONTROL semantics: the precedent runs its control row unconditionally on
  every leg. C0 (the noop control) therefore stays unconditional — gated
  rows are M1–M16 only, `DECLARED_TOTAL=16`. R1/R1b are cheap serial greps;
  keep unconditional (not gated sites).

**Mechanics — the precedent (`plugins/soleur/test/scripts-shard-totality-mutations.sh`).**
`DECLARED_TOTAL` constant (:76); `--rows A-B` parser with
`^[0123456789]+-[0123456789]+$` (enumerated digit class, collation-safe),
`10#` decode, bounds `1<=A<=B<=DECLARED_TOTAL` else exit 2, unknown args
usage-error (:79-100); `in_range()` increments `_row_seq` on EVERY call and
`EXECUTED` only in-range (:108-115); per-leg assertions:
`_row_seq == DECLARED_TOTAL`, `EXECUTED == hi-lo+1`, `EXECUTED >= 1`
(:699-712). Commit-boundary rule: `B > DECLARED_TOTAL` is refused, so a
DECLARED_TOTAL bump and a range re-split must land in the same commit.
Its split is a **ci.yml matrix** (`rows: ["1-12","13-24"]`, ci.yml:1345) —
ours is `run_suite` argv instead; same flag semantics, different split site.

**Mechanics — registration & consumers.**
- `lint-orphan-test-suites.sh:193` extracts the `.test.sh` command token;
  trailing `([[:space:]].*)?$` tolerates `--rows A-B`; two registrations with
  the same command union-dedupe into one surface-1 covered set. The
  double-coverage refusal fires only across the six surfaces. #7103 rule:
  anchor on the COMMAND, never the label (ADR-181:84-89).
- `run_suite` (:1475) shifts `$1` as label; `_shard_selects` is label-keyed
  (manifest or cksum hash-fallback); `"$@"` flows verbatim to dispatch/exec
  (:1583) — `--rows` args just work. `--enumerate` emits the label;
  `--enumerate-commands` emits argv including the flag (extra TAB fields OK).
- Label-rename consumers: `scripts/suite-shard-legs.tsv:350` (phantom row →
  ⊆ lint RED until updated), `scripts/lib/test-affected-paths.sh:103`
  ALWAYS_ON_SUITES (staleness census REDs on the dead entry; this battery's
  `git ls-files` forces a declared class via the repo-wide-idiom arm),
  registration comment at test-all.sh:3477-3481 ("eleven rows" — already
  stale at 19 sites), runbook mention. All update in the SAME commit.
- Tiling-guard home: `plugins/soleur/test/scripts-shard-totality.test.sh` —
  it hosts the structurally identical check (:695-738, ci.yml-matrix
  extractor) and already statically extracts `run_suite` lines (:131-140).
  `scripts-shard-manifest.test.sh` never parses test-all.sh at all — wrong
  home. New extractor: grep `run_suite` lines carrying `--rows` for this
  command token (join backslash continuations; anchor on the flag argument,
  not the label; beware the flag text appearing in comments — the
  own-comment match class, learnings 2026-09-23).
- If the extractor ever runs `test-all.sh --enumerate`, scrub
  `SCRIPTS_SHARD`/`TEST_GROUP` (`env -u`) — inherited env narrows the
  enumerate to one leg (the generator-subprocess lesson). Preferred: parse
  the lines directly, no subprocess.
- Ordinal-shift: adding a registration shifts every later ordinal; under the
  positional degrade path legs silently recompose — the manifest TSV update
  lands in the same PR (hand-edit: drop the phantom row, pin `-a`/`-b` on
  distinct legs ≤ n=7; sticky-LPT rebalances on the next green-run regen).
- `--affected` degrades to the full battery on any `run_suite` diff —
  budget for a longer CI run on this PR.
- ADR-193 floor contract: floors report `printf >&2` + `exit 1` directly
  (never through `fail()`), counters increment at call sites, the
  conservation check runs first, and the floor constant sits on the line
  immediately above its `if` (the mutant builder slices backward).

**Open code-review overlap:** #8659 (EXIT-trap battery replacements — does
not name this file) and #7942 (two unregistered `*.mutation.sh` batteries —
different files). Disposition: acknowledge both; unrelated scope.

**Related issues/PRs:** #8864 (target), #8763 (collision, merged), #8854
(K=7 rebalance, merged), #8927 (sibling residuals tracker), #6480 (open
promotion affecting the heavy matrix), runbook
`knowledge-base/engineering/operations/runbooks/ci-test-scripts-sharding.md`
(2026-09-25 measured history — this feature is the deferred "suite-internal
split" it names).

## Problem Statement / Motivation

At K=7 the `test-scripts` light group's worst leg is a single suite —
`lint-orphan-test-suites-mutations` at 588.8 s (~10.2 min wall). No matrix
leg count can subdivide an atomic registration, so the light group's floor
is pinned to this suite's own duration until the suite itself splits. The
issue's ~9.5 min re-evaluation trigger is already exceeded, and its
collision constraint (PR #8763) merged 2026-09-25.

## Proposed Solution

Suite-internal split per the `scripts-shard-totality-mutations.sh` precedent:
a `--rows A-B` range gate on the battery, two `run_suite` registrations
carrying complementary ranges, and a union-level tiling guard so a
registration/range drift can never let declared rows execute nowhere.

### Phase 1 — `--rows` gate + DECLARED_TOTAL floors (battery file)

Edit `scripts/lint-orphan-test-suites.test.sh`:

1. Add `DECLARED_TOTAL=16` — the gated space is the mutation rows `M1`–`M16`.
   `C0` (noop control), `R1`, and `R1b` stay **unconditional** on every leg
   (precedent: CONTROL + instrument self-test run unconditionally).
2. Port the `--rows A-B` parser from the precedent, **placed before
   `build_pristine`** (an invalid flag must exit 2 before paying the
   expensive sandbox build; precedent parses at :79-100). Same contract:
   `^[0123456789]+-[0123456789]+$`, `10#` decode,
   `1 <= A <= B <= DECLARED_TOTAL` else exit 2, unknown args → usage exit 2,
   `ROWS_HI=0` = all rows. One deliberate divergence: a repeated `--rows`
   exits 2 (the copied `while $#` loop would silently let the last flag win
   — refuse the ambiguity rather than mirror it). **Adapt the ported header
   comment** — do not copy verbatim: it must name `test-all.sh` `run_suite`
   argv as the split site (not ci.yml), state the same-commit
   DECLARED_TOTAL-bump + range-re-split rule, and point at the tiling guard
   in `scripts-shard-totality.test.sh`.
3. Add `in_range()`: increments `_site_seq` on every **gated** call,
   `EXECUTED` only in-range. The gate keys on the row's `M`-suffix ordinal
   (`${_id#M}`), asserted equal to the incremented `_site_seq` (catches a
   duplicate or reordered M-id). **C0 is dispatched ahead of the gate** —
   `C0` shares `ROW_IDS` but is not a gated site, so it must never reach
   `in_range` (a `C0 || in_range` shape consumes site 1 and off-by-ones
   every leg). The replay and aggregation loops iterate a **dispatched-id
   set recorded parent-side at dispatch** (`EXEC_IDS+=("$_id")` or an
   appended `$TMP/executed` file — worker subshells cannot tick parent
   state). Never derive membership by substring match (`M1` ⊂ `M10`–`M16`),
   never re-call `in_range` (stateful — a second pass doubles `_site_seq`),
   and keep `in_range || continue` a standalone parent statement — as the
   left operand of `&&` before `&`, the gate call itself lands inside the
   background subshell and every floor reads zero. A skipped row is never
   dispatched, never replayed — the missing-`.rc` `harness_die` cannot
   fire on an intentional skip — but a `.rc` written for an *undispatched*
   id is FATAL (audit `$TMP/rows/*.rc` directory-side: count ==
   `1 + EXECUTED`, every id dispatched-or-C0).
4. Replace `MIN_ROWS=18` with the equality floors: `_site_seq == DECLARED_TOTAL`
   (a deleted `run_M*` site → FATAL), `EXECUTED == (ROWS_HI==0 ? DECLARED_TOTAL
   : ROWS_HI-ROWS_LO+1)`, `EXECUTED >= 1` (reachable only via gate miswiring —
   it's the misimplementation detector), and the conservation floor
   `ROWS == EXECUTED + 3` (C0 + R1 + R1b — the row that actually pins
   unconditional-site deletion; the current 19-vs-18 slack makes this the
   real fix). Floors report `printf >&2` + `exit 1` directly per
   ADR-193, constant on the line immediately above its `if`.
5. Range-scope `MIN_ASSERTIONS`, **per-row at the worker, not a central
   table or a sum**: each worker's `.rc` gains a 4th field — the row's
   declared expected assertion count, written beside the `run_<id>` call it
   counts — and the aggregation asserts `actual >= declared` per executed
   row (an over-delivering row must not subsidize a hollowed sibling). A
   missing 4th field is FATAL (`read -r _p _f _g _d _t`; `_d`
   mandatory-numeric, `_t` optional — see Phase 2 for elapsed). Unconditional
   base = **5** — `:198` enumeration + `:202` normalisation + R1 + R1b +
   positive-control net +1 — and C0 carries its own declared count (3) in
   its `.rc`, so a deleted R1/R1b drops the total under the floor and dies.
   `2*GLOB_MEMBER_N` applies only when M5 executes (it can fold the term
   into its own declared field — M5 knows the value at write time).
   Recomputed starting values (verify against each `run_M*` at work time):
   M1=3 M2=3 M3=3 M4=2 M5=1 M6=3 M7=2 M8=3 M9=4 M10=3 M11=2 M12=2 M13=4
   M14=3 M15=3 M16=3 — Σ=44; full run total = 5+3+44 + 2·G. Do not trust
   the :643-645 comment, which already disagrees with `MIN_FIXED=51` (true
   total is 52, not "49+3").

### Phase 2 — Registration + manifest (same commit)

1. `scripts/test-all.sh`: replace the single registration (:3486) with
   `run_suite "scripts/lint-orphan-test-suites-mutations-a" bash scripts/lint-orphan-test-suites.test.sh --rows 1-8`
   and `…-mutations-b … --rows 9-16` under the existing `want_scripts` block.
   **Instrument before fixing the boundary:** add a 5th `.rc` field —
   elapsed seconds per row — run the battery once locally, and pick the
   split point that balances the two halves (rows are non-uniform: M5 pays
   per-glob-member linter runs; M1/M3/M9/M10/M13 pay an extra linter
   invocation each; both legs also pay the unconditional PRISTINE build).
   `1-8`/`9-16` is the placeholder only if measurement is skipped. The
   elapsed field is **permanent** — re-splits recur on every
   `DECLARED_TOTAL` bump (commit-boundary rule), and a per-row timing table
   in the replay output turns the next rebalance into a data lookup rather
   than an instrumentation task.
2. `scripts/suite-shard-legs.tsv`: remove the phantom
   `lint-orphan-test-suites-mutations` row; pin `-a`/`-b` on distinct legs
   (≤ n=7) in the SAME commit — the ⊆ lint reds on the phantom the moment
   the label renames. Sticky-LPT rebalances on the next green-run regen.
3. `scripts/lib/test-affected-paths.sh:103` `ALWAYS_ON_SUITES`: swap the old
   label for both new ones (staleness census + repo-wide-idiom arm).
4. Comment fixes: `test-all.sh:4592` "six legs" → "seven legs"; the
   registration comment ~:3477-3481 "eleven rows" → actual count (16 gated
   rows + unconditional C0/R1/R1b); noun-sweep `legs`|`K=` across the edited
   regions only — :3677's "all six jobs" refers to deploy legs, NOT K.

### Phase 3 — Tiling guard (same commit as the registrations)

New block in `plugins/soleur/test/scripts-shard-totality.test.sh` beside the
existing ci.yml-matrix tiling check (:695-738), in the **same commit** as
Phase 2 — the guard is the only artifact closing the hole the split opens.

Extractor contract:

- Parse `run_suite` lines in `scripts/test-all.sh` carrying `--rows` —
  join backslash continuations first, strip `#`-onward (trailing comments,
  not just comment lines, can carry flag-shaped text), anchor on
  `^[[:space:]]*run_suite ` and the flag argument — never the label —
  and never match `skip_suite` (a decline carries a command in decline
  position).
- Group contributions per command token; for each token read
  `DECLARED_TOTAL` from its battery file (`grep -m1 '^DECLARED_TOTAL='`,
  trimmed of trailing comment/whitespace — write the constant bare so the
  guard stays grounded).
- **Sort extracted ranges by lo-bound before the contiguity walk** —
  `run_suite` file order is not a contract (`-b` above `-a` is a valid
  tiling).
- **Non-vacuity clause** (the extractor-drift arm the sibling check already
  carries at :716-717): a `DECLARED_TOTAL`-declaring battery yielding zero
  extracted ranges is a RED finding, never a trivially-tiled empty union.
- **Distinct-legs pin:** assert the `-a`/`-b` manifest rows land on
  different legs (two-line awk over `suite-shard-legs.tsv`) — pinning both
  halves to one leg keeps coverage total but silently defeats the split.
- An *unflagged* same-token registration arm: **deliberate RED** — a mixed
  flagged/unflagged contract is coverage-complete but double-executes and
  is almost always a lost flag; fail loud, not silent.
- A `run_suite` line whose command token's battery lacks `DECLARED_TOTAL`
  is itself a finding (an unsplit job must not ship a `--rows` contract it
  ignores).
- Prefer line parsing over running `--enumerate`; if a subprocess is ever
  used, `env -u SCRIPTS_SHARD TEST_GROUP`.

**Committed RED-driver** (the repo's drive-it-red doctrine): a
positive-control row inside `scripts-shard-totality.test.sh` itself —
mirroring `totality_holds`' positive control at :289-298 — feeding the
comparator a `1-8` + `10-16` fixture against `DECLARED_TOTAL=16` and
requiring the gap to be reported. (The sibling tiling block today has no
committed mutation rows either; a `scripts-shard-totality-mutations.sh`
extractor-mutation arm is the optional fuller version — deferred.)

### Phase 4 — Verification

1. Local: `--rows 1-8`, `--rows 9-16`, no-flag full run; bounds violations
   exit 2 *before* the pristine build (parser placement proves it cheap);
   deleted-site → FATAL; dispatched-worker death → FATAL (`harness_die`
   preserved); rogue `.rc` for an undispatched id → FATAL.
2. Guard-driven RED: drop a range, truncate a range vs DECLARED_TOTAL,
   sort-inverted registrations, overlapping ranges, flag text in a comment —
   each produces the expected verdict (dev-time exercise; the committed
   positive control pins the comparator continuously).
3. `python3 scripts/regenerate-shard-manifest.py --run <id>` (dry-run) to
   confirm no predicted leg ≥ ~9.5 min; `--run` is mandatory (default
   lookup 404s).
4. Neighboring ratchets: run `fixture-relative-assert.test.sh` (baseline
   pins this file at :374 — new floor sites may move its count),
   `guard-vacuity-floor.test.sh` (new floor sites enter its derived
   population — the ADR-193 "constant on the line above its `if`" shape is
   what its slice-widener binds), `no-control-regex` if it exists.
5. CI on this PR: both halves appear as distinct legs (name them in the PR
   body — leg-distinctness evidence); `--affected` degrades to the full
   battery on a `run_suite` diff — expected, not a defect.

## Technical Considerations

- `run_suite` argv forwards verbatim (`"$@"` at :1583); `--enumerate-commands`
  emits the flag as extra TAB fields — no runner change needed.
- Surface-1 extraction tolerates trailing argv (`([[:space:]].*)?$`); both
  halves union-dedupe into one covered set — no double-coverage refusal.
- Commit-boundary rule (from the precedent): `B > DECLARED_TOTAL` is
  refused, so DECLARED_TOTAL bump + range re-split always land together.
- No new infrastructure, no Terraform, no ci.yml matrix change — the halves
  distribute through the existing 7-leg `shard:` matrix via distinct labels.

## Files to Edit

- `scripts/lint-orphan-test-suites.test.sh` — `--rows` parser, `in_range()`,
  DECLARED_TOTAL floors, per-row assertion table, unconditional C0/R1/R1b
- `scripts/test-all.sh` — two registrations (:3486), comment fixes
  (:4592, ~:3478)
- `scripts/suite-shard-legs.tsv` — drop phantom row, pin `-a`/`-b`
- `scripts/lib/test-affected-paths.sh` — `ALWAYS_ON_SUITES` label swap (:103)
- `plugins/soleur/test/scripts-shard-totality.test.sh` — new tiling block
- `knowledge-base/engineering/operations/runbooks/ci-test-scripts-sharding.md` —
  measured-history entry recording the split

## Files to Create

- None — every artifact is an edit to existing machinery.

## User-Brand Impact

- **If this lands broken, the user experiences:** CI that reports green while
  declared mutation rows execute nowhere — a weakened merge gate on every PR
  (the repo's own pre-merge protection degrades silently; the operator's brand
  exposure is a defect shipped under a false-green gate).
- **If this leaks, the user's workflow is exposed via:** a `--rows` range gap
  or a DECLARED_TOTAL/range drift that the per-leg accounting cannot see —
  the exact hole the tiling guard closes.
- **Brand-survival threshold:** `single-user incident`

*CPO sign-off required at plan time before `soleur:work` begins — covered by
the brainstorm triad assessment (2026-09-26): CPO assessed this batch and
found no disposition crosses the single-user-incident threshold provided the
split provably covers all rows (the tiling guard + DECLARED_TOTAL equality
floors are the proof). `soleur:engineering:review:user-impact-reviewer` runs
at review time per the conditional-agent block.*

## Observability

```yaml
liveness_signal:
  what:            per-leg suite times in suite-timings-scripts-* CI artifacts + committed scripts/suite-shard-legs.tsv
  cadence:         every ci.yml run on PR/main
  alert_target:    CI failure on the PR; scripts-shard-manifest.test.sh RED for drift
  configured_in:   .github/workflows/ci.yml + scripts/regenerate-shard-manifest.py
error_reporting:
  destination:     CI job log (GitHub Actions)
  fail_loud:       suite exits non-zero with FATAL/ERROR lines; tiling guard prints the failing range
failure_modes:
  - mode:          registered --rows ranges stop tiling 1..DECLARED_TOTAL
    detection:     tiling guard in scripts-shard-totality.test.sh (RED on every PR)
    alert_route:   required `test` check failure
  - mode:          a declared row site deleted without DECLARED_TOTAL bump
    detection:     equality floor _site_seq == DECLARED_TOTAL (FATAL)
    alert_route:   suite failure in CI
  - mode:          a leg re-drifts past ~9.5 min after suite growth
    detection:     runbook trigger (ci-test-scripts-sharding.md) + regen dry-run
    alert_route:   scripts-shard-manifest.test.sh RED / next skew event
logs:
  where:           GitHub Actions job logs; per-row $TMP/rows/<id>.log replay inside the suite
  retention:       GH Actions retention (90 days)
discoverability_test:
  command:         bash scripts/lint-orphan-test-suites.test.sh --rows 99-99
  expected_output: "out of bounds"
```

## Guard Contract

### Guard 1 — `--rows` tiling assertion (new, in scripts-shard-totality.test.sh)

**Property.** For every command token carrying `--rows` in a `run_suite`
registration, the contributed ranges are disjoint and contiguous, and their
union tiles `1..<that file's DECLARED_TOTAL>` exactly. (Quantified
per-command-token so a future second `--rows` suite is checked the same day
it registers — not just today's instance.)

**Assembly.** The `run_suite` lines in `scripts/test-all.sh` carrying
`--rows` (extractor joins backslash continuations, anchors on the `--rows`
flag argument — never the label — ignores flag-shaped text in comments, and
does NOT match `skip_suite` lines, which carry a command in decline
position). Each distinct command token is grouped and tiled against the
`DECLARED_TOTAL` read from its own battery file. A `run_suite` line whose
command token's battery file lacks `DECLARED_TOTAL` is itself a finding
(an unsplit job must not ship a `--rows` contract it ignores — precedent
verdict, reused).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Delete the `-b` registration (rows 9-16 execute nowhere) | RED |
| 2 | Bump `DECLARED_TOTAL` to 17 without extending ranges | RED |
| 3 | Widen `-b` to `8-16` (overlap with `-a`) | RED |
| 4 | Quote a `--rows` literal inside a comment (flag text must not count) | GREEN (not a registration) |
| 5 | Add a second suite's `run_suite` carrying `--rows` whose ranges leave a gap against ITS OWN `DECLARED_TOTAL` (an instance the guard has never seen) | RED against that token |
| 6 | A `skip_suite` line carrying `--rows` text (a decline, not a registration) | GREEN (not counted) |

### Guard 2 — DECLARED_TOTAL / EXECUTED equality floors (battery-internal)

**Property.** Every declared row site reaches the range gate exactly once
(`_site_seq == DECLARED_TOTAL`), and the executed count equals the selected
range size — a deleted site or a mis-dispatched worker is FATAL, not a
smaller green.

**Assembly.** The `M1`–`M16` dispatch sites (each calls `in_range()` once,
keyed by id suffix — `C0` shares `ROW_IDS` and bypasses the gate), the
parent-recorded dispatched-id set (`EXEC_IDS`), the per-worker `.rc` files
audited directory-side, and the replay/aggregation loops iterating the
dispatched set.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Remove `M7` from `ROW_IDS` (site count 15 vs DECLARED_TOTAL 16) | FATAL/RED |
| 2 | Dispatch a worker for an undispatched id (rogue `.rc` directory-side audit) | FATAL/RED |
| 3 | `--rows 1-8` but replay loops iterate all `ROW_IDS` | FATAL (missing `.rc` or count mismatch) |
| 4 | Count `C0` in `_site_seq` (gated sites then read 17 vs DECLARED_TOTAL 16) | FATAL/RED |
| 5 | Dispatched worker dies before writing `.rc` | FATAL (`harness_die` preserved) |
| 6 | Delete R1 (`ROWS == EXECUTED + 3` conservation breaks) | FATAL/RED |

### Guard 3 — per-row + unconditional assertion floors

**Property.** Every executed row's `actual >= declared` (no row subsidizes a
hollowed sibling), and the unconditional base (5 parent-side + C0's 3) holds
regardless of range (+ `2*GLOB_MEMBER_N` only when M5 executes) — a deleted
R1/R1b or a hollowed row inside a passing half still FATALs.

**Assembly.** The per-row declared expected count in each worker's 4th
`.rc` field (declared beside the `run_<id>` call), the aggregated worker
counters, and the parent-side unconditional assertions (`:198` enumerate,
`:202` normalise, R1, R1b, positive-control net +1).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Strip assertions from an in-range row (its `actual < declared`) | FATAL |
| 2 | Run `--rows 1-8` where M5 (GLOB_MEMBER_N producer) is out of range — floor must not silently loosen | correct floor (no `2*GLOB_MEMBER_N` term) |
| 3 | A worker omits the 4th `.rc` field (missing expectation, not zero) | FATAL |
| 4 | Delete R1 — its unconditional assertion never lands | FATAL (total under base + Σ declared) |

## Domain Review

**Domains relevant:** Engineering, Legal, Product (carried forward from the
2026-09-26 brainstorm's triad assessment — no fresh spawn per carry-forward
rule)

### Engineering

**Status:** reviewed
**Assessment:** Rows-split is the cleanest of the issue's three options —
extraction is command-token-anchored and union-dedupes; the mandatory
conversions are DECLARED_TOTAL semantics and the tiling guard. Move-to-heavy
relocates the floor without lowering it.

### Legal

**Status:** reviewed
**Assessment:** No regulatory exposure — CI machinery, no PII/payments/
credentials. The duplicate-skip audit posture is affirmative.

### Product/UX Gate

**Tier:** none — no user-facing surface; `## Files to Create`/`Edit` contain
no UI-surface paths.

## Open Code-Review Overlap

- #8659 (EXIT-trap battery replacements, touches test-all.sh) — does not name
  this file. **Acknowledge:** different concern (trap/sandbox hygiene).
- #7942 (two unregistered `*.mutation.sh` batteries) — different files.
  **Acknowledge:** unrelated scope; this suite is registered.

## Acceptance Criteria

- [ ] `scripts/lint-orphan-test-suites.test.sh --rows 1-8` executes exactly
  rows M1–M8 (+ unconditional C0/R1/R1b); `--rows 9-16` executes M9–M16;
  no flag executes all 16.
- [ ] `--rows` bounds enforced: malformed arg, `A>B`, `B>DECLARED_TOTAL`, a
  repeated `--rows`, or unknown arg each exit 2 — before `build_pristine`.
- [ ] Deleting any gated `M*` site fails `_site_seq == DECLARED_TOTAL`;
  deleting R1, R1b, or C0 fails `ROWS == EXECUTED + 3` / the unconditional
  base — the current 19-vs-18 slack is gone.
- [ ] A `.rc` file for an undispatched id, and a dispatched worker dying
  before `.rc`, are both FATAL (directory-side audit + `harness_die`
  preserved).
- [ ] Tiling guard RED on: dropped registration, DECLARED_TOTAL bump without
  range extension, overlapping ranges, unsorted-but-valid input GREEN,
  flag text in comments (not counted), `skip_suite` lines (not counted),
  an unflagged same-token registration, and zero-extraction on a
  DECLARED_TOTAL-declaring battery (non-vacuity arm).
- [ ] The tiling block asserts `-a`/`-b` pinned to distinct legs in the TSV.
- [ ] A committed positive-control row feeds the comparator a gapped
  fixture (`1-8` + `10-16` vs `DECLARED_TOTAL=16`) and must report the gap.
- [ ] `scripts/suite-shard-legs.tsv` updated in the same commit — no phantom
  `lint-orphan-test-suites-mutations` row; `-a`/`-b` tabled on distinct legs;
  `scripts-shard-manifest.test.sh` green.
- [ ] `scripts/lib/test-affected-paths.sh` `ALWAYS_ON_SUITES` carries both
  new labels; affected census + repo-wide-idiom arms green.
- [ ] `scripts/test-all.sh:4592` reads "seven legs"; the "eleven rows"
  comment corrected (names the `-a`/`-b` pairing); noun-sweep clean
  (`legs`, `K=` in edited regions).
- [ ] `lint-orphan-test-suites.sh` still derives the same covered set —
  both halves union-dedupe under one command token, no refusal.
- [ ] Regen dry-run predicts no light leg ≥ ~9.5 min suite time.
- [ ] On this PR's own CI run, both halves report as distinct legs each
  under ~9.5 min (named as evidence in the PR body).

## Test Scenarios

- Given the battery with no flag, when run, then all 16 M-rows + C0 + R1 +
  R1b execute and both floors hold.
- Given `--rows 1-8`, when run, then M1–M8 workers dispatch; M9–M16 produce
  no `.rc` and the replay iterates only the executed set (no `harness_die`).
- Given `--rows 99-99` or `--rows 9-8` or `--rows x`, when run, then exit 2
  before any sandbox work.
- Given a registration deleted from test-all.sh, when the tiling guard runs,
  then RED naming the untiled range.
- Given `DECLARED_TOTAL=17` with ranges still `1-8`/`9-16`, when the guard
  runs, then RED naming row 17 as executing nowhere.
- Given a `run_suite` line whose `--rows` text is quoted in a comment, when
  the guard extracts, then the comment contributes no range.
- Regression: the M5-out-of-range half must compute its assertion floor
  WITHOUT the `2*GLOB_MEMBER_N` term (previously unconditional).

## Success Metrics

- Worst `test-scripts` light leg suite time < ~9.5 min on a green run (was
  588.8 s ≈ 9.8 min on one leg).
- Zero phantom rows / zero unregistered labels at manifest-lint time.
- The silent-shrink class (rows executing nowhere) is RED-driven, not
  theoretical.

## Dependencies & Risks

- **Risk:** per-row assertion-table maintenance burden — a row's count drifts
  and the floor needs a bump. Mitigated by the same-commit rule + the
  equality floor failing loudly on site-count drift.
- **Risk:** `--affected` degrades to the full battery on any `run_suite`
  diff — this PR's CI runs the unsplit battery once. Expected; noted.
- **Dependency:** none blocking. #6480 (infra-validate promotion) may later
  add a leg to the heavy matrix — orthogonal; this change touches only the
  light group.
- **Sequencing:** `registry-gate-mutation-battery` split is NG2 — a separate
  change after this pattern lands.
- **Observation (not scope):** M5 runs `require_single_surface` once per
  glob member (~8 full linter invocations inside one row). The new elapsed
  instrumentation will show whether that dominates — a dump-once dedupe is
  a candidate follow-up, not this PR.
- **ADR:** not required — the original `--rows`/DECLARED_TOTAL contract
  ships with no ADR and is documented in file headers + runbook (the repo's
  convention). If NG2 lands a third `--rows` suite, a short ADR codifying
  the suite-internal split contract is worth filing then.

## Sharp Edges

- A plan whose `## User-Brand Impact` section omits the threshold fails
  deepen-plan Phase 4.6 — filled above (single-user incident).
- `git rev-list main..origin/main --count` before citing `git show main:`
  content — this session's stale-main learning applies to any later reader
  on this box.
- The `-a`/`-b` label rename and the TSV update MUST be the same commit —
  the ⊆ lint reds on the phantom row at rename time.
- `regenerate-shard-manifest.py` requires `--run <id>` — its default
  latest-green lookup 404s.
- Do not add a `*.test.sh` path literal to any `run_suite` line beyond the
  command token — extraction reads command position only.

## References & Research

- Precedent: `plugins/soleur/test/scripts-shard-totality-mutations.sh`
  (`--rows` contract :76-115, per-leg floors :699-712)
- Sibling tiling check: `plugins/soleur/test/scripts-shard-totality.test.sh:695-738`
- Battery: `scripts/lint-orphan-test-suites.test.sh` (dispatch :609-633,
  floors :706-718)
- Extraction: `scripts/lint-orphan-test-suites.sh:193` (command-token
  anchored), ADR-181
- Manifest: `scripts/suite-shard-legs.tsv`, `scripts/regenerate-shard-manifest.py`,
  ADR-240
- Runbook: `knowledge-base/engineering/operations/runbooks/ci-test-scripts-sharding.md`
- Brainstorm: `knowledge-base/project/brainstorms/2026-09-26-ci-orphan-suite-rows-split-brainstorm.md`
- Spec: `knowledge-base/project/specs/feat-ci-orphan-suite-rows-split/spec.md`
- Related: #8864, #8763, #8854, #8927, #6480
