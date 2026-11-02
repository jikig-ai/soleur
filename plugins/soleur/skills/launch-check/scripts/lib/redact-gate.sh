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
lc_emit_checked() {
  local src=$1 dest=$2 dry=${3:-0} gl=${LAUNCH_CHECK_GITLEAKS:-gitleaks} scratch s_rc=0 g_rc=0 destdir tmp
  local REDACT_SENTINEL=${LAUNCH_CHECK_REDACT_SENTINEL:-$PLUGIN_DIR/skills/incident/scripts/redact-sentinel.sh}
  command -v "$gl" >/dev/null 2>&1 || lc_abort scanner-missing 2 "gitleaks not found"
  scratch=$(mktemp -d "${TMPDIR:-/tmp}/lc-gate.XXXXXX") || lc_abort scanner-failed 2 "mktemp failed"
  bash "$REDACT_SENTINEL" "$src" >/dev/null 2>&1 || s_rc=$?
  if [ "$s_rc" -eq 1 ]; then rm -rf -- "${scratch:?}"; lc_abort redaction-hit 1 "layer=sentinel"; fi
  if [ "$s_rc" -ne 0 ]; then rm -rf -- "${scratch:?}"; lc_abort scanner-failed 2 "sentinel rc=$s_rc"; fi
  "$gl" detect --source "$src" --no-git --report-format json --report-path "$scratch/r.json" --redact --exit-code 1 >/dev/null 2>"$scratch/e" || g_rc=$?
  if [ "$g_rc" -eq 1 ] && grep -q '"RuleID"' "$scratch/r.json" 2>/dev/null; then rm -rf -- "${scratch:?}"; lc_abort redaction-hit 1 "layer=gitleaks"; fi
  if [ "$g_rc" -ne 0 ]; then rm -rf -- "${scratch:?}"; lc_abort scanner-failed 2 "gitleaks rc=$g_rc"; fi
  rm -rf -- "${scratch:?}"
  [ "$dry" = 1 ] && return 0
  destdir=$(dirname "$dest")
  mkdir -p "$destdir" || lc_abort write-failed 2 "mkdir"
  tmp=$(mktemp "$destdir/.launch-check.XXXXXX") || lc_abort write-failed 2 "mktemp"
  if cp "$src" "$tmp" && cmp -s "$src" "$tmp" && mv -f "$tmp" "$dest"; then return 0; fi
  rm -f -- "${tmp:?}"
  lc_abort write-failed 2 "copy"
}
