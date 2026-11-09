#!/usr/bin/env bash
# Fixture suite for mq-lever-e-verdict-12269.sh (#12269 lever-E soak probe).
#
# PROPERTY under test. The probe reads the live `max_entries_to_build` from
# infra/github/ruleset-ci-required.tf (via REPO_ROOT override) and arms on it:
#
#   value==2 (decline regime): count `merge_group` `ci.yml` runs with
#     conclusion=cancelled since earliest-28d.  >=1 -> exit 5 (waste appeared:
#     re-evaluate the flip).  0 -> exit 0 (premise still absent: tracker closes).
#
#   value==1 (post-flip regime): read the `test` merge_group p50 row in the
#     ci-wallclock-p90 tracker body (gh issue view <TRACKER>). If the row's
#     measurement window does NOT postdate the flip merge timestamp -> exit 3
#     (re-poll next sweep — a pre-flip row is not an after-sample). Materially
#     worse than the before-window floor -> exit 5 (revert warranted).
#     Otherwise -> exit 0 (keep).
#
#   Any gh failure -> exit 3 (transient; re-poll). Probe prints exactly one
#   `REEVAL key=value...` line per run.
#
# STUB. `gh` on PATH is a fixture-backed stub answering ONLY the argv the
# probe may legitimately issue; anything else exits 64 and is logged to
# calls.log (a wandering probe is loud, not silently vacuous). Values are
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

# ── fixture repo root ───────────────────────────────────────────────────────
# mkrepo <value>: a minimal repo root whose ruleset-ci-required.tf carries the
# given max_entries_to_build.
mkrepo() {
  local root="$1" v="$2"
  mkdir -p "$root/infra/github"
  cat > "$root/infra/github/ruleset-ci-required.tf" <<TF
    merge_queue {
      max_entries_to_build              = $v
    }
TF
}

# ── gh stub ─────────────────────────────────────────────────────────────────
# Writes the stub into $STUB_DIR; fixtures consumed from $FIXTURE_DIR:
#   cancelled.json      -> gh run list --event merge_group --workflow ci.yml --status cancelled
#   tracker-body.txt    -> gh issue view <TRACKER> --json body
#   fail                -> if this file exists, every gh call exits 1
mkstub() {
  local d="$1"
  mkdir -p "$d"
  cat > "$d/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FIXTURE_DIR/calls.log"
if [ -f "$FIXTURE_DIR/fail" ]; then echo "gh: simulated failure" >&2; exit 1; fi
case "$*" in
  "run list "*"merge_group"*"ci.yml"*"cancelled"*) cat "$FIXTURE_DIR/cancelled.json" ;;
  "issue view "*"--json body"*) jqf='.'; prev=''; for a in "$@"; do [ "$prev" = "--jq" ] && jqf="$a"; prev="$a"; done; { printf '{"body":' ; jq -Rs . < "$FIXTURE_DIR/tracker-body.txt" ; printf '}' ; } | jq -r "$jqf" ;;
  *) echo "STUB-UNEXPECTED: $*" >> "$FIXTURE_DIR/calls.log"; exit 64 ;;
esac
STUB
  chmod +x "$d/gh"
}

# run_probe <label> <want-rc> <want-reeval-regex|->
run_probe() {
  local label="$1" want_rc="$2" want_re="$3"
  local out rc
  out="$(cd "$REPO_ROOT" && PATH="$STUB_DIR:$PATH" FIXTURE_DIR="$FIXTURE_DIR" \
        SOLEUR_FT_EARLIEST="$EARLIEST" SOLEUR_FT_TRACKER=4242 \
        SOLEUR_FT_FLIP_MERGED="$FLIP_MERGED" SOLEUR_FT_P50_FLOOR=49 \
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
  export FIXTURE_DIR REPO_ROOT
}

# ── value==2 arm ────────────────────────────────────────────────────────────
echo "-- value==2 arm --"

newcase; mkrepo "$REPO_ROOT" 2
printf '[]' > "$FIXTURE_DIR/cancelled.json"
run_probe "v2 no cancelled runs -> exit 0 keep" 0 'verdict=decline-hold'

newcase; mkrepo "$REPO_ROOT" 2
printf '[{"databaseId":1,"conclusion":"cancelled","createdAt":"2026-11-20T00:00:00Z"}]' > "$FIXTURE_DIR/cancelled.json"
run_probe "v2 one cancelled run -> exit 5 waste appeared" 5 'verdict=waste-appeared'

newcase; mkrepo "$REPO_ROOT" 2
printf '[]' > "$FIXTURE_DIR/cancelled.json"
: > "$FIXTURE_DIR/fail"
run_probe "v2 gh failure -> exit 3 repoll" 3 '-'

# ── value==1 arm ────────────────────────────────────────────────────────────
echo "-- value==1 arm --"

# tracker row whose measurement window postdates the flip merge
GOOD_BODY='| check | event | p50 | p90 | window |
| test | merge_group | 55m | 71m | 2026-11-12..2026-11-19 |'
# tracker row predating the flip (window ends before merge)
STALE_BODY='| check | event | p50 | p90 | window |
| test | merge_group | 48m | 60m | 2026-10-20..2026-10-27 |'
# worse p50 on a post-flip window
WORSE_BODY='| check | event | p50 | p90 | window |
| test | merge_group | 80m | 95m | 2026-11-12..2026-11-19 |'

newcase; mkrepo "$REPO_ROOT" 1
printf '%s\n' "$GOOD_BODY" > "$FIXTURE_DIR/tracker-body.txt"
run_probe "v1 post-flip window, p50 within tolerance -> exit 0 keep" 0 'verdict=keep-flip'

newcase; mkrepo "$REPO_ROOT" 1
printf '%s\n' "$STALE_BODY" > "$FIXTURE_DIR/tracker-body.txt"
run_probe "v1 pre-flip window row -> exit 3 repoll" 3 '-'

newcase; mkrepo "$REPO_ROOT" 1
printf '%s\n' "$WORSE_BODY" > "$FIXTURE_DIR/tracker-body.txt"
run_probe "v1 p50 materially worse -> exit 5 revert" 5 'verdict=revert-warranted'

newcase; mkrepo "$REPO_ROOT" 1
printf '%s\n' "$GOOD_BODY" > "$FIXTURE_DIR/tracker-body.txt"
: > "$FIXTURE_DIR/fail"
run_probe "v1 gh failure -> exit 3 repoll" 3 '-'

# ── unparseable / missing tf ────────────────────────────────────────────────
echo "-- degenerate inputs --"

newcase; mkrepo "$REPO_ROOT" 9
printf '[]' > "$FIXTURE_DIR/cancelled.json"
printf '%s\n' "$GOOD_BODY" > "$FIXTURE_DIR/tracker-body.txt"
out="$(cd "$REPO_ROOT" && PATH="$STUB_DIR:$PATH" FIXTURE_DIR="$FIXTURE_DIR" SOLEUR_FT_EARLIEST="$EARLIEST" bash "$PROBE" 2>&1)"; rc=$?
if [ "$rc" -ne 0 ] && [ "$rc" -ne 5 ] && [ "$rc" -ne 3 ]; then
  pass "v9 unsanctioned value refuses to arm (rc=$rc)"
elif [ "$rc" -eq 3 ]; then
  # exit 3 (cannot determine state -> repoll) is also acceptable; never exit 0/5 on an unread value
  pass "v9 unsanctioned value exits 3 repoll (rc=$rc)"
else
  fail "v9 unsanctioned value armed anyway (rc=$rc) :: $out"
fi

echo "=== $passes passed, $fails failed ==="
[ "$fails" -eq 0 ]
