# shellcheck shell=bash
# Shared fail-closed preamble for tfplan-grading gates (#6977, cto F1).
#
# WHY THIS FILE EXISTS. TWELVE gates in tests/scripts/lib/ grade a `terraform show -json`
# document before authorising an apply. Only FOUR validate that the document is readable
# and that every entry is classifiable before any counter reads one: this file's consumer
# (git-data-host-birth-gate.sh), plus web-host-birth-gate.sh, web-host-replace-gate.sh and
# stock-preflight-gate.sh, which carry equivalent checks INLINE. The other EIGHT —
# INCLUDING git-data-host-replace-gate.sh — carry neither. That is not a style difference;
# it is a two-tier safety floor produced by copy-the-sibling, and the lower tier fails OPEN.
#
# Re-derive rather than trusting these numbers. Successive revisions have said "nine and
# seven" and "five", and every one of them was wrong:
#   grep -l 'local plan_json' tests/scripts/lib/*gate*.sh | xargs grep -L plan_gate_assert_readable
# (that lists the 11 not yet ON this preamble; three of the 11 hold inline equivalents.)
# Retrofitting the eight is tracked by issue #6997.
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
  #
  # THE CONJUNCTS ARE ORDERED, AND THE ORDER IS LOAD-BEARING. jq's `and` short-circuits, so
  # each conjunct is the type guard for the one after it:
  #
  #   (type == "object")               — the ELEMENT itself. Without it, `resource_changes:
  #                                      [42]` makes `.change` RAISE, and this function then
  #                                      aborts because jq errored rather than because the
  #                                      assertion was false. Right verdict, wrong mechanism —
  #                                      and this file's own header calls that out as the trap.
  #   (.change | type) == "object"     — guards `.change.actions` against a scalar `.change`.
  #   (.change.actions | type) == "array"
  #   (.change.actions | length) > 0   — D5. `[]` IS an array, so nothing above rejects it,
  #                                      and it is invisible to `any(...)` and to
  #                                      `index("delete")` simultaneously. See the header.
  #   all(.change.actions[]; type == "string")
  #                                    — ADDITIVE, and it does NOT subsume `length > 0`:
  #                                      jq's `all` over an EMPTY stream is vacuously TRUE, so
  #                                      `[]` satisfies this conjunct and only `length > 0`
  #                                      rejects it. Both are required. It closes the NESTED
  #                                      case `[["delete"]]`, which is a non-empty array of
  #                                      the right outer type whose `index("delete")` is null —
  #                                      so a destroy hiding there is dropped by the destroy
  #                                      select exactly like a missing-actions entry.
  #                                      web-host-replace-gate.sh carried this inline while
  #                                      this shared helper did not, so retrofitting that gate
  #                                      onto the helper without it would have been a
  #                                      REGRESSION (#6997). `.change.actions` is a closed enum
  #                                      of strings in terraform, so no legitimate plan shape
  #                                      is newly rejected.
  if ! jq -e 'all(.resource_changes[]; (type == "object") and (.change | type) == "object" and (.change.actions | type) == "array" and (.change.actions | length) > 0 and all(.change.actions[]; type == "string"))' \
       < "$plan_json" >/dev/null 2>&1; then
    # THE OFFENDER LIST MIRRORS THOSE GUARDS, for the same short-circuit reason and one
    # more: it must never come back BLANK. An ABORT that names no offender leaves the
    # operator's only diagnostic empty and sends them to read the gate source.
    #
    # `or` short-circuits too, so `(type != "object")` first is what keeps `.change` from
    # raising on a non-object element. Measured before this guard existed: a
    # `resource_changes: [42]` document aborted with the literal text
    # "unclassifiable plan entry:  has no non-empty array .change.actions" — correct
    # verdict, blank diagnostic.
    #
    # `.address? // "<entry with no address>"` covers the same element: a bare `.address`
    # on a number raises, and `.address?` alone yields EMPTY, which silently drops the
    # entry from the list and reproduces the blank. Naming it as unnameable is the point.
    #
    # (An earlier revision proposed a `?` on `.change.actions` here instead. Measured: it
    # is a no-op on every shape — the `(.change | type) != "object"` disjunct already
    # short-circuits ahead of it, and it does not help the non-object ELEMENT case either,
    # because that raises one level up at `.change`. Recorded rather than silently
    # substituted: shipping a guard whose stated justification is false is this file's own
    # defect class.)
    offenders=$(jq -r '[.resource_changes[] | select((type != "object") or ((.change | type) != "object") or ((.change.actions | type) != "array") or ((.change.actions | length) == 0) or (any(.change.actions[]; type != "string"))) | (.address? // "<entry with no address>")] | .[0:10] | join(", ")' < "$plan_json" 2>/dev/null)
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
