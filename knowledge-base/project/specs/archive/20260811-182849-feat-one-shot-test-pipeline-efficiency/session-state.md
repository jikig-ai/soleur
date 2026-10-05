# Session State

## Plan Phase
- Plan file: `knowledge-base/project/plans/2026-08-11-perf-test-pipeline-efficiency-plan.md`
- Status: complete
- Plan artifact: complete (selector=branch)

### Errors
None blocking. Two recoverable events during planning:
- The plan-file Write was blocked once by the IaC write-guard hook — a Phase 2.8 *skip* note
  contained the literal token `doppler secrets set` while negating it. Rephrased rather than
  using the `iac-routing-ack` opt-out, since there is no real infrastructure step to acknowledge.
- One broken learning citation was caught by the plan's own citation-verification gate and
  corrected to the real filename.

### Decisions
- The briefed "add a nightly workflow" requirement was **already satisfied**:
  `main-health-monitor.yml:309` runs the full un-gated gate every 6h via an Inngest cron. It has
  no `schedule:` block, so a `grep -l 'schedule:'` sweep reported it absent. No workflow added —
  a second one would have forked the toolchain pin-set #7307 built.
- Three of six briefed items ship as **tracked deferrals with evidence**, recorded as
  User-Challenges in `decision-challenges.md` rather than silently dropped:
  - Item 4 (bounded parallelism) — #7376 is the measured result of that exact mechanism on this
    hardware. Deferral was pre-sanctioned by the operator's brief.
  - Item 5 (already-green memo) — `_site/` is untracked and forms a documented producer/consumer
    pair between two suites. A tracked-tree key serves a stale green; an untracked-inclusive key
    never fires. Both horns fatal. Overrule path documented in UC-1.
  - Item 2 (advisory lock) — lands as measurement + ADR-133 amendment rather than a mechanism
    change. This is the operator's own stated fallback ("Data decides").
- Review found three P0s, all the same shape: a guard inheriting the blind spot of the model that
  wrote it (inline predicate paths false-matching the orphan linter's anchor; a CI assertion that
  would have reddened main-health-monitor every 6h; a cf-tunnel predicate omitting four workflows
  the battery actually mutates).
- Deepen found Phase D's anti-rot check would have matched zero lines — both call sites are
  indented inside `if want_scripts`, so a column-0 array anchor extracts nothing and every check
  passes vacuously. Restructured around a declarations-only data file, removing the parser.
- Scope cut ~70% while keeping 100% of the measured win: 9 new files -> 3, 28 ACs -> 10,
  18 scenarios -> 9. The 38.6% comes from path-gating the two batteries alone.

### Components Invoked
`Skill: soleur:plan` -> `Skill: soleur:plan-review` -> `Skill: soleur:deepen-plan`

Agents: `repo-research-analyst`, `learnings-researcher`, `soleur:engineering:cto`,
`dhh-rails-reviewer`, `kieran-rails-reviewer`, `code-simplicity-reviewer`, plus two
`general-purpose` realism passes (verify-the-negative, Phase D implementation-realism).

Gates: premise validation, code-review overlap (0 of 64 issues), User-Brand Impact (4.6),
Observability (4.7), PAT-shaped variable (4.8), UI wireframe (4.9, skipped), encryption posture
(4.10, skipped), precedent-diff (4.4), ADR ordinal re-derived across 62 `origin/*` refs.

No test suite, `test-all.sh`, or heavy battery was executed during planning — cost discipline held.

## Collision Gate (Step 0a.5 + post-plan re-probe)
- `#7376`: OPEN, no closing PRs. Cited as a **blocker for Item 4**, not a work target.
- `#7371` surfaced via `linked:issue` — `closingIssuesReferences: [7307]`, not 7376. Citation.
- `#7423` surfaced via body-probe with a non-empty path intersection
  (`run-registered-suites.sh`, `main-health-monitor.yml`, `suite-runner-flake-7376.sh`).
  Verified NOT a duplicate: #7423 fixed `run_suite` rc capture and the runner's false green; it did
  not path-gate suites, touch a memo, or change lock admission. It is the sibling session that
  *produced* this post-mortem. This branch is cut from its merge commit `532a6b348`.
- Post-plan re-probe: plan frontmatter carries no `issue:`/`closes:` ref. No-op.
