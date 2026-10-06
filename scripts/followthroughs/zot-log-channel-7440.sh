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
#   0 = PASS       envelope rows observed on the newest real boot AND the positive control present.
#   2 = TRANSIENT  not delivered, delivered-but-silent, below floor, control missing,
#                  channel dark, or ANY auth/query/decode failure. Each prints a DISTINCT reason —
#                  an unprovisioned credential must never read as "not yet delivered".
#   3 = CANNOT ESTABLISH   the newest boot cannot be derived, the pass emitted nothing usable, a
#                  credential-shaped row exists OUTSIDE the gradable span, a boundary/newest
#                  timestamp is missing or unparseable, the now-seam env is malformed, or the
#                  producer has gone silent mid-window. Added 2026-10 (#8278): a branch that
#                  refuses to assert a delivery or leak state must not ship under a heading that
#                  asserts one. Same disposition as 2 (issue stays open).
#   1 = FAIL       emitted ONLY when a credential shape is found in the channel's GRADED span.
#                  This is the one carve-out and it is intentional: a leak is a REGRESSION, not a
#                  not-yet, and at this plan's `single-user incident` brand-survival threshold it
#                  must reopen and comment. Everywhere else exit 1 is forbidden because it reopens
#                  daily.
#
# GUARD CONTRACT (#8278 — the split-span defect this revision removes). Before this fix the
# verdict and its delivery evidence came from DIFFERENT SPANS: the exit-1 arm graded leaks over
# an unscoped 30-minute window while delivery was established from a SEPARATE SOLEUR_ZOT_LOG_BOOT
# marker query over --since 72h. A window straddling a replace mixed two host generations, so a
# public FAIL — or a close — could rest on evidence about a dead host. The 72h query is DELETED;
# in-window SOLEUR_ZOT_LOG_BOOT/_DROPPED rows now arrive through the same SOLEUR_ZOT_LOG result
# set (the warehouse LIKE is a substring match). The shape, ported from
# scripts/followthroughs/registry-luks-live-8386.sh and ADR-211:
#
#   - The newest real boot is derived from host-scoped STAMPED rows only: control rows (trusted
#     head cut at ` zot_last_err=`) and SOLEUR_ZOT_LOG_BOOT markers (own host= field). A
#     SOLEUR_ZOT_LOG_DROPPED row carries boot_id but NO host=, so it corroborates and counts on a
#     boot already derived but can never SELECT one.
#   - The boundary B0 is the earliest ingest dt among stamped rows on that boot; an in-window
#     BOOT marker on the boot tightens it to ~provision time. Envelope rows carry no boot_id, so
#     their scope is the boundary, not a field — the dt column is ingest-assigned, the one field
#     the producer cannot set.
#   - ONE awk pass over the dt-sorted, tag-carried rows of BOTH channels produces every value a
#     verdict keys on — the boot scope, the boundary, the delivery proof, every count, and the
#     leak grade. A second pass over the same rows, a field read outside this pass, or a read
#     past the trusted cut is the defect this file's Guard Contract forbids.
#
# Residual, recorded not hidden: boundary precision is ±5 min (heartbeat cadence) — an envelope
# row in the (replace, first-heartbeat) gap without an in-window marker is conservatively
# UNGRADED rather than mis-graded.
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
# (zot-upload-ceiling-7556.sh) queries a 7-day ceiling window and MUST keep the archive arm. Do
# not copy flags between the days-old and minutes-old cases.
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
QUERY="${ZOT_LOG_7440_QUERY_BIN:-$REPO_ROOT/scripts/betterstack-query.sh}"

ENVELOPE_PREFIX="SOLEUR_ZOT_LOG shipper=zot-log-shipper host="
BOOT_MARKER="SOLEUR_ZOT_LOG_BOOT"
DROP_MARKER="SOLEUR_ZOT_LOG_DROPPED"
CONTROL_MARKER="SOLEUR_ZOT_DISK"
# Encoding-safe: no quote, no colon, so it survives the double-encoded `raw` as a LIKE.
ZOT_ONLY_SUBSTR="zotregistry.dev/zot/v2/pkg/api"
EXPECTED_HOST="${ZOT_LOG_7440_HOST:-soleur-registry}"
# The host token is interpolated into an ERE (hostok) — a metachar would weaken host isolation.
# Reject anything outside the hostname alphabet rather than trusting the caller's value.
if [[ ! "$EXPECTED_HOST" =~ ^[a-zA-Z0-9._-]+$ ]]; then
  echo "TRANSIENT: reason=config_invalid — ZOT_LOG_7440_HOST ('$EXPECTED_HOST') is not a" >&2
  echo "           hostname-alphabet value; refusing to interpolate it into the isolation regex." >&2
  exit 2
fi
# Two missed */5 heartbeats. A host that was emitting and stopped reads "dark residue", not
# "current state" — the freshness gate below refuses to grade a corpse.
PRODUCER_SILENT_SECS=600

# NOTE: the pre-delivery boot_id baseline that used to live here is GONE (#7444 R20). F-7
# replaced boot_id drift with the presence of the log_shipper_post_fail= key as the delivery
# discriminator, which left the constant dead — and a dead constant with five lines of rationale
# describing it as the wait/act discriminator reads as though it were still load-bearing.

WINDOW="${ZOT_LOG_7440_WINDOW:-30m}"
WINDOW_MIN="${ZOT_LOG_7440_WINDOW_MIN:-30}"
LIMIT="${ZOT_LOG_7440_LIMIT:-400}"

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

# The decode/sort/pass toolchain: a missing jq/sort/awk/date would produce an EMPTY decode, and an
# empty decode is indistinguishable from a dark warehouse — a tool failure must not read as
# evidence about the channel. Preflighted here so the failure names the tool, not the data.
for _tool in jq awk sort date; do
  command -v "$_tool" >/dev/null 2>&1 || {
    echo "TRANSIENT: reason=query_tool_missing — $_tool is not on PATH; the decode/grade" >&2
    echo "           pipeline cannot run, and its absence is not evidence about the channel." >&2
    exit 2
  }
done

# --- decode helper: JSONEachRow -> .raw (a JSON *string*) -> .message ------------------------
# THE FILTER IS TOTAL — no input shape may error it. `fromjson?` skips non-JSON noise; `objects`
# drops valid-JSON non-objects (a bare scalar would make `.raw` an index error); the inner
# `fromjson? // {} | objects` pair does the same for a non-object .raw; `.message?` and `dt?`
# are error-suppressing index reads; `tostring` makes a non-string member safe for @tsv; and the
# dt test() coerces any non-`YYYY-MM-DD HH:` shape to "" — an empty dt sorts FIRST and lands the
# row in the conservative pre-boundary bucket. A filter that errors mid-stream HALTS the channel
# on jq <= 1.7: every later row — including a leak row — would silently never reach the pass.
# `dt` IS CARRIED THROUGH as a TSV column beside a channel tag: it is the only field in the row
# the producer cannot set, and it is the sort/boundary key that binds the graded set to the
# newest real boot (#8278). @tsv is LOAD-BEARING: it escapes an embedded newline to a literal
# backslash-n, so one warehouse row can never split into two awk records — dropping it hands a
# crafted row a fully-trusted synthetic head.
decode_tsv() { # $1 = one-letter channel tag
  jq -R -r --arg tag "$1" \
    'fromjson? | objects | select(.raw != null) |
     [ (((.dt? // "") | tostring) | if test("^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]+)?$") then . else "" end),
       $tag,
       ((((.raw? // "") | fromjson?) // {} | objects | .message? // "") | tostring) ] | @tsv' \
    2>/dev/null
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

# TWO QUERIES, ONE SPAN. --grep SOLEUR_ZOT_LOG is a substring LIKE, so it returns envelope rows,
# SOLEUR_ZOT_LOG_DROPPED rows AND SOLEUR_ZOT_LOG_BOOT markers alike — all on the SAME --since
# "$WINDOW" --no-archive window. There is no second marker query: the previous --since 72h arm
# was the split span this revision exists to remove (#8278).
raw_log=$(run_query "SOLEUR_ZOT_LOG")
if [[ "$raw_log" == QUERYFAIL* ]]; then
  echo "TRANSIENT: reason=query_failed — betterstack-query.sh exited $(queryfail_rc "$raw_log") querying" >&2
  [[ -n "$(queryfail_msg "$raw_log")" ]] && echo "           $(queryfail_msg "$raw_log")" >&2
  echo "           SOLEUR_ZOT_LOG over $WINDOW. No claim is made about the channel." >&2
  exit 2
fi

control_raw=$(run_query "$CONTROL_MARKER")
if [[ "$control_raw" == QUERYFAIL* ]]; then
  echo "TRANSIENT: reason=query_failed — the control query exited $(queryfail_rc "$control_raw")." >&2
  [[ -n "$(queryfail_msg "$control_raw")" ]] && echo "           $(queryfail_msg "$control_raw")" >&2
  exit 2
fi

# --- THE ONE PASS ----------------------------------------------------------------------------
# Both channels decode to (dt, tag, message) TSVs, are merged and sorted ascending on the
# ingest-assigned dt, and feed ONE awk program. The pass holds the rows and, in END:
#   1. derives NEWEST_BOOT from the newest host-scoped STAMPED row (control head, or a
#      SOLEUR_ZOT_LOG_BOOT marker's own host=; never a _DROPPED row — it carries no host=);
#   2. derives B0, the earliest stamped dt on that boot (an in-window marker tightens it to
#      ~provision time);
#   3. produces every verdict-keyed value on that boot's span: all counts, the delivery fields,
#      and the leak grade — in-scope envelope rows at dt >= B0, pre-boundary rows counted apart.
# Written for POSIX awk: no interval expressions, no [[:classes:]], no gawk extensions — the
# runner awk is mawk. The integer guard below is what keeps a dialect error on the
# CANNOT-ESTABLISH side, never a false verdict.
SUMMARY="$({ printf '%s\n' "$raw_log"     | decode_tsv L
            printf '%s\n' "$control_raw" | decode_tsv C; } \
  | LC_ALL=C sort \
  | awk -F'\t' \
      -v host="$EXPECTED_HOST" \
      -v envpfx="${ENVELOPE_PREFIX}${EXPECTED_HOST} " \
      -v ctlm="${CONTROL_MARKER} " \
      -v bootm="${BOOT_MARKER} " \
      -v dropm="${DROP_MARKER} " \
      -v zottok="$ZOT_ONLY_SUBSTR" '
    function head(m,   i) {
      # THE TRUSTED REGION: verdict fields come only from the head before the free-text
      # ` zot_last_err=` tail. A crafted tail cannot supply a boot_id, a host= or a reporter
      # field. The `: m` fallback makes the whole MESSAGE the head when there is no tail —
      # marker rows carry no tail at all, and every classification below already anchors on the
      # producer envelope at offset 0, so a non-producer row never reaches a verdict field.
      i = index(m, " zot_last_err=")
      return (i > 0) ? substr(m, 1, i - 1) : m
    }
    function fval(h, k,   re, s) {
      # Leftmost match, value = everything up to the next space — a field can therefore never
      # carry a space into a verdict even if the producer emitted one. The value is CLAMPED to
      # the field alphabet at 40 chars: these strings are echoed onto a public issue, so the
      # producer may supply only a bounded, safe-charset token.
      re = "(^| )" k "=[^ ]*"
      if (!match(h, re)) return ""
      s = substr(h, RSTART, RLENGTH)
      sub(/^ /, "", s)
      s = substr(s, length(k) + 2)
      gsub(/[^A-Za-z0-9._-]/, "", s)
      return substr(s, 1, 40)
    }
    function hostok(h) { return h ~ ("(^| )host=" host "($| )") }
    function bootof(h) {
      # First char must be hex — the class is what excludes `unknown`, the producer
      # /proc-unreadable DEFAULT sentinel (u, n, k, w are absent from [0-9a-fA-F]) — and it
      # also keeps a degenerate "-" fragment from aliasing the no-boot sentinel.
      if (!match(h, / boot_id=[0-9a-fA-F][0-9a-fA-F-]*/)) return ""
      return substr(h, RSTART + 9, RLENGTH - 9 > 40 ? 40 : RLENGTH - 9)
    }
    function authleak(m,   s, rest, i, v) {
      # Per-OCCURRENCE, not per-message: walk every `Authorization:[…` header on the row and flag
      # only a value that is NEITHER the zot asterisk mask NOR our REDACTED marker. The value is
      # cut at `]` — NOT at space — because headers pack comma-separated inside one non-space
      # `headers:{…}` blob, and a space-bounded read would eat `],X-Fwd:[Authorization:` whole,
      # hiding a real credential behind a decoy on the same row (fixture S13 measures it).
      s = m
      while (match(s, /Authorization:\[/)) {
        rest = substr(s, RSTART + RLENGTH)
        i = index(rest, "]")
        v = (i > 0) ? substr(rest, 1, i - 1) : rest
        sub(/ .*/, "", v)
        # The mask is three-or-more asterisks (the zot redact emits ******) — a 1-2 asterisk
        # prefix is NOT a mask and must still flag. An EMPTY value (`Authorization:[]`) is a
        # malformed header, not a credential — skip it, never flag it.
        if (v != "" && v !~ /^(\*\*\*|REDACTED)/) return 1
        if (i == 0) return 0
        s = substr(rest, i)
      }
      return 0
    }
    function shapeleak(m,   s, rest, run, t) {
      if (m ~ /\$2[aby]\$[0-9][0-9]\$/) return 1
      # Per-OCCURRENCE like authleak: a leading short/decoy `dp.st.x` must not mask a real token
      # later in the row. No interval expressions in POSIX awk: measure the run after each
      # prefix — but SUBSTANCE, not length: `.` is in the token charset, so 20+ dots of padding
      # would otherwise read as a token and a crafted request path could post a public FAIL on
      # demand. Require >=16 non-separator chars in SOME occurrence run.
      s = m
      while (match(s, /dp\.(pt|st|sa|ct)\./)) {
        rest = substr(s, RSTART + RLENGTH)
        run = rest
        sub(/[^A-Za-z0-9._-].*$/, "", run)
        t = run
        gsub(/[._-]/, "", t)
        if (length(t) >= 16) return 1
        s = substr(s, RSTART + RLENGTH)
      }
      return 0
    }
    # CLASSIFY ONCE, in the main rule — a triplicated predicate is the defect vector this
    # rewrite exists to remove: each END traversal reads Rcls[]/Risctl[]/Rhost[]/Rboot[] instead
    # of re-deriving the classification, so the offset-0 envelope anchors and the trusted-head
    # cut apply to EVERY phase identically.
    {
      nr++
      Rdt[nr] = $1
      Rtag[nr] = $2
      # +3 = skip the dt field, the tag field, and the two tab separators between them.
      m = substr($0, length($1) + length($2) + 3)
      Rmsg[nr] = m
      if (Rtag[nr] == "C") {
        # A C-channel row is whatever --grep returned for SOLEUR_ZOT_DISK — a substring LIKE,
        # so the marker can sit ANYWHERE in the message (a quoted row, an injected request
        # header echo). Only a message STARTING with the marker is a reporter row.
        Risctl[nr] = (index(m, ctlm) == 1)
        h = head(m)
        Rhost[nr] = hostok(h)
        Rboot[nr] = bootof(h)
        Rcls[nr] = "ctl"
      } else {
        if (index(m, dropm) == 1) {
          Rcls[nr] = "drop"
          Rboot[nr] = bootof(head(m))
        } else if (index(m, bootm) == 1) {
          Rcls[nr] = "boot"
          h = head(m)
          Rhost[nr] = hostok(h)
          Rboot[nr] = bootof(h)
        } else if (index(m, envpfx) == 1) {
          Rcls[nr] = "env"
        } else {
          Rcls[nr] = "other"
        }
      }
    }
    END {
      # (1) NEWEST BOOT — newest host-scoped stamped row, newest first. "Stamped" means
      # boot_id present in the trusted region; "host-scoped" means host= matches. A
      # _DROPPED row can never reach here: it is class "drop", and only "ctl"/"boot" select.
      nb = ""
      for (i = nr; i >= 1; i--) {
        if (Rtag[i] == "C") {
          if (Risctl[i] && Rhost[i] && Rboot[i] != "") { nb = Rboot[i]; break }
        } else if (Rcls[i] == "boot" && Rhost[i] && Rboot[i] != "") { nb = Rboot[i]; break }
      }
      # (2) B0 — earliest stamped row on the newest boot (a marker counts, so the boundary
      #     tightens to ~provision time). The selecting row must carry a real dt: an empty
      #     one would make b0="" and ungrade the whole span — skip it, take the next.
      b0 = ""
      if (nb != "") {
        for (i = 1; i <= nr; i++) {
          if (Rdt[i] == "") continue
          if (Rtag[i] == "C") {
            if (Risctl[i] && Rhost[i] && Rboot[i] == nb) { b0 = Rdt[i]; break }
          } else if (Rcls[i] == "boot" && Rhost[i] && Rboot[i] == nb) { b0 = Rdt[i]; break }
        }
      }
      # (3) Every verdict value, on the bounded span.
      n_ctl=0; n_env=0; n_env_pre=0; n_drop=0; n_boot_marker=0
      n_zot=0; n_gcs=0; n_gcd=0; n_gcb=0; n_patch=0
      n_auth=0; n_shape=0; n_leak_out=0; n_other=0
      pf_present=0; pf_val=""; last_ok=""; dcum=""; dseq=""
      for (i = 1; i <= nr; i++) {
        m = Rmsg[i]; d = Rdt[i]
        if (Rtag[i] == "C") {
          if (!Risctl[i] || !Rhost[i]) { n_other++; continue }
          n_ctl++
          if (nb != "" && Rboot[i] == nb) {
            h = head(m)
            v = fval(h, "log_shipper_post_fail");      if (v != "") { pf_present=1; pf_val=v }
            v = fval(h, "log_shipper_last_ok_age_s");  if (v != "") last_ok=v
            v = fval(h, "log_shipper_dropped_cum");    if (v != "") dcum=v
            v = fval(h, "log_shipper_drop_seq");       if (v != "") dseq=v
          }
          continue
        }
        if (Rcls[i] == "drop") {
          # Stamped but NOT host-verifiable: counts only on a boot already derived. A drop row
          # that cannot be attributed (no boot derived, or a foreign boot) is still evidence the
          # read path answered — count it as unclassifiable, never silently drop it.
          if (nb != "" && Rboot[i] == nb) n_drop++
          else n_other++
          continue
        }
        if (Rcls[i] == "boot") {
          if (nb != "" && Rhost[i] && Rboot[i] == nb) n_boot_marker++
          else n_other++
          continue
        }
        if (Rcls[i] == "env") {
          # Envelope rows carry no boot_id — their scope is the boundary, not a field.
          if (b0 != "" && d >= b0) {
            n_env++
            if (index(m, zottok) > 0) n_zot++
            if (index(m, "message:executing gc") > 0) n_gcs++
            if (index(m, "message:gc successfully completed") > 0) n_gcd++
            if (index(m, "message:garbage collected blobs") > 0) n_gcb++
            if (index(m, "message:PatchBlobUpload") > 0) n_patch++
            if (authleak(m)) n_auth++
            if (shapeleak(m)) n_shape++
          } else {
            n_env_pre++
            # A credential shape OUTSIDE the gradable span is counted separately — it is
            # evidence that exists but cannot be attributed to the live host generation.
            if (authleak(m) || shapeleak(m)) n_leak_out++
          }
          continue
        }
        n_other++
      }
      # (4) PRODUCER FRESHNESS KEY — the newest row a producer on THIS host could have emitted:
      # envelope rows (the prefix carries host=), host-scoped ctl/boot rows, and _DROPPED rows
      # attributed to the derived boot. Noise — "other" rows, foreign-host reporters — must not
      # feed it: a fresh marker-quoting row would otherwise keep producer_silent permanently
      # masked on a dead host (the LIKE grep is not host-scoped; the source is multi-tenant).
      pdt = ""
      for (i = 1; i <= nr; i++) {
        if (Rdt[i] == "") continue
        if (Rcls[i] == "env" \
            || (Rcls[i] == "ctl"  && Risctl[i] && Rhost[i]) \
            || (Rcls[i] == "boot" && Rhost[i]) \
            || (Rcls[i] == "drop" && nb != "" && Rboot[i] == nb))
          pdt = Rdt[i]
      }
      # The summary is k=v pairs, not positionals: a 21-field whitespace read silently
      # reorders on any insertion, while a keyed line is order-insensitive and a missing key
      # fails the completeness guard below instead of shifting fields. (An unrecognised extra
      # key is ignored — additive forward-compat; the dangerous direction is the missing key.)
      # dt carries a space ("YYYY-MM-DD HH:MM:SS.ffffff"); emit timestamps in T-form so no
      # value ever contains a space.
      sub(/ /, "T", b0)
      ndt = (pdt != "") ? pdt : "-"
      sub(/ /, "T", ndt)
      print "n_ctl=" n_ctl, "n_env=" n_env, "n_env_pre=" n_env_pre, "n_drop=" n_drop, \
            "n_boot_marker=" n_boot_marker, "n_zot=" n_zot, "n_gcs=" n_gcs, "n_gcd=" n_gcd, \
            "n_gcb=" n_gcb, "n_patch=" n_patch, "n_auth=" n_auth, "n_shape=" n_shape, \
            "n_leak_out=" n_leak_out, "n_other=" n_other, "pf_present=" pf_present, \
            "pf_val=" (pf_val == "" ? "-" : pf_val), "last_ok=" (last_ok == "" ? "-" : last_ok), \
            "dcum=" (dcum == "" ? "-" : dcum), "dseq=" (dseq == "" ? "-" : dseq), \
            "nb=" (nb == "" ? "-" : nb), "b0=" (b0 == "" ? "-" : b0), "ndt=" ndt
    }')"

# Named binding — a summary field is trusted only under its own key; a missing or unknown key
# fails the completeness guard below instead of silently shifting every field after it.
_seen=0
N_CTL=""; N_ENV=""; N_ENV_PRE=""; N_DROP=""; N_BOOT_MARKER=""; N_ZOT=""; N_GCS=""; N_GCD=""
N_GCB=""; N_PATCH=""; N_AUTH=""; N_SHAPE=""; N_LEAK_OUT=""; N_OTHER=""; PF_PRESENT=""
PF_VAL=""; LAST_OK=""; DCUM=""; DSEQ=""; NEWEST_BOOT=""; B0_DT=""; NEWEST_DT=""
for _kv in $SUMMARY; do
  _k="${_kv%%=*}"; _v="${_kv#*=}"
  case "$_k" in
    n_ctl)         N_CTL="$_v";         _seen=$(( _seen + 1 ));;
    n_env)         N_ENV="$_v";         _seen=$(( _seen + 1 ));;
    n_env_pre)     N_ENV_PRE="$_v";     _seen=$(( _seen + 1 ));;
    n_drop)        N_DROP="$_v";        _seen=$(( _seen + 1 ));;
    n_boot_marker) N_BOOT_MARKER="$_v"; _seen=$(( _seen + 1 ));;
    n_zot)         N_ZOT="$_v";         _seen=$(( _seen + 1 ));;
    n_gcs)         N_GCS="$_v";         _seen=$(( _seen + 1 ));;
    n_gcd)         N_GCD="$_v";         _seen=$(( _seen + 1 ));;
    n_gcb)         N_GCB="$_v";         _seen=$(( _seen + 1 ));;
    n_patch)       N_PATCH="$_v";       _seen=$(( _seen + 1 ));;
    n_auth)        N_AUTH="$_v";        _seen=$(( _seen + 1 ));;
    n_shape)       N_SHAPE="$_v";       _seen=$(( _seen + 1 ));;
    n_leak_out)    N_LEAK_OUT="$_v";    _seen=$(( _seen + 1 ));;
    n_other)       N_OTHER="$_v";       _seen=$(( _seen + 1 ));;
    pf_present)    PF_PRESENT="$_v";    _seen=$(( _seen + 1 ));;
    pf_val)        PF_VAL="$_v";        _seen=$(( _seen + 1 ));;
    last_ok)       LAST_OK="$_v";       _seen=$(( _seen + 1 ));;
    dcum)          DCUM="$_v";          _seen=$(( _seen + 1 ));;
    dseq)          DSEQ="$_v";          _seen=$(( _seen + 1 ));;
    nb)            NEWEST_BOOT="$_v";   _seen=$(( _seen + 1 ));;
    b0)            B0_DT="$_v";         _seen=$(( _seen + 1 ));;
    ndt)           NEWEST_DT="$_v";     _seen=$(( _seen + 1 ));;
  esac
done

# THE INTEGER GUARD — "could not measure" is never zero. A missing or non-integer summary field
# means the pass did not run to completion (a dialect error, a changed row shape), and bash
# treats an empty operand as false in every arithmetic test — without this guard a failed awk
# would read as "zero rows everywhere" and post verdicts on a measurement that never happened.
# This is the only thing between a broken pass and a false verdict; do not simplify it away.
_guard_ok=1
[[ "$_seen" -eq 22 ]] || _guard_ok=0
for _n in "$N_CTL" "$N_ENV" "$N_ENV_PRE" "$N_DROP" "$N_BOOT_MARKER" "$N_ZOT" "$N_GCS" "$N_GCD" \
          "$N_GCB" "$N_PATCH" "$N_AUTH" "$N_SHAPE" "$N_LEAK_OUT" "$N_OTHER" "$PF_PRESENT"; do
  case "$_n" in ''|*[!0-9]*) _guard_ok=0 ;; esac
done
for _s in "$PF_VAL" "$LAST_OK" "$DCUM" "$DSEQ" "$NEWEST_BOOT" "$B0_DT" "$NEWEST_DT"; do
  case "$_s" in '') _guard_ok=0 ;; esac
done
if [[ "$_guard_ok" -ne 1 ]]; then
  echo "CANNOT ESTABLISH: the grading pass produced no usable summary — a probe defect (an awk" >&2
  echo "           dialect error, a changed row shape), not evidence in either direction." >&2
  exit 3
fi

# --- CREDENTIAL-SHAPE SCAN, BOOT-SCOPED: the sole exit-1 arm --------------------------------
# Grades ONLY envelope rows at dt >= the newest boot's boundary. Three shapes: (a) an
# Authorization value that is neither zot's ****** mask nor our REDACTED marker; (b) a Doppler
# token prefix; (c) a bcrypt hash prefix. Counts only — the values are never echoed.
n_leak=$(( N_AUTH + N_SHAPE ))
if [[ "$n_leak" -gt 0 ]]; then
  echo "FAIL: reason=credential_shape_in_channel boot=${NEWEST_BOOT} — ${n_leak} shipped row(s) in" >&2
  echo "      the newest boot's span carry something shaped like a credential. This is the ONE" >&2
  echo "      arm that exits 1, because a leak is a regression rather than a not-yet, and the" >&2
  echo "      registry's push credential protects the image supply chain — a leaked one is a" >&2
  echo "      SUPPLY-CHAIN exposure, not a log-hygiene defect. Every holder of BETTERSTACK_QUERY_*" >&2
  echo "      can read these rows." >&2
  echo "      Next: rotate the affected credential FIRST, then fix redact() in" >&2
  echo "      apps/web-platform/infra/cloud-init-registry.yml." >&2
  echo "      COUNTS ONLY — the matching values are deliberately NOT echoed, because this probe's" >&2
  echo "      output is posted verbatim as a comment on a public issue by the sweeper, so printing" >&2
  echo "      them would copy the leak out of one channel and into two more:" >&2
  echo "        unmasked_authorization_rows=${N_AUTH} token_or_hash_shaped_rows=${N_SHAPE}" >&2
  exit 1
fi

# A credential shape OUTSIDE the gradable span is not a FAIL — it cannot be attributed to the
# live host generation — and it is not silence either. CANNOT ESTABLISH, with the count named
# and an action: these rows are directly queryable and must be read as a live leak until ruled
# out — the residual case is a real leak on the NEW boot landing inside the heartbeat gap.
if [[ "$N_LEAK_OUT" -gt 0 ]]; then
  if [[ "$B0_DT" == "-" ]]; then
    echo "CANNOT ESTABLISH: ungraded_credential_rows=${N_LEAK_OUT} — credential-shaped envelope" >&2
    echo "           row(s) exist, but NO gradable boundary could be derived (no usable boot_id," >&2
    echo "           or no readable dt on the stamped rows). Nothing can be attributed to any" >&2
    echo "           generation — this is a producer-side regression in the boot_id/dt fields." >&2
  else
    echo "CANNOT ESTABLISH: ungraded_credential_rows=${N_LEAK_OUT} — credential-shaped envelope" >&2
    echo "           row(s) sit OUTSIDE the newest boot's graded span (dt < ${B0_DT}). A leak" >&2
    echo "           cannot be attributed to the live host generation from these rows, and the" >&2
    echo "           counts-only rule forbids grading it as this boot's own. This is deliberately" >&2
    echo "           neither FAIL (unattributed evidence) nor PASS (a credential shape was seen)." >&2
  fi
  echo "           ACTION: read these rows directly — scripts/betterstack-query.sh --since ${WINDOW}" >&2
  echo "           --grep SOLEUR_ZOT_LOG — and treat any real credential shape as a LIVE leak until" >&2
  echo "           ruled out. If the rows sit in the (replace, first-heartbeat) gap they may belong" >&2
  echo "           to the current boot; rotate on doubt." >&2
  exit 3
fi

# --- zero rows on the newest boot -----------------------------------------------------------
if [[ "$N_ENV" -eq 0 && "$N_ENV_PRE" -eq 0 && "$N_CTL" -eq 0 && "$N_BOOT_MARKER" -eq 0 && "$N_DROP" -eq 0 ]]; then
  echo "TRANSIENT: reason=channel_dark — zero envelope rows AND zero ${CONTROL_MARKER} control" >&2
  echo "           rows in the last ${WINDOW}. The control lands on this source every 5 min." >&2
  if [[ "$N_OTHER" -gt 0 ]]; then
    echo "           ${N_OTHER} row(s) matched the greps but fit no producer shape (a marker" >&2
    echo "           mention, a foreign host, an unattributable _DROPPED/_BOOT row) — the read path" >&2
    echo "           DID answer; check host= drift and forwarder noise before credentials." >&2
  else
    echo "           An empty control means the READ PATH is not answering. This probe has measured" >&2
    echo "           NOTHING about the channel — do NOT read it as 'the shipper is absent'." >&2
  fi
  echo "           Next: check the Better Stack query credentials and the hot-window bound" >&2
  echo "           before concluding anything about the host." >&2
  exit 2
fi

# --- PRODUCER FRESHNESS — before ANY verdict on window content --------------------------------
# NEWEST_DT is scoped to producer-attributable rows (envelope rows carry host= in the prefix;
# stamped rows must host-match; _DROPPED must sit on the derived boot) precisely so a fresh
# marker-quoting NOISE row cannot refresh the gate while the producer is dead — if the newest
# producer row is older than two */5 heartbeat ticks, every liveness-asserting verdict below
# (control_missing, delivered_but_silent, PASS) would be a misdiagnosis posted as fact. Same
# gate shape as registry-luks-live-8386.sh's producer_silent. ZOT_LOG_7440_NOW is the test seam
# — the fixture suite runs fixed dts; the sweeper's env -i never sets it. The "-" sentinel must
# never reach date(1): GNU date parses "-" as today 00:00 UTC and EXITS 0. An in-span credential
# leak still exits 1 ABOVE this gate deliberately: a leak is content evidence, not a liveness
# claim, and a stale-window leak is still a live credential. Runs before no-boot/control_missing
# so a stale window never dresses up as a live diagnosis.
if [[ "$NEWEST_DT" == "-" ]]; then
  echo "CANNOT ESTABLISH: no producer-attributable row carries a readable dt — classified rows" >&2
  echo "           with empty/malformed dt, or only unclassifiable noise, were returned. Freshness" >&2
  echo "           and span are unmeasurable." >&2
  exit 3
fi
NDT_EPOCH="$(date -u -d "$NEWEST_DT" +%s 2>/dev/null)" || NDT_EPOCH=""
if [[ -z "$NDT_EPOCH" ]]; then
  echo "CANNOT ESTABLISH: the newest producer row's ingest time (${NEWEST_DT}) could not be" >&2
  echo "           parsed — the bounded span is unmeasurable." >&2
  exit 3
fi
NOW_EPOCH="${ZOT_LOG_7440_NOW:-$(date -u +%s)}"
if [[ ! "$NOW_EPOCH" =~ ^[0-9]+$ ]]; then
  echo "CANNOT ESTABLISH: ZOT_LOG_7440_NOW is set but not an epoch (${NOW_EPOCH}) — a probe-env" >&2
  echo "           defect, not evidence. Under the sweeper's env -i this arm is unreachable." >&2
  exit 3
fi
ROW_AGE_SECS=$(( NOW_EPOCH - NDT_EPOCH ))
if (( ROW_AGE_SECS > PRODUCER_SILENT_SECS )); then
  echo "CANNOT ESTABLISH: reason=producer_silent boot=${NEWEST_BOOT} — the newest producer row is" >&2
  echo "           ${ROW_AGE_SECS}s old (threshold ${PRODUCER_SILENT_SECS}s, two missed */5 ticks)." >&2
  echo "           The residue in this window describes a host that has stopped emitting, not its" >&2
  echo "           current state — no verdict is graded on a corpse." >&2
  exit 3
fi

# Envelope content exists but the heartbeat does not — preserved AHEAD of boot derivation: the
# envelope proves the read path answers while the reporter's silence masks a separate incident.
if [[ "$N_CTL" -eq 0 && ( "$N_ENV" -gt 0 || "$N_ENV_PRE" -gt 0 ) ]]; then
  echo "TRANSIENT: reason=control_missing — envelope row(s) present (in-span=${N_ENV}," >&2
  echo "           pre_boundary=${N_ENV_PRE}), so the channel is" >&2
  echo "           demonstrably LIVE, but zero ${CONTROL_MARKER} control rows in the last ${WINDOW}." >&2
  echo "           Deliberately NOT channel_dark: the envelope proves the read path answers, so" >&2
  echo "           this masks a SEPARATE live incident — the 5-min disk reporter has stopped." >&2
  echo "           Next: investigate the disk heartbeat cron, not this channel." >&2
  exit 2
fi

# No usable boot_id anywhere means the newest boot cannot be derived, so nothing is gradable.
# exit 3, NOT 2: the sweeper renders 2 as "NOT YET" and 3 as "CANNOT ESTABLISH", and a branch
# whose whole purpose is refusing to assert a delivery or leak state must not ship under a
# heading that asserts one.
if [[ "$NEWEST_BOOT" == "-" ]]; then
  echo "CANNOT ESTABLISH: no usable boot_id on any host-scoped stamped row — every boot_id is" >&2
  echo "           absent or the 'unknown' /proc-fallback sentinel. The newest real boot cannot" >&2
  echo "           be derived, so delivery cannot be established and the leak grade cannot be" >&2
  echo "           scoped." >&2
  echo "           ACTION: rows present with no real boot_id is a PRODUCER regression — check the" >&2
  echo "           \`boot_id=\` field in cloud-init-registry.yml's LINE= emitter." >&2
  exit 3
fi

# --- BOUNDARY MEASURABILITY (a derived boot whose stamped rows carry no readable dt) ----------
# The "-" sentinel must never reach date(1): GNU date parses "-" as today 00:00 UTC and EXITS 0,
# which would silently fabricate a span instead of refusing one. nb != "" here means a stamped
# row exists, so a missing B0 means its rows carry no readable dt — every envelope row then sits
# unbounded in n_env_pre, and no liveness claim below is honest.
if [[ "$B0_DT" == "-" ]]; then
  echo "CANNOT ESTABLISH: a boot was derived (${NEWEST_BOOT}) but its boundary timestamp is" >&2
  echo "           missing — the stamped rows on it carry no readable dt, so the graded span" >&2
  echo "           cannot be measured and no count is trustworthy." >&2
  exit 3
fi

# --- zero envelope rows ON THE NEWEST BOOT: delivery discrimination --------------------------
# GATED ON A KEY THAT ONLY THE NEW CLOUD-INIT CAN PRODUCE, read on the newest boot's OWN rows:
# log_shipper_post_fail= present on a control row of NEWEST_BOOT, a _DROPPED or _BOOT row on
# NEWEST_BOOT. boot_id drift is NOT evidence: the private-NIC guard reboots as a convergence
# primitive and runcmd is per-instance, so drift without a replace proves nothing (#7444 F-7).
delivered=0
delivery_evidence="none"
if [[ "$PF_PRESENT" -eq 1 ]]; then
  delivered=1
  delivery_evidence="postfail_on_boot(log_shipper_post_fail=${PF_VAL})"
elif [[ "$N_DROP" -gt 0 ]]; then
  delivered=1
  delivery_evidence="drop_row_on_boot(${N_DROP})"
elif [[ "$N_BOOT_MARKER" -gt 0 ]]; then
  delivered=1
  delivery_evidence="boot_marker_on_boot(${N_BOOT_MARKER})"
elif [[ "$N_ENV" -gt 0 ]]; then
  delivered=1
  delivery_evidence="envelope_on_boot(${N_ENV})"
fi

if [[ "$N_ENV" -eq 0 ]]; then
  if [[ "$delivered" -eq 1 ]]; then
    echo "TRANSIENT: reason=delivered_but_silent boot=${NEWEST_BOOT} — the host HAS been provisioned" >&2
    echo "           since this change was authored (${delivery_evidence}), yet zero envelope rows" >&2
    echo "           arrived in the last ${WINDOW} on the newest boot while the read path is" >&2
    echo "           alive (${N_CTL} control row(s), ${N_ENV_PRE} pre-boundary excluded)." >&2
    # FIRST-TICK SOFTENING, GATED ON THE LITERAL -1 (#7456). The shipper is a 4-59/5 cron one-shot,
    # so between a host's birth and its first tick this arm was firing "ACT, NOT WAIT" at a host
    # that had simply never run one. Measured 2026-08-12: replaced 20:54:12Z, this arm at 20:56:32Z,
    # unassisted PASS at 20:58:45Z. The discriminator is the reporter's OWN last_ok_age_s — the
    # softening needs no host-age clock of its own. The test MUST be the literal "-1", never
    # emptiness: the pre-delivery reporter emits no log_shipper_* fields at all, and softening on
    # absence would weaken the genuine escalation that case pins (C3g).
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
    if [[ "$LAST_OK" == "-1" ]]; then
      echo "           BEFORE ACTING, rule out a first tick: last_ok_age_s=-1 means no row has EVER" >&2
      echo "           shipped, which is also the state of a host replaced minutes ago — the shipper" >&2
      echo "           is a 4-59/5 cron one-shot. Measured 2026-08-12: a host born 20:54:12Z read" >&2
      echo "           silent at 20:56 and PASSed at 20:58 with no intervention. If this host was" >&2
      echo "           just replaced, re-run after the next 5-minute boundary. If it has been up" >&2
      echo "           longer than that, -1 is a DEAD shipper and the arms below name the cause." >&2
    fi
    if [[ "$PF_VAL" =~ ^[0-9]+$ && "$PF_VAL" != "0" ]]; then
      echo "           The reporter's INDEPENDENT path says log_shipper_post_fail=${PF_VAL}," >&2
      echo "           so ticks ARE running and their POSTs are failing — that is an egress or token" >&2
      echo "           fault, not a dead shipper. reason=shipper_post_failing." >&2
    elif [[ "$PF_VAL" == "0" ]]; then
      echo "           The reporter reports no POST failures, so the tick is likely not running at" >&2
      echo "           all rather than failing to egress." >&2
    else
      # "unknown", "-" (absent on the boot), or any non-numeric value the reporter should never
      # emit — all read the same: the shipper's state cannot be READ, which is NOT a claim that
      # no failures happened. A corrupt value must not collapse into "reports no failures".
      echo "           The reporter says log_shipper_post_fail=${PF_VAL}, which is NOT zero: it means" >&2
      echo "           the shipper's state file was unreadable or corrupt, so the shipper may never" >&2
      echo "           have run a single tick. reason=shipper_state_unreadable — do NOT read this as" >&2
      echo "           'no POST failures', which would be an absence this probe never measured." >&2
    fi
    echo "           Reporter fields already read on this run (no second query needed):" >&2
    echo "             log_shipper_post_fail=${PF_VAL}  (- = absent on the newest boot's rows)" >&2
    echo "             log_shipper_last_ok_age_s=${LAST_OK}  (-1 = no row has EVER shipped)" >&2
    echo "             log_shipper_dropped_cum=${DCUM}  drop_seq=${DSEQ}" >&2
    if [[ "$LAST_OK" == "-1" ]]; then
      : # already led with above — a never-worked state, not a regression.
    elif [[ "$LAST_OK" != "-" ]]; then
      echo "           A finite last_ok_age_s with zero envelope rows means the shipper IS" >&2
      echo "           delivering and the envelope prefix or the probe's grep has drifted." >&2
    fi
    exit 2
  fi
  echo "TRANSIENT: reason=not_delivered boot=${NEWEST_BOOT} — zero envelope rows on the newest" >&2
  echo "           boot, no ${BOOT_MARKER} row on it, and no log_shipper_post_fail= field on any" >&2
  echo "           of its ${CONTROL_MARKER} rows. That field exists only in the reporter this" >&2
  echo "           change ships, so its absence on THIS boot is positive proof the new" >&2
  echo "           cloud-init has not run here (boot_id DRIFT is not used as evidence — this" >&2
  echo "           host self-reboots via the NIC guard, and runcmd is per-instance, so drift" >&2
  echo "           without a replace proves nothing)." >&2
  echo "           The read path IS alive (${N_CTL} control row(s)), so" >&2
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

# --- the zot-only token must be present, or these rows are not really zot's output -----------
if [[ "$N_ZOT" -eq 0 ]]; then
  echo "TRANSIENT: reason=envelope_without_zot_content boot=${NEWEST_BOOT} — ${N_ENV} envelope row(s)" >&2
  echo "           on the newest boot carry the shipper's own framing but NONE contains" >&2
  echo "           ${ZOT_ONLY_SUBSTR}, the substring only zot's own output produces. The shipper is" >&2
  echo "           alive and shipping something that is not zot log content — a journald match" >&2
  echo "           that resolves to the wrong unit." >&2
  exit 2
fi

# --- EXPECTED FLOOR, computed over the BOUNDED span (#8278) -----------------------------------
# zot-liveness-heartbeat.timer fires every 60s (OnUnitActiveSec=60s) and zot logs EVERY request
# at info level, so one genuine zot line lands per minute BY CONSTRUCTION. The expectation is
# now measured over the BOUNDED span — the minutes from B0 to the newest row — not the full
# window: a boundary inside the window would otherwise post a systematic false
# below_expected_floor for ~30 minutes after every replace.
# (The "-" sentinel, the newest-dt parse, and the producer-freshness gate all ran above — before
# the delivery arms — because a stale or boundary-less window must never reach a liveness
# verdict. Only B0 still needs epoch conversion here.)
B0_EPOCH="$(date -u -d "$B0_DT" +%s 2>/dev/null)" || B0_EPOCH=""
if [[ -z "$B0_EPOCH" ]]; then
  echo "CANNOT ESTABLISH: the boundary (${B0_DT}) could not be parsed — the bounded span is" >&2
  echo "           unmeasurable, so the row-count floor cannot be graded honestly." >&2
  exit 3
fi
SPAN_MIN=$(( (NDT_EPOCH - B0_EPOCH) / 60 ))
(( SPAN_MIN < 0 )) && SPAN_MIN=0
EXPECTED_ROWS="$WINDOW_MIN"
(( SPAN_MIN < EXPECTED_ROWS )) && EXPECTED_ROWS=$SPAN_MIN
FLOOR_ROWS=$(( EXPECTED_ROWS / 4 ))
[[ "$FLOOR_ROWS" -ge 3 ]] || FLOOR_ROWS=3

if [[ "$N_ENV" -lt "$FLOOR_ROWS" ]]; then
  echo "TRANSIENT: reason=below_expected_floor boot=${NEWEST_BOOT} — ${N_ENV} envelope row(s) in the" >&2
  echo "           bounded span, against a computed expectation of ~${EXPECTED_ROWS} and a floor of ${FLOOR_ROWS}." >&2
  echo "           The 60s liveness timer plus zot's log-every-request behaviour put one genuine" >&2
  echo "           line per minute on this channel BY CONSTRUCTION, so a shortfall is measurable" >&2
  echo "           rather than a judgement call. The shipper is partly working: POSTs are failing," >&2
  echo "           the rate cap is mis-sized, or the unit is restart-looping." >&2
  if [[ "$PF_VAL" =~ ^[0-9]+$ && "$PF_VAL" != "0" ]]; then
    echo "           log_shipper_post_fail=${PF_VAL} on the reporter's independent path." >&2
  fi
  echo "           ${N_DROP} ${DROP_MARKER} row(s) on the same boot." >&2
  exit 2
fi

# --- PASS ------------------------------------------------------------------------------------
# The four measured evidence classes are printed as COUNTS because the gc start/complete RATIO is
# the discriminator the downstream disk-attribution question needs: a stalled gc emits a start with
# no completion, and that ratio is unreadable from a channel that admits only completions.
# ANCHORED ON THE PARSED message FIELD, matching the producer (#7444 R33). is_cap_exempt keys on
# zerolog's `.message`, which is what closed the bypass where any client sending
# `User-Agent: executing gc` bought cap exemption for every one of its request lines. STAYS
# FOUR-CLASS DELIBERATELY (#7555): this reader is NOT an exemption census and must not become one.
# It answers one question — is the #7440 channel delivering, and what is the gc start/complete
# RATIO — for which these four are the vocabulary.
#
# The consequence to keep in view: these counts are a lower bound on exempt volume, never a
# measure of it. Do not read a flat gc count as "the exempt lane is quiet".

echo "PASS: envelope rows observed (envelope=${N_ENV} control=${N_CTL} pre_boot=${N_ENV_PRE} gc_start=${N_GCS} gc_done=${N_GCD} gc_blobs=${N_GCB} patch_upload=${N_PATCH} dropped_rows=${N_DROP})"
echo "      Window ${WINDOW} boot=${NEWEST_BOOT}; expectation ~${EXPECTED_ROWS} rows (bounded span ${SPAN_MIN}m), floor ${FLOOR_ROWS}; delivery evidence: ${delivery_evidence}."
echo "      This is a READBACK, not the emitter's self-report: each row was read back OUT of the"
echo "      warehouse through the ClickHouse path, which no exit code on the host can fake. The"
echo "      match is POSITIVE and host-isolated — a decoded message starting with"
echo "      '${ENVELOPE_PREFIX}${EXPECTED_HOST}' — so the ${CONTROL_MARKER} echo rows that make a naive"
echo "      'zotregistry.dev' grep return 53 hits today cannot satisfy it."
echo "      ${N_ZOT} of ${N_ENV} row(s) carry ${ZOT_ONLY_SUBSTR}, the substring only zot's"
echo "      own output produces."
echo "      The gc start/complete ratio (${N_GCS}/${N_GCD}) is now readable, which is what"
echo "      makes the downstream growth-attribution question answerable from telemetry at all."
# NO ROW EXCERPT. sweep-followthroughs.sh captures this stdout with 2>&1 and posts it as a comment
# on a PUBLIC repo issue, so anything printed here is published. A raw zot row carries internal
# 10.0.1.x topology, service usernames, OCI repo names, digests, filesystem paths and User-Agent,
# and the credential scan above covers exactly three patterns — a secret shape outside those three
# reaches this line having already passed every gate. The FAIL arm is counts-only for this reason;
# the PASS arm is held to the same discipline. Counts and ratios are the contract; row VALUES are
# not, and the diagnostic question this probe answers ("did the channel deliver?") is a counting
# question. Pinned by C13 in tests/scripts/test-zot-log-channel-probe.sh.
exit 0
