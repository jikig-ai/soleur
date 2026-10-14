# shellcheck shell=bash
# inngest-host-dark-gate.sh — the probe-row gate library for scripts/cutover-inngest.sh.
#
# ONE LIVE ENTRY POINT, PLUS SHARED HELPERS:
#   inngest_execute_registry_gate  scripts/cutover-inngest.sh op=execute step 2.0 and its registry-probe arm (P0 cutover, #8054)
# `_IHDG_IDENT` / `_IHDG_SELECT` and every `_ihdg_*` helper select, parse and grade the hourly
# `SOLEUR_INNGEST_SERVER_PROBE` row; `_ihdg_graded_row` is the shared prelude (E1-E7 below). Helpers
# prefixed `_erg_` are consumed by the execute gate only. The gate itself is documented where it is
# defined, further down this file, E-table included.
#
# RETIRED 2026-10-14 (#8316). This file used to carry a second entry point, `inngest_host_dark_gate`
# ("Guard 2" of the long-gone `inngest-volume-recut` apply_target, #7695), with twenty predicates
# G1-G20. #8285 PR A (#9784) removed its only caller and PR B (#9877) the target itself; the entry
# point and its one private helper (`_ihdg_finished_count`) were deleted under #8316. The full
# design — the monotonicity argument for why a <=90-minute-old row is sound evidence of an emptiness
# that holds at apply time, and the G1-G20 predicate table — is recoverable with:
#   git show b6d745fe78:tests/scripts/lib/inngest-host-dark-gate.sh   (header and function)
# and the retirement is recorded in the 2026-10-14 addendum of ADR-199.
#
# G-NUMBERS THAT REMAIN. G1-G7 were the retired gate's names for what are now E1-E7 of the execute
# gate (the same shared prelude, plus the boot_id shape check); they survive as names inside the
# kept helpers' comments and are NOT edited, because those helpers are byte-identical on purpose.
# G8-G20 have no executable form any more. Dangling mentions of the retired names, listed so none
# is silent: the comment above `_ihdg_graded_row` and the G-numbered comments inside the helpers
# and the execute gate's body (G0-G6, "the recut gate", "the sibling", "shared with
# inngest_host_dark_gate" on its E1..E7 line), the "inlined in `inngest_host_dark_gate`" sentence above
# `_ihdg_graded_row`, the "Born as G10's" note on `_ihdg_decoded_rows`, and the `_erg_flag_class`
# comment ("G20 in this file").
#
# ── WHY THIS IS NOT scripts/inngest-dedicated-host-classify.sh ──────────────────────────────────
#
# That classifier answers a MONITORING question and collapses `silent`, `unreadable` and a
# pre-schema row into one `probe-unavailable` verdict. That is the right shape for a pager: all
# three mean "go look". It is the WRONG shape here, because the three have different remedies and
# only one of them is a wait:
#   silent        — the host emits nothing. Check the timer and the Vector shipper.
#   unreadable    — the read path failed, or a field did not parse. Nothing about the host was
#                   measured; retry.
#   stale_schema  — the host is emitting, but from a pre-probe_schema=8 renderer. ACTIONABLE:
#                   replace the host first WITH A PIN THAT CARRIES THE EMITTER -- a replace on an
#                   unbumped pin re-delivers the same bytes, because the emitter is baked into the
#                   OCI image and reaches the host via the digest literal in user_data, not via
#                   cloud-init (#7695; ADR-199 amendment 2026-09-07). Collapsing it into
#                   `unreadable` would tell the operator to retry forever against a host that can
#                   never satisfy the gate.
# This gate therefore reuses that script's host-conjunction QUERY FILTER (the two-field envelope
# identity, #7674 / #6616) and its R_SPOOF fixture shape — not its function.
#
# ── POSITIVE ALLOWLIST ──────────────────────────────────────────────────────────────────────────
#
# The decision function proceeds ONLY on the literal `dark`. Every other token aborts, `unreadable`
# included. A gate that cannot see the host must never conclude the host is dark: silence is not
# darkness.
#

# THE PROBE-ROW SELECTOR, DEFINED ONCE. This identity conjunction and marker filter were
# replicated verbatim across four jq programs — `_ihdg_rows`, `_ihdg_row_count`,
# `_ihdg_newest_dt` and `_ihdg_tied_newest`. Review measured the cost: neutering the copy inside
# `_ihdg_newest_dt` — the SOLE input to G3's wall-clock staleness bound — left the suite at
# 112 passed, 0 failed, because no fixture exercised that copy. A stale dedicated-host row beside
# a fresh row from the co-located WEB host would then take its `dt` from the foreign row and clear
# the recency bound the predicate exists to enforce.
#
# Two earlier hardenings had already had to be hand-applied to each site (`contains(...)` ->
# `test("^SOLEUR_INNGEST_SERVER_PROBE ")`), which is exactly the drift this removes. One
# definition means a future tightening cannot land on some readers and not others, and one
# mutation of it reddens every consumer at once instead of only the ones with fixtures.
#
# SPLIT IN TWO SINCE #8054. `_IHDG_IDENT` is the decode + host-identity conjunction — the part
# every stream this lib reads shares, the heartbeat included — and `_IHDG_SELECT` is that plus the
# probe-row predicate. The heartbeat reader embeds `_IHDG_IDENT` and adds its own identifier test,
# so the host conjunction is still written exactly once (the suite counts its occurrences).
#
# THE PROBE-ROW PREDICATE IS NO LONGER DEFINED HERE (#8846). A marker-anchored `test(...)` was the
# whole of it, and it was not enough: the inngest server's own event log ships from the SAME host
# under SYSLOG_IDENTIFIER=doppler and quotes the marker whenever a GitHub issue/PR/comment about the
# probe is webhooked in. The emitter is part of a probe row's identity, and "what is a probe row" is
# now answered in ONE place for every reader in the repo — scripts/lib/inngest-probe-row.sh, whose
# `inngest_probe_row` jq def checks the emitter AND the anchor. `_IHDG_PROBE` applies it to the
# DECODED row; every jq program that embeds it is prefixed with "$INNGEST_PROBE_ROW_JQ".
#
# RESOLVED FROM THIS FILE'S OWN LOCATION, with an override for test sandboxes that run a COPY of
# this lib from a temp dir (INNGEST_PROBE_ROW_LIB). A failed load is NOT silence: it sets
# `_IHDG_PROBE_LIB_OK=0`, and both entry points refuse `unreadable` on that before anything else.
# The `|| true` keeps a failed `cd` from aborting a `set -e` caller at the assignment — the path is
# then `/scripts/lib/…`, the source fails, and the flag carries the refusal instead.
#
# THE LOAD IS PROVEN, NOT ASSUMED (the shared consumer load contract, #8846 review P2-1):
#   - `unset` FIRST. `.github/actions/infra-credentials` exports every Doppler key into
#     $GITHUB_ENV, so an INHERITED `INNGEST_PROBE_ROW_JQ='def inngest_probe_row: true;'` survived a
#     lib that sources cleanly but assigns nothing (/dev/null, a truncated checkout) and the old
#     `[[ -n $INNGEST_PROBE_ROW_JQ ]]` check passed on it — measured: a doppler row quoting the
#     marker counted as a probe row with the flag still 1.
#   - `declare -F` before calling the selftest: a lib that defines no selftest must refuse, never
#     fall through to whatever executable of that name is on PATH.
#   - the selftest grades the LOADED def against the event-log shapes; a def that loads but admits
#     a doppler row (or compiles to nothing) is the same missing selector.
#   - the source's stderr is NOT discarded: a missing file and a syntax error must read differently.
unset INNGEST_PROBE_ROW_JQ INNGEST_PROBE_EMITTER INNGEST_PROBE_MARKER
_IHDG_PROBE_ROW_LIB="${INNGEST_PROBE_ROW_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." 2>/dev/null && pwd)/scripts/lib/inngest-probe-row.sh}" || true
_IHDG_PROBE_LIB_OK=1
# shellcheck source=scripts/lib/inngest-probe-row.sh
if ! source "$_IHDG_PROBE_ROW_LIB" || ! declare -F inngest_probe_row_selftest >/dev/null || ! inngest_probe_row_selftest; then
  _IHDG_PROBE_LIB_OK=0
fi

# _ihdg_selector_unavailable — the ONE stderr line G0 and E0 print before refusing `unreadable`.
# Only the message is shared: the refusal itself (`_ihdg_verdict`) stays at each entry point, because
# no shared helper may call `_ihdg_verdict` (the suite enforces it). stdout stays the bare token.
_ihdg_selector_unavailable() {
  echo "inngest-host-dark-gate: selector_unavailable lib=${_IHDG_PROBE_ROW_LIB:-<unresolved>} — the probe-row selector (scripts/lib/inngest-probe-row.sh, or INNGEST_PROBE_ROW_LIB) did not load or failed its selftest; nothing was measured" >&2
}

_IHDG_IDENT='
        | . as $outer
        | ((.raw? // empty) | fromjson?) as $d
        | select(($d | type) == "object")
        | select($d.host == $h and $d.host_name == $hn)'
# ONE LINE, deliberately: the suite's B10 row ERG-M-PROBE empties it with a single-line sed.
_IHDG_PROBE='| select($d | inngest_probe_row)'
_IHDG_SELECT="$_IHDG_IDENT$_IHDG_PROBE"

# THE EXPECTED PROBE SCHEMA, DEFINED ONCE. Both entry points default `--expected-schema` to this
# and the execute gate's caller interpolates it into the `stale_schema` remedy. The emitter's
# schema has bumped 3 -> 4 -> 7 -> 8 and a bump that lands on one consumer and not the other would
# make the two gates disagree about the same row forever (the suite asserts the literal appears
# here and nowhere else in this file).
_IHDG_EXPECTED_SCHEMA="8"

# _ihdg_field <message> <field-name>
#
# Returns 0 and prints the value when the field is PRESENT, 1 when it is ABSENT. The distinction is
# the whole point: `plan §Guard Contract` requires every consumed field to be validated for
# PRESENCE, not just format, because an absent `http_code` is trivially "non-200" and an absent
# `boot_id` compared against an absent `boot_id` is trivially equal.
#
# `read -ra` rather than an unquoted `for tok in $msg` — the latter GLOBS, so a message containing
# `*` would expand against the working directory. The probe's fields are space-separated `k=v` with
# no spaces in any value, so word-splitting is exact rather than approximate.
_ihdg_field() {
  local msg="$1" name="$2" tok val hits=0
  local -a toks=()
  local IFS=' '
  # A MESSAGE CARRYING A NEWLINE IS NOT ONE MESSAGE. `_ihdg_rows` renders `message` through
  # `jq -r`, so an embedded newline becomes two PHYSICAL lines out of ONE row — and the caller
  # loop then takes the LAST line as `newest_msg` while `_ihdg_tied_newest` still sees a single
  # distinct message and passes. Refuse the whole read instead.
  [[ "$msg" != *$'\n'* ]] || return 1
  read -ra toks <<< "$msg"
  for tok in "${toks[@]}"; do
    if [[ "$tok" == "${name}="* ]]; then
      hits=$((hits + 1))
      [[ "$hits" -eq 1 ]] && val="${tok#"${name}"=}"
    fi
  done
  # FIRST-MATCH-WINS WAS A FAIL-OPEN, and the emitter's own field order made it reachable.
  # `logger -t inngest-server-probe "... boot_id=X image_ref=$image_ref ... redis_keys=$redis_keys
  # data_mount_src=$data_mount_src ..."` puts image_ref at field 6 and redis_keys at field 13,
  # and image_ref is `sed`-extracted from /etc/default/soleur-inngest-image with no whitespace
  # strip and no charset validation (inngest-bootstrap.sh). A value containing
  # ` redis_keys=0 server_active=inactive http_code=000 ...` therefore supplies every store and
  # liveness field BEFORE the real ones, and first-match-wins reads the injected copy — verdict
  # `dark`, rc 0, on a serving host with a populated store, authorizing the irreversible destroy.
  #
  # A duplicated field name means the message is not the shape this gate grades. There is no
  # reading of it that is safe to prefer, so refuse rather than choose.
  [[ "$hits" -eq 1 ]] || return 1
  printf '%s' "$val"
  return 0
}

# _ihdg_rows <rows-file> <host> <host_name>
#
# Decode, identity-filter, sort by event time, emit one TSV line per row: <dt>\t<message>.
#
# THE FILTER IS APPLIED AFTER DECODING, and that is not a style choice. ClickHouse stores `raw`
# DOUBLE-ENCODED, so a literal `"host_name":"…"` match against the outer row matches NOTHING, EVER
# — the gate would read zero rows forever and report `silent` for the life of the feature.
# Measured against live rows in #7674: outer match 0/40, post-decode match 40/40.
#
# `-Rn` + `inputs` + `fromjson?` at BOTH levels is load-bearing rather than defensive habit:
# without `-R`, jq parses the stream itself, so ONE malformed line aborts the whole invocation and
# every valid row after it is lost — which surfaces as `silent` ("the host emits nothing") on a
# window that in fact contained a clean reading. A warehouse read is exactly where a truncated line
# shows up.
#
# SORTED HERE, NOT TRUSTED FROM THE CALLER. betterstack-query.sh happens to emit `dt ASC` today; a
# gate whose "newest row" depends on an upstream ORDER BY is one query-shape change away from
# reading the OLDEST row and calling it current.
_ihdg_rows() {
  local rows_file="$1" host="$2" host_name="$3"
  jq -Rn --arg h "$host" --arg hn "$host_name" "$INNGEST_PROBE_ROW_JQ"'
      [ inputs
        | fromjson?
        | select(type == "object")
'"$_IHDG_SELECT"'
        | [ ($outer.dt // ""), ($d.message // "") ]
      ]
      | sort_by(.[0])
      | .[]
      | .[1]
    ' -r < "$rows_file" 2>/dev/null
}

# _ihdg_newest_dt <rows-file> <host> <host_name>
#
# The `dt` of the newest qualifying probe row — the input G3 needs and `_ihdg_rows` deliberately
# drops (it emits one MESSAGE per line so an empty leading field cannot collapse under IFS). Same
# filter and same sort as `_ihdg_rows`, so the row it names is the row the gate grades.
_ihdg_newest_dt() {
  local rows_file="$1" host="$2" host_name="$3"
  jq -Rn --arg h "$host" --arg hn "$host_name" "$INNGEST_PROBE_ROW_JQ"'
      [ inputs
        | fromjson?
        | select(type == "object")
'"$_IHDG_SELECT"'
        | ($outer.dt // "")
      ]
      | sort
      | last // ""
    ' -r < "$rows_file" 2>/dev/null
}

# _ihdg_row_count <rows-file> <host> <host_name>
#
# How many ROWS the identity+marker filter selected — as opposed to how many physical LINES
# `_ihdg_rows` emitted. They differ by exactly the number of embedded newlines, which is what
# makes the comparison a newline detector. Echoes the empty string on any read failure so the
# caller's numeric predicate refuses.
_ihdg_row_count() {
  local rows_file="$1" host="$2" host_name="$3"
  jq -Rn --arg h "$host" --arg hn "$host_name" "$INNGEST_PROBE_ROW_JQ"'
      [ inputs
        | fromjson?
        | select(type == "object")
'"$_IHDG_SELECT"'
      ] | length
    ' -r < "$rows_file" 2>/dev/null
}

# _ihdg_tied_newest <rows-file> <host> <host_name>
#
# Echoes `1` when the newest `dt` is carried by exactly one DISTINCT message, else `0`. Distinct,
# not unique: a duplicated row (the same probe delivered twice) is not a disagreement and must not
# refuse. Echoes `0` on any read failure, so an unparseable file lands on the refusal.
_ihdg_tied_newest() {
  local rows_file="$1" host="$2" host_name="$3" out
  out="$(jq -Rn --arg h "$host" --arg hn "$host_name" "$INNGEST_PROBE_ROW_JQ"'
      [ inputs
        | fromjson?
        | select(type == "object")
'"$_IHDG_SELECT"'
        | { dt: ($outer.dt // ""), m: ($d.message // "") }
      ] as $rows
      | ($rows | map(.dt) | max) as $newest
      | if $newest == null then 0
        else ($rows | map(select(.dt == $newest) | .m) | unique | length | if . == 1 then 1 else 0 end)
        end
    ' -r < "$rows_file" 2>/dev/null)" || return 0
  printf '%s' "${out:-0}"
}

# _ihdg_decoded_rows <rows-file>
#
# Counts rows that DECODE — regardless of host or marker — so "zero rows attributable to this
# host" can be distinguished from "the parser understood nothing in this file". Born as G10's
# positive control (under the name `_ihdg_finished_lines`); since #8054 it is the ONE decode
# counter for all three streams this lib reads (function.finished rows, probe rows in E2, heartbeat
# rows in E13), so it is named for what it counts. It deliberately does NOT filter on any marker: a
# window in which this fleet ran no functions at all is legitimate, and what must be proved is that
# the read and the decode worked, not that any particular event occurred.
_ihdg_decoded_rows() {
  local rows_file="$1"
  jq -Rn '
      [ inputs
        | fromjson?
        | select(type == "object")
        | ((.raw? // empty) | fromjson?)
        | select(type == "object")
      ] | length
    ' < "$rows_file" 2>/dev/null
}

# _ihdg_undecodable <rows-file> — rc 0 when the file carries at least one NON-EMPTY line and NONE
# of its lines decodes; rc 1 otherwise. No token, no policy: the caller names the refusal (E2 says
# `unreadable`, E13 says `fsm_unreadable`). ONE definition for both consumers (#8054 review: the
# two inline copies had already drifted from G10's idiom).
#
# NON-EMPTY lines (`grep -c .`), not physical lines (`grep -c ''`), and that distinction is what
# makes the `silent` verdicts REACHABLE from the production caller: `_bs_query_rows` in
# scripts/cutover-inngest.sh renders its result with `printf '%s\n' "$rows"`, so a ZERO-row result
# lands on disk as ONE empty line. Counted as a physical line it read as "bytes present, nothing
# decoded" -> `unreadable`, and the operator was told to file an issue against the emitter when the
# correct remedy was the `silent` one (read the health run, then replace the host). Measured
# 2026-09-11 at review: a 1-byte file graded `unreadable`, a 0-byte file `silent`, for the same
# host state. `grep -c .` prints 0 and exits 1 on no match, hence `|| true`.
_ihdg_undecodable() {
  local rows_file="$1" raw_lines decoded_rows
  raw_lines="$(grep -c . "$rows_file" 2>/dev/null || true)"
  decoded_rows="$(_ihdg_decoded_rows "$rows_file")"
  [[ "$raw_lines" =~ ^[0-9]+$ && "$decoded_rows" =~ ^[0-9]+$ ]] || return 0   # could not count: treat as undecodable
  [[ "$raw_lines" -ge 1 && "$decoded_rows" -eq 0 ]]
}

# _ihdg_refuse <token> — print a refusal token for the CALLER to dispatch, rc 1. Shared helpers
# name the refusal; only the two entry points turn a token into an exit code (via _ihdg_verdict),
# so policy cannot leak into a helper both of them trust. The test suite asserts no `_ihdg_*`
# helper body calls _ihdg_verdict.
_ihdg_refuse() {
  printf '%s\n' "$1"
  return 1
}

# _ihdg_epoch_from_dt <dt> — Better Stack's UTC `YYYY-MM-DD HH:MM:SS[.ffffff]` to epoch seconds.
# Anything else is a shape this lib has not been taught to read, and `date` would happily coerce
# several of them (`yesterday`, `now`, an RFC-2822 string with a timezone). Refuses with rc 1 and
# prints nothing. ONE definition: the probe side (G3/E5) and the heartbeat side (E13) both go
# through it, so the regex cannot drift between the two streams' freshness bounds.
_ihdg_epoch_from_dt() {
  local dt="$1" epoch
  [[ "$dt" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}[[:space:]][0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?$ ]] || return 1
  epoch="$(date -u -d "${dt} UTC" +%s 2>/dev/null)" || return 1
  [[ "$epoch" =~ ^[0-9]{1,12}$ ]] || return 1
  printf '%s' "$epoch"
}

# _ihdg_graded_row <rows-file> <query-rc> <host> <host_name> <expected_schema> <now_epoch> <max_row_age>
#
# THE ONE PLACE A PROBE ROW IS SELECTED AND GRADED FOR RECENCY, IDENTITY AND SHAPE. G1-G7 of the
# recut gate and E1-E7 of the execute gate are the same seven predicates; until #8054 they were
# ~110 lines inlined in `inngest_host_dark_gate` and the execute gate would have had to carry a
# second copy — the exact "two readers that disagree" class this family of defects keeps producing.
# Both entry points call this and then grade the CONTENT of the row they get back.
#
# On success prints TWO lines — the graded row's age in seconds, then its message — and returns
# 0. On refusal prints the refusal token alone and returns 1; the caller dispatches it through
# _ihdg_verdict. The message is guaranteed newline-free by the row/line count check below, so the
# two-line split is exact.
_ihdg_graded_row() {
  local rows_file="$1" query_rc="$2" host="$3" host_name="$4" expected_schema="$5"
  local now_epoch="$6" max_row_age="$7"

  # ── G1 — the read path answered, and its result is countable ────────────────────
  # EVALUATED FIRST, BEFORE G2. A 503 from the ClickHouse read path yields zero rows; refusing with
  # `silent` there would be a true refusal and a false diagnosis. Measured 2026-09-03: the read
  # path returned HTTP 503 {"exception":"This source is currently under maintenance."} for the whole
  # session, and scripts/followthroughs/inngest-host-not-serving-7674.sh correctly returned
  # TRANSIENT reason=query_failed rather than converting a broken read into a host verdict. That is
  # the measured justification for this gate's `unreadable`-aborts posture — a gate that cannot see
  # the host must never conclude the host is dark.
  [[ "$query_rc" =~ ^[0-9]+$ ]] || { _ihdg_refuse unreadable; return 1; }
  [[ "$query_rc" -eq 0 ]]       || { _ihdg_refuse unreadable; return 1; }
  [[ -n "$rows_file" && -f "$rows_file" ]] || { _ihdg_refuse unreadable; return 1; }
  # E2 — BYTES THAT DO NOT DECODE ARE NOT SILENCE. A gzipped, truncated or HTML error body is a
  # file with lines and zero rows; refusing it as `silent` would send the operator to replace a
  # host whose read path is what broke. Non-empty lines >= 1 and decoded rows == 0 is a decode
  # failure (see `_ihdg_undecodable` for why NON-EMPTY, and why that is load-bearing).
  if _ihdg_undecodable "$rows_file"; then _ihdg_refuse unreadable; return 1; fi

  local rows_tsv rows_count
  rows_tsv="$(_ihdg_rows "$rows_file" "$host" "$host_name")" || { _ihdg_refuse unreadable; return 1; }
  # `grep -c` over a file, never `printf | grep -c`: under `set -o pipefail` a producer that takes
  # SIGPIPE turns a successful match into a non-zero pipeline. The count is derived, then validated
  # by an explicit ^[0-9]+$ predicate — `[[ "" -gt 0 ]]` is FALSE under bash coercion, so an
  # uncomputed count would silently satisfy every threshold.
  if [[ -z "$rows_tsv" ]]; then rows_count=0; else rows_count="$(printf '%s\n' "$rows_tsv" | wc -l)"; fi
  rows_count="${rows_count//[[:space:]]/}"
  # A MESSAGE CARRYING A NEWLINE IS NOT ONE MESSAGE, and the split happens HERE, upstream of every
  # predicate. `_ihdg_rows` renders `message` through `jq -r`, so one row containing a newline is
  # emitted as two physical lines; the selection loop below then takes the LAST as `newest_msg`
  # while `_ihdg_tied_newest` still counts ONE distinct message and passes. Constructed and
  # executed: a single row whose message read `http_code=200 server_active=active redis_keys=99999`
  # followed by a newline and a fully-dark second half returned `dark`, rc 0 — the serving half
  # discarded, the forged half graded, on a gate authorizing an irreversible destroy.
  #
  # Comparing jq's ROW count to the physical LINE count is the detector: they are equal exactly
  # when no message contains a newline.
  local rows_rowcount
  rows_rowcount="$(_ihdg_row_count "$rows_file" "$host" "$host_name")"
  [[ "$rows_rowcount" =~ ^[0-9]+$ ]] || { _ihdg_refuse unreadable; return 1; }
  [[ "$rows_rowcount" == "$rows_count" ]] || { _ihdg_refuse unreadable; return 1; }
  [[ "$rows_count" =~ ^[0-9]+$ ]] || { _ihdg_refuse unreadable; return 1; }

  # ── G5/G6 — envelope identity, COMPUTED BEFORE G2 SO THE ARM IS REACHABLE ───────
  # inngest-bootstrap.sh is the SHARED renderer for the dedicated host AND the co-located web host,
  # and apps/web-platform/infra/vector.toml multiplexes every host into ONE Logs source — so probe
  # rows from the wrong host are the common case, not an edge one. _ihdg_rows already DROPS them
  # via the two-field conjunction, which means by the time G2 runs they are indistinguishable from
  # no rows at all.
  #
  # THAT PLACEMENT IS THE BUG THIS ORDER EXISTS TO AVOID. A `wrong_host` arm evaluated AFTER the
  # silence check is unreachable for exactly the inputs it was written for: the filter has already
  # turned "forty rows, all from web-1" into "zero rows", G2 fires `silent`, and the operator is
  # told the dedicated host emits nothing when in fact their identity filter is wrong. The refusal
  # would be correct and the diagnosis a lie. So the wrong-host population is measured here, and
  # G2's zero-row branch chooses between the two tokens on evidence.
  #
  # (#6616 is OPEN: `host_name` has been observed lying — a web host self-labelling with the
  # sed-rendered `soleur-inngest-prd` literal — which is why `host`, Vector's auto-derived OS
  # hostname that a stale literal cannot forge, is required alongside it. G5 and G6 are separate
  # predicates for that reason: either one alone is spoofable.)
  #
  # A census of PROBE rows, through the same shared predicate the selector uses (#8846): decode,
  # `$_IHDG_PROBE`, then the NEGATED host conjunction. A forged event-log row from the web host is
  # not evidence that the identity filter is wrong, so it must not turn `silent` into `wrong_host`.
  local wrong_host_rows
  wrong_host_rows="$(jq -Rn --arg h "$host" --arg hn "$host_name" "$INNGEST_PROBE_ROW_JQ"'
      [ inputs | fromjson? | select(type == "object")
        | ((.raw? // empty) | fromjson?) as $d
        | select(($d | type) == "object")
        '"$_IHDG_PROBE"'
        | select(($d.host != $h) or ($d.host_name != $hn))
      ] | length' < "$rows_file" 2>/dev/null)"
  [[ "$wrong_host_rows" =~ ^[0-9]+$ ]] || { _ihdg_refuse unreadable; return 1; }

  # ── G2 — the host is not silent ─────────────────────────────────────────────────
  # SILENCE IS NOT EVIDENCE OF DARKNESS. A host emitting nothing is a host whose state is UNKNOWN,
  # and this is the exact fail-open class the G3.7 pre-filter was found to carry.
  if [[ "$rows_count" -lt 1 ]]; then
    if [[ "$wrong_host_rows" -gt 0 ]]; then _ihdg_refuse wrong_host; return 1; fi
    _ihdg_refuse silent; return 1
  fi

  # Row selection. `newest` is the last row by event time, full stop. `chosen` is the newest row
  # that carries a `probe_schema=` field at all — with a FALLBACK to `newest` when no row does, so
  # that a host emitting only pre-schema rows reports `stale_schema` (actionable: "replace the host
  # first") rather than `stale_row` (which would name the wrong problem).
  #
  # ONE FIELD PER LINE, deliberately. An earlier shape emitted `<dt>\t<message>` and read it with
  # `IFS=$'\t' read -r dt msg`. Tab is IFS-WHITESPACE, so bash COLLAPSES runs of it and drops an
  # empty leading field: a row whose `dt` was empty would parse as `dt=<message> msg=`, shifting
  # every field one position left and making the newest row invisible. jq has already sorted, so
  # bash never needs the timestamp.
  local newest_msg chosen_msg _msg
  newest_msg=""; chosen_msg=""
  while IFS= read -r _msg; do
    [[ -n "${_msg:-}" ]] || continue
    newest_msg="$_msg"
    if [[ "$_msg" == *"probe_schema="* ]]; then chosen_msg="$_msg"; fi
  done <<< "$rows_tsv"
  [[ -n "$chosen_msg" ]] || chosen_msg="$newest_msg"
  [[ -n "$newest_msg" ]] || { _ihdg_refuse unreadable; return 1; }

  # ── A TIE ON `dt` IS NOT A WINNER ───────────────────────────────────────────
  # `sort_by` is STABLE, so when two rows share the newest `dt` the one that survives is decided by
  # whatever order the query happened to emit them in — and the two can disagree. Constructed:
  # the same pair of rows, one dark and one reading `server_active=active redis_keys=9999`, gave
  # `dark` in one file order and `host_serving` in the other. Low reachability (`dt` carries
  # sub-second precision) but a verdict that depends on the caller's row order is not a
  # measurement. Tied-and-identical is fine; tied-and-disagreeing is a refusal.
  if [[ "$(_ihdg_tied_newest "$rows_file" "$host" "$host_name")" != "1" ]]; then
    _ihdg_refuse unreadable; return 1
  fi

  # ── THE CHOSEN ROW MUST BE THE NEWEST ROW ───────────────────────────────────
  # An earlier revision selected the newest row CARRYING `probe_schema=` and then bounded it with
  # G3's boot_id comparison. That is not a recency bound: boot_id is CONSTANT across every row of
  # one boot, so a schema-3 row from 90 minutes ago compared equal to a newest row emitted seconds
  # ago, and all sixteen row-derived predicates were then read off the older one.
  #
  # THE FIELD ORDER MAKES THAT MAXIMALLY ADVERSE. The emitter writes `http_code` and
  # `server_active` BEFORE `probe_schema`, and `redis_keys` after it — so a newest row truncated
  # anywhere in between carries the live proof that the host is SERVING, satisfies the boot pin,
  # and is then discarded in favour of a row that says the opposite. Constructed and executed
  # during review: a newest row reading `http_code=200 server_active=active` with no
  # `probe_schema=` returned `dark`, rc 0.
  #
  # So the chosen row is now required to BE the newest row. A newest row that cannot be graded is
  # `unreadable` — "nothing was measured" — never a licence to reach further back. The
  # no-schema-ANYWHERE case still falls through to G4's `stale_schema`, which is the actionable
  # verdict for a host running the pre-schema-3 renderer.
  if [[ "$chosen_msg" != "$newest_msg" ]]; then
    # ONE ARM, because the other one was dead. `chosen_msg` is assigned only when the message
    # carries `probe_schema=`, and otherwise falls back to `newest_msg` — which makes them EQUAL
    # and skips this block entirely. Reaching here therefore implies `chosen_msg` carries a schema,
    # the `if` always fired, and the `stale_schema` line beneath it was unreachable for every
    # possible rows-file. Its justifying comment also contradicted the one eight lines above,
    # which correctly states the no-schema-anywhere case falls through to G4. Measured both ways:
    # an all-pre-schema window returns `stale_schema` (from G4); an older schema-3 row under a
    # newer pre-schema row returns `unreadable` (from here).
    _ihdg_refuse unreadable; return 1
  fi

  # ── G3 — the newest row is RECENT ───────────────────────────────────────────────
  # THIS PREDICATE WAS A BOOT_ID COMPARISON AND IT WAS DEAD ON ARRIVAL — twice over. It compared
  # the chosen row's boot_id with the newest row's, which (a) could never differ once the block
  # above required the chosen row to BE the newest row, and (b) never bounded recency even before
  # that, because boot_id is CONSTANT across every row of one boot: a row from 90 minutes ago and a
  # row from ten seconds ago carry the same boot_id and compared equal. The check that reads like a
  # staleness bound and is not one is worse than no check, because the argument in this file's
  # header cites it as though it were.
  #
  # So G3 is now the wall-clock bound the header always assumed: the newest qualifying row must be
  # no older than `max_row_age`. That is what makes "the store was empty" a claim about NOW rather
  # than about some point in a query window the caller chose. The boot_id PRESENCE check is kept —
  # and since #8054 it is joined by a SHAPE check (E7 below): a `boot_id=unknown` row, the emitter's
  # /proc-read-failed fallback, now refuses BOTH consumers as `unreadable` where the recut gate
  # previously accepted it. Safe direction; recorded in ADR-100's 2026-09-11 addendum.
  local chosen_boot
  chosen_boot="$(_ihdg_field "$chosen_msg" boot_id)" || { _ihdg_refuse unreadable; return 1; }
  [[ -n "$chosen_boot" ]]                            || { _ihdg_refuse unreadable; return 1; }
  # E7 — AND IT IS THE /proc SHAPE. The emitter reads /proc/sys/kernel/random/boot_id (a hyphenated
  # UUID) and falls back to the literal `unknown`; the execute gate strips the hyphens to form the
  # journald `_BOOT_ID` join key (#8054). A degenerate value — `unknown`, an all-hyphen string that
  # strips to "", the already-stripped form — must refuse HERE, in bash, before any jq program sees
  # it as `$bid`: an empty or wrong-shaped join key is how "no matching row" becomes "a match".
  [[ "$chosen_boot" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]] || { _ihdg_refuse unreadable; return 1; }

  [[ "$max_row_age" =~ ^[0-9]{1,9}$ ]] || { _ihdg_refuse unreadable; return 1; }
  if [[ -z "$now_epoch" ]]; then now_epoch="$(date -u +%s 2>/dev/null)"; fi
  [[ "$now_epoch" =~ ^[0-9]{1,12}$ ]]  || { _ihdg_refuse unreadable; return 1; }

  local newest_dt newest_epoch row_age
  newest_dt="$(_ihdg_newest_dt "$rows_file" "$host" "$host_name")"
  [[ -n "$newest_dt" ]] || { _ihdg_refuse unreadable; return 1; }
  # The `dt` -> epoch path is `_ihdg_epoch_from_dt`, shared with the heartbeat side of the execute
  # gate so the shape regex and the UTC pin cannot be re-implemented differently there (#8054).
  newest_epoch="$(_ihdg_epoch_from_dt "$newest_dt")" || { _ihdg_refuse unreadable; return 1; }

  row_age=$(( now_epoch - newest_epoch ))
  # A row from the FUTURE is not fresh, it is a clock or an ingestion problem — and it is the one
  # sign shape that would sail through a `-le` bound on a signed difference.
  [[ "$row_age" -ge 0 ]]              || { _ihdg_refuse stale_row; return 1; }
  [[ "$row_age" -le "$max_row_age" ]] || { _ihdg_refuse stale_row; return 1; }
  # HOW REACHABLE IS THIS, HONESTLY. The recut workflow queries `--since 90m` and this bound
  # defaults to 5400s, so under THAT caller almost no row that arrives here can exceed it — a row
  # older than the window is not returned at all, and the gate answers `silent` instead. The execute
  # gate's caller reads `--since 24h` precisely so that this arm IS reachable there (#8054): the
  # window has to exceed the bound or `stale_row` collapses into `silent`. Said plainly rather than
  # left for a reader to assume this predicate is carrying independent weight, which is the
  # mistake the boot_id version of G3 got away with for a whole merge.
  #
  # It is kept, and it is not decorative, for four reasons: the bound belongs to the GATE rather
  # than to one caller (the same posture as sorting rows here instead of trusting the query);
  # clock skew between the log service and the runner can push a returned row past the bound;
  # the FUTURE arm above is reachable regardless of any window; and `--since` is a workflow literal
  # that a later edit can widen — which is why Row 7 of the suite pins it at 90m on BOTH queries
  # and counts them, so widening the window and leaving this bound behind reddens rather than
  # silently making the emptiness claim older than the argument that justifies it.

  # ── G4 — probe_schema is EXACTLY the expected schema (8 today) ──────────────────
  # EXACT EQUALITY, NOT `>=`. A `>=` comparison would silently accept a FUTURE schema whose field
  # semantics this gate has never seen — the same "a lenient extractor makes absence satisfy
  # everything" shape one version forward. A schema bump must force a deliberate edit here.
  #
  # BUMPED 7 -> 8 (#8017/#8015/#8013, 2026-09-10) when the emitter gained `data_mount_devid`,
  # `data_mount_base` and `registry_fns`, and the key histogram became identifier-aware. The
  # earlier 3 -> 4 bump (#7695) added `redis_key_patterns`. The bump is
  # the point: a bare `redis_keys` count cannot answer "is this residue or state someone needs?",
  # which is the question the recut runbook's "confirm before emptying anything" actually asks. A
  # host still on the schema-3 image emits no `redis_key_patterns`, and grading it here would
  # authorize a destroy against evidence this gate cannot see. `stale_schema` is the correct and
  # actionable verdict for such a host: deliver the new image first.
  #
  # `stale_schema` is the EXPECTED verdict for every dispatch until the host is replaced: the
  # running host's boot_id has been unchanged for weeks, so it emits no probe_schema at all. That is
  # intended and is the mechanical interlock making Phase 2 -> Phase 3 an ordering CONSTRAINT rather
  # than operator discipline — before the new emitter is live the recut is unreachable by
  # construction. It stays its own token precisely because it is actionable ("replace the host
  # first") where `unreadable` is not.
  local schema
  schema="$(_ihdg_field "$chosen_msg" probe_schema)" || { _ihdg_refuse stale_schema; return 1; }
  [[ "$schema" == "$expected_schema" ]]              || { _ihdg_refuse stale_schema; return 1; }

  printf '%s\n%s\n' "$row_age" "$chosen_msg"
  return 0
}

# _ihdg_verdict <token> — echo the token, rc 0 only for the literal `dark`.
_ihdg_verdict() {
  printf '%s\n' "$1"
  [[ "$1" == "dark" ]]
}

# ═══════════════════════════════════════════════════════════════════════════════════════════════
# inngest_execute_registry_gate — `op=execute` step 2.0 (#8054). The lib's one live entry point.
#
# PROPERTY. `scripts/cutover-inngest.sh op=execute` (the P0 cutover step) proceeds past 2.0 only
# when the dedicated inngest host is established, from evidence the host itself emitted, to be
# carrying no function registry that could double-fire. 2.0's reachable-empty arm (webhook HTTP 200,
# `registry_empty=true`) is unchanged and does not come here. THIS gate is the other reading: the
# host is POSITIVELY DARK — `inngest-server-flip-guard.sh` (P1-5) refuses a prod-URI start while
# `INNGEST_CUTOVER_FLIP` is outside {armed, flipping, flushed, done}, and every pre-arm value is
# outside it — and its own flip FSM attested, within `--hb-max-age` on the SAME boot, that the flag
# is pre-arm. A host that cannot start cannot register a function. Every state in which darkness
# cannot be established refuses; silence is not darkness.
#
# WHY A HEARTBEAT. The probe row is hourly, so on its own it proves darkness as of up to 90 minutes
# ago. `inngest-cutover-flip.timer` fires every 30 s and its FSM emits one JSON line per tick on
# EVERY flag, terminal ones included (P0-1/P0-2: `noop-aborted`, `noop-rolled-back`, `noop-done`),
# carrying the journald `_BOOT_ID`. That is a ~1-2/min attestation of "this boot's flag is X", and
# joined on the boot id it upgrades the probe's stale darkness to a fresh one. The bridge is
# FRESHNESS, not corroboration: the probe row's `cutover_flag` and the heartbeat's `.message.flag`
# are each graded against the same allowlist, and they may legitimately differ (`aborted` on the
# hourly row, `rolled-back` on the minute-old heartbeat) — only the NEWEST same-boot heartbeat is
# graded, never "any arm-set flag in the window".
#
# HISTORY OF THE `server_active` PREDICATE (#8078). The retired recut gate's G8 once required
# `server_active == "inactive"`, and the P1-5 refuse loop leaves the unit in `activating`
# indefinitely (measured 2026-09-11 on the live host), so that gate refused today's host as
# `host_serving`. E10 below is the surviving form: `server_active` present, non-empty,
# `!= "unknown"`, `!= "active"`. `activating`, `failed`, `inactive` are all not-serving; `active`
# alone is serving. The wide reading is safe for the execute gate because E9 (`http_code != 200`)
# excludes a bound listener and E11/E13 refuse any cutover flag outside the pre-arm set, so
# `activating` under the P1-5 refusal cannot progress to `active` without leaving that set.
#
# E-TABLE (evaluation order; population before silence, identity before content):
#   E1  probe --query-rc numeric and 0                                      unreadable
#   E2  rows file decodes (raw lines >= 1 and decoded == 0 is a decode fail) unreadable
#   E3  >= 1 row from ANY host; then >= 1 from soleur-inngest/-prd          silent / wrong_host
#   E4  newest row is the graded row, tie-free                              unreadable
#   E5  row age <= --max-row-age, and not from the future                    stale_row
#   E6  probe_schema == --expected-schema exactly                            stale_schema
#   E7  boot_id present, /proc UUID shape, strips to 32 hex                  unreadable
#   E8  host_role == dedicated                                               wrong_host
#   E9  http_code numeric; != 200                                            unreadable / host_serving
#   E10 server_active present, non-empty, != unknown; != active              unreadable / host_serving
#   E11 cutover_flag in {aborted, rolled-back} (POSITIVE allowlist)           flag_armed / flag_unreadable
#   E12 registry_fns == __UNREADABLE__ (entailed by E9 on the real emitter)   unreadable
#   E13 heartbeat: --hb-rc 0; --hb-max-age numeric; file decodes; newest      fsm_unreadable /
#       same-boot inngest-cutover-flip object row age in [0, --hb-max-age];  fsm_silent /
#       its .message.flag graded by the E11 partition, in bash, after select flag_armed / flag_unreadable
#   E14 the probe row postdates the newest same-boot FSM TRANSITION (reason   stale_row
#       not noop-*) in the heartbeat window
#   —   all hold                                                             dark (rc 0)
#
# The CALLER adds one refusal of its own BEFORE this gate runs — `webhook_path`: the webhook's
# non-200 must carry the web-host probe's own fetch-failure signature (HTTP 500 + __FETCH_FAILED__)
# or the script refuses without reading Better Stack at all. It is a script token, not a lib one.
#
# E1-E7 ARE `_ihdg_graded_row` (historically G1-G6 of the retired recut gate, plus the boot_id shape
# check — see the ADR-100 2026-09-11 addendum §7). E8/E9 are the same predicate lines as the retired
# gate's G7/G9. With one entry point the suite's mutation harness runs every row against it; a
# helper tightening that reddens only one place is a copy, and copies are how this family of
# defects recurs.
#
# Usage:
#   source tests/scripts/lib/inngest-host-dark-gate.sh
#   ERG_RC=0; ERG_VERDICT="$(inngest_execute_registry_gate \
#     --rows-file <probe rows: betterstack-query.sh JSONEachRow, --grep SOLEUR_INNGEST_SERVER_PROBE> \
#     --query-rc <n> \
#     --hb-file   <heartbeat rows: same shape, --grep inngest-cutover-flip> \
#     --hb-rc     <n> \
#     [--emit-file <abs path>] [--now-epoch <n>] [--max-row-age 5400] [--hb-max-age 900] \
#     [--host soleur-inngest] [--host-name soleur-inngest-prd] [--expected-schema 8])" || ERG_RC=$?
#   # stdout is EXACTLY the verdict token; rc 0 ONLY for `dark`. The caller runs `set -e`, so the
#   # `|| ERG_RC=$?` shape is load-bearing: a bare `$(…)` aborts before any `::error::` prints.
#   # `--emit-file` receives `key=value` lines (flag, boot_id, row_age, hb_age, hb_flag), each
#   # written ONLY after its own predicate passed, so the caller's notice never re-parses a row.
# ═══════════════════════════════════════════════════════════════════════════════════════════════

# _erg_flag_class <flag> — `preflip` | `armed` | `unreadable`. ONE definition of the P1-5 partition
# for both the probe row (E11) and the heartbeat (E13), and the test suite asserts the `armed` arm
# is SET-EQUAL to inngest-server-flip-guard.sh's own `case` allowlist — the partition already drifted
# once (#6553 added `flushed`), and a retyped copy is the recurrence path. A POSITIVE allowlist for
# the pass class: `unknown` (the emitter's read-failed sentinel), `rollback` (in flight), empty and
# absent all land on `unreadable`, never on `preflip` — G20 in this file once let "" clear.
_erg_flag_class() {
  case "$1" in
    aborted|rolled-back) printf 'preflip' ;;
    armed|flipping|flushed|done) printf 'armed' ;;
    *) printf 'unreadable' ;;
  esac
}

# _erg_emit <emit-file|""> <key> <value>   (execute-gate-only helper: `_erg_` prefix)
#
# Append one validated `key=value` line to the caller's `--emit-file` side channel, or do nothing
# when no file was given. The value MUST already have passed the predicate that validates it — the
# gate's contract with its caller is that nothing in this file is a raw row field. A failed append
# is swallowed: the caller's notice then prints `__UNREAD__` for that field, which is a visible
# degradation of a diagnostic, never a change of verdict.
_erg_emit() {
  local emit_file="$1" key="$2" value="$3"
  [[ -n "$emit_file" ]] || return 0
  printf '%s=%s\n' "$key" "$value" >> "$emit_file" 2>/dev/null || true
  return 0
}

# _erg_hb_newest <hb-file> <host> <host_name> <bid>   (execute-gate-only helper: `_erg_` prefix)
#
# The newest `inngest-cutover-flip` heartbeat row on boot `<bid>` from the named host, as THREE
# lines: its `dt`; its `.message.flag` (or `__ABSENT__`); and the `dt` of the newest same-boot
# TRANSITION row — a parsed row whose `.message.reason` does not start with `noop-` — or `-` when
# there is none in the window. Prints NOTHING when no row qualifies, the single line `__TIE__` when
# two rows at the newest `dt` carry different flags, and the single line `__UNPARSED__` when
# same-boot rows under the tag EXIST but none carries an OBJECT `.message` — OR when a same-boot
# row NEWER than the newest parsed one carries a STRING `.message` that begins with `{` (a
# heartbeat the warehouse did not parse; the FSM's own plain-text lines under the same tag —
# `SOLEUR_INNGEST_CUTOVER_VERIFY_FAILED …`, `latch-unrecordable …` — never begin with `{` and are
# skipped, never graded).
#
# WHY `__UNPARSED__` IS ITS OWN SENTINEL: the FSM logs a JSON STRING (`logger -t
# inngest-cutover-flip "$json"`), Vector re-encodes it as a string, and it is BETTER STACK that
# parses it into an object at ingest (measured 2026-09-11: `.message = {"flag":…}` in the
# warehouse). If that parse stops, every heartbeat is present and unreadable — a read-path change,
# not a dead timer, and telling the operator to replace the host for it would be the wrong remedy.
#
# WHY THE TRANSITION `dt` IS RETURNED: the probe row is hourly and the FSM can change the host's
# state in between — an arm that started the server and then aborted (`verify_or_abort`, whose own
# text names the case "a prod scheduler is STILL RUNNING on this host under a terminal flag").
# After such a transition the probe row's darkness describes a state that no longer exists, so the
# execute gate refuses (`stale_row`) until a probe row POSTDATING the transition lands — which will
# then read `http_code=200` if the server is in fact bound. `noop-*` reasons are idle heartbeats
# (P0-1/P0-2), not transitions, and are excluded from that comparison.
#
# The selector filters on TYPE and IDENTITY only — identifier, host pair, a string `_BOOT_ID` equal
# to the join key, an object `.message` — NEVER on the flag's value: a value filter would skip a
# fresh `armed` and pass on a stale `aborted` (suite row 22). The flag is graded in bash by the
# caller.
_erg_hb_newest() {
  local hb_file="$1" host="$2" host_name="$3" bid="$4"
  jq -Rn --arg h "$host" --arg hn "$host_name" --arg b "$bid" '
      [ inputs
        | fromjson?
        | select(type == "object")
'"$_IHDG_IDENT"'
        | select($d.SYSLOG_IDENTIFIER == "inngest-cutover-flip")
        | select(($d._BOOT_ID | type) == "string")
        | select($d._BOOT_ID == $b)
        | { dt: ($outer.dt // ""), obj: (($d.message | type) == "object"),
            jsonstr: ((($d.message | type) == "string") and ($d.message | startswith("{"))),
            flag: (if ($d.message | type) == "object" then (($d.message.flag // "__ABSENT__") | tostring) else "" end),
            transition: ((($d.message | type) == "object") and ((($d.message.reason // "") | tostring | startswith("noop-")) | not)) }
      ] as $tagged
      | ($tagged | map(select(.obj))) as $rows
      | if ($tagged | length) == 0 then empty
        elif ($rows | length) == 0 then "__UNPARSED__"
        else ($rows | map(.dt) | max) as $newest
           | if ([ $tagged[] | select(.jsonstr and .dt > $newest) ] | length) > 0 then "__UNPARSED__"
             else
               ($rows | map(select(.dt == $newest) | .flag) | unique) as $flags
               | ([ $rows[] | select(.transition) | .dt ] | max // "-") as $transition
               | if ($flags | length) != 1 then "__TIE__" else "\($newest)\n\($flags[0])\n\($transition)" end
             end
        end
    ' -r < "$hb_file" 2>/dev/null
}

inngest_execute_registry_gate() {
  # ── E0 — the probe-row selector is LOADED (#8846) ───────────────────────────────
  # Same refusal, same position, same reason as the sibling's G0. The message is the shared
  # `_ihdg_selector_unavailable`; the `_ihdg_verdict` call stays here for the reason the whitelist
  # `case` below records (a helper may not call `_ihdg_verdict`). Both production callers truncate
  # the emit file themselves before the call, so refusing ahead of this gate's own truncation
  # leaves no stale value for the caller's notice to read.
  if [[ "${_IHDG_PROBE_LIB_OK:-0}" != "1" ]]; then
    _ihdg_selector_unavailable
    _ihdg_verdict "unreadable"; return $?
  fi
  local rows_file="" query_rc="" hb_file="" hb_rc="" emit_file=""
  local host="soleur-inngest" host_name="soleur-inngest-prd" expected_schema="$_IHDG_EXPECTED_SCHEMA"
  # Two freshness bounds, both NUMERIC seconds. The caller's `FLIP_LIVENESS_SINCE` is the string
  # "15m" for its Better Stack `--since`; it is NOT this operand, and a non-numeric value here refuses.
  local now_epoch="" max_row_age="5400" hb_max_age="900"

  while [[ $# -gt 0 ]]; do
    # A trailing flag with no value: `shift 2` would be a no-op and the loop would spin forever
    # under the caller's `||` guard. A hang is not a verdict (the sibling learned this first).
    if [[ "$1" == --* && $# -lt 2 ]]; then _ihdg_verdict "unreadable"; return $?; fi
    case "$1" in
      --rows-file)        rows_file="${2-}";        shift 2 ;;
      --query-rc)         query_rc="${2-}";         shift 2 ;;
      --hb-file)          hb_file="${2-}";          shift 2 ;;
      --hb-rc)            hb_rc="${2-}";            shift 2 ;;
      --emit-file)        emit_file="${2-}";        shift 2 ;;
      --host)             host="${2-}";             shift 2 ;;
      --host-name)        host_name="${2-}";        shift 2 ;;
      --expected-schema)  expected_schema="${2-}";  shift 2 ;;
      --now-epoch)        now_epoch="${2-}";        shift 2 ;;
      --max-row-age)      max_row_age="${2-}";      shift 2 ;;
      --hb-max-age)       hb_max_age="${2-}";       shift 2 ;;
      *) echo "inngest_execute_registry_gate: unknown argument '$1'" >&2; _ihdg_verdict "unreadable"; return $? ;;
    esac
  done

  # The emit file is the validated-values side channel the caller's `::notice::` reads. It is
  # TRUNCATED here, so it must be an absolute path the caller owns (P1b relative-operand rule: a
  # bare filename would truncate a tracked file in a suite run from the repo root). Values are
  # appended ONLY after the predicate that validated them.
  if [[ -n "$emit_file" ]]; then
    case "$emit_file" in
      /*) : ;;
      *)  echo "inngest_execute_registry_gate: --emit-file must be absolute" >&2; _ihdg_verdict "unreadable"; return $? ;;
    esac
    case "$emit_file" in */../*|*/..) _ihdg_verdict "unreadable"; return $? ;; esac
    : > "$emit_file" || { _ihdg_verdict "unreadable"; return $?; }
  fi

  # Both bounds validated BEFORE any read: `[[ "" -le 5 ]]` is FALSE under bash coercion, but an
  # operand that fails validation must name itself, not surface as a stale-row refusal.
  [[ "$max_row_age" =~ ^[0-9]{1,9}$ ]] || { _ihdg_verdict "unreadable"; return $?; }
  [[ "$hb_max_age" =~ ^[0-9]{1,9}$ ]]  || { _ihdg_verdict "fsm_unreadable"; return $?; }
  if [[ -z "$now_epoch" ]]; then now_epoch="$(date -u +%s 2>/dev/null)"; fi
  [[ "$now_epoch" =~ ^[0-9]{1,12}$ ]]  || { _ihdg_verdict "unreadable"; return $?; }

  # ── E1..E7 — the graded row, via the helper shared with inngest_host_dark_gate ───
  local graded row_age chosen_msg
  if ! graded="$(_ihdg_graded_row "$rows_file" "$query_rc" "$host" "$host_name" "$expected_schema" "$now_epoch" "$max_row_age")"; then
    # LITERAL tokens only, by whitelist. The helper's stdout is what it printed — and if a helper
    # ever leaked something that is not a token, dispatching `$graded` would put it on THIS gate's
    # stdout, which the caller prints. Anything unrecognised is `unreadable`. This block is
    # DELIBERATELY duplicated in the other entry point rather than hoisted: a shared dispatcher
    # would be a `_ihdg_*` helper calling `_ihdg_verdict` (policy in a helper — the suite forbids
    # it), and `_ihdg_verdict "$graded"` would put a variable where the suite requires a literal.
    case "$graded" in
      silent)       _ihdg_verdict "silent";       return $? ;;
      wrong_host)   _ihdg_verdict "wrong_host";   return $? ;;
      stale_row)    _ihdg_verdict "stale_row";    return $? ;;
      stale_schema) _ihdg_verdict "stale_schema"; return $? ;;
      *)            _ihdg_verdict "unreadable";   return $? ;;
    esac
  fi
  row_age="${graded%%$'\n'*}"; chosen_msg="${graded#*$'\n'}"
  [[ "$row_age" =~ ^[0-9]+$ && -n "$chosen_msg" ]] || { _ihdg_verdict "unreadable"; return $?; }
  # E7's join key. The helper is the AUTHORITY on the boot_id's shape (the /proc UUID regex lives
  # there, once, and is mutated by the suite against both consumers); a second regex here would be
  # an equivalent mutant's hiding place — the harness reports a masked line as dead code.
  local boot_id bid
  boot_id="$(_ihdg_field "$chosen_msg" boot_id)" || { _ihdg_verdict "unreadable"; return $?; }
  bid="${boot_id//-/}"
  _erg_emit "$emit_file" boot_id "$boot_id"
  _erg_emit "$emit_file" row_age "$row_age"

  # ── E8 — the row says it is the dedicated host ──────────────────────────────────
  local host_role
  host_role="$(_ihdg_field "$chosen_msg" host_role)" || { _ihdg_verdict "wrong_host"; return $?; }
  [[ "$host_role" == "dedicated" ]]                  || { _ihdg_verdict "wrong_host"; return $?; }

  # ── E9 — the loopback did NOT answer 200 ────────────────────────────────────────
  # An ABSENT http_code must not read as "non-200": presence, then shape, then the comparison.
  local http_code
  http_code="$(_ihdg_field "$chosen_msg" http_code)" || { _ihdg_verdict "unreadable"; return $?; }
  [[ "$http_code" =~ ^[0-9]+$ ]]                     || { _ihdg_verdict "unreadable"; return $?; }
  [[ "$http_code" != "200" ]]                        || { _ihdg_verdict "host_serving"; return $?; }

  # ── E10 — systemd does not say the unit is active ───────────────────────────────
  # `!= active`, not `== inactive` — see the header. `unknown` is the emitter's read-failed
  # sentinel and a blank is a shape change; neither is a claim about the unit.
  local server_active
  server_active="$(_ihdg_field "$chosen_msg" server_active)" || { _ihdg_verdict "unreadable"; return $?; }
  [[ -n "$server_active" && "$server_active" != "unknown" ]] || { _ihdg_verdict "unreadable"; return $?; }
  [[ "$server_active" != "active" ]]                        || { _ihdg_verdict "host_serving"; return $?; }

  # ── E11 — the probe row's cutover flag is pre-arm, by POSITIVE allowlist ────────
  # This `case` and E13's are the same three arms modulo the emit key; they stay duplicated for
  # the reason the whitelist `case` above records — hoisting them would put `_ihdg_verdict` inside a
  # helper, which the suite forbids.
  local cutover_flag flag_class
  cutover_flag="$(_ihdg_field "$chosen_msg" cutover_flag)" || cutover_flag=""
  flag_class="$(_erg_flag_class "$cutover_flag")"
  case "$flag_class" in
    preflip) _erg_emit "$emit_file" flag "$cutover_flag" ;;
    armed)   _erg_emit "$emit_file" flag "$cutover_flag"; _ihdg_verdict "flag_armed"; return $? ;;
    *)       _erg_emit "$emit_file" flag "__UNREADABLE__"; _ihdg_verdict "flag_unreadable"; return $? ;;
  esac

  # ── E12 — coherence: a refused loopback cannot have yielded a registry count ────
  # `registry_fns` (#8015) is `__UNREADABLE__` exactly when the GQL read did not yield an array,
  # which a non-200 loopback entails on the real emitter. A NUMBER here beside `http_code != 200`
  # — `0` included; `0` is a measurement, never an absence — means the row contradicts itself.
  local registry_fns
  registry_fns="$(_ihdg_field "$chosen_msg" registry_fns)" || { _ihdg_verdict "unreadable"; return $?; }
  [[ "$registry_fns" == "__UNREADABLE__" ]]                || { _ihdg_verdict "unreadable"; return $?; }

  # ── E13 — the flip FSM's heartbeat, same boot, fresh, pre-arm ───────────────────
  [[ "$hb_rc" =~ ^[0-9]+$ ]] || { _ihdg_verdict "fsm_unreadable"; return $?; }
  [[ "$hb_rc" -eq 0 ]]       || { _ihdg_verdict "fsm_unreadable"; return $?; }
  [[ -n "$hb_file" && -f "$hb_file" ]] || { _ihdg_verdict "fsm_unreadable"; return $?; }
  # Decode coherence, as E2: bytes that do not decode are a broken read, not a silent FSM.
  if _ihdg_undecodable "$hb_file"; then _ihdg_verdict "fsm_unreadable"; return $?; fi

  local hb_out hb_lines hb_dt hb_flag hb_transition hb_epoch hb_age
  hb_out="$(_erg_hb_newest "$hb_file" "$host" "$host_name" "$bid")" || { _ihdg_verdict "fsm_unreadable"; return $?; }
  [[ -n "$hb_out" ]] || { _ihdg_verdict "fsm_silent"; return $?; }
  [[ "$hb_out" != "__TIE__" ]] || { _ihdg_verdict "fsm_unreadable"; return $?; }
  # Same-boot heartbeat rows are PRESENT but none is a parsed object (or the newest JSON-shaped one
  # is unparsed) — the warehouse's ingest-side JSON parse (not Vector's, not the FSM's) has changed.
  # Unreadable, never silent: the timer is demonstrably alive.
  [[ "$hb_out" != "__UNPARSED__" ]] || { _ihdg_verdict "fsm_unreadable"; return $?; }
  hb_lines="$(printf '%s\n' "$hb_out" | wc -l)"
  [[ "${hb_lines//[[:space:]]/}" == "3" ]] || { _ihdg_verdict "fsm_unreadable"; return $?; }
  hb_dt="${hb_out%%$'\n'*}"; hb_transition="${hb_out##*$'\n'}"
  hb_flag="${hb_out#*$'\n'}"; hb_flag="${hb_flag%$'\n'*}"
  # Same `dt` -> epoch path as the probe row (shared helper), same sign discipline as G3/E5.
  hb_epoch="$(_ihdg_epoch_from_dt "$hb_dt")" || { _ihdg_verdict "fsm_unreadable"; return $?; }
  hb_age=$(( now_epoch - hb_epoch ))
  [[ "$hb_age" -ge 0 ]]             || { _ihdg_verdict "fsm_silent"; return $?; }
  [[ "$hb_age" -le "$hb_max_age" ]] || { _ihdg_verdict "fsm_silent"; return $?; }
  _erg_emit "$emit_file" hb_age "$hb_age"
  # ── E14 — the probe row POSTDATES the newest FSM transition on this boot ────────
  # The graded probe row is up to `max_row_age` old; a transition (an arm that started the server
  # and aborted, a rollback, a flip) since then means its darkness describes a state that no longer
  # exists. Refuse until a probe row from AFTER the transition lands — the same `stale_row` token
  # and wait the hourly cadence already gives. `-` means no transition in the heartbeat window.
  if [[ "$hb_transition" != "-" ]]; then
    local hb_transition_epoch row_epoch
    hb_transition_epoch="$(_ihdg_epoch_from_dt "$hb_transition")" || { _ihdg_verdict "fsm_unreadable"; return $?; }
    row_epoch=$(( now_epoch - row_age ))
    [[ "$hb_transition_epoch" -le "$row_epoch" ]] || { _ihdg_verdict "stale_row"; return $?; }
  fi
  # The flag, graded in bash on the NEWEST same-boot row, by the same partition as E11.
  case "$(_erg_flag_class "$hb_flag")" in
    preflip) _erg_emit "$emit_file" hb_flag "$hb_flag" ;;
    armed)   _erg_emit "$emit_file" hb_flag "$hb_flag"; _ihdg_verdict "flag_armed"; return $? ;;
    *)       _erg_emit "$emit_file" hb_flag "__UNREADABLE__"; _ihdg_verdict "flag_unreadable"; return $? ;;
  esac

  _ihdg_verdict "dark"
}
