#!/usr/bin/env bash
set -uo pipefail

# Refuse to run under xtrace, unconditionally: this script reads live Anthropic
# keys into shell variables, and `bash -x` would print them (see #7797). Exit 78 = EX_CONFIG.
case "$-" in
  *x*) printf '[FATAL] refusing to run under xtrace: this script handles a live credential and -x would print it (see #7797)\n' >&2; exit 78 ;;
esac

# anthropic-key-distinctness.sh — prove that CI and manual evals do not hold the
# production Anthropic key (#8505, AC1). Never prints a value: each config is
# reported as `<config> <sha256[:12]>`, `<config> ABSENT` or `<config> ERROR`.
#
# Scope is DERIVED from `doppler configs`, never hard-coded: every config matching
# ^ci($|_) on the CI side and every config matching ^prd($|_) on the production side.
# A ci_* or prd_* branch added later is compared automatically. The root `ci` config
# must hold a key; a ci_* branch may be ABSENT.
#
# Exit 0  DISTINCT: ci holds a key, and no ci* key equals any prd* key.
# Exit 1  ci is ABSENT, or some ci* key equals some prd* key.
# Exit 2  could not measure: config enumeration or parsing failed, a read failed,
#         no ci/prd* config was enumerated, or no prd* config holds a key. Never a pass.
#
# Not covered, by construction: keys outside Doppler project `soleur`, other secret
# names, and the GitHub repo secret (write-only; Terraform writes it from the same
# source as Doppler `ci`).
#
# Usage (needs Doppler read on soleur/ci* and soleur/prd*):
#   bash apps/web-platform/scripts/anthropic-key-distinctness.sh

readonly PROJECT="soleur"
readonly KEY="ANTHROPIC_API_KEY"

# One owned scratch dir for Doppler's stderr (it is how ABSENT is told apart from
# a failed read). Holds error text only, never a value.
WORK="$(mktemp -d)"
trap 'rm -rf -- "$WORK"' EXIT
case "$WORK" in /*) : ;; *) printf 'ERROR mktemp returned a non-absolute path\n'; exit 2 ;; esac

# fingerprint VALUE — first 12 hex chars of sha256. `printf` is a builtin, so the
# value never lands in the argv of an external process.
fingerprint() { printf '%s' "$1" | sha256sum | cut -c1-12; }

# read_key CONFIG — sets READ_STATE (PRESENT|ABSENT|ERROR) and READ_FP.
read_key() {
  local cfg="$1" val err="$WORK/stderr" rc=0
  val="$(doppler secrets get "$KEY" -p "$PROJECT" -c "$cfg" --plain 2>"$err")" || rc=$?
  READ_FP=""
  if (( rc == 0 )) && [[ -n "$val" ]]; then
    READ_STATE=PRESENT
    READ_FP="$(fingerprint "$val")"
  elif (( rc == 0 )) || grep -q 'Could not find requested secret' "$err"; then
    READ_STATE=ABSENT
  else
    READ_STATE=ERROR
  fi
  val=""
  unset val
}

configs_json=""
if ! configs_json="$(doppler configs -p "$PROJECT" --json 2>/dev/null)"; then
  printf 'ERROR could not enumerate Doppler configs for %s\n' "$PROJECT"
  exit 2
fi
# jq runs as its own command (not inside a process substitution) so a parse error
# reaches the exit status instead of truncating the list silently.
names=""
if ! names="$(jq -er '.[] | .name | strings' <<<"$configs_json")"; then
  printf 'ERROR could not parse the Doppler config list\n'
  exit 2
fi
mapfile -t prd_configs < <(grep -E '^prd($|_)' <<<"$names" | LC_ALL=C sort)
mapfile -t ci_configs < <(grep -E '^ci($|_)' <<<"$names" | LC_ALL=C sort)
if (( ${#prd_configs[@]} == 0 )); then
  printf 'ERROR no prd* config enumerated — nothing to compare against\n'
  exit 2
fi
if [[ "${ci_configs[0]:-}" != ci ]]; then
  printf 'ERROR the root ci config was not enumerated\n'
  exit 2
fi

errors=0
declare -A ci_fps=()
root_ci_state=""
for cfg in "${ci_configs[@]}"; do
  read_key "$cfg"
  [[ "$cfg" == ci ]] && root_ci_state="$READ_STATE"
  case "$READ_STATE" in
    PRESENT) printf '%s %s\n' "$cfg" "$READ_FP"; ci_fps["$READ_FP"]="$cfg" ;;
    ABSENT) printf '%s ABSENT\n' "$cfg" ;;
    *) printf '%s ERROR\n' "$cfg"; errors=$((errors + 1)) ;;
  esac
done

equal=0
compared=0
for cfg in "${prd_configs[@]}"; do
  read_key "$cfg"
  case "$READ_STATE" in
    PRESENT)
      printf '%s %s\n' "$cfg" "$READ_FP"
      compared=$((compared + 1))
      [[ -n "${ci_fps[$READ_FP]:-}" ]] && equal=$((equal + 1))
      ;;
    ABSENT) printf '%s ABSENT\n' "$cfg" ;;
    *) printf '%s ERROR\n' "$cfg"; errors=$((errors + 1)) ;;
  esac
done

if (( errors > 0 )); then
  printf 'ERROR %d read(s) failed — the comparison is incomplete\n' "$errors"
  exit 2
fi
if (( compared == 0 )); then
  printf 'ERROR no prd* config holds %s — nothing was compared\n' "$KEY"
  exit 2
fi
if [[ "$root_ci_state" != PRESENT ]]; then
  printf 'SAME-OR-MISSING ci holds no %s\n' "$KEY"
  exit 1
fi
if (( equal > 0 )); then
  printf 'SAME-OR-MISSING a ci* key equals %d prd* config(s)\n' "$equal"
  exit 1
fi
printf 'DISTINCT\n'
exit 0
