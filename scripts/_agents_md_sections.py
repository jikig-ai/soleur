"""Single source of truth for AGENTS.{md,core.md,docs.md,rest.md} section names.

Used by `lint-rule-ids.py` (rule-id coverage, residency invariants) and
`lint-agents-rule-budget.py` (per-rule body cap). A rule body line is any
`^- ` line whose nearest preceding `## <heading>` lives in this set. Lines
under any other heading (sub-bullets in Note blocks, prose lists in
introductory sections, etc.) are exempt from rule-id and per-rule checks.

Adding a new section heading to AGENTS.md requires updating this constant
in the same PR, otherwise new rules under that heading will be silently
exempt from both linters.
"""

SECTIONS = frozenset({
    "Hard Rules",
    "Workflow Gates",
    "Code Quality",
    "Review & Feedback",
    "Passive Domain Routing",
    "Communication",
    "Compliance Tier",
})
