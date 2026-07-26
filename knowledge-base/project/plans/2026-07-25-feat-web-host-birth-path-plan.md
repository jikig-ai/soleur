---
title: "Digest-pinned automated web-host birth path"
type: feat
issue: 6730
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
adr: ADR-145 (provisional — see §Architecture Decision)
date: 2026-07-25
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!-- lint-infra-ignore start -->
<!-- Phase 2.8 reviewed. This plan is the REMOVAL of a human-run infrastructure step, not the
     introduction of one: it replaces the laptop-run terraform apply with a gated
     workflow_dispatch. Every reference to the human-run path below is either (a) historical
     context for what is being deleted, or (b) the break-glass appendix that survives only as
     a fallback. The ## Infrastructure (IaC) section states the apply path. No step in this
     plan is handed to a human except the GitHub environment: required-reviewer approval,
     which is an authorization gate, not a task.

     The ignore region covers THIS justification comment only — it names the human-run path in
     order to say it is being deleted, which is exactly the actor+imperative co-occurrence the
     linter matches on. It does not blanket the plan body: the linter still scans every phase,
     AC and runbook instruction below, and must stay clean there. -->
<!-- lint-infra-ignore end -->

# feat: digest-pinned automated web-host birth path (#6730)

## Overview

`hcloud_server.web["web-N"]` cannot be created by any automated route. Every path that
reaches it HALTs on `host_creates > 0`, and the only documented remedy runs from a human's
laptop — which violates `hr-fresh-host-provisioning-reachable-from-terraform-apply` and
`hr-never-label-any-step-as-manual-without`.

This plan builds the missing path as a gated `workflow_dispatch` job
(`apply_target=web-host-create`) that is **allowed** to birth exactly one web host,
carries its own `host_creates` guard, and implements ADR-128's five carried-forward MUSTs.

**This is now load-bearing, not theoretical.** `web-2` landed in `var.web_hosts` on main
(2026-07-25) while the host does not exist, so the per-PR `apply` job HALTs on **every**
merge to main. The wedge is live; this path is the unwedge.

### Why the HALTs stay

Do not "fix" the wedge by weakening the tripwire. A web host born on an incoherent image
aborts its entire cloud-init `runcmd` at `stage=verify` — no cloudflared, no deploy
webhook, no monitors, no egress firewall. `runcmd` is once-per-instance, so **no reboot
repairs it**; the host is dark until replaced. The correct resolution is a birth path that
is *safe*, so the HALT can distinguish "this path may create a host" from "this path must
never create one".

## Research Reconciliation — Spec vs. Codebase

| Claim | Reality (verified 2026-07-25) | Plan response |
|---|---|---|
| "#6730 is unbuilt" | OPEN. Collision probes surfaced #6744 + #6725; both are cited in #6730's body as *history* (#6725 is step 3 of "how we got here" — it ADDED the HALT; #6744 removed the dead dispatch surface). `closingIssuesReferences` for #6744 = `[6575]`. | Genuinely new scope. Proceed. |
| "web-2 does not exist" | Confirmed against the live Hetzner API: 4 servers (`soleur-web-platform`, `soleur-grok-dogfood`, `soleur-registry`, `soleur-inngest`). No web-2. | The wedge is real; AC14 verifies the unwedge. |
| "`host-image-coherence-preflight.sh` exists" | EXISTS at `apps/web-platform/infra/scripts/`. | Reuse; do not re-author. |
| "`resolve-web1-known-good-tag.sh` exists" | EXISTS at same dir. | Reuse for the known-good arm. |
| "ADR-128 R1–R5 are the binding MUSTs" | Confirmed verbatim in `ADR-128-coherence-two-invariants.md` §"Carried-forward requirements". | ACs map 1:1 to R1–R5. |
| "The deleted assertions have a re-add target" | `soleur-host-bootstrap-observability.test.sh` records the loss inline (AC8/AC8b/AC13/AC14/AC16) and states *"Re-add assertions here the moment that path exists."* | Re-add in THIS PR — that is the file's own instruction. |
| "`crane` is available in CI" | **NO.** Not preinstalled. `reusable-release.yml` ships an `install_crane()` helper (curl + tarball). | Reuse that install shape; do not assume the binary. |
| "next free ADR ordinal is 144" | **FALSE.** 143 is highest on main (#6919), but **144 is claimed by the unmerged #6778 branch**. | Take **ADR-145**. Provisional — `/ship` re-verifies. |

## User-Brand Impact

**If this lands broken, the user experiences:** `app.soleur.ai` returning connection
errors or a stale/blank app. A web host birthed on an incoherent image aborts cloud-init at
`stage=verify` — no cloudflared connector, so the tunnel has no origin — and `runcmd` is
once-per-instance, so no reboot repairs it. Today web-2 is out-of-band (serving weight 0),
but this path is generic over `web-N` and is the documented birth path for **web-1**, the
sole singleton behind the `app.soleur.ai` A record.

**If this leaks, the user's data is exposed via:** the dispatch reads `SENTRY_DSN`,
`HCLOUD_TOKEN` and the R2 backend credentials from Doppler `prd_terraform`. An unmasked
echo, a `set -x` region, or a `::notice::` interpolating a secret would put live production
credentials into a world-readable Actions log — from which the whole fleet is reachable.

**Brand-survival threshold:** single-user incident

A single dark web-1 is a total outage for every user, with no failover partner (web-2 is
out-of-band pre-GA; #6459 unbuilt). One incident is the whole brand.

## Infrastructure (IaC)

### Terraform changes

No new resources. This plan adds an **apply path** for resources that already exist in
`apps/web-platform/infra/` (`hcloud_server.web`, `hcloud_server_network.web`,
`hcloud_volume.workspaces`, `hcloud_volume_attachment.*`, `betteruptime_heartbeat.web_*`).
The `-target` set is the web-host fan-out for one `each.key`.

### Apply path

(c) gated `workflow_dispatch` with a scoped `-target` set and `-var image_name=<pinned digest>`.
Blast radius is bounded by the birth guard (§Distinctness) — exactly one `hcloud_server`
create, zero destroys, zero replaces. Expected downtime: none (the host does not exist yet;
out-of-band host, serving weight 0).

### Distinctness / drift safeguards

- The job carries **its own** `host_creates` guard. A new dispatch job inherits nothing —
  the per-PR `apply` HALT is a separate inline copy, and its `if:` is mutually exclusive
  with every dispatch job.
- The guard is **inverted, not removed**: it asserts `host_creates == 1` AND the created
  address equals the requested `hcloud_server.web["<key>"]` AND
  `resource_deletes == 0` AND `nested_deletes == 0` AND `reboot_updates == 0`.
  Anything else aborts.
- `hcloud_server.web` carries `lifecycle.ignore_changes = [user_data, ssh_keys, image,
  placement_group_id]`, so the pinned digest is honoured **at create time** and a later
  routine apply will not drift it back to `:latest`.

### Vendor-tier reality check

No new vendor resources; no tier gate needed.

## Encryption Posture

No new persistent store and no new cross-component connection — the web-host volume set and
its posture are already declared by ADR-143 / the encryption-posture ledger. This plan only
adds an apply path for existing resources. Gate skipped per §2.11 skip condition.

## Architecture Decision (ADR/C4)

### ADR

**Create ADR-145 — "A host-birth path is a guarded capability, not a removed tripwire."**
Decision: the `host_creates` HALT is retained on every non-birth route; exactly one dispatch
job is granted the capability, and it pays for it with a digest-pin + coherence preflight +
a DSN precondition + an inverted birth guard. Alternatives considered: (a) weaken the HALT
globally (rejected — reintroduces the #6416 attachment-less birth), (b) keep the laptop-run
apply (rejected — the rule violation this closes), (c) auto-birth on merge (rejected — an
unattended create of a billing host with no human authorization).

Ordinal **145 is provisional**: 143 is highest on main and 144 is claimed by the unmerged
#6778 branch. `/ship`'s collision gate re-verifies against `origin/main`; if it renumbers,
sweep `grep -rn 'ADR-145' knowledge-base/project/{plans,specs}/feat-one-shot-6730-web-host-birth-path/`
in the same edit.

Also **amend ADR-128**: its R1–R5 table states that until this path exists, the pinned-image
chain in the HALT carries them. That sentence becomes false when this ships.

### C4 views

Read all three of `model.c4`, `views.c4`, `spec.c4` before concluding. Enumeration for this
change: (a) external human actor — the **operator** firing the dispatch, already modeled;
(b) external system — **Hetzner Cloud** (already modeled), **GHCR** (already modeled),
**Sentry** (already modeled); (c) container — `hcloud_server.web` is a modeled deployment
node; (d) access relationship — no ownership/tenancy boundary changes; the operator→CI→Hetzner
edge already exists for the sibling dispatches. **No new element or edge is required.** This is
an apply-path addition over already-modeled infrastructure, not a new participant.

### Sequencing

ADR-145 ships in this PR with `status: accepted` — the decision is true the moment the job merges.

## Observability

```yaml
liveness_signal:
  what: the dispatch job's own conclusion + the R2 fresh-host Sentry surfacing step
  cadence: per dispatch (on-demand, not scheduled)
  alert_target: the dispatch job fails loudly; Actions surfaces the run
  configured_in: .github/workflows/apply-web-platform-infra.yml (job web_host_create)
error_reporting:
  destination: GitHub Actions annotations (::error::) + the surfaced Sentry events
  fail_loud: true — every gate aborts non-zero; no gate swallows a failure
failure_modes:
  - mode: SENTRY_DSN empty in Doppler prd_terraform (R1)
    detection: pre-create assertion reads the secret and fails on empty
    alert_route: job aborts before any create; ::error:: names the Doppler path
  - mode: image/apply coherence mismatch (host would boot dark at stage=verify)
    detection: host-image-coherence-preflight.sh exits non-zero
    alert_route: job aborts before apply; nothing is destroyed by a failed preflight
  - mode: plan would create the wrong host, or destroy/replace anything
    detection: the inverted birth guard compares the plan's create-set to the request
    alert_route: job aborts before apply
  - mode: host created but cloud-init died (green apply, dark boot)
    detection: R2 surfacing step POLLS de.sentry.io for this host's boot-stage events and
      filters client-side, to a terminal state (cloud_init_complete | a fatal | the 960s
      deadline, against the host's own 900s SOLEUR_FRESH_BOOT_WINDOW_SECONDS); runs
      if: always(), but only draws a verdict when the apply itself succeeded
    alert_route: ::error:: naming the last-reached stage; the run is red. A single
      post-apply read cannot carry this route — cloud_init_complete is the LAST line of
      runcmd, so a one-shot read fires ~15 min early and reports "emitted nothing" on a
      HEALTHY boot, which is byte-identical to a dark one. The poll is what makes this
      route real rather than declared.
logs:
  where: GitHub Actions run log; Sentry (soleur-cloud-init boot stage events)
  retention: Actions default (90d); Sentry per project retention
discoverability_test:
  kind: live-probe
  command: bash tests/scripts/test-web-host-birth-gate.sh
  expected_output: "0 failed"
```

The `discoverability_test` runs the birth gate's own suite — it is ssh-free, deterministic,
and exercises the guard's reject arms (the property that actually protects production),
rather than asserting the workflow file merely contains a string.

## Domain Review

**Domains relevant:** Engineering (CTO)

### Engineering

**Status:** reviewed
**Assessment:** This is an infrastructure-capability change on the highest-blast-radius
surface in the repo. The load-bearing decision is that the capability is *granted narrowly
and paid for with gates*, not that the tripwire is loosened. The three gates that must not
be negotiable: R1 (DSN non-empty), the coherence preflight, and the inverted birth guard.
Each maps to a distinct, already-observed failure mode (#6090 dark boot, #6712 apply-time
skew, #6416 attachment-less birth). No Product/UX surface — no file matches the UI-surface
term list or glob superset, so the mechanical override does not fire and the Product gate is
NONE.

## Implementation Phases

### Phase 0 — Preconditions (verify, do not assume)

0.1 Confirm `crane` is NOT preinstalled on the runner; lift the `install_crane()` shape from
`reusable-release.yml` (content anchor: the `install_crane() {` function) rather than
re-authoring a download.
0.2 Read `workspaces_luks_cutover` end-to-end — it is the closest precedent (a gated
first-provision `+create` with its own gate lib) and this job should be structurally parallel.
0.3 Read the existing `host_creates` guard in the `apply` job and the destroy-guard counter
jq (`tests/scripts/lib/destroy-guard-filter-web-platform.jq`) so the new guard consumes the
same counter shape rather than inventing one.
0.4 Confirm the `-target` fan-out set for one web host by reading `server.tf`'s `for_each`
consumers (server, network attachment, proxy-tls, web-probe, volume, volume attachment).

### Phase 1 — The birth gate lib (TDD: tests first)

1.1 Write `tests/scripts/test-web-host-birth-gate.sh` FIRST, with reject arms for: zero
creates, two creates, a create of the wrong `each.key`, any `resource_deletes > 0`, any
`nested_deletes > 0`, any `reboot_updates > 0`, and a non-numeric counter (fail-closed).
1.2 Implement `tests/scripts/lib/web-host-birth-gate.sh` to satisfy them, mirroring the
sibling gate libs' interface (sourced by the job; reads the plan JSON; emits `::error::`).
1.3 Register the suite in `scripts/test-all.sh` alongside the sibling gate suites.

### Phase 2 — The dispatch job

2.1 Add `web-host-create` to the `apply_target` choice enum **and** its description string.
2.2 Add inputs: `web_host_key` (required, e.g. `web-2`), `confirm` (typo-guard, typed
literal), and reuse the existing `reason`.
2.3 Add the `web_host_create` job, structurally parallel to `workspaces_luks_cutover`:
`if:` on apply_target, `environment:` (required-reviewer gate), `concurrency` on the
fleet-wide apply mutex, `timeout-minutes`, Doppler install, backend-credential extraction,
`terraform init`.
2.4 **R1 gate** — assert `SENTRY_DSN` non-empty in `prd_terraform` BEFORE anything else.
Fail-closed on an unreadable secret (unreadable ≠ present).
2.5 Resolve the digest: `crane digest` on the known-good tag via
`resolve-web1-known-good-tag.sh` (preferred) or `:latest` (fallback), producing a pinned
`@sha256:` ref.
2.6 **Coherence preflight** — run `host-image-coherence-preflight.sh` with the pinned ref.
Non-zero aborts before any apply.
2.7 `terraform plan` with the scoped `-target` set and `-var image_name=<pinned>`; source the
Phase-1 birth gate against the plan JSON.
2.8 `terraform apply tfplan`.
2.9 **R2/R3/R4/R5 surfacing** — query `de.sentry.io` for this host's boot-stage events,
filter client-side with a regex derived from `QUERY`, `if: always()`.

### Phase 3 — Re-add the lost assertions

3.1 In `soleur-host-bootstrap-observability.test.sh`, replace the CAPABILITY-LOST block with
live assertions for AC8/AC8b/AC13/AC14/AC16 against the new job — the file's own instruction.
3.2 Register the job in `plugins/soleur/test/terraform-target-parity.test.ts` (job ⇄ gate-lib
pairing + `-target` parity), alongside the registry dispatch jobs.

### Phase 4 — Docs + ADR

4.1 Author ADR-145.
4.2 Amend ADR-128's R1–R5 preamble (the "until that path exists" framing is now false).
4.3 Rewrite `web-host-birth.md` to lead with the dispatch; keep the laptop-run chain only
as a break-glass appendix, clearly marked as the fallback.
4.4 Update the `host_creates` HALT remediation text — it currently says "there is NO automated
path" for `hcloud_server.web[*]`. That becomes false; it must name the new dispatch.

### Phase 5 — Verify by unwedging main

5.1 Dispatch `apply_target=web-host-create -f web_host_key=web-2`.
5.2 Confirm web-2 exists via the Hetzner API.
5.3 Confirm the next merge to main no longer HALTs.

## Acceptance Criteria

### Pre-merge (PR)

- **AC1** `tests/scripts/test-web-host-birth-gate.sh` exists and passes; every reject arm in
  Phase 1.1 is covered and each is mutation-proven (flip the guard, the arm reds).
- **AC2** The gate is fail-closed on a non-numeric counter (an unparseable plan is never a pass).
- **AC3** `web-host-create` appears in the `apply_target` enum AND its description string.
- **AC4** The job asserts `SENTRY_DSN` non-empty before any `terraform apply` (R1), and fails
  closed when the secret is unreadable.
- **AC5** The job runs `host-image-coherence-preflight.sh` with a pinned `@sha256:` ref before apply.
- **AC6** The job passes `-var image_name=<pinned digest>` — never a bare `:latest`.
- **AC7** The Sentry surfacing step targets `de.sentry.io` (R3), filters client-side (R4), and
  carries `if: always()` (R5). Grep each as a separate assertion.
- **AC8** `soleur-host-bootstrap-observability.test.sh` no longer contains the CAPABILITY-LOST
  block, and asserts AC8/AC8b/AC13/AC14/AC16 against the new job.
- **AC9** `terraform-target-parity.test.ts` registers the job ⇄ `web-host-birth-gate.sh` pairing
  and asserts it sources no sibling gate.
- **AC10** ADR-145 exists with `## Decision` + `## Alternatives Considered`; `check-adr-ordinals.sh` clean.
- **AC11** `web-host-birth.md` leads with the automated path; the `host_creates` HALT text no
  longer claims "NO automated path" for `hcloud_server.web[*]`.
- **AC12** `bash scripts/test-all.sh` green; `actionlint` clean on the workflow.

### Post-merge (dispatch-verified, automated)

- **AC13** Dispatching `web-host-create` for `web-2` creates exactly one host; the Hetzner API
  lists `soleur-web-2`; the R2 step surfaces `cloud_init_complete` with no `fatal` stage.
- **AC14** The next merge to main completes its `apply` job without the `host_creates` HALT.

`Automation: not feasible` is claimed for **no** step in this plan. The dispatch itself is
gated by GitHub `environment:` required reviewers, which is an authorization gate, not a task.

## Test Scenarios

1. **Gate rejects a zero-create plan** — the request asked for a birth; nothing to create ⇒ abort.
2. **Gate rejects a two-create plan** — fan-out escaped the `-target` scope ⇒ abort.
3. **Gate rejects a wrong-key create** — asked for `web-2`, plan creates `web-3` ⇒ abort.
4. **Gate rejects any destroy/replace/reboot** — birth must be purely additive ⇒ abort.
5. **Gate fails closed on unparseable counters** — a malformed plan is never a pass.
6. **R1 aborts on empty DSN** — no create is attempted.
7. **Preflight abort leaves nothing destroyed** — a failed coherence check is pre-apply.
8. **Live**: dispatch for `web-2`, assert the host exists and boot telemetry is clean (AC13).

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| The new job becomes a second unguarded birth route | The inverted guard is mandatory and mutation-tested; `terraform-target-parity.test.ts` pins the job⇄gate pairing so a future refactor cannot silently unhook it. |
| `crane` absent on the runner | Lift `install_crane()` from `reusable-release.yml`; do not assume the binary (verified absent). |
| ADR ordinal collision (third occurrence on this repo today) | 145 chosen against main+unmerged-144; `/ship` re-verifies; renumber sweeps the whole feature artifact set. |
| Pinned digest drifts back to `:latest` on a later apply | `lifecycle.ignore_changes` includes `image`; the pin is honoured at create time only, which is the correct and intended semantic. |
| Secret leakage into the run log | No `set -x` in secret-handling regions; mask before any echo; the R1 assertion tests emptiness without printing the value. |

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` returned no issue whose body names
`apply-web-platform-infra.yml`, `soleur-host-bootstrap-observability.test.sh`, or
`terraform-target-parity.test.ts`.

## Files to Create

- `tests/scripts/lib/web-host-birth-gate.sh`
- `tests/scripts/test-web-host-birth-gate.sh`
- `knowledge-base/engineering/architecture/decisions/ADR-145-host-birth-is-a-guarded-capability.md`

## Files to Edit

- `.github/workflows/apply-web-platform-infra.yml` (enum + description + inputs + the job + HALT remediation text)
- `apps/web-platform/infra/soleur-host-bootstrap-observability.test.sh` (re-add AC8/AC8b/AC13/AC14/AC16)
- `plugins/soleur/test/terraform-target-parity.test.ts` (register the job⇄gate pairing)
- `scripts/test-all.sh` (register the new suite)
- `knowledge-base/engineering/operations/runbooks/web-host-birth.md` (lead with the automated path)
- `knowledge-base/engineering/architecture/decisions/ADR-128-coherence-two-invariants.md` (amend the R1–R5 preamble)

## Sharp Edges

- The `-target` set must cover the **whole** web-host fan-out for the chosen key. A server
  created without its `hcloud_server_network` attachment is the #6416 failure mode — a host
  with no private IP and, transiently, no firewall. Enumerate from `server.tf`'s `for_each`
  consumers, not from memory.
- A green `terraform apply` is not a green boot. R2 exists precisely because those two states
  are indistinguishable without querying Sentry.
- `runcmd` is once-per-instance. A host that aborts at `stage=verify` cannot be repaired by a
  reboot — only by replacement. That is why the coherence preflight is pre-apply and mandatory.
- The events endpoint ignores `message:` search (R4). Passing `query=` there returns 0 for
  events that demonstrably exist — a silent false negative on the exact signal R2 is for.
