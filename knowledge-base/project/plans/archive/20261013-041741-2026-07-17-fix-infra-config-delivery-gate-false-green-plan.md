---
title: "fix: the infra-config gate asserts a count over a coin-flipped read"
date: 2026-07-17
type: fix
issue: 6594
lane: cross-domain
brand_survival_threshold: aggregate pattern
requires_cpo_signoff: false
related_issues: [6425, 6441, 6440, 6465, 6466, 6482, 6483, 6525, 6528, 6565, 6577, 6497, 6178, 6416]
related_adrs: [ADR-114, ADR-068, ADR-008]
status: draft
revision: v2 (post 6-agent plan-review + live telemetry)
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!--
  Phase 2.8 reviewed. The ONLY infrastructure change is a Terraform-managed Cloudflare tunnel
  ingress `service` value in apps/web-platform/infra/tunnel.tf (see `## Infrastructure (IaC)`).
  NO manual provisioning, NO SSH, NO dashboard step, NO host mutation is prescribed. Every
  `systemctl` / `cloudflared service install` token below is DESCRIPTIVE — it documents existing
  in-repo behavior that constrains phase ordering, or appears in `## Alternative Approaches
  Considered` as an approach this plan REJECTS. Grep hits are quotations, not instructions.
-->

# fix: the infra-config gate asserts a count over a coin-flipped read

> **v2.** Rewritten after a 6-agent review panel and live telemetry. Three of v1's own claims were
> measured false and are retracted in-place (D3, D7, and the "#5515 edge closes the race" reading).
> **Retractions are marked, not deleted** — a plan that silently drops its errors teaches nothing.
>
> **Lane:** `specs/feat-one-shot-6594-infra-config-freshness-gate/spec.md` does not exist, so `lane:`
> could not be carried forward. Defaulted to `cross-domain` (TR2 fail-closed).

## Enhancement Summary

**Deepened:** 2026-07-17 · **Panel:** dhh-rails-reviewer, kieran-rails-reviewer,
code-simplicity-reviewer, architecture-strategist, spec-flow-analyzer, cto (6 parallel) + 4 research
agents + live telemetry (Better Stack ClickHouse, Cloudflare API, Hetzner API, GitHub Actions logs).

**Gates run:** 4.4 precedent-diff · 4.5 network-outage (fired; L3→L7 in `## Hypotheses`) ·
4.55 downtime/cutover (fired; `## Downtime & Cutover`) · 4.6 user-brand (pass) · 4.7 observability
(pass, 5/5 fields, ssh-free) · 4.8 PAT-shaped (pass) · 4.9 UI wireframe (skip, no UI surface).
All 7 cited AGENTS rule IDs verified **active**; all 24 cited issues/PRs resolved **live**; all
knowledge-base citations Glob-verified.

### Key improvements over v1

1. **Two PRs, not one — mechanical, not stylistic.** Both applying workflows share
   `group: terraform-apply-web-platform-host` (`cancel-in-progress: false`), which **serializes but
   does not order**. v1 stated the ordering as prose with no enforcing mechanism; in one PR the nonce
   push could fire against the un-repointed tunnel and coin-flip anyway.
2. **The retry loop launders the coin flip.** The gate's 3-attempt loop re-issues a fresh `curl` per
   attempt (= a fresh connector selection) and `break`s on first pass — **any-of-3** semantics. An
   assert inside it means "retry until some host matches". Now terminal, outside the loop.
3. **Cut the freshness assert** (unanimous). Strictly dominated: its only unique catch is
   *content-matches-but-`start_ts`-is-old* — a no-op — while its own unique behavior is
   **false-failing**. And it is unimplementable as specified: the apply step pipes to the log with no
   `tee`/`$GITHUB_OUTPUT`, so the gate (a separate step) has no signal to gate on.
4. **Cut the `host_id` work** (unanimous). An *alternative* to the ingress pin, not a complement —
   and **circular**: the reporter is delivered by the pipeline it audits, so it is absent on the only
   run that matters. It also has no runtime source and three resolution outcomes, so a 3 s metadata
   blip would redden the gate with a wrong-host accusation **against the right host**.
5. **Folded in the `ssh.` repoint.** The `handler_bootstrap` bridge — the sole delivery path for the
   handler + `hooks.json` — rides `ssh.` → `ssh://localhost:22` → *whichever connector*. Pinning only
   `deploy.` leaves the control plane's other half coin-flipped.
6. **Replaced v1's confounded verification.** "≥2 network vantages" cannot be discharged (you cannot
   choose your colo) and post-repoint reads green either way. Now: **CF API config read**
   (authoritative) + `/hooks/deploy-status`'s **existing** `host_id` (corroborating).

### New considerations discovered

- **`ADR-114:122` calls fan-out "the cheapest fix … needing no `.tf` and no tunnel change".** v1
  dismissed it as "much larger" without citing it. Now quoted and rebutted on the merits (fan-out
  fixes the WRITE, not the READ; and it presumes web-2 should be converged — #6440's open question).
- **`model.c4:177-178` asserts "exactly ONE connector … INVARIANT enforced" — false in production.**
  A required C4 correction, not a maybe.
- **The #6416 in-band `hostname` tripwire may not exist.** `ADR-068:413` and #6440's "safe to run"
  both depend on it; a grep of the 12 `connection {}` inlines finds zero host-identity assertions.
  **Phase 0.1 must measure this** — if confirmed it is a *third* instance of the same meta-defect and
  the most consequential (a wrong-host bridge landing would write web-1's config to web-2 silently).
- **`depends_on` does NOT close the nonce-1 race** — the edge landed 2026-06-18 (#5516); the race
  happened 2026-07-10 (#6313). A review claim to the contrary was refuted by `git log -S`.
- **web-2 freezing out of infra-config is consistent with the recorded architecture**, not new debt:
  `model.c4:178` says re-pooling needs full re-delivery (#6466), never a weight flip. Pinning
  converts *randomly drifting* → *deterministically frozen*, which is what makes #6440 tractable.
- **`image_pull_failed` (#6525) is a *pull* failure; `class=cred_store` (#6565) is a *login* failure.**
  Different code paths. **#6565 is blocked on #6528 — merged, and already live on the host** — so it
  is blocked on nothing, and this session measured the datum it was waiting for. See UC-1.
- **`host_name` telemetry is lying** (D-A) and **the dedicated inngest host may be dark** (D-B).
  Both surfaced by the UC-2 investigation; both filed, neither fixed here.

### Retractions (v1 claims measured false, kept visible)

| v1 claim | Reality |
|---|---|
| D3: "the inngest steer is impossible" → then "the operator was right" | **Both wrong in turn.** `host_name` is a `sed`-rendered Vector literal that a *colocated web host* also wears. The `--sdk-url 127.0.0.1:3000` argv settles it: machine `3f07b655` is a web host. **D3's conclusion stands; my challenge to it is withdrawn.** |
| D7: "#6565 is gated on this PR's instrument" | #6565 is gated on **#6528**, which is merged and live. |
| "#5515's edge closes the nonce-1 race" (raised at review) | The edge **predates** the race by 3 weeks. |

**The `host_name` flip-flop is the session's main lesson:** I used `_MACHINE_ID` as a discriminator
when it identifies *a* host but not *which* host — the exact "confirming probe that doesn't
discriminate" trap `2026-07-16-refuting-a-hypothesis-by-reasoning-while-its-discriminator-is-invisible.md`
names. The argv did discriminate.

## Overview

#6594 says the "Verify infra-config apply succeeded" gate passed while #6577's `ci-deploy.sh` never
reached prod, and proposes a freshness assert + a content assert + a `replace` input.

**The gate is broken and the content assert is the fix.** But the issue's diagnosis stops one layer
short, and two of its three proposals do not survive measurement:

> **`deploy.soleur.ai` is a Cloudflare Tunnel with TWO live connectors. The infra-config POST and
> the status read are load-balanced across them independently. The push is a coin-flipped WRITE,
> self-verified against a separately coin-flipped READ** — and the gate's 3-attempt retry loop
> re-selects a connector per attempt and breaks on the first pass, so it is an **any-of-3** read.

This is not new. **#6425 (OPEN, P1) predicted #6594 verbatim on 2026-07-15**: *"`/hooks/infra-config`
— a coin-flipped **WRITE**, self-verified against a *separately* coin-flipped read."* ADR-114
(**accepted**) marks this route **"Unguarded"** and its rule **I2** prescribes the fix.

### What ships

| # | Deliverable | Why |
|---|---|---|
| **1** | **Origin-relative ingress for `deploy.` AND `ssh.`** (`tunnel.tf`) | Makes the recovery **WRITE** land on web-1 deterministically, and de-randomizes the bridge. Config-plane only — **zero host writes**. Discharges ADR-114 I2. |
| **2** | **Content assert** — every non-templated delivered file hashes to the repo | The whole gate fix. An end-state invariant. Catches #6594 unaided. |
| **3** | **Recovery of #6577's `ci-deploy.sh`** via the existing redeploy-nonce | Precedented (#6178 ×2). Deterministic once (1) lands. |
| **4** | **ADR-114 amendment + C4 correction** | Three recorded facts are measured false. `model.c4:177` asserts *"exactly ONE connector … enforced"*. |

**Cut after review** (consensus of DHH + code-simplicity + Kieran, each independently):
**the freshness assert** and **the `host_id` payload work**. Rationale in Alternatives — both are
strictly dominated by the content assert, and each costs more than it buys.

**Out of scope, with tracked homes:** web-2 config divergence (#6440), host addressability (#6466),
cx33 capacity (#6482), drift noise (#6443), `image_pull_failed` (#6525 — **see UC-1**), the
`host_name` mislabel (**D-A**), the possibly-dark dedicated inngest host (**D-B**).

> **Two challenges to the operator's stated direction are persisted at
> `knowledge-base/project/specs/feat-one-shot-6594-infra-config-freshness-gate/decision-challenges.md`
> (UC-1 `image_pull_failed`, UC-2 the inngest steer). Neither is decided here.** `ship` renders them
> into the PR body + an `action-required` issue.

## The `host_name` trap — and a correction I had to make twice

**This section replaces a claim that appeared in two earlier drafts of this plan and is now
retracted. The flip-flop is recorded because the reasoning error is the lesson.**

Better Stack, 72h: all 34 `ci-deploy`-tagged rows — including every `class=cred_store` login failure
#6577's errno probes target — carry `_MACHINE_ID=3f07b65531ab48b9b02d013c6b08feba` /
`host_name=soleur-inngest-prd`. **Zero from any host labelled as a web host.** I briefly concluded
the errno target lives on the inngest host, and that the operator's steer was therefore right.

**That was wrong.** `host_name` is a **Vector-rendered string literal** — `vector.toml`'s
`@@HOST_NAME@@` sentinel, `sed`-substituted to the constant `soleur-inngest-prd` by
`inngest-bootstrap.sh` — **which also runs on a *colocated* web host** via `ci-deploy.sh`'s
`case "inngest")` arm. A colocated web host emits ci-deploy rows, runs `inngest-server.service`, and
self-labels as inngest, **all on one `_MACHINE_ID`** — reproducing every fact I had.
`soleur-host-bootstrap.sh` (#6396) documents this state verbatim and deliberately does not clobber it.

**`_MACHINE_ID` is real, but it does not say WHICH host.** The discriminator that settled it is the
running process's own argv:

| Source | `--sdk-url` |
|---|---|
| **Dedicated** inngest host — `inngest-host.tf:234` | `http://10.0.1.10:3000/api/inngest` (the web backend's **private IP**) |
| **Measured live** — `inngest-server.service` `_CMDLINE` | `http://127.0.0.1:3000/api/inngest` (**localhost**) |

`127.0.0.1` is only correct if inngest and the web app share a box (`inngest-bootstrap.sh:435`: *"the
server polls the **co-located** web-platform"*).

⇒ **Machine `3f07b655` is a WEB host running a colocated inngest, mislabelled `soleur-inngest-prd`.**

**Consequences — the plan gets stronger, not weaker:**

- **The `class=cred_store` failure is a web-host problem.** The issue body's Evidence #1 attribution
  was **correct**. My challenge to it is withdrawn.
- **The recovery (Phase 4) delivers the errno instrument to exactly the right host.** No retarget.
- **The operator's steer is not actionable, and D3 stands** — there is no delivery path for
  `ci-deploy.sh` to the dedicated inngest host, and none was ever designed: the `inngest-bootstrap`
  OCI image does not contain it, `cloud-init-inngest.yml` does not write it, `inngest.tf` has zero
  provisioners, and no workflow `-target`s an inngest resource. The operator's *concern* is still
  honored — see D3.

**Two real defects this surfaced. Both get their own issues; neither is fixed here.**

- **D-A — `host_name` telemetry is actively lying.** A web host reports itself as
  `soleur-inngest-prd`. **Every attribution built on `host_name` is suspect** — including #6425's
  reading that the false `inngest-down` alarms came from web-2. This *explains* the
  `host=soleur-web-platform` / `host_name=soleur-inngest-prd` conflict #6594's body flags as
  UNVERIFIED: it is a **mislabel, not a routing artifact**. (`host` is the shared Better Stack source
  name; `host_name` is the per-host discriminator — and it is wrong.)
- **D-B — the dedicated inngest host is DARK.** `soleur-inngest` (`cpx22`, `10.0.1.40`) is **running**
  (Hetzner API), yet **exactly one `_MACHINE_ID` ships journald** and it is the colocated web host.
  Zero rows from any dedicated-host-only unit (`inngest-redis`, `inngest-nftables`,
  `inngest-boot-phone-home`) — though a Vector allowlist gap is an alternative explanation, so this
  is **strongly-evidenced, not proven**. Consistent with #6536's "the host was dark" class. **If a
  colocated inngest and the dedicated inngest are both live, that is a double-scheduler condition
  and an escalation.** Whether that is so is **UNKNOWN** from off-host evidence.

**This does not disturb #6594.** web-1's `ci-deploy.sh` is stale (`2208300a` vs repo `c528baf1`) and
the gate lies about it — measured live, twice, and independent of every claim above.

## Premise Validation

Measured by me (`hr-no-dashboard-eyeball-pull-data-yourself`), not taken from the issue body.

| Premise | Verification | Verdict |
|---|---|---|
| Host records `ci-deploy.sh sha256=2208300a…`; merged `c528baf1` never landed | Live `GET /hooks/infra-config-status`; `git show 6413c4ea^:… \| sha256sum` → `2208300a6751a256…`; `6413c4ea:…` → `c528baf1e0abaf28…` | **Holds, exact — still true now** |
| `start_ts` = previous day 20:22Z, `files 15/15`, `exit_code 0` | `start_ts=1784233325` = `2026-07-16 20:22:05 UTC` | **Holds — every gate predicate is TRUE of a stale host** |
| 14 of 15 delivered files are verbatim repo files | Hashed all 14 against the repo: **all match**; only `ci-deploy.sh` diverges. `hooks.json` is the sole template render | **Holds — the content assert is implementable and would have caught this** |
| Terraform latched the failure as success | Apply log: `Apply complete! Resources: 1 added, 0 changed, 1 destroyed` | **Holds** |
| **Two live connectors** | CF API tunnel `6410c1ec`: `8c57fcd5` ver 2026.7.1 colos `fra*` (fsn1⇒web-2), `a281fb1b` ver 2026.3.0 colos `ams/hel` (hel1⇒web-1). Hetzner: `soleur-web-2` **running**, priv `10.0.1.11` | **CONFIRMED — the root cause** |
| **#6426's de-pool never took effect** | web-2 connector `run_at=2026-07-13T20:10:24Z`, still live; #6426 merged `2026-07-15T14:49:31Z`. Gate is construction-time; `ignore_changes=[user_data]`; #6482 blocks rebuild | **CONFIRMED — same meta-defect as #6594** |
| **The restart-race (#6178 nonce-1) explains #6594** | Apply log: only `deploy_pipeline_fix` replaced. `ci-deploy.sh` ∉ `handler_bootstrap.triggers_replace` ⇒ no bridge ⇒ no restart | **REFUTED by measurement** |
| **v1 claim: "#5515's `depends_on` closes the nonce-1 race"** (raised at review) | `git log -S`: edge added **2026-06-18** (#5516); nonce-1 race occurred **2026-07-10** (#6313). **The edge predates the race by 3 weeks and did not prevent it** | **REFUTED — the hazard is LIVE** |
| **v1 claim (D7): "#6565 is gated on this PR's instrument"** | #6565 is blocked on **#6528**, which is **MERGED**. Host's `ci-deploy.sh` already carries `_docker_login_failure_class` (×6) + `LOGIN_ERR` (×19). Only `errno_chars` (repo 8 / host 0) is #6577's delta | **REFUTED — #6565 is blocked on nothing** |
| **v1 claim (D3): "the inngest steer is not possible"** | See above — the target fires on the inngest host | **RETRACTED — the operator was right** |

## Hypotheses

`hr-ssh-diagnosis-verify-firewall` fires (the target set includes `infra_config_handler_bootstrap`,
which carries `connection { type = "ssh" }` + `remote-exec`). **L3→L7 discipline is what found the
cause** — the defect is at the routing layer; every service-layer hypothesis is refuted.

| Layer | Hypothesis | Verification | Verdict |
|---|---|---|---|
| **L3 routing** | POST and read land on different connectors | CF API: 2 connectors, colo-split fra vs ams/hel (above) | **CONFIRMED** |
| L3 firewall | Admin-IP drift / block | N/A — no connection failure; apply succeeded, POST returned 202 | **Refuted (N/A)** |
| L3 DNS | `deploy.` misresolves | 6/6 reads → HTTP 200, healthy tunnel | **Refuted** |
| L7 restart race | Bridge restarted the webhook under the push | Apply log — only one resource replaced (above) | **REFUTED by artifact** |
| L7 fail-open push | Script exits 0 on failed POST | `push-infra-config.sh:96-99` exits 1 on non-202 | **Refuted** |
| L7 handler died pre-state-write | Spawned, died before the final state record | **Not observable** — `start_ts` is written only in the final record | **UNKNOWN** |

> **Discipline note** (`2026-07-16-refuting-a-hypothesis-by-reasoning-while-its-discriminator-is-invisible.md`).
> REFUTED verdicts rest on **mechanical artifacts** (an apply log, a trigger set, a `git log -S`
> date) — never on reasoning about semantics. The one hypothesis whose discriminator is invisible is
> **UNKNOWN**. My `/hooks/*` probe ran from **my colo**, which pinned to web-1 6/6: that is evidence
> *two origins exist*, and **not** evidence about which host the runner's POST reached. v1 violated
> this rule twice (D3, D7) by chaining issue numbers instead of measuring; both are retracted above.

## Architecture Decision (ADR/C4)

### ADR — amend ADR-114 (three items)

The headline is **not** "a missing assert". It is: **this codebase repeatedly records controls as
enforced that are inert on running hosts.** #6594 is an instance; so are items 1 and 3.

1. **I1 is inert.** ADR-114 + #6441 record #6426's gate as *"ENFORCED — substantively, not
   vacuously"*. **Measured false** (Premise Validation). A construction-time gate cannot affect a
   running host; `ignore_changes=[user_data]` + #6482 mean it never will. I1 currently rests on
   nothing but a `*/15` census alarm (#6483).
2. **I2's antecedent is discharged** for `deploy.` **and** `ssh.` by this plan. Record that
   origin-relative ingress **restores** the availability the de-pool traded away and is **not**
   blocked by #6482.
3. **The #6416 in-band `hostname` tripwire is unsubstantiated — VERIFY FIRST (Phase 0.1).**
   `ADR-068:413` claims *"Each of the 12 now carries an in-band `hostname` tripwire (#6416) so a
   wrong-host landing fails the apply loudly"*, and #6440's "safe to run" depends on it. Review
   grepped `server.tf`'s 12 `connection {}` blocks and found **zero** host-identity assertions; the
   only `#6416` artifact is `host_creates`, a **plan-time** guard. **If confirmed, this is a third
   instance of the same meta-defect, it is the most consequential (a wrong-host bridge landing would
   write web-1's config to web-2 *silently*), and both ADR-068 and ADR-114 carry a false enforcement
   claim.** Recorded as strongly-evidenced, **requiring one confirming measurement** — not refuted by
   reasoning, and not asserted without it.

**Rebut, do not route around, ADR-114's own recommendation.** `ADR-114:122` says the *"**cheapest
fix** mirrors ADR-068 Option B — fan out `/hooks/infra-config` to peers … **needing no `.tf` and no
tunnel change**"*. v1 called fan-out "much larger" without citing this. The amendment must quote and
answer it: **fan-out fixes the WRITE but not the READ** (`deploy-status` / `inngest-liveness` stay
coin-flipped), and it **presumes web-2 should be converged** — which is #6440's open question.

### C4 — a required correction, not a maybe

`model.c4:177-178` asserts *"ONE tunnel, exactly ONE connector"* and *"INVARIANT (ADR-114 I1,
**enforced #6425**)"*; `model.c4:375` says the edge *"is deterministic ONLY because exactly one host
does"*. **Both are false in production today** (2 live connectors, measured). Read all three
`.c4` files, correct the invariant and the Tunnel→host edge, ensure web-2 is modeled, and run
`c4-code-syntax.test.ts` + `c4-render.test.ts` (a `view include` on an undefined element fails
there, not at `tsc`).

## Infrastructure (IaC)

### Terraform change

One resource, two ingress rules, in `cloudflare_zero_trust_tunnel_cloudflared_config.web`:

```hcl
# ADR-114 I2: origin-relative, NOT connector-relative. Whichever replica answers must proxy to
# web-1 — the only host that can serve these routes (#6425, #6594, Ref #6441).
service = "http://${var.web_hosts["web-1"].private_ip}:9000"   # deploy.<base>  (was localhost:9000)
service = "ssh://${var.web_hosts["web-1"].private_ip}:22"      # ssh.<base>     (was localhost:22)
```

- **`ssh.` is folded in** (review P0-1): the `handler_bootstrap` bridge — the **sole** delivery path
  for the handler + `hooks.json` — rides `ssh.` → `ssh://localhost:22` → *whichever connector*.
  Pinning only `deploy.` would leave the control plane's other half coin-flipped. Same file, same
  resource, same apply, same risk profile. ADR-114:191's *"do NOT repoint the 12 `connection { host }`
  blocks"* is about `connection.host`, **not** the ingress `service`; #6441 §1 shows the service
  repoint needs **no NAT rework** (the runner still dials the public `SERVER_IP`).
- **No `local`** — `tunnel.tf` has no `locals` block, and `var.web_hosts["web-1"].private_ip` reads
  fine inline. (v1's `local.deploy_origin` is cut; and the cited precedent `zot-registry.tf:40`
  actually *hardcodes* `10.0.1.30` — using the var is **better** than the precedent, so don't claim
  the precedent endorses it.)
- **The `:9000` / `:22` ports remain literals.** Flagged honestly: this is a hardcode against the
  plan's own rule. `webhook.service` binds `-ip 0.0.0.0` with the port in its own config; deriving it
  costs more than it buys. Named here so it is a decision, not an oversight.

**Phase 1's precondition — stated, because it is load-bearing:** web-1's webhook is reachable at
`10.0.1.10:9000`. Evidence: `webhook.service` binds `-ip 0.0.0.0`; `firewall.tf` allows only
22/80/443/icmp inbound (so 9000 is public-denied but open on the private net); and `ci-deploy.sh`
already dials `http://${peer}:9000/hooks/deploy-peer` cross-host today.

### Apply path — resolved, not deferred

- `cloudflare_zero_trust_tunnel_cloudflared_config.web` has **no `lifecycle` block** (the
  `ignore_changes = [secret, config_src]` is on the **tunnel** resource — a different resource).
- It **is** `-target`-ed by `apply-web-platform-infra.yml`; `tunnel.tf` matches its path filter.
- ⇒ **A merge auto-applies.** The merge IS the authorization. `[ack-destroy]` never fires — a
  `service` string change is an in-place update.

> **⚠️ A one-line `service` edit is a zero-friction production write to the control plane.** Phase
> 1.2's plan review is load-bearing.
>
> **Rollback is viable** (v1 overstated this — corrected): `tunnel.tf` is applied by
> `apply-web-platform-infra.yml` via the **Cloudflare API**, not through the `deploy.` tunnel. Its
> SSH-bridge step uses the `ssh.` rule. So `revert → merge → apply` restores the ingress even with
> `deploy.` fully dead. What is unavailable meanwhile is `apply-deploy-pipeline-fix.yml` — an
> availability loss, not a trap.

### Drift safeguards

- **AC: `terraform plan` shows `0 to destroy` and no `hcloud_server` create.** Cheap, and #6482 makes
  a `cx33` destroy unre-placeable. (Honest note: `var.web_hosts` is a variable with a default and
  creates **no graph edge** to `hcloud_server.web`, so this is a guard, not the load-bearing gate v1
  billed it as.)
- **#6483 stays open and stays true** — web-2 remains pooled. Comment that `deploy.`/`ssh.` are now
  non-harmful.
- **Evidence for #6440** (found in passing, do not fix here): `terraform_data.registry_insecure_config`
  hardcodes `host = hcloud_server.web["web-1"].ipv4_address`, so the running-host path for
  `docker-daemon.json` converges **web-1 only** — while `cloud-init.yml` claims running hosts get it
  via that resource. True for web-1 only.

## Downtime & Cutover

Gate 4.55 fires: the change is **deploy/router class** — a tunnel ingress restructure. Default is
zero-downtime and this plan meets it, but the reasoning is recorded rather than assumed.

**The offline-inducing operation:** none. The change is an **atomic Cloudflare config-plane update**
to `cloudflare_zero_trust_tunnel_cloudflared_config.web`. No host is powered off, replaced, rebooted,
or restarted. No `hcloud_server`, volume, or attachment is touched (AC: `terraform plan` shows
`0 to destroy` and no `hcloud_server` create). No DB lock class applies — there is no migration.

**Surface affected:** `deploy.soleur.ai` + `ssh.soleur.ai` — the **management plane only**.
`app.soleur.ai` is a direct CF-proxied A record to web-1 (`dns.tf:16`) and **never traverses this
tunnel**, so no user-serving surface is in scope and no user-visible downtime is reachable.

**Zero-downtime path (the default, and what ships):** Cloudflare applies the new ingress config to
connectors without dropping the tunnel. In-flight risk is bounded to requests crossing the config
swap on the management plane — a CI run at most, which retries. **No drain, no blue-green, and no
maintenance window is required**, because there is no serving surface to drain.

**Availability is IMPROVED, not traded.** Today `deploy.`/`ssh.` answer from a **randomly selected**
connector, and web-2 cannot correctly serve either route (it has no `inngest-inventory.sh` at all —
#6425). The status quo is not "available"; it is "answers, sometimes wrongly". Pinning converts
*silently-wrong* → *correct*. #6441 makes the same point: origin-relative ingress **restores** the
availability the #6426 de-pool traded away.

**Residual risk + rollback.** A wrong `service` value breaks the management plane (not users).
Rollback is a one-line revert that **also auto-applies**, and — verified — it does **not** depend on
the surface it repairs: `tunnel.tf` is applied by `apply-web-platform-infra.yml` through the
**Cloudflare API**, not through the `deploy.` tunnel. What is unavailable in the interim is
`apply-deploy-pipeline-fix.yml` (its POST and gate both need `deploy.`) — an availability loss on a
management plane, not a trap. **No operator sign-off is required for a zero-downtime config-plane
change**; PR-A's `terraform plan` review is the gate.

## Observability

```yaml
liveness_signal:
  what: "apply-deploy-pipeline-fix.yml 'Verify infra-config apply succeeded' — asserts every
         non-templated FILE_MAP dest's recorded sha256 equals the repo file at the applied SHA"
  cadence: "every merge touching a deploy_pipeline_fix trigger file (paths-filtered push)"
  alert_target: "workflow failure -> GitHub Actions run failure (blocking step)"
  configured_in: ".github/workflows/apply-deploy-pipeline-fix.yml"
error_reporting:
  destination: "GitHub Actions ::error:: naming the diverging file (content_mismatch:<dest>)"
  fail_loud: true
failure_modes:
  - mode: "delivery landed stale/partial content at the same file count (the #6594 bug)"
    detection: "recorded sha256 != repo file hash for any non-templated FILE_MAP dest"
    alert_route: "gate FAILs naming the file; terminal, evaluated OUTSIDE the retry loop"
  - mode: "read answered by the wrong connector"
    detection: "structurally removed by Phase 1 (origin-relative ingress)"
    alert_route: "n/a — closed by construction, not by an assert"
  - mode: "no prior apply / corrupt state sentinel (exit_code -2/-3, no files[])"
    detection: "sentinel fixture; gate FAILs rather than no-opping on an absent files[]"
    alert_route: "gate FAILs"
  - mode: "handler spawned but died before writing state"
    detection: "UNKNOWN today — blind surface; tracked follow-up"
    alert_route: "n/a — a recorded gap, not a claim"
logs:
  where: "GitHub Actions run log; host journald -> Vector -> Better Stack"
  retention: "per Better Stack plan"
discoverability_test:
  command: >
    HMAC=$(printf '' | openssl dgst -sha256 -hmac "$WEBHOOK_SECRET" | sed 's/.*= //');
    curl -s -H "X-Signature-256: sha256=$HMAC" -H "CF-Access-Client-Id: $ID"
    -H "CF-Access-Client-Secret: $SECRET"
    https://deploy.soleur.ai/hooks/infra-config-status | jq '{start_ts, files}'
  expected_output: "every files[].sha256 matches the repo file of the same basename"
```

**No `ssh`** (`hr-no-ssh-fallback-in-runbooks`). Verified: I ran this exact shape to produce the
live evidence above.

### 2.9.2 — blind surface

`infra-config-apply.sh` writes `start_ts` only in its **final** state record, so a handler that
spawns and dies emits nothing — the UNKNOWN hypothesis has no discriminator. A "handler started"
beacon would supply one, **but it edits `infra-config-apply.sh`, which is in
`handler_bootstrap.triggers_replace`, which re-fires the bridge restart — the nonce-1 race, which
the timeline above proves the `depends_on` edge does NOT close.** Deferred to a follow-up issue,
sequenced after the recovery. `wg-defer-only-after-inline-triage`: the triage is that hazard.

## User-Brand Impact

**If this lands broken, the user experiences:** nothing directly — `app.soleur.ai` is a direct
CF-proxied A record to web-1 (`dns.tf:16`) and never traverses this tunnel. The harm is compounding
and indirect: **every host-script fix, including security fixes, can silently fail to land while CI
reports green** — three instances in eight days (#6577, #6426, #6594 itself).

**If this leaks:** no new exposure. The change narrows a tunnel origin from `localhost` to an RFC1918
address. No secret added, moved, or logged; the gate prints hashes, never payload bytes.

**Brand-survival threshold:** `aggregate pattern` — no single-user incident is reachable from this
diff; the risk is the pattern. The diff touches `infra/**` + `.github/workflows/**`, so preflight
Check 6 scans it; section present, threshold a valid enum ⇒ no scope-out bullet needed.

## Domain Review

**Domains relevant:** Engineering. Product/UX **NONE** — no `## Files to Edit` path matches the
UI-surface globs; the mechanical override does not fire. Legal/Finance/Marketing/Sales/Support/
Operations: no implications (internal management plane; no user-data, vendor-cost, or comms surface).

**Panel run (6 agents):** dhh-rails-reviewer, kieran-rails-reviewer, code-simplicity-reviewer,
architecture-strategist, spec-flow-analyzer, cto. **All findings folded into v2**; the two that
touch operator-stated scope are persisted as UC-1/UC-2 rather than applied.

## Open Code-Review Overlap

`gh issue list --label code-review --state open` against this file list: **None.**

| Issue | Disposition |
|---|---|
| **#6441** | **Fold in the I2 service repoint for `deploy.` + `ssh.`** — `Ref`, not `Closes`. Comment narrowing #6441 to the I1 residual. |
| **#6425** | **Ref, do not close.** web-2 stays pooled; the routes become deterministic. |
| **#6483 / #6440** | **Acknowledge** + contribute the `registry_insecure_config` evidence to #6440. |
| **#6525 / #6400 / #6560** | **UC-1.** Post the pull mechanics to #6525. Do not fold in. |
| **#6565 / #6497** | **Post the measured `class=cred_store` datum to #6565** — it is unblocked *now* (#6528 is merged and live on the host). Not gated on this PR. |
| **#6465** | 4th-`resolve_host_id`-copy trigger — **moot**, `host_id` is cut. Note it. |
| **#6466 / #6482** | **Defer.** Named as constraints. |
| **#6577** | **Ref.** Its instrument's target is the inngest host — **UC-2**, new issue. |

## Files to Edit

| File | Change | PR |
|---|---|---|
| `apps/web-platform/infra/tunnel.tf` | `deploy.` + `ssh.` ingress services → origin-relative | **A** |
| `.github/workflows/apply-deploy-pipeline-fix.yml` | Extract the gate adjudication to a sourceable script; add the content assert **outside** the retry loop | **B** |
| `apps/web-platform/infra/infra-config-gate.sh` *(new)* | The extracted, testable adjudicator | **B** |
| `apps/web-platform/infra/infra-config-gate.test.sh` *(new)* | The failing test + 3 fixtures | **B** |
| `apps/web-platform/infra/push-infra-config.sh` | Bump `redeploy-nonce` (recovery) | **B** |
| `knowledge-base/engineering/architecture/decisions/ADR-114-*.md` | Amend (3 items) | **B** |
| `knowledge-base/engineering/architecture/diagrams/{model,views,spec}.c4` | Correct the ONE-connector invariant | **B** |
| `apps/web-platform/infra/server.tf` | Fix the comment falsified by `push-infra-config.sh:25-31` (it claims the edge means *"the push never races a mid-flight listener restart"*; nonce-1 is the counterexample) | **B** |

## The failing test (`cq-write-failing-tests-before`)

**Zero prod access needed.** I captured the exact production payload that fooled the gate: 15/15,
`exit_code=0`, `files_failed=0`, `start_ts=1784233325`, `ci-deploy.sh sha256=2208300a…`. A real
artifact, not a guess. It contains **no secrets** — only paths and hashes (confirm at /work).

| Fixture | Pre-fix | Post-fix |
|---|---|---|
| **stale-same-count** (the real #6594 payload) | **PASS** ← the bug | **FAIL** `content_mismatch:/usr/local/bin/ci-deploy.sh` |
| **fresh-correct** (all hashes == repo) | PASS | **PASS** (no false-positive) |
| **sentinel** (`{"exit_code":-2,"reason":"no_prior_apply"}` — no `files[]`) | — | **FAIL**, not a silent no-op |

**Mutation-test each assert** (delete the subject; the suite must redden) **and confirm the runner
actually collects the file** — the cited learning's flagship harness shipped wired into zero runners.
"It will be picked up automatically" is false by default.

**Assert map derivation (do not hand-wave — v1 did):** the existing `sed`+`grep -c` yields a
**count**, not a mapping. `FILE_MAP` rows are `VAR|dest|mode|owner`; derive `basename(dest)` →
`apps/web-platform/infra/<name>`. This works for 14/15 and **breaks exactly on**
`/etc/webhook/hooks.json` (repo file is `hooks.json.tmpl`) — so the single exclusion is *derivable
from the template property*, not hardcoded. **Key off FILE_MAP, not `files[]`** — the handler appends
`orphan_hook_command` entries to `files[]` that have no repo counterpart. **Compare against the SHA
the apply ran from, not `HEAD`.**

## Implementation Phases

> **PR-A and PR-B are SEPARATE PRs. This is mechanical, not stylistic** (review P0, two agents
> independently): `tunnel.tf` applies via `apply-web-platform-infra.yml`; `push-infra-config.sh` via
> `apply-deploy-pipeline-fix.yml`. Both declare `group: terraform-apply-web-platform-host` with
> `cancel-in-progress: false` — which **serializes but does not order** them. In one PR the nonce
> push could fire against the un-repointed tunnel and coin-flip anyway. **v1 stated the ordering as
> prose with no enforcing mechanism; the split IS the mechanism.**

### Phase 0 — Preconditions

0.1 **Verify the #6416 in-band `hostname` tripwire exists** (ADR item 3). `grep` the 12
    `connection {}` provisioner inlines for `hostnamectl` / `/etc/hostname` / `uname -n` /
    `$(hostname)`. If absent, ADR-068 + ADR-114 + #6440 all carry a false claim → amendment item 3
    becomes the headline.
0.2 Confirm `var.web_hosts["web-1"].private_ip` renders `10.0.1.10`.
0.3 Confirm the runner + glob collect `infra-config-gate.test.sh` (plain bash — **no bats**; check
    `package.json scripts.test` + `bunfig.toml pathIgnorePatterns`).

### PR-A — Phase 1: pin the write and the bridge (no host write)

1.1 `tunnel.tf`: `deploy.` + `ssh.` services → origin-relative.
1.2 `terraform plan` — AC: `0 to destroy`, no `hcloud_server` create. **Review carefully: merging
    auto-applies with no further gate.**
1.3 Merge → auto-apply.
1.4 **Verify — two instruments, neither of them v1's confounded probe.** *(v1 said "≥2 network
    vantages"; retracted — you cannot choose your colo, and post-repoint both connectors proxy to
    web-1, so a stable reading is expected whether or not the repoint worked. It was a confounded
    experiment that would have read green either way.)*
    - **(a) Config plane (authoritative):** read the ingress back from the **Cloudflare API** and
      assert `service == "http://10.0.1.10:9000"` / `"ssh://10.0.1.10:22"`. Deterministic,
      vantage-free, scriptable.
    - **(b) Data plane (corroborating):** poll `/hooks/deploy-status` — which **already emits
      `host_id` today** (`cat-deploy-state.sh`, #6425) — N times before and after, and compare the
      `host_id` distribution. No new artifact, no circularity.

### PR-B — Phase 2: RED

2.1 Extract the gate adjudication from inline YAML into `infra-config-gate.sh`.
2.2 Commit the captured payload + the fresh-correct + sentinel fixtures.
2.3 **Confirm stale-same-count PASSES — reproducing #6594 — before any fix.**

### PR-B — Phase 3: GREEN

3.1 Content assert, per the derivation above, **outside the 3-attempt retry loop**.
    > **The retry loop launders a coin flip into a green** (review P0): the loop re-issues a fresh
    > `curl` per attempt = a **fresh connector selection** — and `break`s on the first attempt that
    > satisfies the predicate. That is **any-of-3** semantics. An assert placed inside it means
    > "retry until some host matches". A content mismatch must be **terminal**, never retried.
3.2 All three fixtures behave per the table. Mutation-test.

### PR-B — Phase 4: recovery (the ONE prod write; gated)

**Do not run before PR-A is verified.** Until the write is pinned, this is a coin flip.

4.1 Bump the `redeploy-nonce` in `push-infra-config.sh` — **only** this file. Per #6178's nonce-2
    rationale this re-fires `deploy_pipeline_fix` **alone** (it is absent from `handler_bootstrap`'s
    five-element trigger set), so no bridge, no restart, **no nonce-1 race**.
4.2 **The merge IS the authorization.** No `-replace`, no `workflow_dispatch`, no SSH.
4.3 The new gate verifies. If `ci-deploy.sh` is still `2208300a`, CI goes **RED and names the file**
    — the outcome #6594 exists to produce.

> **Operator-visible action.** The plan's only prod write. Gated behind PR-A, precedented, and it
> mutates no host config in place — it re-delivers repo-defined files, so
> `hr-prod-host-config-change-immutable-redeploy` is satisfied: this **is** the immutable-redeploy
> path. **Never a silent side effect.**
>
> **Expect main to be RED between Phase 3 and Phase 4** — the content assert is *truthfully* red
> against a genuinely stale host until the nonce lands. Intended. Stated here so nobody "fixes" it.

### PR-B — Phase 5: ADR + C4

5.1 Amend ADR-114 (3 items; quote and rebut `ADR-114:122`'s fan-out recommendation).
5.2 Correct `model.c4`'s ONE-connector invariant. Run both C4 tests.

### Handovers (no code; each is a comment or an issue)

- **#6565** ← the measured datum: `class=cred_store rc=1 stderr_chars=97|96|94 kw=errsaving
  tok=error docker_ver=29.3.0 (registry=ghcr)` on `soleur-inngest-prd`. **It is unblocked now.**
- **#6525** ← the pull mechanics: `pull_image_with_fallback` returns 1 only when **both** registries
  fail; the GHCR leg retries **once, and only for auth-classified stderr**, so a network/timeout
  failure gets **zero** retries. Fail-closed but downtime-safe (old container stays live).
- **New issue** ← *cloud-init changes are silent no-ops on running hosts* (#6426's class). A CI gate
  failing any PR touching `cloud-init*.yml` without an explicit reach-running-hosts ack. **This is
  the only one of the three "merged but never deployed" mechanisms with no detection at all.**
- **New issue (D-A)** ← *`host_name` telemetry is lying*: a web host self-labels `soleur-inngest-prd`
  (a `sed`-rendered Vector literal, #6396). Every `host_name`-based attribution is suspect, including
  #6425's web-2 reading. Explains #6594's flagged `host`/`host_name` conflict.
- **New issue (D-B)** ← *the dedicated inngest host may be dark, and a colocated scheduler may still
  be live*: `soleur-inngest` is running but ships no journald; the live `inngest-server` argv says
  `--sdk-url 127.0.0.1:3000` (colocated). Possible double-scheduler — triage.
- **#6465** ← the 4th-copy trigger did not fire (`host_id` cut).

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| **PR-A and PR-B in one PR ⇒ arbitrary apply order ⇒ the recovery coin-flips anyway** | **Two PRs.** The split is the mechanism; prose is not. |
| **The retry loop turns the content assert into "any-of-3"** | Assert **outside** the loop; mismatch is terminal. |
| **A wrong `service` value breaks `deploy.`** — and it auto-applies on merge with no gate | Use the regex-validated `var.web_hosts`. Phase 1.2 review. Rollback is viable and does **not** depend on `deploy.` (corrected above). |
| **Pinning makes `deploy.` unavailable if web-1 is down** | Accepted, and a net **improvement**: today the alternative is not "available" but "answered by a host that cannot serve the route" — web-2 has no `inngest-inventory.sh` at all. Correct-or-unavailable ≻ silently-wrong. |
| **web-2 freezes out of infra-config after the pin** | **Consistent with the recorded architecture, not new debt.** `model.c4:178`: *"re-pooling needs full infra-config + SSH re-delivery (#6466), never a weight flip."* Today web-2 receives a **random ~50% subset** — an arbitrary interleaving. Pinning converts *randomly drifting* → *deterministically frozen*, which is what makes #6440's audit tractable. Fan-out is a **GA prerequisite** (ADR-068 §8), filed, not "the successor". |
| **NEW (deepen): web-1's connector must dial its own private NIC, where it dialled loopback before.** A NIC-present dependency that did not exist. | **The one genuinely new failure mode this change introduces.** ADR-114:210-213 notes the boot race — the cloudflared token rides `user_data` at create while the network attach always lands after — and ADR-114:161-163's prescribed NIC-wait gate **was never shipped** (`cloud-init.yml` installs cloudflared behind only a `cloudflared_ready` poll). So on a fresh web-1, cloudflared can serve ingress before `10.0.1.10` exists → `deploy.` AND `ssh.` dark until the NIC converges, and #6557 documents attaches that land while the guest never configures the address (terminal at the reboot cap). Since `ssh.` is CI's only SSH route, a NIC-less fresh web-1 is unrecoverable in-band. ~~It bites only on a fresh web-1 boot, which #6482 currently makes impossible anyway.~~ **RETRACTED — that mitigation was false.** #6482 (2026-07-15) claims cx33 is unavailable EU-wide; **#6538 (2026-07-16, one day newer) measures `cx-family available: hel1 = [cx23, cx33, cx43, cx53]` and `soleur-web-platform cx33 hel1 rebuildable_in_place_today YES`.** Stock returned; a fresh web-1 boot is possible today. This is the exact error ADR-114:67-72 records against itself — *"a rate quoted from a snapshot is a claim with a timestamp, not a fact"* — and the plan re-committed it while quoting the rule. **Real mitigation:** the pin still wins decisively (today `ssh.` already lands wrong ~50% of the time, so this is a *conditional counterfactual* regression against a status quo that is already broken), the new post-apply verification fails the apply loudly instead of silently, and the unshipped ADR-114:161-163 NIC-wait gate is filed as this change's named structural complement. Named, measured, not waved away. |
| **`hooks.json` has no repo file to hash** | Exclusion derived from the template property, not hardcoded; asserted to be exactly one. |
| **`files[]` can exceed FILE_MAP** (`orphan_hook_command`) | Key the assert off FILE_MAP. |
| **The gate compares host bytes to the wrong ref** | Assert against the SHA the apply ran from, not `HEAD`. |

## Alternative Approaches Considered

| Alternative | Verdict |
|---|---|
| **Freshness assert (issue proposal #1)** | **CUT** — unanimous (DHH, code-simplicity, Kieran). It is strictly dominated: the unique state it catches (content matches, `start_ts` old) is *delivery of byte-identical content* — a no-op with no failure hiding in it. Its own unique behavior is **false-failing** when the resource legitimately doesn't replace. And it is **unimplementable as specified**: the gate is a separate step and the apply step pipes `terraform apply` straight to the log — no `tee`, no `$GITHUB_OUTPUT` — so there is no signal to gate it on. Content is the end-state invariant; freshness is a proxy for it with an extra input and a failure mode. |
| **`host_id` in the payload (v1 scope 3)** | **CUT** — unanimous. It is an **alternative** to Phase 1, not a complement: both answer "which host answered", and Phase 1 answers it by construction for one line of HCL. Costs: the nonce-1 race (editing `cat-infra-config-state.sh` re-fires the bridge), a 4th `resolve_host_id` copy (#6465's fired trigger), a 12+-surface enumeration, and a **circular dependency** — the `host_id` reporter is delivered *by the pipeline it exists to audit*, so it is absent on the only run that matters. It also has **no runtime source** (no `terraform output` for the hcloud id) and **three** resolution outcomes (`hetzner-N`, hashed machine-id, empty), so a 3s metadata blip would redden the gate with a wrong-host accusation **against the right host**. Verification uses `/hooks/deploy-status`'s **existing** `host_id` instead. |
| **`replace` input (issue proposal #3)** | **REJECTED.** (a) **#6482**: a `-replace` at any `cx33` destroys-and-wedges with no EU capacity to re-place — a loaded gun in a dispatch input. (b) The nonce already solves it, precedented ×2, merge-authorized. (c) It adds a dispatch-reachable prod-write lever (`hr-menu-option-ack-not-prod-write-auth`). (d) A forced replace *"succeeds loudly while delivering nothing"*. If ever needed, allowlist to exactly `terraform_data.deploy_pipeline_fix`. |
| **De-pool web-2 (#6426's intent)** | **Unavailable.** Construction-time gate; `ignore_changes=[user_data]`; #6482 blocks the rebuild. Measured: merged 2026-07-15, web-2's connector (up since 2026-07-13) still live. |
| **De-pool by destroy** (remove web-2 from `var.web_hosts`) | **Rejected** — but v1's "origin-relative is the ONLY lever" was overstated. This lever exists (web-2 serves no user traffic, LB weight 0). It is rejected because **#6482 makes it a one-way door**: a destroyed `cx33` cannot be re-placed, forfeiting ADR-068's GA line. The sound claim: **origin-relative is the only *reversible, non-destructive* lever.** |
| **CF connector `DELETE` API** | Not a lever — `cloudflared` is a systemd service and reconnects. Named so the next reader doesn't re-derive it. |
| **Fan out infra-config to peers (ADR-068 Option B)** | **Deferred, and rebutted on the merits — not routed around.** ADR-114:122 calls it *"the cheapest fix … needing no `.tf` and no tunnel change"*. But it fixes the **WRITE** only: `deploy-status` and `inngest-liveness` stay coin-flipped, so the gate's read stays unsound. And it presumes web-2 should be converged — #6440's open question. **File as a GA prerequisite.** |
| **Per-host hostnames (`deploy-web-1.`)** | **Rejected.** ADR-114's normative anti-pattern: a per-hostname rule pointed at `localhost:` is a **no-op**. |
| **Gate-only; depend on #6441** | **Rejected.** Ships an assert whose read is coin-flipped and whose retry loop is any-of-3. |

## Key Decisions

- **D1** — The root cause is #6425 (two connectors), not a missing assert. Measured.
- **D2** — Order is load-bearing: **pin → assert → recover**, and **the PR split is what enforces it**.
- **D3** — **The inngest steer is not actionable, and the plan honors its intent anyway.** An
  interim draft claimed the opposite on `host_name` evidence; **retracted** — that field is a config
  literal and a colocated web host wears it (see the `host_name` trap). There is no delivery path for
  `ci-deploy.sh` to the dedicated inngest host and none was designed. The operator's *concern* —
  "don't fire an untested `-replace` at web-1" — is honored **better than the literal ask**: the
  enabling change is a Cloudflare config edit with **zero host writes**, the failing test runs
  **offline against a real captured payload**, and the only prod write is the **precedented nonce**,
  not a `-replace`. Honest limit: the nonce bump is *unrehearsed* — what protects it is that it is
  reversible and precedented, not that it is tested.
- **D4** — Reject the `replace` input (#6482 + the nonce precedent).
- **D5** — #6426's de-pool merged and never took effect. **The same meta-defect as #6594**, and with
  the #6416 tripwire (item 3) possibly a third instance. **This is the amendment's headline.**
- **D6** — The recovery is gated behind PR-A and is explicitly operator-visible.
- **D7** — ~~`image_pull_failed` is blocked on this PR's instrument~~ **RETRACTED.** #6565 is blocked
  on #6528, which is **merged and live on the host**. The conclusion (don't fix by guessing) stands;
  the reason was wrong — and the correction *unblocks #6565 today*. See UC-1.

## Sharp Edges

- A plan whose `## User-Brand Impact` is empty/`TBD`/threshold-less fails `deepen-plan` Phase 4.6.
- **Never merge PR-A and PR-B together.** Shared concurrency serializes but does not order.
- **Never put the content assert inside the retry loop.** Fresh curl = fresh connector = any-of-3.
- **Expect main RED between Phase 3 and Phase 4.** It is a true red. Do not "fix" it.
- **`depends_on` does NOT close the nonce-1 race** — the edge (2026-06-18) predates the race
  (2026-07-10). Any plan that edits `infra-config-apply.sh` or `cat-infra-config-state.sh` alongside
  a nonce bump reproduces #6178.
- **Never hardcode `10.0.1.10` or `15`.** Both have canonical sources. (The `:9000`/`:22` ports are a
  knowing, named exception.)
