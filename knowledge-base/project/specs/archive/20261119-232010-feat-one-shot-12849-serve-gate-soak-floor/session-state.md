# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-11-18-fix-serve-gate-soak-floor-and-per-instance-grader-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)
- cto_spawns=0 (pipeline-level; the planning subagent's CTO rulings D1-D5, F1-F11, G1-G13 are recorded in decision-challenges.md)

### Errors
- `gh issue view --comments --json` flag conflict; fixed with `--json comments`.
- Issue-create hook blocks (milestone, Mandated-By, absolute --body-file path); fixed and filed #12936, #12938, #12939.
- Plan named `bash scripts/lint-guard-contract.py`; corrected to `python3`.
- Lead: row G13-scope was classed `operator (scope)`; reclassified technical (CTO ruling: ships with #12869) per hr-technical-fork-is-not-an-operator-question.

### Decisions
- Floor SOAK_FLOOR_DAYS=3 in the gate; 3..999 accepted, 1-2 `*_below_floor`, leading zeros or >3 digits `*_invalid` (closes the overflow bypass G1). No workflow pin.
- Per-instance grader as a serve-only pre-plan step via `scripts/lib/serve-soak-evidence.sh`, under `env -i` with Better Stack read creds only; non-zero rc refuses; non-web-2 hosts refused until #12869.
- Evidence lines from the gate's `fail()` and the helper; mirrored to the step summary; pass lines re-validated before plan.
- Deferred: Better Stack shipping of evidence lines (#12936), long-lived re-serve (#12938), replace-path gap (#12939, ships with #12869).
- Overlap: draft PR #12918 (#12910) edits lb-weight-gate.sh Condition A; this PR edits Condition B. SOLEUR_OVERLAP exit=13, continue; whichever merges second rebases.

### Components Invoked
- soleur:plan, soleur:gdpr-gate, soleur:plan-review, soleur:deepen-plan; CTO, CPO, research, plan-review and infra-review agents.

## Operator Constraints
- Never SSH; never read a live secret value; never dispatch a production workflow (Operator-authorizes hold).
- Technical forks go to soleur:engineering:cto (BINDING); record "Ruled by CTO agent, <date>".
- Ref #12008 / Ref #9421, never Closes. Closes #12849 only.
- Removing the prd override is #12933 (Operator-authorizes), not this PR.
