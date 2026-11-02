#!/usr/bin/env bash
# launch-check.sh: read-only production-readiness + Soleur-baseline gap analysis for a customer repository.
#
#   scan          --target <repo> --facts <file> [--files-out <file>] [--show-secrets]
#   render        --target <repo> --facts <file> [--judged <file>] [--dry-run]
#   verify-report --file <report.md>
#   report-path   (prints the report's repo-relative path)
#
# The analysis writes nothing but the report file. No network, no telemetry. Exit codes:
#   0 ok · 1 redaction hit (render) / invalid report (verify-report) · 2 usage, preflight, scanner, input or write failure.
# Every abort prints one SOLEUR_LAUNCH_CHECK_ABORT marker; this tool's only sink is the caller's tool result.
# Headless runs (CI set, or LAUNCH_CHECK_HEADLESS=1) may scan and render --dry-run but never overwrite the report.
set -uo pipefail

# Deterministic ordering and matching on every machine, and a repository that cannot run code through git config
# while we read it (a core.fsmonitor command, a hooks path).
export LC_ALL=C
export GIT_CONFIG_COUNT=2 GIT_CONFIG_KEY_0=core.fsmonitor GIT_CONFIG_VALUE_0=false GIT_CONFIG_KEY_1=core.hooksPath GIT_CONFIG_VALUE_1=/dev/null

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
trap cleanup EXIT
# A signal must END the run (a trap that only cleans up lets the script carry on against a deleted work directory).
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

# The plugin root is resolved by IDENTITY (the manifest names soleur), never by a working-directory guess,
# and everything the skill reads at run time must ship inside it.
preflight_plugin() {
  grep -q '"name"[[:space:]]*:[[:space:]]*"soleur"' "$PLUGIN_DIR/.claude-plugin/plugin.json" 2>/dev/null \
    || lc_abort plugin-root-unresolved 2 "no soleur manifest above $SKILL_DIR"
  [ -s "$(lc_guards_tsv)" ] || lc_abort plugin-root-unresolved 2 "guards.tsv missing or empty"
  [ -r "$(lc_seam LAUNCH_CHECK_REDACT_SENTINEL "$PLUGIN_DIR/skills/incident/scripts/redact-sentinel.sh")" ] \
    || lc_abort plugin-root-unresolved 2 "redact-sentinel.sh missing"
}

# val <flag> <remaining-argc>: a flag with no value is a usage error (exit 2), not an unbound-variable crash (exit 1).
val() { [ "$2" -ge 2 ] || lc_abort usage 2 "$1 needs a value"; }

is_headless() { [ -n "${CI:-}" ] || [ "${LAUNCH_CHECK_HEADLESS:-}" = 1 ]; }

need_repo() {
  [ -n "${TARGET:-}" ] || lc_abort usage 2 "--target is required"
  [ "$(git -C "$TARGET" rev-parse --is-inside-work-tree 2>/dev/null)" = true ] || lc_abort not-a-git-repo 2 "$TARGET"
  # The repository root, not the directory the caller happened to be in: files, report and scan all key on it.
  TARGET=$(cd "$(git -C "$TARGET" rev-parse --show-toplevel)" && pwd -P)
}

cmd_scan() {
  local files_out=""
  TARGET=""; FACTS=""
  # shellcheck disable=SC2034  # read by the SEC-01/SEC-02 detectors in lib/checks.sh
  LC_SHOW_SECRETS=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --target) val "$1" $#; TARGET=$2; shift 2 ;;
      --facts) val "$1" $#; FACTS=$2; shift 2 ;;
      --files-out) val "$1" $#; files_out=$2; shift 2 ;;
      --show-secrets)
        # Locations of secrets belong on the customer's own terminal. A pipe (an agent's tool result) is not one.
        if [ -t 1 ] || [ "${LAUNCH_CHECK_TEST:-}" = 1 ]; then LC_SHOW_SECRETS=1; export LC_SHOW_SECRETS; shift
        else lc_abort usage 2 "--show-secrets prints secret locations and needs an interactive terminal: run it yourself in a separate terminal, not through an agent"; fi ;;
      *) lc_abort usage 2 "unknown scan argument: $1" ;;
    esac
  done
  [ -n "$FACTS" ] || lc_abort usage 2 "--facts is required"
  # A failed scan must not leave the previous run's facts behind for render to accept.
  rm -f -- "$FACTS" ${files_out:+"$files_out"}
  need_repo; preflight_plugin; lc_preflight_scanners
  WORK=$(mktemp -d "${TMPDIR:-/tmp}/lc-work.XXXXXX") || lc_abort scanner-failed 2 "mktemp failed"
  lc_walk "$TARGET" "$WORK/files"
  STACK=$(lc_stack "$WORK/files")
  CAT="$WORK/catalog.tsv"; lc_build_catalog "$CAT"
  FACTS_OUT="$WORK/facts.tsv"; printf '# stack=%s\n' "$STACK" > "$FACTS_OUT"
  lc_run_checks "$CAT"
  cp "$FACTS_OUT" "$FACTS" || lc_abort write-failed 2 "facts file $FACTS"
  if [ -n "$files_out" ]; then cp "$WORK/files" "$files_out" || lc_abort write-failed 2 "files list $files_out"; fi
  printf 'SOLEUR_LAUNCH_CHECK_RUN stack=%s checks=%s gaps=%s ok=%s not-assessed=%s excluded=%s symlinks=%s\n' "$STACK" \
    "$(grep -vc '^#' "$FACTS_OUT")" \
    "$(awk -F'\t' '$2=="gap"' "$FACTS_OUT" | grep -c .)" \
    "$(awk -F'\t' '$2=="ok"' "$FACTS_OUT" | grep -c .)" \
    "$(awk -F'\t' '$2=="na" || $2=="unsupported-stack"' "$FACTS_OUT" | grep -c .)" \
    "$LC_EXCLUDED_COUNT" "$LC_SYMLINK_COUNT"
}

cmd_render() {
  JUDGED=""; DRY=0; TARGET=""; FACTS=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --target) val "$1" $#; TARGET=$2; shift 2 ;;
      --facts) val "$1" $#; FACTS=$2; shift 2 ;;
      --judged) val "$1" $#; JUDGED=$2; shift 2 ;;
      --dry-run) DRY=1; shift ;;
      *) lc_abort usage 2 "unknown render argument: $1" ;;
    esac
  done
  [ -s "${FACTS:-}" ] || lc_abort usage 2 "--facts must name the file written by scan"
  [ -z "$JUDGED" ] || [ -f "$JUDGED" ] || lc_abort usage 2 "--judged file not found"
  if [ "$DRY" = 0 ] && is_headless; then
    lc_abort headless-write-refused 2 "unattended runs (CI or LAUNCH_CHECK_HEADLESS=1) may only use --dry-run"
  fi
  need_repo; preflight_plugin; lc_preflight_scanners
  WORK=$(mktemp -d "${TMPDIR:-/tmp}/lc-work.XXXXXX") || lc_abort scanner-failed 2 "mktemp failed"
  # scan records the stack in the facts header; only an older or hand-made facts file needs the repository walked again.
  STACK=$(awk -F= '/^# stack=/ {print $2; exit}' "$FACTS")
  if [ -z "$STACK" ]; then lc_walk "$TARGET" "$WORK/files"; STACK=$(lc_stack "$WORK/files"); fi
  CAT="$WORK/catalog.tsv"; lc_build_catalog "$CAT"
  lc_clean_facts
  [ -z "$JUDGED" ] || lc_validate_judged "$JUDGED"
  lc_render
  if [ "$DRY" = 1 ]; then
    lc_emit_checked "$WORK/report.md" "" 1
    cat "$WORK/report.md"
  else
    LC_DEST_ROOT="$TARGET" lc_emit_checked "$WORK/report.md" "$TARGET/$REPORT_REL" 0
    printf 'SOLEUR_LAUNCH_CHECK_WRITE path=%s findings=%s\n' "$REPORT_REL" "$LC_OPEN_COUNT"
  fi
}

cmd_verify() {
  local file="" block n dups bad
  while [ $# -gt 0 ]; do
    case "$1" in --file) val "$1" $#; file=$2; shift 2 ;; *) lc_abort usage 2 "unknown verify-report argument: $1" ;; esac
  done
  invalid() { printf 'SOLEUR_LAUNCH_CHECK_REPORT_INVALID reason=%s\n' "$1"; exit 1; }
  [ -f "$file" ] || invalid file-missing
  block=$(tr -d '\r' < "$file" | awk '/^```launch-check-state$/ {f=1; next} /^```$/ && f {f=0} f')
  [ -n "$block" ] || invalid no-state-block
  # Here-strings, not `printf | grep -q`: under pipefail an early-exiting grep can SIGPIPE the writer and read a match as a miss (#9217).
  grep -qx 'schema_version=1' <<<"$block" || invalid schema-version
  grep -qE '^catalog_hash=.+' <<<"$block" || invalid catalog-hash
  bad=$(grep -vE '^(schema_version=1|catalog_hash=.+|finding [A-Z]+-[A-Za-z0-9-]+ (open|accepted( .*)?))$' <<<"$block" || true)
  [ -z "$bad" ] || invalid bad-line
  if grep -qE '^finding SEC-0[12] accepted *$' <<<"$block"; then invalid critical-accept-needs-reason; fi
  dups=$(printf '%s\n' "$block" | awk '$1 == "finding" {print $2}' | sort | uniq -d | head -n 1)
  [ -z "$dups" ] || invalid duplicate-id
  n=$(printf '%s\n' "$block" | grep -c '^finding ')
  printf 'SOLEUR_LAUNCH_CHECK_REPORT_OK findings=%s\n' "$n"
}

main() {
  local sub=${1:-}
  [ $# -gt 0 ] && shift
  case "$sub" in
    scan) cmd_scan "$@" ;;
    render) cmd_render "$@" ;;
    verify-report) cmd_verify "$@" ;;
    report-path) printf '%s\n' "$REPORT_REL" ;;
    *) lc_abort usage 2 "usage: launch-check.sh scan|render|verify-report|report-path [options]" ;;
  esac
}
main "$@"
