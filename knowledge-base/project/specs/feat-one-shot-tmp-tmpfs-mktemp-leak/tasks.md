---
feature: feat-one-shot-tmp-tmpfs-mktemp-leak
lane: cross-domain
plan: knowledge-base/project/plans/2026-07-27-fix-tmp-tmpfs-mktemp-cleanup-leak-plan.md
status: pending
---

# Tasks — /tmp tmpfs cleanup leak

Derived from the **post-review (v2)** plan. Phase order follows `## Plan Review Revisions` R9,
not the original body: RED → widen linter → derive defective set from tool output → fix → relocate
→ ADR → track. Where the plan body and the Revisions section disagree, **the Revisions section
wins**.

> Two reviews (code-simplicity, spec-flow-analyzer) were still running when the plan was written.
> Read their findings and fold them in before starting Phase 1.

## Phase 0 — Preconditions

- [ ] 0.1 Re-run the falsifying measurements; confirm they still hold:
      `python3 scripts/lint-trap-tempfile-ownership.py scripts/followthroughs/anthropic-admin-key-6297.test.sh` → 0
      `python3 scripts/lint-trap-tempfile-ownership.py --census` → 98 (highwater 100)
- [ ] 0.2 Confirm no bats; suites are plain `*.test.sh`. Do not add a framework.
- [ ] 0.3 Confirm `run_probe` uses `env -i` and determine whether `TMPDIR` reaches the child —
      load-bearing for whether the single-root fix closes the full 1,883/1,883 pairing.
- [ ] 0.4 Census headroom is **2**. Every new `.sh` created in this PR must carry an owning trap or
      `--check-highwater` fails at the end (kieran P1-6).

## Phase 1 — RED (tests first, must fail)

- [ ] 1.1 `scripts/followthroughs/anthropic-admin-key-6297-cleanup.test.sh` — drive the helper via
      command substitution at real nesting depth; assert `[[ ! -e "$path" ]]` **after process exit**.
      Asserting a trap exists is forbidden (it passes today against a leaking script).
- [ ] 1.2 Linter fixture reproducing the **mid-line** append inside a `$()`-invoked helper with a
      named-function trap. Must exit 1. A multi-line fixture is vacuous — it is not the real shape.
- [ ] 1.3 `run_suite` delta test: a synthetic leaking suite must make `test-all.sh` fail.

## Phase 2 — Widen rule (a) (contract change BEFORE consumers)

- [ ] 2.1 Un-anchor `ARRAY_APPEND` using the proven command-position idiom already used by `MKTEMP`;
      switch `.match()` → `.search()` at the append test.
- [ ] 2.2 Resolve named-function traps in `trap_owned_arrays()` via `find_functions()` spans.
- [ ] 2.3 Give rule (a) an accept mechanism — added-line scoping or its own highwater — in this same
      change. It currently has none, unlike rule (c) (architecture P1-4b).
- [ ] 2.4 Do **not** implement transitive `$()` detection (old Phase 5.2 — cut, R5).
- [ ] 2.5 Note in-source that `find_functions()` desyncs on heredoc braces and misses `cleanup` in
      the two largest scripts, so this fails toward silence there.
- [ ] 2.6 Run the full scan; confirm exactly 2 findings, both the real defect, zero false positives.

## Phase 3 — Fix the leak site and sweep the class

- [ ] 3.1 Replace the `TMP_PATHS` accumulator in `anthropic-admin-key-6297.test.sh` with a **single
      scratch root** + `export TMPDIR` + `trap 'rm -rf -- "$TMP_ROOT"' EXIT INT TERM`. No registry
      file (R2).
- [ ] 3.2 Derive the defective set **from Phase 2.6 tool output**, not by hand. Expect **12** files,
      not 10. Record a *defective* / *sound* verdict for each in the PR body; fix only the defective.
- [ ] 3.3 `constraint-scaffold.sh` and `constraint-scaffold/test/boundary.test.sh` — trap signals to
      `EXIT INT TERM`. Confirm no `git worktree prune` is separately owed on the kill path.

## Phase 4 — Outcome-based detection (highest leverage, R7)

- [ ] 4.1 Ungate `tmp_delta` in `scripts/test-all.sh` `run_suite()` from `TEST_TIMING_LOG`.
- [ ] 4.2 Give each suite a private scratch root; export `TMPDIR` for the child; reap unconditionally.
- [ ] 4.3 Fail a suite on non-zero delta. Covers 95 suites and the 65 non-shell temp allocators the
      shell linter structurally cannot see.

## Phase 5 — Relocate bulk temp writes off RAM

- [ ] 5.1 New `scripts/lib/scratch-root.sh` (NOT `test-contention.sh`, which declares itself
      observation-only and whose `TC_TMPDIR` binds at source time — R6).
- [ ] 5.2 Call-time only; never mutate `TC_TMPDIR`; never override an explicit `TMPDIR`.
- [ ] 5.3 Add a test asserting `TC_TMPDIR` still resolves to the tmpfs after the resolver runs, so
      ADR-133's instrumentation cannot be silently repointed.
- [ ] 5.4 Assign an age policy for `$HOME/.cache/soleur/tmp` or drop the claim that it is handled.

## Phase 6 — Observability fix (small, unblocks the probe)

- [ ] 6.1 Route `tmpfs-guard.sh`'s per-reap line through `logger`, not captured stdout. Today the
      journal has 0 `reaping` vs 346 `Reaped`, so every AC and doc claim keyed on it is false.
- [ ] 6.2 Fix `[[ "${reaped:-0}" -eq 0 ]]` doing arithmetic on a multi-line capture.

## Phase 7 — ADR (gate, not record — runs before any deferred reaper work)

- [ ] 7.1 Withdraw amendment 2a (registry file). Decision #2 stands.
- [ ] 7.2 Re-file the named-function/anchor finding under Decision #2 or "Enforcement, stated
      honestly" — not #4, which governs rule (c).
- [ ] 7.3 New ADR: per-run private scratch roots reaped unconditionally, over shared `/tmp` reaping
      gated on conjunctive evidence. Ordinal provisional; `/ship` re-verifies against `origin/main`.

## Phase 8 — Track

- [ ] 8.1 File the tracking issue; `Closes #<N>` in the PR body. Cross-ref #6734, #6789, #6713, #6760.
- [ ] 8.2 File: count-based reaper, redesigned after the source fix soaks (R3).
- [ ] 8.3 File: fstab ceiling raise (R4).
- [ ] 8.4 File: ADR-129 D#4 accept re-evaluation across the bare-`mktemp` population — the upgrade
      trigger has fired (architecture P0-2).
- [ ] 8.5 File: `iac-plan-write-guard.sh` `echo | grep -q` race under `pipefail` (measured 9 deny /
      3 allow on identical 50 KB input). **Sibling pattern checks lose the same race fail-OPEN** —
      higher priority than this plan.
- [ ] 8.6 Withdraw the #6760 harm-reduction comment — `skill-security-scan-` matches nothing; the
      real prefixes are `skill-scan-input-` / `skill-scan-results-`.
- [ ] 8.7 Capture the learning: an outcome detector beats a source-shape detector, and a default
      name template is not a leak signature.

## Acceptance criteria corrections (apply before claiming any AC)

- [ ] AC2/AC17 must anchor on the **resolved scratch root**, not `/tmp` — Phase 5 moves the
      artifacts out of `/tmp` and makes the original counts vacuous.
- [ ] AC12: 12 files, not 10.
- [ ] AC7/T9 are unconstructable (disjoint namespaces) — drop with the reaper.
- [ ] AC1 restate as inspection; AC3 fold into AC4; AC4 wording is inverted; AC13 pin `env -u TMPDIR`;
      AC14 anchor on amendment text, not the word "nesting".
