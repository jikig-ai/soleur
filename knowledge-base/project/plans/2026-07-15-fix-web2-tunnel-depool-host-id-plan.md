---
title: "fix: de-pool web-2 from the shared Cloudflare Tunnel + host-identify deploy-status/liveness"
date: 2026-07-15
type: fix
issue: 6425
branch: feat-one-shot-6425-web2-tunnel-depool-host-id
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# fix: de-pool web-2 from the shared Cloudflare Tunnel + host-identify deploy-status/liveness

**Ref #6425** (not `Closes` — the de-pool executes post-merge; see Phase 7).

> Revised after a 7-reviewer panel + a scoped advisor consult, then deepened. The panel falsified **27** v1/v2 claims and produced **four P0s**. See `## Review Corrections` — several are lessons, not just edits.

## Enhancement Summary

**Deepened:** 2026-07-15 · **Panel:** dhh · kieran · code-simplicity · architecture-strategist · spec-flow-analyzer · cto (devex) · cpo (sign-off) + a Fable advisor consult.

### Key improvements over v1

1. **The root cause was confirmed live, not argued.** The Cloudflare API census found 2 connectors on tunnel `6410c1ec`, colo-split fra* (web-2/fsn1) vs ams*+hel* (web-1/hel1) — independently corroborating the EU-vs-US vantage evidence.
2. **The deliverable was saved from missing its own incident.** `host_id` on the JSON emits alone would not have appeared in the 2026-07-15 probe, which returned `FATAL __FETCH_FAILED__` — a plain-text `exit 1` path. AC3 now covers the **success × failure** axis.
3. **A GA time-bomb was removed.** v1 bound the connector to ADR-068 §(c); §(c) clears at GA → web-2 re-joins → #6425 recurs *while web-2 serves users*. The gate is now *designated ingress host*, which never clears.
4. **The apply path was made executable.** Two independent P0s (the coherence preflight aborting the de-pool; the racing run consuming the `triggers_replace` hash and making the re-push a no-op) are now compensated — or dissolved entirely by the split recorded in `decision-challenges.md` UC-1.
5. **The detector gap was closed.** v1 ran the vantage-independent census once, by hand, then relied on a single-vantage poll it had itself declared worthless. The census is now a standing 15-min watchdog check filing an `action-required` issue — the only wire into `operator-digest`.

### New considerations discovered

- The de-pool's blast radius is the **apply pipeline**, not a serving surface (`## Downtime & Cutover`) — and the failure mode is "nothing happens," not "half a host."
- `/hooks/infra-config` is a **coin-flipped WRITE** self-verified against a *separately* coin-flipped read; `ssh.soleur.ai` carries the seccomp/AppArmor applies. Both are worse than the reported symptom.
- Two in-code root-cause attributions (`tunnel.tf:58-64` "registry transiently DOWN"; `:68-71` the 2026-07-11 502) may be misdiagnoses of this same coin flip — probe prescribed, conclusion withheld.
- Three defects in Soleur's own tooling surfaced (see `decision-challenges.md`), including a `plan-review` sentinel where declaring the **higher** threshold silently buys **less** review.

## Overview

`server.tf:158` passes `tunnel_token` into `templatefile("cloud-init.yml", …)` for **every** member of `var.web_hosts` (`for_each`, `server.tf:107`). `cloud-init.yml:590` consumes it — at the **only** `${tunnel_token}` reference site in the file — as `cloudflared service install ${tunnel_token}`. So web-2 (fsn1) registers a **second connector** on the one `soleur-web-platform` tunnel.

**Confirmed live during review** (Cloudflare API, tunnel `6410c1ec-4f01-4a69-ad98-7bb1621f6d37`, status `healthy`):

```
client 8c57fcd5  conns=4  colos: fra03 fra17 fra18 fra08   <- fsn1 = web-2
client a281fb1b  conns=4  colos: ams15 hel01 hel01 ams08   <- hel1 = web-1
```

Two connectors. Cloudflare selects **per edge colo** — sticky per vantage, not random per request. The Frankfurt/Helsinki colo split independently corroborates the operator's evidence: a US CI runner (watchdog 29400873473, 08:27:48 UTC) read `functions=61` healthy; EU probes at 08:50 read `inngest_server=inactive` **10/10 identical**. Two origins, colo-pinned.

**Inngest is not down and never was. No user impact** — `app.soleur.ai` is an A record pinned to web-1 (`dns.tf:16`).

### The real defect: the non-fan-out paths were never enumerated

Only `/hooks/deploy` fans out to peers over the private net (`ci-deploy.sh:173-203`), which is why deploys survive the coin flip. Nothing else does:

| Tunnel path (`tunnel.tf`) | Target | Fans out? | Consequence of a 2nd connector |
|---|---|---|---|
| `deploy.soleur.ai` → `/hooks/deploy` | `http://localhost:9000` (`:33`) | **Yes** | Benign by design |
| → `/hooks/deploy-status`, `/hooks/inngest-liveness` | same | **No** (reads) | **#6425** — reads a random host |
| → `/hooks/infra-config` | same | **No** | **A coin-flipped WRITE**, self-verified against a *separately* coin-flipped read (`push-infra-config.sh:94`, single URL, no peer concept) |
| `ssh.soleur.ai` | `ssh://localhost:22` (`:41`) | **No** | **`apply-deploy-pipeline-fix.yml`'s SSH bridge lands on a random host** — it targets `terraform_data.docker_seccomp_config` + `apparmor_bwrap_profile` (`:288-292`) |
| `registry.soleur.ai` | `tcp://10.0.1.30:5000` (`:66`) | **No** | Dial originates from whichever connector; web-2's private NIC is open #6416 |

Two are materially worse than the reported symptom: a **sandbox-escape control update can silently land on web-2 while CI reports green**, and host-script pushes land non-deterministically. That is why the threshold is `single-user incident` — it reflects the surface governed, not the difficulty of the diff.

### Why this is not a CTO-ruling reversal

ADR-068's 2026-07-01 amendment (`:355-358`) reads:

> "both hosts run cloudflared on that ONE tunnel, **so** a POST load-balances to ONE connector non-deterministically. **Chosen: Option B** — a receiving-host private-net fan-out."

That "so" is a **premise clause**. The CTO *observed* two connectors as an existing constraint and designed a fan-out around it. The question before him was *"how do deploys reach both hosts"*; A/B/C/D answer that question. **He never ruled on connector count, because connector count was not the question.** There is nothing to reverse. (v1 claimed a "fifth option ADR-068 never considered" — that was a category error: one-connector *composes* with Option B rather than competing with it, which v1 itself admitted by saying "retains Option B unchanged.")

**Stronger — the 2-connector state falsifies ADR-068's own verification contract.** Two verbatim claims:

- `ADR-068:720-722` — web-2 acceptance is proven via web-1's `/hooks/deploy-status` `reason`, *"the only web-2 signal reachable through the single tunnel (**the off-host runner cannot read web-2 directly**; web-2 has zero LB weight + no public ingress)"*
- `ADR-068:826` — *"web-2 `:9000` is private-net-deny"*

**Both are false today.** web-2's connector puts its `:9000` on the public `deploy.soleur.ai`. So the warm-standby/recreate verify (`reason==ok` vs `ok_peer_fanout_degraded`) can POST to web-2 and read web-1's stale slot — **a green verify that proves nothing.**

De-pooling therefore **repairs an internal contradiction** and makes ADR-068's existing verification design sound for the first time. Option B's fan-out is retained unchanged; only the entry point becomes deterministic.

### Deliverable 2 is a fast-follow ADR-068 already scheduled

`ADR-068:600`: *"The residual wrong-volume-attached gap is closed by the **ADR-082 `host_id` sentinel** as a fast-follow — not a v1 dependency."* `ADR-082` Item 5 records the delivered half (`host_id` on `pull_failure_event`, #6396, merged 2026-07-14). This extends the **same** sentinel to the read surfaces.

---

## Research Reconciliation — Spec vs. Codebase

| Brief claim | Codebase reality | Plan response |
|---|---|---|
| `server.tf:158` passes `tunnel_token` to every host | **Confirmed** (`:107`, `:158`, `cloud-init.yml:590`) | Gate it (Phase 2) |
| "Gate it so only web-1 runs a connector" reaches the hosts | **False.** `server.tf:217-219` puts `user_data` in `ignore_changes` on the `for_each` resource → applies to **both** instances → a cloud-init change is **zero plan diff** on running hosts | Inert at merge (the safety property). Materialises only via `apply_target=web-2-recreate` |
| dns.tf documents web-1-only intent never enforced on the connector | **Confirmed** (`dns.tf:4-12`, `:16`) | See "Why this is not a reversal" |
| Impact = `deploy.soleur.ai` | **Understated** — 5 paths, 4 non-fan-out | Blast-radius table |
| "reuse the `pull_failure_event` host-id source" | `resolve_host_id()` (`ci-deploy.sh:137-155`). But `cat-deploy-state.sh` / `inngest-inventory.sh` are standalone hook targets that don't source it | Duplicate + token drift-guard, per the `test_durability_drift_guard` precedent |
| A second identity scheme would be bad | **Two already exist**: `resolve_host_id()` and `HOST_ID=$(cat /var/lib/cloud/data/instance-id \|\| hostname)` (`soleur-host-bootstrap.sh:29`); plus TF-derived `host_name` (`server.tf:188`) | Use `resolve_host_id()` per brief. Unification → Deferred |
| The 3 auto-closed inngest-down issues are an auto-close defect | **Not a defect** — the watchdog read a healthy web-1 | Do **not** touch the watchdog corroboration work |
| #6413 pre-existing, out of scope | **Confirmed OPEN**, p3-low, non-required | We add a 2nd `%{ if ~}` directive — the same construct it trips on. Non-blocking; see Risks |
| #6415 / #6416 open | **Confirmed** | Deferral issue links both |
| `restart-inngest-server.yml` push trigger runs a full prod restart | **Confirmed** (`:14-24` push on own path; job `restart` `:30` has no `event_name` guard) | Fix inline — and the guard is an **existing idiom** (`cutover-inngest.yml:48`, `deploy-inngest-image.yml:29`) |

**Premise validation:** every cited issue verified via `gh issue view`; ADR-068/082 read directly, not paraphrased. **v1's ADR framing was materially wrong and the panel corrected it** — see `## Review Corrections`.

---

## Hypotheses

L3→L7 order was honoured, which is what made the diagnosis cheap:

1. **L3/routing — CONFIRMED.** `dig deploy.soleur.ai` → 188.114.97.2 / 188.114.96.2 (anycast; origin chosen at the edge). DNS/firewall ruled out first.
2. **L7/connector selection — CONFIRMED (root cause).** Two connectors, verified live via the Cloudflare API (census above). Colo-sticky selection explains `10/10 identical` per vantage.
3. **"Host was reprovisioned" — REFUTED.** Store 333MB→0, root_avail 50G→70G, canary reset = a different host answering.
4. **"Inngest is down" — REFUTED.** Watchdog read `functions=61`.
5. **#6400 `image_pull_failed` / #6357 share this root cause — UNVERIFIED. Do not assert.**

### Network-Outage Deep-Dive (deepen-plan Phase 4.5)

Gate fired on two triggers: the prose names `502` (#6357), and the **resource-shape trigger** — Phase 7 drives `terraform apply` on `apply-deploy-pipeline-fix.yml`'s `terraform_data.*` targets, which carry `connection { type = "ssh" }` + `provisioner` blocks, making SSH a hard apply-time dependency the prose-only scan would miss (the #3061 class). Layer-by-layer verification status per `plan-network-outage-checklist.md`:

| Layer | Status | Artifact |
|---|---|---|
| **L3 — firewall allow-list vs. current egress IP** | **Not applicable to the de-pool, but load-bearing for Phase 7 step 4.** `apply-deploy-pipeline-fix.yml` does **not** need the runner IP in `var.admin_ips` — it bridges SSH through the CF Tunnel (`:33-42`) with the `ci_ssh` Access service token. The de-pool itself (`web-2-recreate`) is a Hetzner-API call and traverses **no** SSH. | `apply-deploy-pipeline-fix.yml:33-42`; `server.tf` provisioners pin `host = hcloud_server.web["web-1"].ipv4_address` (direct IP, not the tunnel) |
| **L3 — DNS / routing** | **VERIFIED — and this is the root cause.** `dig deploy.soleur.ai` → 188.114.97.2 / 188.114.96.2 (Cloudflare anycast). Origin is chosen at the **edge**, not by DNS, so DNS is correct and irrelevant. Checked *before* any service-layer hypothesis, per `hr-ssh-diagnosis-verify-firewall`. | Operator-pulled 2026-07-15 08:50–09:05 UTC |
| **L7 — TLS / proxy** | **VERIFIED.** CF edge terminates TLS; the tunnel is an outbound-only connector (no inbound port). The defect is **connector selection**, not TLS. Confirmed live: 2 connectors, colo-split fra* vs ams*/hel*. | Cloudflare API census, `## Overview` |
| **L7 — application** | **VERIFIED.** Both origins are healthy *as applications* — web-1 answers correctly, web-2 answers as an unprovisioned host (#6415/#6416). No application fault exists; `functions=61` on web-1. | Watchdog run 29400873473 |

**No gaps.** The L3→L7 ordering was honoured and is precisely why the diagnosis was cheap once the census ran: L3 ruled DNS/firewall out immediately, leaving edge-side connector selection as the only remaining explanation for two deterministic-but-opposite verdicts on one URL.

**One SSH-adjacent risk this surfaces:** `ssh.soleur.ai` → `ssh://localhost:22` is itself coin-flipped, so `apply-deploy-pipeline-fix.yml`'s SSH-bridged applies (`terraform_data.docker_seccomp_config`, `apparmor_bwrap_profile`) can land on web-2 **today**. De-pooling fixes this as a side effect — and it is why Phase 7 step 4 runs *after* the de-pool.

### Hypothesis 5 — probe prescribed, conclusion withheld

Two candidate mechanisms, both currently attributed elsewhere in code comments:

- **#6400:** CI's `cloudflared access tcp --hostname registry.soleur.ai` landing on web-2's connector → dial to `10.0.1.30:5000` from a host whose private NIC is open **#6416** → intermittent pull failure. Would make `tunnel.tf:58-64`'s *"a `dial tcp … canceled` here means the origin is transiently DOWN (registry stability = #6288)"* a **misdiagnosis**.
- **#6357:** `tunnel.tf:68-71` attributes a 2026-07-11 502 on the deploy route to registry dials saturating the tunnel daemon's HA-stream budget. A 502 is equally consistent with the POST landing on a web-2 connector whose `:9000` was **unbound** — `ADR-068:758-761` records that web-2's original cloud-init **aborted before the webhook-enable step**. Same misdiagnosis class, zero marginal probe cost.

**Probe (read-only, Phase 1.1).** `pull_failure_event` carries `tags.host_id` since #6396 (2026-07-14), so the evidence already exists:

```
Sentry → Issues → search: op:image-pull → Tag Details → host_id distribution
(restrict to events after 2026-07-14; before that host_id was not emitted)
```

≥2 distinct `host_id`s ⇒ the coin flip is implicated. **Either outcome: comment on #6400 / #6357 and move on — do not widen this PR's diff.** Not gated by an AC (v1 gated it; that was ceremony over a zero-diff read).

---

## User-Brand Impact

**If this lands broken, the user experiences:** nothing directly — `app.soleur.ai` → web-1; web-2 serves no user traffic. Two real failure modes, both disclosed below: a `-replace` that **wedges every apply-on-merge** (P0-2), and an inverted predicate that boots the **live** host dark (AC5).

**If this leaks, the user's data is exposed via:** no new surface. The change **narrows** one — web-2's rendered `user_data` no longer carries the live tunnel token (`user_data` is readable from the host's own metadata service).

**Brand-survival threshold:** `single-user incident`

**Rationale — argued from the DIFF, not the bug** (CPO condition C4; the taxonomy at `plugins/soleur/skills/incident/SKILL.md:95-97` is three *ascending* tiers, so `single-user incident` de-escalates to `none`, not `aggregate pattern` — and `none` is barred):

1. **Credential touch.** The change governs a live `tunnel_token` rendered into `user_data`. That is a sensitive-data surface, which the taxonomy's second disjunct ("**OR** any sensitive-data surface is at risk") catches on the *surface*, not on diff-failure. `hr-weigh-every-decision-against-target-user-impact` fires on any plan touching credentials regardless of blast radius.
2. **AC5-regression → loss of the remediation channel.** An inverted predicate takes `deploy` + `ssh` + `registry` dark on the **live** host simultaneously. It does *not* take `app.soleur.ai` down (A record direct to web-1) — so it is not direct user impact. What it destroys is **the ability to respond to a user incident on the host serving every user**, and `hr-no-ssh-fallback-in-runbooks` means there is no sanctioned backdoor.

> *(v1/v2 argued the threshold from the badness of the **bug being fixed**. As precedent that is wrong — it would make every P1 bugfix inherit maximum ceremony. The verdict stands; the reasoning is replaced. Per CPO.)*

**CPO sign-off: APPROVE-WITH-CONDITIONS** (C1–C6; all folded in — C2/C3 §(c), C4 above, C5 deferral, C1/C6 sweep). `user-impact-reviewer` runs at review time.

---

## Architecture Decision (ADR/C4)

### ADR — amend `knowledge-base/engineering/architecture/decisions/ADR-068-multi-host-workspaces-shared-git-data-lease-coordinator.md`

In-place amendment, not a new ordinal: this corrects ADR-068's **own** premise, and the repo's precedent is unanimous (12 prior in-place amendments, incl. `:643-682` "Correction to §(b)" — the exact pattern). ADR-113 is next-free but **do not use it**.

Amendment (2026-07-15, `Ref #6425`) records, in ~5 sentences:

1. **The premise correction.** The 2026-07-01 amendment *observed* two connectors and routed deploys around them via Option B; it did not gate the connector, and the non-fan-out paths were never enumerated. Option B is **retained unchanged**.
2. **The falsified contract.** `:720-722` ("the off-host runner cannot read web-2 directly") and `:826` ("web-2 `:9000` is private-net-deny") are false under two connectors — the warm-standby verify can POST to web-2 and read web-1. De-pooling makes that verify sound.
3. **The invariant** — *the tunnel connector is gated on being the **designated ingress host**.* **NOT** on §(c) (see P0-1 below).
4. **The accepted trade** (P2-1): de-pooling removes deploy-ingress survival of a web-1 **cloudflared-process-only** failure — bounded by the systemd restart-on-failure (`cloud-init.yml:590`), and worthless if web-1's *host* dies (`app.soleur.ai` → web-1 anyway). **A silent-wrong-answer mode is traded for a loud-total-outage mode. That is the right trade and must be a stated one.**
5. **The sole-consumer note:** the gate is the only `${tunnel_token}` consumer; a second consumer must be added **inside** it.

> **P0-1 — do NOT bind the connector to §(c).** v1 proposed adding the connector to §(c)'s gated set. §(c) (`ADR-068:566-575` — *not* `:703-714`, and it gates **LB weight only**, not the `app` A record) requires owner-side relay + git-data cutover + LUKS soak. Both conditions are about **serving `/workspaces` correctly**; neither bears on terminating a deploy webhook. Binding them means **§(c) clears at GA → web-2 re-joins the tunnel → #6425 recurs verbatim, while web-2 is now serving real users.** `host_id` would make that *detectable*, not *fixed*. The correct gate — "is this the designated ingress host?" — does not clear at GA. web-2 may re-join only once the non-fan-out paths are **host-addressable** (fan-out-aware deploy-status, per-host infra-config targeting, host-scoped SSH) — a separate prerequisite §(c) does not contain, filed as a GA-scoped deferral (Phase 6.3).

### C4 views

**Enumeration against all three files** (`model.c4`, `views.c4`, `spec.c4`), read in full:

- **(a) External human actors:** none added.
- **(b) External systems:** `cloudflare` (`model.c4:232`), Hetzner — both modelled.
- **(c) Containers:** `tunnel` (`:176-178`), `hetzner` (`:180-183`), `coordinator` (`:202-205`) — all modelled.
- **(d) Relationships:** **v1 got this wrong.** `model.c4:362` (`tunnel -> coordinator "Routes traffic"`) is the **only** tunnel edge, but it models the **deferred 3.D rewire** (`ADR-068:224-226`: the `service` target *"becomes"* the coordinator), not anything live. Today the tunnel routes to `:9000`, `:22`, and zot — **none is the coordinator, and none is modelled.** Writing a live connector-topology fact onto a not-yet-real edge is a category error.

**Edits:**
1. **`model.c4:176-178`** — the `tunnel` **element description** ("Zero-trust inbound access — no exposed ports") gains the single-connector invariant. True regardless of the 3.D rewire.
2. **Add the genuinely-missing `tunnel -> hetzner` edge** for the live deploy/ssh/registry ingress.

Edit 2 adds a relationship, so **verify whether `views.c4` needs an `include`** — v1's "no new element, therefore no include" shortcut does not survive edit 2. Run `apps/web-platform/test/c4-code-syntax.test.ts` + `c4-render.test.ts`.

---

## Infrastructure (IaC)

### Terraform changes

| File | Change |
|---|---|
| `apps/web-platform/infra/server.tf` | add **one** templatefile var: `web_tunnel_connector = each.key == "web-1"`. **`:158` is untouched** — the `tunnel_token` map entry stays (templatefile requires every interpolated var present regardless of branch) |
| `apps/web-platform/infra/cloud-init.yml` | wrap `:590` + `:593` in `%{ if web_tunnel_connector ~}` / `%{ endif ~}` |

```yaml
%{ if web_tunnel_connector ~}
  - cloudflared service install ${tunnel_token}
  - soleur-wait-ready service cloudflared cloudflared_ready || exit 1
%{ endif ~}
```

**One predicate, one place.** v1 also proposed `tunnel_token = each.key == "web-1" ? <token> : ""`. **Dropped — that was a correctness bug, not redundancy:**

- `${tunnel_token}` has **exactly one** reference site (`cloud-init.yml:590`), *inside* the gated block → the gate alone already keeps the token out of web-2's rendered `user_data`. The ternary adds nothing.
- The ternary **alone** cannot work: an empty token → `cloudflared service install ` → `:593` readiness poll → `exit 1` → boot abort.
- **Two predicates can diverge.** Edit one and not the other → web-1 renders gate-on with an empty token → `service install ` fails → `:593` exits 1 → **the live host boots with deploy + ssh + registry dark.** The redundancy manufactures the exact catastrophe AC5 exists to prevent.

**Precedent:** mirrors `web_colocate_inngest` (`variables.tf:356-360`; gate at `cloud-init.yml:664-728`, the file's only other `%{ if ~}` pair) — which gates with a bool and does **not** also blank its gated value.

> **The `tunnel_token` map entry MUST stay** (this is why `:158` is untouched, not merely why it *may* be). Terraform's `MakeTemplateFileFunc` pre-checks `expr.Variables()` **before** evaluation, and HCL's `if` directive compiles to a `ConditionalExpr` whose `Variables()` walk covers **both** branches. Omitting the key for web-2 → `vars map does not contain key "tunnel_token"`. The gate suppresses the *render*, never the *key requirement*.
>
> **Column-0 hazard (the only real YAML risk).** The directive must sit at **column 0**, exactly as `:664`/`:728` do. Indenting it (`  %{ if ... ~}`) leaves the leading spaces after the `~` trim and corrupts `runcmd:` list indentation. AC5's `yaml.safe_load` arm is what catches this.

**Rejected: a `web_tunnel_connector_host` variable** (proposed by the advisor consult; **rejected on the CTO's reasoning**). It exposes a knob that looks like a promotion switch and isn't: `each.key == "web-1"` is the in-file idiom (`server.tf:108`, `:188`) and `dns.tf` pins `web["web-1"]` in four places plus the LB weight. Promotion requires moving all of them in lockstep; a lone connector flip mid-outage yields a connector on web-2 while the A record and LB weight still point at web-1 — ingress split, at 3am. Encoding the coupling in the ADR beats exposing a knob that lets you violate it.

**Keep `ignore_changes` untouched** — `terraform-target-parity.test.ts:1168-1180` pins `placement_group_id` + `user_data`.

### Apply path

**Merging is safe mid-migration — the load-bearing fact.** `user_data` is in `ignore_changes` on the `for_each` resource; `cloud-init.yml` is consumed at one place (`server.tf:147`) and is **not** in `local.host_script_files` or any `triggers_replace`.

> **Merging deliverable 1 produces ZERO plan diff on `hcloud_server.web`.** It **rides the allow-list apply, which cannot touch `hcloud_server.web` or `hcloud_server.registry`** — so it cannot disturb the in-flight registry migration. *(v1/v2 said "does not ride a prod apply at all" — imprecise: the merge touches `apps/web-platform/infra/**`, so `apply-web-platform-infra.yml` **does** fire and `-target`s ~98 resources at `:296-393`, including `cloudflare_zero_trust_tunnel_cloudflared.web` (`:312`) and `random_id.tunnel_secret` (`:311`). The substantive claim survives only because both `hcloud_server.web` and `hcloud_server.registry` are absent from that allow-list.)*

Reinforcing: `hcloud_server.web` is **not** in the push-triggered `-target=` allow-list (`apply-web-platform-infra.yml:297-393`; the only `hcloud_*` web entries are `hcloud_firewall.web` / `_attachment.web` at `:390-391`). It appears as a `-target` at exactly one line — `:1150`, in the dispatch-only `web_2_recreate` job — and is `OPERATOR_APPLIED_EXCLUSIONS` in `terraform-target-parity.test.ts:482`.

**The de-pool** uses an existing scoped dispatch (job `web_2_recreate`, `:895`; plan `:1134-1154`): `-replace='hcloud_server.web["web-2"]'` + 3 targets, its own `web2_*` destroy-guard counters, data volume preserved (`:1143-1144`, asserted `:1189-1195`). **`hcloud_server.registry` is not in the target set** — the stuck registry gate (`registry-host-replace-gate.sh`) is a different gate on a different resource. Fully automatable via `gh`.

### Two deliverables, two delivery mechanisms (v1 conflated them)

| Script | Delivery | Consequence |
|---|---|---|
| `cat-deploy-state.sh` | **baked** (`host_script_files`, `server.tf:19`) **and** DPF-pushed (`:878`) | edit → `local.host_scripts_content_hash` changes (`server.tf:83`) → **triggers the coherence preflight** |
| `inngest-inventory.sh` | **DPF webhook only** (`server.tf:910` → `push-infra-config.sh` → `/hooks/infra-config`) | edit → **coin-flipped push** |

> **P1-1 — the coherence preflight will abort a naive sequence.** `web-2-recreate` extracts the pinned image's baked host-scripts, recomputes the hash, and asserts `== local.host_scripts_content_hash` (`apply-web-platform-infra.yml:1122-1130`); a mismatch **aborts loud before anything is destroyed**. Editing `cat-deploy-state.sh` changes that hash, so **merge → immediately dispatch `web-2-recreate` will abort** — web-1 has not yet been redeployed with the new digest. Phase 7 must gate on the release landing first.

### The ordering constraint

**The coin flip poisons its own remediation channel.** `push-infra-config.sh:94` POSTs to `deploy.${APP_DOMAIN_BASE}/hooks/infra-config` — the same coin-flipped hostname — and `apply-deploy-pipeline-fix.yml` push-triggers on both `cat-deploy-state.sh` (`:69`) and `inngest-inventory.sh` (`:89`).

> **De-pool first.** Terraform/Hetzner is the only lever outside the tunnel. Deliverable 1's verification does not depend on deliverable 2 (AC1 counts connectors directly), so nothing forces the inverse.

> **The `[skip-deploy-fix-apply]` kill switch is LOAD-BEARING, not optional** (v1/v2 called it optional — wrong). `apply-deploy-pipeline-fix.yml:288-293` runs `terraform apply -target=terraform_data.deploy_pipeline_fix` with **no `-replace` and no taint**; the provisioner re-runs only when `triggers_replace` changes. So the merge-triggered racing run **consumes** the hash change, and a later dispatch sees identical contents → **no diff → no-op → nothing lands on web-1.** The kill switch is the only thing that leaves the hash unconsumed. (It reads `github.event.head_commit.message` at `:173`, empty on `workflow_dispatch` → it correctly never suppresses step 4 itself.) The advisor's "self-healing race" reading holds for *correctness* but not for *delivery* — the copy is destroyed either way, but the trigger is spent.

**Phase 7 sequence** — all `gh` CLI, no operator step:

0. **Engage the merge-freeze / edit-lock** (`guardrails.sh`). `ADR-068:873-879` records that an operator recovery dispatch pending on `web-1-swap` **can be cancelled by a subsequent routine push**; because we use `Ref` not `Closes`, a cancelled de-pool presents as a *stall*, not a failure. (Both workflows share `terraform-apply-web-platform-host` with `cancel-in-progress: false`, so step 3 **queues** rather than being cancelled — the freeze covers the ADR's distinct `web-1-swap` case.)
1. **Merge with `[skip-deploy-fix-apply]` in the merge commit** — mandatory, per the box above.
2. **Wait for the web-1 release to land the new digest** (`web-platform-release.yml`); confirm `curl -s https://app.soleur.ai/health | jq -r .version` equals the new semver. **This gates the coherence preflight** — without it, step 3 aborts.
3. **De-pool:** `gh workflow run apply-web-platform-infra.yml -f apply_target=web-2-recreate -f reason='#6425 …'` → verify **AC1** + **AC6**.
4. **Deliver deliverable 2:** `gh workflow run apply-deploy-pipeline-fix.yml -f reason='#6425 post-de-pool push'` → now deterministic (web-2 is de-pooled) **and** non-no-op (the hash was never consumed) → verify **AC13/AC14**.
5. `gh issue close 6425` **only after AC1 passes**. Release the freeze.

> **Steps 1-2 exist only because both deliverables ship together.** Deliverable 1 alone is hash-neutral and could de-pool immediately. See `decision-challenges.md` **UC-1** — three reviewers independently recommended splitting; the operator's stated scope is retained as the default and the compensations above make it correct.

### Risk: the `-replace` blast radius (P0-2 — v1 understated this)

v1 said a failed replace merely "loses a warm standby". **Its own citation says otherwise.** `variables.tf:86-92`:

> "a `-replace` recreate DURING a hel1 capacity shortage destroyed web-2 then could not re-place it, **wedging every apply-on-merge on `resource_unavailable`** (2026-07-13, #6374 follow-on)"

`hcloud_server.web` is reachable in the per-PR apply path as a dependency of the targeted `hcloud_firewall_attachment.web` (`ADR-068:531-533`). So the true failure mode is **every infra apply-on-merge wedges**, not "we lose a standby."

- **The standby loss is acceptable** — volume preserved; web-2 is rebuildable via the `warm-standby` dispatch; the ADR-068 cutover is deferred.
- **The wedge must be disclosed, with its lever:** flip `var.web_hosts["web-2"].location` off the starved DC (the documented 2026-07-13 remedy) and re-dispatch.

With that disclosed and the lever recorded, the acceptance is sound.

### Distinctness / drift safeguards

- `dev != prd`: N/A (prod-only root). `ignore_changes`: unchanged.
- **No 32KB risk.** `%{ if ~}` / `%{ endif ~}` are consumed at render and `~` trims trailing whitespace → web-1's rendered `user_data` grows **~0 bytes**; web-2's shrinks. (v1 claimed "~+40 bytes" — wrong.) Size stays pinned by `cloud-init-user-data-size.test.ts`.
- Secret handling: the gate keeps the token out of web-2's render. State posture unchanged (encrypted R2 backend).

### Vendor-tier reality check

N/A — no new vendor resource. `CF_API_TOKEN` verified **live** as `active` with Tunnel scope, readable from Doppler `prd_terraform`.

---

## Downtime & Cutover

Required by deepen-plan Phase 4.55 — the plan drives `-replace='hcloud_server.web["web-2"]'`, which is the **infra reboot/replace class** trigger (a `must be replaced` on an `hcloud_server`).

### The offline-inducing operation and the surface it affects

`terraform apply -replace='hcloud_server.web["web-2"]'` (job `web_2_recreate`) **destroys and recreates web-2**. Enumerating every surface web-2 currently serves:

| Surface | Does web-2 serve it? | Effect of the replace |
|---|---|---|
| `app.soleur.ai` (all user traffic) | **No** — A record pinned to `hcloud_server.web["web-1"].ipv4_address` (`dns.tf:16`) | **None** |
| Cloudflare LB pool | **No — and there is no LB.** Zero `cloudflare_load_balancer` / `default_pool_ids` resources exist in the entire root (verified by CPO). Web-2 is *stronger* than weight-0: it is in no pool because no pool exists | **None** |
| `/workspaces` (per-user worktrees) | **No** — host-local NVMe; no user's lease resolves to web-2 (ADR-068 §(c) gate has never cleared) | **None** |
| Private-net deploy fan-out peer | Yes, nominally — but dormant; and web-2 is the subject of open #6415/#6416 (not provisioned) | Transient; the fan-out is a no-op at the current single-serving-host state |
| **`deploy.soleur.ai` / `ssh.soleur.ai` / `registry.soleur.ai` (the rogue connector)** | **Yes — ~half the vantages** | **This is the thing being deleted.** During the window the tunnel drops to one connector, which **is the target state** |

### Zero-downtime path — evaluated, and it is the default

**The operation is zero-downtime by construction for every legitimate serving surface.** No blue-green, rolling, or expand-contract cutover is required, because web-2 serves no legitimate surface to drain:

- **No drain needed** — no user traffic, no LB pool, no lease-holding worktrees.
- **The only traffic web-2 answers is the defect itself.** Removing it is the fix, not an outage. Framing the connector loss as "downtime" would be a category error: those vantages were being served *wrongly*.
- **web-1 is untouched.** The `-replace` is scoped to `hcloud_server.web["web-2"]` + 3 web-2 targets; `hcloud_server.web["web-1"]` is not in the target set, and `user_data`/`image` sit in its `ignore_changes` anyway.
- **The data volume is preserved** — `hcloud_volume.workspaces["web-2"]` is deliberately not targeted (`:1143-1144`), asserted 0-destroy post-apply from the *saved* plan (`:1189-1195`).
- **Blue-green was considered and rejected as churn:** provisioning a fresh web-3 and retiring web-2 would achieve the identical end state at strictly higher cost and risk (a second host in a capacity-constrained DC), to drain a host that serves nothing.

**Residual downtime: none.** No maintenance window is required and no operator sign-off on downtime is sought, because no serving surface goes offline.

### The real availability risk is to the APPLY PIPELINE, not to a serving surface

Stated plainly so the zero-downtime finding is not read as "risk-free": if the `-replace` destroys web-2 during an fsn1 capacity shortage and cannot re-place it, **every infra apply-on-merge wedges** on `resource_unavailable` (`variables.tf:86-92`; `hcloud_server.web` is reachable in the per-PR apply path as a dependency of the targeted `hcloud_firewall_attachment.web`, `ADR-068:531-533`). That is a **CI/deploy-plane** outage, not a user-facing one — and it is the one accepted risk in this plan.

- **Lever:** flip `var.web_hosts["web-2"].location` off the starved DC and re-dispatch (the documented 2026-07-13 remedy).
- **Per-stage verification:** the `web2_*` destroy-guard counters + the coherence preflight both **abort before anything is destroyed** — the failure mode is "nothing happens," not "half a host."
- **Rollback:** see Risks — re-pooling costs a second full recreate (the token bakes into the systemd unit at first boot and `ignore_changes=[user_data]` blocks a config-only revert). **A bad de-pool is not quickly undoable.**

## Observability

```yaml
liveness_signal:
  what: "Connector census (Cloudflare API) every watchdog tick + host_id on GET /hooks/deploy-status and GET /hooks/inngest-liveness"
  cadence: "census every 15 min (scheduled-inngest-health.yml); host_id on every read"
  alert_target: "GitHub issue labelled action-required (the ONLY wire into operator-digest) when connectors != 1"
  configured_in: ".github/workflows/scheduled-inngest-health.yml; apps/web-platform/infra/hooks.json.tmpl:100,155"

error_reporting:
  destination: "Sentry (existing emit_fail envelope, tags.host_id) + an action-required GitHub issue"
  fail_loud: true  # resolve_host_id returning empty emits host_id:"" — never omits the field. An absent field is indistinguishable from an old script; an empty one is not.

failure_modes:
  - mode: "web-2 (or any non-primary host) re-joins the tunnel — a recreate without the gate, a predicate regression, a hand-run cloudflared, or §(c) clearing at GA"
    detection: "connector census != 1, every 15 min. VANTAGE-INDEPENDENT — the only instrument that is."
    alert_route: "action-required issue -> operator-digest"
  - mode: "deploy.soleur.ai answers from a non-primary host (#6425 recurrence)"
    detection: "host_id in the response != hetzner-<web-1 id>. IN-SURFACE probe — the response identifies its own emitter, discriminating 'two origins' from 'one broken origin' in ONE read: exactly the discrimination the 16h investigation lacked."
    alert_route: "action-required issue; SOLEUR_ORIGIN_HOST_CHURN breadcrumb in the workflow log"
  - mode: "resolve_host_id drifts between its 3 copies"
    detection: "token drift-guard test"
    alert_route: "CI red on PR"
  - mode: "restart-inngest-server.yml self-triggers a prod restart"
    detection: "job reached with event_name=push"
    alert_route: "CI red on PR (AC7)"

logs:
  where: "journald -> Vector -> Better Stack Logs source 2457081 (per-host host_name discriminator, #6396); Sentry for fatal boot stages"
  retention: "Better Stack default; Sentry 90d"

diagnostic:  # NOT an alert route — a log marker is not an alert (see below)
  SOLEUR_ORIGIN_HOST_CHURN: "agent-facing breadcrumb in the watchdog log, mirroring SOLEUR_INNGEST_LIVENESS_VERDICT / SOLEUR_ZOT_DISK"

discoverability_test:
  command: |
    # No SSH. Connector census — the vantage-independent invariant.
    # Count CONNECTORS (entries with >=1 live conn), NOT the tunnel's `connections` int
    # and NOT per-entry `conns` — three different countable things (verified live).
    TUNNEL_ID=$(curl -s -H "Authorization: Bearer $CF_API_TOKEN" \
      "https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT_ID/cfd_tunnel?name=soleur-web-platform" \
      | jq -r '.result[0].id')
    curl -s -H "Authorization: Bearer $CF_API_TOKEN" \
      "https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/connections" \
      | jq '[.result[] | select((.conns|length) > 0)] | length'
  expected_output: "1 (pre-fix baseline, measured live 2026-07-15: 2 — clients 8c57fcd5/fra* = web-2, a281fb1b/ams*+hel* = web-1)"
```

**The detector gap this closes (CTO Q5a — the sharpest panel finding).** v1 ran the census **once, manually**, then left the only standing check as a 15-min watchdog reading `host_id` from **one vantage** — which v1 itself declared proves nothing. So a future re-join would revert detection to *exactly the 2026-07-15 conditions*: v1 closed the incident without closing the detector gap. Wiring `CF_API_TOKEN` + `CF_ACCOUNT_ID` into `scheduled-inngest-health.yml` converts AC1 from a one-shot into a **standing regression guard** — the one change that would have caught this on day one **and every day after**. The token already has the scope; the wiring is the whole cost.

**Why `action-required` specifically (CTO Q4):** `operator-digest` harvests **only** open issues labelled `action-required`. `scheduled-inngest-health.yml` files `ci/inngest-down` / `ci/inngest-functions-degraded` / `ci/inngest-restart-exhausted` — **never** `action-required`. And `SOLEUR_*` markers are grep targets in workflow logs, not alert routes. v1 listed the churn marker under `alert_route:` — **a log marker is not an alert route**; as specified, churn would be detected and discarded into a log nobody greps until the next 16h investigation. Reclassified above.

---

## Implementation Phases

Contract-changing edits precede consumers; the read-only probe precedes everything.

### Phase 1 — Read-only (no diff)
1.1. Run the Hypothesis-5 `host_id` probe (#6400 **and** #6357). Comment findings on those issues. Not an AC.
1.2. Baseline census — **already measured** (Overview). Carry the numbers into the PR body; do not re-derive.
1.3. **Confirm the two delivery paths** (the table above). `cat-deploy-state.sh` is baked (`server.tf:19`) **and** DPF-pushed; `inngest-inventory.sh` is DPF-pushed **only** (`server.tf:910`). No new files → no bake-set/Dockerfile/`.dockerignore` change; `cloud-init-user-data-size.test.ts:384-393`'s hardcoded `28` stays valid. *(v1 asserted both were in `host_script_files` — false.)*

### Phase 2 — Deliverable 1: gate the connector
2.1. **RED first:** add the AC5 render assertion; it must fail on `main`.
2.2. `server.tf` — add `web_tunnel_connector = each.key == "web-1"`. Leave `:158` alone.
2.3. `cloud-init.yml:588-593` — wrap in `%{ if web_tunnel_connector ~}`, mirroring `:664`.

### Phase 3 — Deliverable 2: host identity
3.1. Copy `resolve_host_id()` **verbatim** from **`ci-deploy.sh:137-156`** — the range **must include `:156`**, `HOST_ID="$(resolve_host_id || true)"`. The `|| true` is load-bearing: both targets run `set -euo pipefail` (`cat-deploy-state.sh:2`, `inngest-inventory.sh:75`) and `resolve_host_id` `return 1`s when metadata is unreachable **and** `/etc/machine-id` is unreadable → a bare `HOST_ID="$(resolve_host_id)"` **aborts the hook**, turning `/hooks/deploy-status` into a non-200. *(v1/v2 cited `:137-155`, which excludes it.)*
   - **Placement trap:** `inngest-inventory.sh:509` guards on `BASH_SOURCE` with the invariant *"sourcing (the unit test) must NOT hit the network"* — a top-level `HOST_ID=` would fire `curl --max-time 3` on every invocation, including unit tests. Place it inside the execution guard.
   - **`SOLEUR_HOST_ID_OVERRIDE` is mandatory in the harness**, not optional: both suites run `bash "$TARGET"` and runners have `/etc/machine-id` → an unset override yields a nondeterministic `machine-<id>`.
   - The function is otherwise standalone-safe: bash-only, deps `curl`/`tr`/`printf`, no `ci-deploy.sh` helpers or vars.
3.2. `SOLEUR-DEBT` marker on each copy. **State the true reason** — *distribution* cost, not sourcing mechanics:
   > `SOLEUR-DEBT: Nth of 3 resolve_host_id copies (ci-deploy.sh source-of-truth). Kept in sync by test_host_id_drift_guard, NOT a shared sourced lib — sourcing works in infra (ci-deploy.sh:703), but DISTRIBUTING a new script costs ~11 surfaces (push-infra-config.sh, hooks.json.tmpl, infra-config-apply.sh FILE_MAP, infra-config-install.sh DEST_SPEC + its 2 hardcoded counts, server.tf triggers_replace, apply-deploy-pipeline-fix.yml paths, ship-deploy-pipeline-fix-gate.test.ts, ship/SKILL.md) plus the bake path. Upgrade trigger: a 4th copy OR any consumer outside infra/. Tracked: #<deferral>.`
3.3. **Token drift guard** (~8 lines), mirroring `test_durability_drift_guard` (`inngest-inventory.test.sh:345`) — whose own comment reads *"Token co-occurrence guard (**NOT a verdict-equivalence proof** — the five Phase-2.2 verdicts pin THIS parser)"*. The precedent deliberately splits the work: **behavioral tests prove equivalence, the grep trips on rename.** `resolve_host_id` is better positioned than `derive_durability_state` for that split — it already has both seams (`ci-deploy.sh:138-145`), `ci-deploy.test.sh:1635-1647` exercises `SOLEUR_HOST_ID_OVERRIDE`, and AC2/AC3 give each new copy a behavioral test for free.
   ```bash
   tokens=(SOLEUR_HOST_ID_OVERRIDE SOLEUR_HOST_ID_METADATA_URL 'hetzner-%s' 'machine-%s')
   # assert every token present in ci-deploy.sh, cat-deploy-state.sh, inngest-inventory.sh
   ```
   *(v1 proposed a ~30-line normalized-body guard, arguing a token guard "proves reference, not equivalence" — a strawman: nobody asked the guard to prove equivalence, because the behavioral tests do.)* **Cite the function name, not a line range.**
3.4. **Consumers.** `cat-deploy-state.sh`: `--arg hid "$HOST_ID"`, place `host_id: $hid` in the **outer** object literal (last in the merge chain, `:344`) so a state-file key cannot clobber it; do not touch the `exit_code` sentinel (#2205).
   `inngest-inventory.sh` — **all four exit paths plus the marker**, not just the JSON emits:
   | Path | Line | Shape |
   |---|---|---|
   | liveness success | `:454` | JSON `jq -nc` |
   | full success | `:504` | JSON `jq -nc` |
   | **DEGRADED** | `:433-435` | **plain text, `exit 1`** |
   | **FATAL** | `:438-440` (also `:191`, `:280`, `:294`) | **plain text, `exit 1`** |
   Add `host_id=` to the DEGRADED/FATAL text lines and to the `SOLEUR_INNGEST_LIVENESS_VERDICT` marker (`:431`, which today carries `mode/health_code/functions/durability` but no host). **The failure paths are the ones that fire the alert** — see AC3.
3.5. Extend `cat-deploy-state.test.sh` + `inngest-inventory.test.sh` (both modes) + the drift guard.

### Phase 4 — Deliverable 3: guard the self-triggering restart workflow
4.1. `restart-inngest-server.yml:30` — add `if: github.event_name == 'workflow_dispatch'`, **citing the existing idiom** (`cutover-inngest.yml:48`, `deploy-inngest-image.yml:29`). Keep the `push` trigger (it genuinely registers the workflow in the Actions UI). Add a test.
4.2. **Check `apply-inngest-rls.yml`** — the *one* real remaining candidate (`push` + `workflow_dispatch`, no `event_name` job guard). If it writes prod on self-trigger, add the same one line inline.
4.3. **File an issue** for a proper class sweep. *(v1 prescribed triaging "11 further workflows" inline and gated it with an AC. Three of its claims were false: the list held 9, not 11; `inngest-watchdog-restart-dispatch.yml:37` **has** a guard (`event_name == 'issues'`) that v1's grep missed; and `cutover-inngest.yml` / `deploy-inngest-image.yml` were already guarded. **v1's own narrow grep produced a wrong enumeration that an AC would have laundered into a checked box** — the exact defect class this plan warns about. Do not re-run it inline under a P1.)*

### Phase 5 — Observability wiring (converges CTO Q1#3 + Q4 + Q5a)
5.1. Add `CF_API_TOKEN` + `CF_ACCOUNT_ID` to `scheduled-inngest-health.yml`; run the connector census each tick; file an **`action-required`** issue when `connectors != 1`. Emit `SOLEUR_ORIGIN_HOST_CHURN` as a log breadcrumb.

### Phase 6 — ADR + C4 + deferrals
6.1. ADR-068 amendment (5 items). ADR-082 Item 5. `model.c4` (2 edits) + c4 tests.
6.2. **Full web-2 provisioning — document in-place + comment on the EXISTING #6415/#6416. Do NOT file a new issue.** *(v1/v2 proposed a third umbrella issue "linking #6415, #6416". `wg-when-deferring-a-capability-create-a` says default to documenting in-place and file only when the triple test passes; #6415 and #6416 already track exactly this, so a linking issue is the phantom-backlog pattern by name. Per CPO C5.)*
6.3. Deferral: **host-addressability prerequisite** (P0-1) — fan-out-aware deploy-status, per-host infra-config targeting, host-scoped SSH. **GA-scoped; blocks web-2 re-joining the tunnel.** Also record (spec-flow P1-2) that **re-pooling requires a full infra-config + SSH-bridge re-delivery to web-2, not just a weight flip** — post-de-pool, web-2 receives those channels 0% of the time (today ~50%), so its host scripts and `seccomp`/`apparmor` profiles freeze at whatever `PINNED` baked and drift permanently. A freshly-recreated web-2 has **no `inngest-inventory.sh` at all** (it is not baked) → `/hooks/inngest-liveness` on web-2 is broken by construction.
6.4. Deferral: unify the 3 host-identity schemes. Cited by the `SOLEUR-DEBT` markers' `Tracked:` field (the convention requires it — precedent `Tracked: #5450`).
6.5. Deferral: class sweep of self-push-triggered workflows (Phase 4.3).

### Phase 7 — Post-merge
See `## Infrastructure (IaC)` → Phase 7 sequence (freeze → merge → **await release digest** → de-pool → re-push → close).

---

## Acceptance Criteria

### Pre-merge
- **AC2.** `cat-deploy-state.sh` emits top-level `host_id`; `exit_code` unchanged; a state file containing `{"host_id":"evil"}` **cannot** clobber it (jq object `+` is right-wins and the literal is last — `cat-deploy-state.sh:344`).
- **AC3 (rebuilt — v2's axis was wrong).** `host_id` appears on **every** exit path of `inngest-inventory.sh`, asserted on the **success × failure** axis, not the full-vs-liveness axis:
  - liveness success (`:454`, JSON) and full success (`:504`, JSON);
  - **DEGRADED (`:433-435`) and FATAL (`:438-440`) — plain-text `exit 1` bodies**;
  - the `SOLEUR_INNGEST_LIVENESS_VERDICT` marker (`:431`).
  > **This is the correction that saves the deliverable.** `hooks.json.tmpl:160` sets `include-command-output-in-response-on-error: true` precisely so the watchdog can read the FATAL body. The operator's actual 2026-07-15 probe returned **HTTP 500 `FATAL __FETCH_FAILED__`** — a plain-text failure path. `host_id` on the JSON success emits only **would not have been present in the incident that motivated this plan**: the watchdog would still file an anonymous `inngest_down` P1. v2's AC3 passed vacuously against its own stated purpose.
- **AC4.** Token drift guard green at 3 synced copies, **red** on a mutated copy. The negative arm requires the guard be parameterised (`extract_fn_body <file> <fn>` + a `$TMP` fixture) — the precedent greps hardcoded `$SCRIPT_DIR` paths and cannot be handed a fixture.
- **AC5 (latent-critical, two-armed) — the harness already exists.** Use the **`terraform console` render authority** at `apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh:287-300` ("AC7: `web_colocate_inngest` gate — terraform render authority"), which shells `templatefile(...)`, varies the toggle, and `yaml.safe_load`s each render. CI supplies terraform via `setup-terraform` in the `deploy-script-tests` job.
  - `web_tunnel_connector=true` → render **contains** `cloudflared service install` + the token.
  - `web_tunnel_connector=false` → render **contains neither**.
  - Both `yaml.safe_load` clean (guards the column-0 hazard below).
  - **Plus a separate source assertion** on `server.tf` that the predicate is `each.key == "web-1"` — the render test cannot see which host maps to which toggle value, and that mapping *is* the risk that darkens web-1.
  > *(v2 pointed AC5 at `cloud-init-user-data-size.test.ts` — wrong: that file is a **model** (`readFileSync` + `gzipSync` + regex), and its `renderedSize` **never evaluates `%{ if }`**. It is not a render authority. v1 pointed at `terraform plan` — also wrong: `base64gzip` + `sensitive` + `ignore_changes` make the rendered `user_data` unreadable there, and it is never rendered for existing hosts at all.)*
- **AC6 → post-merge.** *(v1/v2 filed it pre-merge. `apply-web-platform-infra.yml` has **no `pull_request` trigger** — there is no PR-time terraform plan for this root. Its byte-size half was doubly wrong: `ignore_changes=[user_data]` means size is observable only at a CREATE, i.e. the recreate plan. Size is guarded pre-merge by the `cloud-init-user-data-size.test.ts` model instead.)*
- **AC7.** `restart-inngest-server.yml`'s `restart` job carries the dispatch guard (citing `cutover-inngest.yml:48`); a test asserts it. `apply-inngest-rls.yml` triaged **with evidence**, not pre-judgement.
- **AC8.** ADR-068 amendment present (premise correction, falsified contract, designated-ingress-host invariant, stated availability trade, sole-consumer note) and **does not bind the connector to §(c)**. ADR-082 Item 5 updated.
- **AC9.** `model.c4`'s `tunnel` element description carries the invariant; `tunnel -> hetzner` edge added; c4 tests pass.
- **AC10.** Deferral issues 6.2–6.5 exist; `SOLEUR-DEBT` markers cite 6.4.
- **AC11.** Watchdog census wired: `connectors != 1` files an **`action-required`**-labelled issue (assert the label — it is the only wire into `operator-digest`).
- **AC12.** PR body uses `Ref #6425`, **not** `Closes` (a false-resolved P1 while web-2 is still pooled is a real harm).

### Post-merge (automated)
- **AC6.** `terraform plan` shows **0 to add, 0 to change, 0 to destroy** for `hcloud_server.web` on the merge-triggered allow-list apply; the `web-2-recreate` plan shows web-2's rendered `user_data` under 32,768 bytes (a CREATE — the only place size is observable).
- **AC1 (the invariant).** After `web-2-recreate`, the census returns **exactly 1**:
  `[.result[] | select((.conns|length) > 0)] | length == 1`.
  **Pin that jq.** Three different countable things exist and two make AC1 red on a correct fix (verified live): the tunnel object's `connections: 8`, the `/connections` array's `2` entries, and each entry's `conns: 4`.
  **Host identity is NOT assertable here** — `origin_ip` is `null` on both entries (verified live). Discriminate by colo geography (`ams*`/`hel*` = hel1 = web-1) or defer identity to AC13. *(v1 said "and its origin is web-1" — unimplementable from this endpoint.)*
  > This is the invariant, vantage-independent. A response-poll is a **proxy**: selection is colo-sticky, so 10/10 identical reads from one vantage prove nothing. This is the AC that would have caught the bug on day one.
- **AC13.** `/hooks/deploy-status` returns `host_id == "hetzner-<web-1 hcloud id>"` — equal to the id Terraform holds for `hcloud_server.web["web-1"]` (an identity assertion against a TF-known value, not self-consistency) — identical across 10 reads.
- **AC14.** `/hooks/inngest-liveness` returns the same `host_id`.
- **AC15.** `gh issue close 6425` only after AC1 passes.

---

## Alternative Approaches Considered

| Approach | Verdict |
|---|---|
| **Gate the connector to the primary (chosen)** | One predicate, one place. Retains Option B fan-out. Inert at merge. Repairs ADR-068's falsified verify contract. |
| **Per-host tunnels (`for_each` `cloudflared.web`)** | **Rejected by ADR-068 (`:378-384`)** — risks REPLACING the live tunnel (`config_src` import artifact) = deploy-path outage. Not re-litigated. |
| **`web_tunnel_connector_host` variable** | **Rejected** — a knob that looks like a promotion switch and isn't; permits a connector/A-record/LB-weight split at 3am. Advisor proposed it; CTO's operator-grounded counter prevailed. |
| **`tunnel_token` ternary + bool gate (v1)** | **Rejected** — redundant (one consumer, inside the gate) and creates a divergence surface whose failure mode is web-1 booting dark. |
| **Delete the connector via the Cloudflare API** | **Rejected** — not durable; a live `cloudflared` re-registers in seconds. |
| **Rotate `random_id.tunnel_secret`** | **Rejected** — invalidates web-1's connector too (`ignore_changes=[user_data]` means it never re-runs `service install`). Self-inflicted outage. |
| **SSH to web-2 and disable cloudflared** | **Rejected** — violates `hr-no-ssh-fallback-in-runbooks`, and is self-defeating: `ssh.soleur.ai` routes through the tunnel being fixed. |
| **Remove web-2 from `var.web_hosts`** | **Rejected** — a guarded destroy; fights ADR-068's direction. `web-2-recreate` de-pools additively. |
| **Wait for the deferred 3.D cutover** | **Rejected** — leaves a P1 and a silently-staling sandbox-control delivery path open indefinitely. |

---

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| **`-replace` during an fsn1 shortage destroys web-2 and wedges every apply-on-merge** (P0-2, `variables.tf:86-92`) | Disclosed, not minimised. Lever: flip `var.web_hosts["web-2"].location` off the starved DC, re-dispatch. Volume preserved. |
| **Coherence preflight aborts the de-pool** (P1-1) | Phase 7 step 2 gates on the web-1 release landing the new digest. |
| **De-pool dispatch silently cancelled by a routine push** (P1-5, `ADR-068:873-879`) | Phase 7 step 0 engages the merge-freeze. Presents as a stall (we use `Ref`, not `Closes`). |
| **Predicate inverted → a future web-1 recreate boots the live host dark** | AC5's two-armed render assertion. Highest-consequence latent risk; do not weaken to the web-2 arm alone. |
| **Availability: web-1 connector death now takes deploy+ssh+registry dark with no fallback** (P2-1) | **A stated trade**, recorded in the ADR: a silent-wrong-answer mode → a loud-total-outage mode. Bounded by systemd restart-on-failure; worthless anyway if web-1's host dies (`app.soleur.ai` → web-1). |
| **§(c) clears at GA → web-2 re-joins → #6425 recurs** | **P0-1.** The connector is gated on designated-ingress-host, **not** §(c). Host-addressability filed as a GA-scoped blocker (6.3). |
| **#6413**: `validate` already fails on cloud-init's YAML-directive schema; we add a 2nd `%{ if ~}` | Pre-existing, p3-low, **non-required**. Do not fix here; note in the PR body. |
| **Cloudflare connector-selection semantics assumed** | AC1 measures connectors directly; the baseline was measured live, not inferred. |
| **Panel found wrong shell line-range citations in v1/v2** (`ci-deploy.sh:277-287`, `:1135-1152`, `inngest-inventory.sh:366-369` → `:367-370`) | `/work` **must re-verify every `.sh` line citation** before relying on it. Ironic given this plan's own Sharp Edge — hence the explicit task. |
| **No rollback exists, and it costs the same as the de-pool** (spec-flow P1-3) | Stated, not hidden. The token bakes into web-2's systemd unit at first boot and `ignore_changes=[user_data]` means a config-only revert never reaches a running web-2 → re-pooling = revert the predicate **+ a second full recreate**, subject to the same fsn1 capacity risk and the same coherence preflight. **A bad de-pool is not quickly undoable.** |
| `soleur-host-bootstrap-observability.test.sh:152` greps the cloud-init **template** for the cloudflared readiness line | Still passes (the literal stays in the template) but **no longer proves every host has the async-death detector**. AC5's two-armed **render** assertion must carry that weight. The H3 ordering assertions (`:134-138`) still pass — `:586` stays ungated. |

---

## Open Code-Review Overlap

Checked 62 open `code-review` issues against every Files-to-Edit path. Two `server.tf` substring hits, both **Acknowledge — no collision**: **#2197** (real edits are `lib/billing/types.ts` + `server/rate-limiter.ts`; cites `server.tf` only as an illustration; its proposed "fail if `server.tf` gains `count`/`for_each`" check does not trip — `for_each` predates us and we add neither) and **#3216** (a test regex that *parses* server.tf; we edit inside an existing block and add no top-level block). Zero hits elsewhere.

---

## Files to Edit

| File | Change |
|---|---|
| `apps/web-platform/infra/server.tf` | add `web_tunnel_connector` templatefile var (`:158` untouched) |
| `apps/web-platform/infra/cloud-init.yml` | wrap `:590`+`:593` in `%{ if web_tunnel_connector ~}` |
| `apps/web-platform/infra/cat-deploy-state.sh` | `resolve_host_id()` + `SOLEUR-DEBT`; `host_id` in the outer jq literal |
| `apps/web-platform/infra/inngest-inventory.sh` | `resolve_host_id()` + `SOLEUR-DEBT`; `host_id` in both modes |
| `apps/web-platform/infra/cat-deploy-state.test.sh` | `host_id`; no `exit_code` clobber; drift guard |
| `apps/web-platform/infra/inngest-inventory.test.sh` | `host_id` both modes; drift guard (+ negative arm) |
| `apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh` | **AC5's two-armed render assertion** (the `terraform console` render authority at `:287-300`). **This file breaks whether or not we want it to:** its `render_ci()` hardcodes the full templatefile var map and its own comment says *"a new map var breaks this render (the intended tripwire)"* — adding `web_tunnel_connector` trips it. Worse, `terraform console 2>/dev/null` (`:296`) **swallows the error**, so it surfaces as a confusing YAML failure, not the real cause |
| `plugins/soleur/test/cloud-init-user-data-size.test.ts` | pre-merge size guard only (a **model**, not a render authority — `renderedSize` never evaluates `%{ if }`). **Also fix its stale comment at `:40-41`** ("web user_data uses bake-and-extract, *not* base64gzip") — `server.tf:147` **does** use `base64gzip` (#6090) |
| `.github/workflows/restart-inngest-server.yml` | `:30` dispatch guard |
| `.github/workflows/scheduled-inngest-health.yml` | connector census + `action-required` issue on `!= 1` |
| `.github/workflows/apply-inngest-rls.yml` | triage; guard if it writes prod on self-trigger |
| `knowledge-base/engineering/architecture/decisions/ADR-068-multi-host-workspaces-shared-git-data-lease-coordinator.md` | amendment (5 items) |
| `knowledge-base/engineering/architecture/decisions/ADR-082-fresh-web2-boot-observability.md` | Item 5 — read-surface `host_id` extension |
| `knowledge-base/engineering/architecture/diagrams/model.c4` | `tunnel` element description; `tunnel -> hetzner` edge |

## Files to Create

None. No shared `resolve-host-id.sh`: sourcing works in infra (`ci-deploy.sh:703`), but **distributing** a new script costs ~11 surfaces plus the bake path. Duplicate-and-pin per `test_durability_drift_guard`.

---

## Domain Review

**Domains relevant:** Engineering (CTO — reviewed), Product (CPO — sign-off pending).

**Product/UX Gate:** **NONE.** Mechanical UI-surface scan against `plugins/soleur/skills/brainstorm/references/ui-surface-terms.md`: no Files-to-Edit path matches `components/**/*.tsx`, `app/**/page.tsx`, `app/**/layout.tsx`, or any UI glob. Infrastructure/ingress change, no user-facing surface.

**GDPR / Compliance Gate (2.7):** invoked on trigger (b) (`single-user incident`); no regulated-data surface (no schema/migration/auth/API route/`.sql`). The change **reduces** credential spread (web-2 no longer receives the tunnel token).

**Brainstorm-recommended specialists:** none (direct one-shot entry, no brainstorm).

---

## Test Scenarios

Runner: `apps/web-platform/infra/*.test.sh` are plain `bash` (existing convention); TS tests under `plugins/soleur/test/`. **No new framework.**

1. `host_id` in `/hooks/deploy-status`; `exit_code` intact; hostile state file cannot clobber.
2. `host_id` in `/hooks/inngest-liveness` (`INVENTORY_LIVENESS_ONLY=1`) **and** full inventory.
3. `resolve_host_id` honours `SOLEUR_HOST_ID_OVERRIDE` / `SOLEUR_HOST_ID_METADATA_URL` (CI has no metadata service; seams exist at `ci-deploy.sh:138-145`).
4. Drift guard: green at 3 synced copies, **red** on a mutated copy.
5. Render: web-1 has `cloudflared service install` + token; web-2 has neither.
6. `restart-inngest-server.yml` job carries the dispatch guard.
7. `terraform plan`: `hcloud_server.web` 0/0/0.
8. Census jq returns 1 against a 1-connector fixture and 2 against the recorded 2-connector fixture.

---

## Deferred

| Item | Why | Re-evaluation trigger | Tracking |
|---|---|---|---|
| Full web-2 provisioning (inngest + vector) | Operator-fixed scope | #5274 Phase 3.D cutover | 6.2; relates #6415/#6416 |
| **Host-addressability of the non-fan-out paths** | **P0-1 — the GA blocker for web-2 re-joining the tunnel** | GA cutover | 6.3 |
| Unify the 3 host-identity schemes | Duplicate-and-pin is the convention | A 4th copy **or** any consumer outside `infra/` | 6.4 |
| Class sweep of self-push-triggered workflows | Proportionality under a P1; v1's inline enumeration was wrong | — | 6.5 |
| Fix #6400 / #6357 | Operator-fixed scope; root cause unproven | Phase 1.1 probe returns ≥2 `host_id`s | #6400 / #6357 (comment only) |
| Fix #6413 cloud-init `validate` schema | Pre-existing, p3-low, non-required | — | #6413 |

---

## Review Corrections

What the 7-reviewer panel + advisor changed. Recorded because several are lessons, not edits.

| # | v1 claim | Verdict | Source |
|---|---|---|---|
| 1 | "ADR-068 *accepted* the multi-connector topology; this is a *fifth option*" | **Category error.** The "so" clause is a premise; the CTO never ruled on connector count. The honest + stronger framing: the 2-connector state **falsifies ADR-068's own verify contract** (`:720-722`, `:826`). | DHH, architecture-strategist |
| 2 | `tunnel_token` ternary **and** bool gate | **Correctness bug.** One consumer, inside the gate → ternary redundant; two predicates can diverge → web-1 boots dark. | code-simplicity |
| 3 | Add the connector to ADR-068 §(c)'s gated set | **P0 — GA time bomb.** §(c) clears at GA → web-2 re-joins → #6425 recurs while web-2 serves users. Gate on *designated ingress host* instead. | architecture-strategist |
| 4 | Failed `-replace` "loses a warm standby" | **P0 — understated.** It **wedges every apply-on-merge** (`variables.tf:86-92`, the very line v1 cited). | architecture-strategist |
| 5 | merge → immediately dispatch `web-2-recreate` | **Will abort.** Editing `cat-deploy-state.sh` changes `host_scripts_content_hash` → the coherence preflight (`:1122-1130`) fails until web-1 carries the new digest. | architecture-strategist |
| 6 | Both scripts are in `host_script_files` | **False.** `inngest-inventory.sh` is DPF-webhook-only (`server.tf:910`). Different delivery mechanisms. | architecture-strategist |
| 7 | C4 edit on the `tunnel -> coordinator` edge | **Wrong target** — that edge models the deferred 3.D rewire. Use the `tunnel` element description; add the missing `tunnel -> hetzner`. | architecture-strategist |
| 8 | §(c) is at `:703-714`, gates LB weight + the A record | **Wrong line and content.** §(c) is `:566-575`; gates LB weight only. | architecture-strategist |
| 9 | "11 further workflows, zero dispatch guards" | **False ×3.** List held 9; `inngest-watchdog-restart-dispatch.yml:37` has a guard my grep missed; the idiom already exists. **My own narrow grep produced a wrong enumeration an AC would have laundered into a checked box.** | code-simplicity, CTO |
| 10 | Normalized-body drift guard | **Gold-plating.** The precedent's own comment delegates equivalence to behavioral tests, which AC2/AC3 already provide. | code-simplicity |
| 11 | AC5 via `terraform plan` grep | **Unverifiable** — `base64gzip` renders a gzipped blob. Use the existing TS render harness. | own verification |
| 12 | AC6 asserts 0-diff **and** byte size | **Mutually exclusive** — a 0-diff plan renders no `user_data`. | code-simplicity |
| 13 | web-1 `user_data` grows ~40 bytes; 32KB risk | **False** — directives are consumed at render; growth ~0. Risk row deleted. | code-simplicity |
| 14 | AC1 = "exactly one connector, origin web-1" | **Ambiguous + partly unimplementable.** Three countable things; `origin_ip` is `null`. Pinned jq; identity deferred to AC13. | CTO (ran it live) |
| 15 | `SOLEUR_ORIGIN_HOST_CHURN` under `alert_route` | **Dead signal.** A log marker is not an alert route; `operator-digest` reads only `action-required` issues. | CTO |
| 16 | Census run once, manually | **Detector gap left open** — a re-join would revert to 2026-07-15 conditions. Wired into the watchdog (Phase 5). | CTO |
| 17 | "Infra has no source-lib precedent" | **False** — `ci-deploy.sh:703` sources. The real blocker is *distribution*. Marker reworded. | CTO |
| 18 | `web_tunnel_connector_host` variable | **Advisor proposed, CTO rejected** — a knob that permits an ingress split at 3am. CTO prevailed. | advisor vs CTO |
| 19 | "Open Code-Review Overlap: None" | **Wrong** — the query had errored; those "none" lines were vacuous. 2 hits; both dispositioned. | own verification |
| 20 | **AC3: `host_id` on the JSON emits** | **The deliverable would have missed its own incident.** `inngest-inventory.sh` has **4** exit paths; DEGRADED (`:433-435`) and FATAL (`:438-440`) are **plain-text `exit 1`** bodies that `hooks.json.tmpl:160` deliberately surfaces to the watchdog. The operator's actual probe returned **HTTP 500 `FATAL __FETCH_FAILED__`** — a path with no `host_id`. AC3 passed vacuously against its own purpose. | Kieran |
| 21 | AC5 via `cloud-init-user-data-size.test.ts` (v2's fix for v1's `terraform plan` error) | **Still wrong** — that file is a **model** (regex + `gzipSync`); `renderedSize` never evaluates `%{ if }`. The real render authority is `cloud-init-inngest-bootstrap.test.sh:287-300` (`terraform console` + `yaml.safe_load`) — the test that proves the `web_colocate_inngest` gate. v1/v2 cited that gate as precedent but missed its test. | Kieran |
| 22 | `cloud-init-inngest-bootstrap.test.sh` not in Files to Edit | **The change breaks it** — `render_ci()` hardcodes the var map ("a new map var breaks this render — the intended tripwire") and `2>/dev/null` swallows the error. | Kieran |
| 23 | `resolve_host_id` copy range `:137-155` | **Excludes the load-bearing `|| true` at `:156`.** Under `set -euo pipefail` a bare assignment **aborts the hook** → non-200. | Kieran |
| 24 | AC6 pre-merge | **No `pull_request` trigger** on `apply-web-platform-infra.yml` → no PR-time plan exists. Moved post-merge. | Kieran |
| 25 | `[skip-deploy-fix-apply]` "optional" | **Load-bearing.** The racing run *consumes* the `triggers_replace` hash → the later dispatch is a **no-op** → deliverable 2 never lands. | spec-flow |
| 26 | Deferral 6.2 = a new umbrella issue | **Phantom backlog** — #6415/#6416 already track it. Document in-place + comment. | CPO (C5) |
| 27 | Threshold argued from the badness of the bug | **Wrong reasoning, right verdict.** Re-anchored on diff-side grounds (credential touch + remediation-channel loss). | CPO (C4) |

**Unresolved — surfaced, not auto-applied:** the **two-PR split**. **Three reviewers converged on it independently** (DHH on proportionality; spec-flow on P0-a/P0-b; architecture-strategist on the coherence-preflight coupling), and it *dissolves* both P0s rather than compensating for them. It argues against the operator's stated scope, so it is a **User-Challenge** → `knowledge-base/project/specs/feat-one-shot-6425-web2-tunnel-depool-host-id/decision-challenges.md` **UC-1**. The operator's direction is retained as the default and Phase 7's two compensations (mandatory kill switch + release-wait) make it correct as asked.

---

## Sharp Edges

Canonical home for the facts this plan turns on. Other sections cite; they do not restate.

- **`ignore_changes = [user_data]` is on the `for_each` resource** — it applies to *every* instance. "web-2 is fresh so it gets the new user_data" is **wrong** for an already-created web-2. New `user_data` reaches it only through a `-replace`.
- **The remediation channel is the broken channel.** `/hooks/infra-config`, `/hooks/deploy-status`, and `ssh.soleur.ai` all traverse the tunnel being fixed. De-pool first — Terraform/Hetzner is the only lever outside it.
- **Connector selection is colo-sticky, not per-request.** `10/10 identical` from one vantage proves nothing about another. Count connectors via the Cloudflare API; never verify de-pooling from a single vantage.
- **Three countable things in the CF connections response** — the tunnel's `connections` int, the `/connections` array length, and each entry's `conns`. Two of the three make AC1 red on a correct fix. `origin_ip` is `null`.
- **`base64gzip(templatefile(...))` + `sensitive` + `ignore_changes` make rendered `user_data` unreadable at `terraform plan` — three independent blockers.** The render authority is `terraform console` on the `templatefile(...)` expression (`cloud-init-inngest-bootstrap.test.sh:287-300`). A *model* that regexes the template (`cloud-init-user-data-size.test.ts`) is not a render authority — it never evaluates `%{ if }`.
- **`%{ if }` directives must sit at column 0.** Indenting one leaves the leading spaces after the `~` trim and corrupts `runcmd:` list indentation — the only real YAML hazard here.
- **A templatefile var referenced inside ANY `%{ if }` branch must be in the vars map.** `MakeTemplateFileFunc` pre-checks `expr.Variables()`, and a `ConditionalExpr`'s walk covers both branches. The gate suppresses the render, never the key requirement. Corollary: any test that hardcodes the var map (`cloud-init-inngest-bootstrap.test.sh:294`) breaks on a new var — by design.
- **`include-command-output-in-response-on-error: true` means the FAILURE bodies are the alert surface.** For `inngest-inventory.sh`, the paths that fire the watchdog's `inngest_down` are plain-text `exit 1`, not the JSON emits. Diagnostics added only to the success paths are invisible exactly when they matter.
- **A `-target` apply with no `-replace`/taint re-runs a provisioner only when `triggers_replace` moves.** Whoever consumes the hash first wins; a later dispatch against identical contents is a silent no-op.
- **A log marker is not an alert route.** `operator-digest` harvests only `action-required`-labelled issues — never PR bodies, never workflow logs.
- **`cat-deploy-state.sh` is baked; `inngest-inventory.sh` is not.** Editing the former moves `host_scripts_content_hash` and arms the `web-2-recreate` coherence preflight.
- **Don't cite shell line ranges in comments.** The existing `durability_state` guard's `ci-deploy.sh:277-287` citation is already stale. Cite function names. (v1 propagated three such errors.)
- **`inngest-inventory.sh` serves two hooks** (`/hooks/inngest-inventory`, `/hooks/inngest-liveness` with `INVENTORY_LIVENESS_ONLY=1`). `host_id` on only the full path leaves the watchdog's surface blind.
- **`hcloud_server.web` is `OPERATOR_APPLIED_EXCLUSIONS`** (`terraform-target-parity.test.ts:482`), `-target`ed at exactly one line (`:1150`). Adding it to the push allow-list would put the live web hosts on the per-merge apply path.
- A plan whose `## User-Brand Impact` is empty or placeholder fails `deepen-plan` Phase 4.6. It is filled.
