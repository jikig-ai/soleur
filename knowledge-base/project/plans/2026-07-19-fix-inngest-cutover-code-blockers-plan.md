# fix: ADR-100 Inngest dedicated-host cutover — remaining code blockers

---
type: bug-fix
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
issues: [6500, 6441, 6617]
adrs: [ADR-096, ADR-100, ADR-114, ADR-117]
created: 2026-07-19
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->

## Overview

Three prerequisite code blockers stand between today's state and a safe ADR-100
cutover. This plan ships them as **two PRs**, split on *which host must be
replaced for the change to take effect* — the only split axis that avoids paying
for two `inngest-host-replace` cycles.

| PR | Issue | Surface | Takes effect via |
|----|-------|---------|------------------|
| **PR-A** | #6500 + #6617 (a, c) | `cloud-init-inngest.yml`, `vector.toml`, `inngest-host.tf` | `inngest-host-replace` |
| **PR-B** | #6441 (**not** #6466 — see Reconciliation) | `cloud-init.yml`, `soleur-host-bootstrap.sh` | fresh web-host boot |

**This plan does NOT execute the cutover.** `cutover-inngest.yml` remains a
separately-gated `workflow_dispatch`. No change to `INNGEST_BASE_URL`; no touch
to the dark Inngest tables; the 2.4 app-repoint draft PR stays held until
`op=arm`.

## Premise Validation

Checked before any research was dispatched (plan Phase 0.6).

| Cited reference | Probe | Result |
|---|---|---|
| #6500 OPEN | `gh issue view 6500` | ✅ OPEN, `priority/p1-high` |
| #6466 OPEN | `gh issue view 6466` | ✅ OPEN, `priority/p1-high`, `deferred-scope-out` |
| #6617 OPEN | `gh issue view 6617` | ✅ OPEN, `priority/p1-high` |
| #6122 OPEN | `gh issue view 6122` | ✅ OPEN (zot migration parent) |
| `cloud-init-inngest.yml` bare `IREF` | `grep -n IREF` | ✅ present — `IREF=ghcr.io/jikig-ai/soleur-inngest-bootstrap:v1.1.23` |
| zot absent on inngest host | `grep -in 'zot\|ZIREF\|ZURL'` | ✅ **0 hits** — confirmed no zot path |
| `cloud-init.yml` `ZIREF` pattern | `grep -n ZIREF` | ✅ present |
| ADR-114 NIC-wait prescription | read ADR-114 §I1 | ✅ present — **but attributed to #6441, not #6466** |
| `cloudflared service install` ungated by NIC | read `cloud-init.yml` runcmd | ✅ gated only by `web_tunnel_connector`; no NIC wait |
| Vector Source 4 tag allowlist | read `vector.toml` `[sources.host_scripts_journald]` | ✅ 17 tags; the 4 named tags absent |

Three premises **did not hold as stated**. They are reconciled below.

## Research Reconciliation — Spec vs. Codebase

| Brief claim | Codebase reality | Plan response |
|---|---|---|
| "#6466 (P1, GA blocker) — NIC-wait before `cloudflared service install`" | #6466's body is about **host-addressability** (fan-out `/hooks/deploy-status`, per-host infra-config targeting, host-scoped SSH, web-2 promotion runbook). It contains **no** NIC-wait item. ADR-114 §I1 states the gate verbatim and says: *"It is candidate (b) under I2 below, tracked in **#6441**."* #6441 is OPEN. | **Re-attribute.** PR-B ships the NIC-wait against **#6441**, and comments on #6466 to record the split. The *work* is real and unshipped — only the issue number was wrong. #6466 stays open for its own (larger) addressability scope. |
| "Provision the heartbeat URL for the dedicated host so `inngest-heartbeat` stops emitting `url_present=no`" | The `url_present=no` line is the **deliberate dark-arm**, rendered by `inngest-bootstrap.sh` only when `DOPPLER_PROJECT` is the dark project. `INNGEST_HEARTBEAT_URL` is provisioned **by `op=arm` (G4)** in `cutover-inngest.yml`, and `op=rollback` **removes** it — explicitly so a dark host never becomes *"a SECOND pusher on the shared Better Stack heartbeat monitor"* (#6552). | **Reject the prescribed remedy; keep the goal.** Provisioning the URL pre-`op=arm` would (a) bypass the cutover FSM gate, (b) create the exact dual-pusher state #6552 exists to prevent, and (c) contradict this brief's own "nothing before `op=arm`" constraint. The quota waste is real, so PR-A instead makes the dark arm **quiet**: log once per boot + on transition, not every 60 s. Same row reduction, no arming side-effect. |
| "mirror [the ZIREF pattern] onto the inngest host path" | `cloud-init.yml`'s inngest block is gated by `web_colocate_inngest`, whose `default = false` (`variables.tf`). The ZIREF reference pattern therefore lives in a path that **has never executed in production**. | **Use as shape, not as proof.** PR-A adopts the three-tier ADR-096 gate shape but treats it as new code: it gets its own tests and its own measured zot-resolution probe. Do not assume the pattern is battle-tested. |

Two further gaps the brief did not name, both load-bearing:

- **Sentry emit does not exist on the dedicated host.** `grep -i sentry cloud-init-inngest.yml` → **0 hits**. The host reports only to Better Stack via `inngest-boot-phone-home.sh`. `soleur-boot-emit` (the Sentry emitter) is defined in `soleur-host-bootstrap.sh`, which the inngest host **does not run**. #6500's acceptance criterion 2 ("reports on the Sentry `stage:` schema") is therefore a **port**, not a call-site addition — it needs a DSN staged into the isolated `soleur-inngest/prd` project.
- **The inngest host is not an enumerated zot client.** `grep 10.0.1.40` across `zot-registry.tf` + `cloud-init-registry.yml` → **0 hits**. Whether zot's `accessControl` and the registry host's firewall admit `10.0.1.40`, and whether `soleur-inngest/prd` even holds `ZOT_*` credentials, is **unverified**. Phase A0 measures this before any code is written.

## Hypotheses

`hr-ssh-diagnosis-verify-firewall` fires (brief matches `SSH`, `unreachable`,
`firewall`, `timeout`). This plan *prevents* an outage rather than diagnosing
one, but the L3→L7 discipline still binds the Phase A0 probe order: **no
service-layer hypothesis may be investigated before L3 is measured.**

| Layer | Question | Verification (Phase A0, before code) |
|---|---|---|
| **L3 — firewall** | Does the firewall admit `10.0.1.40 → 10.0.1.30:5000`? | `hcloud firewall describe` on the registry firewall; diff against `10.0.1.40`. Artifact pasted into the PR body. |
| **L3 — routing** | Does the inngest host hold a private NIC and route to `10.0.1.30`? | Better Stack `net-health` marker — `inngest-boot-phone-home.sh net-health` already emits `nic=`. |
| **L4/L7 — registry auth** | Does `/v2/` answer, and with what status for the inngest identity? | **Measured, not derived** — run the pinned zot digest with the repo's exact `accessControl`, or probe the live private endpoint. Record the literal status. |
| **L7 — mirror content** | Does zot actually carry `soleur-inngest-bootstrap:v1.1.23`? | `manifest_resolves` probe (the shape `zot-entry-gate.sh` uses). #6500 itself warns this is *expected*, not *established*. |

**Sharp edge, binding on Phase A0:** per the #6497 learning, a hypothesis about
a vendored service's HTTP behavior must be **measured against the pinned image**,
never read off its config. No phase of PR-A may branch on an assumed zot status
code. If A0 shows the inngest host cannot reach or authenticate to zot, PR-A's
scope changes from "add a zot path" to "add a zot path **and** enroll the host as
a zot client" — and that enrollment is the larger half.

## User-Brand Impact

**If this lands broken, the user experiences:** a scheduler outage. A botched
NIC-wait can leave a fresh web-1 with no cloudflared connector — `deploy.` and
`ssh.` both dark, unrecoverable in-band (there is no SSH fallback). A botched
zot path can leave the singleton inngest host unable to boot, so every scheduled
reminder, digest, and cron the user depends on silently stops firing.

**If this leaks, the user's data is exposed via:** the GHCR PAT and the zot
credential are both baked into `user_data` at render time. A widened bake — or a
Sentry/Better Stack emit that tails a log containing them — puts registry
credentials into an observability sink with a different retention and access
boundary than Doppler.

**Brand-survival threshold:** `single-user incident`.

One user losing their scheduler is a brand event, not a metric. `requires_cpo_signoff: true`
is set accordingly; `user-impact-reviewer` runs at review time.

## Implementation Phases

### PR-A — inngest host: zot path, Sentry stage emit, self-reporting liveness

Closes #6500. Ref #6617.

**A0 — Measure before coding (no code in this phase).**
Run the four Hypotheses probes above. Record each literal result in the PR body.
**Gate:** if zot cannot serve `10.0.1.40`, stop and re-scope — do not write a
fallback that silently never takes the zot arm.

**A1 — Port the Sentry stage emitter to the dedicated host.**
Add a `soleur-boot-emit`-equivalent to `cloud-init-inngest.yml`, DSN staged from
the isolated `soleur-inngest/prd` project (never baked beyond the existing scoped
token). Keep `inngest-boot-phone-home.sh` — this is *additive*; Better Stack stays
the boot-stage channel, Sentry becomes the channel `zot-soak-6122.sh` can query.
Emit on the pull path only: `inngest_zot` (info) / `inngest_ghcr_fallback` (warning),
matching the tag vocabulary the soak already greps.

**A2 — Zot-primary pull with GHCR fallback.**
Replace the bare `IREF=` with the ADR-096 three-tier gate: `/v2/` probe → zot pull
→ atomic fallback to GHCR. Image ref, docker auth, and cosign target move together
(ADR-096 Edge A/B: `insecure-registries` + `--allow-insecure-registry`). The pull
stays **fail-closed** after both arms are exhausted — the fallback widens the
inputs, it does not soften the gate.

**A3 — Give the file a CI owner.**
`cloud-init-inngest-bootstrap.test.sh` reads `cloud-init.yml` despite its name;
`inngest-host.test.sh` has zero `ghcr`/`IREF`/`zot` assertions. Add assertions to
`inngest-host.test.sh` covering: zot arm present, GHCR fallback present, pull
fail-closed, Sentry emit present, and the pin matching the tag the drift-guard
derives. **This is what stops the pin silently drifting again** — it is the root
cause #6500 names, not a nice-to-have.

**A4 — Positive liveness marker (#6617a).**
Add `inngest-server-probe.{service,timer}` to `inngest-bootstrap.sh`: probe
`http://127.0.0.1:8288/health`, emit a `SOLEUR_*` marker via
`logger -t inngest-server-probe`. Set `SyslogIdentifier=inngest-server-probe`
explicitly — per #6536, an unset identifier tags the unit with the ExecStart
basename and the channel silently matches no Vector source. Emit
**unconditionally before classification** (the #6537/ADR-117 positive-control
rule): a marker gated on the health it reports disappears exactly when it matters.
If the unit runs Doppler as root, set `Environment=HOME=/root`.

**A5 — Vector allowlist (#6617c) + the delivery that makes it real.**
Add `inngest-server-probe`, `inngest-redis`, `inngest-nftables`, and
`inngest-boot-phone-home` to `[sources.host_scripts_journald].include_matches.SYSLOG_IDENTIFIER`.
**Editing `vector.toml` does not ship it.** Per the 2026-07-18 learning, the file
is committed config; the running host boots from a pinned OCI image and carries
`ignore_changes = [user_data]`. This phase must therefore also name the delivery
path — the `inngest-host-replace`, or a `-target`ed re-delivery plus a Vector
config reload driven from the bootstrap script. An AC that only greps the repo
file would pass on a host that never receives it.

**A6 — Quiet the dark heartbeat arm (#6617b, re-scoped).**
Change the dark arm in `inngest-bootstrap.sh` from an unconditional 60 s
`logger` line to once-per-boot + on-transition. **This PR writes no heartbeat
URL value anywhere** — provisioning that value is `op=arm`'s job (see
Reconciliation).

### PR-B — web host: NIC-wait before cloudflared registration

Ref #6441. Ref #6466 (records the scope split).

**B1 — Add a `nic` verb to `soleur-wait-ready`.**
The helper already implements `service <unit> <stage>` and `port <port> <stage>`
with the fail-closed `|| exit 1` idiom at both existing call sites. Adding
`nic <ip> <stage>` reuses the established bounded-poll + stage-emit shape rather
than inventing a parallel one.

**B2 — Gate `cloudflared service install` on NIC convergence.**
Insert `soleur-wait-ready nic 10.0.1.10 private_nic_ready || exit 1` immediately
**before** `cloudflared service install`, inside the existing
`%{ if web_tunnel_connector ~}` block. Bounded boot window per ADR-114 ("with a
bounded boot window") — the timeout is a **plan-time decision, not an
implementation detail**: it must exceed the observed Hetzner attach latency and
fail loud, never fall through silently.

**B3 — Handle the documented NIC-down-at-boot case.**
Per `2026-07-07-immutable-redeploy.md`, fresh Hetzner hosts boot with the private
NIC **down** — the additive attach lands after cloud-init's network stage, and a
soft reboot converges it. A wait alone can therefore time out on a host that is
attached but not converged. Mirror the registry host's converger
(`cloud-init-registry.yml`), which already handles exactly this with a bounded
reboot counter. **Do not write a fresh converger** — this is a solved problem on a
sibling host.

**B4 — Test the render.**
Extend `cloud-init-inngest-bootstrap.test.sh` (which owns `cloud-init.yml`
rendering) to assert: with `web_tunnel_connector=true` the NIC-wait renders
**before** `cloudflared service install`; with `false` neither renders. The
ordering assertion is the load-bearing one — `private-nic-guard.test.sh` already
demonstrates this line-number-comparison idiom.

## Files to Edit

**PR-A**
- `apps/web-platform/infra/cloud-init-inngest.yml` — Sentry emitter (A1), zot gate (A2)
- `apps/web-platform/infra/inngest-bootstrap.sh` — probe units (A4), dark-arm quieting (A6)
- `apps/web-platform/infra/vector.toml` — 4 tags (A5)
- `apps/web-platform/infra/inngest-host.tf` — DSN/`ZOT_*` template vars (A1/A2)
- `apps/web-platform/infra/inngest-host.test.sh` — CI ownership (A3)
- `apps/web-platform/infra/journald-config.test.sh` — Source 4 tag assertions (A5)

**PR-B**
- `apps/web-platform/infra/cloud-init.yml` — NIC-wait before cloudflared (B2)
- `apps/web-platform/infra/soleur-host-bootstrap.sh` — `nic` verb (B1)
- `apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh` — render+ordering tests (B4)

**Files to Create:** none. Every change extends an existing surface.

## Infrastructure (IaC)

### Terraform changes
`inngest-host.tf` gains `templatefile()` vars for the Sentry DSN and the zot
endpoint/credential. Both sourced from the **isolated `soleur-inngest/prd`**
Doppler project — no inheritance path to `soleur/prd` (ADR-100 isolation
invariant). Any secret value that must exist is declared as a `doppler_secret`
Terraform resource, never written by hand. No new Terraform root; no new provider.

**If A0 shows the inngest host is not an authorized zot client**, this section
grows an `accessControl` entry and/or a firewall rule enrolling `10.0.1.40`.
That is a scope expansion to be surfaced, not absorbed silently.

### Apply path
**(c) taint + `-replace`** — `inngest-host-replace`, the existing 5-target guarded
dispatch (server + NIC + firewall + volume attachment + volume). Blast radius:
the singleton inngest host. **Zero prod impact today** because the host is dark —
this is precisely why the work must land *before* the cutover, not after.

Per `2026-07-07-immutable-redeploy.md`: `-target` walks **upstream, not
downstream**. The replace must `-target` the dependent attachments explicitly, or
the new host comes up off the private net and/or public-exposed before the
firewall re-attaches. The existing 5-target allow-set already encodes this — use
it; do not hand-roll a narrower target list.

PR-B needs no apply: `cloud-init.yml` governs *future* fresh web hosts. The
running fleet carries `ignore_changes = [user_data]`, so the gate is inert until
web-1 is next recreated — which is exactly the cutover's resume path.

### Distinctness / drift safeguards
- `soleur-inngest/prd` ≠ `soleur/prd` — asserted by the existing boot isolation self-check.
- `ignore_changes = [user_data]` on both host resources: config changes are **latent**, not live. Any AC claiming a running-host effect must name a delivery step.
- Tag↔pin coupling (`hr-tagged-build-workflow-needs-initial-tag-push`): if PR-A bumps the bootstrap image, the tag push and all pins move in the **same** PR.

### Vendor-tier reality check
No new vendor resource. `betteruptime_heartbeat.inngest_prd` already exists and
is `paused = true`; this plan does **not** unpause it and does **not** add a
heartbeat.

## Observability

```yaml
liveness_signal:
  what: SOLEUR_* marker from inngest-server-probe (HTTP 200 on 127.0.0.1:8288/health)
  cadence: 60s systemd timer
  alert_target: Better Stack Logs source 2457081 (absence-of-marker is queryable)
  configured_in: inngest-bootstrap.sh (unit) + vector.toml Source 4 (allowlist)

error_reporting:
  destination: Sentry (stage: schema, new on this host) + Better Stack (existing phone-home)
  fail_loud: true — the OCI pull stays fail-closed after both registry arms

failure_modes:
  - mode: zot unreachable / unauthorized at boot
    detection: Sentry stage:inngest_ghcr_fallback (warning)
    alert_route: zot-soak-6122.sh denominator; sentry_issue_alert.zot_mirror_fallback_rate
  - mode: both registries fail
    detection: Sentry stage-fatal + Better Stack oci-pull-rc-<n> + absent boot markers
    alert_route: host never reaches bootstrap-done; marker absence localizes the stage
  - mode: inngest-server dead but host up
    detection: absence of inngest-server-probe marker (NEW — today only absence-of-WARN)
    alert_route: Better Stack Logs query on the inngest-server-probe channel
  - mode: fresh web host registers cloudflared pre-NIC
    detection: soleur-wait-ready nic stage emit + fail-closed exit
    alert_route: boot-stage marker absence; host does not become a connector

logs:
  where: Better Stack Logs source 2457081 via Vector Source 4 (journald)
  retention: per existing Better Stack plan

discoverability_test:
  command: bash scripts/betterstack-query.sh --grep SOLEUR_INNGEST_SERVER_PROBE
  expected_output: >=1 row per 60s window on a healthy host; zero rows is now a
    POSITIVE down-signal rather than an ambiguous silence
```

**The gap this closes.** Vector Source 1 ships only `PRIORITY 0-4`, so a healthy
inngest-server is *structurally silent*. Absence-of-WARN was the only liveness
signal — which is why #6617's question stayed unanswerable for days. A5's four
tags are the same class: `inngest-redis`, `inngest-nftables`, and
`inngest-boot-phone-home` emit at `PRIORITY 5-6` and match **no** source today, so
their zero-row state carries no information at all.

**Known drift (in scope to state, out of scope to fix):** the deployed OCI image
predates the current repo `vector.toml`, so running behavior does not match repo
config — a `PRIORITY=6` row arrived despite Source 1's documented `0-4` filter.
No AC in this plan may treat the repo file as evidence of running-host behavior.

### Soak follow-through enrollment
PR-A's zot arm feeds `zot-soak-6122.sh`, whose C1 blocker arm reads #6500's state
via `gh`. Closing #6500 is what unblocks that arm — **do not remove the arm to
make the gate pass** (#6500's own instruction). No new soak script; this plan
extends an existing soak's denominator.

## Architecture Decision (ADR/C4)

### ADR
**No new ADR.** All three changes *implement* decisions already recorded:
ADR-096 (three-tier zot gate), ADR-114 §I1 (the NIC-wait, verbatim), ADR-100
(dedicated-host observability). None reverses or extends a recorded Decision.

**One amendment is required:** ADR-114 §I1 currently reads *"Not shipped in
#6416; no phase of that PR claims to enforce I1."* PR-B ships it — the ADR must
be amended in the same PR, or the corpus lies about the system.

### C4 views
**No C4 impact.** Enumeration checked against all three model files
(`model.c4`, `views.c4`, `spec.c4`):

- **External human actors:** none added.
- **External systems:** zot registry, GHCR, Sentry, Better Stack, Cloudflare
  Tunnel — all already modeled (`zot` 22 refs, `ghcr` 9, `sentry` 14,
  `betterstack` 15, `tunnel` 14 in `model.c4`), all already `include`d in
  `views.c4`.
- **Containers / data stores:** none added. The inngest host and registry host
  are modeled.
- **Actor↔surface access relationships:** unchanged. The inngest host already
  has a modeled pull edge; this plan changes *which registry it prefers*, not
  *who may reach what*.

The one thing that would change this: if A0 forces enrolling `10.0.1.40` as a new
zot client, that **is** a new relationship edge and the `.c4` edit becomes an
in-scope task.

## Domain Review

**Domains relevant:** Engineering.

### Engineering

**Status:** reviewed
**Assessment:** Infrastructure-only change across two immutable hosts. The
dominant risks are sequencing (an unbootable singleton with no rollback if
ADR-096 5.3 lands first) and latency-of-effect (`ignore_changes = [user_data]`
makes every change latent until a replace). Both are addressed structurally: the
CI-ownership phase (A3) prevents recurrence of the ungoverned-pin root cause, and
the apply-path section names the delivery step for every latent change. Product,
Legal, Finance, Marketing, Sales, Support, Operations: not relevant — no
user-facing surface, no new vendor, no new recurring cost, no regulated-data
surface.

**Product/UX Gate:** skipped — mechanical UI-surface scan over `Files to Edit`
matched zero paths under `components/**`, `app/**/page.tsx`, `app/**/layout.tsx`.
Tier NONE.

## GDPR / Compliance Gate

Not invoked. No regulated-data surface: no schema, no migration, no auth flow, no
API route, no `.sql`. Triggers (a)–(d) do not fire — no LLM processing of
operator data, no new cron reading `knowledge-base/`, no new artifact
distribution surface. The `single-user incident` threshold (trigger b) is
declared, so this is recorded rather than skipped silently: the threshold is set
by *availability* blast-radius, not by personal-data processing.

One adjacent note carried from User-Brand Impact: registry credentials are baked
into `user_data`. PR-A must not widen that bake, and must not tail credential-
bearing logs into Sentry — `inngest-boot-phone-home.sh` already documents that
its POST bypasses Vector's PII scrub, so anything it ships must be pre-scrubbed.

## Open Code-Review Overlap

**None.** Queried all 61 open `code-review` issues; zero bodies reference
`cloud-init-inngest.yml`, `cloud-init.yml`, `vector.toml`, `inngest-bootstrap.sh`,
or `inngest-host.tf`.

## Acceptance Criteria

### Pre-merge (PR-A)

1. `grep -c 'zot\|ZIREF' apps/web-platform/infra/cloud-init-inngest.yml` ≥ 1 (was 0).
2. The zot arm is followed by a GHCR fallback and the pull remains fail-closed after both — asserted by an `inngest-host.test.sh` case, not by eyeball.
3. A Sentry `stage:` emit exists on the pull path emitting `inngest_zot` / `inngest_ghcr_fallback`, matching the tag vocabulary `zot-soak-6122.sh` greps.
4. `inngest-host.test.sh` asserts: zot arm, GHCR fallback, fail-closed pull, Sentry emit, pin-consistency. Test count strictly increases.
5. Vector Source 4 contains all four new tags; `journald-config.test.sh` asserts each by exact value.
6. `inngest-server-probe.{service,timer}` render with an explicit `SyslogIdentifier=inngest-server-probe`, and the marker emits **unconditionally before** health classification.
7. The dark heartbeat arm no longer logs unconditionally every 60 s, and the diff contains **no write of a heartbeat URL value** (verified by grepping the diff for the secret name paired with any write verb; expected count 0).
8. A0's four probe results are pasted verbatim in the PR body, including the literal zot HTTP status observed.
9. `bash apps/web-platform/infra/inngest-host.test.sh` and `journald-config.test.sh` both exit 0.
10. PR body uses `Closes #6500` and `Ref #6617`.

### Pre-merge (PR-B)

11. `soleur-wait-ready` supports `nic <ip> <stage>` with a bounded poll and fail-closed exit; the timeout is a named constant with a stated rationale.
12. In the rendered `web_tunnel_connector=true` template, the NIC-wait line number is **strictly less than** the `cloudflared service install` line number (the `private-nic-guard.test.sh` ordering idiom).
13. With `web_tunnel_connector=false`, neither the NIC-wait nor the cloudflared install renders.
14. ADR-114 §I1 is amended: the "Not shipped in #6416" sentence is updated to record this PR.
15. `bash apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh` exits 0.
16. PR body uses `Ref #6441` and `Ref #6466` (**not** `Closes` — the fix takes effect only on a future host replace; see Risks).

### Post-merge (gated dispatch — all API-verified)

17. `inngest-host-replace` dispatched; the fresh boot emits `inngest_zot` **or** `inngest_ghcr_fallback` to Sentry — verified by API query.
18. `scripts/betterstack-query.sh --grep SOLEUR_INNGEST_SERVER_PROBE` returns ≥ 1 row in a 5-minute window.
19. Better Stack row volume on the `inngest-heartbeat` channel drops materially from the ~1,414/24 h baseline.
20. `zot-soak-6122.sh` C1 blocker arm no longer names #6500 as OPEN.

**Automation:** 17–20 are all API-readable (`gh workflow run`, `betterstack-query.sh`,
Sentry API). None is operator-eyeball; per `hr-no-dashboard-eyeball-pull-data-yourself`
each is a query with a deterministic verdict rule.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| **Sequencing:** ADR-096 5.3 revokes the GHCR PAT before PR-A merges → the singleton is unbootable with no rollback (5.3–5.5 are irreversible). | This plan is the 5.3 blocker. #6462 already wires the soak to refuse while #6500 is OPEN. Do not weaken that arm. |
| **A0 shows zot cannot serve `10.0.1.40`.** | Explicit stop-and-re-scope gate. A fallback whose primary arm can never succeed is worse than no fallback — it looks fixed and is not. |
| **Latent config:** `vector.toml`/`cloud-init` edits never reach the running host (`ignore_changes = [user_data]`). | Every latent change names its delivery step. No AC treats a repo grep as running-host evidence. |
| **`-target` walks upstream only** → replaced host lands off the private net or public-exposed. | Use the existing 5-target allow-set; do not hand-roll. |
| **Fresh Hetzner host boots with private NIC down** → B2's wait times out on an attached-but-unconverged host. | B3 mirrors the registry host's bounded-reboot converger rather than writing a new one. |
| **PR-B is latent on the running fleet** → a "fixed" claim that is inert. | AC16 uses `Ref`, not `Closes`. #6441 closes when a fresh web-1 has actually booted through the gate. |
| **The ZIREF reference pattern has never run in production** (`web_colocate_inngest` default false). | Treated as new code with its own tests; not assumed correct by precedent. |
| **Credential widening** into Sentry/Better Stack via a log tail. | Pre-scrub anything the phone-home ships (it bypasses Vector's PII scrub by design). |

## Alternatives Considered

| Option | Verdict |
|---|---|
| **One PR for all three items** | **Rejected.** PR-B touches a different host with a different apply path; bundling couples a web-host boot change to an inngest-host replace for no benefit. |
| **Three PRs (one per issue)** | **Rejected.** #6500 and #6617(a,c) both land on `cloud-init-inngest.yml`/`vector.toml` and both take effect via the *same* `inngest-host-replace`. Splitting them buys a second replace cycle and nothing else. |
| **Provision the heartbeat URL now** (as briefed) | **Rejected** — bypasses the `op=arm` gate and creates the dual-pusher state #6552 exists to prevent. Re-scoped to quieting the dark arm. |
| **Extend `zot-soak-6122.sh` to query Better Stack** instead of porting Sentry to the host | **Rejected** — #6500's acceptance names the Sentry `stage:` schema explicitly, and the soak's other six paths already report there. Two schemas for one verdict is the worse shape. |
| **Attribute the NIC-wait to #6466** (as briefed) | **Rejected** — ADR-114 tracks it under #6441. Filing against #6466 would close an issue whose actual scope (host-addressability) remains untouched. |

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or contains placeholder text fails `deepen-plan` Phase 4.6.
- **Do not derive zot's HTTP behavior from its `accessControl` config.** Measure it against the pinned image (#6497). A policy-less user gets `Login Succeeded`, not `403` — a plan branching on an assumed status code builds an unreachable arm and tests that assert a string that cannot exist.
- **`grep` on the repo proves the file, not the host.** Both hosts carry `ignore_changes = [user_data]` and boot from pinned OCI images that predate `main`. "Baked and latent" is a claim about an artifact that may not exist — verify tag recency and content-carrier before trusting it.
- **An unset `SyslogIdentifier=` is the #6536 trap.** systemd tags the unit with the ExecStart basename (`doppler`, `bash`, `curl`), which matches no Vector source — the channel is silently dark. Every new unit in this plan sets it explicitly.
- A positive-control marker gated on the health it reports vanishes exactly when it is needed. Emit unconditionally, before classification, rate-limited (ADR-117 / #6537).
