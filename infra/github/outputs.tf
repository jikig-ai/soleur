output "ruleset_id" {
  description = "GitHub repository ruleset ID (stable post-import)."
  value       = github_repository_ruleset.ci_required.ruleset_id
}

output "ruleset_url" {
  description = "Browser URL for the ruleset (operator-facing)."
  value       = "https://github.com/${var.gh_owner}/${var.gh_repo}/rules/${github_repository_ruleset.ci_required.ruleset_id}"
}
