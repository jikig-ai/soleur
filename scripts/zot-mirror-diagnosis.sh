#!/usr/bin/env bash
# zot-mirror-diagnosis.sh — pure classifier + message library for the zot-mirror failure
# path (#7242, ADR-166). SOURCED by .github/workflows/reusable-release.yml (the token
# preflight and the degraded-bridge arm) AND by
# .github/actions/cf-tunnel-registry-bridge/action.yml (both ::error:: sites) AND by
# scripts/zot-mirror-diagnosis.test.sh. No network, no side effects.
#
# WHY THIS EXISTS. On 2026-08-03 every Web Platform Release from 17:11 UTC failed at the
# zot bridge, and the error told the operator the cause was a stale
# REGISTRY_PUSH_ACCESS_TOKEN_* — a hypothesis a step in the SAME JOB had disproved six
# minutes earlier ("Registry-push Access service token verified live"). The measured cause
# was a zot crash-loop at ~4 restarts/min, which straddles the tens of seconds a
# `docker login` + three-tag `crane copy` takes; the Access policy was intact and the
# tunnel connector had never dropped. Two prior iterations of this same defect class on
# this same code path (2026-07-15, 2026-07-29) were each fixed by rewriting the sentence,
# and each re-drifted — one of them sent an entire investigation to the wrong network layer.
#
# So the rule this library enforces by construction is: NO FAILURE MESSAGE ON THIS PATH MAY
# NAME A CAUSE THE JOB DID NOT MEASURE. The message text lives in exactly ONE place, and it
# branches on a verdict derived from the detector's measured JSON counts.
#
# Verdicts (the closed vocabulary zot_mirror_verdict echoes):
#   live          the detector probed the credential and Cloudflare Access ADMITTED it.
#                 Rotation is ruled OUT by measurement. This is where a crash-looping or
#                 otherwise unreachable origin lands.
#   stale         a MEASURED dead count (json .dead > 0). Rotation genuinely is the remedy,
#                 and this is the only arm on which that is true.
#   unverifiable  a measured "could not tell" (json .unverifiable > 0). NOT an accusation:
#                 the detector's own cause vocabulary all carries "Do NOT rotate".
#   unmeasured    nothing was checked, or the verdict file could not be read/parsed, or the
#                 exit code and the counts contradict each other. Ranks nothing.
#
# LOAD-BEARING: this file must NOT `set -euo pipefail`. It is sourced into steps already
# running under `bash --noprofile --norc -eo pipefail {0}`, so a `set -e` here would leak
# into the caller and change the failure semantics of the very step it is diagnosing.

# Derive the verdict. $1 = the detector's exit code, $2 = path to its --json-file output.
#
# rc ALONE IS NOT ENOUGH, and that is the entire point. check-cloudflare-token-drift.sh
# exits 1 for `DEAD_N > 0 || UNVERIFIABLE_N > 0` — so mapping rc=1 to "stale" prints
# "the token is STALE, rotate it" about a token nothing measured. The counts come from the
# JSON; rc only distinguishes "ran" from "could not run at all" (exit 2).
zot_mirror_verdict() {
  local rc="$1" json_file="$2"
  local dead unver

  # rc outside {0,1} is the detector's "nothing was checked at all". An unwritable
  # --json-file is itself one of those conditions, so this arm and the unreadable-file arm
  # below are two routes to the same honest answer.
  if [[ "$rc" != "0" && "$rc" != "1" ]]; then
    echo "unmeasured"
    return 0
  fi

  # A missing key reads as the -1 sentinel, never as 0 — treating "the file did not report
  # this" as "the count was zero" would manufacture `live` out of a file that measured
  # nothing. `|| true` keeps a python failure from aborting a sourced caller under -e.
  read -r dead unver < <(python3 -c '
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    if not isinstance(d, dict):
        raise ValueError("not an object")
    print(int(d["dead"]), int(d["unverifiable"]))
except Exception:
    print(-1, -1)
' "$json_file" 2>/dev/null || printf '%s\n' "-1 -1")

  if [[ "$dead" == "-1" || "$unver" == "-1" ]]; then
    echo "unmeasured"
  elif [[ "$dead" -gt 0 ]]; then
    # A measured dead count outranks a measured ungradeable one: the accusation has evidence.
    echo "stale"
  elif [[ "$unver" -gt 0 ]]; then
    echo "unverifiable"
  elif [[ "$rc" == "1" ]]; then
    # rc=1 asserts "dead OR unverifiable", so rc=1 with both counts at zero means the exit
    # code and the counts disagree. Resolving that to `live` would certify a credential the
    # detector explicitly refused to certify — the worst available direction. No claim.
    echo "unmeasured"
  else
    echo "live"
  fi
  return 0
}

# Echo the detector's own cause token for the first unverifiable row, or `unknown`.
# $1 = path to the --json-file output.
#
# The detector emits a CLOSED cause vocabulary (gate-indeterminate, stamped-non-refusal,
# unexpected-status, refused-unstamped) precisely so a consumer never has to pattern-match
# English prose. Each carries a different investigation and all four carry "Do NOT rotate".
zot_mirror_unverifiable_cause() {
  local json_file="$1" cause
  cause=$(python3 -c '
import json, sys
try:
    rows = json.load(open(sys.argv[1])).get("unverifiable_keys") or []
    c = (rows[0].get("cause") or "").strip() if rows else ""
    print(c if c else "unknown")
except Exception:
    print("unknown")
' "$json_file" 2>/dev/null || printf 'unknown\n')
  printf '%s\n' "${cause:-unknown}"
  return 0
}

# Render the operator-facing diagnosis for a verdict.
# $1 = verdict, $2 = checked_at (the preflight's UTC stamp), $3 = restart summary
# (the in-job SOLEUR_ZOT_DISK zot_restarts series, or an explicit "could not query"
# sentence — NEVER a claim derived from a failed query), $4 = unverifiable cause.
#
# Emits multi-line text on stdout. Callers append their own $SAFE_TO_RERUN suffix; this
# function does not repeat it.
zot_mirror_diagnosis() {
  local verdict="${1:-}" checked_at="${2:-}" restarts="${3:-}" cause="${4:-unknown}"
  local when="${checked_at:-an earlier step in this job}"

  case "$verdict" in
    live)
      cat <<EOF
MEASURED LIVE — the registry-push credential is NOT the cause, and this job proved it.
The Preflight step in this run, at ${when}, presented these exact credentials to
registry.soleur.ai and Cloudflare Access ADMITTED them. Rotating the token will not help.
(That claim rests on one mapping: access_hostname_for() in
scripts/check-cloudflare-token-drift.sh maps REGISTRY_PUSH_ACCESS_TOKEN to registry.* —
if that mapping is ever dropped, this arm is no longer entitled to the claim.)

Scope: this settles the Cloudflare Access credential ONLY. It says nothing about
ZOT_PUSH_USER/ZOT_PUSH_TOKEN, which is a separate docker-login failure mode.

Registry-host health, read from Better Stack during this run:
  ${restarts:-(no restart series was requested on this path)}

A climbing zot_restarts count is the origin flapping: a docker login plus a three-tag
crane copy takes tens of seconds, so it straddles a restart and the tunnel's origin dial
fails mid-push. That surfaces as 'websocket: bad handshake' from cloudflared and
'connection reset by peer' from the docker client — with Access having admitted the
request. Do not read a bad handshake as an edge refusal.

Recovery: re-run this job once the restart count has PLATEAUED, not on a timer — a re-run
into a live crash-loop fails the same way. scripts/followthroughs/zot-restart-plateau-6288.sh
is the plateau prober (0 = plateau holds, 1 = still climbing, 2 = could not tell).
EOF
      ;;
    stale)
      cat <<EOF
MEASURED DEAD — the registry-push credential was probed in this job and Cloudflare
rejected it. A rotation did not propagate, and this is the one verdict on which rotating
is the remedy.

Terraform will NOT fix this: the doppler_secret resources carry
lifecycle.ignore_changes = [value], so 'terraform apply' reports "No changes" while the
stale value keeps being served.

List the affected configs, then set the live value in EVERY ONE of them:
  doppler run -p soleur -c prd_terraform -- bash scripts/check-cloudflare-token-drift.sh

Doppler branch configs do NOT inherit values from the 'prd' root config — measured
2026-08-02, one token was carried independently by seven configs. Setting root alone
leaves every other stale copy in place and looks completely successful, which is the
silent-and-delayed failure this detector exists to catch.

Once the fan-out is repaired, re-run this job; the zot mirror will retry the push.
EOF
      ;;
    unverifiable)
      cat <<EOF
NOT GRADED — the registry-push credential could not be measured either way, so nothing
here accuses it. The detector reported: ${cause}

Do NOT rotate on this verdict. Every cause in that vocabulary describes the edge or the
probe, not the credential:
  gate-indeterminate   the host answered an uncredentialed request with no Access stamp,
                       which characterises neither a gate nor its absence (a tunnel
                       outage looks like this). Re-run.
  stamped-non-refusal  an Access stamp on something that is not a refusal — not evidence
                       the credential was rejected. Investigate the Access application.
  unexpected-status    no stamp and no success; LIVE requires positive evidence of
                       admission, and this is not evidence of staleness either.
  refused-unstamped    something other than Access is refusing (WAF, IP rule, bot-fight),
                       so the credential could not be graded.

The zot push failed while the credential was ungraded. Re-run to re-probe; if the same
cause repeats, investigate the edge for registry.soleur.ai before touching any secret.
EOF
      ;;
    unmeasured)
      cat <<EOF
NOTHING WAS MEASURED about the registry-push credential in this run — the preflight did
not run, could not run, or its verdict file could not be read. This message therefore
names no cause.

Candidates, in no particular order (this arm deliberately does not rank them):
  - the origin: zot may be down or restarting. Read SOLEUR_ZOT_DISK zot_restarts in
    Better Stack (source registry_disk_prd).
  - the credential: run the detector yourself —
    doppler run -p soleur -c prd_terraform -- bash scripts/check-cloudflare-token-drift.sh
  - the preflight's own preconditions: the Doppler CLI, or a DOPPLER_TOKEN_PRD scoped to
    the 'prd' root config, may be missing from this job.

Base case: if the settling probe is ITSELF unavailable, do not loop on it — escalate to
the zot crash-loop tracking issue rather than re-running into an unknown state.
EOF
      ;;
    *)
      echo "unrecognised verdict '${verdict}' — zot_mirror_diagnosis was called with a value outside {live,stale,unverifiable,unmeasured}. This is a bug in the caller, not a diagnosis of the zot mirror." >&2
      return 1
      ;;
  esac
  return 0
}
