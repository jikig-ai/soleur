#!/usr/bin/env bash
# SYNTHESIZED FIXTURE — never executed, never registered as a suite. Read only by
# scripts/battery-tag-authorship.test.sh when a mutation row lifts its FIXTURE_EXCLUSION entry.
#
# It carries a `repo-boundary-tag-exempt:` marker with NO matching ledger entry. Unmutated the
# guard must grade this OFFENDER — the marker-plus-ledger bijection is the whole point of the
# two-key design, and the guard's own comment says path granularity alone "would let a
# copy-pasted marker on a NEW command in an already-exempt file be silently absorbed".
#
# It pins the `in_ledger` MEMBERSHIP predicate, which was measured surviving: making the test
# unconditional graded this site EXEMPT and the guard went green. The existing ledger rows
# mutate the ledger's CONTENTS; neither touches the predicate that reads it.
#
# repo-boundary-tag-exempt: deliberately unmatched. See above.
_battery_tag_fixture_marker_without_ledger_entry() {
  git tag battery-tag-fixture-marker-only
}
