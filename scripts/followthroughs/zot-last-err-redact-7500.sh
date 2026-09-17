#!/usr/bin/env bash
# Follow-through verification for #7500 Phase B — producer-side redaction of `zot_last_err`.
#
# WHY THIS IS A SOAK AND NOT A PRE-MERGE AC.
#
# Phase B lands in `cloud-init-registry.yml`. The registry host is cloud-init-only (ADR-096), so
# merging applies NOTHING: the change is inert until the next `registry-host-replace`, and this
# PR schedules no replace. A pre-merge AC asserting "the sample is redacted in the warehouse"
# would therefore be asserting a property of a host that does not yet run the code — which is
# the un-runnable-AC class, not a gate.
#
# REPLACE-GATED, NOT DATE-GATED. `earliest=` is a floor on when this probe first RUNS; it is
# never the condition. The condition is the OBSERVED SHAPE of tier-4 rows in the warehouse.
#
# EXIT CONTRACT (the sweeper lists `--state open`; its reopen path fires only on exit 1)
#   0 = PASS       tier-4 rows were observed in the window AND none carries header content
#   3 = CANNOT ESTABLISH  delivery is UNMEASURABLE (no usable boot_id on any row; or the
#                           terminal branch was reached, which is a probe defect). Renders as
#                           its own sweeper heading, so it is never read as "not yet".
#   2 = TRANSIENT  not yet delivered, no tier-4 row on the current boot, or ANY auth/query/decode
#                  failure
#   1 = FAIL       the producer IS delivered (boot_id moved past the recorded baseline) and
#                  tier-4 rows STILL carry header content -- the redaction shipped and does not
#                  work. Emitted ONLY in that branch: a host that has not been replaced yet is a
#                  not-yet, never a failure.
#
# WHY 1 IS NARROW. `exit 1` means "this must not close". A host that has not been replaced yet
# is a NOT-YET, not a defect, and a daily red for however long the replace takes trains everyone
# to walk past it. But an earlier revision emitted 1 in NO branch at all, which meant the one
# outcome that genuinely must not close — delivered and STILL leaking — was unreportable.
# Delivery is now established independently (boot_id), so FAIL is reachable exactly there.
#
# There is no automatic escalation for a long-running exit 2: sweep-followthroughs.sh comments
# TRANSIENT and does not escalate open issues. An earlier revision of this header deferred to an
# "escalation horizon" that does not exist — that was an unmeasured claim about a mechanism.
# The daily comments land on a PUBLIC issue and state which control is not yet in force; that is
# a deliberate trade, recorded here rather than discovered later.
#
# Whether the redaction is CORRECT when it arrives is settled pre-merge by
# `apps/web-platform/infra/zot-disk-heartbeat-redaction.test.sh` (29 assertions, 14 measured RED
# first). This probe answers DELIVERY, and says so rather than implying it graded both.
#
# THREE GUARDS, each closing a way this probe could PASS while proving nothing:
#
#   1. SUBJECT-MUST-HAVE-RUN. Requires at least one row whose `zot_last_err_src=fallback` —
#      i.e. tier 4 actually occurred in the window. Tier 4 is the ONLY tier the gate changes,
#      so a window containing none makes "no header content" trivially true: every other tier
#      is a matched diagnostic line that rarely carries a headers object anyway. Without this
#      guard the probe would PASS on a quiet week and close the issue having graded nothing.
#
#   2. A DARK CHANNEL IS NOT A CLEAN ONE. Zero rows of ANY kind means the reporter or the
#      warehouse is dark, which is indistinguishable from "clean" by absence alone. Reported
#      as `channel_dark` and exit 2, never as evidence of redaction.
#
#   3. DECODE BEFORE MATCHING. `betterstack-query.sh` emits JSONEachRow whose `raw` is an
#      escaped JSON string; matching the marker against the undecoded envelope silently returns
#      nothing — a probe that can never PASS, indistinguishable from a clean result.
#
# Secrets: BETTERSTACK_QUERY_HOST, BETTERSTACK_QUERY_USERNAME, BETTERSTACK_QUERY_PASSWORD
#
# Tracker directive (goes in the issue body):
#   <!-- soleur:followthrough script=scripts/followthroughs/zot-last-err-redact-7500.sh earliest=2026-09-09T00:00:00Z secrets=BETTERSTACK_QUERY_HOST,BETTERSTACK_QUERY_USERNAME,BETTERSTACK_QUERY_PASSWORD -->
#
# The merge-time boot_id is baked in as BASELINE_AT_MERGE (see the comment at that assignment for
# why it cannot be passed through the environment). SOLEUR_FT_BASELINE_BOOT still overrides it.
# With neither, the probe reports delivery state UNKNOWN rather than asserting a state it cannot
# measure -- and the delivered-and-leaking FAIL branch is unreachable.

set -uo pipefail

# XTRACE REFUSAL (#7797). This probe binds BETTERSTACK_QUERY_PASSWORD, and shell tracing echoes a
# command AFTER expansion -- so under `bash -x` the credential reaches the transcript at the moment
# it is bound, before it is used for anything. Two live tokens leaked exactly that way. Refuse to
# run traced while a credential is present, rather than trusting the caller not to trace.
case "$-" in
  *x*)
    if [ -n "${BETTERSTACK_QUERY_PASSWORD:+x}" ]; then
      printf '[FATAL] refusing to trace with a live credential set (see #7797)\n' >&2
      exit 78
    fi
    ;;
esac

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
QUERY="$REPO_ROOT/scripts/betterstack-query.sh"
PARSE_LIB="$REPO_ROOT/scripts/lib/zot-telemetry-parse.sh"
WINDOW="${SOLEUR_FT_WINDOW:-24h}"

# An unprovisioned secret must be TRANSIENT, never FAIL: `set -u` on a missing variable would
# abort with a non-zero status that this contract reads as FAIL, posting a daily false red.
for v in BETTERSTACK_QUERY_HOST BETTERSTACK_QUERY_USERNAME BETTERSTACK_QUERY_PASSWORD; do
  if [[ -z "${!v:-}" ]]; then
    echo "TRANSIENT: $v is unset — cannot query the Logs warehouse. This is a provisioning" >&2
    echo "           gap, not evidence about the redaction." >&2
    exit 2
  fi
done

if [[ ! -x "$QUERY" ]]; then
  echo "TRANSIENT: $QUERY missing or not executable — the probe could not run." >&2
  exit 2
fi

# --limit IS NOT OPTIONAL. betterstack-query.sh defaults to LIMIT=100 (its :368), applied as an
# inner `ORDER BY dt DESC LIMIT n`. The registry heartbeat is */5, i.e. 288 rows/24h, so the
# default silently reads the newest ~8h20m while every message below says "$WINDOW". Every
# sibling on this stream passes it explicitly (zot-fill-rate-7341.sh, zot-restart-loop-alarm.sh
# both use 5000). An unreported truncation on a probe that CLOSES a leak tracker is a window
# that excludes the rows it claims to have graded.
LIMIT="${SOLEUR_FT_LIMIT:-5000}"
RAWOUT="$("$QUERY" --since "$WINDOW" --grep 'SOLEUR_ZOT_DISK' --limit "$LIMIT" 2>/dev/null)" || {
  echo "TRANSIENT: betterstack-query.sh exited non-zero — channel_dark or auth failure." >&2
  exit 2
}

if [[ -z "$RAWOUT" ]]; then
  echo "TRANSIENT: channel_dark — zero SOLEUR_ZOT_DISK rows in $WINDOW. Absence of rows is not" >&2
  echo "           evidence of redaction; it is evidence the reporter or the warehouse is dark." >&2
  exit 2
fi

# MIRRORS zot_envelope_anchor (scripts/lib/zot-telemetry-parse.sh). NOT sourced, for the same
# mechanical reason zot-fill-rate-7341.sh records: the library's `zot_trusted_region` cuts to
# END OF LINE, which on a JSONEachRow row also removes the closing `"}` so the row no longer
# decodes. The three invariants are therefore mirrored post-decode below, each labelled with the
# library function it mirrors, and the divergence is filed for reconciliation — a JSON-aware
# variant belongs in the library.
#
# WHY THE ANCHOR IS LOAD-BEARING HERE. `--grep SOLEUR_ZOT_DISK` compiles to an UNANCHORED
# `raw LIKE '%…%'` over a source every host multiplexes into, and the library's own header
# records this as measured, not hypothetical: on 2026-07-15 three GitHub-webhook rows quoting a
# marker were returned to the sibling NIC leg. Before boot-scoping, a contaminating row could
# only flip the delivered BRANCH. Once the row set is scoped to the newest boot, one such row
# SELECTS the evidence base — so it excludes every genuine row and the probe exits 0, closing a
# live leak tracker. `User-Agent` is on the producer's HDR_KEEP allowlist and ships verbatim,
# which makes the injection vector an unauthenticated request header. The anchor closes it.
[[ -r "$PARSE_LIB" ]] || {
  echo "TRANSIENT: $PARSE_LIB is not readable — refusing to hand-roll the trusted-region parse." >&2
  exit 2
}
ENVELOPE="$(printf '%s\n' "$RAWOUT" | { grep -F '"raw":"{\"message\":\"SOLEUR_ZOT_DISK ' || true; })"
if [[ -z "$ENVELOPE" ]]; then
  echo "TRANSIENT: $(printf '%s\n' "$RAWOUT" | grep -c . || true) row(s) matched the marker but NONE carries the" >&2
  echo "           direct-POST producer envelope. Rows merely QUOTING the marker are not evidence" >&2
  echo "           about the producer, in either direction." >&2
  exit 2
fi

# DECODE BOTH HOPS. betterstack-query.sh's own header states `raw` is DOUBLE-encoded (a JSON
# string containing a JSON document); the sibling zot-log-channel-7440.sh decodes both. Stopping
# after hop 1 leaves every envelope key in the region LEAKY greps, so any envelope field named
# `headers`/`clientIP` makes LEAKY == TIER4_N on every row — a permanent false FAIL posted daily
# on a PUBLIC issue. `fromjson?` skips a noise line instead of aborting the stream.
#
# `dt` IS CARRIED THROUGH AND SORTED ON. MIRRORS zot_trusted_region's `sort`: the library warns
# against hard-coupling to the shared tool's dt-ASC default (#6251-spirit). Decoding `.raw`
# alone discards the sort key and makes "newest" whatever the query happened to return.
DECODED="$(printf '%s\n' "$ENVELOPE" \
  | jq -r 'select(.raw != null) | [(.dt // ""), (((.raw | fromjson?) // {}) | (.message // ""))] | @tsv' 2>/dev/null \
  | sort \
  | cut -f2-)" || DECODED=""
DECODED="$(printf '%s\n' "$DECODED" | grep -F 'SOLEUR_ZOT_DISK' || true)"
if [[ -z "$DECODED" ]]; then
  echo "TRANSIENT: could not decode the JSONEachRow envelope — matching the undecoded form" >&2
  echo "           would silently match nothing, which reads exactly like a clean result." >&2
  exit 2
fi

# TRUSTED REGION. boot_id decides DELIVERY, so a crafted tail carrying ` boot_id=FORGED`
# would otherwise win the greedy match, select the delivered branch, and close this tracker
# while Phase B had never been applied -- asserting a control is live on a host never replaced.
# The tail is cut first, exactly as zot_trusted_region does. LEAKY below still reads the tail,
# which is correct: that is the untrusted content it exists to measure.
#
# DERIVED BEFORE THE TIER-4 SELECTION, and that ordering is the whole point of #7960's first
# real post-replace run. Previously this sat BELOW the LEAKY computation, so `LEAKY` counted
# header-bearing rows across the entire $WINDOW while `NEWEST_BOOT` described only the newest
# row. The instant a replace lands mid-window those two describe DIFFERENT HOSTS: the newest
# row selects the delivered branch, and the leak check then grades PRE-replace output that the
# redaction was never in force for -- a guaranteed false FAIL ("the redaction shipped and is not
# working") on the one run that matters. Measured 2026-09-17: the replace applied at 11:21Z, so
# the 18:00Z sweep's returned set would have been roughly 20% pre-replace rows -- ~100 rows back
# from 18:00Z reaches 09:40Z under the LIMIT that was in force before this revision made it
# explicit. (An earlier draft of this comment said "~93%", computed against a literal 24h window
# the probe never received. The defect is unchanged; the magnitude was wrong and is corrected
# here rather than left as a recorded measurement nobody can reproduce.)
#
# It cuts the other way too, which is why scoping BOTH operands matters rather than just the
# leak check: an unscoped TIER4_ROWS could satisfy Guard 1 ("the subject must have run")
# entirely from rows emitted by a host that no longer exists, and report PASS on evidence the
# delivered producer never produced.
# MIRRORS zot_newest_boot. Two invariants the previous hand-rolled form dropped, both of which
# were false-CLOSE paths:
#   * `[0-9a-fA-F-]+` rather than `[^ ]*` — a bare `[^ ]*` accepts any token.
#   * `grep -v 'boot_id=unknown'` — `unknown` is the producer's /proc-unreadable DEFAULT
#     (cloud-init-registry.yml: `[ -n "$BOOT_ID" ] || BOOT_ID=unknown`), not an identity.
#     Accepting it means `unknown != BASELINE` selects the delivered branch and scopes the grade
#     to a pseudo-boot, so a /proc read failure alone closes the tracker. No attacker required.
NEWEST_BOOT="$(printf '%s\n' "$DECODED" \
  | sed 's/ zot_last_err=.*//' \
  | grep -oE 'boot_id=[0-9a-fA-F-]+' \
  | grep -v 'boot_id=unknown' \
  | tail -1 | cut -d= -f2)"

# No boot_id anywhere in the decoded rows means delivery is UNMEASURABLE, and an unmeasurable
# delivery state must not be graded. Without this the scoping below would select zero rows and
# fall into Guard 1, which reports "no tier-4 row in the window" -- a true statement about the
# wrong question.
if [[ -z "$NEWEST_BOOT" ]]; then
  echo "CANNOT ESTABLISH: no usable boot_id on any decoded SOLEUR_ZOT_DISK row (rows exist, but" >&2
  echo "           every boot_id is absent or the 'unknown' /proc-fallback sentinel), so delivery" >&2
  echo "           cannot be established and the leak check cannot be scoped to a host." >&2
  echo "           ACTION: rows present with no real boot_id is a PRODUCER regression — the" >&2
  echo "           heartbeat emitter dropped a field this verdict depends on. Check the" >&2
  echo "           \`boot_id=\` field in cloud-init-registry.yml's LINE= emitter." >&2
  # exit 3, NOT 2. sweep-followthroughs.sh renders 2 as "NOT YET" and 3 as "CANNOT ESTABLISH",
  # and the heading is the only text an operator sees without expanding the <details> fold. A
  # branch whose whole purpose is refusing to assert a delivery state must not ship under a
  # heading that asserts one. Same disposition either way (issue stays open).
  exit 3
fi

# Bound the trusted region the way scripts/lib/zot-telemetry-parse.sh does: `zot_last_err` is
# emitted LAST and is free text, so a crafted log line could otherwise spoof a field a verdict
# keys on. Here we WANT the tail, so cut the other direction and keep it explicit.
# SCOPED TO THE DELIVERED BOOT. The boot_id is read from each row's trusted region (the tail is
# cut first, exactly as NEWEST_BOOT does above) but the FULL row is what gets printed, because
# LEAKY below must still read the untrusted tail it exists to measure.
# ONE PASS, ONE TRUSTED REGION, applied to EVERY field a verdict keys on. The previous revision
# bounded only the boot_id read; the tier selector ran `grep` against the FULL row, so a crafted
# `zot_last_err` tail containing the literal `zot_last_err_src=fallback` promoted a non-tier-4
# row into the graded set and satisfied Guard 1 with rows the gate never touched. The producer's
# own template names this class one layer down: "a whole-line substring test instead lets any
# private-net client send `User-Agent: executing gc` and make EVERY one of its request lines
# cap-exempt … field-anchoring closes the bypass by construction."
#
# Rows are emitted as `head TAB tail` so the leak check reads the tail bounded at the SAME
# (first) delimiter the head cut uses. The two must not disagree — see the LEAKY note below.
#
# The tier test accepts `fallback` OR `suppressed`, and that is a correctness fix, not a
# widening. Phase B's gate RE-TAGS a tier-4 sample it fully suppressed
# (cloud-init-registry.yml: `if [ -z "$_msgs" ] && [ -n "$ZOT_ERR_RAW" ]; then
# ZOT_ERR_SRC=suppressed; fi`). A `fallback`-only selector therefore makes Guard 1 permanently
# unsatisfiable on a delivered host whose gate is working at its strongest — the tracker could
# never close, and #7960's falsification condition would fire on a CORRECT outcome. `suppressed`
# carries no sample, so it counts toward "the subject ran" and is excluded from the leak grade.
# Left-anchored (`(^| )`), so the token cannot be matched mid-word.
TIER4_ROWS="$(printf '%s\n' "$DECODED" \
  | awk -v want="$NEWEST_BOOT" '
      {
        i = index($0, " zot_last_err=")
        head = (i > 0) ? substr($0, 1, i - 1) : $0
        tail = (i > 0) ? substr($0, i + 14) : ""
        if (head !~ /(^| )zot_last_err_src=(fallback|suppressed)( |$)/) next
        if (!match(head, / boot_id=[0-9a-fA-F-]+/)) next
        b = substr(head, RSTART + 9, RLENGTH - 9)
        if (b != want) next
        print head "\t" tail
      }' || true)"
TOTAL_ROWS="$(printf '%s\n' "$DECODED" | grep -cF 'SOLEUR_ZOT_DISK' || true)"
[[ -n "$TOTAL_ROWS" ]] || TOTAL_ROWS=0

# KNOWN LIMITATION, stated rather than left implicit: `boot_id != BASELINE` establishes a new
# BOOT, not a new HOST. cloud-init's runcmd is per-instance and does not re-run on reboot, and
# THIS host reboots as a convergence primitive (the private-NIC guard calls `reboot`; the
# heartbeat carries `reboot_count=`). So a plain reboot of the UN-REPLACED host flips boot_id
# with the OLD user_data still in place, and this probe reads that as delivered. The sibling
# zot-log-channel-7440.sh hit exactly this and replaced the drift heuristic with a positive
# delivery key. Doing the same here is a design change with more than one candidate key and a
# second consumer to migrate, so it is tracked separately rather than smuggled into a scoping
# fix. Until then a reboot-without-replace can produce a premature verdict in either direction.
BASELINE_AT_MERGE=d0107f1f-834b-4acc-bd5a-00e53b61d835
BASELINE="${SOLEUR_FT_BASELINE_BOOT:-$BASELINE_AT_MERGE}"

# ASSIGNED ABOVE GUARD 1, deliberately. Guard 1 used to fire before BASELINE existed, so its
# message could not name the delivery state and collapsed two opposite situations into one
# comment: "the replace has not happened" and "the replace LANDED and we are waiting only on a
# tier-4 occurrence". The second is the run that first proves delivery succeeded, and the
# operator was shown a NOT-YET heading for it. Nothing between here and the old position
# computed either value, so the move is free.
# Guard 1: the subject must have run. EXACT match on the field value, not a substring --
# `zot_last_err_src=fallback` would also match a future qualified form by prefix.
if [[ -z "$TIER4_ROWS" ]]; then
  echo "TRANSIENT: $TOTAL_ROWS SOLEUR_ZOT_DISK row(s) in $WINDOW, but NONE at tier 4" >&2
  echo "           (zot_last_err_src=fallback|suppressed) on the current boot ($NEWEST_BOOT)." >&2
  if [[ -n "$BASELINE" && "$NEWEST_BOOT" != "$BASELINE" ]]; then
    echo "           DELIVERY HAS LANDED — boot_id != the merge-time baseline ($BASELINE). This is" >&2
    echo "           NOT 'not yet': the replace fired and the probe is waiting only on a tier-4" >&2
    echo "           occurrence on this boot. Nothing to do unless this persists for days." >&2
  else
    echo "           The host still carries the merge-time baseline boot_id, so Phase B is not in" >&2
    echo "           force yet. This is the expected reading until a registry-host-replace fires." >&2
  fi
  echo "           Tier 4 is the only tier the gate changes, so this window cannot grade it." >&2
  echo "           NOTE: rows from an EARLIER boot are deliberately excluded — grading them" >&2
  echo "           would describe a host this verdict is not about." >&2
  exit 2
fi

TIER4_N="$(printf '%s\n' "$TIER4_ROWS" | grep -c . || true)"
[[ -n "$TIER4_N" ]] || TIER4_N=0

# LEAKY reads the tail the awk pass already cut at the FIRST ` zot_last_err=`. The previous form
# was `sed -n 's/.* zot_last_err=//p'` — a GREEDY prefix, i.e. the LAST occurrence — while every
# other cut in this file and in the library is leftmost. On a tier-4 sample (three `docker logs`
# lines flattened into one field) a later line's text lands after an earlier line's header
# content, so the greedy read truncated the leak out of the measurement: measured, a row
# carrying `{headers:{Cookie:…}} clientIP:…` followed by a second ` zot_last_err=` graded CLEAN.
# That is exit 1's reserved case scored as exit 0.
#
# Only `fallback` rows are graded: a `suppressed` row carries no sample and cannot leak.
# The discriminator is STRUCTURAL rather than the bare words — the gate emits zot's `.message`
# verbatim, and a legitimate message such as `cannot parse headers` would otherwise force a
# post-delivery FAIL on a row that leaks nothing.
LEAKY="$(printf '%s\n' "$TIER4_ROWS" \
  | awk -F'\t' '$1 ~ /(^| )zot_last_err_src=fallback( |$)/ { print $2 }' \
  | grep -cE '(headers|clientIP)[[:space:]]*[]=:{"]' || true)"
[[ -n "$LEAKY" ]] || LEAKY=0

# DELIVERY IS ITS OWN QUESTION, and conflating it with the leak check is the #7455 defect with
# the operands swapped. Three states collapse into one reading unless delivery is established
# independently:
#
#   (a) the replace has not fired                          -> genuinely not yet
#   (b) it fired and tier 4 did not occur in this window   -> ungraded, NOT "not delivered"
#   (c) it fired and the gate WORKED                       -> also produces no leaky tier-4 row
#
# (c) is the dangerous one: the tier gate's whole job is to stop emitting the row this probe
# looks for, so Guard 1's own success is indistinguishable from non-delivery unless something
# else says the new producer is running. `boot_id` is that something -- it is on every row, and
# a replace necessarily produces a new one.
#
# The merge-time boot_id decides delivery. It is baked in below rather than read from the
# environment; with neither it nor an override present the probe reports an UNKNOWN delivery state
# rather than asserting "NOT YET DELIVERED", because asserting a delivery state it cannot measure
# is exactly the unmeasured claim this whole change removes.
# BAKED IN, not passed. sweep-followthroughs.sh runs every probe under `env -i` with only the
# names declared in the directive's `secrets=`, so an exported SOLEUR_FT_BASELINE_BOOT is stripped
# before this script starts. Reading it from the environment alone therefore left BASELINE empty on
# every scheduled run, which made the delivered-and-leaking FAIL branch above unreachable -- a
# guard that could not fire. The constant is the boot_id measured on the live host immediately
# before merge (2026-09-08: 100 of 100 SOLEUR_ZOT_DISK rows in a 24h window carried this single
# value, read from the trusted region). The env var is still honoured first so an operator can
# override it without editing this file.

if [[ -n "$BASELINE" && -n "$NEWEST_BOOT" && "$NEWEST_BOOT" != "$BASELINE" ]]; then
  # DELIVERED: the host has been replaced since merge. Now the leak check is a real verdict,
  # and a leak here is a genuine FAIL -- the redaction shipped and did not work. This is the
  # branch the previous revision could not express at all.
  if [[ "$LEAKY" -gt 0 ]]; then
    echo "FAIL: the producer IS delivered (boot_id $NEWEST_BOOT != baseline $BASELINE) and" >&2
    echo "      $LEAKY of $TIER4_N tier-4 row(s) STILL carry header content. The redaction" >&2
    echo "      shipped and is not working. This must not close." >&2
    exit 1
  fi
  echo "PASS: producer delivered (boot_id $NEWEST_BOOT != baseline $BASELINE);"
  echo "      $TIER4_N tier-4 row(s) on this boot in $WINDOW, none carrying header content."
  exit 0
fi

if [[ "$LEAKY" -gt 0 ]]; then
  echo "TRANSIENT: NOT YET DELIVERED — $LEAKY of $TIER4_N tier-4 row(s) still carry header" >&2
  echo "           content in zot_last_err. Phase B is inert until the next" >&2
  echo "           registry-host-replace (ADR-096: the host is cloud-init-only), so this is the" >&2
  echo "           expected reading until a replace fires. The sink-side scrub (ADR-211 Layer 2)" >&2
  echo "           is in force meanwhile and covers the PUBLIC egress, which is the worse one." >&2
  exit 2
fi

# Reachable only if BASELINE_AT_MERGE is ever blanked (`:-` already treats an empty override as
# unset, so the override alone cannot produce this state). Kept deliberately: the failure it
# guards against is a future edit emptying the constant, which would otherwise send every run
# down the NOT-YET-DELIVERED branch above and assert a delivery state with nothing measuring it.
if [[ -z "$BASELINE" ]]; then
  echo "TRANSIENT: delivery state UNKNOWN — $TIER4_N tier-4 row(s) carry no header content," >&2
  echo "           which is what BOTH a delivered-and-working gate and a quiet pre-delivery" >&2
  echo "           window look like. BASELINE_AT_MERGE is empty and no SOLEUR_FT_BASELINE_BOOT" >&2
  echo "           override was given; restore the merge-time boot_id (it is on every" >&2
  echo "           SOLEUR_ZOT_DISK row) to make this gradeable. Reporting UNKNOWN rather than" >&2
  echo "           asserting a delivery state this probe cannot measure." >&2
  exit 2
fi

# BASELINE is set and the boot_id has NOT moved: the host was never replaced, so Phase B
# cannot be in force. This was previously the fall-through to the terminal PASS below, which
# reported "producer delivered ... the tier gate is in force" for an un-replaced host whose
# window merely happened to be clean -- the exact false-close this probe exists to prevent.
if [[ -n "$BASELINE" && "$NEWEST_BOOT" == "$BASELINE" ]]; then
  echo "TRANSIENT: NOT YET DELIVERED — boot_id is still the merge-time baseline ($BASELINE)," >&2
  echo "           so no registry-host-replace has fired and Phase B cannot be in force." >&2
  echo "           $TIER4_N tier-4 row(s) carried no header content, which is the expected" >&2
  echo "           reading for a quiet window and is NOT evidence of delivery." >&2
  exit 2
fi

# UNREACHABLE, and it must stay that way. Every route to this line now exits above: the
# no-usable-boot_id guard makes NEWEST_BOOT non-empty, the delivered branch consumes
# `!= BASELINE`, the empty-BASELINE branch consumes the third, and `== BASELINE` consumes the
# last. This block used to be a live `exit 0` reachable exactly in the no-boot_id case — i.e. it
# WAS the false close that the harness found. Leaving an `exit 0` at the bottom of a file whose
# reachability depends on a guard 130 lines above is one refactor away from resurrection, so the
# terminal state is now a refusal rather than a pass.
echo "CANNOT ESTABLISH: reached the terminal branch, which is unreachable by construction." >&2
echo "           Some guard above stopped exiting. Do NOT read this as a pass — no verdict was" >&2
echo "           computed. This is a probe defect; fix the guard chain before trusting a run." >&2
exit 3
