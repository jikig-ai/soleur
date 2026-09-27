# Tasks: Start a new CRO chat to enter a CRM lead

Derived from `knowledge-base/project/plans/2026-09-27-feat-crm-new-lead-chat-plan.md`.

## Phase 1: Setup

- [ ] 1.1 Add failing tests for the New lead href on a populated board and on the empty board (`apps/web-platform/test/crm/crm-surface.test.tsx`)
- [ ] 1.2 Add a failing context-validation test for `{ type: "crm-lead" }` with no path
- [ ] 1.3 Add `apps/web-platform/test/server/crm-lead-directive.test.ts` (field set, no BANT/MEDDIC/SPICED/email, stage stays new, SQL column anchor)
- [ ] 1.4 Add a failing test that crm-lead dispatch registers the seven `crm_*` tools and a normal dispatch does not
- [ ] 1.5 Add a failing test that `context_path` `crm-lead/<id>.mode` rebuilds type `crm-lead` and skips the KB resolver

## Phase 2: Core Implementation

- [ ] 2.1 Export `CRM_CONTACT_UPSERT_FIELDS` from `server/crm/crm-tools.ts` and build the upsert schema from it
- [ ] 2.2 Add `server/crm-lead-directive.ts` (`CRM_LEAD_DIRECTIVE`)
- [ ] 2.3 Allow `crm-lead` as a mode-flag context type in `server/context-validation.ts`
- [ ] 2.4 Stamp `context_path` `crm-lead/<id>.mode` on create and rehydrate it on later turns in `server/ws-handler.ts`
- [ ] 2.5 Replace the router baseline when `crmLead` is set in `buildSoleurGoSystemPrompt`
- [ ] 2.6 Register `buildCrmTools` only when `crmLead` is set, and set assistant message `leader_id` to `cro` at that persist site only (`server/cc-dispatcher.ts`)
- [ ] 2.7 Add the New lead link to the CRM header and empty state (`components/crm/crm-surface.tsx`)
- [ ] 2.8 Map `mode=crm-lead` to `{ type: "crm-lead" }` on the chat page without a KB fetch
- [ ] 2.9 Amend ADR-102 with the Concierge Query writer note. Do not add an ADR ordinal or edit `.c4`

## Phase 3: Testing

- [ ] 3.1 Re-run the Phase 1 tests and confirm they pass
- [ ] 3.2 Confirm a normal Concierge tool list still has no `crm_*` names
- [ ] 3.3 Confirm #6172 and #6262 are still open and the PR body does not close them
