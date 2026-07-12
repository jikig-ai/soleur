---
title: "fix(infra): webhook.service ReadWritePaths hard-requires /var/lib/inngest → 226/NAMESPACE on colocate=false fresh web boots"
issue: 6090
branch: feat-one-shot-6090-webhook-inngest-readwritepath
type: bug
classification: infra-config-change
lane: cross-domain  # no spec.md on branch → TR2 fail-closed default (change is genuinely single-domain infra)
brand_survival_threshold: aggregate pattern
date: 2026-07-12
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!-- Phase 2.8 reviewed: this fix is ROUTED THROUGH TERRAFORM (cloud-init templatefile re-render on -replace
     + the standalone webhook.service delivered via terraform_data.deploy_pipeline_fix's triggers_replace push).
     The `systemctl` / cloud-init tokens in the prose below are QUOTES of existing cloud-init-managed runcmd
     lines (evidence of the bug), NOT new manual/SSH operator steps. No operator SSH, no hand-run systemctl.
     See the ## Infrastructure (IaC) section for the full apply path. -->

# fix(infra): webhook.service ReadWritePaths hard-requires `/var/lib/inngest` → deterministic 226/NAMESPACE on fresh `web_colocate_inngest=false` boots

🐛 **Bug** · P1 · `apps/web-platform/infra` · closes #6090 (this peel)

## Overview

A fresh web-2 boot dies with a deterministic systemd **226/NAMESPACE** unit failure: `webhook.service`'s
`ReadWritePaths=` list hard-requires `/var/lib/inngest` (no leading `-`), but on a host where
`web_colocate_inngest=false` (the default since the co-located-inngest bootstrap gate merged 2026-07-11,
ADR-100 / #6178) **nothing ever creates that directory** — the only creator, `inngest-bootstrap.sh:123`
(`mkdir -p /var/lib/inngest`), lives inside the `%{ if web_colocate_inngest ~}` runcmd block at
`cloud-init.yml:636` and is skipped entirely. systemd refuses to set up the mount namespace for a
non-optional `ReadWritePaths` target that is absent, so the cloud-init-managed webhook enable step
(`cloud-init.yml:578`) fails, `:9000` never binds, and every deploy fan-out reports
`ok_peer_fanout_degraded` — the weight-0 warm-standby never becomes deployable. This is the last
remaining blocker for the #6178 Inngest cutover, whose runbook step-1a needs a clean, green web-2 recreate.

**The fix is a one-character change per file, applied to BOTH lockstep copies of the unit:** prefix the
`/var/lib/inngest` token with `-` (making it `-`-optional), exactly matching the adjacent
`-/var/lib/vector` / `-/etc/vector` tokens that were made optional for the identical reason in PR #4257.
When the directory is absent, systemd silently ignores it (namespace sets up, `:9000` binds); when it is
present (a colocate host after `inngest-bootstrap.sh` has run), it "becomes a real ReadWritePath" on the
next namespace setup — the exact semantics documented at `webhook.service:40-44`.

`cloud-init.yml` is templatefile-injected (not baked into the image), so the change applies on the next
`-replace`; the standalone `webhook.service` file is delivered to running hosts via the
`deploy_pipeline_fix` webhook push (`server.tf:856-859`). No operator SSH, no hand-run commands.

## Research Reconciliation — Premise vs. Codebase

All premises in the task framing were verified against the branch before planning. No stale premises.

| Premise (as stated) | Verified reality | Plan response |
| --- | --- | --- |
| `webhook.service` RWP hard-requires `/var/lib/inngest` (no `-`) around L245 | ✅ `cloud-init.yml:245` — exact token `/var/lib/inngest` with no leading `-`, adjacent to `-/var/lib/vector -/etc/vector` | Prefix with `-` |
| `/var/lib/inngest` created only by the inngest-bootstrap runcmd, gated behind `web_colocate_inngest` | ✅ sole creator is `inngest-bootstrap.sh:123`; invoked only inside `cloud-init.yml:636 %{ if web_colocate_inngest ~}` | Confirmed — dir never exists on colocate=false |
| `web_colocate_inngest` default false | ✅ `variables.tf:350-353` `type = bool`, `default = false` | Confirmed |
| webhook enabled around L578 | ✅ `cloud-init.yml:578` (webhook binary installed L567-576) — a cloud-init runcmd line | Confirmed |
| #6090 OPEN with a merged predecessor PR | ✅ OPEN; `closedByPullRequestsReferences` = PR **#6125** (merged, earlier probe-and-harden arc). **COLLISION acknowledged — operator confirmed genuinely new scope (deterministic post-gate 226/NAMESPACE deadlock). Proceeding past the merged-linked-PR check per instruction.** | Continue |
| #6178 (Inngest cutover) / #5933 (fresh-boot observability) OPEN | ✅ both OPEN | Verification + observability wired against them |
| **NEW (not in task): a SECOND copy of the RWP line exists** | ⚠️ **`apps/web-platform/infra/webhook.service:45`** carries the byte-identical RWP line (standalone unit, base64-delivered to running web-1 via `infra-config-apply.sh` + hashed in `deploy_pipeline_fix.triggers_replace`, `server.tf:859`). It is **NOT** templatefile-rendered. | **Fix BOTH copies with the `-` form (only Option that keeps the non-templated copy in lockstep — see Design Decision).** |
| **NEW: the earlier-arc diagnosis comments reference the now-severed 226 chain** | ⚠️ `soleur-host-bootstrap.sh:191-193` and `soleur-host-bootstrap-observability.test.sh:526` explain a failed GHCR pull → `/var/lib/inngest` never created → "webhook.service fails 226/NAMESPACE → :9000 never binds". After this fix that causal link is **broken** (a missing dir no longer fails webhook). | Annotate both comments so future debuggers are not misled (GHCR rationale stays; the 226 clause is marked severed). |

## User-Brand Impact

**If this lands broken, the user experiences:** no direct user-facing artifact changes — web-2 is a
weight-0 warm-standby with **no public ingress**. The realized impact is *aggregate resilience*: the
warm-standby never becomes deployable, so there is no failover capacity if web-1 fails, and the #6178
Inngest cutover stays blocked.

**If this leaks, the user's data / workflow / money is exposed via:** N/A — `webhook.service` runs on an
internal host reachable only via loopback + the `10.0.1.0/24` private net (`hcloud_firewall.web`
default-denies `:9000` on the public interface). The change stores no data and opens no new surface; it
only governs whether an internal host completes first boot.

**Brand-survival threshold:** `aggregate pattern` — the failure degrades fleet-wide availability
(loss of warm-standby / blocked cutover), not a single user's data or workflow. No per-PR CPO sign-off
required; section present per gate.

## Root Cause (verified)

1. `webhook.service` runs `ProtectSystem=strict` + `PrivateTmp` in a mount namespace. `ReadWritePaths=`
   whitelists the paths the webhook-driven `deploy <component>` handlers may write (via `sudo`, which
   elevates UID but does **not** escape the namespace).
2. A `ReadWritePaths` token **without** a leading `-` is **mandatory**: if the target is absent at unit
   start, systemd refuses to construct the namespace and the unit fails with `226/NAMESPACE`. A token
   **with** a leading `-` is optional: an absent target is silently skipped.
3. `/var/lib/inngest` is the SQLite data dir for the co-located inngest server. Its sole creator is
   `inngest-bootstrap.sh:123`, invoked only inside the `%{ if web_colocate_inngest ~}` block
   (`cloud-init.yml:636-700`).
4. With `web_colocate_inngest=false` (default), that block is skipped → `/var/lib/inngest` is **never**
   created → the mandatory `ReadWritePaths=… /var/lib/inngest …` token has no target → the
   cloud-init-managed webhook enable step (`cloud-init.yml:578`) fails `226/NAMESPACE` → `:9000` never
   binds → `ok_peer_fanout_degraded`.

**Why now / why deterministic:** the earlier #6090 arc (PRs through #6125) treated this as a *flaky
ordering race* — on a colocate host the dir is created late (bootstrap at L636 runs *after* webhook is
enabled at L578), and a failed anonymous GHCR pull could leave it absent (see the now-stale diagnosis at
`soleur-host-bootstrap.sh:191-193`). The colocate gate (merged 2026-07-11) removed the dir-creating path
entirely on the default config, converting the intermittent race into a **permanent** failure that no
amount of GHCR-auth hardening can fix. Fresh reproduction: run **29169983049** (2026-07-11), the first
post-gate web-2 recreate past the merged deploy-fanout `tag_malformed` fix.

## Hypotheses (network-outage gate — `hr-ssh-diagnosis-verify-firewall`)

The feature description contains the substring "SSH" (in "Do NOT SSH the deny-all hosts"), so the L3→L7
network-outage checklist gate fires. **The failure is NOT a network outage** — it is a local systemd
mount-namespace unit failure, deterministically established from unit semantics and off-host-confirmed via
the baked-DSN `webhook_bound` beacon. The L3→L7 ladder is explicitly ruled out:

- **L3 firewall / egress allow-list:** not implicated — `:9000` is a *local bind* that never happens; no
  outbound connection is attempted at the failing step. `hcloud_firewall.web` is unchanged.
- **L4/DNS/routing:** not implicated — no name resolution or route is exercised by the enable step.
- **L7 sshd/fail2ban/service:** the service **is** the subject, but the failure mode is systemd namespace
  construction (`226/NAMESPACE`), a config-time refusal, not a connectivity fault.

Diagnosis is **off-host only** (baked-DSN boot beacons + Better Stack markers). **No SSH to the deny-all
hosts** (`hr-no-ssh-fallback-in-runbooks`).

## Design Decision — `-`-optional (Option B), not a templatefile guard (Option A)

The task offered two shapes. **Choose Option B (`-/var/lib/inngest`) decisively.**

- **Option A** — wrap the token in `%{ if web_colocate_inngest ~}/var/lib/inngest %{ endif ~}`:
  - ✗ **Fatal:** works only for the templatefile-rendered `cloud-init.yml:245`. The **standalone
    `webhook.service:45`** is read by `file()` and base64-delivered to running hosts — it is **not**
    templated, so the `%{ if }` directive is impossible there. The two lockstep copies would **diverge**,
    and the running-host copy would keep hard-requiring the dir (re-opening the bug on any redeploy).
    `server.tf:793-794` explicitly requires the two to stay in lockstep.
  - ✗ Even on colocate=true it does not fix the documented *ordering race* (dir created at L636, after
    webhook is enabled at L578) — it only narrows it.
- **Option B** — prefix the token with `-` in **both** files:
  - ✓ **Uniform** across the templated and non-templated copies → lockstep preserved (no divergence, the
    `triggers_replace` hash stays a single source of truth).
  - ✓ **Exact in-repo precedent:** the adjacent `-/var/lib/vector` / `-/etc/vector` tokens already ship
    this way for the identical reason (PR #4257 took webhook.service down entirely until the dirs existed);
    rationale documented verbatim at `webhook.service:40-44`.
  - ✓ Fixes **both** the colocate=false permanent failure **and** the latent colocate=true ordering race:
    when `inngest-bootstrap.sh` later creates the dir, it "becomes a real ReadWritePath" on the next
    namespace setup (webhook.service:43-44) — the webhook-driven inngest deploy's `chown` works exactly as
    before once the dir exists.
  - ✓ No regression for colocate=true: the first inngest install runs under cloud-init as root (not in the
    webhook namespace); later webhook-driven deploys occur after the dir already exists.

Not ADR-worthy: this restores an existing boot invariant using an established in-file precedent; no
ownership / substrate / resolver / trust-boundary changes (see Architecture Decision below).

## Implementation Phases

### Phase 1 — RED: regression test locking the `-`-optional + lockstep invariant

Add an infra test (home: `apps/web-platform/infra/inngest.test.sh`, which already reasons about the
webhook namespace and `/var/lib/inngest`; deepen-plan to confirm the exact assert host) that:

1. Asserts `cloud-init.yml`'s webhook.service `ReadWritePaths` contains `-/var/lib/inngest` (optional
   form) and does **not** contain the bare mandatory ` /var/lib/inngest ` token.
2. Asserts the standalone `webhook.service` `ReadWritePaths` contains `-/var/lib/inngest`.
3. **Lockstep parity:** asserts the two `ReadWritePaths=` lines are byte-identical (modulo the YAML block
   indent), so a future edit cannot silently diverge the templated and delivered copies.

Run it first, confirm it FAILS on the current (mandatory) form (`cq-write-failing-tests-before`).

### Phase 2 — GREEN: apply the `-` prefix + comment alignment (both lockstep copies)

1. `cloud-init.yml:245` — `… /etc/webhook -/var/lib/inngest -/var/lib/vector -/etc/vector …`; update the
   comment block (L239-244) so `/var/lib/inngest` shares the "optional because created later by
   inngest-bootstrap.sh; becomes a real ReadWritePath once present" rationale rather than the current
   "hard-required" wording.
2. `webhook.service:45` — identical one-char change; fold `/var/lib/inngest` into the existing
   `-`-optional rationale at L32-34 + L40-44 (extend the vector-paths explanation to cover inngest;
   cite #4257 + #6090).

Re-run Phase 1 test → GREEN.

### Phase 3 — Comment-accuracy sweep (severed-causal-chain references)

The `-`-optional fix breaks the "missing `/var/lib/inngest` → webhook 226/NAMESPACE → `:9000` unbound"
chain that two earlier-arc comments assert as fact. Annotate (do not delete the still-valid GHCR
rationale):

1. `soleur-host-bootstrap.sh:191-193` — mark the 226/NAMESPACE clause severed by #6090's `-`-optional fix.
2. `soleur-host-bootstrap-observability.test.sh:526` — same annotation (it is a comment inside the test).

### Phase 4 — Verify emit coverage of the death stage (observability)

Confirm the systemd-namespace death is named off-host. `cloud-init.yml:581`
(`soleur-wait-ready port 9000 webhook_bound || exit 1`) POSTs a named `stage=webhook_bound` fatal to
Sentry via the **baked DSN** when `:9000` never binds — the in-surface, no-SSH discoverability signal.
Verify that the `226/NAMESPACE` abort at the webhook enable step (L578) does **not** short-circuit runcmd
*before* reaching the L581 beacon (i.e., that the failure still surfaces a named emit, not an anonymous
abort). If L578 can abort ahead of L581 under an active `set -e`/EXIT trap, add a named baked-DSN emit at
the enable step so the systemd-namespace death is named (relates to #5933, #6090 observability). This is a
verification task, not a presumed new beacon.

### Phase 5 — Post-merge: fresh web-2-recreate + off-host green verification (automated apply)

Trigger `gh workflow run apply-web-platform-infra.yml -f apply_target=web-2-recreate` (scoped `-replace`
of web-2 to re-run first-boot cloud-init and bind `:9000`; ingress-safe, weight-0, nothing irreversible).
The run's off-host acceptance step ("Wait for web-2 :9000 + verify off-host — no SSH — shared poll",
`apply-web-platform-infra.yml:1209`) must go fully green: web-1's `/hooks/deploy-status` `reason` flips
off `ok_peer_fanout_degraded` to `ok`, and **no** `webhook_bound` fatal appears in Sentry for the recreate.

## Files to Edit

- `apps/web-platform/infra/cloud-init.yml` — L245 `-/var/lib/inngest`; comment L239-244.
- `apps/web-platform/infra/webhook.service` — L45 `-/var/lib/inngest`; comment L32-34 + L40-44.
- `apps/web-platform/infra/soleur-host-bootstrap.sh` — L191-193 comment accuracy (severed 226 clause).
- `apps/web-platform/infra/soleur-host-bootstrap-observability.test.sh` — L526 comment accuracy.
- `apps/web-platform/infra/inngest.test.sh` — ADD `-`-optional + lockstep parity assertions (Phase 1).

## Files to Create

None (regression assertions land in the existing `inngest.test.sh`).

## Infrastructure (IaC)

### Terraform changes
No new resources, variables, providers, or secrets. The edit is to `cloud-init.yml` (consumed via
`templatefile()` in `server.tf` for `hcloud_server.web` `user_data`) and the standalone `webhook.service`
(read via `file()`, hashed into `terraform_data.deploy_pipeline_fix.triggers_replace`, `server.tf:856-859`).

### Apply path
- **Fresh hosts:** `cloud-init.yml` re-renders on the next `-replace` — delivered by
  `apply_target=web-2-recreate` (scoped `-replace` of web-2 only; `hcloud_server.web["web-2"]` has
  `ignore_changes=[user_data]`, so a plain apply will NOT re-deliver — the `-replace` is required).
- **Running hosts (web-1):** the `webhook.service` change flows through the `deploy_pipeline_fix` webhook
  push (its `triggers_replace` hash includes `file("webhook.service")`), which rewrites the unit +
  restarts the listener. No SSH.
- Chosen path: cloud-init re-render via `web-2-recreate` for the standby; `deploy_pipeline_fix` push for
  web-1. Downtime/blast-radius: web-2 is weight-0 (no ingress); web-1 sees only a sub-second listener
  restart, already an accepted `deploy_pipeline_fix` behavior.

### Distinctness / drift safeguards
No `dev`/`prd` divergence (this infra is prd-only). The lockstep parity test (Phase 1) is the drift
safeguard preventing the templated and delivered copies from diverging.

### Vendor-tier reality check
N/A — no vendor resource created.

## Observability

```yaml
liveness_signal:
  what: "webhook :9000 bind confirmed by soleur-wait-ready (cloud-init.yml:581) → baked-DSN Sentry emit; steady-state by web-1 /hooks/deploy-status reason=ok"
  cadence: "once per fresh boot (wait-ready poll); deploy-status reason on every fan-out"
  alert_target: "Sentry (baked DSN) + web-1 deploy-status reason (Better Stack marker)"
  configured_in: "apps/web-platform/infra/cloud-init.yml:581 (soleur-wait-ready), soleur-host-bootstrap.sh (_sentry_emit boundary)"
error_reporting:
  destination: "Sentry via baked DSN (host-emitted, no SSH)"
  fail_loud: "yes — soleur-wait-ready … || exit 1 emits a named stage=webhook_bound fatal and aborts boot"
failure_modes:
  - mode: "webhook.service fails 226/NAMESPACE (the bug) → :9000 never binds"
    detection: "in-surface baked-DSN emit stage=webhook_bound (fatal), emitted FROM the booting host; off-host visible as web-1 deploy-status reason=ok_peer_fanout_degraded"
    alert_route: "Sentry (stage tag) + apply-web-platform-infra.yml:1209 off-host acceptance step"
  - mode: "webhook enable step (L578) aborts before reaching the L581 beacon"
    detection: "Phase-4 verification confirms a named emit at the enable step (or the L581 beacon still fires); no anonymous abort"
    alert_route: "Sentry named stage tag"
logs:
  where: "Sentry events (baked DSN); web-1 /hooks/deploy-status; GH Actions run log for web-2-recreate"
  retention: "Sentry default; deploy-status is live/transient"
discoverability_test:
  command: "gh run view <web-2-recreate-run-id> --log  # off-host acceptance step must show reason flip ok_peer_fanout_degraded → ok; NO ssh"
  expected_output: "web-2 :9000 bound; web-1 deploy-status reason=ok; no webhook_bound fatal in Sentry"
```

Affected-surface note (§2.9.2): web-2 fresh boot is a deny-all blind surface. The `webhook_bound` beacon
is emitted **from** the host (in-surface probe via the baked DSN), with a `stage` structured tag that
discriminates the systemd-namespace death from later cloud-init stages — satisfying the blind-surface
probe requirement.

## Architecture Decision (ADR/C4)

**No new ADR or C4 change.** This is a bug fix restoring an existing boot invariant using an established
in-file precedent (`-`-optional `ReadWritePaths`, PR #4257); it makes no ownership/tenancy, substrate,
resolver, or trust-boundary decision, and does not reverse or extend an ADR (it operates *within*
ADR-100 / #6178's dedicated-inngest-host direction — colocate=false is exactly that state).

C4 completeness check (read against `model.c4` + `views.c4`): no **external human actor**, no **external
system/vendor**, no **container/data-store**, and no **actor↔surface access relationship** is
added/removed/changed. `web-2` and `webhook.service` are existing internal elements; the fix only governs
whether an already-modeled host completes first boot. → **no C4 impact.**

## Domain Review

**Domains relevant:** none (engineering is the self-domain of the change).

No cross-domain implications detected — infrastructure/tooling change. Product/UX Gate: **NONE** — no
file under `components/**`, `app/**/page.tsx`, or `app/**/layout.tsx`; no UI-surface term matches. No
GDPR/regulated-data surface (systemd unit + cloud-init; no schema/auth/API/`.sql`).

## Open Code-Review Overlap

None — no open `code-review`-labelled issue references the files in scope
(`cloud-init.yml`, `webhook.service`, `soleur-host-bootstrap.sh`, `inngest.test.sh`). (Re-verify at
deepen-plan against the finalized Files-to-Edit list.)

## Acceptance Criteria

### Pre-merge (PR)
- [ ] **AC1** `grep -c -- '-/var/lib/inngest' apps/web-platform/infra/cloud-init.yml` returns `1`; the
  mandatory bare token is gone: `grep -Ec '[^-]/var/lib/inngest -/var/lib/vector' apps/web-platform/infra/cloud-init.yml` returns `0`.
- [ ] **AC2** `grep -c -- '-/var/lib/inngest' apps/web-platform/infra/webhook.service` returns `1`.
- [ ] **AC3** Lockstep parity: the `ReadWritePaths=` token list (trimmed) is byte-identical between
  `cloud-init.yml:245` and `webhook.service:45` — asserted by the new `inngest.test.sh` case.
- [ ] **AC4** The new regression test FAILS on the pre-fix (mandatory) form and PASSES on the `-` form.
- [ ] **AC5** `bash apps/web-platform/infra/inngest.test.sh` passes; existing infra tests
  (`infra-config-apply.test.sh`, `infra-config-install.test.sh`) still pass (no assertion regressed).
- [ ] **AC6** `soleur-host-bootstrap.sh:191-193` and `soleur-host-bootstrap-observability.test.sh:526`
  comments no longer assert the (now-severed) "missing dir → webhook 226/NAMESPACE" chain as live fact.
- [ ] **AC7** Phase-4 emit-coverage check documented: the death stage surfaces a named baked-DSN emit
  (either the existing L581 `webhook_bound` beacon fires, or a named emit is added at L578).
- [ ] **AC8** PR body uses `Closes #6090` (the code fix lands pre-merge; the post-merge recreate is
  verification of the already-merged fix, not the fix itself).

### Post-merge (operator / automated)
- [ ] **AC9** `gh workflow run apply-web-platform-infra.yml -f apply_target=web-2-recreate -f reason='#6090 verify webhook RWP inngest -optional'` completes green.
  Automation: `gh` CLI (feasible in-session/CI once merged). The `-replace` re-runs first-boot cloud-init;
  ingress-safe, weight-0, reversible.
- [ ] **AC10** The run's off-host acceptance step (`apply-web-platform-infra.yml:1209`) shows web-1
  `/hooks/deploy-status` `reason` flipped off `ok_peer_fanout_degraded` to `ok`; `:9000` bound on web-2.
- [ ] **AC11** No `stage=webhook_bound` fatal in Sentry for the web-2-recreate boot (baked DSN; off-host).

## Test Scenarios

1. **Pre-fix RED:** current mandatory token → new test fails; documents the 226/NAMESPACE deadlock.
2. **Post-fix GREEN (colocate=false):** `-`-optional token, dir absent → namespace sets up, `:9000` binds.
3. **Colocate=true regression:** dir present (post-`inngest-bootstrap.sh`) → `-`-optional still writable →
   webhook-driven inngest deploy `chown` unaffected (matches vector-path precedent semantics).
4. **Lockstep:** an edit that changes one copy's RWP list but not the other fails the parity assertion.
5. **Live off-host verify:** web-2-recreate run → reason flip → no `webhook_bound` fatal.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, placeholder, or omits the threshold fails
  `deepen-plan` Phase 4.6 — this section is filled (threshold `aggregate pattern`).
- **Two lockstep copies, not one.** `cloud-init.yml:245` (templated, fresh hosts) and `webhook.service:45`
  (non-templated, delivered to running hosts) must both change and stay byte-identical — this is why
  Option A (templatefile-only guard) is rejected and the parity test exists.
- **`ignore_changes=[user_data]`** means a plain `terraform apply` will NOT re-deliver the cloud-init
  change to an existing web host; the `-replace` (via `web-2-recreate`) is required for fresh delivery,
  and web-1 gets the standalone-unit change via the `deploy_pipeline_fix` push — not via cloud-init.
- **Do NOT SSH the deny-all hosts.** Diagnose only via baked-DSN boot beacons + Better Stack / deploy-status
  markers (`hr-no-ssh-fallback-in-runbooks`).
- `inngest-server.service`'s own `ReadWritePaths=/var/lib/inngest /var/lock` (`inngest-bootstrap.sh:431`)
  is **out of scope** — that unit legitimately owns the dir (its bootstrap creates it first) and must keep
  the hard requirement. Only `webhook.service`'s copy is the bug.
