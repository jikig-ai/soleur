# Runbook — birthing the git-data host

> ## ⛔ DO NOT DISPATCH THIS YET
>
> `git-data-host-create` exists and is **mechanically held**. The job refuses to plan
> until **#6982** ships an off-host emitter in `cloud-init-git-data.yml`.
>
> This is not caution and it is not a preference — it is enforced by
> `tests/scripts/lib/git-data-birth-readiness-gate.sh`, which runs before any provider is
> contacted. If you dispatch today you get a clean refusal in about ten seconds and
> nothing is created.
>
> **Why the hold exists:** this host emits nothing off-host, and nothing in its boot path
> fails closed. A green `terraform apply` and a host whose encrypted volume never mounted
> are *indistinguishable*. #6982 also carries items ADR-115 makes **unfixable after the
> birth** — git-data is excluded from the reboot primitive, so a wrong sizing or a missing
> log shipper cannot be corrected by the usual reboot-forcing resize. Birthing first
> forecloses those options permanently.
>
> The full release checklist is in **ADR-149**. Clear this banner only when every item is
> done, not merely when the gate stops refusing.

---

## What this births

`soleur-git-data` — the shared bare-repo store that will hold every connected user's
source code and workspace history. It is **declared in IaC and has never existed**: an
authenticated `terraform state list` returns 201 addresses and zero git-data members.

Before this route existed there was no way to create it. `git-data-host-replace` cannot:
its gate requires `actions ⊇ {delete, create}`, so a first CREATE fails the
`server_replaced` arm; its `luks_passphrase_touched` arm fires on a create too; and its
five-member allow-set cannot hold an eighteen-address birth fan-out. The only remaining
route was an untargeted `terraform apply` from an operator laptop — no destroy-guard, no
stock preflight, and a plan of that shape taken 2026-07-27 carried **nine destroys**.

## Before you dispatch

| Check | How |
|---|---|
| #6982 has shipped and ADR-149's release checklist is complete | The banner above is cleared |
| You are on `main` | The environment pins `main`; a branch dispatch is refused |
| `prd_git_data` has **not** been hand-created in Doppler | `doppler configs -p soleur` — it must be ABSENT (Terraform creates it) |

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
5. **`terraform plan`** scoped to eighteen `-target`s.
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

**Be honest about what you cannot verify yet.** The probe above observes *reachability*, not
*boot correctness*: it tells you something answers on `10.0.1.20:22`, not that the bootstrap
ran or that the LUKS volume mounted. **The git-data host itself** emits nothing — no Sentry
emit, no log shipper, no heartbeat of its own — until #6982. A green apply means Terraform
created the resources; it does not mean the host booted correctly. That gap is the entire
reason the interlock exists, and it closes when #6982 does.

## References

- ADR-149 — this route, the interlock, and its release checklist
- ADR-145 — the web-host birth precedent this mirrors
- ADR-115 — why git-data is excluded from the reboot primitive
- ADR-103 — why every git-data address is an operator-applied exclusion
- ADR-068 — the multi-host workspaces architecture this serves
- `web-host-birth.md` — the sibling runbook
- `git-data-luks-cutover-5274.md` — the cutover that makes the LUKS volume live
- #6977 (this route) · #6982 (the interlock's release) · #5274 (Phase-3 GA)
