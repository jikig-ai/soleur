---
title: Plan — verify reducer case arms with grep, not Read-first-N-lines
date: 2026-05-13
category: best-practices
module: plan
issue: 2939
related_pr: 3743
tags: [plan-skill, paraphrase-without-verification, reducer, case-arms, kieran-review]
---

# Learning: When verifying a reducer/switch against a spec claim, grep ALL `case` arms — Read-first-N-lines is confidence not correctness

## Problem

During plan-write for #2939 PR-A, Phase 1 verification of a spec claim ("chip removal triggers on `stream_end`") used `Read(file, limit=100)` on `apps/web-platform/test/cc-soleur-go-end-to-end-render.test.tsx`. The Read showed a workflow_started→chip-removal sequence in the first test. I concluded the spec was wrong: "trigger is `workflow_started`, NOT `stream_end`," and wrote that into Research Reconciliation row 5 of the plan as a "Kieran-style correction" of the spec.

Kieran plan-review caught the error: `apps/web-platform/lib/chat-state-machine.ts` ships **both** `case "stream_end"` (line 522, removes `tool_use_chip` via filter) **and** `case "workflow_started"` (line 716, also filters `tool_use_chip`). The spec was right that `stream_end` is a trigger; the plan rewrote correct semantics into a regression hole. FR1.3 as plan-v1-written would have asserted only the `workflow_started` path, silently green-lighting any future regression that broke `stream_end` removal.

The Read-first-N-lines view showed *one* test of *one* sequence — the test author happened to demonstrate the `workflow_started` path first. Other case arms in the reducer live at lines 522 and beyond, outside the first-100-line window. The Read produced confidence ("I checked"), not correctness ("I enumerated").

## Solution

**Plan-skill rule:** When verifying a spec claim about a reducer/switch statement's behavior, the verification command MUST be `grep -n "case " <reducer-file>` (enumerate all arms) BEFORE the targeted `Read`. The Read is for *each matching arm's body*; the grep is the enumeration.

Concretely, for a claim of form "X triggers behavior Y":
1. `grep -n "case " <reducer.ts>` — enumerate every `case` arm by line number.
2. For each line, `Read(file, offset=<line>, limit=20)` — verify whether that arm contains a fingerprint of behavior Y.
3. Sum: how many arms exhibit behavior Y? That count is the load-bearing number for FRs that assert "X is the only trigger" or "X is one of N triggers."

`Read(file, limit=100)` is fine for first-pass orientation, but it is NOT a verification primitive for claims about exhaustive triggers. Reducers in this codebase routinely exceed 600 lines; switches with 8-12 case arms are common; the first arm is rarely the only relevant one.

Add to plan SKILL.md Sharp Edges (proposed bullet):

> When verifying a spec claim about a reducer's case arms (chip removal triggers, exhaustiveness rails, side-effect emission), `grep -n "case " <reducer-file>` to enumerate ALL arms BEFORE deciding which arm(s) exhibit the claimed behavior. `Read(file, limit=N)` is for *each arm's body* once located, not for *enumeration* — first-N-line views silently undercount when the reducer ships behavior across multiple later case arms. **Why:** PR #3743 plan v1 (#2939) wrongly claimed `tool_use_chip` removal triggers only on `workflow_started`; Kieran plan-review caught that `chat-state-machine.ts:522` ALSO removes via `stream_end`. FR1.3 as written would have green-lit any future regression that broke the missed trigger.

## Key Insight

The "paraphrase-without-verification" rule already covers issue-body claims (2026-04-22 learning) and one's own pattern proposals (2026-05-12 learning, plan-time parsing patterns). This learning extends the class to **plan-time verification of multi-case structures**: a Read that returns plausible-looking evidence is not the same as a grep that enumerates the structure being claimed about.

The asymmetric cost is sharp:
- **Cost of grep-then-Read:** ~5 seconds (one extra grep command).
- **Cost of Read-first-N-only:** in this session, ~15 minutes of plan-review surface (Kieran agent compute + my edit pass to apply the correction). At /work time it would have been worse — RED tests passing vacuously against a missing trigger, then a follow-up PR to backfill the assertion.

Plan-review (DHH + Kieran + Code Simplicity) caught it at the cheapest point past plan-write. Earlier catch (plan Phase 1) would have been cheaper still.

## Session Errors

- **Read-first-100-lines verification misread spec FR1.3 as wrong** — *Recovery:* applied Kieran's P0 #2 correction in plan edit pass; FR1.3 now covers both `stream_end` AND `workflow_started` chip-removal paths. *Prevention:* this learning + proposed plan SKILL.md Sharp Edge.

- **Wrong WS path in plan (`**/api/ws*` instead of `**/ws`)** — *Recovery:* applied Kieran's P0 #1 correction. *Prevention:* Phase 0 verification grep now load-bearing in plan template (this plan has the explicit step).

- **Wrong `tool_use` event shape in plan injection examples (referenced `toolName`/`toolLabel` fields not on the wire)** — *Recovery:* applied Kieran's P0 #3 correction; injection examples now use `{leaderId, label}` only. *Prevention:* same as above — Phase 0 verification of wire-schema (zod-schemas.ts) against plan's example shapes.

All three corrections share the same parent class: I cited file:line evidence without grepping the actual structure being claimed about. The brainstorm-skill learning from earlier this session (`2026-05-13-brainstorm-grep-cited-flag-symbol-against-main-before-spawning-leaders.md`) addresses this at the *brainstorm* layer; this learning addresses it at the *plan* layer.

## Cross-references

- Plan: `knowledge-base/project/plans/2026-05-13-feat-cc-soleur-go-smoke-2939-pr-a-plan.md`
- Spec: `knowledge-base/project/specs/feat-cc-soleur-go-smoke-2939/spec.md`
- Sibling learning (brainstorm layer): `knowledge-base/project/learnings/2026-05-13-brainstorm-grep-cited-flag-symbol-against-main-before-spawning-leaders.md`
- Parent rule class: paraphrase-without-verification (canonical learning: `2026-04-22-ts-sql-normalizer-parity-when-shipping-backfill-migration.md`)
- Kieran plan-review session that caught all 3 errors: PR #3743 plan-review pass, 2026-05-13
- Reducer in question: `apps/web-platform/lib/chat-state-machine.ts:522` (`stream_end` chip removal) + `:716` (`workflow_started` chip removal)
