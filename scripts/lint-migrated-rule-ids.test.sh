#!/usr/bin/env bash
# Tests for scripts/lint-migrated-rule-ids.sh — the registry placement + body-integrity guard
# for rules migrated out of AGENTS.rules.md (#8030, PR #8175).
#
# Every row of the plan's Guard Contract mutation matrix is a named case below. Two design
# rules the cases depend on:
#
#   1. The body hash is computed HERE by an independent implementation (Python), never by the
#      guard's own `--print-hash`. A fixture hashed by the code under test agrees with it by
#      construction and would pin nothing.
#   2. Every assertion helper runs the guard AND asserts in one call, so "delete the assertion,
#      keep the run" cannot be expressed, and CASES is incremented inside the helper — never in
#      pass()/fail() — so a neutered verdict helper breaks the PASS+FAIL==CASES conservation.
#
# Fixture ids use the `zz-` prefix: it is not a corpus section prefix (hr|wg|cq|rf|pdr|cm), so
# no rule-id lint mistakes a fixture for a citation.

export TMPDIR="${TMPDIR:-/var/tmp}"
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GUARD="$REPO_ROOT/scripts/lint-migrated-rule-ids.sh"

TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT
OUT="$TMPROOT/.out"

PASS=0
FAIL=0
CASES=0

pass() { PASS=$((PASS + 1)); printf '  PASS %s\n' "$1"; }
fail() {
  FAIL=$((FAIL + 1))
  printf '  FAIL %s\n' "$1"
  if [[ -n "${2:-}" ]]; then printf '       %s\n' "$2"; fi
}

# --- instrument self-test (ADR-193): both helpers must move their counter ------------------
pass "instrument self-test (pass)" >/dev/null
fail "instrument self-test (fail, EXPECTED)" >/dev/null
if [[ "$PASS" -ne 1 || "$FAIL" -ne 1 ]]; then
  printf 'FATAL: instrument self-test: pass/fail helpers did not both move (PASS=%s FAIL=%s)\n' "$PASS" "$FAIL" >&2
  exit 1
fi
PASS=0
FAIL=0

# --- fixture builders ----------------------------------------------------------------------
BANNER_TAIL=' — migrated out of `AGENTS.rules.md` on 2026-09-14 (PR #8175).**'
HOME_REL="plugins/soleur/skills/fixture/SKILL.md"

body_hash() {
  python3 -c 'import hashlib,re,sys; print(hashlib.sha256(re.sub(r"\s+"," ",sys.argv[1]).strip().encode()).hexdigest())' "$1"
}

new_root() {
  local r="$TMPROOT/$1"
  mkdir -p "$r/scripts" "$r/plugins/soleur/skills/fixture"
  : >"$r/scripts/migrated-rule-ids.txt"
  printf '%s' "$r"
}

# callout <id> <body-line>
callout() {
  printf '> **Rule `%s`%s\n' "$1" "$BANNER_TAIL"
  printf '> Domain-scoped per `cq-agents-md-tier-gate`: fixture banner sentence.\n'
  printf '>\n'
  printf '> %s\n' "$2"
}

body_for() { printf 'Fixture body for %s [id: %s] [skill-enforced: fixture Gate]. **Why:** fixture.' "$1" "$1"; }

# add_row <root> <id> <path> <heading> [hash-override]
add_row() {
  local h="${5:-$(body_hash "$(body_for "$2")")}"
  printf '%s | 2026-09-14 | #8175 | %s :: %s | %s\n' "$2" "$3" "$4" "$h" >>"$1/scripts/migrated-rule-ids.txt"
}

run_guard() {
  LINT_MIGRATED_RULE_IDS_ROOT="$1" bash "$GUARD" >"$OUT" 2>&1
  RC=$?
}

# expect_green <name> <root> [exact-needle]
expect_green() {
  CASES=$((CASES + 1))
  run_guard "$2"
  local o
  o="$(cat "$OUT")"
  if [[ "$RC" -eq 0 && "$o" == *"lint-migrated-rule-ids: OK"* && ( -z "${3:-}" || "$o" == *"$3"* ) ]]; then
    pass "$1"
  else
    fail "$1" "rc=$RC out=$(printf '%s' "$o" | tr '\n' '|' | cut -c1-400)"
  fi
}

# expect_red <name> <root> <needle> [needle2] [absent-needle]
expect_red() {
  CASES=$((CASES + 1))
  run_guard "$2"
  local o
  o="$(cat "$OUT")"
  if [[ "$RC" -eq 1 && "$o" == *"$3"* && ( -z "${4:-}" || "$o" == *"$4"* ) \
        && ( -z "${5:-}" || "$o" != *"$5"* ) && "$o" != *"lint-migrated-rule-ids: OK"* ]]; then
    pass "$1"
  else
    fail "$1" "rc=$RC needle=[$3] out=$(printf '%s' "$o" | tr '\n' '|' | cut -c1-400)"
  fi
}

canonical_home() {
  # <root> <id> — a heading, the callout directly under it, then a sibling heading.
  {
    printf '# Fixture skill\n\n### Gate A\n\n'
    callout "$2" "$(body_for "$2")"
    printf '\n### Gate B\n\nOther content.\n'
  } >"$1/$HOME_REL"
}

# --- 0: positive control, dispatched first --------------------------------------------------
r="$(new_root c0)"; canonical_home "$r" zz-fixture-alpha
add_row "$r" zz-fixture-alpha "$HOME_REL" "### Gate A"
expect_green "0 canonical fixture" "$r" "lint-migrated-rule-ids: OK (1 rows checked, 1 banners matched)"
if [[ "$FAIL" -ne 0 ]]; then
  printf 'FATAL: positive control failed — the fixture is broken and no other case proves anything\n' >&2
  exit 1
fi

# --- 1 / 1b: placement is section-scoped ---------------------------------------------------
r="$(new_root c1)"
{ printf '# Fixture\n\n'; callout zz-fixture-alpha "$(body_for zz-fixture-alpha)"; printf '\n### Gate A\n\nNothing here.\n'; } >"$r/$HOME_REL"
add_row "$r" zz-fixture-alpha "$HOME_REL" "### Gate A"
expect_red "1 callout above its heading" "$r" "not inside section" "zz-fixture-alpha"

r="$(new_root c1b)"
{ printf '# Fixture\n\n### Gate A\n\nProse mentions [id: zz-fixture-alpha] [skill-enforced: x] in passing.\n\n### Gate B\n\n'
  callout zz-fixture-alpha "$(body_for zz-fixture-alpha)"; } >"$r/$HOME_REL"
add_row "$r" zz-fixture-alpha "$HOME_REL" "### Gate A"
expect_red "1b prose token in section, callout elsewhere" "$r" "not inside section"

# --- 2 / 2b: floors -------------------------------------------------------------------------
r="$(new_root c2)"; printf '# comment only\n#\n' >"$r/scripts/migrated-rule-ids.txt"
expect_red "2 comment-only registry under fixture root" "$r" "0 rows checked < floor 1"

r="$(new_root c2b)"; canonical_home "$r" zz-fixture-alpha
add_row "$r" zz-fixture-alpha "$HOME_REL" "### Gate A"
cp "$GUARD" "$r/scripts/lint-migrated-rule-ids.sh"
CASES=$((CASES + 1))
( unset LINT_MIGRATED_RULE_IDS_ROOT; bash "$r/scripts/lint-migrated-rule-ids.sh" ) >"$OUT" 2>&1
RC=$?
o="$(cat "$OUT")"
if [[ "$RC" -eq 1 && "$o" == *"1 rows checked < floor 7"* ]]; then
  pass "2b default floor applies with no fixture root"
else
  fail "2b default floor applies with no fixture root" "rc=$RC out=$(printf '%s' "$o" | tr '\n' '|' | cut -c1-300)"
fi

# --- 3 / 3b / 3c / 3d: heading resolution ----------------------------------------------------
r="$(new_root c3)"; canonical_home "$r" zz-fixture-alpha
add_row "$r" zz-fixture-alpha "$HOME_REL" "### Gate A"
add_row "$r" zz-fixture-beta "$HOME_REL" "### Gate Missing"
expect_red "3 second row's heading absent" "$r" "heading not found" "zz-fixture-beta" "zz-fixture-alpha"

r="$(new_root c3b)"
{ printf '# Fixture\n\n### Pre-Ship Domain Review (conditional)\n\n'; callout zz-fixture-alpha "$(body_for zz-fixture-alpha)"; } >"$r/$HOME_REL"
add_row "$r" zz-fixture-alpha "$HOME_REL" "### Pre-Ship Domain Review"
expect_red "3b registry heading is a strict prefix" "$r" "heading not found"

r="$(new_root c3c)"
{ printf '# Fixture\n\n### Gate A\n\n'; callout zz-fixture-alpha "$(body_for zz-fixture-alpha)"; printf '\n### Gate A\n\nDuplicate.\n'; } >"$r/$HOME_REL"
add_row "$r" zz-fixture-alpha "$HOME_REL" "### Gate A"
expect_red "3c ambiguous heading" "$r" "ambiguous heading"

r="$(new_root c3d)"
{ printf '# Fixture\n\n(xxy)\n\n### (x|y).*\n\n'; callout zz-fixture-alpha "$(body_for zz-fixture-alpha)"; } >"$r/$HOME_REL"
add_row "$r" zz-fixture-alpha "$HOME_REL" "### (x|y).*"
expect_green "3d regex metacharacters are literal" "$r"

# --- 5b: banner without its body line --------------------------------------------------------
r="$(new_root c5b)"
{ printf '# Fixture\n\n### Gate A\n\n> **Rule `zz-fixture-alpha`%s\n> Banner sentence only.\n\nPlain paragraph [id: zz-fixture-alpha] [x].\n' "$BANNER_TAIL"; } >"$r/$HOME_REL"
add_row "$r" zz-fixture-alpha "$HOME_REL" "### Gate A"
expect_red "5b banner with no body line in its blockquote" "$r" "body line missing after banner"

# Escape check (plan): correct banner, but the body line names a DIFFERENT rule id.
r="$(new_root c5e)"
{ printf '# Fixture\n\n### Gate A\n\n'; callout zz-fixture-alpha "$(body_for zz-fixture-other)"; } >"$r/$HOME_REL"
add_row "$r" zz-fixture-alpha "$HOME_REL" "### Gate A"
expect_red "5e escape: body line names another rule" "$r" "body line missing after banner"

# --- 6 / 6b / 10: reverse scan ----------------------------------------------------------------
r="$(new_root c6)"; canonical_home "$r" zz-fixture-alpha
add_row "$r" zz-fixture-alpha "$HOME_REL" "### Gate A"
mkdir -p "$r/plugins/soleur/skills/other"
{ printf '# Other\n\n### X\n\n'; callout zz-fixture-orphan "$(body_for zz-fixture-orphan)"; } >"$r/plugins/soleur/skills/other/SKILL.md"
expect_red "6 banner for an id with no registry row" "$r" "no registry row" "zz-fixture-orphan"

r="$(new_root c6b)"; canonical_home "$r" zz-fixture-alpha
add_row "$r" zz-fixture-alpha "$HOME_REL" "### Gate A"
mkdir -p "$r/plugins/soleur/skills/other"
printf '# Other\n\n> **Rule `zz-fixture-orphan` - migrated out of AGENTS.rules.md on 2026-09-14.**\n' >"$r/plugins/soleur/skills/other/SKILL.md"
expect_red "6b non-canonical banner" "$r" "non-canonical migration banner" "other/SKILL.md"

r="$(new_root c10)"; canonical_home "$r" zz-fixture-alpha
add_row "$r" zz-fixture-alpha "$HOME_REL" "### Gate A"
mkdir -p "$r/plugins/soleur/skills/other"
printf '# Other\n\n- CI workflow edits. These were migrated out of AGENTS.md in an earlier pass.\n' >"$r/plugins/soleur/skills/other/SKILL.md"
expect_green "10 prose about AGENTS.md (not .rules.md) is not a banner" "$r"

# --- 7a / 7b / 8 / 9: section-boundary scanning ---------------------------------------------
r="$(new_root c7a)"
{ printf '# Fixture\n\n#### Deep Gate\n\n'; callout zz-fixture-alpha "$(body_for zz-fixture-alpha)"; printf '\n#### Next Deep\n\nx\n'; } >"$r/$HOME_REL"
add_row "$r" zz-fixture-alpha "$HOME_REL" "#### Deep Gate"
expect_green "7a level-4 heading section" "$r"

r="$(new_root c7b)"; canonical_home "$r" zz-fixture-alpha
printf 'zz-fixture-alpha|2026-09-14|#8175|%s :: ### Gate A|%s\n' "$HOME_REL" "$(body_hash "$(body_for zz-fixture-alpha)")" >"$r/scripts/migrated-rule-ids.txt"
expect_green "7b pipes without surrounding spaces" "$r"

r="$(new_root c8)"
{ printf '# Fixture\n\n### Gate A\n\n#### Sub-heading\n\nIntro.\n\n'; callout zz-fixture-alpha "$(body_for zz-fixture-alpha)"; printf '\n### Gate B\n'; } >"$r/$HOME_REL"
add_row "$r" zz-fixture-alpha "$HOME_REL" "### Gate A"
expect_green "8 lower-level sub-heading does not close the section" "$r"

r="$(new_root c9)"
{ printf '# Fixture\n\n### Gate A\n\n```bash\n## not a heading\n```\n\n'; callout zz-fixture-alpha "$(body_for zz-fixture-alpha)"; } >"$r/$HOME_REL"
add_row "$r" zz-fixture-alpha "$HOME_REL" "### Gate A"
expect_green "9a backtick fence with info string hides a heading line" "$r"

r="$(new_root c9b)"
{ printf '# Fixture\n\n### Gate A\n\n~~~\n## not a heading\n~~~\n\n'; callout zz-fixture-alpha "$(body_for zz-fixture-alpha)"; } >"$r/$HOME_REL"
add_row "$r" zz-fixture-alpha "$HOME_REL" "### Gate A"
expect_green "9b tilde fence hides a heading line" "$r"

# 9c: a 4-space-indented ``` is CONTENT, not a fence opener — so a real heading after it still
# closes the section. Discriminates in the RED direction: a guard that wrongly opened a fence
# here would swallow `### Gate B`, extend Gate A to EOF, and pass a misplaced callout.
r="$(new_root c9c)"
{ printf '# Fixture\n\n### Gate A\n\n    ```\n    indented code\n\n### Gate B\n\n'; callout zz-fixture-alpha "$(body_for zz-fixture-alpha)"; } >"$r/$HOME_REL"
add_row "$r" zz-fixture-alpha "$HOME_REL" "### Gate A"
expect_red "9c indented backticks do not open a fence" "$r" "not inside section"

# --- 11 / 12 / 13 / 14: grammar, confinement, fail-closed, accumulation -----------------------
r="$(new_root c11)"; canonical_home "$r" zz-fixture-alpha
add_row "$r" zz-fixture-alpha "$HOME_REL" "### Gate A"
printf 'zz-fixture-garbage | not a row\n' >>"$r/scripts/migrated-rule-ids.txt"
expect_red "11 malformed row" "$r" "malformed row" "line 2"

r="$(new_root c12a)"; add_row "$r" zz-fixture-alpha "../outside.md" "### Gate A"
expect_red "12a parent-relative path" "$r" "path escapes root"

r="$(new_root c12b)"; add_row "$r" zz-fixture-alpha "/abs/path.md" "### Gate A"
expect_red "12b absolute path" "$r" "path escapes root"

r="$(new_root c12c)"; canonical_home "$r" zz-fixture-alpha
ln -s "$r/$HOME_REL" "$r/plugins/soleur/skills/fixture/LINK.md"
add_row "$r" zz-fixture-alpha "plugins/soleur/skills/fixture/LINK.md" "### Gate A"
expect_red "12c symlinked home" "$r" "symlink"

r="$(new_root c12d)"; mkdir -p "$r/docs"
{ printf '# Doc\n\n### Gate A\n\n'; callout zz-fixture-alpha "$(body_for zz-fixture-alpha)"; } >"$r/docs/home.md"
add_row "$r" zz-fixture-alpha "docs/home.md" "### Gate A"
expect_red "12d home outside plugins/soleur" "$r" "outside plugins/soleur"

r="$(new_root c13a)"; rm -f "$r/scripts/migrated-rule-ids.txt"
expect_red "13a registry absent" "$r" "registry not found" "" "No such file"

r="$(new_root c13b)"; add_row "$r" zz-fixture-alpha "plugins/soleur/skills/fixture/GONE.md" "### Gate A"
expect_red "13b home file absent" "$r" "home file not found" "" "No such file"

r="$(new_root c14)"; canonical_home "$r" zz-fixture-alpha
add_row "$r" zz-fixture-beta "$HOME_REL" "### Nope One"
add_row "$r" zz-fixture-gamma "$HOME_REL" "### Nope Two"
expect_red "14 two bad rows named in one run" "$r" "zz-fixture-beta" "zz-fixture-gamma"

# --- 15 / 15b / 15c: body integrity ---------------------------------------------------------
r="$(new_root c15)"
{ printf '# Fixture\n\n### Gate A\n\n'; callout zz-fixture-alpha "$(body_for zz-fixture-alpha | sed 's/Fixture body/Fixture bodyX/')"; } >"$r/$HOME_REL"
add_row "$r" zz-fixture-alpha "$HOME_REL" "### Gate A"
expect_red "15 one word of the body edited, row hash unchanged" "$r" "body hash mismatch" "zz-fixture-alpha"

r="$(new_root c15b)"
{ printf '# Fixture\n\n### Gate A\n\n'; callout zz-fixture-alpha "$(body_for zz-fixture-alpha | sed 's/Fixture body for/Fixture   body  for/; s/\*\*Why:\*\* fixture/**Why:**    fixture/')"; } >"$r/$HOME_REL"
add_row "$r" zz-fixture-alpha "$HOME_REL" "### Gate A"
expect_green "15b whitespace-only change is normalised" "$r"

r="$(new_root c15c)"; canonical_home "$r" zz-fixture-alpha
printf 'zz-fixture-alpha | 2026-09-14 | #8175 | %s :: ### Gate A\n' "$HOME_REL" >"$r/scripts/migrated-rule-ids.txt"
expect_red "15c row missing its hash field" "$r" "malformed row"

# --- L: live registry, no override ------------------------------------------------------------
CASES=$((CASES + 1))
bash "$GUARD" >"$OUT" 2>&1
RC=$?
o="$(cat "$OUT")"
n="$(printf '%s' "$o" | sed -n 's/.*OK (\([0-9][0-9]*\) rows checked.*/\1/p')"
if [[ "$RC" -eq 0 && "$n" =~ ^[0-9]+$ && "$n" -ge 7 ]]; then
  pass "L live registry is clean ($n rows)"
else
  fail "L live registry is clean" "rc=$RC out=$(printf '%s' "$o" | tr '\n' '|' | cut -c1-500)"
fi

# --- floor + conservation (reported directly, never through fail()) --------------------------
printf '\nRESULT: %s passed, %s failed, %s cases\n' "$PASS" "$FAIL" "$CASES"
if [[ "$CASES" -lt 32 ]]; then
  printf 'FAIL: vacuity floor: only %s cases ran; expected >= 32\n' "$CASES" >&2
  exit 1
fi
if [[ $((PASS + FAIL)) -ne "$CASES" ]]; then
  printf 'FAIL: conservation: PASS(%s)+FAIL(%s) != CASES(%s) — a verdict helper was neutered\n' "$PASS" "$FAIL" "$CASES" >&2
  exit 1
fi
[[ "$FAIL" -eq 0 ]]
