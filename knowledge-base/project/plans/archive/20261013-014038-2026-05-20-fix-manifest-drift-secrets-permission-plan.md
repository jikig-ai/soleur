---
type: fix
issue: 4169
branch: feat-one-shot-manifest-secrets-drift-4169
lane: single-domain
requires_cpo_signoff: false
---

# fix: manifest drift — add `secrets: write` to GitHub App manifest + PM2 suppress

## Enhancement Summary

**Deepened on:** 2026-05-20
**Sections enhanced:** Overview, User-Brand Impact, Acceptance Criteria (Post-merge), Risks & Sharp Edges
**Verification commands run live (not from memory):**

- `gh issue view 4169 / 4170 --json state,title` — confirmed both are OPEN issues with the cited titles. PR-vs-issue disambiguation done (per 2026-05-20 PR-vs-issue rule).
- `grep -qE "\[id: <rule>\]" AGENTS.md` — confirmed every cited AGENTS.md rule ID is ACTIVE (`hr-weigh-every-decision-against-target-user-impact`, `hr-observability-as-plan-quality-gate`, `wg-use-closes-n-in-pr-body-not-title-to`).
- `date -d "2026-05-21T16:00:00Z" -u +%s` minus `date -u +%s` → ~26h ahead, well inside the 30-day cap (`2592000s`) enforced at `scheduled-github-app-drift-guard.yml:317`.
- `echo "2026-05-21T16:00:00Z" | grep -qE '<workflow-regex>'` → MATCH against the workflow's strict-ISO-8601 regex at line 313.
- `jq '.default_permissions + {"secrets":"write"} | keys'` → 8-key alphabetical array (`actions, administration, checks, contents, members, metadata, pull_requests, secrets`). Alphabetical-tail position confirmed.
- `Read bin/diff-github-app-manifest.sh:60-150` — read the diff-mode classification logic verbatim.

### Key Improvements (vs. initial plan)

1. **Failure-mode correction.** The PM1 comment said the next cron tick would fire `permission_drift` / `ci/auth-broken`; per `bin/diff-github-app-manifest.sh:78-79` and workflow:341-353, the actual mode for "live has Y, manifest doesn't" is `permission_unexpected_grant` → `ci/guard-broken` (workflow:345-346). The plan's user-impact framing, AC verbiage, and post-merge AC label all corrected to the real label. Identifies the canonical mode/label pair operators should grep for post-merge.
2. **Brand-survival scope-out.** Discovered Files-to-Edit `apps/web-platform/infra/*` matches the canonical sensitive-path regex (`apps/[^/]+/infra/`). With `threshold: none`, the plan now contains a one-sentence scope-out (`reason: manifest JSON + ISO-8601 suppress text + ops docstring carry no credentials, no PII, no auth-flow code paths`) per preflight Check 6.1, satisfying deepen-plan Phase 4.6 and the upcoming preflight gate.
3. **Cron timing clarification.** Added an explicit note that the suppress file is only effective from the FIRST tick AFTER merge (the cron checks out `main` via sparse-checkout). No protective effect during the PR window — auto-merge via `/soleur:ship` is the right delivery vehicle.

### New Considerations Discovered

- The plan correctly uses `Closes #4169` (not `Ref #N`). The reconciliation work (manifest parity) IS committed at merge — there is no post-merge `terraform apply` gating the fix, so the `ops-remediation Closes vs Ref` rule does not apply. The cron tick is OBSERVATION of the merged artifact, not REMEDIATION executed post-merge.
- The diff script's `permission_drift > permission_unexpected_grant` precedence (`bin/diff-github-app-manifest.sh:129-142`) means once the manifest gains `secrets: write` AND the live App matches, neither direction fires — the suppress file becomes redundant (and the follow-through issue tracks its deletion). No drift can fire green-on-green by construction.
- Self-grep risk: AC1 quotes the string `"secrets": "write"`. A future deepen-plan greppy AC could match this string in the plan body itself. The current ACs all use `jq -e` or `grep -qE` against the actual manifest file path (`apps/web-platform/infra/github-app-manifest.json`), not whole-tree scope, so the self-grep trap does not fire.

## Overview

Live GitHub App `GET /app` `permissions` includes `"secrets": "write"` (verified by operator at 2026-05-20T13:41Z, see #4169 comment), but the committed manifest at `apps/web-platform/infra/github-app-manifest.json` `default_permissions` does not. Without committed-side parity AND a suppress file, the hourly drift-guard cron (`.github/workflows/scheduled-github-app-drift-guard.yml`) will fire on its next tick (~14:50-15:00Z) and open an issue.

**Failure-mode correction vs. PM1 comment.** The PM1 comment on #4169 stated the cron would fire `permission_drift` / `ci/auth-broken`. Per `bin/diff-github-app-manifest.sh:78-79` and the workflow's mode→label routing (workflow:341-353), the actual current direction is `Live > Manifest` (extra-in-live), which fires `permission_unexpected_grant` → `ci/guard-broken` (workflow:345-346). The PR's load-bearing outcome (suppress the noise during reconciliation, then land manifest parity) is identical either way; the mode/label correction is documented here so the runbook reader can grep the right issue label post-merge.

Two-line surgical fix:

1. Add `"secrets": "write"` to `default_permissions` in the manifest (alphabetical, after `pull_requests`).
2. Create `apps/web-platform/infra/MANIFEST_DRIFT_SUPPRESS_UNTIL` with strict ISO-8601 UTC timestamp `2026-05-21T16:00:00Z` (~24h reconciliation window — within the 30-day workflow cap).

Bundled: 1-line docstring correction in `bin/snapshot-github-app.sh` line 17 (drop `| base64 -d` from the Doppler example). Same operational domain, trivial scope, named in the issue context.

## User-Brand Impact

**If this lands broken, the user experiences:** the hourly drift-guard cron fires a `permission_unexpected_grant` issue (`ci/guard-broken`), routing the operator into a paper alert loop while the live App is healthy. No end-user impact (the live App's `secrets: write` is the source of truth; drift-guard noise stays in the ops surface).

**If this leaks, the user's data is exposed via:** N/A — manifest authoring touches no user data, no credentials, no PII. The `secrets: write` permission is already granted on the live App; this PR only documents it in the committed source.

- **Brand-survival threshold:** none
- `threshold: none, reason: manifest JSON + ISO-8601 suppress text + ops docstring carry no credentials, no PII, no auth-flow code paths; the live GitHub App already has secrets:write granted, this PR only brings the committed source into parity with reality (no new privilege is requested or granted).`

## Research Reconciliation — Spec vs. Codebase

| Spec claim (issue body / #4169 comment) | Reality (codebase verification) | Plan response |
|---|---|---|
| Manifest at `apps/web-platform/infra/github-app-manifest.json` lacks `secrets` | Confirmed via `Read`: 7 keys (`actions, administration, checks, contents, members, metadata, pull_requests`), no `secrets` | Add `"secrets": "write"` after `pull_requests` (alphabetical-last position) |
| Insert "alphabetically between `pull_requests` and the next key" | `pull_requests` is the LAST key in the current map; no key follows. `secrets` sorts after `pull_requests` alphabetically | Insert as the new last entry. Plan body corrects the issue's phrasing (no "next key" exists). |
| Suppress format regex `^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$` enforced in workflow | Confirmed at `.github/workflows/scheduled-github-app-drift-guard.yml:313` | Use `2026-05-21T16:00:00Z` (passes regex; ~24h ahead of 2026-05-20 plan-write time) |
| 30-day max-window cap also enforced | Confirmed at workflow:317 (`max_window_s=$((30 * 24 * 3600))`) | 24h window is well inside the cap |
| `bin/snapshot-github-app.sh` docstring shows `| base64 -d` but Doppler stores raw PEM | Confirmed: script line 17 shows `doppler secrets get GITHUB_APP_PRIVATE_KEY --plain -p soleur -c prd \| base64 -d > /tmp/app.pem` — issue comment correctly notes Doppler GITHUB_APP_PRIVATE_KEY stores raw PEM (no encode/decode round-trip) | Drop `| base64 -d` from line 17 inline. Issue body's command (no decode) is canonical. |

## Files to Edit

- `apps/web-platform/infra/github-app-manifest.json` — add `"secrets": "write"` as final entry in `default_permissions` (after `pull_requests`).
- `bin/snapshot-github-app.sh` — line 17, drop `| base64 -d` from the inline docstring example. Keep `chmod 600` and `shred -u` lines verbatim.

## Files to Create

- `apps/web-platform/infra/MANIFEST_DRIFT_SUPPRESS_UNTIL` — single-line file containing exactly `2026-05-21T16:00:00Z\n` (LF terminator; workflow `tr -d ' \t\r\n'` strips). No trailing whitespace, no BOM. Mode 0644.

## Implementation Phases

### Phase 1 — Manifest edit

1. Read `apps/web-platform/infra/github-app-manifest.json`.
2. Edit `default_permissions` to insert `"secrets": "write"` after `pull_requests`. Keep 2-space indent, trailing comma logic: change `"pull_requests": "write"` (no comma, last entry) → `"pull_requests": "write",\n    "secrets": "write"` (new last entry, no comma).
3. Verify with `jq .default_permissions apps/web-platform/infra/github-app-manifest.json` — expect 8 keys, `secrets` value `"write"`.
4. Verify byte parity (post-merge attestation, not pre-merge): `jq --sort-keys .default_permissions apps/web-platform/infra/github-app-manifest.json` matches the 8-key shape from the live-App snapshot in the #4169 comment.

### Phase 2 — Suppress file create

1. Create `apps/web-platform/infra/MANIFEST_DRIFT_SUPPRESS_UNTIL` with content `2026-05-21T16:00:00Z\n`.
2. Verify regex match: `grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' apps/web-platform/infra/MANIFEST_DRIFT_SUPPRESS_UNTIL && echo OK`.
3. Verify file is captured by workflow's sparse-checkout block (`.github/workflows/scheduled-github-app-drift-guard.yml:70`) — already listed, no workflow edit needed.

### Phase 3 — Docstring fix in snapshot script

1. Read `bin/snapshot-github-app.sh` line 17.
2. Replace the docstring example line:
   - Before: `#                              doppler secrets get GITHUB_APP_PRIVATE_KEY --plain \`<br>`#                                -p soleur -c prd | base64 -d > /tmp/app.pem`
   - After: `#                              doppler secrets get GITHUB_APP_PRIVATE_KEY --plain \`<br>`#                                -p soleur -c prd > /tmp/app.pem`
3. No executable code changes — comment-only. `bash -n bin/snapshot-github-app.sh` should pass unchanged.

### Phase 4 — Follow-through issue (post-merge)

Create a follow-through issue (per /ship phase 7.5) to track deletion of the SUPPRESS file once the live App is reconciled with the committed manifest. The suppress file is intentionally temporary — leaving it in main beyond the reconciliation window blinds drift-guard.

- Title: `follow-through: delete MANIFEST_DRIFT_SUPPRESS_UNTIL after #4170 manifest-vs-live parity confirmed`
- Body: links to #4169 (this PR), references the workflow's 30-day cap as the hard backstop, prescribes the deletion check: `! [ -f apps/web-platform/infra/MANIFEST_DRIFT_SUPPRESS_UNTIL ]` once a drift-guard tick passes green without the suppress file in place.
- Labels: `follow-through`
- Automation: ship phase 7 step 3.5 handles issue creation post-merge.

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` returns no matches against `apps/web-platform/infra/github-app-manifest.json`, `bin/snapshot-github-app.sh`, or `MANIFEST_DRIFT_SUPPRESS_UNTIL` (verified at plan-write time).

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `jq -e '.default_permissions.secrets == "write"' apps/web-platform/infra/github-app-manifest.json` exits 0.
- [ ] `jq -e '.default_permissions | length == 8' apps/web-platform/infra/github-app-manifest.json` exits 0 (was 7, now 8).
- [ ] `jq -e '.default_permissions | keys == ["actions","administration","checks","contents","members","metadata","pull_requests","secrets"]' apps/web-platform/infra/github-app-manifest.json` exits 0 (alphabetical key order preserved).
- [ ] `apps/web-platform/infra/MANIFEST_DRIFT_SUPPRESS_UNTIL` exists, single line, matches regex `^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$` via `grep -qE`.
- [ ] Suppress timestamp epoch (`date -d "$(cat apps/web-platform/infra/MANIFEST_DRIFT_SUPPRESS_UNTIL)" -u +%s`) is within 30 days of now (`max_window_s = 30*24*3600`) — workflow cap honored.
- [ ] `bin/snapshot-github-app.sh` line 17 docstring no longer contains the literal token `| base64 -d` (verified via `grep -F '| base64 -d' bin/snapshot-github-app.sh` returning zero matches).
- [ ] `bash -n bin/snapshot-github-app.sh` passes (comment-only edit; syntax unchanged).
- [ ] PR body contains `Closes #4169`.

### Post-merge (operator/cron)

- [ ] Next hourly drift-guard cron tick (`scheduled-github-app-drift-guard`) emits the `::warning::Manifest drift detected but suppressed until 2026-05-21T16:00:00Z` annotation and does NOT open a `ci/guard-broken` (or `ci/auth-broken`) issue. Note: between PR-open and PR-merge the suppress file is unreachable from the cron (workflow checks out `main`), so the first protective tick is the FIRST cron after merge. (Automation: GitHub Actions cron; verified via `gh run list --workflow scheduled-github-app-drift-guard.yml --limit 1` post next-hour boundary.)
- [ ] After live-App `secrets: write` parity is confirmed (already true per #4169 comment), the next drift-guard tick after `2026-05-21T16:00:00Z` passes green without the suppress file (follow-through issue tracks the deletion).

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure config + ops docstring change. No user data, no schema, no auth flow, no UI surface, no new dependencies. Single-domain (engineering ops).

## Infrastructure (IaC)

Not applicable — no new infrastructure resources, no Terraform changes. This PR edits committed metadata (manifest JSON describing already-provisioned App permissions) and a workflow-controlled suppress file (consumed by an existing cron). The live GitHub App already has `secrets: write` granted; this PR brings the committed source into parity, it does NOT provision anything.

## Observability

Not applicable — pure-docs / config-data PR with no new code paths under `apps/*/server/`, `apps/*/src/`, or `apps/*/infra/*.{ts,tf}`. The drift-guard cron (`.github/workflows/scheduled-github-app-drift-guard.yml`) IS the observability surface for this change; its existing Sentry heartbeat (workflow:575-584) covers the post-merge signal:

```yaml
liveness_signal:
  what: scheduled-github-app-drift-guard cron tick (1h cadence)
  cadence: hourly (0 * * * *)
  alert_target: Sentry monitor `scheduled-github-app-drift-guard` + ops email (Resend)
  configured_in: .github/workflows/scheduled-github-app-drift-guard.yml:575-584
error_reporting:
  destination: GitHub issue under `ci/auth-broken` or `ci/guard-broken` label + Sentry heartbeat error status
  fail_loud: yes — issue created on first failure, comment-appended on repeat
failure_modes:
  - mode: permission_drift (manifest declares X, live lacks X)
    detection: bin/diff-github-app-manifest.sh exit non-zero with `permission_drift:` prefix
    alert_route: ci/auth-broken issue + Sentry error
  - mode: suppress_timestamp_invalid (regex fail / >30d cap / unparseable)
    detection: workflow regex + date -d parse + max_window_s check (workflow:313-326)
    alert_route: ::warning:: annotation in run log (no issue, suppress ignored)
logs:
  where: GitHub Actions run log + Sentry monitor history
  retention: 90 days (Actions retention default)
discoverability_test:
  command: gh run list --workflow scheduled-github-app-drift-guard.yml --limit 1 --json conclusion,createdAt
  expected_output: latest run conclusion is `success` AND createdAt within last 65 minutes
```

No `ssh` in `discoverability_test.command`. No new observability surface introduced.

## Risks & Sharp Edges

- **Suppress file MUST land in main before the next cron tick.** Cron fires hourly at `:00`; if the PR merges at e.g. `:55`, the suppress file must be on main when the `:00` tick checks out via sparse-checkout. Mitigation: workflow's `if: github.repository == 'jikig-ai/soleur'` + sparse-checkout already pulls `apps/web-platform/infra/MANIFEST_DRIFT_SUPPRESS_UNTIL` (workflow:70). The only timing risk is human-paced PR merge; auto-merge via `/soleur:ship` closes the window to ~2-5 min.
- **`2026-05-21T16:00:00Z` is ~24h ahead.** This is well inside the 30-day cap (workflow:317) but is the operator's deliberate window — if reconciliation takes longer, the follow-through issue tracks renewal/deletion. Do NOT padd to 30 days "for safety" — long suppress windows blind the guard.
- **Alphabetical key order.** The manifest's `default_permissions` keys are alphabetically sorted (`actions, administration, checks, contents, members, metadata, pull_requests`). New `secrets` belongs at the END of this ordering (not between `pull_requests` and "the next key" — there is no next key in the current file). The plan corrects the issue body's phrasing. Verified via `jq -e '.default_permissions | keys == ["actions","administration","checks","contents","members","metadata","pull_requests","secrets"]'` (AC above).
- **Docstring fix scope.** `bin/snapshot-github-app.sh` line 17 ONLY — do not touch the surrounding `chmod 600` or `shred -u` lines. The fix is one-token removal (`| base64 -d`); the script's executable code path uses `$KEY_FILE` (caller-prepared) and is unaffected by docstring drift. Confirmed by `Read` lines 12-19 and the executable body lines 26-85.
- **PR-vs-issue disambiguation on `#4170`.** The follow-through issue (Phase 4) references PM2 / the parity attestation downstream of this PR. Per the recent disambiguation learning, the planner verified `#4169` is an ISSUE (this one) and the follow-through will create a NEW issue (not paraphrase #4170 — that's a separate issue). `gh issue view 4169 --json title` confirmed at plan-write.
- **`Closes #4169` carries.** This PR's fix DOES land the manifest reconciliation pre-merge (manifest edit + suppress file). Auto-close at merge is correct (vs. `Ref #N` for ops-remediation PRs whose fix runs post-merge). Per the `ops-remediation Closes vs Ref` rule: this PR's load-bearing artifact (manifest + suppress) is committed AT merge; no post-merge `terraform apply` step gates the fix. `Closes` is correct.

## Test Strategy

No test additions. The change is data-config (`*.json`, single-line text file) + a comment-only docstring fix. Validation is mechanical (AC `jq -e` + `grep -qE`) and post-merge cron observation. The workflow's regex+cap enforcement (`scheduled-github-app-drift-guard.yml:313-322`) is the runtime gate — adding a unit test for the suppress-file format would duplicate the workflow's own check against synthetic input the workflow already accepts.

## Rollback

Trivial three-step rollback if drift-guard fires unexpected modes post-merge:

1. `git revert <merge-commit>` — manifest reverts to 7 keys, suppress file deleted, docstring restored to `| base64 -d`.
2. Drift-guard's next tick will fire `permission_drift` (because live still has `secrets: write`) — open a `ci/auth-broken` issue. This restores the pre-#4169 state, which is the pre-fix baseline.
3. Re-attempt with a tighter scope.

No external systems written, no migrations, no infra apply. Pure source-of-truth file revert.

## Plan-Time Verification (already run)

- `Read apps/web-platform/infra/github-app-manifest.json` — confirmed 7-key map, no `secrets`, `pull_requests` is last (matches issue claim modulo "next key" phrasing).
- `Read .github/workflows/scheduled-github-app-drift-guard.yml` — confirmed regex at line 313, max-window-s at line 317, sparse-checkout entry at line 70.
- `Read bin/snapshot-github-app.sh` — confirmed line 17 has the `| base64 -d` token in the docstring example.
- `gh issue view 4169` — confirmed issue body + comment; PM1 attestation verified live-App lacks parity.
- `gh issue list --label code-review --state open` — no overlap with edited paths.
- `ls apps/web-platform/infra/` — confirmed `MANIFEST_DRIFT_SUPPRESS_UNTIL` does not exist (fresh create, not edit).
- Today is 2026-05-20; suppress timestamp `2026-05-21T16:00:00Z` is ~24h ahead → within 30-day cap (workflow:317).

Sharp-edge note: per AGENTS.md, a plan whose `## User-Brand Impact` section is empty/TBD will fail `deepen-plan` Phase 4.6. This plan's section is populated with a concrete user-experience artifact (paper alert loop on PM2 for the ops surface only) and a `threshold: none` declaration. No sensitive-path diff (`*.json` config + ops docstring + workflow-controlled text file), so the `threshold: none` declaration does not require a scope-out bullet per preflight Check 6.1.
