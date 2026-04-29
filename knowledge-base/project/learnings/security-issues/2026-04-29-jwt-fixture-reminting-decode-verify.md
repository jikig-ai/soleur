---
title: Re-minting JWT-encoded test fixtures requires per-token decode verification, not source-form grep
date: 2026-04-29
category: security-issues
module: test-fixtures
problem_type: secret-scanning-alert-handling
severity: medium
related:
  - knowledge-base/project/learnings/security-issues/2026-04-17-log-injection-unicode-line-separators.md
  - knowledge-base/project/learnings/2026-04-07-ux-agent-placeholder-secrets-trigger-push-protection.md
tags:
  - secret-scanning
  - jwt
  - test-fixtures
  - base64
  - dependabot
---

# Re-minting JWT-encoded test fixtures: decode every token

## Problem

GitHub secret-scanning fired alert #2 against `apps/web-platform/infra/canary-bundle-claim-check.test.sh` for a `JWT_SERVICE_ROLE` constant whose payload base64-encoded the **dev** Supabase project ref (`ifsccnjhymdmidffkzhl`). The signature was the literal 3-char string `sig` — the JWT could not authenticate to anything — but the scanner pattern-matched the `iss=supabase` + `role=service_role` + 20-char project-ref shape regardless of signature validity.

The remediation looked straightforward: replace the dev ref with a placeholder (`aaaaaaaaaaaaaaaaaaaa`) across 5 JWT constants in the file, run a source-form grep to confirm the dev ref is gone, ship the fix.

The naive sweep was insufficient. After applying `replace_all "ifsccnjhymdmidffkzhl"` and confirming `grep -c ifsccnjhymdmidffkzhl <file>` returned `0`, one of the five JWTs (`JWT_LOG_INJECT_U2028`) still encoded the dev ref in its base64 payload. The grep gate could not see it — the dev ref's base64-encoded form is a different byte sequence (`aWZzY2Nuamh5bWRtaWRmZmt6aGw`) — but the secret scanner would have re-fired on the next push.

## Solution

After every JWT-fixture re-mint, decode each token's payload and grep the **decoded** form for the value being removed:

```bash
FILE=apps/web-platform/infra/canary-bundle-claim-check.test.sh
for tok in CANONICAL_JWT JWT_SERVICE_ROLE JWT_BAD_ISS JWT_LOG_INJECT JWT_LOG_INJECT_U2028; do
  val=$(grep -E "^${tok}=" "$FILE" | head -1 | sed -E "s/^${tok}='([^']+)'.*/\1/")
  payload=$(echo "$val" | cut -d. -f2)
  decoded=$(echo "$payload" | tr '_-' '/+' | base64 -d 2>/dev/null)
  echo "$tok decoded: $decoded"
  if echo "$decoded" | grep -q ifsccnjhymdmidffkzhl; then
    echo "  ❌ DEV REF LEAKED in $tok"
  fi
done
```

This catches the case where source-form grep returned `0` but the value survived inside a base64 payload. For the U+2028 fixture specifically, the existing `Edit` invocation also failed on a `old_string` that included the prior comment line containing a raw U+2028 codepoint (Edit normalizes some non-ASCII bytes during match) — the recovery was a narrower ASCII-only `old_string` that anchored on the JWT line alone.

## Key Insight

**Source-form grep on encoded fixtures is pseudo-coverage.** Any value embedded in a base64, hex, JSON-string-escape, or URL-encoded blob will NOT show up in a literal-string grep — but the GitHub secret scanner (and any downstream consumer that decodes the blob) will see it. When the goal is "remove value X from fixture file F," the verification must close the loop the scanner closes:

1. Substitute the value at the source.
2. Source-form grep for value X → expect 0.
3. **For each encoded blob in F, decode it and grep for value X → expect 0.**

Step 3 is the load-bearing one. Without it, secret-scanner alerts re-fire after merge, dependency dismissal API calls return 422, and the operator who closed the alert ticket gets paged again 24 hours later.

## Adjacent invariants surfaced during this fix

Two related properties also have to hold for this fixture file specifically (not generalizable, captured here so the next maintainer sees them):

- `JWT_LOG_INJECT` payload bytes must contain `5c 6e` (literal `\n`, two ASCII chars), NOT `0a` (raw LF). The script's `tr -d '\000-\037\177'` pass strips raw LFs **before** the F12 assertion ever sees them — without the literal escape, F12 silently no-ops.
- `JWT_LOG_INJECT_U2028` payload bytes must contain `5c 75 32 30 32 38` (literal six-char ` `), NOT `e2 80 a8` (raw U+2028 codepoint). The script's `jq -er` JSON parser converts the literal escape to the codepoint at parse time; only THEN does `sanitize()`'s `sed` pass strip the bytes. If the source already contains the codepoint, the parser passes through, the sed pass strips it, and F12-bis still passes — but the test no longer proves the JSON-escape parser branch. Bash heredocs and many GUI editors silently convert typed ` ` text into the codepoint, so the byte form has to be verified post-edit.

The companion comment block for each fixture must also document the encoded form using the same source-form rendering as the payload (literal `\n`, literal ` `) — otherwise a future re-mint reads the comment, types the rendered form, and silently breaks the test it was meant to preserve. Caught during multi-agent review of this PR (PR #3054, pattern-recognition-specialist).

## Session Errors

- **User-Brand Impact gate (Phase 4.6) failed during deepen-plan** — threshold was `none` but diff path matched the sensitive-path regex (`apps/[^/]+/infra/`). Required adding a `threshold: none, reason: <one-sentence>` scope-out bullet. **Prevention:** plan/deepen-plan could pre-emit the scope-out template when diff paths match the sensitive regex.
- **U+2028 mint hazard in plan's Phase 2 instructions** — single-quoted bash `printf` would have produced raw codepoint, breaking F12-bis. Caught by deepen-plan pass which switched to byte-exact pre-minted JWT strings. **Prevention:** plan emits byte-exact target strings instead of mint-helper code for any fixture that round-trips through `jq` or another escape-decoding parser.
- **`Edit` failed on `JWT_LOG_INJECT_U2028` with U+2028 codepoint in old_string** — the harness normalized non-ASCII bytes during match. **Recovery:** narrower ASCII-only `old_string`. **Prevention:** when editing near non-ASCII bytes, scope `old_string` to ASCII-only context or use `sed` for byte-level edits.
- **Source-form `replace_all` missed the base64-encoded dev ref** — the actual session error this learning documents. **Prevention:** see Solution above.
- **`decode_jwt` bash helper returned empty output for 3 of 5 payloads** due to nested `seq`/command-substitution quoting. **Recovery:** direct inline decodes. **Prevention:** prefer simple inline pipelines over bash functions for one-shot verification.

## Tags

category: security-issues
module: test-fixtures
problem_type: secret-scanning-alert-handling
