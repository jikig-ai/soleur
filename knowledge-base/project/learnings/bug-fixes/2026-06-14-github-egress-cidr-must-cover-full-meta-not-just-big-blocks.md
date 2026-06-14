# Learning: GitHub egress CIDR allowlist must cover the FULL /meta union, not just the 4 big blocks

## Problem

The `scheduled-ruleset-bypass-audit` Inngest cron missed its daily Sentry check-in
(monitor slug `scheduled-ruleset-bypass-audit`, Sentry incident 5516336, 2026-06-14 06:13 UTC).
Last good check-in was the day before. The cron is all-`api.github.com` (App-token mint +
REST audit), and the Sentry heartbeat is the LAST step — gated on the GitHub calls
succeeding. So a blocked GitHub call yields NO heartbeat at all → a **missed** check-in
(not a `?status=error` **failed** one). Missed-vs-failed is the firewall-drop signature,
not an auth/error signature.

## Root Cause

The container egress firewall (#5089) default-drops all egress not on an allowlist. The
CIDR allowlist (`apps/web-platform/infra/cron-egress-allowlist-cidr.txt`, added by clone-fix
#5244) carried **only the 4 big GitHub git/pages blocks**: `140.82.112.0/20`,
`185.199.108.0/22`, `192.30.252.0/22`, `143.55.64.0/20`.

But **`api.github.com` round-robins DNS across TWO pools**: those 4 big blocks AND ~48
additional Azure `20.x`/`4.x` `/32` hosts published in GitHub's `/meta` `.git` **and**
`.api` lists. When a fire landed on (or the per-tick single-IP resolver pinned) an
uncovered `20.x`/`4.x` address, the call was neither in the single-IP set nor matched by the
CIDR interval set → default-dropped → no GitHub call → no heartbeat → missed check-in. This
is exactly the observed intermittency: 06-13 dialed a covered `140.82.x` IP (green); 06-14
landed on an uncovered range (red).

Live confirmation: committed file = 4 ranges; `curl -s https://api.github.com/meta | jq -r
'(.git+.api)[]|select(test(":")|not)' | sort -u` = **52 ranges** → 48 uncovered.

## Solution

Extend the CIDR file to the **complete `/meta` `.git`+`.api` IPv4 union** (52 ranges,
generated mechanically, snapshot-dated). The existing
`terraform_data.cron_egress_firewall` folds the file hash into `triggers_replace` and
file-provisions it, so a merge to `main` auto-re-applies via `apply-web-platform-infra.yml`
(path filter `apps/web-platform/infra/**`) — no operator host-shell step. The post-apply
remote-exec probes container→`api.github.com` reachability, so the apply fails if the
firewall is inert.

Drift guards added: an exact-count guard (`==52`) + Azure-range presence asserts in
`cron-egress-firewall.test.sh`, and a delimiter-anchored `[{,[:space:]](20|4)[.]` post-apply
assert in `server.tf` proving a non-`140.82` element landed.

## Key Insight

**For an LB host on a default-drop egress firewall, the hostname allowlist (single-IP
resolver) is the wrong layer — you need the CIDR interval set, and it must cover the host's
FULL published IP pool, not a representative subset.** `api.github.com` and `github.com`
both round-robin across `140.82` AND Azure `20.x`/`4.x` pools; covering only the big blocks
produces an *intermittent* drop that passes on most fires and fails when DNS happens to
return an uncovered IP. Verify CIDR coverage with a set-difference, never "it resolves to a
covered IP today":

```bash
comm -23 <(curl -s https://api.github.com/meta | jq -r '(.git+.api)[]|select(test(":")|not)' | sort -u) \
         <(grep -vE '^[[:space:]]*(#|$)' apps/web-platform/infra/cron-egress-allowlist-cidr.txt | sort -u)
```

Empty = full coverage. The `/32`s rotate, so a static snapshot goes stale — durable fix
(self-refreshing generator) tracked in #5284.

## Secondary insight (server.tf post-apply assert)

When asserting "a non-`140.82` element is present" against `nft list set`, you cannot grep a
bare `(20|4)[.]` — an unanchored `4[.]` false-matches `143.55.64.0` (the `4.` in `64.0`),
and nft may render a block as an expanded range. Anchor on the element delimiter
(`[{,[:space:]](20|4)[.]`) so only an octet that STARTS an element matches. Display-agnostic
and expansion-safe.

## Session Errors

1. **PreToolUse hook blocked literal `ssh root@` strings in plan prose** (plan phase) —
   Recovery: rewrote to host-shell phrasing + IaC-routing ack. Prevention: when documenting
   "no SSH" in a plan/runbook, phrase the negation without the literal `ssh <user>@<host>`
   token (the hook matches the literal, not the intent).
2. **stdin-stealing `grep`-inside-`while-read` over a pipe** (plan phase) — the
   `discoverability_test` first-draft returned 0 UNCOVERED against the broken file because
   the inner `grep` consumed the loop's stdin. Recovery: rewrote as `comm -23 <(meta)
   <(file)`. Prevention: never put a stdin-reading command inside a `while read` over a
   pipe; use process-substitution set ops.
3. **`terraform fmt -check` errored on a `.sh` arg** (work phase) — fmt accepts only
   `.tf`/`.tfvars`/`.tftest.hcl`. Recovery: ran fmt on `server.tf` alone. Prevention: scope
   `terraform fmt` to `.tf` files only.
4. **`Edit` "file modified since read"** on the generated CIDR file (review phase) — a
   linter/normalizer touched the file post-generation. Recovery: re-read + re-applied.
   Prevention: re-Read a just-generated file before editing it.
5. **`Edit` whitespace mismatch** (`SSH).` vs `SSH.`) — Recovery: grep-located the exact
   line, re-applied. Prevention: grep for the live substring before constructing an Edit
   `old_string` from memory.

## Tags
category: bug-fixes
module: apps/web-platform/infra (cron-egress-firewall)
related: [[2026-06-10-best-effort-cron-monitor-liveness-not-success-and-offhost-visible-warn]]
