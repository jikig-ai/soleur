#!/usr/bin/env bash
# boundary-prefix.test.sh — the #10248 shared wrapper-boundary fragment.
#
# Guard 2 (consumption census): every boundary-anchored gated-command regex in
#   .claude/hooks/*.sh + plugins/soleur/scripts/*.sh interpolates
#   ${SOLEUR_BOUNDARY_PFX — or sits in the justified-exemption registry below.
#   The site set is DERIVED by grep each run, never a member list.
#
# Guard 3 (fragment semantics): the both-directions behavioral matrix —
#   `boundary + (atom space)* + gated-cmd` matches iff every interposed word is a
#   legal prefix atom. String-payload flags are NOT atoms: `rtk run -c 'gh pr
#   merge'` must not match (the opaque-payload lexical-limit class).
#
# Auto-discovered by the `scripts` group glob in scripts/test-all.sh.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
LIB="$REPO_ROOT/plugins/soleur/scripts/lib/wrapper-boundary.sh"
HOOKS_DIR="$REPO_ROOT/.claude/hooks"
SCRIPTS_DIR="$REPO_ROOT/plugins/soleur/scripts"

echo "=== boundary-prefix: shared wrapper-boundary fragment (#10248) ==="
echo ""

# --- instrument self-test ---------------------------------------------------
# Both helpers must record before any row runs (ADR-193: a neutered assert
# helper folds every row into silence). Printed via printf + exit 1, never
# routed through the helpers it verifies.
{ assert_eq "x" "x" "self-test ok"; } >/dev/null 2>&1
if [[ "$PASS" -ne 1 || "$FAIL" -ne 0 ]]; then
  printf '[FATAL] instrument self-test: assert_eq did not record a pass\n' >&2
  exit 1
fi
{ assert_eq "x" "y" "self-test fail"; } >/dev/null 2>&1
if [[ "$PASS" -ne 1 || "$FAIL" -ne 1 ]]; then
  printf '[FATAL] instrument self-test: assert_eq did not record a fail\n' >&2
  exit 1
fi
PASS=0; FAIL=0

# --- load the fragment ------------------------------------------------------
assert_file_exists "$LIB" "wrapper-boundary.sh exists"
# Source hygiene: an inherited env value must not masquerade as the loaded
# fragment — consumers unset before sourcing (incidents.sh, precommit-guard.sh);
# the sentinel is what suites assert, never a bare [[ -n ]].
SOLEUR_BOUNDARY_PFX="poisoned-inherited-value"
SOLEUR_BOUNDARY_PFX_LOADED=""
if [[ -f "$LIB" ]]; then
  unset SOLEUR_ENV_ASN_RE SOLEUR_LAUNCHER_RE SOLEUR_RTK_RE SOLEUR_BOUNDARY_PFX SOLEUR_BOUNDARY_PFX_LOADED
  # shellcheck source=/dev/null
  source "$LIB"
fi
assert_eq "1" "${SOLEUR_BOUNDARY_PFX_LOADED:-0}" "SOLEUR_BOUNDARY_PFX_LOADED sentinel set by the lib"
assert_contains "${SOLEUR_BOUNDARY_PFX:-missing}" "rtk" "boundary prefix fragment contains the rtk atom"
assert_contains "${SOLEUR_BOUNDARY_PFX:-missing}" "sudo" "boundary prefix fragment contains the launcher atom"
assert_contains "${SOLEUR_BOUNDARY_PFX:-missing}" "A-Za-z_" "boundary prefix fragment contains the env-assignment atom"
if [[ "$FAIL" -gt 0 ]]; then print_results; fi

# --- Guard 3: fragment semantics (the both-directions matrix) ---------------
# The consumption idiom per plan: (<boundary>)[[:space:]]*(PFX[[:space:]]+)*<gated-cmd>.
# A representative gated family per site class; the sites' own test files carry
# per-site smoke rows proving the interpolation happened at each site.
BOUNDARY='(^|&&|\|\||;|[[:space:]]--[[:space:]])'
pfx() { printf '%s[[:space:]]*(%s[[:space:]]+)*%s' "$BOUNDARY" "${SOLEUR_BOUNDARY_PFX}" "$1"; }

# match/no-match verdict helper — count-form, never `! grep -q` (a pattern-compile
# rc 2 must not fold into "no match").
M() {  # M <ere> <line> <expected-count> <label>
  local got rc
  got="$(grep -cE "$1" <<<"$2" 2>/dev/null)" && rc=0 || rc=$?
  if [[ "$rc" -eq 2 ]]; then
    assert_eq "compile" "rc2" "$4 (pattern failed to compile)"
    return
  fi
  assert_eq "$3" "$got" "$4"
}

echo "-- must-match rows (wrapper spellings reach the gated command) --"
GH_PR_MERGE="$(pfx 'gh[[:space:]]+pr[[:space:]]+merge([[:space:]]|$)')"
GIT_COMMIT="$(pfx 'git([[:space:]]+(-C[[:space:]]+[^[:space:]]+|-c[[:space:]]+[^[:space:]]+|--git-dir=[^[:space:]]+|--git-dir[[:space:]]+[^[:space:]]+|-[A-Za-z]))*[[:space:]]+commit([[:space:]]|$)')"
GIT_STASH="$(pfx 'git[[:space:]]+stash')"
GH_ISSUE="$(pfx 'gh[[:space:]]+issue[[:space:]]+create')"
GIT_PUSH_MAIN="$(pfx 'git[[:space:]]+push([[:space:]]+(-f|--force(-with-lease)?))?[[:space:]]+origin[[:space:]]+(main|master|HEAD:main|HEAD:master)([[:space:]]|;|\)|&|$)')"
TF_APPLY="$(pfx '(terraform|tofu)[[:space:]]+apply([[:space:]]|;|\)|&|$)')"

M "$GH_PR_MERGE" 'rtk gh pr merge 5'                    1 'rtk gh pr merge (bare rtk passthrough)'
M "$GH_PR_MERGE" 'rtk run gh pr merge 5'               1 'rtk run gh pr merge'
M "$GH_PR_MERGE" 'rtk -v run gh pr merge 5'            1 'rtk -v run gh pr merge (global pre-subcommand)'
M "$GH_PR_MERGE" 'rtk run --skip-env gh pr merge 5'    1 'rtk run --skip-env gh pr merge (global post-subcommand)'
M "$GH_PR_MERGE" 'rtk run --skip-env=ci gh pr merge 5' 1 'rtk run --skip-env=<v> gh pr merge (=value form)'
M "$GH_PR_MERGE" 'sudo rtk gh pr merge 5'              1 'sudo rtk gh pr merge (launcher + rtk compose)'
M "$GH_PR_MERGE" 'X=1 rtk gh pr merge 5'               1 'X=1 rtk gh pr merge (env-asn + rtk compose)'
M "$GH_PR_MERGE" 'sudo X=1 rtk run gh pr merge 5'      1 'mixed atoms compose (sudo + env + rtk run)'
M "$GH_PR_MERGE" 'foo && rtk gh pr merge 5'            1 'chained: && rtk gh pr merge'
M "$GH_PR_MERGE" 'foo -- rtk gh pr merge 5'            1 'after -- boundary: rtk gh pr merge'
M "$GH_PR_MERGE" 'xargs rtk gh pr merge 5'             1 'xargs rtk gh pr merge'
M "$GH_PR_MERGE" 'gh pr merge 5'                       1 'bare gh pr merge still matches (no regression)'
M "$GH_PR_MERGE" 'sudo gh pr merge 5'                  1 'sudo gh pr merge (pre-existing launcher)'

M "$GIT_COMMIT" 'rtk git commit -m x'                  1 'rtk git commit'
M "$GIT_COMMIT" 'rtk run git commit -m x'              1 'rtk run git commit'
M "$GIT_COMMIT" 'LEFTHOOK=0 rtk git commit -m x'       1 'env + rtk git commit'
M "$GIT_COMMIT" 'git commit -m x'                      1 'bare git commit still matches'

M "$GIT_STASH"  'rtk git stash'                        1 'rtk git stash'
M "$GH_ISSUE"   'rtk gh issue create --title x'        1 'rtk gh issue create'
M "$GIT_PUSH_MAIN" 'rtk git push origin main'          1 'rtk git push origin main'
M "$TF_APPLY"   'rtk terraform apply'                  1 'rtk terraform apply'

echo ""
echo "-- must-not-match rows (the anchor stays faithful both directions) --"
M "$GH_PR_MERGE" 'echo "gh pr merge"'                  0 'echo "gh pr merge" (quoted text, raw input)'
M "$GH_PR_MERGE" "rtk run -c 'gh pr merge'"            0 "rtk run -c 'gh pr merge' (string payload — lexical-limit class)"
M "$GH_PR_MERGE" 'rtk summary --shell "gh pr merge"'   0 'rtk summary --shell (string payload)'
M "$GIT_COMMIT"  "rtk summary 'git commit'"            0 "rtk summary 'git commit' (quoted positional)"
M "$GH_PR_MERGE" 'rtk unknown gh pr merge'             0 'rtk unknown gh pr merge (unknown word stops the prefix)'
M "$GH_PR_MERGE" 'rtk-foo gh pr merge'                 0 'rtk-foo gh pr merge (glued suffix is not rtk)'
M "$GH_PR_MERGE" 'artk gh pr merge'                    0 'artk gh pr merge (glued prefix is not rtk)'
M "$GH_PR_MERGE" 'mygit commit && gh pr merge 5'       1 'chained real merge after non-gated words still matches'
M "$GIT_COMMIT"  'sudox git commit'                    0 'sudox git commit (glued launcher suffix)'
M "$GIT_COMMIT"  'FOO git commit'                      0 'FOO git commit (no = is not env-asn)'
M "$GH_PR_MERGE" 'rtk -x gh pr merge'                  0 'rtk -x gh pr merge (unknown option word)'
M "$GH_PR_MERGE" 'cat gh pr merge'                     0 'cat gh pr merge (gh is argv, not command — pre-existing shape)'
# The [|;&]-class boundary (guardrails.sh:145 / precommit COMMIT_RE shape) covers
# a single `|` — assert the prefix loop composes there too.
PIPE_GIT_COMMIT="(^|[|;&])[[:space:]]*(${SOLEUR_BOUNDARY_PFX}[[:space:]]+)*git([[:space:]]+(-[A-Za-z]))*[[:space:]]+commit([[:space:]]|$)"
M "$PIPE_GIT_COMMIT" 'printf "x" | rtk git commit -F -'  1 'pipe boundary: rtk git commit reaches the commit gate'
M "$PIPE_GIT_COMMIT" 'printf "x" | git commit -F -'      1 'pipe boundary: bare git commit still matches'
M "$GH_PR_MERGE" 'gh pr mergeable'                     0 'gh pr mergeable (terminator keeps word boundary)'

echo ""
echo "-- fail-soft rows (fragment unset ⇒ identical pre-fix matching) --"
# Run in a subshell with the var actually unset — the lib was sourced above, so
# testing the degradation path needs its absence, not a stand-in name.
(
  unset SOLEUR_BOUNDARY_PFX
  PFX_EMPTY_RE="(^|&&|\\|\\||;|[[:space:]]--[[:space:]])[[:space:]]*(\${SOLEUR_BOUNDARY_PFX:-}[[:space:]]+)*gh[[:space:]]+pr[[:space:]]+merge([[:space:]]|$)"
  echo "bare:$(grep -cE "$PFX_EMPTY_RE" <<<'gh pr merge 5' || true)"
  echo "rtk:$(grep -cE "$PFX_EMPTY_RE" <<<'rtk gh pr merge 5' || true)"
) > /tmp/bp-failsoft.$$ 2>/dev/null
assert_eq "bare:1" "$(grep -oE 'bare:[0-9]+' /tmp/bp-failsoft.$$)" 'unset PFX: bare gh pr merge still matches'
assert_eq "rtk:0" "$(grep -oE 'rtk:[0-9]+' /tmp/bp-failsoft.$$)" 'unset PFX: rtk-prefixed spelling misses (pre-fix behavior)'
rm -f /tmp/bp-failsoft.$$

# --- integration: precommit-guard.sh consumes the sibling lib (#10248 AC) -----
# The plan's pin: `precommit-guard.sh 'rtk git commit'` must refuse (exit 1) on
# main, keep refusing the bare spelling, and still work from a plugin-cache-
# shaped layout (script + lib/ sibling, no .claude/ tree) — the path that made
# scripts/lib/ the fragment's home instead of .claude/hooks/lib/.
GUARD="$SCRIPTS_DIR/precommit-guard.sh"
PG_TMP="$(mktemp -d)"; assert_fixture_dir "$PG_TMP"
git -C "$PG_TMP" init -q -b main && git -C "$PG_TMP" commit -q --allow-empty -m init

_rc=0; bash "$GUARD" --cwd "$PG_TMP" 'rtk git commit' >/dev/null 2>&1 || _rc=$?
assert_eq "1" "$_rc" "precommit-guard refuses 'rtk git commit' on main"

_rc=0; bash "$GUARD" --cwd "$PG_TMP" 'git commit' >/dev/null 2>&1 || _rc=$?
assert_eq "1" "$_rc" "precommit-guard still refuses the bare 'git commit' on main"

_rc=0; bash "$GUARD" --cwd "$PG_TMP" 'rtk run -c git commit' >/dev/null 2>&1 || _rc=$?
assert_eq "0" "$_rc" "precommit-guard does not see through rtk -c payload (declared lexical-limit class)"

# Cache-shaped layout: only scripts/ + scripts/lib/ exist, no .claude/ tree.
mkdir -p "$PG_TMP/cache/scripts/lib"
cp "$GUARD" "$PG_TMP/cache/scripts/precommit-guard.sh"
cp "$LIB" "$PG_TMP/cache/scripts/lib/wrapper-boundary.sh"
_rc=0; bash "$PG_TMP/cache/scripts/precommit-guard.sh" --cwd "$PG_TMP" 'rtk git commit' >/dev/null 2>&1 || _rc=$?
assert_eq "1" "$_rc" "precommit-guard refuses 'rtk git commit' from plugin-cache-shaped layout"

# And the fail-soft arm: lib ABSENT beside the script → warn on stderr, pre-fix
# matching (bare commit still refused, rtk spelling misses — status quo).
rm -f "$PG_TMP/cache/scripts/lib/wrapper-boundary.sh"
_rc=0; _err="$(bash "$PG_TMP/cache/scripts/precommit-guard.sh" --cwd "$PG_TMP" 'git commit' 2>&1 >/dev/null)" || _rc=$?
assert_eq "1" "$_rc" "precommit-guard without the lib still refuses bare 'git commit' on main"
grep -qF 'wrapper-boundary.sh unavailable' <<<"$_err" \
  && assert_eq 1 1 "precommit-guard without the lib warns (headless_or_stderr arm)" \
  || assert_eq 1 0 "precommit-guard without the lib warns (headless_or_stderr arm)"
rm -rf "$PG_TMP"

# --- Guard 2: consumption census --------------------------------------------
# Derive the candidate set: non-comment lines in the two dirs carrying a chain
# boundary alternation `(^|` AND a gated-command literal. Comment-stripped scan
# (grep-rewrite.test.sh:295 / _strip_comments idiom); verdicts are count-form.
echo ""
echo "-- consumption census (derived site set, not a member list) --"

# Justified exemptions — file:line with a reason. Each entry must still exist on
# disk AND the exemption is positional (a moved line re-enters the census).
#   brand-hex-commit-gate.sh:119, git-commit-secret-scan.sh:113,
#   guardrails.sh:228 — bare-[[:space:]] in the boundary alternation already
#     matches `rtk git …` / `rtk rm …` via the space.
#   guardrails.sh:702 — [^A-Za-z0-9_-] word-boundary class, space before `gh`
#     already satisfies it.
#   incidents.test.sh:228/234/240 — test-internal assertion literals inside
#     strip_command_bodies cases (fixture text, not a gate pattern).
#   resolve-regenerable-conflicts.test.sh:719 — `_PUSH_RE` `[^-[:alnum:]]`
#     boundary: space before `git` already matches.
EXEMPTIONS=(
  ".claude/hooks/brand-hex-commit-gate.sh:119"
  ".claude/hooks/git-commit-secret-scan.sh:113"
  ".claude/hooks/guardrails.sh:230"
  ".claude/hooks/guardrails.sh:704"
  ".claude/hooks/incidents.test.sh:228"
  ".claude/hooks/incidents.test.sh:234"
  ".claude/hooks/incidents.test.sh:240"
  "plugins/soleur/scripts/resolve-regenerable-conflicts.test.sh:719"
)

is_exempt() {
  local site="$1" e
  for e in "${EXEMPTIONS[@]}"; do [[ "$site" == "$e" ]] && return 0; done
  return 1
}

# Candidate: non-comment line containing `(^|` AND a gated-command literal
# followed by a word-ish edge (space, backslash-escape, paren, bracket, pipe).
# Deliberately loose: the exemption registry dispositions residue; a tight
# predicate that misses a site is the worst outcome.
CANDIDATES="$(
  for f in "$HOOKS_DIR"/*.sh "$SCRIPTS_DIR"/*.sh; do
    [[ -f "$f" ]] || continue
    rel="${f#"$REPO_ROOT"/}"
    awk -v file="$rel" '
      /^[[:space:]]*#/ { next }
      { line = $0; sub(/[[:space:]]#.*$/, "", line) }
      line ~ /\(\^\|/ && line ~ /(gh|git|terraform|tofu|doppler|rm)[ \\(\[|]/ { printf "%s:%d\n", file, NR }
    ' "$f"
  done
)"

CAND_COUNT=0; CONSUMING=0; UNCOVERED=""
while IFS= read -r site; do
  [[ -n "$site" ]] || continue
  CAND_COUNT=$((CAND_COUNT + 1))
  file="${site%:*}"; lineno="${site##*:}"
  line="$(sed -n "${lineno}p" "$REPO_ROOT/$file")"
  if [[ "$line" == *'${SOLEUR_BOUNDARY_PFX'* || "$line" == *'$SOLEUR_BOUNDARY_PFX'* ]]; then
    CONSUMING=$((CONSUMING + 1))
  elif is_exempt "$site"; then
    :
  else
    UNCOVERED+="$site"$'\n'
  fi
done <<<"$CANDIDATES"

echo "  census: $CAND_COUNT candidates, $CONSUMING consuming, ${#EXEMPTIONS[@]} exempt"

# Floor: the derived candidate set must be at least the known 28 (20 consumers +
# 8 exemptions) — a neutered scan that finds 0 sites reds here.
MIN_CANDIDATES=28
if [[ "$CAND_COUNT" -lt "$MIN_CANDIDATES" ]]; then
  printf '[FATAL] census floor: only %s boundary-anchored candidates found, floor is %s — the scan is neutered\n' "$CAND_COUNT" "$MIN_CANDIDATES" >&2
  exit 1
fi
assert_eq "" "$UNCOVERED" "every derived boundary-anchored gated-command site consumes \${SOLEUR_BOUNDARY_PFX} or is exempt$( [[ -n "$UNCOVERED" ]] && printf ' — uncovered:\n%s' "$UNCOVERED" )"

# Exemption hygiene: every registry entry names a file that exists and whose
# cited line still carries the candidate shape (stale exemptions must not
# silently pass — Guard 2 mutation row 4).
STALE=""
for e in "${EXEMPTIONS[@]}"; do
  ef="${e%:*}"; el="${e##*:}"
  if [[ ! -f "$REPO_ROOT/$ef" ]]; then STALE+="$e (file gone)"$'\n'; continue; fi
  eline="$(sed -n "${el}p" "$REPO_ROOT/$ef" | sed 's/[[:space:]]#.*$//')"
  if grep -qE '\(\^\|' <<<"$eline" && grep -qE '(gh|git|terraform|tofu|doppler|rm)[ \\(\[|]' <<<"$eline"; then
    :
  else
    STALE+="$e (line no longer candidate-shaped)"$'\n'
  fi
done
assert_eq "" "$STALE" "every exemption entry still names a live candidate line$( [[ -n "$STALE" ]] && printf ' — stale:\n%s' "$STALE" )"

# --- assertion floor ---------------------------------------------------------
MIN_CASES=51
if [[ $((PASS + FAIL)) -lt "$MIN_CASES" ]]; then
  printf '[FATAL] anti-vacuity: only %s assertions ran, floor is %s\n' "$((PASS + FAIL))" "$MIN_CASES" >&2
  exit 1
fi

print_results
