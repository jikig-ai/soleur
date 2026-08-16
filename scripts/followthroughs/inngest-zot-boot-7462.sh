#!/usr/bin/env bash
# #7462 / #7228 — post-delivery readback for the dedicated inngest host's zot-primary boot.
#
# TRACKERS: **#7462** (the restore) and **#7228** (the dispatch incident). Both are OPEN and both
# stay open until this reads PASS. scripts/sweep-followthroughs.sh lists `--state open`, so hosting
# a probe on a closed issue is a permanent silent no-op — do not re-point this at #6500, which is
# an AUTHORIZATION act (ADR-096 Phase 5.3-5.5) whose own probe is zot-soak-6122.sh.
#
# WHAT IT VERIFIES. PR #7516 gave the host a zot-primary bootstrap pull path. That PR is INERT at
# merge: hcloud_server.inngest is in no `-target` on the per-merge apply path, so nothing in
# cloud-init-inngest.yml reaches the host until the separately gated
# `apply_target=inngest-host-replace` dispatch (#7462 steps 4-6). Until that dispatch fires this
# probe is EXPECTED to read TRANSIENT — that is the steady state, not a fault.
#
# KNOWN COST, STATED RATHER THAN DISCOVERED: on the open path the sweeper comments unconditionally
# before deciding, so a correctly-behaving exit-2 probe posts one comment per sweep until delivery.
# `earliest=` is set a week out for exactly this reason; if delivery slips, push the date rather
# than weakening an arm.
#
# THE DISCRIMINATOR IS POSITIVE AND STAGE-ISOLATED, and the control is deliberately NOT the pull.
# `stage=inngest_zot` proves the zot leg served the manifest. It does NOT prove the image ran —
# inngest-bootstrap.sh ships INSIDE that image, and the entire #7228 incident was "the pull half
# worked well enough to look fine while nothing installed". So PASS additionally requires
# `stage=bootstrap-done`, which is emitted only after the pulled image's bootstrap completes. That
# is a READBACK out of the warehouse, which no exit code on the host can fake.
#
# WHY NOT the negation "no oci-pull-ALL-LEGS-FAILED rows". That form is FAIL-OPEN: a host that
# never boots emits nothing at all and would auto-PASS on the exact state this exists to reject.
# Absence arms are used only to DOWNGRADE a positive, never to grant one.
#
# GHCR IS NOT A FALLBACK ANY MORE. AP-016 lapsed 2026-07-30 (#7071) and that PAT is revoked, so
# `stage=inngest_ghcr_fallback` means the zot leg missed and the remaining leg is a guaranteed 401.
# It is a downgrade, not a tolerated variant.
#
# EXIT CONTRACT (scripts/sweep-followthroughs.sh) — AND THE SINGLE `exit 1` IS DELIBERATE:
#   0 = PASS       zot-served AND bootstrap-done observed, with no failure marker in the window.
#   2 = TRANSIENT  not delivered, host dark, zot leg missed, bootstrap incomplete, or ANY
#                  auth/query/decode failure. Each prints a DISTINCT reason — an unprovisioned
#                  credential must never read as "not yet delivered", because the two have
#                  opposite remedies and only one of them is a wait.
#   1 = FAIL       emitted ONLY when oci-pull-ALL-LEGS-FAILED is observed. That is a DELIVERED and
#                  BROKEN host — both registry legs refused, the host is dark, and inbound-email
#                  dispatch is down. It is actionable now, not a not-yet, so it must comment.
#                  Everywhere else exit 1 is forbidden because it comments daily.
#
# THE `${VAR:?msg}` FORM IS BANNED HERE and the ban is mechanical, not stylistic: under the
# sweeper's non-interactive shell that word-expansion aborts with status 1, which this contract
# reads as FAIL — so an unprovisioned secret would post a daily false-FAIL forever instead of
# retrying quietly. scripts/lint-followthrough-varq-ban.sh reddens CI on it.
#
# ENCODING-SAFE GREP, THEN DECODE, THEN FIELD-ISOLATE. ClickHouse stores `raw` DOUBLE-ENCODED, so a
# grep containing a quote or a colon-joined field name becomes a LIKE that matches NOTHING, EVER.
# The single --grep below carries neither, and every judgement is made on the DECODED `.stage`
# field — not on a substring of the row, or a CI job that merely PRINTED a stage name would count.
#
# THE ARCHIVE ARM STAYS. The window is 7d because a host replace is a rare, operator-timed event;
# betterstack-query.sh's remote() alone is only the ~40-minute hot window. Do NOT copy --no-archive
# from the minutes-old sibling probes (zot-log-channel-7440.sh) — here it would silently truncate
# the window to well under the thing being measured.
#
# Required env (LITERAL names — the sweeper runs probes under `env -i` with PATH + HOME + the
# directive-declared `secrets=` ONLY; all three are already wired into
# .github/workflows/scheduled-followthrough-sweeper.yml, so this needs no workflow edit):
#   BETTERSTACK_QUERY_HOST, BETTERSTACK_QUERY_USERNAME, BETTERSTACK_QUERY_PASSWORD
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
QUERY="${INNGEST_ZOT_BOOT_QUERY_BIN:-$REPO_ROOT/scripts/betterstack-query.sh}"

MARKER="SOLEUR_INNGEST_BOOT_STAGE"
WINDOW="${INNGEST_ZOT_BOOT_WINDOW:-7d}"
LIMIT="${INNGEST_ZOT_BOOT_LIMIT:-2000}"

# --- credentials: absent is TRANSIENT, and must say so in its own words ------------------------
missing=""
[[ -z "${BETTERSTACK_QUERY_HOST:-}" ]] && missing="${missing} BETTERSTACK_QUERY_HOST"
[[ -z "${BETTERSTACK_QUERY_USERNAME:-}" ]] && missing="${missing} BETTERSTACK_QUERY_USERNAME"
[[ -z "${BETTERSTACK_QUERY_PASSWORD:-}" ]] && missing="${missing} BETTERSTACK_QUERY_PASSWORD"
if [[ -n "$missing" ]]; then
  echo "TRANSIENT: reason=credentials_unprovisioned — missing:${missing}." >&2
  echo "           This is NOT 'not yet delivered'. The probe could not ask the question at all," >&2
  echo "           so nothing about the host was measured. Next: confirm the directive's secrets=" >&2
  echo "           clause lists all three and that they are set in the sweeper workflow env." >&2
  exit 2
fi

# --- one query, decoded once ------------------------------------------------------------------
rows="$("$QUERY" --since "$WINDOW" --grep "$MARKER" --limit "$LIMIT" 2>/dev/null)"
qrc=$?
if [[ "$qrc" -ne 0 ]]; then
  echo "TRANSIENT: reason=query_failed rc=${qrc} — the ClickHouse read path did not answer." >&2
  echo "           Nothing about the host was measured. A revoked connection password and a" >&2
  echo "           network fault both land here; neither is a statement about delivery." >&2
  exit 2
fi

# Field-isolate on the DECODED object. `.raw | fromjson` per betterstack-query.sh's header;
# rows that do not decode are dropped rather than substring-matched, because a row that merely
# CONTAINS a stage name (a CI log echoing it, this script's own name) is not an occurrence.
#
# `-R` plus `fromjson?` at BOTH levels is load-bearing, not defensive habit. Without `-R`, jq
# parses the stream itself, so ONE malformed line aborts the whole invocation and every valid row
# after it is lost — which surfaces as reason=channel_dark, i.e. "the host never booted", on a
# window that in fact contained a clean PASS. A warehouse read is exactly where a truncated or
# non-JSON line shows up, so the failure is expected rather than exotic. Pinned by C12.
stages="$(printf '%s\n' "$rows" \
  | jq -R -r 'fromjson? | .raw? | fromjson? | select(.marker == "'"$MARKER"'") | .stage // empty' 2>/dev/null)"

count_stage() {
  local want="$1" n
  n="$(printf '%s\n' "$stages" | grep -cxF "$want" || true)"
  [[ "$n" =~ ^[0-9]+$ ]] || n=0
  printf '%s' "$n"
}

n_any="$(printf '%s\n' "$stages" | grep -c '[^[:space:]]' || true)"
[[ "$n_any" =~ ^[0-9]+$ ]] || n_any=0
n_zot="$(count_stage inngest_zot)"
n_bootstrap="$(count_stage bootstrap-done)"
n_prezot="$(count_stage pre-zot-pull)"
n_fallback="$(count_stage inngest_ghcr_fallback)"
n_allfail="$(count_stage oci-pull-ALL-LEGS-FAILED)"

# --- FAIL: delivered and broken. The one carve-out. -------------------------------------------
if [[ "$n_allfail" -gt 0 ]]; then
  echo "FAIL: reason=all_legs_failed — ${n_allfail} oci-pull-ALL-LEGS-FAILED marker(s) in the last ${WINDOW}." >&2
  echo "      The host was delivered and BOTH registry legs refused, so nothing installed and" >&2
  echo "      :8288 is unbound. Inbound-email and PR-review dispatch are down (#7228)." >&2
  echo "      This is actionable NOW and is not a wait. Next: read the marker's detail= field via" >&2
  echo "      betterstack-query.sh --grep oci-pull-ALL-LEGS-FAILED; it names each leg and its rc." >&2
  echo "      (zot=${n_zot} ghcr_fallback=${n_fallback} pre_zot_pull=${n_prezot} boot_markers=${n_any})" >&2
  exit 1
fi

# --- channel dark: the host has not reported at all -------------------------------------------
if [[ "$n_any" -eq 0 ]]; then
  echo "TRANSIENT: reason=channel_dark — zero ${MARKER} rows in the last ${WINDOW}." >&2
  echo "           The host has not booted in the window, or the phone-home token is unstaged." >&2
  echo "           Before delivery this is the EXPECTED reading: PR #7516's arm is inert at merge" >&2
  echo "           and reaches the host only via the apply_target=inngest-host-replace dispatch." >&2
  exit 2
fi

# --- booted, but on an image older than the shipper --------------------------------------------
if [[ "$n_prezot" -eq 0 ]]; then
  echo "TRANSIENT: reason=not_delivered — ${n_any} boot marker(s) present, so the host IS booting" >&2
  echo "           and the channel answers, but zero pre-zot-pull stages. That stage exists only in" >&2
  echo "           post-#7516 cloud-init, so this host is running an older user_data." >&2
  echo "           Next: this is a provisioning question, not a wait — dispatch" >&2
  echo "           apply_target=inngest-host-replace (#7462 steps 4-6)." >&2
  exit 2
fi

# --- delivered, but the zot leg missed ----------------------------------------------------------
if [[ "$n_zot" -eq 0 ]]; then
  echo "TRANSIENT: reason=zot_leg_missed — pre-zot-pull fired ${n_prezot} time(s) but zero" >&2
  echo "           inngest_zot stages; ${n_fallback} inngest_ghcr_fallback stage(s) in the window." >&2
  echo "           The new code ran and zot did not serve the pinned digest. Since AP-016 lapsed" >&2
  echo "           (#7071) the GHCR leg is a guaranteed 401, so the host cannot recover on its own." >&2
  echo "           Next: confirm the pinned digest is present in zot (mirror_only=true backfill)" >&2
  echo "           and that 10.0.1.40 reaches 10.0.1.30:5000." >&2
  exit 2
fi

# --- zot served, but the image never finished bootstrapping -------------------------------------
if [[ "$n_bootstrap" -eq 0 ]]; then
  echo "TRANSIENT: reason=bootstrap_incomplete — ${n_zot} inngest_zot stage(s) prove zot SERVED the" >&2
  echo "           image, but zero bootstrap-done stages, so the pulled image did not finish." >&2
  echo "           The pull half is not the deliverable: inngest-bootstrap.sh ships INSIDE that" >&2
  echo "           image, and this exact gap is what made #7228 look healthy while dispatch was" >&2
  echo "           dead. Next: read bootstrap-exit- and post-boot-health stages for the rc." >&2
  exit 2
fi

# --- a GHCR fallback alongside a success is still a downgrade -----------------------------------
if [[ "$n_fallback" -gt 0 ]]; then
  echo "TRANSIENT: reason=fallback_observed — ${n_zot} inngest_zot and ${n_bootstrap} bootstrap-done" >&2
  echo "           stage(s), but also ${n_fallback} inngest_ghcr_fallback stage(s) in the window." >&2
  echo "           At least one boot did not resolve from zot. Steady state for ADR-096 Phase 5 is" >&2
  echo "           ZERO fallbacks, and with AP-016 lapsed each one is a boot that survived by luck." >&2
  echo "           Not closing on a partially-migrated pull path." >&2
  exit 2
fi

# --- PASS ---------------------------------------------------------------------------------------
# COUNTS ONLY. sweep-followthroughs.sh captures this stdout with 2>&1 and posts it as a comment on
# a PUBLIC repo issue. The markers' detail= fields carry 10.0.1.x topology, OCI repo names and
# digests, so row VALUES are never printed here. The question this probe answers ("did the host
# boot from zot and finish?") is a counting question.
echo "PASS: the dedicated inngest host booted zot-primary and completed bootstrap."
echo "      Window ${WINDOW}: inngest_zot=${n_zot} bootstrap-done=${n_bootstrap} pre-zot-pull=${n_prezot}"
echo "      ghcr_fallback=${n_fallback} all_legs_failed=${n_allfail} total_boot_markers=${n_any}"
echo "      This is a READBACK out of the Better Stack warehouse, not the host's self-report."
echo "      The discriminator is POSITIVE and stage-isolated on the decoded .stage field:"
echo "      inngest_zot proves zot served the manifest, and bootstrap-done proves the pulled image"
echo "      actually ran — the half that was missing throughout #7228."
echo "      #7462 (restore) and #7228 (dispatch incident) may now close. #6500 is a SEPARATE"
echo "      authorization act gating ADR-096 Phase 5.3-5.5 and is NOT closed by this probe."
exit 0
