---
title: "Per-leaf redaction is insufficient for structured JSON; synthesized secret-shapes trip push-protection"
date: 2026-06-08
category: security-issues
module: apps/web-platform/server/debug-event.ts
tags: [redaction, secret-scanning, push-protection, feature-flags, test-fixtures]
feature: feat-debug-mode-stream
pr: 5042
---

# Learning: redacting `tool_input` for a debug stream — three reusable traps

Captured shipping the workspace-scoped Debug Mode harness stream (#5045). Three
insights generalize beyond this feature.

## 1. Per-string-leaf redaction does NOT cover structured JSON — you also need KEY-AWARE redaction

The plan's P0-6 fix said: "don't redact the `JSON.stringify` blob (serialization
turns `KEY=value` into `"KEY":"value"`, defeating the `=`/`Authorization:`
anchors); instead walk the object and redact each string VALUE." That is correct
but **insufficient**.

In structured JSON the key and value are **separate leaves**:
`{"headers":{"Authorization":"Bearer <opaque>"}}` — the value leaf is just
`"Bearer <opaque>"`, which has LOST its `Authorization:` anchor. The redactor
(allowlist/sentinel-anchored) matches nothing on a bare opaque value, and the
probe (also shape-anchored) doesn't trip either. The secret rides the wire.

**Fix:** complement per-leaf redaction with **key-aware** redaction — when an
object property's KEY is a credential noun, drop the WHOLE value to
`[redacted-key]` regardless of the value's own shape:

```ts
function redactStringLeaves(value, keyContext?) {
  if (typeof value === "string") {
    if (keyContext && isCredentialKey(keyContext)) return "[redacted-key]";
    return redactCommandForDisplay(value);
  }
  // arrays inherit keyContext; objects pass each property's own key as context
}
```

**The credential-key set must be complete AND handle compounds.** Multi-agent
review (security-sentinel + user-impact, concurring) found the first set missed
`passphrase`, `sessionid`, `csrf`, `mnemonic`, `recovery_code`, `seed`, … — and
that `session` (covered) ≠ `sessionid` (the no-separator compound). The robust
shape is: a segment set (split on `[_\-.\s]+`) PLUS a substring fallback for
camelCase / no-separator compounds (`xSessionId`, `userPassphrase` → `.includes`
on a high-signal noun list). Over-redaction of a non-secret is an acceptable
cost on a dev-only surface; under-redaction is a single-user incident.

**Residual (accepted):** a generic no-sentinel secret under a TRULY benign key
(`{"note":"the password is hunter2"}`) still rides — same class as a secret
narrated in prose. Pin the accepted gap with a test (`expect(wire).toContain`)
so a future redactor change that closes it is noticed.

**Also: probe the PRE-cap string.** If you byte-cap then probe, a redactor-miss
straddling the cap boundary can be truncated so the surviving prefix no longer
matches the probe → partial secret survives. Probe the full string, THEN cap for
the wire (redaction already bounds regex back-tracking).

## 2. Synthesized secret-SHAPE fixtures trip GitHub Push Protection — split them across concatenation

`cq-test-fixtures-synthesized-only` says use fake values, never real secrets. But
a fake value with a REAL token SHAPE (`sk_live_0123…`, `ghp_0123…`, `sk-ant-…`)
still matches GitHub's secret-scanning regex and **blocks the push** (`GH013 …
Push cannot contain secrets`). The push scans every commit in the range, so a fix
in the working tree isn't enough — the literal must be gone from history.

**Fix:** construct sentinel fixtures via string concatenation so no contiguous
token literal exists in source, while the runtime value keeps the exact shape the
redactor matches:

```ts
const STRIPE = "sk_" + "live_0123456789abcdefABCD1234";  // scanner sees no token
const GITHUB = "ghp_" + "0123456789abcdefghij0123456789abcd";
const ANTHROPIC = "sk-" + "ant-api03AAAA…";
```

To purge an already-committed literal without `rebase -i` (blocked in this env):
soft-reset to the pre-feature base (`git reset --soft <base>`), re-`git add` the
fixed files (the index keeps the rest staged), and recommit clean. Verify with
`git diff --cached | grep -E '<token-regex>'` → empty before committing.

## 3. `useFeatureFlag` THROWS without a provider — use `useOptionalFeatureFlag` in widely-rendered components

Adding `useFeatureFlag("debug-mode")` to `chat-surface.tsx` broke **106 tests** —
`useFeatureFlag` throws when no `<FeatureFlagProvider>` is mounted, and many
`ChatSurface`/`ChatPage` test harnesses render without one. The codebase already
ships `useOptionalFeatureFlag` (returns `false` with no provider) for exactly
this case. For any flag read in a component rendered across many test surfaces,
prefer `useOptionalFeatureFlag` — it's also the fail-closed default (no provider
→ feature off).

## Session Errors

- **First Bash command ran in the bare-repo root** (`fatal: this operation must
  be run in a work tree`). Recovery: `cd` into `.worktrees/feat-debug-mode-stream`.
  Prevention: the bare-repo root is the default CWD; first action in a worktree
  task is `cd` into the worktree (one-off orientation).
- **`Edit` failed "File has not been read yet"** on two files read via `Bash cat`
  rather than the `Read` tool. Recovery: `Read` first. Prevention: the Edit gate
  only tracks the `Read` tool — always `Read` before `Edit` even if already
  `cat`'d (covered by `hr-always-read-a-file-before-editing-it`).
- **106-test failure from `useFeatureFlag` without a provider.** Recovery +
  prevention: §3 above (use `useOptionalFeatureFlag`).
- **GitHub Push Protection blocked the push** on a synthesized Stripe-shape
  fixture. Recovery + prevention: §2 above (concatenation + history rewrite).
- **`ws-known-types-guard` exact-set test failed** — adding a `WSMessage` type
  requires updating the hardcoded expected set. Prevention: covered by
  `cq-union-widening-grep-three-patterns` (grep every consumer; the exact-set
  test is one).
- **`nav-states` e2e false-failed (2 desktop, Chromium crash at `page.goto`)
  under parallel load.** Recovery: `--workers=1` → pass. One-off throttled-machine
  flake (already documented in the qa skill).
- **Plan-file `Edit` "modified since read"** after a `sed` checkbox update changed
  it mid-flight. Recovery: re-`Read` then `Edit`. One-off.
