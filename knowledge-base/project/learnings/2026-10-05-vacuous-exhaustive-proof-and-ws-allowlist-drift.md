# Learning: A compile-time exhaustiveness proof typed `new Set<Union>` can never fail — and 11 WS frame types were silently dropped on main

## Problem

Brainstorming a "generic Working… status" UX complaint surfaced the real cause:
`apps/web-platform/lib/ws-known-types.ts`'s `KNOWN_WS_MESSAGE_TYPES` allowlist
was missing 11 `WSMessage`/`ClosePreamble` union members (`reasoning_narration`,
`turn_summary`, `command_stream`, `stream_replay`, `autonomous_disclosure`,
`autonomous_disclosure_response`, `autonomous_posture`, `abort_turn`,
`resume_stream`, `membership_revoked`, `revocation_notice`). `ws-client.ts`
drops non-allowlisted frames before Zod parse (`op: "ws-unknown-event"`), so the
narration feature shipped in #5363 could never reach `liveNarration` — the
"Still working…" fallback rendered permanently, reading as a UX deficiency.

Two layers made the drift invisible:

1. **Vacuous compile-time proof.** `new Set<AllowedWSMessageType>([...])`
   types the set's elements as `AllowedWSMessageType`, so
   `SetToUnion<typeof KNOWN_WS_MESSAGE_TYPES>` is always the full union and both
   `Exclude`s in `_Exhaustive` are always `never`. The `satisfies` +
   proof-const pair can never fail — it checks what the constructor was TOLD to
   be, not what the literal contains.
2. **Self-consistent guard test.** `ws-known-types-guard.test.ts` pins the same
   hand-maintained list, so it passes while the allowlist is wrong — the test
   asserts agreement between two copies of the same mistake.

## Solution

- Verify before asserting: the subagent flagged it as "likely"; confirming took
  two commands — `git show main:lib/ws-known-types.ts` (list contents) +
  `comm -23 <(union members from types.ts) <(allowlist entries)` (the exact
  missing set) + reading the drop site in `ws-client.ts`.
- Fix pattern (spec `feat-concierge-activity-trail` FR1): derive the expected
  set FROM the union at test time (reflect over `WSMessage["type"]` via a
  schema/registry that is itself union-derived, or test-parse each union
  member through the guard) — never compare a hand-maintained literal to itself.
- Pattern class filed as machinery issue #9516 (sweep for the same shape
  elsewhere: `Exclude<` proofs over `new Set<UnionType>` literals; tests
  asserting agreement between two hand-maintained copies).

## Key Insight

A guard is only a guard if it can fail. "Compile-time exhaustive" is a claim
about WHERE the generic parameter sits: `new Set<Union>(literal)` widens the
literal to the union before any check runs — the check then compares the union
to itself. The same class exists at value level whenever a test pins a literal
that is also the production constant (self-consistency, not verification).
`cq-assert-anchor-not-bare-token`'s mutation clause already names the general
rule — *mutation-test every new assertion: if deleting the guard leaves the
suite green, it pins nothing* — this file records the type-level instance.

Secondary: a UX complaint ("status is generic") can be a telemetry bug wearing
a UX costume. The debug stream showed rich activity because `debug_event` WAS
allowlisted; the user-facing narration channel was the one being dropped.
Symptom location ≠ defect location.

## Session Errors

1. `gh issue create` blocked: `--body-file` passed a relative path; the filing
   gate resolves it against the hook's CWD. **Prevention:** always pass a
   literal absolute path to `--body-file`.
2. `gh issue create` blocked: `Fix-Size: ~12 files` — the gate's regex needs
   literal `N lines / M files` digits, and `User-Impact:` must contain a word
   from `lib/user-surface-taxonomy.txt` (route/page/screen/component/…).
   **Prevention:** read the two-line exit format exactly; "measured" means
   digits, not `~`.
3. An exec call containing BOTH a file-fix and `gh issue create` was rejected
   pre-execution — the fix never ran, and retrying the filing re-read the old
   body. **Prevention:** update the body file in its own call (the gate's own
   message says this — it was ignored the first time).
4. First `git push` remote-rejected `(failed)` with no detail; retry pushed
   cleanly. **Prevention:** transient — retry once before investigating.
5. `xdg-open` on a PNG directory hit a nautilus D-Bus proxy error on Omarchy.
   **Prevention:** `imv -d <dir>` is the configured image/png handler — open
   image sets with `imv`, not the file manager.

## Tags
category: workflow-patterns
module: apps/web-platform (chat ws protocol); .claude/hooks (filing gate)
related: knowledge-base/project/specs/feat-concierge-activity-trail/spec.md; issue #9515, #9516; spec feat-reasoning-chat-boxes (#5363)
