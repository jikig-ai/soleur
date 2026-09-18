# Runbook — birthing the git-data host

> ## Release record — the DO-NOT-DISPATCH banner was cleared 2026-09-13 (PR #8128, merged 2026-09-14)
>
> This runbook opened with a `⛔ DO NOT DISPATCH THIS YET` banner from its first commit until
> the PR that made this edit. It was cleared on the release condition it stated, and nothing
> else: the rendered template booted **once on a throwaway host** outside the
> `hcloud_server.git_data` address, and the artifacts were observed **off-box**.
>
> - **Rehearsal:** `git-data-rung2-rehearsal.yml` run
>   [34768256297](https://github.com/jikig-ai/soleur/actions/runs/34768256297), dispatched
>   from `main` `15fd63aff` with `dry_run=false`. Verdict `PASS` — `stage:boot_complete`
>   reached carrying `luks_mounted=yes repo_root=yes hooks_path=yes provision=yes`, no
>   `level:fatal` on Better Stack, the Better Stack source-liveness anchor answered (the Sentry
>   one did not — next bullet); teardown verified against
>   the Hetzner API. Read the booleans as the capture script does: they are literals
>   `git-data-bootstrap.sh` emits after its own `mountpoint`/`test` checks pass, so the PASS
>   attests that the final stage was REACHED and nothing reported a fatal — not four
>   independently measured invariants. Each artifact is recorded in the evidence file with
>   the query that retrieved it. `RUNG2_SENTRY_CROSSCHECK=UNAVAILABLE` (a run-pinned
>   liveness window on a quiet project — recorded on #8010, which is where that key becomes
>   load-bearing; the gate ignores it today).
> - **Evidence:** `apps/web-platform/infra/git-data-rung2-boot-evidence.env`, committed ALONE
>   in PR #8126 — merged to `main` BEFORE this record landed, because ADR-149's #8043
>   disposition orders "evidence PR, then the banner PR, then the birth" (Guard 4 of `git_data_rung2_rehearsal_gate` reads the evidence's own commit and
>   HOLDs on a co-edit with any of the 13 hash-bound inputs). Template sha256
>   `5c50797be8392fe551a940ae04555c52a3f4409cf249ed11bb1280fec783d5b1`.
> - **Gate:** `git_data_rung2_rehearsal_gate` reads `RELEASED`, provenance `PASS`. It
>   self-invalidates the moment any bound input moves — re-check it rather than trusting
>   this paragraph:
>
> ```bash
> source tests/scripts/lib/git-data-birth-readiness-gate.sh
> git_data_rung2_rehearsal_gate \
>   apps/web-platform/infra/cloud-init-git-data.yml \
>   apps/web-platform/infra/git-data-rung2-boot-evidence.env
> ```
>
> **What clearing the banner does NOT change.** The sole remaining control on the dispatch is
> the `web-platform-infra-apply` environment approval — measured `prevent_self_review: false`
> with a single reviewer AND `can_admins_bypass: true`, so the dispatcher can approve their
> own deployment, and an org admin can skip the approval outright (see *"Three things a green
> boot does NOT mean"* below). ADR-149 item 8 is
> the banner clear itself; the item's history (deferred out of #6982 into #7025, then held open
> again when #8052 voided the first evidence) is why this edit touches the runbook, the ADR-149
> disposition row that records the clear, and nothing else.
>
> The banner's text is preserved in git history:
> `git log -p --follow -- knowledge-base/engineering/operations/runbooks/git-data-birth.md`.

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
| #6982 has shipped and ADR-149's release checklist is complete | ADR-149's disposition table records item 8 DONE, and the release record at the top of this runbook names the rehearsal run and the evidence PR |
| You are on `main` | The environment pins `main`; a branch dispatch is refused |
| `prd_git_data` has **not** been hand-created in Doppler | `doppler configs -p soleur` — it must be ABSENT (Terraform creates it) |
| **SIZING is confirmed** (#6982 / ADR-149 item 9) | `var.git_data_server_type` is `cpx22`, and ADR-068's D-SIZE addendum records WHY. Step 9's stock preflight checks **orderability**, never **adequacy** — it will happily birth an under-sized host. `user_data` is ForceNew and a type change routes through the DESTRUCTIVE `git-data-host-replace`, so the shape must be right at birth. |
| **EMITTER verified** — it has actually emitted, not merely shipped | The rehearsal evidence named in the release record at the top of this runbook. `grep -c '$${sentry_dsn}'` proves nothing: the readiness gate checks THREADING, and a non-comment line that merely references the variable releases it. The question is whether an event ARRIVED. |
| `DOPPLER_TOKEN` is present | **Changed by #8178.** The poll resolves `BETTERSTACK_QUERY_{HOST,USERNAME,PASSWORD}` through `doppler run -p soleur -c prd_terraform`, so `DOPPLER_TOKEN` is the only repo-config precondition. (The GitHub-secret copies hold a SQL API connection that does not cover git-data's source; ADR-149's #8178 amendment has the history.) If the poll fails because the token is absent, the boot signal is **unread** and you are back to "a green apply proves nothing" — do not re-dispatch after a green apply; run the query in "After the birth". |

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
this repo is two-party.** The same read (2026-09-13) shows `can_admins_bypass: true`, and the
sole reviewer is an org admin — so for that person the approval is one click, optionally.
Re-measure rather than trusting this line:

```bash
gh api repos/jikig-ai/soleur/environments/web-platform-infra-apply \
  --jq '{can_admins_bypass, rules: [.protection_rules[] | select(.type=="required_reviewers")
        | {prevent_self_review, reviewers: [.reviewers[].reviewer.login]}]}'
```

One human clicking twice is the real control. Treat it as **one** control, not two.

**3 — The rehearsal evidence attests that a STAGE WAS REACHED, not that four invariants were
measured.** `luks_mounted`, `repo_root`, `hooks_path` and `provision` are **hardcoded
literals** at the emit call in `git-data-bootstrap.sh` — they read `yes` by construction.
That is not nothing: each has a named upstream `FATAL:` gate followed by `exit 1` (19 in that script — a 20th `FATAL:` match is the emitter arm inside `log()`, not a gate),
so a failure aborts *before* the emit rather than emitting `no`. Read them as "no gate
fired", never as "four invariants were measured".

Exactly **one** boolean in that row is measured: `nft_metadata_drop`, computed just above the
emit by grepping the live nftables chain (`nft list chain inet soleur_git_data output` for
`169.254.169.254`), anchored on the metadata address rather than the table name so a table
whose rule was flushed reads `no`. It is **not** in `git-data-rung2-boot-evidence.env` —
that file records the queries, and the capture projects only the four hardcoded booleans —
so it has to be read from Better Stack separately. For the rehearsal that cleared the banner
(run 34768256297, host `soleur-git-data-rehearsal-34768256297`) it read `yes` on the
`boot_complete` row at `2026-09-13 16:27:17 UTC`, via:

```bash
export BS_TABLE=t520508_soleur_git_data_prd_logs
doppler run -p soleur -c prd_terraform -- bash scripts/betterstack-query.sh \
  "SELECT dt, JSONExtractString(raw,'stage') AS stage,
          JSONExtractString(raw,'nft_metadata_drop') AS nft_metadata_drop
   FROM (SELECT dt, raw FROM remote(\$BS_TABLE)
         UNION ALL SELECT dt, raw FROM s3Cluster(primary, \$BS_TABLE_S3) WHERE _row_type = 1)
   WHERE JSONExtractString(raw,'host_name') = 'soleur-git-data-rehearsal-34768256297'
   ORDER BY dt ASC FORMAT JSONEachRow"
```

(An earlier rehearsal's reading, run 33888071954, was recorded in PR #8002's body; that
attestation was voided and deleted by #8052, so it is not the one this runbook rests on.)

Finally: the authorization-map interlock is a **static** assertion over Terraform source. It
proves what the production root *renders*, not what a live host *honours*. No live host is
probed, because none exists until this dispatch creates one.

**And it is weaker on the replace path than on this one.** `git-data-host-replace` carries no
`environment:`, therefore no `deployment_branch_policy`, so a `workflow_dispatch` there runs
the **selected ref's** scripts — the gate is supplied by the branch it polices. It holds
against an accidental collapse merged and dispatched from `main`; it does **not** hold against
a deliberate actor with repository write. What compensates is that the same gate runs against
the live production root on every pull request, so a collapse cannot reach `main` without
first reddening the required `test` check.

### The invariant Article 17 correctness rests on — asserted from PR #8052 (#8043 F8)

**Erasure and provision refuse to act unless the store is mounted, and never create it.** Until
2026-09-11 this was an *accident*, and the accident is worth keeping on record because it is
what the assertion replaced.

`git-data-remove.sh` derives `REPO_ROOT=/mnt/git-data/repositories`, then guards with
`readlink -f`. **`readlink -f` succeeds on a non-existent path whose parents all exist** (verified:
rc=0, and it prints the path), so on a host where the volume failed to mount, both path guards
passed. The script then created the repo root, found no repo, printed `not present (no-op)`
and **exited 0** — reporting Article 17 erasure success over a store nobody looked at.
`git-data-provision.sh` had the severe half: it ran `git init --bare` onto the root disk, where a
later successful mount silently hides the user's repository.

What prevented it was that the forced command runs as `git`, cloud-init creates `/mnt/git-data`
as root, and the bootstrap never chowned that mountpoint — so the create took EACCES and
`set -euo pipefail` aborted before the false success. One unrelated `chown` and erasure would
have begun silently succeeding over nothing.

**What asserts it now.** Both wrappers assert a second, independently-defaulted seam
`GIT_DATA_MOUNT_ROOT` (default `/mnt/git-data`) is a mount point — on the mount ROOT, not on
`REPO_ROOT`, because `mountpoint -q` on the `repositories` subdirectory returns 1 on a healthy
host and would refuse every erasure — and refuse with a named non-zero exit otherwise;
`mountpoint(1)` absent from PATH is itself a refusal. The create of the repo root is deleted from
both. Guard 1 in `git-data-remove.test.sh` / `git-data-provision.test.sh` pins it (mounted store
still erases; unmounted → refusal with the root still absent; instrument absent → fail closed).

**What this does NOT close, stated so it is not read as closed:** `account-delete.ts` catches the
refusal, mirrors it to Sentry, and continues the cascade — the user is still told the account
was deleted. That app-layer boundary is a follow-up deadlined to the `GIT_DATA_STORE_ENABLED`
cutover (#8043 FR17), not this host's job.

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
   which arm refused. Its last arm (#8189, shared with the replace gate) refuses unless the
   created server carries exactly the default key and the git-data root key, and the root
   key's `SHA256:` fingerprint equals `apps/web-platform/infra/git-data-root-key.fingerprint`:
   `verdict=git_data_root_key_not_in_create reason=<word>`. Remedy: dispatch
   `apply-git-data-root-key.yml`, commit its printed fingerprint, re-dispatch
   (`git-data-luks-cutover-5274.md` › verdict map).
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
>
> **Superseded 2026-09-15 (#8189):** both sites were deleted with the rest of the cutover body. The
> dispatch is now a read-only proof, and the real cutover is being rebuilt under #8211.

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

## Reading the poll's verdict (#8178)

Since #8178 the poll (both `git_data_host_create` and `git_data_host_replace`) reports
**three** outcomes. The verdict rests on the FINAL read, and the summary line
`answered=N/M` says how many reads answered.

| Verdict | What it means | Where to go |
|---|---|---|
| `received` | The host reported `boot_complete` after this run's anchor. | Nowhere. The per-field invariants run next. |
| `silent` | The final read ANSWERED and no `boot_complete` from this host generation was present. A statement about the host, or about its upload path. | Sentry events for `host_name:soleur-git-data` timestamped AFTER the run's boot-trail anchor, in this order: (1) a `stage:betterstack_ingest` warning means the host ran and its Better Stack upload failed; (2) a `stage:boot_complete` event means it finished booting, after the final read or with its upload lost — do not replace it; (3) a `level:fatal` event names the stage that failed; (4) `stage:bootcmd_start` with no `stage:gitdata_runcmd_ok` means it stopped in package or file setup, or its runcmd_ok emit was not delivered; (5) nothing at all means it died before its network came up. For a birth, then see "If it fails" above. For a replace there is no in-job remedy: do not re-dispatch it as a reading. |
| `unreadable` | The final read failed. If `answered=0`, nothing about the host was measured; if some reads answered, they saw no `boot_complete`, but the final window is unmeasured. | The READ path, never the host. The class names which fault it was. |

The class on an `unreadable` run:

| Class | Meaning |
|---|---|
| `credentials-rejected` | The read path refused the credentials. Rotate/verify them in `prd_terraform`. |
| `source-not-in-connection` | `CLUSTER_DOESNT_EXIST`: the SQL API connection in use does not cover this source (#7867). A connection covers only sources created before it; use the connection in `prd_terraform`, or create one that covers the source. |
| `source-under-maintenance` | The vendor's read path is under maintenance. |
| `transport` | DNS / connect / timeout / TLS from the runner, or the per-read 45 s cap expired. |
| `reader-refusal` | `betterstack-query.sh` refused (destination pin / usage / trace). A reader misconfiguration. |
| `credentials-absent` / `reader-exit-1` | The wiring itself: the three variables were not injected, or `doppler run` failed before the reader (check `DOPPLER_TOKEN`). |
| `other` | None of the above; read the per-poll line's rc and stderr. |

**Re-dispatch is never how to get a reading.** After a green birth apply the birth gate
refuses a re-dispatch. A replace can be re-dispatched, but every replace destroys and
recreates the host holding every connected user's repositories. Once the read works, run
the read-only query in "After the birth" with the run's boot-trail anchor. (There is no
web-host `git ls-remote` serving check yet; it is #5274 PR C. The existing web-host probe is
a TCP connect to :22, which answers on a host whose LUKS volume never mounted.)

The log never prints the response body, only its byte length: this repository is public,
and a ClickHouse auth failure body names the query username.

## After the birth — verify the host actually booted (#6982)

**A green apply is not a green boot.** The dispatch's own post-apply step polls for the
boot signal and FAILS the job if it does not arrive, so a green run is now meaningful; the
poll runs only after the apply step actually ran (green or failed) — a run refused at the
gate skips it, so a skipped poll is not a verdict on the host. A RED job whose summary shows
`apply outcome: success` is a failed VERIFICATION, not a failed birth: run the query below;
do not re-dispatch (the gate refuses a zero-create plan).

No SSH appears below, and none is possible: git-data has no human SSH path by design
(three `command=`/`no-pty` forced commands on a `/bin/sh` login shell — the forced-command map is the whole confinement, ADR-149 #8043 disposition — deny-all public ingress).

```bash
# 1. The boot-completion signal, with its FIVE assertions (#7772 added nft_metadata_drop).
#    BS_TABLE IS PINNED: git-data ships to its own source 2734275, not the shared 2457081
#    that betterstack-query.sh defaults to. Unpinned, this returns zero rows on a healthy
#    host and the reading instruction below sends you down the partial-birth tree for a
#    perfectly good birth. Field-isolated raw SQL — a
#    bare-substring grep matches the shared source's inngest rows quoting issue bodies.
#    NOTE `remote($BS_TABLE)` takes NO `primary` argument; only s3Cluster does. The
#    archive arm is REQUIRED: remote() alone is the ~40-minute hot window.
#    ANCHOR IS REQUIRED (#8178, AP-027): set ANCHOR to the epoch the run's
#    "Stamp boot-trail run anchor" step printed. host_name does not tell host generations
#    apart, so without it a replace whose new host never reported returns the DESTROYED
#    host's all-yes row and this query certifies a dark host.
ANCHOR=<epoch printed by the run's anchor step>
BS_TABLE=t520508_soleur_git_data_prd_logs BS_TABLE_S3=t520508_soleur_git_data_prd_s3 \
  doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh "
  SELECT dt, JSONExtractString(raw,'stage') AS stage,
             JSONExtractString(raw,'luks_mounted') AS luks_mounted,
             JSONExtractString(raw,'repo_root')    AS repo_root,
             JSONExtractString(raw,'hooks_path')   AS hooks_path,
             JSONExtractString(raw,'provision')    AS provision,
             JSONExtractString(raw,'nft_metadata_drop') AS nft_metadata_drop
  FROM (SELECT dt, raw FROM remote(\$BS_TABLE)
        UNION ALL SELECT dt, raw FROM s3Cluster(primary, \$BS_TABLE_S3) WHERE _row_type = 1)
  WHERE dt > fromUnixTimestamp(${ANCHOR})
    AND JSONExtractString(raw,'host_name') = 'soleur-git-data'
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
  | jq -r ".[] | \"\(.shortId)  \(.count)x  last=\(.lastSeen)  \(.title)\""'
#    Only issues whose `last=` is AFTER the run's anchor can describe this host generation.

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
- the `file()`-bound payloads `modules/git-data-userdata/main.tf` injects as plain text
  (`git-data-bootstrap.sh` and its siblings — #6982; `git_data_rung2_bound_files` in
  `tests/scripts/lib/git-data-birth-readiness-gate.sh` enumerates the current set, 13 inputs
  with the template and the module's `.tf` files)

**Every byte counts, comments included.** Post-birth, a one-word comment fix in either file
costs a full `git-data-host-replace`: a destroy-then-create of the host holding every
connected user's source code, with both volumes and the passphrase preserved *by omission*.
Pre-birth the same edit costs a full re-rehearsal instead — the evidence binds these bytes,
so any edit re-holds the birth until another paid cpx22 boots and a fresh evidence PR lands.
The omission is deliberate — it preserves the clean replace-to-reprovision path — so this is a
residual to respect, not a bug to fix.

There is also a hard **32,768-byte** cap on the rendered `user_data`, gated in CI by
`apps/web-platform/infra/git-data-userdata-budget.sh`. Measure with Terraform's own
`base64gzip`, never `gzip -9` — the latter overstates headroom.

**Deferred:** the `prjquota` MOUNT option is deliberately NOT set (#6982 / R31). The
`mkfs -O quota,project` FLAG ships because it is migration-forcing; the mount option is
reversible, does nothing until projects are assigned, and would add a new way for the mount
to fail at boot on a host with no console.
