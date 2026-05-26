---
date: 2026-05-11
status: complete
issues:
  - "#3258 (closed, superseded by #3286)"
  - "#3603 (hardening umbrella, OPEN)"
pull_requests:
  - "#3286 (merged 2026-05-05 — shipped headline fix)"
  - "#3602 (draft, this brainstorm's PR)"
brand_survival_threshold: single-user incident
gdpr_gate_required: true
---

# Brainstorm — cc-soleur-go transcript persistence hardening

## What We're Building

A **3-PR hardening sequence** for the cc-soleur-go transcript-persistence path, gated by an operator verification of the already-shipped headline fix.

Issue #3258 framed two architectural approaches (persist at SDK stream-end vs exclude cc rows from hydration). Repo investigation during this brainstorm established that **approach 1 already shipped in PR #3286** (merged 2026-05-05, same day as the parent PR #3254): `saveAssistantMessage` exists at `apps/web-platform/server/cc-dispatcher.ts:1018-1050`, called from `onTextTurnEnd` at line 1077. Hydration in `api-messages.ts:76-88` returns cc and non-cc rows uniformly — no `active_workflow` filter — confirming approach 2 was correctly rejected.

The brainstorm therefore pivoted from *design the fix* to *audit residual risk surfaced by CTO + CPO + CLO under USER_BRAND_CRITICAL framing*. Seven workstreams emerged. They are tracked in **issue #3603** and will land as three PRs in sequence:

| PR | Workstreams | Scope | GDPR gate |
|---|---|---|---|
| **PR-A** | W1, W2, W3, W4 | Engineering hardening — cross-tenant invariant tests, flush-on-abort, retry idempotency latch, `status`/`usage` parity on cc path | Required (plan 2.7, work 2 exit, ship 5.5) |
| **PR-B** | W5 | Migration cohort UX — inline "history may be partial" affordance + rollout banner | Not required (UX-only) |
| **PR-C** | W6, W7 | Legal refresh — Privacy Policy §4.7 + DPD activity #10 acknowledgement of cc persistence; DSAR audit-log review for 2026-05-05 → AC11 cohort | Required for §C scope (regulated-data documents) |

A **Step 0** prerequisite gates all three: operator verifies AC11 from #3286 on prod (cc/KB-Concierge thread renders both bubbles after tab reload). If that fails, a fresh symptom-scoped issue is filed and this hardening pass is paused — the wrong frame for a still-broken visible state.

## Why This Approach

The verification-gated 3-PR shape was chosen over a single bundled PR or a tighter W1-only split because:

- **Review competence boundaries.** PR-A is engineering with GDPR-gated risk. PR-B is product/UX. PR-C is legal-document writing. Each maps to a distinct reviewer competence; mixing them dilutes the review.
- **GDPR-gate budget.** USER_BRAND_CRITICAL with brand-survival threshold = single-user incident means the cross-tenant tests carry zero failure budget. Bundling them with non-regulated UX/doc work raises the chance that a non-regulated bug stalls a regulated workstream.
- **AC11 verification first.** The CTO assessment flagged that AC11 from #3286 (Continue-Thread renders both bubbles on cc/KB-Concierge tab reload) was unchecked at merge. If the visible fix is broken, every workstream in #3603 is reasoning on a false premise. A 5-minute operator check is cheaper than a wasted plan cycle. See `knowledge-base/project/learnings/2026-04-23-verify-trigger-path-before-attributing-regression.md` for the canonical version of this lesson.
- **Migration cohort affordance is honest, not silent.** CPO frame: "selective deletion" (current asymmetric state) is worse for trust than "symmetric blank" (approach 2). The fix in #3286 closes the asymmetry going forward, but conversations created between 2026-05-05 and the AC11 verification date still render lopsidedly. Silent rendering of an incomplete transcript is also a transparency defect per CLO (Art. 5(1)(a)). A "history may be partial" inline marker is mandatory on the brand-promise *and* legal axis.

## Key Decisions

| # | Decision | Rationale |
|---|---|---|
| DEC1 | Close #3258 as superseded by #3286 | Headline ask already shipped; reviving the issue's two-approach framing would mislead a future planner. |
| DEC2 | Open #3603 as hardening umbrella | Residual scope is real (W1-W7) but distinct from the original issue's framing. A new issue avoids re-litigating closed approaches. |
| DEC3 | Verification-gated 3-PR sequence (PR-A engineering, PR-B UX, PR-C legal) | Matches review competence boundaries; isolates GDPR-gate risk to PR-A and PR-C. |
| DEC4 | AC11 prod verification is Step 0; failure aborts and pivots to fresh issue | Don't reason on a false premise. |
| DEC5 | W4 (`status`/`usage` column parity on cc path) lands in PR-A alongside W2/W3 | Same file, same owner, same test surface. Stage 3 deferral comment at `cc-dispatcher.ts:1137-1139` is resolved here. |
| DEC6 | Cross-tenant matrix test (W1) uses synthesized fixtures only | Per `cq-test-fixtures-synthesized-only`. Two-user-two-conversation matrix asserts isolation under concurrent load. |
| DEC7 | Abort flush (W2) writes `status:"aborted"` from `onWorkflowEnded` for non-`completed` statuses; no UNIQUE DB constraint for retry-dedup | Surfacing a Postgres UNIQUE error to a user is a worse UX than an in-process latch (W3). Single owner stays in `dispatchSoleurGo`. |
| DEC8 | Retry-idempotency latch (W3) is per-`(conversationId, turnIndex)` in-process, keyed by turn counter | DB constraints would propagate Postgres errors to the user; an in-process latch is invisible to the client. |
| DEC9 | Privacy Policy §4.7 + DPD activity #10 refresh lands in PR-C post-ship of PR-A | Documenting state that doesn't yet exist on main is the prior PR-3286-shipped-but-undocumented gap. Refresh after persistence is verified on prod. |
| DEC10 | DSAR cohort audit (W7) is internal-only; supplementary disclosure only if any Art. 15 export actually occurred in the 2026-05-05 → AC11 window | Determination is auditable; proactive disclosure to non-exporting users would be noise. |

## Open Questions

1. **AC11 verification owner.** Who runs the operator check on prod, and where is the result logged? Suggestion: this brainstorm's session learning captures the result; if it fails, file the fresh issue before the plan cycle starts.
2. **W2 abort-flush wire detail.** Does `onWorkflowEnded` fire reliably on container kill, or only on graceful runner shutdown? If the latter, container-kill loss is an irreducible residual — note in W2 plan as accepted-risk, not a bug.
3. **W3 turn-counter semantics.** Should the latch be `(conversationId, turnIndex)` or `(conversationId, sdkSessionId, turnIndex)`? If `sessionId` changes on SDK rebind mid-conversation, the turnIndex restarts — a stale latch could miss a legitimate new turn. Resolve in plan Phase 2.
4. **W5 cohort detection query shape.** Must scan `conversations` where `created_at BETWEEN '2026-05-05' AND <AC11_date>` AND `EXISTS (user message)` AND `NOT EXISTS (assistant message)`. Index coverage? Run cost vs runtime?
5. **PR-B vs PR-C ordering.** PR-B (migration banner) can ship before PR-C (legal refresh) without dependency. Default ship order: A → B → C, but B and C are independent.

## User-Brand Impact

- **Artifact:** cc-soleur-go conversation transcripts (user-generated PII + assistant-generated content). Surfaces: KB-Concierge, cc-soleur-go chat, Conversation Inbox (Phase 3.3 shipped), Session Sharing (Phase 3.18 shipped).
- **Vectors endorsed at Phase 0.1:** trust breach / lost transcripts, data loss / corruption, cross-tenant / dedup-contract leak.
- **Threshold:** single-user incident. One screenshot of User A's assistant turn surfacing in User B's tab ends recruitment per CPO. One incomplete DSAR export per CLO is an Art. 15 violation regardless of cohort size.
- **Failure modes ranked.** (1) cross-tenant leak — low probability, unbounded blast radius, Art. 33/34 notifiable; (2) silent transcript truncation on abort — medium probability, single-user blast, P1 trust break; (3) double-rendered turn on SDK retry — high visibility, low blast, P2 UX glitch.
- **Mitigations baked into the 3-PR sequence.** PR-A's W1 matrix test is the primary cross-tenant invariant. W2 flush-on-abort closes the silent-truncation hole except on container-kill. W3 latch closes the double-render hole. W5 banner converts the residual cohort gap into transparent user-facing acknowledgement.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support
**Mandatory under USER_BRAND_CRITICAL:** CPO, CLO, CTO (spawned in parallel at Phase 0.5)

### Engineering (CTO)

**Summary:** Headline fix shipped in #3286. Three residual risks identified — partial assistant text lost on abort (Risk 2), SDK-retry idempotency (Risk 3), `mirrorWithDebounce` swallowing save failure to UI (Risk 4). Blast radius single-user, single-conversation under existing RLS. Cleaner primitive available (write-through buffer with flush-on-abort) but not architecturally mandatory. Migration cohort is narrow (hours-wide window between #3254 and #3286 merges) — no backfill job warranted.

### Product (CPO)

**Summary:** Workspace positioning ("compounding institutional memory") makes Approach 2 untenable as a final state — confirms #3286's Approach 1 choice was correct. Priority for hardening is misclassified at P2; recommends P1 given Phase 3.3 + 3.18 already depend on transcript durability and Phase 4 recruitment is gated on this trust. Migration cohort needs an inline "history may be partial" marker (sunset 90 days). Cross-tenant dedup tests must be tenant-scoped, not just idempotency-scoped — one screenshot ends recruitment.

### Legal (CLO)

**Summary:** Pre-#3286 lopsided state was a DSAR Art. 15 completeness gap and an Art. 5(1)(a) transparency gap (Privacy Policy 4.7 promises retention "while account active" but cc assistant turns expired with SDK session). #3286 closed the export-completeness gap; the transparency defect (docs don't acknowledge cc path) remains. Cross-tenant dedup failures are Art. 33/34 notifiable breach surface — invariants must be tested with synthesized two-user-two-conversation matrix. GDPR-gate invocation required at plan 2.7, work 2 exit, ship 5.5 (third invocation added for breach-notification surface). Privacy Policy §4.7 + DPD activity #10 need a one-sentence refresh in PR-C.

## Capability Gaps

None. CTO, CPO, CLO confirmed all primitives exist:

- Engineering: `supabase()` service client, `updateConversationFor` ownership probe, `reportSilentFallback`, `mirrorWithDebounce`, RLS policy on `messages` via `conversations.user_id`, `status`/`usage` columns from migration 040.
- Product: `spec-flow-analyzer` and `ux-design-lead` available for PR-B banner/marker design.
- Legal: `legal-document-generator`, `legal-compliance-auditor`, `/soleur:gdpr-gate` skill cover PR-C scope.

Evidence: `grep -n "saveAssistantMessage\|onTextTurnEnd" apps/web-platform/server/cc-dispatcher.ts` confirms the persistence hook. `gh pr view 3286` confirms merge. `apps/web-platform/supabase/migrations/040_message_status_aborted.sql` confirms `status`/`usage` columns exist. `apps/web-platform/server/cc-dispatcher.ts:183-197` defines `mirrorWithDebounce`. Cross-tenant RLS exists per `apps/web-platform/supabase/migrations/001_initial_schema.sql:68-98`.
