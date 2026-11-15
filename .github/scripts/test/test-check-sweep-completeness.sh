#!/usr/bin/env bash
# Fixture tests for check-sweep-completeness.sh (#5269).
#
# Drives the REAL executor offline via its `$2` changeset-file argument
# (never `gh`, never the live registry). Each case builds a SYNTHETIC temp
# registry + changeset so the suite is deterministic and survives growth of
# the real .github/enforcement-contracts.json. Covers TS1-TS8 from the plan.
#
# When the SUT's contract changes, update this fixture in the same PR.

set -uo pipefail

DIR=$(cd "$(dirname "$0")" && pwd)
EXEC="$DIR/../check-sweep-completeness.sh"

PASS=0
FAIL=0

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Synthetic on-disk files the registries reference (absolute paths so the
# executor's `test -f` self-consistency check resolves regardless of CWD).
mkdir -p "$TMP/src" "$TMP/test"
TRIG="$TMP/src/cron-manifest.ts"
TRIG2="$TMP/src/other-manifest.ts"
DEP1="$TMP/test/cron-safe-commit-parity.test.ts"
DEP2="$TMP/test/cron-shared.test.ts"
DEP3="$TMP/test/other.test.ts"
LEGACY="$TMP/src/legacy-cron-manifest.ts"
MISSING="$TMP/test/does-not-exist.test.ts"   # intentionally NOT created
touch "$TRIG" "$TRIG2" "$DEP1" "$DEP2" "$DEP3" "$LEGACY"

# --- Registries ---
reg() { printf '%s' "$1" > "$TMP/$2"; echo "$TMP/$2"; }

REG_ONE=$(reg "{\"sibling_sets\":[{\"name\":\"set-a\",\"trigger\":[\"$TRIG\"],\"dependents\":[\"$DEP1\",\"$DEP2\"]}]}" reg_one.json)
REG_EMPTY=$(reg '{"sibling_sets":[]}' reg_empty.json)
REG_NOKEY=$(reg '{}' reg_nokey.json)
REG_MALFORMED=$(reg '{bad json' reg_malformed.json)
REG_EMPTYDEPS=$(reg "{\"sibling_sets\":[{\"name\":\"d\",\"trigger\":[\"$TRIG\"],\"dependents\":[]}]}" reg_emptydeps.json)
REG_MISSING=$(reg "{\"sibling_sets\":[{\"name\":\"m\",\"trigger\":[\"$TRIG\"],\"dependents\":[\"$MISSING\"]}]}" reg_missing.json)
REG_TWO=$(reg "{\"sibling_sets\":[{\"name\":\"set-a\",\"trigger\":[\"$TRIG\"],\"dependents\":[\"$DEP1\"]},{\"name\":\"set-b\",\"trigger\":[\"$TRIG2\"],\"dependents\":[\"$DEP3\"]}]}" reg_two.json)

# --- Changesets ---
cs() { printf '%s\n' "${@:2}" > "$TMP/$1"; echo "$TMP/$1"; }

CS_TRIGONLY=$(cs cs_trigonly.txt "$TRIG")
CS_ALL=$(cs cs_all.txt "$TRIG" "$DEP1" "$DEP2")
CS_DEPONLY=$(cs cs_deponly.txt "$DEP1")
CS_LEGACY=$(cs cs_legacy.txt "$LEGACY")
CS_BOTH_TRIG=$(cs cs_both_trig.txt "$TRIG" "$TRIG2")
CS_A_SAT_B_VIOL=$(cs cs_a_sat_b_viol.txt "$TRIG" "$DEP1" "$TRIG2")

# --- Harness ---
RC=0
OUT=""
run_check() { OUT=$(bash "$EXEC" "$1" "$2" 2>&1); RC=$?; }

ok() { echo "PASS [$1]"; PASS=$((PASS + 1)); }
bad() { echo "FAIL [$1]: $2"; echo "  rc=$RC out=$OUT"; FAIL=$((FAIL + 1)); }

assert_rc() { # name expected
  if [[ "$RC" -eq "$2" ]]; then ok "$1"; else bad "$1" "expected rc=$2 got rc=$RC"; fi
}
assert_out() { # name substring
  if grep -Fq "$2" <<<"$OUT"; then ok "$1"; else bad "$1" "expected output to contain '$2'"; fi
}

# TS1 — RED: trigger changed, both dependents missing → exit 1, names both
run_check "$REG_ONE" "$CS_TRIGONLY"
assert_rc "TS1-rc" 1
assert_out "TS1-names-dep1" "$DEP1"
assert_out "TS1-names-dep2" "$DEP2"

# TS2 — GREEN: trigger + all dependents → exit 0
run_check "$REG_ONE" "$CS_ALL"
assert_rc "TS2-rc" 0

# TS3 — no false positive: only a dependent changed (no trigger) → exit 0
run_check "$REG_ONE" "$CS_DEPONLY"
assert_rc "TS3-rc" 0

# TS4 — anchoring: a path containing the trigger's basename as a substring
# must NOT count as the trigger (exact full-path match only) → exit 0
run_check "$REG_ONE" "$CS_LEGACY"
assert_rc "TS4-rc" 0

# TS5 — registry integrity
run_check "$REG_EMPTY" "$CS_ALL";       assert_rc "TS5a-empty-array" 0
run_check "$REG_MALFORMED" "$CS_ALL";   assert_rc "TS5b-malformed" 1
run_check "$REG_NOKEY" "$CS_ALL";       assert_rc "TS5c-absent-key" 0
run_check "$REG_EMPTYDEPS" "$CS_TRIGONLY"; assert_rc "TS5d-empty-deps" 1
run_check "$REG_MISSING" "$CS_TRIGONLY"
assert_rc "TS5e-missing-path-rc" 1
assert_out "TS5e-missing-path-named" "$MISSING"

# TS6 — multi-set aggregation: both sets violated → exit 1, names deps from both
run_check "$REG_TWO" "$CS_BOTH_TRIG"
assert_rc "TS6-rc" 1
assert_out "TS6-names-dep1" "$DEP1"
assert_out "TS6-names-dep3" "$DEP3"

# TS7 — no masking: set A satisfied, set B violated → exit 1
run_check "$REG_TWO" "$CS_A_SAT_B_VIOL"
assert_rc "TS7-rc" 1
assert_out "TS7-names-dep3" "$DEP3"

# TS8 — fail-closed: no $2 and PR_NUMBER unset → exit 1 (never exit 0)
OUT=$(env -u PR_NUMBER bash "$EXEC" "$REG_ONE" 2>&1); RC=$?
assert_rc "TS8-fail-closed-rc" 1

# TS9 — fail-closed: a MISSING changeset file is unprovable → exit 1 (not a
# swallowed-empty exit 0). Regression guard for the silent-false-negative.
run_check "$REG_ONE" "$TMP/does-not-exist-changeset.txt"
assert_rc "TS9-missing-changeset-file" 1

# TS10 — legit: an empty-but-PRESENT changeset (0 files changed) → exit 0
CS_EMPTY=$(cs cs_empty.txt)
run_check "$REG_ONE" "$CS_EMPTY"
assert_rc "TS10-empty-present-changeset" 0

# TS11 — registry integrity: a set with an empty trigger array can never fire
# → exit 1 (fail-open rot guard), mirroring the empty-dependents check.
REG_NOTRIG=$(reg "{\"sibling_sets\":[{\"name\":\"nt\",\"trigger\":[],\"dependents\":[\"$DEP1\"]}]}" reg_notrig.json)
run_check "$REG_NOTRIG" "$CS_ALL"
assert_rc "TS11-empty-trigger" 1

# --- Derivation rows (changed-path reader remainder, row 19) ---------------------
# The ALLOW reader (`grep -Fxq` on the changeset) is fed by the files API. A
# newline or CR inside a filename forges a line: `z\n<dependent>` reads as the
# dependent being present, and `<dependent>\r` equals the dependent after the
# `tr -d '\r'` normalisation. Both routes must refuse (exit 1), never pass.
#
# `gh` is called by bare name, so a PATH shim stands in for it. The shim accepts
# EXACTLY the argv the script is modeled to send and exits 64 on anything else,
# so a changed flag (the drop---paginate mutation) is observable as a failure
# instead of being absorbed by a permissive stub. It applies the REAL jq filter
# the script passes, page by page, as `gh api --paginate --jq` does.
SHIM_DIR=$(mktemp -d -t sweep-shim.XXXXXXXX)
trap 'rm -rf "$TMP" "$SHIM_DIR"' EXIT
cat > "$SHIM_DIR/gh" <<'SHIM'
#!/usr/bin/env bash
# Modeled argv (exact):
#   gh api repos/{owner}/{repo}/pulls/<PR>/files --paginate --jq <expr>
#   gh pr diff <PR> --name-only
if [[ "${1:-}" == "api" && $# -eq 5 && "$2" == "repos/{owner}/{repo}/pulls/${SHIM_PR:?}/files" \
      && "$3" == "--paginate" && "$4" == "--jq" ]]; then
  [[ "${SHIM_API_RC:-0}" -eq 0 ]] || exit "$SHIM_API_RC"
  for page in "${SHIM_PAGES:?}"/*.json; do
    jq -r "$5" "$page" || exit 1
  done
  exit 0
fi
if [[ "${1:-}" == "pr" && $# -eq 4 && "$2" == "diff" && "$3" == "${SHIM_PR:?}" && "$4" == "--name-only" ]]; then
  [[ -f "${SHIM_DIFF:-/nonexistent}" ]] || exit 1
  cat "$SHIM_DIFF"
  exit 0
fi
echo "gh shim: unexpected argv: $*" >&2
exit 64
SHIM
chmod +x "$SHIM_DIR/gh"

PAGES="$SHIM_DIR/pages"
# pages_from <jq-array-expression-of-filenames> : write a single files-API page.
pages_from() { # name... (filenames as args; may contain newline/CR)
  rm -rf "$PAGES"; mkdir -p "$PAGES"
  printf '%s\0' "$@" | jq -Rs 'split("\u0000")[:-1] | map({filename: .})' > "$PAGES/p1.json"
}
run_derive() { # script
  OUT=$(env -u GH_TOKEN PATH="$SHIM_DIR:$PATH" SHIM_PR=7 SHIM_PAGES="$PAGES" SHIM_DIFF="${SHIM_DIFF:-}" \
          SHIM_API_RC="${SHIM_API_RC:-0}" PR_NUMBER=7 bash "$1" "$REG_ONE" 2>&1); RC=$?
}

# TD1 — files API happy path: trigger + both dependents -> exit 0.
pages_from "$TRIG" "$DEP1" "$DEP2"
run_derive "$EXEC"
assert_rc "TD1-api-clean-rc" 0

# TD1b — files API: trigger only -> exit 1 (the derivation still feeds the check).
pages_from "$TRIG"
run_derive "$EXEC"
assert_rc "TD1b-api-violation-rc" 1
assert_out "TD1b-names-dep1" "$DEP1"

# TD2 — newline-name: `z\n<DEP1>\n<DEP2>` would forge both dependents. Refuse.
pages_from "$TRIG" "z"$'\n'"$DEP1"$'\n'"$DEP2"
run_derive "$EXEC"
assert_rc "TD2-newline-name-rc" 1
assert_out "TD2-newline-name-msg" "newline or carriage return"

# TD3 — CR row: `<DEP1>\r` equals DEP1 after tr -d '\r'. Refuse (do not normalise away).
pages_from "$TRIG" "$DEP1"$'\r' "$DEP2"
run_derive "$EXEC"
assert_rc "TD3-cr-name-rc" 1
assert_out "TD3-cr-name-msg" "newline or carriage return"

# TD4 — forged TRIGGER with every dependent really changed: the forged line would
# make the set "triggered" and then satisfied (rc 0). A hostile name is refused.
pages_from "$DEP1" "$DEP2" "q"$'\n'"$TRIG"
run_derive "$EXEC"
assert_rc "TD4-forged-trigger-rc" 1

# TD5 — 3000-entry cap: GitHub caps the files API at 3000, so a listing that
# reaches it may be truncated (a missed trigger lets dependents pass). Exit 1.
rm -rf "$PAGES"; mkdir -p "$PAGES"
{ printf '%s\n' "$TRIG" "$DEP1" "$DEP2"; for i in $(seq 1 2997); do echo "pad/f$i.txt"; done; } \
  | jq -R '{filename: .}' | jq -s '.' > "$PAGES/p1.json"
run_derive "$EXEC"
assert_rc "TD5-cap-3000-rc" 1
assert_out "TD5-cap-3000-msg" "3000"
# TD5b — one below the cap is measured normally.
{ printf '%s\n' "$TRIG" "$DEP1" "$DEP2"; for i in $(seq 1 2996); do echo "pad/f$i.txt"; done; } \
  | jq -R '{filename: .}' | jq -s '.' > "$PAGES/p1.json"
run_derive "$EXEC"
assert_rc "TD5b-below-cap-rc" 0

# TD6 — API failure falls back to `gh pr diff --name-only`; a clean fallback passes.
pages_from "$TRIG"
SHIM_DIFF="$SHIM_DIR/shim_diff.txt"; printf '%s\n' "$TRIG" "$DEP1" "$DEP2" > "$SHIM_DIR/shim_diff.txt"
export SHIM_API_RC=1
run_derive "$EXEC"
assert_rc "TD6-fallback-clean-rc" 0

# TD7 — fallback route with a CR name: refuse (the CR would otherwise be stripped).
printf '%s\r\n' "$TRIG" > "$SHIM_DIR/shim_diff.txt"; printf '%s\n' "$DEP1" "$DEP2" >> "$SHIM_DIR/shim_diff.txt"
run_derive "$EXEC"
assert_rc "TD7-fallback-cr-rc" 1
assert_out "TD7-fallback-cr-msg" "carriage return"
unset SHIM_API_RC SHIM_DIFF

# TD8 — changeset file / stdin route: a CR anywhere is refused, not stripped.
CS_CR="$TMP/cs_cr.txt"; printf '%s\n' "$TRIG" "$DEP1" > "$CS_CR"; printf '%s\r\n' "$DEP2" >> "$CS_CR"
run_check "$REG_ONE" "$CS_CR"
assert_rc "TD8a-file-cr-rc" 1
OUT=$(printf '%s\r\n' "$TRIG" "$DEP1" "$DEP2" | bash "$EXEC" "$REG_ONE" - 2>&1); RC=$?
assert_rc "TD8b-stdin-cr-rc" 1

# TD9 — mutation: drop `--paginate` from the script. The exact-argv shim then
# exits 64 on the API call and the derivation cannot produce a changeset, so the
# clean row of TD1 must NOT stay green. (Proves the shim pins the argv.)
MUT="$SHIM_DIR/check-sweep-mut.sh"
sed 's/ --paginate / /' "$EXEC" > "$MUT"
if cmp -s "$EXEC" "$MUT"; then bad "TD9-mutation-applied" "sed did not change the script"; else ok "TD9-mutation-applied"; fi
pages_from "$TRIG" "$DEP1" "$DEP2"
run_derive "$MUT"
rm -f "$MUT"
if [[ "$RC" -ne 0 ]]; then ok "TD9-drop-paginate-killed"; else bad "TD9-drop-paginate-killed" "mutant still exited 0"; fi

echo ""
echo "Results: $PASS pass, $FAIL fail"
[[ "$FAIL" -eq 0 ]] || exit 1
# Vacuity floor: a neutered `ok`/`assert_*` (or deleted rows) must not read green.
MIN_ASSERTIONS=39
if [ "$PASS" -lt "$MIN_ASSERTIONS" ]; then
  echo "FAIL: only $PASS assertions passed, expected at least $MIN_ASSERTIONS"
  exit 1
fi
