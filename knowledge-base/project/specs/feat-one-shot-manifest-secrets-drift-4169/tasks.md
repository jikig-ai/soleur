---
plan: knowledge-base/project/plans/2026-05-20-fix-manifest-drift-secrets-permission-plan.md
issue: 4169
lane: single-domain
---

# Tasks — fix manifest drift (secrets: write) + PM2 suppress

## Phase 1 — Manifest edit

- [x] 1.1 Read `apps/web-platform/infra/github-app-manifest.json` (mandatory before Edit per AGENTS.md).
- [x] 1.2 Insert `"secrets": "write"` as the new last entry in `default_permissions` (after `pull_requests`). Add trailing comma to the existing `pull_requests` line; no comma on `secrets` (JSON-spec).
- [x] 1.3 Verify with `jq -e '.default_permissions.secrets == "write"' apps/web-platform/infra/github-app-manifest.json`.
- [x] 1.4 Verify with `jq -e '.default_permissions | length == 8' apps/web-platform/infra/github-app-manifest.json`.
- [x] 1.5 Verify with `jq -e '.default_permissions | keys == ["actions","administration","checks","contents","members","metadata","pull_requests","secrets"]' apps/web-platform/infra/github-app-manifest.json`.

## Phase 2 — Suppress file create

- [x] 2.1 Create `apps/web-platform/infra/MANIFEST_DRIFT_SUPPRESS_UNTIL` with single line content `2026-05-21T16:00:00Z` (LF terminator, no trailing whitespace, no BOM, mode 0644).
- [x] 2.2 Verify regex match: `grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' apps/web-platform/infra/MANIFEST_DRIFT_SUPPRESS_UNTIL`.
- [x] 2.3 Verify cap-honor: `(( $(date -d "$(cat apps/web-platform/infra/MANIFEST_DRIFT_SUPPRESS_UNTIL)" -u +%s) - $(date -u +%s) < 30*24*3600 ))`.

## Phase 3 — Docstring fix in snapshot script

- [x] 3.1 Read `bin/snapshot-github-app.sh` (line 17 + surrounding context).
- [x] 3.2 Edit line 17 docstring: drop the literal `| base64 -d` from the example. Keep `chmod 600` and `shred -u` adjacent comment lines intact.
- [x] 3.3 Verify with `grep -F '| base64 -d' bin/snapshot-github-app.sh` returning zero matches.
- [x] 3.4 Verify `bash -n bin/snapshot-github-app.sh` exits 0 (syntax unchanged).

## Phase 4 — Commit + PR

- [x] 4.1 Stage: `git add apps/web-platform/infra/github-app-manifest.json apps/web-platform/infra/MANIFEST_DRIFT_SUPPRESS_UNTIL bin/snapshot-github-app.sh`.
- [x] 4.2 Commit with message `fix(github-app): manifest secrets:write parity + PM2 suppress window`.
- [x] 4.3 Push branch.
- [ ] 4.4 Open PR with body containing `Closes #4169` and a one-paragraph summary referencing the live-App parity attestation in #4169.

## Phase 5 — Post-merge follow-through (automation via /ship phase 7.5)

- [ ] 5.1 (Operator) After merge: confirm next drift-guard tick emits `::warning::Manifest drift detected but suppressed until 2026-05-21T16:00:00Z` and does NOT open a `ci/auth-broken` issue.
- [ ] 5.2 (Automation) /ship phase 7 step 3.5 files follow-through issue tracking SUPPRESS file deletion.
- [ ] 5.3 (Future, post-reconciliation window) Delete `apps/web-platform/infra/MANIFEST_DRIFT_SUPPRESS_UNTIL` once a drift-guard tick passes green without it. Tracked separately.
