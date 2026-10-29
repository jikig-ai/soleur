#!/usr/bin/env bash
#
# Family-wide STRUCTURAL guard for every Better Stack Logs alert declared in this root (#11388).
#
# THE GAP IT CLOSES. Each per-alert drift guard under apps/web-platform/test/infra/*alert*.test.sh pins ONE
# alert's SQL and parameters by NAME. None of them asks what the declared set LOOKS LIKE as a whole, so a
# change that adds an alert, hides one behind a Terraform construct, or attaches a second alert to an
# existing exploration passes every named guard (the key-probe census even required the stem
# `inngest_luks_key_probe_`, so `inngest_luks_key_probe2_fail` escaped it). This suite derives the set each
# run and holds EVERY member to one shape. Members drift; the set is never named.
#
# WHAT IT ASSERTS, over every `resource "logtail_exploration"` and `resource "logtail_exploration_alert"`
# in EVERY *.tf of the infra root (presence rows 1-24 below, each one verdict over the whole set):
#   1-4   census: at least 19 alerts and 19 explorations, every enumerated header yields a block (a header
#         `block_of` cannot extract would otherwise be invisible to every row after it; an UNQUOTED label
#         is enumerated and then reds here, never skipped) AND no other code line of any root *.tf names a
#         logtail_exploration except an enumerated header or a `logtail_exploration*.<n>.id` reference (a header
#         the enumerator's sed cannot see, `resource"logtail_exploration_alert" "x" {`, reds as un-enumerated),
#         and at least 15 alert guards under apps/web-platform/test/infra. Rows 1-4 are all `--census-only` runs.
#   5-7   closed attribute set: top-level keys of each alert equal REQUIRED_ATTRS + OPTIONAL_ATTRS, plus
#         exactly one `escalation_target` block. No family-wide attribute VALUE pins: the per-alert guards
#         own `push`, `call`, the windows and the SQL.
#   8     no `lifecycle`, `count`, `for_each`, `provider`, `depends_on`, `dynamic`, `provisioner` or
#         `connection` anywhere in an alert OR an exploration block
#   9-10  one alert per exploration, and the alert's resource name equals the exploration it binds
#   11    no `removed`, `moved` or `import` block names a logtail_exploration* address
#   12    no `*override.tf`, `*override.tf.json` or `*.tf.json` in the root
#   13    no symlink anywhere under the infra root (a `zz.tf -> elsewhere` is loaded by Terraform and read by
#         no row here); find's own exit status is read, and only the root's own `.terraform` is skipped
#   14    no `logtail_*` resource declared in a `.tf` OUTSIDE the root's own `*.tf` (a subdirectory or module
#         file is invisible to the root enumeration and to every guard) and no root `module` block whose
#         `source` is not `./<subdir>...` (a remote or `..` source loads .tf no row here can read)
#   15-17 provider tripwire: the lock's `logtail` constraint equals main.tf's literal, the lock version
#         equals PROVIDER_LOCK_VERSION below, and main.tf's `source` equals PROVIDER_SOURCE (a tripwire, NOT
#         an integrity proof)
#   18-19 CI pin: every apps/web-platform/test/infra/*alert*.test.sh is a plain `bash <path>` step in
#         infra-validation.yml whose step keys are exactly {name, run} (an allow-list: any other key, `if:`,
#         `continue-on-error:`, `env:`, `shell:` ... reds), and the WHOLE job block (job-level keys after
#         `steps:` included) is an allow-list too (runs-on, needs, if == JOB_IF_ALLOWED, permissions,
#         timeout-minutes, steps, strategy, name) with no `defaults:`, no `GUARD_*` (bare or prefixed) /
#         `ALERT_STRUCT_*` / BASH_ENV / SHELLOPTS / BASHOPTS / ENV env and no $GITHUB_ENV / $GITHUB_PATH write;
#         workflow level refuses `defaults:` and the same env names. Line-based awk, no PyYAML. This is the
#         suite's second chokepoint (the first is logtail_blocks / block_text).
#   20    no non-comment line of ANY workflow under .github/workflows or of scripts/test-all.sh names
#         `ALERT_STRUCT_` (those variables redirect this suite at another tree). An override run prints
#         `graded tree: <infra root>` first.
#   21-22 apply parity, scoped to `logtail_*` ONLY: every enumerated logtail resource has a
#         `-target=<addr>` argument in apply-web-platform-infra.yml (echo/printf lines and comments, whole-line or
#         trailing, do not count), and every `-target=logtail_*` there is an
#         enumerated resource. The equality of the WHOLE -target set is deliberately not asserted, and this
#         suite only READS the workflow.
#   23-24 predicate controls: synthetic blocks prove the meta-argument and attribute-set predicates pass a
#         comment and a heredoc that merely NAME the forbidden words and fail a real one.
#
# ONE CHOKEPOINT. Every row reads through tests/scripts/lib/hcl-effective-text.sh: strip_comments (all three
# comment forms, line-count-preserving) -> blank_heredocs (heredoc bodies are literal text, never code) ->
# block_of (brace depth, never an awk range). `block_of` prints heredoc bodies unchanged, so each block is
# piped through blank_heredocs a second time; that is what makes a `sql_query` heredoc invisible to the
# meta-argument rows. No row re-greps raw text.
#
# ACCEPTED LIMIT (the anchor). REQUIRED_ATTRS, the census floors and the provider constants live in this
# file, in the same diff as what they protect, so a deliberate in-diff edit of a pin passes: the suite
# proves consistency, not integrity. The external anchor is review (CODEOWNERS row `/apps/web-platform/infra/`
# covers this file). It also proves TEXT, not live Better Stack state. THIS FILE'S OWN WIRING: it lives in
# apps/web-platform/infra/, so it is registered by the glob in run-registered-suites.sh, and
# .github/scripts/test/test-infra-suite-registration.sh Arms 1 and 2 pin that the runner step runs, sharded
# and unmasked. Arm 3b of that gate covers apps/web-platform/test/infra/*.test.sh only and does NOT reach
# this file. The CI-pin rows above cover the per-alert guards, not this file.
#
# MUTATION BATTERY (bottom of file, rows M-*). Each row copies the tree into a scratch dir under $TMPDIR,
# mutates the COPY, re-runs this suite against it through ALERT_STRUCT_{INFRA,WF,APPLY_WF,GUARDS} (or, for the
# harness rows that edit the suite or the lexer itself, through a scratch repo skeleton), and requires rc=1 plus
# the row's own FAIL text. rc>=2 is the instrument, not evidence. Tracked files are never written; a checksum of
# the real infra root and both workflows is compared at exit (git diff is not used: a dirty worktree must not
# fail it). Inner runs are ~10-12 s each (header enumeration, then one lexer pass per block) and run in parallel;
# no row depends on wall-clock time.
#
# Usage: bash apps/web-platform/infra/betterstack-alert-structure.test.sh [--presence-only | --census-only]
#   --presence-only skips the mutation battery (the inner runs use it).
#   --census-only runs ONLY enumeration + the census floors (rows 1-4, a few seconds) and prints a final
#   `N passed, 0 failed` line; it exits 1 when fewer than 19 alerts are enumerated. This is the cheap
#   discoverability probe; --presence-only measured 12-19 s on a loaded host.
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

PRESENCE_ONLY=""; CENSUS_ONLY=""
for _a in "$@"; do
  case "$_a" in
    --presence-only) PRESENCE_ONLY=1 ;;
    --census-only) CENSUS_ONLY=1; PRESENCE_ONLY=1 ;;
    *) printf 'FATAL: unknown argument %s (only --presence-only | --census-only)\n' "$_a" >&2; exit 2 ;;
  esac
done

# ── pins (same file, same diff as what they protect: tripwires, see the header) ────────────────────
REQUIRED_ATTRS="alert_type call check_period confirmation_period critical_alert email exploration_id incident_cause metadata name on_missing_data operator paused push query_period recovery_period sms value"
OPTIONAL_ATTRS=""
CENSUS_FLOOR_ALERTS=19
CENSUS_FLOOR_EXPLORATIONS=19
GUARD_CENSUS_FLOOR=15
PROVIDER_LOCK_VERSION="11.2.0"
PROVIDER_SOURCE="BetterStackHQ/logtail"
JOB_IF_ALLOWED="needs.detect-changes.outputs.pr_duplicate != 'true'"
META_RE='(^|\{)[[:space:]]*(lifecycle|count|for_each|provider|depends_on|dynamic|provisioner|connection)[[:space:]]*(=|\{|")'

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SELF="$DIR/$(basename "${BASH_SOURCE[0]}")"
REPO="$(cd "$DIR/../../.." && pwd)"

# Overrides exist for the mutation battery. An override that is SET but EMPTY would silently fall back to the
# real tree and grade it as "mutated", so it is refused outright.
for _v in ALERT_STRUCT_INFRA ALERT_STRUCT_WF ALERT_STRUCT_APPLY_WF ALERT_STRUCT_GUARDS; do
  if [ "${!_v+set}" = set ] && [ -z "${!_v}" ]; then
    printf 'FATAL: %s is set but EMPTY; refusing (it would fall back to the real tree)\n' "$_v" >&2; exit 2
  fi
done
INFRA="${ALERT_STRUCT_INFRA:-$DIR}"
WF="${ALERT_STRUCT_WF:-$REPO/.github/workflows/infra-validation.yml}"
APPLY_WF="${ALERT_STRUCT_APPLY_WF:-$REPO/.github/workflows/apply-web-platform-infra.yml}"
GUARDS="${ALERT_STRUCT_GUARDS:-$REPO/apps/web-platform/test/infra}"
HCL_LIB="$REPO/tests/scripts/lib/hcl-effective-text.sh"
# An override redirects the graded tree: say so on every run, so a log never reads as a verdict on the real root.
for _v in ALERT_STRUCT_INFRA ALERT_STRUCT_WF ALERT_STRUCT_APPLY_WF ALERT_STRUCT_GUARDS; do
  if [ -n "${!_v:-}" ]; then printf 'graded tree: %s (workflow %s, apply workflow %s, guards %s)\n' "$INFRA" "$WF" "$APPLY_WF" "$GUARDS"; break; fi
done

pass=0; fail=0; FAILED=()
ok() { pass=$((pass + 1)); printf '[ok] %s\n' "$1"; }
no() { fail=$((fail + 1)); FAILED+=("$1"); printf '[FAIL] %s\n' "$1"; }

# P1b (#7708) - byte-identical to every other tracked copy; the P1a suite pins that.
# `$(cd X && pwd)` prints an absolute path but yields EMPTY when the cd fails. Every path this
# file READS is checked through it; the scratch dir every mutation WRITES to is checked too.
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
assert_fixture_dir "$REPO"; assert_fixture_dir "$INFRA"; assert_fixture_dir "$WF"; assert_fixture_dir "$APPLY_WF"; assert_fixture_dir "$GUARDS"
assert_fixture_dir "$HCL_LIB"

# INSTRUMENT SELF-TEST - both helpers must move their own counter before any verdict is trusted.
_p0=$pass; _f0=$fail
{ ok "self-test"; no "self-test"; } >/dev/null
if [ "$pass" -ne $((_p0 + 1)) ] || [ "$fail" -ne $((_f0 + 1)) ] || [ "${#FAILED[@]}" -ne 1 ]; then
  printf '[FATAL] instrument self-test: ok()/no() did not each move their counter\n' >&2; exit 2
fi
pass=$_p0; fail=$_f0; FAILED=()

[ -f "$HCL_LIB" ] || { printf 'FATAL: shared HCL lexer not found at %s\n' "$HCL_LIB" >&2; exit 2; }
# shellcheck source=../../../tests/scripts/lib/hcl-effective-text.sh
. "$HCL_LIB" || { printf 'FATAL: could not source %s\n' "$HCL_LIB" >&2; exit 2; }
[ -d "$INFRA" ] && [ -d "$GUARDS" ] && [ -r "$WF" ] && [ -r "$APPLY_WF" ] \
  || { printf 'FATAL: unreadable input (infra %s, guards %s, workflow %s, apply workflow %s)\n' "$INFRA" "$GUARDS" "$WF" "$APPLY_WF" >&2; exit 2; }

WORK="$(mktemp -d -t alertstruct.XXXXXX)" || { printf '[FATAL] mktemp failed\n' >&2; exit 2; }
assert_fixture_dir "$WORK"
trap 'rm -rf "$WORK"' EXIT

# fail_line_has <log> <fragment>: true when some `[FAIL]` line of <log> contains <fragment>. NO early-exit reader behind a
# pipe: `grep -F '[FAIL]' log | grep -qF tag` lets the second grep exit on its first hit, the first grep then dies of
# SIGPIPE on any log larger than the pipe buffer, and pipefail reports 141 = "not found" (a false-negative that reddened
# a correct mutation row about 1 run in 6 under 6-way load). The second grep here reads to EOF and its output is discarded.
fail_line_has() { grep -F '[FAIL]' "$1" | grep -F -- "$2" >/dev/null; }

# ── the chokepoint ─────────────────────────────────────────────────────────────────────────────────
# logtail_blocks prints `file|type|name` for every logtail_exploration(_alert) header in every *.tf of the
# root, read from the comment- and heredoc-blind view. A header with leading whitespace is still a header
# (HCL ignores indentation) and so is one with UNQUOTED labels (`resource logtail_exploration_alert x {` is
# valid HCL2); block_text then cannot extract either and presence row 3 reds it.
logtail_blocks() {
  local f
  for f in "$INFRA"/*.tf; do
    [ -e "$f" ] || continue
    strip_comments "$f" | blank_heredocs \
      | sed -nE 's/^[[:space:]]*resource[[:space:]]+"?(logtail_exploration(_alert)?)"?[[:space:]]+"?([^" {]+)"?.*/\1|\3/p' \
      | while IFS='|' read -r t n; do printf '%s|%s|%s\n' "$f" "$t" "$n"; done
  done
}
# FAIL-CLOSED CROSS-CHECK for the enumerator above (#11483 review). logtail_blocks only sees a header its sed
# recognises; `resource"logtail_exploration_alert" "x" {` (no space after `resource`) is valid HCL and invisible to
# it. Every code line (comments, heredoc bodies and trailing comments dropped) of every root *.tf that names
# logtail_exploration must therefore be an ENUMERATED header (the SAME prefix as the sed) or a
# `logtail_exploration*.<n>.id` reference; anything else is printed as `file:line`.
logtail_strays() {
  local f
  for f in "$INFRA"/*.tf; do
    [ -e "$f" ] || continue
    strip_comments "$f" | blank_heredocs | sed -E 's/[[:space:]]*(#|\/\/).*$//' | grep -nF 'logtail_exploration' \
      | grep -vE '^[0-9]+:[[:space:]]*resource[[:space:]]+"?logtail_exploration(_alert)?"?[[:space:]]+"?[^" {]+' \
      | grep -vE '^[0-9]+:[[:space:]]*exploration_id[[:space:]]*=[[:space:]]*logtail_exploration\.[A-Za-z0-9_-]+\.id[[:space:]]*$' \
      | sed "s|^|$(basename "$f"):|"
  done
}
# One block, code-only: brace-depth extraction, then heredoc bodies blanked.
block_text() { block_of "$1" "$2" "$3" | blank_heredocs; }

# depth-1 lines of a block (the block header is depth 0), strings emptied and trailing comments cut
top_lines() {
  awk "$HCL_AWK_FUNCS"'{ c = cv($0); if (d == 1) print c; o = gsub(/\{/, "{", c); x = gsub(/\}/, "}", c); d += o - x }'
}
# top-level keys: `<attr>` for an attribute, `block:<type>` for a nested block
top_keys() {
  top_lines | sed -nE \
    -e 's/^[[:space:]]*([A-Za-z_][A-Za-z0-9_-]*)[[:space:]]*=.*/\1/p' -e 't' \
    -e 's/^[[:space:]]*([A-Za-z_][A-Za-z0-9_-]*)([[:space:]]+"")*[[:space:]]*\{.*/block:\1/p'
}
allowed_keys() { { printf '%s\n' $REQUIRED_ATTRS $OPTIONAL_ATTRS; echo "block:escalation_target"; } | sort -u; }
# problems of ONE alert block (text in $1), one predicate per function so each presence row has its own verdict
unknown_keys_of() {  # unknown or duplicated keys
  local keys; keys="$(top_keys <<<"$1")"
  { grep -vxFf <(allowed_keys) <<<"$keys"; sort <<<"$keys" | uniq -d | sed 's/^/dup:/'; } | grep -v '^$' | tr '\n' ' '
}
missing_keys_of() {
  local keys r out=""; keys="$(top_keys <<<"$1")"
  for r in $REQUIRED_ATTRS; do grep -qxF "$r" <<<"$keys" || out="$out$r "; done
  printf '%s' "$out"
}
escalation_count_of() { top_keys <<<"$1" | grep -cxF 'block:escalation_target'; }
meta_hits_of() { awk "$HCL_AWK_FUNCS"'{ print cv($0) }' <<<"$1" | grep -E "$META_RE" | sed -n -e 's/^[[:space:]]*//' -e '1,3p' | tr '\n' ' '; }
# exploration names an alert binds (depth-1 `exploration_id = logtail_exploration.<n>.id`), one per line
bound_exploration_of() {
  top_lines <<<"$1" | grep -E '^[[:space:]]*exploration_id[[:space:]]*=' \
    | sed -nE 's/^[[:space:]]*exploration_id[[:space:]]*=[[:space:]]*logtail_exploration\.([A-Za-z0-9_-]+)\.id[[:space:]]*$/\1/p'
}
exploration_id_lines_of() { top_lines <<<"$1" | grep -cE '^[[:space:]]*exploration_id[[:space:]]*='; }

# `removed` / `moved` / `import` blocks (single header matcher, brace depth) that name a logtail_exploration*
# address. Prints one line per offending block. The block text is the code-only view.
surgery_in() {
  strip_comments "$1" | blank_heredocs | awk "$HCL_AWK_FUNCS"'
    !inb && $0 ~ /^[[:space:]]*(removed|moved|import)[[:space:]]*\{/ { inb = 1; d = 0; txt = "" }
    inb {
      c = cv($0); txt = txt " " c
      o = gsub(/\{/, "{", c); x = gsub(/\}/, "}", c); d += o - x
      if (d <= 0) { if (txt ~ /logtail_exploration/) print "hit"; inb = 0 }
    }'
}

# `module` blocks of ONE file (comment- and heredoc-blind): prints each block's depth-1 `source` literal, or `-` when
# the block has none. A single-line `module "x" { source = "..." }` has no depth-1 line and reads as `-` (fail closed).
module_sources_in() {
  strip_comments "$1" | blank_heredocs | awk "$HCL_AWK_FUNCS"'
    !inb && $0 ~ /^[[:space:]]*module([[:space:]]|")/ { inb = 1; d = 0; src = "-" }
    inb {
      if (d == 1 && match($0, /^[[:space:]]*source[[:space:]]*=[[:space:]]*"[^"]*"/)) { src = substr($0, RSTART, RLENGTH); sub(/^[^"]*"/, "", src); sub(/"$/, "", src) }
      c = cv($0); o = gsub(/\{/, "{", c); x = gsub(/\}/, "}", c); d += o - x
      if (d <= 0 && o + x > 0) { print src; inb = 0 }
    }'
}

lock_field() {  # lock_field <version|constraints> -> value of the logtail provider entry in the lock
  awk -v f="$1" '/^provider "registry.terraform.io\/betterstackhq\/logtail" \{/ { i = 1; next }
    i && /^\}/ { exit }
    i && $1 == f { v = $0; sub(/^[^"]*"/, "", v); sub(/".*$/, "", v); print v }' "$INFRA/.terraform.lock.hcl" 2>/dev/null
}
main_constraint() { main_logtail_field version; }

# CI pin: for ONE guard path, prints one reason line per defect. `W:` = not wired as a plain step,
# `M:` = masked. Empty output = wired plainly and unmasked.
#   step  : every step-level key must be `name` or `run` (ALLOW-list; an unlisted key is the defect, whatever it is)
#   job   : the WHOLE job block, `steps:` list excluded: job-level keys that appear before OR after `steps:` are an
#           ALLOW-list {runs-on, needs, if (== JOB_IF_ALLOWED), permissions, timeout-minutes, steps, strategy, name};
#           `defaults:`, a shell-injection env name and a $GITHUB_ENV / $GITHUB_PATH write anywhere in the job (run
#           bodies included: an earlier step poisons every later one) are refused by name
#   file  : workflow-level lines before `jobs:`: no `defaults:` (a default shell rewrites every step), no
#           shell-injection env name, no guard-redirect env name
# `*GUARD_*` (any name containing `GUARD_`, with or without a prefix: the guards read GUARD_TF, GUARD_SCRIPTS_DIR,
# GUARD_SERVER_TF, GUARD_VECTOR_TOML bare) and `ALERT_STRUCT_*` are the env names that redirect a guard or this
# suite at another tree. BASH_ENV, SHELLOPTS, BASHOPTS and ENV are the names that make bash source or change a
# program before the guard's first line.
ci_pin_of() {  # ci_pin_of <workflow> <repo-relative guard path>
  awk -v P="$2" -v JOBIF="$JOB_IF_ALLOWED" '
    function guard(s) { return s ~ /(^|[^A-Z0-9])[A-Z_]*GUARD_[A-Z_]+/ }
    function shenv(s) { return s ~ /(^|[^A-Za-z0-9_])(BASH_ENV|SHELLOPTS|BASHOPTS|ENV)[[:space:]]*[:=]/ }
    function ind(s) { match(s, /^[[:space:]]*/); return RLENGTH }
    function blank(s) { return s ~ /^[[:space:]]*$/ }
    function cmt(s) { return s ~ /^[[:space:]]*#/ }
    { L[NR] = $0 }
    END {
      nall = 0; nplain = 0
      for (i = 1; i <= NR; i++) {
        s = L[i]
        if (cmt(s) || index(s, P) == 0) continue
        nall++
        t = s
        if (sub(/^[[:space:]]*(-[[:space:]]+)?run:[[:space:]]*bash[[:space:]]+/, "", t)) {
          sub(/[[:space:]]+$/, "", t)
          if (t == P) { nplain++; plain[nplain] = i }
        }
      }
      if (nall == 0) { print "W:no step runs it"; exit }
      if (nall != nplain) print "W:" (nall - nplain) " invocation(s) are not a plain `bash <path>` run line"
      for (n = 1; n <= nplain; n++) {
        i = plain[n]; dash = 0
        if (L[i] ~ /^[[:space:]]*-[[:space:]]/) dash = i
        else {
          for (j = i - 1; j >= 1; j--) {
            if (blank(L[j]) || cmt(L[j])) continue
            if (ind(L[j]) < ind(L[i])) { if (L[j] ~ /^[[:space:]]*-[[:space:]]/) dash = j; break }
          }
        }
        if (!dash) { print "W:cannot locate the step block"; continue }
        for (k = i + 1; k <= NR; k++) if (!blank(L[k]) && ind(L[k]) <= ind(L[dash])) break
        match(L[dash], /^[[:space:]]*-[[:space:]]+/); kc = RLENGTH
        for (m = dash; m < k; m++) {
          if (blank(L[m]) || cmt(L[m])) continue
          if (L[m] ~ /^[[:space:]]*(-[[:space:]]+)?(if|continue-on-error):/) print "M:step has " (L[m] ~ /continue-on-error/ ? "continue-on-error" : "if")
          if (guard(L[m])) print "M:step sets a *_GUARD_* env"
          if (L[m] ~ /ALERT_STRUCT_/) print "M:step sets an ALERT_STRUCT_* env"
          line = L[m]
          if (m == dash) sub(/^[[:space:]]*-[[:space:]]+/, "", line)
          else { if (ind(line) != kc) continue; sub(/^[[:space:]]+/, "", line) }
          key = "?"
          if (match(line, /^[A-Za-z0-9_-]+:/)) key = substr(line, 1, RLENGTH - 1)
          if (key != "name" && key != "run") print "M:step key " key " is outside the {name, run} allow-list"
        }
        job = 0
        for (j = dash; j >= 1; j--) {
          if (!blank(L[j]) && !cmt(L[j]) && ind(L[j]) == 0) break
          if (L[j] ~ /^  [A-Za-z0-9_-]+:[[:space:]]*$/) { job = j; break }
        }
        if (!job) { print "W:cannot locate the job"; continue }
        region = "job"
        for (m = job + 1; m <= NR; m++) {
          s = L[m]
          if (blank(s) || cmt(s)) continue
          if (ind(s) <= 2) break
          if (s ~ /GITHUB_(ENV|PATH)/) print "M:job writes $GITHUB_ENV / $GITHUB_PATH (every later step would run poisoned)"
          if (ind(s) == 4 && s !~ /^[[:space:]]*-/) {
            region = (s ~ /^    steps:/) ? "steps" : "job"
            jk = s; sub(/^[[:space:]]+/, "", jk); sub(/[: \t].*$/, "", jk)
            if (jk !~ /^(runs-on|needs|if|permissions|timeout-minutes|steps|strategy|name)$/) print "M:job key " jk " is outside the job allow-list"
            if (jk == "defaults") print "M:job has defaults: (a default shell rewrites every step)"
          }
          if (region != "job") continue
          if (s ~ /^    continue-on-error:/) print "M:job has continue-on-error"
          if (shenv(s)) print "M:job sets a shell-injection env (BASH_ENV, SHELLOPTS, BASHOPTS or ENV)"
          if (guard(s)) print "M:job sets a *_GUARD_* env"
          if (s ~ /ALERT_STRUCT_/) print "M:job sets an ALERT_STRUCT_* env"
          if (s ~ /^    if:/) { v = s; sub(/^    if:[[:space:]]*/, "", v); sub(/[[:space:]]+$/, "", v); if (v != JOBIF) print "M:job has an if: other than the dedup gate" }
        }
        for (m = 1; m <= NR; m++) {
          if (L[m] ~ /^jobs:/) break
          if (cmt(L[m])) continue
          if (L[m] ~ /^defaults:/) print "M:workflow-level defaults: (a default shell rewrites every step)"
          if (shenv(L[m])) print "M:workflow-level shell-injection env (BASH_ENV, SHELLOPTS, BASHOPTS or ENV)"
          if (guard(L[m])) print "M:workflow-level *_GUARD_* env"
          if (L[m] ~ /ALERT_STRUCT_/) print "M:workflow-level ALERT_STRUCT_* env"
        }
      }
    }' "$1" | sort -u
}
# Non-comment lines of one file that name ALERT_STRUCT_ (those variables point this suite at another tree).
struct_env_lines() { grep -vE '^[[:space:]]*#' "$1" | grep -E 'ALERT_STRUCT_' | sed -n '1,3p' | tr '\n' ' '; }
# One `<file> names ALERT_STRUCT_ (<lines>)` per offending file: the graded workflow, every workflow of the repo and
# scripts/test-all.sh (the runner that could export the variable for this suite).
struct_env_hits() {
  local f l
  for f in "$WF" "$REPO"/.github/workflows/*.yml "$REPO/scripts/test-all.sh"; do
    [ -r "$f" ] || continue
    l="$(struct_env_lines "$f")"
    [ -z "$l" ] || printf '%s names ALERT_STRUCT_ (%s)\n' "$(basename "$f")" "${l% }"
  done | sort -u
}

# The -target addresses of a workflow, scoped to logtail_* and to REAL arguments: whole-line comments, echo/printf
# lines and trailing `# ...` comments are dropped, so a -target that is only TEXT cannot satisfy the parity rows.
logtail_targets_of() {
  grep -vE '^[[:space:]]*(#|(-[[:space:]]+)?(run:[[:space:]]*)?(echo|printf)([[:space:]]|$))' "$1" | sed -E 's/[[:space:]]+#.*$//' \
    | grep -oE -- '-target=logtail_[A-Za-z0-9_]+\.[A-Za-z0-9_-]+' | sed 's/^-target=//' | sort -u
}

# Declared-set helpers
# main.tf's logtail provider field (`source` / `version`), from the required_providers block
main_logtail_field() {  # main_logtail_field <source|version>
  strip_comments "$INFRA/main.tf" 2>/dev/null | blank_heredocs \
    | awk -v f="$1" '/^[[:space:]]*logtail[[:space:]]*=[[:space:]]*\{/ { i = 1; next }
      i && /\}/ { exit }
      i && $1 == f { v = $0; sub(/^[^"]*"/, "", v); sub(/".*$/, "", v); print v }'
}

# ── enumerate once ─────────────────────────────────────────────────────────────────────────────────
declare -A BLK
ALERT_NAMES=(); EXPL_NAMES=(); NOBLOCK=()
while IFS='|' read -r _f _t _n; do
  [ -n "$_n" ] || continue
  _b="$(block_text "$_f" "$_t" "$_n")"
  [ -n "$_b" ] || NOBLOCK+=("$_n")
  BLK["$_t|$_n"]="$_b"
  case "$_t" in
    logtail_exploration_alert) ALERT_NAMES+=("$_n") ;;
    *) EXPL_NAMES+=("$_n") ;;
  esac
done < <(logtail_blocks)
NA=${#ALERT_NAMES[@]}; NE=${#EXPL_NAMES[@]}
STRAYS=(); while IFS= read -r _s; do [ -z "$_s" ] || STRAYS+=("$_s"); done < <(logtail_strays)

join() { local IFS='; '; printf '%s' "$*"; }

# ── 1-4 census ─────────────────────────────────────────────────────────────────────────────────────
[ "$NA" -ge "$CENSUS_FLOOR_ALERTS" ] \
  && ok "census floor: $NA logtail_exploration_alert blocks enumerated (floor $CENSUS_FLOOR_ALERTS)" \
  || no "census floor: only $NA logtail_exploration_alert blocks enumerated (floor $CENSUS_FLOOR_ALERTS): 0 checked must never read as green; edit the census floor with a legitimate removal"
[ "$NE" -ge "$CENSUS_FLOOR_EXPLORATIONS" ] \
  && ok "census floor: $NE logtail_exploration blocks enumerated (floor $CENSUS_FLOOR_EXPLORATIONS)" \
  || no "census floor: only $NE logtail_exploration blocks enumerated (floor $CENSUS_FLOOR_EXPLORATIONS): edit the census floor with a legitimate removal"
if [ "${#NOBLOCK[@]}" -eq 0 ] && [ "${#STRAYS[@]}" -eq 0 ]; then
  ok "every enumerated header yields an extractable block, and no other code line names a logtail_exploration"
else
  no "census: $([ "${#NOBLOCK[@]}" -eq 0 ] || printf 'no extractable block for: %s: the header is indented, unquoted or malformed and every row below would skip it; start the resource at column 0 with quoted labels. ' "$(join "${NOBLOCK[@]}")")$([ "${#STRAYS[@]}" -eq 0 ] || printf 'un-enumerated logtail_exploration line(s): %s: neither an enumerated header nor a logtail_exploration*.<n>.id reference, so no row would read it; write the header as resource "logtail_exploration[_alert]" "<name>" {' "$(join "${STRAYS[@]}")")"
fi
GUARD_LIST=()
for _g in "$GUARDS"/*alert*.test.sh; do [ -e "$_g" ] && GUARD_LIST+=("apps/web-platform/test/infra/$(basename "$_g")"); done
[ "${#GUARD_LIST[@]}" -ge "$GUARD_CENSUS_FLOOR" ] \
  && ok "guard census: ${#GUARD_LIST[@]} alert guards enumerated (floor $GUARD_CENSUS_FLOOR)" \
  || no "guard census: only ${#GUARD_LIST[@]} alert guards enumerated (floor $GUARD_CENSUS_FLOOR): edit GUARD_CENSUS_FLOOR with the removal"

# --census-only stops here: enumeration + the four census floors, nothing else.
if [ -n "$CENSUS_ONLY" ]; then
  if [ "$((pass + fail))" -ne 4 ] || [ "${#FAILED[@]}" -ne "$fail" ]; then
    printf '[FATAL] census-only ledger: %s ran, %s failed, %s recorded\n' "$((pass + fail))" "$fail" "${#FAILED[@]}" >&2; exit 1
  fi
  printf '\n=== betterstack-alert-structure --census-only: %s passed, %s failed (%s alerts, %s explorations, %s guards) ===\n' "$pass" "$fail" "$NA" "$NE" "${#GUARD_LIST[@]}"
  if [ "$fail" -eq 0 ]; then exit 0; else exit 1; fi
fi

# ── 5-7 closed attribute set ───────────────────────────────────────────────────────────────────────
_unk=(); _mis=(); _esc=()
for _n in "${ALERT_NAMES[@]}"; do
  _b="${BLK["logtail_exploration_alert|$_n"]}"
  _u="$(unknown_keys_of "$_b")"; [ -z "$_u" ] || _unk+=("alert $_n has unknown top-level key(s) [${_u% }]")
  _m="$(missing_keys_of "$_b")"; [ -z "$_m" ] || _mis+=("alert $_n is missing [${_m% }]")
  _c="$(escalation_count_of "$_b")"; [ "$_c" = 1 ] || _esc+=("alert $_n has $_c escalation_target blocks")
done
[ "${#_unk[@]}" -eq 0 ] \
  && ok "closed attribute set: no alert carries a key outside REQUIRED_ATTRS + OPTIONAL_ATTRS" \
  || no "closed attribute set: $(join "${_unk[@]}"): add it to OPTIONAL_ATTRS in this PR"
[ "${#_mis[@]}" -eq 0 ] \
  && ok "closed attribute set: every alert carries all $(wc -w <<<"$REQUIRED_ATTRS") required keys" \
  || no "missing required key: $(join "${_mis[@]}"): restore it or edit REQUIRED_ATTRS"
[ "${#_esc[@]}" -eq 0 ] \
  && ok "every alert carries exactly one escalation_target block" \
  || no "escalation_target blocks: $(join "${_esc[@]}"): restore the single escalation_target block"

# ── 8 no meta-arguments (alerts AND explorations) ──────────────────────────────────────────────────
_meta=()
for _k in "${!BLK[@]}"; do
  _h="$(meta_hits_of "${BLK[$_k]}")"; [ -z "$_h" ] || _meta+=("${_k#*|} (${_k%%|*}): ${_h% }")
done
[ "${#_meta[@]}" -eq 0 ] \
  && ok "no lifecycle/count/for_each/provider/depends_on/dynamic/provisioner/connection in any enumerated block" \
  || no "meta-argument in a logtail block: $(join "${_meta[@]}"): remove it; the family guards read the declared text only"

# ── 9-10 one alert per exploration, names agree ────────────────────────────────────────────────────
declare -A REFS; _bind=()
for _n in "${ALERT_NAMES[@]}"; do
  _b="${BLK["logtail_exploration_alert|$_n"]}"
  _cnt="$(exploration_id_lines_of "$_b")"; _got="$(bound_exploration_of "$_b" | tr '\n' ' ')"; _got="${_got% }"
  if [ "$_cnt" != 1 ] || [ "$_got" != "$_n" ]; then
    _bind+=("alert $_n: exploration_id must be exactly logtail_exploration.$_n.id (lines $_cnt, binds [$_got])")
  fi
  [ -z "$_got" ] || REFS["${_got%% *}"]=$(( ${REFS["${_got%% *}"]:-0} + 1 ))
done
[ "${#_bind[@]}" -eq 0 ] \
  && ok "every alert binds the exploration of its own name" \
  || no "$(join "${_bind[@]}"): rename the alert or restore its own exploration"
_ref=()
for _n in "${EXPL_NAMES[@]}"; do
  [ "${REFS[$_n]:-0}" = 1 ] || _ref+=("exploration $_n is referenced by ${REFS[$_n]:-0} alerts (want exactly 1)")
done
for _n in "${!REFS[@]}"; do
  grep -qxF "$_n" < <(printf '%s\n' "${EXPL_NAMES[@]}") || _ref+=("alert binds unknown exploration $_n")
done
[ "${#_ref[@]}" -eq 0 ] \
  && ok "each exploration is referenced by exactly one alert" \
  || no "$(join "${_ref[@]}"): one alert per exploration"

# ── 11 no state surgery ────────────────────────────────────────────────────────────────────────────
_sur=()
for _f in "$INFRA"/*.tf; do
  [ -e "$_f" ] || continue
  [ -z "$(surgery_in "$_f")" ] || _sur+=("$(basename "$_f")")
done
[ "${#_sur[@]}" -eq 0 ] \
  && ok "no removed/moved/import block names a logtail_exploration or logtail_exploration_alert address" \
  || no "state surgery: $(join "${_sur[@]}") has a removed/moved/import block naming a logtail address: delete the block"

# ── 12 no override files ───────────────────────────────────────────────────────────────────────────
[ "$(p_b4_no_override_files "$INFRA")" = 1 ] \
  && ok "no *override.tf / *override.tf.json / *.tf.json in the infra root" \
  || no "override file present in the infra root ($(cd "$INFRA" && ls -- *override.tf *.tf.json 2>/dev/null | tr '\n' ' ')): Terraform merges it over the reviewed text; delete it"

# ── 13 no symlinks ─────────────────────────────────────────────────────────────────────────────────
# find's own status is read (a find that failed to walk the tree found "no symlink" by not looking), and only the
# ROOT's own .terraform is skipped (a nested .terraform directory is a place to hide a link, not a provider cache).
_slrc=0; _slraw="$(find "$INFRA" -type l -not -path "$INFRA/.terraform/*" -printf '%P\n' 2>/dev/null)" || _slrc=$?
_sl="$(printf '%s\n' "$_slraw" | sed '/^$/d' | sort | tr '\n' ' ')"
if [ "$_slrc" -ne 0 ]; then
  no "symlink scan: find exited $_slrc under the infra root: an unreadable tree is not evidence of no symlink; fix the permissions"
elif [ -z "$_sl" ]; then
  ok "no symlink under the infra root"
else
  no "symlink under the infra root: ${_sl% }: a link is loaded by Terraform as the file it points at and read by no row here; replace it with a regular file"
fi

# ── 14 no logtail_* resource outside the root's own *.tf, no module block that leaves the root's subdirectories ──
# A root `module` block whose source is not `./<subdir>/...` (a registry or git source, an absolute path, a `..`
# escape, or no depth-1 source at all) pulls in .tf this suite never reads. The one legitimate module block today
# (git-data.tf, ./modules/git-data-userdata) is a root subdirectory, which the file scan below does read.
_out=()
_mods="$(for _f in "$INFRA"/*.tf; do
  [ -e "$_f" ] || continue
  while IFS= read -r _src; do printf '%s|%s\n' "$(basename "$_f")" "$_src"; done < <(module_sources_in "$_f")
done)"
while IFS='|' read -r _mf _src; do
  [ -n "$_mf" ] || continue
  case "$_src" in
    *..*|-|"") _out+=("$_mf: module with source '$_src' (non-local module source)") ;;
    ./[A-Za-z0-9_]*) : ;;
    *) _out+=("$_mf: module with source '$_src' (non-local module source)") ;;
  esac
done <<<"$_mods"
_fndrc=0; _found="$(find "$INFRA" -mindepth 2 \( -name '*.tf' -o -name '*.tf.json' \) -not -path "$INFRA/.terraform/*" -print 2>/dev/null | sort)" || _fndrc=$?
while IFS= read -r _f; do
  [ -n "$_f" ] || continue
  case "$_f" in
    *.tf.json) _c="$(grep -c 'logtail_' "$_f" 2>/dev/null)" ;;
    *) _c="$(strip_comments "$_f" | blank_heredocs | grep -cE '^[[:space:]]*resource[[:space:]]+"?logtail_')" ;;
  esac
  [ "${_c:-0}" -eq 0 ] || _out+=("${_f#"$INFRA"/}")
done <<<"$_found"
if [ "$_fndrc" -ne 0 ]; then
  no "subdirectory scan: find exited $_fndrc under the infra root: an unreadable tree is not evidence of no logtail_* resource; fix the permissions"
elif [ "${#_out[@]}" -eq 0 ]; then
  ok "no logtail_* resource is declared outside the infra root's own *.tf files, and every root module block has a ./<subdir> source"
else
  no "logtail_* resource or non-local module outside the infra root: $(join "${_out[@]}"): a subdirectory, remote module or module file is invisible to the root enumeration and to every guard; declare it in a root *.tf and keep module sources under ./"
fi

# ── 15-17 provider tripwire ────────────────────────────────────────────────────────────────────────
_lc="$(lock_field constraints)"; _lv="$(lock_field version)"; _mc="$(main_constraint)"; _ms="$(main_logtail_field source)"
[ -n "$_lc" ] && [ "$_lc" = "$_mc" ] \
  && ok "provider: lock constraints \"$_lc\" equals main.tf's logtail version literal" \
  || no "provider lock constraints \"$_lc\" != main.tf logtail version \"$_mc\": edit the two together with the bump"
[ -n "$_lv" ] && [ "$_lv" = "$PROVIDER_LOCK_VERSION" ] \
  && ok "provider: lock version \"$_lv\" equals PROVIDER_LOCK_VERSION (a tripwire, not an integrity proof)" \
  || no "provider lock version \"$_lv\" != PROVIDER_LOCK_VERSION \"$PROVIDER_LOCK_VERSION\": edit the two provider constants with the bump"
[ -n "$_ms" ] && [ "$_ms" = "$PROVIDER_SOURCE" ] \
  && ok "provider: main.tf's logtail source \"$_ms\" equals PROVIDER_SOURCE" \
  || no "provider source \"$_ms\" != PROVIDER_SOURCE \"$PROVIDER_SOURCE\": a different publisher's logtail provider would read every resource below as the real one; edit PROVIDER_SOURCE only with a deliberate provider change"

# ── 18-19 CI pin ───────────────────────────────────────────────────────────────────────────────────
_w=(); _mk=()
for _g in "${GUARD_LIST[@]}"; do
  _r="$(ci_pin_of "$WF" "$_g")"
  while IFS= read -r _line; do
    case "$_line" in
      W:*) _w+=("$_g: ${_line#W:}") ;;
      M:*) _mk+=("$_g: ${_line#M:}") ;;
    esac
  done <<<"$_r"
done
[ "${#_w[@]}" -eq 0 ] \
  && ok "CI pin: every alert guard is a plain 'bash <path>' step in infra-validation.yml" \
  || no "CI pin: $(join "${_w[@]}"): restore the plain 'bash <path>' step"
[ "${#_mk[@]}" -eq 0 ] \
  && ok "CI pin: no alert-guard step (keys exactly {name, run}), job block or workflow env is masked" \
  || no "CI pin masked: $(join "${_mk[@]}"): restore the plain 'bash <path>' step with only name:/run: keys and no job- or workflow-level if:/continue-on-error:/*_GUARD_*/ALERT_STRUCT_* env"

# ── 20 no ALERT_STRUCT_ env anywhere in a workflow or the test runner ──────────────────────────────
_se=(); while IFS= read -r _s; do [ -z "$_s" ] || _se+=("$_s"); done < <(struct_env_hits)
[ "${#_se[@]}" -eq 0 ] \
  && ok "CI env: no workflow and not scripts/test-all.sh names ALERT_STRUCT_ (the override variables of this suite)" \
  || no "CI env: $(join "${_se[@]}"): those variables point this suite at another tree; remove it"

# ── 21-22 apply parity, scoped to logtail_* ────────────────────────────────────────────────────────
_enum="$(for _k in "${!BLK[@]}"; do printf '%s.%s\n' "${_k%%|*}" "${_k#*|}"; done | sort -u)"
_tgt="$(logtail_targets_of "$APPLY_WF")"
_untg="$(comm -23 <(printf '%s\n' "$_enum" | sed '/^$/d') <(printf '%s\n' "$_tgt" | sed '/^$/d') | tr '\n' ' ')"
_stray="$(comm -13 <(printf '%s\n' "$_enum" | sed '/^$/d') <(printf '%s\n' "$_tgt" | sed '/^$/d') | tr '\n' ' ')"
[ -z "$_untg" ] && [ -n "$_tgt" ] \
  && ok "apply parity: every enumerated logtail resource has a -target= line in apply-web-platform-infra.yml" \
  || no "apply parity: no -target= line in apply-web-platform-infra.yml for: ${_untg% }: an untargeted resource is never applied and never exists (#5566); add the line"
[ -z "$_stray" ] \
  && ok "apply parity: every -target=logtail_* line names an enumerated resource" \
  || no "apply parity: -target=logtail_* line(s) naming no enumerated resource: ${_stray% }: remove the line or declare the resource in a root *.tf"

# ── 23-24 predicate controls (synthetic blocks through the SAME chokepoint) ─────────────────────────
_ctl="$WORK/ctl.tf"
{
  echo 'resource "logtail_exploration_alert" "ctl_ok" {'
  echo '  # lifecycle { prevent_destroy = true }'
  echo '  /* count = 1 */'
  echo '  // for_each = []'
  echo '  # provisioner "local-exec" { connection { type = "ssh" } }'
  for _r in $REQUIRED_ATTRS; do
    case "$_r" in
      incident_cause) printf '  incident_cause = <<-EOT\n    lifecycle {\n    count = 1\n    for_each = []\n  EOT\n' ;;
      metadata) printf '  metadata = {\n    runbook = "x"\n  }\n' ;;
      *) printf '  %s = 1 # count = 2\n' "$_r" ;;
    esac
  done
  printf '  escalation_target {\n    policy_id = null\n  }\n}\n'
  echo 'resource "logtail_exploration_alert" "ctl_bad" {'
  echo '  lifecycle {'
  echo '    ignore_changes = [value]'
  echo '  }'
  echo '  zz_unknown = 1'
  echo '  push = true'
  printf '  escalation_target {\n  }\n  escalation_target {\n  }\n}\n'
} > "$_ctl"
_cok="$(block_text "$_ctl" logtail_exploration_alert ctl_ok)"; _cbad="$(block_text "$_ctl" logtail_exploration_alert ctl_bad)"
if [ -n "$_cok" ] && [ -n "$_cbad" ] \
   && [ -z "$(meta_hits_of "$_cok")" ] && [ -n "$(meta_hits_of "$_cbad")" ]; then
  ok "control: the meta-argument predicate passes a comment and a heredoc that NAME the words and fails a real lifecycle block"
else
  no "control: the meta-argument predicate is not discriminating (ok-block hits='$(meta_hits_of "$_cok")', bad-block hits='$(meta_hits_of "$_cbad")')"
fi
if [ -n "$_cok" ] && [ -z "$(unknown_keys_of "$_cok")" ] && [ -z "$(missing_keys_of "$_cok")" ] && [ "$(escalation_count_of "$_cok")" = 1 ] \
   && [ -n "$(unknown_keys_of "$_cbad")" ] && [ -n "$(missing_keys_of "$_cbad")" ] && [ "$(escalation_count_of "$_cbad")" = 2 ]; then
  ok "control: the attribute-set predicates pass the canonical synthetic alert and fail an unknown key, missing keys and two escalation blocks"
else
  no "control: the attribute-set predicates are not discriminating (ok: unk='$(unknown_keys_of "$_cok")' mis='$(missing_keys_of "$_cok")' esc=$(escalation_count_of "$_cok"); bad: unk='$(unknown_keys_of "$_cbad")' esc=$(escalation_count_of "$_cbad"))"
fi

# ── Mutation battery ───────────────────────────────────────────────────────────────────────────────
if [ -z "$PRESENCE_ONLY" ]; then
  MUT_DIR="$WORK/mut"; mkdir -p "$MUT_DIR" || { printf '[FATAL] mkdir failed\n' >&2; exit 2; }
  assert_fixture_dir "$MUT_DIR"
  MUT_REAL="$(realpath "$MUT_DIR")"
  assert_fixture_dir "$MUT_REAL"
  _snap() { { find "$INFRA" -maxdepth 1 -type f \( -name '*.tf' -o -name '*.tf.json' -o -name '.terraform.lock.hcl' \) -print0 | sort -z | xargs -0 sha256sum; sha256sum "$WF" "$APPLY_WF"; } | sha256sum; }
  SNAP_BEFORE="$(_snap)"

  # INSTRUMENT CONTROL - the inner run against the PRISTINE tree must exit 0, or every row below would grade a
  # broken invocation as "mutation RED".
  ctl_rc=0; bash "$SELF" --presence-only >"$MUT_DIR/control.log" 2>&1 || ctl_rc=$?
  if [ "$ctl_rc" -ne 0 ]; then
    printf '[FATAL] instrument control: the inner run exited %s on the PRISTINE tree - the battery cannot be trusted:\n' "$ctl_rc" >&2
    sed 's/^/    /' "$MUT_DIR/control.log" >&2; exit 2
  fi

  _in_mut() { local p; p="$(realpath -m -- "$1")"; case "$p" in "$MUT_REAL"/*) return 0 ;; esac; return 1; }
  _dsum() { ( cd "$1" && { find . -type f -print0 | sort -z | xargs -0 sha256sum; find . -type l -printf '%p -> %l\n' | sort; } | sha256sum ); }

  PRELUDE='import re, sys, os
root, wf, awf = sys.argv[1], sys.argv[2], sys.argv[3]
BT = os.path.join(root, "betterstack-logs-alerts.tf")
def rd(p): return open(p, encoding="utf-8").read()
def wr(p, s): open(p, "w", encoding="utf-8").write(s)
AH = re.compile(r"^resource \"logtail_exploration_alert\" \"([A-Za-z0-9_]+)\" \{$", re.M)
EH = re.compile(r"^resource \"logtail_exploration\" \"([A-Za-z0-9_]+)\" \{$", re.M)
def span(s, m):
    j = s.index("\n}\n", m.start())
    return m.start(), j + 3
def inject(s, i, text):
    m = list(AH.finditer(s))[i]
    return s[:m.end()] + "\n" + text + s[m.end():]
def alert_text(s, i):
    a, b = span(s, list(AH.finditer(s))[i]); return s[a:b]
def inject_expl(s, i, text):
    m = list(EH.finditer(s))[i]
    return s[:m.end()] + "\n" + text + s[m.end():]
def last(s): return len(list(AH.finditer(s))) - 1
def mid(s): return len(list(AH.finditer(s))) // 2'

  fake_root() {  # fake_root <dir>: a scratch repo skeleton built from the real tree (suite, lexer, infra, workflow, guard names)
    local r="$1" g
    assert_fixture_dir "$r"
    _in_mut "$r" || { printf '[FATAL] fake_root outside MUT_DIR: %s\n' "$r" >&2; exit 2; }
    mkdir -p "$r/apps/web-platform/infra" "$r/tests/scripts/lib" "$r/.github/workflows" "$r/apps/web-platform/test/infra" || exit 2
    cp -P "$APPLY_WF" "$r/.github/workflows/apply-web-platform-infra.yml" || exit 2
    cp -P "$INFRA"/*.tf "$r/apps/web-platform/infra/" || exit 2
    cp -P "$INFRA/.terraform.lock.hcl" "$r/apps/web-platform/infra/" || exit 2
    cp -P "$SELF" "$r/apps/web-platform/infra/betterstack-alert-structure.test.sh" || exit 2
    cp -P "$HCL_LIB" "$r/tests/scripts/lib/hcl-effective-text.sh" || exit 2
    cp -P "$WF" "$r/.github/workflows/infra-validation.yml" || exit 2
    for g in "$GUARDS"/*alert*.test.sh; do : > "$r/apps/web-platform/test/infra/$(basename "$g")"; done
  }

  # mut <red|pass|fatal> <label> <expected FAIL fragment | -> <ovr|fake> <python program | -> [suite-sed] [lib-append]
  #   red   : inner rc must be 1 AND a [FAIL] line must contain the fragment (a row that goes red for the WRONG reason is not evidence)
  #   pass  : inner rc must be 0 (a legitimate shape must not red)
  #   fatal : inner rc must be 2 (the instrument refuses to run)
  mut() {
    local want="$1" label="$2" tag="$3" kind="$4" prog="$5" ssed="${6:-}" libapp="${7:-}"
    local w root wf awf suite b0 b1 w0 w1 rootall
    MUT_N=$(( ${MUT_N:-0} + 1 ))
    w="$MUT_DIR/s$MUT_N"; _in_mut "$w" || { printf '[FATAL] scratch %s outside MUT_DIR\n' "$w" >&2; exit 2; }
    mkdir -p "$w" || exit 2
    if [ "$kind" = ovr ]; then
      root="$w/infra"; wf="$w/infra-validation.yml"; awf="$w/apply-web-platform-infra.yml"; suite="$SELF"
      mkdir -p "$root" || exit 2
      cp -P "$INFRA"/*.tf "$root/" || exit 2
      cp -P "$INFRA/.terraform.lock.hcl" "$root/" || exit 2
      cp -P "$WF" "$wf" || exit 2
      cp -P "$APPLY_WF" "$awf" || exit 2
      rootall="$root"
    else
      fake_root "$w/repo"
      root="$w/repo/apps/web-platform/infra"; wf="$w/repo/.github/workflows/infra-validation.yml"
      awf="$w/repo/.github/workflows/apply-web-platform-infra.yml"
      rootall="$w/repo"   # a fake-root program may plant a file outside infra/ (another workflow, scripts/test-all.sh)
      suite="$root/betterstack-alert-structure.test.sh"
      if [ -n "$ssed" ]; then
        cp -P "$suite" "$suite.orig" && sed -i "$ssed" "$suite" && ! cmp -s "$suite" "$suite.orig" \
          || { no "mutation '$label' did not land (suite sed matched nothing)"; return 0; }
        rm -f "$suite.orig"
      fi
      if [ -n "$libapp" ]; then printf '\n%s\n' "$libapp" >> "$w/repo/tests/scripts/lib/hcl-effective-text.sh"; fi
    fi
    b0="$(_dsum "$rootall")"; w0="$(sha256sum < "$wf") $(sha256sum < "$awf")"
    if [ "$prog" != "-" ]; then
      printf '%s\n%s\n' "$PRELUDE" "$prog" > "$w/mut.py"
      python3 "$w/mut.py" "$root" "$wf" "$awf" || { no "mutation '$label' did not land (the python program failed)"; return 0; }
      b1="$(_dsum "$rootall")"; w1="$(sha256sum < "$wf") $(sha256sum < "$awf")"
      if [ "$b0" = "$b1" ] && [ "$w0" = "$w1" ]; then no "mutation '$label' produced no change"; return 0; fi
    fi
    # Inner runs execute concurrently (each is a ~10-12 s pass, header enumeration then one lexer pass per block);
    # grading happens in grade_all, in row order. MUT_FLAG selects the inner mode (default --presence-only).
    if [ "$kind" = ovr ]; then
      [ -n "$root" ] && [ -n "$wf" ] || { printf '[FATAL] mut: empty override path\n' >&2; exit 2; }
      local gd="$GUARDS"
      if [ -n "${MUT_GUARDS_EMPTY:-}" ]; then gd="$w/noguards"; mkdir -p "$gd" || exit 2; fi
      ( rc=0; ALERT_STRUCT_INFRA="$root" ALERT_STRUCT_WF="$wf" ALERT_STRUCT_APPLY_WF="$awf" ALERT_STRUCT_GUARDS="$gd" bash "$suite" "${MUT_FLAG:---presence-only}" >"$w/out.log" 2>&1 || rc=$?; echo "$rc" > "$w/rc" ) &
    else
      ( rc=0; env -u ALERT_STRUCT_INFRA -u ALERT_STRUCT_WF -u ALERT_STRUCT_APPLY_WF -u ALERT_STRUCT_GUARDS bash "$suite" "${MUT_FLAG:---presence-only}" >"$w/out.log" 2>&1 || rc=$?; echo "$rc" > "$w/rc" ) &
    fi
    PEND_WANT+=("$want"); PEND_LABEL+=("$label"); PEND_TAG+=("$tag"); PEND_DIR+=("$w")
    while [ "$(jobs -rp | wc -l)" -ge "$MUT_JOBS" ]; do wait -n 2>/dev/null || true; done
  }

  grade_all() {
    local i want label tag w rc
    wait
    for i in "${!PEND_DIR[@]}"; do
      want="${PEND_WANT[$i]}"; label="${PEND_LABEL[$i]}"; tag="${PEND_TAG[$i]}"; w="${PEND_DIR[$i]}"
      rc="$(cat "$w/rc" 2>/dev/null)"; rc="${rc:-255}"
      case "$want:$rc" in
        red:1)
          if [ "$tag" = "-" ] || fail_line_has "$w/out.log" "$tag"; then ok "mutation RED: $label"
          else no "mutation went red for the WRONG reason (no [FAIL] line contains '$tag'): $label"; fi ;;
        pass:0) ok "must-PASS stays green: $label" ;;
        fatal:2) ok "instrument refuses (rc 2): $label" ;;
        red:0) no "mutation SURVIVED: $label - the rows above pin nothing" ;;
        pass:1) no "legitimate shape went RED: $label - $(grep -F '[FAIL]' "$w/out.log" | sed -n 1p)" ;;
        *) no "mutation UNRESOLVED (want $want, inner rc=$rc, not an assertion): $label - instrument, not evidence" ;;
      esac
    done
  }
  PEND_WANT=(); PEND_LABEL=(); PEND_TAG=(); PEND_DIR=()
  MUT_JOBS="$(nproc 2>/dev/null || echo 2)"; [ "$MUT_JOBS" -le 6 ] || MUT_JOBS=6; [ "$MUT_JOBS" -ge 1 ] || MUT_JOBS=2

  # ── mutation matrix ────────────────────────────────────────────────────────────────────────────────
  mut red "M-1: a zz_override.tf planted in the infra root" "override" ovr \
    'wr(os.path.join(root, "zz_override.tf"), "# merged over the reviewed text\n")'
  mut red "M-2: a *.tf.json planted in the infra root" "override" ovr \
    'wr(os.path.join(root, "zz.tf.json"), "{}\n")'
  mut red "M-3a: lifecycle { ignore_changes } on the LAST alert (a check that stops at the first member is itself the defect)" "meta-argument" ovr \
    's = rd(BT); wr(BT, inject(s, last(s), "  lifecycle {\n    ignore_changes = [query_period]\n  }"))'
  mut red "M-3b: count = 0 on a MIDDLE alert" "meta-argument" ovr \
    's = rd(BT); wr(BT, inject(s, mid(s), "  count = 0"))'
  mut red "M-3c: for_each on the FIRST alert" "meta-argument" ovr \
    's = rd(BT); wr(BT, inject(s, 0, "  for_each = toset([])"))'
  mut red "M-4a: aggregation_interval = 300 on one alert (unknown key)" "OPTIONAL_ATTRS" ovr \
    's = rd(BT); wr(BT, inject(s, mid(s) + 1, "  aggregation_interval = 300"))'
  mut red "M-4b: a dynamic \"escalation_target\" block on another alert (sibling-block axis)" "block:dynamic" ovr \
    's = rd(BT); wr(BT, inject(s, 2, "  dynamic \"escalation_target\" {\n    for_each = []\n    content {\n    }\n  }"))'
  mut red "M-4c: a second escalation_target block on one alert" "escalation_target blocks" ovr \
    's = rd(BT); wr(BT, inject(s, 3, "  escalation_target {\n    team_name = \"Your team\"\n  }"))'
  mut red "M-5: push deleted from one alert (missing required key)" "missing required key" ovr \
    's = rd(BT); a, b = span(s, list(AH.finditer(s))[mid(s)]); blk = s[a:b]; new = re.sub(r"(?m)^  push +=.*\n", "", blk, count=1); assert new != blk; wr(BT, s[:a] + new + s[b:])'
  mut red "M-6: a second alert (probe2) bound to an EXISTING exploration" "is referenced by 2 alerts" ovr \
    's = rd(BT); t = alert_text(s, last(s)); m = AH.search(t); nm = m.group(1); t2 = t.replace("\"" + nm + "\" {", "\"" + nm + "_probe2\" {", 1); wr(BT, s + "\n" + t2)'
  mut red "M-7: a moved {} block naming a logtail_exploration_alert address, in a DIFFERENT *.tf (removed/import share the one header matcher)" "state surgery" ovr \
    'p = os.path.join(root, "dns.tf"); wr(p, rd(p) + "\nmoved {\n  from = logtail_exploration_alert.old_name\n  to   = logtail_exploration_alert.new_name\n}\n")'
  mut red "M-7b: a removed {} block naming a logtail_exploration address (multi-line form)" "state surgery" ovr \
    'p = os.path.join(root, "network.tf"); wr(p, rd(p) + "\nremoved {\n  from = logtail_exploration.old_name\n  lifecycle {\n    destroy = false\n  }\n}\n")'
  mut red "M-8: the lock's logtail version bumped" "provider lock version" ovr \
    'p = os.path.join(root, ".terraform.lock.hcl"); s = rd(p); i = s.index("betterstackhq/logtail"); j = s.index("\"11.2.0\"", i); wr(p, s[:j] + "\"11.2.1\"" + s[j + 8:])'
  mut red "M-8b: main.tf's logtail constraint literal changed away from the lock's" "provider lock constraints" ovr \
    'p = os.path.join(root, "main.tf"); s = rd(p); i = s.index("BetterStackHQ/logtail"); j = s.index("~> 11.2", i); wr(p, s[:j] + "~> 11.3" + s[j + 7:])'
  mut red "M-9a: continue-on-error: true on one alert-guard step" "masked" ovr \
    'p = wf; s = rd(p); k = "        run: bash apps/web-platform/test/infra/egress-gw-alert.test.sh\n"; assert s.count(k) == 1; wr(p, s.replace(k, k + "        continue-on-error: true\n"))'
  mut red "M-9b: another alert-guard step deleted" "no step runs it" ovr \
    'p = wf; s = rd(p); n = re.subn(r"(?m)^      - name: [^\n]*\n        run: bash apps/web-platform/test/infra/ghcr-blocked-alert\.test\.sh\n", "", s); assert n[1] == 1; wr(p, n[0])'
  mut red "M-9c: a step-level if: on a third alert-guard step" "step has if" ovr \
    'p = wf; s = rd(p); k = "        run: bash apps/web-platform/test/infra/sandbox-alerts.test.sh\n"; assert s.count(k) == 1; wr(p, s.replace(k, k + "        if: always() && false\n"))'
  mut red "M-9d: a *_GUARD_* env on a fourth alert-guard step" "*_GUARD_* env" ovr \
    'p = wf; s = rd(p); k = "        run: bash apps/web-platform/test/infra/ghcr-blocked-alert.test.sh\n"; assert s.count(k) == 1; wr(p, s.replace(k, k + "        env:\n          ALERT_GUARD_TF: /dev/null\n"))'
  mut red "M-9e: the guard job gains continue-on-error: true" "job has continue-on-error" ovr \
    'p = wf; s = rd(p); k = "  deploy-script-tests-fixed:\n"; assert s.count(k) == 1; wr(p, s.replace(k, k + "    continue-on-error: true\n"))'
  mut red "M-9f: the guard step is wrapped as bash <path> || true (not a plain run line)" "not a plain" ovr \
    'p = wf; s = rd(p); k = "        run: bash apps/web-platform/test/infra/web-nic-guard-unpinned-url-alert.test.sh\n"; assert s.count(k) == 1; wr(p, s.replace(k, "        run: bash apps/web-platform/test/infra/web-nic-guard-unpinned-url-alert.test.sh || true\n"))'
  mut red "M-10a: DISPATCH - an infra root with ZERO logtail_* blocks (floor RED, never 0 checked rc 0)" "census floor" ovr \
    'wr(BT, "# every logtail resource removed\n")'
  mut red "M-10b: one alert+exploration pair legitimately removed (the floor is exactly today's count)" "census floor" ovr \
    's = rd(BT); i = last(s); a, b = span(s, list(AH.finditer(s))[i]); nm = AH.search(s[a:b]).group(1); s = s[:a] + s[b:]; e = [m for m in EH.finditer(s) if m.group(1) == nm][0]; c, d = span(s, e); wr(BT, s[:c] + s[d:])'
  MUT_GUARDS_EMPTY=1 mut red "M-10c: an empty guard directory (the CI-pin census floor)" "guard census" ovr '-'
  mut red "M-11: an alert header indented by two spaces (block_of cannot extract it, so every row after would skip it)" "no extractable block" ovr \
    's = rd(BT); m = list(AH.finditer(s))[mid(s)]; wr(BT, s[:m.start()] + "  " + s[m.start():])'

  # ── predicates the rows above did not pin on their own (each names its own FAIL fragment) ─────────
  mut red "M-12: two alerts swap their exploration_id lines (each still binds exactly one exploration, each exploration is still referenced once: ONLY the name-equality half of rows 9-10 sees it)" "exploration_id must be exactly" ovr \
    's = rd(BT); ms = list(AH.finditer(s)); a1, b1 = span(s, ms[1]); a2, b2 = span(s, ms[2]); t1 = s[a1:b1]; t2 = s[a2:b2]; pat = re.compile(r"(?m)^  exploration_id +=.*\n"); l1 = pat.search(t1).group(0); l2 = pat.search(t2).group(0); assert l1 != l2; wr(BT, s[:a1] + t1.replace(l1, l2, 1) + s[b1:a2] + t2.replace(l2, l1, 1) + s[b2:])'
  mut red "M-13a: lifecycle { ignore_changes } injected into an EXPLORATION (row 8 reads explorations too)" "meta-argument" ovr \
    's = rd(BT); wr(BT, inject_expl(s, 0, "  lifecycle {\n    ignore_changes = [sql_query]\n  }"))'
  mut red "M-13b: a provisioner \"local-exec\" block injected into the LAST exploration" "meta-argument" ovr \
    's = rd(BT); n = len(list(EH.finditer(s))); wr(BT, inject_expl(s, n - 1, "  provisioner \"local-exec\" {\n    command = \"true\"\n  }"))'
  mut red "M-13c: a connection block injected into a MIDDLE alert" "meta-argument" ovr \
    's = rd(BT); wr(BT, inject(s, mid(s), "  connection {\n    type = \"ssh\"\n  }"))'
  mut red "M-14: the guard job's if: replaced by if: always() (not the dedup gate)" "if: other than the dedup gate" ovr \
    'p = wf; s = rd(p); k = "  deploy-script-tests-fixed:\n    needs: detect-changes\n    if: needs.detect-changes.outputs.pr_duplicate != \x27true\x27\n"; assert s.count(k) == 1; wr(p, s.replace(k, k.replace("if: needs.detect-changes.outputs.pr_duplicate != \x27true\x27", "if: always()")))'
  mut red "M-15a: a *_GUARD_* env at JOB level BEFORE steps:" "job sets a *_GUARD_* env" ovr \
    'p = wf; s = rd(p); k = "  deploy-script-tests-fixed:\n"; assert s.count(k) == 1; wr(p, s.replace(k, k + "    env:\n      ALERT_GUARD_TF: /dev/null\n"))'
  mut red "M-15b: continue-on-error: true as a job-level key AFTER the steps: list (the old scan stopped at steps:)" "job has continue-on-error" ovr \
    'p = wf; s = rd(p); k = "\n  deploy-script-tests-done:\n"; assert s.count(k) == 1; wr(p, s.replace(k, "\n    continue-on-error: true" + k))'
  mut red "M-15c: a job-level if: AFTER the steps: list" "if: other than the dedup gate" ovr \
    'p = wf; s = rd(p); k = "\n  deploy-script-tests-done:\n"; assert s.count(k) == 1; wr(p, s.replace(k, "\n    if: always()" + k))'
  mut red "M-15d: a job-level *_GUARD_* env AFTER the steps: list" "job sets a *_GUARD_* env" ovr \
    'p = wf; s = rd(p); k = "\n  deploy-script-tests-done:\n"; assert s.count(k) == 1; wr(p, s.replace(k, "\n    env:\n      ALERT_GUARD_TF: /dev/null" + k))'
  mut red "M-16: a *_GUARD_* env at WORKFLOW level" "workflow-level *_GUARD_* env" ovr \
    'p = wf; s = rd(p); k = "\nenv:\n"; assert s.count(k) == 1; wr(p, s.replace(k, k + "  ALERT_GUARD_TF: /dev/null\n"))'
  mut red "M-17a: an unlisted step key (timeout-minutes) on a guard step (the step check is an allow-list of {name, run})" "allow-list" ovr \
    'p = wf; s = rd(p); k = "        run: bash apps/web-platform/test/infra/egress-gw-alert.test.sh\n"; assert s.count(k) == 1; wr(p, s.replace(k, k + "        timeout-minutes: 1\n"))'
  mut red "M-17b: a benign-looking env: block (no *_GUARD_* name) on a guard step" "allow-list" ovr \
    'p = wf; s = rd(p); k = "        run: bash apps/web-platform/test/infra/ghcr-blocked-alert.test.sh\n"; assert s.count(k) == 1; wr(p, s.replace(k, k + "        env:\n          HARMLESS: yes\n"))'
  mut red "M-18a: ALERT_STRUCT_INFRA set as env of a DIFFERENT job (it redirects this suite at another tree)" "CI env: infra-validation.yml names ALERT_STRUCT_" ovr \
    'p = wf; s = rd(p); k = "  registry-userdata-budget:\n"; assert s.count(k) == 1; wr(p, s.replace(k, k + "    env:\n      ALERT_STRUCT_INFRA: /tmp/elsewhere\n"))'
  mut red "M-18b: ALERT_STRUCT_INFRA on a guard step" "step sets an ALERT_STRUCT_* env" ovr \
    'p = wf; s = rd(p); k = "        run: bash apps/web-platform/test/infra/egress-gw-alert.test.sh\n"; assert s.count(k) == 1; wr(p, s.replace(k, k + "        env:\n          ALERT_STRUCT_INFRA: /tmp/elsewhere\n"))'
  mut red "M-18c: ALERT_STRUCT_WF at workflow level" "workflow-level ALERT_STRUCT_* env" ovr \
    'p = wf; s = rd(p); k = "\nenv:\n"; assert s.count(k) == 1; wr(p, s.replace(k, k + "  ALERT_STRUCT_WF: /dev/null\n"))'
  mut red "M-18d: ALERT_STRUCT_GUARDS at the guard job level" "job sets an ALERT_STRUCT_* env" ovr \
    'p = wf; s = rd(p); k = "  deploy-script-tests-fixed:\n"; assert s.count(k) == 1; wr(p, s.replace(k, k + "    env:\n      ALERT_STRUCT_GUARDS: /dev/null\n"))'
  mut red "M-19: a symlink planted in the infra root (zz_link.tf -> main.tf)" "symlink under the infra root" ovr \
    'os.symlink("main.tf", os.path.join(root, "zz_link.tf"))'
  mut red "M-20a: a logtail_exploration declared in a .tf of a SUBDIRECTORY" "outside the infra root" ovr \
    'd = os.path.join(root, "sentry"); os.makedirs(d); wr(os.path.join(d, "zz.tf"), "resource \"logtail_exploration\" \"sub_x\" {\n}\n")'
  mut red "M-20b: a logtail_exploration_alert with UNQUOTED labels in a new module directory" "outside the infra root" ovr \
    'd = os.path.join(root, "modules", "x"); os.makedirs(d); wr(os.path.join(d, "main.tf"), "resource logtail_exploration_alert sub_y {\n}\n")'
  mut red "M-21: main.tf's logtail provider source changed to another publisher" "provider source" ovr \
    'p = os.path.join(root, "main.tf"); s = rd(p); k = "source  = \"BetterStackHQ/logtail\""; assert s.count(k) == 1; wr(p, s.replace(k, "source  = \"evilcorp/logtail\""))'
  mut red "M-22a: an alert header with UNQUOTED labels (the enumerator must see it, never skip it)" "zz_unq1" ovr \
    's = rd(BT); wr(BT, s + "\nresource logtail_exploration_alert zz_unq1 {\n}\n")'
  mut red "M-22b: an exploration header with a quoted type and an UNQUOTED name" "zz_unq2" ovr \
    's = rd(BT); wr(BT, s + "\nresource \"logtail_exploration\" zz_unq2 {\n}\n")'
  mut red "M-23a: a -target= line of an enumerated exploration deleted from the apply workflow" "no -target= line in apply-web-platform-infra.yml" ovr \
    'p = awf; s = rd(p); k = "              -target=logtail_exploration.egress_gw_probe_fail \\\n"; assert s.count(k) == 1; wr(p, s.replace(k, ""))'
  mut red "M-23b: a -target=logtail_* line naming a resource nobody declares" "naming no enumerated resource" ovr \
    'p = awf; s = rd(p); k = "              -target=logtail_exploration.egress_gw_probe_fail \\\n"; assert s.count(k) == 1; wr(p, s.replace(k, k + "              -target=logtail_exploration.rogue_x \\\n"))'
  MUT_FLAG=--census-only mut red "M-24a: --census-only with one alert+exploration pair removed (exit 1, never a vacuous green)" "census floor" ovr \
    's = rd(BT); i = last(s); a, b = span(s, list(AH.finditer(s))[i]); nm = AH.search(s[a:b]).group(1); s = s[:a] + s[b:]; e = [m for m in EH.finditer(s) if m.group(1) == nm][0]; c, d = span(s, e); wr(BT, s[:c] + s[d:])'

  # ── #11483 review round 1: the CI pin is an allow-list at job level, the guard-env pattern matches bare names,
  #    module sources, a header the enumerator's sed cannot see, text-only -target lines, other workflows ─────────
  mut red "M-25a: BASH_ENV as a JOB-level env (bash would source it before the guard's first line)" "job sets a shell-injection env" ovr \
    'p = wf; s = rd(p); k = "  deploy-script-tests-fixed:\n"; assert s.count(k) == 1; wr(p, s.replace(k, k + "    env:\n      BASH_ENV: /tmp/elsewhere\n"))'
  mut red "M-25b: defaults.run.shell on the guard JOB (rewrites how every run line executes)" "job has defaults:" ovr \
    'p = wf; s = rd(p); k = "  deploy-script-tests-fixed:\n"; assert s.count(k) == 1; wr(p, s.replace(k, k + "    defaults:\n      run:\n        shell: bash -c \"true\" {0}\n"))'
  mut red "M-25c: defaults.run.shell at WORKFLOW level" "workflow-level defaults:" ovr \
    'p = wf; s = rd(p); k = "\nenv:\n"; assert s.count(k) == 1; wr(p, s.replace(k, "\ndefaults:\n  run:\n    shell: bash -c \"true\" {0}\n" + k))'
  mut red "M-25d: a run body in the guard job appends to \$GITHUB_PATH (a later step would run a planted bash)" "GITHUB_PATH" ovr \
    'p = wf; s = rd(p); i = s.index("  deploy-script-tests-fixed:\n"); j = s.index("    steps:\n", i) + len("    steps:\n"); wr(p, s[:j] + "      - run: echo /tmp/elsewhere >> \"$GITHUB_PATH\"\n" + s[j:])'
  mut red "M-25e: BASH_ENV at WORKFLOW level" "workflow-level shell-injection env" ovr \
    'p = wf; s = rd(p); k = "\nenv:\n"; assert s.count(k) == 1; wr(p, s.replace(k, k + "  BASH_ENV: /tmp/elsewhere\n"))'
  mut red "M-26a: the bare override name GUARD_TF (no leading underscore) on a guard STEP" "step sets a *_GUARD_* env" ovr \
    'p = wf; s = rd(p); k = "        run: bash apps/web-platform/test/infra/egress-gw-alert.test.sh\n"; assert s.count(k) == 1; wr(p, s.replace(k, k + "        env:\n          GUARD_TF: /dev/null\n"))'
  mut red "M-26b: GUARD_SCRIPTS_DIR at JOB level" "job sets a *_GUARD_* env" ovr \
    'p = wf; s = rd(p); k = "  deploy-script-tests-fixed:\n"; assert s.count(k) == 1; wr(p, s.replace(k, k + "    env:\n      GUARD_SCRIPTS_DIR: /dev/null\n"))'
  mut red "M-26c: GUARD_VECTOR_TOML at WORKFLOW level" "workflow-level *_GUARD_* env" ovr \
    'p = wf; s = rd(p); k = "\nenv:\n"; assert s.count(k) == 1; wr(p, s.replace(k, k + "  GUARD_VECTOR_TOML: /dev/null\n"))'
  mut red "M-27a: a root module block with a remote (git) source" "non-local module source" ovr \
    'p = os.path.join(root, "dns.tf"); wr(p, rd(p) + "\nmodule \"zz_remote\" {\n  source = \"git::https://example.invalid/m.git//x\"\n}\n")'
  mut red "M-27b: a root module block whose source escapes the root (../elsewhere)" "non-local module source" ovr \
    'p = os.path.join(root, "network.tf"); wr(p, rd(p) + "\nmodule \"zz_escape\" {\n  source = \"../elsewhere\"\n}\n")'
  mut red "M-28: resource\"logtail_exploration_alert\" with NO space after resource (valid HCL the enumerator sed cannot see)" "un-enumerated" ovr \
    's = rd(BT); wr(BT, s + "\nresource\"logtail_exploration_alert\" \"zz_nospace\" {\n}\n")'
  mut red "M-29a: an echo line carries the -target= of a resource whose real line was deleted (text, not an argument)" "no -target= line in apply-web-platform-infra.yml" ovr \
    'p = awf; s = rd(p); k = "              -target=logtail_exploration.egress_gw_probe_fail \\\n"; assert s.count(k) == 1; wr(p, s.replace(k, "              echo \"-target=logtail_exploration.egress_gw_probe_fail\"\n"))'
  mut red "M-29b: the -target= of a deleted line survives only in a TRAILING comment" "no -target= line in apply-web-platform-infra.yml" ovr \
    'p = awf; s = rd(p); k = "              -target=logtail_exploration.egress_gw_probe_fail \\\n"; assert s.count(k) == 1; wr(p, s.replace(k, "              true # -target=logtail_exploration.egress_gw_probe_fail\n"))'
  mut red "M-30a: ALERT_STRUCT_INFRA in ANOTHER workflow of the repo (the check used to read infra-validation.yml only)" "zz-other.yml names ALERT_STRUCT_" fake \
    'wr(os.path.join(os.path.dirname(wf), "zz-other.yml"), "name: other\non: push\nenv:\n  ALERT_STRUCT_INFRA: /tmp/elsewhere\n")'
  mut red "M-30b: ALERT_STRUCT_INFRA exported by scripts/test-all.sh" "test-all.sh names ALERT_STRUCT_" fake \
    'rp = os.path.dirname(os.path.dirname(os.path.dirname(wf))); os.makedirs(os.path.join(rp, "scripts"), exist_ok=True); wr(os.path.join(rp, "scripts", "test-all.sh"), "#!/usr/bin/env bash\nexport ALERT_STRUCT_INFRA=/tmp/elsewhere\n")'
  mut red "M-31a: a symlink inside a NESTED .terraform directory (only the root's own .terraform is skipped)" "symlink under the infra root" ovr \
    'd = os.path.join(root, "modules", "x", ".terraform"); os.makedirs(d); os.symlink("../../../main.tf", os.path.join(d, "zz.tf"))'
  mut red "M-31b: the symlink scan's find fails (nonexistent start path): rc is read, never taken as 'no symlink'" "symlink scan: find exited" fake \
    - 's#find "\$INFRA" -type l#find "$INFRA/zz-gone" -type l#'
  mut red "M-31c: the subdirectory scan's find fails: rc is read, never taken as 'no logtail resource outside'" "subdirectory scan: find exited" fake \
    - 's#find "\$INFRA" -mindepth 2#find "$INFRA/zz-gone" -mindepth 2#'

  # ── must-PASS rows: legitimate edits must not red ────────────────────────────────────────────────
  mut pass "M-p1: attribute-order shuffle (check_period/query_period swapped in one alert)" - ovr \
    's = rd(BT); m = list(AH.finditer(s))[mid(s)]; a, b = span(s, m); blk = s[a:b]; x = re.search(r"(?m)^  check_period +=.*\n", blk).group(0); y = re.search(r"(?m)^  query_period +=.*\n", blk).group(0); blk2 = blk.replace(x, "@@X@@").replace(y, x).replace("@@X@@", y); assert blk2 != blk; wr(BT, s[:a] + blk2 + s[b:])'
  mut pass "M-p2: comments naming the forbidden words inside an alert (# lifecycle {, /* count */, // for_each)" - ovr \
    's = rd(BT); wr(BT, inject(s, mid(s), "  # lifecycle {\n  /* count = 1\n     for_each = [] */\n  // depends_on = [x]"))'
  mut pass "M-p3: a sql_query heredoc in an exploration containing count / for_each / lifecycle lines" - ovr \
    's = rd(BT); i = s.index("resource \"logtail_exploration\" "); j = s.index("    sql_query = ", i); k = s.index("\n", j); body = "    sql_query = <<-SQL\n      count = 1\n      for_each = 2\n      lifecycle {\n    SQL"; wr(BT, s[:j] + body + s[k:])'
  mut pass "M-p4: a lifecycle { line inside a heredoc inside an alert (incident_cause as a heredoc)" - ovr \
    's = rd(BT); a, b = span(s, list(AH.finditer(s))[mid(s)]); blk = s[a:b]; new = re.sub(r"(?m)^  incident_cause += .*\n", "  incident_cause = <<-EOT\n    lifecycle {\n    count = 1\n    dynamic \"x\" {\n  EOT\n", blk, count=1); assert new != blk; wr(BT, s[:a] + new + s[b:])'
  mut pass "M-p5: a re-spaced guard step (extra spaces after run:, trailing spaces, a commented if: and continue-on-error:)" - ovr \
    'p = wf; s = rd(p); k = "        run: bash apps/web-platform/test/infra/egress-gw-alert.test.sh\n"; assert s.count(k) == 1; wr(p, s.replace(k, "        run:    bash apps/web-platform/test/infra/egress-gw-alert.test.sh   \n        # if: always()\n        # continue-on-error: true\n"))'
  mut pass "M-p6: a moved {} block naming a NON-logtail address" - ovr \
    'p = os.path.join(root, "dns.tf"); wr(p, rd(p) + "\nmoved {\n  from = cloudflare_record.old_name\n  to   = cloudflare_record.new_name\n}\n")'
  mut pass "M-p7: OPTIONAL_ATTRS extended in the suite AND one alert uses that attribute" - fake \
    's = rd(BT); wr(BT, inject(s, mid(s), "  aggregation_interval = 300"))' \
    's/^OPTIONAL_ATTRS=""$/OPTIONAL_ATTRS="aggregation_interval"/'

  mut pass "M-p8: a -target line for a NON-logtail resource added to the apply workflow (the parity rows are scoped to logtail_*)" - ovr \
    'p = awf; s = rd(p); k = "              -target=logtail_exploration.egress_gw_probe_fail \\\n"; assert s.count(k) == 1; wr(p, s.replace(k, k + "              -target=cloudflare_record.zz_extra \\\n"))'
  mut pass "M-p9: a subdirectory .tf declaring a NON-logtail resource and one that only names logtail in a comment" - ovr \
    'd = os.path.join(root, "sentry"); os.makedirs(d); wr(os.path.join(d, "zz.tf"), "# resource \"logtail_exploration\" \"c\" {\nresource \"null_resource\" \"zz\" {\n}\n")'
  MUT_FLAG=--census-only mut pass "M-p10: --census-only runs ONLY the census rows (a planted zz_override.tf, which row 12 reds, does not fail it)" - ovr \
    'wr(os.path.join(root, "zz_override.tf"), "# merged over the reviewed text\n")'

  mut pass "M-p11: a root module block with a LOCAL ./modules source (the git-data shape) stays green" - ovr \
    'p = os.path.join(root, "dns.tf"); wr(p, rd(p) + "\nmodule \"zz_local\" {\n  source = \"./modules/zz-local\"\n}\n")'
  mut pass "M-p12: a job-level name:, and a benign workflow-level env name, stay green (the allow-list is not a blanket reject)" - ovr \
    'p = wf; s = rd(p); k = "  deploy-script-tests-fixed:\n"; assert s.count(k) == 1; s = s.replace(k, k + "    name: guard job\n"); k = "\nenv:\n"; assert s.count(k) == 1; wr(p, s.replace(k, k + "  UNRELATED_FLAG: \"1\"\n"))'

  # ── harness rows ──────────────────────────────────────────────────────────────────────────────────
  mut fatal "M-a: the suite's ok() stops moving its counter: the instrument self-test must refuse to run" - fake - \
    's/^ok() { pass=\$((pass + 1)); /ok() { /'
  mut red "M-b: strip_comments neutered to the identity: the must-PASS comment row flips RED (proves it exercises the lexer)" "meta-argument" fake \
    's = rd(BT); wr(BT, inject(s, mid(s), "  # lifecycle {\n  /* count = 1\n     for_each = [] */\n  // depends_on = [x]"))' \
    "" 'strip_comments() { cat "$1"; }'
  mut red "M-b2: blank_heredocs neutered to the identity: the must-PASS heredoc row flips RED (proves it exercises the heredoc lexer)" "meta-argument" fake \
    's = rd(BT); a, b = span(s, list(AH.finditer(s))[mid(s)]); blk = s[a:b]; new = re.sub(r"(?m)^  incident_cause += .*\n", "  incident_cause = <<-EOT\n    lifecycle {\n    count = 1\n  EOT\n", blk, count=1); assert new != blk; wr(BT, s[:a] + new + s[b:])' \
    "" 'blank_heredocs() { cat; }'
  mut red "M-c: block_of neutered to print nothing: an unreadable block set must never read as green" "no extractable block" fake - \
    "" 'block_of() { :; }'
  grade_all

  # ── direct rows (not mutations of a copy) ────────────────────────────────────────────────────────
  # M-census: the discoverability probe on the PRISTINE tree exits 0 and prints the `N passed, 0 failed` line.
  _cl="$MUT_DIR/census.log"; _crc=0; bash "$SELF" --census-only >"$_cl" 2>&1 || _crc=$?
  if [ "$_crc" -eq 0 ] && [ "$(grep -c 'passed, 0 failed' "$_cl")" -ge 1 ]; then
    ok "M-census: --census-only exits 0 on the pristine tree and prints 'passed, 0 failed'"
  else
    no "M-census: --census-only on the pristine tree exited $_crc without a 'passed, 0 failed' line: $(sed -n '$p' "$_cl")"
  fi
  # M-flake: the pipe-free reader (fail_line_has) must never false-negative on a log whose first line carries the tag
  # and whose remainder is far larger than the pipe buffer, 200 runs in a row. The legacy `| grep -q` form is run 20
  # times for information only: whether it false-negatives depends on the host's pipe capacity and load, so its count
  # is reported, never asserted.
  _legacy_fail_line_has() { grep -F '[FAIL]' "$1" | grep -qF -- "$2"; }
  _fl="$MUT_DIR/flake.log"
  { printf '[FAIL] M-flake-tag on the first line\n'
    awk 'BEGIN { for (i = 0; i < 4000; i++) printf "[FAIL] filler line %d padding padding padding padding padding\n", i }'; } > "$_fl"
  _flsize="$(wc -c < "$_fl")"; _fl_new=0; _fl_old=0
  for _i in $(seq 1 200); do fail_line_has "$_fl" "M-flake-tag" || _fl_new=$((_fl_new + 1)); done
  for _i in $(seq 1 20); do _legacy_fail_line_has "$_fl" "M-flake-tag" || _fl_old=$((_fl_old + 1)); done
  if [ "$_flsize" -gt 65536 ] && [ "$_fl_new" -eq 0 ]; then
    ok "M-flake: fail_line_has found the tag in 200 of 200 runs on a ${_flsize}-byte log (informational: the legacy grep -q form missed it $_fl_old of 20 here)"
  else
    no "M-flake: fail_line_has false-negatives $_fl_new of 200 (want 0), log $_flsize bytes (want >65536; informational legacy misses $_fl_old of 20)"
  fi
  # M-scorer: negative control for the row scorer (fail_line_has decides "red for the RIGHT reason"). It must accept a
  # [FAIL] line holding the fragment, and must REFUSE a fragment that is only in an [ok] line and one that no line holds.
  _sc="$MUT_DIR/scorer.log"; printf '[ok] wrong-reason-frag\n[FAIL] some other defect\n[FAIL] right-reason-frag here\n' > "$_sc"
  if fail_line_has "$_sc" "right-reason-frag" && ! fail_line_has "$_sc" "wrong-reason-frag" && ! fail_line_has "$_sc" "absent-frag"; then
    ok "M-scorer: fail_line_has grades a [FAIL] line holding the fragment RIGHT and a fragment found only in an [ok] line or nowhere WRONG"
  else
    no "M-scorer: fail_line_has no longer separates the right reason from the wrong one (a row that reds for the wrong reason would pass)"
  fi
fi

# PRESENCE_ROWS is exactly the count of presence rows an inner (--presence-only) run asserts; the outer run
# adds one row per `mut` call (MUT_N) plus BATTERY_DIRECT_ROWS direct rows. The instrument control above is what
# catches a floor that drifts past the presence rows (that control, not this comment, is the guard against a dead battery).
PRESENCE_ROWS=24
MUT_ROWS=83
BATTERY_DIRECT_ROWS=3
_floor=$PRESENCE_ROWS
if [ -z "$PRESENCE_ONLY" ]; then
  [ "${MUT_N:-0}" -eq "$MUT_ROWS" ] || { printf '[FATAL] mutation row count: ran %s, MUT_ROWS %s\n' "${MUT_N:-0}" "$MUT_ROWS" >&2; exit 1; }
  _floor=$((PRESENCE_ROWS + MUT_ROWS + BATTERY_DIRECT_ROWS))
  [ "$(_snap)" = "$SNAP_BEFORE" ] || no "instrument: the battery wrote to the real infra root or workflows (checksum changed)"
fi
_ran=$((pass + fail))
if [ "$_ran" -lt "$_floor" ]; then printf '[FATAL] assertion floor: %s ran, floor %s\n' "$_ran" "$_floor" >&2; exit 1; fi
if [ "${#FAILED[@]}" -ne "$fail" ]; then printf '[FATAL] ledger %s != fail counter %s\n' "${#FAILED[@]}" "$fail" >&2; exit 1; fi
printf '\n=== betterstack-alert-structure: %s passed, %s failed (%s assertions, floor %s) ===\n' "$pass" "$fail" "$_ran" "$_floor"
[ "$fail" -eq 0 ]
