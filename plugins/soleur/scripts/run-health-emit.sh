#!/usr/bin/env bash
# run-health-emit.sh — upsert a phase entry into run_health.json + snapshot prompt text.
# Usage:
#   run-health-emit.sh --run-dir <dir> [--run-id <id>] [--issue <N>] [--branch <b>] [--harness <h>]
#                     --phase <name> --status <started|completed|failed|budget-capped>
#                     [--prompt-file <path>] [--error <msg>] [--reviewed-coverage <v>]
# Idempotent: re-invoking with the same phase updates the existing entry rather than duplicating.
# Storage is under .soleur/runs/<run-id>/ (gitignored). Emission failures are non-fatal: the
# script exits 0 on best-effort write errors after printing a warning to stderr.
set -u

RUN_DIR=""
RUN_ID=""
ISSUE=""
BRANCH=""
HARNESS="${SOLEUR_HARNESS:-unknown}"
PHASE=""
STATUS=""
PROMPT_FILE=""
ERROR_MSG=""
REVIEWED_COVERAGE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --run-dir) RUN_DIR="$2"; shift 2 ;;
    --run-id) RUN_ID="$2"; shift 2 ;;
    --issue) ISSUE="$2"; shift 2 ;;
    --branch) BRANCH="$2"; shift 2 ;;
    --harness) HARNESS="$2"; shift 2 ;;
    --phase) PHASE="$2"; shift 2 ;;
    --status) STATUS="$2"; shift 2 ;;
    --prompt-file) PROMPT_FILE="$2"; shift 2 ;;
    --error) ERROR_MSG="$2"; shift 2 ;;
    --reviewed-coverage) REVIEWED_COVERAGE="$2"; shift 2 ;;
    *) echo "run-health-emit: unknown arg $1" >&2; shift ;;
  esac
done

if [[ -z "$RUN_DIR" || -z "$PHASE" || -z "$STATUS" ]]; then
  echo "run-health-emit: --run-dir, --phase, --status required" >&2
  exit 0
fi

mkdir -p "$RUN_DIR/phase_prompts" 2>/dev/null || { echo "run-health-emit: cannot create $RUN_DIR" >&2; exit 0; }

HEALTH="$RUN_DIR/run_health.json"
NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Resolve run metadata: prefer existing file, then args, then defaults.
if [[ -z "$RUN_ID" ]]; then
  if [[ -f "$HEALTH" ]]; then
    RUN_ID="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("run_id",""))' "$HEALTH" 2>/dev/null)"
  fi
  [[ -z "$RUN_ID" ]] && RUN_ID="$(basename "$RUN_DIR")"
fi
[[ -z "$BRANCH" ]] && BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)"
[[ -z "$ISSUE" ]] && ISSUE=""

python3 - "$HEALTH" "$RUN_ID" "$ISSUE" "$BRANCH" "$HARNESS" "$PHASE" "$STATUS" "$NOW" "$ERROR_MSG" "$REVIEWED_COVERAGE" "$PROMPT_FILE" "$RUN_DIR" <<'PY' 2>/dev/null || echo "run-health-emit: python write failed (non-fatal)" >&2
import json, os, re, sys, shutil

(health, run_id, issue, branch, harness, phase, status, now, err, rcov, prompt_file, run_dir) = sys.argv[1:13]

SECRET_RE = re.compile(
    r"BEGIN [A-Z ]*PRIVATE KEY|sk-ant-[A-Za-z0-9_-]{10,}|gh[pousr]_[A-Za-z0-9_]{16,}|"
    r"github_pat_[A-Za-z0-9_]{16,}|sk_(?:live|test)_[A-Za-z0-9]{16,}|"
    r"dp\.(?:pt|st|sa|ct)\.[A-Za-z0-9_-]{20,}|AKIA[0-9A-Z]{16}"
)

data = {}
if os.path.exists(health) and not os.path.islink(health):
    try:
        with open(health) as f:
            loaded = json.load(f)
            if isinstance(loaded, dict):
                data = loaded
    except Exception:
        data = {}

data.setdefault("run_id", run_id)
data.setdefault("issue", issue)
data.setdefault("branch", branch)
data.setdefault("harness", harness)
data.setdefault("started_at", now)
data.setdefault("phases", [])
data.setdefault("errors", [])
if rcov:
    data["reviewed_coverage"] = rcov

# Find existing phase entry.
entry = None
for p in data["phases"]:
    if p.get("phase") == phase:
        entry = p
        break
if entry is None:
    entry = {"phase": phase, "started_at": now}
    data["phases"].append(entry)

entry["status"] = status
if status in ("completed", "failed", "budget-capped"):
    entry["ended_at"] = now
elif "started_at" not in entry:
    entry["started_at"] = now

if err:
    clean_err = SECRET_RE.sub("[REDACTED]", err)
    clean_err = re.sub(r"[\x00-\x1f\x7f\u2028\u2029]", " ", clean_err)[:512]
    entry.setdefault("errors", []).append({"at": now, "msg": clean_err})
    data["errors"].append({"phase": phase, "at": now, "msg": clean_err})

# Seal completed_at only when status is a terminal run status.
if status in ("completed", "failed", "budget-capped"):
    if phase.lower() in ("8", "ship", "done", "final", "exit", "terminate"):
        data["completed_at"] = now
        data["status"] = status

# Snapshot prompt file (append-only per attempt).
if prompt_file and os.path.exists(prompt_file) and not os.path.islink(prompt_file):
    pp_dir = os.path.join(run_dir, "phase_prompts")
    os.makedirs(pp_dir, exist_ok=True)
    safe_phase = re.sub(r"[^A-Za-z0-9._-]", "_", phase) or "phase"
    base = os.path.join(pp_dir, f"{safe_phase}.md")
    if os.path.exists(base):
        n = 2
        while os.path.exists(os.path.join(pp_dir, f"{safe_phase}.attempt-{n}.md")):
            n += 1
        dest = os.path.join(pp_dir, f"{safe_phase}.attempt-{n}.md")
    else:
        dest = base
    shutil.copyfile(prompt_file, dest)
    entry["prompt_snapshot"] = os.path.relpath(dest, run_dir)

# Summarize per-seat liveness records when <run_dir>/seats/*.json exist (#12524).
seats_dir = os.path.join(run_dir, "seats")
if os.path.isdir(seats_dir) and not os.path.islink(seats_dir):
    total = 0
    active = 0
    completed = 0
    recovered = 0
    escalated = 0
    degraded = 0
    for name in sorted(os.listdir(seats_dir)):
        if not name.endswith(".json"):
            continue
        sp = os.path.join(seats_dir, name)
        if os.path.islink(sp):
            continue
        try:
            with open(sp) as sf:
                srec = json.load(sf)
            if not isinstance(srec, dict):
                continue
            total += 1
            st = srec.get("status", "running")
            if st == "running":
                if srec.get("recovery_action") in ("nudge", "respawn"):
                    recovered += 1
                else:
                    active += 1
            elif st == "completed":
                completed += 1
            elif st == "recovered":
                recovered += 1
            elif st == "escalated":
                escalated += 1
            if srec.get("reviewed_coverage") == "degraded":
                degraded += 1
        except Exception:
            continue
    data["seats_summary"] = {
        "total": total,
        "active": active,
        "completed": completed,
        "recovered": recovered,
        "escalated": escalated,
    }
    if (escalated > 0 or degraded > 0) and not rcov and data.get("reviewed_coverage") in (None, "", "full"):
        data["reviewed_coverage"] = "degraded"

# Write atomically with PID-scoped temp file.
tmp = f"{health}.{os.getpid()}.tmp"
try:
    with open(tmp, "w") as f:
        json.dump(data, f, indent=2)
        f.write("\n")
    os.replace(tmp, health)
finally:
    if os.path.exists(tmp):
        try:
            os.remove(tmp)
        except OSError:
            pass
PY

exit 0
