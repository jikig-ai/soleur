#!/usr/bin/env bash
# Follow-through verification: #8539 — the dedicated inngest host converges a late-attached
# private NIC, AND the helper is actually reporting it (ADR-115 amendment 2026-09-22, PR #8560).
#
# WHY THIS EXISTS. #8539 is an ops-remediation: merging does NOT fix production. The host only
# carries the `.network` fallback and the wait helper after an `inngest-host-replace`, and
# because INNGEST_CUTOVER_FLIP=done every replace additionally needs a human-approved
# `cutover-inngest.yml -f op=resume`. ADR-115's own amendment says the converge claim is
# "adopting" — a mechanism-level argument until a boot emits `by=99-soleur-private-fallback`.
# Without enrollment that promise rests on human memory, which is what #8539 cost 59 minutes of
# scheduler-dark time to learn. This is the twin of private-nic-converged-6415.sh (registry).
#
# Exit semantics (enforced by scripts/sweep-followthroughs.sh):
#   0 = PASS      — a genuine private_nic_ok emission on the newest boot; sweeper closes #8539
#   1 = FAIL      — the helper is reporting and the NIC did NOT converge (timeout); stays open
#   * = TRANSIENT — probe fault, or the helper is not deployed yet (the replace has not run)
#
# Required secrets: BETTERSTACK_QUERY_{HOST,USERNAME,PASSWORD}.
# Convention: knowledge-base/engineering/operations/runbooks/followthrough-convention.md

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BQ="${NIC8539_BQ_OVERRIDE:-$REPO_ROOT/scripts/betterstack-query.sh}"
MARKER='SOLEUR_INNGEST_BOOT_STAGE'

if [[ ! -x "$BQ" ]]; then
  echo "TRANSIENT: betterstack-query.sh not found/executable at $BQ" >&2
  exit 2
fi

# 30d, not 24h: unlike the registry guard's 5-minute cron, this helper runs ONCE per host
# replace. A 24h window would read TRANSIENT forever on a healthy fleet.
ROWS="$("$BQ" --since 30d --grep "$MARKER" --limit 2000 2>/dev/null)"; rc=$?
if [[ "$rc" -ne 0 ]]; then
  echo "TRANSIENT: Better Stack query failed (rc=$rc) — probe fault, not a verdict" >&2
  exit 2
fi

# FIELD ISOLATION, not substring matching. `--grep` compiles to an unanchored
# `raw LIKE '%SOLEUR_INNGEST_BOOT_STAGE%'` over a source every host multiplexes into, so it
# returns any row that merely CONTAINS the string — including a GitHub webhook payload of the
# PR that added the marker. private-nic-converged-6415.sh records that exact false-PASS
# happening live on 2026-07-15, with the offending rows carrying the success token verbatim.
# Decode and select on the DECODED object instead, mirroring inngest-zot-boot-7462.sh.
# `-R` plus `fromjson?` at BOTH levels: without `-R` one malformed line aborts the whole
# invocation and every valid row after it is lost, which would surface as "never emitted".
STAGES="$(printf '%s\n' "$ROWS" \
  | jq -R -r 'fromjson? | .raw? | fromjson?
      | select(.marker == "'"$MARKER"'")
      | select(.stage | startswith("private_nic_"))
      | "\(.dt) \(.stage) \(.detail // "")"' 2>/dev/null | LC_ALL=C sort)"

if [[ -z "$STAGES" ]]; then
  echo "TRANSIENT: no private_nic_* emission in 30d — the helper is not on the host yet." >&2
  echo "           #8539's code merging does not deliver it. It reaches the host only via:" >&2
  echo "             gh workflow run apply-web-platform-infra.yml \\" >&2
  echo "               -f apply_target=inngest-host-replace -f reason='deliver the #8539 NIC converge'" >&2
  echo "           followed by a human-approved: gh workflow run cutover-inngest.yml -f op=resume" >&2
  exit 2
fi

# Newest boot only. Every arm emits exactly one event per boot, so the last row IS the verdict
# for the most recent replace; an older timeout must not outvote a newer success.
NEWEST="$(printf '%s\n' "$STAGES" | tail -1)"
STAGE="$(printf '%s' "$NEWEST" | awk '{print $2}')"
DETAIL="$(printf '%s' "$NEWEST" | cut -d' ' -f3-)"

case "$STAGE" in
  private_nic_ok)
    echo "PASS: newest inngest boot converged its private NIC — $NEWEST"
    # `by=` names WHICH networkd file did it. This is ADR-115's stated promotion criterion:
    # the converge claim stays "adopting" until a boot shows the fallback doing the work.
    case "$DETAIL" in
      *by=99-soleur-private-fallback*)
        echo "      by=99-soleur-private-fallback — the race occurred and the fallback healed it."
        echo "      This is the evidence ADR-115's amendment names; record it there." ;;
      *by=10-netplan-*)
        echo "      by=10-netplan-* — no race on this boot; the fallback stayed inert (also healthy)." ;;
      *) echo "      NOTE: unrecognised by= value; see the runbook's by= table." ;;
    esac
    exit 0 ;;
  private_nic_timeout)
    echo "FAIL: the newest inngest boot did NOT converge its private NIC — $NEWEST" >&2
    echo "      The helper ran and the address never arrived within its bound, so the zot login" >&2
    echo "      that follows it ran against an unconverged NIC. Read links= per the runbook's" >&2
    echo "      table in knowledge-base/engineering/operations/runbooks/inngest-server.md." >&2
    exit 1 ;;
  private_nic_probe_fault)
    echo "TRANSIENT: the helper could not measure (reason= in the detail) — $NEWEST" >&2
    echo "           'could not measure' is not 'did not converge'. No verdict." >&2
    exit 2 ;;
  *)
    echo "TRANSIENT: unrecognised stage '$STAGE' — $NEWEST" >&2
    exit 2 ;;
esac
