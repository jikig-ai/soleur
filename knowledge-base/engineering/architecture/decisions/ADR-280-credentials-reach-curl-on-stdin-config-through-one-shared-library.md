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
job. Moving the credential to curl's stdin config closes the readers of `cmdline` and `ps` (other uids, and any process that only lists
arguments). It does not close a same-uid reader of `/proc/<pid>/environ` (the library hands a credential to a child by environment where it
must), and it does not close tampering with the library itself inside the job (the library is sourced from the job's own checkout, so a
step that can rewrite the workspace can rewrite it). S1 added a lint (Rule E) that counts credentials on curl's argument list in workflow, composite-action and cloud-init YAML; S2 moved
the ops, runner and plugin scripts to curl's stdin config (`--config -`) with a token-shape guard and a process substitution. Workflow steps
cannot call a repo script by a stable path the way those scripts call each other, and 68 inline copies of the shape guard already exist, so
S3 needs one tested place for the pattern that 24 alert-path composite steps and the converted workflows can all use.

## Decision

1. **Credentials reach curl on its stdin config, through `scripts/lib/bearer-curl.sh`.** `bc_curl SCRIPT SPEC... -- ARGS` builds the
   `header = "..."` directives from variable *names* (read by indirect expansion only inside the library) and runs
   `curl --disable --noproxy '*' ARGS --config -` fed by a process substitution (never a pipe: under `pipefail` a consumer that exits first
   turns the writer's SIGPIPE into 141). `bc_hmac_sha256_hex KEYVAR` signs with the key in a `python3 -I` child's environment only.
2. **One chokepoint, judged before any byte is sent.** (`bc_refuse SCRIPT VAR` prints the same line and marker for a site's own
   pre-guard and returns 2, so a site that must keep a refusal out of the wrong verdict arm announces it identically.) Every value passes `bc_ok` (non-empty, `[A-Za-z0-9._~+/=-]`) inside the single
   internal `_bc_send`; the token `curl` occurs in the library only there, and a suite row asserts it. A refused call makes zero requests,
   prints one value-free line naming only the variable, and the marker `SOLEUR_CREDENTIAL_REFUSED script=<name> reason=<token_shape|control_char>`.
3. **A refusal lands in the same verdict class as the old failure.** The library returns 2 and a caller treats it as a curl failure. rc 2
   collides with curl's own exit 2, so no caller branches on `rc == 2`; the marker is the discriminator. Where a bare rc 2 would fold into a
   different verdict arm (a malformed key skipping every Claude step) the site carries an explicit pre-guard, written next to the site and
   exercised by a row. The restart-mapping pre-guard (a credential fault read as a server restart) belongs to the held-back `probe` step and is
   an S4 obligation, not something this slice delivers.
4. **A missing library is a hard failure, never an argv fallback.** Composite actions and steps source the library from the job's own
   checkout (`${GITHUB_WORKSPACE:?}/scripts/lib/bearer-curl.sh`), so the action file and the library cannot skew. A fallback to the argv form
   would defeat the property. `scripts/lint-workflow-local-action-checkout.py` requires a usable checkout that includes `scripts/lib/`, no
   `path:`, and no `pull_request_target` trigger for any job that uses the composites or sources the library.
5. **Tracing is refused.** Each credential-binding function returns 78 when `set -x` is on: a sourced library cannot rely on its caller's
   prologue. `bc_ok_var NAME` takes the variable name so a site's own pre-guard never carries the value as an argument.
6. **No default timeout is added.** A site that carried `--max-time` keeps it. The transfer itself is NOT byte-neutral: it now runs with
   `--disable --noproxy '*'` first (no `.curlrc`, no proxy) and with the TLS-redirecting environment variables unset, which is a transport
   change recorded here, not a no-op. The `timeout-minutes` of each job still bounds a site that has no `--max-time`.
7. **Trailing whitespace is trimmed, interior is not.** A secret stored with a trailing newline is the commonest storage accident and curl
   itself trims a header value, so the value is judged and sent after a trailing-whitespace trim; whitespace or any other byte outside the
   alphabet inside the value is still refused.
8. **The arguments after `--` cannot undo the property.** `_bc_tail_ok` refuses (rc 64, before any request) verbose and trace flags,
   redirect following, a second config, a credential header or basic/bearer/cookie flag of the caller's own, and a body read from stdin.

## Considered options

- **The 68 inline copies.** Rejected: each is a place for the guard to drift, and a workflow step cannot be unit-tested without
  re-implementing it.
- **A `curl` wrapper earlier on `$PATH` in the runner.** Rejected: ambient, not testable per site, and invisible to the Rule E lint.
- **Argv with `::add-mask::`.** Rejected: masking hides the value from logs and does nothing about `/proc/<pid>/cmdline`.
- **A default `--max-time` in the library.** Rejected: it changes the request, and every converted step has its own `timeout-minutes`.

## Consequences

- Rule E baseline E shrinks by deletion only (now 17 files / 43 sites); per-site fingerprint keying is not adopted because S4 and S5 delete
  the remaining population.
- Blast radius: the library is sourced by 12 workflow and composite files, so a defect in it fails every one of them at once. That is the
  reason it has its own suite (with a mutation-sensitive census) and a CODEOWNERS entry, and why a missing or unloadable library is a visible
  hard failure at each site rather than a silent skip.
- The 2026-10-06 plan rejected a shared helper. That rejection is reversed for workflows and composite actions only (they have no stable
  script path to call); the scripts under `scripts/` keep their inline wrapper. Whether S4 and S5 migrate the two inline-wrapper scripts is
  decided in those slices.
- The two Better Stack reader callers in `scheduled-inngest-health.yml` and `git-data-cutover.yml` no longer discard stderr, so a reader
  refusal marker reaches the run log (#9757, item done).
- Retrieval: `SOLEUR_CREDENTIAL_REFUSED` lines are found in the Better Stack stream for hosted runs and in the workflow run log for GitHub
  runs (observability layer 6).
- Two sites are held back to S4 because converting them needs an edit to an `apps/web-platform/infra/**` suite, which fires the production
  push apply: `workspaces-luks-cutover.yml` (its suite's curl stub exits 64 on `--disable --noproxy`; it reads `HCLOUD_TOKEN_READONLY` first and
  falls back to the read/write name until ADR-241 O10) and the `probe` step of `scheduled-inngest-health.yml` (its suite builds a fake
  workspace with stubbed `openssl` and `curl` and no library). A step whose suite executes it in a library-less fake workspace cannot
  adopt a sourced library without that edit; that is the cost of choosing a sourced library, accepted here.
- The HMAC key and the credentials live in a child's environment (same-uid and root can read `/proc/<pid>/environ`): a reduction from
  world-readable `cmdline`, not elimination. Past exposure is not remediated here; rotation stays with ADR-241 O13.
- A vendor changing its key alphabet turns an alert into a visible refusal annotation instead of a vendor 401, with a new cause. The marker
  lives in run logs and is not paged.

## Verification

`scripts/lib/bearer-curl.test.sh` (shim calibrated against `curl --libcurl`, a loopback real-curl end-to-end row, a 0x01-0x7f byte sweep,
hostile/empty/unset values at every spec position, the HMAC oracle, a negative canary, the chokepoint census), the S3 stage of
`tests/scripts/test-argv-bearer-sweep.sh`, and Rule E baseline equality.
