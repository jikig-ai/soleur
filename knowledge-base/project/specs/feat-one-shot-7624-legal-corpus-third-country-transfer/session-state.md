# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-08-20-fix-legal-corpus-third-country-transfer-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)
- Scope verification: PASS — `git diff origin/main...HEAD --name-only` listed only
  `knowledge-base/project/plans/` and `knowledge-base/project/specs/`. No corpus file
  was touched during planning.
- Collision re-probe (post-plan, #7247 rule): plan frontmatter `closes: 7624` matches the
  ref already cleared at Step 0a.5. No newly-discovered target, so no additional probe.

### Errors
- Brief's path `scripts/check-tc-document-sha.sh` is wrong; actual path is
  `apps/web-platform/scripts/check-tc-document-sha.sh`.
- The brief's "flag a missing transfer basis to the CLO" instruction rested on a false
  premise: register §(e) DOES name one (DPF + SCCs + CBPR). Nothing was invented.
- Planning subagent emitted a Session Summary before its last review agent returned; that
  agent then found a P0. The superseding summary is the one of record.
- AC14 as first written was unsatisfiable (`grep -c '^-'` matches the unified-diff header
  `--- a/<path>`). Corrected to `'^-[^-]'`. This mattered: the cheapest field fix for a red
  AC would have been to weaken the very assertion guarding the #7625 boundary.
- Row A10 was orphaned (owned by no phase); reassigned.
- Row count was wrong twice (34, then 50/45) before review caught it. Final: 64 rows /
  55 anchors / 16 files. Row count demoted from closure criterion to work-list.
- Plan file corrupted twice by `str.index` splices matching prose rather than headings
  (Phase 7 lost once). Both repaired; integrity re-verified independently after handoff —
  Phase 7 and `## Acceptance Criteria` both present at 1507 lines.

### Decisions
- **The issue said "roughly ten statements"; enumeration found 64.** Three of four defect
  classes carry no `weur` token, so the sed sweep the brief warned about would have shipped
  a corpus still false in three ways.
- **The existing guard does not cover the failure class that produced this PR.** Both
  divergences came from amending the REGISTER, not from re-typing a forbidden string into
  the corpus. Had every sentinel existed on 2026-08-19, PR #7622 would still have merged
  green, because the guard never reads the register. Recorded as an undetected mode; the
  binding-pin remedy is filed as a follow-up rather than built here.
- CLO ruled the Art. 6(1)(f) balancing test must be RE-DERIVED, not patched: its
  proportionality limb declares longer-than-ten-year retention disproportionate, which is
  exactly what the register now records.
- Guard shrank ~65%; two deviations from CLO wording are recorded rather than applied
  silently.
- Two silent vacuity conditions documented: sentinels depend on `docs/legal/*.md`
  paragraphs staying unwrapped single lines (194 of 638 exceed 200 chars), and the dispatch
  floor is a typed threshold deviating from AP-023, outside the repo's vacuity meta-guard.

### Components Invoked
soleur:plan, soleur:deepen-plan, soleur:legal:clo, Explore, learnings-researcher,
kieran-rails-reviewer, spec-flow-analyzer, code-simplicity-reviewer,
architecture-strategist, scoped advisor consult, mechanical verification pass (18/18),
lint-guard-contract.py, lint-infra-no-human-steps.py,
lint-legal-mirror-drift-baseline.sh, check-tc-document-sha.sh
