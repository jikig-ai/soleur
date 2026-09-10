# Runbook — birthing the git-data host

> ## ⛔ DO NOT DISPATCH THIS YET
>
> **Do not assume this banner is backed by a mechanical hold — as of PR #8002 it may not
> be.** Both gates release once
> `apps/web-platform/infra/git-data-rung2-boot-evidence.env` is on `main`. From that moment
> this banner is the ONLY prose hold, and the sole remaining control is the
> `web-platform-infra-apply` environment approval — measured `prevent_self_review: false`
> with a single reviewer, so **the dispatcher can approve their own deployment.** That is one
> human clicking twice, not a two-party control. Do not dispatch.
>
> #6982 shipped the off-host emitter, so `git_data_birth_readiness_gate` no longer refuses —
> the sentinel it looks for (`${sentry_dsn}` in non-comment template text) is present. That
> released the FIRST gate, and for a while this banner really was the only hold, which is the
> posture ADR-149's own Alternatives table rejects.
>
> So #6982 also added a SECOND gate: `git_data_rung2_rehearsal_gate` runs in the same
> dispatch job, before any provider is contacted, and refuses unless
> `apps/web-platform/infra/git-data-rung2-boot-evidence.env` exists and attests a rung-2 boot
> rehearsal **of the current template** (the evidence carries a sha256 of
> `cloud-init-git-data.yml`, so it self-invalidates the moment that file is edited again).
> **That was true until PR #8002.** Once its evidence file lands on `main` this gate
> RELEASES and a dispatch no longer exits early. Check the live state rather than trusting
> this paragraph:
>
> ```bash
> git cat-file -e origin/main:apps/web-platform/infra/git-data-rung2-boot-evidence.env \
>   && echo 'evidence IS on main — the rung-2 gate is RELEASED' \
>   || echo 'evidence absent — the rung-2 gate still HOLDs'
> ```
>
> Note what that gate does and does not check: it asserts that a well-formed, template-bound
> assertion EXISTS. It strips comments before reading, never resolves the Actions run id, and
> ignores `RUNG2_SENTRY_CROSSCHECK` entirely (#8010). The hash is a staleness detector, not an
> authorship proof.
>
> ### What changed in #7025: the route to produce that evidence now EXISTS
>
> Until #7025 there was no automation that could produce
> `git-data-rung2-boot-evidence.env` at all — `rung2` appeared only in the apply workflow
> and the gate itself. Nothing booted a throwaway host; nothing captured the artifacts. The
> gate was waiting on something no one could do without a hand-run laptop procedure.
>
> #7025 shipped the **route, not the run**:
>
> - `.github/workflows/git-data-rung2-rehearsal.yml` — `workflow_dispatch` only, confirm
>   token `REHEARSE-GIT-DATA`, `dry_run` defaulting to **true**.
> - `apps/web-platform/infra/rung2-rehearsal/` — a **separate Terraform root** with its own
>   R2 state key, so a rehearsal apply cannot address a production resource through
>   Terraform's managed-resource lifecycle. That boundary is narrower than it sounds and
>   ADR-149 DC-6 spells out what it does NOT cover: the Hetzner credential, the Doppler
>   project, Sentry, the parent root's push trigger, and teardown garbage collection are all
>   shared. State separation bounds the LIFECYCLE, not the AUTHORITY.
> - `scripts/followthroughs/git-data-rung2-evidence-capture.sh` — captures the evidence
>   off-box and writes the file **only** on PASS.
>
> It shipped **unfired**, and the banner stayed up, for a reason worth internalising: a PR
> merges **atomically**, so evidence committed in the same PR that builds the harness would
> be evidence from a rehearsal that never ran. The harness has to exist, merge, and then
> *run*. Producing evidence is now one gated dispatch, not a procedure.
>
> **RELEASE CONDITION — clear this banner only when the rehearsal evidence exists.**
> Every gate #6982 ships is STATIC, and the failure class it defends against
> (*green apply, dark host*) is only observable at RUNTIME. Mutation arms prove the code
> CAN go red when neutered; they never prove an event ARRIVES when it is intact. So the
> condition is not "the code merged" — it is:
>
> 1. the rendered template booted **once on a throwaway host** outside the
>    `hcloud_server.git_data` address (dispatch the rehearsal workflow with
>    `dry_run=false`), and
> 2. the artifacts were **observed off-box**, each recorded with the query that retrieved
>    it: a Better Stack **source-liveness anchor**, one `stage:boot_complete` row carrying
>    its four assertion booleans, and **no `level:fatal`** from that host.
>
> **A CORRECTION TO AN EARLIER VERSION OF THIS LIST**, because it asked for something
> unsatisfiable. It previously demanded *"a Sentry event from the fatal channel"* from a
> successful rehearsal. The fatal channel fires **only on failure** — a clean boot emits
> `info`, never `fatal` — so that clause could be met only by a rehearsal that failed, or
> by fabricating it. The fatal channel is proven at **rung 1** instead, by
> `git-data-runcmd-rehearsal.test.sh`, which shows the trap firing and emitting `fatal`.
> Rung 2's job is the real-host facts rung 1 structurally cannot reach: TLS egress from a
> real Hetzner host, a real `doppler run`, and a real `cryptsetup luksOpen`.
>
> Related measurement, since it shaped the capture script: `stage:bootcmd_start` reaches
> **Sentry only**. It is a bare `curl` inside `bootcmd`, which runs before `write_files`,
> so `/usr/local/bin/git-data-emit` does not exist yet. That much still holds.
>
> **Superseded in part by #7460 (ADR-198).** The rest of this paragraph used to read: "the
> emitter's Better Stack block is gated on `BETTERSTACK_LOGS_TOKEN`, which is present only
> under `doppler run`. On a *successful* boot the only Better Stack row a git-data host ever
> produces is `boot_complete` itself." The token is now baked at `0600` in `user_data`, so
> EIGHT of the nine stages reach Better Stack and only `bootcmd_start` is Sentry-only.
> Anchoring a Better Stack query on an early stage is now correct, not a mistake — but
> `bootcmd_start` specifically still returns zero rows.
>
> If only the container-harness rung was reached, that is **not** sufficient: the harness
> cannot exercise `doppler run` against real Doppler, `luksOpen` against a real volume, the
> private NIC, or whether an event actually lands. The banner-clear PR carries the
> throwaway-host rung as **its own** precondition.
>
> **Why the hold outlived the gate:** the interlock is a ONE-BIT LATCH guarding a
> nine-item checklist, and the bit flips on *threading*, not on *emitting*. It cannot
> verify the emitter emits. ADR-115 additionally makes several #6982 items unfixable after
> the birth — git-data is excluded from the reboot primitive, and `user_data` is ForceNew
> with no `ignore_changes`, so **every** cloud-init edit after birth costs a destructive
> `git-data-host-replace` of the host holding every user's source code.
>
> The full release checklist is **ADR-149**, and its per-item disposition table records
> what #6982 discharged. Clear this banner only when every item is done — including the
> rehearsal — not merely when the gate stops refusing.

---

## What this births

`soleur-git-data` — the shared bare-repo store that will hold every connected user's
source code and workspace history. It is **declared in IaC and has never existed**: an
authenticated `terraform state list` returns 201 addresses and zero git-data members.

Before this route existed there was no way to create it. `git-data-host-replace` cannot:
its gate requires `actions ⊇ {delete, create}`, so a first CREATE fails the
`server_replaced` arm; its `luks_passphrase_touched` arm fires on a create too; and its
five-member allow-set cannot hold a twenty-address birth fan-out. The only remaining
route was an untargeted <!-- lint-infra-ignore start -->`terraform apply` from an operator laptop<!-- lint-infra-ignore end --> — no destroy-guard, no
stock preflight, and a plan of that shape taken 2026-07-27 carried **nine destroys**.
(That route is what this runbook exists to replace — it is described, never prescribed.)

## Before you dispatch

| Check | How |
|---|---|
| #6982 has shipped and ADR-149's release checklist is complete | The banner above is cleared |
| You are on `main` | The environment pins `main`; a branch dispatch is refused |
| `prd_git_data` has **not** been hand-created in Doppler | `doppler configs -p soleur` — it must be ABSENT (Terraform creates it) |
| **SIZING is confirmed** (#6982 / ADR-149 item 9) | `var.git_data_server_type` is `cpx22`, and ADR-068's D-SIZE addendum records WHY. Step 7's stock preflight checks **orderability**, never **adequacy** — it will happily birth an under-sized host. `user_data` is ForceNew and a type change routes through the DESTRUCTIVE `git-data-host-replace`, so the shape must be right at birth. |
| **EMITTER verified** — it has actually emitted, not merely shipped | The rehearsal evidence named in the banner. `grep -c '$${sentry_dsn}'` proves nothing: the readiness gate checks THREADING, and a non-comment line that merely references the variable releases it. The question is whether an event ARRIVED. |
| The Better Stack query credentials are present | The birth job's post-apply poll needs `BETTERSTACK_QUERY_{HOST,USERNAME,PASSWORD}`. If that step warns they are absent, the boot signal is **unread** and you are back to "a green apply proves nothing". |

That last row matters more than it looks. See *"Doppler config already exists"* below.

### Three things a green boot does NOT mean

The same three statements are written to the **run summary page** by an un-gated job that
runs before the approval prompt, so you do not have to have read this file to see them
(#8009, CPO condition C2). They are repeated here because the runbook is where you are
standing when you decide to dispatch at all.

`confirm=BIRTH-GIT-DATA` is a **typo guard, not an authorization**. The authorization is the
environment approval.

**1 — Repositories are NOT encrypted at rest before the cutover.** `luks_mounted` is about
the **device**, not the repositories. `git-data-bootstrap.sh` pins that wording itself, under
AC30:

> `luks_mounted` is about the DEVICE. It says NOTHING about the repositories being encrypted
> at rest — they are NOT, REPO_ROOT is the PLAINTEXT volume until the cutover.

A green boot is fully compatible with every repository sitting on plaintext storage.

**2 — The approval is NOT two-party.** `web-platform-infra-apply` reports
`prevent_self_review: false` with a single reviewer, so **the person who dispatches can
approve it**. Two things to know about that reading: it comes from the live API, and
`prevent_self_review` is declared **nowhere in this repository's Terraform** — so `false` is
the provider default rather than a setting anyone chose. Every environment here that has
required reviewers reads the same way, with the same single reviewer: **no approval gate in
this repo is two-party.** Re-measure rather than trusting this line:

```bash
gh api repos/jikig-ai/soleur/environments/web-platform-infra-apply \
  --jq '.protection_rules[] | select(.type=="required_reviewers")
        | {prevent_self_review, reviewers: [.reviewers[].reviewer.login]}'
```

One human clicking twice is the real control. Treat it as **one** control, not two.

**3 — The rehearsal evidence attests that a STAGE WAS REACHED, not that four invariants were
measured.** `luks_mounted`, `repo_root`, `hooks_path` and `provision` are **hardcoded
literals** at the emit call in `git-data-bootstrap.sh` — they read `yes` by construction.
That is not nothing: each has a named upstream `FATAL: …; exit 1` gate (20 in that script),
so a failure aborts *before* the emit rather than emitting `no`. Read them as "no gate
fired", never as "four invariants were measured".

Exactly **one** boolean in that row is measured: `nft_metadata_drop`, computed just above the
emit by grepping the live nftables chain (`nft list chain inet soleur_git_data output` for
`169.254.169.254`), anchored on the metadata address rather than the table name so a table
whose rule was flushed reads `no`. It read `yes`. It is **not** in
`git-data-rung2-boot-evidence.env` — that file records the queries, and the capture projects
only the four hardcoded booleans — so it was read directly from Better Stack and recorded in
the evidence PR's body.

Finally: the authorization-map interlock is a **static** assertion over Terraform source. It
proves what the production root *renders*, not what a live host *honours*. No live host is
probed, because none exists until this dispatch creates one.

### An undocumented invariant that Article 17 correctness currently rests on

**`/mnt/git-data` must stay root-owned.** This is not a preference; it is the only thing
making erasure fail closed today, and nothing asserts it.

`git-data-remove.sh` derives `REPO_ROOT=/mnt/git-data/repositories`, then guards with
`readlink -f`. **`readlink -f` succeeds on a path that does not exist** (verified: rc=0, and it
prints the path), so on a host where the volume failed to mount, both guards pass. The script
then runs `mkdir -p "$REPO_ROOT"`, finds no repo, prints `not present (no-op)` and **exits 0** —
reporting Article 17 erasure success over a store nobody looked at.

What actually prevents that today: the forced command runs as `git`, cloud-init creates
`/mnt/git-data` as root, and `git-data-bootstrap.sh` chowns only the *symlink*
(`chown -h …/repositories`). So the `mkdir -p` takes EACCES and `set -euo pipefail`
(`git-data-remove.sh` line 28) aborts before the false success.

That is an **accidental** invariant holding up a statutory guarantee. The moment anyone chowns
that mountpoint to `git` for an unrelated permissions fix, erasure begins silently succeeding
over nothing, and the failure is invisible — a no-op and a real erasure produce the same exit
code and the same message. The assertion that would make it deliberate is a `mountpoint -q`
check, which cannot land here: `git-data-remove.sh` is one of the payloads bound by
`RUNG2_TEMPLATE_SHA256`, so editing it voids the rung-2 evidence and buys a fresh paid
rehearsal. It is tracked with the other hash-bound hardening items.

## Dispatch

```bash
gh workflow run apply-web-platform-infra.yml \
  -f apply_target=git-data-host-create \
  -f confirm=BIRTH-GIT-DATA \
  -f reason='<why, in one line>'
```

`confirm` is a **typo-guard, not the authorization**. The authorization is the
`web-platform-infra-apply` environment's required reviewer.

**The approver approves blind.** GitHub holds the job in "Waiting" *before its first step
runs*, so there is no plan for the reviewer to inspect — they are authorizing the
dispatch, not its contents. Everything that actually protects the store runs after
approval: the interlock, the birth gate, and the stock preflight.

## What the job does, in order

0. **The disclosure job** — un-gated, runs first, and writes the three limits above to the
   run summary so they are on screen before the approval prompt, not after it.
1. **Validates `confirm`** — before anything reads a secret or contacts a provider.
2. **Birth-readiness interlock** — refuses while the host would boot dark.
3. **Rung-2 rehearsal interlock** — refuses unless committed boot evidence exists for the
   CURRENT template, hash-bound so it re-holds on any later edit to `cloud-init-git-data.yml`.
   (This step was missing from this list; it has run since #6982.)
4. **Authorization-map interlock** — refuses unless the three SSH forced-command slots
   resolve to three distinct keys AND each authority's private half is published under the
   matching Doppler name. Static, so it needs no rehearsal. The rung-2 rehearsal is
   structurally incapable of catching this class: `rung2-rehearsal/rehearsal.tf` sets all
   three pubkeys to one `tls_private_key` by design, so a production collapse is a **no-op**
   there and the evidence still records PASS.
5. Mints a throwaway SSH key (HCL evaluates `file()` at plan time; the git-data host is
   cloud-init-only and never receives it).
6. Asserts `SENTRY_DSN` is present and non-empty — *unreadable* and *empty* get different
   messages, because they have different remedies.
7. **`terraform plan`** scoped to twenty `-target`s — re-derive rather than trusting the
   number here:

   ```
   awk '/^  git_data_host_create:/{f=1}
        f && /^[[:space:]]*-target=/{n++}
        f && /^  [a-z_]+:$/ && !/git_data_host_create/{exit}
        END{print n}' .github/workflows/apply-web-platform-infra.yml    # => 20
   ```

8. **Birth gate** — refuses unless the plan is exactly the scoped birth. Its message names
   which arm refused.
9. **Stock preflight** — refuses if the server type is not orderable in its location. Runs
   *after* the birth gate: the gate proves the plan is the right plan, the preflight proves
   it is a feasible one.
10. **`terraform apply`**.

## What a green run gives you — and what it does not

**It gives you:** an **empty** bare-repo store on a host that has never existed before.

**It does not give you:**

- **A serving store.** `GIT_DATA_STORE_ENABLED` is still absent from Doppler `prd`. The
  feature stays dark.
- **Encryption of the live store.** Every wrapper still mounts the **plaintext**
  `/mnt/git-data`. The LUKS volume is created and mounted but is not yet the live store —
  that is the #5274 Phase-3 cutover. See `git-data-luks-cutover-5274.md`.
- **Monitoring.** `betteruptime_heartbeat.git_data_prd` is deliberately **out** of this
  job's `-target` set and ships paused. Its feeder already exists and is web-host-resident,
  so arming a monitor from this route would produce a green dashboard measuring nothing.
- **Working transport keys in the running web container.** See below — this one has an
  action attached.

### Required follow-up: redeploy the web container

The birth mints the three SSH keypairs and writes their private halves to Doppler `prd`.
The **running** web container cannot see them: `ci-deploy.sh` resolves its env with
`doppler secrets download --format docker` and passes `--env-file` to `docker run`, so the
environment is baked **at container start**. Until the next redeploy the host's
`authorized_keys` holds public halves whose private halves the app does not have.

The remedy is the platform's ordinary container swap — **a `ci-deploy` redeploy**, which
the release pipeline already performs on any merge touching `apps/web-platform/**`. Either
merge anything to `main` or trigger a release; no special command exists and none is
needed.

> There is **no systemd unit** for the web app on these hosts. It is started by a bare
> `docker run` from `cloud-init.yml`. If you find a document telling you to restart a unit
> to pick up these keys, that document is wrong — `git-data-cutover.sh` currently contains
> exactly that mistake at two sites (tracked under #5274/#6982).

## If it fails

**A re-dispatch is normally the correct remedy.** The operation is additive, so nothing
existing is destroyed, and the birth gate's requirement arm accepts a `no-op` on every
member the server's own creation does not entail — so a partial apply does **not** wedge
the retry. That property is deliberate and is regression-tested.

Two exceptions:

### The server landed but a later address did not

The retry plans **zero** server creates and the gate correctly refuses.

**Do not try to complete the host by hand.** `cloud-init` `runcmd` is once-per-instance and
has already finished, so attaching a NIC or a volume afterwards leaves the app
unconfigured — and ADR-115 excludes git-data from the reboot primitive, so there is no
reboot that repairs it. **That host must be replaced, not completed.** Use
`git-data-host-replace` once the host exists.

### Doppler config already exists

If the failure names `doppler_config.git_data_prd` already existing, the config was created
outside Terraform. **A re-dispatch cannot succeed** — measured 2026-07-27, the Doppler API
returns `400 {"messages":["Name is already in use"]}` rather than adopting it. Import it
first:

```bash
terraform import doppler_config.git_data_prd soleur.prd_git_data
```

then re-dispatch. This is the one failure mode the otherwise-additive re-dispatch story
does not cover, which is why it is called out separately.

## Verifying the result

**Without SSH.** The host runs a deny-all firewall and there is no SSH fallback in this
runbook by design (`hr-no-ssh-fallback-in-runbooks`).

- **The job itself** — `gh run list --workflow=apply-web-platform-infra.yml --limit 5
  --json conclusion,displayTitle`. The job conclusion plus its step summary are the
  terminal signal.
- **The step summary** restates what you have and what you do not.
- **Hetzner** — the server, both volumes and both attachments are visible in the console.

- **The web host's reachability probe** — a real, no-SSH, post-apply signal that already
  exists:

  ```bash
  doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 30m --grep git-data-probe
  ```

  `web-git-data-probe.service` runs on the web host and ships to Better Stack via Vector
  journald. **Before the birth** every line reads
  `[git-data-probe] SUPPRESS ping: 10.0.1.20:22 UNREACHABLE over the private net`. **After a
  successful birth** those stop and `cannot ping` lines begin (the heartbeat URL is
  deliberately unwired — see above). Continued `SUPPRESS` lines five minutes post-apply mean
  the host is dark or the NIC never attached.

**Be honest about what you cannot verify yet.** <!-- lint-infra-ignore start -->The probe above observes *reachability*, not
*boot correctness*: it tells you something answers on `10.0.1.20:22`, not that the bootstrap
ran or that the LUKS volume mounted.<!-- lint-infra-ignore end --> A green apply means Terraform created the
resources; on its own it does not mean the host booted correctly.

**That gap is why the interlock existed, and #6982 closed it.** The host now emits off-host
itself via `/usr/local/bin/git-data-emit` — Sentry always (from the baked DSN), plus Better
Stack once the Doppler stage has run — and reports `stage:boot_complete` with its four
booleans, which the birth job polls. So do not stop at the reachability probe: go to
**After the birth — verify the host actually booted** below and read the host's own
channels. It still has no heartbeat of its own (deliberate — see ADR-149's D-HB finding).

## References

<!-- lint-infra-ignore start -->
- ADR-149 — this route, the interlock, and its release checklist
- ADR-145 — the web-host birth precedent this mirrors
- ADR-115 — why git-data is excluded from the reboot primitive
- ADR-103 — why every git-data address is an operator-applied exclusion
<!-- lint-infra-ignore end -->
- ADR-068 — the multi-host workspaces architecture this serves
- `web-host-birth.md` — the sibling runbook
- `git-data-luks-cutover-5274.md` — the cutover that makes the LUKS volume live
- #6977 (this route) · #6982 (the interlock's release) · #5274 (Phase-3 GA)

## After the birth — verify the host actually booted (#6982)

**A green apply is not a green boot.** The dispatch's own post-apply step polls for the
boot signal and FAILS the job if it does not arrive, so a green run is now meaningful — but
verify independently if that step warned that its credentials were missing.

No SSH appears below, and none is possible: git-data has no human SSH path by design
(`git-shell` + three `command=`/`no-pty` forced commands, deny-all public ingress).

```bash
# 1. The boot-completion signal, with its FIVE assertions (#7772 added nft_metadata_drop).
#    BS_TABLE IS PINNED: git-data ships to its own source 2734275, not the shared 2457081
#    that betterstack-query.sh defaults to. Unpinned, this returns zero rows on a healthy
#    host and the reading instruction below sends you down the partial-birth tree for a
#    perfectly good birth. Field-isolated raw SQL — a
#    bare-substring grep matches the shared source's inngest rows quoting issue bodies.
#    NOTE `remote($BS_TABLE)` takes NO `primary` argument; only s3Cluster does. The
#    archive arm is REQUIRED: remote() alone is the ~40-minute hot window.
BS_TABLE=t520508_soleur_git_data_prd_logs \
  doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh "
  SELECT dt, JSONExtractString(raw,'stage') AS stage,
             JSONExtractString(raw,'luks_mounted') AS luks_mounted,
             JSONExtractString(raw,'repo_root')    AS repo_root,
             JSONExtractString(raw,'hooks_path')   AS hooks_path,
             JSONExtractString(raw,'provision')    AS provision,
             JSONExtractString(raw,'nft_metadata_drop') AS nft_metadata_drop
  FROM (SELECT dt, raw FROM remote(\$BS_TABLE)
        UNION ALL SELECT dt, raw FROM s3Cluster(primary, \$BS_TABLE_S3) WHERE _row_type = 1)
  WHERE JSONExtractString(raw,'host_name') = 'soleur-git-data'
    AND JSONExtractString(raw,'stage') = 'boot_complete'
  ORDER BY dt DESC LIMIT 5 FORMAT JSONEachRow"

# 2. Any boot FATAL. Sentry is the durable channel and the only one that pages.
#    scripts/sentry-issue.sh takes an ISSUE ID, not a query (usage:
#    [--latest-event] [--redact] <issue-id>) — so search the issues API directly, then
#    feed an id it returns into that script for the full event.
doppler run -p soleur -c prd -- sh -c '
  q=$(printf "%s" "host_name:soleur-git-data" | jq -sRr @uri)
  curl -sS -H "Authorization: Bearer $SENTRY_ISSUE_RO_TOKEN" -H "Accept: application/json" \
    "https://sentry.io/api/0/organizations/jikigai-eu/issues/?query=$q&statsPeriod=24h" \
  | jq -r ".[] | \"\(.shortId)  \(.count)x  \(.title)\""'

#    Then, for any id above:
#    doppler run -p soleur -c prd -- bash scripts/sentry-issue.sh --latest-event <issue-id>

# 3. The standing probe (runs daily until it passes).
doppler run -p soleur -c prd_terraform -- \
  bash scripts/followthroughs/git-data-birth-emitter-6982.sh   # 0 PASS / 1 FAIL / 2 TRANSIENT
#    WITHOUT the wrapper it exits 2 for a MISSING CREDENTIAL, indistinguishable from
#    exit 2 for "host still unborn" -- the state you are actually testing for.
```

**Reading the result.** ANY `"no"` among the four assertions is a FAILED birth even if the
apply was green: it means the bootstrap reached its final stage with an invariant unmet.
Zero rows means the host never got that far — check (2) for the stage that died.

**What the boot signal does NOT say.** It reports `luks_mounted` — the LUKS *device* is open
and mounted — and asserts **nothing** about the repositories being encrypted at rest,
because they are not: `REPO_ROOT` is on the PLAINTEXT volume until the
`GIT_DATA_STORE_ENABLED` cutover. Do not read it as an encryption-at-rest attestation; the
Art. 30 register carries that distinction explicitly.

## ForceNew hazard — read before editing either file (#6982)

`hcloud_server.git_data` deliberately carries **no** `lifecycle.ignore_changes = [user_data]`,
and `user_data` is **ForceNew**. Both of these are inputs to it:

- `apps/web-platform/infra/cloud-init-git-data.yml`
- `apps/web-platform/infra/git-data-bootstrap.sh` (and the four other scripts, now injected
  as plain text rather than base64 — #6982)

**Every byte counts, comments included.** Post-birth, a one-word comment fix in either file
costs a full `git-data-host-replace`: a destroy-then-create of the host holding every
connected user's source code, with both volumes and the passphrase preserved *by omission*.
Pre-birth the same edit costs nothing. The omission is deliberate — it preserves the clean
replace-to-reprovision path — so this is a residual to respect, not a bug to fix.

There is also a hard **32,768-byte** cap on the rendered `user_data`, gated in CI by
`apps/web-platform/infra/git-data-userdata-budget.sh`. Measure with Terraform's own
`base64gzip`, never `gzip -9` — the latter overstates headroom.

**Deferred:** the `prjquota` MOUNT option is deliberately NOT set (#6982 / R31). The
`mkfs -O quota,project` FLAG ships because it is migration-forcing; the mount option is
reversible, does nothing until projects are assigned, and would add a new way for the mount
to fail at boot on a host with no console.
