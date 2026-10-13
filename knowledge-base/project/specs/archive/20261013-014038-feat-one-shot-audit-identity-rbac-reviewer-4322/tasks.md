# Tasks — Audit identity-rbac-reviewer subset and fold into security-sentinel

Plan: `knowledge-base/project/plans/2026-05-22-chore-audit-identity-rbac-reviewer-subset-plan.md`
Issue: #4322 (closes on merge)
Lane: procedural

## Phase 0 — Verify audit data is current

- [ ] 0.1 Re-extract review-commit SHAs for PRs #4287, #4289, #4294, #4339 via `gh pr view <N> --json commits` and confirm they match the plan's audit table (`cf20611`, `29d80b8`, `5faf013`, `6b2036e`).
- [ ] 0.2 If any SHA has changed (force-push amend), re-read the new commit body and update the audit-learning's attribution table before continuing.
- [ ] 0.3 Confirm PR #4331 still has 0 content-rule matches via `gh pr diff 4331 | grep -cE '\b(is_workspace_member|current_organization_id|workspace_members|set_current_organization_id|add_workspace_member_attestation)\b'`.

## Phase 1 — Write audit learning

- [ ] 1.1 Create `knowledge-base/project/learnings/2026-05-22-identity-rbac-reviewer-subset-audit.md`.
- [ ] 1.2 Include sections: Context, Dispatch-rule eligibility table, Per-PR review-commit attribution table, Verdict (fold), Alternative interpretations + rebuttals, Action taken in same PR.
- [ ] 1.3 Verify the learning links back to plan + issue #4322 + originating issue #4233.

## Phase 2 — Fold R1–R6 into security-sentinel

- [ ] 2.1 Read `plugins/soleur/agents/engineering/review/identity-rbac-reviewer.md` to capture verbatim source for R1–R6 + known-gap deferrals + dispatch-glob staleness note.
- [ ] 2.2 Edit `plugins/soleur/agents/engineering/review/security-sentinel.md` to append a new `## Multi-org / Workspace Boundary Checklist (R1–R6)` section AFTER the existing OWASP scanning checklist.
- [ ] 2.3 The new section MUST contain: dispatch path/content patterns (verbatim from SKILL.md:272-277), six `### R1` … `### R6` subsection headings, known-gap bullets for #4304/#4305/#4306/#4307/#4318, dispatch-glob staleness note.
- [ ] 2.4 Verify `grep -cE '^### R[1-6] ' plugins/soleur/agents/engineering/review/security-sentinel.md` returns 6.
- [ ] 2.5 Verify `grep -cE '#430[4-7]|#4318' plugins/soleur/agents/engineering/review/security-sentinel.md` returns ≥ 5.

## Phase 3 — Remove the dispatch entry

- [ ] 3.1 Edit `plugins/soleur/skills/review/SKILL.md`: delete lines 263-279 (the `**If diff touches multi-org / workspace boundary surfaces:**` block + entry #17 + "When to run" + "What this agent checks" bullet for identity-rbac-reviewer).
- [ ] 3.2 Rewrite the `#### Boundary disambiguation` paragraph to name three reviewers (gdpr-gate / data-integrity-guardian / security-sentinel). Include a sentence that security-sentinel owns workspace-boundary review via the R1–R6 subsection in its agent body.
- [ ] 3.3 Verify `{#boundaries}` anchor preserved verbatim: `grep -c '{#boundaries}' plugins/soleur/skills/review/SKILL.md` returns ≥ 1.
- [ ] 3.4 Verify no numbering gap or orphan reference to entry #17 for identity-rbac-reviewer.

## Phase 4 — Update README

- [ ] 4.1 Edit `plugins/soleur/README.md`: delete the `identity-rbac-reviewer` table row at line 103.
- [ ] 4.2 Verify `grep -c identity-rbac plugins/soleur/README.md` returns 0.

## Phase 5 — Delete agent body

- [ ] 5.1 `git rm plugins/soleur/agents/engineering/review/identity-rbac-reviewer.md`.
- [ ] 5.2 Verify `test ! -f plugins/soleur/agents/engineering/review/identity-rbac-reviewer.md` returns 0.

## Phase 6 — Final AC verification

- [ ] 6.1 Run the full grep-AC battery from the plan's "Pre-merge (PR)" section.
- [ ] 6.2 `git grep -nE 'identity-rbac-reviewer|identity-rbac' plugins/ knowledge-base/ docs/ .github/ apps/ -- ':!**/archive/**' ':!knowledge-base/project/learnings/2026-05-22-identity-rbac-reviewer-subset-audit.md' ':!knowledge-base/project/plans/2026-05-22-chore-audit-identity-rbac-reviewer-subset-plan.md'` returns zero matches.
- [ ] 6.3 `bun test plugins/soleur/test/components.test.ts` passes (safety-net check — this PR does not edit any SKILL `description:`).
- [ ] 6.4 PR body contains `Closes #4322`.

## Phase 7 — Ship

- [ ] 7.1 Run `/soleur:ship` to commit, push, mark PR ready, run preflight, and trigger auto-merge.
- [ ] 7.2 `/soleur:ship` Phase 5.5 will verify all gates green and post-merge will auto-close #4322.
