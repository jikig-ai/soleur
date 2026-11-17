#!/usr/bin/env bash
#
# Parse one retry-budget ruling line and append a fixed ledger section.
# Identity, then a spent spawn bit, then empty history, then at most 64
# stdin bytes. The parent branches on the verdict line, not on the status.

set -euo pipefail

emit() {
  local verb="$1" reason="$2" plain="$3"
  printf 'SOLEUR_RETRY_BUDGET_RULING verb=%s reason=%s\n' "$verb" "$reason"
  if [[ "$plain" == 1 ]]; then
    printf '%s %s\n' "$verb" "$reason"
  fi
}

for arg in "$@"; do
  if [[ "$arg" == "--probe" ]]; then
    printf '%s\n' ok
    exit 0
  fi
done

toplevel=""
branch=""
git_common=""
ledger=""
history=""
child_session=""
phase_flag=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --toplevel|--branch|--git-common-dir|--ledger|--history|--child-session|--phase|--evidence)
      if [[ $# -lt 2 ]]; then
        emit fail identity 1
        exit 2
      fi
      key="$1"
      val="$2"
      shift 2
      case "$key" in
        --toplevel) toplevel="$val" ;;
        --branch) branch="$val" ;;
        --git-common-dir) git_common="$val" ;;
        --ledger) ledger="$val" ;;
        --history) history="$val" ;;
        --child-session) child_session="$val" ;;
        --phase) phase_flag="$val" ;;
        --evidence) ;;
      esac
      ;;
    *)
      emit fail identity 1
      exit 2
      ;;
  esac
done

if [[ -z "$toplevel" || -z "$branch" || -z "$git_common" || -z "$ledger" ]]; then
  emit fail identity 1
  exit 2
fi

top="${toplevel%/}"
parent="${ledger%/*}"
base="${parent##*/}"
if [[ -z "$top" || "$parent" == "$ledger" || "$base" != "$branch" || "$ledger" != "$top/"* || ! -d "$parent" ]]; then
  emit fail identity 1
  exit 2
fi
case "$ledger" in
  *"/../"*|*/..)
    emit fail identity 1
    exit 2
    ;;
esac
case "${branch}${toplevel}${git_common}${child_session}${phase_flag}" in
  *$'\n'*|*$'\r'*|*ruling_grant*|*ruling_spawn*)
    emit fail identity 1
    exit 2
    ;;
esac

if [[ -f "$ledger" && -s "$ledger" ]]; then
  spent_rc=0
  python3 - "$ledger" <<'PY' || spent_rc=$?
import sys
try:
    data = open(sys.argv[1], "rb").read()
except OSError:
    sys.exit(3)
sys.exit(0 if b"ruling_spawn: used" in data else 1)
PY
  if [[ "$spent_rc" -eq 0 ]]; then
    emit fail spent 0
    exit 2
  fi
  if [[ "$spent_rc" -ne 1 ]]; then
    emit fail identity 1
    exit 2
  fi
fi

hist_nonempty=0
if [[ -n "$history" && -f "$history" && -s "$history" ]]; then
  hist_nonempty=1
fi
ledger_present=0
if [[ -f "$ledger" && -s "$ledger" ]]; then
  ledger_present=1
fi

append_section() {
  local verb="$1" reason="$2" phase="$3" spawn="$4"
  SOLEUR_RULING_LEDGER="$ledger" \
    SOLEUR_RULING_BRANCH="$branch" \
    SOLEUR_RULING_TOPLEVEL="$toplevel" \
    SOLEUR_RULING_GIT_COMMON="$git_common" \
    SOLEUR_RULING_VERB="$verb" \
    SOLEUR_RULING_PHASE="$phase" \
    SOLEUR_RULING_REASON="$reason" \
    SOLEUR_RULING_CHILD="$child_session" \
    SOLEUR_RULING_SPAWN="$spawn" \
    python3 - <<'PY'
import os
import sys
import tempfile

ledger = os.environ["SOLEUR_RULING_LEDGER"]
phase = os.environ["SOLEUR_RULING_PHASE"]
spawn = os.environ["SOLEUR_RULING_SPAWN"] == "1"
phase_line = "phase: " + phase if phase else "phase:"
lines = [
    "",
    "## Retry budget ruling",
    "",
    "branch: " + os.environ["SOLEUR_RULING_BRANCH"],
    "toplevel: " + os.environ["SOLEUR_RULING_TOPLEVEL"],
    "git-common-dir: " + os.environ["SOLEUR_RULING_GIT_COMMON"],
    "verb: " + os.environ["SOLEUR_RULING_VERB"],
    phase_line,
    "reason: " + os.environ["SOLEUR_RULING_REASON"],
    "child-session: " + os.environ["SOLEUR_RULING_CHILD"],
]
if spawn:
    lines.append("ruling_spawn: used")
lines.append("")
text = "\n".join(lines)
if "ruling_grant" in text:
    sys.exit(2)
parent = os.path.dirname(ledger)
fd, tmp = tempfile.mkstemp(prefix=".ruling.", dir=parent)
try:
    existing = b""
    if os.path.isfile(ledger):
        with open(ledger, "rb") as handle:
            existing = handle.read()
    if b"ruling_spawn: used" in existing:
        os.close(fd)
        os.unlink(tmp)
        sys.exit(4)
    with os.fdopen(fd, "wb") as out:
        out.write(existing)
        out.write(text.encode("utf-8"))
    os.replace(tmp, ledger)
except Exception:
    if os.path.exists(tmp):
        os.unlink(tmp)
    raise
PY
}

if [[ "$hist_nonempty" -eq 0 || "$ledger_present" -eq 0 ]]; then
  append_section fail empty-history "$phase_flag" 0
  emit fail empty-history 1
  exit 2
fi

raw="$(mktemp)"
trap 'rm -f "$raw"' EXIT
dd_rc=0
dd if=/dev/stdin of="$raw" bs=1 count=64 status=none || dd_rc=$?
if [[ "$dd_rc" -ne 0 && ! -s "$raw" ]]; then
  append_section fail unparseable "$phase_flag" 1
  emit fail unparseable 1
  exit 2
fi

parsed="$(python3 - "$raw" <<'PY'
import sys

data = open(sys.argv[1], "rb").read()

def classify(buf):
    if buf == b"":
        return "empty", ""
    for byte in buf:
        if (byte < 32 and byte != 10) or byte == 127:
            return "unparseable", ""
    newlines = buf.count(b"\n")
    if newlines > 1 or (newlines == 1 and not buf.endswith(b"\n")):
        return "unparseable", ""
    line = buf[:-1] if buf.endswith(b"\n") else buf
    if line in (b"continue", b"fail"):
        return line.decode("ascii"), ""
    if line.startswith(b"goto "):
        rest = line[5:]
        allowed = (b"plan", b"work", b"review", b"qa", b"test-fix-loop")
        if rest in allowed:
            return "goto", rest.decode("ascii")
    return "unparseable", ""

kind, phase = classify(data)
sys.stdout.write(kind + "\t" + phase)
PY
)"
kind="${parsed%%$'\t'*}"
phase_tok="${parsed#*$'\t'}"

case "$kind" in
  continue)
    append_section continue ok "$phase_flag" 1
    emit continue ok 0
    exit 0
    ;;
  goto)
    append_section goto ok "$phase_tok" 1
    emit goto ok 0
    exit 0
    ;;
  fail)
    append_section fail fail "$phase_flag" 1
    emit fail fail 1
    exit 2
    ;;
  empty)
    append_section fail empty "$phase_flag" 1
    emit fail empty 1
    exit 2
    ;;
  *)
    append_section fail unparseable "$phase_flag" 1
    emit fail unparseable 1
    exit 2
    ;;
esac
