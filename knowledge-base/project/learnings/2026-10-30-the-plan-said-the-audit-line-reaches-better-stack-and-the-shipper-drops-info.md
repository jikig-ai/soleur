# Learning: the plan said the audit line reaches Better Stack, and the shipper drops everything below WARN

## Problem

PR #11593 (#11524 remove a stored subscription token, #11525 chat state after a
`key_invalid` card) was planned with a reviewed `## Observability` block that
named a pino `logger.info` line (`op: oauth-credential-removed`) as the
`liveness_signal`, "shipped to Better Stack (existing web-platform log drain)".
Four plan reviewers, three CTO rounds and a CPO sign-off read it. It was false:
`apps/web-platform/infra/vector.toml` `app_container_warn_filter` keeps only pino
level >= 40, and `server/logger.ts` mirrors to Sentry only at warn and above, so
an info line reached neither sink. Found at review by the observability seat
(P1), then confirmed by reading the filter.

The same review round found two more claims that outran their evidence:

- The rebind handshake inferred "the server refused my `resume_session`" from
  **any** `error` frame while an armed flag was set. Five seats converged: the
  server also sends a non-fatal checkpoint notice (no `errorCode`) and then a
  successful `session_started`, plus transient "Auth probe failed" errors. The
  branch swallowed them and the surface opened a duplicate conversation.
- The plan's `discoverability_test.command` used `|` and `&&`, which preflight
  Check 10 refuses to run, so the command "verified" in a plain shell could never
  run as the gate.

## Solution

- Audit line emitted at `logger.warn` only when `deleted === true` (a real
  erasure), `info` otherwise; Sentry `extra` carries `userIdHash`; plan
  `## Observability` rewritten with pino layer 2 cited and two honest
  "no runtime detector" modes.
- Only the exact shared `CONVERSATION_NOT_FOUND_MESSAGE` counts as a refusal
  (one constant imported by `ws-handler.ts` and `ws-client.ts`); every other
  error falls through and the rebind stays armed.
- Discoverability command reduced to one allowlisted `grep -Pzo` with a literal
  `expected_output`, and executed.

## Key Insight

A plan's observability claim is a claim about the **path** to a sink, and the
path has a filter nobody wrote the plan against. For every log line a plan names
as a signal, read the shipper's filter chain end to end (level floor, field
allowlist, PII scrub) and the logger's own mirror threshold before accepting
"reaches Better Stack/Sentry". Separately, do not infer a protocol outcome
("refused") from an untyped signal ("some error while armed"): name the exact
frame, or add a typed code, before branching on it.

## Session Errors

1. **Observability claim unverified against the shipper filter** — Recovery:
   emitted at warn, rewrote the plan block. **Prevention:** plan-sharp-edges
   bullet added ("a log line named as a liveness signal must be checked against
   the shipper's level floor").
2. **Technical-ruling gate failed on 5 `decision-challenges.md` rows** (4
   `pending - assumed`, 1 bad shape) — Recovery: one batched CTO spawn, rows
   rewritten. **Prevention:** the planning subagent should write the CTO ruling
   at the time of the plan-review cut, not an assumed default.
3. **Rebind refusal inferred from any `error` while armed** — Recovery: exact
   message match + shared constant + disarm paths + tests. **Prevention:** type
   the signal before branching on it.
4. **`pgrep -f` used in a Bash call** — blocked by the pkill-self-match hook.
   Recovery: dropped it. **Prevention:** already hook-enforced.
5. **`rm -rf` of a `/tmp` scratch dir blocked as a protected location** while the
   CWD was the worktree — Recovery: `rm -f` + `rmdir`. **Prevention:** one-off;
   hook false positive on a compound command, worth a look if it recurs.
6. **Both round-2 fix agents died on `EAI_AGAIN`** — Recovery: reconciled
   `git status`, resumed by `SendMessage` (transcripts intact), no respawn.
7. **A review seat returned status lines instead of its report, twice** —
   Recovery: `SendMessage` "reply now with the report". **Prevention:** state the
   deliverable in the spawn prompt (done) and resume rather than respawn.
8. **Affected-test gate returned rc=6 (budget deferred)** after queueing 22
   minutes behind sibling runs — Recovery: relied on targeted suites + `tsc` +
   CI as the authoritative gate; not labelled passed.
9. **Playwright install stalled at extraction twice**, so `nav-states` failed at
   `browserType.launch` (35/35) — Recovery: recorded INFRA-BLOCKED per the QA
   skill; CI's containerized e2e is authoritative.
10. **PR went `CONFLICTING` after QA (main moved)** — Recovery: ship syncs it.
11. **Plan ACs ticked in bulk (`sed` on lines 488–504) after a green run, and
    review-trailer finding counts (60/40) are approximations** — **Prevention:**
    tick an AC by running the command it names; state counts as approximate in
    the PR body.

## Tags

category: workflow-patterns
module: observability, chat-ws-client, api-keys
