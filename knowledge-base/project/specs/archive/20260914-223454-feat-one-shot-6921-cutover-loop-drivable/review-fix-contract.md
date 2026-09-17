# Review-fix contract (PR #8173 review round 1, CTO ruling 2026-09-14)

Binding for every file touched in the fix round. Where it conflicts with the plan, this wins.

## 1. Quiesce marker

- Path: `${INNGEST_QUIESCE_MARKER:-/var/lib/inngest/quiesced-by-op}` (root disk; survives reboot).
- Writer: ONLY the `ci-deploy.sh` `quiesce inngest` handler. Atomic (`mktemp` in the same dir, then `mv -f`).
- JSON: `{"v":1,"epoch":<int unix s>,"boot_id":"<str from /proc/sys/kernel/random/boot_id>","host_id":"<str>","run_id":"<str>","capture_sha256":"<64 hex>","capture_count":<int>}`. May later gain `"capture_consumed_at":<int>` (written only by `inngest-rearm-reminders.sh` rearm-from-capture on full success).
- Capture file: `${INNGEST_CUTOVER_CAPTURE_FILE:-/var/lib/inngest/cutover-capture.json}`.

## 2. Tri-state function (BYTE-IDENTICAL in ci-deploy.sh, inngest-inventory.sh, inngest-rearm-reminders.sh)

Paste exactly this block (it writes to stdout only the state word; callers use `$(inngest_quiesce_state)`):

```bash
# Quiesce state of the web inngest unit (ADR-100 amendment 2026-09-14, CTO ruling): the
# systemd shape says "must not be started"; the marker says "a deliberate op=quiesce-web".
# Prints exactly one of: quiesced | disabled_unattributed | not_quiesced. Byte-identical in
# ci-deploy.sh, inngest-inventory.sh and inngest-rearm-reminders.sh (parity test pins it).
inngest_quiesce_state() {
  local a e m me ae ae_epoch
  a="$(systemctl is-active inngest-server.service 2>/dev/null || true)"
  e="$(systemctl is-enabled inngest-server.service 2>/dev/null || true)"
  if [[ ! ( ( "$a" == inactive || "$a" == failed ) && "$e" == disabled ) ]]; then
    echo not_quiesced
    return 0
  fi
  m="${INNGEST_QUIESCE_MARKER:-/var/lib/inngest/quiesced-by-op}"
  me="$(jq -r 'if (.v == 1 and (.epoch | type) == "number") then (.epoch | floor | tostring) else "" end' "$m" 2>/dev/null || true)"
  if [[ ! "$me" =~ ^[0-9]{9,11}$ ]]; then
    echo disabled_unattributed
    return 0
  fi
  ae="$(systemctl show -p ActiveEnterTimestamp --value inngest-server.service 2>/dev/null || true)"
  if [[ -n "$ae" && "$ae" != "n/a" ]]; then
    ae_epoch="$(date -d "$ae" +%s 2>/dev/null || true)"
    if [[ "$ae_epoch" =~ ^[0-9]+$ ]] && (( ae_epoch > me )); then
      echo disabled_unattributed
      return 0
    fi
  fi
  echo quiesced
}
```

Void rule: `ActiveEnterTimestamp` later than `marker.epoch` ⇒ the unit started after the quiesce ⇒ unattributed. An empty `ActiveEnterTimestamp` (after a reboot) is NOT void.

## 3. Which signal each site uses

| Site | Signal | Outcome |
|---|---|---|
| ci-deploy `restart` handler | shape (state != not_quiesced) | `quiesced` → `inngest_quiesced_restart_refused`; `disabled_unattributed` → `inngest_disabled_unattributed_restart_refused`. Both exit 1, no restart verb |
| ci-deploy `deploy inngest` arm (top, before pull) | same | `inngest_quiesced_deploy_refused` / `inngest_disabled_unattributed_deploy_refused` |
| inngest-wiped-volume-verify.sh | shape only (unchanged predicate) — move the gate BEFORE enumeration | `quiesced_refused` |
| workspaces-cutover.sh reconcile + dead-man | shape only (unchanged) | skip start |
| inngest-inventory.sh non-array branch | shape AND marker (tri-state) | see §4 |
| inngest-rearm-reminders.sh capture | tri-state + sha | see §5 |

## 4. Inventory output lines (non-200, exit 1)

- `quiesced` and `/health` != 200:
  `inngest-inventory: QUIESCED host_id=$HOST_ID unit=$a enabled=disabled quiesced_since=$epoch capture=<present|consumed|absent> rebooted_since_quiesce=<true|false> — deliberate stop+disable (op=quiesce-web); no restart`
  - `capture=present`: capture file exists and its sha256 == marker.capture_sha256; `consumed`: marker has `capture_consumed_at`; else `absent`.
  - `rebooted_since_quiesce`: current boot_id != marker.boot_id.
  - journald: `SOLEUR_INNGEST_LIVENESS_VERDICT mode=quiesced quiesced_since=… host_id=…`
- `disabled_unattributed` and `/health` != 200:
  `inngest-inventory: DISABLED_UNATTRIBUTED host_id=$HOST_ID unit=$a enabled=disabled — scheduler disabled with no valid quiesce marker; not a deliberate quiesce; dispatch op=rollback`
  - journald `SOLEUR_INNGEST_LIVENESS_VERDICT mode=disabled_unattributed host_id=…`
- `/health == 200` still wins (DEGRADED in liveness mode; unchanged FATAL in full mode).
- Every field before the ` — ` separator is fixed-vocabulary; consumers must parse only that region, anchored at line start.
- Both lines are evaluated BEFORE `_pf_timeout_marker gql_error` and the `ERROR:` logger (no marker noise on quiesced ticks).

## 5. Rearm script

- `capture` mode:
  - state `not_quiesced` → live enumeration (response unchanged, no `source`).
  - state `quiesced` → require capture file is a JSON array AND sha256 == marker.capture_sha256 AND marker has no `capture_consumed_at`. Output `{captured, reminder_ids, capture_file, source:"persisted", captured_at:<ISO of marker.epoch>, quiesced_since:<marker.epoch>, rebooted_since_quiesce:<bool>}`. Refusals (exit 1, stderr, one line each):
    - consumed → `ERROR: capture: already re-armed (capture consumed at <ISO>) — nothing to resume; if scheduling must reopen dispatch op=rollback`
    - no/invalid capture or sha mismatch → `ERROR: capture: stale_capture — the persisted capture does not match the quiesce marker (<reason>); dispatch op=rollback, then op=quiesce-web to take a fresh capture`
  - state `disabled_unattributed` → exit 1 `ERROR: capture: capture_unattributed — scheduler disabled with no valid quiesce marker; dispatch op=rollback, then op=quiesce-web`
- `rearm-from-capture`:
  - If a marker exists: require sha256(capture) == marker.capture_sha256 (else exit 1 `stale_capture`, file kept).
  - Hold back records whose `fire_at` (ms) <= cutoff_s*1000, where cutoff_s = max(marker.epoch, stop_epoch) and stop_epoch is `InactiveEnterTimestamp` only when readable AND the current boot_id equals marker.boot_id (else marker.epoch): they were due while the web scheduler was still running and already fired there. (Amended: the marker precedes the ≤180 s stop.) They are NOT POSTed; count them as `held_back`, print their ids on stderr `inngest-rearm-reminders: held back <n> reminder(s) due before the quiesce: <ids>`.
  - Canonical final line (stderr): `inngest-rearm-reminders: re-armed=N failed=F held_back=H total=K` where K = N+F+H = record count. The Σ=0 line becomes `re-armed=0 failed=0 held_back=0 total=0`.
  - On full success (F == 0): delete the capture file and, if a marker exists, rewrite it atomically with `capture_consumed_at`.
  - 503 handling: capture response headers (`curl -D`); `X-Soleur-Unavailable: backend-refused` → abort with `ERROR: re-arm got 503 backend-refused for reminder_id=<id> — the app's Inngest backend is not accepting connections (the INNGEST_BASE_URL repoint has not deployed, or the dedicated host is restarting); capture retained; re-run op=rearm once the backend serves`; `cutover-quiesce` (or header absent) → the existing INNGEST_CUTOVER_QUIESCE message.
- `inngest-enumerate-reminders.sh`: scrub GraphQL error text before printing (URIs, `user:pass@`, `password=`, DSN key=value), mirroring `_pf_scrub` in inngest-inventory.sh.

## 6. ci-deploy.sh handlers

- `quiesce inngest` entry, by state and is-active:
  - is-active `active` → capture (bounded, as today) → `capture_sha256=$(sha256sum capture)`, `capture_count=$(jq length)` → write marker atomically (failure → `quiesce_marker_write_failed`, exit 1, nothing stopped) → disable → stop → verify → fan-out.
  - state `quiesced` (re-dispatch) → no capture, marker untouched (epoch must not move) → disable/stop (idempotent) → verify → fan-out.
  - unit absent (`is-enabled` prints `not-found` or empty AND is-active `inactive`) → no capture, no marker → existing verify/fan-out (web-2 path).
  - anything else (failed, activating, deactivating, inactive+enabled, disabled_unattributed) → `logger -t "$LOG_TAG" "INNGEST_QUIESCE_CAPTURE_UNAVAILABLE unit=$a enabled=$e state=$st"`, `final_write_state 1 "quiesce_capture_unavailable"`, exit 1, nothing disabled/stopped.
  - Capture stderr tail: `_cred_err_tail` THEN a URI/DSN scrub before logging `INNGEST_QUIESCE_CAPTURE_FAILED`.
  - No second EXIT trap: remove the temp file explicitly on every path.
  - Final verify: after `verify_inngest_quiesced` passes, require `inngest_quiesce_state` == `quiesced` (unit present) else `final_write_state 1 "quiesced_shape_unrecognized"`.
- `enable inngest` (op=rollback): BEFORE enable/start, `mv -f capture capture.retired-<epoch>` (if present) and `rm -f marker`; log `INNGEST_ENABLE: retired capture=<path|none> marker_removed=<true|false>`.
- web-platform deploy health hint: when `inngest_quiesce_state` != not_quiesced, log `INNGEST_HEALTH_CHECK: quiesced (<state>) — no restart hint` instead of suggesting restart-inngest-server.yml.

## 7. Deploy-status reasons (new)

`quiesce_capture_unavailable`, `quiesce_marker_write_failed`, `quiesced_shape_unrecognized`, `inngest_disabled_unattributed_restart_refused`, `inngest_disabled_unattributed_deploy_refused` (plus existing `quiesce_capture_failed`, `inngest_quiesced_restart_refused`, `inngest_quiesced_deploy_refused`, `quiesced_refused`).

## 8. Classifier + watchdog

- Classifier: `^inngest-inventory: QUIESCED` → `inngest_quiesced`; `^inngest-inventory: DISABLED_UNATTRIBUTED` → `inngest_disabled_unattributed`. Neither is restart-family. Line-anchored (multi-line bodies), herestrings not `printf | grep -q`.
- Probe step:
  - `inngest_quiesced)` → extract `quiesced_since` from the FIRST QUIESCED line with an anchored sed over the fixed region (`^inngest-inventory: QUIESCED host_id=[^ ]* unit=[a-z]* enabled=disabled quiesced_since=\([0-9]\{9,11\}\) `); unparseable → `unknown`; `web_quiesced_since=<epoch|unknown>`; break; no failure.
  - `inngest_disabled_unattributed)` → `record_failure "inngest_disabled_unattributed" "<detail>"`; break. Not in the restart-dispatch `if:`. The file-issue step gets an arm (title `[ci/inngest-disabled-unattributed]`, remedy op=rollback). Check-in `error`.
  - Output `web_quiesced_since` (empty unless quiesced). Its ONLY reader is the new `nolive` step.
- New step `id: nolive` after the dedicated-host steps, `if: always()`: env `INNGEST_QUIESCE_GRACE_MIN: 60`. `alarm=true` iff `web_quiesced_since != ''` AND dedicated verdict != `healthy` (including empty/`probe-unavailable`/`stopped-by-brake`) AND (since == `unknown` OR now − since > GRACE·60). Always writes `alarm=true|false`. On true: `::error::`, file/comment `[ci/inngest-no-live-scheduler]` (label `action-required`). A close step closes it when `alarm == 'false'`.
- Sentry check-in `ok` additionally requires `steps.nolive.outputs.alarm != 'true'`.

## 9. CI (scripts/cutover-inngest.sh)

- 2.2 PASSED only when no probe returned 200, ≥1 non-200 body carries the anchored QUIESCED sentinel, AND every answered non-200 (non-000) body carries it. A `DISABLED_UNATTRIBUTED` body → UNKNOWN with remedy `op=rollback`.
- Rearm P2-b parser accepts the `held_back=H` field (absent ⇒ 0) and reconciles N+F+H == K and K == Σcaptured.
- quiesce-web preflight (before any stop): `/hooks/infra-config-status` sha256 of `/usr/local/bin/{ci-deploy.sh,inngest-inventory.sh,inngest-rearm-reminders.sh,inngest-enumerate-reminders.sh}` must equal the checkout's `sha256sum`; else `::error::` "config push not landed" and exit 1 before dispatching.
- quiesce-web poller: `lock_contention` keeps polling; explicit arms for `quiesce_capture_failed`, `quiesce_capture_unavailable`, `quiesce_marker_write_failed`, `quiesced_shape_unrecognized` with remedies.
