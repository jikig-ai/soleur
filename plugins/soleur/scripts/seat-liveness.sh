#!/usr/bin/env bash
# seat-liveness.sh — ephemeral metadata-only spawned-agent seat liveness and bounded recovery (#12524, ADR-332).
#
# Subcommands:
#   seat-liveness.sh init      --run-dir <dir> --seat <id> [--harness <h>] [--role <r>] [--tier <t>]
#                              [--writable <true|false>] [--side-effecting <true|false>]
#                              [--idle-timeout-ms <ms>] [--deadline-ms <ms>] [--artifact-path <p>] [--now-ms <ms>]
#   seat-liveness.sh heartbeat --run-dir <dir> --seat <id> [--now-ms <ms>]
#   seat-liveness.sh sweep     --run-dir <dir> [--seat <id>] [--now-ms <ms>] [--exited <true|false>]
#                              [--exit-code <rc>] [--error <msg>] [--hook-deferred <true|false>] [--floor-passed <true|false>]
#   seat-liveness.sh decide    --run-dir <dir> --seat <id> [--dirty-diff <true|false>]
#                              [--diff-verified <true|false>] [--artifact-verified <true|false>]
#   seat-liveness.sh cleanup   --run-dir <dir> [--ttl-ms <ms>] [--now-ms <ms>]
#   seat-liveness.sh --self-test
#
# Metadata-only boundary (FR2): rejects --prompt, --transcript, --messages, --raw-output, or secret-shaped tokens.

set -euo pipefail

if [[ "${1:-}" == "--self-test" ]]; then
  sb="$(mktemp -d)"
  trap 'rm -rf "$sb"' EXIT
  bash "$0" init --run-dir "$sb" --seat "selftest" --harness claude --role "selftest-role" --now-ms 1000000 >/dev/null
  bash "$0" heartbeat --run-dir "$sb" --seat "selftest" --now-ms 1010000 >/dev/null
  bash "$0" sweep --run-dir "$sb" --seat "selftest" --now-ms 1020000 >/dev/null
  bash "$0" decide --run-dir "$sb" --seat "selftest" >/dev/null
  bash "$0" cleanup --run-dir "$sb" --now-ms 1030000 >/dev/null
  echo "SOLEUR_SEAT_LIVENESS_SELFTEST=ok"
  exit 0
fi

SUBCMD="${1:-}"
if [[ -z "$SUBCMD" ]]; then
  echo "seat-liveness: subcommand required (init|heartbeat|sweep|decide|cleanup|--self-test)" >&2
  exit 2
fi
shift

detect_active_harness() {
  if [[ -n "${SOLEUR_HARNESS:-}" ]]; then printf '%s' "$SOLEUR_HARNESS"; return; fi
  if [[ -n "${CLAUDECODE:-}" ]]; then printf 'claude'; return; fi
  if [[ -n "${OPENCODE:-}" ]]; then printf 'opencode'; return; fi
  if [[ -n "${ANTIGRAVITY_CLI:-}${AGY_VERSION:-}${GEMINI_CLI:-}" ]]; then printf 'antigravity'; return; fi
  if [[ -n "${GROK_HOME:-}${GROK_AGENT:-}${GROK_DEFAULT_MODEL:-}${GROK_SUBAGENTS:-}" ]]; then printf 'grok'; return; fi
  if [[ -n "${CODEX_THREAD_ID:-}" ]]; then printf 'codex'; return; fi
  if [[ -n "${DEVIN:-}${DEVIN_HOME:-}" ]]; then printf 'devin'; return; fi
  printf 'claude'
}

RUN_DIR=""
SEAT_ID=""
HARNESS="$(detect_active_harness)"
ROLE="subagent"
TIER="inherit"
WRITABLE="false"
SIDE_EFFECTING="false"
IDLE_TIMEOUT_MS="120000"
DEADLINE_MS="600000"
ARTIFACT_PATH=""
NOW_MS=""
EXITED="false"
EXIT_CODE="0"
ERROR_MSG=""
HOOK_DEFERRED="false"
FLOOR_PASSED=""
DIRTY_DIFF=""
DIFF_VERIFIED=""
ARTIFACT_VERIFIED=""
TTL_MS="86400000"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --run-dir) RUN_DIR="$2"; shift 2 ;;
    --seat) SEAT_ID="$2"; shift 2 ;;
    --harness) HARNESS="$2"; shift 2 ;;
    --role) ROLE="$2"; shift 2 ;;
    --tier) TIER="$2"; shift 2 ;;
    --writable) WRITABLE="$2"; shift 2 ;;
    --side-effecting) SIDE_EFFECTING="$2"; shift 2 ;;
    --idle-timeout-ms) IDLE_TIMEOUT_MS="$2"; shift 2 ;;
    --deadline-ms) DEADLINE_MS="$2"; shift 2 ;;
    --artifact-path) ARTIFACT_PATH="$2"; shift 2 ;;
    --now-ms) NOW_MS="$2"; shift 2 ;;
    --exited) EXITED="$2"; shift 2 ;;
    --exit-code) EXIT_CODE="$2"; shift 2 ;;
    --error) ERROR_MSG="$2"; shift 2 ;;
    --hook-deferred) HOOK_DEFERRED="$2"; shift 2 ;;
    --floor-passed) FLOOR_PASSED="$2"; shift 2 ;;
    --dirty-diff) DIRTY_DIFF="$2"; shift 2 ;;
    --diff-verified) DIFF_VERIFIED="$2"; shift 2 ;;
    --artifact-verified) ARTIFACT_VERIFIED="$2"; shift 2 ;;
    --ttl-ms) TTL_MS="$2"; shift 2 ;;
    --prompt|--transcript|--messages|--raw-output|--secret|--token|--api-key)
      echo "seat-liveness: forbidden metadata-only violation ($1 is prohibited)" >&2
      exit 2 ;;
    *)
      echo "seat-liveness: unknown argument $1" >&2
      exit 2 ;;
  esac
done

if [[ -z "$RUN_DIR" ]]; then
  echo "seat-liveness: --run-dir is required" >&2
  exit 2
fi

SEATS_DIR="$RUN_DIR/seats"
mkdir -p "$SEATS_DIR"

if [[ "$SUBCMD" == "decide" && -z "$DIRTY_DIFF" ]]; then
  if git -C "$RUN_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 && [[ -n "$(git -C "$RUN_DIR" status --porcelain --untracked-files=no 2>/dev/null || true)" ]]; then
    DIRTY_DIFF="true"
  else
    DIRTY_DIFF="false"
  fi
fi

python3 - "$SUBCMD" "$SEATS_DIR" "$SEAT_ID" "$HARNESS" "$ROLE" "$TIER" "$WRITABLE" "$SIDE_EFFECTING" \
  "$IDLE_TIMEOUT_MS" "$DEADLINE_MS" "$ARTIFACT_PATH" "$NOW_MS" "$EXITED" "$EXIT_CODE" "$ERROR_MSG" \
  "$HOOK_DEFERRED" "$FLOOR_PASSED" "$DIRTY_DIFF" "$DIFF_VERIFIED" "$ARTIFACT_VERIFIED" "$TTL_MS" <<'PY'
import glob
import json
import os
import re
import sys
import time

(
    subcmd,
    seats_dir,
    seat_id,
    harness,
    role,
    tier,
    writable_s,
    side_effecting_s,
    idle_timeout_s,
    deadline_s,
    artifact_path,
    now_s,
    exited_s,
    exit_code_s,
    error_msg,
    hook_deferred_s,
    floor_passed_s,
    dirty_diff_s,
    diff_verified_s,
    artifact_verified_s,
    ttl_s,
) = sys.argv[1:22]

now_ms = int(now_s) if now_s else int(time.time() * 1000)
ttl_ms = int(ttl_s)
SEAT_ID_RE = re.compile(r"^[A-Za-z0-9:._-]{1,128}$")
LINE_BREAK_RE = re.compile(r"[\r\n\u2028\u2029]")
SECRET_RE = re.compile(
    r"BEGIN [A-Z ]*PRIVATE KEY|sk-ant-[A-Za-z0-9_-]{10,}|gh[pousr]_[A-Za-z0-9._~+/=-]{16,}|"
    r"github_pat_[A-Za-z0-9._~+/=-]{16,}|sk_(?:live|test)_[A-Za-z0-9]{16,}|"
    r"dp\.(?:pt|st|sa|ct)\.[A-Za-z0-9_-]{20,}|AKIA[0-9A-Z]{16}"
)
SATURATION_RE = re.compile(
    r"\b(?:429|529|503)\b|rate[-_ ]?limit|resource[-_ ]?exhausted|overloaded|quota[-_ ]?exceeded|capacity|too many requests|usage[-_ ]?limit",
    re.IGNORECASE,
)
VALID_HARNESSES = {"claude", "grok", "codex", "devin", "cursor", "opencode", "antigravity", "unknown"}
VALID_TIERS = {"cheap", "standard", "strong", "advisor", "inherit"}
IN_BAND_NUDGE_HARNESSES = {"claude", "codex", "antigravity"}
CHILD_DISK_HEARTBEAT_HARNESSES = {"claude", "codex", "antigravity", "grok", "opencode"}
FALLBACK_GRAPH = {
    "cheap": None,
    "standard": "cheap",
    "strong": None,
    "advisor": "strong",
    "inherit": None,
}

for field_name, val in (
    ("seat_id", seat_id),
    ("harness", harness),
    ("role", role),
    ("tier", tier),
    ("artifact_path", artifact_path),
    ("error", error_msg),
):
    if not val:
        continue
    if SECRET_RE.search(val):
        sys.stderr.write(f"seat-liveness: secret redaction violation in metadata field '{field_name}'\n")
        sys.exit(2)
    if field_name != "error" and (len(val) > 512 or LINE_BREAK_RE.search(val)):
        sys.stderr.write(f"seat-liveness: metadata-only violation in '{field_name}' (length or newline constraint)\n")
        sys.exit(2)

if artifact_path and re.search(r"(?:^|[\\/])\.\.(?:[\\/]|$)", artifact_path):
    sys.stderr.write("seat-liveness: invalid --artifact-path (path traversal prohibited)\n")
    sys.exit(2)


def validate_seat_id(sid: str) -> str:
    if not sid or not SEAT_ID_RE.match(sid) or sid in (".", "..") or sid.startswith("-"):
        sys.stderr.write("seat-liveness: invalid --seat id (must match /^[A-Za-z0-9:._-]{1,128}$/)\n")
        sys.exit(2)
    return sid


def safe_seat_file(sid: str) -> str:
    valid = validate_seat_id(sid)
    clean = re.sub(r"[^A-Za-z0-9._-]", "_", valid)
    return os.path.join(seats_dir, f"{clean}.json")


def write_seat(path: str, data: dict) -> None:
    tmp = f"{path}.{os.getpid()}.tmp"
    try:
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2)
            f.write("\n")
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp):
            try:
                os.remove(tmp)
            except OSError:
                pass


def read_seat(path: str) -> dict:
    if os.path.islink(path):
        sys.stderr.write("seat-liveness: refusing symlinked seat file\n")
        sys.exit(2)
    if not os.path.exists(path):
        sys.stderr.write(f"seat-liveness: seat file not found: {path}\n")
        sys.exit(2)
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
    if not isinstance(data, dict):
        raise ValueError("seat file is not a JSON object")
    return data


def sweep_ttl(now_val: int, ttl_val: int) -> tuple[int, int]:
    removed = 0
    retained = 0
    for tmp_p in glob.glob(os.path.join(seats_dir, "*.tmp")):
        try:
            if os.path.islink(tmp_p) or (now_val - int(os.path.getmtime(tmp_p) * 1000) > ttl_val):
                os.remove(tmp_p)
        except OSError:
            pass
    for p in sorted(glob.glob(os.path.join(seats_dir, "*.json"))):
        if os.path.islink(p):
            try:
                os.remove(p)
                removed += 1
            except OSError:
                pass
            continue
        try:
            rec = read_seat(p)
            last_ts = int(rec.get("last_progress_at") or rec.get("started_at") or 0)
        except Exception:
            try:
                last_ts = int(os.path.getmtime(p) * 1000)
            except OSError:
                last_ts = 0
        if now_val - last_ts > ttl_val:
            try:
                os.remove(p)
                removed += 1
            except OSError:
                retained += 1
        else:
            retained += 1
    return removed, retained


if subcmd == "init":
    validate_seat_id(seat_id)
    if harness not in VALID_HARNESSES:
        harness = "unknown"
    if tier not in VALID_TIERS:
        sys.stderr.write(f"seat-liveness init: invalid --tier '{tier}'\n")
        sys.exit(2)
    # Automatic 24h TTL sweep on init so stale seats never pollute `.soleur/runs/default/seats/`.
    sweep_ttl(now_ms, ttl_ms)
    idle_ms = int(idle_timeout_s)
    deadline_delta = int(deadline_s)
    seat_path = safe_seat_file(seat_id)
    prior_attempt = 0
    if os.path.exists(seat_path) and not os.path.islink(seat_path):
        try:
            prior_rec = read_seat(seat_path)
            if prior_rec.get("status") not in ("completed", "recovered", "escalated"):
                prior_attempt = int(prior_rec.get("attempt", 0))
        except Exception:
            prior_attempt = 0
    record = {
        "seat_id": seat_id,
        "harness": harness,
        "role": role,
        "tier": tier,
        "writable": writable_s.lower() == "true",
        "side_effecting": side_effecting_s.lower() == "true",
        "started_at": now_ms,
        "last_progress_at": now_ms,
        "deadline_at": now_ms + deadline_delta,
        "idle_timeout_ms": idle_ms,
        "attempt": prior_attempt,
        "status": "running",
        "classification": "alive",
        "artifact_path": artifact_path,
        "updated_at": now_ms,
    }
    write_seat(seat_path, record)
    print(f"SOLEUR_SEAT_LIVENESS seat={seat_id} status=alive action=init")

elif subcmd == "heartbeat":
    p = safe_seat_file(seat_id)
    rec = read_seat(p)
    rec["last_progress_at"] = max(int(rec.get("last_progress_at", now_ms)), now_ms)
    rec["updated_at"] = now_ms
    write_seat(p, rec)
    print(f"SOLEUR_SEAT_LIVENESS seat={seat_id} status={rec.get('classification', 'alive')} action=heartbeat")

elif subcmd == "sweep":
    if seat_id:
        paths = [safe_seat_file(seat_id)]
        if not os.path.exists(paths[0]) or os.path.islink(paths[0]):
            sys.stderr.write(f"seat-liveness sweep: seat file not found for '{seat_id}'\n")
            sys.exit(2)
    else:
        paths = sorted(glob.glob(os.path.join(seats_dir, "*.json")))
    exited = exited_s.lower() == "true"
    exit_code = int(exit_code_s)
    hook_deferred = hook_deferred_s.lower() == "true"

    for p in paths:
        if not os.path.exists(p) or os.path.islink(p):
            continue
        rec = read_seat(p)
        if not seat_id and rec.get("status") in ("completed", "recovered", "escalated"):
            continue
        sid = validate_seat_id(str(rec.get("seat_id", "")))
        art = rec.get("artifact_path", "")
        art_ok = True
        if art:
            art_ok = (not os.path.islink(art)) and os.path.isfile(art) and os.path.getsize(art) > 0
        floor_ok = True if floor_passed_s == "" else (floor_passed_s.lower() == "true")

        clean_done = exited and exit_code == 0 and art_ok and floor_ok
        attempt = int(rec.get("attempt", 0))

        if hook_deferred:
            cls = "hook_deferred"
        elif error_msg and SATURATION_RE.search(error_msg):
            cls = "rate_limit"
        elif now_ms >= int(rec["deadline_at"]) and not clean_done:
            cls = "crash"
        elif exited:
            if exit_code != 0:
                cls = "crash"
            elif not art_ok or not floor_ok:
                cls = "truncated"
            else:
                cls = "alive"
                rec["status"] = "recovered" if attempt > 0 else "completed"
                rec["reviewed_coverage"] = "full"
        else:
            idle_elapsed = now_ms - int(rec["last_progress_at"])
            total_elapsed = now_ms - int(rec["started_at"])
            idle_limit = int(rec["idle_timeout_ms"])
            seat_harness = rec.get("harness", "unknown")
            if seat_harness in CHILD_DISK_HEARTBEAT_HARNESSES and idle_elapsed > idle_limit:
                cls = "crash"
            elif total_elapsed > idle_limit:
                cls = "legit_long_turn"
            else:
                cls = "alive"

        rec["classification"] = cls
        rec["updated_at"] = now_ms
        write_seat(p, rec)
        print(f"SOLEUR_SEAT_LIVENESS seat={sid} status={cls} action=sweep")

elif subcmd == "decide":
    p = safe_seat_file(seat_id)
    rec = read_seat(p)
    sid = validate_seat_id(str(rec.get("seat_id", "")))
    cls = rec.get("classification", "alive")
    writable = bool(rec.get("writable", False))
    side_fx = bool(rec.get("side_effecting", False))
    attempt = int(rec.get("attempt", 0))
    h = rec.get("harness", "unknown")
    t = rec.get("tier", "inherit")

    dirty_diff = dirty_diff_s.lower() == "true" if dirty_diff_s != "" else False
    diff_verified = None if diff_verified_s == "" else (diff_verified_s.lower() == "true")
    art_verified = artifact_verified_s.lower() == "true"

    action = "none"
    fb_tier = "none"
    rcov = "full"

    if cls in ("alive", "legit_long_turn"):
        action = "none"
        rcov = "full"
    elif writable and dirty_diff:
        if diff_verified is True:
            action = "accept"
            rec["status"] = "recovered"
            rcov = "full"
        elif diff_verified is None:
            action = "verify_disk"
            rec["status"] = "escalated"
            rcov = "degraded"
        else:
            action = "escalate"
            rec["status"] = "escalated"
            rcov = "degraded"
    elif art_verified:
        action = "accept"
        rec["status"] = "recovered"
        rcov = "full"
    elif side_fx:
        action = "escalate"
        rec["status"] = "escalated"
        rcov = "degraded"
    elif attempt >= 1:
        action = "escalate"
        rec["status"] = "escalated"
        rcov = "degraded"
    else:
        duration_budget = max(
            int(rec.get("deadline_at", now_ms)) - int(rec.get("started_at", now_ms)),
            int(rec.get("idle_timeout_ms", 120000)),
        )
        if h in IN_BAND_NUDGE_HARNESSES and cls in ("hook_deferred", "truncated"):
            action = "nudge"
            attempt += 1
            rec["attempt"] = attempt
            rec["status"] = "running"
            rec["last_progress_at"] = now_ms
            rcov = "full"
        else:
            action = "respawn"
            attempt += 1
            rec["attempt"] = attempt
            rec["status"] = "running"
            rec["last_progress_at"] = now_ms
            rec["deadline_at"] = now_ms + duration_budget
            if cls == "rate_limit":
                fb_tier = FALLBACK_GRAPH.get(t) or "same"
            else:
                fb_tier = "same"
            rcov = "full"

    rec["recovery_action"] = action
    rec["fallback_tier"] = fb_tier
    rec["reviewed_coverage"] = rcov
    rec["updated_at"] = now_ms
    write_seat(p, rec)
    print(
        f"SOLEUR_SEAT_LIVENESS seat={sid} status={cls} action={action} "
        f"attempt={attempt} fallback_tier={fb_tier} reviewed_coverage={rcov}"
    )

elif subcmd == "cleanup":
    removed, retained = sweep_ttl(now_ms, ttl_ms)
    print(f"SOLEUR_SEAT_LIVENESS_CLEANUP removed={removed} retained={retained}")

else:
    sys.stderr.write(f"seat-liveness: unknown subcommand '{subcmd}'\n")
    sys.exit(2)
PY
