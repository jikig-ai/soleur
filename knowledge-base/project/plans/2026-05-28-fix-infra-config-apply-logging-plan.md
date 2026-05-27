---
title: "fix(infra): add structured logging + error surfacing to infra-config-apply.sh"
type: fix
date: 2026-05-28
lane: single-domain
issue: 4554
requires_cpo_signoff: false
---

# fix(infra): add structured logging + error surfacing to infra-config-apply.sh

## Overview

`infra-config-apply.sh` is the webhook handler that writes infrastructure config files (ci-deploy.sh, webhook.service, hooks.json, etc.) to the production host when `terraform apply` runs. It currently has zero structured logging: no `logger -t` tags, no per-file write confirmations, no persistent status, and a self-restart race condition that can kill the script mid-write. Discovered during #4538 AC11 validation when `ci-deploy.sh` on the server was never updated despite 3 successful HTTP 202 responses.

## Problem Statement / Motivation

The async webhook pattern (HTTP 202 returned before script runs) means `push-infra-config.sh` always reports success. When `infra-config-apply.sh` fails:

1. **No `logger -t` tags** -- errors go to stderr/journald without a filterable tag, blending into general webhook logs
2. **No per-file write confirmation** -- impossible to tell which files were written vs. failed
3. **No persistent status** -- unlike `ci-deploy.sh` which writes `/var/lock/ci-deploy.state` queryable via `/hooks/deploy-status`, `infra-config-apply.sh` leaves no trace
4. **Self-restart race** -- the `systemd-run --on-active=3s` call at line 80 already runs after the write loop (line 73), but the 3s timer starts immediately. With the new state file write added between the loop and the restart, the timer must account for both writes AND state persistence. Without reordering, the restart could fire before the state file is written, making the new status endpoint useless on the very apply that triggered it

The sibling script `ci-deploy.sh` (same directory) already follows all these patterns: `LOG_TAG="ci-deploy"`, `logger -t "$LOG_TAG"` on every operation, `write_state()` for persistent status, and a state file consumed by `cat-deploy-state.sh` via `/hooks/deploy-status`. This fix brings `infra-config-apply.sh` to the same observability standard.

## Proposed Solution

1. Add `logger -t infra-config-apply` for all operations (env var validation, file decode, write, chmod, mv, post-write)
2. Compute SHA256 of each written file and log it (filename + SHA + success/fail)
3. Write a persistent status file (`/var/lock/infra-config-apply.state`) with per-file results, queryable via a new `/hooks/infra-config-status` endpoint in `hooks.json.tmpl`
4. Replace the fixed 3s delay self-restart with a completion-gated approach: all file writes complete first, status file is written, THEN the delayed restart is scheduled

## Research Insights

**Codebase precedent -- `ci-deploy.sh` logging pattern:**
- `readonly LOG_TAG="ci-deploy"` at `ci-deploy.sh:27`
- `logger -t "$LOG_TAG" "<message>"` for every operation
- `write_state()` function at `ci-deploy.sh:62-85` writes atomic JSON to `/var/lock/ci-deploy.state`
- `final_write_state()` at `ci-deploy.sh:96-99` with sentinel file to prevent EXIT trap overwrite
- `cat-deploy-state.sh` reads and merges state for the `/hooks/deploy-status` endpoint

**Webhook handler pattern -- `hooks.json.tmpl`:**
- Existing status endpoint: `deploy-status` at line 59 with `include-command-output-in-response: true` (GET, returns JSON)
- Existing config endpoint: `infra-config` at line 31 with `include-command-output-in-response: false` (POST, returns 202)
- Both use the same HMAC secret for authentication

**SystemD constraints -- `webhook.service`:**
- `ReadWritePaths` includes `/var/lock` -- state file writable
- `ReadWritePaths` includes `/usr/local/bin`, `/etc/systemd/system`, `/etc/webhook`, `/etc/sudoers.d` -- all write destinations accessible
- No additional `ReadWritePaths` changes needed

**Self-restart mechanism:**
- Current: `sudo /usr/bin/systemd-run --on-active=3s --unit=webhook-self-restart /usr/bin/systemctl restart webhook` at `infra-config-apply.sh:80`
- The 3s delay was chosen as "> typical TCP FIN handshake (~200ms)" per the script header comment
- Current ordering: write loop (lines 47-73) completes, then daemon-reload (line 77), then `systemd-run` (line 80). The write loop itself is NOT raced -- the restart schedules AFTER the loop. The race is between the 3s timer and the NEW work this PR adds: state file write + `sync`. Without reordering, `systemd-run` would fire immediately after the loop but before the state file is persisted
- Fix: insert state file write + `sync` between the write loop and the `systemd-run` call. The 3s delay is retained for HTTP response flush

**Workflow integration -- `apply-deploy-pipeline-fix.yml`:**
- Line 164: "Verify webhook is alive post-apply" step already polls `/hooks/deploy-status`
- The new `/hooks/infra-config-status` endpoint can be polled with the same pattern
- This replaces the current blind "HTTP 202 = success" assumption in `push-infra-config.sh`

**Cloud-init sync requirement:**
- `cloud-init.yml:206` writes `infra-config-apply.sh` to `/usr/local/bin/infra-config-apply.sh` on fresh servers
- Changes to `infra-config-apply.sh` must also update the cloud-init reference (already handled by the existing `base64encode(file(...))` pattern in `server.tf:39`)

## User-Brand Impact

- **If this lands broken, the user experiences:** stale infrastructure config on the production server (ci-deploy.sh not updated, webhook hooks not refreshed), causing deploy failures or stale deploy behavior
- **If this leaks, the user's workflow is exposed via:** no data exposure vector -- this is internal infrastructure tooling with no user-facing data
- **Brand-survival threshold:** `none`

Threshold rationale: `infra-config-apply.sh` handles internal infrastructure config files (scripts, systemd units, webhook hooks). No user PII, no auth tokens, no user-facing surfaces. The failure mode is "stale deploy scripts" which is operationally impactful but not a data/privacy incident.

## Observability

```yaml
liveness_signal:
  what: "/hooks/infra-config-status endpoint returns JSON with per-file write results"
  cadence: "on-demand (queried after each terraform apply)"
  alert_target: "CI workflow step failure in apply-deploy-pipeline-fix.yml"
  configured_in: "apps/web-platform/infra/hooks.json.tmpl (new infra-config-status hook)"

error_reporting:
  destination: "journald via logger -t infra-config-apply, shipped to Better Stack via Vector"
  fail_loud: "logger -t infra-config-apply 'FAILED: ...' + non-zero status in /var/lock/infra-config-apply.state"

failure_modes:
  - mode: "base64 decode failure for one or more files"
    detection: "per-file status in /var/lock/infra-config-apply.state shows failed=true"
    alert_route: "CI poll of /hooks/infra-config-status returns non-zero exit_code"
  - mode: "mv (atomic write) failure due to disk full or permission error"
    detection: "logger -t infra-config-apply 'FAILED: mv ...' + state file"
    alert_route: "CI poll of /hooks/infra-config-status"
  - mode: "self-restart kills webhook before status file is written"
    detection: "status file missing or stale (timestamp check)"
    alert_route: "CI poll returns no_prior_apply or stale timestamp"

logs:
  where: "journalctl -t infra-config-apply on the host; Better Stack via Vector journald source"
  retention: "journald: per systemd journal config; Better Stack: 30 days"

discoverability_test:
  command: |
    HMAC=$(printf '' | openssl dgst -sha256 -hmac "$WEBHOOK_SECRET" | sed 's/.*= //')
    curl -s -H "X-Signature-256: sha256=${HMAC}" \
      -H "CF-Access-Client-Id: ${CF_ACCESS_ID}" \
      -H "CF-Access-Client-Secret: ${CF_ACCESS_SECRET}" \
      "https://deploy.${APP_DOMAIN_BASE}/hooks/infra-config-status" | jq .
  expected_output: '{"exit_code":0,"files_written":7,"files_failed":0,"files":[...]}'
```

## Technical Approach

### Implementation Phases

[Plan review applied: consolidated 6 phases into 3. Deferred push-infra-config.sh polling to follow-up. Corrected self-restart race analysis.]

#### Phase 1: Add structured logging + state file + restart reordering to infra-config-apply.sh

All changes to `infra-config-apply.sh` in one pass: logging, state file, SHA verification, and restart reordering.

**Files to edit:**
- `apps/web-platform/infra/infra-config-apply.sh`

**Logging changes:**
1. Add `readonly LOG_TAG="infra-config-apply"` after `set -euo pipefail`
2. Add `logger -t "$LOG_TAG" "starting: N files to write"` after env var validation
3. Per env-var validation failure: `logger -t "$LOG_TAG" "FATAL: required env var $env_var is missing or empty"`
4. Per file write: `logger -t "$LOG_TAG" "writing: $dest_path"` before decode, `logger -t "$LOG_TAG" "wrote: $dest_path sha256=$sha"` after mv
5. Per file failure: `logger -t "$LOG_TAG" "FAILED: $dest_path reason=<decode|chmod|mv>"`
6. Visudo skip: `logger -t "$LOG_TAG" "SKIPPED: $dest_path reason=visudo_validation_failed"`
7. Completion: `logger -t "$LOG_TAG" "complete: $written_count/$total_count files written"`

**State file changes:**
1. Add `STATE_FILE="${INFRA_CONFIG_STATE:-/var/lock/infra-config-apply.state}"` (test-overridable)
2. Add `START_TS=$(date +%s)` at script start
3. Track per-file results in a shell array, building JSON at the end (no jq dependency -- use printf, matching the `ci-deploy.sh` `write_state()` approach)
4. After each mv, compute SHA256 of the written file: `sha256sum "$dest" | awk '{print $1}'`
5. Write atomic state file via mktemp+mv after the write loop completes:

```json
{
  "start_ts": 1716912000,
  "end_ts": 1716912001,
  "exit_code": 0,
  "files_written": 7,
  "files_failed": 0,
  "files": [
    {"file": "/usr/local/bin/ci-deploy.sh", "sha256": "abc123...", "status": "ok"},
    {"file": "/etc/sudoers.d/deploy-inngest-bootstrap", "sha256": "def456...", "status": "skipped", "reason": "visudo_validation_failed"}
  ]
}
```

6. Add EXIT trap with sentinel pattern (same as `ci-deploy.sh:96-99`): if the script crashes before writing the final state, the trap writes `{"exit_code":1,"reason":"unhandled"}`

**Restart reordering:**
1. Insert state file write + `sync` BETWEEN the write loop and the `systemd-run` call
2. Add `logger -t "$LOG_TAG" "scheduling self-restart in 3s"` before the restart
3. The final ordering is: write loop -> state file write -> sync -> daemon-reload -> systemd-run

**Important: no jq in infra-config-apply.sh.** The current script has zero jq dependency. State file JSON is built via printf (same pattern as `ci-deploy.sh:72-75`). The per-file array is the only complexity -- build it by appending comma-separated JSON objects to a shell variable during the write loop.

#### Phase 2: Add /hooks/infra-config-status endpoint + wiring

Add the status endpoint and wire it into Terraform, cloud-init, and CI.

**Files to create:**
- `apps/web-platform/infra/cat-infra-config-state.sh` -- minimal read-only state reporter

The script is deliberately simpler than `cat-deploy-state.sh` (no service status merging, no journal tails, no cron-fire aggregation). It does ONE thing: read the state file and return it.

```bash
#!/usr/bin/env bash
set -euo pipefail
STATE_FILE="${INFRA_CONFIG_STATE:-/var/lock/infra-config-apply.state}"
if [[ ! -f "$STATE_FILE" ]]; then
  echo '{"exit_code":-2,"reason":"no_prior_apply"}'
elif ! jq -c . "$STATE_FILE" 2>/dev/null; then
  echo '{"exit_code":-3,"reason":"corrupt_state"}'
fi
```

**Files to edit:**
- `apps/web-platform/infra/hooks.json.tmpl` -- add `infra-config-status` hook entry (GET, `include-command-output-in-response: true`, same HMAC auth)
- `apps/web-platform/infra/server.tf`:
  - Add `cat_infra_config_state_script_b64 = base64encode(file("${path.module}/cat-infra-config-state.sh"))` to the `templatefile()` vars block (near line 33)
  - Add `file("${path.module}/cat-infra-config-state.sh")` to the `triggers_replace` list (near line 237)
- `apps/web-platform/infra/cloud-init.yml` -- add `write_files` entry for `/usr/local/bin/cat-infra-config-state.sh` (755, root:root, base64-encoded)
- `apps/web-platform/infra/infra-config-apply.sh` -- add FILE_MAP entry: `"CAT_INFRA_CONFIG_STATE_SH_B64|/usr/local/bin/cat-infra-config-state.sh|755|root:root"`
- `apps/web-platform/infra/push-infra-config.sh` -- add the new file to the JSON payload: `"cat_infra_config_state_sh_b64": "$(base64 -w0 < "${INFRA_DIR}/cat-infra-config-state.sh")"`
- `.github/workflows/apply-deploy-pipeline-fix.yml` -- add "Verify infra-config apply succeeded" step after "Verify webhook is alive post-apply", polling `/hooks/infra-config-status` and asserting `exit_code == 0`

**Dependency chain for self-update (AC15):** When `push-infra-config.sh` sends the payload, it must include `cat_infra_config_state_sh_b64`. The webhook handler passes this to `infra-config-apply.sh` as env var `CAT_INFRA_CONFIG_STATE_SH_B64`. The handler writes it to `/usr/local/bin/cat-infra-config-state.sh`. On subsequent applies, the script is self-updated via this path.

#### Phase 3: Tests

**Files to edit:**
- `apps/web-platform/infra/infra-config-apply.test.sh` -- add tests for logging, state file, SHA verification

**Files to create:**
- `apps/web-platform/infra/cat-infra-config-state.test.sh` -- tests for the state reporter

New test cases for `infra-config-apply.test.sh`:
1. Happy path: state file written with correct per-file SHA values and `status: ok` for all files
2. On partial failure (e.g., one bad base64 input under `set +e` controlled scope), state file records the failure with `status: failed`
3. Visudo failure: state file shows `status: skipped, reason: visudo_validation_failed`
4. Logger calls emit with correct tag (mock logger captures args to a file; verify `grep -q "infra-config-apply"`)
5. Self-restart not called until after state file exists (mock `systemd-run` records call order relative to state file write)

New test cases for `cat-infra-config-state.test.sh`:
1. No state file: returns `{"exit_code":-2,"reason":"no_prior_apply"}`
2. Corrupt state file: returns `{"exit_code":-3,"reason":"corrupt_state"}`
3. Valid state file: returns the JSON verbatim

### Deferred to follow-up

**push-infra-config.sh status polling (originally Phase 5).** Adding sleep+poll loops to the Terraform local-exec provisioner bloats `terraform apply` wall-clock by 15-20s per apply. The CI workflow (`apply-deploy-pipeline-fix.yml`) is the correct verification surface -- it already polls `/hooks/deploy-status` and will now also poll `/hooks/infra-config-status` (Phase 2). The provisioner script remains fire-and-forget. If operator-local `terraform apply` needs verification, query `/hooks/infra-config-status` manually afterward.

## Alternative Approaches Considered

| Approach | Rejected Because |
|----------|-----------------|
| Syslog-only (no state file) | Requires SSH or journalctl access to diagnose; violates `hr-no-ssh-fallback-in-runbooks` |
| Webhook synchronous mode (`include-command-output-in-response: true`) | Would expose script stdout in HTTP response but reintroduces Cloudflare 120s timeout risk that #963 solved |
| Separate logging service | Over-engineering for 7 file writes; `logger -t` + state file matches the proven `ci-deploy.sh` pattern |
| Write status to Doppler | Would add Doppler dependency to the webhook handler which currently has none; adds latency and a new failure mode |

## Files to Edit

- `apps/web-platform/infra/infra-config-apply.sh` -- add logging, state file, SHA verification, restart reordering, FILE_MAP entry for new script
- `apps/web-platform/infra/hooks.json.tmpl` -- add `infra-config-status` hook entry
- `apps/web-platform/infra/server.tf` -- add `cat_infra_config_state_script_b64` to cloud-init vars and `triggers_replace`
- `apps/web-platform/infra/cloud-init.yml` -- add `write_files` entry for state reporter script
- `apps/web-platform/infra/push-infra-config.sh` -- add `cat_infra_config_state_sh_b64` to JSON payload (NOT polling -- just the file encoding for self-update)
- `.github/workflows/apply-deploy-pipeline-fix.yml` -- add infra-config-status verification step
- `apps/web-platform/infra/infra-config-apply.test.sh` -- add tests for logging, state file, SHA, restart ordering

## Files to Create

- `apps/web-platform/infra/cat-infra-config-state.sh` -- read-only state reporter for `/hooks/infra-config-status`
- `apps/web-platform/infra/cat-infra-config-state.test.sh` -- tests for the state reporter

## Open Code-Review Overlap

None -- no open `code-review`-labeled issues touch the files in scope.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1: `infra-config-apply.sh` uses `readonly LOG_TAG="infra-config-apply"` and `logger -t "$LOG_TAG"` for all operations (env validation, per-file write, completion summary)
- [ ] AC2: Per-file write status logged with filename + SHA256 + success/fail/skipped status
- [ ] AC3: State file written to `/var/lock/infra-config-apply.state` with JSON structure: `exit_code`, `files_written`, `files_failed`, per-file array with `file`, `sha256`, `status`, `reason`. JSON built via printf (no jq dependency in the handler)
- [ ] AC4: `cat-infra-config-state.sh` exists and returns state file JSON (or sentinels for missing/corrupt). Script is minimal -- no service status merging, no journal tails
- [ ] AC5: `hooks.json.tmpl` contains `infra-config-status` hook entry (GET, `include-command-output-in-response: true`)
- [ ] AC6: Self-restart (`systemd-run`) is called AFTER all file writes complete AND state file is persisted AND `sync` has flushed buffers. Ordering: write loop -> state file -> sync -> daemon-reload -> systemd-run
- [ ] AC7: All existing tests pass (`bash apps/web-platform/infra/infra-config-apply.test.sh`)
- [ ] AC8: New tests cover: state file happy path, partial failure state, logger output, self-restart ordering
- [ ] AC9: `cat-infra-config-state.test.sh` covers: missing state, corrupt state, valid state
- [ ] AC10: `apply-deploy-pipeline-fix.yml` includes "Verify infra-config apply succeeded" step
- [ ] AC11: `server.tf` `triggers_replace` includes the new `cat-infra-config-state.sh`
- [ ] AC12: `cloud-init.yml` includes `write_files` entry for `cat-infra-config-state.sh`
- [ ] AC13: `infra-config-apply.sh` FILE_MAP includes entry for `CAT_INFRA_CONFIG_STATE_SH_B64|/usr/local/bin/cat-infra-config-state.sh|755|root:root`
- [ ] AC14: `push-infra-config.sh` JSON payload includes `cat_infra_config_state_sh_b64` field (file encoding for self-update delivery)

### Post-merge (operator)

- [ ] AC16: After merge, `apply-deploy-pipeline-fix.yml` triggers automatically and `terraform apply -target=terraform_data.deploy_pipeline_fix` succeeds
  - Automation: handled by existing workflow on push to main with path filter
- [ ] AC17: `/hooks/infra-config-status` returns valid JSON when polled post-apply
  - Automation: verified by the new CI step in `apply-deploy-pipeline-fix.yml`

## Test Scenarios

- Given all env vars are set correctly, when infra-config-apply.sh runs, then all 7+ files are written and the state file shows `exit_code: 0, files_failed: 0`
- Given one env var has invalid base64 content, when infra-config-apply.sh runs, then the affected file shows `status: failed` in state and other files still succeed
- Given visudo validation fails for the sudoers file, when infra-config-apply.sh runs, then the sudoers entry shows `status: skipped, reason: visudo_validation_failed` and other files succeed
- Given the script crashes mid-write (EXIT trap fires), when cat-infra-config-state.sh reads the state, then `exit_code` is non-zero with reason `unhandled`
- Given infra-config-apply.sh completes successfully, when `apply-deploy-pipeline-fix.yml` polls `/hooks/infra-config-status`, then it receives JSON with `exit_code: 0`
- Given no prior infra-config apply has run, when `/hooks/infra-config-status` is queried, then it returns `{"exit_code": -2, "reason": "no_prior_apply"}`

## Dependencies & Risks

**Risk: Self-update chicken-and-egg for `cat-infra-config-state.sh`.**
The new state reporter script needs to exist on the host before it can serve `/hooks/infra-config-status`. On the first apply after this PR merges, the script is written by `infra-config-apply.sh` (Phase 3 adds it to FILE_MAP), AND the new hooks.json entry references it. The webhook restarts with the new hooks.json that references the newly-written script -- ordering is correct because hooks.json is written AFTER all scripts.

**Risk: State file path collision with ci-deploy.sh.**
Using `/var/lock/infra-config-apply.state` (distinct from `/var/lock/ci-deploy.state`). Both are in `/var/lock` which is in `ReadWritePaths`.

**Risk: Backward compatibility of CI status polling.**
The status endpoint won't exist until the first post-merge apply. The CI verification step in `apply-deploy-pipeline-fix.yml` must tolerate HTTP 404 gracefully on the initial apply (old host without the endpoint). Implementation: if the poll returns non-200, warn but do not fail the workflow -- the "Verify webhook is alive" step already confirms the webhook binary restarted successfully.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- infrastructure/tooling change.

## Sharp Edges

- The `FILE_MAP` self-update for `cat-infra-config-state.sh` creates a bootstrap dependency: the first apply writes the script, the second apply can update it via the status endpoint. The first `/hooks/infra-config-status` query after the initial apply may fail if the webhook restart hasn't completed yet -- the CI verification step must tolerate this.
- `sha256sum` must be available on the host (standard on Ubuntu/Debian). The test sandbox should verify this or mock it.
- The state file is overwritten on each apply (not appended). Only the most recent apply's state is available. This matches the `ci-deploy.sh` pattern.
- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. Fill it before requesting deepen-plan or `/work`.

## References

- Issue: #4554
- `ci-deploy.sh` logging pattern: `apps/web-platform/infra/ci-deploy.sh:27,62-99`
- `cat-deploy-state.sh` state reporter: `apps/web-platform/infra/cat-deploy-state.sh`
- hooks.json template: `apps/web-platform/infra/hooks.json.tmpl`
- Async webhook learning: `knowledge-base/project/learnings/2026-03-21-async-webhook-deploy-cloudflare-timeout.md`
- SSH-to-webhook migration learning: `knowledge-base/project/learnings/2026-05-26-ssh-to-webhook-provisioner-migration-mount-namespace-traps.md`
- Auto-apply workflow: `.github/workflows/apply-deploy-pipeline-fix.yml`
