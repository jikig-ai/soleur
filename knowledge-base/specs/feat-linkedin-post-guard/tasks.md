# Tasks: LinkedIn Post Guard

## Phase 1: Setup

- [x] 1.1 Verify `linkedin-community.sh` exists (may need to coordinate with feat-linkedin-api-scripts branch or merge its changes first)
- [x] 1.2 Read `cmd_post_content()` function to identify exact insertion point for the guard

## Phase 2: Core Implementation

- [x] 2.1 Add `LINKEDIN_ALLOW_POST` guard as the first statement in `cmd_post_content()` in `plugins/soleur/skills/community/scripts/linkedin-community.sh`
  - [x] 2.1.1 Check `"${LINKEDIN_ALLOW_POST:-}" != "true"` (strict string equality, not just set/unset)
  - [x] 2.1.2 Print informational error message to stderr naming the variable and required value
  - [x] 2.1.3 Return 1 (not 0) to signal failure to callers
- [x] 2.2 Verify `scheduled-community-monitor.yml` does NOT set `LINKEDIN_ALLOW_POST` (confirm by reading the file)
- [x] 2.3 Verify `scheduled-content-publisher.yml` does NOT set `LINKEDIN_ALLOW_POST` yet (deferred to #590 when `content-publisher.sh` gains LinkedIn channel support)

## Phase 3: Testing & Validation

- [x] 3.1 Run `shellcheck plugins/soleur/skills/community/scripts/linkedin-community.sh` -- zero new warnings (shellcheck not installed; bash -n syntax check passed)
- [x] 3.2 Source the script and verify guard blocks posting when `LINKEDIN_ALLOW_POST` is unset
- [x] 3.3 Source the script and verify guard blocks posting when `LINKEDIN_ALLOW_POST=false`
- [x] 3.4 Source the script and verify guard allows posting when `LINKEDIN_ALLOW_POST=true`
- [x] 3.5 Verify `scheduled-community-monitor.yml` has no `LINKEDIN_ALLOW_POST` in env block
