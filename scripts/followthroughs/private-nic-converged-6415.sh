#!/usr/bin/env bash
# Follow-through verification: #6415 — the registry host's private NIC is converged AND the
# guard is actually reporting it (ADR-115, PR #6422).
#
# WHY THIS EXISTS. #6415 is an ops-remediation: the code merging does NOT fix production. The
# host only carries the guard after a `registry-host-replace` reprovision, so the PR body says
# "#6415 closes when the replace verifies". Without enrollment that promise rests on human
# memory — which is the exact failure this whole incident is about (#6400 ran 14 days because
# `learnings/2026-07-07-immutable-redeploy.md` Sharp edge 2's "always verify after a -replace"
# was an operator-memory dependency). This script is that verification, mechanized.
#
# Exit semantics (enforced by scripts/sweep-followthroughs.sh):
#   0 = PASS      — a genuine SOLEUR_PRIVATE_NIC emission reports nic_ok=true; sweeper closes #6415
#   1 = FAIL      — the guard is reporting, but the NIC is NOT converged; sweeper comments, stays open
#   * = TRANSIENT — probe fault OR the guard is not deployed yet (the replace has not run);
#                   sweeper retries next sweep. Never closes and never false-FAILs on "not yet".
#
# Required secrets: BETTERSTACK_QUERY_{HOST,USERNAME,PASSWORD} (declared via the directive's
# `secrets=` clause and wired into scheduled-followthrough-sweeper.yml's env: block).
#
# Convention: knowledge-base/engineering/operations/runbooks/followthrough-convention.md

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BQ="${ZOT_BQ_OVERRIDE:-$REPO_ROOT/scripts/betterstack-query.sh}"

if [[ ! -x "$BQ" ]]; then
  echo "TRANSIENT: betterstack-query.sh not found/executable at $BQ" >&2
  exit 2
fi

# 24h window: the guard emits every 5 min, so a live guard yields ~288 rows/day. A window this
# wide tolerates a sweep landing during a reboot or a brief ingest lag.
ROWS="$("$BQ" --since 24h --grep SOLEUR_PRIVATE_NIC --limit 500 2>/dev/null)"; rc=$?
if [[ "$rc" -ne 0 ]]; then
  echo "TRANSIENT: Better Stack query failed (rc=$rc) — probe fault, not a verdict" >&2
  exit 2
fi

# MEMBERSHIP ANCHOR — load-bearing, and NOT optional. `--grep` compiles to an unanchored
# `raw LIKE '%SOLEUR_PRIVATE_NIC%'` over a Logs source EVERY host multiplexes into, so it returns
# any row that merely CONTAINS the string. Verified live 2026-07-15: it returned 3 rows that were
# GitHub webhook payloads of the PR adding this guard (the PR body quotes the marker) — and those
# rows even contain the literal `nic_ok=true`, so an unanchored grep here would FALSE-PASS and
# auto-close #6415 against a host that never emitted. A genuine emission is a direct POST of
# {"message":"SOLEUR_PRIVATE_NIC …"}, so its raw STARTS with that envelope; a Vector-shipped
# journald row's raw starts {"PRIORITY":"6",… and buries the marker in a nested .message.
GENUINE="$(printf '%s\n' "$ROWS" | grep -F '"raw":"{\"message\":\"SOLEUR_PRIVATE_NIC ' || true)"

if [[ -z "$GENUINE" ]]; then
  echo "TRANSIENT: no genuine SOLEUR_PRIVATE_NIC emission in 24h — the guard is not on the host yet." >&2
  echo "           #6415 closes only after the registry-host-replace reprovision delivers it:" >&2
  echo "           gh workflow run apply-web-platform-infra.yml -f apply_target=registry-host-replace -f reason='deliver the #6415 NIC guard'" >&2
  exit 2
fi

# Scope to the newest boot, mirroring the alarm. Strip the free-text zot_last_err tail FIRST so a
# crafted log tail cannot spoof the fields this verdict keys on (the shared trusted-region rule).
TRUSTED="$(printf '%s\n' "$GENUINE" | sort | sed 's/ zot_last_err=.*//')"
NEWEST="$(printf '%s\n' "$TRUSTED" | grep -oE 'boot_id=[0-9a-fA-F-]+' | grep -v 'boot_id=unknown' | tail -1 | cut -d= -f2)"
if [[ -z "$NEWEST" ]]; then
  echo "TRANSIENT: emissions present but no usable boot_id — cannot scope to the newest host" >&2
  exit 2
fi
SCOPED="$(printf '%s\n' "$TRUSTED" | grep -F "boot_id=$NEWEST")"

NIC="$(printf '%s\n' "$SCOPED" | grep -oE 'nic_ok=(true|false)' | tail -1 | cut -d= -f2)"
CONV="$(printf '%s\n' "$SCOPED" | grep -oE 'converged_by=[a-z-]+' | tail -1 | cut -d= -f2)"
STORE="$(printf '%s\n' "$SCOPED" | grep -oE 'zot_store_mounted=(true|false)' | tail -1 | cut -d= -f2)"
RB="$(printf '%s\n' "$SCOPED" | grep -oE 'reboot_count=[0-9]+' | cut -d= -f2 | sort -n | tail -1)"

if [[ "$NIC" == "true" && "$STORE" == "true" ]]; then
  echo "PASS: boot_id=$NEWEST nic_ok=true converged_by=${CONV:-?} zot_store_mounted=true reboot_count=${RB:-0}"
  # converged_by is the empirical H1-vs-H2 verdict the plan asked to be recorded:
  #   already => no race on this boot; reboot => the race is REAL and the guard healed it.
  echo "      converged_by=${CONV:-?} is the empirical H1-vs-H2 verdict — record it in ADR-115."
  exit 0
fi

echo "FAIL: boot_id=$NEWEST nic_ok=${NIC:-?} converged_by=${CONV:-?} zot_store_mounted=${STORE:-?} reboot_count=${RB:-0}" >&2
echo "      The guard IS reporting, so this is a real verdict, not a probe fault." >&2
echo "      Decode: imds_rc!=0 => H1 (metadata service); imds_rc=0 && imds_nets=0 => H2 (attach race);" >&2
echo "      imds_nets>0 && converged_by!=already => the attach landed and the guest never configured it." >&2
echo "      Full context: doppler run -p soleur -c prd_terraform -- bash scripts/zot-restart-loop-alarm.sh" >&2
exit 1
