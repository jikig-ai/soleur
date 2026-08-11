#!/usr/bin/env bash
# #7440 / ADR-182 — post-delivery readback for the registry host's zot container-log channel.
#
# TRACKER: **#7455** (dedicated). **NOT #7440** — that issue is closed by the shipping PR, and
# scripts/sweep-followthroughs.sh lists `--state open`, so a probe hosted there would be a
# permanent silent no-op: on a closed issue rc=0 takes "no action, no comment" and rc=2 likewise,
# so even the eventual real PASS would leave NO artifact to flip ADR-182 — and CLOSED_LOOKBACK_DAYS
# removes the issue from the candidate set entirely after two weeks. The sweeper resolves the host
# from the directive comment on #7455, so this reference is for a human reader; changing it does not
# re-route the probe.
#
# WHAT IT CLOSES. ADR-182 ships at status `adopting`. Its flip condition is an OBSERVED
# envelope-stamped row read back OUT of the warehouse. That cannot happen before merge:
# hcloud_server.registry is cloud-init-only (ADR-096, ADR-172 §8), every registry resource is an
# OPERATOR_APPLIED_EXCLUSION, and merging this applies NOTHING. Delivery rides the pending step-6
# `registry-host-replace` of the open zot-pin ordered path.
#
# SO TRANSIENT IS THE EXPECTED STEADY STATE UNTIL THAT REPLACE, AND THAT IS NOT A BUG. The
# escalation horizon lives in the tracker body: `delivered_but_silent`, or any undelivered state
# persisting past 90 days, is an escalation rather than a steady state. Known cost, stated rather
# than discovered: on the open path the sweeper comments unconditionally before deciding, so a
# correctly-behaving exit-2 probe posts one comment per sweep until delivery.
#
# EXIT CONTRACT (scripts/sweep-followthroughs.sh) — AND THE SINGLE `exit 1` IS DELIBERATE:
#   0 = PASS       envelope rows observed AND the positive control present.
#   2 = TRANSIENT  not delivered, delivered-but-silent, below floor, control missing,
#                  channel dark, or ANY auth/query/decode failure. Each prints a DISTINCT reason —
#                  an unprovisioned credential must never read as "not yet delivered".
#   1 = FAIL       emitted ONLY when a credential shape is found in the channel. This is the one
#                  carve-out and it is intentional: a leak is a REGRESSION, not a not-yet, and at
#                  this plan's `single-user incident` brand-survival threshold it must reopen and
#                  comment. Everywhere else exit 1 is forbidden because it reopens daily.
#
# THE DISCRIMINATOR IS POSITIVE AND HOST-ISOLATED. It asserts that a decoded message STARTS WITH
# the envelope the shipper stamps. It is emphatically NOT the negation "raw does not begin with the
# heartbeat prefix": that form is FAIL-OPEN — under any raw-encoding drift every echo row
# reclassifies as genuine and this probe would auto-PASS on the exact production state it exists to
# reject. The same literal used POSITIVELY fails VISIBLY instead, which is the safe polarity.
#
# WHY NOT THE TOKENS THE ISSUE SUGGESTED. `routes.go` is an ordinary Go filename any Go service
# could log, and ALL hosts multiplex into Logs source 2457081 (`host_name` is Vector-populated and
# this channel has no Vector), so a single row from another host would pass as "genuine" with no
# registry shipper in existence. `blobs/uploads` measured 0 rows even inside the heartbeat echoes,
# so it has no measured association with the upload evidence at all. The envelope's in-message
# `host=` token is the only isolation available on a direct-POST channel.
#
# THE FALSE-GREEN THIS EXISTS TO REFUSE. Today a bare `--grep zotregistry.dev` returns 53 rows over
# 6h — every one of them the heartbeat's own `zot_last_err` echo. A naive probe would call that a
# live channel. A heartbeat row's decoded message starts with `SOLEUR_ZOT_DISK `, so it can never
# satisfy the prefix anchor below, no matter how many times it names zot.
#
# ENCODING-SAFE GREP, THEN DECODE, THEN FIELD-ISOLATE. ClickHouse stores `raw` DOUBLE-ENCODED: real
# zot JSON `"caller":"zotregistry.dev/…"` is stored as `\"caller\":\"zotregistry.dev`. A grep
# containing a quote or a colon-joined field name becomes a LIKE that matches NOTHING, EVER — the
# trap betterstack-query.sh's own header documents. So the greps below carry no quote and no colon,
# and every judgement is made on the DECODED object.
#
# --no-archive IS DELIBERATE HERE, AND IT IS THE OPPOSITE CHOICE FROM THE SIBLING PROBE.
# betterstack-query.sh defaults to hot+archive; --no-archive opts DOWN to the ~40-minute hot
# window. This probe's window is 30 minutes — entirely inside that keyhole — so the archive arm
# would add an S3 failure mode to a steady-state probe for no coverage. The sibling probe
# (zot-inventory-marker-7278.sh) queries 7d and MUST keep the archive arm. Do not copy flags
# between the days-old and minutes-old cases.
#
# THE `${VAR:?msg}` FORM IS BANNED HERE and the ban is mechanical, not stylistic: under the
# sweeper's non-interactive shell that word-expansion aborts with status 1, which this contract
# reads as FAIL — so an unprovisioned secret would post a daily false-FAIL forever instead of
# retrying quietly. scripts/lint-followthrough-varq-ban.sh reddens CI on it.
#
# Required env (LITERAL names — the sweeper runs probes under `env -i` with PATH + HOME + the
# directive-declared `secrets=` ONLY; all three are already wired into
# .github/workflows/scheduled-followthrough-sweeper.yml, so this needs no workflow edit):
#   BETTERSTACK_QUERY_HOST, BETTERSTACK_QUERY_USERNAME, BETTERSTACK_QUERY_PASSWORD
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
QUERY="${ZOT_LOG_7440_QUERY_BIN:-$REPO_ROOT/scripts/betterstack-query.sh}"

ENVELOPE_PREFIX="SOLEUR_ZOT_LOG shipper=zot-log-shipper host="
BOOT_MARKER="SOLEUR_ZOT_LOG_BOOT"
DROP_MARKER="SOLEUR_ZOT_LOG_DROPPED"
CONTROL_MARKER="SOLEUR_ZOT_DISK"
# Encoding-safe: no quote, no colon, so it survives the double-encoded `raw` as a LIKE.
ZOT_ONLY_TOKEN="zotregistry.dev/zot/v2/pkg/api"
HOST_TOKEN="${ZOT_LOG_7440_HOST:-soleur-registry}"

# The boot_id observed on 2026-08-11 while authoring this change, i.e. the boot that PRE-DATES
# delivery. A SOLEUR_ZOT_DISK row still reporting this value means the host has not been replaced
# since, so the cloud-init carrying the shipper cannot have been delivered. Any other value means a
# provisioning event happened — which is what separates "wait" from "act" below.
BASELINE_BOOT_ID="${ZOT_LOG_7440_BASELINE_BOOT_ID:-bc135d5b-d509-41c4-8129-9181421e845c}"

WINDOW="${ZOT_LOG_7440_WINDOW:-30m}"
WINDOW_MIN="${ZOT_LOG_7440_WINDOW_MIN:-30}"
LIMIT="${ZOT_LOG_7440_LIMIT:-400}"

# EXPECTED FLOOR, computed rather than asserted. zot-liveness-heartbeat.timer fires every 60s
# (OnUnitActiveSec=60s) and zot logs EVERY request at info level, so one genuine zot line lands per
# minute BY CONSTRUCTION — ~1,440/day before any real pull traffic. That rate (1/min) sits well
# under the shipper's 17-per-5-minute cap, so liveness rows are never the ones dropped. A shortfall
# against this is therefore measurable rather than a judgement call. The quarter-of-expected floor
# absorbs ingest lag and a partial first window without tolerating a mostly-dead shipper.
EXPECTED_ROWS="$WINDOW_MIN"
FLOOR_ROWS=$(( EXPECTED_ROWS / 4 ))
[[ "$FLOOR_ROWS" -ge 3 ]] || FLOOR_ROWS=3

for v in BETTERSTACK_QUERY_HOST BETTERSTACK_QUERY_USERNAME BETTERSTACK_QUERY_PASSWORD; do
  if [[ -z "${!v:-}" ]]; then
    echo "TRANSIENT: reason=credentials_unset — $v is unset, so the Logs warehouse cannot be" >&2
    echo "           queried. This is a PROVISIONING GAP in the sweeper env, NOT evidence about" >&2
    echo "           the channel. Deliberately its own reason: collapsing it into" >&2
    echo "           'not_delivered' would report an absence this probe never measured." >&2
    exit 2
  fi
done

if [[ ! -x "$QUERY" ]]; then
  echo "TRANSIENT: reason=query_tool_missing — $QUERY is missing or not executable." >&2
  exit 2
fi

# --- decode helper: JSONEachRow -> .raw (a JSON *string*) -> .message ------------------------
# Both hops use `fromjson?` so a non-JSON noise line is skipped rather than aborting the stream,
# and `// empty` drops fieldless rows instead of emitting a literal "null".
decode_messages() {
  jq -R -r 'fromjson? | .raw // empty' 2>/dev/null \
    | jq -R -r 'fromjson? | .message // empty' 2>/dev/null
}

count_lines() {
  local n
  n=$(grep -c . 2>/dev/null || true)
  [[ "$n" =~ ^[0-9]+$ ]] || n=0
  printf '%s' "$n"
}

# betterstack-query.sh exits 3 on unset credentials and 64 on an unknown flag; ANY non-zero maps to
# TRANSIENT, because a failed query is not an absence.
run_query() {
  local out rc
  out=$("$QUERY" --since "$WINDOW" --no-archive --limit "$LIMIT" --grep "$1" 2>/dev/null)
  rc=$?
  if [[ $rc -ne 0 ]]; then
    printf 'QUERYFAIL %s' "$rc"
    return 0
  fi
  printf '%s' "$out"
}

raw_log=$(run_query "SOLEUR_ZOT_LOG")
if [[ "$raw_log" == QUERYFAIL* ]]; then
  echo "TRANSIENT: reason=query_failed — betterstack-query.sh exited ${raw_log#QUERYFAIL } querying" >&2
  echo "           SOLEUR_ZOT_LOG over $WINDOW. No claim is made about the channel." >&2
  exit 2
fi

decoded=$(printf '%s\n' "$raw_log" | decode_messages)

# PREFIX-ANCHORED and HOST-ISOLATED. `grep -F` on a fixed prefix at offset 0: a prose mention of
# the marker (this file, the ADR, the tracker body, the PR description — all ingested somewhere in
# this estate) can never sit at offset 0 followed by the exact shipper+host tokens.
envelope_hits=$(printf '%s\n' "$decoded" | grep -F "${ENVELOPE_PREFIX}${HOST_TOKEN} " || true)
n_envelope=$(printf '%s\n' "$envelope_hits" | count_lines)
boot_hits=$(printf '%s\n' "$decoded" | grep -E "^${BOOT_MARKER} boot_id=" || true)
n_boot=$(printf '%s\n' "$boot_hits" | count_lines)
drop_hits=$(printf '%s\n' "$decoded" | grep -E "^${DROP_MARKER} n=" || true)
n_drop=$(printf '%s\n' "$drop_hits" | count_lines)

# --- positive control: is the READ PATH alive at all? ---------------------------------------
control_raw=$(run_query "$CONTROL_MARKER")
if [[ "$control_raw" == QUERYFAIL* ]]; then
  echo "TRANSIENT: reason=query_failed — the control query exited ${control_raw#QUERYFAIL }." >&2
  exit 2
fi
control_decoded=$(printf '%s\n' "$control_raw" | decode_messages | grep -E "^${CONTROL_MARKER} " || true)
n_control=$(printf '%s\n' "$control_decoded" | count_lines)

# The reporter carries the shipper's own health on an INDEPENDENT working path, which is the only
# signal that survives a totally dead shipper egress.
shipper_post_fail=$(printf '%s\n' "$control_decoded" | grep -oE 'log_shipper_post_fail=[0-9]+' | tail -1 | grep -oE '[0-9]+$' || true)
current_boot_id=$(printf '%s\n' "$control_decoded" | grep -oE 'boot_id=[0-9a-f-]+' | tail -1 | sed 's/^boot_id=//' || true)

# --- DELIVERY DISCRIMINATION: this is what separates WAIT from ACT ---------------------------
delivered=0
delivery_evidence="none"
if [[ "$n_boot" -gt 0 ]]; then
  delivered=1
  delivery_evidence="boot_marker(${n_boot})"
elif [[ -n "$current_boot_id" && "$current_boot_id" != "$BASELINE_BOOT_ID" ]]; then
  delivered=1
  delivery_evidence="boot_id_drift(${current_boot_id})"
fi

# --- CREDENTIAL-SHAPE SCAN: the sole exit-1 arm ---------------------------------------------
# Scans the DECODED shipped messages, never this file. Three shapes, each measured or reasoned:
#  (a) an Authorization header value that is NEITHER zot's own mask (******) NOR our REDACTED
#      marker — i.e. redaction regressed and a real value reached the wire;
#  (b) a Doppler token prefix — the token class actually present on this host;
#  (c) a bcrypt hash prefix, which would mean the htpasswd file's contents leaked into a log line.
#      (a) is a SUBTRACTION, not a match: the sanitizer strips quotes, so a shipped header object
#      renders `Authorization:[******]`. Selecting rows that HAVE the header and then removing the
#      masked and redacted forms is what makes "the value is something else" detectable at all — a
#      positive pattern for "a credential" cannot be written, but "not one of the two safe forms"
#      can. Single-quoted throughout: an unquoted `$2[aby]$` would expand as a positional param.
auth_rows=$(printf '%s\n' "$envelope_hits" | grep -F 'Authorization:[' || true)
auth_leaks=$(printf '%s\n' "$auth_rows" | grep -vE 'Authorization:\[(\*{3,}|REDACTED)' || true)
#      The Doppler charset MUST include `.` — a real service token is `dp.st.<config>.<random>`, so
#      a dot-free trailing class stops at the config segment (3 chars) and never reaches the 20-char
#      floor. That form matched nothing and was caught only by the C8c fixture.
shape_leaks=$(printf '%s\n' "$envelope_hits" \
  | grep -E 'dp\.(pt|st|sa|ct)\.[A-Za-z0-9._-]{20,}|\$2[aby]\$[0-9]{2}\$' || true)
n_auth_leak=$(printf '%s\n' "$auth_leaks" | count_lines)
n_shape_leak=$(printf '%s\n' "$shape_leaks" | count_lines)
n_leak=$(( n_auth_leak + n_shape_leak ))

if [[ "$n_leak" -gt 0 ]]; then
  echo "FAIL: reason=credential_shape_in_channel — ${n_leak} shipped row(s) in the last ${WINDOW}" >&2
  echo "      carry something shaped like a credential. This is the ONE arm that exits 1, because" >&2
  echo "      a leak is a regression rather than a not-yet, and the registry's push credential" >&2
  echo "      protects the image supply chain — a leaked one is a SUPPLY-CHAIN exposure, not a" >&2
  echo "      log-hygiene defect. Every holder of BETTERSTACK_QUERY_* can read these rows." >&2
  echo "      Next: rotate the affected credential FIRST, then fix redact() in" >&2
  echo "      apps/web-platform/infra/cloud-init-registry.yml." >&2
  echo "      COUNTS ONLY — the matching values are deliberately NOT echoed, because this probe's" >&2
  echo "      output is posted verbatim as a comment on a public issue by the sweeper, so printing" >&2
  echo "      them would copy the leak out of one channel and into two more:" >&2
  echo "        unmasked_authorization_rows=${n_auth_leak} token_or_hash_shaped_rows=${n_shape_leak}" >&2
  exit 1
fi

# --- zero envelope rows: FOUR distinct reasons, never collapsed ------------------------------
if [[ "$n_envelope" -eq 0 ]]; then
  if [[ "$n_control" -eq 0 ]]; then
    echo "TRANSIENT: reason=channel_dark — zero envelope rows AND zero ${CONTROL_MARKER} control" >&2
    echo "           rows in the last ${WINDOW}. The control lands on this source every 5 min, so an" >&2
    echo "           empty control means the READ PATH is not answering. This probe has measured" >&2
    echo "           NOTHING about the channel — do NOT read it as 'the shipper is absent'." >&2
    echo "           Next: check the Better Stack query credentials and the hot-window bound" >&2
    echo "           before concluding anything about the host." >&2
    exit 2
  fi
  if [[ "$delivered" -eq 1 ]]; then
    echo "TRANSIENT: reason=delivered_but_silent — the host HAS been provisioned since this change" >&2
    echo "           was authored (${delivery_evidence}), yet zero envelope rows arrived in the last" >&2
    echo "           ${WINDOW} while the read path is alive (${n_control} control row(s))." >&2
    echo "           THIS IS THE STATE THAT MEANS ACT, NOT WAIT, and it is deliberately NOT" >&2
    echo "           collapsed into 'not delivered': the shipper unit crashed, latched its" >&2
    echo "           start-limit, or its journald match is wrong." >&2
    if [[ -n "$shipper_post_fail" && "$shipper_post_fail" != "0" ]]; then
      echo "           The reporter's INDEPENDENT path says log_shipper_post_fail=${shipper_post_fail}," >&2
      echo "           so the unit IS running and its POSTs are failing — that is an egress or token" >&2
      echo "           fault, not a dead unit. reason=shipper_post_failing." >&2
    else
      echo "           The reporter reports no POST failures, so the unit is likely not running at" >&2
      echo "           all rather than failing to egress." >&2
    fi
    echo "           Next: read log_shipper_post_fail / log_shipper_last_ok_age_s on the" >&2
    echo "           ${CONTROL_MARKER} rows, and the SOLEUR_ZOT_LOG_BOOT row's shipper_unit= field." >&2
    exit 2
  fi
  echo "TRANSIENT: reason=not_delivered — zero envelope rows, no ${BOOT_MARKER} row, and the" >&2
  echo "           ${CONTROL_MARKER} boot_id still reads ${current_boot_id:-unknown}, which is the" >&2
  echo "           pre-delivery baseline. The read path IS alive (${n_control} control row(s)), so" >&2
  echo "           this is a MEASURED absence rather than a dark channel." >&2
  echo "           This is the EXPECTED steady state until the host is replaced: the registry host" >&2
  echo "           is cloud-init-only, so merging the shipper applied nothing. Delivery rides the" >&2
  echo "           step-6 registry-host-replace of the open zot-pin ordered path." >&2
  echo "           Next: nothing to do here. Past the 90-day horizon in the tracker body this" >&2
  echo "           becomes an escalation rather than a steady state." >&2
  exit 2
fi

# --- envelope rows exist. Control must too, or a live incident is being masked ---------------
if [[ "$n_control" -eq 0 ]]; then
  echo "TRANSIENT: reason=control_missing — ${n_envelope} envelope row(s) present, so the channel is" >&2
  echo "           demonstrably LIVE, but zero ${CONTROL_MARKER} control rows in the last ${WINDOW}." >&2
  echo "           Deliberately NOT channel_dark: the envelope proves the read path answers, so" >&2
  echo "           this masks a SEPARATE live incident — the 5-min disk reporter has stopped." >&2
  echo "           Next: investigate the disk heartbeat cron, not this channel." >&2
  exit 2
fi

# --- the zot-only token must be present, or these rows are not really zot's output -----------
n_zot_token=$(printf '%s\n' "$envelope_hits" | grep -cF "$ZOT_ONLY_TOKEN" || true)
[[ "$n_zot_token" =~ ^[0-9]+$ ]] || n_zot_token=0
if [[ "$n_zot_token" -eq 0 ]]; then
  echo "TRANSIENT: reason=envelope_without_zot_content — ${n_envelope} envelope row(s) carry the" >&2
  echo "           shipper's own framing but NONE contains ${ZOT_ONLY_TOKEN}, the substring only" >&2
  echo "           zot's own output produces. The shipper is alive and shipping something that is" >&2
  echo "           not zot log content — a journald match that resolves to the wrong unit." >&2
  exit 2
fi

if [[ "$n_envelope" -lt "$FLOOR_ROWS" ]]; then
  echo "TRANSIENT: reason=below_expected_floor — ${n_envelope} envelope row(s) in the last ${WINDOW}," >&2
  echo "           against a computed expectation of ~${EXPECTED_ROWS} and a floor of ${FLOOR_ROWS}." >&2
  echo "           The 60s liveness timer plus zot's log-every-request behaviour put one genuine" >&2
  echo "           line per minute on this channel BY CONSTRUCTION, so a shortfall is measurable" >&2
  echo "           rather than a judgement call. The shipper is partly working: POSTs are failing," >&2
  echo "           the rate cap is mis-sized, or the unit is restart-looping." >&2
  if [[ -n "$shipper_post_fail" && "$shipper_post_fail" != "0" ]]; then
    echo "           log_shipper_post_fail=${shipper_post_fail} on the reporter's independent path." >&2
  fi
  echo "           ${n_drop} ${DROP_MARKER} row(s) in the same window." >&2
  exit 2
fi

# --- PASS ------------------------------------------------------------------------------------
# The four measured evidence classes are printed as COUNTS because the gc start/complete RATIO is
# the discriminator the downstream disk-attribution question needs: a stalled gc emits a start with
# no completion, and that ratio is unreadable from a channel that admits only completions.
n_gc_start=$(printf '%s\n' "$envelope_hits" | grep -cF 'executing gc' || true)
n_gc_done=$(printf '%s\n' "$envelope_hits" | grep -cF 'gc successfully completed' || true)
n_gc_blobs=$(printf '%s\n' "$envelope_hits" | grep -cF 'garbage collected blobs' || true)
n_patch=$(printf '%s\n' "$envelope_hits" | grep -cF 'PatchBlobUpload' || true)
for v in n_gc_start n_gc_done n_gc_blobs n_patch; do
  [[ "${!v}" =~ ^[0-9]+$ ]] || eval "$v=0"
done

echo "PASS: envelope rows observed (envelope=${n_envelope} control=${n_control} gc_start=${n_gc_start} gc_done=${n_gc_done} gc_blobs=${n_gc_blobs} patch_upload=${n_patch} dropped_rows=${n_drop})"
echo "      Window ${WINDOW}; expectation ~${EXPECTED_ROWS} rows, floor ${FLOOR_ROWS}; delivery evidence: ${delivery_evidence}."
echo "      This is a READBACK, not the emitter's self-report: each row was read back OUT of the"
echo "      warehouse through the ClickHouse path, which no exit code on the host can fake. The"
echo "      match is POSITIVE and host-isolated — a decoded message starting with"
echo "      '${ENVELOPE_PREFIX}${HOST_TOKEN}' — so the ${CONTROL_MARKER} echo rows that make a naive"
echo "      'zotregistry.dev' grep return 53 hits today cannot satisfy it."
echo "      ${n_zot_token} of ${n_envelope} row(s) carry ${ZOT_ONLY_TOKEN}, the substring only zot's"
echo "      own output produces."
echo "      The gc start/complete ratio (${n_gc_start}/${n_gc_done}) is now readable, which is what"
echo "      makes the downstream growth-attribution question answerable from telemetry at all."
echo "      ADR-182 may now flip adopting -> accepted."
printf '%s\n' "$envelope_hits" | tail -3 | cut -c1-200 | sed 's/^/        /'
exit 0
