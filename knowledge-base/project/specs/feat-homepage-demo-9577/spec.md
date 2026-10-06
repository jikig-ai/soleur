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
