---
title: Workflow-side credentials reach curl on its stdin config through one shared sourced library
status: adopting
date: 2026-10-09
supersedes: none
issue: 9597
related: [7797, 9757]
related_adrs: [ADR-241]
tags: [security, ci, credentials, curl, argv, workflow, composite-action]
brand_survival_threshold: single-user incident
---

# ADR-280: Workflow-side credentials reach curl on its stdin config through one shared sourced library

## Status

**Adopting** (slice S3 of the argv-credential sweep, tracker #9597). The status moves to `accepted` once the first scheduled runs of the
converted workflows and the first delivered alert email are recorded on the follow-through issue the PR files. The ordinal was the next
free one against `origin/main`, every `origin/*` ref and every open PR's files on 2026-10-09 (278 and 279 are held by open PRs); it is
re-verified at ship.

## Context

A header passed as `-H "Authorization: Bearer ..."` is an argument of the transfer process, readable in `/proc/<pid>/cmdline` and `ps` by
every local user for the life of the request. On a hosted runner that means a compromised third-party action or dependency step in the same
job. S1 added a lint (Rule E) that counts credentials on curl's argument list in workflow, composite-action and cloud-init YAML; S2 moved
the ops, runner and plugin scripts to curl's stdin config (`--config -`) with a token-shape guard and a process substitution. Workflow steps
cannot call a repo script by a stable path the way those scripts call each other, and 68 inline copies of the shape guard already exist, so
S3 needs one tested place for the pattern that 24 alert-path composite steps and the converted workflows can all use.

## Decision

1. **Credentials reach curl on its stdin config, through `scripts/lib/bearer-curl.sh`.** `bc_curl SCRIPT SPEC... -- ARGS` builds the
   `header = "..."` directives from variable *names* (read by indirect expansion only inside the library) and runs
   `curl --disable --noproxy '*' ARGS --config -` fed by a process substitution (never a pipe: under `pipefail` a consumer that exits first
   turns the writer's SIGPIPE into 141). `bc_hmac_sha256_hex KEYVAR` signs with the key in a `python3 -I` child's environment only.
2. **One chokepoint, judged before any byte is sent.** Every value passes `bc_ok` (non-empty, `[A-Za-z0-9._~+/=-]`) inside the single
   internal `_bc_send`; the token `curl` occurs in the library only there, and a suite row asserts it. A refused call makes zero requests,
   prints one value-free line naming only the variable, and the marker `SOLEUR_CREDENTIAL_REFUSED script=<name> reason=<token_shape|control_char>`.
3. **A refusal lands in the same verdict class as the old failure.** The library returns 2 and a caller treats it as a curl failure. rc 2
   collides with curl's own exit 2, so no caller branches on `rc == 2`; the marker is the discriminator. Where a bare rc 2 would fold into a
   different verdict arm (a malformed key skipping every Claude step; a credential fault mapped to a server restart) the site carries an
   explicit pre-guard, written next to the site and exercised by a row.
4. **A missing library is a hard failure, never an argv fallback.** Composite actions and steps source the library from the job's own
   checkout (`${GITHUB_WORKSPACE:?}/scripts/lib/bearer-curl.sh`), so the action file and the library cannot skew. A fallback to the argv form
   would defeat the property. `scripts/lint-workflow-local-action-checkout.py` requires a usable checkout that includes `scripts/lib/`, no
   `path:`, and no `pull_request_target` trigger for any job that uses the composites or sources the library.
5. **Tracing is refused.** Each credential-binding function returns 78 when `set -x` is on: a sourced library cannot rely on its caller's
   prologue.
6. **No default timeout is added.** The conversion is byte-neutral per call site; a site that carried `--max-time` keeps it.

## Considered options

- **The 68 inline copies.** Rejected: each is a place for the guard to drift, and a workflow step cannot be unit-tested without
  re-implementing it.
- **A `curl` wrapper earlier on `$PATH` in the runner.** Rejected: ambient, not testable per site, and invisible to the Rule E lint.
- **Argv with `::add-mask::`.** Rejected: masking hides the value from logs and does nothing about `/proc/<pid>/cmdline`.
- **A default `--max-time` in the library.** Rejected: it changes the request, and every converted step has its own `timeout-minutes`.

## Consequences

- Rule E baseline E shrinks by deletion only; per-site fingerprint keying is not adopted because S4 and S5 delete the remaining population.
- The held-back file `workspaces-luks-cutover.yml` rides S4: converting its one Hetzner read needs an edit to an infra suite's curl stub,
  which fires the production push apply. It reads `HCLOUD_TOKEN_READONLY` first and falls back to the read/write name until ADR-241 O10.
- The HMAC key and the credentials live in a child's environment (same-uid and root can read `/proc/<pid>/environ`): a reduction from
  world-readable `cmdline`, not elimination. Past exposure is not remediated here; rotation stays with ADR-241 O13.
- A vendor changing its key alphabet turns an alert into a visible refusal annotation instead of a vendor 401, with a new cause. The marker
  lives in run logs and is not paged.

## Verification

`scripts/lib/bearer-curl.test.sh` (shim calibrated against `curl --libcurl`, a loopback real-curl end-to-end row, a 0x01-0x7f byte sweep,
hostile/empty/unset values at every spec position, the HMAC oracle, a negative canary, the chokepoint census), the S3 stage of
`tests/scripts/test-argv-bearer-sweep.sh`, and Rule E baseline equality.
