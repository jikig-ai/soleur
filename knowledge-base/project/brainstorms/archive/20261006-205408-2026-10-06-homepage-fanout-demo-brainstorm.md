# Homepage demo: one brief fanning out to departments (#9577)

Date: 2026-10-06. Lane: cross-domain. Brand-survival threshold: single-user incident. Issue: #9577 (OPEN, no comments). Sibling #9578 (founder-defined acceptance check) is brainstormed separately.

## What We're Building

One new proof section on the homepage (`plugins/soleur/docs/index.njk`): a labelled, static illustration of one fictional founder brief fanning out to four departments, with a status line per department as text. Two departments are done, one has stopped because a check did not pass (it says what is held back and that the founder decides), and one is waiting on the founder. It exists to show the "human-in-the-loop" claim, which today is asserted twice (the hero line and the FAQ) and never shown.

## Why This Approach

Six read-only reports (CPO, CLO, CTO, CMO, repo research, learnings research) converged on a small honest block over a bigger one.

The verified gap that shapes everything: the self-hosted product pauses to ask the user and can stop at gates, but it has no per-department live status display. The status words a visitor could see map to the hosted Command Center (`active`, `waiting_for_user`, `completed`, `failed` in `apps/web-platform/lib/types.ts`), which is waitlist-only after #9584. Nothing in the product literally means "the check did not pass"; the nearest is `failed`. So the demo can only be an illustration, and it must say so on the frame.

Rejected: a real captured self-hosted run (sequential phases in a terminal, developer register that the hero-copy revert trigger forbids) and "do not build until the work-visualization issue #2004 exists" (honest, but a much larger build and the claim stays asserted).

## Key Decisions

| Decision | Choice | Source |
|---|---|---|
| What it depicts | Labelled illustration, 4 departments (legal, marketing, finance, engineering): done, done, stopped, waiting on you | Operator, after 4 leaders converged |
| Timing | Ship now, with NO button of its own and no reuse of the hero events; record the ship date on #9588 and in the 2026-11-03 verdict | Operator, on the CMO's confound finding |
| Placement | After the positioning section, before the quote block (below the hero and stats, so it is a proof section and not a second hero) | CMO, over the CPO's "between hero and stats" |
| Build | Static HTML and CSS, rendered at build time, real text in a figure with a caption and a list. No animation in v1 (YAGNI, reversible); a reduced-motion-gated stagger is a later option | CTO |
| Source of the states | A data file for the demo's rows plus a bun drift test that checks every status key against the product's state vocabulary and every department against `agents.js` | CTO |
| Frame disclosure | "Illustrative example with sample data. Not a live run or a customer result." and "Soleur pauses for your approval; it does not guarantee any check will pass." on the frame | CLO |
| Fixtures | Fictional company, `example.com` addresses, no vendor or Anthropic or Claude marks, no durations, counts or outcome claims, no hosted, dashboard, web-app, install, CLI or plugin wording | CLO, CMO, CTO |
| Competitor reference | Ideas only: no Sutra text, status strings, layout, markup, screenshots or name | CLO |
| Visual design | Wireframes approved 2026-10-06 (desktop 1440, mobile 390, 320 wrap): `knowledge-base/product/design/marketing/homepage-fanout-demo-9577.pen`, screenshots 13 to 16. Two copy edits approved over the drawn text: the H2 says "the departments it concerns" (four shown, eight exist) and the Legal row says drafts are ready for review, not that legal documents were updated | Operator |
| Metric | Not a conversion claim. Success is the section existing without moving the hero test; a demo-specific view event is deliberately not added (it would need a login-gated Plausible goal) | Operator |

Productize candidate: none.

## User-Brand Impact

- **Artifact:** the new homepage proof section and its data file.
- **Vector:** a staged demo that reads as live product behaviour overstates what visitors get (a false public claim), and hosted-looking states would widen the #9620 mismatch.
- **Threshold:** single-user incident.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Product

**Summary:** Build now as a small honest proof surface for the self-hosting developer; show 3 to 4 departments; show no hosted UI, pricing or invented metrics. Self-hosted skills do pause on questions and stop at gates; per-department live status lines are not a Soleur surface.

### Legal

**Summary:** Go with conditions: label the frame as illustrative, no guarantee line, fictional fixtures, no vendor marks, keep any hosted depiction at "coming soon", coordinate with #9620, and a CLO review of the final built text after the wireframe.

### Engineering

**Summary:** Static HTML and CSS below the fold; put demo styles in `style.css` only (not the inline critical block) and avoid `landing-*` and `section-*` class prefixes; the 320px overflow gate and the hosted-claims guard apply; add a data file and a drift test. No ADR needed.

### Marketing

**Summary:** Proof section, one H2, no button inside; adding it before the 2026-11-03 verdict is another bundled change to the hero CTA test, so record the ship date; four departments; real HTML text for AEO; no new JSON-LD.

## Capability Gaps

- No Soleur surface shows per-department live status for self-hosted users (evidence: repo research checked `apps/web-platform/lib/types.ts`, `apps/web-platform/server/agent-engine-dispatch.ts`, `plugins/soleur/skills/*/SKILL.md`; the work-visualization issue #2004 is open and unbuilt). The demo is therefore labelled illustrative rather than backed.
- No product state literally means "a check did not pass"; the nearest is `failed`. The line is illustrative and mapped to `failed` in the drift test only at the key level.

## Reconciliation Notes

- The CPO said "waiting on you" is verifiable for self-hosted (skills pause on a question); the repo researcher said it is a hosted-only label. Both hold: the pause exists, the status label does not. The demo word "Waiting on you" is therefore illustrative wording, not a quoted product string.
- The repo researcher's report mislabelled the hosted app's engine statuses as the self-hosted pipeline and described drift guards that do not match the test file; its department-list and state-vocabulary findings were cross-checked against the CTO's.

## Open Questions

- Exact copy for the brief and the four rows (decided at the plan stage with the wireframe and the CLO's review of built text).
- Whether the demo's status keys should be checked against `lib/types.ts` by parsing it or against a small committed vocabulary file (plan stage).
- (out of scope) A real per-department status display for self-hosted users (#2004).
- (out of scope) The #9620 decision on hosted availability.
