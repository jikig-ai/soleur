# Decision challenges — feat-one-shot-9579-9580-homepage-copy-trust-fixes

Persisted by `soleur:plan` (headless). Each row is a taste or user-challenge decision where the plan took the operator's stated direction as the default and a reviewer proposed another. `soleur:ship` renders these into the PR body.

## 2026-10-06 — D1: exact computed counts versus a computed soft floor (issue #9579 item 4)

- **Operator direction (default, implemented):** replace the hardcoded "60+" in homepage prose with the computed count (`stats.js` gives 67 agents, 103 skills).
- **Challenge (CMO):** brand-guide `Numbers: soft floors in prose` and drift-guard Test 16 (#3165, closed P1) say prose uses soft floors and the exact count lives in the stat strip. A small template filter that floors to the nearest 10 ("60+" agents, "100+" skills) is computed, cannot drift, fixes the skills understatement, keeps Test 16 and the social-channel "60+" claims unchanged, and needs no brand-guide carve-out. Cost of the alternative: the homepage would keep reading "60+ AI agents", so item 4's visible intent (the exact number) is not delivered.
- **Why the default stands:** the issue names the exact figure; the plan limits the blast radius (homepage plus an opt-in `summaryCounts` flag; pricing and about stay on the floor) and re-pins Test 16 with Guard 2.
- **Reversal cost:** low. Swap the interpolation for the filter in four places and revert the Test 16 re-pin.

## 2026-10-06 — D2: self-host primary CTA versus brand-guide line 491 (issue #9579 item 3)

- **Operator direction (default, implemented):** make self-host install the primary hero CTA, keep the waitlist for hosted.
- **Challenge (CPO, CMO):** the 2026-03-22 validation rule says not to lead with CLI installation; the roadmap's alpha cohort needs at least 3 of 10 non-Claude-Code founders and today has 0, so a self-host-primary hero may skew recruitment toward Claude Code users. The planned before/after read is confounded (traffic mix, a bundled change set) and install clicks are not installs.
- **Why the default stands:** the rule's premise (hosted launching) has not happened, hosted is waitlist-only, and the issue frames this as a test. Mitigations in the plan: waitlist stays visible and labelled directly below the CTA, new event only (existing `Waitlist Signup` name unchanged for baseline comparability), a pre-registered decision rule and a dated, test-scoped brand-guide carve-out with a revert trigger.
- **Reversal cost:** low; one CTA block.

## 2026-10-06 — D3: hero compare link target (issue #9579 item 6)

- **Operator direction:** "Link the hero to `/compare/`".
- **Finding:** no `/compare/` route exists. The plan links `/compare/soleur-vs-cursor/` with neutral text and files a follow-up for a hub, a CTA block on compare pages and a screenshot-gate route.
- **Alternative:** build a small `/compare/` hub index now. Rejected for this PR as new-page scope that also triggers wireframe and SEO work.

## 2026-10-06 — plan-review taste splits (kept as planned)

- **Footer non-affiliation line.** Simplicity reviewer: cut (duplicates the quote-block line). CLO: keep, because the Anthropic naming rule is site-wide while the quote is the weakest spot. Kept; legal advice outranks simplicity, cost is one line in `base.njk`.
- **Plausible baseline pull before merge.** Simplicity and DHH: cut (history is retained; pull at evaluation time). CPO and CMO: pull before merge and fix a start date. Kept (one API call); the change date goes into the brand-guide note either way.
- **Guard matrices.** DHH and simplicity: drop mutation matrices, keep one assertion per property. The Guard Contract gate (plan Phase 2.12, lint-guard-contract.py) requires at least 3 rows per guard, so the matrices were trimmed to 6 to 8 rows each rather than removed.
- **Six deferral issues.** DHH: file one. The deferral rule asks for a tracking issue per cut item and they are already filed (#9588 to #9593).
- **CTA-test depth.** DHH: skip baseline, decision rule and evaluation issue (revert if it looks bad). CPO: a pre-registered decision rule is required. Kept.
- **Hero reorder demotes the waitlist button (CPO scope-creep flag).** Accepted with the mitigations in D2.
