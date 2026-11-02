#!/usr/bin/env bash
# launch-check.sh: read-only production-readiness + Soleur-baseline gap analysis for a customer repository.
#
#   scan          --target <repo> --facts <file> [--files-out <file>] [--show-secrets]
#   render        --target <repo> --facts <file> [--judged <file>] [--dry-run]
#   verify-report --file <report.md>
#
# The analysis writes nothing but the report file. No network, no telemetry. Exit codes:
#   0 ok · 1 redaction hit (render) / invalid report (verify-report) · 2 preflight or scanner failure.
# Every abort prints one SOLEUR_LAUNCH_CHECK_ABORT marker; this tool's only sink is the caller's tool result.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd -P)"
PLUGIN_DIR="$(cd "$SKILL_DIR/../.." && pwd -P)"
REPORT_REL="knowledge-base/engineering/readiness/launch-check.md"
export SKILL_DIR PLUGIN_DIR

# shellcheck source=lib/common.sh
source "$SKILL_DIR/scripts/lib/common.sh"
# shellcheck source=lib/safe-walk.sh
source "$SKILL_DIR/scripts/lib/safe-walk.sh"
# shellcheck source=lib/checks.sh
source "$SKILL_DIR/scripts/lib/checks.sh"
# shellcheck source=lib/baseline.sh
source "$SKILL_DIR/scripts/lib/baseline.sh"
# shellcheck source=lib/redact-gate.sh
source "$SKILL_DIR/scripts/lib/redact-gate.sh"
# shellcheck source=lib/render.sh
source "$SKILL_DIR/scripts/lib/render.sh"

WORK=""
cleanup() { [ -n "$WORK" ] && rm -rf -- "${WORK:?}"; return 0; }
trap cleanup EXIT INT TERM HUP

# The plugin root is resolved by IDENTITY (the manifest names soleur), never by a working-directory guess,
# and everything the skill reads at run time must ship inside it.
preflight_plugin() {
  grep -q '"name"[[:space:]]*:[[:space:]]*"soleur"' "$PLUGIN_DIR/.claude-plugin/plugin.json" 2>/dev/null \
    || lc_abort plugin-root-unresolved 2 "no soleur manifest above $SKILL_DIR"
  [ -s "$(lc_guards_tsv)" ] || lc_abort plugin-root-unresolved 2 "guards.tsv missing or empty"
  [ -r "${LAUNCH_CHECK_REDACT_SENTINEL:-$PLUGIN_DIR/skills/incident/scripts/redact-sentinel.sh}" ] \
    || lc_abort plugin-root-unresolved 2 "redact-sentinel.sh missing"
}

need_repo() {
  [ -n "${TARGET:-}" ] || lc_abort usage 2 "--target is required"
  git -C "$TARGET" rev-parse --is-inside-work-tree >/dev/null 2>&1 || lc_abort not-a-git-repo 2 "$TARGET"
  TARGET=$(cd "$TARGET" && pwd -P)
}

cmd_scan() {
  local files_out=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --target) TARGET=$2; shift 2 ;;
      --facts) FACTS=$2; shift 2 ;;
      --files-out) files_out=$2; shift 2 ;;
      --show-secrets) LC_SHOW_SECRETS=1; shift ;;
      *) lc_abort usage 2 "unknown scan argument: $1" ;;
    esac
  done
  [ -n "${FACTS:-}" ] || lc_abort usage 2 "--facts is required"
  need_repo; preflight_plugin; lc_preflight_scanners
  WORK=$(mktemp -d "${TMPDIR:-/tmp}/lc-work.XXXXXX") || lc_abort scanner-failed 2 "mktemp failed"
  lc_walk "$TARGET" "$WORK/files"
  STACK=$(lc_stack "$WORK/files")
  CAT="$WORK/catalog.tsv"; lc_build_catalog "$CAT"
  FACTS_OUT="$WORK/facts.tsv"; : > "$FACTS_OUT"
  lc_run_checks "$CAT"
  cp "$FACTS_OUT" "$FACTS"
  [ -n "$files_out" ] && cp "$WORK/files" "$files_out"
  printf 'SOLEUR_LAUNCH_CHECK_RUN stack=%s checks=%s gaps=%s excluded=%s symlinks=%s\n' \
    "$STACK" "$(grep -c . "$FACTS_OUT")" "$(awk -F'\t' '$2=="gap"' "$FACTS_OUT" | grep -c .)" "$LC_EXCLUDED_COUNT" "$LC_SYMLINK_COUNT"
}

cmd_render() {
  JUDGED=""; DRY=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --target) TARGET=$2; shift 2 ;;
      --facts) FACTS=$2; shift 2 ;;
      --judged) JUDGED=$2; shift 2 ;;
      --dry-run) DRY=1; shift ;;
      *) lc_abort usage 2 "unknown render argument: $1" ;;
    esac
  done
  [ -s "${FACTS:-}" ] || lc_abort usage 2 "--facts must name the file written by scan"
  [ -z "$JUDGED" ] || [ -f "$JUDGED" ] || lc_abort usage 2 "--judged file not found"
  need_repo; preflight_plugin; lc_preflight_scanners
  WORK=$(mktemp -d "${TMPDIR:-/tmp}/lc-work.XXXXXX") || lc_abort scanner-failed 2 "mktemp failed"
  lc_walk "$TARGET" "$WORK/files"
  STACK=$(lc_stack "$WORK/files")
  CAT="$WORK/catalog.tsv"; lc_build_catalog "$CAT"
  [ -z "$JUDGED" ] || lc_validate_judged "$JUDGED"
  lc_render
  if [ "$DRY" = 1 ]; then
    lc_emit_checked "$WORK/report.md" "" 1
    cat "$WORK/report.md"
  else
    lc_emit_checked "$WORK/report.md" "$TARGET/$REPORT_REL" 0
    printf 'SOLEUR_LAUNCH_CHECK_WRITE path=%s findings=%s\n' "$REPORT_REL" "$LC_OPEN_COUNT"
  fi
}

cmd_verify() {
  local file="" block n
  while [ $# -gt 0 ]; do
    case "$1" in --file) file=$2; shift 2 ;; *) lc_abort usage 2 "unknown verify-report argument: $1" ;; esac
  done
  invalid() { printf 'SOLEUR_LAUNCH_CHECK_REPORT_INVALID reason=%s\n' "$1"; exit 1; }
  [ -f "$file" ] || invalid file-missing
  block=$(awk '/^```launch-check-state$/ {f=1; next} /^```$/ && f {f=0} f' "$file")
  [ -n "$block" ] || invalid no-state-block
  printf '%s\n' "$block" | grep -qx 'schema_version=1' || invalid schema-version
  printf '%s\n' "$block" | grep -qE '^catalog_hash=.+' || invalid catalog-hash
  if printf '%s\n' "$block" | grep -vE '^(schema_version=1|catalog_hash=.+|finding [A-Za-z]+-[A-Za-z0-9-]+ (open|accepted( .*)?))$' | grep -q .; then invalid bad-line; fi
  n=$(printf '%s\n' "$block" | grep -c '^finding ')
  printf 'LAUNCH_CHECK_REPORT_OK findings=%s\n' "$n"
}

main() {
  local sub=${1:-}
  [ $# -gt 0 ] && shift
  case "$sub" in
    scan) cmd_scan "$@" ;;
    render) cmd_render "$@" ;;
    verify-report) cmd_verify "$@" ;;
    *) printf 'usage: launch-check.sh scan|render|verify-report [options]\n' >&2; exit 2 ;;
  esac
}
main "$@"
