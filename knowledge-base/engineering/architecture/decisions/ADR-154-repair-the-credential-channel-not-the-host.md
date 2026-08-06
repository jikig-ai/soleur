# ADR-154 — Repair the credential channel, not the host: zero stock makes `-replace` unavailable

- **Status:** Accepted
- **Date:** 2026-08-01
- **PR:** #7133
- **Issue:** #7095 (production has not deployed since 2026-07-29); follow-ups in #7103
- **Related:** [ADR-096](./ADR-096-migrate-container-registry-ghcr-to-self-hosted-zot.md) clause (f)
  (the mirror gate proves the image is readable by the PUSH credential, never that the host can pull
  it), [ADR-148](./ADR-148-web-host-replacement-is-a-distinct-gated-dispatch.md) (the
  `web-host-replace` arm this ADR declines to use),
  `.github/actions/cf-tunnel-ssh-bridge/action.yml` (where the new gate lives),
  `scripts/check-cloudflare-token-drift.sh` (the detector that was already right)

> **Ordinal.** ADR-154 is the next free ordinal against a freshly fetched `origin/main` (highest
> existing is ADR-153), verified at `/work` time. Provisional until `/ship` re-checks at merge.

## Context

On 2026-07-28 the `ci_ssh` Cloudflare Access service token was rotated out-of-band during incident
response. Cloudflare returns a service token's `client_secret` **only at create**, so the value in
Terraform state and the value in Doppler both went stale invisibly: `terraform plan` reported no
changes throughout, because there is nothing in the plan graph that can observe a credential the
provider will not read back.

Every remote write path to `web-1` authenticates with that credential. The consequence, measured
2026-08-01:

| Signal | Value |
|---|---|
| `app.soleur.ai/health` | `v0.244.0`, uptime 228095s (~63h) |
| `main` | `v0.247.1` |
| Consecutive failed `Web Platform Release` runs | **every release since `30465249534`** (2026-07-29T15:18Z) — 15 at the time of writing, 16 hours later. Anchored on the last success rather than an integer: while the channel is dark this count grows, so a number stated here rots by construction. |
| Host `ci-deploy` log | `ZOT_GATE: ZOT_REGISTRY_URL unset — GHCR path (dark, pre-provisioning)` → `PRELUDE: GHCR_READ_{USER,TOKEN} not both present` → `IMAGE_PULL_FAIL: result=auth_denied` |
| `Doppler Error: Invalid Auth token` on the inngest heartbeat | 55 events |
| The same token value read directly from Doppler | **HTTP 200 — valid** |

That last row is the whole diagnosis. The credential in Doppler authenticates; the credential
**baked into the host at first boot** does not. `var.doppler_token` is written once by cloud-init
and has no re-delivery path, so a merged code change cannot rotate it. This is a *delivery* gap,
not a *value* gap.

Two repairs were considered, and the obvious one is unavailable.

### Why the immutable redeploy is not the remedy here

`hr-prod-host-config-change-immutable-redeploy` says a prod host config change is repaired by
replacing the host, not by mutating it. That rule is right, and it has a precondition this
situation fails.

`web-1` is a `cx33` (Hetzner `server_type` id 115). Queried live against `/v1/datacenters` on
2026-08-01:

- `available = false` in **all 6** datacenters
- `available_for_migration = false` in all 6

`terraform apply -replace` on an `hcloud_server` **destroys before it creates**. With no create
side available, a replace does not produce a rebuilt host — it produces *no host*. The current
state is degraded but serving: `app.soleur.ai` continues to answer on v0.244.0 throughout. It is
safe for a STRONGER reason than an earlier draft gave — that draft said it is "served over the
tunnel", which is false. `tunnel.tf` declares exactly three ingress hostnames (`deploy.`,
`registry.`, `ssh.`) plus a 404 catch-all; `app.soleur.ai` is a CF-proxied **A record straight to
web-1's public IPv4** (`dns.tf`), covered by no Access application. So the serving surface does not
traverse the tunnel or Access at all, and nothing in this decision can reach it. A replace would take production from **stale but serving** to **destroyed and
unbootable**, with no rollback.

It would not even solve the problem. A fresh host runs 16 SSH-delivered installers, and those run
over the same bridge whose credential is dead. The redeploy needs the channel that the redeploy was
supposed to repair.

Blue-green fails for the same reason: there is no second `cx33` to green onto.

### Why the previous fix did not restore production

PR #7097 (merged 2026-07-31) contained the *correct* infra code. It never arrived. Its SSH-free
`local-exec` delivery leg (`terraform_data.deploy_pipeline_fix`) carries `depends_on`
`terraform_data.infra_config_handler_bootstrap`, which is root-SSH-provisioned. Run 30650564509
destroyed both resources, then failed on `ssh: handshake failed: connection reset by peer`. State
was left emptier than reality, and the payload never shipped. (`30650564509` is the only failing
run in the window, at `run_attempt: 1`; an earlier draft of this ADR claimed a second, identical
reproduction — the run history does not contain one.)

Its precondition was phrased as *"confirm the last green run of `apply-deploy-pipeline-fix.yml`"* —
a citation of a past state, not a probe of the present one. The last green run was 2026-07-30T16:30Z
and the channel died the following day.

### Why nobody noticed for three days

The first draft of this plan asserted a monitoring gap. That assertion was false, and the remedy
built on it would have caused a worse outage (see *Rejected* below).

`scripts/check-cloudflare-token-drift.sh` runs twice daily via `scheduled-terraform-drift.yml`. It
reported `verdict: dead` on runs 30608371251, 30653453432 and 30686984837 — three consecutive fires
spanning 24h across two calendar days (the OUTAGE ran three days; the fires did not) — naming the credential (`CI_SSH_ACCESS_TOKEN_ID/_SECRET`), the symptom
(`HTTP 403 from ssh.soleur.ai`) and the remedy. The `notify-ops-email` step ran every time.

The detector was never the gap. The verdict **blocked nothing** and **reached no one who acted on
it**.

## Decision

Three propositions.

### 1. Zero stock makes `-replace` *unavailable*, not merely inadvisable

Before selecting a host `-replace` as a remedy, query the target `server_type`'s live availability.
`-replace` is destroy-before-create; if `available` is false in the host's location, the operation
has **no create side** and the rule that prescribes it does not apply. Record the stock query in the
plan. This is a precondition of `hr-prod-host-config-change-immutable-redeploy`, not an exception to
it — and when it fails, the remedy is to repair the smallest thing that restores the control plane.

### 2. A detector firing into an unread channel has not detected anything

A monitoring control is only complete when its verdict reaches something that *acts*. A correct
diagnosis emitted into email three times while production stayed down is indistinguishable, in
outcome, from no detector at all. So a `dead` verdict must (a) **block** the channel it invalidates,
and (b) escalate to a surface that is harvested — an `action-required` issue, which
`operator-digest` reads, rather than only an email, which it cannot see.

Corollary, inherited from #7127: a verdict that means *"Cloudflare rejected this"* and a verdict
that means *"nothing answered, so I learned nothing"* must not share a code path. Their remedies are
opposite, and conflating them sends an operator to overwrite a healthy secret. The detector already
separates them; every consumer must read the structured verdict rather than the bare exit code,
which covers both.

### 3. Probe the transport before the destroy

Any workflow that destroys or mutates state over a remote channel must assert **the channel works
right now**, positively, before the first destructive operation — never by citing a past green run,
and never by a negative assertion. "No longer returns the denial body" is satisfied by a 502, a
timeout and a DNS failure, all of which leave the channel dead.

Implemented as the **final step** of the shared `cf-tunnel-ssh-bridge` composite action. Position is
the contract: because the composite is consumed as one `uses:` step and GitHub guarantees step
order, a caller that has invoked the bridge has necessarily passed the gate before any of its own
later steps run. One edit, six callers, no duplicated logic.

Note that the bridge *building successfully proves nothing here*: a local `cloudflared` TCP listener
opens whether or not the edge admits the service token, so `nc -z 127.0.0.1 2222` succeeds on a dead
credential. That is precisely how run 30650564509 got as far as destroying resources.

## Consequences

<!-- lint-infra-ignore start: the sentence below DESCRIBES the hand-run step this ADR
     ELIMINATES; it does not prescribe one. The whole positive consequence is that the
     operator-local apply is gone, replaced by a workflow_dispatch arm. -->
**Positive.** The recovery is in-band: a new narrow `ci-ssh-token-replace` arm on
`apply-web-platform-infra.yml` re-mints the token via `workflow_dispatch`, where previously the
documented repair was an operator-local `terraform apply` — the hand-run infra step
`hr-all-infrastructure-provisioning-servers` forbids.
<!-- lint-infra-ignore end --> A future occurrence of this failure fails
*loudly and early*, with a reason string that names the remedy, instead of at
`connection reset by peer` after a destroy.

**Negative / accepted — the deviation itself.** web-1 remains a MUTATED host, which is exactly the
state `hr-prod-host-config-change-immutable-redeploy` exists to prevent; declining the redeploy
accepts it. State and reality are known to disagree:
`terraform_data.{infra_config_handler_bootstrap,deploy_pipeline_fix}` are absent from state while
the host still carries the old handler. The recovery apply is what reconciles them.

**The exception has an expiry, and must not silently become permanent.** "0/6 datacenters on
2026-08-01" is a MEASUREMENT, not a property. When `cx33` returns to stock — or `var.web_hosts` is
repinned to an orderable type — the hard rule's precondition holds again and web-1 SHOULD be
redeployed. **Re-evaluation trigger:** the next host-level remediation proposal, or the next
`/v1/datacenters` query reporting `cx33` available in web-1's location, whichever comes first;
tracked as B7 on #7103. A hard-rule exception with no expiry is how a hard rule dies.

> **Re-examined 2026-08-06 (#7309) — the trigger did NOT fire; the exception STANDS.**
> Probed `.server_types.available`, 3 samples, per datacenter: `cx33` is **✗ in `hel1-dc2`**
> (web-1's location, which is what this trigger keys on) and **✓ in `nbg1-dc3` and
> `fsn1-dc14`**. So the "`available = false` in **all 6** datacenters" reading above is a
> 2026-08-01 sample and is now **false fleet-wide** — do not cite it as current. Only the
> `hel1-dc2` cell answers the question this exception rests on, and it is unchanged.
>
> **The trigger as written is also too weak, and #7309 is the evidence.** It fires on ONE
> green probe. `cx23` in `hel1-dc2` changed direction twice across twelve days — the first
> inside twenty-four hours — so a single ✓ is a moment, not a capacity reservation, and
> retiring a hard-rule exception on one reading is exactly the inference #7309 exists to
> warn against. Re-scope to a REPEATED, PER-DATACENTER sample under #6460, which must build
> that anyway. Until then, read this trigger as "sustained availability in web-1's DC",
> not "any query anywhere returns true".

**Negative / accepted — the gate.** The bridge now depends on the detector at run time: a detector defect, or a
Doppler enumeration failure, fails every SSH-bridged workflow. This is deliberate fail-closed
posture — the alternative is proceeding on an unmeasured channel, which is the defect being
removed — but it does put `check-cloudflare-token-drift.sh` on the critical path of five workflows
(six call sites; `workspaces-luks-cutover.yml` invokes the bridge twice).

The detector is not above suspicion either. PR #7127, merged 2026-08-01T12:48Z — AFTER all three
cited runs — fixed a defect whereby this same detector graded an `ssh://`-origin app DEAD
**unconditionally** (it accepted only HTTP 200, but that origin speaks SSH). At the moment those
verdicts fired it could not have returned anything else for this key. They were nonetheless
CORRECT — an independent 403 confirms the credential was genuinely dead — but a defect of exactly
the class accepted as a risk above existed in this detector twelve hours before this was written.
That is the strongest argument for keeping the `unverifiable` arm distinct from `dead`.
The `unverifiable` arm exists so that "the probe could not measure" is distinguishable from "the
credential is rejected" when triaging that.

**Unresolved, tracked in #7103.** `cloudflare_zero_trust_access_service_token.deploy` is *also*
stale in Terraform state (rotated in the same 2026-07-28 window), while Doppler holds the live
value. Any future untargeted apply that syncs outputs would republish the dead secret over the
working one and remove the last write path to an unreplaceable host. It needs its own PR that
sequences after `ci_ssh` is restored and updates all three holders atomically (Doppler, the
`secrets.CF_ACCESS_CLIENT_*` repo secrets, operator-env consumers).

Also tracked: the absence of a `deploy-web-image.yml` that can redeploy an **existing** tag. Its
absence is why an already-built, already-signed image sat unreachable for three days — the only way
to deploy is to mint a new version.

## Rejected alternatives

**Convert the Access tokens from Terraform `output`s to `doppler_secret` resources.** This was the
draft plan's centrepiece and three independent reviews converged on it as its most dangerous
content. It is cut in full, and recorded here so it is not re-proposed:

1. The hole it claimed to close does not exist. `ci_ssh` already auto-republishes on every apply via
   the `Sync CF Access CI-SSH service token to Doppler` step.
2. It would have been a regression. `doppler_secret` + `lifecycle.ignore_changes = [value]`
   suppresses the in-place update a rotation produces, so it would work exactly once and silently
   freeze every rotation after — manufacturing this outage permanently.
3. Its `.deploy` half would have taken production down. `.deploy` was rotated in the same window, so
   state holds the **dead** secret and Doppler the **live** one. `ignore_changes` does not suppress
   a *create*, so the create would publish the dead value over the working one, leaving zero remote
   write paths to a host with 0/6 datacenter stock.

**Replace `hcloud_server.web["web-1"]`.** Rejected on stock (proposition 1) and on circularity: the
rebuild needs the dead channel.

**Build a third liveness probe.** Rejected under proposition 2 — a probe already existed, already
ran, and already produced the right answer. Building another one fixes nothing.

**Patch the infra code again.** Rejected: the code on `main` is already correct. Two of the fifteen
failed releases (`30650563981`, `30688451384`) postdate that correct fix. The defect is arrival, not authorship.
