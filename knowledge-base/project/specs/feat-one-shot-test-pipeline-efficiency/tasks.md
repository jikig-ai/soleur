# Tasks — feat-one-shot-test-pipeline-efficiency

Derived from `knowledge-base/project/plans/2026-08-11-perf-test-pipeline-efficiency-plan.md`
(post-review revision). Phase order is load-bearing: no phase introduces a skip path before skip
reporting exists, and no phase makes a decision before its instrument exists.

**Standing constraints**
- Test-first: a failing test lands before each behavioural change (`cq-write-failing-tests-before`).
- **Exactly one full-gate run**, in Phase E, with `SOLEUR_TEST_FORCE_ALL=1` and `TEST_TIMING_LOG` set.
  The "after" figure is arithmetic on that same log. Do not re-run the gate for an environmental
  condition.
- Never put a path literal on a `run_suite` line (see plan §Sharp Edges).

---

## Phase A — Item 6: keep heavy suites out of subagent fan-out

- [ ] **A.1** Write `plugins/soleur/test/fanout-suite-scope.test.sh` (RED). Two arms:
  - [ ] A.1.1 Behavioural: with `SOLEUR_SUBAGENT=1`, a full-gate invocation exits non-zero and names
        the targeted-suite alternative.
  - [ ] A.1.2 Text: both `work/SKILL.md` and `review/SKILL.md` carry the scope clause, asserted on a
        content anchor spanning no punctuation boundary in the source.
- [ ] **A.2** Add the `SOLEUR_SUBAGENT=1` full-gate refusal to `scripts/test-all.sh` (GREEN), printing
      the alternative and the escape hatch.
- [ ] **A.3** Add the fan-out scope clause to `plugins/soleur/skills/work/SKILL.md`.
- [ ] **A.4** Add the same clause to `plugins/soleur/skills/review/SKILL.md`.
- [ ] **A.5** Confirm the new suite is caught by the `plugins/soleur/test/*.test.sh` glob at
      `test-all.sh:764` — which sits inside `want_scripts` (`:744-768`), **not** `want_bun`. Verify the
      match; do not assume it.
- [ ] **A.6** Run the new suite alone. Green.

## Phase B — skip reporting (the enabler, ~15 lines)

- [ ] **B.1** Extend `scripts/test-all-infra-coverage-notice.test.sh` (RED): denominator counts a
      skipped suite; summary distinguishes passed/failed/skipped; the skip line names suite + reason +
      re-run command; `TEST_TIMING_LOG` carries `skip=<reason>` as a **labelled** trailing field that
      keeps field 3 unambiguous against both the `ok` and `FAIL` shapes.
- [ ] **B.2** Add `skipped=0` and the `skip_suite <label> <reason> <rerun-cmd>` helper to
      `scripts/test-all.sh` (GREEN). It increments both `suites` and `skipped` and prints in the shape
      `:806-812` already uses. A **sibling helper**, never an option on `run_suite`.
- [ ] **B.3** Change the summary to `=== P passed, F failed, S skipped, N total ===` with `N = P+F+S`.
- [ ] **B.4** Migrate the existing infra gate's `else` branch (`test-all.sh:806-812`) onto `skip_suite`
      in the same edit, retiring the pre-existing denominator drift.
- [ ] **B.5** Run the coverage-notice suite alone. Green.

## Phase C — Item 1: the relevance gate (~25 lines)

- [ ] **C.1** Extend the coverage-notice suite (RED) with the negative-control pair, the fail-safe arm,
      the force-all arm, and the CI arm.
- [ ] **C.2** Rename `_infra_diff_names` → `_diff_names` throughout `scripts/test-all.sh` (it was never
      infra-specific; leaving the name invites a later reader to re-narrow it).
- [ ] **C.3** Add `_diff_touches <path…>`, reusing the three-source union and fail-SAFE arm at
      `:237-259`, and **widen the untracked arm** from `-- apps/web-platform/infra` to the union of
      declared predicate prefixes.
- [ ] **C.4** Make `_diff_touches` return true unconditionally when `SOLEUR_TEST_FORCE_ALL=1` **or**
      `CI` is set (same `[[ -n "${CI:-}" ]]` predicate as `test-contention.sh:322`). A decline must be
      *unreachable* under CI, not detected — no CI assertion.
- [ ] **C.5** Declare the registry predicate as a named bash array above `test-all.sh:614`, from the
      battery's own declarations (`:58-59`, `:60-61`, `:70-72`, `:73-76`) **plus the battery file
      itself**.
- [ ] **C.6** Declare the cf-tunnel predicate as a named array above `:760`: `SUITE_REL`/`BRIDGE_REL`/
      `APPLY_REL` (`:37-39`), `INVENTORY_REL` (`:64`), `scheduled-terraform-drift.yml` (`:227`/`:260`),
      **all five `W7_EXPECTED` workflows** from `check-cloudflare-token-drift.test.sh:1791` including
      `git-data-cutover.yml` (mutated at `:200-205`), **plus the battery file itself**.
- [ ] **C.7** Guard both `run_suite` lines on `_diff_touches "${ARRAY[@]}"`, calling `skip_suite` on the
      else branch. Array referenced **by name**; no path literal on a `run_suite` line.
- [ ] **C.8** Author `ADR-178` via `/soleur:architecture` — "The local gate may decline to execute a
      suite, and every decline is a counted verdict." Re-derive the ordinal against freshly-fetched
      `origin/*` refs before writing.
- [ ] **C.9** Run the coverage-notice suite alone. Green.

## Phase D — anti-rot (~15 lines in an existing linter)

- [ ] **D.1** Add arms to the `lint-orphan-test-suites` coverage (RED): a declared path renamed out of
      the tree FAILs; an array missing its own battery path FAILs; the shipped tree PASSes.
- [ ] **D.2** Extend `scripts/lint-orphan-test-suites.sh` (GREEN): extract both predicate arrays from
      `test-all.sh`, assert every element resolves in `git ls-files`, and assert each array contains
      its own battery path. Fold into the existing `fails` counter.
- [ ] **D.3** Do **not** build a set-equality check against the batteries' own declarations — they
      declare in four incompatible shapes including a transitive `W7_EXPECTED` in a sibling suite (see
      plan Phase D "Deliberately NOT built").
- [ ] **D.4** Run `bash scripts/lint-orphan-test-suites.sh`. Expect `orphan test suites: none`, exit 0.

## Phase E — the sanctioned full-gate run (ONCE)

- [ ] **E.1** `SOLEUR_TEST_FORCE_ALL=1 TEST_TIMING_LOG=<path> bash scripts/test-all.sh`. Every suite
      executes, so the log is both the green gate and the comparable measurement.
- [ ] **E.2** Record the total wall clock from that log.
- [ ] **E.3** Derive the projected typical-run figure by subtracting the two gated suites' measured
      times from the same log. **No second full-gate run.**
- [ ] **E.4** If any suite is RED, triage inline; do not re-run the whole gate to confirm a flake — use
      the per-suite re-run command the runner now prints.

## Phase F — Item 2: measure the bytes, amend ADR-133 (~4 lines + a doc)

- [ ] **F.1** Add per-directory attribution arms to `scripts/test-contention.test.sh` (RED) via the
      existing `TC_DF_CMD` seam (`:58`): pressure on `/tmp` and none on `$TMPDIR` yields two distinct
      numbers, never their sum.
- [ ] **F.2** Add the per-directory bytes helper to `scripts/lib/test-contention.sh` (GREEN).
- [ ] **F.3** Record `du -sb` for `/tmp` and `$TMPDIR` at the **existing** `TEST_TIMING_LOG`-gated probe
      hook (`test-all.sh:148-152`, `:177-181`), emitting `bytes_tmp=` / `bytes_tmpdir=` as labelled
      trailing fields. **No background sampler.**
- [ ] **F.4** Read the per-directory figures out of the Phase E log.
- [ ] **F.5** Write the dated ADR-133 amendment: state the ADR's original justification from the
      current on-disk file, quote **both** directory figures, record the **keep-the-lock** verdict, and
      record the evidence bar that was not met. ADR-133's `status:` stays unchanged.

## Phase G — Item 3: the rule against session-dependent acceptance criteria

- [ ] **G.1** Re-measure: `python3 scripts/lint-agents-rule-budget.py AGENTS.md AGENTS.rules.md 2>&1`
      (baseline `B_ALWAYS=44478`, cap 46000, per-rule cap 600). If headroom is under ~700 bytes, trim
      sibling prose **in the same commit** — do not defer the trim.
- [ ] **G.2** Write the `cq-ac-must-not-depend-on-concurrent-sessions` body in `AGENTS.rules.md` under
      `## Code Quality`, ≤600 bytes, with a `[skill-enforced: …]` tag naming the plan-review wiring.
- [ ] **G.3** Add the pointer-only entry to `AGENTS.md` under `## Code Quality` (ADR-151 — never merge
      the body into the index).
- [ ] **G.4** Wire the check into `plugins/soleur/skills/plan-review/SKILL.md`'s standing panel
      instructions, classified **Mechanical**.
- [ ] **G.5** Do **not** build `lint-plan-ac-determinism.py` — it necessarily fires on this plan's own
      acceptance criteria (see plan Phase G "Deliberately NOT built").
- [ ] **G.6** Verify: `scripts/lint-rule-ids.py` and `scripts/lint-agents-enforcement-tags.py` both
      exit 0.

## Phase H — deferrals, PR, ship

- [ ] **H.1** File the Item 4 deferral issue (bounded parallelism; blocked on #7376), with
      re-evaluation criteria and a milestone from `knowledge-base/product/roadmap.md`.
- [ ] **H.2** File the Item 5 deferral issue (session memo; the `_site/` defect — cite UC-1 in
      `decision-challenges.md`).
- [ ] **H.3** File the Item 2 deferral issue (multi-run experiment), carrying the evidence bar from the
      plan's §Risks verbatim.
- [ ] **H.4** Comment on **#7376** linking H.1 and the Phase F probe. Do **not** close or re-scope it.
- [ ] **H.5** Verify all 10 acceptance criteria in the plan.
- [ ] **H.6** Confirm the PR body states: the two scope reductions (no new nightly workflow; three
      items deferred) with reasons, the measured `B_ALWAYS`, and the before/after wall clock from the
      Phase E log.
- [ ] **H.7** Confirm `ship` renders `decision-challenges.md` (UC-1, UC-2) into the PR body and files
      the `action-required` issue.
- [ ] **H.8** Re-derive the ADR-178 ordinal against freshly-fetched `origin/main` immediately before
      merge; on renumber sweep the plan body, this file, and plan AC8 in the same edit.
