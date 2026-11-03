# shellcheck shell=bash
# The write chokepoint. Every byte that reaches the report goes through lc_emit_checked.
# Requires SKILL_DIR and PLUGIN_DIR. Test seams (honoured only when LAUNCH_CHECK_TEST=1, see lc_seam):
# LAUNCH_CHECK_REDACT_SENTINEL, LAUNCH_CHECK_GITLEAKS. Optional LC_DEST_ROOT: the write must stay inside it.
source "$SKILL_DIR/scripts/lib/common.sh"

# The version CI pins and code-to-prd documents (parity-tested against code-to-prd.sh, so the two cannot drift apart).
LC_GITLEAKS_PIN=8.24.2

# lc_preflight_scanners: the redaction layers must be runnable before anything is read or written.
# Resolvable is not runnable: an unpinned version-manager shim satisfies `command -v` and fails on every call, so the
# binary is probed by running it (bounded when the host has a timeout command; stock macOS has neither).
lc_preflight_scanners() {
  local gl bound=""
  gl=$(lc_seam LAUNCH_CHECK_GITLEAKS gitleaks)
  command -v "$gl" >/dev/null 2>&1 || lc_abort scanner-missing 2 "install gitleaks $LC_GITLEAKS_PIN (macOS: brew install gitleaks; Linux: your package manager, or mise use gitleaks@$LC_GITLEAKS_PIN)"
  if command -v timeout >/dev/null 2>&1; then bound="timeout 10"; elif command -v gtimeout >/dev/null 2>&1; then bound="gtimeout 10"; fi
  # shellcheck disable=SC2086  # $bound is deliberately split into command and argument
  $bound "$gl" version >/dev/null 2>&1 || lc_abort scanner-failed 2 "gitleaks is on PATH but not runnable; CI pins $LC_GITLEAKS_PIN"
}

# lc_emit_checked <src-file> <dest-path> <dry-run 0|1>: scan the exact bytes, then write them or write nothing.
# The body runs in a subshell so its EXIT trap owns the scratch directory and the destination temp file on
# every path (including lc_abort's exit) without replacing the caller's own trap.
lc_emit_checked() {
  local rc=0
  ( lc__emit_body "$@" ) || rc=$?
  [ "$rc" -eq 0 ] || exit "$rc"
}

# scratch and tmp are deliberately NOT local: the EXIT trap fires after the function has returned, when a local would
# already be gone (the old form printed "scratch: parameter null or not set" and leaked the scratch directory).
lc__emit_body() {
  local src=$1 dest=$2 dry=${3:-0} gl s_rc=0 g_rc=0 destdir anc real err
  local REDACT_SENTINEL
  gl=$(lc_seam LAUNCH_CHECK_GITLEAKS gitleaks)
  REDACT_SENTINEL=$(lc_seam LAUNCH_CHECK_REDACT_SENTINEL "$PLUGIN_DIR/skills/incident/scripts/redact-sentinel.sh")
  tmp=""
  command -v "$gl" >/dev/null 2>&1 || lc_abort scanner-missing 2 "gitleaks not found"
  scratch=$(mktemp -d "${TMPDIR:-/tmp}/lc-gate.XXXXXX") || lc_abort scanner-failed 2 "mktemp failed"
  trap 'rm -rf -- "${scratch:?}"; [ -z "$tmp" ] || rm -f -- "$tmp"' EXIT
  # Both paths are made absolute BEFORE the scans move to the scratch directory: gitleaks reads .gitleaksignore (and the
  # sentinel its own relative files) from the working directory, so a customer's repository or a plan directory must
  # never be the place the scanners run from.
  case "$scratch" in /*) ;; *) scratch="$PWD/$scratch" ;; esac
  case "$src" in /*) ;; *) src="$PWD/$src" ;; esac
  case "$dest" in ""|/*) ;; *) dest="$PWD/$dest" ;; esac
  cd "$scratch" || lc_abort scanner-failed 2 "scratch directory"
  bash "$REDACT_SENTINEL" "$src" >/dev/null 2>&1 || s_rc=$?
  [ "$s_rc" -eq 1 ] && lc_abort redaction-hit 1 "layer=sentinel"
  [ "$s_rc" -eq 0 ] || lc_abort scanner-failed 2 "sentinel rc=$s_rc"
  # The repository's own gitleaks configuration must never relax the gate (the scans run from the scratch directory).
  env -u GITLEAKS_CONFIG -u GITLEAKS_CONFIG_TOML "$gl" detect --source "$src" --no-git --report-format json --report-path "$scratch/r.json" --redact --exit-code 1 >/dev/null 2>"$scratch/e" || g_rc=$?
  if [ "$g_rc" -eq 1 ] && grep -q '"RuleID"' "$scratch/r.json" 2>/dev/null; then lc_abort redaction-hit 1 "layer=gitleaks"; fi
  if [ "$g_rc" -ne 0 ]; then err=$(head -c 160 "$scratch/e" | tr '\n\t' '  '); lc_abort scanner-failed 2 "gitleaks rc=$g_rc: $err"; fi
  [ "$dry" = 1 ] && return 0
  destdir=$(dirname "$dest")
  if [ -n "${LC_DEST_ROOT:-}" ]; then
    # Resolve the deepest EXISTING ancestor physically before creating anything: a symlinked knowledge-base/ must not
    # carry the write outside the repository.
    anc=$destdir; while [ ! -d "$anc" ]; do anc=$(dirname "$anc"); done
    real=$(cd "$anc" && pwd -P)
    case "$real/" in "$LC_DEST_ROOT"/*) ;; *) lc_abort write-failed 2 "destination resolves outside the target repository" ;; esac
  fi
  mkdir -p "$destdir" || lc_abort write-failed 2 "mkdir"
  tmp=$(mktemp "$destdir/.launch-check.XXXXXX") || lc_abort write-failed 2 "mktemp"
  if cp "$src" "$tmp" && cmp -s "$src" "$tmp" && chmod 644 "$tmp" && mv -f "$tmp" "$dest"; then tmp=""; return 0; fi
  lc_abort write-failed 2 "copy"
}
