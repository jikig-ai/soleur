---
title: "fix: add gh CLI to production Docker image for cron-follow-through-monitor"
type: fix
date: 2026-05-27
lane: single-domain
---

# fix: add gh CLI to production Docker image for cron-follow-through-monitor

## Overview

The `cron-follow-through-monitor` Inngest function (and `event-ship-merge`) directly invokes the `gh` CLI binary via `spawn("gh", ...)` and `execFileSync("gh", ...)`, but `gh` is not installed in the production Docker image (`apps/web-platform/Dockerfile`). Every invocation raises `spawnSync gh ENOENT` at runtime, making both the label-creation step and the predicate-validation step of `cron-follow-through-monitor` non-functional in production.

**Sentry ID:** `4a02599747374741a90c6aa06307c049`

## Problem Statement / Motivation

The `cron-follow-through-monitor` function was migrated from a GitHub Actions workflow (`scheduled-follow-through.yml`) to an Inngest cron function in TR9 PR-2 (#4063). In GHA, `gh` is pre-installed in the runner environment. In the Docker production image, only `git`, `bubblewrap`, `socat`, `qpdf`, and Playwright Chromium are installed. The migration preserved the `gh` call sites verbatim but did not add `gh` to the Dockerfile.

Three call sites are affected:
1. `spawn("gh", ["label", "create", ...])` at `cron-follow-through-monitor.ts:317` -- label creation
2. `execFileSync("gh", ["issue", "list", ...])` at `cron-follow-through-monitor.ts:409` -- issue listing for predicate validation
3. `spawnSimple("gh", ["pr", "checkout", ...])` at `event-ship-merge.ts:163` -- PR checkout

## Proposed Solution

Install `gh` (GitHub CLI) in the Dockerfile's runner stage via the official GitHub apt repository. This is the standard Debian/Ubuntu installation method and is the same approach used in GitHub-hosted Actions runners.

The `gh` binary is needed at runtime (not build time), so it belongs in the runner stage's `apt-get install` block alongside `git`, `bubblewrap`, `socat`, `qpdf`.

## Technical Considerations

- **Image size:** `gh` adds ~50 MB to the image. This is acceptable given the image already includes Playwright Chromium (~300 MB) and the Claude Code CLI.
- **apt repository setup:** `gh` is not in the default Debian repos for `node:22-slim` (Debian Bookworm). Installation requires adding the GitHub CLI apt repository first.
- **Security:** The `gh` binary is used only with `GH_TOKEN` from `buildSpawnEnv()` -- the same allowlist-based env that controls claude spawns. No new secret surfaces are introduced.
- **Parallel work:** PR #4531 (`feat-one-shot-fix-sentry-cron-community-monitor`) is an open WIP for a different cron function issue. It has not touched the Dockerfile. This fix is independent.

## User-Brand Impact

- **If this lands broken, the user experiences:** follow-through issues are never auto-triaged by the cron monitor; labels are not created; the agent never receives predicate results. The cron function silently fails (caught by Sentry) but operator GitHub issues accumulate without automated follow-through.
- **If this leaks, the user's data/workflow/money is exposed via:** N/A -- `gh` is a read/write tool for the operator's own GitHub repo, authenticated via existing `GH_TOKEN`. No new data surface.
- **Brand-survival threshold:** `none`

*Scope-out override:* `threshold: none, reason: gh CLI is an operator-internal automation tool; the ENOENT only affects the operator's own cron automation, not end-user data or sessions.`

## Observability

```yaml
liveness_signal:
  what: Sentry cron monitor "scheduled-follow-through"
  cadence: per-run (cron schedule in cron-follow-through-monitor.ts)
  alert_target: Sentry issue alert -> operator email
  configured_in: apps/web-platform/infra/sentry/cron-monitors.tf

error_reporting:
  destination: Sentry web-platform via SENTRY_DSN
  fail_loud: Sentry event with "spawnSync gh ENOENT" message (currently firing -- this fix eliminates it)

failure_modes:
  - mode: gh binary missing from PATH
    detection: Sentry ENOENT error on spawn("gh", ...)
    alert_route: Sentry issue -> operator email
  - mode: gh apt repository unreachable at build time
    detection: Docker build fails at apt-get install step
    alert_route: CI build failure notification

logs:
  where: docker logs (stdout/stderr from Inngest handler)
  retention: per container lifecycle + Sentry event retention

discoverability_test:
  command: "curl -s https://<host>/health | jq '.version'"
  expected_output: build version string confirming image includes gh fix
```

## Files to Edit

| File | Change |
|------|--------|
| `apps/web-platform/Dockerfile` | Add GitHub CLI apt repository setup + `gh` to the `apt-get install` block in the runner stage |

## Files to Create

None.

## Open Code-Review Overlap

None.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1: `apps/web-platform/Dockerfile` runner stage installs `gh` from the official GitHub CLI apt repository
- [ ] AC2: The `apt-get install` block adds the GitHub apt keyring and source list before installing `gh`
- [ ] AC3: `docker build` succeeds locally with the updated Dockerfile (verified: `docker build -f apps/web-platform/Dockerfile apps/web-platform/ --target runner`)
- [ ] AC4: `docker run <image> gh --version` returns a valid version string
- [ ] AC5: No other files are modified beyond the Dockerfile
- [ ] AC6: PR body contains `Ref #<sentry-issue-number>` (not `Closes` -- the Sentry issue is external)
- [ ] AC7: PR has `semver:patch` label and `bug` label

### Post-merge (operator)

- [ ] AC8: After deploy, Sentry `spawnSync gh ENOENT` events stop recurring for `cron-follow-through-monitor`
- [ ] AC9: `cron-follow-through-monitor` next cron run completes the `ensure-labels` and `validate-predicates` steps without ENOENT

## Test Scenarios

- Given the updated Docker image, when `cron-follow-through-monitor` runs the `ensure-labels` step, then `spawn("gh", ["label", "create", ...])` does not raise ENOENT
- Given the updated Docker image, when `cron-follow-through-monitor` runs the `validate-predicates` step, then `execFileSync("gh", ["issue", "list", ...])` does not raise ENOENT
- Given the updated Docker image, when `event-ship-merge` runs the `checkout-pr` step, then `spawnSimple("gh", ["pr", "checkout", ...])` does not raise ENOENT

## Implementation Phases

### Phase 1: Add gh CLI to Dockerfile

Add the GitHub CLI apt repository and install `gh` in the runner stage. The canonical installation for Debian follows this pattern:

1. Install `curl` as a transient dependency (needed to fetch the keyring; can be removed after if desired, but keeping it is simpler and it is ~1 MB)
2. Add the GitHub CLI GPG keyring: `curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg -o /usr/share/keyrings/githubcli-archive-keyring.gpg`
3. Add the apt source: `echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" > /etc/apt/sources.list.d/github-cli.list`
4. `apt-get update && apt-get install -y gh`
5. Clean up: `rm -rf /var/lib/apt/lists/*`

This should be a single `RUN` block placed immediately before or combined with the existing `apt-get install` block at Dockerfile line 57.

## Alternative Approaches Considered

| Approach | Rejected Because |
|----------|-----------------|
| Replace `gh` calls with GitHub REST API via `fetch()` | High-effort rewrite of 3 call sites; `gh` is the established pattern in all cron functions; would diverge from the GHA-era code that was deliberately preserved during migration |
| Install `gh` via npm package | No official npm package for `gh` CLI; unofficial wrappers are unmaintained |
| Install `gh` via direct binary download | Less maintainable than apt; no automatic security updates; breaks the existing apt-based package management pattern in the Dockerfile |

## Dependencies & Risks

- **Risk 1:** GitHub CLI apt repository availability at Docker build time. Mitigation: the repository is GitHub's official distribution channel and is highly available. If it were temporarily down, the Docker build would fail loudly (not silently).
- **Risk 2:** Image size increase. Mitigation: ~50 MB is marginal relative to the existing ~500 MB+ image with Playwright and Claude Code CLI.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- infrastructure/tooling change.

## References & Research

### Internal References

- `apps/web-platform/server/inngest/functions/cron-follow-through-monitor.ts:317,409` -- `gh` call sites
- `apps/web-platform/server/inngest/functions/event-ship-merge.ts:163` -- additional `gh` call site
- `apps/web-platform/Dockerfile:57-59` -- existing apt-get install block
- TR9 PR-2 (#4063) -- migration that introduced the Inngest function

### External References

- [GitHub CLI installation docs](https://github.com/cli/cli/blob/trunk/docs/install_linux.md) -- canonical Debian/Ubuntu apt installation

### Related Work

- PR #4531 (`feat-one-shot-fix-sentry-cron-community-monitor`) -- parallel WIP for different cron function issue; has not touched Dockerfile
- Sentry ID `4a02599747374741a90c6aa06307c049` -- the error this fix addresses

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. Fill it before requesting deepen-plan or `/work`.
- The `gh` apt repository requires adding a GPG keyring and source list BEFORE running `apt-get install gh`. A bare `apt-get install gh` will fail because `gh` is not in the default Debian repos.
- The `event-ship-merge.ts` function is also affected by this same ENOENT. The Dockerfile fix covers all three call sites across both functions.
