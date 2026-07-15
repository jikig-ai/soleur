---
adr: 114
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

**Negative / accepted.** I1 and I2 are **recorded but not enforced** here. `ssh.` remains
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

### Candidate implementations for I2 — assessed in #6441

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
