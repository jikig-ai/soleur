# shellcheck shell=bash
# Guard 2 — inngest_host_dark_gate. The fifth authorization layer for the inngest-volume-recut
# apply_target (#7695), and the only one that checks the WORLD rather than an intent.
#
# Layers 1-4 authorize by intent: a human approved the environment, a confirm literal was typed, a
# volume id was pinned, a plan document matched a shape. Every one of them can be fully satisfied
# while the host is serving live traffic and the store holds armed reminders. This gate is the one
# that measures.
#
# PROPERTY. The recut cannot be dispatched unless, on ONE SINGLE probe row from the CURRENT boot of
# the DEDICATED host, the store is measured empty and the host measured dark — and, at dispatch
# time, four live re-reads still agree.
#
# ── WHY A ≤90-MINUTE-OLD ROW IS SOUND EVIDENCE OF AN EMPTINESS THAT HOLDS AT APPLY TIME ─────────
#
# The obvious objection to authorizing an irreversible destroy on a log row is that the row is a
# snapshot: `inngest-server-probe.timer` fires hourly, so the chosen row can be up to ~90 minutes
# old, and "the store was empty then" is not "the store is empty now". The argument that closes the
# gap is a MONOTONICITY argument, and it lives here rather than in the plan because a reader of the
# gate is exactly the person who needs it:
#
#   1. inngest-server is the only writer that can INCREASE the key count. It is not the only
#      writer full stop — an earlier revision of this comment said it was, and that was false and
#      is corrected here rather than quietly reworded. Measured: `redis-cli` has THREE in-repo
#      callers against this instance. `inngest-cutover-flip.sh` issues `FLUSHALL` (a writer, and
#      the one condition 3 below exists to exclude); `inngest-bootstrap.sh`'s probe issues
#      `INFO keyspace` (a reader); the third is a test. The mechanism is also not the one that
#      sentence named: the loopback bind comes from `inngest-redis.conf` (`bind 127.0.0.1 -::1`,
#      `protected-mode yes`), not from the unit, and the unit contributes `--requirepass`. So
#      Redis is unreachable OFF the box and credential-gated ON it — which is a different and
#      weaker statement than "reachable from nothing else", and the argument below only needs the
#      weaker one.
#
#      The corrected form is a MONOTONICITY claim over all three callers, and it is strictly
#      stronger than the false one: the only non-server writer decreases the count, and the reader
#      does not write at all.
#   2. G8 ∧ G9 prove inngest-server was NOT BOUND on the newest row — `server_active=inactive` AND
#      a non-200 loopback `http_code`. A process that is not running and not answering cannot have
#      written a key since that row was emitted.
#   3. G19 proves no concurrent FLUSHALL can be AUTHORIZED: the cutover flip FSM only writes to
#      this Redis under `INNGEST_CUTOVER_FLIP` ∈ {arm, execute}, and G19 re-reads the flag
#      SYNCHRONOUSLY at dispatch time (not from the row) and refuses anything but
#      `rolled-back`/`aborted`. The row is a ≤90-minute-old snapshot; the flag is the thing that
#      actually authorizes a write, and it is readable in real time.
#   4. Armed reminders, if any survived, only CONSUME keys when they fire — a `BRPOP`-shaped
#      dequeue removes, it does not add.
#   5. The flip FSM's `FLUSHALL` sets the count to 0 — but it is NOT harmless on a race, and an
#      earlier revision of this comment said it was. `run_preflush_flip` in
#      inngest-cutover-flip.sh runs stop -> FLUSHALL -> assert -> record_flush_latch ->
#      **start_server**, and the `flushed` resume arm calls start_server with no flush at all. So
#      the raced transition's LAST act starts the only writer that can increase the count. Its
#      trigger is also outside GitHub's reach: inngest-cutover-flip.timer is OnBootSec=30s /
#      OnUnitActiveSec=30s, ships enabled for the host's life, and polls a Doppler flag — so the
#      `deploy-inngest-restart` concurrency group, which serialises WORKFLOW JOBS, cannot serialise
#      it. G19 therefore SAMPLES the flag; it does not hold it. That residual window (G19's read to
#      the apply) is real and is recorded here rather than argued away.
#
# So between the chosen row and the apply the key count cannot INCREASE. A count of 0 at t-90min
# under (1)-(4) is a count of 0 at t. The claim being made is bounded and checkable, which is the
# point: the alternative is an operator asserting from memory that nothing is running.
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
#   stale_schema  — the host is emitting, but from a pre-probe_schema=3 renderer. ACTIONABLE:
#                   replace the host first. This is the EXPECTED verdict for every dispatch until
#                   the host is replaced, and collapsing it into `unreadable` would tell the
#                   operator to retry forever against a host that can never satisfy the gate.
# This gate therefore reuses that script's host-conjunction QUERY FILTER (the two-field envelope
# identity, #7674 / #6616) and its R_SPOOF fixture shape — not its function.
#
# ── POSITIVE ALLOWLIST ──────────────────────────────────────────────────────────────────────────
#
# The decision function proceeds ONLY on the literal `dark`. Every other token aborts, `unreadable`
# included. This deliberately INVERTS the posture of the G3.7 pre-filter, which may only ADD a
# refusal and so degrades safely to the on-host latch when a read fails. Here the gate is
# authorizing an irreversible destroy: a gate that cannot see the host must never conclude the host
# is dark.
#
# ── THE TWENTY PREDICATES ───────────────────────────────────────────────────────────────────────
#
# ONE PER PREDICATE, NOT ONE PER TOKEN. Several predicates share a verdict token (three map to
# `wrong_host`, two to `host_serving`, four to `unreadable`), so a drop-one battery keyed on TOKENS
# needs only ~10 cases and silently under-covers: dropping G12 and dropping G15 both still emit
# `unreadable`, so a token-keyed battery cannot tell that one of them was deleted. AC B11's battery
# is keyed on PREDICATES — one case per Gn — and tests/scripts/test-inngest-host-dark-gate.sh
# asserts a floor of 20 such cases.
#
#   Row selection
#     G1  the probe query returned rc 0 AND the row count parses as ^[0-9]+$   -> unreadable
#     G2  the row count is >= 1                                                -> silent
#     G3  the chosen row IS the newest, and its age is within --max-row-age     -> stale_row
#     G4  probe_schema == "3", EXACT equality (not >=)                         -> stale_schema
#   Identity  (inngest-bootstrap.sh is the SHARED renderer for both hosts)
#     G5  envelope host      == soleur-inngest                                 -> wrong_host
#     G6  envelope host_name == soleur-inngest-prd                             -> wrong_host
#     G7  message host_role  == dedicated                                      -> wrong_host
#   Not serving
#     G8  server_active == inactive                                            -> host_serving
#     G9  http_code parses as ^[0-9]+$ AND != 200                              -> host_serving
#     G10 zero function.finished rows attributable to this host                -> host_executing
#   Store empty
#     G11 redis_active == active                                               -> redis_down
#     G12 redis_keys parses as ^[0-9]+$                                        -> unreadable
#     G13 redis_keys == 0                                                      -> store_populated
#     G14 data_mount_src == the pinned device                                  -> mount_mismatch
#     G15 data_bytes parses as ^[0-9]+$  (READABILITY ONLY — no ceiling)       -> unreadable
#   Read proof
#     G16 flush_latched ∈ {true,false}   (READABILITY ONLY)                    -> unreadable
#   Dispatch-time live re-reads (NOT from the row)
#     G17 the live Hetzner volume (BY NAME) id == the operator's pin           -> id_pin_mismatch
#     G18 scripts/followthroughs/inngest-host-not-serving-7674.sh reads PASS   -> followthrough_7674
#     G19 INNGEST_CUTOVER_FLIP (synchronous) ∈ {rolled-back, aborted}          -> flag_unsafe
#     G20 INNGEST_DIAGNOSTIC_BOOT (synchronous) is unset or 0                  -> diagnostic_boot
#
# ⚠️ G12 AND G13 ARE SEPARATE PREDICATES AND SEPARATE CASES, AND MERGING THEM REOPENS THE PLAN'S
# OWN MUTATION ROW 12. `[[ "__UNREADABLE__" -eq 0 ]]` is TRUE under bash arithmetic coercion — a
# non-numeric operand evaluates to 0 — so a single merged `redis_keys == 0` check treats "the
# emitter could not read the keyspace" as "the keyspace is empty", which is the exact fail-open the
# `__UNREADABLE__` sentinel exists to prevent. G12 establishes the operand is a number BEFORE G13
# compares it.
#
# ⚠️ G1 IS EVALUATED BEFORE G2, AND THE ORDER IS LOAD-BEARING FOR THE DIAGNOSIS, NOT THE VERDICT.
# A 503 from the read path yields zero rows. Evaluating G2 first would refuse — correctly — with
# `silent`, telling the operator the host emits nothing when in fact the operator's own read path
# is down. Both orders are safe; only one is honest.
#
# ⚠️ ONE READING ONLY, AND IT IS `redis_keys`. That field is summed by the emitter from
# `INFO keyspace` across EVERY database. The single-database size command reads db-0 only, while
# `FLUSHALL` spans every db — so a store holding keys in db-1 reports zero under it, which is a
# false `dark` authorizing a destroy. A historical probe field carried exactly that asymmetry and
# sits one field name away from this one. This gate reads NEITHER the single-db command nor that
# field, and AC B13 pins the absence of both by name against this file — which is why neither
# literal appears anywhere above: a body-grep sees comments too, so a file that documents the
# forbidden token cannot also assert it is absent. tests/scripts/test-inngest-host-dark-gate.sh
# names them explicitly and greps for them here.
#
# Usage:
#   source tests/scripts/lib/inngest-host-dark-gate.sh
#   inngest_host_dark_gate \
#     --rows-file <probe rows: betterstack-query.sh JSONEachRow output> \
#     --query-rc <n> \
#     --finished-file <function.finished rows, same shape> \
#     --finished-rc <n> \
#     --expected-volume-id <id> \
#     --live-attachment-id <id> \
#     --followthrough-rc <n> \
#     --cutover-flag <value> \
#     --diagnostic-boot <value>
#   # echoes exactly one verdict token; rc 0 ONLY for `dark`.

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
_IHDG_SELECT='
        | . as $outer
        | ((.raw? // empty) | fromjson?) as $d
        | select(($d | type) == "object")
        | select($d.host == $h and $d.host_name == $hn)
        | select((($d.message? // "") | test("^SOLEUR_INNGEST_SERVER_PROBE ")))'

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
  jq -Rn --arg h "$host" --arg hn "$host_name" '
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
  jq -Rn --arg h "$host" --arg hn "$host_name" '
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
  jq -Rn --arg h "$host" --arg hn "$host_name" '
      [ inputs
        | fromjson?
        | select(type == "object")
        | ((.raw? // empty) | fromjson?) as $d
        | select(($d | type) == "object")
        | select($d.host == $h and $d.host_name == $hn)
        | select((($d.message? // "") | test("^SOLEUR_INNGEST_SERVER_PROBE ")))
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
  out="$(jq -Rn --arg h "$host" --arg hn "$host_name" '
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

# _ihdg_finished_count <rows-file> <host> <host_name>
#
# Count function.finished rows ATTRIBUTABLE to the dedicated host. The identity test is an OR
# rather than the probe rows' AND, and the asymmetry is deliberate: for the probe we are granting
# authority to a row and must be certain it is the right host, so we require both fields; here we
# are looking for a REASON TO REFUSE, so any single hint that this host executed a function is
# enough. Requiring the conjunction would let a row with one spoofed field slip past.
_ihdg_finished_count() {
  local rows_file="$1" host="$2" host_name="$3"
  jq -Rn --arg h "$host" --arg hn "$host_name" '
      [ inputs
        | fromjson?
        | select(type == "object")
        | ((.raw? // empty) | fromjson?) as $d
        | select(($d | type) == "object")
        | select((($d.message? // "") | contains("function.finished")))
        | select(
            $d.host == $h
            or $d.host_name == $hn
            or (($d.message? // "") | contains("host_name=" + $hn))
            or (($d.message? // "") | contains("host_name=" + $h))
          )
      ] | length
    ' < "$rows_file" 2>/dev/null
}

# _ihdg_finished_lines <rows-file>
#
# G10's POSITIVE CONTROL. Counts rows that DECODE — regardless of host — so "zero rows attributable
# to this host" can be distinguished from "the parser understood nothing in this file". It
# deliberately does NOT filter on the `function.finished` marker: a window in which this fleet ran
# no functions at all is legitimate, and what must be proved is that the read and the decode
# worked, not that any particular event occurred.
_ihdg_finished_lines() {
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

# _ihdg_verdict <token> — echo the token, rc 0 only for the literal `dark`.
_ihdg_verdict() {
  printf '%s\n' "$1"
  [[ "$1" == "dark" ]]
}

inngest_host_dark_gate() {
  local rows_file="" query_rc="" finished_file="" finished_rc=""
  local expected_volume_id="" live_attachment_id="" followthrough_rc=""
  local cutover_flag="" diagnostic_boot=""
  local host="soleur-inngest" host_name="soleur-inngest-prd" expected_schema="3"
  # G3's recency bound. `now_epoch` is injectable so the suite can pin a clock; the default is the
  # real one. 5400s = 90 minutes, the window the monotonicity argument in this file's header
  # assumes — it was, until this revision, assumed and enforced nowhere.
  local now_epoch="" max_row_age="5400"

  while [[ $# -gt 0 ]]; do
    # A trailing flag with no value made `shift 2` a no-op (it returns non-zero and shifts
    # nothing), so the loop spun until the job timeout — and because the workflow calls the gate
    # under `if !`, the inherited `-e` is suppressed and nothing aborted. A hang is not a verdict.
    if [[ "$1" == --* && $# -lt 2 ]]; then _ihdg_verdict "unreadable"; return $?; fi
    case "$1" in
      --rows-file)           rows_file="${2-}";           shift 2 ;;
      --query-rc)            query_rc="${2-}";            shift 2 ;;
      --finished-file)       finished_file="${2-}";       shift 2 ;;
      --finished-rc)         finished_rc="${2-}";         shift 2 ;;
      --expected-volume-id)  expected_volume_id="${2-}";  shift 2 ;;
      --live-attachment-id)  live_attachment_id="${2-}";  shift 2 ;;
      --followthrough-rc)    followthrough_rc="${2-}";    shift 2 ;;
      --cutover-flag)        cutover_flag="${2-}";        shift 2 ;;
      --diagnostic-boot)     diagnostic_boot="${2-}";     shift 2 ;;
      --host)                host="${2-}";                shift 2 ;;
      --host-name)           host_name="${2-}";           shift 2 ;;
      --expected-schema)     expected_schema="${2-}";     shift 2 ;;
      --now-epoch)           now_epoch="${2-}";           shift 2 ;;
      --max-row-age)         max_row_age="${2-}";         shift 2 ;;
      *) echo "inngest_host_dark_gate: unknown argument '$1'" >&2; _ihdg_verdict "unreadable"; return $? ;;
    esac
  done

  # ── G1 — the read path answered, and its result is countable ────────────────────
  # EVALUATED FIRST, BEFORE G2. A 503 from the ClickHouse read path yields zero rows; refusing with
  # `silent` there would be a true refusal and a false diagnosis. Measured 2026-09-03: the read
  # path returned HTTP 503 {"exception":"This source is currently under maintenance."} for the whole
  # session, and scripts/followthroughs/inngest-host-not-serving-7674.sh correctly returned
  # TRANSIENT reason=query_failed rather than converting a broken read into a host verdict. That is
  # the measured justification for this gate's `unreadable`-aborts posture — a gate that cannot see
  # the host must never conclude the host is dark.
  [[ "$query_rc" =~ ^[0-9]+$ ]] || { _ihdg_verdict "unreadable"; return $?; }
  [[ "$query_rc" -eq 0 ]]       || { _ihdg_verdict "unreadable"; return $?; }
  [[ -n "$rows_file" && -f "$rows_file" ]] || { _ihdg_verdict "unreadable"; return $?; }

  local rows_tsv rows_count
  rows_tsv="$(_ihdg_rows "$rows_file" "$host" "$host_name")" || { _ihdg_verdict "unreadable"; return $?; }
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
  [[ "$rows_rowcount" =~ ^[0-9]+$ ]] || { _ihdg_verdict "unreadable"; return $?; }
  [[ "$rows_rowcount" == "$rows_count" ]] || { _ihdg_verdict "unreadable"; return $?; }
  [[ "$rows_count" =~ ^[0-9]+$ ]] || { _ihdg_verdict "unreadable"; return $?; }

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
  local wrong_host_rows
  wrong_host_rows="$(jq -Rn --arg h "$host" --arg hn "$host_name" '
      [ inputs | fromjson? | select(type == "object")
        | ((.raw? // empty) | fromjson?) as $d
        | select(($d | type) == "object")
        | select((($d.message? // "") | test("^SOLEUR_INNGEST_SERVER_PROBE ")))
        | select(($d.host != $h) or ($d.host_name != $hn))
      ] | length' < "$rows_file" 2>/dev/null)"
  [[ "$wrong_host_rows" =~ ^[0-9]+$ ]] || { _ihdg_verdict "unreadable"; return $?; }

  # ── G2 — the host is not silent ─────────────────────────────────────────────────
  # SILENCE IS NOT EVIDENCE OF DARKNESS. A host emitting nothing is a host whose state is UNKNOWN,
  # and this is the exact fail-open class the G3.7 pre-filter was found to carry.
  if [[ "$rows_count" -lt 1 ]]; then
    if [[ "$wrong_host_rows" -gt 0 ]]; then _ihdg_verdict "wrong_host"; return $?; fi
    _ihdg_verdict "silent"; return $?
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
  [[ -n "$newest_msg" ]] || { _ihdg_verdict "unreadable"; return $?; }

  # ── A TIE ON `dt` IS NOT A WINNER ───────────────────────────────────────────
  # `sort_by` is STABLE, so when two rows share the newest `dt` the one that survives is decided by
  # whatever order the query happened to emit them in — and the two can disagree. Constructed:
  # the same pair of rows, one dark and one reading `server_active=active redis_keys=9999`, gave
  # `dark` in one file order and `host_serving` in the other. Low reachability (`dt` carries
  # sub-second precision) but a verdict that depends on the caller's row order is not a
  # measurement. Tied-and-identical is fine; tied-and-disagreeing is a refusal.
  if [[ "$(_ihdg_tied_newest "$rows_file" "$host" "$host_name")" != "1" ]]; then
    _ihdg_verdict "unreadable"; return $?
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
    _ihdg_verdict "unreadable"; return $?
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
  # than about some point in a query window the caller chose. Both the boot_id PRESENCE checks are
  # kept — an unparseable or absent boot_id still means the row shape is not what this gate grades.
  local chosen_boot
  chosen_boot="$(_ihdg_field "$chosen_msg" boot_id)" || { _ihdg_verdict "unreadable"; return $?; }
  [[ -n "$chosen_boot" ]]                            || { _ihdg_verdict "unreadable"; return $?; }

  [[ "$max_row_age" =~ ^[0-9]{1,9}$ ]] || { _ihdg_verdict "unreadable"; return $?; }
  if [[ -z "$now_epoch" ]]; then now_epoch="$(date -u +%s 2>/dev/null)"; fi
  [[ "$now_epoch" =~ ^[0-9]{1,12}$ ]]  || { _ihdg_verdict "unreadable"; return $?; }

  local newest_dt newest_epoch row_age
  newest_dt="$(_ihdg_newest_dt "$rows_file" "$host" "$host_name")"
  [[ -n "$newest_dt" ]] || { _ihdg_verdict "unreadable"; return $?; }
  # Better Stack renders `dt` as UTC `YYYY-MM-DD HH:MM:SS[.ffffff]`. Anything else is a shape this
  # gate has not been taught to read, and `date` would happily coerce several of them.
  [[ "$newest_dt" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}[[:space:]][0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?$ ]] \
    || { _ihdg_verdict "unreadable"; return $?; }
  newest_epoch="$(date -u -d "${newest_dt} UTC" +%s 2>/dev/null)" \
    || { _ihdg_verdict "unreadable"; return $?; }
  [[ "$newest_epoch" =~ ^[0-9]{1,12}$ ]] || { _ihdg_verdict "unreadable"; return $?; }

  row_age=$(( now_epoch - newest_epoch ))
  # A row from the FUTURE is not fresh, it is a clock or an ingestion problem — and it is the one
  # sign shape that would sail through a `-le` bound on a signed difference.
  [[ "$row_age" -ge 0 ]]              || { _ihdg_verdict "stale_row"; return $?; }
  [[ "$row_age" -le "$max_row_age" ]] || { _ihdg_verdict "stale_row"; return $?; }
  # HOW REACHABLE IS THIS, HONESTLY. The workflow queries `--since 90m` and this bound defaults to
  # 5400s, so under the CURRENT wiring almost no row that arrives here can exceed it — a row older
  # than the window is not returned at all, and the gate answers `silent` instead. Said plainly
  # rather than left for a reader to assume this predicate is carrying independent weight, which is
  # the mistake the boot_id version of G3 got away with for a whole merge.
  #
  # It is kept, and it is not decorative, for four reasons: the bound belongs to the GATE rather
  # than to one caller (the same posture as sorting rows here instead of trusting the query);
  # clock skew between the log service and the runner can push a returned row past the bound;
  # the FUTURE arm above is reachable regardless of any window; and `--since` is a workflow literal
  # that a later edit can widen — which is why Row 7 of the suite pins it at 90m on BOTH queries
  # and counts them, so widening the window and leaving this bound behind reddens rather than
  # silently making the emptiness claim older than the argument that justifies it.

  # ── G4 — probe_schema is EXACTLY 3 ──────────────────────────────────────────────
  # EXACT EQUALITY, NOT `>=`. A `>=` comparison would silently accept a FUTURE schema whose field
  # semantics this gate has never seen — the same "a lenient extractor makes absence satisfy
  # everything" shape one version forward. A schema bump must force a deliberate edit here.
  #
  # `stale_schema` is the EXPECTED verdict for every dispatch until the host is replaced: the
  # running host's boot_id has been unchanged for weeks, so it emits no probe_schema at all. That is
  # intended and is the mechanical interlock making Phase 2 -> Phase 3 an ordering CONSTRAINT rather
  # than operator discipline — before the new emitter is live the recut is unreachable by
  # construction. It stays its own token precisely because it is actionable ("replace the host
  # first") where `unreadable` is not.
  local schema
  schema="$(_ihdg_field "$chosen_msg" probe_schema)" || { _ihdg_verdict "stale_schema"; return $?; }
  [[ "$schema" == "$expected_schema" ]]              || { _ihdg_verdict "stale_schema"; return $?; }

  # ── G7 — the row says it is the dedicated host ──────────────────────────────────
  # host_role is derived on-host from DOPPLER_PROJECT (§D1), this codebase's canonical
  # dedicated-vs-web discriminator. The earlier attempt gated on "is /mnt/data a mountpoint", which
  # is TRUE on the co-located web host too — cloud-init.yml mounts the workspaces volume there — so
  # a web-host row could have carried a store measurement into this gate's clearance condition. An
  # emitted positive identity is what replaced an inferred one.
  local host_role
  host_role="$(_ihdg_field "$chosen_msg" host_role)" || { _ihdg_verdict "wrong_host"; return $?; }
  [[ "$host_role" == "dedicated" ]]                  || { _ihdg_verdict "wrong_host"; return $?; }

  # ── G8 — systemd says the server unit is not running ────────────────────────────
  local server_active
  server_active="$(_ihdg_field "$chosen_msg" server_active)" || { _ihdg_verdict "unreadable"; return $?; }
  # A present-but-EMPTY value is a readability failure, not a claim about the unit. The emitter
  # defaults this to `unknown` rather than blank, so a blank here means the row shape changed —
  # which is a reason to stop, not a reason to say the host is serving.
  [[ -n "$server_active" ]]                                 || { _ihdg_verdict "unreadable"; return $?; }
  [[ "$server_active" == "inactive" ]]                      || { _ihdg_verdict "host_serving"; return $?; }

  # ── G9 — and the loopback agrees ────────────────────────────────────────────────
  # `server_active` alone is a systemd CLAIM; `http_code` is the claim that matters. This host has
  # already been observed reporting a started unit that had failed to bind its port, so the two
  # signals must agree. An ABSENT http_code must not read as "non-200" — hence the presence check
  # and the ^[0-9]+$ predicate before the comparison.
  local http_code
  http_code="$(_ihdg_field "$chosen_msg" http_code)" || { _ihdg_verdict "unreadable"; return $?; }
  [[ "$http_code" =~ ^[0-9]+$ ]]                     || { _ihdg_verdict "unreadable"; return $?; }
  [[ "$http_code" != "200" ]]                        || { _ihdg_verdict "host_serving"; return $?; }

  # ── G10 — and nothing executed a function on it ─────────────────────────────────
  # Independent of what the probe says: a host can be executing functions while its own liveness
  # marker reports whatever it reports. An unreadable function.finished query is `unreadable`, never
  # "zero rows, therefore none".
  [[ "$finished_rc" =~ ^[0-9]+$ ]] || { _ihdg_verdict "unreadable"; return $?; }
  [[ "$finished_rc" -eq 0 ]]       || { _ihdg_verdict "unreadable"; return $?; }
  [[ -n "$finished_file" && -f "$finished_file" ]] || { _ihdg_verdict "unreadable"; return $?; }
  # A POSITIVE CONTROL, because zero is G10's CLEARING value and every way the query can be wrong
  # also produces zero. G1/G2 give the probe query one (`rows_count >= 1`, else `silent`); this
  # query had none, so an undecodable envelope, a mis-targeted query, or a `function.finished`
  # channel that never reaches this Logs source all read as "no functions ran". Note the polarity
  # difference that made it dangerous: in `_ihdg_rows` a dropped row pushes toward `silent`, a
  # refusal; here a dropped row pushes toward `dark`.
  # THE CONTROL COMPARES BYTES TO DECODES, NOT DECODES TO ZERO. An earlier revision required
  # `finished_total >= 1` — at least one decodable row — and that was self-defeating: the CALLER
  # queries `--grep 'function.finished'` (apply-web-platform-infra.yml), so the file handed to us
  # is ALREADY marker-filtered. "No rows" therefore means "this fleet ran no functions in the
  # window", which is the NORMAL state whenever a recut is attempted — so the gate refused
  # `unreadable` on its own precondition and could never pass. The control's comment claimed it
  # "deliberately does NOT filter on the marker": true of the control, false of its INPUT, which
  # is the half that decides what it can see.
  #
  # The failure it exists to catch is an UNDECODABLE envelope — bytes arrived and the parser
  # understood none of them. That is exactly `raw_lines > 0 && decoded == 0`, and it is
  # distinguishable from a legitimately empty window without requiring the fleet to be busy.
  local finished_raw finished_total finished_count
  finished_raw="$(grep -c . "$finished_file" 2>/dev/null || true)"
  [[ "$finished_raw" =~ ^[0-9]+$ ]]   || { _ihdg_verdict "unreadable"; return $?; }
  finished_total="$(_ihdg_finished_lines "$finished_file")"
  [[ "$finished_total" =~ ^[0-9]+$ ]] || { _ihdg_verdict "unreadable"; return $?; }
  finished_count="$(_ihdg_finished_count "$finished_file" "$host" "$host_name")"
  [[ "$finished_count" =~ ^[0-9]+$ ]] || { _ihdg_verdict "unreadable"; return $?; }
  if [[ "$finished_raw" -ge 1 && "$finished_total" -eq 0 ]]; then
    _ihdg_verdict "unreadable"; return $?
  fi
  [[ "$finished_count" -eq 0 ]]       || { _ihdg_verdict "host_executing"; return $?; }

  # ── G11 — Redis is UP, so its keyspace answer means something ───────────────────
  # Without this the gate authorizes destruction on an ambiguity: a host where Redis failed to start
  # emits a redis_keys derived from a failed `INFO keyspace`, and "Redis is down" becomes
  # indistinguishable from "the store is empty". Same fail-open shape as reading silence as
  # darkness, applied to the field the whole decision rests on.
  local redis_active
  redis_active="$(_ihdg_field "$chosen_msg" redis_active)" || { _ihdg_verdict "unreadable"; return $?; }
  [[ "$redis_active" == "active" ]]                        || { _ihdg_verdict "redis_down"; return $?; }

  # ── G12 — the key count is a NUMBER ─────────────────────────────────────────────
  # SEPARATE FROM G13, AND THE SEPARATION IS THE WHOLE GUARD. `[[ "__UNREADABLE__" -eq 0 ]]` is TRUE
  # under bash arithmetic coercion, so a merged check reads the emitter's "I could not measure this"
  # sentinel as the clearing value. The emitter's own awk was found summing `keys=abc` to 0 for the
  # same reason and was corrected to match `keys=[0-9]+` and exit non-zero otherwise.
  local redis_keys
  redis_keys="$(_ihdg_field "$chosen_msg" redis_keys)" || { _ihdg_verdict "unreadable"; return $?; }
  # WIDTH-BOUNDED, not merely numeric. `[[ "18446744073709551616" -eq 0 ]]` is TRUE in bash — the
  # value wraps at 2^64 — so an unbounded ^[0-9]+$ lets a sufficiently large count reach G13 and
  # coerce to the clearing value. Twelve digits is far above any reachable keyspace and far below
  # the wrap.
  [[ "$redis_keys" =~ ^[0-9]{1,12}$ ]]                 || { _ihdg_verdict "unreadable"; return $?; }

  # ── G13 — and it is zero ────────────────────────────────────────────────────────
  # If redis_keys > 0 the destructive path is REFUSED OUTRIGHT, no exceptions — and note that
  # enumeration is then unavailable, because inngest-enumerate-reminders.sh queries 127.0.0.1:8288,
  # which is not bound on a dark host. Non-empty AND non-enumerable means ADR-142's preserve-and-copy
  # is the only lawful path and the dispatch must route there.
  [[ "$redis_keys" -eq 0 ]] || { _ihdg_verdict "store_populated"; return $?; }

  # ── G14 — the store we measured is ON THE DEVICE BEING DESTROYED ────────────────
  # THIS IS THE CONDITION THAT MAKES THE WHOLE GATE MEAN WHAT IT CLAIMS. `redis_keys` is a statement
  # about a Redis PROCESS; the recut destroys a BLOCK DEVICE. Today's mount is `mount … || true`
  # with `nofail`, so a failed mount leaves /mnt/data on the ephemeral root disk and Redis reports
  # an empty store WHILE THE VOLUME HOLDS A POPULATED AOF — every other condition satisfied,
  # destruction unsafe. The flip FSM already carries a `latch-unrecordable detail=not-a-mountpoint`
  # abort for precisely this shape, so the repo has been bitten by it before.
  #
  # Pinned to the physical device by id: pre-recut that is the by-id path of the volume the dispatch
  # named; post-recut it is the mapper. Both are accepted so the gate remains usable for a
  # re-dispatch after a partial apply.
  local data_mount_src expected_dev
  data_mount_src="$(_ihdg_field "$chosen_msg" data_mount_src)" || { _ihdg_verdict "unreadable"; return $?; }
  [[ "$expected_volume_id" =~ ^[0-9]+$ ]] || { _ihdg_verdict "id_pin_mismatch"; return $?; }
  expected_dev="/dev/disk/by-id/scsi-0HC_Volume_${expected_volume_id}"
  if [[ "$data_mount_src" != "$expected_dev" && "$data_mount_src" != "/dev/mapper/inngest-redis" ]]; then
    _ihdg_verdict "mount_mismatch"; return $?
  fi

  # ── G15 — data_bytes is READABLE (readability only, no ceiling) ─────────────────
  # An AUDIT field, not a threshold. An empty Redis on a volume holding megabytes is a state a human
  # should see before it is erased — but a size CEILING here would be a made-up number, and the
  # honest guard is that the figure was actually measured. `__UNREADABLE__` means the emitter could
  # not walk the mount, which means the only surviving record of what is about to be destroyed does
  # not exist.
  local data_bytes
  data_bytes="$(_ihdg_field "$chosen_msg" data_bytes)" || { _ihdg_verdict "unreadable"; return $?; }
  [[ "$data_bytes" =~ ^[0-9]+$ ]]                      || { _ihdg_verdict "unreadable"; return $?; }

  # ── G16 — flush_latched is READABLE (readability only) ──────────────────────────
  # Neither polarity blocks: a latched flush and an un-latched one are both legitimate states at
  # this point. What is NOT legitimate is `__UNREADABLE__`, which the emitter emits when it could
  # not read the latch directory — and `[ -f ]` cannot distinguish "no latch" from "cannot read", so
  # a gate accepting `false` without this check would accept a positive claim about a store that was
  # never read.
  local flush_latched
  flush_latched="$(_ihdg_field "$chosen_msg" flush_latched)" || { _ihdg_verdict "unreadable"; return $?; }
  case "$flush_latched" in
    true|false) : ;;
    *) _ihdg_verdict "unreadable"; return $? ;;
  esac

  # ── G17 — the LIVE volume is the one the operator pinned ────────────────────────
  # Guard 1's ID-PIN reads `.change.before.id` from a plan document. This one reads LIVE Hetzner
  # state at dispatch time. They can disagree — a plan is a projection of state, and state can be
  # wrong about the world — and it is the world that gets destroyed.
  #
  # WHAT THE CALLER ACTUALLY READS — and this comment has now overstated it in BOTH directions.
  # The workflow does `curl .../volumes?name=soleur-inngest-redis-store | jq -r '.volumes[0].id'`
  # and NOTHING ELSE: there is no `.server` read and no attachment assertion anywhere in the job.
  # A previous revision said it "reads the live ATTACHMENT" (too strong); the revision correcting
  # THAT then added "and asserts the volume is attached to the inngest server", which is equally
  # false. G17 proves exactly one thing: the volume carrying this NAME has the id the operator
  # pinned. The attachment property is carried by G14's `data_mount_src` — a fact about what the
  # host actually mounted — and the terraform ADDRESS question by Guard 1's `before.id`. Guard 1's before.id pin is the counter that answers the address
  # question; the two are complementary and neither subsumes the other.
  #
  # An unreadable live id lands here rather than on `unreadable`: the pin could not be confirmed,
  # and this token names the thing the operator must go check.
  [[ "$live_attachment_id" =~ ^[0-9]+$ ]]             || { _ihdg_verdict "id_pin_mismatch"; return $?; }
  [[ "$live_attachment_id" == "$expected_volume_id" ]] || { _ihdg_verdict "id_pin_mismatch"; return $?; }

  # ── G18 — #7674 reads PASS ──────────────────────────────────────────────────────
  # Without this the recut is strictly COUNTERPRODUCTIVE rather than merely premature: the first
  # `arm` after a recut would write a fresh latch, fail `verify_or_abort` against a host that cannot
  # serve, and land the FSM in terminal `aborted` — with the latch burned and the store gone.
  [[ "$followthrough_rc" =~ ^[0-9]+$ ]] || { _ihdg_verdict "followthrough_7674"; return $?; }
  [[ "$followthrough_rc" -eq 0 ]]       || { _ihdg_verdict "followthrough_7674"; return $?; }

  # ── G19 — the cutover flag, RE-READ SYNCHRONOUSLY ───────────────────────────────
  # NOT from the probe row. The row is a ≤90-minute-old snapshot; the flag is readable in real time
  # and is the thing that actually authorizes a concurrent FLUSHALL. This is also step (3) of the
  # monotonicity argument at the top of this file — without it, "the count cannot increase between
  # the row and the apply" is not established.
  case "$cutover_flag" in
    rolled-back|aborted) : ;;
    *) _ihdg_verdict "flag_unsafe"; return $? ;;
  esac

  # ── G20 — diagnostic boot is off ────────────────────────────────────────────────
  # ALSO a synchronous read: INNGEST_DIAGNOSTIC_BOOT is not an emitted probe field, and §D2 did not
  # catch that the plan's condition 11 had no input at all. If it is still set, the flip reaches
  # `done` against a SQLite-only non-durable scheduler — #7228's defect reproduced one layer over,
  # now with the latch burned.
  # THE EMPTY STRING IS NOT AN ACCEPTING VALUE, and it was. G20 was the only predicate in the gate
  # whose clearing value was `""`, which made it the only one that failed OPEN when its flag was
  # omitted from the call entirely — measured: dropping `--diagnostic-boot` returned `dark`. The
  # caller must now say what it measured, using the literal `unset` for a key it positively
  # established is absent. An empty value reaching here means the caller did not decide, and a
  # gate authorizing an irreversible destroy must not decide for it.
  case "$diagnostic_boot" in
    0|unset) : ;;
    *) _ihdg_verdict "diagnostic_boot"; return $? ;;
  esac

  _ihdg_verdict "dark"
}
