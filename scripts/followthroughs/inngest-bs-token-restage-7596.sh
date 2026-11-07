#!/usr/bin/env bash
# #7596 — the boot-trace allowlist (`inngest-boot-phone-home`,
# `inngest-bs-token-restage`) reaches the inngest host ONLY inside a baked
# image through `apply_target=inngest-host-replace`; this host's vector.toml is
# never redelivered by terraform_data.journald_persistent. This probe is the
# issue's measured close condition, and it runs THREE reads per pass:
#
#   leg 1 (journald):   rows with SYSLOG_IDENTIFIER="inngest-bs-token-restage",
#                       host="soleur-inngest" AND host_name="soleur-inngest-prd"
#   leg 2 (boot anchor): inngest-server-probe rows on the same host+host_name —
#                       the newest row's _BOOT_ID pins the CURRENT host
#                       generation; the last row of any OTHER boot id bounds it
#   leg 3 (curl ingest): SOLEUR_INNGEST_BOOT_STAGE markers with stage
#                       bs-token-restage-enabled / bs-token-restaged /
#                       bs-token-restage-enable-FAILED — the host's own
#                       boot-stage markers ride the direct-curl ingest leg
#                       (cloud-init-inngest.yml), INDEPENDENT of the
#                       journald→Vector leg under test
#
# THE GENERATION FLOOR. PASS counts only CURRENT-GENERATION evidence: a
# restage `ok=1` row must postdate MIN_DT (the filing/enrollment floor —
# pre-floor rows are by construction pre-replace evidence, e.g. the 2026-10-18
# `bs-token-restage-enabled` marker) AND positively resolve AND match
# `_BOOT_ID` against the newest server-probe row's boot id. `_BOOT_ID`
# unresolvable — the server-probe read is absent, or the row/probe carries no
# boot id — is TRANSIENT `boot_id_unresolvable`, NEVER a degraded
# MIN_DT-only PASS (that degraded path is exactly the stale-evidence close the
# 2026-10-28 learning names). BOOT_STAGE markers carry no _BOOT_ID; their
# generation is proven by dt: a marker must postdate the newest PREVIOUS-boot
# probe row (or, when no previous boot is visible in the window, fall within
# GEN_TOL_S of the current boot's earliest probe row — markers fire during
# boot, before the probe's first emit).
#
# THE TWO STAGES ARE NOT INTERCHANGEABLE. `bs-token-restaged` is emitted by
# inngest-bs-token-restage.sh on EVERY boot (per-boot phone-home — boot
# evidence only). `bs-token-restage-enabled` is emitted ONLY in the
# replace-bound first-boot runcmd (the `systemctl enable` arm — DELIVERY
# proof). Arm-2 therefore requires a same-generation `bs-token-restage-enabled`
# marker: a post-floor plain reboot ships `bs-token-restaged` with zero
# delivery evidence, and satisfying the close on it would be a false close on
# an undelivered unit.
#
#   exit 0 = PASS        current-generation close evidence, printed with
#                        `pass_arm=journald|boot_stage` and
#                        `journald_rows=present|absent` (the journald leg's
#                        verdict travels INSIDE the PASS the sweeper posts —
#                        an arm-2 PASS with journald_rows=absent is the
#                        leg_journald verdict delivered at close time, and
#                        arm-1 is preferred when both legs carry evidence)
#   exit 1 = FAIL        deliberately unreachable — the probe's only honest
#                        states are PASS and TRANSIENT; a FAIL that can never
#                        discriminate is a misfire under the sweeper
#   exit 2 = TRANSIENT   reasons:
#                        pre_replace           no post-floor evidence of any
#                                            kind (the channel_dark-family
#                                            state — the replace has not
#                                            landed or the host emits nothing)
#                        leg_unit              post-floor activity proves the
#                                            host lives, but ZERO restage-unit
#                                            evidence on either leg in the
#                                            current generation — the unit
#                                            likely never ran/enabled
#                        restage_not_ok        current-generation restage rows
#                                            exist but none carries ok=1 /
#                                            the enabled stage (journald
#                                            SOLEUR_INNGEST_BS_TOKEN_RESTAGE_FAILED
#                                            drc= emits, or a
#                                            bs-token-restage-enable-FAILED
#                                            BOOT_STAGE marker)
#                        delivery_unproven     a current-generation
#                                            bs-token-restaged marker fired
#                                            (the per-boot restage ran) but
#                                            no same-generation
#                                            bs-token-restage-enabled marker
#                                            arrived — the expected state of
#                                            a plain post-floor reboot; the
#                                            replace-bound delivery proof
#                                            lives in an earlier generation
#                        boot_id_unresolvable  post-floor restage evidence
#                                            exists but the generation anchor
#                                            cannot be resolved
#                        credentials_unprovisioned | query_tool_missing |
#                        query_failed | selector_failed
#   exit 78              refused to run under xtrace with a live credential.
#
# NO leg_journald TRANSIENT REASON: arm-2 PASS preempts it — a post-floor
# BOOT_STAGE bs-token-restage-enabled marker satisfies PASS even with
# journald rows absent, so the journald leg's status is carried as
# `journald_rows=absent` inside the PASS output rather than as its own
# TRANSIENT vocabulary entry.
#
# Filter fields are isolated POST-DECODE — Better Stack stores `raw`
# double-encoded, so a literal `"host":"…"` grep on the outer row matches
# nothing, ever. Field isolation first, content check second: a missing row
# is silence, not a verdict — TRANSIENT, never FAIL.
#
# TRACKER: #7596 — `host=soleur-inngest` AND `host_name=soleur-inngest-prd`
# are both required on the journald leg: a web-1 row under a stale `host_name`
# is a real shape the shared renderer can produce (#6616), and an
# inert-on-web-1 identifier shipping a row was the exact false-close the
# issue names. The RESTAGE identifier is the positive control —
# `inngest-boot-phone-home` is silent-on-success by design (every logger call
# sits in a failure arm, journald-config.test.sh CF-4c).
#
# Tracker directive (goes in the issue body; a deferred operator step — the
# probe is inert until enrolled):
#   <!-- soleur:followthrough script=scripts/followthroughs/inngest-bs-token-restage-7596.sh earliest=2026-10-30T00:00:00Z secrets=BETTERSTACK_QUERY_HOST,BETTERSTACK_QUERY_USERNAME,BETTERSTACK_QUERY_PASSWORD -->
#
# Secrets clause: BETTERSTACK_QUERY_HOST / BETTERSTACK_QUERY_USERNAME /
# BETTERSTACK_QUERY_PASSWORD are already wired into the sweeper env. No
# `${VAR:?}` — the vault provision order is not guaranteed and that lint
# bans the form here. Reader stderr is never echoed.
#
# RETIREMENT: when #7596 closes, remove —
#   - this probe and scripts/followthroughs/inngest-bs-token-restage-7596.test.sh
#   - its run_suite line in scripts/test-all.sh (the
#     "scripts/followthroughs/inngest-bs-token-restage-7596" registration)
#   - the `<!-- soleur:followthrough ... -->` directive on issue #7596
#   - the verdict-taxonomy paragraphs in
#     knowledge-base/engineering/operations/runbooks/inngest-server.md
#     ("Post-replace: the boot-trace allowlist (#7596)")
set -uo pipefail

# xtrace refusal (the probes' credential discipline, #7797): a traced run
# would print the Better Stack credentials to the log.
case "$-" in
  *x*)                                                    # [mut:xtrace]
    if [ -n "${BETTERSTACK_QUERY_PASSWORD:+x}" ]; then
      printf '[FATAL] refusing to trace with a live credential set (see #7797)\n' >&2
      exit 78
    fi
    ;;
esac
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
QUERY="$SCRIPT_DIR/../betterstack-query.sh"               # [mut:query-path]
INNGEST_HOST='soleur-inngest'                             # [mut:host]
HOST_NAME='soleur-inngest-prd'
WINDOW="${RESTAGE_WINDOW:-${SOLEUR_FT_WINDOW:-7d}}"
LIMIT="${RESTAGE_LIMIT:-${SOLEUR_FT_LIMIT:-500}}"
IDENT='inngest-bs-token-restage'
MARKER='SOLEUR_INNGEST_BS_TOKEN_RESTAGED'
# The SQL prefilter uses the PREFIX, not the D-suffixed marker: the failure
# emit is SOLEUR_INNGEST_BS_TOKEN_RESTAGE_FAILED, which never contains
# RESTAGED — a full-prefix grep is what lets restage_not_ok fire on the real
# failure shape instead of misreporting it as channel_dark.
MARKER_PREFIX='SOLEUR_INNGEST_BS_TOKEN_RESTAGE'
PROBE_IDENT='inngest-server-probe'
STAGE_MARKER='SOLEUR_INNGEST_BOOT_STAGE'
# The generation floor: baked at filing/enrollment (ISO-8601 UTC). Only rows
# at or after MIN_DT may qualify — earlier evidence is by construction
# pre-replace. Suite-asserted constant.
MIN_DT='2026-10-30'                                       # [mut:floor]
MIN_DT_CUT="${MIN_DT} 00:00:00"
# BOOT_STAGE markers precede the first server-probe emit of their boot (the
# probe's first fire is timer-scheduled), so a marker may predate the earliest
# observed probe row of its own generation. 7200s covers the marker→first-probe
# ordering; a marker older than that relative to the current boot is treated
# as previous-generation, which only ever costs a TRANSIENT, never a false PASS.
GEN_TOL_S=7200                                            # [mut:tol]

# --- credentials: absent = TRANSIENT, never ${VAR:?} ------------------------
missing=""
[[ -z "${BETTERSTACK_QUERY_HOST:-}" ]] && missing="${missing} BETTERSTACK_QUERY_HOST"
[[ -z "${BETTERSTACK_QUERY_USERNAME:-}" ]] && missing="${missing} BETTERSTACK_QUERY_USERNAME"
[[ -z "${BETTERSTACK_QUERY_PASSWORD:-}" ]] && missing="${missing} BETTERSTACK_QUERY_PASSWORD"
if [[ -n "$missing" ]]; then                                        # [mut:cred]
  printf 'TRANSIENT: reason=credentials_unprovisioned — missing:%s. The sweeper env or doppler -c prd_terraform provides these; retry once provisioned.\n' \
    "$missing" >&2
  exit 2
fi
[[ -x "$QUERY" || -f "$QUERY" ]] || {
  printf 'TRANSIENT: reason=query_tool_missing — %s not found.\n' "$QUERY" >&2
  exit 2
}

postf() {  # postf <dt> — true iff the row's dt is shape-valid AND at/after the generation floor
  # The shape gate comes FIRST: the floor check is a lexical compare, and a
  # null or non-ISO dt reaching it can sort past '2026-…' and count as
  # post-floor evidence.
  [[ "$1" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2} ]] || return 1          # [mut:dtshape]
  [[ ! "$1" < "$MIN_DT_CUT" ]]
}
# A parse failure yields EMPTY output, never epoch 0 — a degenerate 0 bound
# would make the GEN_TOL_S comparison vacuous (every epoch >= -7200). Callers
# treat an empty epoch as unresolvable (gen=0), never a degraded pass.
ep() { date -u -d "$1" +%s 2>/dev/null; }

transient() { printf 'TRANSIENT: %s\n' "$1" >&2; exit 2; }

# --- the three reads ---------------------------------------------------------
qrc=0
jout="$("$QUERY" --since "$WINDOW" --grep "$MARKER_PREFIX" --limit "$LIMIT" 2>/dev/null)" || qrc=$?
[[ "$qrc" -eq 0 ]] || transient "reason=query_failed rc=$qrc leg=journald — the Better Stack read failed; no verdict can be formed this pass."
pout="$("$QUERY" --since "$WINDOW" --grep "$PROBE_IDENT" --limit "$LIMIT" 2>/dev/null)" || qrc=$?
[[ "$qrc" -eq 0 ]] || transient "reason=query_failed rc=$qrc leg=server-probe — the generation anchor could not be read."
bout="$("$QUERY" --since "$WINDOW" --grep "$STAGE_MARKER" --limit "$LIMIT" 2>/dev/null)" || qrc=$?
[[ "$qrc" -eq 0 ]] || transient "reason=query_failed rc=$qrc leg=boot-stage — the BOOT_STAGE read failed."

# Post-decode field isolation, one TSV per leg:
#   journald leg:  dt \t _BOOT_ID \t ok|other   (ident + host + host_name)
#   probe leg:     dt \t _BOOT_ID               (ident + host + host_name)
#   stage leg:     dt \t stage                  (.marker + .host — the curl
#                  payload carries no host_name; this leg is independent)
jrc=0
jrows="$(printf '%s\n' "$jout" | jq -R -r \
    --arg h "$INNGEST_HOST" --arg hn "$HOST_NAME" --arg id "$IDENT" --arg mok "$MARKER ok=1"'($|[[:space:]])' '
    fromjson? | . as $o | ($o.raw? | fromjson?) as $r
    | select($r | type == "object")
    | select($r.SYSLOG_IDENTIFIER == $id)
    | select($r.host == $h)
    | select($r.host_name == $hn)
    | "\($o.dt)\t\($r._BOOT_ID // "-")\t\(if ($r.message // "") | test($mok) then "ok" else "other" end)"' 2>/dev/null)" || jrc=$?
prows="$(printf '%s\n' "$pout" | jq -R -r \
    --arg h "$INNGEST_HOST" --arg hn "$HOST_NAME" --arg id "$PROBE_IDENT" '
    fromjson? | . as $o | ($o.raw? | fromjson?) as $r
    | select($r | type == "object")
    | select($r.SYSLOG_IDENTIFIER == $id)
    | select($r.host == $h)
    | select($r.host_name == $hn)
    | "\($o.dt)\t\($r._BOOT_ID // "-")"' 2>/dev/null)" || jrc=$?
srows="$(printf '%s\n' "$bout" | jq -R -r \
    --arg h "$INNGEST_HOST" --arg sm "$STAGE_MARKER" '
    fromjson? | . as $o | ($o.raw? | fromjson?) as $r
    | select($r | type == "object")
    | select($r.marker == $sm)
    | select($r.host == $h)
    | "\($o.dt)\t\($r.stage // "-")"' 2>/dev/null)" || jrc=$?
[[ "$jrc" -eq 0 ]] || transient "reason=selector_failed rc=$jrc — jq failed to decode; the Better Stack raw shape may have changed."

# --- the generation anchor ---------------------------------------------------
# The NEWEST server-probe row CARRYING a boot id names the current boot:
# rows whose _BOOT_ID never shipped ('-') are skipped — a newest dash row
# must not strand the probe in boot_id_unresolvable while an earlier row
# already named the generation. Lexicographic order on 'YYYY-MM-DD HH:MM:SS'
# is chronological.
CUR_BOOT="$(printf '%s\n' "$prows" | awk -F'\t' 'NF >= 2 && $1 != "" && $2 != "" && $2 != "-" { if ($1 >= m) { m = $1; b = $2 } } END { print b }')"
# The id is echoed verbatim into PASS/TRANSIENT output, and the sweeper posts
# probe output into issue comments — gate it to the _BOOT_ID charset before
# it may travel (markup/mention channel). Anything else degrades to
# unresolvable, never to output.
[[ "$CUR_BOOT" =~ ^[0-9a-f-]+$ ]] || CUR_BOOT=""                # [mut:bootgate]
# The last previous-generation probe row bounds the current boot from below
# (empty when no other boot is visible in the window).
PREV_BOUND="$(printf '%s\n' "$prows" | awk -F'\t' -v b="$CUR_BOOT" 'NF >= 2 && $2 != "" && $2 != "-" && $2 != b { if ($1 > m) m = $1 } END { print m }')"
# The current boot's earliest observed probe row — the fallback lower bound for
# the stage-leg generation test.
BOOT_LOW="$(printf '%s\n' "$prows" | awk -F'\t' -v b="$CUR_BOOT" 'NF >= 2 && $2 == b { if (m == "" || $1 < m) m = $1 } END { print m }')"
# Shape-gate the bounds before they enter the generation test: a garbage bound
# could sort below every real dt and prove 'current generation' for a stale
# marker.
[[ "$PREV_BOUND" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2} ]] || PREV_BOUND=""
[[ "$BOOT_LOW" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2} ]] || BOOT_LOW=""
BOOT_LOW_EPOCH=""; [[ -n "$BOOT_LOW" ]] && BOOT_LOW_EPOCH="$(ep "$BOOT_LOW")"

# --- classify the evidence ---------------------------------------------------
J_POST=0; J_QUAL=0; J_CURGEN=0; J_NOBOOT=0
while IFS=$'\t' read -r dt boot kind; do
  [[ -n "$dt" ]] || continue
  postf "$dt" || continue
  J_POST=$((J_POST + 1))
  if [[ -z "$boot" || "$boot" == "-" ]]; then J_NOBOOT=$((J_NOBOOT + 1)); continue; fi
  if [[ "$boot" == "$CUR_BOOT" ]]; then                                # [mut:boot]
    J_CURGEN=$((J_CURGEN + 1))
    [[ "$kind" == "ok" ]] && J_QUAL=$((J_QUAL + 1))
  fi
done <<< "$jrows"

# The stage-leg generation test: with a visible previous boot the marker must
# postdate that generation's last probe row; without one it must fall within
# GEN_TOL_S of the current boot's earliest probe row.
#
# THE TWO STAGES ARE NOT INTERCHANGEABLE (the arm-2 false-close). All three
# stages count as post-floor restage evidence (M_POST — liveness plus the
# unresolvable-anchor gate), but on a resolved generation they split:
#   bs-token-restage-enabled      replace-bound first-boot runcmd — DELIVERY
#                                 proof; the ONLY stage that qualifies arm-2
#   bs-token-restage-enable-FAILED same runcmd arm, failure side — feeds
#                                 restage_not_ok
#   bs-token-restaged             per-boot phone-home inside the restage
#                                 script — boot evidence only; a plain
#                                 post-floor reboot ships it with zero
#                                 delivery proof, so it can NEVER satisfy
#                                 the close on its own
M_POST=0; M_QUAL=0; M_FAIL=0; M_BOOT=0; M_QUAL_STAGE=""
while IFS=$'\t' read -r dt stage; do
  [[ -n "$dt" ]] || continue
  case "$stage" in bs-token-restaged|bs-token-restage-enabled|bs-token-restage-enable-FAILED) ;; # [mut:arm]
    *) continue ;;
  esac
  postf "$dt" || continue
  M_POST=$((M_POST + 1))
  gen=0
  # The generation test can only run when the anchor resolved — with no
  # current boot id a marker is post-floor evidence of unknown generation:
  # it feeds boot_id_unresolvable below, never a PASS.
  if [[ -n "$CUR_BOOT" && "$CUR_BOOT" != "-" ]]; then
    if [[ -n "$PREV_BOUND" ]]; then
      # Written as `$PREV_BOUND < $dt`, not `$dt > $PREV_BOUND`: a bare `>`
      # in front of "$var" is the operand-not-provably-absolute shape the
      # fixture-relative-assert ratchet scans for (#7708), and the scanner
      # cannot see that `[[ ]]` makes it a comparison.
      [[ "$PREV_BOUND" < "$dt" ]] && gen=1                     # [mut:gen]
    else
      # Empty epoch on ANY unparseable input leaves gen=0 — never a
      # degraded pass on a degenerate (epoch-0) bound.
      e="$(ep "$dt")"
      [[ -n "$e" && -n "$BOOT_LOW_EPOCH" ]] && (( e >= BOOT_LOW_EPOCH - GEN_TOL_S )) && gen=1
    fi
  fi
  (( gen == 1 )) || continue
  case "$stage" in
    bs-token-restage-enabled) M_QUAL=$((M_QUAL + 1)); M_QUAL_STAGE="$stage" ;; # [mut:arm2]
    bs-token-restage-enable-FAILED) M_FAIL=$((M_FAIL + 1)) ;;
    bs-token-restaged) M_BOOT=$((M_BOOT + 1)) ;;
  esac
done <<< "$srows"

# Liveness across ALL legs: any post-floor row of any kind proves the host is
# not pre-replace dark. Stage-leg rows of EVERY stage count for liveness;
# the restage-only filter above is for evidence, not for life.
PF_STAGE=0
while IFS=$'\t' read -r dt stage; do
  [[ -n "$dt" ]] || continue
  postf "$dt" && PF_STAGE=$((PF_STAGE + 1))
done <<< "$srows"
PF_PROBE="$(printf '%s\n' "$prows" | awk -F'\t' -v cut="$MIN_DT_CUT" 'NF >= 2 && $1 != "" && !($1 < cut) { c++ } END { print c + 0 }')"
HAS_POSTFLOOR=$(( J_POST + M_POST + PF_STAGE + PF_PROBE ))

# --- the verdict -------------------------------------------------------------
if (( J_QUAL >= 1 )); then
  printf 'PASS: observed %s ok=1 from SYSLOG_IDENTIFIER=%s host=%s host_name=%s _BOOT_ID=%s (post-floor %s, window %s) pass_arm=journald journald_rows=present — the #7457 allowlist is live on the current host generation; #7596 close evidence.\n' \
    "$MARKER" "$IDENT" "$INNGEST_HOST" "$HOST_NAME" "$CUR_BOOT" "$MIN_DT" "$WINDOW"
  exit 0
fi
if (( M_QUAL >= 1 )); then
  jr="absent"; (( J_POST >= 1 )) && jr="present"
  printf 'PASS: observed SOLEUR_INNGEST_BOOT_STAGE stage=%s marker(s) post-floor %s from host=%s on the direct-curl ingest leg (window %s) pass_arm=boot_stage journald_rows=%s — the replace-bound enable marker is the delivery proof (bs-token-restaged alone is per-boot evidence and never qualifies); the journald leg state rides inside this verdict.\n' \
    "$M_QUAL_STAGE" "$MIN_DT" "$INNGEST_HOST" "$WINDOW" "$jr"
  exit 0
fi
if [[ -z "$CUR_BOOT" || "$CUR_BOOT" == "-" ]]; then
  (( J_POST + M_POST >= 1 )) && transient "reason=boot_id_unresolvable — post-floor restage evidence exists but no inngest-server-probe row carrying _BOOT_ID could be read; refusing a stale-generation close (never a degraded MIN_DT-only PASS)."
  (( HAS_POSTFLOOR >= 1 )) && transient "reason=leg_unit — post-floor activity proves the host lives but zero restage-unit evidence on either leg, and the generation anchor is dark; the unit likely never ran/enabled."
  transient "reason=pre_replace — no post-floor (>= $MIN_DT) evidence of any kind; the inngest-host-replace has not landed or the host emits nothing."
fi
(( J_NOBOOT >= 1 )) && transient "reason=boot_id_unresolvable — $J_NOBOOT post-floor restage row(s) carry no _BOOT_ID against a resolved current boot ($CUR_BOOT); their generation cannot be proven."
if (( J_CURGEN + M_FAIL >= 1 )); then
  transient "reason=restage_not_ok — $((J_CURGEN + M_FAIL)) current-generation restage row(s) on boot $CUR_BOOT but none carries ok=1 / the enabled stage (journald SOLEUR_INNGEST_BS_TOKEN_RESTAGE_FAILED drc= emit(s) or a bs-token-restage-enable-FAILED BOOT_STAGE marker); the unit ran and did not re-stage/enable cleanly."
fi
if (( M_BOOT >= 1 )); then
  transient "reason=delivery_unproven — a current-generation bs-token-restaged marker fired on boot $CUR_BOOT (the per-boot restage ran) but no same-generation bs-token-restage-enabled marker arrived; restaged is boot evidence only — the enabled marker is the replace-bound delivery proof, so a plain post-floor reboot can never satisfy the close on its own."
fi
if (( HAS_POSTFLOOR >= 1 )); then
  transient "reason=leg_unit — post-floor activity proves the host lives ($HAS_POSTFLOOR row(s) across legs) but zero restage-unit evidence in the current generation ($CUR_BOOT); the unit likely never ran/enabled — the emit leg, not the allowlist leg, is the suspect."
fi
transient "reason=pre_replace — no post-floor (>= $MIN_DT) evidence of any kind across the journald, server-probe and BOOT_STAGE legs; expected until the next inngest-host-replace lands."
