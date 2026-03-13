---
title: refactor(community): platform adapter interface
type: refactor
date: 2026-03-13
---

# refactor(community): platform adapter interface

## Overview

Introduce a thin shell router (`community-router.sh`) and shared library (`community-common.sh`) that standardize how 5 community platform scripts are discovered, authenticated, and dispatched. This eliminates triple-duplication of platform detection logic across SKILL.md, community-manager agent, and scheduled workflow.

## Problem Statement / Motivation

Adding HN as platform #5 required updating 3 separate files with overlapping platform detection logic. Each new platform multiplies this maintenance cost. The 5 existing scripts (Discord, GitHub, X, Bluesky, HN) share significant duplicated code (`require_jq`, retry logic, curl response parsing) but use inconsistent command names (`messages` vs `fetch-mentions` vs `get-notifications` vs `mentions`).

The YAGNI trigger from #470 has been met (>3 platforms). The "thin router over migration" learning applies — add a facade, don't reorganize internals.

## Proposed Solution

### Architecture

```
community-router.sh (entry point — new)
  ├── discovers *-community.sh via glob
  ├── queries cmd_capabilities per script
  ├── checks cmd_check-auth per script
  └── dispatches standardized commands

community-common.sh (shared library — new)
  ├── require_jq(), require_curl()
  ├── parse_curl_response()     # curl + tail + sed pattern
  ├── validate_json()            # jq validation
  └── retry_guard()              # depth >= 3 check + sleep

discord-community.sh   (capabilities: fetch-mentions, fetch-metrics)
github-community.sh    (capabilities: fetch-mentions, fetch-metrics, fetch-timeline)
x-community.sh         (capabilities: fetch-mentions, fetch-metrics, post-reply, fetch-timeline)
bsky-community.sh      (capabilities: fetch-mentions, fetch-metrics, post-reply)
hn-community.sh        (capabilities: fetch-mentions, fetch-metrics, fetch-timeline)
```

### Key Design Decisions (from SpecFlow analysis)

**D1: `cmd_capabilities` contract** — Space-separated string on stdout. Example: `echo "fetch-mentions fetch-metrics fetch-timeline"`. Called via subprocess (`script capabilities`), not sourcing.

**D2: `cmd_check-auth` contract** — Exit 0 (auth OK) or exit 1 (not configured). Env-var presence only, no API calls. GitHub: `command -v gh &>/dev/null && gh auth status &>/dev/null`. HN: always exits 0 (public API). Stdout suppressed; only exit code matters.

**D3: Platform naming** — Derived from filename by stripping `-community.sh`. Canonical names: `discord`, `github`, `x`, `bsky`, `hn`. Router accepts lowercase only.

**D4: Command mapping table**

| Standard Command | Discord | GitHub | X | Bluesky | HN |
|-----------------|---------|--------|---|---------|-----|
| `fetch-mentions` | `messages` | `activity` | `fetch-mentions` | `get-notifications` | `mentions` |
| `fetch-metrics` | `guild-info` | `contributors` | `fetch-metrics` | `get-metrics` | `trending` |
| `post-reply` | — | — | `post-tweet` | `post` | — |
| `fetch-timeline` | — | `activity` | `fetch-timeline` | — | `mentions` |

Each script implements `cmd_fetch_mentions`, `cmd_fetch_metrics`, etc. as wrappers that call the existing internal functions. Old command names stay as aliases in the case dispatch for backward compat.

**D5: Router output format** — JSON envelope for multi-platform fan-out:
```json
{
  "results": {"discord": {...}, "github": {...}},
  "errors": {"bsky": "401 Unauthorized"},
  "skipped": ["hn"]
}
```
Exit 0: all succeeded. Exit 1: all failed. Exit 2: partial (some succeeded, some failed).

**D6: Stderr forwarding** — `--platform` dispatch: transparent stderr (preserves X API contract string `"This endpoint requires paid API access."`). Fan-out: prefix with `[platform]` on stderr, but never modify stdout.

**D7: Shared library scope** — Only extract truly duplicated functions: `require_jq()`, `parse_curl_response()` (curl + tail + sed), `validate_json()`, `retry_guard()` (depth check). Do NOT extract `handle_response()` — it has platform-specific logic (X's 403 paid-tier detection, Bluesky's session handling). Scripts source `community-common.sh` but define their own response handlers.

**D8: Source guards** — All scripts get `if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then main "$@"; fi` to enable sourcing for testing. Currently only x-community.sh and hn-community.sh have this.

**D9: HN in scope** — Merge `origin/main` to bring `hn-community.sh` into the worktree. Add adapter functions (`cmd_capabilities`, `cmd_check_auth`, standardized command wrappers).

## Technical Considerations

- **GitHub outlier**: Uses `gh api` not curl, has no `require_jq`. It sources `community-common.sh` but only uses `retry_guard()`. The shared library must not assume curl.
- **X API cross-file contract**: `x-community.sh:201` — stderr string `"This endpoint requires paid API access."` matched by community-manager agent for 403 fallback. Must be preserved exactly.
- **5-layer hardening**: All scripts must implement: input validation, curl stderr suppression (`2>/dev/null`), JSON validation, jq fallback chains (`// []`), float-safe retry_after clamping (`printf '%.0f'`). Per learning `2026-03-09-shell-api-wrapper-hardening-patterns.md`.
- **Exit code convention**: 0 success, 1 failure, 2 partial failure / rate limit exhausted.

## Acceptance Criteria

- [ ] `community-router.sh platforms` lists 5 platforms with correct capabilities and auth status
- [ ] `community-router.sh fetch-metrics` collects metrics from all enabled platforms, returns JSON envelope
- [ ] `community-router.sh fetch-mentions --platform x` returns X mentions only with transparent stderr
- [ ] `community-router.sh post-reply --platform bsky "test"` posts to Bluesky
- [ ] `community-router.sh post-reply "test"` (no `--platform`) exits 1 with helpful error listing supported platforms
- [ ] A mock `test-community.sh` with `cmd_capabilities` is auto-discovered by the router
- [ ] SKILL.md platform detection replaced by `community-router.sh platforms`
- [ ] Community-manager agent dispatches via router commands, not hardcoded script paths
- [ ] Scheduled workflow calls router instead of inline platform logic
- [ ] Old command names still work when calling scripts directly (backward compat aliases)
- [ ] All 5 scripts source `community-common.sh` and use shared helpers
- [ ] All 5 scripts have `BASH_SOURCE[0]` guard for testability
- [ ] Exit code 2 returned when some platforms succeed and others fail

## Test Scenarios

- Given no credentials configured, when `community-router.sh platforms`, then all platforms show "disabled" except GitHub and HN (always-on)
- Given X credentials set but free tier, when `community-router.sh fetch-mentions --platform x`, then stderr shows `"This endpoint requires paid API access."` exactly (contract preserved)
- Given 3 of 5 platforms enabled, when `community-router.sh fetch-metrics`, then results contains 3 entries, skipped contains 2, exit code 0
- Given Bluesky returns 401, when `community-router.sh fetch-metrics`, then errors contains `{"bsky": "..."}`, exit code 2
- Given a script without `cmd_capabilities`, when `community-router.sh platforms`, then it is skipped with stderr warning
- Given `community-router.sh post-reply` without `--platform`, then exit 1 with error listing platforms that support post-reply

## Implementation Phases

### Phase 1: Foundation (community-common.sh + source guards)

1. Merge `origin/main` to bring `hn-community.sh` into worktree
2. Create `plugins/soleur/skills/community/scripts/community-common.sh`:
   - `require_jq()` — extracted from discord/x/bsky/hn (identical in all 4)
   - `require_curl()` — new, same pattern as require_jq
   - `parse_curl_response()` — wraps `curl -s -w "\n%{http_code}" | tail/sed` pattern
   - `validate_json()` — normalized `jq . >/dev/null 2>&1` check
   - `retry_guard()` — `depth >= 3` check, returns 1 if exceeded
3. Add `BASH_SOURCE[0]` guard to discord-community.sh, github-community.sh, bsky-community.sh
4. Update all 5 scripts to `source community-common.sh` and replace inline duplicates
5. Verify all existing commands still work after extraction

### Phase 2: Adapter Functions (cmd_capabilities + cmd_check-auth + standard commands)

For each of the 5 scripts:

1. Add `cmd_capabilities` echoing space-separated supported ops
2. Add `cmd_check_auth` with env-var presence check (exit 0/1)
3. Add standardized command wrappers (`cmd_fetch_mentions`, `cmd_fetch_metrics`, etc.) that delegate to existing internal functions
4. Add `capabilities` and `check-auth` to the case dispatch
5. Keep old command names as aliases in case dispatch

### Phase 3: Router (community-router.sh)

Create `plugins/soleur/skills/community/scripts/community-router.sh`:

1. `discover_platforms()` — glob `*-community.sh`, exclude `community-common.sh`, extract platform name
2. `check_platform_auth()` — call `script check-auth`, return exit code
3. `get_platform_capabilities()` — call `script capabilities`, parse space-separated output
4. `dispatch_single()` — run command on one platform, forward stdout/stderr transparently
5. `dispatch_all()` — run command on all enabled platforms, aggregate into JSON envelope, handle partial failure
6. `cmd_platforms()` — list platforms with capabilities and auth status
7. `main()` — parse `--platform` flag, route to dispatch_single or dispatch_all
8. Validate `post-reply` requires `--platform`

### Phase 4: Integration (update callers)

1. Update `SKILL.md` — replace inline platform detection table and per-platform bash blocks with `community-router.sh` commands
2. Update `community-manager.md` — replace hardcoded script paths and per-platform data collection with router dispatch
3. Update `scheduled-community-monitor.yml` — replace inline platform logic with router commands
4. Verify all 4 community skill sub-commands work end-to-end: `digest`, `health`, `platforms`, `engage`

## Dependencies & Risks

- **Risk: GitHub script is too different** — Mitigation: GitHub only sources `community-common.sh` for `retry_guard()`, skips curl-specific helpers. Its adapter functions delegate to `gh api` calls directly.
- **Risk: Overscoping** — Learning `2026-03-09-external-api-scope-calibration` warns this exact refactor was 3x overscoped before. Mitigation: 4 focused phases, no new platform capabilities, no output schema normalization beyond the router envelope.
- **Risk: X API contract breakage** — Mitigation: `--platform` dispatch uses transparent stderr forwarding. Test scenario explicitly validates the contract string.
- **Dependency**: `hn-community.sh` must be merged from main before Phase 2.

## References & Research

### Internal References

- Brainstorm: `knowledge-base/brainstorms/2026-03-13-community-platform-adapters-brainstorm.md`
- Spec: `knowledge-base/specs/feat-community-platform-adapters/spec.md`
- Learning — scope calibration: `knowledge-base/learnings/2026-03-09-external-api-scope-calibration.md`
- Learning — thin router: `knowledge-base/learnings/2026-02-22-simplify-workflow-thin-router-over-migration.md`
- Learning — shell hardening: `knowledge-base/learnings/2026-03-09-shell-api-wrapper-hardening-patterns.md`
- Learning — retry depth: `knowledge-base/learnings/2026-03-09-depth-limited-api-retry-pattern.md`
- Learning — X API billing: `knowledge-base/learnings/2026-03-10-x-api-pay-per-use-billing-and-web-fallback.md`
- Learning — table-driven routing: `knowledge-base/learnings/2026-02-22-domain-prerequisites-refactor-table-driven-routing.md`
- X API contract: `plugins/soleur/skills/community/scripts/x-community.sh:201`

### Related Work

- Parent issue: #127
- This issue: #470
- HN monitoring: #597 (commit 28517cf)
- Draft PR: #605
