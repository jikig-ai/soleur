---
feature: gh-app-drift-guard
issue: 3187
plan: knowledge-base/project/plans/2026-05-05-feat-github-app-drift-guard-plan.md
spec: knowledge-base/project/specs/feat-3187-gh-app-drift-guard/spec.md
status: tasks
date: 2026-05-05
brand_survival: single-user-incident
requires_cpo_signoff: true
---

# Tasks: GitHub App Drift-Guard

Derived from the finalized post-review plan. Phase numbering matches plan
phases. TDD-first per `cq-write-failing-tests-before` is exempt for this
infrastructure-only task tree (CI workflow + scripts + docs); the contract
test in Phase 2.1 IS the failing test, written alongside the workflow.

## Phase 1 — Workflow + secret shape

### 1.1 Extend secret-shape verifier

- [ ] **1.1.1** Read `apps/web-platform/scripts/verify-required-secrets.sh` to locate the existing `OAUTH_PROBE_GITHUB_CLIENT_ID` shape-check block (line ~141).
- [ ] **1.1.2** Add WARN-not-error shape check for `GH_APP_DRIFTGUARD_APP_ID`: numeric, 5–10 digits (`^[1-9][0-9]{4,9}$`). Override env var: `SOLEUR_SKIP_GH_APP_DRIFTGUARD_APP_ID_SHAPE`.
- [ ] **1.1.3** Add WARN-not-error shape check for `GH_APP_DRIFTGUARD_PRIVATE_KEY_B64`: base64-decodable AND decoded value starts with `-----BEGIN`. Override env var: `SOLEUR_SKIP_GH_APP_DRIFTGUARD_PEM_SHAPE`.
- [ ] **1.1.4** Locally run `bash apps/web-platform/scripts/verify-required-secrets.sh` (with both override env vars set, since secrets aren't in local Doppler yet). Confirm no breakage; both new checks fire WARN messages.

### 1.2 Create the workflow file

- [ ] **1.2.1** Create `.github/workflows/scheduled-github-app-drift-guard.yml`. Header comment block: name, brand-survival threshold, learning references (`drift-guard-self-silent-failures`, `github-secrets-prefix`), runbook link, plan/spec links.
- [ ] **1.2.2** `on:` block — `schedule: [cron: '0 * * * *']` and `workflow_dispatch: {}` only. NO other triggers.
- [ ] **1.2.3** `concurrency:` — `group: scheduled-github-app-drift-guard`, `cancel-in-progress: false`.
- [ ] **1.2.4** `permissions:` — `contents: read` and `issues: write` only.
- [ ] **1.2.5** Job `drift-check` on `ubuntu-latest`, `timeout-minutes: 5`. Job-level `if: github.repository == 'jikig-ai/soleur'` guard.
- [ ] **1.2.6** Step "Checkout (sparse, for notify-ops-email)": `actions/checkout` SHA-pinned, sparse-checkout `.github/actions`, `sparse-checkout-cone-mode: false`.
- [ ] **1.2.7** Step "Defensively create labels" — idempotent `gh label create ci/guard-broken … 2>/dev/null \|\| true` and same for `security/leak-suspected`. Env: `GH_TOKEN`, `GH_REPO`.
- [ ] **1.2.8** Step "Drift check" with `id: check`. Env: `APP_ID`, `PRIVATE_KEY_B64`, `EXPECTED_CLIENT_ID`. Body (all output tee'd to `$RUNNER_TEMP/step-output.log 2>&1`):
  - [ ] **1.2.8.1** `set -uo pipefail` (NOT `-e` — collect failure mode).
  - [ ] **1.2.8.2** Define `b64url()` helper using `base64 -w 0 | tr '+/' '-_' | tr -d '=\n'`.
  - [ ] **1.2.8.3** Define `record_failure() { local mode="$1"; local detail="$2"; local label="$3"; if [[ -z "$failure_mode" ]]; then failure_mode="$mode"; failure_detail="$detail"; failure_label="$label"; fi; }`. Initialize all three vars empty.
  - [ ] **1.2.8.4** Numeric APP_ID validation: `[[ "$APP_ID" =~ ^[1-9][0-9]+$ ]] || { record_failure ci_guard_broken "APP_ID not numeric" ci/guard-broken; }`.
  - [ ] **1.2.8.5** Base64-decode PEM: `printf '%s' "$PRIVATE_KEY_B64" | base64 -d > "$KEY_FILE" 2>/dev/null || { record_failure ci_guard_broken "(b64-decode failed)" ci/guard-broken; }`. Use `umask 077` before `mktemp`. Set `KEY_FILE=$(mktemp -p "$RUNNER_TEMP" app.pem.XXXXXX)`.
  - [ ] **1.2.8.6** Mask the decoded PEM: `while IFS= read -r line; do echo "::add-mask::$line"; done < "$KEY_FILE"` (line-by-line — `::add-mask::` is per-line).
  - [ ] **1.2.8.7** PEM shape check: `openssl rsa -in "$KEY_FILE" -check -noout 2>/dev/null || { record_failure ci_guard_broken "(PEM shape invalid)" ci/guard-broken; }`.
  - [ ] **1.2.8.8** JWT mint: build header + payload via `printf` and `jq -nc --argjson iat ... --argjson exp ... --argjson iss "$APP_ID" '{...}'`. Concat segments with `b64url` helper. Sign via `printf '%s' "$unsigned" | openssl dgst -sha256 -sign "$KEY_FILE" -binary | b64url`.
  - [ ] **1.2.8.9** Mask the JWT immediately: `echo "::add-mask::$JWT"`.
  - [ ] **1.2.8.10** `gh api /app` via curl with header file: `curl -s -w "\n%{http_code}" -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28" --header @<(printf 'Authorization: Bearer %s' "$JWT") https://api.github.com/app`. Capture body to `$RESPONSE_FILE`, HTTP code separately.
  - [ ] **1.2.8.11** Three-layer assertion (per AC5):
    - presence of `EXPECTED_CLIENT_ID` and `APP_ID` (else `ci/guard-broken` "expected-side empty")
    - presence of response `client_id` and `id`; on missing, locally decode JWT iss; if iss matches `APP_ID` → 401 routes to `ci/auth-broken` (App swap suspected); else `ci/guard-broken`
    - byte-equality of `(client_id, id)` against expected (mismatch → `ci/auth-broken`)
  - [ ] **1.2.8.12** Emit outputs: `failure_mode=`, `failure_detail=`, `failure_label=` to `$GITHUB_OUTPUT` (sanitize via `tr -d '\r\n\f\v\x7f\x85'` per oauth-probe pattern at L86-90).
- [ ] **1.2.9** Step "Leak tripwire" (`if: always()`). Env: `GH_TOKEN`, `GH_REPO`. Body:
  - [ ] `grep -E "(BEGIN [A-Z ]+PRIVATE KEY|eyJ[A-Za-z0-9_-]{20,})" "$RUNNER_TEMP/step-output.log"` — if exit 0 (match found): create `ci/guard-broken` + `security/leak-suspected` co-labeled issue with title `[security/leak-suspected] GitHub App drift-guard log-leak tripwire`. Body redacts the matched line. Then `exit 1`.
- [ ] **1.2.10** Step "File/update issue on failure" (`if: steps.check.outputs.failure_mode != ''`). Env: `GH_TOKEN`, `GH_REPO`, `FAILURE_MODE`, `FAILURE_DETAIL`, `FAILURE_LABEL`. Body:
  - Title prefix per `failure_label`: `[ci/auth-broken] GitHub App drift-guard fired` or `[ci/guard-broken] GitHub App drift-guard malfunctioned`.
  - Dedup search: `gh issue list --state open --label "$FAILURE_LABEL" --search 'in:title "drift-guard"' --json number --jq '.[0].number // empty'`.
  - If existing → `gh issue comment` with timestamped body; else `gh issue create` with body file (per oauth-probe pattern L444-485).
  - On `gh issue list` terminal failure (non-zero exit), file synthetic `ci/guard-broken` issue regardless.
- [ ] **1.2.11** Step "Notify ops on failure" with `id: notify`, `continue-on-error: true`, `if: steps.check.outputs.failure_mode != '' || steps.tripwire.outcome == 'failure'`. Uses `./.github/actions/notify-ops-email`. Inputs: `subject`, `body` (HTML), `resend-api-key`.
- [ ] **1.2.12** Step "Auto-close stale issues on green" (`if: steps.check.outputs.failure_mode == '' && steps.tripwire.outcome == 'success'`). Env: `GH_TOKEN`, `GH_REPO`. Search by `--label ci/auth-broken --search 'in:title "drift-guard"'`; close with comment.
- [ ] **1.2.13** Step "Cleanup PEM" (`if: always()`). Body: `rm -f "$RUNNER_TEMP/app.pem"* 2>/dev/null || true`.
- [ ] **1.2.14** Verify `gh workflow validate scheduled-github-app-drift-guard.yml` (or equivalent YAML lint) passes.

## Phase 2 — Contract test + docs + ownership

### 2.1 Contract test (Vitest)

- [ ] **2.1.1** Create `apps/web-platform/test/github-app-drift-guard-contract.test.ts`. Imports: `node:fs.readFileSync`, `node:crypto`, `node:child_process.spawnSync`, `vitest`. Resolve workflow path via `path.resolve(__dirname, '../../..', '.github/workflows/scheduled-github-app-drift-guard.yml')`.
- [ ] **2.1.2** Copy `extractFunctionBody(yaml, name)` helper verbatim from `apps/web-platform/test/oauth-probe-contract.test.ts:82-101`.
- [ ] **2.1.3** Export named constants for the load-bearing strings: `LEAK_TRIPWIRE_PEM_REGEX`, `LEAK_TRIPWIRE_JWT_REGEX`, `WORKFLOW_NAME`, `CONCURRENCY_GROUP`, three `ISSUE_TITLE_PREFIX_*` constants.
- [ ] **2.1.4** Tests for **trigger contract**: assert `on:` contains `schedule:` and `workflow_dispatch:`, asserts `.not.toContain('pull_request_target')`, `.not.toContain('workflow_run')`, exact YAML match for `pull_request` literal absent.
- [ ] **2.1.5** Tests for **permissions contract**: assert `permissions:` contains exactly `contents: read` and `issues: write`. Assert `.not.toContain('id-token:')`, `.not.toContain('actions: write')`, etc.
- [ ] **2.1.6** Test for **concurrency**: exact match of `group:` value AND `cancel-in-progress: false`.
- [ ] **2.1.7** Test for **workflow_dispatch actor guard**: assert presence of `if: github.repository ==` at job level.
- [ ] **2.1.8** Test for **leak-tripwire regex string equality**: assert both regex strings appear verbatim.
- [ ] **2.1.9** Test for **`record_failure` 3-output shape**: extract the function body via `extractFunctionBody`; assert it writes `failure_mode`, `failure_detail`, AND `failure_label` to `$GITHUB_OUTPUT`.
- [ ] **2.1.10** Test for **distinct title prefixes**: assert all three exact prefixes appear in the workflow text; assert no collision with oauth-probe's `[ci/auth-broken] Synthetic OAuth probe failed`.
- [ ] **2.1.11** Test for **idempotent label create**: assert `gh label create ci/guard-broken … 2>/dev/null || true` and same for `security/leak-suspected`.
- [ ] **2.1.12** Test for **defensive denials**: `expect(yaml).not.toContain('actions/upload-artifact')`. For each step that has `PRIVATE_KEY_B64` or `JWT` in env: `expect(stepBody).not.toContain('set -x')`.
- [ ] **2.1.13** **JWT decode-and-verify test** (per learning `2026-04-29-jwt-fixture-reminting-decode-verify.md`):
  - Generate ephemeral RSA keypair via `crypto.generateKeyPairSync('rsa', { modulusLength: 2048 })`.
  - Extract the workflow's mint shell logic via `extractFunctionBody`.
  - Spawn it as a child bash process (`spawnSync('bash', ['-c', script], { env: { APP_ID: '12345', PRIVATE_KEY_B64: <base64 of ephemeral PEM>, ... } })`).
  - Capture the minted JWT from stdout (workflow writes JWT to a known token in the script, OR test isolates the b64url helper directly).
  - Assert no `\n` appears in any of the three JWT segments (Kieran P1-1).
  - Decode header — `JSON.parse(Buffer.from(parts[0], 'base64url').toString())` — assert `alg === 'RS256'`, `typ === 'JWT'`.
  - Decode payload — assert `iss === 12345`, `exp - iat === 600`, `iat <= now <= exp`.
  - Verify signature: `crypto.createPublicKey(publicKeyPem)` + `crypto.verify('RSA-SHA256', Buffer.from(`${parts[0]}.${parts[1]}`), publicKey, Buffer.from(parts[2], 'base64url'))`.
  - Assert verify returns `true`.
- [ ] **2.1.14** **Negative-control fixture test**:
  - Inline JS string literal: synthesized `/app` response (no real client_id). Example: `const FAKE_APP_RESPONSE = '{"id":12345,"client_id":"Iv1.synthesized","slug":"test-app",...}'`.
  - `expect(FAKE_APP_RESPONSE).not.toMatch(LEAK_TRIPWIRE_PEM_REGEX)` AND `expect(FAKE_APP_RESPONSE).not.toMatch(LEAK_TRIPWIRE_JWT_REGEX)`.
- [ ] **2.1.15** Run the test suite: `cd apps/web-platform && npx vitest run github-app-drift-guard-contract`. Confirm all pass.

### 2.2 Operator runbook

- [ ] **2.2.1** Create `knowledge-base/engineering/ops/runbooks/github-app-drift.md`. Frontmatter: title, owner, related links.
- [ ] **2.2.2** Section "Bootstrap":
  - Where to find the App DB ID (GitHub UI: `/settings/apps/<slug>` → "App ID" field).
  - Canonical PEM base64 encoding command: `base64 -w 0 < app.pem > app.pem.b64` then store via `cat app.pem.b64 | doppler secrets set GH_APP_DRIFTGUARD_PRIVATE_KEY_B64 --plain -p soleur -c prd` (verify with `doppler secrets get … --plain | base64 -d | head -1`).
  - Canonical Doppler→GH sync: `doppler secrets get GH_APP_DRIFTGUARD_PRIVATE_KEY_B64 -p soleur -c prd --plain | gh secret set GH_APP_DRIFTGUARD_PRIVATE_KEY_B64`. Same for the App ID.
- [ ] **2.2.3** Section "Triage":
  - Single decision tree for `ci/auth-broken` (drift detected) vs `ci/guard-broken` (guard malfunctioning).
  - "Do not auto-escalate the user-facing OAuth probe; human triage decides whether to red the user probe."
- [ ] **2.2.4** Section "Rotation":
  - Key-rotation procedure if leak is suspected.
  - Steps: revoke old PEM in GitHub UI → generate new PEM → encode + store in Doppler → sync to GH workflow secret → manually trigger drift-guard to verify GREEN.
- [ ] **2.2.5** Honest cleanup-model note: `rm -f` on cloud-VM ephemeral runners; `shred` does not provide additional security on COW filesystems.

### 2.3 CODEOWNERS

- [ ] **2.3.1** Read existing `CODEOWNERS` to locate the `# Secret-scanning floor (gitleaks rule pack + workflow).` section.
- [ ] **2.3.2** Add line under that section: `/.github/workflows/scheduled-github-app-drift-guard.yml          @jeanderuelle`. Preserve column alignment.

### 2.4 Compliance posture

- [ ] **2.4.1** Read `knowledge-base/legal/compliance-posture.md`. Locate Vendor DPA table at L27-33.
- [ ] **2.4.2** Add Doppler row: `Doppler | AUTO (MSA + DPA addendum — verification pending) | 2026-05-05 | EU-US Data Privacy Framework | US | Holds GH_APP_DRIFTGUARD_PRIVATE_KEY_B64 (brand-survival credential); RBAC review tracked in #3228`.
- [ ] **2.4.3** Update `last_updated:` frontmatter to `2026-05-05`.

### 2.5 Repo labels (PR-time, before merge)

- [ ] **2.5.1** Run `gh label create ci/guard-broken --description "Synthetic CI guard malfunctioned" --color D93F0B`.
- [ ] **2.5.2** Run `gh label create security/leak-suspected --description "Workflow log scan suggests credential leak" --color B60205`.

## Phase 3 — Verify + review

### 3.1 Local verification

- [ ] **3.1.1** Run `bash scripts/test-all.sh` (or repo equivalent). All suites pass.
- [ ] **3.1.2** Run `npx tsc --noEmit` in `apps/web-platform/`. Clean.
- [ ] **3.1.3** Run `bash apps/web-platform/scripts/verify-required-secrets.sh` locally with both `SOLEUR_SKIP_GH_APP_DRIFTGUARD_*_SHAPE=1` set. Confirm no breakage of existing checks.

### 3.2 Multi-agent review

- [ ] **3.2.1** Push branch (`git push -u origin gh-app-drift-guard`) — reviewers analyze remote state per `rf-before-spawning-review-agents-push-the`.
- [ ] **3.2.2** Run `/soleur:review` on PR #3224. Explicitly request `user-impact-reviewer` per `single-user incident` threshold.
- [ ] **3.2.3** Resolve all review findings inline per `rf-review-finding-default-fix-inline`. Scope-out criteria per review skill §5.

### 3.3 PR finalization

- [ ] **3.3.1** Mark draft PR #3224 ready: `gh pr ready 3224`.
- [ ] **3.3.2** Verify PR body has `Ref #3187` (NOT `Closes #3187` — issue closes after AC21 verifies the live workflow run).
- [ ] **3.3.3** Apply PR labels: `priority/p2-medium`, `domain/engineering`, `type/feature`. Apply semver label per `/ship` defaults.

### 3.4 Pre-merge note

Pre-merge `workflow_dispatch` is INFEASIBLE for the new workflow (must
exist on default branch). The contract test (Phase 2.1) is the load-bearing
pre-merge gate. Live workflow verification is post-merge in Phase 4.

## Phase 4 — Post-merge operator (AC21)

### 4.1 Provision secrets in Doppler

- [ ] **4.1.1** Generate (or rotate) the GitHub App PEM via GitHub App settings page.
- [ ] **4.1.2** `base64 -w 0 < app.pem > app.pem.b64`.
- [ ] **4.1.3** `cat app.pem.b64 | doppler secrets set GH_APP_DRIFTGUARD_PRIVATE_KEY_B64 --plain -p soleur -c prd`.
- [ ] **4.1.4** `doppler secrets set GH_APP_DRIFTGUARD_APP_ID --plain -p soleur -c prd <<< "<numeric-app-id>"`.

### 4.2 Sync to GitHub workflow secrets

- [ ] **4.2.1** `doppler secrets get GH_APP_DRIFTGUARD_PRIVATE_KEY_B64 -p soleur -c prd --plain | gh secret set GH_APP_DRIFTGUARD_PRIVATE_KEY_B64`.
- [ ] **4.2.2** `doppler secrets get GH_APP_DRIFTGUARD_APP_ID -p soleur -c prd --plain | gh secret set GH_APP_DRIFTGUARD_APP_ID`.

### 4.3 Live verification (AC21)

- [ ] **4.3.1** `gh workflow run scheduled-github-app-drift-guard.yml`. Capture run ID.
- [ ] **4.3.2** Poll: `gh run view <id> --json status,conclusion`. Wait for completion.
- [ ] **4.3.3** Verify GREEN: `conclusion === 'success'`.
- [ ] **4.3.4** Verify no leak-tripwire fire: no `[security/leak-suspected]` issue created.
- [ ] **4.3.5** Verify both assertions passed: inspect workflow logs for `client_id matches expected` and `id matches expected`.
- [ ] **4.3.6** If GREEN and verified, close issue #3187: `gh issue close 3187 --comment "Live workflow run verified GREEN — see run <url>."` per `cq-for-type-ops-remediation-classification-ops`.

### 4.4 Post-deploy follow-up

- [ ] **4.4.1** Confirm hourly cron fires within 60-90 minutes of merge. Inspect `gh run list -w scheduled-github-app-drift-guard.yml --limit 3`.
- [ ] **4.4.2** Update `knowledge-base/legal/compliance-posture.md` Doppler row when DPA addendum verification completes (tracked under #3228).
