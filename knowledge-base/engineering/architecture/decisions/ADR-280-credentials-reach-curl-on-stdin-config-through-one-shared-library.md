---
title: Workflow-side credentials reach curl on its stdin config through one shared sourced library
status: adopting
date: 2026-10-09
supersedes: none
issue: 9597
related: [7797, 9757]
related_adrs: [ADR-241, ADR-072, ADR-217]
tags: [security, ci, credentials, curl, argv, workflow, composite-action]
brand_survival_threshold: single-user incident
---

# ADR-280: Workflow-side credentials reach curl on its stdin config through one shared sourced library

## Status

**Adopting** (slice S3 of the argv-credential sweep, tracker #9597). The status moves to `accepted` once the first scheduled runs of the
converted workflows and the first delivered alert email are recorded on the follow-through issue the PR files. The ordinal was verified free against
`origin/main` and every open PR's files on 2026-10-09 and is re-verified at ship.

## Context

A header passed as `-H "Authorization: Bearer ..."` is an argument of the transfer process, readable in `/proc/<pid>/cmdline` and `ps` by
every local user for the life of the request. On a hosted runner that means a compromised third-party action or dependency step in the same
job. Moving the credential to curl's stdin config closes the readers of `cmdline` and `ps` (other uids, and any process that only lists
arguments). It does not close a same-uid reader of `/proc/<pid>/environ` (the library hands the HMAC key to a short-lived child by environment, and the step's own `env:` block already puts every bearer value in
the environment of every child of the step), and it does not close tampering with the library itself inside the job (the library is sourced from the job's own checkout, so a
step that can rewrite the workspace can rewrite it). S1 added a lint (Rule E) that counts credentials on curl's argument list in workflow, composite-action and cloud-init YAML; S2 moved
the ops, runner and plugin scripts to curl's stdin config (`--config -`) with a token-shape guard and a process substitution. Workflow steps
cannot call a repo script by a stable path the way those scripts call each other, and 68 inline copies of the shape guard already exist, so
S3 needs one tested place for the pattern that the 26 alert-path composite call steps (23 `notify-ops-email`, 3 `anthropic-preflight`) and the converted workflows can all use.

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
   collides with curl's own exit 2, so no caller branches on `rc == 2`; the marker is the discriminator. (Exception: the inngest heartbeat body exits 0 for a present-but-malformed value, see the 2026-10-15 follow-ups.) Where a bare rc 2 would fold into a
   different verdict arm (a malformed key skipping every Claude step) the site carries an explicit pre-guard, written next to the site and
   exercised by a row. The restart-mapping pre-guard (a credential fault read as a server restart) belongs to the held-back `probe` step and is
   an S4 obligation, not something this slice delivers.
4. **A missing library is a hard failure, never an argv fallback.** Composite actions and steps source the library from the job's own
   checkout (`${GITHUB_WORKSPACE:?}/scripts/lib/bearer-curl.sh`), so the action file and the library cannot skew. A fallback to the argv form
   would defeat the property. `scripts/lint-workflow-local-action-checkout.py` requires, for any job that uses a library composite (the set is derived from the action
   files) or sources the library: a usable checkout (no `path:`, no foreign `repository:`) whose sparse cone, if any, names `scripts`,
   `scripts/**` or a path under `scripts/lib/` by path segment with a later negation refused; no `pull_request_target` trigger; and, under
   `workflow_run`, `issue_comment`, `pull_request_review*` and `issues`, a checkout of the default branch's own ref only (any other `ref:`
   fails closed; on `pull_request_review*` even the implicit and `github.sha` refs are the PR's merge ref, so only an explicit default-branch
   spelling counts). Not covered, and named in the lint: a script that sources the library on a step's behalf, a composite that only calls
   another library composite, and the callers' triggers of a reusable workflow.
5. **Tracing is refused.** Each credential-binding function returns 78 when `set -x` is on: a sourced library cannot rely on its caller's
   prologue. `bc_ok_var NAME` takes the variable name so a site's own pre-guard never carries the value as an argument.
6. **No default timeout is added.** A site that carried `--max-time` keeps it. The transfer itself is NOT byte-neutral: it now runs with
   `--disable --noproxy '*'` first (no `.curlrc`, no proxy) and with the environment variables that redirect TLS trust, key logging, name
   resolution or library loading unset (the union of `betterstack-query.sh` and `sentry-alert-live-fidelity.sh`), which is a transport
   change recorded here, not a no-op. The `timeout-minutes` of each job still bounds a site that has no `--max-time`.
7. **Trailing whitespace is trimmed, interior is not.** A secret stored with a trailing newline is the commonest storage accident, and curl
   sends a trailing blank verbatim (measured on curl 8.22 over the config channel), so the vendor would see a different token than the one
   intended. The value is therefore judged and sent after a trailing-whitespace trim; whitespace or any other byte outside the alphabet
   inside the value is still refused.
8. **The arguments after `--` are checked against what would undo the property.** `_bc_tail_ok` refuses (rc 64, before any request), in the
   separate, attached, clustered and `=`-joined spellings, and for long options by prefix (the runner's curl 8.5 accepts `--verb` for
   `--verbose`): verbose and trace flags, redirect following, a second config or `--next`, a credential header (judged by name, and a
   header read from a file or stdin) or basic/bearer/cookie flag of the caller's own, a request body that reads stdin (`@-`, `<-`, `name=-`
   and the device spellings, with `;type=` modifiers dropped), a literal `--`, a value-taking option left without its value, `--libcurl`,
   and the trust, proxy, socks, netrc, unix-socket, DNS-override and resolution families. It is a guard against a caller's mistake: it does
   not enumerate every curl option (an option outside these families is not judged), and it is not a boundary against code that can edit
   the library.

## Considered options

- **The 68 inline copies.** Rejected: each is a place for the guard to drift, and a workflow step cannot be unit-tested without
  re-implementing it.
- **A `curl` wrapper earlier on `$PATH` in the runner.** Rejected: ambient, not testable per site, and invisible to the Rule E lint.
- **Argv with `::add-mask::`.** Rejected: masking hides the value from logs and does nothing about `/proc/<pid>/cmdline`.
- **A default `--max-time` in the library.** Rejected: it changes the request, and every converted step has its own `timeout-minutes`.

## Consequences

- Rule E baseline E shrinks by deletion only (now 17 files / 42 sites); per-site fingerprint keying is not adopted because S4 and S5 delete
  the remaining population.
- Blast radius: 12 files name the library (10 workflows and 2 composites), and 15 workflow files call the composites (12 of them not among
  the 10), so a defect in it reaches 22 workflow files and 26 composite call steps, including the alert paths of the production-apply and release workflows. That is the
  reason it has its own suite (with a mutation-sensitive census) and a CODEOWNERS entry, and why a missing or unloadable library is a visible
  hard failure at each site rather than a silent skip.
- S1 and S2 kept an inline wrapper per script. This slice adds the shared library for workflows and composite actions only (they have no
  stable script path to call); the scripts under `scripts/` keep their inline wrapper. Whether S4 and S5 migrate the two inline-wrapper
  scripts is decided in those slices.
- The two Better Stack reader callers in `scheduled-inngest-health.yml` and `git-data-cutover.yml` no longer discard stderr, so a reader
  refusal marker reaches the run log (#9757, item done).
- Retrieval: the library runs only in GitHub Actions steps, so `SOLEUR_CREDENTIAL_REFUSED` lines are found in the workflow run log
  (observability layer 6), not in Better Stack, and they are not paged.
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

## Addendum — 2026-10-09 (#9597 S4)

Slice S4 applies this contract to the push-triggered, production-class files: the deploy-webhook callers (HMAC signature plus the Cloudflare
Access pair), the Supabase, GitHub App, Resend and Hetzner bearer sites, the `openssl dgst -hmac` keys on the same calls, one push URL that
carried a token, and the two sites the Consequences above hold back. Status stays `adopting`; the sections above are unchanged and dated, and
this addendum records what S4 changed relative to them. No new ADR ordinal: the decision is the same contract on a new population. ADR-241 is
not amended: S4 names no new `secrets.*` reference and changes no tier classification.

### What S4 closes

- **The held-back sites.** `scheduled-inngest-health.yml` `probe` now uses the library (sourced inside the arm that uses it, so the three
  "secrets unset" paths never need it; a missing library is a visible `::error::`), and the infra suite that executes the step copies
  `scripts/lib/bearer-curl.sh` into its fake workspace. `workspaces-luks-cutover.yml` reads the volume through the inline wrapper (below), and
  its suite's curl stub gained `--disable` and `--noproxy` arms. The step keeps `HCLOUD_TOKEN_READONLY` first with the read/write fallback until
  ADR-241 O10; the shape guard judges whichever value was read.
- **The S4 obligation named in decision 3 is delivered.** The restart-mapping pre-guard of the `probe` step runs before the retry loop: the
  signature and both Access values are judged with `bc_ok_var`, a refusal is announced through `bc_refuse`, and the step records `secret_unset`
  (the liveness-probe issue class: no restart, no seed for the `[ci/inngest-down]` age gate). A credential fault is therefore never read as a
  transport failure or as a server that needs a restart.
- **Other pre-guards where a bare rc 2 would land in the wrong verdict arm**, each written beside its site:
  the post-re-push liveness probe in `apply-deploy-pipeline-fix.yml` (a refusal records `listener_state=probe_error`, never `down`), its
  `pre_frame` step (`secret_unavailable`, never `unreachable`; the `PRE_DETAIL` wording for that status was reworded to cover an unusable value
  as well as an unreadable one), `apply-inngest-rls.yml` (`secret_unset`, with `2>/dev/null` dropped from the converted calls so the marker is
  visible), `track.sh` (the existing `redeploy_credential_absent` verdict, exit 2; `openssl` leaves its tool list, `python3` joins it) and
  `infra-config-verify.sh` (below). The poll loops (`restart-inngest-server.yml`, `deploy-inngest-image.yml`, the release verify step) carry no
  pre-guard: the verdict is the old terminal red either way and the marker repeats per attempt.
- **`infra-config-verify.sh` pre-guard.** Its `HTTP_CODE=000` arm tells the operator the webhook listener itself is down. A refused credential
  must not print that sentence, so the three credential values are judged once before the poll loop, the verdict is held in a variable, and the
  first attempt acts on it right after truncating the status file: its own `::error::` (the credential is unusable, this says nothing about the listener, do not read it as an outage),
  the marker, and exit 1. The script also gained the xtrace refusal (Rule A) with the touch.

### The inline-wrapper clause

Decision 3's cost, "a step whose suite executes it in a library-less fake workspace cannot adopt a sourced library", generalizes. **The S2
inline wrapper (a step-local shape guard and `curl --disable --noproxy '*' ... --config -` fed by a process substitution) is allowed only where
a pinned property of the job or its suite rules out sourcing a repo file, and the exception is bounded mechanically by the HMAC parity audit
(`hm_audit`) in `tests/scripts/test-argv-bearer-sweep.sh`** (every inline copy of the HMAC snippet is pinned byte-equal to the canonical one;
read the audit for the current copy count, which is not restated here). Everywhere else the library is the form. The exceptions S4 takes, each
with its pinned property:

| Site | Why the library is not sourced |
|---|---|
| `web-platform-release.yml` `deploy` and `release-outcome`, `deploy-inngest-image.yml` `deploy` (seven guard copies across the three jobs) | The jobs are checkout-free by documented design (the lock-holding deploy runner and the silent-alert composite; ADR-072, ADR-217 and the workflow-run deploy invariants pin that area). |
| `workspaces-luks-cutover.yml` Hetzner read | Its suite's census of the token-holding step forbids any repo script executed on the runner there. |
| `infra-config-verify.sh` | Its suite's actuation sweep pins the script to a read-only command allow-list (it sources only its own gate file), and its mutation harness builds a skeleton with no `scripts/lib`. |
| `verify-tunnel-ingress-origin.sh` | Already inline since S2; only its HMAC line moved to the canonical snippet. |

An inline copy is weaker than the library in three stated ways: it does not run `_bc_tail_ok` (decision 8), it does not trim a trailing newline
(decision 7: an inline copy refuses such a value rather than sending it trimmed) and it does not unset the curl-redirecting environment variables
(decision 6), and its marker always carries `reason=token_shape` (it does not distinguish `control_char`). The marker is otherwise the same line,
with `script=<name>` set to the workflow or script name. The accepted residual is more inline guard copies, the drift the Context names, bounded
by the parity audit.

### HMAC keys leave openssl's argv

The decision's first item named `bc_hmac_sha256_hex` for the signature; S4 moves the key on every production `openssl dgst -sha256 -hmac "$KEY"`
site in the converted files: **20 sites** (`track.sh` 2, `apply-deploy-pipeline-fix.yml` 5, `deploy-inngest-image.yml` 2,
`restart-inngest-server.yml` 3, `scheduled-inngest-health.yml` 1, `web-platform-release.yml` 3, `infra-config-verify.sh` 1,
`push-infra-config.sh` 1, `verify-tunnel-ingress-origin.sh` 1, `github-app-key-status.sh` 1). Library sites sign with
`SIG="$(... | bc_hmac_sha256_hex KEY)" || SIG=""`, so an empty key or a missing `python3` reaches the call's shape check and the marker instead of
aborting mute under `set -e`; inline sites use the canonical `python3 -I` snippet with the key in the child's environment only. Rule E does not
see these (the key is on openssl's argv, not curl's), so the guard is a battery stage whose population is derived from the tree: every tracked
non-test, non-Markdown file with an `openssl dgst ... -hmac` operand must be in an allow-list of exactly what remains:

- two arms in `scripts/cutover-inngest.sh` (the registry-probe and doublefire-probe signatures), held back because converting them edits the
  census regexes of `cutover-inngest-workflow.test.sh`, a file an open draft PR already edits. Owner: #9757 item 1, taken once that draft merges.
- two agent-executed Markdown files that teach the argv form (`ship/SKILL.md`, the postmerge `deploy-status-debugging.md` reference): plugin
  files, tracked under #9757 and not edited here.

### The git credential by environment

`bump-inngest-bootstrap-pin.sh` built `https://x-access-token:${GH_TOKEN}@github.com/<repo>.git` and passed it to `git ls-remote` and
`git push`, so the token was on the argument lists of `git` and `git-remote-https`. The remote is now `https://github.com/<repo>.git` and the
credential reaches those two commands only, as a per-command environment prefix: `GIT_CONFIG_COUNT=1`,
`GIT_CONFIG_KEY_0=http.https://github.com/.extraheader`, `GIT_CONFIG_VALUE_0="Authorization: basic <base64 of x-access-token:TOKEN>"` (the form
`actions/checkout` uses; git 2.31 or later). The token passes a shape guard (`[A-Za-z0-9._~+/=-]`, the canonical credential alphabet `bc_ok`
judges — **amended 2026-10-11:** this record originally claimed `[A-Za-z0-9_]`, the legacy ~40-char `ghs_` base62 class; GitHub's issued
installation tokens are now ~390 chars and carry `.` and `-`, so that class refused every real token — the defect repaired under #9972) before
the header is
built, refusing with the same marker (`script=bump-inngest-bootstrap-pin`) and dying before any git network call; the header string is a plain
shell variable, never exported, and `BUMP_PUSH_URL` (the fixture seam) takes no header. **Residual:** the environment of a child is readable by
the same uid and by root (the same class as the HMAC key above), and base64 is an encoding, not protection. This is a reduction from the
world-readable `cmdline`, not elimination. The suite drives the real header path against a loopback HTTP server that judges the
`Authorization` header; the first live run against github.com is the first proof against the real remote.

### Where the library runs

- Under `workflow_run`, decision 4's checkout is of the default branch's own ref, so the sourced library is the default branch's head at the
  time the job runs. It can be newer than the SHA the run deploys. That is the intent (the pipeline code, not the release, owns the credential
  path), and it means the library is not pinned to the deployed commit.
- Decision 4 named "a script that sources the library on a step's behalf" as not covered. S4 covers it: a tracked `.sh` file outside
  `scripts/lib/` that names the library is a script consumer, derived from the tree, and a `run:` step that names one is judged like a step that
  names the library. `track.sh` (called from composites and workflow steps) and `push-infra-config.sh` are the first consumers.

### Considered options (S4)

| Option | Verdict |
|---|---|
| Inline wrapper at the checkout-free sites | **Adopted as the default.** No checkout is added to the lock-holding deploy job, so the job's documented shape and its `superseded` ordering are untouched. Cost: the inline copies above. |
| One-file sparse checkout at the checkout-free sites (`actions/checkout` pinned, `persist-credentials: false`, `sparse-checkout: scripts/lib/bearer-curl.sh`, cone mode off; a shape the lint already accepts), as an unconditional first step before the ordering guard | **Recorded, not taken.** It would let those jobs use the library and drop the copies, at a higher blast radius: a checkout outage would fail the deploy job at its first step even for a run that would have exited as `superseded`, and a `release-outcome` checkout failure would suppress that job's operator email. Revisit if the inline copies drift. |
| Convert the two `cutover-inngest.sh` arms in this slice | Rejected: the conversion edits a suite another open draft owns (above). |
| Rotate the exposed credentials in this slice | Rejected: S4 reduces argv exposure and does not rotate; rotation stays with ADR-241 O13 and its tracker. Past exposure is not remediated here. |

### Verification (S4)

The S4 stage of `tests/scripts/test-argv-bearer-sweep.sh` (population-derived HMAC guard, the pre-guard rows, the S3 stage's manifest and
held-back expectations updated one for one), the extended `scripts/lint-workflow-local-action-checkout.test.sh`, the bump script's suite (the
header form against a loopback HTTP server that judges the `Authorization` header value-free), the two infra suites, and Rule E
baseline equality after the baseline-only change.

## Addendum — 2026-10-10 (#9597 S4 review corrections)

The review of the S4 pull request falsified or sharpened several sentences of the 2026-10-09 addendum and of the sections above. The earlier text is
left as written; where it conflicts with this addendum, this addendum governs. `related_adrs` now also lists ADR-072 and ADR-217, which the 2026-10-09
addendum already relied on.

### Curl's stderr is intentionally NOT silenced on converted calls (reverses an old rule)

Two learnings carry the rule "suppress curl stderr (`2>/dev/null`) on a request with an auth header so debug output cannot leak the token":
`2026-02-18-token-env-var-not-cli-arg.md` ("Additional measures") and `2026-03-09-shell-api-wrapper-hardening-patterns.md` (Fix 2, "curl stderr
suppression"). **For a call made through `bc_curl` the rule is reversed, and the half of the argument that depends on the argument guard holds for `bc_curl` only.**
Decision 8 makes `_bc_tail_ok` refuse `--verbose`, `--trace*` and every spelling of them before any request, so a `bc_curl` call has no mode in which curl echoes the
request headers; and the refusal marker `SOLEUR_CREDENTIAL_REFUSED` is printed to stderr from inside the command substitution (`code=$(bc_curl ... )`), so a
`2>/dev/null` on the call discards the only line that distinguishes a refused credential from a transport failure. The battery therefore asserts that no `bc_curl`
statement discards stderr (the S3 stage for workflow steps, an S4 row for scripts), and the converted RLS calls had theirs removed.
**The inline wrappers (`_sig_curl`, `_bearer_curl`) do not run `_bc_tail_ok`** (the 2026-10-09 addendum, "weaker in three stated ways"), so nothing at runtime refuses a
`-v` or `--trace` argument there; the marker argument (do not discard stderr) applies to them equally. What stands in their place is the fixed argument list of each inline
call plus two battery facts: the dynamic replay feeds every call a well-formed run records, inline calls included, through the library's `_bc_tail_ok`, so a header-printing
flag added to an EXECUTED inline call turns that row red; and no `_sig_curl` or `_bearer_curl` call carries a `2>/dev/null` today (checked by a repository grep), but the no-stderr-discard row
covers `bc_curl` statements only, so one added to an inline call is not asserted. A curl call that does NOT go through the chokepoint or an inline wrapper keeps the old
advice. (The `2>/dev/null` on a `doppler secrets get` or a `jq` stays: those are not the transfer.)

### `deploy-inngest-image.yml` `deploy` is inline by choice, not by a pinned property

The 2026-10-09 table gives one reason for three jobs: "the jobs are checkout-free by documented design (... ADR-072, ADR-217 and the workflow-run
deploy invariants pin that area)". That is true of `web-platform-release.yml` `deploy` and `release-outcome` only. `deploy-inngest-image.yml` is a
`workflow_dispatch`-only job (its `if:` skips every other event): it has no `workflow_run` ordering, no `superseded` arm and no comment or suite that
pins the absence of a checkout, and its sibling `restart-inngest-server.yml` (same concurrency group `deploy-inngest-restart`, same shape) uses the
library with a checkout. Its no-checkout state is incidental. It stays inline in this slice so that a merge that already fires four production applies
does not also add a checkout step to a deploy path, and **converting its two sites (the trigger and the verify poll) to the library, with a checkout step, is a tracked
follow-up on #9757 (the argv-credential follow-up list)**, which removes two guard copies, two `_sig_curl` copies and two HMAC copies from the parity audit. Until then the
inline-wrapper clause is met for the release jobs and the luks and verify-tunnel sites, and NOT for this one: it is the clause's one honest
exception, not a precedent.

### Slips in the 2026-10-09 addendum

- `verify-tunnel-ingress-origin.sh` was inline since Tier 2 (#9654), not "already inline since S2"; S4 only moved its HMAC line to the canonical snippet.
- The `ci-deploy.sh` fan-out signer conversion was PR #9805 (`8729cc0dfa`); #9799 is the issue it closed.
- The inline guard copies do not print the same marker as the library. `verify-tunnel-ingress-origin.sh` prints no `SOLEUR_CREDENTIAL_REFUSED`
  line at all (a `::error::` and exit 1), and every other inline copy prints `reason=token_shape` whatever the cause: a control byte, a missing
  `python3` or an empty HMAC key reads as `token_shape` too. That is a lossy label, an AP-021 (ADR-166) diagnostic-honesty residual, not a measurement
  of the credential's shape; read the variable named on the line above the marker, and the library sites for `control_char`.
- "Bounded mechanically by the HMAC parity audit" overstated the bound. The parity audit bounds the HMAC-signing copies. The guard copies are bounded by
  a separate derived pin in the battery: every tracked file that defines `_bearer_ok` (outside knowledge-base and the tests) must equal the canonical
  text byte for byte and the count must equal what `git grep` finds, and the files defining `_sig_curl` or `_bearer_curl` must equal an explicit set
  (a new inline wrapper elsewhere is an unclassified member). The pattern-only copy in `infra-config-verify.sh` is pinned by its own row.
- The HMAC census is no longer one spelling. It reads statements, not lines: continuation lines are joined and any `openssl` statement carrying
  `-hmac` or `-macopt` is a member, whatever the subcommand (`dgst`, `sha256`, `mac`) or the layout. The real tree's set is unchanged (the two
  `scripts/cutover-inngest.sh` arms and the two Markdown exceptions).

### The library does not run only in GitHub Actions steps

Consequences says "the library runs only in GitHub Actions steps, so `SOLEUR_CREDENTIAL_REFUSED` lines are found in the workflow run log". After S4 that
is no longer true. `apps/web-platform/scripts/github-app-key-status.sh` is a script invoked under `doppler run -p soleur -c prd_terraform`, so its
marker is in the invoking terminal, and `apps/web-platform/infra/push-infra-config.sh` is invoked by the `local-exec` provisioner of
`terraform_data.deploy_pipeline_fix`, so its marker is in the Terraform output (the apply workflow's log under CI, the local terminal for a local
apply). The library needs `python3` for `bc_hmac_sha256_hex`, so a machine without it reaches the refusal marker (an empty signature reaches the
shape check), not a push. Layer-6 retrieval still holds for the workflow sites; for these two scripts the retrieval surface is whichever process
invoked them.

### Residual: git hooks inherit the header

`bump-inngest-bootstrap-pin.sh` passes the push credential as `GIT_CONFIG_COUNT`, `GIT_CONFIG_KEY_0` and `GIT_CONFIG_VALUE_0` in the environment of
`git ls-remote` and `git push`. Git runs its hooks (for example `pre-push`) with its own environment, so a repository hook sees those three variables
and with them the `Authorization` header. Same class as the `/proc/<pid>/environ` residual above: a reduction from the world-readable `cmdline`, not
elimination, and a hook is code the checkout already controls.

### Library gaps seen by the reviewers (not changed in this pull request)

Recorded so the next change to `scripts/lib/bearer-curl.sh` starts from them; none is exploitable by the converted call sites, which pass fixed
argument lists:

- `--proto =https` is not pinned: a caller that passes a non-https URL is not refused.
- `--expand-header`, `--expand-user`, `--expand-oauth2-bearer` and `--head` are not covered by the argument guard.
- A refusal at rc 64 (the argument guard) prints a class line but no `SOLEUR_CREDENTIAL_REFUSED` marker; only the credential refusal (rc 2) does.
- `--url` prefix-matches `--url-query` in `_BC_LONG_BODY`, so a `--url VALUE` whose VALUE contains `/proc/`, `/dev/stdin`, `/dev/fd/` or `/dev/.`, or ends in `=-`
  or `@-`, is judged a request body that reads stdin and is refused (a false positive, never a pass).
- Credentials in a URL **path** are not on the config channel and remain on argv: the Slack webhook URL in `web-platform-release.yml`, the `psql`
  connection URIs and the seed scripts' password. They are tracked on the #9757 follow-up list.

### Inline sites now trim leading and trailing ASCII whitespace at the call site (supersedes "an inline copy refuses such a value")

The 2026-10-09 addendum says an inline copy "does not trim a trailing newline (decision 7: an inline copy refuses such a value rather than sending it
trimmed)". The review measured the consequence: a GitHub secret stored with a trailing newline (the commonest storage accident, which decision 7 exists for)
would have turned the release deploy this merge itself fires red, and silenced its failure email, while the 22 library sites accepted the same value. In the
seven inline-using steps (`web-platform-release.yml`: the lock probe, "Deploy via webhook", "Verify deploy script completion", the deploy-failure email and the
release-outcome email; `deploy-inngest-image.yml`: the trigger and the verify poll) a one-line loop now trims the **leading and trailing** ASCII whitespace of
`CF_ACCESS_CLIENT_ID` and `CF_ACCESS_CLIENT_SECRET` (the two email steps: `RESEND_API_KEY`) before the guard. The pinned function text is unchanged, so the inline
`_bearer_ok` itself still refuses whitespace; the trim sits at the call site, in front of it, which is also why the byte-equal pin on the `_bearer_ok` copies did not have to move.

- **Both ends, unlike the library.** `bc_ok` trims trailing whitespace only. The inline loop also trims leading whitespace because the argv form these sites replace
  tolerated a leading blank (curl 8.5.0 sent `CF-Access-Client-Id:  value` and the Cloudflare edge discards leading whitespace of a field value): refusing it would have
  turned a value that worked yesterday into a red release deploy on the merge. The library keeps refusing a leading blank; this is a stated divergence, in the lenient
  direction, limited to the seven steps.
- **ASCII only, locale-independent.** The class is spelled out as bytes (`$' \t\r\n\v\f'`: space, tab, CR, LF, VT, FF), never `[[:space:]]`, so the judgement does not follow
  the runner's ambient locale: a trailing U+2003 is NOT trimmed and is then refused by the guard, under a UTF-8 locale as under `C`. It equals the library's judgement,
  which runs under `LC_ALL=C`, for the ASCII whitespace the two share.
- **The HMAC key (`WEBHOOK_SECRET`) is never trimmed**: it signs as the exact key it was given. Interior whitespace, any control byte, an all-whitespace value and a
  non-ASCII space are still refused.
- **Why the other inline sites do not need it.** `workspaces-luks-cutover.yml` (Hetzner read), `verify-tunnel-ingress-origin.sh` and `infra-config-verify.sh` take their
  values from `doppler secrets get ...`, inside `$(...)`, which strips trailing newlines before the guard sees the value; the accident the trim exists for (a stored
  trailing newline) cannot reach them. A trailing space or a leading blank in a Doppler value would still be refused there, which is the stricter, pre-existing
  behaviour of those sites and is not changed here.
- **The loop's presence is pinned.** The battery DERIVES the population (every workflow step that defines the inline `_bearer_ok() {` and declares a `secrets.*` value for
  one of the three names must carry exactly the canonical loop for exactly those names before the definition, and the executed rows must be exactly that set), so a new
  inline step copied from a donor without the loop turns a row red instead of shipping a stored-newline failure. The executed rows discriminate the shape: both ends,
  every whitespace byte, interior space and LF refused (a strip-all implementation sends a different credential), U+2003 refused under a UTF-8 locale (a `[[:space:]]`
  implementation is seen), all-whitespace refused, and the key untrimmed; mutants of the loop (removed, trailing-only, leading-only, strip-all, locale-class, applied
  to the key) are each judged red by name.

### A refused credential at the infra-config gate pages as `ungraded` (the `credential_refused` output)

`infra-config-verify.sh` runs in `apply-deploy-pipeline-fix.yml` as the step with id `infra_config_gate`. When a credential fails the shape check it makes zero requests,
prints the marker and exits 1; it now also writes `credential_refused=true` to `$GITHUB_OUTPUT`. The alert step "Alert on a red infra-config gate (#7220)" reads that output
ahead of its frame-derived arms: with no request made the status file is empty, so without the output the ladder would have classified the failure `unreachable` and told
the operator the listener may be down, a cause nobody measured. With it the class is `ungraded`: the check never ran, and the text says so and names the verify step's log (the
variable is on the `... unusable` line beside the marker, never its value). Two honest limits. The wiring covers pass 1 (`steps.infra_config_gate`); the second verify pass
(`infra_config_gate_pass2`, which runs the same script) writes its own output under its own step id and is not read, so a pass-2 refusal would reach the
`PASS2_OUTCOME == failure` arm and read as a failed re-push. That is not wired because the secrets cannot change between the two steps of one job, so a credential that passed
pass 1 cannot be refused in pass 2. And `ungraded` is a quieter class than `unreachable` (it carries no `action-required` label), although a refused Cloudflare Access or HMAC
secret is shared by every webhook caller; the marker in the run log and the step annotation are what name it, which is a conscious trade of loudness for a true statement.

## Addendum — 2026-10-11 (#9597 S5)

Slice S5, the last, converts what Rule E still baselined after S4. Status stays `adopting`; the sections above are unchanged and dated, and this addendum records what S5 changed
relative to them. No new ADR ordinal, and ADR-241 is not amended: S5 names no new `secrets.*` reference and changes no tier classification.

### The apply workflow

- **Five sites, the library form.** The three best-effort Better Stack heartbeat-status reads and the two Hetzner volume probes of the recovery-posture step in
  `apply-web-platform-infra.yml` send their credential on curl's stdin config through `scripts/lib/bearer-curl.sh`, sourced from the job's own checkout (all four jobs carry
  one). Curl's stderr is not silenced on these calls, so a refusal marker is visible in the run log. The sweep battery judges the order (the `source` line before the first call in
  each step, which the lint cannot decide statically) and executes the real step bodies.
- **A refusal lands in the verdict class of the failure it replaces.** The heartbeat reads stay non-gating: a refused token makes no request, prints the marker, and the step
  summary reads "unavailable" exactly as an unreadable token did. In the posture step a refused token makes both probes return rc 2, which the existing folds turn into
  `unknown-000` and `unknown`. No consumer treats `unknown-*` as a licence to proceed: the `absent` verdict needs a 404 on the pinned id AND a name count of 0, and the recut
  gate aborts a resume arm unless the probe said `absent`. A refusal therefore cannot manufacture the verdict that admits a bare create.
- **Three operator hints printed the argv form.** The `::error::` texts of the recovery-posture step and the registry-recut step (and the PROVENANCE comment above the id pin) told the operator to
  run `curl -s -H "Authorization: Bearer $HCLOUD_TOKEN" ...`, which puts the Hetzner token on the process command line of whatever machine they paste it into. They now print the stdin-config
  form (`printf 'Authorization: Bearer %s' "$HCLOUD_TOKEN" | curl -s -H @- ...`: a header file read from stdin, so the token is on no argument list). Rule E does not read echo text, so nothing but review pins this.
- **Two claims of the tracker were stale at planning time.** No `doppler secrets ... --token` call exists (the three occurrences in the file are comments; every call uses
  `DOPPLER_TOKEN` in the environment), and the file is well under the 490,000-byte gate, so no comment prose was relocated.

### Final state of baseline E

The target was that baseline E holds only rows owned by other tracked work: the two `apps/cla-evidence` rows (the R2 SigV4 `--user` pair on the legal-evidence upload path), owned by #9756. See the 2026-10-11 (#9756) addendum: they left it too.
That is the tracker's own close condition ("baseline E holds only entries owned by other tracked work"). It is reached when the registry commit of this slice is delivered; if that commit
is carved out, the registry row stays listed and must carry its own owner (a `#N` comment line directly above it, which the battery requires) before `Closes #9597` is claimed.
The owner of the cla-evidence rows is named in a header comment of the baseline and of the census ceiling table (the baseline writer emits it), not in a column, so the file format is
unchanged and `--write-baseline-e` reproduces the header. A row removed by a conversion leaves the ceiling table in the same change. The battery pins set identity with the rows still
owned by tracked work, not a count.

### The registry host: an inline form with a pinned property, delivered by a host replace

- **Four scripts, the inline form.** The Better Stack Logs posting scripts of `cloud-init-registry.yml` (the disk heartbeat, the container-log shipper, the private-NIC guard and the
  boot block) carry an inline form of the library: the stored value's trailing whitespace is trimmed (as `bc_ok` does, because a value with a trailing newline worked on the old argv
  form and curl sent the trimmed header), a judge (`_bs_ok`, byte-identical to the canonical inline `_bearer_ok` apart from the template escape; the library's alphabet
  `[A-Za-z0-9._~+/=-]`) runs before any request, then `curl --disable --noproxy '*' ... --config -` is fed by a process substitution that is a PER-COMMAND redirect (the boot block is
  fed to `bash -s` on stdin, so a bare `--config -` would read the rest of the script). It is not the whole library: the inline copies omit its `env -u` scrub of the variables that
  redirect TLS trust or load libraries and its xtrace refusal.
- **Why inline, and what the pinned property is.** The host has no checkout (cloud-init only, ADR-096), so it cannot source `scripts/lib/bearer-curl.sh`. A cloud-init-written helper was
  the first design and was dropped because the three suites that execute these scripts extract them standalone (a helper at an absolute path would need a path rewrite in each), which is
  the property ADR-280's inline-wrapper clause names ("a pinned property of the job or its suite"), and because a missing helper is a silent not-shipped on a host whose only signal is
  absent rows. The user_data budget is a secondary reason and a movable one: `REGISTRY_GZIP_BUDGET` (21,600 B, ADR-185) is a tripwire below the 24,767 B policy ceiling, and the four
  inline copies cost about 490 B stored (21,012 to 21,500 B), leaving about 100 B under the constant. The four copies of the judge, the trim and the refusal marker, and the three `post()`
  copies, are pinned byte-equal by a parity audit in the battery, which also derives the posting population from the template by set identity per script and requires exactly one raw read
  of the token per script.
- **A refusal is the not-shipped branch, never the egress-FAILED branch.** A refused token prints `SOLEUR_CREDENTIAL_REFUSED script=<name> reason=<token_shape|control_char>` to stderr
  (`zot-disk-heartbeat`, `zot-log-shipper`, `soleur-private-nic-guard`, `zot-log-boot`), makes no request and keeps the script's exit status; the shipper judges once per run, before its
  batch loop, so a refusal is one marker per five-minute run. The marker is NOT observable from Better Stack on this host: the disk-heartbeat and NIC-guard cron lines have no stderr
  redirect and cron has no MTA, the boot block's output goes to `cloud-init-output.log`, and the shipper's cron line pipes stderr to `logger -t zot-log-shipper` (journald, `user.notice`)
  but the shipper ships only the zot container, so it never reaches Better Stack either. A refused token therefore shows as the ABSENCE of the rows. The detector is the hourly
  `scheduled-zot-restart-loop.yml` (a producer silent for 3 h files a `[ci/zot-telemetry-silent]` issue, which does not page, and which decays to a transient reading after 24 h of
  silence); the positive-match Better Stack alerts read silence as healthy, and the token-free disk ping keeps its monitor green. That is why the live token's shape is read before
  merge and why the new host's first rows are read after it. The marker stays NON_PAGING in the Better Stack drift guard, whose pin moved 67 to 71 for the four emitters.
- **Delivery is an automatic replace.** `hcloud_server.registry` carries no `ignore_changes` on `user_data`, so merging a change to the rendered registry user_data makes
  `registry-host-replace-dispatch.yml` dispatch `-replace=hcloud_server.registry` with no reviewer gate (ADR-096, ADR-190, and the runbook `registry-host-replace-dispatch.md`). The running
  host keeps the argv form until that replace is delivered; the new host boots the converted scripts. The registry changes sit in ONE commit (the template, the suites that execute it, the battery's registry rows and this section). Declining the replace is only possible BEFORE the merge, by reverting that commit: a squash merge collapses the slice into one commit and merging dispatches the replace, so after the merge there is nothing left to revert. After the revert the registry row stays in baseline E and needs its own owner line (a `#N` comment above it, which the battery requires).

## Addendum — 2026-10-11 (#9756)

The two `apps/cla-evidence` rows left baseline E and the census ceiling; baseline E is empty. `r2-conditional-put.sh` (and through it `upload-evidence.sh`, `upload-bypass.sh` and the operator-run `cla-backfill-evidence.ts`) and `bootstrap.sh` send the R2 SigV4 pair as `user = "<id>:<secret>"` on curl's stdin config through ONE app-local helper, `apps/cla-evidence/scripts/_r2-sigv4-curl.sh`.

- **Why app-local (Decision 1 deviation, and a second curl site against Decision 2).** Decision 4's lint forbids a `pull_request_target` job from sourcing `scripts/lib/bearer-curl.sh`, and `cla-evidence.yml` is one; the library also builds `header =` lines only. Rejected: a `user =` mode in the library. The `_cf-admin-token.sh` helper is the precedent. The R2 path therefore has its own chokepoint beside the library's.
- **Decision 5 deviation.** The sourced helper has no xtrace refusal of its own (a sourced `exit` kills the caller); each file that calls it carries one, and the helper suite asserts that on code lines (a comment does not count) before the line that sources the helper. The refusal-probe script is exempt by name: it judges synthetic values and starts no curl. **Decision 7 deviation.** No trim: a trailing newline or tab is refused as `control_char` and a trailing space as `token_shape`, because both callers hold the exact 32/64 length. **Decision 8 deviation.** A position-aware ALLOWLIST of curl arguments replaces deny families, plus an in-file anchored URL pin and an `env -u` scrub (the library's 13 names plus the four pair variables; the suite asserts the superset). Curl's own stderr is discarded here, unlike the converted calls of the 2026-10-10 addendum; the helper's refusal lines sit outside that redirect.
- **Exit codes.** A refused credential exits 2 with the marker as the discriminator (Decision 3: curl also exits 2); a bad call, destination or argument returns 64 from the helper and reads as status `000` at the callers; xtrace exits 78; a failed bootstrap probe exits 1. The judge's two variable-name parameters let a caller name the variables its operator set; a caller whose names differ must pre-judge, because the chokepoint's own judge uses the cla-evidence defaults.
- **Transport.** `--disable --noproxy '*'` and the scrub mean every caller, the one-shot bootstrap and the backfill included, needs direct egress to R2 with the system trust store; a proxy or a TLS-inspecting CA reads as status `000`. `cla-evidence` is a required, self-sealing check, so the helper suite's real-curl wire row is the pre-merge proof and the break-glass runbook the recovery.
- **The same pair, one step later.** `bootstrap.sh` Step 2 used to pass the pair as `NAME=value` arguments to the `doppler` CLI (not curl, so outside Rule E's vocabulary). It now writes each secret on the CLI's stdin, one name per call, and keeps `NAME=value` only for the non-secret endpoint and bucket. The two secret writes are NOT atomic: a failure between them leaves `prd_cla` with the new key id and the old secret, which fails the required check on every PR, so that case prints a mixed-pair warning and exits 1, and a read-back compares each stored length with 32 and 64 (values never printed). Recovery needs the same pair and a live admin token (one hour); re-running is idempotent. The bootstrap suite asserts neither value appears on any doppler argv.

## Amendment 2026-10-11 (#9999) — the canonical alphabet governs every credential-shape pin

Scope clarification; the decisions and addenda above are unchanged and dated. The `[A-Za-z0-9._~+/=-]` class `bc_ok` enforces was adopted here as the alphabet a credential may occupy on curl's stdin
config channel — RFC 6750's b64token grammar, the maximal alphabet a bearer value may carry. This amendment extends the same contract to **every credential-shape pattern in the repo**: any
sentinel, detection, redaction, filter or validation expression that judges the *value* of a credential uses the canonical alphabet for that value's character run, or documents at the site why a
narrower class is correct. Anchoring elements are not narrowed by this clause — a `ghs_`/`github_pat_` prefix, an `sk-ant-` infix or a `{36}`-style length bound may stay; what may not stay is a
body alphabet narrower than `[A-Za-z0-9._~+/=-]` justified only by "the vendor issues base62 today".

Enforcement: the Guard-3 census in `scripts/lint-shell-trace-credential-refusal.test.sh` sweeps the tracked corpus for GitHub-prefix char-class literals (`gh[opsur]`/`github_pat_` forms — literal,
bracketed, alternation, factored-prefix, and single-backslash-escaped spellings) and fails on any non-canonical class. A documented-narrower disposition is discharged by a slot in
`_ghs_census_allow()` (keyed on file + exact literal) in that suite, not merely by a comment at the site; the census's own header enumerates the sweep's residual blind spots (extensionless files,
multi-line assembly, separator obfuscation, and the prefixes outside the GitHub family — `sbp_`/`xox`/`sk-ant`/`AKIA` siblings keep their vendor shapes until a rotation teaches otherwise).

### Rejected alternative: per-site vendor-format pins

Modelling each pattern on the vendor's currently issued shape (`ghs_[A-Za-z0-9_]{20,}` and kin) was rejected on measurement, not taste: what a vendor issues is mutable surface the repo cannot
observe, so the pin's correctness is hostage to a rotation that arrives with no notice. The incident chain is the measured cost. When GitHub rotated `ghs_` installation tokens to a ~390-520-char
shape over the b64token alphabet, two retired guards paid out the cost in sequence: a `[A-Za-z0-9_]` refusal guard in the pin-bump script died on every valid live-minted token until #9972 converted
it to the canonical body, and a `[A-Za-z0-9_-]{30,128}` warn-not-throw format validator in `git-auth.ts` warned on every issued token until #9999 retired its length ceiling and widened its class —
the same PR that swept the surviving vendor-format pins in detection, sentinel and documentation sites onto the canonical class. Per-site vendor pins cost one pipeline outage per rotation plus a repo-wide sweep; the
canonical alphabet costs nothing at rotation time because it is already the maximal set the channel can carry.

## Addendum — 2026-10-12 (#9757 residue)

Scope clarification and recorded deviations for the residue of the argv-bearer sweep; the decisions and addenda above are unchanged and dated. Status stays `adopting`; the flip to `accepted` stays with #9905's follow-through.

- **Held-back HMAC arms closed.** `scripts/cutover-inngest.sh` now carries zero `-hmac` operands: the two arms that held the webhook signing key on `openssl dgst -hmac` argv (the registry probe and the doublefire probe) compute the signature with the canonical `python3 -I` HMAC one-liner, which reads the key from an environment variable and the payload from stdin, so the key is on no argv, and the probe-arms tool census in `apps/web-platform/infra/cutover-inngest-workflow.test.sh` allows exactly the canonical HMAC line. The allowance lives in ONE place, the single code view `_probe_arms_code_of` (a fixed-string whole-line match, so a near-miss spelling is not allowed), and every census row reads that view, so the allowance and the sites it judges cannot drift apart.
- **`htpasswd -i` is the stdin form for passwords.** `htpasswd` is not curl, so Rule E of the lint does not see it and the library is not the right chokepoint. The form is `printf '%s' "$PW" | htpasswd -Bin <user>` for create and `htpasswd -vi <file> <user>` for verify; through `docker run` the container also needs docker's own `-i`, because docker forwards nothing without it and the hash then covers an empty password (measured against the real binary in `apps/web-platform/infra/htpasswd-stdin.test.sh`, which also records the exit codes: 0 match, 3 mismatch, 6 absent user, 1 unreadable file). Recurrence is guarded by the S6 derived row in `tests/scripts/test-argv-bearer-sweep.sh`: a `git grep`-derived census of every tracked `htpasswd` invocation, with a floor, that refuses a password on argv outside a residual allowlist. The site converted in this change is the `registry-luks-recut` rehearsal step in `apply-web-platform-infra.yml`; it sits in a dispatch-only job, so the merge-triggered apply never runs it and it is exercised only by the offline refusing-stub-docker row until the next `registry-luks-recut` dispatch. The registry host template (`cloud-init-registry.yml`) was NOT converted in that change (a push to that file replaces the production registry host with no reviewer gate); it is converted by PR B, see the 2026-10-14 section below, which also deleted the S6 allowlist entries that carried those three template lines.
- **Heartbeat URLs on checkout-less hosts.** A Better Stack heartbeat URL carries its secret in the path. On hosts with no repo checkout (so no sourced library, as with the S5 registry copies and the inngest heartbeat feeder) the URL reaches curl on the stdin config (`--config -`) fed by a process substitution (`< <(printf 'url = "%s"\n' "$URL")`), judged first by an inline shape guard: the `https://` scheme, then a NEGATED character class over the rest (`[A-Za-z0-9._~:/?&=%+-]`; a positive pattern would constrain only the first character). Applied in `web-git-data-probe.sh` and `luks-monitor.sh`. A refusal makes zero requests and prints one value-free `SOLEUR_CREDENTIAL_REFUSED` marker; in `luks-monitor.sh` it is judged once before the three-attempt loop and ends as an exhausted push does. Four points are recorded here:
  - **Decision 6 is honored, not waived.** The first plan text said `-q` only and no `--disable --noproxy '*'`. Lint Rule D requires `--disable` first and `--noproxy '*'` for any curl that takes `--config -`, so both heartbeat curls carry them; the plan text is superseded. `-g` is new in `web-git-data-probe.sh`, where it keeps a URL with `[ ]` or `{ }` from echoing itself in curl's glob-parse error.
  - **Decision 7 deviation.** No trim: a trailing newline or other control byte is refused as `control_char` and trailing whitespace as `token_shape`, the same as the SigV4 helper.
  - **No host pin.** The guard exists to close config-directive injection through `url = "%s"` (a quote, backslash or newline) and deliberately does not pin the host, so it cannot mis-refuse a healthy URL and needs no production test seam. A writer to the Doppler key could therefore redirect a beat to another https host; accepted, recorded as a residual.
  - **The inngest heartbeat is deferred to its own PR.** `inngest-bootstrap.sh` runs POSIX `sh`, where the config feed is a pipe (Rule E rejects a heredoc carrying the value). Editing that file turns the `GuardA` row in `cloud-init-inngest-bootstrap.test.sh` red by design until the next tag mint and pin bump, so the commit cannot be green inside this PR; it is preserved on a side branch and tracked in its own issue.
- **Leads (b) and (g), and the residual of (g).** Lead (b): every `::add-mask::` line for a value that is not a bearer token is shape-checked first (`_mask_ok`: no control character, non-empty), so a value cannot end the directive and start a forged one, and an empty read never prints a bare directive. Lead (g): the raw `echo "$BODY"` of a host script's response body on the enumerate, registry-probe, doublefire-probe and re-arm failure paths became one bounded, scrubbed first line (`_body_head`: printable ASCII only, 160 characters, embedded mid-line in the `::error::` text so a body line starting with `::` cannot forge a workflow command). Four raw `echo "$BODY"` sites remain, in the capture arm, the inventory arm, the 2.0 registry-probe arm and the 2.6 doublefire-probe arm: they are outside the four sites lead (g) named, so they were left alone here; converting them is a possible follow-up, not a gap this change claims to close.
- **Residuals.** Same-uid `/proc/<pid>/environ` readers can still read a credential held in a child's environment; this addendum, like decision 1, concerns the world-readable argument list. Three further heartbeat probe scripts and the skill markdown snippets that show an argv-form credential are tracked in #10093. Review leads (c) #10091 and (e) #10092 are deferred.

> **Superseded 2026-10-13 (#10091, #10092, #10093 markdown part):** the last bullet of the 2026-10-12 addendum above says review leads (c) #10091 and (e) #10092 are deferred and that the skill markdown snippets are tracked in #10093. Those three statements are historical and the work landed in PR A, recorded in the sub-section below. The same bullet's "three further heartbeat probe scripts" clause is still live: #10093 stays open for them (PRs B and C).

### 2026-10-13 follow-ups — PR A (#10091, #10092, #10093 markdown)

- **`.env` writers lock, resolve and rename.** The four community setup scripts write `.env` through one byte-identical `_wenv_write` block (pinned by `community-argv.test.sh`). One mutual-exclusion mechanism on every platform: an owner-pid `mkdir` lock directory beside the resolved `.env`, and a bounded wait that fails closed. `flock` was rejected: a flock run and a mkdir run exclude nothing against each other, `flock` without `-w` blocks forever, and `exec {fd}<dir` needs bash 4.1 while macOS ships 3.2. **Stale-lock recovery is itself serialized by a second `mkdir` mutex** (`<.env>.lock.d.recover`): the winner re-reads the lock's owner under the mutex (this narrows the race to the instructions between that read and the removal; it is not a compare-and-swap), removes the lock only if that fresh read is a dead pid, or if the snapshot and the re-read both found no pid after a short pause (an owner that turned from a dead pid into nothing has changed hands and is left alone), and always releases the mutex. The first design (claim the lock by renaming it aside, then put it back) was reproduced losing keys with three or more waiters against a dead-owner lock, the writers all exiting 0, and was replaced; nothing is renamed away any more. The target is resolved with `readlink -f` (a dangling link or a non-regular target is refused, so `mv -f` never replaces a link with a regular file), the temp is a same-directory `mktemp` in its own `.wenv.` namespace under `umask 077` (the sweep touches nothing else), `grep` exit status 2 aborts rather than wiping the file, the lock is removed only when its owner file reads exactly this process, and everything is released on EXIT, INT, TERM and HUP. `.env.lock.d*` and `.env.wenv.*` are git-ignored beside `.env.tmp.*` in THIS repository only: the helper does not probe `git check-ignore`, so in a consumer repository whose `.gitignore` lacks them a killed run can leave an untracked `.env.lock.d` or `.env.wenv.*` that `git add -A` would stage (a temp is mode 600 and holds the full `.env`). Parallel runs of the previous body measured up to seven copies of a key. Residual, stated: a lock whose owner is slower than the empty-owner pause to record its pid can be taken for ownerless; SIGKILL leaves its lock, temp and (if it died mid-recovery) the mutex, which later runs report after the bounded wait.
- **Why four pinned copies and not one sourced lib (CTO-ruled, 2026-10-13).** `_wenv_class`, `_wenv_validate` and `_wenv_refuse` are already four pinned copies, and the recovery protocol was being rewritten during this review; extracting a lib in the same change would mix a refactor into a correctness fix. The consolidation is not filed as an issue (it fits none of the scope-out criteria; the CONCUR gate rejected it): revisit it at the next edit that touches all four copies, and do it then as one change to a sourced lib for every `_wenv_*` helper.
- **The lib check is a control-character check, not the setup-script allow-list.** `soleur_op_env_upsert` is the sink for arbitrary operator-entered credentials, which legitimately contain `$`, `"`, `'`, space, `!`, `#` and `?`; the setup-script allow-list protects curl's stdin config, a different sink, and porting it would refuse real vendor credentials. The lib keeps its CR/LF refusal and adds `[[:cntrl:]]` under `local LC_ALL=C` with a value-free `SOLEUR_BOOTSTRAP_BAD_ARG ... reason=value-contains-control-char`. The file the lib writes is by default a different file from the repo-root `.env` the community scripts source, and no consumer the suite greps sources it, so the raw form stays; a suite row goes red if one ever does. `ENV_FILE` is overridable, so pointing it at the repo-root `.env` is outside that claim. U+0085, U+2028 and U+2029 are not refused: nothing the rows grep treats them as a line end and refusing them would reject legitimate non-ASCII credentials. The lib's own read-modify-write takes no lock (tracked in #10204).
- **Marker classes.** `SOLEUR_CREDENTIAL_REFUSED` now carries two reason classes: `token_shape|control_char` (a malformed credential: fix the value, do not retry) and `env_*` with `var=ENV_FILE phase=write-env` (an operational write-env fault: lock timeout, `env_lock_not_dir`, unreadable, unresolvable, dangling or non-regular `.env`, unwritable directory, failed write). Consumers branch on the reason prefix; `MARKER_RE` mirrors both and pages neither. The comment above `MARKER_RE` (the only `apps/**` edit in this PR, comment-only) names the six community emitters and both classes. A separate marker family for operational faults is deferred to the next legitimate `MARKER_RE` edit (tracked in #10275).
- **Agent-run markdown teaches the stdin form.** Ten curl commands in eight plugin markdown files, plus two prose rewordings, now pass the credential through `--config -` after a one-line shape `case` (`LC_ALL=C`, `--proto '=https'`, no `--noproxy '*'`: these are third-party API calls and a host behind a mandatory egress proxy must keep working). The form is inline, with no reference to `scripts/lib/bearer-curl.sh`, because a consumer repo has no checkout. Recurrence is guarded by stage S7 of `tests/scripts/test-argv-bearer-sweep.sh`: a derived census over tracked `plugins/**/*.md` (logical lines, backslash continuations joined) for the nine header names Rule E carries, a shrink-only allowlist whose one entry is `skill-creator/references/api-security.md` (a document about chat visibility), a floor, mutation rows, and rows that execute the converted snippets against a stub `curl`. **S7 is the only guard for that population and its scope is stated, not total:** it does not read `knowledge-base/**` (including the runbooks agents follow), the echoed strings in `.github/workflows/scheduled-terraform-drift.yml` (which still print an argv-form `curl -H "Authorization: Bearer ..."` into issue bodies), other header names (`Cookie`, `Proxy-Authorization`, ...), `-u`/`--user`, tokens in URLs or `-d`, clients other than `curl`, or non-markdown files. Widening it to `knowledge-base/**` lands in the same change that converts those runbooks and the workflow strings (tracked in #10274), so the gate arrives green. The PR template, which sits outside S7's scan, was converted by hand in PR A. `apps/web-platform/infra/sentry/README.md` was deliberately NOT converted there: any path under `apps/web-platform/infra/` fires the infra apply workflows on merge, so PR A (a routine release set) leaves it for a PR that already owns an apply (tracked in #10274).

### 2026-10-14 follow-ups — PR B (#10119, registry heartbeat curls of #10093)

The registry template (`cloud-init-registry.yml`) is converted in one commit with its suites, so declining the host replace it fires is one revert before merge. The three htpasswd sites now take the password on stdin: the divergence probe is `printf '%s' "$2" | htpasswd -vi /etc/zot/htpasswd "$1"` (`$?` is still `htpasswd`'s own status and the 0 / 3 / other → `true` / `false` / `unknown` map survives the pipe. Measured at review: neither `pipefail` nor errexit would change that today, because `printf` is a builtin that exits 0 and errexit is cleared inside the command substitution that calls the function, so the earlier rationale that either option would turn rc 3 into `unknown` was wrong; the static row that bans them pins the ENVIRONMENT the map was measured in, so adding either later is a deliberate re-measurement), and the boot step creates `/etc/zot/htpasswd` with `install -m 600 /dev/null` (the mode is narrow from birth, with no post-hoc `chmod`) and feeds each entry from its own pipe (`-Bin`, `>` for the pull user, `>>` for the push user), so neither `htpasswd` can consume the `bash -s` script text. The two heartbeat curls (disk, liveness) read their URL from a stdin config line (`curl --disable --noproxy '*' -g -fsS -m 10 --config - < <(printf 'url = "%s"\n' '<literal>')`, `-o /dev/null` kept on the liveness one). There is no runtime shape guard on those two (the value is a provider-generated Terraform literal and the user_data gzip budget is scarce, headroom measured at 48 B), so the contract is held at render time: `registry-userdata-budget.test.sh` asserts the two rendered literals match `^https://[A-Za-z0-9._~:/?&=%+-]+$` and that a quote, a double quote, a backslash, a newline and plain `http` do not. Residual, stated: that proves the stub render, not the live provider value; a real `betteruptime_heartbeat.url` with a quote in it would break the quoting at the next replace, and the only detector is the heartbeat going dark.

**Guard.** Stage S6 of `tests/scripts/test-argv-bearer-sweep.sh` no longer carries a residual allowlist: `S6_ALLOW` is empty and `S6_ALLOW_CEIL` is 0 (the grow-by-one case is judged RED by the same predicate), the three registry sites are asserted by identity (file and whole stripped line), and a new `S6-REG` scan reads every logical line of the YAML with a `curl` command word and a `*_heartbeat_url` interpolation, drops the stdin feed, and requires the remainder to be empty, the two converted sites by exact identity. `htpasswd-stdin.test.sh` gains ten rows that run the REAL ZOTEOF block (cut from the same offline render the budget script makes) through `bash -s` in the digest-pinned `ubuntu:24.04` + `apache2-utils` image: mode 600 even under `umask 000`, two verifying bcrypt entries, a failing first `htpasswd` aborting before the `>>` line, the empty-token guard, and an argv-recording wrapper ahead of the real binary proving no password and no option cluster holding `b` reaches `htpasswd`, with an argv-form control the same judge must call RED. **Delivery** is the unattended registry host replace (`registry-host-replace-dispatch.yml` push trigger); the verification is the follow-through probe `scripts/followthroughs/registry-htpasswd-stdin-10119.sh`. Its PASS needs three good rows on a boot_id different from the pre-merge host's AND a `registry-host-replace-dispatch.yml` run that succeeded after the merge (the sweeper job carries `actions: read`, #8450; an earlier draft of the probe claimed the sweeper's token cannot read Actions runs, which was false): a changed boot_id alone is not delivery, because the registry self-reboots and an unreplaced old host would report `matches=true` from its old argv-built file under a fresh boot_id. A dispatcher failure comment escalates only while the probe has no PASS, `dt` is normalised before it is compared with `mergedAt` (Better Stack's is space-separated), and a wait that outlives 24h from the merge becomes CANNOT ESTABLISH.

**Scope of the S6 and S6-REG scanners (stated, not total).** They are text scanners over a fixed corpus: S6 reads `apps scripts .github` (not `*.test.sh`, not `*.md`), S6-REG reads the one registry template, S6-HB the top-level `apps/web-platform/infra/*.sh` heartbeat scripts. S6-REG now treats a comment line as never continued by a trailing backslash and `/usr/bin/curl` as a curl command word (both found by review); it still does not see another HTTP client, a URL carried in a variable, or any other file. `scripts/registry-restore-from-ghcr.sh` (`crane auth login ... -p`) sits outside every corpus (two sites, a pre-existing argv password; tracked as an item on the #9757 checklist).

> **Superseded 2026-10-19 (#9757):** the last sentence above is historical. `scripts/registry-restore-from-ghcr.sh` now feeds both registry passwords to `crane auth login --password-stdin` and stage S8 (below) scans for the class.

### 2026-10-15 follow-ups — PR C (#10120, probe scripts of #10093)

> **Superseded 2026-10-15 (#10120, #10093):** two sentences above are historical. The 2026-10-12 addendum's "The inngest heartbeat is deferred to its own PR" bullet and its residuals bullet's "Three further heartbeat probe scripts ... are tracked in #10093" clause are both closed by this section: the inngest heartbeat body and the three probe scripts are converted. #10093 and #10120 stay OPEN as the tracker for the residuals listed below.

The last four heartbeat sites leave curl's argv and the residual allowlist of stage S6-HB is deleted (`S6H_ALLOW` is empty, `S6H_ALLOW_CEIL` is 0, and the grow-by-one case is judged RED by the same predicate). Facts a future engineer cannot derive from the code:

- **Pipe, not heredoc, for the POSIX body.** The inngest heartbeat body (the `HEARTBEATSCRIPTEOF` heredoc of `inngest-bootstrap.sh`) is `sh` (dash on Ubuntu): the config is fed by `printf 'url = "%s"\n' "$URL" | /usr/bin/curl --disable --noproxy '*' -gfsS --max-time 10 --config -`. Rule E of the lint refuses a heredoc feeding the config and dash has no process substitution. There is no `exec` before curl (it would only replace the pipeline's forked subshell) and no `pipefail`, so the script's status is curl's, as before. The guard is `https://*` as its own `case`, then a NEGATED class over the rest, under `LC_ALL=C`. A dash row in `inngest.test.sh` runs the rendered body inside the digest-pinned ubuntu image (authoritative and mandatory in CI; a labelled non-pinned local `dash` is the only fallback; a skipped row never counts toward the floor).
- **The three probes use the bash form of the `web-git-data-probe.sh` guard**, byte-identical `_hb_url_ok` and `_hb_curl` (pinned by a parity row in S6-HB), one `_hb_curl` call per attempt (a process substitution is consumed once). The guard sits after each script's test seam and empty-URL branch.
- **Refusal rate limit, own stamp each (CTO-ruled, 2026-10-15).** A refused value logs at most one `SOLEUR_CREDENTIAL_REFUSED` line per hour per script (3600 s), on a stamp that is never shared with a fault or canary limiter, because a refusal must not mask a real fault line and a fault line must not mask a refusal: `web-zot-consumer-probe.sh` reuses its `_window_open` helper with an optional window argument (default 1800 s, so existing callers are unchanged), `inngest-consumer-probe.sh` and `web-private-nic-guard.sh` carry the same normalising limiter inline (non-digits and stamps longer than 10 digits read as "emit", then a base-10 conversion so a zero-padded stamp cannot crash it). A future-dated or garbage stamp reads as "emit", and an unwritable stamp (read-only or absent `/run`) fails OPEN: the line ships on every tick, loud rather than silent. The NIC guard derives its stamp path from its single test-root seam; the zot and consumer probes take theirs from an environment variable like their other marker seams (`SOLEUR_PROBE_REFUSAL_MARKER`, `SOLEUR_INNGEST_CONSUMER_REFUSAL_MARKER`; the heartbeat body likewise honours `INNGEST_HEARTBEAT_REFUSAL_STAMP` and `INNGEST_HEARTBEAT_GATE_STAMP`), an accepted residual of the same class as those seams (needs a Doppler or env-file writer). An unset URL is `reason=empty` on the inngest web render (no dark arm there) and on the NIC guard when it could otherwise ship.
- **Exit status after a refusal (CTO-ruled, 2026-10-15).** The three probes keep their fail-soft exit (the missed beat is the alarm). The inngest body exits **0** for a present-but-malformed value (`token_shape`, `control_char`) for the same reason: a non-zero exit fires the unit's unlimited `OnFailure` logger on every 60 s tick (at least ~2.9k rows/day, 2 rows x 1,440 ticks: the ERR row on Source 4 plus the systemd failure row on Source 1, against a Source 4 headroom of about 5.1k/day as measured in #7228 and not re-measured since; the #6536 storm shape). Only `reason=empty` keeps exit 2, because the web render has no dark arm and an absent URL on the live pusher must stay loud, as curl's own blank-URL rejection was; that path therefore keeps the OnFailure storm exposure BY CHOICE (pre-existing since #6536, a provisioning fault rather than a retried state), so the exit-0 ruling does not cover it. Consequences to know: a refusal no longer shows up as a failed unit, so the only signals are the marker and the monitor page; the unit's `inactive` state in `/hooks/deploy-status` (`services.inngest_heartbeat`) and the bootstrap's heartbeat-oneshot warning no longer exclude a credential refusal (read `inngest_heartbeat_journal_tail` or the marker); and during the cutover window in which both hosts hold a URL for the shared `soleur-inngest-server-prd` monitor, web-1's still-serving beats keep it green, so the dedicated host's `SOLEUR_CREDENTIAL_REFUSED script=inngest-heartbeat` marker must be absent before `flip=armed`.
- **Diagnosing a page without SSH.** A missing beat while the host is healthy: query the unit's tag for `SOLEUR_CREDENTIAL_REFUSED` over at least 70 minutes (the marker is hourly-limited): `doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 70m --grep SOLEUR_CREDENTIAL_REFUSED`, decode the row and filter on its `SYSLOG_IDENTIFIER`, then fix the Doppler value (`soleur/prd` `WEB_ZOT_CONSUMER_URL_<HOST>`, `WEB_NIC_GUARD_URL_<HOST>`, `INNGEST_CONSUMER_URL`, `INNGEST_HEARTBEAT_URL`; the dedicated inngest host reads `INNGEST_HEARTBEAT_URL` from `soleur-inngest/prd`); do not revert the guard. The inngest runbook and the Better Stack query runbook point here.
- **Residuals (tracker: #10093, which stays open).** (1) Same-uid `/proc/<pid>/environ` readers can still read the URL held in a child's environment: the three web-1 probe units run as root, but `inngest-heartbeat.service` runs as `deploy`, so its URL is readable by that uid and root (the cmdline exposure to every local uid is gone). `bash -x` on a host would still print the URL variable (only the NIC guard refuses xtrace; #10363), and the unit's inner `bash -c` expansion before the refusal is #9639. (2) Web-2 and the dedicated inngest host receive the converted scripts later than web-1: the three `terraform_data` installs deliver to web-1 only, web-2 gets the scripts from the image seed at its next fresh boot or replace, and the inngest host gets the heartbeat body at a dispatch-only image deploy; until then they keep the argv form. (3) The inngest body does not redirect curl's stderr, and `https:///<token>` or `https://<token>` passes the shape guard, so curl's `-S` error text can name a secret in host position in journald (the old argv shape did the same; the probes send curl stderr to `/dev/null`). (4) `web-git-data-probe.sh` still emits its refusal marker on every tick, unlimited. (5) Sentry Crons check-in URLs carry the Sentry public key in the path on argv in `cron-egress-*.sh`; unclassified (Sentry public keys are public by design). (6) Heartbeat URLs baked into `cloud-init-registry.yml` user_data are readable from the Hetzner metadata service; stdin conversion does not address this. (7) The S6-HB scanner is a text heuristic and not exhaustive; besides the names in its header it does not see curl inside a quoted string, producer and consumer split across segments, other HTTP clients, a quoted metacharacter before the URL, files in subdirectories or not named `*.sh`, or units. These pre-date PR C (the scanner dates from #10086). It covers the stage contract's `*HEARTBEAT_URL` plus `curl`, `/path/curl`, `\curl` and backtick spellings. (8) There is no Better Stack log alert keyed on the marker; detection is the monitor page plus the query above. (9) The unset-URL WARN lines of `web-zot-consumer-probe.sh`, `inngest-consumer-probe.sh` and `web-git-data-probe.sh` are unlimited (one row per tick; they pre-date PR C). (10) The `FAULT` limiter of `inngest-consumer-probe.sh` still suppresses on a future-dated stamp (a known latent silent-canary shape, not fixed here; only its zero-padded and over-long stamp handling was aligned).

### 2026-10-19 follow-ups: registry login verbs (#9757)

- **The stdin rule now covers registry login commands.** The restore engine's sink and GHCR logins are `printf '%s' "$TOKEN" | $CRANE auth login ... --password-stdin` (a pipe from a builtin: a here-string is a temp file on bash older than 5.1). The engine also refuses to run traced with a live registry credential (exit 78) and unsets the credential names after login.
- **Stage S8 of `tests/scripts/test-argv-bearer-sweep.sh` enforces it.** Corpus: the whole tracked tree minus `*.test.sh`, `tests/` and `knowledge-base/`, with `.md` only under `plugins/`; the verb is variable-aware (`$CRANE auth login`, `"$DOCKER_BIN" login`) because a literal `crane` pattern sees none of the engine's sites. Floor: 12 sites in 7 files. Named blind spots: a feeder that itself carries the token on argv, binaries named without crane/docker/podman, commands built by concatenation or `eval`, and a bare flag-variable such as `$SINK_TLS_FLAG` (neither host nor visible option).
- **S8 selects on the full run only.** The affected-test array does not name its population, and editing it would arm every PR-gated battery (CTO-ruled, 2026-10-19). Deferred review leads from the same umbrella are tracked in #10529, #10530, #10531 and #10532.
