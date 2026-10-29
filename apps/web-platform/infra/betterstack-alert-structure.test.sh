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
# in EVERY *.tf of the infra root (presence rows 1-18 below, each one verdict over the whole set):
#   1-3   census: at least 19 alerts and 19 explorations, and every enumerated header yields a block
#         (a header `block_of` cannot extract would otherwise be invisible to every row after it)
#   4-6   closed attribute set: top-level keys of each alert equal REQUIRED_ATTRS + OPTIONAL_ATTRS, plus
#         exactly one `escalation_target` block. No family-wide attribute VALUE pins: the per-alert guards
#         own `push`, `call`, the windows and the SQL.
#   7     no `lifecycle`, `count`, `for_each`, `provider`, `depends_on` or `dynamic` anywhere in a block
#   8-9   one alert per exploration, and the alert's resource name equals the exploration it binds
#   10    no `removed`, `moved` or `import` block names a logtail_exploration* address
#   11    no `*override.tf`, `*override.tf.json` or `*.tf.json` in the root
#   12-13 provider tripwire: the lock's `logtail` constraint equals main.tf's literal and the lock version
#         equals PROVIDER_LOCK_VERSION below (a tripwire, NOT an integrity proof)
#   14-16 CI pin: every apps/web-platform/test/infra/*alert*.test.sh is a plain `bash <path>` step in
#         infra-validation.yml with no step-level `if:`, `continue-on-error:` or `*_GUARD_*` env, and its
#         job carries no `continue-on-error:`, `*_GUARD_*` env or `if:` other than the job's one legitimate
#         dedup gate (JOB_IF_ALLOWED). Line-based awk, no PyYAML. This is the suite's second chokepoint
#         (the first is logtail_blocks / block_text); Arm 3b of
#         .github/scripts/test/test-infra-suite-registration.sh is NOT widened to cover it.
#   17-18 predicate controls: synthetic blocks prove the meta-argument and attribute-set predicates pass a
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
# covers this file). It also proves TEXT, not live Better Stack state. This suite's OWN wiring is protected
# only by the registration gate (Arm 3b); the CI-pin rows above cover the per-alert guards, not this file.
#
# MUTATION BATTERY (bottom of file). Each row copies the tree into a scratch dir under $TMPDIR, mutates the
# COPY, re-runs this suite against it through ALERT_STRUCT_{INFRA,WF,GUARDS} (or, for the harness rows that
# edit the suite or the lexer itself, through a scratch repo skeleton), and requires rc=1 plus the row's own
# FAIL text. rc>=2 is the instrument, not evidence. Tracked files are never written; a checksum of the real
# infra root and workflow is compared at exit (git diff is not used: a dirty worktree must not fail it).
#
# Usage: bash apps/web-platform/infra/betterstack-alert-structure.test.sh [--presence-only]
#   --presence-only skips the mutation battery (the inner runs use it; so does the discoverability probe).
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

PRESENCE_ONLY=""
for _a in "$@"; do
  case "$_a" in
    --presence-only) PRESENCE_ONLY=1 ;;
    *) printf 'FATAL: unknown argument %s (only --presence-only)\n' "$_a" >&2; exit 2 ;;
  esac
done

# ── pins (same file, same diff as what they protect: tripwires, see the header) ────────────────────
REQUIRED_ATTRS="alert_type call check_period confirmation_period critical_alert email exploration_id incident_cause metadata name on_missing_data operator paused push query_period recovery_period sms value"
OPTIONAL_ATTRS=""
CENSUS_FLOOR_ALERTS=19
CENSUS_FLOOR_EXPLORATIONS=19
GUARD_CENSUS_FLOOR=15
PROVIDER_LOCK_VERSION="11.2.0"
JOB_IF_ALLOWED="needs.detect-changes.outputs.pr_duplicate != 'true'"
META_RE='(^|\{)[[:space:]]*(lifecycle|count|for_each|provider|depends_on|dynamic)[[:space:]]*(=|\{|")'

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SELF="$DIR/$(basename "${BASH_SOURCE[0]}")"
REPO="$(cd "$DIR/../../.." && pwd)"

# Overrides exist for the mutation battery. An override that is SET but EMPTY would silently fall back to the
# real tree and grade it as "mutated", so it is refused outright.
for _v in ALERT_STRUCT_INFRA ALERT_STRUCT_WF ALERT_STRUCT_GUARDS; do
  if [ "${!_v+set}" = set ] && [ -z "${!_v}" ]; then
    printf 'FATAL: %s is set but EMPTY; refusing (it would fall back to the real tree)\n' "$_v" >&2; exit 2
  fi
done
INFRA="${ALERT_STRUCT_INFRA:-$DIR}"
WF="${ALERT_STRUCT_WF:-$REPO/.github/workflows/infra-validation.yml}"
GUARDS="${ALERT_STRUCT_GUARDS:-$REPO/apps/web-platform/test/infra}"
HCL_LIB="$REPO/tests/scripts/lib/hcl-effective-text.sh"

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
assert_fixture_dir "$REPO"; assert_fixture_dir "$INFRA"; assert_fixture_dir "$WF"; assert_fixture_dir "$GUARDS"
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
[ -d "$INFRA" ] && [ -d "$GUARDS" ] && [ -r "$WF" ] \
  || { printf 'FATAL: unreadable input (infra %s, guards %s, workflow %s)\n' "$INFRA" "$GUARDS" "$WF" >&2; exit 2; }

WORK="$(mktemp -d -t alertstruct.XXXXXX)" || { printf '[FATAL] mktemp failed\n' >&2; exit 2; }
assert_fixture_dir "$WORK"
trap 'rm -rf "$WORK"' EXIT

# ── the chokepoint ─────────────────────────────────────────────────────────────────────────────────
# logtail_blocks prints `file|type|name` for every logtail_exploration(_alert) header in every *.tf of the
# root, read from the comment- and heredoc-blind view. A header with leading whitespace is still a header
# (HCL ignores indentation); block_text then cannot extract it and presence row 3 reds it.
logtail_blocks() {
  local f
  for f in "$INFRA"/*.tf; do
    [ -e "$f" ] || continue
    strip_comments "$f" | blank_heredocs \
      | sed -nE 's/^[[:space:]]*resource[[:space:]]+"(logtail_exploration(_alert)?)"[[:space:]]+"([^"]+)".*/\1|\3/p' \
      | while IFS='|' read -r t n; do printf '%s|%s|%s\n' "$f" "$t" "$n"; done
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
meta_hits_of() { awk "$HCL_AWK_FUNCS"'{ print cv($0) }' <<<"$1" | grep -E "$META_RE" | sed 's/^[[:space:]]*//' | head -n 3 | tr '\n' ' '; }
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

lock_field() {  # lock_field <version|constraints> -> value of the logtail provider entry in the lock
  awk -v f="$1" '/^provider "registry.terraform.io\/betterstackhq\/logtail" \{/ { i = 1; next }
    i && /^\}/ { exit }
    i && $1 == f { v = $0; sub(/^[^"]*"/, "", v); sub(/".*$/, "", v); print v }' "$INFRA/.terraform.lock.hcl" 2>/dev/null
}
main_constraint() {
  strip_comments "$INFRA/main.tf" 2>/dev/null | blank_heredocs \
    | awk '/^[[:space:]]*logtail[[:space:]]*=[[:space:]]*\{/ { i = 1; next }
      i && /\}/ { exit }
      i && $1 == "version" { v = $0; sub(/^[^"]*"/, "", v); sub(/".*$/, "", v); print v }'
}

# CI pin: for ONE guard path, prints one reason line per defect. `W:` = not wired as a plain step,
# `M:` = masked. Empty output = wired plainly and unmasked.
ci_pin_of() {  # ci_pin_of <workflow> <repo-relative guard path>
  awk -v P="$2" -v JOBIF="$JOB_IF_ALLOWED" '
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
        for (m = dash; m < k; m++) {
          if (cmt(L[m])) continue
          if (L[m] ~ /^[[:space:]]*(-[[:space:]]+)?(if|continue-on-error):/) print "M:step has " (L[m] ~ /continue-on-error/ ? "continue-on-error" : "if")
          if (L[m] ~ /_GUARD_/) print "M:step sets a *_GUARD_* env"
        }
        job = 0
        for (j = dash; j >= 1; j--) {
          if (!blank(L[j]) && !cmt(L[j]) && ind(L[j]) == 0) break
          if (L[j] ~ /^  [A-Za-z0-9_-]+:[[:space:]]*$/) { job = j; break }
        }
        if (!job) { print "W:cannot locate the job"; continue }
        for (m = job + 1; m <= NR; m++) {
          if (L[m] ~ /^    steps:/) break
          if (cmt(L[m])) continue
          if (L[m] ~ /^    continue-on-error:/) print "M:job has continue-on-error"
          if (L[m] ~ /_GUARD_/) print "M:job sets a *_GUARD_* env"
          if (L[m] ~ /^    if:/) { v = L[m]; sub(/^    if:[[:space:]]*/, "", v); sub(/[[:space:]]+$/, "", v); if (v != JOBIF) print "M:job has an if: other than the dedup gate" }
        }
        for (m = 1; m <= NR; m++) {
          if (L[m] ~ /^jobs:/) break
          if (!cmt(L[m]) && L[m] ~ /_GUARD_/) print "M:workflow-level *_GUARD_* env"
        }
      }
    }' "$1" | sort -u
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

join() { local IFS='; '; printf '%s' "$*"; }

# ── 1-3 census ─────────────────────────────────────────────────────────────────────────────────────
[ "$NA" -ge "$CENSUS_FLOOR_ALERTS" ] \
  && ok "census floor: $NA logtail_exploration_alert blocks enumerated (floor $CENSUS_FLOOR_ALERTS)" \
  || no "census floor: only $NA logtail_exploration_alert blocks enumerated (floor $CENSUS_FLOOR_ALERTS): 0 checked must never read as green; edit the census floor with a legitimate removal"
[ "$NE" -ge "$CENSUS_FLOOR_EXPLORATIONS" ] \
  && ok "census floor: $NE logtail_exploration blocks enumerated (floor $CENSUS_FLOOR_EXPLORATIONS)" \
  || no "census floor: only $NE logtail_exploration blocks enumerated (floor $CENSUS_FLOOR_EXPLORATIONS): edit the census floor with a legitimate removal"
[ "${#NOBLOCK[@]}" -eq 0 ] \
  && ok "every enumerated header yields an extractable block" \
  || no "no extractable block for: $(join "${NOBLOCK[@]}"): the header is indented or malformed and every row below would skip it; start the resource at column 0"

# ── 4-6 closed attribute set ───────────────────────────────────────────────────────────────────────
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

# ── 7 no meta-arguments ────────────────────────────────────────────────────────────────────────────
_meta=()
for _k in "${!BLK[@]}"; do
  _h="$(meta_hits_of "${BLK[$_k]}")"; [ -z "$_h" ] || _meta+=("${_k#*|} (${_k%%|*}): ${_h% }")
done
[ "${#_meta[@]}" -eq 0 ] \
  && ok "no lifecycle/count/for_each/provider/depends_on/dynamic in any enumerated block" \
  || no "meta-argument in a logtail block: $(join "${_meta[@]}"): remove it; the family guards read the declared text only"

# ── 8-9 one alert per exploration, names agree ─────────────────────────────────────────────────────
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

# ── 10 no state surgery ────────────────────────────────────────────────────────────────────────────
_sur=()
for _f in "$INFRA"/*.tf; do
  [ -e "$_f" ] || continue
  [ -z "$(surgery_in "$_f")" ] || _sur+=("$(basename "$_f")")
done
[ "${#_sur[@]}" -eq 0 ] \
  && ok "no removed/moved/import block names a logtail_exploration or logtail_exploration_alert address" \
  || no "state surgery: $(join "${_sur[@]}") has a removed/moved/import block naming a logtail address: delete the block"

# ── 11 no override files ───────────────────────────────────────────────────────────────────────────
[ "$(p_b4_no_override_files "$INFRA")" = 1 ] \
  && ok "no *override.tf / *override.tf.json / *.tf.json in the infra root" \
  || no "override file present in the infra root ($(cd "$INFRA" && ls -- *override.tf *.tf.json 2>/dev/null | tr '\n' ' ')): Terraform merges it over the reviewed text; delete it"

# ── 12-13 provider tripwire ────────────────────────────────────────────────────────────────────────
_lc="$(lock_field constraints)"; _lv="$(lock_field version)"; _mc="$(main_constraint)"
[ -n "$_lc" ] && [ "$_lc" = "$_mc" ] \
  && ok "provider: lock constraints \"$_lc\" equals main.tf's logtail version literal" \
  || no "provider lock constraints \"$_lc\" != main.tf logtail version \"$_mc\": edit the two together with the bump"
[ -n "$_lv" ] && [ "$_lv" = "$PROVIDER_LOCK_VERSION" ] \
  && ok "provider: lock version \"$_lv\" equals PROVIDER_LOCK_VERSION (a tripwire, not an integrity proof)" \
  || no "provider lock version \"$_lv\" != PROVIDER_LOCK_VERSION \"$PROVIDER_LOCK_VERSION\": edit the two provider constants with the bump"

# ── 14-16 CI pin ───────────────────────────────────────────────────────────────────────────────────
GUARD_LIST=()
for _g in "$GUARDS"/*alert*.test.sh; do [ -e "$_g" ] && GUARD_LIST+=("apps/web-platform/test/infra/$(basename "$_g")"); done
[ "${#GUARD_LIST[@]}" -ge "$GUARD_CENSUS_FLOOR" ] \
  && ok "guard census: ${#GUARD_LIST[@]} alert guards enumerated (floor $GUARD_CENSUS_FLOOR)" \
  || no "guard census: only ${#GUARD_LIST[@]} alert guards enumerated (floor $GUARD_CENSUS_FLOOR): edit GUARD_CENSUS_FLOOR with the removal"
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
  && ok "CI pin: no alert-guard step or job is masked (if:, continue-on-error:, *_GUARD_* env)" \
  || no "CI pin masked: $(join "${_mk[@]}"): restore the plain 'bash <path>' step with no if:/continue-on-error:/*_GUARD_* env"

# ── 17-18 predicate controls (synthetic blocks through the SAME chokepoint) ─────────────────────────
_ctl="$WORK/ctl.tf"
{
  echo 'resource "logtail_exploration_alert" "ctl_ok" {'
  echo '  # lifecycle { prevent_destroy = true }'
  echo '  /* count = 1 */'
  echo '  // for_each = []'
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
  _snap() { { find "$INFRA" -maxdepth 1 -type f \( -name '*.tf' -o -name '*.tf.json' -o -name '.terraform.lock.hcl' \) -print0 | sort -z | xargs -0 sha256sum; sha256sum "$WF"; } | sha256sum; }
  SNAP_BEFORE="$(_snap)"

  # INSTRUMENT CONTROL - the inner run against the PRISTINE tree must exit 0, or every row below would grade a
  # broken invocation as "mutation RED".
  ctl_rc=0; bash "$SELF" --presence-only >"$MUT_DIR/control.log" 2>&1 || ctl_rc=$?
  if [ "$ctl_rc" -ne 0 ]; then
    printf '[FATAL] instrument control: the inner run exited %s on the PRISTINE tree - the battery cannot be trusted:\n' "$ctl_rc" >&2
    sed 's/^/    /' "$MUT_DIR/control.log" >&2; exit 2
  fi

  _in_mut() { local p; p="$(realpath -m -- "$1")"; case "$p" in "$MUT_REAL"/*) return 0 ;; esac; return 1; }
  _dsum() { ( cd "$1" && find . -type f -print0 | sort -z | xargs -0 sha256sum | sha256sum ); }

  PRELUDE='import re, sys, os
root, wf = sys.argv[1], sys.argv[2]
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
def last(s): return len(list(AH.finditer(s))) - 1
def mid(s): return len(list(AH.finditer(s))) // 2'

  fake_root() {  # fake_root <dir>: a scratch repo skeleton built from the real tree (suite, lexer, infra, workflow, guard names)
    local r="$1" g
    _in_mut "$r" || { printf '[FATAL] fake_root outside MUT_DIR: %s\n' "$r" >&2; exit 2; }
    mkdir -p "$r/apps/web-platform/infra" "$r/tests/scripts/lib" "$r/.github/workflows" "$r/apps/web-platform/test/infra" || exit 2
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
    local w root wf suite b0 b1 w0 w1
    MUT_N=$(( ${MUT_N:-0} + 1 )); MUT_ROWS_RUN=$(( ${MUT_ROWS_RUN:-0} + 1 ))
    w="$MUT_DIR/s$MUT_N"; _in_mut "$w" || { printf '[FATAL] scratch %s outside MUT_DIR\n' "$w" >&2; exit 2; }
    mkdir -p "$w" || exit 2
    if [ "$kind" = ovr ]; then
      root="$w/infra"; wf="$w/infra-validation.yml"; suite="$SELF"
      mkdir -p "$root" || exit 2
      cp -P "$INFRA"/*.tf "$root/" || exit 2
      cp -P "$INFRA/.terraform.lock.hcl" "$root/" || exit 2
      cp -P "$WF" "$wf" || exit 2
    else
      fake_root "$w/repo"
      root="$w/repo/apps/web-platform/infra"; wf="$w/repo/.github/workflows/infra-validation.yml"
      suite="$root/betterstack-alert-structure.test.sh"
      if [ -n "$ssed" ]; then
        cp -P "$suite" "$suite.orig" && sed -i "$ssed" "$suite" && ! cmp -s "$suite" "$suite.orig" \
          || { no "mutation '$label' did not land (suite sed matched nothing)"; return 0; }
        rm -f "$suite.orig"
      fi
      if [ -n "$libapp" ]; then printf '\n%s\n' "$libapp" >> "$w/repo/tests/scripts/lib/hcl-effective-text.sh"; fi
    fi
    b0="$(_dsum "$root")"; w0="$(sha256sum < "$wf")"
    if [ "$prog" != "-" ]; then
      printf '%s\n%s\n' "$PRELUDE" "$prog" > "$w/mut.py"
      python3 "$w/mut.py" "$root" "$wf" || { no "mutation '$label' did not land (the python program failed)"; return 0; }
      b1="$(_dsum "$root")"; w1="$(sha256sum < "$wf")"
      if [ "$b0" = "$b1" ] && [ "$w0" = "$w1" ]; then no "mutation '$label' produced no change"; return 0; fi
    fi
    # Inner runs execute concurrently (each is a ~7 s lexer pass); grading happens in grade_all, in row order.
    if [ "$kind" = ovr ]; then
      [ -n "$root" ] && [ -n "$wf" ] || { printf '[FATAL] mut: empty override path\n' >&2; exit 2; }
      local gd="$GUARDS"
      if [ -n "${MUT_GUARDS_EMPTY:-}" ]; then gd="$w/noguards"; mkdir -p "$gd" || exit 2; fi
      ( rc=0; ALERT_STRUCT_INFRA="$root" ALERT_STRUCT_WF="$wf" ALERT_STRUCT_GUARDS="$gd" bash "$suite" --presence-only >"$w/out.log" 2>&1 || rc=$?; echo "$rc" > "$w/rc" ) &
    else
      ( rc=0; env -u ALERT_STRUCT_INFRA -u ALERT_STRUCT_WF -u ALERT_STRUCT_GUARDS bash "$suite" --presence-only >"$w/out.log" 2>&1 || rc=$?; echo "$rc" > "$w/rc" ) &
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
          if [ "$tag" = "-" ] || grep -F '[FAIL]' "$w/out.log" | grep -qF -- "$tag"; then ok "mutation RED: $label"
          else no "mutation went red for the WRONG reason (no [FAIL] line contains '$tag'): $label"; fi ;;
        pass:0) ok "must-PASS stays green: $label" ;;
        fatal:2) ok "instrument refuses (rc 2): $label" ;;
        red:0) no "mutation SURVIVED: $label - the rows above pin nothing" ;;
        pass:1) no "legitimate shape went RED: $label - $(grep -F '[FAIL]' "$w/out.log" | head -n 1)" ;;
        *) no "mutation UNRESOLVED (want $want, inner rc=$rc, not an assertion): $label - instrument, not evidence" ;;
      esac
    done
  }
  PEND_WANT=(); PEND_LABEL=(); PEND_TAG=(); PEND_DIR=()
  MUT_JOBS="$(nproc 2>/dev/null || echo 2)"; [ "$MUT_JOBS" -le 6 ] || MUT_JOBS=6; [ "$MUT_JOBS" -ge 1 ] || MUT_JOBS=2

  # ── Guard 1 matrix ────────────────────────────────────────────────────────────────────────────────
  mut red "row 1: a zz_override.tf planted in the infra root" "override" ovr \
    'wr(os.path.join(root, "zz_override.tf"), "# merged over the reviewed text\n")'
  mut red "row 2: a *.tf.json planted in the infra root" "override" ovr \
    'wr(os.path.join(root, "zz.tf.json"), "{}\n")'
  mut red "row 3a: lifecycle { ignore_changes } on the LAST alert (a check that stops at the first member is itself the defect)" "meta-argument" ovr \
    's = rd(BT); wr(BT, inject(s, last(s), "  lifecycle {\n    ignore_changes = [query_period]\n  }"))'
  mut red "row 3b: count = 0 on a MIDDLE alert" "meta-argument" ovr \
    's = rd(BT); wr(BT, inject(s, mid(s), "  count = 0"))'
  mut red "row 3c: for_each on the FIRST alert" "meta-argument" ovr \
    's = rd(BT); wr(BT, inject(s, 0, "  for_each = toset([])"))'
  mut red "row 4a: aggregation_interval = 300 on one alert (unknown key)" "OPTIONAL_ATTRS" ovr \
    's = rd(BT); wr(BT, inject(s, mid(s) + 1, "  aggregation_interval = 300"))'
  mut red "row 4b: a dynamic \"escalation_target\" block on another alert (sibling-block axis)" "block:dynamic" ovr \
    's = rd(BT); wr(BT, inject(s, 2, "  dynamic \"escalation_target\" {\n    for_each = []\n    content {\n    }\n  }"))'
  mut red "row 4c: a second escalation_target block on one alert" "escalation_target blocks" ovr \
    's = rd(BT); wr(BT, inject(s, 3, "  escalation_target {\n    team_name = \"Your team\"\n  }"))'
  mut red "row 5: push deleted from one alert (missing required key)" "missing required key" ovr \
    's = rd(BT); a, b = span(s, list(AH.finditer(s))[mid(s)]); blk = s[a:b]; new = re.sub(r"(?m)^  push +=.*\n", "", blk, count=1); assert new != blk; wr(BT, s[:a] + new + s[b:])'
  mut red "row 6: a second alert (probe2) bound to an EXISTING exploration" "is referenced by 2 alerts" ovr \
    's = rd(BT); t = alert_text(s, last(s)); m = AH.search(t); nm = m.group(1); t2 = t.replace("\"" + nm + "\" {", "\"" + nm + "_probe2\" {", 1); wr(BT, s + "\n" + t2)'
  mut red "row 7: a moved {} block naming a logtail_exploration_alert address, in a DIFFERENT *.tf (removed/import share the one header matcher)" "state surgery" ovr \
    'p = os.path.join(root, "dns.tf"); wr(p, rd(p) + "\nmoved {\n  from = logtail_exploration_alert.old_name\n  to   = logtail_exploration_alert.new_name\n}\n")'
  mut red "row 7b: a removed {} block naming a logtail_exploration address (multi-line form)" "state surgery" ovr \
    'p = os.path.join(root, "network.tf"); wr(p, rd(p) + "\nremoved {\n  from = logtail_exploration.old_name\n  lifecycle {\n    destroy = false\n  }\n}\n")'
  mut red "row 8: the lock's logtail version bumped" "provider lock version" ovr \
    'p = os.path.join(root, ".terraform.lock.hcl"); s = rd(p); i = s.index("betterstackhq/logtail"); j = s.index("\"11.2.0\"", i); wr(p, s[:j] + "\"11.2.1\"" + s[j + 8:])'
  mut red "row 8b: main.tf's logtail constraint literal changed away from the lock's" "provider lock constraints" ovr \
    'p = os.path.join(root, "main.tf"); s = rd(p); i = s.index("BetterStackHQ/logtail"); j = s.index("~> 11.2", i); wr(p, s[:j] + "~> 11.3" + s[j + 7:])'
  mut red "row 9a: continue-on-error: true on one alert-guard step" "masked" ovr \
    'p = wf; s = rd(p); k = "        run: bash apps/web-platform/test/infra/egress-gw-alert.test.sh\n"; assert s.count(k) == 1; wr(p, s.replace(k, k + "        continue-on-error: true\n"))'
  mut red "row 9b: another alert-guard step deleted" "no step runs it" ovr \
    'p = wf; s = rd(p); n = re.subn(r"(?m)^      - name: [^\n]*\n        run: bash apps/web-platform/test/infra/ghcr-blocked-alert\.test\.sh\n", "", s); assert n[1] == 1; wr(p, n[0])'
  mut red "row 9c: a step-level if: on a third alert-guard step" "step has if" ovr \
    'p = wf; s = rd(p); k = "        run: bash apps/web-platform/test/infra/sandbox-alerts.test.sh\n"; assert s.count(k) == 1; wr(p, s.replace(k, k + "        if: always() && false\n"))'
  mut red "row 9d: a *_GUARD_* env on a fourth alert-guard step" "*_GUARD_* env" ovr \
    'p = wf; s = rd(p); k = "        run: bash apps/web-platform/test/infra/ghcr-blocked-alert.test.sh\n"; assert s.count(k) == 1; wr(p, s.replace(k, k + "        env:\n          ALERT_GUARD_TF: /dev/null\n"))'
  mut red "row 9e: the guard job gains continue-on-error: true" "job has continue-on-error" ovr \
    'p = wf; s = rd(p); k = "  deploy-script-tests-fixed:\n"; assert s.count(k) == 1; wr(p, s.replace(k, k + "    continue-on-error: true\n"))'
  mut red "row 9f: the guard step is wrapped as bash <path> || true (not a plain run line)" "not a plain" ovr \
    'p = wf; s = rd(p); k = "        run: bash apps/web-platform/test/infra/web-nic-guard-unpinned-url-alert.test.sh\n"; assert s.count(k) == 1; wr(p, s.replace(k, "        run: bash apps/web-platform/test/infra/web-nic-guard-unpinned-url-alert.test.sh || true\n"))'
  mut red "row 10a: DISPATCH - an infra root with ZERO logtail_* blocks (floor RED, never 0 checked rc 0)" "census floor" ovr \
    'wr(BT, "# every logtail resource removed\n")'
  mut red "row 10b: one alert+exploration pair legitimately removed (the floor is exactly today's count)" "census floor" ovr \
    's = rd(BT); i = last(s); a, b = span(s, list(AH.finditer(s))[i]); nm = AH.search(s[a:b]).group(1); s = s[:a] + s[b:]; e = [m for m in EH.finditer(s) if m.group(1) == nm][0]; c, d = span(s, e); wr(BT, s[:c] + s[d:])'
  MUT_GUARDS_EMPTY=1 mut red "row 10c: an empty guard directory (the CI-pin census floor)" "guard census" ovr '-'
  mut red "row 11: an alert header indented by two spaces (block_of cannot extract it, so every row after would skip it)" "no extractable block" ovr \
    's = rd(BT); m = list(AH.finditer(s))[mid(s)]; wr(BT, s[:m.start()] + "  " + s[m.start():])'

  # ── must-PASS rows: legitimate edits must not red ────────────────────────────────────────────────
  mut pass "attribute-order shuffle (check_period/query_period swapped in one alert)" - ovr \
    's = rd(BT); m = list(AH.finditer(s))[mid(s)]; a, b = span(s, m); blk = s[a:b]; x = re.search(r"(?m)^  check_period +=.*\n", blk).group(0); y = re.search(r"(?m)^  query_period +=.*\n", blk).group(0); blk2 = blk.replace(x, "@@X@@").replace(y, x).replace("@@X@@", y); assert blk2 != blk; wr(BT, s[:a] + blk2 + s[b:])'
  mut pass "comments naming the forbidden words inside an alert (# lifecycle {, /* count */, // for_each)" - ovr \
    's = rd(BT); wr(BT, inject(s, mid(s), "  # lifecycle {\n  /* count = 1\n     for_each = [] */\n  // depends_on = [x]"))'
  mut pass "a sql_query heredoc in an exploration containing count / for_each / lifecycle lines" - ovr \
    's = rd(BT); i = s.index("resource \"logtail_exploration\" "); j = s.index("    sql_query = ", i); k = s.index("\n", j); body = "    sql_query = <<-SQL\n      count = 1\n      for_each = 2\n      lifecycle {\n    SQL"; wr(BT, s[:j] + body + s[k:])'
  mut pass "a lifecycle { line inside a heredoc inside an alert (incident_cause as a heredoc)" - ovr \
    's = rd(BT); a, b = span(s, list(AH.finditer(s))[mid(s)]); blk = s[a:b]; new = re.sub(r"(?m)^  incident_cause += .*\n", "  incident_cause = <<-EOT\n    lifecycle {\n    count = 1\n    dynamic \"x\" {\n  EOT\n", blk, count=1); assert new != blk; wr(BT, s[:a] + new + s[b:])'
  mut pass "a re-spaced guard step (extra spaces after run:, trailing spaces, a commented if: and continue-on-error:)" - ovr \
    'p = wf; s = rd(p); k = "        run: bash apps/web-platform/test/infra/egress-gw-alert.test.sh\n"; assert s.count(k) == 1; wr(p, s.replace(k, "        run:    bash apps/web-platform/test/infra/egress-gw-alert.test.sh   \n        # if: always()\n        # continue-on-error: true\n"))'
  mut pass "a moved {} block naming a NON-logtail address" - ovr \
    'p = os.path.join(root, "dns.tf"); wr(p, rd(p) + "\nmoved {\n  from = cloudflare_record.old_name\n  to   = cloudflare_record.new_name\n}\n")'
  mut pass "OPTIONAL_ATTRS extended in the suite AND one alert uses that attribute" - fake \
    's = rd(BT); wr(BT, inject(s, mid(s), "  aggregation_interval = 300"))' \
    's/^OPTIONAL_ATTRS=""$/OPTIONAL_ATTRS="aggregation_interval"/'

  # ── harness rows ──────────────────────────────────────────────────────────────────────────────────
  mut fatal "(a) the suite's ok() stops moving its counter: the instrument self-test must refuse to run" - fake - \
    's/^ok() { pass=\$((pass + 1)); /ok() { /'
  mut red "(b) strip_comments neutered to the identity: the must-PASS comment row flips RED (proves it exercises the lexer)" "meta-argument" fake \
    's = rd(BT); wr(BT, inject(s, mid(s), "  # lifecycle {\n  /* count = 1\n     for_each = [] */\n  // depends_on = [x]"))' \
    "" 'strip_comments() { cat "$1"; }'
  mut red "(b2) blank_heredocs neutered to the identity: the must-PASS heredoc row flips RED (proves it exercises the heredoc lexer)" "meta-argument" fake \
    's = rd(BT); a, b = span(s, list(AH.finditer(s))[mid(s)]); blk = s[a:b]; new = re.sub(r"(?m)^  incident_cause += .*\n", "  incident_cause = <<-EOT\n    lifecycle {\n    count = 1\n  EOT\n", blk, count=1); assert new != blk; wr(BT, s[:a] + new + s[b:])' \
    "" 'blank_heredocs() { cat; }'
  mut red "(c) block_of neutered to print nothing: an unreadable block set must never read as green" "no extractable block" fake - \
    "" 'block_of() { :; }'
  grade_all
fi

# PRESENCE_ROWS is exactly the count of presence rows an inner (--presence-only) run asserts; the outer run
# adds one row per mutation. The instrument control above is what catches a floor that drifts past
# the presence rows (that control, not this comment, is the guard against a dead battery).
PRESENCE_ROWS=18
MUT_ROWS=35
_floor=$PRESENCE_ROWS
if [ -z "$PRESENCE_ONLY" ]; then
  [ "${MUT_ROWS_RUN:-0}" -eq "$MUT_ROWS" ] || { printf '[FATAL] mutation row count: ran %s, MUT_ROWS %s\n' "${MUT_ROWS_RUN:-0}" "$MUT_ROWS" >&2; exit 1; }
  _floor=$((PRESENCE_ROWS + MUT_ROWS))
  [ "$(_snap)" = "$SNAP_BEFORE" ] || no "instrument: the battery wrote to the real infra root or workflow (checksum changed)"
fi
_ran=$((pass + fail))
if [ "$_ran" -lt "$_floor" ]; then printf '[FATAL] assertion floor: %s ran, floor %s\n' "$_ran" "$_floor" >&2; exit 1; fi
if [ "${#FAILED[@]}" -ne "$fail" ]; then printf '[FATAL] ledger %s != fail counter %s\n' "${#FAILED[@]}" "$fail" >&2; exit 1; fi
printf '\n=== betterstack-alert-structure: %s passed, %s failed (%s assertions, floor %s) ===\n' "$pass" "$fail" "$_ran" "$_floor"
[ "$fail" -eq 0 ]
