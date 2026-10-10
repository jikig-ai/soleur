#!/usr/bin/env bash
# =============================================================================
# verify-ruleset-required-checks.sh — a pre-apply, by-value gate on one ruleset's
# required checks (#9362).
#
#   verify-ruleset-required-checks.sh <plan.json|-> <resource-address> <canonical.json>
#
# Reads a `terraform show -json` plan document (a file, or `-` for stdin) and compares
# the {context, integration_id} set the plan is about to write for ONE ruleset resource
# against the committed canonical file, row by row, by value. A rebound integration id
# is an in-place update, which the destroy guard (deletes only) cannot see, so this is
# the check that stops it BEFORE `terraform apply`.
#
# Scope, stated plainly: it compares required-check bindings and nothing else. It is not
# a general ruleset-equality check; the destroy guard still owns deletes, and the daily
# ruleset audit still owns after-the-fact drift.
#
# Exit codes (distinct on purpose, so a malfunction never reads as a clean pass or as
# a mismatch):
#   0  the planned set equals the canonical set
#   1  the sets differ (each differing row is printed, context and id only)
#   2  usage error or the gate could not decide: empty input, unparseable JSON, the
#      resource address absent or ambiguous, the resource being deleted (`after` null),
#      no required checks in the plan, or a malformed canonical
#
# There is NO override, by design (ADR-241, the 2026-10-10 entry): a legitimate change to a
# required check updates the committed canonical in the same reviewed PR. A canonical-only
# fix does not match the apply workflow's push paths, so after it merges the apply is
# re-run by a workflow_dispatch; a re-run of the red run replays the old canonical.
#
# The plan document carries input-variable values, including the Tier-B App key. It is
# read from a pipe or a file and held in a shell variable only: never echoed, never
# traced, and handed to jq through `printf | jq` pipes rather than here-strings (bash
# backs a large here-string with a temp file). jq's stderr goes to /dev/null because a
# parse error quotes a fragment of its input. Rows are printed through `tojson`, so a
# control character in a context cannot forge a workflow command line.
#
# Driven by tests/scripts/test-apply-github-infra-mint-shape.sh (Guard 1).
# =============================================================================
set -uo pipefail

# Every message is a static string (the one number is a jq length), so it is safe to splice
# into a workflow command. The annotation lets a triage that reads check-run annotations tell
# "the gate could not decide" from "the bindings differ".
die() { # <rc> <message>
  printf '::error title=required-check-gate-undecided::verify-ruleset-required-checks: %s. The gate fails closed and has no override (ADR-241, 2026-10-10 entry).\n' "$2"
  exit "$1"
}

[[ $# -eq 3 ]] || die 2 "usage: verify-ruleset-required-checks.sh <plan.json|-> <resource-address> <canonical.json>"
plan_src="$1"; addr="$2"; canonical_file="$3"

# The address is spliced into a workflow annotation, so refuse anything that is not an
# ordinary Terraform address.
[[ "$addr" =~ ^[A-Za-z0-9_.-]+$ ]] || die 2 "refusing a resource address with unexpected characters"

# Read the whole of stdin before any validation that can exit, so an early exit never
# SIGPIPEs the `terraform show` on the other end of the pipe.
if [[ "$plan_src" == "-" ]]; then
  plan="$(cat)"
else
  [[ -r "$plan_src" ]] || die 2 "plan file is not readable"
  plan="$(cat -- "$plan_src")"
fi
[[ "$plan" =~ [^[:space:]] ]] || die 2 "the plan document is empty"
[[ -r "$canonical_file" ]] || die 2 "canonical file is not readable"

LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/canonicalize-required-status-checks.sh"
[[ -r "$LIB" ]] || die 2 "the shared projection library is missing"
# shellcheck source=lib/canonicalize-required-status-checks.sh
source "$LIB"
proj="${CANONICALIZE_REQUIRED_STATUS_CHECKS_JQ:-}"
[[ -n "$proj" ]] || die 2 "the shared projection is empty"

# --- the canonical must be well-formed before it is trusted ---------------------------
canonical="$(jq -c 'select(type == "array")' "$canonical_file" 2>/dev/null)" || canonical=""
[[ -n "$canonical" ]] || die 2 "the canonical is not a JSON array"
jq -e '
  length > 0
  and all(.[]; (.context | type == "string") and (.integration_id | type == "number"))
  and ((map(.context) | unique | length) == length)
' <<<"$canonical" >/dev/null 2>&1 \
  || die 2 "the canonical is empty, has a non-string context or non-numeric integration_id, or repeats a context"

# --- select the one resource and refuse every shape the gate cannot judge -----------
matches="$(printf '%s' "$plan" | jq -r --arg addr "$addr" '[.resource_changes[]? | select(.address == $addr)] | length' 2>/dev/null)" \
  || die 2 "the plan document is not parseable JSON"
[[ "$matches" == "1" ]] || die 2 "the plan has ${matches:-0} resource_changes entries for the address (want exactly 1)"

printf '%s' "$plan" | jq -e --arg addr "$addr" '
  [.resource_changes[] | select(.address == $addr)][0].change.after != null
' >/dev/null 2>&1 \
  || die 2 "the resource has no planned end state (it is being deleted)"

planned_raw="$(printf '%s' "$plan" | jq -c --arg addr "$addr" '
  [.resource_changes[] | select(.address == $addr)][0].change.after
  | [.rules[]?.required_status_checks[]?.required_check[]?]
' 2>/dev/null)" || die 2 "could not read the planned required checks"
[[ "$(jq 'length' <<<"$planned_raw" 2>/dev/null)" =~ ^[0-9]+$ ]] || die 2 "could not count the planned required checks"
[[ "$(jq 'length' <<<"$planned_raw")" -gt 0 ]] || die 2 "the plan carries no required checks for the address"

planned="$(jq -c "$proj" <<<"$planned_raw" 2>/dev/null)" || die 2 "could not project the planned required checks"
canon_p="$(jq -c "$proj" <<<"$canonical" 2>/dev/null)" || die 2 "could not project the canonical"

n_planned="$(jq 'length' <<<"$planned")"
n_canon="$(jq 'length' <<<"$canon_p")"

# Compare by VALUE, not by rendered text: jq keeps a number's source literal, so 15368.0 and
# 15368 are equal values with different spellings.
if jq -en --argjson a "$planned" --argjson b "$canon_p" '$a == $b' >/dev/null 2>&1; then
  printf 'OK: %s: %s/%s required checks match the canonical by value\n' "$addr" "$n_planned" "$n_canon"
  exit 0
fi

# --- mismatch: name each differing row (context and id only), then fail -----------------
printf '::error title=required-check-bindings::%s: the planned required-check bindings differ from the committed canonical (planned %s, canonical %s). Refusing to apply. There is no override, by design (ADR-241, 2026-10-10 entry): reconcile infra/github/*.tf and the canonical file in one reviewed PR, then re-apply by workflow_dispatch (a re-run of this run replays the old canonical). Rows below: "-" is canonical-only, "+" is plan-only.\n' \
  "$addr" "$n_planned" "$n_canon"
jq -r --argjson planned "$planned" '
  ($planned) as $p | (.) as $c
  | ($c - $p)[] | "- " + tojson
' <<<"$canon_p"
jq -r --argjson canon "$canon_p" '
  (.) as $p | ($canon) as $c
  | ($p - $c)[] | "+ " + tojson
' <<<"$planned"
# A duplicated or doubled row differs in count without any row differing in value.
if [[ "$n_planned" != "$n_canon" ]]; then
  printf 'row count differs: planned %s, canonical %s\n' "$n_planned" "$n_canon"
fi
exit 1
