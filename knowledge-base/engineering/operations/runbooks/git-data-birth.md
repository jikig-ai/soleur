# Runbook — birthing the git-data host

> ## ⛔ DO NOT DISPATCH THIS YET
>
> **The MECHANICAL hold is released; this banner is now the only thing holding the route.**
> Read that twice before dispatching.
>
> #6982 shipped the off-host emitter, so `git-data-birth-readiness-gate.sh` no longer
> refuses — the sentinel it looks for (`${sentry_dsn}` in non-comment template text) is
> present. A dispatch today would **plan and apply**. Nothing stops you but this paragraph.
>
> **RELEASE CONDITION — clear this banner only when the rehearsal evidence exists.**
> Every gate #6982 ships is STATIC, and the failure class it defends against
> (*green apply, dark host*) is only observable at RUNTIME. Mutation arms prove the code
> CAN go red when neutered; they never prove an event ARRIVES when it is intact. So the
> condition is not "the code merged" — it is:
>
> 1. the rendered template booted **once on a throwaway host** outside the
>    `hcloud_server.git_data` address, and
> 2. all three artifacts were **observed off-box**: a Sentry event from the fatal channel,
>    a Better Stack stage marker, and one `stage:boot_complete` row carrying its four
>    assertion booleans — each with the query that retrieved it.
>
> If only the container-harness rung was reached, that is **not** sufficient: the harness
> cannot exercise `doppler run` against real Doppler, `luksOpen` against a real volume, the
> private NIC, or whether an event actually lands. The banner-clear PR carries the
> throwaway-host rung as **its own** precondition.
>
> **Why the hold outlived the gate:** the interlock is a ONE-BIT LATCH guarding a
> seven-item checklist, and the bit flips on *threading*, not on *emitting*. It cannot
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

1. **Validates `confirm`** — before anything reads a secret or contacts a provider.
2. **Birth-readiness interlock** — refuses while the host would boot dark.
3. Mints a throwaway SSH key (HCL evaluates `file()` at plan time; the git-data host is
   cloud-init-only and never receives it).
4. Asserts `SENTRY_DSN` is present and non-empty — *unreadable* and *empty* get different
   messages, because they have different remedies.
5. **`terraform plan`** scoped to twenty `-target`s — re-derive rather than trusting the
   number here:

   ```
   awk '/^  git_data_host_create:/{f=1}
        f && /^[[:space:]]*-target=/{n++}
        f && /^  [a-z_]+:$/ && !/git_data_host_create/{exit}
        END{print n}' .github/workflows/apply-web-platform-infra.yml    # => 20
   ```
6. **Birth gate** — refuses unless the plan is exactly the scoped birth. Its message names
   which arm refused.
7. **Stock preflight** — refuses if the server type is not orderable in its location. Runs
   *after* the birth gate: the gate proves the plan is the right plan, the preflight proves
   it is a feasible one.
8. **`terraform apply`**.

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
# 1. The boot-completion signal, with its four assertions. Field-isolated raw SQL — a
#    bare-substring grep matches the shared source's inngest rows quoting issue bodies.
#    NOTE `remote($BS_TABLE)` takes NO `primary` argument; only s3Cluster does. The
#    archive arm is REQUIRED: remote() alone is the ~40-minute hot window.
doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh "
  SELECT dt, JSONExtractString(raw,'stage') AS stage,
             JSONExtractString(raw,'luks_mounted') AS luks_mounted,
             JSONExtractString(raw,'repo_root')    AS repo_root,
             JSONExtractString(raw,'hooks_path')   AS hooks_path,
             JSONExtractString(raw,'provision')    AS provision
  FROM (SELECT * FROM remote(\$BS_TABLE)
        UNION ALL SELECT * FROM s3Cluster(primary, \$BS_TABLE_S3) WHERE _row_type = 1)
  WHERE JSONExtractString(raw,'host_name') = 'soleur-git-data'
    AND JSONExtractString(raw,'stage') = 'boot_complete'
  ORDER BY dt DESC LIMIT 5"

# 2. Any boot FATAL. Sentry is the durable channel and the only one that pages.
#    scripts/sentry-issue.sh takes an ISSUE ID, not a query (usage:
#    [--latest-event] [--redact] <issue-id>) — so search the issues API directly, then
#    feed an id it returns into that script for the full event.
doppler run -p soleur -c prd -- sh -c '
  q=$(printf "%s" "host_name:soleur-git-data" | jq -sRr @uri)
  curl -sS -H "Authorization: Bearer $SENTRY_AUTH_TOKEN" -H "Accept: application/json" \
    "https://sentry.io/api/0/organizations/jikigai-eu/issues/?query=$q&statsPeriod=24h" \
  | jq -r ".[] | \"\(.shortId)  \(.count)x  \(.title)\""'

#    Then, for any id above:
#    doppler run -p soleur -c prd -- bash scripts/sentry-issue.sh --latest-event <issue-id>

# 3. The standing probe (runs daily until it passes).
bash scripts/followthroughs/git-data-birth-emitter-6982.sh   # 0 PASS / 1 FAIL / 2 TRANSIENT
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
