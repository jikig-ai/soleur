# Tasks: founder acceptance record follow-ups

Plan: knowledge-base/project/plans/2026-11-08-feat-founder-acceptance-record-followups-plan.md
Rulings of record: decision-challenges.md; CLO wording: clo-wording-rulings.md. Tests first in every phase. Never change founder-acceptance-record.md bytes (sha256 10d283e0...a287).

## Phase 0 Pre-flight
- 0.1 Fetch origin/main; confirm migration 186 is free
- 0.2 Record the text sha256 baseline
- 0.3 Re-run the code-review overlap query on the final file list
- 0.4 Measure (or state unmeasured) the live code lifetime

## Phase 1 Published trio (#12365)
- 1.1 Apply CLO block R, other edits, falsehood fixes, Amended entry and Superseded marker to docs/legal/{privacy-policy,gdpr-policy,data-protection-disclosure}.md
- 1.2 Mirror into plugins/soleur/docs/pages/legal/*.md (no heading change, Last Updated untouched)
- 1.3 Recompute the three LEGAL_DOC_SHAS entries
- 1.4 Add published-retention.test.ts; run legal-doc-consistency, legal-doc-shas-guard, check-tc-document-sha.sh, lint-legal-mirror-drift-baseline.sh, markdown lint, test-all.sh
- 1.5 Append CLO ruling addendum (L7 superseded); narrow #12365 (stays open)

## Phase 2 Deck wording and tripwire (#12366)
- 2.1 legal-copy.test.ts first (pins, drift assertions)
- 2.2 codeBody and wrong_code ("about 10 minutes"); terms kind wording
- 2.3 needsBaseGuard tripwire in registry-pins.test.ts + texts/README.md sentence
- 2.4 Comment on #12366 (items 1, 2 done; item 3 tripwire)

## Phase 3 Counts check (#12429)
- 3.1 Migration 186 + down + verify; static test; tenant-isolation row
- 3.2 service.ts hashCounts parser; ops.ts STORE_FAILED_STAGES gains counts
- 3.3 counts route + route test; census unchanged
- 3.4 scripts/legal-acceptance-counts.sh + test (key validation, hardcoded host, jq -e, status line)
- 3.5 Runbook, CLO L8 marker, ADR-319 amendment, C4 text, routes.ts comment, PA-40 addendum

## Phase 4 Inbox entry
- 4.1 Tests first (inbox-rows, severity, surface, badge, bulk handler, tools, no-service-client, route)
- 4.2 Evaluate the fallback trigger (end of 4.1)
- 4.3 ux-design-lead: variance frame in approval-request.pen (AC16)
- 4.4 inbox-rows.ts (user-context client, founder_id and key filters; accepted-row fixture), union widening sweep (sortTime ternary; locate keyOf), legal-inbox-row.tsx, badge switch, wire key regex
- 4.5 SWR refresh, state transitions, keyboard no-op

## Phase 5 CPO sign-off (after Phase 4)
- 5.1 CPO reviews the variance frame; rules on answered-row decay
- 5.2 Set signOff.cpo; PROVISIONAL stays true; reword header/test titles; FORBIDDEN_CLAIMS assertion

## Phase 6 parked-hold (#12396)
- 6.1 scripts/ci-parked-hold.test.sh first
- 6.2 scripts/ci-parked-hold.sh (live read, retry, fail closed, mg_arm semantics)
- 6.3 secret-scan.yml member steps (step-level event condition, env-hoisted inputs, selftest without GH_TOKEN, header comment), aggregate lines, CODEOWNERS rows (advisory caveat)
- 6.4 required-checks.txt comments; bot-PR sweep
- 6.5 Reword drain-prs SKILL.md and hook header; delete the follow-through probe after rg; ADR-032 amendment
- 6.6 Hook-cost measurement (1/10/100 statements)

## Phase 7 Records and release
- 7.1 Archive plan and spec in the PR
- 7.2 PR body (Closes #12396, #12429; Ref #12365, #12366, #12197, #12011; deviations)
- 7.2a Before merge: re-read the `approval-queue` flag read-only (flag-list skill); if it changed from ON, STOP and send the published sentence "As of November 9, 2026 ... switched on in production for every workspace" to the CLO for re-ruling (plan R12); record the read time in the PR body. The operator decision (leave on or turn off) stays pending and is not made here.
- 7.3 Merge queue after green CI; /health sha after each deploy
- 7.4 Post-merge measurements; comments on #12197 (measured / not measured): verify read once pre-merge as baseline; /health sha; counts helper (STOP on total=0: published statement false, escalate to the CLO); verify read; Inbox; parked-hold; published pages after deploy-docs (new phrase at least 1, old phrase 0); counts-route 401 curl; anon-denial POST to the Supabase rpc endpoint with the public anon key (403 or 401, never 200; 404 is inconclusive)
- 7.5 Roadmap row and milestone for the Inbox entry
