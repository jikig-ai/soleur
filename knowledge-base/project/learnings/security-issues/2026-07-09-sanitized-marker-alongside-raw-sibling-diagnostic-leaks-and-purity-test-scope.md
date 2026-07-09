---
title: "A sanitized structured marker added alongside a pre-existing raw diagnostic emitter on the SAME sink leaks — and a prefix-scoped purity test passes green while it does"
date: 2026-07-09
category: security-issues
module: apps/web-platform/infra (inngest cutover pre-flight scripts)
issue: 6258
pr: 6283
tags: [observability, credential-leak, purity-test, review, sanitizer, journald, better-stack]
severity: P1
---

# Learning: sanitized marker + raw sibling diagnostic on the same sink = leak

## Problem

PR #6283 (#6258) added structured `SOLEUR_INNGEST_PREFLIGHT_*` markers to the inngest
cutover pre-flight scripts and correctly **enum-mapped** raw GraphQL `errors[].message`
into `reason=gql_error` (Deepen Finding 13: "Vector does NOT scrub `postgres://` URIs; the
purity test is the SOLE guard"). The new markers were clean.

But each script ALSO had **pre-existing** sibling diagnostic emitters on the SAME journald
tag + stdout:

```bash
logger -t "$LOG_TAG" "ERROR: malformed GraphQL response on page $page: errors=$err_msgs …"
echo   "inngest-inventory: FATAL … : ${gql_msg:-…}"
```

`err_msgs`/`gql_msg`/`fn_errs` carry the **verbatim** GraphQL error text. A
`postgres://<user>:<pass>@<host>:5432/db` DSN legitimately appears in a Postgres
`errors[].message` on exactly the `EMAXCONNSESSION` pool-pressure path this probe targets —
so the credential shipped to Better Stack (3rd-party log store, no `PRIORITY` filter on the
`host_scripts_journald` Vector source) AND the GitHub-Actions run log, on the failure path
the fix exists to diagnose.

The purity test **looked** like it guarded this — it fixtured a real DSN — but scoped its
assertion to only the new-marker lines:

```bash
local soleur_lines; soleur_lines=$(echo "$markers" | grep 'SOLEUR_INNGEST_PREFLIGHT')
assert_eq "no '://' in any SOLEUR marker" "0" "$(echo "$soleur_lines" | grep -c '://')"
```

So it filtered OUT the very ERROR line that carried the DSN → **green while leaking**.

## Root cause

Two independent gaps compose:
1. **Sanitizer applied to the new emitter only.** When you add a scrubbed marker next to
   pre-existing raw diagnostic emitters on the same sink, the *concern* (no creds off-box)
   spans BOTH — but the diff only touched the new one.
2. **Prefix-scoped purity assertion.** Grepping to the new marker's prefix before asserting
   is vacuous for the leak: it can't see the sibling line. The assertion must run against
   the **full sink capture**.

Caught by two orthogonal review agents converging (security-sentinel flagged the exact
lines as pre-existing; user-impact-reviewer escalated to P1 as the plan's own named
single-user vector) — neither the passing unit suite nor the marker-only purity test saw it.

## Solution

- Add a `_pf_scrub` stdin filter (redact `scheme://…` + `user:pass@host` + strip
  control/Unicode separators) and apply it to `err_msgs`/`gql_msg`/`fn_errs` in **all three**
  scripts (swept the same-class hole in registry-probe too, not just the two flagged).
- Widen the purity assertions to the **full** journald + stdout capture (`$MARKERS_CAP`,
  `$STDOUT_CAP`), not the SOLEUR subset.

## Key Insight

**When you add a sanitized log/marker alongside a pre-existing raw diagnostic emitter on the
same off-box sink, scrub the siblings in the same PR, and assert purity against the FULL sink
capture — never the new emitter's prefix.** A prefix-scoped purity test is a vacuous guard for
a sibling-line leak: it passes green by construction. Sweep all emitters to the sink
(`git grep 'logger -t "\$LOG_TAG"'`), not just the one the diff introduces — same class as
`hr-write-boundary-sentinel-sweep-all-write-sites` for log sinks.

**Corollary (assertion shape):** a credential-leak purity assertion must target the
**credential-bearing** shape (`user:pass@host:port`, i.e. `@[^ ]+:[0-9]+`), NOT a bare `://`.
Scripts legitimately print credential-LESS internal endpoint URLs (`http://10.0.1.40:8288/…`)
for operator diagnostics — a `no '://'` assertion false-fails on those. (This bit during the
fix: my first widened registry-probe assertion used `no '://'` and red-failed on the benign
`$GQL_URL`; narrowed to the DSN-credential pattern.)

## Session Errors

1. **Widened purity assertion `no '://'` false-failed on a benign internal endpoint URL.**
   Recovery: narrowed the registry-probe assertion to the credential-DSN shape
   (`@[^ ]+:[0-9]+`) + a specific `host:port` scrub check. Prevention: assert on the
   credential shape, not bare `://` (captured as the corollary above).
2. Planning subagent's Monitor/foreground-sleep waits were rejected by the harness (used
   auto-notifications). One-off — harness auto-notify is the correct pattern.
3. Impl subagent: an expanded `$@` token is not a bash assignment prefix (parse-time
   decision); passed dynamic env seams via `env "$@"`. One-off, self-corrected.
4. Two Edit anchors needed a re-grep after a line-rewrap. One-off.

## Tags
category: security-issues
module: apps/web-platform/infra
