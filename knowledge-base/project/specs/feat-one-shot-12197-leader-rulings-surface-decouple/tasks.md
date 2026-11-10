# Tasks: leader rulings of 2026-11-10 for the founder acceptance record (#12197)

Plan: `knowledge-base/project/plans/2026-11-10-feat-leader-rulings-legal-surface-decouple-plan.md`. Rulings: `decision-challenges.md` in this directory. One PR (draft #12567), one commit per change.

## Phase 1: Setup

- [x] 1.1 Decision record written at plan time (`decision-challenges.md`, rows R1 to R11, F1 to F3, W1 to W3, L1, L2, K1 to K3, PR1 to PR7, O1 to O5) and `clo-register-markers.md`
- [x] 1.2 `git fetch`; re-read ADR-032, ADR-319 and the compliance-posture approval-queue row on the current merge-base before appending

## Phase 2: Core Implementation

- [x] 2.1 Change 1: legal surface gates on `LEGAL_ACCEPTANCE_FOUNDER_ID` only
  - [x] 2.1.1 RED: `surface.test.ts`, `page.test.tsx`, `routes.test.ts` (plan 1.1 to 1.3)
  - [x] 2.1.2 GREEN: `surface.ts` per CTO F1 (plan 1.5)
  - [x] 2.1.3 Comments in the two legal pages, `inbox-rows.ts`, `app/api/inbox/route.ts`, the decide and reauth routes, `reauth.ts`, `legal-acceptance-card.tsx`, the README's other flag lines, the `surface.test.ts` header and `test/feature-map.md` (plan 1.6); `inbox-rows.test.ts` and `inbox-route.test.ts` are not edited (plan 1.4); AC18 grep returns nothing
  - [x] 2.1.4 `server/legal-acceptance/README.md`, runbook and the ADR-319 amendment with CTO K1 to K3 sentences (plan 1.7, 1.7b, 1.8)
  - [x] 2.1.5 `model.c4` description strings; re-render `model.likec4.json` with `render-c4-model.sh` (plan 1.9)
- [x] 2.2 Change 2: `PUSH_DISCLOSURE` and corrected `GH_DISCLOSURE`
  - [x] 2.2.1 RED: `test/web-egress-toggle.test.tsx` literals and placement assertions (plan 2.1)
  - [x] 2.2.2 GREEN: `lib/web-egress-disclosure.ts`, `web-egress-toggle.tsx`, `scope-grants/page.tsx`, one paragraph per piece (plan 2.2)
  - [x] 2.2.3 Sweep: "push to git remotes" only in `lib/web-egress-disclosure.ts` (plan 2.3)
- [x] 2.3 Change 3: one dated sentence in ADR-032's 2026-11-08 amendment (plan Phase 3)
- [x] 2.4 Change 4: CLO audit record and posture cell append (plan 4.1, 4.2); CLO register markers M1 to M4c (plan 4.3)
- [x] 2.5 Change 5: counsel questionnaire, byte-identical to the CLO draft, `status: draft` (plan Phase 5)
- [x] 2.6 Change 6: frame `j89zs` `"y": 11500` to `"y": 12300` (plan Phase 6)

## Phase 3: Testing

- [x] 3.1 e2e: second mock founder user, `founder.json`, `e2e-auth` env (`LEGAL_ACCEPTANCE_FOUNDER_ID`, `FLAG_APPROVAL_QUEUE: "0"`, `FLAGSMITH_ENVIRONMENT_KEY: ""`) (plan 7.1 to 7.3)
- [x] 3.2 e2e spec `nav-states-inbox-legal.e2e.ts` with negative control and two screenshots (plan 7.4)
- [x] 3.3 Run the spec locally; commit the screenshots as frame 23 evidence (plan 7.5)
- [ ] 3.4 Verification before ship: tsc, vitest file list, hard-constraint checks (plan Phase 8)
- [x] 3.4.1 C4 tests and local `c4-model-freshness.test.sh` (plan 1.9)
- [x] 3.4.2 `lint-legal-registers.sh`, `lint-questionnaire-identity.sh --all`, `technical-ruling-gate.sh --branch`, markdownlint
- [ ] 3.5 Phone-width QA (390×844) of the ON block, dialog and callout at review
- [ ] 3.6 Archive plan and spec in the PR; merge queue after green CI; post-deploy `build_sha` check and read-only Sentry check
