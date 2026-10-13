---
feature: feat-one-shot-5087-model-tiered-agents
issue: 5087
lane: cross-domain
plan: knowledge-base/project/plans/2026-06-11-chore-model-tiered-agent-frontmatter-plan.md
recommended_scope: Option C (narrow additive haiku-floor pin on 5 research agents)
note: Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).
---

# Tasks — Model-tiered maker/checker (#5087)

> Scope below = **Option C** (recommended in the plan). If the operator opts into Option A
> (full sweep + opus reviewer pins) at plan-review, regenerate these tasks from the plan's
> `## Implementation Phases (Option A)` section — Option A additionally requires ADR-054 +
> a policy §1 rewrite enumerating opus exceptions + per-agent justifications on all 25 agents
> + a clo attestation, none of which are in the Option C task list below.

## Phase 0 — Confirm direction (gating)

- [ ] 0.1 Confirm Option C is the chosen scope (not A/B). The plan's Decision Required recommends C;
      Option A's opus reviewer pins are a separate, ADR-supersession-class change and are NOT in this list.
- [ ] 0.2 Re-read `plugins/soleur/AGENTS.md` Model Selection Policy §1 to confirm the override-with-justification
      mechanism is still the live convention before editing.

## Phase 1 — Frontmatter pins (5 research agents)

For EACH of the 5 files, use the Edit tool on the frontmatter `model:` line ONLY (line 4), then add a
one-sentence body justification. Do NOT use a global `sed` (defensive habit; these 5 have no example-block
`model:` line, but keep the per-file Edit discipline).

- [ ] 1.1 `plugins/soleur/agents/engineering/research/repo-research-analyst.md` → `model: haiku` + justification.
- [ ] 1.2 `plugins/soleur/agents/engineering/research/learnings-researcher.md` → `model: haiku` + justification.
- [ ] 1.3 `plugins/soleur/agents/engineering/research/best-practices-researcher.md` → `model: haiku` + justification.
- [ ] 1.4 `plugins/soleur/agents/engineering/research/framework-docs-researcher.md` → `model: haiku` + justification.
- [ ] 1.5 `plugins/soleur/agents/engineering/research/git-history-analyzer.md` → `model: haiku` + justification.
- [ ] 1.6 Justification text (each agent body): one sentence — pure read-and-summarize role; pinned to the haiku
      floor per #5087 to close the ADR-053 direct-`Task`-spawn coverage gap (`/plan`/`/brainstorm` spawn these
      unpinned); floor-safe (never upgrades a session). Cite this plan + ADR-053.

## Phase 2 — Policy registration

- [ ] 2.1 `plugins/soleur/AGENTS.md` policy §1: change "Current exceptions: none." → enumerate the 5 research
      agents as haiku exceptions, with a one-line rationale citing the direct-spawn coverage gap. This is a
      within-§1 override registration, NOT an ADR-053 supersession (no Decision-#1 reversal).

## Phase 3 — Verify (Acceptance Criteria C-AC1..C-AC5)

- [ ] 3.1 `for f in <5 files>; do grep -c '^model: haiku' "$f"; done` → all 1 (C-AC1).
- [ ] 3.2 Each of the 5 bodies contains the justification sentence referencing the plan + ADR-053 (C-AC1, verify shape).
- [ ] 3.3 `grep -c 'Current exceptions: none' plugins/soleur/AGENTS.md` → 0; `grep -c 'repo-research-analyst' plugins/soleur/AGENTS.md` → ≥1 (C-AC2).
- [ ] 3.4 `git diff --name-only` lists exactly the 5 research files + AGENTS.md (+ plan/tasks) — no reviewer/
      discovery/orchestrator agent touched; never-downgrade list untouched (C-AC3).
- [ ] 3.5 `cd /home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-5087-model-tiered-agents && bun test plugins/soleur/test/components.test.ts` passes (C-AC4).
- [ ] 3.6 `grep -h 'description:' plugins/soleur/agents/**/*.md | wc -w` still < 2500 — justifications went in BODY, not `description:` (C-AC5).

## Phase 4 — Ship

- [ ] 4.1 PR body uses `Closes #5087` (Option C is a normal pre-merge change; no post-merge operator step, so `Closes` is correct here — unlike ops-remediation plans).
- [ ] 4.2 Note in the PR body that Option A (opus reviewer pins) was deliberately deferred as a separate
      ADR-supersession-class change; link the plan's Decision Required section.
