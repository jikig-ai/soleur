#!/usr/bin/env bash
# Tests for scripts/lint-doppler-description-length.py.
#
# THE PROPERTY: no tracked Terraform `resource "doppler_*"` block sends Doppler a
# `description` over 255 bytes, or one the lint cannot measure statically. Doppler
# rejects an over-cap description at create/update time and neither the provider
# schema nor `terraform plan` checks it, so the first observable failure is a red
# push apply -- which is what a 273-character doppler_project.infra_privileged did
# after the credential-tiering merge.
#
# Rows 1-16, H1, H2 are the plan's Guard 1 matrix. The N rows are the layouts a
# review panel showed defeating the first, line-based version (a fake heredoc in a
# string or comment, inline and mid-line block comments, unquoted labels, a BOM, a
# column-0 continuation, `description=` without spaces) plus the NFC, exit-code,
# log-injection and scan-set rows. The live tree is asserted by the separate
# `-live` registration in scripts/test-all.sh, not here.
#
# Every must-FAIL row anchors on `<file>:<line>: <type>.<name> ...`, never a bare
# token, and `row` refuses any output carrying a Python traceback: a crash exits 1
# like a finding and prints the failing source line, which would otherwise satisfy
# the expected substring.
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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

# row <name> <expected-exit> <expected-substring> <file>...
# The verdict owner. A traceback is never an acceptable output, whatever the rc.
row() {
  local name="$1" want_rc="$2" want="$3"; shift 3
  local out rc=0
  out="$(python3 "$SUT" "$@" 2>&1)" || rc=$?
  if [[ "$rc" -eq "$want_rc" && "$out" == *"$want"* && "$out" != *Traceback* ]]; then
    pass "$name (rc=$rc)"
  else
    fail "$name — want rc=$want_rc + '$want', got rc=$rc: $(printf '%s' "$out" | head -5 | tr '\n' '|')"
  fi
}
# row_absent <name> <expected-exit> <forbidden-substring> <file>...
row_absent() {
  local name="$1" want_rc="$2" forbidden="$3"; shift 3
  local out rc=0
  out="$(python3 "$SUT" "$@" 2>&1)" || rc=$?
  if [[ "$rc" -eq "$want_rc" && "$out" != *"$forbidden"* && "$out" != *Traceback* ]]; then
    pass "$name (rc=$rc)"
  else
    fail "$name — want rc=$want_rc and no '$forbidden', got rc=$rc: $(printf '%s' "$out" | head -5 | tr '\n' '|')"
  fi
}

# row/row_absent self-test: each must REJECT a wrong substring and a wrong rc, or a
# row that asserts only "it exited 1" reads as a pinned finding. Counters unwound.
d=$(fx selftest); assert_fixture_dir "$d"; dp doppler_project p "$(lit "$(x 256)")" > "$d/a.tf"
row "self-test: wrong substring" 1 "no such finding text" "$d/a.tf" >/dev/null
row "self-test: wrong rc" 0 "description is 256 bytes" "$d/a.tf" >/dev/null
row "self-test: true case" 1 "description is 256 bytes" "$d/a.tf" >/dev/null
row_absent "self-test: forbidden present" 1 "description is 256 bytes" "$d/a.tf" >/dev/null
if [[ "$PASS" -ne 1 || "$FAIL" -ne 3 ]]; then
  printf 'FATAL: row/row_absent cannot reject (PASS=%s FAIL=%s, want 1/3)\n' "$PASS" "$FAIL" >&2
  exit 2
fi
PASS=0; FAIL=0

ORIG_273="Tier B (#8209, ADR-241): credentials that write infra, read another tier's secrets, or reach third-party installations. Read only via DOPPLER_TOKEN_INFRA_PRIVILEGED, an environment secret on main-only environments. Values are operator-supplied; none passes through tfstate."

# 1 — regression: the original 273-character string.
d=$(fx r1); assert_fixture_dir "$d"; dp doppler_project infra_privileged "$(lit "$ORIG_273")" > "$d/a.tf"
cases=$((cases + 1)); row "1 regression: original 273-char description" 1 "a.tf:3: doppler_project.infra_privileged description is 273 bytes" "$d/a.tf"

# 2 — boundary: 256 bytes.
d=$(fx r2); assert_fixture_dir "$d"; dp doppler_project p "$(lit "$(x 256)")" > "$d/a.tf"
cases=$((cases + 1)); row "2 boundary: 256 bytes" 1 "a.tf:3: doppler_project.p description is 256 bytes" "$d/a.tf"

# 3 — boundary pair: exactly 255 bytes, then a trailing # comment.
d=$(fx r3); assert_fixture_dir "$d"; dp doppler_project p "$(lit "$(x 255)") # trailing comment" > "$d/a.tf"
cases=$((cases + 1)); row "3 boundary: 255 bytes + trailing # comment passes" 0 "max 255/255 bytes" "$d/a.tf"

# 4 — second member in one file.
d=$(fx r4); assert_fixture_dir "$d"; { dp doppler_project first "$(lit ok)"; dp doppler_project second "$(lit "$(x 256)")"; } > "$d/a.tf"
cases=$((cases + 1)); row "4 second member of one file" 1 "a.tf:8: doppler_project.second description is 256 bytes" "$d/a.tf"

# 5 — second file.
d=$(fx r5); assert_fixture_dir "$d"; dp doppler_project good "$(lit ok)" > "$d/ok.tf"; dp doppler_project bad "$(lit "$(x 256)")" > "$d/bad.tf"
cases=$((cases + 1)); row "5 second file in one scan" 1 "bad.tf:3: doppler_project.bad description is 256 bytes" "$d/ok.tf" "$d/bad.tf"

# 6 — type family beyond doppler_project.
d=$(fx r6); assert_fixture_dir "$d"; dp doppler_change_request_policy p "$(lit "$(x 256)")" > "$d/a.tf"
cases=$((cases + 1)); row "6 type family: doppler_change_request_policy" 1 "a.tf:3: doppler_change_request_policy.p description is 256 bytes" "$d/a.tf"

# 7 — unmeasurable shapes fail closed.
d=$(fx r7a); assert_fixture_dir "$d"; dp doppler_project p 'var.d' > "$d/a.tf"
cases=$((cases + 1)); row "7a unmeasurable: var reference" 1 "a.tf:3: doppler_project.p description is not a single string literal; cannot measure" "$d/a.tf"
d=$(fx r7b); assert_fixture_dir "$d"; dp doppler_project p '"${var.a} x"' > "$d/a.tf"
cases=$((cases + 1)); row "7b unmeasurable: leading interpolation" 1 "a.tf:3: doppler_project.p description is not a single string literal" "$d/a.tf"
d=$(fx r7c); assert_fixture_dir "$d"; dp doppler_project p '"x ${var.a}"' > "$d/a.tf"
cases=$((cases + 1)); row "7c unmeasurable: mid-string interpolation" 1 "a.tf:3: doppler_project.p description is not a single string literal" "$d/a.tf"
d=$(fx r7d); assert_fixture_dir "$d"; dp doppler_project p '"%{ for i in range(50) }xxxxxxxx%{ endfor }"' > "$d/a.tf"
cases=$((cases + 1)); row "7d unmeasurable: template directive" 1 "a.tf:3: doppler_project.p description is not a single string literal" "$d/a.tf"
d=$(fx r7e); assert_fixture_dir "$d"; dp doppler_project p '"a" != "" ? var.long : "b"' > "$d/a.tf"
cases=$((cases + 1)); row "7e unmeasurable: literal followed by an expression" 1 "a.tf:3: doppler_project.p description is not a single string literal" "$d/a.tf"
d=$(fx r7f); assert_fixture_dir "$d"; dp doppler_project p '"a" /* c */ == "" ? var.long : "b"' > "$d/a.tf"
cases=$((cases + 1)); row "7f unmeasurable: a comment hides the rest of the expression" 1 "a.tf:3: doppler_project.p description is not a single string literal" "$d/a.tf"
# The opener is assembled at run time: a literal one in this file's source reads as a
# real heredoc to guard-vacuity-floor.test.sh, which then skips every line after it.
hd='<''<'
d=$(fx r7g); assert_fixture_dir "$d"; printf 'resource "doppler_project" "p" {\n  description = %sEOT\n%s\nEOT\n}\n' "$hd" "$(x 300)" > "$d/a.tf"
cases=$((cases + 1)); row "7g unmeasurable: heredoc description" 1 "a.tf:2: doppler_project.p description is not a single string literal" "$d/a.tf"

# 8 — multibyte: 254 ASCII + one em dash = 255 characters, 257 bytes.
d=$(fx r8); assert_fixture_dir "$d"; dp doppler_project p "$(lit "$(x 254)—")" > "$d/a.tf"
cases=$((cases + 1)); row "8 multibyte: bytes, not characters" 1 "a.tf:3: doppler_project.p description is 257 bytes" "$d/a.tf"

# 9 — the lint's own dispatch: two distinct vacuity messages, each exclusive.
d=$(fx r9a); assert_fixture_dir "$d"; printf 'variable "v" {\n  description = "d"\n}\n\nresource "github_repository" "r" {\n  description = "d"\n}\n' > "$d/a.tf"
cases=$((cases + 1)); row "9a vacuous: no doppler_* resource" 1 "no doppler_* resource found" "$d/a.tf"
cases=$((cases + 1)); row_absent "9a vacuous: only its own message" 1 "no description measured" "$d/a.tf"
d=$(fx r9b); assert_fixture_dir "$d"; printf 'resource "doppler_project" "p" {\n  name = "n"\n}\n' > "$d/a.tf"
cases=$((cases + 1)); row "9b vacuous: no description measured" 1 "no description measured" "$d/a.tf"

# 10 — reorder: the description after a nested lifecycle block.
reorder() { printf 'resource "doppler_project" "p" {\n  name = "n"\n  lifecycle {\n    prevent_destroy = true\n  }\n  description = %s\n}\n' "$1"; }
d=$(fx r10); assert_fixture_dir "$d"; reorder "$(lit "$(x 256)")" > "$d/a.tf"
cases=$((cases + 1)); row "10 reorder: description after a nested block" 1 "a.tf:6: doppler_project.p description is 256 bytes" "$d/a.tf"
d=$(fx r10t); assert_fixture_dir "$d"; reorder "$(lit ok)" > "$d/a.tf"
cases=$((cases + 1)); row "10 twin: compliant description after a nested block" 0 "1 description(s) measured" "$d/a.tf"

# 11 — escapes are counted raw: \" is 2 source bytes for 1 decoded byte.
d=$(fx r11); assert_fixture_dir "$d"; dp doppler_project p "\"$(x 253)\\\"x\"" > "$d/a.tf"   # 255 decoded, 256 raw
cases=$((cases + 1)); row "11 escapes counted raw (256 raw)" 1 "a.tf:3: doppler_project.p description is 256 bytes" "$d/a.tf"
d=$(fx r11t); assert_fixture_dir "$d"; dp doppler_project p "\"$(x 253)\\\"\"" > "$d/a.tf"   # 254 decoded, 255 raw
cases=$((cases + 1)); row "11 twin: 255 raw passes" 0 "max 255/255 bytes" "$d/a.tf"

# 12 — a blank line inside the doppler block changes nothing.
blank() { printf 'resource "doppler_project" "p" {\n  name = "n"\n\n  description = %s\n}\n' "$1"; }
d=$(fx r12); assert_fixture_dir "$d"; blank "$(lit "$(x 256)")" > "$d/a.tf"
cases=$((cases + 1)); row "12 blank line before the description" 1 "a.tf:4: doppler_project.p description is 256 bytes" "$d/a.tf"
d=$(fx r12t); assert_fixture_dir "$d"; blank "$(lit ok)" > "$d/a.tf"
cases=$((cases + 1)); row "12 twin: compliant after a blank line" 0 "1 description(s) measured" "$d/a.tf"

# 13 — unformatted layouts are still measured: structure is brackets, not columns.
d=$(fx r13a); assert_fixture_dir "$d"; printf 'resource "doppler_project" "p" {\n  lifecycle {\n}\n  description = %s\n}\n' "$(lit "$(x 256)")" > "$d/a.tf"
cases=$((cases + 1)); row "13a column-0 nested } then a description" 1 "a.tf:4: doppler_project.p description is 256 bytes" "$d/a.tf"
d=$(fx r13b); assert_fixture_dir "$d"; printf 'resource "doppler_project" "p" {\ndescription = %s\n}\n' "$(lit "$(x 256)")" > "$d/a.tf"
cases=$((cases + 1)); row "13b description at column 0" 1 "a.tf:2: doppler_project.p description is 256 bytes" "$d/a.tf"
d=$(fx r13c); assert_fixture_dir "$d"; printf 'resource "doppler_project" "x" { description = %s }\n' "$(lit "$(x 300)")" > "$d/a.tf"
cases=$((cases + 1)); row "13c one-line doppler block" 1 "a.tf:1: doppler_project.x description is 300 bytes" "$d/a.tf"

# 14 — an escaped template and a trailing // comment are measured, not rejected.
d=$(fx r14a); assert_fixture_dir "$d"; dp doppler_project p '"a $${literal} b %%{ also } c"' > "$d/a.tf"
cases=$((cases + 1)); row "14a escaped template sequences pass" 0 "1 description(s) measured" "$d/a.tf"
d=$(fx r14b); assert_fixture_dir "$d"; dp doppler_project p "$(lit "$(x 255)") // c" > "$d/a.tf"
cases=$((cases + 1)); row "14b 255 bytes + trailing // comment passes" 0 "max 255/255 bytes" "$d/a.tf"

# 15 — no-argument mode scans every tracked *.tf from the repo TOP LEVEL (at any
# depth), not the cwd; and the GIT_* scrub keeps a hostile environment from
# redirecting the fixture repo into the caller's index.
d=$(fx r15); assert_fixture_dir "$d"
decoy="$TMP_ROOT/r15-decoy"; assert_fixture_dir "$decoy"
git init -q "$decoy" || { echo "FATAL: git init decoy failed" >&2; exit 2; }
decoy_before="$(git -C "$decoy" ls-files | wc -l)"
(
  export GIT_DIR="$decoy/.git" GIT_INDEX_FILE="$decoy/.git/index"
  # Strip every GIT_* variable by PREFIX: under lefthook GIT_DIR/GIT_INDEX_FILE point at
  # the caller's live repo, and GIT_DIR beats cwd — the fixture would stage into it.
  while IFS= read -r v; do unset "$v"; done < <(compgen -e | grep '^GIT_' || true)
  cd "$d" || exit 2
  git init -q . || exit 2
  mkdir -p infra/github apps/x/infra/sub apps/y || exit 2
  dp doppler_project p "$(lit "$(x 256)")" > infra/github/x.tf
  dp doppler_project q "$(lit "$(x 257)")" > apps/x/infra/sub/y.tf
  git add infra/github/x.tf apps/x/infra/sub/y.tf || exit 2
  cd apps/y || exit 2
  rc=0; out="$(python3 "$SUT" 2>&1)" || rc=$?
  printf '%s\n' "$rc" > "$d/.rc"; printf '%s\n' "$out" > "$d/.out"
)
r15_rc="$(cat "$d/.rc" 2>/dev/null || echo missing)"
cases=$((cases + 1))
if [[ "$r15_rc" == 1 ]] \
   && grep -qF 'infra/github/x.tf:3: doppler_project.p description is 256 bytes' "$d/.out" \
   && grep -qF 'apps/x/infra/sub/y.tf:3: doppler_project.q description is 257 bytes' "$d/.out" \
   && ! grep -qF Traceback "$d/.out"; then
  pass "15 no-arg mode scans every tracked *.tf from the repo top level"
else
  fail "15 no-arg mode — rc=$r15_rc out=$(head -3 "$d/.out" 2>/dev/null | tr '\n' '|')"
fi
cases=$((cases + 1))
if [[ "$(git -C "$decoy" ls-files | wc -l)" == "$decoy_before" ]]; then
  pass "15 hygiene: an inherited GIT_DIR/GIT_INDEX_FILE is not written to"
else
  fail "15 hygiene: the decoy index gained entries — the GIT_* scrub is not effective"
fi

# 16 — every finding is printed, never only the first.
d=$(fx r16); assert_fixture_dir "$d"; dp doppler_project one "$(lit "$(x 256)")" > "$d/a.tf"; dp doppler_project two "$(lit "$(x 300)")" > "$d/b.tf"
cases=$((cases + 1)); row "16 two findings: the first" 1 "a.tf:3: doppler_project.one description is 256 bytes" "$d/a.tf" "$d/b.tf"
cases=$((cases + 1)); row "16 two findings: the second" 1 "b.tf:3: doppler_project.two description is 300 bytes" "$d/a.tf" "$d/b.tf"

# H1 — non-doppler descriptions are out of scope, however long.
d=$(fx h1); assert_fixture_dir "$d"
{ printf 'variable "x" {\n  description = %s\n}\n\n' "$(lit "$(x 600)")"
  printf 'resource "github_repository_environment" "e" {\n  description = %s\n}\n\n' "$(lit "$(x 400)")"
  dp doppler_project p "$(lit ok)"; } > "$d/a.tf"
cases=$((cases + 1)); row "H1 non-doppler descriptions ignored" 0 "1 description(s) measured" "$d/a.tf"

# H2 — a commented-out description is not a description.
d=$(fx h2); assert_fixture_dir "$d"; printf 'resource "doppler_project" "p" {\n  # description = %s\n  description = "ok"\n}\n' "$(lit "$(x 300)")" > "$d/a.tf"
cases=$((cases + 1)); row "H2 commented-out description ignored" 0 "1 description(s) measured" "$d/a.tf"

# H3 — a description key inside an object expression or a nested block is not the
# resource's description (must-PASS: the lint must not reject more than the property).
d=$(fx h3); assert_fixture_dir "$d"
printf 'resource "doppler_project" "p" {\n  tags = { description = %s }\n  lifecycle {\n    description = %s\n  }\n  description = "ok"\n}\n' "$(lit "$(x 300)")" "$(lit "$(x 300)")" > "$d/a.tf"
cases=$((cases + 1)); row "H3 object-key and nested-block descriptions ignored" 0 "1 description(s) measured" "$d/a.tf"

# H4 — a header with a trailing comment is still a header (must-PASS).
d=$(fx h4); assert_fixture_dir "$d"; printf 'resource "doppler_project" "p" { # note\n  description = "ok"\n}\n' > "$d/a.tf"
cases=$((cases + 1)); row "H4 header with a trailing comment" 0 "1 description(s) measured" "$d/a.tf"

# H5 — a heredoc body is text, never structure: its column-0 `}`, `KEY=value` and
# fake header must not move the description after it out of its block.
d=$(fx h5); assert_fixture_dir "$d"
printf 'resource "doppler_project" "p" {\n  name = %sEOT\n}\nFOO=bar\nresource "x" "y" {\nEOT\n  description = %s\n}\n' "$hd" "$(lit "$(x 256)")" > "$d/a.tf"
cases=$((cases + 1)); row "H5 heredoc body is not structure" 1 "a.tf:7: doppler_project.p description is 256 bytes" "$d/a.tf"
d=$(fx h5i); assert_fixture_dir "$d"
printf 'resource "doppler_project" "p" {\n  name = %s-EOT\n    }\nresource "x" "y" {\n    EOT\n  description = %s\n}\n' "$hd" "$(lit "$(x 256)")" > "$d/a.tf"
cases=$((cases + 1)); row "H5 indented heredoc (dash form) closer" 1 "a.tf:6: doppler_project.p description is 256 bytes" "$d/a.tf"
d=$(fx h5b); assert_fixture_dir "$d"
printf '/*\n}\nFOO=bar\n*/\nresource "doppler_project" "p" {\n  description = "ok"\n}\n' > "$d/a.tf"
cases=$((cases + 1)); row "H5b block-comment body is not structure" 0 "1 description(s) measured" "$d/a.tf"

# H6 — control characters in a name are stripped before printing.
d=$(fx h6); assert_fixture_dir "$d"; printf 'resource "doppler_project" "p\x1b[31m" {\n  description = %s\n}\n' "$(lit "$(x 256)")" > "$d/a.tf"
cases=$((cases + 1)); row "H6 control characters stripped from names" 1 "a.tf:2: doppler_project.p[31m description is 256 bytes" "$d/a.tf"
d=$(fx h6b); assert_fixture_dir "$d"; printf 'resource "doppler_project" "p\xe2\x80\xa8\xc2\x9bq" {\n  description = %s\n}\n' "$(lit "$(x 256)")" > "$d/a.tf"
cases=$((cases + 1)); row "H6 U+2028 and C1 stripped from names" 1 "a.tf:2: doppler_project.pq description is 256 bytes" "$d/a.tf"

# H7 — a column-0 comment inside a doppler block is skipped.
d=$(fx h7); assert_fixture_dir "$d"; printf 'resource "doppler_project" "p" {\n  name = "n"\n# note at column 0\n  description = %s\n}\n' "$(lit "$(x 256)")" > "$d/a.tf"
cases=$((cases + 1)); row "H7 column-0 comment inside a doppler block" 1 "a.tf:4: doppler_project.p description is 256 bytes" "$d/a.tf"

# H8 — any indentation is a description.
d=$(fx h8); assert_fixture_dir "$d"; printf 'resource "doppler_project" "p" {\n    description = %s\n}\n' "$(lit "$(x 256)")" > "$d/a.tf"
cases=$((cases + 1)); row "H8 deeper-indented description is measured" 1 "a.tf:2: doppler_project.p description is 256 bytes" "$d/a.tf"

# N — layouts that defeated the line-based version. Each over-cap block follows a
# compliant one, so the vacuity check cannot be what catches it.
nfx() { # <row> <body-of-second-block-file> -> fixture dir with ok.tf + bad.tf
  local d; d=$(fx "$1"); assert_fixture_dir "$d"
  dp doppler_project good "$(lit ok)" > "$d/ok.tf"
  printf '%s' "$2" > "$d/bad.tf"
  printf '%s\n' "$d"
}
d=$(nfx n1 "$(printf 'resource "doppler_project" "a" {\n  name = "n %sEOT"\n}\n\nresource "doppler_project" "b" {\n  description = %s\n}\n' "$hd" "$(lit "$(x 256)")")")
cases=$((cases + 1)); row "N1 a heredoc opener inside a string is text" 1 "bad.tf:6: doppler_project.b description is 256 bytes" "$d/ok.tf" "$d/bad.tf"
d=$(nfx n2 "$(printf 'resource "doppler_project" "a" {\n  name = "n" # see %sEOT\n}\n\nresource "doppler_project" "b" {\n  description = %s\n}\n' "$hd" "$(lit "$(x 256)")")")
cases=$((cases + 1)); row "N2 a heredoc opener inside a comment is text" 1 "bad.tf:6: doppler_project.b description is 256 bytes" "$d/ok.tf" "$d/bad.tf"
d=$(nfx n3 "$(printf 'resource "doppler_project" "b" {\n  /* c */ description = %s\n}\n' "$(lit "$(x 256)")")")
cases=$((cases + 1)); row "N3 inline block comment before the description" 1 "bad.tf:2: doppler_project.b description is 256 bytes" "$d/ok.tf" "$d/bad.tf"
d=$(nfx n4 "$(printf 'resource "doppler_project" "b" {\n  /* a\n  */ description = %s\n}\n' "$(lit "$(x 256)")")")
cases=$((cases + 1)); row "N4 description after a multi-line comment closes" 1 "bad.tf:3: doppler_project.b description is 256 bytes" "$d/ok.tf" "$d/bad.tf"
d=$(nfx n5 "$(printf 'resource "doppler_project" "b" {\n  name = "n" /*\nresource "x" "y" {\n  */\n  description = %s\n}\n' "$(lit "$(x 256)")")")
cases=$((cases + 1)); row "N5 block comment opened mid-line" 1 "bad.tf:5: doppler_project.b description is 256 bytes" "$d/ok.tf" "$d/bad.tf"
d=$(nfx n6 "$(printf 'resource doppler_project b {\n  description = %s\n}\n' "$(lit "$(x 256)")")")
cases=$((cases + 1)); row "N6 unquoted block labels" 1 "bad.tf:2: doppler_project.b description is 256 bytes" "$d/ok.tf" "$d/bad.tf"
d=$(nfx n7 "$(printf '\xef\xbb\xbfresource "doppler_project" "b" {\n  description = %s\n}\n' "$(lit "$(x 256)")")")
cases=$((cases + 1)); row "N7 UTF-8 BOM before the header" 1 "bad.tf:2: doppler_project.b description is 256 bytes" "$d/ok.tf" "$d/bad.tf"
d=$(nfx n8 "$(printf 'resource "doppler_project" "b" {\n  x = ["s",\n"t"]\n  description = %s\n}\n' "$(lit "$(x 256)")")")
cases=$((cases + 1)); row "N8 column-0 continuation line" 1 "bad.tf:4: doppler_project.b description is 256 bytes" "$d/ok.tf" "$d/bad.tf"
d=$(nfx n9 "$(printf 'resource "doppler_project" "b" {\n  description=%s\n}\n' "$(lit "$(x 256)")")")
cases=$((cases + 1)); row "N9 description= without spaces" 1 "bad.tf:2: doppler_project.b description is 256 bytes" "$d/ok.tf" "$d/bad.tf"
d=$(nfx n10 "$(printf 'resource "doppler_project" "b" {\n  name = %sEOT\n  body\n' "$hd")")
cases=$((cases + 1)); row "N10 unterminated heredoc fails closed" 1 "bad.tf:2: unterminated heredoc; cannot scan this file" "$d/ok.tf" "$d/bad.tf"
d=$(nfx n11 "$(printf 'resource "doppler_project" "b" {\n  /* never closed\n  description = %s\n}\n' "$(lit "$(x 256)")")")
cases=$((cases + 1)); row "N11 unterminated block comment fails closed" 1 "bad.tf:2: unterminated block comment; cannot scan this file" "$d/ok.tf" "$d/bad.tf"

# N12 — NFC expansion: 63 x U+1D160 is 252 source bytes and 756 decoded, and
# Terraform sends the NFC form. Raw bytes alone would pass it.
d=$(fx n12); assert_fixture_dir "$d"
python3 -c 'import sys; open(sys.argv[1], "w", encoding="utf-8").write("resource \"doppler_project\" \"p\" {\n  description = \"" + "\U0001D160" * 63 + "\"\n}\n")' "$d/a.tf" \
  || { echo "FATAL: NFC fixture write failed" >&2; exit 2; }
cases=$((cases + 1)); row "N12 NFC-expanding characters measured after normalisation" 1 "a.tf:2: doppler_project.p description is 756 bytes" "$d/a.tf"

# N13 — a *.tf.json declaring a doppler_* resource fails closed.
d=$(fx n13); assert_fixture_dir "$d"; dp doppler_project good "$(lit ok)" > "$d/ok.tf"
printf '{"resource":{"doppler_project":{"p":{"name":"n","description":"%s"}}}}\n' "$(x 300)" > "$d/x.tf.json"
cases=$((cases + 1)); row "N13 a doppler *.tf.json fails closed" 1 "x.tf.json: *.tf.json mentions doppler_*; JSON syntax is not measured" "$d/ok.tf" "$d/x.tf.json"

# N14 — a path carrying a runner log command cannot emit one; a path with a space
# keeps it (the control-character strip must not eat ordinary characters).
d=$(fx n14); assert_fixture_dir "$d"; dp doppler_project p "$(lit "$(x 256)")" > "$d/x##[error title=forged]y.tf"
cases=$((cases + 1)); row_absent "N14 no ##[ command reaches the log" 1 "##[" "$d/x##[error title=forged]y.tf"
d=$(fx "n15 a b"); assert_fixture_dir "$d"; dp doppler_project p "$(lit "$(x 256)")" > "$d/a.tf"
cases=$((cases + 1)); row "N15 a space in a path survives" 1 "n15 a b/a.tf:3: doppler_project.p description is 256 bytes" "$d/a.tf"

# N16 — the lint's own failure is exit 2 with ERROR:, never a finding's exit 1.
cases=$((cases + 1)); row "N16 unreadable input exits 2, not 1" 2 "ERROR: lint-doppler-description-length could not run" "$TMP_ROOT/does-not-exist.tf"

# N17 — the summary reports the maximum, not the last value, and the file count.
d=$(fx n17); assert_fixture_dir "$d"; { dp doppler_project a "$(lit "$(x 255)")"; dp doppler_project b "$(lit ok)"; } > "$d/a.tf"; dp doppler_project c "$(lit ok)" > "$d/b.tf"
cases=$((cases + 1)); row "N17 summary: max and file count" 0 "3 doppler_* resource(s) in 2 file(s); 3 description(s) measured, max 255/255 bytes" "$d/a.tf" "$d/b.tf"

# N18 — an unbalanced closing brace makes the whole file unscannable, not silently
# mis-attributed (every later block would otherwise be read at the wrong depth).
d=$(nfx n18 "$(printf '}\nresource "doppler_project" "b" {\n  description = %s\n}\n' "$(lit "$(x 256)")")")
cases=$((cases + 1)); row "N18 unbalanced closing brace fails closed" 1 "bad.tf:1: unbalanced '}'; cannot scan this file" "$d/ok.tf" "$d/bad.tf"

# N19 — the token contract another guard consumes (#8705): apps/web-platform/infra/
# web-probes-token-rotation.test.sh loads tokenize() and matches references inside HEREDOC bodies
# and across `ID . ID`. A change here that drops the body, or re-tokenizes `a.b`, blinds that guard
# while this lint stays green.
d=$(fx n19); assert_fixture_dir "$d"
printf 'x = <<-EOT\n  ${a.b.key}\nEOT\ny = a.b\n' > "$d/h.tf"
n19="$(python3 - "$SUT" "$d/h.tf" 2>&1 <<'PY2'
import importlib.util
import sys

spec = importlib.util.spec_from_file_location("ldl", sys.argv[1])
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
toks = mod.tokenize(open(sys.argv[2], encoding="utf-8").read())
here = [t for t in toks if t[0] == "HEREDOC"]
print("HEREDOC_BODY_OK" if len(here) == 1 and "${a.b.key}" in here[0][1] else f"HEREDOC_BAD {here!r}")
kinds = [t[:2] for t in toks if t[0] != "NL"]
print("DOT_OK" if (("ID", "a"), ("OTHER", "."), ("ID", "b")) == tuple(kinds[-3:]) else f"DOT_BAD {kinds[-3:]!r}")
PY2
)" || true
cases=$((cases + 1))
if [[ "$n19" == *HEREDOC_BODY_OK* ]]; then pass "N19a a HEREDOC token carries its body in the value slot"; else fail "N19a HEREDOC body contract: $n19"; fi
cases=$((cases + 1))
if [[ "$n19" == *DOT_OK* ]]; then pass "N19b a.b tokenizes as ID, OTHER '.', ID"; else fail "N19b a.b token contract: $n19"; fi

if [[ $((PASS + FAIL)) -ne "$cases" ]]; then
  printf 'FATAL: conservation — PASS+FAIL=%d but %d rows ran\n' "$((PASS + FAIL))" "$cases" >&2
  exit 1
fi
MIN_CASES=63
if (( cases < MIN_CASES )); then
  printf '[FATAL] assertion floor: only %d assertions ran (floor %d)\n' "$cases" "$MIN_CASES" >&2
  exit 1
fi

echo "$PASS passed, $FAIL failed ($cases rows)"
[[ "$FAIL" -eq 0 ]] || exit 1
