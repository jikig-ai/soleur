---
title: "Smoke evidence: target-user-impact gate end-to-end"
date: 2026-04-28
feature: feat-user-impact-gate
issue: 2888
pr: 2889
---

# Smoke Evidence: Target-User-Impact Gate

This file captures the end-to-end smoke run of the workflow gate added in PR #2889.
Each test scenario from `knowledge-base/project/plans/2026-04-24-feat-user-impact-gate-plan.md`
section "Test Scenarios" was executed against a synthetic plan
(`_smoke-synthetic-user-impact-gate-plan.md`). The synthetic plan was deleted
after capture (see Cleanup below).

## T1 — deepen-plan halt on missing section

**Setup:** Synthetic plan with no `## User-Brand Impact` heading.

**Command (Phase 4.6 logic):**

```bash
grep -q '^## User-Brand Impact' <plan-file>
```

**Output:**

```
HALT: Plan is missing `## User-Brand Impact` section.
See plugins/soleur/skills/plan/references/plan-issue-templates.md for the template.
Per AGENTS.md hr-weigh-every-decision-against-target-user-impact, every plan
must answer the user-impact framing question before deepen-plan can proceed.

Telemetry emit (simulated):
  emit_incident hr-weigh-every-decision-against-target-user-impact applied
```

**Result:** PASS — gate fires. Telemetry path is wired (`.claude/hooks/lib/incidents.sh` `emit_incident`).

## T2 — deepen-plan pass on filled section

**Setup:** Synthetic plan now has the section with concrete artifact + vector +
threshold (`single-user incident`).

**Output:**

```
Section body length: 521 chars
PASS Step 1: heading present
PASS Step 2: threshold line found
Threshold = single-user incident → CPO sign-off + user-impact-reviewer at review-time

RESULT: Phase 4.6 passes; deepen-plan proceeds.
```

**Result:** PASS — phase 4.6 lets deepen-plan continue when the section is non-empty and threshold-validated.

## T3 — preflight Check 5 FAIL on missing section

**Setup:** Branch has changes to `apps/web-platform/server/session-sync.ts` (sensitive-path glob match). PR body contains no `## User-Brand Impact` section.

**Output:**

```
Step 5.1: sensitive-path glob match → DO NOT skip
Step 5.3: FAIL — Sensitive-path diff detected but PR body is missing `## User-Brand Impact` section.
          Add the section per plan-issue-templates.md.

RESULT: Check 5 = FAIL (correctly fired).
```

**Result:** PASS — Check 5 fires when a sensitive-path diff lacks the section.

## T4 — preflight Check 5 PASS after fill

**Setup:** Same branch. PR body now contains `## User-Brand Impact` with `Brand-survival threshold: single-user incident`.

**Output:**

```
Threshold line: - **Brand-survival threshold:** single-user incident
Step 5.4: PASS

RESULT: Check 5 = PASS
```

**Result:** PASS — gate stops blocking once the section is filled.

## T5 — preflight Check 5 PASS on scope-out

**Setup:** Sensitive-path diff. PR body declares `threshold: none, reason: comment-only edit, no executable code path changed`.

**Output:**

```
Threshold: - **Brand-survival threshold:** none
Scope-out present → PASS
```

**Result:** PASS — operator-justified scope-out is honored.

## T5b — preflight Check 5 FAIL on threshold=none without scope-out (negative case)

**Setup:** Sensitive-path diff. PR body declares `threshold: none` but no scope-out reason.

**Output:**

```
FAIL — Sensitive-path diff with threshold:none requires a 'threshold: none, reason: <why>' scope-out note.
```

**Result:** PASS — escape hatch is gated; un-justified `none` blocks the ship.

## T6 — review spawns user-impact-reviewer on threshold=single-user incident

**Setup:** Plan declares `Brand-survival threshold: single-user incident`.

**Output:**

```
Match: plan declares 'Brand-survival threshold: single-user incident'
→ Review SKILL.md conditional_agents block fires agent #15 (user-impact-reviewer)
```

**Result:** PASS — review SKILL.md `<conditional_agents>` block lists agent #15 with the matching trigger.

## T7 — review does NOT spawn user-impact-reviewer on threshold=aggregate pattern

**Setup:** Plan declares `Brand-survival threshold: aggregate pattern`.

**Output:**

```
NOT fired — only single-user incident triggers the agent.
```

**Result:** PASS — agent invocation is correctly scoped to the `single-user incident` threshold.

## T8 — AGENTS.md rule visible next session (deferred)

**Setup:** PR #2889 must merge to main before the rule is loaded into a fresh session's CLAUDE.md context. Verification is operator-driven post-merge per AC14.

**Pre-merge verification:** `grep -q 'hr-weigh-every-decision-against-target-user-impact' AGENTS.md` returns 0; `python3 scripts/lint-rule-ids.py` exits 0; `wc -c AGENTS.md` reports 39411 bytes (under the 40k critical threshold).

**Result:** PASS pre-merge; post-merge verification deferred to next session per AC14.

## T9 — telemetry emission path

**Setup:** Both deepen-plan Phase 4.6 (halt) and brainstorm Phase 0.1 (tag-match) reference `emit_incident hr-weigh-every-decision-against-target-user-impact applied`.

**Verification:** `.claude/hooks/lib/incidents.sh` `emit_incident` path is the canonical telemetry channel used by `hr-ssh-diagnosis-verify-firewall` (precedent at `plugins/soleur/skills/deepen-plan/SKILL.md` Phase 4.5). The new gates wire identical syntax.

**Result:** PASS pre-merge; first real-world emission will appear in `.claude/.rule-incidents.jsonl` the next time a plan triggers either layer.

## Gate-Layer Summary

| Layer | Skill / File | Mechanism | Smoke result |
|---|---|---|---|
| Framing | `brainstorm/SKILL.md` Phase 0.1 | AskUserQuestion + trigger-keyword tag | Path verified (T1 prerequisite) |
| Template | `plan/references/plan-issue-templates.md` | `## User-Brand Impact` in MINIMAL/MORE/A-LOT | 3 sections present (`grep -c` = 3) |
| Plan check | `plan/SKILL.md` Phase 2.6 | Section presence + threshold-driven CPO sign-off | Wired |
| Pre-impl halt | `deepen-plan/SKILL.md` Phase 4.6 | Hard halt on missing/empty/placeholder | T1 + T2 PASS |
| Review | `review/SKILL.md` agent #15 | Fires on `single-user incident` only | T6 + T7 PASS |
| Ship gate | `preflight/SKILL.md` Check 5 | FAIL on sensitive-path diff without section | T3 + T4 + T5 + T5b PASS |
| Hard rule | `AGENTS.md` `hr-weigh-…` | Loaded every turn; 493 bytes | Lint passes |

## Cleanup

Synthetic plan (`knowledge-base/project/plans/_smoke-synthetic-user-impact-gate-plan.md`) deleted before merge per Phase G Task G4 of the canonical plan. No dummy edits to `apps/web-platform/server/session-sync.ts` were committed (the path was used as a glob-match target only, not an actual code change).

## References

- Plan: `knowledge-base/project/plans/2026-04-24-feat-user-impact-gate-plan.md`
- Spec: `knowledge-base/project/specs/feat-user-impact-gate/spec.md`
- Issue: #2888
- Triggering incident: #2887
- PR: #2889
