# Decision-challenges render and the Technical-Ruling Gate remedy

Moved out of `ship/SKILL.md` Phase 6 step 2.5 (the SKILL body has no byte headroom) and extended for the class split.
Rule: `hr-technical-fork-is-not-an-operator-question`. Schema, closed category list and recording format:
[technical-ruling-delegation.md](../../brainstorm-techniques/references/technical-ruling-delegation.md).

## Render (Phase 6 step 2.5, ADR-084)

If `knowledge-base/project/specs/<branch>/decision-challenges.md` exists and is non-empty, an earlier headless phase
(`plan`/`work`) recorded auto-decided dissents against the operator's stated direction, which the operator has not seen.
Phase 6 **full-replaces** the body, so fold the artifact into the generated body under the
`## Model Dissents (informational)` heading (deliberately outside the `ship-operator-step-gate` deny set
`Operator`/`Post-merge`/`Follow-up`; informational statements, never operator-action bullets). Render **by `Class`**:

- **`technical` rows** go in a `### Ruled by CTO agent` sub-block of that same heading, each with its `Ruled by` line
  (and `Dissent:`). They file **no issue**: a technical ruling never reaches the operator.
- **`operator (<category>)` rows** render in the existing form, and ONLY these open one idempotent issue. Check
  `gh issue list --search "decision-challenge <branch>" --state open -L 200` first, then
  `gh issue create --label action-required --label decision-challenge --milestone "Post-MVP / Later"` with a plain-language
  title linking the PR, because `operator-digest` Section 4 harvests `action-required` issues, not PR bodies. A split
  item yields both a technical row and an operator row.
- No new top-level PR-body heading: that keeps the diff and the `ship-operator-step-gate` deny-token surface unchanged.
- `guardrails.sh`'s filing gate refuses the `gh issue create` unless the body names a user-visible consequence; when the
  dissent is about a hook/gate/guard the honest exit is `--label meta/machinery` (measured on PR #8354), which the digest
  excludes, so the PR-body section is then the operator-visible surface. See
  [decision-principles.md](../../brainstorm-techniques/references/decision-principles.md).

## The gate: three call sites, one parser

`bash plugins/soleur/skills/ship/scripts/technical-ruling-gate.sh <mode>` (exit 0 pass, 1 fail, 2 could not measure):

1. **one-shot, after the plan phase and before `work`:** `--branch`. A `pending - assumed: <default>` row is resolved
   here, in the main context, so a wrong assumption does not ride through `work` and `review`.
2. **ship Phase 5.5:** `--branch` (the artifact check; it also looks under `specs/archive/` for this branch).
3. **ship Phase 6, right after the `gh pr edit` that writes the final body and before `gh pr ready`:**
   `b=$(mktemp -t pr-body.XXXXXXXX); gh pr view PR_NUMBER --json body --jq .body > "$b"; bash <gate> --pr-body "$b"; rc=$?`
   (read `rc` on its own line). Phase 6 full-replaces the body, so the body must be checked after it is written.

An absent artifact is `[PASS] no decision-challenges artifact`. An artifact with no table, or a table with 0 rows, is exit 2:
add the `## Decision Classes` table (a few rows; an in-flight branch that rebases onto this gate adds it at ship time).

## Remedy procedure (a `[FAIL]` is never a bare stop)

1. For each `unruled-technical` or `ruling-contradicts-assumed` row: spawn `soleur:engineering:cto` (`soleur:legal:clo` for
   legal) per the delegation step, write the `Ruled by` cell, commit, re-run the gate.
2. **At most two spawns per artifact.** A spawn that fails, times out, or returns without Decision and Rationale counts as
   an attempt. A ruling that says the item is actually operator-class rewrites the row as `operator (<category>)` with the
   CTO's reason, once.
3. After the cap the terminal state is **not** an operator question: the PR stays draft and ship files ONE
   `domain/engineering` issue (never `action-required`) carrying the question and the evidence.
4. `owner-label-unscoped` in the PR body: rewrite the line as a technical ruling (spawn the CTO) or append
   `(operator: <category>)` when it is a genuine operator-class item, then `gh pr edit` and re-run the body check.
5. Emit `SOLEUR_RULE_APPLIED rule=hr-technical-fork-is-not-an-operator-question` when the gate runs (telemetry).
