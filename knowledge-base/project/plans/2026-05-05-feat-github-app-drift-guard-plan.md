---
date: 2026-05-05
issue: 3187
related_issues: [3181, 3183, 1784, 2887, 3121, 3160, 3226, 3227, 3228, 3229, 3230]
brand_survival: single-user-incident
requires_cpo_signoff: true
type: feature
classification: ci-workflow + secret + content
brainstorm: knowledge-base/project/brainstorms/2026-05-05-github-app-drift-guard-brainstorm.md
spec: knowledge-base/project/specs/feat-3187-gh-app-drift-guard/spec.md
status: plan
plan_review: 2026-05-05 (dhh + kieran + simplicity, applied)
---

# Plan: GitHub App Drift-Guard via JWT-signed `gh api /app` Snapshot

## Overview

Build a scheduled GitHub Actions workflow that mints a GitHub App JWT
hourly, calls `gh api /app`, and asserts the response identity (`client_id`
+ `id`) matches expected sentinel values. Catches H_C-class drift (someone
swaps the entire GitHub App while keeping the 3 callback URLs the existing
15-minute OAuth probe verifies — see PR #3181). Brand-survival threshold:
single-user incident. CPO sign-off carried from brainstorm Phase 0.5;
`user-impact-reviewer` invoked at PR review time.

## User-Brand Impact

- **If this lands broken, the user experiences:** A swapped GitHub App goes
  undetected. Users sign in via GitHub OAuth to an attacker-controlled flow
  and surrender credentials/repo-read scopes that GitHub mints to the
  attacker's App. The user-facing 3-URL probe stays GREEN throughout.
- **If this leaks, the user's data is exposed via:** Workflow-log capture
  of the GitHub App PEM private key (or a freshly-minted JWT). An attacker
  with the PEM mints installation tokens against every repo our App is
  installed on → controller-side unauthorized access to user repo content,
  metadata, and any data accessible via the App's installed scopes.
  Reportable Article 33 breach under GDPR Policy §11 (72-hour CNIL clock
  starts at awareness, not confirmation).
- **If sentinels rotate ahead of GitHub-side OAuth (App-identity rotation):**
  Drift-guard mints JWTs against the new App identity (App-Y), GitHub
  returns App-Y's metadata, byte-equality assertions go GREEN — while
  users still hit App-X's consent screen and break their sign-in. Up to
  60 minutes of false-green coverage during which real user sign-ins
  fail. **Mitigation:** runbook §"App-identity rotation (replacing the
  App entirely)" locks the order: GitHub-side OAuth deploy and oauth-probe
  green check FIRST, then sentinel update. Identity rotation is rare;
  key rotation (more common) does not have this trap because the App's
  client_id and database ID are unchanged.
- **If GitHub Actions cron is degraded ("guard-itself-dark"):** the guard
  fails to fire, drift goes undetected, and auto-close-on-green leaves
  the last tracking issue closed — removing the only signal that
  something was being watched. **Disposition:** out of scope for this
  PR. Cross-workflow heartbeat coverage (drift-guard, oauth-probe,
  cf-token-expiry-check, terraform-drift, canary-bundle-claim-check)
  needs its own architectural-pivot design cycle; tracked in
  [#3236](https://github.com/jikig-ai/soleur/issues/3236) (architectural-pivot
  scope-out, code-simplicity-reviewer co-signed). Drift-guard's 60-min
  worst-case detection window is preserved as long as Actions is
  operating; heartbeat is a strict superset, not a regression
  introduced by this PR.
- **Brand-survival threshold:** `single-user incident`.

CPO sign-off carried from brainstorm Phase 0.5 (BUILD, P3→P2, Phase 4
sequencing). `user-impact-reviewer` invoked at review-time per the
review skill's conditional-agent block.

## Research Reconciliation — Spec vs. Codebase

The repo-research-analyst surfaced material gaps between the spec and the
actual repo state. These reconciliations are baked into the plan; the
spec is authoritative for goals and the reconciled values are
authoritative for implementation.

| Spec claim | Codebase reality | Plan response |
|---|---|---|
| Workflow secret `GITHUB_APP_PRIVATE_KEY_B64` | `gh secret set GITHUB_*` returns HTTP 422 — GitHub reserves the prefix (learning `2026-05-04-github-secrets-cannot-start-with-github-prefix.md`). | Rename to `GH_APP_DRIFTGUARD_PRIVATE_KEY_B64`. Functional naming. |
| Workflow secret `GITHUB_APP_DATABASE_ID` | Same prefix rejection. Server-side `apps/web-platform/server/github-app.ts:8` reads `process.env.GITHUB_APP_ID` (runtime env, separate from workflow secrets). | Rename to `GH_APP_DRIFTGUARD_APP_ID`. Document in runbook that workflow secret and server-side env var hold the same value in different scopes. |
| Doppler→GH workflow-secret sync | No automated script exists. Pattern is manual `doppler secrets get … \| gh secret set`. | Document the manual command in the runbook. Automation deferred (separate scope). |
| `ci/auth-broken` label exists | Confirmed; `ci/guard-broken` and `security/leak-suspected` do NOT exist. `gh issue create --label X` returns HTTP 422 if missing. | Idempotent `gh label create … 2>/dev/null \|\| true` in workflow per `scheduled-oauth-probe.yml:436-438`. |
| Snapshot-leak-floor sequencing concern | #3121 (Gitleaks floor) closed 2026-05-04. Our leak-tripwire does NOT upload artifacts and does NOT persist captured logs outside the ephemeral runner. | Sequencing concern does not apply. Note for traceability. |
| `notify-ops-email` available | Confirmed at `.github/actions/notify-ops-email/action.yml`. Inputs: `subject`, `body` (HTML), `resend-api-key`. WARN-not-fail on non-2xx. | Wrap in `continue-on-error: true` with `id: notify`. No cascade — failed email + filed-issue is sufficient. |
| `oauth-probe-contract.test.ts` is the test pattern | Confirmed. Uses raw text grep + custom `extractFunctionBody` (lines 82-101). NO `js-yaml` parsing. | Mimic verbatim. Mirror sentinel constants and regex helpers. |
| `gh api` accepts JWT auth | **No.** `gh api` passes `GH_TOKEN` as `Authorization: token <value>`; GitHub's `/app` requires `Authorization: Bearer <jwt>`. | Use `curl` directly with JWT in env (header file via `--header @<(printf '...')`). Drop the `gh api /app` line. |
| `openssl base64 -A` is safe for base64url | **No.** Some openssl builds emit a trailing newline that `tr -d '='` does not strip → JWT segments contain `\n` → 401. | Use `base64 -w 0 \| tr '+/' '-_' \| tr -d '=\n'`. coreutils `base64` is on `ubuntu-latest`. |
| `shred -u` provides PEM cleanup | Cloud-VM ephemeral runner FS makes `shred` theatrical (COW filesystem; underlying blocks not addressable). `::add-mask::` and the leak-tripwire are the real defenses. | Use `rm -f`. Honest runbook wording. |

## Files to Create

| Path | Purpose |
|---|---|
| `.github/workflows/scheduled-github-app-drift-guard.yml` | The workflow. Hourly cron + `workflow_dispatch`. |
| `apps/web-platform/test/github-app-drift-guard-contract.test.ts` | Vitest contract test locking workflow invariants. |
| `knowledge-base/engineering/ops/runbooks/github-app-drift.md` | Operator runbook: bootstrap, triage, rotation. |

## Files to Edit

| Path | Edit |
|---|---|
| `apps/web-platform/scripts/verify-required-secrets.sh` | WARN-not-error shape checks for `GH_APP_DRIFTGUARD_APP_ID` (numeric, 5–10 digits) and `GH_APP_DRIFTGUARD_PRIVATE_KEY_B64` (base64-decodable, decodes to a string starting with `-----BEGIN`). Override env vars `SOLEUR_SKIP_GH_APP_DRIFTGUARD_APP_ID_SHAPE` and `SOLEUR_SKIP_GH_APP_DRIFTGUARD_PEM_SHAPE`. Mirror the existing `OAUTH_PROBE_GITHUB_CLIENT_ID` pattern at line 141. |
| `CODEOWNERS` | Add `/.github/workflows/scheduled-github-app-drift-guard.yml @jeanderuelle` under the existing `# Secret-scanning floor` section. |
| `knowledge-base/legal/compliance-posture.md` | Add Doppler row to Vendor DPA table (after L33). Update `last_updated:` to `2026-05-05`. Body note references #3228 for DPA verification follow-up. |

**No edits to** `apps/web-platform/server/github-app.ts` — runtime helper is
read-only; workflow uses inline openssl, not the server-side helper.

## Open Code-Review Overlap

1 overlap: **#3160** (rename-laundering CI guard for secret-scanning floor)
references `CODEOWNERS` informationally. **Disposition: acknowledge** —
#3160 adds a CI job inside `secret-scan.yml`; this plan adds one
CODEOWNERS line for the new workflow. No semantic conflict.

## Acceptance Criteria

### Pre-merge (PR)

**Workflow surface lockdown.**

- [ ] **AC1** Workflow `on:` is exactly `schedule: [cron: '0 * * * *']` and `workflow_dispatch:` (NO `pull_request*`, NO `workflow_run`). `permissions:` is exactly `contents: read` and `issues: write`. `concurrency: { group: scheduled-github-app-drift-guard, cancel-in-progress: false }`. NO `actions/upload-artifact` step. All third-party Actions SHA-pinned with version comment. Job-level `if: github.repository == 'jikig-ai/soleur'` guard on `workflow_dispatch` runs. (TR1, TR2, TR3, TR5, TR6, SpecFlow F6, F7)

**JWT mint, API call, assertion.**

- [ ] **AC2** PEM secret-handling: `[[ "$APP_ID" =~ ^[1-9][0-9]+$ ]]` validation BEFORE jq-templating the iss claim (Kieran P0-1). `printf '%s' "$KEY_B64" \| base64 -d` decode; on failure, `record_failure ci_guard_broken "(b64-decode failed)" "ci/guard-broken"` and exit 0. `openssl rsa -in "$KEY_FILE" -check -noout` shape check; on failure, `record_failure ci_guard_broken "(PEM shape invalid)" "ci/guard-broken"`. PEM written to `$RUNNER_TEMP/app.pem` with `umask 077`. `::add-mask::` called on the decoded PEM AND the minted JWT before any subsequent step. PEM/JWT passed to subprocesses via `env:`, never argv. (TR4, FR2, SpecFlow F1)
- [ ] **AC3** Inline RS256 JWT mint with `iat = now - 60`, `exp = now + 540`. base64url helper: `base64 -w 0 \| tr '+/' '-_' \| tr -d '=\n'` (Kieran P1-1). Signature via `openssl dgst -sha256 -sign "$KEY_FILE" -binary`. (FR3, SpecFlow F8)
- [ ] **AC4** `gh api /app` call uses **curl** (not `gh api` — Kieran P1-2: gh CLI does not accept JWT bearer auth). JWT passed via `--header @<(printf 'Authorization: Bearer %s' "$JWT")` so the JWT never appears in argv. Body to `$RESPONSE_FILE`, HTTP code captured. (Learning `token-env-var-not-cli-arg`)
- [ ] **AC5** Three-layer assertion: (a) presence of `EXPECTED_CLIENT_ID` + `APP_ID` env vars (else `ci/guard-broken` "expected-side empty"); (b) presence of response `client_id` + `id` (else: locally decode JWT iss; if iss matches `APP_ID`, route 401 to `ci/auth-broken` per SpecFlow F2; else `ci/guard-broken`); (c) byte-equality of both pairs (mismatch → `ci/auth-broken`). (FR5, FR4, SpecFlow F2)

**Failure routing and dedup.**

- [ ] **AC6** `record_failure` helper writes THREE outputs: `failure_mode`, `failure_detail`, `failure_label` (Kieran P0-2: don't conflate label with mode). `failure_mode` is a snake_case key (e.g., `client_id_drift`, `ci_guard_broken`); `failure_label` is the GitHub label (`ci/auth-broken` or `ci/guard-broken`). First-failure-wins per oauth-probe pattern at L70-78.
- [ ] **AC7** Three-way label routing: `ci/auth-broken` (drift) / `ci/guard-broken` (malfunction) / `security/leak-suspected` (additionally co-applied with `ci/guard-broken` when leak-tripwire fires). Both new labels (`ci/guard-broken`, `security/leak-suspected`) defensively created via `gh label create … 2>/dev/null \|\| true` workflow step AND created in repo at PR-time. Distinct title prefixes to avoid collision with oauth-probe (Kieran P1-3): `[ci/auth-broken] GitHub App drift-guard fired` / `[ci/guard-broken] GitHub App drift-guard malfunctioned` / `[security/leak-suspected] GitHub App drift-guard log-leak tripwire`.
- [ ] **AC8** Issue dedup: `gh issue list --state open --label "$failure_label" --search 'in:title "drift-guard"' --json number --jq '.[0].number // empty'` (matches oauth-probe pattern; scopes to drift-guard via title token). Comment-or-create branching. On terminal `gh issue list` failure, file synthetic `ci/guard-broken` issue. (No retry-with-backoff per DHH cut: hourly cron self-heals; `set -e` cascades the failure; `notify-ops-email` step still fires.)

**Leak tripwire and cleanup.**

- [ ] **AC9** Tee step output to `$RUNNER_TEMP/step-output.log 2>&1`. Post-step (`if: always()`) grep with anchored regex: `BEGIN [A-Z ]+PRIVATE KEY` AND `eyJ[A-Za-z0-9_-]{20,}`. On match: fail run + create `ci/guard-broken` + `security/leak-suspected` co-labeled issue (defensively co-create label). (FR8, SpecFlow F5, F9)
- [ ] **AC10** Cleanup step (`if: always()`): `rm -f "$RUNNER_TEMP/app.pem" 2>/dev/null \|\| true`. (Kieran P1-4: `shred` is theater on cloud-VM runners; document honestly in runbook.)

**Notify path and auto-close.**

- [ ] **AC11** `notify-ops-email` invoked on failure with `id: notify` and `continue-on-error: true`. (No cascade per DHH cut: failed email + filed GitHub issue is the operator signal; second issue would be paranoia about paranoia.)
- [ ] **AC12** Auto-close stale issues on green runs (matches oauth-probe pattern at L500-522). Search uses the same title token `drift-guard` to scope.

**Scripts, ownership, compliance posture.**

- [ ] **AC13** `verify-required-secrets.sh` extended with WARN-not-error shape checks for both new secrets per "Files to Edit". (TR9)
- [ ] **AC14** CODEOWNERS line added per "Files to Edit". Branch-protection enforcement remains an operator follow-up (existing CODEOWNERS L4-6 documents this). (TR6)
- [ ] **AC15** Doppler row added to `compliance-posture.md` Vendor DPA table; `last_updated:` bumped. (G5)
- [ ] **AC16** Two new labels created in repo at PR-time: `gh label create ci/guard-broken --description "Synthetic CI guard malfunctioned" --color D93F0B && gh label create security/leak-suspected --description "Workflow log scan suggests credential leak" --color B60205`.

**Contract test (load-bearing pre-merge gate).**

- [ ] **AC17** `apps/web-platform/test/github-app-drift-guard-contract.test.ts` uses raw text grep + `extractFunctionBody` (mirror oauth-probe-contract.test.ts:82-101). Locks the load-bearing invariants:
  - Allowlist of `on:` triggers; denylist of `pull_request_target` / `workflow_run` / `pull_request`
  - Exact `permissions:` block (`contents: read`, `issues: write` only)
  - `concurrency` group + `cancel-in-progress: false`
  - Job-level `workflow_dispatch` actor guard (`github.repository ==`)
  - Leak-tripwire: regex string equality for BOTH `BEGIN [A-Z ]+PRIVATE KEY` and `eyJ[A-Za-z0-9_-]{20,}` patterns
  - `record_failure` helper writes 3 outputs (`failure_mode`, `failure_detail`, `failure_label`)
  - Three distinct title prefixes (no collision with oauth-probe)
  - Idempotent `gh label create … \|\| true` for both new labels
  - Defensive: NO `actions/upload-artifact`; NO `set -x` in steps with PEM/JWT in env
  - **JWT decode-and-verify** (per learning `2026-04-29-jwt-fixture-reminting-decode-verify.md`): generate ephemeral RSA keypair via `node:crypto.generateKeyPairSync` (Kieran P2-1: stdlib, no `jose` dep); extract the workflow's mint shell logic via `extractFunctionBody`; spawn it as a child process with the ephemeral key; `crypto.createPublicKey` + `crypto.verify('RSA-SHA256', ...)` to assert signature validity, alg=RS256, iss matches input, exp - iat == 600. Asserts no `\n` in any of the three JWT segments (Kieran P1-1 verification).
  - **Negative-control fixture** as inline JS string literal in the test file (per `cq-test-fixtures-synthesized-only`; Kieran P2-2): a synthesized `/app` response (no real client_id) does NOT trip the leak-tripwire regex.

**Review and verification.**

- [ ] **AC18** `bash scripts/test-all.sh` and `npx tsc --noEmit` clean.
- [ ] **AC19** Operator runbook `knowledge-base/engineering/ops/runbooks/github-app-drift.md` published with three sections: (1) **Bootstrap** — where to find App DB ID (`/settings/apps/<slug>` → "App ID"), canonical PEM base64 encoding (`base64 -w 0 < app.pem | doppler secrets set GH_APP_DRIFTGUARD_PRIVATE_KEY_B64 --plain`), Doppler→GH sync command (`doppler secrets get GH_APP_DRIFTGUARD_PRIVATE_KEY_B64 -p soleur -c prd --plain | gh secret set GH_APP_DRIFTGUARD_PRIVATE_KEY_B64`); (2) **Triage** — single decision tree on `ci/auth-broken` vs `ci/guard-broken`; "do not auto-escalate user-facing OAuth probe; human triage decides"; (3) **Rotation** — key-rotation procedure if leak is suspected. Bootstrap section addresses SpecFlow F10 + F11.
- [ ] **AC20** `/soleur:review` invoked with `user-impact-reviewer` engaged per `single-user incident` threshold.

### Post-merge (operator)

- [ ] **AC21** Manually trigger workflow once (`gh workflow run scheduled-github-app-drift-guard.yml`) per `wg-after-merging-a-pr-that-adds-or-modifies`. Verify GREEN, both assertions pass, no leak-tripwire fire. (All of: secret provisioning, sync, runbook bootstrap follow the AC19 runbook — they are operator activities documented there, not PR-checklist items.)

## Implementation Phases

### Phase 1 — Workflow + secret shape

1. Add WARN-not-error shape checks to `apps/web-platform/scripts/verify-required-secrets.sh` mirroring the existing `OAUTH_PROBE_GITHUB_CLIENT_ID` pattern at line 141.
2. Create `.github/workflows/scheduled-github-app-drift-guard.yml`. Single drift-check step contains: numeric APP_ID validation → base64-decode PEM with mktemp + umask 077 → `::add-mask::` PEM → `openssl rsa -check` shape → inline JWT mint with `base64 -w 0 | tr '+/' '-_' | tr -d '=\n'` helper → `::add-mask::` JWT → `curl` to `https://api.github.com/app` with `--header @<(printf ...)` → three-layer assertion → `record_failure` writing 3 outputs. Tee whole step to `$RUNNER_TEMP/step-output.log`. Defensively-create-labels step before drift-check. Leak-tripwire post-step (`if: always()`). Issue file/update step using `failure_label` output. `notify-ops-email` step with `id: notify`, `continue-on-error: true`. Auto-close-on-green step. Cleanup step (`if: always()`, `rm -f`).

### Phase 2 — Contract test + docs + ownership

1. Create `apps/web-platform/test/github-app-drift-guard-contract.test.ts` per AC17 spec. Use `extractFunctionBody` from oauth-probe pattern; ephemeral RSA via `node:crypto`; inline negative-control fixture string literal.
2. Create `knowledge-base/engineering/ops/runbooks/github-app-drift.md` with three sections per AC19.
3. Edit `CODEOWNERS` per "Files to Edit".
4. Edit `knowledge-base/legal/compliance-posture.md` per "Files to Edit".
5. Create the two new labels in repo (`gh label create …`).

### Phase 3 — Verify + review

1. `bash scripts/test-all.sh`, `npx tsc --noEmit` (AC18).
2. `bash apps/web-platform/scripts/verify-required-secrets.sh` locally — shape checks added without breaking existing.
3. `/soleur:review` (AC20).
4. Pre-merge verification of the workflow itself is INFEASIBLE via `gh workflow run --ref` (workflow must exist on default branch first per AGENTS.md sharp-edge `cq-when-a-plan-prescribes-pre-merge`). Live verification is post-merge AC21.
5. PR body uses `Ref #3187`, NOT `Closes #3187` — issue closes after AC21 verifies the live workflow run, per `cq-for-type-ops-remediation-classification-ops`.

## Test Strategy

- **Vitest contract test** is the load-bearing pre-merge gate. Locks exact YAML strings (regex patterns, permissions, trigger block, helper output shape).
- **JWT mint correctness** verified via decode-and-verify with ephemeral keypair (per `jwt-fixture-reminting-decode-verify` learning) — catches `openssl dgst` flag drift, `--argjson` typing, base64url segment newline.
- **Negative-control fixture** is an inline JS string literal in the test file; the synthesized `/app` response does NOT trip the leak-tripwire regex.
- **Pre-merge live workflow run is INFEASIBLE** (workflow not on default branch). First live run is post-merge AC21.

## Risks

| Risk | Mitigation |
|---|---|
| `notify-ops-email` itself broken (SMTP creds drifted) | Operator still sees the GitHub issue (created via `issues: write`, no SMTP dependency). The notify failure does not mask the primary signal. |
| Leak-tripwire false-positive on legit `/app` response field | Negative-control fixture in contract test (AC17). Regex anchored to PEM blocks and JWT-prefix shape, not arbitrary `eyJ` substrings. |
| Local pre-tool hook silently blocks `.github/workflows/*` edits during /work | Documented in learning `2026-03-18-security-reminder-hook-blocks-workflow-edits.md`; /work skill operator handles. |
| Concurrency-group name collision across workflows | Quick grep at /work time; contract test asserts the exact group string. |

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6.
- The leak-tripwire regex is intentionally anchored. A future PR that loosens it to `BEGIN.*KEY` (catches public key) or narrows it to literal `BEGIN RSA PRIVATE KEY` (misses PKCS#8) silently weakens the guard. Contract test asserts exact regex strings (AC17); CODEOWNERS requires second-reviewer (AC14).
- Workflow-secret naming must not start with `GITHUB_*` (HTTP 422). This plan uses `GH_APP_DRIFTGUARD_*`. Anyone proposing to "harmonize" should be redirected to `2026-05-04-github-secrets-cannot-start-with-github-prefix.md`.
- `gh api` does NOT accept JWT bearer auth — this plan uses `curl` directly. Anyone replacing curl with `gh api` will silently 401.
- `openssl base64 -A` trails newline on some builds — this plan uses `base64 -w 0 | tr '+/' '-_' | tr -d '=\n'`. The `-d=` strip is load-bearing AND the `\n` strip is load-bearing. Don't simplify the helper without re-verifying.
- `tee`-captured step output goes to `$RUNNER_TEMP`. The ephemeral runner FS is destroyed at end-of-run. If anyone later adds `actions/upload-artifact` to upload the tee'd file for "debugging", that upload would re-create the leak class the tripwire is meant to detect. Contract test AC17 asserts no `actions/upload-artifact`.
- `if: failure()` does NOT fire when the previous step has `continue-on-error: true`. The notify step uses `continue-on-error: true`; the auto-close-on-green step uses `if: steps.check.outputs.failure_mode == ''` (not `if: success()`).
- `shred -u` is theater on cloud-VM runners. We use `rm -f` and document the honest cleanup model in the runbook.
- **Pre-merge verification of a NEW workflow is impossible** via `gh workflow run --ref feature-branch`. The workflow file must exist on the default branch first. Verification is post-merge (AC21).

## Domain Review

**Domains relevant:** Engineering, Legal, Product, Operations

(Marketing, Sales, Finance, Support not relevant — internal CI/security
infrastructure with no user-facing surface.)

### Engineering (CTO) — brainstorm carry-forward

**Status:** reviewed (carried from brainstorm 2026-05-05)
**Assessment:** BUILD now with scope changes. Inline openssl JWT mint
(no third-party Action). Base64-PEM in Doppler. Assert client_id + id.
Hourly cadence. Three-way label split. Self-silent-failure surface
enumerated and addressed via explicit presence checks on both sides
of every comparison.

### Legal (CLO) — brainstorm carry-forward

**Status:** reviewed (carried from brainstorm 2026-05-05)
**Assessment:** GO with conditions. Drift-guard is itself a GDPR §299
compliance control. Leak-tripwire + trigger-lockdown + permissions
minimization non-negotiable. Doppler row in `compliance-posture.md` is
blocking. Pre-written user-comm template deferred to #3227.

### Product (CPO) — brainstorm carry-forward (sign-off)

**Status:** reviewed (carries plan-time `requires_cpo_signoff: true`)
**Assessment:** BUILD, P3 → P2, attach to Phase 4. Sequence BEFORE
Stripe live activation. Do NOT auto-escalate the user-facing OAuth
probe on identity-only drift.

### Operations (COO) — fresh assessment

**Status:** reviewed
**Assessment:** Doppler now holds a brand-survival credential. Rotation
cadence and RBAC follow-up tracked under #3228. The new secrets go in
`prd` only — `dev` does not need them since this is a prod-only guard.

### Product/UX Gate

**Tier:** none — no user-facing surfaces. Mechanical escalation does not
fire. Skip.

**Brainstorm-recommended specialists:** none for this PR's scope.

## Alternative Approaches Considered

| Alternative | Why not |
|---|---|
| `actions/create-github-app-token@v1` (GitHub-published) | Mints an installation token, not an App-level JWT. Different identity primitive; does not surface `client_id` from `/app`. Wrong tool. |
| Daily cron (per spec's original AC) | 24h dwell window vs hourly's 1h. $0 cost reduction (public repo Actions minutes are free). 24x faster MTTD at zero operational cost. |
| Defer entirely (P3-low keep-as-is) | Pre-#2887 framing. Post-#2887 (dev/prd Doppler collapse, brand-survival event, 2026-05-03) the org's posture treats credential-handling defenses as default-build. CPO bumped P3 → P2. |

## Follow-up Tracking

All deferrals tracked:

- **#3226** Sentry breadcrumb mirror for JWT-mint + `/app` response
- **#3227** Pre-written user-communication template for confirmed compromise
- **#3228** Doppler RBAC review for `GH_APP_DRIFTGUARD_PRIVATE_KEY_B64`
- **#3229** Installation-level guard (detect unexpected installations)
- **#3230** Roadmap `Current State` refresh

No new deferrals at plan time; all SpecFlow F1-F12 findings folded into ACs.
