# Pin floor `~> 6.10` per repo-local learning
# knowledge-base/project/learnings/2026-03-19-github-ruleset-stale-bypass-actors.md.
# Provider issues #2179/#2269/#2317/#2467/#2504/#2536/#2855/#2952 affect
# earlier 6.x patch versions and touch `bypass_actors` / `required_check` /
# `integration_id` -- exactly the surface this root manages. Lockfile pins
# the exact patch; bump deliberately via README.md Phase 4.
terraform {
  required_version = ">= 1.6"

  required_providers {
    github = {
      source  = "integrations/github"
      version = "~> 6.10"
    }
  }
}
