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

RUN_DIR=""
SEAT_ID=""
HARNESS="${SOLEUR_HARNESS:-claude}"
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
DIRTY_DIFF="false"
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

if [[ -z "$NOW_MS" ]]; then
  NOW_MS="$(python3 -c 'import time; print(int(time.time() * 1000))')"
fi

SEATS_DIR="$RUN_DIR/seats"
mkdir -p "$SEATS_DIR"

python3 - "$SUBCMD" "$SEATS_DIR" "$SEAT_ID" "$HARNESS" "$ROLE" "$TIER" "$WRITABLE" "$SIDE_EFFECTING" \
  "$IDLE_TIMEOUT_MS" "$DEADLINE_MS" "$ARTIFACT_PATH" "$NOW_MS" "$EXITED" "$EXIT_CODE" "$ERROR_MSG" \
  "$HOOK_DEFERRED" "$FLOOR_PASSED" "$DIRTY_DIFF" "$DIFF_VERIFIED" "$ARTIFACT_VERIFIED" "$TTL_MS" <<'PY'
import glob
import json
import os
import re
import sys

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

now_ms = int(now_s)
SECRET_RE = re.compile(
    r"BEGIN [A-Z ]*PRIVATE KEY|sk-ant-[A-Za-z0-9_-]{10,}|gh[pousr]_[A-Za-z0-9_]{16,}|"
    r"github_pat_[A-Za-z0-9_]{16,}|sk_(?:live|test)_[A-Za-z0-9]{16,}|"
    r"dp\.(?:pt|st|sa|ct)\.[A-Za-z0-9_-]{20,}|AKIA[0-9A-Z]{16}"
)
SATURATION_RE = re.compile(
    r"\b(?:429|529|503)\b|rate[-_ ]?limit|resource[-_ ]?exhausted|overloaded|quota[-_ ]?exceeded|capacity|too many requests",
    re.IGNORECASE,
)
IN_BAND_NUDGE_HARNESSES = {"claude", "codex", "antigravity"}
FALLBACK_GRAPH = {
    "cheap": None,
    "standard": "cheap",
    "strong": None,
    "advisor": "strong",
    "inherit": None,
}

for val in (seat_id, role, artifact_path):
    if val and SECRET_RE.search(val):
        sys.stderr.write("seat-liveness: secret redaction violation in metadata field\n")
        sys.exit(2)


def safe_seat_file(sid: str) -> str:
    clean = re.sub(r"[^A-Za-z0-9._-]", "_", sid)
    if not clean:
        sys.stderr.write("seat-liveness: invalid --seat id\n")
        sys.exit(2)
    return os.path.join(seats_dir, f"{clean}.json")


def write_seat(path: str, data: dict) -> None:
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)
        f.write("\n")
    os.replace(tmp, path)


def read_seat(path: str) -> dict:
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


if subcmd == "init":
    if not seat_id:
        sys.stderr.write("seat-liveness init: --seat required\n")
        sys.exit(2)
    idle_ms = int(idle_timeout_s)
    deadline_delta = int(deadline_s)
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
        "attempt": 0,
        "status": "running",
        "classification": "alive",
        "artifact_path": artifact_path,
        "updated_at": now_ms,
    }
    write_seat(safe_seat_file(seat_id), record)
    print(f"SOLEUR_SEAT_LIVENESS seat={seat_id} status=alive action=init")

elif subcmd == "heartbeat":
    if not seat_id:
        sys.stderr.write("seat-liveness heartbeat: --seat required\n")
        sys.exit(2)
    p = safe_seat_file(seat_id)
    rec = read_seat(p)
    rec["last_progress_at"] = max(int(rec.get("last_progress_at", now_ms)), now_ms)
    rec["updated_at"] = now_ms
    write_seat(p, rec)
    print(f"SOLEUR_SEAT_LIVENESS seat={seat_id} status={rec.get('classification', 'alive')} action=heartbeat")

elif subcmd == "sweep":
    paths = [safe_seat_file(seat_id)] if seat_id else sorted(glob.glob(os.path.join(seats_dir, "*.json")))
    exited = exited_s.lower() == "true"
    exit_code = int(exit_code_s)
    hook_deferred = hook_deferred_s.lower() == "true"

    for p in paths:
        if not os.path.exists(p):
            continue
        rec = read_seat(p)
        sid = rec["seat_id"]
        art = rec.get("artifact_path", "")
        art_ok = True
        if art:
            art_ok = os.path.isfile(art) and os.path.getsize(art) > 0
        floor_ok = True if floor_passed_s == "" else (floor_passed_s.lower() == "true")

        clean_done = exited and exit_code == 0 and art_ok and floor_ok

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
                rec["status"] = "completed"
        else:
            idle_elapsed = now_ms - int(rec["last_progress_at"])
            total_elapsed = now_ms - int(rec["started_at"])
            idle_limit = int(rec["idle_timeout_ms"])
            if idle_elapsed > idle_limit:
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
    if not seat_id:
        sys.stderr.write("seat-liveness decide: --seat required\n")
        sys.exit(2)
    p = safe_seat_file(seat_id)
    rec = read_seat(p)
    sid = rec["seat_id"]
    cls = rec.get("classification", "alive")
    writable = bool(rec.get("writable", False))
    side_fx = bool(rec.get("side_effecting", False))
    attempt = int(rec.get("attempt", 0))
    h = rec.get("harness", "unknown")
    t = rec.get("tier", "inherit")

    dirty_diff = dirty_diff_s.lower() == "true"
    diff_verified = None if diff_verified_s == "" else (diff_verified_s.lower() == "true")
    art_verified = artifact_verified_s.lower() == "true"

    action = "none"
    fb_tier = "none"
    rcov = "full"

    if cls in ("alive", "legit_long_turn"):
        action = "none"
        rcov = "full"
    elif art_verified or (writable and dirty_diff and diff_verified is True):
        action = "accept"
        rec["status"] = "recovered"
        rcov = "full"
    elif writable and dirty_diff:
        if diff_verified is None:
            action = "verify_disk"
            rcov = "degraded"
        else:
            action = "escalate"
            rec["status"] = "escalated"
            rcov = "degraded"
    elif side_fx:
        action = "escalate"
        rec["status"] = "escalated"
        rcov = "degraded"
    elif attempt >= 1:
        action = "escalate"
        rec["status"] = "escalated"
        rcov = "degraded"
    else:
        if h in IN_BAND_NUDGE_HARNESSES and cls in ("hook_deferred", "truncated"):
            action = "nudge"
            attempt += 1
            rec["attempt"] = attempt
            rec["status"] = "recovered"
            rcov = "full"
        else:
            action = "respawn"
            attempt += 1
            rec["attempt"] = attempt
            rec["status"] = "recovered"
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
    ttl_ms = int(ttl_s)
    removed = 0
    retained = 0
    for p in sorted(glob.glob(os.path.join(seats_dir, "*.json"))):
        try:
            rec = read_seat(p)
            last_ts = int(rec.get("last_progress_at") or rec.get("started_at") or 0)
            if now_ms - last_ts > ttl_ms:
                os.remove(p)
                removed += 1
            else:
                retained += 1
        except Exception:
            retained += 1
    print(f"SOLEUR_SEAT_LIVENESS_CLEANUP removed={removed} retained={retained}")

else:
    sys.stderr.write(f"seat-liveness: unknown subcommand '{subcmd}'\n")
    sys.exit(2)
PY
