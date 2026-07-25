---
title: One tunnel, many connectors — tunnel ingress must be origin-relative, not connector-relative
status: accepted
date: 2026-07-15
amends: [ADR-008, ADR-068]
supersedes: none
issue: 6416
related: [6400, 6122, 6288, 6357, 6440, 6441, 6442, 6443]
related_adrs: [ADR-008, ADR-068, ADR-096]
---

# ADR-114: One tunnel, many connectors — tunnel ingress must be origin-relative, not connector-relative

## Context

#6416 reported that `soleur-web-2` had no private-network IP, so the Cloudflare tunnel
origin could not reach the zot registry at `10.0.1.30:5000`, and CI's zot mirror silently
skipped on every release.

The operator asked a sharper question alongside it:

> *"Why do we have a tunnel for each backend instead of a tunnel that allows to reach any
> backend?"*

**The premise is inverted, and answering it is the point of this ADR.** We do not have a
tunnel per backend. We have exactly one — and one is correct. What was broken is subtler
and is what this ADR names.

### Measured, not assumed

| Claim | Evidence |
|---|---|
| There is exactly ONE tunnel | `git grep 'resource "cloudflare_zero_trust_tunnel_cloudflared"' -- '*.tf'` → **1** (`tunnel.tf:10`) |
| It carries THREE ingress rules | `deploy.` → `http://localhost:9000`, `ssh.` → `ssh://localhost:22`, `registry.` → `tcp://10.0.1.30:5000` |
| It has MULTIPLE connector replicas | CF API: tunnel `soleur-web-platform` healthy, **2 connectors / 8 QUIC connections** (cloudflared opens 4 per replica) |
| No cloudflared on git-data / zot / inngest | ADR-096 §Decision: *"no cloudflared on the registry host"* |
| web-2 had no private-net attachment | `hcloud server describe soleur-web-2 -o json \| jq '.private_net'` → `[]`; web-1 → `10.0.1.10` |

What *is* per-backend is the **(hostname + CF Access app + service token + CI bridge action)**
quadruple. That is deliberate least-privilege, not accident — `tunnel.tf`'s `registry_push` service-token block gives the
registry its own token *"so registry-write access rotates/revokes independently of host-shell
+ webhook access"*. **That layering is correct and stays.**

### Observed blast radius — measured, and it refutes BOTH models

The two-connector model predicts the `registry.` ingress fails ~50% of the time (the share of
requests landing on the unattached web-2). Measured across the 16 most recent completed
`web-platform-release.yml` runs that actually built an image:

| bridge step `conclusion` | mirror step | count |
|---|---|---|
| `success` (forced by `continue-on-error`) | **skipped** (bridge truly failed) | **15** |
| `success` | `success` (bridge truly succeeded) | **1** |

**≈94% failure — neither ~50% nor 100%.** The bridge's real error, from a failing job log:

```
Error response from daemon: Get "http://127.0.0.1:5000/v2/": context deadline exceeded
```

cloudflared's local forward opened; the connector that answered had no route to
`10.0.1.30:5000`. zot has been backfilled at most once in this window — every other deploy
silently fell through to GHCR, so the ADR-096 zot-primary path was effectively dead while
reporting green.

> **Correction, recorded deliberately.** An earlier revision of this ADR asserted *"the
> measured rate is 100%"* and inferred that something **pins** `registry.` to one replica. A
> later run succeeded, which **falsifies pinning outright** — a route pinned to a
> route-less connector can never succeed. The reviewer who re-ran the measurement caught it.
> This is the same defect the ADR warns about one section up: a rate quoted from a snapshot is
> a claim with a timestamp, not a fact. Do not re-quote 100%.

Three things this settles, and one it does not:

- **The masking is total, not partial.** `continue-on-error` forces the bridge's `conclusion`
  to `success`; the mirror's `if: steps.zot_bridge.outcome == 'success'` then skips it; a
  skipped step emits nothing, so `mirror_status` stays unset and the Slack degraded line —
  which reads that output *by step id* — stays inert. Every layer that could have reported the
  failure was, by construction, silent.
- **The step `conclusion` field is unusable as evidence here.** Any probe or alert reading it
  is reading a value the platform is contractually obliged to falsify. Read `outcome`.
- **The route is NOT pinned**, so I1 (connector homogeneity) is exactly the right frame: both
  replicas serve, and one of them cannot honor the rule.
- **It does NOT settle the ~94% skew.** 15-of-16 under a fair 50/50 is ~0.03% likely, so
  selection is heavily biased toward the unattached replica — but not absolute. The mechanism
  is unexplained, and it matters for I2 candidate (b) (which assumes a connector can be
  removed from rotation predictably). Tracked as an open question on #6441 rather than guessed
  at here.

### The actual defect

Cloudflare binds ingress to a **tunnel**, then load-balances across that tunnel's **connector
replicas**. That is the contract, not a defect. The defect is narrower:

> **`localhost:` in a multi-replica tunnel is a category error.** It does not mean *"this
> host"*. It means *"whichever replica answers."*

| Route (leg) | Service | Host-agnostic? | Status |
|---|---|---|---|
| `registry.` | `tcp://10.0.1.30:5000` | **Yes** — if every replica is a private-net member | **Already the correct pattern.** Only homogeneity was missing (#6416) |
| `deploy.` — **trigger** (`/hooks/deploy`) | `http://localhost:9000` | Yes — ADR-068 Option B fans out to peers over the private net | Solved |
| `deploy.` — **status** (`/hooks/deploy-status`) | `http://localhost:9000` | **No** — host-local by design | Known; read-only |
| `deploy.` — **infra-config** (`/hooks/infra-config`) | `http://localhost:9000` | **No — and no fan-out** | **Unguarded.** See below |
| `ssh.` | `ssh://localhost:22` | **No — fundamentally host-specific** | The open problem (I2) |

> **The `infra-config` leg is a third `deploy.` surface, and it is the one with the largest
> blast radius.** `terraform_data.deploy_pipeline_fix` runs `local-exec` →
> `push-infra-config.sh`, which POSTs to `https://deploy.<base>/hooks/infra-config` → the
> tunnel → **whichever replica answers** → that replica's `http://localhost:9000` →
> `infra-config-apply.sh`, which writes on **that host only**. Measured: `/hooks/deploy` passes
> `SOLEUR_DEPLOY_PEERS` (2 references in `hooks.json.tmpl`); `/hooks/infra-config` passes
> **zero**, and `infra-config-apply.sh` contains no peer/fan-out/`10.0.1` reference at all. It
> returns 202, Terraform records success, and the intended host can keep stale scripts —
> `ci-deploy.sh`, `hooks.json`, `webhook.service` and ~12 more.
>
> This is exactly the defect I2 names, and it was missed at plan time because the enumeration
> discriminated on *"has a `connection {}` block"* (i.e. "is it SSH?") rather than on I2's own
> test: **does correctness depend on which host answers?** `deploy_pipeline_fix` has no
> `connection {}`, so it fell out of the SSH-shaped sweep while being fully exposed. Surfaced by
> `architecture-strategist` at review. The cheapest fix mirrors ADR-068 Option B — fan out
> `/hooks/infra-config` to peers as `ci-deploy.sh` already does, needing no `.tf` and no tunnel
> change. Scoped into #6441; #6440's audit is widened to the files this leg writes.

The `registry.` rule is the pattern to generalize: **private-net-relative**, so whichever
replica answers proxies to the *right* origin. It did not fail because it was wrong; it
failed because a connector existed that could not honor it.

### Prior art — ADR-068 already knew

`ADR-068:354-357` states the multi-connector fact verbatim: *"both hosts run cloudflared on
that ONE tunnel, so a POST load-balances to ONE connector non-deterministically."* It chose
Option B (private-net fan-out) and **explicitly REJECTED per-host tunnels** (`:378-384`):
`for_each`-ing `cloudflared.web` risks **replacing the live tunnel** (`config_src` forces
replacement) — a deploy-path outage.

**This ADR cites that rejection rather than re-deciding it.** The real gap in ADR-068 is
narrower: it solved connector nondeterminism **for the deploy path only** and never
generalized to `ssh.` / `registry.`. That generalization is what ADR-114 records.

## Decision

**Keep one tunnel.** Per-backend tunnels are rejected — they multiply tokens, Access apps,
DNS records and cloudflared instances, **and do not solve determinism** (see Alternatives).

Three normative rules:

### I1 — Connector homogeneity (a RUNTIME precondition)

> A host MUST NOT serve as a tunnel connector unless it can serve **every** ingress rule —
> concretely, its private NIC is up.

**I1 is stated as a runtime precondition, deliberately.** The tempting construction-time form
— *"private-net attach is a precondition of holding the tunnel token"* — is **falsified by
construction**: `server.tf:158` passes `tunnel_token` via cloud-init `user_data` at server
**create**, while `hcloud_server_network.web` cannot exist until `hcloud_server.web[k].id`
does. **The attach ALWAYS lands after the token.** Every fresh host boots cloudflared and
registers *before* its private NIC exists — the same race `cloud-init.yml:445` notes for
`insecure-registries`.

Enforcement is therefore a runtime gate (cloud-init must block `cloudflared service install`
until the NIC is up, with a bounded boot window). **Not shipped in #6416; no phase of that PR
claims to enforce I1.** It is candidate (b) under I2 below, tracked in #6441.

### I2 — Ingress services MUST be origin-relative for any host-specific route

> An ingress `service` MUST address the origin by its private-net address (`10.0.1.x`) for
> any route whose correctness depends on *which host* answers. `localhost:` is permitted
> **only** for genuinely host-agnostic routes.

### Anti-pattern (normative)

> **Per-hostname ingress DOES NOT pin a connector.** The hostname selects the *tunnel*; CF
> then load-balances across replicas. An `ssh-web-1.` hostname pointed at `ssh://localhost:22`
> is a **no-op** — it changes nothing.

If a "route to a specific host" fix does not change the ingress **service** address, it
changes nothing.

## Consequences

**Positive.** The one-tunnel design is affirmed with its failure mode named. `registry.` is
recognized as the correct pattern rather than a lucky one. #6416's guard (`host_creates`) and
tripwire (in-band `hostname` assertion) are anchored to a stated invariant instead of folklore.

**Negative / accepted.** *(AMENDED 2026-07-15 by #6425 — I1 is now ENFORCED via the single-connector gate; I2 remains violated-but-inert. See the amendment below. The text as originally written follows.)* I1 and I2 are **recorded but not enforced** here. `ssh.` remains
host-nondeterministic across two connectors; the in-band `hostname` assertion converts that
from a silent wrong-host write into a loud apply failure, which is a strict improvement but
not a fix. Tracked in #6441; the audit of what may already have been written to the wrong host is #6440.

**Load-bearing constraint for any I2 implementation.** Do **NOT** repoint the 12
`terraform_data.*` `connection { host }` blocks to `10.0.1.10`. They dial web-1's **public**
IP by design: `.github/actions/cf-tunnel-ssh-bridge/action.yml:165` sets
`SERVER_IP=$(terraform output -raw server_ip)` (public by contract, `outputs.tf:1-4`) and
`:208-210` installs `iptables -t nat -A OUTPUT -d "$SERVER_IP" --dport 22 -j REDIRECT`. The
provisioners work *because* they dial that public IP and the kernel hijacks it. Repointing to
RFC1918 stops the NAT rule matching, the runner blackholes, and **every provisioner dies** —
and those 12 are `-target`ed by the per-PR merge apply, so main wedges.

> **Amendment (2026-07-15, #6425 — candidate (b) shipped; I1 is now ENFORCED).**
> The "recorded but not enforced" status above and the candidate assessment below are
> **superseded**. #6425 shipped **candidate (b)**, the single-connector gate:
> `server.tf`'s `web_tunnel_connector = each.key == "web-1"` gates `cloudflared service
> install`, so only the designated ingress host registers a connector. Read this ADR's
> Consequences with that in mind — ADR-068's amendment delegates the invariant *here*, so the
> two documents contradicted each other until this note existed.
>
> **What changed, precisely:**
> - **I1 is enforced**, and substantively rather than vacuously: web-1 *is* a connector and
>   *can* serve every ingress rule. The gate eliminates the risky population — a fresh host
>   that boots `cloudflared` before its private NIC exists (the token rides `user_data` at
>   create; the network attach always lands after). That race is unfixable at construction
>   time, which is why (b) was called "the only shape that makes I1 well-formed".
> - **I2 is NOT satisfied — it is made inert.** `ssh://localhost:22` and
>   `http://localhost:9000` are unchanged and still connector-relative, so I2's antecedent
>   still fires. They are not "genuinely host-agnostic routes"; they are routes only one host
>   can currently answer. **I2's violation is latent, gated behind I1 holding.** Anything that
>   re-pools a second connector re-manifests it immediately.
> - The normative anti-pattern below **stands**: a per-hostname ingress does not pin a
>   connector, and the 12 `connection { host }` blocks must not be repointed.
>
> **The un-taken complement (worth filing against #6466).** Candidate (a) was disfavoured for
> needing the `-d "$SERVER_IP"` NAT rework — but that rework is forced by per-host *hostname*
> multiplexing (`ssh-web-1.` needs its own bridge, port and NAT rule), **not** by an
> RFC1918 service address. Keeping ONE hostname and repointing the ingress *service* to
> `10.0.1.x` touches nothing client-side: the runner still dials the public `SERVER_IP`, the
> NAT still matches, cloudflared simply dials the private address instead of `localhost`.
> That is the pattern `tunnel.tf` already calls "the RIGHT pattern and the one to generalize"
> for `registry.`. It is not a replacement for de-pooling — origin-relative ingress *depends*
> on I1 (#6416 broke `registry.` exactly this way) — it is the complement that would make
> determinism survive connector count **structurally**, and would restore the availability
> #6425 trades away. Today the only thing between a GA re-pool and a #6425 recurrence is this
> ADR plus the `*/15` census alarm.
>
> **Standing enforcement:** `scripts/tunnel-connector-census.sh` + the `connector_census` job
> in `scheduled-inngest-health.yml` file an `action-required` issue whenever the live
> connector count leaves 1. Vantage-independent — a response-poll cannot detect a second
> connector, because selection is colo-sticky.

> **Amendment (2026-07-17, #6594 — I2's antecedent discharged for `deploy.` + `ssh.`; the in-band `hostname` tripwire is MEASURED FALSE; the fan-out recommendation is rebutted).**
> #6594 surfaced the `infra-config` leg failing exactly as the "third `deploy.` surface" note
> above predicted: the verify gate reported 15/15 success while #6577's `ci-deploy.sh` never
> reached the host. Diagnosis and fix produced three corrections to the text above.
>
> **1 — HEADLINE: the in-band `hostname` tripwire does not exist.** The Consequences section
> credits #6416 with a *"tripwire (in-band `hostname` assertion)"* that "converts a silent
> wrong-host write into a loud apply failure", and `ADR-068:413` states *"Each of the 12 now
> carries an in-band `hostname` tripwire (#6416)"*. **Measured false, 2026-07-17:**
> `grep -rnE 'hostnamectl|/etc/hostname|uname -n|\$\(hostname\)' apps/web-platform/infra/*.tf`
> returns exactly one hit — a *comment* at `server.tf`'s `fail2ban`/keep-inline note reading
> "NOT runtime `$(hostname)`" — and **zero** host-identity assertions in any of `server.tf`'s
> 12 `connection {}` provisioner inlines. The safeguard that "loud apply failure" leaned on was
> never shipped. This is the most consequential of the plan's meta-defect instances (a control
> recorded as enforced that is inert): with no tripwire, a wrong-host bridge landing writes
> web-1's config to web-2 *silently*. `ADR-068:413` and #6440's "safe to run" both carry this
> false enforcement claim and should be corrected.
>
> **2 — I1 is inert on the running fleet, not enforced.** The 2026-07-15 amendment says "I1 is
> enforced" via the `web_tunnel_connector` gate. That gate lives at **cloud-init create-time
> `user_data` only**, and `hcloud_server.web` carries `ignore_changes = [user_data]`, so
> cloud-init never re-runs on an already-booted host. web-2 booted 2026-07-13; the gate merged
> 2026-07-15 (#6425). So the gate governs *future* fresh hosts, not the fleet that exists — I1
> is a construction-time gate presented as a runtime precondition, and `model.c4`'s
> *"INVARIANT (ADR-114 I1, enforced #6425)"* is false in production. This is precisely the
> license #6594's fix needed.
>
> **3 — I2's antecedent is now discharged for `deploy.` AND `ssh.` (the "un-taken complement",
> taken).** PR-A (#6595) repointed the `deploy.` and `ssh.` ingress *services* to
> `http://${web-1.private_ip}:9000` / `ssh://${web-1.private_ip}:22` — the exact move the
> 2026-07-15 amendment named as the complement that "would make determinism survive connector
> count **structurally**" and "restore the availability #6425 trades away". All three routes
> (`deploy.`, `ssh.`, `registry.`) are now origin-relative; the anti-pattern still stands for
> anyone tempted to fix host-routing by changing the *hostname* rather than the *service*.
> Applied and verified on prod 2026-07-17 (CF-API config read-back + `/hooks/deploy-status`
> data-plane probe). PR-B then closed the observability half: a content assert
> (`infra-config-gate.sh`) that compares each delivered file's sha256 against the applied
> commit, so a stale-but-same-count host fails loud — the safeguard item 1 shows was missing.
>
> **Rebuttal of the fan-out recommendation.** The "third `deploy.` surface" note above
> recommends: *"The cheapest fix mirrors ADR-068 Option B — fan out `/hooks/infra-config` to
> peers as `ci-deploy.sh` already does, needing no `.tf` and no tunnel change."* PR-B did **not**
> take that path, for reasons that outlive #6594:
> - **Fan-out cannot discharge I2 at all.** I2 governs the ingress `service` address; fan-out
>   operates at the application layer and would leave `http://localhost:9000` in place, so the
>   READ side (`/hooks/deploy-status`, `/hooks/infra-config-status`, `inngest-liveness`) stays
>   coin-flipped. The verify gate self-verifies a coin-flipped WRITE against a *separately*
>   coin-flipped READ — fan-out patches one leg of the WRITE and leaves the READ untouched.
> - **Fan-out presumes web-2 should be converged.** Writing web-1's config to every peer
>   assumes the peer is a legitimate destination — exactly #6440's open question (whether a
>   coin-flipped push already wrote to a host that should not hold that config). Origin-relative
>   ingress makes the destination deterministic instead of multiplying it.
>
> So fan-out is not "the cheapest fix"; it is a different, narrower fix for a different problem
> (application-level replication), and it does not close the transport-layer determinism gap I2
> exists to name.

> **Amendment (2026-07-19, #6441 — I1's runtime gate SHIPS for first boot; the three prior
> status statements are reconciled; the blast-radius claim is corrected).**
>
> **1 — Reconciling the three statements about I1's status.** This ADR has said three
> different things, each true of a different thing, which is why they read as contradictory:
>
> | Statement | Where | Verdict |
> |---|---|---|
> | *"Not shipped in #6416"* | original text, above | **True and unchanged.** #6416 shipped no I1 enforcement. |
> | *"I1 is now ENFORCED via the single-connector gate"* | 2026-07-15, #6425 | **Overstated.** #6425 gated *which host may register* — it reduced the POPULATION that can violate I1. It never added the NIC wait, so a gated-in host still registered NIC-less. |
> | *"I1 is inert on the running fleet"* | 2026-07-17, #6594 | **True, and still true after this PR.** `ignore_changes = [user_data]` means cloud-init never re-runs on a booted host. |
>
> The reconciliation: I1 has two halves. **Which host** may register (shipped #6425) and
> **when** it may register (shipped here). Neither is retroactive to a running host.
>
> **2 — What #6441 ships: a first-boot NIC gate.** A baked `soleur-wait-nic` helper, invoked
> bare in `runcmd` immediately before `cloudflared service install`, inside the existing
> `web_tunnel_connector` block. It waits up to 60 s for the host's expected private address
> (single-sourced from `var.web_hosts`), then **defers and continues** — it never aborts and
> never reboots. Three mutually-exclusive arms emit exactly one Sentry boot-stage event:
> `private_nic_ready` / `private_nic_timeout` / `private_nic_probe_fault`. The third exists
> because an unresolvable `ip` binary is *zero evidence*, and must never be recorded as
> evidence of absence (the #6415 mislabel).
>
> This is a **first-boot** gate, not the runtime precondition I1 is worded as. That gap is
> deliberate and is item 4 below.
>
> **3 — The blast-radius claim in this ADR's own trade analysis is STALE.** The inherited
> framing held that a NIC-less connector breaks only the `registry.` route while `deploy.`
> and `ssh.` stay up. Post-#6594 that is false: item 3 of the 2026-07-17 amendment repointed
> **all three** ingress services to private-net literals (`tunnel.tf` — `deploy.` →
> `http://10.0.1.10:9000`, `ssh.` → `ssh://10.0.1.10:22`, `registry.` → `tcp://10.0.1.30:5000`).
> A connector without its private NIC therefore serves **nothing**, not one route. The fix
> that discharged I2 widened I1's blast radius — worth stating plainly, because it means the
> two invariants are more coupled than either amendment implied.
>
> **4 — The runtime arm (`ExecStartPre`) is REJECTED for now, not tracked as an open item.**
> `ExecStartPre` is the shape that best matches I1's runtime wording, and is the long-term
> preference on record from engineering review. It is rejected here on three grounds:
> - **It puts the wait inside systemd's start timeout.** `TimeoutStartSec` (default 90 s) spans
>   `ExecStartPre` **plus** `ExecStart` combined, so a 60 s NIC wait leaves ~30 s for the rest of
>   activation, and any later increase to the wait silently converts this gate into a
>   `systemctl start` failure. The runcmd shape has no such ceiling.
>
>   > **[Corrected at review.]** This bullet originally argued that an `ExecStartPre` would
>   > consume the downstream `cloudflared_ready` gate's ~60 s budget and detonate its live
>   > `|| exit 1`, because the unit sits in `activating` and `systemctl is-active --quiet`
>   > returns false throughout. The premise is true; **the conclusion does not follow.**
>   > `cloudflared service install` runs `systemctl start`, which blocks on the job by default,
>   > so a long `ExecStartPre` delays the *install command itself* — `soleur-wait-ready` does
>   > not begin polling until activation has already resolved, and gets its full budget. The two
>   > budgets are sequential under either shape. The rejection stands on the two grounds below,
>   > each independently sufficient, plus the `TimeoutStartSec` ceiling above, which is the
>   > argument the original bullet should have made. Recorded rather than silently rewritten
>   > because the wrong version was load-bearing in a commit message and a code comment.
> - **Making it safe means re-tuning a fail-closed gate** currently pinned by an exact-string
>   test assertion — coupling a low-risk fix to a change that can dark the sole origin.
> - **Its value is smaller than assumed.** cloudflared dials its ingress origin **per
>   connection**, not at process start, so a connector that registered NIC-less begins serving
>   the instant the attach lands. A NIC-less connector is a *converging* state, not a stuck
>   one. The already-running case is separately covered by `web-private-nic-guard.timer`.
>
> Because the state converges on its own, this is a rejection rather than a deferral — the ADR
> cannot call the state self-healing and simultaneously hold an open item to fix it. **Revival
> condition:** evidence that per-connection origin resolution is false, or an owner for the
> `cloudflared_ready` budget. If revived, an `ExecStartPre=-` (leading dash), a wait bound
> under 45 s, and an explicit `TimeoutStartSec=` pin are mandatory.
>
> **5 — A delivery-channel hazard, recorded because it is not obvious from the code.**
> `soleur-host-bootstrap.sh` feeds `local.host_scripts_content_hash`, which is injected into
> `user_data` and re-verified at boot under `set -e`. So editing the bootstrap script couples
> the change to image-bake sequencing: a host created after the apply but before `:latest`
> carries the matching bootstrap aborts its entire runcmd at `stage=verify`.
>
> **[Scope corrected 2026-07-20, #6575 — the hazard survives; only its scope statement changes.]**
> This bullet previously said the coherence preflight covered **only** the web-2-recreate dispatch.
> That scoping is gone with the dispatch job. The verifier is retained, renamed host-agnostic
> (`host-image-coherence-preflight.sh`, comparison logic byte-unchanged), and is reachable by any
> host through a documented operator procedure: the `host_creates` HALT runbook now carries the
> complete `crane digest` → preflight → `terraform apply -var image_name=<pinned>` chain. So the
> preflight is no longer web-2-scoped and no longer callerless.
>
> **What did not change is the hazard itself.** The verifier still requires a pinned `@sha256` ref
> while the default `var.image_name` is the mutable `:latest`, so the routine merge apply is still
> not coherence-verified. ADR-128 names this the **cross-commit skew** invariant and records that no
> build-time artifact can observe it; it is open under **#6712** and closable only by **#6730**'s
> digest-pinned birth path. The separable half — that the image's baked host-scripts match the tree
> it was built from — is *build-integrity*, and is statically enforced in
> `cloud-init-user-data-size.test.ts`.
>
> For the routine merge apply this is a non-issue, but **not** for the reason an earlier draft
> of this amendment gave. That draft argued: *"`hcloud_server.web["web-1"]` appears in no
> `-target=`, so the workflow cannot create or replace it."* **The inference is invalid.**
> `-target` is transitive at the resource level — the workflow states this in its own comments —
> so `cloudflare_record.app` and `hcloud_firewall_attachment.web` each pull the whole
> `hcloud_server.web` for_each map into the plan graph. web-1 **is** target-reachable there.
>
> What actually prevents a birth is the **`host_creates > 0` HALT tripwire** in the `apply` job,
> added by #6416 — whose error text reads *"the host would come up with no private-net IP … the
> #6416 failure mode"*, i.e. precisely the condition this NIC gate mitigates. The two facts now
> pinned by test are therefore: `hcloud_server.web` carries `ignore_changes = [user_data, …]`
> (the edit is inert for the running host), and that tripwire exists and parses its counter from
> the plan. The superseded assertion would have stayed green with the tripwire deleted.
>
> **A pre-existing gap this surfaced, not closed here:** the `warm_standby` job `-target`s
> `hcloud_server_network.web["web-1"]` — transitively reaching `hcloud_server.web` — while its
> guard set is `resource_deletes` / `nested_deletes` / `reboot_updates` with **no**
> `host_creates` check. That path could birth a host on a new bootstrap hash with no coherence
> preflight. It belongs to the apply workflow's guard set rather than to this gate, and is
> tracked in #6718. Reachability is narrow — web-1 normally exists in state, so targeting its
> network attachment does not create it — so this is a defence-in-depth gap rather than a live
> outage. The reason to close it is that the sibling `apply` job already decided this class of
> accident warrants a hard HALT.
>
> The residual exposure remains an operator-driven fresh create or `-replace` of web-1, which
> has no preflight; closing it needs a preflight that works against a mutable tag, tracked in
> #6712.
>
> **Related follow-ups filed with this amendment:** #6710 (whether a never-ready cloudflared
> should abort the boot at all — the adjacent `cloudflared_ready` fail-closed gate, grandfathered
> here rather than endorsed) and #6711 (private-NIC health splits across Sentry and Better Stack
> with no shared join key).

> **Amendment (2026-07-20, #6718 — the `warm_standby` gap above is CLOSED; #6712 is PREVENTED,
> not VERIFIED).** Factual status note on the two items the 2026-07-19 amendment left open.
>
> **Closed.** The `warm_standby` job now carries the same `host_creates > 0` HALT as the sibling
> `apply` job. It is unbypassable for a *stronger* reason than the sibling: `apply` evaluates its
> HALT **outside** the `destroy_count` sum so `[ack-destroy]` cannot reach it, whereas
> `warm_standby` has **no `destroy_count` sum and no ack path at all** — it is `workflow_dispatch`
> -only and never reads a commit message. (An earlier revision of this amendment imported the
> sibling's rationale verbatim and misdescribed the mechanism it was documenting; caught in
> #6725's review.)
> The load-bearing edit was extending that job's `^[0-9]+$` validation to cover `host_creates`:
> `jq -r` on a missing key yields the string `null`, and `[[ "null" -gt 0 ]]` passes — without it
> the guard would have been present, green, and fail-**open**.
>
> **The 2026-07-19 assessment of reachability was correct but incomplete.** It reasoned that
> web-1 normally exists in state, so targeting its network attachment does not create it — hence
> "defence-in-depth". The composition it did not state: `warm_standby` passes **no
> `-var image_name`** (only `web_2_recreate` pins — `apply` is unpinned too and is held by its own
> #6416 HALT rather than by pinning, so the mutable-tag exposure is a property of the WORKFLOW,
> not of one dispatch; this makes the HALT more justified, not less), so a transitive birth would
> use the mutable `:latest` default. That is #6712's failure mode reached through #6718's hole,
> which is why the two were closed as one defect.
>
> **Measured while closing it (Terraform v1.10.5):** a `-target` naming an unresolvable `for_each`
> instance key **warns and is silently ignored** — exit 0, `No changes` — it does **not** error.
> This mattered: had it errored, the plan step would have died before the guard block and the new
> HALT would have been present but unreachable. It also means `warm_standby`'s three `web-2`
> `-target`s have been no-ops since #6538 (tracked in #6575).
>
> **#6712 is PREVENTED, not VERIFIED, and stays open.** No preflight was added and no resolver
> shipped — the resolver extraction was cut because its only call site (`web_2_recreate`) is
> unreachable after the web-2 retirement. The birth is now *blocked* rather than *validated*.
>
> **A second unguarded path existed and was closed here too.** The first revision of this PR
> asserted "no automated path can birth a web host" **without enumerating the workflows** — and
> the assertion was false: `apply-deploy-pipeline-fix.yml` fires on `push:main` *and*
> `workflow_dispatch`, runs `terraform apply -auto-approve` over four `terraform_data` targets
> that each reference `hcloud_server.web["web-1"]`, and carried no counter, no HALT and no
> `-var image_name` — the identical composition. #6725's review caught it; the same shared-filter
> HALT now guards it. **The enumeration is the deliverable, not the claim**: apply (#6416),
> warm_standby (#6718), apply-deploy-pipeline-fix (#6718), web_2_recreate (gate unsatisfiable),
> workspaces_luks_cutover (gate requires zero actions on the web-1 server).
>
> **The residual inverted into a capability gap.** The 2026-07-19 residual — an operator-driven
> fresh create/`-replace` of web-1 with no preflight — is now the *only* remaining route, because
> every automated route that can reach `hcloud_server.web` HALTs (scope: **web** hosts;
> `inngest_host` legitimately births a host). That violates
> `hr-fresh-host-provisioning-reachable-from-terraform-apply` and is tracked in **#6730**. Do not
> resolve it by weakening either HALT: the correct fix is a pinned, attachment-complete birth path
> that the tripwire can distinguish from an accidental create.
>
> **[Enumeration correction, 2026-07-20, #6575.]** Two entries in the five-path enumeration above
> are no longer *guarded paths* — they are **deleted paths**. `warm_standby` and `web_2_recreate`
> were removed with the rest of the web-2 dispatch surface, so the surviving enumeration is: apply
> (#6416 HALT), apply-deploy-pipeline-fix (#6718 HALT), workspaces_luks_cutover (gate requires zero
> actions on the web-1 server). Read as-written, "warm_standby (#6718)" now credits a HALT to a job
> that does not exist, which overstates the guarded surface by two. The **conclusion is unchanged
> and if anything stronger** — every *remaining* automated route to `hcloud_server.web` still HALTs,
> and two routes that could reach it no longer exist at all. Also measured-and-now-moot: the note
> that `warm_standby`'s three `web-2` `-target`s had been no-ops since #6538 was the tracking item
> #6575 closed by deleting them.

### Candidate implementations for I2 — assessed in #6441 (SUPERSEDED — see the amendment above; (b) shipped in #6425)

Two shapes are on the table: **(a)** per-host private-net-relative ingress (`ssh-web-1.` →
`ssh://10.0.1.10:22`) — **disfavoured**, it needs the `-d "$SERVER_IP"` NAT rework and
ADR-068:378-384 already rejected the adjacent per-host-tunnel shape; and **(b)** a
single-connector gate enforcing I1 at runtime — **leading**, and the only shape that makes I1
well-formed. The full assessment, evidence, and open risks live in **#6441**; designing them
here would put speculative work in the wrong artifact. The one constraint that must not be
lost is normative and stated above: **do not repoint the 12 `connection { host }` blocks.**

## Alternatives Considered

| Option | Verdict | Why |
|---|---|---|
| **A tunnel per backend** (the operator's framing) | **Rejected** | Premise inverted — there is already exactly one tunnel, and one is right: CF load-balancing across replicas is the contract. Per-backend tunnels multiply tokens / Access apps / DNS / cloudflared **and do not solve determinism** — each tunnel would still load-balance across its own replicas. ADR-068:378-384 already rejected the adjacent shape (risks REPLACING the live tunnel; `config_src` forces replacement ⇒ deploy-path outage). |
| Per-host hostnames pointed at `ssh://localhost:22` | **Rejected — does not work** | The hostname selects the tunnel; CF then load-balances. Recorded above as a normative anti-pattern. |
| Dedicated cloudflared on the zot host | **Rejected** | ADR-096 §Decision: *"no cloudflared on the registry host"*. Reversing needs its own ADR and expands the deny-all host's blast radius. |
| Make the zot mirror blocking (#6416 ask #3, literally worded) | **Rejected** | Reverses ADR-096's explicit Decision. The real gap was the **skipped** degraded emit — fixed by loudness, not blocking. |
| Remove the `registry.` ingress rule as "stale" | **Rejected** | #6357 already disproved this; it is the live ADR-096 push path. |

## Relationship to other ADRs

- **ADR-008** → `superseded-in-part`. Its Decision hardcodes single-host `localhost:` routes
  (dated 2026-03-27, when there was one host), and its claimed `app.soleur.ai → localhost:3000`
  route **does not exist** (measured: 0 `app.` ingress rules; app is a direct A record).
- **ADR-068** → **extended**, not corrected. It stated the multi-connector fact and rejected
  per-host tunnels; it simply never generalized beyond the deploy path. Its "11 SSH
  provisioners" count is stale — measured **12**.
- **ADR-096** → **vindicated, not amended.** Its Decision (zot primary, no cloudflared on the
  registry host, GHCR fallback) is unchanged and was never the problem — the registry ingress
  it specifies is the one route that already had the right shape.
  > An earlier revision of this ADR attributed the singular phrase *"the web host's cloudflared
  > (already a 10.0.1.0/24 member)"* to ADR-096. That string is **not in ADR-096** — it was a
  > comment in `tunnel.tf`, which this PR corrects. ADR-096 does carry a singular framing at
  > `:199` ("bridges over SSH to the *existing* web host"), but that sentence is about the apply
  > path, not tunnel membership. Caught at review; the misattribution is recorded rather than
  > silently deleted because the *conclusion* (no amendment needed) never depended on it.
