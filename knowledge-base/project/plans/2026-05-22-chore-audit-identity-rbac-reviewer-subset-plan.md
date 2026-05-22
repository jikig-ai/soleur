---
type: chore
lane: procedural
requires_cpo_signoff: false
issue: 4322
falsifiability-source: 4233
---

# Audit identity-rbac-reviewer findings after 5 identity-touching PRs

Closes #4322.

## Overview

PR #4288 (#4233) introduced the standalone `identity-rbac-reviewer` agent as a separable lens for multi-org / workspace boundary integrity. The plan §Implementation Choice carried a falsifiability criterion: after 5 identity-touching PRs post-merge, audit whether identity-rbac-reviewer's findings were a strict subset of other reviewers' findings — if so, fold the R1–R6 checklist back into `security-sentinel` as a "Multi-org / workspace boundary" subsection and delete the standalone agent.

This plan executes that audit and the consequent action in a single PR.

## User-Brand Impact

**If this lands broken, the user experiences:** No direct user-facing artifact — this PR edits review-skill orchestration only.
**If this leaks, the user's [data / workflow / money] is exposed via:** N/A (no production code paths touched).
**Brand-survival threshold:** none — internal tooling cleanup. The downstream risk if we fold incorrectly is that future workspace-boundary PRs lose a dedicated lens; mitigated by the R1–R6 checklist persisting verbatim inside security-sentinel.

## Research Reconciliation — Spec vs. Codebase

| Spec claim (issue body) | Reality | Plan response |
|---|---|---|
| "5 PRs that triggered identity-rbac-reviewer dispatch" | 4 of 5 PRs match the dispatch rule's path-or-content gate (#4287, #4289, #4294, #4339); #4331 contains 0 trigger-content matches and edits no path-rule paths | Audit covers all 5 PRs; #4331 is documented as "agent should not have fired" rather than evidence of subset behavior |
| "compare findings" | GitHub PR review/comment threads contain zero identity-rbac or security-sentinel attributions; findings live in the `review:` commit messages on each branch | Audit data source = `git log` of `review:` commits per PR, not `gh pr view --json reviews,comments` (which returns empty) |
| Issue numbers #4304/#4305/#4306/#4307/#4318 as "known gaps" surfaced as `info` on every identity PR | These issues are tracked but no review commit cites them as identity-rbac surfacing them on the 4 eligible PRs | Audit table records "known gaps surfaced: not attributed in review commit" as the empirical state |

## Audit Data (pre-computed at plan time)

Dispatch-rule eligibility (per `plugins/soleur/skills/review/SKILL.md:272-277`):

| PR | Path-rule match | Content-rule matches | Identity-rbac dispatched? |
|---|---|---|---|
| #4287 (mig 063 workspace_member_actions) | yes (`migrations/.*\.sql`, `lib/supabase/tenant.ts` not present) | 94 | yes |
| #4289 (team-workspace-legal-scaffolding) | no (`docs/legal/`, `app/(auth)/accept-terms/`) | 19 | yes (via content rule) |
| #4294 (mig 062 departed-member DSAR) | yes | 51 | yes |
| #4331 (Flagsmith identity-aware flags) | no | 0 | NO (correctly not dispatched) |
| #4339 (tenant-integration mig 062 fix) | yes (mig 062 re-apply) | 9 | yes |

Per-PR review commit attribution (canonical source: `git log --format=%B <review-sha>` on each PR's `review:` commit):

| PR | Review commit SHA | Agents credited in commit body | identity-rbac credited? |
|---|---|---|---|
| #4287 | `cf20611` | git-history-analyzer (P1, P2-1), pattern-recognition-specialist (P1-2, P1-1, P2-3), data-integrity-guardian (P1-A), migration-expert (P2-1), performance-oracle (P2-1), architecture-strategist (deferred ×2), test-design-reviewer (deferred) | NO |
| #4289 | `29d80b8` | git-history-analyzer + data-integrity-guardian + pattern-recognition-specialist + test-design-reviewer (P2 concur), code-simplicity-reviewer (DISSENT flip) | NO |
| #4294 | `5faf013` | security-sentinel (P2 orphan-org FK), data-integrity-guardian (P2 down-mig guard), user-impact-reviewer (F7), pattern-recognition-specialist (stale comment), code-simplicity-reviewer (DISSENT flip), code-quality-analyst | NO |
| #4339 | `6b2036e` | pattern-recognition-specialist (F1/F3/F5), code-simplicity-reviewer (inline comment), data-integrity-guardian (P2 latent) | NO |

Across 4 PRs where identity-rbac-reviewer was eligible to fire and 100% of cases where the dispatch rule passed, **zero** findings were attributed to identity-rbac-reviewer in the review-commit ledger. Every workspace-boundary-adjacent finding (mig 062 down-guard, mig 063 backfill ASSERTs, orphan-org RESTRICT→SET NULL, mig 062 idempotency hazard) was attributed to security-sentinel, data-integrity-guardian, pattern-recognition-specialist, or git-history-analyzer.

**Verdict: STRICT SUBSET (in fact, EMPTY) — fold R1–R6 into security-sentinel and delete the standalone agent.**

## Open Code-Review Overlap

None. No open code-review issues touch the four files in scope (`plugins/soleur/agents/engineering/review/identity-rbac-reviewer.md`, `plugins/soleur/agents/engineering/review/security-sentinel.md`, `plugins/soleur/skills/review/SKILL.md`, `plugins/soleur/README.md`).

## Files to Create

- `knowledge-base/project/learnings/2026-05-22-identity-rbac-reviewer-subset-audit.md` — audit report with the per-PR comparison table above, the empty-set finding, and the fold-or-keep verdict reasoning (canonical source the PR body links to).

## Files to Edit

- `plugins/soleur/agents/engineering/review/security-sentinel.md` — append a `## Multi-org / Workspace Boundary Checklist (R1–R6)` section containing the R1–R6 rules verbatim from the deleted agent (including dispatch-time path/content match, severity defaults, known-gap deferrals #4304/#4305/#4306/#4307/#4318, and the dispatch-glob staleness note). Inline the body so security-sentinel becomes the single source of truth.
- `plugins/soleur/skills/review/SKILL.md` — remove entry #17 (identity-rbac-reviewer dispatch block at lines 268-279) and replace the `#boundaries` paragraph with a three-reviewer disambiguation (gdpr-gate / data-integrity-guardian / security-sentinel). The new security-sentinel description must mention that it owns workspace-boundary review (R1–R6 subsection in the agent body). Re-number any downstream entries that depended on the slot.
- `plugins/soleur/README.md` — delete the `identity-rbac-reviewer` table row at line 103.
- `plugins/soleur/agents/engineering/review/identity-rbac-reviewer.md` — DELETE.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `knowledge-base/project/learnings/2026-05-22-identity-rbac-reviewer-subset-audit.md` exists and contains: per-PR comparison table covering all 5 PRs, dispatch-rule eligibility table, review-commit attribution table, and "fold" verdict with reasoning.
- [ ] `plugins/soleur/agents/engineering/review/identity-rbac-reviewer.md` does NOT exist (`test ! -f plugins/soleur/agents/engineering/review/identity-rbac-reviewer.md` returns 0).
- [ ] `git grep -nE 'identity-rbac-reviewer|identity-rbac' plugins/ knowledge-base/ docs/ .github/ apps/ -- ':!**/archive/**' ':!knowledge-base/project/learnings/2026-05-22-identity-rbac-reviewer-subset-audit.md' ':!knowledge-base/project/plans/2026-05-22-chore-audit-identity-rbac-reviewer-subset-plan.md'` returns zero matches. (The audit-learning and this plan are the only permitted historical references.)
- [ ] `plugins/soleur/agents/engineering/review/security-sentinel.md` contains the literal string `## Multi-org / Workspace Boundary Checklist (R1–R6)`.
- [ ] Security-sentinel R1–R6 subsection contains each of the six rule keys: `grep -cE '^### R[1-6] ' plugins/soleur/agents/engineering/review/security-sentinel.md` returns 6.
- [ ] Security-sentinel R1–R6 subsection contains all five known-gap deferral issue references: `grep -cE '#430[4-7]|#4318' plugins/soleur/agents/engineering/review/security-sentinel.md` returns ≥ 5.
- [ ] `plugins/soleur/README.md` does NOT contain `identity-rbac-reviewer` (`grep -c identity-rbac plugins/soleur/README.md` returns 0).
- [ ] `plugins/soleur/skills/review/SKILL.md` does NOT contain entry #17 for identity-rbac-reviewer; the `{#boundaries}` paragraph names three reviewers (gdpr-gate, data-integrity-guardian, security-sentinel), not four.
- [ ] `bun test plugins/soleur/test/components.test.ts` passes (skill description budget intact — this PR does not edit any SKILL description, only body prose, so the test is a safety net, not a target).
- [ ] PR body contains `Closes #4322` (issue auto-closes on merge — no post-merge operator action required for this PR).

### Post-merge (operator)

- [ ] None. This PR is a pure docs/agent-orchestration edit; no infrastructure, no migrations, no operator-driven steps. `/soleur:ship` handles `gh pr ready` + auto-merge + issue close automatically.

## Test Strategy

No new tests. Verification is grep-based per the AC list above. The R1–R6 checklist's behavioral assertion (it should fire on workspace-boundary PRs) is empirically falsified by the audit data — fold is the correct response to that finding, not "add tests asserting fire pattern".

## Risks

- **Future workspace-boundary PRs lose a dedicated lens.** Mitigation: R1–R6 checklist is preserved verbatim inside security-sentinel; the dispatch condition (workspace_id / is_workspace_member content match) becomes a sub-trigger of the security-sentinel dispatch, which already fires on every code PR. Net coverage is the same — the lens lives inside a more-broadly-spawned agent.
- **The empty-attribution finding may be a measurement artifact** (e.g., identity-rbac-reviewer DID surface findings but the operator only credited the agent that re-surfaced them with a clearer remediation). Mitigation: the audit-learning explicitly names this as a possible alternative interpretation and documents that even if identity-rbac was "first-to-surface," every finding was independently surfaced by an agent that fires on more PRs (security-sentinel fires on every code PR; identity-rbac fires on a narrow path-or-content match) — so the standalone agent adds no marginal coverage.
- **Re-introduction cost.** If a future workspace-boundary class emerges that security-sentinel cannot cover (e.g., a deeply Postgres-specific RLS pattern), re-introducing identity-rbac-reviewer is cheap — the agent body is preserved in git history at `plugins/soleur/agents/engineering/review/identity-rbac-reviewer.md` pre-deletion.

## Domain Review

**Domains relevant:** none — this is pure tooling/orchestration cleanup with no product, legal, compliance, or infra implications.

No cross-domain implications detected — single-domain procedural change (review-skill agent dispatch).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. This plan declares threshold = `none` because the change is internal tooling only.
- When editing `plugins/soleur/skills/review/SKILL.md` to remove entry #17, verify the numbered list does not have a numbering gap. The entry at line 270 is `17. Task identity-rbac-reviewer(...)` and the next numbered entry (a re-use of `17.` for the anti-slop scanner hook at line 290) is a duplicate-number — when removing the identity-rbac dispatch, also verify the anti-slop entry's number is consistent with the renumbered list. Per the wider codebase pattern, numbered entries in SKILL.md dispatch are positional only — no test enforces a specific integer at a specific dispatch slot, but plan-review will flag obvious numbering gaps.
- The `#boundaries` anchor (line 281, `{#boundaries}`) is referenced from other agent files (`security-sentinel.md`, `gdpr-gate/SKILL.md`, `data-integrity-guardian.md`) per the canonical-disambiguation comment. Preserve the anchor verbatim and edit only the four-reviewer→three-reviewer prose. Verify with `git grep -F '{#boundaries}'` post-edit.
- The R1–R6 subsection inside security-sentinel must preserve the **dispatch-time content patterns** (`\bis_workspace_member\b`, `\bcurrent_organization_id\b`, etc.) verbatim — these are the canonical-source patterns the SKILL.md dispatch glob references. A typo here silently disables workspace-boundary review for the next migration PR.

## Implementation Phases

1. **Phase 0 — Verify audit data is current.** Re-run `gh pr view <N> --json commits --jq '.commits[] | select(.messageHeadline | test("^review:")) | .oid'` for each of the 5 PRs and confirm the review-commit SHAs in the audit table match (`cf20611`, `29d80b8`, `5faf013`, `6b2036e`; PR #4339's review commit). If any review commit has been amended/force-pushed since plan time, re-extract attributions and update the audit-learning before proceeding.
2. **Phase 1 — Write audit learning.** Create `knowledge-base/project/learnings/2026-05-22-identity-rbac-reviewer-subset-audit.md` with the full audit data, comparison table, verdict, and alternative-interpretation discussion.
3. **Phase 2 — Fold R1–R6 into security-sentinel.** Append the `## Multi-org / Workspace Boundary Checklist (R1–R6)` section to `plugins/soleur/agents/engineering/review/security-sentinel.md`, copying the R1–R6 rule bodies verbatim from `identity-rbac-reviewer.md` (including dispatch path/content patterns, severity defaults, known-gap deferrals, dispatch-glob staleness note, and reporting protocol delta).
4. **Phase 3 — Remove the dispatch entry.** Edit `plugins/soleur/skills/review/SKILL.md`: delete the lines 268-279 block (entry #17 + "When to run" + "What this agent checks"). Rewrite the `#boundaries` paragraph as three-reviewer disambiguation. Verify `{#boundaries}` anchor preserved.
5. **Phase 4 — Update README.** Delete the `identity-rbac-reviewer` row from `plugins/soleur/README.md:103`.
6. **Phase 5 — Delete agent body.** `git rm plugins/soleur/agents/engineering/review/identity-rbac-reviewer.md`.
7. **Phase 6 — Verify AC list.** Run all grep-based ACs; iterate if any fail.

## Observability

Skipped — pure-docs PR with no code/infra surface (per Phase 2.9 skip condition: "Plan is pure-docs (no Files-to-Edit under code/infra paths above)"). All edits land in `plugins/soleur/agents/`, `plugins/soleur/skills/`, `plugins/soleur/README.md`, and `knowledge-base/project/learnings/`.

## Infrastructure (IaC)

Skipped — no new infrastructure, no servers, no secrets, no vendor accounts. Pure agent/skill/docs edits.

## GDPR / Compliance Gate

Skipped — no regulated-data surface touched. Edits are to review-tooling orchestration only; no schemas, migrations, auth flows, API routes, or `.sql` files. No new LLM-summarization paths, no new artifact-distribution surfaces.
