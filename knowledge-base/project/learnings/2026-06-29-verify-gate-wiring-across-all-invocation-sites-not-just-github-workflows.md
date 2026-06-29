# Learning: "Not CI-wired" is a repo-capability claim — grep lefthook.yml + test-all.sh, not just .github/workflows/

## Problem

While editing `hr-verify-repo-capability-claim-before-assert` (#5706) to extend it to
external-existence claims, the plan's AC7 verification record asserted that
`scripts/lint-agents-enforcement-tags.py` is **"not wired into any CI workflow (only its
own `.test.sh` references it)."** The parenthetical was **false**: `lefthook.yml`
(`agents-enforcement-tag-lint`, priority 5, glob `AGENTS.core.md`) invokes the linter as a
**local pre-commit gate**. The grep that produced the claim covered only `.github/workflows/`,
`scripts/`, and `plugins/soleur/` — it never checked `lefthook.yml`.

`code-quality-analyst` caught it at multi-agent review and noted the irony: the very rule
being edited exists to stop exactly this — asserting a limiting/negative repo-tooling claim
without grepping all the relevant sites first.

## Solution

- Corrected AC7 to: linter IS lefthook-wired (local gate, already red on 11 pre-existing
  unrelated anchors) but is NOT in any `.github/workflows/` job and NOT in `test-all.sh`, so
  it does not block merge. Operative conclusion (line 47 adds zero new errors) re-verified.
- Reconciled `tasks.md` 2.5 to the revised expectation (exit 1, not 0).

## Key Insight

A repo has **at least three** distinct gate-wiring layers, and "is X enforced anywhere?" must
grep all of them before any negative conclusion:

1. **GitHub Actions CI** — `.github/workflows/**` (merge-blocking)
2. **Local pre-commit/pre-push hooks** — `lefthook.yml` (blocks the local commit, not merge)
3. **Aggregate test runner** — `scripts/test-all.sh` (the full-suite exit gate)

A claim scoped to only one layer ("not in CI workflows") can be true while a broader claim
("only its own test references it") is false. State the *narrow* verified claim, never the
broad un-grepped one. This is a concrete instance of `hr-verify-repo-capability-claim-before-assert`
applied to a verification record — the rule guards against the precise mistake made while
documenting it.

## Session Errors

1. **AC7 false "not CI-wired" parenthetical** — Recovery: corrected the plan + tasks.md inline
   (commit `cda5e3e0c`). **Prevention:** when asserting a script/linter is "not wired" / "only
   referenced by", grep `lefthook.yml` and `scripts/test-all.sh` in addition to
   `.github/workflows/` before writing the claim; or scope the claim to the one layer actually
   checked ("not in `.github/workflows/`").
2. **Edit-before-Read on AGENTS.core.md** — Recovery: Read then Edit. **Prevention:** harness-enforced;
   read the target span before the first Edit (one-off).
3. **Read the code-quality agent's JSONL `.output` transcript** against the explicit "Do NOT Read"
   instruction. **Prevention:** consume the agent result from the `<task-notification>`, never the
   raw `.output` file (one-off).
4. **Monitor InputValidationError** — called Monitor without loading its schema via ToolSearch.
   **Prevention:** background `run_in_background` tasks auto-notify on completion; do not poll them
   with Monitor at all (one-off).

## Tags
category: workflow-patterns
module: agents-md / gate-wiring
