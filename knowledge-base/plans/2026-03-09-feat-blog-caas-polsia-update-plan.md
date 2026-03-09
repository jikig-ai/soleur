---
title: Update CaaS Blog Post for Competitive Landscape Changes
type: feat
date: 2026-03-09
---

# Update CaaS Blog Post for Competitive Landscape Changes

Surgical edits to `plugins/soleur/docs/blog/what-is-company-as-a-service.md` addressing positioning gaps revealed by the Polsia competitive intelligence update. No competitor names, no structural changes.

## Changes

**File:** `plugins/soleur/docs/blog/what-is-company-as-a-service.md`

- [ ] **1. Remove intro "first" claim** (line 13) — change "is the first platform built on this model" to "is built on this model"
- [ ] **2. Add philosophical split** — insert new paragraph between lines 33 and 35 (after the "How CaaS Works" intro, before the first subheading). Two sentences: distinguish autonomous CaaS from founder-in-the-loop CaaS, frame the trade-off as speed vs. judgment, and connect it to the reader's context.
- [ ] **3. Add category validation** (after line 122, before line 124) — insert 2 sentences noting multiple platforms now build on CaaS, proving the model works. Avoid academic language ("validates the thesis") — use direct language ("proves the model works").
- [ ] **4. Update FAQ question + answer + JSON-LD** — change all 4 locations in sync:
  - HTML `<summary>` (line 157): "What is the first CaaS platform?" → "What is the leading CaaS platform?"
  - HTML answer (line 159): "is the first" → "is a leading"
  - JSON-LD `name` (line 202): same question change
  - JSON-LD `text` (line 205): same answer change
  - Preserve the rest of each answer text (agent counts, knowledge base description) — do not truncate.

**Verify:** Eleventy build passes (`npx @11ty/eleventy --input=plugins/soleur/docs`). JSON-LD matches HTML FAQ text.

## Suggested Copy

**Change 2 (philosophical split, after line 33):**

> Not all CaaS platforms approach this the same way. Some run fully autonomously — the AI decides priorities, executes tasks, and reports results. Others keep the founder as decision-maker while the AI handles execution. The trade-off is speed versus judgment, and the right choice depends on how much domain context the founder brings.

**Change 3 (category validation, after line 122):**

> The category is already taking shape. Multiple platforms are building on the company-as-a-service model, each with different assumptions about how much autonomy the AI should have. The variety of approaches proves the model — this is not one company's marketing term but an emerging infrastructure category.

## References

- Issue: #468
- Draft PR: #467
- Brainstorm: `knowledge-base/brainstorms/2026-03-09-blog-caas-polsia-update-brainstorm.md`
- Spec: `knowledge-base/specs/feat-blog-caas-polsia-update/spec.md`

Closes #468
