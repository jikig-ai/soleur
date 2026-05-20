---
title: feat(drift-guard) — diff installation-grant permissions vs manifest (post-#4173 follow-up)
type: feat
date: 2026-05-20
issue: 4179
lane: single-domain
requires_cpo_signoff: true
brand_survival_threshold: single-user incident
related_issues: [4173, 4115, 4136, 4137, 4144, 3187]
related_prs: [4174, 4121]
---

# feat(drift-guard): diff installation-grant permissions vs manifest (post-#4173 follow-up)

## Enhancement Summary

**Deepened on:** 2026-05-20
**Sections enhanced:** 4 (Proposed Solution, Sharp Edges, Acceptance Criteria, Test Scenarios)
**Research probes used:**
- Live `gh api /orgs/jikig-ai/installations` (shape verification)
- `@octokit/openapi-types/types.d.ts:85507-85530` (canonical schema for `apps/list-installations`)
- `https://docs.github.com/en/rest/apps/apps#list-installations-for-the-authenticated-app` (auth + pagination)
- `https://docs.github.com/en/rest/orgs/orgs#list-app-installations-for-an-organization` (rejected endpoint cross-check)
- `.github/workflows/scheduled-ruleset-bypass-audit.yml:328` (sibling workflow endpoint precedent)
- AGENTS.md gates (Phase 4.6/4.7/4.8 all PASS at plan-write time)

### Key Improvements (caught at deepen-pass, pre-/work)

1. **Endpoint-shape mismatch caught.** Plan v1 prescribed `jq -c '.installations[]'` (wrapper-style) for `GET /app/installations`. The official OpenAPI schema at `apps/web-platform/node_modules/@octokit/openapi-types/types.d.ts:85517-85528` is a **flat array** under `application/json` — the wrapper-style jq would return zero iterations against a real response, silently bypassing the per-install diff. Correct form is `jq -c '.[]'` (no `.installations` key). The `/orgs/{org}/installations` endpoint IS wrapper-style — the plan was mixing shapes. Now corrected and locked via an AC + explicit Sharp Edge.
2. **Pagination (Link header) acknowledged.** `GET /app/installations` defaults to `per_page=30`, max `100`. Future-proofs against >30 installations (currently 1). Plan now prescribes `?per_page=100` in the URL plus a Link-header presence check that records `installation_list_truncated` as a `ci/guard-broken` mode rather than silently iterating only the first page.
3. **`response_shape_unparseable` mode lined up.** Mode name in the per-install diff loop already matches the existing diff script's vocabulary; documented as REUSED, not relabeled.
4. **Sister-workflow precedent confirmed.** `scheduled-ruleset-bypass-audit.yml:109,299,328` already mints installation tokens against `/app/installations/{id}/access_tokens` using the same JWT pattern. The plan's endpoint choice is consistent with the existing precedent.
5. **Fold-in #3561 (`tr -d '\x7f'`) confirmed orthogonal.** The new failure-mode strings (`installation_permission_drift` etc.) DO contain `f` (`installation_permissi_on_dri{f}t`, `installation_response_shape_unparseable`'s `_unparseable`) — a literal `f` would silently be dropped from sanitized stdout when the mode is echoed to `$GITHUB_OUTPUT`. The bug DOES manifest against the new modes. **Fold-in is now load-bearing, not opportunistic.** Updated risk R4 from "medium → low w/ fold-in" to "P1 must-fix".

### New Considerations Discovered

- **Plan v1's "no test fixture changes" claim was incomplete.** The contract test stays unchanged for the EXISTING 7 cases (script is unmodified). The plan adds ONE new case for the workflow's per-installation synthesis pattern (covered as AC10). Phrasing in §Proposed Solution updated.
- **The `MANIFEST_DRIFT_SUPPRESS_UNTIL` is currently active (`2026-05-21T16:00:00Z`).** This means the first scheduled run AFTER merge but BEFORE 2026-05-21T16:00:00Z will silently suppress BOTH diffs (a-vs-b AND c-vs-b). Operator action item: extend the suppress file's expiry by 24h if PR merges within 24h of plan-write time, OR delete it post-merge to force immediate verification. Added to Post-merge AC list.
- **`installation_unexpected_grant` is the **easier synthetic** for AC19** because plane-(c) drift "live has Y, manifest doesn't" can be produced by deleting a key from the committed manifest (no UI click required). The inverse direction "manifest declares X, live lacks X" requires the operator to NOT re-accept after a manifest add — much harder to synthesize. Plan clarifies which direction the synthetic test should use.

## Overview

Extend `.github/workflows/scheduled-github-app-drift-guard.yml` to diff the
**installation-level** permission grant against the committed manifest, closing
the three-plane drift gap that produced incident #4173. Reuse the existing
`bin/diff-github-app-manifest.sh` shared diff script verbatim — the script's
input contract (`{permissions, events}` shape) already matches the
per-installation object returned by `GET /app/installations`. Net diff is one
new YAML block (~50 LoC) inside the existing `check` step + one new test case
class in the existing contract test + runbook + tf-comment updates. No new
script files, no new workflows, no new secrets.

## Problem Statement / Motivation

GitHub Apps have **three independent permission planes** that can drift
silently. Per the learning at
`knowledge-base/project/learnings/2026-05-20-github-app-installation-grant-vs-manifest-three-plane-drift.md`:

| Plane | Source of truth | API endpoint | Read by current cron? |
|-------|-----------------|--------------|------------------------|
| (a) App-level declaration | App settings page | `GET /app` | YES |
| (b) Committed manifest JSON | `apps/web-platform/infra/github-app-manifest.json` | (file) | YES |
| (c) Installation-level grant | Per-installation settings | `GET /app/installations` | **NO** |

The cron compares (a) vs (b). Terraform apply uses the **installation token**
derived from (c). At #4173 incident time:

- (a) declared 8 permissions including `secrets:write`
- (b) declared 7 (no `secrets`)
- (c) granted 7 (no `secrets`)

The cron stayed green throughout because plane (c) was invisible. The actual
runtime fault — `apply-web-platform-infra.yml` 403'ing on
`actions/secrets/public-key` — went undetected by the standing primitive that
exists precisely to catch this class.

Two independent reviewers concurred at PR #4173 review time:

- `security-sentinel` (P1): "the very class of drift this PR remediates is
  undetected by the cron the PR claims is the standing detection primitive"
- `architecture-strategist` (HIGH): "the structural detection gap remains
  undetected by automation post-merge"

`apps/web-platform/infra/github-app.tf:24-30` explicitly names this issue
(#4179) as the remediation:

> Drift-guard at scheduled-github-app-drift-guard.yml detects
> App-declared-vs-manifest divergence; installation-grant-vs-manifest
> divergence (the class that produced #4173) is tracked in #4179 as a
> drift-guard extension.

The brainstorm at
`knowledge-base/project/brainstorms/2026-05-05-github-app-drift-guard-brainstorm.md:149-151`
also explicitly named installation-level guard as out-of-scope-for-v1, deferred
to a separate concern. This issue IS that concern.

## Proposed Solution

Add a fourth diff block inside the `check` step (between the existing
App-level manifest diff at YAML:280-356 and the `strip_log_injection` block at
YAML:366), guarded by the same `MANIFEST_DRIFT_SUPPRESS_UNTIL` suppression
logic that the existing diff already honors.

Pseudocode (corrected at deepen-pass — note `jq -c '.[]'` against a FLAT
ARRAY, `per_page=100`, and Link-header truncation check):

```bash
# After App-level manifest diff completes successfully...
if [[ -z "$failure_mode" && -n "${JWT:-}" && -f "$MANIFEST_FILE" && \
      "$suppress_active" -eq 0 ]]; then
  INSTALL_LIST_FILE=$(mktemp -p "$RUNNER_TEMP" installations.XXXXXX)
  INSTALL_HEADERS_FILE=$(mktemp -p "$RUNNER_TEMP" installations-hdr.XXXXXX)
  HTTP_CODE=$(curl -s --max-time 15 -w '%{http_code}' \
    -o "$INSTALL_LIST_FILE" \
    -D "$INSTALL_HEADERS_FILE" \
    -H 'Accept: application/vnd.github+json' \
    -H 'X-GitHub-Api-Version: 2022-11-28' \
    --header @<(printf 'Authorization: Bearer %s' "$JWT") \
    'https://api.github.com/app/installations?per_page=100') \
    || HTTP_CODE="network_error"

  # HTTP routing (matches the /app call's pattern at YAML:235-254).
  if [[ "$HTTP_CODE" == "network_error" || "$HTTP_CODE" != "200" ]]; then
    record_failure installation_api_http \
      "GET /app/installations -> HTTP ${HTTP_CODE}" ci/guard-broken
  # Pagination check: if Link: <...>; rel="next" present, the loop would
  # silently miss installations past page 1. Today's 1-install state can't
  # paginate, but installations is unbounded over time.
  elif grep -qiE '^link:.*rel="next"' "$INSTALL_HEADERS_FILE"; then
    record_failure installation_list_truncated \
      "GET /app/installations returned a paginated response (Link: rel=next present); per-page bump or pagination loop required" \
      ci/guard-broken
  # FLAT ARRAY (per @octokit/openapi-types/types.d.ts:85517-85528 — NOT
  # object-wrapped like /orgs/{org}/installations).
  elif [[ "$(jq -r '. | type' "$INSTALL_LIST_FILE" 2>/dev/null)" != "array" ]]; then
    record_failure installation_response_shape_unparseable \
      "GET /app/installations response root is not an array" ci/guard-broken
  else
    while IFS= read -r install_json; do
      INSTALL_RESP_FILE=$(mktemp -p "$RUNNER_TEMP" install-resp.XXXXXX)
      printf '%s' "$install_json" \
        | jq -c '{permissions, events}' > "$INSTALL_RESP_FILE"
      install_id=$(printf '%s' "$install_json" | jq -r '.id // "unknown"')

      diff_out=""
      diff_rc=0
      diff_out=$(MANIFEST_FILE="$MANIFEST_FILE" RESPONSE_FILE="$INSTALL_RESP_FILE" \
        bash bin/diff-github-app-manifest.sh 2>/dev/null) || diff_rc=$?

      if (( diff_rc != 0 )); then
        diff_mode="${diff_out%%:*}"
        diff_detail="${diff_out#*:}"
        case "$diff_mode" in
          permission_drift)
            record_failure installation_permission_drift \
              "installation_id=${install_id} ${diff_detail}" \
              ci/auth-broken
            ;;
          permission_unexpected_grant)
            record_failure installation_unexpected_grant \
              "installation_id=${install_id} ${diff_detail}" \
              ci/guard-broken
            ;;
          response_shape_unparseable)
            # Should never fire here — synthesis always produces a valid shape.
            # If it does, the bug is in synthesis; route as guard-broken.
            record_failure installation_response_shape_unparseable \
              "installation_id=${install_id} ${diff_detail}" \
              ci/guard-broken
            ;;
          *)
            record_failure installation_diff_unknown_mode \
              "installation_id=${install_id} diff_rc=${diff_rc} out=${diff_out}" \
              ci/guard-broken
            ;;
        esac
      fi
    done < <(jq -c '.[]' "$INSTALL_LIST_FILE")
  fi
fi
```

Endpoint-shape verification (canonical evidence):

```bash
$ grep -nB1 -A 5 '"/app/installations":' \
    apps/web-platform/node_modules/@octokit/openapi-types/types.d.ts
107: "/app/installations": {
108:   /** List installations for the authenticated app
109:    *  You must use a JWT to access this endpoint. */
114:   get: operations["apps/list-installations"];

$ sed -n '85517,85528p' apps/web-platform/node_modules/@octokit/openapi-types/types.d.ts
# response 200 → application/json → bare object with `id: number` at root
# (i.e., element type, not wrapper). Hence `jq '. | type' == "array"`,
# `jq '.[]'`, not `jq '.installations[]'`.
```

The suppression window applies identically — a manifest-edit PR triggers a
window during which BOTH plane (a) reconciliation (semi-automatic via App
settings) AND plane (c) re-acceptance (operator UI click per `runbook Step 2.1`)
are expected to complete out-of-band.

**Endpoint choice rationale (corrected at deepen-pass).** Issue body suggests
`GET /orgs/{org}/installations` (PAT/OAuth admin:read scope required, per the
official docs cross-checked at deepen-pass). The plan uses
`GET /app/installations?per_page=100` instead because:

1. It accepts the App-JWT the guard already mints — no new auth primitive, no
   new secret, no new scope question. Per AGENTS.md `hr-github-app-auth-not-pat`,
   adding a PAT-shaped variable to bypass the App is a hard-no.
2. It returns ALL installations of THIS App (across any future target org/user),
   not just `jikig-ai` — future-proofs against multi-tenant install.
3. Sister workflow `.github/workflows/scheduled-ruleset-bypass-audit.yml:328`
   already uses App-JWT against `/app/installations/{id}/access_tokens` — same
   auth primitive, same plumbing pattern, same masking discipline.

**Endpoint-shape WARNING (caught at deepen-pass).** The two endpoints have
DIFFERENT response shapes:

- `GET /orgs/{org}/installations` → object-wrapped: `{total_count, installations:[…]}`
- `GET /app/installations` → **flat array**: `[…]` (per the canonical OpenAPI
  schema at `apps/web-platform/node_modules/@octokit/openapi-types/types.d.ts:85507-85530`)

Plan v1 conflated the two. The pseudocode above uses `jq '. | type' == "array"`
for shape validation and `jq -c '.[]'` for iteration — correct for
`/app/installations`. Any later edit that flips back to `'.installations[]'`
will silently iterate zero times.

**Pagination handled.** GitHub defaults `per_page=30`, max 100. The new URL
pins `?per_page=100`. With current 1-installation state, no Link header
appears. The new `installation_list_truncated` failure mode fires only if a
future state introduces a second page (>100 installations); routed to
`ci/guard-broken` rather than silently iterating only page 1.

**Live shape verification at plan-write time** (against `gh api
/orgs/jikig-ai/installations` — this is the OBJECT-WRAPPED endpoint used for
read-only state inspection; the workflow itself uses the FLAT-ARRAY
`/app/installations` endpoint above):

```json
{
  "installations": [{
    "id": 122213433,
    "app_slug": "soleur-ai",
    "permissions": {"checks":"read","actions":"write","members":"read",
                    "secrets":"write","contents":"write","metadata":"read",
                    "pull_requests":"write","administration":"write"},
    "events": []
  }]
}
```

8 keys; matches the post-#4173 committed manifest exactly. Confirms no false-
positive surface at first scheduled run.

## Technical Considerations

### Architecture impacts

- Single-file workflow extension. No new script, no new test file, no new
  composite action. Diff-script contract preserved (input shape unchanged).
- Three new failure mode strings (`installation_permission_drift`,
  `installation_unexpected_grant`, `installation_response_shape_unparseable`)
  + one HTTP failure mode (`installation_api_http`). All route via the
  existing `record_failure` allowlist — extend the allowlist case statement at
  YAML:113-119 to accept the new modes (or rely on the existing two-label
  routing — `ci/auth-broken` and `ci/guard-broken` — which are unchanged).
- Issue-filing step at YAML:452-513 already keys on `FAILURE_LABEL`, not on
  `FAILURE_MODE` — the existing two-label set covers the new modes without
  edit. The `FAILURE_DETAIL` body string carries the mode name so triagers see
  `installation_permission_drift` vs `permission_drift` in the issue body and
  can distinguish plane.

### Performance implications

- One additional HTTP call per cron tick (`GET /app/installations`). Hourly
  cron — well below GitHub's per-App rate limit (5000 req/hr per App
  per `https://docs.github.com/en/rest/overview/resources-in-the-rest-api`).
- Wall clock budget: existing step has `timeout-minutes: 5`; one additional
  HTTP call + N small jq invocations (N = installations of this App, currently 1)
  adds ~1-3 seconds.

### Security considerations

- Reuses the existing App-JWT (10-min lifetime, masked at mint time). No new
  PEM read, no new credential surface.
- Same leak tripwire at YAML:387-450 already covers the new code path — any
  accidental JWT echo through the new curl call would trigger the post-step
  grep.
- `INSTALL_LIST_FILE` and per-install response files written under
  `$RUNNER_TEMP` mode 0o600 (umask 077 already set at YAML:184). Cleanup step
  at YAML:553-561 already globs `$RUNNER_TEMP/app-response.*` — extend the
  glob to also cover `$RUNNER_TEMP/installations.*` and
  `$RUNNER_TEMP/install-resp.*`.

### NFR impacts

- **Detectability** (NFR-OBS): closes a documented gap — the runtime fault
  class that produced #4173 becomes detected within ≤1 hour (cron cadence).
- **Self-silent-failure surface** (NFR-CORRECT): adds defensive checks
  mirroring the existing patterns. Specifically: response-shape validation
  BEFORE per-installation iteration (catches GitHub API incident shapes like
  `{"message":"Not Found"}`), `installations` array presence check, defensive
  re-invoke of the diff script against `${RESPONSE_FILE:-}` empty.
- **Brand-survival** (NFR-BRAND): the existing primitive is the GDPR Art 33
  72h-clock survival mechanism for the App identity surface; this extension
  closes a structural gap in that mechanism — same regulatory framing.

### Sharp Edges

- **bash fifo trap (PR #4173 Session Error 2).** Process substitution
  `<(gh api ...)` against `bin/diff-github-app-manifest.sh` fails because the
  script reads `$RESPONSE_FILE` twice (response-shape check + permissions
  diff). The plan MUST use `mktemp` files, never `<(...)`. See
  `knowledge-base/project/learnings/2026-05-20-github-app-installation-grant-vs-manifest-three-plane-drift.md`
  Session Error 2.

- **Endpoint-shape (caught at deepen-pass).** `GET /app/installations` is a
  **flat array**, NOT object-wrapped. The plan-time iteration uses `jq -c
  '.[]'` (no `.installations` key). A future edit that flips to
  `'.installations[]'` will silently iterate zero times AND silently pass the
  shape-validation check above (because the wrong jq would also return
  `null`, which `jq -r '. | type'` reports as `"null"` — not `"array"` — and
  the shape validator catches it). The canonical reference is
  `apps/web-platform/node_modules/@octokit/openapi-types/types.d.ts:85507-85530`
  AND the OpenAPI docs at
  `https://docs.github.com/en/rest/apps/apps#list-installations-for-the-authenticated-app`.
  Symmetric to but distinct from the `/orgs/{org}/installations` endpoint
  (object-wrapped) used for read-only operator inspection.

- **`installations` array iteration in bash.** `jq -c '.[]'` emits one JSON
  object per line; bash `while IFS= read -r install_json` consumes them
  safely (no need for `mapfile`). Each iteration writes a synthetic per-install
  file matching the diff-script's `{permissions, events}` contract via
  `printf '%s' "$install_json" | jq -c '{permissions, events}' >
  "$INSTALL_RESP_FILE"`.

- **Pagination via Link header.** GitHub defaults `per_page=30`, max 100. The
  URL pins `?per_page=100`. Curl's `-D <file>` dumps response headers; a
  `Link:` header with `rel="next"` indicates truncation, which fires
  `installation_list_truncated` → `ci/guard-broken`. Today (1 install) this
  cannot trigger; the gate exists because installations is unbounded over
  time. **Do NOT replace this with a pagination loop** — extending the cron
  step to handle multiple pages adds complexity disproportionate to current
  state, and the explicit failure is more reviewable than a silent loop.

- **`tr -d '\x7f'` interaction with new failure-mode strings (caught at
  deepen-pass).** The fold-in of #3561 is **load-bearing**, not opportunistic.
  The new mode strings `installation_permission_drift`,
  `installation_unexpected_grant`, `installation_response_shape_unparseable`,
  `installation_list_truncated`, `installation_api_http`,
  `installation_diff_unknown_mode` all contain the letter `f` (`drift`,
  `installation_*`). The current `tr -d '\r\n\f\v\x7f'` interprets `\x7f` as
  literal chars `x`, `7`, `f` — silently stripping every `f` from the
  sanitized output that lands in `$GITHUB_OUTPUT.failure_mode`. Issue body
  would show `installation_permission_drit`, `installation_unexpected_grant`
  (no `f`, looks fine), `installation_response_shape_unparseable` (no `f`,
  looks fine), `installation_diff_unknown_mode` → `installation_di_unknown_mode`.
  Operator triage breaks because the mode names disagree with code and with
  any future grep against the workflow source. **MUST replace `\x7f` with
  `\177` (octal) in the same PR.**

- **First-fail-wins vs all-fails-collected.** The existing `record_failure`
  function only records the FIRST failure mode (`if [[ -z "$failure_mode" ]]`).
  This means a per-installation loop that emits multiple failures will report
  only the first. Acceptable because (a) the App currently has 1 installation,
  (b) the issue body includes the App-level failure detail and operator can
  read the run log for the full set, (c) extending `record_failure` to a
  list-collector would touch a load-bearing primitive used by every existing
  failure path. Document in a code comment; defer multi-fail collection to a
  follow-up if multi-installation lands.

- **Per-installation diff script invocation: cwd contract.** The existing
  diff script call at YAML:333-334 sets `MANIFEST_FILE` to the committed
  manifest path (relative to repo root). The workflow's `Checkout` step at
  YAML:64-71 already sparse-checks out `apps/web-platform/infra/github-app-manifest.json`
  and `bin/diff-github-app-manifest.sh`. New code paths reuse these paths
  verbatim — no checkout change.

- **Test fixture: `installations.[0].permissions` vs the existing
  `.permissions` test fixture shape.** The contract test at
  `apps/web-platform/test/github-app-manifest-drift-guard.test.ts` mocks
  `$RESPONSE_FILE` directly with `{permissions, events}`. The plan does NOT
  change the script's input contract — only the workflow extracts each
  installation's `{permissions, events}` and writes it to a per-install file
  matching the existing shape. The contract test stays as-is for the existing
  `permission_drift` / `permission_unexpected_grant` / `response_shape_unparseable`
  modes; a new case is added for "the workflow's synthetic per-install file
  matches the contract" — see Test Scenarios.

## Research Reconciliation — Spec vs. Codebase

| Issue body claim | Codebase reality | Plan response |
|------------------|-------------------|---------------|
| Use `GET /orgs/jikig-ai/installations` (PAT) | `GET /app/installations` (App-JWT) returns identical per-install shape and reuses the JWT the guard already mints | Use `/app/installations` — see Endpoint choice rationale |
| "Re-tag the script's output modes with installation-specific labels" | The script's output is `<mode>:<details>` to stdout; the workflow YAML case statement at :341-353 maps modes to labels. The script itself never sees the labels. | Re-tag is done in YAML, not in the script. Script stays read-only. |
| "~50 lines of workflow YAML" | Confirmed by pseudocode walk: ~50 LoC for the new block, +6 LoC to extend `record_failure` allowlist and cleanup glob | Accurate estimate |
| "no test fixture changes" | The contract test's existing 7 cases stay valid because the script is unchanged. The workflow's per-install synthesis logic needs ITS OWN test path (1 new case in the same file). | One new contract test case for the synthesis path — clarify "no script test changes; one new workflow-synthesis test case." |
| "MANIFEST_DRIFT_SUPPRESS_UNTIL should apply identically" | Confirmed at YAML:303-356 — suppress_active is computed once per run and gates the existing diff block. Extending the same `if [[ "$suppress_active" -eq 0 ]]` guard covers the new block. | Reuse `suppress_active` variable in-scope; no new file. |

No "Gap callouts" — issue body is broadly accurate; minor refinements above.

## User-Brand Impact

- **If this lands broken, the user experiences:** the same #4173 failure
  class — `apply-web-platform-infra.yml` (and any future infra-touching
  workflow) 403's on installation-token-gated endpoints, blocking every push to
  `main` that touches `apps/web-platform/infra/**`. If a future permission
  widening gates an *auth-flow* endpoint (e.g., the App is asked to read
  `members:write` for some hypothetical org-membership flow), founders are
  locked out of GitHub-mediated sign-in until the operator re-accepts. One
  user's broken sign-in IS the brand-ending incident.

- **If this leaks, the user's data is exposed via:** N/A. Read-only diff
  primitive over App permission scopes (which are public to the App). No new
  data surface. The existing leak tripwire (PEM/JWT scan) already covers the
  one new code path that touches the JWT.

- **Brand-survival threshold:** `single-user incident`. The drift this catches
  is a category of incident where one user's auth failure equals the brand-end
  signal. CPO sign-off required at plan time. `user-impact-reviewer` invoked
  at PR-review time per `plugins/soleur/skills/review/SKILL.md` conditional-
  agent block.

## Observability

```yaml
liveness_signal:
  what: "Sentry cron monitor for scheduled-github-app-drift-guard"
  cadence: "hourly (matches workflow cron 0 * * * *)"
  alert_target: "Sentry issue + operator-email via notify-ops-email composite action + auto-filed GitHub issue"
  configured_in: ".github/workflows/scheduled-github-app-drift-guard.yml:575-584"

error_reporting:
  destination: "Sentry web-platform via SENTRY_PUBLIC_KEY + SENTRY_PROJECT_ID + SENTRY_INGEST_DOMAIN secrets"
  fail_loud: "Sentry check-in posts ?status=error when failure_mode != '' OR tripwire.outcome == 'failure'; ::warning::Drift-guard failed annotation in run log; auto-filed GitHub issue with label ci/auth-broken (drift) or ci/guard-broken (malfunction) and priority/p1-high; operator email via Resend"

failure_modes:
  - mode: "installation_permission_drift (live install grants strictly less than manifest declares)"
    detection: "diff-github-app-manifest.sh re-invoked against synthetic per-install {permissions, events} file; non-zero exit + stdout starts with permission_drift:"
    alert_route: "ci/auth-broken label + Sentry status=error + operator email + auto-filed issue"
  - mode: "installation_unexpected_grant (live install grants more than manifest declares)"
    detection: "diff-github-app-manifest.sh re-invoked; non-zero exit + stdout starts with permission_unexpected_grant:"
    alert_route: "ci/guard-broken label + Sentry status=error + operator email + auto-filed issue"
  - mode: "installation_api_http (HTTP non-200 from GET /app/installations)"
    detection: "curl --max-time 15 -w '%{http_code}' captures status; non-200/non-401 → record_failure"
    alert_route: "ci/guard-broken label + Sentry status=error + operator email + auto-filed issue"
  - mode: "installation_response_shape_unparseable (response missing/wrong-shape installations[] field)"
    detection: "jq -r '.installations | type' against response file; non-array → record_failure"
    alert_route: "ci/guard-broken label + Sentry status=error + operator email + auto-filed issue"

logs:
  where: "GitHub Actions run log at ${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}; auto-filed issue body links the run URL"
  retention: "GitHub Actions run logs: 90 days (org default). Auto-filed issues persist until closed. Sentry events: 30 days (org default)."

discoverability_test:
  command: "gh run list --workflow scheduled-github-app-drift-guard.yml --limit 1 --json conclusion,createdAt --jq '.[0]'"
  expected_output: '{"conclusion":"success","createdAt":"<within last hour>"}'
```

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1 — Workflow YAML extends the existing `check` step at
  `.github/workflows/scheduled-github-app-drift-guard.yml` with an installation-
  grant diff block placed AFTER the App-level manifest diff (lines 280-356)
  and BEFORE the `strip_log_injection` block (lines 366-371). Verified by
  `awk '/Manifest-vs-live permission\/event diff/,/strip_log_injection\(\)/' .github/workflows/scheduled-github-app-drift-guard.yml | wc -l` returns a count greater than the pre-change baseline.
- [ ] AC2 — New diff block reuses `bin/diff-github-app-manifest.sh` verbatim —
  no edits to the script. Verified by `git diff origin/main -- bin/diff-github-app-manifest.sh` returns empty.
- [ ] AC3 — New diff block reuses `suppress_active` (set at YAML:330) and
  ONLY runs when `suppress_active -eq 0`. Verified by grepping the new block
  for `if [[ "$suppress_active" -eq 0`.
- [ ] AC4 — Endpoint is `https://api.github.com/app/installations?per_page=100`
  (App-JWT auth, max-page-size pinned), NOT `/orgs/jikig-ai/installations`
  (PAT-auth, object-wrapped, wrong shape). Verified by `grep -c
  '/app/installations?per_page=100' .github/workflows/scheduled-github-app-drift-guard.yml`
  returns at least 1.
- [ ] AC4b — Iteration uses `jq -c '.[]'` against the FLAT array, NOT
  `jq -c '.installations[]'`. Verified by `grep -cE "jq -c '\.installations\[\]'" .github/workflows/scheduled-github-app-drift-guard.yml`
  returns 0 AND `grep -cE "jq -c '\.\[\]'" .github/workflows/scheduled-github-app-drift-guard.yml`
  returns at least 1.
- [ ] AC4c — Pagination Link-header guard present: `grep -cE 'rel="next"' .github/workflows/scheduled-github-app-drift-guard.yml`
  returns at least 1 AND the matching block routes to
  `installation_list_truncated` → `ci/guard-broken`.
- [ ] AC5 — Curl invocation uses `--header @<(printf 'Authorization: Bearer
  %s' "$JWT")` form (NOT `-H "Authorization: Bearer $JWT"` directly, per
  P1-2 trap dossier at YAML:28). Verified by `grep -c '@<(printf'
  .github/workflows/scheduled-github-app-drift-guard.yml` returns at least 2
  (existing /app call + new /app/installations call).
- [ ] AC6 — New failure modes emitted via `record_failure` use the prefix
  `installation_` (`installation_permission_drift`,
  `installation_unexpected_grant`, `installation_api_http`,
  `installation_response_shape_unparseable`, `installation_list_truncated`,
  `installation_diff_unknown_mode`) so the auto-filed issue body
  distinguishes plane (c) from plane (a) drift. Verified by `grep -cE
  'installation_(permission_drift|unexpected_grant|api_http|response_shape_unparseable|list_truncated|diff_unknown_mode)'
  .github/workflows/scheduled-github-app-drift-guard.yml` returns 6 or more.
- [ ] AC7 — Failure-label routing: `installation_permission_drift` →
  `ci/auth-broken` (security-regression direction, mirrors plane-(a)
  precedent at YAML:342-343); `installation_unexpected_grant`,
  `installation_api_http`, `installation_response_shape_unparseable` →
  `ci/guard-broken`. Verified by reading the new case statement in the PR
  diff.
- [ ] AC8 — Per-installation iteration uses `while IFS= read -r install_json;
  do … done < <(jq -c '.[]' "$INSTALL_LIST_FILE")` (FLAT array; process-
  substitution-as-input is safe — the file is a regular file read once via
  jq). Defensive: empty array silently produces zero iterations
  and no `record_failure`. Verified by reading the new block.
- [ ] AC9 — Cleanup step at YAML:553-561 extended to include `rm -f
  "$RUNNER_TEMP"/installations.* "$RUNNER_TEMP"/installations-hdr.*
  "$RUNNER_TEMP"/install-resp.*`. Verified by
  `grep -cE 'install-resp|installations\.\*|installations-hdr' .github/workflows/scheduled-github-app-drift-guard.yml` returns at least 3.
- [ ] AC10 — Contract test
  `apps/web-platform/test/github-app-manifest-drift-guard.test.ts` adds ONE
  new case proving the workflow's per-install synthesis pattern: given a
  multi-install `/app/installations` response, `jq '{permissions, events}'`
  per element produces a file the existing diff script consumes correctly.
  Verified by `./node_modules/.bin/vitest run apps/web-platform/test/github-app-manifest-drift-guard.test.ts` reports 8 passing cases (was 7).
- [ ] AC11 — Runbook `knowledge-base/engineering/ops/runbooks/github-app-provisioning.md`
  Step 2.1 updated to note: "After re-accepting installation permissions in
  the UI, the next hourly cron run of scheduled-github-app-drift-guard.yml
  will close any open `installation_permission_drift` tracking issue
  automatically via the existing auto-close-stale step at YAML:530-551."
  Verified by `grep -c 'installation_permission_drift' knowledge-base/engineering/ops/runbooks/github-app-provisioning.md` returns at least 1.
- [ ] AC12 — `apps/web-platform/infra/github-app.tf:24-30` comment block
  updated to remove the "tracked in #4179 as a drift-guard extension"
  language and replace with "Both planes detected by scheduled-github-app-
  drift-guard.yml (App-declared vs manifest at YAML:280-356, installation-
  grant vs manifest at YAML:<new line>)." Verified by `grep -c '#4179'
  apps/web-platform/infra/github-app.tf` returns 0 after the edit.
- [ ] AC13 — `Closes #4179` AND `Closes #3561` appear in the PR body (NOT
  title — per `wg-use-closes-n-in-pr-body-not-title-to`). Verified at `gh pr
  view --json body --jq .body | grep -cE 'Closes #(4179|3561)'` returns 2.
- [ ] AC13b — **MUST-FIX: #3561 fold-in.** Replace `tr -d '\r\n\f\v\x7f'`
  with `tr -d '\r\n\f\v\177'` (octal `\177` survives `tr`'s POSIX
  no-hex-escape interpretation) at `strip_log_injection` (around YAML:370).
  Verified by `grep -cE "tr -d '\\\\r\\\\n\\\\f\\\\v\\\\177'" .github/workflows/scheduled-github-app-drift-guard.yml` returns at least 1 AND `grep -c '\\\\x7f' .github/workflows/scheduled-github-app-drift-guard.yml` returns 0. This is **load-bearing** for the new failure modes (every `installation_*` name contains `f` — see Sharp Edges).
- [ ] AC14 — All existing contract test cases pass unchanged (the script is
  not edited). Verified by `./node_modules/.bin/vitest run apps/web-platform/test/github-app-manifest-drift-guard.test.ts` AND `./node_modules/.bin/vitest run apps/web-platform/test/github-app-manifest-parity.test.ts` both green.
- [ ] AC15 — `actionlint .github/workflows/scheduled-github-app-drift-guard.yml`
  exits 0 (no YAML/Action syntax regressions). The plan-time grep should NOT
  be `bash -n` against the YAML file (see Sharp Edges).
- [ ] AC16 — `bash -c "$(awk '/^      - id: check/,/^      - id: tripwire/'
  .github/workflows/scheduled-github-app-drift-guard.yml | awk '/run: \|/{f=1;next} f && /^        [^ ]/{f=0} f')" </dev/null` syntax-checks the
  extracted shell snippet from the check step (parses but does not execute —
  exits 0 on syntax-OK). This validates the embedded shell, not the YAML.
- [ ] AC17 — Plan-prescribed simplicity: net new file count = 0; net new
  workflow count = 0; net new secret count = 0; net new script count = 0.
  Verified by `git diff --name-status origin/main -- bin/ scripts/ .github/workflows/ apps/web-platform/infra/`.

### Post-merge (operator)

- [ ] AC17b — **If the merge happens before 2026-05-21T16:00:00Z**, the active
  `MANIFEST_DRIFT_SUPPRESS_UNTIL` file will suppress BOTH a-vs-b AND c-vs-b
  diffs on the first post-merge run. To force immediate verification, either:
  (a) `rm apps/web-platform/infra/MANIFEST_DRIFT_SUPPRESS_UNTIL` in the same
  PR (and re-add a fresh one if a manifest edit happens post-merge), or
  (b) wait until after 2026-05-21T16:00:00Z to run AC18. The agent SHOULD
  remove the suppress file in this PR since plane (c) reconciliation completed
  in PR #4174.
- [ ] AC18 — Operator (or agent via Playwright/`gh` CLI per
  hr-exhaust-all-automated-options-before) manually triggers `gh workflow run
  scheduled-github-app-drift-guard.yml --ref main` once post-merge and
  verifies the run completes green (current installation grants the same 8
  permissions as the manifest declares; no drift expected). Verified by
  `gh run list --workflow scheduled-github-app-drift-guard.yml --limit 1 --json conclusion --jq '.[0].conclusion'`
  returns `"success"`. **Automation feasibility:** fully automatable —
  `/soleur:ship` Phase 6 post-merge already includes a `gh workflow run`
  step for modified workflows; this AC is automatable inline.
- [ ] AC19 — Synthetic-drift test in fork: operator forks `jikig-ai/soleur` to
  a personal account, removes `secrets` from `apps/web-platform/infra/github-app-manifest.json`,
  commits, manually dispatches the workflow, confirms an `installation_unexpected_grant`
  issue is filed labeled `ci/guard-broken`. (Inverse direction —  manifest
  declares fewer than live grants is the easier synthetic to construct since
  it requires no operator UI click.) Operator-only because forking + dispatch
  requires interactive auth.

  **Automation feasibility note:** Forking + manifest edit + manual
  dispatch are all `gh` CLI scriptable — this step COULD be automated as a
  separate workflow that runs against a sibling repo, but the cost
  (provisioning a sibling repo + a dedicated App installation to serve as the
  fork target) exceeds the value of a one-time synthetic test. Defer
  automation to a follow-up if the test cadence ever needs to increase.

## Test Scenarios

### Acceptance Tests (RED-phase targets)

- **AT1 (AC1–AC9).** Given the workflow YAML at HEAD lacks the installation-
  grant diff block, when CI runs against a manifest that declares X but the
  live installation lacks X, then the cron's auto-filed issue body still says
  `permission_drift` (plane a-vs-b only, not c). Expected post-fix: a second
  issue is filed with `installation_permission_drift` in the body, labeled
  `ci/auth-broken`.

- **AT2 (AC2, AC10).** Given a fixture `/app/installations` response with two
  installations (one matches manifest, one declares fewer permissions),
  when the workflow's per-install synthesis runs, then the diff script
  receives a `{permissions, events}` file for EACH installation and emits
  `permission_drift:...` for the second only. Test scaffolds via
  spawnSync of `bash -c '<extracted snippet>'` against fixture files
  (mirrors the existing case 1-7 pattern at line 76-150 of the contract
  test).

- **AT3 (AC8).** Given an empty `installations: []` response (no
  installations of this App), when the workflow runs, then zero `record_failure`
  invocations fire AND the run exits green. Defensive against the
  "loop-over-empty-array" silent-skip pattern.

- **AT4 (AC4 + AC5).** Given a recorded HTTP request mock for `GET /app/installations`,
  when the workflow's new step runs, then the request includes
  `Authorization: Bearer <jwt>` (NOT `Authorization: token <jwt>`) AND
  `X-GitHub-Api-Version: 2022-11-28`. Verified via the contract test's
  ability to record headers (see existing test at github-app-drift-guard-contract.test.ts:289).

### Regression Tests

- **RT1.** All 7 existing contract test cases at
  `apps/web-platform/test/github-app-manifest-drift-guard.test.ts` pass
  unchanged (the script is not modified).
- **RT2.** All 11 existing parity test cases at
  `apps/web-platform/test/github-app-manifest-parity.test.ts` pass unchanged
  (no change to manifest contents).
- **RT3.** Existing workflow integration test at
  `apps/web-platform/test/github-app-drift-guard-contract.test.ts` (if it
  exercises the workflow YAML structurally) passes — confirm by running the
  full suite.

### Edge Cases

- **EC1.** `MANIFEST_DRIFT_SUPPRESS_UNTIL` set to a future timestamp →
  installation-grant diff is also suppressed (same gate). Asserted by
  reading the AC3 grep result.
- **EC2.** `GET /app/installations` returns `{"message":"Bad credentials"}`
  HTTP 401 → `installation_api_http` failure mode with HTTP code `401`,
  routed to `ci/guard-broken` (matches PEM-stale class — the same JWT was
  good enough for `GET /app` so a 401 on `/app/installations` is a guard
  malfunction, not auth-broken).
- **EC3.** `GET /app/installations` returns HTTP 200 but body is
  `{"message":"Not Found"}` (no `installations` key) → response_shape_unparseable.
  Asserted at AC8.
- **EC4.** Per-installation diff script invocation returns
  `response_shape_unparseable` (very unlikely — the `{permissions, events}`
  synthesis always produces a valid shape). Routed to `ci/guard-broken`.

### Integration Verification (for `/soleur:qa`)

- **API verify (post-merge):**
  ```bash
  gh workflow run scheduled-github-app-drift-guard.yml --ref main
  sleep 60
  gh run list --workflow scheduled-github-app-drift-guard.yml --limit 1 \
    --json conclusion,databaseId --jq '.[0]'
  ```
  Expected: `{"conclusion":"success","databaseId":<id>}`.

- **Issue-state verify (post-merge):**
  ```bash
  gh issue list --label ci/auth-broken --state open --json title,body \
    --jq '.[] | select(.title | contains("drift-guard"))'
  gh issue list --label ci/guard-broken --state open --json title,body \
    --jq '.[] | select(.title | contains("drift-guard"))'
  ```
  Expected: both return empty (no open drift-guard tracking issues — live
  state matches manifest as of plan-write time probe).

## Files to Edit

- `.github/workflows/scheduled-github-app-drift-guard.yml` — add installation-
  grant diff block (~50 LoC) inside the `check` step; extend cleanup glob
  (1 LoC); optionally extend `record_failure` allowlist if new modes warrant
  inclusion (the existing wildcard-warning default routes unknown labels to
  `ci/guard-broken` — fail-safe).
- `apps/web-platform/test/github-app-manifest-drift-guard.test.ts` — add
  ONE new contract test case for the per-installation synthesis pattern
  (~25 LoC). Place after the existing case 7.
- `apps/web-platform/infra/github-app.tf` — update comment block at lines
  24-30 to reflect that both planes are now detected (lose the "#4179 as a
  drift-guard extension" deferred-language; replace with the closed-loop
  statement).
- `knowledge-base/engineering/ops/runbooks/github-app-provisioning.md` —
  extend Step 2.1 with the auto-close-stale note + cross-reference the new
  failure mode names.

## Files to Create

None. The existing diff script, suppression file, contract test file, and
runbook all preserve their shape.

## Open Code-Review Overlap

Two open code-review issues touch `.github/workflows/scheduled-github-app-drift-guard.yml`:

- **#3561** (priority/p3-low, `tr -d '\x7f'` silently strips literal `x`/`7`/`f`):
  Fold-in. One-line fix at the workflow's `strip_log_injection` function
  (replace `\x7f` with `\177` octal form). Same workflow file, trivial
  scope, closes the bug class. PR body will include `Closes #3561` (Closes
  is appropriate because the fix is pre-merge code, not post-merge
  operator work). New failure-mode strings introduced here (`installation_permission_drift`
  etc.) do NOT contain `x`, `7`, or `f` in load-bearing positions, so the
  bug does not manifest against the new modes — folding-in is opportunistic
  defense-in-depth.

- **#3750** (priority/p3-low, deferred-scope-out, extract mint-app-jwt
  composite action ~85 LoC dedup):
  **Acknowledge.** Substantial refactor (~85 LoC across two workflows + new
  composite action file). Different concern (DRY refactor vs. new detection
  primitive). Folding in would balloon scope from ~80 LoC to ~165 LoC and
  introduces a refactor risk surface that this plan's primary value (close
  the #4173 detection gap) does not need. Issue #3750 stays open.

## Success Metrics

- Time-to-detect installation-grant drift: ≤1 hour after divergence (matches
  cron cadence). Compare to current state: indefinite (the standing
  primitive never detects this plane).
- Mean wall-clock budget per cron run: stays under the existing 5-minute
  step timeout. The one additional HTTP call + small jq invocations adds <5
  seconds.
- Zero false positives in the first 24 hours post-merge (the live install
  matches the manifest as of plan-write time probe — verified via
  `gh api /orgs/jikig-ai/installations`).
- One pre-existing bug (#3561) closed inline.

## Dependencies & Risks

### Dependencies

- The existing `bin/diff-github-app-manifest.sh` script is unchanged — its
  contract is the single source of truth for `{permissions, events}` diff
  semantics. Any future edits to the script must keep this contract intact
  (already covered by the existing contract test).
- The `MANIFEST_DRIFT_SUPPRESS_UNTIL` mechanism is reused as-is.
- The existing App-JWT mint logic is reused — no changes to the mint flow.
- The `notify-ops-email` composite action and Sentry heartbeat already
  cover the new failure paths via the existing `failure_mode != ''`
  gate at YAML:517.

### Risks

- **R1 (low).** First post-merge run could surface drift that was previously
  invisible. Mitigation: plan-time probe confirms current installation
  matches the manifest exactly (8 permissions, 0 events). The
  `MANIFEST_DRIFT_SUPPRESS_UNTIL` is currently set to `2026-05-21T16:00:00Z`
  (in scope for the post-#4173 reconciliation window) — both diffs will be
  suppressed during that window; the first un-suppressed run is therefore
  expected to be green.

- **R2 (low).** The first-fail-wins behavior of `record_failure` means if
  TWO installations both drift simultaneously, only the first is reported
  per cron tick. Acceptable for the current 1-installation state; document
  inline; defer multi-fail collection.

- **R3 (low).** Per the new Sharp Edge above, an unanticipated multi-install
  topology (we get a second installation tomorrow because we accept the App
  on a different org) would surface unexpectedly via this new code path —
  but it would surface as `installation_unexpected_grant` (correct
  behavior) or `installation_permission_drift` if that install grants
  fewer permissions than the manifest declares. Either is a real signal
  the operator should act on, not noise.

- **R4 (P1 → must-fix in this PR).** Deepen-pass caught that EVERY proposed
  failure mode name (`installation_permission_drift`,
  `installation_unexpected_grant`, `installation_response_shape_unparseable`,
  `installation_list_truncated`, `installation_diff_unknown_mode`) contains
  the letter `f` in load-bearing positions. The current `tr -d '\x7f'` bug
  at workflow:370 silently strips every `f` from sanitized output — the
  operator-facing issue body would show garbled mode names (e.g.,
  `installation_permission_drit`). The #3561 fold-in is no longer
  opportunistic; it is **load-bearing** for the new feature. Tracked as
  AC13b.

## Infrastructure (IaC)

**Skip silently** — this plan introduces no new infrastructure (pure code +
docs change against an already-provisioned drift-guard workflow). No new
secrets, no new vendor accounts, no new Terraform resources, no new systemd
units, no new cron jobs (extends an existing cron). The IaC routing gate at
Phase 2.8 does not fire.

## Domain Review

**Domains relevant:** Engineering (CTO), Legal (CLO) — carry-forward only;
Product (CPO) — carry-forward + plan-time sign-off

### Engineering (CTO)

**Status:** carry-forward from brainstorm `2026-05-05-github-app-drift-guard-brainstorm.md`
+ learning `2026-05-20-github-app-installation-grant-vs-manifest-three-plane-drift.md`
**Assessment:** Build now. Diff-script contract preserved (no new script);
single workflow file extension with ~50 LoC YAML + one new test case + comment
+ runbook updates. Reuse existing JWT mint, suppression mechanism, leak
tripwire, issue-filing flow, and Sentry heartbeat. The architectural insight
(three-plane drift model) is already codified in the learning file; this plan
implements the v2 detection primitive the brainstorm explicitly deferred to a
follow-up.

### Legal (CLO)

**Status:** carry-forward from brainstorm (CLO assessment of #4115/parent)
**Assessment:** GO unchanged. The drift-guard is a GDPR Policy §299 compliance
control (the brainstorm's CLO note). This plan extends the control's coverage
to a missed detection plane — same regulatory framing, no new processing
surface. No new data category, no new vendor, no new lawful basis question.
Doppler row in `compliance-posture.md` already present from the parent PR
#4121.

### Product/UX Gate

**Tier:** none
**Decision:** auto-accepted (pipeline)
**Agents invoked:** none (no UI change, infrastructure-only)
**Skipped specialists:** none
**Pencil available:** N/A

#### CPO sign-off (plan-time, required by `single-user incident` threshold)

**Status:** required per `requires_cpo_signoff: true` in YAML frontmatter.
**Carry-forward:** CPO sign-off on the parent feature (brainstorm
`2026-05-05`, P3→P2 bump, Phase 4 sequencing pre-Stripe-live) covered the
architectural choice. This follow-up extends the SAME primitive to close a
known structural gap — does not invent a new product decision; CPO ack at
plan time is therefore confirmatory rather than re-design.

**Recommended next action:** during one-shot pipeline, ack carry-forward
+ invoke CPO domain leader only if scope expands beyond the diff-block
extension described above.

## GDPR / Compliance Gate

**Skip silently.** Plan does not touch regulated-data surfaces per the
canonical regex (no schema, no migration, no auth flow, no API route, no
`.sql` file). The extended cron reads only GitHub's authoritative state about
Soleur's own App permissions; the App's permission scopes are public to the
App itself. No operator-session data, no LLM, no new artifact distribution.

Trigger (a) — LLM/external API on operator data: no LLM; external API
(`GET /app/installations`) reads only the App's own metadata. Skip.
Trigger (b) — brand-survival threshold `single-user incident` declared: YES,
but the data category is the App's own permission scope, not user data. The
threshold drives CPO sign-off (above), not GDPR-gate processing-activity
treatment.
Trigger (c) — new cron/workflow reading from learnings/specs: extends an
existing cron; no new read of learnings/specs.
Trigger (d) — new artifact distribution surface: no.

All four triggers either skip or resolve to existing carry-forward.

## References & Research

### Internal References

- Existing workflow: `.github/workflows/scheduled-github-app-drift-guard.yml`
  (especially lines 280-356 — App-level diff block to mirror)
- Existing diff script: `bin/diff-github-app-manifest.sh` (unchanged; contract
  documented at lines 1-34)
- Existing contract test: `apps/web-platform/test/github-app-manifest-drift-guard.test.ts`
  (especially the case-1-7 pattern at lines 70-150)
- Existing parity test: `apps/web-platform/test/github-app-manifest-parity.test.ts`
  (no change needed)
- Manifest: `apps/web-platform/infra/github-app-manifest.json`
  (8 permissions, 0 events, post-#4173 reconciled state)
- Suppression file: `apps/web-platform/infra/MANIFEST_DRIFT_SUPPRESS_UNTIL`
  (currently `2026-05-21T16:00:00Z` — active suppression window)
- Terraform comment: `apps/web-platform/infra/github-app.tf:24-30`
- Runbook: `knowledge-base/engineering/ops/runbooks/github-app-provisioning.md`
  (Step 2.1 at line 62)
- Foundational learning: `knowledge-base/project/learnings/2026-05-20-github-app-installation-grant-vs-manifest-three-plane-drift.md`
- Manifest-as-IaC pattern learning: `knowledge-base/project/learnings/2026-05-20-manifest-as-iac-with-shared-diff-script-contract.md`
- Brainstorm carry-forward: `knowledge-base/project/brainstorms/2026-05-05-github-app-drift-guard-brainstorm.md`
  (especially Non-Goals §"Installation-level guard")
- Prior plan precedent: `knowledge-base/project/plans/2026-05-05-feat-github-app-drift-guard-plan.md`
  (the parent feature)
- Adjacent plan: `knowledge-base/project/plans/2026-05-20-fix-apply-web-platform-infra-secrets-write-installation-grant-4173-plan.md`
  (the incident-remediation that triggered this follow-up)
- AGENTS.md `hr-github-app-auth-not-pat` — endpoint-choice rationale aligns

### External References

- GitHub REST API — `GET /app/installations`:
  https://docs.github.com/en/rest/apps/apps#list-installations-for-the-authenticated-app
- GitHub REST API — `GET /orgs/{org}/installations`:
  https://docs.github.com/en/rest/orgs/orgs#list-app-installations-for-an-organization
  (rejected — requires PAT with admin:org; we use the App-JWT endpoint instead)
- GitHub REST API — App JWT auth:
  https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/generating-a-json-web-token-jwt-for-a-github-app

### Related Work

- Related issues: #4173 (root incident), #4115 (parent feat, manifest-as-IaC),
  #4136, #4137 (downstream PMs unblocked by closing this), #3187 (drift-guard
  v1), #3561 (fold-in inline)
- Related PRs: #4121 (manifest-as-IaC + drift-guard v1), #4174 (the immediate
  #4173 fix that named this issue as the follow-up)
