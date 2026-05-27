---
title: "fix(infra): add structured logging + error surfacing to infra-config-apply.sh"
type: fix
date: 2026-05-28
lane: single-domain
issue: 4554
---

# Tasks: fix(infra) infra-config-apply logging + error surfacing

## Phase 1: Core — logging + state file + restart reordering

### 1.1 Add structured logging to infra-config-apply.sh
- [ ] Add `readonly LOG_TAG="infra-config-apply"` after `set -euo pipefail`
- [ ] Add `logger -t "$LOG_TAG"` calls for: env var validation failures, per-file write start/success/failure, visudo skip, completion summary
- [ ] Ensure `echo ... >&2` error messages are ALSO sent via `logger -t` (dual output for backward compat)

### 1.2 Add persistent state file
- [ ] Add `STATE_FILE="${INFRA_CONFIG_STATE:-/var/lock/infra-config-apply.state}"` (test-overridable)
- [ ] Add `START_TS=$(date +%s)` at script start
- [ ] Track per-file results during write loop (shell array, no jq)
- [ ] After each successful mv, compute SHA256: `sha256sum "$dest" | awk '{print $1}'`
- [ ] After write loop, build JSON via printf and write atomically via mktemp+mv
- [ ] Add EXIT trap with sentinel pattern for unhandled crashes

### 1.3 Reorder self-restart
- [ ] Insert state file write + `sync` between write loop and `systemd-run` call
- [ ] Final ordering: write loop -> state file write -> sync -> daemon-reload -> systemd-run
- [ ] Add `logger -t "$LOG_TAG" "scheduling self-restart in 3s"` before restart

### 1.4 Add FILE_MAP entry for cat-infra-config-state.sh
- [ ] Add `"CAT_INFRA_CONFIG_STATE_SH_B64|/usr/local/bin/cat-infra-config-state.sh|755|root:root"` to FILE_MAP array

## Phase 2: Endpoint + wiring

### 2.1 Create cat-infra-config-state.sh
- [ ] Create minimal state reporter script (read JSON file, return sentinels for missing/corrupt)
- [ ] No service status merging, no journal tails -- just the state file

### 2.2 Wire into hooks.json.tmpl
- [ ] Add `infra-config-status` hook entry (GET, `include-command-output-in-response: true`, same HMAC auth)

### 2.3 Wire into server.tf
- [ ] Add `cat_infra_config_state_script_b64 = base64encode(file("${path.module}/cat-infra-config-state.sh"))` to templatefile vars
- [ ] Add `file("${path.module}/cat-infra-config-state.sh")` to `triggers_replace` list

### 2.4 Wire into cloud-init.yml
- [ ] Add `write_files` entry for `/usr/local/bin/cat-infra-config-state.sh` (755, root:root)

### 2.5 Update push-infra-config.sh payload
- [ ] Add `"cat_infra_config_state_sh_b64": "$(base64 -w0 < "${INFRA_DIR}/cat-infra-config-state.sh")"` to JSON payload

### 2.6 Add CI verification step
- [ ] Add "Verify infra-config apply succeeded" step to `apply-deploy-pipeline-fix.yml`
- [ ] Poll `/hooks/infra-config-status` post-apply
- [ ] Tolerate HTTP 404 on first apply (warn, do not fail)

## Phase 3: Tests

### 3.1 Extend infra-config-apply.test.sh
- [ ] Test: happy path — state file written with correct per-file SHA and `status: ok`
- [ ] Test: partial failure — bad base64 produces `status: failed` in state
- [ ] Test: visudo failure — `status: skipped, reason: visudo_validation_failed`
- [ ] Test: logger output — mock logger captures correct tag
- [ ] Test: restart ordering — mock systemd-run records call order relative to state file

### 3.2 Create cat-infra-config-state.test.sh
- [ ] Test: no state file — returns `{"exit_code":-2,"reason":"no_prior_apply"}`
- [ ] Test: corrupt state file — returns `{"exit_code":-3,"reason":"corrupt_state"}`
- [ ] Test: valid state file — returns JSON verbatim
