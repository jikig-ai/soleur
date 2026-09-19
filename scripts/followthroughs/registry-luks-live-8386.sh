#!/usr/bin/env bash
# Follow-through verification for #8386 — the registry-host at-rest posture emitter.
#
# WHAT THIS ANSWERS, AND WHAT IT DELIBERATELY DOES NOT.
#
# `hcloud_volume.registry` claims LUKS at rest in scripts/encryption-posture-ledger.json, and
# until #8386 nothing could read that claim off-box: the evidence was the Terraform/cloud-init
# SOURCE, not a measurement of the running host. #8386 adds five fields to the SOLEUR_ZOT_DISK
# heartbeat row, ahead of its free-text `zot_last_err` tail:
#
#   store_mount_src       findmnt -no SOURCE /var/lib/zot   (or __NOMOUNT__ / __UNREADABLE__)
#   store_backing_dev     the cryptsetup `device:` line the LUKS verdict was taken against
#   store_mount_devid     the /dev/disk/by-id/scsi-0HC_Volume_* alias of the backing disk
#   store_expected_devid  the Terraform-rendered scsi-0HC_Volume_<id> literal
#   store_luks            yes | no | unknown | absent
#
# This probe reads those fields out of Better Stack and grades them. It answers "is the store
# measured to be on a LUKS device on the volume Terraform declared". It does NOT answer "can we
# still unlock it" or "is the header intact" — the escrow re-test (`cryptsetup luksOpen
# --test-passphrase`, the header-UUID read) that luks-monitor.sh runs daily for the workspaces
# volume is deliberately out of scope and is tracked on the deferral issue. A `store_luks=yes`
# reading therefore means the store SITS ON a LUKS container, nothing more.
#
# DELIVERY IS A HOST REPLACE. The registry host is cloud-init-only (ADR-096), so merging #8386
# applies NOTHING: the emitter is inert until the next registry-host-replace. That is why the
# undelivered state (V2) is a first-class verdict with its own escalation clock rather than a
# failure — and why this file is a follow-through and not a pre-merge AC.
#
# EXIT CONTRACT (sweep-followthroughs.sh maps the code to the heading an operator reads without
# expanding the fold; the issue stays open on everything but 0, and this probe never returns 0):
#   0 = PASS               unreachable by design — see V7 below.
#   1 = FAIL               the store was measured NOT encrypted (V1, V4). Posted publicly.
#   2 = NOT YET            channel/auth/envelope/decode/host-scope guards, and the first sweep
#                          of an undelivered window.
#   3 = CANNOT ESTABLISH   the evidence cannot be read or is not yet deep enough.
#   5 = ACTION REQUIRED    a human decision is due (V6, V7), or an exit-3 branch has been parked
#                          past the staleness horizon and is a probe defect rather than a wait.
#
# WHY V7 IS NOT AN AUTO-CLOSE, recorded because "evidence complete" obviously wants to be exit 0.
# Better Stack source 2457081 is shared and multi-tenant (scripts/lib/betterstack-sources.sh
# calls it "Shared, multi-tenant, and chatty"): the web hosts and the Inngest node ship into it,
# a Better Stack source has ONE ingest token, and `host=` and `boot_id=` are PRODUCER-CONTROLLED
# fields inside the message while only `dt` is ingest-assigned. Any holder of that token can
# synthesize three producer-shaped rows on a fresh boot id. That is adequate authority for "stop
# waiting, a human should look". It is not adequate authority for unattended closure of a
# security tracker plus a ledger flip to `available`. Exit 0 returns when the emitter moves to a
# single-tenant source (the BS_GIT_DATA_SOURCE_ID pattern) — named in the deferral issue.
#
# NO GitHub Actions QUERY, and this is a capability fact rather than a preference.
# scheduled-followthrough-sweeper.yml declares `permissions: contents: read` + `issues: write`,
# so an Actions-runs query 403s under the token this probe inherits. An earlier draft split the
# undelivered verdict three ways on the dispatcher's run history; that arm is DELETED rather
# than degraded, and V2's message carries the re-fire command and the apply-file byte count
# instead. This probe's only external read is scripts/betterstack-query.sh.
#
# GUARD CHAIN — ordered early exits, each with its own branch marker, none of them a verdict:
#   secret unset -> 2 | query missing -> 2 | query non-zero -> 2 | zero rows -> 2 channel_dark |
#   parse lib unreadable -> 2 | no producer envelope -> 2 | decode failure -> 2 |
#   host filter empties the set -> 2 | no usable boot_id -> 3 | newest dt unparseable -> 3 |
#   newest row older than 30 min -> 3 producer_silent | the awk pass produced no integers -> 3.
#
# WHY producer_silent EXISTS. A host that WAS emitting and stopped is otherwise
# indistinguishable from a dark warehouse once the query window rolls past its last row: the
# rows are still there, they are just all old, and every count below would be computed from a
# host that has not spoken in hours. Six missed ticks (the heartbeat is */5) is the threshold.
#
# ONE AWK PASS, ONE TRUSTED REGION. Every value a verdict keys on — boot_id and all five posture
# fields — is read from `substr($0, 1, index($0, " zot_last_err=") - 1)`, the region the producer
# fills, in a SINGLE pass that also produces the counts. `zot_last_err` is free text: it carries
# zot's own log line, which is attacker-influenced through request headers on the private net.
# A crafted tail must not be able to supply a boot_id, a posture field or a count. A second pass
# over the same rows, a field read outside this pass, or a read past the tail cut is the defect
# this file's Guard Contract forbids.
#
# COUNTS ON THE NEWEST BOOT (head only):
#   D  rows carrying a non-empty `store_luks=`
#   Y  rows reading `store_luks=yes`
#   P  rows reading `store_luks=no`
#
# P COUNTS `no` AND DELIBERATELY NOT `absent`. The store mounts through a `nofail` fstab line
# plus the registry-luks-open.service oneshot, so the first tick or two of a legitimate boot can
# land before the mount and read `absent`; counting that as permanent plaintext would FAIL every
# correct replace. `no` — a store MOUNTED from something that is not a LUKS container — is never
# explainable by a boot race. Residual, stated rather than hidden: `absent` on the NEWEST row is
# still V4, so a sweep landing inside the post-replace mount race posts one FAIL on a correct
# boot. Rare, self-correcting on the next sweep, and fail-loud in the safe direction.
#
# PUBLIC OUTPUT. The sweeper posts this script's output verbatim into a comment on a PUBLIC
# issue. Messages carry counts, verdict tokens and boot ids only — never row text. And on the
# FAIL verdicts (V1/V4) the volume alias and `store_mount_src` are withheld too: "named Hetzner
# volume X is mounted unencrypted right now" on a public tracker is an advertisement, and the
# rule "never row text" does not by itself cover the verdict PROSE. Those verdicts name the
# branch marker and which disjunct fired, and point at the private Better Stack read.
#
# STALENESS APPLIES TO EVERY EXIT-3 BRANCH, not just the undelivered one. The sweeper never
# escalates a long-lived 2/3 on its own, so scoping the clock to V2 would leave a STRUCTURALLY
# BROKEN probe — an awk dialect change, a jq upgrade, a renamed field — parked on V3 / V5 / the
# integer guard / producer_silent forever, all exit 3, indistinguishable from legitimately
# waiting to anyone not diffing daily comments. Every exit-3 branch therefore consults the clock
# against the `earliest=` constant in the tracker directive below and exits 5 instead once more
# than 30 days have elapsed, naming the branch.
#
# Secrets: BETTERSTACK_QUERY_HOST, BETTERSTACK_QUERY_USERNAME, BETTERSTACK_QUERY_PASSWORD
#
# Tracker directive (goes in the #8386 issue body; all three names are already in the sweeper's
# env: map, so the directive is what authorizes forwarding them and no workflow edit is needed):
#   <!-- soleur:followthrough script=scripts/followthroughs/registry-luks-live-8386.sh earliest=2026-09-21T00:00:00Z secrets=BETTERSTACK_QUERY_HOST,BETTERSTACK_QUERY_USERNAME,BETTERSTACK_QUERY_PASSWORD -->

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
LEDGER="$REPO_ROOT/scripts/encryption-posture-ledger.json"
APPLY_WF="$REPO_ROOT/.github/workflows/apply-web-platform-infra.yml"

# ── CONTRACT CONSTANTS ────────────────────────────────────────────────────────────────────────
# The five field names are the emitter contract (#8386). They are declared HERE, once, and the
# suite greps them out of this file rather than restating them, so a rename reddens the suite
# before any case runs. The emitter/probe seam itself is pinned on the producer side by
# registry-boot-guard.test.sh's field-name loop.
F_SRC="store_mount_src"
F_BACKING="store_backing_dev"
F_DEVID="store_mount_devid"
F_EXPECTED="store_expected_devid"
F_LUKS="store_luks"
# The mapper NAME is a committed constant, and the one committed constant any verdict reads. It
# is fixed by the same template that renders the volume id, so it is not an independent claim --
# it is an assertion that the mount is the one this template creates, not some other LUKS device.
EXPECTED_SRC="/dev/mapper/registry"
# The ALIAS is NOT a committed constant: it is the row's own store_expected_devid, rendered by
# Terraform from state, so a repo diff cannot change what this probe expects. Only its SHAPE is
# pinned here -- an empty registry_volume_id renders `scsi-0HC_Volume_` and must not satisfy a
# comparison against an equally-empty measured value.
ALIAS_SHAPE='^scsi-0HC_Volume_[0-9]+$'
# The producer's own hostname, from zot-registry.tf. Scoping on it precedes boot selection as
# defence in depth: the envelope anchor already admits only the direct-POST producer envelope, so
# a second host would have to emit a producer-shaped row to contaminate the set.
EXPECTED_HOST="soleur-registry"
MARKER="SOLEUR_ZOT_DISK"
# Three rows on one boot. One row is a single tick and cannot distinguish a settled mount from a
# lucky read; three spans fifteen minutes of the heartbeat.
CONFIRM_MIN=3
# Six missed */5 ticks.
PRODUCER_SILENT_SECS=1800
STALE_DAYS=30
# One sweep. sweep-followthroughs.sh runs daily, so "the first sweep past earliest" is the first
# 24 hours, and only inside it is an undelivered window NOT YET rather than CANNOT ESTABLISH.
FIRST_SWEEP_SECS=86400
# GitHub's workflow-file size limit, the thing #8361 is over.
WORKFLOW_BYTE_LIMIT=512000
REFIRE_CMD="gh workflow run registry-host-replace-dispatch.yml -f reason='deliver #8386 registry posture emitter' -f tracker=8386"

WINDOW="${SOLEUR_FT_WINDOW:-24h}"
# --limit IS NOT OPTIONAL. betterstack-query.sh defaults to LIMIT=100, applied as an inner
# `ORDER BY dt DESC LIMIT n`. The heartbeat is */5, i.e. 288 rows/24h, so the default silently
# reads the newest ~8h20m while every message below says "$WINDOW". Every sibling on this stream
# passes 5000 explicitly.
LIMIT="${SOLEUR_FT_LIMIT:-5000}"

marker() { # <verdict-token> <extra k=v pairs>
  printf 'registry-luks[#8386]: verdict=%s %s\n' "$1" "$2" >&2
}

# ── THE STALENESS CLOCK ───────────────────────────────────────────────────────────────────────
# Read from the tracker directive in this file's OWN header, never from a second copy: the
# directive is what the sweeper acts on, so anything else would let the two drift.
EARLIEST_RAW="$(grep -oE 'earliest=[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z' "${BASH_SOURCE[0]}" | head -1 | cut -d= -f2)" || EARLIEST_RAW=""
NOW_EPOCH="$(date -u +%s)"
EARLIEST_EPOCH="$(date -u -d "$EARLIEST_RAW" +%s 2>/dev/null)" || EARLIEST_EPOCH=""
ELAPSED_DAYS=""
ELAPSED_SECS=""
if [[ -n "$EARLIEST_EPOCH" ]]; then
  ELAPSED_SECS=$(( NOW_EPOCH - EARLIEST_EPOCH ))
  ELAPSED_DAYS=$(( ELAPSED_SECS / 86400 ))
fi

# Returns 0 when the caller's exit-3 state has been parked past the horizon, having printed the
# escalation marker and prose. A clock that cannot be read NEVER escalates: an unparseable
# directive must not manufacture an ACTION REQUIRED comment out of nothing.
stale_now() { # <branch-token>
  [[ -n "$ELAPSED_DAYS" ]] || return 1
  (( ELAPSED_DAYS > STALE_DAYS )) || return 1
  printf 'registry-luks[#8386]: escalation=stale branch=%s days=%s\n' "$1" "$ELAPSED_DAYS" >&2
  printf 'ACTION REQUIRED: in this state for %s days — treat this as a defect, not a wait.\n' "$ELAPSED_DAYS" >&2
  printf '           Branch: %s. Past %s days a probe parked on one CANNOT ESTABLISH branch is\n' "$1" "$STALE_DAYS" >&2
  printf '           indistinguishable from one legitimately waiting; this escalation separates them.\n' >&2
  return 0
}

# ── PREFLIGHT ─────────────────────────────────────────────────────────────────────────────────
# An unprovisioned secret must be TRANSIENT, never FAIL: `set -u` on a missing variable would
# abort with a non-zero status that this contract reads as FAIL, posting a daily false red. The
# banned `: "${VAR:?msg}"` form does the same thing and is what lint-followthrough-varq-ban.sh
# exists to keep out of this directory.
for v in BETTERSTACK_QUERY_HOST BETTERSTACK_QUERY_USERNAME BETTERSTACK_QUERY_PASSWORD; do
  if [[ -z "${!v:-}" ]]; then
    marker "g1_secret_unset" "secret=$v"
    echo "TRANSIENT: $v is unset — cannot query the Logs warehouse. This is a provisioning" >&2
    echo "           gap, not evidence about the registry volume's at-rest posture." >&2
    exit 2
  fi
done

if [[ ! -x "$QUERY" ]]; then
  marker "g2_query_missing" "path=scripts/betterstack-query.sh"
  echo "TRANSIENT: $QUERY missing or not executable — the probe could not run." >&2
  exit 2
fi

# The query's stdout is CAPTURED and its stderr is DISCARDED, and neither is ever echoed below.
# BETTERSTACK_QUERY_PASSWORD is bound in that child process; a tool that dies mid-auth can print
# a URL or a header carrying it, and this probe's output goes into a public issue comment. The
# xtrace refusal above covers TRACING, not output pass-through — they are different leaks.
RAWOUT="$("$QUERY" --since "$WINDOW" --grep "$MARKER" --limit "$LIMIT" 2>/dev/null)" || {
  marker "g3_query_failed" "window=$WINDOW"
  echo "TRANSIENT: betterstack-query.sh exited non-zero — channel_dark or auth failure. Its" >&2
  echo "           output is deliberately NOT reproduced here: the credential is bound in that" >&2
  echo "           process and this text lands on a public issue. Read it from the workflow log." >&2
  exit 2
}

if [[ -z "$RAWOUT" ]]; then
  marker "g4_channel_dark" "window=$WINDOW"
  echo "TRANSIENT: channel_dark — zero $MARKER rows in $WINDOW. Absence of rows is not evidence" >&2
  echo "           about the volume's posture; it is evidence the reporter or the warehouse is dark." >&2
  exit 2
fi

# MIRRORS zot_envelope_anchor (scripts/lib/zot-telemetry-parse.sh). NOT sourced, for the
# mechanical reason zot-fill-rate-7341.sh and zot-last-err-redact-7500.sh both record: the
# library's `zot_trusted_region` cuts to END OF LINE, which on a JSONEachRow row also removes the
# closing `"}` so the row no longer decodes. The invariants are mirrored post-decode below, each
# labelled with the library function it mirrors.
#
# WHY THE ANCHOR IS LOAD-BEARING. `--grep SOLEUR_ZOT_DISK` compiles to an UNANCHORED
# `raw LIKE '%…%'` over a source every host multiplexes into, and the library's header records
# this as measured: on 2026-07-15 three GitHub-webhook rows quoting a marker were returned to a
# sibling probe. Once the row set is scoped to the newest boot, one contaminating row SELECTS the
# evidence base.
[[ -r "$PARSE_LIB" ]] || {
  marker "g5_parse_lib_unreadable" "path=scripts/lib/zot-telemetry-parse.sh"
  echo "TRANSIENT: $PARSE_LIB is not readable — refusing to hand-roll the trusted-region parse" >&2
  echo "           when the invariants this file mirrors cannot be read beside it." >&2
  exit 2
}
ENVELOPE="$(printf '%s\n' "$RAWOUT" | { grep -F '"raw":"{\"message\":\"'"$MARKER"' ' || true; })"
if [[ -z "$ENVELOPE" ]]; then
  MARKER_ROWS="$(printf '%s\n' "$RAWOUT" | grep -c . || true)"
  marker "g6_envelope_absent" "rows=$MARKER_ROWS"
  echo "TRANSIENT: $MARKER_ROWS row(s) matched the marker but NONE carries the direct-POST" >&2
  echo "           producer envelope. Rows merely QUOTING the marker are not evidence about the" >&2
  echo "           producer, in either direction." >&2
  exit 2
fi

# DECODE BOTH HOPS. betterstack-query.sh's header states `raw` is DOUBLE-encoded (a JSON string
# containing a JSON document). Stopping after hop 1 leaves every field unreadable, which looks
# exactly like a producer that never emitted them — a probe that can never grade anything,
# indistinguishable from an undelivered window. `fromjson?` skips a noise line instead of
# aborting the stream.
#
# `dt` IS CARRIED THROUGH AND SORTED ON, and it is carried as a TSV column rather than discarded:
# the producer_silent guard below needs the newest row's ingest timestamp, and `dt` is the only
# field in the row that the PRODUCER does not control. Decoding `.raw` alone would discard the
# sort key and make "newest" whatever the query happened to return.
DECODED_TSV="$(printf '%s\n' "$ENVELOPE" \
  | jq -r 'select(.raw != null) | [(.dt // ""), (((.raw | fromjson?) // {}) | (.message // ""))] | @tsv' 2>/dev/null \
  | sort)" || DECODED_TSV=""
DECODED_TSV="$(printf '%s\n' "$DECODED_TSV" | { grep -F "$MARKER" || true; })"
if [[ -z "$DECODED_TSV" ]]; then
  marker "g7_decode_failed" "window=$WINDOW"
  echo "TRANSIENT: could not decode the JSONEachRow envelope — matching the undecoded form would" >&2
  echo "           silently match nothing, which reads exactly like an undelivered emitter." >&2
  exit 2
fi

# HOST SCOPING, ON THE TRUSTED HEAD, BEFORE BOOT SELECTION. `host=` is producer-controlled inside
# the message, so this is defence in depth rather than authentication — but it removes the class
# the 7500 probe records as a known open gap (a second host POSTing this marker supplying the
# "newest boot"). Matched with a word boundary on both sides so `host=soleur-registry-2` does not
# satisfy it, and read from the head so a crafted tail cannot forge it.
SCOPED_TSV="$(printf '%s\n' "$DECODED_TSV" | awk -v host="$EXPECTED_HOST" '
  {
    i = index($0, " zot_last_err=")
    head = (i > 0) ? substr($0, 1, i - 1) : $0
    if (head ~ ("(^| )host=" host "($| )")) print
  }')"
if [[ -z "$SCOPED_TSV" ]]; then
  ALL_ROWS="$(printf '%s\n' "$DECODED_TSV" | grep -c . || true)"
  marker "g8_host_filter_empty" "decoded=$ALL_ROWS expected_host=$EXPECTED_HOST"
  echo "TRANSIENT: $ALL_ROWS decoded producer row(s), NONE from host=$EXPECTED_HOST. Grading" >&2
  echo "           another host's rows would answer a question about a volume this ledger row" >&2
  echo "           does not describe." >&2
  exit 2
fi

# MIRRORS zot_newest_boot. Two invariants a hand-rolled form drops, both false-close paths:
#   * `[0-9a-fA-F-]+` rather than `[^ ]*` — a bare `[^ ]*` accepts any token.
#   * `unknown`, the producer's /proc-unreadable DEFAULT, is not an identity. The character class
#     is what excludes it: `u`, `n`, `k`, `w` are absent from `[0-9a-fA-F-]`.
NEWEST_BOOT="$(printf '%s\n' "$SCOPED_TSV" \
  | sed 's/ zot_last_err=.*//' \
  | grep -oE 'boot_id=[0-9a-fA-F-]+' \
  | tail -1 | cut -d= -f2)" || NEWEST_BOOT=""

if [[ -z "$NEWEST_BOOT" ]]; then
  marker "g9_no_boot_id" "host=$EXPECTED_HOST"
  echo "CANNOT ESTABLISH: no usable boot_id on any decoded $MARKER row (rows exist, but every" >&2
  echo "           boot_id is absent or the 'unknown' /proc-fallback sentinel), so the posture" >&2
  echo "           fields cannot be scoped to a boot." >&2
  echo "           ACTION: rows present with no real boot_id is a PRODUCER regression — check the" >&2
  echo "           \`boot_id=\` field in cloud-init-registry.yml's LINE= emitter." >&2
  if stale_now "g9_no_boot_id"; then exit 5; fi
  exit 3
fi

# PRODUCER LIVENESS. `dt` is ingest-assigned, so it is the one timestamp in the row the producer
# cannot set. The newest surviving row's age is what separates "the host is emitting and this is
# its current state" from "the host stopped hours ago and every count below describes a corpse".
NEWEST_DT="$(printf '%s\n' "$SCOPED_TSV" | tail -1 | cut -f1)"
NEWEST_DT_EPOCH="$(date -u -d "$NEWEST_DT" +%s 2>/dev/null)" || NEWEST_DT_EPOCH=""
if [[ -z "$NEWEST_DT_EPOCH" ]]; then
  marker "g10_dt_unreadable" "boot=$NEWEST_BOOT"
  echo "CANNOT ESTABLISH: the newest row's ingest timestamp could not be parsed, so the producer's" >&2
  echo "           liveness cannot be established and a stale window would grade as a current one." >&2
  echo "           ACTION: check betterstack-query.sh's dt column format against this probe's read." >&2
  if stale_now "g10_dt_unreadable"; then exit 5; fi
  exit 3
fi
ROW_AGE_SECS=$(( NOW_EPOCH - NEWEST_DT_EPOCH ))
if (( ROW_AGE_SECS > PRODUCER_SILENT_SECS )); then
  marker "g11_producer_silent" "boot=$NEWEST_BOOT age_s=$ROW_AGE_SECS"
  echo "CANNOT ESTABLISH: producer_silent — the newest $MARKER row from host=$EXPECTED_HOST is" >&2
  echo "           ${ROW_AGE_SECS}s old (threshold ${PRODUCER_SILENT_SECS}s, six missed */5 ticks)." >&2
  echo "           A host that WAS emitting and stopped is indistinguishable from a dark warehouse" >&2
  echo "           once the window rolls past its last row, so the counts below are not graded." >&2
  echo "           ACTION: the heartbeat cron or its egress is down — that is its own alarm." >&2
  if stale_now "g11_producer_silent"; then exit 5; fi
  exit 3
fi

# ── THE ONE PASS ──────────────────────────────────────────────────────────────────────────────
# Every verdict field and every count comes from here, off the trusted head, on the newest boot.
# Rows arrive dt-ASCENDING, so the LAST matching row's values are the newest row's values and no
# second pass is needed to find them. Written for POSIX awk: no interval expressions, no
# [[:classes:]], no gawk extensions — Ubuntu's /usr/bin/awk is mawk.
read -r D Y P N_LUKS N_SRC N_DEVID N_EXPECTED N_BACKING < <(printf '%s\n' "$SCOPED_TSV" \
  | awk -v want="$NEWEST_BOOT" \
        -v f_luks="$F_LUKS" -v f_src="$F_SRC" -v f_devid="$F_DEVID" \
        -v f_expected="$F_EXPECTED" -v f_backing="$F_BACKING" '
      function fval(h, k,   re, s) {
        # Leftmost match, value = everything up to the next space. A field can therefore never
        # carry a space into a verdict even if the producer emitted one.
        re = "(^| )" k "=[^ ]*"
        if (!match(h, re)) return ""
        s = substr(h, RSTART, RLENGTH)
        sub(/^ /, "", s)
        return substr(s, length(k) + 2)
      }
      BEGIN { d = 0; y = 0; p = 0
              luks = "__ABSENT__"; src = "__ABSENT__"; devid = "__ABSENT__"
              expd = "__ABSENT__"; bdev = "__ABSENT__" }
      {
        # THE HEAD CUT. `: $0` makes the whole record the trusted head when the row carries no
        # tail at all; two things keep that unreachable for a non-producer row, and both are
        # load-bearing: the envelope anchor above admits only the direct-POST producer envelope,
        # and @tsv escapes an embedded newline to a literal backslash-n so one warehouse row can
        # never split into two awk records. A refactor that drops @tsv hands a crafted row a
        # fully-trusted synthetic head.
        i = index($0, " zot_last_err=")
        head = (i > 0) ? substr($0, 1, i - 1) : $0
        # MIRRORS zot_scope_to_boot, deliberately stricter than the library grep -F.
        if (!match(head, / boot_id=[0-9a-fA-F-]+/)) next
        b = substr(head, RSTART + 9, RLENGTH - 9)
        if (b != want) next
        # `absent` is deliberately NOT counted into p. See the P comment in the header: the
        # nofail mount plus the luks-open oneshot make an early-boot `absent` tick legitimate,
        # and folding it in would FAIL every correct replace. (The comment sits ABOVE the `if`
        # rather than before the `else`: a comment between a statement and its `else` is not
        # portable across awk dialects, and mawk is what runs this.)
        v = fval(head, f_luks)
        if (v != "") {
          d++
          if (v == "yes") y++
          else if (v == "no") p++
        }
        luks = (v == "") ? "__ABSENT__" : v
        src  = fval(head, f_src);      if (src  == "") src  = "__ABSENT__"
        devid = fval(head, f_devid);   if (devid == "") devid = "__ABSENT__"
        expd = fval(head, f_expected); if (expd == "") expd = "__ABSENT__"
        bdev = fval(head, f_backing);  if (bdev == "") bdev = "__ABSENT__"
      }
      END { print d, y, p, luks, src, devid, expd, bdev }')

# A missing summary line is "could not measure", never zero. LOAD-BEARING, not defensive padding:
# bash treats an EMPTY operand as false in `[[ "" -gt 0 ]]`, so a failed awk would make P read as
# "no plaintext rows" and V4/V5 would grade a measurement that never happened. This guard is the
# only thing between a dialect error and a false reading — do not simplify it away.
for _n in "${D:-}" "${Y:-}" "${P:-}"; do
  case "$_n" in
    ''|*[!0-9]*)
      marker "g12_no_counts" "boot=$NEWEST_BOOT"
      echo "CANNOT ESTABLISH: the grading pass produced no usable counts for boot $NEWEST_BOOT —" >&2
      echo "           a PROBE DEFECT (an awk dialect error, a changed row shape), not evidence in" >&2
      echo "           either direction." >&2
      if stale_now "g12_no_counts"; then exit 5; fi
      exit 3 ;;
  esac
done
N_LUKS="${N_LUKS:-__ABSENT__}"
N_SRC="${N_SRC:-__ABSENT__}"
N_DEVID="${N_DEVID:-__ABSENT__}"
N_EXPECTED="${N_EXPECTED:-__ABSENT__}"
N_BACKING="${N_BACKING:-__ABSENT__}"

# ── VERDICTS, TOP TO BOTTOM. The order is part of the property, not an implementation detail. ──

# V1 — FIRST, DELIBERATELY. A real plaintext reading must not be suppressed by a later arm (a
# malformed rendered alias, say) that would otherwise grade the same boot CANNOT ESTABLISH.
if (( P > 0 )); then
  marker "v1_plaintext_on_boot" "boot=$NEWEST_BOOT plaintext_rows=$P confirming=$Y measured=$D"
  echo "FAIL: on boot $NEWEST_BOOT, $P of $D measured row(s) read the registry store as MOUNTED" >&2
  echo "      AND NOT on a LUKS container. That reading is never explainable by a boot race (an" >&2
  echo "      unmounted store reads 'absent', which is not counted here), so it is a real" >&2
  echo "      plaintext window on the volume hcloud_volume.registry claims is encrypted." >&2
  echo "      The volume alias and the mount source are deliberately WITHHELD from this comment:" >&2
  echo "      it is public. Read them from the private Better Stack view:" >&2
  echo "      scripts/betterstack-query.sh --since 24h --grep $MARKER --limit 5000" >&2
  echo "      This must not close." >&2
  exit 1
fi

# V2 — the undelivered family. ONE state; the exit encodes the urgency of waiting rather than a
# different state, because the sweeper has no way to tell the three delivery sub-states apart
# (see the Actions-permissions note in the header).
if (( D == 0 )); then
  APPLY_BYTES="$(wc -c < "$APPLY_WF" 2>/dev/null)" || APPLY_BYTES=""
  APPLY_BYTES="${APPLY_BYTES// /}"
  APPLY_STATE="unreadable"
  case "$APPLY_BYTES" in
    ''|*[!0-9]*) APPLY_BYTES="unreadable" ;;
    *) if (( APPLY_BYTES > WORKFLOW_BYTE_LIMIT )); then APPLY_STATE="OVER"; else APPLY_STATE="UNDER"; fi ;;
  esac
  # The byte count is MESSAGE CONTENT, never a branch. A rename or a repair of that workflow must
  # not be able to change a verdict — only the text an operator reads.
  _v2_body() {
    echo "           No row on boot $NEWEST_BOOT carries a \`$F_LUKS=\` field, so the #8386 emitter" >&2
    echo "           is not running on this host. Delivery is a registry-host replace (ADR-096)." >&2
    echo "           apply-web-platform-infra.yml is $APPLY_BYTES byte(s) ($APPLY_STATE the" >&2
    echo "           ${WORKFLOW_BYTE_LIMIT} B workflow-file limit #8361 tracks)." >&2
    echo "           Re-fire delivery with:" >&2
    echo "             $REFIRE_CMD" >&2
    echo "           Run history is in the Actions tab; this probe cannot read it (the sweeper" >&2
    echo "           has no actions: read scope, so such a query would 403)." >&2
  }
  if [[ -n "$ELAPSED_DAYS" ]] && (( ELAPSED_DAYS > STALE_DAYS )); then
    marker "v2_undelivered_stale" "boot=$NEWEST_BOOT days=$ELAPSED_DAYS apply_bytes=$APPLY_BYTES"
    echo "ACTION REQUIRED: undelivered for $ELAPSED_DAYS days — this is a delivery failure, not a wait." >&2
    _v2_body
    exit 5
  fi
  if [[ -n "$ELAPSED_SECS" ]] && (( ELAPSED_SECS < FIRST_SWEEP_SECS )); then
    marker "v2_undelivered_fresh" "boot=$NEWEST_BOOT apply_bytes=$APPLY_BYTES"
    echo "TRANSIENT: the emitter is not delivered yet, and this is the first sweep past earliest." >&2
    _v2_body
    exit 2
  fi
  marker "v2_undelivered" "boot=$NEWEST_BOOT apply_bytes=$APPLY_BYTES"
  echo "CANNOT ESTABLISH: the emitter is not delivered to the running host." >&2
  _v2_body
  exit 3
fi

# V3 — a partial/truncated producer row. Without this arm an empty value reads `!= yes` and posts
# a public FAIL for what is a producer defect.
if [[ "$N_LUKS" == "__ABSENT__" ]]; then
  marker "v3_newest_field_absent" "boot=$NEWEST_BOOT measured=$D confirming=$Y"
  echo "CANNOT ESTABLISH: $D row(s) on boot $NEWEST_BOOT carry \`$F_LUKS=\`, but the NEWEST row" >&2
  echo "           does not — a partial or truncated producer row. Refusing to read a missing" >&2
  echo "           field as 'not encrypted': that would post a public FAIL for a producer defect." >&2
  if stale_now "v3_newest_field_absent"; then exit 5; fi
  exit 3
fi

# V4 — not measured encrypted on the DECLARED volume. Each disjunct is named in the marker; none
# of the VALUES is, because this comment is public.
V4_REASONS=""
_v4_add() { V4_REASONS="${V4_REASONS:+$V4_REASONS,}$1"; }
# The alias SHAPE first: an empty registry_volume_id renders `scsi-0HC_Volume_` into
# registry-luks-open.sh's DEV too, so that host genuinely has no opened mapper and FAIL is the
# true reading. It also stops `__UNREADABLE__ == __UNREADABLE__` from satisfying the equality
# disjunct below — equality alone would pass on two matching sentinels.
[[ "$N_EXPECTED" =~ $ALIAS_SHAPE ]] || _v4_add "expected_devid_malformed"
[[ "$N_LUKS" == "yes" ]] || _v4_add "store_luks_not_yes"
[[ "$N_SRC" == "$EXPECTED_SRC" ]] || _v4_add "mount_src_unexpected"
[[ "$N_DEVID" == "$N_EXPECTED" ]] || _v4_add "devid_mismatch"
if [[ -n "$V4_REASONS" ]]; then
  marker "v4_not_encrypted" "reason=$V4_REASONS boot=$NEWEST_BOOT confirming=$Y measured=$D"
  echo "FAIL: the newest row on boot $NEWEST_BOOT does not measure the registry store as LUKS on" >&2
  echo "      the Terraform-declared volume. Disjunct(s) that fired: $V4_REASONS." >&2
  echo "        expected_devid_malformed — the rendered alias does not match $ALIAS_SHAPE" >&2
  echo "        store_luks_not_yes       — the store is not measured on a LUKS container" >&2
  echo "        mount_src_unexpected     — /var/lib/zot is not mounted from the declared mapper" >&2
  echo "        devid_mismatch           — the measured volume is not the declared one" >&2
  echo "      The alias and the mount source are WITHHELD from this comment: it is public. Read" >&2
  echo "      them from the private Better Stack view:" >&2
  echo "      scripts/betterstack-query.sh --since 24h --grep $MARKER --limit 5000" >&2
  echo "      An 'absent' reading within minutes of a replace is the boot mount race and clears" >&2
  echo "      itself on the next sweep; anything else is real." >&2
  exit 1
fi

# V5 — the evidence-depth floor.
if (( Y < CONFIRM_MIN )); then
  marker "v5_boot_too_young" "boot=$NEWEST_BOOT confirming=$Y required=$CONFIRM_MIN measured=$D"
  echo "CANNOT ESTABLISH: boot $NEWEST_BOOT too young: $Y of $CONFIRM_MIN confirming rows." >&2
  echo "           The newest row measures correctly; one or two ticks is not yet a settled" >&2
  echo "           reading. This clears itself as the heartbeat runs." >&2
  if stale_now "v5_boot_too_young"; then exit 5; fi
  exit 3
fi

# ── THE LEDGER READ — ONLY HERE, after V1-V5 are excluded ─────────────────────────────────────
# Hoisting it above V5 would put its failure arm in front of every other verdict, so a missing
# ledger file would mask a real plaintext reading. Three states, never two: "could not read" and
# "read, and it is not available" are different, and collapsing them would let an unreadable
# ledger read as a pending flip.
LEDGER_STATE="$(python3 - "$LEDGER" <<'PY' 2>/dev/null
import json, sys
try:
    with open(sys.argv[1]) as fh:
        doc = json.load(fh)
    rows = [s for s in doc["stores"] if s.get("store") == "hcloud_volume.registry"]
    val = rows[0]["at_rest"]["live_verification"]
    if not isinstance(val, str):
        raise TypeError("live_verification is not a string")
except Exception:
    print("__UNREADABLE__")
else:
    print("available" if val.strip().startswith("available") else "other")
PY
)" || LEDGER_STATE="__UNREADABLE__"
case "$LEDGER_STATE" in
  available|other) : ;;
  *) LEDGER_STATE="__UNREADABLE__" ;;
esac

if [[ "$LEDGER_STATE" == "__UNREADABLE__" ]]; then
  marker "v6_ledger_unreadable" "boot=$NEWEST_BOOT confirming=$Y"
  echo "CANNOT ESTABLISH: the evidence is complete on boot $NEWEST_BOOT ($Y confirming rows), but" >&2
  echo "           scripts/encryption-posture-ledger.json could not be read for" >&2
  echo "           hcloud_volume.registry's at_rest.live_verification (missing file, malformed" >&2
  echo "           JSON, or no such row). 'Could not read' is not 'read, and it is not available'." >&2
  if stale_now "v6_ledger_unreadable"; then exit 5; fi
  exit 3
fi

if [[ "$LEDGER_STATE" == "other" ]]; then
  marker "v6_flip_ledger" "boot=$NEWEST_BOOT confirming=$Y alias=$N_EXPECTED"
  echo "ACTION REQUIRED: observed boot $NEWEST_BOOT measured encrypted on $N_EXPECTED across $Y" >&2
  echo "           row(s), backing device $N_BACKING." >&2
  echo "           Flip hcloud_volume.registry's at_rest.live_verification to \`available\` AND" >&2
  echo "           raise live_coverage_floor to 2 in a one-line PR, then this closes. TWO things," >&2
  echo "           not three: the standing store_luks alert is the deferral issue's own" >&2
  echo "           follow-through and must not hold this record hostage to its blocker." >&2
  exit 5
fi

# V7 — evidence complete AND the ledger already corrected. Exit 5, not 0: see the header.
marker "v7_evidence_complete" "boot=$NEWEST_BOOT confirming=$Y alias=$N_EXPECTED ledger=available"
echo "ACTION REQUIRED: evidence complete — boot $NEWEST_BOOT measured encrypted on the declared" >&2
echo "           volume $N_EXPECTED across $Y row(s) (backing device $N_BACKING, mount source" >&2
echo "           the declared mapper), and the ledger reads \`available\`." >&2
echo "           Closing #8386 is a REVIEWED decision, taken after the boot is confirmed in the" >&2
echo "           Better Stack read. This probe deliberately does not close it: source 2457081 is" >&2
echo "           shared and multi-tenant with one ingest token, and host= / boot_id= are" >&2
echo "           producer-controlled inside the message, so three producer-shaped rows are" >&2
echo "           forgeable by any holder of that token. That is enough authority to say 'a human" >&2
echo "           should look'; it is not enough to auto-close a security tracker." >&2
exit 5
