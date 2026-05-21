---
date: 2026-05-21
category: workflow-patterns
tags: [brainstorm, premise-validation, worktree, adr, granularity, deferral-vs-legal-floor]
related_issues: [4078, 3244]
related_prs: [4213, 4065]
related_learnings:
  - 2026-05-19-bare-repo-grep-and-subagent-infra-claim-verification.md
  - 2026-05-15-brainstorm-leader-research-sequencing-and-prior-art-cwd.md
  - 2026-05-12-brainstorm-defer-decision-issue-body-rule-drift-and-oauth-only-bundling-scope-bound.md
  - 2026-05-07-brainstorm-verify-referenced-pr-state-and-leader-infra-claims.md
---

# PR-I brainstorm: three premise-verification patterns + one deferral-vs-legal-floor resolution pattern

## Problem

PR-I (issue #4078) was a "deferred from PR-H" follow-up brainstorm. Four moments of friction surfaced before approach selection — each one would have wasted a Phase 0.5 leader fan-out (3-5 min parallel agent compute) if missed at premise validation:

1. The cited carry-forward artifact (`knowledge-base/project/brainstorms/2026-05-19-pr-h-trust-tier-external-classes-brainstorm.md`) returned **not found** when grepped from the bare-repo root at Phase 0's pre-worktree premise probe — but existed at the worktree clone's `origin/main` HEAD.
2. The issue body's `template_hash` references assumed per-template granularity. PR-H had shipped a placeholder `templateHashFor` at `apps/web-platform/app/api/dashboard/today/[id]/send/route.ts:70-80` computing `sha256(action_class:owning_domain:tier)` — collapsing all sends with the same (class, domain, tier) into one bucket. Without a real per-template registry, `template_authorizations` granularity would have collapsed to `scope_grants` granularity, weakening the GDPR Art. 7(3) "authorize THIS template" defense.
3. The issue body's step 3(a) prescribed "flip `action_class_registry` default for that `template_hash`" — assuming a runtime-mutable registry. ADR-034 (landed in PR-H) fixed the action-class registry as **code-static** (verified `apps/web-platform/server/scope-grants/action-class-map.ts:23-45` is a literal-union). Step 3(a) was architecturally incompatible with main as it now stands.
4. The operator's framing — "structural design only, bounds deferred" — collided with CLO's Art. 7(3) hard floor: `template_authorizations` rows with NULL bound columns (`max_sends`, `expires_at`, `soft_reconfirm_at`) are functionally identical to a blanket consent waiver, re-opening the finding CLO closed in PR-H.

## Solution / Reusable Patterns

### Pattern 1 — Pre-worktree premise probe must use worktree-clone grep, not bare-root

`AGENTS.md` `hr-when-in-a-worktree-never-read-from-bare-repo` covers reads from inside a worktree session. The **pre-worktree** probe at brainstorm Phase 0 is the inverse case: the worktree doesn't exist yet, but the cited artifact may be at `origin/main` HEAD that the worktree will clone. The bare repo's working-tree files reflect whatever was last checked out into the bare root for a manual inspection — which can lag `origin/main`.

**Fix:** when probing for cited artifact existence in Phase 0 pre-worktree, either (a) `git show origin/main:<path>` to read from the canonical ref directly, or (b) defer the artifact-existence check until after the worktree is created and re-grep from inside it. Updating brainstorm SKILL.md Phase 0 Pre-worktree premise probe to mention this explicitly.

### Pattern 2 — Verify cited substrate's actual granularity at the call site before accepting issue body premise

When an issue body cites a hash, key, or identifier (`template_hash`, `tenant_key`, `lookup_id`), grep the **producer call site** to confirm the granularity claim. The shape of `templateHashFor` at PR-H's send route was the load-bearing signal — issue #4078 body implicitly assumed per-template granularity that didn't exist. CTO surfaced this at Phase 0.5 by grepping send/route.ts:70-80.

This is sharper than the existing "Verifying cited flag/symbol against main before spawning leaders" Phase 1.1 check, which targets *retirement comments* and *gating symbols*. The granularity check targets *what does this hash actually distinguish?* — a different failure mode that PR-I caught only because CTO independently grepped the producer.

**Fix:** brainstorm SKILL.md Phase 1.1 already has multiple "verify cited X" patterns. Adding one for substrate granularity (hash/key/identifier producer call-site grep) when the issue body's predicate path depends on the granularity claim.

### Pattern 3 — Cross-check issue body's prescribed registry mutations against the relevant ADR's mutability decision

Issue bodies are written-once and can drift from later architectural decisions. When an issue body cites a registry mutation (`flip X default`, `add row to Y`, `update Z config`), check the relevant ADR for a code-static-vs-runtime-mutable decision before designing around the mutation. Issue #4078 step 3(a) prescribed `action_class_registry` mutation, but ADR-034 had already fixed the registry as code-static — the mutation is architecturally impossible.

Restated quarantining mechanism: write a `template_authorizations` row with `revoked_at=now, revocation_reason='quarantine_retroactive'`. No registry mutation. `isTemplateAuthorized` returns null on next probe.

**Fix:** brainstorm SKILL.md Phase 1.1 — adding an "ADR mutability cross-check" item alongside the existing "verifying cited flag/symbol" pattern.

### Pattern 4 — Deferral-vs-legal-floor resolution: NOT NULL with provisional defaults

Operator's "structural design only, bounds deferred" framing was a reasonable engineering instinct (don't commit to 100/30/90/30 calibration numbers without cohort usage data). CLO's Art. 7(3) hard floor rejected NULL-bound rows (blanket consent waiver). Resolution: **ship columns NOT NULL with provisional defaults sourced from the previous brainstorm's carry-forward; the follow-up issue tunes the values, it does not introduce them.** This preserves both intents — Art. 7(3) satisfied at structural ship + no commitment to specific calibration numbers.

The reusable mental model: when an operator's "defer X" framing collides with a hard-floor invariant (legal, security, audit), the resolution is rarely "operator override" or "block on operator's framing." It's "ship X with provisional defaults sourced from a documented prior decision, and reframe the follow-up as *tuning* not *introducing*."

This is a Phase 1.2 dialogue pattern, not a static rule — the cost of codifying it is shape-fitting it to all "deferral vs floor" axes, and we don't yet have enough data points beyond PR-I. Captured here for retrieval if it recurs; not promoted to AGENTS.md.

## Key Insight

Three of the four patterns (1, 2, 3) share a structure: **the issue body is written at one point in time; main drifts; the brainstorm parent's Phase 0/0.5/1.1 must independently verify the issue's premise rather than treating the body as a factual floor.** PR-I's issue body had three independent factual gaps (bare-root grep, granularity placeholder, ADR mutability) that a 90-second pre-worktree + Phase 1.1 verification pass caught. Without those verification steps, the Phase 0.5 leader fan-out would have committed prose to a wrong premise on each axis.

The 4th pattern (deferral vs legal floor) is structurally different — it's a *dialogue reconciliation* pattern, not a *premise verification* pattern. Worth keeping separate so future readers don't conflate them.

## Session Errors

1. **Bare-root grep false negative for cited brainstorm path.** Pre-worktree premise probe at Phase 0 ran `find knowledge-base ...` from the bare-repo root and reported the file missing. The file existed at the worktree clone's `origin/main` HEAD. **Recovery:** caught at Phase 1.1 prior-art check (re-ran from inside the worktree); all subsequent leader prompts used worktree-relative paths. **Prevention:** brainstorm SKILL.md Phase 0 pre-worktree probe gains an explicit "use `git show origin/main:<path>` or defer to post-worktree re-grep" note (routed below).

2. **Deferred-tool loading delay (TaskCreate, TaskUpdate).** Cost was 2 extra ToolSearch calls when task-tracking became useful mid-flow. **Recovery:** loaded the schemas as needed. **Prevention:** none warranted — deferred-tool loading is a harness-level mechanism, and reactive load on first use is the right cost profile for a brainstorm with 6 tasks.

## Cross-References

- `knowledge-base/project/learnings/2026-05-19-bare-repo-grep-and-subagent-infra-claim-verification.md` — the prior learning that motivated this pattern for the in-session worktree case. PR-I extends it to the pre-worktree probe case.
- `knowledge-base/project/learnings/2026-05-15-brainstorm-leader-research-sequencing-and-prior-art-cwd.md` — adjacent prior-art for worktree-vs-bare-root grep failure modes.
- `knowledge-base/project/brainstorms/2026-05-21-pr-i-template-authorizations-brainstorm.md` — the brainstorm that surfaced these patterns.
- `knowledge-base/project/brainstorms/2026-05-19-pr-h-trust-tier-external-classes-brainstorm.md` — the predecessor brainstorm; the cited carry-forward at issue.
- PR #4065 — PR-H implementation that introduced the placeholder `templateHashFor` and ADR-034 (code-static action-class registry).
