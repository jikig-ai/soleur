# infra/github/ -- GitHub branch-protection Terraform root

Companion to `apps/web-platform/infra/sentry/` — same auto-apply-on-merge
boundary per ADR-031 (revised in ADR-032 for this root). Structured as a
phased runbook for the one-time App-credential verification + import
bootstrap; the sibling Sentry README is structured as a reference doc
because cron-monitors + issue-alerts have parallel lifecycles. State key:
`github/terraform.tfstate` in R2 bucket `soleur-terraform-state`.

Managed resources (both on the `main` branch of `jikig-ai/soleur`, both adopted
via `terraform import` — idempotent, run in CI on first apply, see Phase 1):

- `github_repository_ruleset.ci_required` — ruleset 14145388 ("CI Required"),
  `ruleset-ci-required.tf`.
- `github_repository_ruleset.cla_required` — ruleset 13304872 ("CLA Required"),
  `ruleset-cla-required.tf` (Terraform-ified in #6072, mirroring CI per ADR-032;
  its enforced values are byte-identical to the former imperative
  `scripts/create-cla-required-ruleset.sh`, now a DR-only restore skeleton).

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

**Before any terminal-side state write, take a snapshot — there is no other
way back.** R2 does not implement object versioning, so the backend keeps no
history and a bad state write cannot be undone from it (ADR-006 as amended;
gap tracked at #7992). On the auto-apply path above this is moot — nobody is
present before the write, which is why §"Phase 5 -- Rollback" recovers by
reverting config rather than by restoring state. But if you are about to run
`terraform state push`, `state rm`, `state mv` or an `apply` from a terminal,
capture the current state first. Run the whole block — the exports and `init`
are part of it, because `state pull` talks to the R2 backend:

```bash
cd infra/github/
export AWS_ACCESS_KEY_ID=$(doppler secrets get AWS_ACCESS_KEY_ID -p soleur -c prd_terraform --plain)
export AWS_SECRET_ACCESS_KEY=$(doppler secrets get AWS_SECRET_ACCESS_KEY -p soleur -c prd_terraform --plain)
terraform init -input=false

umask 077                                  # state holds credentials in plaintext
SNAPDIR=$(mktemp -d)
terraform state pull > "$SNAPDIR/tfstate.pre-$(date -u +%Y%m%dT%H%M%SZ).json"
echo "snapshot: $SNAPDIR"                  # note this path; a new shell loses $SNAPDIR
```

Delete it when the operation closes (§5d has the removal step). A snapshot is
worth nothing if it is taken after the write, and this is the last section you
read before one.

## Merge queue (#5780)

> **Status (2026-07-01): reverted; blocked by a GitHub platform limitation.** The
> first enablement deadlocked `main` — CodeQL does not report a status context on
> `merge_group` temp refs ([`codeql-action#1537`](https://github.com/github/codeql-action/issues/1537),
> open since 2023, no ETA), so the required `CodeQL` check never posts on a queued
> entry. This is **NOT fixable by switching CodeQL to advanced setup** — the
> status is unreported regardless of setup mode. The `merge_queue` rule is REMOVED
> from this root and the live ruleset. **The queue and a blocking required CodeQL
> check are mutually exclusive**; re-adoption is possible ONLY if GitHub resolves
> #1537, OR CodeQL is deliberately dropped from `required_status_checks`
> (advisory). The BEHIND-race #5780 targeted is already handled by `/ship`'s
> auto-sync loop, so the queue is not worth de-requiring CodeQL. See ADR-032
> (2026-07-01 decision + incident note) + the PIR at
> `knowledge-base/engineering/operations/post-mortems/merge-queue-codeql-merge-group-deadlock-postmortem.md`.
> The rest of this section describes the (currently inactive) target state, valid
> only once one of the two preconditions above holds.

Under the target state the ruleset would carry a second rule sibling — a
`merge_queue {}` block in `ruleset-ci-required.tf` — adopting a **GitHub merge
queue** for `main`. (That block is **not present today**; see the status note
above.) It would fix the strict-up-to-date BEHIND starvation: with
`strict_required_status_checks_policy = true`, a web-platform PR's CI (~8 min)
cannot converge faster than `main` merges on an active day, so the PR is flipped
`BEHIND` and restarts forever. A queue would build each candidate against the
projected post-merge state, so "up-to-date" would be satisfied **by
construction** — no human/agent re-update race. With the queue reverted, that
BEHIND race is instead handled by `/ship`'s auto-sync loop.
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
   `rules[0]` → `select(.type==…)` fragility, and added a stall probe
   (`merge-queue-stall-check.yml`) + CLA synthetics (`merge-queue-cla-synthetics.yml`).
   **Both of those PR-1 workflows were removed after the revert** (dead weight
   with the queue off — the stall probe polled a null queue every 30 min; the CLA
   synthetics only fire on `merge_group`, which never occurs without a queue).
   They are preserved in git history and MUST be restored as part of any
   re-adoption.
2. **PR-2 (this root)** would add the `merge_queue` block and *enable* the queue.
   PR #5800 did exactly this on 2026-06-30 and was **reverted the same day**; the
   block is not in the root today.

`merge_group` only fires *after* the queue is live, so enabling and verifying
cannot happen in the same merge.

### Kill switch (already exercised)

Remove the `merge_queue {}` block from `ruleset-ci-required.tf` and merge —
auto-apply reverts to pre-queue behavior. **This is what happened on 2026-06-30**,
and it is why no block is present now; the procedure is recorded here for a future
re-adoption. This is `0 destroy` (a rule-block
removal, not a `required_check` removal), so it is **not** `[ack-destroy]`-gated
(intended — the kill-switch must stay friction-free).

### Admin-merge after the queue

`bypass_actors` is unchanged, so admins can still `gh pr merge --admin` past the
queue. Admin-merge is now the **queue-bypass-of-last-resort**, not a routine
workaround for the BEHIND race (the queue removes that need).

### Drift detection

`scheduled-terraform-drift.yml` includes `infra/github` in its matrix (#5780,
CTO B-2), so the whole ruleset — and, if the queue is ever re-adopted, the
`merge_queue` rule — is drift-detected on a schedule. A `terraform plan` there
also catches a *silently-re-added* queue rule (added outside Terraform). While
the queue is reverted there is no stall probe (it was removed with PR-1's
workflows); drift = "config changed outside Terraform" is the only live probe of
the two.

### DR-restore sync (P1-3)

`scripts/create-ci-required-ruleset.sh` (the documented from-scratch restore
path) restores the `required_status_checks` rule **only** — it carries no
`merge_queue` rule, matching the reverted state of `ruleset-ci-required.tf`
(see that script's own header note). The two must stay in lockstep: if the queue
is ever re-adopted, the `merge_queue` params have to be added to BOTH, else a DR
restore creates a ruleset the next `terraform plan` immediately wants to change
(and the drift matrix flags). Any param the `.tf` leaves at provider default must
be written explicitly in the DR skeleton because the raw REST API requires every
field; the post-DR `terraform plan` is the authority on final values.

### Post-enablement canary (after PR-2 applies)

```bash
# Rule is APPLIED (App-auth token; does NOT prove the queue drains):
gh api repos/jikig-ai/soleur/rulesets/14145388 \
  --jq '[.rules[] | select(.type=="merge_queue")] | length'
# Expected: 1 — but ONLY after a re-adoption applies the block.
# TODAY (queue reverted) this correctly returns 0.
```

Then verify the queue *functions*: open a trivial human PR, `gh pr merge --squash
--auto`, confirm it ENTERS the queue (not direct-merge), all required contexts
report on the `merge_group` temp ref, and it merges without stalling. **NOTE: as
of 2026-07 this step is known to FAIL for `CodeQL` while it is a required check
(codeql-action#1537) — that is exactly the deadlock. This canary is only runnable
once CodeQL is either advisory or #1537 is fixed** (see the status note at the top
of this section). Then confirm a `rule-metrics-aggregate.yml` bot PR flows through
(CLA synthetics cover its CLA contexts — restore `merge-queue-cla-synthetics.yml`
first, removed after the revert), and that the stall probe
(`merge-queue-stall-check.yml`, also removed after the revert — restore it) has
run ≥1 green cycle. When all pass, flip the ADR-032 amendment status
`adopting → accepted`.

## Phase 0 -- Doppler setup (one-time, App-auth)

The provider authenticates as the `soleur-ai` GitHub App (id `3261325`,
org-wide installation `122213433` on `jikig-ai`) per
AGENTS.rules.md `hr-github-app-auth-not-pat`. App credentials are already
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
5. **Post-apply verify**: `gh api .../rulesets/14145388` (CI) **and**
   `.../rulesets/13304872` (CLA) count probes, recorded in the workflow run
   summary.

The import step is **per-address** (`import_ruleset <addr> <id>` for each
resource), so both rulesets adopt independently — the CI resource being in state
does not skip the CLA import. The CLA first apply is a **no-op reconcile**: the
`.tf` values are byte-identical to the live ruleset (id 13304872), so
`terraform plan` shows no change once imported. To reproduce the CLA import
manually (mirrors the CI block below), run:

```bash
cd infra/github/
export AWS_ACCESS_KEY_ID=$(doppler secrets get AWS_ACCESS_KEY_ID -p soleur -c prd_terraform --plain)
export AWS_SECRET_ACCESS_KEY=$(doppler secrets get AWS_SECRET_ACCESS_KEY -p soleur -c prd_terraform --plain)
terraform init -input=false

doppler run -p soleur -c prd_terraform --name-transformer tf-var -- \
  terraform import github_repository_ruleset.cla_required soleur:13304872
```

The `AWS_*` exports sit **outside** `doppler run --name-transformer tf-var` deliberately: the
transformer rewrites Doppler's own `AWS_ACCESS_KEY_ID` to `TF_VAR_aws_access_key_id`, so a
command run entirely inside it reaches the R2 backend with no usable credentials. The
transformer is still required — this root needs `TF_VAR_github_app_id` and
`TF_VAR_github_app_private_key` — so the correct shape is two-layer, not one or the other.

### Adopting `jikig-ai/soleur-marketplace` (#7471)

`repository-marketplace.tf` declares `github_repository.soleur_marketplace` — the public
repo that is the plugin's distribution channel (ADR-182). The repo was created out-of-band
with `gh repo create` as a one-time bootstrap and is adopted into state by
`import_repository` in `apply-github-infra.yml`, a sibling of `import_ruleset` with the same
`grep -qxF` exact-address guard.

**The import id shape differs from the ruleset one, and the difference is load-bearing.** A
`github_repository` imports by its bare **name**; the owner comes from the provider block.
Copying the ruleset's `owner:id` form fails at apply:

```bash
cd infra/github/
export AWS_ACCESS_KEY_ID=$(doppler secrets get AWS_ACCESS_KEY_ID -p soleur -c prd_terraform --plain)
export AWS_SECRET_ACCESS_KEY=$(doppler secrets get AWS_SECRET_ACCESS_KEY -p soleur -c prd_terraform --plain)
terraform init -input=false

doppler run -p soleur -c prd_terraform --name-transformer tf-var -- \
  terraform import github_repository.soleur_marketplace soleur-marketplace
```

**If the App installation is scoped to selected repositories**, the import fails with a 404
that reads like a missing repo rather than a missing grant. Widen the installation to include
the new repo before re-running; the failure aborts the step under `set -euo pipefail` rather
than falling through to a `plan` that would propose CREATE against a name that already exists.

Terraform owns the repo's settings — visibility, description, topics, `archive_on_destroy` —
**and, since #7493, its default-branch ruleset and the contents of
`.claude-plugin/marketplace.json`.** The sentence this paragraph used to carry ("deliberately
**not** its contents ... hand-maintained") is superseded.

### `ruleset-marketplace-pr-required.tf` (#7493)

Two resources, which must be read together:

- `github_repository_ruleset.marketplace_pr_required` — requires a PR with **one approval** on
  the default branch, and blocks deletion and force-push. A pure CREATE: that repo had zero
  rulesets, so there is nothing to import and `import_ruleset` is not involved. (It could not be,
  incidentally — that helper hardcodes `soleur:$id` and cannot express another repo's ruleset.)
- `github_repository_file.marketplace_manifest` — publishes
  `infra/github/soleur-marketplace-manifest.json` to that repo. Adopted via
  `overwrite_on_create = true` rather than a third import shape; at provider 6.12.1 the create
  path GETs the file first and reuses its SHA, so an existing byte-identical file takes an
  update-shaped path rather than 422-ing.

**The two are coupled by the bypass actor, not by ordering.** `bypass_actors` are attributes of
the ruleset resource and ship inside its own POST, so there is no window in which the ruleset
exists without them and a `depends_on` would buy nothing. What breaks is a WRONG bypass — the
App id `3261325` versus the installation id `122213433` — which leaves the file write rejected
and the run red. That is recoverable by a normal merge (the rulesets API is not gated by the
ruleset), so it is a red pipeline, not a deadlock.

**The human bypass actors use `bypass_mode = "always"`, unlike the two sibling rulesets.** This is
deliberate and was measured: in `pull_request` mode the sole maintainer's own merge is refused
(`reviewDecision: REVIEW_REQUIRED`) and requires an `--admin` override, which would make every
routine change an administrator action on the repo a broken install is fixed *through*.

**A destroy unpublishes the plugin.** `github_repository_file` has no `keep_on_destroy`, and
`archive_on_destroy` protects the repository rather than a file inside it. `tests/scripts/
test-destroy-guard-counter.sh` T8 pins that a replacement counts as a destroy.

### What guards what

| Guard | Where | Runs |
|---|---|---|
| `marketplace-manifest-guard` (source validity) | `scripts/marketplace-manifest-validate.sh` | every PR, blocking |
| ruleset matches its declaration | `scripts/verify-marketplace-ruleset.sh` | post-apply; fixtures on every PR |
| published bytes match source | `apply-github-infra.yml` verify step | post-apply (cache-busted body poll — the raw CDN caches 300 s) |
| published manifest still correct | `scheduled-marketplace-drift.yml` | daily; dispatches a reconcile on content drift |

The source gate and the drift gate are not redundant. The drift gate reads the PUBLISHED
artifact, so it can only report a bad manifest after it is live — and with the reconcile arm in
place, a bad SOURCE would be republished daily while a published-vs-source byte-diff reported
in-sync, because published genuinely does match source.

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
# (select-by-type, NOT .rules[0] — GitHub may return rules[] in any order, and a
#  re-adopted merge_queue rule would sit alongside this one as a sibling. The
#  guard is kept even though only one rule exists today; see the .tf header.)
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

**R2 has no point-in-time recovery.** The bucket does not implement the S3 object-versioning
API, so there is no "restore the previous state file" gesture here and never has been. This
section used to open with one; it was inoperable from the day it was written. Measured
2026-09-09: `list-object-versions` returns `NotImplemented` (rc=254) while the control
`list-objects-v2` returns rc=0 on the same credential and endpoint, so this is a vendor
capability gap and not a token-scope problem. ADR-006 is amended accordingly, and the
automatic pre-apply snapshot that would close the gap is tracked at #7992.

**What this root manages — check this first.** Four rulesets are live across the two repos and
this root manages three of them:

| Ruleset | Live id | Managed here? |
|---|---|---|
| CI Required (`jikig-ai/soleur`) | `14145388` | yes — `ruleset-ci-required.tf` |
| CLA Required (`jikig-ai/soleur`) | `13304872` | yes — `ruleset-cla-required.tf` |
| Marketplace PR Required (`jikig-ai/soleur-marketplace`) | `20802604` | yes — `ruleset-marketplace-pr-required.tf` |
| Code Quality Copilot review (`jikig-ai/soleur`) | `19474295` | **no** — not Terraform-managed |
| Force Push Prevention (`jikig-ai/soleur`) | `13044280` | **no** — not Terraform-managed |

If the thing you lost is one of the last two, nothing in this section applies — none of it will
recreate them and `scripts/create-ci-required-ruleset.sh` will exit early reporting that "CI
Required" already exists.

**Route by which failure you actually have.** State records what exists; it is not a lever on
what exists. Restoring old state only makes Terraform *believe* the old set is live, and the
next apply reconciles against the current config — rewriting the damage. So for the common
case the recovery is a **config revert**, not a state operation.

| Failure | Recovery |
|---|---|
| Bad config applied, live ruleset wrong (**the common case**) | §5a — `git revert` and merge; auto-apply reconciles |
| A ruleset was deleted outright | §5b — recreate, then re-import under its **new** id |
| State lost or corrupted, resources intact | §5c — `terraform import` |
| State corrupted **and** config bad | §5a, then §5c |
| You took a snapshot before a terminal-side write and need it back | §5d — last resort |

### 5a. Bad config applied (start here)

`git revert` the commit that broke it and merge the revert. `apply-github-infra.yml` applies on
merge, so the revert reconciles the live ruleset with no terminal access.

**Two things will stop you, and neither is obvious at 3am.**

**The destroy guard fails the apply closed.** Reverting a commit that *added* a required check
removes a nested block, and the guard at `apply-github-infra.yml:360` counts nested deletes.
The apply aborts unless the **merge commit message** contains a line that is exactly
`[ack-destroy]`. Put it there when you open the revert, not after the apply has already failed.

**If the bad apply self-locked `main`, no PR can merge at all** — including the revert. That
happens when the apply added a required context nothing ever posts (the #5780 merge-queue
deadlock three sections above is this exact shape). The way through is the ruleset's own
bypass: `ruleset-ci-required.tf:73` grants `OrganizationAdmin` and `RepositoryRole 5` a
`bypass_mode = "pull_request"` bypass, so an org admin can merge the revert through a live
self-lock. Failing that, edit the rule directly at
<https://github.com/jikig-ai/soleur/rules/14145388> and let the next apply reconcile.

### 5b. A ruleset was deleted outright

`scripts/create-ci-required-ruleset.sh` is the documented disaster-recovery restore path: it
POSTs the full ruleset from the canonical JSON and exits early if one already exists. Run it
rather than rebuilding rules by hand — the CI ruleset carries **23** required contexts
(`grep -c 'context *=' infra/github/ruleset-ci-required.tf`), so hand-restoring a remembered
subset silently under-protects `main`.

> **The recreated ruleset gets a NEW id, and the old one is hardcoded in twelve places.**
> The script POSTs (`gh api "repos/${REPO}/rulesets" -X POST`), and GitHub assigns a fresh id on
> POST — it does not reuse `14145388`. The script prints the new id; write it down. Until every
> site below is updated, `terraform import` 404s, the post-apply verify errors on a deleted id,
> and the merge gate is orphaned:
>
> ```bash
> git grep -n '14145388' -- '*.yml' '*.sh' '*.tf'
> ```
>
> At minimum: `apply-github-infra.yml` (the `import_ruleset` line and the post-apply verify),
> `scripts/update-ci-required-ruleset.sh`, and `scripts/audit-ruleset-bypass.sh`. Substitute the
> new id there **before** running the import in §5c.

### 5c. State lost or corrupted, resources intact

Re-import. `apply-github-infra.yml` imports idempotently on every run, so merging any commit
that touches `infra/github/*.tf` recovers **part** of the state with no terminal access — but
only part, and the remainder fails loudly:

| Resource | Live id | Recovered by |
|---|---|---|
| `github_repository_ruleset.ci_required` | `soleur:14145388` | auto-import on merge |
| `github_repository_ruleset.cla_required` | `soleur:13304872` | auto-import on merge |
| `github_repository.soleur_marketplace` | `soleur-marketplace` | auto-import on merge |
| `github_repository_ruleset.marketplace_pr_required` | `soleur-marketplace:20802604` | **manual import — see below** |
| `github_branch_default.soleur_marketplace` | — | re-apply |
| `github_repository_file.marketplace_manifest` | — | re-apply (`overwrite_on_create = true`) |

**`marketplace_pr_required` is the one that bites.** The workflow does not import it, so after
a total state loss the plan computes a CREATE against a ruleset of that name that already
exists live — a name collision, and the apply dies there, leaving state *partially* restored.
Import it by hand first, then let the merge finish the rest.

See **Phase 1** for the full first-apply sequence — Phase 2 has no import step.

To do it from a terminal, run the whole sequence below as one block. The bare `AWS_*` exports
must sit **outside** `doppler run --name-transformer tf-var`: that transformer rewrites
`AWS_ACCESS_KEY_ID` to `TF_VAR_aws_access_key_id`, which the R2 backend cannot use. The
transformer is still required for the `terraform` calls, because this root needs
`TF_VAR_github_app_id` and `TF_VAR_github_app_private_key` — so the shape is two-layer.
(`state list`, `state pull` and `state push` need only the backend credentials and evaluate no
variables; only `plan`/`import`/`apply` need the `TF_VAR_*` layer.)

```bash
cd infra/github/
export AWS_ACCESS_KEY_ID=$(doppler secrets get AWS_ACCESS_KEY_ID -p soleur -c prd_terraform --plain)
export AWS_SECRET_ACCESS_KEY=$(doppler secrets get AWS_SECRET_ACCESS_KEY -p soleur -c prd_terraform --plain)
terraform init -input=false

terraform state list | grep github_                      # what is already adopted

# Import only what is missing. Re-importing an adopted resource errors
# `Resource already managed by Terraform`. Substitute any id the DR script reissued (§5b).
doppler run -p soleur -c prd_terraform --name-transformer tf-var -- \
  terraform import github_repository_ruleset.marketplace_pr_required soleur-marketplace:20802604

doppler run -p soleur -c prd_terraform --name-transformer tf-var -- \
  terraform plan -out=tfplan-rollback.binary
doppler run -p soleur -c prd_terraform --name-transformer tf-var -- \
  terraform apply tfplan-rollback.binary
```

Use `apply`, **not** `apply -refresh-only`. After an import the live resources are the truth and
a refresh is harmless; the reason to avoid `-refresh-only` here is narrower — it only updates
state from the API and applies no configuration, so it cannot converge the drift you are
recovering from, and it will look like it succeeded.

### 5d. Restoring a snapshot you took earlier

There is no snapshot on the auto-apply path — no human is present before the write — so this
applies only if you took one before a terminal-side operation (see §"Authorization model:
apply-on-merge"). It is the last resort: prefer 5a–5c.

Read all four before running anything.

- **Try the push WITHOUT `-force` first.** Measured on Terraform v1.10.5: a snapshot whose
  `serial` *equals* the remote's and whose `lineage` matches pushes cleanly, rc=0. That is the
  common case when an apply failed *before* persisting — which is exactly what §"Authorization
  model" tells you to snapshot for. Only a genuinely **lower** serial is refused, with
  `cannot import state with serial N over newer state with serial M`. Reach for `-force` when
  you see that message, not before.
- **`-force` disables the wrong-root guard.** The bucket holds **six** state objects (five live
  roots plus one orphan). With `-force` the `lineage` check is skipped, so pushing another
  root's snapshot over `github/terraform.tfstate` **succeeds silently**.
- **`state push` has no `-backup` flag** (unlike `state mv` and `state rm`), so the restore is
  itself a one-way door. Pull the current bad state to a second file *first*.
- **A snapshot restores the record, not the world.** Terraform persists state incrementally, so
  a half-succeeded apply leaves real resources the restored state does not know about; the next
  apply duplicates them or errors `already exists`. Reconcile with `terraform plan` plus
  `import` / `state rm` before applying.

```bash
cd infra/github/
export AWS_ACCESS_KEY_ID=$(doppler secrets get AWS_ACCESS_KEY_ID -p soleur -c prd_terraform --plain)
export AWS_SECRET_ACCESS_KEY=$(doppler secrets get AWS_SECRET_ACCESS_KEY -p soleur -c prd_terraform --plain)
terraform init -input=false

SNAP=/path/to/your/snapshot.json          # the file from the §Authorization-model block
umask 077
SNAPDIR=$(mktemp -d)

# Keep a copy of the CURRENT (bad) state before overwriting it — state push has no -backup.
terraform state pull > "$SNAPDIR/current-bad.json"

# Identity check: lineage MUST match; note the two serials.
jq -r '"snapshot lineage=\(.lineage) serial=\(.serial)"' "$SNAP"
jq -r '"remote   lineage=\(.lineage) serial=\(.serial)"' "$SNAPDIR/current-bad.json"

# Equal serial + matching lineage: this succeeds as-is.
terraform state push "$SNAP"
# Only if it refuses with "cannot import state with serial N over newer state with serial M",
# and only after confirming the lineages above match:
#   terraform state push -force "$SNAP"
```

Terraform state holds provider credentials in **plaintext**. Clean up when the incident closes:

```bash
[ -n "${SNAPDIR:-}" ] && rm -f "$SNAPDIR"/*.json && rmdir "$SNAPDIR"
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY
```

The `[ -n ... ]` guard matters: in a fresh shell `$SNAPDIR` is unset and `"$SNAPDIR"/*.json`
expands to `/*.json`. `rm` is used rather than `shred` deliberately — `mktemp -d` lands in
`/tmp`, which is tmpfs here, where `shred`'s overwrite guarantee does not hold; the file is
removed, not securely erased, so treat any snapshot as a live credential until the volume is
gone.

**Concurrency hazard.** There is no state lock (`use_lockfile = false` — R2 has no S3
conditional writes), and a terminal sits outside every GitHub Actions concurrency group by
construction, so a terminal-side push races any in-flight CI apply with no mutual exclusion.
`scheduled-terraform-drift.yml` runs in group `terraform-drift`, **disjoint** from
`terraform-apply-github-infra`, so it is not serialized against the apply either. Check both,
and keep the run handle so you can watch or cancel:

```bash
for wf in apply-github-infra.yml scheduled-terraform-drift.yml; do
  gh run list --workflow="$wf" --json status,headBranch,databaseId,url \
    --jq ".[] | select(.status != \"completed\") | \"$wf \(.databaseId) \(.status) \(.url)\""
done
```
