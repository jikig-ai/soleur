# Tasks: founder approval cards, PR-C (#12011)

Plan: `knowledge-base/project/plans/archive/20261104-000420-2026-11-03-feat-founder-approval-cards-plan.md` (PR-C section, AC9 to AC14, AC19). PR-B (#12069) is merged and live. PR-D is not started.

Scope: web screens and the in-place email-code check, behind `approval-queue`. No migration, no change to `dsar-export-allowlist.ts`.

## Server (workstream A)

- [ ] A1 Failing tests first: `service.test.ts`, `routes.test.ts`, texts-in-image test (`registry-embedding.test.ts`)
- [ ] A2 Texts reach the production image (6.7); test the deployed path before any card exists
- [ ] A3 `server/legal-acceptance/service.ts` and `reauth.ts`: issue, claim, mark, record; session id as the SQL reads it (6.5, 6.8, 6.9)
- [ ] A4 Reauth route (send, verify): same response for known and unknown address (6.6); per-user attempt ceiling (6.8)
- [ ] A5 Decide route: intent for every choice, never for a runtime token; typed outcomes (6.5, 6.9)
- [ ] A6 Sentry ops events (`op=accepted`, `decide_rejected`, `reauth_failed`, `row_without_event`)

## UI (workstream B)

- [ ] B1 Failing tests first: `card.test.tsx`, copy test (forbidden wording), state derivation test
- [ ] B2 `lib/legal-acceptance-copy.ts` (PROVISIONAL, CLO gate) with the (c) and (c-2) notices word for word, undo of a Decline (6.10)
- [ ] B3 State derivation in `lib/approval-card-state.ts`: pending, accepted, declined, changes requested, replaced, expired
- [ ] B4 `legal-acceptance-card.tsx`, `legal-reauth-dialog.tsx`, page `approvals/legal/[key]`, index page

## Infra and records (workstream C)

- [ ] C1 Sentry issue alert in `apps/web-platform/infra/sentry` (6.4) with its test
- [ ] C2 ADR-319 amendment: session id derivation, texts in image, undo of Decline, retention/redaction left to counsel (6.9, 6.10)
- [ ] C3 Legal records: LIA, attestation and register note the web screen and the notices; compliance-posture row

## Gate and ship

- [ ] G1 Affected-test gate, markdown-lint sweep, repo ratchets
- [ ] G2 Review (full coverage), compound, ship with `Ref #12011`
