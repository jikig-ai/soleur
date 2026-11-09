#!/usr/bin/env bash
# Fixture suite for mq-lever-e-verdict-12269.sh (#12269 lever-E soak probe).
#
# PROPERTY under test. The probe reads the live `max_entries_to_build` from
# infra/github/ruleset-ci-required.tf (via REPO_ROOT override) and arms on it:
#
#   value==2 (decline regime): count `merge_group` `ci.yml` runs with
#     conclusion=cancelled since earliest-28d.  >=2 -> exit 5 (waste appeared:
#     re-evaluate the flip; same threshold the gate used).  <2 -> exit 0.
#
#   value==1 (post-flip regime): find the ci-wallclock-p90 standing tracker via
#     find-or-file (issue list, exact title + github-actions author), read its
#     body, require `Report refreshed:` to postdate the flip merge (derived via
#     `git log -S'max_entries_to_build'` pickaxe), then read the REAL 8-column
#     row `| test | merge_group | <n> | <p50 s> | <p90 s> | <dur> | <bound> | <goal> |`
#     (SECONDS).  p50 > floor*1.2 OR p90 > floor*2.5 OR >=2 churn-cancelled runs
#     since the flip -> exit 5 (revert).  Else -> exit 0 (keep).
#
#   Any gh/git failure -> exit 3 (transient; re-poll). Probe prints exactly one
#   `REEVAL key=value...` line per run.
#
# STUBS. `gh` and `git` on PATH are fixture-backed stubs answering ONLY the
# argv the probe may legitimately issue; anything else exits 64 and is logged
# to calls.log (a wandering probe is loud, not silently vacuous). Values are
# synthesized (cq-test-fixtures-synthesized-only).
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROBE="$HERE/mq-lever-e-verdict-12269.sh"

fails=0
passes=0
pass() { printf '  PASS: %s\n' "$1"; passes=$((passes + 1)); }
fail() { printf '  FAIL: %s\n' "$1" >&2; fails=$((fails + 1)); }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Canonical fixture-dir guard (byte-identical copy; the fixture-dir-operand-assert
# suite pins every tracked copy).
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
assert_fixture_dir "$WORK"

command -v jq >/dev/null || { echo "FATAL: jq required for the fixture stub" >&2; exit 1; }

EARLIEST="2026-12-15T00:00:00Z"
FLIP_MERGED="2026-11-10T00:00:00Z"

# mkrepo <root> <value>: a minimal repo root whose tf carries the value, plus a
# commented copy naming the OTHER sanctioned value first (the probe must read
# the assignment, not the comment — the comment-first ordering is deliberate).
mkrepo() {
  local root="$1" v="$2" other=2
  [ "$v" = "2" ] && other=1
  mkdir -p "$root/infra/github"
  cat > "$root/infra/github/ruleset-ci-required.tf" <<TF
    # \`max_entries_to_build = $other\` (a historical value kept in comments)
    merge_queue {
      max_entries_to_build              = $v
    }
TF
}

# mkstub <dir>: fixture-backed gh + git. Fixtures consumed from $FIXTURE_DIR:
#   cancelled.json   -> gh run list ... --status cancelled (json array)
#   issues.json      -> gh issue list --search ... (json array)
#   tracker-body.txt -> gh issue view --json body (raw text)
#   pickaxe.txt      -> git log -S'max_entries_to_build' output (ISO ts)
#   fail             -> every gh call exits 1
mkstub() {
  local d="$1"
  mkdir -p "$d"
  cat > "$d/gh" <<'STUB'
#!/usr/bin/env bash
printf 'gh %s\n' "$*" >> "$FIXTURE_DIR/calls.log"
if [ -f "$FIXTURE_DIR/fail" ]; then echo "gh: simulated failure" >&2; exit 1; fi
case "$*" in
  "run list "*"merge_group"*"ci.yml"*"cancelled"*) cat "$FIXTURE_DIR/cancelled.json" ;;
  "issue list "*"ci-wallclock-p90"*) cat "$FIXTURE_DIR/issues.json" ;;
  "issue view "*"--json body"*) jqf='.'; prev=''; for a in "$@"; do [ "$prev" = "--jq" ] && jqf="$a"; prev="$a"; done; { printf '{"body":' ; jq -Rs . < "$FIXTURE_DIR/tracker-body.txt" ; printf '}' ; } | jq -r "$jqf" ;;
  *) echo "STUB-UNEXPECTED: $*" >> "$FIXTURE_DIR/calls.log"; exit 64 ;;
esac
STUB
  cat > "$d/git" <<'STUB'
#!/usr/bin/env bash
printf 'git %s\n' "$*" >> "$FIXTURE_DIR/calls.log"
case "$*" in
  "log "*"max_entries_to_build"*) cat "$FIXTURE_DIR/pickaxe.txt" ;;
  *) echo "STUB-UNEXPECTED: git $*" >> "$FIXTURE_DIR/calls.log"; exit 64 ;;
esac
STUB
  chmod +x "$d/gh" "$d/git"
}

# run_probe <label> <want-rc> <want-reeval-regex|->
run_probe() {
  local label="$1" want_rc="$2" want_re="$3"
  local out rc
  out="$(cd "$REPO_ROOT" && PATH="$STUB_DIR:$PATH" FIXTURE_DIR="$FIXTURE_DIR" \
        SOLEUR_FT_EARLIEST="$EARLIEST" SOLEUR_FT_P50_FLOOR=49 \
        bash "$PROBE" 2>&1)"; rc=$?
  local ok=1
  [ "$rc" -eq "$want_rc" ] || { ok=0; fail "$label: rc=$rc want $want_rc :: $out"; }
  local n
  n=$(grep -c '^REEVAL ' <<<"$out" || true)
  if [ "$n" -ne 1 ]; then ok=0; fail "$label: expected exactly one REEVAL line, got $n :: $out"; fi
  if [ "$want_re" != "-" ] && ! grep -qE "$want_re" <<<"$out"; then
    ok=0; fail "$label: REEVAL line missing /$want_re/ :: $out"
  fi
  [ "$ok" -eq 1 ] && pass "$label"
}

newcase() {
  FIXTURE_DIR="$(mktemp -d)"; assert_fixture_dir "$FIXTURE_DIR"
  STUB_DIR="$FIXTURE_DIR/stub"; mkstub "$STUB_DIR"
  : > "$FIXTURE_DIR/calls.log"
  REPO_ROOT="$FIXTURE_DIR/repo"
  printf '%s\n' "$FLIP_MERGED" > "$FIXTURE_DIR/pickaxe.txt"
  printf '[{"number":4242,"title":"ci-wallclock-p90: required-check wall-clock report","author":{"login":"github-actions"}}]' > "$FIXTURE_DIR/issues.json"
  printf '[]' > "$FIXTURE_DIR/cancelled.json"
  export FIXTURE_DIR REPO_ROOT
}

# ── value==2 arm ────────────────────────────────────────────────────────────
echo "-- value==2 arm --"

newcase; mkrepo "$REPO_ROOT" 2
run_probe "v2 zero cancelled runs -> exit 0 decline-hold" 0 'verdict=decline-hold'

newcase; mkrepo "$REPO_ROOT" 2
printf '[{"databaseId":1}]' > "$FIXTURE_DIR/cancelled.json"
run_probe "v2 ONE cancelled run -> exit 0 (gate-aligned >=2, not >=1)" 0 'verdict=decline-hold'

newcase; mkrepo "$REPO_ROOT" 2
printf '[{"databaseId":1},{"databaseId":2}]' > "$FIXTURE_DIR/cancelled.json"
run_probe "v2 two cancelled runs -> exit 5 waste-appeared" 5 'verdict=waste-appeared'

newcase; mkrepo "$REPO_ROOT" 2
: > "$FIXTURE_DIR/fail"
run_probe "v2 gh failure -> exit 3 repoll" 3 '-'

# ── value==1 arm ────────────────────────────────────────────────────────────
echo "-- value==1 arm --"

# REAL schema (8 columns, seconds) + Report refreshed POST-dating the flip.
GOOD_BODY='Report refreshed: 2026-11-20T09:00:00Z

| required check | surface | n | p50 (s) | p90 (s) | p90 dur (s) | bound (s) | goal (s) |
|---|---|---|---|---|---|---|---|
| test | merge_group | 30 | 2926 | 4100 | 2200 | 900 | 900 |'
# refreshed PRE-dating the flip -> repoll
STALE_BODY='Report refreshed: 2026-11-01T09:00:00Z

| test | merge_group | 30 | 2926 | 4100 | 2200 | 900 | 900 |'
# p50 materially worse (4800 > 2940*1.2=3528) -> revert
WORSE_P50_BODY='Report refreshed: 2026-11-20T09:00:00Z

| test | merge_group | 30 | 4800 | 6000 | 3000 | 900 | 900 |'
# p90 in the tail (> 2940*2.5=7350) while p50 flat -> revert
WORSE_P90_BODY='Report refreshed: 2026-11-20T09:00:00Z

| test | merge_group | 30 | 2900 | 8000 | 3000 | 900 | 900 |'

newcase; mkrepo "$REPO_ROOT" 1
printf '%s\n' "$GOOD_BODY" > "$FIXTURE_DIR/tracker-body.txt"
run_probe "v1 post-flip report, p50/p90 within tolerance -> exit 0 keep-flip" 0 'verdict=keep-flip'

newcase; mkrepo "$REPO_ROOT" 1
printf '%s\n' "$STALE_BODY" > "$FIXTURE_DIR/tracker-body.txt"
run_probe "v1 pre-flip report -> exit 3 repoll" 3 '-'

newcase; mkrepo "$REPO_ROOT" 1
printf '%s\n' "$WORSE_P50_BODY" > "$FIXTURE_DIR/tracker-body.txt"
run_probe "v1 p50 materially worse -> exit 5 revert" 5 'verdict=revert-warranted'

newcase; mkrepo "$REPO_ROOT" 1
printf '%s\n' "$WORSE_P90_BODY" > "$FIXTURE_DIR/tracker-body.txt"
run_probe "v1 tail-only regression (p50 flat, p90 blows) -> exit 5 revert" 5 'verdict=revert-warranted'

newcase; mkrepo "$REPO_ROOT" 1
printf '%s\n' "$GOOD_BODY" > "$FIXTURE_DIR/tracker-body.txt"
printf '[{"databaseId":1},{"databaseId":2}]' > "$FIXTURE_DIR/cancelled.json"
run_probe "v1 churn >=2 cancelled since flip -> exit 5 revert" 5 'verdict=revert-warranted churn=2'

newcase; mkrepo "$REPO_ROOT" 1
printf '%s\n' "$GOOD_BODY" > "$FIXTURE_DIR/tracker-body.txt"
printf '[]' > "$FIXTURE_DIR/issues.json"
run_probe "v1 tracker not found -> exit 3 repoll" 3 '-'

newcase; mkrepo "$REPO_ROOT" 1
printf '%s\n' "$GOOD_BODY" > "$FIXTURE_DIR/tracker-body.txt"
: > "$FIXTURE_DIR/fail"
run_probe "v1 gh failure -> exit 3 repoll" 3 '-'

newcase; mkrepo "$REPO_ROOT" 1
printf '%s\n' "$GOOD_BODY" > "$FIXTURE_DIR/tracker-body.txt"
: > "$FIXTURE_DIR/pickaxe.txt"
run_probe "v1 pickaxe empty -> exit 3 repoll" 3 '-'

# ── degenerate inputs ───────────────────────────────────────────────────────
echo "-- degenerate inputs --"

newcase; mkrepo "$REPO_ROOT" 9
printf '%s\n' "$GOOD_BODY" > "$FIXTURE_DIR/tracker-body.txt"
out="$(cd "$REPO_ROOT" && PATH="$STUB_DIR:$PATH" FIXTURE_DIR="$FIXTURE_DIR" SOLEUR_FT_EARLIEST="$EARLIEST" bash "$PROBE" 2>&1)"; rc=$?
if [ "$rc" -ne 0 ] && [ "$rc" -ne 5 ]; then
  pass "v9 unsanctioned value refuses to arm (rc=$rc)"
else
  fail "v9 unsanctioned value armed anyway (rc=$rc) :: $out"
fi

newcase; mkdir -p "$REPO_ROOT/infra/github" # tf absent entirely
out="$(cd "$REPO_ROOT" && PATH="$STUB_DIR:$PATH" FIXTURE_DIR="$FIXTURE_DIR" SOLEUR_FT_EARLIEST="$EARLIEST" bash "$PROBE" 2>&1)"; rc=$?
if [ "$rc" -eq 3 ]; then pass "missing tf -> exit 3 repoll"; else fail "missing tf -> rc=$rc :: $out"; fi

echo "=== $passes passed, $fails failed ==="
[ "$fails" -eq 0 ]
