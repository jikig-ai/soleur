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
   collides with curl's own exit 2, so no caller branches on `rc == 2`; the marker is the discriminator. Where a bare rc 2 would fold into a
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
`actions/checkout` uses; git 2.31 or later). The token passes a shape guard (`[A-Za-z0-9_]`, the installation-token class) before the header is
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
suppression"). **For a call made through `bc_curl` (and the inline wrappers) the rule is reversed.** Decision 8 makes `_bc_tail_ok` refuse
`--verbose`, `--trace*` and every spelling of them before any request, so curl has no mode in which it echoes the request headers; and the refusal
marker `SOLEUR_CREDENTIAL_REFUSED` is printed to stderr from inside the command substitution (`code=$(bc_curl ... )`), so a `2>/dev/null` on the call
discards the only line that distinguishes a refused credential from a transport failure. The battery therefore asserts that no `bc_curl` statement
discards stderr (the S3 stage for workflow steps, an S4 row for scripts), and the converted RLS calls had theirs removed. A curl call that does NOT go through the chokepoint keeps the old
advice. (The `2>/dev/null` on a `doppler secrets get` or a `jq` stays: those are not the transfer.)

### `deploy-inngest-image.yml` `deploy` is inline by choice, not by a pinned property

The 2026-10-09 table gives one reason for three jobs: "the jobs are checkout-free by documented design (... ADR-072, ADR-217 and the workflow-run
deploy invariants pin that area)". That is true of `web-platform-release.yml` `deploy` and `release-outcome` only. `deploy-inngest-image.yml` is a
`workflow_dispatch`-only job (its `if:` skips every other event): it has no `workflow_run` ordering, no `superseded` arm and no comment or suite that
pins the absence of a checkout, and its sibling `restart-inngest-server.yml` (same concurrency group `deploy-inngest-restart`, same shape) uses the
library with a checkout. Its no-checkout state is incidental. It stays inline in this slice so that a merge that already fires four production applies
does not also add a checkout step to a deploy path, and **converting its two sites (the trigger and the verify poll) to the library is a recorded
follow-up (S5 or a chore)**, which removes two guard copies, two `_sig_curl` copies and two HMAC copies from the parity audit. Until then the
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
is no longer true. `apps/web-platform/scripts/github-app-key-status.sh` is a script an operator or an agent runs (`doppler run -p soleur -c
prd_terraform -- bash ...`), so its marker is in that terminal, and `apps/web-platform/infra/push-infra-config.sh` is run by the `local-exec`
provisioner of `terraform_data.deploy_pipeline_fix`, so its marker is in the terraform apply output (the apply workflow's log when CI applies, the
operator's terminal when a person does). The library needs `python3` for `bc_hmac_sha256_hex`, so a machine that runs `terraform apply` without it
gets the refusal marker (an empty signature reaches the shape check), not a push. Layer-6 retrieval still holds for the workflow sites; for these two
scripts the retrieval surface is whoever ran them.

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

### Inline sites now trim trailing whitespace at the call site (supersedes "an inline copy refuses such a value")

The 2026-10-09 addendum says an inline copy "does not trim a trailing newline (decision 7: an inline copy refuses such a value rather than sending it
trimmed)". The review measured the consequence: a GitHub secret stored with a trailing newline (the commonest storage accident, which decision 7 exists for)
would have turned the release deploy this merge itself fires red, and silenced its failure email, while the 22 library sites accepted the same value. In the
seven inline-using steps (`web-platform-release.yml`: the lock probe, "Deploy via webhook", "Verify deploy script completion", the deploy-failure email and the
release-outcome email; `deploy-inngest-image.yml`: the trigger and the verify poll) a one-line loop now trims the **trailing** whitespace of
`CF_ACCESS_CLIENT_ID` and `CF_ACCESS_CLIENT_SECRET` (the two email steps: `RESEND_API_KEY`) before the guard, as `bc_ok` does. The pinned function text is
unchanged, so the inline `_bearer_ok` itself still refuses trailing whitespace; the trim sits at the call site, in front of it. Interior whitespace and any
control byte are still refused, and **the HMAC key (`WEBHOOK_SECRET`) is never trimmed**: it signs as the exact key it was given. The battery executes each
of the seven steps with a trailing newline and space (trimmed value sent, signature unchanged), an interior control byte (refused) and a key with a trailing
newline (signs as that exact key). The other inline guards (`workspaces-luks-cutover.yml`, `verify-tunnel-ingress-origin.sh`, `infra-config-verify.sh`) do
not trim and still refuse a trailing newline.
