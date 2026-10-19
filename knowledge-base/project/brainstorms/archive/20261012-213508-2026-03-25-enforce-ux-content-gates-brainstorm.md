# Brainstorm: Enforce UX Design and Content Review Gates

**Date:** 2026-03-25
**Status:** Complete
**Issue:** #1137
**Branch:** enforce-ux-content-gates

## What We're Building

Three changes to the plan and work skills that close the gap where domain leader specialist recommendations (wireframes, copywriter review) are captured as text but never enforced as prerequisites.

**Origin case:** Pricing page v2 (#656) — CMO recommended conversion-optimizer and copywriter, CPO recommended UX review, but implementation went straight to coding HTML/CSS from brainstorm decisions. The Product/UX Gate was marked "reviewed (carried from brainstorm)" but brainstorm validated the *idea*, not the *page design*.

## Why This Approach

Inline gate enhancement (Approach A) was chosen over a separate gate registry file (Approach B) or brainstorm-level enforcement (Approach C) because:

- Extends existing plan/work SKILL.md gate patterns rather than introducing new file types
- Keeps single source of truth in the plan file
- Respects brainstorm/plan separation (brainstorm = WHAT, plan = HOW)

## Key Decisions

### 1. Content Review Gate Trigger: Dual-Signal

The Content Review gate fires when **both** signals align:

- **Auto-detect**: Plan skill classifies the page as "copy-heavy" (landing pages, pricing pages, onboarding flows with persuasive/explanatory copy — NOT settings pages with field labels)
- **Domain leader confirmation**: A domain leader (CMO, CRO) explicitly recommended copywriter or content specialist in their assessment

Auto-detect proposes, domain leader confirms. This prevents false triggers on low-copy pages and ensures the gate only fires when a domain expert agrees.

### 2. Specialist Status Tracking: Structured Fields

Plan files track specialist status with structured, machine-parseable fields:

```
Copywriter: ran | skipped(reason) | pending
UX Design Lead: ran | skipped(reason) | pending
Conversion Optimizer: ran | skipped(reason) | pending
```

- `ran` — specialist completed review
- `skipped(reason)` — user explicitly declined with justification
- `pending` — recommended but not yet addressed

### 3. UX Gate Decline Path: Skip With Justification

The tightened BLOCKING UX gate allows explicit skip but requires a reason (e.g., "minor CSS tweak on existing layout", "iterating on validated wireframe"). This prevents routing around the gate while allowing legitimate fast paths.

Brainstorm carry-forward is **not sufficient** for new pages. It remains valid for non-UX decisions (brand positioning, legal review, architecture).

### 4. Work Skill Enforcement: Hard Block

Work skill hard-blocks implementation when any recommended specialist has `pending` status. User must either run the specialist or explicitly decline (which updates status to `skipped(reason)`) before coding starts. This is stronger than the issue's original "warning" proposal — ensures the gap is always addressed.

### 5. Implementation Scope

Three files, three changes:

| Component | File | Change |
|-----------|------|--------|
| Tighten BLOCKING UX gate | `plugins/soleur/skills/plan/SKILL.md` | Brainstorm carry-forward no longer satisfies gate for new pages; must produce wireframes or explicitly skip with reason |
| Add Content Review gate | `plugins/soleur/skills/plan/SKILL.md` | New subsection under Domain Review with dual-signal trigger; writes structured specialist status fields |
| Pre-implementation specialist block | `plugins/soleur/skills/work/SKILL.md` | Hard block on `pending` specialist status; prompt to run or decline before proceeding |

## Open Questions

1. **Retroactive application**: Should the work skill check catch plans created before this fix, or only new plans? Recommendation: check all plans — old plans without the status field are treated as pre-fix and get a softer warning rather than a hard block.
2. **Pencil MCP availability**: When wireframes are recommended but Pencil MCP is unavailable, should the gate accept a text-based wireframe description or require the user to install Pencil? Recommendation: accept any wireframe artifact (text-based, Pencil, external tool) — the gate checks for design intent, not tool choice.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Product (CPO)

**Summary:** Well-scoped process fix. Key concerns: Content Review trigger must be concrete (not subjective "copy-heavy"), decline path must exist to prevent routing around gates, work skill warning is appropriate but user chose hard block. Recommends resolving trigger heuristic and "unresolved" definition before planning. No milestone assigned — treat as cross-cutting infrastructure.

### Engineering (CTO)

**Summary:** Changes target two SKILL.md files with well-defined gate patterns. Low architectural risk. Main concern: structured status fields must be parseable by the work skill's Phase 0.5 check without fragile regex. Recommend a consistent format that grep can match.
