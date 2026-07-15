#!/usr/bin/env bash
# Follow-through soak gate for #6122 Phase 5 (registry migration GHCR → self-hosted zot).
#
# After the operator provisions (1.8) + backfills (1.9) zot and the pull-site flip goes
# live, the fleet must run zot-primary for a soak window with ZERO GHCR fallbacks before
# GHCR push/egress can be retired (tasks 5.3-5.5) and ADR-096 flips adopting → accepted
# (5.6). This script is that gate. It PASSES (closes the tracker) only when, over the
# window from just-after cutover to now, Sentry shows:
#   (a) ZERO fallback events across ALL FOUR signals the companion alarm
#       (sentry_issue_alert.zot_mirror_fallback_rate) watches — see FAIL_QUERIES below;
#   (b) a MIN_SAMPLE of zot-served pulls PER image (registry:"zot" image:"web" /
#       image:"inngest") — so a vacuous "zero fallbacks because nothing deployed" cannot
#       close the tracker. Proof the flip was actually exercised.
#
# The four watched signals and their emitters (anchored on EMIT NAMES, not line numbers —
# ADR-096 mandates this; line citations rot). NOTE there are THREE distinct emitters, with
# two different tag schemas — that asymmetry is the whole reason the queries differ:
#   registry:"ghcr-fallback"       ci-deploy.sh  `registry_pull_event ghcr-fallback`
#                                  jq tags: {feature, op, registry, image}
#   registry:"zot-gate-degraded"   ci-deploy.sh  `zot_gate_degraded_event`
#                                  jq tags: {feature, op, registry, zot_gate_reason}
#   stage:"inngest_ghcr_fallback"  cloud-init.yml calls `soleur-boot-emit inngest_ghcr_fallback`
#                                  (defined in soleur-host-bootstrap.sh) tags: {stage, host_id, region}
#   stage:"app_ghcr_fallback"      cloud-init.yml `_emit ... "app_ghcr_fallback" warning`
#                                  tags: {stage, image_ref, host_id, detail}
#
# ⚠ THE PREFIX ASYMMETRY IS DELIBERATE. Do NOT "normalize" the queries to a common prefix.
# ci-deploy.sh's jq payload carries feature+op, so the registry: queries are prefixed. NEITHER
# boot-path emitter (`soleur-boot-emit` nor `_emit`) writes feature or op — they are separate
# emitters that happen to share that gap — so the stage: queries MUST be bare. Sentry tag
# matching is EXACT: prefixing a stage: query makes it match zero events forever, silently
# restoring the blindness this gate exists to catch. Verify against BOTH emitters' tag
# schemas above before touching a query — one of them is not enough.
# Proven live: stage:"bootstrap_complete" → 9 events; the same query prefixed → 0.
# The FAIL set (whole query strings, not just the tag values) is pinned against the alarm by
# apps/web-platform/test/sentry-zot-mirror-fallback-alert-op-contract.test.ts, so drift on
# either side fails CI rather than silently darkening this gate.
#
# ⚠ WHAT THIS GATE CANNOT SEE — it is NECESSARY BUT NOT SUFFICIENT to authorize 5.3-5.5:
#   - FAIL set is 4-of-5. The Sentry-dark mode (ci-deploy.sh returns early when doppler,
#     DOPPLER_TOKEN, or ZOT_REGISTRY_URL is absent) emits NOTHING to Sentry — journald only.
#     It is caught ONLY by the insufficient-sample arm below. Tracked: #6437.
#   - Fresh-boot (web) coverage is PARTIAL. If cloud-init's /v2/ probe MISSES, the ref stays
#     GHCR, the pull succeeds first try, and the emit's guard never fires — so the dominant
#     fresh-boot fallback path emits nothing at all. There is also no app_zot liveness beacon
#     (inngest has one), so "0 fresh-boot fallbacks" is indistinguishable from "no fresh boot
#     happened". This gate counts BAD events but has no DENOMINATOR of expected boots.
#   - Consequence: a PASS here is evidence, not authorization. See ADR-096.
#
# ⚠ HISTORY: this file was committed mode 100644 and therefore NEVER RAN — sweep-followthroughs.sh
# rejects a non-executable probe before exec and prints to stderr only (no comment, no exit code).
# No query in this file executed between its creation and #6435. scripts/followthrough-exec-bit.test.sh
# now guards the whole probe class.
#
# Exit semantics (per sweep-followthroughs.sh contract):
#   0 = PASS       (zero fallbacks AND sufficient zot sample; sweeper closes the tracker)
#   1 = FAIL       (>=1 fallback on any watched signal OR insufficient zot sample — leave
#                   open: a real fallback is a regression to investigate; an insufficient
#                   sample means keep soaking, do NOT retire GHCR yet)
#   * = TRANSIENT  (Sentry API unreachable / auth / parse failure; retry next sweep)
#
# Required env: SENTRY_AUTH_TOKEN (wire as secrets.SENTRY_IAC_AUTH_TOKEN in the sweeper).
# Directive for the tracking issue body (pin START to the cutover UTC, earliest to >=7d):
#   <!-- soleur:followthrough script=scripts/followthroughs/zot-soak-6122.sh earliest=<UTC+7d> secrets=SENTRY_AUTH_TOKEN -->

set -uo pipefail

# Fail-safe env check. Deliberately NOT `: "${VAR:?msg}"` — under a non-interactive shell
# that word-expansion aborts with status 1, which this contract reads as FAIL ("criteria not
# met") when the truth is "the probe could not run". An unprovisioned env must never be able
# to report a verdict on an irreversible retirement. See followthrough-convention.md.
if [[ -z "${SENTRY_AUTH_TOKEN:-}" ]]; then
  echo "TRANSIENT: SENTRY_AUTH_TOKEN is unset or empty — cannot query Sentry (declare it in the directive's secrets= clause)" >&2
  exit 2
fi

ORG="jikigai-eu"
API="https://sentry.io/api/0"
MIN_SAMPLE="${ZOT_SOAK_MIN_SAMPLE:-3}"   # min zot-served pulls per image to prove exercise

# Absolute window start — PIN THIS to just after the cutover flip (the same UTC the
# operator records in the revert runbook). Placeholder until pinned; the earliest= gate in
# the issue directive still defers the first real check to >=7 days after cutover.
START="${ZOT_SOAK_START:-<POST_CUTOVER_UTC>}"
END=$(date -u +%Y-%m-%dT%H:%M:%S)

# Own the unpinned-START case rather than delegating it to Sentry's date parser. Until START
# is pinned it holds the literal placeholder above; today's fail-safety rests on Sentry 400ing
# that string — an unverified vendor behaviour this gate must not bet an irreversible
# retirement on.
#
# NOTE: this proves START is a TIMESTAMP, not that it is the RIGHT one. Nothing here asserts
# START <= cutover_utc, and a START pinned LATE is a false-PASS route: it excludes flip-day
# fallbacks while the remaining days still clear MIN_SAMPLE. The window bound is
# operator-asserted and unverified. Tracked on #6122 (which owns the true cutover UTC).
if [[ ! "$START" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T ]]; then
  echo "TRANSIENT: START is unpinned ($START) — pin ZOT_SOAK_START in this script to the cutover UTC before this gate can report a verdict." >&2
  exit 2
fi

# sentry_count <query> → echoes the event count for the window, or "TRANSIENT" on error.
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
  # Require .data to BE an array. The previous form took `length` with an alternative-operator
  # default of zero, which yields a plain 0 for an unexpected payload shape (an error object has
  # no .data → length of null → 0). That 0 is numeric, so it sailed through the guard below as a
  # COUNTED ZERO — a false-PASS route on the one gate protecting an irreversible action. (The
  # default was also dead code: `length` never returns null.) On a shape mismatch jq now errors →
  # empty → TRANSIENT.
  n=$(printf '%s' "$body" | jq -r 'if (.data | type) == "array" then (.data | length) else error("no data array") end' 2>/dev/null)
  [[ "$n" =~ ^[0-9]+$ ]] && echo "$n" || echo "TRANSIENT"
}

# --- (a) Fallback events across ALL FOUR watched signals. Zero required. ---
#
# Declared, guarded, and summed by ONE loop, so "declared but never counted" — the #6435
# defect — is structurally unrepresentable rather than policed by a reviewer's attention.
# ⚠ [freshboot] and [appboot] are BARE stage: queries. NEVER prefix them (see the header).
declare -A FAIL_QUERIES=(
  [rolling]='feature:supply-chain op:image-pull registry:"ghcr-fallback"'
  [gate]='feature:supply-chain op:image-pull registry:"zot-gate-degraded"'
  [freshboot]='stage:"inngest_ghcr_fallback"'
  [appboot]='stage:"app_ghcr_fallback"'
)

declare -A COUNTS
FALLBACKS=0
# Sorted for deterministic output; the array above stays the single source of truth.
for k in $(printf '%s\n' "${!FAIL_QUERIES[@]}" | sort); do
  n=$(sentry_count "${FAIL_QUERIES[$k]}")
  if [[ ! "$n" =~ ^[0-9]+$ ]]; then
    echo "TRANSIENT: Sentry query '$k' failed (window $START..$END) — retry next sweep." >&2
    exit 2
  fi
  COUNTS[$k]=$n
  FALLBACKS=$(( FALLBACKS + n ))
done

# --- (b) zot-served sample per image. >= MIN_SAMPLE required (proof of exercise). ---
ZOT_WEB=$(sentry_count 'feature:supply-chain op:image-pull registry:"zot" image:"web"')
ZOT_INNGEST=$(sentry_count 'feature:supply-chain op:image-pull registry:"zot" image:"inngest"')

for v in "$ZOT_WEB" "$ZOT_INNGEST"; do
  if [[ "$v" == "TRANSIENT" ]]; then
    echo "TRANSIENT: Sentry query failed (window $START..$END) — retry next sweep." >&2
    exit 2
  fi
done

if [[ "$FALLBACKS" -gt 0 ]]; then
  # Per-signal counts, not just the total: the remediation differs by signal.
  # gate-degraded = zot was never ATTEMPTED (the gate degraded → fleet silently on GHCR;
  #   chase the mirror/network path — #6416 / #6288).
  # ghcr-fallback = zot WAS attempted and the pull failed (chase the pull path).
  # inngest_/app_ghcr_fallback = a fresh boot could not pull from zot.
  echo "FAIL: $FALLBACKS fallback event(s) since $START (rolling=${COUNTS[rolling]} gate-degraded=${COUNTS[gate]} inngest-freshboot=${COUNTS[freshboot]} app-freshboot=${COUNTS[appboot]}) — the fleet was served by GHCR. Investigate before retiring GHCR (do NOT proceed to 5.3-5.5)."
  exit 1
fi

# ⚠ This arm MUST keep `exit 1` (FAIL). Do NOT "fix" it to exit 2 (TRANSIENT) on the
# reasoning that a thin sample just means "not enough deploys yet" — that is not the only
# route here. In the Sentry-dark mode (#6437) ci-deploy.sh returns before every
# zot_gate_degraded_event call site, so the fleet emits NOTHING: FALLBACKS=0 with no degrade
# event, and this sample arm is the ONLY detector. TRANSIENT would make a silently
# unconfigured fleet report "retry next sweep" forever instead of blocking the retirement.
# The sample arm is a floor on GOOD evidence, not a ceiling on BAD — except here, where it is
# the only ceiling.
if [[ "$ZOT_WEB" -lt "$MIN_SAMPLE" || "$ZOT_INNGEST" -lt "$MIN_SAMPLE" ]]; then
  echo "FAIL(insufficient-sample): zot-served pulls web=$ZOT_WEB inngest=$ZOT_INNGEST (need >=$MIN_SAMPLE each) — zero fallbacks so far, but keep soaking until each image has been served by zot enough times to be conclusive."
  exit 1
fi

echo "PASS: 0 ghcr-fallbacks and zot served web=$ZOT_WEB inngest=$ZOT_INNGEST (>=$MIN_SAMPLE each) since $START — zot-primary soak holds. Safe to retire GHCR (5.3-5.5) and flip ADR-096 accepted (5.6)."
exit 0
