# shellcheck shell=bash
# The write chokepoint. Every byte that reaches the report goes through lc_emit_checked.
# Requires SKILL_DIR and PLUGIN_DIR. Test seams: LAUNCH_CHECK_REDACT_SENTINEL, LAUNCH_CHECK_GITLEAKS.
source "$SKILL_DIR/scripts/lib/common.sh"

# lc_preflight_scanners: the redaction layers must be runnable before anything is read or written.
lc_preflight_scanners() {
  local gl=${LAUNCH_CHECK_GITLEAKS:-gitleaks}
  command -v "$gl" >/dev/null 2>&1 || lc_abort scanner-missing 2 "install gitleaks (macOS: brew install gitleaks; Linux: your package manager or mise use gitleaks)"
  "$gl" version >/dev/null 2>&1 || lc_abort scanner-failed 2 "gitleaks is on PATH but not runnable"
}

# lc_emit_checked <src-file> <dest-path> <dry-run 0|1>: scan the exact bytes, then write them or write nothing.
# The body runs in a subshell so its EXIT trap owns the scratch directory and the destination temp file on
# every path (including lc_abort's exit) without replacing the caller's own trap.
lc_emit_checked() {
  local rc=0
  ( lc__emit_body "$@" ) || rc=$?
  [ "$rc" -eq 0 ] || exit "$rc"
}

lc__emit_body() {
  local src=$1 dest=$2 dry=${3:-0} gl=${LAUNCH_CHECK_GITLEAKS:-gitleaks} scratch tmp="" s_rc=0 g_rc=0 destdir
  local REDACT_SENTINEL=${LAUNCH_CHECK_REDACT_SENTINEL:-$PLUGIN_DIR/skills/incident/scripts/redact-sentinel.sh}
  command -v "$gl" >/dev/null 2>&1 || lc_abort scanner-missing 2 "gitleaks not found"
  scratch=$(mktemp -d "${TMPDIR:-/tmp}/lc-gate.XXXXXX") || lc_abort scanner-failed 2 "mktemp failed"
  trap 'rm -rf -- "${scratch:?}"; [ -z "$tmp" ] || rm -f -- "$tmp"' EXIT
  bash "$REDACT_SENTINEL" "$src" >/dev/null 2>&1 || s_rc=$?
  [ "$s_rc" -eq 1 ] && lc_abort redaction-hit 1 "layer=sentinel"
  [ "$s_rc" -eq 0 ] || lc_abort scanner-failed 2 "sentinel rc=$s_rc"
  "$gl" detect --source "$src" --no-git --report-format json --report-path "$scratch/r.json" --redact --exit-code 1 >/dev/null 2>"$scratch/e" || g_rc=$?
  if [ "$g_rc" -eq 1 ] && grep -q '"RuleID"' "$scratch/r.json" 2>/dev/null; then lc_abort redaction-hit 1 "layer=gitleaks"; fi
  [ "$g_rc" -eq 0 ] || lc_abort scanner-failed 2 "gitleaks rc=$g_rc"
  [ "$dry" = 1 ] && return 0
  destdir=$(dirname "$dest")
  mkdir -p "$destdir" || lc_abort write-failed 2 "mkdir"
  tmp=$(mktemp "$destdir/.launch-check.XXXXXX") || lc_abort write-failed 2 "mktemp"
  cp "$src" "$tmp" && cmp -s "$src" "$tmp" && mv -f "$tmp" "$dest" && tmp="" && return 0
  lc_abort write-failed 2 "copy"
}
