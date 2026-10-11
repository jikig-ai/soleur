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
- **`taste` rows** render in the same `## Model Dissents (informational)` block as plain informational lines (the model's choice and its
  recommendation); they file no issue.
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

`bash ${CLAUDE_PLUGIN_ROOT}/skills/ship/scripts/technical-ruling-gate.sh <mode>` (exit 0 pass or `[WARN]`, 1 fail, 2 could not measure):

1. **one-shot, after the plan phase and before `work`:** `--branch`. A `pending - assumed: <default>` row is resolved
   here, in the main context, so a wrong assumption does not ride through `work` and `review`.
2. **ship Phase 5.5:** `--branch` (the artifact check; it also looks under `specs/archive/` for this branch).
3. **ship Phase 6, right after the `gh pr edit` that writes the final body and before `gh pr ready`:**
   `b=$(mktemp -t pr-body.XXXXXXXX); if gh pr view PR_NUMBER --json body --jq .body > "$b"; then bash "${CLAUDE_PLUGIN_ROOT}/skills/ship/scripts/technical-ruling-gate.sh" --pr-body "$b"; rc=$?; else rc=2; fi; rm -f "$b"; echo "gate-rc=$rc"`
   Read the printed `gate-rc=`; no `gate-rc=0` line means do not proceed. Exit 0: go on to `gh pr ready`. Exit 1: remedy item 4 below, then
   `gh pr edit` and re-run. Exit 2 (the fetch failed, the body is empty or whitespace-only, an unclosed fence, or an unreadable file):
   fix the fetch and re-run (at most three tries, then stop with the PR draft); never `gh pr ready` past it.
   Phase 6 full-replaces the body, so the body must be checked after it is written.

The plugin root is `${CLAUDE_PLUGIN_ROOT}` (cloud shells do not export it: resolve it as the Cloud Mode paragraph of ship/SKILL.md does).
An absent artifact is `[PASS] no decision-challenges artifact`. Rulings render into a PUBLIC PR body: leave secrets, credentials and
unfixed-vulnerability detail out of the ruling text and out of the `domain/engineering` issue (carry the question and a pointer, not evidence snippets). An artifact with no `| Item | Class | Ruling |` table is a `[WARN]` and exit 0
(the label and `pending` lints still ran; add the table when the artifact lists decisions). A table with 0 rows, a drifted header, an unclosed code fence, an empty PR body or an unreadable
file is exit 2: fix the file or the invocation, never continue past it. A table row written after a blank line is outside the
table: a later writer adds its own `| Item | Class | Ruling |` header and separator.

## Remedy procedure (a `[FAIL]` is never a bare stop)

1. ONE batched spawn of `soleur:engineering:cto` (`soleur:legal:clo` for legal) carries ALL `unruled-technical` rows (a blank ruling or a
   `pending - assumed` placeholder), per the delegation step; write each `Ruled by` cell, commit, re-run the gate. If a ruling differs
   from what was built on the assumption, re-enter `work` for that item and amend the plan and tasks.
2. **At most two spawns per pipeline run** (a spawn from `one-shot` counts toward `ship`'s). A spawn that fails, times out, or returns without Decision and Rationale counts as
   an attempt. A ruling that says the item is actually operator-class rewrites the row as `operator (<category>)` with the
   CTO's reason, once.
3. After the cap the terminal state is **not** an operator question: the PR stays draft and ship files ONE
   `domain/engineering` issue (never `action-required`) carrying the question and the evidence.
4. `owner-label-unscoped` in the PR body: rewrite the line as a technical ruling (spawn the CTO) or append
   `(operator: <category>)` when it is a genuine operator-class item, then `gh pr edit` and re-run the body check.
5. Emit `SOLEUR_RULE_APPLIED rule=hr-technical-fork-is-not-an-operator-question` when the gate runs (telemetry).
