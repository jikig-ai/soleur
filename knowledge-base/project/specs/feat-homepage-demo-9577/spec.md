---
feature: homepage-demo-9577
lane: cross-domain
brand_survival_threshold: single-user incident
refs: [9577, 9578, 9588, 9620, 9584]
brainstorm: knowledge-base/project/brainstorms/2026-10-06-homepage-fanout-demo-brainstorm.md
status: draft
created: 2026-10-06
---

# Spec: homepage demo of one brief fanning out to departments

## Problem Statement

The homepage asserts "human-in-the-loop" twice (the hero line and the FAQ) and never shows it. Visitors cannot see what the founder still decides. The self-hosted product pauses to ask the user and can stop at gates, but it has no per-department live status display, so any demo is an illustration and must say so.

## Goals

- Show one fictional founder brief fanning out to four departments, with a status line per department as text: two done, one stopped because a check did not pass (what is held back, and that the founder decides), one waiting on the founder.
- Back the "human-in-the-loop" claim without implying outcomes, speed, or a live product surface the visitor cannot get today.
- Keep the demo's states from drifting away from the product's state vocabulary.

## Non-Goals

- No button or CTA inside the section, and no reuse of the hero's `Hero Self-host Click` or `Waitlist Signup` events (the hero CTA test, review 2026-11-03, must stay readable).
- No animation in v1, no video or GIF, no new inline script.
- No hosted UI, pricing, dashboard or web-app wording; no counts, durations or savings.
- No competitor text, status strings, layout, markup, screenshots or name.
- No founder-defined acceptance check (that is #9578).
- No demo-specific Plausible event.

## Functional Requirements

- FR1: A homepage section, after the positioning section and before the quote block, with one H2, a figure with caption, a fictional brief card, and a list of four department rows (legal, marketing, finance, engineering). Wireframe: knowledge-base/product/design/marketing/homepage-fanout-demo-9577.pen.
- FR1a: Approved copy (operator-approved 2026-10-06 with two edits over the drawn wireframe; the `.pen` still shows the old H2 and Legal line, layout is unchanged and does not need a redraw). Label `HOW A BRIEF FANS OUT`. H2 `One brief reaches the departments it concerns. You keep the final say.` Brief card `Fernlight is adding shared reminders. Launch it to current customers as a paid add-on.` Legal, Done: `Draft terms and privacy notice changes ready for your review.` Marketing, Done: `Launch post and customer email drafted.` Finance, Stopped: `Add-on price held back. The margin check did not pass. You decide what happens next.` Engineering, Waiting on you: `Needs your answer: switch reminders on by default for existing accounts, or let each customer opt in?` Link `See every department below`, targeting `#departments` (the "Your AI Organization" section needs that id added). Secondary text uses `--color-text-secondary` (#848484, 4.9:1 or better); the tertiary token (#737373) fails 4.5:1 and must not be used for captions.
- FR2: The frame carries, as visible text: "Illustrative example with sample data. Not a live run or a customer result." and "Soleur pauses for your approval; it does not guarantee any check will pass."
- FR1a/FR2 amendment (CLO review, 2026-10-06; supersedes the quoted wording above where it differs): no real company name in the brief (`A small software company is adding shared reminders to its app. Launch it to current customers as a paid add-on.`); H2 `Example: one brief reaches the departments it concerns, and you keep the final say.`; Legal line `Draft terms and privacy notice changes, for review by you and a qualified lawyer.`; Marketing line `Launch post and customer email drafted for your approval.`; caption `Illustrative example with sample data. Not a live run, a product screenshot or a customer result.` / `Agent output is a draft for you to review and approve. Soleur does not guarantee that any test or review will catch every problem.`; figure name `Illustrative example with sample data: one founder brief and the status each of four departments reports back`.
- FR3: Status is conveyed by text, not colour alone. The stopped row says what is held back and who decides. The waiting row says what it needs answered.
- FR4: One link under the figure to the eight department cards on the same page.
- FR5: The rows come from a committed data file under `plugins/soleur/docs/_data/`.

## Technical Requirements

- TR1: Static HTML and CSS rendered at build time; demo styles live in `style.css`, not the inline critical block; avoid `landing-*` and `section-*` class prefixes for new classes.
- TR2: The critical-CSS coverage check, the screenshot gate (including the 320px overflow pass) and the hosted-claims drift guard pass; no "hosted", "web app", "dashboard", "install", "CLI", "terminal", "plugin" or Claude or Anthropic wording in the section; counts only via `stats`.
- TR3: A bun drift test checks that every status key in the data file exists in the product's state vocabulary, every department is in `agents.js`, and the rendered homepage contains each state and both disclosure lines.
- TR4: Fixtures are fictional: a made-up company and `example.com` addresses.

## Acceptance Criteria

- The CLO has reviewed the final built text, after the wireframe, and recorded a verdict.
- The ship date is recorded as a comment on #9588 and in the 2026-11-03 verdict.
- Coordinate with #9620 before any hosted depiction is considered (none in v1).

## Plan-stage amendments (2026-10-06)

Recorded by `knowledge-base/project/plans/2026-10-06-feat-homepage-fanout-demo-plan.md`, decided by the operator at the plan gate after plan review:

- FR1a copy: **Finance is "Waiting on you"** (`Needs your answer: set the add-on price from the sample cost figures, or hold it until costs are clearer?`) and **Engineering is "Stopped"** (`Reminders change held back. A test did not pass. You decide what happens next.`). Reason: no margin gate exists in the product, and "the margin check" implied a pre-set bar (the founder-defined check of #9578 is unbuilt). The Legal, Marketing, H2, brief and link copy are unchanged.
- FR1a label: `How a brief reaches the departments` ("fans out" implied parallel dispatch).
- FR2: a visible `Illustrative example · sample data` tag at the top of the figure, in addition to the two caption lines.
- Design deviations from the approved wireframe: flat outline chips with state glyphs (Stopped not a solid white fill, Done receding), a gold left border on the two founder-action rows, the connector dropped below 768 px, content-driven wrapping instead of a 320 px breakpoint, no hover or pointer styling.
- TR3: the bun test parses `STATUS_LABELS` keys from `apps/web-platform/lib/types.ts` as text; the Eleventy build checks a local closed constant and throws on bad rows; the validator lives in `plugins/soleur/lib/fanout-validate.js`.
- Wireframe screenshots 13–15 are superseded for the label, the Finance and Engineering rows and the chip and connector treatment.
- Hero-test confound: ship now; the attribution rule is pre-registered on #9588 before merge. The copy upgrade after #9578 ships is #9661.
