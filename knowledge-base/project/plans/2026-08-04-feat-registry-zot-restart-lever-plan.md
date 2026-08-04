---
title: "feat: an operator-reachable restart lever for zot on the registry host"
issue: 7278
branch: feat-one-shot-7278-registry-restart-lever
lane: cross-domain
type: feature
brand_survival_threshold: aggregate pattern
requires_cpo_signoff: false
adr: ADR-169 (PROVISIONAL — re-derive against origin/main at ship)
created: 2026-08-04
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->

# feat: an operator-reachable restart lever for zot on the registry host

Closes #7278.

## Enhancement Summary (deepen-plan, 2026-08-04)

**Agents:** architecture-strategist, spec-flow-analyzer, security-sentinel, terraform-architect,
learnings-researcher. **Gates run:** 4.5, 4.55, 4.6, 4.7, 4.8, 4.9, 4.10.

Deepen-plan found **five blocking defects** in v1. Two of them invalidate v1's central
claims, and one is a pre-existing production landmine that v1 would have walked into.

### R1 (BLOCKING, pre-existing) — the activation vehicle is already broken

v1 named `registry-luks-recut` as the vehicle that activates the host half. **It cannot run
today.** Measured directly:

```
$ gzip -9 -c apps/web-platform/infra/cloud-init-registry.yml | base64 -w0 | wc -c
34320          # Hetzner user_data cap = 32768  → 1,552 bytes OVER, before template substitution
# siblings for scale: cloud-init-git-data.yml = 23312, cloud-init-inngest.yml = 18624
```

`hcloud_server.registry` renders `user_data = base64gzip(templatefile("cloud-init-registry.yml", …))`
with no comment stripping, and substitution only grows it (incompressible digests/URLs/tokens).
So **any** registry provisioning event — the recut included — fails at the Hetzner API right
now. This is inherited (it crossed the cap before this plan existed), not caused by it, but
v1's entire sequencing story rested on the recut succeeding and never checked.

**Response:** adopt the in-repo remedy as **Phase 1, ahead of all other work** —
`apps/web-platform/infra/modules/git-data-userdata/` already solves exactly this
("THE RATIONALE STRIP … comments were 61% of the raw payload") and ships a parity test
(`git-data-render-strip-parity.test.sh`). The registry must use it before this plan adds a
webhook binary, a hooks file, three scripts, a unit and an emitter. **This finding also
blocks #7277 and should be surfaced to the operator independently of this PR.**

### R2 (BLOCKING) — v1's success signal cannot work for `restart-zot`

v1 claimed a fresh `container_id` + `started_at >= FRESH_FLOOR` was "structurally impossible
for the old container to produce". **False, and v1's own R7 proves it:** `docker restart`
reuses the container, so `container_id` never changes — and `--restart unless-stopped` is
already advancing `started_at` every ~17 s, so a crash-looping zot satisfies any freshness
floor within seconds. v1 reproduced the exact anti-pattern it cited two paragraphs earlier.

**Response:** the success contract is rewritten in AC2 around **the loop stopping**, which is
the property the operator actually wants and which the burning outage cannot fake.

### R3 (BLOCKING) — this plan arms a host-replace landmine

`hcloud_server.registry` carries **"Deliberately NO lifecycle.ignore_changes=[user_data]"**
(`zot-registry.tf`), and `user_data` is ForceNew. Editing `cloud-init-registry.yml` therefore
leaves a **pending REPLACE of the registry host** in any untargeted plan — which, against
today's plaintext volume, hits R3's `refusing-non-luks-device` arm and takes the registry
permanently dark. v1's AC6 asserted "no replace" without naming which plan it evaluates, so
it would have passed *vacuously* against the CI-targeted plan while the landmine sat armed.

### R4 (BLOCKING) — the HMAC secret has no apply path, and either state is boot-fatal

`cloud-init-registry.yml` asserts both directions (`n_total -ne 4 || n_admitted -ne 4` →
`FATAL … refusing to launch`). Adding a 5th secret while the config holds 4 is fatal; bumping
the assertion to 5 while the secret is absent is also fatal. The two halves land on
**different, unorderable apply paths**: `zot-registry.tf` is an `OPERATOR_APPLIED_EXCLUSION`
(not in the CI `-target` list), and the recut's own gate forbids widening its 6-address
allow-set.

### R5 (BLOCKING) — AC5 guards the wrong artifact

`scripts/check-cloudflare-token-drift.sh` deliberately has **no hardcoded token list**
("A hardcoded list is exactly how CF_API_TOKEN_AUDIT was missed"); it enumerates from Doppler
and maps via an `access_hostname_for()` case arm keyed on the **uppercase** Doppler key. v1's
`grep -c registry_ctl` is case-sensitive and would never match `REGISTRY_CTL_ACCESS_TOKEN`.
Worse: an enumerated token with no mapping is reported **UNVERIFIABLE and fails the run**, so
v1 would have turned the fleet-wide scheduled drift detector red.

### Accepted-and-applied (non-blocking)

R6 AC3 must allowlist permitted hook keys — `adnanh/webhook` also honours
`pass-arguments-to-command` and `pass-file-to-command`, so v1's "zero
`pass-environment-to-command`" was itself a reject-list of one.
R7 Pin `hcloud_firewall_attachment.registry`, not just the zero-rule firewall — a detached
firewall is zero-rules *and* wide open once :9000 carries a root-equivalent listener.
R8 The registry-ctl credentials must **not** land in `soleur/prd` root (the release token
reads it — every release run could fire `recreate-zot`).
R9 `.github/workflows/scheduled-zot-restart-loop.yml` is the responder's real first-read
surface and was missing from Files to Edit; and v1's premise about
`zot-restart-loop-alarm.sh` was wrong — its `registry-host-replace` text lives in the
**NIC_CAUSE** arms (a different failure class a container restart cannot fix), so
re-pointing those would be actively harmful.
R10 `lever_not_activated` must print its escalation path, or Phase 6 makes the incident
path strictly worse than today's.
R11 Baking `hooks.json` into `user_data` makes the action set immutable-until-reprovision —
an ADR consequence, not only a security property.
R12 Add a `## Downtime & Cutover` section (gate 4.55): the tunnel ingress list is a
whole-list replacement on the live serving path for `deploy.`/`ssh.`/`registry.`.

> Phase 2.8 note: every provisioning step in this plan is a Terraform resource plus
> cloud-init. The phrases that read as manual framing below appear only in *prohibitions*
> (statements that such steps must not exist) and in acceptance criteria that assert their
> absence. There is no operator-executed provisioning step anywhere in this plan.

## Overview

The registry host has no in-place restart lever. The Inngest host has
`restart-inngest-server.yml`; the registry host has no equivalent and no shell. On
2026-08-03 that gap turned a container crash-loop into a 22-hour, 6-release outage
whose only proposed remedies were destroy-the-host or destroy-the-store — and both
were blocked anyway.

This plan adds a **parameterless, allow-listed control listener on the registry host**
reachable over the existing Cloudflare tunnel through a **new dedicated ingress
hostname and its own CF Access service token**, driven by a GitHub Actions workflow
that mirrors `restart-inngest-server.yml`'s freshness-anchored two-signal verification.

Two findings below change the shape of the work relative to the issue body. Both were
verified against code and live telemetry, not paraphrased (`hr-verify-repo-capability-claim-before-assert`):

1. **The issue's preferred option (c) — "reuse the deploy-webhook pattern, adds no new
   inbound" — is refuted.** The deploy webhook is pinned to web-1 and cannot reach the
   registry host at all. Every viable option requires new inbound to `10.0.1.30` or a
   new remote-exec primitive. See §Research Reconciliation R1.
2. **Delivery, not transport, is the binding constraint.** ADR-096 makes the registry
   host cloud-init-only, so the listener can only land via a provisioning event — and
   `registry-host-replace` is currently blocked. See §Research Reconciliation R2 and
   §Activation Sequencing. This is the single most important thing this plan contributes
   that the issue does not contain.

---

## ⚠ Live incident finding (measured during planning, 2026-08-04 ~16:40 UTC)

Pulled directly from Better Stack per `hr-no-dashboard-eyeball-pull-data-yourself`
(`doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 12h --grep SOLEUR_ZOT_DISK`):

| time (UTC) | `pcent` | `zot_restarts` | `state_status` | `oom_kills_5m` |
|---|---|---|---|---|
| ~04:40 | 30 | 2757 | running | 0 |
| 15:35 | 67 | 5308 | running | 0 |
| 16:00 | 78 | 5407 | running | 0 |
| 16:40 | 82 | 5556 | running | 0 |

Three facts follow, and each one is load-bearing for this plan:

- **The crash-loop is live right now**, at ~3.6 restarts/min (#7247 is still OPEN).
- **It is not OOM.** `zot_anon_mb` is 36-47 MB against `zot_memory_cap_mb=3072`,
  `zot_oom_kills=0`, `oom_killed=false`. Any plan premised on the ADR-062 memory cap is
  premised on a refuted cause.
- **The crash-loop is filling the store.** `pcent` climbed 30 → 82 in ~12 h, and
  67 → 82 in the last 65 minutes (~14 points/hour) on a 59 GB filesystem. Extrapolating
  the recent rate, the store reaches 100 % within roughly 1-2 hours of the measurement
  above. zot is the **sole** pull path (GHCR is dead as a fallback, ADR-096 amendment
  2026-07-30), so a full store is a fleet-wide hard-down of deploys.

**Consequence for this plan, stated plainly:** this lever cannot be delivered before that
deadline (see §Activation Sequencing), so it is not the remedy for the currently-burning
incident. It is the remedy for the *next* one. The disk exhaustion belongs to #7247 and
must be raised with the operator immediately and separately — this plan does not and
cannot absorb it.

A grim corollary worth stating because it affects sequencing: if the store does fill and
the registry hard-downs, the store's contents become worthless, which removes the very
thing `registry-luks-recut` exists to preserve — and thereby *unblocks* the recut. The
recut is this lever's activation vehicle. That makes landing this code promptly more
valuable, not less.

---

## Research Reconciliation — issue claims vs. codebase reality

<!-- lint-infra-ignore start -->
<!-- This table DESCRIBES existing reality and records alternatives this plan REJECTS
     (notably R8's SSH break-glass and R6's why-not-journald). It prescribes no step for
     anyone to execute. The no-human-steps gate matches on actor+SSH co-occurrence, which
     this necessarily contains in order to rule those paths out. -->

| Issue / prior-art claim | Reality (verified) | Plan response |
|---|---|---|
| **R1.** Option (c), reusing the deploy-webhook, "adds no new inbound" and is closest to precedent. | **Refuted.** `tunnel.tf` `ingress_rule` for `deploy.${var.app_domain_base}` is `http://${var.web_hosts["web-1"].private_ip}:9000` — pinned to web-1. `ci-deploy.sh`'s restart arm rejects any component other than `inngest` (`component_not_restartable`) and executes `docker`/`systemctl` **locally**; it has no remote-exec primitive for `10.0.1.30`. `cloud-init-registry.yml` contains no `webhook`, no `hooks.json`, no `cloudflared`, no `:9000`. | Adopt the deploy-webhook **pattern** (adnanh/webhook + HMAC trigger-rule + dedicated CF Access app/token + signed status hook + freshness-anchored poll) but on a **new** registry-side listener with its **own** ingress hostname and token. Record the refutation in the ADR's Alternatives Considered. |
| **R2.** Transport is the open question. | **The open question is delivery.** ADR-096 rules the registry host cloud-init-only ("an SSH-provisioned `terraform_data` would hit the first parity guard"). The only vehicle for new host-side code is a provisioning event. | Add §Activation Sequencing. Split the change so the Terraform/edge half applies on merge and the host half activates at the next provisioning. |
| **R3.** `registry-host-replace` is blocked because LUKS resources are absent from state (`out_of_scope=2`); if forced, cloud-init refuses the plaintext volume and the registry goes permanently dark. | **Confirmed, and the fatal half is the second one.** `cloud-init-registry.yml` blkid discriminator: the `*)` arm prints `reason=refusing-non-luks-device … a plaintext volume must be recut, not wiped (ADR-096)` and `exit 1`. The zot launch additionally gates on `findmnt -no SOURCE /var/lib/zot \| grep -qx /dev/mapper/registry` and refuses "to serve an empty/unencrypted store". Independently corroborated by `model.c4` on the `zotRegistry` element: *"The LIVE device is still plaintext ext4 until the guarded `registry-luks-recut` workflow_dispatch is fired; that vehicle shipped UNFIRED (#6929)."* | Treat the replace path as unavailable. Do **not** propose forcing it. Activation rides #7277's recut. |
| **R4.** (Inherited from `model.c4`, #6460) `soleur-registry` runs a server type that "can no longer be ordered", so it cannot be rebuilt. | **Stale as of a live probe on 2026-08-04.** `GET /v1/datacenters` → `cx23` (id 114) is `available` in **nbg1-dc3 and hel1-dc2**; `cpx22` (109) in all three; `cx33` (115) in nbg1-dc3. The `registry-host-replace` stock-preflight would **pass** today. | Stock is **not** a blocker; do not cite it as one. Correct the stale claim in `model.c4` as part of the C4 task. |
| **R5.** (Inherited from `model.c4` `zotRegistry` description) The registry host is a "cx33, 4 vCPU / 8 GB". | **Contradicted** by the sibling `hetzner` element in the same file ("soleur-registry (cx23)"), by `variables.tf` (`registry_server_type` default reverted to `cx23` per #6497/#6463), and by live telemetry (`mem_total_mb=3819` ≈ 4 GB). | Fix the `zotRegistry` description in the C4 task — the change falsifies it and the completeness mandate requires fixing it. |
| **R6.** AC2: ship the component's own error channel as "journald → Vector allowlist". | **Does not apply to this host.** `cloud-init-registry.yml` has no Vector; `grep -n vector` returns nothing. The registry host self-reports via cron + `doppler run --project soleur-registry --config prd` + `curl` POST to Better Stack Logs source 2457081. ADR-096 rejected a journald interim explicitly because journald needs SSH to read (`hr-no-ssh-fallback-in-runbooks`). | Ship the error channel on the host's **actual** observability layer: a new `SOLEUR_ZOT_RESTART` structured line to the same Better Stack Logs source, queryable with `betterstack-query.sh --grep`, no SSH. Cited in §Observability per `hr-observability-layer-citation`. |
| **R7.** `--restart unless-stopped` already restarted the container 5000+ times, so what is missing is a restart that can *change* something. | **Confirmed and sharpened.** Live `zot_restarts=5556`. Institutional learning `2026-03-19-docker-restart-does-not-apply-new-images.md`: `docker restart` reuses the existing container **and its existing image** — a freshly pulled image is never used. | The action set must include a **recreate** (pull → `rm -f` → `run`), not only a `docker restart`. Both ship; the runbook points at `recreate-zot` as the one that changes something. |
| **R8.** The current operational surface is "an empty set". | **Very nearly true, with one caveat worth recording.** `hcloud_ssh_key.default` is attached to `hcloud_server.registry` as well as the web/git-data/inngest hosts, so an operator-key SSH ProxyJump from web-1 to `10.0.1.30` is *technically* reachable. No such path exists anywhere in the repo (`grep` for an ssh/jump reference to `10.0.1.30` returns nothing). | Record it in the ADR as a **considered-and-rejected break-glass**, not as an existing lever: it grants full root shell (violates AC3), it is SSH in a runbook (`hr-no-ssh-fallback-in-runbooks`), and it re-creates the #7095 token-rotation class. Naming it is what stops the next responder rediscovering it under pressure. |

<!-- lint-infra-ignore end -->

---

## Hypotheses (why zot is crash-looping) — NOT this plan's deliverable

Recorded because the lever's action set must be useful against the real cause, and
because a hypothesis table must not read CONFIRMED while its discriminator is invisible.

| # | Hypothesis | Status | Discriminator |
|---|---|---|---|
| H1 | Host/container OOM (the #6288 class) | **REFUTED** by measurement | `zot_oom_kills=0`, `oom_killed=false`, `zot_anon_mb` 36-47 MB vs `zot_memory_cap_mb=3072`, over 12 h |
| H2 | Store exhaustion causes the loop | **UNKNOWN — direction unresolved** | `pcent` 30→82 while looping. Cause vs. effect is not decidable from this data; a GC that restarts mid-pass could leak orphans, or a full-ish store could crash zot. Needs zot's own stderr. |
| H3 | Corrupt blob/index crashes zot on a specific GC pass | **UNKNOWN** | `zot_last_err` is a truncated tail of the *info*-level HTTP/gc log — the fatal line is not in it. Deciding datum is zot's stderr on exit, which is not currently shipped. |
| H4 | Bad/incompatible zot image | **UNKNOWN** | Would be discriminated by `recreate-zot` pulling a fresh digest. |

**No verdict above may be upgraded without its discriminator.** H2/H3/H4 are precisely
why the lever needs a *recreate* and a *status* hook: `restart-zot-status` returning the
running image digest and the container's exit history is a discriminator this plan
creates. Shipping a diagnosis is #7247's job, not this plan's.

---

## Decision: transport

**Chosen — Option A: a registry-side `adnanh/webhook` control listener, behind a new
dedicated tunnel ingress hostname and its own CF Access service token.**

| Option | Verdict | Reason |
|---|---|---|
| **(A) Registry-side webhook + new ingress + dedicated Access token** | **CHOSEN** | Highest fidelity to the in-repo precedent (`webhook.service` + `hooks.json.tmpl` + `cloudflare_zero_trust_access_*` + a signed status hook + a freshness-anchored poll — every piece is already templated and unit-tested). Origin-relative service satisfies ADR-114 I2 by construction. Satisfies AC3 **structurally**: the hooks pass no payload to the command at all. |
| (B) / (c-ii) web-1-relayed via `ci-deploy.sh` | Rejected | Still needs a listener on `10.0.1.30` — zot's `:5000` exposes no restart API — so it pays the identical cloud-init cost while *additionally* widening the deploy webhook's blast radius to the registry, and putting registry control inside the deploy `flock` and its 4800 s cap. Strictly worse on every axis. |
| (C) / (a) an `ssh.`-style ingress for the registry host | Rejected | Grants a full root shell, which cannot satisfy "cannot be used to reach anything other than the zot container" without a forced-command `authorized_keys` — which itself needs cloud-init, so it does not even dodge the delivery cost. Also SSH-in-a-runbook (`hr-no-ssh-fallback-in-runbooks`) and re-creates the #7095 class. |
| (D) Hetzner API `server reboot` (not in the issue's list) | Rejected | Zero-code-change and available today, but unsafe on *this* host: cloud-init `runcmd` is once-per-instance, so the `findmnt` gate does **not** re-run on reboot; if the store fails to remount, the existing container restarts against an empty root-disk path and zot serves an **empty store answering 200** — converting a loud crash-loop into a silent empty-store outage (the exact class in learning `2026-07-24-guest-luks-store-must-gate-consumer-on-mount…`). Record in the ADR so it is not rediscovered as "the obvious quick fix". |

### Why this satisfies AC3 by construction, not by validation

The deploy webhook parses a command grammar (`read -r ACTION COMPONENT IMAGE TAG <<< "$SSH_ORIGINAL_COMMAND"`) and defends it with a **reject list**. A reject list is only as good as its enumeration.

The registry lever ships **no grammar**. There are exactly three hooks; the action is the
**hook id in the URL**, never a parameter; and each hook's `pass-environment-to-command`
is **empty** — no payload field is forwarded to any script. An attacker holding both the
HMAC secret and the CF Access token can therefore do exactly three things, and there is no
input surface through which to attempt a fourth. This is the property to assert in tests.

---

## Activation Sequencing (load-bearing)

The change splits cleanly into two halves with different apply paths:

| Half | Contents | Applies |
|---|---|---|
| **Edge half** | New `ingress_rule`, `cloudflare_zero_trust_access_application`/`_service_token`/`_policy`, the `doppler_secret`s, the `random_password` HMAC secret, the drift-check registration | On merge, via the existing auto-apply — **but only after the `-target=` allowlist is extended; see the ordering invariant below.** Harmless while nothing listens: the ingress resolves to a closed port and returns 502/404. |

### ⚠ Ordering invariant: the ingress rule must never be live without its Access policy

The merge-apply job in `.github/workflows/apply-web-platform-infra.yml` runs against a
**hand-maintained `-target=` allowlist** (~238 entries). Verified:
`cloudflare_zero_trust_tunnel_cloudflared_config.web` **is** in that set, alongside
`cloudflare_zero_trust_access_application.deploy` / `.ssh`, their tokens and policies, and
`cloudflare_record.deploy` / `.ssh`.

The consequence is a **P0 if missed**: the tunnel config resource is already targeted, so a
merge that adds a fourth `ingress_rule` **publishes the new control hostname on the next
merge-apply** — while the new `cloudflare_zero_trust_access_application.registry_ctl`,
`..._service_token.registry_ctl` and `..._policy.registry_ctl_service_token` are **absent
from the allowlist** and would therefore **not** be created. That is a control-plane
hostname routed to the registry host with **no CF Access in front of it**.

Therefore, as a merge-blocking requirement:

- All four new resources (Access application, service token, policy, and
  `cloudflare_record.registry_ctl`) **must be added to the `-target=` allowlist in the same
  PR** as the ingress rule, so they are created in the same apply.
- Per the allowlist Sharp Edge, the work-list is derived from `git grep`, not from the
  filter alone. Three artifacts assert on this set and **all** must be swept:
  `.github/workflows/apply-web-platform-infra.yml` (the list),
  `tests/scripts/test-destroy-guard-counter-web-platform.sh` (the counter test), and
  `.github/workflows/infra-validation.yml`. Re-run the `git grep -ln -- '-target='
  tests/ scripts/ .github/` sweep at /work time in case the set has grown.
- Add an AC asserting the plan output shows the Access policy created **in the same apply
  as** the ingress rule, never after it.
| **Host half** | `webhook` binary, `hooks.json`, `zot-control.service`, `restart-zot.sh` / `recreate-zot.sh` / `zot-status.sh`, the `SOLEUR_ZOT_RESTART` emitter | At the **next registry-host provisioning event** — `runcmd` is once-per-instance and no gate re-runs on a booted host. |

**The next provisioning event is #7277's `registry-luks-recut`.** `registry-host-replace`
is unavailable (R3). Therefore:

- **This PR must merge before the recut fires**, or the reprovisioning window is spent
  and the lever waits for the one after that. This is a sequencing constraint the issue
  does not state and the recut runbook does not know about; the runbook pointer task
  below must carry it.
- The plan must **not** claim the lever is live at merge. AC1 is satisfied *as delivered
  capability*, with activation gated on a provisioning event that this plan does not own.
  Anything else would be a false-green of exactly the class this issue exists to prevent.
- The activation state must be **observable, never assumed** — see the activation probe
  in §Observability. A lever whose liveness is inferred rather than measured is the
  silent-failure anti-pattern in AC2 wearing a different hat.

---

## Downtime & Cutover

Gate 4.55 fires on the **deploy/router class**: the change rewrites
`cloudflare_zero_trust_tunnel_cloudflared_config.web`'s `ingress_rule` list, and that
resource is the **live serving path** for `deploy.` (the deploy webhook), `ssh.` (the CI
runner bridge) and `registry.` (the fleet's sole image-pull path). v1's claim that "nothing in
the edge half touches a serving path" was wrong, and its "harmless while nothing listens" was
right for the wrong reason (it is inert because no DNS record resolves yet, not because the
origin returns 502/404).

**Offline-inducing operation:** the ingress list is a **whole-list replacement**. Terraform
sends the full `config` block; a dropped or reordered rule silently breaks the route it
belonged to, and ingress rules are **first-match**, so a rule landing below the
`http_status:404` catch-all is dead.

**Zero-downtime path (default, chosen):**
1. The new rule is **appended above the catch-all** and below the three existing rules — it
   cannot shadow them, because hostnames are disjoint and matching is exact-host.
2. The four new resources land in the **same apply** as the ingress edit (the §Ordering
   invariant), so the hostname never resolves without its Access policy.
3. `cloudflare_record.registry_ctl` carries an explicit `depends_on` the Access policy, so DNS
   cannot resolve ahead of admission control.
4. **Pre-apply verification:** dump the live ingress list before applying and assert the plan
   preserves all three existing rules verbatim and in relative order. This is the
   whole-list-replacement discipline ADR-136/#6767 established for ruleset entrypoints; it is
   **not** currently wired for tunnel configs, and this plan should record that gap rather than
   assume the existing gate covers it.
5. **Rollback:** revert the ingress-rule addition and re-apply; the three existing rules are
   restored from the same declarative source. No data is involved.

**Residual downtime:** none expected. The apply mutates Cloudflare edge config, not the origin;
existing routes are unchanged tuples. The residual *risk* — not downtime — is a malformed
whole-list write during an active incident, which step 4 is designed to catch.

**Timing caveat:** the registry store is filling (§Live incident finding). Prefer not to apply
a tunnel-config rewrite during the window in which the sole pull path may be hard-downing; the
edge half has no urgency, because the host half cannot activate until the recut anyway.

---

## User-Brand Impact

**If this lands broken, the user experiences:** an operator or agent fires the restart
lever during an outage and gets a green run while zot is still down — or worse,
`recreate-zot` runs against an unmounted store and zot comes up serving an **empty
registry**, so every host in the fleet pulls a nonexistent image and the whole platform
becomes undeployable (the #7071 shape, which cost ~5 h, and the 2026-08-03 shape, which
cost ~22 h).

**If this leaks, the user's workflow is exposed via:** the HMAC secret plus the CF Access
service token together permit repeated `recreate-zot` calls against the sole pull path —
a denial-of-release primitive. No user data traverses this surface (the store holds our
own OCI blobs and cosign signatures); the exposure is availability, not confidentiality.

**Brand-survival threshold:** `aggregate pattern`

Rationale for not selecting `single-user incident`: no user or customer data is reachable
from this surface at any point, so no single user's breach is possible through it. The
harm is fleet availability, which is felt in aggregate. The threshold is set on the
evidence, not to select a review tier — and §Plan Review below requests
`architecture-strategist` explicitly regardless of tier, because this is a new trust
boundary on a production host.

---

## Architecture Decision (ADR/C4)

This introduces a new trust boundary (a remotely-triggerable, root-equivalent control
surface) on a production host, so per `wg-architecture-decision-is-a-plan-deliverable`
the ADR and the C4 update are deliverables of **this** plan.

### ADR

**Create `ADR-169-registry-host-control-plane-parameterless-allowlisted-lever.md`.**

Ordinal is **PROVISIONAL**: `origin/main` currently tops out at ADR-168 (167 is absent),
so 169 is next-free — but a sibling PR can claim it during the pipeline, and
`adr-ordinals` is not a required check. Re-derive at ship, and if it moves, sweep
`grep -rn 'ADR-169' knowledge-base/project/{plans,specs}/feat-one-shot-7278-registry-restart-lever/`
in the same edit so the plan, tasks and any AC naming the ordinal move with it.

Decision to record: *the registry host gets a control plane, and it is a parameterless
allow-list rather than a command grammar.* Must include:

<!-- lint-infra-ignore start -->
<!-- The Alternatives-Considered bullet names the SSH/reboot paths this ADR REJECTS.
     Naming a rejected path is not prescribing it. -->


- The R1 refutation (the deploy webhook cannot reach the registry host) so the "reuse
  deploy.soleur.ai" idea is not re-proposed.
- **The root-equivalence disclosure, stated honestly:** the control user needs Docker
  socket access, and Docker socket access is root-equivalent on the host. The mitigation
  is *not* that the interface is unprivileged — it is that the interface exposes no input
  surface: three fixed hooks, zero forwarded parameters, no shell. The privilege lives in
  the scripts, which are baked and immutable between provisionings.
- Alternatives Considered: (B) web-1 relay, (C) SSH ingress, (D) Hetzner reboot, and the
  (R8) operator-key ProxyJump break-glass — each with its rejection reason.
- Amend ADR-096's cloud-init-only ruling with the consequence this plan discovered: it
  makes every host-side capability wait for a provisioning event, which is why the
  activation-sequencing constraint above exists.

<!-- lint-infra-ignore end -->

### C4 views

Per the C4 completeness mandate, all three of `model.c4`, `views.c4` and `spec.c4` were
read, and the enumeration below is what the "no new element" conclusion rests on:

- **(a) External human actors:** the operator (`founder`) — already modeled. The lever is
  fired from GitHub Actions, so no new actor.
- **(b) External systems / vendors:** GitHub (`github`), Cloudflare tunnel/Access
  (`tunnel`, `cloudflare`), Better Stack (`betterstack`), Doppler (`doppler`) — **all
  already modeled**. No new vendor is introduced.
- **(c) Containers / data stores touched:** `zotRegistry` — already modeled. No new store.
- **(d) Access relationships that change:** **YES, and this is the new edge.**
  `github → tunnel → zotRegistry` today carries only the **data plane** (registry push).
  It gains a **control plane**. That relationship change must be drawn.

Because no new *element* is introduced, no new `view … include` line is required —
`zotRegistry` already appears in both views that list it. Edits required in `model.c4`:

1. `tunnel` element description: "THREE ingress rules (deploy./ssh./registry.)" → **four**, naming the new control hostname and its origin-relative service.
2. New/extended `tunnel -> zotRegistry` control edge (distinct from the existing `registry.` data-plane edge), noting the parameterless hook set and the separate Access token.
3. `zotRegistry` description: add the control plane; **fix the falsified "cx33, 4 vCPU / 8 GB"** to cx23/4 GB (R5); **retire the stale "cannot be rebuilt / unorderable" claim** (R4) with the 2026-08-04 probe as evidence.
4. `zotRegistry -> betterstack` description: add `SOLEUR_ZOT_RESTART` to the shipped markers.

Then run the C4 validation tests (`apps/web-platform/test/c4-code-syntax.test.ts` and
`c4-render.test.ts`) — a `view include` referencing an undefined element fails there, not
at `tsc`.

### Sequencing

The ADR describes the target state and ships with status `adopting`, flipping to
`accepted` once a provisioning event activates the host half and a real fire is measured.

---

## Infrastructure (IaC)

### Terraform changes

`apps/web-platform/infra/tunnel.tf`
- A **fourth** `ingress_rule` on `cloudflare_zero_trust_tunnel_cloudflared_config.web`:
  hostname `registry-ctl.${var.app_domain_base}`, service
  `http://${local.registry_private_ip}:9000`. **Origin-relative** (ADR-114 I2). Must sit
  **above** the `http_status:404` catch-all — ingress rules are first-match.
- `cloudflare_zero_trust_access_application.registry_ctl` — `session_duration = "15m"`,
  matching the `ssh` and `registry` apps rather than `deploy`'s 24 h, because this is a
  control surface.
- `cloudflare_zero_trust_access_service_token.registry_ctl` — **a new dedicated token**,
  not a reuse of `deploy`/`ci_ssh`/`registry_push`, so registry *control* rotates
  independently of registry *write* and host shell. Needs
  `lifecycle { create_before_destroy = true }` — Cloudflare rejects destroying a token
  while a policy references it (error 12139), exactly as the three siblings document.
- `cloudflare_zero_trust_access_policy.registry_ctl_service_token`.
- `apps/web-platform/infra/dns.tf` — CNAME for `registry-ctl` to
  `<tunnel-id>.cfargotunnel.com`, mirroring the three existing records.

`apps/web-platform/infra/zot-registry.tf`
- `random_password.registry_ctl_webhook_secret` — the HMAC secret, **TF-generated**, never
  operator-minted (`hr-tf-variable-no-operator-mint-default`); mirrors
  `random_password.registry_luks`. Introduces **no** no-default variable, so the
  merge-triggered apply cannot fail on an unprovisioned `TF_VAR_*`.
- `doppler_secret` entries publishing the HMAC secret into the isolated
  `soleur-registry/prd` project so cloud-init can read it through the **existing** scoped
  boot credential. **This changes the admitted-secret cardinality**: the boot isolation
  self-check in `cloud-init-registry.yml` asserts `n_admitted=…` with a fixed cardinality
  (currently 4, including `REGISTRY_LUKS_KEY`). That assertion must be updated in the same
  change or first boot fails its own self-check.
- The CF Access token id/secret published for the workflow to read.

**#7071 trap — mandatory, not optional.** Every `doppler_secret` carrying a token in this
root declares `lifecycle { ignore_changes = [value] }`. That is precisely what caused
#7071: Terraform *replaced* the `registry_push` Access token and could never propagate the
new value, so a stale token was served until CI failed with `websocket: bad handshake`.
The new token must therefore be **registered in `scripts/check-cloudflare-token-drift.sh`**
(already wired into `scheduled-terraform-drift.yml` and a release preflight). Omitting this
reproduces #7071 silently on the new surface.

`apps/web-platform/infra/cloud-init-registry.yml`
- Install the `webhook` binary; write `/etc/webhook/registry-hooks.json`; add
  `zot-control.service`; add `restart-zot.sh`, `recreate-zot.sh`, `zot-status.sh`; add the
  `SOLEUR_ZOT_RESTART` emitter.
- **The listener must be non-fatal to boot.** Its installation must never `exit 1` in
  `runcmd` — a failed control-plane install must not become a new reason a
  reprovisioning leaves the registry dark. It fails *loud* via telemetry, not via boot.
- The host firewall stays at **zero rules** (deny-all-public). Port 9000 is reachable only
  from `10.0.1.0/24`, exactly as web-1's `:9000` is — Hetzner filters only the public NIC.
  No `hcloud_firewall.registry` change; add a test pinning that it stays empty.

### Apply path

**(a) cloud-init + (b) edge-applies-on-merge, split.** The edge half applies on merge and
is inert until a listener exists. The host half is cloud-init-only per ADR-096 and
activates at the next provisioning event (§Activation Sequencing). Expected downtime from
this PR: **none** — nothing in the edge half touches a serving path. This is an immutable
redeploy in the `hr-prod-host-config-change-immutable-redeploy` sense: the host config
change is delivered by re-provisioning, never patched in place.

### Distinctness / drift safeguards

- `create_before_destroy` on the service token (the 12139 trap).
- `ignore_changes = [value]` on the `doppler_secret`s **plus** drift-check registration
  (the #7071 trap above). The safeguard is the drift check; `ignore_changes` alone is the
  bug.
- The HMAC secret and the Access client secret land in `terraform.tfstate` — state is on
  the encrypted R2 backend.
- CF Access service tokens expire (default 1 y) and expiry presents as an indistinguishable
  403. `cloudflare_notification_policy.service_token_expiry` already fires account-wide for
  all tokens; update its description to name the fourth token.

### Vendor-tier reality check

No new vendor and no new paid-tier resource. Cloudflare Zero Trust Access service tokens
and tunnel ingress rules are in use on this account already (three of each).

---

## Observability

Layer citation per `hr-observability-layer-citation`: the registry host runs **no Vector**
(`grep -n vector apps/web-platform/infra/cloud-init-registry.yml` → no matches) and has no
SSH. Its observability layer is **cron + `doppler run --project soleur-registry --config prd`
+ `curl` POST → Better Stack Logs source 2457081**, read with
`scripts/betterstack-query.sh --grep <marker>`. ADR-096 rejected a journald interim
explicitly because journald needs SSH to read. This is why AC2's "journald → Vector
allowlist" does not apply here (R6).

```yaml
liveness_signal:
  what: "SOLEUR_ZOT_CONTROL heartbeat line proving the control listener is installed and answering, plus the existing 60s zot-liveness beat and 5-min SOLEUR_ZOT_DISK"
  cadence: "control-plane activation probe on the existing 5-min registry cron; SOLEUR_ZOT_RESTART on demand per fire"
  alert_target: "Better Stack Logs source 2457081; absence surfaced by the scheduled recurrence poller (the scripts/zot-restart-loop-alarm.sh pattern), not a native Better Stack alert (ADR-096)"
  configured_in: "apps/web-platform/infra/cloud-init-registry.yml (emitter); .github/workflows/restart-zot-registry.yml (assertion)"

error_reporting:
  destination: "SOLEUR_ZOT_RESTART action=<a> outcome=failed reason=<enumerated> to Better Stack Logs, AND ::error:: + non-zero exit in the workflow run"
  fail_loud: "yes — the workflow exits 1 on: non-202 from the hook; a status frame whose started_at predates the trigger floor; a fresh container that is not serving after the settle window; and poll-budget exhaustion. There is no exit path that reports success without a fresh-container assertion."

failure_modes:
  - mode: "hook returns 202 but the restart never runs (webhook accepted, script failed)"
    detection: "status poll never returns a container started_at at/after FRESH_FLOOR"
    alert_route: "workflow ::error:: + exit 1; SOLEUR_ZOT_RESTART outcome=failed"
  - mode: "container restarts, then immediately dies again (the crash-loop is unfixed)"
    detection: "post-settle re-read: fresh started_at present BUT zot not answering on the private IP, or restart_count advanced again during the settle window"
    alert_route: "workflow ::error:: + exit 1 with reason=restarted_but_not_serving"
  - mode: "recreate-zot runs against an unmounted store and serves an EMPTY registry"
    detection: "recreate-zot.sh re-asserts findmnt -no SOURCE /var/lib/zot | grep -qx /dev/mapper/registry BEFORE docker run and refuses otherwise; the status hook reports the mount source so the workflow asserts it too"
    alert_route: "script exits non-zero, hook status reports reason=store_not_mounted, workflow exits 1"
  - mode: "the lever is not installed on the live host (predates the provisioning event)"
    detection: "the ingress resolves but returns 502/404; the workflow maps this to a distinct, named verdict"
    alert_route: "::error:: reason=lever_not_activated — explicitly NOT reported as a restart failure"
  - mode: "CF Access token expired or rotated out of band (#7071 class)"
    detection: "403 at the edge; scripts/check-cloudflare-token-drift.sh with the new token registered"
    alert_route: "scheduled-terraform-drift.yml + release preflight"

logs:
  where: "Better Stack Logs source 2457081 (SOLEUR_ZOT_RESTART / SOLEUR_ZOT_CONTROL); GitHub Actions run log"
  retention: "per the existing Better Stack Logs source retention — unchanged by this plan"

discoverability_test:
  command: "doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 1h --grep SOLEUR_ZOT_RESTART"
  expected_output: "one SOLEUR_ZOT_RESTART line per fire carrying action=, outcome=, container_id=, started_at=, image_digest=, mount_source= — and zero lines when the lever has never been fired"
```

### The positive-control requirement (from learning `2026-08-04-my-probe-passed-against-the-outage-it-was-built-to-detect.md`)

The verification must measure something the **pre-restart** zot could not have produced.
`state_status=running` and a 200 on `/v2/` are both emitted by the crash-looping container
today, so neither can be the success signal. The success signal is the **container identity
and start time** — a new `container_id` with `started_at >= FRESH_FLOOR` is structurally
impossible for the old container to produce. That is the source of truth the workflow
asserts against, exactly mirroring `restart-inngest-server.yml`'s `FRESH_FLOOR` guard on
`start_ts`.

### zot `/v2/` returns 401 when healthy

The corroborating reachability probe must **not** use `curl -f` — zot's `/v2/` is
auth-gated and answers 401, which `curl -f` reports as failure (learning
`2026-07-16-the-fix-for-an-inert-monitor-shipped-a-probe-that-could-never-fire.md`).
Treat 200 **and** 401 as "serving"; treat connection-refused/timeout as "down".
Pin this contract in a comment where the probe is written.

---

## Encryption Posture

Detection fires: `.tf` files change and a **new cross-component connection** is introduced.
No new persistent store.

**Ledger task (verified shape).** `scripts/lint-encryption-posture.py` resolves this block
against `scripts/encryption-posture-ledger.json`, whose top-level keys are
`schema_version, live_coverage_floor, store_classes, non_store_types, non_iac_stores,
stores, connections`. The `cloudflare_zero_trust_access_*` and
`cloudflare_zero_trust_tunnel_cloudflared*` resource types are already listed under
`non_store_types`, so **no `stores` entry is required** for the new resources. What *is*
required is a fourth entry in `connections` (currently 3), using the exact existing schema:

```json
{
  "connection": "GitHub Actions -> registry-ctl.<base> -> zot control listener (10.0.1.30:9000)",
  "enforced_at": "apps/web-platform/infra/tunnel.tf (ingress_rule + Access policy); .github/workflows/restart-zot-registry.yml",
  "in_transit": {
    "tls": "TLS 1.2+ to the Cloudflare edge; plain HTTP on the private-net leg",
    "cert_verification": "on (public legs); n/a (private-net leg)",
    "does_not_defend": "a party holding both the HMAC secret and the CF Access service token; and a 10.0.1.0/24 foothold able to replay the private-net leg",
    "disclosed_as": "internal control-plane call; no user data"
  }
}
```

Run `python3 scripts/lint-encryption-posture.py` and require it to pass — do not hand-verify.

```yaml
at_rest:
  - store: "HMAC secret + CF Access client secret (new credentials, no new store)"
    mechanism: "Doppler-managed secret storage (soleur-registry/prd and soleur/prd), masked visibility; plus Terraform state on the R2 backend with SSE"
    evidence: "doppler_secret resources in zot-registry.tf / tunnel.tf with visibility = \"masked\"; R2 backend config in main.tf"
    defends_against: "at-rest disclosure of the control credentials from vendor storage or a state-file read"
    does_not_defend: "a compromised CI runner or a live Doppler token — both read the plaintext value by design"
    disclosed_as: "internal infrastructure credential; no user data"
    live_verification: "doppler secrets get <NAME> -p soleur-registry -c prd --plain returns the value the workflow authenticates with"

in_transit:
  - connection: "GitHub Actions runner → Cloudflare edge (registry-ctl.<base>)"
    tls: "TLS 1.2+ (Cloudflare edge)"
    cert_verification: "on"
    does_not_defend: "a party holding both the HMAC secret and the CF Access token — authentication, not transport, is the boundary"
    disclosed_as: "internal control-plane call"
  - connection: "Cloudflare edge → cloudflared connector"
    tls: "TLS (cloudflared tunnel transport)"
    cert_verification: "on"
    does_not_defend: "Cloudflare as a trusted intermediary (inherent to the tunnel architecture, already accepted for deploy./ssh./registry.)"
    disclosed_as: "internal control-plane call"
  - connection: "connector (web-1) → registry host 10.0.1.30:9000"
    tls: "none — plain HTTP over the Hetzner private network"
    cert_verification: "n/a"
    does_not_defend: "an attacker with a foothold on 10.0.1.0/24 can observe the request and replay it. The HMAC secret is never transmitted (the signature is over the body), so replay — not disclosure — is the exposure, and a replay can only re-fire an already-authorised restart."
    disclosed_as: "private-net internal call"

exception:
  - applies_to: "connector → registry host 10.0.1.30:9000 (plaintext-exception)"
    justification: "Mirrors the established and already-accepted posture for every private-net leg in this fleet: deploy. terminates at http://10.0.1.10:9000 and registry. at tcp://10.0.1.30:5000, both plain-HTTP by design (model.c4: 'Plain-HTTP on the private net (integrity via cosign digest-pinning, not TLS)'). Introducing TLS on this one leg alone would add a certificate lifecycle to a deny-all-public host that has no shell to repair it from — strictly worse for availability than the risk it removes."
    tracking_issue: "file at /work time — 'TLS or mTLS for private-net control-plane legs' covering deploy./registry./registry-ctl. together, since a per-leg fix is not coherent"
    reevaluate_when: "the private network gains a non-fleet tenant, OR any private-net leg begins carrying user data, OR a fleet-wide private-net mTLS story lands"
    expires_on: "2027-08-04"
```

---

## Implementation Phases

Ordering is dependency-directed, not file-grouped: contract-defining changes precede their
consumers.

### Phase 0 — Preconditions (verify, do not assume)

0.1 Re-derive the next-free ADR ordinal against freshly-fetched `origin/main`.
0.2 Confirm PR #7279 (the recut-runbook blocked-state banner) has not yet merged; if it
    has, rebase and confirm the pointer edit does not collide with its banner. **Do not
    edit the banner** either way.
0.3 Re-read the admitted-secret self-check cardinality in `cloud-init-registry.yml` and
    record the current value; the new secret changes it.
0.4 Probe the pinned `webhook` binary version/asset actually installed on web-1's path
    and reuse the identical acquisition method, rather than inventing one.
0.5 Re-pull `SOLEUR_ZOT_DISK` and record whether the store filled since planning — the
    activation story changes if the registry has hard-downed.

### Phase 0.5 — BLOCKING PREREQUISITE: get `user_data` back under the cap (R1)

Nothing else in this plan can be provisioned until this lands. **Do this first; if it cannot
be made to fit, stop and re-scope — the lever is undeliverable.**

1.0a Measure the baseline on the **substituted** render, not the raw file (the raw file
     measured 34,320 B against a 32,768 B cap on 2026-08-04).
1.0b Adopt the existing in-repo remedy: `apps/web-platform/infra/modules/git-data-userdata/`
     (rationale-strip; its own comment records comments were 61 % of the raw payload).
     Generalise or mirror it for the registry — do **not** hand-roll a second stripper.
1.0c Port the parity test (`git-data-render-strip-parity.test.sh`) so the stripped render is
     provably behaviour-identical to the unstripped one.
1.0d Assert `base64gzip` length `< 32768` **with margin**, since this plan then adds a webhook
     binary install, a hooks file, three scripts, a unit and an emitter on top.
1.0e **Surface to the operator independently:** this defect also blocks #7277, and it blocks
     *any* registry provisioning today. It is not caused by this PR.

### Phase 1 — Contract: the hook set and its scripts (RED first)

1.1 Write failing tests **before** implementation (`cq-write-failing-tests-before`):
    - `hooks.json` shape test: exactly three hooks; **every** hook's
      `pass-environment-to-command` is absent or empty (the AC3 structural guarantee);
      every hook carries the HMAC `trigger-rule` and
      `trigger-rule-mismatch-http-response-code: 403`; the two mutating hooks are async
      (`include-command-output-in-response: false`, `success-http-response-code: 202`).
    - `recreate-zot.sh` refuses when `/var/lib/zot` is not backed by `/dev/mapper/registry`.
    - `hcloud_firewall.registry` still has zero inbound rules.
1.2 Implement `restart-zot.sh`, `recreate-zot.sh`, `zot-status.sh` and the
    `SOLEUR_ZOT_RESTART` emitter. `recreate-zot.sh` pulls the pinned digest, `docker rm -f`,
    then re-runs the **exact** baked run-line (memory cap, journald log driver, volume
    mounts, `-p 0.0.0.0:5000:5000`) — never a hand-retyped variant.
1.3 Async-hook rationale comment: synchronous execution would exceed Cloudflare's ~120 s
    edge timeout and return 524 while the restart actually succeeded (learning
    `2026-03-21-async-webhook-deploy-cloudflare-timeout.md`).

### Phase 2 — Host half (cloud-init)

2.1 `zot-control.service` (hardened: `ProtectSystem=strict`, minimal `ReadWritePaths`,
    `Restart=on-failure`), `webhook` install, `hooks.json` render.
2.2 Update the admitted-secret cardinality self-check (Phase 0.3).
2.3 Non-fatal install guarantee + a cloud-init render test.

### Phase 3 — Edge half (Terraform)

3.1 `tunnel.tf` ingress rule (above the 404 catch-all) + Access app/token/policy.
3.2 `dns.tf` CNAME. 3.3 `zot-registry.tf` HMAC secret + `doppler_secret`s.
3.4 **Register the new token in `scripts/check-cloudflare-token-drift.sh`** (#7071 trap).
3.5 `terraform validate`; confirm the plan shows **no create/replace** of
    `hcloud_server.registry` or `hcloud_volume.registry`.

### Phase 4 — The workflow

4.1 `scripts/zot-restart-poll-classify.sh` — a **pure, unit-tested** per-frame classifier,
    mirroring `scripts/inngest-restart-poll-classify.sh`, plus
    `tests/scripts/test-zot-restart-poll-classify.sh`.
4.2 `.github/workflows/restart-zot-registry.yml` mirroring `restart-inngest-server.yml`:
    `workflow_dispatch` with a `choice` input (`restart-zot` | `recreate-zot`) selecting
    the **hook**; the `push`-registration trigger scoped to this file **with the
    `if: github.event_name == 'workflow_dispatch'` job guard** (#6425 — without it,
    editing the file on main restarts production as a side effect); `concurrency` group;
    `timeout-minutes` exceeding the poll budget.
4.3 `TRIGGER_TS` / `FRESH_FLOOR` freshness anchor; poll `zot-status`; settle-window
    re-read; the `lever_not_activated` verdict kept distinct from a restart failure.

### Phase 5 — ADR + C4

5.1 Write ADR-169. 5.2 Apply the four `model.c4` edits (including the R4/R5 corrections).
5.3 Run the C4 validation tests.

### Phase 6 — Runbook + triage pointers (AC4)

6.1 `knowledge-base/engineering/operations/runbooks/registry-luks-recut-6929.md` — add a
    "**try the restart lever first**" pointer near the top and an entry under `## Related`.
    **Do not touch the blocked-state banner** (PR #7279 owns it). The pointer must also
    carry the §Activation Sequencing constraint: *this recut is the lever's activation
    vehicle; confirm the lever's code is on `main` before firing.*
6.2 `scripts/zot-restart-loop-alarm.sh` — its remediation text currently routes to
    `registry-host-replace`. Re-point the crash-loop arm at the lever, with the
    not-yet-activated caveat. Cite content anchors, not line numbers
    (`cq-cite-content-anchor-not-line-number`); re-read before editing.
6.3 `knowledge-base/engineering/operations/runbooks/zot-registry-revert.md` — carries a
    STOP banner saying a zot problem "must be fixed as one"; add the lever as the how.
6.4 No SSH in any of these (`hr-no-ssh-fallback-in-runbooks`); no operator-executed steps.

### Phase 7 — Follow-through enrollment

The ADR ships `adopting` and flips to `accepted` only after a real fire is measured
post-activation. That is a time-gated close criterion, so per §2.9.1 enroll it:
`scripts/followthroughs/registry-restart-lever-7278.sh` + the
`<!-- soleur:followthrough script=… earliest=… secrets=… -->` directive + the
`follow-through` label. Its `earliest` cannot be a fixed date — it is
provisioning-gated — so the probe must exit non-zero-but-not-failing until
`SOLEUR_ZOT_CONTROL` first appears.

---

## Files to Create

- `knowledge-base/engineering/architecture/decisions/ADR-169-registry-host-control-plane-parameterless-allowlisted-lever.md`
- `.github/workflows/restart-zot-registry.yml`
- `scripts/zot-restart-poll-classify.sh`
- `tests/scripts/test-zot-restart-poll-classify.sh`
- `tests/scripts/test-registry-control-hooks-shape.sh`
- `scripts/followthroughs/registry-restart-lever-7278.sh`

## Files to Edit

- `apps/web-platform/infra/tunnel.tf`
- `apps/web-platform/infra/dns.tf`
- `apps/web-platform/infra/zot-registry.tf`
- `apps/web-platform/infra/cloud-init-registry.yml`
- `apps/web-platform/infra/modules/git-data-userdata/` — generalise the rationale-strip module for the registry (R1, blocking)
- `.github/workflows/scheduled-zot-restart-loop.yml` — the FIRE issue body is the responder's real first-read surface (R9)
- `scripts/check-cloudflare-token-drift.test.sh` — pin the new `access_hostname_for()` arm (R5)
- `.github/workflows/apply-web-platform-infra.yml` — **extend the `-target=` allowlist** with the four new resources (the ordering invariant above)
- `tests/scripts/test-destroy-guard-counter-web-platform.sh` — the counter test that pins the allowlist size/membership
- `.github/workflows/infra-validation.yml` — third artifact asserting on the `-target=` set
- `scripts/check-cloudflare-token-drift.sh`
- `scripts/encryption-posture-ledger.json` — the ledger `lint-encryption-posture.py` resolves the §Encryption Posture block against
- `scripts/zot-restart-loop-alarm.sh`
- `knowledge-base/engineering/architecture/diagrams/model.c4`
- `knowledge-base/engineering/operations/runbooks/registry-luks-recut-6929.md`
- `knowledge-base/engineering/operations/runbooks/zot-registry-revert.md`
- `.github/workflows/scheduled-followthrough-sweeper.yml` (only if a new `secrets=` is needed)

---

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 (capability).** A `workflow_dispatch` on `restart-zot-registry.yml` with
      `action=restart-zot` or `recreate-zot` reaches the registry host's control listener
      over the tunnel and restarts/recreates **only** the zot container — no host replace,
      no store recut, no shell anywhere in the path. Verified structurally at merge (see
      AC1a); verified end-to-end at activation (post-activation criteria below).
- [ ] **AC1a (delivery honesty).** The workflow distinguishes `lever_not_activated`
      (ingress resolves, nothing listening) from a restart failure, with distinct exit
      messages. `grep` the workflow for both verdict strings.
- [ ] **AC2 (fail-loud + telemetry) — REWRITTEN per R2.** The success contract is
      **"the loop stopped"**, not "something restarted". `started_at` alone is disqualified:
      `--restart unless-stopped` advances it every ~17 s, so a crash-looping zot satisfies any
      freshness floor. `container_id` alone is disqualified for `restart-zot`: `docker restart`
      reuses the container. The per-action contracts are therefore:
      - `restart-zot` → success iff, across a settle window, zot is **serving** AND
        `restart_count` is **stable** (did not advance). A `restart_count` that keeps climbing
        is the unfixed crash-loop and MUST classify `terminal_fail`.
      - `recreate-zot` → success iff `container_id` **differs** from the value captured at
        trigger time AND zot is serving AND `restart_count` is stable across the settle window.
      Both actions capture `{container_id, restart_count}` at trigger time (before the hook
      POST) and compare against the post-settle read — a delta, never an absolute.
      Verified by `tests/scripts/test-zot-restart-poll-classify.sh` with at minimum: a
      still-looping frame (`restart_count` advancing) → `terminal_fail`; a `restart-zot` frame
      with an unchanged `container_id` but stable counter + serving → `success`; a
      `recreate-zot` frame with an unchanged `container_id` → `terminal_fail`.
      Plus: `SOLEUR_ZOT_RESTART` is emitted on both outcomes, and
      `scripts/betterstack-query.sh --grep SOLEUR_ZOT_RESTART` is the documented read path
      (**no `ssh `** appears in any prescribed verification command).
- [ ] **AC3 (blast radius, structural) — REWRITTEN per R6/R7.**
      `tests/scripts/test-registry-control-hooks-shape.sh` asserts an **allowlist of permitted
      keys** per hook object — not the absence of three named ones. `adnanh/webhook` forwards
      caller input through **three** keys (`pass-environment-to-command`,
      `pass-arguments-to-command`, `pass-file-to-command`); v1's "zero
      `pass-environment-to-command`" was itself a reject-list of one, the exact failure mode
      the design claims to escape. The test asserts: exactly three hooks; every hook object's
      key set is a **subset of an explicit permitted-key allowlist** that contains **none** of
      the three forwarding keys; all three carry an HMAC `trigger-rule` with mismatch code 403.
      Separately, pin **both** that `hcloud_firewall.registry` declares zero inbound rules
      **and** that `hcloud_firewall_attachment.registry` still binds it to the host — a
      detached firewall is zero-rules *and* wide open, which the zero-rule assertion alone
      would pass while :9000 carries a root-equivalent listener.
- [ ] **AC4 (pointers).** `registry-luks-recut-6929.md` points at the lever as the first
      thing to try **and** states the activation-vehicle constraint;
      `zot-restart-loop-alarm.sh`'s crash-loop remediation names the lever;
      `zot-registry-revert.md` names it. `git diff` on `registry-luks-recut-6929.md` shows
      **no change** to the blocked-state banner owned by PR #7279.
- [ ] **AC5 (#7071 trap) — REWRITTEN per R5.** `scripts/check-cloudflare-token-drift.sh`
      deliberately holds **no** hardcoded token list ("A hardcoded list is exactly how
      CF_API_TOKEN_AUDIT was missed") — it enumerates from Doppler via
      `[A-Z0-9_]*ACCESS_TOKEN_(ID|SECRET)` and maps each to a hostname in the
      `access_hostname_for()` case arm, keyed on the **uppercase** Doppler key. So the AC is:
      an `access_hostname_for()` arm exists mapping `REGISTRY_CTL_ACCESS_TOKEN` →
      `registry-ctl.<base>`, pinned by a case in `scripts/check-cloudflare-token-drift.test.sh`.
      **This is merge-blocking in the strong sense:** an enumerated token with no mapping is
      reported UNVERIFIABLE and **fails the run**, so shipping the `doppler_secret` without the
      mapping turns the fleet-wide scheduled drift detector red. v1's
      `grep -c registry_ctl` was case-sensitive and could never have matched.
      Also run `scripts/followthroughs/token-drift-coverage-7159.sh` and require exit 0.
- [ ] **AC5a (ordering invariant — P0).** The four new Cloudflare resources are present in
      the `-target=` allowlist in `.github/workflows/apply-web-platform-infra.yml`, and the
      `terraform plan` output for the merge-apply target set shows
      `cloudflare_zero_trust_access_policy.registry_ctl_service_token` created **in the same
      plan as** the modified `cloudflare_zero_trust_tunnel_cloudflared_config.web`. A plan in
      which the ingress rule changes while the Access policy is absent must FAIL this AC —
      that state publishes an unprotected control hostname.
- [ ] **AC5b (allowlist guard sweep).** `tests/scripts/test-destroy-guard-counter-web-platform.sh`
      and `.github/workflows/infra-validation.yml` are updated consistently with the new
      allowlist membership, and the full `tests/scripts/` suite passes — the counter test is
      the one that fails last and loudest if the sweep was partial.
- [ ] **AC6 (no premature provisioning) — REWRITTEN per R3, and it must name its plan.**
      v1 said "`terraform plan` shows no replace" without naming which plan, which made it pass
      **vacuously**: the registry is excluded from the CI `-target` set, so the CI plan cannot
      show a registry replace no matter what. The real state is the opposite of what v1 implied.
      Split into two assertions:
      - **AC6a.** The **CI-targeted** plan (the merge-apply `-target` set) shows no create,
        replace or destroy of `hcloud_server.registry` or `hcloud_volume.registry`.
      - **AC6b (the landmine disclosure).** Because `hcloud_server.registry` carries
        *"Deliberately NO lifecycle.ignore_changes=[user_data]"* and `user_data` is ForceNew,
        editing `cloud-init-registry.yml` leaves a **pending REPLACE** visible in any
        **untargeted** plan — which against today's plaintext volume would take the registry
        permanently dark. Assert that (i) this is stated explicitly in the ADR and in a
        comment at the cloud-init edit site, (ii) **no untargeted apply is prescribed anywhere**
        in this change or its runbook edits, and (iii) the recut runbook pointer warns that the
        documented operator-local full apply is now a registry-killing operation until the
        volume is LUKS.
- [ ] **AC7 (ADR/C4).** ADR-169 exists (ordinal re-derived at ship) and records the R1
      refutation, the root-equivalence disclosure, and all four rejected alternatives.
      `model.c4` says four ingress rules, carries the control edge, and no longer claims
      cx33/8 GB or an unorderable type. C4 validation tests pass.
- [ ] **AC8 (safety of recreate).** `recreate-zot.sh` re-asserts the `findmnt` mount gate
      before `docker run` and refuses otherwise — asserted by a unit test that feeds it a
      non-mapper mount source.
- [ ] **AC9 (fully automated).** Every provisioning step is a Terraform resource or
      cloud-init. The HMAC secret is `random_password`; no no-default TF variable is
      introduced; no step requires a human to execute a command.
- [ ] **AC10 (self-restart guard).** The workflow's `push` registration trigger cannot fire
      the op: the job carries `if: github.event_name == 'workflow_dispatch'`.
- [ ] **AC14 (R1 — user_data under the cap).** After the rationale-strip module is applied,
      the rendered payload is under Hetzner's 32,768-byte cap **with margin**, measured on the
      substituted template, not the raw file. Assert via a parity/size test mirroring
      `git-data-render-strip-parity.test.sh`: the stripped render must be byte-identical in
      *behaviour* to the unstripped one and `base64gzip` length must be `< 32768`. Record the
      before/after numbers in the PR body (baseline measured 2026-08-04: **34,320**).
      **This AC gates every other host-half AC** — without it nothing can be provisioned.
- [ ] **AC15 (R4 — boot self-check is order-independent).** The admitted-secret self-check
      accepts **both** cardinalities during the transition (`n_total ∈ {4,5}` with the 5th
      admitted **by name**), so the `doppler_secret` and the cloud-init edit may land in either
      order without a boot-fatal window. Asserted by a unit test feeding the self-check both a
      4-secret and a 5-secret config. If the reviewer-preferred simplification is taken instead
      (drop the HMAC secret; rely on the CF Access service token alone), record that decision
      in the ADR with its defense-in-depth trade-off — do **not** leave a single-cardinality
      assertion that only one apply order can satisfy.
- [ ] **AC16 (R10 — the dead end has an exit).** The `lever_not_activated` message names the
      escalation path in its text: the recut dispatch as the activation vehicle, #7277 as its
      blocker, and #7247 for the live crash-loop/disk-exhaustion. Asserted by a test on the
      message string, not by a comment. A verdict that tells the responder only "not activated"
      makes the incident path worse than today's.
- [ ] **AC17 (R9 — the responder's real first-read surface).** The FIRE issue body composed in
      `.github/workflows/scheduled-zot-restart-loop.yml` names the lever. The
      `zot-restart-loop-alarm.sh` edit touches **only** the crash-loop arm; `git diff` shows
      **no change** to any `NIC_CAUSE` arm (a private-NIC fault is a different failure class
      that a container restart cannot fix — re-pointing it would be actively harmful).
- [ ] **AC18 (R8 — credential co-residence).** The registry-ctl Access token is **not** written
      to the `soleur/prd` root config (which the release workflow token reads); assert its
      Doppler `config` is the scoped one, so a release run cannot fire `recreate-zot`.

### Post-activation (fires at the next registry-host provisioning event — tracked by the Phase 7 follow-through, not a merge blocker)

- [ ] **AC11.** `SOLEUR_ZOT_CONTROL` appears in Better Stack, proving the listener installed.
- [ ] **AC12.** One real `restart-zot` fire returns a fresh `container_id` and a green run.
- [ ] **AC13.** ADR-169 status flips `adopting` → `accepted`.

---

## Domain Review

**Domains relevant:** Engineering (infrastructure, security)

### Engineering

**Status:** reviewed (planner assessment; `architecture-strategist` requested at deepen-plan)
**Assessment:** New remotely-triggerable control surface on a production host. The security
question is not the transport (HMAC + CF Access mirrors three existing accepted surfaces)
but the **root-equivalence of Docker socket access**, which the ADR must disclose rather
than obscure. The mitigation is the absence of an input surface, not the absence of
privilege. Delivery sequencing is the dominant engineering risk and is treated explicitly.

### Product/UX Gate

Not applicable — no UI surface. No file in `## Files to Create` or `## Files to Edit`
matches a UI-surface glob (`components/**/*.tsx`, `app/**/page.tsx`, `app/**/layout.tsx`).
Product domain not relevant; mechanical override did not fire.

---

## Open Code-Review Overlap

None. No open `code-review`-labelled issue body names any path in
`## Files to Edit` / `## Files to Create`.

---

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| **The store fills before this lands** and the registry hard-downs. | Out of this plan's scope and control; belongs to #7247 and is surfaced to the operator now. Noted that a full store paradoxically unblocks the recut, which is this lever's activation vehicle. |
| **The lever ships and is never activated** because the recut keeps slipping. | The activation state is *measured* (`SOLEUR_ZOT_CONTROL`), never assumed; the Phase 7 follow-through keeps it visible instead of letting it rot silently. |
| **The recut fires before this merges**, wasting the provisioning window. | Phase 6.1 writes the constraint into the recut runbook itself, where the person firing it will read it. |
| **`recreate-zot` serves an empty store** — the worst outcome in this plan. | Mount gate re-asserted in the script *and* re-asserted by the workflow against the status hook's `mount_source`. Two independent checks because the single-check version is the #7071/2026-08-03 failure shape. |
| **New token silently goes stale** (#7071). | AC5 — drift-check registration is a merge blocker, not a nicety. |
| **The listener install breaks a future reprovisioning.** | Non-fatal-to-boot requirement (Phase 2.3) — the control plane may never be the reason the data plane stays dark. |
| **Docker socket access is root-equivalent.** | Disclosed in the ADR; mitigated by zero forwarded parameters and baked, immutable scripts. Accepted, not hidden. |

---

## Non-Goals / Out of Scope

- **Diagnosing or fixing the crash-loop itself** (#7247). This plan builds the lever; H2/H3/H4 stay UNKNOWN.
- **The D10 recut gate and its `ghcr-fallback` operand** (#7277) — explicitly untouched.
- **The recut runbook's blocked-state banner** — PR #7279 owns it.
- **Store disk-exhaustion remediation** — surfaced, not solved, here.
- **TLS on private-net legs** — tracked by the Encryption Posture exception.
- Cache-clearing or other destructive zot actions — deliberately excluded from the action set to keep the blast radius at two mutating verbs.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. It is filled above.
- The ADR ordinal here is **provisional**. If it moves, sweep this plan, `tasks.md`, and AC7 in the same edit — a renumber that reaches only the ADR file leaves an AC asserting a nonexistent path.
- `docker restart` does **not** apply a newly pulled image. `restart-zot` and `recreate-zot` are not interchangeable, and the runbook must not present them as such.
- zot's `/v2/` answers **401 when healthy**. Any corroborating probe using `curl -f` will read a healthy registry as down.
- The plan's own prohibitive phrasing trips `.claude/hooks/iac-plan-write-guard.sh`; the `iac-routing-ack` comment at the top is the sanctioned opt-out and must survive edits to this file.
