#!/usr/bin/env bash
# D10 — PRE-DESTROY authorization gate for the registry-luks-recut dispatch (#6929 / #7277).
#
# WHAT AUTHORIZES A RECUT, in one sentence: a recut is authorized only when CI has just proven,
# by executing it, that every image reference production depends on can be re-materialised into
# an empty registry from GHCR — a source that survives the destroy.
#
# ── WHY THE PREVIOUS AUTHORIZATION CONDITION COULD NOT BE REPAIRED ──────────────────────────
# Until 2026-07-30 this gate authorized a destroy on "GHCR covers the empty-store window", and
# measured that with Sentry counters. Two independent failures ended that:
#
#   * the PREMISE was retracted (#7071). The host->GHCR edge is dead: the read PAT is revoked
#     (401) and the minter is disabled (403 DENIED). Nothing covers the window.
#   * the OPERAND was dark. `ghcr-fallback` is emitted in ci-deploy.sh only INSIDE the success
#     branch of a GHCR pull, so with the credential revoked it can never fire and could never
#     abort anything.
#
# The 2026-07-30 revision responded by refusing unconditionally. That was the right call at the
# time and the wrong thing to leave in place: it made the recut unfireable during exactly the
# incident it exists to recover from. This rewrite does not repair the old premise — it REPLACES
# it. The new criterion never claims the empty-store window is covered. It claims the window is
# ENDED, by a restore that has just been executed successfully in rehearsal and is then executed
# for real by a chained job.
#
# ── THE INDEPENDENCE CRITERION ───────────────────────────────────────────────────────────────
# A gate on an irreversible destroy may not depend on the component whose failure motivates it.
# This gate depends on GHCR-read-from-CI, which is NOT that component: the release pipeline's
# failing half is the PUSH into prod zot (9 consecutive `copy_v` failures), while its GHCR-read
# half demonstrably works. If GHCR-read-from-CI is broken there is genuinely nothing to restore
# from, and refusing is then correct rather than a deadlock.
#
# ── THE PREDICATES ───────────────────────────────────────────────────────────────────────────
#   A0  inventory derived from production's OWN pins           ABORTING
#   A1  source proof: every pin resolves at GHCR               ABORTING
#   A2  rehearsed restore into a throwaway registry            POSITIVE — this IS the pass condition
#   A3  non-vacuity floor                                      ABORTING
#   A4  sink-credential validity at the Cloudflare Access edge ABORTING on a MEASURED dead count
#   A5  live sink proof against prod zot                       ADVISORY-DEGRADING (see below)
#
# Every predicate has an explicit could-not-measure bucket that ABORTS, and each bucket is
# evaluated BEFORE any comparison. The verdict switch has no default-pass arm. "I could not
# check" must never read as "it is fine" on the one gate protecting an irreversible destroy.
#
# ── A5 IS DELIBERATELY THE INVERSE, AND THIS IS THE MOST DANGEROUS LINE IN THE FILE ─────────
# Everywhere else here, "cannot measure" means "cannot prove safe" and aborts. In A5 the
# UNmeasurability *is* the incident, so it degrades and proceeds.
#
# ONLY AUTHORISATION AND CORRECTNESS FAILURES ABORT. AVAILABILITY FAILURES DEGRADE.
#
# An earlier draft put `connection reset by peer` mid-upload in the ABORT bucket. That is the
# literal failure text of release run 30988480437 — the incident this gate exists to authorise
# recovery from — so that draft would have aborted TODAY, for the same reason the old gate did.
# A credential rejection, by contrast, is independent of zot's health: it means the post-destroy
# restore cannot work no matter how healthy the rebuilt host is, which is precisely the state in
# which a destroy is unrecoverable.
#
# Do not "fix" this asymmetry into consistency. It is pinned by test rows in both directions.
#
# ── WHAT WAS REMOVED, AND WHERE EACH ROLE WENT ───────────────────────────────────────────────
#   the three Sentry counters   -> premise retracted; the surviving question ("can the source
#                                  still serve?") is answered directly by A1.
#   the registry="zot" denominator -> its anti-vacuity role is LOAD-BEARING and is preserved by
#                                  A3, which is a positive observation of the thing that matters
#                                  and is available during a zot outage. The denominator was
#                                  zero exactly then.
#   the `zot_served == 0` abort -> deleted outright. It fired during the crash-loop the recut
#                                  recovers from, so it was a second unfireable gate hiding
#                                  behind the first. Blocking on it IS the deadlock.
#
# Two structural safety properties are kept verbatim: fail-closed on any unmeasurable input, and
# the GITHUB_ACTIONS-guarded `::add-mask::` emit (unguarded, it prints the live prd credential to
# the operator's terminal, because the runbook tells them to run this locally).
#
# Usage:
#   scripts/registry-pull-path-health.sh --rehearse-target <host:port> [--tags-out <path>]
#   scripts/registry-pull-path-health.sh --prepare --tags-out <path>
#
# Env:
#   APP_DOMAIN_BASE   (required) — the /health URL is derived from it, never hard-coded.
#   ZOT_PUSH_USER / ZOT_PUSH_TOKEN — passed through to the rehearsal.
#   Test seams, one per external dependency, each able to emit every classified token:
#     REGISTRY_GATE_HEALTH_CMD   REGISTRY_GATE_CRANE_CMD   REGISTRY_GATE_RESTORE_CMD
#     REGISTRY_GATE_DRIFT_CMD    REGISTRY_GATE_SINK_CMD

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

REHEARSE_TARGET=""
TAGS_OUT=""
PREPARE_ONLY=0

abort() { # $1 = predicate label, rest = message
  local p="$1"; shift
  echo "::error::registry-pull-path-health: ${p} ABORT — $*" >&2
  echo "verdict=REFUSED predicate=${p}"
  exit 1
}
usage_err() { echo "::error::registry-pull-path-health: $*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --rehearse-target) REHEARSE_TARGET="${2-}"; shift 2 ;;
    --tags-out)        TAGS_OUT="${2-}";        shift 2 ;;
    --prepare)         PREPARE_ONLY=1;          shift ;;
    *) usage_err "unknown argument '$1'" ;;
  esac
done

HEALTH_CMD="${REGISTRY_GATE_HEALTH_CMD:-}"
CRANE="${REGISTRY_GATE_CRANE_CMD:-crane}"
RESTORE="${REGISTRY_GATE_RESTORE_CMD:-${ROOT}/scripts/registry-restore-from-ghcr.sh}"
DRIFT="${REGISTRY_GATE_DRIFT_CMD:-${ROOT}/scripts/check-cloudflare-token-drift.sh}"
SINK_CMD="${REGISTRY_GATE_SINK_CMD:-}"

WORK="$(mktemp -d)" || usage_err "could not create a scratch directory."
trap 'rm -rf "$WORK"' EXIT

# ── A3's declared constants. ────────────────────────────────────────────────────────────────
# FLOOR is declared here WITH its derivation, not left as a placeholder, because an under-set
# floor is the vacuity hole A3 exists to close. Raising it is the deliberate act that admits a
# new required image.
#
# FLOOR = 2:
#   jikig-ai/soleur-web-platform        at production's own /health version   (required)
#   jikig-ai/soleur-inngest-bootstrap   at the cloud-init.yml pin             (required)
# soleur-inngest-config is `conditional` and does NOT count: it is not published at GHCR
# (measured 2026-08-05 — `crane ls` returns NAME_UNKNOWN), and a gate listing it as required
# would abort forever on a repo that does not exist, creating exactly the new deadlock this
# rewrite exists to remove.
readonly FLOOR=2

# The pin set is a SOURCE-LEVEL declaration, so "declared but never counted" is unrepresentable
# — the same discipline the removed signal array carried, re-pointed at an instrument that is
# available during a zot outage. Each entry: repo|tag-derivation|disposition.
#
# (The removed array's name is spelled nowhere in this file on purpose: AC8 is a whole-file
# grep for the retired Sentry operands, and a comment naming one would false-fail a correct
# gate — the same trap AC1 documents for the retired refusal phrase.)
#
# This idiom transfers here precisely BECAUSE the set is declared in source. It would NOT have
# transferred to a derive-from-`crane ls` design, where the set is computed at runtime and there
# is no source arity to pin — applying it there would have been cargo-culting an assertion that
# cannot hold.
readonly REQUIRED_PINS=(
  "jikig-ai/soleur-web-platform|health-version"
  "jikig-ai/soleur-inngest-bootstrap|cloud-init-pin"
)
readonly CONDITIONAL_PINS=(
  "jikig-ai/soleur-inngest-config|terraform-digest-pointer"
)

declared_required="${#REQUIRED_PINS[@]}"
if (( declared_required != FLOOR )); then
  abort A3 "the declared required-pin set has ${declared_required} entries but FLOOR is ${FLOOR}. Refusing to report a verdict on a pin set that does not match its own floor — a silently downgraded 'required' entry is how this gate would go green while production stayed unrestorable."
fi

# classify <last-stderr-line> — shared failure vocabulary.
#
# Classify on the LAST line, never on rc and never on line 1: crane exits 1 for every failure
# class, and its first line is the same `HEAD request failed, falling back on GET: …` for
# tag-absent, repo-absent AND DNS failure (measured 2026-08-05). rc and line 1 are buckets, not
# diagnoses. There is no NAME_UNKNOWN arm: GHCR emits that only from the tags API, and every
# call here is a manifest read. If one is ever added, it falls to UNKNOWN and aborts — loud, and
# the safe direction.
classify() {
  case "$1" in
    *MANIFEST_UNKNOWN*|*"manifest unknown"*)                          echo NOTFOUND ;;
    *UNAUTHORIZED*|*DENIED*|*"authentication required"*)              echo DENIED ;;
    *"no such host"*|*"dial tcp"*|*"connection refused"*|\
    *"i/o timeout"*|*"TLS handshake"*)                                echo NETWORK ;;
    *) echo UNKNOWN ;;
  esac
}

# The `tr '\n' ' '` is a WORKFLOW-COMMAND INJECTION GUARD, not formatting. Registry stderr is
# externally-influenced text interpolated into `::error::` output, and GitHub parses workflow
# commands per LINE — a newline followed by `::add-mask::` inside it would be executed.
last_err() { tail -c 400 "$1" 2>/dev/null | tr '\n' ' ' || true; }

# ── A0 — inventory derivation, from production's OWN pins. ──────────────────────────────────
# Zero reads of zot: reading the digest list out of zot would make this gate depend on the
# failing component, and the live catalog is unreadable during a crash-loop.
#
# Derived from what production actually PINS, never by re-deriving zot's retention policy. That
# was rejected on three measured grounds: it reimplements a policy living in
# cloud-init-registry.yml and will drift (the first draft transcribed it wrongly, dropping the
# `sha256-.*` signature rule); it is actively harmful, because pushing ~11 tags per repo into a
# fresh store with hourly gc and keep-5 is the maximal-pressure case for the out-of-order
# eviction the repo already warns about, and could evict the very tag cloud-init pins; and it
# buys nothing, because production pins a handful of refs and those are the whole obligation.
[[ -n "${APP_DOMAIN_BASE:-}" ]] || abort A0 "APP_DOMAIN_BASE is unset, so the /health URL cannot be derived. Hard-coding it here would make the committed-config read decorative."
HEALTH_URL="https://app.${APP_DOMAIN_BASE}/health"

if [[ -n "$HEALTH_CMD" ]]; then
  "$HEALTH_CMD" > "$WORK/health.json" 2>"$WORK/health.err"; health_rc=$?
else
  # `Cache-Control: no-cache` is load-bearing: a cached edge response carrying a previous
  # version would satisfy the membership assertion below while the actually-running build is
  # unrestorable.
  curl -sf --max-time 20 -H 'Cache-Control: no-cache' "$HEALTH_URL" \
    > "$WORK/health.json" 2>"$WORK/health.err"; health_rc=$?
fi
(( health_rc == 0 )) || abort A0 "could not read ${HEALTH_URL} (rc=${health_rc}). This is a could-not-measure outcome, evaluated before any comparison, and it is NOT a zot-induced deadlock: /health is served by already-running containers and survives a zot outage. $(last_err "$WORK/health.err")"

command -v jq >/dev/null 2>&1 || abort A0 "jq is unavailable, so /health cannot be parsed."

PROD_VERSION="$(jq -r '.version // empty' "$WORK/health.json" 2>/dev/null)"
PROD_SHA="$(jq -r '.build_sha // empty' "$WORK/health.json" 2>/dev/null)"
[[ -n "$PROD_VERSION" ]] || abort A0 "/health returned no parseable .version field, so the restore set cannot be derived. Refusing to treat an unparseable response as an empty inventory."
# build_sha is asserted as well as version, deliberately: a cached edge response carrying a
# previous version would otherwise satisfy A1 while the build actually running is unrestorable.
[[ -n "$PROD_SHA" ]] || abort A0 "/health returned .version but no .build_sha. Both are required — a cached edge response can carry a stale version with the running build unrestorable, and asserting only the version would not detect it."

echo "A0 inventory: version=${PROD_VERSION} build_sha=${PROD_SHA} floor=${FLOOR}"

# resolve_tag <derivation> — production's pin, read from where production declares it.
resolve_tag() {
  case "$1" in
    health-version)  printf 'v%s' "$PROD_VERSION" ;;
    cloud-init-pin)
      # Read from the file, never hard-coded in this gate: the pin is production's, and a copy
      # here would drift silently the first time cloud-init is bumped.
      grep -oE 'soleur-inngest-bootstrap:v[0-9]+\.[0-9]+\.[0-9]+' \
        "${REGISTRY_GATE_CLOUD_INIT:-${ROOT}/apps/web-platform/infra/cloud-init.yml}" 2>/dev/null \
        | head -1 | sed 's/.*://' ;;
    terraform-digest-pointer) printf 'latest' ;;
    *) printf '' ;;
  esac
}

# ── A1 — source proof. A2's precondition and the operator-facing classifier. ────────────────
# Not an independent fifth leg: `crane copy` performs the same source resolution, so A1 proves
# nothing A2 does not. Its value is narrower and still worth having — it aborts on a GHCR
# outage BEFORE multiple GB start moving, and it produces the classified message.
resolved=0
: > "$WORK/manifest.entries"

MISSED=""

resolve_one() { # $1 = repo, $2 = derivation, $3 = disposition
  local repo="$1" tag err cls digest
  tag="$(resolve_tag "$2")"
  if [[ -z "$tag" ]]; then
    # A required pin whose tag cannot be derived from production's own configuration is RECORDED
    # AS MISSED and left to A3's floor, rather than aborted here.
    #
    # That is deliberate. Aborting immediately would leave the floor check below unreachable
    # through every input this gate accepts — and an unreachable assertion is one a future edit
    # can delete with the whole suite still green (measured: it survived a mutation battery).
    # Routing the one input that CAN under-fill the pin set through the floor is what makes the
    # floor a live guard rather than decoration.
    if [[ "$3" == "required" ]]; then
      MISSED="${MISSED}${MISSED:+, }${repo} (tag underivable via '${2}')"
      echo "A1 ${repo}: tag could not be derived from committed config — recorded as MISSED"
    fi
    return 0
  fi
  $CRANE digest "ghcr.io/${repo}:${tag}" > "$WORK/d.out" 2>"$WORK/d.err"
  digest="$(grep -oE '^sha256:[0-9a-f]{64}$' "$WORK/d.out" 2>/dev/null | head -1 || true)"
  if [[ -n "$digest" ]]; then
    printf '{"repo":"%s","tag":"%s","disposition":"%s"}\n' "$repo" "$tag" "$3" >> "$WORK/manifest.entries"
    [[ "$3" == "required" ]] && resolved=$(( resolved + 1 ))
    echo "A1 ${repo}:${tag} -> ${digest} (${3})"
    return 0
  fi
  err="$(last_err "$WORK/d.err")"
  cls="$(classify "$err")"
  if [[ "$3" == "conditional" && "$cls" == "NOTFOUND" ]]; then
    # A declared skip, recorded rather than silent. The floor counts only `required` entries, so
    # a conditional skip can never make this gate vacuous.
    echo "A1 ${repo}:${tag} -> absent at GHCR (conditional, declared skip)"
    return 0
  fi
  case "$cls" in
    NOTFOUND) abort A1 "required source ghcr.io/${repo}:${tag} did not resolve: absent, OR NOT VISIBLE TO THIS CREDENTIAL. GHCR returns MANIFEST_UNKNOWN for both (measured), so this does NOT prove the tag was deleted — check the job's 'packages: read' permission before concluding it was. crane: ${err}" ;;
    DENIED)   abort A1 "GHCR rejected this credential for ${repo}:${tag}. crane: ${err}" ;;
    NETWORK)  abort A1 "GHCR was unreachable resolving ${repo}:${tag} (network/DNS). Nothing has been destroyed. crane: ${err}" ;;
    *)        abort A1 "resolving ${repo}:${tag} failed in a way this gate cannot classify: UNKNOWN. An unclassified failure must read as neither 'absent' nor 'fine'. crane: ${err}" ;;
  esac
}

for entry in "${REQUIRED_PINS[@]}";    do resolve_one "${entry%%|*}" "${entry##*|}" required;    done
for entry in "${CONDITIONAL_PINS[@]}"; do resolve_one "${entry%%|*}" "${entry##*|}" conditional; done

# ── A3 — the non-vacuity floor, on what was actually RESOLVED. ──────────────────────────────
if (( resolved != FLOOR )); then
  abort A3 "resolved ${resolved} required references but FLOOR is ${FLOOR}${MISSED:+ — missed: ${MISSED}}. An inventory below its floor makes every predicate below pass while proving nothing: this is the vacuity hole the removed Sentry denominator used to cover, and it is the single most likely way this gate fails open."
fi

# Emit the pinned manifest the restore engine consumes. On the resume arm the recut has ALREADY
# destroyed the volume, so this derivation must have run there too — which is why the calling
# workflow puts it in an UNCONDITIONAL prepare step.
MANIFEST="${TAGS_OUT:-$WORK/pins.json}"
{
  printf '{ "floor": %s, "entries": [' "$FLOOR"
  paste -sd, "$WORK/manifest.entries"
  printf '] }'
} > "$MANIFEST" 2>/dev/null || abort A0 "could not write the pin manifest to ${MANIFEST}."
echo "A3 floor satisfied: resolved=${resolved} floor=${FLOOR} manifest=${MANIFEST}"

if (( PREPARE_ONLY == 1 )); then
  echo "verdict=PREPARED manifest=${MANIFEST}"
  exit 0
fi

[[ -n "$REHEARSE_TARGET" ]] || usage_err "--rehearse-target <host:port> is required to render a verdict. A2 — the rehearsed restore — IS the pass condition, so it cannot be skipped."

# ── A4 — sink-credential validity, graded live at the Cloudflare Access edge. ───────────────
# The repo already contains a live grader for exactly this credential class, and it does not
# touch zot: scripts/zot-mirror-diagnosis.sh's `zot_mirror_verdict` verifies the registry-push CF
# Access service token AT THE ACCESS EDGE. Its own documentation of the `live` arm is why this
# satisfies the independence criterion BY CONSTRUCTION rather than by argument: live is
# "where a crash-looping or otherwise unreachable origin lands". The Access edge is up whether
# or not zot is.
#
# THE TRAP THIS ORDER EXISTS TO AVOID: zot_mirror_verdict makes ZERO network requests. It is
# pure arithmetic over a JSON file the DETECTOR must produce first. Sourcing only the grader
# returns `unmeasured`, which maps to DEGRADE — i.e. a predicate that runs, prints, and can
# never abort. That is the dark-operand defect this whole rewrite exists to remove,
# reintroduced inside the predicate meant to close it. So: run the detector, THEN grade.
#
# Sourcing constraint (load-bearing): zot-mirror-diagnosis.sh's header states it must NOT
# `set -euo pipefail`, because it is sourced into steps already running under `bash -eo
# pipefail`. Do not wrap it in a subshell that swallows the verdict.
DRIFT_JSON="$WORK/drift.json"
if [[ -x "$DRIFT" ]]; then
  "$DRIFT" --json-file "$DRIFT_JSON" > "$WORK/drift.out" 2>"$WORK/drift.err"; drift_rc=$?
else
  drift_rc=2
fi

if [[ -n "${REGISTRY_GATE_VERDICT_CMD:-}" ]]; then
  # Seam for the grader itself, so the out-of-vocabulary arm below is reachable in tests. The
  # real grader has a closed four-value vocabulary and cannot produce a fifth, which is exactly
  # why that arm would otherwise be untestable — and an untested abort arm is indistinguishable
  # from a missing one.
  a4_verdict="$("$REGISTRY_GATE_VERDICT_CMD" "$drift_rc" "$DRIFT_JSON" 2>/dev/null)"
else
  # shellcheck source=/dev/null
  if [[ -r "${ROOT}/scripts/zot-mirror-diagnosis.sh" ]]; then
    . "${ROOT}/scripts/zot-mirror-diagnosis.sh"
  fi
  if declare -F zot_mirror_verdict >/dev/null 2>&1; then
    a4_verdict="$(zot_mirror_verdict "$drift_rc" "$DRIFT_JSON")"
  else
    # Deriving it here would duplicate a classifier whose exit-code discipline is already
    # written and reviewed; but a missing grader is a could-not-measure outcome, not a pass.
    a4_verdict="unmeasured"
  fi
fi

case "$a4_verdict" in
  live)
    echo "A4 sink credential: live (Cloudflare Access ADMITTED these credentials; rotation ruled OUT by measurement)" ;;
  stale)
    abort A4 "the registry-push CF Access service token is MEASURED DEAD (json .dead > 0). This is the ONLY arm on which rotation is the remedy, and it means the post-destroy restore cannot authenticate no matter how healthy the rebuilt host is. Nothing has been destroyed." ;;
  unverifiable|unmeasured)
    # NOT an accusation: the detector's own cause vocabulary all carries "Do NOT rotate", and
    # `unmeasured` explicitly "ranks nothing". Degrading here is correct; aborting would
    # deadlock the gate on the detector's own blind spots.
    echo "A4 sink credential: ${a4_verdict} — DEGRADED, not an accusation. a4_credential=${a4_verdict}" ;;
  *)
    abort A4 "the credential grader returned '${a4_verdict}', which is outside its documented four-value vocabulary. An unrecognised verdict must not be read as either health or failure." ;;
esac

# ── A2 — the rehearsed restore. THIS IS THE PASS CONDITION. ────────────────────────────────
# It proves the restore SCRIPT is correct against a real registry HTTP API — argv, auth, ref
# construction, digest parity, blob completeness — before anything is destroyed.
#
# REJECTED ALTERNATIVE, recorded because it is strictly stronger and a reviewer will ask for it:
# rehearse against PRODUCTION zot. That would additionally prove the tunnel, the live
# credential, the real zot version and the real accessControl, eliminating A4's residual. It is
# rejected because it depends on the component whose failure motivates the recut — during a
# crash-loop that rehearsal aborts exactly when the gate is needed. This plan's own independence
# criterion, applied to itself.
[[ -x "$RESTORE" ]] || abort A2 "the restore engine is not executable at ${RESTORE}, so the pass condition cannot be exercised."
"$RESTORE" --target "$REHEARSE_TARGET" --tags-from "$MANIFEST" > "$WORK/restore.out" 2>&1
restore_rc=$?
sed 's/^/    /' "$WORK/restore.out" 2>/dev/null | tail -20
if (( restore_rc != 0 )); then
  case "$restore_rc" in
    2) abort A2 "the rehearsal failed with exit 2 (source unavailable) — GHCR could not be read, so there is nothing to restore FROM. Refusing to destroy the only remaining copy." ;;
    3) abort A2 "the rehearsal failed with exit 3 (sink unavailable) — the throwaway registry did not accept the write. This is a rehearsal-harness fault, not a production signal, but it means the pass condition was never established." ;;
    4) abort A2 "the rehearsal failed with exit 4 (verification mismatch) — the restore produced a registry whose contents do not match GHCR, or whose blobs are incomplete. A host would fail these pulls. This is the defect the gate exists to catch." ;;
    5) abort A2 "the rehearsal failed with exit 5 (credential unusable) — the rehearsal could not authenticate to the throwaway." ;;
    6) abort A2 "the rehearsal failed with exit 6 (could-not-classify) — the restore engine hit a failure it could not name, so the pass condition is unproven." ;;
    *) abort A2 "the rehearsal failed with an unenumerated exit ${restore_rc}. Every exit code of the restore engine is supposed to be enumerated; an unrecognised one is a could-not-measure outcome." ;;
  esac
fi
echo "A2 rehearsal: the full required pin set was restored and blob-verified into ${REHEARSE_TARGET}"

# ── A5 — live sink proof. ADVISORY-DEGRADING. Read the header before changing this. ─────────
# The first draft of this design had NO predicate that observed prod zot at all. It answered
# "must not depend on the failing component" by never looking at it — a different and much
# weaker property. It would have authorised destroying a sink it had never observed, then
# chained into that sink the exact `crane copy` write with a measured 9-of-9 failure record.
sink_outcome="unmeasured"
if [[ -n "$SINK_CMD" ]]; then
  sink_outcome="$("$SINK_CMD" 2>/dev/null || echo unmeasured)"
fi

case "$sink_outcome" in
  ok)
    echo "A5 sink probe: WRITE SUCCEEDED against live prod zot. A4's staleness residual is now measured, not assumed. sink_probe=ok" ;;
  credential_rejected)
    abort A5 "prod zot is REACHABLE but REJECTED the credential (401/403/DENIED, or a CF Access admission refusal). This is an AUTHORISATION failure and it is independent of zot's health: the post-destroy restore cannot work no matter how healthy the rebuilt host is. This is exactly the state A4 could not see, and the state in which a destroy is unrecoverable." ;;
  wrong_digest)
    abort A5 "the probe write COMPLETED but produced the WRONG DIGEST. That is a measured correctness failure, not an availability one." ;;
  *)
    # EVERY other outcome — reset mid-upload, timeout, 5xx, origin unreachable, tunnel down, or
    # unclassifiable — PROCEEDS with a named degradation. These are the MOTIVATING condition.
    # A gate that aborts on them cannot authorise the recovery it exists to authorise.
    echo "A5 sink probe: could not measure the live sink ('${sink_outcome}'). PROCEEDING with a named degradation — availability failures of the sink are the motivating condition for this recut, not a reason to refuse it. sink_probe=unmeasured" ;;
esac

# ── verdict ─────────────────────────────────────────────────────────────────────────────────
# ONLY inside Actions. `::add-mask::` is a workflow COMMAND, not a shell builtin — outside a
# runner it is an ordinary echo that PRINTS THE TOKEN to the terminal and scrollback, and the
# runbook tells the operator to run this gate locally.
if [[ -n "${GITHUB_ACTIONS:-}" && -n "${ZOT_PUSH_TOKEN:-}" ]]; then
  echo "::add-mask::${ZOT_PUSH_TOKEN}"
fi

echo "verdict=AUTHORIZED floor=${FLOOR} resolved=${resolved} a4_credential=${a4_verdict} sink_probe=${sink_outcome} rehearsal=${REHEARSE_TARGET}"
echo "registry-pull-path-health: a recut is AUTHORIZED — CI has just re-materialised production's full required pin set into an empty registry from GHCR and verified its blobs."
exit 0
