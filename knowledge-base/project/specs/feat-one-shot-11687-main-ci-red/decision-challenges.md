# Decision challenges: feat-one-shot-11687-main-ci-red

Headless plan-phase output (2026-10-31). This harness has no subagent spawn mechanism, so
technical rulings carry `pending - assumed:` defaults per the pipeline contract; review-phase
agents resolve them.

## Decision Classes

| Item | Class | Ruling |
|------|-------|--------|
| Relocate all four sub-root exclusion comment blocks (~1.4 KB headroom) vs only the new lb-staging block (~250 B, minimal) | technical | pending - assumed: relocate all four under one new `§push-paths sub-root exclusions` heading — same mechanism, durable headroom |
| Signature 3 direction: extend bash `for _r in` + mkdir + G4GIT fixture vs revert `lb-staging` from python GUARD4_ROOTS | technical | pending - assumed: extend bash side — #11652's commit message records the python addition as deliberate review hardening; bash was the missed side |
| Brand-survival threshold | technical | pending - assumed: `single-user incident` (one unredacted ga-overlay dispatch exposes multiple rotation-requiring infra credentials; matches the epic's own review tier) |
| CPO sign-off + gdpr-gate + scoped advisor + plan-review fan-out | technical | pending - assumed: deferred to review pipeline — no spawn mechanism in this planning harness; `requires_cpo_signoff: true` set in plan frontmatter |
