# Learning: Environment Variable Post Guard as Defense-in-Depth

## Problem

The scheduled community monitor workflow tells the agent via prompt instructions not to post to LinkedIn. But prompt instructions are a soft guard -- if the agent disobeys (hallucination, misparse, prompt injection), `cmd_post_content()` in `linkedin-community.sh` would execute successfully and publish content autonomously. There was no programmatic barrier between the agent deciding to post and the post actually happening.

This mirrors a gap already present in the X/Twitter integration, where the only defense-in-depth is the API tier itself (Free tier returns HTTP 403 on posting endpoints). That API-level block is accidental, not designed -- it would vanish if the account were upgraded.

## Solution

Added a `LINKEDIN_ALLOW_POST` environment variable guard at the top of `cmd_post_content()` in `plugins/soleur/skills/community/scripts/linkedin-community.sh`. The guard checks `"${LINKEDIN_ALLOW_POST:-}" != "true"` and returns 1 with an error message if the variable is not set to exactly `"true"`.

Design decisions:

1. **Strict string equality (`!= "true"`)** over a set/unset check -- prevents accidental enabling via empty string, `"1"`, `"TRUE"`, or any other truthy-looking value. Only the exact string `true` passes.
2. **`return 1` instead of `exit 1`** -- the script uses a `BASH_SOURCE` guard at line 327 to allow sourcing for testing. `exit 1` would kill the sourcing shell; `return 1` safely aborts just the function.
3. **Guard in the script, not the workflow** -- the monitoring workflow does NOT set `LINKEDIN_ALLOW_POST`, making autonomous posting structurally impossible regardless of what the agent prompt says. A future publishing workflow that intentionally posts would set the variable explicitly.
4. **6 lines, not 10** -- initial implementation had a redundant comment and an extra echo line. Code-simplicity review compressed it without losing clarity.

Collateral changes:
- Added `LINKEDIN_ALLOW_POST` to the script header's environment variable documentation block.
- Added `TODO(#590)` breadcrumb in `scheduled-content-publisher.yml` for the future env change (deferred because `channel_to_section()` only maps discord and x -- LinkedIn is dead code there).
- Filed #629 for X/Bluesky post guard parity (pre-existing gap discovered during this work).

## Key Insight

Agent prompt instructions are necessary but not sufficient for safety-critical operations. They are a "please don't" guard -- they work when the agent cooperates and fail silently when it doesn't. For destructive or irreversible actions (publishing content, sending messages, deleting data), add a programmatic guard that makes the unsafe action structurally impossible without explicit opt-in.

The pattern is:

```bash
if [[ "${ACTION_ALLOW_VAR:-}" != "true" ]]; then
  echo "ERROR: $ACTION_ALLOW_VAR must be 'true' to proceed" >&2
  return 1
fi
```

This creates a two-key system: the agent must both decide to act AND the environment must be configured to permit the action. Neither alone is sufficient. The monitoring workflow omits the key; the publishing workflow provides it. The separation is structural, not behavioral.

This is the same defense-in-depth principle as the `BASH_SOURCE` guard (prevents accidental direct execution), the PreToolUse hooks (prevent commits to main), and the guardrails.sh guards (prevent destructive git operations). The common thread: never rely on a single layer of protection for irreversible actions.

## Session Errors

1. **`setup-ralph-loop.sh` path wrong in one-shot skill** -- tried `./plugins/soleur/skills/one-shot/scripts/setup-ralph-loop.sh` but the script lives at `./plugins/soleur/scripts/setup-ralph-loop.sh`. Same class of error documented in `2026-03-14-bare-repo-helper-extraction-patterns.md` (plan-prescribed paths implemented verbatim without tracing).
2. **`shellcheck` not installed** -- fell back to `bash -n` for syntax validation. `bash -n` catches syntax errors but misses the class of issues shellcheck detects (unquoted variables, unused variables, POSIX compatibility). Not a blocker for this change but a tooling gap.

## Related

- `2026-03-13-shell-script-defensive-patterns.md` -- authoring-time defensive patterns for shell scripts (complementary: that learning covers code quality; this one covers access control)
- `2026-03-10-x-api-pay-per-use-billing-and-web-fallback.md` -- X API 402/403 as accidental defense-in-depth (this learning formalizes the pattern as intentional)
- `2026-03-13-platform-integration-scope-calibration.md` -- LinkedIn scope decisions that deferred API posting (this learning implements the guard for the deferred scope)
- `2026-02-24-guardrails-chained-commit-bypass.md` -- guardrails.sh as defense-in-depth for git operations (same principle, different domain)
- GitHub issue #629 -- X/Bluesky post guard parity (filed during this session)

## Tags
category: prevention
module: plugins/soleur/skills/community
