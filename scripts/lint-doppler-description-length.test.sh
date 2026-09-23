#!/usr/bin/env bash
# Tests for scripts/lint-doppler-description-length.py.
#
# THE PROPERTY: no tracked Terraform `resource "doppler_*"` block carries a
# `description` whose literal's RAW SOURCE exceeds 255 UTF-8 bytes, or one the
# lint cannot measure statically. Doppler's API rejects an over-cap description at
# create/update time, and neither the provider schema nor `terraform plan` checks
# it, so the first observable failure is a red push apply. That happened after the
# credential-tiering merge (runs 35912754656, 35921899265): a 273-character
# doppler_project.infra_privileged description reddened every push apply.
#
# Each row below is one line of the plan's Guard 1 mutation matrix (rows 1-16,
# H1, H2, H4; H3 is scripts/guard-vacuity-floor.test.sh applied to this file).
# Adding an edge case means adding a `row` line, not editing shell.
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SUT="$SCRIPT_DIR/lint-doppler-description-length.py"

command -v python3 >/dev/null 2>&1 || { echo "FAIL: python3 missing — this suite cannot run its SUT"; exit 1; }
command -v git >/dev/null 2>&1 || { echo "FAIL: git missing — this suite cannot run its SUT"; exit 1; }

TMP_ROOT=$(mktemp -d -t doppler-desc.XXXXXXXX) || { echo "FATAL: cannot create scratch root" >&2; exit 1; }
: "${TMP_ROOT:?}"
[[ "$TMP_ROOT" == /* && -d "$TMP_ROOT" && ! -L "$TMP_ROOT" ]] || { echo "FATAL: bad scratch root" >&2; exit 1; }
readonly TMP_ROOT
trap 'rm -rf -- "$TMP_ROOT"' EXIT INT TERM

# The canonical fixture-dir assertion, byte-equal to the definition in
# plugins/soleur/test/test-helpers.sh (that file also defines assert_eq/PASS/FAIL
# counters this suite owns itself, so it is copied rather than sourced).
# plugins/soleur/test/fixture-dir-operand-assert.test.sh compares every copy in the
# tree against that one with comments stripped — edit there, then re-sync here.
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
assert_fixture_dir "$TMP_ROOT"

PASS=0; FAIL=0; cases=0
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

# Instrument self-test: both helpers must move their counter, or every verdict
# below is meaningless. Reset afterwards so conservation below counts rows only.
pass "instrument self-test (pass path)" >/dev/null
fail "instrument self-test (fail path)" >/dev/null
if [[ "$PASS" -ne 1 || "$FAIL" -ne 1 ]]; then
  printf 'FATAL: assertion helpers are not dispatching (PASS=%s FAIL=%s)\n' "$PASS" "$FAIL" >&2
  exit 2
fi
PASS=0; FAIL=0

[[ -f "$SUT" ]] || { echo "  FAIL: $SUT missing (RED expected before implementation)"; echo "0 passed, 1 failed"; exit 1; }

# --- fixture builders ---------------------------------------------------------
x() { printf '%*s' "$1" '' | tr ' ' x; }          # exactly N ASCII bytes
lit() { printf '"%s"' "$1"; }                       # a double-quoted HCL literal
dp() { # <type> <name> <description-value-source> -> a terraform-fmt-shaped block
  printf 'resource "%s" "%s" {\n  name        = "n"\n  description = %s\n}\n\n' "$1" "$2" "$3"
}
fx() { # <row-name> -> fresh fixture dir, printed
  local d="$TMP_ROOT/$1"
  assert_fixture_dir "$d"
  mkdir -p "$d" || { echo "FATAL: mkdir $d failed" >&2; exit 2; }
  printf '%s\n' "$d"
}

LAST_OUT=""
# row <name> <expected-exit> <expected-substring> <file>...
row() {
  local name="$1" want_rc="$2" want="$3"; shift 3
  local out rc=0
  out="$(python3 "$SUT" "$@" 2>&1)" || rc=$?
  LAST_OUT="$out"
  if [[ "$rc" -eq "$want_rc" && "$out" == *"$want"* ]]; then
    pass "$name (rc=$rc)"
  else
    fail "$name — want rc=$want_rc + '$want', got rc=$rc: $(printf '%s' "$out" | head -5 | tr '\n' '|')"
  fi
}

ORIG_273="Tier B (#8209, ADR-241): credentials that write infra, read another tier's secrets, or reach third-party installations. Read only via DOPPLER_TOKEN_INFRA_PRIVILEGED, an environment secret on main-only environments. Values are operator-supplied; none passes through tfstate."

# 1 — regression: the original 273-character string.
d=$(fx r1); assert_fixture_dir "$d"; dp doppler_project infra_privileged "$(lit "$ORIG_273")" > "$d/a.tf"
cases=$((cases + 1)); row "1 regression: original 273-char description" 1 "doppler_project.infra_privileged description is 273 bytes" "$d/a.tf"

# 2 — boundary: 256 bytes.
d=$(fx r2); assert_fixture_dir "$d"; dp doppler_project p "$(lit "$(x 256)")" > "$d/a.tf"
cases=$((cases + 1)); row "2 boundary: 256 bytes" 1 "description is 256 bytes" "$d/a.tf"

# 3 — boundary pair: exactly 255 bytes, then a trailing # comment.
d=$(fx r3); assert_fixture_dir "$d"; dp doppler_project p "$(lit "$(x 255)") # trailing comment" > "$d/a.tf"
cases=$((cases + 1)); row "3 boundary: 255 bytes + trailing # comment passes" 0 "max 255/255 bytes" "$d/a.tf"

# 4 — second member in one file.
d=$(fx r4); assert_fixture_dir "$d"; { dp doppler_project first "$(lit ok)"; dp doppler_project second "$(lit "$(x 256)")"; } > "$d/a.tf"
cases=$((cases + 1)); row "4 second member of one file" 1 "doppler_project.second description is 256 bytes" "$d/a.tf"

# 5 — second file.
d=$(fx r5); assert_fixture_dir "$d"; dp doppler_project good "$(lit ok)" > "$d/ok.tf"; dp doppler_project bad "$(lit "$(x 256)")" > "$d/bad.tf"
cases=$((cases + 1)); row "5 second file in one scan" 1 "bad.tf" "$d/ok.tf" "$d/bad.tf"

# 6 — type family beyond doppler_project.
d=$(fx r6); assert_fixture_dir "$d"; dp doppler_change_request_policy p "$(lit "$(x 256)")" > "$d/a.tf"
cases=$((cases + 1)); row "6 type family: doppler_change_request_policy" 1 "doppler_change_request_policy.p description is 256 bytes" "$d/a.tf"

# 7 — unmeasurable shapes fail closed.
d=$(fx r7a); assert_fixture_dir "$d"; dp doppler_project p 'var.d' > "$d/a.tf"
cases=$((cases + 1)); row "7a unmeasurable: var reference" 1 "cannot measure" "$d/a.tf"
d=$(fx r7b); assert_fixture_dir "$d"; dp doppler_project p '"${var.a} x"' > "$d/a.tf"
cases=$((cases + 1)); row "7b unmeasurable: leading interpolation" 1 "cannot measure" "$d/a.tf"
d=$(fx r7c); assert_fixture_dir "$d"; dp doppler_project p '"x ${var.a}"' > "$d/a.tf"
cases=$((cases + 1)); row "7c unmeasurable: mid-string interpolation" 1 "cannot measure" "$d/a.tf"
d=$(fx r7d); assert_fixture_dir "$d"; dp doppler_project p '"%{ for i in range(50) }xxxxxxxx%{ endfor }"' > "$d/a.tf"
cases=$((cases + 1)); row "7d unmeasurable: template directive" 1 "cannot measure" "$d/a.tf"
d=$(fx r7e); assert_fixture_dir "$d"; dp doppler_project p '"a" != "" ? var.long : "b"' > "$d/a.tf"
cases=$((cases + 1)); row "7e unmeasurable: literal followed by an expression" 1 "cannot measure" "$d/a.tf"

# 8 — multibyte: 254 ASCII + one em dash = 255 characters, 257 bytes.
d=$(fx r8); assert_fixture_dir "$d"; dp doppler_project p "$(lit "$(x 254)—")" > "$d/a.tf"
cases=$((cases + 1)); row "8 multibyte: bytes, not characters" 1 "description is 257 bytes" "$d/a.tf"

# 9 — the lint's own dispatch: two distinct vacuity messages.
d=$(fx r9a); assert_fixture_dir "$d"; printf 'variable "v" {\n  description = "d"\n}\n\nresource "github_repository" "r" {\n  description = "d"\n}\n' > "$d/a.tf"
cases=$((cases + 1)); row "9a vacuous: no doppler_* resource" 1 "no doppler_* resource found" "$d/a.tf"
d=$(fx r9b); assert_fixture_dir "$d"; printf 'resource "doppler_project" "p" {\n  name = "n"\n}\n' > "$d/a.tf"
cases=$((cases + 1)); row "9b vacuous: no description measured" 1 "no description measured" "$d/a.tf"

# 10 — reorder: the description after a nested lifecycle block (its } at column 2).
reorder() { printf 'resource "doppler_project" "p" {\n  name = "n"\n  lifecycle {\n    prevent_destroy = true\n  }\n  description = %s\n}\n' "$1"; }
d=$(fx r10); assert_fixture_dir "$d"; reorder "$(lit "$(x 256)")" > "$d/a.tf"
cases=$((cases + 1)); row "10 reorder: description after a nested block" 1 "doppler_project.p description is 256 bytes" "$d/a.tf"
d=$(fx r10t); assert_fixture_dir "$d"; reorder "$(lit ok)" > "$d/a.tf"
cases=$((cases + 1)); row "10 twin: compliant description after a nested block" 0 "1 description(s) measured" "$d/a.tf"

# 11 — escapes are counted raw: \" is 2 source bytes for 1 decoded byte.
d=$(fx r11); assert_fixture_dir "$d"; dp doppler_project p "\"$(x 253)\\\"x\"" > "$d/a.tf"   # 255 decoded, 256 raw
cases=$((cases + 1)); row "11 escapes counted raw (256 raw)" 1 "description is 256 bytes" "$d/a.tf"
d=$(fx r11t); assert_fixture_dir "$d"; dp doppler_project p "\"$(x 253)\\\"\"" > "$d/a.tf"   # 254 decoded, 255 raw
cases=$((cases + 1)); row "11 twin: 255 raw passes" 0 "max 255/255 bytes" "$d/a.tf"

# 12 — a blank line inside the doppler block never clears the header.
blank() { printf 'resource "doppler_project" "p" {\n  name = "n"\n\n  description = %s\n}\n' "$1"; }
d=$(fx r12); assert_fixture_dir "$d"; blank "$(lit "$(x 256)")" > "$d/a.tf"
cases=$((cases + 1)); row "12 blank line before the description" 1 "description is 256 bytes" "$d/a.tf"
d=$(fx r12t); assert_fixture_dir "$d"; blank "$(lit ok)" > "$d/a.tf"
cases=$((cases + 1)); row "12 twin: compliant after a blank line" 0 "1 description(s) measured" "$d/a.tf"

# 13 — unformatted shapes fail closed, never a silent skip.
d=$(fx r13a); assert_fixture_dir "$d"; { dp doppler_project good "$(lit ok)"; printf 'resource "doppler_project" "p" {\n  lifecycle {\n}\n  description = %s\n}\n' "$(lit "$(x 256)")"; } > "$d/a.tf"
cases=$((cases + 1)); row "13a column-0 nested } then a description" 1 "outside any top-level block" "$d/a.tf"
d=$(fx r13b); assert_fixture_dir "$d"; { dp doppler_project good "$(lit ok)"; printf 'resource "doppler_project" "p" {\ndescription = %s\n}\n' "$(lit "$(x 256)")"; } > "$d/a.tf"
cases=$((cases + 1)); row "13b description at column 0" 1 "attribute at column 0" "$d/a.tf"
d=$(fx r13c); assert_fixture_dir "$d"; { dp doppler_project good "$(lit ok)"; printf 'resource "doppler_project" "x" { description = %s }\n' "$(lit "$(x 300)")"; } > "$d/a.tf"
cases=$((cases + 1)); row "13c one-line doppler block" 1 "one-line doppler block" "$d/a.tf"

# 14 — an escaped template and a trailing // comment are measured, not rejected.
d=$(fx r14a); assert_fixture_dir "$d"; dp doppler_project p '"a $${literal} b %%{ also } c"' > "$d/a.tf"
cases=$((cases + 1)); row "14a escaped template sequences pass" 0 "1 description(s) measured" "$d/a.tf"
d=$(fx r14b); assert_fixture_dir "$d"; dp doppler_project p "$(lit "$(x 255)") // c" > "$d/a.tf"
cases=$((cases + 1)); row "14b 255 bytes + trailing // comment passes" 0 "max 255/255 bytes" "$d/a.tf"

# 15 — no-argument mode scans every tracked *.tf from the repo top level.
d=$(fx r15); assert_fixture_dir "$d"
(
  # Strip every GIT_* variable by PREFIX: under lefthook GIT_DIR/GIT_INDEX_FILE point at
  # the caller's live repo, and GIT_DIR beats cwd — the fixture would stage into it.
  while IFS= read -r v; do unset "$v"; done < <(compgen -e | grep '^GIT_' || true)
  cd "$d" || exit 2
  git init -q . || exit 2
  mkdir -p infra/github apps/x || exit 2
  dp doppler_project p "$(lit "$(x 256)")" > infra/github/x.tf
  git add infra/github/x.tf || exit 2
  cd apps/x || exit 2
  rc=0; out="$(python3 "$SUT" 2>&1)" || rc=$?
  printf '%s\n' "$rc" > "$d/.rc"; printf '%s\n' "$out" > "$d/.out"
)
r15_rc="$(cat "$d/.rc" 2>/dev/null || echo missing)"
cases=$((cases + 1))
if [[ "$r15_rc" == 1 ]] && grep -qF 'infra/github/x.tf' "$d/.out"; then
  pass "15 no-arg mode scans from the repo top level, not the cwd"
else
  fail "15 no-arg mode — rc=$r15_rc out=$(head -3 "$d/.out" 2>/dev/null | tr '\n' '|')"
fi

# 16 — every finding is printed, never only the first.
d=$(fx r16); assert_fixture_dir "$d"; dp doppler_project one "$(lit "$(x 256)")" > "$d/a.tf"; dp doppler_project two "$(lit "$(x 300)")" > "$d/b.tf"
cases=$((cases + 1)); row "16 two findings: the first" 1 "doppler_project.one description is 256 bytes" "$d/a.tf" "$d/b.tf"
cases=$((cases + 1)); row "16 two findings: the second" 1 "doppler_project.two description is 300 bytes" "$d/a.tf" "$d/b.tf"

# H1 — non-doppler descriptions are out of scope, however long.
d=$(fx h1); assert_fixture_dir "$d"
{ printf 'variable "x" {\n  description = %s\n}\n\n' "$(lit "$(x 600)")"
  printf 'resource "github_repository_environment" "e" {\n  description = %s\n}\n\n' "$(lit "$(x 400)")"
  dp doppler_project p "$(lit ok)"; } > "$d/a.tf"
cases=$((cases + 1)); row "H1 non-doppler descriptions ignored" 0 "1 description(s) measured" "$d/a.tf"

# H2 — a commented-out description is not a description.
d=$(fx h2); assert_fixture_dir "$d"; printf 'resource "doppler_project" "p" {\n  # description = %s\n  description = "ok"\n}\n' "$(lit "$(x 300)")" > "$d/a.tf"
cases=$((cases + 1)); row "H2 commented-out description ignored" 0 "1 description(s) measured" "$d/a.tf"

# H5 — a heredoc body never moves the header. A column-0 `}` or `KEY=value` inside
# one is text, not structure; honouring it would hide the description after it.
d=$(fx h5); assert_fixture_dir "$d"
# The opener is assembled at run time: a literal one in this file's source reads as a real
# heredoc to guard-vacuity-floor.test.sh, which then skips every line after it — this floor too.
hd_open='<''<EOT'
printf 'resource "doppler_project" "p" {\n  name = %sEOT\n}\nFOO=bar\nresource "x" "y" {\nEOT\n  description = %s\n}\n' "${hd_open%EOT}" "$(lit "$(x 256)")" > "$d/a.tf"
cases=$((cases + 1)); row "H5 heredoc body is not structure" 1 "doppler_project.p description is 256 bytes" "$d/a.tf"
d=$(fx h5b); assert_fixture_dir "$d"
printf '/*\n}\nFOO=bar\n*/\nresource "doppler_project" "p" {\n  description = "ok"\n}\n' > "$d/a.tf"
cases=$((cases + 1)); row "H5b block-comment body is not structure" 0 "1 description(s) measured" "$d/a.tf"

# H7 — a column-0 comment inside a doppler block is skipped, not read as a header.
d=$(fx h7); assert_fixture_dir "$d"; printf 'resource "doppler_project" "p" {\n  name = "n"\n# note at column 0\n  description = %s\n}\n' "$(lit "$(x 256)")" > "$d/a.tf"
cases=$((cases + 1)); row "H7 column-0 comment inside a doppler block" 1 "doppler_project.p description is 256 bytes" "$d/a.tf"

# H8 — any indentation is a description: a deeper-indented one is measured too.
d=$(fx h8); assert_fixture_dir "$d"; printf 'resource "doppler_project" "p" {\n    description = %s\n}\n' "$(lit "$(x 256)")" > "$d/a.tf"
cases=$((cases + 1)); row "H8 deeper-indented description is measured" 1 "doppler_project.p description is 256 bytes" "$d/a.tf"

# H6 — control characters in a resource name are stripped before printing, so a
# crafted name cannot start a CI log line with a workflow command.
d=$(fx h6); assert_fixture_dir "$d"; printf 'resource "doppler_project" "p\x1b[31m" {\n  description = %s\n}\n' "$(lit "$(x 256)")" > "$d/a.tf"
cases=$((cases + 1)); row "H6 control characters stripped from names" 1 "doppler_project.p[31m description is 256 bytes" "$d/a.tf"

# H4 — live: the real tree passes, with bounds rather than exact numbers so a
# legitimate description edit does not break this row.
cases=$((cases + 1))
live_rc=0; live_out="$(cd "$REPO_ROOT" && python3 "$SUT" 2>&1)" || live_rc=$?
live_d="$(printf '%s' "$live_out" | sed -nE 's/.* ([0-9]+) description\(s\) measured.*/\1/p')"
live_m="$(printf '%s' "$live_out" | sed -nE 's/.*max ([0-9]+)\/255 bytes.*/\1/p')"
if [[ "$live_rc" -eq 0 && "$live_d" =~ ^[0-9]+$ && "$live_m" =~ ^[0-9]+$ ]] \
   && (( live_d >= 4 && live_m <= 255 )); then
  pass "H4 live tree: $live_d descriptions, max $live_m/255"
else
  fail "H4 live tree — rc=$live_rc out=$(printf '%s' "$live_out" | head -5 | tr '\n' '|')"
fi

if [[ $((PASS + FAIL)) -ne "$cases" ]]; then
  printf 'FATAL: conservation — PASS+FAIL=%d but %d rows ran\n' "$((PASS + FAIL))" "$cases"
  exit 1
fi
MIN_CASES=36
if (( cases < MIN_CASES )); then
  printf '[FATAL] assertion floor: only %d assertions ran (floor %d)\n' "$cases" "$MIN_CASES"
  exit 1
fi

echo "$PASS passed, $FAIL failed ($cases rows)"
[[ "$FAIL" -eq 0 ]] || exit 1
