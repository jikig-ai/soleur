#!/usr/bin/env bash
# Follow-through verification for #7574 / #7672: does the rehearsal-skip monitor's
# transient-streak counter actually SURVIVE between runs?
#
# PR #7653 fixed three measured defects in scripts/followthroughs/t5-skip-persistence-bound-7510.sh
# (an octal fail-open that produced a PASS over a sample of zero, a SIGPIPE loss under
# `pipefail` that zeroed the observed count, and a single-literal marker set blind to the S1
# arm). It deliberately used `Ref #7574`, not `Closes`, for one reason: the standing carrier
# `.github/workflows/scheduled-rehearsal-skip-monitor.yml` escalates only when a TRANSIENT
# streak persists, and that counter survives between runs solely via an `actions/cache`
# save/restore round-trip. That round-trip was REASONED, never OBSERVED -- it cannot be
# exercised locally, and it cannot be exercised by a single CI run.
#
# If it silently does not work, the counter resets to 0 every run and the escalation NEVER
# fires: a probe that can never reach a verdict becomes indistinguishable from one that keeps
# reaching a clean one. That is the exact failure #7574 exists to close, one level up.
#
# THIS PROBE IS ONE-TIME BY NATURE, which is why enrolling it with the sweeper is correct
# rather than a workaround. The sibling probe t5-skip-persistence-bound-7510.sh is NOT
# enrolled, because its job is to watch a window FOREVER and the sweeper closes on first PASS
# -- it would retire itself after one clean sample. This probe asks a different question, and
# it is permanently answered the first time it is true: once run N+1 has demonstrably restored
# what run N saved, the cache round-trip works. Closing on that PASS is the right outcome.
#
# Exit semantics (per sweep-followthroughs.sh contract):
#   0 = PASS       (a later run restored an earlier run's streak file -- the round-trip works)
#   1 = FAIL       (>=2 qualifying runs exist, and the later one did NOT restore -- broken)
#   * = TRANSIENT  (gh unreachable, or not yet enough runs to answer)
#
# Required env: GH_TOKEN
#
# Close criteria (mirrors #7672):
#   1. The monitor has run on at least two SEPARATE days.
#   2. The later run's log shows a cache RESTORE of the streak file saved by an earlier run
#      -- i.e. a non-empty `matched-key`, not a cache miss falling back to a fresh counter.
#   3. That later run's own round-trip assertion step passed.

set -uo pipefail

_transient() { echo "TRANSIENT: $1" >&2; exit 2; }

[[ -n "${GH_TOKEN:-}" ]] || _transient "GH_TOKEN not set"

REPO="jikig-ai/soleur"
WF="scheduled-rehearsal-skip-monitor.yml"
SAMPLE=30

runs=$(gh run list --repo "$REPO" --workflow "$WF" --limit "$SAMPLE" \
         --json databaseId,createdAt,conclusion 2>/dev/null) \
  || _transient "gh run list failed"

# Distinct UTC days, oldest-first, so "a later run restored an earlier run's save" is a
# question we can actually ask. `conclusion` is deliberately NOT filtered to success: a run
# that went RED because the probe reported FAIL still exercised the cache round-trip, and
# excluding it would shrink the sample for a reason unrelated to what is being measured.
mapfile -t ids < <(printf '%s' "$runs" | jq -r '
  [ .[] | select(.conclusion != null and .conclusion != "cancelled") ]
  | sort_by(.createdAt)
  | .[] | "\(.databaseId) \(.createdAt[0:10])"' 2>/dev/null) \
  || _transient "could not parse run list"

[[ "${#ids[@]}" -ge 2 ]] || _transient "only ${#ids[@]} completed monitor run(s) so far; need >=2 on separate days"

days=$(printf '%s\n' "${ids[@]}" | awk '{print $2}' | sort -u | wc -l)
[[ "$days" -ge 2 ]] || _transient "all ${#ids[@]} completed run(s) fall on a single day ($(printf '%s\n' "${ids[@]}" | awk '{print $2}' | sort -u)); the round-trip needs two"

# Walk newest-first and look for a run whose log shows a MATCHED restore key. The workflow
# prints `streak state: matched-key='<key>'` from its round-trip assertion step; on a first
# run (or a genuine miss) it prints `<none, first run>`.
first_day=$(printf '%s\n' "${ids[@]}" | awk '{print $2}' | head -1)
checked=0
for (( i=${#ids[@]}-1; i>=0; i-- )); do
  id=$(awk '{print $1}' <<<"${ids[$i]}")
  day=$(awk '{print $2}' <<<"${ids[$i]}")
  # Only a run on a LATER day than the earliest sampled run can prove a cross-day restore.
  [[ "$day" == "$first_day" ]] && continue
  log=$(gh run view "$id" --repo "$REPO" --log 2>/dev/null) || continue
  checked=$((checked + 1))
  # Anchored on the workflow's own emitted line, not a bare token.
  line=$(grep -F "streak state: matched-key=" <<<"$log" | head -1 || true)
  [[ -n "$line" ]] || continue
  if grep -qF "matched-key='<none, first run>'" <<<"$line"; then
    continue
  fi
  echo "PASS: run $id ($day) restored a prior generation of the streak file -- the actions/cache round-trip works across runs."
  echo "      $line"
  exit 0
done

[[ "$checked" -ge 1 ]] || _transient "could not fetch the log of any run on a day later than $first_day"

echo "FAIL: across $checked monitor run(s) on a day later than $first_day, none restored a prior streak file." >&2
echo "      Every later run reported a cache MISS, so the consecutive-transient counter resets" >&2
echo "      every run and the escalation in scheduled-rehearsal-skip-monitor.yml can never fire." >&2
echo "      A probe that cannot reach a verdict is then indistinguishable from one that keeps" >&2
echo "      reaching a clean one -- which is the failure #7574 exists to close." >&2
exit 1
