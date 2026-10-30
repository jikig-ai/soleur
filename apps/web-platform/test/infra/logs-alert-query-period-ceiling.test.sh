#!/usr/bin/env bash
# Guard 3 of the #11631 plan: no native Better Stack logs alert is created with a query_period above 900 s, and the
# two retired once-a-day dead-man alerts stay gone.
#
# WHY. A logtail_exploration_alert whose row arrives once a day cannot see its row: the retired
# luks_monitor_host_timer_dark (query_period 97200) and claude_cost_capture_dark (86400) read `Current value: 0`
# through 33 healthy nights. Alerts created since 2026-10-01 are measured against a 900 s ceiling (the table in
# betterstack-logs-alerts.tf); a dead-man that needs a longer window is an archive-fed heartbeat
# (scripts/deadman-heartbeat-feeder.sh), not a longer window here. This suite is the sentinel that keeps the next
# one from being written the old way.
#
# WHAT IT READS. Every logtail_exploration_alert resource block in every .tf under apps/web-platform/infra/ (the
# working tree: tracked plus not-yet-committed files, so a new file cannot dodge the scan), after lexing out `#`, `//`
# and /* */ comments and heredoc bodies (the file carries query_period values inside comments, e.g. a dated
# measurement table and `# query_period = 2592000`). query_period is parsed per block; a value that is not an
# integer literal is a FAILURE, never a pass. Ceiling: 900 for every alert except the live legacy ones, which are
# allowlisted BY NAME, each with its own ceiling (a renamed copy of an allowlisted alert is therefore RED).
# ALLOWLIST CHANGES ARE EDITS TO THIS FILE, which review sees; the alerts at origin/main are printed so a weakening
# shows up as a diff of printed names.
#
# ANTI-VACUITY. The number of blocks the lexer parsed must equal an independent naive count of
# `resource "logtail_exploration_alert` lines (prefix match, no closing quote) and be at least 1: a lexer that finds
# nothing, or a rename of the resource kind, is a failure.
#
# MUTATIONS ARE COMMITTED. Each row is applied to a scratch copy of the .tf files by an exact-string edit that must
# match once, and must go RED (or, for the must-PASS rows, stay GREEN). Harness rows: the same checker with the
# ceiling raised to 100000 turns mutation 1 GREEN (the sentinel reads the ceiling); a new alert at exactly 900 stays
# GREEN.

set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../../../.." && pwd)"
INFRA_REL="apps/web-platform/infra"
APPLY_REL=".github/workflows/apply-web-platform-infra.yml"
CENSUS_REL="tests/scripts/test-infra-privileged-tier-census.sh"
PY="$(type -P python3)" || { echo "FATAL: python3 not found" >&2; exit 1; }

fails=0; passes=0; cases=0
pass() { printf '  PASS: %s\n' "$1"; passes=$((passes + 1)); }
fail() { printf '  FAIL: %s\n' "$1" >&2; fails=$((fails + 1)); }

assert_fixture_dir() {
  case "${1-}" in
    "") printf 'FATAL: fixture dir is EMPTY\n' >&2; exit 2 ;;
    */../*|*/..) printf 'FATAL: fixture dir %s contains ..; refusing\n' "$1" >&2; exit 2 ;;
    /proc/*|/sys/*|/dev/*) printf 'FATAL: fixture dir %s is a synthetic-fs path; refusing\n' "$1" >&2; exit 2 ;;
    /|//|/.) printf 'FATAL: fixture dir resolves to the filesystem root; refusing\n' >&2; exit 2 ;;
    /*) : ;;
    *)  printf 'FATAL: fixture dir %s is RELATIVE; refusing\n' "$1" >&2; exit 2 ;;
  esac
}
WORK="$(mktemp -d "${TMPDIR}/logs-alert-ceiling.XXXXXXXX")" || { echo "FATAL: mktemp failed" >&2; exit 1; }
assert_fixture_dir "$WORK"
trap 'rm -rf -- "$WORK"' EXIT

# ── the checker ──────────────────────────────────────────────────────────────────────────────
cat > "$WORK/checker.py" <<'PYCHK'
import re, sys, os

DEFAULT_CEILING = 900
# name -> its own ceiling. The live legacy alerts only; see the header.
ALLOW = {"claude_cost_daily_burn": 86400, "inngest_luks_wrong_volume": 5400}
RETIRED = ("luks_monitor_host_timer_dark", "claude_cost_capture_dark")
RETAINED_TARGETS = (
    "-target=logtail_exploration.claude_cost_capture_dark",
    "-target=logtail_exploration_alert.claude_cost_capture_dark",
    "-target=logtail_exploration.luks_monitor_host_timer_dark",
    "-target=logtail_exploration_alert.luks_monitor_host_timer_dark",
)
CENSUS_ENTRIES = (
    '"logtail_exploration.claude_cost_capture_dark": "#11631"',
    '"logtail_exploration_alert.claude_cost_capture_dark": "#11631"',
    '"logtail_exploration.luks_monitor_host_timer_dark": "#11631"',
    '"logtail_exploration_alert.luks_monitor_host_timer_dark": "#11631"',
)


def lex(s):
    """Return s with comments and heredoc bodies blanked (newlines kept). Strings are preserved."""
    out, i, n = [], 0, len(s)
    while i < n:
        c = s[i]
        if c == '"':
            j, depth = i + 1, 0
            while j < n:
                if s[j] == "\\":
                    j += 2
                    continue
                if s.startswith("${", j):
                    depth += 1
                    j += 2
                    continue
                if s[j] == "}" and depth:
                    depth -= 1
                elif s[j] == '"' and depth == 0:
                    break
                j += 1
            out.append(s[i:j + 1])
            i = j + 1
        elif c == "#" or s.startswith("//", i):
            j = s.find("\n", i)
            j = n if j == -1 else j
            i = j
        elif s.startswith("/*", i):
            j = s.find("*/", i + 2)
            j = n if j == -1 else j + 2
            out.append("\n" * s.count("\n", i, j))
            i = j
        elif s.startswith("<<", i) and re.match(r"<<-?[A-Za-z_][A-Za-z0-9_]*[ \t]*\n", s[i:]):
            m = re.match(r"<<(-?)([A-Za-z_][A-Za-z0-9_]*)[ \t]*\n", s[i:])
            tag = m.group(2)
            j = i + m.end()
            out.append("<<HEREDOC\n")
            while j < n:
                k = s.find("\n", j)
                k = n if k == -1 else k
                line = s[j:k]
                j = k + 1
                out.append("\n")
                if line.strip() == tag:
                    break
            i = j
        else:
            out.append(c)
            i += 1
    return "".join(out)


def find_close(s, i):
    """s[i] == '{'. Return the index of the matching '}' ignoring braces inside strings."""
    depth, j, n = 0, i, len(s)
    while j < n:
        c = s[j]
        if c == '"':
            j += 1
            d = 0
            while j < n:
                if s[j] == "\\":
                    j += 2
                    continue
                if s.startswith("${", j):
                    d += 1
                    j += 2
                    continue
                if s[j] == "}" and d:
                    d -= 1
                elif s[j] == '"' and d == 0:
                    break
                j += 1
        elif c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return j
        j += 1
    return -1


def alerts_in(text):
    """-> (list of (name, body-or-None-if-unbalanced), naive_count)."""
    lexed = lex(text)
    # Independent of the block parser: a prefix match (no closing quote) over the comment- and heredoc-free text, so
    # a renamed resource kind or a header the block regex cannot read is counted here and missing there.
    naive = len(re.findall(r'(?m)^[ \t]*resource "logtail_exploration_alert', lexed))
    found = []
    for m in re.finditer(r'(?m)^[ \t]*resource "logtail_exploration_alert" "([A-Za-z0-9_-]+)" \{', lexed):
        o = m.end() - 1
        c = find_close(lexed, o)
        found.append((m.group(1), lexed[o + 1:c] if c != -1 else None))
    return found, naive


def top_level_attr(body, key):
    """Value text of a top-level `key = value` attribute (depth 0 of this block's body), else None."""
    depth, vals = 0, []
    for line in body.split("\n"):
        if depth == 0:
            m = re.match(r"\s*" + re.escape(key) + r"\s*=\s*(.*?)\s*$", line)
            if m:
                vals.append(m.group(1))
        depth += line.count("{") - line.count("}")
    return vals[0] if vals else None


def main(infra_dir, apply_path, census_path):
    bad, seen = [], []
    naive_total = parsed_total = raw_total = 0
    names_all = set()
    tf_files = []
    for root, _d, files in os.walk(infra_dir):
        for f in files:
            if f.endswith(".tf"):
                tf_files.append(os.path.join(root, f))
    tf_files.sort()
    if not tf_files:
        bad.append("no-tf-files-found")
    for p in tf_files:
        text = open(p, encoding="utf-8").read()
        lexed = lex(text)
        found, naive = alerts_in(text)
        naive_total += naive
        parsed_total += len(found)
        raw_total += len(re.findall(r'(?m)^[ \t]*resource "logtail_exploration_alert', text))
        for kind in ("logtail_exploration", "logtail_exploration_alert"):
            for m in re.finditer(r'(?m)^[ \t]*resource "' + kind + r'" "([A-Za-z0-9_-]+)"', lexed):
                if m.group(1) in RETIRED:
                    bad.append("retired-resource-redeclared:%s.%s" % (kind, m.group(1)))
        for name, body in found:
            rel = os.path.relpath(p, infra_dir)
            if body is None:
                bad.append("unbalanced-block:%s:%s" % (rel, name))
                continue
            names_all.add(name)
            raw = top_level_attr(body, "query_period")
            if raw is None or not re.fullmatch(r"[0-9]+", raw):
                bad.append("unparsable-query_period:%s:%s=%r" % (rel, name, raw))
                continue
            qp = int(raw)
            ceiling = ALLOW.get(name, DEFAULT_CEILING)
            seen.append((name, qp, ceiling, rel))
            if qp > ceiling:
                bad.append("query_period-above-ceiling:%s:%s:%d>%d" % (rel, name, qp, ceiling))
    if parsed_total != naive_total or parsed_total < 1 or parsed_total > raw_total:
        bad.append("anti-vacuity:parsed=%d naive=%d raw=%d" % (parsed_total, naive_total, raw_total))
    apply_text = open(apply_path, encoding="utf-8").read()
    for t in RETAINED_TARGETS:
        if re.search(r"(?m)^[ \t]*" + re.escape(t) + r"( \\)?[ \t]*$", apply_text) is None:
            bad.append("retained-destroy-target-missing:%s" % t)
    census_text = open(census_path, encoding="utf-8").read()
    for e in CENSUS_ENTRIES:
        if e not in census_text:
            bad.append("census-intended-destroy-missing:%s" % e.split(":")[0].strip('"'))
    for name, qp, ceiling, rel in sorted(seen):
        print("alert %s query_period=%d ceiling=%d (%s)" % (name, qp, ceiling, rel))
    print("blocks parsed=%d naive=%d" % (parsed_total, naive_total))
    for b in bad:
        print("VIOLATION " + b)
    sys.exit(1 if bad else 0)


main(sys.argv[1], sys.argv[2], sys.argv[3])
PYCHK
"$PY" -I - "$WORK/checker.py" "$WORK/checker-wide.py" <<'PYM'
import sys
s = open(sys.argv[1]).read()
a = "DEFAULT_CEILING = 900"
assert s.count(a) == 1
open(sys.argv[2], "w").write(s.replace(a, "DEFAULT_CEILING = 100000"))
PYM

# ── a working-tree snapshot of the .tf files, the apply workflow and the census ───────────────
snap() { # <dest> -> copies the tracked-plus-untracked .tf files under the infra dir, the apply workflow, the census
  local dest="$1" f
  assert_fixture_dir "$dest"
  rm -rf -- "$dest"; mkdir -p "$dest/infra" "$dest/.github/workflows" "$dest/tests/scripts"
  while IFS= read -r f; do
    [[ -n "$f" && -f "$REPO/$f" ]] || continue
    mkdir -p "$dest/infra/$(dirname "${f#"$INFRA_REL"/}")"
    cp "$REPO/$f" "$dest/infra/${f#"$INFRA_REL"/}"
  done < <(git -C "$REPO" ls-files --cached --others --exclude-standard -- "$INFRA_REL/*.tf")
  cp "$REPO/$APPLY_REL" "$dest/apply.yml"
  cp "$REPO/$CENSUS_REL" "$dest/census.sh"
}
run_checker() { # <snapshot-dir> [checker] -> rc; output in $WORK/out
  "$PY" -I "${2:-$WORK/checker.py}" "$1/infra" "$1/apply.yml" "$1/census.sh" > "$WORK/out" 2>&1
}
edit() { # <snapshot-dir> <relative-file> <old> <new> -> exact-once replace; returns 0 if landed
  "$PY" -I - "$1/$2" "$3" "$4" <<'PYE'
import sys
p = sys.argv[1]
s = open(p).read()
if s.count(sys.argv[2]) != 1:
    sys.stderr.write("edit: %d occurrences\n" % s.count(sys.argv[2]))
    sys.exit(3)
open(p, "w").write(s.replace(sys.argv[2], sys.argv[3]))
PYE
}
append() { # <snapshot-dir> <relative-file> <text>
  printf '\n%s\n' "$3" >> "$1/$2"
}

BASE="$WORK/base"; snap "$BASE"

echo "== the shipped tree =="
cases=$((cases + 1))
if run_checker "$BASE"; then pass "no logtail_exploration_alert exceeds its ceiling; the retired alerts are absent; the retained destroy targets and census entries are present"
else fail "the shipped tree violates the sentinel"; sed 's/^/        | /' "$WORK/out" >&2; fi
sed 's/^/  | /' "$WORK/out"
cases=$((cases + 1))
_parsed="$(sed -n 's/^blocks parsed=\([0-9]*\) naive=.*/\1/p' "$WORK/out")"
if [[ "$_parsed" =~ ^[0-9]+$ ]] && (( _parsed >= 15 )); then pass "anti-vacuity: the lexer parsed $_parsed alert blocks (an independent naive count agrees)"
else fail "anti-vacuity: parsed '$_parsed' blocks"; fi
cases=$((cases + 1))
if ! grep -q 'alert claude_cost_capture_dark\|alert luks_monitor_host_timer_dark' "$WORK/out"; then pass "neither retired alert is among the parsed blocks"
else fail "a retired alert block is present"; fi
for _n in claude_cost_daily_burn inngest_luks_wrong_volume; do
  cases=$((cases + 1))
  if grep -q "^alert $_n " "$WORK/out"; then pass "the allowlisted legacy alert $_n is present and within its own ceiling"
  else fail "the allowlisted legacy alert $_n was not found (a stale allowlist entry, or the alert was renamed)"; fi
done
echo "-- alerts at origin/main (printed so a weakening shows as a diff of names) --"
if git -C "$REPO" cat-file -e origin/main:"$INFRA_REL/betterstack-logs-alerts.tf" 2>/dev/null; then
  git -C "$REPO" show origin/main:"$INFRA_REL/betterstack-logs-alerts.tf" \
    | "$PY" -I -c '
import re, sys
s = sys.stdin.read()
print("  origin/main:", " ".join(sorted(re.findall(r"(?m)^resource \"logtail_exploration_alert\" \"([a-z0-9_]+)\"", s))))'
else
  echo "  (origin/main is not available in this checkout; nothing to print)"
fi

echo "== committed mutation rows =="
expect_red() { # <row> <dir> <violation-substring> [checker]
  cases=$((cases + 1))
  if run_checker "$2" "${4:-}"; then fail "mutation row $1 SURVIVED (the sentinel stayed green)"
  elif grep -q "VIOLATION .*$3" "$WORK/out"; then pass "mutation row $1 is RED as predicted ($3)"
  else fail "mutation row $1 went red for another reason"; sed 's/^/        | /' "$WORK/out" >&2; fi
}
expect_green() { # <row> <dir> [checker]
  cases=$((cases + 1))
  if run_checker "$2" "${3:-}"; then pass "mutation row $1 stays GREEN (must-PASS)"
  else fail "mutation row $1 went red but must stay green"; sed 's/^/        | /' "$WORK/out" >&2; fi
}
landed() { # <row> <rc-of-edit>
  cases=$((cases + 1))
  if [[ "$2" == 0 ]]; then pass "mutation row $1 landed"; else fail "mutation row $1 did NOT land (its verdict would be vacuous)"; fi
}
ALERT_TPL='resource "logtail_exploration_alert" "%s" {
  exploration_id = logtail_exploration.inngest_step_524.id
  name           = "%s"
  alert_type     = "threshold"
  operator       = "higher_than"
  value          = 0
  query_period   = %s%s
  check_period   = 60
  recovery_period = 60
}'
mk_alert() { printf "$ALERT_TPL" "$1" "$1" "$2" "${3:-}"; }

# M1: add an alert with query_period = 3600
M1="$WORK/m1"; snap "$M1"; append "$M1" infra/betterstack-logs-alerts.tf "$(mk_alert synth_over_ceiling 3600)"; landed M1 0
expect_red M1 "$M1" 'query_period-above-ceiling:.*synth_over_ceiling:3600>900'
# M2: a compliant alert first, an over-limit one in a DIFFERENT file (not first-hit)
M2="$WORK/m2"; snap "$M2"; append "$M2" infra/betterstack-logs-alerts.tf "$(mk_alert synth_compliant 900)"
printf '%s\n%s\n' "$(mk_alert synth_second_ok 300)" "$(mk_alert synth_second_over 7200)" > "$M2/infra/zz-synth-extra.tf"; landed M2 0
expect_red M2 "$M2" 'zz-synth-extra.tf:synth_second_over:7200>900'
# M3: rename an allowlisted alert to a new name at 86400
M3="$WORK/m3"; snap "$M3"
edit "$M3" infra/betterstack-logs-alerts.tf 'resource "logtail_exploration_alert" "claude_cost_daily_burn"' 'resource "logtail_exploration_alert" "claude_cost_daily_burn_renamed"'; landed M3 $?
expect_red M3 "$M3" 'claude_cost_daily_burn_renamed:86400>900'
# M4: re-add a retired exploration, and (M4b) a retired alert
M4="$WORK/m4"; snap "$M4"; append "$M4" infra/betterstack-logs-alerts.tf 'resource "logtail_exploration" "luks_monitor_host_timer_dark" {
  name = "x"
}'; landed M4 0
expect_red M4 "$M4" 'retired-resource-redeclared:logtail_exploration.luks_monitor_host_timer_dark'
M4B="$WORK/m4b"; snap "$M4B"; append "$M4B" infra/betterstack-logs-alerts.tf "$(mk_alert claude_cost_capture_dark 900)"; landed M4b 0
expect_red M4b "$M4B" 'retired-resource-redeclared:logtail_exploration_alert.claude_cost_capture_dark'
# M5: remove one of the four retained -target lines
M5="$WORK/m5"; snap "$M5"
"$PY" -I - "$M5/apply.yml" <<'PYD'
import re, sys
p = sys.argv[1]
s = open(p).read()
lines = s.split("\n")
idx = [i for i, l in enumerate(lines) if l.strip().startswith("-target=logtail_exploration_alert.luks_monitor_host_timer_dark")]
if len(idx) != 1:
    sys.exit(3)
del lines[idx[0]]
open(p, "w").write("\n".join(lines))
PYD
landed M5 $?
expect_red M5 "$M5" 'retained-destroy-target-missing:-target=logtail_exploration_alert.luks_monitor_host_timer_dark'
M5B="$WORK/m5b"; snap "$M5B"
edit "$M5B" census.sh '"logtail_exploration.claude_cost_capture_dark": "#11631"' '"logtail_exploration.claude_cost_capture_dark_x": "#11631"'; landed M5b $?
expect_red M5b "$M5B" 'census-intended-destroy-missing'
# M6: the discovery finds zero alert blocks (the resource kind is renamed)
M6="$WORK/m6"; snap "$M6"
"$PY" -I - "$M6/infra/betterstack-logs-alerts.tf" <<'PYR'
import sys
p = sys.argv[1]
s = open(p).read()
n = s.count('resource "logtail_exploration_alert" ')
if n < 1:
    sys.exit(3)
open(p, "w").write(s.replace('resource "logtail_exploration_alert" ', 'resource "logtail_exploration_alertx" '))
PYR
landed M6 $?
expect_red M6 "$M6" 'anti-vacuity'
# M7: a query_period = 86400 appearing ONLY inside a comment, a heredoc and a block comment (must-PASS)
M7="$WORK/m7"; snap "$M7"
append "$M7" infra/betterstack-logs-alerts.tf '# query_period = 86400
// query_period = 86400
/* resource "logtail_exploration_alert" "in_block_comment" {
  query_period = 86400
} */
locals {
  synth_note = <<-NOTE
    resource "logtail_exploration_alert" "in_heredoc" {
      query_period = 86400
    }
  NOTE
}'
append "$M7" infra/betterstack-logs-alerts.tf "$(mk_alert synth_commented 900 ' # query_period = 86400 is not the value')"; landed M7 0
expect_green M7 "$M7"
# M8: a real over-limit block carrying a trailing comment is still parsed
M8="$WORK/m8"; snap "$M8"; append "$M8" infra/betterstack-logs-alerts.tf "$(mk_alert synth_trailing 3600 ' # a note')"; landed M8 0
expect_red M8 "$M8" 'synth_trailing:3600>900'
# M9: a value that is not an integer literal is unparsable (a failure, not a pass)
M9="$WORK/m9"; snap "$M9"; append "$M9" infra/betterstack-logs-alerts.tf "$(mk_alert synth_expr 'local.some_window')"; landed M9 0
expect_red M9 "$M9" 'unparsable-query_period:.*synth_expr'
# M10: an unbalanced block is a failure
M10="$WORK/m10"; snap "$M10"; append "$M10" infra/betterstack-logs-alerts.tf 'resource "logtail_exploration_alert" "synth_unbalanced" {
  query_period = 300'; landed M10 0
expect_red M10 "$M10" 'unbalanced-block'

echo "== harness rows =="
# (a) the sentinel reads its ceiling: with the ceiling at 100000, M1 goes GREEN.
cases=$((cases + 1))
if ! cmp -s "$WORK/checker.py" "$WORK/checker-wide.py"; then pass "harness: the wide-ceiling checker differs from the real one (landed)"; else fail "harness: the wide-ceiling checker did not land"; fi
expect_green "H1 (ceiling 100000 turns M1 green)" "$M1" "$WORK/checker-wide.py"
# (b) a new alert at exactly 900 stays green with the real checker.
H2="$WORK/h2"; snap "$H2"; append "$H2" infra/betterstack-logs-alerts.tf "$(mk_alert synth_at_ceiling 900)"
expect_green "H2 (a new alert at exactly 900 s)" "$H2"
H3="$WORK/h3"; snap "$H3"; append "$H3" infra/betterstack-logs-alerts.tf "$(mk_alert synth_at_901 901)"
expect_red H3 "$H3" 'synth_at_901:901>900'
# (c) the real checker is not vacuously green: it rejects an empty infra dir.
mkdir -p "$WORK/empty/infra"; cp "$BASE/apply.yml" "$BASE/census.sh" "$WORK/empty/"
expect_red "H4 (an empty infra dir)" "$WORK/empty" 'no-tf-files-found'

echo
echo "=== $passes passed, $fails failed, $cases cases ==="
if (( passes + fails != cases )); then
  printf 'FATAL: verdict conservation violated — %s+%s != %s cases.\n' "$passes" "$fails" "$cases" >&2
  exit 1
fi
MIN_PASSES=30
if (( passes < MIN_PASSES )); then
  printf 'FATAL: only %s passes, below the floor of %s -- the suite was truncated.\n' "$passes" "$MIN_PASSES" >&2
  exit 1
fi
(( fails == 0 )) || exit 1
echo "All $cases cases passed."
