---
name: feat-github-app-manifest-4115
issue: 4115
pr: 4121
branch: feat-github-app-manifest-4115
plan: knowledge-base/project/plans/2026-05-20-feat-github-app-manifest-plan.md
spec: knowledge-base/project/specs/feat-github-app-manifest-4115/spec.md
brainstorm: knowledge-base/project/brainstorms/2026-05-20-github-app-manifest-brainstorm.md
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
deferred_issues: [4145, 4146]
status: ready-for-work
---

# Tasks: feat-github-app-manifest-4115

Plan: `knowledge-base/project/plans/2026-05-20-feat-github-app-manifest-plan.md`

## Phase 0: Preconditions

- [x] 0.1 Snapshot live App via JWT path (Kieran P0-2 — PAT does NOT work for `gh api /app`)
  - [x] 0.1.1 Fetch PEM: `doppler secrets get GITHUB_APP_PRIVATE_KEY --plain -p soleur -c prd | base64 -d > /tmp/app.pem && chmod 600 /tmp/app.pem`
  - [x] 0.1.2 Read `APP_ID` from Doppler
  - [x] 0.1.3 Run `bin/snapshot-github-app.sh > /tmp/github-app-snapshot.json` (after task 5.3)
  - [x] 0.1.4 `shred -u /tmp/app.pem` after snapshot captured
- [x] 0.2 Verify `apps/web-platform/app/internal/` does NOT exist yet: `find apps/web-platform/app -maxdepth 2 -type d | grep internal` returns empty
- [x] 0.3 Verify operator-auth coverage: `grep -n 'matcher\|config' apps/web-platform/middleware.ts`; record whether `/internal/*` is gated
- [x] 0.4 Verify Article 30 PA-17 line numbers: `grep -n "^### Processing Activity 17" knowledge-base/legal/article-30-register.md` and `sed -n '299p' ... | wc -l` returns `1`
- [x] 0.5 Verify `apps/web-platform/tsconfig.json` has `resolveJsonModule: true` (Kieran P1-2)
- [x] 0.6 Capture pre-edit line numbers of `scheduled-github-app-drift-guard.yml` JWT-mint block (currently 119-150 per `scheduled-ruleset-bypass-audit.yml:106` citation) so Phase 3.3 can verify the citation post-edit (Kieran P0-3)

## Phase 1: Manifest JSON + parity test (RED → GREEN)

- [x] 1.1 Write parity test at `apps/web-platform/test/github-app-manifest-parity.test.ts`. Asserts:
  - [x] 1.1.1 File exists at `apps/web-platform/infra/github-app-manifest.json` and parses as JSON
  - [x] 1.1.2 `hook_attributes.url` template contains `/api/webhooks/github`
  - [x] 1.1.3 `callback_urls.length >= 3` (per `2026-05-04-github-app-callback-url-three-entries.md`)
  - [x] 1.1.4 `default_permissions.administration === "write"`
  - [x] 1.1.5 `public === false`
  - [x] 1.1.6 `setup_on_update === true`
  - [x] 1.1.7 Every `doppler_secret.github_app_*` in `github-app.tf` (5 resources) maps to a documented expected-output via regex grep
- [x] 1.2 Run parity test — confirm RED
- [x] 1.3 Write `apps/web-platform/infra/github-app-manifest.json` from the Phase 0.1 snapshot:
  - [x] 1.3.1 Copy `permissions` from snapshot → `default_permissions` in manifest verbatim
  - [x] 1.3.2 Copy `events` from snapshot → `default_events` in manifest verbatim (preserve ordering — see Sharp Edges)
  - [x] 1.3.3 Set `name`, `url`, `description` from snapshot
  - [x] 1.3.4 Set `public: false`, `setup_on_update: true`
  - [x] 1.3.5 Set `redirect_url: "https://${app_domain}/internal/github-app-init"` (literal `${app_domain}` placeholder; runtime-substituted)
  - [x] 1.3.6 Set `hook_attributes.url: "https://${app_domain}/api/webhooks/github"` (same placeholder)
  - [x] 1.3.7 Set `setup_url: "https://${app_domain}/dashboard/repos"`
  - [x] 1.3.8 `callback_urls` array with three entries from the 2026-05-04 learning, preserving snapshot ordering
  - [x] 1.3.9 OMIT `hook_attributes.secret` (Risks R6 — Soleur-managed via `random_id`; webhook secret pasted in Phase 5)
- [x] 1.4 Re-run parity test — confirm GREEN

## Phase 2: Static init page

- [ ] 2.1 Create `apps/web-platform/app/internal/github-app-init/page.tsx`
  - [ ] 2.1.1 `export const dynamic = "force-dynamic"` (Kieran P1-2)
  - [ ] 2.1.2 `export const metadata = { robots: { index: false } }` (defense-in-depth)
  - [ ] 2.1.3 Static `import manifest from "@/infra/github-app-manifest.json"`
  - [ ] 2.1.4 Page function: `async function Page({ searchParams }: { searchParams: Promise<{ code?: string; installation_id?: string; setup_action?: string }> })` then `const params = await searchParams` (Kieran P0-1 — Next.js 15 Promise contract)
  - [ ] 2.1.5 Substitute `${app_domain}` from `process.env.APP_DOMAIN` over the manifest's `redirect_url`, `hook_attributes.url`, and `setup_url` before form serialization
- [ ] 2.2 Render branching:
  - [ ] 2.2.1 If `params.code || params.installation_id || params.setup_action`: render informational view (NOT default form). View shows: "This URL was reached via GitHub callback; any temporary `code` is discarded unused. If you intended to install the App, visit `/dashboard/repos`. To populate Doppler, copy the 5 values from the App's settings page on GitHub." DOES NOT POST `code` anywhere (SpecFlow §3)
  - [ ] 2.2.2 Else: render the manifest-POST form with heading + narrative + `<form method="POST" action="https://github.com/settings/apps/new">` + `<input type="text" name="manifest" value="<JSON.stringify(manifest)>">` + submit button
- [ ] 2.3 Smoke-test locally:
  - [ ] 2.3.1 `bun --cwd apps/web-platform run dev`
  - [ ] 2.3.2 `curl -s http://localhost:3000/internal/github-app-init | grep -F 'name="manifest"'` (form HTML)
  - [ ] 2.3.3 `curl -s 'http://localhost:3000/internal/github-app-init?code=test-discard'` → informational view
  - [ ] 2.3.4 `curl -s 'http://localhost:3000/internal/github-app-init?installation_id=42&setup_action=install'` → informational view (proves the param-set widening)
- [ ] 2.4 Run `bun --cwd apps/web-platform run typecheck` — no TS errors

## Phase 3: Drift-guard extension (shared script + workflow + test)

- [ ] 3.1 Read `.github/workflows/scheduled-github-app-drift-guard.yml`, locate `RESPONSE_FILE` save site (post-line 218) and `record_failure` allowlist (~lines 98-117). Kieran P2-3: if `record_failure` has a mode allowlist, add `permission_drift`, `permission_unexpected_grant`, `response_shape_unparseable` to it
- [ ] 3.2 Write `bin/diff-github-app-manifest.sh` (shared script — Phase 3.3 contract). Reads `MANIFEST_FILE` + `RESPONSE_FILE` env vars:
  - [ ] 3.2.1 Response-shape sanity check: assert `.permissions` is object, `.events` is array. If malformed → exit non-zero, stdout: `response_shape_unparseable:<details>`
  - [ ] 3.2.2 Normalize permissions: `jq --sort-keys '.default_permissions' MANIFEST_FILE` vs `jq --sort-keys '.permissions' RESPONSE_FILE`
  - [ ] 3.2.3 Normalize events: `jq '.default_events | sort // []' MANIFEST_FILE` vs `jq '.events | sort // []' RESPONSE_FILE` (arrays — `--sort-keys` does NOT sort array elements)
  - [ ] 3.2.4 Diff direction classification:
    - Manifest declares > live grants → `permission_drift:<details>` (exit non-zero)
    - Live has > manifest declares → `permission_unexpected_grant:<details>` (exit non-zero)
  - [ ] 3.2.5 Match → exit 0 (silent)
  - [ ] 3.2.6 Add `set -euo pipefail`; pass `shellcheck`
- [ ] 3.3 First-merge suppression window — pick ONE mechanism and implement:
  - [ ] 3.3.1 EITHER: PR-label `manifest-drift-window` triggers 24h warning-only mode (workflow reads `gh pr list --search "<sha> in:body"` to find the merging PR's labels)
  - [ ] 3.3.2 OR: `MANIFEST_DRIFT_SUPPRESS_UNTIL` file committed with each manifest change (UTC ISO timestamp; workflow reads via `cat`)
  - [ ] 3.3.3 Either way: emit a visible step annotation/warning ("drift detected but suppressed until X") — silent pass would defeat Art. 33 framing
- [ ] 3.4 Extend `.github/workflows/scheduled-github-app-drift-guard.yml`:
  - [ ] 3.4.1 Add step AFTER the existing `id`/`client_id` immutability check, BEFORE `shred -u "$KEY_FILE"` cleanup
  - [ ] 3.4.2 Step invokes `bash bin/diff-github-app-manifest.sh`; captures stdout; on non-zero exit, parse `<mode>:<details>` and call `record_failure <mode> "<details>" <label>` per Phase 3.2 mode-classification (label: `ci/auth-broken` for `permission_drift`; `ci/guard-broken` for the other two)
  - [ ] 3.4.3 Update workflow's failure-mode comment header (lines 8-12) to enumerate 5 modes total
  - [ ] 3.4.4 Run `actionlint .github/workflows/scheduled-github-app-drift-guard.yml`
- [ ] 3.5 Sibling-workflow line-number sweep (Kieran P0-3): `grep -n "119-150" .github/workflows/scheduled-ruleset-bypass-audit.yml`; verify the cited drift-guard JWT-mint block range is still 119-150 post-edit. Update citation if shifted
- [ ] 3.6 Write `apps/web-platform/test/github-app-manifest-drift-guard.test.ts` (Kieran P1-3: mirror `apps/web-platform/test/github-app-drift-guard-contract.test.ts:3,375` `spawnSync` + skip-on-missing-jq pattern). 6-case matrix:
  - [ ] 3.6.1 Permission match → exit 0
  - [ ] 3.6.2 Manifest declares `administration:write`, live grants `administration:read` → exit non-zero, mode `permission_drift`
  - [ ] 3.6.3 Live has `events:["repository_dispatch"]` not in manifest → exit non-zero, mode `permission_unexpected_grant`
  - [ ] 3.6.4 Response `{message:"Not Found"}` → exit non-zero, mode `response_shape_unparseable`
  - [ ] 3.6.5 Empty arrays both sides → exit 0
  - [ ] 3.6.6 Same array content, different ordering → exit 0 (proves `jq sort` normalization)

## Phase 4: Legal register edits (atomic with surface change)

- [ ] 4.1 Edit `knowledge-base/legal/article-30-register.md` line 299: append TOM (13) as a SINGLE CONTINUOUS STRING with NO embedded newlines (Kieran P1-5). Text per plan Files-to-Edit §3. Verify post-edit: `sed -n '299p' knowledge-base/legal/article-30-register.md | wc -l` returns `1`
- [ ] 4.2 Edit `knowledge-base/legal/compliance-posture.md`: substitute literal `"GitHub App creation + webhook URL wiring"` → `"GitHub App creation via committed manifest (#4115) + webhook URL wiring"` (Kieran P1-4 confirmed clean substitution surface)

## Phase 5: Operator runbook + snapshot script + webhook-secret automation alternative

- [ ] 5.1 Write `knowledge-base/engineering/ops/runbooks/github-app-provisioning.md`:
  - [ ] 5.1.1 When-to-run section (first-time prd, future stg, App re-create, manifest-update follow-up)
  - [ ] 5.1.2 4-step operator flow with 5 Doppler pastes + 1 GitHub-side webhook-secret paste (SpecFlow §1+§6)
  - [ ] 5.1.3 Doppler key mapping table (5 keys)
  - [ ] 5.1.4 Webhook-secret automation alternative: `gh api -X PATCH /app/hook/config -f secret="$webhook_secret"` (via App-JWT)
  - [ ] 5.1.5 PEM `openssl base64 -A -in app.pem -out app.pem.b64` cross-platform one-liner (SpecFlow §6)
  - [ ] 5.1.6 Doppler-write CLI Leak-2 form: `doppler secrets set X --silent --no-interactive -p soleur -c prd <<< "$value" >/dev/null 2>&1`
  - [ ] 5.1.7 Manifest-drift discipline: operator updates manifest in follow-up PR within 1h of any GitHub-side permission change (or use `manifest-drift-window` label)
- [ ] 5.2 Document operator-only canonical list citation (case b OAuth-consent carve-out) in runbook preamble
- [ ] 5.3 Write `bin/snapshot-github-app.sh`:
  - [ ] 5.3.1 `set -euo pipefail` + `set -o pipefail`
  - [ ] 5.3.2 Reads `$APP_ID` from env, `/tmp/app.pem` from disk
  - [ ] 5.3.3 Mints 10-min RS256 JWT inline (mirror drift-guard `mint_jwt` at workflow lines 122-148 — base64url-encode header + payload via `base64 -w 0 | tr '+/' '-_' | tr -d '=\n'`)
  - [ ] 5.3.4 `curl -sS -H "Authorization: Bearer $JWT" -H "Accept: application/vnd.github+json" https://api.github.com/app | jq` → stdout
  - [ ] 5.3.5 Header comment: operator-only; CI uses workflow's own JWT-mint
  - [ ] 5.3.6 Pass `shellcheck`; `chmod +x`

## Phase 6: Verification + AC sweep

- [ ] 6.1 Run all new tests: `bun --cwd apps/web-platform test test/github-app-manifest-parity.test.ts test/github-app-manifest-drift-guard.test.ts` — all pass
- [ ] 6.2 Run typecheck: `bun --cwd apps/web-platform run typecheck` — clean
- [ ] 6.3 Run lint: `bun --cwd apps/web-platform run lint` on the changed files
- [ ] 6.4 `actionlint .github/workflows/scheduled-github-app-drift-guard.yml`
- [ ] 6.5 `shellcheck bin/diff-github-app-manifest.sh bin/snapshot-github-app.sh`
- [ ] 6.6 Verify AC1 through AC8b per the plan's Acceptance Criteria section
- [ ] 6.7 `/soleur:gdpr-gate` against the diff at /work Phase 2 exit per `hr-gdpr-gate-on-regulated-data-surfaces`
- [ ] 6.8 PR body wording: replace "measurable Art. 32 improvement" with "Art. 32 trade-off"; add Out-of-scope section listing #4145 + #4146 + their re-evaluation triggers
- [ ] 6.9 PR body uses `Ref #4115` (NOT `Closes #4115`) — Sharp Edge
- [ ] 6.10 Update PR description: link brainstorm + spec + plan paths

## Post-merge (operator)

- [ ] PM1 AC12: Run `gh api /app | jq --sort-keys .permissions` against `jq --sort-keys .default_permissions apps/web-platform/infra/github-app-manifest.json`; outputs must match
- [ ] PM2 First hourly drift-guard cron tick must NOT fire `permission_drift`. Check workflow run history; if it fires, the manifest authoring missed a snapshot detail
- [ ] PM3 First dogfood run of the new init page: visit `/internal/github-app-init` in prd → click button → verify GitHub's form pre-fills correctly. If verified, `gh issue close 4115 --reason completed`
- [ ] PM4 Verify webhook delivery to `apps/web-platform/app/api/webhooks/github/route.ts` returns 200 (signature verifies) post-webhook-secret paste

## Notes

- Brand-survival threshold: `single-user incident`. CPO sign-off required at plan time (carry-forward from brainstorm framing — see plan YAML frontmatter `requires_cpo_signoff: true`).
- `user-impact-reviewer` invoked at `/soleur:review` time.
- GDPR gate produced no findings at plan-time (no schema changes, no new vendors, no Art. 9 columns). Will re-run at /work Phase 2 exit.
- Deferred follow-ups: #4145 (Approach B downloadable-artifact callback), #4146 (synthetic-replay attestation cron). Re-evaluation triggers documented in each issue.
