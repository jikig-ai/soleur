#!/usr/bin/env bash
# boundary-prefix.test.sh — the #10248 shared wrapper-boundary fragment.
#
# Guard 2 (consumption census): every boundary-anchored gated-command regex in
#   .claude/hooks/{,lib/}*.sh + plugins/soleur/scripts/{,lib/}*.sh interpolates
#   ${SOLEUR_BOUNDARY_PFX — or, for variable-composed patterns, names a shared
#   atom (SOLEUR_BOUNDARY_PFX|SOLEUR_RTK_RE) at file level — or sits in the
#   justified-exemption registry below.
#   The site set is DERIVED by grep each run, never a member list.
#   Out of scope: plugins/soleur/hooks/, plugins/soleur/skills/*/scripts/ — a
#   future boundary gate there is invisible until the glob widens.
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
M "$GH_PR_MERGE" 'rtk run -- gh pr merge 5'            1 'rtk run -- gh pr merge (end-of-options marker, review F4)'
M "$GH_PR_MERGE" 'rtk -- run gh pr merge 5'            1 'rtk -- run gh pr merge (marker before exec word)'
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
  # No backslash on the var — inside this subshell it is genuinely unset, so
  # ${SOLEUR_BOUNDARY_PFX:-} expands to empty and the pattern under test is the
  # REAL fail-soft form `([[:space:]]+)*`. An escaped \${…} would paste the
  # literal text into the regex and make the verdicts coincidental (P2 fix).
  PFX_EMPTY_RE="(^|&&|\\|\\||;|[[:space:]]--[[:space:]])[[:space:]]*(${SOLEUR_BOUNDARY_PFX:-}[[:space:]]+)*gh[[:space:]]+pr[[:space:]]+merge([[:space:]]|$)"
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
trap 'rm -rf "$PG_TMP"' EXIT
( source "$REPO_ROOT/plugins/soleur/test/lib/git-fixture-env.sh" \
  && git_fixture_env "$PG_TMP" || exit 1
  git -C "$PG_TMP" init -q -b main && git -C "$PG_TMP" commit -q --allow-empty -m init ) || exit 2

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
#   guardrails.sh:231 — bare-[[:space:]] in the boundary alternation already
#     matches `rtk git …` / `rtk rm …` via the space.
#   guardrails.sh:705 — [^A-Za-z0-9_-] word-boundary class, space before `gh`
#     already satisfies it.
#   lib/incidents.sh:305-321 (detect_bypass: --no-verify / -c core.hooksPath= /
#     -c commit.gpgsign=false / --no-gpg-sign) — same bare-[[:space:]] boundary
#     class; `rtk git --no-verify` already matches via the space, pre-fragment.
#   incidents.test.sh:228/234/240 — test-internal assertion literals inside
#     strip_command_bodies cases (fixture text, not a gate pattern).
#   pre-closing-technical-fork-gate.test.sh:630 — a stderr-line regex
#     `(^|: )line [0-9]+:`; `rm ` inside `arm ` trips candidacy — not a
#     command boundary.
#   resolve-regenerable-conflicts.test.sh:719 — `_PUSH_RE` `[^-[:alnum:]]`
#     boundary: space before `git` already matches.
#   delegation-verify.sh:244,245,250,251,254,403 (is_denied / ops-prose DENY lists) — these are
#     refusal patterns over envelope TEXT, not gates on an executed command. Their boundary is the
#     negative class `[^[:alnum:]_-]`, which a space satisfies, so `rtk git push`, `sudo rm -rf` and
#     `X=1 gh secret` are already refused. Interpolating the wrapper-prefix atom would only NARROW
#     what the deny list catches, so the exemption is the safe disposition.
#   delegation-verify.sh:363 — `(^|[[:space:]])(-X|--method|-f|...)` anchors a FLAG on the gh api
#     argument list, not a command boundary; the `gh api` literal is a case label.
#   delegation-verify.test.sh:1217 — a deny_del fixture row (`--admin` pattern + the input text
#     `gh pr merge 123 --squash --admin`), test data not a gate pattern.
#   delegation-verify.test.sh:1260 — a mutation-kill row: the mutant replacement text for CMDPOS_RE
#     and the `gh workflow run` command it is run against, both test data not a gate pattern.
EXEMPTIONS=(
  ".claude/hooks/brand-hex-commit-gate.sh:119"
  ".claude/hooks/git-commit-secret-scan.sh:113"
  ".claude/hooks/guardrails.sh:231"
  ".claude/hooks/guardrails.sh:705"
  ".claude/hooks/lib/incidents.sh:305"
  ".claude/hooks/lib/incidents.sh:311"
  ".claude/hooks/lib/incidents.sh:316"
  ".claude/hooks/lib/incidents.sh:321"
  ".claude/hooks/incidents.test.sh:228"
  ".claude/hooks/pre-closing-technical-fork-gate.test.sh:630"
  ".claude/hooks/incidents.test.sh:234"
  ".claude/hooks/incidents.test.sh:240"
  "plugins/soleur/scripts/resolve-regenerable-conflicts.test.sh:719"
  "plugins/soleur/scripts/delegation-verify.sh:244"
  "plugins/soleur/scripts/delegation-verify.sh:245"
  "plugins/soleur/scripts/delegation-verify.sh:250"
  "plugins/soleur/scripts/delegation-verify.sh:251"
  "plugins/soleur/scripts/delegation-verify.sh:254"
  "plugins/soleur/scripts/delegation-verify.sh:363"
  "plugins/soleur/scripts/delegation-verify.sh:403"
  "plugins/soleur/scripts/delegation-verify.test.sh:1217"
  "plugins/soleur/scripts/delegation-verify.test.sh:1260"
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
# NOTE on the command vocabulary: the tail predicate is a closed literal list
# (gh|git|terraform|tofu|doppler|rm). A new boundary gate on an unlisted command
# (kubectl, aws, stripe) escapes derivation silently — extend the predicate when
# a gate on a new command lands; a loose tail that misses sites is the worst
# outcome for a drift guard.
# NOTE on the boundary shape: inline candidacy requires a literal `(^|`
# alternation — a site anchored on bare `^` (precommit-guard.sh COMMIT_RE) is
# not derivable; its consumption is instead backstopped by the integration rows
# above (a missing fragment reds `rtk git commit` → rc 1).
# lib/ is in scope: the carrier itself (incidents.sh detect_bypass) holds
# boundary-anchored git patterns — a census that cannot see its own carrier is
# the blind spot the review design-pass flagged.
CANDIDATES="$(
  for f in "$HOOKS_DIR"/*.sh "$HOOKS_DIR"/lib/*.sh "$SCRIPTS_DIR"/*.sh "$SCRIPTS_DIR"/lib/*.sh; do
    [[ -f "$f" ]] || continue
    rel="${f#"$REPO_ROOT"/}"
    awk -v file="$rel" '
      /^[[:space:]]*#/ { next }
      { line = $0; sub(/[[:space:]]#.*$/, "", line) }
      line ~ /\(\^\|/ && line ~ /(gh|git|terraform|tofu|doppler|rm)[ \\(\[|]/ { printf "%s:%d:inline\n", file, NR; next }
      # Variable-COMPOSED boundary patterns (review panel P1/P2): a gate whose
      # boundary alternation lives in a variable (ship-kb-archive-gate.sh
      # _MERGE_BOUNDARY/_MERGE_PREFIX) produces no `(^|`-and-literal line at all.
      # The usage line — a `${…BOUNDARY|PREFIX|PFX}` reference next to a gated
      # literal — is the candidate. `SOLEUR_` names are excluded: they are the
      # shared fragment itself, already judged by the inline arm above.
      line ~ /\$\{?[A-Za-z_]*(BOUNDARY|PREFIX)/ && line !~ /SOLEUR_/ && line ~ /(gh|git|terraform|tofu|doppler|rm)[ \\(\[|$]/ { printf "%s:%d:composed\n", file, NR }
    ' "$f"
  done
)"

CAND_COUNT=0; CONSUMING=0; UNCOVERED=""
declare -A CONSUMING_FILES=()
while IFS= read -r site; do
  [[ -n "$site" ]] || continue
  CAND_COUNT=$((CAND_COUNT + 1))
  file="${site%%:*}"; rest="${site#*:}"; lineno="${rest%%:*}"; kind="${rest##*:}"
  if [[ "$kind" == "composed" ]]; then
    # Composed consumption is FILE-level: the composed definition must name a
    # shared atom var. Non-comment lines only, so a commented-out reference
    # cannot fake provision.
    # awk one-pass — `grep -v | grep -q` under pipefail SIGPIPEs the producer
    # (early match closes the pipe, rc 141 reads as failure).
    if awk '/^[[:space:]]*#/ { next } /SOLEUR_(BOUNDARY_PFX|RTK_RE)/ { found=1 } END { exit !found }' "$REPO_ROOT/$file"; then
      CONSUMING=$((CONSUMING + 1))
      CONSUMING_FILES["$file"]=1
    elif is_exempt "${site%:*}"; then
      :
    else
      UNCOVERED+="$site"$'\n'
    fi
    continue
  fi
  # Strip the trailing comment EXACTLY as the candidacy scan does — a
  # `${SOLEUR_BOUNDARY_PFX` mentioned only inside a trailing comment must not
  # count as consumption (review design-pass P2: raw-line vs stripped-line asymmetry).
  line="$(sed -n "${lineno}p" "$REPO_ROOT/$file" | sed 's/[[:space:]]#.*$//')"
  if [[ "$line" == *'${SOLEUR_BOUNDARY_PFX'* || "$line" == *'$SOLEUR_BOUNDARY_PFX'* ]]; then
    CONSUMING=$((CONSUMING + 1))
    CONSUMING_FILES["$file"]=1
  elif is_exempt "${site%:*}"; then
    :
  else
    UNCOVERED+="$site"$'\n'
  fi
done <<<"$CANDIDATES"

echo "  census: $CAND_COUNT candidates, $CONSUMING consuming, ${#EXEMPTIONS[@]} exempt"

# Floor: the derived candidate set must be at least the known 36 (24 consumers +
# 12 exemptions) — a neutered scan that finds 0 sites reds here.
MIN_CANDIDATES=36
if [[ "$CAND_COUNT" -lt "$MIN_CANDIDATES" ]]; then
  printf '[FATAL] census floor: only %s boundary-anchored candidates found, floor is %s — the scan is neutered\n' "$CAND_COUNT" "$MIN_CANDIDATES" >&2
  exit 1
fi
assert_eq "" "$UNCOVERED" "every derived boundary-anchored gated-command site consumes \${SOLEUR_BOUNDARY_PFX} or is exempt$( [[ -n "$UNCOVERED" ]] && printf ' — uncovered:\n%s' "$UNCOVERED" )"

# Provision arm (review design-pass P2): interpolation is not provision. A
# consuming file that never sources the carrier greens the line-level census
# while running pre-#10248 matching forever — fail-soft makes it never-detected.
# Every consuming FILE must name a carrier path: incidents.sh (which nested-
# sources the lib) or wrapper-boundary.sh directly.
UNPROVISIONED=""
for file in "${!CONSUMING_FILES[@]}"; do
  # Comment-stripped: `# shellcheck source=lib/incidents.sh` is present in
  # every consumer and must not count as a live carrier source. awk one-pass —
  # `grep -v | grep -q` under pipefail SIGPIPEs the producer on early match.
  awk '/^[[:space:]]*#/ { next } /source.*(incidents\.sh|wrapper-boundary\.sh)/ { found=1 } END { exit !found }' "$REPO_ROOT/$file" \
    || UNPROVISIONED+="$file"$'\n'
done
assert_eq "" "$UNPROVISIONED" "every consuming file sources a carrier (incidents.sh or wrapper-boundary.sh)$( [[ -n "$UNPROVISIONED" ]] && printf ' — unprovisioned:\n%s' "$UNPROVISIONED" )"

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
MIN_CASES=54
if [[ $((PASS + FAIL)) -lt "$MIN_CASES" ]]; then
  printf '[FATAL] anti-vacuity: only %s assertions ran, floor is %s\n' "$((PASS + FAIL))" "$MIN_CASES" >&2
  exit 1
fi

print_results
