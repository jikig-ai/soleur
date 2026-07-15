# fix: web-2 private-net attachment + tunnel connector determinism (#6416)

---
lane: cross-domain
type: fix
issue: 6416
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
adr: ADR-113 (next-free verified against origin/main 2026-07-15; re-verify at /ship)
---

> **Lane note:** `knowledge-base/project/specs/feat-one-shot-6416-web2-private-net-tunnel/spec.md` does not exist (no brainstorm preceded this one-shot). Spec lacks valid `lane:` — defaulted to `cross-domain` (TR2 fail-closed).
>
> **This is v2.** A 5-agent panel + a scoped advisor consult falsified four v1 claims by **measurement**. Every correction is marked `v2:` inline. v1's largest phase (per-host SSH ingress) is **cut** — see `## Alternatives Considered`.

## Overview

`soleur-web-2` (warm standby, fsn1) is attached to **no** Hetzner private network (`privIP=-`), so
the `registry.soleur.ai` tunnel ingress — service `tcp://10.0.1.30:5000` (zot, private-net-only) —
fails whenever web-2's cloudflared replica answers. CI's zot mirror is dead, silently.

**Root cause — a `-target` transitivity asymmetry, not a missing declaration.**
`hcloud_server_network.web` (`network.tf:39-44`) *is* declared `for_each = var.web_hosts`, but it
is a **graph leaf** (nothing reads its attributes) and is not allowlisted, so `-target` can never
pull it. Meanwhile `-target` traversal is **RESOURCE-level, not instance-level** (reproduced on
Terraform **1.10.5**, the pin at `apply-web-platform-infra.yml:127`): a reference to
`hcloud_server.web["web-1"]` pulls the **entire** `for_each` map, **including web-2**. Two
allowlisted per-PR targets do exactly that:

| Allowlisted target | Site | Reference |
|---|---|---|
| `cloudflare_record.app` | `dns.tf:16` | `hcloud_server.web["web-1"].ipv4_address` |
| `hcloud_firewall_attachment.web` | `firewall.tf:93` | `[for h in hcloud_server.web : h.id]` (whole map) |

`cloudflare_record.app` is the **`app.soleur.ai` A record** — per-PR-necessary and **unremovable**.
**It alone births web-2**, so the pull cannot be engineered away and a **guard is the only fix**.

> **v2 correction:** v1 named `hcloud_firewall_attachment.web` as *the* cause — it is one of **two**.
> (The terraform-architect cited the second as `cloudflare_record.web_host` at `dns.tf:16`; that
> resource **does not exist** — retired with #5933/#6133, `dns.tf:22-27`. The real puller at that
> line is `cloudflare_record.app`. Verified by direct read.)

**Every existing guard is blind by construction.** The destroy-guard jq counts deletes and
reboot-updates but has **no create counter** — its `reboot_updates` header even says it "never
false-fires on a **CREATE (web-2 add)**". `terraform-target-parity.test.ts` classifies both
resources as `OPERATOR_APPLIED_EXCLUSIONS`, so it is green while prod drifts; it has no notion of
transitive pull-in. And the 12h drift detector **saw** it (exit 2) but is **drowned** — see P4b.

**The topology finding (the operator's first-class question).** See `## Architecture Decision`.
The filed registry failure and a more severe **unfiled** SSH-provisioning hazard share one cause:
a single tunnel with **connector-relative** ingress and **two** replicas ⇒ nondeterministic origin.

## Research Reconciliation — Spec vs. Codebase

| Issue claim | Reality (verified) | Plan response |
|---|---|---|
| "Restore web-2's attachment — likely a `web-2-recreate` / server_network fix" | Right instinct; **the mechanism already exists**. `warm_standby` (`apply-web-platform-infra.yml:657`) already `-target`s `hcloud_server_network.web["web-2"]` (`:760-765`); `web_2_recreate` (`:894`) too (`:1148-1152`). **No new Terraform.** | P1 dispatches the existing job. |
| Implied: web-2 is unattached by design | **False.** No ADR or comment says so. It is in `network.tf`'s `for_each`, the warm-standby set, and the recreate set. Unintended drift. | Root cause is the transitive-pull asymmetry. |
| "Verify the `registry.*`/`ssh.*` ingress is served by a private-net-attached origin (web-1)" | **Not expressible today.** CF load-balances across HA replicas; `server.tf:158` gives BOTH hosts the same token (`for_each`, no `each.key` conditional). You cannot pin the answering origin. | Re-framed as a determinism decision — `## Architecture Decision`. |
| "Consider failing the release loud (not `continue-on-error`-masked)" | **Contradicts ADR-096**, which explicitly binds the mirror non-blocking. The *real* gap is narrower: `zot_mirror` is `if: steps.zot_bridge.outcome == 'success'` and `degraded()` lives **inside** it, so a **bridge** failure makes the mirror **skip** and nothing emits. | **Do not make it blocking.** Fix the loudness gap (P3). |
| `tunnel.tf:62` blames `dial tcp 10.0.1.30:5000: operation was canceled` on "the origin is transiently DOWN (#6288)" | **Misattribution.** An unattached web-2 produces the identical error on ~50% of dials. | Correct the comment (P4). |
| Issue scope: registry push only | **Incomplete.** `cf-tunnel-ssh-bridge/action.yml:208` NAT-redirects web-1's public IP into the shared tunnel, so the 11 web-1-scoped `terraform_data.*` provisioners can land on **web-2** while state records web-1. | Carries the threshold. P2c tripwire; audit filed as its own P1 issue. |

## Hypotheses

Network-outage checklist triggered (`unreachable`, `firewall`, `timeout`, `handshake`). L3 → L7.

1. **L3 — private-network membership (ROOT CAUSE).** `hcloud_server_network.web["web-2"]` absent
   from live state. Artifact: `hcloud server describe soleur-web-2 -o json | jq '.private_net'`
   → `[]` (issue: `privIP=-`) vs `soleur-web-platform` → `10.0.1.10`. **[verified — code
   conclusive; live re-confirm at P0.1]**
2. **L3 — Hetzner firewall.** Opt-out **with artifact**: intra-`hcloud_network` traffic is not
   subject to `hcloud_firewall` at all (public interface only —
   `2026-07-02-multi-host-ga-cutover-review-mechanisms.md`), and web-1 → `10.0.1.30:5000` is
   REACHABLE now. The failure is *absence of an interface*, not a filtered packet.
   **[verified — not the cause]**
3. **L3 — DNS/routing.** `registry.soleur.ai` is a proxied CNAME to the tunnel (`dns.tf:59`);
   identical for both replicas → not a discriminator. **[verified — not the cause]**
4. **L7 — ingress routing (CO-CAUSE).** The rule is correct and live (`tunnel.tf:64-75`; #6357
   already disproved a "stale rule" premise). The defect is **which connector answers**.
   Artifact: `cloudflared tunnel info soleur-web-platform` → expect **2** registrations.
   **[verified statically at `server.tf:158`]**
5. **L7 — SSH config landing on the wrong host (LATENT, unfiled; CARRIES THE THRESHOLD).** Same
   co-cause on `ssh.`. The issue's own evidence (`hostname` → `soleur-web-2`) is one such landing.
   **ALREADY happening; P1 has ZERO effect on it** — P1 grants private-net membership, which
   changes exactly one ingress (`registry.`); `ssh://localhost:22` is connector-relative and
   wholly unaffected. **[verified]**
6. **L7 — zot origin down (#6288).** Cannot explain a per-replica split; web-1 REACHABLE at the
   same instant web-2 is not. **[verified — not the cause]**
7. **L7 — `deploy.` nondeterminism. `v2: VERIFIED — was "unverified" in v1.`**
   `deploy-status-fanout-verify.sh:66-67` defaults `DEPLOY_URL`/`DEPLOY_STATUS_URL` to
   `https://deploy.soleur.ai/...`, and `cloudflare_record.deploy` (`dns.tf:31-37`) is a proxied
   CNAME to `<tunnel-id>.cfargotunnel.com` → ingress `http://localhost:9000`. **The tunnel IS on
   the fan-out path**; the script's own header ("via web-1's PUBLIC") is **false** — the same
   stale-comment class as `tunnel.tf:62`. The **trigger** leg is already solved by ADR-068's
   Option B (receiving-host fan-out: whichever host receives self-excludes and forwards to peers).
   The **unsolved** leg is `GET /hooks/deploy-status`, which is **host-local**: today web-2 is
   unattached and likely 502s, so the GET effectively lands on web-1 and the verify accidentally
   works. **After P1, web-2 answers it successfully and the verify goes nondeterministic** — i.e.
   **P1 corrodes the very evidence AC12/AC14 depend on.** Only `HEALTH_URL` (`app.soleur.ai`,
   single A record → web-1) is safe. **[verified — see Risks; this is why AC14 needs N runs]**

## Architecture Decision (ADR/C4)

> **Operator question (first-class scope):** *"why do we have a tunnel for each backend instead of
> a tunnel that allows to reach any backend?"*

### Answer from evidence — the premise is inverted

**We do not have a tunnel per backend. We have exactly ONE tunnel** — `git grep 'resource
"cloudflare_zero_trust_tunnel_cloudflared"' -- '*.tf'` returns **1 hit** (`tunnel.tf:10`), with
one config (`:26-81`) carrying 4 ingress rules, and **no** cloudflared on git-data, zot, or
inngest (ADR-096 §Decision: *"no cloudflared on the registry host"*).

What *is* per-backend is the **(hostname + CF Access app + service token + CI bridge action)**
quadruple — **deliberate least-privilege**, not accident (`tunnel.tf:148-151`: a dedicated
registry token *"so registry-write access rotates/revokes independently of host-shell + webhook
access"*). **That layering is correct and this plan keeps it.**

**One tunnel is also the right architecture.** Cloudflare binds ingress to a *tunnel* and
load-balances across *connector replicas* — that is the **contract, not a defect**. The defect is
narrower:

> **`localhost:` in a multi-replica tunnel is a category error.** It does not mean "this host" —
> it means *"whichever replica answers."*

| Route | Service | Host-agnostic? | Status |
|---|---|---|---|
| `registry.` | `tcp://${local.registry_endpoint}` → `10.0.1.30:5000` | Yes — if every replica is a private-net member | **Already the correct pattern**; only homogeneity was missing |
| `deploy.` | `http://localhost:9000` | Trigger leg: yes (ADR-068 Option B fan-out). **Status leg: NO** — `deploy-status` is host-local (H7) | Partially solved |
| `ssh.` | `ssh://localhost:22` | **No — fundamentally host-specific** | The open problem |

The registry rule is the pattern to generalize: **private-net-relative**, so whichever replica
answers proxies to the *right* origin.

### Prior art — ADR-068 already knew (v2 correction)

**v1 claimed ADR-068 "introduced the second connector without stating the invariant; that omission
is the proximate cause". That is FALSE.** `ADR-068:354-357` states it verbatim: *"both hosts run
cloudflared on that ONE tunnel, so a POST load-balances to ONE connector non-deterministically."*
It chose Option B and **explicitly REJECTED per-host tunnels** (`:378-384`) — *"`for_each`-ing
`cloudflared.web` risks REPLACING the live tunnel (import artifact, `config_src` forces
replacement) = deploy-path outage… collides with 3.D's ingress rewire"* — and even records that
*"the 11 SSH provisioners are all web-1-scoped"* (`:383`).

**Two consequences.** (1) ADR-113 must **cite** ADR-068's rejection of per-host tunnels, never
re-decide it as novel. (2) **v1's P2b was re-proposing an explicitly-rejected alternative** — the
exact trap the Phase 0.6 ADR-corpus grep exists to catch, missed at plan time and caught by the
panel. The real gap in ADR-068 is narrower and is what ADR-113 closes: **it solved connector
nondeterminism for the DEPLOY path only and never generalized to `ssh.` / `registry.`**

### Normative content of ADR-113

- **I1 — Connector homogeneity (runtime precondition).** *A host must not serve as a tunnel
  connector unless it can serve **every** ingress rule* — concretely, its private NIC is up.
  > **v2 correction (architecture-strategist, P1-4).** v1 stated I1 as *"private-net attach is a
  > precondition of holding the token"* and claimed *"enforced by the P2 guard"*. **Both were
  > wrong.** I1 as v1 phrased it is **falsified by construction**: `server.tf:158` passes
  > `tunnel_token` via cloud-init `user_data` at server-**create**, while
  > `hcloud_server_network.web` cannot exist until `hcloud_server.web[k].id` does. **The attach
  > ALWAYS lands after the token.** Every fresh host boots cloudflared (`cloud-init.yml:590`) and
  > registers *before* its private NIC exists — the identical race the plan notes for
  > insecure-registries (`cloud-init.yml:445`). And `host_creates` enforces *"no host CREATE on
  > the per-PR path"* — it is silent on attach-before-token and **exempts** the very dispatch jobs
  > that birth token-holding unattached connectors. **I1 is therefore stated as a RUNTIME
  > precondition** (cloud-init must block `cloudflared service install` until the NIC is up), with
  > an explicit bounded boot window. Its enforcement is candidate (b) below — **not** shipped
  > here, and **no phase in this PR claims to enforce it**.
- **I2 — Ingress services MUST be private-net-relative (`10.0.1.x`) for any host-specific route.**
  `localhost:` is permitted **only** for genuinely host-agnostic routes. Well-formed and testable.
- **Anti-pattern (normative):** per-hostname ingress **does not pin a connector** — the hostname
  selects the *tunnel*, then CF load-balances. `ssh-web-1.` → `ssh://localhost:22` is a **no-op**.

### Sequencing — I1/I2 implementation deferred, ADR is NOT

`wg-architecture-decision-is-a-plan-deliverable` is satisfied: **ADR-113 is authored now**, states
the category-error finding + I1/I2 + the anti-pattern as normative, cites ADR-068's prior
rejection, and records the two candidate implementations with evidence. Status `adopting`.

What ships here for H5 is the **P2c tripwire** (detection), not the topology change (prevention) —
the tripwire is the only *runtime evidence*, is a precondition of trusting either candidate, and
touches no `.tf` in the live-origin graph.

**Two candidate implementations** (the I2 issue picks one):

| Candidate | Assessment |
|---|---|
| **(a) Per-host private-net-relative ingress** (`ssh-web-1.` → `ssh://10.0.1.10:22`) | **Disfavoured.** Needs the `-d "$SERVER_IP"` NAT rework (below), a new TF output for the private address, two cloudflared listeners + two NAT rules, 11 connection blocks, CF Access, DNS, and an `ssh.` retirement. **ADR-068:378-384 already rejected the adjacent per-host-tunnel shape.** |
| **(b) Single-connector gate — enforce I1 at runtime** ⭐ | **Leading candidate.** web-2 does not run cloudflared until its NIC is up (and, on a warm standby, not at all). One connector ⇒ `localhost:` and `ssh.` deterministic **by construction**. Evidence it is safe: the tunnel carries **no `app.` ingress rule** (`grep -c 'hostname = "app\.' tunnel.tf` → **0**) — it is purely *management-plane*; `app.soleur.ai` is a **direct proxied A record** to web-1 (`dns.tf:13-20`), never through the tunnel; break-glass is preserved (`tunnel.tf:4`: *"Operator/admin SSH still uses the direct A record + admin_ips firewall"*). `server.tf:188` **already** computes the per-host discriminator, so the gate is ~1 line. **This is also the ONLY shape that makes I1 well-formed** (arch-strategist P1-4). **Open risks to price:** `deploy.` fan-out reaches web-2 through the tunnel (H7), so gating web-2 out interacts with ADR-068 Option B — the fan-out targets peers over the **private net**, so it should hold, **but must be proven**; and on promotion web-2 *would* need the token, while **no web-2 promotion runbook exists** (pre-existing gap). |

### C4 views

All three model files read (`model.c4` 441 L, `views.c4` 62 L, `spec.c4` 54 L) — not a keyword
grep. **External human actors** (`founder`, `emailSender`, `betaContact`, `contributor`): none
added. **External systems/vendors** (`cloudflare`, `github`, `ghcr`, `zotRegistry`,
`betterstack`): none added. **Containers touched** (`platform.infra.tunnel` `:176`,
`platform.infra.hetzner` `:180`, `zotRegistry` `:258`): all already modeled **and** already in the
`containers` view (`views.c4:32` for tunnel/hetzner, `:36` for zotRegistry — *v2: v1 cited
`:36-40`; lines `39-42` are a `style`/`autoLayout` block*), so new edges render with **no new
`include`**. Note the L1 `context` view (`:11-14`) does not include `tunnel`/`hetzner` — new edges
won't render there, which is fine.

**Access relationships that change — 3 missing edges + 1 falsified description** (in scope; edited
directly on the filesystem and committed in this feature's lifecycle — the `c4-edit` flag gates
only the in-browser editor's `PUT /api/kb/c4`, not this workflow):

1. **Amend `platform.infra.tunnel`'s description** (`:176-179`). "*Zero-trust inbound access — no exposed ports*" is falsified-by-omission: it omits the multi-replica connector semantics this entire plan turns on.
2. **Add `tunnel -> zotRegistry`** — the live ADR-096 registry-push ingress. Missing today: the tunnel's only edge is `tunnel -> coordinator` (`:362`).
3. **Add `hetzner -> tunnel`** — each web host runs a connector **replica** of the one tunnel.
4. **Add `github -> tunnel`** — CI reaches `ssh.`/`registry.`/`deploy.` via CF Access service tokens.

Validate with `apps/web-platform/test/c4-code-syntax.test.ts` + `c4-render.test.ts`.

## User-Brand Impact

- **If this lands broken, the user experiences:** a deploy pulling an unverifiable or stale image
  (zot silently un-backfilled → GHCR fallback → once ADR-096 Phase-5 retires GHCR push, **no**
  image source); and — via H5 — a `soleur-web-platform` whose container-egress firewall / seccomp /
  apparmor profile was never actually applied, because the provisioner landed on web-2.
- **If this leaks, the user's data is exposed via:** an unenforced container egress firewall on the
  live serving host (ADR-052 / #5046 — the control that stops an agent container exfiltrating a
  user's repo contents and BYOK credentials). H5 makes "Terraform says web-1 is hardened" an
  assertion state cannot back.
- **Brand-survival threshold:** `single-user incident` — with a **false-assurance multiplier**: the
  hole is one we believe is closed, and CI reports green.

Sign-off: `requires_cpo_signoff: true`. `user-impact-reviewer` runs at review time.

## Infrastructure (IaC)

### Terraform changes

**None to resource declarations.** `hcloud_server_network.web` already declares web-2
(`network.tf:39-44`). Terraform touched only for: `tunnel.tf` comment correction at `:58-63`
(comment-only, **no resource diff**), and P2c's `hostname` assertion inside existing
`terraform_data.*` provisioner scripts. No new providers, no new sensitive variables.

### Apply path

**Existing guarded dispatch — no new provisioning path.** `gh workflow run
apply-web-platform-infra.yml -f apply_target=warm-standby -f reason="#6416 restore web-2
private-net attach"`, **agent-run**, never operator (`hr-all-infrastructure-provisioning-servers`;
`2026-07-07-agent-runs-terraform-apply-never-route-to-operator.md`).

**Blast radius.** The job re-swaps web-1 (sole live origin) at its **current** tag and fans out to
web-2, holding the `web-1-swap` mutex. On the **happy path** this is the same mechanism every
release performs. **v2: not on the failure path** — `deploy-status-fanout-verify.sh:16-21` waits
`FRESH_BOOT_WINDOW_S=600` then re-POSTs once (`DEGRADED_RETRY_MAX=1`) ⇒ **up to 2 swap cycles** of
the sole live origin, then terminal exit 1. A release does one.

### Distinctness / drift safeguards

- `dev != prd`: prd-only root (`prd_terraform`); N/A by construction.
- `lifecycle.ignore_changes` on `hcloud_server.web` = `[user_data, ssh_keys, image,
  placement_group_id]` (`server.tf:217-219`) — why no reboot materializes; `reboot_updates == 0`
  is the backstop.
- **State:** R2 backend; the job shares the workflow-level R2 serializer + the `web-1-swap` mutex.
- **Drift detector cannot be P2's backstop** — it is drowned (P4b item 2). Hence a **pre-apply
  HALT**, not a detection.

### Vendor-tier reality check

No new vendor resource; no tier gate. Hetzner private-network attachment is free and additive.

## Observability

```yaml
liveness_signal:
  what: "zot mirror reachability per release — `steps.zot_mirror.outputs.mirror_status`, now emitted on the bridge-failure path too (P3)"
  cadence: "every release (push to main touching apps/web-platform/**)"
  alert_target: "GH step summary ::warning:: + the Slack release ⚠️ (reusable-release.yml:846/891) + sentry_issue_alert.zot_mirror_fallback_rate (issue-alerts.tf, >3/1h)"
  configured_in: ".github/workflows/reusable-release.yml; apps/web-platform/infra/sentry/issue-alerts.tf"
error_reporting:
  destination: "GitHub Actions step summary + Slack release message + Sentry"
  fail_loud: "degraded — NOT blocking. ADR-096 binds the mirror non-blocking; P3 makes the EXISTING degraded signal cover the bridge-failure path it currently skips. Loud != red."
failure_modes:
  - mode: "a per-PR merge-apply transitively BIRTHS a web host (the edge that STARTS the drift, since the private-net leaf can never be pulled with it)"
    detection: "P2 `host_creates` counter: plan JSON shows an hcloud_server/hcloud_volume at actions == [\"create\"]"
    alert_route: "merge-apply HALTS with ::error:: naming the address + a PER-TYPE remediation. NO [ack-destroy] bypass."
  - mode: "an SSH provisioner lands on the WRONG host (H5) — state records web-1, config landed on web-2"
    detection: "P2c in-band `hostname` assertion in the provisioner preflight, fail-closed — the ONLY runtime evidence in this plan (a tunnel.tf grep proves config shape, never packet destination)"
    alert_route: "the SSH apply ABORTS red. A red apply beats a green lie."
  - mode: "the CF tunnel bridge cannot reach its origin (zot down #6288, or a wrong-replica dial)"
    detection: "steps.zot_bridge.outcome == 'failure' → the EXISTING degraded() emitter, now reached (P3)"
    alert_route: "::warning:: + step summary + Slack ⚠️ — the path that is silent today"
logs:
  where: "GitHub Actions run logs + step summaries; Better Stack Logs source 2457081 (per-host host_name discriminator, #6396)"
  retention: "GH Actions 90d; Better Stack per plan"
discoverability_test:
  command: "gh run list --workflow=reusable-release.yml --limit 5 --json conclusion,url && gh run view <id> --log | grep -E 'zot mirror degraded|attach proof|mirror_status' || true"
  expected_output: "either 'attach proof OK: hcloud_server_network.web[\"web-2\"] present in state' (P1 landed) or an explicit 'zot mirror degraded' line — never silence"
```

**No `ssh ` in `discoverability_test.command`** (`hr-no-ssh-fallback-in-runbooks`) — web-2 is a
blind surface (deny-all public, no SSH), so every detection is an emitted signal.
**v2:** the grep does **not** match a literal `rc=<number>` — a bridge failure has **no numeric
exit code** (see P3). Trailing `|| true` because `grep -c`/`grep` returning no match exits 1 and
would abort a `set -e` script.

### Soak follow-through enrollment

ADR-113 flips `adopting → accepted` only after a soak ⇒ a soak-gated close criterion, which MUST
be enrolled, not remembered:

- **Script:** `scripts/followthroughs/zot-mirror-connector-6416.sh` — exit 0 when, over ≥7 days
  **strictly after** the P1 apply, releases show zero `zot mirror degraded` **and** ≥3 releases
  sampled. Mirror `scripts/followthroughs/reconcile-ff-only-sentry-4977.sh`, `start=` pinned
  strictly after the deploy.
- **Tracker:** `<!-- soleur:followthrough script=scripts/followthroughs/zot-mirror-connector-6416.sh earliest=<P1-apply +7d> secrets=BETTERSTACK_API_TOKEN -->` + the `follow-through` label (verified to exist).
- **Sweeper:** confirm `secrets=` in `.github/workflows/scheduled-followthrough-sweeper.yml`; add if absent.

## Implementation Phases

### P0 — Preconditions

- **P0.1** `hcloud server describe soleur-web-2 -o json | jq '.private_net'` → expect `[]`; and
  `soleur-web-platform` → `10.0.1.10`. If web-2 is **already** attached, the premise is stale →
  STOP and re-scope (`2026-07-12-remove-request-issue-verify-stale-premise-before-acting.md`).
- **P0.2** `cloudflared tunnel info soleur-web-platform` → record the connector count (expect 2).
  *(v2: v1 also prescribed an N=10 `hostname` tally as "the evidence the I2 option choice depends
  on". **Cut** — I2's options are decided on structural grounds, the connector count is already
  statically proven at `server.tf:158`, and the issue already contains one `soleur-web-2` landing.
  No value of N moved a decision. P2c makes the tally permanent anyway.)*
- **P0.3** ~~Probe web-2's `:9000` via the fan-out to decide recreate-vs-warm-standby.~~
  **v2: CUT — the probe cannot make its own decision.** The fan-out reaches the peer over
  `WEB_HOST_PRIVATE_IPS` (`deploy-status-fanout-verify.sh:35`), and **web-2 has no private IP** —
  the premise of #6416. It returns `ok_peer_fanout_degraded` in **both** branches: a constant, not
  a discriminator. **Replaced by the P1 escalation rule below**, which needs no prior probe.

### P1 — Restore the attachment (agent-run dispatch, no new TF)

- Dispatch `warm-standby`; poll with `gh run watch`.
- The job's own **attach proof** step asserts both web-2 addresses are in `terraform state list`
  and `::error::`s otherwise — that is the AC's evidence, not a claim.
- **v2 — escalation rule (architecture-strategist Q1(b)), replaces P0.3.** The attach-proof step
  (`:801-831`) runs **BEFORE** the verify step (`:833+`). So an unbound `:9000` yields **job RED
  with the attachment successfully applied** — *P1's objective succeeds even when the job fails.*
  **The real hazard is the inverse:** reading RED as "attach failed" and reflexively dispatching
  `web-2-recreate`, which `-replace`s the host and **destroys a good attach for nothing**.
  **Rule: on RED, read the attach-proof step's outcome FIRST. Dispatch `web-2-recreate` only if
  the APPLY failed — never if only the VERIFY failed.**
- **Post-attach L3 re-verify** (`2026-07-07-immutable-redeploy.md` SE-2): a fresh host can boot
  with its private NIC **down** while the control plane says "attached". Prove **packets**, not
  state; a soft reboot brings the NIC up.

### P2 — Prevent recurrence: `host_creates` HALT (fail-closed)

**Ruling (CTO Q1 + terraform-architect): guard. Do NOT break the dependency.** `server_ids` is a
genuine data dependency; breaking it trades a caught bug for an uncaught drift class, is
whack-a-mole across ~70 targets, and **cannot work anyway** since `cloudflare_record.app`
independently births web-2. Transitive pull-in is `-target` **semantics**, not a resource bug.

```jq
# 7th surface (#6416). `-target` is transitive at the RESOURCE level (verified, TF 1.10.5), so
# EVERY allow-listed resource referencing ANY hcloud_server.web instance — cloudflare_record.app
# (dns.tf:16) AND hcloud_firewall_attachment.web (firewall.tf:93) — pulls the whole for_each map
# incl. web-2. A pure `+ create` is invisible to resource_deletes/nested_deletes/reboot_updates.
# Type-scoped (not address) for the same defense-in-depth reason reboot_updates is.
# actions==["create"] EXACTLY: a -replace is ["delete","create"], already counted by
# resource_deletes -> no double-count (MEASURED against tfplan-hcloud-server-location-replace.json:
# host_creates=0, resource_deletes=1).
host_creates: (
  [ .resource_changes[]?
    | select(.type == "hcloud_server" or .type == "hcloud_volume")
    | select(.change.actions == ["create"]) ]
  | length
),
```

- **Additive key only** — `apply` / `warm_standby` / manual-rerun read only the three original
  counters and stay byte-unchanged (the jq header's BACKWARD-COMPAT discipline).
- **Add `host_creates` to the numeric parse validation** at `apply-web-platform-infra.yml:424-427`.
  **v2 (spec-flow #4):** that block exists precisely because *"empty values from a jq failure would
  silently evaluate false in the `-gt 0` test and let destructive plans slip past the guard."*
  Omitting it ships a **fail-open** guard the plan calls fail-closed.
- **NO `[ack-destroy]` bypass** — gate **outside** the `destroy_count` sum, mirroring
  `reboot_updates`' suppression of the generic ack line (`:445-450`).
- **v2 — PER-TYPE remediation text (arch-strategist P2-5, spec-flow #9).** v1's single message
  named `-f apply_target=warm-standby`, which is correct **only for web-2**. `hcloud_server.inngest`
  → `apply_target=inngest-host`. `hcloud_server.registry` → **no dispatch creates it** (both
  registry dispatches are `-replace` and need the resource already in state); remediation is the
  operator-local **full apply** (the `OPERATOR_APPLIED_EXCLUSIONS` contract, ADR-096). **A legit
  `web-3`** → also no dispatch (`warm_standby`'s targets are hardcoded to web-2, `:760-765`) ⇒
  a merged `var.web_hosts` web-3 entry would make **every subsequent merge** HALT, not just its own
  PR. The message must name the full-apply-before-merge path. *"Does not wedge the repo" holds only
  for today's 2-host state.*
- **Do NOT gate the dispatch jobs** on `host_creates` — they legitimately create.
- **`terraform-target-parity.test.ts` needs NO change** — its exclusion sets stay byte-identical
  and become **true instead of aspirational**.
- **Tripwire, not a routine gate:** `host_creates == 0` today ⇒ no-op on normal merges. **Option A
  changes no HCL** ⇒ zero blast radius on the live web-1.
- **Known hazard, undefended sibling:** `apply-web-platform-infra.yml:747-752` **already documents
  this exact hazard** for `warm_standby` and defends it with two layers; the `apply` job inherited
  it with **neither**.

**v2 — test-harness reality (Kieran P0). v1 mis-modelled this and mis-scoped the edit:**

- `_run_gate` (`test-destroy-guard-counter-web-platform.sh:101-124`) emits
  `"$rdel:$ndel:$rupd:$dcount:$rc"` = **3 counters + a derived sum + an rc** — **not "5 counters"**.
  The `web2_*` keys are not in the string at all (a separate gate reads them). **Adding a 6th jq
  key does not widen the string**; threading it is a *choice*, and if taken it widens **~54
  counter-string sites across T1–T28**, not one.
- The T10 anchor is at **`:235`** (the comparison); **`:238` is only the failure message** — an
  editor following v1 literally would patch the message and not the assert.
- **T18 semantically INVERTS and must be resolved explicitly.** `tfplan-hcloud-server-create.json`
  **is** `hcloud_server.web["web-2"]` with `actions: ["create"]` (measured `host_creates=1`), and
  T18 (`:335-343`) is named *"hcloud_server create (**web-2 add**) is not a reboot"* with the
  comment *"**a legit new host**"* — it asserts **PASS on the exact plan shape the new guard must
  HALT**. Both cannot hold. **This is the codified belief this plan overturns; updating T18 is the
  point, not a chore.** Bonus: **AC1's RED fixture already exists** — do not author a new one.
- `_run_gate` encodes the ack semantics (`rc=1 if dcount>0 && !ack`); an ack-independent HALT needs
  a **second rc source** in the harness.
- **v2 — DROP v1's "T10 free retro-proof" claim.** **Measured: `host_creates == 0`** against
  `tfplan-web-platform-real-baseline.json` (its only hcloud entries are `no-op`). The fixture does
  not contain the drift. *(Bonus finding: it records `hcloud_server.web` **unkeyed** — it predates
  the `for_each` migration and is stale as a "real baseline".)*

### P2c — In-band wrong-host tripwire (replaces the cut P2b), ships WITH P1

> **v2 CUT (unanimous).** v1's **P2b** (per-host `ssh-web-*` ingress + DNS + CF Access + bridge
> param + repointing 11 `terraform_data.*` connection blocks) is **cut and filed as its own
> issue**. Four independent findings, three of them P0:
>
> 1. **It does not work.** `cf-tunnel-ssh-bridge/action.yml:165` sets
>    `SERVER_IP=$(terraform output -raw server_ip)` = `hcloud_server.web["web-1"].ipv4_address`
>    (**public** by contract, `outputs.tf:1-4`), and `:208-210` installs
>    `iptables -t nat -A OUTPUT -d "$SERVER_IP" --dport 22 -j REDIRECT`. The connection blocks work
>    **only because** they dial that public IP and the kernel hijacks it — the action's own comment
>    says the design holds *"with no server.tf connection.host change"*. Repointing to `10.0.1.10`
>    ⇒ the NAT rule stops matching ⇒ the runner blackholes RFC1918 ⇒ **every provisioner dies**.
>    Those 11 are `-target`ed by the **per-PR merge** `apply` job ⇒ **main wedged**. v1 never
>    mentioned `-d "$SERVER_IP"`.
> 2. **The coupling argument was refuted by this plan's own text.** v1: "P1 makes web-2 answer more
>    routes successfully ⇒ must ship together". P1 grants private-net membership, changing exactly
>    ONE ingress (`registry.`). `ssh://localhost:22` is connector-relative and **wholly unaffected**
>    — H5 says so: *"ALREADY happening and P1 does not cause it."* **P1's effect on H5 is zero.**
> 3. **The "additive cutover" was additive on the wrong axis.** `connection.host` is a **single
>    value repointed** — a swap, with no additive form. And the merge-apply runs **immediately** on
>    merge while P1 is a **post-merge** dispatch ⇒ I2 would go live before I1.
> 4. **ADR-068:378-384 already rejected the adjacent per-host-tunnel shape.**
>
> Per the plan-review rule — *when BOTH the simplification and correctness panels fire on the same
> scope, prefer delete over fix* — P2b is cut and its bugs dissolve.

**What ships instead (~10 LoC, no HCL, no CI-path risk):** a **fail-closed `hostname` assertion**
in the SSH-provisioner preflight. Each `terraform_data.*` declared for `web-1` asserts in-band that
the shell it reached **is** `soleur-web-platform`; a mismatch **aborts the apply red**.

**Do NOT touch the `connection { host }` blocks** — they must keep dialing web-1's **public** IP or
the bridge's `-d "$SERVER_IP"` NAT rule stops matching.

Why this is the right primary, not a cheaper P2b:

- **It is the only runtime evidence in the plan.** A `tunnel.tf` grep proves *config shape*; it can
  never prove a packet landed on web-1 (that would have to hold across the CF edge, the Access
  policy, the bridge `--hostname`, and the NAT rule). **You want this even if (a) later ships** —
  (a) without it is an unverified config claim, and this becomes its regression anchor.
- **It kills the actual threat** — the false-assurance multiplier that carries the threshold.
- **It does not depend on P1**; coupling to P1 is nonetheless real *in this direction*: P1 makes
  web-2 a **successful** origin for more routes (H7), so the tripwire should be live first.
- **It unblocks the deferred audit issue immediately** — the audit runs behind a fail-closed
  identity assertion instead of a config claim.

**Priced objection:** it converts a silent ~50% wrong-host *write* into a loud ~50% apply *failure*.
That is a strict improvement (a red apply beats a green lie). If flakiness bites, a bounded re-dial
retry in the bridge (new replica per attempt; ~3% residual at N=5) is ~10 more lines and touches no
`.tf`.

### P3 — Un-mask the silent CI signal (ADR-096-consistent)

> **v2 CORRECTION (Kieran #7 + spec-flow #2, P0).** v1 prescribed *"a new step
> `if: steps.zot_bridge.outcome != 'success'` that emits `mirror_status=degraded`"*. **That does not
> work.** Step outputs are namespaced **by step id**: a new step writes
> `steps.<new_id>.outputs.mirror_status`, while the Slack append reads
> `MIRROR_STATUS: ${{ steps.zot_mirror.outputs.mirror_status }}` (`:846`). `zot_mirror` stays
> skipped, its output stays unset, **the Slack ⚠️ stays inert** — the exact condition the file's own
> comment at `:842-845` documents. v1's AC5 would have passed while the goal failed.

**Correct fix — preserve the output contract every consumer reads:**

- **Drop `zot_mirror`'s `if:` gate; run it unconditionally and branch INTERNALLY** on
  `steps.zot_bridge.outcome`. Keeps `steps.zot_mirror.outputs.mirror_status` and **inherits the
  existing `degraded()` emitter** rather than duplicating it.
- **Branch on `== 'failure'`, NOT `!= 'success'`** (Kieran/spec-flow #6): `zot_bridge` itself
  carries `if: steps.docker_build.outcome == 'success'` (`:653`), so a **build** failure leaves it
  `skipped`; `!= 'success'` would emit "zot mirror degraded" for a build failure. `skipped` ⇒
  nothing to say.
- **Re-materialize the emitter's inputs — shell/step state does not cross steps:** `ZOT` is a local
  inside `zot_mirror`'s run block (`:746`) → recompute; `IMAGE` is **step-scoped** `env:` (`:680`)
  → re-declare (available as `inputs.docker_image`); **`rc` does not exist** for a bridge failure
  (`zot_bridge` is a composite `uses:` action — GitHub exposes only `outcome`/`conclusion`) → pass
  a sentinel (`rc=bridge`) or widen `degraded()` to accept a non-numeric reason.
- **Do NOT remove `continue-on-error`, do NOT red the release** — reverses ADR-096's Decision.
  Ask #3 is satisfied by **loudness, not blocking**.
- **v2 — also fix `cf-tunnel-registry-bridge/action.yml:3-5`, stale twice:** it says "the web host's
  cloudflared" (**singular** — the assumption this plan breaks) **and** `→ http://10.0.1.30:5000`,
  when `tunnel.tf:66` is `tcp://` and `tunnel.tf:49-56` documents at length why `http://` was the
  #6122 cutover bug.
- **Cut** v1's "carry the discriminating origin field": the action has **no `outputs:` block**, and
  the origin's identity is learned *by connecting* — least obtainable exactly on the failure path
  where it would be needed. P1 also retires the "wrong replica" hypothesis for `registry.`.

### P4 — Architecture record

- Author **ADR-113** via `/soleur:architecture` (next-free verified; re-verify at `/ship`).
- **Amend ADR-008** — `superseded-in-part` (precedent: `ADR-043:3`, so no new status value). Two
  independent staleness proofs: its Decision hardcodes single-host `localhost:` routes (dated
  2026-03-27), **and** its claimed `app.soleur.ai → localhost:3000` route **does not exist**
  (`grep -c 'hostname = "app\.' tunnel.tf` → 0).
- **Amend ADR-068** — **v2: as "extend the already-stated finding", NOT "state the omitted
  invariant"** (v1's framing was false; `:354-357` states it verbatim). The real gap: it solved
  connector-nondeterminism for the **deploy path only** and never generalized to `ssh.`/`registry.`.
  ADR-113 **cites** its rejection of per-host tunnels (`:378-384`) rather than re-deciding it.
- **ADR-096** — cite as precedent; **Decision text unchanged**. *v2: its stated **premise** is
  falsified exactly as ADR-008's is (`:41`, `:199` say "**the** web host's cloudflared (already a
  10.0.1.0/24 member)" — singular, and false for web-2). An optional non-blocking premise note is
  permitted; AC8 is relaxed accordingly so it does not **forbid** the correction.*
- Apply the 4 `.c4` edits; run `c4-code-syntax.test.ts` + `c4-render.test.ts`.
- Correct `tunnel.tf:58-63`.
- **File the separate P1 issue:** *"Audit web-1 vs web-2 for the 11 provisioner-applied host
  configs — Terraform state may be false."* Labels `type/bug`, `priority/p1-high`,
  `domain/engineering` (all verified). **v2: unblocked by P2c** (it runs behind a fail-closed
  identity assertion), not blocked on the cut P2b.
- **File the I2 issue:** *"Deterministic tunnel origin for host-specific routes (ADR-113 I2)."*
  Must carry: candidate (b) as the leading shape; the `-d "$SERVER_IP"` NAT rework + a new TF output
  for the private address + two-listener/two-NAT-rule requirement if (a); ADR-068:378-384's prior
  rejection; the `WEB_HOST_PRIVATE_IPS` three-sources-of-truth cleanup; the `ssh.`-retirement
  follow-up; and the ADR-082 stale `monitored = false` note.

### P4b — File the two adjacent findings (file, do not execute)

1. **`hcloud_firewall_attachment` does not attach before first boot.** Provider **1.63.0** docs:
   *"The `firewall_ids` property of the `hcloud_server` resource ensures that a server is attached
   to the specified Firewalls before its first boot. This is **not** the case when using the
   `hcloud_firewall_attachment` resource… In some scenarios this may pose a security risk."* A
   per-PR-born host boots with a **public IP and no firewall** — an independent reason the per-PR
   apply must never create a host, and it **reinforces P2's Option-A ruling**. Related race:
   `cloud-init.yml:445` sets `insecure-registries` for `10.0.1.30:5000` and pulls over a private net
   the attach has not yet provided (mitigated in practice by ADR-096's dark-launch GHCR fallback).
   Labels: `type/bug`, `priority/p2-medium`, `domain/engineering`.
2. **The 12h drift detector is drowned, not blind — it always alarms.**
   `scheduled-terraform-drift.yml:100` runs `plan -detailed-exitcode` with **no `-target`**, so it
   **did** see the missing attachment (exit 2). But `server.tf` documents **10+ resources that
   permanently show "will be created"** (lines 229, 267, 307, 362, 434, 662, 810, 956, 1019, 1048 —
   the `terraform_data` provisioners under `ignore_changes`). **Exit 2 is the permanent steady
   state**, so the real signal was indistinguishable from documented noise. *A detector that always
   alarms is not a detector.* Fix shape: a documented-noise allowlist. Labels: `type/bug`,
   `priority/p2-medium`, `domain/engineering`.

### P5 — Hygiene + enrollment

- Remove the two **stale** `-target`s (`apply-web-platform-infra.yml:370-371`):
  `cloudflare_record.web_host` + `betteruptime_monitor.web_host`. Both resources were deleted
  (`dns.tf:22-27`, "#5933 retired"); Terraform only **warns** on unmatched targets, so they are
  silently dead.
- Enroll the soak follow-through (script + tracker directive + sweeper `secrets=`).
- **v2 — CUT** v1's `WEB_HOST_PRIVATE_IPS` single-sourcing and the ADR-082 `monitored = false` fix:
  both are adjacency. They move to the I2 issue's context (the first is only load-bearing *for* I2).

## Files to Edit

| File | Change |
|---|---|
| `tests/scripts/lib/destroy-guard-filter-web-platform.jq` | P2 — additive `host_creates` key + header doc (6th → 7th surface) |
| `.github/workflows/apply-web-platform-infra.yml` | P2 — `apply` job: read + **unconditional** HALT (no ack bypass) + add `host_creates` to the numeric validation at `:424-427` + **per-type** remediation text; P5 — drop the 2 stale `-target`s at `:370-371` |
| `tests/scripts/test-destroy-guard-counter-web-platform.sh` | P2 — **resolve T18** (`:335-343`, currently asserts PASS on a web-2 create); thread `host_creates` through `_run_gate` (`:101-124`) **and widen ~54 counter-string sites across T1–T28**, incl. the T10 compare at **`:235`**; add a second ack-independent rc source. **Reuse the existing `tfplan-hcloud-server-create.json` fixture** for AC1's RED |
| `apps/web-platform/infra/server.tf` | **P2c — fail-closed `hostname` assertion in the SSH-provisioner preflight.** Do **NOT** touch `connection { host }` |
| `.github/workflows/reusable-release.yml` | P3 — drop `zot_mirror`'s `if:` gate, branch internally on `== 'failure'`, re-materialize `ZOT`/`IMAGE`, sentinel `rc` |
| `.github/actions/cf-tunnel-registry-bridge/action.yml` | P3 — header `:3-5` stale twice (singular "the web host's cloudflared"; `http://` should be `tcp://`) |
| `apps/web-platform/infra/tunnel.tf` | P4 — comment correction at `:58-63` (comment-only; **no resource diff**) |
| `knowledge-base/engineering/architecture/diagrams/model.c4` | P4 — tunnel description amend + 3 edges |
| `.../decisions/ADR-008-cloudflare-tunnel-deployment.md` | P4 — `superseded-in-part` by ADR-113 |
| `.../decisions/ADR-068-multi-host-workspaces-shared-git-data-lease-coordinator.md` | P4 — **extend** the already-stated finding to `ssh.`/`registry.` |
| `.github/workflows/scheduled-followthrough-sweeper.yml` | P5 — `secrets=` wiring if absent |

**Deliberately NOT in this table:**

- `plugins/soleur/test/terraform-target-parity.test.ts` — needs **no** change; its exclusion sets become true rather than aspirational. `tfplan-web-platform-real-baseline.json` needs no re-capture (only its counter string widens).
- `dns.tf`, `cf-tunnel-ssh-bridge/action.yml`, the 11 `connection { host }` blocks — **P2b is cut**; these move to the I2 issue.
- `ADR-096` Decision text — precedent, not implicated (an optional premise note is permitted; see P4).
- `ADR-082`, `WEB_HOST_PRIVATE_IPS`, the registry-bridge origin-discriminator — cut as adjacency / instrumentation for a hypothesis P1 retires.

## Files to Create

| File | Purpose |
|---|---|
| `knowledge-base/engineering/architecture/decisions/ADR-113-*.md` | P4 — the tunnel-topology decision |
| `scripts/followthroughs/zot-mirror-connector-6416.sh` | P5 — soak probe |

## Acceptance Criteria

> **v2:** v1 had 14 ACs, six of which asserted *the absence of work* (a diff, not a post-condition).
> Cut: v1's AC3/AC6/AC10/AC11/AC2c and AC8's second half. **Every retained AC was re-derived by
> RUNNING it against the current tree** — v1's AC6 returned **7, not 2**, and v1's T10 retro-proof
> measured **0**. An acceptance criterion that fails on `origin/main` isn't a criterion.

### Pre-merge (PR)

1. **AC1 (RED→GREEN, no double-count).** Using the **existing** `tfplan-hcloud-server-create.json`
   (measured `host_creates=1`), the guard HALTs; against
   `tfplan-hcloud-server-location-replace.json` (`["delete","create"]`) `host_creates == 0` **and**
   `resource_deletes == 1`. `bash tests/scripts/test-destroy-guard-counter-web-platform.sh` fails
   before the jq change, passes after.
2. **AC2 (T18 resolved).** T18 no longer asserts that a per-PR `hcloud_server.web["web-2"]` create
   is legitimate; its name/comment no longer say "a legit new host". The suite is internally
   consistent with the guard.
3. **AC3 (fail-closed, not fail-open).** `host_creates` appears in the numeric-validation
   conditional at `apply-web-platform-infra.yml:424-427`; a non-numeric value aborts with
   `::error::`.
4. **AC4 (no ack bypass).** The HALT is evaluated **outside** the `destroy_count` sum (so
   `[ack-destroy]` cannot bypass it), and the `::error::` text names a **per-type** remediation —
   including that `hcloud_server.registry` / a new `web-3` have **no dispatch path** and require the
   operator-local full apply **before** the code merges.
5. **AC5 (P3 reaches the Slack line).** `zot_mirror` has **no** `if:` gate; it branches internally
   on `steps.zot_bridge.outcome == 'failure'`; and `reusable-release.yml:846` still reads
   `steps.zot_mirror.outputs.mirror_status` (i.e. the id the Slack append consumes is preserved).
   *v1's AC — "a step exists writing `mirror_status=degraded`" — was a proxy that passes while the
   Slack ⚠️ stays silent.*
6. **AC6 (ADR-096 not reversed).** `continue-on-error: true` is still present on the `zot_bridge`
   and `zot_mirror` steps. **Verify by reading those two steps** — *not* `grep -c` over the file,
   which returns **7** (`:364, :656, :678, :818, :834`, …) and cannot express the scope.
7. **AC7 (stale targets gone).** `grep -c -- '-target=cloudflare_record.web_host'
   .github/workflows/apply-web-platform-infra.yml || true` returns **0** (it returns **1** today).
   *v1 also asserted `git grep '"web_host"' -- '*.tf'` → 0, which already passes on `origin/main`
   and proves nothing — cut.*
8. **AC8 (ADR + C4).** `ADR-113-*.md` exists (**re-check after any `/ship` renumber and sweep this
   plan + `tasks.md` + AC8/AC9 together**); `model.c4` contains a `tunnel -> zotRegistry` edge;
   `c4-code-syntax.test.ts` + `c4-render.test.ts` pass.
9. **AC9 (ADR amendments).** ADR-008 is `superseded-in-part` by ADR-113; ADR-068 gains the
   generalization paragraph and ADR-113 cites its per-host-tunnel rejection. **ADR-096's `##
   Decision` text is unchanged** *(v2: relaxed from v1's `git diff ADR-096 == 0`, which would have
   forbidden correcting its falsified singular-connector premise).*
10. **AC10 (audit + I2 issues filed).** Both exist with the labels named in P4.
11. **AC11 (soak enrollment).** The probe script exists, is executable, and the tracker carries the
    `soleur:followthrough` directive + `follow-through` label.

### Post-merge (agent-run — NOT operator)

12. **AC12 (attach proof).** The `warm-standby` run's log contains `attach proof OK:
    hcloud_server_network.web["web-2"] present in state`. **On RED, apply P1's escalation rule** —
    a RED verify with a green apply means the attach LANDED.
13. **AC13 (packets, not state).** `hcloud server describe soleur-web-2 -o json | jq -r
    '.private_net[0].ip'` returns `10.0.1.11` (declaration) **AND** ≥5 consecutive registry-bridge
    runs succeed (packets). *v2: v1's evidence options were unfalsifiable — you cannot select the
    replica, cannot observe which answered (no outputs contract), and the fan-out proves
    **web-1 → 10.0.1.11:9000**, the wrong direction. N≥5 is the honest statistical form.*
14. **AC14 (end-to-end).** **≥5 consecutive** releases show `zot_bridge` success and `zot_mirror`
    not skipped, with no `zot mirror degraded`. *v2: a single green release passes at ~50% by luck
    even with web-2 fully broken.*

**Automation-feasibility:** every post-merge AC is `gh`/`hcloud`-CLI automatable. **No step in this
plan is operator-gated**, so there is deliberately no `### Post-merge (operator)` section.

## Domain Review

**Domains relevant:** Engineering (CTO)

### Engineering

**Status:** reviewed — CTO (Phase 2.5) + terraform-architect (2.8) + a 5-agent plan-review panel
(DHH, Kieran, code-simplicity, architecture-strategist, spec-flow) + a scoped `fable` advisor
consult (Step 4.5). All rulings applied.

| Source | Ruling / finding | Disposition |
|---|---|---|
| CTO Q1 + terraform-architect | Guard, don't break the dependency (`server_ids` is a genuine data dependency; `cloudflare_record.app` births web-2 anyway; provider 1.63.0 forbids >1 attachment per firewall) | Applied — P2 |
| CTO Q2 | One tunnel; `localhost:` is the category error; per-hostname ingress does **not** pin a connector | Applied — ADR-113 |
| CTO Q3 | Addressing inline, audit separate | **Overridden** by DHH + code-simplicity + advisor (below): the coupling premise was false. Audit stays separate; addressing → I2 issue |
| CTO Q5 | Threshold `single-user incident` (false-assurance multiplier) | Applied |
| DHH (P0) | **P2b does not work** — the `-d "$SERVER_IP"` NAT scope; and the coupling argument is contradicted 165 lines earlier | Applied — P2b **cut** |
| DHH / code-simplicity | 6 ACs assert absence-of-work; ADR-107/113 drift; Architecture section writes ADR-113 twice | Applied — ACs 14→11 (+ v1's AC3b/3c/3d dissolved with P2b); ordinal swept; section trimmed |
| code-simplicity | The `hostname` assertion is the only **runtime evidence** and is wanted even if (a) ships; §Observability contradicted §P2 | Applied — P2c; failure_modes rewritten |
| Kieran (P0, measured) | `_run_gate` = 3 counters + sum + rc (not 5); ~54 sites widen; `:235` vs `:238`; **T18 inverts**; AC1's fixture already exists; AC6 returns **7**; T10 retro-proof is **0** | Applied — P2 harness block + ACs |
| architecture-strategist (P1-4) | **I1 is falsified by construction** — the token is granted at server-create, the attach always lands after; `host_creates` does not enforce I1 | Applied — I1 restated as a **runtime** precondition; **no phase claims to enforce it** |
| architecture-strategist (P2-7) | **ADR-068 already states the finding and already rejected per-host tunnels**; AC8 over-constrained ADR-096 | Applied — P4 reframed; AC9 relaxed |
| architecture-strategist (P1-3) | **`deploy.` IS on the tunnel path**; P1 corrodes AC12/AC14's evidence | Applied — H7 verified; AC13/AC14 → N≥5 |
| architecture-strategist Q1(b) | Attach-proof runs **before** verify ⇒ RED job can mean a **landed** attach; reflexive recreate would destroy it | Applied — P1 escalation rule; P0.3 cut |
| spec-flow (#4, #9) | Guard ships **fail-open** without the numeric validation; remediation dead-ends for registry/web-3 | Applied — AC3, AC4 |
| `fable` advisor (Step 4.5) | Decouple; enforce I1 directly via a connector gate (one replica ⇒ deterministic today) | Applied — candidate (b), the leading I2 shape (and the only one that makes I1 well-formed) |

**Capability gaps:** none. **No DB writes** — the WAL clause of `hr-observability-as-plan-quality-gate` does not apply.

### Product/UX Gate

**Not applicable.** The mechanical UI-surface scan over `## Files to Edit` / `## Files to Create`
matched **no** UI-surface path (`.tf`, `.yml`, `.jq`, `.sh`, `.c4`, `.md`, `.json`, `.ts` tests
only). Product assessed **NONE** — infrastructure/CI change, no user-facing surface. No wireframe
required (`wg-ui-feature-requires-pen-wireframe` does not fire). `cmo` / `ux-design-lead` not
activated by the independent relevance read (no market/GTM/brand/user-copy or visual content).

### GDPR / Compliance

Gate **not** invoked: no regulated-data surface (no schema, migration, auth flow, API route, or
`.sql`); none of the (a)-(d) expansion triggers fire. **Noted, not a gate:** `var.web_hosts`
carries a GDPR-residency validation (`contains(["nbg1","fsn1","hel1"])`, CLO T-1, GA-blocking);
this plan does not alter it and web-2's fsn1 remains EU.

## Open Code-Review Overlap

**None.** 62 open `code-review` issues fetched; every `## Files to Edit` / `## Files to Create` path
checked against issue bodies via `jq --arg path … | contains($path)`. Zero matches.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| The `warm-standby` dispatch re-swaps web-1 (sole live origin) | Happy path = the same mechanism every release performs, at the **current** tag, under the `web-1-swap` mutex; `reboot_updates == 0` + `ignore_changes[placement_group_id]` keep a reboot out. **Failure path differs:** up to **2** swap cycles (`FRESH_BOOT_WINDOW_S=600`, `DEGRADED_RETRY_MAX=1`) then terminal exit 1. |
| A RED warm-standby run is misread as "attach failed" → reflexive `web-2-recreate` **destroys a good attach** | P1's escalation rule: read the **attach-proof step** first; recreate only if the APPLY failed. |
| **P1 corrodes its own acceptance evidence (H7)** — after the attach, web-2 answers `deploy-status` successfully and the verify goes nondeterministic across two hosts | AC13/AC14 use **N≥5** rather than a single green run; `HEALTH_URL` (`app.soleur.ai`) is the only single-origin signal. Candidate (b) resolves it structurally; tracked in the I2 issue. |
| `host_creates` wedges **every** merge on a legitimate `web-3` (no dispatch creates it) | AC4's per-type remediation names the operator-local full apply **before** the code merges. "Does not wedge the repo" holds only for today's 2-host state — stated, not assumed. |
| Guard ships fail-open on a jq hiccup | AC3 — `host_creates` in the numeric validation (`:424-427`), whose own comment documents exactly this failure mode. |
| The T18 change looks like "weakening a test" to a reviewer | It is the codified belief this plan overturns. AC2 makes the intent explicit and the PR body must say so. |
| P2c turns a silent wrong-host write into a ~50% red apply | Priced and accepted — a red apply beats a green lie. Bounded re-dial retry is the escape hatch if it bites. |
| ADR-113 ordinal collides with a sibling PR | `/ship`'s ADR-Ordinal Collision Gate re-verifies against `origin/main`; on renumber sweep plan + `tasks.md` + AC8/AC9 **in the same edit**. |

## Alternatives Considered

| Option | Verdict | Why |
|---|---|---|
| A tunnel per backend (the operator's framing) | **Rejected** | Premise inverted — we already have one tunnel, and one tunnel is *right* (CF load-balancing across replicas is the contract). Per-backend tunnels multiply tokens/Access apps/DNS/cloudflared **and do not solve determinism**. **ADR-068:378-384 already rejected the adjacent shape** (risks REPLACING the live tunnel; `config_src` forces replacement ⇒ deploy-path outage). |
| **v1's P2b — per-host `ssh-web-*` ingress + repointed connection blocks** | **CUT (3× P0)** | Breaks the `-d "$SERVER_IP"` NAT match ⇒ every provisioner dies ⇒ **main wedged**; its coupling premise was contradicted by this plan's own H5; "additive" was additive on the wrong axis (`connection.host` is a swap); and it re-proposed an ADR-068-rejected shape. → **I2 issue** (candidate (a), disfavoured). |
| Per-host hostnames pointed at `ssh://localhost:22` | **Rejected — DOES NOT WORK** | The hostname selects the **tunnel**; CF then load-balances. Recorded as a normative anti-pattern in ADR-113. |
| Dedicated cloudflared on the zot host | **Rejected** | ADR-096 §Decision: "no cloudflared on the registry host". Reversing needs its own ADR and expands the deny-all host's blast radius. |
| Allowlist the leaf (`hcloud_server_network.web`) | **Rejected — most expensive wrong answer** | Needs an ADR-068 amendment + **four coupled hand-maintained sets** (`OPERATOR_APPLIED_EXCLUSIONS` `:498`, `MOVED_OPERATOR_CONSUMED` `:955-960`, the subset test `:1021`, the warm-standby guard `:1112`), weakens the #5877 moved-block anchor (`:402-411`), and **legitimizes per-PR host creation** — leaving the unfirewalled-first-boot race (P4b#1) intact. |
| Break the transitive pull in `firewall.tf` | **Rejected — dead twice over** | `cloudflare_record.app` births web-2 regardless; provider **1.63.0** forbids >1 `hcloud_firewall_attachment` per firewall; and splitting it destroy+creates the live attachment ⇒ **a window where web-1 has no firewall**. |
| Force the leaf non-leaf via `depends_on` | **Rejected** | Verified viable ("5 to add") but a backwards edge a maintainer deletes as redundant — and it legitimizes per-PR host creation. |
| A static guard ("no allowlisted target may reference `hcloud_server.web`") | **Rejected** | `cloudflare_record.app` **must** reference it and **must** be allowlisted. The property is **plan-shaped, not source-shaped** ⇒ the jq filter is the right home. |
| Make the zot mirror blocking (ask #3 as literally worded) | **Rejected** | Reverses ADR-096's explicit Decision. The real gap is the **skipped** degraded emit — fixed in P3 without touching the contract. |
| Remove the `registry.` ingress rule as "stale" | **Rejected** | #6357 already disproved this; it is the live ADR-096 push path. |

**Deferral tracking:** the I2 issue and the audit issue are filed in this PR (AC10). A deferral
without a tracking issue is invisible.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6.
- **`-target` is transitive on DEPENDENCIES, not DEPENDENTS — and at RESOURCE, not INSTANCE, granularity.** A reference to `hcloud_server.web["web-1"]` pulls **web-2** too. Any allowlisted resource referencing an `OPERATOR_APPLIED_EXCLUSIONS` member silently drags it in, while its own leaf dependents stay behind.
- **A Cloudflare Tunnel hostname selects the TUNNEL, not the CONNECTOR.** Per-host hostnames pointed at `localhost:` are a **no-op**. If a "route to a specific host" fix does not change the ingress **service** address, it changes nothing.
- **A guard's own header can document its blind spot.** `reboot_updates` says it "never false-fires on a CREATE (web-2 add)". Read a guard's stated non-goals before asking "would this have caught X?".
- **A test can encode the belief you are overturning.** T18 asserts a per-PR web-2 create is "a legit new host" — the exact shape this plan HALTs. Before adding a guard, grep the suite for a test that *blesses* the thing you are about to forbid; updating it is the point, not collateral.
- **A skipped step emits nothing.** `continue-on-error: true` + a downstream `if: steps.X.outcome == 'success'` is a *silence* generator: the downstream step's own emitter never runs. Audit the **skip** path, not just the failure path.
- **Step outputs are namespaced by step id.** Moving an emitter to a new step orphans every consumer reading `steps.<old_id>.outputs.*`. Prefer branching **inside** the existing step over adding a sibling.
- **`terraform state list` proves declaration, not packets.** A fresh host can boot with its private NIC down while the control plane says "attached".
- **A hazard documented on one job is not defended on its sibling.** `apply-web-platform-infra.yml:747-752` spells out the transitive-pull hazard and defends `warm_standby` with two layers; `apply` inherited it with neither. A comment's presence proves the trap is **known**, not **handled**.
- **When a plan asserts what a command returns, run it.** v1's AC6 returned 7 (not 2) and its "free retro-proof" measured 0 — both one execution from being caught.
- **`grep -c` returning 0 exits 1** — an AC using it aborts a `set -e` verification script *on success*. Use `|| true` or `test "$(…)" -eq 0`.
- Do not prescribe exact learning filenames with dates in `tasks.md` — dates drift across session boundaries.
