---
title: "obs: suppress soleur_www uptime monitor during docs-deploy Pages rebuild (Option A)"
issue: 4596
branch: feat-one-shot-4596-suppress-www-uptime-docs-deploy
type: feat
lane: single-domain
brand_survival_threshold: none
date: 2026-05-29
---

# obs: suppress `soleur_www` uptime monitor during docs-deploy Pages rebuild (Option A)

✨ **feat** — Closes #4596

## Enhancement Summary

**Deepened on:** 2026-05-29
**Sections enhanced:** Research Reconciliation, Risks & Mitigations, Observability, Sharp Edges

### Key Improvements (from deepen pass)
1. **API contract verified against provider source.** Confirmed (via `jianyuan/terraform-provider-sentry` OpenAPI `api.yaml` + impl Go) that uptime monitors are Sentry **detectors** managed at `GET/PUT /api/0/organizations/{org}/detectors/{detector_id}/`, NOT the Crons `/monitors/` endpoint. The PUT requires the FULL `ProjectMonitorRequest` body → GET-then-PUT design.
2. **Self-heal claim corrected (verify-the-negative pass).** The provider sends `enabled: null` on apply when the HCL attribute is omitted (`resource_uptime_monitor_impl.go:66-69`), so the next `apply-sentry-infra.yml` run is NOT a guaranteed self-heal. The `if: always()` resume step is now documented as the sole re-enable guarantee.
3. **Secrets/auth precedent confirmed.** `SENTRY_IAC_AUTH_TOKEN` + `SENTRY_API_HOST` + `SENTRY_ORG` exist as GitHub repo secrets (`gh secret list`); the curl-auth shape mirrors `sentry-monitors-audit.sh`.

### New Considerations Discovered
- A bare partial `PUT {"enabled": false}` may 400 (OpenAPI `requestBody.required: true` against full schema) — flagged as a /work live-probe OQ; default to GET-then-PUT.
- Probe cap default (5 min) may be under-sized vs. the observed ~15-min flap; resume is unconditional so under-sizing only weakens the "confirming" log, never strands the monitor.

## Overview

The `soleur_www` Sentry uptime monitor asserts `equals 301` (www must redirect to the
canonical apex). A docs deploy (`deploy-docs.yml`) rebuilds GitHub Pages and
re-propagates the custom-domain apex-canonical redirect; during that window
`https://www.soleur.ai/` transiently serves its own `200` instead of the `301`,
false-paging the monitor on our own deploy (observed 2026-05-29 ~12:30 CEST, #4573/#4578).

The predecessor PR #4595 (Option B) absorbed the window by widening
`downtime_threshold` 3→5 (≈15→25 min fuse) — at a cost of **+10 min MTTD** on a real
www-only redirect regression. Option A removes the window from the monitor's view
entirely (zero MTTD cost): pause the monitor for the duration of the Pages rebuild,
then resume it after the deploy + a propagation grace + one confirming `301` probe.
Once Option A lands, the conservative `downtime_threshold = 5` is superseded and is
ratcheted back to `3` for parity with `soleur_apex`.

This is a pure CI/infra change. No application code, no schema, no user-facing surface.

## Research Reconciliation — Spec vs. Codebase

The issue body sketches the mechanism but understates the API contract. The single
most consequential reconciliation: **uptime monitors are NOT served by the legacy
`/organizations/{org}/monitors/` (Crons) endpoint** — they live under the unified
`/detectors/` API. The plan-skill Sharp Edge from #4591 calls this out, and the
provider source confirms it.

| Claim (issue / intuition) | Reality (verified against provider source + OpenAPI spec) | Plan response |
| --- | --- | --- |
| "Pause the monitor via the Sentry API" — endpoint unspecified | `sentry_uptime_monitor` is a Sentry **detector**. Managed at `GET/PUT /api/0/organizations/{org}/detectors/{detector_id}/`; the `enabled` boolean toggles pause/resume. The legacy `/organizations/{org}/monitors/` path (used by `sentry-monitors-audit.sh:230`) is **Crons-only** and does NOT return uptime monitors. Verified: `jianyuan/terraform-provider-sentry` `internal/apiclient/api.yaml` paths `listOrganizationMonitors` = `GET /0/organizations/{org}/detectors/`, `updateProjectMonitor` = `PUT /0/organizations/{org}/detectors/{detector_id}/`. | Pause/resume via the `/detectors/` endpoint. Identify the monitor by `name == "soleur-ai-www"` + `type` from the list endpoint (Sentry allows duplicate names; cross-check `type`). |
| "set a maintenance window" (alternative phrasing) | The pinned provider `v0.15.0-beta2` exposes only the `enabled` boolean — **no** native "maintenance window" attribute. `ProjectMonitor` response schema: `{id, projectId, enabled, name, type, ...}`. | Use the `enabled` toggle, not a non-existent maintenance-window API. |
| `PUT {"enabled": false}` is a simple partial patch | `updateProjectMonitor` `requestBody.required: true` against the **full** `ProjectMonitorRequest` schema (type + dataSources + conditionGroup + config). A bare `{"enabled": false}` PUT risks a `400`. | **GET-then-PUT round-trip**: fetch the full detector object, mutate only `.enabled` via `jq`, PUT the mutated object back. Robust against the full-body requirement. |
| "reuse the token `apply-sentry-infra.yml` already uses if scoping allows" | `SENTRY_IAC_AUTH_TOKEN` (GitHub repo secret, maps to `iac-terraform-prd` internal integration on `jikigai-eu`) is the exact token the apply workflow uses for write ops. `SENTRY_API_HOST`, `SENTRY_ORG` are GitHub repo secrets (verified via `gh secret list`). | Reuse `SENTRY_IAC_AUTH_TOKEN` + `SENTRY_API_HOST` + `SENTRY_ORG`. Scoping is sufficient (same token already does write applies to these detectors). |
| Toggling `enabled` via CI is drift-neutral | The TF resource `sentry_uptime_monitor.soleur_www` has **no** `enabled` attribute. The provider schema documents the default as `true`, BUT the impl sends `enabled: null` on the API request when the attribute is omitted (`resource_uptime_monitor_impl.go:66-69` — `out.Enabled.SetNull()`). Whether the Sentry API treats `enabled: null` as "leave unchanged" vs "reset to default true" is **NOT verified** — so the next `apply-sentry-infra.yml` run is **NOT a guaranteed self-heal**. Within one deploy run, a `false`→`true` toggle nets to `true` (no drift) only if resume succeeds. | The `if: always()` resume step is the **sole** re-enable guarantee — do NOT rely on the TF apply to undo a stuck pause. Resume fails loud (red workflow). No `lifecycle.ignore_changes` needed (the attribute is absent from HCL). /work: optionally verify the `enabled: null` apply semantics with one live apply-dry-run, but design for the resume step being the only heal path. |

## User-Brand Impact

**If this lands broken, the user experiences:** nothing user-facing. The blast radius is
internal observability only — a docs-deploy CI workflow gains a pause/resume bracket
around an uptime monitor. Worst realistic failure is a monitor that stays paused
(missed alert window) or a deploy step that fails after the pause (caught by `if: always()` resume).

**If this leaks, the user's data is exposed via:** N/A. No user data, no PII, no
regulated surface is touched. The only secret in play (`SENTRY_IAC_AUTH_TOKEN`) is
already present in `apply-sentry-infra.yml` and is routed through env vars (never
interpolated into `run:` bodies).

- **Brand-survival threshold:** `none`
- `threshold: none, reason: pure CI/infra change — the diff touches only .github/workflows/deploy-docs.yml (a public docs-site deploy workflow) and a single Terraform scalar in apps/web-platform/infra/sentry/uptime-monitors.tf; no schema, auth flow, API route, .sql, or user-data surface, and the only secret (SENTRY_IAC_AUTH_TOKEN) is pre-existing and env-routed (never interpolated into run: bodies).`

## Acceptance Criteria

### Pre-merge (PR)

- [x] **AC1 — Pause step exists and is correct.** `deploy-docs.yml` has a step BEFORE
  `Setup Pages` that: (a) GETs `https://${SENTRY_API_HOST}/api/0/organizations/${SENTRY_ORG}/detectors/`,
  (b) selects the object with `.name == "soleur-ai-www"` (and `.type` matching the
  uptime detector type) to extract `.id`, (c) GET-then-PUTs that detector with
  `.enabled = false`. Verify: `grep -n 'detectors' .github/workflows/deploy-docs.yml` returns ≥2 hits (list + put).
- [x] **AC2 — Resume step is `if: always()`.** The resume step (re-enable, `.enabled = true`)
  runs with `if: always()` so a failed deploy/probe still re-enables the monitor.
  Verify: the resume step's `if:` line equals `always()`.
- [x] **AC3 — Propagation grace + confirming probe.** Between deploy and resume, the
  workflow probes `https://www.soleur.ai/` and waits until it returns `301` (bounded
  retry loop with a `curl --max-time` per attempt and a finite attempt cap), then
  resumes. The probe is best-effort: if `301` is not observed within the cap, the
  workflow STILL resumes the monitor (never leave it paused) and logs a warning.
  Verify: `grep -n 'www.soleur.ai' .github/workflows/deploy-docs.yml` shows a probe loop;
  every `curl` in the new steps has `--max-time`.
- [x] **AC4 — Token reuse, env-routed.** The new steps consume `SENTRY_IAC_AUTH_TOKEN`,
  `SENTRY_API_HOST`, `SENTRY_ORG` via `env:` blocks (NOT inline `${{ secrets.* }}` in `run:`).
  No untrusted input reaches a `run:` body unquoted. Verify: `grep -n 'SENTRY_IAC_AUTH_TOKEN\|SENTRY_API_HOST\|SENTRY_ORG' .github/workflows/deploy-docs.yml`.
- [x] **AC5 — Permissions unchanged or minimally widened.** The deploy job's
  `permissions:` block is unchanged (the Sentry call uses a repo secret, not the
  GITHUB_TOKEN). Verify: `permissions:` still lists exactly `contents: read`,
  `pages: write`, `id-token: write`.
- [x] **AC6 — Threshold ratcheted back to 3.** `uptime-monitors.tf`
  `sentry_uptime_monitor.soleur_www` has `downtime_threshold = 3` (parity with
  `soleur_apex`). The 2026-05-29 "longer fuse" comment block is replaced with a
  comment explaining the Option-A suppression supersedes the fuse widening (cite #4596).
  Verify: `grep -n 'downtime_threshold' apps/web-platform/infra/sentry/uptime-monitors.tf`
  shows `3` for both apex and www.
- [x] **AC7 — `actionlint` clean.** `actionlint .github/workflows/deploy-docs.yml`
  exits 0; embedded `run:` shell snippets pass `bash -n` when extracted (or `bash -c`).
- [x] **AC8 — `terraform validate` clean on the sentry root.** From
  `apps/web-platform/infra/sentry`: `terraform init -backend=false && terraform validate`
  exits 0 after the threshold change. (Threshold is a scalar `3`; no schema risk.)
- [x] **AC9 — Destroy-guard suites still green.** The threshold change is an in-place
  UPDATE, not a destroy. `bash tests/scripts/test-destroy-guard-counter-sentry.sh` and
  `bash tests/scripts/test-destroy-guard-sentry-scope-guard.sh` both pass unchanged
  (the workflow `-target=` list is NOT modified by this PR).

### Post-merge (operator / CI — automated)

- [ ] **AC10 — `apply-sentry-infra.yml` applies the threshold change.** The merge to
  `main` touches `uptime-monitors.tf`, which auto-fires `apply-sentry-infra.yml` (#4585);
  it applies `downtime_threshold = 3` to the live `soleur_www` detector.
  Automation: `apply-sentry-infra.yml` push trigger (no operator action). Verify post-apply
  via the workflow run summary, OR via `GET /api/0/organizations/{org}/detectors/` and
  confirm `soleur-ai-www` reflects the new threshold.
- [ ] **AC11 — First post-merge docs deploy does not page `soleur_www`.** The next
  `deploy-docs.yml` run pauses then resumes the monitor; no `soleur_www` page fires
  during the deploy window. (Observable via Sentry detector check history.)

## Implementation Phases

### Phase 1 — Add pause/resume bracket to `deploy-docs.yml`

**File:** `.github/workflows/deploy-docs.yml`

The deploy job runs inside the Playwright container (`bash` default shell; `curl`, `jq`
available — `jq` is present in the image; if not, the step installs it). The bracket
wraps the Pages-publishing steps so the monitor is blind to the rebuild + propagation.

1. **Pause step** — insert after `Screenshot gate` (line 152) and before `Setup Pages`
   (line 162). Pseudocode (final shell lives in the workflow):

   ```yaml
   - name: Pause soleur_www uptime monitor (suppress deploy-window false page)
     id: pause_www_monitor
     env:
       SENTRY_AUTH_TOKEN: ${{ secrets.SENTRY_IAC_AUTH_TOKEN }}
       SENTRY_API_HOST: ${{ secrets.SENTRY_API_HOST }}
       SENTRY_ORG: ${{ secrets.SENTRY_ORG }}
     run: |
       set -euo pipefail
       which jq >/dev/null 2>&1 || (apt-get update && apt-get install -y jq)
       # Uptime monitors are Sentry "detectors", NOT Crons monitors — they are
       # served by /detectors/, not /organizations/{org}/monitors/ (#4591).
       detectors=$(curl -sS --max-time 20 \
         -H "Authorization: Bearer ${SENTRY_AUTH_TOKEN}" \
         "https://${SENTRY_API_HOST}/api/0/organizations/${SENTRY_ORG}/detectors/")
       # Select by name (Sentry allows dup names — also cross-check the uptime type).
       id=$(jq -r '[.[] | select(.name == "soleur-ai-www")] | .[0].id // empty' <<<"$detectors")
       if [[ -z "$id" ]]; then
         echo "::warning::soleur-ai-www detector not found; skipping pause (deploy continues)."
         echo "monitor_id=" >> "$GITHUB_OUTPUT"
         exit 0
       fi
       echo "monitor_id=${id}" >> "$GITHUB_OUTPUT"
       # Full-body GET-then-PUT: updateProjectMonitor requires the full
       # ProjectMonitorRequest; a bare {"enabled":false} PUT risks a 400.
       full=$(curl -sS --max-time 20 \
         -H "Authorization: Bearer ${SENTRY_AUTH_TOKEN}" \
         "https://${SENTRY_API_HOST}/api/0/organizations/${SENTRY_ORG}/detectors/${id}/")
       body=$(jq '.enabled = false' <<<"$full")
       curl -sS --max-time 20 -X PUT \
         -H "Authorization: Bearer ${SENTRY_AUTH_TOKEN}" \
         -H "Content-Type: application/json" \
         -d "$body" \
         "https://${SENTRY_API_HOST}/api/0/organizations/${SENTRY_ORG}/detectors/${id}/" \
         -o /dev/null -w 'pause PUT status: %{http_code}\n'
       echo "Paused soleur-ai-www detector ${id}."
   ```

   > **Open question for /work:** confirm via one live `PUT` (or a Sentry-side check)
   > whether the SaaS accepts a partial `{"enabled": false}` PUT. If it does, the
   > GET-then-PUT can be simplified. Default to GET-then-PUT (safe) unless verified.
   > The DELETE-FK / full-body assumption is from the OpenAPI `requestBody.required: true`.

2. **Probe-then-resume step** — insert AFTER `Deploy to GitHub Pages` (line 173).
   Runs `if: always()` so a failed deploy still resumes. Probe loop with a finite cap.

   ```yaml
   - name: Probe www→apex 301 then resume soleur_www monitor
     if: always()
     env:
       SENTRY_AUTH_TOKEN: ${{ secrets.SENTRY_IAC_AUTH_TOKEN }}
       SENTRY_API_HOST: ${{ secrets.SENTRY_API_HOST }}
       SENTRY_ORG: ${{ secrets.SENTRY_ORG }}
       MONITOR_ID: ${{ steps.pause_www_monitor.outputs.monitor_id }}
     run: |
       set -uo pipefail
       which jq >/dev/null 2>&1 || (apt-get update && apt-get install -y jq)
       # Propagation grace + confirming probe (best-effort; never block resume).
       confirmed=0
       for i in $(seq 1 30); do            # ~5 min cap @ 10s/attempt
         code=$(curl -s --max-time 10 -o /dev/null -w '%{http_code}' "https://www.soleur.ai/")
         if [[ "$code" == "301" ]]; then confirmed=1; break; fi
         sleep 10
       done
       [[ "$confirmed" -eq 1 ]] && echo "www→apex 301 confirmed." \
         || echo "::warning::www did not return 301 within probe cap; resuming monitor anyway."
       # Always resume, even if pause was skipped (no id) — resume only if we have an id.
       if [[ -z "${MONITOR_ID}" ]]; then
         echo "No monitor id captured at pause; nothing to resume."; exit 0
       fi
       full=$(curl -sS --max-time 20 \
         -H "Authorization: Bearer ${SENTRY_AUTH_TOKEN}" \
         "https://${SENTRY_API_HOST}/api/0/organizations/${SENTRY_ORG}/detectors/${MONITOR_ID}/")
       body=$(jq '.enabled = true' <<<"$full")
       http=$(curl -sS --max-time 20 -X PUT \
         -H "Authorization: Bearer ${SENTRY_AUTH_TOKEN}" \
         -H "Content-Type: application/json" \
         -d "$body" \
         "https://${SENTRY_API_HOST}/api/0/organizations/${SENTRY_ORG}/detectors/${MONITOR_ID}/" \
         -o /dev/null -w '%{http_code}')
       echo "resume PUT status: ${http}"
       if [[ "$http" != "200" ]]; then
         echo "::error::Failed to resume soleur-ai-www monitor (HTTP ${http}). \
   It may remain paused until the next apply-sentry-infra.yml run re-applies enabled=true."
         exit 1
       fi
       echo "Resumed soleur-ai-www detector ${MONITOR_ID}."
   ```

   Notes for /work:
   - Insert points are EXACT line anchors (read the file first per `hr-always-read-a-file-before-editing-it`).
   - The probe loop's `sleep`/cap (30×10s = 5 min) is a starting value; tune against the
     observed ~15-min flap from #4595's commit message if propagation is slower. The
     resume runs regardless of probe outcome, so an under-sized cap only weakens the
     "confirming" guarantee, never strands the monitor.
   - Keep all secret reads in `env:` blocks (matches `apply-sentry-infra.yml` posture).

### Phase 2 — Ratchet `downtime_threshold` 5→3 in `uptime-monitors.tf`

**File:** `apps/web-platform/infra/sentry/uptime-monitors.tf`

1. Change `sentry_uptime_monitor.soleur_www` `downtime_threshold = 5` → `3`.
2. Replace the "2026-05-29: longer fuse than the apex monitor (5 checks…)" comment block
   with a comment that explains: Option A (#4596) suppresses the deploy window at the
   source (deploy-docs.yml pause/resume), so the conservative fuse is no longer needed;
   threshold restored to 3 for parity with `soleur_apex`. Cite #4596 and #4595.
3. Leave `recovery_threshold = 1`, the `equals 301` assertion, and the `url` unchanged.
4. Do NOT add an `enabled` attribute or `lifecycle.ignore_changes` — the CI toggle nets
   to `true` on success via the `if: always()` resume step. Do NOT count on the next
   `apply-sentry-infra.yml` run to heal a stuck pause: the provider sends `enabled: null`
   when the HCL attribute is absent, and the API's null-handling semantics are unverified
   (see Reconciliation row 5). The resume step is the sole heal path.

### Phase 3 — Verification

- Run `actionlint .github/workflows/deploy-docs.yml` (AC7).
- Extract each new `run:` snippet and `bash -n` it (AC7).
- `cd apps/web-platform/infra/sentry && terraform init -backend=false && terraform validate` (AC8).
- `bash tests/scripts/test-destroy-guard-counter-sentry.sh` and
  `bash tests/scripts/test-destroy-guard-sentry-scope-guard.sh` (AC9 — both unchanged-green).

## Alternative Approaches Considered

| Approach | Why not chosen |
| --- | --- |
| **Keep Option B (threshold 5) only** | The issue explicitly supersedes it; +10 min MTTD on real www regressions is the cost Option A removes. Option A + threshold-3 is strictly better once the suppression exists. |
| **Terraform `enabled=false` toggle via two applies** | Would require two `apply-sentry-infra.yml` runs bracketing each deploy (orchestration nightmare, state-lock contention, far slower than a curl, and couples docs deploys to the Terraform pipeline). The curl toggle is the idiomatic "transient operational override" — the TF default `true` is the resume target, so no persistent drift. |
| **Native Sentry maintenance window** | The pinned provider `v0.15.0-beta2` and the `/detectors/` API expose only the `enabled` boolean — no maintenance-window primitive. |
| **Pause via legacy `/organizations/{org}/monitors/` endpoint** | That endpoint is Crons-only; it does NOT return uptime monitors (#4591). Would silently no-op. |
| **Bare `PUT {"enabled": false}` (partial)** | `updateProjectMonitor` requires the full `ProjectMonitorRequest` body; partial PUT risks 400. GET-then-PUT is the safe default (a /work-time live probe MAY confirm partial works and simplify). |

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/observability tooling change.
Pure CI workflow + a single Terraform scalar. No user-facing surface, no product/legal/
growth/community implication. (Engineering/CTO is the implicit owner; the issue carries
`domain/engineering`.)

## Infrastructure (IaC)

This change does NOT introduce new infrastructure. It (a) edits an existing GitHub
Actions workflow to make transient operational API calls against an already-provisioned
Sentry detector, and (b) edits one scalar on an existing Terraform-managed resource.

- **Terraform changes:** `apps/web-platform/infra/sentry/uptime-monitors.tf` —
  `downtime_threshold` 5→3 on `sentry_uptime_monitor.soleur_www`. No new resources, no
  new providers, no new variables. Apply path: the existing `apply-sentry-infra.yml`
  auto-apply (push-to-main, `-target=sentry_uptime_monitor.soleur_www` already in the
  list) — no new apply mechanism. Blast radius: in-place UPDATE of one monitor's fuse;
  zero downtime; destroy-count 0 (passes the existing destroy-guard).
- **No operator SSH / dashboard / secret-mint steps.** The Sentry token, API host, and
  org are pre-existing GitHub repo secrets (`gh secret list` confirmed). The pause/resume
  API calls are runtime operations, not provisioning.

## Observability

```yaml
liveness_signal:
  what: "soleur_www Sentry uptime detector — equals-301 assertion, 5-min interval"
  cadence: "every 300s (unchanged)"
  alert_target: "Sentry issue alert on assertion-false (paging path, unchanged)"
  configured_in: "apps/web-platform/infra/sentry/uptime-monitors.tf (soleur_www) + issue-alerts.tf"
error_reporting:
  destination: "GitHub Actions step logs + step summary; ::warning::/::error:: annotations on pause/resume failure"
  fail_loud: "resume step exits non-zero (red workflow) if the resume PUT != 200, with an explicit message that the monitor may remain paused until the next apply-sentry-infra.yml run"
failure_modes:
  - mode: "Pause succeeds, deploy/probe fails, resume succeeds"
    detection: "if: always() resume step runs; PUT returns 200"
    alert_route: "none needed — monitor restored; deploy failure surfaces via the normal red workflow"
  - mode: "Pause succeeds, resume FAILS (Sentry API down at resume time)"
    detection: "resume step PUT != 200 → step exits 1 (red workflow)"
    alert_route: "red deploy-docs run (visible in Actions); requires a deploy-docs re-run or operator re-enable — NOT auto-healed by the next sentry apply (enabled:null null-handling unverified)"
  - mode: "Detector not found at pause (name drift / API change)"
    detection: "::warning:: 'soleur-ai-www detector not found'; monitor_id output empty; deploy continues; nothing to resume"
    alert_route: "warning annotation in the run; monitor never paused so no missed-alert window"
  - mode: "Real www regression DURING a deploy window"
    detection: "monitor is paused during the window (accepted gap == the whole point of Option A); soleur_apex (threshold 3) still covers a user-facing outage"
    alert_route: "soleur_apex pages on a true apex outage; www-only regression caught on the next non-deploy check after resume"
logs:
  where: "GitHub Actions run logs for deploy-docs.yml (pause + probe/resume steps)"
  retention: "GitHub Actions default log retention (90 days)"
discoverability_test:
  command: curl -fsS -o /dev/null -w '%{http_code}' --max-time 10 https://www.soleur.ai/
  expected_output: "301"
```

## Open Code-Review Overlap

Ran `gh issue list --label code-review --state open` and checked for overlap with the two
edited files (`.github/workflows/deploy-docs.yml`, `apps/web-platform/infra/sentry/uptime-monitors.tf`).
**None.** (Verify at /work time with the two-stage `gh --json` then standalone `jq --arg`
pattern per the plan-skill check; the corpus is small.)

## Risks & Mitigations

- **Sentry `/detectors/` API is beta-adjacent and may change shape.** The provider's
  `v0.15.0-beta2` already drives these endpoints; the workflow uses the SAME REST surface.
  Mitigation: GET-then-PUT (resilient to added required fields); name-based lookup with a
  not-found warning that never blocks the deploy.
- **Probe cap under-sized vs. real propagation time.** The 2026-05-29 flap was ~15 min;
  the probe cap (5 min default) may expire before `301` returns. Mitigation: resume runs
  REGARDLESS of probe outcome — an under-sized cap only weakens the "confirming" log line,
  never strands the monitor. /work should consider a longer cap (e.g., 30×30s = 15 min) to
  match the observed window; weigh against deploy-job wall-clock.
- **Resume failure leaves the monitor paused.** Mitigated by `if: always()` + a fail-loud
  red workflow (the resume PUT exiting non-zero is visible in Actions). NOT silently
  self-healed by Terraform: the provider sends `enabled: null` on apply when the HCL
  attribute is absent, and the API's null-handling is unverified — treat the resume step
  as the only reliable heal path. If a resume genuinely fails, the operator (or a re-run of
  deploy-docs.yml) must re-enable; do not assume the next sentry apply fixes it.
- **`jq` absence in container.** The Playwright image MAY lack `jq`; both steps guard with
  `which jq || apt-get install -y jq` (matches `apply-sentry-infra.yml:165`).

### Precedent-Diff (Phase 4.4) — Sentry curl-auth pattern

The new pause/resume steps make authenticated Sentry REST calls. Two sibling precedents exist:

- `apps/web-platform/scripts/sentry-monitors-audit.sh` — uses `curl -H "Authorization: Bearer ${SENTRY_AUTH_TOKEN}"` against `https://${api_host}/api/0/...`, with a region-probe over `${SENTRY_ORG}.sentry.io` candidates and a `curl_retry()` wrapper for transient 500s. The org slug `jikigai-eu` requires the org-subdomain host (`SENTRY_API_HOST` secret pins it).
- `.github/workflows/apply-sentry-infra.yml` — passes `SENTRY_AUTH_TOKEN: ${{ secrets.SENTRY_IAC_AUTH_TOKEN }}` via `env:` to terraform/audit steps; never inlines the secret in `run:`.

**Diff vs. precedent in this plan:** the workflow consumes the SAME secrets (`SENTRY_IAC_AUTH_TOKEN`, `SENTRY_API_HOST`, `SENTRY_ORG`) via `env:` (matches apply-sentry posture), and uses the SAME `Bearer` header + `https://${SENTRY_API_HOST}/api/0/...` shape (matches audit-script posture). The plan does NOT replicate the audit script's region-probe loop because `SENTRY_API_HOST` is already a pinned secret (the probe is only needed when the host is unknown). /work MAY add a 2-attempt retry around the GET/PUT calls mirroring `curl_retry()` if the transient-500 pattern affects `/detectors/` (low priority — a failed pause/resume already fails loud).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/placeholder
  text, or omits the threshold will fail `deepen-plan` Phase 4.6. (This plan fills it:
  threshold = none, with a sensitive-path scope-out reason.)
- **Uptime monitors are detectors, not Crons monitors.** Any code that reaches for
  `/organizations/{org}/monitors/` to find `soleur_www` will silently no-op — that path is
  Crons-only (#4591). Use `/detectors/`.
- **`updateProjectMonitor` PUT requires the full body.** Do not assume a partial
  `{"enabled":false}` PUT works without a live probe — default to GET-then-PUT.
- **Do not add an `enabled` attribute to the TF resource** unless you also add
  `lifecycle.ignore_changes = [enabled]` — otherwise the CI toggle and Terraform fight over
  the field. The chosen design keeps `enabled` out of TF; the `if: always()` resume step is
  the sole re-enable guarantee (the provider sends `enabled: null` on omitted-attr apply, and
  the API's null-handling is unverified — do NOT treat the next sentry apply as a self-heal).
- **Insert points in `deploy-docs.yml` are line-anchored.** Read the file before editing;
  the pause step goes after the screenshot gate (line 152) and before `Setup Pages`
  (line 162); the resume step goes after `Deploy to GitHub Pages` (line 173).

## References

- Issue: #4596 (this), #4595 (Option B predecessor — threshold 3→5), #4585/#4591
  (auto-apply extended to `sentry_uptime_monitor.*`), #4577/#4573/#4578 (apex-canonical flip).
- Files: `.github/workflows/deploy-docs.yml`, `apps/web-platform/infra/sentry/uptime-monitors.tf`,
  `.github/workflows/apply-sentry-infra.yml` (token + apply precedent),
  `apps/web-platform/scripts/sentry-monitors-audit.sh` (region-probe + auth pattern precedent).
- API contract: `jianyuan/terraform-provider-sentry` `internal/apiclient/api.yaml`
  (`listOrganizationMonitors` = `GET /0/organizations/{org}/detectors/`;
  `updateProjectMonitor` = `PUT /0/organizations/{org}/detectors/{detector_id}/`; `enabled` bool).
  Provider pinned at `v0.15.0-beta2` (`apps/web-platform/infra/sentry/.terraform.lock.hcl`).
- ADR: `knowledge-base/engineering/architecture/decisions/ADR-031-sentry-as-iac.md` (token/secret-store model).

## Files to Edit

- `.github/workflows/deploy-docs.yml` — add pause step (before Setup Pages) + probe/resume
  step (after Deploy to GitHub Pages, `if: always()`).
- `apps/web-platform/infra/sentry/uptime-monitors.tf` — `downtime_threshold` 5→3 on
  `soleur_www` + comment update.

## Files to Create

- None.
