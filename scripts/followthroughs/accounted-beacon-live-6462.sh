#!/usr/bin/env bash
# Follow-through probe for #6462: does the fresh-boot registry beacon actually FIRE?
#
# WHY THIS EXISTS — it is the only query in #6462 that will ever execute.
# The gate this PR fixes (zot-soak-6122.sh) is NOT enrolled and never has been: the sweeper
# discovers work via `gh issue list --label follow-through` + a directive, and #6122 carries
# neither. It will not run until #6122 pins the cutover UTC. So the soak's own denominator
# CANNOT self-verify. Meanwhile a typo'd stage name is silently dark — #6462's own defect
# class (a signal whose absence reads as "no problem" when it means "nothing was reported")
# reproduced INSIDE its own fix. This probe closes that loop.
#
# PASS  = a real fresh boot emitted a beacon (the emitter is alive and correctly wired).
# TRANSIENT = no fresh boot has happened yet in the window ⇒ not a data point, not a failure.
# FAIL  = fresh boots DID happen and emitted NO beacon ⇒ the beacon is dark. That is the
#         thing this probe exists to catch, and it must be loud.
#
# Enrollment (the directive that makes the sweeper run this):
#   <!-- soleur:followthrough script=scripts/followthroughs/accounted-beacon-live-6462.sh earliest=<deploy+7d> secrets=SENTRY_AUTH_TOKEN -->
#   plus the `follow-through` label, both on #6462.
#
# Exit semantics (per sweep-followthroughs.sh contract):
#   0 = PASS       (sweeper closes the tracker)
#   1 = FAIL       (sweeper leaves it open + comments)
#   2 = TRANSIENT  (sweeper leaves it open, retries next sweep)

set -uo pipefail

if [[ -z "${SENTRY_AUTH_TOKEN:-}" ]]; then
  echo "TRANSIENT: SENTRY_AUTH_TOKEN is unset or empty — cannot query Sentry (declare it in the directive's secrets= clause)" >&2
  exit 2
fi

ORG="jikigai-eu"
API="https://sentry.io/api/0"
# Absolute window start. The beacon ships with this PR, so anything before the merge cannot
# carry it; a fixed start avoids a rolling window that silently forgets early evidence.
START="${BEACON_PROBE_START:-2026-07-15T00:00:00}"
END="$(date -u +%Y-%m-%dT%H:%M:%S)"

# Mirrors zot-soak-6122.sh's sentry_count contract exactly, including the TRANSIENT sentinel
# on a non-200 or an unexpected payload shape. Do NOT "simplify" the jq to `.data | length`
# with a default — an error object has no .data, and a defaulted 0 is a COUNTED ZERO that
# would read as "the beacon is dark" on what is really a probe failure.
sentry_count() {
  local q enc url resp status body n
  q="$1"
  enc=$(printf '%s' "$q" | jq -sRr @uri)
  url="${API}/organizations/${ORG}/events/?query=${enc}&start=${START}&end=${END}&per_page=100&field=title&field=timestamp"
  resp=$(curl -sS -w '\nHTTP_STATUS:%{http_code}' \
    -H "Authorization: Bearer $SENTRY_AUTH_TOKEN" -H "Accept: application/json" "$url" 2>/dev/null)
  status=$(printf '%s' "$resp" | sed -n 's/^HTTP_STATUS://p' | tr -d '[:space:]')
  body=$(printf '%s' "$resp" | sed '$d')
  if [[ "$status" != "200" ]]; then echo "TRANSIENT"; return; fi
  n=$(printf '%s' "$body" | jq -r 'if (.data | type) == "array" then (.data | length) else error("no data array") end' 2>/dev/null)
  [[ "$n" =~ ^[0-9]+$ ]] && echo "$n" || echo "TRANSIENT"
}

# All three queries are BARE stage: — _emit writes only {stage,image_ref,host_id,detail}, no
# feature/op. Prefixing any of these matches zero events FOREVER, which would make this probe
# report "dark beacon" on a perfectly healthy fleet. See zot-soak-6122.sh's prefix note.
BOOTS=$(sentry_count 'stage:"bootstrap_complete"')
ZOT=$(sentry_count 'stage:"app_zot"')
SERVED=$(sentry_count 'stage:"app_ghcr_served"')

for pair in "bootstrap_complete:$BOOTS" "app_zot:$ZOT" "app_ghcr_served:$SERVED"; do
  name="${pair%%:*}"; val="${pair##*:}"
  if [[ ! "$val" =~ ^[0-9]+$ ]]; then
    echo "TRANSIENT: Sentry query '$name' failed (window $START..$END) — retry next sweep." >&2
    exit 2
  fi
done

BEACONS=$((ZOT + SERVED))

# No fresh boot yet ⇒ NOT a data point. cloud-init.yml is ignore_changes-pinned on running
# hosts (server.tf), so the beacon only reaches the fleet on a rebuild. Mirrors the sibling
# probe's rule (zot-mirror-connector-6416.sh) — a probe must not FAIL on absence of the
# precondition it depends on.
if (( BOOTS == 0 )); then
  echo "TRANSIENT: no fresh boot since $START (bootstrap_complete=0) — the beacon only ships on a rebuild (cloud-init is ignore_changes-pinned on running hosts). Not a data point yet." >&2
  exit 2
fi

# Fresh boots happened. Exactly one beacon should fire per successful boot, so zero beacons
# across N boots means the emitter is dark — a typo'd stage, an unresolved DSN, a curl that
# never lands, or cloud-init never reaching the fleet.
if (( BEACONS == 0 )); then
  echo "FAIL: $BOOTS fresh boot(s) since $START but ZERO registry beacons (app_zot=0, app_ghcr_served=0). The beacon is DARK — #6462's own defect class inside its own fix. Check: the emit landed above the IMAGE_REF reassignment in cloud-init.yml; the stage literals are not typo'd; _emit's call site is after :408 (see #6505 — every _emit before that line is silently dark under dash)."
  exit 1
fi

echo "PASS: $BOOTS fresh boot(s) since $START emitted $BEACONS registry beacon(s) (app_zot=$ZOT zot-served, app_ghcr_served=$SERVED GHCR-served). The beacon FIRES on a real fresh boot — #6462's denominator is live and the soak's floor has evidence to converge on."
exit 0
