# Tasks — `/vision/` voice rewrite (#3993)

Plan: `knowledge-base/project/plans/2026-06-01-mktg-vision-rewrite-plan.md`

- [x] Read vision.njk, brand-guide §Don't, audit §1 for exact reframings
- [x] Confirm freshness block (#4754) = `{% include "page-freshness.njk" %}` + frontmatter — preserve untouched
- [x] Confirm FAQ answers + FAQPage JSON-LD contain none of the four codenames (FAQ parity unaffected)
- [x] Rewrite "vessel" sentence (audit R1 three-sentence rewrite)
- [x] Rewrite "Swarm of Agents" → "agents across every department, working in parallel"
- [x] Rewrite "The Global Brain" card → audit R2 crisp parallel copy
- [x] Rewrite "The Decision Ledger" card → "a durable record of the decisions your agents make"
- [x] Rewrite "The Coordination Engine" callout (same inside-baseball pattern) → plain
- [x] Demote lowercase "swarm(s)" jargon → "agent teams"
- [x] Extend seo-aeo-drift-guard.test.ts: codename-absence guard + freshness-still-present guard
- [x] Build: `npx @11ty/eleventy --output=/tmp/site-vision` exit 0
- [x] grep -c codenames in built vision/index.html → 0
- [x] validate-seo.sh exit 0
- [x] bun test full suite green
- [x] CodeQL self-check grep clean
- [x] Commit (conventional, no Closes #N)
