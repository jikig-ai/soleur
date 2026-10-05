# Runbook — the git-data rung-2 boot rehearsal

Boots the real git-data cloud-init once on a **throwaway** host, so the first real boot of
that template is not the production host holding every connected user's source code.

This is **not** a second DO-NOT-DISPATCH banner. The hold lives in `git-data-birth.md` and in
`git_data_rung2_rehearsal_gate`; this file only says how to run the rehearsal and how to read
what comes back.

## Dispatch

```bash
gh workflow run git-data-rung2-rehearsal.yml --ref main \
  -f confirm=REHEARSE-GIT-DATA -f dry_run=true
```

**Pass `--ref main` explicitly.** Since #8010 the gate reads the run's `head_branch` and refuses
anything but `main` (`RUN_NOT_MAIN`), so a dispatch off a feature branch spends a paid host on
evidence that can never release the interlock.

Being explicit is worth it even though `gh` already defaults correctly. An earlier revision of
this runbook justified the flag by claiming `gh workflow run` "defaults to the ref your checkout
is on" — that is FALSE, and it was measured false at review: `gh workflow run --help` (gh
2.101.0) documents the default as the repository's default branch, and `gh` does not read local
HEAD. The flag guards against a caller who sets `--ref` deliberately, not against `gh`'s default.

The workflow's own input descriptions are the source of truth for the flags — they are not
restated here, because a second copy drifts. Two human gates and nothing else: the
`web-platform-infra-apply` environment approval on the dispatch, and your review of the
evidence PR. There is no SSH anywhere in this route; the rehearsal host is never logged into.

Start with `dry_run=true`. It renders, plans the **seed** phase, asserts that plan **creates only
rehearsal addresses and destroys nothing** (`scripts/git-data-rung2-plan-shape.sh … additive`), and
stops. Re-dispatch with `dry_run=false` when you intend to spend a real host. Since #5274 a real run
boots three times on one address (see *The three-boot run*), so budget roughly three short host
lifetimes and up to ~2 hours of wall clock in the worst case.

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
    **Narrowed by #7460:** the ingest token is now baked at `0600`, so EIGHT of the nine stages
    reach Better Stack. Only the `bootcmd` beacon is Sentry-only, and structurally so — it
    fires before `write_files`, so the shared emitter does not exist yet. This is
    the 2026-07-31 shape: the rehearsal died at `luks_open` and the route reported TRANSIENT.
    That stage now reaches BOTH channels, which is the point of #7460 — but the Sentry-derived
    arm is retained, because it is what still covers the beacon and any run whose baked token
    has been rotated out from under it.
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

Since #7481 you are **not** asked to go and consult Sentry yourself. Before #7460 everything
prior to `doppler run` reached Sentry only, so a host that died early was invisible to the
Better Stack channel; the ingest token is now baked at `0600` and eight of the nine stages
reach both. The one remaining Sentry-only emit is the `bootcmd` beacon, and a
Better-Stack-side token rotation can silently return the pre-`doppler run` stages to
Sentry-only until the host is replaced — which the emitter now reports at
`stage:betterstack_ingest`, `level:warning`, rather than swallowing.
The capture script performs that read itself on
every no-verdict path and prints a `second channel:` line saying what it found, including the
failing `stage`, its `rc`, and the `detail` text. A fatal there is reported as a **FAIL**, not
as TRANSIENT.

That matters because the reverse is what happened on 2026-07-31: the rehearsal died at
`luks_open`, Better Stack never saw it, the route reported TRANSIENT, and the cause had to be
re-queried by hand afterwards from a host that no longer existed. If the capture log's
`second channel:` line says `UNAVAILABLE` or `SKIPPED`, that is a statement about the
instrument — read what it names and fix that; it is not evidence about the host.

The redaction step's tuple was widened from three names to eleven — including both R2 keys,
which this workflow writes into `$GITHUB_ENV` and which grant Terraform state read.

**It does NOT cover every credential in that step's environment, and you should not treat the
artifact as safe on that basis.** The step runs under `doppler run -c prd_terraform`, which
exports the whole config: measured 2026-09-03, 160 names, roughly 70 of them credential-shaped
and outside the allowlist. The tuple is a name-allowlist over an environment holding a whole
Doppler config — a fail-open shape that widening does not change. The fix that changes the
shape is narrowing the config this step runs under; it is tracked, not done. Treat the
artifact as sensitive.

## After a PASS

The workflow is `permissions: contents: read` and **cannot commit its own evidence**. That is
the interlock, not a gap: a route that writes its own gate-releasing file turns a
two-human-gate birth into a one-dispatch birth, where approving "run a rehearsal" would
release the interlock as a side effect. So you land it yourself.

The job summary on a PASS prints this same sequence, so you can work from where you already
are. Substitute the run id of the rehearsal that passed:

```bash
# 1. WAIT FOR THE WHOLE RUN. The evidence artifact uploads BEFORE teardown, so a failed teardown
#    reds the run after you already hold a good file. Since #8010 the gate reads the run's status
#    and conclusion: a run still in flight is RUN_NOT_COMPLETED and a red one is RUN_NOT_SUCCESS,
#    and neither can be argued out of.
gh run watch <run-id>
gh run view <run-id> --json conclusion --jq .conclusion    # must print exactly: success

gh run download <run-id> -n git-data-rung2-boot-evidence
mv git-data-rung2-boot-evidence.env apps/web-platform/infra/

# 2. THE ACK GOES IN BEFORE `git add`, NOT AFTER. Only if the job summary's post-reset line read
#    `ACK REQUIRED` — it prints `ACK NOT REQUIRED — cross-check CLEAN` otherwise. Since #5274 that
#    line comes after the replace probe and covers both boots (`RUNG2_SENTRY_CROSSCHECK` and
#    `RUNG2_REPLACE_SENTRY_CROSSCHECK`); it names which boot needs the ack. Appending after
#    the commit yields Guard 4's "differs from its committed state" HOLD and forces an amend.
#
#    Grammar, all three parts checked: RUNG2_SENTRY_CROSSCHECK_ACK=<run-id>:<reason>. The run-id
#    must be the one in RUNG2_EVIDENCE_URL (else SENTRY_ACK_MISMATCH); the reason must be
#    non-empty after trimming; and the reason must NOT contain `#`, because the gate strips
#    trailing comments and would silently truncate it.
echo 'RUNG2_SENTRY_CROSSCHECK_ACK=<run-id>:<why the second channel may be skipped for this run>' \
  >> apps/web-platform/infra/git-data-rung2-boot-evidence.env

# 3. (#8043 Guard 4) COMMIT NEXT, ALONE — then validate. The gate's provenance arm reads the
# evidence's OWN commit and HOLDs on an untracked file or on a commit that also touches a
# hash-bound file, so the old "validate before committing" order is now refused by design.
git checkout -b evidence-git-data-rung2
git add apps/web-platform/infra/git-data-rung2-boot-evidence.env
git commit -m 'feat(git-data): commit the rung-2 boot evidence from run <N>'

# 4. VALIDATE. Since #8010 this call needs `jq` and `curl` on PATH and reaches api.github.com —
#    it resolves the run the evidence names. Without them it ABORTs on TOOLING_MISSING, which is
#    a statement about your shell, not about the evidence. Export GH_TOKEN if you have one: the
#    anonymous limit is 60 requests/hour per IP and this call spends two of them.
source tests/scripts/lib/git-data-birth-readiness-gate.sh
git_data_rung2_rehearsal_gate \
  apps/web-platform/infra/cloud-init-git-data.yml \
  apps/web-platform/infra/git-data-rung2-boot-evidence.env

gh pr create
```

`RELEASED` means the birth may proceed once that PR merges. `HOLD` names the refusal in exactly
one bracketed token — look that token up in the table below rather than re-dispatching, because
a HOLD on fresh evidence usually means the template moved or the instrument could not read, not
that the rehearsal was bad.

**Open the PR promptly.** The evidence carries a sha256 of `cloud-init-git-data.yml` and its
nine `file()`-bound payloads, so *any* merge touching those between the rehearsal and this PR
invalidates it. `infra-validation.yml` catches that on the PR, but the remedy is a full
re-rehearsal — another paid host and another approval.

## The gate's refusals — token → remedy

Every refusal this table covers carries exactly one bracketed token on its verdict line, and the
token is the lookup key; the prose beside it is not.

**Not every refusal is tokenised, and the untokenised ones are the common ones.** The checks that
predate #8010 — `STALE EVIDENCE`, the key-cardinality refusals, the render-var divergence arm and
the Guard 4 provenance arm — emit a prose verdict line with no bracket, and they are what an
ordinary payload PR trips. An earlier revision of this section claimed every refusal carries a
token; it does not, and reading a tokenless line as "no row exists for my failure" would send you
looking for a table entry that was never meant to exist. If the line has no bracket, the message
itself is the instruction. The **why** of each check lives in
the gate library's own header and in ADR-149's `Disposition — #8010` — this table is only what to
do next.

The two halves are not interchangeable. A **measured refusal** means the gate looked and the
answer was no; a **could-not-measure** token means there was no answer at all, and nothing in it
says the evidence is bad. Under CI the could-not-measure half also emits its own `::error::`
annotation, and the daily #8210 follow-through probe reports it as `CANNOT ESTABLISH` on the
tracker rather than as `NOT YET`.

**Measured refusals** — the gate read the run, and the run is not the one the evidence claims:

| Token | What it measured | What to do |
|---|---|---|
| `SENTRY_VERDICT_FATAL` | The committed `RUNG2_SENTRY_CROSSCHECK` records a fatal on the second channel. | Nothing acknowledges this one. Fix what the fatal names and re-rehearse. |
| `SENTRY_UNAVAILABLE_UNACKED` | The verdict is `UNAVAILABLE` and the file carries no acknowledgement. | Either append `RUNG2_SENTRY_CROSSCHECK_ACK=<run-id>:<reason>` (grammar in *After a PASS*, step 2) in the evidence's own commit, or re-rehearse with a `SENTRY_ISSUE_RO_TOKEN` whose scope works. |
| `SENTRY_ACK_MISMATCH` | An acknowledgement is present and its run-id is **not** the one in `RUNG2_EVIDENCE_URL` — an ack copied forward from a previous evidence file. | Re-key the ack to this file's own run id. An empty reason or a reason containing `#` emits `SENTRY_UNAVAILABLE_UNACKED` instead, not this token. |
| `RUN_NOT_FOUND` | The API answered, and this repository has no such run. | The URL names a run that does not exist — fix it, or re-rehearse. |
| `RUN_WRONG_WORKFLOW` | The run is not `git-data-rung2-rehearsal.yml`. | The URL points at some other workflow's run. Re-rehearse. |
| `RUN_WRONG_EVENT` | The run is not a `workflow_dispatch`. | Re-dispatch from the *Dispatch* section; a scheduled or push-triggered run cannot produce this evidence. |
| `RUN_NOT_MAIN` | The run's `head_branch` is not `main`. | Re-dispatch **with `--ref main`**. |
| `RUN_NOT_COMPLETED` | The run is still in flight. | Do **not** re-dispatch — `gh run watch <id>`, then re-run the gate. See *Three things that will mislead you*. |
| `RUN_NOT_SUCCESS` | The run completed with a conclusion other than `success`. | Usually a failed teardown after a good capture. The evidence is unusable either way: clear the host with `teardown_only=true`, then re-dispatch. |
| `RUN_HASH_MISMATCH` | The tree at the run's `head_sha` does not hash to the evidence's `RUNG2_TEMPLATE_SHA256`. | The evidence does not belong to the payload that run booted. Re-rehearse; do not hand-edit the hash. |
| `RUN_ID_REGRESSED` | The evidence names an OLDER run than the version of the file it replaces — the downgrade shape: revert the payload, then cite the genuine older run that really did boot it. Every other fact can be true. | Re-rehearse from `main` against the CURRENT payload. If the replay is deliberate, append `RUNG2_EVIDENCE_DOWNGRADE_ACK=<run-id>:<why older bytes are being reinstated>` in the evidence file's own commit. The reason **may not contain `#`** — the gate strips any trailing comment (a space followed by a hash) before reading, so such a reason would arrive truncated; it is refused by name rather than silently accepted. |
| `RUN_NO_EVIDENCE_ARTIFACT` | The run uploaded no `git-data-rung2-boot-evidence` artifact. | The signature of a `dry_run=true` dispatch. Re-dispatch with `dry_run=false`. |

**Could-not-measure** — the gate could not reach an answer. Fail-closed, and none of these is a
statement about the host:

| Token | What it could not do | What to do |
|---|---|---|
| `TOOLING_MISSING` (an ABORT) | Run at all — one of `jq`, `curl`, `tar`, `find` or `sha256sum` is absent. | Install it and re-run. Nothing was measured. `find` and `sha256sum` are on the list because they are USED (the archive symlink sweep and the tree hash); the check runs FIRST, before the live hash consumes `sha256sum`. |
| `RUN_OFFLINE` | Reach `api.github.com`. | Check the network/proxy and re-run. |
| `RUN_RATE_LIMITED` | Spend a request — the anonymous limit is 60/hour per IP, shared behind NAT on hosted runners. | Locally: `export GH_TOKEN=…` and re-run. In CI it needs `actions: read` plus a threaded token at the call site, which is tracked as this cycle's blocker issue and cited from the message itself. |
| `RUN_UNRESOLVABLE` | Tell "no such run" from "not visible to me" — an authenticated read was refused and the anonymous retry 404'd. | Re-run with a token that can read this repository's Actions. |
| `RUN_SHA_UNREACHABLE` | Find the run's `head_sha` in this checkout. | `git fetch origin main` — and on a shallow clone, `git fetch --unshallow`. |
| `RUN_HASH_UNCOMPUTABLE` | Extract and hash the tree at that sha. | Re-run in a clean checkout; if it repeats, the archive at that sha is the thing to look at, not the evidence. |
| `RUN_ARTIFACT_RECORD_UNREADABLE` | Read the run's artifact record — including the case where the run is old enough that GitHub no longer keeps one. | For a recent run, re-run (usually transport or rate limit). For an old run, re-rehearse: the record cannot be recovered. |
| `SENTRY_VERDICT_UNREADABLE` | Parse `RUNG2_SENTRY_CROSSCHECK` out of the evidence. | Its value is `NOT_RUN` (the cross-check never ran — no `jq`, no `SENTRY_ISSUE_RO_TOKEN`, or no reader on the rehearsal runner), or a value outside the set the capture can write. An **absent** key does not reach this token: the required-key loop refuses it first, with an untokenised cardinality message. |
| `RUN_FLOOR_UNREADABLE` | Read which run the PREVIOUS version of the evidence attested, so Guard 5 cannot tell a fresh rehearsal from a replay of an older one. | Re-run in a full checkout (`git fetch --unshallow`). Note the known gap recorded in ADR-149 `## Amendment — 2026-09-20 (#8010)`: on a shallow clone the floor comes back EMPTY and Guard 5 skips silently rather than reaching this token, so an absent HOLD here is not proof the floor was checked. |

## The PR #8564 payload: what the rehearsal must read

PR #8564 (PR1 of #8211, ADR-239) changes the cloud-init template and several `file()`-bound
payloads, so it voids every earlier rung-2 evidence file — including any rehearsed for PR #8511
alone.

**The #8511 re-rehearsal is held until PR #8564 merges** (the operator ruling on DC-2, posted on
#5914). Rehearsing #8511 first buys a rehearsal that PR #8564's merge immediately invalidates.
**One rehearsal on `main` after PR #8564 merges covers both payloads**, and serves both ADR-237
post-merge step 2 and PR #8564's own gate. The interlock window in *Changing the payload* is
correspondingly longer; that is the accepted price of not paying for two rehearsal hosts.

A PASS on that rehearsal requires all of the following, in addition to the usual artifact checks.

**Boot arm — `boot_complete` terminal booleans.** Every one of these must read `yes`:

```text
luks_mounted=yes fence_on_mapper=yes erasure_probe=yes plaintext_empty=yes
```

`fence_on_mapper` and `erasure_probe` are new in PR #8564. `fence_on_mapper` says the `pre-receive`
fence resolved onto `/dev/mapper/git-data` rather than onto the mountpoint underneath it;
`erasure_probe` says one real run of `git-data-remove.sh`, as the `git` uid on a synthetic id,
exited 0 with `not present (no-op)` on stderr. `plaintext_empty` says the retained plaintext volume's
post-journal-replay tree was counted at zero (since #5274 it is read through a dm snapshot over a
kernel-read-only origin, never mounted itself). `git-data-rung2-evidence-capture.sh` refuses to write
evidence if any terminal boolean reads `no`.

**Reboot arm — the re-attach target.** The reboot arm must read:

```text
luks_reopen_ok action=reopened target=/mnt/git-data
```

`action=reopened` alone is **not** enough, and was the pre-#8564 acceptance. The `target` field is
what proves the mapper came back at the serving path rather than at some other mountpoint, so any
other `target` is a FAIL. The capture's `HOST_SQL` reads the column, and
`tests/scripts/test-git-data-rung2-evidence-capture.sh` covers both arms.

**Informational to the birth poll, but gating HERE:** `plaintext_volume` and `plaintext_journal`
(#5274) — the capture PASSes only when every `boot_complete` row reads `plaintext_volume=present`
**and** `plaintext_journal=dirty`; see *The three-boot run*. **Informational everywhere:**
`served_repos=<n>`. A non-zero
`served_repos` is not informational — it ends the boot as `FATAL: luks_residue count=<n>`, so it
never reaches a `boot_complete` a capture would accept.

## The three-boot run (#5274)

The 2026-09-24 production replace FATALed because the predecessor was destroyed with the plaintext
volume mounted read-write, leaving a dirty ext4 journal the old rehearsal never produced. A real run
now reproduces it, on one address, in three boots:

1. **Seed** (`rehearsal_phase=seed`, plan-shape `additive`). `rung2-rehearsal/seed-dirty-journal.sh`
   mounts the plaintext volume read-write, writes a marker, creates a `repositories/` probe and
   `sync -f`s it into the home blocks, removes the probe and fsyncs only (the removal is committed
   to the journal, its home block not yet written), then powers off with `sysrq o` — never
   unmounting. A read that did not replay the journal would count the probe and FATAL
   `plaintext_residue count=1`, so boot #1's count of 0 proves the replay into the COW. It emits one
   Better Stack row per step as `stage=seed_<step>`, `host_name=<rehearsal-host>-seed`. The workflow
   polls the Hetzner API until the host is `off` (10 min); a timeout FAILs the run pointing at those
   rows, and the payload is never booted against an undirtied volume.
2. **Payload, boot #1** (`rehearsal_phase=payload`, plan-shape `host-only`). Terraform replaces the
   server (and both attachments) with the unmodified module render — the production event. Capture
   #1 must read `plaintext_volume=present plaintext_journal=dirty` on every `boot_complete` row
   (Guard 2). Then the existing settle / hard reset / unattended-reopen arm.
3. **Replace arm, boot #2** (`-replace=hcloud_server.rehearsal -replace=tls_private_key.rehearsal_host_ssh`,
   plan-shape `host-only`). Boot #2 **adopts** a LUKS volume boot #1 formatted and abandoned
   mounted — the state the production replace boots into — against the plaintext volume boot #1
   read. It must read `plaintext_journal=dirty` **again**, which proves no journal replay reached
   the volume (only a replay clears `needs_recovery`). It does not prove that nothing else was
   written: that proof is the loopback suite's before/after hash of the origin and the bootstrap's
   own before/after comparison of the device's written-sector counters. Its window is `RUNG2_REPLACE_SINCE`, stamped before its
   apply (the host name is reused across all three boots). A PASS appends `RUNG2_REPLACE_BOOT=PASS`
   to the evidence. Stated gap: the rehearsal root has no private network and no Doppler host-key
   secret, so those two production replace targets are not rehearsed.

**`host-only` admits** only a replace of `hcloud_server.rehearsal`, `hcloud_volume_attachment.rehearsal`,
`hcloud_volume_attachment.rehearsal_luks` (all three required) and `tls_private_key.rehearsal_host_ssh`,
and an update of `hcloud_firewall_attachment.rehearsal`. Any change to either volume is refused: a
fresh plaintext volume makes the seed vacuous; a fresh LUKS volume skips the adopt arm. Both modes
also refuse an import and any create outside the root's own `*.rehearsal`/`*.rehearsal_*` addresses
(module-scoped addresses included).

**Releasing evidence exists only if all three boots pass.** The evidence upload's `if:` requires the
capture, reboot and replace rcs to be `0`; the gate refuses a run that did not succeed
(`RUN_NOT_SUCCESS`) or left no evidence artifact (`RUN_NO_EVIDENCE_ARTIFACT`), and since #5274 it
also requires `RUNG2_REPLACE_BOOT=PASS` and a classified `RUNG2_REPLACE_SENTRY_CROSSCHECK`. Guard 2
reads every `boot_complete` row in the window through its own query (capped at 1000 rows, failing
closed at the cap), not the newest 50 host rows.

**Budget and teardown.** Every rehearse step carries its own `timeout-minutes`, and the job ceiling
is their sum plus a stated 10-minute margin (`git-data-rung2-rehearsal.test.sh` asserts both; the
workflow comment carries the current numbers). Teardown is a separate job (`needs: rehearse`,
`if: always()`, `environment: infra-privileged` — no reviewers and main-only, so it never waits for
a second approval and keeps its credentials after the legacy fallback is removed), so a rehearse
job that hits its ceiling still destroys its paid hosts. `teardown_only=true` stays the
manual fallback.

**When a run does not PASS** (cap: **two paid runs per payload hash**; a named FATAL always needs a
code PR, never a re-run):

| Outcome | Next |
|---|---|
| seed off-poll timeout | read the `stage=seed_*` rows for `<host>-seed`; fix the seed in a PR |
| payload FATAL `reason=snapshot` / `mount` / `journal` / `source` | code PR; if it is the kernel mechanism itself, stop and return to ADR-239's alternatives with the CTO and CLO |
| capture #1 PASS, replace arm FAIL | read boot #2's fatal row; the LUKS adopt arm is the suspect; code PR |
| replace arm WRAPPER FAILURE (rc 3: no capture verdict twice, Doppler self-probe run) | a credential or harness fault, not the host; fix the credential, one re-dispatch, counted against the cap |
| replace arm TRANSIENT | one re-dispatch, counted against the cap |
| seed off-poll fails at once on an empty `HCLOUD_TOKEN` | the credential loader, not the seed; fix the credential tier |
| teardown did not complete | dispatch with `teardown_only=true` (operator-gated like every dispatch) |
| TRANSIENT (source-liveness anchor silent) | one re-dispatch, counted against the cap |

Every future rehearsal pays for the seed and replace boots; re-evaluate when #8571's wipe empties the
plaintext volume id (that PR amends the `present`+`dirty` PASS rule in its own rehearsal).

## Changing the payload: the two-PR sequence

The evidence is hash-bound to the payload and Guard 4 refuses a commit that touches both, and
since #8010 the run behind it must also have been dispatched **from `main`**. Those two together
fix the shape of any payload change, and it is two PRs, not one:

1. **The payload PR** edits `cloud-init-git-data.yml` (or any of its `file()`-bound payloads) and
   **deletes** `apps/web-platform/infra/git-data-rung2-boot-evidence.env` in the same PR. Deleting
   it is the honest move: a voided attestation that stays on disk looks freshly re-rehearsed to
   every reader, and the gate HOLDs on an absent file exactly as it HOLDs on a stale one.
2. **Merge it.** The rehearsal dispatches from `main` only, so the new payload cannot be rehearsed
   before it is on `main`.
3. **Dispatch on `main`** (`--ref main`, `dry_run=false`) against the merged payload.
4. **The evidence-only PR** lands the resulting file alone, per *After a PASS*.

**The route is interlocked in between, and that is the intended state — not a defect.** From the
moment step 1 merges until step 4 merges, `main` carries no valid rung-2 evidence, so
`git_data_rung2_rehearsal_gate` HOLDs and both the birth and replace jobs refuse. Plan the window;
do not try to shorten it by landing the payload and its evidence together, which Guard 4 refuses,
or by re-dating an old evidence file, which `RUN_HASH_MISMATCH` refuses.

## If teardown fails

Re-dispatch with `teardown_only=true`. A surviving host is a paying box with a LUKS volume
attached; the scheduled drift workflow sweeps for the `soleur-git-data-rehearsal-` prefix
daily and files an issue, but the recovery is this arm, not a console click (a Terraform
destroy also reclaims the volumes and the scratch Doppler config).

## Three things that will mislead you

- **The evidence self-invalidates.** Its hash covers the cloud-init *and* all nine
  `file()`-bound payloads. Any later edit to what ships re-holds the birth, by design. The
  rung-2 PR check reports that on the PR that caused it rather than at dispatch time.
- **`RUN_NOT_COMPLETED` is not a failure, and re-dispatching is the wrong reflex.** The gate
  reads the run live, so validating while the run is still going gets you a HOLD that says
  nothing about the rehearsal. It resolves itself: `gh run watch <id>`, then re-run the gate.
  Spending a second paid host on it produces a second run that is also in flight.
- **A clean rehearsal emits no `fatal`.** Do not go looking for one. The fatal channel is
  proven at rung 1 by `git-data-runcmd-rehearsal.test.sh`; rung 2 proves the real-host facts
  rung 1 cannot reach — TLS egress from a real host, a real `doppler run`, a real
  `cryptsetup luksOpen`.
