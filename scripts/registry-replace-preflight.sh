#!/usr/bin/env bash
# Read-only preflight for the registry-host-replace dispatcher (#7555).
#
# ── THIS IS DELIBERATELY NOT scripts/registry-pull-path-health.sh ───────────────────────────
# That file is the D10 PRE-DESTROY authorization gate for `registry-luks-recut`. Do not "simplify"
# this by calling it. Three independent grounds, each measured rather than argued:
#
#   1. D10's A1/A2 authorize a destroy on "the store can be re-materialised from GHCR". That is
#      earned for a RECUT, where GHCR is the restore source. `registry-host-replace` PRESERVES the
#      volume (`store_destroyed==0`, enforced by registry_host_replace_gate in
#      apply-web-platform-infra.yml), so the restore source is the volume, not GHCR. Wiring A1/A2
#      would abort the deadline fix on a GHCR condition the replace does not depend on.
#   2. D10's A4 aborts on a measured-dead CF Access push credential. But `/etc/zot/htpasswd` is
#      baked at boot from Doppler by cloud-init-registry.yml, so a pre-replace credential
#      rejection means the running host's bake has diverged — and the remedy for that divergence
#      IS a host replace. It would block the recovery on the condition the recovery cures.
#   3. D10 renders its verdict by EXECUTING a restore rehearsal, i.e. by pushing images. A
#      precondition that mutates the registry it is about to replace is not a health check.
#
# The plan for #7555 said "reuse registry-pull-path-health.sh". The authority that plan CITES for
# the hazard — scheduled-zot-restart-loop.yml's remediation block — prescribes a read-only
# betterstack query instead, and does not mention that script. This file implements the cited
# mechanism. Decision + the three grounds: ADR-190 §"Why the replace pre-check is not the D10
# recut gate".
#
# ── WHAT IT CHECKS ─────────────────────────────────────────────────────────────────────────
#   P0  credentials/query readable ......... GATING, fail-closed
#   P1  no sustained local-cache pulls ..... GATING   (the #6400 hazard)
#   P2  ghcr-fallback event count .......... ADVISORY ONLY — MUST NOT GATE (see below)
#   P3  no in-progress release run ......... GATING
#   P4  live zot serving probe ............. DELIBERATELY ABSENT (see below)
#   P5  the replace will be OBSERVABLE ..... GATING   (control + container-log channel)
#   P6  the boot-image asset exists ........ GATING, fail-closed (#8714 5.3b-iii)
#
# Output: a single `verdict=` line on stdout. Exit 0 = clear to dispatch, non-zero = do not.
#
# Usage: scripts/registry-replace-preflight.sh [--manual] | --print-asset | --check-asset
#   --print-asset  print the release asset the rendered user_data will fetch (repo/tag/asset/
#             sha256/url, derived from zot-registry.tf exactly as P6 derives it) and exit. Read-only,
#             no credentials.
#   --check-asset  run ONLY P6 (the boot-image asset exists and matches T) and exit. The gate the
#             other registry-host-creating routes call before terraform creates a host
#             (apply-web-platform-infra.yml registry_host_replace / registry_luks_recut /
#             registry_region_migrate), and rule-audit's standing probe. Needs gh + GH_TOKEN.
#   --manual  this run is the operator's re-fire of a refused/dark replace. Skips P1 only.
#             A FLAG, NOT AN ENV VAR, on purpose: the caller that may set it is the
#             workflow_dispatch arm, and `github.event_name` is unforgeable by the caller,
#             whereas an env var of the same name is exactly the shape the seam loop below
#             refuses. REGISTRY_PREFLIGHT_MANUAL is honoured OUTSIDE Actions for local use and
#             refused inside it, so there is no env route to a P1 downgrade in production.
# Env seams (tests only, one per external dependency):
#   REGISTRY_PREFLIGHT_QUERY_CMD   REGISTRY_PREFLIGHT_RUNS_CMD   REGISTRY_PREFLIGHT_TF

set -uo pipefail

# XTRACE REFUSAL (#7797). This script handles a live credential, and `set -x`
# would print it — xtrace expands before any masking hook can see the line, so
# refusing is the only reliable mitigation rather than a belt-and-braces one.
case "$-" in
  *x*) printf '[FATAL] refusing to run under xtrace: this script handles a live credential and -x would print it (see #7797)\n' >&2; exit 78 ;;
esac

MANUAL=0
PRINT_ASSET=0
CHECK_ASSET=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --manual) MANUAL=1; shift ;;
    --print-asset) PRINT_ASSET=1; shift ;;
    --check-asset) CHECK_ASSET=1; shift ;;
    -h|--help) sed -n '1,40p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "registry-replace-preflight: unknown argument '$1'" >&2; exit 2 ;;
  esac
done

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
QUERY_CMD="${REGISTRY_PREFLIGHT_QUERY_CMD:-${ROOT}/scripts/betterstack-query.sh}"
RUNS_CMD="${REGISTRY_PREFLIGHT_RUNS_CMD:-gh}"
WINDOW="${REGISTRY_PREFLIGHT_WINDOW:-24h}"
TF_FILE="${REGISTRY_PREFLIGHT_TF:-${ROOT}/apps/web-platform/infra/zot-registry.tf}"
# P5's two markers. The control rides the HOST heartbeat transport; the channel marker rides the
# CONTAINER-LOG transport that #7556 actually reads. They must stay on different transports or
# P5's positive control proves nothing.
P5_CONTROL_MARKER="${REGISTRY_PREFLIGHT_P5_CONTROL:-SOLEUR_ZOT_DISK}"
P5_CHANNEL_MARKER="${REGISTRY_PREFLIGHT_P5_CHANNEL:-HTTP API}"

# THE TEST SEAMS ARE REFUSED ON THE PRODUCTION PATH (#7555 review). "tests only" was a comment,
# not a mechanism: `REGISTRY_PREFLIGHT_QUERY_CMD=/bin/true REGISTRY_PREFLIGHT_RUNS_CMD=/bin/true`
# makes every predicate pass and prints a verdict line BYTE-IDENTICAL to a real clean reading —
# on the sole gate in front of an irreversible production host replace. The sibling D10 gate
# already carries this refusal; it was the one thing worth copying from it.
#
# REGISTRY_PREFLIGHT_MANUAL is in this list even though it is not a command seam: setting it
# DOWNGRADES P1 from gating to advisory, which is the same "manufacture a clear verdict" power
# as the command seams. The supported production route is the `--manual` flag, passed only from
# the workflow_dispatch arm. Outside Actions the env var still works, for local reproduction.
if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
  # ZOT_WRITERS and the two P5 markers are on this list for the same reason as the command seams,
  # and their absence was measured, not theorised: with the three real writers mid-push,
  # retargeting REGISTRY_PREFLIGHT_ZOT_WRITERS at an idle workflow turns `verdict=REFUSED
  # predicate=P3` into `verdict=CLEAR ... in_progress_releases=0`. That is exactly the
  # "manufacture a CLEAR verdict" power this loop's own message describes. Pointing both P5
  # markers at a common substring makes P5 pass trivially, same class.
  #
  # WAIT_SECS and POLL_SECS are deliberately NOT here: they can only shorten the wait, which
  # refuses earlier. A seam that can only over-refuse is not a bypass.
  # REGISTRY_PREFLIGHT_TF: pointing P6 at a doctored .tf would make it check an asset the host
  # will never fetch -- the same manufactured-CLEAR power.
  for _seam in REGISTRY_PREFLIGHT_QUERY_CMD REGISTRY_PREFLIGHT_RUNS_CMD REGISTRY_PREFLIGHT_WINDOW REGISTRY_PREFLIGHT_MANUAL \
               REGISTRY_PREFLIGHT_ZOT_WRITERS REGISTRY_PREFLIGHT_P5_CONTROL REGISTRY_PREFLIGHT_P5_CHANNEL \
               REGISTRY_PREFLIGHT_TF; do
    if [[ -n "${!_seam:-}" ]]; then
      echo "::error::registry-replace-preflight: ${_seam} is set inside GitHub Actions. A seam set on the production path can manufacture a CLEAR verdict. Refusing." >&2
      echo "verdict=REFUSED predicate=SEAM"
      exit 1
    fi
  done
fi
# Reached only outside Actions (the loop above exits otherwise), so this cannot widen the
# production path.
[[ "${REGISTRY_PREFLIGHT_MANUAL:-0}" == "1" ]] && MANUAL=1

abort() { # $1 = predicate, rest = message
  local p="$1"; shift
  # Strip CR/LF and non-printables: `::error::` is LINE-ORIENTED, so an embedded newline in
  # captured vendor stderr terminates the annotation and emits the remainder as raw log lines —
  # including a forged `::add-mask::`. This repo flags that exact class in reusable-release.yml.
  local _m; _m="$(printf '%s' "$*" | tr -d '\n\r' | LC_ALL=C tr -cd '\40-\176')"
  echo "::error::registry-replace-preflight: ${p} ABORT — ${_m}" >&2
  echo "verdict=REFUSED predicate=${p}"
  exit 1
}

# ── The boot-image asset the rendered user_data will fetch (#8714 5.3b-iii) ─────────────────
# Tag, asset name and version come from the mirror builder's `names` mode, the one bash
# derivation the publish workflow also uses (zot-image-oci-archive.sh); T and the repo are literals
# in zot-registry.tf's zot-mirror block. zot-image-fetch.test.sh pins the rendered ZOT_ASSET_URL
# (terraform's own derivation) equal to the url printed here. Sets MIRROR_* or returns 1.
mirror_asset() {
  local names
  MIRROR_ERR=""
  [[ -r "$TF_FILE" ]] || { MIRROR_ERR="cannot read $TF_FILE"; return 1; }
  names="$(ZOT_REGISTRY_TF="$TF_FILE" bash "${ROOT}/apps/web-platform/infra/zot-image-oci-archive.sh" names 2>&1)" \
    || { MIRROR_ERR="zot-image-oci-archive.sh names failed: $(printf '%s' "$names" | tail -1)"; return 1; }
  MIRROR_TAG="$(printf '%s\n' "$names" | sed -n 's/^TAG=//p')"
  MIRROR_ASSET="$(printf '%s\n' "$names" | sed -n 's/^ASSET=//p')"
  MIRROR_T="$(grep -E '^[[:space:]]*zot_mirror_asset_sha256_amd64[[:space:]]*=[[:space:]]*"[0-9a-f]{64}"[[:space:]]*$' "$TF_FILE" | grep -oE '[0-9a-f]{64}' || true)"
  MIRROR_REPO="$(grep -E '^[[:space:]]*zot_mirror_repo[[:space:]]*=[[:space:]]*"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+"[[:space:]]*$' "$TF_FILE" | sed -E 's/^[^"]*"([^"]+)".*$/\1/' || true)"
  [[ "$(printf '%s' "$MIRROR_T" | grep -c . || true)" == 1 ]] || { MIRROR_ERR="expected exactly one zot_mirror_asset_sha256_amd64 = \"<64 hex>\" in $TF_FILE"; return 1; }
  [[ "$(printf '%s' "$MIRROR_REPO" | grep -c . || true)" == 1 ]] || { MIRROR_ERR="expected exactly one zot_mirror_repo = \"<owner>/<repo>\" in $TF_FILE"; return 1; }
  [[ "$MIRROR_TAG" =~ ^zot-image-v[0-9]+\.[0-9]+\.[0-9]+-[0-9a-f]{12}$ && "$MIRROR_ASSET" =~ ^zot-linux-amd64-v[0-9]+\.[0-9]+\.[0-9]+\.oci\.tar$ ]] \
    || { MIRROR_ERR="the builder printed an unexpected tag/asset: [$MIRROR_TAG] [$MIRROR_ASSET]"; return 1; }
  MIRROR_URL="https://github.com/${MIRROR_REPO}/releases/download/${MIRROR_TAG}/${MIRROR_ASSET}"
}

if [[ "$PRINT_ASSET" == "1" ]]; then
  mirror_asset || { echo "registry-replace-preflight: --print-asset: ${MIRROR_ERR}" >&2; exit 2; }
  printf 'repo=%s\ntag=%s\nasset=%s\nsha256=%s\nurl=%s\n' "$MIRROR_REPO" "$MIRROR_TAG" "$MIRROR_ASSET" "$MIRROR_T" "$MIRROR_URL"
  exit 0
fi

# ── P0 — the read itself must be trustworthy, or nothing below means anything. ──────────────
# FAIL-CLOSED. This is Phase 1 defect (b) one layer up: a query that could not run must never be
# read as "no events found". betterstack-query.sh exits 3 when the credentials are absent.
p0_err="$(mktemp)"
trap 'rm -f "$p0_err"' EXIT INT TERM

# ── P6 — GATING, fail-closed. The asset the replaced host will boot from must EXIST and MATCH. ──
# The host fetches zot's image from a release asset and refuses to start zot unless its sha256 is
# the pinned T (cloud-init-registry.yml, zot-image-fetch.sh). A replace onto an asset that is not
# published yet, was deleted, or carries other bytes therefore boots a host that serves NOTHING,
# with no tier beneath it. So the replace is refused unless GitHub's own digest of the published
# asset equals the pinned T. Checked BEFORE P3's drain wait, so a missing asset refuses in seconds.
# Unlike P1/P3 this cannot be tripped by the condition a replace cures: it reads GitHub, not zot.
# NOT skipped on the manual arm: a manual re-fire onto a missing asset darks the host the same way.
# A published release is immutable here (repository setting), and /releases/tags/ never returns a
# draft, so an `uploaded` asset under a published tag is the exact object the host will download.
p6_check() {
  mirror_asset || abort P6 "cannot derive the boot-image asset from zot-registry.tf: ${MIRROR_ERR}. Refusing to replace the host onto an asset it cannot name."
  p6_json="$("$RUNS_CMD" api "repos/${MIRROR_REPO}/releases/tags/${MIRROR_TAG}" 2>"$p0_err")"; p6_rc=$?
  if (( p6_rc != 0 )); then
    if grep -q 'HTTP 404' "$p0_err"; then
      abort P6 "release ${MIRROR_TAG} is not published in ${MIRROR_REPO}, so ${MIRROR_ASSET} does not exist and the replaced host could not start zot. A NEW pin: publish it first with gh workflow run zot-image-mirror.yml --ref <branch> (zot-image.provenance.md, bump procedure). A release that WAS published and is now gone cannot be re-created under this tag (immutable releases): revert the pin (runbooks/registry-host-replace-dispatch.md, zot boot image)."
    fi
    abort P6 "could not read release ${MIRROR_TAG} (gh exited ${p6_rc}): $(head -c 300 "$p0_err"). A failed read is not a present asset."
  fi
  p6_digests="$(printf '%s' "$p6_json" | jq -r --arg a "$MIRROR_ASSET" '[.assets[]? | select(.name == $a and .state == "uploaded") | .digest] | if length == 1 then .[0] // "" else "count=\(length)" end' 2>/dev/null)" \
    || abort P6 "the release ${MIRROR_TAG} response is not parseable JSON. A failed read is not a present asset."
  case "$p6_digests" in
    "sha256:${MIRROR_T}") : ;;
    "count=0") abort P6 "release ${MIRROR_TAG} is published but carries no uploaded ${MIRROR_ASSET}; the replaced host could not start zot." ;;
    count=*) abort P6 "release ${MIRROR_TAG} carries ${p6_digests#count=} uploaded assets named ${MIRROR_ASSET}; refusing an ambiguous boot image." ;;
    *) abort P6 "${MIRROR_ASSET} in ${MIRROR_TAG} has digest '${p6_digests:-none}', but zot-registry.tf pins sha256:${MIRROR_T}. The replaced host would refuse it (sha_mismatch) and never start zot." ;;
  esac
  echo "NOTE: P6 ${MIRROR_ASSET} in ${MIRROR_TAG} is published with the pinned sha256:${MIRROR_T:0:12}..."
}

if [[ "$CHECK_ASSET" == "1" ]]; then
  p6_check
  echo "verdict=CLEAR predicate=P6 boot_asset=${MIRROR_TAG}/${MIRROR_ASSET}"
  exit 0
fi

probe() { # $1 = --grep value; prints rows, sets PROBE_RC
  local marker="$1"
  PROBE_OUT="$("$QUERY_CMD" --since "$WINDOW" --grep "$marker" --limit 200 2>"$p0_err")"
  PROBE_RC=$?
}

probe 'registry=local-cache'
if (( PROBE_RC != 0 )); then
  if [[ "$PROBE_RC" == "3" ]]; then
    abort P0 "betterstack-query.sh exited 3 — BETTERSTACK_QUERY_{HOST,USERNAME,PASSWORD} unset or EMPTY. A failed read is not a clean reading, so this refuses rather than dispatching a production host replace on an unmeasured pull path."
  fi
  abort P0 "betterstack-query.sh exited ${PROBE_RC}: $(head -c 300 "$p0_err"). Not evidence about the pull path."
fi

# ── P1 — GATING. The #6400 hazard, stated in the mechanism that actually detects it. ─────────
# `_try_local_cache_reload` (apps/web-platform/infra/ci-deploy.sh) fires when the pull path has
# already failed. CORRECTED (#7555 review): the earlier wording said "ONLY when BOTH registries
# have already failed", which is false at one of its two call sites — the ZOT_ACTIVE==0 branch is
# reached when zot is dark and never attempted, i.e. GHCR alone failed. So a hit does not entail
# "serving off the last tier"; it can mean zot was not configured this deploy. The direction is
# fail-closed (over-refusal), so this costs availability of the fix rather than safety, but the
# sentence was the entire justification for P1 being GATING and it did not hold as written. This is #6400 exactly: a degraded fallback is
# what turned a registry outage into a total deploy outage.
# P1 IS SKIPPED ON THE MANUAL RE-FIRE ARM (#7555 review). During a replace outage deploys fall
# back to local-cache, so P1 would abort for 24h — and the documented rollback for a failed or
# dark replace IS "re-fire the dispatcher". That is verbatim the anti-pattern this file's own
# header rejects for D10's A4: it would block the recovery on the condition the recovery cures.
# The `reason` input required by workflow_dispatch is the human judgement P1 stands in for.
# Counts over the RAW row. betterstack-query.sh's own header records the stronger rule (#6475):
# field-isolate from the decoded object, or a job that merely PRINTED a marker name counts. The
# marker survives double-encoding so this works today, but a row QUOTING the literal (an error
# tail spliced into a log line) would refuse the replace. Fail-closed, and noted rather than
# silently relied on.
lc_hits="$(printf '%s\n' "$PROBE_OUT" | { grep -c 'registry=local-cache' || true; })"
if [[ "$MANUAL" == "1" && "${lc_hits:-0}" -gt 0 ]]; then
  echo "NOTE: P1 observed ${lc_hits} local-cache event(s) but this is a MANUAL re-fire, which is the documented recovery path for a failed or dark replace. Not gating."
elif [[ "${lc_hits:-0}" -gt 0 ]]; then
  abort P1 "${lc_hits} local-cache pull event(s) in the last ${WINDOW}. The fleet is already falling back to its LAST tier, so replacing the registry host now would remove the only remaining pull source. Resolve the pull path first, then re-dispatch."
fi

# ── P2 — ADVISORY ONLY. THIS MUST NEVER BECOME A GATE. ─────────────────────────────────────
# `registry=ghcr-fallback` is emitted only INSIDE the success branch of a GHCR pull
# (the GHCR fallback leg in ci-deploy.sh, DELETED by #8036 1c on 2026-09-23 — the surviving
# helper is `_pull_with_transient_retry`, which is registry-neutral and serves zot). Per #7071
# the host->GHCR read PAT is
# revoked (401) and the minter is disabled (403 DENIED), so that branch CANNOT succeed and the
# event CANNOT fire. A gate keyed on this operand reads CLEAN whether the fleet is healthy or the
# fallback is destroyed — it is a dark operand, which is the exact defect class the D10 rewrite
# existed to remove. ZERO HERE IS NOT EVIDENCE OF ANYTHING. Reported for the record only.
probe 'registry=ghcr-fallback'
if (( PROBE_RC == 0 )); then
  gf_hits="$(printf '%s\n' "$PROBE_OUT" | { grep -c 'registry=ghcr-fallback' || true; })"
else
  gf_hits="unreadable"
fi

p6_check

# ── P3 — GATING. Do not replace the host out from under an in-flight push. ──────────────────
# Replacing mid-push strands a partially-uploaded manifest on the PRESERVED volume. Directly
# on-point for #7555, whose motivating failure mode is large-layer pushes.
# EVERY WORKFLOW THAT CRANE-COPIES INTO ZOT, not just the web release (#7555 review): the hazard
# is "a replace mid-push strands a partial manifest on the preserved volume", and three workflows
# can be pushing. Derived rather than remembered:
#   grep -rln 'crane copy' .github/workflows/
ZOT_WRITER_WORKFLOWS="${REGISTRY_PREFLIGHT_ZOT_WRITERS:-web-platform-release.yml build-inngest-config-bundle.yml build-inngest-bootstrap-image.yml}"
# DELIBERATELY UNFILTERED BY EVENT, and that is a decision, not an oversight (#5806,
# ADR-217). web-platform-release.yml now produces TWO runs per merge: a push-arm run
# that crane-copies into zot (the `release` job) and a workflow_run-arm run carrying
# the deploy chain, which does NOT crane-copy. Counting only the push arm would be
# the narrower reading of P3's stated hazard — but the deploy arm PULLS from this
# very registry (ci-deploy.sh's zot pull path, ADR-096), so replacing the host under
# an in-flight deploy is its own hazard. Both arms are therefore counted on purpose.
# The cost is a longer drain: the deploy arm's ceiling is 90 minutes against a
# WAIT_SECS of 2100, so a co-firing deploy will more often reach the refusal below.
# Do not "fix" that by adding --event push without first re-reading this paragraph.
# `queued` COUNTS. Merging fires the release and this dispatcher on the SAME push, so at preflight
# time the release is very likely queued, not in_progress — and `--status` takes one value, so the
# old single-status filter reported 0 for exactly the case P3 exists to catch.
# Reuses $p0_err rather than a second mktemp: the EXIT trap covers only $p0_err, so a separate
# temp file here leaked one file per invocation.
p3_err="$p0_err"
in_progress=0
runs_rc=0
for _wf in $ZOT_WRITER_WORKFLOWS; do
  _json="$("$RUNS_CMD" run list --workflow="$_wf" --limit 30 --json status 2>>"$p3_err")" || { runs_rc=$?; break; }
  _n="$(printf '%s' "$_json" | { grep -oE '"status":"(queued|in_progress|waiting|requested|pending|action_required)"' || true; } | grep -c . || true)"
  in_progress=$(( in_progress + _n ))
done
if (( runs_rc != 0 )); then
  abort P3 "could not list in-flight runs for the zot-writing workflows (gh exited ${runs_rc}): $(tail -c 300 "$p3_err"). Refusing rather than replacing the registry host with an unknown number of pushes in flight."
fi
# P3 WAITS BEFORE IT REFUSES. Refusing outright made the MODAL case operator-driven: merging a
# user_data change fires the release AND this dispatcher on the same push, so a queued release is
# the expected state, not the exception. That turned every ordinary delivery into "refuse → file
# a comment → a human types `gh workflow run`", i.e. the operator step this whole workflow exists
# to remove (hr-never-label-any-step-as-manual-without).
#
# The hazard is a replace *mid-push*, not a replace six minutes after one. So poll until the
# writers drain and refuse only if they do not.
# 480 -> 2100 (35 min). MEASURED, not guessed: the first real refusal (run 31976455167,
# 2026-08-16) waited the full 480s and refused anyway, because web-platform-release takes ~31
# minutes end to end (run 31974987386: created 21:57:21Z, concluded 22:28:23Z = 31m02s) and the
# release fires on the SAME merge as this dispatcher. A budget shorter than a release can never
# clear the modal case it exists for — it only converts an immediate refusal into a delayed one.
#
# 2100 is NOT a ceiling on release duration, and the comment should not imply one. Over the last
# 60 push-triggered releases: mean 1630s, max 5538s, and 18.3% exceeded 2100s. So this clears
# roughly 82% of co-firing releases; the rest still refuse, now after 35 minutes instead of 8.
# Raising it further trades runner-hold and API budget for that tail — the durable fix is to
# serialise this dispatcher against the release rather than to poll for it.
#
# The job's own `timeout-minutes` must exceed this or the wait is truncated by a cancellation,
# which is worse than a refusal because a cancelled job does not satisfy `failure()` and files
# no artifact. Raised to 70 in registry-host-replace-dispatch.yml alongside this — 70, not 45,
# because the apply poll adds a further 1500s on the same path.
WAIT_SECS="${REGISTRY_PREFLIGHT_WAIT_SECS:-2100}"
# 20 -> 60. The 480 -> 2100 raise multiplied this loop's API cost by 4.24x: at a 20s poll it is
# 105 iterations x 3 workflows x 2 GETs = 636 requests, and the job's total (with the apply poll)
# measured 988 against the 1,000/hour per-repo GITHUB_TOKEN ceiling — which `web-platform-release`
# is spending from at the same time, because it co-fires on this very push. Exhausting it makes
# `gh` return 403, which this loop's error arm reports as `verdict=REFUSED predicate=P3`: a rate
# limit recorded as a delivery refusal, with the refusal comment itself failing on the same
# exhausted token. 60s costs at most 40s of extra drain latency on a 2100s budget (1.9%) and cuts
# the loop to 216 requests.
POLL_SECS="${REGISTRY_PREFLIGHT_POLL_SECS:-60}"
# CHARGE ELAPSED, NOT ACCUMULATED SLEEP. Every iteration also makes one `gh run list` per
# zot-writing workflow, and those round-trips are wall clock the old `waited + POLL_SECS` never
# charged. At 105 iterations x 3 workflows that is 315 unbilled round-trips, so the loop's real
# duration was 2100 + 315*T_gh — minutes of drift that grows exactly when the API is slow, i.e.
# during the incidents this workflow fires for. The job's `timeout-minutes` is derived from
# WAIT_SECS, so a declared budget that is not the real ceiling makes that derivation unsound.
_p3_started_at=$SECONDS
waited=0
while [[ "${in_progress:-0}" -gt 0 && "$waited" -lt "$WAIT_SECS" ]]; do
  echo "NOTE: P3 sees ${in_progress} in-flight zot-writing run(s); waiting for the push to drain (${waited}s/${WAIT_SECS}s)."
  sleep "$POLL_SECS"
  waited=$(( SECONDS - _p3_started_at ))
  in_progress=0
  for _wf in $ZOT_WRITER_WORKFLOWS; do
    _json="$("$RUNS_CMD" run list --workflow="$_wf" --limit 30 --json status 2>>"$p3_err")" || { runs_rc=$?; break; }
    _n="$(printf '%s' "$_json" | { grep -oE '"status":"(queued|in_progress|waiting|requested|pending|action_required)"' || true; } | grep -c . || true)"
    in_progress=$(( in_progress + _n ))
  done
  if (( runs_rc != 0 )); then
    abort P3 "could not re-list in-flight runs while waiting for the push to drain (gh exited ${runs_rc}): $(tail -c 300 "$p3_err"). Refusing rather than replacing the registry host with an unknown number of pushes in flight."
  fi
done
if [[ "${in_progress:-0}" -gt 0 ]]; then
  abort P3 "${in_progress} in-flight run(s) across the zot-writing workflows still queued or running after waiting ${waited}s. A replace mid-push strands a partial manifest on the preserved volume. Re-dispatch once they finish."
fi

# P1 WAS MEASURED BEFORE THE WAIT, AND THE WAIT IS NOW UP TO 35 MINUTES.
#
# P0/P1/P2 all sample the warehouse near the top of this script, before the drain loop. At 480s a
# stale reading was a rounding error. At 2100s the fleet can begin falling back to local-cache
# DURING the wait, and this script would then dispatch on a clean reading taken half an hour
# earlier while printing `local_cache_hits=` as though it were current — the #6400 hazard P1
# exists to catch, reached precisely because the budget was raised. The re-measure therefore
# belongs with the raise, not as a follow-up: this is the one direction in which a longer wait
# makes an unsafe replace MORE likely.
#
# Skipped when the loop never waited (the original reading is still fresh) and on the manual arm,
# which deliberately does not gate on P1 — see the P1 block's own note.
if [[ "${waited:-0}" -gt 0 && "$MANUAL" != "1" ]]; then
  probe 'registry=local-cache'
  if (( PROBE_RC != 0 )); then
    abort P1 "the post-wait re-read of the pull path failed (betterstack-query.sh exited ${PROBE_RC}: $(tail -c 300 "$p0_err")). P1 was last measured ${waited}s ago, and a failed read is not a clean reading."
  fi
  lc_hits="$(printf '%s\n' "$PROBE_OUT" | { grep -c 'registry=local-cache' || true; })"
  if [[ "${lc_hits:-0}" -gt 0 ]]; then
    abort P1 "${lc_hits} local-cache pull event(s) appeared DURING the ${waited}s drain wait. The fleet started falling back to its last tier while this job waited, so the pre-wait CLEAR reading is stale. Resolve the pull path first, then re-dispatch."
  fi
  echo "NOTE: P1 re-read after the ${waited}s drain wait — still 0 local-cache events."
fi

# ── P4 — DELIBERATELY ABSENT: no live zot serving probe. ────────────────────────────────────
# Do not add one. On this transport a bad handshake does not distinguish an edge refusal from an
# origin that is down or restarting — measured in #7242/ADR-166, where CF Access admitted every
# request while zot was crash-looping. It is worse here than for the recut: #7555's MOTIVATING
# SYMPTOM is a degraded zot, so a serving predicate would refuse precisely when the fix is most
# needed. The same reasoning removed D10's A5 (ADR-169 ground 2).

# ── P5 — CAN THE RESULT OF THIS REPLACE BE OBSERVED AT ALL? GATING. ─────────────────────────
# P4's absence is defensible ONLY because something else eventually verifies the host: #7556
# reads zot's own boot `configuration settings` line out of the warehouse. That is the standing
# justification written into this file and into the dispatcher. P5 checks the justification is
# still TRUE at the moment of the replace, instead of assuming it.
#
# The hazard is specific and it is the #6400 escalation. Today a degraded zot still SERVES pulls
# and only fails large-layer PUSHES. A replace that boots dark serves nothing — and with the
# host->GHCR fallback retracted (#7071) there is no tier beneath it. So firing blind trades a
# blocked release for a total deploy outage, and with the container-log channel dark nobody
# learns which one happened until the next deploy fails.
#
# THIS DOES NOT VIOLATE ADR-169's INDEPENDENCE CRITERION. The criterion forbids depending on the
# component whose failure motivates the destroy — here, zot's HTTP deadlines. The log channel is
# not that component, and P5 reads no pull-path health: it asks only "will I be able to see what
# I did". Unlike P1 and P3 (both of which DO violate it — see the amendment), P5 cannot be tripped
# by the condition the replace cures.
#
# TWO ARMS, because an empty query is not evidence of a dark channel — that mistake was made
# once already this cycle and cost a false all-clear until a 72h positive control refuted it.
# The control marker rides a DIFFERENT transport than the container-log channel, so:
#   control empty  -> the READ is broken; refuse, same class as P0.
#   control alive + container-log empty -> the CHANNEL is dark; refuse, this is #7569.
#   both alive -> the replace's outcome will be observable; proceed.
probe "$P5_CONTROL_MARKER"
p5_control_rc=$PROBE_RC
p5_control_hits="$(printf '%s\n' "$PROBE_OUT" | { grep -c '[^[:space:]]' || true; })"
if (( p5_control_rc != 0 )); then
  abort P5 "the control query for ${P5_CONTROL_MARKER} failed (rc=${p5_control_rc}): $(head -c 200 "$p0_err"). A read that did not run cannot establish that this replace would be observable."
fi
probe "$P5_CHANNEL_MARKER"
p5_channel_rc=$PROBE_RC
p5_channel_hits="$(printf '%s\n' "$PROBE_OUT" | { grep -c '[^[:space:]]' || true; })"
if (( p5_channel_rc != 0 )); then
  abort P5 "the container-log query failed (rc=${p5_channel_rc}): $(head -c 200 "$p0_err"). Refusing rather than reading a failed query as a live channel."
fi
if [[ "${p5_control_hits:-0}" -eq 0 ]]; then
  abort P5 "no ${P5_CONTROL_MARKER} rows in the last ${WINDOW} — the warehouse read itself is not returning host telemetry, so a dark boot would be indistinguishable from a healthy one. Fix the read before replacing the sole pull path."
fi
if [[ "${p5_channel_hits:-0}" -eq 0 ]]; then
  abort P5 "the control marker is delivering (${p5_control_hits} rows) but the registry CONTAINER-LOG channel returned zero rows in ${WINDOW} — this is #7569. Replacing the host now would put the fleet's sole pull path (no SSH, no GHCR fallback since #7071) behind a channel that cannot report whether it came back. Resolve #7569, then re-dispatch; delivery is deferred, not cancelled."
fi

# Print the OBSERVED counts, never literals. They are zero on the ordinary path only because
# every non-zero reading aborts above — but P1 no longer always aborts (`--manual` downgrades it
# to a NOTE), so a literal `local_cache_hits=0` would report a clean reading for a run that
# actually observed hits and proceeded anyway. The verdict line is the durable artifact; it must
# describe what was measured, not what the happy path implies.
echo "verdict=CLEAR local_cache_hits=${lc_hits:-0} ghcr_fallback_hits=${gf_hits} in_progress_releases=${in_progress:-0} obs_control_hits=${p5_control_hits:-0} obs_channel_hits=${p5_channel_hits:-0} boot_asset=${MIRROR_TAG}/${MIRROR_ASSET} manual=${MANUAL} window=${WINDOW}"
echo "NOTE: ghcr_fallback_hits is ADVISORY. Its emitter is unreachable since #7071, so a zero says nothing about fallback health."
exit 0
