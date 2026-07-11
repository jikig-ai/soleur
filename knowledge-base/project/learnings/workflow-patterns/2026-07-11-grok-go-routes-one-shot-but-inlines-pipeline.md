---
title: Grok /go routes to one-shot but agent inlines pipeline steps
date: 2026-07-11
tags:
  - grok
  - workflow
  - one-shot
  - fidelity
category: workflow-patterns
closes:
  - 6325
related_prs:
  - 6335
  - 6338
---

# Grok `/go` routes to one-shot but agent inlines pipeline steps

## Symptom

Operator invoked `/go 6325 implement Phase F` under Grok Build. The agent:

1. Correctly classified intent as implementation work.
2. Ran one-shot **Step 0b** (worktree) and **Step 0c** (draft PR).
3. **Implemented Phase F inline** (Write/Edit/Shell on product code).
4. Pushed a draft PR and **stopped** — no `/plan`, `/review`, `/qa`, `/compound`, `/ship`, no merge, no `<promise>DONE</promise>`.

From the operator's perspective the feature "looked done" (code pushed, PR open) but the Soleur lifecycle never ran.

## Root causes

1. **Missing `implement` route** — inputs like "#6325 implement Phase F" fell through to `default`/brainstorm or were manually treated as one-shot without a clear routing row.
2. **No post-route contract** — `/go` named `soleur:one-shot` but nothing forbade the parent agent from cherry-picking one-shot steps.
3. **Weak completion criteria** — "pushed draft PR" was treated as success; one-shot's true deliverable (merged PR) was not enforced at the `/go` boundary.
4. **Harness surface mismatch** — Grok uses slash commands (`/one-shot`); prose still emphasized Claude's Skill tool, making inline tool loops feel equivalent.

## Fix (PR #6338)

| Layer | Change |
|-------|--------|
| Routing | `implement` row in `go.md` → `soleur:one-shot`; golden eval row in `go-routing.jsonl` |
| Post-route gate | `go.md` Step 2.1 (`go-post-route` block): `/go` dispatches only — next action MUST be skill invocation |
| Pipeline contract | `plugins/soleur/lib/workflow-fidelity.ts` — `PIPELINE_SKILLS`, `ONE_SHOT_CHILD_SKILLS`, `workflowFidelityInstructions()` |
| Harness | `harness.ts` appends fidelity block to `routingInstructions()`; `invokeSkill` stresses Steps 0–8 for one-shot |
| one-shot | Anti-bypass protocol block at top of SKILL.md; harness adapter for child skills |
| Session rules | `hr-pipeline-skills-never-inline-after-go-route` in AGENTS.core.md |
| Tests | `workflow-fidelity.test.ts`, `harness.test.ts` sentinel drift guards |

## Detection signals (for future sessions)

- Agent writes product code in the same turn that `/go` classified intent, before `/one-shot` or `/plan` ran.
- Agent reports "done" or "draft PR created" without `<promise>DONE</promise>`.
- Agent reads `one-shot/SKILL.md` and executes Steps 0b–0c then jumps to implementation.

## Correct behavior

```
/go #6325 implement Phase F
  → classify: implement
  → invoke: /one-shot #6325 implement Phase F   # same turn, immediately
/one-shot
  → Steps 0–8 via /plan, /work, /review, /qa, /compound, /ship
  → merged PR + <promise>DONE</promise>
```

## Why this matters

Soleur's value is the full brainstorm→plan→implement→review→compound lifecycle. Skipping review/ship reintroduces silent quality regressions and leaves draft PRs orphaned in the queue — exactly the failure mode autonomous agents optimize toward when completion pressure is ambiguous.