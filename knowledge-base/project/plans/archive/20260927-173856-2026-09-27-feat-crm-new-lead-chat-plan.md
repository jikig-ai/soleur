---
title: "feat: Start a new CRO chat to enter a CRM lead"
type: feat
date: 2026-09-27
slug: feat-crm-new-lead-chat
branch: feat-one-shot-crm-lead-new-chat
issue: none
closes: none
priority: high
domain: product
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
lane: cross-domain
---

# feat: Start a new CRO chat to enter a CRM lead

No spec.md on this branch. Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).

"Lead" has no glossary entry. In this plan it means a new `beta_contacts` row (the product's contact/opportunity head). It is not a second entity.

## Enhancement Summary

**Deepened on:** 2026-09-27
**Sections enhanced:** 4 (mode persistence, assistant leader id, precedent, negative-claim check)
**Research agents used:** none spawned. Grok subagent depth is 1, so the deepen passes ran in this process. Reviewed-Coverage: sequential-fallback.

### Key Improvements

1. The in-memory `session.contextPath` must be the stamped `crm-lead/<id>.mode` value. A cache hit treats `null` as defined and never re-reads the row, so a reaped Query would rebuild the prompt without the mode.
2. The only assistant `leader_id` write is `buildRow` in `cc-dispatcher.ts`. Other `CC_ROUTER_LEADER_ID` uses are log attribution, not the bubble.
3. Keep `persona: "command_center"`. A new persona value is not in the permission-callback union. The CRO text is a prompt flag beside that persona, the same way `routineAuthoring` is.

### New Considerations Discovered

- Verified live: #3270 CLOSED (FLAG_CC_SOLEUR_GO removed), #5402 CLOSED (routine-authoring tab), #6172 OPEN, #6262 OPEN, #3243 OPEN.
- `agentPath` is referenced only in `apps/web-platform/server/domain-leaders.ts`. The web prompt does not load `cro.md`.
- Halt gates passed: User-Brand Impact, Observability, Guard Contract lint, no PAT-shaped token, committed `.pen`. No new store, no downtime DDL, no SSH/timeout trigger.

## Overview

The read-only CRM board at `/dashboard/crm` already exists on `origin/main`. It tells the operator to talk to the CRO, then links to `/dashboard/chat`, which resumes the last thread. A new chat whose job is entering a contact never starts, and the live Concierge (the only path for a new `start_session`, ADR-022) is not given the existing `crm_*` tools or a field list.

This plan adds a New lead control on that board. It opens `/dashboard/chat/new` as the CRO, scoped by a mode flag, and the CRO asks only for the fields `crm_contact_upsert` and `crm_note_append` already accept. No new table, no form, no BANT/MEDDIC/SPICED columns.

## Problem Statement / Motivation

From the CRM screen there is no control that starts a new chat for a new contact. The header, empty state, funnel, and contact drawer either omit a link or point at `/dashboard/chat`. `use-nav-resume` treats that bare path as "resume the last chat". The empty state also says there is nothing to enter, which hides the conversational entry the board was designed around (ADR-102: editing stays with the agent; no CRUD UI).

Even a correct `/dashboard/chat/new?leader=cro` link would not qualify a customer today. `leader` is stored as `conversations.domain_leader`, but `ws-handler.ts` `start_session` always sets routing `{ kind: "soleur_go_pending" }` and dispatches `dispatchSoleurGoForConversation`. `buildCrmTools` is registered only in `startAgentSession` (`agent-runner.ts`). The Concierge `soleur_platform` server in `cc-dispatcher.ts` registers narration tools and, when flagged, the C4 write tool. The Concierge system prompt tells the model to dispatch `/soleur:go`. `plugins/soleur/agents/sales/cro.md` is not loaded into that prompt (`agentPath` is unused outside `domain-leaders.ts`).

## Proposed Solution

Copy the mode-flag pattern already used for routine authoring (`context.type === "routine-authoring"`), with two differences the routine path does not need:

1. The prompt replaces the Command Center router baseline for this chat (same shape as the support persona), so the model does not dispatch `/soleur:go`.
2. The mode survives a cold Query. `context_path` is unique per `(user_id, repo_url)` when set, so a constant sentinel would collapse every New lead click into one thread. The server stamps a per-conversation path `crm-lead/<conversationId>.mode` at insert. Turn 2 and a later cold start recognize that prefix and rebuild `{ type: "crm-lead" }` instead of `{ type: "kb-viewer" }`. The client never supplies the path.

The New lead control (board header and empty state; the header is visible in funnel view too) navigates to `/dashboard/chat/new?leader=cro&mode=crm-lead&msg=<seed>`. The chat page maps `mode=crm-lead` to `{ type: "crm-lead" }` with no KB fetch and no `contextPending`. The seed message is `I want to enter a new CRM lead.` Field names stay in the trusted directive, not in the URL.

`buildCrmTools({ userId })` is registered on that conversation's Concierge `soleur_platform` server only. Writes stay gated. `userId` stays closure-captured. The same RPCs run. Assistant message `leader_id` for this mode is `cro` so the bubble matches the privacy notice (agents `cro`/`cpo`). Permission logs and narration stay `cc_router`.

## Technical Considerations

- Architecture: do not boot `startAgentSession` for this chat. ADR-022 retired that path for new sessions. The amendment is which Query holds the existing tools.
- Performance: one extra MCP tool bundle on crm-lead cold starts only.
- Security: third-party contact text is already untrusted. The directive repeats the Art. 9 prohibition. It must not tell the model to skip the review gate. A client-supplied `context_path` is not the mode switch; the server stamps the prefix from the conversation id.
- NFR: the control is a link with accessible name "New lead". No new retention class. Owner-only RLS is unchanged.
- `email` appears in ADR-102's narrative of what conversations contain. `beta_contacts` has no email column. The CRO must not ask for one.
- Stage `qualified` is a value of `stage` (`STAGE_PROBABILITY`), not a required-field gate. The schema allows `qualified` with other columns null. The CRO leaves `stage` at `new` until the operator says the contact is qualified, then sets `qualified` through the existing upsert or `crm_contact_set_stage`.
- `amount` without `currency` is rejected by `beta_contacts_amount_requires_currency`. The prompt says so.
- `amountBasis` is `hypothetical_acv`, `committed`, or `unknown`.

### Attack Surface Enumeration

Not a security-fix plan. The write surface stays the three RPCs (`crm_contact_upsert`, `crm_note_append`, `crm_contact_set_stage`). This change adds one caller (the crm-lead Concierge Query). It does not add an owner INSERT policy, a service-role write, or a browser POST.

## Research Insights

### Premise Validation

Checked on 2026-09-27 against `origin/main` (`e3b804196c`). #6172 is OPEN; title is the deferred in-UI contacts/pipeline surface; `closedByPullRequestsReferences` is empty. The surface it describes is already on main: `apps/web-platform/app/(dashboard)/dashboard/crm/page.tsx`, `components/crm/crm-surface.tsx`, ADR-102 "UI phase (read-only)". This plan does not deliver that issue and does not close it. #6262 is OPEN; it asks for a `/soleur:pipeline` skill. No such skill exists under `plugins/soleur/skills/`. This plan does not add one and does not close it. The CRM board, `crm_*` tools, and `beta_contacts` columns exist on `origin/main`. The gap is entry and guidance, not a missing store. Shape: patch the live chat path, not a greenfield CRM.

### Property List

1. From the CRM screen the operator can start a new chat whose purpose is entering a new `beta_contacts` row.
2. In that chat the CRO names the data the product already stores for that row and for a sales-lens note, and does not invent another schema.

### Cut List

- A contact form or drag-to-stage UI. Property 1 is a chat. ADR-102 rejected a write UI because it duplicates the agent.
- Reviving `startAgentSession` for `leader=cro`. ADR-022 makes `soleur_go_pending` the new-session path. The legacy runner is not where a new chat runs.
- New qualification columns, or BANT/MEDDIC/SPICED as stored fields. `pipeline-analyst.md` names those frameworks as analysis vocabulary. They are not columns. Property 2 is already `crm_contact_upsert` / `crm_note_append`.
- A constant `context_path` sentinel. The partial unique index `conversations_context_path_user_uniq` would merge every New lead into one thread.
- Widening `conversations.kind`. A non-`command_center` kind is filtered out of the rail (migration 131). The chat must stay `command_center`.
- Closing #6172 or #6262. Neither issue is what this change ships.
- Editing `plugins/soleur/agents/sales/cro.md` as the product prompt. The web chat does not load `agentPath`.

### Repo research

- Board host: `apps/web-platform/components/crm/crm-surface.tsx` (`Header` link to `/dashboard/chat`, `EmptyState` with no link). Drawer link: `contact-detail-sheet.tsx`. Funnel link: `funnel-view.tsx`. Those edit links stay as they are. This plan does not retarget them.
- New chat route: `app/(dashboard)/dashboard/chat/[conversationId]/page.tsx`. `conversationId === "new"` starts a session. `?context=` is a KB path fetch. `?leader=` is read in `chat-surface.tsx` and passed to `startSession`. `?msg=` is sent once `sessionConfirmed`.
- Mode-flag precedent: `ALLOWED_CONTEXT_TYPES` / `MODE_FLAG_CONTEXT_TYPES` in `server/context-validation.ts`; `ROUTINE_AUTHORING_DIRECTIVE`; `routineAuthoring` threaded in `ws-handler.ts` `dispatchSoleurGoForConversation` and appended in `cc-dispatcher.ts`. Support replaces the baseline in `buildSoleurGoSystemPrompt` when `persona === "support"`.
- Turn 2 rebuilds context only as `kb-viewer` from `session.contextPath` (`ws-handler.ts` chat case). A mode with no path dies on the next cold Query. System prompt and MCP servers are baked at cold-Query construction (`hasActiveCcQuery`).
- Columns: `CONTACT_COLUMNS` in `server/crm/crm-reads.ts`. Upsert inputs in `crm_contact_upsert` inside `server/crm/crm-tools.ts`. Stages: `STAGE_PROBABILITY` in `lib/crm/stage-probability.ts`.
- C4 already has `engine -> crmStore`, `webapp -> crmStore` (read), and `betaContact` (`model.c4` Beta-CRM comment). No new actor, store, or edge.

### Learnings

- ADR-102 and the 2026-07-08 CRM learnings: writes are RPC-only, `auth.uid()`-pinned, PII-safe errors, Art. 9 not solicited. Do not add a second write path.
- `2026-06-14` short-circuit guards must sit with the recovery they describe. The crm-lead prompt replacement and the tool registration must be the same flag.
- Mode flags that are not persisted are a turn-2 lie. Routine authoring has this gap because it has no `context_path`. This plan does not copy that gap.
- Untrusted CRM bodies can carry instructions. The existing envelope stays. The directive is server-authored, not `context.content`.

### Community discovery

TypeScript / Next.js is the stack. The community-discovery signature table (Flutter, Rust, Elixir, Go, Swift, Kotlin, PHP) does not match. Skipped.

### Functional overlap

No independent registry search ran (see Reviewed-Coverage below). On disk there is no `soleur:pipeline` skill. The overlap is the in-repo mode-flag and the existing CRM tools. Nothing to install.

### External research

Skipped. The field list is fixed by the schema. Adopting an external qualification framework would be the parallel schema this plan cuts.

### CLAUDE.md

Client/server import boundary stands. The directive module lives under `server/`. The board is a client component and only builds a URL.

### Related issues

- #6172 OPEN. Not closed. The read-only board is already shipped; this work is the chat entry.
- #6262 OPEN. Not closed. A sales-execution skill is a different surface.
- #3270 / ADR-022. Concierge is the new-session binding.
- #5402. Routine-authoring mode flag, the pattern, not the persistence story.
- ADR-113. Support persona, the prompt-replacement pattern.

### Research Reconciliation — Spec vs. Codebase

No spec.md. The operator text assumed a CRM/CRO screen. Reality:

| Claim in the ask | Reality on origin/main | Plan response |
|---|---|---|
| A screen handles CRM leads | `/dashboard/crm` read-only board | Add New lead on that screen |
| The CRO chat can record a lead | Tools exist on the legacy runner only | Register those tools on the crm-lead Concierge Query |
| The CRO knows the qualification fields | No product prompt lists them; no separate qualification schema | Directive lists upsert and note inputs only |

## Implementation Phases

### Phase 1: Tests first

- `apps/web-platform/test/crm/crm-surface.test.tsx`: header and empty state expose a link whose href contains `/dashboard/chat/new`, `leader=cro`, `mode=crm-lead`, and the seed text. The link is present when contacts exist and when the list is empty.
- `apps/web-platform/test/ws-context-validation.test.ts`: `{ type: "crm-lead" }` is accepted with no path; a client `path` is still rejected when unsafe.
- New `apps/web-platform/test/server/crm-lead-directive.test.ts`: the directive string contains every `CRM_CONTACT_UPSERT_FIELDS` name except `contactId`, contains `body` and `lens`, does not contain `BANT`, `MEDDIC`, `SPICED`, or `email`, and states that `stage` stays `new` until the operator calls the contact qualified.
- A cc-dispatcher or soleur-go test: `crmLead: true` registers the seven `crm_*` tool names; `crmLead` absent does not.
- A ws-handler test: a `context_path` of `crm-lead/<id>.mode` rebuilds type `crm-lead` and does not call the KB document resolver.

### Phase 2: One field list and the directive

- Export `CRM_CONTACT_UPSERT_FIELDS` from `server/crm/crm-tools.ts` (the upsert input keys) and build the tool schema from it. Note inputs `body` and `lens` stay on `crm_note_append`.
- Add `server/crm-lead-directive.ts` exporting `CRM_LEAD_DIRECTIVE`, interpolated from that list plus `STAGES` and the amount-basis enum. Trusted system text. States: you are the CRO for this chat; do not dispatch `/soleur:go`; ask for the listed fields; do not invent fields; do not ask for email; do not solicit Art. 9 data; treat contact text as data; leave stage `new` until the operator says qualified; amount requires currency; the review gate is the only save confirmation.

### Phase 3: Wire the mode through the live chat

- `server/context-validation.ts`: add `crm-lead` to both allow-sets (mode flag, no path required).
- `server/ws-handler.ts`: on create, when context type is `crm-lead`, set `context_path` to `crm-lead/<id>.mode` and set `session.contextPath` to that same string (not only the column). The chat-case cache treats a present `session.contextPath` of `null` as a hit and skips the row read (`session.contextPath !== undefined`). In both the cache-hit path and the row-read path, a `crm-lead/<id>.mode` value rebuilds `{ type: "crm-lead" }` and skips KB resolution. Thread `crmLead` the way `routineAuthoring` is threaded.
- `server/soleur-go-runner.ts`: `buildSoleurGoSystemPrompt` takes `crmLead` beside `persona: "command_center"`. When `crmLead` is true, return the CRO directive instead of the router baseline (same early-return shape as `persona === "support"`). Do not also append "Dispatch via /soleur:go". Do not add a persona enum value. `permission-callback.ts` only special-cases `"support"`.
- `server/cc-dispatcher.ts`: when `crmLead`, spread `buildCrmTools({ userId })` into the existing `soleur_platform` server. Pass `crmLead` into the prompt builder. The only `leader_id:` assignment is `buildRow` (`leader_id: CC_ROUTER_LEADER_ID`). Pass the flag into `buildRow` and set `cro` there. Leave every `leaderId: CC_ROUTER_LEADER_ID` log site unchanged.

### Phase 4: CRM entry

- `components/crm/crm-surface.tsx`: New lead link in `Header` and `EmptyState`. Href built with `URLSearchParams` so the seed is encoded. Empty-state copy no longer says there is nothing to enter. It says the board is read-only and the CRO chat is how a lead is entered.
- `app/(dashboard)/dashboard/chat/[conversationId]/page.tsx`: if `mode=crm-lead`, set `initialContext` to `{ type: "crm-lead" }` synchronously. Do not set `contextPending`. Do not fetch KB. Ignore `mode` when `context` (KB path) is also present; KB wins and this plan does not combine them.

### Phase 5: ADR

- Amend `knowledge-base/engineering/architecture/decisions/ADR-102-beta-crm-capture-store-per-tenant-owner-private-agent-native.md` with a short subsection: a new-lead chat is a Concierge Query (ADR-022) with `buildCrmTools` registered for that mode, same RPCs, same review gate. It is not a return to `agent-runner.ts`. Do not allocate a new ADR ordinal.

## Files to Edit

- `apps/web-platform/components/crm/crm-surface.tsx`
- `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx`
- `apps/web-platform/server/context-validation.ts`
- `apps/web-platform/server/ws-handler.ts`
- `apps/web-platform/server/soleur-go-runner.ts`
- `apps/web-platform/server/cc-dispatcher.ts`
- `apps/web-platform/server/crm/crm-tools.ts`
- `apps/web-platform/test/crm/crm-surface.test.tsx`
- `apps/web-platform/test/ws-context-validation.test.ts`
- `knowledge-base/engineering/architecture/decisions/ADR-102-beta-crm-capture-store-per-tenant-owner-private-agent-native.md`

## Files to Create

- `apps/web-platform/server/crm-lead-directive.ts`
- `apps/web-platform/test/server/crm-lead-directive.test.ts`
- `knowledge-base/product/design/crm/crm-new-lead-chat.pen`

## Open Code-Review Overlap

`gh issue list --label code-review --state open` on 2026-09-27. Matches:

- #3243 arch: decompose `cc-dispatcher.ts`. Acknowledge. This plan adds a flag branch, not a module split.
- #3242 review: `tool_use` WS event lacks raw name. Acknowledge. Different concern.
- #3374 review: `slot_reclaimed` frame in `ws-handler.ts`. Acknowledge. Different concern.
- #2191 refactor(ws): session timers. Acknowledge. Different concern.
- #2223 and #2222 perf(chat) on the chat page. Acknowledge. Scroll and memo work, not this mode flag.

None folded in.

## User-Brand Impact

- **If this lands broken, the user experiences:** the New lead control opens a normal Concierge thread that tries to run `/soleur:go`, or a CRO chat that cannot save because the tools were not registered, so the contact never appears on the board.
- **If this leaks, the user's data is exposed via:** a crm-lead turn sending another tenant's `beta_contacts` row to the model or the browser. The existing closure `userId` and `auth.uid()` RPC pin are what stop that. This plan does not add a browser write.
- **Brand-survival threshold:** `single-user incident`

CPO sign-off is required before `soleur:work`. Recorded in Domain Review from an in-process pass, not an independent spawn (Reviewed-Coverage). `soleur:engineering:review:user-impact-reviewer` runs at review time.

Artifact pairs:

- New lead link and the CRO thread. Exposure vector: the model context for that thread includes third-party contact fields the operator types, which is the existing PA-30 Chapter V transfer to Anthropic, not a new vendor.
- Saved `beta_contacts` row. Exposure vector: a write RPC that trusted a client-supplied owner id. The tool must keep `userId` in the closure and must not add `p_user_id`.

## Observability

```yaml
liveness_signal:
  what: "crm-lead mode is wired: context type crm-lead is allowed and the CRM board links to it"
  cadence: "per ship, via the discoverability probe; chat errors use the existing web-platform Sentry capture"
  alert_target: "Sentry issue on crm-tools or cc-dispatcher exceptions (existing project)"
  configured_in: "apps/web-platform/sentry.server.config.ts"
error_reporting:
  destination: "Sentry web-platform via SENTRY_DSN"
  fail_loud: "crm-tools:<op>:<code> synthetic error already mirrored by reportSilentFallback; a failed upsert returns { error, code } to the model"
failure_modes:
  - mode: "New lead opens a router thread with no crm_* tools"
    detection: "crm-lead directive test and the cc tool-registration test fail in CI"
    alert_route: "CI on the PR; no new pager"
  - mode: "Cold restart drops the mode and the model stops seeing the tools"
    detection: "ws-handler test that a crm-lead/<id>.mode context_path rebuilds type crm-lead"
    alert_route: "CI on the PR; no new pager"
  - mode: "Upsert rejected (currency, stage, auth)"
    detection: "existing crm-tools Sentry mirror with SQLSTATE mapped to a stable code and no row text"
    alert_route: "Sentry issue, existing crm-tools feature tag"
logs:
  where: "web-platform server logs and Sentry; no new unit"
  retention: "existing Sentry and log retention; no new sink"
discoverability_test:
  command: "grep -F crm-lead apps/web-platform/server/context-validation.ts apps/web-platform/components/crm/crm-surface.tsx"
  expected_output: "crm-lead"
```

## Guard Contract

### Guard 1 — CRM intake field set

**Property.** The CRO intake directive asks only for fields `crm_contact_upsert` and `crm_note_append` accept, and does not name a second qualification schema.

**Assembly.** One chokepoint: `CRM_CONTACT_UPSERT_FIELDS` in `server/crm/crm-tools.ts` feeds both the upsert tool schema and `CRM_LEAD_DIRECTIVE`. Note fields are the `body` and `lens` keys on `crm_note_append` in the same file. The test `apps/web-platform/test/server/crm-lead-directive.test.ts` reads the exported directive and the exported field list. No second list in the React layer. The prompt builder is the only consumer of the directive (`buildSoleurGoSystemPrompt` when `crmLead` is true).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Delete `name` from `CRM_CONTACT_UPSERT_FIELDS` while the directive test still requires every upsert key the tool accepts, or remove `name` from the directive while the export still lists it | RED |
| 2 | Make the directive test exit 0 without reading `CRM_LEAD_DIRECTIVE` (empty body, no expect) | RED — the test must fail closed when the export is missing |
| 3 | After a compliant list, add `budget` to the directive string | RED |
| 4 | Insert the word `BANT` into the directive while the field list is otherwise compliant | RED — X holds (a directive exists) and Y fails (no parallel schema) |

**Harness rows.** Delete the `expect` that forbids `BANT` and the suite must still fail if that word is present, because the field-set equality check is independent of that one expect; a test file that contains zero `expect(` calls fails a line-count floor in the same test file (the dispatch floor). Must-PASS: the directive uses `nextAction` (the tool key) rather than `next_action` (the column). That spelling is allowed. The column name is not a second field.

**Anchor.** The field list and the directive ship in one diff, so this guard proves they match each other, not that a reviewer outside the diff approved the schema. The schema authority outside the directive file is the upsert tool's input object, which the export feeds. A weakening that edits the export and the directive together still has to match `crm_contact_upsert`'s RPC argument list in `126_beta_crm.sql` (`p_name`, `p_company`, `p_role`, `p_source`, `p_stage`, `p_next_action`, `p_next_action_date`, `p_last_contact`, `p_amount`, `p_currency`, `p_amount_basis`, `p_expected_close_date`). The test includes that SQL name set, mapped camelCase, so one diff cannot drop a column from both the export and the directive and stay green.

## Acceptance Criteria

- [ ] On `/dashboard/crm`, with contacts and with an empty board, a control named New lead navigates to a new chat (`/dashboard/chat/new`) with `leader=cro`, `mode=crm-lead`, and the seed message. (`crm-surface.tsx`, `crm-surface.test.tsx`)
- [ ] That chat's first model prompt is the CRO directive, not the `/soleur:go` router baseline. (`buildSoleurGoSystemPrompt`, `crm-lead-directive.ts`)
- [ ] The directive names every upsert field except `contactId`, plus note `body` and `lens`, names stage `qualified` only as a `stage` value, and does not name email, BANT, MEDDIC, or SPICED. (`crm-lead-directive.test.ts`)
- [ ] The crm-lead Query registers `crm_contact_list`, `crm_contact_get`, `crm_note_list`, `crm_stage_transitions_list`, `crm_contact_upsert`, `crm_note_append`, and `crm_contact_set_stage`. A normal Concierge Query does not. (`cc-dispatcher.ts`)
- [ ] Writes still go through the existing RPCs with no client `userId` argument, and remain review-gated. (`crm-tools.ts` unchanged call shape)
- [ ] A second turn and a cold Query on a conversation whose `context_path` is `crm-lead/<id>.mode` still receive the directive and the tools, and do not resolve that path as a KB file. (`ws-handler.ts`)
- [ ] Each New lead click creates a distinct conversation. (`context_path` includes the conversation id)
- [ ] Assistant bubbles on that conversation use leader id `cro`. Other Concierge leader ids stay `cc_router`.
- [ ] The board stays read-only. No POST route, no form, no drag-to-stage.
- [ ] ADR-102 records the Concierge Query as the new-lead writer. No new ADR file. No `.c4` edit.
- [ ] #6172 and #6262 stay open.
- [ ] Wireframe `knowledge-base/product/design/crm/crm-new-lead-chat.pen` shows the board control, the empty state, and the CRO asking for the existing fields.

## Test Scenarios

- Given the board has contacts, when the operator activates New lead, then the browser goes to `/dashboard/chat/new` with `leader=cro`, `mode=crm-lead`, and a seed that says a new CRM lead.
- Given the board is empty, when the operator activates New lead, then the same href is used and the empty copy does not say there is nothing to enter.
- Given `mode=crm-lead` and no `context` query, when the chat page renders, then `startSession` receives `{ type: "crm-lead" }` and does not wait on a KB fetch.
- Given context type `crm-lead`, when the conversation row is inserted, then `context_path` is `crm-lead/<that id>.mode` and `kind` stays `command_center` and `domain_leader` is `cro`.
- Given that `context_path` on a later turn with no warm Query, when the server rebuilds context, then type is `crm-lead` and the KB resolver is not called.
- Given two New lead clicks, when both conversations exist, then their ids differ.
- Given the CRO directive, when the test scans it, then every upsert field except `contactId` is present and `BANT` is absent.
- Given a normal Concierge dispatch, when tool names are listed, then no `crm_contact_upsert`.
- Given a crm-lead dispatch, when the model calls `crm_contact_upsert` without `contactId`, then the RPC is `crm_contact_upsert` and the review gate still applies.
- Given the operator has not said the contact is qualified, when the directive is followed, then `stage` is omitted or `new`, not `qualified`.
- **Browser:** open `/dashboard/crm`, activate New lead, confirm the chat shows the CRO and the first reply asks for name, company, role, source, next action, dates, amount with currency and amount basis, and expected close, and does not ask for email.
- **API verify:** none added. Existing `GET /api/crm/contacts` remains the board read. No new route.
- **Cleanup:** none. Tests use mocks. No live contact is created by the plan.

## Success Metrics

- An operator on the CRM board can start a new CRO chat in one action.
- A reviewer can point at `CRM_CONTACT_UPSERT_FIELDS` as the only field list.

## Precedent diff

Routine authoring (`#5402`) is the mode-flag precedent. Side by side:

| | Routine authoring | This plan |
|---|---|---|
| Context type | `routine-authoring`, no path | `crm-lead`, no client path |
| Prompt | Appended to the router baseline | Replaces the router baseline, because the baseline says to dispatch `/soleur:go` |
| Tools | Directive names `routine_run`; registration is the legacy runner | `buildCrmTools` registered on the Concierge server for this flag only |
| Persistence | No `context_path`, so a cold Query loses the flag | Server-stamped per-id `context_path`, copied onto `session.contextPath` |
| Persona | `command_center` | `command_center` plus `crmLead` |

No new SQL function. The write RPCs stay the `SECURITY DEFINER` functions already in `126_beta_crm.sql`. This plan does not change their `search_path` or grants.

## Dependencies & Risks

- The long-lived Query bakes tools at cold start. Forgetting either the column stamp or the `session.contextPath` copy makes a reaped Query drop the tools while the socket cache still looks warm. Phase 1 tests both.
- `cc-dispatcher.ts` is large (#3243). Touch only the tool-build block, the prompt flag, and the assistant `leader_id` persist.
- `?context=` and `?mode=crm-lead` together are undefined. KB wins; do not invent a combined mode.
- Grok subagent depth is 1, so domain leaders and the review panel were not separate processes. See Reviewed-Coverage.

## Domain Review

**Domains relevant:** Product, Sales, Legal, Engineering

Reviewed-Coverage: sequential-fallback. This process is a Grok subagent. Nested `spawn_subagent` is refused at depth 1 (`~/.grok` user guide, Depth Limits). Domain, spec-flow, CPO, CRO, CLO, CTO, and plan-review passes below were done in this process. They are not independent reviews.

### Sales (CRO)

**Status:** reviewed
**Assessment:** #6172 and #6262 were checked OPEN. The sales job is to collect the existing contact head before calling `stage` `qualified`. Do not add a pipeline skill here. Do not ask for email. Amount needs a currency and an amount basis or the row is either rejected or stuck at `unknown`, which pipeline rollups exclude from committed pipeline.

### Legal (CLO)

**Status:** reviewed
**Assessment:** No new table and no new column. PA-30 and the privacy notice already describe `cro`/`cpo` agent writes and the Anthropic transfer. Attributing the bubble to `cro` keeps that notice true. The directive must forbid Art. 9 solicitation. No privacy-doc edit in this plan. Recommend the Phase 2.7 gate, which ran below.

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Blast radius of a bad write is one owner, because the RPC checks `auth.uid()`. Registering the tools on every Concierge chat would widen the model that can call them. Keep the flag. Do not revive the legacy runner. Do not persist the mode in `kind` or a constant `context_path`.

### Product/UX Gate

**Tier:** blocking
**Decision:** reviewed (partial)
**Agents invoked:** none independently. In-process spec-flow, CPO, and a `.pen` wireframe.
**Skipped specialists:** none. `soleur:marketing:copywriter` was not recommended. Product chrome only.
**Pencil available:** `pen` is on PATH (`pen.dev` CLI). `check_deps.sh --auto` failed installing `@pencil.dev/cli` (sharp build). Node is v26.8.1, so this is not the Node hard-block. The `.pen` was written in the schema of `beta-crm-pipeline.pen`. Screenshots were not exported.
**Wireframes:** ready for async review at `knowledge-base/product/design/crm/crm-new-lead-chat.pen` (frames `01 CRM board — New lead`, `02 CRO new-lead chat`, `03 CRM empty — New lead`).

#### Findings

- Entry is the New lead control on the board, including the empty state and the funnel (the header is shared). Exit is a CRO chat that asks for the existing fields and saves only after the review gate. A dropped chat saves nothing.
- Dead end avoided: `mode` must not fall through to the router baseline.
- Existing "edit this contact" links stay on `/dashboard/chat`. Out of scope. They still resume the last thread.
- CPO: do not add a form. The empty state must not keep saying there is nothing to enter. Threshold stays single-user incident. Sign-off is this in-process pass; an independent CPO spawn did not run.

### GDPR gate

**This is not legal review. Findings are heuristic. Consult `soleur:legal:clo` + `soleur:legal:legal-compliance-auditor` before merging.**

Ran the five v1 checks against this plan (no new migration, no new column).

### `GDPR-Art-6` — no new column

**Severity:** Suggestion
**Article:** Art. 6
**Location:** plan section Proposed Solution
**Pattern matched:** no new schema column
**Why this matters:** Lawful basis for `beta_contacts` is already Art. 6(1)(f) with the 2026-07-07 LIA.
**What to do:** Do not add a column. If one appears during work, stop and annotate it.

### `GDPR-Art-9` — do not solicit special-category data

**Severity:** Suggestion
**Article:** Art. 9
**Location:** `CRM_LEAD_DIRECTIVE`
**Pattern matched:** free-text note body can carry special-category data if the model asks for it
**Why this matters:** No Art. 9 column is being added, so this is not a Critical column-name match. The risk is the prompt.
**What to do:** The directive forbids asking for Art. 9 data. The existing tool envelope stays.

### `GDPR-Chapter-V` — existing Anthropic transfer

**Severity:** Suggestion
**Article:** Art. 44–49
**Location:** PA-30, already disclosed
**Pattern matched:** crm-lead turns send contact fields the operator types to the model
**Why this matters:** This is the existing `cro`/`cpo` path, not a new vendor.
**What to do:** No new DPA row. Do not log row values.

No `GDPR-Art-5e` or `GDPR-Art-17` finding: no new table and no new FK.

## Architecture Decision (ADR/C4)

### ADR

Amend ADR-102 (no new ordinal). One line of decision: new-lead chats write through the Concierge Query's `soleur_platform` server using the existing `crm_*` tools and RPCs. `agent-runner.ts` is not the new-session writer (ADR-022).

### C4 views

No `.c4` edit.

Checked `knowledge-base/engineering/architecture/diagrams/model.c4`, `views.c4`, and `spec.c4` by reading the Beta-CRM block and the view includes:

- External human actors: `founder` (already modeled; reaches the store only through `webapp` or the agent). `betaContact` (already modeled, `#external`, included from `views.c4` context and containers).
- External systems: no new vendor. Anthropic stays the existing engine path. Supabase stays `crmStore`.
- Container / store: `platform.infra.crmStore` already in the containers view.
- Access: `engine -> crmStore` is the write edge this mode uses. `webapp -> crmStore` stays the read-only GET edge. No `founder -> crmStore` edge is added.
- Counts on edges are untouched because the model file is untouched. `plugins/soleur/test/c4-count-parity.test.sh` does not need a new expectation. Work runs it only if a `.c4` line changes. The plan forbids that change.

### Sequencing

The amendment is true when this mode ships. Status of ADR-102 stays `adopting`. No follow-up issue for the ADR.

## Alternative Approaches Considered

| Approach | Why not |
|---|---|
| Embed `ChatSurface` on the CRM page, as Routines does | The ask is a new chat in the conversation rail. An embedded composer hides the thread from the rail and still needs the same server mode. |
| Link to `/dashboard/chat/new?leader=cro` only | `leader` does not change the prompt or the tool list. |
| Put the field list in the `msg` query | The list would be user text, droppable and forgeable, and would drift from the tool schema. |
| New `kind = crm_lead` | Rail and DSAR filters key on `command_center`. A write-boundary sweep for a label is the wrong chokepoint. |

## References & Research

- ADR-102, ADR-022, ADR-113
- `apps/web-platform/server/crm/crm-tools.ts` `crm_contact_upsert`
- `apps/web-platform/server/crm/crm-reads.ts` `CONTACT_COLUMNS`
- `apps/web-platform/lib/crm/stage-probability.ts` `STAGE_PROBABILITY`
- `apps/web-platform/server/routine-authoring-directive.ts`
- `apps/web-platform/supabase/migrations/126_beta_crm.sql`
- Wireframe: `knowledge-base/product/design/crm/crm-new-lead-chat.pen`
- Prior board plan: `knowledge-base/project/plans/2026-07-08-feat-beta-crm-ui-read-only-board-plan.md`

## Reviewed-Coverage

sequential-fallback. Plan-review panel (DHH, Kieran, simplicity, spec-flow, CPO) was not spawned. In-process pass applied below as mechanical: keep one field export; do not revive the legacy runner; test cold start; do not close #6172 or #6262. No taste change was auto-applied.

## Sharp Edges

- A plan whose User-Brand Impact section is empty fails deepen-plan. This one is filled.
- `email` is not a column.
- Turn-2 `kb-viewer` rebuild will treat `crm-lead/<id>.mode` as a document if the prefix check is ordered second.
- Registering CRM tools outside the `crmLead` flag puts third-party writes on every Concierge chat.
- The directive must not say the model may skip the review gate.
