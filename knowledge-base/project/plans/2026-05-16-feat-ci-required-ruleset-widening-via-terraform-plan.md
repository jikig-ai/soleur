---
title: Widen CI Required ruleset via new infra/github/ Terraform root
date: 2026-05-16
type: feature
classification: infra-iac
status: draft
lane: cross-domain
requires_cpo_signoff: false
related_issues:
  - https://github.com/jikig-ai/soleur/issues/3888
related_prs:
  - https://github.com/jikig-ai/soleur/pull/3886
related_learnings:
  - knowledge-base/project/learnings/2026-05-16-allowlist-diff-shadowed-widening-and-gitleaks-verbose-flag.md
  - knowledge-base/project/learnings/2026-03-19-github-ruleset-stale-bypass-actors.md
tags: [ci, branch-protection, terraform, secret-scan, gdpr-art-30]
---

## Enhancement Summary

**Deepened on:** 2026-05-16
**Sections enhanced:** Overview, Phase 1 (provider pin + bypass_actors handling), Phase 2 (import shape), Phase 4 (infra-validation extension), Risks (R6/R7 elevated), Sharp Edges.
**Research used:** Context7 GitHub provider docs (`/integrations/terraform-provider-github`), GitHub provider issue tracker (#2317 integration_id drift, #2467 required_check optional, #2504 bypass_actors ordering drift, #2536 actor_id 1→0 change, #2855 v6.7.4 init failure, #2952 bypass_actors deletion bug, #3159 v6.x fork-policy regression), repo-local learning `2026-03-19-github-ruleset-stale-bypass-actors.md`, live `gh api repos/jikig-ai/soleur/rulesets/14145388` capture, live `gh pr view 3886 --json statusCheckRollup`.

### Key Improvements

1. **Provider pin tightened from `~> 6.0` to `~> 6.10`** — repo-local learning `2026-03-19-github-ruleset-stale-bypass-actors.md` explicitly recommends `>= v6.10.0` to dodge go-github client bugs that touched `bypass_actors` and `required_check`. v6.7.4 had a documented `Internal validation error during TF Init` regression (provider issue #2855) — `~> 6.0` would permit it.
2. **`bypass_actors` ordering hazard documented** — provider issue #2504 reports phantom drift when multiple `bypass_actors` blocks are present. Live state has TWO (OrganizationAdmin + RepositoryRole id=5). The plan now prescribes a `lifecycle.ignore_changes = [bypass_actors[*].actor_id]` escape hatch IF the import-time plan surfaces ordering churn — operator-attested choice during Phase 2.3 plan-diff reconciliation.
3. **`integration_id` drift documented** — provider issue #2317 reports phantom diffs when `integration_id` is set on one side and omitted on the other. Plan keeps the value explicit on every `required_check` block (matching live state) to suppress drift.
4. **`actor_id = 0` for OrganizationAdmin verified against current provider semantics** — provider issue #2536 documents the 1→0 transition; live API returns `actor_id: null`. The provider's HCL form for `null` is `actor_id = 0` (a documented sentinel). Plan retains `0` with an inline comment citing #2536; the alternative is `actor_id = null` if the v6.10+ release tolerated it (verify at import time).
5. **`infra-validation.yml` path filter is the load-bearing widening** — the workflow's `paths:` filter is hardcoded to `apps/*/infra/**` AND the `detect-changes` job uses `find apps/*/infra` + `git diff -- 'apps/*/infra/'`. Folding `infra/github/` into validation requires three coordinated edits (path filter + find pathspec + git-diff pathspec) — these are now enumerated as Phase 4.1/4.2/4.3 in the plan body. Without all three, `terraform validate` does not run on PRs touching `infra/github/`.
6. **Import oracle bound to live API capture before any apply** — the import oracle (Phase 0.4) is now mandatory pre-apply input to the plan-diff probe. Without the oracle, an unexpected drift in the import plan cannot be distinguished from a Terraform-config defect.

### New Considerations Discovered

- **Provider issue #2952 — `bypass_actors` removal silently no-ops.** If the live ruleset's bypass actors diverge from the plan's encoded form, removing one via Terraform may not actually delete it. Mitigation: the plan operates in pure-import mode; we adopt the existing 2 bypass actors verbatim, not modify them.
- **Provider issue #3159 — v6.x fork-policy regression on org-level ops.** Not relevant to ruleset CRUD specifically but worth noting in ADR-032 as a class of v6.x rough edge.
- **GitHub Actions integration_id reported in API ≠ documented value.** The API returned `integration_id: 15368` consistently for all 4 of the 5 baseline checks that run under Actions; CodeQL's check uses `57789`. These are stable for `jikig-ai/soleur` but **not** documented as well-known constants — they are GitHub App installation IDs visible only via the API. The plan now treats both as Terraform variables with documented defaults AND records the API-capture command in the runbook so future operators can re-discover them.
- **Live `actor_id: null` for OrganizationAdmin in API response** vs **Terraform requires non-null actor_id field.** This is the most likely import-time diff source. If `terraform plan` flags an unwanted `bypass_actors` modification post-import, the recovery sequence is: (a) confirm provider version is `>= 6.10.0`, (b) try `actor_id = 0`, (c) if drift persists, add `lifecycle.ignore_changes = [bypass_actors]` and document.

# Widen `CI Required` ruleset to gate secret-scan + correctness checks via Terraform

## Overview

PR #3886 merged on 2026-05-16T13:59:41Z with `lint fixture content` showing
`"conclusion": "FAILURE"` in the status-check rollup. The merge was permitted
because that check is not in the `CI Required` ruleset's
`required_status_checks` list (current set: `test`, `dependency-review`,
`e2e`, `CodeQL`, `skill-security-scan PR gate` — 5 items, verified via
`gh api repos/jikig-ai/soleur/rulesets/14145388`). Eight more secret-scan
and correctness checks fail-silently the same way — a regression of any of
them lands on `main` invisible to the merge gate.

This plan widens the ruleset to add **9 required checks** (6 Tier 1
secret-scan jobs from `.github/workflows/secret-scan.yml` + 3 Tier 2
non-secret-scan jobs from `.github/workflows/ci.yml`). Per AGENTS.md hard
rule `hr-all-infrastructure-provisioning-servers`, branch protections must
be Terraform-managed. No `infra/github/` Terraform root exists today, so
the work is:

1. Create `infra/github/` as a new Terraform root with R2 remote backend
   (per `hr-every-new-terraform-root-must-include-an` + ADR-006).
2. Adopt the existing ruleset 14145388 into Terraform state via
   `terraform import`.
3. Widen the `required_status_checks` set to 14 items (5 existing + 9 new).
4. File the GDPR Article 30 register entry for the new processing root
   (Activity 12 — GitHub branch-protection state custody).
5. Provide the operator runbook covering Doppler secret setup, init, plan,
   apply, and rollback.
6. File four follow-up issues for the deferred Tier-2 expansion items
   (`smoke (*)` matrix, `Block *` family, `Analyze (*)` CodeQL subjobs,
   docs/perf gates) and one referencing #3888.

The "test" for this plan is mechanical: `terraform plan` must show
**exactly 9 additions to `required_status_checks`** and zero other changes.
Any deviation (a re-ordering, a property drift, a bypass-actor diff) means
the import surfaced unmanaged drift that must be reconciled first.

## User-Brand Impact

**If this lands broken, the user experiences:** No direct user impact —
this is an internal CI policy artifact. Indirect impact: a regression in
secret-scan, lockfile, or service-role allowlisting that ships to `main`
because the gate didn't fire could leak a credential or break a
production deploy — the user experiences slow page loads, broken auth, or
in the worst case the brand-survival event of a leaked production secret
on a public repo. The reason this PR exists is precisely that the
non-required state IS the broken-experience state.

**If this leaks, the user's [data / workflow / money] is exposed via:**
The Terraform state file holds the ruleset configuration plus the
short-lived GitHub PAT/App token at apply time. State is encrypted-at-rest
in R2; the token is Doppler-resident at apply time and never written to
state thanks to GitHub provider's redaction (`api_token` is marked
sensitive). The branch protection config itself is public via
`gh api repos/.../rulesets/14145388` — there is no confidentiality
surface to leak.

**Brand-survival threshold:** aggregate pattern.

Rationale: a single ruleset-policy change is not single-user-incident-class.
But the *absence* of the widening allowed PR #3886 to ship a failing
secret-scan gate — repeated occurrences of that aggregate pattern (each
slip merges another regression) is brand-survival because secret-scan
is the floor that catches credential leaks on a public repo. This PR
closes the aggregate-pattern gap; CPO sign-off not required per the
plan-time staging model.

## Research Reconciliation — Spec vs. Codebase

| Spec/Issue claim | Codebase reality | Plan response |
|---|---|---|
| "PR #3886 had `lint fixture content` FAILING but merged anyway" | Verified via `gh pr view 3886 --json statusCheckRollup` — entry `{"name":"lint fixture content","conclusion":"FAILURE"}` co-exists with `mergedAt: 2026-05-16T13:59:41Z`. | No change — claim accurate. |
| "Current required: 5 checks (test, dependency-review, e2e, CodeQL, skill-security-scan PR gate)" | Verified via `gh api repos/jikig-ai/soleur/rulesets/14145388` — exactly 5 contexts, integration_ids 15368 (Actions) for 4 of them and 57789 (CodeQL) for `CodeQL`. | Plan encodes both integration_ids in the Terraform resource. |
| "No `infra/github/` Terraform root exists" | Verified via `find . -name '*.tf'` — Terraform roots are `apps/web-platform/infra/` (main + `sentry/` sub-root) and zero `infra/` root at repo level. | Plan creates `infra/github/` at the repo root (NOT under `apps/web-platform/`) because branch protection is a repo-level concern, not a web-platform-app concern. |
| "All 9 new checks come from GitHub Actions" | Verified by job-name grep against `.github/workflows/secret-scan.yml` (6 jobs) and `.github/workflows/ci.yml` (3 jobs). All run under `runs-on: ubuntu-*` (integration_id 15368). | Plan uses `integration_id = 15368` for all 9 new entries. |
| "Existing reference TF roots: `apps/web-platform/infra/` and `apps/telegram-bridge/infra/`" | `apps/web-platform/infra/` exists with main.tf, sentry/ sub-root, R2 backend. `apps/telegram-bridge/infra/` does NOT exist — `find apps/telegram-bridge/ -name '*.tf'` returns zero. | Plan references **only** `apps/web-platform/infra/` (main + sentry/ sub-root) as precedent. Issue-body claim about `telegram-bridge/infra/` is stale — noted here, not propagated. |
| "Existing `prd_terraform` Doppler config holds AWS creds for R2" | Verified — `doppler secrets --project soleur --config prd_terraform --only-names` includes `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, plus CF tokens. **No `GITHUB_TOKEN` variable today.** | Plan adds `GH_RULESET_PAT` to `prd_terraform` as Phase 0 operator step (see Phase 1). |

## Files to Create

```text
infra/github/
├── main.tf                 # backend "s3" (R2), required_providers, provider "github"
├── versions.tf             # terraform.required_version + provider versions
├── variables.tf            # gh_token, gh_owner, gh_repo, integration_ids
├── ruleset-ci-required.tf  # github_repository_ruleset.ci_required (the load-bearing resource)
├── outputs.tf              # ruleset_id, ruleset_url
├── .gitignore              # mirror apps/web-platform/infra/.gitignore (terraform.tfstate*, .terraform/)
├── README.md               # operator runbook (init/plan/apply/import/rollback + Doppler setup)
└── .terraform.lock.hcl     # provider lock (commit per Terraform convention)

knowledge-base/engineering/architecture/decisions/
└── ADR-032-github-branch-protection-as-iac.md   # decision record (mirrors ADR-031 sentry pattern)
```

## Files to Edit

```text
knowledge-base/legal/article-30-register.md   # add Processing Activity 12
.github/workflows/infra-validation.yml        # extend tf-validate matrix to infra/github/
```

## Open Code-Review Overlap

Ran `gh issue list --label code-review --state open --json number,title,body --limit 200 > /tmp/open-review-issues.json`
then `jq` grep over each of the planned file paths.

**Result:** None. No open code-review issues touch `infra/github/`,
`knowledge-base/legal/article-30-register.md`, or
`.github/workflows/infra-validation.yml`. The check ran.

## Domain Review

**Domains relevant:** Engineering (CTO), Legal (CLO), Security.

### Engineering (CTO)

**Status:** reviewed.
**Assessment:** Standard infra-IaC pattern. The new root mirrors
`apps/web-platform/infra/sentry/` (sub-root with own R2 key, beta-eligible
provider versioning, separate ADR). The only novel surface is the
`integrations/github` provider — adopt the latest stable major (v6.x
series), pin via `.terraform.lock.hcl`. No new CI surface (validation
flows through existing `infra-validation.yml`).

### Legal (CLO)

**Status:** reviewed.
**Assessment:** A Terraform root for GitHub branch-protection state is a
new processing surface for Soleur — it persists a controller-side artifact
(ruleset config) plus operator-attributed apply events (via Terraform's
own audit trail and GitHub's audit-log of the API caller). No personal
data of users or operators is processed; the GitHub PAT/App token belongs
to the *operator* (Jean) as data subject only in the trivial "the token
identifies its bearer" sense. New Article 30 PA12 entry mirrors PA10's
template (operational telemetry / orchestration plane). Lawful basis:
Art. 6(1)(f) legitimate interest (operate the CI policy substrate);
retention: indefinite (state file is the source-of-truth, no expiry).

### Security

**Status:** reviewed.
**Assessment:** The GitHub PAT/App token is the most sensitive surface.
Three mitigations: (1) Doppler-resident, never in git or in state-file
plaintext (GitHub provider marks `token` sensitive); (2) scoped to single
repo via fine-grained PAT (only `Administration: read+write` on
`jikig-ai/soleur`, no org-wide admin); (3) rotation cadence — 90-day
expiry max, runbook documents rotation. R2 backend already TLS-only with
versioning; ADR-006 covers state confidentiality posture.

## Implementation Phases

### Phase 0 — Preconditions (operator-driven, one-time)

These run on the operator's workstation, NOT in CI. Plan-time-verified
commands:

**Phase 0.1 — Mint the GitHub Fine-Grained PAT.**

1. Browser: `https://github.com/settings/personal-access-tokens/new`
2. Resource owner: `jikig-ai` org (NOT personal account — required for
   repo-scoped FGPATs on org repos).
3. Repository access: select `jikig-ai/soleur` only.
4. Permissions: `Administration: Read and write` (the only permission
   needed for `repository_ruleset` CRUD per GitHub provider docs);
   `Metadata: Read-only` is auto-granted.
5. Expiration: 90 days. (Calendar reminder at +75 days.)
6. Token name: `terraform-infra-github-rulesets`.

This step is interactive (FGPAT generation is browser-gated). Automation
gate: not feasible — GitHub's UI does not expose FGPAT mint via API for
human-tied identities. Documented in Phase 0 of runbook.

**Phase 0.2 — Stash the PAT in Doppler (`prd_terraform`).**

Mechanical step — operator runs the canonical Doppler-set command from
the runbook. Standardize on `GH_RULESET_PAT` (not `GITHUB_TOKEN` — the
latter collides with the magic variable that `actions/checkout` and other
actions expect). Verification:
`doppler secrets get GH_RULESET_PAT -p soleur -c prd_terraform --plain`
returns the token. Sensitive variable; never echoed to terminal.

**Phase 0.3 — Verify the PAT works.**

```bash
GH_TOKEN=$(doppler secrets get GH_RULESET_PAT -p soleur -c prd_terraform --plain) \
  gh api repos/jikig-ai/soleur/rulesets/14145388 | jq '.id, .name'
```

Expected: `14145388`, `"CI Required"`. If 401/403, regenerate Phase 0.1
with the correct permissions.

**Phase 0.4 — Capture the live state for reconciliation.**

```bash
gh api repos/jikig-ai/soleur/rulesets/14145388 > /tmp/ruleset-live-pre-import.json
```

This is the **import oracle**: after `terraform import` succeeds, the
Terraform-rendered config must produce a `plan` that ONLY adds the 9
new checks and modifies nothing else. Diff against this oracle if drift
appears.

### Phase 1 — Scaffold `infra/github/` (Terraform root)

**Phase 1.1 — `infra/github/main.tf`** (mirrors
`apps/web-platform/infra/sentry/main.tf` shape):

```hcl
# Backend mirrors apps/web-platform/infra/main.tf + sentry/main.tf — same R2
# bucket, distinct state key so this root never shares locks with peers.
terraform {
  backend "s3" {
    bucket                      = "soleur-terraform-state"
    key                         = "github/terraform.tfstate"
    region                      = "auto"
    endpoints                   = { s3 = "https://4d5ba6f096b2686fbdd404167dd4e125.r2.cloudflarestorage.com" }
    skip_credentials_validation = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_s3_checksum            = true
    use_path_style              = true
    use_lockfile                = false # R2 does not support S3 conditional writes
  }
}

# Provider auth: GH_RULESET_PAT env var (Doppler prd_terraform).
# Fine-grained PAT scoped to jikig-ai/soleur with Administration: Read+Write only.
# Rotation: 90 days max; runbook in README.md §Rotation.
provider "github" {
  owner = var.gh_owner   # "jikig-ai"
  token = var.gh_token   # from TF_VAR_gh_token via doppler --name-transformer tf-var
}
```

**Phase 1.2 — `infra/github/versions.tf`:**

```hcl
terraform {
  required_version = ">= 1.6"

  required_providers {
    github = {
      source  = "integrations/github"
      version = "~> 6.10"
    }
  }
}
```

**Pin rationale (deepened):** `~> 6.10` (≥ 6.10.0, < 7.0.0).
Repo-local learning
`knowledge-base/project/learnings/2026-03-19-github-ruleset-stale-bypass-actors.md`
explicitly recommends `>= v6.10.0` to avoid known go-github client
bugs affecting `bypass_actors` (provider issues #2179, #2269, #2952)
and `required_check` (#2467 — `required_check` schema marked Required
when API allows omission). v6.7.4 had a documented `Internal
validation error during TF Init` regression (#2855). The narrower
`~> 6.0` (which permits 6.0.x — 6.9.x) would let any of those land
during a future `terraform init -upgrade`. Lockfile commit pins the
exact patch version. Verify at apply time via `terraform init`'s
generated `.terraform.lock.hcl` entry.

**Phase 1.3 — `infra/github/variables.tf`:**

```hcl
variable "gh_token" {
  description = "Fine-grained PAT for ruleset CRUD. Sourced from Doppler prd_terraform/GH_RULESET_PAT."
  type        = string
  sensitive   = true
}

variable "gh_owner" {
  description = "GitHub org owning the repo."
  type        = string
  default     = "jikig-ai"
}

variable "gh_repo" {
  description = "Repository slug under the org."
  type        = string
  default     = "soleur"
}

variable "actions_integration_id" {
  description = "GitHub Actions integration_id. Verified 15368 via API."
  type        = number
  default     = 15368
}

variable "codeql_integration_id" {
  description = "CodeQL integration_id. Verified 57789 via API."
  type        = number
  default     = 57789
}
```

**Phase 1.4 — `infra/github/ruleset-ci-required.tf`** (the load-bearing
resource; encodes the existing 5 + new 9 = 14 required checks):

```hcl
# CI Required ruleset (id 14145388) — adopted via `terraform import` in
# Phase 2 of the runbook. WIDENED from 5 to 14 required status checks
# to close the secret-scan-failure-merged gap surfaced by PR #3886
# (lint fixture content failed and merged because it was not required).
#
# Bypass actors preserved from the live ruleset:
#   - OrganizationAdmin (actor_type, no specific id)        — pull_request mode
#   - RepositoryRole id=5 (Admin)                           — pull_request mode
#
# Strict policy is preserved (strict_required_status_checks_policy = true).
resource "github_repository_ruleset" "ci_required" {
  name        = "CI Required"
  repository  = var.gh_repo
  target      = "branch"
  enforcement = "active"

  conditions {
    ref_name {
      include = ["~DEFAULT_BRANCH"]
      exclude = []
    }
  }

  bypass_actors {
    actor_id    = 0
    actor_type  = "OrganizationAdmin"
    bypass_mode = "pull_request"
  }

  bypass_actors {
    actor_id    = 5  # built-in Admin repository role
    actor_type  = "RepositoryRole"
    bypass_mode = "pull_request"
  }

  rules {
    required_status_checks {
      strict_required_status_checks_policy = true
      do_not_enforce_on_create              = false

      # --- Pre-existing 5 (carried over unchanged) ---
      required_check {
        context        = "test"
        integration_id = var.actions_integration_id
      }
      required_check {
        context        = "dependency-review"
        integration_id = var.actions_integration_id
      }
      required_check {
        context        = "e2e"
        integration_id = var.actions_integration_id
      }
      required_check {
        context        = "CodeQL"
        integration_id = var.codeql_integration_id
      }
      required_check {
        context        = "skill-security-scan PR gate"
        integration_id = var.actions_integration_id
      }

      # --- Tier 1: secret-scan jobs from .github/workflows/secret-scan.yml ---
      # All 6 jobs run under integration_id 15368 (GitHub Actions).
      required_check {
        context        = "gitleaks scan"
        integration_id = var.actions_integration_id
      }
      required_check {
        context        = "lint fixture content"
        integration_id = var.actions_integration_id
      }
      required_check {
        context        = "allowlist-diff (.gitleaks.toml paths surface)"
        integration_id = var.actions_integration_id
      }
      required_check {
        context        = "rename-guard (allowlist destinations)"
        integration_id = var.actions_integration_id
      }
      required_check {
        context        = "waiver discipline (issue:#NNN trailer)"
        integration_id = var.actions_integration_id
      }
      required_check {
        context        = "Bash fixture tests for guard scripts"
        integration_id = var.actions_integration_id
      }

      # --- Tier 2: non-secret-scan correctness gates from .github/workflows/ci.yml ---
      required_check {
        context        = "lockfile-sync"
        integration_id = var.actions_integration_id
      }
      required_check {
        context        = "service-role-allowlist-gate"
        integration_id = var.actions_integration_id
      }
      required_check {
        context        = "tc-document-sha-guard"
        integration_id = var.actions_integration_id
      }
    }
  }
}
```

**Phase 1.5 — `infra/github/outputs.tf`:**

```hcl
output "ruleset_id" {
  description = "GitHub repository ruleset ID (stable post-import)."
  value       = github_repository_ruleset.ci_required.ruleset_id
}

output "ruleset_url" {
  description = "Browser URL for the ruleset (operator-facing)."
  value       = "https://github.com/${var.gh_owner}/${var.gh_repo}/rules/${github_repository_ruleset.ci_required.ruleset_id}"
}
```

**Phase 1.6 — `infra/github/.gitignore`** (mirror
`apps/web-platform/infra/.gitignore`):

```text
.terraform/
terraform.tfstate
terraform.tfstate.backup
*.tfvars
*.tfvars.json
crash.log
```

### Phase 2 — Import the existing ruleset

**Phase 2.1 — Init the backend.**

```bash
cd infra/github/

# R2 backend creds must be raw (NOT tf-var-transformed — would mangle to
# TF_VAR_aws_* and S3 backend silently fails to authenticate). This is
# the canonical triplet per
# knowledge-base/project/learnings/2026-05-09-drift-runbook-canonical-tf-invocation-and-fresh-plan.md.
export AWS_ACCESS_KEY_ID=$(doppler secrets get AWS_ACCESS_KEY_ID -p soleur -c prd_terraform --plain)
export AWS_SECRET_ACCESS_KEY=$(doppler secrets get AWS_SECRET_ACCESS_KEY -p soleur -c prd_terraform --plain)

terraform init -input=false
```

**Phase 2.2 — Import the ruleset.**

The `github_repository_ruleset` import address per provider v6.x docs
is `<repo>:<ruleset_id>` (NOT `<owner>/<repo>:<ruleset_id>` —
deepen-pass: the provider docs show
`terraform import github_repository_ruleset.example example:12345`,
where `example` is the repo name only; the owner comes from the
provider block's `owner = "jikig-ai"`). Verified against
https://registry.terraform.io/providers/integrations/github/latest/docs/resources/repository_ruleset#import.
Run via Doppler tf-var transformer so `GH_RULESET_PAT` becomes
`TF_VAR_gh_token`:

```bash
doppler run -p soleur -c prd_terraform --name-transformer tf-var -- \
  terraform import github_repository_ruleset.ci_required soleur:14145388
```

If the import errors with "ruleset not found", verify (a) the PAT
has `Administration: Read+Write` (not just `Read`), (b) the owner
in the provider block is `jikig-ai`, (c) the ruleset id is 14145388
(re-fetch via `gh api repos/jikig-ai/soleur/rulesets | jq '.[]
| select(.name=="CI Required") | .id'`).

**Phase 2.3 — `terraform plan` is the test.**

```bash
doppler run -p soleur -c prd_terraform --name-transformer tf-var -- \
  terraform plan -out=tfplan.binary

terraform show -json tfplan.binary | jq '
  .resource_changes[]
  | select(.address == "github_repository_ruleset.ci_required")
  | .change
  | { actions, before_count: (.before.rules[0].required_status_checks[0].required_check | length),
      after_count: (.after.rules[0].required_status_checks[0].required_check | length) }
'
```

**Acceptance:** `before_count: 5, after_count: 14, actions: ["update"]`,
**zero other changes anywhere**. If the diff includes property
re-orderings, conditions tweaks, or bypass-actor changes, STOP — that
indicates ruleset drift the import surfaced; reconcile by editing the
Terraform config to match live state BEFORE proceeding to apply.

**Phase 2.4 — Apply (operator-attested).**

```bash
doppler run -p soleur -c prd_terraform --name-transformer tf-var -- \
  terraform apply tfplan.binary
```

**Phase 2.5 — Verify.**

```bash
gh api repos/jikig-ai/soleur/rulesets/14145388 \
  | jq '.rules[0].parameters.required_status_checks | length'
# Expected: 14
```

### Phase 3 — Article 30 register PA12 entry

Append a new `## Processing Activity 12 — GitHub branch-protection state
custody (CI policy substrate)` section to
`knowledge-base/legal/article-30-register.md` (between current PA11 and
the `## Vendor / Sub-Processor Mapping` section, mirroring PA10's
schema):

- **(b) Purposes:** Operate the CI-policy substrate that gates merges to
  `main` (required status checks, branch protection bypass actors).
  Provide an auditable IaC trail of every change to the branch
  protection policy (Terraform state + git commits + GitHub audit log
  cross-reference).
- **(c) Categories of data subjects:** None of consequence. The GitHub
  PAT bearer (operator-level Soleur engineer) is the sole identifier
  reachable from this root; this is operator-internal, not user-facing.
- **(c) Categories of personal data:** None. Ruleset config is policy
  metadata (check contexts, integration_ids, bypass actor types — none
  of these are personal data per Art. 4(1)).
- **Special categories (Art. 9 / 10):** None.
- **Lawful basis:** Art. 6(1)(f) — legitimate interest (operate the CI
  substrate). No balancing test required absent personal data.
- **(d) Recipients:** Soleur internal (operator only). GitHub holds the
  ruleset state as a sub-processor of the Soleur GitHub org's IaC.
- **(e) Third-country transfers + safeguards:** GitHub Inc. (US);
  existing GitHub Enterprise SCC + DPA covers this (already documented
  in the Vendor / Sub-Processor Mapping section of the register for
  PA-* entries that touch GitHub). The PAT itself is Doppler-resident
  (EU region) until apply time, transferred to GitHub API at apply.
- **(f) Retention:** Indefinite while the policy is in effect. State
  file in R2 is the source-of-truth; rotation events documented in
  Terraform commit history (no separate audit log).
- **(g) TOMs (Art. 32):** (1) PAT scoped to single repo with
  `Administration: Read+Write` only (least privilege); (2) 90-day
  rotation cadence; (3) PAT Doppler-resident, never in git or
  state-plaintext (provider marks `token` sensitive); (4) R2 backend
  versioning + TLS; (5) `terraform plan` as a mandatory pre-apply gate
  (operator-attested); (6) GitHub Actions integration_id pinned in
  Terraform config (15368 / 57789) — drift of the integration_id at
  apply time is a signal of upstream provider change.

### Phase 4 — `infra-validation.yml` extension (3 coordinated edits)

Deepen-pass finding: `.github/workflows/infra-validation.yml` is
hardcoded to `apps/*/infra/**` in THREE places. All three must be
widened in this PR, otherwise `terraform validate` silently
skips `infra/github/` and the AC6 / AC7 gates never fire.

**Phase 4.1 — `paths:` filter (line ~12).** Extend to include
`infra/**`:

```yaml
on:
  pull_request:
    paths:
      - "apps/*/infra/**"
      - "infra/**"
      - ".github/workflows/infra-validation.yml"
```

**Phase 4.2 — `detect-changes` find/git-diff pathspec (lines ~40-43).**
The current form `find apps/*/infra -maxdepth 0 -type d` and
`git diff -- 'apps/*/infra/'` miss `infra/github/`. Refactor to a
list-of-globs:

```yaml
- name: Find changed infra directories
  id: dirs
  env:
    EVENT_NAME: ${{ github.event_name }}
    BASE_REF: ${{ github.base_ref }}
  run: |
    if [[ "$EVENT_NAME" == "workflow_dispatch" ]]; then
      DIRS=$( { find apps/*/infra -maxdepth 0 -type d 2>/dev/null ; \
                 find infra/* -maxdepth 0 -type d 2>/dev/null ; } \
              | jq -R -s -c 'split("\n") | map(select(. != ""))')
    else
      DIRS=$(git diff --name-only "origin/${BASE_REF}...HEAD" -- 'apps/*/infra/' 'infra/' \
        | sed -E 's|^(apps/[^/]+/infra)/.*|\1|; s|^(infra/[^/]+)/.*|\1|' \
        | sort -u \
        | jq -R -s -c 'split("\n") | map(select(. != ""))')
    fi
    printf 'directories=%s\n' "$DIRS" >> "$GITHUB_OUTPUT"
```

**Pathspec→regex translation gate (deepen-plan SKILL.md):**
Both pathspec arguments (`apps/*/infra/`, `infra/`) and both `sed -E`
regex extractions must cover three shapes: top-level (impossible
under either pathspec — both require a parent), single-ancestor
(`apps/web-platform/infra/...` or `infra/github/...`), and
deep-nested (`apps/web-platform/infra/sentry/...` or
`infra/github/<future-subdir>/...`). The `sed -E` regex anchors
on `^apps/[^/]+/infra` and `^infra/[^/]+` — verify each shape with
a fixture test:

```bash
printf 'apps/web-platform/infra/main.tf\napps/web-platform/infra/sentry/main.tf\ninfra/github/main.tf\ninfra/github/README.md\n' \
  | sed -E 's|^(apps/[^/]+/infra)/.*|\1|; s|^(infra/[^/]+)/.*|\1|' \
  | sort -u
# Expected: apps/web-platform/infra
#           infra/github
```

**Phase 4.3 — Matrix unchanged.** The `validate` job consumes
`${{ matrix.directory }}` directly; no further edit needed once
the directory list includes `infra/github/`.

The job runs **without** Doppler creds (validate is offline via
`terraform init -backend=false`), mirroring the existing
`apps/web-platform/infra/` and `apps/web-platform/infra/sentry/`
entries.

**Acceptance:** A scratch PR touching `infra/github/main.tf`
triggers `infra-validation` with `directory=infra/github` in the
matrix, and `terraform validate` returns success.

### Phase 5 — ADR-032 (architecture decision record)

Mirror ADR-031 (sentry-as-iac) shape; new file
`knowledge-base/engineering/architecture/decisions/ADR-032-github-branch-protection-as-iac.md`.
~30 lines:

- **Context:** AGENTS.md `hr-all-infrastructure-provisioning-servers`
  mandates Terraform for branch protections; the ruleset was previously
  managed via the GitHub UI which produced silent drift (PR #3886 merge
  with failing check). No `infra/github/` root existed.
- **Decision:** Adopt `integrations/github` v6.x provider; new
  `infra/github/` root with R2 backend (key
  `github/terraform.tfstate`); ruleset 14145388 adopted via import.
- **Consequences:** Ruleset edits now go through PR + Terraform plan +
  operator-attested apply. The deferred Tier-3 expansions (smoke (*)
  matrix rollup, Block * family rollup, etc.) become per-PR edits to
  this root rather than UI clicks.

### Phase 6 — Follow-up issues (file, do NOT bundle)

Create five GitHub issues post-apply (Phase 6 of the runbook). Each
issue body references this PR as parent context.

1. **#3888 hook** — file follow-up confirming that the new required
   check `allowlist-diff (.gitleaks.toml paths surface)` makes #3888's
   fix gate merges. Title: `secret-scan: confirm allowlist-diff parser
   widening (#3888) now blocked at merge gate post-ruleset-widening`.
   Label: `priority/p3-low`, `domain/engineering`. Body: links #3888 as
   the **shadowing fix** issue, this PR as the **gate-widening**, and
   notes that the two together close the failure mode.

2. **smoke (*) matrix** — file: `secret-scan: add 'secret-scan smoke
   matrix complete' rollup job + require in CI Required ruleset`.
   Rationale: the 9-job matrix can't be required directly (each
   matrix-leg name is `smoke (<case>)`, which is implementation-coupled
   and grows whenever a new case lands). Need a rollup job that depends
   on all matrix legs, then require the rollup. Label:
   `priority/p3-low`, `domain/engineering`, `type/chore`.

3. **`Block *` family** — file: `ci: add 'pr-quality-guards rollup' job
   + require in CI Required ruleset`. Same rollup pattern: the 6 `Block
   *` jobs in `.github/workflows/pr-quality-guards.yml` need a rollup.
   Label: same as above.

4. **`Analyze (*)` CodeQL subjobs** — file: `ci: investigate whether
   'CodeQL' parent check already aggregates 'Analyze (*)' subjobs`.
   Hypothesis: the existing required `CodeQL` (integration_id 57789) is
   the rollup; needs verification by examining a failing CodeQL Analyze
   run to confirm the parent surfaces FAILURE. If not, file a follow-up
   for the rollup. Label: same.

5. **docs/perf gates** — file: `ci: enumerate docs + perf gates and
   evaluate required-check candidates`. Scope: `deploy-docs.yml`,
   `web-platform-build`, `critical-css-gate`, `readme-counts` — each
   has a different ship-blocking weight. Label: same.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1 — `infra/github/main.tf` exists with R2 backend block matching
  the apps/web-platform/infra/sentry/main.tf shape (verified via
  `diff <(awk '/^terraform/,/^}/' apps/web-platform/infra/sentry/main.tf
  | head -30) <(awk '/^terraform/,/^}/' infra/github/main.tf | head -30)`
  — the only intended diff is `key = "github/terraform.tfstate"` vs the
  sentry root's key, and the absence of the Sentry provider block).
- [ ] AC2 — `infra/github/versions.tf` pins `integrations/github`
  to `~> 6.0`; `.terraform.lock.hcl` committed.
- [ ] AC3 — `infra/github/ruleset-ci-required.tf` declares exactly 14
  `required_check` blocks (verified via
  `grep -c '^      required_check {' infra/github/ruleset-ci-required.tf`
  → `14`).
- [ ] AC4 — All 9 new check contexts appear as **literal exact** strings
  matching the workflow job `name:` fields (verified via
  `for ctx in 'gitleaks scan' 'lint fixture content' 'allowlist-diff (.gitleaks.toml paths surface)' 'rename-guard (allowlist destinations)' 'waiver discipline (issue:#NNN trailer)' 'Bash fixture tests for guard scripts' 'lockfile-sync' 'service-role-allowlist-gate' 'tc-document-sha-guard'; do grep -F "$ctx" infra/github/ruleset-ci-required.tf || echo "MISSING: $ctx"; done`
  emits zero `MISSING:` lines).
- [ ] AC5 — All 9 new contexts are valid GitHub Actions job names
  (verified by greppping `.github/workflows/secret-scan.yml` and
  `.github/workflows/ci.yml` for each context string;
  `grep -nF '<context>' .github/workflows/<file>.yml` returns ≥1 match
  per context). Note: punctuation must match exactly — `:`, `(`, `)`,
  `.` are all load-bearing.
- [ ] AC6 — `terraform validate` passes in `infra/github/` (run in
  `.github/workflows/infra-validation.yml` matrix-extended job).
- [ ] AC7 — `.github/workflows/infra-validation.yml` matrix includes
  `infra/github/`.
- [ ] AC8 — Article 30 register PA12 entry exists (verified via
  `grep -c '^## Processing Activity 12' knowledge-base/legal/article-30-register.md`
  → `1`); all 8 limbs present (verified via the eight `**` field labels).
- [ ] AC9 — ADR-032 created and references ADR-006 (R2 backend) +
  ADR-031 (sentry-as-iac precedent).
- [ ] AC10 — README.md operator runbook in `infra/github/` covers
  Phase 0 (Doppler setup), Phase 1 (init), Phase 2 (import + plan +
  apply), Phase 3 (verify), Phase 4 (rotation), Phase 5 (rollback).
- [ ] AC11 — No tfvars files committed (verified via
  `git ls-files infra/github/ | grep -E '\.tfvars' || echo CLEAN`
  emits `CLEAN`).
- [ ] AC12 — PR body uses `Ref #3888`, NOT `Closes #3888` (this PR
  widens the gate; #3888 is the parser fix, separate scope — per
  `wg-use-closes-n-in-pr-body-not-title-to` and the ops-remediation
  variant rule for post-merge state changes).

### Post-merge (operator)

- [ ] AC13 — **Automation feasibility:** This phase is operator-driven
  by design because the apply mutates production branch-protection
  state, requiring two-factor operator attestation per
  `hr-menu-option-ack-not-prod-write-auth`. The apply is NOT a
  `gh workflow run` candidate (would bypass the human attestation
  rule). Documented in the runbook §Apply.
- [ ] AC14 — Operator runs Phase 0 (Doppler setup) and
  Phase 2 (import + plan + apply) per the runbook.
- [ ] AC15 — `terraform plan` (pre-apply) shows the canonical 9-add
  diff: `~ resource "github_repository_ruleset" "ci_required" {
  ~ required_status_checks { + required_check {...} (× 9) } }` and
  **nothing else** (verified via the `terraform show -json` jq probe
  in Phase 2.3 — `before_count: 5, after_count: 14, actions:
  ["update"]`). Any other diff requires reconciliation and
  re-planning.
- [ ] AC16 — Apply succeeds; `gh api repos/jikig-ai/soleur/rulesets/14145388
  | jq '.rules[0].parameters.required_status_checks | length'`
  returns `14`.
- [ ] AC17 — Operator files the five follow-up issues per Phase 6.
- [ ] AC18 — Operator closes #3888 with reference comment confirming
  the gate now exists (NOT auto-closed — see `Closes` discipline
  above; closure happens after AC16 confirms apply success).

## Test Strategy

This is an infra-only change; the "test" is `terraform plan` showing
exactly the expected diff. The Tier-1 verification triplet:

1. **Static validation:** `terraform validate` in CI via
   `infra-validation.yml` — catches syntax and provider-schema errors
   pre-merge.
2. **Plan diff probe (operator, post-merge):** Phase 2.3's
   `terraform show -json | jq ...` probe — asserts the 9-addition
   shape with zero side effects. Documented as the canonical
   pre-apply gate.
3. **Live API verification (operator, post-apply):** Phase 2.5's
   `gh api ... | jq '... | length'` returns `14`.

No unit test framework is appropriate (the Terraform config IS the
test — there's no logic to unit-test, only a declarative resource
spec). No `pytest`/`bun test`/etc. addition.

## Risks

- **R1 — Import-time drift.** The live ruleset may carry properties
  the Terraform config doesn't model (e.g., `do_not_enforce_on_create`
  defaults, conditions edge cases, bypass-actor `actor_id` quirks).
  Mitigation: Phase 2.3's plan-diff probe surfaces this BEFORE apply;
  operator reconciles by editing the Terraform config to match live
  state, NOT by applying the unreviewed diff. The import oracle
  (Phase 0.4) is the diff reference.
- **R2 — Integration_id drift.** GitHub may renumber Actions
  integration_id (currently 15368) or CodeQL (57789). Mitigation:
  Phase 1.3 pins both as variables with documented defaults; the
  Article 30 PA12 TOM clause documents that drift is a signal of
  upstream provider change. A future PR would update the variable
  default and re-apply.
- **R3 — Provider major-version drift.** `integrations/github` v6.x
  is the chosen pin; the v7.x major (if released) may break the
  `github_repository_ruleset` schema. Mitigation: `~> 6.0` pin in
  versions.tf prevents implicit upgrade. Lockfile committed.
- **R4 — PAT expiry.** 90-day FGPAT expiry will cause `apply` to fail
  with 401 after rotation deadline. Mitigation: runbook §Rotation
  documents the cadence; calendar reminder at +75 days. Filing a
  follow-up issue for `scheduled-gh-token-expiry-check.yml` (sibling
  to `scheduled-cf-token-expiry-check.yml`) is out of scope for this
  PR — noted as a Tier-3 expansion.
- **R5 — Required-check name drift.** A workflow job rename (e.g.,
  `lint fixture content` → `lint-fixture-content`) would break the
  required check until the Terraform config is updated. Mitigation:
  document the contract in ADR-032 (job names are public ABI for
  branch protection); the renamer must update `infra/github/` in the
  same PR. A future hook could enforce this (out of scope).
- **R6 — Bypass-actor ordering drift.** Provider issue #2504 reports
  that `github_repository_ruleset` shows phantom diffs intermittently
  when multiple `bypass_actors` blocks are defined — the provider
  re-orders state entries against config in a non-deterministic way.
  Live state has two (OrganizationAdmin + RepositoryRole id=5).
  Mitigation: if Phase 2.3 surfaces ordering churn, add a
  `lifecycle { ignore_changes = [bypass_actors] }` block to the
  resource and document the operator-attested escape hatch. This is
  the SAME pattern as the import-only Sentry resources in
  `apps/web-platform/infra/sentry/` per ADR-031 / learning
  `2026-05-15-terraform-import-only-beta-provider-schema-validation.md`.
- **R7 — `actor_id` for `OrganizationAdmin` (provider issue #2536).**
  GitHub's API returns `actor_id: null` for `OrganizationAdmin`
  bypass actors. The provider previously expected `actor_id = 1`
  (the documented OrganizationAdmin role id); GitHub then changed
  the internal value to `0`. Current consensus in the issue thread
  is `actor_id = 0` for v6.10+, but the provider may still surface
  phantom diffs between `0` and `1` depending on patch version.
  Mitigation: Phase 2.3 surfaces this before apply. Recovery
  sequence: (a) confirm provider is `>= 6.10.0`, (b) try
  `actor_id = 0`, (c) if drift persists, try `actor_id = 1`,
  (d) if drift still persists, add
  `lifecycle.ignore_changes = [bypass_actors[*].actor_id]`.
- **R8 — `required_check` schema-vs-API mismatch (#2467, #2317).**
  Provider issue #2467 reports `required_check` is marked Required
  in the provider schema even though the API allows omitting it
  (empty status-checks list). Not blocking for this PR (we set 14
  required checks; the schema is satisfied). Issue #2317 reports
  that `integration_id` omission produces phantom drift if GitHub
  later reports a non-null integration_id. Mitigation: plan sets
  `integration_id` explicitly on every `required_check` block
  (matching live state's values 15368 / 57789) to suppress this
  drift class entirely.
- **R9 — `bypass_actors` removal is silently no-op (#2952).** If a
  future PR removes a `bypass_actors` block, the provider may not
  actually delete the entry on GitHub. Not in scope for this PR
  (we adopt the existing 2 actors verbatim). Mitigation:
  documented in ADR-032 as a known v6.x edge — future removals
  require manual API verification.
- **R10 — v6.x init regression risk.** v6.7.4 had a documented
  `Internal validation error during TF Init` (#2855). Mitigation:
  Phase 1.2 pin is now `~> 6.10` (rather than `~> 6.0`); patch
  version locked in `.terraform.lock.hcl`.

## Sharp Edges

- **A plan whose `## User-Brand Impact` section is empty, contains only
  `TBD`/`TODO`/placeholder text, or omits the threshold will fail
  `deepen-plan` Phase 4.6. This plan declares `aggregate pattern`.**
- The 9 new required-check contexts are literal job `name:` fields. A
  punctuation drift (e.g., a maintainer who "fixes" `(.gitleaks.toml
  paths surface)` to remove parens) silently un-requires the check.
  ADR-032 documents this fragility.
- The `prd_terraform` Doppler config is shared with
  `apps/web-platform/infra/` — adding `GH_RULESET_PAT` there does NOT
  pollute the existing TF root (it's only consumed when `infra/github/`
  runs `doppler run --name-transformer tf-var`).
- The R2 backend block in `infra/github/main.tf` uses
  `key = "github/terraform.tfstate"` (NOT `web-platform/github/...`).
  This root is repo-level (branch protection is a repo concern), not
  app-level — placing the key under `web-platform/` would mis-signal
  ownership for a future multi-app reorg.
- `terraform import` is **operator-only**, never CI-automated, per
  `hr-menu-option-ack-not-prod-write-auth`. The auto-apply patterns
  documented in `apply-deploy-pipeline-fix.yml` and
  `apply-sentry-infra.yml` (which use `-target=`-scoped applies for
  create-only resources) do NOT apply here — the ruleset import +
  widen requires single human attestation.
- The `Allowlist-Widened-By:` trailer / `secret-scan-allowlist-ack`
  label mechanism is **separate** from this ruleset gate. The trailer
  enforces operator-ack on `.gitleaks.toml` widenings; the ruleset
  enforces secret-scan jobs must pass before merge. They are
  complementary — this PR does not change the trailer mechanism.
- Per `hr-write-boundary-sentinel-sweep-all-write-sites`: there are no
  TS write sites in this PR, but the analog is sweep-all-workflow-job-
  name-edits. If a future PR renames `gitleaks scan` to `Gitleaks
  scan` (capitalization), the required-check entry becomes a
  permanent-pending state. The ADR-032 contract clause covers this.
- **Provider v6.x rough edges (deepened).** Five known provider
  issues touch this PR's surface: #2317 (integration_id drift),
  #2467 (required_check Required-vs-API), #2504 (bypass_actors
  ordering drift), #2536 (OrganizationAdmin actor_id 1↔0), #2952
  (bypass_actors removal no-op). The pin `~> 6.10` is the floor
  per learning `2026-03-19-github-ruleset-stale-bypass-actors.md`.
  Phase 2.3 plan-diff probe is the load-bearing check that catches
  any of the above producing unexpected diff at import time.
- **Phase 4's three coordinated edits to `infra-validation.yml`
  are not optional.** Without ALL three (paths filter +
  detect-changes find + detect-changes git-diff pathspec), AC6/AC7
  appear to pass (the validate job runs on the existing apps/*
  paths) but `infra/github/` itself is silently skipped from
  validation in CI. The fixture-test prescription in Phase 4.2
  exercises all three shapes (top-level/single-ancestor/
  deep-nested) per the deepen-plan pathspec→regex translation
  gate.

## Operator Runbook (canonical form for `infra/github/README.md`)

```text
# infra/github/ — GitHub branch-protection Terraform root

Mirrors apps/web-platform/infra/sentry/ pattern. State key: github/terraform.tfstate.

## Phase 0 — Doppler setup (one-time)

1. Mint a fine-grained PAT at
   https://github.com/settings/personal-access-tokens/new
   - Resource owner: jikig-ai
   - Repository access: select jikig-ai/soleur ONLY
   - Permissions: Administration: Read+Write (Metadata: Read auto)
   - Expiration: 90 days
   - Name: terraform-infra-github-rulesets

2. Stash in Doppler prd_terraform:
   doppler secrets set GH_RULESET_PAT='<token>' -p soleur -c prd_terraform

3. Verify:
   GH_TOKEN=$(doppler secrets get GH_RULESET_PAT -p soleur -c prd_terraform --plain) \
     gh api repos/jikig-ai/soleur/rulesets/14145388 | jq '.id'
   # Expected: 14145388

## Phase 1 — Init

cd infra/github/

export AWS_ACCESS_KEY_ID=$(doppler secrets get AWS_ACCESS_KEY_ID -p soleur -c prd_terraform --plain)
export AWS_SECRET_ACCESS_KEY=$(doppler secrets get AWS_SECRET_ACCESS_KEY -p soleur -c prd_terraform --plain)

terraform init -input=false

## Phase 2 — Import + plan + apply (one-time bootstrap)

doppler run -p soleur -c prd_terraform --name-transformer tf-var -- \
  terraform import github_repository_ruleset.ci_required jikig-ai/soleur:14145388

doppler run -p soleur -c prd_terraform --name-transformer tf-var -- \
  terraform plan -out=tfplan.binary

# Verify diff is exactly the 9 additions:
terraform show -json tfplan.binary | jq '
  .resource_changes[]
  | select(.address == "github_repository_ruleset.ci_required")
  | .change.after.rules[0].required_status_checks[0].required_check
  | length
'
# Expected: 14 (5 pre-existing + 9 new)

# If diff includes anything else, STOP — reconcile config to match live state.

doppler run -p soleur -c prd_terraform --name-transformer tf-var -- \
  terraform apply tfplan.binary

## Phase 3 — Verify post-apply

gh api repos/jikig-ai/soleur/rulesets/14145388 \
  | jq '.rules[0].parameters.required_status_checks | length'
# Expected: 14

## Phase 4 — Rotation (every 90 days)

1. Mint new PAT (same scope as Phase 0).
2. doppler secrets set GH_RULESET_PAT='<new-token>' -p soleur -c prd_terraform
3. Revoke old PAT at https://github.com/settings/personal-access-tokens.

## Phase 5 — Rollback

If a Terraform apply broke the ruleset:

1. Read the previous state version from R2:
   aws --endpoint-url=https://4d5ba6f096b2686fbdd404167dd4e125.r2.cloudflarestorage.com \
     s3api list-object-versions --bucket soleur-terraform-state \
     --prefix github/terraform.tfstate

2. Restore the prior version (operator-attested):
   aws --endpoint-url=... s3api copy-object \
     --copy-source soleur-terraform-state/github/terraform.tfstate?versionId=<prev> \
     --bucket soleur-terraform-state --key github/terraform.tfstate

3. terraform apply -refresh-only to sync R2-restored state to GitHub API.

For catastrophic ruleset corruption: emergency fallback is the GitHub UI
at https://github.com/jikig-ai/soleur/rules/14145388 — operator can
manually restore the 5 baseline checks; then re-import from clean state.
```
