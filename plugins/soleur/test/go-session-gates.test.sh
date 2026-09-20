#!/usr/bin/env bash
# go-session-gates.test.sh — Guard 1 for #8308.
#
# PROPERTY. With no CLAUDE_PLUGIN_ROOT, GROK_PLUGIN_ROOT or CLAUDE_PROJECT_DIR in the
# environment, each of the three `plugins/soleur/commands/go.md` gate fences, AS THE LOADER
# DELIVERS IT, dispatches to the Soleur payload script at the verified root and emits a
# SOLEUR_PLUGIN_ROOT_RESOLVE line naming the arm that produced it; an undelivered fence, an
# unverified root, a missing payload, an ambient decoy environment, or a cloud session never
# reaches a dispatch.
#
# ASSEMBLY. The three ```bash fences under `## Step 0.0: Workspace Readiness Gate`,
# `## Step 0.5: Cloud Mode detection` and `## Step 0: Session-Start Preamble`. Members are
# extracted by HEADING ANCHOR, never by line number, and the count is asserted: != 3 fences,
# or any empty extracted body, is a FAIL and never a skip (ADR-177 — a suite that could not
# run is UNRESOLVED, not passed).
#
# The loader's delivery transform is modelled by `deliver`, pinned by row H1 to
# `arm4-probe/arm5-delivered.txt` — a capture from a headless `claude -p --plugin-dir` run
# (#8308 Phase 0 / Arm 5). Stated precisely, because the weaker claim is the true one: that
# file is ADDED BY THIS DIFF, and H1 reads its comparison root back out of the capture's own
# `BARE=` line, so the pin is self-consistent whatever that path is. What it establishes is
# that the transform is context-free text replacement (the probe body is a QUOTED heredoc, so
# bash expanded nothing — anything substituted came from the loader). Commit discipline, not
# structure, is what keeps both sides from being edited together. Row H3 bypasses the
# simulator entirely and is the only row that does.
#
# Verdict accounting is the fixture-relative-assert.test.sh TRIPLE-CHECK: counters, an
# append-only VERDICT_LOG ledger, and an exit-time floor with the LEDGER as the authority.
# Moving a verdict between counters is free; appending to the ledger is not.

set -euo pipefail

REPO_ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
# shellcheck source=../../../plugins/soleur/test/test-helpers.sh
source "${REPO_ROOT}/plugins/soleur/test/test-helpers.sh"

GO_MD="${REPO_ROOT}/plugins/soleur/commands/go.md"
PAYLOAD="${REPO_ROOT}/plugins/soleur"
ARM5_DELIVERED="${REPO_ROOT}/knowledge-base/project/specs/feat-one-shot-7450-git-root-anchor-untrusted/arm4-probe/arm5-delivered.txt"
PROBE_MD="${REPO_ROOT}/knowledge-base/project/specs/feat-one-shot-7450-git-root-anchor-untrusted/arm4-probe/commands/zzzprobe.md"

BASH_BIN="$(command -v bash)"
[ -n "$BASH_BIN" ] || { echo "FATAL: no bash on PATH" >&2; exit 2; }

TMP_ROOT=$(mktemp -d -t gosessiongates.XXXXXXXX) || { echo "FATAL: no scratch root" >&2; exit 2; }
: "${TMP_ROOT:?refusing to proceed without a scratch root}"
assert_fixture_dir "${TMP_ROOT}"
trap 'rm -rf "$TMP_ROOT"' EXIT

passes=0; fails=0; asserted=0
VERDICT_LOG="$TMP_ROOT/verdicts.txt"; : > "$VERDICT_LOG"
pass() { echo "  PASS: $1"; echo "PASS" >> "$VERDICT_LOG"; passes=$((passes + 1)); }
fail() { echo "  FAIL: $1"; echo "FAIL" >> "$VERDICT_LOG"; fails=$((fails + 1)); }
ck()   { asserted=$((asserted + 1)); }

# ck+verdict in one call. `want_in`/`want_not_in` are the two shapes every row uses.
want_in()     { ck; case "$1" in *"$2"*) pass "$3" ;; *) fail "$3 (missing: $2)" ;; esac; }
want_not_in() { ck; case "$1" in *"$2"*) fail "$3 (present: $2)" ;; *) pass "$3" ;; esac; }
want_eq()     { ck; if [ "$1" = "$2" ]; then pass "$3"; else fail "$3 (got '$1', want '$2')"; fi; }

GATE_ANCHORS=(
  "## Step 0.0: Workspace Readiness Gate"
  "## Step 0.5: Cloud Mode detection"
  "## Step 0: Session-Start Preamble"
)
GATE_NAMES=(readiness cloud-detect session-start)
# Each gate's own skip marker when the root VERIFIES but its dispatch target is absent (R6c),
# and when nothing resolved at all (R4). Step 0.5 has no `absent-from-verified-root` spelling —
# `script-unreachable` is its equivalent, and asserting the real string beats asserting a
# uniformity the file does not have.
GATE_ABSENT_MARKERS=(
  "SOLEUR_GIT_REPO_DIAG source=probe-unreachable reason=absent-from-verified-root"
  "SOLEUR_CLOUD_DETECT_SKIPPED reason=script-unreachable"
  "SOLEUR_SESSION_START_SKIPPED reason=absent-from-verified-root"
)
GATE_UNVERIFIED_MARKERS=(
  "SOLEUR_GIT_REPO_DIAG source=probe-unreachable reason=plugin-root-unverified"
  "SOLEUR_CLOUD_DETECT_SKIPPED reason=plugin-root-unverified"
  "SOLEUR_SESSION_START_SKIPPED reason=plugin-root-unverified"
)

# --- helpers ---------------------------------------------------------------------------------

# extract_fence <heading-anchor> <file>
#
# FLAG-BASED, never an `/A/,/B/` range address: a range opens AND closes on the start line
# whenever the end pattern matches it, silently yielding an empty body that every downstream
# assertion then passes over. The fence bookkeeping is `extract_gate_anchor()`'s from
# plugins/soleur/skills/incident/test/redact-sentinel.test.sh with only the inner match changed;
# It handles leading whitespace. It does NOT handle an info string (the pattern is anchored to
# end-of-line, so ```` ```bash title=x ```` does not match), nor `~~~`, nor CRLF — R10 asserts
# go.md carries none of those rather than assuming it. An earlier version of this comment
# credited the info-string handling to `extract_gate_anchor`; that property belongs to
# `exec_lines`, a different helper in the same file, and neither source has it.
#
# The heading match is WHOLE-LINE equality, not `index($0, anchor) == 1`. A prefix match still
# matched `## Step 0.5: Cloud Mode detection (renamed)`, so mutation row 14 -- renaming a gate
# heading -- SURVIVED: the extractor still found three fences and R10's count check never fired.
extract_fence() {
  awk -v anchor="$1" '
    $0 == anchor && !seen { seen = 1; next }
    !seen { next }
    !infence && /^[[:space:]]*```bash[[:space:]]*$/ { infence = 1; next }
    infence && /^[[:space:]]*```/ { exit }
    infence { print }
  ' "$2"
}

# count_fences <file> — how many gate fences the extractor actually finds (R10).
count_fences() {
  local f="$1" n=0 a
  for a in "${GATE_ANCHORS[@]}"; do
    if [ -n "$(extract_fence "$a" "$f")" ]; then n=$((n + 1)); fi
  done
  printf '%s' "$n"
}

# deliver <root> — stdin -> stdout, replacing ONLY the exact literal ${CLAUDE_PLUGIN_ROOT}.
# Measured 2026-09-19 on both harnesses (Arm 5): the transform is exact-literal replacement of
# the braced token, so `${CLAUDE_PLUGIN_ROOT:-x}` and `$CLAUDE_PLUGIN_ROOT` survive unchanged.
# Row H1 is the self-test of exactly that, pinned to a capture this diff did not produce.
deliver() {
  local root="$1" body
  body="$(cat)"
  printf '%s\n' "${body//'${CLAUDE_PLUGIN_ROOT}'/$root}"
}

# resolver_snippet <fence-body> — the bytes between the resolver anchors, exclusive (R8).
resolver_snippet() {
  printf '%s\n' "$1" | awk '
    /^# --- soleur plugin-root resolver/ { inr = 1; next }
    inr && /^# --- end resolver ---/     { exit }
    inr { print }
  '
}

# code_lines <fence-body> — the fence body with comment-only lines stripped (R9). Prose and
# comments legitimately NAME the banned tokens ("never default to ./plugins/soleur" is in a
# fence comment on main), so an unscoped absence grep false-fails a correct file. The
# fence-scoping TECHNIQUE is redact-sentinel.test.sh's `exec_lines`; that suite scans the three
# SECRET gates, not go.md, so this is a pattern copied rather than coverage inherited.
# NOTE on `<<<"$var"` throughout this file rather than `printf … | grep -q`: under
# `set -o pipefail` an early `grep -q` match closes the pipe, the producer takes SIGPIPE (141),
# and the pipeline's non-zero status makes the `if` read FALSE — so a NEGATIVE guard fails OPEN.
# The ban and portability rows are the highest-value static rows in this file.
code_lines() { printf '%s\n' "$1" | grep -vE '^[[:space:]]*#' || true; }

# mk_root <dir> <manifest-name> [absent-gate]
#
# Every fixture file is written from a QUOTED heredoc. Heredoc bodies are invisible to
# plugins/soleur/test/lib/fixture-scan.py, which is what keeps the two row-by-row-equality
# baselines from churning by more than this file's own existence.
mk_root() {
  local dir="$1" name="$2" absent="${3:-}"
  assert_fixture_dir "$dir"
  mkdir -p "$dir/.claude-plugin" "$dir/scripts" "$dir/skills/git-worktree/scripts"
  cat > "$dir/.claude-plugin/plugin.json" <<MANIFEST_EOF
{ "name": "${name}", "description": "go-session-gates fixture root" }
MANIFEST_EOF
  [ "$absent" = cloud-detect ] || cp "${PAYLOAD}/scripts/cloud-detect.sh" "$dir/scripts/cloud-detect.sh"
  [ "$absent" = readiness ] || cp "${PAYLOAD}/skills/git-worktree/scripts/git-repo-readiness-diag.sh" \
    "$dir/skills/git-worktree/scripts/git-repo-readiness-diag.sh"
  # STUB, never the real manager: the real one reaches `git push origin --delete`,
  # `git branch -D` and `reset --hard HEAD` for merged branches with no worktree.
  if [ "$absent" != session-start ]; then
    cat > "$dir/skills/git-worktree/scripts/worktree-manager.sh" <<'STUB_EOF'
#!/usr/bin/env bash
echo "STUB_WORKTREE_MANAGER argv=$*"
STUB_EOF
    chmod +x "$dir/skills/git-worktree/scripts/worktree-manager.sh"
  fi
}

# mk_decoy_root <dir> <manifest-name> — every script announces itself, so "did the gate execute
# a root it should have refused" is observable rather than inferred.
mk_decoy_root() {
  local dir="$1" name="$2"
  assert_fixture_dir "$dir"
  mkdir -p "$dir/.claude-plugin" "$dir/scripts" "$dir/skills/git-worktree/scripts"
  cat > "$dir/.claude-plugin/plugin.json" <<MANIFEST_EOF
{ "name": "${name}", "description": "go-session-gates DECOY root" }
MANIFEST_EOF
  local s
  for s in "$dir/scripts/cloud-detect.sh" \
           "$dir/skills/git-worktree/scripts/git-repo-readiness-diag.sh" \
           "$dir/skills/git-worktree/scripts/worktree-manager.sh"; do
    # Writes a LEDGER as well as stdout. Step 0's session-class gate consumes cloud-detect.sh's
    # stdout into a `case`, so a stdout-only marker is invisible there — and "the decoy ran but
    # we could not see it" would have read as "the decoy did not run", which is the opposite
    # verdict on the one row that documents the preflight's limitation.
    cat > "$s" <<'DECOY_EOF'
#!/usr/bin/env bash
echo "DECOY_EXECUTED $0 $*"
[ -n "${SOLEUR_DECOY_LOG:-}" ] && echo "DECOY_EXECUTED $0" >> "$SOLEUR_DECOY_LOG"
exit 0
DECOY_EOF
    chmod +x "$s"
  done
}

# mk_workspace <dir> — a temp git repo on `main` whose committed .mcp.json DIFFERS from the
# working copy, so Step 0's restore is observable rather than vacuous.
mk_workspace() {
  local dir="$1"
  assert_fixture_dir "$dir"
  mkdir -p "$dir"
  # `name || { … }`, not `if ! name; then`. Both are CHECKED calls and Guard 5's assertion 4
  # accepts either, but fixture-env-adoption.test.sh's out-of-scope counter derives helper
  # calls with `(^|[;&|`]|$\()[[:space:]]*git_fixture_env`, which the `if ! ` prefix defeats --
  # so the `if` form reads as adoption to one arm of that file and as NON-adoption to the
  # other, and the second arm is the one with the ratchet. Measured: it took the ceiling
  # 25 -> 26.
  git_fixture_env "$dir" || {
    echo "FATAL: git_fixture_env refused to build an environment for $dir" >&2
    exit 2
  }
  git -C "$dir" init -q -b main
  cat > "$dir/.mcp.json" <<'MCP_EOF'
{"fixture":"main"}
MCP_EOF
  git -C "$dir" add .mcp.json
  git -C "$dir" commit -q -m "fixture"
  cat > "$dir/.mcp.json" <<'MCP_EOF'
{"fixture":"working-copy-differs"}
MCP_EOF
}

# DEVIN* scrub list, built from the live environment rather than a hand-listed set.
devin_unsets() {
  local v
  while IFS='=' read -r v _; do
    case "$v" in DEVIN*) printf -- '-u\n%s\n' "$v" ;; esac
  done < <(env)
}
mapfile -t DEVIN_UNSET < <(devin_unsets)

# run_gate <fence-file> <workspace> <home> [VAR=VALUE ...]
#
# Composes the repo's two env forms: `env -u` to UNSET (redact-sentinel.test.sh's
# `VAR=value "$BASH_BIN"` prefix only overrides) and an explicit HOME on scratch in EVERY row,
# so the Devin CLI-cache arm can never reach a developer's real cache.
# A FIXED path, assigned once at top level. Every caller runs `out="$(run_gate ...)"`, and a
# command substitution is a SUBSHELL — an assignment inside run_gate never reaches the parent,
# so `decoy_ran` read an empty variable and answered "none" for every row, including the ones
# whose whole job is to detect execution. Measured: R6 and R7 passed VACUOUSLY that way while
# R6b, the must-PASS row, was the only one loud enough to notice. Truncation inside the
# subshell is fine — it acts on the file, not on a variable.
DECOY_LOG=""
run_gate() {
  local fence="$1" ws="$2" home="$3"; shift 3
  : > "$DECOY_LOG"
  ( cd "$ws" && env -u CLAUDE_PLUGIN_ROOT -u GROK_PLUGIN_ROOT -u CLAUDE_PROJECT_DIR \
      "${DEVIN_UNSET[@]}" HOME="$home" "SOLEUR_DECOY_LOG=$DECOY_LOG" "$@" \
      "$BASH_BIN" "$fence" 2>&1 ) || true
}
decoy_ran() { [ -s "$DECOY_LOG" ] && printf 'DECOY_EXECUTED' || printf 'none'; }

SCRATCH_HOME="$TMP_ROOT/home"; mkdir -p "$SCRATCH_HOME"
DECOY_LOG="$TMP_ROOT/decoy-ran.log"; : > "$DECOY_LOG"

# --- R10 (part 1): the extractor answered, or nothing below means anything --------------------
echo "R10. extractor integrity (asserted BEFORE any row that depends on it)"
ck; if [ -f "$GO_MD" ]; then pass "go.md exists"; else fail "go.md missing at $GO_MD"; exit 2; fi
want_eq "$(count_fences "$GO_MD")" "${#GATE_ANCHORS[@]}" "R10: every declared gate anchor yields a fence"
# The four tables below are parallel by construction and every row indexes all four. Without
# this, adding a member to one silently desyncs the rest and every loop quietly covers N-1 of N.
for _arr in GATE_NAMES GATE_ABSENT_MARKERS GATE_UNVERIFIED_MARKERS; do
  # A nameref, not `eval "_n=\${#${_arr}[@]}"` — same result, but shellcheck can see the
  # assignment (the eval form draws SC2154) and there is no quoting surface to get wrong.
  declare -n _ref="$_arr"
  want_eq "${#_ref[@]}" "${#GATE_ANCHORS[@]}" "R10: $_arr has one member per gate anchor"
  unset -n _ref
done
# A FOURTH gate fence added to go.md is invisible to a check that only counts the anchors we
# already declared — measured: appending a `## Step 0.9` fence carrying the #8061 form, a CWD
# default AND `set -u` left this suite at 137/0/137, because count_fences only ever looks where
# GATE_ANCHORS points. Count the bash fences in the WHOLE file instead: every one of them is a
# gate, so a new fence must either join the declared set or red this row.
_go_fences="$(grep -c '^```bash$' "$GO_MD" || true)"
want_eq "$_go_fences" "${#GATE_ANCHORS[@]}" "R10: go.md carries no bash fence outside the declared gate anchors"
ck; if grep -q '~~~' "$GO_MD"; then fail "R10: go.md uses a ~~~ fence the extractor cannot see"; else pass "R10: no ~~~ fences"; fi
ck; if grep -q $'\r' "$GO_MD"; then fail "R10: go.md carries CR bytes the extractor cannot see"; else pass "R10: no CRLF"; fi

declare -a FENCE_LITERAL
for i in "${!GATE_ANCHORS[@]}"; do
  body="$(extract_fence "${GATE_ANCHORS[$i]}" "$GO_MD")"
  ck; if [ -n "$body" ]; then pass "R10: ${GATE_NAMES[$i]} fence body non-empty"; else fail "R10: ${GATE_NAMES[$i]} fence body EMPTY"; fi
  f="$TMP_ROOT/fence-${GATE_NAMES[$i]}.sh"; printf '%s\n' "$body" > "$f"
  FENCE_LITERAL[$i]="$f"
done

# --- R8: the three resolver snippets are one artifact, not three -----------------------------
echo "R8. resolver byte-identity across the three fences"
check_r8() {
  local file="$1" label="$2" i b s
  local -a snip
  for i in "${!GATE_ANCHORS[@]}"; do
    b="$(extract_fence "${GATE_ANCHORS[$i]}" "$file")"
    snip[$i]="$(resolver_snippet "$b")"
  done
  ck; if [ -n "${snip[0]}" ] && [ -n "${snip[1]}" ] && [ -n "${snip[2]}" ]; then
    pass "$label: all three resolver snippets present between the anchors"
  else
    fail "$label: a resolver snippet is EMPTY (0=${#snip[0]} 1=${#snip[1]} 2=${#snip[2]} bytes)"
  fi
  ck; if [ "${snip[0]}" = "${snip[1]}" ]; then pass "$label: readiness == cloud-detect"; else fail "$label: readiness != cloud-detect"; fi
  ck; if [ "${snip[1]}" = "${snip[2]}" ]; then pass "$label: cloud-detect == session-start"; else fail "$label: cloud-detect != session-start"; fi
  for i in "${!GATE_ANCHORS[@]}"; do
    # OCCURRENCES, not matching lines -- the sibling at the Devin-cache row already documents
    # this trap and this row was written with the wrong idiom anyway.
    s="$(printf '%s\n' "${snip[$i]}" | grep -oF '${CLAUDE_PLUGIN_ROOT}' | grep -c . || true)"
    want_eq "$s" "1" "$label: ${GATE_NAMES[$i]} snippet holds the loader token exactly once"
  done
}
check_r8 "$GO_MD" "R8"

# --- R9: banned forms, shell options, portability, telemetry hygiene, arm placement ----------
echo "R9. static bans over fence CODE lines (comments stripped)"
check_r9() {
  local file="$1" label="$2" i body code all_code=""
  for i in "${!GATE_ANCHORS[@]}"; do
    body="$(extract_fence "${GATE_ANCHORS[$i]}" "$file")"
    code="$(code_lines "$body")"
    all_code="${all_code}${code}"$'\n'

    # Shell options: `set -u` would abort the resolver BEFORE it prints its own marker, which is
    # the silent-skip class this whole change exists to remove.
    # A CHARACTER CLASS, not an enumeration of spellings. Measured: the enumerated form
    # `-(e|u|eu|euo|o)\b` CAUGHT `set -euo pipefail`/`set -u`/`set -o pipefail` and EVADED
    # `set -ue` and `set -eo pipefail` -- and `set -ue` is precisely the `-u` this bans.
    # `\b` is also a GNU extension, in a guard whose own R9 bans non-POSIX constructs.
    ck; if grep -qE '(^|[[:space:];])set +[-+]([a-z]*[eu][a-z]*|o[[:space:]])' <<<"$code"; then
      fail "$label: ${GATE_NAMES[$i]} fence enables a set option"
    else
      pass "$label: ${GATE_NAMES[$i]} fence enables no set -e/-u/-o pipefail"
    fi

    # The two Devin cache paths belong to Step 0.5 ALONE. Copying them into Step 0 would make
    # the MUTATING gate newly reachable on a harness where it has always skipped.
    local n_cache
    # OCCURRENCES, not matching lines: both cache paths sit on one `for d in ...` line, so a
    # line count reports 1 for a correct fence and the row would false-fail forever.
    n_cache="$(printf '%s\n' "$code" | grep -oE 'devin/cli/plugins/cache|/opt/\.devin/plugins' | grep -c . || true)"
    ck; if [ "${GATE_NAMES[$i]}" = cloud-detect ]; then
      if [ "$n_cache" -ge 2 ]; then pass "$label: Step 0.5 carries both Devin cache paths"; else fail "$label: Step 0.5 is missing a Devin cache path (found $n_cache)"; fi
    else
      if [ "$n_cache" -eq 0 ]; then pass "$label: ${GATE_NAMES[$i]} carries no Devin cache path"; else fail "$label: ${GATE_NAMES[$i]} carries a Devin cache path ($n_cache)"; fi
    fi

    # The marker must never carry the resolved path: keeps filesystem paths out of telemetry,
    # which is what makes the plan's GDPR assessment true.
    local echoed
    echoed="$(printf '%s\n' "$code" | grep -F 'SOLEUR_PLUGIN_ROOT_RESOLVE' || true)"
    ck; if [ -z "$echoed" ]; then
      fail "$label: ${GATE_NAMES[$i]} emits no SOLEUR_PLUGIN_ROOT_RESOLVE line"
    elif grep -qE '\$\{?ROOT\}?' <<<"$echoed"; then
      fail "$label: ${GATE_NAMES[$i]} RESOLVE line interpolates the resolved path"
    else
      pass "$label: ${GATE_NAMES[$i]} RESOLVE line carries no path"
    fi
  done

  # Banned expansion forms. An unbraced $CLAUDE_PLUGIN_ROOT is NOT substituted by the loader
  # (Arm 5, both harnesses), so it reaches bash and resolves against ambient environment.
  #
  # The predicate is the PLAIN LITERAL, not the plan's drafted `/\$CLAUDE_PLUGIN_ROOT(?!\})/`.
  # Two things are true and the plan's parenthetical asserted the first about the second:
  #   - `${CLAUDE_PLUGIN_ROOT}` does NOT contain the substring `$CLAUDE_PLUGIN_ROOT` (the
  #     character after the `$` is `{`), so a bare literal match cannot self-trip on the
  #     canonical token -- the reason the plan gave for adding the lookahead does not hold.
  #   - `${GROK_PLUGIN_ROOT:-$CLAUDE_PLUGIN_ROOT}` DOES contain it, followed by `}`. So the
  #     drafted `(?!\})` lookahead would have excluded the exact #8061 form this guard exists
  #     to ban, and the guard would have been vacuous on its own defect. Measured: the
  #     lookahead-equivalent ERE scored PASS against unmodified go.md.
  local b
  for b in '$CLAUDE_PLUGIN_ROOT' '${CLAUDE_PLUGIN_ROOT:' ':-./plugins/soleur' ':-plugins/soleur'; do
    ck; if grep -qF -- "$b" <<<"$all_code"; then
      fail "$label: banned form '$b' in fence code"
    else
      pass "$label: no '$b' in fence code"
    fi
  done
  # Portability: none of these is on stock macOS in the form used here.
  for b in 'xargs -r' 'readlink -f' 'stat -c' 'sed -i' 'timeout '; do
    ck; if grep -qF -- "$b" <<<"$all_code"; then
      fail "$label: non-POSIX '$b' in fence code"
    else
      pass "$label: no '$b' in fence code"
    fi
  done
}
check_r9 "$GO_MD" "R9"

# --- R3b: the dispatch operands name files that still exist ----------------------------------
# R3's stub proves the fence COMPUTED a path, never that the real script is still there — the
# 2026-02-22 cleanup-merged-path-mismatch class.
echo "R3b. \${ROOT}-relative dispatch operands resolve under plugins/soleur/"
r3b_n=0
for i in "${!GATE_ANCHORS[@]}"; do
  body="$(extract_fence "${GATE_ANCHORS[$i]}" "$GO_MD")"
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    r3b_n=$((r3b_n + 1))
    ck; if [ -f "${PAYLOAD}/${rel}" ]; then
      pass "R3b: ${GATE_NAMES[$i]} operand plugins/soleur/${rel} exists"
    else
      fail "R3b: ${GATE_NAMES[$i]} operand plugins/soleur/${rel} does NOT exist"
    fi
  done < <(code_lines "$body" | grep -oE '\$\{ROOT\}/[A-Za-z0-9_./-]+' | sed 's|^\${ROOT}/||' | sort -u)
done
ck; if [ "$r3b_n" -ge 3 ]; then pass "R3b: found $r3b_n \${ROOT}-relative operands (>=3)"; else fail "R3b: only $r3b_n \${ROOT}-relative operands found; the extraction found nothing to check"; fi

# --- behavioural rows -------------------------------------------------------------------------
FIX_ROOT="$TMP_ROOT/root-ok";        mk_root "$FIX_ROOT" soleur
DECOY_EVIL="$TMP_ROOT/root-evil";    mk_decoy_root "$DECOY_EVIL" evil
DECOY_CLAIM="$TMP_ROOT/root-claim";  mk_decoy_root "$DECOY_CLAIM" soleur

delivered_fence() {
  # TWO `local` statements, deliberately. Word expansion happens before `local` takes effect,
  # so `${GATE_NAMES[$i]}` inside the SAME `local` resolves against the OUTER `i` -- measured:
  # `A=(x y z); f(){ local i="$1" out="p-${A[$i]}-q"; echo "$out"; }; i=0; f 2` prints `p-x-q`.
  # Every caller but one sits in a `for i in …` loop where the two coincide, which is what hid
  # it; the D self-test passes a literal and wrote fence 0's body to a session-start filename.
  local i="$1"
  local root="$2" out="$TMP_ROOT/delivered-${GATE_NAMES[$i]}-$3.sh"
  deliver "$root" < "${FENCE_LITERAL[$i]}" > "$out"
  printf '%s' "$out"
}
fresh_ws() { local d="$TMP_ROOT/ws-$1"; rm -rf "$d"; mk_workspace "$d"; printf '%s' "$d"; }

echo "D. decoy-ledger instrument self-test"
: > "$DECOY_LOG"
want_eq "$(decoy_ran)" "none" "D: an empty ledger reads as 'none'"
ws="$(fresh_ws dself)"
out="$(run_gate "$(delivered_fence 0 "$DECOY_CLAIM" claim)" "$ws" "$SCRATCH_HOME")"
want_eq "$(decoy_ran)" "DECOY_EXECUTED" "D: a decoy that ran is visible to the PARENT shell"

echo "R1/R2/R3. delivered -> verified fixture root, environment unset"
R1_EXPECT=(
  "SOLEUR_PLUGIN_ROOT_RESOLVE gate=readiness source=plugin-root-token verified=true"
  "SOLEUR_PLUGIN_ROOT_RESOLVE gate=cloud-detect source=plugin-root-token verified=true"
  "SOLEUR_PLUGIN_ROOT_RESOLVE gate=session-start source=plugin-root-token verified=true"
)
R1_EFFECT=("SOLEUR_GIT_REPO_READY=true" "not-local:no-devin-env" "STUB_WORKTREE_MANAGER argv=cleanup-merged")
for i in "${!GATE_ANCHORS[@]}"; do
  ws="$(fresh_ws "r$i")"
  out="$(run_gate "$(delivered_fence "$i" "$FIX_ROOT" ok)" "$ws" "$SCRATCH_HOME")"
  want_in "$out" "${R1_EXPECT[$i]}" "R$((i+1)): ${GATE_NAMES[$i]} resolves via the loader token"
  want_in "$out" "${R1_EFFECT[$i]}" "R$((i+1)): ${GATE_NAMES[$i]} reached its dispatch"
  want_not_in "$out" "${GATE_UNVERIFIED_MARKERS[$i]}" "R$((i+1)): ${GATE_NAMES[$i]} emits no skip marker"
  if [ "$i" = 2 ]; then
    ck; if [ "$(cat "$ws/.mcp.json")" = "$(git -C "$ws" show main:.mcp.json)" ]; then
      pass "R3: .mcp.json restored from main"
    else
      fail "R3: .mcp.json NOT restored (working copy still differs from main)"
    fi
  fi
done

echo "R3d. .mcp.json is never truncated when main does not carry one"
# The P1 this suite did not cover: `git show main:.mcp.json > .mcp.json` truncates the target
# before forking, so a repo whose main has no .mcp.json ended up with a 0-byte file, silently,
# rc 0. THIS repo tracks one, which is why every fixture had one and nobody saw it.
ws="$(fresh_ws r3d)"
# `:?`, not a bare use. `fresh_ws` runs `mk_workspace`, whose `assert_fixture_dir` failure path
# is `exit 2` — but it runs inside THIS command substitution, so that exit kills the SUBSHELL
# and the parent continues with ws="". The next line would then be `git -C "" rm --cached`,
# which git resolves against the CALLER's repository: it would unstage this repo's own
# .mcp.json and commit the removal. `${ws:?}` aborts the parent, which is the only scope that
# can stop it. (P1a flags exactly these two writes; the read-only sites above are unaffected.)
# No apostrophe in the :? word. Measured on bash 5.3.15: inside "${v:?word}" an unpaired '
# opens a single-quote context that runs past the closing brace, and the parse dies ~80 lines
# later on an unrelated "(" with no hint of the real cause.
: "${ws:?fresh_ws r3d produced no workspace path; refusing to run git against the caller repo}"
# In a SUBSHELL with the fixture environment, because these two run in the PARENT shell and
# `fresh_ws` cannot hand its environment back: `mk_workspace` calls `git_fixture_env` inside
# `$(fresh_ws …)`, so the exports die with that command substitution. Without them `git commit`
# has no identity, and a runner with no global `user.email` — every CI runner — aborts with
# `fatal: empty ident name`, taking the whole suite down at this row. Measured on CI run
# 35483661921: 149 rows PASS locally, `[FAIL] go-session-gates.test.sh (255ms)` in CI, and
# every row after R3d never executed. The subshell is what keeps the ceiling and the pinned
# identity from leaking into H3's real-harness run further down.
(
  git_fixture_env "$ws" || { echo "FATAL: git_fixture_env refused an environment for $ws" >&2; exit 2; }
  git -C "$ws" rm -q --cached .mcp.json
  git -C "$ws" commit -q -m "main carries no .mcp.json"
) || { echo "FATAL: R3d fixture setup failed" >&2; exit 2; }
printf '%s' '{"local":"customer-edits"}' > "$ws/.mcp.json"
out="$(run_gate "$(delivered_fence 2 "$FIX_ROOT" ok)" "$ws" "$SCRATCH_HOME")"
want_eq "$(cat "$ws/.mcp.json")" '{"local":"customer-edits"}' "R3d: a local .mcp.json survives when main has none"
want_in "$out" "SOLEUR_SESSION_START_SKIPPED reason=mcp-json-absent-on-main" "R3d: and the skip is reported, not swallowed"
ck; if [ -e "$ws/.mcp.json.soleur-tmp" ]; then fail "R3d: the temp file was left behind"; else pass "R3d: no temp file left behind"; fi

echo "R3f. the .mcp.json restore does not depend on worktree-manager.sh"
# Added at ship time on an advisor finding. The restore was NESTED inside the
# `[ -f worktree-manager.sh ]` arm, so a verified-but-torn root missing that one script
# skipped the restore too and the only marker named the reaper. That is the #8308 coupling in
# miniature, and no row saw it: R6c asserts the reaper did NOT dispatch and says nothing about
# .mcp.json, so decoupling left the suite byte-identical at 149/0. This row is what makes the
# two independent.
NOMGR="$TMP_ROOT/root-no-manager"; mk_root "$NOMGR" soleur session-start
ws="$(fresh_ws r3f)"
out="$(run_gate "$(delivered_fence 2 "$NOMGR" nomgr)" "$ws" "$SCRATCH_HOME")"
want_in "$out" "SOLEUR_SESSION_START_SKIPPED reason=absent-from-verified-root" "R3f: the absent reaper is still reported"
want_not_in "$out" "STUB_WORKTREE_MANAGER" "R3f: and nothing was dispatched for it"
want_eq "$(cat "$ws/.mcp.json")" "$(git -C "$ws" show main:.mcp.json)" "R3f: the restore ran anyway"

echo "R3g. a git show failure names the cause it MEASURED, not the first of three (AP-021)"
# `git show main:.mcp.json` fails for at least three reasons and the marker asserted one of
# them for all three. This drives the arm the old spelling got WRONG: a repo with no local
# `main` at all. R3d already covers "main exists, carries no .mcp.json".
ws="$(fresh_ws r3g)"
: "${ws:?fresh_ws r3g produced no workspace path; refusing to run git against the caller repo}"
(
  git_fixture_env "$ws" || { echo "FATAL: git_fixture_env refused an environment for $ws" >&2; exit 2; }
  git -C "$ws" branch -m main notmain
) || { echo "FATAL: R3g fixture setup failed" >&2; exit 2; }
out="$(run_gate "$(delivered_fence 2 "$FIX_ROOT" ok)" "$ws" "$SCRATCH_HOME")"
want_in "$out" "SOLEUR_SESSION_START_SKIPPED reason=mcp-json-no-local-main" "R3g: names the missing branch"
want_not_in "$out" "reason=mcp-json-absent-on-main" "R3g: and does NOT claim main lacks the file"
ck; if [ -e "$ws/.mcp.json.soleur-tmp" ]; then fail "R3g: the temp file was left behind"; else pass "R3g: no temp file left behind"; fi

echo "R3h. the verdict is the classifier's FIRST stdout line, and trailing output is ignored"
# `SESSION_VERDICT="$(… | head -1)"` assumes cloud-detect.sh's non-banner stdout leads with the
# verdict. R2 drives the REAL script (one line) and R3c a one-line stub, so neither can tell
# `head -1` from `tail -1` — both pass under either. This stub prints the verdict first and
# noise after, which only `head -1` reads correctly.
NOISY="$TMP_ROOT/root-noisy-classifier"; mk_root "$NOISY" soleur
cat > "$NOISY/scripts/cloud-detect.sh" <<'NOISY_EOF'
#!/usr/bin/env bash
echo "local"
echo "note: some future diagnostic line"
NOISY_EOF
chmod +x "$NOISY/scripts/cloud-detect.sh"
ws="$(fresh_ws r3h)"
out="$(run_gate "$(delivered_fence 2 "$NOISY" noisy)" "$ws" "$SCRATCH_HOME")"
want_in "$out" "STUB_WORKTREE_MANAGER argv=cleanup-merged" "R3h: a leading 'local' verdict proceeds despite trailing output"
want_not_in "$out" "SOLEUR_SESSION_START_SKIPPED reason=cloud-session" "R3h: and the trailing line is not read as the verdict"

echo "R3e. a verified root whose CLASSIFIER is absent is reported distinctly"
# SESSION_PROBE=absent had no row: mk_root's absent=session-start drops only worktree-manager.sh.
CLASSLESS="$TMP_ROOT/root-no-classifier"; mk_root "$CLASSLESS" soleur cloud-detect
ws="$(fresh_ws r3e)"
out="$(run_gate "$(delivered_fence 2 "$CLASSLESS" noclass)" "$ws" "$SCRATCH_HOME")"
want_in "$out" "SOLEUR_SESSION_START_SKIPPED reason=classifier-absent" "R3e: names the ABSENT CLASSIFIER, not the absent manager"
want_not_in "$out" "STUB_WORKTREE_MANAGER" "R3e: dispatches nothing without a session class"

echo "R3c. session-class gate: a not-local verdict never reaches cleanup-merged"
CLOUD_ROOT="$TMP_ROOT/root-cloud"; mk_root "$CLOUD_ROOT" soleur
cat > "$CLOUD_ROOT/scripts/cloud-detect.sh" <<'CLOUD_EOF'
#!/usr/bin/env bash
echo "not-local:sentinel-absent"
CLOUD_EOF
chmod +x "$CLOUD_ROOT/scripts/cloud-detect.sh"
ws="$(fresh_ws r3c)"
out="$(run_gate "$(delivered_fence 2 "$CLOUD_ROOT" cloud)" "$ws" "$SCRATCH_HOME")"
want_in "$out" "SOLEUR_SESSION_START_SKIPPED reason=cloud-session verdict=not-local:sentinel-absent" "R3c: cloud session skips session-start, naming the verdict"
want_not_in "$out" "STUB_WORKTREE_MANAGER" "R3c: cleanup-merged never dispatched on a cloud session"

echo "R4. undelivered fence, environment unset -> source=none, honest skip"
for i in "${!GATE_ANCHORS[@]}"; do
  ws="$(fresh_ws "r4$i")"
  out="$(run_gate "${FENCE_LITERAL[$i]}" "$ws" "$SCRATCH_HOME")"
  want_in "$out" "SOLEUR_PLUGIN_ROOT_RESOLVE gate=${GATE_NAMES[$i]} source=none verified=false" "R4: ${GATE_NAMES[$i]} reports source=none"
  want_in "$out" "${GATE_UNVERIFIED_MARKERS[$i]}" "R4: ${GATE_NAMES[$i]} emits its existing skip marker"
done
# Measured in a fresh fixture repo: --is-bare-repository -> false, --is-inside-work-tree -> true.
# Exactly ONE `true`, in that order. The plan's first draft claimed two.
ws="$(fresh_ws r4pair)"
out="$(run_gate "${FENCE_LITERAL[0]}" "$ws" "$SCRATCH_HOME")"
pair="$(printf '%s\n' "$out" | grep -E '^(true|false)$' | tr '\n' ',' || true)"
want_eq "$pair" "false,true," "R4: Step 0.0 fallback prints the ordered pair false then true"

echo "R5/R5b. undelivered fence + an explicit root in the environment"
for i in "${!GATE_ANCHORS[@]}"; do
  ws="$(fresh_ws "r5$i")"
  out="$(run_gate "${FENCE_LITERAL[$i]}" "$ws" "$SCRATCH_HOME" "GROK_PLUGIN_ROOT=$FIX_ROOT")"
  want_in "$out" "gate=${GATE_NAMES[$i]} source=grok-env verified=true" "R5: ${GATE_NAMES[$i]} falls through to GROK_PLUGIN_ROOT"
  want_in "$out" "${R1_EFFECT[$i]}" "R5: ${GATE_NAMES[$i]} reached its dispatch via grok-env"
  ws="$(fresh_ws "r5b$i")"
  out="$(run_gate "${FENCE_LITERAL[$i]}" "$ws" "$SCRATCH_HOME" "CLAUDE_PLUGIN_ROOT=$FIX_ROOT")"
  want_in "$out" "gate=${GATE_NAMES[$i]} source=plugin-root-token verified=true" "R5b: ${GATE_NAMES[$i]} read-from-disk harness happy path"
  want_in "$out" "${R1_EFFECT[$i]}" "R5b: ${GATE_NAMES[$i]} reached its dispatch via the variable"
done

echo "R5c. Step 0.5 Devin CLI cache arm, behaviourally"
CACHE_HOME="$TMP_ROOT/home-devin"
CACHE_ROOT="$CACHE_HOME/.local/share/devin/cli/plugins/cache/soleur-abc123"
mk_root "$CACHE_ROOT" soleur
ws="$(fresh_ws r5c)"
out="$(run_gate "${FENCE_LITERAL[1]}" "$ws" "$CACHE_HOME")"
want_in "$out" "gate=cloud-detect source=devin-cache verified=true" "R5c: Step 0.5 resolves from the Devin CLI cache"
want_in "$out" "not-local:no-devin-env" "R5c: the real cloud-detect.sh ran from the cache root"

echo "R6/R6b/R6c. identity preflight and the payload-absent state"
for i in "${!GATE_ANCHORS[@]}"; do
  ws="$(fresh_ws "r6$i")"
  out="$(run_gate "$(delivered_fence "$i" "$DECOY_EVIL" evil)" "$ws" "$SCRATCH_HOME")"
  want_in "$out" "gate=${GATE_NAMES[$i]} source=plugin-root-token verified=false" "R6: ${GATE_NAMES[$i]} refuses a non-Soleur manifest"
  want_in "$out" "${GATE_UNVERIFIED_MARKERS[$i]}" "R6: ${GATE_NAMES[$i]} emits its skip marker on the decoy"
  want_eq "$(decoy_ran)" "none" "R6: ${GATE_NAMES[$i]} executed nothing under the decoy root"

  # MUST-PASS, and it documents a LIMITATION: the preflight is a shape check, not
  # authentication (ADR-179 A11, which rejected the stronger root-outside-worktree assertion).
  # If this row ever fails, someone added a trust assertion the ADR declined — supersede A11
  # first, then change this row.
  ws="$(fresh_ws "r6b$i")"
  out="$(run_gate "$(delivered_fence "$i" "$DECOY_CLAIM" claim)" "$ws" "$SCRATCH_HOME")"
  want_in "$out" "gate=${GATE_NAMES[$i]} source=plugin-root-token verified=true" "R6b: a manifest CLAIMING soleur is accepted (known limitation)"
  want_eq "$(decoy_ran)" "DECOY_EXECUTED" "R6b: and its payload executes (the preflight is not authentication)"

  # R6c: ours, but this gate's own dispatch target is gone.
  absent_root="$TMP_ROOT/root-absent-${GATE_NAMES[$i]}"
  mk_root "$absent_root" soleur "${GATE_NAMES[$i]}"
  ws="$(fresh_ws "r6c$i")"
  out="$(run_gate "$(delivered_fence "$i" "$absent_root" absent)" "$ws" "$SCRATCH_HOME")"
  want_in "$out" "gate=${GATE_NAMES[$i]} source=plugin-root-token verified=true" "R6c: ${GATE_NAMES[$i]} verifies the root"
  want_in "$out" "${GATE_ABSENT_MARKERS[$i]}" "R6c: ${GATE_NAMES[$i]} reports the absent payload distinctly"
  want_not_in "$out" "${R1_EFFECT[$i]}" "R6c: ${GATE_NAMES[$i]} dispatched nothing"
done

echo "R7. ambient decoys never win against a delivered token (the A10 control)"
for i in "${!GATE_ANCHORS[@]}"; do
  ws="$(fresh_ws "r7$i")"
  out="$(run_gate "$(delivered_fence "$i" "$FIX_ROOT" ok)" "$ws" "$SCRATCH_HOME" \
        "CLAUDE_PLUGIN_ROOT=$DECOY_EVIL" "GROK_PLUGIN_ROOT=$DECOY_CLAIM")"
  want_in "$out" "gate=${GATE_NAMES[$i]} source=plugin-root-token verified=true" "R7: ${GATE_NAMES[$i]} ignores ambient roots"
  want_eq "$(decoy_ran)" "none" "R7: ${GATE_NAMES[$i]} executed nothing under an ambient decoy"
done

echo "H1. deliver() self-test, pinned to an artifact this diff did not produce"
ck; if [ -f "$ARM5_DELIVERED" ] && [ -f "$PROBE_MD" ]; then
  pass "H1: the Arm 5 probe and its capture are both committed"
else
  fail "H1: missing $ARM5_DELIVERED or $PROBE_MD"
fi
if [ -f "$ARM5_DELIVERED" ] && [ -f "$PROBE_MD" ]; then
  probe_src="$(awk "/^cat > \"\\\$OUT.delivered\" <<'PROBE_EOF'\$/ {inb=1; next} inb && /^PROBE_EOF\$/ {exit} inb {print}" "$PROBE_MD")"
  ck; if [ -n "$probe_src" ]; then pass "H1: extracted the probe's undelivered body"; else fail "H1: could not extract the probe's undelivered body"; fi
  arm5_root="$(grep -m1 '^BARE=' "$ARM5_DELIVERED" | sed 's/^BARE=//')"
  printf '%s\n' "$probe_src" | deliver "$arm5_root" > "$TMP_ROOT/h1-simulated.txt"
  ck; if cmp -s "$TMP_ROOT/h1-simulated.txt" "$ARM5_DELIVERED"; then
    pass "H1: deliver() reproduces the real loader's capture byte-for-byte"
  else
    fail "H1: deliver() diverges from arm5-delivered.txt"
    diff -u "$ARM5_DELIVERED" "$TMP_ROOT/h1-simulated.txt" | head -20 || true
  fi
  sim="$(printf '%s\n' "$probe_src" | deliver "$arm5_root")"
  want_in "$sim" 'FORM_8061=${GROK_PLUGIN_ROOT:-$CLAUDE_PLUGIN_ROOT}' "H1: the :- form survives delivery unchanged"
  want_in "$sim" 'UNBRACED=$CLAUDE_PLUGIN_ROOT' "H1: the unbraced form survives delivery unchanged"
  # Added after mutation row 15 SURVIVED: the probe carried no ${CLAUDE_PLUGIN_ROOT:-...} row,
  # so widening deliver() to also replace that form perturbed nothing the fixture instantiated.
  # A FIXTURE-space gap, not a guard gap -- and a mutation battery cannot see one, because it
  # scores the SUT through the fixtures it already has.
  want_in "$sim" 'COLONDASH=${CLAUDE_PLUGIN_ROOT:-./plugins/soleur}' "H1: the colon-dash form survives delivery unchanged"
fi

echo "H2. must-PASS: a non-canonical but compliant go.md variant"
H2_MD="$TMP_ROOT/h2-go.md"
python3 - "$GO_MD" "$H2_MD" <<'PY'
import sys, re
src, dst = sys.argv[1], sys.argv[2]
s = open(src, encoding="utf-8").read()
# Change GATE= values, add a blank line and different comment text OUTSIDE the resolver
# anchors. R8/R9 must be indifferent to all three.
s = re.sub(r'^GATE=(\S+)$', lambda m: "\n# H2: a comment outside the anchors\nGATE=h2-" + m.group(1),
           s, flags=re.M)
open(dst, "w", encoding="utf-8").write(s)
PY
ck; if [ -s "$H2_MD" ]; then pass "H2: variant synthesized"; else fail "H2: variant not synthesized"; fi
check_r8 "$H2_MD" "H2"
check_r9 "$H2_MD" "H2"

echo "H3. real-harness contact (the one row the simulator does not mediate)"
# ADR-188's default is FAIL-in-CI / SKIP-locally, because a pinned binary CI installs makes a CI
# skip a broken environment. This row INVERTS that default DELIBERATELY: CI does not and should
# not install the Claude CLI, so a CI skip is the EXPECTED state. The arm cannot silently disarm
# because AC12 makes a real run mandatory pre-merge and commits its capture.
#
# The skip is an OPT-OUT, never an opt-in. An opt-in default IS mutation row 17 -- "make H3
# print SKIP-DECLARED unconditionally" -- shipped as the shape; it measured green because the
# mutation changed nothing that was not already true.
#
# COST, disclosed: on a box carrying the Claude CLI this row spawns a headless session on
# every run of this suite, and the full battery invokes it. `SOLEUR_GO_GATES_SKIP_H3=1` opts
# out and SAYS SO in its reason string -- it never claims the binary is absent.
H3_SKIP_REASON=""
if ! command -v claude >/dev/null 2>&1; then
  H3_SKIP_REASON=claude-binary-absent
elif [ "${SOLEUR_GO_GATES_SKIP_H3:-}" = "1" ]; then
  H3_SKIP_REASON=explicit-opt-out
fi
if [ -z "$H3_SKIP_REASON" ]; then
  # Two corrections the plan's drafted command needed, both measured rather than reasoned:
  #
  #  1. The prompt goes on STDIN. `claude -p --plugin-dir ... --allowedTools ... "<prompt>"`
  #     is rejected outright ("Input must be provided either through stdin or as a prompt
  #     argument when using --print"), so the drafted shape never ran at all.
  #  2. The prompt must INVOKE `/soleur:go`, not describe its blocks. Asked to "run the Step
  #     0.0 / 0.5 / 0 bash blocks", the agent Reads go.md from disk -- the UNDELIVERED path --
  #     and the capture then reads `source=none verified=false`, i.e. the pre-fix behaviour
  #     reported as though it were the post-fix one. Measured both ways in one session.
  #
  # Run from a SCRATCH workspace: Step 0 dispatches cleanup-merged for real, and a row that
  # deletes the developer's merged branches as a side effect of measuring is not a test.
  # Measured the hard way -- running this from the worktree root reverted every uncommitted
  # file in it to HEAD.
  h3_ws="$(fresh_ws h3)"
  h3_out="$(cd "$h3_ws" && printf '%s\n' "/soleur:go run ONLY the Step 0.0, Step 0.5 and Step 0 bash blocks exactly as delivered, then print their combined raw stdout verbatim inside one fenced code block with no summary, then STOP - do not classify, do not route, do not invoke any skill" \
    | timeout 420 claude -p --plugin-dir "${REPO_ROOT}/plugins/soleur" --allowedTools "Bash" 2>&1 || true)"
  for g in readiness cloud-detect session-start; do
    want_in "$h3_out" "gate=${g} source=plugin-root-token verified=true" "H3: real harness resolved ${g}"
  done
else
  # The reason must be TRUE, not merely printed. A skip claiming the binary is absent while
  # `command -v` finds it is precisely the disarm this arm exists to refuse.
  # The reason must be TRUE. Written as `[ "$R" = claude-binary-absent ] && command -v claude`
  # this was `¬P ∧ P` — that branch is set only inside `if ! command -v claude`, so the guard
  # could never fire and counted as a decided assertion while deciding nothing. Assert the
  # REASON matches an independently re-derived observation instead.
  ck
  if command -v claude >/dev/null 2>&1; then _h3_expect=explicit-opt-out; else _h3_expect=claude-binary-absent; fi
  if [ "$H3_SKIP_REASON" = "$_h3_expect" ]; then
    pass "H3: SKIP-DECLARED reason=${H3_SKIP_REASON}, re-derived from command -v claude (AC12 carries the mandatory pre-merge run)"
  else
    fail "H3: SKIP-DECLARED reason=${H3_SKIP_REASON} contradicts command -v claude (expected ${_h3_expect}) — the skip is not derived"
  fi
fi

# --- L2. DECIDER self-tests: the axis a pass()/fail() control cannot reach -------------------
#
# A control on pass()/fail() proves DISPATCH. It says nothing about a helper that OWNS a
# verdict: want_in/want_not_in/want_eq each decide a branch and THEN call pass(), so a decider
# that always takes the pass branch appends a genuine PASS row and every leg of the
# triple-check -- counters, append-only ledger, assertion floor -- reconciles exactly.
#
# Measured on this file before this block existed, each a single edit, each leaving the suite
# byte-identical at `137 passed, 0 failed, 137 assertion(s) executed (floor 137)`:
#   want_in()  { ck; pass "$3"; }                    -> GREEN (21 rows blind)
#   want_not_in() { ck; pass "$3"; }                 -> GREEN
#   want_eq()  { ck; pass "$3"; }                    -> GREEN
#   case "$1" in  ->  case "$1$2" in   (one token)   -> GREEN
#   check_r8 / check_r9 bodies -> `ck; pass` loops    -> GREEN
# With three of those applied plus an R9-ban-evading revert of go.md's resolver
# (`XROOT="${CLAUDE_PLUGIN_ROOT}"; ROOT="${GROK_PLUGIN_ROOT:-$XROOT}"`), the defect this suite
# exists to catch was live and the suite still reported 137/0/137, rc=0.
#
# So each decider is driven in BOTH directions and the observables are reconciled, then the
# whole probe is retracted from the counters AND the ledger. Verdicts here are reported with
# printf + exit 1 -- never through the helpers under test, which is the mutation being defended
# against.
echo "L2. decider self-tests"
_L2_FAILED=0
_l2_drive() {                      # _l2_drive <want-passes> <want-fails> <label> <cmd...>
  local wp="$1" wf="$2" label="$3"; shift 3
  local p0=$passes f0=$fails a0=$asserted l0
  l0=$(wc -l < "$VERDICT_LOG")
  "$@" >/dev/null 2>&1
  local dp=$((passes - p0)) df=$((fails - f0)) da=$((asserted - a0))
  local dl=$(( $(wc -l < "$VERDICT_LOG") - l0 ))
  # Retract from BOTH the counters and the append-only ledger, so the floor stays exact.
  passes=$p0; fails=$f0; asserted=$a0
  head -n "$l0" "$VERDICT_LOG" > "$TMP_ROOT/verdicts.l2" && mv "$TMP_ROOT/verdicts.l2" "$VERDICT_LOG"
  if [ "$dp" -ne "$wp" ] || [ "$df" -ne "$wf" ] || [ "$da" -ne 1 ] || [ "$dl" -ne $((wp + wf)) ]; then
    printf 'FATAL: decider self-test %s: got passes+=%s fails+=%s asserted+=%s ledger+=%s; want %s/%s/1/%s\n' \
      "$label" "$dp" "$df" "$da" "$dl" "$wp" "$wf" "$((wp + wf))" >&2
    _L2_FAILED=1
  fi
}
_l2_drive 1 0 "want_in/accept"      want_in     "haystack" "hay" "L2 probe"
_l2_drive 0 1 "want_in/reject"      want_in     "haystack" "zzz" "L2 probe"
_l2_drive 1 0 "want_not_in/accept"  want_not_in "haystack" "zzz" "L2 probe"
_l2_drive 0 1 "want_not_in/reject"  want_not_in "haystack" "hay" "L2 probe"
_l2_drive 1 0 "want_eq/accept"      want_eq     "a" "a" "L2 probe"
_l2_drive 0 1 "want_eq/reject"      want_eq     "a" "b" "L2 probe"

# The COMPOSITE deciders get the same treatment: a go.md variant broken in exactly the two ways
# they exist to detect must drive each of them to a non-zero fail delta. Without this, replacing
# either body with a `ck; pass` loop is green (measured above).
L2_BAD="$TMP_ROOT/l2-broken-go.md"
python3 - "$GO_MD" "$L2_BAD" <<'L2PY'
import sys, pathlib
src, dst = sys.argv[1], sys.argv[2]
s = pathlib.Path(src).read_text()
# (a) make ONE fence's resolver differ -> R8 byte-identity must fail.
s = s.replace('ROOT="${CLAUDE_PLUGIN_ROOT}"; SRC=plugin-root-token',
              'ROOT="${CLAUDE_PLUGIN_ROOT}"; SRC=plugin-root-token # L2-divergence', 1)
# (b) introduce a banned form in fence CODE -> R9 must fail.
s = s.replace('[ -n "$ROOT" ] || SRC=none',
              'ROOT="${ROOT:-./plugins/soleur}"\n[ -n "$ROOT" ] || SRC=none', 1)
pathlib.Path(dst).write_text(s)
L2PY
_l2_composite() {                  # _l2_composite <label> <fn>
  local label="$1" fn="$2"
  local p0=$passes f0=$fails a0=$asserted l0
  l0=$(wc -l < "$VERDICT_LOG")
  "$fn" "$L2_BAD" "L2" >/dev/null 2>&1
  local df=$((fails - f0))
  passes=$p0; fails=$f0; asserted=$a0
  head -n "$l0" "$VERDICT_LOG" > "$TMP_ROOT/verdicts.l2" && mv "$TMP_ROOT/verdicts.l2" "$VERDICT_LOG"
  if [ "$df" -lt 1 ]; then
    printf 'FATAL: composite self-test %s scored 0 failures against a deliberately broken go.md — it decides nothing\n' "$label" >&2
    _L2_FAILED=1
  fi
}
_l2_composite "check_r8" check_r8
_l2_composite "check_r9" check_r9
[ "$_L2_FAILED" -eq 0 ] || { printf 'FATAL: the deciders are not load-bearing; every behavioural row above is unproven\n' >&2; exit 2; }
ck; pass "L2: want_in/want_not_in/want_eq/check_r8/check_r9 each decide both ways"

# --- L. instrument self-test: drive the helpers, do not read them -----------------------------
echo "L. verdict accounting"
ck; _p0=$passes; _f0=$fails; _lines0=$(wc -l < "$VERDICT_LOG")
fail "SELF-TEST (expected; retracted immediately)"
_moved_f=$((fails - _f0)); _moved_p=$((passes - _p0))
_lines1=$(wc -l < "$VERDICT_LOG")
fails=$_f0
_tmp_log="$TMP_ROOT/verdicts.trunc"; head -n -1 "$VERDICT_LOG" > "$_tmp_log"; mv "$_tmp_log" "$VERDICT_LOG"
if [ "$_moved_f" -eq 1 ] && [ "$_moved_p" -eq 0 ] && [ $((_lines1 - _lines0)) -eq 1 ]; then
  pass "fail() moves fails and only fails, and appends exactly one ledger row"
else
  echo "  FAIL: fail() accounting is wrong (fails+=$_moved_f passes+=$_moved_p ledger+=$((_lines1 - _lines0)))"
  fails=$((fails + 1)); echo "FAIL" >> "$VERDICT_LOG"
fi

LEDGER_PASS=$(grep -c '^PASS$' "$VERDICT_LOG" || true)
LEDGER_FAIL=$(grep -c '^FAIL$' "$VERDICT_LOG" || true)
if [ "$LEDGER_PASS" -ne "$passes" ] || [ "$LEDGER_FAIL" -ne "$fails" ]; then
  echo "FATAL: ledger disagrees with counters (ledger P/F = $LEDGER_PASS/$LEDGER_FAIL; counters = $passes/$fails)" >&2
  exit 2
fi
if [ $((passes + fails)) -ne "$asserted" ]; then
  echo "FATAL: verdicts ($((passes + fails))) != assertions counted ($asserted)" >&2
  exit 2
fi

# Pinned to the row table's full contribution, not a slack figure: floor SLACK is attack budget,
# and a floor 26 below the real total lets 26 assertions be deleted with the suite still green.
# 155 is the H3-SKIPPED total; H3 running adds two more (157), so the floor holds on both paths.
# Raising it is part of adding a row — R3f, R3g and R3h took it 147 -> 155.
MIN_ASSERTIONS=155
if [ "$asserted" -lt "$MIN_ASSERTIONS" ]; then
  echo "FATAL: only $asserted assertions executed, floor is $MIN_ASSERTIONS -- rows were removed" >&2
  exit 2
fi

echo
echo "go-session-gates.test.sh: $passes passed, $fails failed, $asserted assertion(s) executed (floor $MIN_ASSERTIONS)"
# The APPEND-ONLY ledger is the authority; `$fails` is a mutable counter every reconciliation
# above has already read.
LEDGER_FAIL_FINAL=$(grep -c '^FAIL$' "$VERDICT_LOG" || true)
[ "$LEDGER_FAIL_FINAL" -eq 0 ] && [ "$fails" -eq 0 ] || exit 1
exit 0
