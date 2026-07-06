# CLA Required ruleset (id 13304872) -- Terraform-managed as of #6072, mirroring
# the sibling CI Required ruleset (id 14145388, ruleset-ci-required.tf) per
# ADR-032. Adopted via `terraform import` on the first apply-github-infra.yml run
# (see infra/github/README.md). Its enforced values are BYTE-IDENTICAL to the
# former imperative scripts/create-cla-required-ruleset.sh payload and to the two
# canonical JSONs the daily cron-ruleset-bypass-audit reads
# (scripts/ci-cla-required-ruleset-canonical-{bypass-actors,required-status-checks}.json).
# This migrated the DECLARATION surface only, not any enforced policy value.
#
# Divergences from the CI ruleset (ruleset-ci-required.tf), all intended:
#   - strict policy is FALSE here (CI is true): the CLA gate does not require the
#     branch be up-to-date before merge (preserved from the live ruleset).
#   - THREE bypass actors (CI has two): the extra one is the CLA bot Integration
#     (id 1236702, always mode), which must update CLA status on every PR.
#   - TWO required checks (cla-check, cla-evidence), both GitHub Actions checks
#     (integration id 15368). CLA has no GHAS/CodeQL rollup check, so -- unlike
#     CI -- this file references no GHAS integration id.
#
# SE-1 (0<->null sentinel): the live API and the canonical bypass JSON carry
# actor_id null for OrganizationAdmin; the provider's HCL form for null is 0 on
# v6.10+ (provider issue #2536), so the OrganizationAdmin block below uses 0. The
# T-cla-1b sync gate normalizes 0->null before comparing the `.tf` to the
# canonical (do NOT change the canonical to 0 -- it mirrors the live API shape
# the daily audit compares against).
#
# Job-name contract (ADR-032): the two check context strings below are public ABI
# for the CLA branch-protection gate. Renaming the cla-check / cla-evidence jobs
# (.github/workflows/cla.yml, .github/workflows/cla-evidence.yml) silently
# un-requires the check until this resource is updated in the same PR.
resource "github_repository_ruleset" "cla_required" {
  name        = "CLA Required"
  repository  = var.gh_repo
  target      = "branch"
  enforcement = "active"

  conditions {
    ref_name {
      include = ["~DEFAULT_BRANCH"]
      exclude = []
    }
  }

  # OrganizationAdmin: actor_id 0 is the null sentinel (see SE-1 in the header).
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

  # The CLA bot -- the one actor the CI ruleset does not carry. `always` mode so
  # it can update CLA status on every PR (IN the canonical; not a widening).
  bypass_actors {
    actor_id    = 1236702
    actor_type  = "Integration"
    bypass_mode = "always"
  }

  rules {
    required_status_checks {
      strict_required_status_checks_policy = false
      do_not_enforce_on_create             = false

      required_check {
        context        = "cla-check"
        integration_id = var.actions_integration_id
      }
      required_check {
        context        = "cla-evidence"
        integration_id = var.actions_integration_id
      }
    }
  }
}
