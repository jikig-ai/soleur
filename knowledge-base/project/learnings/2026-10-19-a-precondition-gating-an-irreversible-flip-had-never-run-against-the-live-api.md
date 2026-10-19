# Learning: a precondition that gates an irreversible flip had never run against the live API

## Problem

The first live dispatch of the git-data rehearsal flip (run 39225916196, 2026-10-19) refused in the
`Flip preconditions` step with `verdict=pin_fault_paging_absent` and HTTP 301, before any flag write, freeze
or redeploy. The check had been written, reviewed and covered by a 636-assertion suite, and none of it had
ever executed the step against anything resembling the live API. Two defects, one step:

- `SENTRY_API_HOST` (a repo secret) is a scheme-less org-subdomain (`jikigai-eu.sentry.io`); every other
  consumer prepends `https://`. The step built `${host}/api/...`, so curl went out over http and Sentry
  answered 301.
- Rule id `1310055` is a Sentry **workflow** id. `organizations/<org>/alert-rules/1310055/` answers 404 for
  it, and a workflow carries `enabled: true|false`, not `status`. One read-only probe with an existing token
  showed this: `workflows/1310055/` returns 200, `enabled: true`.

## Solution

`.github/workflows/git-data-cutover.yml` `Flip preconditions`: pin the host (`jikigai-eu.sentry.io`, refusing
before any request so the read token can go nowhere else), GET `workflows/1310055/`, and require
`jq -e '.id == "1310055" and .name == "git-data-host-key-pin-fault" and .enabled == true'`. The suite now
EXECUTES the real step bytes up to the d6 scan under a `bc_curl` shim (rows FP1-FP3: the exact request, the
refusal matrix, the host pin). Eleven targeted mutants (gate deleted, code gate deleted, enabled loosened,
id/name dropped, scheme dropped, pin deleted, token swapped, `-w` dropped, `--max-time` dropped, `-o` file
swapped) are each killed by the row aimed at them.

## Key Insight

A refusal gate that stands in front of an irreversible production action is only as good as its first live
read, and a static suite cannot supply that read. Three habits close it: probe the live read shape once,
read-only (endpoint, id kind, field name), before coding the check; execute the step's real bytes against a
shim in the suite so the request URL and every refusal are asserted, not their spelling; and measure a
reviewer's doubt about credential scope with the nearest existing token (an `org:read` token read the
workflow, 200) rather than reading the script that provisions it.

## Session Errors

1. **Told the owner a credential was theirs to mint.** `DOPPLER_TOKEN_GIT_DATA_FLAG` was one
   `doppler configs tokens create … | gh secret set --env …` away; the owner corrected it. Recovery: minted
   it by pipe, value never printed. **Prevention:** before listing a credential as an owner blocker, check
   `doppler configs tokens` / the environment secret list and the credential-tier runbook for a mint recipe;
   production writes and dispatches still need the owner's named go.
2. **Inferred the secret's stored form from the 301.** The first fix added a scheme-tolerance for a form
   nobody had read, and review showed every sibling consumer pins the scheme-less value. Recovery: the host
   is now pinned instead of tolerated. **Prevention:** read the stored form (or a sibling consumer) before
   coding for it; the 301 only proved "not https".
3. **The static row pinned spelling.** `WF-pinfault` left 16 of 22 mutants alive. Recovery: executed rows
   FP1-FP3. **Prevention:** a gate on an irreversible action is tested by executing it under a shim.
4. **Token scope settled by reading, not measuring.** A reviewer flagged that the RO token is pinned to
   `event:read, org:read, project:read`. Recovery: probed the endpoint with the existing `SENTRY_ISSUE_RO_TOKEN`
   (`event:read, org:read`): 200. **Prevention:** one read-only call beats a scope argument.
5. **A hook blocked a whole Bash call that merely contained `git stash list`.** Recovery: re-issued without
   it. **Prevention:** none beyond not including the string.
6. **Assertion-count floor slips.** 635 to 636 missed the verdict-count pin (56 to 57); a later 640 forgot a
   branch that only fails. Recovery: read the suite's own FAIL line each time. **Prevention:** run the suite
   after every added row and trust its `ran/declared` line over arithmetic.
7. **Memory write blocked by hook; two stop-hook corrections.** Recovery: this file is the committed record;
   work continued instead of pausing on a mergeable PR. **Prevention:** none needed.

## Tags
category: logic-errors
module: git-data-cutover
