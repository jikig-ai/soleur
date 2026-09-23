#!/usr/bin/env bash
# pre-merge-rebase's resolver lookup finds the PLUGIN's copy first (#8542 follow-up, AC8).
#
# Both pre-merge-rebase.sh copies loaded resolve-regenerable-conflicts.sh from
# $WORK_DIR/plugins/soleur/scripts/ only -- a path inside the repository being merged. In a
# self-hosted repo that path does not exist, so the regen retry never ran and the hook denied
# `gh pr merge`; and where it does exist it is the MERGED tree's copy, whose sibling renderer the
# resolver would then execute. The lookup now prefers ${CLAUDE_PLUGIN_ROOT}.
#
# The block is extracted from each hook by its marker comments and EXECUTED, so the rows measure
# the shipped bytes rather than a paraphrase of them. The two copies are asserted byte-identical.
#
# Run via:  bash .claude/hooks/pre-merge-rebase-regen-lookup.test.sh
export TMPDIR="${TMPDIR:-/var/tmp}"

set -uo pipefail

# Redirect incident telemetry into a per-suite sandbox BEFORE any case runs (see the helper).
. "$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/lib/test-incident-sandbox.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HOOK_CLAUDE="$REPO_ROOT/.claude/hooks/pre-merge-rebase.sh"
HOOK_OPENHANDS="$REPO_ROOT/.openhands/hooks/pre-merge-rebase.sh"

passes=0; fails=0; CASES_RUN=0; FAILED=()
pass() { passes=$((passes + 1)); echo "  PASS: $1"; }
fail() { fails=$((fails + 1)); FAILED+=("$1"); echo "  FAIL: $1" >&2; }

_iv_p="$passes"; _iv_f="$fails"; _iv_n="${#FAILED[@]}"
{ pass "self-test"; fail "self-test"; } >/dev/null 2>&1
if [[ "$passes" -ne $((_iv_p + 1)) || "$fails" -ne $((_iv_f + 1)) || "${#FAILED[@]}" -ne $((_iv_n + 1)) ]]; then
  printf '[FATAL] instrument self-test: the verdict helpers did not both record\n' >&2; exit 1
fi
passes=0; fails=0; FAILED=(); CASES_RUN=0

# The body below is a COPY. The canonical definition lives in
# plugins/soleur/test/test-helpers.sh; plugins/soleur/test/fixture-dir-operand-assert.test.sh
# asserts this copy is byte-equal to it. Do not reword it in one file only. #7652
assert_fixture_dir() {
  case "${1-}" in
    "") printf 'FATAL: fixture dir is EMPTY; git -C "" would operate on %s\n' "$PWD" >&2; exit 2 ;;
    */../*|*/..) printf 'FATAL: fixture dir %s contains ..; refusing\n' "$1" >&2; exit 2 ;;
    /proc/*|/sys/*|/dev/*) printf 'FATAL: fixture dir %s is a synthetic-fs path; refusing\n' "$1" >&2; exit 2 ;;
    /|//|/.) printf 'FATAL: fixture dir resolves to the filesystem root; refusing\n' >&2; exit 2 ;;
    /*) : ;;
    *)  printf 'FATAL: fixture dir %s is RELATIVE; refusing\n' "$1" >&2; exit 2 ;;
  esac
}

SANDBOX="$(mktemp -d)"; assert_fixture_dir "$SANDBOX"
trap 'rm -rf "$SANDBOX"' EXIT

# extract <hook> — the lookup block, marker to marker. REFUSES a slice that lacks the
# constructs that define it: a truncated block still parses and answers, and would then
# report a verdict about code that is not the hook's.
extract() {
  local out
  out="$(sed -n '/# >>> regen-resolver-lookup/,/# <<< regen-resolver-lookup/p' "$1")"
  if [[ "$out" != *'REGEN_RESOLVER=""'* || "$out" != *'CLAUDE_PLUGIN_ROOT'* \
        || "$out" != *'$WORK_DIR/plugins/soleur/scripts/resolve-regenerable-conflicts.sh'* \
        || "$out" != *'<<< regen-resolver-lookup'* ]]; then
    printf '[FATAL] could not extract the regen-resolver-lookup block from %s\n' "$1" >&2; exit 2
  fi
  printf '%s\n' "$out"
}
BLOCK_CLAUDE="$(extract "$HOOK_CLAUDE")"
BLOCK_OPENHANDS="$(extract "$HOOK_OPENHANDS")"
printf '%s\n' "$BLOCK_CLAUDE" > "$SANDBOX/block.sh"

echo "=== pre-merge-rebase regen-resolver lookup (AC8) ==="

CASES_RUN=$((CASES_RUN + 1))
[[ "$BLOCK_CLAUDE" == "$BLOCK_OPENHANDS" ]] \
  && pass "the .claude and .openhands lookup blocks are byte-identical" \
  || fail "the two hooks' lookup blocks diverged: $(diff <(printf '%s\n' "$BLOCK_CLAUDE") <(printf '%s\n' "$BLOCK_OPENHANDS") | head -5 | tr '\n' ' ')"

# The hook consumes the lookup through `-n`, not `-f`: an empty REGEN_RESOLVER must skip the
# retry. A `-f` on an empty string is false too, but only by accident of the value.
for _h in "$HOOK_CLAUDE" "$HOOK_OPENHANDS"; do
  CASES_RUN=$((CASES_RUN + 1))
  grep -qE '^[[:space:]]+if \[\[ -n "\$REGEN_RESOLVER" \]\]' "$_h" \
    && pass "$(basename "$(dirname "$(dirname "$_h")")"): the retry is gated on a non-empty lookup" \
    || fail "$(basename "$(dirname "$(dirname "$_h")")"): the retry no longer consumes the lookup's result"
done

# mkplugin <name> <plugin-name> — a plugin root carrying a resolver and a manifest.
mkplugin() {
  local root="$SANDBOX/$1"; assert_fixture_dir "$root"
  mkdir -p "$root/scripts" "$root/.claude-plugin"
  printf '{\n  "name": "%s"\n}\n' "$2" > "$root/.claude-plugin/plugin.json"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$root/scripts/resolve-regenerable-conflicts.sh"
  (cd "$root" && pwd -P)
}
P_SOLEUR="$(mkplugin plugin-soleur soleur)"
P_OTHER="$(mkplugin plugin-other other)"

WD_BARE="$SANDBOX/wd-bare"; assert_fixture_dir "$WD_BARE"; mkdir -p "$WD_BARE"
WD_COPY="$SANDBOX/wd-copy"; assert_fixture_dir "$WD_COPY"
mkdir -p "$WD_COPY/plugins/soleur/scripts"
printf '#!/usr/bin/env bash\nexit 0\n' > "$WD_COPY/plugins/soleur/scripts/resolve-regenerable-conflicts.sh"

# lookup <work-dir> [plugin-root|-] -> the REGEN_RESOLVER the block selects. Run under the
# hooks' own `set -eo pipefail`, from $SANDBOX, so a relative CLAUDE_PLUGIN_ROOT resolves
# somewhere other than the work dir and an aborting line surfaces as rc != 0.
lookup() {
  local wd="$1" cpr="${2:--}"
  if [[ "$cpr" == "-" ]]; then
    (cd "$SANDBOX" && env -u CLAUDE_PLUGIN_ROOT WORK_DIR="$wd" bash -c 'set -eo pipefail; . "$1"; printf "%s" "$REGEN_RESOLVER"' _ "$SANDBOX/block.sh")
  else
    (cd "$SANDBOX" && CLAUDE_PLUGIN_ROOT="$cpr" WORK_DIR="$wd" bash -c 'set -eo pipefail; . "$1"; printf "%s" "$REGEN_RESOLVER"' _ "$SANDBOX/block.sh")
  fi
}

check() {  # <label> <expected> <work-dir> [plugin-root|-]
  local label="$1" want="$2" got rc=0
  got="$(lookup "${@:3}")" || rc=$?
  CASES_RUN=$((CASES_RUN + 1))
  if [[ "$rc" -eq 0 && "$got" == "$want" ]]; then pass "$label"
  else fail "$label: rc=$rc got=[$got] want=[$want]"; fi
}

check "AC8: a self-hosted repo (no in-repo copy) resolves the plugin's resolver" \
  "$P_SOLEUR/scripts/resolve-regenerable-conflicts.sh" "$WD_BARE" "$P_SOLEUR"
check "the plugin copy wins over the merged tree's copy when both exist" \
  "$P_SOLEUR/scripts/resolve-regenerable-conflicts.sh" "$WD_COPY" "$P_SOLEUR"
# The OTHER direction of the plan's AC4, documented rather than defended: with no plugin root in
# the environment the hook falls back to the in-repo copy -- this repository's own sessions,
# where the project hook runs without CLAUDE_PLUGIN_ROOT. A resolver loaded from there runs its
# sibling renderer from the same tree; no check inside the resolver can change that.
check "no CLAUDE_PLUGIN_ROOT: the in-repo copy is the fallback" \
  "$WD_COPY/plugins/soleur/scripts/resolve-regenerable-conflicts.sh" "$WD_COPY" -
check "a CLAUDE_PLUGIN_ROOT whose plugin.json does not name soleur is not used" \
  "$WD_COPY/plugins/soleur/scripts/resolve-regenerable-conflicts.sh" "$WD_COPY" "$P_OTHER"
check "neither source: the lookup is empty, so the retry is skipped (the deny stands)" \
  "" "$WD_BARE" -
check "a CLAUDE_PLUGIN_ROOT that does not exist neither aborts the hook nor resolves" \
  "" "$WD_BARE" "$SANDBOX/no-such-root"
check "a RELATIVE CLAUDE_PLUGIN_ROOT is absolutized before the hook cd's into the work dir" \
  "$P_SOLEUR/scripts/resolve-regenerable-conflicts.sh" "$WD_BARE" "plugin-soleur"

echo ""
echo "cases_run=$CASES_RUN passes=$passes fails=$fails ledger=${#FAILED[@]}"

_min_cases=10
if [[ "$CASES_RUN" -lt "$_min_cases" ]]; then
  printf '[FATAL] assertion floor: only %s case(s) ran, floor is %s\n' "$CASES_RUN" "$_min_cases" >&2; exit 1
fi
if [[ $((passes + fails)) -ne "$CASES_RUN" ]]; then
  printf '[FATAL] %s verdicts for %s cases — a case decided nothing\n' "$((passes + fails))" "$CASES_RUN" >&2; exit 1
fi
if [[ "${#FAILED[@]}" -ne "$fails" ]]; then
  printf '[FATAL] ledger/counter disagree: %s vs %s\n' "${#FAILED[@]}" "$fails" >&2; exit 1
fi
if [[ "${#FAILED[@]}" -ne 0 ]]; then
  printf '[FATAL] %s failing assertion(s):\n' "${#FAILED[@]}" >&2
  printf '  - %s\n' "${FAILED[@]}" >&2; exit 1
fi
echo "pre-merge-rebase-regen-lookup: all $passes assertions passed"
