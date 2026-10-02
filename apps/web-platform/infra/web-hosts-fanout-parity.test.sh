#!/usr/bin/env bash
#
# Drift guard: EVERY workflow copy of the WEB_HOST_PRIVATE_IPS fan-out peer list
# (#5274 Phase 3 / ADR-068) MUST equal the set of private_ips in var.web_hosts
# (variables.tf). A drift means a deploy fans out to the wrong peers → a host
# silently ships stale code (single-user incident). There is ONE in-repo copy of
# this roster today and this guard covers it:
#   1. web-platform-release.yml — the tagged-release deploy fan-out (×1).
#
# reason: the two apply-web-platform-infra.yml copies lived in the `warm_standby` and
# `web_2_recreate` jobs, both DELETED with the web-2 dispatch sweep (#6575, 2026-07-20).
# The operand is KEPT at floor 0 rather than dropped.
#
# Keeping it at 0 was initially rejected as "vacuous", which was wrong and was measured
# wrong at review: `check_all_copies`'s third argument is a `-lt` FLOOR, not an equality
# check, and the per-copy content-comparison loop runs regardless of it. So floor 0 costs
# nothing today and keeps the roster check LIVE over any copy that ever reappears in that
# file. Measured: adding a job with a wrong roster (10.0.1.10,10.0.1.99) is INVISIBLE with
# the operand dropped and FAILS LOUD with it at 0.
#
# The extractor-break scenario that motivated dropping it is already covered by operand 2
# (floor 1) — breaking the IP regex fails that operand loudly.
#
# The multi-copy machinery is RETAINED deliberately: an earlier version extracted only the
# FIRST occurrence per file (`head -1`) and would have shipped a second copy un-guarded.
# Do not re-introduce head -1.
# Extracts EACH copy by shape and compares its sorted set to var.web_hosts.
#
# Run: bash apps/web-platform/infra/web-hosts-fanout-parity.test.sh
# Registered in .github/workflows/infra-validation.yml.

set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# WHP_* are seams of the SUITE (the self-test rows below feed mutated copies through them).
VARS_TF="${WHP_VARS_TF:-${DIR}/variables.tf}"
WORKFLOW="${DIR}/../../../.github/workflows/web-platform-release.yml"
APPLY_WORKFLOW="${DIR}/../../../.github/workflows/apply-web-platform-infra.yml"
CUTOVER_WORKFLOW="${WHP_CUTOVER_WORKFLOW:-${DIR}/../../../.github/workflows/git-data-cutover.yml}"

passes=0
fails=0
pass() { passes=$((passes + 1)); }
fail() { fails=$((fails + 1)); echo "FAIL: $1" >&2; }

[ -f "$VARS_TF" ] || { echo "FAIL: variables.tf not found at $VARS_TF" >&2; exit 1; }
[ -f "$WORKFLOW" ] || { echo "FAIL: workflow not found at $WORKFLOW" >&2; exit 1; }

# --- Operand 1: private_ips declared in var.web_hosts (variables.tf) ---
# Match `private_ip = "10.0.1.NN"` — the only shape these lines take. Sorted,
# newline-joined for a set comparison independent of declaration order.
tf_ips="$(grep -oE 'private_ip[[:space:]]*=[[:space:]]*"[0-9.]+"' "$VARS_TF" \
  | grep -oE '10\.0\.1\.[0-9]+' | sort -u)"

# --- WEB_HOST_PRIVATE_IPS extractor: emit ONE normalized IP-set (sorted,
# comma-joined) PER occurrence — one line per in-file copy — so EACH copy is
# checked independently. The prior `head -1` validated only the FIRST copy; a
# union-then-compare would also hide a copy that DROPS an IP (the union carries
# it from the sibling copy), so we compare per-copy.
extract_wf_ip_sets() {
  local file="$1" line
  grep -oE 'WEB_HOST_PRIVATE_IPS:[[:space:]]*"[0-9.,]+"' "$file" \
    | grep -oE '"[0-9.,]+"' | tr -d '"' \
    | while IFS= read -r line; do
        printf '%s\n' "$line" | tr ',' '\n' | grep -oE '10\.0\.1\.[0-9]+' | sort -u | paste -sd, -
      done
}

# --- Expected set: var.web_hosts private_ips, sorted + comma-joined to match the
# per-copy normalization above. Must itself be NON-EMPTY.
#
# This floor is an anti-PARSER-DRIFT tripwire, not a host-count policy: if the
# grep above stops matching variables.tf's shape, `tf_ips` silently empties and
# every parity assertion below would compare "" against "" and PASS — a green
# test proving nothing. The floor exists to make that failure loud.
#
# It was `-lt 2` until 2026-07-17 (#6538), which conflated "the parser works"
# with "there are two hosts". Retiring web-2 left ONE host and tripped it with
# "parser drift" — blaming the parser for a roster change it was not measuring.
# The correct floor is >=1: one host is a legitimate roster, zero is drift. ---
tf_n=$(printf '%s\n' "$tf_ips" | grep -c '.')
if [ "$tf_n" -lt 1 ]; then fail "extracted 0 private_ips from var.web_hosts — parser drift (the grep no longer matches variables.tf's shape; every assertion below would vacuously pass)"; fi
tf_set="$(printf '%s\n' "$tf_ips" | grep -E '.' | paste -sd, -)"

# --- Assert EVERY WEB_HOST_PRIVATE_IPS copy in a workflow equals var.web_hosts.
# min_copies pins the KNOWN copy count so a silently-removed copy (or a
# silent-empty extraction) fails loud instead of vacuously passing. ---
check_all_copies() {
  local file="$1" label="$2" min_copies="$3"
  local s i=0 n
  local sets=()
  mapfile -t sets < <(extract_wf_ip_sets "$file")
  n=${#sets[@]}
  if [ "$n" -lt "$min_copies" ]; then
    fail "$label: expected >=$min_copies WEB_HOST_PRIVATE_IPS copies, found $n — a copy was removed or the parser drifted"
    return
  fi
  for s in "${sets[@]}"; do
    i=$((i + 1))
    if [ "$s" = "$tf_set" ]; then
      pass
    else
      fail "$label copy #$i fan-out peer list drift: var.web_hosts=[$tf_set] copy=[$s]"
    fi
  done
}

# Operand 2: web-platform-release.yml — 1 copy (the tagged-release deploy fan-out).
check_all_copies "$WORKFLOW" "release-workflow" 1
# Operand 3: apply-web-platform-infra.yml — 2 copies (#8211 PR2: the inline pin_load steps in
# git_data_host_replace + git_data_host_create each fan the webhook redeploy to the full peer set).
check_all_copies "$APPLY_WORKFLOW" "apply-workflow" 2
# Operand 4: git-data-cutover.yml — 1 copy (the top-level env feeds the redeploy + finalizer steps;
# a fleet change that drops a peer here would silently produce a mixed-flag fleet).
check_all_copies "$CUTOVER_WORKFLOW" "cutover-workflow" 1

# Operand 5 (#8211): the per-host git_data_store= READBACK in git-data-cutover.yml names each host
# by its var.web_hosts KEY (`for h in "web-1|<host_name spellings>" "web-2|..."`). The readback needs
# a per-host Better Stack host_name map the IP list does not carry, so it is a literal — and a host
# added to var.web_hosts without a readback entry would be redeployed but never read back, leaving a
# mixed-flag fleet that no step reports. Compare the SET of keys, not their order.
tf_keys="$(grep -E '^[[:space:]]*"[A-Za-z0-9-]+"[[:space:]]*=[[:space:]]*\{.*private_ip' "$VARS_TF" \
  | grep -oE '^[[:space:]]*"[A-Za-z0-9-]+"' | tr -d ' "' | sort -u | paste -sd, -)"
rb_keys="$(grep -E '^[[:space:]]*for h in ' "$CUTOVER_WORKFLOW" \
  | grep -oE '"[A-Za-z0-9-]+\|' | tr -d '"|' | sort -u | paste -sd, -)"
rb_loops="$(grep -cE '^[[:space:]]*for h in ' "$CUTOVER_WORKFLOW")"
# Floors: the extractor matching nothing would compare "" against "" (or one side against the other
# by accident), so each side must be non-empty and the readback must be exactly one loop.
if [ -z "$tf_keys" ]; then fail "readback: extracted 0 var.web_hosts keys from $VARS_TF — parser drift"
elif [ "$rb_loops" -ne 1 ]; then fail "readback: expected exactly 1 'for h in' readback loop in the cutover workflow, found $rb_loops"
elif [ -z "$rb_keys" ]; then fail "readback: extracted 0 host keys from the readback loop — parser drift"
elif [ "$tf_keys" = "$rb_keys" ]; then pass
else fail "readback host-key drift: var.web_hosts=[$tf_keys] readback loop=[$rb_keys] — a host would be redeployed but never read back"; fi

# --- Self-test: the operand above must go RED on the edits it exists to catch (Guard 1 matrix,
# #8211 plan). Each mutant is a COPY of the real file fed through a seam; the suite re-invokes
# itself with WHP_SELFTEST=1 so the rows cannot recurse. A row that does not LAND (the sed changed
# nothing) is a harness failure, never a pass. ---
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
if [ -z "${WHP_SELFTEST:-}" ]; then
  MUT="$(mktemp -d "${TMPDIR:-/var/tmp}/whp-mut.XXXXXXXX")" || { echo "FAIL: mktemp for the self-test" >&2; exit 2; }
  assert_fixture_dir "$MUT"
  trap 'rm -rf "$MUT"' EXIT
  # whp_row <name> <expect red|green> <var|wf> <sed-script> [<message the RED run must print>]
  whp_row() {
    local name="$1" expect="$2" which="$3" script="$4" want="${5:-}" src rc
    assert_fixture_dir "$MUT"
    cp "$VARS_TF" "$MUT/variables.tf" && cp "$CUTOVER_WORKFLOW" "$MUT/git-data-cutover.yml" || { fail "self-test $name: could not copy the sources"; return; }
    if [ "$which" = var ]; then src="$MUT/variables.tf"; else src="$MUT/git-data-cutover.yml"; fi
    cp "$src" "$MUT/pristine"
    sed -E -i "$script" "$src"
    if cmp -s "$src" "$MUT/pristine"; then fail "self-test $name: the mutation did not land"; return; fi
    WHP_SELFTEST=1 WHP_VARS_TF="$MUT/variables.tf" WHP_CUTOVER_WORKFLOW="$MUT/git-data-cutover.yml" \
      bash "${BASH_SOURCE[0]}" > "$MUT/out" 2>&1
    rc=$?
    # A RED row must be red for the reason it names: a harness fault also exits non-zero.
    if [ "$expect" = red ] && [ "$rc" -ne 0 ] && [ -n "$want" ] && ! grep -qF -- "$want" "$MUT/out"; then
      fail "self-test $name: red, but not for the named reason [$want] ($(head -c 200 "$MUT/out" | tr '\n' ' '))"
    elif { [ "$expect" = red ] && [ "$rc" -ne 0 ]; } || { [ "$expect" = green ] && [ "$rc" -eq 0 ]; }; then pass
    else fail "self-test $name: expected $expect, the suite exited $rc ($(head -c 200 "$MUT/out" | tr '\n' ' '))"; fi
  }
  # 1: a var.web_hosts KEY the readback does not name (the IPs are untouched, so only the key operand can catch it).
  whp_row "var-key-without-readback" red var 's#^([[:space:]]*)"web-2"( *= *\{)#\1"web-9"\2#' 'readback host-key drift'
  # 2: web-2 dropped from the readback loop only.
  whp_row "readback-drops-web-2" red wf 's#( "web-2\|[^"]*")##' 'readback host-key drift'
  # 3 (dispatch): the loop no longer matches the extractor at all -> must fail on the floor, not pass vacuously.
  whp_row "extractor-matches-nothing" red wf 's#^([[:space:]]*)for h in #\1for host in #' 'found 0'
  # 4: a second loop over hosts after a compliant first (the count floor, not just set equality).
  whp_row "second-readback-loop" red wf 's#^([[:space:]]*)for h in ("web-1\|[^"]*" "web-2\|[^"]*"); do#&\n\1  :\n\1done\n\1for h in \2; do#' 'found 2'
  # 5: reordering the entries must stay GREEN (set equality, not order).
  whp_row "reordered-entries" green wf 's#for h in ("web-1\|[^"]*") ("web-2\|[^"]*"); do#for h in \2 \1; do#'
fi

total=$((passes + fails))
echo "web-hosts-fanout-parity: ${passes} passed, ${fails} failed (${total} assertions)"
[ "$fails" -eq 0 ]
