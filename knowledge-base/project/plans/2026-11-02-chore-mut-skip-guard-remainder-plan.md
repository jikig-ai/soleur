---
title: "chore: family remainder batch-2 — canonical-equality + seam-check + mutation-battery hardening across 4 MUT_SKIP-idiom alert guards"
date: 2026-11-02
slug: chore-mut-skip-guard-remainder
branch: feat-one-shot-11720-mut-skip-remainder
issue: 11720
lane: cross-domain
type: chore
---

## Overview

Batch-2 of the #11720 family remainder: port the **shipped** guard-hardening convention — canonical-equality heredoc compare, `res_block()`/`param()` exactly-once block-scoped pins, `PRESENCE_ROWS`/`MUT_ROWS` named floors, `_red_verdict`/`mutate_green`/`mutate_floor_red`, decoy/comment-extraction mutation rows, and **workflow seam checks** — to four of the eleven remaining `MUT_SKIP`-idiom alert-guard suites under `apps/web-platform/test/infra/`.

This batch: `registry-store-not-luks-alert.test.sh`, `registry-zot-credential-shape-alert.test.sh`, `workspaces-luks-deadman-fired-alert.test.sh`, `egress-gw-alert.test.sh`. `registry-clientip-not-rfc1918-alert.test.sh` is descoped (already carries a stricter gen-3 harness-marker model — a donor port would be a downgrade). The remaining six files stay open under #11720 for later batches.

## Problem Statement / Motivation

The four suites still carry the pre-#11601 idiom documented in #11720:

- **Presence needles satisfiable by dead text** — a `/* */`- or `#`-wrapped decoy copy of a pinned literal satisfies the needle while the live guard is gutted.
- **First-hit `grep -oE` window extraction** — `workspaces-luks-deadman-fired` extracts `QP`/`CK` by `grep -oE … | grep -oE '[0-9]+$'`, so a decoy match earlier in the file steers the assertion.
- **`MUT_SKIP` / `*_GUARD_*` env axes that can halve or redirect the battery with no red** — and `egress-gw` carries only a weak `pass -lt 30` floor (`:297-301`) plus a `fail -gt 0` verdict tail — no `PRESENCE_ROWS`/`MUT_ROWS` accounting, no mutation-row floor coverage.
- **Stale floors as magic literals** — `registry-store` (`_floor=35/24`), `registry-zot` (`_floor=27/20`), `workspaces-deadman` (`PRESENCE_ROWS=22` + `_floor=37` — already two write sites, the exact trap of the 2026-10-31 floor learning).

## Proposed Solution

Per file, apply the batch-1 convention as it shipped in `inngest-luks-wrong-volume-alert.test.sh` (donor-of-record; `inngest-luks-key-probe-alert.test.sh` is the gen-2 origin), extended by per-suite seam checks the batch-1 file delegates to siblings for — batch-2 makes them first-party per ported suite:

1. **Canonical-equality compare** — `sql_local()`/`sql_local_raw()`-style extraction, whitespace-stripped heredoc compared byte-for-byte against a `*_CANON` constant built from derived literals (never re-pinned literals). Named-property greps retained only for failure-message clarity.
2. **`res_block()`/`param()` exactly-once pins** — block-scoped, anchored both ends, count must equal 1. `param()` ERE must cover the entire value line (the ternary-prefix trap from the batch-1 postmortem).
3. **VAR_BLOCK-style unanchored opener counts** — decoy openers count and go red.
4. **`PRESENCE_ROWS`/`MUT_ROWS` named constants** with a **constructible floor tail** — the donor's shape (`_floor=$((P+M))` then `[ -n "${MUT_SKIP:-}" ] && _floor=$PRESENCE_ROWS` inside the contiguous-assignment window) is itself UNCONSTRUCTIBLE under `build_mutant`'s backward-widening rule (a non-assignment stops the walk → `_floor` unbound → CONSTRUCTION classification). Every ported floor uses the constructible form instead:

```bash
PRESENCE_ROWS=NN
MUT_ROWS=MM
_eff=${MUT_SKIP:+0}
_eff=${_eff:-$MUT_ROWS}
_floor=$((PRESENCE_ROWS + _eff))
_ran=$((pass + fail))
if [ "$_ran" -lt "$_floor" ]; then printf '[FATAL] assertion floor: %s ran, floor %s\n' "$_ran" "$_floor" >&2; exit 1; fi
```

Every line inside the contiguous window is a pure `^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*=[^;]*$` assignment — no `[ -n ]` rebind, no comment — so `build_mutant`'s backward walk carries all six bindings into the mutant → FIRES. Semantics: `MUT_SKIP` set → `_eff=0` → floor drops to `PRESENCE_ROWS` (identical to the donor's intent); `mutate_floor_red`'s `^PRESENCE_ROWS=NN$` sed anchor still lands. The conservation/ledger `if…fi` block sits AFTER the floor `if…fi` (donor order) — any `if…fi` inside the assignment run would also stop the walk.
5. **Mutation battery ported to `_red_verdict`/`mutate_red`/`mutate_green`/`mutate_floor_red`** — scratch-copy mutation into `MUT_DIR`, instrument self-test (`MUT_SKIP=1 bash "$SELF"` rc 0), `edit()` single-occurrence enforcement, per-row expected-FAIL fragments, rc discrimination (only rc=1 is a caught mutation — normalize instrument failures to `exit 2` where the suite currently exits 1).
6. **Decoy/comment-extraction class rows** — decoy heredoc with gutted live body, `/* */`-wrapped decoy blocks, commented pinned lines, inline tautology, `$$` escapes — each row checked for reachability (a row is vacuous until a fixture distinguishes the mutant).
7. **Workflow seam-check rows (the shipped replacement for the issue's "env -u" wording)** — assert `MUT_SKIP` and the suite's own `*_GUARD_*` literals are absent from `infra-validation.yml` executable text (whole-line `#` comments stripped; inline trailing comments handled explicitly). Per-suite prefix set enumerated from the file, never hand-typed. No `env -u` run lines are added — they would self-red `registry-clientip:479`'s `suite-seam-in-workflow` pin and the byte-exact run-line pins in `web-nic`/`ghcr`.
8. **Meta-guard promotion of ALL FOUR ported files (uniform — resolves the singleton asymmetry)** — each ported floor is verified FIRES-classified, and PROMOTED_FILES is the anti-silent-floor-deletion pin (`:1404-1417`); registering only one of four identical cases is arbitrary. Each file gets: (a) a `PROMOTED_FILES` regex entry at the LIVE site (`scripts/guard-vacuity-floor.test.sh:1089` — the last of four assignments; :798/:811/:819 are stale snapshots; dots escaped), (b) the grounds comment paragraph every sibling entry carries, (c) `MIN_FIRING_SUITES` +4 (61→65) per the hand-ratchet convention. egress-gw additionally REPLACES its existing `pass -lt 30` floor (`:298-301`, already FIRES in the deferred ledger) with the derived `_floor` — leaving both would mask the new floor via `classify_suite` best-of-candidates. Promotion is a deliberate registration act: it is not forced by ARM 5c (egress-gw is already floor-bearing; nothing grows).

## Technical Considerations

- **Deviation from issue wording, recorded:** the issue prescribes "`env -u MUT_SKIP -u <axes>` on each file's run line". Batch-1 shipped the strictly-stronger seam check instead (it also covers step `env:`/`shell:`/`working-directory:`/job-env redirects). This plan ports the shipped convention; the issue's words are superseded.
- **`mutate_green` is TF-only in both references** — files whose legit-edit surface spans other axes keep green rows scoped to TF or widen the helper deliberately.
- **Floor constants are two write sites** — `mutate_floor_red`'s sed anchor must track the declaration; grep every occurrence of the constant literal after each bump (2026-10-31 postmortem).
- **Serial CI runtime** — `deploy-script-tests-fixed` runs suites serially under `timeout-minutes: 15` (`infra-validation.yml:851`). Measure the leg on-branch; if it approaches ~12 min, bump the timeout (precedent recorded at `:692`). Added mutation rows are spent only on infra-touching PRs (path-filtered triggers).
- **`assert_fixture_dir` / P1b parity** — the inlined helper blocks must stay byte-identical to the canonical copy or the parity suite reds.
- **No registry changes for suite discovery** — suites are named steps in `infra-validation.yml`; `lint-orphan-test-suites.test.sh` is unaffected (no renames). `test/infra/` is NOT shard-registered (ADR-240 n/a). `apps/web-platform/infra/lib/mutation-scorer.sh` is NOT adopted (would add a `grep-q-pipe-guard` registry obligation; the references inline `_red_verdict` instead).
- **Shared SUT baseline** — all four pin text inside `betterstack-logs-alerts.tf` + `apply-web-platform-infra.yml`; an in-flight `.tf` PR can invalidate canons mid-batch (the #11653 race precedent). Re-probe at Phase-7 sync.

## Research Insights

**Premise Validation (Phase 0.6):** #11528 CLOSED (batch-1 issue), #8841/#9139 CLOSED via PR #11695, #11601 MERGED (donor), #11695 MERGED (batch-1). Fresh `grep -l MUT_SKIP` census = 13 files − 2 ported = the issue's exact 11. All cited file paths exist. `env -u` never landed on `infra-validation.yml` (git `-S` probe: zero hits on main; only unrelated historical commits). Stale premise found and reconciled: the issue's "env -u" wording predates the shipped seam-check convention.

**Property List (Phase 0.6b):** (a) a presence needle cannot be satisfied by dead text; (b) the mutation battery cannot be halved or redirected by an env axis; (c) each guard's own dispatch is proven non-vacuous (floor + instrument control); (d) CI-level muting is barred structurally, not by convention. **Cut List:** shared `test/infra/lib/` helper (cut by the issue and the batch-1 plan — ports re-derive per-file); `mutation-scorer.sh` adoption (registry obligation for zero convention gain); `env -u` run lines (superseded by seam checks, self-reds sibling pins); registry-clientip rewrite (already gen-3 — porting downgrades it).

**Key learnings applied:** canonical-equality subsumes decoy-heredoc/in-heredoc-comment/inline-tautology/`$$`-escape lanes (batch-1 CTO ruling); `_red_verdict` rc=1-only discrimination (2026-09-18 crash-vs-kill learning); floor-constant two-write-sites (2026-10-31); mutation anchors must not match inside the suite's own comments (2026-09-23); derive needles from call form (2026-10-29); `egress-gw` PROMOTED_FILES/constructible-floor obligation (guard-vacuity-floor meta-guard, ARM 5c); scratch-copy mutation removes the in-place stranding flake class (batch-1 header :56-58).

**Relevant files:** donor `apps/web-platform/test/infra/inngest-luks-wrong-volume-alert.test.sh` (864 lines, the port template); `inngest-luks-key-probe-alert.test.sh` (gen-2 origin); meta-guard `scripts/guard-vacuity-floor.test.sh` (:257 DEFERRED_DIRS, :1089/:1404-1417 PROMOTED_FILES, ARM 5c); registration `.github/workflows/infra-validation.yml` (:844-1004 `deploy-script-tests-fixed`); `scripts/lib/inngest-probe-row.sh` (canonical emitter lib — derive emitter needles from it where the suite pins emitters).

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing user-facing — a vacuous alert-guard suite is a false-green CI signal; user impact is indirect (a silently-weakened drift alert on the ops fleet).
- **If this leaks, the user's [data / workflow / money] is exposed via:** no exposure — test files only, synthesized fixtures, no credentials or user data in scope.
- **Brand-survival threshold:** none
- threshold: none, reason: diff is confined to `apps/web-platform/test/infra/` guard suites, one meta-guard ledger entry, and at most a `timeout-minutes` bump in `infra-validation.yml` — no production code, auth, data, payment, or user-owned resource surface.

## Observability

```yaml
liveness_signal:    # the four ported suites run as named serial steps in deploy-script-tests-fixed on every infra-touching PR; cadence per-push; alert_target = the required "test" aggregator leg; configured_in .github/workflows/infra-validation.yml
error_reporting:    # suite [FAIL] lines + non-zero exit → red named step → fail-closed deploy-script-tests-done aggregator (infra-validation.yml:1345-1414); fail_loud = yes
failure_modes:      # [{mode: vacuous port (assertion count below floor), detection: per-suite _floor + ledger conservation + mutate_floor_red, alert_route: red step}, {mode: floor drift across files, detection: scripts/guard-vacuity-floor.test.sh n_deferred/PROMOTED_FILES ledger, alert_route: red meta-guard suite}, {mode: CI-level muting via env axis, detection: per-suite workflow seam-check row, alert_route: red suite step}, {mode: serial-leg timeout, detection: aggregator cancelled-classifier names the timeout shape (infra-validation.yml:1404), alert_route: red leg}]
logs:               # stdout in the infra-validation job log on GitHub Actions; GH retention default
discoverability_test:
  command:          bash -c 'grep -cE "^PRESENCE_ROWS=[0-9]+" apps/web-platform/test/infra/egress-gw-alert.test.sh'
  expected_output:  "1"
```

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Port the canonical-equality SQL compare + `res_block()`/`param()` exactly-once block-scoped pins + `VAR_BLOCK`-style opener counts + `PRESENCE_ROWS`/`MUT_ROWS` constants + `_red_verdict`/`mutate_green`/`mutate_floor_red` (each port needs its own mutation-matrix rebaseline)." [issue #11720] | Phases 1–4 per-file ports; FR-1 | mapped (4 of 11 this batch) |
| 2 | "Add the comment/decoy extraction class rows: decoy heredoc with gutted live body, `/* */`-wrapped decoy blocks, commented pinned lines, inline tautology, `$$` escapes." [issue #11720] | Per-file mutation batteries; FR-2 | mapped |
| 3 | "`env -u MUT_SKIP -u <suite's own *_GUARD_* axes>` on each file's `infra-validation.yml` run line (verify the override names against each suite's header)." [issue #11720] | Workflow seam-check rows inside each ported suite; FR-3 | mapped — mechanism superseded by shipped seam-check convention (deviation recorded) |
| 4 | "The batch-1 PR ports the … convention to `inngest-luks-wrong-volume-alert.test.sh` only … The remaining MUT_SKIP-idiom guard files still carry the pre-#11601 idiom" [issue #11720, remainder list] | 4 of 11 files this batch | descoped — justification: issue's own guidance permits batches ("one file per PR … batching ≥2 per PR is fine"); 11-in-1 ≈ 3–6k dense-bash diff lines over one shared `.tf` baseline — batching by starting-generation keeps each PR reviewable; remainder tracked in #11720 |
| 5 | "`apps/web-platform/test/infra/registry-clientip-not-rfc1918-alert.test.sh`" [issue #11720, remainder list] | — | descoped — justification: file already carries a stricter gen-3 harness-marker seam model (FLOOR_FULL/FLOOR_CHILD, marker-gated MUT_SKIP/NO_MUT/REPIN); a donor-convention rewrite is a downgrade. Verify-only row keeps it green |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| FR-1 per-file convention port | "Port the canonical-equality SQL compare + `res_block()`/`param()` exactly-once block-scoped pins" | asked |
| FR-2 decoy/comment-extraction rows | "Add the comment/decoy extraction class rows" | asked |
| FR-3 workflow seam-check rows | "`env -u MUT_SKIP -u <suite's own *_GUARD_* axes>` on each file's `infra-validation.yml` run line" — property behind the words: CI-level muting barred | asked (mechanism superseded — see Ask 3) |
| egress-gw PROMOTED_FILES entry in `scripts/guard-vacuity-floor.test.sh` | — | inferred — justification: meta-guard ARM 5c reds when a deferred-dir file becomes floor-bearing (n_deferred 47→48); the registration entry is the sanctioned path, `MAX_DEFERRED` bump is forbidden by the arm's own text |
| On-branch runtime measurement + conditional `timeout-minutes` bump | — | inferred — justification: added mutation rows extend a serial leg already under a 15-min ceiling; repo precedent (`infra-validation.yml:692`) records the same measurement-before-ship |
| `## Operator Holds` section | — | inferred — enforcement contract: go.md Step 1.5 requires the epic's standing holds recorded in the branch's plan file |

### Split Assessment

- Subsystems touched: 2 — `apps/web-platform` (test/infra), `scripts`
- Planned files: 5 | Estimated changed lines: ~1,400
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: split — estimated lines exceed 800; the split boundary IS the batch boundary (4 files this PR; #11720 carries the remaining 6+1). Advisory satisfied: this plan already IS the split — a second split inside the batch would produce sub-file PRs with no review benefit (each port is independent; one miscounted floor does not revert siblings). Proceed as single PR for the 4-file batch.

## Guard Contract

### Guard 1 — Per-suite canonical-equality + block-scoped pins (4 ported files)

**Property.** A dead-text copy (comment-, heredoc-, or `/* */`-wrapped) of any pinned literal can never satisfy the guard, and every pinned attribute is bound exactly once inside its resource block — weakening the alert definition in `betterstack-logs-alerts.tf` or `apply-web-platform-infra.yml` always turns the suite red.

**Assembly.** The `logtail_exploration`/`logtail_exploration_alert` resource blocks each suite pins in `apps/web-platform/infra/betterstack-logs-alerts.tf`, its `-target=` legs in `apply-web-platform-infra.yml`, its own `run:` step text in `infra-validation.yml`, and the suite's own mutation battery. Chokepoints: `res_block()`/`param()` (block-scoped, exactly-once), the canon compare (whole extracted heredoc, whitespace-stripped), the per-suite census (file-wide openers count), and the per-suite `*_GUARD_*` env-axis set — every consumer of the guarded text flows through one of these.

**Mutation matrix.**

| # | Edit (design-level) | Expected |
|---|---|---|
| 1 | Gut the live SQL body inside the `name = <<-SQL … SQL` block in the suite's target `.tf` resource, leaving the declaration line | RED — canon compare fails |
| 2 | Add a `/* */`- or `#`-wrapped decoy copy of the pinned heredoc elsewhere in the `.tf` | RED — unanchored opener/param count exceeds 1 |
| 3 | Add a second `logtail_exploration_alert` resource carrying the suite's marker after a compliant first | RED — census/param cardinality |
| 4 | Weaken one `param()`-pinned attribute value inside the block | RED — param count drops to 0 |
| 5 | Delete the suite's mutation-row block from the suite itself (harness edit) | RED — `MUT_ROWS`/`_floor` accounting |
| 6 | Bump the suite's `PRESENCE_ROWS`/`MUT_ROWS` constant by 1 without adding a row (`mutate_floor_red`) | RED — floor fails on the real run |
| 7 | Instrument-failure disguised as caught mutation (suite exits 2 on unbound var) | SURVIVED-not-RED — rc≠1 cannot be credited; row reports wrong/unresolved |
| 8 | `env:` or `shell:` redirect of a `*_GUARD_*` axis inside the suite's workflow step | RED — seam-check row |
| 9 | must-PASS: a legit `.tf` edit that changes the alert body AND the canon constant in the same PR | GREEN — canon moved with the thing it protects |

**Anchor.** The canon constant is derived from the same `.tf` it protects — a weakening that moves both in one diff is caught only by row 9's explicit must-PASS shape plus review; `PRESENCE_ROWS`/`MUT_ROWS` are two-write-site constants (declaration + `mutate_floor_red` sed anchor) — grep every occurrence after each bump.

### Guard 2 — Workflow seam checks (per ported suite)

**Property.** No `MUT_SKIP` or `<PREFIX>_GUARD_*` literal reaches `infra-validation.yml`'s executable text — CI can never mute or redirect a ported suite's battery.

**Assembly.** The `deploy-script-tests-fixed` job's executable surface in `.github/workflows/infra-validation.yml` (run lines, step `env:`/`shell:`/`working-directory:` keys, job env). Chokepoint: each ported suite's own seam-check row reading the workflow's comment-stripped code view.

**Mutation matrix.**

| # | Edit | Expected |
|---|---|---|
| 1 | Add `MUT_SKIP=1` to the suite's step `env:` in the workflow | RED — seam row |
| 2 | Add a `<PREFIX>_GUARD_*` literal to any run line in the job | RED — seam row |
| 3 | Guard's own seam-check row deleted from the suite (dispatch) | RED — `MUT_ROWS`/floor accounting drops |
| 4 | must-PASS: a comment line (`#`-whole-line) mentioning `MUT_SKIP` in the workflow | GREEN — comment-stripped view |

**Anchor.** The seam set is enumerated from each suite's own `*_GUARD_*` declarations — not a hand-typed list (the finite-list staleness learning).

### Guard 3 — four-file meta-guard promotion (uniform registration)

**Property.** Every ported file whose floor scores FIRES is registered in `PROMOTED_FILES` at the live write site — a silent floor deletion in any ported suite reds the membership pin.

**Assembly.** `scripts/guard-vacuity-floor.test.sh`'s LAST `PROMOTED_FILES=` assignment (:1089), its `MIN_FIRING_SUITES` ratchet (:1419), and the zero-slack membership pin (:1404-1417: each entry must be floor-bearing + covered + FIRES).

**Mutation matrix.**

| # | Edit | Expected |
|---|---|---|
| 1 | Add a ported file to a stale `PROMOTED_FILES` site (:798/:811/:819) instead of :1089 | RED — file stays deferred, membership pin never sees it (no-op detection: the entry must land in the live regex) |
| 2 | Register a ported file whose floor is CONSTRUCTION-classified (non-assignment in the window) | RED — membership pin reports `floor-does-not-fire` |
| 3 | Delete or weaken a promoted suite's floor after registration | RED — `no-longer-floor-bearing` / `floor-does-not-fire` |
| 4 | must-PASS: four constructible floors + four live-site entries + `MIN_FIRING_SUITES` 61→65 | GREEN — counters move exactly as AC4 declares |

**Anchor.** The meta-guard ledger is the independently-checked registry — the diff edits both the suites and the ledger; the ledger's own suite certifies consistency.

## Domain Review

**Domains relevant:** Engineering, Operations

### Engineering (soleur:engineering:cto — domain sweep)

**Status:** reviewed
**Assessment:** Convention confirmed in-tree; floors are heterogeneous (four generations present) so the port is a rewrite not a patch; adopt seam-check rows not `env -u` (literal `env -u` self-reds sibling pins); registry-clientip already gen-3 — verify-only or exclude; normalize instrument failures to `exit 2`; re-derive `MUT_ROWS` after `mutate`→`mutate_red` rename; measure serial CI leg.

### Operations (soleur:operations:coo — fail-closed second leader)

**Status:** reviewed
**Assessment:** Zero cost/procurement/vendor surface; suites are named serial steps under `timeout-minutes: 15` on GH-hosted runners, path-filtered to infra PRs; watch item — measure the leg on-branch, bump timeout if it approaches the ceiling (precedent at `:692`); parity-pin sweep obligation on byte-identical helper blocks; census constants deliberately red future additions with instructive messages.

## Product/UX Gate

Not applicable — no user-facing surface; no `components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx` in Files to Create/Edit. Mechanical override did not fire.

## Open Code-Review Overlap

- `#8735` (infra-validation notify-main-failure misses cancelled jobs) — **Acknowledge:** separate concern (notification path), orthogonal to seam-check/floor work. Remains open.
- `#7942` (two `*.mutation.sh` batteries in plugins/soleur/test run in no gate) — **Acknowledge:** different directory and battery shape; not in scope.
- No open code-review issues touch the four suite files or `scripts/guard-vacuity-floor.test.sh`.

## Files to Edit

- `apps/web-platform/test/infra/registry-store-not-luks-alert.test.sh` — full port (canon compare, `res_block`/`param`, `PRESENCE_ROWS`/`MUT_ROWS` replacing `_floor=35/24`, `_red_verdict`/`mutate_green`/`mutate_floor_red`, decoy rows, `REGSTORE_*` seam check, `exit 2` instrument normalization)
- `apps/web-platform/test/infra/registry-zot-credential-shape-alert.test.sh` — full port (`_floor=27/20` → named constants; `REGCREDSHAPE_*` seam check; `exit 2` normalization)
- `apps/web-platform/test/infra/workspaces-luks-deadman-fired-alert.test.sh` — full port (replaces first-hit `grep -oE` window extraction at :178-179; `PRESENCE_ROWS=22`/`_floor=37` → named constants; `DEADMAN_GUARD_*` seam check)
- `apps/web-platform/test/infra/egress-gw-alert.test.sh` — full port + floor replacement (`pass -lt 30` → derived `_ran -lt _floor`; `EGW_GUARD_*` + `IV` seam check; constructible floor shape per meta-guard contract)
- `scripts/guard-vacuity-floor.test.sh` — `PROMOTED_FILES` entries for all four ported files at the live :1089 site + grounds comments + `MIN_FIRING_SUITES` 61→65
- (conditional) `.github/workflows/infra-validation.yml` — `timeout-minutes` bump on `deploy-script-tests-fixed` (:851) ONLY if the measured leg approaches the 15-min ceiling; bump rule: ≥2× the measured leg, same convention as `:692`; decided by the Phase-4 measurement, not pre-authorized

## Files to Create

- (none)

## Implementation Phases

1. **Phase 1 — registry-store-not-luks + registry-zot-credential-shape** (the two smallest; both already whole-compare `FLAT = EXPECTED_FLAT`). Port convention, seam checks, named floors, `exit 2` normalization; run each suite green; run `mutate_floor_red` equivalence.
2. **Phase 2 — workspaces-luks-deadman-fired.** Replace first-hit `grep -oE` extraction with block-scoped pins + canon; named constants; `DEADMAN_GUARD_*` seam check; decoy rows.
3. **Phase 3 — egress-gw.** Full port + floor REPLACEMENT (weak `pass -lt 30` floor exists today — not floorless) + `PROMOTED_FILES` ledger entry; the deepest port in the batch.
4. **Phase 4 — re-baseline + measure.** `bash scripts/guard-vacuity-floor.test.sh` green with ledger flat except the declared egress-gw promotion; affected-suites run green; measure `deploy-script-tests-fixed` leg duration; conditional timeout bump.

## Acceptance Criteria

- [ ] AC1: All four ported suites exit 0 green on the pristine tree and carry `PRESENCE_ROWS`/`MUT_ROWS` named constants whose `_floor=$((PRESENCE_ROWS + MUT_ROWS))` equals the suite's real assertion count (verified by `mutate_floor_red` going red on +1).
- [ ] AC2: Each ported suite's mutation battery contains decoy/comment-extraction rows (decoy heredoc with gutted live body, `/* */`-wrapped decoy block, commented pinned line) each driven RED by `mutate_red`, plus a `mutate_green` must-PASS row.
- [ ] AC3: Each ported suite asserts `MUT_SKIP` and its own `*_GUARD_*` literals absent from `infra-validation.yml` executable text (seam-check row); no `env -u` appears in the workflow.
- [ ] AC4: All four ported floors classify FIRES (not merely pass on real runs) and all four files are registered at the LIVE `PROMOTED_FILES` site (`scripts/guard-vacuity-floor.test.sh:1089`) with grounds comments + `MIN_FIRING_SUITES` 61→65; egress-gw's old `pass -lt 30` floor is removed. `bash scripts/guard-vacuity-floor.test.sh` exits 0 and its printed counters are diffed before/after — measured pre-port baseline (this branch, 2026-11-02): `covered 383`, `deferred 47` (`fires 31`, `construct 16`, `nofire 0`), `fires 366`, `construct 17`. Expected post-port movement: `deferred` 47→43, `deferred fires` 31→30, `deferred construct` 16→13, `covered` 383→387, `fires` 366→370. Any other movement is a finding.
- [ ] AC5: `registry-clientip-not-rfc1918-alert.test.sh` is byte-identical to pre-batch (verify-only) — `git diff` on it is empty.
- [ ] AC6: The four suites' run lines in `infra-validation.yml` remain plain `run: bash …`; the `deploy-script-tests-fixed` leg is measured on-branch and `timeout-minutes` is bumped only if the measurement approaches the ceiling.
- [ ] AC7: `assert_fixture_dir` blocks in ported files remain byte-identical to the canonical copy (P1b parity suite green).

## Test Scenarios

- `bash apps/web-platform/test/infra/registry-store-not-luks-alert.test.sh` → `=== N/N suites passed ===`-shaped tail, rc 0
- Same for the other three suites
- `MUT_SKIP=1 bash <each suite>` → rc 0 (instrument control)
- `bash scripts/guard-vacuity-floor.test.sh` → rc 0, deferred counts flat + egress-gw promoted
- Negative: hand-introduce a `MUT_SKIP` literal into `infra-validation.yml` → each ported suite's seam row reds (verified by the suite's own mutation row, not a manual run)

## Operator Holds

Delegation: https://github.com/jikig-ai/soleur/issues/10390#issuecomment-6361717901
Envelope: knowledge-base/engineering/operations/runbooks/delegated-dispatch-10390-terraform-drift-envelope.md

- Hold: the deferred carrier batch (#8525 + #8013 + the RestartSec=300 half of #8080 + advisory #10290) waits for the next vinngest-v* bake / host-replace window
- Hold: #8839 (stuck-on-Working spawn backstop) waits for the Sentry spawn-agent dead-letter evidence and the 35-day lifecycle check
- Hold: Operator-reserved: #9943 — the owner's decision on a new Better Stack read credential in the cutover dispatch
- Hold: Operator-reserved: op=backup dispatch
- Hold: Operator-reserved: DOPPLER_TOKEN_INFRA_PRIVILEGED seed

The `Envelope:` path names a file that does not exist (read-only CTO run) — deliberate: the evaluator leaves every hold standing when the envelope is missing; no delegated act is armed.

## Non-Goals

- The other 6 files in the #11720 remainder (`bwrap-probe-rollback`, `faithful-canary-sandbox`, `ghcr-blocked`, `inngest-step-524`, `sandbox-alerts`, `web-nic-guard-unpinned-url`) — later batches per the issue's own ordering guidance
- `registry-clientip-not-rfc1918` rewrite — already gen-3 (descoped, AC5 verify-only)
- Shared `test/infra/lib/` helper — cut (see Cut List)
- `mutation-scorer.sh` adoption — registry obligation without convention gain
- Any production code, `.tf` resource change, or workflow behavioral change

## Sharp Edges

- A plan whose `## User-Brand Impact` section omits the threshold fails deepen-plan Phase 4.6 — filled above.
- Floor constants are two write sites: after every `PRESENCE_ROWS`/`MUT_ROWS` bump, grep every occurrence of the literal.
- Mutation anchors must not match inside the suite's own header comments (the `paused = ` decoy class); count occurrences the way the matcher counts them.
- `env -u` must not be written literally anywhere — the issue's wording is stale; sibling seam pins red on it.
- Shared `.tf` baseline race: an in-flight `betterstack-logs-alerts.tf` PR invalidates canons mid-batch — re-probe at Phase-7 sync (#11653 precedent).

## Port Contract — per-file obligations (review-consolidated)

Bindings consolidated from advisor + spec-flow review (2026-11-02); they amend the generic steps above where they are more specific.

**Shared obligations (all four files):**
- Floor tail is the CONSTRUCTIBLE form (rebind `MUT_ROWS=0` above the contiguous window — see Solution item 4). Constants sit ADJACENT to the floor block (deadman's `PRESENCE_ROWS=22` at :204 must move to the tail).
- Floor trip and assertion-ledger trips exit **1** (verdict-class — `mutate_floor_red` grades rc=1 only); instrument failures (`assert_fixture_dir`, mktemp, pristine-control, unbound-var) stay exit **2**. Rewrite each file's "instrument failures exit 2" comment where a floor trip would grade UNRESOLVED.
- Battery carries: pristine-child control (`ctl_rc` + `control.log`, FATAL-2 — registry-store and registry-zot LACK it today), `want=wrong` negative-control row, `_red_verdict` with inner-log capture (`>"$olog"`, not `>/dev/null`), `[note] MUT_SKIP active` loud line, and recomputed `PRESENCE_ROWS`/`MUT_ROWS` from the PORTED counts — never today's literals (slack is one-directional).
- Seam-check scope per file: assert `MUT_SKIP` and the suite's own axis literals absent from `infra-validation.yml` executable text; **the excluded set is each suite's axis NAMES enumerated from the file** — `REGSTORE_*`/`REGCREDSHAPE_*` contain no `_GUARD_` substring, so a `_GUARD_` pattern misses them. Each ported suite also pins its own `run: bash …` registration line. Proving the seam check red needs an `IV` axis (registry-clientip mutates `iv` at :593): add `<PREFIX>_IV` (registry-store/zot currently never read the workflow at all) AND wire BOTH `mutate` case tables to admit it — egress-gw's case arms are `TF|WF|RB|CR|*) FATAL` with no `IV)` arm today (:322-350).
- Canon derivation rule: `*_CANON` is built from literals derived from the file that EMITS them. Where an emitter literal's home is `apps/web-platform/infra/cloud-init-registry.yml` (registry-* suites' `store_luks`, `SOLEUR_ZOT_*`, `REDACTED`/`Authorization` shapes), add that file as a fixture axis (registry-* need a new `CI` axis; deadman `CUT` and egress `CR` already have emitter axes). If a needle's source file is not already a suite axis, add it — never embed a static literal as "derived".
- Unanchored opener counts cover BOTH `name = <<-SQL` openers AND resource-block headers (a `/* */`-wrapped decoy resource at column 0 is also first-match-extracted). Named region anchors per predicate (egress needs `DENY_SQL`/`SILENT_SQL`/`FAIL_SQL`-style regions, not inline `s.index` math).
- Helper-name collisions: reuse/rename existing helpers deliberately — egress has `block_of`/`line_in`/`sql_has`, deadman has `line_in`/`sql_has`, registry-* have `alr_kv` (first-match) → `param()` adds exact-once; `param()` value ERE covers the ENTIRE value line.
- Canon preserves deliberate order-insensitivity: deadman pins a conjunct SET (reorder is `mutate PASS` today) → use a sorted-conjunct compare or per-conjunct canon, NOT a whole-byte canon; egress's fail predicate carries a scoped OR — same question per predicate.
- Canonicalization per file: strip-all (`tr -d`) canon needs the `sql_local_raw` companion rows (intra-literal trailing spaces are load-bearing — registry-store/zot currently use collapsed-space `tr -s` and have explicit trailing-space mutations); keep the collapsed-space piece rows or strip-all+raw pair per file.
- `mutate_floor_red` sed anchor: bare `PRESENCE_ROWS=<n>` line at column 0, adjacent to the floor block; the constant and the anchor bump together (two-write-site trap).
- Registration (uniform — all four ported files): the `PROMOTED_FILES` regex lives at `scripts/guard-vacuity-floor.test.sh:1089` — it is the LAST of four `PROMOTED_FILES=` assignments (:798/:811/:819 are stale snapshots). Each ported file gets an entry there (escaped dots) + grounds comment; `MIN_FIRING_SUITES` 61→65 per the comment convention. Measured baseline → expected post-port: `deferred` 47→43, `deferred fires` 31→30, `deferred construct` 16→13, `covered` 383→387, `fires` 366→370. Anything else is a finding.
- Conditional timeout bump targets `deploy-script-tests-fixed` `timeout-minutes: 15` (`infra-validation.yml:851`), decided by the measured on-branch leg — steps carry no per-step bound.

**Per-file notes:**
- `registry-store-not-luks`: axes `{TF,WF}` + add `CI` (cloud-init-registry.yml emitters) + `IV`; replace `_floor=35/24`; children currently credit any `rc != 0` → `_red_verdict` rc=1-only + pristine control.
- `registry-zot-credential-shape`: same shape as registry-store; replace `_floor=27/20`; add `CI` + `IV`.
- `workspaces-luks-deadman-fired`: replace first-hit `grep -oE` window extraction with exact pins + `param()` uniqueness (QP/CK exact values, not ranges — a duplicated `query_period` line earlier in the block is invisible to first-hit); conjunct-set canon (order-insensitive preserved); floor trip exit 2→1 conversion; add `FIRE_LINE` uncommented-early-copy count row; move constants adjacent to floor; axes `{TF,WF,CUT}` + `IV`.
- `egress-gw`: remove `pass -lt 30` floor, port to derived `_ran -lt _floor`; add `IV)` arms to both `mutate` case tables; `EGW_GUARD_*` + `MUT_SKIP` seam literals; named per-predicate region anchors; `MIN_FIRING_SUITES` + PROMOTED_FILES + grounds comment.

**New ACs (review-consolidated):**
- [ ] AC8: Every ported suite's floor tail is the constructible pure-assignment window (no non-assignment inside it) — verified by `bash scripts/guard-vacuity-floor.test.sh` reporting each file's classification; all four score FIRES and all four are promoted via the live `PROMOTED_FILES` site (the three previously DEF_CONSTRUCT files leave both deferred and construct classification; egress-gw leaves deferred-FIRES for covered-FIRES).
- [ ] AC9: Each ported suite's floor trip exits 1 and each instrument failure exits 2 — `mutate_floor_red` rows grade RED (not UNRESOLVED) on a +1 bump.
- [ ] AC10: Each ported suite carries an `IV` axis and both `mutate` case tables admit it; the seam-check row is proven red by an IV mutation in the battery.
- [ ] AC11: deadman's conjunct reorder remains a `mutate PASS` (green) row after the port — the canon is set-tolerant; QP/CK are pinned exactly with `param()` uniqueness.
- [ ] AC12: `mutate_green` rows are TF-scoped unless the helper is deliberately widened; a `want=wrong` negative-control row exists per battery.

## Port Contract — deepen-plan realism pass refinements (2026-11-02)

Measured per-file facts; amend the per-file notes where more specific.

- **registry-store-not-luks**: existing `EXPECTED_FLAT` whole-predicate byte-compare is KEPT (already canon-strength — augment with derived-literal construction, do not downgrade). `alr_kv` already IS `param()` — extend it to exact-once semantics rather than adding a twin; the `:162-163` awk ranges are `res_block()` — name them. Add `REGSTORE_IV` (+ readability row + own-run-line registration pin) and `REGSTORE_CI` (cloud-init-registry.yml `LINE="SOLEUR_ZOT_DISK …"` emitters); extend `mutate()` copy+dispatch to N axes using ghcr's `env "P_GUARD_${which}=$copy"` indirection (ghcr-blocked:427). Add pristine-child control (absent today). Floor trips → exit 1 (verdict-class; `mutate_floor_red` requires it), instruments → exit 2; the `[ "$rc" -ne 0 ]` grader is replaced by `_red_verdict` so an exit-2 instrument failure can no longer grade RED.
- **registry-zot-credential-shape**: pin target is a `*_sql` LOCAL not a resource block — needs the `sql_local()` extractor (egress :97-103 shape) plus `res_block`/`block_of` for the EXP/ALR resources. Floors are SLACK today (`20` vs actual `24`, `27` vs actual `31`) — recompute from the ported file. The runbook-existence row reads a hardcoded `$REPO/…` path — wire a `REGCREDSHAPE_RB` override for the RB mutation class. Add `REGCREDSHAPE_IV` + `CI` axes; pristine control absent → add.
- **workspaces-luks-deadman-fired**: conjunct-set canon (sorted-conjunct compare) preserves the existing shape check's AND/GROUP-BY cardinality and the reorder-green row. QP/CK pinned exactly via `param()` (a duplicated `query_period` line must red, not silently first-hit). Floor/ledger exit 2→ floor trip becomes exit 1 (`mutate_floor_red` needs rc=1; instruments stay 2 — update the `:322` convention comment). `sql_has` here is 1-arg vs egress's 2-arg — reconcile signatures deliberately, do not copy across files. `mutate()` has TWO case sites (:220-225 and :242-246) — both get `IV)` arms.
- **egress-gw**: `EGW_GUARD_IV` ALREADY exists (:56, readability-checked, drives rows :285/:288) — only the mutate dispatch lacks `IV)` (two case sites :322-328/:345-350 + `egw_replace` hard-anchored; the second table at :345-350 has NO `*)` catch-all — an `IV` row without a dispatch arm falls through silently, so add `*)` → FATAL-2 alongside the `IV)` arm). Existing helpers are the convention under different names: `sql_local()` :97-103, `block_of()` :105-111 ≡ `res_block()`, `line_in` ≡ `param()` — RENAME/extend, never add twins. The floor runs BEFORE the mutation block today and there is no post-mutation floor — the derived `_ran -lt _floor` tail must be `pass+fail` evaluated AFTER mutations (deadman shape) plus the `${#FAILED[@]} == $fail` ledger equality check.
- **Cross-cutting**: all inputs are already CI-trigger-covered; IV-axis rows assert each suite's existing `run:` registration — no new path entries needed.

## Enhancement Summary

deepen-plan run 2026-11-02 (orchestrator-level fan-out, Devin depth-1).

### Gate results
- 4.6 User-Brand Impact: PASS (threshold none + scope-out line)
- 4.7 Observability: PASS (5 fields, allowlisted verb, literal expected_output `1`)
- 4.8 PAT-shaped variable: PASS (no hits)
- 4.9 UI wireframe: skipped (no UI surface)
- 4.10 Encryption Posture: skipped (no new store/connection)
- 4.11 Guard Contract: PASS (lint-guard-contract.py green, 3 entries, structural assemblies)
- 4.12 Scope Check: PASS (1 unfenced section, mapped/descoped-with-justification, Recommendation line)
- 4.13 Task Design: skipped (no new autonomous-task surface)
- 4.4 Precedent-Diff: the donor pair IS the repo precedent (`inngest-luks-wrong-volume-alert.test.sh`, `inngest-luks-key-probe-alert.test.sh`) — the port binds to it; no new scheduled job (ADR-033 check n/a)
- 4.5 Network-Outage / 4.55 Downtime: skipped (no triggers)

### Key Improvements
- **Floor constructibility corrected twice**: the donor shape is CONSTRUCTION-class; the first fix was also non-assignment-contaminated. Final shape is the pure-assignment `_eff=${MUT_SKIP:+0}`/`_eff=${_eff:-$MUT_ROWS}` window (Kieran-verified).
- **Promotion scope reconciled to uniform all-four** (was egress-only in early drafts and self-contradictory after the DHH amendment): each ported floor gets a live-site `PROMOTED_FILES` entry + grounds comment; `MIN_FIRING_SUITES` 61→65; counters measured against a real baseline run (deferred 47→43, fires 366→370).
- **`env -u` superseded by seam checks** (shipped batch-1 convention; `env -u` would self-red `registry-clientip:479`); per-suite seam literal sets use axis NAMES not a `_GUARD_` pattern (`REGSTORE_*`/`REGCREDSHAPE_*` lack the substring).
- **Per-file realism refinements merged**: keep registry-store's whole-predicate FLAT canon; `sql_local()` for zot's local-scoped pin; zot floors were slack (20/27 vs actual 24/31) — recount; deadman `sql_has` signature collision reconciled; egress `EGW_GUARD_IV` exists — only dispatch arms missing; egress floor moves AFTER the mutation block (`pass+fail` form) + ledger equality; second egress `mutate` case gets `*)` → FATAL-2 alongside `IV)`.
- **Exit-code contract fixed**: floor/ledger trips exit 1 (verdict-class — `mutate_floor_red` requires it); instrument failures exit 2; deadman's `:322` convention comment rewritten.
- **AC4 measured**: counters asserted against a real baseline run of `scripts/guard-vacuity-floor.test.sh` on this branch (25/25 green).

### New Considerations Discovered
- `mutate_floor_red` grading requires floor exit 1 — a `mutate`-battery rc-discrimination change in both registry suites (`[ rc -ne 0 ]` → `_red_verdict`) plus pristine-child control.
- registry-store/zot need new `IV` + `CI` axes (workflow seam + cloud-init emitters); ghcr's `env "P_GUARD_${which}=$copy"` indirection is the dispatch pattern for N-axis mutation.
- Shared `.tf` baseline race re-probed at Phase-7 sync — canons are per-file and the risk window is one PR.

### Remaining Holds (unchanged)
Carrier batch / #8839 / #9943 / op=backup / DOPPLER_TOKEN_INFRA_PRIVILEGED seed — see `## Operator Holds`; none touched by this plan.
