#!/usr/bin/env bash
# run-health-emit.sh — upsert a phase entry into run_health.json + snapshot prompt text.
# Usage:
#   run-health-emit.sh --discover
#   run-health-emit.sh --run-dir <dir> --status <completed|failed|budget-capped> --seal
#                      [--session-state <path>] [--import-tally]
#   run-health-emit.sh --run-dir <dir> [--run-id <id>] [--issue <N>] [--branch <b>] [--harness <h>]
#                     --phase <name> --status <token>
#                     [--prompt-file <path>] [--error <msg>] [--reviewed-coverage <v>] [--seal]
# Idempotent: re-invoking with the same phase updates the existing entry rather than duplicating.
# --seal sets sealed only with a terminal status. A phase name never seals by itself.
# Storage is under .soleur/runs/<run-id>/ (gitignored). Emission failures are non-fatal: the
# script exits 0 on best-effort write errors after printing a warning to stderr.
set -u

unset SOLEUR_RUN_HEALTH_SEAL SOLEUR_RUN_HEALTH_SESSION_STATE \
  SOLEUR_RUN_HEALTH_IMPORT_TALLY SOLEUR_RUN_HEALTH_TALLY_SHOW

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
SEAL=0
IMPORT_TALLY=0
SESSION_STATE=""
DISCOVER=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --run-dir) [[ $# -ge 2 ]] || { echo "run-health-emit: --run-dir requires a value" >&2; exit 0; }; RUN_DIR="$2"; shift 2 ;;
    --run-id) [[ $# -ge 2 ]] || { echo "run-health-emit: --run-id requires a value" >&2; exit 0; }; RUN_ID="$2"; shift 2 ;;
    --issue) [[ $# -ge 2 ]] || { echo "run-health-emit: --issue requires a value" >&2; exit 0; }; ISSUE="$2"; shift 2 ;;
    --branch) [[ $# -ge 2 ]] || { echo "run-health-emit: --branch requires a value" >&2; exit 0; }; BRANCH="$2"; shift 2 ;;
    --harness) [[ $# -ge 2 ]] || { echo "run-health-emit: --harness requires a value" >&2; exit 0; }; HARNESS="$2"; shift 2 ;;
    --phase) [[ $# -ge 2 ]] || { echo "run-health-emit: --phase requires a value" >&2; exit 0; }; PHASE="$2"; shift 2 ;;
    --status) [[ $# -ge 2 ]] || { echo "run-health-emit: --status requires a value" >&2; exit 0; }; STATUS="$2"; shift 2 ;;
    --prompt-file) [[ $# -ge 2 ]] || { echo "run-health-emit: --prompt-file requires a value" >&2; exit 0; }; PROMPT_FILE="$2"; shift 2 ;;
    --error) [[ $# -ge 2 ]] || { echo "run-health-emit: --error requires a value" >&2; exit 0; }; ERROR_MSG="$2"; shift 2 ;;
    --reviewed-coverage) [[ $# -ge 2 ]] || { echo "run-health-emit: --reviewed-coverage requires a value" >&2; exit 0; }; REVIEWED_COVERAGE="$2"; shift 2 ;;
    --session-state) [[ $# -ge 2 ]] || { echo "run-health-emit: --session-state requires a value" >&2; exit 0; }; SESSION_STATE="$2"; shift 2 ;;
    --seal) SEAL=1; shift ;;
    --import-tally) IMPORT_TALLY=1; shift ;;
    --discover) DISCOVER=1; shift ;;
    *) echo "run-health-emit: unknown arg $1" >&2; shift ;;
  esac
done

if [[ "$DISCOVER" == "1" ]]; then
  d="$(mktemp -d -t runhealth-discover.XXXXXXXX)" || { echo "run-health-emit: mktemp failed" >&2; exit 0; }
  printf 'discover\n' > "$d/prompt.md"
  bash "$0" --run-dir "$d/run" --phase 0 --status started --prompt-file "$d/prompt.md" >/dev/null
  bash "$0" --run-dir "$d/run" --status completed --seal >/dev/null
  if python3 - "$d/run/run_health.json" <<'PY'
import json, sys
try:
    data = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(1)
ok = (
    data.get("sealed") is True
    and data.get("schema_version") == 1
    and len(data.get("phases") or []) == 1
)
sys.exit(0 if ok else 1)
PY
  then
    echo ok
  else
    echo "run-health-emit: discover failed" >&2
  fi
  rm -rf "$d"
  exit 0
fi

# Refuse before mkdir. A Python-only check would already have created the directory,
# and the heredoc discards Python stderr.
if [[ -n "$PHASE" ]]; then
  if [[ "$PHASE" == "." || "$PHASE" == ".." || "$PHASE" == *..* || ! "$PHASE" =~ ^[A-Za-z0-9._-]+$ ]]; then
    echo "run-health-emit: refused phase token" >&2
    exit 0
  fi
fi

if [[ "$SEAL" == "1" ]]; then
  if [[ -z "$RUN_DIR" || -z "$STATUS" ]]; then
    echo "run-health-emit: --run-dir and --status required with --seal" >&2
    exit 0
  fi
elif [[ -z "$RUN_DIR" || -z "$PHASE" || -z "$STATUS" ]]; then
  echo "run-health-emit: --run-dir, --phase, --status required" >&2
  exit 0
fi

TALLY_SHOW=""
if [[ "$IMPORT_TALLY" == "1" ]]; then
  # A stub earlier on PATH still wins. The sibling script is the fallback.
  _tally_dir="$(cd "$(dirname "$0")" && pwd)"
  TALLY_SHOW="$(PATH="${PATH}:${_tally_dir}" pipeline-tally.sh show 2>/dev/null)" || TALLY_SHOW=""
fi

mkdir -p "$RUN_DIR/phase_prompts" 2>/dev/null || { echo "run-health-emit: cannot create $RUN_DIR" >&2; exit 0; }

HEALTH="$RUN_DIR/run_health.json"
NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Resolve run metadata: prefer existing file, then args, then defaults.
if [[ -z "$RUN_ID" ]]; then
  if [[ -f "$HEALTH" ]]; then
    RUN_ID="$(python3 -c "import json,sys;print(json.load(open(sys.argv[1])).get('run_id',''))" "$HEALTH" 2>/dev/null)" || RUN_ID=""
  fi
  [[ -z "$RUN_ID" ]] && RUN_ID="$(basename "$RUN_DIR")"
fi
[[ -z "$BRANCH" ]] && BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)"
[[ -z "$ISSUE" ]] && ISSUE=""

SOLEUR_RUN_HEALTH_SEAL="$SEAL" \
SOLEUR_RUN_HEALTH_SESSION_STATE="$SESSION_STATE" \
SOLEUR_RUN_HEALTH_IMPORT_TALLY="$IMPORT_TALLY" \
SOLEUR_RUN_HEALTH_TALLY_SHOW="$TALLY_SHOW" \
python3 - "$HEALTH" "$RUN_ID" "$ISSUE" "$BRANCH" "$HARNESS" "$PHASE" "$STATUS" "$NOW" "$ERROR_MSG" "$REVIEWED_COVERAGE" "$PROMPT_FILE" "$RUN_DIR" <<'PY' 2>/dev/null || echo "run-health-emit: python write failed (non-fatal)" >&2
import json, os, sys, shutil

(health, run_id, issue, branch, harness, phase, status, now, err, rcov, prompt_file, run_dir) = sys.argv[1:13]
seal = os.environ.get("SOLEUR_RUN_HEALTH_SEAL", "") == "1"
session_state = os.environ.get("SOLEUR_RUN_HEALTH_SESSION_STATE", "")
import_tally = os.environ.get("SOLEUR_RUN_HEALTH_IMPORT_TALLY", "") == "1"
tally_show = os.environ.get("SOLEUR_RUN_HEALTH_TALLY_SHOW", "")
terminal = ("completed", "failed", "budget-capped")

def goto_count(path):
    if not path or not os.path.isfile(path):
        return 0
    n = 0
    try:
        with open(path) as handle:
            for line in handle:
                if line.rstrip("\r\n") == "verb: goto":
                    n += 1
    except OSError:
        return 0
    return n

data = {}
if os.path.exists(health):
    try:
        with open(health) as f:
            data = json.load(f)
    except Exception:
        data = {}

was_sealed = bool(data.get("sealed"))
saved_status = data.get("status")
saved_completed = data.get("completed_at")

data["schema_version"] = 1
data.setdefault("run_id", run_id)
data.setdefault("issue", issue)
data.setdefault("branch", branch)
data.setdefault("harness", harness)
data.setdefault("started_at", now)
data.setdefault("phases", [])
data.setdefault("errors", [])
data.setdefault("sealed", False)
if rcov:
    data["reviewed_coverage"] = rcov

if phase:
    entry = None
    for p in data["phases"]:
        if p.get("phase") == phase:
            entry = p
            break
    if entry is None:
        entry = {"phase": phase, "started_at": now}
        data["phases"].append(entry)
    entry["status"] = status
    if status in terminal:
        entry["ended_at"] = now
    elif "started_at" not in entry:
        entry["started_at"] = now
    if err:
        entry.setdefault("errors", []).append({"at": now, "msg": err})
        data["errors"].append({"phase": phase, "at": now, "msg": err})
    if prompt_file and os.path.exists(prompt_file):
        pp_dir = os.path.join(run_dir, "phase_prompts")
        os.makedirs(pp_dir, exist_ok=True)
        base = os.path.join(pp_dir, "%s.md" % phase)
        if os.path.exists(base):
            n = 2
            while os.path.exists(os.path.join(pp_dir, "%s.attempt-%d.md" % (phase, n))):
                n += 1
            dest = os.path.join(pp_dir, "%s.attempt-%d.md" % (phase, n))
        else:
            dest = base
        shutil.copyfile(prompt_file, dest)
        entry["prompt_snapshot"] = os.path.relpath(dest, run_dir)

if (not was_sealed) and seal and status in terminal:
    data["sealed"] = True
    data["completed_at"] = now
    data["status"] = status
if was_sealed:
    data["sealed"] = True
    if saved_completed is not None:
        data["completed_at"] = saved_completed
    if saved_status is not None:
        data["status"] = saved_status
if seal:
    data["goto_count"] = goto_count(session_state)
    if import_tally:
        data["tally_show"] = tally_show

tmp = health + ".tmp"
with open(tmp, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
os.replace(tmp, health)
PY

exit 0
