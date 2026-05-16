---
date: 2026-05-05
category: best-practices
tags: [brand-workshop, brainstorm, ux-design-lead, brand-architect, founder-approval]
related-prs: [3233]
related-issues: [3232, 3234]
---

# Brand-workshop tokens are not founder-approvable without UX mockups

## What happened

While running `/soleur:go` on a request to add a light/dark/system theme toggle for app.soleur.ai, the codebase scan revealed the app is dark-only and the brand guide explicitly forbids using an undefined "Solar Radiance" light palette. The session pivoted into a brand workshop to define the palette first.

The brand-workshop skill (per `plugins/soleur/skills/brainstorm/references/brainstorm-brand-workshop.md`) ran:

1. Worktree + draft PR created
2. Tracking issues filed
3. `brand-architect` agent invoked — produced hex/oklch values, CSS custom-property names, inline WCAG AA contrast verification, and a metaphor extension ("forge at dawn")
4. Brand guide committed and pushed
5. PR marked ready for review
6. Workshop declared "complete" — `Approved for production` was written into the brand guide

The founder reviewed and pushed back: the palette had been "approved" without ever being rendered on a real surface. Hex codes in markdown are not a brand decision — the founder needed to see buttons, cards, inputs, error states applied to the new tokens before signing off.

## Why the existing skill missed this

- `brand-architect` is structurally a writer, not a designer. It outputs markdown. Its WCAG AA verification is mathematical, not perceptual.
- The brand-workshop reference had no step routing visual-direction changes through `ux-design-lead` for actual mockups before commit/PR-ready.
- The completion message confirmed the brand-guide path but said nothing about whether a human had ever seen the palette rendered.
- The session also misframed the founder as "CMO" — the brand-guide.md `owner: CMO` tag is a function role; in a solo founder org, the founder/CEO carries that role and the framing question should reflect that.

## Fix applied

- Added step 4.5 (Visual mockup gate) to `plugins/soleur/skills/brainstorm/references/brainstorm-brand-workshop.md`: when the diff to `## Visual Direction` is non-empty, hand off to `ux-design-lead` to render representative surfaces (button states, card surface, form input, navigation, modal, error state — both palettes side-by-side if dual-mode), then surface the mockups via AskUserQuestion with `Approve / Request changes / Reject`. Only "Approve" continues to commit. Up to 3 iteration loops before forcing a fresh-context resume.
- Updated the completion message template to include `Mockups:` and `Founder approval:` lines so the audit trail makes it explicit that a human reviewed rendered output, not abstract tokens.

## Where this rule lives

- Domain-scoped (brand workshop only) → owning skill reference, not AGENTS.md, per `cq-agents-md-tier-gate`.
- The change is *discoverable* (the commit message and PR will name the founder approval), so a learning file plus skill edit is sufficient — no new AGENTS.md hard rule, per `wg-every-session-error-must-produce-either` discoverability exit.

## Generalization

Beyond the brand workshop specifically: any agent or skill whose output is a *visual* decision (palette, typography, layout, motion, imagery direction) MUST route through a render-and-show step before claiming "approved." The render can be Pencil mockups, Playwright screenshots of an HTML mockup, or a live preview deployment — but it cannot be markdown alone.

## Retroactive remediation

Per `wg-when-fixing-a-workflow-gates-detection` ("retroactively apply the fixed gate to the case that exposed the gap"), PR #3233 must not merge until `ux-design-lead` produces Solar Radiance mockups and the founder explicitly approves them. The `Approved for production` line in `brand-guide.md` is the load-bearing claim; it stays only if a real mockup gate is satisfied.
