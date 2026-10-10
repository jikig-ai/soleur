#!/usr/bin/env bash
#
# Guard 1 (#9879): the inngest LUKS store is the SOLE COPY of the queue and run state, and the
# Terraform that protects it must stay pinned. This suite reads the EFFECTIVE (comment-stripped)
# Terraform text of the main root and asserts, as whole code lines inside the right block:
#
#   hcloud_volume.inngest_redis_luks           delete_protection = true (direct attribute) and
#                                               lifecycle { prevent_destroy = true }; no ignore_changes
#   random_password.inngest_redis_luks          lifecycle { prevent_destroy = true }; no ignore_changes
#   doppler_secret.inngest_redis_luks_key       lifecycle { prevent_destroy = true }; no ignore_changes
#   doppler_project.inngest                     lifecycle { prevent_destroy = true }  (cascade parent)
#   doppler_environment.inngest_prd             lifecycle { prevent_destroy = true }  (cascade parent)
#   hcloud_volume_attachment.inngest_redis_luks NO lifecycle block and no prevent_destroy (a pin there
#                                               breaks the sanctioned inngest-host-replace)
#   the root directory                          no *override.tf, no *.tf.json
#   every top-level *.tf                        exactly one writer of INNGEST_REDIS_LUKS_KEY on
#                                               soleur-inngest/prd
#
# Three scans on purpose: block text, directory listing, cross-file census. All reads go through ONE
# chokepoint, the shared lexer tests/scripts/lib/hcl-effective-text.sh (also sourced by
# workspaces-luks.test.sh), which strips `#`, `//` and multi-line comments and keeps line numbers.
# The lexer keeps trailing comments, so every predicate is anchored to a WHOLE code line
# (`^\s*prevent_destroy\s*=\s*true\s*(#.*)?$`) and evaluated only inside the right block.
#
# THE MUTATION MATRIX (every row runs on a scratch COPY of the root under /var/tmp; the real files
# are never edited; each mutation is asserted to have LANDED, to be confined to the block it targets,
# and to turn the verdict RED for the NAMED reason, after an unmutated control went GREEN first):
#   R1  delete_protection flipped to false            R7  prevent_destroy removed from the SECOND pair member
#   R2  volume prevent_destroy line deleted           R8  prevent_destroy removed from a Doppler parent
#   R3  volume lifecycle wrapped in a multi-line /* */ R9  lifecycle / prevent_destroy ADDED to the attachment
#   R4  volume prevent_destroy = false                R10 planted *override.tf / *.tf.json
#   R5  ignore_changes on the volume or either member R11 a second writer of INNGEST_REDIS_LUKS_KEY
#   R6  prevent_destroy moved into a non-lifecycle block  R12 extractor returns empty (renamed resource)
# Harness rows: the lexer neutered to the identity function, and block extraction neutered to empty,
# must each redden THIS suite (run on a scratch tree that sources a neutered copy of the lexer).
# Must-PASS rows: cosmetic rewrites (spacing, trailing comment), an attachment whose comments
# mention prevent_destroy / a lifecycle block, the rehearsal sub-root's scratch secret of the same
# NAME (a different directory, never scanned), and the same NAME on a different Doppler project.
#
# ANCHOR (stated, not hidden): these pins and this guard land in one diff, so one diff can weaken
# both. The independent anchors are the census rows (G4h / G4_PROTECTED) in
# tests/scripts/test-infra-privileged-tier-census.sh, the merge-base diff that census computes, and
# the post-merge read of live Hetzner state.
#
# Every failure names the runbook section "Sole-copy protection and key loss" in
# knowledge-base/engineering/operations/runbooks/inngest-luks-cutover-6894.md: lifting a protection
# deliberately is a reviewed two-step change (delete protection first, then prevent_destroy).
#
# Run: bash apps/web-platform/infra/inngest-luks-sole-copy.test.sh
# Presence under apps/web-platform/infra/ IS registration (derived by run-registered-suites.sh).
#
# `set -e` is deliberately ABSENT: deliberately-nonzero greps are wrapped so the harness never
# aborts mid-suite.
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# The shared lexer is resolved from the REPO ROOT, never from this suite's own directory.
REPO_ROOT="$(cd "$DIR/../../.." && pwd)"
HCL_LIB="$REPO_ROOT/tests/scripts/lib/hcl-effective-text.sh"
[ -f "$HCL_LIB" ] || { printf 'FATAL: shared HCL lexer not found at %s\n' "$HCL_LIB" >&2; exit 2; }
# shellcheck source=../../../tests/scripts/lib/hcl-effective-text.sh
. "$HCL_LIB" || { printf 'FATAL: could not source %s\n' "$HCL_LIB" >&2; exit 2; }

RUNBOOK_REL="knowledge-base/engineering/operations/runbooks/inngest-luks-cutover-6894.md"
RUNBOOK_SECTION="Sole-copy protection and key loss"
LUKS_TF="inngest-redis-luks.tf"
HOST_TF="inngest-host.tf"
EXPECTED_CHECKS=18

# Counters. `cases` is the INDEPENDENT case counter, incremented at every assert call site and never
# inside pass()/fail(), so a neutered verdict helper cannot also neuter the accounting that notices it.
passes=0
fails=0
cases=0
pass() { passes=$((passes + 1)); }
fail() { fails=$((fails + 1)); printf 'FAIL: %s\n' "$1" >&2; }

# Reporter self-test: one pass() adds exactly one pass and no fail, one fail() exactly one fail and
# no pass. Runs in a SUBSHELL so the real counters are untouched, and reports through printf + exit
# 2, never through fail(), the very function under suspicion.
suite_selftest() {
  local got
  got="$( passes=0; fails=0; pass selftest-pass; fail selftest-fail 2>/dev/null; printf '%s/%s' "$passes" "$fails" )"
  if [ "$got" != "1/1" ]; then
    printf 'INSTRUMENT FAIL - inngest-luks-sole-copy.test.sh: pass()/fail() self-test got passes/fails=%s, want 1/1; every verdict below would be meaningless\n' "$got" >&2
    exit 2
  fi
}
suite_selftest

# Canonical fixture-path guard (fixture-relative-assert P1b; byte-identical to every tracked copy).
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

# ONE owning trap for every scratch tree below. Scratch copies live under /var/tmp, never beside the
# real files.
SUITE_TMP="$(mktemp -d /var/tmp/inngest-sole-copy-suite.XXXXXX)" || { printf 'FATAL: mktemp -d failed\n' >&2; exit 2; }
assert_fixture_dir "$SUITE_TMP"
trap 'rm -rf "$SUITE_TMP"' EXIT

# Pristine snapshot of the root's top-level *.tf (Terraform reads the top level only). Every row
# mutates a COPY of this; the real tree is only ever read.
PRISTINE="$SUITE_TMP/pristine"
mkdir "$PRISTINE" || { printf 'FATAL: mkdir %s failed\n' "$PRISTINE" >&2; exit 2; }
assert_fixture_dir "$PRISTINE"
cp "$DIR"/*.tf "$PRISTINE"/ || { printf 'FATAL: could not snapshot %s/*.tf\n' "$DIR" >&2; exit 2; }
[ -f "$PRISTINE/$LUKS_TF" ] && [ -f "$PRISTINE/$HOST_TF" ] || { printf 'FATAL: %s or %s missing from %s\n' "$LUKS_TF" "$HOST_TF" "$DIR" >&2; exit 2; }

# --- Block scanners -------------------------------------------------------------

# stdin: one resource block (comment-stripped). `direct` prints the lines at brace depth 1 (the
# block's own attributes and nested-block openers); `lifecycle` prints the depth-2 lines of a
# `lifecycle {` block that is a DIRECT child of the resource. A line that merely sits inside some
# other nested block (labels, a provisioner) is in neither, which is what makes "moved into a
# non-lifecycle block" visible.
blk_scan() {
  awk -v mode="$1" '
    function code(s) { gsub(/"([^"\\]|\\.)*"/, "\"\"", s); sub(/[[:space:]]*(#|\/\/).*$/, "", s); return s }
    {
      c = code($0); o = gsub(/\{/, "{", c); x = gsub(/\}/, "}", c)
      before = d; d += o - x
      if (mode == "direct") { if (before == 1 && d >= 1) print; next }
      if (before == 1 && d == 2 && $0 ~ /^[[:space:]]*lifecycle[[:space:]]*\{[[:space:]]*((#|\/\/).*)?$/) { inlc = 1; next }
      if (inlc) {
        if (before == 2 && d == 1) { inlc = 0; next }
        if (before == 2) print
      }
    }'
}

# Code with trailing comments removed, for NEGATIVE checks (a comment must never trip a refusal).
code_only() { sed -E 's/[[:space:]]+(#|\/\/).*$//'; }

# `<attr> = true` as a whole code line: exactly ONE assignment line in the text and it is `true`
# (spacing and a trailing comment tolerated, anything else is not).
attr_true_in() { # <text> <attr> -> 1|0
  local text="$1" attr="$2" n
  n="$(grep -Ec "^[[:space:]]*${attr}[[:space:]]*=" <<<"$text")"
  [ "$n" = "1" ] || { echo 0; return; }
  if grep -Eq "^[[:space:]]*${attr}[[:space:]]*=[[:space:]]*true${B4_TAIL}" <<<"$text"; then echo 1; else echo 0; fi
}

p_delete_protection() { # <block> : direct attribute, exactly one, true
  [ -n "$1" ] || { echo 0; return; }
  attr_true_in "$(blk_scan direct <<<"$1")" delete_protection
}

p_prevent_destroy() { # <block> : inside a direct lifecycle block, exactly one, true, and one in the block overall
  local total
  [ -n "$1" ] || { echo 0; return; }
  total="$(code_only <<<"$1" | grep -Ec '(^|[^A-Za-z_])prevent_destroy[[:space:]]*=')"
  [ "$total" = "1" ] || { echo 0; return; }
  attr_true_in "$(blk_scan lifecycle <<<"$1")" prevent_destroy
}

p_no_ignore_changes() { # <block> : the key-drift detector depends on there being none
  [ -n "$1" ] || { echo 0; return; }
  if code_only <<<"$1" | grep -Eq '(^|[^A-Za-z_])ignore_changes[[:space:]]*='; then echo 0; else echo 1; fi
}

p_attachment_unpinned() { # <block> : NO lifecycle block and no prevent_destroy assignment, comments excluded
  local c
  [ -n "$1" ] || { echo 0; return; }
  c="$(code_only <<<"$1")"
  if grep -Eq '(^|[^A-Za-z_])(lifecycle[[:space:]]*\{|prevent_destroy[[:space:]]*=)' <<<"$c"; then echo 0; else echo 1; fi
}

# Resource block of one address across the root's top-level *.tf. TB_COUNT = number of declarations
# found (exactly one is required); TB_BLOCK = their comment-stripped text. ONE raw grep per tree
# (CAND_FILES, set by evaluate_tree) picks the candidate files for all six addresses; a header hidden in
# a comment is still resolved by block_of itself. A header the raw grep cannot see is not a header
# block_of can see either (both anchor on column 0).
tree_block() { # <dir> <type> <name>
  local dir="$1" type="$2" name="$3" f b n
  TB_COUNT=0; TB_BLOCK=""
  for f in $CAND_FILES; do
    grep -Eq "^resource[[:space:]]+\"${type}\"[[:space:]]+\"${name}\"" "$f" || continue
    b="$(block_of "$f" "$type" "$name")"
    [ -n "$b" ] || continue
    n="$(grep -Ec "^resource[[:space:]]+\"${type}\"[[:space:]]+\"${name}\"" <<<"$b")"
    TB_COUNT=$((TB_COUNT + n))
    TB_BLOCK="${TB_BLOCK}${b}"$'\n'
  done
}

# Writers of INNGEST_REDIS_LUKS_KEY on soleur-inngest/prd across the root's top-level *.tf: every
# doppler_secret named so, except one PROVABLY on another project or config by a string literal. A
# project or config that is a reference or a local counts as a writer.
count_key_writers() { # <dir> -> number
  local dir="$1" f total=0 n files
  files="$(grep -l 'INNGEST_REDIS_LUKS_KEY' "$dir"/*.tf 2>/dev/null)"
  for f in $files; do
    [ -f "$f" ] || continue
    n="$(strip_comments "$f" | awk '
      function code(s) { sub(/[[:space:]]*(#|\/\/).*$/, "", s); sub(/[[:space:]]+$/, "", s); return s }
      function val(s, key,   r) { r = s; if (sub("^[[:space:]]*" key "[[:space:]]*=[[:space:]]*", "", r)) return code(r); return "" }
      /^resource[[:space:]]+"doppler_secret"/ { inb = 1; d = 0; nm = ""; pj = ""; cf = "" }
      inb {
        c = code($0); before = d
        d += gsub(/\{/, "{", c) - gsub(/\}/, "}", c)
        if (before == 1) {
          v = val($0, "name");    if (v != "") nm = v
          v = val($0, "project"); if (v != "") pj = v
          v = val($0, "config");  if (v != "") cf = v
        }
        if (d <= 0 && /\}/) {
          if (nm == "\"INNGEST_REDIS_LUKS_KEY\"") {
            elsewhere = (pj ~ /^"/ && pj != "\"soleur-inngest\"") || (cf ~ /^"/ && cf != "\"prd\"")
            if (!elsewhere) w++
          }
          inb = 0
        }
      }
      END { print w + 0 }')"
    total=$((total + n))
  done
  echo "$total"
}

# --- The evaluator ----------------------------------------------------------------

# Runs EVERY check against one root directory. Fills VIOLS (violation codes) and CHECKED (how many
# predicates were evaluated). "Green" means no violation AND all EXPECTED_CHECKS predicates ran, so an
# extractor that returns nothing can never read as "0 checked, exit 0".
VIOLS=(); CHECKED=0
check() { # <code> <1|0>
  CHECKED=$((CHECKED + 1))
  [ "$2" = "1" ] || VIOLS+=("$1")
}
extract() { # <type> <name> <outvar>
  tree_block "$TREE" "$1" "$2"
  CHECKED=$((CHECKED + 1))
  if [ "$TB_COUNT" != "1" ]; then
    VIOLS+=("EXTRACT:$1.$2")
    printf -v "$3" '%s' ""
  else
    printf -v "$3" '%s' "$TB_BLOCK"
  fi
}
evaluate_tree() { # <dir>
  local B_VOL B_ATT B_PW B_SEC B_PROJ B_ENV
  TREE="$1"; VIOLS=(); CHECKED=0
  CAND_FILES="$(grep -lE '^resource[[:space:]]+"[a-z_]+"[[:space:]]+"(inngest_redis_luks|inngest_redis_luks_key|inngest|inngest_prd)"' "$TREE"/*.tf 2>/dev/null)"
  extract hcloud_volume inngest_redis_luks B_VOL
  extract hcloud_volume_attachment inngest_redis_luks B_ATT
  extract random_password inngest_redis_luks B_PW
  extract doppler_secret inngest_redis_luks_key B_SEC
  extract doppler_project inngest B_PROJ
  extract doppler_environment inngest_prd B_ENV
  check VOL_DELETE_PROTECTION "$(p_delete_protection "$B_VOL")"
  check VOL_PREVENT_DESTROY "$(p_prevent_destroy "$B_VOL")"
  check VOL_IGNORE_CHANGES "$(p_no_ignore_changes "$B_VOL")"
  check PW_PREVENT_DESTROY "$(p_prevent_destroy "$B_PW")"
  check PW_IGNORE_CHANGES "$(p_no_ignore_changes "$B_PW")"
  check SEC_PREVENT_DESTROY "$(p_prevent_destroy "$B_SEC")"
  check SEC_IGNORE_CHANGES "$(p_no_ignore_changes "$B_SEC")"
  check PROJ_PREVENT_DESTROY "$(p_prevent_destroy "$B_PROJ")"
  check ENV_PREVENT_DESTROY "$(p_prevent_destroy "$B_ENV")"
  check ATT_PINNED "$(p_attachment_unpinned "$B_ATT")"
  check OVERRIDE_FILES "$(p_b4_no_override_files "$TREE")"
  if [ "$(count_key_writers "$TREE")" = "1" ]; then check KEY_WRITER_COUNT 1; else check KEY_WRITER_COUNT 0; fi
  if [ "$CHECKED" -ne "$EXPECTED_CHECKS" ]; then
    printf 'INSTRUMENT FAIL - evaluator ran %s checks, expected %s (a predicate was skipped)\n' "$CHECKED" "$EXPECTED_CHECKS" >&2
    exit 2
  fi
  [ "${#VIOLS[@]}" -eq 0 ]
}

viol_text() { # <code> -> what is wrong
  case "$1" in
    EXTRACT:*)            echo "the block for ${1#EXTRACT:} was not found exactly once (renamed, wrapped in a comment, duplicated, or moved out of the root)" ;;
    VOL_DELETE_PROTECTION) echo "hcloud_volume.inngest_redis_luks does not carry delete_protection = true as one code line" ;;
    VOL_PREVENT_DESTROY)  echo "hcloud_volume.inngest_redis_luks does not carry prevent_destroy = true inside a lifecycle block" ;;
    VOL_IGNORE_CHANGES)   echo "hcloud_volume.inngest_redis_luks has an ignore_changes (it would hide a lifted delete protection)" ;;
    PW_PREVENT_DESTROY)   echo "random_password.inngest_redis_luks does not carry prevent_destroy = true inside a lifecycle block" ;;
    PW_IGNORE_CHANGES)    echo "random_password.inngest_redis_luks has an ignore_changes (the key-drift detector depends on there being none)" ;;
    SEC_PREVENT_DESTROY)  echo "doppler_secret.inngest_redis_luks_key does not carry prevent_destroy = true inside a lifecycle block" ;;
    SEC_IGNORE_CHANGES)   echo "doppler_secret.inngest_redis_luks_key has an ignore_changes (the key-drift detector depends on there being none)" ;;
    PROJ_PREVENT_DESTROY) echo "doppler_project.inngest does not carry prevent_destroy = true inside a lifecycle block (it cascade-deletes the key)" ;;
    ENV_PREVENT_DESTROY)  echo "doppler_environment.inngest_prd does not carry prevent_destroy = true inside a lifecycle block (it cascade-deletes the key)" ;;
    ATT_PINNED)           echo "hcloud_volume_attachment.inngest_redis_luks carries a lifecycle block or prevent_destroy (it would break the sanctioned inngest-host-replace)" ;;
    OVERRIDE_FILES)       echo "the root holds an *override.tf or *.tf.json that can override a protection behind the HCL this suite reads" ;;
    KEY_WRITER_COUNT)     echo "INNGEST_REDIS_LUKS_KEY on soleur-inngest/prd does not have exactly one writer" ;;
    *)                    echo "unknown violation code" ;;
  esac
}

# What every failure tells the reader to do.
runbook_pointer() {
  printf 'Lifting a protection deliberately is a reviewed two-step change (delete protection first, then prevent_destroy): see the runbook section "%s" in %s.' "$RUNBOOK_SECTION" "$RUNBOOK_REL"
}
report_viols() {
  local v
  for v in "${VIOLS[@]}"; do printf '  - [%s] %s\n' "$v" "$(viol_text "$v")" >&2; done
  printf '  %s\n' "$(runbook_pointer)" >&2
}
has_viol() { case " ${VIOLS[*]:-} " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }

# --- Scratch trees and mutation plumbing --------------------------------------------

drop_tree() { assert_fixture_dir "$1"; rm -rf "$1"; }
new_tree() { # -> prints a fresh scratch root holding a copy of the pristine *.tf
  local d
  d="$(mktemp -d "$SUITE_TMP/row.XXXXXX")" || { printf 'FATAL: mktemp -d failed\n' >&2; exit 2; }
  assert_fixture_dir "$d"
  cp "$PRISTINE"/*.tf "$d"/ || { printf 'FATAL: could not copy the pristine tree\n' >&2; exit 2; }
  printf '%s' "$d"
}

# Every changed line of the mutated file must sit INSIDE the targeted resource block of the pristine
# file (a pure insertion counts when it lands between the block's first and last line).
confined() { # <pristine-file> <mutated-file> <type> <name>
  local range s e hunks
  range="$(_b4_block_range "$1" "$3" "$4")"
  [ -n "$range" ] || return 1
  s="${range% *}"; e="${range#* }"
  # diff exits 1 when the files differ, which is the expected case: capture, never pipe it.
  hunks="$(diff -U0 "$1" "$2")"
  awk -v s="$s" -v e="$e" '
    /^@@/ {
      split($2, a, ","); st = substr(a[1], 2) + 0; ln = (a[2] == "" ? 1 : a[2] + 0)
      if (ln == 0) { if (st < s || st >= e) bad = 1 } else if (st < s || st + ln - 1 > e) bad = 1
    }
    END { exit bad ? 1 : 0 }' <<<"$hunks"
}

# Apply an in-block sed (-E) to <file> of a fresh tree; sets MUT_TREE. Returns 1 (and says why) when
# the mutation did not land or strayed outside the block, so a vacuous row is a FAIL, never a pass.
MUT_TREE=""
apply_block_sed() { # <name> <file> <type> <resname> <inner-sed>
  local name="$1" file="$2" type="$3" rname="$4" inner="$5" tree
  tree="$(new_tree)"
  assert_fixture_dir "$tree"
  MUT_TREE="$tree"
  sed -E "/^resource \"${type}\" \"${rname}\" \{/,/^\}/ { ${inner} }" "$PRISTINE/$file" > "$tree/$file" \
    || { fail "$name: sed failed"; return 1; }
  if cmp -s "$PRISTINE/$file" "$tree/$file"; then fail "$name: the mutation changed nothing (vacuous row)"; return 1; fi
  if ! confined "$PRISTINE/$file" "$tree/$file" "$type" "$rname"; then
    fail "$name: the mutation was not confined to resource \"$type\" \"$rname\""; return 1
  fi
  return 0
}

# --- Assert wrappers (cases++ AT THE CALL SITE) -------------------------------------

# The unmutated tree, or a must-PASS variant: no violation at all.
assert_green_tree() { # <name> <tree>
  cases=$((cases + 1))
  if evaluate_tree "$2"; then
    pass
  else
    fail "$1: expected GREEN but the guard reported:"; report_viols
  fi
}
# A mutated tree: RED, and for the NAMED reason (a RED from a broken sed is not evidence).
assert_red_tree() { # <name> <expected-code> <tree>
  cases=$((cases + 1))
  if evaluate_tree "$3"; then
    fail "$1: MUTATION was not caught (the guard stayed GREEN on a weakened tree)"
  elif has_viol "$2"; then
    pass
  else
    fail "$1: RED, but not for the expected reason [$2]; got: ${VIOLS[*]}"
  fi
}
assert_mut_red() { # <name> <expected-code> <file> <type> <resname> <inner-sed>
  local name="$1" code="$2"
  if ! apply_block_sed "$name" "$3" "$4" "$5" "$6"; then cases=$((cases + 1)); return; fi
  assert_red_tree "$name" "$code" "$MUT_TREE"
  drop_tree "$MUT_TREE"
}
assert_mut_green() { # <name> <file> <type> <resname> <inner-sed>
  local name="$1"
  if ! apply_block_sed "$name" "$2" "$3" "$4" "$5"; then cases=$((cases + 1)); return; fi
  assert_green_tree "$name" "$MUT_TREE"
  drop_tree "$MUT_TREE"
}
# Planted file (a path relative to the root, directories created). The unplanted copy must be GREEN
# first, or the row is vacuous.
plant() { # <tree> <relpath> <content>
  mkdir -p "$(dirname "$1/$2")" && printf '%s\n' "$3" > "$1/$2"
}
assert_plant_red() { # <name> <expected-code> <relpath> <content>
  local tree
  tree="$(new_tree)"
  if ! evaluate_tree "$tree"; then cases=$((cases + 1)); fail "$1: the unplanted copy already fails (vacuous row)"; report_viols; drop_tree "$tree"; return; fi
  plant "$tree" "$3" "$4"
  assert_red_tree "$1" "$2" "$tree"
  drop_tree "$tree"
}
assert_plant_green() { # <name> <relpath> <content>
  local tree
  tree="$(new_tree)"
  plant "$tree" "$2" "$3"
  assert_green_tree "$1" "$tree"
  drop_tree "$tree"
}

# --- Harness rows ---------------------------------------------------------------------

# H0: the unmutated tree is GREEN (the control every RED row is measured against), and the real
# tree, read in place, agrees with its snapshot.
assert_green_tree "H0 control: the unmutated root holds every pin" "$PRISTINE"
assert_green_tree "H0 the real root, read in place, holds every pin" "$DIR"

# H1: a failure message names the runbook section. Drive one RED tree and read the report text.
cases=$((cases + 1))
h1_tree=""
if apply_block_sed "H1 message row (setup)" "$LUKS_TF" hcloud_volume inngest_redis_luks 's/^([[:space:]]+delete_protection[[:space:]]*=[[:space:]]*)true/\1false/'; then
  h1_tree="$MUT_TREE"
  evaluate_tree "$h1_tree" >/dev/null 2>&1
  h1_msg="$(report_viols 2>&1)"
  if grep -Fq "$RUNBOOK_SECTION" <<<"$h1_msg" && grep -Fq "$RUNBOOK_REL" <<<"$h1_msg"; then
    pass
  else
    fail "H1: a RED report does not name the runbook section \"$RUNBOOK_SECTION\" in $RUNBOOK_REL"
  fi
fi
[ -z "$h1_tree" ] || drop_tree "$h1_tree"

# --- Mutation matrix (every row is RED for the named reason) ----------------------------

VOL_T=hcloud_volume; VOL_N=inngest_redis_luks
# R1
assert_mut_red "R1 delete_protection flipped to false" VOL_DELETE_PROTECTION "$LUKS_TF" $VOL_T $VOL_N \
  's/^([[:space:]]+delete_protection[[:space:]]*=[[:space:]]*)true/\1false/'
# R2 (the line is blanked, so line numbers stay stable)
assert_mut_red "R2 volume prevent_destroy line deleted" VOL_PREVENT_DESTROY "$LUKS_TF" $VOL_T $VOL_N \
  's/^[[:space:]]+prevent_destroy[[:space:]]*=.*$//'
# R3 the whole lifecycle block wrapped in a MULTI-LINE block comment (the opener sits on the blank
# line above `lifecycle {`, the closer after its `}`; the lifecycle lines themselves stay ordinary
# lines, so ONLY a real comment lexer sees the block is gone)
R3_ML='{ /^$/ { N; /\n[[:space:]]+lifecycle[[:space:]]*\{$/ { N; N; s/^\n/  \/*\n/; s/\n([[:space:]]+\})$/\n\1 *\// } } }'
assert_mut_red "R3 volume lifecycle wrapped in a multi-line /* */" VOL_PREVENT_DESTROY "$LUKS_TF" $VOL_T $VOL_N "$R3_ML"
# Nested runs (the lexer-neutering harness rows below) need only the control and R3.
if [ -n "${SOLE_COPY_NESTED:-}" ]; then
  [ "$fails" -eq 0 ]
  exit
fi
# R4
assert_mut_red "R4 volume prevent_destroy = false" VOL_PREVENT_DESTROY "$LUKS_TF" $VOL_T $VOL_N \
  's/^([[:space:]]+prevent_destroy[[:space:]]*=[[:space:]]*)true/\1false/'
# R5 ignore_changes on the volume (list form and `= all`) and on either pair member
assert_mut_red "R5a ignore_changes = [delete_protection] on the volume" VOL_IGNORE_CHANGES "$LUKS_TF" $VOL_T $VOL_N \
  's/^([[:space:]]+prevent_destroy[[:space:]]*=[[:space:]]*true)$/\1\n    ignore_changes = [delete_protection]/'
assert_mut_red "R5b ignore_changes = all on the volume" VOL_IGNORE_CHANGES "$LUKS_TF" $VOL_T $VOL_N \
  's/^([[:space:]]+prevent_destroy[[:space:]]*=[[:space:]]*true)$/\1\n    ignore_changes = all/'
assert_mut_red "R5c ignore_changes = [value] on the doppler_secret" SEC_IGNORE_CHANGES "$LUKS_TF" doppler_secret inngest_redis_luks_key \
  's/^([[:space:]]+prevent_destroy[[:space:]]*=[[:space:]]*true)$/\1\n    ignore_changes = [value]/'
assert_mut_red "R5d ignore_changes = [result] on the random_password" PW_IGNORE_CHANGES "$LUKS_TF" random_password inngest_redis_luks \
  's/^([[:space:]]+prevent_destroy[[:space:]]*=[[:space:]]*true)$/\1\n    ignore_changes = [result]/'
# R6 prevent_destroy moved into a nested NON-lifecycle block (the labels map) and out of lifecycle
assert_mut_red "R6 prevent_destroy moved into a nested non-lifecycle block" VOL_PREVENT_DESTROY "$LUKS_TF" $VOL_T $VOL_N \
  's/^([[:space:]]+)(app[[:space:]]*=.*)$/\1\2\n\1prevent_destroy = true/;s/^[[:space:]]+prevent_destroy[[:space:]]*=[[:space:]]*true$//'
# R7 the pair: the first member (random_password) and the SECOND (doppler_secret, later in the file)
assert_mut_red "R7a prevent_destroy removed from the first pair member (random_password)" PW_PREVENT_DESTROY "$LUKS_TF" random_password inngest_redis_luks \
  's/^[[:space:]]+prevent_destroy[[:space:]]*=.*$//'
assert_mut_red "R7b prevent_destroy removed from the SECOND pair member (doppler_secret); first stays compliant" SEC_PREVENT_DESTROY "$LUKS_TF" doppler_secret inngest_redis_luks_key \
  's/^[[:space:]]+prevent_destroy[[:space:]]*=.*$//'
# R8 the Doppler parents (cascade delete of the key)
assert_mut_red "R8a prevent_destroy removed from doppler_environment.inngest_prd" ENV_PREVENT_DESTROY "$HOST_TF" doppler_environment inngest_prd \
  's/^[[:space:]]+prevent_destroy[[:space:]]*=.*$//'
assert_mut_red "R8b prevent_destroy removed from doppler_project.inngest" PROJ_PREVENT_DESTROY "$HOST_TF" doppler_project inngest \
  's/^[[:space:]]+prevent_destroy[[:space:]]*=.*$//'
# R9 the host-replace breaker: a pin ADDED to the attachment (and any lifecycle block at all)
assert_mut_red "R9a prevent_destroy = true ADDED to the attachment" ATT_PINNED "$LUKS_TF" hcloud_volume_attachment inngest_redis_luks \
  's/^([[:space:]]+server_id[[:space:]]*=.*)$/\1\n\n  lifecycle {\n    prevent_destroy = true\n  }/'
assert_mut_red "R9b a lifecycle block (create_before_destroy) ADDED to the attachment" ATT_PINNED "$LUKS_TF" hcloud_volume_attachment inngest_redis_luks \
  's/^([[:space:]]+server_id[[:space:]]*=.*)$/\1\n\n  lifecycle {\n    create_before_destroy = true\n  }/'
# R10 override files in the root
assert_plant_red "R10a planted zz_override.tf" OVERRIDE_FILES zz_override.tf '# planted by inngest-luks-sole-copy.test.sh'
assert_plant_red "R10b planted extra.tf.json" OVERRIDE_FILES extra.tf.json '{}'
# R11 a second writer of INNGEST_REDIS_LUKS_KEY on the prd config, in a sibling file
R11_BODY='resource "doppler_secret" "inngest_redis_luks_key_second" {
  project = doppler_project.inngest.name
  config  = doppler_environment.inngest_prd.slug
  name    = "INNGEST_REDIS_LUKS_KEY"
  value   = "synthetic-not-a-secret"
}'
assert_plant_red "R11a a second doppler_secret named INNGEST_REDIS_LUKS_KEY on soleur-inngest/prd (references)" KEY_WRITER_COUNT sibling_writer.tf "$R11_BODY"
R11B_BODY='resource "doppler_secret" "inngest_redis_luks_key_second" {
  project = local.not_resolvable_here
  config  = local.neither_is_this
  name    = "INNGEST_REDIS_LUKS_KEY"
  value   = "synthetic-not-a-secret"
}'
assert_plant_red "R11b a second writer whose project/config are locals (not provably elsewhere)" KEY_WRITER_COUNT sibling_writer.tf "$R11B_BODY"
# R12 the extractor returns empty for an address (renamed resource): zero attributes would be checked
assert_mut_red "R12a volume renamed: the extractor finds nothing" "EXTRACT:hcloud_volume.inngest_redis_luks" "$LUKS_TF" $VOL_T $VOL_N \
  's/^resource "hcloud_volume" "inngest_redis_luks"/resource "hcloud_volume" "gone"/'
assert_mut_red "R12b attachment renamed: the extractor finds nothing" "EXTRACT:hcloud_volume_attachment.inngest_redis_luks" "$LUKS_TF" hcloud_volume_attachment inngest_redis_luks \
  's/^resource "hcloud_volume_attachment" "inngest_redis_luks"/resource "hcloud_volume_attachment" "gone"/'

# --- Must-PASS rows (variants that differ from the canonical in a permitted way) -------

COSMETIC='s/^([[:space:]]+(prevent_destroy|delete_protection))[[:space:]]*=[[:space:]]*true.*$/\1   =   true   # note/'
assert_mut_green "P1a cosmetic rewrite (spacing + trailing comment) on the volume" "$LUKS_TF" $VOL_T $VOL_N "$COSMETIC"
assert_mut_green "P1b cosmetic rewrite on the random_password" "$LUKS_TF" random_password inngest_redis_luks "$COSMETIC"
assert_mut_green "P1c cosmetic rewrite on the doppler_secret" "$LUKS_TF" doppler_secret inngest_redis_luks_key "$COSMETIC"
assert_mut_green "P1d cosmetic rewrite on doppler_project.inngest" "$HOST_TF" doppler_project inngest "$COSMETIC"
assert_mut_green "P1e cosmetic rewrite on doppler_environment.inngest_prd" "$HOST_TF" doppler_environment inngest_prd "$COSMETIC"
assert_mut_green "P2 attachment with a trailing comment mentioning prevent_destroy" "$LUKS_TF" hcloud_volume_attachment inngest_redis_luks \
  's/^([[:space:]]+server_id[[:space:]]*=.*)$/\1  # no lifecycle { prevent_destroy = true } here, see the runbook/'
assert_mut_green "P3 attachment with a multi-line comment holding a lifecycle block" "$LUKS_TF" hcloud_volume_attachment inngest_redis_luks \
  's/^([[:space:]]+volume_id[[:space:]]*=.*)$/\1\n  \/*\n  lifecycle {\n    prevent_destroy = true\n  }\n  *\//'
assert_mut_green "P4 volume with a multi-line comment before the guarded lines and a string holding /*" "$LUKS_TF" $VOL_T $VOL_N \
  's~^([[:space:]]+location[[:space:]]*=.*)$~\1\n  /* P4 note: a multi-line comment\n     that closes before the guarded lines */\n  note = "glob /mnt/*"~'
P5_BODY='resource "doppler_secret" "scratch" {
  project = "soleur-inngest-rehearsal"
  config  = "prd"
  name    = "INNGEST_REDIS_LUKS_KEY"
  value   = "synthetic-not-a-secret"
}'
assert_plant_green "P5 the rehearsal sub-root: a same-NAME scratch secret in a subdirectory (never scanned)" inngest-provision-rehearsal/scratch.tf "$P5_BODY"
P6_BODY='resource "doppler_secret" "elsewhere" {
  project = "soleur"
  config  = "prd"
  name    = "INNGEST_REDIS_LUKS_KEY"
  value   = "synthetic-not-a-secret"
}'
assert_plant_green "P6 the same NAME on a different Doppler project, provable by string literal" other_project_secret.tf "$P6_BODY"

# --- Harness rows: neutering the shared lexer must redden THIS suite -----------------------
# Run a copy of this suite on a scratch tree that has the same layout (apps/web-platform/infra,
# tests/scripts/lib) and sources a NEUTERED copy of the lexer. Nested runs (SOLE_COPY_NESTED) execute only
# H0, H1 and R3 and exit, and must exit 1 (a verdict, never a crash) with the named row failing.
nested_neutered() { # <name> <function-override> <expected-fail-row-substring>
  local name="$1" override="$2" expect="$3" root out rc=0
  cases=$((cases + 1))
  root="$(mktemp -d "$SUITE_TMP/nest.XXXXXX")" || { printf 'FATAL: mktemp -d failed\n' >&2; exit 2; }
  assert_fixture_dir "$root"
  mkdir -p "$root/apps/web-platform/infra" "$root/tests/scripts/lib" || { printf 'FATAL: mkdir failed\n' >&2; exit 2; }
  cp "$PRISTINE"/*.tf "$root/apps/web-platform/infra/" || { printf 'FATAL: cp failed\n' >&2; exit 2; }
  cp "${BASH_SOURCE[0]}" "$root/apps/web-platform/infra/inngest-luks-sole-copy.test.sh" || { printf 'FATAL: cp failed\n' >&2; exit 2; }
  cp "$HCL_LIB" "$root/tests/scripts/lib/hcl-effective-text.sh" || { printf 'FATAL: cp failed\n' >&2; exit 2; }
  printf '\n%s\n' "$override" >> "$root/tests/scripts/lib/hcl-effective-text.sh"
  out="$(SOLE_COPY_NESTED=1 bash "$root/apps/web-platform/infra/inngest-luks-sole-copy.test.sh" 2>&1)"
  rc=$?
  if [ "$rc" -eq 1 ] && grep -Fq "$expect" <<<"$out"; then
    pass
  else
    fail "$name: the neutered lexer did not redden the suite as expected (rc=$rc, wanted rc=1 with a failing row containing [$expect])"
  fi
  rm -rf "$root"
}
nested_neutered "HX1 strip_comments neutered to the identity function" 'strip_comments() { cat "$1"; }' "R3 volume lifecycle wrapped in a multi-line"
nested_neutered "HX2 block extraction neutered to empty" 'block_of() { :; }' "H0 control: the unmutated root holds every pin"

# --- Accounting and floor -----------------------------------------------------------------
# Reported by printf + exit 1, NEVER through fail(): a neutered fail() must not silence the floor.
if [ "$((passes + fails))" -ne "$cases" ]; then
  printf '[FATAL] accounting identity: passes(%s) + fails(%s) != cases(%s) - a verdict was discarded\n' "$passes" "$fails" "$cases" >&2
  exit 1
fi
MIN_CASES=36
if [ "$cases" -lt "$MIN_CASES" ]; then
  printf '[FATAL] anti-vacuity floor: only %s cases ran, floor is %s\n' "$cases" "$MIN_CASES" >&2
  exit 1
fi

echo "inngest-luks-sole-copy: ${passes} passed, ${fails} failed (${cases} cases)"
[ "$fails" -eq 0 ]
