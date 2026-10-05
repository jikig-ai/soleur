#!/usr/bin/env bash
# #7440 / ADR-184 — post-delivery readback for the registry host's zot container-log channel.
#
# TRACKER: **#7455** (dedicated). **NOT #7440** — that issue is closed by the shipping PR, and
# scripts/sweep-followthroughs.sh lists `--state open`, so a probe hosted there would be a
# permanent silent no-op: on a closed issue rc=0 takes "no action, no comment" and rc=2 likewise,
# so even the eventual real PASS would leave NO artifact to flip ADR-184 — and CLOSED_LOOKBACK_DAYS
# removes the issue from the candidate set entirely after two weeks. The sweeper resolves the host
# from the directive comment on #7455, so this reference is for a human reader; changing it does not
# re-route the probe.
#
# STATUS AS OF 2026-08-12 (#7455): CLOSED. The condition below was met — first PASS 21:03:51Z, and
# ADR-184 is now `accepted`. This probe stays enrolled as a REGRESSION detector: a future replace
# can legitimately return the channel to not-delivered, and the arms below must keep working.
# Everything from here to the exit contract is the ORIGINAL pre-delivery framing, kept because the
# arms are still live; read it as history, not as current state.
#
# WHAT IT CLOSED. ADR-184 shipped at status `adopting`. Its flip condition is an OBSERVED
# envelope-stamped row read back OUT of the warehouse. That cannot happen before merge:
# hcloud_server.registry is cloud-init-only (ADR-096, ADR-172 §8), every registry resource is an
# OPERATOR_APPLIED_EXCLUSION, and merging this applied NOTHING.
#
# DELIVERY LANDED, AND THE MECHANISM IS WORTH RECORDING because the pending-forever framing this
# header carried was retired by an event nobody scheduled. The zot-pin ordered path closed
# 2026-08-12T20:39Z WITHOUT firing its step-6 `registry-host-replace` — the atomic 3-way recut had
# already replaced the host on 08-10, two days BEFORE the shipper merged, so the shipper missed that
# window and sat inert. A separate `registry_host_replace` dispatch (run 31639782781) succeeded at
# 20:54:12Z, and the channel has read PASS since. So a TRANSIENT now means a REGRESSION — do not
# discount one on the strength of the pre-delivery paragraphs above — and `not_delivered`
# specifically means a host is running cloud-init older than the shipper, which is a provisioning
# question rather than a wait.
#
# The escalation horizon lives in the tracker body: `delivered_but_silent`, or any undelivered state
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

# NOTE: the pre-delivery boot_id baseline that used to live here is GONE (#7444 R20). F-7
# replaced boot_id drift with the presence of the log_shipper_post_fail= key as the delivery
# discriminator, which left the constant dead — and a dead constant with five lines of rationale
# describing it as the wait/act discriminator reads as though it were still load-bearing.

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
# THE FAILURE MESSAGE TRAVELS ON STDOUT, and that is forced rather than stylistic: every caller
# is `x=$(run_query ...)`, a COMMAND SUBSTITUTION, so the function runs in a SUBSHELL and any
# global it assigns is discarded in the parent. A `QUERY_LAST_ERR` global here reports empty at
# every call site — measured, and caught by C3j.
#
# `2>/dev/null` previously destroyed the LIKELIEST first-run failure: an unprovisioned secret
# resolves to "", the sweeper still forwards it (it tests for SET, not non-empty),
# betterstack-query.sh exits 3 with an actionable "credentials not injected" message — and the
# operator's issue comment said only "exited 3". The sibling probe already learned this
# (zot-fill-rate-7341.sh keeps stderr and bounds it with `head -c 600`).
#
# BOUNDED, and the bound is not cosmetic: the sweeper posts this stdout VERBATIM into a comment on
# a PUBLIC issue. The trailing space after %s keeps the rc field splittable when the message is
# empty, so `${rest%% *}` is always exactly the rc.
# ONE owning trap for the whole script (ADR-129 rule (c)). The stderr capture below cannot own its
# own cleanup: run_query is called as `x=$(run_query ...)`, i.e. in a SUBSHELL, so a trap declared
# inside it would fire on the subshell's exit and a bare `rm -f` leaks whenever the script dies
# between mktemp and cleanup. Hoisting the tempfile to script scope gives it a single owner in the
# parent. The two callers are sequential, never concurrent, so reuse is safe.
QERR="$(mktemp)" || { echo "TRANSIENT: mktemp failed — no query attempted" >&2; exit 2; }
trap 'rm -f "$QERR"' EXIT INT TERM

run_query() {
  local out rc msg
  out=$("$QUERY" --since "$WINDOW" --no-archive --limit "$LIMIT" --grep "$1" 2>"$QERR")
  rc=$?
  if [[ $rc -ne 0 ]]; then
    msg="$(head -c 400 "$QERR" | tr '\n\r\t' '   ')"
    printf 'QUERYFAIL %s %s' "$rc" "$msg"
    return 0
  fi
  printf '%s' "$out"
}

# Split a QUERYFAIL payload into its rc and its bounded stderr.
queryfail_rc()  { local r="${1#QUERYFAIL }"; printf '%s' "${r%% *}"; }
queryfail_msg() { local r="${1#QUERYFAIL }"; [[ "$r" == *" "* ]] && printf '%s' "${r#* }"; }

raw_log=$(run_query "SOLEUR_ZOT_LOG")
if [[ "$raw_log" == QUERYFAIL* ]]; then
  echo "TRANSIENT: reason=query_failed — betterstack-query.sh exited $(queryfail_rc "$raw_log") querying" >&2
  [[ -n "$(queryfail_msg "$raw_log")" ]] && echo "           $(queryfail_msg "$raw_log")" >&2
  echo "           SOLEUR_ZOT_LOG over $WINDOW. No claim is made about the channel." >&2
  exit 2
fi

decoded=$(printf '%s\n' "$raw_log" | decode_messages)

# PREFIX-ANCHORED and HOST-ISOLATED — and the anchor is `grep -E "^…"`, not `grep -F` (#7444
# R18). `grep -F` has NO anchor, so the comment that used to sit here claiming "a fixed prefix at
# offset 0 … can never sit at offset 0" described a property the code did not have. Measured: a
# warehouse row that merely MENTIONS the envelope mid-line satisfied it, and 30 such rows clear
# FLOOR_ROWS and exit 0 — auto-flipping ADR-184 to accepted on prose. The three sibling marker
# greps below were anchored all along, which is what made this read as an omission.
#
# The prefix contains no ERE metacharacter, so -E changes nothing except adding the anchor.
envelope_hits=$(printf '%s\n' "$decoded" | grep -E "^${ENVELOPE_PREFIX}${HOST_TOKEN} " || true)
n_envelope=$(printf '%s\n' "$envelope_hits" | count_lines)
# THE BOOT MARKER NEEDS ITS OWN WINDOW (#7444 R32). It fires ONCE, from runcmd, at provision
# time — but it was being read out of $decoded, i.e. the 30-minute `--no-archive` hot-window
# query sized for the steady envelope stream. So `n_boot > 0` was true only if a sweep happened
# to run within ~30 minutes of a host replace, and false for the rest of that host's life.
# That made the ONE field that breaks the four-way `post_fail=unknown` collapse unreadable in
# practice. Queried separately at 72h WITH the archive arm, which is the window its cadence
# actually needs; past the source's 3-day retention it is gone permanently, which the arms below
# say rather than implying the absence is evidence.
boot_raw=$(BOOT_WINDOW=72h; "$QUERY" --since 72h --limit "$LIMIT" --grep "$BOOT_MARKER" 2>/dev/null || printf '')
boot_hits=$(printf '%s\n' "$boot_raw" | decode_messages | grep -E "^${BOOT_MARKER} boot_id=[0-9a-f-]+ host=${HOST_TOKEN}( |$)" || true)
n_boot=$(printf '%s\n' "$boot_hits" | count_lines)
drop_hits=$(printf '%s\n' "$decoded" | grep -E "^${DROP_MARKER} n=" || true)
n_drop=$(printf '%s\n' "$drop_hits" | count_lines)

# --- positive control: is the READ PATH alive at all? ---------------------------------------
control_raw=$(run_query "$CONTROL_MARKER")
if [[ "$control_raw" == QUERYFAIL* ]]; then
  echo "TRANSIENT: reason=query_failed — the control query exited $(queryfail_rc "$control_raw")." >&2
  [[ -n "$(queryfail_msg "$control_raw")" ]] && echo "           $(queryfail_msg "$control_raw")" >&2
  exit 2
fi
control_decoded=$(printf '%s\n' "$control_raw" | decode_messages | grep -E "^${CONTROL_MARKER} " || true)
n_control=$(printf '%s\n' "$control_decoded" | count_lines)

# The reporter carries the shipper's own health on an INDEPENDENT working path, which is the only
# signal that survives a totally dead shipper egress.
# `[0-9]+` alone cannot match the reporter's `unknown` DEFAULT, which is what it emits when the
# shipper's state file is unreadable — so an unset value silently read as "no POST failures", an
# absence the probe never measured. Captured as its own sub-state instead.
shipper_post_fail_raw=$(printf '%s\n' "$control_decoded" | grep -oE 'log_shipper_post_fail=[^ ]+' | tail -1 | sed 's/^log_shipper_post_fail=//' || true)
shipper_post_fail=""
shipper_post_fail_unknown=0
case "$shipper_post_fail_raw" in
  '')           : ;;                                   # field absent entirely (old cloud-init)
  *[!0-9]*)     shipper_post_fail_unknown=1 ;;         # `unknown` — state file unreadable
  *)            shipper_post_fail=$shipper_post_fail_raw ;;
esac
current_boot_id=$(printf '%s\n' "$control_decoded" | grep -oE 'boot_id=[0-9a-f-]+' | tail -1 | sed 's/^boot_id=//' || true)
# The reporter carries three more shipper fields on this same row and the probe held them all
# while telling the operator to go re-run the query it had just run (#7444 R19). last_ok_age_s in
# particular decides between the two hypotheses `delivered_but_silent` otherwise only guesses at:
# -1 means no row has EVER shipped, while a small age with zero envelope rows means the shipper
# works and the envelope/grep drifted.
shipper_last_ok_age=$(printf '%s\n' "$control_decoded" | grep -oE 'log_shipper_last_ok_age_s=-?[0-9]+' | tail -1 | sed 's/^log_shipper_last_ok_age_s=//' || true)
shipper_dropped_cum=$(printf '%s\n' "$control_decoded" | grep -oE 'log_shipper_dropped_cum=[^ ]+' | tail -1 | sed 's/^log_shipper_dropped_cum=//' || true)
shipper_drop_seq=$(printf '%s\n' "$control_decoded" | grep -oE 'log_shipper_drop_seq=[^ ]+' | tail -1 | sed 's/^log_shipper_drop_seq=//' || true)

# --- DELIVERY DISCRIMINATION: this is what separates WAIT from ACT ---------------------------
# GATED ON A KEY THAT ONLY THE NEW CLOUD-INIT CAN PRODUCE (#7444 F-7), never on boot_id drift.
#
# boot_id drift is NOT a provisioning event on this host. The private-NIC guard calls `reboot` as
# a convergence primitive, and cloud-init's `runcmd` is per-instance, so a plain reboot of the
# CURRENT, UN-REPLACED host flips boot_id without delivering anything. Reproduced: that drift
# alone flipped delivered=1 -> reason=delivered_but_silent -> "ACT, NOT WAIT", starting the 90-day
# escalation clock against a host that was never replaced.
#
# `log_shipper_post_fail=` exists only in the reporter shipped BY this change, so its presence on
# a control row is positive proof the new cloud-init ran — and its ABSENCE proves the opposite,
# regardless of how many times the host has rebooted. The boot marker remains the primary
# evidence; this is the fallback that replaces the drift heuristic.
delivered=0
delivery_evidence="none"
if [[ "$n_boot" -gt 0 ]]; then
  delivered=1
  delivery_evidence="boot_marker(${n_boot})"
elif [[ -n "$shipper_post_fail_raw" ]]; then
  delivered=1
  delivery_evidence="reporter_carries_shipper_fields(log_shipper_post_fail=${shipper_post_fail_raw})"
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
    # FIRST-TICK SOFTENING, GATED ON THE LITERAL -1 (#7456). The shipper is a 4-59/5 cron one-shot,
    # so between a host's birth and its first tick this arm was firing "ACT, NOT WAIT" at a host
    # that had simply never run one. Measured 2026-08-12: replaced 20:54:12Z, this arm at 20:56:32Z,
    # unassisted PASS at 20:58:45Z. The discriminator is the reporter's OWN last_ok_age_s, so no
    # clock is introduced — this probe reads none, decode_messages drops dt, and the boot marker
    # carries no timestamp. The test MUST be the literal "-1", never emptiness: the pre-delivery
    # reporter emits no log_shipper_* fields at all, and softening on absence would weaken the
    # genuine escalation that case pins (C3g).
    # THE ACT FRAMING IS NEVER SUPPRESSED. An earlier revision replaced it with a reassuring
    # "expected until its first tick" whenever last_ok_age_s was the literal -1. That is unsafe and
    # NOT FIXABLE ON THIS ROW: -1 is the reporter's DEFAULT on an unreadable state file, so a host
    # born four minutes ago and a host whose shipper died a week ago (jq off PATH -> exit 1 -> state
    # never written) emit an identical `post_fail=unknown last_ok_age_s=-1` pair. The obvious
    # discriminator is wrong too — zot_uptime_s is the zot CONTAINER's current-run age, not host
    # age, so under the restart loop this channel exists to diagnose it is permanently small and
    # would soften forever on the exact incident that matters. No field here carries host age, and
    # adding one costs a provisioning event on the sole image-pull path.
    #
    # So the first-tick case is served ADDITIVELY: the escalation still reads ACT, and a young host
    # gets an extra line telling the operator what to check. Fail-safe direction — a freshly
    # replaced host costs one re-run, a dead shipper still escalates.
    echo "           THIS IS THE STATE THAT MEANS ACT, NOT WAIT, and it is deliberately NOT" >&2
    echo "           collapsed into 'not delivered': the shipper's cron tick is failing, its" >&2
    echo "           journald match is wrong, or jq is missing on the host." >&2
    if [[ "${shipper_last_ok_age:-}" == "-1" ]]; then
      echo "           BEFORE ACTING, rule out a first tick: last_ok_age_s=-1 means no row has EVER" >&2
      echo "           shipped, which is also the state of a host replaced minutes ago — the shipper" >&2
      echo "           is a 4-59/5 cron one-shot. Measured 2026-08-12: a host born 20:54:12Z read" >&2
      echo "           silent at 20:56 and PASSed at 20:58 with no intervention. If this host was" >&2
      echo "           just replaced, re-run after the next 5-minute boundary. If it has been up" >&2
      echo "           longer than that, -1 is a DEAD shipper and the arms below name the cause." >&2
    fi
    if [[ "$shipper_post_fail_unknown" -eq 1 ]]; then
      echo "           The reporter says log_shipper_post_fail=unknown, which is NOT zero: it means" >&2
      echo "           the shipper's state file was unreadable, so the shipper may never have run a" >&2
      echo "           single tick. reason=shipper_state_unreadable — do NOT read this as 'no POST" >&2
      echo "           failures', which would be an absence this probe never measured." >&2
    elif [[ -n "$shipper_post_fail" && "$shipper_post_fail" != "0" ]]; then
      echo "           The reporter's INDEPENDENT path says log_shipper_post_fail=${shipper_post_fail}," >&2
      echo "           so ticks ARE running and their POSTs are failing — that is an egress or token" >&2
      echo "           fault, not a dead shipper. reason=shipper_post_failing." >&2
    else
      echo "           The reporter reports no POST failures, so the tick is likely not running at" >&2
      echo "           all rather than failing to egress." >&2
    fi
    echo "           Reporter fields already read on this run (no second query needed):" >&2
    echo "             log_shipper_post_fail=${shipper_post_fail_raw:-<absent>}" >&2
    echo "             log_shipper_last_ok_age_s=${shipper_last_ok_age:-<absent>}  (-1 = no row has EVER shipped)" >&2
    echo "             log_shipper_dropped_cum=${shipper_dropped_cum:-<absent>}  drop_seq=${shipper_drop_seq:-<absent>}" >&2
    if [[ "${shipper_last_ok_age:-}" == "-1" ]]; then
      : # already led with above — a never-worked state, not a regression.
    elif [[ -n "${shipper_last_ok_age:-}" ]]; then
      echo "           A finite last_ok_age_s with zero envelope rows means the shipper IS" >&2
      echo "           delivering and the envelope prefix or the probe's grep has drifted." >&2
    fi
    exit 2
  fi
  echo "TRANSIENT: reason=not_delivered — zero envelope rows, no ${BOOT_MARKER} row, and no" >&2
  echo "           log_shipper_post_fail= field on any ${CONTROL_MARKER} row. That field exists" >&2
  echo "           only in the reporter this change ships, so its absence is positive proof the" >&2
  echo "           new cloud-init has not run (boot_id currently ${current_boot_id:-unknown}; note" >&2
  echo "           boot_id DRIFT is not used as evidence — this host self-reboots via the NIC" >&2
  echo "           guard, and runcmd is per-instance, so drift without a replace proves nothing)." >&2
  echo "           The read path IS alive (${n_control} control row(s)), so" >&2
  echo "           this is a MEASURED absence rather than a dark channel." >&2
  echo "           SINCE 2026-08-12 THIS IS A REGRESSION, NOT A NOT-YET. The channel was DELIVERED" >&2
  echo "           2026-08-12T20:54:12Z (run 31639782781) and first read back 21:03:51Z, which" >&2
  echo "           flipped ADR-184 to accepted. Reaching this arm now means the reporter has" >&2
  echo "           stopped carrying log_shipper_* fields — i.e. the host regressed to a" >&2
  echo "           pre-shipper image, or was re-provisioned from one." >&2
  echo "           Next: INVESTIGATE. Do not wait. (Before delivery this arm correctly read as the" >&2
  echo "           expected steady state; that advice is retired, not merely dated. It also named" >&2
  echo "           step-6 of the zot-pin ordered path as the delivery vehicle — that path closed" >&2
  echo "           WITHOUT firing step-6, so an operator who had just dispatched a replace was" >&2
  echo "           being told to wait for a step that no longer existed.)" >&2
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
# ANCHORED ON THE PARSED message FIELD, matching the producer (#7444 R33). is_cap_exempt keys on
# zerolog's `.message`, which is what closed the bypass where any client sending
# `User-Agent: executing gc` bought cap exemption for every one of its request lines. The reader
# counted the same four classes with a bare `grep -cF` over the WHOLE row, so that string in a
# header still counted here — byte-identical literals, different semantics, no gate between them.
# sanitize() strips quotes, so a shipped zerolog row renders `message:executing gc` while a
# header-borne one renders `User-Agent:[executing gc]` with `message:HTTP API`.
# STAYS FOUR-CLASS DELIBERATELY (#7555). The producer's cap-exempt set is now WIDER than these
# four: #7444 R12 added four crash classes (panic:, fatal error, runtime error, [signal] — which
# #7555 also repaired, since they could never match a PLAINTEXT panic), and #7555 added the
# HTTP-API half of an upload-failure pairing. This reader is NOT an exemption census and must not
# become one. It answers one question — is the #7440 channel delivering, and what is the gc
# start/complete RATIO — for which these four are the vocabulary. The upload-pairing question has
# its own probe (scripts/followthroughs/zot-upload-ceiling-7556.sh); counting it here too would be
# a second encoding that can drift from the first.
#
# The consequence to keep in view: these counts are a lower bound on exempt volume, never a
# measure of it. Do not read a flat gc count as "the exempt lane is quiet".
n_gc_start=$(printf '%s\n' "$envelope_hits" | grep -cF 'message:executing gc' || true)
n_gc_done=$(printf '%s\n' "$envelope_hits" | grep -cF 'message:gc successfully completed' || true)
n_gc_blobs=$(printf '%s\n' "$envelope_hits" | grep -cF 'message:garbage collected blobs' || true)
n_patch=$(printf '%s\n' "$envelope_hits" | grep -cF 'message:PatchBlobUpload' || true)
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
echo "      ADR-184 may now flip adopting -> accepted."
# NO ROW EXCERPT. sweep-followthroughs.sh captures this stdout with 2>&1 and posts it as a comment
# on a PUBLIC repo issue, so anything printed here is published. A raw zot row carries internal
# 10.0.1.x topology, service usernames, OCI repo names, digests, filesystem paths and User-Agent,
# and the credential scan above covers exactly three patterns — a secret shape outside those three
# reaches this line having already passed every gate. The FAIL arm is counts-only for this reason;
# the PASS arm is held to the same discipline. Counts and ratios are the contract; row VALUES are
# not, and the diagnostic question this probe answers ("did the channel deliver?") is a counting
# question. Pinned by C13 in tests/scripts/test-zot-log-channel-probe.sh.
exit 0
