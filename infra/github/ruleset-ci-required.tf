# CI Required ruleset (id 14145388) -- adopted via `terraform import` per the
# README.md Phase 2 runbook. WIDENED from 5 to 14 required status checks to
# close the secret-scan-failure-merged gap surfaced by PR #3886
# (`lint fixture content` failed and merged because it was not required).
# #4385 then added `enforce` (15th; the "14" wording above is the #3886
# import figure and was left stale). #5585 adds `tenant-integration-required`
# (16th) — the first PATH-FILTERED required check: an always-run aggregator
# gate job (see .github/workflows/tenant-integration.yml) that fails closed, so
# the path-filtered tenant-isolation suite gates merges without leaving
# unrelated PRs "Expected — Waiting". See ADR-032.
#
# Bypass actors preserved from the live ruleset:
#   - OrganizationAdmin (actor_id = 0 per provider issue #2536)  -- pull_request mode
#   - RepositoryRole id = 5 (built-in Admin)                     -- pull_request mode
#
# Strict policy preserved (strict_required_status_checks_policy = true).
#
# Job-name contract: the 17 `context` strings below are public ABI for the
# branch-protection gate. A workflow job rename (`lint fixture content` ->
# `lint-fixture-content`) silently un-requires the check until this resource
# is updated in the same PR. See ADR-032 Sharp Edges.
#
# #6049 adds `adr-ordinals` (17th) — a ci.yml always-run gate job that the live
# ruleset already required but this IaC root + the canonical JSON omitted (an
# IaC-revert latent bug: the next apply would have computed it unmanaged and
# REMOVED it from live). Reconciled here as a no-op apply (live already has it).
#
# #5780 adds a second rule sibling — a `merge_queue` block (below the
# required_status_checks block) — adopting a GitHub merge queue for `main` to
# fix the strict-up-to-date BEHIND starvation. The queue REQUIRES every
# required-check workflow to also fire on `merge_group` (landed in PR-1,
# #5784), else queue entries stall pending forever. Because `rules` now holds
# TWO rule types, any code/probe that reads the required-status-checks rule
# MUST select by type (`select(.type=="required_status_checks")`), never a
# positional `.rules[0]` — the apply-verify probe and audit script already do.
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
      # adr-ordinals (#6049): always-run ADR-ordinal-collision gate job in
      # .github/workflows/ci.yml. GitHub Actions context (integration_id 15368,
      # NOT GHAS 57789 — using the CodeQL id would silently un-match the gate).
      # Reconciled from live, which already required it; see the count-contract
      # comment at the top of this file.
      required_check {
        context        = "adr-ordinals"
        integration_id = var.actions_integration_id
      }

      # --- Tier 3: legal-doc cross-document lockstep gate (#4384, closes the
      # advisory-bypass-via-auto-merge gap that produced #4333). Context
      # string is the JOB name (`enforce`) at
      # .github/workflows/legal-doc-cross-document-gate.yml:36, NOT the
      # workflow display name — per ADR-032 job-name contract. Workflow
      # `paths:` filter removed in the same PR (#4384) so the job posts on
      # every PR; the existing `surface_hit=false` short-circuit (lines
      # 82-85) keeps non-DSAR PRs at O(seconds). See learning
      # 2026-03-20-github-required-checks-skip-ci-synthetic-status.md.
      required_check {
        context        = "enforce"
        integration_id = var.actions_integration_id
      }

      # --- Tier 4: tenant-isolation suite required-check shim (#5585). Context
      # is the JOB name `tenant-integration-required` at
      # .github/workflows/tenant-integration.yml — an always-run (if: always())
      # aggregator that fails closed when the dev-Supabase tenant-isolation
      # suite is red. Runs under GitHub Actions (integration_id 15368), so bot
      # PRs satisfy it via the synthetic check-run posted by
      # bot-pr-with-synthetic-checks (CHECK_NAMES) — same as the other 15368
      # checks. Unlike them, the heavy suite is path-gated (detect-changes), so
      # this is the first conditionally-skipped-but-required check. See ADR-032.
      required_check {
        context        = "tenant-integration-required"
        integration_id = var.actions_integration_id
      }
    }

    # Merge queue REVERTED (#5780 kill-switch, 2026-06-30). The queue was
    # enabled by PR #5800 but DEADLOCKED main: GitHub CodeQL *default setup*
    # does not run / post the required `CodeQL` context on a `merge_group`
    # temp ref (it fires only on `push`/`pull_request`), so every queue entry
    # stalled AWAITING_CHECKS until the 15-min timeout, then re-jammed (3 real
    # PRs — #5808/#5794/#5798 — were stuck). All 15 OTHER required contexts DID
    # report on the temp ref, so PR-1's `merge_group` wiring is correct; the
    # gap is CodeQL-on-`merge_group` only. Reverting to direct-merge restores
    # CodeQL coverage (it runs on `pull_request`). Re-adopt the queue ONLY
    # after CodeQL is converted to *advanced* setup (a `codeql.yml` workflow
    # with an `on: merge_group` trigger) so the `CodeQL` context posts on the
    # temp ref. Tracked in #5780; see the PIR + ADR-032 amendment.
  }
}
