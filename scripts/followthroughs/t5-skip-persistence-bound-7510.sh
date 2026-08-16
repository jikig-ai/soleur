#!/usr/bin/env bash
# Follow-through verification for the T5 counted-skip persistence bound (PR #7510, issue #7291).
#
# ADR-188 accepts, explicitly, that nothing bounds the T5 mutation arm's skip ACROSS runs. The
# three mechanical conditions bound it per-run; an arm that skips on every run forever satisfies
# all three and reports green, and the only carrier is `Skipped: N` plus a NOTE on the stdout of
# a check that exits 0. This probe is that missing observer.
#
# It reads the ONE signal that already exists — the suite's own loud SKIP line in post-merge
# `infra-validation.yml` logs — so it needs no new instrumentation to be useful today.
#
# Exit semantics (per sweep-followthroughs.sh contract):
#   0 = PASS       (no skip observed in the sampled window; the residual has not materialised)
#   1 = FAIL       (>= 1 skip observed; the deferred pre-bake / S1 extension is now owed)
#   * = TRANSIENT  (gh unreachable, auth failure, no runs to sample)
#
# Required env: GH_TOKEN  (declared via the directive's secrets= clause; the sweeper runs under
#                          `env -i` and strips everything not declared)
#
# Close criteria:
#   - Sample the most recent successful post-merge runs of infra-validation.yml on main
#   - Grep their logs for `SKIP (loud): T5 MUTATION`
#   - 0 occurrences  => PASS (close; the skip is not persistent)
#   - >=1 occurrence => FAIL (leave open; ADR-188's 1-in-20 observation window has fired)

set -uo pipefail

if [[ -z "${GH_TOKEN:-}" ]]; then echo "TRANSIENT: GH_TOKEN not set" >&2; exit 2; fi

REPO="jikig-ai/soleur"
WF="infra-validation.yml"
SAMPLE=20   # ADR-188's declared window: "more than 1 in 20 post-merge runs"

runs=$(gh run list --repo "$REPO" --workflow "$WF" --branch main \
         --limit "$SAMPLE" --json databaseId,conclusion 2>/dev/null) || {
  echo "TRANSIENT: gh run list failed" >&2; exit 2; }

ids=$(printf '%s' "$runs" | jq -r '.[] | select(.conclusion == "success") | .databaseId' 2>/dev/null) || {
  echo "TRANSIENT: could not parse run list" >&2; exit 2; }

# An empty sample is NOT a clean bill of health — it is an un-run instrument. Absence of evidence
# here is indistinguishable from evidence of absence, which is the exact trap this file's own
# subject matter is about.
[[ -n "$ids" ]] || { echo "TRANSIENT: no successful post-merge runs to sample" >&2; exit 2; }

sampled=0
hits=0
while IFS= read -r id; do
  [[ -n "$id" ]] || continue
  log=$(gh run view "$id" --repo "$REPO" --log 2>/dev/null) || continue
  sampled=$((sampled + 1))
  n=$(printf '%s' "$log" | grep -cF 'SKIP (loud): T5 MUTATION' || true)
  hits=$((hits + n))
done <<< "$ids"

[[ "$sampled" -ge 1 ]] || { echo "TRANSIENT: no run logs could be fetched" >&2; exit 2; }

if [[ "$hits" -eq 0 ]]; then
  echo "PASS: 0 loud T5 skips across ${sampled} sampled post-merge run(s) — the persistence residual has not materialised."
  exit 0
fi

echo "FAIL: ${hits} loud T5 skip(s) across ${sampled} sampled post-merge run(s)." >&2
echo "      ADR-188's declared observation window has fired: the skip is masking a persistent" >&2
echo "      condition rather than a transient one. The deferred pre-baked image (#7535) is owed," >&2
echo "      and the S1 extension (#7572) becomes the same class of problem." >&2
exit 1
