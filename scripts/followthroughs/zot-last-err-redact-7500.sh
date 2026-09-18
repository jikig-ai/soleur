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
# PROOF KEY: err_redact_rev (producer: cloud-init-registry.yml LINE=; contract: ADR-211).
#
# EXIT CONTRACT (the sweeper lists `--state open`; its reopen path fires only on exit 1). The
# authoritative rows are R1-R4 in the decision-table comment above the verdict chain; the
# earlier exits are the channel/envelope/decode guards.
#   0 = PASS       delivery PROVEN on the newest boot, tier-4 rows present, none leaking (R3)
#   1 = FAIL       delivery PROVEN and a tier-4 row on that boot carries header structure (R2)
#   2 = TRANSIENT  delivery PROVEN but no tier-4 row on that boot yet (R1), or ANY
#                  auth/query/envelope/decode failure
#   3 = CANNOT ESTABLISH  the newest boot is not proven to run the Phase B producer (R4), or no
#                  row carries a usable boot_id. Renders under its own sweeper heading.
#
# WHY PROOF, NEVER BOOT DRIFT. `exit 0` closes a credential-leak tracker and `exit 1` asserts on
# a public issue that the redaction shipped and is broken; both need POSITIVE proof that the
# graded boot runs the Phase B producer. A boot_id that differs from some earlier one proves a new
# BOOT, not a new HOST: cloud-init's runcmd is per-instance and does not re-run on reboot, and
# this host reboots as a convergence primitive (the private-NIC guard). So drift feeds no
# verdict. `SOLEUR_ZOT_LOG_BOOT` is not a key either: `git log -S` puts it in 07cf8ebcb (#7444,
# the log shipper), not in 96f5b6eb5 (#7954, Phase B).
#
# Proof is either of two tokens, both read from the trusted region of a row on the newest boot:
#   * `err_redact_rev=<n>`, n >= 1 -- emitted on EVERY row by the post-#7960 producer (necessary and
#     sufficient). The primary key.
#   * `zot_last_err_src=suppressed` -- emitted only by the Phase B gate, and only when it withheld
#     a sample (sufficient, not necessary). Kept as secondary corroboration.
#
# There is no automatic escalation for a long-running exit 2 or 3: sweep-followthroughs.sh
# comments and does not escalate open issues. The daily comments land on a PUBLIC issue and carry
# counts, boot ids and proof-source names only -- never row content.
#
# Whether the redaction is CORRECT when it arrives is settled pre-merge by
# `apps/web-platform/infra/zot-disk-heartbeat-redaction.test.sh`. This probe answers DELIVERY,
# and grades what the delivered producer actually emits.
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
  MARKER_ROWS="$(printf '%s\n' "$RAWOUT" | grep -c . || true)"
  echo "TRANSIENT: $MARKER_ROWS row(s) matched the marker but NONE carries the" >&2
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

# TRUSTED REGION. boot_id scopes every verdict, so a crafted tail carrying ` boot_id=FORGED`
# would otherwise win the greedy match and select which host is graded. The tail is cut first,
# exactly as zot_trusted_region does. The leak grade below still reads the tail, which is
# correct: that is the untrusted content it exists to measure.
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
#     Accepting it scopes the grade to a pseudo-boot, so a /proc read failure alone -- on a row
#     that carries the proof token -- could close the tracker. No attacker required.
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

# ONE PASS, ONE TRUSTED REGION, applied to EVERY field a verdict keys on. MIRRORS
# zot_trusted_region: each row is cut at the FIRST ` zot_last_err=` (the free-text field the
# producer emits LAST); every verdict field -- boot_id, the tier tag, and the proof token -- is
# read from the text BEFORE it, and only the leak grade reads the text after it. A crafted
# `zot_last_err` tail therefore cannot supply boot_id, promote a row to tier 4 (the producer's own
# template names this class: "a whole-line substring test instead lets any private-net client send
# `User-Agent: executing gc`…"), or forge the proof token. The cut is leftmost, never greedy: a
# later ` zot_last_err=` inside a flattened multi-line sample must not truncate the leak out of
# the measurement.
#
# Outputs ONE summary line of counts -- never row text, so nothing below can echo row content
# onto the public issue:
#   F  rows on the newest boot whose head carries `err_redact_rev=<n>`, n >= 1 (ALL rows, not only
#      tier 4: the producer emits the field on every row, whatever the tier)
#   S  tier-4 rows on the newest boot tagged `suppressed`
#   T  tier-4 rows (`fallback` or `suppressed`) on the newest boot
#   L  tier-4 rows graded LEAKING (see below)
#
# ONE ROW ON THE NEWEST BOOT SUFFICES FOR PROOF: the host is cloud-init-only with no SSH ingress
# (ADR-096), so the heartbeat script cannot change within a boot.
#
# THE LEAK GRADE IS STRUCTURE, NOT WORDS. Field-keyed proof makes exit 1 reachable on an ordinary
# delivered host, so a message that merely names "headers" or "clientIP" must not post a public
# FAIL. The producer strips quotes (`tr -d '"\\'`), so a real leak reads `headers:{Cookie:[…]}` or
# `clientIP:10.0.1.9`. Matched case-insensitively (tolower) against the tail:
#   1. a header MAP with at least one `key:` -- covers Go `map[…]` rendering; an empty map or a
#      list of header NAMES does not match;
#   2. a clientIP carrying an ADDRESS -- dotted IPv4, or two colons for IPv6 (`default` does not);
#   3. a bare CREDENTIAL header (the producer's CRED_HDRS list) whose value is not `[REDACTED` or
#      zot's `[******` mask -- survives a truncated or renamed `headers` wrapper. The trailing
#      `\[` is REQUIRED and deliberate: zot renders header values as Go slices, so a real leak is
#      `Cookie:[abc]`, while an unbracketed `authorization: denied` is prose. Measured: an
#      unbracketed `cookie: sid=deadbeef` grades CLEAN here, as it did under the pre-#7960
#      discriminator -- do not delete the `\[` to "widen" this, or ordinary prose posts a public
#      FAIL on a delivered host.
# A `suppressed` row whose tail is anything but `none` also counts: the gate is supposed to have
# withheld that sample, so anything shipped under `suppressed` is a gate regression.
# Written for POSIX awk (no interval expressions, no [[:classes:]]) so mawk and gawk agree.
read -r PROOF_F PROOF_S TIER4_N LEAKY < <(printf '%s\n' "$DECODED" \
  | awk -v want="$NEWEST_BOOT" '
      BEGIN { f = 0; s = 0; t = 0; l = 0 }
      {
        i = index($0, " zot_last_err=")
        head = (i > 0) ? substr($0, 1, i - 1) : $0
        tail = (i > 0) ? substr($0, i + 14) : ""
        if (!match(head, / boot_id=[0-9a-fA-F-]+/)) next
        b = substr(head, RSTART + 9, RLENGTH - 9)
        if (b != want) next
        if (head ~ /(^| )err_redact_rev=[1-9][0-9]*( |$)/) f++
        if (head ~ /(^| )zot_last_err_src=suppressed( |$)/) {
          t++; s++
          if (tail != "none") l++
          next
        }
        if (head !~ /(^| )zot_last_err_src=fallback( |$)/) next
        t++
        lt = tolower(tail); leak = 0
        if (lt ~ /headers[ \t]*[:=][ \t]*(map)?[[{][ \t]*[a-z0-9-]+[ \t]*:/) leak = 1
        if (lt ~ /clientip[ \t]*[:=][ \t]*\[?([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+|[0-9a-f]*:[0-9a-f]*:)/) leak = 1
        rest = lt
        while (!leak && match(rest, /(^|[^a-z0-9-])(authorization|cookie|x-api-key|proxy-authorization|x-amz-security-token)[ \t]*[:=][ \t]*\[/)) {
          rest = substr(rest, RSTART + RLENGTH)
          if (rest !~ /^(redacted|\*\*\*\*\*\*)/) leak = 1
        }
        if (leak) l++
      }
      END { print f, s, t, l }')
TOTAL_ROWS="$(printf '%s\n' "$DECODED" | grep -cF 'SOLEUR_ZOT_DISK' || true)"
[[ -n "$TOTAL_ROWS" ]] || TOTAL_ROWS=0
# A missing summary line is "could not measure", never zero: every count below must be an integer.
# LOAD-BEARING, not defensive padding: bash treats an EMPTY operand as false in `[[ "" -gt 0 ]]`,
# so if the awk pass produced nothing, LEAKY would read as "no leak" and R3 would CLOSE the tracker
# on a measurement that never happened. This guard is the only thing between a failed awk and a
# false close -- do not simplify it away.
for _n in "$PROOF_F" "$PROOF_S" "$TIER4_N" "$LEAKY"; do
  case "$_n" in
    ''|*[!0-9]*)
      # R4 (unmeasurable): no count means no proof can be read -> CANNOT ESTABLISH
      echo "CANNOT ESTABLISH: the grading pass produced no usable counts for boot $NEWEST_BOOT --" >&2
      echo "           a probe defect, not evidence in either direction." >&2
      exit 3 ;;
  esac
done

# Proof source, named in every authoritative message (counts and names only -- P6).
PROOF_SRC=""
if (( PROOF_F > 0 && PROOF_S > 0 )); then PROOF_SRC="err_redact_rev+suppressed"
elif (( PROOF_F > 0 )); then PROOF_SRC="err_redact_rev"
elif (( PROOF_S > 0 )); then PROOF_SRC="suppressed"
fi
DELIVERY_PROVEN=0
[[ -n "$PROOF_SRC" ]] && DELIVERY_PROVEN=1

# DECISION TABLE (every exit below is one of these rows):
#   R1  proof, T == 0          -> 2  DELIVERY PROVEN, not yet graded
#   R2  proof, T > 0, L > 0    -> 1  FAIL
#   R3  proof, T > 0, L == 0   -> 0  PASS
#   R4  no proof               -> 3  CANNOT ESTABLISH
if [[ "$DELIVERY_PROVEN" -eq 0 ]]; then
  # R4: no proof -> CANNOT ESTABLISH
  echo "CANNOT ESTABLISH: boot $NEWEST_BOOT lacks err_redact_rev, and carries no" >&2
  echo "           zot_last_err_src=suppressed row, so it is NOT PROVEN to run the Phase B" >&2
  echo "           producer. ($TOTAL_ROWS row(s) in $WINDOW; $TIER4_N tier-4 row(s) on this boot," >&2
  echo "           $LEAKY graded as carrying header structure.) Refusing both to close the tracker" >&2
  echo "           and to assert the redaction is broken on a host this probe cannot identify." >&2
  echo "           EXPECTED until the registry-host-replace that delivers this field completes." >&2
  echo "           Check the last successful run of registry-host-replace-dispatch.yml (and the" >&2
  echo "           apply-web-platform-infra.yml run it dispatched): if one has completed since the" >&2
  echo "           field was merged, this reading means the field is NOT reaching the host --" >&2
  echo "           investigate now (is err_redact_rev in the newest rows' trusted region? did the" >&2
  echo "           replace render from the merge SHA?), do not wait." >&2
  exit 3
fi

if [[ "$TIER4_N" -eq 0 ]]; then
  # R1: proof, T == 0 -> NOT YET (proven, ungraded)
  echo "DELIVERY PROVEN ($PROOF_SRC) — no tier-4 row on boot $NEWEST_BOOT yet." >&2
  echo "           $TOTAL_ROWS SOLEUR_ZOT_DISK row(s) in $WINDOW, none at tier 4" >&2
  echo "           (zot_last_err_src=fallback|suppressed) on this boot. Tier 4 is the only tier" >&2
  echo "           the gate changes, so this window cannot grade it. Nothing to do unless this" >&2
  echo "           persists for days. Rows from an EARLIER boot are deliberately excluded." >&2
  exit 2
fi

if [[ "$LEAKY" -gt 0 ]]; then
  # R2: proof, T > 0, L > 0 -> FAIL
  echo "FAIL: delivery proven ($PROOF_SRC) and $LEAKY of $TIER4_N tier-4 row(s)" >&2
  echo "      STILL carry header content on boot $NEWEST_BOOT: header structure (a header map," >&2
  echo "      an address-valued clientIP, an unmasked credential header) or a non-empty" >&2
  echo "      suppressed sample. The redaction shipped and is not holding. This must not close." >&2
  exit 1
fi

# R3: proof, T > 0, L == 0 -> PASS
echo "PASS: producer delivered (proof: $PROOF_SRC) — $TIER4_N tier-4 row(s) on boot $NEWEST_BOOT"
echo "      in $WINDOW, none carrying header content."
exit 0
