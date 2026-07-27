# shellcheck shell=bash
# Shared fail-closed preamble for tfplan-grading gates (#6977, cto F1).
#
# WHY THIS FILE EXISTS. NINE gates in tests/scripts/lib/ grade a `terraform show -json`
# document before authorising an apply. Only TWO of them — web-host-birth-gate.sh and
# web-host-replace-gate.sh — validate that the document is readable and that every entry
# is classifiable before any counter reads one. The other SEVEN, INCLUDING
# git-data-host-replace-gate.sh, carry neither check.
#
# Re-derive rather than trusting these numbers (an earlier revision said seven and five):
#   grep -l 'local plan_json' tests/scripts/lib/*gate*.sh | xargs grep -L plan_gate_assert_readable That is not a style difference; it
# is a two-tier safety floor produced by copy-the-sibling, and the lower tier fails OPEN.
#
# THE THREE FAILURES THIS PREVENTS, each measured on a real gate:
#
#   1. `null | length` is 0 in jq. A degraded document whose `resource_changes` is null
#      or absent reads as "zero creates, zero destroys, zero out-of-scope" — every
#      counter satisfied, every arm silent, PASS. The same fail-open shape as a
#      200-with-null-body satisfying a count check.
#
#   2. `null | index("delete")` returns null rather than erroring, so an entry missing
#      `.change.actions` is silently DROPPED by the destroy and out-of-scope selects. The
#      resource vanishes from the work-list instead of failing closed, and what it hides
#      is precisely a destroy the gate cannot see.
#
#   3. With `set -e` disabled — which is how these gates run, sourced inside a step that
#      captures rc by hand — a failed `jq` yields "" and `[[ "" -gt 0 ]]` is FALSE under
#      bash arithmetic coercion. A destructive plan passes because the check that would
#      have caught it could not be computed.
#
# Every function here ABORTS (returns 1) rather than returning a zero. A gate that
# authorises production infrastructure must never let "I could not check" read as
# "it is fine".
#
# Usage:  source tests/scripts/lib/plan-gate-preamble.sh
#         plan_gate_assert_readable      <gate-name> <plan-json>   || return 1
#         plan_gate_assert_classifiable  <gate-name> <plan-json>   || return 1
#         plan_gate_assert_numeric       <gate-name> <name=value>… || return 1

# plan_gate_assert_readable <gate-name> <plan-json>
#
# The file exists, parses, and carries an ARRAY `resource_changes`. The array-type test is
# separate from `has()` on purpose: `has("resource_changes")` is true for an explicit
# `"resource_changes": null`, which is exactly failure mode 1.
plan_gate_assert_readable() {
  local gate="$1" plan_json="$2"

  if [[ -z "$plan_json" ]]; then
    echo "${gate}: ABORT — no plan JSON path supplied. Fail-closed: a gate with nothing to grade has not approved anything."
    return 1
  fi

  if [[ ! -f "$plan_json" ]]; then
    echo "${gate}: ABORT — plan JSON not found: ${plan_json}"
    return 1
  fi

  if ! jq -e 'has("resource_changes") and (.resource_changes | type == "array")' \
       < "$plan_json" >/dev/null 2>&1; then
    echo "${gate}: ABORT — jq filter failed on ${plan_json}: the document is unparseable or has no resource_changes array. Fail-closed: an unreadable plan is not evidence of a safe one."
    return 1
  fi

  return 0
}

# plan_gate_assert_classifiable <gate-name> <plan-json>
#
# Every entry carries a NON-EMPTY ARRAY `.change.actions` before any counter reads one.
# Scoped to ALL types, not just the gate's subject type — the destroy and out-of-scope arms
# read every entry's actions, so an unclassifiable entry of ANY type is a hole.
#
# THE LENGTH CHECK IS NOT PEDANTRY. `[]` is an array, so a type-only check accepts it —
# and an entry with empty actions is then INVISIBLE to every downstream arm at once:
# `[] | any(...)` is false (the out-of-scope and firewall selects skip it) and
# `[] | index("delete")` is null (the destroy select skips it). Measured: a plan whose
# happy 18-address birth also carried `hcloud_server.web["web-1"]` with `"actions": []`
# and `"after": null` — a destroy of the singleton behind app.soleur.ai — scored
# destroys=0, out_of_scope=0 and PASSED.
#
# It is also a fail-OPEN default at the one place a gate is a quantifier: jq's `all` over
# an empty array is `true`, so a required member appearing only as `[]` satisfied a
# presence assertion too. A zero-length actions array is exactly "an entry the gate cannot
# classify", which is this function's job.
plan_gate_assert_classifiable() {
  local gate="$1" plan_json="$2"
  local offenders

  # POSITIVE assertion, not a negative search.
  #
  # The obvious form — `if jq -e '[...|select(bad)]|length > 0'` — reads a jq ERROR as
  # "condition false". Measured: an entry whose `.change` is a SCALAR (`"change": 42`)
  # makes `.change.actions` raise `Cannot index number with string "actions"`, jq exits 5,
  # the `if` is false, and the function reports the plan CLASSIFIABLE. That is failure
  # mode 2 from this file's own header, inside the check written to close it.
  #
  # `all(...)` asserts the property instead, so an error, a missing key, a wrong type and
  # a scalar `.change` all land on the abort side. The `-e` exit is then only consulted
  # for the assertion's own truth.
  if ! jq -e 'all(.resource_changes[]; (.change | type) == "object" and (.change.actions | type) == "array" and (.change.actions | length) > 0)' \
       < "$plan_json" >/dev/null 2>&1; then
    offenders=$(jq -r '[.resource_changes[] | select(((.change | type) != "object") or ((.change.actions | type) != "array") or ((.change.actions | length) == 0)) | .address] | .[0:10] | join(", ")' < "$plan_json" 2>/dev/null)
    echo "${gate}: ABORT — unclassifiable plan entry: ${offenders} has no non-empty array .change.actions, so it cannot be classified as create/destroy/no-op. Fail-closed: an entry the gate cannot read is not evidence of a safe plan — a destroy hiding in an unreadable entry is exactly what this refuses to wave through."
    return 1
  fi

  return 0
}

# plan_gate_assert_numeric <gate-name> <name=value> [<name=value>…]
#
# Every counter is a non-negative integer BEFORE any arithmetic compares one. Takes
# name=value pairs rather than bare values so the abort message can name WHICH counter
# failed to parse — a bare "counter parse failed" sends the operator to read the gate
# source to find out which jq expression broke.
#
# The `${pair#*=}` split takes everything after the FIRST `=`, so a value that itself
# contains `=` is reported intact rather than silently truncated to something that might
# coincidentally match ^[0-9]+$.
plan_gate_assert_numeric() {
  local gate="$1"; shift
  local pair name value bad=""

  for pair in "$@"; do
    name="${pair%%=*}"
    value="${pair#*=}"
    if [[ ! "$value" =~ ^[0-9]+$ ]]; then
      bad+="${bad:+, }${name}='${value}'"
    fi
  done

  if [[ -n "$bad" ]]; then
    echo "${gate}: ABORT — counter parse failed (${bad}). A counter that did not evaluate is not a zero: with set -e disabled a failed jq yields the empty string, and [[ \"\" -gt 0 ]] is FALSE under bash coercion, so an uncomputed counter silently satisfies every threshold. Fail-closed."
    return 1
  fi

  return 0
}
