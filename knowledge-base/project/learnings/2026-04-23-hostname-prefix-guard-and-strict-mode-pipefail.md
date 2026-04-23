---
category: security-issues
tags: [url-validation, bash, strict-mode, pipefail, guards]
date: 2026-04-23
pr: "#2840"
issues: ["#2839", "#2837"]
---

# Learning: Hostname-Prefix Guards Accept Subdomain Bypass; Command-Substitution Pipes Under `set -euo pipefail` Abort the Outer Script

## Problem

While bundling three MU1 ops fixes (#2837 / #2838 / #2839), two subtle defects were caught by parallel review agents on a green-tests PR:

1. **Hostname-prefix guard bypass.** The dev-cleanup guard in
   `apps/web-platform/infra/mu1-cleanup-guard.mjs` initially identified the
   Supabase project by:

   ```js
   const actualRef = new URL(url).hostname.split(".")[0];
   if (actualRef !== DEV_PROJECT_REF) throw new Error(...);
   ```

   That accepts `https://ifsccnjhymdmidffkzhl.supabase.co.evil.com` — the
   first DNS label equals `DEV_PROJECT_REF`, so the guard passes. An
   attacker who controls `NEXT_PUBLIC_SUPABASE_URL` at cleanup time (and
   can register a DNS suffix) exfiltrates the dev service-role key to an
   arbitrary endpoint.

2. **Command-substitution pipefail ambush.** The new audit script at
   `apps/web-platform/infra/audit-bwrap-uid.sh` computed a sha256 of the
   on-host seccomp profile via:

   ```bash
   FILE_HASH=$(jq -cS . "$EXPECTED_SECCOMP_PATH" 2>/dev/null | sha256sum | cut -d' ' -f1)
   ```

   Under `set -euo pipefail`, a malformed on-host JSON makes `jq` exit
   non-zero, `pipefail` propagates the failure through the pipe, and the
   whole command substitution aborts the script *before* the intended
   "On-host seccomp profile... is not valid JSON" FAIL branch can run.
   The script dies silently instead of emitting a labelled FAIL.

## Solution

1. **Exact-hostname equality, not prefix-split.** Replace the split with a
   constant comparison against the full expected hostname:

   ```js
   const DEV_HOSTNAME = `${DEV_PROJECT_REF}.supabase.co`;
   const actualHostname = new URL(url).hostname; // in try/catch
   if (actualHostname !== DEV_HOSTNAME) throw new Error(...);
   ```

   Add regression tests for both `<ref>.supabase.co.evil.com` (subdomain
   suffix) and `<ref>supabase.co` (label-boundary-less).

2. **Explicit `|| true` on every optional-failure pipe inside `$(...)`.**
   When a pipeline may legitimately fail and a downstream branch should
   classify the failure, guard the pipe so strict mode cannot swallow it:

   ```bash
   FILE_HASH=$(jq -cS . "$FILE" 2>/dev/null | sha256sum | cut -d' ' -f1 || true)
   EMPTY_HASH=$(printf '' | sha256sum | cut -d' ' -f1)
   if [[ -z "$FILE_HASH" || "$FILE_HASH" == "$EMPTY_HASH" ]]; then
     emit_fail "... is not valid JSON"
   fi
   ```

   Add a regression test that seeds a malformed on-disk fixture and
   asserts the script exits with the labelled FAIL — not a strict-mode
   silent abort.

## Key Insight

Two classes of "defensive-looking code that isn't":

- **Identity guards that strip context.** `hostname.split(".")[0]` looks
  like a hostname check but is really a prefix check — the discarded tail
  is the attack surface. Whenever a guard is meant to pin identity, the
  comparison must be over the *whole* identity (full hostname, full URI,
  full JWT issuer+subject), never a parse-first-label.

- **Strict mode's quiet failures.** `set -euo pipefail` is usually
  load-bearing safety, but inside `$(...)` it inverts the expectation:
  the pipe's failure propagates out, often killing the script before the
  code meant to classify that very failure can run. Every optional-
  failure pipe inside a command substitution needs `|| true`, and the
  downstream branch needs to detect the sentinel (empty string, empty
  hash) explicitly.

## Session Errors

- **Prefix-split guard shipped in first commit.** Caught by
  security-sentinel on PR #2840 review.
  **Recovery:** exact-hostname equality + two bypass regression tests.
  **Prevention:** new learning (this file) + pattern to watch for in
  future URL/JWT/token identity guards; propose an AGENTS.md rule when
  another instance is found.

- **`FILE_HASH` pipeline missed `|| true`.** Caught by
  code-simplicity-reviewer on the same PR (upgraded from P3 nit to P2
  bug after verifying strict-mode behavior with `bash -c '...'`).
  **Recovery:** added `|| true`, hoisted `EMPTY_HASH` constant, added a
  regression test that exercises the malformed-JSON branch.
  **Prevention:** this learning file; apply the "command substitution
  under strict mode needs `|| true` on failable pipes" rule as a review
  heuristic for any new bash script with `set -euo pipefail`.

## Related

- `knowledge-base/project/learnings/2026-04-15-multi-agent-review-catches-bugs-tests-miss.md` —
  pattern-catalogue of defects caught by multi-agent review on
  green-tests PRs.
- AGENTS.md rule `cq-destructive-prod-tests-allowlist` — adjacent
  principle (destructive prod ops must hard-assert synthetic
  identifiers).
- Issue trail: #2839 (prefix guard), #2837 (audit check 2 hash-compare),
  PR #2840.
