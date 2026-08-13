#!/usr/bin/env bash
# Guard 1's mutation battery for scripts/lint-orphan-test-suites.sh (#7402).
#
# WHY THIS FILE EXISTS. That linter's failure mode is SILENT: if its walk narrows, a surface
# stops matching, or its glob list desynchronises from the runner's, it keeps printing
# `orphan test suites: none` and exits 0 — byte-identical to a healthy repo. Reading it cannot
# distinguish those states. So every row below breaks the linter in one specific way and
# asserts it goes RED, naming the specific suite that stopped being covered.
#
# THE SANDBOX IS SYNTHETIC, AND IT IS A REAL GIT REPO. Both halves are load-bearing.
#
#   Real git repo: the linter's producer is `git ls-files`, which returns NOTHING outside a
#   repository. A plain `cp -r` sandbox would make every row pass against an empty walk —
#   reproducing, inside this harness, the exact vacuity row M6 exists to catch. The
#   enumeration is asserted non-empty before any row runs.
#
#   Synthetic: measured, this worktree is 13,630 tracked files / 258 MB, so fourteen tree
#   copies would be ~3.6 GB of I/O plus fourteen `git add` of 13.6k files. The sandbox instead
#   holds path-shaped EMPTY files at every tracked `*.test.sh` path (they are never executed —
#   the linter only ever asks whether something is registered) plus the four real inputs the
#   linter reads: scripts/test-all.sh, .github/workflows/, apps/web-platform/infra/run-registered-suites.sh
#   and scripts/lib/test-relevance-paths.sh. That is also what cq-test-fixtures-synthesized-only
#   asks for, and it makes M2's "two files under directories no glob covers" and M8's
#   producer-narrowing directly controllable rather than incidental.
#
# THE SINGLE-SURFACE PRECONDITION. The covered set is a UNION of six surfaces, so
# de-registering a suite on one surface is a NO-OP if another surface also matches it — the
# row would pass green while proving nothing. Every row that de-registers (M1, M3, M5, M9,
# M10, and the surface-6 removal) first asserts its target is covered by EXACTLY ONE surface,
# via the linter's SOLEUR_LINT_ORPHAN_DUMP_SURFACES seam, and aborts loudly if not. This is the
# semantic analogue of the syntactic DID-NOT-LAND check in `mutate` below.
#
# MUTATORS FAIL CLOSED. `mutate` requires its literal to occur EXACTLY ONCE and exits 3
# otherwise, so a mutator whose anchor drifted aborts the harness instead of scoring a phantom
# kill against an unmutated file. That failure — a battery that stops mutating and keeps
# reporting kills — is the same class as the one the battery guards.
set -uo pipefail

# git exports these when this runs as a lefthook hook, and they would repoint every sandbox
# `git` call at the parent repo — the sandbox would then enumerate 13,630 files and every row
# would measure the wrong tree.
unset GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Overridable so this battery can be pointed at an older or already-broken copy and PROVED to
# red against it. A guard that has never been shown to fail is not evidence.
SUT="${LINT_ORPHAN_TARGET_OVERRIDE:-$REPO_ROOT/scripts/lint-orphan-test-suites.sh}"

# /tmp on this machine class is a shared ~4 GiB tmpfs and this file builds one sandbox per row.
# `mktemp -d` respects TMPDIR, so defaulting it here keeps the verdicts independent of another
# worktree's disk usage.
export TMPDIR="${TMPDIR:-/var/tmp}"
# Same reason the SUT pins it: `comm` and `sort` must agree on collation, and the harness sorts
# too.
export LC_ALL=C

PASS=0; FAIL=0; ROWS=0
TMP="$(mktemp -d)" || exit 2
trap 'rm -rf "$TMP"' EXIT

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }
harness_die() {
  echo "FATAL(harness): $1" >&2
  echo "The battery could not set up or could not land a mutation. That is NOT a verdict about" >&2
  echo "the linter — treat it as a broken harness and fix it before reading any row above." >&2
  exit 2
}

# --- Sandbox construction -------------------------------------------------------------------
PRISTINE="$TMP/pristine"

materialise() {
  # Path-shaped empty file, parents included. `git ls-files` is index-bound, so these only have
  # to exist and be added — never to be runnable.
  #
  # DIRECTORY-SHAPED declarations get a tracked `.keep` instead. The relevance-predicate arrays
  # legitimately declare directories (`.claude/hooks`), and the SUT checks them with
  # `git ls-files --error-unmatch`, which is satisfied by any tracked file BENEATH the path.
  # Writing a file AT that path instead fails with "Is a directory" the moment a sibling entry
  # has already created it — order-dependently, which is the worst way for a fixture to break.
  local p
  while IFS= read -r p; do
    [[ -n "$p" ]] || continue
    if [[ -d "$REPO_ROOT/$p" ]]; then
      mkdir -p "$PRISTINE/$p" || return 1
      : > "$PRISTINE/$p/.keep" || return 1
      continue
    fi
    mkdir -p "$PRISTINE/$(dirname "$p")" || return 1
    [[ -e "$PRISTINE/$p" ]] || : > "$PRISTINE/$p" || return 1
  done
}

build_pristine() {
  mkdir -p "$PRISTINE" || return 1

  # (1) Every tracked *.test.sh, as an empty file. This is the producer's domain, and building
  #     it from the real index rather than a hand-list is what keeps the sandbox honest as
  #     suites are added and removed.
  git -C "$REPO_ROOT" ls-files '*.test.sh' | materialise || return 1
  # (2) tests/commands/*.sh — the SUT's dedicated non-suffix loop walks this directory and
  #     reds on a zero count.
  git -C "$REPO_ROOT" ls-files 'tests/commands/*.sh' | materialise || return 1
  # (3) Every path declared in the relevance-predicate arrays: the SUT asserts each is a
  #     tracked file, so a sandbox missing them would red for a reason unrelated to any row.
  ( set +u
    # shellcheck source=scripts/lib/test-relevance-paths.sh
    source "$REPO_ROOT/scripts/lib/test-relevance-paths.sh"
    printf '%s\n' "${REGISTRY_BATTERY_PATHS[@]}" "${CF_TUNNEL_BATTERY_PATHS[@]}" \
                  "${C4_PRODUCER_PATHS[@]}" "${GITHUB_SCRIPTS_SUITE_PATHS[@]}"
  ) | LC_ALL=C sort -u | materialise || return 1

  # (4) The real inputs, copied verbatim. These are what the rows mutate.
  mkdir -p "$PRISTINE/scripts/lib" "$PRISTINE/apps/web-platform/infra" "$PRISTINE/.github/workflows" || return 1
  cp "$SUT" "$PRISTINE/scripts/lint-orphan-test-suites.sh" || return 1
  cp "$REPO_ROOT/scripts/test-all.sh" "$PRISTINE/scripts/test-all.sh" || return 1
  cp "$REPO_ROOT/scripts/lib/test-relevance-paths.sh" "$PRISTINE/scripts/lib/" || return 1
  cp "$REPO_ROOT/apps/web-platform/infra/run-registered-suites.sh" "$PRISTINE/apps/web-platform/infra/" || return 1
  cp "$REPO_ROOT"/.github/workflows/*.yml "$PRISTINE/.github/workflows/" || return 1

  git -C "$PRISTINE" init -q -b main >/dev/null 2>&1 || return 1
  git -C "$PRISTINE" add -A >/dev/null 2>&1 || return 1
}

# NORMALISE THE FIXTURE TO A FULLY-REGISTERED BASELINE.
#
# The subject of this battery is the LINTER, not the repository's current registration state.
# Those are different questions with different owners: whether the live tree has an orphan is
# answered by the `run_suite "scripts/lint-orphan-test-suites"` line in test-all.sh, which runs
# the real thing against the real tree. Asserting it a second time HERE would make every row
# below red whenever any concurrent session has `git add`ed an unregistered suite — a verdict
# about somebody else's in-flight work, arriving as a failure of this file
# (cq-ac-must-not-depend-on-concurrent-sessions). Measured: that happened during development,
# when a sibling session staged scripts/suite-exit-class-parity.test.sh.
#
# So any orphan the pristine fixture inherits from the live index gets a synthetic run_suite
# line appended to the SANDBOX's test-all.sh — announced, never silent. Appending at EOF is
# sufficient and safe: the linter only ever GREPS this file for the call shape, and the one
# code path that executes it (`--print-suite-globs`) exits at the top.
#
# CAPPED. Normalising a handful of inherited orphans keeps the fixture stable; normalising
# dozens would mean a surface in the SUT is broken, and papering over that is precisely the
# failure this battery exists to catch. Above the cap it is a harness abort, not a fixup.
MAX_NORMALISED=25
normalise_pristine() {
  local out="$TMP/pristine-baseline.txt" n=0 p
  bash "$PRISTINE/scripts/lint-orphan-test-suites.sh" > "$out" 2>&1
  while IFS= read -r p; do
    [[ -n "$p" ]] || continue
    printf '  run_suite "%s" bash %s\n' "$p" "$p" >> "$PRISTINE/scripts/test-all.sh"
    echo "  note(harness): fixture-normalised — registered inherited orphan ${p} in the sandbox runner"
    n=$((n + 1))
  done < <(sed -nE 's/^ERROR: ([A-Za-z0-9._\/-]+\.test\.sh) is never run by any runner.*/\1/p' "$out")
  if (( n > MAX_NORMALISED )); then
    harness_die "the pristine fixture inherited ${n} orphans (cap ${MAX_NORMALISED}) — that is a broken surface in the SUT, not fixture noise"
  fi
  NORMALISED=$n
}

build_pristine || harness_die "could not build the synthetic repo"

# ANTI-VACUITY, ASSERTED BEFORE ANY ROW RUNS. If `git ls-files` returns nothing here — not a
# repo, `git add` failed, an env var repointed it — every row below would pass over an empty
# walk and this battery would certify the guard while testing nothing.
sandbox_tracked=$(git -C "$PRISTINE" ls-files '*.test.sh' | wc -l | tr -d ' ')
real_tracked=$(git -C "$REPO_ROOT" ls-files '*.test.sh' | wc -l | tr -d ' ')
if (( sandbox_tracked < 1 )); then
  harness_die "the synthetic repo enumerates ZERO *.test.sh files — every row would be vacuous"
fi
if [[ "$sandbox_tracked" != "$real_tracked" ]]; then
  harness_die "synthetic repo enumerates ${sandbox_tracked} suites but the real repo has ${real_tracked} — the fixture is not a faithful stand-in"
fi
pass "harness: synthetic git repo enumerates ${sandbox_tracked} *.test.sh files (non-empty, matches the real index)"

NORMALISED=0
normalise_pristine
pass "harness: fixture normalised to a fully-registered baseline (${NORMALISED} inherited orphan(s) registered in the sandbox)"

# --- Row plumbing ----------------------------------------------------------------------------
OUT=""

# Sets the global $SB rather than PRINTING the path. Capturing it as `sb=$(new_sandbox …)`
# would run this in a COMMAND SUBSTITUTION, where harness_die's `exit 2` kills only the
# subshell — the caller would carry on with an empty path and every row after it would
# silently measure nothing.
new_sandbox() {
  SB="$TMP/$1"
  cp -a "$PRISTINE" "$SB" || harness_die "could not copy the pristine sandbox for $1"
}

# EXACT-LITERAL mutator with a built-in DID-NOT-LAND check. Stronger than a post-hoc `diff`:
# it also rejects an AMBIGUOUS anchor (two matches), where a diff would happily report "it
# changed" after mutating a site the row never meant to touch.
mutate() {
  local file="$1" old="$2" new="$3"
  python3 - "$file" "$old" "$new" <<'PY' || return $?
import sys
path, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(path).read()
n = s.count(old)
if n != 1:
    sys.stderr.write("MUTATOR-DID-NOT-LAND: anchor occurs %d time(s), expected exactly 1, in %s\n" % (n, path))
    sys.exit(3)
open(path, "w").write(s.replace(old, new, 1))
PY
}

mutate_or_die() {
  mutate "$@" || harness_die "mutator did not land on $1 (anchor drifted — the row would have scored a phantom kill)"
}

# Run the SUT inside a sandbox. rc is captured from the command itself, never from a pipeline,
# because `$?` after a pipe is the LAST element's status — which is how a crash reads as a pass.
run_lint() {
  local sb="$1"
  OUT="$SB/.lint-out"
  bash "$SB/scripts/lint-orphan-test-suites.sh" > "$OUT" 2>&1
  return $?
}

assert_red() {
  local label="$1" rc="$2"
  if (( rc != 0 )); then pass "$label — linter exited ${rc}"; else fail "$label — linter exited 0 (MUTANT SURVIVED)"; fi
}
assert_has() {
  local label="$1" needle="$2"
  if grep -qF -- "$needle" "$OUT"; then pass "$label"; else
    fail "$label — output did not contain: ${needle}"
    echo "    ---- linter output ----"; sed 's/^/    /' "$OUT" | head -20
  fi
}
assert_lacks() {
  local label="$1" needle="$2"
  if grep -qF -- "$needle" "$OUT"; then fail "$label — output unexpectedly contained: ${needle}"; else pass "$label"; fi
}

# The single-surface precondition. Asserts $2 is covered by EXACTLY ONE surface in the
# UNMUTATED sandbox; without it, a union match makes the row's mutation a silent no-op.
require_single_surface() {
  local sb="$1" path="$2" row="$3"
  local dump="$sb/.surfaces" n=0 i found=""
  SOLEUR_LINT_ORPHAN_DUMP_SURFACES=1 bash "$sb/scripts/lint-orphan-test-suites.sh" > "$dump" 2>&1
  for i in 1 2 3 4 5 6; do
    if grep -qxF "SURFACE${i} ${path}" "$dump"; then n=$((n + 1)); found="${found}${i} "; fi
  done
  if (( n != 1 )); then
    harness_die "${row}: '${path}' is covered by ${n} surface(s) [${found:-none}], expected exactly 1 — the mutation would be a no-op and the row would prove nothing"
  fi
  pass "${row} precondition: ${path} is covered by exactly one surface (surface ${found% })"
}

row() { ROWS=$((ROWS + 1)); echo ""; echo "[$1] $2"; }

# Literals the rows anchor on, hoisted so a drift breaks ALL of them at once (loudly, via
# mutate's DID-NOT-LAND) rather than silently weakening one row.
BOARD_LINE='  run_suite "scripts/board/set-board-status" bash scripts/board/set-board-status.test.sh'
BOARD_SUITE='scripts/board/set-board-status.test.sh'
GLOB_LINE="  'apps/cla-evidence/scripts/*.test.sh'"
INFRA_STEP='        run: bash apps/web-platform/infra/zot-log-shipper.test.sh'
INFRA_SUITE='apps/web-platform/infra/zot-log-shipper.test.sh'
HOOK_LINE='            bash main.test.sh'
HOOK_SUITE='apps/cla-evidence/infra/main.test.sh'
S5_STEP='        run: bash apps/web-platform/test/infra/vector-pii-scrub.test.sh'
S5_SUITE='apps/web-platform/test/infra/vector-pii-scrub.test.sh'
LOOPBACK_SUITE='apps/web-platform/infra/workspaces-luks-loopback.test.sh'
PRODUCER_LINE="git -C \"\$REPO_ROOT\" ls-files '*.test.sh' | LC_ALL=C sort -u > \"\$WORK/tracked\""
ORPHAN_MSG='is never run by any runner'

# =============================================================================================
# C0 — NOOP CONTROL. The positive control every mutation battery needs: if the unmutated
# sandbox is already RED, every row below "kills" a mutant that was dead on arrival.
# =============================================================================================
row C0 "noop control — the unmutated synthetic repo is GREEN"
new_sandbox c0
run_lint "$SB"; rc=$?
if (( rc == 0 )); then pass "C0 — unmutated sandbox exits 0"; else
  fail "C0 — unmutated sandbox exited ${rc}; every row below is meaningless"
  sed 's/^/    /' "$OUT" | head -30
fi
assert_has "C0 — reports no orphans" "orphan test suites: none"
assert_has "C0 — reports a non-empty walk over six surfaces" "walked ${real_tracked} tracked *.test.sh against 6 registration surfaces"

# =============================================================================================
# M1 — delete a registered suite's run_suite line (surface 1). Verify-the-verifier: this
# re-introduces a REAL orphan, the #6734/#7402 defect itself.
# =============================================================================================
row M1 "delete a run_suite line from test-all.sh (surface 1)"
new_sandbox m1
require_single_surface "$SB" "$BOARD_SUITE" "M1"
mutate_or_die "$SB/scripts/test-all.sh" "$BOARD_LINE"$'\n' ""
run_lint "$SB"; rc=$?
assert_red "M1" "$rc"
assert_has "M1 — names the de-registered suite" "${BOARD_SUITE} ${ORPHAN_MSG}"

# =============================================================================================
# M2 — two new unregistered suites under directories no glob covers, BOTH named. Two in one
# row is strictly stronger than a separate "reports the second member" row, and unlike that
# row it stays meaningful under a set-difference implementation.
# =============================================================================================
row M2 "two unregistered suites under uncovered directories, both reported"
new_sandbox m2
mkdir -p "$SB/tools/nowhere" "$SB/docs/deep/nested" || harness_die "M2 mkdir"
: > "$SB/tools/nowhere/alpha.test.sh"; : > "$SB/docs/deep/nested/beta.test.sh"
git -C "$SB" add -A >/dev/null 2>&1 || harness_die "M2 git add"
run_lint "$SB"; rc=$?
assert_red "M2" "$rc"
assert_has "M2 — names the first new orphan" "tools/nowhere/alpha.test.sh ${ORPHAN_MSG}"
assert_has "M2 — names the second new orphan" "docs/deep/nested/beta.test.sh ${ORPHAN_MSG}"

# =============================================================================================
# M3 — delete a `run: bash …` step from infra-validation.yml (surface 3). Surface 3 carries 98
# of the ~340 tracked suites, an order of magnitude more than any other, and it is delegated to
# a second script's derivation — the likeliest surface to silently under-match.
# =============================================================================================
row M3 "delete a run: bash step from infra-validation.yml (surface 3)"
new_sandbox m3
require_single_surface "$SB" "$INFRA_SUITE" "M3"
mutate_or_die "$SB/.github/workflows/infra-validation.yml" "$INFRA_STEP"$'\n' ""
run_lint "$SB"; rc=$?
assert_red "M3" "$rc"
assert_has "M3 — names the de-registered infra suite" "${INFRA_SUITE} ${ORPHAN_MSG}"

# =============================================================================================
# M4 — keep the run_suite LABEL, swap the COMMAND. Closes the silent direction: a parser
# degrading toward a bare-path grep inflates the covered set and hides real orphans behind a
# green "none", which no floor can detect. Measured escape at test-all.sh's REQUIRED_RUNNERS
# comment: `run_suite "<path>" bash -c true` once left this linter reporting no orphans.
# =============================================================================================
row M4 "keep the run_suite label, swap its command (registration must be command-anchored)"
new_sandbox m4
mutate_or_die "$SB/scripts/test-all.sh" "$BOARD_LINE" \
  '  run_suite "scripts/board/set-board-status.test.sh" bash -c true'
run_lint "$SB"; rc=$?
assert_red "M4" "$rc"
assert_has "M4 — a label-only mention does not count as registration" "${BOARD_SUITE} ${ORPHAN_MSG}"

# =============================================================================================
# M5 — delete one glob pattern from test-all.sh's SUITE_GLOBS. This row ONLY reds if the linter
# ASKS the runner for its patterns. Carry a duplicate copy in the linter and the runner stops
# running eight suites while the linter, reading its stale copy, reports them covered.
# =============================================================================================
row M5 "delete a glob pattern from the runner (surface 2 must be derived, never duplicated)"
new_sandbox m5
glob_members=$(git -C "$SB" ls-files 'apps/cla-evidence/scripts/*.test.sh')
[[ -n "$glob_members" ]] || harness_die "M5: the target glob matches no tracked file — nothing to lose"
GLOB_MEMBER_N=$(wc -l <<< "$glob_members" | tr -d ' ')
while IFS= read -r m; do require_single_surface "$SB" "$m" "M5"; done <<< "$glob_members"
mutate_or_die "$SB/scripts/test-all.sh" "$GLOB_LINE"$'\n' ""
run_lint "$SB"; rc=$?
assert_red "M5" "$rc"
while IFS= read -r m; do assert_has "M5 — names ${m}" "${m} ${ORPHAN_MSG}"; done <<< "$glob_members"

# =============================================================================================
# M6 — OWN DISPATCH. Neuter the walk so it enumerates zero files. The single most valuable row
# here: it is the only one covering the direction where failure is byte-identical to success.
# =============================================================================================
row M6 "neuter the producer to enumerate zero files (anti-vacuity floor)"
new_sandbox m6
mutate_or_die "$SB/scripts/lint-orphan-test-suites.sh" "$PRODUCER_LINE" \
  "git -C \"\$REPO_ROOT\" ls-files 'no-such-directory-anywhere/*.test.sh' | LC_ALL=C sort -u > \"\$WORK/tracked\""
run_lint "$SB"; rc=$?
assert_red "M6" "$rc"
assert_has "M6 — the producer floor fires on a zero walk" "enumerated 0 tracked suites"
assert_lacks "M6 — does not report a clean repo" "orphan test suites: none"

# =============================================================================================
# M7 — an exclusion with a reason but no tracking issue.
# =============================================================================================
row M7 "exclusion with a reason but no #NNNN"
new_sandbox m7
mutate_or_die "$SB/scripts/lint-orphan-test-suites.sh" 'EXCLUSIONS=()' \
  "EXCLUSIONS=( \"${BOARD_SUITE}|flaky on this machine\" )"
run_lint "$SB"; rc=$?
assert_red "M7" "$rc"
assert_has "M7 — fail-closed on a missing tracking issue" "has no reason or no tracking issue"

# =============================================================================================
# M8 — PRODUCER PARTIAL-NARROWING. The highest-value row, and the one this guard is most likely
# to fail silently against: reverting to the pre-#7402 `scripts/*.test.sh` producer still
# enumerates 70 real files, clears every per-surface zero-check, finds no orphans among them
# and prints `orphan test suites: none`. M6 covers "enumerates zero"; only a count floor covers
# "enumerates a plausible SUBSET".
# =============================================================================================
row M8 "narrow the producer back to scripts/*.test.sh (plausible-subset)"
new_sandbox m8
mutate_or_die "$SB/scripts/lint-orphan-test-suites.sh" "$PRODUCER_LINE" \
  "git -C \"\$REPO_ROOT\" ls-files 'scripts/*.test.sh' | LC_ALL=C sort -u > \"\$WORK/tracked\""
run_lint "$SB"; rc=$?
narrowed=$(git -C "$SB" ls-files 'scripts/*.test.sh' | wc -l | tr -d ' ')
(( narrowed > 0 )) || harness_die "M8: the narrowed producer matches nothing, so this row degenerates into M6"
assert_red "M8" "$rc"
assert_has "M8 — the producer floor fires on a plausible subset (${narrowed} of ${real_tracked})" "enumerated ${narrowed} tracked suites"
assert_lacks "M8 — does not read as a clean repo" "orphan test suites: none"

# =============================================================================================
# M9 — delete the per-app main.test.sh hook step (surface 4). One workflow step registers a
# suite in every infra root at once without naming any of them; nothing else in the linter can
# see it, because the path on that step is relative.
# =============================================================================================
row M9 "delete the per-app main.test.sh hook step (surface 4)"
new_sandbox m9
require_single_surface "$SB" "$HOOK_SUITE" "M9"
mutate_or_die "$SB/.github/workflows/infra-validation.yml" "$HOOK_LINE"$'\n' ""
run_lint "$SB"; rc=$?
assert_red "M9" "$rc"
assert_has "M9 — names the suite the hook covered" "${HOOK_SUITE} ${ORPHAN_MSG}"
assert_has "M9 — surface 4 is reported dark" "registration surface 4 matched ZERO tracked suites"

# =============================================================================================
# M10 — delete a `run: bash …` step from a workflow OTHER than infra-validation.yml (surface 5).
# =============================================================================================
row M10 "delete a run: bash step from another workflow (surface 5)"
new_sandbox m10
require_single_surface "$SB" "$S5_SUITE" "M10"
mutate_or_die "$SB/.github/workflows/validate-vector-config.yml" "$S5_STEP"$'\n' ""
run_lint "$SB"; rc=$?
assert_red "M10" "$rc"
assert_has "M10 — names the de-registered suite" "${S5_SUITE} ${ORPHAN_MSG}"

# =============================================================================================
# M11 — an exclusion key matching ZERO tracked files. M7 covers the missing issue-ref and the
# ambiguous row below covers the >=2 direction; a STALE key that masks nothing while looking
# disciplined is a third, distinct failure — and the one that survives longest, because
# deleting or renaming the suite an exclusion was written for leaves no trace.
# =============================================================================================
row M11 "exclusion key matching zero tracked files"
new_sandbox m11
mutate_or_die "$SB/scripts/lint-orphan-test-suites.sh" 'EXCLUSIONS=()' \
  'EXCLUSIONS=( "scripts/deleted-long-ago.test.sh|pre-existing failure, tracked in #9999" )'
run_lint "$SB"; rc=$?
assert_red "M11" "$rc"
assert_has "M11 — fail-closed on a stale key" "matches 0 tracked files, expected exactly 1"

# =============================================================================================
# M12 (AC26) — an exclusion key matching TWO tracked files. This is the basename-collision the
# re-key to repo-relative paths exists to prevent: measured, `parity.test.sh` exists under both
# constraint-scaffold/test/ and linear-fetch/test/, and linear-fetch's is one of the suites
# #7402 exists to keep honest — so the collision lands exactly on the work.
# =============================================================================================
row M12 "exclusion key matching two tracked files (basename collision)"
new_sandbox m12
collide=$(git -C "$SB" ls-files 'plugins/soleur/skills/*/test/parity.test.sh' | wc -l | tr -d ' ')
(( collide >= 2 )) || harness_die "M12: the ambiguous key matches ${collide} files, so this row cannot test ambiguity"
mutate_or_die "$SB/scripts/lint-orphan-test-suites.sh" 'EXCLUSIONS=()' \
  'EXCLUSIONS=( "plugins/soleur/skills/*/test/parity.test.sh|ambiguous, tracked in #9999" )'
run_lint "$SB"; rc=$?
assert_red "M12" "$rc"
assert_has "M12 — fail-closed on an ambiguous key" "matches ${collide} tracked files, expected exactly 1"

# =============================================================================================
# M13 (AC25) — REMOVE SURFACE 6 and assert the loopback suite becomes an orphan. Surface 6 is
# verified BY ITS ABSENCE, not by being present in the source: it is what makes zero orphans
# satisfiable at all, and without this row a later "simplify the two greps into one" edit could
# delete it and leave the battery green.
# =============================================================================================
row M13 "remove surface 6 (multi-line \`run: |\` block) — the loopback suite must become an orphan"
new_sandbox m13
require_single_surface "$SB" "$LOOPBACK_SUITE" "M13"
# The anchor is surface 6's REGEX BODY, not the whole pipeline: an ERE that can never match a
# line empties the surface exactly as deleting the block would, and a single-line anchor cannot
# be broken by a reflow of the continuation lines around it.
mutate_or_die "$SB/scripts/lint-orphan-test-suites.sh" \
  '^[[:space:]]*(sudo[[:space:]]+)?bash[[:space:]]+[A-Za-z0-9._/-]+\.test\.sh' \
  'ZZZ_SURFACE_6_REMOVED_NEVER_MATCHES'
run_lint "$SB"; rc=$?
assert_red "M13" "$rc"
assert_has "M13 — the loopback suite is reported as an orphan without surface 6" "${LOOPBACK_SUITE} ${ORPHAN_MSG}"
assert_has "M13 — surface 6 is reported dark" "registration surface 6 matched ZERO tracked suites"

# =============================================================================================
# M14 — surface 4 goes dark on the LINTER side rather than the workflow side. M9 removes the
# workflow step (the real-world failure); this removes the linter's ability to SEE that step
# (the guard-rot failure). They are different subjects with the same symptom, and only one of
# them is a change anybody would notice while reviewing a workflow diff.
# =============================================================================================
row M14 "the surface-4 detector stops matching (guard-side rot)"
new_sandbox m14
mutate_or_die "$SB/scripts/lint-orphan-test-suites.sh" \
  '^[[:space:]]*bash[[:space:]]+main\.test\.sh[[:space:]]*$' \
  'ZZZ_SURFACE_4_DETECTOR_NEVER_MATCHES'
run_lint "$SB"; rc=$?
assert_red "M14" "$rc"
assert_has "M14 — the per-surface zero-check names the dark surface" "registration surface 4 matched ZERO tracked suites"
assert_has "M14 — and the suite that surface covered is named" "${HOOK_SUITE} ${ORPHAN_MSG}"

# =============================================================================================
# M15 — the runner stops answering `--print-suite-globs`. M5 proves the linter notices a pattern
# being DELETED; this proves it notices the whole contract disappearing. Without the rc check,
# an unanswered flag yields an empty pattern set, and all 167 glob-registered suites are
# reported as orphans at once — a report so obviously wrong it gets ignored, taking the real
# findings with it. Fail-closed means saying WHY.
# =============================================================================================
row M15 "the runner no longer answers --print-suite-globs (the derivation contract itself)"
new_sandbox m15
mutate_or_die "$SB/scripts/test-all.sh" \
  'if [[ "${1:-}" == "--print-suite-globs" ]]; then' \
  'if [[ "${1:-}" == "--this-flag-was-removed" ]]; then'
run_lint "$SB"; rc=$?
assert_red "M15" "$rc"
assert_has "M15 — names the broken contract rather than reporting 167 phantom orphans" \
  "--print-suite-globs' exited 2 and printed 0 pattern(s)"
assert_has "M15 — and says not to re-copy the patterns into the linter" "rather than re-copying the patterns here"

# =============================================================================================
# M16 — POSITIVE CONTROL for the exclusion mechanism. M7, M11 and M12 each prove a malformed
# exclusion is REJECTED; none of them proves a well-formed one is ACCEPTED. Without this row,
# an exclusion mechanism that rejected everything — including correct entries — would score
# three kills and look healthy, and the next person with a legitimate suite to skip would find
# the escape hatch welded shut.
# =============================================================================================
row M16 "a well-formed exclusion suppresses its orphan and says so"
new_sandbox m16
mkdir -p "$SB/tools/nowhere" || harness_die "M16 mkdir"
: > "$SB/tools/nowhere/gamma.test.sh"
git -C "$SB" add -A >/dev/null 2>&1 || harness_die "M16 git add"
mutate_or_die "$SB/scripts/lint-orphan-test-suites.sh" 'EXCLUSIONS=()' \
  'EXCLUSIONS=( "tools/nowhere/gamma.test.sh|blocked on a fixture rewrite, tracked in #9999" )'
run_lint "$SB"; rc=$?
if (( rc == 0 )); then pass "M16 — a correctly-formed exclusion is accepted (exit 0)"; else
  fail "M16 — a correctly-formed exclusion was REJECTED (exit ${rc}); the escape hatch is welded shut"
  sed 's/^/    /' "$OUT" | head -10
fi
assert_has "M16 — the exclusion is announced with its reason" "note: tools/nowhere/gamma.test.sh excluded -- blocked on a fixture rewrite, tracked in #9999"
assert_lacks "M16 — and the suite is not also reported as an orphan" "tools/nowhere/gamma.test.sh ${ORPHAN_MSG}"

# --- Floors -----------------------------------------------------------------------------------
# TWO floors, because they catch different deletions. The ROW floor catches a whole row being
# deleted (the mutation matrix silently shrinking); the ASSERTION floor catches a row being
# hollowed out — kept in place, still printing its banner, with its assertions removed.
# The assertion floor is DERIVED, not a literal, for the reason the neighbouring MIN_ASSERTIONS
# comment in scripts/test-all-infra-coverage-notice.test.sh gives: a fixed literal acquires
# slack every time a list grows. M5 contributes two assertions per member of the glob it
# deletes (a precondition and a name check), so that term is accumulated from the fixture
# rather than restated. MIN_FIXED is the count produced by no loop, and it is the only number
# here ever edited by hand: 1 harness + 3 C0 + 3 M1 + 3 M2 + 3 M3 + 2 M4 + 1 M5 + 3 M6 + 2 M7
# + 3 M8 + 4 M9 + 3 M10 + 2 M11 + 2 M12 + 4 M13 + 3 M14 + 3 M15 + 3 M16 + 1 normalisation = 49.
MIN_ROWS=17
MIN_FIXED=49
MIN_ASSERTIONS=$(( MIN_FIXED + (2 * ${GLOB_MEMBER_N:-0}) ))
echo ""
if (( ROWS < MIN_ROWS )); then
  echo "FATAL: ${ROWS} mutation rows ran, expected >= ${MIN_ROWS} — a row was deleted, so the matrix silently shrank." >&2
  exit 1
fi
if (( PASS + FAIL < MIN_ASSERTIONS )); then
  echo "FATAL: only $((PASS + FAIL)) assertions ran, expected >= ${MIN_ASSERTIONS} — the suite was stranded, not clean." >&2
  exit 1
fi

echo "lint-orphan-test-suites.test.sh: ${ROWS} rows, $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] || exit 1
