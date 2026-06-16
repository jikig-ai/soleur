---
date: 2026-06-16
category: integration-issues
module: supabase-auth
tags: [supabase, management-api, auth, rate-limits, smtp, debugging, 401, doppler]
issue: 5330
---

# Learning: A Supabase Management API `401` is often a validation error, not an auth failure

## Problem

Issue #5330 (AC9/AC10) asked to apply raised GoTrue OTP rate-limit ceilings
(`rate_limit_email_sent: 2→100`, `rate_limit_verify: 30→150`) to the prd and
dev Supabase projects after CPO sign-off.

prd applied cleanly. dev did **not**:

```
PATCH /v1/projects/mlwiodleouzwniehynfz/config/auth
  {"rate_limit_email_sent": 100, "rate_limit_verify": 150}
→ HTTP 401
```

The `401` was read as "this token can't write the dev project" and the dev
`SUPABASE_PAT` was assumed read-only / the account assumed to have only
read/member org role. Multiple fresh **full-account** Management tokens were
minted (via the dashboard) to "fix permissions" — every one still returned
`401` on the dev PATCH while `GET` on the same project returned `200`. That
`GET 200 / PATCH 401` split reinforced the (wrong) permissions theory.

## Root cause

The `401` was a **field-level validation error**, not an authorization
failure. Printing the response **body** (not just the status code) revealed:

```
{"message":"Custom SMTP required to configure SMTP_SENDER_NAME or
RATE_LIMIT_EMAIL_SENT. Missing SMTP_ADMIN_EMAIL, SMTP_HOST, SMTP_PORT,
SMTP_USER, SMTP_PASS fields."}
```

The dev project (`soleur-dev`) has **no custom SMTP** configured
(`smtp_host: null`, `smtp_admin_email: null`); it runs on Supabase's shared
email service. Supabase refuses to raise `rate_limit_email_sent` above the
shared-service default unless a custom SMTP provider is configured. prd
accepted `100` only because prd has Resend SMTP wired (via
`configure-auth.sh`). The token had write access all along — proven by
`PATCH {"rate_limit_verify": 150}` returning `HTTP 200` (verify has no SMTP
dependency).

## Solution

1. **Read the body.** `curl -sS -w '\n%{http_code}\n' -X PATCH …` and print the
   JSON `message`. The status code alone (`401`) is misleading on this API.
2. prd: targeted PATCH of `{rate_limit_email_sent, rate_limit_verify}` → 200,
   verified by re-GET.
3. dev: `rate_limit_verify` already 150 (no SMTP needed). `rate_limit_email_sent`
   left at the shared-service default — raising it would require giving dev a
   custom SMTP provider (coupling dev auth email to prod's Resend
   account/domain), which the operator (CPO) declined as not worth it for a
   dev convenience setting. #5330 closed: prd complete, dev not-applicable.

## Key insight

- **On the Supabase Management API, a `401` whose corresponding `GET` returns
  `200` is almost certainly a field-level validation / plan / SMTP
  requirement — not a credentials or org-role problem. Print the response
  body before concluding anything about permissions.**
- `rate_limit_email_sent` can ONLY be set when **custom SMTP** is configured on
  the project. `rate_limit_verify` (and other non-email knobs) have no such
  dependency. This is why dev (shared email) and prd (Resend SMTP) behave
  differently for the *same* token.
- Minting more credentials to "fix" a `401` is the wrong reflex until the body
  has been read — it wastes effort and can expose write-capable tokens.

## Session Errors

1. **Misdiagnosed the dev `401` as an org-role / read-only-token permissions
   wall (twice), including in two GitHub issue comments.** — Recovery: read the
   PATCH response body via `curl`, which named the SMTP requirement. —
   Prevention: when a Management API write returns `4xx` but `GET` succeeds,
   ALWAYS print the response body before forming a permissions hypothesis.
2. **Targeted PATCH of `rate_limit_email_sent` alone failed on dev** — because
   dev has no custom SMTP. — Prevention: same as #1; treat `rate_limit_email_sent`
   as SMTP-gated.
3. **`configure-auth.sh`'s expected env names (`SUPABASE_ACCESS_TOKEN`,
   `PROJECT_REF`, `RESEND_API_KEY`) don't match the Doppler secret names
   (`SUPABASE_PAT`/`SUPABASE_ACCESS_TOKEN`, `SUPABASE_PROJECT_REF`,
   `RESEND_API_KEY`), and Doppler `dev` has no `RESEND_API_KEY`.** The runbook's
   literal `doppler run -c dev … configure-auth.sh` could not have run as
   written. — Recovery: targeted Management-API PATCH instead. — Prevention:
   align the script's env-var reads with Doppler names (or add a wrapper) and
   add a `dev` RESEND_API_KEY before claiming the runbook works on dev.
4. **`agent-browser` daemon wedged** — `/usr/bin/agent-browser` (stale 0.5.0)
   shadowed `~/.local/bin/agent-browser` (0.22.3); the daemon returned empty
   output through the background harness. — Recovery: pivoted to Playwright
   MCP. — Prevention: one-off / machine-local; the git-worktree/agent-browser
   skill troubleshooting already documents the shadowing fix.
5. **Playwright MCP browser repeatedly closed between calls** — transient
   instability on the tokens page. — Recovery: re-navigated each time. —
   Prevention: one-off; tolerate by re-navigating + re-snapshotting.
6. **Supabase sign-in page exposed the password in plaintext in an
   accessibility snapshot (→ transcript).** — Recovery: flagged to the user and
   recommended rotation. — Prevention: avoid full-page snapshots on
   credential-entry pages; let the user drive login and snapshot only after
   landing on the post-auth page.
7. **Minted full-account Management tokens to "fix" a non-permissions problem**
   — wasted effort and briefly exposed prod-write-capable credentials in the
   transcript. — Recovery: deleted every test token; confirmed revoked
   (`GET → 401`). — Prevention: downstream of #1 — read the body first.

## Prevention

- Default debugging step for any Supabase Management API non-2xx: `-w` the
  status AND print the JSON body. Never infer "permissions" from the code.
- Remember the SMTP coupling: `rate_limit_email_sent` / `smtp_sender_name`
  require custom SMTP on the project.
- dev and prd are distinct Supabase projects in the SAME org
  (`vttwegzidmuaiefjlysl`): `soleur-web-platform`=`ifsccnjhymdmidffkzhl` (prd),
  `soleur-dev`=`mlwiodleouzwniehynfz` (dev). They differ in SMTP config, not in
  access.
- When investigating with browser-minted tokens, delete them when done and
  confirm revocation.
