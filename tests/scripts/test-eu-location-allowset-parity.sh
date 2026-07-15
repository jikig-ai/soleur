#!/usr/bin/env bash
# Pins the EU-residency location allow-set across every site that encodes it (#6453).
#
# The set {nbg1, fsn1, hel1} is GDPR residency policy (CLO T-1, GA-blocking) and is
# replicated across FOUR sites in two languages:
#
#   1. apps/web-platform/infra/variables.tf  var.location          validation
#   2. apps/web-platform/infra/variables.tf  var.registry_location validation
#   3. apps/web-platform/infra/variables.tf  var.web_hosts         validation
#   4. tests/scripts/lib/stock-preflight-gate.sh  STOCK_PREFLIGHT_EU_LOCATIONS
#
# Nothing pinned them together. The stock gate's own test OVERRIDES
# STOCK_PREFLIGHT_EU_LOCATIONS with a synthetic topology ("eu-a eu-b eu-c") precisely so it
# stays hermetic — which means the REAL default was asserted by no test at all.
#
# Drift is not cosmetic. The gate's abort prints an "orderable in EU: <list>" suggestion
# built from its copy; terraform's validation rejects a location using its copy. If they
# diverge, the gate either advises a location terraform will refuse (misdirection in the one
# message an operator reads while a prod recreate is blocked) or silently omits a legal one.
#
# Precedent: tests/scripts/test-destroy-guard-regex-parity.sh pins the [ack-destroy] regex
# across six sites for the same reason — CODEOWNERS gates approval, not content coherence.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TF="$REPO_ROOT/apps/web-platform/infra/variables.tf"
GATE="$REPO_ROOT/tests/scripts/lib/stock-preflight-gate.sh"

passes=0
fails=0
pass() { passes=$((passes + 1)); }
fail() { fails=$((fails + 1)); echo "FAIL: $1" >&2; }

# Canonical, sorted+normalised. Changing this line is a GDPR-residency decision, not a
# refactor — it must move in lockstep with all four sites.
CANONICAL="fsn1 hel1 nbg1"

# Extract every EU allow-set from a `contains([...])` inside a terraform `condition =` line.
#
# Anchored on the `condition` + `contains(` CONSTRUCT, never a bare `nbg1` token: the same
# file names nbg1/fsn1/hel1 in `error_message` prose AND in two long `description` strings
# (":39", ":54"), so a bare-token grep matches its own documentation and reports sites that
# do not exist. Spacing is `[[:space:]]*` throughout because `terraform fmt` re-aligns `=`
# when a block gains an attribute — a single-space regex silently stops matching.
# The final `grep -oE 'contains\(...'` re-match is load-bearing, NOT redundant: var.web_hosts
# nests the call inside `alltrue([for h in values(var.web_hosts) : contains([...], h.location)])`,
# so a naive `[^]]*\]` on the whole line captures the OUTER `alltrue([...` bracket and yields
# garbage (`forhinvalues(var.web_hosts):contains(nbg1 fsn1 hel1`) rather than the set. Re-anchor
# on `contains(` first, then take its bracket group.
tf_allowsets() {
  grep -oE 'condition[[:space:]]*=[[:space:]]*.*contains\([[:space:]]*\[[^]]*\]' "$TF" \
    | grep -oE 'contains\([[:space:]]*\[[^]]*\]' \
    | sed -E 's/^contains\([[:space:]]*\[//; s/\]$//' \
    | tr -d '" ' \
    | tr ',' ' ' \
    | while read -r set; do
        printf '%s\n' "$(printf '%s\n' $set | sort | tr '\n' ' ' | sed 's/ $//')"
      done
}

mapfile -t TF_SETS < <(tf_allowsets)

# 1. Cardinality floor. If the extraction silently collapses to zero (a fmt change, a
#    refactor to a local, a renamed attribute), every comparison below would vacuously pass.
EXPECTED_TF_SITES=3
if [[ "${#TF_SETS[@]}" -eq "$EXPECTED_TF_SITES" ]]; then
  pass
else
  fail "expected ${EXPECTED_TF_SITES} terraform contains() allow-sets in variables.tf, extracted ${#TF_SETS[@]}. Either a site was added/removed (update EXPECTED_TF_SITES + this test) or the extractor stopped matching (fmt drift) — do NOT ignore: a zero-extraction makes this whole suite vacuous."
fi

# 2. Every terraform site equals the canonical set.
i=0
for set in "${TF_SETS[@]}"; do
  i=$((i + 1))
  if [[ "$set" == "$CANONICAL" ]]; then
    pass
  else
    fail "terraform allow-set #${i} is '${set}', expected '${CANONICAL}' — EU residency sets have drifted apart within variables.tf"
  fi
done

# 3. The gate's default matches. Read the DEFAULT out of the `${VAR:-...}` expansion rather
#    than sourcing the file: the suite that sources it overrides the value, so sourcing here
#    would assert the override, not the shipped default.
gate_default=$(grep -oE 'STOCK_PREFLIGHT_EU_LOCATIONS="\$\{STOCK_PREFLIGHT_EU_LOCATIONS:-[^}]*\}"' "$GATE" \
  | sed -E 's/.*:-([^}]*)\}"/\1/')
if [[ -n "$gate_default" ]]; then
  pass
else
  fail "could not extract STOCK_PREFLIGHT_EU_LOCATIONS's default from ${GATE#"$REPO_ROOT/"} — the \${VAR:-default} shape changed; this test is now blind"
fi

gate_norm=$(printf '%s\n' $gate_default | sort | tr '\n' ' ' | sed 's/ $//')
if [[ "$gate_norm" == "$CANONICAL" ]]; then
  pass
else
  fail "stock-preflight-gate.sh's EU allow-set is '${gate_norm}', expected '${CANONICAL}' — the gate's 'orderable in EU' suggestion has drifted from the terraform residency validation"
fi

echo "eu-location-allowset-parity: $passes passed, $fails failed"
[ "$fails" -eq 0 ] || exit 1
