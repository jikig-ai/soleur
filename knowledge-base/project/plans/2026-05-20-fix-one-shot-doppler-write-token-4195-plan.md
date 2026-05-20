---
title: "fix(infra): mint write-capable Doppler service token for apply-web-platform-infra sync step"
type: fix
date: 2026-05-20
issue: 4195
lane: single-domain
classification: ops-only-prod-write
requires_cpo_signoff: false
---

# fix(infra): mint write-capable Doppler service token for apply-web-platform-infra sync step

Closes #4195. Operator preference: Option 1 (separate write-capable service token published as `DOPPLER_TOKEN_WRITE` GH repo secret, used only by the sync step). The remaining 12 callsites of `secrets.DOPPLER_TOKEN` keep the existing read-only token — smallest blast-radius change.

## Enhancement Summary

**Deepened on:** 2026-05-20
**Sections enhanced:** Research Reconciliation (+1 row), Sharp Edges (+3 entries), Acceptance Criteria (+2 ACs), Implementation Phases (Phase 0 expanded with 2 preconditions).

### Key Improvements

1. **Doppler provider source-verified** (not docs-paraphrased) — confirmed `access` enum is `{"read","read/write"}`; confirmed `name` is `ForceNew`; confirmed `key` is `Computed + Sensitive` and CANNOT be re-read after creation (state-loss = unrecoverable, must `-replace`).
2. **In-band-mint precedent fully grounded** — this PR is the third invocation of the canonical pattern (`kb-drift.tf` was the first; the recent #4150 cleanup added a second + retired 4 operator-mint variables). The pattern is now load-bearing, and AGENTS.md rule `hr-tf-variable-no-operator-mint-default` explicitly endorses it. Plan inherits the same discipline: zero operator-mint, zero new vendor accounts.
3. **Bootstrap-cycle is genuine** — verified by reading the GH Actions runtime contract: `${{ secrets.X }}` is interpolated at job-start, NOT step-start. A secret created mid-workflow by `github_actions_secret.X` is invisible to the same workflow run. Mitigation (precondition guard + warning + operator re-fire) is the only correct shape; alternatives (manual `gh secret set` pre-seed, two-job workflow with `needs:`) all defeat the in-band-mint discipline or add structural complexity for a one-time bootstrap event.
4. **Stderr-redirect removal is load-bearing for #4195** — the original failure was masked precisely because of `>/dev/null 2>&1`. Keeping the redirect would silently re-create the same observability gap on the next failure class (e.g., quota exhaustion, network partition during the API call).

### New Considerations Discovered

- **State-storage sharp edge:** `doppler_service_token.write.key` lands in `terraform.tfstate` in R2. R2 backend uses encrypted bucket; same blast-radius posture as the existing `doppler_service_token.kb_drift.key`. Document in the new HCL header.
- **Service-token name collision:** if a Doppler service token named `"ci-tf-write"` already exists in `prd_terraform` (e.g., from an aborted prior attempt or a manual test), the Doppler API `POST /v3/configs/config/tokens` returns the NEW token (Doppler API allows duplicate names; uses opaque slug for uniqueness). The TF resource owns the new slug; the old token becomes orphaned and must be cleaned up manually. Phase 0 must check.
- **App-permission alignment:** the `integrations/github` App-auth at `main.tf:65-72` already has `secrets:write` (added during the #4150 cleanup per learning `2026-05-20-tf-operator-mint-variables-are-design-smell.md` session-error #1). No new App permission needed for this PR. Documented explicitly so the next reader does not re-investigate.

## Overview

PR #4181 added a post-apply step in `apply-web-platform-infra.yml` that writes the freshly-rotated `cloudflare_zero_trust_access_service_token.ci_ssh` outputs back into Doppler `prd_terraform` as `CI_SSH_ACCESS_TOKEN_ID` / `CI_SSH_ACCESS_TOKEN_SECRET`. The step failed at first execution (run #26176906538, 2026-05-20) because the workflow's `secrets.DOPPLER_TOKEN` is a `prd_terraform`-scoped service token with `read` access — `doppler secrets set` requires `read/write`. The operator recovered manually via `apps/web-platform/infra/scripts/sync-ci-ssh-access-token.sh` using a personal write-capable token.

This plan mints a dedicated write-capable service token in-band via Terraform (mirrors `kb-drift.tf:65-86`), publishes the token value to GitHub as `DOPPLER_TOKEN_WRITE`, and rewires only the sync step (`apply-web-platform-infra.yml:312-345`) to consume the new secret. All other `secrets.DOPPLER_TOKEN` references stay on the read-only token.

The fix is in-band (provider-mint, no operator-mint) per `hr-tf-variable-no-operator-mint-default` and `hr-exhaust-all-automated-options-before`. No new Terraform root (uses existing `apps/web-platform/infra/`), no new provider, no new vendor account.

## User-Brand Impact

**If this lands broken, the user experiences:** No direct user-facing impact. The Doppler sync step is post-apply infrastructure plumbing; failures are operator-observable only.

**If this leaks, the user's [data / workflow / money] is exposed via:** A leaked `DOPPLER_TOKEN_WRITE` grants write to `prd_terraform` (Cloudflare, Hetzner, GitHub-App, Inngest, Resend credentials, plus `var.admin_ips`). A malicious overwrite of `admin_ips` would broaden SSH allowlist; a malicious overwrite of `CI_SSH_ACCESS_TOKEN_*` would not be exploitable without the corresponding CF Access service-token issuance (the actual rotation is in Cloudflare's hands). Net incremental write surface vs. the existing `DOPPLER_TOKEN_TF` workplace token already in `prd_terraform`: zero — `DOPPLER_TOKEN_TF` (the provider-auth token consumed by the `doppler` provider) already has full write to `prd_terraform`. The new token narrows blast radius (config-scoped, not workplace-scope) and lives only in `secrets.DOPPLER_TOKEN_WRITE`.

**Brand-survival threshold:** none — infrastructure plumbing, operator-only observability, no first-party user data on the path.

- `threshold: none, reason:` diff matches the canonical sensitive-path regex (touches `.github/workflows/apply-web-platform-infra.yml` and `apps/web-platform/infra/`), but the net incremental write surface vs. the existing `DOPPLER_TOKEN_TF` workplace-scope provider-auth token is zero or negative — the new `DOPPLER_TOKEN_WRITE` is config-scoped to `prd_terraform` only and lives in a single repo secret, while the existing `DOPPLER_TOKEN_TF` already has full write to every config including `prd_terraform`. No user data, no first-party PII path, no payment surface; failure mode is operator-observable workflow failure with the local-fallback script as immediate recovery.

## Research Reconciliation — Spec vs. Codebase

| Claim | Reality | Plan response |
|---|---|---|
| Issue body: "mint a write-capable DOPPLER_TOKEN_WRITE" implies `access = "write"` | Doppler provider source: `validation.StringInSlice([]string{"read", "read/write"}, false)` — `"write"` alone is rejected at `terraform validate`. | Use `access = "read/write"` (the canonical write-tier value). |
| Issue body: "mint a new Doppler service token … as a separate GitHub repo secret" suggests operator-mint via dashboard + `gh secret set` | Codebase precedent (`kb-drift.tf:65-86`) mints `doppler_service_token` in-band via the existing DopplerHQ provider auth (`var.doppler_token_tf` is workplace-scope and CAN issue service tokens) AND publishes the value via `github_actions_secret` using the App-installation `github` provider. | Adopt the in-band pattern verbatim (provider-mint per `hr-tf-variable-no-operator-mint-default`); no operator-mint step. |
| Issue body recommends "store as a separate GitHub repo secret" | The `github_actions_secret` resource (App-auth at `main.tf:65-72`) already has `secrets:write` on the soleur repo; the existing `doppler_token_kb_drift` resource at `kb-drift.tf:82-86` is the precedent. | Add `github_actions_secret.doppler_token_write` with `repository = "soleur"`, `secret_name = "DOPPLER_TOKEN_WRITE"`, no `ignore_changes` (rotation must propagate per `kb-drift.tf:30-31` precedent). |
| Issue body: sync step uses redirected output (`>/dev/null 2>&1`) masking the specific error | Confirmed at `apply-web-platform-infra.yml:340-342`; cannot distinguish permission-denied from other failures. | Plan does NOT touch the redirect (out of scope) but adds an explicit failure-path AC: the post-fix sync step must surface stderr on failure. Defer redirect removal to a separate code-quality scope-out — orthogonal to this fix. |

## Files to Edit

- `apps/web-platform/infra/doppler-write-token.tf` *(new)* — `doppler_service_token.write` + `github_actions_secret.doppler_token_write`. Header comment mirrors `kb-drift.tf:1-33` rotation/scope conventions.
- `.github/workflows/apply-web-platform-infra.yml` — rewire only the `Sync CF Access CI-SSH service token to Doppler` step (lines 312-345) to consume `secrets.DOPPLER_TOKEN_WRITE` instead of `secrets.DOPPLER_TOKEN`. Add a "Verify required secrets present" companion line for `DOPPLER_TOKEN_WRITE` (mirror lines 141-150). Bootstrap-cycle comment block at top of sync step explaining: first apply has no `DOPPLER_TOKEN_WRITE` GH secret yet; the resource creates it; subsequent applies consume it.
- `apps/web-platform/infra/scripts/sync-ci-ssh-access-token.sh` — comment refresh: "Canonical path NOW works (post-#4195). Use this script only for local reprovisioning after a workstation `terraform apply`." Drop the "fallback IS the canonical path" implication from header (line 12).
- `.github/workflows/apply-web-platform-infra.yml` — append `-target=doppler_service_token.write` and `-target=github_actions_secret.doppler_token_write` to the `terraform plan` allow-list (lines 197-274) per the maintenance comment at line 199-203.

## Files to Create

- `apps/web-platform/infra/doppler-write-token.tf` (see above).
- `knowledge-base/project/learnings/2026-05-20-doppler-write-token-bootstrap-cycle-and-access-enum.md` — captures (a) the `"read/write"` enum value (not `"write"`), (b) the bootstrap cycle (first apply creates the secret the consumer step needs; the consumer step is gated by an output-presence check so the bootstrap apply degrades to warning instead of failing), (c) the precedent reference (`kb-drift.tf`).

## Implementation Phases

### Phase 0 — Preconditions and grounding

- Verify `var.doppler_token_tf` (workplace-scope personal token in `prd_terraform`) is currently usable to mint a new config-scoped service token. Read `variables.tf:137` confirms it's the workplace personal token. No new var needed.
- Verify Doppler provider 1.21.2 supports `access = "read/write"` (confirmed: provider source at `doppler/resource_service_token.go` — `Schema["access"].ValidateFunc = validation.StringInSlice([]string{"read", "read/write"}, false)`; default is `"read"`).
- Verify `github_actions_secret` is already a working resource in this root (`kb-drift.tf:82-86` proves it). The App-installation auth at `main.tf:65-72` covers secret publishing AND already has `secrets:write` (added during #4150 cleanup; see learning `2026-05-20-tf-operator-mint-variables-are-design-smell.md` session error #1). **No new App permission required for this PR.**
- Verify `DOPPLER_TOKEN_WRITE` is NOT currently set as a GH repo secret (must be created in-band, not pre-seeded):

  ```bash
  gh api repos/jikig-ai/soleur/actions/secrets/DOPPLER_TOKEN_WRITE --jq '.name' 2>&1 | head -3
  # Expected: HTTP 404 (secret does not exist yet) — if it exists, delete it before merge:
  #   gh secret delete DOPPLER_TOKEN_WRITE --repo jikig-ai/soleur
  # so the in-band mint owns the value end-to-end (avoids state-vs-secret drift).
  ```

- Verify no Doppler service token named `ci-tf-write` already exists in `prd_terraform` (the Doppler API allows duplicates by name; the new TF-managed token would orphan the old one):

  ```bash
  doppler configs tokens --project soleur --config prd_terraform --json \
    | jq -r '.[] | select(.name == "ci-tf-write") | "EXISTS:\(.slug)"'
  # Expected: no output. If a row matches, delete the orphan first:
  #   doppler configs tokens revoke --project soleur --config prd_terraform --slug <slug>
  ```

- Verify the `integrations/github` App-installation (id `122213433` per `main.tf:69`) has `secrets:write` (`gh api apps/soleur-ai --jq '.permissions.secrets'` should return `"write"`). If `"read"` or absent, the in-band `github_actions_secret` resource will fail with `403 Resource not accessible by integration` — out-of-scope to widen here; defer with a tracking issue (would re-open the #4150 App-permission-mutation workflow).

### Phase 1 — Author HCL (`doppler-write-token.tf`)

```hcl
# Closes #4195. Dedicated write-capable Doppler service token for the
# post-apply `Sync CF Access CI-SSH service token to Doppler` step in
# `.github/workflows/apply-web-platform-infra.yml`. The existing
# `secrets.DOPPLER_TOKEN` is `prd_terraform`-scoped READ-only; the sync
# step needs `secrets:write`. Mirrors the in-band mint pattern from
# `kb-drift.tf:65-86` with two diffs: (a) `access = "read/write"`,
# (b) scoped to `prd_terraform` (not `prd_kb_drift_walker`).
#
# Blast radius: token grants write to `prd_terraform` ONLY (Cloudflare,
# Hetzner, GitHub-App, Inngest, Resend creds, `var.admin_ips`). Net
# incremental write surface vs. existing `var.doppler_token_tf`
# (workplace-scope) is ZERO -- this is a strict narrowing.
#
# Rotation: `terraform apply -replace=doppler_service_token.write`.
# The new key value MUST propagate to
# `github_actions_secret.doppler_token_write.plaintext_value` -- this
# file deliberately omits `lifecycle.ignore_changes = [plaintext_value]`
# on that resource so rotation reaches the consumer in the same apply
# (mirrors `kb-drift.tf:78-86`).
#
# autonomy-considered: provider-mint-applied (App auth + doppler_service_token).

resource "doppler_service_token" "write" {
  project = "soleur"
  config  = "prd_terraform"
  name    = "ci-tf-write"
  access  = "read/write"
}

resource "github_actions_secret" "doppler_token_write" {
  repository      = "soleur"
  secret_name     = "DOPPLER_TOKEN_WRITE"
  plaintext_value = doppler_service_token.write.key
}
```

Grep precedent verbatim from `kb-drift.tf:65-86`; only the diffs noted in the header change.

### Phase 2 — Append to the apply allow-list

Edit `.github/workflows/apply-web-platform-infra.yml` Terraform plan step (the long `-target=` list at lines 197-274) — append two lines:

```yaml
              -target=doppler_service_token.write \
              -target=github_actions_secret.doppler_token_write \
```

Position: directly after `-target=doppler_service_token.kb_drift` and `-target=github_actions_secret.doppler_token_kb_drift` (sibling resources) for grep-readability.

### Phase 3 — Rewire the sync step

Edit `.github/workflows/apply-web-platform-infra.yml` `Sync CF Access CI-SSH service token to Doppler` step (lines 312-345):

- Change `DOPPLER_TOKEN: ${{ secrets.DOPPLER_TOKEN }}` → `DOPPLER_TOKEN: ${{ secrets.DOPPLER_TOKEN_WRITE }}`.
- Drop the `>/dev/null 2>&1` redirect on the two `doppler secrets set` lines — surface stderr on failure so future permission-denied errors are not masked. Keep `--silent --no-interactive` (those suppress success echo of the just-set value, NOT errors).
- Add a precondition guard at the top of the step (companion to the existing `Verify required secrets present` step at lines 142-152):

  ```yaml
  - name: Verify DOPPLER_TOKEN_WRITE present
    env:
      DOPPLER_TOKEN_WRITE_CHECK: ${{ secrets.DOPPLER_TOKEN_WRITE }}
    run: |
      set -euo pipefail
      if [[ -z "$DOPPLER_TOKEN_WRITE_CHECK" ]]; then
        echo "::warning::DOPPLER_TOKEN_WRITE not yet present — this is expected on the first apply that creates it. Subsequent applies will use the synced token. If you see this on the second+ run, manually trigger one more apply via gh workflow run."
        echo "skip_sync=true" >> "$GITHUB_OUTPUT"
      else
        echo "skip_sync=false" >> "$GITHUB_OUTPUT"
      fi
    id: doppler_write_check
  ```

  Then gate the sync step with `if: steps.doppler_write_check.outputs.skip_sync != 'true'`.

  **Why the bootstrap-cycle dance:** on the first apply that creates `github_actions_secret.doppler_token_write`, the GH Actions runner already started before the secret existed — `${{ secrets.DOPPLER_TOKEN_WRITE }}` will be empty for that one run. The next apply (any apply) will have the secret. The warning is non-fatal because the local-fallback script remains functional; the operator can re-fire the workflow via `gh workflow run apply-web-platform-infra.yml --ref main -F reason='bootstrap DOPPLER_TOKEN_WRITE'` immediately after the first merge.

### Phase 4 — Refresh script comments

Edit `apps/web-platform/infra/scripts/sync-ci-ssh-access-token.sh` header (lines 1-12) to remove the "fallback IS the canonical path" implication that #4195 introduced. The CI path now works post-#4195 first-apply; the script is for local reprovisioning only.

### Phase 5 — Capture learning

Write `knowledge-base/project/learnings/2026-05-20-doppler-write-token-bootstrap-cycle-and-access-enum.md` covering:

1. Doppler provider `access` enum is `{"read","read/write"}` — `"write"` alone is invalid (caught at `terraform validate`).
2. Bootstrap cycle: a workflow that consumes a GH Actions secret created by its own `terraform apply` is empty on the first run; gate consumer steps with a presence check that emits `::warning::` (not `::error::`).
3. Precedent reference: `apps/web-platform/infra/kb-drift.tf:65-86` is the canonical in-band Doppler-service-token + github-actions-secret-publish pattern.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1 — `apps/web-platform/infra/doppler-write-token.tf` exists with exactly the two resources `doppler_service_token.write` (access `"read/write"`, project `"soleur"`, config `"prd_terraform"`, name `"ci-tf-write"`) and `github_actions_secret.doppler_token_write` (repository `"soleur"`, secret_name `"DOPPLER_TOKEN_WRITE"`, plaintext_value `doppler_service_token.write.key`).

  Verify: `grep -nE 'resource "doppler_service_token" "write"|resource "github_actions_secret" "doppler_token_write"' apps/web-platform/infra/doppler-write-token.tf | wc -l` returns `2`.

- [ ] AC2 — `terraform validate` passes against `apps/web-platform/infra/` (catches the `"write"` vs `"read/write"` enum trap).

  Verify (run from worktree root):

  ```bash
  cd apps/web-platform/infra
  export AWS_ACCESS_KEY_ID=$(doppler secrets get AWS_ACCESS_KEY_ID -p soleur -c prd_terraform --plain)
  export AWS_SECRET_ACCESS_KEY=$(doppler secrets get AWS_SECRET_ACCESS_KEY -p soleur -c prd_terraform --plain)
  terraform init -input=false
  doppler run -p soleur -c prd_terraform --name-transformer tf-var -- terraform validate
  ```

  Expected stdout: `Success! The configuration is valid.`

- [ ] AC3 — Apply allow-list in `.github/workflows/apply-web-platform-infra.yml` includes both new resources.

  Verify: `grep -nE 'target=doppler_service_token\.write|target=github_actions_secret\.doppler_token_write' .github/workflows/apply-web-platform-infra.yml | wc -l` returns `2`.

- [ ] AC4 — Sync step consumes `secrets.DOPPLER_TOKEN_WRITE` (NOT `secrets.DOPPLER_TOKEN`).

  Verify (precision-anchor on the sync step's env block via awk-range with flag pattern per learning `2026-05-15-plan-ac-verification-commands-awk-self-match-and-marker-conjunction.md`):

  ```bash
  awk '/^      - name: Sync CF Access CI-SSH service token to Doppler/{flag=1; next} /^      - name: /{flag=0} flag' \
    .github/workflows/apply-web-platform-infra.yml | grep -c 'secrets.DOPPLER_TOKEN_WRITE'
  ```

  Expected: `1` (single env-var assignment). And the same awk-range piped to `grep -c 'secrets.DOPPLER_TOKEN[^_]'` returns `0` (no leftover reference to the read-only token in that step body).

- [ ] AC5 — Other 12+ workflow consumers of `secrets.DOPPLER_TOKEN` are unchanged (defensive: confirm we did not accidentally rewire reads).

  Verify: `grep -c 'secrets.DOPPLER_TOKEN[^_]' .github/workflows/*.yml | grep -vE ':(0)$'` matches the pre-fix count (record the pre-fix count in the PR body — currently 19 matches across 5 workflows). The expected match count must be preserved exactly.

- [ ] AC6 — Bootstrap-cycle precondition guard present at the sync step.

  Verify (anchored to the new step name; `-A8` catches the step body regardless of where `id:` is placed within the step mapping):

  ```bash
  grep -A8 'Verify DOPPLER_TOKEN_WRITE present' .github/workflows/apply-web-platform-infra.yml | grep -E 'DOPPLER_TOKEN_WRITE_CHECK|skip_sync=true|warning'
  ```

  Expected: ≥3 line matches across the three patterns (env-check variable, output assignment, warning message). And the sync step `if:` includes `steps.doppler_write_check.outputs.skip_sync != 'true'`.

- [ ] AC7 — `>/dev/null 2>&1` redirect removed from the two `doppler secrets set` lines in the sync step.

  Verify (awk-range, same precision-anchor as AC4):

  ```bash
  awk '/^      - name: Sync CF Access CI-SSH service token to Doppler/{flag=1; next} /^      - name: /{flag=0} flag' \
    .github/workflows/apply-web-platform-infra.yml | grep -cE 'doppler secrets set CI_SSH_ACCESS_TOKEN.*>/dev/null 2>&1'
  ```

  Expected: `0`.

- [ ] AC8 — Sync script header comment refresh: `apps/web-platform/infra/scripts/sync-ci-ssh-access-token.sh` lines 1-12 no longer imply the "fallback IS the canonical path".

  Verify: `grep -c 'Use this script only for local reprovisioning' apps/web-platform/infra/scripts/sync-ci-ssh-access-token.sh` returns `>= 1`.

- [ ] AC9 — `Closes #4195` is in the PR body (NOT title), per `wg-use-closes-n-in-pr-body-not-title-to`. Type is single-domain infra, post-merge ops applies — but the *actual fix* (the sync step) is observable on the next merge that touches `apps/web-platform/infra/**`, NOT only on rotation. Use `Closes #4195` (the apply happens auto-via push trigger on merge).

- [ ] AC10 — Learning file written: `knowledge-base/project/learnings/2026-05-20-doppler-write-token-bootstrap-cycle-and-access-enum.md` with YAML frontmatter (`title`, `date`, `category`, `tags`) and three sections covering (a) access enum, (b) bootstrap cycle, (c) precedent reference.

### Post-merge (operator)

- [ ] AC11 — The `apply-web-platform-infra.yml` workflow auto-fires on push to main (paths-filter matches `apps/web-platform/infra/**` and `.github/workflows/apply-web-platform-infra.yml`). Operator clicks "approve" in the `web-platform-infra-apply` environment gate when prompted. First apply: creates `doppler_service_token.write` + `github_actions_secret.doppler_token_write`; sync step emits `::warning::` because `DOPPLER_TOKEN_WRITE` was empty at runner-start.

  Verify (operator, after first apply completes):

  ```bash
  gh api repos/jikig-ai/soleur/actions/secrets/DOPPLER_TOKEN_WRITE --jq '.name'
  # Expected: "DOPPLER_TOKEN_WRITE"
  ```

- [ ] AC12 — Re-trigger the workflow to confirm the canonical path now works:

  ```bash
  gh workflow run apply-web-platform-infra.yml --ref main -F reason='post-#4195 bootstrap second apply'
  ```

  Verify (after the run completes): the `Sync CF Access CI-SSH service token to Doppler` step's GH Actions log line `Synced CI_SSH_ACCESS_TOKEN_ID/_SECRET to Doppler prd_terraform.` is present AND the step exited 0.

  ```bash
  gh run list --workflow=apply-web-platform-infra.yml --limit 1 --json conclusion,databaseId --jq '.[0]'
  # Expected: .conclusion == "success"
  gh run view <run-id> --log | grep "Synced CI_SSH_ACCESS_TOKEN_ID/_SECRET"
  # Expected: one matching line
  ```

- [ ] AC13 — Doppler-side state-truth: `CI_SSH_ACCESS_TOKEN_ID` and `CI_SSH_ACCESS_TOKEN_SECRET` exist in `prd_terraform` (operator already put them there via the local-fallback recovery — this is verification that the second apply did NOT regress the values, since CF Access service tokens reissue secrets on `-replace` ONLY).

  Verify:

  ```bash
  doppler secrets get CI_SSH_ACCESS_TOKEN_ID -p soleur -c prd_terraform --plain | head -c 8
  doppler secrets get CI_SSH_ACCESS_TOKEN_SECRET -p soleur -c prd_terraform --plain | head -c 8
  # Expected: 8 chars of each; non-empty. Should match what operator wrote during recovery.
  ```

- [ ] AC14 — Close issue: `gh issue close 4195 --comment "Resolved via PR #<N>. <run-url> shows the second apply's sync step succeeded."`

- [ ] AC15 — Phase 0 orphan-token check completed: PR body includes a one-line preamble like `Phase 0: no orphan ci-tf-write token in prd_terraform (doppler configs tokens --json | jq …); no pre-existing DOPPLER_TOKEN_WRITE GH secret (gh api 404).` This is evidence-of-check, not a re-run gate.

- [ ] AC16 — `secrets:write` App permission audit: PR body includes `gh api apps/soleur-ai --jq '.permissions.secrets'` output (`"write"`) confirming the App-installation auth can publish `github_actions_secret`. Cited evidence — no re-run at AC time.

## Research Insights

**Doppler provider semantics (source-verified, not docs-paraphrased):**

```go
// DopplerHQ/terraform-provider-doppler doppler/resource_service_token.go
"access": {
    Description:  "The access level (read or read/write)",
    Type:         schema.TypeString,
    Optional:     true,
    Default:      "read",
    ValidateFunc: validation.StringInSlice([]string{"read", "read/write"}, false),
    ForceNew:     true,
},
"key": {
    Description: "The key for the Doppler service token",
    Type:        schema.TypeString,
    Computed:    true,
    Sensitive:   true,
},
// Read() comment: "`key` cannot be read after initial creation"
```

Implications: `access`, `project`, `config`, `name` are all `ForceNew` — any edit triggers destroy-then-create (state-tracked rotation). `key` is `Sensitive` (never logged) but persists in `terraform.tfstate` forever; state-loss is unrecoverable without `-replace`.

**Doppler API duplicate-name behavior:**

The Doppler API `POST /v3/configs/config/tokens` does NOT enforce name uniqueness within a project+config — duplicates are allowed, identified by opaque slug. Terraform tracks the slug in its resource ID (`<project>.<config>.<slug>`). A pre-existing manual-mint token with the same name will not block a TF apply; the new resource will mint a new token and orphan the old one. The Phase 0 pre-check is the only guard.

**GitHub Actions secret-interpolation timing:**

Per <https://docs.github.com/en/actions/security-guides/using-secrets-in-github-actions#using-secrets-in-a-workflow>, secrets are resolved at job-start (when the runner is provisioned + receives its environment). A secret created mid-run by `github_actions_secret` (Terraform or `gh secret set`) is invisible to the same job. The bootstrap-cycle warning + operator re-fire is the correct mitigation for one-time first-apply.

**Precedent file inventory** (canonical in-band Doppler+GH-secret pattern):

- `apps/web-platform/infra/kb-drift.tf:65-86` — original pattern (PR-H #3244 / #4150)
- `apps/web-platform/infra/inngest.tf` — sibling pattern (random_id-based credentials)
- `apps/web-platform/infra/main.tf:65-72` — App-installation auth for the `integrations/github` provider
- AGENTS.md rule `hr-tf-variable-no-operator-mint-default` — enforces this pattern by default

**References:**

- Doppler provider source: <https://github.com/DopplerHQ/terraform-provider-doppler/blob/master/doppler/resource_service_token.go>
- GitHub Actions secrets timing: <https://docs.github.com/en/actions/security-guides/using-secrets-in-github-actions>
- `integrations/github` App-auth: <https://registry.terraform.io/providers/integrations/github/6.12.1/docs#authenticating-via-github-app-installation>
- Canonical autonomy-hierarchy learning: `knowledge-base/project/learnings/best-practices/2026-05-20-tf-operator-mint-variables-are-design-smell.md`

## Test Strategy

No new unit tests — this is infrastructure config. Verification is via:

1. `terraform validate` at AC2 — catches the `"write"` vs `"read/write"` enum trap and any HCL syntax errors.
2. `terraform plan` (auto-run by `apply-web-platform-infra.yml` on the merge commit) — proves the new resources are in scope for the next apply.
3. Post-merge `gh run view` log inspection at AC12 — proves the sync step exited 0 with the success message.

## Domain Review

**Domains relevant:** engineering (CTO) only.

### Engineering (CTO)

**Status:** reviewed (inline by planner; this is a single-resource infra-config change with no cross-domain implications).

**Assessment:** Mirrors the canonical `kb-drift.tf:65-86` in-band Doppler-service-token + GH-secret-publish pattern. Net incremental write surface vs. existing `DOPPLER_TOKEN_TF` is zero (strict narrowing). No Product, Marketing, Sales, Finance, Legal, Operations, or Security cross-cutting implications.

## Infrastructure (IaC)

### Terraform changes

- New file: `apps/web-platform/infra/doppler-write-token.tf` (one `doppler_service_token`, one `github_actions_secret`).
- No new provider; reuses `DopplerHQ/doppler ~> 1.21` (provider-auth via `var.doppler_token_tf`) and `integrations/github ~> 6.0` (App-installation auth via `var.github_app_id` + `var.github_app_private_key`).
- No new `TF_VAR_*` secrets in Doppler — token is minted in-band from the existing workplace-scope `doppler_token_tf`.
- Sensitive outputs: none (`doppler_service_token.write.key` is consumed by `github_actions_secret.doppler_token_write.plaintext_value` in the same state, never emitted as an `output`).

### Apply path

(b) cloud-init-not-applicable + idempotent in-place — apply path is the existing `apply-web-platform-infra.yml` push-trigger on merge to main. Bootstrap cycle: first apply creates the secret with a runner that didn't have it; the sync step degrades to `::warning::` (skip) on that single run; second apply consumes the secret normally.

Expected downtime: zero. Blast radius: zero (additive — no existing resource is modified; the sync step's old `secrets.DOPPLER_TOKEN` path is replaced 1:1 with the new `secrets.DOPPLER_TOKEN_WRITE` path).

### Distinctness / drift safeguards

- `dev != prd`: this is `prd_terraform`-scoped only; no `dev_terraform` equivalent is needed because dev infra is bring-up-only and does not run the sync step.
- `lifecycle.ignore_changes`: deliberately OMITTED on `github_actions_secret.doppler_token_write.plaintext_value` (so token rotation via `terraform apply -replace=doppler_service_token.write` propagates to the consumer in the same apply — mirrors `kb-drift.tf:78-86`).
- State storage: encrypted R2 backend (per `main.tf:1-14`); the `doppler_service_token.key` value lands in `terraform.tfstate` — same posture as the existing `doppler_service_token.kb_drift` resource.

### Vendor-tier reality check

Doppler service tokens are unmetered on the standard paid plan (the soleur project's current tier). No `count = var.doppler_paid_tier ? 1 : 0` gate needed; the resource is unconditional.

## Observability

```yaml
liveness_signal:
  what: "Successful exit (rc=0) of the 'Sync CF Access CI-SSH service token to Doppler' step in apply-web-platform-infra.yml"
  cadence: "On every merge to main that touches apps/web-platform/infra/** OR on every manual workflow_dispatch"
  alert_target: "GitHub Actions workflow-failure notification (operator email + repo bell)"
  configured_in: ".github/workflows/apply-web-platform-infra.yml — step 'Sync CF Access CI-SSH service token to Doppler' with explicit stderr-surfacing (no >/dev/null redirect post-#4195)"

error_reporting:
  destination: "GitHub Actions step log (stderr surfaced; `::error::` annotations for permission-denied class)"
  fail_loud: "yes — `set -euo pipefail` enabled at step top; doppler CLI non-zero exit propagates to step failure; step failure marks workflow run as failed and triggers GitHub's standard failure notification chain"

failure_modes:
  - mode: "DOPPLER_TOKEN_WRITE secret missing (bootstrap-cycle first apply)"
    detection: "Precondition guard step `Verify DOPPLER_TOKEN_WRITE present` emits ::warning:: when env is empty"
    alert_route: "Annotated as warning (not error) on first apply; surfaces as GH summary annotation only. Operator must re-fire workflow once after first merge to consume the newly-published secret."
  - mode: "Permission denied on doppler secrets set (token revoked / scope drift)"
    detection: "doppler CLI exits non-zero with stderr printed (>/dev/null redirect removed in this PR); step fails"
    alert_route: "GH Actions workflow-failure notification → operator email"
  - mode: "CI_SSH_ACCESS_TOKEN outputs missing (apply ran with -target= that excluded ci_ssh resource)"
    detection: "Existing precondition at apply-web-platform-infra.yml:325-329 catches empty outputs and exits 0 with a ::warning:: (no behavior change in this PR)"
    alert_route: "GH summary annotation; no failure (legitimate skip path)"

logs:
  where: "GitHub Actions run log (https://github.com/jikig-ai/soleur/actions/workflows/apply-web-platform-infra.yml)"
  retention: "90 days (GitHub default; sufficient for post-mortem of a rotation event)"

discoverability_test:
  command: |
    gh run list --workflow=apply-web-platform-infra.yml --limit 5 \
      --json conclusion,createdAt,databaseId,event \
      --jq '.[] | select(.event == "push" or .event == "workflow_dispatch")'
  expected_output: "Most recent run's .conclusion == 'success'; for the bootstrap apply, .conclusion is also 'success' (the precondition guard converts the empty-secret case to a warning, not an error)."
```

## Sharp Edges

- **Bootstrap cycle:** on the very first apply after this PR merges, `DOPPLER_TOKEN_WRITE` does not yet exist as a GH repo secret. The runner already started; `${{ secrets.DOPPLER_TOKEN_WRITE }}` interpolates to empty. The precondition guard (Phase 3) catches this and emits `::warning::` rather than failing the run. Operator must re-fire the workflow once after first merge — documented in AC11/AC12 and in the new learning file. Plan-time prevention: if the operator wants to skip the bootstrap dance, manually `gh secret set DOPPLER_TOKEN_WRITE` with a placeholder before merging (rejected: this defeats the in-band mint discipline of `hr-tf-variable-no-operator-mint-default`).
- **Doppler `access` enum:** the provider accepts `"read"` or `"read/write"` ONLY. `"write"` alone fails at `terraform validate` — caught by AC2. The issue body's phrasing "write-capable" must NOT be transliterated to `access = "write"` in HCL.
- **Stderr-surfacing change:** removing `>/dev/null 2>&1` from the two `doppler secrets set` lines surfaces success-path stdout too (the just-set value). The `--silent` flag suppresses Doppler CLI's own value-echo, so stdout is still empty on success. If a future Doppler CLI version changes `--silent`'s semantic, the GH Actions log could leak a token value. Mitigation: `printf '::add-mask::%s\n' "$CLIENT_ID"` is already in place at lines 333-334. The `add-mask` directive protects against this regression class.
- **Net incremental write surface analysis:** the existing `var.doppler_token_tf` (workplace-scope personal token) ALREADY has full write to `prd_terraform`. The new `DOPPLER_TOKEN_WRITE` is a strict narrowing (config-scoped). The reverse claim "this adds new write surface" is false — at most, this adds a SECOND token with the same surface as the existing one. Net is zero or negative.
- **`Closes #4195` placement:** this is single-domain infra (NOT `ops-only-prod-write`-class — the fix lives in code, not in a post-merge runbook). The fix manifests on the next merge auto-apply, which IS pre-merge from the human's perspective (the merge IS the trigger). Use `Closes #4195` per `wg-use-closes-n-in-pr-body-not-title-to`; the issue auto-closes on merge, and the apply confirms the fix.
- **`key` is `Computed + Sensitive` and CANNOT be re-read** — Doppler provider source for `resourceServiceTokenRead` explicitly notes `// "key" cannot be read after initial creation`. The `key` value lands in `terraform.tfstate` on create and is never re-fetched from the Doppler API. Implication: if the state file is lost or the resource is removed from state via `terraform state rm doppler_service_token.write`, the only recovery is `terraform apply -replace=doppler_service_token.write`, which mints a NEW token and orphans the old one (still valid; must be revoked manually via `doppler configs tokens revoke`). Document this in the new HCL header.
- **Service-token name is not a uniqueness constraint** — the Doppler API allows multiple tokens with the same `name` in the same project+config (uniqueness is the opaque slug). Phase 0's `doppler configs tokens --json` pre-check is the correct guard; if skipped, the in-band create will silently mint a duplicate and orphan the prior token. Doppler dashboard cleanup is manual (no auto-GC of orphaned tokens).
- **GH Actions secrets are job-scoped, not step-scoped** — `${{ secrets.DOPPLER_TOKEN_WRITE }}` is interpolated at job-start (when the runner is provisioned), not step-start. A secret created by an earlier step in the same job is invisible to later steps in the same job. The two-job alternative (`needs:` chaining the publish + consume into separate jobs) would technically work but adds structural complexity for a one-time bootstrap event — the warning + operator re-fire is the simplest correct shape. The behavior is documented at <https://docs.github.com/en/actions/security-guides/using-secrets-in-github-actions>.
- **`hr-tf-variable-no-operator-mint-default` compliance** — this PR introduces zero new TF variables. The `doppler_service_token.write` resource is minted from the existing `var.doppler_token_tf` workplace token (which already authorizes minting in `prd_terraform`). The `github_actions_secret.doppler_token_write` resource is published via the existing App-installation auth (no new var, no new App permission, no new PAT). Per the canonical autonomy hierarchy in learning `2026-05-20-tf-operator-mint-variables-are-design-smell.md`, this is the lowest-cost lifecycle shape.

## Open Code-Review Overlap

```bash
gh issue list --label code-review --state open \
  --json number,title,body --limit 200 > /tmp/open-review-issues.json

for path in apps/web-platform/infra/doppler-write-token.tf \
            apps/web-platform/infra/scripts/sync-ci-ssh-access-token.sh \
            .github/workflows/apply-web-platform-infra.yml; do
  jq -r --arg path "$path" '
    .[] | select(.body // "" | contains($path))
    | "#\(.number): \(.title)"
  ' /tmp/open-review-issues.json
done
```

Result: **None.** No open code-review issues touch the files this plan edits.

## Resume prompt

```text
Resume prompt (copy-paste after /clear):
/soleur:work knowledge-base/project/plans/2026-05-20-fix-one-shot-doppler-write-token-4195-plan.md. Branch: feat-one-shot-doppler-write-token-4195. Worktree: .worktrees/feat-one-shot-doppler-write-token-4195/. Issue: #4195. Plan reviewed, implementation next.
```
