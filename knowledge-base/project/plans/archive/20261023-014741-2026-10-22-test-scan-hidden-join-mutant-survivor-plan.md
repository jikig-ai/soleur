---
title: "test: ci-pr-affected-replay mutation battery — survivor 'scan-hidden-join-and-find-per-scan' (row_scan_ops)"
type: fix
date: 2026-10-22
slug: test-scan-hidden-join-mutant-survivor
branch: feat-one-shot-10724-mutation-survivor
issue: 10724
closes: 10724
domain: engineering
priority: p3-low
brand_survival_threshold: none
lane: cross-domain
---

# test: ci-pr-affected-replay mutation battery — survivor 'scan-hidden-join-and-find-per-scan' (row_scan_ops)

Spec lacks valid `lane:` — defaulted to cross-domain (TR2 fail-closed).

## Overview

The `scan-hidden-join-and-find-per-scan` mutant in `plugins/soleur/test/ci-pr-affected-replay.test.sh` intermittently survives its `row_scan_ops` row: it prepends a per-scan `"\n".join(index.paths).find("zz")` whose cost is invisible to the row's two deterministic instruments (`PathIndex.ops` is self-reported; the `sys.settrace` line-event counter sees only one extra line) and lands exactly at the margin of the third instrument, a best-of-3 CPU bound that a loaded merge-group runner can flip. Each survivor ejects an unrelated PR from the merge queue at roughly an hour of `merge_group` time per hit. The fix extends the row so this mutant class is killed deterministically, without weakening the bounds that guard every other row.

## Research Insights

### Relevant file paths

- `plugins/soleur/test/ci-pr-affected-replay.test.sh:953` — `row_scan_ops()` (embedded Python fixture; `traced()` at ~971, `cpu()` at ~988, fixture construction at ~958-970, ops/line-event bounds at ~1010-1031, CPU bounds at ~1034-1047, assertion call site at ~1056).
- `plugins/soleur/test/ci-pr-affected-replay.test.sh:947-952` — the three-instrument rationale comment (ops is self-reported; line events see call-less Python work; only CPU sees cost inside ONE C call).
- `plugins/soleur/test/ci-pr-affected-replay.test.sh:2543` — the `mutate scan-hidden-join-and-find-per-scan` row (old text is the 4-space-indented `for m in index.start.finditer(text):` line, landed once inside `walk_text`).
- `plugins/soleur/test/ci-pr-affected-replay.test.sh:2119-2160` — `mutate()`/`mutant_outcome()`: killed iff the row exits non-zero on the mutated SUT copy; controls at ~2700-2740; summary + anti-vacuity floors `FLOOR_ASSERTIONS=712` / `FLOOR_MUTANTS=298` at ~2744-2758 (floors are literals "raised IN THE SAME EDIT" that adds rows/mutants).
- `scripts/ci-pr-affected-replay.py:1085-1120` — `PathIndex`: `self.paths = sorted(self.tracked)` (plain list), `self.tracked` (plain set), `under()` uses `bisect_left(self.paths, …)`.
- `scripts/ci-pr-affected-replay.py:1123-1173` — `walk_text`/`scan_views`/`scan_text`: the scan walks the trie via `index.start`/`index.root`/`index.ops`; it never touches `index.paths` or `index.tracked`. `views(text)` at `:1028` takes no index.
- `.github/workflows/ci.yml` `test-scripts` leg (~:1352) — the shard that runs this file (the failed leg in every reported survivor).

### Empirical verification (run this session, python3)

- `str.join(x)` calls `PySequence_Fast`: for a `list`/`tuple` it takes the element array directly (a `list` subclass `__iter__` override is NOT seen), but for an object exposing `__len__`+`__getitem__`+`__iter__` it dispatches to `__iter__`. A probe class wrapping `index.paths` therefore counts `"\n".join(index.paths)`, `sorted(…)`, `list(…)`, `tuple(…)`, `for … in …` and slicing — while `bisect_left` (used by `PathIndex.under`) and integer indexing stay uncounted.
- A `set` subclass with an `__iter__` override counts `sorted(index.tracked)`/`join`/iteration; `x in index.tracked` uses `set.__contains__` directly and is NOT counted — the correct boundary, since membership is O(1) and materialization is the O(paths) tell.
- Consequence: a test-side instrument can make O(tracked-paths) C work inside `scan_text` visible to a counter, deterministically and without touching the SUT.

### Institutional learnings that apply

- `knowledge-base/project/learnings/2026-08-09-my-tests-pinned-a-constant-by-indexing-it-and-my-mutants-read-as-survivors.md` — the instrument must not take its reading from the thing under test (`PathIndex.ops` is exactly that failure shape here: self-reported, so the mutant simply doesn't call it).
- `knowledge-base/project/learnings/2026-10-13-a-heuristic-scorer-over-attacker-text-needs-a-cost-bound-and-a-bypass-model-before-its-first-green.md` — a battery written against the observed spelling measures the author's imagination; ship a bypass model (the join class has several spellings: `join(index.paths)`, `join(sorted(index.tracked))`, `tuple(index.paths)`, `vars(index)["paths"]`).
- the test file's own floor convention (`ci-pr-affected-replay.test.sh`, the `FLOOR_*` comment: literals raised IN THE SAME EDIT that adds mutants) — the 2026-07-19 two-producer-count learning is the adjacent prior.
- `knowledge-base/project/brainstorms/2026-09-21-ci-runner-concurrency-brainstorm.md` — merge-group runners are shared and queue-loaded (that doc is about the 20-job ceiling, not in-job CPU noise); the load-sensitivity evidence is the issue's own four observed survivals across loaded runs.

### Related issues / PRs

- Issue #10724 (OPEN, `priority/p3-low`, `type/bug`, `domain/engineering`, `meta/machinery`) — this plan's target; survivor observed on merge-group run 39482907164 plus three runs 2026-10-22 (deruelle comment).
- PR #10851 (OPEN/WIP, `feat-one-shot-s4-affected-index-pr3-required-ratchet`) — live sibling editing the SAME test file (inserts a `row_rt_*` ratchet family at old ~2114 and ~2668, edits the mutant summary at ~2740) AND the SUT `scripts/ci-pr-affected-replay.py` (~:47, :129-186, +297-line insert at ~1680, `cmd_audit` ~1692, `main` ~1757-2072). It does NOT touch `row_scan_ops` (953-1056), the scan-region mutants (2368-2543), or `PathIndex`/`walk_text`/`scan_text` (1085-1174). **Collision plan: this change stays inside the row_scan_ops embedded Python (~971-1050), its call site (~1056), optionally new `mutate` lines appended to the scan-mutant block (~2543-2545) and the two floor literals (~2744-2758); no SUT edit at all.**
- ADR-276 (present on `origin/main`; PR #10851 amends it) — merge-group is the full-battery authority; a survivor there ejects the batch, which is the cost this plan removes.

### CLAUDE.md conventions applied

- Minimalism ladder: the smallest change that kills the mutant class (a ~15-line instrument inside the row) beats fixture restructure or a new SUT hook.
- Shell/Python conventions: `set -uo pipefail` file already; embedded Python in the heredoc style of the existing row; floor literals updated in the same edit as added mutants (`FLOOR_MUTANTS`, `FLOOR_ASSERTIONS` re-measured, not guessed).

### Premise Validation

Checked: issue #10724 is OPEN and unclosed-by-PR (`gh issue view`); the mutant (`:2543`), `row_scan_ops` (`:953`) and the best-of-3 CPU bound (`:1034-1047`) all exist verbatim on `origin/main`; the sibling PR #10851 is real and its diff regions are disjoint from this plan's edit regions; no ADR prescribes or rejects the candidate mechanism (ADR corpus grep for mutation/timing/best-of-3 hit only unrelated ADRs; ADR-276 is the sibling's own authority record and is consistent with this fix). Nothing stale.

### Property List (Phase 0.6b)

- P1: `scan-hidden-join-and-find-per-scan` is killed deterministically — the row is RED on that mutated SUT on every run, independent of runner load or clock.
- P2: `row_scan_ops` stays GREEN on the pristine SUT (the `mutant_outcome` harness rejects `row-red-on-pristine` and the row is itself a perf guard on the real SUT).
- P3: the kill must not weaken the battery — the CPU bound remains the only instrument for in-C-call cost that does NOT materialize `index.paths`/`index.tracked` (e.g., a regex over text); relaxing it globally would open a new survivor class.
- P4: zero SUT changes and zero added wall-time — the fix must not collide with PR #10851's in-flight SUT edits and must not lengthen the `test-scripts` leg.

### Cut List (Phase 0.6b)

- "Adjust the row's window" (larger path counts / looser CPU multiplier): CUT as the primary fix — it leaves the kill on the one flaky instrument and merely moves the margin; kept as documented fallback (Alternative Approaches) if the probe proves unworkable in review.
- SUT-side hook (make `PathIndex.paths` a counting structure in `scripts/ci-pr-affected-replay.py`): CUT — buys P1 but violates P4 (collides with PR #10851's live SUT diff and changes production code for testability) when the test-side probe buys the same property for free.

### Functional overlap / community discovery

- Stack check: no uncovered stacks (bash + Python + TS repo; all covered by built-in agents) — Phase 1.5 skipped.
- Functional-overlap agent: not spawned (no agent runtime in this pipeline context); assessed inline — the change is a bespoke instrument inside one repo test row; no community skill/agent covers `row_scan_ops` internals. No overlap.

### Research decision

External research: SKIPPED — strong local context; the SUT, row and harness are fully read in-repo and the fix is a CPython-runtime fact verified empirically above. No best-practices/framework-docs fan-out needed (Phase 1.6).

## Problem Statement / Motivation

`row_scan_ops` guards the property "audit-scan work is bounded by the text, not by the tracked-path count" with three instruments: `PathIndex.ops` (self-reported), a `sys.settrace` line-event count, and best-of-3 CPU time at 3x slack. The `scan-hidden-join-and-find-per-scan` mutant adds `"\n".join(index.paths).find("zz")` once per `walk_text` call — work that lives entirely inside C calls, so the first two instruments are blind by construction and only the CPU bound can see it. Its cost (`join` over ~100k paths ≈ the order of the `3 * max(t2, 300µs)` bound) sits at the measurement's margin, so sustained runner load inflates the baseline `t2` enough to push the ratio under 3 and the mutant survives. Confirmed on one merge-group run (39482907164) and three more 2026-10-22 runs; each survival ejects an unrelated PR at ~1 hour of merge-queue time. The kill must move off the clock onto a deterministic signal.

## Proposed Solution

Add a fourth, deterministic instrument inside `row_scan_ops`'s embedded Python: a **materialization probe** that counts every iteration/slicing of the two O(tracked-paths) collections a scan must never touch — `index.paths` and `index.tracked`.

```python
class _SeqProbe:          # wraps index.paths (a list) — a sequence, never a list, so join()/sorted()/list() must iterate it
    def __init__(self, data):
        self._d, self.hits = data, 0
    def __len__(self):
        return len(self._d)
    def __getitem__(self, i):
        if isinstance(i, slice):
            self.hits += 1
        return self._d[i]
    def __iter__(self):
        self.hits += 1
        return iter(self._d)

class _SetProbe(set):     # wraps index.tracked — iteration counted, O(1) membership left uncounted
    hits = 0
    def __iter__(self):
        self.hits += 1
        return super().__iter__()
```

Install in `traced()` immediately after `idx = m.PathIndex(tracked)` — `idx.paths, idx.tracked = _SeqProbe(idx.paths), _SetProbe(idx.tracked)` — and read `idx.paths.hits + idx.tracked.hits` after each `m.scan_text(idx, text)` call; any nonzero count appends to `bad[]` (with the fixture named). Pristine `walk_text` touches neither attribute (verified by reading `scripts/ci-pr-affected-replay.py:1123-1173`), so the counter holds 0 and the row stays green; the mutant's join materializes `index.paths` on the first fixture and the row goes RED before the CPU phase runs — no clock involved.

Deliberate non-features of the probe: no `__getattr__` delegation (a `.copy()`-style evasion gets a loud `AttributeError`/`crashed` outcome instead of a silent plain-list escape), and integer indexing stays uncounted (O(1) `bisect_left` in `under()` remains legal — and is never called by this row anyway).

Two sibling evasion mutants join the battery so the instrument is tested against the class, not the spelling:

```bash
mutate scan-hidden-sorted-tracked-per-scan '    for m in index.start.finditer(text):' '    "\n".join(sorted(index.tracked))
    for m in index.start.finditer(text):' row_scan_ops
mutate scan-hidden-tuple-paths-per-scan '    for m in index.start.finditer(text):' '    tuple(index.paths)
    for m in index.start.finditer(text):' row_scan_ops
```

In the same edit: re-measure and bump `FLOOR_ASSERTIONS` (712) and `FLOOR_MUTANTS` (298) literals, and update the instrument prose — the header block at ~:27-28, the three-instrument comment at ~:947-952, and the `pass` text at ~:1056 — to name the fourth instrument.

The CPU bound is NOT touched: it remains the only instrument for in-C-call cost that does not materialize the two collections (e.g., per-scan `re.compile` over text). Property P3 requires it stays.

## Technical Considerations

- **Why a non-list `_SeqProbe` and not a `list` subclass:** `str.join`/`PySequence_Fast` takes the element array of a real `list`/`tuple` without calling `__iter__`; only a foreign sequence dispatches to the override. Verified empirically (see Research Insights).
- **Bypass model:** every single-edit spelling that materializes the collections routes through one of the two probe objects — `join(index.paths)`, `join(sorted(index.tracked))`, `tuple`/`list`/`max`/`sum`/`hash`/`for … in`, `vars(index)["paths"]`, `getattr(index, "paths")`, `index.__dict__["paths"]`, `index.paths[:]`. The probe travels with the object. An escape would need a *copying* call (`.copy()` → `AttributeError` → `crashed`, loud) or a re-derived collection (trie walk → line-events visible; `index.tracked` rebuild → probed). Amended on verified seat dissent (CTO ruling 2026-10-22): `_SetProbe` is a plain-object delegating wrapper, NOT a set subclass — a subclass leaks `set()`/`frozenset()`/`.copy()`/`|`/union-family past `__iter__` at C level, a one-edit non-insider escape of this exact class. `_SeqProbe.__getitem__` counts every access (closes `reversed()`/genexpr indexing). Residuals shrink to `._d`/`__dict__` raw access and `copy.copy()` — insider-knowledge or two-edit spellings only; a `rebind` of `index.paths`/`index.tracked` reads as a loud `crashed`, never a kill.
- **`sys.settrace` interaction:** the probe's `__iter__` body is itself Python; on the mutant it adds ≤1 line event per call — far under every `ev` bound, and identical on every run (not a new flake source).
- **OverflowError path:** `traced()` catches the line-cap overflow and returns `got=None`; probe hits are read on the index after the call either way (counters are independent of the trace hook).
- **Row runtime:** the probe adds two attribute swaps and two integer reads per fixture — no measurable wall-time; `test-scripts` leg unchanged (P4).
- **Collision surface vs PR #10851:** all edits land at ~:27-28 (header prose), ~:947-1056 (`row_scan_ops` + call site), ~:2544+ (new `mutate` lines after the existing scan-mutant block), ~:2744-2758 (floor literals). The sibling inserts at old ~2114 and ~2668 and edits ~2740; disjoint hunks, clean merge. If the sibling merges first and shifts line numbers, anchors are content-anchored (`row_scan_ops()`, the `mutate` block tail, the `FLOOR_` literals), not positional.
- **CPU-bound residual (accepted):** a future mutant whose C cost neither materializes the collections nor clears ~2x the bound could still flake the same way; that class is documented, not expanded — this plan does not relax or remove the bound (P3).
- **NFR register:** no production surface; NFR impact is CI determinism (a pipeline property, not a register entry).
- **Precedent-diff (deepen-plan §4.4):** no precedent; pattern is novel — `grep __iter__`/counting-probe across `plugins/soleur/test/` and `scripts/` finds no existing materialization counter; the only `sys.settrace` consumer is this file itself. Reviewers should scrutinize the probe shape directly (it is verified empirically, not inherited).

## Files to Edit

- `plugins/soleur/test/ci-pr-affected-replay.test.sh` — (a) header instrument prose ~:27-28; (b) three-instrument comment ~:947-952; (c) `row_scan_ops` embedded Python ~:955-1050 (probe classes + install in `traced()` + hits assertions); (d) `pass` text ~:1056; (e) two `mutate` lines appended after the `scan-hidden-join-and-find-per-scan` block ~:2544; (f) `FLOOR_ASSERTIONS` / `FLOOR_MUTANTS` literals ~:2744-2758 — one region per bullet, all disjoint from PR #10851's hunks.

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-10724-mutation-survivor/tasks.md` — pipeline task breakdown (generated at Save Tasks).
- `knowledge-base/project/specs/feat-one-shot-10724-mutation-survivor/decision-challenges.md` — pipeline decision log (the technical fork below).

## Alternative Approaches Considered

| Approach | Verdict |
|---|---|
| **A. Test-side materialization probe (chosen)** | Kills the class deterministically; zero SUT diff; ~15 lines inside the row; consistent with the file's "operation count, never a clock" design rule. |
| B. Relax the CPU bound (3x → higher) | Rejected — weakens the bound for every other mutant and stays probabilistic (violates P3). |
| C. Restructure the window (bigger/longer path fixtures so join cost ≫ bound) | Fallback only — still a clock measurement; merely moves the margin; adds PathIndex-construction wall-time. Kept as the documented fallback if review rejects the probe. |
| D. SUT-side hook (counting structure inside `PathIndex`) | Rejected — edits production code for testability and collides with PR #10851's live SUT diff (violates P4). |
| E. Drop the CPU instrument | Rejected — it is the only coverage for in-C-call cost that does not touch the collections; removing it opens a new survivor class (violates P3). |

*Fork disposition:* the issue permits "extend the row OR adjust the window"; A-vs-C-vs-B is a technical ruling (CTO seat per `technical-ruling-delegation.md`). No agent spawn was available in this planning context; A is the assumed default, recorded in `decision-challenges.md` for the review/CTO seat to confirm.

## Open Code-Review Overlap

None — `gh issue list --label code-review --state open` bodies contain neither `plugins/soleur/test/ci-pr-affected-replay.test.sh` nor `scripts/ci-pr-affected-replay.py` (checked 2026-10-22).

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — internal test-instrument change on a CI-only file.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing user-facing — the artifact is a CI leg (`test-scripts`) either going red falsely or silently keeping a coverage gap in the mutation battery; worst case repeats today's failure mode (a ~1-hour merge-queue ejection on an unrelated PR).
- **If this leaks, the user's [data / workflow / money] is exposed via:** no exposure vector — a test fixture and a probe class carry no user data and touch no credential, network or production surface.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** the diff is confined to a plugin test file; there is no user-facing artifact or data path for an incident to reach.

## Guard Contract

### Guard 1 — scan-time materialization probe (`row_scan_ops`)

**Property.** No `scan_text` call in the `row_scan_ops` fixtures may iterate or slice `index.paths` or `index.tracked`; any materialization of a tracked-path collection during a scan fails the row deterministically.

**Assembly.** The chokepoint is the pair of instance attributes `index.paths` / `index.tracked` on the `PathIndex` the row constructs in `traced()`, reached through `scan_text → scan_views → walk_text`. Members are not spellings but object references: `vars()`, `getattr`, and `__dict__` all return the same probe object, so the assembly is closed under attribute-access spelling — the two collections are the only O(paths) state the SUT exposes to the scan loop.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Prepend `"\n".join(index.paths).find("zz")` before the `finditer` loop in `walk_text` (the issue's mutant) | RED |
| 2 | Prepend `"\n".join(sorted(index.tracked))` — a SECOND member of the class via the other collection | RED |
| 3 | Delete the probe installation line (`idx.paths, idx.tracked = _SeqProbe…`) — the guard's own dispatch; the join mutants then survive | RED (battery reports survivors) |
| 4 | SUT-side copying-channel evasion (`"\n".join(index.paths.copy())`) — `_SeqProbe` has no `.copy()` | CRASHED (`AttributeError`, loud — never a silent survive; the probe deliberately carries no `__getattr__` delegation) |
| 5 | *(harness, must-PASS)* Prepend `if "d0/s0/f0.txt" in index.tracked: pass` — O(1) membership, no materialization | GREEN (guard must not over-reject: membership is legal work) |
| 6 | *(harness, must-PASS)* Pristine SUT with probes armed across all fixtures | GREEN |

**Anchor.** `FLOOR_MUTANTS` and `FLOOR_ASSERTIONS` are literals raised in the same commit that adds the two mutants — a diff that weakens the battery (deletes a `mutate` line or leaves floors stale) fails `MUT_RUN >= SITES_MUTATE` or the floor, independently of this guard's code.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---|---|---|
| 1 | "extend row_scan_ops to kill the join-and-find-per-scan mutant or adjust the row's window" [issue #10724] | FR-1 probe instrument, FR-2 evasion mutants, Files-to-Edit (a)-(f) | mapped |
| 2 | "it is timing-sensitive on a loaded runner; the root cause is not measured" [deruelle comment, #10724] | FR-1 deterministic instrument (moves the kill off the clock) | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|---|---|---|
| Materialization probe in `row_scan_ops` | "extend row_scan_ops to kill the join-and-find-per-scan mutant" | asked |
| Three sibling evasion mutants (`sorted(index.tracked)`, `tuple(index.paths)`, `index.tracked.copy()`) | — | inferred — justification: the bypass model from `2026-10-13-…-bypass-model…` — an instrument tested only against the observed spelling re-opens the class; the two additions cover the class's other single-edit spellings and exercise both probes |
| `FLOOR_ASSERTIONS`/`FLOOR_MUTANTS` literal bumps | — | inferred — justification: the file's floor convention requires the literals to move "IN THE SAME EDIT" that adds mutants, or the anti-vacuity gate goes red |
| Instrument-prose updates (header ~:27-28, comment ~:947-952, pass text ~:1056) | — | inferred — justification: the file documents its instruments verbatim ("three instruments"); adding a fourth unnamed instrument leaves the doc self-falsifying |

### Split Assessment

- Subsystems touched: 1 — `plugins/soleur`
- Planned files: 3 | Estimated changed lines: ~60 (incl. KB artifacts)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

- [ ] AC1 — `mutate scan-hidden-join-and-find-per-scan … row_scan_ops` reports `killed` on every run: the row exits non-zero on that mutated SUT deterministically (verified by running the row directly against a locally-built mutant copy 5x AND by the full battery run reporting `mutants killed N of N`).
- [ ] AC2 — `row_scan_ops` is GREEN on the pristine SUT: probe counters hold 0 across every fixture; `PRISTINE_OK[row_scan_ops]` is set, not `row-red-on-pristine`.
- [ ] AC3 — `scan-hidden-sorted-tracked-per-scan` and `scan-hidden-tuple-paths-per-scan` are reported `killed` (each exercises a different probe).
- [ ] AC4 — `FLOOR_MUTANTS` and `FLOOR_ASSERTIONS` literals moved in the same commit; `MUT_RUN >= SITES_MUTATE` and both floors pass (measured values, not guesses).
- [ ] AC5 — `git diff origin/main...HEAD -- scripts/ci-pr-affected-replay.py` is empty (zero SUT diff; no collision with PR #10851's SUT hunks).
- [ ] AC6 — The header instrument prose, the three-instrument comment, and the `pass` text name all four instruments accurately.
- [ ] AC7 — Suite exits 0 end-to-end: `bash plugins/soleur/test/ci-pr-affected-replay.test.sh` prints `0 failed` with all controls green.

## Test Scenarios

- `unit` — Given the pristine SUT, when `row_scan_ops` runs, then `_SeqProbe`/`_SetProbe` hits are 0 for every fixture and the row passes.
- `unit` — Given the `scan-hidden-join-and-find-per-scan` mutant applied to a SUT copy, when `row_scan_ops` runs, then `bad[]` names the materialization and the row exits non-zero on the FIRST fixture (before the CPU phase) — repeat 5x to demonstrate load-independence.
- `unit` — Given the `sorted(index.tracked)` mutant, when the row runs, then `_SetProbe.hits >= 1` and the row exits non-zero.
- `unit` — Given the `tuple(index.paths)` mutant, when the row runs, then `_SeqProbe.hits >= 1` and the row exits non-zero.
- `integration` — Given the full suite, when `bash plugins/soleur/test/ci-pr-affected-replay.test.sh` completes, then `mutants killed M of M` (all killed), floors pass, exit 0.
- `integration` — Given a copy of the row with the probe-install line commented out, when the two join mutants run, then the battery reports survivors (proves the instrument is load-bearing, not decorative).

## Success Metrics

- `scan-hidden-join-and-find-per-scan` kills on 100% of runs (was: ~4 observed survivals across merge-group/PR-head runs in 3 days).
- Zero added wall-time to the `test-scripts` leg (probe = two swaps + two integer reads per fixture).
- `MUT_RUN`/`MUT_KILLED` both 300, `SITES_MUTATE` 300, floors consistent.

## Dependencies & Risks

- **Merge-order risk (PR #10851):** if the sibling merges first, line numbers shift; all edit anchors here are content-anchored (function names, `mutate` rows, `FLOOR_` literals) and the sibling's hunks are disjoint — rebase resolves cleanly. If OUR PR merges first, the sibling's `FLOOR_MUTANTS`/`FLOOR_ASSERTIONS` literals conflict at ~:2744-2758 — expected, resolved by re-measuring on the merged file (flag for the sibling owner in the PR body).
- **Probe-shape risk:** if `scan_text` later legitimately materializes `index.paths`/`index.tracked`, the probe goes red on the pristine SUT — correct behavior (it would BE a regression of the text-bounded-work invariant); the row's own error text names the counter.
- **CPython-version risk:** probe relies on `PySequence_Fast` iteration semantics, stable across CPython 3.x; `sys.settrace` already requires CPython (the row documents this).
- **Residual flake surface:** other CPU-bound mutants near their margin could still flake; the bound is deliberately kept (P3) — a separate concern from this issue.
- **Observability note:** this change IS the instrument; its failure signal is the `test-scripts` leg going red with the mutant name printed — no runtime observability surface is added (files touched: `plugins/soleur/test/`, outside the Phase 2.9 detection set).

## References & Research

- `plugins/soleur/test/ci-pr-affected-replay.test.sh:953,1056,2543,2744` — row, assertion, mutant, floors
- `scripts/ci-pr-affected-replay.py:1085-1173` — `PathIndex`/`walk_text`/`scan_text` (no `index.paths`/`index.tracked` access in the scan path)
- Issue #10724 + deruelle recurrence comment (2026-10-22); runs 39482907164, 39761132470, 39812368174, 39820694149
- PR #10851 (sibling collision map); ADR-276 (merge-group battery authority, sibling's)
- `knowledge-base/project/learnings/2026-08-09-my-tests-pinned-a-constant-by-indexing-it-and-my-mutants-read-as-survivors.md`; `…/2026-10-13-…-bypass-model…`; `…/2026-07-19-…-self-graded-mutation-battery…`
- Learnings consulted via grep: mutation-battery, flake and guard-contract corpus under `knowledge-base/project/learnings/`

## Enhancement Summary (deepen-plan, 2026-10-22)

- **Halt gates §4.6–4.12 verified:** User-Brand Impact present (threshold `none` + decision sentence); Observability/Encryption/PAT/UI-wireframe detection does not fire (test-only diff, no `.tf`/`.sql`/UI paths, no PAT-shaped tokens); Guard Contract lint clean (1 entry, ≥3 matrix rows, own-dispatch + second-member + must-PASS harness rows); exactly one live `## Scope Check` with all asks mapped and every `inferred` item justified.
- **Agent fan-outs (skills/learnings/review seats):** not spawned — this pipeline context has no Task/run_subagent tool. The research the fan-outs would produce was done inline at plan time (SUT walk, mutant mechanics, probe semantics verified by execution, learnings corpus grep). Flagged for the review seat.
- **Precedent-diff result:** pattern is novel — recorded in Technical Considerations.
- **Round-1 realism passes (inline):** the plan's negative claims verified — `walk_text` touches neither `index.paths` nor `index.tracked` (read `scripts/ci-pr-affected-replay.py:1123-1173`); zero-SUT-diff is asserted by AC5 against the merge-base (`origin/main...HEAD`, not the moving tip).
- **Suite baseline measured:** `bash plugins/soleur/test/ci-pr-affected-replay.test.sh` → 712 passed / 0 failed / 298 mutants on this runner (the flake is load-dependent, as diagnosed).
