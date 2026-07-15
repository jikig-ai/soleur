#!/usr/bin/env bash
# Post-merge sequence for #6425 PR A — de-pool web-2 from the shared Cloudflare Tunnel,
# verify the single-connector invariant (ADR-114 I1), and resolve the issue.
#
# A SCRIPT, not an operator checklist (hr-ship-message-no-operator-checklist +
# hr-multi-step-post-merge-bootstrap-script). Idempotent: re-running after a completed
# de-pool is a no-op that just re-verifies.
#
# WHY THIS IS SHORT — the two-PR split is what made it short.
# An earlier single-PR shape carried two compensations that no longer exist here, because
# PR A is provably HASH-NEUTRAL (it touches no member of local.host_script_files; the
# host-identity scripts moved to PR B):
#
#   * No release-digest wait. `web-2-recreate`'s coherence preflight compares
#     local.host_scripts_content_hash against the hash baked into web-1's RUNNING image.
#     PR A does not move that hash, so the preflight passes against the CURRENT image and
#     the de-pool can run the moment the merge lands. (The single-PR shape edited
#     cat-deploy-state.sh — a baked member — so it had to wait ~40 min for a release to
#     land first, or the preflight aborted the de-pool. That was P0-a.)
#   * No `[skip-deploy-fix-apply]` kill switch. PR A changes no deploy-pipeline-fix trigger,
#     so there is no triggers_replace hash for a racing merge-apply to consume. (That was
#     P0-b: the racing run spent the trigger against a coin-flipped host, making the later
#     dispatch a silent no-op.)
#
# Splitting dissolved both rather than compensating for them — which is why 3 of 7 plan
# reviewers asked for it. PR B (host identity) needs no post-merge script at all: once
# web-2 is de-pooled, its merge-triggered push lands on web-1 deterministically.
#
# Usage:  bash scripts/followthroughs/web2-tunnel-depool-6425.sh [--dry-run]
# Needs:  gh (authed), doppler (authed; prd_terraform read), jq, curl.
set -euo pipefail

DRY_RUN=""
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1

REPO="${GH_REPO:-jikig-ai/soleur}"
ISSUE=6425
APPLY_DEADLINE_S="${APPLY_DEADLINE_S:-1800}"   # 30 min: the recreate apply

say()  { printf '\n=== %s\n' "$*"; }
info() { printf '    %s\n' "$*"; }
die()  { printf '\nFATAL: %s\n' "$*" >&2; exit 1; }
run()  { if [[ -n "$DRY_RUN" ]]; then info "DRY-RUN: $*"; else "$@"; fi; }

command -v gh >/dev/null      || die "gh not on PATH"
command -v doppler >/dev/null || die "doppler not on PATH"
command -v jq >/dev/null      || die "jq not on PATH"

# --- census (the AC1 authority; the classifier is pure + unit-tested) -------------------------
CENSUS_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/scripts/tunnel-connector-census.sh"
[[ -f "$CENSUS_LIB" ]] || die "census lib not found at $CENSUS_LIB"
# shellcheck source=../tunnel-connector-census.sh
source "$CENSUS_LIB"

census_now() {  # echoes "<verdict> <count>"; never exits non-zero on an API failure
  local tok acct tid resp code body
  tok=$(doppler secrets get CF_API_TOKEN --project soleur --config prd_terraform --plain 2>/dev/null || true)
  acct=$(doppler secrets get CF_ACCOUNT_ID --project soleur --config prd_terraform --plain 2>/dev/null || true)
  [[ -n "$tok" && -n "$acct" ]] || { echo "census_unavailable -1"; return 0; }
  tid=$(curl -s --max-time 20 -H "Authorization: Bearer $tok" \
    "https://api.cloudflare.com/client/v4/accounts/$acct/cfd_tunnel?name=soleur-web-platform" \
    | jq -r '.result[0].id // empty' 2>/dev/null || true)
  [[ -n "$tid" ]] || { echo "census_unavailable -1"; return 0; }
  resp=$(curl -s --max-time 20 -w '\n%{http_code}' -H "Authorization: Bearer $tok" \
    "https://api.cloudflare.com/client/v4/accounts/$acct/cfd_tunnel/$tid/connections" || printf '\n000')
  code=$(printf '%s' "$resp" | tail -1); body=$(printf '%s' "$resp" | sed '$d')
  classify_connector_census "$code" "$body"
}

# =============================================================================================
say "STAGE 0 — where are we?"

BASELINE=$(census_now); info "connector census: $BASELINE"
case "$BASELINE" in
  "ok 1")
    info "Already exactly one connector — the de-pool has run. Re-verifying and resolving."
    SKIP_DEPOOL=1 ;;
  "multi_connector"*)
    info "More than one connector — the de-pool has not run yet. Proceeding." ;;
  *)
    die "census is '$BASELINE'. Refusing to act on an unreadable or zero census — dispatching
    a de-pool against an unknown connector state is the coin flip #6425 is about. Investigate
    first: an unreadable census is usually an expired CF_API_TOKEN in Doppler prd_terraform;
    a genuine zero means the tunnel is already fully dark." ;;
esac

# =============================================================================================
say "STAGE 1 — de-pool web-2 (scoped dispatch; data volume preserved)"

if [[ -n "${SKIP_DEPOOL:-}" ]]; then
  info "skipped (census already 1)."
else
  run gh workflow run apply-web-platform-infra.yml --repo "$REPO" \
    -f apply_target=web-2-recreate \
    -f reason="#6425 de-pool web-2 from the shared tunnel (ADR-114 I1)"
  if [[ -z "$DRY_RUN" ]]; then
    info "dispatched; waiting for the run to complete…"
    sleep 20
    RID=$(gh run list --repo "$REPO" --workflow=apply-web-platform-infra.yml \
      --event=workflow_dispatch --limit 1 --json databaseId --jq '.[0].databaseId')
    info "run: https://github.com/$REPO/actions/runs/$RID"
    timeout "$APPLY_DEADLINE_S" gh run watch "$RID" --repo "$REPO" --exit-status \
      || die "the web-2-recreate run failed or timed out — see the run log.
    If it failed on 'resource_unavailable', the DC is capacity-starved: web-2 was destroyed
    and cannot be re-placed, which WEDGES every apply-on-merge (the 2026-07-13 / #6374
    precedent). Documented lever: flip var.web_hosts[\"web-2\"].location off the starved DC
    and re-dispatch — each apply re-plans from scratch, so the flip unwedges it."
  fi
fi

# =============================================================================================
say "STAGE 2 — AC1: the invariant (vantage-independent)"

if [[ -n "$DRY_RUN" ]]; then
  info "DRY-RUN: would assert census == 'ok 1'"
else
  # web-2's cloudflared re-registers within seconds of boot if the gate did not apply, so a
  # brief retry loop distinguishes "still settling" from "the gate is not in the image".
  for attempt in 1 2 3 4 5; do
    V=$(census_now); info "attempt $attempt: census = $V"
    [[ "$V" == "ok 1" ]] && break
    (( attempt == 5 )) && die "AC1 FAILED: census is '$V', expected 'ok 1'.
    web-2 still holds a connector. Check that the merged server.tf carries
    web_tunnel_connector = each.key == \"web-1\", and that the recreate actually re-rendered
    user_data (it renders only at CREATE — lifecycle.ignore_changes covers it otherwise)."
    sleep 30
  done
  info "AC1 PASS — exactly one connector. deploy./ssh./registry. ingress is now deterministic."
fi

# =============================================================================================
say "STAGE 3 — resolve #$ISSUE (only after AC1 passed)"

if [[ -n "$DRY_RUN" ]]; then
  info "DRY-RUN: would close #$ISSUE"
else
  FINAL=$(census_now)
  if [[ "$FINAL" == "ok 1" ]]; then
    STATE=$(gh issue view "$ISSUE" --repo "$REPO" --json state --jq '.state')
    if [[ "$STATE" == "OPEN" ]]; then
      gh issue close "$ISSUE" --repo "$REPO" --comment "De-pool verified: the connector census returns exactly 1 (ADR-114 I1). web-2 no longer registers a connector, so deploy./ssh./registry. ingress is deterministic by construction. Closed by scripts/followthroughs/web2-tunnel-depool-6425.sh. Standing guard: the */15 census in scheduled-inngest-health.yml files an action-required issue if the count ever leaves 1."
      info "closed #$ISSUE"
    else
      info "#$ISSUE already $STATE"
    fi
  else
    die "refusing to resolve #$ISSUE — final census is '$FINAL', not 'ok 1'."
  fi
fi

say "DONE — web-2 is de-pooled and the invariant is verified."
info "PR B (host identity) can merge now: its push lands on web-1 deterministically."
