# Runbook — the git-data rung-2 boot rehearsal

Boots the real git-data cloud-init once on a **throwaway** host, so the first real boot of
that template is not the production host holding every connected user's source code.

This is **not** a second DO-NOT-DISPATCH banner. The hold lives in `git-data-birth.md` and in
`git_data_rung2_rehearsal_gate`; this file only says how to run the rehearsal and how to read
what comes back.

## Dispatch

```bash
gh workflow run git-data-rung2-rehearsal.yml \
  -f confirm=REHEARSE-GIT-DATA -f dry_run=true
```

The workflow's own input descriptions are the source of truth for the flags — they are not
restated here, because a second copy drifts. Two human gates and nothing else: the
`web-platform-infra-apply` environment approval on the dispatch, and your review of the
evidence PR. There is no SSH anywhere in this route; the rehearsal host is never logged into.

Start with `dry_run=true`. It renders, plans, asserts the plan **creates only rehearsal
addresses and destroys nothing**, and stops. Re-dispatch with `dry_run=false` when you intend
to spend a real host (~€0.02, ~8 minutes).

## The three artifacts, and what each one rules out

| Artifact | What it establishes |
|---|---|
| **Source-liveness anchor** — any Better Stack row from any *other* host | The instrument works. Without it, zero rows from the rehearsal host is ambiguous between "booted dark" and "my query/credentials/source are broken", and reading it either way is a guess. |
| **`stage:boot_complete`** from the rehearsal host, four booleans positive | The boot reached its final stage with every invariant met. |
| **No `level:fatal`** from that host | Nothing in the chain hit its trap. Meaningful only *because* the anchor proved the channel is live. |

Each is written into the evidence file **with the query that retrieved it**. A result without
its question is unreproducible.

## Reading the outcome

The capture **step** reports five states; the capture **script** is three-state (0/1/2).
States 3 and >3 are synthesized by the workflow, because they describe failures of the
*wrapper* that the script has no knowledge of — it never ran. The distinction is the point:

- **PASS (0)** — evidence written, uploaded as an artifact. See **After a PASS** below;
  merging that PR is what releases the birth interlock.
- **FAIL (1)** — a fatal, or a false assertion. This is the failure class the whole route
  exists to find: it would have looked green from the `terraform apply`. No evidence written.
  Since #7481 a FAIL has **two** provenances, and the output says which:
  - *Better Stack-derived* — the host reported `level:fatal`, or `boot_complete` with a false
    assertion.
  - *Sentry-derived* — the host reported a fatal that Better Stack structurally could not see.
    Everything before `doppler run` reaches Sentry only, because the emitter's Better Stack
    block is gated on `BETTERSTACK_LOGS_TOKEN`, which exists only under `doppler run`. This is
    the 2026-07-31 shape: the rehearsal died at `luks_open` and the route reported TRANSIENT.
    The verdict now names `stage`, `rc` and the `detail` text, so the cause is in the artifact
    rather than something to re-query by hand. A Sentry-derived FAIL can also arrive on an
    otherwise-PASSing Better Stack read — a fatal on either channel beats a clean read on the
    other, and no evidence is written.
- **TRANSIENT (2)** — no verdict, from **either** channel. **Not** evidence the host booted
  dark. The step output carries the Better Stack condition and then a `second channel:` line
  saying what Sentry contributed. Sub-causes, all printed rather than inferred:
  - `second channel: Sentry has NO level:fatal event` — both channels genuinely quiet.
  - `second channel: UNAVAILABLE — Sentry refused the read (rc=77|78)` — a 401/403. This is
    **deterministic**: a re-dispatch reproduces it exactly and burns another paid host. Fix
    `SENTRY_ISSUE_RO_TOKEN`'s scope instead.
  - `second channel: SKIPPED` — `jq` or the token is absent. Also not a host verdict.
- **WRAPPER FAILURE (3)** — `doppler run` exited 1 **twice** without the capture script ever
  producing its `RUNG2_CAPTURE_VERDICT=` sentinel. This says nothing about the host; it never
  got to speak. **You are not asked to go and look at anything here:** since #7481 the workflow
  self-probes that credential (`doppler secrets --only-names -p soleur -c prd_terraform`,
  which never prints a value) and its `::error::` states whether the token can read the config.
  If it can, the fault is not token scope — read the capture-log artifact. The poll stops here
  rather than retrying, because a bad credential is not transient and retrying it spends
  ~16 minutes on a paid host to report the least actionable verdict.

- **UNEXPECTED EXIT (>3)** — the wrapper exited a code that is not a verdict at all: `64`
  is the capture script's own usage error, `126`/`127` mean `doppler` or the script was not
  found or not executable. A toolchain fault, not a statement about the host.

On every non-PASS the run also uploads a `git-data-rung2-capture-log` artifact — that is the
diagnostic; download it before re-dispatching. **It is redacted**: the Better Stack host and
username are replaced with `<redacted:VAR>` placeholders, because this repo is public and an
Actions artifact is downloadable by any authenticated GitHub user. If the redaction step
itself fails there is no artifact rather than a raw one.

Since #7481 you are **not** asked to go and consult Sentry yourself. Everything before
`doppler run` reaches Sentry only — the emitter's Better Stack block is gated on
`BETTERSTACK_LOGS_TOKEN`, which exists only inside `doppler run` — so a host that dies early
is invisible to the Better Stack channel. The capture script now performs that read itself on
every no-verdict path and prints a `second channel:` line saying what it found, including the
failing `stage`, its `rc`, and the `detail` text. A fatal there is reported as a **FAIL**, not
as TRANSIENT.

That matters because the reverse is what happened on 2026-07-31: the rehearsal died at
`luks_open`, Better Stack never saw it, the route reported TRANSIENT, and the cause had to be
re-queried by hand afterwards from a host that no longer existed. If the capture log's
`second channel:` line says `UNAVAILABLE` or `SKIPPED`, that is a statement about the
instrument — read what it names and fix that; it is not evidence about the host.

The redaction step's tuple covers every credential in the capture step's environment, not only
the Better Stack pair — including both R2 keys, which this workflow writes into `$GITHUB_ENV`
and which grant Terraform state read.

## After a PASS

The workflow is `permissions: contents: read` and **cannot commit its own evidence**. That is
the interlock, not a gap: a route that writes its own gate-releasing file turns a
two-human-gate birth into a one-dispatch birth, where approving "run a rehearsal" would
release the interlock as a side effect. So you land it yourself.

The job summary on a PASS prints this same sequence, so you can work from where you already
are. Substitute the run id of the rehearsal that passed:

```bash
gh run download <run-id> -n git-data-rung2-boot-evidence
mv git-data-rung2-boot-evidence.env apps/web-platform/infra/

# Validate BEFORE committing — the gate tells you what it would refuse and why.
source tests/scripts/lib/git-data-birth-readiness-gate.sh
git_data_rung2_rehearsal_gate \
  apps/web-platform/infra/cloud-init-git-data.yml \
  apps/web-platform/infra/git-data-rung2-boot-evidence.env

git checkout -b evidence-git-data-rung2
git add apps/web-platform/infra/git-data-rung2-boot-evidence.env
gh pr create
```

`RELEASED` means the birth may proceed once that PR merges. `HOLD` names the refusal — read
it rather than re-dispatching, because a HOLD on fresh evidence usually means the template
moved, not that the rehearsal was bad.

**Open the PR promptly.** The evidence carries a sha256 of `cloud-init-git-data.yml` and its
nine `file()`-bound payloads, so *any* merge touching those between the rehearsal and this PR
invalidates it. `infra-validation.yml` catches that on the PR, but the remedy is a full
re-rehearsal — another paid host and another approval.

## If teardown fails

Re-dispatch with `teardown_only=true`. A surviving host is a paying box with a LUKS volume
attached; the scheduled drift workflow sweeps for the `soleur-git-data-rehearsal-` prefix
daily and files an issue, but the recovery is this arm, not a console click (a Terraform
destroy also reclaims the volumes and the scratch Doppler config).

## Two things that will mislead you

- **The evidence self-invalidates.** Its hash covers the cloud-init *and* all nine
  `file()`-bound payloads. Any later edit to what ships re-holds the birth, by design. The
  rung-2 PR check reports that on the PR that caused it rather than at dispatch time.
- **A clean rehearsal emits no `fatal`.** Do not go looking for one. The fatal channel is
  proven at rung 1 by `git-data-runcmd-rehearsal.test.sh`; rung 2 proves the real-host facts
  rung 1 cannot reach — TLS egress from a real host, a real `doppler run`, a real
  `cryptsetup luksOpen`.
