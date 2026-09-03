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
#   5. The only other writer, the flip FSM's `FLUSHALL`, sets the count to 0. Even if G19's
#      synchronous flag read were somehow raced, the raced write is the one write that cannot
#      make a zero reading stale.
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
#     G3  the chosen row's boot_id equals the NEWEST row's boot_id             -> stale_row
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
#     G17 the live Hetzner attachment volume id == the operator's pin          -> id_pin_mismatch
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
  local msg="$1" name="$2" tok
  local -a toks=()
  local IFS=' '
  read -ra toks <<< "$msg"
  for tok in "${toks[@]}"; do
    if [[ "$tok" == "${name}="* ]]; then
      printf '%s' "${tok#"${name}"=}"
      return 0
    fi
  done
  return 1
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
        | . as $outer
        | ((.raw? // empty) | fromjson?) as $d
        | select(($d | type) == "object")
        | select($d.host == $h and $d.host_name == $hn)
        | select((($d.message? // "") | contains("SOLEUR_INNGEST_SERVER_PROBE")))
        | [ ($outer.dt // ""), ($d.message // "") ]
      ]
      | sort_by(.[0])
      | .[]
      | .[1]
    ' -r < "$rows_file" 2>/dev/null
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

  while [[ $# -gt 0 ]]; do
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
        | select((($d.message? // "") | contains("SOLEUR_INNGEST_SERVER_PROBE")))
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

  # ── G3 — the chosen row is from the CURRENT boot ────────────────────────────────
  # Without this, "dark" can be a fact about a host that no longer exists: a replaced host whose new
  # boot has not yet emitted a schema-3 row leaves the newest schema-3 row sitting on the PREVIOUS
  # boot_id, and every field on it describes a machine that is gone. Both boot_ids must be PRESENT —
  # an absent boot_id compared against an absent boot_id is trivially equal.
  local chosen_boot newest_boot
  chosen_boot="$(_ihdg_field "$chosen_msg" boot_id)" || { _ihdg_verdict "unreadable"; return $?; }
  newest_boot="$(_ihdg_field "$newest_msg" boot_id)" || { _ihdg_verdict "unreadable"; return $?; }
  [[ -n "$chosen_boot" && -n "$newest_boot" ]]       || { _ihdg_verdict "unreadable"; return $?; }
  [[ "$chosen_boot" == "$newest_boot" ]]             || { _ihdg_verdict "stale_row"; return $?; }

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
  local finished_count
  finished_count="$(_ihdg_finished_count "$finished_file" "$host" "$host_name")"
  [[ "$finished_count" =~ ^[0-9]+$ ]] || { _ihdg_verdict "unreadable"; return $?; }
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
  [[ "$redis_keys" =~ ^[0-9]+$ ]]                      || { _ihdg_verdict "unreadable"; return $?; }

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

  # ── G17 — the LIVE attachment is the volume the operator pinned ─────────────────
  # Guard 1's ID-PIN reads `.change.before.id` from a plan document. This one reads the LIVE Hetzner
  # attachment at dispatch time. They can disagree — a plan is a projection of state, and state can
  # be wrong about the world — and it is the world that gets destroyed. An unreadable live id lands
  # here too rather than on `unreadable`: the pin could not be confirmed, and this token names the
  # thing the operator must go check.
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
  case "$diagnostic_boot" in
    ''|0) : ;;
    *) _ihdg_verdict "diagnostic_boot"; return $? ;;
  esac

  _ihdg_verdict "dark"
}
