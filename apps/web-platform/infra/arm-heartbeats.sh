#!/usr/bin/env bash
# Measured-beat ARM gate for the web-host probe heartbeats (#6438/#6548, ADR-117 automated),
# plus the `--sweep` backstop that re-pauses whatever an externally-imposed cut left live.
#
# EXTRACTED FROM `.github/workflows/apply-web-platform-infra.yml` (#7587). It used to be ~130
# lines of bash inside a YAML scalar, which nothing asserted on: `git grep arm_one` across the
# test trees returned only comments. A guard written against bash-inside-YAML can only check
# that a clock read APPEARS in the step — which a decoy `date +%s` satisfies and an equivalent
# rewrite false-REDs. As a real script it is driven behaviourally by `arm-heartbeats.test.sh`
# with a fake clock and a fake `curl` on PATH, the house shape used by
# `web-private-nic-guard.sh` + `.test.sh` and the other pairs in this directory.
#
# THE SWEEP LIVES HERE TOO (#7659). It shipped as ~45 further lines inside the sibling step's
# YAML scalar — the same shape this file's own rationale condemns, asserted the same way, with
# its own second implementation of "PATCH a heartbeat's paused flag" and its own second copy of
# the API base literal. `--sweep` is that step's body, so there is ONE `hb_patch_paused`, ONE
# `BS_API_BASE`, and the loop, the arithmetic, the summary line and the fail-not-annotate branch
# are all executed by `arm-heartbeats.test.sh` instead of string-matched.
#
# THE SEQUENCE (ADR-117's, VERIFIED against the live Better Stack API). A paused heartbeat
# exposes NO usable ping timestamp — `attributes` is {status, paused, period, grace,
# updated_at, url, …} with NO last_ping_at, and `updated_at` does not move when a beat arrives
# while paused. So the only way to MEASURE a real beat is to UNPAUSE and watch `status`
# transition to `up`, rolling back BEFORE the first absence alert if it never does. Per monitor:
#   1. resolve the monitor id from TFSTATE (never a name-regex — a name collision would arm the
#      wrong monitor). The named-monitor modes (#9980, below) are the one exception: they resolve by
#      EXACT name over the API list, require exactly one match, and take the owner's --id as the
#      independent anchor;
#   2. OP/STATE-GATE on live `status=="paused"`: a monitor already `up`/`pending`/`down`
#      (ignore_changes=[paused] keeps SOURCE paused=true forever, but a prior arm unpaused it
#      LIVE) is skipped, so routine re-applies are a TRUE no-op and never flake on a BS blip;
#   3. PATCH {paused:false}, then poll `status` until `up` within the deadline;
#   4. `up` ⇒ a real beat landed ⇒ ARMED. Otherwise PATCH {paused:true} IMMEDIATELY (roll back
#      BEFORE the first absence alert would fire) — never leave an unfed monitor live, never
#      leave a green-but-inert one paused-and-forgotten.
#
# THE DEADLINE IS WALL CLOCK, NOT A SLEEP TALLY (#7587, and the #5795 defect class). The poll
# loop used to advance its counter by `sleep 10` alone, with the per-iteration
# `curl --max-time 15` uncounted — so a nominal `deadline` could consume up to
# `deadline + (deadline/10) × 15 = deadline × 2.5` of real wall clock. Better Stack answers in
# ~0.2 s today (measured: 235 s elapsed against a 230 s nominal deadline on run 32360734255),
# so the exposure is to vendor latency rather than to normal operation — but a budget that
# counts only its own sleeps is out-raced by its own round-trips, which is exactly what a
# step-level `timeout-minutes` cannot compensate for. `elapsed` is now re-read from the clock
# after every round-trip.
#
# THE BOUND THAT FOLLOWS IS A LOOP BOUND, AND IT IS NOT THE FUNCTION'S BOUND (#7657 D1/D2).
# Re-reading the clock bounds the POLL LOOP at `deadline + one iteration`. `arm_one` itself
# spends four further round-trips that the `elapsed` accounting never sees — the pre-loop GET,
# the pre-loop unpause PATCH, the final iteration's own GET (the part that overshoots), and the
# terminal rollback PATCH. Each is capped by `--max-time ARM_CURL_MAX_TIME_S`, so per call site:
#
#   worst-case wall clock  =  deadline + ARM_POLL_INTERVAL_S
#                             + (3 + ARM_ROLLBACK_ATTEMPTS) × ARM_CURL_MAX_TIME_S
#                          =  deadline + 85 s  at the shipped 10 / 15 / 2
#
# ADDITIVE, not a multiplier: the overhead is per CALL SITE, so it scales with the number of
# arms and not with the size of the deadlines. `Σ(deadlines) × 1.1` was the wrong shape — it
# happened to be generous for six large deadlines and would under-budget a seventh small one.
# The step ceiling in the workflow is sized against `Σ(deadline_i + 85)`; the whole ladder is
# derived, not restated, by the `ARM gate's deadlines fit its job` describe in
# `plugins/soleur/test/terraform-target-parity.test.ts`.
#
# AND IT IS WHY THE ROLLBACK RESERVE IS 40 s, NOT 10 (#7657 D5). The deadline used to be
# `period + grace − 10`, reserving one poll interval for the rollback. The real gap between the
# unpause landing and the re-pause landing is `deadline + ARM_POLL_INTERVAL_S +
# 2 × ARM_CURL_MAX_TIME_S` — the final iteration's overshoot plus the rollback PATCH — so at as
# little as 2 s of Better Stack round-trip the old formula re-paused the monitor AFTER its first
# absence alert had already fired. A false page from the gate that exists to prevent false pages.
# The reserve is now the measured worst case: `deadline = period + grace − 40`. The rollback RETRY
# does not enter this term: it fires only when the first attempt failed, and a failed PATCH did not
# re-pause anything, so it lengthens the STEP's wall clock without lengthening the LIVE window.
#
# THE ROLLBACK IS ALSO RECORDED, NOT ONLY ATTEMPTED. Every id whose `PATCH {paused:false}`
# succeeded is appended to `$ARMED_UNCONFIRMED` and removed ONLY when it reaches `up` or when a
# rollback `PATCH {paused:true}` actually returns a 2xx. Removing on "rollback attempted" would
# drop a FAILED rollback's id, so `--sweep` — the last chance to re-pause it — would never retry
# the exact monitor the `::error::` is warning about.
# There is deliberately NO `trap` (Cut List C6): bash keeps only the last EXIT handler, an
# INT/TERM handler returns and then fires EXIT too (double-PATCH), and bash defers the handler
# until the foreground `sleep` returns. The state file plus the sibling sweep step is ONE
# mechanism with ONE entry point, and it survives a step-level cancellation, which a trap
# does not.
#
# WHAT THIS FILE DOES NOT DETECT (#7658 E9, recorded rather than fixed). `$ARMED_UNCONFIRMED`
# lives in `$RUNNER_TEMP` and dies with the runner. A monitor left unpaused by an EARLIER run
# whose runner died is read by the next run's op/state gate as `already armed (status=…)` and is
# never re-paused, and the nightly `heartbeat-live-reconcile` only flags fed-but-PAUSED monitors,
# never unpaused-and-unfed ones. The only detector for that state today is the page itself.
# Closing it means re-deriving the arm set from tfstate in the sweep rather than from a state
# file; tracked, not done here.
#
# ERREXIT. The caller is a GitHub `run:` step with no `shell:` key, so GitHub invokes it as
# `/usr/bin/bash -e {0}` (ADR-170) — but this file runs as its own process under its own
# shebang, so it owns its flags. `set +e` is declared EXPLICITLY anyway rather than merely
# omitted: the difference is invisible to a reader, and the whole point of the rollback path is
# that it must not abort at the first failing PATCH. For the same reason every PATCH result is
# read as DATA (`hb_patch_paused` returns a verdict, it never aborts), and no arithmetic is
# written as a bare `(( … ))` — that exits non-zero whenever the expression evaluates to 0.
#
# CONTRACT (env in, exit code out) — also printed by `--help`:
#   BS_TOKEN            (required for --arm, --status and --arm-one; may be EMPTY for --sweep, which
#                       then reports `outcome=mint-unreadable` and names the ids it could not re-pause)
#                       Better Stack API token, already ::add-mask::ed by the caller. --status needs
#                       read scope; --arm-one and --sweep need WRITE scope.
#   TFSTATE_JSON        (required for --arm) path to `terraform show -json` for this root.
#   ARMED_UNCONFIRMED   (required for --arm and --sweep; optional for --arm-one) path to the state file
#                       `--sweep` reads.
#   BS_API_BASE         (optional) Better Stack API root. PINNED: anything other than the production
#                       root https://uptime.betterstack.com/api/v2 is refused (rc=1) before any
#                       request, because the bearer is sent to this host. A test that needs another
#                       destination shims `curl` on PATH rather than redirecting this variable.
#   ARM_POLL_INTERVAL_S (optional) poll period in whole seconds, 1 to 999, default 10; lowered only by
#                       the test harness. Any other value refuses (rc=1) before a request.
#
# NAMED-MONITOR MODES (#9980) — the operator-invoked twins of --arm, for ONE monitor by name:
#   --status <name>                 read-only. Resolves <name> by EXACT name over the whole paginated
#                                   GET /heartbeats list and prints
#                                   `name= id= paused= status= period= grace=`. Needs only BS_TOKEN
#                                   (read scope is enough). Never issues a PATCH.
#   --arm-one <name> [--id <id>]    resolves the id the same way, requires EXACTLY ONE exact-name match
#                                   (and equality with --id when given: the pin is the owner's
#                                   independent anchor, read in a separate step), refuses when its fixed
#                                   150 s deadline exceeds the monitor's own period + grace - 40, then
#                                   runs the SAME arm_one the per-merge path uses: op/state gate,
#                                   unpause, poll status to `up`, rollback to paused (one retry), books.
#                                   Needs BS_TOKEN with WRITE scope. TFSTATE_JSON is not read.
#                                   ARMED_UNCONFIRMED is optional: unset, a private 0600 file is made
#                                   under ${TMPDIR:-/var/tmp}; set, the path must be writable (checked
#                                   BEFORE the first PATCH). Its path and the --sweep recovery command
#                                   are printed before the first PATCH, and a private file is removed
#                                   only when it is empty on exit. There is no trap (the file header,
#                                   Cut List C6, says why), so ANY interruption (Ctrl-C, a closed
#                                   terminal) leaves the monitor live: re-run with --sweep on the
#                                   printed path and the same WRITE-scope BS_TOKEN.
#                                   A run takes up to about 150 s of polling (235 s worst case) plus the
#                                   name resolution: give the caller a timeout of at least 300 s. This
#                                   script's own messages go to stdout. Once a run has reached the
#                                   named-monitor stage (an argument, destination or interval refusal
#                                   prints one `::error::` line and no verdict), the LAST line is a
#                                   machine verdict:
#                                   `::notice::arm-one-result name= id= outcome= rc=` (id=none unless
#                                   exactly one monitor matched) with outcome one of armed | already-up |
#                                   live-not-up | rolled-back | rollback-failed | unpause-recovered |
#                                   unpause-unknown | failed | refused.
#   Neither mode touches the per-merge arm list. <name> matches ^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$,
#   <id> matches ^[0-9]+$ (an empty --id refuses), and anything else refuses with rc 1 before a request.
#   `--status` fields are whitelisted: period and grace print as digits (at most 9), `null` (absent) or
#   INVALID.
#
# EXIT CODES.
#   --arm (default)
#     0 = every arm either ARMED, was a NO-OP (already live), was ABSENT from tfstate, or — for
#         the one soft call site, inngest-consumer — measured no beat and was rolled back to
#         paused, which is an assertion about the FEEDER and not about the arming.
#     1 = at least one arm could not do its job (GET failed, unpause failed, rollback failed, or
#         the status could not be read at all during the poll), OR the pre-arm contract/tfstate
#         checks refused to start.
#   --sweep
#     0 = nothing was on the books, or every id on them is now confirmed re-paused.
#     1 = at least one monitor is STILL unpaused-and-unfed (a non-2xx re-PATCH, or the token
#         could not be minted at all).
#   --status
#     0 = exactly one monitor carries that exact name. 1 = zero, several, or the list could not be read.
#   --arm-one
#     0 = armed (a real beat landed in THIS run) or the monitor was already `up` (nothing changed).
#     1 = refused or failed: a collision, an id pin mismatch, a ceiling breach, an unreadable list or
#         monitor, a monitor that is live but NOT `up` (`down`, `pending`: not armed by this run), a
#         FAILED rollback, or an unpause whose outcome is unknown (the id stays on the books file and
#         the recovery command is repeated). Read `--status` after any rc 1.
#     2 = the gate worked and the feeder did not feed: the monitor was rolled back to paused and the
#         soak is NOT satisfied.
#   78 = refused to run under xtrace (every mode).
#
# `--sweep` OUTCOME VOCABULARY (the `outcome=` tag in its annotation and run-summary line):
#   noop             the state file was absent or empty — nothing was ever unpaused.
#   repaused         every id on the books returned a 2xx to `PATCH {"paused":true}`.
#   partial          at least one id did not; those monitors are live with nothing feeding them.
#   mint-unreadable  BS_TOKEN was empty, so no id could even be attempted.

set -uo pipefail
set +e   # explicit, not inherited — see ERREXIT above.
# Refuse to run under xtrace: -x prints a variable's value the moment it is bound (see #7797),
# and this script holds a live API token. Placed before the credential is read.
case "$-" in
  *x*) printf '[FATAL] refusing to run under xtrace: this script handles a live credential and -x would print it (see #7797)\n' >&2; exit 78 ;;
esac

BS_TOKEN="${BS_TOKEN:-}"
TFSTATE_JSON="${TFSTATE_JSON:-}"
ARMED_UNCONFIRMED="${ARMED_UNCONFIRMED:-}"
BS_API_BASE="${BS_API_BASE:-https://uptime.betterstack.com/api/v2}"
ARM_POLL_INTERVAL_S="${ARM_POLL_INTERVAL_S:-10}"
# The per-round-trip ceiling. Read by the ladder guard as well as by `curl`: it is one of the
# two terms in the per-call-site overhead above, so it may not be spelled inline.
ARM_CURL_MAX_TIME_S=15
# --arm-one's fixed poll budget (#9980). The monitor's feeder beats every 60 s, so 150 s is two and a half
# beats; the ceiling check below refuses a monitor whose own first absence alert would land sooner.
ARM_ONE_DEADLINE=150
# A vendor that ignores per_page still ends: the resolver makes at most this many list requests.
ARM_LIST_MAX_PAGES=20

usage() {
  sed -n '/^# CONTRACT (env in/,/^#   mint-unreadable/p' "$0" | sed 's/^# \{0,1\}//'
  echo
  echo "usage: arm-heartbeats.sh [--arm | --sweep | --status <name> | --arm-one <name> [--id <id>] | --help]"
}

MODE=arm
NAME=""
PIN_ID=""
HAVE_ID=0
argerr() { echo "::error::arm-heartbeats.sh: $1"; exit 1; }
case "${1:-}" in
  ""|--arm) MODE=arm ;;
  --sweep)  MODE=sweep ;;
  --status)
    MODE=status
    [[ "${2:-}" == -h || "${2:-}" == --help ]] && { usage; exit 0; }
    [[ $# -eq 2 ]] || argerr "--status takes exactly one <name> (usage: --status <name>)."
    NAME="${2:-}" ;;
  --arm-one)
    MODE=armone
    [[ "${2:-}" == -h || "${2:-}" == --help ]] && { usage; exit 0; }
    if [[ $# -eq 2 ]]; then NAME="${2:-}"
    elif [[ $# -eq 4 && "${3:-}" == "--id" ]]; then NAME="${2:-}"; PIN_ID="${4:-}"; HAVE_ID=1
    else argerr "--arm-one takes <name> and an optional --id <id> (usage: --arm-one <name> [--id <id>])."; fi ;;
  -h|--help) usage; exit 0 ;;
  *) echo "::error::arm-heartbeats.sh: unknown argument '$1' (expected --arm, --sweep, --status, --arm-one or --help)."; exit 1 ;;
esac
if [[ "$MODE" == status || "$MODE" == armone ]]; then
  # The leading alphanumeric is deliberate: a forgotten name must not let `--id` be read as the name.
  # C locale: in a UTF-8 locale U+202E and U+200B count as printable (same reason as show(), defined further down).
  _shown="$(LC_ALL=C; _t="${NAME:0:40}"; printf '%s' "${_t//[^[:print:]]/?}")"
  [[ "$NAME" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$ ]] || argerr "the monitor name must match ^[A-Za-z0-9][A-Za-z0-9._-]{0,127}\$ (got '${_shown}')."
  # HAVE_ID, not -n: `--id ""` (an empty shell variable) must refuse rather than silently drop the pin.
  [[ "$HAVE_ID" -eq 0 || "$PIN_ID" =~ ^[0-9]+$ ]] || argerr "--id must be a numeric Better Stack heartbeat id."
fi

# Destination pin: the bearer is sent to this host, so an env override must not redirect it.
# Placed after argument parsing so `--help` still works, and before any request in either mode.
case "$BS_API_BASE" in
  https://uptime.betterstack.com/api/v2) ;;
  *) echo "::error::arm-heartbeats.sh: BS_API_BASE must be https://uptime.betterstack.com/api/v2 — refusing to send the Better Stack token anywhere else."; exit 1 ;;
esac
# The poll interval reaches `sleep` AND, since #9980, a `$(( ))` ceiling computation in --arm-one: an
# unvalidated value is arithmetic evaluation (command substitution) and a negative one loosens the ceiling.
[[ "$MODE" == sweep || "$ARM_POLL_INTERVAL_S" =~ ^[1-9][0-9]{0,2}$ ]] || { echo "::error::arm-heartbeats.sh: ARM_POLL_INTERVAL_S must be a whole number of seconds between 1 and 999 (got '${ARM_POLL_INTERVAL_S:0:20}')."; exit 1; }

# Token-shape guard: a newline or quote in the token would inject a curl config directive on the
# stdin channel below. Never echoes the value. Better Stack tokens are alphanumeric.
_bearer_ok() { local LC_ALL=C; case "${1:-}" in ''|*[!A-Za-z0-9._~+/=-]*) return 1 ;; esac; }

# The ONE credentialed curl. It owns the transport flags (`--disable` first so ~/.curlrc is
# skipped, `--noproxy '*'`), the token-shape guard and the bearer header. The header rides curl's
# stdin config channel (`--config -`) fed by a process substitution whose `printf` is the shell
# builtin, so the token is never in any process's argument list (/proc/<pid>/cmdline, `ps`). An
# unusable token makes zero curl calls and returns non-zero (callers read that as a failed call).
bs_api() {  # <transport args...> <url>
  _bearer_ok "$BS_TOKEN" || return 2
  curl --disable --noproxy '*' "$@" --config - 2>/dev/null \
    < <(printf 'header = "Authorization: Bearer %s"\n' "$BS_TOKEN")
}

now_s() { date +%s; }

# Operator-supplied or vendor-supplied text is shown with every non-printable byte replaced and a length
# cap, so it can neither forge a `::notice::` line (newline) nor drive the terminal (ESC, bidi override).
# The C locale makes `[:print:]` ASCII-only: in a UTF-8 locale U+202E and U+200B count as printable.
show() { local LC_ALL=C t="${1:0:200}"; t="${t//[^[:print:]]/?}"; printf '%s' "$t"; }

# --- the unconfirmed-arm state file -------------------------------------------------------
# One id per line. `state_add` fires immediately after a successful unpause; `state_remove`
# fires ONLY on a 2xx rollback or on reaching `up`.
state_add() {  # <id> [pre-unpause]
  # An append that fails is NOT ignorable (#7658 E4): the monitor is already LIVE at this point,
  # so a silently dropped id is a monitor off the sweep's books with nothing feeding it — the
  # exact state the file exists to make impossible.
  # A hand-edited file may not end in a newline: appending to it would GLUE this id onto the last
  # line (99 + 42 = 9942, a different monitor), so a leading newline is written in that case.
  local lead=""
  if [[ -s "$ARMED_UNCONFIRMED" && -n "$(tail -c1 "$ARMED_UNCONFIRMED" 2>/dev/null)" ]]; then lead=$'\n'; fi
  if ! printf '%s%s\n' "$lead" "$1" >> "$ARMED_UNCONFIRMED"; then
    if [[ "${2:-}" == pre-unpause ]]; then
      echo "::error::arm-heartbeats.sh: could not record monitor $1 in $(show "$ARMED_UNCONFIRMED") BEFORE unpausing it — nothing was changed; refusing to unpause a monitor with nowhere to record it."
      return 1
    fi
    echo "::error::arm-heartbeats.sh: could not record monitor $1 in $(show "$ARMED_UNCONFIRMED") — it is UNPAUSED and OFF the re-pause sweep's books. Re-pause it by hand: Better Stack → Heartbeats → $1 → Pause."
    return 1
  fi
  # Before the unpause the id must be READ BACK: an append that "succeeds" into a file that does not
  # keep it (a procfs entry, a glued line) would let the monitor go live off the books.
  if [[ "${2:-}" == pre-unpause ]] && ! grep -qxF -- "$1" "$ARMED_UNCONFIRMED" 2>/dev/null; then
    echo "::error::arm-heartbeats.sh: monitor $1 was appended to $(show "$ARMED_UNCONFIRMED") but could not be read back from it — nothing was changed; refusing to unpause a monitor that is not on the books."
    return 1
  fi
}
state_remove() {
  [[ -f "$ARMED_UNCONFIRMED" ]] || return 0
  local keep grc
  # lint-trap-ownership: ok no EXIT trap by design (Cut List C6): a trap would delete the books file on the very interruption it must survive; the scratch file is renamed over the books or removed on every path below
  if ! keep=$(mktemp "${ARMED_UNCONFIRMED}.keep.XXXXXX"); then
    echo "::error::arm-heartbeats.sh: could not create a scratch file beside $(show "$ARMED_UNCONFIRMED"); leaving it INTACT. The re-pause sweep will re-PATCH ${1}, which is idempotent."
    return 1
  fi
  # `grep -vxF` exits 1 when it selects nothing, which is the ORDINARY case here (the last id
  # being removed). Exit >= 2 is grep FAILING — an unreadable source, a broken pipe, ENOSPC on
  # the redirect — and `$keep` is then empty or truncated. Installing it would silently drop
  # every OTHER id from the books, which is precisely the failure this file claims to design out
  # (#7658 E3). Never read the source file through a pipe either: a `grep -q` on a pipe takes
  # SIGPIPE on an early match under pipefail.
  grep -vxF -- "$1" "$ARMED_UNCONFIRMED" > "$keep" 2>/dev/null
  grc=$?
  if [[ "$grc" -ge 2 || ! -f "$keep" ]]; then
    rm -f "$keep"
    echo "::error::arm-heartbeats.sh: could not rewrite $(show "$ARMED_UNCONFIRMED") (grep rc=${grc}); leaving it INTACT. The re-pause sweep will re-PATCH ${1}, which is idempotent."
    return 1
  fi
  if ! mv -f "$keep" "$ARMED_UNCONFIRMED"; then
    rm -f "$keep"
    echo "::error::arm-heartbeats.sh: could not install the rewritten $(show "$ARMED_UNCONFIRMED"); leaving it INTACT."
    return 1
  fi
}

# --- Better Stack ---------------------------------------------------------------------------
# HB_STATUS / HB_UPDATED_AT are set by hb_fetch and read by arm_one's terminal branch.
HB_STATUS=""
HB_UPDATED_AT=""
HB_PATCH_CODE=""
# CR/LF are stripped from every vendor-controlled string before it can reach an `echo "::…"`
# (#7658 E7). `jq -r` unescapes `\n` into a real newline, so an `updated_at` containing one
# breaks out of the annotation and emits an attacker-chosen line at column 0, which the runner
# parses as a workflow command (`::error::`, `::add-mask::`, `::stop-commands::`).
# `-f` here is belt-and-braces, NOT the load-bearing check, and this is recorded because the
# review found `-f` deletable with both suites green (#7656 C4). Where it MATTERED was the old
# `hb_patch_paused`, a bare `curl` whose exit status WAS its verdict — without `-f` a rollback that
# got HTTP 500 read as success. That call now reads `%{http_code}` and does not depend on `-f` at
# all. On this GET the flag is genuinely redundant: with or without it, a 5xx yields a body with no
# `.data.attributes.status`, so the guard below fails closed either way (verified by mutation). The
# check that decides is `[[ -n "$HB_STATUS" ]]`, and deleting THAT reds the suite (row M10).
hb_fetch() {  # <id> -> 0 and sets HB_STATUS/HB_UPDATED_AT; non-zero when the lookup failed
  local body
  body=$(bs_api -fsS --max-time "$ARM_CURL_MAX_TIME_S" "${BS_API_BASE}/heartbeats/$1")
  # There is deliberately no separate `[[ -n "$body" ]] || return 1` here. It was in the extracted
  # original and it is unobservable: an empty or non-JSON body makes `jq` yield nothing, so the
  # `[[ -n "$HB_STATUS" ]]` guard below already fails closed on exactly the same inputs. A second
  # guard that no input can distinguish from the first is a guard that cannot be driven red
  # (#7656 C5) — the suite's T7b/T7c drive an empty 200 and a 200 with no `.status` through the
  # ONE guard that decides, and M10 proves deleting it changes the verdict.
  HB_STATUS=$(printf '%s' "$body" | jq -r '.data.attributes.status // empty' 2>/dev/null | tr -d '\r\n')
  HB_UPDATED_AT=$(printf '%s' "$body" | jq -r '.data.attributes.updated_at // "unreported"' 2>/dev/null | tr -d '\r\n')
  # Vendor text reaches the operator's terminal (the rollback-failed line, the poll notices): reduce it to a harmless charset.
  HB_STATUS="${HB_STATUS//[^A-Za-z0-9_.-]/?}"
  HB_UPDATED_AT="${HB_UPDATED_AT//[^A-Za-z0-9_.:+-]/?}"
  [[ -n "$HB_STATUS" ]] || return 1
  return 0
}
# ONE implementation, STATUS-CODE semantics (#7658 E6, #7659 F1). `curl -fsS` alone was the
# in-script predicate while the sweep read `-w '%{http_code}'`: two halves of one mechanism with
# two different success tests, and prose claiming both were "2xx". `-f` is also weaker than the
# claim — it does not reject a 3xx, and without `-L` curl does not follow one either. Reading the
# code makes "2xx" a fact rather than a paraphrase, and it makes a 5xx impossible to mistake for
# a successful rollback.
hb_patch_paused() {  # <id> <true|false> -> 0 on a 2xx; sets HB_PATCH_CODE
  HB_PATCH_CODE=$(bs_api -sS -o /dev/null -w '%{http_code}' --max-time "$ARM_CURL_MAX_TIME_S" \
    -X PATCH -H 'Content-Type: application/json' \
    "${BS_API_BASE}/heartbeats/$1" --data-raw "{\"paused\":$2}")
  HB_PATCH_CODE="${HB_PATCH_CODE//[^0-9]/}"
  # curl printed nothing at all — a transport failure or a `--max-time` kill. `000` is curl's own
  # spelling for that, and naming it keeps the retry classifier below total over the status space.
  [[ -n "$HB_PATCH_CODE" ]] || HB_PATCH_CODE=000
  [[ "$HB_PATCH_CODE" =~ ^2 ]]
}

# THE ROLLBACK RETRIES ONCE, AND ONLY ON A STATUS THAT COULD SUCCEED ON A SECOND TRY (#7658 E8).
# Deviation 3 made a FAILED rollback fatal (return 1) even for the soft inngest caller, which is
# the right direction — a monitor that is unpaused with nothing feeding it is a statement about the
# ARMING, and a soft landing there would leave the apply GREEN while production uptime alerting is
# live-and-unfed. But it made a SINGLE unretried round-trip fatal, on the one arm that can never
# take the no-op branch while #7228 is open: at 2.71 merge-applies/day that is ~990 rollback
# PATCHes a year, every one of them able to red a routine apply and raise a false ops alarm on one
# lost packet. The vendor's error rate is UNVERIFIED — this repo holds no measurement of it — so
# the cost is stated as a sensitivity: p = 0.1 % → ~1 false red/yr, p = 0.5 % → ~5, p = 1 % → ~10.
#
# One immediate retry, no backoff: `--max-time` already bounds each attempt, the failure mode being
# covered is a lost round-trip rather than a busy server, and every extra attempt is a term the
# step's wall-clock ceiling has to carry (the ladder budgets `ARM_ROLLBACK_ATTEMPTS` explicitly).
# A 4xx is NOT retried — a 401/403/404 does not fix itself on a second immediate call, and burning
# the budget on it delays the `::error::` the operator needs.
#
# The sweep deliberately does NOT layer a second retry on top of this: it IS the next attempt, it
# runs seconds later on the same id, and its own failure is reported as `outcome=partial` rather
# than swallowed.
ARM_ROLLBACK_ATTEMPTS=2
hb_rollback() {  # <id> <label> -> 0 once the monitor is confirmed paused
  local id="$1" label="$2" attempt=1
  while true; do
    hb_patch_paused "$id" true && return 0
    [[ "$attempt" -lt "$ARM_ROLLBACK_ATTEMPTS" ]] || return 1
    case "$HB_PATCH_CODE" in
      5*|000) ;;
      *) return 1 ;;
    esac
    echo "::warning::${label}: rollback PATCH paused=true returned HTTP ${HB_PATCH_CODE} — retrying once before treating the monitor as still live."
    attempt=$(( attempt + 1 ))
  done
}

# =================================================================================================
# --sweep — the rollback that survives a cancellation (#7587)
# =================================================================================================
# `arm_one` rolls a monitor back to `paused` on its own terminal branch. That line is unreachable
# on an EXTERNALLY-IMPOSED cut — a step timeout, a job timeout, a cancel — and on those paths a
# heartbeat is left unpaused with nothing feeding it, so it pages on absence at whatever hour its
# grace window expires. This is the backstop, invoked from a sibling step gated `if: always()`.
sweep_main() {
  local armed repaused failed outcome ids id rc
  if [[ ! -s "$ARMED_UNCONFIRMED" ]]; then
    # The modal case by a wide margin: an apply that never unpaused anything. Reported rather
    # than silent, so `outcome=` has a value on EVERY run and the email can tell "the sweep found
    # nothing to do" apart from "the sweep did not run".
    sweep_report 0 0 0 noop
    return 0
  fi
  armed=$(grep -c '' "$ARMED_UNCONFIRMED" 2>/dev/null || echo 0)
  ids=$(tr '\n' ' ' < "$ARMED_UNCONFIRMED" 2>/dev/null | sed 's/ *$//')
  echo "::warning::Heartbeat re-pause sweep FIRED: ${armed} monitor(s) were left unpaused-and-unconfirmed by the ARM gate (${ids}). Production uptime alerting for them was live with nothing feeding it."

  # An EMPTY token and a token of an unusable shape are the same outcome: no request can be made
  # with it (`bs_api` would refuse), so no id can even be attempted.
  if ! _bearer_ok "$BS_TOKEN"; then
    # The ids, not just the count (#7655 B3). They are the only thing that lets an operator
    # re-pause by hand, and this branch exits before the loop that would otherwise echo them.
    echo "::error::Re-pause sweep: no Better Stack API token — ${armed} monitor(s) are LIVE AND UNFED and this step cannot re-pause them: ${ids}. Re-pause each by hand: Better Stack → Heartbeats → the id → Pause. They will page when their grace window expires."
    sweep_report "$armed" 0 "$armed" mint-unreadable
    return 1
  fi

  repaused=0
  failed=0
  # Read the state file directly, never through a pipe: under `pipefail` a producer that takes
  # SIGPIPE turns a correct read into a non-zero pipeline.
  while read -r id; do
    [[ -n "$id" ]] || continue
    # Idempotent: re-PATCHing `paused:true` on an already-paused monitor is a no-op, which is
    # what lets this run after the ARM step has already cleared some ids.
    if hb_patch_paused "$id" true; then
      repaused=$(( repaused + 1 ))
      echo "re-paused heartbeat ${id} (HTTP ${HB_PATCH_CODE})"
    else
      failed=$(( failed + 1 ))
      echo "::error::Re-pause sweep: PATCH {\"paused\":true} for heartbeat ${id} returned HTTP ${HB_PATCH_CODE:-000} — it is STILL unpaused-and-unfed."
    fi
  done < "$ARMED_UNCONFIRMED"

  outcome=repaused
  rc=0
  if [[ "$failed" -gt 0 ]]; then
    outcome=partial
    rc=1
  fi
  sweep_report "$armed" "$repaused" "$failed" "$outcome"

  # FAIL, do not merely annotate. `::error::` does not fail a step, and every path that leaves
  # this file non-empty already reds the apply job — so an annotating sweep would only ever
  # soften a red, never create one. What it MUST not do is stay green on the one path where it
  # could not finish the job: a still-unpaused monitor has to keep the run non-green so
  # `notify-apply-failure` fires and the operator is emailed.
  if [[ "$failed" -gt 0 ]]; then
    echo "::error::Re-pause sweep could not re-pause ${failed} of ${armed} monitor(s). They are live with nothing feeding them and will page on absence."
    return 1
  fi
  if [[ "$armed" -gt 0 ]]; then
    echo "::warning::Heartbeat re-pause sweep re-paused ${repaused} of ${armed} monitor(s). Uptime alerting for them is PAUSED until the next apply arms them; the previously-applied infrastructure is unaffected."
  fi
  return "$rc"
}

# The structured line goes to an ANNOTATION first and the run summary second (#7659 F2).
# `$GITHUB_STEP_SUMMARY` has NO REST API — this repo has already been burned by reading a field
# that cannot say otherwise (#7307, knowledge-base/project/learnings/2026-08-09-the-monitor-
# reported-success-and-i-read-the-field-that-cannot-say-otherwise.md) — so a summary-only tag is
# human-only, readable exactly by opening the run's web page. `::notice::` annotations ARE
# retrievable: `gh api repos/{o}/{r}/check-runs/<job-id>/annotations`.
sweep_report() {  # <armed> <repaused> <failed> <outcome>
  echo "::notice::heartbeat-repause-sweep armed=$1 repaused=$2 failed=$3 outcome=$4"
  [[ -n "${GITHUB_STEP_SUMMARY:-}" ]] || return 0
  { echo "### Heartbeat re-pause sweep"; echo; echo "armed=$1 repaused=$2 failed=$3 outcome=$4"; } >> "$GITHUB_STEP_SUMMARY"
}

if [[ "$MODE" == "sweep" ]]; then
  if [[ -z "$ARMED_UNCONFIRMED" ]]; then
    echo "::error::arm-heartbeats.sh --sweep: ARMED_UNCONFIRMED is unset — refusing to run a half-configured sweep."
    exit 1
  fi
  sweep_main
  exit $?
fi

# =================================================================================================
# --arm (default)
# =================================================================================================

# The tfstate / required-env / resource-count preflight belongs to the per-merge arm only (#9980):
# --status and --arm-one resolve their monitor by name through the API and read no tfstate.
if [[ "$MODE" == arm ]]; then
  for _required in BS_TOKEN TFSTATE_JSON ARMED_UNCONFIRMED; do
    if [[ -z "${!_required}" ]]; then
      echo "::error::arm-heartbeats.sh: ${_required} is unset — refusing to run a half-configured arming pass."
      exit 1
    fi
  done
  if ! _bearer_ok "$BS_TOKEN"; then
    echo "::error::arm-heartbeats.sh: BS_TOKEN has an unexpected shape — refusing to run an arming pass that could not authenticate."
    exit 1
  fi
  if [[ ! -r "$TFSTATE_JSON" ]]; then
    echo "::error::arm-heartbeats.sh: TFSTATE_JSON=${TFSTATE_JSON} is not readable — cannot resolve any monitor id."
    exit 1
  fi
  # READABLE IS NOT THE SAME AS POPULATED (#7658 E10). A readable `{}` — a `terraform show -json`
  # that failed soft, a truncated write, the wrong root — makes every `jq` lookup return empty, so
  # all six arms report "not present in tfstate" and the gate exits 0 having armed NOTHING, with no
  # error channel fired. A state with zero resources is never a legitimate input to this step.
  _resource_count=$(jq -r '[.values.root_module.resources[]?] | length' "$TFSTATE_JSON" 2>/dev/null)
  if [[ ! "$_resource_count" =~ ^[0-9]+$ || "$_resource_count" -eq 0 ]]; then
    echo "::error::arm-heartbeats.sh: TFSTATE_JSON=${TFSTATE_JSON} is readable but holds no resources — a contentless state would silently 'skip' every arm and exit green. Refusing."
    exit 1
  fi
fi

# ARM_ELAPSED / ARM_LAST_STATUS / ARM_LAST_UPDATED_AT report the last arm's terminal facts to
# the caller below. They are what the inngest-consumer message emits instead of a hard-coded
# deadline and a guess about which failure this was.
ARM_ELAPSED=0
ARM_LAST_STATUS=""
ARM_LAST_UPDATED_AT=""

# arm_one <state-address> <label> <deadline_seconds> [<given-id>]
#   0 = armed or no-op          1 = the gate could not do its job (incl. a FAILED rollback)
#   2 = the gate worked and the FEEDER did not feed, monitor rolled back to paused
# <given-id> (the 4th, OPTIONAL positional; --arm-one only) is a Better Stack id already resolved by
# exact name: with it, <state-address> is a display token and tfstate is not read. ARM_RESULT reports
# which return this was: armed | noop | unpause-failed | books-failed | rollback-failed (empty otherwise).
arm_one() {
  local addr="$1" label="$2" deadline="$3" given_id="${4:-}"
  local id started elapsed reads_ok
  ARM_RESULT=""
  ARM_ELAPSED=0
  ARM_LAST_STATUS=""
  ARM_LAST_UPDATED_AT=""
  # `--arm-one` hands the id it already resolved by exact name as a 4th POSITIONAL argument (#9980): a
  # positional cannot be steered by the environment, and the six per-list `arm_one` call lines (five
  # per-merge arms plus the inngest block) pass three arguments.
  if [[ -n "$given_id" ]]; then
    id="$given_id"
  else
    id=$(jq -r --arg a "$addr" '.values.root_module.resources[]? | select(.address==$a) | .values.id' "$TFSTATE_JSON")
  fi
  if [[ -z "$id" || "$id" == "null" ]]; then
    echo "::notice::${label}: not present in tfstate (address ${addr}) — skipping (this apply path did not create it)."
    return 0
  fi
  if ! hb_fetch "$id"; then
    echo "::error::${label}: GET /heartbeats/${id} failed — cannot verify arm state."
    return 1
  fi
  if [[ "$HB_STATUS" != "paused" ]]; then
    ARM_RESULT=noop
    echo "${label}: already armed (status=${HB_STATUS//[^A-Za-z0-9_.-]/?}) — no-op."
    return 0
  fi
  # --arm-one only: the id goes on the books BEFORE the unpause PATCH. A request that lands server-side with
  # its reply lost (or a process killed mid-flight) must never leave a live monitor on nobody's books; a
  # re-pause of an already-paused monitor is idempotent, so the early entry costs nothing.
  if [[ -n "$given_id" ]] && ! state_add "$id" pre-unpause; then
    ARM_RESULT=books-failed
    return 1
  fi
  echo "${label}: monitor ${id} is paused; unpausing and watching for a real beat (status→up, deadline=${deadline}s)…"
  if ! hb_patch_paused "$id" false; then
    ARM_RESULT=unpause-failed
    echo "::error::${label}: PATCH paused=false FAILED (HTTP ${HB_PATCH_CODE:-000}) — cannot begin arming."
    return 1
  fi
  # The id is on the sweep's books from the instant the monitor is live, not from the instant
  # we decide to give up: everything between those two points is exactly the window in which an
  # externally-imposed cut leaves it unpaused-and-unfed. (--arm-one recorded it BEFORE the unpause; this per-merge path records after.)
  if [[ -z "$given_id" ]]; then state_add "$id"; fi
  started=$(now_s)
  elapsed=0
  reads_ok=0
  while [[ "$elapsed" -lt "$deadline" ]]; do
    sleep "$ARM_POLL_INTERVAL_S"
    if hb_fetch "$id"; then
      ARM_LAST_STATUS="$HB_STATUS"
      ARM_LAST_UPDATED_AT="$HB_UPDATED_AT"
      reads_ok=$(( reads_ok + 1 ))
    else
      # NEVER carry the PRE-UNPAUSE reading forward (#7658 E1). The seed value was `paused`, and
      # at rollback the monitor is unpaused — so a stale carry makes the terminal message report
      # `status=paused` as an observation, which is affirmatively false, and makes a total loss
      # of Better Stack visibility render as a benign feeder miss.
      ARM_LAST_STATUS=""
      ARM_LAST_UPDATED_AT=""
    fi
    # Re-read the CLOCK rather than adding the sleep: the round-trip above is inside the loop
    # and is the term the old tally ignored.
    elapsed=$(( $(now_s) - started ))
    if [[ "$ARM_LAST_STATUS" == "up" ]]; then
      ARM_ELAPSED="$elapsed"
      state_remove "$id"
      ARM_RESULT=armed
      echo "::notice::${label}: status=up within ${elapsed}s — a real beat landed. ARMED."
      return 0
    fi
  done
  ARM_ELAPSED="$elapsed"
  # No `up` in time: roll back to paused BEFORE the first absence alert.
  #
  # rc=2, NOT 1, and the distinction is load-bearing for exactly one caller. Every other
  # non-zero exit from this function ("GET failed", "PATCH failed") means the gate could not do
  # its job. THIS one means the gate worked and the FEEDER is not feeding — an assertion about
  # the monitored system, not about the arming. Callers whose feeder is expected to be healthy
  # still treat it as fatal (`|| rc=1` catches any non-zero); the inngest-consumer caller below
  # distinguishes it, because its feeder is knowingly dark.
  #
  # A FAILED rollback is NOT that case and returns 1 even for the soft caller. "The monitor is
  # unpaused and nothing is feeding it" is a statement about the arming, and it is the one
  # condition where a soft landing would leave the apply job GREEN while production uptime
  # alerting is live-and-unfed — the predicate on the notify job would be false and nobody
  # would be emailed, which is the #7586 defect reproduced inside the #7587 fix.
  #
  # NEITHER is a poll that never read a status at all. rc=2 asserts something about the feeder,
  # and no such assertion is available when every in-loop GET failed (#7658 E1) — that is a loss
  # of vendor visibility, i.e. the gate could not do its job, so it returns 1.
  if ! hb_rollback "$id" "$label"; then
    ARM_RESULT=rollback-failed
    echo "::error::${label}: rollback PATCH paused=true FAILED (HTTP ${HB_PATCH_CODE:-000}) after ${ARM_ROLLBACK_ATTEMPTS} attempt(s) — monitor ${id} is unpaused-and-unfed. It is on the re-pause sweep's books unless an earlier 'could not record' error says otherwise; investigate immediately."
    echo "::error::${label}: status never reached 'up' within ${elapsed}s of a ${deadline}s deadline (last status=${ARM_LAST_STATUS:-unknown})."
    return 1
  fi
  state_remove "$id"
  if [[ "$reads_ok" -eq 0 ]]; then
    echo "::error::${label}: every status read during the ${deadline}s poll FAILED — the monitor was unpaused, could not be observed at all, and has been rolled back to paused. This is a loss of Better Stack visibility, NOT a verdict about the feeder."
    return 1
  fi
  if [[ -z "$given_id" ]]; then
    echo "::error::${label}: status never reached 'up' within ${elapsed}s of a ${deadline}s deadline (probe timer never pinged) — ROLLED BACK to paused. A green-but-inert monitor is the #6400 shape this gate exists to prevent. Investigate: is the web-1 timer installed + the private-net path healthy?"
  else
    echo "::error::${label}: status never reached 'up' within ${elapsed}s of a ${deadline}s deadline (no beat landed) — ROLLED BACK to paused. A green-but-inert monitor is the #6400 shape this gate exists to prevent. Read this monitor's own feeder signal before retrying."
  fi
  return 2
}

# =================================================================================================
# --status / --arm-one (#9980) — one monitor, by exact name
# =================================================================================================
# RES_* are written by hb_resolve_name and read by the two mains. The resolver is always called
# DIRECTLY (never inside $( ) or a `| while read` pipeline), so they survive in this shell.
RES_COUNT=0; RES_ID=""; RES_IDS=""; RES_PAUSED=""; RES_STATUS=""; RES_PERIOD=""; RES_GRACE=""; RES_COMPLETE=0
# The ONE list read. The destination is the PINNED base plus the caller's validated query ($1, a positional
# exactly like hb_fetch's id), so it can never name another host.
hb_list_page() {  # <query> -> the page body on stdout; non-zero when the read failed
  local page_body
  page_body=$(bs_api -fsS --max-time "$ARM_CURL_MAX_TIME_S" "${BS_API_BASE}/heartbeats?$1") || return 1
  printf '%s' "$page_body"
}
hb_resolve_name() {  # <name> -> 0 when the whole list was read (RES_COUNT says how many matched); 1 otherwise
  local name="$1" query pages=0 body rows next rid rstatus rpaused rperiod rgrace
  RES_COUNT=0; RES_ID=""; RES_IDS=""; RES_PAUSED=""; RES_STATUS=""; RES_PERIOD=""; RES_GRACE=""; RES_COMPLETE=0
  query="per_page=250"
  while [[ -n "$query" ]]; do
    pages=$(( pages + 1 ))
    if [[ "$pages" -gt "$ARM_LIST_MAX_PAGES" ]]; then
      echo "::error::arm-heartbeats.sh: the heartbeat list did not end within ${ARM_LIST_MAX_PAGES} pages — refusing to resolve '${name}' from a partial read."
      return 1
    fi
    # The query is the ONLY thing this function varies, and it is pinned to page/per_page numbers: a vendor
    # `pagination.next` that is off-origin, off-path or carries any other parameter never reaches a request.
    if [[ ! "$query" =~ ^(page|per_page)=[0-9]+(\&(page|per_page)=[0-9]+)?$ ]]; then
      echo "::error::arm-heartbeats.sh: refusing to follow a pagination.next that leaves ${BS_API_BASE}/heartbeats (page, per_page only)."
      return 1
    fi
    if ! body=$(hb_list_page "$query"); then
      echo "::error::arm-heartbeats.sh: GET of the heartbeat list (page ${pages}) failed — cannot resolve '${name}'."
      return 1
    fi
    # A 200 that is not a list is a FAILED read. Counted as an empty page it would hide a duplicate.
    if ! printf '%s' "$body" | jq -e '.data | type == "array"' >/dev/null 2>&1; then
      echo "::error::arm-heartbeats.sh: page ${pages} of the heartbeat list carries no .data array — refusing to resolve '${name}' from a partial read."
      return 1
    fi
    # \x1f, not tab: tab is IFS-whitespace, so `read` would collapse an empty field and shift the rest.
    # Every field is VALIDATED before it is shaped (a vendor id of "42<LF>43" must not become 4243 by having
    # its newline stripped): ids and numbers are digits, `null` (absent) or INVALID, and the display-only
    # fields (status, paused) are reduced to a harmless charset so nothing vendor-controlled reaches the
    # operator's terminal raw.
    if ! rows=$(printf '%s' "$body" | jq -r --arg n "$name" '
        def idv: if (type == "number" or (type == "string" and test("\\A[0-9]{1,18}\\z"))) then tostring else "INVALID" end;
        def num: if . == null then "null" elif ((type == "number" or type == "string") and (tostring | test("\\A[0-9]{1,9}\\z"))) then tostring else "INVALID" end;
        def txt: if . == null or . == "" then "null" else (tostring | gsub("[^A-Za-z0-9_.-]"; "?")) end;
        .data[] | select(.attributes.name == $n)
        | [ (.id | idv), (.attributes.status | txt),
            (.attributes | if has("paused") and .paused != null then .paused else "unreported" end | txt),
            (.attributes.period | num), (.attributes.grace | num) ]
        | join("\u001f")' 2>/dev/null); then
      echo "::error::arm-heartbeats.sh: could not parse page ${pages} of the heartbeat list."
      return 1
    fi
    if [[ -n "$rows" ]]; then
      while IFS=$'\x1f' read -r rid rstatus rpaused rperiod rgrace; do
        if [[ ! "$rid" =~ ^[0-9]+$ ]]; then
          echo "::error::arm-heartbeats.sh: a heartbeat named '${name}' carries a missing or non-numeric id — refusing."
          return 1
        fi
        # COUNTED, never de-duplicated: a row repeated by an overlapping page reads as a collision. A false
        # refusal costs the owner one look; a false unique match arms the wrong monitor.
        RES_COUNT=$(( RES_COUNT + 1 ))
        RES_IDS="${RES_IDS}${RES_IDS:+ }${rid}"
        RES_ID="$rid"; RES_STATUS="$rstatus"; RES_PAUSED="$rpaused"; RES_PERIOD="$rperiod"; RES_GRACE="$rgrace"
      done <<< "$rows"
    fi
    # `.pagination` absent is a single page; a present one must be an object whose `next` is absent or a
    # string. Anything else is a FAILED read: treating it as "no next page" would resolve from a partial list.
    if ! next=$(printf '%s' "$body" | jq -r '
        if (.pagination == null) or ((.pagination | type) == "object" and ((.pagination | has("next") | not) or (.pagination.next == null) or ((.pagination.next | type) == "string")))
        then ((.pagination.next // "") | if (length > 0) and (gsub("[\r\n]"; "") | length) == 0 then error("empty pagination.next") else . end) else error("malformed pagination") end' 2>/dev/null); then
      echo "::error::arm-heartbeats.sh: page ${pages} of the heartbeat list carries a malformed .pagination — refusing to resolve '${name}' from a partial read."
      return 1
    fi
    next="${next//$'\r'/}"; next="${next//$'\n'/}"
    # Stripping the pinned prefix leaves a bare query; anything that was not under that prefix stays a full
    # URL, which the pin above then refuses. A `next` that strips to NOTHING (`.../heartbeats?`) is not an
    # end of list: it is a partial-read shape, refused rather than read as "no more pages".
    query=""
    if [[ -n "$next" ]]; then
      query="${next#"${BS_API_BASE}/heartbeats?"}"
      if [[ -z "$query" ]]; then
        echo "::error::arm-heartbeats.sh: page ${pages} of the heartbeat list carries an empty pagination.next — refusing to resolve '${name}' from a partial read."
        return 1
      fi
    fi
  done
  RES_COMPLETE=1
  return 0
}

# Both named modes need a usable token before any request; the destination pin already ran.
named_token_check() {
  if ! _bearer_ok "$BS_TOKEN"; then
    echo "::error::arm-heartbeats.sh: BS_TOKEN is unset or has an unexpected shape — refusing to make a request that could not authenticate."
    return 1
  fi
}
# Exactly one exact-name match, or a named refusal. Sets nothing the callers must trust except RES_*.
resolve_exactly_one() {
  hb_resolve_name "$NAME" || return 1
  if [[ "$RES_COUNT" -eq 0 ]]; then
    echo "::error::arm-heartbeats.sh: no heartbeat is named '${NAME}' (exact match over the whole list)."
    return 1
  fi
  if [[ "$RES_COUNT" -gt 1 ]]; then
    echo "::error::arm-heartbeats.sh: ${RES_COUNT} heartbeats are named '${NAME}': ids ${RES_IDS}; refusing to pick one."
    return 1
  fi
  return 0
}

status_main() {
  named_token_check || return 1
  resolve_exactly_one || return 1
  echo "name=${NAME} id=${RES_ID} paused=${RES_PAUSED} status=${RES_STATUS} period=${RES_PERIOD} grace=${RES_GRACE}"
  return 0
}

# The machine verdict: ONE `::notice::` annotation an agent can parse without reading prose.
ARM_ONE_OUTCOME=refused
arm_one_verdict() {  # <rc>
  # The id is claimed only when exactly ONE monitor matched; a collision or an unread list has no single id.
  local vid=none
  if [[ "$RES_COUNT" -eq 1 && "$RES_COMPLETE" -eq 1 ]]; then vid="$RES_ID"; fi
  echo "::notice::arm-one-result name=${NAME} id=${vid} outcome=${ARM_ONE_OUTCOME} rc=$1"
}
# Absolute path of this script, for the printed recovery command. CDPATH is cleared for the `cd`: a
# non-empty CDPATH makes `cd` print the directory, which would put two lines in the printed command.
self_path() {
  local src="${BASH_SOURCE[0]:-$0}" dir
  if dir=$(CDPATH='' cd -- "$(dirname -- "$src")" >/dev/null 2>&1 && pwd); then
    printf '%s/%s' "$dir" "$(basename -- "$src")"
  else
    printf '%s' "$src"
  fi
}
recovery_cmd() {
  # LC_ALL=C makes %q escape every non-ASCII byte, so a bidi override in a path cannot ride into the pasteable line.
  local LC_ALL=C
  printf 'ARMED_UNCONFIRMED=%q bash %q --sweep   # needs the SAME WRITE-scope BS_TOKEN (runbook step 7 shows the doppler wrapper); read --status FIRST: if it says status=up do NOT sweep' "$ARMED_UNCONFIRMED" "$(self_path)"
}
armone_run() {
  local own_books=0 max rc=0 on_books=0 left safe_status probe
  named_token_check || return 1
  resolve_exactly_one || return 1
  if [[ "$HAVE_ID" -eq 1 && "$PIN_ID" != "$RES_ID" ]]; then
    echo "::error::arm-heartbeats.sh: id pin mismatch — '${NAME}' resolves to id ${RES_ID}, not the pinned ${PIN_ID}. Refusing to arm either."
    return 1
  fi
  # The ceiling: the unpause window (deadline + the loop's last round-trips) must end before THIS monitor's
  # own first absence alert. Derived from the file's own terms; at 10/15 it is period + grace - 40. The
  # digit bound keeps the arithmetic below inside the shell's integer range.
  if [[ ! "$RES_PERIOD" =~ ^[1-9][0-9]{0,8}$ || ! "$RES_GRACE" =~ ^[1-9][0-9]{0,8}$ ]]; then
    echo "::error::arm-heartbeats.sh: period/grace of '${NAME}' are not positive integers (period=${RES_PERIOD} grace=${RES_GRACE}) — cannot bound the unpause window, refusing."
    return 1
  fi
  max=$(( RES_PERIOD + RES_GRACE - (ARM_POLL_INTERVAL_S + 2 * ARM_CURL_MAX_TIME_S) ))
  if [[ "$ARM_ONE_DEADLINE" -gt "$max" ]]; then
    echo "::error::arm-heartbeats.sh: the ${ARM_ONE_DEADLINE}s arm deadline exceeds this monitor's ceiling of ${max}s (period ${RES_PERIOD} + grace ${RES_GRACE} - reserve) — an arm that outlives its first absence alert would false-page. Refusing."
    return 1
  fi
  if [[ -z "$ARMED_UNCONFIRMED" ]]; then
    # lint-trap-ownership: ok the private books file must outlive the process on interruption (the printed --sweep command reads it); removed on a clean finish
    if ! ARMED_UNCONFIRMED=$(mktemp "${TMPDIR:-/var/tmp}/arm-one-unconfirmed.XXXXXX"); then
      echo "::error::arm-heartbeats.sh: could not create the private books file under ${TMPDIR:-/var/tmp} — refusing to unpause a monitor with nowhere to record it."
      return 1
    fi
    own_books=1
  elif [[ -L "$ARMED_UNCONFIRMED" ]] || { [[ -e "$ARMED_UNCONFIRMED" ]] && { [[ ! -f "$ARMED_UNCONFIRMED" ]] || [[ ! -r "$ARMED_UNCONFIRMED" ]]; }; } \
       || ! { : >> "$ARMED_UNCONFIRMED"; } 2>/dev/null \
       || ! { probe=$(mktemp "${ARMED_UNCONFIRMED}.probe.XXXXXX" 2>/dev/null) && rm -f "$probe"; }; then
    # Absent, or a plain readable regular file we can append to AND rewrite beside (state_remove needs a sibling
    # scratch file; without one a successful arm would leave its id on the books). A symlink, a device (/dev/null swallows every
    # write), a FIFO or a directory would let the unpause land with nothing real on the books.
    echo "::error::arm-heartbeats.sh: ARMED_UNCONFIRMED=$(show "$ARMED_UNCONFIRMED") must be absent or a readable, writable regular file (not a symlink) — refusing to unpause a monitor with nowhere to record it."
    return 1
  fi
  echo "::notice::arm-one books: $(show "$ARMED_UNCONFIRMED"). Any interruption (Ctrl-C, a closed terminal) can leave the monitor live; re-pause with: $(recovery_cmd)"
  arm_one "(by name)" "$NAME" "$ARM_ONE_DEADLINE" "$RES_ID" || rc=$?

  if [[ "$rc" -eq 0 && "$ARM_RESULT" == noop ]]; then
    # arm_one's no-op branch is right for the per-merge path (any live status is "already armed"). For THIS
    # mode rc 0 is read as "the soak is satisfied", so only a monitor that is `up` may say so.
    if [[ "$HB_STATUS" == "up" ]]; then
      ARM_ONE_OUTCOME=already-up
      # A line left by an earlier interrupted run would have the sweep re-pause a monitor that is now fed.
      if grep -qxF -- "$RES_ID" "$ARMED_UNCONFIRMED" 2>/dev/null; then
        state_remove "$RES_ID" && echo "::notice::arm-heartbeats.sh: removed the stale line ${RES_ID} from $(show "$ARMED_UNCONFIRMED") (the monitor is up)."
      fi
    else
      ARM_ONE_OUTCOME=live-not-up
      rc=1
      safe_status="${HB_STATUS//[^A-Za-z0-9_.-]/?}"
      echo "::error::arm-heartbeats.sh: '${NAME}' (id ${RES_ID}) is live but its status is '${safe_status:0:40}', not 'up' — this run did NOT arm it and no beat was measured. Read --status again after 60-120 s; if it is still not up and should be paused, pause it in Better Stack (Heartbeats → ${RES_ID} → Pause)."
    fi
  elif [[ "$rc" -eq 0 && "$ARM_RESULT" == armed ]]; then
    ARM_ONE_OUTCOME=armed
  elif [[ "$rc" -eq 0 ]]; then
    # rc 0 without a recognised result is a code path this mode does not understand: never report it as armed.
    rc=1
    ARM_ONE_OUTCOME=failed
    echo "::error::arm-heartbeats.sh: internal error — arm_one returned 0 with no result; refusing to report '${NAME}' as armed. Read --status."
  elif [[ "$ARM_RESULT" == rollback-failed ]]; then
    ARM_ONE_OUTCOME=rollback-failed
    echo "::error::arm-heartbeats.sh: monitor ${RES_ID} is LIVE and unfed and its re-pause failed; its id is on $(show "$ARMED_UNCONFIRMED"). Run: $(recovery_cmd)"
  elif [[ "$rc" -eq 2 ]]; then
    ARM_ONE_OUTCOME=rolled-back
    echo "::warning::${NAME}: the monitor is paused again and the soak is NOT satisfied. If this is the git-data host monitor, read the host's own events (stage liveness) in Better Stack (runbook step 6)."
  elif [[ "$ARM_RESULT" == unpause-failed ]]; then
    # An unpause PATCH that answers 000/5xx may still have LANDED server-side with only the reply lost. The id
    # was recorded BEFORE the request, so whatever this read-back finds, the books already cover it.
    ARM_ONE_OUTCOME=unpause-unknown
    if ! hb_fetch "$RES_ID"; then
      echo "::error::arm-heartbeats.sh: the unpause PATCH failed AND '${NAME}' could not be read back, so it may be live and unfed. Its id is on $(show "$ARMED_UNCONFIRMED"); run: $(recovery_cmd)"
    elif [[ "$HB_STATUS" != "paused" ]]; then
      echo "::warning::${NAME}: the unpause reply was lost but the monitor IS live (status=${HB_STATUS//[^A-Za-z0-9_.-]/?}); rolling it back to paused."
      if hb_rollback "$RES_ID" "$NAME"; then
        state_remove "$RES_ID"
        ARM_ONE_OUTCOME=unpause-recovered
      else
        ARM_ONE_OUTCOME=rollback-failed
        echo "::error::arm-heartbeats.sh: monitor ${RES_ID} is LIVE and unfed and its re-pause failed; its id is on $(show "$ARMED_UNCONFIRMED"). Run: $(recovery_cmd)"
      fi
    elif [[ "$HB_PATCH_CODE" == 4* ]]; then
      # A definite rejection: the request cannot land later.
      state_remove "$RES_ID"
      ARM_ONE_OUTCOME=failed
    else
      echo "::warning::arm-heartbeats.sh: the unpause PATCH was ambiguous (HTTP ${HB_PATCH_CODE:-000}) and the monitor reads paused, but the request may still land late. Its id stays on $(show "$ARMED_UNCONFIRMED"); read --status after 60-120 s: if it is paused, remove that line; if it is live, run: $(recovery_cmd)"
    fi
  else
    # books-failed, a failed GET gate, or every poll read failing (rolled back): nothing live is left by this run.
    ARM_ONE_OUTCOME=failed
  fi

  # What is left on the books after the outcome above is decided. It never changes the outcome.
  # grep rc 1 is "not listed"; rc 2 is "could not read it", which must count as listed.
  grep -qxF -- "$RES_ID" "$ARMED_UNCONFIRMED" 2>/dev/null
  [[ $? -eq 1 ]] || on_books=1
  if [[ "$on_books" -eq 1 ]]; then
    case "$ARM_ONE_OUTCOME" in
      armed|already-up|rolled-back|unpause-recovered)
        left=paused
        [[ "$ARM_ONE_OUTCOME" == armed || "$ARM_ONE_OUTCOME" == already-up ]] && left=up
        echo "::warning::arm-heartbeats.sh: the books file $(show "$ARMED_UNCONFIRMED") still lists ${RES_ID}, which this run left ${left}. Remove ONLY that line (other ids on it may be live and unfed). Do not run --sweep while '${NAME}' is ${left}-and-listed unless you mean to pause it." ;;
      failed)
        # `failed` includes a gate read that never answered: this run did not establish the monitor's state, so
        # nothing here may claim one.
        echo "::warning::arm-heartbeats.sh: the books file $(show "$ARMED_UNCONFIRMED") still lists ${RES_ID} and this run did not establish whether '${NAME}' is paused. Read --status FIRST: if it says paused=true remove ONLY that line; if it is live, run --sweep (or, if status=up, leave the monitor and remove that line)." ;;
    esac
  elif [[ "$own_books" -eq 1 && ! -s "$ARMED_UNCONFIRMED" ]]; then
    rm -f "$ARMED_UNCONFIRMED"
  fi
  return "$rc"
}
armone_main() {
  local rc=0
  armone_run || rc=$?
  arm_one_verdict "$rc"
  return "$rc"
}

if [[ "$MODE" == status ]]; then status_main; exit $?; fi
if [[ "$MODE" == armone ]]; then armone_main; exit $?; fi

rc=0
# deadline = period + grace − 40, where 40 = ARM_POLL_INTERVAL_S + 2 × ARM_CURL_MAX_TIME_S is the
# worst-case gap between the poll loop's last clock read and the rollback PATCH landing (#7657
# D5; the old reserve of 10 re-paused AFTER the first absence alert at ≥2 s of vendor latency).
# zot 180+60−40, nic-guard 360+120−40, git-data 60+180−40. inngest-consumer and web-bash-synthetic depart from the
# formula deliberately — see their own blocks below and the 2026-08-20 amendment to ADR-117.
arm_one 'betteruptime_heartbeat.web_zot_consumer["web-1"]' 'web-zot-consumer (web-1)' 200 || rc=1
arm_one 'betteruptime_heartbeat.web_nic_guard["web-1"]'    'web-nic-guard (web-1)'    440 || rc=1
# (#6459/ADR-143) web-2's per-host heartbeats are born `paused` (web-probe.tf
# ignore_changes=[paused]) exactly like web-1's; the ONLY unpause path is this gate, so they
# MUST be armed here or web2-standby-soak-6459.sh reads them `paused` and false-FAILs a healthy
# web-2 as a DARK host (#6459 could never close). arm_one no-ops (return 0) when the address is
# absent from tfstate, so this is inert on any apply path that has not yet created web-2.
arm_one 'betteruptime_heartbeat.web_zot_consumer["web-2"]' 'web-zot-consumer (web-2)' 200 || rc=1
arm_one 'betteruptime_heartbeat.web_nic_guard["web-2"]'    'web-nic-guard (web-2)'    440 || rc=1
# Measured absent from the merge-path tfstate (run 32360734255, 2026-08-20: "git-data-prd: not
# present in tfstate"), so today this arm returns in milliseconds. It is still a live call site
# and still counts toward the step's wall-clock ceiling, which is why the budget guard sums it.
arm_one 'betteruptime_heartbeat.git_data_prd'              'git-data-prd'             200 || rc=1

# (#10455 b, ADR-079 addendum 2026-10-20) web-bash-synthetic, one literal arm per host (the `for_each` beat is born `paused`
# like its siblings and this gate is its only unpause path; web-host-coverage in arm-heartbeats.test.sh fails when a
# var.web_hosts member lacks a call). The deadline departs from period+grace-40 (2660) ON PURPOSE, like the inngest arm below:
# 2660 s per host would put ~90 minutes of worst-case wall clock into every merge's ARM step whenever no beat can land.
# 300 s catches the first run after an install (timer first fires 30 s + up to 60 s of jitter after enable, then the run) and
# stays far below the first absence alert (900+1800), so a failed attempt cannot false-page. A beat is NOT guaranteed inside
# the window on a later apply (the cadence is 900 s): an unlanded beat is a soft landing, exactly as for inngest-consumer,
# because the first merge can precede the image that carries the probe's resolver (the unit then reports
# no_ping reason=probe_absent and, correctly, sends nothing). It arms on the first apply whose window catches a beat, and the
# post-merge check (soleur:postmerge) fails loudly on any beat still paused, so this is never a silent dark state.
ARM_WBS_DEADLINE=300
arm_wbs_soft() {  # <label> <arm_one rc>: rc 2 = the gate worked and no beat landed yet (soft); anything else non-zero is a real failure
  if [[ "$2" -eq 2 ]]; then
    echo "::warning::${1}: no beat within ${ARM_WBS_DEADLINE}s (elapsed ${ARM_ELAPSED}s); monitor rolled back to paused. Better Stack reported status=${ARM_LAST_STATUS:-unknown} at rollback. The runtime Bash synthetic pings every 15 minutes, and until the web image carrying the probe's resolver is running the unit sends no ping by design (journal: reason=probe_absent), so on the first apply this warning is expected. It arms on the first apply whose window catches a beat; soleur:postmerge verifies it."
  elif [[ "$2" -ne 0 ]]; then
    rc=1
  fi
}
wrc=0
arm_one 'betteruptime_heartbeat.web_bash_synthetic["web-1"]' 'web-bash-synthetic (web-1)' "$ARM_WBS_DEADLINE" || wrc=$?
arm_wbs_soft 'web-bash-synthetic (web-1)' "$wrc"
wrc=0
arm_one 'betteruptime_heartbeat.web_bash_synthetic["web-2"]' 'web-bash-synthetic (web-2)' "$ARM_WBS_DEADLINE" || wrc=$?
arm_wbs_soft 'web-bash-synthetic (web-2)' "$wrc"

# (#7228/#7587) inngest-consumer — the ONE caller that distinguishes rc=2 (see arm_one's
# terminal branch), and the ONE arm whose deadline deliberately departs from period+grace−40.
#
# Its feeder is inngest-consumer-probe.sh on web-1, which pings only after reading a NON-EMPTY
# function registry out of 10.0.1.40:8288. That host has not bound :8288 since 2026-07-30, and
# THIS CHANGE DOES NOT FIX THAT — the fix needs `apply_target=inngest-host-replace` plus a
# cutover window (#7462), so the probe is correctly SUPPRESSING and no beat can land.
#
# 230 → 30. Measured on run 32360734255: the five healthy arms complete in ~0.6 s of wall clock
# while this one arm burns ~235 s, which was 98.8% of the ARM step and 78.5% of the whole apply
# job, on EVERY merge. 30 s costs nothing on the happy path (a healthy arm answers in ~0.2 s)
# and it preserves the self-clearing property a short-circuit would destroy: arm_one still
# attempts the measurement every apply and returns 0 via `already armed (status=…)` the first
# time the monitor is live-up, so nothing here can outlive #7228 and there is no expiry
# mechanism to rot.
#
# THE COST, OWNED RATHER THAN BURIED, INCLUDING THE TAIL (#7657 D7). With a 180 s feeder period
# against a 30 s window, an attempt catches the first beat with p = 30/180 = 1/6, and attempts
# are independent, so the number of applies to arm is geometric. At the measured 2.71
# merge-applies/day: MEAN 6 attempts ≈ 2.2 days, MEDIAN 1.5 days, **p95 17 attempts ≈ 6.3 days**,
# p99 ≈ 9.6 days, and **P(still unarmed after 2 days) = (5/6)^5.4 ≈ 37 %**. Quoting only the mean
# of a geometric buries the half that matters. It was paused every day of the incident, so this
# is not a new dark state, but it IS a multi-day blind window rather than a same-apply re-arm.
# UNVERIFIED rider: p = 1/6 assumes Better Stack's `status` flips to `up` the moment a beat is
# received. If propagation lags by L, effective p is (30 − L)/180 — at L = 10 s that is 1/9, mean
# 3.3 d, p95 9.4 d. This change measured no such semantics.
#
# The unpause window stays far below the monitor's first absence alert: worst case is
# 30 + ARM_POLL_INTERVAL_S + 2 × ARM_CURL_MAX_TIME_S = 70 s against period+grace = 240 s, so no
# false page is possible during a failed attempt.
ARM_INNGEST_DEADLINE=30
arc=0
arm_one 'betteruptime_heartbeat.inngest_consumer' 'inngest-consumer (web-1)' "$ARM_INNGEST_DEADLINE" || arc=$?
if [[ "$arc" -eq 2 ]]; then
  # This message is NOT the pre-#7587 one, and the rewrite is the point. That text hard-coded
  # "230s", and it instructed the reader that a sighting after #7228 closes means "the probe or
  # the private-net path is broken". Against a 30 s window and a 180 s period a HEALTHY feeder
  # produces this warning roughly five runs in six, so the old instruction would send an
  # operator to debug a surface that is working. What replaces it is the status Better Stack
  # reported at rollback — the value actually observed, never a carried-forward pre-unpause
  # reading (#7658 E1), and `unknown` when the read itself failed.
  #
  # `updated_at` is reported but NOT claimed as a discriminator (#7658 E2). The retracted claim
  # was that status and updated_at together "separate 'the feeder never beat' from 'a beat was
  # simply not due inside our window'". This file's own header records the repo's verified
  # position — `updated_at` is a record-mutation timestamp and does NOT move when a beat arrives
  # while paused — and this script PATCHes that same record ~30 s before reading the field, so
  # the most plausible reading of any movement is OUR OWN unpause. Asserting a property of the
  # PAIR that we have not measured of either member is the same defect class this branch already
  # retracted once in 01ab1e3c4.
  echo "::warning::inngest-consumer: no beat within ${ARM_INNGEST_DEADLINE}s (elapsed ${ARM_ELAPSED}s); monitor rolled back to paused. Better Stack reported status=${ARM_LAST_STATUS:-unknown} at rollback (updated_at=${ARM_LAST_UPDATED_AT:-unreported}; that field is a record-mutation timestamp and this run PATCHed the record, so do not read a beat into it). This arm polls for ${ARM_INNGEST_DEADLINE}s against a 180s feeder period, so a HEALTHY feeder misses roughly five windows in six — on its own this warning is not a fault. While the 10.0.1.40 bind failure (#7228) is open no beat can land at all, so seeing this every apply is the expected reading. It arms automatically on the first apply whose window catches a beat."
elif [[ "$arc" -ne 0 ]]; then
  rc=1
fi
exit "$rc"
