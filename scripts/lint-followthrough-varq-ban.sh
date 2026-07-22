#!/usr/bin/env bash
# lint-followthrough-varq-ban.sh -- fail when a follow-through probe gates its exit
# on the banned `: "${VAR:?msg}"` / colon-less `${VAR?msg}` word-expansion (#6757).
#
# WHY: under the sweeper's non-interactive shell, `${VAR:?}` / `${VAR?}` ABORTS with
# status 1 the instant the variable is unset/empty. In the sweep-followthroughs.sh exit
# contract `exit 1 = FAIL = "do NOT close"`, so an unprovisioned secret posts a DAILY
# false-FAIL comment forever instead of exiting 2 (TRANSIENT = quiet retry). The
# compliant form is `if [[ -z "${VAR:-}" ]]; then echo "TRANSIENT: ..." >&2; exit 2; fi`.
# The ban is documented in followthrough-convention.md §Author workflow; this guard is
# its mechanical enforcer. It is the EXECUTABLE FORM of that doc's canonical census.
#
# Detection = the canonical census, byte-faithful:
#   grep -nE '\$\{[A-Za-z_][A-Za-z0-9_]*:?\?'  (optional colon, then literal `?`)
# then drop FULL-LINE comments (`^[0-9]+:[[:space:]]*#` on the -n output). Any surviving
# line is a violation. The regex is named-var only by design (matches the doc census);
# a positional-param `${1:?}` is uncaught, but every probe secret is a named var.
#
# LINE-NUMBER ORDER IS LOAD-BEARING: run `grep -n` on the RAW file FIRST, then drop
# full-line-comment hits. Piping `grep -v '^#' | grep -n` re-indexes line numbers against
# the comment-stripped stream and mis-cites every offender (ghcr-minter-live's real line 28
# would print as 4). Detection is identical either way; only the diagnostic file:line differs,
# and naming the offender accurately is the whole value of the guard.
#
# Usage:  lint-followthrough-varq-ban.sh [TARGET_DIR]
#   no arg      -> scans <repo-root>/scripts/followthroughs (production run; ≥10-file floor)
#   TARGET_DIR  -> scans that dir verbatim (how the .test.sh points it at a mktemp sandbox)
#
# Exit: 0 = no violations; 1 = one or more violations; 2 = internal error (dir absent, or a
#       production run whose probe count falls below the min-cardinality floor -> broken glob).

set -uo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
DEFAULT_DIR="${REPO_ROOT:-.}/scripts/followthroughs"
TARGET_DIR="${1:-$DEFAULT_DIR}"

if [[ ! -d "$TARGET_DIR" ]]; then
  echo "ERROR: target dir not found: $TARGET_DIR" >&2
  exit 2
fi

# The min-cardinality floor keys on the RESOLVED target dir, not on arg-presence: a caller
# passing the real dir explicitly (lint-followthrough-varq-ban.sh scripts/followthroughs)
# must not silently bypass the vacuity floor; a mktemp sandbox dir never resolves to the
# default, so the floor is skipped there (deepen-plan finding).
resolve() { (cd "$1" 2>/dev/null && pwd -P) || echo "$1"; }
is_production_run="no"
if [[ "$(resolve "$TARGET_DIR")" == "$(resolve "$DEFAULT_DIR")" ]]; then
  is_production_run="yes"
fi

violations=0
scanned=0
for f in "$TARGET_DIR"/*.sh; do
  [[ -e "$f" ]] || continue
  case "$f" in
    *.test.sh) continue ;;
  esac
  scanned=$((scanned + 1))
  # grep -n on the RAW file FIRST (correct line numbers), THEN drop full-line comments.
  while IFS= read -r hit; do
    [[ -z "$hit" ]] && continue
    lineno="${hit%%:*}"
    echo "$f:$lineno: banned \${VAR:?} / \${VAR?} form on an executable line -- use 'if [[ -z \"\${VAR:-}\" ]]; then echo \"TRANSIENT: ...\" >&2; exit 2; fi'" >&2
    violations=$((violations + 1))
  done < <(grep -nE '\$\{[A-Za-z_][A-Za-z0-9_]*:?\?' "$f" | grep -vE '^[0-9]+:[[:space:]]*#')
done

# Minimum-cardinality floor (production run only): a broken glob yielding 0 files must not
# pass vacuously. Skipped for an explicit sandbox dir (the .test.sh fixtures are few).
# VARQ_BAN_MIN_PROBES is a TEST-ONLY override so the .test.sh can force a floor breach on the
# real tree (set it above the probe count) and prove exit 2 fires; production CI never sets it
# and gets the default 10.
MIN_PROBES="${VARQ_BAN_MIN_PROBES:-10}"
if [[ "$is_production_run" == "yes" ]] && (( scanned < MIN_PROBES )); then
  echo "ERROR: only $scanned non-test probe(s) scanned in $TARGET_DIR -- expected the full set; the glob or path is broken" >&2
  exit 2
fi

if (( violations > 0 )); then
  echo "FAILED: $violations banned \${VAR:?}/\${VAR?} occurrence(s) on executable lines. See followthrough-convention.md §Author workflow." >&2
  exit 1
fi

echo "followthrough-varq-ban: clean ($scanned probe(s) scanned in $TARGET_DIR)"
exit 0
