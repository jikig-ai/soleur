# Learning: GitHub Rulesets Do Not Auto-Prune Bypass Actors

## Problem

GitHub rulesets bypass_actors array retains entries for apps that have been uninstalled or deleted. These ghost entries are invisible to standard API discovery (GET /apps/{id} returns 404, not listed in org installations) but retain full bypass privileges on security-critical rulesets.

## Solution

1. Enumerate bypass actors via `gh api repos/{owner}/{repo}/rulesets/{id}`
2. For each Integration actor, verify via `GET /apps/{actor_id}` — a 404 means the app is deleted/uninstalled
3. Remove stale entries via PUT with the complete ruleset payload (array replacement semantics — the provided array replaces the existing one wholesale)
4. Verify via separate GET that all other fields are unchanged

The `gh api --method PUT --input /tmp/payload.json` pattern avoids shell escaping issues with nested JSON.

## Key Insight

GitHub does not automatically prune bypass_actors when apps are uninstalled. This creates invisible security debt — unidentifiable integrations with `bypass_mode: "always"` on enforcement rulesets. Periodic audits of bypass_actors should check each Integration entry against the Apps API.

## Prevention

- After uninstalling a GitHub App, check all rulesets for leftover bypass entries
- Periodically audit rulesets via `gh api repos/{owner}/{repo}/rulesets` and verify all Integration bypass actors are identifiable
- The Terraform github_repository_ruleset resource had related bugs (#2269, #2952) in the go-github client library — if managing rulesets via Terraform, ensure provider >= v6.10.0

## Tags

category: integration-issues
module: github-rulesets
