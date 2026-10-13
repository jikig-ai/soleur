# Brainstorm: Active-Active Web Cluster via IaC (re-add web-2, de-pet web-1, blue-green host lifecycle)

- **Date:** 2026-07-24
- **Branch:** feat-web-active-active-iac
- **Draft PR:** #6919
- **Tracking issue:** #6459 (blue-green host replacement — ADR needed); interacts with #6608 (inngest allowlist derivation)
- **Lane:** cross-domain
- **Brand-survival threshold:** single-user incident
- **Chosen approach:** A — Phased "cluster-first, flip-last"

## What We're Building

Make Soleur's web tier a **full active-active cluster** (web-1 + web-2 serving concurrently) built
**entirely via Terraform IaC**, such that every host is disposable/cattle. The operator's proof-goal:
once a fresh IaC-built web-2 serves traffic properly, **destroy web-1 and rebuild it purely from IaC**.

**Reframe from research:** the multi-host machinery already exists (`var.web_hosts` `for_each`; deploy
fan-out code is dormant-but-present). Re-adding web-2 as a *host* is nearly free. What's missing is the
**health-gated ingress/drain layer** (no load balancer today; `dns.tf` app record is a singleton pinned
to web-1) and **proven fresh-boot readiness**. And **concurrent serving (`replicas>1`) is gated on the
ADR-068 Phase-2→3 GA chain** — two hosts writing one workspace's git index corrupts it. So we
**decouple the cluster build from the concurrent-serving flip.**

## Why This Approach (A — cluster-first, flip-last)

Every step is independently valuable and nothing blocks on the ADR-068 GA chain we don't control here.
Order:

1. **Fresh-boot readiness gate** (the #6459 re-eval trigger — 3 silent-boot postmortems) + **cloud-init
   parity** (fold web-1's ~11 SSH provisioners into cloud-init so a fresh boot reaches parity).
2. **Health-gated ingress layer** — Cloudflare Load Balancer (weighted pool + health monitors) and/or
   multi-connector CF Tunnel (already architected in `tunnel.tf`), replacing the singleton `dns.tf`
   app record. This is the missing **drain** primitive.
3. **Birth fresh cattle web-2** as a **health-gated warm standby** (hold `replicas=1`). Resolve #6608
   (inngest nftables allowlist derivation) in its **own** maintenance-window inngest recreate — it is
   `user_data` ForceNew and would otherwise replace the prod scheduler.
4. **Prove disposability on web-2** (destroy + IaC-rebuild the *standby*, never web-1 first).
5. **De-pet web-1 = blue-green cattle-rebuild:** add a cattle sibling, drain web-1 off ingress,
   reprovision web-1 fresh, then drop `ignore_changes=[user_data]` + provisioners **together**.
6. **Flip to concurrent active-active serving** only when **ADR-068 Phase-3 GA lands** (`#6416` +
   ADR-115 `luksOpen` → git-data host → coordinator routing). Until then: `replicas=1` + web-2 as a
   health-gated warm standby.

## Key Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| D1 | End state = **full active-active** (operator-confirmed) | Consistent with ADR-068's recorded operator choice (one workspace servable across hosts concurrently) |
| D2 | **Decouple build from flip** — build cluster + warm standby now, flip to concurrent serving at ADR-068 Phase-3 GA | `replicas>1` never enabled; dual-writer git corruption without Phase-3 lease coordinator |
| D3 | **Fresh-boot readiness assertions are a hard gate** before de-pet/destroy | #6459 re-eval trigger; 3 silent-boot postmortems; `hr-fresh-host-provisioning-reachable-from-terraform-apply` |
| D4 | **Prove disposability on web-2 first**, never destroy web-1 first | Destroying the only live prod host is a confidence milestone, not a GA prerequisite (CPO) |
| D5 | **New ADR** for host-lifecycle + ingress-drain (resolves #6459), amending `hr-prod-host-config-change-immutable-redeploy` + ADR-103 | Blue-green add/drain/remove is an IaC redesign, not a line item |
| D6 | Build the **health-gated ingress/LB layer** — the true blocker for disposability | No LB today; DNS round-robin can't fail a dead host out within TTL |
| D7 | **De-petting web-1 IS the cattle-rebuild** (can't strip `ignore_changes=[user_data]` from the live pet without forcing replacement) | Fold provisioners → cloud-init, add cattle sibling, drain, reprovision, then drop `ignore_changes` |
| D8 | #6608 (inngest allowlist) sequenced as its **own** maintenance-window inngest recreate, NOT inside the web-2 add | `web_host_private_ips` is `user_data` ForceNew — naive change replaces the prod scheduler |
| D9 | Precondition before ANY host destroy: **drain + assert zero un-pushed user work** | Worst-case = permanent invisible loss of un-pushed commits → CLO Art. 33 72h clock |
| D10 | Both hosts stay in an **EU Hetzner DC** | `var.web_hosts` validation (GDPR, CLO T-1, GA-blocking); cross-host replication needs an Art. 30 register entry |

## Open Questions (for the ADR / plan)

1. **DC placement of web-2 (the #1 ADR decision).** hel1 (same-DC: rebuildable via `cx33` stock +
   placement group, but no DC-outage resilience and `-replace`-during-shortage wedges applies — the
   2026-07-13 incident) **vs** fsn1/nbg1 (cross-DC resilience, but `cx33` not orderable there → needs a
   verified-available server-type, and loses placement-group co-location). Blue-green add/drain/remove
   largely dissolves the `-replace` footgun. **Resolve with a live Hetzner stock probe at plan time.**
2. **LB choice:** Cloudflare Load Balancer (weighted pools + monitors — gives weighted drain) vs
   multi-connector CF Tunnel (health-gated by construction, already architected) vs both. Must
   terminate/route in-EU (CLO).
3. **How much of ADR-068 Phase-2/3 does this effort drive** vs consume as an external dependency? (A
   keeps it external; the flip is the final gated step.)
4. **`proxy-tls` cert regen:** adding a SAN regenerates `tls_self_signed_cert.proxy_server` — coordinate
   CA reload so web-1's pinned client doesn't reject web-2.

## User-Brand Impact

- **Artifact:** the active-active web cluster ingress + the web-1/web-2 host-lifecycle (destroy/rebuild) path.
- **Vector:** a botched cutover silently destroys a live user's **un-pushed workspace commits** (git-backed
  recovery does not cover never-pushed work), or a dual-writer flip corrupts a workspace git index, or the
  LB routes to a fresh host that silently failed to boot.
- **Threshold:** single-user incident.

## Domain Assessments

**Assessed:** Engineering (CTO + platform-strategist + terraform-architect), Product (CPO), Legal (CLO).
Operations/Marketing/Sales/Finance/Support: not relevant (internal infra).

### Engineering — CTO
Sequencing: re-add web-2 as warm-standby cattle (safe now) → de-pet web-1 (safe now, prereq for rebuild) →
ADR-068 Phase-3 GA flip (gate) → CF dual-serve (gated) → destroy+rebuild web-1 (last). Top risks:
dual-writer git corruption, no ingress drain/health-gate, fresh-boot silent failure. Verdict: one new ADR
extending ADR-068 + resolving #6459. Gaps: no `hcloud_load_balancer`, no drain mechanism (only deploy-time
cron drain).

### Engineering — Platform Strategist
Recommend multi-connector CF Tunnel (health-gated by construction; `tunnel.tf` already architected for it)
with a `cloudflare_load_balancer` added for weighted drain. Blue-green = add key → for_each builds cattle
host → drain via connector/weight → remove key. De-petting web-1 *is* the cattle-rebuild. Breakage:
placement-group ternary hard-refs `var.web_hosts["web-1"].location`; tunnel origins hard-ref web-1.

### Engineering — Terraform Architect
web-2 re-add = one `var.web_hosts` entry (auto-fans-out) BUT hand edits needed: `dns.tf` singleton app
record (web-2 gets zero ingress until rewired), `inngest-host.tf` ForceNew literal (#6608, sequence
separately), `proxy-tls` cert regen. Parity guards go RED: `inngest-host.test.sh §6b`,
`web-hosts-fanout-parity`, `web-1-swap-concurrency-parity`. Same-DC capacity footgun is the sharpest edge.
Dropping `ignore_changes=[user_data]` alone force-replaces the live host — order matters.

### Product — CPO
Decouple: build cluster + warm standby now, flip at Phase-3 GA. Gate the build on fresh-boot readiness (a
standby that silently fails to boot is worse than none). Destroy-web-1 proof is a confidence milestone, not
a GA-blocker — prove on web-2 first. Worst case: destroying web-1 while a user holds un-pushed commits.
YAGNI: don't build concurrent-serving orchestration while `replicas=1`.

### Legal — CLO
Both hosts stay hel1/EU (GDPR ok). New surfaces: cross-host replication = inter-host personal-data transfer
→ needs an **Art. 30 register** entry; LB must terminate/route in-EU (not a non-EU anycast PoP). Lost
un-pushed work = availability breach (Art. 32(1)(c)) → **Art. 33 72h clock**; dual-writer cross-tenant
write = confidentiality breach, same clock. Threshold confirmed: single-user incident. No new *consent*
surface (Hetzner already-disclosed processor); one *disclosure* surface = Art. 34 subject notice if cutover
loses work.

## Capability Gaps (with evidence)

| Gap | Evidence | Owner |
|-----|----------|-------|
| No load balancer resource | `git grep -n 'hcloud_load_balancer\|cloudflare_load_balancer' -- apps/web-platform/infra/*.tf` → none; `dns.tf:5,13-16` app record is a singleton pinned to `web["web-1"].ipv4_address` | terraform-architect / platform-strategist |
| No ingress drain / health-gate | `git grep -in drain` → only deploy-time cron drain (`cat-deploy-state.sh:235-245`); blue-green add/drain/remove (#6459) unbuilt | platform-strategist |
| No `create_before_destroy` anywhere | `git grep -n create_before_destroy -- '*.tf'` → none (#6459); add-before-remove not yet expressible | terraform-architect |
| Fresh-boot readiness unproven | `knowledge-base/project/learnings/best-practices/2026-05-20-hr-fresh-host-iac.md`; `2026-07-13-warm-standby-cross-dc-and-replace-capacity-footgun.md`; 3 silent-boot postmortems (#6459) | Engineering |
| ADR-068 Phase-2/3 not landed | ADR-068 `Status: adopting`; Phase 2 blocked behind #6416 + ADR-115 `luksOpen`; `replicas>1` never enabled | ADR-068 workstream (external) |

## Prior Art

- `knowledge-base/project/brainstorms/2026-07-15-hetzner-cap-headroom-brainstorm.md` (#6453) — rejected
  cap-preflight + blue-green-via-slots; accepted cap 5→10 + stock fix + `hr` amendment.
- `knowledge-base/project/plans/2026-06-29-feat-multi-host-workspaces-layer-plan.md` (ADR-068) — the
  Phase 0–4 multi-host `/workspaces` epic; Phase 3 is the concurrent-serving GA gate.
- #6538 — old web-2 fsn1-orphan retirement (unrebuildable `cx33`, dark, outside placement group).
