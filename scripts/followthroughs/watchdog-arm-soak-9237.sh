#!/usr/bin/env bash
# watchdog-arm-soak-9237.sh — 24h detect-only soak probe for #9237 (#9168).
#
# NOTIFY-ONLY probe — this tracker must never be closed by a script. The arm
# mutation it tracks (`gh variable set WATCHDOG_ARMED --body 1`) needs
# actions-variables write, a scope the sweeper token deliberately lacks; a
# human performs it. So EVERY verdict lands in the sweeper's registered
# TRANSIENT sub-vocabulary (followthrough-convention.md): nothing here exits
# 0 or 1.
#
# What it measures (the spec's soak AC, mirrored as code):
#   1. >=24h elapsed since the watchdog's FIRST completed run (dark launch
#      2026-09-29 ~18:00Z; window = [t0, t0+86400s]).
#   2. Every completed scheduled-supabase-watchdog.yml run in that window has
#      conclusion == success (a failed/timed-out run = dirty soak — a human
#      investigates before arming, same as the spec's "clean" gate).
#   3. ZERO `watchdog:restart` sentinel comments across every
#      `supabase-auto-restart`-labelled issue (bot-authored only, same filter
#      the ledger read uses). A sentinel while supposedly detect-only means
#      the dark-launch gate failed — the worst possible find.
#   4. Best-effort `actions/variables/WATCHDOG_ARMED` read — expected to 403
#      under the sweeper's scopes; reported as context, never gated on.
#
# Exit semantics:
#   2 = NOT YET           (soak window incomplete; nothing dirty so far)
#   3 = CANNOT ESTABLISH  (gh/jq missing, GH_TOKEN unset, any API read fails —
#                          an unreadable ledger or run list must never
#                          masquerade as a clean window)
#   5 = ACTION REQUIRED   (window complete: clean → run the arm command; dirty
#                          → investigate first; already armed → verify + close
#                          #9237 manually)
#  78 = xtrace refusal while GH_TOKEN is set (#7797)
#
# Credential posture: secrets=GH_TOKEN (the sweeper forwards
# secrets.GITHUB_TOKEN with contents:read, issues:write, actions:read). Probe
# reads: workflow runs (actions:read), labelled issues + comments (issues
# scope). The actions-variables read is attempted once, non-fatally.
#
# RETIREMENT: when #9237 closes, delete this file, its .test.sh, and its
# run_suite line in scripts/test-all.sh.
set -uo pipefail

# XTRACE REFUSAL (#7797): GH_TOKEN-bound probes refuse `bash -x` — tracing
# echoes the expanded credential into the transcript before first use.
case "$-" in
  *x*)
    if [ -n "${GH_TOKEN:+x}" ]; then
      printf '[FATAL] refusing to trace with a live credential set (see #7797)\n' >&2
      exit 78
    fi
    ;;
esac

GH_REPO="${GH_REPO:-jikig-ai/soleur}"
WORKFLOW="scheduled-supabase-watchdog.yml"
SOAK_SECONDS=86400
# ~83% of the 288 expected 5-min ticks — absorbs normal scheduler jitter while
# still catching a stalled/broken workflow (a sparse window is human-review,
# not auto-clean).
MIN_RUNS=240

[ -n "${GH_TOKEN:-}" ] || { echo "CANNOT ESTABLISH: GH_TOKEN not set (secrets= clause)" >&2; exit 3; }
command -v gh  >/dev/null || { echo "CANNOT ESTABLISH: gh not on PATH" >&2; exit 3; }
command -v jq  >/dev/null || { echo "CANNOT ESTABLISH: jq not on PATH" >&2; exit 3; }

iso_epoch() {
  date -u -d "$1" +%s 2>/dev/null && return 0
  date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$1" +%s 2>/dev/null
}

# ── 1. Completed runs of the watchdog workflow ────────────────────────────────
# --paginate pages the endpoint; --jq filters EACH page and emits one value per
# run (gh forbids --slurp with --jq), so `jq -s` collects the emitted stream
# into the flat array downstream expects.
RUNS_RC=0
RUNS_RAW="$(gh api "repos/${GH_REPO}/actions/workflows/${WORKFLOW}/runs?status=completed&per_page=100" \
  --paginate \
  --jq '.workflow_runs[] | {created_at, conclusion}' 2>/dev/null)" || RUNS_RC=$?
RUNS_JSON="$(jq -s '.' <<<"$RUNS_RAW" 2>/dev/null || true)"
if [[ "$RUNS_RC" != "0" ]] || ! jq -e 'type == "array"' >/dev/null 2>&1 <<<"$RUNS_JSON"; then
  echo "CANNOT ESTABLISH: workflow-runs read failed (rc=${RUNS_RC})" >&2; exit 3
fi
N_RUNS=$(jq 'length' <<<"$RUNS_JSON")
if [[ "$N_RUNS" == "0" ]]; then
  echo "CANNOT ESTABLISH: zero completed ${WORKFLOW} runs — is the watchdog even scheduled?" >&2; exit 3
fi

T0_ISO=$(jq -r '[.[].created_at] | min' <<<"$RUNS_JSON")
T0=$(iso_epoch "$T0_ISO" || true)
NOW=$(date -u +%s)
if [[ -z "${T0:-}" ]]; then
  echo "CANNOT ESTABLISH: unparseable oldest run timestamp '$T0_ISO'" >&2; exit 3
fi
WINDOW_END=$(( T0 + SOAK_SECONDS ))

# Soak verdict only counts runs inside [t0, t0+24h]; later runs are context.
WIN=$(jq --arg t0 "$T0_ISO" --argjson end "$WINDOW_END" '
  . as $r
  | ($r | map(select(.created_at <= ($end | todate)))) as $w
  | {total: ($w | length),
     dirty: ($w | map(select(.conclusion | test("^(failure|timed_out|action_required|startup_failure|stale)$"))) | length),
     cancelled: ($w | map(select(.conclusion == "cancelled")) | length),
     post: (($r | length) - ($w | length))}' <<<"$RUNS_JSON")
WIN_TOTAL=$(jq -r '.total' <<<"$WIN")
WIN_DIRTY=$(jq -r '.dirty' <<<"$WIN")
WIN_CANCELLED=$(jq -r '.cancelled' <<<"$WIN")

# ── 2. Restart sentinels on the audit ledger ──────────────────────────────────
ISSUES_RC=0
ISSUES_JSON="$(gh issue list --repo "$GH_REPO" --state all --limit 100 \
  --label supabase-auto-restart --json number 2>/dev/null)" || ISSUES_RC=$?
if [[ "$ISSUES_RC" != "0" ]]; then
  echo "CANNOT ESTABLISH: audit-issue list read failed" >&2; exit 3
fi
SENTINELS=0
for N in $(jq -r '.[].number' <<<"$ISSUES_JSON"); do
  C_RC=0
  C_RAW="$(gh api "repos/${GH_REPO}/issues/${N}/comments?per_page=100" --paginate \
    --jq '.[] | select(.user.login == "github-actions[bot]") | select(.body | test("watchdog:restart")) | .id' \
    2>/dev/null)" || C_RC=$?
  CNT="$(jq -s 'length' <<<"$C_RAW" 2>/dev/null || true)"
  if [[ "$C_RC" != "0" ]] || [[ ! "$CNT" =~ ^[0-9]+$ ]]; then
    echo "CANNOT ESTABLISH: comment read failed on audit issue #${N} — ledger unreadable" >&2; exit 3
  fi
  SENTINELS=$(( SENTINELS + CNT ))
done

# ── 3. Arm state (best-effort: the sweeper's token usually cannot read repo
#        variables — the value is context, not a gate) ─────────────────────────
ARMED="unreadable"
if V="$(gh api "repos/${GH_REPO}/actions/variables/WATCHDOG_ARMED" --jq '.value' 2>/dev/null)" && [ -n "$V" ]; then
  ARMED="$V"
fi

printf 'soak: window=[%s → %s] now=%s | runs total=%s window=%s dirty=%s cancelled=%s post-window=%s | sentinels=%s | armed=%s\n' \
  "$T0_ISO" "$(date -u -d "@$WINDOW_END" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -r "$WINDOW_END" +%Y-%m-%dT%H:%M:%SZ)" \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$N_RUNS" "$WIN_TOTAL" "$WIN_DIRTY" "$WIN_CANCELLED" \
  "$(jq -r '.post' <<<"$WIN")" "$SENTINELS" "$ARMED"

# ── Verdict ───────────────────────────────────────────────────────────────────
if [[ "$ARMED" == "1" ]]; then
  echo "ACTION REQUIRED: WATCHDOG_ARMED is already '1' — verify a recent watchdog run then close #9237 manually."
  exit 5
fi
if [[ "$NOW" -lt "$WINDOW_END" ]]; then
  echo "NOT YET: soak window incomplete ($(( (WINDOW_END - NOW) / 3600 ))h remaining; ${WIN_TOTAL} clean-window runs, ${WIN_DIRTY} dirty, ${SENTINELS} sentinels)."
  exit 2
fi
if [[ "$SENTINELS" -gt 0 ]]; then
  echo "ACTION REQUIRED: ${SENTINELS} watchdog:restart sentinel(s) found while the watchdog should be detect-only — the dark-launch gate was breached; investigate the audit ledger BEFORE arming."
  exit 5
fi
if [[ "$WIN_DIRTY" -gt 0 ]]; then
  echo "ACTION REQUIRED: ${WIN_DIRTY} non-success run(s) inside the soak window — review the failed runs before arming."
  exit 5
fi
if [[ "$WIN_TOTAL" -lt "$MIN_RUNS" ]]; then
  echo "ACTION REQUIRED: soak window complete but only ${WIN_TOTAL} completed runs (< ${MIN_RUNS} expected) — cadence gap; verify the schedule before arming."
  exit 5
fi
echo "ACTION REQUIRED: soak clean — ${WIN_TOTAL} successful runs across 24h, zero restart sentinels. Arm now: gh variable set WATCHDOG_ARMED --body 1"
exit 5
