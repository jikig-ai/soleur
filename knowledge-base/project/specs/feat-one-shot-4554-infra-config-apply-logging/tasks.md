---
title: "fix(infra): add structured logging + error surfacing to infra-config-apply.sh"
type: fix
date: 2026-05-28
lane: single-domain
issue: 4554
---

# Tasks: fix(infra) infra-config-apply logging + error surfacing

## Phase 1: Core -- logging + state file + restart reordering

### 1.1 Add structured logging to infra-config-apply.sh
- [ ] Add `readonly LOG_TAG="infra-config-apply"` after `set -euo pipefail`
- [ ] Add `logger -t "$LOG_TAG"` calls for: env var validation failures, per-file write start/success/failure, visudo skip, completion summary
- [ ] Ensure `echo ... >&2` error messages are ALSO sent via `logger -t` (dual output for backward compat)

### 1.2 Restructure write loop for per-file error handling
- [ ] Wrap `base64 -d` in per-file error handler (`if ! ... 2>/dev/null; then ... continue; fi`) so decode failures are recorded without aborting under `set -euo pipefail`
- [ ] Track per-file results in shell variables during write loop (no jq dependency)
- [ ] After each successful mv, compute SHA256: `sha256sum "$dest" | awk '{print $1}'`
- [ ] On failure: log via `logger -t`, record failed status, increment fail counter, continue

### 1.3 Add persistent state file
- [ ] Add `STATE_FILE="${INFRA_CONFIG_STATE:-/var/lock/infra-config-apply.state}"` (test-overridable)
- [ ] Add `START_TS=$(date +%s)` at script start
- [ ] After write loop, build JSON via printf and write atomically via mktemp+mv
- [ ] Redesign EXIT trap: clear stale `.final` sentinel, write `"unhandled"` state on non-zero exit without sentinel, clean tmpfiles (precedent: `ci-deploy.sh:105-111`)
- [ ] At normal completion: touch `.final` sentinel BEFORE writing success state (precedent: `ci-deploy.sh:96-97`)

### 1.4 Reorder self-restart
- [ ] Insert state file write + `sync` between write loop and `systemd-run` call
- [ ] Final ordering: write loop -> state file write -> sync -> daemon-reload -> systemd-run
- [ ] Add `logger -t "$LOG_TAG" "scheduling self-restart in 3s"` before restart

### 1.5 Add FILE_MAP entry for cat-infra-config-state.sh
- [ ] Add `"CAT_INFRA_CONFIG_STATE_SH_B64|/usr/local/bin/cat-infra-config-state.sh|755|root:root"` to FILE_MAP array

## Phase 2: Endpoint + wiring

### 2.1 Create cat-infra-config-state.sh
- [ ] Create minimal state reporter script (read JSON file, return sentinels for missing/corrupt)
- [ ] No service status merging, no journal tails -- just the state file
- [ ] Add comment explaining that `jq -c .` printing to stdout IS the success path (no explicit else needed)

### 2.2 Wire into hooks.json.tmpl
- [ ] Add `infra-config-status` hook entry (GET, `include-command-output-in-response: true`, same HMAC auth)
- [ ] Add `CAT_INFRA_CONFIG_STATE_SH_B64` to `infra-config` hook's `pass-environment-to-command` array

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

### 2.7 Update workflow paths filter
- [ ] Add `"apps/web-platform/infra/cat-infra-config-state.sh"` to `apply-deploy-pipeline-fix.yml` `paths:` list

### 2.8 Update drift guard test
- [ ] Add `"apps/web-platform/infra/cat-infra-config-state.sh"` to `TRIGGER_FILES` array in `plugins/soleur/test/ship-deploy-pipeline-fix-gate.test.ts`

## Phase 3: Tests

### 3.1 Extend infra-config-apply.test.sh
- [ ] Test: happy path -- state file written with correct per-file SHA and `status: ok` for all 8 files
- [ ] Test: partial failure -- bad base64 produces `status: failed` in state, other files still succeed
- [ ] Test: visudo failure -- `status: skipped, reason: visudo_validation_failed`
- [ ] Test: logger output -- mock logger captures correct tag
- [ ] Test: restart ordering -- mock systemd-run records call order relative to state file
- [ ] Test: EXIT trap writes unhandled state on crash (simulate with early exit)

### 3.2 Create cat-infra-config-state.test.sh
- [ ] Test: no state file -- returns `{"exit_code":-2,"reason":"no_prior_apply"}`
- [ ] Test: corrupt state file -- returns `{"exit_code":-3,"reason":"corrupt_state"}`
- [ ] Test: valid state file -- returns JSON verbatim
