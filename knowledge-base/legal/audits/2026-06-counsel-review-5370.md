---
title: "Counsel review audit — #5370 (Concierge turn_summary durable narration; PA-2 amendment)"
type: counsel-review
date: 2026-06-15
issue: 5370
pr: 5363
status: SIGNED-OFF (CLO-agent-attested, Soleur-as-tenant-zero v1)
signed_off_at: 2026-06-15
signed_off_by: "Soleur CLO agent (v1 internal counsel-review attestation; operator retains optional veto)"
disposition: DISCHARGED
re_evaluation_triggers: "First arms-length (non-Soleur) Web Platform user OR any multi-tenant workspace flag flip (TEAM_WORKSPACE_INVITE_ENABLED) — at which point the cross-tenant-prose residual (#5384) becomes a live, structural control requirement, NOT a directive-only posture; EEA-out hosting change; regulated-industry onboarding"
---

# Counsel review audit — #5370 (Concierge `turn_summary` durable narration)

Load-bearing evidence for the `/ship` Phase 5.5 Counsel-Review CLO-Attestation gate on PR #5363 (branch `feat-reasoning-chat-boxes`, #5370). This is the v1 *internal* CLO-agent attestation under the Soleur-as-tenant-zero posture. Each legal-doc claim was cross-checked against the implementing migration / RPC / TS body (PR #4353/#4558 drift-class discipline). External counsel re-review is reserved for the frontmatter `re_evaluation_triggers`.

**Change under review:** the Concierge (cc-router) runtime gains two always-registered MCP tools — `narrate` (transient live status line, never persisted) and `summarize` (one durable `messages` row, `message_kind='turn_summary'`, migration 105). The legal artifacts frame this as an **amendment to existing Processing Activity 2** (conversation runtime / `messages`), not a new PA.

**Implementing files cross-checked:**
- `apps/web-platform/supabase/migrations/105_turn_summary_message_kind{,.down}.sql`
- `apps/web-platform/server/messages/insert-turn-summary.ts`
- `apps/web-platform/server/dsar-export.ts` (redaction keying + allowlist, ~L396-434, ~L621-646)
- `apps/web-platform/server/cc-dispatcher.ts` (`emitNarration` ~L872-934; `redactNarrationOrDrop` ~L824-858; directive ~L312-337)

---

## Per-claim verdict

### Claim 1 — AMENDMENT to PA-2, not a new Processing Activity — **CONFIRMED**

Migration 105 is `ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS message_kind text` (additive, nullable, no default) plus a CHECK pinning `turn_summary` → `role='assistant'`. The row reuses the existing `messages` table, RLS (mig 059), retention, and erasure cascade — no new substrate. The A30 register amends PA-2 §(b) Purposes, §Lawful basis, and §(g) TOMs (14)-(16) rather than minting a PA. Code and prose agree: reuse of the registered runtime, not a new activity.

### Claim 2 — Lawful basis Art. 6(1)(b) (same as parent conversation) — **CONFIRMED**

The summary is an agent-authored record of the conversational work the user requested; it is part of providing the contracted service. A30 PA-2 Lawful-basis cell, Privacy Policy §4.7, GDPR Policy §3.12, DPD §2.3(i) all assert Art. 6(1)(b) consistently. Sound: a faithful by-product record of user-requested work is "necessary for performance of the contract" on the same footing as the prompt/response rows it summarizes. No new basis required.

### Claim 3 — Art. 22 negative determination — **CONFIRMED**

The feature produces descriptive prose ("Fixed the side panel layout") about work already performed; it makes no decision *about the data subject* and produces no legal or similarly significant effect. The directive (cc-dispatcher.ts ~L329-333) constrains `summarize` to an outcome description of the just-completed turn. A30 PA-2 Lawful-basis cell, PP §4.7, GDPR §3.12, DPD §2.3(i) state the negative determination identically. Accurate.

### Claim 4 — User's-own-data; exports UN-redacted because Art-15(4) keys on `user_id` — **CONFIRMED (code-verified, the load-bearing claim)**

- `insert-turn-summary.ts` L77 sets `user_id: input.founderId` (NOT omitted — contrast the draft-card branch), and the file's header comment states this is *because* DSAR author-redaction keys on `user_id`.
- `dsar-export.ts` L624-628: `isSubjectAuthored = rawUserId === expectedUserId || (rawUserId === null && LEGACY_NULL_IS_SUBJECT)`. The redaction predicate keys on `user_id`, not `role`. A subject-authored row is added to `subjectAuthoredMessageIds` and `redactRow(row, !isSubjectAuthored, …)` is called with `false` → no redaction applied.
- Therefore a `turn_summary` row, inserted with `user_id=founderId`, is subject-authored in the founder's own export and returned un-redacted. `message_kind` is in `MESSAGE_NON_REDACT_ALLOWLIST` (L419-434, structural discriminator); the summary BODY lives in `content`, a `MESSAGE_REDACT_FIELDS` member that is only nulled for *foreign-author* rows. Code matches every prose claim in PP §4.7 / A30 TOM (16) / DPD §2.3(i).

### Claim 5 — No new recipient / sub-processor / third-country transfer — **CONFIRMED**

The row lands in the existing Supabase `messages` table (eu-west-1, Ireland) on existing Hetzner compute (hel1, Finland). `emitNarration` writes via `insertTurnSummary` → `getFreshTenantClient(founderId)` (same Supabase plane). No egress to any new processor; `narrate`/`summarize` are in-process tools. PP §4.7, GDPR §3.12, DPD §2.3(i), A30 §(d)/§(e) (unchanged) all assert "no new recipient / sub-processor / third-country transfer." Accurate.

### Claim 6 — Art. 17 erasure inherited (conversation-delete + account-delete cascade) — **CONFIRMED**

The row is an ordinary `messages` row keyed by `conversation_id`; the mig-001 FK `messages.conversation_id → conversations(id) ON DELETE CASCADE` and the account-delete cascade both reach it with no new cascade code. A30 PA-2 §(f) Retention (unchanged — "Erasure requests under Art. 17 honoured at row granularity") and the §(b)/TOM(16) additions, plus PP §4.7 / DPD §2.3(i) ("cascade-deleted on account deletion via foreign key `ON DELETE CASCADE`"), state inheritance correctly. No new erasure surface claimed or needed.

### Claim 7 — Cross-tenant prose residual honestly represented (no overclaimed control) — **CONFIRMED**

This is the one place where overclaiming would be a material misstatement, and the docs do NOT overclaim:
- `redactNarrationOrDrop` (cc-dispatcher.ts L824-858) runs `formatAssistantText` + a secret-shape probe and **drops the whole narration on trip** (returns `null`, fail-loud to Sentry). It scrubs host/sandbox paths and secret SHAPES only — it does **not** parse or scrub another tenant's prose. The code carries no cross-tenant content control.
- `assertWriteScope` (called at `emitNarration` L903) is, per its own comment, a "forward-compat write-scope seam (no-op today)" — not a control.
- A30 TOM (15) states verbatim: *"the redaction probe (14) does NOT scrub cross-tenant prose — the directive (b) is the operative control"* and *"`assertWriteScope` is a no-op forward-compat seam, NOT a control today."* The compliance-posture #5370 entry and DPD §2.3(i) repeat this honestly. The operative controls named — (a) solo-pinned tenant client `getFreshTenantClient(founderId)` with `workspace_id=founderId`, (b) the system-prompt directive forbidding naming out-of-context entities (cc-dispatcher.ts L334-337), (c) PR-time `user-impact-reviewer` — all exist in code/process.
- The structural residual is tracked at **#5384** (verified OPEN: "Tripwire: structural cross-tenant-prose control for turn_summary (multi-tenant)").

The representation is honest: a directive-only + RLS-solo-pin posture, with the redaction probe correctly described as a secret-shape backstop and NOT a cross-tenant control. Sound for the v1 single-tenant (Soleur-as-tenant-zero) posture; the frontmatter re-evaluation trigger flags that this residual becomes a structural requirement on first arms-length user or any multi-tenant flag flip.

---

## Cross-document consistency

| Artifact | Section | Art. 6(1)(b) | Art. 22 neg. | user_id un-redact | no new processor | Verdict |
|---|---|---|---|---|---|---|
| `article-30-register.md` | PA-2 (b)/lawful/(g)14-16 | ✓ | ✓ | ✓ | ✓ | consistent |
| `privacy-policy.md` | §4.7 | ✓ | ✓ | ✓ | ✓ | consistent |
| `gdpr-policy.md` | §3.12 | ✓ | ✓ | ✓ | ✓ | consistent |
| `data-protection-disclosure.md` | §2.3(i) | ✓ | ✓ | ✓ | ✓ | consistent |
| `compliance-posture.md` | #5370 entry | ✓ | ✓ | ✓ | ✓ | consistent |

All five artifacts carry the "amendment-not-new-PA" framing, the Art. 22 negative determination, and the honest cross-tenant-prose residual. No internal contradiction found.

## Eleventy-mirror note (non-blocking observation, not a misstatement)

The GDPR Policy Eleventy mirror (`plugins/soleur/docs/pages/legal/gdpr-policy.md`) carries the §3.12 body (5 `turn_summary` hits). The Privacy Policy and DPD Eleventy mirrors were NOT updated with the §4.7 / §2.3(i) *prose* in this PR. This does **not** fail the enforced consistency gate (`apps/web-platform/test/legal-doc-consistency.test.ts`), because:
- the §4.7 / §2.3(i) edits extended existing sections without adding headings → heading-sequence parity holds;
- all three mirror Last-Updated dates already read "June 15, 2026" (same-day #5325 ship) → date-parity holds.

It matches the documented legacy-drift posture (test §lines 12-22: heading-sequence + sentinel, not full body equality). It is a documentation-completeness item for the operator's awareness, not a misstatement of the implementation, and therefore not an attestation blocker. (Recommend folding the §4.7 / §2.3(i) body into those two mirrors in a future legacy-drift cleanup, per the test's own follow-up note.)

---

## Disposition: **DISCHARGED**

All seven attested claims CONFIRMED against the implementing code. No prose misstates the migration / insert / DSAR / dispatcher behavior. The cross-tenant-prose residual is honestly scoped and tracked (#5384). No `[DRAFT — pending CLO/counsel review]` markers were added by this PR; none to clear.

The legal-doc amendments are DISCHARGED for the v1 Soleur-as-tenant-zero posture. The operator retains an optional veto; external counsel re-review is reserved for the frontmatter re-evaluation triggers (first arms-length user, any multi-tenant flag flip, EEA-out, regulated industry).
