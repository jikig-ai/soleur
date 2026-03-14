---
title: "feat: Add programmatic no-post guard to linkedin-community.sh"
type: feat
date: 2026-03-15
deepened: 2026-03-15
---

# feat: Add Programmatic No-Post Guard to linkedin-community.sh

## Enhancement Summary

**Deepened on:** 2026-03-15
**Sections enhanced:** 3 (Proposed Solution, Acceptance Criteria, Dependencies & Risks)

### Key Improvements

1. Corrected content-publisher workflow scope -- `content-publisher.sh` has no LinkedIn channel support yet, so adding `LINKEDIN_ALLOW_POST` to its workflow YAML is premature. Deferred to the LinkedIn content-publisher integration issue (#590).
2. Added `BASH_SOURCE` guard verification -- the guard depends on `linkedin-community.sh` having the source guard pattern (task 2.10 in feat-linkedin-api-scripts), which is confirmed in the tasks.
3. Applied institutional learning: shell script defensive patterns (return code 1, guard-first placement) align with documented prevention strategies from `knowledge-base/learnings/2026-03-13-shell-script-defensive-patterns.md`.

## Overview

Add a `LINKEDIN_ALLOW_POST=true` environment variable guard to `cmd_post_content()` in `linkedin-community.sh`. When the variable is unset or not `true`, the function refuses to post and exits with an informational message. This provides defense-in-depth against unauthorized autonomous LinkedIn posts during monitoring runs.

## Problem Statement / Motivation

The scheduled community monitor workflow (`scheduled-community-monitor.yml`) instructs the agent via prompt not to post to LinkedIn during monitoring runs. But this is a soft guard -- if the agent disobeys or hallucinates a posting instruction, `cmd_post_content()` will succeed because there is no programmatic check.

Compare with X/Twitter where `fetch-mentions` returns HTTP 403 on Free tier -- the API itself enforces the restriction even if the agent ignores the prompt instruction. LinkedIn has no equivalent API-level restriction.

A single environment variable check at the top of `cmd_post_content()` makes autonomous posting structurally impossible unless the caller explicitly opts in. The monitoring workflow would NOT set this variable. The content-publisher workflow and manual invocations would set it explicitly.

## Proposed Solution

Add a guard at the top of `cmd_post_content()` in `plugins/soleur/skills/community/scripts/linkedin-community.sh`:

```bash
cmd_post_content() {
  # Defense-in-depth: refuse to post unless explicitly allowed.
  # The monitoring workflow does NOT set this variable, making
  # autonomous posting structurally impossible during monitor runs.
  if [[ "${LINKEDIN_ALLOW_POST:-}" != "true" ]]; then
    echo "Error: LINKEDIN_ALLOW_POST is not set to 'true'." >&2
    echo "Posting is disabled by default as a safety guard." >&2
    echo "Set LINKEDIN_ALLOW_POST=true to enable posting." >&2
    return 1
  fi

  # ... existing posting logic ...
}
```

Callers that should be allowed to post set `LINKEDIN_ALLOW_POST=true` in their environment:

1. Manual invocations via the terminal (user sets the env var)
2. `scheduled-content-publisher.yml` -- deferred until `content-publisher.sh` gains LinkedIn channel support (issue #590); the script currently handles only `discord` and `x` channels

The monitoring workflow (`scheduled-community-monitor.yml`) does NOT set the variable, so even if the agent calls `post-content`, the script refuses.

### Research Insight: content-publisher.sh has no LinkedIn support

The `channel_to_section()` function in `scripts/content-publisher.sh` only maps `discord` and `x`. Adding `LINKEDIN_ALLOW_POST=true` to the content-publisher workflow YAML before the script supports a `linkedin` channel would be dead code. The workflow env block change should ship with issue #590 (content-publisher LinkedIn support), not with this guard.

## Technical Considerations

### Return code

The guard returns 1 (not 0). Per constitution rule: "functions that create fallback issues on failure must return 1 (not 0) -- `return 0` after a fallback masks the failure from CI." The caller should see a non-zero exit to know posting was blocked.

### Implementation strategy

The `linkedin-community.sh` script is being implemented in the `feat-linkedin-api-scripts` branch (issue #589, task 2.6). This guard should be integrated directly into `cmd_post_content()` during that implementation -- amend task 2.6 in `knowledge-base/specs/feat-linkedin-api-scripts/tasks.md` to include the guard as a sub-task. This plan is a specification amendment to that plan, not a standalone deliverable requiring a separate PR.

## Non-goals

- Modifying any other community scripts (x, bsky, discord, github, hn)
- Adding post guards to non-LinkedIn platforms
- Changing the monitoring workflow prompt instructions (they remain as a first layer of defense)
- Adding authentication or credential-level restrictions (the guard is simpler and more reliable)

## Acceptance Criteria

- [ ] `cmd_post_content()` in `linkedin-community.sh` checks `LINKEDIN_ALLOW_POST` before any posting logic
- [ ] When `LINKEDIN_ALLOW_POST` is unset, `post-content` exits with code 1 and prints an informational message to stderr
- [ ] When `LINKEDIN_ALLOW_POST=false`, `post-content` exits with code 1
- [ ] When `LINKEDIN_ALLOW_POST=true`, `post-content` proceeds normally
- [ ] `scheduled-community-monitor.yml` does NOT set `LINKEDIN_ALLOW_POST`
- [ ] `scheduled-content-publisher.yml` does NOT set `LINKEDIN_ALLOW_POST` yet (deferred to #590 when `content-publisher.sh` gains LinkedIn channel support)
- [ ] Guard message references `LINKEDIN_ALLOW_POST=true` so operators know how to enable posting

## Test Scenarios

- Given `LINKEDIN_ALLOW_POST` is unset, when `linkedin-community.sh post-content --text "test"`, then exit code 1 with "LINKEDIN_ALLOW_POST is not set" message to stderr
- Given `LINKEDIN_ALLOW_POST=false`, when `linkedin-community.sh post-content --text "test"`, then exit code 1 with guard message
- Given `LINKEDIN_ALLOW_POST=true` and valid credentials, when `linkedin-community.sh post-content --text "test"`, then post is created normally
- Given `LINKEDIN_ALLOW_POST=true` but no credentials, when `linkedin-community.sh post-content --text "test"`, then credential error (guard passes, credential check catches it)
- Given monitoring workflow runs (no `LINKEDIN_ALLOW_POST` in env), when agent calls `post-content`, then post is blocked regardless of prompt instructions
- Given `LINKEDIN_ALLOW_POST=true` set manually, when script calls `post-content`, then post succeeds (content-publisher workflow integration deferred to #590)

## Applicable Institutional Learnings

- **Shell script defensive patterns** (`knowledge-base/learnings/2026-03-13-shell-script-defensive-patterns.md`): Prevention strategy #5 (always include an `else`/default case) applies -- the guard's `return 1` path is the catch-all for all non-`"true"` values.
- **Platform integration scope calibration** (`knowledge-base/learnings/2026-03-13-platform-integration-scope-calibration.md`): "Match scope to what can be validated on day one." The content-publisher workflow env change cannot be validated until #590 ships, so it is deferred.
- **Community router deduplication** (`knowledge-base/learnings/2026-03-13-community-router-deduplication.md`): The guard lives in `linkedin-community.sh` (the platform script), not in the router or caller. This follows the pattern where platform-specific behavior belongs in platform scripts.

## Dependencies & Risks

| Risk | Impact | Mitigation |
|------|--------|-----------|
| `linkedin-community.sh` not yet merged | Cannot add guard to a file that does not exist | Integrate guard into `cmd_post_content()` during feat-linkedin-api-scripts implementation (amend task 2.6) |
| Operator forgets to set env var in new workflows | Posting silently blocked | Error message explicitly names the variable and required value |
| Guard bypassed by sourcing and calling internal functions | Direct API calls bypass guard | Acceptable risk -- sourcing is a deliberate developer action, not an agent behavior |
| Content-publisher LinkedIn support not yet implemented | `LINKEDIN_ALLOW_POST` env in workflow YAML would be dead code | Defer workflow YAML change to #590 |

## Semver Intent

`semver:patch` -- this is a defensive hardening of an existing feature, not a new capability.

## References

- Security review: PR #620
- Follow-up from: #592
- Parent feature: #589 (LinkedIn API scripts)
- Pattern reference: X/Twitter 403 on Free tier (natural API-level guard)
- File: `plugins/soleur/skills/community/scripts/linkedin-community.sh` (task 2.6 in feat-linkedin-api-scripts)
- Workflow: `.github/workflows/scheduled-community-monitor.yml`
- Workflow: `.github/workflows/scheduled-content-publisher.yml`
- Constitution: "functions that create fallback issues on failure must return 1 (not 0)"
