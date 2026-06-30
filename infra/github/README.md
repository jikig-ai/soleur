# infra/github/ -- GitHub branch-protection Terraform root

Companion to `apps/web-platform/infra/sentry/` — same auto-apply-on-merge
boundary per ADR-031 (revised in ADR-032 for this root). Structured as a
phased runbook for the one-time App-credential verification + import
bootstrap; the sibling Sentry README is structured as a reference doc
because cron-monitors + issue-alerts have parallel lifecycles. State key:
`github/terraform.tfstate` in R2 bucket `soleur-terraform-state`.

Managed resource: ruleset 14145388 ("CI Required") on the `main` branch of
`jikig-ai/soleur`. Adopted via `terraform import` (idempotent, runs in CI on
first apply — see Phase 1 below).

Per AGENTS.md `hr-all-infrastructure-provisioning-servers`, every change to
the required-status-check set must flow through this root. UI edits will
produce drift on the next `terraform plan` -- reconcile by editing this
config to match live state OR re-applying to restore the configured set.

## Authorization model: apply-on-merge

Apply runs **automatically in CI** when a PR touching `infra/github/*.tf`
merges to `main` -- see `.github/workflows/apply-github-infra.yml`. The PR
merge IS the human authorization (`hr-menu-option-ack-not-prod-write-auth`),
mirroring the ADR-031 boundary for `apps/web-platform/infra/sentry/`.

CODEOWNERS (`/.github/CODEOWNERS`) pins `/infra/github/` to `@deruelle` — a
PR cannot merge without code-owner review, so a leaked `DOPPLER_TOKEN` alone
is insufficient to push a ruleset change to production.

Kill switch: include `[skip-github-apply]` on its own line in the merge
commit message to skip the auto-apply for that merge. Destructive plans
(any `delete` action) additionally require `[ack-destroy]` in the merge
commit message, or the apply fails closed.

Manual escape hatch: `gh workflow run apply-github-infra.yml -f reason='...'`
for the first apply post-Phase-0 (when no `infra/github/*.tf` files have
changed yet) or for re-runs after a transient failure.

## Merge queue (#5780)

> **Status (2026-07-01): reverted, rolling forward.** The first enablement
> deadlocked `main` — GitHub CodeQL **default setup** does not post the required
> `CodeQL` context on `merge_group` temp refs, so every queue entry stalled. The
> queue was kill-switched (the `merge_queue` rule is currently REMOVED from this
> root and from the live ruleset). Re-enablement requires CodeQL **advanced**
> setup (`.github/workflows/codeql.yml`, `on: merge_group`) to be live and
> verified first. See ADR-032 (2026-07-01 incident note) + the PIR at
> `knowledge-base/engineering/operations/post-mortems/merge-queue-codeql-merge-group-deadlock-postmortem.md`.
> The rest of this section describes the target (re-enabled) state.

The ruleset carries a second rule sibling — a `merge_queue {}` block in
`ruleset-ci-required.tf` — adopting a **GitHub merge queue** for `main`. It fixes
the strict-up-to-date BEHIND starvation: with
`strict_required_status_checks_policy = true`, a web-platform PR's CI (~8 min)
cannot converge faster than `main` merges on an active day, so the PR is flipped
`BEHIND` and restarts forever. The queue builds each candidate against the
projected post-merge state, so "up-to-date" is satisfied **by construction** —
no human/agent re-update race — and routine admin-merge is no longer needed.
Full rationale + the param table live in ADR-032 (#5780 amendment).

**Chosen params** (only value-bearing decisions are set; `max_entries_to_build`
and `min_entries_to_merge_wait_minutes` stay at provider default, inert at
`max/min_entries_to_merge = 1`):

| Param | Value | Note |
| --- | --- | --- |
| `merge_method` | `SQUASH` | Matches `gh pr merge --squash`. |
| `grouping_strategy` | `ALLGREEN` | Safe default at our volume. |
| `max_entries_to_merge` | `1` | One candidate at a time (no batching). |
| `min_entries_to_merge` | `1` | Merge as soon as a candidate is green. |
| `check_response_timeout_minutes` | `15` | **Must exceed the slowest required check on `merge_group`.** Under-setting it *dequeues a green PR* (re-introducing the starvation). Re-derive from the observed slowest-required-check p95 (target `>= 1.5x slowest`); raise it if the slowest required check exceeds ~10 min. |

### Two-PR sequencing (load-bearing)

The queue dispatches a `merge_group` event against a temporary
`gh-readonly-queue/main/*` ref. A required check whose workflow never fires on
`merge_group` leaves the queue entry **pending forever → the queue stalls**. So:

1. **PR-1 (#5784, merged 2026-06-30)** added `merge_group:` to all 7 producer
   workflows (CodeQL is default-setup, the 8th producer), fixed the apply-verify
   `rules[0]` → `select(.type==…)` fragility, and added the stall probe
   (`merge-queue-stall-check.yml`) + CLA synthetics (`merge-queue-cla-synthetics.yml`).
2. **PR-2 (this root)** adds the `merge_queue` block and *enables* the queue.

`merge_group` only fires *after* the queue is live, so enabling and verifying
cannot happen in the same merge.

### Kill switch

Remove the `merge_queue {}` block from `ruleset-ci-required.tf` and merge —
auto-apply reverts to pre-queue behavior. This is `0 destroy` (a rule-block
removal, not a `required_check` removal), so it is **not** `[ack-destroy]`-gated
(intended — the kill-switch must stay friction-free).

### Admin-merge after the queue

`bypass_actors` is unchanged, so admins can still `gh pr merge --admin` past the
queue. Admin-merge is now the **queue-bypass-of-last-resort**, not a routine
workaround for the BEHIND race (the queue removes that need).

### Drift detection

`scheduled-terraform-drift.yml` now includes `infra/github` in its matrix
(#5780, CTO B-2), so the `merge_queue` rule is drift-detected on a schedule. A
`terraform plan` there also catches a *silently-disabled* queue (rule removed
outside Terraform → no entries → the stall probe is blind to it). The stall probe
and the drift probe are deliberately separated: stall = "queue not draining",
drift = "config changed/removed outside Terraform".

### DR-restore sync (P1-3)

`scripts/create-ci-required-ruleset.sh` (the documented from-scratch restore
path) restores BOTH the `required_status_checks` and `merge_queue` rules. Its
`merge_queue` params **must be kept in lockstep** with the `merge_queue` block in
`ruleset-ci-required.tf` — if they drift, a DR restore creates a ruleset the next
`terraform plan` immediately wants to change (and the drift matrix flags). The
two params the `.tf` leaves at provider default are set to GitHub's defaults
(5/5) in the DR skeleton because the raw REST API requires every field; the
post-DR `terraform plan` is the authority on their final values.

### Post-enablement canary (after PR-2 applies)

```bash
# Rule is APPLIED (App-auth token; does NOT prove the queue drains):
gh api repos/jikig-ai/soleur/rulesets/14145388 \
  --jq '[.rules[] | select(.type=="merge_queue")] | length'
# Expected: 1
```

Then verify the queue *functions*: open a trivial human PR, `gh pr merge --squash
--auto`, confirm it ENTERS the queue (not direct-merge), all 18 required contexts
(16 CI Required + 2 CLA Required: `cla-check`, `cla-evidence`) report on the
`merge_group` temp ref incl. `CodeQL`, and it merges without stalling. Then
confirm a `rule-metrics-aggregate.yml` bot PR flows through (CLA synthetics cover
its CLA contexts), and that `merge-queue-stall-check.yml` has run ≥1 green cycle.
When all pass, flip the ADR-032 amendment status `adopting → accepted`.

## Phase 0 -- Doppler setup (one-time, App-auth)

The provider authenticates as the `soleur-ai` GitHub App (id `3261325`,
org-wide installation `122213433` on `jikig-ai`) per
AGENTS.core.md `hr-github-app-auth-not-pat`. App credentials are already
mirrored from `prd` to `prd_terraform` by the `apps/web-platform/infra/`
root's `doppler_secret` resources (PR #4150), so no fresh mint is needed.

Verify Doppler has both secrets:

```bash
doppler secrets get GITHUB_APP_ID -p soleur -c prd_terraform --plain | wc -c
doppler secrets get GITHUB_APP_PRIVATE_KEY -p soleur -c prd_terraform --plain | wc -c
# Both must be non-zero. PEM is ~1.7KB.
```

If either is empty, mirror from the source `prd` config:

```bash
doppler secrets set GITHUB_APP_ID="$(doppler secrets get GITHUB_APP_ID -p soleur -c prd --plain)" \
  -p soleur -c prd_terraform
doppler secrets set GITHUB_APP_PRIVATE_KEY="$(doppler secrets get GITHUB_APP_PRIVATE_KEY -p soleur -c prd --plain)" \
  -p soleur -c prd_terraform
```

The App MUST have `Administration: Write` permission on `jikig-ai/soleur`
(required for ruleset writes). Verify at
<https://github.com/organizations/jikig-ai/settings/installations/122213433>
if `terraform plan` errors with `401 "Resource not accessible by integration"`.

## Phase 1 -- First apply (one-time)

Merging a PR that touches `infra/github/*.tf` (e.g. this one, #4384) triggers
`apply-github-infra.yml` automatically — no manual `workflow_dispatch` needed.
The first apply is a **5 → 15 transition** (5 baseline imported + 9 from
PR #3891 Tier-1/Tier-2 widening + 1 from PR #4384 `enforce`). The 9 #3891
additions land in the same apply because the import-then-plan flow reconciles
the configured set against the live state.

The workflow performs:

1. `terraform init -lockfile=readonly`.
2. **Idempotent import**: if the resource is not in state, runs
   `terraform import github_repository_ruleset.ci_required soleur:14145388`.
   On subsequent applies, this step is a no-op.
3. `terraform plan -out=tfplan` with destroy-guard (`[ack-destroy]` required
   in commit message for any `delete` action).
4. `terraform apply tfplan` (auto-approved — PR merge is the human
   authorization).
5. **Post-apply verify**: `gh api .../rulesets/14145388` count probe,
   recorded in the workflow run summary.

If you want to reproduce the local-terminal plan-diff probe before merge
(sanity check that the diff is the expected set of additions), the
canonical sequence is:

```bash
cd infra/github/
export AWS_ACCESS_KEY_ID=$(doppler secrets get AWS_ACCESS_KEY_ID -p soleur -c prd_terraform --plain)
export AWS_SECRET_ACCESS_KEY=$(doppler secrets get AWS_SECRET_ACCESS_KEY -p soleur -c prd_terraform --plain)
terraform init -input=false

# Skip the `terraform import` line below if the CI workflow has already
# applied at least once — the resource is already in R2 state and
# re-importing returns `Error: Resource already managed by Terraform`.
# Run `terraform state list | grep github_repository_ruleset` to check.
doppler run -p soleur -c prd_terraform --name-transformer tf-var -- \
  terraform import github_repository_ruleset.ci_required soleur:14145388

doppler run -p soleur -c prd_terraform --name-transformer tf-var -- \
  terraform plan
# Expected (first apply): 10 required_check additions (9 from #3891 + 1
# from #4384), no destroys.
# Expected (post-apply, idle): no changes.
```

(This is read-only against R2 state once import runs — apply still belongs in CI.)

## Phase 2 -- Subsequent applies (auto-on-merge)

Open a PR that edits `infra/github/*.tf` (e.g. adding a new required check
to `ruleset-ci-required.tf`). On merge to `main`, the `apply-github-infra`
workflow:

- Re-runs init + plan in CI.
- Aborts with `[ack-destroy]` guidance if the plan removes any required check
  without explicit acknowledgement in the commit message.
- Applies the change (PR merge is the human authorization per ADR-031).
- Records the post-apply ruleset count in the workflow run summary.

No terminal-side `terraform apply` is required for any normal flow.

## Phase 3 -- Manual verification (optional / debug)

The auto-apply workflow already runs a count probe and writes it to the run
summary. If you want to manually re-verify the live state:

```bash
gh api repos/jikig-ai/soleur/rulesets/14145388 \
  | jq '.rules[] | select(.type=="required_status_checks") | .parameters.required_status_checks | length'
# Expected: matches the current ruleset-ci-required.tf set
# (select-by-type, NOT .rules[0] — the merge_queue rule is a sibling and
#  GitHub may return rules[] in any order; see this file's intro + .tf header.)
```

Spot-check the active contexts:

```bash
gh api repos/jikig-ai/soleur/rulesets/14145388 \
  | jq -r '.rules[] | select(.type=="required_status_checks") | .parameters.required_status_checks[].context' \
  | sort
```

## Phase 4 -- Rotation (App credentials -- none required operator-side)

The provider authenticates as the `soleur-ai` GitHub App. App credentials do
not rotate operator-side -- the App PEM lives in Doppler indefinitely.
Rotation cadence is the GitHub App admin UI (`Settings > Developer settings >
GitHub Apps > soleur-ai > Private keys`), with re-mirror to Doppler when a
new PEM is generated. The 90-day PAT rotation cadence documented prior to
PR #4384 is obsolete.

## Phase 5 -- Rollback

If a Terraform apply broke the ruleset:

1. List prior state versions in R2:

   ```bash
   aws --endpoint-url=https://4d5ba6f096b2686fbdd404167dd4e125.r2.cloudflarestorage.com \
     s3api list-object-versions --bucket soleur-terraform-state \
     --prefix github/terraform.tfstate
   ```

2. Restore the prior version (operator-attested):

   ```bash
   aws --endpoint-url=https://4d5ba6f096b2686fbdd404167dd4e125.r2.cloudflarestorage.com \
     s3api copy-object \
     --copy-source soleur-terraform-state/github/terraform.tfstate?versionId=<prev> \
     --bucket soleur-terraform-state --key github/terraform.tfstate
   ```

3. Apply the restored state with operator attestation (`apply` — NOT
   `apply -refresh-only`; the latter pulls state FROM the API and would
   reconcile the rollback away):

   ```bash
   doppler run -p soleur -c prd_terraform --name-transformer tf-var -- \
     terraform plan -out=tfplan-rollback.binary
   doppler run -p soleur -c prd_terraform --name-transformer tf-var -- \
     terraform apply tfplan-rollback.binary
   ```

For catastrophic ruleset corruption: emergency fallback is the GitHub UI at
<https://github.com/jikig-ai/soleur/rules/14145388> -- operator can manually
restore the 5 baseline checks; then re-import from clean state via Phase 2.
