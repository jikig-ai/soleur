---
date: 2026-06-15
category: bug-fixes
tags: [worm, security-definer, account-delete, gdpr-art17, suppression, gated-tools, action-sends, migration]
issue: 5325
pr: 5326
---

# Mirroring a WORM/audit precedent must carry its LATER fixes + verify its constraints actually apply

feat-agent-native-outbound-email (#5325) reused the `action_sends` WORM posture
(migration 051) for two new tables. Multi-agent review (user-impact +
data-integrity + security) caught four blockers, all the same shape: **a
precedent was copied at face value without checking (a) whether later migrations
fixed the precedent, or (b) whether the precedent's structural constraints are
satisfiable in the new call context.**

## The four traps

1. **`session_replication_role` in a new WORM-anonymise RPC re-introduces a
   fixed production outage.** Migration 051's `anonymise_action_sends` used
   `SET LOCAL session_replication_role = 'replica'` to bypass the WORM trigger.
   That GUC is **superuser-only (PGC_SUSET)**; on managed Supabase `postgres` is
   not superuser, so it raises `42501` and aborts the account-delete saga →
   **no account can be deleted** (#4696). Migration **087** eradicated it across
   every erasure RPC, switching to a privilege-free custom GUC `app.worm_bypass`
   (`SET LOCAL app.worm_bypass = 'on'` + a trigger fast-path
   `IF current_setting('app.worm_bypass', true) = 'on' THEN RETURN COALESCE(NEW, OLD)`).
   Copying mig 051's *pre-087* shape silently reintroduced the outage. **Lesson:**
   when mirroring a WORM/anonymise RPC, grep for the LATEST migration that
   touched that pattern (`git grep -l session_replication_role supabase/migrations`
   → 087 supersedes 051) and copy the fixed form. The trigger can stay
   `FOR EACH STATEMENT` — the GUC bypass works by *not raising*; the
   `RETURN COALESCE(NEW,OLD)` is harmless at statement level.

2. **`action_sends` is NOT reusable for agent-initiated sends — verify the FK is
   satisfiable, not just that the columns exist.** The plan's `[work-verified]`
   claim confirmed `action_sends` had the right *columns*, but `message_id` is a
   `NOT NULL` FK to `public.messages` with `UNIQUE(message_id)`, built for the
   founder-clicks-Send-on-a-draft path. Agent MCP tool handlers have **no
   `messages.id`** at tool-exec time (the tool runs inside the SDK iterator; the
   assistant message is persisted only at the `result` event with a fresh UUID;
   the tool closure carries `userId` only). The fork (reuse vs dedicated table)
   was routed to the **CTO agent**, which ruled a dedicated `outbound_sends` WORM
   table. **Lesson:** "the columns exist" ≠ "the table is reusable here" — trace
   whether the FK/UNIQUE constraints can be satisfied from the new call site.

3. **A keyed hash used for matching must canonicalize identically at write AND
   check.** `recipientHash` normalized with `trim().toLowerCase()` only, but the
   recipient *validator* used `normalizeEmail(extractAddrSpec(...))`. So
   suppressing `a@example.com` (bare) produced a different HMAC than a send
   addressed `Name <a@example.com>` (display-name form) → the C5 check silently
   passed and re-mailed an opted-out contact. `email_reply` hit this by default
   (inbound `from` headers carry a display name). **Lesson:** any
   hash-for-matching must run the SAME canonicalization on both sides; add a test
   asserting `hash("X <a@b>") === hash("a@b")`.

4. **A `gated` tool whose safety story is "the human sees X" must add a
   `buildGateMessage` case — the default is content-free.** The whole
   single-user-incident safety story was "the operator sees the exact recipient +
   body and approves." But `buildGateMessage` had no case for the new tools, so
   the operator saw `"Agent wants to use email_send. Allow?"` — no recipient, no
   body. The human-approval gate was decorative, and the body-hash binding was
   tautological (handler hashed its own input). **Lesson:** when adding a `gated`
   tool, the gate-message render IS the control — add a `buildGateMessage` case
   surfacing the decision-relevant fields, and test it is not the default string.

## Meta-lesson

All four passed `tsc` and the originally-written tests; only multi-agent review
(and the full-suite exit gate, which caught a 5th: the new user-FK tables were
unclassified in `DSAR_TABLE_ALLOWLIST`) surfaced them. At a single-user-incident
threshold, the review is a *required* merge gate, not optional polish — and the
reviewers must be given the threat model + the plan's User-Brand Impact section
so they can check "is this failure mode actually prevented by the code," not just
"does the code look reasonable." Related: [[2026-06-15-architectural-fork-decisions-route-to-cto-not-operator]].
