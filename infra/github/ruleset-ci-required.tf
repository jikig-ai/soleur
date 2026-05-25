# CI Required ruleset (id 14145388) -- adopted via `terraform import` per the
# README.md Phase 2 runbook. WIDENED from 5 to 14 required status checks to
# close the secret-scan-failure-merged gap surfaced by PR #3886
# (`lint fixture content` failed and merged because it was not required).
#
# Bypass actors preserved from the live ruleset:
#   - OrganizationAdmin (actor_id = 0 per provider issue #2536)  -- pull_request mode
#   - RepositoryRole id = 5 (built-in Admin)                     -- pull_request mode
#
# Strict policy preserved (strict_required_status_checks_policy = true).
#
# Job-name contract: the 14 `context` strings below are public ABI for the
# branch-protection gate. A workflow job rename (`lint fixture content` ->
# `lint-fixture-content`) silently un-requires the check until this resource
# is updated in the same PR. See ADR-032 Sharp Edges.
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

  # actor_id = 0 sentinel for OrganizationAdmin per provider issue #2536
  # (live API returns null; provider's HCL form for null is 0 on v6.10+).
  # If Phase 2.3 plan-diff probe surfaces bypass_actors churn, add
  # `lifecycle { ignore_changes = [bypass_actors] }` per Risk R6.
  bypass_actors {
    actor_id    = 0
    actor_type  = "OrganizationAdmin"
    bypass_mode = "pull_request"
  }

  bypass_actors {
    actor_id    = 5 # built-in Admin repository role
    actor_type  = "RepositoryRole"
    bypass_mode = "pull_request"
  }

  rules {
    required_status_checks {
      strict_required_status_checks_policy = true
      do_not_enforce_on_create             = false

      # --- Baseline 5 (verified against ruleset-live-pre-import.json at adoption) ---
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

      # --- Tier 1: secret-scan + guard-script-fixture jobs ---
      # All 6 jobs run under GitHub Actions (integration_id 15368) on every
      # PR (no path filters). 5 from .github/workflows/secret-scan.yml,
      # 1 ("Bash fixture tests for guard scripts") from
      # .github/workflows/pr-quality-guards.yml.
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

      # --- Tier 3: legal-doc cross-document lockstep gate (#4384, closes the
      # advisory-bypass-via-auto-merge gap that produced #4333). Context
      # string is the JOB name (`enforce`) at
      # .github/workflows/legal-doc-cross-document-gate.yml:36, NOT the
      # workflow display name — per ADR-032 job-name contract. Workflow
      # `paths:` filter removed in the same PR (#4384) so the job posts on
      # every PR; the existing `surface_hit=false` short-circuit (lines
      # 85-88) keeps non-DSAR PRs at O(seconds). See learning
      # 2026-03-20-github-required-checks-skip-ci-synthetic-status.md.
      required_check {
        context        = "enforce"
        integration_id = var.actions_integration_id
      }
    }
  }
}
