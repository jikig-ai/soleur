#!/usr/bin/env bash
# Shared constants for rule-metrics scripts.
# Sourced by scripts/rule-metrics-aggregate.sh, scripts/rule-prune.sh, and
# .claude/hooks/lib/incidents.sh (hook-emitter side consumes SCHEMA_VERSION).
# Do NOT add executable logic here — source-only.
#
# Drift guard: scripts/rule-prune.sh and scripts/lint-rule-ids.py both
# enforce the rule_id format; because bash ERE and Python `re` differ in
# syntax, the regex itself is NOT defined here. Each script carries its
# own regex with a comment referring to the other.

# shellcheck disable=SC2034  # sourced by other scripts
RULE_PREFIX_LEN=50
# shellcheck disable=SC2034
UNUSED_WEEKS_DEFAULT=8
# shellcheck disable=SC2034
SCHEMA_VERSION=1
