---
lane: cross-domain
issue: 4114
plan: knowledge-base/project/plans/2026-05-20-infra-apply-web-platform-infra-workflow-plan.md
---

# Tasks — `apply-web-platform-infra.yml` workflow

Derived from `2026-05-20-infra-apply-web-platform-infra-workflow-plan.md` (deepened 2026-05-20).

## Phase 0 — Preconditions

- [x] 0.1 Verify the 3 third-party action SHA pins in `apply-sentry-infra.yml` are 40-char and re-usable: `actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5`, `hashicorp/setup-terraform@5e8dbf3c6d9deaf4193ca7a8fb23f2ac83bb6c85`, `DopplerHQ/cli-action@5351693ec144fc7f7a2d30025061acfc3c53c47c`. Verify length: `<sha> | awk '{print length($1)}'` → 40 for each.
- [x] 0.2 Confirm `apps/web-platform/infra/.terraform.lock.hcl` exists. If absent, file a precondition note and let /work run `terraform init` once before adding `-lockfile=readonly`.
- [x] 0.3 Enumerate the FINAL `-target=` allow-list. Start from the plan's 25-resource list (PR-H + inngest); expand by `grep -nE '^resource' apps/web-platform/infra/*.tf | grep -vE 'server\.tf:(terraform_data|hcloud_server|hcloud_volume)'`. Bake the count into AC4.
- [x] 0.4 Confirm Doppler single-invocation pattern: `apply-deploy-pipeline-fix.yml:174` uses `doppler run --name-transformer tf-var -- terraform plan ...`. Adopt this; do NOT use the nested form from `variables.tf` comments.
- [x] 0.5 Confirm CODEOWNERS convention: `.github/CODEOWNERS` line 76 (`apply-github-infra.yml @deruelle`) and line 100 (`apply-sentry-infra.yml @deruelle`). Mirror the convention for `apply-web-platform-infra.yml`.

## Phase 1 — RED (workflow scaffold passes actionlint)

- [x] 1.1 Create `.github/workflows/apply-web-platform-infra.yml` with valid YAML + empty `jobs:` map.
- [x] 1.2 Verify `actionlint .github/workflows/apply-web-platform-infra.yml` exits 0.

## Phase 2 — GREEN (full workflow body)

- [x] 2.1 Copy `apply-sentry-infra.yml` structure verbatim. Adapt:
  - `name`, `paths`, `concurrency.group`, `env.INFRA_DIR` per plan §Phase 2.
  - Kill-switch token `[skip-web-platform-apply]` (anchored regex).
  - Environment gate `web-platform-infra-apply`.
- [x] 2.2 Apply the **`apply-github-infra.yml` destroy-guard shape** (numeric regex validation + `set -e` re-enable). NOT the sentry shape.
- [x] 2.3 Add 25–40 `-target=` flags per Phase 0.3 enumeration. Verify VIA grep that no `terraform_data.{disk_monitor_install|resource_monitor_install|fail2ban_tuning|deploy_pipeline_fix|docker_seccomp_config|apparmor_bwrap_profile|orphan_reaper_install}` appears (AC5).
- [x] 2.4 Add `add-mask` for every secret extracted via `doppler secrets get ... --plain`.
- [x] 2.5 Add post-apply summary writing to `$GITHUB_STEP_SUMMARY`.
- [x] 2.6 Verify `actionlint` still passes.

## Phase 3 — Comment / CODEOWNERS sweep

- [x] 3.1 Update `apps/web-platform/infra/github-app.tf:6-8` — remove "deferred-automation backlog" wording for `terraform apply` (closed by this PR); PRESERVE the "GitHub App creation remains operator-manual" note (vendor limit).
- [x] 3.2 Append `.github/CODEOWNERS` line `/.github/workflows/apply-web-platform-infra.yml @deruelle`.
- [x] 3.3 Grep `apps/web-platform/infra/*.tf` and `apps/web-platform/infra/*.md` for "manually run terraform" / "operator runs terraform" / "ssh.*terraform apply"; update or scope-out each match.

## Phase 4 — Operator one-time setup (post-merge, manual gate)

- [ ] 4.1 (operator) Create GitHub environment `web-platform-infra-apply` at Settings → Environments. Add @deruelle as required reviewer. Restrict to `main`.
- [ ] 4.2 (operator) `gh workflow run apply-web-platform-infra.yml` with `reason: first apply post-merge`. Approve the environment gate. Confirm `gh api repos/jikig-ai/soleur/actions/runs/<id>` returns `conclusion: "success"`.
- [ ] 4.3 (operator) Verify next `scheduled-terraform-drift.yml` cron is clean (no drift for `apps/web-platform/infra`).

## Phase 5 — Verification

- [ ] 5.1 AC1–AC10 verified pre-merge via inspection.
- [ ] 5.2 AC11–AC14 verified post-merge.
- [ ] 5.3 PR body uses `Closes #4114`. Verify post-merge that the issue auto-closed.
- [ ] 5.4 Compound-capture: file a learning at `knowledge-base/project/learnings/<topic>.md` documenting the `-target=` allow-list philosophy for mixed-SSH terraform roots (if not already covered).
