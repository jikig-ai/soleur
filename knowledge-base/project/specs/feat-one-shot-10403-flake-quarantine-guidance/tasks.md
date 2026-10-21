# Tasks — feat: flake-quarantine + deterministic-loop guidance for user repos (#10403)

Plan: `knowledge-base/project/plans/2026-10-21-feat-flake-quarantine-deterministic-loop-guidance-plan.md`

## Phase 1 — Author the reference

- [ ] 1.1 Create `plugins/soleur/skills/test-fix-loop/references/determinism-checklist.md` (~150 lines): flake signatures (pass-on-retry, order-dependence, environment-dependence); quarantine protocol (isolate → file → `flaky` label → auto-close on N consecutive greens, adapted from `.github/workflows/scheduled-integration-suites.yml`); determinism axes — seeded RNG, frozen clocks, controlled networking (fail-loud blockade pattern), state isolation, terse failure output/quiet flags, contention/load boundaries (#10649 shape); `Source:` footer naming the Osmani article.
- [ ] 1.2 Verify each of the five AC-named axes (seeds, clocks, network, state isolation, output terseness) has prescriptive content, not just a word mention.

## Phase 2 — Wire the loop

- [ ] 2.1 Edit `plugins/soleur/skills/test-fix-loop/SKILL.md`: add the flake screen as the final sub-step of §1 Parse Failures — one isolated re-run per newly-failed test (keyed file+test-name; runner filter flag or suite-level fallback); pass-on-retry on unchanged code = flake signature; errored/timed-out re-run is NOT a pass; build errors and KILLED/rc-3 suites never enter screening.
- [ ] 2.2 Add the quarantine action: exclusion from fix bookkeeping/delta counts for the run; tracker filing via `gh` (title `flake: <test> — <signature>`, open-issue dedup search first, `flaky` label create-then-add mirroring `Intermittently-failing test`/#FBCA04, never rewriting an existing label); report-only fallback with explicit notice when no `gh`/remote.
- [ ] 2.3 Add `Quarantined flakes:` block to the Diagnostic Report contract (name + issue per flake; `SUCCESS (N quarantined — issues #…)` never bare green); NON_CONVERGENCE/MAX_ITERATIONS Recommendation names remaining failures as load-only flake candidates; possible-diff-interaction flag when the flaked path intersects the loop's own commits.
- [ ] 2.4 Add the Key Principles line ("pass-on-retry is a flake to quarantine, not a fix to report") and the `[determinism-checklist.md](./references/determinism-checklist.md)` markdown link (reachability census).

## Phase 3 — Wire the consumers

- [ ] 3.1 Edit `plugins/soleur/agents/engineering/review/test-design-reviewer.md`: Repeatable-side WARN for determinism-signal tests (unseeded RNG, wall-clock reads, real network, shared mutable state, nondeterministic output, no determinism control) + checklist pointer (~12 lines).
- [ ] 3.2 Edit `plugins/soleur/skills/qa/SKILL.md`: weave the checklist pointer into existing flake-discrimination prose (Step 2.6 #5009 discriminator or the Notes false-fail bullet); net file growth ≤ 60 B vs merge base — trim a redundant clause in the same bullet if needed.

## Phase 4 — Verify

- [ ] 4.1 `wc -c plugins/soleur/skills/qa/SKILL.md` ≤ 37000 and `git diff origin/main -- plugins/soleur/skills/qa/SKILL.md` shows the basename present.
- [ ] 4.2 `bun test plugins/soleur/test/components.test.ts` green (reachability + no-backtick).
- [ ] 4.3 `python3 scripts/lint-skill-body-budget.py --base origin/main` exits 0.
- [ ] 4.4 `bun test plugins/soleur/test/fullsuite-merge-gate.test.ts` green (affected-tests.sh pin intact).
- [ ] 4.5 Read-through: trace both walks (fail-again → cluster/fix; pass-on-retry → quarantine/report) and the §2 ordering (Suite-terminated before screen).
- [ ] 4.6 Confirm no new dirs under `plugins/soleur/skills/` or `plugins/soleur/agents/`; no `description:` edits; README counts unchanged.
