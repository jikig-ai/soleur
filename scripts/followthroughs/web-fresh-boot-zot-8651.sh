#!/usr/bin/env bash
# web-fresh-boot-zot-8651.sh — follow-through probe that owns the close of #8651.
#
# #8651: every fresh web-host boot since the 2026-07-17 zot cutover resolved its seed image to
# GHCR (the zot selection read Doppler tokenlessly, #6985), and the GHCR read PAT is revoked
# (AP-016), so every fresh web boot was DARK. The fix bakes the zot endpoint + pull credential
# into user_data. Merging it changes no host (hcloud_server.web ignore_changes = [user_data]);
# only a web-host-replace of web-2 realizes it. This probe is the OBSERVED-EVIDENCE close
# condition the zot soak's WEB_BLOCKER arm (zot-soak-6122.sh) requires: #8651 CLOSED as
# COMPLETED only once a fresh web boot is SEEN zot-served — never on merge.
#
# Evidence is read through `fresh-host-boot-trail.sh --image-origin`, so the Sentry filter
# lives in one place. That mode prints two lines for the host:
#   image-origin: stage=<app_zot|app_ghcr_served|app_ghcr_fallback|none> ... time=<iso> detail=<…>
#   seed-fatal:   stage=<stage|none> ... time=<iso> detail=<…>
#
# Why no time lower bound: only the fixed template emits BOTH a host_name tag on _emit AND a
# `zot_login=` detail on app_zot. An app_zot for soleur-web-2 carrying `zot_login=ok` is
# therefore from the new template by construction; pre-fix events carry no host_name at all
# (measured: the 3 July app_ghcr_served events have host_name ""), so they cannot match.
#
# Exit (sweep-followthroughs.sh contract):
#   0 PASS            — app_zot with zot_login=ok for soleur-web-2, and no seed fatal NEWER than it
#   1 FAIL            — a seed fatal for soleur-web-2 is newer than every app_zot (booted dark again)
#                       or the newest origin is GHCR (app_ghcr_served / app_ghcr_fallback)
#   2 NOT YET         — no fresh web-2 boot from the fixed template observed yet
#   3 CANNOT ESTABLISH — token unbound, Sentry unreadable, or an unparseable answer (TRANSIENT:)
#   78                — refused to run under xtrace (a live credential is in the environment)
set -uo pipefail
case "$-" in
  *x*) printf '[FATAL] refusing to run under xtrace: SENTRY_ACTIONS_RO_TOKEN is in the environment (see #7797)\n' >&2; exit 78 ;;
esac

HOST="${WEB_ZOT_8651_HOST:-soleur-web-2}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TRAIL="${WEB_ZOT_8651_TRAIL:-$REPO_ROOT/apps/web-platform/infra/scripts/fresh-host-boot-trail.sh}"

if [[ -z "${SENTRY_ACTIONS_RO_TOKEN:-}" ]]; then
  echo "TRANSIENT: SENTRY_ACTIONS_RO_TOKEN is not bound — declare it in the directive's secrets= clause. Cannot establish the image origin." >&2
  exit 3
fi
[[ -f "$TRAIL" ]] || { echo "TRANSIENT: boot-trail reader not found at $TRAIL" >&2; exit 3; }

out=$(bash "$TRAIL" --image-origin "$HOST" 2>&1); rc=$?
if [[ "$rc" -eq 2 ]] || grep -q '^TRANSIENT:' <<<"$out"; then
  echo "TRANSIENT: image-origin read failed (rc=$rc): $(head -c 300 <<<"$out")" >&2
  exit 3
fi
origin=$(grep -m1 '^image-origin:' <<<"$out" || true)
fatal=$(grep -m1 '^seed-fatal:' <<<"$out" || true)
if [[ -z "$origin" || -z "$fatal" ]]; then
  echo "TRANSIENT: unparseable image-origin output (rc=$rc): $(head -c 300 <<<"$out")" >&2
  exit 3
fi
field() { sed -nE "s/.* $1=([^ ]*).*/\1/p" <<<"$2" | head -1; }
o_stage=$(field stage "$origin"); o_time=$(field time "$origin")
f_stage=$(field stage "$fatal"); f_time=$(field time "$fatal")
echo "$origin"
echo "$fatal"

# A seed fatal newer than the newest origin event = this host booted dark after (or without) a
# zot-served boot. ISO-8601 UTC timestamps in one format compare correctly as strings.
if [[ "$f_stage" != none && ( "$o_stage" == none || "$f_time" > "$o_time" ) ]]; then
  echo "FAIL: $HOST booted DARK (seed fatal at $f_time is newer than the newest image-origin event). Map the detail's nic=/zot=[…cause=…] fields to the plan's Observability failure modes, fix forward, then re-dispatch web-host-replace — runcmd is once-per-instance, an unchanged re-replace repeats."
  exit 1
fi
case "$o_stage" in
  none)
    echo "NOT YET: no fresh $HOST boot from the fixed template observed (dispatch web-host-replace web_host_key=web-2, confirm=REPLACE-web-2)."
    exit 2 ;;
  app_zot)
    if grep -q 'zot_login=ok' <<<"$origin"; then
      echo "PASS: $HOST booted zot-served (zot_login=ok) at $o_time with no later seed fatal — #8651's observed-evidence close condition holds. GHCR's outcome is recorded in the same detail (ghcr_login=…); it is not asserted, so a restored GHCR credential cannot fail a correct zot boot."
      exit 0
    fi
    echo "FAIL: $HOST app_zot at $o_time lacks zot_login=ok in its detail — not the fixed template's success beacon."
    exit 1 ;;
  *)
    echo "FAIL: the newest image-origin event for $HOST is $o_stage at $o_time — GHCR served the boot, not zot."
    exit 1 ;;
esac
