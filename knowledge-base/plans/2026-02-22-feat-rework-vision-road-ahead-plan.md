---
title: "feat: Rework Vision Road Ahead"
type: feat
date: 2026-02-22
issue: "#274"
version-bump: PATCH
---

# Rework Vision Road Ahead

## Overview

Rewrite the "Road Ahead" section on the Vision page to present Soleur's long-term Master Plan as three escalating milestones -- from automating software companies, to hardware companies with robot integration, to multiplanetary companies with spacefleet integration.

## Problem Statement / Motivation

The current "Road Ahead" section uses generic phase names ("The Toy", "The Business", "The Empire") that describe an individual founder's journey from micro-SaaS to autonomous scaling. The new milestones reframe the vision at a civilization-scale: Soleur's ambition is not just to help one founder, but to progressively automate entire categories of companies, culminating in multiplanetary operations inspired by Iain M. Banks' "The Culture."

## Proposed Solution

Rename the section from "The Road Ahead" to "Master Plan" and replace the 3 existing cards with the new milestones.

### Changes Required

**Primary: `plugins/soleur/docs/pages/vision.njk`** (lines 119-148)

1. Change `<h2>` from "The Road Ahead" to "Master Plan"
2. Replace the 3 `<article class="component-card">` entries:

| Current | New |
|---------|-----|
| Phase 1 / The Toy / "Build a single-agent Micro-SaaS." | Milestone 1 / Automate Software Companies / Description of full software company automation |
| Phase 2 / The Business / "Automate the Lean Startup loop..." | Milestone 2 / Automate Hardware Companies / Description of hardware + robotics integration |
| Phase 3 / The Empire / "Autonomous scaling..." | Milestone 3 / Multiplanetary Companies / Description of spacefleet integration inspired by The Culture |

### Other Sections/Pages Assessment

| Page/Section | Update Needed? | Rationale |
|-------------|---------------|-----------|
| Vision: Company-as-a-Service | No | Still accurate -- describes Soleur's core thesis |
| Vision: Core Value Proposition | No | "Billion-Dollar Solopreneur" still fits the new milestones |
| Vision: Model-Agnostic Architecture | No | Technical architecture is orthogonal to the milestone vision |
| Vision: Strategic Architecture | No | Coordination engine and dogfooding apply at all scales |
| Vision: Revenue Philosophy | No | Revenue model is independent of the milestone framing |
| Landing page (index.njk) | No | No milestone/roadmap references; "billion-dollar" quote still valid |
| Community page | No | No vision references |
| Getting Started page | No | No vision references |

**Conclusion: Only the "Road Ahead" section in vision.njk needs updating.**

## Acceptance Criteria

- [ ] Section title changed from "The Road Ahead" to "Master Plan"
- [ ] Card categories changed from "Phase N" to "Milestone N"
- [ ] Card 1: "Automate Software Companies" with description covering full software company automation
- [ ] Card 2: "Automate Hardware Companies" with description covering robotics integration
- [ ] Card 3: "Multiplanetary Companies" with description covering spacefleet integration and The Culture reference
- [ ] Card dot colors maintain visual variety (use existing CSS variables)
- [ ] No other sections or pages modified
- [ ] Eleventy build passes (`bun run build` or equivalent)
- [ ] Visual verification via screenshot at desktop and mobile widths

## Test Scenarios

- Given the vision page loads, when I scroll to the Master Plan section, then I see "Master Plan" as the section title (not "The Road Ahead")
- Given the Master Plan section is visible, when I read the 3 cards, then they display Milestone 1/2/3 with the correct titles and descriptions
- Given the page is viewed on mobile (< 768px), when the catalog-grid stacks to single column, then all 3 milestone cards display correctly
- Given the Eleventy build runs, when all templates compile, then zero build errors occur

## MVP

### plugins/soleur/docs/pages/vision.njk (lines 119-148)

```html
<section class="category-section">
  <div class="category-header">
    <h2 class="category-title">Master Plan</h2>
  </div>
  <div class="catalog-grid">
    <article class="component-card">
      <div class="card-header">
        <span class="card-dot" style="background: var(--cat-tools)"></span>
        <span class="card-category">Milestone 1</span>
      </div>
      <h3 class="card-title">Automate Software Companies</h3>
      <p class="card-description">Give one founder the leverage of an entire software organization. Engineering, marketing, sales, legal, finance, operations -- every department running autonomously on command.</p>
    </article>
    <article class="component-card">
      <div class="card-header">
        <span class="card-dot" style="background: var(--cat-workflow)"></span>
        <span class="card-category">Milestone 2</span>
      </div>
      <h3 class="card-title">Automate Hardware Companies</h3>
      <p class="card-description">Extend orchestration beyond code into the physical world. Integrate control of robots, manufacturing lines, and supply chains -- bridging the gap between digital intelligence and physical execution.</p>
    </article>
    <article class="component-card">
      <div class="card-header">
        <span class="card-dot" style="background: var(--accent)"></span>
        <span class="card-category">Milestone 3</span>
      </div>
      <h3 class="card-title">Multiplanetary Companies</h3>
      <p class="card-description">Integrate spacefleets and off-world operations into the orchestration engine. Autonomous companies that span planets -- inspired by the Minds of Iain M. Banks' Culture series.</p>
    </article>
  </div>
</section>
```

## References

- Issue: #274
- File: `plugins/soleur/docs/pages/vision.njk:119-148`
- CSS classes: `category-section`, `catalog-grid`, `component-card` (all existing in `docs/css/style.css`)
