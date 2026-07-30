#!/usr/bin/env bash
# D10 — PRE-DESTROY pull-path health gate for the registry-luks-recut dispatch (#6929).
#
# !!! THIS GATE'S PREMISE IS RETRACTED — 2026-07-30 (#7071). READ BEFORE RELYING ON A PASS. !!!
#
# The paragraph below is retained as the ORIGINAL rationale. Its central assumption is now false,
# and the consequence is that a PASS here no longer means what it says.
#
#   ~~WHY: the recut destroys the zot store. That is only an acceptable trade because the store
#   is a DISPOSABLE GHCR MIRROR — pulls fall through to GHCR while it re-fills. If the GHCR
#   fallback path is ALREADY degraded when the recut fires, that assumption is false and the
#   dispatch would create the #6400 total-deploy-outage rather than merely tolerating an empty-
#   store window. So: refuse to destroy the store while the very path that covers its absence is
#   unhealthy.~~
#
# WHAT CHANGED. There is no GHCR fallback to be healthy or degraded: the read PAT is revoked
# (GET api.github.com/user -> 401) and the minter is disabled (pull-token mint -> 403 DENIED).
# So the empty-store window is NOT covered by anything — it is a total pull outage until the next
# CI dual-push re-fills zot. The trade this gate was written to protect no longer exists.
#
# AND ONE OF ITS OWN ABORT OPERANDS IS NOW STRUCTURALLY DARK. `ghcr-fallback` is emitted at
# ci-deploy.sh only INSIDE the success branch of `_ghcr_pull_or_recover` — i.e. only when a GHCR
# pull SUCCEEDED. With the credential revoked that event can never fire again, so the operand
# that most directly measured "is the fallback healthy" is permanently 0. The gate is not fully
# vacuous — `zot-gate-degraded`, `local-cache` and the non-vacuity floor still fire — but a PASS
# is now evidence about zot's own health only, never about cover for its absence.
#
# ADR-096 states the principle this violates, and states it about this class: "A gate that cannot
# fail is worse than no gate, because it is read as evidence."
#
# DO NOT read a PASS here as authorization to destroy the store. Re-derive the authorization
# condition before the next recut; this file has not been re-scoped, only marked.
#
# ZERO-TOLERANCE THRESHOLD. A healthy fleet emits ONLY `registry=zot`
# (apps/web-platform/infra/ci-deploy.sh registry_pull_event); `ghcr-fallback` and `local-cache`
# are both level=warning precisely because they are never expected. So ">=1 event ⇒ ABORT" has
# no false-abort surface and is a real number, not a hand-wave like "sustained hits".
#
# ── WHY SENTRY (and a CORRECTION to an earlier claim in this file) ──────────────────────────
# This gate was originally specified against `betterstack-query.sh --grep ghcr-fallback`, and an
# earlier revision of this header asserted that query "can never return a row" because "there is
# no web-host table" in Better Stack.
#
# THAT ASSERTION WAS FALSE, and the way it was reached is worth recording, because it is the
# exact failure this gate exists to prevent — reading absence-of-signal as absence-of-channel:
#
#   * `registry_pull_event` (apps/web-platform/infra/ci-deploy.sh) emits the TEXT
#     `IMAGE_PULL_OK: registry=<r> image=<i> tag=<t>` via `logger -t ci-deploy`. The string
#     "registry_pull_event" is the shell FUNCTION name and appears in no log line — so grepping
#     for it returns zero for a reason that has nothing to do with ingestion.
#   * `apps/web-platform/infra/server.tf` ships the SAME vector.toml to the WEB host, and
#     `ci-deploy` is in Vector Source 4's SYSLOG_IDENTIFIER allowlist — so web-host journald
#     lands in the SAME table as the inngest feed. Live-verified 2026-07-25: an
#     `--since 720h --grep IMAGE_PULL_OK` query returns rows carrying
#     `"SYSLOG_IDENTIFIER":"ci-deploy","host":"soleur-web-platform"`.
#   * The `--grep ghcr-fallback` zero was therefore a TRUE zero — a healthy fleet that emitted no
#     fallbacks in 30 days — not a structural absence.
#
# Sentry is retained as the query source because it is where the SEVERITY lives (these events are
# `level: "warning"` there and drive the `zot_mirror_fallback_rate` alert), and because
# scripts/followthroughs/zot-soak-6122.sh supplies a hardened query helper for exactly these tags.
# Positive control, live 2026-07-25: `feature:supply-chain op:image-pull registry:"zot"` returns
# 88 events over 720h, so the tag idiom and the credential both work.
#
# KNOWN RESIDUAL: Sentry emission from ci-deploy.sh is FAIL-OPEN (`curl … || logger`), so a Sentry
# ingest outage drops these events silently. The journald→Vector→Better Stack path does NOT have
# that property. The DENOMINATOR below is what makes that residual survivable: an outage that
# suppresses the fallback counters suppresses the zot counter too, and a zero denominator ABORTS.
#
# FAIL-CLOSED. An unreachable API, a bad token, or an unexpected payload shape ABORTS. The gate
# protects an irreversible destroy; "I could not check" must never read as "it is fine".
#
# ── THE DENOMINATOR (why zero degraded events is not, by itself, health) ────────────────────
# `total == 0` is produced by FOUR distinct states and only one of them is health:
#   1. the fleet deployed and zot served every pull            — healthy;
#   2. nothing deployed in the window (a quiet weekend)        — no evidence;
#   3. ZOT_ACTIVE=0 — the zot gate degraded, so ci-deploy skipped zot entirely and emitted
#      NOTHING while the fleet ran 100% on GHCR                — the exact state this gate exists
#                                                                to catch, scoring as clean;
#   4. the web host is Sentry-dark (the emitter's env trio unset) — every event invisible.
# So a bare "zero bad events" reading is indistinguishable from "we observed nothing at all".
# This gate therefore requires POSITIVE EVIDENCE that the pull path was exercised at all
# (registry=zot >= 1) before it will accept a zero. Precedent: zot-soak-6122.sh added the same
# denominator arm for the same reason ("nothing above proves the fleet was OBSERVED at all").
#
# Usage:
#   scripts/registry-pull-path-health.sh [--since-hours N]
#
# Env:
#   SENTRY_AUTH_TOKEN  (required) — read scope on the org's events. In CI, from Doppler
#                      prd_terraform (the same config the dispatch already reads).
#   SENTRY_ORG         (default jikigai-eu)
#   REGISTRY_PULL_HEALTH_QUERY_CMD (test seam) — invoked with the Sentry query string; must echo
#                      an integer event count, or a non-numeric token to signal a failed query.

set -uo pipefail

SINCE_HOURS=24
while [[ $# -gt 0 ]]; do
  case "$1" in
    --since-hours) SINCE_HOURS="${2-}"; shift 2 ;;
    *) echo "::error::registry-pull-path-health: unknown argument '$1'" >&2; exit 1 ;;
  esac
done

if [[ ! "$SINCE_HOURS" =~ ^[1-9][0-9]*$ ]]; then
  echo "::error::registry-pull-path-health: --since-hours must be a positive integer (got '${SINCE_HOURS}')." >&2
  exit 1
fi

ORG="${SENTRY_ORG:-jikigai-eu}"
API="${SENTRY_API_BASE:-https://sentry.io/api/0}"

# The watched signals. Both are level=warning in ci-deploy.sh and both mean "zot did not serve":
#   ghcr-fallback — zot WAS attempted and the pull failed (the pull path is degraded).
#   local-cache   — BOTH registries failed and an already-running image was reloaded. Strictly
#                   worse than ghcr-fallback: it means the GHCR cover this recut depends on was
#                   ITSELF unavailable.
# Declared as an array so "declared but never counted" is unrepresentable in source, with a
# runtime cardinality floor below so an emptied array cannot silently yield a PASS.
declare -A WATCHED=(
  [ghcr-fallback]='feature:supply-chain op:image-pull registry:"ghcr-fallback"'
  [local-cache]='feature:supply-chain op:image-pull registry:"local-cache"'
  # ZOT_ACTIVE=0 — the zot gate degraded, so ci-deploy never ATTEMPTED zot and emitted no
  # ghcr-fallback at all while the fleet ran entirely on GHCR. Without this entry that state is
  # invisible to the two counters above and scores as clean. It is recorded elsewhere in-tree as
  # the highest-volume degraded signal, so omitting it would blind the gate to its likeliest
  # real-world trigger.
  [zot-gate-degraded]='feature:supply-chain op:image-pull registry:"zot-gate-degraded"'
)

# The DENOMINATOR. Proves the pull path was exercised at all in the window; without it, "no bad
# events" and "we observed nothing" are the same reading. See the header.
DENOMINATOR_QUERY='feature:supply-chain op:image-pull registry:"zot"'

if (( ${#WATCHED[@]} != 3 )); then
  echo "::error::registry-pull-path-health: WATCHED has ${#WATCHED[@]} entries, expected 3 — refusing to report a verdict on a partial signal set." >&2
  exit 1
fi

if [[ -z "${REGISTRY_PULL_HEALTH_QUERY_CMD:-}" && -z "${SENTRY_AUTH_TOKEN:-}" ]]; then
  echo "::error::registry-pull-path-health: SENTRY_AUTH_TOKEN unset — cannot verify the GHCR fallback path is healthy. Refusing to authorize a store destroy against an unverifiable pull path." >&2
  exit 1
fi
# ONLY inside Actions. `::add-mask::` is a workflow COMMAND, not a shell builtin — outside a
# runner it is an ordinary echo that PRINTS THE TOKEN to the terminal and scrollback. The runbook
# tells the operator to run this script locally, so an unguarded mask emit would leak the live
# prd credential onto their screen every time.
if [[ -n "${GITHUB_ACTIONS:-}" && -n "${SENTRY_AUTH_TOKEN:-}" ]]; then
  echo "::add-mask::${SENTRY_AUTH_TOKEN}"
fi

START=$(date -u -d "-${SINCE_HOURS} hours" +%Y-%m-%dT%H:%M:%S 2>/dev/null) || {
  echo "::error::registry-pull-path-health: could not compute the window start." >&2; exit 1; }
END=$(date -u +%Y-%m-%dT%H:%M:%S)

# sentry_count <query> → echoes the event count, or a non-numeric token on any failure.
sentry_count() {
  if [[ -n "${REGISTRY_PULL_HEALTH_QUERY_CMD:-}" ]]; then
    $REGISTRY_PULL_HEALTH_QUERY_CMD "$1"
    return
  fi
  local enc url resp status body n
  enc=$(printf '%s' "$1" | jq -sRr @uri)
  url="${API}/organizations/${ORG}/events/?query=${enc}&start=${START}&end=${END}&per_page=100&field=title&field=timestamp"
  resp=$(curl -sS -w '\nHTTP_STATUS:%{http_code}' \
    -H "Authorization: Bearer ${SENTRY_AUTH_TOKEN}" -H "Accept: application/json" "$url" 2>/dev/null)
  status=$(printf '%s' "$resp" | sed -n 's/^HTTP_STATUS://p' | tr -d '[:space:]')
  body=$(printf '%s' "$resp" | sed '$d')
  if [[ "$status" != "200" ]]; then echo "QUERY_FAILED"; return; fi
  # Require .data to BE an array. Taking `length` with a zero default would turn an error object
  # (no .data → null → 0) into a COUNTED ZERO — a false-PASS on the one gate protecting an
  # irreversible destroy. On a shape mismatch jq errors → empty → QUERY_FAILED.
  n=$(printf '%s' "$body" | jq -r 'if (.data | type) == "array" then (.data | length) else error("no data array") end' 2>/dev/null)
  [[ "$n" =~ ^[0-9]+$ ]] && echo "$n" || echo "QUERY_FAILED"
}

echo "registry-pull-path-health: window ${START}..${END} (${SINCE_HOURS}h), org=${ORG}"

total=0
declare -A COUNTS
for k in $(printf '%s\n' "${!WATCHED[@]}" | sort); do
  n=$(sentry_count "${WATCHED[$k]}")
  if [[ ! "$n" =~ ^[0-9]+$ ]]; then
    echo "::error::registry-pull-path-health: Sentry query for '${k}' failed (window ${START}..${END}). FAIL-CLOSED: the recut destroys the zot store and this gate is what proves the GHCR fallback can cover its absence. Re-run once Sentry is reachable — do NOT proceed on an unverified pull path." >&2
    exit 1
  fi
  COUNTS[$k]=$n
  total=$(( total + n ))
done

n_zot=$(sentry_count "$DENOMINATOR_QUERY")
if [[ ! "$n_zot" =~ ^[0-9]+$ ]]; then
  echo "::error::registry-pull-path-health: the denominator query (registry=zot) failed (window ${START}..${END}). FAIL-CLOSED — without it, zero degraded events cannot be distinguished from zero observations." >&2
  exit 1
fi

echo "pull_path ghcr_fallback=${COUNTS[ghcr-fallback]} local_cache=${COUNTS[local-cache]} zot_gate_degraded=${COUNTS[zot-gate-degraded]} total=${total} threshold=0 zot_served=${n_zot}"

if (( n_zot == 0 )); then
  cat >&2 <<EOF
::error::registry-pull-path-health: ABORT — the pull path is UNOBSERVED in the last ${SINCE_HOURS}h, not proven healthy. Zero degraded events (ghcr-fallback=${COUNTS[ghcr-fallback]} local-cache=${COUNTS[local-cache]} zot-gate-degraded=${COUNTS[zot-gate-degraded]}) is only evidence when SOMETHING was served: registry=zot count is 0, so no deploy exercised the pull path at all — or the emitter is dark.

Refusing to authorize an irreversible store destroy on an absence of data.

EXIT: force a dual-push so the path is exercised, then re-dispatch:
  gh workflow run web-platform-release.yml -f bump_type=patch
(or widen the window with a longer --since-hours if you are certain the fleet has been idle.)
EOF
  exit 1
fi

if (( total > 0 )); then
  cat >&2 <<EOF
::error::registry-pull-path-health: ABORT — ${total} degraded pull event(s) in the last ${SINCE_HOURS}h (ghcr-fallback=${COUNTS[ghcr-fallback]} local-cache=${COUNTS[local-cache]}). A healthy fleet emits ONLY registry=zot, so ANY of these means the GHCR fallback path is already degraded.

This recut DESTROYS the zot store and depends on GHCR covering the empty-store window. Firing it now would turn a tolerable window into a total-deploy outage (#6400).

EXIT: the degradation must clear first — check the zot_mirror_fallback_rate alert state, then re-fire. If the degradation IS the reason you want to recut, that is an INCIDENT path, not a recut: fix the pull path first.
EOF
  exit 1
fi

echo "registry-pull-path-health: zero degraded pull events in ${SINCE_HOURS}h."

# FAIL CLOSED (2026-07-30, #7071). Everything above still runs — the counts are real and
# worth printing — but a clean count no longer answers the question this gate was built to
# answer, so it must not return 0 as though it did.
#
# The gate authorized destroying the zot store on the strength of "GHCR covers the
# empty-store window". That premise is retracted, and the operand that measured it
# (`ghcr-fallback`) can no longer fire at all, so a PASS here is now a statement about
# zot's own health that reads as authorization to destroy the only thing serving pulls.
# ADR-096, about this exact class: "A gate that cannot fail is worse than no gate, because
# it is read as evidence."
#
# Emitting a PASS plus a warning was tried first and rejected: a green exit is what the
# calling workflow branches on, and a NOTE nobody re-reads is not a gate. Reversing this is
# one line, deliberately — destroying production's only pull path should cost an explicit
# edit by someone who has re-derived the authorization condition, not a default-open path.
cat >&2 <<'EOF'
::error::registry-pull-path-health: REFUSING — this gate's premise is retracted and it has no valid PASS condition (#7071).

The recut destroys the zot store. That was acceptable only while GHCR covered the empty-store window. GHCR is no longer readable (read PAT revoked -> 401; minter disabled -> 403 DENIED), so the window is now a TOTAL pull outage until the next CI dual-push re-fills zot. Separately, this gate's most direct operand is dark: `ghcr-fallback` is emitted only inside the SUCCESS branch of a GHCR pull, so it can never fire and can never abort anything.

The counts printed above are real, and they describe ZOT's health. They do not describe cover for zot's absence, because there is none.

TO PROCEED you must re-derive what should authorize a recut and encode it here. Candidates, none of them chosen: gate on a successful CI dual-push within N hours; pre-stage the live digests outside the destroyed volume and gate on a rehearsed restore; require a second mirror to exist; or refuse until a GHCR pull credential is restored. See this script's header and ADR-096 clause (g), which records that the restoration paths have no tracker.
EOF
exit 1
