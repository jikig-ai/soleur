# Session State — #7095 (PR-A: restore production)

Branch `feat-one-shot-7095-host-pull-leg`, draft PR #7097.

## Plan Phase — complete

Plan: `knowledge-base/project/plans/2026-07-30-fix-web-host-doppler-token-revocation-broke-host-pull-leg-plan.md`

**The issue's premise was falsified by measurement.** All three ADR-096 clause (f) suspects
(private NIC, `ZOT_PULL_*`, zot `accessControl`) are healthy. The real fault is one credential
level up and is a **second, distinct incident**: web-1's boot-baked full-`prd` Doppler service
token in `/etc/default/webhook-deploy` was revoked at **2026-07-30T11:19:30.614Z**, so
`doppler secrets get` returns empty → `ZOT_REGISTRY_URL` empty → the zot gate takes its
`"dark, pre-provisioning"` branch and never contacts zot → unauthenticated GHCR pull of a private
package → `auth_denied` → `image_pull_failed`. The two incidents share only that reason string,
which is why eight red releases read as one known incident.

## Work Phase — Phase 0 complete, implementation in progress

### Phase 0 measured results (recorded in the plan under `## Phase 0 Results`)

- **0.0 RESOLVED to branch (a)** — `/etc/default/inngest-server` DOES exist on web-1; the
  `web-probe-read-token.tf:5-6` parenthetical is stale. Two independent proofs: (i)
  `inngest-heartbeat.service` carries a NON-optional `EnvironmentFile` for it and ran healthy
  until 11:19:56; (ii) unit failure onset is +18.17s / +26.14s after the mint with zero failures
  in the preceding 53h, and since the ExecStart branches on `[ -n "$DOPPLER_TOKEN" ]`, an empty
  token would make behaviour invariant across the revocation — it flipped. **H7b CONFIRMED.**
- **0.4 — Terraform's copy of the token is ALIVE (HTTP 200)** and its rendered env line carries no
  CR/`#`/space/newline. This is the precondition the entire remediation rests on.
- 0.2 channel alive (`complete: 15/15 files written, 0 failed` @ 16:32:48); 0.2b apply workflow
  green @ 16:30:44 (root-SSH leg alive); 0.3 token state unmoved.
- Prod self-reports `version: 0.244.0` against latest tag v0.246.1.
- `web-{1,2}.app.soleur.ai` do NOT resolve (000) — the per-host origin probes R33 wants for PR-B
  do not exist as DNS today.

### Landed commits

| commit | content |
|---|---|
| `24bd9c143` | Phase 0 measured results into the plan |
| `f5278fe72` | `release-outcome` terminal job — alerts the operator on ANY failed release run |
| `d0e000920` | credential-delivery core (tmpl, server.tf render, var validation, payload/hooks/FILE_MAP/DEST_SPEC, envfile_shape + mkdir -p, gate tier-1/tier-2) |
| `ceba900b2` | consumer wiring (3 units, 2 drop-ins, ci-deploy-wrapper source) + de-hardcoded 9 literal `15`s |
| `78142fc64` | apply-workflow `paths:` + R34 webhook-down branch + R22 falsification recorded |

### Suite status at last run

`infra-config-gate` 18/18 · `infra-config-install` 31/31 · `infra-config-apply` 63/63.

### Review revisions that did NOT survive contact (recorded in the plan)

- **R22 FALSIFIED.** `deploy_pipeline_fix` `depends_on` `infra_config_handler_bootstrap`
  (`server.tf:1306`), which writes the new `hooks.json` (`:1204`) and restarts the listener
  (`:1219`) before the push. The #5515 edge exists for exactly this scenario. A second apply pass
  would guard an unreachable state, and would be a no-op without `-replace` anyway.
  **Residual (real, deliberately deferred):** the verify step only re-polls and never re-POSTs, so
  it cannot recover from the documented nonce-1 race. Fixing it means putting `continue-on-error`
  on the fail-closed gate whose latched false-green (#6594) let this outage class hide — not a
  change to make under outage pressure.
- **R27 CONFIRMED** by an independent slice: `web-platform-release.yml`'s `case` at `:706` is on
  `$EXIT_CODE`, not on reason, and already echoes the reason at `:728-732`. No edit needed there.

### In flight (background agents, strict file ownership)

1. `ci-deploy.sh` + `ci-deploy.test.sh` — credential-read diagnostics (`SOLEUR_DEPLOY_CRED_FAIL
   rc= empty= err=`), `MOCK_DOPPLER_GET_FAIL` seam, positive controls, fail-OPEN preserved per R25.
   **Observability only — no new abort path.**
2. Five-way lockstep parity — `ship-deploy-pipeline-fix-gate.test.ts` `TRIGGER_FILES`,
   `ship/SKILL.md` `DEPLOY_PIPELINE_FIX_TRIGGERS` + `DPF_REGEX`, `cron-egress-firewall.test.sh`
   order assertion (mutation-tested).
3. `cloud-init.yml` fresh-host parity — must consume the ALREADY-RENDERED string (R8: render once,
   inject) and report the one-line `server.tf` change needed.

### Exit gates — BOTH runners, against a clean committed tree

| gate | rc | result |
|---|---|---|
| `scripts/test-all.sh` | 0 | 239/239 suites |
| `apps/web-platform/infra/run-registered-suites.sh` | 0 | 87/87 suites, zero orphans |

Both required: `test-all.sh` does NOT cover `apps/web-platform/infra/` and says so in its preamble.
An earlier `test-all.sh` run was KILLED rather than interpreted — files were edited while it was
in flight, which makes its output a mid-refactor snapshot of the author's own making.

### Follow-ups filed (net flow: 0 closed, 2 filed, +2 — stated deliberately)

- **#7103** — consolidated PR-B tracker (telemetry off the box, credential liveness, staleness
  alerting, the 19-of-19 web-1 pinning, ADR-154 + PIRs).
- **#7104** — the R22 residual, kept SEPARATE as a discovered defect in a different subsystem:
  the apply-verify step re-polls but never re-POSTs, so it cannot recover from the documented
  nonce-1 webhook-restart race.

#7095 itself stays OPEN and was re-titled — its original title named the falsified premise
(`ZOT_PULL_*`/private NIC), which actively misleads anyone triaging a live P1. A correcting
comment carries the E1–E5 evidence; the original body is left intact for the record.

### Remaining after those land

- Apply the `server.tf` `user_data` key the cloud-init slice reports.
- Full-suite exit gate: `scripts/test-all.sh` AND `apps/web-platform/infra/run-registered-suites.sh`
  (the diff touches `apps/web-platform/infra/`, which `test-all.sh` does NOT cover).
- `/review` → `/qa` → `/compound` → `/ship`.
- Post-mortem stays `status: ongoing` until prod genuinely deploys again.
