# Learning: a "message-free" verification invariant was structurally vacuous — trace the row producer, route the mechanism fork to the CTO

## Problem

The `feat-live-verify-harness` plan (deepen finding, data-integrity P0-1) mandated a
**message-free** rail-verification check: the harness would "start a fresh conversation,
assert it appears in the Recent Conversations rail, and NEVER send a message" — because a
`messages` row can spawn a WORM-undeletable `action_sends` child (permanent prod-row
accumulation on a persistent synthetic principal).

During /work, tracing the actual producer showed the invariant was **structurally vacuous**:

- `apps/web-platform/server/ws-handler.ts:2164` — `conversations` rows are materialized
  **lazily on the first user message** (`createConversation` at `:2191`, inside
  `if (!session.conversationId && session.pending)`). Session-start only sets
  `session.pending`. **A strictly message-free run creates no `conversations` row**, so
  nothing ever enters the rail and the #5391/#5436 realtime-timing path is never exercised.
- `messages` is NOT in the `supabase_realtime` publication (mig 039); `conversations` IS
  (mig 034). The rail's realtime feed observes the `conversations` INSERT — which only the
  message path produces. So a message-free harness is **false confidence**: green, but
  blind to the exact regression class it exists to catch.

The WORM premise was also narrower than stated: `action_sends.message_id → messages` is
`NO ACTION`/RESTRICT + WORM no-delete trigger (mig 051:103,144-154), but the **sole**
`action_sends` writer is `server/action-sends/write-action-send.ts` (agent scope-gated
action sends). A plain user message writes **no** `action_sends` row.

## Solution

The plan-vs-codebase contradiction was an **engineering mechanism decision with material
trade-offs**, so per the `/work` architectural-fork HARD GATE it was routed to the
**`soleur:engineering:cto` agent** (NOT the non-technical operator). The CTO ruled
**Option B (message-minimal)** and replaced `I-message-free` with **`I-action-send-free`**:

- The harness sends **exactly one benign user message** through the browser UI (the only
  path that produces the rail's realtime INSERT), then tears down.
- The synthetic principal holds **zero `scope_grants`**, so the agent Send route 403s
  before `write-action-send.ts` can run — **no `action_sends` row is reachable by
  construction**. Teardown also asserts the principal has 0 `action_sends` before deleting
  (else `CANT-RUN:CANT-TEARDOWN-has-action-sends+#5463`; escalate, never force-delete).
- Q3 correction from the CTO: `getCurrentRepoUrl` reads **`workspaces.repo_url`** (ADR-044),
  not `users.repo_url`; the seed ladder must set `workspaces.repo_url` (the `seed-qa-user.sh`
  gap — it sets `repo_status` but not `repo_url`) or `createConversation` aborts.

Recorded in ADR-064 (amends the draft; the `I-message-free` → `I-action-send-free` swap).

## Key Insight

When a deepen-derived invariant contradicts the code, **trace the actual producer before
coding** — a safety invariant ("never write X") can be structurally incompatible with the
feature's own success condition ("observe the row that only writing X produces"). The
binding "which mechanism" decision is the CTO's call, not the operator's: route it to the
`cto` agent with file:line evidence + candidate options, then implement exactly what it
returns and record it in an ADR. The cheapest verification of a "never do X" invariant is
to ask: *can the feature succeed at all without doing X?*

Second-order: secret redactors anchored on a token's "shape" miss structurally-encoded
secrets. `@supabase/ssr` stores the auth cookie as `base64-<base64url(JSON session)>` (no
JWT dots) embedding access_token + refresh_token + email — a JWT/email/`sb-*-auth-token=`
ruleset misses it and the chunked `…-auth-token.0=` name. Scrub the `base64-<blob>` shape
and the `.N` chunk suffix explicitly.

## Session Errors

- **`test-all.sh` reported exit 0 while a bun suite FAILed internally** ("120/121 suites
  passed" + `[FAIL] plugins/soleur`, `1 fail`). Recovery: grepped the log for
  `[FAIL]`/`N fail` and found `components.test.ts` failing; fixed + re-ran green.
  **Prevention:** never trust `test-all.sh`'s exit code — always grep the log for
  `\[FAIL\]`/`[0-9]+ fail`. Reinforces
  `2026-05-18-test-all-tail-masking-and-monitor-exit-condition-tightness.md`.
- **`components.test.ts` backtick-link gate fired on a SKILL.md app-path** written as
  `` `scripts/bootstrap-live-verify.sh` `` — the regex anchors on backtick+`scripts/` and
  cannot tell a skill-relative asset from an app path. **Prevention:** in SKILL.md bodies,
  reference app scripts by their full `apps/web-platform/scripts/…` path (starts with
  `apps/`, so the regex no longer matches), or use a proper markdown link.
- **Bash tool CWD drift** — a prior `cd apps/web-platform` persisted and a later relative
  `sed -i scripts/live-verify/run.ts` hit "No such file or directory". **Prevention:** use
  worktree-absolute paths (already an AGENTS guideline); one-off.
- **`git grep` missed new untracked files** for the AC1 structural check (exit 1 stopped
  the `&&` chain). **Prevention:** use `grep -rn` for pre-commit untracked-file greps.
- **My own comment contained the literal `playwright-core`** which AC1's grep forbids;
  caught by re-running the AC grep before commit. **Prevention:** when an AC is a literal
  grep-for-zero, the forbidden string must not appear even in prose/comments.
- **Assumed `redact.test.ts` was greenfield** — it was already committed (AC3). Recovery:
  read it (it already covered AC3); added only the new base64-blob + chunked-cookie cases.
  One-off (resume-context staleness).

## Tags
category: integration-issues
module: live-verify-harness
issue: 5452
adr: ADR-064
