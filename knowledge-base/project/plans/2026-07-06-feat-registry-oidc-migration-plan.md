---
plan: registry-oidc-migration
issue: "#6122"
date: 2026-07-06
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
brainstorm: knowledge-base/project/brainstorms/2026-07-06-registry-oidc-migration-brainstorm.md
spec: knowledge-base/project/specs/feat-registry-oidc-migration/spec.md
supersedes_adr: ["ADR-088"]
amends_adr: ["ADR-087"]
new_adr: "ADR-096 (provisional)"
plan_review: "architecture-strategist + spec-flow-analyzer + code-simplicity-reviewer (single-user-incident panel), 2026-07-06"
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->

# Plan — Migrate container registry off GHCR to self-hosted zot (Hetzner registry host, volume-backed)

## Overview

Move our two private container images (`soleur-web-platform`, `soleur-inngest-bootstrap`) off
GitHub Container Registry onto **a single self-hosted [zot](https://zotregistry.dev) registry
running as a docker/systemd unit on a dedicated small Hetzner "registry" host, with a
Hetzner-volume storage backend**. Hetzner hosts authenticate their `docker pull` with a
**Terraform-generated, read-only htpasswd credential** (zero human mint) read from Doppler at
boot. GitHub Actions pushes to zot; the cosign keyless-signing + offline-verification chain is
preserved unchanged. GHCR is retired for our own images after a dual-push soak.

**Why now:** a GitHub App installation token cannot `docker pull` private repo-linked GHCR
packages — a confirmed GitHub platform limitation ([community #171423](https://github.com/orgs/community/discussions/171423),
no ETA). GHCR cannot provide a zero-touch machine identity, which was ADR-088's whole purpose.

**Design shaped by the plan-review panel (2026-07-06):** the initial draft assumed a Nomad HA job
(fabricated — no orchestrator exists here, ADR-027) and R2-backed multi-writer storage (unsafe —
no cross-instance GC/lock). Operator chose the simplest correct design: single zot, Hetzner-volume,
HA deferred. See Research Reconciliation.

## Research Reconciliation — draft vs. verified codebase reality (2026-07-06)

| Claim (brainstorm/draft) | Reality (verified) | Response |
|---|---|---|
| "zot has native OIDC bearer workload auth" | **FALSE.** zot machine-auth = htpasswd (bcrypt + per-repo read-only ACL) or bearer via an *external* Docker-v2 token server we'd build. No native JWT/OIDC workload mode. | **htpasswd + Terraform `random_password`** — zero human mint, no minter, no token server. |
| "HA Nomad job, mirror existing web/CLI-engine jobs" | **FABRICATED.** ADR-027: "no orchestrator in use"; Nomad is post-GA (ADR-068 Phase 4a). Closest precedent (Inngest) = **systemd units** (`inngest.tf`). No `.nomad` specs; no `cli-engine` jobs. | **Single zot container as a systemd/docker unit** on a dedicated `hcloud_server.registry`. |
| "R2-backed → stateless → HA" | Multi-writer zot over shared R2 races GC/dedupe; R2 has no conditional-write/lock (`main.tf:13`). R2 S3 storage cred likely NOT TF-generable (provider v4 has no resource emitting a retrievable R2 keypair) → would reintroduce the no-default-var merge trap. | **Hetzner volume + snapshot cron** (operator choice). Cut R2 entirely. Durability = CI-reproducibility. |
| "reuse the Inngest minter" | Minter mints GitHub App tokens; re-point = rewrite. | **Retire the minter.** |
| "single `registry` field per boot, reuse #6090 bootcmd beacon" | `#6090` beacon fires at **network stage before any docker pull**; rolling `ci-deploy` deploys never run cloud-init bootcmd. Category error. | **Emit `registry`/`pull_rc`/`login_rc`/`image` at each pull site.** |
| Pull-site inventory (6 sites) | **Incomplete:** missed `cloud-init.yml:591-606` (2nd inngest pull), `apply-web-platform-infra.yml:1070` (imagetools digest-resolve + `docker login ghcr`), `deploy.sh` (soleur:deploy). host-bootstrap login is `:172-199` not `:25-30`. | Full inventory below; all in Phase 3 scope. |
| Dual-push covers rollback | Only **new** tags dual-push; `cloud-init.yml:591` pins `v1.1.18`, `variables.tf:47` defaults `:latest` — **old tags never mirrored** → rollback + fresh-boot break after retirement. | **Backfill last N releases of both images** (crane/skopeo GHCR→zot); retirement gates on "every pinned tag resolves in zot." |
| ADR-088 governs; ghcr in C4 | ADR-087+088 on main (highest ADR-092). `ghcr` = external system `model.c4:242`; `hetzner` desc `:170`. | New **ADR-096** supersedes 088, amends 087; C4 edits in scope. |

## User-Brand Impact

**If this lands broken, the user experiences:** their app fails to boot or deploy — a fresh
Hetzner host can't pull the web-app image from zot (ADR-080 baked-script extraction fails), or a
rolling deploy stalls. Surfaces as a stuck deploy / a tenant app that won't come up.

**If this leaks, the user's workflow is exposed via:** a leaked read-only zot credential lets an
attacker `docker pull` our platform images (source disclosure) — pull-only, in-datacenter,
private-network-scoped; no push, no data.

**Brand-survival threshold:** single-user incident → `requires_cpo_signoff: true` (carried from
brainstorm; no product surface — deploy-availability, not data exposure). `user-impact-reviewer`
runs at PR review.

## Architecture Decision (ADR/C4)

### ADR
Create **ADR-096 — "Container images served from a self-hosted zot registry host (Hetzner,
volume-backed); read-only htpasswd machine credential; GHCR retired for own images"** via
`/soleur:architecture`.
- **Supersedes ADR-088** (installation-token minter — infeasible, GHCR refuses App tokens).
  **Amends ADR-087** (cosign verify: substrate GHCR→zot; verification identity unchanged).
- **Alternatives Considered:** (a) GHCR+App-token minter — *rejected, platform limitation*; (b)
  GHCR+auto-rotated PAT — *rejected, no PAT-mint API*; (c) zot bearer/JWT via self-built Docker-v2
  token server — *rejected, bespoke supply-chain auth (YAGNI)*; (d) R2-backed multi-writer HA —
  *rejected, unsafe (no cross-instance GC/lock) + R2 cred not TF-generable*; (e) R2-backed
  single-writer — *deferred, needs operator mint + multipart spike; volume is simpler*; (f) Quay
  managed — *rejected, new vendor + egress + not in-datacenter*; (g) Nomad HA — *rejected, no
  orchestrator (ADR-027); post-GA per ADR-068*.
- **Cold-boot dependency (state explicitly, per architecture P0-2):** the registry host is a
  boot-time dependency for every web host (= no worse than today's GHCR dependency). Registry host
  is provisioned first, is rarely rebooted, has restart-on-failure + a liveness alert. Its own
  bootstrap pulls zot's image from the upstream public registry (digest-pinned) — no paradox.
- **status: adopting** now; → **accepted** after the retirement soak (Phase 5). Reconcile with
  ADR-068's future-Nomad C4 (note Phase 4a remains deferred; zot stays on systemd). Ordinal
  **provisional** — ship's collision gate re-verifies; on renumber sweep this plan+spec+tasks.

### C4 views (minimal)
Edit the three `.c4` files: add an internal `zotRegistry` container under `platform.infra` (tech
"zot OCI registry, Hetzner registry host, volume-backed" — **not** "Nomad HA"); move the host pull
edge GHCR→zot; correct the `ghcr` external-system description (`model.c4:242` — no longer "source of
the web app image"; retained only as third-party source for `ghcr.io/sigstore/cosign`); add
`zotRegistry` to the `views.c4` include lines (`:14`,`:32`,`:36`). Run
`apps/web-platform/test/c4-code-syntax.test.ts` + `c4-render.test.ts` after.

## Infrastructure (IaC)

New infra: a dedicated Hetzner registry host + volume, a single zot systemd/docker unit, htpasswd
+ push credentials, a firewall rule, Doppler secrets. Routed through Terraform in
`apps/web-platform/infra/`. `terraform-architect` to review `.tf` shaping at /work.

### Terraform changes
- **New `apps/web-platform/infra/zot-registry.tf`:**
  - `hcloud_server.registry` (small, e.g. CAX11) on the existing private network + `hcloud_volume`
    for zot storage (`/var/lib/zot`), attached; cloud-init installs docker + runs zot (digest-pinned
    upstream image) as a systemd unit, mirroring the Inngest systemd pattern (`inngest.tf`).
  - `random_password.zot_pull` (read-only) + `random_password.zot_push` (Actions). **TF-generated →
    no no-default input var → the merge-apply var trap is structurally avoided** (contrast
    `ghcr_read_token`/`resend_receiving_api_key`).
  - `doppler_secret`: `ZOT_REGISTRY_URL`, `ZOT_PULL_USER`, `ZOT_PULL_TOKEN`, `ZOT_PUSH_USER`,
    `ZOT_PUSH_TOKEN`. TF owns values → **no `ignore_changes`** (no out-of-band writer).
  - zot config: htpasswd (bcrypt from the two `random_password`s), **local `/var/lib/zot` filesystem
    storage** (volume-backed; `dedupe`+`gc` on — safe on a singleton), access-control read-only for
    pull user / read+create for push user. No R2, no S3 driver, no multipart spike.
  - `firewall.tf`: registry host reachable from web hosts on the **private network** (no public
    ingress). No R2 egress rule (no R2). Keep GHCR egress allow through the soak; remove at retirement.
  - **Snapshot cron** for `/var/lib/zot` volume (durability belt-and-suspenders; images are also
    CI-reproducible).
- `variables.tf`: **no new no-default vars** (all creds TF-generated). Confirm at /work.
<!-- lint-infra-ignore start -->
- **Apply-path topology (architecture P1-2 — REVISED by CTO ruling 2026-07-06, see
  `knowledge-base/project/specs/feat-registry-oidc-migration/apply-path-cto-ruling.md`):** the
  original AC ("append every zot resource to the `-target=` list") is **REVERSED**. A brand-new host
  cannot be provisioned by the per-PR CI `-target` path (it bridges over SSH to the EXISTING web
  host). Following the sole brand-new-host precedent (git-data, ADR-068), **all 24 #6122 resources (18 host-stack + 6 CI-push ingress) →
  `OPERATOR_APPLIED_EXCLUSIONS`** in `plugins/soleur/test/terraform-target-parity.test.ts`, applied
  by the operator's initial full (untargeted) `terraform apply` + drift detector; **ZERO added to the
  workflow `-target=` list.** `doppler_service_token.registry` additionally goes in
  `OPERATOR_APPLIED_TOKEN_EXCLUSIONS`. Two load-bearing conditions: (1) registry host is cloud-init-only
  (no `remote-exec` `terraform_data`); (2) no zot cred is a `github_actions_secret` — Phase-2 push
  reads `ZOT_PUSH_*` via `doppler run` at runtime. The registry host is a singleton (no `for_each
  var.web_hosts`, no placement group, no `moved {}`) → no `monitored`-flag gate needed, no transitive
  drag.

### Apply path
**(b) cloud-init-only (git-data/ADR-068 model; NO `remote-exec`).** Registry host + volume + Doppler
secrets land via the **operator's initial full (untargeted) `terraform apply` + drift detector** — NOT
the per-PR CI targeted apply (CTO ruling; a new host can't be provisioned over the SSH-to-existing-host
bridge). **AC #2 reinterpreted as two checks (CTO):** (a) the per-PR CI **targeted** plan shows **zero**
zot resources + zero create/replace of existing infra (they are operator-applied exclusions, not a
miss); (b) the operator's **full untargeted** plan shows all 24 #6122 resources as CREATE + zero
create/replace of existing infra. Ordering: registry host provisioned + `/v2/`-healthy before web-host
pulls flip (Phase 3 entry gate). zot config changes on the running host re-apply via re-provision
(cloud-init is idempotent; git-data pattern), not a separate SSH bootstrap.

<!-- lint-infra-ignore end -->

### Distinctness / drift safeguards
`dev != prd` (registry host prd-only — confirm at /work). No `ignore_changes` (TF owns all values).
Secret values land in `terraform.tfstate` (encrypted R2 backend). Rotation: `terraform apply
-replace=random_password.zot_pull` re-propagates htpasswd + Doppler in one apply, inside the single
concurrency group (backend has no lock).

### Vendor-tier / expense
Dedicated Hetzner registry host is a **new recurring expense (~€4/mo CAX11 + volume)** →
`wg-record-recurring-vendor-expense` applies: record it via ops-advisor before PR-ready (AC below).
No new SaaS vendor, no paid-tier `count` gate.

## Observability

```yaml
liveness_signal:
  what: zot /v2/ registry API reachability on the registry host + last-successful-pull age
  cadence: 60s uptime probe (private-network reachable via the tunnel/uptime path; no shell access)
  alert_target: Better Stack uptime monitor plus existing alert route
  configured_in: apps/web-platform/infra/uptime-alerts.tf (new zot monitor)
error_reporting:
  destination: Sentry (host pull failures via ci-deploy.sh / cloud-init already mirror; add zot-unit down)
  fail_loud: true (a failed pull aborts the deploy/boot; never silent-fallback to a stale image)
failure_modes:
  - mode: registry host / zot unit down
    detection: Better Stack /v2/ probe fails
    alert_route: uptime alert; break-glass GHCR fallback on cold-boot path (Phase 3)
  - mode: volume full / IO error
    detection: zot logs to vector to Better Stack; pull fails loud on host
    alert_route: Sentry + uptime
  - mode: htpasswd credential wrong
    detection: docker login 401 on host, ci-deploy.sh reports to Sentry (existing)
    alert_route: Sentry
  - mode: image/tag missing in zot (push regressed OR old tag not backfilled)
    detection: docker pull manifest-unknown to Sentry (existing); Phase-3 entry gate pre-checks
    alert_route: Sentry; Actions push-workflow failure alerts independently
  - mode: elevated GHCR-fallback rate (zot degrading mid-soak)
    detection: zot-soak beacon aggregation > X% ghcr-fallback over Y hours
    alert_route: page + trigger the Phase-3 revert runbook (distinct from the soak-close criterion)
logs:
  where: zot container logs to vector (apps/web-platform/infra/vector.tf) to Better Stack
  retention: existing Better Stack retention
discoverability_test:
  command: betteruptime_heartbeat.registry_prd absence-of-ping (web-host cron probes zot /v2/ over the private net + pings the heartbeat)
  expected_output: heartbeat green — liveness needs NO public ingress (CTO ruling — the public https://<zot-host>/v2/ probe was DROPPED as redundant; do not add a public uptime monitor)
```
**Per-pull-site beacon (spec-flow P0-3 — replaces the bootcmd-beacon category error):** emit a
structured event with `registry=zot|ghcr-fallback`, `image=web|inngest`, `pull_rc`, `login_rc` at
**each pull site** — `ci-deploy.sh` (web `:1025`, inngest `:1492`), `cloud-init.yml` (`:452`,`:545`,
`:591`), `soleur-host-bootstrap.sh` (`:190`) — on the channel that path already uses
(`pull_failure_event`/`final_write_state` for ci-deploy; `soleur-boot-emit` for cloud-init;
`_sentry_emit` for host-bootstrap). `zot-soak-6122.sh` reads this unified event and **must count
ci-deploy rolling deploys** (the primary path the bootcmd beacon can't see).

### Soak Follow-Through Enrollment
GHCR retirement (Phase 5) is soak-gated. Enroll: `scripts/followthroughs/zot-soak-6122.sh` (exit 0
when the soak holds: zero `registry=ghcr-fallback` across a **minimum sample that includes ≥1
fresh-boot of each image** + 100% zot-pull success over the window, counted **per `image=`**), a
`<!-- soleur:followthrough script=zot-soak-6122.sh earliest=<flip+Nd> secrets=… -->` directive on the
tracker + `follow-through` label, and any new `secrets=` wired into `scheduled-followthrough-sweeper.yml`.

## Implementation Phases

### Phase 0 — De-risking spikes (in /work Phase 0; no production writes)
0.1 Stand up zot locally (docker, upstream image) with **local filesystem storage**; push + pull both test images; confirm read-only htpasswd ACL (pull allowed, push denied) and `gc`/`dedupe` on a singleton.
0.2 cosign: sign a test digest stored in zot; run the **offline** verifier against it. Assert (a) the read-only user can fetch the `sha256-<digest>.sig`/`.att` tag, and (b) zot `gc` does NOT reap the `.sig` as unreferenced when only the digest is pulled (referrers handling). `COSIGN_IDENTITY_REGEXP` (Actions identity) is registry-agnostic — confirm unchanged.
0.3 Confirm `crane`/`skopeo copy` mirrors a GHCR tag → zot (for the backfill).
0.4 Re-verify next ADR ordinal vs origin/main (provisional 093).

### Phase 1 — IaC foundations + tag backfill (additive; GHCR stays primary)
Author `zot-registry.tf` (host+volume+zot unit+creds+firewall+snapshot) + `uptime-alerts.tf` monitor; append all addresses to the `-target=` allowlist. Deploy; verify `/v2/` reachable on the private network + monitor green. **Backfill** the last N releases of BOTH images GHCR→zot (`crane copy`) so rollback targets and the pinned `v1.1.18`/`:latest` tags exist in zot.

### Phase 2 — Push side (dual-push: GHCR + zot)
**CI→zot ingress (CTO ruling 2, `apply-path-cto-ruling.md`):** CI cannot reach the private-net zot
directly; it bridges via `cloudflared access tcp --hostname registry.<base> --url 127.0.0.1:5000`
(new `cf-tunnel-registry-bridge` composite action, mirrors `cf-tunnel-ssh-bridge`) using the
`registry_push` CF Access service token from Doppler `prd_terraform`, then `docker login
127.0.0.1:5000` with the zot-push htpasswd. `127.0.0.1` is auto-insecure to docker → plain-HTTP zot
rides the raw-TCP forward.
Edit `build-inngest-bootstrap-image.yml` (`:131-194`) + `reusable-release.yml` (`:425-432`,`:580-611`)
to also push to zot (add `127.0.0.1:5000/...` tags to the single build-push → dual-push) and
cosign-sign the zot digest (`:626-640` — same digest, same registry the host offline-verifies
against). GHCR push stays live. **Push must land in zot before any pull flips.**

### Phase 3 — Pull side (flip to zot-primary, GHCR break-glass) — FULL inventory
Edit every pull site to try zot-primary then fall back to GHCR, **atomically switching image source + mounted docker-config auth + cosign sig-fetch target together** (spec-flow P1-4), and emit the per-site beacon fields:
- `ci-deploy.sh`: web login/pull (`ghcr_prelude_and_login` `:535-569`, pull `:1025`), inngest pull (`:1492`), cosign verifier config mount (`:600-606`).
- `soleur-host-bootstrap.sh`: login block **`:172-199`** (corrected).
- `cloud-init.yml`: fresh-boot web extract (`:440-452`, `:545`) **AND the missed inngest extract `:591-606`**.
- `.github/workflows/apply-web-platform-infra.yml:1070` (imagetools digest-resolve + `docker login ghcr`) — point at zot.
- `plugins/soleur/skills/deploy/scripts/deploy.sh:17-25` (soleur:deploy) — migrate or explicitly out-scope with rationale.
**Phase-3 entry gate:** verify the currently-deployed tags of BOTH images resolve in zot before flipping; the flip trails dual-push by ≥1 full release of each image.

### Phase 4 — cosign chain continuity
Confirm the offline verifier passes on **both** the zot-primary and the GHCR-fallback branch (auth+sig target move together). Trust root + identity regexp unchanged; no cosign version bump.

### Phase 5 — Cutover, soak, retirement (soak-gated)
Soak on zot-primary. **Revert runbook (spec-flow P1-7):** if the fallback-rate alarm fires (>X% ghcr-fallback over Y hours), page + revert Phase 3 to GHCR-primary (clean — GHCR push still live). When `zot-soak-6122.sh` passes (min-sample incl fresh-boot of each image): remove the fallback branch, stop GHCR push, **retire** `cron-ghcr-token-minter.ts` + `ghcr-minter-doppler-token.tf` + `ghcr-read-credential.tf` + the `GHCR_MINTER_DISABLED` gate + GHCR egress allow. **PAT rotation ordering (spec-flow P2-8):** rotate + revoke the leaked classic PAT **only after** the fallback-removal deploy is confirmed on all hosts (the soak break-glass rides that PAT until then). Flip ADR-096 → accepted.

### Phase 6 — ADR/C4 + docs
Write ADR-096; edit the three `.c4` files; run c4 syntax+render tests. Update any runbook naming GHCR pull.

## Acceptance Criteria

### Pre-merge (PR)
- [ ] Phase-0 spike evidence in PR/spec: zot local-fs push/pull both images, read-only ACL enforced, cosign offline-verify passes from zot incl `.sig` ACL + gc-not-reaping-`.sig`.
- [ ] `zot-registry.tf` adds **no no-default TF var**; **(CTO-revised)** all 24 #6122 resources (18 host-stack + 6 CI-push ingress) are in `OPERATOR_APPLIED_EXCLUSIONS` (parity test green) and **none** are in the `apply-web-platform-infra.yml` `-target=` list; the per-PR **targeted** plan shows **zero** zot resources + no create/replace of existing infra; the operator's **full untargeted** plan shows all 24 as CREATE + no create/replace of existing infra (paste plan summary).
- [ ] Both images backfilled to zot (last N releases + the pinned `v1.1.18` + `:latest`); Phase-5 retirement gate: every tag referenced by `cloud-init.yml`/`variables.tf` resolves in zot.
- [ ] Push workflows dual-push both images + cosign-sign the zot digest (CI evidence: a tag build is pullable + signed from zot).
- [ ] Every pull site (full inventory incl `cloud-init.yml:591-606`, `apply-web-platform-infra.yml:1070`) tries zot-primary with an atomic GHCR fallback (image+auth+sig together) and emits `registry`/`image`/`pull_rc`/`login_rc`.
- [ ] cosign offline verify passes on **both** zot-primary and GHCR-fallback branches; `COSIGN_IDENTITY_REGEXP` unchanged.
- [ ] Phase-3 entry gate script verifies both images' deployed tags resolve in zot before flip.
- [ ] Revert runbook + fallback-rate alarm (`> X%` over `Y h` ⇒ page+revert) documented, distinct from soak-close.
- [ ] ADR-096 written (status: adopting) with the 7-alternative table + the cold-boot-dependency statement; all three `.c4` files edited; `c4-code-syntax.test.ts` + `c4-render.test.ts` green.
- [ ] `## Observability` liveness + per-pull-site beacon wired; `discoverability_test.command` has no shell/ssh.
- [ ] `zot-soak-6122.sh` (min-sample incl fresh-boot of each image; per-`image` count) + directive + label committed.
- [ ] Recurring registry-host expense (~€4/mo) recorded via ops-advisor (`wg-record-recurring-vendor-expense`).
- [ ] Typecheck `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` (only `.ts` change is the minter deletion); tests via `package.json`/vitest.

### Post-merge (automated / one owner-only step)
- [ ] Registry host `/v2/` uptime monitor green (Better Stack).
- [ ] Soak window elapses with zero `registry=ghcr-fallback` beacons across the min-sample incl fresh-boot of each image (follow-through sweeper).
- [ ] On soak pass (retirement PR): GHCR retired, minter + `ghcr-*.tf` removed, ADR-096 → accepted.
- [ ] Rotate + revoke the leaked classic PAT **after** the fallback-removal deploy is confirmed on all hosts — the one owner-only step (`Automation: personal GitHub credential the account owner holds; revoke via github.com/settings/tokens or `gh` under the owner session`). `playwright-attempt: n/a — owner-held credential, not a session-automatable vendor mint.`

## Domain Review
**Domains relevant:** Engineering, Operations, Finance (brainstorm carry-forward).
### Engineering
**Status:** reviewed (carry-forward + plan-time verification + 3-agent panel). **Assessment:** zot-native machine-auth = htpasswd (`random_password`, zero human mint, no minter). Single systemd zot on a dedicated registry host (Inngest pattern; no Nomad). Volume-backed; durability via CI-reproducibility. cosign registry-agnostic.
### Operations
**Status:** reviewed. **Assessment:** in-datacenter private-network placement satisfies the restricted-egress firewall. Ops cost = one registry host (patch/zot GC/volume snapshot). Cold-boot dependency on the registry host = no worse than today's GHCR dependency; break-glass covers the soak; monitored + restart-on-failure.
### Finance
**Status:** reviewed. **Assessment:** new ~€4/mo Hetzner registry host + volume (record via ops-advisor). No R2 storage cost (cut), no new SaaS vendor.
### Product/UX Gate
**Tier:** none. No user-facing surface. No `.pen`. **CPO sign-off:** satisfied by brainstorm framing (no product surface). `user-impact-reviewer` at PR review.

## GDPR / Compliance Gate
Considered (single-user-incident threshold trigger). **No regulated-data surface** — container images are compiled artifacts, zot creds are machine credentials, no schema/migration/auth/API/PII movement. Skipped with rationale.

## Risks & Mitigations
- **Cold-boot dependency on the registry host:** monitored + restart-on-failure + break-glass during soak; documented as no-worse-than-GHCR. HA deferred (evidence-gated follow-up).
- **Old-tag rollback:** backfill + Phase-5 gate that every pinned tag resolves in zot.
- **Soak false-green:** per-pull-site beacon (not bootcmd) + min-sample incl fresh-boot of each image + per-`image` count.
- **Auto-apply omission/drag:** `-target` allowlist append + targeted-plan AC + `monitored`-flag gate on any web_hosts `for_each`.
- **Break-glass rides the leaked PAT:** rotate only after fallback-removal deploy confirmed on all hosts.
- **cosign fallback:** atomic image+auth+sig switch; verify passes on both branches (AC).

## Sharp Edges
- A plan whose `## User-Brand Impact` is empty/TBD fails deepen-plan Phase 4.6 — filled.
- ADR-096 ordinal provisional; on renumber `grep -rn 'ADR-096' knowledge-base/project/{plans,specs}/feat-registry-oidc-migration/` and sweep.
- zot's own image is third-party (upstream, digest-pinned) — never pull it from our zot (bootstrap paradox).
- **Deferred (follow-up issue):** zot HA + read-replicas (and R2-backed stateless storage) — reopen only if the singleton shows real availability pain in the soak data.
- **Deferred (fast-follow, inline-triaged at /work):** the `/var/lib/zot` volume **snapshot cron** (task 1.5). Durability's primary guarantee is CI-reproducibility (images rebuildable from source; the crane backfill re-runs) — the snapshot is belt-and-suspenders. A host-side hcloud API token to self-snapshot would widen the registry host's blast radius (it currently holds only a scoped read-only `prd_registry` token); if added it belongs as a **GHA-side scheduled snapshot job** (uses the existing CI `hcloud_token`, no new host secret). Not merge-blocking for a CI-reproducible registry.
