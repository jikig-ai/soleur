#!/usr/bin/env bash
# lint-integration-env-gates.sh -- fail when a `process.env.<VAR> ===|!== "1"` test
# gate in the tracked apps/web-platform/{test,lib} tree is never SET by a CI
# workflow, or when a file carrying one is never COLLECTED by a workflow that
# sets its gate.
#
# WHY (#9855): a `describe.skipIf(!process.env.<GATE>)` suite that no CI job
# un-gates passes vacuously forever -- strictly worse than no test, because the
# green summary reads as coverage. The pyramid census found ~40% of the
# integration layer in exactly that state: seven gate vars set nowhere under
# .github/ or scripts/. This file is the durability half of the fix -- the
# scheduled leg that exports the gates is .github/workflows/scheduled-integration-suites.yml.
#
# TWO ARMS, because the defect exists at two levels.
#
#   Var level: the var must appear in a SETTING POSITION in a workflow --
#   `env <VAR>=1` (run-prefix) or `<VAR>: ["']?1` (env-mapping) -- on a
#   non-comment line. A bare-token match is vacuous: tenant-integration.yml
#   carries `# TENANT_INTEGRATION_TEST=1 ...` INSIDE a header comment, so a
#   comment-only mention would certify unwired while the suite still skips.
#
#   File level: every FILE containing a gate must be collected by a workflow
#   that sets its gate -- the file's app-relative path, or its parent directory
#   at depth >= 2 (test/server/, trailing slash), must appear as a
#   whitespace/EOL-bounded token in that workflow. Measured live: on the tree
#   this file was added to, test/dsar-departed-member.integration.test.ts gated
#   on TENANT_INTEGRATION_TEST -- a WIRED var -- yet sat at test/ root while the
#   only CI invocation filtered to test/server/. Var-level coverage alone would
#   have reported it covered.
#
# THE PRODUCER IS `git grep` OVER THE WHOLE TRACKED test/ + lib/ TREES -- not a
# directory list. The `unit` vitest project collects `lib/**/*.test.ts` as well
# as `test/**/*.test.ts` (vitest.config.ts); a census scoped to test/ alone
# would miss a gate planted one directory over, which is the documented
# lint-orphan-test-suites lesson. The idiom is deliberately the canonical
# `===|!== "1"` shape only: presence-check gates (RLS_FUZZ_DATABASE_URL) and
# behaviour flags (SEO_AEO_SKIP_BUILD) are outside it BY DESIGN -- record
# widening as an edit to this header, not silent drift.
#
# THIS FILE HAS A COMPANION SUITE (scripts/lint-integration-env-gates.test.sh):
# a guard whose failure mode is "silently stops detecting" cannot be proved by
# reading it, so the battery mutates the tree underneath it.
#
# Allowlist entries carry a REASON and a tracking issue -- skipping is a
# recorded decision, not silent absorption.
#
# FIXTURE SEAM: SOLEUR_LINT_GATES_ROOT redirects the repo root (producer and
# consumer) so the companion battery can drive a scratch fixture repo. The
# root must be a real `git` work tree -- the producer is `git grep`, and a
# plain directory would enumerate ZERO gates and trip the anti-vacuity floor.
# (lint-orphan-test-suites.sh's BASH_SOURCE-derived root does not port to a
# fixture, hence the explicit override.)

set -euo pipefail
export LC_ALL=C

REPO_ROOT="${SOLEUR_LINT_GATES_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
WORKFLOW_DIR="$REPO_ROOT/.github/workflows"
PRODUCER_PATHS=(apps/web-platform/test apps/web-platform/lib)
GATE_IDIOM='process\.env\.[A-Z0-9_]+ *(===|!==) *"1"'

# var | reason -- the single chokepoint for exemptions. Every entry cites #9855,
# the issue that records why these vars are deliberate non-CI arms.
ALLOWLIST_VARS=(
  "RLS_FUZZ_LOCAL|wired via package.json test:rls-fuzz script prefix (RLS_FUZZ_LOCAL=1 vitest …), a wiring surface this grammar cannot see — allowlisted rather than grammar-widened (#9855)"
  "SOLEUR_ISOLATION_IN_IMAGE|in-image arm of test/sandbox-isolation.test.ts -- runs inside the runtime image, not GitHub CI (#9855)"
  "SOLEUR_ISOLATION_TEST_HOST|deliberate fail-loud host-capability opt-in; CI must not satisfy it (#9855)"
  "ANTHROPIC_ISOLATION_TEST_OK|manual opt-in for a host-level destructive arm (#9855)"
)

# repo-relative path | reason -- per-FILE exemptions from the collection arm,
# for gates collected via a non-path mechanism. Empty is the goal state.
ALLOWLIST_FILES=()

fails=0
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

_in_allowlist_vars() {
  local v="$1" row
  for row in ${ALLOWLIST_VARS[@]+"${ALLOWLIST_VARS[@]}"}; do
    [[ "${row%%|*}" == "$v" ]] && return 0
  done
  return 1
}

_in_allowlist_files() {
  local f="$1" row
  # ${a[@]+...} is load-bearing, not style: on bash <=4.3 (stock macOS bash
  # 3.2, the local lefthook/test-all.sh path) `"${EMPTY[@]}"` under `set -u` is
  # an unbound-variable abort -- and ALLOWLIST_FILES' goal state IS empty.
  for row in ${ALLOWLIST_FILES[@]+"${ALLOWLIST_FILES[@]}"}; do
    [[ "${row%%|*}" == "$f" ]] && return 0
  done
  return 1
}

# _var_set_in <var> <stripped-file> -- the ONE copy of the setting-position
# grammar. Two forms, both deliberately narrow:
#
#   (a) `env <VAR>=1` (or `env A=1 <VAR>=1 cmd`) run-prefix, where `env` must
#       be preceded by line-start, whitespace, `;`, or `-- `. A quote before
#       `env` (echo "env X=1 …", JSON bodies) is NOT a boundary -- a
#       string-literal mention is not a setting. A BARE `X=1 cmd` prefix with
#       no `env` keyword is deliberately NOT a setting form -- `env` is the
#       required spelling; 100% of live wiring uses it (measured 2026-10-10).
#   (b) `<VAR>: ["']?1` env-MAPPING, anchored to line start (optional `- `):
#       a `VAR: 1` token mid-line in a run: body (echo "VAR: 1", a curl JSON
#       body) is not an env-mapping and must not certify wiring.
#
# Accepted residual, documented: `env X="1"` quoted values and flow-map
# `env: {X: "1"}` spellings are NOT matched -- a maintainer who wires a gate
# that way gets a loud UNWIRED/UNCOVERED red, never a silent pass, and
# rewrites in the canonical form. package.json script prefixes
# (`RLS_FUZZ_LOCAL=1 vitest …` via `test:rls-fuzz`) are the known-blind
# wiring surface -- that class is allowlist territory.
_var_set_in() {
  local v="$1" stripped="$2"
  grep -qE "(^|[[:space:];]|--[[:space:]])env([[:space:]]+[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]+)*[[:space:]]+${v}=1([[:space:]]|$)|^[[:space:]]*(-[[:space:]]*)?${v}:[[:space:]]*[\"']?1[\"']?[[:space:]]*($|#)" \
    "$stripped"
}

# _path_token_in <path-token> <stripped-file> -- bounded-token match: the path
# must be preceded by line-start/whitespace (optional quote) and followed by
# whitespace, EOL, optional quote, or a YAML flow-list close `,` `)` `]`.
_path_token_in() {
  local tok="$1" stripped="$2" esc
  # Escape the FULL ERE metachar class -- a filename containing `|` or `+`
  # would otherwise WIDEN the match (alternation/quantifier) and false-cover.
  esc="$(printf '%s' "$tok" | sed 's/[][\.*^$+?(){}|]/\\&/g')"
  grep -qE "(^|[[:space:]])[\"']?${esc}[\"']?([[:space:]]|$|[,\)\]])" "$stripped"
}

# _workflow_files -- every workflow file, listed once. Keeping the file list
# explicit (not a recursive glob over the whole .github/) is deliberate: only
# this dir is a CI registration surface.
find "$WORKFLOW_DIR" -maxdepth 1 -type f \( -name '*.yml' -o -name '*.yaml' \) \
  | LC_ALL=C sort -u > "$WORK/workflows" || true

# Comment-stripped bodies, computed ONCE per file. Consumers grep the stripped
# copy -- never `grep -vE ... | grep -qE` inline: when -q exits on a first
# match the upstream strip dies of SIGPIPE (rc 141) and under pipefail the
# pipeline reports the var UNWIRED. Measured: TENANT_INTEGRATION_TEST flipped
# wired -> unwired between two identical runs on timing alone. An early
# `exit 0` in _var_wired_in's loop has the same hazard on the READ side, so it
# collects matches instead of short-circuiting.
mkdir -p "$WORK/stripped"
while IFS= read -r _wf; do
  [[ -n "$_wf" ]] || continue
  _b="$WORK/stripped/$(basename "$_wf")"
  grep -vE '^[[:space:]]*#' "$_wf" > "$_b" 2>/dev/null || true
done < "$WORK/workflows"

# _var_wired_in <var> -- prints the workflow files that SET <var> in a setting
# position on a non-comment line.
_var_wired_in() {
  local v="$1" f
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    if _var_set_in "$v" "$WORK/stripped/${f##*/}"; then
      printf '%s\n' "$f"
    fi
  done < "$WORK/workflows"
}

# _file_collected_in <app_rel_path> <workflow-file> -- the file (or its
# depth>=2 parent dir, trailing slash) appears whitespace/EOL-bounded.
_file_collected_in() {
  local app_rel="$1" wf="$2" parent stripped
  stripped="$WORK/stripped/${wf##*/}"
  _path_token_in "$app_rel" "$stripped" && return 0
  # Walk ANCESTOR dirs, deepest first: a file under test/server/scope-grants/
  # IS collected by a `test/server/` filter. Depth >= 2 only (a dir token must
  # contain a `/` after its leading segment): `test/` alone must NOT satisfy a
  # file whose parent is test/ -- `test/server/` in a run line must not cover a
  # sibling at test/ root. The trailing slash is required so the token is a
  # directory filter.
  parent="$(dirname "$app_rel")"
  while [[ "$parent" == */* ]]; do
    _path_token_in "$parent/" "$stripped" && return 0
    parent="$(dirname "$parent")"
  done
  return 1
}

# --- The producer -------------------------------------------------------------
# Per-file, not per-var: the census that feeds BOTH arms. `-l` first, then the
# var names per file -- a file can carry more than one gate (MU1 carries the
# partial-set canary). Source extensions ONLY: a `process.env.X === "1"`
# literal in prose (test/README.md documents the idiom) can never gate a
# suite, and counting it is a false UNCOVERED. NON-.test source files
# (helpers/fixtures) stay in the census -- a gate inside test/helpers/*.ts is
# vacuous exactly as much as one in a suite -- but they are exempt from the
# file-level collection arm below: vitest collects *.test.* only, so a helper
# is exercised through its importers, and "no workflow path-filter names this
# helper" is the CORRECT shape, not a defect.
git -C "$REPO_ROOT" grep -lE "$GATE_IDIOM" -- "${PRODUCER_PATHS[@]}" \
  | grep -E '\.(ts|tsx)$' \
  | LC_ALL=C sort -u > "$WORK/gated_files" || true
found_files=$(wc -l < "$WORK/gated_files" | tr -d ' ')
COLLECTABLE_RE='\.test\.'

# PRODUCER FLOOR (anti-vacuity). 59 source files measured 2026-10-10 on the
# adding commit (60 pre-source-filter incl. test/README.md, which quotes the
# idiom). A count floor cannot see a SUBSTITUTION, only a narrowing -- that is
# what the zero-check and the companion battery's row-2 mutation cover. Slack
# deliberately tight: a floor is attack budget, not padding.
MIN_GATED_FILES=50
if (( found_files == 0 )); then
  echo "ERROR: the gate census enumerated ZERO files -- a vacuous producer is not a clean tree." >&2
  fails=$((fails + 1))
elif (( found_files < MIN_GATED_FILES )); then
  echo "ERROR: the gate census enumerated ${found_files} files, below the floor of ${MIN_GATED_FILES} -- the producer is narrowed or broken, so every 'covered' verdict below certified a SUBSET." >&2
  fails=$((fails + 1))
fi

# --- Both arms ----------------------------------------------------------------
uncovered=0
wired_vars=0
allowlisted_vars=0

# Build "file -> vars" once: for each gated file, the gate vars it carries.
: > "$WORK/file_vars"
while IFS= read -r f; do
  [[ -n "$f" ]] || continue
  # `|| true`: a file deleted between the census and this pass (TOCTOU) makes
  # the second git grep exit 1; skip the file rather than die mid-loop.
  vars="$(git -C "$REPO_ROOT" grep -hoE "$GATE_IDIOM" -- "$f" 2>/dev/null \
    | sed -E 's/.*process\.env\.([A-Z0-9_]+).*/\1/' | LC_ALL=C sort -u | tr '\n' ' ' || true)"
  vars="${vars% }"
  [[ -n "$vars" ]] || continue
  printf '%s\t%s\n' "$f" "$vars" >> "$WORK/file_vars"
done < "$WORK/gated_files"

# Var-level pass over DISTINCT vars once (TENANT_INTEGRATION_TEST alone sits
# on ~38 files — per-file evaluation re-scanned every workflow ~38x for the
# same answer). Persists wired_map as `var<TAB>workflow` rows; the file-level
# pass consumes the map instead of re-scanning all workflows per file.
: > "$WORK/var_wired"; : > "$WORK/wired_map"
cut -f2- "$WORK/file_vars" | tr ' ' '\n' | LC_ALL=C sort -u > "$WORK/distinct_vars"
while IFS= read -r v; do
  [[ -n "$v" ]] || continue
  _in_allowlist_vars "$v" && continue
  # $(...) capture, never `| head -1`: head closes the pipe early and the
  # function dies on SIGPIPE writing a SECOND match (rc 141 -> pipefail ->
  # reads UNWIRED). Deterministic once a var gains a second wiring file.
  wfs="$(_var_wired_in "$v")"
  if [[ -n "$wfs" ]]; then
    printf '%s\n' "$v" >> "$WORK/var_wired"
    while IFS= read -r wf; do
      [[ -n "$wf" ]] && printf '%s\t%s\n' "$v" "$wf" >> "$WORK/wired_map"
    done <<< "$wfs"
  else
    printf 'UNWIRED\t%s\n' "$v" >> "$WORK/var_wired"
  fi
done < "$WORK/distinct_vars"
LC_ALL=C sort -u -o "$WORK/var_wired" "$WORK/var_wired"

allowlisted_vars=$(printf '%s\n' "${ALLOWLIST_VARS[@]}" | wc -l | tr -d ' ')
wired_vars=$(grep -vc '^UNWIRED' "$WORK/var_wired" || true)

# File-level pass. A file is covered iff (a) every var it carries is
# allowlisted, or (b) SOME workflow both collects the file AND sets every
# non-allowlisted var on it -- skipIf is a conjunction, so a workflow that sets
# only one of two gates still leaves the suite dormant in that file.
while IFS=$'\t' read -r f vars; do
  app_rel="${f#apps/web-platform/}"
  _in_allowlist_files "$f" && continue
  # Non-collectable source files (helpers, fixtures -- anything that is not a
  # *.test.* vitest target) are var-level-only: no path filter can name them,
  # and their coverage runs through the suites that import them.
  grep -qE "$COLLECTABLE_RE" <<<"$app_rel" || continue
  covered=0
  all_allowlisted=1
  for v in $vars; do
    _in_allowlist_vars "$v" || { all_allowlisted=0; break; }
  done
  if (( all_allowlisted == 1 )); then
    covered=1
  else
    # Candidates = workflows setting EVERY non-allowlisted var on this file
    # (intersection of wired_map rows); collection is then checked on the
    # intersection only -- the conjunction is already enforced by membership.
    candidates=""
    first=1
    for v in $vars; do
      _in_allowlist_vars "$v" && continue
      vws="$(awk -F'\t' -v v="$v" '$1 == v { print $2 }' "$WORK/wired_map")"
      if [[ -z "$vws" ]]; then
        candidates=""
        break
      fi
      if (( first == 1 )); then
        candidates="$vws"
        first=0
      else
        candidates="$(comm -12 \
          <(printf '%s\n' "$candidates" | LC_ALL=C sort -u) \
          <(printf '%s\n' "$vws" | LC_ALL=C sort -u))"
        [[ -n "$candidates" ]] || break
      fi
    done
    while IFS= read -r wf; do
      [[ -n "$wf" ]] || continue
      _file_collected_in "$app_rel" "$wf" && { covered=1; break; }
    done <<< "$candidates"
  fi
  if (( covered == 0 )); then
    uncovered=$((uncovered + 1))
    echo "UNCOVERED: $f (gates: $vars)" >&2
  fi
done < "$WORK/file_vars"

# Var-level uncovered report (a var with no wiring marks every file on it
# uncovered above; report the var once so the cause is named). `|| true` is
# load-bearing: under pipefail a zero-match grep rc=1 would kill the script
# before the summary line -- the fixture green case hits exactly that.
while IFS=$'\t' read -r _ v; do
  echo "UNWIRED-VAR: $v -- present in no setting position under .github/workflows/ and not allowlisted" >&2
done < <(grep '^UNWIRED' "$WORK/var_wired" || true)
unwired_n=$(grep -c '^UNWIRED' "$WORK/var_wired" || true)

echo "env-gates: found=${found_files} wired=${wired_vars} allowlisted=${allowlisted_vars} uncovered=${uncovered}"

if (( fails > 0 || uncovered > 0 || unwired_n > 0 )); then
  exit 1
fi
exit 0
