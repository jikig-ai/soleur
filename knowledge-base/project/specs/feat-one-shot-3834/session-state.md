# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-05-15-chore-agents-core-md-rule-cap-audit-plan.md
- Status: complete

### Errors
None.

### Decisions
- Bundled scope: closes #3834 (per-rule audit — current state has zero violations) AND clears an active B_ALWAYS REJECT regression (22,499 > 22,000; parallel sessions re-grew core after #3837 merged).
- Per-rule cap audit finding: longest core rule is `hr-menu-option-ack-not-prod-write-auth` at 582 B (under 600 B cap). All 5 compliance-tier rules off-limits for Why-trim.
- B_ALWAYS shrink target: 22,499 → 21,966 B (matching #3837's 34 B headroom). Path: 8 Why-tail trims + 1 extra trim summing to ~530 B.
- Loader-class-fit pre-cited inline so any demotion fallback has gate evidence at plan time.
- DEF-1 promoted: structural shrink via brainstorm Approach D (discoverability litmus + retired-rule-ids allowlist) — second tactical Why-trim within 30 days flags the byte-neutral-over-long-run pattern.

### Components Invoked
- soleur:plan, soleur:deepen-plan
- gh CLI (issue/PR/label verification)
- grep/awk/sed/find (codebase verification)
- python3 scripts/lint-agents-rule-budget.py (linter state capture)
