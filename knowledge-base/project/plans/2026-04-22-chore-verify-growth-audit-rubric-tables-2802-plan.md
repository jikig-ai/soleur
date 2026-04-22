# Verify Scheduled Growth Audit Pinned Prompt Produces Both Rubric Tables (#2802)

**Type:** chore / follow-through verification
**Issue:** #2802
**Source PR:** #2795 (merged c597cc6b at 2026-04-22T18:16:57Z)
**Workflow run:** <https://github.com/jikig-ai/soleur/actions/runs/24795319398>
**Branch:** feat-one-shot-2802-verify-growth-audit-rubric-tables
**Detail level:** MINIMAL (verification task, no code changes expected)

## Overview

PR #2795 pinned a dual-rubric AEO audit template (SAP Scorecard + 8-component AEO diagnostic) in two surfaces:

1. `.github/workflows/scheduled-growth-audit.yml` Step 2 prompt (cron runs)
2. `plugins/soleur/agents/marketing/growth-strategist.md` GEO/AEO Content Audit section (ad-hoc `/soleur:growth aeo` runs)

The concern tracked by #2802 is that an LLM-mediated agent can silently drop parts of a pinned prompt. To verify the pin held, the growth-audit workflow was triggered post-merge (run 24795319398), and the produced audit must be checked against a deterministic grep-based validator.

**Status at planning time:** Workflow run 24795319398 completed `success` at 2026-04-22T18:35:44Z. The audit file `knowledge-base/marketing/audits/soleur-ai/2026-04-22-aeo-audit.md` exists (15,018 bytes) and has already been merged to main via PR #2810 (commit 8428f358 `docs: weekly growth audit 2026-04-22`). Pre-planning validator run shows all four assertions PASS.

This plan formalizes the verification, records evidence, and closes #2802.

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Reality | Plan response |
|---|---|---|
| "Workflow run (already triggered)" (issue body) | Run 24795319398 completed success at 18:35:44Z | Proceed to validator step; skip re-trigger |
| "Awaiting completion and validator pass" (issue body) | Completion confirmed; pre-planning validator already PASS | Plan execution is a re-run + close, not a wait-loop |
| "If either table is missing, file a P1 follow-up" (issue body) | Both tables present; pre-planning validator 8/8 on AEO diagnostic | P1 follow-up branch is unreachable; document as non-triggered |

## Pre-Planning Verification Snapshot

Validator run against `knowledge-base/marketing/audits/soleur-ai/2026-04-22-aeo-audit.md` (the audit produced by run 24795319398):

```text
PASS: Structure row (weight 40, score 34/40)
PASS: Authority row (weight 35, score 26/35)
PASS: Presence row (weight 25, score 20/25)
PASS: 8-component count 8/8 (FAQ structure, Answer density, Statistics, Source citations,
      Conversational readiness, Entity clarity, Authority / E-E-A-T, Citation-friendly)
```

Weight totals:

- SAP Scorecard: 40 + 35 + 25 = 100 ✓
- 8-component AEO diagnostic: 20 + 15 + 15 + 15 + 10 + 10 + 10 + 5 = 100 ✓

The pinned template held on both dimensions.

## Acceptance Criteria

### Pre-merge (PR) — N/A

This is a verification follow-through. No PR. No code changes. No branch will be merged beyond the initialization commit; the worktree exists purely to host the verification evidence if the /ship flow insists on a PR, otherwise `gh issue close` is the terminal action.

### Post-merge (operator) — required for issue closure

- [ ] Validator executes against `knowledge-base/marketing/audits/soleur-ai/2026-04-22-aeo-audit.md` and all four assertions PASS (Structure/40, Authority/35, Presence/25, 8-component count 8/8)
- [ ] Validator output captured verbatim in the #2802 closing comment
- [ ] `gh issue close 2802` with evidence comment citing the audit path, workflow run URL (24795319398), and merged PR #2810
- [ ] Verify #2802 state transitions to CLOSED (`gh issue view 2802 --json state`)

## Hypotheses

No network-outage triggers in scope (issue description does not match SSH/firewall/timeout patterns). Skipped.

## Files to Edit

None. Plan execution is read-only against the repo.

## Files to Create

None. Evidence lives in:

- Existing audit file (already on main via PR #2810): `knowledge-base/marketing/audits/soleur-ai/2026-04-22-aeo-audit.md`
- Closing comment on #2802

If a learning is captured during `/ship compound`, it would be written to `knowledge-base/project/learnings/best-practices/<topic>.md` — but this verification has no surprising finding (happy path), so a learning is not expected.

## Open Code-Review Overlap

None. Query against 30 open `code-review`-labeled issues for "scheduled-growth-audit", "growth-strategist", and "aeo-audit" returned zero matches. No fold-in, acknowledge, or defer needed.

## Implementation Phases

### Phase 1 — Re-run the validator (evidence capture)

Run the exact validator from #2802's issue body in a fresh shell, inside the worktree. Capture stdout to a temporary file for the closing comment.

```bash
AUDIT=$(ls -1 knowledge-base/marketing/audits/soleur-ai/*-aeo-audit.md | sort | tail -n 1)
echo "Audit file: $AUDIT"
echo "Audit size: $(wc -c < "$AUDIT") bytes"
echo
echo "=== SAP Scorecard rows ==="
grep -qE "^\| \*\*Structure\*\* +\| 40 +\|" "$AUDIT" || { echo "FAIL: Structure row missing"; exit 1; }
grep -qE "^\| \*\*Authority\*\* +\| 35 +\|" "$AUDIT" || { echo "FAIL: Authority row missing"; exit 1; }
grep -qE "^\| \*\*Presence\*\*  +\| 25 +\|" "$AUDIT" || { echo "FAIL: Presence row missing"; exit 1; }
echo "PASS: Structure/40, Authority/35, Presence/25"
echo
echo "=== 8-component AEO diagnostic ==="
n=$(grep -cE "^\| (FAQ structure|Answer density|Statistics|Source citations|Conversational|Entity clarity|Authority / E-E-A-T|Citation-friendly)" "$AUDIT")
[[ "$n" == "8" ]] || { echo "FAIL: 8-component diagnostic has $n/8 rows"; exit 1; }
echo "PASS: 8/8 diagnostic rows"
echo
echo "OK: pinned template held"
```

**Exit criteria:** All four grep assertions print PASS and final line is `OK: pinned template held`. If any assertion fails, branch to Phase 1b.

### Phase 1b — P1 follow-up branch (unreachable given pre-planning snapshot, but specified for completeness)

If any validator assertion FAILS:

1. Capture failing grep output and audit file delta against the previous passing audit (`2026-04-21-aeo-audit.md`) via `diff -u`.
2. File a P1 GitHub issue titled `P1: scheduled-growth-audit.yml dropped <rubric> table in run 24795319398` with labels `priority/p1-high`, `domain/marketing`, `type/bug`. Body includes: validator failure, diff against prior audit, suspected cause (LLM rewrite of the pinned prompt), link to PR #2795 where the pin was introduced.
3. Close #2802 with a comment stating "Pin dropped — see #<new-P1>" and link the new issue.

Per the pre-planning snapshot, this branch is unreachable this session. It is documented so a future re-run of the same plan (next week's cron) has the procedure.

### Phase 2 — Close #2802 with evidence

Construct the closing comment from Phase 1 output. Use a heredoc (not multi-line `--body` flags — AGENTS.md `hr-in-github-actions-run-blocks-never-use`).

```bash
gh issue comment 2802 --body-file - <<'EOF'
## Verification — pinned template held

**Audit file:** `knowledge-base/marketing/audits/soleur-ai/2026-04-22-aeo-audit.md`
**Workflow run:** https://github.com/jikig-ai/soleur/actions/runs/24795319398 (success, 2026-04-22 18:35:44Z)
**Merged via:** PR #2810 (commit 8428f358 `docs: weekly growth audit 2026-04-22`)

### Validator output

```text
<paste Phase 1 stdout verbatim>
```

### Weight totals

- SAP Scorecard: 40 + 35 + 25 = 100
- 8-component AEO diagnostic: 20 + 15 + 15 + 15 + 10 + 10 + 10 + 5 = 100

Both pinned tables present. No P1 follow-up required. Closing per the issue's Acceptance Criteria.
EOF

gh issue close 2802
gh issue view 2802 --json state --jq .state  # expect: CLOSED

```

**Exit criteria:** `gh issue view 2802 --json state --jq .state` prints `CLOSED`.

### Phase 3 — Worktree cleanup

The worktree is initialization-only; no commits beyond `e172abf0 chore: initialize feat-one-shot-2802-verify-growth-audit-rubric-tables` are required.

Options:

1. **Preferred:** Leave the branch to be cleaned up by the next session-start `worktree-manager.sh cleanup-merged` sweep once the follow-through-branch retention policy picks it up.
2. **If `/ship` insists on a PR:** Commit the plan + spec/tasks artifacts and open a no-op PR titled `chore: verify #2802 pinned-template follow-through (docs only)` with body linking the validator output and `Closes #2802`. Merge via `gh pr merge --squash --auto`.

**Default path:** option 1. The issue is closable without a PR because no code changed.

### Test Scenarios

None. No code changes, no tests to write. The validator itself is the test.

## Domain Review

**Domains relevant:** Marketing (CMO)

This touches a marketing-ops deliverable (weekly AEO audit). Spawning the CMO would be appropriate if the plan proposed any change to the audit template or workflow. Since the plan is pure verification and the pre-planning snapshot already confirms the pin held, the CMO review is a no-op — the audit content itself was already reviewed as part of PR #2810 (`docs: weekly growth audit 2026-04-22`).

**Decision:** Domain review waived for this plan. Rationale: zero code/content changes, zero new deliverables, zero new decisions. The verification is mechanical.

If Phase 1b is triggered (validator FAIL), re-invoke this plan and spawn the CMO for the P1 follow-up issue before filing.

### Product/UX Gate

**Tier:** NONE. No user-facing surface. No pages, components, flows.

## Risks

- **Audit file already merged via PR #2810.** The audit was generated, reviewed, and merged to main before #2802 verification ran. This is fine — the verification is deterministic grep against a committed file, not a build-time check. Noted to pre-empt reviewer confusion about "why is the audit already on main before verification closed?"
- **Pre-planning validator was run inside a worktree, not main.** The worktree branch has no changes to `knowledge-base/marketing/audits/soleur-ai/` relative to main — the audit file is identical. Phase 1 re-runs the validator inside the worktree against the merged-to-main file; no divergence risk.
- **Bash pattern brittleness.** The grep patterns in the validator are position-sensitive (`^\| \*\*Structure\*\* +\| 40 +\|`). A future audit that uses different column padding (e.g., `| **Structure** | 40 |`) would FAIL the validator despite a correct rubric. This is a known trade-off — deterministic gating preferred over fuzzy match. A future concern if multiple audit authors produce different whitespace, tracked separately if it occurs.

## CLI-Verification Gate

All CLI invocations in this plan are standard `gh`, `grep`, `ls`, `wc`, and `diff`. Verified: `gh issue comment --body-file -` is documented in `gh issue comment --help`; `gh issue close <N>` is documented in `gh issue close --help`. No fabricated tokens.

## Non-Goals

- Not re-running `scheduled-growth-audit.yml`. The triggered run (24795319398) already succeeded and its output is the verification target.
- Not modifying the pinned prompt in the workflow or agent doc. If the validator fails, that branch files a P1 follow-up; it does not fix the prompt inline.
- Not validating the content of the audit (scoring accuracy, recommendations quality). Only validating the *structural presence* of the two rubric tables as pinned.
- Not verifying the weekly cron actually fires on its schedule. Out of scope for this follow-through; tracked by the cron infrastructure itself.

## References

- Issue: #2802
- Source PR: #2795 (merged c597cc6b)
- Workflow run: https://github.com/jikig-ai/soleur/actions/runs/24795319398
- Audit file: `knowledge-base/marketing/audits/soleur-ai/2026-04-22-aeo-audit.md`
- Merged via: PR #2810 (commit 8428f358)
- Pinned prompt surfaces:
  - `.github/workflows/scheduled-growth-audit.yml` Step 2
  - `plugins/soleur/agents/marketing/growth-strategist.md` GEO/AEO Content Audit section
- Parser runbook: `knowledge-base/project/plans/2026-04-19-chore-aeo-presence-reaudit-after-pr-2596-plan.md`
- AGENTS.md rules applied: `wg-when-fixing-a-workflow-gates-detection` (retroactive gate check), `cm-when-proposing-to-clear-context-or` (resume prompt)
