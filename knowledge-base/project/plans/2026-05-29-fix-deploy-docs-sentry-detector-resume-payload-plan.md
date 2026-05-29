---
title: "fix: deploy-docs.yml Sentry detector resume/pause PUT sends minimal {enabled} payload"
type: fix
issue: 4618
branch: feat-one-shot-4618-deploy-docs-sentry-resume
lane: single-domain
created: 2026-05-29
brand_survival_threshold: aggregate pattern
---

# 🐛 fix: deploy-docs.yml Sentry detector resume/pause PUT sends minimal `{enabled}` payload (HTTP 400 → 200)

## Enhancement Summary

**Deepened on:** 2026-05-29
**Sections enhanced:** Research Insights (live API probe), Risks (precedent-diff gate), Sharp Edges (verb + round-trip)

### Key Improvements

1. **Live API reproduction + fix verification** — the 400 was reproduced against `jikigai-eu.sentry.io` and the
   minimal-payload fix verified to return 200 for both pause (`enabled:false`) and resume (`enabled:true`). The exact
   `serialization_error` (`dataSources[].queryObj.url` → null) is captured verbatim.
2. **Root-cause refinement** — the issue's hypothesis (`enabled:true` read-only-field / null-handling mismatch) was
   *disproven*; the 400 is purely the GET→PUT shape round-trip. Reconciled in the Research Reconciliation table.
3. **Pause step also broken** — discovered the pause step shares the same round-trip and has been silently
   non-functional (400 swallowed by best-effort `exit 0`), making #4596 Option A a no-op. Both steps fixed.
4. **Verb pinned** — PATCH live-tested → 403; PUT is mandatory. Encoded as AC3 + Sharp Edge.

### New Considerations Discovered

- The detectors API treats `PUT {"enabled": <bool>}` as a partial update — no full ProjectMonitorRequest body needed
  (the stale comment claiming otherwise is corrected in Phase 3).
- Fixing the pause step is a real behavior change (the monitor will now genuinely pause during deploys); resume's
  `if: always()` + the fix guarantee re-enable. AC10 confirms `enabled:true` post-deploy.
- Sole fix site: `git grep "jq '.enabled = (true|false)'"` returns only `deploy-docs.yml` lines 213 + 288 — no other
  workflow/script uses the broken round-trip.

### Deepen-plan Gate Results

- **4.4 Precedent-diff:** no sibling minimal-PUT precedent in repo (this is the only `/detectors/` PUT); pattern is
  corrected by the live-verified API contract, documented in Risks. Not a scheduled-job change (no Inngest/cron gate).
- **4.5 Network-outage:** no SSH/connectivity diagnosis in scope (the only `ssh` token is the `(NO ssh)` annotation in
  discoverability_test). Skip.
- **4.6 User-Brand Impact:** present, threshold `aggregate pattern` (valid). Pass.
- **4.7 Observability:** section present, all 5 fields non-empty, `discoverability_test.command` ssh-free. Pass.
- **4.8 PAT-shaped variable:** no matches. Pass.

## Overview

`Deploy Documentation to GitHub Pages` (`.github/workflows/deploy-docs.yml`) fails on every push to `main` at the
post-deploy step **"Probe www→apex 301 then resume soleur_www monitor"**. The Pages build/deploy succeeds; the
failure is the Sentry detector **resume** PUT returning HTTP 400, which `exit 1`s the workflow and may strand the
`soleur-ai-www` uptime monitor paused.

**Root cause (live-reproduced against `jikigai-eu.sentry.io` on 2026-05-29):** the resume/pause steps use a
GET-then-round-trip-PUT pattern: GET the full detector body, set `.enabled = true` (or `false`) with `jq`, PUT the
whole body back. But the Sentry **detectors** API response shape is NOT its request shape. The GET response returns
`dataSources` as an **array** of subscription objects, each with a nested `queryObj`. The PUT serializer expects
`dataSources.assertion.url` to be a **string**. Round-tripping the GET array through PUT produces a `null` `url`,
yielding:

```json
{"dataSources":{"assertion":{"error":"serialization_error",
  "details":"Failed to deserialize the JSON body into the target type: url: invalid type: null, expected a string at line 1 column 67"}}}
```
→ HTTP 400. The 400 has **nothing to do with `enabled`** (the step's own error text guessing at `enabled:null`
null-handling was a red herring).

**Verified fix:** PUT a minimal `{"enabled": true}` (resume) / `{"enabled": false}` (pause) body. Both return **HTTP
200** and correctly transition the detector's `enabled` state. The detectors API treats PUT as a partial update for
the `enabled` field — the full ProjectMonitorRequest body the comment claims is required (lines 205-206) is a stale
assumption inherited from the legacy Crons monitors API; the new detectors API does not need it for an enable/disable
toggle.

This bug exists in **both** the pause step (lines 207-222) and the resume step (lines 282-302) — they share the same
round-trip pattern. The pause step is currently *masked* because pause is best-effort (`exit 0` on any failure), so its
PUT silently 400s and the monitor never actually pauses — meaning the deploy-window false-page suppression (#4596
Option A) has been silently non-functional too. Fixing both restores the intended behavior.

## Research Reconciliation — Spec vs. Codebase

| Spec/issue claim | Reality (live-verified 2026-05-29) | Plan response |
|---|---|---|
| 400 is a payload-shape / read-only-field mismatch on `enabled:true` | 400 is a `serialization_error` on `dataSources[].queryObj` → `url: null`; `enabled` is irrelevant | Strip the round-trip; send minimal `{"enabled": <bool>}`. |
| "the new detectors API differs from the legacy monitors API; `enabled:null` null-handling unverified" | Confirmed different. Minimal `{"enabled":true}` PUT → 200. `enabled` is never null. | Drop the GET-then-PUT entirely for the toggle. |
| Pause step works (records `monitor_id`, pauses monitor) | Pause uses the SAME broken round-trip; its PUT 400s but is swallowed by best-effort `exit 0`. Monitor was never actually paused. | Fix pause step too (same minimal-payload change). |
| MONITOR_ID=1221117 is the `soleur-ai-www` detector | Confirmed: GET `/detectors/1221117/` → `{name:"soleur-ai-www", type:"uptime_domain_failure"}` | n/a |

## Premise Validation

Checked: cited commits `77cde01b`, `d5d7fb12`, `5b61d5b7` all exist on `main` and reproduce identically (pre-existing,
not feature-introduced — confirmed). Sibling commit `a546a798` exists (WIP cf-sentry-iac-apex-canonical, #4578). The
failing run `26638479707` is confirmed `conclusion: failure` on `main`. The detector `/detectors/1221117/` exists and
is the `soleur-ai-www` uptime monitor. Live API probe reproduced the exact 400 and verified the minimal-payload fix
returns 200. Monitor was left `enabled:true` (healthy) after probing. **No stale premises.** One premise was *refined*:
the 400 cause is the `dataSources` round-trip, not `enabled` null-handling.

## CLI / API verification (Research Insights)

All verified live 2026-05-29 against `https://jikigai-eu.sentry.io` with `SENTRY_IAC_AUTH_TOKEN` (org `jikigai-eu`):

```
# REPRODUCE (the bug): round-trip GET body with .enabled=true → 400 serialization_error
PUT /api/0/organizations/jikigai-eu/detectors/1221117/  (body = full GET, .enabled=true)  → 400

# FIX (verified): minimal payload → 200, state transitions correctly
PUT /api/0/organizations/jikigai-eu/detectors/1221117/  -d '{"enabled": true}'   → 200  (enabled→true)
PUT /api/0/organizations/jikigai-eu/detectors/1221117/  -d '{"enabled": false}'  → 200  (enabled→false)

# PATCH is NOT a substitute: returns 403 for this token. Verb MUST stay PUT.
PATCH /api/0/organizations/jikigai-eu/detectors/1221117/ -d '{"enabled": true}'  → 403 (permission denied)
```

`actionlint` 1.7.7 is installed locally (`/home/jean/.local/bin/actionlint`) for AC verification of the workflow YAML.

## Problem / Motivation

- **Main CI is red** on every docs push — noise that erodes the green-main signal and triggers post-merge-verification churn.
- The `soleur-ai-www` uptime monitor can be **left paused** after a deploy (resume 400s, `exit 1`), creating a blind
  spot: a real www→apex redirect regression would not page.
- The deploy-window false-page suppression (#4596 Option A) is **silently non-functional** because the pause PUT also
  400s (swallowed by best-effort). The monitor was never being paused, so any future deploy-window flap can still
  false-page. Fixing pause restores the intended #4596 behavior.

## User-Brand Impact

**If this lands broken, the user experiences:** no direct end-user (alpha-user) artifact — this is an internal CI +
observability surface. The downstream user-facing risk is a *missed* page on a real www→apex regression (the monitor
stays paused or never pauses correctly), delaying detection of a canonicalization outage that would surface to users as
a broken `www.soleur.ai` redirect.

**If this leaks, the user's data/workflow/money is exposed via:** N/A — no user data, auth, or PII surface. The
`SENTRY_IAC_AUTH_TOKEN` is the only secret touched and is already gated to the workflow's secret scope (no change to
its handling).

**Brand-survival threshold:** `aggregate pattern` — a single failed resume does not damage the brand; the risk is an
aggregate observability-decay pattern (monitor repeatedly stranded → www regression goes unpaged). No per-PR CPO
sign-off required.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 — Resume step minimal payload.** `deploy-docs.yml`'s resume step builds the PUT body as the literal
      `{"enabled": true}` (no GET-then-`jq '.enabled = true'` round-trip). Verify:
      `grep -n 'enabled.*:.*true' .github/workflows/deploy-docs.yml` shows the minimal body, and
      `grep -c 'jq .* .enabled = true' .github/workflows/deploy-docs.yml` returns `0` (round-trip removed).
- [ ] **AC2 — Pause step minimal payload.** The pause step builds the PUT body as `{"enabled": false}` (no
      round-trip). Verify `grep -c "jq '.enabled = false'" .github/workflows/deploy-docs.yml` returns `0`.
- [ ] **AC3 — Verb stays PUT.** Both steps use `curl ... -X PUT` (NOT PATCH — PATCH returns 403 for the IaC token).
      Verify `grep -c '\-X PUT' .github/workflows/deploy-docs.yml` returns `2` and `grep -c '\-X PATCH'` returns `0`.
- [ ] **AC4 — Resume still GETs nothing it does not need.** The resume step no longer issues the pre-PUT
      `GET /detectors/{id}/` solely to round-trip it. (The pause step's *list* GET to discover the id stays; the
      *single-detector* GET that fed the round-trip is removed in both steps.) Verify by reading the step bodies — no
      `full=$(curl ... /detectors/${...}/)` immediately preceding the toggle PUT.
- [ ] **AC5 — Resume fail-loud preserved.** A non-200 resume PUT still `exit 1`s with the actionable `::error::`
      message (stranded-paused is worse than red workflow). The HTTP-status check (`if [[ "$http" != "200" ]]`) and the
      `::error::` line are retained.
- [ ] **AC6 — Pause best-effort preserved.** A non-200 pause PUT still warns and `exit 0`s (a Sentry blip must never
      block a docs deploy). The `::warning::` + record-`monitor_id`-regardless behavior is retained.
- [ ] **AC7 — Stale-comment correction.** The misleading comment at lines 205-206 ("Full-body GET-then-PUT:
      updateProjectMonitor requires the full ProjectMonitorRequest; a bare {"enabled":false} PUT risks a 400.") is
      replaced with the corrected note: the detectors API accepts a minimal `{enabled}` PUT (200), and the full-body
      round-trip is what *caused* the 400 (`dataSources[].queryObj.url` → null serialization_error). Cite #4618.
- [ ] **AC8 — Workflow YAML lints clean.** `actionlint .github/workflows/deploy-docs.yml` exits 0. Embedded `run:`
      shell for the two edited steps passes `bash -n` (extract the snippet; do NOT run `bash -n` on the whole `.yml`).

### Post-merge (operator → automated where feasible)

- [ ] **AC9 — Workflow goes green.** The next push to `main` touching the docs surface runs `deploy-docs.yml` to
      success (resume step prints `resume PUT status: 200`). **Automation:** `gh run watch` / `gh run list --workflow
      deploy-docs.yml --limit 1 --json conclusion` in `/soleur:ship` post-merge verification — NOT operator
      dashboard-watching.
- [ ] **AC10 — Detector confirmed enabled after deploy.** After a deploy completes, GET
      `/api/0/organizations/jikigai-eu/detectors/1221117/` returns `enabled: true`. **Automation:** single `curl ... |
      jq '.enabled'` call (read-only) in ship post-merge verification, using `SENTRY_IAC_AUTH_TOKEN` from Doppler
      `prd`. Deterministic verdict: `enabled == true` → pass.

## Implementation Phases

> NEVER CODE happens here at plan time. /work implements. TDD note: workflow `run:` bash is not unit-testable in the
> repo's test runner; the verification gate is `actionlint` + `bash -n` on extracted snippets + the live post-merge
> probe (AC9/AC10). There is no RED test to write first; the "failing test" is the reproduced live 400 (already
> captured in Research Insights).

### Phase 1 — Fix the resume step (lines 282-302)

Replace the GET-then-round-trip-PUT with a minimal-payload PUT.

`.github/workflows/deploy-docs.yml` — resume step `run:` block:

```bash
# BEFORE (broken):
#   full=$(curl -sS ... "/detectors/${MONITOR_ID}/") || { ...exit 1; }
#   body=$(jq '.enabled = true' <<<"$full" ...) || { ...exit 1; }
#   http=$(curl -sS -X PUT ... -d "$body" "/detectors/${MONITOR_ID}/" ...)
#
# AFTER (verified 200): no pre-PUT GET, no round-trip; minimal payload.
http=$(curl -sS --max-time 20 -X PUT \
  -H "Authorization: Bearer ${SENTRY_AUTH_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"enabled": true}' \
  "https://${SENTRY_API_HOST}/api/0/organizations/${SENTRY_ORG}/detectors/${MONITOR_ID}/" \
  -o /dev/null -w '%{http_code}')
echo "resume PUT status: ${http}"
if [[ "$http" != "200" ]]; then
  echo "::error::Failed to resume soleur-ai-www monitor (HTTP ${http}). It may remain paused until manually re-enabled or a deploy-docs.yml re-run."
  exit 1
fi
echo "Resumed soleur-ai-www detector ${MONITOR_ID}."
```

- Keep the `jq` install line (the pause step's list-select still uses `jq`; resume keeps it for parity / no-harm).
- Keep the `MONITOR_ID` empty-guard (`if [[ -z "${MONITOR_ID}" ]]; then ...exit 0`) — resume only runs when pause
  captured an id.
- Keep the probe loop (www→apex 301 confirming) and `if: always()`.
- The corrected `::error::` line drops the now-false "enabled:null null-handling is unverified" tail (AC5/AC7).

### Phase 2 — Fix the pause step (lines 207-222)

Same change, `enabled: false`.

`.github/workflows/deploy-docs.yml` — pause step `run:` block:

```bash
# AFTER: minimal payload, no round-trip.
status=$(curl -sS --max-time 20 -X PUT \
  -H "Authorization: Bearer ${SENTRY_AUTH_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"enabled": false}' \
  "https://${SENTRY_API_HOST}/api/0/organizations/${SENTRY_ORG}/detectors/${id}/" \
  -o /dev/null -w '%{http_code}')
echo "pause PUT status: ${status}"
echo "monitor_id=${id}" >> "$GITHUB_OUTPUT"   # record regardless (resume is idempotent)
if [[ "$status" != "200" ]]; then
  echo "::warning::Pause PUT returned ${status} (expected 200); monitor may not be paused. Deploy continues; resume still runs."
else
  echo "Paused soleur-ai-www detector ${id}."
fi
```

- Keep the list GET (`detectors=$(curl ... /detectors/)`) and the `jq` select-by-name-AND-uptime-type id resolution —
  that GET is correct and necessary to discover the id.
- Remove ONLY the single-detector `full=$(curl ... /detectors/${id}/)` GET and the `body=$(jq '.enabled = false' ...)`
  round-trip.
- Preserve best-effort semantics (warn + `exit 0` on any non-200; `set -uo pipefail` unchanged).

### Phase 3 — Correct the stale comment (lines 205-206)

Replace:
```
# Full-body GET-then-PUT: updateProjectMonitor requires the full
# ProjectMonitorRequest; a bare {"enabled":false} PUT risks a 400.
```
with:
```
# Minimal-payload PUT: the Sentry detectors API accepts a bare {"enabled":<bool>}
# body and returns 200 (verified #4618). The OLD full-body GET-then-PUT round-trip
# is what CAUSED the 400 — the GET response shape (dataSources[].queryObj) is NOT
# the PUT request shape, so the round-trip serializes dataSources.assertion.url as
# null → serialization_error. Verb MUST be PUT (PATCH returns 403 for the IaC token).
```

### Phase 4 — Verify

- `actionlint .github/workflows/deploy-docs.yml` → exit 0 (AC8).
- Extract each edited `run:` block and `bash -n` it (NOT `bash -n` on the `.yml` — that parses YAML as bash).
- Run all AC1-AC8 greps.

## Files to Edit

- `.github/workflows/deploy-docs.yml` — pause step (lines ~207-222), resume step (lines ~282-302), comment (lines
  205-206). Single file.

## Files to Create

- None.

## Open Code-Review Overlap

1 open code-review issue touches `deploy-docs.yml`:
- **#2965** (review: evaluate build-time critical-CSS extractor for Eleventy docs) — **Acknowledge.** Different concern
  (critical-CSS extraction strategy, not the Sentry resume step). This plan does not touch the screenshot-gate /
  critical-CSS steps. #2965 remains open.

## Observability

This is a `.github/workflows/*.yml` change — NOT under `apps/*/server`, `apps/*/src`, `apps/*/infra`, or
`plugins/*/scripts`, and it introduces no new infrastructure surface. Per Phase 2.9, the 5-field Observability schema
is **skip-eligible** (no code-class file under the trigger paths). However, because the change *restores* an
observability primitive (the uptime monitor's enabled state), the operative observability is the workflow's own
liveness:

- **liveness_signal:** `deploy-docs.yml` run status on push-to-`main` / per docs-surface push / GitHub Actions run
  conclusion / configured in `.github/workflows/deploy-docs.yml`. Green run = resume succeeded.
- **error_reporting:** the resume step's `::error::` annotation + non-zero exit (fail-loud, retained — AC5). A red
  workflow is the signal.
- **failure_modes:** {resume PUT non-200 → `exit 1` + `::error::` → red workflow}; {pause PUT non-200 → `::warning::`,
  deploy continues (best-effort)}; {monitor stranded disabled → caught by AC10 post-deploy `enabled` probe}.
- **logs:** GitHub Actions run logs (`gh run view <id> --log`), 90-day retention.
- **discoverability_test:** `gh run list --workflow deploy-docs.yml --limit 1 --json conclusion` (NO ssh) → expected
  `"conclusion": "success"`; and `curl -sS -H "Authorization: Bearer $TOK" ".../detectors/1221117/" | jq '.enabled'` →
  expected `true`.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — CI/observability tooling change. No user-facing UI, no schema/auth/API
(application) surface, no legal/marketing/sales/finance/support implication. Product domain: NONE (no user-facing
surface). Skipping Product/UX Gate.

## Infrastructure (IaC)

Skip — no new infrastructure. The Sentry uptime detector already exists (codified in
`apps/web-platform/infra/sentry/uptime-monitors.tf`, auto-applied via `apply-sentry-infra.yml`). This change only fixes
how an existing CI workflow toggles the detector's `enabled` flag via the Sentry API — no new server, secret, vendor,
DNS, cert, or persistent process. The `enabled` toggle is a runtime operational mutation (pause/resume around a deploy
window), intentionally NOT Terraform-managed (Terraform would fight the transient pause; the TF resource owns the
detector's *definition*, the workflow owns its *transient enabled-state during deploys*).

## Risks & Mitigations

- **Risk: detectors API changes the minimal-payload contract on a future Sentry release** (the resource is
  provider-beta, `sentry_uptime_monitor` v0.15.0-beta2). *Mitigation:* the resume step is fail-loud (AC5) — a contract
  break surfaces as a red workflow immediately, not a silent strand. AC10's post-deploy `enabled` probe is the
  drift-resilience backstop.
- **Risk: removing the round-trip GET drops some field the PUT needs.** *Mitigation:* live-verified — the minimal
  `{"enabled": <bool>}` PUT returns 200 and the GET afterward confirms only `enabled` changed; all other fields
  (`dataSources`, `conditionGroup`, `config`, `assertion`) are untouched server-side. The detectors API treats the
  enable toggle as a partial update.
- **Risk: verb confusion (PATCH vs PUT).** *Mitigation:* AC3 pins PUT; PATCH was live-tested and returns 403 for the
  IaC token — encoded as a Sharp Edge.
- **Risk: pause step now actually pauses (it never did before due to the swallowed 400).** This is the *intended*
  #4596-Option-A behavior, but it is a behavior *change* (the monitor will genuinely be disabled during the deploy
  window now). *Mitigation:* resume runs `if: always()` and is now also fixed, so the monitor is reliably re-enabled
  even on a failed deploy. AC10 confirms `enabled:true` post-deploy. The pause window is bounded by the deploy +
  probe-loop duration (≤ ~15 min cap).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the
  threshold will fail `deepen-plan` Phase 4.6. (Section is filled above; threshold = `aggregate pattern`.)
- **The Sentry detectors API GET body is NOT its PUT body.** GET returns `dataSources` as an array of subscription
  objects with nested `queryObj`; PUT expects `dataSources.assertion.url` as a string. Round-tripping GET→PUT
  serializes `url` as null → `serialization_error` → HTTP 400. For an enable/disable toggle, send ONLY
  `{"enabled": <bool>}`. (This is the bug; do not reintroduce the round-trip.)
- **Verb must be `PUT`, not `PATCH`.** `PATCH /detectors/{id}/` with the `SENTRY_IAC_AUTH_TOKEN` returns 403
  (permission denied). PUT with the minimal body returns 200.
- **`bash -n` on a `.github/workflows/*.yml` file parses the YAML header as bash** and reports false errors. Validate
  the workflow with `actionlint`; validate embedded `run:` shell by extracting the snippet and `bash -c '...'` /
  `bash -n` on the snippet only. (See AGENTS.md learning `2026-05-11-multi-word-required-check-exposes-strip-all-whitespace-bug`.)
- **The pause step was silently non-functional** (its 400 was swallowed by best-effort `exit 0`). Fixing it changes
  real behavior — the monitor will now actually pause during deploys. This is intended (#4596 Option A), but verify the
  resume reliably re-enables (AC10) so the monitor is never left disabled.

## Test Scenarios

1. **Resume happy path:** deploy completes → resume PUT `{"enabled": true}` → 200 → `enabled:true`. (Live-verified.)
2. **Pause happy path:** pause PUT `{"enabled": false}` → 200 → `enabled:false`. (Live-verified.)
3. **Resume failure path:** resume PUT non-200 → `::error::` + `exit 1` → red workflow (fail-loud retained).
4. **Pause failure path:** pause PUT non-200 → `::warning::` + record id + `exit 0` (deploy continues).
5. **No-id path:** pause skips (detector not found) → `monitor_id` empty → resume `exit 0` ("nothing to resume").
6. **actionlint:** `actionlint .github/workflows/deploy-docs.yml` → exit 0.

## Related

- Issue #4618 (this fix). Use `Closes #4618` in the PR body (the fix is pre-merge code, not a post-merge ops remediation).
- #4591 — established that uptime monitors are `/detectors/`, not Crons `/monitors/` (the endpoint this step correctly
  uses).
- #4596 (Option A) — the pause/resume-around-deploy design this fix makes actually functional.
- #4577 / a546a798 (#4578) — the www→apex apex-canonical reconcile context.
- `apps/web-platform/infra/sentry/uptime-monitors.tf` — the `soleur_www` (`soleur-ai-www`) detector definition.
- Learning: `knowledge-base/project/learnings/integration-issues/2026-04-29-supabase-auth-probe-and-sentry-rule-api-quirks.md` (Sentry API request/response shape quirks).
