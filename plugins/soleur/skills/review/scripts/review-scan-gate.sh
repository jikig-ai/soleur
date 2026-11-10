#!/usr/bin/env bash
# Orchestrator scan receipt. Stdout is the status line, then file:line rule-id.
# A temp dir, when one is needed, lives under mktemp and is removed on every return.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../../../.." && pwd)"
ENSURE="$SCRIPT_DIR/ensure-semgrep.sh"
TMP=""

cleanup() {
  if [ -n "$TMP" ]; then
    rm -rf "$TMP"
    TMP=""
  fi
}
trap cleanup EXIT INT TERM

refuse() {
  echo "SOLEUR_REVIEW_SCAN_GATE refuse engine=${1:-none} files=${2:-0} rules=${3:-0} findings=${4:-0}"
  exit 1
}

if [ "${1:-}" = "--probe" ]; then
  echo "SOLEUR_REVIEW_SCAN_GATE probe"
  exit 0
fi

is_lock() {
  case "$(basename -- "$1")" in
    package-lock.json|bun.lock|yarn.lock|Cargo.lock|go.sum|Gemfile.lock|poetry.lock|uv.lock) return 0 ;;
    *) return 1 ;;
  esac
}

kind_of() {
  local base
  base="$(basename -- "$1")"
  case "$base" in
    *.sh|*.bash|*.zsh) printf 'shell\n'; return ;;
  esac
  case "$base" in
    *.py|*.js|*.jsx|*.ts|*.tsx|*.mjs|*.cjs|*.rb|*.go|*.java|*.rs|*.swift|*.kt|*.kts|*.c|*.cc|*.cpp|*.h|*.hpp|*.cs|*.php|*.scala)
      printf 'source\n'
      return
      ;;
  esac
  printf 'other\n'
}

is_test_path() {
  case "$1" in
    test/*|*/test/*) return 0 ;;
    *) return 1 ;;
  esac
}

line_copied_from_target() {
  local line="$1" f
  shift
  for f in "$@"; do
    [ -f "$f" ] || continue
    if grep -Fxq -- "$line" "$f"; then
      return 0
    fi
  done
  return 1
}

summary_rules() {
  local err="$1" rules=0 line n
  shift
  while IFS= read -r line || [ -n "$line" ]; do
    if [[ "$line" =~ ^Ran[[:space:]]([0-9]+)[[:space:]]rules?[[:space:]]on[[:space:]]([0-9]+)[[:space:]]files? ]]; then
      n="${BASH_REMATCH[1]}"
      if line_copied_from_target "$line" "$@"; then
        continue
      fi
      if [ "${BASH_REMATCH[2]}" -eq 0 ]; then
        continue
      fi
      rules="$n"
    fi
  done <"$err"
  printf '%s\n' "$rules"
}

sources=()
shells=()
for path in "$@"; do
  [ -f "$path" ] || continue
  if is_lock "$path"; then
    continue
  fi
  case "$(kind_of "$path")" in
    source) sources+=("$path") ;;
    shell) shells+=("$path") ;;
    *) ;;
  esac
done

files=$(( ${#sources[@]} + ${#shells[@]} ))

if [ "$files" -eq 0 ]; then
  echo "SOLEUR_REVIEW_SCAN_GATE skip engine=none files=0 rules=0 findings=0"
  exit 0
fi

if [ "${#sources[@]}" -gt 0 ] && [ "${#shells[@]}" -gt 0 ]; then
  engine="mixed"
elif [ "${#sources[@]}" -gt 0 ]; then
  engine="semgrep"
else
  engine="shellcheck"
fi

TMP="$(mktemp -d)"
rules=0
findings=0
finding_lines=()

if [ "${#sources[@]}" -gt 0 ]; then
  if ! bash "$ENSURE" >/dev/null 2>&1; then
    refuse "$engine" "$files" 0 0
  fi
  map="$TMP/map.tsv"
  : >"$map"
  scan_args=()
  need_ignore=0
  idx=0
  for src in "${sources[@]}"; do
    if is_test_path "$src"; then
      need_ignore=1
      ext="${src##*.}"
      copy="$TMP/scan/$idx.$ext"
      mkdir -p "$TMP/scan"
      cp -- "$src" "$copy"
      printf '%s\t%s\n' "$copy" "$src" >>"$map"
      scan_args+=("$copy")
      idx=$((idx + 1))
    else
      printf '%s\t%s\n' "$src" "$src" >>"$map"
      scan_args+=("$src")
    fi
  done
  if [ "$need_ignore" -eq 1 ]; then
    : >"$TMP/scan/.semgrepignore"
  fi
  sem_args=(
    --config=auto
    --config=p/javascript
    --config=p/typescript
    --config=p/owasp-top-ten
    --config=plugins/soleur/skills/review/references/semgrep-custom-rules.yaml
    --json
    --error
  )
  if [ "$need_ignore" -eq 1 ]; then
    sem_args+=(--no-git-ignore)
  fi
  out="$TMP/sem.json"
  err="$TMP/sem.err"
  attempt=0
  sem_rc=0
  while [ "$attempt" -lt 2 ]; do
    attempt=$((attempt + 1))
    if [ "$attempt" -eq 2 ]; then
      ( cd "$ROOT" && EIO_BACKEND=posix semgrep -j 1 "${sem_args[@]}" "${scan_args[@]}" >"$out" 2>"$err" )
    else
      ( cd "$ROOT" && semgrep "${sem_args[@]}" "${scan_args[@]}" >"$out" 2>"$err" )
    fi
    sem_rc=$?
    if [ "$attempt" -eq 1 ] && grep -q 'io_uring_queue_init: Cannot allocate memory' "$err"; then
      continue
    fi
    break
  done
  if [ "$sem_rc" -ne 0 ] && [ "$sem_rc" -ne 1 ]; then
    refuse "$engine" "$files" 0 0
  fi
  rules="$(summary_rules "$err" "${sources[@]}")"
  if [ "$rules" -eq 0 ]; then
    refuse "$engine" "$files" 0 0
  fi
  parsed="$TMP/parsed.txt"
  if ! python3 - "$out" "$map" >"$parsed" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
mapping = {}
for raw in open(sys.argv[2]):
    raw = raw.rstrip("\n")
    if not raw:
        continue
    src, orig = raw.split("\t", 1)
    mapping[src] = orig
paths = data.get("paths") or {}
scanned = paths.get("scanned") or []
print("SCANNED")
for item in scanned:
    print(mapping.get(item, item))
print("FINDINGS")
for row in data.get("results") or []:
    path = mapping.get(row.get("path", ""), row.get("path", ""))
    start = row.get("start") or {}
    line = start.get("line", 0)
    rule = row.get("check_id") or "unknown"
    print(f"{path}:{line} {rule}")
PY
  then
    refuse "$engine" "$files" 0 0
  fi
  mode="wait"
  scanned_tmp="$TMP/scanned.list"
  : >"$scanned_tmp"
  while IFS= read -r row || [ -n "$row" ]; do
    if [ "$row" = "SCANNED" ]; then
      mode="scanned"
      continue
    fi
    if [ "$row" = "FINDINGS" ]; then
      mode="findings"
      continue
    fi
    if [ "$mode" = "scanned" ]; then
      printf '%s\n' "$row" >>"$scanned_tmp"
    elif [ "$mode" = "findings" ] && [ -n "$row" ]; then
      finding_lines+=("$row")
      findings=$((findings + 1))
    fi
  done <"$parsed"
  for src in "${sources[@]}"; do
    if ! grep -Fxq -- "$src" "$scanned_tmp"; then
      refuse "$engine" "$files" "$rules" 0
    fi
  done
  scanned_n="$(grep -c . "$scanned_tmp" || true)"
  if [ "$scanned_n" -ne "${#sources[@]}" ]; then
    refuse "$engine" "$files" "$rules" 0
  fi
fi

if [ "${#shells[@]}" -gt 0 ]; then
  if ! command -v shellcheck >/dev/null 2>&1; then
    refuse "$engine" "$files" "$rules" 0
  fi
  sh_out="$TMP/sh.json"
  sh_err="$TMP/sh.err"
  shellcheck -f json "${shells[@]}" >"$sh_out" 2>"$sh_err"
  sh_rc=$?
  if [ "$sh_rc" -ne 0 ] && [ "$sh_rc" -ne 1 ]; then
    refuse "$engine" "$files" "$rules" 0
  fi
  sh_parsed="$TMP/sh-parsed.txt"
  if ! python3 - "$sh_out" >"$sh_parsed" <<'PY'
import json, sys
rows = json.load(open(sys.argv[1]))
for row in rows:
    code = row.get("code")
    rule = f"SC{code}" if isinstance(code, int) else str(code)
    print(f"{row.get('file')}:{row.get('line')} {rule}")
PY
  then
    refuse "$engine" "$files" "$rules" 0
  fi
  while IFS= read -r row || [ -n "$row" ]; do
    [ -n "$row" ] || continue
    finding_lines+=("$row")
    findings=$((findings + 1))
  done <"$sh_parsed"
fi

echo "SOLEUR_REVIEW_SCAN_GATE ok engine=${engine} files=${files} rules=${rules} findings=${findings}"
if [ "${#finding_lines[@]}" -gt 0 ]; then
  printf '%s\n' "${finding_lines[@]}"
fi
exit 0
