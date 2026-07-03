---
title: "chore(infra): fresh web-2 boot observability prerequisites"
date: 2026-07-03
type: chore
issue: 5933
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
status: draft
---

# chore(infra): fresh web-2 boot observability prerequisites (Ref #5933)

## Overview

Issue #5933 enumerates **four** fresh-host observability/hardening gaps that are hard
prerequisites of the **#5887 web-2 operator cutover** (ADR-068 Phase 2). #5921 (the
bake-and-extract cloud-init path) is already merged and **inert on running web-1**
(`hcloud_server.web` has no `ignore_changes` drama here — the SSH provisioners stay
web-1-scoped and web-2 is provisioned only in a FULL operator apply). #5921 ships the
SSH-free error-path Sentry trap (`{stage, image_ref, host_id}` in `soleur-host-bootstrap.sh`)
and the fail-closed `/run/soleur-hostscripts.ok` sentinel. The four remaining gaps:

1. **Per-host uptime absence detector** (PRIMARY, missing).
2. **A-record drain on boot failure.**
3. **Fresh-host egress-firewall ENFORCEMENT probe** (post-container).
4. **Pin `var.image_name` to an immutable digest + verify a signature.**

### Scope of THIS PR (after inline triage)

This PR ships the **one item that is fully unblocked, inert on running web-1, and closes the
highest-severity gap** — **Item 3 (fresh-host post-container egress-enforcement probe)** —
plus a new **ADR-081** recording the complete four-part design, plus **tracked follow-ups**
for Items 1, 2, 4. The PR body uses **`Ref #5933`** (NOT `Closes`) — the issue stays open
until all four land, sequenced against #5887.

**Why Items 1, 2, 4 are deferred (inline triage, not punting):**

| Item | Blocker verified in-repo | Sequenced behind |
|------|--------------------------|------------------|
| 1 — per-host absence detector | The only firewall-preserving probe path is a **new CF-proxied per-host hostname** (`web-<n>.app.soleur.ai` → specific origin). That record lives in the **main root**, whose auto-apply is **RED (#5887 — `moved` resources excluded by `-target` allow-list)**. A monitor pointed at a not-yet-created hostname pages immediately (522/NXDOMAIN). The origin firewall gates 443 to CF IPs only (`firewall.tf`), so a raw-origin-IP probe is rejected and opening the firewall to Sentry/BetterStack probe ranges is rejected (exposes origins). | #5887 fix, then rides the cutover apply. |
| 2 — A-record drain | `cloudflare_record.app` is a **singleton (web-1 only)**; the `for_each`-over-`var.web_hosts` round-robin **does not exist yet** — it is a destroy+recreate of the LIVE app record explicitly **deferred to the operator cutover** (`dns.tf:4-12`, `git-data-luks-cutover-5274.md`). There is nothing to drain until the round-robin exists. | The cutover DNS rewire (CF Load-Balancer origin health-check is the recommended drain — see ADR-081). |
| 4 — image digest pin + signature | Cross-cutting supply-chain change spanning `web-platform-release.yml` (emit + thread the pushed digest), `variables.tf`, `cloud-init.yml` (`docker pull` + a cosign verify step), and cosign key/OIDC-keyless provisioning. Deserves a focused, security-reviewed PR — folding it into the egress-probe PR would blur two review surfaces. | Own PR (ADR-081 records the design). |

Item 3 has **no** dependency on #5887, `var.web_hosts`, cross-root variables, or web-2
existing. It is a new baked host-script + a cloud-init wiring edit + a `.test.sh`, mirroring
the existing `cron-egress-postapply-assert.sh` pattern.

## Research Reconciliation — Spec vs. Codebase

| Issue claim | Codebase reality (verified) | Plan response |
|-------------|-----------------------------|---------------|
| "the live positive+negative container-egress probe (`cron-egress-postapply-assert.sh`) is web-1-SSH-only and cannot run at bootstrap time on a fresh host (no container yet)" | Confirmed. `cron-egress-postapply-assert.sh:85` runs the container probe only `if docker ps … grep -qx soleur-web-platform`, else prints `WARNING: … SKIPPED (fresh-host bootstrap)`. It is invoked by the `terraform_data.cron_egress_firewall` `remote-exec` (SSH, web-1-scoped). | Item 3 adds a **post-container** probe on the cloud-init path, run AFTER the app container starts, reusing the SAME positive+negative curl-probe logic (lines 77-89) but NOT skippable (the container IS up at that point). |
| "no per-host web monitor anywhere in the root (`uptime-alerts.tf`)" | Confirmed. `uptime-alerts.tf` has only `betteruptime_monitor.soleur_apex` (apex URL). `sentry/uptime-monitors.tf` has 4 URL-scoped monitors (apex/www/changelog/acme). None is `for_each = var.web_hosts`. | Item 1 (deferred) designs the per-host monitor in ADR-081. |
| "`app.soleur.ai` … proxied A-records with no CF Load-Balancer origin health-check (`dns.tf`)" | Partially stale: `cloudflare_record.app` is currently a **singleton** (`content = hcloud_server.web["web-1"].ipv4_address`), NOT yet a `for_each` round-robin. The round-robin is deferred (`dns.tf:4-12`). | Item 2 (deferred) — the drain is designed INTO the cutover DNS rewire in ADR-081. |
| "`var.image_name` … public `:latest` GHCR image" | Confirmed. `variables.tf:44-48` default `ghcr.io/jikig-ai/soleur-web-platform:latest`; `cloud-init.yml:355,381,466,578` `docker pull ${image_name}` with no digest/signature check. | Item 4 (deferred) — ADR-081 records the digest-pin + cosign design. |
| "#5921 ships the SSH-free error-path signals … fail-closed guarantee" | Confirmed. `soleur-host-bootstrap.sh` `emit_fail()` posts `{stage, image_ref, host_id}` to Sentry; sentinel `/run/soleur-hostscripts.ok` written LAST; cloud-init terminal `docker run` block gates on it. | Item 3 reuses this exact machinery (same Sentry envelope, same fail-closed model) for the post-container probe. |

Premise validation: #5921 = CLOSED (predecessor, expected). #5887 = OPEN (this issue is a
prerequisite of it — expected). #5046 = CLOSED (egress firewall, expected). No stale premise.

## User-Brand Impact

**If this lands broken, the user experiences:** a fresh web-2 that either (a) power-offs at
boot on a false-positive probe (web-2 never joins the cluster — caught by Item 1's absence
detector once it lands) or (b) — the failure this item PREVENTS — serves prod traffic with a
**non-enforcing container egress firewall**, i.e. a live data-exfiltration path out of the
agent container.

**If this leaks, the user's data is exposed via:** an inert/unstarted `SOLEUR-EGRESS`
nftables ruleset that lets the agent container reach arbitrary internet hosts (the #5046
threat: `nft -f` exits 0 on an inert ruleset — only a real container probe proves
enforcement). A compromised or prompt-injected agent could exfiltrate operator repo contents.

**Brand-survival threshold:** single-user incident.

CPO sign-off: this substrate's single-user-incident threshold is already established by
**ADR-080** (2026-07-02, CPO sign-off on record for the fresh-host image-bake substrate).
This PR hardens the SAME substrate with a security control that is strictly fail-safe (a
false-positive powers the host OFF; it never opens egress). `user-impact-reviewer` runs at the
one-shot review phase. No NEW user-data-serving surface is introduced.

## Implementation Phases

### Phase 1 — Fresh-host post-container egress-enforcement probe (Item 3)

**1.1 New baked script `apps/web-platform/infra/cron-egress-enforce-probe.sh`.**
- `#!/bin/sh`, `set -e` at top (own errexit — same rationale as
  `cron-egress-postapply-assert.sh:30`).
- Reuse the exact positive+negative container-egress probe from
  `cron-egress-postapply-assert.sh:77-89`, WITHOUT the fresh-host skip branch — this script
  is invoked precisely because the container is now running:
  - positive: `docker exec soleur-web-platform curl -s -o /dev/null --max-time 20 https://api.github.com` MUST succeed (allowlisted host reachable).
  - negative: `docker exec soleur-web-platform curl -s -o /dev/null --max-time 8 https://example.com` MUST fail (non-allowlisted host dropped → ruleset enforcing). Use `if … ; then echo ASSERT-FAILED … ; exit 1; fi` (errexit-exempt `!`-pipeline avoidance, per the sibling script's note).
- Also assert `nft list chain ip filter DOCKER-USER | grep -q 'jump SOLEUR-EGRESS'` and
  `systemctl is-active cron-egress-firewall.service` FIRST (structure before enforcement),
  mirroring `cron-egress-postapply-assert.sh:51-76` (subset).
- On ANY failure: emit a **discriminating Sentry event** (see Observability) then `exit 1`.
  Factor the Sentry-emit out of `soleur-host-bootstrap.sh`'s `emit_fail()` into a shared
  sourced helper `apps/web-platform/infra/host-sentry-emit.sh` (so both the bootstrap trap
  and this probe post the SAME envelope) — OR, if extraction proves invasive at /work, inline
  a byte-identical copy and add a `.test.sh` asserting the two envelopes match. Prefer
  extraction (single source of truth).
- Probe stage label `STAGE=egress-enforce`; `PROBE_RESULT` ∈ `{positive_fail, negative_fail, structure_fail, ok}`.

**1.2 Wire the probe into `cloud-init.yml`'s terminal block, AFTER the app `docker run`.**
- The app container starts in the terminal `runcmd` block (`cloud-init.yml:~578`,
  `docker run … ${image_name}`), which itself runs ONLY if `/run/soleur-hostscripts.ok`
  exists (fail-closed gate).
- Immediately after the container is confirmed up (add a short `until docker ps … grep -qx
  soleur-web-platform` readiness wait, bounded ~60s), invoke
  `/usr/local/bin/cron-egress-enforce-probe.sh`.
- **Fail-closed on probe failure:** if the probe exits non-zero, `poweroff -f` (mirrors the
  bootstrap fail-closed model) so a non-enforcing host does NOT stay up serving. The probe
  emits its Sentry event BEFORE the poweroff. Rationale: an open container-egress path on a
  serving host is worse than an absent host (which Item 1's detector will page on).

**1.3 Register the new script in the baked set + Dockerfile (LOCKSTEP).**
- Add `"cron-egress-enforce-probe.sh"` to `local.host_script_files` in `server.tf:16-47`.
- Add the matching `COPY`/inclusion into `apps/web-platform/Dockerfile`'s
  `/opt/soleur/host-scripts/` set — `cloud-init-user-data-size.test.ts` asserts the two sets
  are byte-identical. Verify with that test.
- The combined `host_scripts_content_hash` (`server.tf:65-67`) auto-includes the new file
  (it globs `local.host_script_files`); no hash edit needed, but the boot-time recompute must
  match — this is exercised by the size/lockstep test.

**1.4 Install the script on-host.** Ensure `soleur-host-bootstrap.sh` (or the cloud-init
extraction) installs `cron-egress-enforce-probe.sh` to `/usr/local/bin/` with mode 0755, and
add a `FAILED_FILE=cron-egress-enforce-probe.sh; test -x /usr/local/bin/…; [ "$(stat -c %a …)" = 755 ]`
assertion in the bootstrap install loop (mirrors the existing install-verify loop at the
bootstrap tail).

**1.5 Test `apps/web-platform/infra/cron-egress-enforce-probe.test.sh`** (bats-free `.test.sh`
convention — the repo has no bats; sibling `cron-egress-firewall.test.sh` is the pattern).
Register in `.github/workflows/infra-validation.yml`. Assert (static, no live host):
- `set -e` present at top; script is `#!/bin/sh`.
- The negative probe uses the `if …; then … exit 1; fi` shape (NOT a bare `&&`).
- The Sentry envelope tags match the bootstrap `emit_fail` envelope (source-grep both).
- The script is present in `local.host_script_files` (grep `server.tf`) AND in the Dockerfile
  host-scripts set (grep) — the lockstep guard, in addition to the TS size test.
- cloud-init.yml invokes the probe AFTER the `docker run … ${image_name}` line (awk
  line-ordering assertion: probe-invocation line number > container-start line number).

### Phase 2 — ADR-081 (records the full four-part design)

Create `knowledge-base/engineering/architecture/decisions/ADR-081-fresh-web2-boot-observability.md`
via `/soleur:architecture` (or direct Edit). Status: `adopting`. Record:
- **Decision:** the four-control fresh-host observability contract (per-host absence detector,
  A-record drain, post-container egress-enforcement probe, image digest-pin + signature).
- **Item 3** documented as SHIPPED here.
- **Item 1 design:** per-host CF-**proxied** probe hostname (`web-<n>.app.soleur.ai` → the
  specific origin IP, preserving the CF-only origin firewall) + a `betteruptime_monitor`
  `for_each` over a `monitored`-gated subset of `var.web_hosts` (add
  `monitored = optional(bool, true)`; `web-2 = { … monitored = false }` until cutover). Reject
  raw-origin-IP probes (firewall) and grey-cloud DNS (origin exposure). Note: probe hostnames
  live in the main root (rides #5887 fix); Sentry-root per-host monitors need a
  `web_host_probe_urls` var if vendor-redundancy is wanted.
- **Item 2 design:** the drain mechanism for the deferred multi-host round-robin — recommend a
  **CF Load Balancer** with per-origin health monitors (auto-drain), with `monitored`-gated
  `for_each` round-robin membership as the interim (a failed host is pulled by flipping its
  flag). Both ride the cutover DNS rewire.
- **Item 4 design:** pin `var.image_name` to `@sha256:<digest>` (release workflow emits the
  pushed digest → threads into a `var.image_digest`), + a cosign verify step in `cloud-init.yml`
  before `docker run`. Cite precedents: `knowledge-base/project/learnings/2026-03-19-docker-base-image-digest-pinning.md`,
  `2026-06-10-release-digest-plan-review-catches.md`.
- **C4:** read all three `.c4` files
  (`knowledge-base/engineering/architecture/diagrams/{model,views,spec}.c4`). The
  fresh-host boot surface + external uptime-monitor actors (Sentry/BetterStack) may already be
  modeled from #5921/uptime-alerting; if the container-egress-enforcement relationship or the
  external uptime actor is absent, add the element + `#external` tag + edge + `view include`
  and run `apps/web-platform/test/c4-code-syntax.test.ts` + `c4-render.test.ts`. If all present,
  cite the checked actors/systems in a "no C4 impact" line.

### Phase 3 — Follow-up tracking issues (Items 1, 2, 4)

Create one GitHub issue per deferred item (label `chore` + `domain/engineering`; verify labels
via `gh label list` first), each: what/why-deferred/re-eval-criteria, blocked-on #5887 (Items
1, 2) resp. own-PR (Item 4), linking ADR-081. Milestone from `knowledge-base/product/roadmap.md`
matching the ADR-068 Phase 2 line.

## Acceptance Criteria

### Pre-merge (PR) — Item 3

- [ ] `apps/web-platform/infra/cron-egress-enforce-probe.sh` exists, `#!/bin/sh`, `set -e` at line ≤ 25, and the negative probe uses `if …; then echo ASSERT-FAILED…; exit 1; fi` (NOT bare `&&`): `grep -qE 'if docker exec .* curl .* https://example.com; then' cron-egress-enforce-probe.sh`.
- [ ] `"cron-egress-enforce-probe.sh"` present in `local.host_script_files` (`grep -c 'cron-egress-enforce-probe.sh' apps/web-platform/infra/server.tf` ≥ 1) AND in the Dockerfile host-scripts set (`grep -c cron-egress-enforce-probe apps/web-platform/Dockerfile` ≥ 1).
- [ ] `apps/web-platform/test/cloud-init-user-data-size.test.ts` passes (baked-set ↔ Dockerfile lockstep).
- [ ] `cloud-init.yml` invokes the probe on a line number GREATER than the terminal `docker run … ${image_name}` container-start line (awk ordering check in the `.test.sh`).
- [ ] On probe failure cloud-init reaches `poweroff -f` (fail-closed) — assert the probe-invocation block contains `poweroff -f` on the non-zero branch.
- [ ] The probe's Sentry envelope tag set equals `soleur-host-bootstrap.sh` `emit_fail`'s (`stage`, `image_ref`, `host_id`) plus `probe_result`; asserted by source-grep in the `.test.sh`.
- [ ] `apps/web-platform/infra/cron-egress-enforce-probe.test.sh` registered in `.github/workflows/infra-validation.yml` and green.
- [ ] `web-hosts-fanout-parity.test.sh` still green (Item 3 does NOT touch `var.web_hosts`; confirm no regression).
- [ ] ADR-081 created (`status: adopting`), C4 three-file review cited (edit or justified "no impact").
- [ ] Three follow-up issues created for Items 1, 2, 4; PR body uses `Ref #5933` (NOT `Closes`).

### Post-merge (operator / cutover) — NOT this PR
- Items 1, 2, 4 land per their tracking issues, sequenced behind #5887; #5933 closes when all four are merged + the web-2 cutover verified.

## Observability

```yaml
liveness_signal:
  what: "fresh-host container-egress enforcement proof (positive+negative probe) at boot"
  cadence: "once per fresh-host boot, post-container-start"
  alert_target: "Sentry (fatal event) + fail-closed poweroff → Item 1 per-host absence detector (deferred)"
  configured_in: "apps/web-platform/infra/cron-egress-enforce-probe.sh + cloud-init.yml terminal block"
error_reporting:
  destination: "Sentry via on-host DSN (doppler prd SENTRY_DSN), same envelope as soleur-host-bootstrap.sh emit_fail"
  fail_loud: true   # non-zero probe → Sentry event THEN poweroff -f; no ok state, no silent serve
failure_modes:
  - mode: "ruleset inert / not enforcing (non-allowlisted host reachable from container)"
    detection: "in-container negative probe (docker exec curl https://example.com succeeds)"
    alert_route: "Sentry {stage:egress-enforce, probe_result:negative_fail} + poweroff -f"
  - mode: "over-blocking (allowlisted host unreachable from container)"
    detection: "in-container positive probe (docker exec curl https://api.github.com fails)"
    alert_route: "Sentry {stage:egress-enforce, probe_result:positive_fail} + poweroff -f"
  - mode: "firewall service not active / DOCKER-USER jump missing (structure)"
    detection: "systemctl is-active + nft list chain DOCKER-USER grep"
    alert_route: "Sentry {stage:egress-enforce, probe_result:structure_fail} + poweroff -f"
  - mode: "container never came up within readiness window"
    detection: "bounded until-loop on docker ps times out"
    alert_route: "Sentry {stage:egress-enforce, probe_result:container_absent} + poweroff -f"
logs:
  where: "journald (persistent, terminal container uses --log-driver journald); probe ASSERT-FAILED sentinels in cloud-output.log"
  retention: "journald bounded per journald-soleur.conf"
discoverability_test:
  command: "bash apps/web-platform/infra/cron-egress-enforce-probe.test.sh"
  expected_output: "0 failed"
  # Runnable, SSH-free, local. Proves the probe + its boot-wiring are correctly assembled
  # BEFORE any host exists. Once web-2 boots, the runtime signal is a Sentry search for
  # tag stage:egress-enforce (zero fatal events on a healthy boot) — the boot probe emits it.
```

**2.9.2 blind-surface (fresh-host boot = uninspectable):** the probe runs INSIDE the boot
sequence (no SSH). Its structured `probe_result` field discriminates ALL competing
hypotheses in ONE event — `negative_fail` (under-enforcing security hole) vs `positive_fail`
(over-blocking) vs `structure_fail` (unit/chain missing) vs `container_absent` — so the root
cause is decided the moment the event lands, not after N blind fixes.

## Infrastructure (IaC)

### Terraform changes
- `apps/web-platform/infra/server.tf` — extend `local.host_script_files` (one string). No new
  resources, no new providers, no new variables in THIS PR.
- No `-target` allow-list edit needed for Item 3 (it adds no new Terraform resource; the baked
  file rides the image + the existing `host_scripts_content_hash`).

### Apply path
- **cloud-init-only** for the fresh-host path (the probe runs at boot). Running web-1 is
  **inert**: the baked script ships to web-1 on the next `apps/web-platform/**` deploy (image
  re-seed) but only EXECUTES at boot, and web-1 is not rebooting. No downtime, no blast radius
  on the live host. web-1's egress enforcement continues to be proven by the existing
  SSH-provisioner `cron-egress-postapply-assert.sh` on re-apply.

### Distinctness / drift safeguards
- Baked-set ↔ Dockerfile lockstep enforced by `cloud-init-user-data-size.test.ts` +
  `host_scripts_content_hash` boot recompute (a mismatched image aborts boot before the probe).
- No secret material added.

### Vendor-tier reality check
- N/A for Item 3 (no new vendor resource). Item 1's BetterStack per-host monitors (deferred)
  must respect the free-tier 10-monitor cap — noted in ADR-081.

## Architecture Decision (ADR/C4)

An architectural decision IS made (a new fresh-host observability contract + the substrate
security-probe boundary) → **ADR-081** is a deliverable of Phase 2 (not a deferred issue), per
`wg-architecture-decision-is-a-plan-deliverable`. C4: three-file review in Phase 2; external
uptime-monitor actors + the container-egress-enforcement relationship are the candidate
elements to confirm/add.

## Domain Review

**Domains relevant:** Engineering (infra/security/observability). Product/UX: NONE (no
user-facing surface — `## Files to Create`/`Edit` touch only `apps/web-platform/infra/**`,
`Dockerfile`, `.github/workflows/**`, `knowledge-base/**`; no `components/**`, no `app/**/page.tsx`).

Planning-process note: domain-leader + plan-review + deepen-plan subagents were NOT spawned
inline for this plan because the one-shot planning subagent stalled on a nested background
agent (recorded in session-state.md); planning ran inline in the parent. The multi-agent
adversarial review is provided by the one-shot **/review** phase (security-sentinel,
observability-coverage-reviewer, architecture-strategist) — which is the stronger gate for a
security-control change at single-user-incident threshold. **Recommend deepen-plan's triad
(data-integrity-guardian + security-sentinel + architecture-strategist) is honored at review.**

### Engineering (inline CTO/security assessment)
**Status:** reviewed (inline). **Assessment:** Item 3 is a fail-safe security control on an
already-single-user-incident substrate (ADR-080). The design reuses proven machinery
(`emit_fail` envelope, fail-closed sentinel, the exact probe curls from the sibling
provisioner script), minimizing novel surface. Key risk: a false-positive negative-probe
(e.g. `example.com` transiently resolvable through an allowlisted CDN) would poweroff a
healthy host — mitigated by choosing a probe target that is definitively NOT in the
allowlist (verify `example.com` against `cron-egress-allowlist.txt` /
`cron-egress-allowlist-cidr.txt` at /work; the sibling script already uses `example.com`, so
precedent holds). Second risk: probe ordering — must run strictly after container readiness;
the bounded until-loop handles it.

## Open Code-Review Overlap

Run at /work after `## Files to Edit` is final:
`gh issue list --label code-review --state open --json number,title,body > /tmp/o.json` then
`jq` each path. Expected: none (fresh-host infra scripts are new). Record result in the PR.

## Test Scenarios

- **Unit/static (`cron-egress-enforce-probe.test.sh`, CI):** all AC static assertions above.
- **Lockstep:** `cloud-init-user-data-size.test.ts` green.
- **No live web-2 exists** — end-to-end enforcement is proven at the operator cutover boot
  (the probe fires, emits `egress-enforce` telemetry, and either serves or power-offs). QA
  here is CI-static + a dry `sh -n cron-egress-enforce-probe.sh` parse + the ordering awk
  check. No prod synthetic-user path (`hr-dev-prd-distinct-supabase-projects`).

## Sharp Edges / Risks

- The app container starts AFTER `soleur-host-bootstrap.sh` writes the sentinel — the probe
  therefore CANNOT live in the bootstrap script (container not up); it MUST be a separate
  post-`docker run` cloud-init step. Verified against `soleur-host-bootstrap.sh` (sentinel
  written LAST) + `cloud-init.yml:578` (container start in the terminal block).
- `nft -f` exits 0 on an inert ruleset — the negative container probe is the ONLY proof of
  enforcement (issue #5933 item 3 explicitly; #5046 threat).
- Do NOT copy `cron-egress-postapply-assert.sh:85`'s fresh-host SKIP branch — on this path the
  container IS up and the skip would defeat the whole item.
- Adding the script to `local.host_script_files` WITHOUT the matching Dockerfile COPY fails
  `cloud-init-user-data-size.test.ts` — keep them in lockstep in the SAME commit.
- If the Sentry-emit helper is extracted from `soleur-host-bootstrap.sh`, re-run the #5921
  bootstrap tests to confirm the trap still emits the identical envelope.
- A false-positive poweroff of a fresh web-2 leaves it absent — Item 1's per-host detector
  (deferred) is what pages on that absence; until Item 1 lands, absence is caught by the
  cutover operator watching the boot. Acceptable because the cutover will not run until Items
  1/2/4 also land (this PR is a prerequisite, not the cutover).
