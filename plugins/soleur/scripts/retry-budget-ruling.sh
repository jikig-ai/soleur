#!/usr/bin/env bash
#
# Parse one retry-budget ruling line and append a fixed ledger section.
# Identity, then a spent spawn bit, then --not-capped, then empty history,
# then at most 64 stdin bytes. The parent branches on the verdict line.

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
not_capped=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --not-capped)
      not_capped=1
      shift
      ;;
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
leaf="${ledger##*/}"
if [[ -z "$top" || "$parent" == "$ledger" || "$base" != "$branch" || "$leaf" != "session-state.md" || "$ledger" != "$top/"* || ! -d "$parent" ]]; then
  emit fail identity 1
  exit 2
fi
case "$ledger" in
  ..|../*|*/..|*/../*)
    emit fail identity 1
    exit 2
    ;;
esac
case "$toplevel" in
  ..|../*|*/..|*/../*)
    emit fail identity 1
    exit 2
    ;;
esac

field_rc=0
python3 - "$branch" "$toplevel" "$git_common" "$ledger" "$child_session" "$phase_flag" <<'PY' || field_rc=$?
import sys

for field in sys.argv[1:]:
    raw = field.encode("utf-8", "surrogateescape")
    if any(byte < 32 or byte == 127 for byte in raw):
        sys.exit(1)
    if "\u2028" in field or "\u2029" in field or "\u0085" in field:
        sys.exit(1)
    if "ruling_grant" in field or "ruling_spawn" in field:
        sys.exit(1)
    if field.splitlines() != ([field] if field else []):
        sys.exit(1)
sys.exit(0)
PY
if [[ "$field_rc" -ne 0 ]]; then
  emit fail identity 1
  exit 2
fi

if [[ -L "$ledger" ]]; then
  emit fail identity 1
  exit 2
fi

real_top=$(realpath -e -- "$top" 2>/dev/null) || {
  emit fail identity 1
  exit 2
}
real_parent=$(realpath -e -- "$parent" 2>/dev/null) || {
  emit fail identity 1
  exit 2
}
case "$real_parent/" in
  "$real_top"/*) ;;
  *)
    emit fail identity 1
    exit 2
    ;;
esac

line_used() {
  python3 - "$1" <<'PY'
import sys
try:
    data = open(sys.argv[1], "rb").read()
except OSError:
    sys.exit(3)
sys.exit(0 if b"ruling_spawn: used" in data.splitlines() else 1)
PY
}

if [[ -f "$ledger" && -s "$ledger" ]]; then
  spent_rc=0
  line_used "$ledger" || spent_rc=$?
  if [[ "$spent_rc" -eq 0 ]]; then
    emit fail spent 0
    exit 2
  fi
  if [[ "$spent_rc" -ne 1 ]]; then
    emit fail identity 1
    exit 2
  fi
fi

append_section() {
  local verb="$1" reason="$2" phase="$3" spawn="$4"
  local py_rc=0
  # Exclusive lock on the ledger inode for up to 5s, then append. A replace
  # would drop a concurrent append, including the spawn bit.
  SOLEUR_RULING_LEDGER="$ledger" \
    SOLEUR_RULING_BRANCH="$branch" \
    SOLEUR_RULING_TOPLEVEL="$toplevel" \
    SOLEUR_RULING_GIT_COMMON="$git_common" \
    SOLEUR_RULING_VERB="$verb" \
    SOLEUR_RULING_PHASE="$phase" \
    SOLEUR_RULING_REASON="$reason" \
    SOLEUR_RULING_CHILD="$child_session" \
    SOLEUR_RULING_SPAWN="$spawn" \
    python3 - <<'PY' || py_rc=$?
import os
import sys
import time

import fcntl

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
try:
    fd = os.open(ledger, os.O_RDWR | os.O_CREAT | os.O_APPEND, 0o644)
except OSError:
    sys.exit(2)
deadline = time.monotonic() + 5
while True:
    try:
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        break
    except BlockingIOError:
        if time.monotonic() >= deadline:
            os.close(fd)
            sys.exit(2)
        time.sleep(0.02)
try:
    os.lseek(fd, 0, os.SEEK_SET)
    chunks = []
    while True:
        block = os.read(fd, 65536)
        if not block:
            break
        chunks.append(block)
    if b"ruling_spawn: used" in b"".join(chunks).splitlines():
        sys.exit(4)
    payload = text.encode("utf-8")
    view = payload
    while view:
        wrote = os.write(fd, view)
        if wrote <= 0:
            sys.exit(2)
        view = view[wrote:]
except OSError:
    sys.exit(2)
finally:
    os.close(fd)
PY
  return "$py_rc"
}

append_or_spent() {
  local rc=0
  append_section "$@" || rc=$?
  if [[ "$rc" -eq 4 ]]; then
    emit fail spent 0
    exit 2
  fi
  if [[ "$rc" -ne 0 ]]; then
    emit fail identity 1
    exit 2
  fi
}

if [[ "$not_capped" -eq 1 ]]; then
  append_or_spent fail not-capped "$phase_flag" 0
  emit fail not-capped 1
  exit 2
fi

hist_nonempty=0
if [[ -n "$history" && -f "$history" && -s "$history" ]]; then
  hist_nonempty=1
fi
ledger_present=0
if [[ -f "$ledger" && -s "$ledger" ]]; then
  ledger_present=1
fi

if [[ "$hist_nonempty" -eq 0 || "$ledger_present" -eq 0 ]]; then
  append_or_spent fail empty-history "$phase_flag" 0
  emit fail empty-history 1
  exit 2
fi

raw="$(mktemp)"
trap 'rm -f "$raw"' EXIT
dd_rc=0
dd if=/dev/stdin of="$raw" bs=1 count=64 status=none || dd_rc=$?
if [[ "$dd_rc" -ne 0 && ! -s "$raw" ]]; then
  append_or_spent fail unparseable "$phase_flag" 1
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
    append_or_spent continue ok "$phase_flag" 1
    emit continue ok 0
    exit 0
    ;;
  goto)
    append_or_spent goto ok "$phase_tok" 1
    printf 'SOLEUR_RETRY_BUDGET_RULING verb=goto reason=ok phase=%s\n' "$phase_tok"
    exit 0
    ;;
  fail)
    append_or_spent fail fail "$phase_flag" 1
    emit fail fail 1
    exit 2
    ;;
  empty)
    append_or_spent fail empty "$phase_flag" 1
    emit fail empty 1
    exit 2
    ;;
  *)
    append_or_spent fail unparseable "$phase_flag" 1
    emit fail unparseable 1
    exit 2
    ;;
esac
