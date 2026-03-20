---
title: "GitHub Actions Bot Cannot Be Added as Ruleset Bypass Actor"
date: 2026-03-19
category: integration-issues
module: github-rulesets
tags: [cla, github-api, rulesets, bypass-actors, github-actions]
---

# Learning: GitHub Actions Bot Cannot Be Added as Ruleset Bypass Actor

## Problem

After hardening the CLA Required ruleset (ID 13304872) in `jikig-ai/soleur` by adding `integration_id: 15368` to the `cla-check` required status check (restricting which app can satisfy the check), we attempted to add `github-actions[bot]` as a bypass actor so bot-authored PRs could skip the CLA check entirely. The goal was to prevent CLA friction for automated PRs from CI workflows while simultaneously closing the security gap where any actor could post a passing `cla-check` status.

## Investigation

1. **Successfully added `integration_id: 15368`** to the `cla-check` required status check via `gh api PUT /repos/{owner}/{repo}/rulesets/{id}`. This locked down who can satisfy the check to only the `github-actions` app (app ID 15368), closing the spoofing gap tracked in issue #773.

2. **Attempted to add `github-actions` as a bypass actor** using the Rulesets API with `actor_type: "Integration"` and `actor_id: 15368`. The API returned HTTP 422 with the error:

   > Actor GitHub Actions integration must be part of the ruleset source or owner organization

3. **Investigated the error.** The `github-actions` app (ID 15368) is a GitHub platform-native identity — it powers `GITHUB_TOKEN` authentication in all Actions workflows. Unlike installable GitHub Apps (which appear in Settings > Integrations and can be referenced as bypass actors), `github-actions` is built into the platform itself. It is not "installed" on any repository or organization in the way the Rulesets API expects.

4. **Confirmed workaround already in place.** Bot workflows already use the PR-based commit pattern with synthetic `cla-check` statuses posted via the GitHub Statuses API. Because these statuses are posted using `GITHUB_TOKEN` (which authenticates as the `github-actions` app, ID 15368), they satisfy the `integration_id: 15368` constraint. The bypass actor is unnecessary — the existing pattern already works.

## Solution

Accepted the platform limitation. The bypass actor addition was abandoned because it is not needed:

- **`integration_id: 15368`** on the `cla-check` required status ensures only `github-actions` app can satisfy the check (security hardening — done).
- **PR-based commit pattern** with synthetic `cla-check` statuses already allows bot PRs to pass the ruleset (functional requirement — already met).
- **No bypass actor needed** because bot workflows satisfy the check through the normal path (synthetic status from the correct integration), not by bypassing it.

## Key Insight

GitHub's `github-actions` app (ID 15368) occupies a unique position in the platform: it is the identity behind every `GITHUB_TOKEN`-authenticated API call, it appears as the author of check runs and commit statuses, but it is **not an installable GitHub App integration**. The Rulesets API requires bypass actors to be "part of the ruleset source or owner organization" — meaning they must be explicitly installed apps, teams, or roles. Platform-native identities like `github-actions` do not qualify.

This means any strategy that relies on `github-actions[bot]` bypass in rulesets will fail. The correct alternatives are:

1. **Synthetic statuses from workflows** — post passing statuses using `GITHUB_TOKEN`, which authenticates as `github-actions` (app ID 15368). Combine with `integration_id` on the required check to lock down who can satisfy it.
2. **Dedicated custom GitHub App** — create and install a purpose-built app that CAN be added as a bypass actor.
3. **Repository role bypass** — use `maintain` or `admin` role-based bypass (but this opens bypass to all users with that role, not just bots).

Option 1 is the lightest-weight and is already implemented across all bot workflows in this repository.

## Session Errors

1. **HTTP 422 from GitHub Rulesets API** — `PUT /repos/jikig-ai/soleur/rulesets/13304872` returned `Actor GitHub Actions integration must be part of the ruleset source or owner organization` when attempting to add `github-actions` (actor ID 15368, type Integration) as a bypass actor.
2. **python3 json.tool parse error** — `gh api` response mixed stdout (JSON body) with stderr (HTTP status line), causing `python3 -m json.tool` to fail on the combined output. Fix: pipe only stdout, or use `gh api --jq '.'` instead of external JSON formatting.

## Prevention

- **Before planning ruleset bypass actors**, verify the target identity is an installable GitHub App by checking `GET /orgs/{org}/installations` or `GET /repos/{owner}/{repo}/installations`. Platform-native apps like `github-actions` will not appear.
- **Prefer `integration_id` constraints over bypass actors** for bot workflows. Restricting which app can satisfy a check is more precise than bypassing the check entirely, and it works with platform-native identities.
- **When piping `gh api` output through external parsers**, separate stdout from stderr (`2>/dev/null` or `--silent`) to avoid parse failures from mixed streams.

## References

- GitHub Rulesets API: `PUT /repos/{owner}/{repo}/rulesets/{id}` — [docs](https://docs.github.com/en/rest/repos/rules#update-a-repository-ruleset)
- Related issue: #773 (CLA check integration_id security gap)
- Related issue: #772 (bot workflows with direct-push vulnerability)
- Related learning: `2026-03-19-content-publisher-cla-ruleset-push-rejection.md` — PR-based commit pattern that this work builds upon
- GitHub Actions app ID 15368: platform-native identity, not installable — this is an undocumented platform constraint

## Tags

category: integration-issues
module: github-rulesets
