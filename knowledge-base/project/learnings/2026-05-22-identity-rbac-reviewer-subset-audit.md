---
date: 2026-05-22
type: audit
issue: 4322
falsifiability_source: 4233
introducing_pr: 4288
verdict: fold
---

# identity-rbac-reviewer subset audit — verdict: FOLD

## Context

PR #4288 (closing #4233) introduced the standalone `identity-rbac-reviewer` agent as a separable lens for multi-org / workspace boundary integrity (RLS predicates, JWT `current_organization_id`, write-boundary sentinels, SECURITY DEFINER `search_path` pinning, attestation owner-checks).

The plan §Implementation Choice carried a pre-committed falsifiability criterion: **after 5 identity-touching PRs post-merge, audit whether identity-rbac-reviewer's findings were a strict subset of other reviewers' findings on the same PRs.**

- Strict subset (no unique value) → fold the R1-R6 checklist into `security-sentinel` and delete the standalone agent.
- At least one unique finding → keep as standalone.

This document executes that audit.

## Identity-touching PR sample (5 PRs post-#4288)

Identity-touching = path-rule OR content-rule match per the dispatch glob at `plugins/soleur/skills/review/SKILL.md:272-277`.

| PR | Merged-at (UTC) | Title (abbrev) | Path-rule match | Content-rule matches | Dispatched? |
|---|---|---|---|---|---|
| #4287 | 2026-05-22T20:21:30Z | mig 063 workspace_member_actions audit log | yes (`migrations/.*\.sql`) | 94 | yes |
| #4289 | 2026-05-22T08:07:37Z | team-workspace-legal-scaffolding | no | 19 | yes (content) |
| #4294 | 2026-05-22T09:21:11Z | DSAR departed-workspace-member coverage | yes | 51 | yes |
| #4331 | 2026-05-22T09:49:36Z | identity-aware Flagsmith per-role targeting | no | 0 | NO (correctly skipped) |
| #4339 | 2026-05-22T12:34:31Z | mig 062 workspaces-dep one-shot | yes (mig 062 re-apply) | 9 | yes |

**Eligible-to-fire = 4 of 5** (#4331's diff contained zero canonical content patterns and edits no path-rule paths; the dispatch correctly skipped).

## Per-PR review-commit attribution

Canonical attribution source: `git log --format=%B <review-sha>` on each branch's `review:` commit. (GitHub PR review/comment threads were empty — operator ran multi-agent review locally and recorded findings in the review commit body, then either fixed inline or filed scope-outs.)

| PR | Review SHA (pre-squash) | Squash-merge SHA (origin/main) | Agents credited in commit body | identity-rbac credited? |
|---|---|---|---|---|
| #4287 | `cf206114` | `e071b791` | git-history-analyzer (P1, P2-1); pattern-recognition-specialist (P1-2, P1-1, P2-3); data-integrity-guardian (P1-A); migration-expert (P2-1); performance-oracle (P2-1); architecture-strategist (deferred ×2); test-design-reviewer (deferred) | **NO** |
| #4289 | `29d80b80` | `8877c198` | git-history-analyzer + data-integrity-guardian + pattern-recognition-specialist + test-design-reviewer (P2 concur); code-simplicity-reviewer (DISSENT flip) | **NO** |
| #4294 | `5faf0134` | `ce53967f` | security-sentinel (P2 orphan-org FK); data-integrity-guardian (P2 down-mig guard); user-impact-reviewer (F7); pattern-recognition-specialist (stale comment); code-simplicity-reviewer (DISSENT flip); code-quality-analyst | **NO** |
| #4339 | `6b2036ee` | `2d2ed6df` | pattern-recognition-specialist (F1/F3/F5); code-simplicity-reviewer (inline comment); data-integrity-guardian (P2 latent) | **NO** |

The pre-squash SHAs are the canonical attribution source (a fresh clone of `origin/main` resolves them only via the squash-merge body); the squash-merge SHAs are reachable from `origin/main` and preserve the same `review:` ledger text verbatim, so the verdict is reproducible from either ref.

Across the 4 PRs where identity-rbac-reviewer was eligible to fire, **zero** findings were attributed to it in the review-commit ledger. Every workspace-boundary-adjacent finding (mig 062 down-guard, mig 063 backfill ASSERTs, orphan-org RESTRICT→SET NULL, mig 062 idempotency hazard, stale-comment cleanup) was first-surfaced by `security-sentinel`, `data-integrity-guardian`, `pattern-recognition-specialist`, or `git-history-analyzer`.

## Verdict — STRICT (EMPTY) SUBSET → FOLD

Per the falsifiability criterion, identity-rbac-reviewer's findings set is a strict subset of the other reviewers' findings sets on every eligible PR. In fact the set is empty: identity-rbac-reviewer surfaced no findings credited in the review-commit ledger across the 4-PR eligible cohort.

**Action:** Fold the R1-R6 checklist into `security-sentinel` as a `## Multi-org / Workspace Boundary Checklist (R1–R6)` subsection (preserving rules, severity defaults, known-gap deferrals, dispatch-glob staleness note verbatim). Delete `plugins/soleur/agents/engineering/review/identity-rbac-reviewer.md`. Remove the dispatch entry from `plugins/soleur/skills/review/SKILL.md` and rewrite the `#boundaries` paragraph to three-reviewer disambiguation (gdpr-gate / data-integrity-guardian / security-sentinel). Drop the README table row.

## Alternative interpretation considered

**Counter-hypothesis:** identity-rbac-reviewer DID surface findings first but the operator credited only the agent with the clearer remediation in the commit body, so the attribution data understates identity-rbac's contribution.

**Mitigation against false negatives in this audit.** Even granting the counter-hypothesis fully, every finding under review on the 4 eligible PRs was *also* independently surfaced by an agent that fires on a broader trigger set: `security-sentinel` runs on every code PR; `data-integrity-guardian` runs on every migration. identity-rbac-reviewer fires on a narrow path-or-content match. Under the most charitable counter-interpretation, the standalone agent's unique value is "first-to-surface, faster" — but since the broader agents independently re-surface the same findings within the same review cycle, the net coverage is unchanged and the standalone agent adds no marginal merge-blocking signal.

## Structural reasons for the empty-set finding

1. **Path-rule overlap with security-sentinel + data-integrity-guardian dispatch.** Every PR where identity-rbac was eligible was already in security-sentinel's universal code-PR scope AND in data-integrity-guardian's migration-safety scope. There was no diff shape that triggered identity-rbac but NOT one of the broader agents.
2. **Workspace-boundary concerns are not orthogonal to OWASP/CWE concerns.** RLS predicate gaps (R1), write-boundary sentinels (R2), SECURITY DEFINER `search_path` pins (R5), and attestation owner-checks (R6) all map to OWASP A01 (Broken Access Control) / A03 (Injection) / A07 (Identification & Authentication Failures). The R1-R6 checklist is a domain-specific lens *on top of* security-sentinel's OWASP coverage, not a separable concern.
3. **Known-gap deferrals (#4304-#4307, #4318) are tracked as standalone issues** with owners and re-evaluation criteria. Surfacing them as `info`-severity on every identity-PR was design-time decoration — it added line-noise without changing reviewer behavior (the gaps are already in the backlog).

## Forward-looking — preserving checklist value after fold

The R1-R6 rules themselves are good — the verdict is about agent-architecture (standalone vs. inline), not about checklist content. The fold preserves the rules verbatim inside `security-sentinel.md`, ensuring future workspace-boundary PRs still get the lens via the agent that already fires on every code PR.

**Re-extraction is cheap if needed.** The deleted agent body persists in git history at `plugins/soleur/agents/engineering/review/identity-rbac-reviewer.md@<pre-fold-sha>`. If a future class emerges that security-sentinel cannot cover (e.g., a deeply Postgres-specific RLS pattern that benefits from a dedicated checklist agent), re-introducing the standalone agent is a single-file restore plus a SKILL.md dispatch entry.

## Institutional lesson — falsifiability discipline worked

The same-day burst between #4288 merging (2026-05-22T07:40Z) and the 5th identity-touching PR (#4339 at +4h54m) was much faster than the originally-expected multi-day cadence — 5 identity-touching PRs landed in a ~5-hour window. The empirical sample is still load-bearing (zero attributions across 4 eligible PRs) and fold-back is still cheap (4 reference sites); the lesson is that a high-traffic burst can satisfy the falsifiability criterion just as well as a deliberate week-long sample, as long as the dispatch eligibility is verified per-PR. Without the pre-committed falsifiability criterion, the standalone agent would have become load-bearing-by-default — fold gets harder the longer the agent exists (downstream references multiply, deletion blast-radius grows).

**Pattern to repeat:** Any "split an existing reviewer into a sibling for clarity" decision should pre-commit an audit window with a binary fold-or-keep verdict criterion, so the choice is falsifiable post-merge rather than locked in by brainstorm-time judgment.

## References

- PR #4288 — `feat(plugin): add identity-rbac-reviewer agent for multi-org/workspace boundary integrity (#4233)` (agent introduction).
- Issue #4233 — `CLOSED` — origin of the "no current agent owns auth/sessions/RBAC cross-cutting" concern.
- Issue #4322 — this audit.
- Review-commit ledger pattern (canonical attribution source): `git log --grep="^review:" --format="%h %s" main` returns per-PR review-fix commits, whose bodies attribute each P-rated finding to a specific agent. Load-bearing data source for any future "did agent X surface anything?" audit.
