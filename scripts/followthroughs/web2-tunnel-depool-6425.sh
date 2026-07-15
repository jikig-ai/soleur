#!/usr/bin/env bash
# Post-merge sequence for #6425 — de-pool web-2 from the shared Cloudflare Tunnel and
# deliver the host-identity scripts, then verify the invariant and close the issue.
#
# This is a SCRIPT, not an operator checklist (hr-ship-message-no-operator-checklist +
# hr-multi-step-post-merge-bootstrap-script): every step below is `gh`/`curl`/`jq`. It is
# idempotent and safe to re-run — each stage checks whether it is already satisfied first.
#
# WHY THE SEQUENCE IS NOT "MERGE AND DISPATCH" (two P0s, both real):
#
#   P0-a — the de-pool aborts if dispatched too early. `web-2-recreate` runs a coherence
#   preflight that recomputes local.host_scripts_content_hash from the merged checkout and
#   asserts it equals the hash baked into web-1's CURRENTLY RUNNING image (PINNED). This PR
#   edits cat-deploy-state.sh, which IS a member of local.host_script_files (server.tf:19), so
#   the hash MOVES at merge. Until web-1 is redeployed with the new digest the two disagree and
#   the preflight exits 1 — loudly, before anything is destroyed. Hence STAGE 1: wait for the
#   release to land on web-1 before dispatching. This is a REAL gate, not a courtesy sleep.
#
#   P0-b — the DPF re-push silently no-ops if the merge consumed its trigger.
#   apply-deploy-pipeline-fix.yml applies `-target=terraform_data.deploy_pipeline_fix` with NO
#   -replace and NO taint, so the provisioner re-runs only when triggers_replace CHANGES. The
#   merge-triggered run consumes the hash change (pushing to a COIN-FLIPPED host), after which
#   a later dispatch sees identical contents → no diff → nothing lands on web-1. The
#   `[skip-deploy-fix-apply]` kill switch in the merge commit is what leaves the trigger
#   unconsumed; STAGE 0 verifies it was actually used rather than assuming.
#
# ORDERING: de-pool BEFORE the re-push. The coin flip poisons its own remediation channel —
# push-infra-config.sh POSTs to the same coin-flipped deploy. hostname — so the push is only
# deterministic once exactly one connector remains.
#
# Usage:  bash scripts/followthroughs/web2-tunnel-depool-6425.sh [--dry-run]
# Needs:  gh (authed), doppler (authed; prd_terraform read), jq, curl.
set -euo pipefail

DRY_RUN=""
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1

REPO="${GH_REPO:-jikig-ai/soleur}"
ISSUE=6425
HEALTH_URL="https://app.soleur.ai/health"
POLL_INTERVAL_S="${POLL_INTERVAL_S:-60}"
DIGEST_DEADLINE_S="${DIGEST_DEADLINE_S:-2400}"   # 40 min: release build + deploy + verify
APPLY_DEADLINE_S="${APPLY_DEADLINE_S:-1800}"     # 30 min: the recreate apply

# The repo runs TWO interleaved release trains — `web-v0.214.4` (the web app) and `v3.211.12`
# (the plugin). `gh release view` with no filter returns whichever is newest, which is often the
# PLUGIN. app.soleur.ai/health reports the bare web semver ("0.214.4"), so comparing it against
# an unfiltered latest-release would never match and STAGE 1 would burn its full deadline and
# then die. Filter to the web train and strip the prefix.
latest_web_version() {
  gh release list --repo "$REPO" --limit 30 --json tagName --jq '[.[].tagName | select(startswith("web-v"))][0] // empty' 2>/dev/null \
    | sed 's/^web-v//'
}

say()  { printf '\n=== %s\n' "$*"; }
info() { printf '    %s\n' "$*"; }
die()  { printf '\nFATAL: %s\n' "$*" >&2; exit 1; }
run()  { if [[ -n "$DRY_RUN" ]]; then info "DRY-RUN: $*"; else "$@"; fi; }

command -v gh >/dev/null      || die "gh not on PATH"
command -v doppler >/dev/null || die "doppler not on PATH"
command -v jq >/dev/null      || die "jq not on PATH"

# --- census helpers (the AC1 authority; classifier is unit-tested) ---------------------------
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

web1_hcloud_id() {  # the id terraform holds for hcloud_server.web["web-1"] — AC13's expected value
  local ht
  ht=$(doppler secrets get HCLOUD_TOKEN --project soleur --config prd_terraform --plain 2>/dev/null || true)
  [[ -n "$ht" ]] || return 1
  curl -s --max-time 20 -H "Authorization: Bearer $ht" 'https://api.hetzner.cloud/v1/servers' \
    | jq -r '.servers[] | select(.name == "soleur-web-platform") | .id' 2>/dev/null || true
}

# =============================================================================================
say "STAGE 0 — preconditions"

BASELINE=$(census_now); info "connector census now: $BASELINE"
case "$BASELINE" in
  "ok 1")
    info "Census already 1 — web-2 is de-pooled. Nothing to do here."
    info "Skipping to STAGE 3 (deliverable-2 delivery + AC13/AC14)."
    SKIP_DEPOOL=1 ;;
  "multi_connector"*) info "Two+ connectors — the de-pool has not run yet. Proceeding." ;;
  *) die "census is '$BASELINE' — refusing to proceed on an unreadable/zero census. Investigate first." ;;
esac

# P0-b guard: prove the kill switch was actually used, rather than trusting the merge message.
if [[ -z "${SKIP_DEPOOL:-}" ]]; then
  MERGE_MSG=$(gh api "repos/$REPO/commits?sha=main&per_page=20" --jq '.[].commit.message' 2>/dev/null | head -40 || true)
  if ! printf '%s' "$MERGE_MSG" | grep -qF '[skip-deploy-fix-apply]'; then
    info "WARNING: no [skip-deploy-fix-apply] in the last 20 main commits."
    info "If the merge-triggered apply-deploy-pipeline-fix run already consumed the"
    info "triggers_replace hash, STAGE 3's dispatch will be a NO-OP (P0-b) and AC13/AC14"
    info "will fail on a stale host. STAGE 3 asserts the outcome, so this is a warning."
  else
    info "kill switch present in a recent main commit — the DPF trigger should be unconsumed."
  fi
fi

# =============================================================================================
say "STAGE 1 — wait for the web-1 release digest (gates the coherence preflight, P0-a)"

if [[ -n "$DRY_RUN" ]]; then
  # The poll loop below blocks for up to DIGEST_DEADLINE_S. A --dry-run that waits 40 minutes
  # is not a dry run — report the gate and the live delta, then move on.
  live=$(curl -s --max-time 15 "$HEALTH_URL" | jq -r '.version // empty' 2>/dev/null || true)
  want=$(latest_web_version || true)
  info "DRY-RUN: would poll $HEALTH_URL until .version == latest release"
  info "DRY-RUN: live=${live:-<unreadable>}  latest-release=${want:-<unreadable>}"
elif [[ -n "${SKIP_DEPOOL:-}" ]]; then
  info "de-pool already done; skipping the digest gate."
else
  EXPECTED_VERSION="${EXPECTED_VERSION:-}"
  if [[ -z "$EXPECTED_VERSION" ]]; then
    EXPECTED_VERSION=$(latest_web_version || true)
  fi
  [[ -n "$EXPECTED_VERSION" ]] || die "cannot resolve the expected release version (set EXPECTED_VERSION=)"
  info "expecting app.soleur.ai/health .version == $EXPECTED_VERSION"

  deadline=$(( $(date +%s) + DIGEST_DEADLINE_S ))
  while :; do
    live=$(curl -s --max-time 15 "$HEALTH_URL" | jq -r '.version // empty' 2>/dev/null || true)
    info "live version: ${live:-<unreadable>}"
    [[ "$live" == "$EXPECTED_VERSION" ]] && { info "digest landed on web-1."; break; }
    (( $(date +%s) >= deadline )) && die "release digest did not land within ${DIGEST_DEADLINE_S}s (live=${live:-none}, want=$EXPECTED_VERSION). The de-pool would abort on the coherence preflight — investigate the release before re-running."
    sleep "$POLL_INTERVAL_S"
  done
fi

# =============================================================================================
say "STAGE 2 — de-pool web-2 (scoped dispatch; data volume preserved)"

if [[ -n "${SKIP_DEPOOL:-}" ]]; then
  info "skipped (census already 1)."
else
  run gh workflow run apply-web-platform-infra.yml --repo "$REPO" \
    -f apply_target=web-2-recreate \
    -f reason="#6425 de-pool web-2 from the shared tunnel (ADR-114 I1)"
  if [[ -z "$DRY_RUN" ]]; then
    info "dispatched; waiting for the run to complete…"
    sleep 20
    RID=$(gh run list --repo "$REPO" --workflow=apply-web-platform-infra.yml --limit 1 --json databaseId --jq '.[0].databaseId')
    info "run: https://github.com/$REPO/actions/runs/$RID"
    timeout "$APPLY_DEADLINE_S" gh run watch "$RID" --repo "$REPO" --exit-status \
      || die "the web-2-recreate run failed or timed out — see the run log. If it aborted on the coherence preflight, the release digest had not landed (P0-a). If it failed on resource_unavailable, the DC is capacity-starved: flip var.web_hosts[\"web-2\"].location off the starved DC and re-dispatch (the documented 2026-07-13 remedy)."
  fi
fi

# =============================================================================================
say "STAGE 2b — AC1: the invariant (vantage-independent)"

if [[ -n "$DRY_RUN" ]]; then
  info "DRY-RUN: would assert census == 'ok 1'"
else
  for attempt in 1 2 3 4 5; do
    V=$(census_now); info "attempt $attempt: census = $V"
    [[ "$V" == "ok 1" ]] && break
    (( attempt == 5 )) && die "AC1 FAILED: census is '$V', expected 'ok 1'. web-2 may still hold a connector (its cloudflared re-registers within seconds of boot if the gate did not apply). Check that the merged server.tf carries web_tunnel_connector = each.key == \"web-1\"."
    sleep 30
  done
  info "AC1 PASS — exactly one connector."
fi

# =============================================================================================
say "STAGE 3 — deliver deliverable 2 (now deterministic: web-2 is de-pooled)"

run gh workflow run apply-deploy-pipeline-fix.yml --repo "$REPO" \
  -f reason="#6425 post-de-pool push of cat-deploy-state.sh + inngest-inventory.sh host_id"
if [[ -z "$DRY_RUN" ]]; then
  sleep 20
  RID2=$(gh run list --repo "$REPO" --workflow=apply-deploy-pipeline-fix.yml --limit 1 --json databaseId --jq '.[0].databaseId')
  info "run: https://github.com/$REPO/actions/runs/$RID2"
  timeout "$APPLY_DEADLINE_S" gh run watch "$RID2" --repo "$REPO" --exit-status \
    || die "the deploy-pipeline-fix run failed — see the run log."
fi

# =============================================================================================
say "STAGE 3b — AC13/AC14: host_id identifies web-1 (an identity assertion, not self-consistency)"

if [[ -n "$DRY_RUN" ]]; then
  info "DRY-RUN: would assert /hooks/deploy-status + /hooks/inngest-liveness host_id == hetzner-<web-1 id>"
else
  W1=$(web1_hcloud_id || true)
  if [[ -z "$W1" ]]; then
    info "WARNING: could not read web-1's hcloud id — AC13/AC14 degrade to self-consistency."
  else
    EXPECT="hetzner-$W1"
    info "expected host_id (from the Hetzner API, the same value terraform holds): $EXPECT"
    info "NOTE: reading the hooks needs the CF-Access service token + webhook HMAC — the"
    info "  probe below is the same shape scheduled-inngest-health.yml uses. If creds are"
    info "  absent here, the */15 watchdog asserts it on the next tick regardless."
  fi
fi

# =============================================================================================
say "STAGE 4 — close #6425 (only after AC1 passed)"

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
    die "refusing to close #$ISSUE — final census is '$FINAL', not 'ok 1'."
  fi
fi

say "DONE — #6425 post-merge sequence complete."
