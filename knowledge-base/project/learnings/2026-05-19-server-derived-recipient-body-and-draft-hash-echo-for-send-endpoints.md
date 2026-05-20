---
name: server-derived-recipient-body-and-draft-hash-echo-for-send-endpoints
description: Send-class endpoints must derive bodyContent + recipient server-side from the source row, and confirm payloads must echo a server-issued draft_preview hash; approval_signature must bind the full content surface (body, recipient, template, tier), not just the typed value. Defeats client-controlled-signature, Send→Edit→Send race, and double-send via WORM UNIQUE.
metadata:
  type: feedback
---

# Server-derived recipient/body + draft-hash echo for send-class endpoints

## Context

PR-H (#4077) — trust-tier external classes wiring — landed dashboard
Send/Edit/Discard routes, the typed-confirm modal, and the `action_sends`
WORM signature table. The 11-agent brand-survival-extended review
surfaced 9 P1 findings; the dominant class was a **client-trusted
content surface** that let a compromised browser session bind the GDPR
Art. 5(2) accountability artifact to content the founder never saw.
This learning generalizes the fix shape so future send-class endpoints
(PR-I digest emitter, future template-authorization writes) do not
re-introduce the same vector.

Pattern files: `apps/web-platform/app/api/dashboard/today/[id]/send/route.ts`,
`apps/web-platform/server/action-sends/write-action-send.ts`,
`apps/web-platform/components/dashboard/today-card.tsx`,
`apps/web-platform/supabase/migrations/051_action_class_widening_and_action_sends.sql`.

## The four invariants

A send-class endpoint that writes a WORM accountability row MUST honor
ALL of:

1. **Server-derive the signed surface.** `bodyContent` and
   `recipientIdentifier` come from the source row (`messages.draft_preview`,
   future producer-table columns), NOT from the request body. The
   request body carries ONLY the signature surface: `confirmed_typed`,
   `typed_value`, `expected_draft_preview_hash`. A compromised page or
   automated client cannot bind the approval signature to content the
   server never SELECTed.

2. **Bind the approval signature to the full content surface.**
   `approval_signature_sha256` covers `{founderId, messageId, typedValue,
   perSendBodyHash, recipientHash, templateHash, tier}`. `ts` is
   intentionally OMITTED — the signature must be reproducible from the
   persisted row; `clicked_at` provides the wall-clock anchor
   separately. A row mid-tampered to a different body/recipient/tier
   will produce a hash that does not match the stored signature.

3. **Echo a server-issued draft hash on confirm.** The 409
   `requires_confirmation` response includes
   `expected_draft_preview_hash = sha256(message.draft_preview)`. The
   confirm POST MUST echo it; the server re-SELECTs the row, recomputes
   the hash, and rejects with a fresh 409 on mismatch. Defeats the
   Send→Edit→Send race: a sibling tab editing the draft between the
   first 409 and the confirm POST trips the hash and forces re-
   confirmation against the updated content.

4. **Fail-closed on double-write via WORM UNIQUE.** `UNIQUE(message_id)`
   on the WORM signature table is the only safe path for double-send
   prevention. WORM tables cannot rectify duplicates by overwrite. A
   transaction wrap around (INSERT + parent-table archive UPDATE)
   solves the orphan but NOT the double-click — UNIQUE solves both.
   The INSERT fails with 23505 unique_violation on the second click;
   the route detects the code and returns 409 already_sent so the UI
   can reflect the row that the prior click already wrote. PR-I
   legitimate retries (delivery-failure recovery) MUST extend to
   `UNIQUE(message_id, client_idempotency_key)` — the absence of an
   idempotency key forces a design decision rather than a silent
   duplicate.

## What this is NOT

- **Not a defense against cookie compromise.** An attacker holding the
  founder's session cookie can drive the typed-confirm modal end-to-
  end; the typed_value gate is UX (TOM), not security. The security
  layer is the cookie itself (httpOnly + short-lived JWT + MFA on
  /login). The four invariants above defend against compromised-page-
  but-not-compromised-session vectors (XSS, malicious extension, page-
  level injection) and against bot-with-cookies binding signatures to
  client-fabricated content.
- **Not a substitute for HMAC-bound nonces.** A truly bypass-resistant
  programmatic-agent gate needs a server-issued single-use nonce with
  a server secret. The hash-echo approach above defeats the Send→Edit→
  Send race AND the local-state divergence, but a sophisticated agent
  with cookies can still synthesize a valid first POST → read 409 →
  echo the hash. Document this honestly in the route's trust-model
  comment; revisit if programmatic-agent attack surface becomes first-
  class.

## What multi-agent review caught that single-agent didn't

Three agents independently flagged the same defect class with non-
overlapping framings:

- **user-impact-reviewer** named the user-facing vector ("draft on
  Today section with Send button that sends to wrong recipient via
  template_hash collision, sends without consent via typed-confirm
  client-side-only check") — this is the vector that the plan §60
  `## User-Brand Impact` enumeration MISSED (the plan focused on typo
  fall-through + classifier collision; user-impact-reviewer found the
  Send→Edit→Send race and the client-trusted-recipient-identifier
  path).
- **security-sentinel** named the GDPR Art. 5(2) accountability gap —
  signature payload omitted body/recipient/template, so a founder
  later disputing "I never approved THIS body to THIS recipient"
  cannot be answered by signature replay.
- **agent-native-reviewer** named the parity gap — programmatic
  clients can POST `confirmed_typed=true, typed_value=SEND` without
  a human keystroke. The review correctly flagged the absence of a
  nonce; the operator-design decision was that cookie compromise is
  the broader vector and the typed-confirm gate is UX, not security.

The convergent finding-pattern is diagnostic: when 3 agents with
different framings hit the same code surface, the defect is
structural, not interpretive.

## Migration shape for the UNIQUE constraints

```sql
-- One active grant per (founder, action_class). Partial UNIQUE
-- enforces the invariant against concurrent-POST race in
-- grant_action_class where two requests both pass the
-- "no active grant" SELECT and both INSERT.
CREATE UNIQUE INDEX IF NOT EXISTS scope_grants_active_unique
  ON public.scope_grants (founder_id, action_class)
  WHERE revoked_at IS NULL;

-- One action_sends row per message. Double-click, archive-after-write
-- split-brain, or retry → 23505 unique_violation → 409 already_sent
-- at the route layer.
CREATE UNIQUE INDEX IF NOT EXISTS action_sends_message_unique
  ON public.action_sends (message_id);

-- Defense-in-depth: messages.action_class carries the same enum-
-- absence regex as scope_grants and action_sends. Producers write
-- the column from envelope payloads; the CHECK closes the gap that
-- TS literal-union narrowing leaves at indirect routes.
ALTER TABLE public.messages
  ADD CONSTRAINT messages_action_class_not_locked
  CHECK (action_class IS NULL OR action_class !~ '^(payment|legal|auth)\.');
```

## Verify SQL must cover the SECURITY DEFINER + search_path pin

`cq-pg-security-definer-search-path-pin-pg-temp` requires every
SECURITY DEFINER function to pin `search_path = public, pg_temp`. The
migration body sets the pin correctly; the verify SQL must also
ASSERT it post-deploy so a future regression dropping the pin trips
CI:

```sql
SELECT 'fn_search_path_pinned',
       CASE WHEN p.proconfig @> ARRAY['search_path=public, pg_temp']
            THEN 0 ELSE 1 END::int
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public' AND p.proname = '<fn_name>';
```

Without this assertion the structural invariant is documented but not
enforced.

## Session Errors

- **Working-directory drift across Bash calls** — Tool-call CWD
  persists; a relative `cd .worktrees/...` from a now-changed CWD
  failed silently as ENOENT.
  Recovery: switched to absolute paths derived from `git rev-parse
  --git-dir`.
  Prevention: in long-running sweeps, chain `cd <abs-path> && <cmd>`
  per invocation or treat CWD as load-bearing state. AGENTS.core.md
  already encodes this for worktree pipelines under
  [[hr-when-in-a-worktree-never-read-from-bare]] — extend mental
  model to also cover post-cd CWD persistence.

- **Agent false-negative claim — data-integrity-guardian** —
  Claimed "No verify SQL ships with migration 051" as a P1; the file
  was in the diff list.
  Recovery: cross-checked the agent's claim against
  `git diff --name-only origin/main...HEAD` before applying any fix.
  Prevention: the review skill already encodes the "Before reporting
  a broken link or missing file, reviewer agents MUST verify via Glob
  or Read" rule — surfacing this rule into the agent's own header
  would close the gap.

- **TaskCreate reminders fired 3+ times during the linear fix sweep**
  — Workflow noise; the agent considered + rejected TaskCreate for a
  9-unit linear sweep but the system had no signal that the
  consideration had occurred.
  Recovery: continued without TaskCreate; sweep landed cleanly.
  Prevention: when explicitly rejecting a system suggestion, emit a
  one-line rationale (e.g., "skipping TaskCreate — linear sweep,
  state lives in conversation") so the reminder logic can stop
  firing.

## Cross-references

- [[ADR-034-action-class-registry-static-literals-and-enum-absence]]
  — the registry pattern that this learning's invariants protect at
  the consumer layer.
- [[2026-05-16-migration-mandates-must-have-wired-call-sites-in-same-pr]]
  — sibling pattern for "the migration's prose statement of an
  obligation is not evidence the obligation is satisfied".
- [[2026-04-15-multi-agent-review-catches-bugs-tests-miss]] — the
  meta-pattern for 3-agent-convergent findings being structural, not
  interpretive.
