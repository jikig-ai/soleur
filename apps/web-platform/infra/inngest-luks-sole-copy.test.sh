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
#                                               soleur-inngest/prd; every doppler_secret on that
#                                               project/config has a plain string-literal `name`;
#                                               no `change_protection` anywhere in effective text
#   the six pinned blocks                       no count / for_each / provider / provisioner block
#   the runbook + infra-validation.yml          the runbook heading the failure messages cite exists, the
#                                               lexer and the runbook are in infra-validation's
#                                               pull_request.paths, and the read-back one-liner in the
#                                               postmerge skill is byte-identical to the runbook's
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
#   R5  ignore_changes on the volume or either member R11 a second writer of INNGEST_REDIS_LUKS_KEY (plain,
#   R6  prevent_destroy moved into a non-lifecycle        referenced, local, and INDENTED)
#       block                                         R12 extractor returns empty (renamed resource)
#   R13 a trailing comment holding a heredoc opener (hash or double-slash form) hides a wrapped protection
#   R14 a doppler_secret whose name is not a plain string literal (local, upper(), each.key, a quoted but
#       templated name, all three attributes locals) and that is not provably on another project/config
#   R15 count / for_each / provider / provisioner on one of the six pinned blocks
#   R16 `change_protection` (the Hetzner action that lifts delete protection) or the hcloud CLI spelling
#       `disable-protection` in any effective .tf text (planted both before and after the real candidates)
#   R17 a `{` in a TRAILING comment (the brace counter must count code only)
#   R18 a fake `lifecycle { prevent_destroy = true }` inside a HEREDOC (literal text, never code)
# Harness rows: the lexer neutered to the identity function, and block extraction neutered to empty,
# must each redden THIS suite (run on a scratch tree that sources a neutered copy of the lexer).
# NEGATIVE CONTROLS (N1-N3, and HX3-HX5 which neuter the helper each one watches): a deliberately wrong
# expected code must be judged FAIL, a sed that changes nothing must make apply_block_sed refuse, a
# change outside the block must make `confined` refuse (N3 also pins its four boundaries: an insertion
# or an edit right before the header and right after the closing brace). Without them, neutering has_viol /
# confined / the landing check left every matrix row green (measured 36/0 each, at 36 cases). N4: the block
# range `confined` is built on ignores braces in comments, strings and heredocs.
# DOC AND CI WIRING ROWS (H1b-H1e, H2): the runbook heading the messages cite exists (and a renamed copy is
# judged missing); the lexer and the runbook are in infra-validation.yml pull_request.paths (and a workflow
# copy without the entry is judged missing); the read-back one-liner is byte-identical in the postmerge skill
# and the runbook (and a copy with another volume id is judged different).
# ACCOUNTING PROOFS (HX6, HX7): a copy that drops one `cases` increment must trip the pass+fail != cases
# identity, and a copy that runs almost no rows must trip the MIN_CASES floor. MIN_CASES is also pinned
# EXACTLY to the measured case count, so lowering it (or adding rows without re-measuring) is a FATAL.
# Must-PASS rows: cosmetic rewrites (spacing, trailing comment), an attachment whose comments
# mention prevent_destroy / a lifecycle block, the rehearsal sub-root's scratch secret of the same
# NAME (a different directory, never scanned), the same NAME on a different Doppler project, a REAL
# heredoc whose body holds comment-looking lines, a non-literal secret name on another project, and a
# comment that mentions change_protection.
#
# ANCHOR (stated, not hidden): these pins and this guard land in one diff, so one diff can weaken
# both. THIS SUITE IS ADVISORY until it is promoted to a required check (#9927). The required-check anchor
# is the G2e attribute pin in plugins/soleur/test/terraform-target-parity.test.ts (the parity test), an
# independent re-implementation, in another language and with its own lexer, of what must not be weakenable
# in one diff. The census (G4h / G4_PROTECTED in tests/scripts/test-infra-privileged-tier-census.sh) pins
# that the six addresses stay declared and not removed or moved, NOT their attribute lines, so it is not an
# anchor for those. The other independent check is the post-merge read of live Hetzner state.
#
# Every failure names the runbook section "Sole-copy protection and key loss" in
# knowledge-base/engineering/operations/runbooks/inngest-luks-cutover-6894.md: lifting a protection
# deliberately is a reviewed two-step change (delete protection first, then prevent_destroy).
#
# Run: bash apps/web-platform/infra/inngest-luks-sole-copy.test.sh
# Presence under apps/web-platform/infra/ IS registration (derived by run-registered-suites.sh).
# Nested runs (the harness rows that neuter the lexer or a helper in a COPY of this suite) are selected
# by the suite-private argv flag `--nested <mode>`, never by an environment variable: an ambient export
# in a developer's shell must not be able to shrink the suite to its control rows.
#
# `set -e` is deliberately ABSENT: deliberately-nonzero greps are wrapped so the harness never
# aborts mid-suite.
set -uo pipefail

# Suite-private nested-run selector. Anything else on argv (including extra arguments after the mode) is a
# usage error; the environment is not read.
NESTED=""
if [ "$#" -gt 0 ]; then
  case "$#:$1:${2-}" in
    2:--nested:r3|2:--nested:negctl|2:--nested:acct|2:--nested:floor) NESTED="$2" ;;
    *) printf 'usage: %s [--nested r3|negctl|acct|floor]\n' "$0" >&2; exit 2 ;;
  esac
fi

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# The shared lexer is resolved from the REPO ROOT (this suite's "$DIR/../../.."), the lib's one home, never
# from a copy next to this suite.
REPO_ROOT="$(cd "$DIR/../../.." && pwd)"
HCL_LIB="$REPO_ROOT/tests/scripts/lib/hcl-effective-text.sh"
[ -f "$HCL_LIB" ] || { printf 'FATAL: shared HCL lexer not found at %s\n' "$HCL_LIB" >&2; exit 2; }
# shellcheck source=../../../tests/scripts/lib/hcl-effective-text.sh
. "$HCL_LIB" || { printf 'FATAL: could not source %s\n' "$HCL_LIB" >&2; exit 2; }

RUNBOOK_REL="knowledge-base/engineering/operations/runbooks/inngest-luks-cutover-6894.md"
RUNBOOK_SECTION="Sole-copy protection and key loss"
LUKS_TF="inngest-redis-luks.tf"
HOST_TF="inngest-host.tf"
EXPECTED_CHECKS=21

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
# A killed run (SIGKILL skips the EXIT trap) leaves its tree behind: sweep stale ones (older than a day)
# so /var/tmp does not accumulate them. Real directories only (-type d never follows a symlink).
[ -n "$NESTED" ] || find "${TMPDIR:-/var/tmp}" -maxdepth 1 -type d -name 'inngest-sole-copy-suite.*' -mmin +1440 -exec rm -rf {} + 2>/dev/null || true
SUITE_TMP="$(mktemp -d "${TMPDIR:-/var/tmp}/inngest-sole-copy-suite.XXXXXX")" || { printf 'FATAL: mktemp -d failed\n' >&2; exit 2; }
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
# non-lifecycle block" visible. The text is read through blank_heredocs and braces are counted on cv()
# (both from the shared lexer): a heredoc body is literal text, so a fake `lifecycle { prevent_destroy = true }`
# in one is not a lifecycle block, and a brace in a trailing comment or a string moves no depth.
blk_scan() {
  blank_heredocs | awk -v mode="$1" "$HCL_AWK_FUNCS"'
    {
      c = cv($0); o = gsub(/\{/, "{", c); x = gsub(/\}/, "}", c)
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
  total="$(blank_heredocs <<<"$1" | code_only | grep -Ec '(^|[^A-Za-z_])prevent_destroy[[:space:]]*=')"
  [ "$total" = "1" ] || { echo 0; return; }
  attr_true_in "$(blk_scan lifecycle <<<"$1")" prevent_destroy
}

p_no_ignore_changes() { # <block> : the key-drift detector depends on there being none
  local c
  [ -n "$1" ] || { echo 0; return; }
  # Capture first: `code_only | grep -q` under pipefail reads a SIGPIPE (141) as "no match" once grep
  # exits early on a large block.
  c="$(code_only <<<"$1")"
  if grep -Eq '(^|[^A-Za-z_])ignore_changes[[:space:]]*=' <<<"$c"; then echo 0; else echo 1; fi
}

# The four meta-arguments that change WHICH instances exist or HOW they are managed. A `count` or
# `for_each` re-addresses the resource (the address the pins and the runbook name stops existing), a
# `provider` alias retargets it, and a `provisioner` block runs arbitrary commands on create or destroy
# (it is the other way, besides a Terraform resource, to lift a protection). Depth-1 lines only: the
# same words inside `labels` or `lifecycle` are ordinary attributes.
p_no_meta_args() { # <block>
  local d
  [ -n "$1" ] || { echo 0; return; }
  d="$(blk_scan direct <<<"$1" | code_only)"
  if grep -Eq '^[[:space:]]*((count|for_each|provider)[[:space:]]*=|provisioner[[:space:]]*")' <<<"$d"; then echo 0; else echo 1; fi
}

p_attachment_unpinned() { # <block> : NO lifecycle block and no prevent_destroy assignment, comments excluded
  local c
  [ -n "$1" ] || { echo 0; return; }
  c="$(code_only <<<"$1")"
  if grep -Eq '(^|[^A-Za-z_])(lifecycle[[:space:]]*\{|prevent_destroy[[:space:]]*=)' <<<"$c"; then echo 0; else echo 1; fi
}

# Resource block of one address across the root's top-level *.tf. TB_COUNT = number of declarations
# found (exactly one is required); TB_BLOCK = their comment-stripped text. ONE raw grep per tree
# (CAND_FILES, an array set by evaluate_tree) picks the candidate files for all six addresses; a header hidden in
# a comment is still resolved by block_of itself. A header the raw grep cannot see is not a header
# block_of can see either (both anchor on column 0).
tree_block() { # <dir> <type> <name>
  local dir="$1" type="$2" name="$3" f b n
  TB_COUNT=0; TB_BLOCK=""
  for f in ${CAND_FILES[@]+"${CAND_FILES[@]}"}; do
    grep -Eq "^resource[[:space:]]+\"${type}\"[[:space:]]+\"${name}\"" "$f" || continue
    b="$(block_of "$f" "$type" "$name")"
    [ -n "$b" ] || continue
    n="$(grep -Ec "^resource[[:space:]]+\"${type}\"[[:space:]]+\"${name}\"" <<<"$b")"
    TB_COUNT=$((TB_COUNT + n))
    TB_BLOCK="${TB_BLOCK}${b}"$'\n'
  done
}

# ONE emitter for both doppler_secret censuses below: prints one line per `resource "doppler_secret"`
# block in <file> (an indented header counts), `name US project US config` (US = the unit separator, a
# non-whitespace delimiter so an absent attribute stays an empty field), each the raw right-hand side of the
# block's own depth-1 attribute with a trailing comment cut. Read through the shared lexer; braces are counted
# on cv(); a heredoc body is skipped, so a fake `project = "elsewhere"` inside a heredoc `value` cannot launder
# a writer into "provably on another project".
doppler_secret_blocks() { # <file>
  strip_comments "$1" | awk "$HCL_AWK_FUNCS"'
    function code(s) { sub(/[[:space:]]*(#|\/\/).*$/, "", s); sub(/[[:space:]]+$/, "", s); return s }
    function val(s, key,   r) { r = s; if (sub("^[[:space:]]*" key "[[:space:]]*=[[:space:]]*", "", r)) return code(r); return "" }
    { if (in_heredoc($0)) next }
    /^[[:space:]]*resource[[:space:]]+"doppler_secret"/ { inb = 1; d = 0; nm = ""; pj = ""; cf = "" }
    inb {
      c = cv($0); before = d
      d += gsub(/\{/, "{", c); x = gsub(/\}/, "}", c); d -= x
      if (before == 1) {
        v = val($0, "name");    if (v != "") nm = v
        v = val($0, "project"); if (v != "") pj = v
        v = val($0, "config");  if (v != "") cf = v
      }
      if (d <= 0 && x > 0) { printf "%s\037%s\037%s\n", nm, pj, cf; inb = 0 }
    }'
}
US=$'\037'
# A quoted string with no interpolation, template directive or escape: the only shape whose value is known
# from the text alone. A quoted-but-templated "${local.x}_KEY" is NOT a literal.
LITERAL_RE='^"[^"$%\\]*"$'
is_literal() { [[ "${1-}" =~ $LITERAL_RE ]]; }
# PROVABLY not the inngest project / prd config: a string LITERAL project other than soleur-inngest, or a
# string LITERAL config other than prd. A reference, a local or a templated string proves nothing.
secret_elsewhere() { # <project> <config> -> 0 when provably elsewhere
  { is_literal "$1" && [ "$1" != '"soleur-inngest"' ]; } || { is_literal "$2" && [ "$2" != '"prd"' ]; }
}

# Writers of INNGEST_REDIS_LUKS_KEY on soleur-inngest/prd across the root's top-level *.tf: every
# doppler_secret named so, except one PROVABLY on another project or config by a string literal. A
# project or config that is a reference, a local or a templated string counts as a writer.
count_key_writers() { # <dir> -> number
  local dir="$1" f total=0 nm pj cf
  local -a files
  mapfile -t files < <(grep -l 'INNGEST_REDIS_LUKS_KEY' "$dir"/*.tf 2>/dev/null)
  for f in ${files[@]+"${files[@]}"}; do
    [ -f "$f" ] || continue
    while IFS="$US" read -r nm pj cf; do
      [ "$nm" = '"INNGEST_REDIS_LUKS_KEY"' ] || continue
      secret_elsewhere "$pj" "$cf" || total=$((total + 1))
    done < <(doppler_secret_blocks "$f")
  done
  echo "$total"
}

# Every doppler_secret in the root that is not PROVABLY on another project or config (the same `elsewhere`
# rule as count_key_writers) must carry a plain string-literal `name`. count_key_writers can only see a writer
# whose name it can READ; `name = local.k`, `upper("inngest_redis_luks_key")`, a templated "${local.p}_KEY" or
# `for_each` with `name = each.key` would write the same key invisibly, and so would a secret whose project
# and config are locals too (the opaque shape is flagged, not only the one that names the inngest project).
# Prints 1 (all literal or provably elsewhere) or 0.
p_inngest_secret_names_literal() { # <dir>
  local dir="$1" f nm pj cf bad=0
  # RAW greps first (they only ever over-select: the lexer cannot create a token that is not in the file), so
  # the lexer runs only on files that declare a doppler_secret AND hold a `name =` line that is not a plain
  # quoted literal (a non-literal name is the only way to be flagged below). The second grep needs PCRE; when
  # it is unavailable (rc 2) every doppler_secret file stays a candidate, never fewer.
  local -a cand all
  mapfile -t all < <(grep -lE '^[[:space:]]*resource[[:space:]]+"doppler_secret"' "$dir"/*.tf 2>/dev/null)
  cand=()
  if [ "${#all[@]}" -gt 0 ]; then
    mapfile -t cand < <(grep -lP '^\s*name\s*=(?!\s*"[^"$%\\]*"\s*((#|//).*)?$)' "${all[@]}" 2>/dev/null || { [ "$?" -ne 2 ] || printf '%s\n' "${all[@]}"; })
  fi
  for f in ${cand[@]+"${cand[@]}"}; do
    [ -f "$f" ] || continue
    while IFS="$US" read -r nm pj cf; do
      is_literal "$nm" && continue
      secret_elsewhere "$pj" "$cf" && continue
      bad=1
    done < <(doppler_secret_blocks "$f")
  done
  if [ "$bad" = "0" ]; then echo 1; else echo 0; fi
}

# `change_protection` is the Hetzner volume action that lifts delete protection (API
# `actions/change_protection`; the hcloud CLI spells the same action `disable-protection`, and
# `enable-protection` is its sibling; the provider's own `delete_protection` attribute is NOT these words).
# None has any business in the root's effective text outside a comment: a terraform_data / local-exec / http
# that names one is a second, unpinned way to unprotect the volume.
# Trailing comments are kept by the lexer, so a trailing-comment mention is RED too (fail safe: reword
# it); whole-line and block comments are blanked and may discuss it freely.
CP_TOKENS=(-e change_protection -e disable-protection -e enable-protection)
p_no_change_protection() { # <dir>
  local f txt
  local -a cand
  mapfile -t cand < <(grep -lF "${CP_TOKENS[@]}" "$1"/*.tf 2>/dev/null)   # raw superset, then the lexer
  for f in ${cand[@]+"${cand[@]}"}; do
    [ -f "$f" ] || continue
    txt="$(strip_comments "$f")"
    if grep -Fq "${CP_TOKENS[@]}" <<<"$txt"; then echo 0; return; fi
  done
  echo 1
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
  mapfile -t CAND_FILES < <(grep -lE '^resource[[:space:]]+"[a-z_]+"[[:space:]]+"(inngest_redis_luks|inngest_redis_luks_key|inngest|inngest_prd)"' "$TREE"/*.tf 2>/dev/null)
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
  local meta=1 mb
  for mb in "$B_VOL" "$B_ATT" "$B_PW" "$B_SEC" "$B_PROJ" "$B_ENV"; do
    [ "$(p_no_meta_args "$mb")" = "1" ] || meta=0
  done
  check META_ARGS "$meta"
  check SEC_NAME_NOT_LITERAL "$(p_inngest_secret_names_literal "$TREE")"
  check CHANGE_PROTECTION "$(p_no_change_protection "$TREE")"
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
    META_ARGS)            echo "one of the six pinned blocks carries count, for_each, provider or a provisioner block (it re-addresses, retargets or scripts a protected resource)" ;;
    SEC_NAME_NOT_LITERAL) echo "a doppler_secret that is not provably on another project/config has a name that is not a plain string literal (the single-writer census cannot read it)" ;;
    CHANGE_PROTECTION)    echo "a .tf file names change_protection / disable-protection / enable-protection in effective text (a second, unpinned way to lift the Hetzner delete protection)" ;;
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

# Apply an in-block sed (-E) to <file> of a fresh tree (or, with <existing-tree>, a SECOND step on a tree an
# earlier step already mutated, for a mutation that spans two resource blocks); sets MUT_TREE. Returns 1 (and
# says why) when the mutation did not land or strayed outside the block, so a vacuous row is a FAIL, never a pass.
MUT_TREE=""
apply_block_sed() { # <name> <file> <type> <resname> <inner-sed> [<existing-tree>]
  local name="$1" file="$2" type="$3" rname="$4" inner="$5" tree base
  if [ -n "${6-}" ]; then
    tree="$6"; base="$tree/$file.before"
    assert_fixture_dir "$tree"
    cp "$tree/$file" "$base" || { fail "$name: could not snapshot the first-step file"; return 1; }
  else
    tree="$(new_tree)"; base="$PRISTINE/$file"
  fi
  assert_fixture_dir "$tree"
  MUT_TREE="$tree"
  sed -E "/^resource \"${type}\" \"${rname}\" \{/,/^\}/ { ${inner} }" "$base" > "$tree/$file" \
    || { fail "$name: sed failed"; return 1; }
  if cmp -s "$base" "$tree/$file"; then fail "$name: the mutation changed nothing (vacuous row)"; return 1; fi
  if ! confined "$base" "$tree/$file" "$type" "$rname"; then
    fail "$name: the mutation was not confined to resource \"$type\" \"$rname\""; return 1
  fi
  [ -z "${6-}" ] || rm -f "$base"
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
# A mutation that spans TWO blocks (<t1>.<n1> then <t2>.<n2>, both in <file>), each step confined to its own
# block. RED for the named code, or (the control) GREEN.
apply_chain() { # <name> <file> <t1> <n1> <sed1> <t2> <n2> <sed2>
  apply_block_sed "$1" "$2" "$3" "$4" "$5" || return 1
  apply_block_sed "$1 (second block)" "$2" "$6" "$7" "$8" "$MUT_TREE"
}
assert_chain_red() { # <name> <expected-code> <file> <t1> <n1> <sed1> <t2> <n2> <sed2>
  local name="$1" code="$2" tree
  if ! apply_chain "$name" "$3" "$4" "$5" "$6" "$7" "$8" "$9"; then cases=$((cases + 1)); return; fi
  tree="$MUT_TREE"
  assert_red_tree "$name" "$code" "$tree"
  drop_tree "$tree"
}
assert_chain_green() { # <name> <file> <t1> <n1> <sed1> <t2> <n2> <sed2>
  local name="$1" tree
  if ! apply_chain "$name" "$2" "$3" "$4" "$5" "$6" "$7" "$8"; then cases=$((cases + 1)); return; fi
  tree="$MUT_TREE"
  assert_green_tree "$name" "$tree"
  drop_tree "$tree"
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

# --- Negative controls for the verdict helpers -----------------------------------------
# Each body runs inside a command substitution (a subshell), so its counters and ledger roll back
# exactly like suite_selftest's, and reports through printf only, never through pass()/fail(), the
# helpers under suspicion. The caller compares the report to the one value an HONEST helper produces.

# N1: a deliberately WRONG expected code must be judged FAIL, the right one PASS: 1 pass, 1 fail.
nc_wrong_code() {
  passes=0; fails=0
  if ! apply_block_sed "nc" "$LUKS_TF" hcloud_volume inngest_redis_luks 's/^([[:space:]]+delete_protection[[:space:]]*=[[:space:]]*)true/\1false/'; then
    printf 'setup-failed'; return
  fi
  assert_red_tree "nc-wrong-code" NO_SUCH_CODE "$MUT_TREE"
  assert_red_tree "nc-right-code" VOL_DELETE_PROTECTION "$MUT_TREE"
  drop_tree "$MUT_TREE"
  printf '%s/%s' "$passes" "$fails"
}
# N2: a sed that changes nothing must make apply_block_sed refuse (return non-zero, one fail).
nc_noop_sed() {
  passes=0; fails=0
  if apply_block_sed "nc" "$LUKS_TF" hcloud_volume inngest_redis_luks 's/ZZ_NO_SUCH_TEXT_ZZ/x/'; then
    printf 'accepted-a-noop-mutation'
  else
    printf 'refused/%s' "$fails"
  fi
  drop_tree "$MUT_TREE"
}
# N3: `confined` accepts a change INSIDE the volume block (an edit, an insertion right after the header,
# an insertion right before the closing brace) and refuses every change OUTSIDE it, at both file ends and on
# the exact boundaries: an insertion right before the header, an insertion right after the closing brace, an
# edit of the line before the header, an edit of the line after the closing brace. The verdict string is
# `inside/ins-after-header/ins-before-close` (all 0 = accepted) then `file-start/file-end/ins-before-header/
# ins-after-close/edit-before-header/edit-after-close` (all 1 = refused).
nc_confined() {
  local t range s e v out=""
  t="$(new_tree)"
  assert_fixture_dir "$t"
  range="$(_b4_block_range "$PRISTINE/$LUKS_TF" hcloud_volume inngest_redis_luks)"
  s="${range% *}"; e="${range#* }"
  sed -E '/^resource "hcloud_volume" "inngest_redis_luks" \{/,/^\}/ s/^([[:space:]]+delete_protection[[:space:]]*=[[:space:]]*)true/\1false/' "$PRISTINE/$LUKS_TF" > "$t/in.tf"
  sed "${s}a # ins" "$PRISTINE/$LUKS_TF" > "$t/ins_after_header.tf"
  sed "${e}i # ins" "$PRISTINE/$LUKS_TF" > "$t/ins_before_close.tf"
  { printf '# stray first line\n'; cat "$PRISTINE/$LUKS_TF"; } > "$t/before.tf"
  { cat "$PRISTINE/$LUKS_TF"; printf '# stray last line\n'; } > "$t/after.tf"
  sed "${s}i # ins" "$PRISTINE/$LUKS_TF" > "$t/ins_before_header.tf"
  sed "${e}a # ins" "$PRISTINE/$LUKS_TF" > "$t/ins_after_close.tf"
  sed "$((s - 1))s/\$/ # edit/" "$PRISTINE/$LUKS_TF" > "$t/edit_before_header.tf"
  sed "$((e + 1))s/\$/ # edit/" "$PRISTINE/$LUKS_TF" > "$t/edit_after_close.tf"
  for v in in ins_after_header ins_before_close before after ins_before_header ins_after_close edit_before_header edit_after_close; do
    if confined "$PRISTINE/$LUKS_TF" "$t/$v.tf" hcloud_volume inngest_redis_luks; then out="${out}0/"; else out="${out}1/"; fi
  done
  drop_tree "$t"
  printf '%s' "${out%/}"
}
negctl_rows() {
  local got
  cases=$((cases + 1))
  got="$(nc_wrong_code 2>/dev/null)"
  if [ "$got" = "1/1" ]; then pass; else fail "N1 a wrong expected violation code was not judged FAIL (got passes/fails=[$got], want 1/1): has_viol or assert_red_tree is blind"; fi
  cases=$((cases + 1))
  got="$(nc_noop_sed 2>/dev/null)"
  if [ "$got" = "refused/1" ]; then pass; else fail "N2 a no-op sed was not refused by apply_block_sed (got [$got], want refused/1): the landing check is blind"; fi
  cases=$((cases + 1))
  got="$(nc_confined 2>/dev/null)"
  if [ "$got" = "0/0/0/1/1/1/1/1/1" ]; then pass; else fail "N3 confined() did not accept in-block changes and refuse out-of-block ones, boundaries included (got [$got], want 0/0/0/1/1/1/1/1/1: in, ins-after-header, ins-before-close, file-start, file-end, ins-before-header, ins-after-close, edit-before-header, edit-after-close)"; fi
}

# --- Accounting and floor -----------------------------------------------------------------
# Reported by printf + exit 1, NEVER through fail(): a neutered fail() must not silence the floor.
# A function so the nested accounting modes (--nested acct|floor) can run it after only the control row.
finish() {
  if [ "$((passes + fails))" -ne "$cases" ]; then
    printf '[FATAL] accounting identity: passes(%s) + fails(%s) != cases(%s) - a verdict was discarded\n' "$passes" "$fails" "$cases" >&2
    exit 1
  fi
  MIN_CASES=89
  if [ "$cases" -lt "$MIN_CASES" ]; then
    printf '[FATAL] anti-vacuity floor: only %s cases ran, floor is %s\n' "$cases" "$MIN_CASES" >&2
    exit 1
  fi
  # The floor is pinned EXACTLY to the measured case count: lowering MIN_CASES (which would let rows be
  # deleted unnoticed) and adding rows without re-measuring it are both FATAL. The two nested runs that reach
  # this point (acct, floor) have 2 cases and are stopped by the floor check above, so they never get here.
  [ "$cases" -le "$MIN_CASES" ] || { printf '[FATAL] floor drift: %s cases ran but MIN_CASES is %s - re-measure and set MIN_CASES=%s\n' "$cases" "$MIN_CASES" "$cases" >&2; exit 1; }
  echo "inngest-luks-sole-copy: ${passes} passed, ${fails} failed (${cases} cases)"
  [ "$fails" -eq 0 ]
}

# --- Harness rows ---------------------------------------------------------------------

# H0: the unmutated tree is GREEN (the control every RED row is measured against), and the real
# tree, read in place, agrees with its snapshot.
assert_green_tree "H0 control: the unmutated root holds every pin" "$PRISTINE"
assert_green_tree "H0 the real root, read in place, holds every pin" "$DIR"
# Nested accounting runs (a COPY of this suite, started by HX6/HX7/HX3-HX5 below) stop here: `acct` and
# `floor` run the accounting block after the control rows alone, `negctl` runs only the negative controls.
case "$NESTED" in
  acct|floor) finish; exit $? ;;
  negctl)     negctl_rows; [ "$fails" -eq 0 ]; exit $? ;;
esac

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
# The heredoc opener is built from two pieces so this file's own source holds no heredoc opener
# (scripts/guard-vacuity-floor.test.sh reads a double less-than plus a word anywhere, even in a comment, as a heredoc and would skip lines).
LT2='<''<'
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
# The `--nested r3` runs (the lexer-neutering harness rows below) execute only H0, H1 and R3, and exit.
if [ "$NESTED" = r3 ]; then
  [ "$fails" -eq 0 ]
  exit
fi

# H1b: the heading the failure messages send the reader to must exist in the runbook. Matched on the
# heading TEXT (a `##`/`###` line), not its section number, which a reorganisation may change.
runbook_has_heading() { # <file> -> 0|1
  grep -Eq "^#{2,3}[[:space:]]+.*${RUNBOOK_SECTION}" "$1" 2>/dev/null
}
cases=$((cases + 1))
if runbook_has_heading "$REPO_ROOT/$RUNBOOK_REL"; then
  pass
else
  fail "H1b: $RUNBOOK_REL has no ## or ### heading containing \"$RUNBOOK_SECTION\", which every failure message cites"
fi
# H1c (negative control for H1b): a runbook copy whose heading is renamed must NOT satisfy the predicate.
cases=$((cases + 1))
h1c_dir="$(mktemp -d "$SUITE_TMP/h1c.XXXXXX")" || { printf 'FATAL: mktemp -d failed\n' >&2; exit 2; }
assert_fixture_dir "$h1c_dir"
sed -E "/^#{2,3}[[:space:]]+.*${RUNBOOK_SECTION}/ s/${RUNBOOK_SECTION}/Renamed section/" "$REPO_ROOT/$RUNBOOK_REL" > "$h1c_dir/runbook.md" 2>/dev/null
if cmp -s "$REPO_ROOT/$RUNBOOK_REL" "$h1c_dir/runbook.md"; then
  fail "H1c: the heading rename changed nothing (vacuous row)"
elif runbook_has_heading "$h1c_dir/runbook.md"; then
  fail "H1c: a runbook whose heading was renamed still satisfied the H1b predicate (H1b is blind)"
else
  pass
fi
drop_tree "$h1c_dir"

# H1d/H1e (+ controls): the lexer and the runbook must be in infra-validation.yml's pull_request.paths, or a
# lexer-only or docs-only edit skips the suite whose rows exist to catch it (sibling idiom:
# inngest-host-state-workflow-guard.test.sh asserts the same for its workflow and script).
INFRA_WF_REL=".github/workflows/infra-validation.yml"
LEXER_REL="tests/scripts/lib/hcl-effective-text.sh"
pr_paths_has() { # <workflow-file> <path> -> yes|no|error
  python3 -c '
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1])) or {}
on = wf.get("on", wf.get(True)) or {}
print("yes" if sys.argv[2] in list((on.get("pull_request") or {}).get("paths") or []) else "no")
' "$1" "$2" 2>/dev/null || echo error
}
cases=$((cases + 1))
if [ "$(pr_paths_has "$REPO_ROOT/$INFRA_WF_REL" "$LEXER_REL")" = yes ]; then pass; else fail "H1d: $LEXER_REL is not in $INFRA_WF_REL pull_request.paths (a lexer-only edit would skip this suite)"; fi
cases=$((cases + 1))
if [ "$(pr_paths_has "$REPO_ROOT/$INFRA_WF_REL" "$RUNBOOK_REL")" = yes ]; then pass; else fail "H1e: $RUNBOOK_REL is not in $INFRA_WF_REL pull_request.paths (a docs-only heading rename would skip H1b)"; fi
# Controls: the same workflow with that one entry removed must read "no" (a vacuous reader would say yes).
path_control() { # <name> <path>
  local name="$1" path="$2" d
  cases=$((cases + 1))
  d="$(mktemp -d "$SUITE_TMP/wf.XXXXXX")" || { printf 'FATAL: mktemp -d failed\n' >&2; exit 2; }
  assert_fixture_dir "$d"
  grep -vF -- "- \"$path\"" "$REPO_ROOT/$INFRA_WF_REL" > "$d/wf.yml"
  if cmp -s "$REPO_ROOT/$INFRA_WF_REL" "$d/wf.yml"; then
    fail "$name: removing the entry changed nothing (vacuous row)"
  elif [ "$(pr_paths_has "$d/wf.yml" "$path")" = no ]; then
    pass
  else
    fail "$name: a workflow without the $path entry still read as having it"
  fi
  drop_tree "$d"
}
path_control "H1d control (lexer entry removed)" "$LEXER_REL"
path_control "H1e control (runbook entry removed)" "$RUNBOOK_REL"

# H2: the one-line read-back command (identified by `protection.delete`) is carried by the postmerge skill
# AND the runbook, and nothing else ties the copies. Byte equality of the FIRST fenced block in each file whose
# body holds that substring. Both docs are edited by hand, so a drifted copy (a different volume id, a
# dropped exit code) would make the skill assert the wrong thing about the sole copy's protection.
SKILL_REL="plugins/soleur/skills/postmerge/SKILL.md"
readback_of() { # <md-file> -> the first fenced block containing `protection.delete`, fences excluded
  awk '
    /^[[:space:]]*```/ { if (inf) { if (hit) { printf "%s", buf; exit } inf = 0 } else { inf = 1; hit = 0 } buf = ""; next }
    inf { buf = buf $0 "\n"; if (index($0, "protection.delete")) hit = 1 }
  ' "$1" 2>/dev/null
}
readback_parity() { # <skill-md> <runbook-md> -> 1 (both found, byte-identical) | 0
  local d a b rc=0
  d="$(mktemp -d "$SUITE_TMP/rb.XXXXXX")" || { printf 'FATAL: mktemp -d failed\n' >&2; exit 2; }
  assert_fixture_dir "$d"
  readback_of "$1" > "$d/skill.txt"
  readback_of "$2" > "$d/runbook.txt"
  a="$(wc -c < "$d/skill.txt")"; b="$(wc -c < "$d/runbook.txt")"
  if [ "$a" -gt 0 ] && [ "$b" -gt 0 ] && cmp -s "$d/skill.txt" "$d/runbook.txt"; then echo 1; else echo 0; fi
  drop_tree "$d"
}
cases=$((cases + 1))
if [ "$(readback_parity "$REPO_ROOT/$SKILL_REL" "$REPO_ROOT/$RUNBOOK_REL")" = 1 ]; then
  pass
else
  fail "H2: the read-back command in $SKILL_REL differs from (or is missing beside) the one in $RUNBOOK_REL; they must be byte-identical"
fi
# H2 control: a runbook copy whose volume id differs must NOT be judged equal.
cases=$((cases + 1))
h2_dir="$(mktemp -d "$SUITE_TMP/h2.XXXXXX")" || { printf 'FATAL: mktemp -d failed\n' >&2; exit 2; }
assert_fixture_dir "$h2_dir"
sed -E '/protection\.delete/ s#/v1/volumes/[0-9]+#/v1/volumes/1#' "$REPO_ROOT/$RUNBOOK_REL" > "$h2_dir/runbook.md" 2>/dev/null
if cmp -s "$REPO_ROOT/$RUNBOOK_REL" "$h2_dir/runbook.md"; then
  fail "H2 control: the volume-id mutation changed nothing (vacuous row)"
elif [ "$(readback_parity "$REPO_ROOT/$SKILL_REL" "$h2_dir/runbook.md")" = 0 ]; then
  pass
else
  fail "H2 control: a runbook read-back with a different volume id was judged byte-identical (H2 is blind)"
fi
drop_tree "$h2_dir"
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
R11C_BODY='  resource "doppler_secret" "inngest_redis_luks_key_indented" {
    project = doppler_project.inngest.name
    config  = doppler_environment.inngest_prd.slug
    name    = "INNGEST_REDIS_LUKS_KEY"
    value   = "synthetic-not-a-secret"
  }'
assert_plant_red "R11c an INDENTED second writer (a header with leading whitespace is still a resource)" KEY_WRITER_COUNT sibling_writer.tf "$R11C_BODY"
R11D_BODY='resource "doppler_secret" "inngest_redis_luks_key_hidden" {
  project = doppler_project.inngest.name
  config  = doppler_environment.inngest_prd.slug
  name    = "INNGEST_REDIS_LUKS_KEY"
  value   = '"${LT2}"'-EOT
  project = "elsewhere"
  EOT
}'
assert_plant_red "R11d a second writer whose heredoc value holds a fake project = \"elsewhere\" line (not code)" KEY_WRITER_COUNT sibling_writer.tf "$R11D_BODY"
R11E_BODY='resource "doppler_secret" "inngest_redis_luks_key_second" {
  project = "${local.proj}"
  config  = "prd"
  name    = "INNGEST_REDIS_LUKS_KEY"
  value   = "synthetic-not-a-secret"
}'
assert_plant_red "R11e a second writer whose project is a quoted but TEMPLATED string (not provably elsewhere)" KEY_WRITER_COUNT sibling_writer.tf "$R11E_BODY"
# R14 a doppler_secret on the inngest project whose name the census cannot read. The count is then 1
# (the real writer) so ONLY the non-literal-name check can see it.
R14A_BODY='resource "doppler_secret" "indirect" {
  project = doppler_project.inngest.name
  config  = doppler_environment.inngest_prd.slug
  name    = local.k
  value   = "synthetic-not-a-secret"
}'
assert_plant_red "R14a name = local.k on soleur-inngest/prd" SEC_NAME_NOT_LITERAL sibling_indirect.tf "$R14A_BODY"
R14B_BODY='resource "doppler_secret" "indirect" {
  project = "soleur-inngest"
  config  = "prd"
  name    = upper("inngest_redis_luks_key")
  value   = "synthetic-not-a-secret"
}'
assert_plant_red "R14b name = upper(...) on the literal soleur-inngest/prd" SEC_NAME_NOT_LITERAL sibling_indirect.tf "$R14B_BODY"
R14C_BODY='resource "doppler_secret" "fan" {
  for_each = toset(["INNGEST_REDIS_LUKS_KEY"])
  project  = doppler_project.inngest.name
  config   = doppler_environment.inngest_prd.slug
  name     = each.key
  value    = "synthetic-not-a-secret"
}'
assert_plant_red "R14c for_each with name = each.key on soleur-inngest/prd" SEC_NAME_NOT_LITERAL sibling_indirect.tf "$R14C_BODY"
R14D_BODY='resource "doppler_secret" "opaque" {
  project = local.p
  config  = local.c
  name    = local.k
  value   = "synthetic-not-a-secret"
}'
assert_plant_red "R14d project, config AND name all locals (opaque: nothing proves it is elsewhere)" SEC_NAME_NOT_LITERAL sibling_indirect.tf "$R14D_BODY"
R14E_BODY='resource "doppler_secret" "templated" {
  project = "soleur-inngest"
  config  = "prd"
  name    = "${local.pfx}_REDIS_LUKS_KEY"
  value   = "synthetic-not-a-secret"
}'
assert_plant_red "R14e a quoted but TEMPLATED name on the literal soleur-inngest/prd" SEC_NAME_NOT_LITERAL sibling_indirect.tf "$R14E_BODY"
R14F_BODY='resource "doppler_secret" "config_only" {
  project = local.p
  config  = doppler_environment.inngest_prd.slug
  name    = local.k
  value   = "synthetic-not-a-secret"
}'
assert_plant_red "R14f project a local, config the inngest_prd reference, name a local" SEC_NAME_NOT_LITERAL sibling_indirect.tf "$R14F_BODY"
R14G_BODY='  resource "doppler_secret" "indented_indirect" {
    project = doppler_project.inngest.name
    config  = doppler_environment.inngest_prd.slug
    name    = local.k
    value   = "synthetic-not-a-secret"
  }'
assert_plant_red "R14g an INDENTED doppler_secret header with name = local.k on the inngest project" SEC_NAME_NOT_LITERAL sibling_indirect.tf "$R14G_BODY"
R14H_BODY='resource "doppler_secret" "templated_project" {
  project = "${local.proj}"
  config  = "${local.cfg}"
  name    = local.k
  value   = "synthetic-not-a-secret"
}'
assert_plant_red "R14h a non-literal name where project and config are quoted but TEMPLATED strings (not provably elsewhere)" SEC_NAME_NOT_LITERAL sibling_indirect.tf "$R14H_BODY"

# R12 the extractor returns empty for an address (renamed resource): zero attributes would be checked
assert_mut_red "R12a volume renamed: the extractor finds nothing" "EXTRACT:hcloud_volume.inngest_redis_luks" "$LUKS_TF" $VOL_T $VOL_N \
  's/^resource "hcloud_volume" "inngest_redis_luks"/resource "hcloud_volume" "gone"/'
assert_mut_red "R12b attachment renamed: the extractor finds nothing" "EXTRACT:hcloud_volume_attachment.inngest_redis_luks" "$LUKS_TF" hcloud_volume_attachment inngest_redis_luks \
  's/^resource "hcloud_volume_attachment" "inngest_redis_luks"/resource "hcloud_volume_attachment" "gone"/'
# R13 a trailing comment holding a heredoc opener must NOT start a heredoc: if it did, the text after it
# would be read as literal body, and a /* */-wrapped protection (or a block-commented attribute) would
# still look like code. The opener comes from LT2 (defined above), so this file's own source holds no heredoc
# opener.
R13A_SED="s~^([[:space:]]+location[[:space:]]*=.*)\$~\\1 # see ${LT2}EOF~;${R3_ML}"
assert_mut_red "R13a trailing # comment with a heredoc opener, then the volume lifecycle wrapped in /* */" VOL_PREVENT_DESTROY "$LUKS_TF" $VOL_T $VOL_N "$R13A_SED"
R13B_SED="s~^([[:space:]]+location[[:space:]]*=.*)\$~\\1 // see ${LT2}-EOT~;s~^([[:space:]]+)delete_protection[[:space:]]*=.*\$~\\1/*\\n\\1delete_protection = true\\n\\1*/~"
assert_mut_red "R13b trailing // comment with a -heredoc opener, then delete_protection block-commented out" VOL_DELETE_PROTECTION "$LUKS_TF" $VOL_T $VOL_N "$R13B_SED"
# R15 a meta-argument on each of the six blocks (every attribute at least once, every block once)
META_HDR='s/^(resource .*\{)$/\1\n'
assert_mut_red "R15a count = 1 on the volume" META_ARGS "$LUKS_TF" $VOL_T $VOL_N "${META_HDR}  count = 1/"
assert_mut_red "R15b for_each on the random_password" META_ARGS "$LUKS_TF" random_password inngest_redis_luks "${META_HDR}  for_each = toset([\"a\"])/"
assert_mut_red "R15c provider alias on the attachment" META_ARGS "$LUKS_TF" hcloud_volume_attachment inngest_redis_luks "${META_HDR}  provider = hcloud.alt/"
assert_mut_red "R15d a provisioner block on the doppler_secret" META_ARGS "$LUKS_TF" doppler_secret inngest_redis_luks_key "${META_HDR}  provisioner \"local-exec\" {\\n    command = \"true\"\\n  }/"
assert_mut_red "R15e count = 0 on doppler_project.inngest" META_ARGS "$HOST_TF" doppler_project inngest "${META_HDR}  count = 0/"
assert_mut_red "R15f for_each on doppler_environment.inngest_prd" META_ARGS "$HOST_TF" doppler_environment inngest_prd "${META_HDR}  for_each = {}/"
# R16 a second, unpinned way to lift the volume's delete protection. The only real file that names the token is
# workspaces-luks.tf (comments only), so a planted file named aa_* sorts BEFORE it and zz_* AFTER it: a scan
# that stops after the first candidate file, or looks only at the last, would each miss one of the two orders.
R16A_BODY='resource "terraform_data" "lift" {
  provisioner "local-exec" {
    command = "curl -sS -X POST https://api.hetzner.cloud/v1/volumes/1/actions/change_protection -d {}"
  }
}'
assert_plant_red "R16a a local-exec that calls the change_protection action" CHANGE_PROTECTION aa_lift.tf "$R16A_BODY"
R16B_BODY='data "http" "lift" {
  url    = "https://api.hetzner.cloud/v1/volumes/1/actions/change_protection"
  method = "POST"
}'
assert_plant_red "R16b an http data source that calls the change_protection action" CHANGE_PROTECTION aa_lift.tf "$R16B_BODY"
R16C_BODY='resource "terraform_data" "lift" {
  input = "echo # innocent; curl https://api.hetzner.cloud/v1/volumes/1/actions/change_protection"
}'
assert_plant_red "R16c the token after a # INSIDE a string is still seen (no comment-stripping of strings)" CHANGE_PROTECTION aa_lift.tf "$R16C_BODY"
R16D_BODY='resource "terraform_data" "lift" {
  provisioner "local-exec" {
    command = "hcloud volume disable-protection ${hcloud_volume.inngest_redis_luks.id} delete"
  }
}'
assert_plant_red "R16d the hcloud CLI spelling: local-exec hcloud volume disable-protection" CHANGE_PROTECTION aa_lift.tf "$R16D_BODY"
assert_plant_red "R16e the change_protection action in a file that sorts AFTER the real candidate" CHANGE_PROTECTION zz_lift.tf "$R16A_BODY"
assert_plant_red "R16f the hcloud CLI spelling in a file that sorts AFTER the real candidate" CHANGE_PROTECTION zz_lift.tf "$R16D_BODY"

# R17 a `{` in a TRAILING comment must not move the brace depth. The two steps span two blocks: the password
# block gets `# {` on `length = 40` and its prevent_destroy swapped for another lifecycle attribute, and the
# doppler_secret block after it closes with `} # }`. A depth counter that reads the comments runs the password
# block into the secret block and lets the secret's prevent_destroy stand in for the password's. The control
# keeps the real prevent_destroy: same two comment edits, must be GREEN.
R17_PW_BRACE='s/^([[:space:]]+length[[:space:]]*=[[:space:]]*40.*)$/\1 # {/'
R17_PW_SWAP='s/^([[:space:]]+)prevent_destroy[[:space:]]*=.*$/\1create_before_destroy = true/'
R17_SEC_CLOSE='s/^\}$/} # }/'
assert_chain_red "R17 a { in a trailing comment on the password plus } # } on the secret, password prevent_destroy swapped out" PW_PREVENT_DESTROY "$LUKS_TF" random_password inngest_redis_luks "${R17_PW_BRACE};${R17_PW_SWAP}" doppler_secret inngest_redis_luks_key "$R17_SEC_CLOSE"
assert_chain_green "R17 control: the same two comment edits with the real prevent_destroy kept" "$LUKS_TF" random_password inngest_redis_luks "$R17_PW_BRACE" doppler_secret inngest_redis_luks_key "$R17_SEC_CLOSE"
# R18 a fake `lifecycle { prevent_destroy = true }` inside a HEREDOC is literal text, never code. The volume
# keeps no real prevent_destroy; the only one is in the heredoc. The control keeps the real one (the heredoc
# is then harmless text and must not read as a second assignment).
R18_HEREDOC="s~^([[:space:]]+location[[:space:]]*=.*)\$~\\1\\n  note = ${LT2}-EOT\\n  lifecycle {\\n    prevent_destroy = true\\n  }\\n  EOT~"
R18_DROP='s/^[[:space:]]+prevent_destroy[[:space:]]*=.*$//'
assert_mut_red "R18a a fake lifecycle { prevent_destroy = true } in a heredoc, the real prevent_destroy dropped" VOL_PREVENT_DESTROY "$LUKS_TF" $VOL_T $VOL_N "${R18_DROP};${R18_HEREDOC}"
R18B_HEREDOC="s~^([[:space:]]+location[[:space:]]*=.*)\$~\\1\\n  note = ${LT2}-EOT\\n  delete_protection = true\\n  EOT~"
assert_mut_red "R18b a fake delete_protection = true in a heredoc, the real one flipped to false" VOL_DELETE_PROTECTION "$LUKS_TF" $VOL_T $VOL_N \
  "s/^([[:space:]]+delete_protection[[:space:]]*=[[:space:]]*)true/\\1false/;${R18B_HEREDOC}"
assert_mut_green "R18 control: the heredoc holding a fake lifecycle block, the real prevent_destroy kept" "$LUKS_TF" $VOL_T $VOL_N "$R18_HEREDOC"

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
# P7 a REAL heredoc: its body holds comment-looking lines (a /* that must NOT open a comment, a # line).
# The lifecycle block after it must stay visible, or a lexer that mishandles heredocs is hiding code.
assert_mut_green "P7 a real heredoc with a /* and a # line in its body before the guarded lines" "$LUKS_TF" $VOL_T $VOL_N \
  "s~^([[:space:]]+location[[:space:]]*=.*)\$~\\1\\n  note = ${LT2}-EOT\\n  /* literal text, not a comment opener\\n  # also literal\\n  EOT~"
# P8 a non-literal name is fine on a project that is provably not the inngest one
P8_BODY='resource "doppler_secret" "elsewhere_indirect" {
  project = "soleur"
  config  = "prd"
  name    = local.k
  value   = "synthetic-not-a-secret"
}'
assert_plant_green "P8 a non-literal secret name on a provably different Doppler project" other_project_indirect.tf "$P8_BODY"
# P9 comments may discuss change_protection
P9_BODY='# a whole-line comment about change_protection
/* a block comment about
   change_protection */
resource "terraform_data" "note" {
  input = "x"
}'
assert_plant_green "P9 whole-line and block comments that mention change_protection" comment_only.tf "$P9_BODY"
# P10 count / provider as NESTED attributes (a labels map key) are ordinary attributes, not meta-arguments: a
# scan of the whole block instead of depth 1 would call this RED.
assert_mut_green "P10 count and provider as keys of the nested labels map on the volume (depth 2, not meta-arguments)" "$LUKS_TF" $VOL_T $VOL_N \
  's/^([[:space:]]+)(app[[:space:]]*=.*)$/\1\2\n\1count = "1"\n\1provider = "hetzner"/'
# P11/P12 the `elsewhere` rule needs only ONE of project / config to be a provable string literal: a non-literal
# name is fine when only the config (or only the project) proves the secret is not the inngest prd one.
P11_BODY='resource "doppler_secret" "other_config" {
  project = local.p
  config  = "dev"
  name    = local.k
  value   = "synthetic-not-a-secret"
}'
assert_plant_green "P11 a non-literal name where only the CONFIG is a provably different string literal" other_config_indirect.tf "$P11_BODY"
P12_BODY='resource "doppler_secret" "other_project" {
  project = "soleur"
  config  = doppler_environment.inngest_prd.slug
  name    = local.k
  value   = "synthetic-not-a-secret"
}'
assert_plant_green "P12 a non-literal name where only the PROJECT is a provably different string literal" other_project_ref_config.tf "$P12_BODY"

# --- Negative controls (N1-N3) -------------------------------------------------------------------
negctl_rows
# N4: the block RANGE `confined` is built on counts braces on code only. A copy of the volume block that gains
# a `{` in a trailing comment, a `{` in a string and a heredoc whose body holds two stray `}` lines (five added
# lines in all) must report the pristine range with its end moved by exactly those five lines.
cases=$((cases + 1))
n4_dir="$(mktemp -d "$SUITE_TMP/n4.XXXXXX")" || { printf 'FATAL: mktemp -d failed\n' >&2; exit 2; }
assert_fixture_dir "$n4_dir"
n4_base="$(_b4_block_range "$PRISTINE/$LUKS_TF" $VOL_T $VOL_N)"
sed -E "/^resource \"${VOL_T}\" \"${VOL_N}\" \{/,/^\}/ s~^([[:space:]]+location[[:space:]]*=.*)\$~\\1 # {\\n  note = \"{\"\\n  txt = ${LT2}-EOT\\n  }\\n  }\\n  EOT~" "$PRISTINE/$LUKS_TF" > "$n4_dir/$LUKS_TF"
n4_got="$(_b4_block_range "$n4_dir/$LUKS_TF" $VOL_T $VOL_N)"
n4_want="${n4_base% *} $(( ${n4_base#* } + 5 ))"
if cmp -s "$PRISTINE/$LUKS_TF" "$n4_dir/$LUKS_TF"; then
  fail "N4: the brace-decoy edit changed nothing (vacuous row)"
elif [ -n "$n4_base" ] && [ "$n4_got" = "$n4_want" ]; then
  pass
else
  fail "N4: _b4_block_range counted braces that are comment, string or heredoc text (got [$n4_got], want [$n4_want])"
fi
drop_tree "$n4_dir"

# --- Harness rows: neutering the shared lexer, a verdict helper, or the accounting must redden THIS suite
# Run a copy of this suite on a scratch tree that has the same layout (apps/web-platform/infra,
# tests/scripts/lib) with a NEUTERED copy of the lexer (a function override appended to the lib) and/or a
# NEUTERED suite (a sed over the copy). Nested runs execute a subset selected by `--nested <mode>` and must
# exit 1 (a verdict, never a crash) with the named text in the output. Both mutations are asserted to have
# LANDED (the copy differs from the original), or the row fails as vacuous.
nested_case() { # <name> <mode> <lib-override|-> <suite-sed|-> <expected-output-substring>
  local name="$1" mode="$2" override="$3" ssed="$4" expect="$5" root out rc=0 suite
  cases=$((cases + 1))
  root="$(mktemp -d "$SUITE_TMP/nest.XXXXXX")" || { printf 'FATAL: mktemp -d failed\n' >&2; exit 2; }
  assert_fixture_dir "$root"
  mkdir -p "$root/apps/web-platform/infra" "$root/tests/scripts/lib" || { printf 'FATAL: mkdir failed\n' >&2; exit 2; }
  cp "$PRISTINE"/*.tf "$root/apps/web-platform/infra/" || { printf 'FATAL: cp failed\n' >&2; exit 2; }
  suite="$root/apps/web-platform/infra/inngest-luks-sole-copy.test.sh"
  cp "${BASH_SOURCE[0]}" "$suite" || { printf 'FATAL: cp failed\n' >&2; exit 2; }
  cp "$HCL_LIB" "$root/tests/scripts/lib/hcl-effective-text.sh" || { printf 'FATAL: cp failed\n' >&2; exit 2; }
  [ "$override" = "-" ] || printf '\n%s\n' "$override" >> "$root/tests/scripts/lib/hcl-effective-text.sh"
  if [ "$ssed" != "-" ]; then
    sed "$ssed" "${BASH_SOURCE[0]}" > "$suite"
    if cmp -s "${BASH_SOURCE[0]}" "$suite"; then
      fail "$name: the suite mutation changed nothing (vacuous row)"; rm -rf "$root"; return
    fi
  fi
  out="$(bash "$suite" --nested "$mode" 2>&1)"
  rc=$?
  if [ "$rc" -eq 1 ] && grep -Fq "$expect" <<<"$out"; then
    pass
  else
    fail "$name: the neutered copy did not redden as expected (rc=$rc, wanted rc=1 with output containing [$expect])"
  fi
  rm -rf "$root"
}
nested_case "HX1 strip_comments neutered to the identity function" r3 'strip_comments() { cat "$1"; }' - "R3 volume lifecycle wrapped in a multi-line"
nested_case "HX2 block extraction neutered to empty" r3 'block_of() { :; }' - "H0 control: the unmutated root holds every pin"
# The verdict helpers (BRE seds: `(` `)` `{` are literal there; the original body is kept under another name).
nested_case "HX3 has_viol neutered to always-true" negctl - 's/^has_viol() {/has_viol() { return 0; }\n_has_viol_orig() {/' "N1 a wrong expected violation code"
nested_case "HX4 confined neutered to always-true" negctl - 's/^confined() {/confined() { return 0; }\n_confined_orig() {/' "N3 confined()"
nested_case "HX5 the apply_block_sed landing check neutered to if-false" negctl - 's/if cmp -s "\$base" "\$tree\/\$file"; then/if false; then/' "N2 a no-op sed"
# The accounting (finish): one `cases` increment dropped must trip the identity; no rows must trip the floor.
nested_case "HX6 a dropped cases increment trips the pass+fail != cases identity" acct - '/^assert_green_tree() {/,/^}/ s/cases=\$((cases + 1))/:/' "accounting identity"
nested_case "HX7 a run with almost no rows trips the MIN_CASES floor" floor - - "anti-vacuity floor"

finish
