#!/usr/bin/env bash
set -euo pipefail

# EXIT CONTRACT (#7424)
#   0  every registered suite passed
#   1  >= 1 suite FAILED (an assertion verdict) — failure dominates when both are present
#      ALSO 1: a suite WROTE TO THE LIVE REPOSITORY. Counted into `failed` rather than given a
#      new code, because every consumer of this runner is binary on non-zero and a fifth code
#      buys nothing; the [FATAL] line above the summary names it unambiguously. See the
#      REPO WRITE BOUNDARY blocks (#7553/#7652).
#      NOT 1: the REPORT class — an observation, never a verdict. A ref belonging to a branch
#      that `git worktree list` says is checked out in ANOTHER worktree moved during this run.
#      That is a sibling session doing its own work, not this run corrupting anything, so a
#      REPORT class increments nothing and changes no exit code — it is printed, and that is
#      the whole of its effect. It is
#      documented here because a result class the runner can produce but its own contract does
#      not describe is the same claim/check drift this boundary exists to fix (#7652).
#   3  UNRESOLVED — not measured, and NOT green. TWO producers:
#      (a) 0 failures and >= 1 suite KILLED;
#      (b) the run crossed TC_RUNTIME_CEILING_S and stopped starting suites, so
#          >= 1 suite was DECLINED and its coverage was not obtained (#7869).
#      Both mean the same thing to a consumer — coverage is incomplete and the
#      run is neither green nor a verdict about the diff — which is why (b)
#      reuses 3 rather than minting a code. It is NOT 4: 4 means nothing ran at
#      all, and a curtailed run has real results for the suites it did reach.
#      `suite_exit_class` is untouched by (b); its byte-identical parity with
#      .github/scripts/test/run-all.sh is pinned by a dedicated suite.
#      3 is a TOP-LEVEL contract only: a nested runner returning 3 into run_suite classifies
#      as a plain FAIL, because rc=3 is not signal-shaped. Do not adopt 3 in a nested runner
#      without revisiting this.
#      NOT 1 either: the UNMEASURABLE class. A boundary dimension was captured at one end of the
#      run and not the other, so its delta is meaningless — neither clean nor dirty. It is printed,
#      counted into the breakdown, and changes no exit code, because a run that could not measure
#      something must not report a verdict about it.
#   2  usage error — TEST_GROUP took an unsupported value (predates the above), OR the
#      relevance-predicate data file is missing, OR scripts/lib/repo-write-boundary.sh is missing
#      or stale (added #7652 — a gate whose boundary is undefined refuses rather than running at
#      reduced meaning), OR apps/web-platform/node_modules is absent while the webplat group is
#      selected (#8580 — the arm's suites all resolve binaries out of the app's install, so the
#      group cannot run at all; the refusal names the `npm ci` remediation). All are "this
#      runner cannot run", not a
#      verdict about any suite; ADR-181 declined a separate code because every consumer is
#      binary and a second usage-shaped code buys nothing.
#   4  REFUSED before anything ran. SIX producers. The first two are
#      overridden by SOLEUR_ALLOW_FULL_GATE=1:
#        (a) SOLEUR_SUBAGENT=1 is set — a DECLARED spawned agent;
#        (b) a sibling full-gate run is already in flight — a MEASURED condition (#7553).
#        (b) is the reachable one: nothing in this repo sets SOLEUR_SUBAGENT, so (a)'s
#        antecedent only holds when someone exports it deliberately.
#      The next two are affected-mode SELECTION refusals (#8322) — no hatch:
#        (c) AFFECTED_UNRESOLVED reason=zero-selected — the diff selects zero
#            runnable registrations, which is no gate;
#        (d) AFFECTED_UNRESOLVED reason=below-floor — the always-on set fell
#            below _MIN_ALWAYS_ON_DECLARED, meaning the index was gutted.
#      The last two are #8761's enumerate/deleted-checkout protections:
#        (e) working tree missing — a deleted cwd detected up-front, or
#            mid-walk while still in enumerate mode or before the first
#            registration (the deleted-checkout probe is mode-agnostic, but
#            once an EXECUTING battery's walk has begun it exits 3 instead — a mid-run
#            abort leaves real coverage unresolved, which is 3's shape);
#        (f) enumerate deadline — the graceful per-registration bound for the
#            enumerate family. Its hard-bound sibling is the watchdog's
#            SIGTERM/SIGKILL (143/137), which is not a runner code at all: a
#            walk that stopped advancing is killed, not refused.
#      (ADR-181). Distinct from 3 on purpose: 3 says a suite was terminated and its coverage
#      is unresolved; 4 says nothing ran, by design, and nothing is unresolved. Sharing 3
#      would make a refused run read as a killed suite.
#
# Every consumer was binary zero/non-zero BEFORE this change (lefthook, the three ci.yml
# shards, package.json, main-health-monitor.yml) and still blocks on any non-zero, so 3 is
# safe for all of them; exiting 0 on a killed suite would silently green every one.
# grok-pre-push-gate.sh is the exception THIS change creates: it now reads 3, renders
# [UNRESOLVED] instead of [FAIL], and forwards 3 — its own consumer (ship Phase 6) is binary. Note that ci.yml's
# aggregate `test` job reads `needs.<shard>.result`, whose domain is
# {success,failure,cancelled,skipped} — so the REQUIRED context cannot carry 3. CI collapses
# killed into failure, and the distinction survives in the shard log and the [KILLED] lines.

# --- Auto-discovered suite globs (the ONLY declaration; see --print-suite-globs) ---------
#
# These are the patterns the glob loop further down expands. They live HERE, in an array with
# a machine-readable accessor, for one reason: scripts/lint-orphan-test-suites.sh must diff
# `git ls-files '*.test.sh'` against what this runner actually registers, and the only safe way
# for it to know these patterns is to ASK. A second copy of the list inside the linter would
# make the linter blind to the one mutation it exists to catch — delete a pattern here and the
# suites it covered stop running while the linter, reading its own stale copy, still reports
# `orphan test suites: none` (Guard 1 row M5). Deriving turns a duplicated list into a contract.
#
# QUOTED, individually. An unquoted array literal is pathname-expanded AT ASSIGNMENT, which
# would freeze today's matches into the array and silently stop registering files added later.
#
# `plugins/soleur/skills/*/scripts/*.test.sh` is deliberately NOT here: measured, it matches
# zero tracked files (the four linear-fetch suites #7402 recorded under `scripts/` were
# `git mv`d to `.../test/` by #7482 and are covered by the `skills/*/test/` entry above it).
# A glob matching nothing is not coverage — it is a line that makes a future suite
# auto-register without anyone deciding to. The linter's orphan report is that decision point.
SUITE_GLOBS=(
  'plugins/soleur/test/*.test.sh'
  'plugins/soleur/skills/*/test/*.test.sh'
  'plugins/soleur/scripts/*.test.sh'
  '.claude/hooks/*.test.sh'
  # `.claude/hooks/lib/*.test.sh` is a separate entry because shell globs do not cross `/`:
  # the `.claude/hooks/*.test.sh` entry above never reached the lib/ subdirectory and
  # freeze-lock.test.sh had never gated CI (#7409).
  '.claude/hooks/lib/*.test.sh'
  'apps/cla-evidence/scripts/*.test.sh'
  'apps/web-platform/scripts/*.test.sh'
  'apps/web-platform/scripts/lib/*.test.sh'
  'scripts/lib/*.test.sh'
)

# Answer the linter's question and exit, BEFORE anything with a side effect: no TMPDIR export,
# no bare-repo guard, no TEST_GROUP validation (which would reject this argv as a group name and
# exit 2), no tc_acquire — the linter runs INSIDE the advisory lock this runner holds, so a code
# path that blocks on it would deadlock the gate on itself.
# Query flags are position-INDEPENDENT: `--affected --capacity` must still be
# the capacity probe, not an affected run. Scan the whole argv rather than
# pinning $1 — a mode flag before the query flag would otherwise turn a
# lock-free probe into a battery dispatch.
_query_globs=0
_query_capacity=0
for _qarg in "$@"; do
  case "$_qarg" in
    --print-suite-globs) _query_globs=1 ;;
    --capacity)          _query_capacity=1 ;;
  esac
done
unset _qarg
if (( _query_globs == 1 )); then
  printf '%s\n' "${SUITE_GLOBS[@]}"
  exit 0
fi

# Answer "can this box absorb another full gate?" and exit, under the SAME
# discipline as --print-suite-globs above: BEFORE anything with a side effect —
# no TMPDIR export, no bare-repo guard, no TEST_GROUP validation, and above all
# no tc_acquire, since a pre-launch probe that blocked on the lock would queue
# behind the very run the caller is asking whether to start (#7545).
#
# THIS IS THE DELIVERABLE FOR THE ISSUE'S TITLE. "A session cannot tell before
# launching whether the box can absorb another full gate" — it can now, in under
# a second, without running a suite or taking the lock.
#
# IT ALWAYS EXITS 0, including on a contended box. The verdict is a STATEMENT:
# it reports and the caller decides. An `exit 1` here would make every consumer
# a gate — lefthook's pre-commit hook runs this runner, so a non-zero would
# block `git commit` — and that decline was cut on measured evidence (see
# tc_capacity_line's header and the ADR-133 addendum).
#
# Sources the lib INDEPENDENTLY, because the normal source site sits below the
# bare-repo guard this branch deliberately precedes. Same defensive shape: a
# missing lib degrades to a named CAPACITY_UNKNOWN rather than to silence, so
# the answer can never simply vanish.
if (( _query_capacity == 1 )); then
  # Mirrors the pin below: the contention lib observes the /tmp TMPFS, not
  # whatever TMPDIR the caller happens to carry.
  export TC_TMPDIR="${TC_TMPDIR:-/tmp}"
  _cap_lib="$(dirname "${BASH_SOURCE[0]}")/lib/test-contention.sh"
  if [[ -f "$_cap_lib" ]]; then
    # shellcheck source=scripts/lib/test-contention.sh
    source "$_cap_lib" || true
  fi
  if declare -F tc_capacity_line >/dev/null 2>&1 && declare -F tc_preamble >/dev/null 2>&1; then
    # tc_preamble is what performs the single /proc walk and promotes its
    # readings; its own output is not wanted here, only the verdict built from
    # them. One walk, one source of truth.
    tc_preamble >/dev/null 2>&1 || true
    tc_capacity_line
    # The per-sibling detail is what makes the verdict ACTIONABLE: "contended"
    # tells you to wait, "pid 2266786 in .worktrees/feat-x, 1214s in" tells you
    # what you are waiting for.
    # The rows tc_preamble ALREADY resolved on the walk above. Calling
    # tc_siblings here was a SECOND non-atomic walk, and it produced exactly the
    # contradiction the promotion exists to prevent — reproduced on this box:
    #   CAPACITY_OK measured_siblings=0
    #     -> pid 1497146 in .../feat-one-shot-7545... (running 3s)
    #     -> pid 1497376 ...
    #     -> pid 1503142 ...
    # a verdict of "idle" printed directly above three enumerated siblings,
    # because the count came from walk #1 and the rows from walk #2 six seconds
    # later. It also doubled this branch's latency.
    _cap_rows="${TC_LAST_SIB_ROWS:-}"
    if [[ -n "${_cap_rows//[[:space:]]/}" ]]; then
      while IFS=$'\t' read -r _cp _cc _ce; do
        [[ -n "$_cp" ]] || continue
        printf '[contention]   -> pid %s in %s (running %ss)\n' "$_cp" "$_cc" "$_ce"
      done <<< "$_cap_rows"
    fi
  else
    echo '[contention] BANNER CAPACITY_UNKNOWN reason=lib_unavailable'
  fi
  exit 0
fi

# --- Shard partition: --enumerate and SCRIPTS_SHARD (#7902) --------------------------------
#
# Parsed HERE, under the same discipline as --print-suite-globs and --capacity above: BEFORE
# the TMPDIR export, the bare-repo guard, TEST_GROUP validation, and above all before
# tc_acquire. The shard-totality guard invokes this runner once per leg to enumerate that
# leg's ASSIGNED registrations, and it runs INSIDE the advisory lock a real gate run holds —
# so an enumerate path that blocked on that lock would deadlock the gate on itself, exactly as
# the --print-suite-globs path would.
#
# --enumerate is SHIFTED off argv so the group is still read positionally below
# (`bash scripts/test-all.sh --enumerate scripts`), keeping one argv convention.
_ENUMERATE=0
_EMIT_COMMANDS=0

# --- Mode flags (#8322) ------------------------------------------------------
#
# --affected   THE LOCAL DEFAULT. Run the suites this diff can move plus every
#              declared always-on ratchet; decline the rest as not-affected.
#              Honest scope note: affected+ratchets does NOT exercise
#              suite×suite interaction — the backstop for that class is CI's
#              sharded full battery (the required `test` context), not any
#              local run. A green affected run is not a full-coverage claim.
# --full       The whole battery — what CI runs. Refused under SOLEUR_SUBAGENT=1
#              or measured sibling contention unless SOLEUR_ALLOW_FULL_GATE=1.
# --print-affected-set   Enumerate-shaped plumbing: walks every registration and
#              emits AFFECTED_CLASS\t<label>\t<class> receipts, runs nothing.
#
# Parsed as a WHILE-LOOP over leading flags, replacing the $1-only if/elif that
# predated the mode flags — `--enumerate-commands --affected scripts` composes.
# An unknown `--flag` is NOT consumed: it falls through to the TEST_GROUP
# positional below and dies on validation — fail-closed, unchanged.
_AFFECTED_REQ=0        # --affected (or --print-affected-set) named explicitly
_FULL_REQ=0            # --full named explicitly
_PRINT_AFFECTED=0
# Wall-clock bound for the enumerate family (#8761). Overridable by
# SOLEUR_ENUM_DEADLINE_S (digits only, else the default holds); the deadline is
# a safety bound on a seconds-scale walk, not a performance assertion — a clean
# walk measures ~35s, a loaded host has taken >300s, so the default sits well
# above either while still capping the multi-hour incident class.
_ENUM_DEADLINE_S=900
while [[ "${1:-}" == --* ]]; do
  case "$1" in
    --enumerate)
      _ENUMERATE=1
      ;;
    --enumerate-commands)
      # --enumerate-commands publishes the COMMAND each registration would run, not just its
      # label. It raises the enumerate flag as WELL as its own, deliberately: conditionals in
      # this file gate on `_ENUMERATE`, and one of them is the entire "takes no lock" property.
      # The mechanism is worth stating precisely, because the obvious reading is wrong: `tc_acquire`
      # is NOT skipped. It is called unconditionally; the gated line sets
      # SOLEUR_DISABLE_SESSION_STATE=1, and `scripts/lib/test-contention.sh` returns early on that
      # without serialising. The OUTCOME — this path cannot deadlock a gate run that already holds
      # the lock — is what matters and is unchanged. A mode that set only its own flag would take
      # the lock and reintroduce the deadlock `--enumerate` exists to avoid, so the two flags are
      # not independent and must not be made so.
      #
      # RECORD CONTRACT. This mode emits two record types, both TAB-delimited, one per line. It does
      # NOT own the whole stream: unrelated preamble lines reach stdout too (measured — the orphan
      # reaper's `ORPHAN_SCAN valid=1 …` line, space-delimited, emitted before any registration). A
      # consumer MUST select by record prefix rather than assume every line is a record; the guard
      # does exactly that. An earlier revision of this comment said "two record types, one per line"
      # full stop, which would have misled the next consumer into a strict parse.
      #   SUITE_COMMAND\t<label>\t<argv0>\t<argv1>...   — from run_suite; fields 3..N are the
      #                                                    exact argv the runner would exec.
      #   SUITE_COMMAND_DECLINED\t<label>\t<rerun>       — from skip_suite; field 3 is a HUMAN
      #                                                    DISPLAY string, never argv. The two
      #                                                    types are distinct precisely so a
      #                                                    consumer cannot parse a display string
      #                                                    as a command.
      # ESCAPING: none. A TAB or NEWLINE inside an argv element would corrupt the record, so the
      # emitter REFUSES rather than emitting a corrupt line (fail closed, exit 2). No registration
      # in this file carries such an element today; if one ever does, the consumer must learn a
      # real encoding rather than the emitter silently mangling it.
      _ENUMERATE=1
      _EMIT_COMMANDS=1
      ;;
    --affected)
      _AFFECTED_REQ=1
      ;;
    --full)
      _FULL_REQ=1
      ;;
    --print-affected-set)
      # Plumbing, not an early exit: it RAISES enumerate so the walk below emits
      # receipts without running a suite, and terminates at the enumerate exit.
      _PRINT_AFFECTED=1
      _AFFECTED_REQ=1
      _ENUMERATE=1
      ;;
    --help)
      cat <<'USAGE'
Usage: bash scripts/test-all.sh [flags] [all|webplat|bun|scripts|infra]
   or: TEST_GROUP=<value> bash scripts/test-all.sh [flags]

Modes (local default is --affected; CI always runs the full battery):
  --affected            run the suites this diff can move, plus every always-on
                        repo-global ratchet. Exempt from the full-gate refusals.
  --full                the whole battery. Refused under SOLEUR_SUBAGENT=1 or
                        measured sibling contention unless SOLEUR_ALLOW_FULL_GATE=1.
  --print-affected-set  emit AFFECTED_CLASS receipts per registration; runs nothing.
  --enumerate           emit the leg's assigned registration labels; runs nothing.
  --enumerate-commands  emit each registration's argv as SUITE_COMMAND records.
  --capacity            report whether the box can absorb another full gate.
  --print-suite-globs   print the registration glob list.
  --help                this text.

Recovery levers: --full (explicit), SOLEUR_TEST_FORCE_ALL=1 (legacy spelling of
the same intent), SOLEUR_ALLOW_FULL_GATE=1 (names a refusal you mean to bypass).

Enumerate modes die at a hard wall-clock deadline — SOLEUR_ENUM_DEADLINE_S
seconds (default 900); a deleted-cwd walk exits 4, it never spins.
USAGE
      exit 0
      ;;
    *)
      break
      ;;
  esac
  shift
done
if (( _AFFECTED_REQ == 1 && _FULL_REQ == 1 )); then
  echo "ERROR: --affected and --full are mutually exclusive." >&2
  exit 2
fi
if (( $# > 1 )); then
  echo "ERROR: at most one TEST_GROUP positional is accepted (got: $*)." >&2
  exit 2
fi

# Mode resolution. --full raises _FULL_GATE, which arms _diff_touches's
# always-true arm AND the infra registration's run conjunct — an explicit ask
# for the whole battery includes infra.
#
# SOLEUR_TEST_FORCE_ALL is deliberately NOT wired to _FULL_GATE: it is the
# older, narrower "force the relevance gates" spelling, and runner-SUT
# fixtures lean on exactly that narrowness (test-all-infra-coverage-notice
# sets it to pin the relevance-gated batteries ON while it moves ONLY the
# infra variable — a FORCE_ALL that also force-ran infra would collapse the
# very distinction that suite isolates). Under affected mode FORCE_ALL still
# degrades to a full selection via the force-all fallback below; only the
# infra conjunct stays exclusively --full's.
_FULL_GATE=0
if (( _FULL_REQ == 1 )); then
  _FULL_GATE=1
fi
_AFFECTED=0
# TEST_GROUP=affected is a DISTINCT selector (#8591): naming it must never also
# arm this axis, or a heuristic-scoped run would silently also carry #8322's
# pre-pass, decline path and degraded-full recheck. The positional group is
# still $1 here (TEST_GROUP resolves below); computing the effective group
# early keeps the two selectors disjoint by construction.
_aff_group_req="${TEST_GROUP:-${1:-all}}"
if [[ "$_aff_group_req" != "affected" ]] \
  && { (( _AFFECTED_REQ == 1 )) || { [[ -z "${CI:-}" ]] && (( _FULL_GATE == 0 )); }; }; then
  _AFFECTED=1
fi

# SCRIPTS_SHARD=k/N partitions the group across CI matrix legs.
#
# UNSET runs the full group. SET-BUT-MALFORMED — including empty or whitespace-only — FAILS
# CLOSED with exit 2, following the TEST_GROUP validation precedent below.
#
# The unset-vs-set-empty distinction is deliberate and is the SAFE direction.
# `SCRIPTS_SHARD: ${{ matrix.shard }}` always resolves to a non-empty value, so an EMPTY value
# under CI means the interpolation broke — a renamed matrix key, a dropped `env:`. Treating
# that as "unset" would make the leg silently re-run the WHOLE group and report green, which
# is the "a leg lost its env" failure this partition must not have. Falling back to running
# NOTHING would be worse still: a required check green over zero coverage.
#
# `${SCRIPTS_SHARD+x}`, not `${SCRIPTS_SHARD:-}`, is what distinguishes unset from set-empty.
_SHARD_K=0
_SHARD_N=0
if [[ -n "${SCRIPTS_SHARD+x}" ]]; then
  _shard_raw="${SCRIPTS_SHARD//[[:space:]]/}"
  # The digits are ENUMERATED rather than ranged, and bounded to 9, for two measured reasons.
  #
  # (a) `[0-9]` inside `[[ =~ ]]` is COLLATION-dependent: under en_US.UTF-8 it matches U+FF11
  #     FULLWIDTH DIGIT ONE. `10#１` is then a fatal arithmetic-expansion error, and bash aborts
  #     the enclosing `if…fi` compound and RESUMES AFTER `fi` with status 0 — `set -uo pipefail`
  #     does not fire, the range check below never runs, and _SHARD_K/_SHARD_N keep their initial
  #     0, which `_shard_selects` reads as "not sharding" and runs the FULL group. Measured:
  #     a fullwidth-digit spec printed `k/N=0/0` and assigned all 375 registrations. A validator
  #     whose whole contract is `exit 2` must not have a fall-through, even a safe-direction one.
  #     An explicit `[0123456789]` cannot be widened by collation; `LC_ALL=C` is NOT usable here
  #     because `[[` is a shell keyword, not a command, so it takes no env prefix.
  # (b) an unbounded run overflows 64-bit: `10#99999999999999999999` wraps, so `1 <= k <= N`
  #     holds for a pair that matches no ordinal.
  if [[ ! "$_shard_raw" =~ ^([0123456789]{1,9})/([0123456789]{1,9})$ ]]; then
    echo "ERROR: SCRIPTS_SHARD must be k/N with 1 <= k <= N (got: '${SCRIPTS_SHARD}')." >&2
    echo "       Unset it to run the full group. A malformed value is never inferred: it fails" >&2
    echo "       closed rather than silently running everything or nothing." >&2
    exit 2
  fi
  _SHARD_K=$(( 10#${BASH_REMATCH[1]} ))
  _SHARD_N=$(( 10#${BASH_REMATCH[2]} ))
  if (( _SHARD_N < 1 || _SHARD_K < 1 || _SHARD_K > _SHARD_N )); then
    echo "ERROR: SCRIPTS_SHARD must be k/N with 1 <= k <= N (got: '${SCRIPTS_SHARD}')." >&2
    echo "       Unset it to run the full group. A malformed value is never inferred: it fails" >&2
    echo "       closed rather than silently running everything or nothing." >&2
    exit 2
  fi
  # Echoed so a leg's resolved assignment is readable in its own CI log, and so the guard can
  # assert N DISTINCT values across N legs — which is what detects a leg that lost its env.
  echo "[shard] SCRIPTS_SHARD resolved k/N = ${_SHARD_K}/${_SHARD_N}"
fi

# Default TMPDIR to /var/tmp (disk-backed) rather than /tmp.
#
# /tmp on this machine class is a ~4 GiB SHARED tmpfs, and parallel worktrees are this
# repo's documented workflow — so two concurrent runs compete for the same RAM-backed
# capacity. The observed failure is a suite TIMEOUT that reads exactly like a real
# regression (documented in-repo for skill-security-scan #4096 and vitest.config.ts
# #3817/#4128), plus abandoned sibling scratch dirs that produced a false RED and a
# blocked tool-output failure. Six separate places in the repo currently DOCUMENT the
# workaround "run with TMPDIR=/var/tmp"; setting it here removes the footgun instead of
# documenting it a seventh time.
#
# Respects an explicit caller value — CI or an operator pinning TMPDIR keeps it.
export TMPDIR="${TMPDIR:-/var/tmp}"

# Session scratch root (#7004): allocate <base>/soleur-run.<pid>.XXXXXXXX under
# the effective TMPDIR's base, export TMPDIR at it so every descendant mktemp
# lands inside the session root, and write .soleur-owned so Reaper 3 and the
# session-start sweep can reclaim a dead run's residue without name heuristics.
# Sourced opportunistically — a missing lib degrades to the pre-#7004 shape,
# never blocks the gate. The EXIT trap at the acquire site gains
# `_soleur_scratch_cleanup` (spliced, not a second trap — ADR-129).
_SCRATCH_LIB="$(dirname "${BASH_SOURCE[0]}")/lib/scratch-root.sh"
if [[ -f "$_SCRATCH_LIB" ]]; then
  # shellcheck source=scripts/lib/scratch-root.sh
  source "$_SCRATCH_LIB" || true
fi
if declare -F soleur_scratch_session_begin >/dev/null 2>&1; then
  soleur_scratch_session_begin "$TMPDIR" || true
fi
declare -F _soleur_scratch_cleanup >/dev/null 2>&1 || _soleur_scratch_cleanup() { :; }

# Pin the #6789 contention instrumentation to /tmp, INDEPENDENTLY of TMPDIR above.
#
# test-contention.sh binds `TC_TMPDIR="${TC_TMPDIR:-${TMPDIR:-/tmp}}"` at SOURCE time, so
# without this line the TMPDIR default above silently repoints it at /var/tmp. That is
# fail-open in the worst way: the lib exists to observe headroom on the /tmp TMPFS, and
# /var/tmp is disk-backed with hundreds of GB free, so every reading would come back
# healthy while the mount it was built to watch went unobserved. Instrumentation aimed at
# the wrong mount is indistinguishable from a healthy mount.
#
# The two settings are deliberately separate and must stay that way (see the
# "RELATIONSHIP TO test-contention.sh" section of scripts/lib/scratch-root.sh): suites get
# a disk-backed scratch dir, the janitor keeps watching the tmpfs.
export TC_TMPDIR="${TC_TMPDIR:-/tmp}"

# Sequential test runner that isolates test suites to avoid Bun's FPE crash
# when running all tests via recursive directory discovery.
# See: knowledge-base/project/learnings/2026-03-20-bun-fpe-spawn-count-sensitivity.md
#
# Per-suite timing: when TEST_TIMING_LOG is set to a writable path, each
# run_suite() invocation appends "<label>\t<elapsed_ms>[\tFAIL|\tKILLED]" to that
# path. Field 3 carries the result class for any non-passing suite; KILLED means
# signal-shaped and UNRESOLVED, not failed (#7424).
# Elapsed time uses bash 5.0+ EPOCHREALTIME (microsecond precision, no
# coreutils dependency, portable across Linux + Homebrew bash on macOS).
# CI runs ubuntu-latest (bash 5.x). macOS default /bin/bash is 3.2 — install
# bash 5 from Homebrew if you need timing locally; otherwise EPOCHREALTIME is
# unset and elapsed_ms computes 0 silently.
#
# Both reads below are `${EPOCHREALTIME:-}`, never bare. This file runs under
# `set -euo pipefail` (line 2), so a BARE read on a shell without the variable
# is an unbound-variable ABORT in run_suite — the runner would die on its FIRST
# suite with no summary, no rc file and no [FAIL], which is exactly the shape
# work/SKILL.md's triage table attributes to a harness REAP, sending the
# operator into a relaunch loop that reproduces it forever. The `*.*` guard
# below only works if the read reaches it. (#7484 review; the same class was
# found and fixed in scripts/lib/test-contention.sh.)

# --- Version Check ---
# Gated on bun being installed so the script runs cleanly in a bun-free
# environment. The parenthetical here used to read "TEST_GROUP=scripts in CI
# omits setup-bun by design"; that is FALSE and has been since #7566 (verified
# 2026-09-17: ci.yml's test-scripts job runs `oven-sh/setup-bun` and names its
# step "bash + python3 + bun"). ci.yml corrected its own copy of the claim
# in-place — "`setup-bun` IS required (#7332)" — and this twin was never swept,
# so the stale sentence survived precisely where a reader of THIS file would
# look. CI is bun-BEARING; the gate below still matters because a developer host
# need not be, and because `command -v` answers a different question either way.
# The node point is unchanged and still true: the scripts shard needs no node
# *version pin* — it uses stock ubuntu-latest node, unpinned, for the one
# `node --test` suite below.
#
# `command -v bun` is NOT a sufficient test for "bun works", and the difference is not cosmetic.
# A version-manager SHIM resolves on PATH while being unable to run: a `mise` shim with no
# version pinned prints `mise ERROR No version is set for shim: bun` to stderr and exits
# non-zero. This file is `set -euo pipefail` (line 2), so the bare `actual=$(bun --version)` was
# an ABORT rather than a skipped check — and it sits ABOVE every registration emit, so the
# observable failure was not a missing warning. It was EVERY invocation of this runner exiting
# rc 1 having emitted nothing, on a host where nothing about the battery was wrong.
#
# WHAT THAT BREAKS. Two consumers fail closed on the `--enumerate` record stream and go red for
# a cause neither can name: `scripts/battery-tag-authorship.test.sh` › the `--enumerate-commands`
# root-set guard (rc AND count) and `plugins/soleur/test/scripts-shard-totality.test.sh` ›
# `enumerate_leg()` (each call runs as a background child whose rc the guard captures via
# per-pid `wait` — a dead child fails its leg row loudly).
# `scripts/lint-orphan-test-suites.sh` › the `--print-suite-globs` derivation is the same
# fail-closed shape on the SIBLING stream and the same prologue window.
#
# SCOPE, stated narrowly on purpose. This guards ONE tool. The prologue above the first
# registration emit still aborts rc-1-with-zero-records if `tr`, `dirname`, `mktemp` or `mkdir`
# fails, and the `dirname` sites do it with no runner-authored stderr at all. `command v as a
# liveness claim` is a repo-wide class (tracked separately); do not read this block as closing
# it. `scripts/orphan-process-reaper.sh` › the `logger` guard is the in-repo reference shape.
#
# The DEGRADED case is reported rather than silently swallowed, and the report carries the exit
# status instead of asserting a cause this code never measured: 126 is a bad interpreter, 127 a
# binary that vanished between `command -v` and the call, 1 a shim refusing. `timeout` and the
# `||` arm are BOTH load-bearing and cover different failures — see the same argument made for
# `crane` further down this file; `|| actual=""` covers a non-zero exit and cannot rescue a shim
# that never returns (a version manager may go to the network to install a missing runtime).
#
# Pinned by scripts/test-all-enumerate-toolchain.test.sh, whose R5 row is what stops this from
# being "fixed" by deleting the check. (#8231)
if [[ -f .bun-version ]]; then
  # `tr` gets the same treatment as `bun` below, for the same reason and one line earlier: a
  # bare command substitution here is an ABORT under `set -e`, above every registration emit.
  expected=$(tr -d '[:space:]' < .bun-version) || expected=""
fi
if [[ -n "${expected:-}" ]] && command -v bun >/dev/null 2>&1; then
  _bun_rc=0
  actual=$(timeout 10 bun --version 2>/dev/null) || _bun_rc=$?
  # Normalise the COMMAND's output, not just the file's: a shim emitting CRLF or a banner line
  # otherwise compares unequal to a byte-identical pinned version and this block emits
  # `Bun 1.3.14 installed, expected 1.3.14` — a warning that contradicts itself.
  actual=$(printf '%s' "${actual:-}" | tr -d '[:space:]') || actual=""
  if [[ -z "$actual" ]]; then
    echo "WARNING: 'bun --version' produced no version (exit ${_bun_rc}); skipping the version check" >&2
  elif [[ "$actual" != "$expected" ]]; then
    # %q, not raw: $actual is PATH-controlled, and a shim can otherwise emit control characters
    # or U+2028 and forge a line shaped like this runner's own status output into a CI log.
    printf 'WARNING: Bun %q installed, expected %q (from .bun-version)\n' "$actual" "$expected" >&2
    echo "Run: bun upgrade" >&2
  fi
fi

# --- Git Hook Isolation ---
# When invoked as a lefthook pre-commit hook, git sets GIT_DIR, GIT_INDEX_FILE,
# and GIT_WORK_TREE in the environment. These override GIT_CEILING_DIRECTORIES
# and cause test-spawned git commands to operate on the parent repo instead of
# their temp directories. Unsetting them restores normal git discovery behavior.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_TEMPLATE_DIR GIT_EXEC_PATH
# Incident-telemetry sandbox belt (#7853). The five chokepoints already export this; a runner is the
# outer boundary, so it sets a default for anything they do not reach -- a suite invoked from a
# third cwd, or one whose runtime loads no preload.
#
# Fail-loud, and both conditions matter. An UNSET root is not a degraded sandbox:
# _incidents_repo_root() walks up to the operator real .claude/.rule-incidents.jsonl. An EMPTY value
# reads as unset to that same function while still looking "set" to any static check for the
# variable name, which is the shape that let two previous per-call-site sweeps report clean while
# they leaked.
# Validate an INHERITED root too, not only one we mint. `[ -z ]` alone lets a NON-ABSOLUTE value
# through, and `_incidents_repo_root()` returns any non-empty value verbatim -- so
# `INCIDENTS_REPO_ROOT=.` resolves to `./.claude/.rule-incidents.jsonl` against the HOOK's cwd,
# i.e. the operator's real ledger for any hook spawned at the checkout root, while every static
# check for the variable's name reports it set. The TS and Python siblings both require an
# absolute path; these shell arms did not.
case "${INCIDENTS_REPO_ROOT:-}" in
  /?*) : ;;                       # absolute inherited root: honour it
  "")  _soleur_inc_sb="$(mktemp -d -t soleur-inc-XXXXXX 2>&1)" || {
         printf "FATAL: could not create an incident-telemetry sandbox: %s\n" "${_soleur_inc_sb}" >&2
         printf "  Refusing to run: an unset INCIDENTS_REPO_ROOT points test telemetry at the\n" >&2
         printf "  operator real .claude/.rule-incidents.jsonl. Check free space on %s.\n" \
           "${TMPDIR:-/tmp}" >&2
         exit 1
       }
       case "${_soleur_inc_sb:-}" in
         /?*) : ;;
         *)   printf "FATAL: mktemp produced a non-absolute sandbox path: %s\n" \
                "${_soleur_inc_sb:-<empty>}" >&2; exit 1 ;;
       esac
       # FAIL LOUD, not `|| true`. `emit_incident` drops a row without a sentinel when its parent
       # dir is missing, so on a full tmpfs every test emit would be silently discarded and any
       # suite asserting on telemetry would fail for an unrelated-looking reason.
       mkdir -p "$_soleur_inc_sb/.claude" || {
         printf "FATAL: could not create %s/.claude\n" "$_soleur_inc_sb" >&2; exit 1
       }
       export INCIDENTS_REPO_ROOT="$_soleur_inc_sb"
       export SOLEUR_TEST_INCIDENT_ROOT="$_soleur_inc_sb"
       _soleur_inc_owned="$_soleur_inc_sb"
       unset _soleur_inc_sb ;;
  *)   printf "FATAL: inherited INCIDENTS_REPO_ROOT is not absolute: %s\n" \
         "$INCIDENTS_REPO_ROOT" >&2
       printf "  A relative root resolves against each hook's cwd, which for a hook spawned at\n" >&2
       printf "  the checkout root IS the operator's real ledger.\n" >&2
       exit 1 ;;
esac

# --- Bare Repo Guard ---
# Bare repos contain stale working-tree files that diverge from HEAD.
# Running tests from a bare root produces phantom failures.
# Use a worktree instead: cd .worktrees/<name> && bash ../../scripts/test-all.sh
if git rev-parse --is-bare-repository 2>/dev/null | grep -q true; then
  echo "ERROR: Cannot run tests from a bare repository root." >&2
  echo "Stale files at the bare root diverge from HEAD and produce phantom test failures." >&2
  echo "Run from a worktree instead: cd .worktrees/<name> && bash ../../scripts/test-all.sh" >&2
  exit 1
fi

# --- Deleted-checkout guard (#8761) -------------------------------------------
# A run whose cwd is deleted — before launch or mid-walk — must fail fast with a
# named error, never spin and never complete `exit 0` over a truncated receipt
# set (two `test-all.sh` processes spun ~97% CPU for ~5h on a deleted worktree).
# The probe is PATH-based on purpose: `[[ -e . ]]`/`[[ -d . ]]`/`stat .` stay
# TRUE on a deleted-but-open cwd (fd-relative stat resolves the retained inode);
# `[[ -d "$PWD" ]]` resolves the path and fails. Emitted to
# stderr AND stdout: an operator-protection signal must reach the harness's
# captured stdout, and the receipt stream is prefix-keyed so a non-record line
# is contract-tolerated. `exit` not `return`: the `_shard_selects` call sites
# are `|| return 0`, so a return is swallowed as non-selection. Residual edge:
# a deleted-then-RECREATED same-path directory keeps `[[ -d "$PWD" ]]` true —
# accepted; the incident shape is a removal that stays removed.
_wt_missing_die() {
  echo "ERROR: working tree missing (deleted worktree?)" >&2
  echo "ERROR: working tree missing (deleted worktree?)"
  # 4 when nothing could have run — enumerate mode executes nothing by
  # definition, and before the first registration in any mode; 3 once the
  # walk has begun in an executing battery, because a mid-run cwd loss leaves
  # coverage unresolved — the contract's 3-shape, not a refusal.
  if (( _ENUMERATE == 1 || ${_shard_ordinal:-0} == 0 )); then exit 4; else exit 3; fi
}
# NOT gated on `git rev-parse --show-toplevel`: a LIVE non-git cwd is a
# legitimate degraded run (test-all-group-affected's undeterminable-diff arms
# require fail-open there); only the path being gone is the refusal condition.
if [[ ! -d "$PWD" ]]; then
  # _soleur_inc_cleanup is not yet defined and the EXIT trap is not yet
  # armed — a refusal here would leak the minted soleur-inc-* sandbox.
  [[ -n "${_soleur_inc_owned:-}" && "$_soleur_inc_owned" == /* ]]     && rm -rf "$_soleur_inc_owned"
  _wt_missing_die
fi
# `10#` and `> 0` mirror the TC_RUNTIME_CEILING_S parse (same file): a bare
# `=~ ^[0-9]+$` accepts `08` (octal literal → `(( ))` errors on it per
# registration, silently killing the graceful layer) and `0` (fires the
# watchdog instantly on every enumerate run). Non-numeric or zero falls back
# to the default — the deadline is the fix, it cannot be disabled.
if [[ "${SOLEUR_ENUM_DEADLINE_S:-}" =~ ^[0123456789]{1,9}$ ]] && (( 10#$SOLEUR_ENUM_DEADLINE_S > 0 )); then
  _ENUM_DEADLINE_S=$(( 10#$SOLEUR_ENUM_DEADLINE_S ))
fi

# --- Enumerate watchdog (#8761) ----------------------------------------------
# The enumerate/print path answers to record-consumers and previously had NO
# wall-clock bound: a run holding a deleted cwd spun ~97% CPU for ~5h on two
# cores. The per-registration deadline in _shard_selects is the graceful first
# line; this subshell is the HARD bound — it ends the run even when control
# flow never advances (a pure-compute spin inside one loop iteration, the
# un-located incident-site class). Pure bash (sleep + kill): timeout(1) is
# absent on stock macOS; the bounded-wait precedent is lib/test-contention.sh's
# _tc_wait_heartbeat's tracked-sleep pattern. Armed HERE — before the preamble
# and the walk, so a wedge anywhere in the enumerate run is bounded; exits
# before the EXIT trap installs rely on the kill -0 poll (~1s) for disarm.
# Residual: flag-parse, the bare-repo rev-parse and the INCIDENTS mktemp sit
# above this line — bounded code, but a wedged-fs hang there is uncovered.
# Disarmed at the single enumerate terminator ([shard] enumerate complete)
# and from the EXIT trap (_enum_wd_disarm) — a terminator-only disarm would
# leak the subshell past _wt_missing_die's exit, this fix's primary path.
#
# DISARM MUST KILL THE WATCHDOG'S CHILD TOO: the sleep inherits the runner's
# stdout, so when a consumer reads the run through $( ) or a pipe, a killed
# subshell whose sleep survives orphaned keeps the write end open and the
# reader blocks for the rest of the deadline — the same "process gone, consumer
# still waits" shape this issue is about. The subshell's TERM trap kills the
# tracked sleep before exiting. The 1s granularity doubles as a parent-liveness
# poll: `kill -0` each iteration exits the watchdog within ~1s of an
# untrappable parent death (SIGKILL/OOM runs no EXIT trap, no disarm), and the
# lstart identity comparison at fire time closes pid-reuse on the kill target.
if (( _ENUMERATE == 1 )); then
  _ENUM_TOP_PID=$$
  _ENUM_TOP_LSTART="$(ps -o lstart= -p $$ 2>/dev/null)"
  _ENUM_T0=$SECONDS
  (
    _wd_sleep=""
    # $BASHPID is bash 4.0+; the runner targets bash 3.2 (stock macOS), where
    # under set -u a bare $BASHPID aborts the sweep before the parent's TERM.
    # A nested shell's $PPID IS this subshell's pid — the portable spelling.
    _wd_self="$(bash -c 'echo "$PPID"')"
    trap '[[ -n "$_wd_sleep" ]] && kill -TERM "$_wd_sleep" 2>/dev/null; exit 0' TERM
    # SIGPIPE must not kill the watchdog mid-fire: the consumer's read end is
    # often already gone on the path that most needs the kill. printf under
    # this trap fails with EPIPE (rc>0) instead of dying.
    trap '' PIPE
    _wd_end=$(( SECONDS + _ENUM_DEADLINE_S ))
    # kill -0 alone answers true for an UNREAPED ZOMBIE parent — the stat
    # check treats a zombie as dead so the poll exits instead of waiting out
    # the deadline on a corpse (ps absent -> empty -> falls back to kill -0).
    while kill -0 "$_ENUM_TOP_PID" 2>/dev/null \
      && [[ "$(ps -o stat= -p "$_ENUM_TOP_PID" 2>/dev/null)" != Z* ]] \
      && (( SECONDS < _wd_end )); do
      sleep 1 & _wd_sleep=$!
      wait "$_wd_sleep" 2>/dev/null || true
    done
    # The loop exits EITHER on deadline or on parent death — an untrappable
    # parent death (SIGKILL/OOM runs no EXIT trap, no disarm) releases the
    # consumer's pipe here instead of holding it to the deadline.
    if (( SECONDS >= _wd_end )) && kill -0 "$_ENUM_TOP_PID" 2>/dev/null; then
      # Identity before kill: a pid recycled after the parent's death must
      # never take the signal. Fire iff the captured start-time matches; if
      # no baseline was captured (ps absent at arm) or the fire-time read is
      # empty (pid dead or ps broke), fire anyway — the deadline is the
      # contract, and kill on a dead pid is a harmless ESRCH.
      _wd_now="$(ps -o lstart= -p "$_ENUM_TOP_PID" 2>/dev/null)"
      if [[ -z "$_ENUM_TOP_LSTART" || -z "$_wd_now" \
          || "$_wd_now" == "$_ENUM_TOP_LSTART" ]]; then
        # Kill the walk's IN-FLIGHT CHILDREN first: a wedged git/grep child
        # keeps burning CPU AND holds the inherited receipt pipe open — the
        # same gone-but-held shape this issue is about. Direct children only
        # (pgrep -P); the runner shares the caller's process group, so a
        # group kill would take the caller with it. $BASHPID is THIS subshell
        # — it is itself a direct child of the runner and must be excluded,
        # or the sweep self-terminates before the parent's TERM is sent.
        # Snapshot the child list ONCE: after the parent dies they reparent
        # to init and a second pgrep -P enumerates nothing — a TERM-ignoring
        # wedged child would survive the KILL leg and hold the receipt pipe.
        _wd_kids="$(pgrep -P "$_ENUM_TOP_PID" 2>/dev/null || true)"
        for _wd_kid in $_wd_kids; do
          [[ "$_wd_kid" == "$_wd_self" ]] && continue
          kill -TERM "$_wd_kid" 2>/dev/null || true
        done
        kill -TERM "$_ENUM_TOP_PID" 2>/dev/null || true
        printf 'ERROR: enumerate deadline exceeded (%ss) — terminating the walk (override: SOLEUR_ENUM_DEADLINE_S)\n' "$_ENUM_DEADLINE_S" >&2 || true
        printf 'ERROR: enumerate deadline exceeded (%ss) — terminating the walk (override: SOLEUR_ENUM_DEADLINE_S)\n' "$_ENUM_DEADLINE_S" || true
        sleep 5 & _wd_sleep=$!
        wait "$_wd_sleep" 2>/dev/null || true
        kill -KILL "$_ENUM_TOP_PID" 2>/dev/null || true
        for _wd_kid in $_wd_kids; do
          [[ "$_wd_kid" == "$_wd_self" ]] && continue
          kill -KILL "$_wd_kid" 2>/dev/null || true
        done
      fi
    fi
  ) &
  _ENUM_WD_PID=$!
fi

# --- Contention instrumentation (#6789) ---
# Observe-only: /tmp headroom, sibling test-all.sh runs resolved to their
# worktrees, and machine pressure. Sourced defensively — a missing or broken
# lib must degrade to a normal run, never block tests. The no-op fallbacks
# below keep every call site total.
_TC_LIB="$(dirname "${BASH_SOURCE[0]}")/lib/test-contention.sh"
if [[ -f "$_TC_LIB" ]]; then
  # shellcheck source=scripts/lib/test-contention.sh
  source "$_TC_LIB" || true
fi
# Guard on tc_acquire AND tc_capacity_line. The single-function form was
# reproduced dying under version skew: a lib that defines tc_acquire but not
# tc_capacity_line (an origin/main-era copy in a mixed checkout, a stale plugin
# cache, a half-reverted worktree) left the stubs uninstalled, and the bare
# top-level `tc_capacity_line >&2` below exited 127 under `set -e` —
#   scripts/test-all.sh: line 814: tc_capacity_line: command not found
# with NO summary, NO rc file and NO [FAIL] line, which is the signature this
# repo documents as "a harness reap, not your diff".
#
# The old parenthetical said tc_acquire is "the LAST-defined function in the
# lib". That was FALSE and had been false on main: tc_epilogue is defined after
# it (941 vs 816 here, 660 vs 569 on main). The all-or-nothing-parse argument it
# rested on is real but covers TRUNCATION only, never skew — so the guard now
# names every function whose absence would abort, rather than one function
# believed to dominate the rest. bash parses a
# sourced file all-or-nothing, so a file truncated at an exact function boundary
# is the only state where an earlier function exists but a later one does not —
# checking the last one closes even that edge. If the lib is absent or failed to
# parse, install no-op stubs for every call site so a broken/missing lib degrades
# to a normal run rather than aborting the suite.
# Checked as a SET, not via a proxy. Guarding on one function treats "the lib
# failed to load at all" as the only failure — true for a missing or truncated
# file, false for VERSION SKEW, which is the live case (an origin/main-era lib in
# a mixed checkout, a stale plugin cache, a half-reverted worktree). Reproduced:
# a lib with tc_acquire but no tc_capacity_line left the stubs uninstalled and
# the bare top-level call below exited 127 with no summary, no rc file and no
# [FAIL] line. The list is asserted against the stub bodies by
# scripts/test-all-capacity-signal.test.sh, so adding a stub without adding its
# name here reds.
_TC_STUBBED_FNS="tc_preamble tc_epilogue tc_tmp_entry_count tc_used_bytes tc_acquire tc_capacity_line"
_tc_lib_incomplete=0
for _tc_fn in $_TC_STUBBED_FNS; do
  declare -F "$_tc_fn" >/dev/null 2>&1 || _tc_lib_incomplete=1
done
if (( _tc_lib_incomplete )); then
  echo "WARNING: contention instrumentation unavailable ($_TC_LIB); continuing without it." >&2
  tc_preamble() { :; }
  tc_epilogue() { :; }
  tc_tmp_entry_count() { printf '0\n'; }
  tc_used_bytes() { printf '0\n'; }
  tc_acquire() { :; }
  # NOT a no-op, unlike its siblings above. Every other stub here degrades an
  # OBSERVATION to a harmless zero; this one degrades an ANSWER, and an answer
  # that silently vanishes is the failure this verdict exists to prevent — a
  # reader who sees no CAPACITY_ line cannot tell "the box is fine" from "the
  # instrument is gone". AC15/M11 pin it.
  tc_capacity_line() { echo '[contention] BANNER CAPACITY_UNKNOWN reason=lib_unavailable'; }
fi

# ADR-133 amendment instrument: bytes held per mount, at RUN boundaries.
#
# WHY BYTES. The per-suite probe records `tmp_delta=<ENTRY COUNT>`, but ADR-133's
# capacity verdict is about BYTES — it explicitly rejected count-based reasoning
# because 4,294 small entries held 160 MB (4.5%) while three trees held 3.1 GiB
# (88%). The quantity the advisory lock exists to protect had never been measured
# by the instrument shipped to measure it.
#
# WHY RUN BOUNDARIES AND NOT PER SUITE. `du` is a RECURSIVE walk, unlike the
# shallow `find -maxdepth 1` the entry-count probe uses. At two edges x ~289
# suites that is ~578 walks per mount over multi-GiB trees — the same
# observer-effect confound that got a background sampler rejected during
# planning. Four walks answer the question ADR-133 actually asks: how many bytes
# did this run hold on each mount. WHICH suite holds them is the coincident-peak
# question, and that belongs to the deferred multi-run experiment.
#
# TWO DIRECTORIES, NEVER SUMMED. TMPDIR is /var/tmp (disk-backed) and TC_TMPDIR
# is /tmp (the 4 GiB tmpfs) — deliberately different mounts. A single number
# spanning both would report health from whichever is roomier, which is
# indistinguishable from a healthy mount.
#
# Gated on TEST_TIMING_LOG, so a default local run pays nothing for it.
_emit_bytes_probe() {
  [[ -n "${TEST_TIMING_LOG:-}" ]] || return 0
  local tmpfs_bytes disk_bytes
  tmpfs_bytes=$(tc_used_bytes "${TC_TMPDIR:-/tmp}")
  disk_bytes=$(tc_used_bytes "${TMPDIR:-/var/tmp}")
  printf '%s\t0\tbytes_tmp=%s\tbytes_tmpdir=%s\n' \
    "$1" "$tmpfs_bytes" "$disk_bytes" >> "$TEST_TIMING_LOG"
}

# --- Relevance predicates (ADR-181) ---
# Sourced at TOP LEVEL, and deliberately NOT defensively, unlike the contention lib above. That
# one is observe-only, so a missing lib must degrade to a normal run. This one DECIDES WHETHER
# SUITES EXECUTE: were it absent and the arrays empty, every gated suite would decline silently
# and the summary would still read green — the exact "green that is not evidence" the gate
# exists to prevent, produced by the gate itself. A missing file is a hard failure.
# --- Repo-write boundary lib (#7652) ------------------------------------------------------
#
# The _REL_LIB class of contract, not the _TC_LIB `|| true` class, and the selection rule is the
# one _REL_LIB's own comment states: a lib that decides whether the gate MEANS ANYTHING is a hard
# failure when missing. Under `|| true`, `_repo_state` would be undefined, return 127 inside
# `if _repo_state_before="$(_repo_state)"` — where `set -e` does not fire — and the run would
# print "the repo-write boundary was not measured (git unavailable at run start)", naming a cause
# it did not measure. That is an AP-021 violation manufactured by the fix for #7652.
#
# `test -f` is checked too, and is not sufficient on its own: it proves a file exists, never that
# it defines what the caller will call. So the named function SET is asserted in the _TC_LIB
# shape, and a STALE lib is NAMED rather than silently narrowing the gate behind a full-width
# claim.
#
# Placed HERE, above `tc_acquire`, deliberately: both suites that drive this runner as their SUT
# splice out everything between that anchor and `tc_epilogue`, and the end block runs under
# `set -u`. A source line below the anchor is deleted in those sandboxes and surfaces as two
# unrelated red suites instead of one honest failure.
_RWB_LIB="$(dirname "${BASH_SOURCE[0]}")/lib/repo-write-boundary.sh"
if [[ ! -f "$_RWB_LIB" ]]; then
  echo "ERROR: missing $_RWB_LIB — the repo-write boundary is undefined." >&2
  echo "Refusing to run: without it this runner cannot tell whether a suite wrote to your" >&2
  echo "repository, and a silent clean claim is worse than no claim." >&2
  echo "" >&2
  echo "  Restore it:  git checkout -- scripts/lib/repo-write-boundary.sh" >&2
  echo "  This runner also runs from lefthook's pre-commit hook. To commit before restoring:" >&2
  echo "    git commit --no-verify     (or)    LEFTHOOK=0 git commit" >&2
  exit 2
fi
# shellcheck source=scripts/lib/repo-write-boundary.sh
source "$_RWB_LIB"
_RWB_MISSING=""
for _rwb_fn in _repo_state repo_boundary_manifest \
               repo_boundary_render_inspected repo_boundary_render_not_inspected \
               repo_boundary_classify repo_boundary_next_action; do
  declare -F "$_rwb_fn" >/dev/null || _RWB_MISSING="$_RWB_MISSING $_rwb_fn"
done
if [[ -n "$_RWB_MISSING" ]]; then
  echo "ERROR: $_RWB_LIB is present but STALE — missing:$_RWB_MISSING" >&2
  echo "Refusing to run: a narrower check beneath a full-width claim is the exact defect the" >&2
  echo "boundary exists to prevent." >&2
  echo "" >&2
  echo "  Restore it:  git checkout -- scripts/lib/repo-write-boundary.sh" >&2
  echo "  To commit before restoring:  git commit --no-verify   (or)   LEFTHOOK=0 git commit" >&2
  exit 2
fi
unset _rwb_fn

_REL_LIB="$(dirname "${BASH_SOURCE[0]}")/lib/test-relevance-paths.sh"
if [[ ! -f "$_REL_LIB" ]]; then
  echo "ERROR: missing $_REL_LIB — the suite relevance predicates are undefined." >&2
  echo "Refusing to run: without them every gated suite would decline silently while the" >&2
  echo "summary still reported green." >&2
  exit 2
fi
# shellcheck source=scripts/lib/test-relevance-paths.sh
source "$_REL_LIB"

# --- Affected-mode declarations (#8322) --------------------------------------
#
# The _TC_LIB class of contract — degrade, never block — and deliberately NOT
# the _REL_LIB class above it. The asymmetry is load-bearing: a missing
# relevance lib declines every gated suite behind a green summary, but a missing
# affected lib cannot, because classification never runs without it — the
# derivation below instead emits AFFECTED_FALLBACK reason=index-missing and
# selects EVERYTHING. Blocking here would make a missing data file a wedge for
# the whole local gate; degrading keeps the gate and loses only the selection.
_AFF_LIB="$(dirname "${BASH_SOURCE[0]}")/lib/test-affected-paths.sh"
_AFF_LIB_OK=0
if [[ -f "$_AFF_LIB" ]]; then
  # shellcheck source=scripts/lib/test-affected-paths.sh
  source "$_AFF_LIB" || true
fi
if declare -p ALWAYS_ON_SUITES >/dev/null 2>&1; then
  _AFF_LIB_OK=1
fi

# --- Test group selector ---
# TEST_GROUP partitions the suite list across CI matrix shards. Env var wins
# over positional ($1) so GitHub Actions `env:` blocks and `gh workflow run`
# compose without rewriting the call site. Default `all` preserves byte-
# identical behavior for local invocation and any caller that never set this.
#
#   all      every suite, in original order (no-args default)
#   webplat  only apps/web-platform vitest
#   bun      3 named bun tests + plugins/soleur + blog-link-validation
#   scripts  11 pre-suite bash/python + the plugins/soleur/test/*.test.sh glob (SUITE_GLOBS)
#   scripts-heavy  the three cost-heaviest registrations, carved out of `scripts` so a
#            dedicated 3-leg ci.yml matrix can run them one-per-leg (#8006). Included
#            in `all`, so a local full-gate run covers them unchanged.
#   infra    ONLY the CI-registered apps/web-platform/infra/ runner (#7103 R5(a)).
#            This is the "TEST_GROUP asks" arm of the relevance gate below: an
#            explicit ask bypasses the diff check, so an infra run is reachable
#            without fabricating a diff. It is deliberately NOT part of `all`'s
#            shard set in ci.yml — infra gates through infra-validation.yml there.
#   affected every registration still passes the chokepoint, but run_suite declines
#            each suite the diff cannot reach (the counted-decline path, same as
#            skip_suite — declines stay in the denominator). The local targeted
#            mode: it exists because the repo-global advisory lock serialises full
#            batteries, and a session that only needs its own diff's coverage was
#            paying the whole battery's lock occupancy for it. It is NOT a CI
#            group — the matrix keeps running the full shards — and it does not
#            satisfy the ship-time full-gate requirement (ADR-183).
#
# See `.github/workflows/ci.yml` test-{webplat,bun,scripts,scripts-heavy} jobs + the
# synthetic `test` aggregator. See plan
# `knowledge-base/project/plans/2026-05-12-feat-ci-test-job-speedup-plan.md`.
TEST_GROUP="${TEST_GROUP:-${1:-all}}"
case "$TEST_GROUP" in
  all|webplat|bun|scripts|scripts-heavy|infra|affected) ;;
  *)
    echo "ERROR: TEST_GROUP must be one of: all, webplat, bun, scripts, scripts-heavy, infra, affected (got: $TEST_GROUP)" >&2
    echo "Usage: bash scripts/test-all.sh [all|webplat|bun|scripts|scripts-heavy|infra|affected]" >&2
    echo "   or: TEST_GROUP=<value> bash scripts/test-all.sh" >&2
    exit 2
    ;;
esac

# Two affected selectors coexist (#8322's declared-edge `--affected`, #8591's
# heuristic `TEST_GROUP=affected`) and they are DISTINCT modes — naming both on
# one invocation cannot mean "run both" (the runner has one selection axis) and
# silently preferring either would misreport which selection the evidence came
# from. Fail closed with the usage-error rc, same class as --affected/--full
# above.
if [[ "$TEST_GROUP" == "affected" ]] \
  && (( _AFFECTED_REQ == 1 || _FULL_REQ == 1 || _PRINT_AFFECTED == 1 )); then
  echo "ERROR: TEST_GROUP=affected cannot be combined with --affected/--full/--print-affected-set." >&2
  echo "       Pick one selector: 'bash scripts/test-all.sh --affected' (declared-edge gate)" >&2
  echo "       or 'TEST_GROUP=affected bash scripts/test-all.sh' (heuristic scope)." >&2
  exit 2
fi

# --- Subagent full-gate refusal (Item 6 of the 2026-08-11 test-pipeline post-mortem) ---------
# A spawned subagent runs only the suites targeting the files it was given. Three review agents
# running lints and suites concurrently inflated a measurement of the registry mutation battery
# by 1.9x (860 s -> 1675 s): the battery did not get slower, the machine did. A timing figure
# taken under that contention is not a measurement of the code — and this runner now GATES
# suites on measured cost, so a corrupted measurement propagates into what runs at all.
#
# MECHANICAL, not prose. The fan-out instructions in plugins/soleur/skills/{work,review}/SKILL.md
# carry the same rule in English, but a paragraph in a prompt IS agent discretion: a grep
# asserting that paragraph exists certifies the instruction was WRITTEN, never that it was
# obeyed. Those clauses explain this guard; this guard is what enforces it.
#
# It fires HERE — after TEST_GROUP is validated so the message can name it, but before
# tc_acquire and before the first suite — so a refused run costs nothing and never takes the
# advisory lock that a legitimate sibling run is queued on.
# SCRIPTS_SHARD IS SCOPED TO THE TWO SCRIPTS GROUPS, AND SAYS SO LOUDLY (#7902 review).
#
# `_shard_selects` sits at the chokepoint, so it is group-agnostic by construction — with the
# variable set and any other TEST_GROUP it partitions that group too. Measured before this guard
# existed: `TEST_GROUP=bun SCRIPTS_SHARD=2/3` silently ran 7 of ~21 registrations, and
# `TEST_GROUP=infra` hit the zero-assignment refusal with a message about the scripts count that
# made no sense for infra.
#
# CI is unaffected either way — the variable is bound only on ci.yml's test-scripts and
# test-scripts-heavy jobs, which pass `scripts` and `scripts-heavy` positionally (#8006). This
# is for the developer who exports it once and then runs a different group: an explicit refusal
# beats both a confusing exit 2 and a silently sharded gate.
if [[ -n "${SCRIPTS_SHARD+x}" && "$TEST_GROUP" != "scripts" && "$TEST_GROUP" != "scripts-heavy" ]]; then
  echo "ERROR: SCRIPTS_SHARD is set but TEST_GROUP is '$TEST_GROUP'." >&2
  echo "       The partition is scoped to the scripts and scripts-heavy groups; applying it to" >&2
  echo "       another group would silently run a fraction of that group and report success." >&2
  echo "       Unset SCRIPTS_SHARD, or run one of the scripts groups." >&2
  exit 2
fi

# --- Shard-assignment manifest (#8006, ADR-240) --------------------------------
#
# Positional round-robin balances by registration ORDER, not cost: measured on run
# 35840517639 it put 797s of suite time on leg 5/5 against 237s on the best leg. The
# committed manifest scripts/suite-shard-legs.tsv maps label -> leg from CI-measured
# durations (sticky-LPT, regenerated by scripts/regenerate-shard-manifest.py). The
# runner only READS it — computation stays out of the chokepoint, because
# `_shard_selects` sees one registration at a time and can never balance a set it is
# still discovering. That is also why a missing/stale manifest degrades instead of
# failing: coverage never depends on the table being present or current.
#
# ENGAGEMENT IS NARROW. All of: sharding is on (_SHARD_N > 0), TEST_GROUP is one
# of {scripts, scripts-heavy} — each bound to its OWN manifest file
# (suite-shard-legs.tsv for the light group, suite-shard-legs-heavy.tsv for
# heavy; per-group files keep the light table's insertion-stable surface
# untouched when the heavy table regenerates — ADR-240 amendment) — and the
# manifest declares `n` equal to _SHARD_N. Every other shape takes the
# positional path in `_shard_selects` — same behaviour as before manifests
# existed.
#
# SOLEUR_SHARD_MANIFEST (light) / SOLEUR_SHARD_MANIFEST_HEAVY (heavy) override the
# default path so the mutation battery can score fallback behaviour against
# fixture manifests without touching the committed file. `off` disables
# outright. A set-but-empty value, a non-absolute path, or a missing file all
# fail closed: an explicit override that cannot be honoured is a programming
# error, not a degrade. The default path being absent IS a degrade — a fresh
# clone or a mid-rebase checkout must still partition.
_shard_manifest_active=0
# Parallel indexed arrays, not an assoc map (bash 3.2) and NOT a packed-string
# pseudo-map either: a "|label=leg|" blob + `case` glob lookup backtracks over
# ~480 delimiters and measured >2min for one enumerate; a linear array scan
# with literal == is ~1.4s for the same 482x482 workload.
_shard_m_labels=()
_shard_m_legs=()
if (( _SHARD_N > 0 )) && [[ "$TEST_GROUP" == "scripts" || "$TEST_GROUP" == "scripts-heavy" ]]; then
  # The group's own file and its own override variable — bound by name so the
  # validation below can stay a single code path (the variable NAME keeps the
  # error messages naming the variable the caller actually set). The VALUE is
  # bound directly per arm, never via `${!_shard_mvar}` indirection: the
  # shell-trace credential lint reads `${!name}` as a runtime-selected
  # expansion (a credential class) and would put this runner in scope for the
  # xtrace refusal it does not need.
  if [[ "$TEST_GROUP" == "scripts-heavy" ]]; then
    _shard_mvar="SOLEUR_SHARD_MANIFEST_HEAVY"
    _shard_mfile="$(dirname "${BASH_SOURCE[0]}")/suite-shard-legs-heavy.tsv"
    _shard_mset="${SOLEUR_SHARD_MANIFEST_HEAVY+x}"
    _shard_mval="${SOLEUR_SHARD_MANIFEST_HEAVY-}"
  else
    _shard_mvar="SOLEUR_SHARD_MANIFEST"
    _shard_mfile="$(dirname "${BASH_SOURCE[0]}")/suite-shard-legs.tsv"
    _shard_mset="${SOLEUR_SHARD_MANIFEST+x}"
    _shard_mval="${SOLEUR_SHARD_MANIFEST-}"
  fi
  if [[ -n "$_shard_mset" ]]; then
    if [[ "$_shard_mval" == "off" ]]; then
      _shard_mfile=""
    elif [[ -z "$_shard_mval" ]]; then
      echo "ERROR: $_shard_mvar is set but empty." >&2
      echo "       Set it to an absolute manifest path, 'off', or unset it for the" >&2
      echo "       default $_shard_mfile." >&2
      exit 2
    elif [[ "$_shard_mval" != /* ]]; then
      echo "ERROR: $_shard_mvar must be an absolute path" >&2
      echo "       (got: '$_shard_mval') — this runner never normalises cwd." >&2
      exit 2
    elif [[ ! -f "$_shard_mval" ]]; then
      echo "ERROR: $_shard_mvar points at a file that does not exist:" >&2
      echo "       '$_shard_mval'" >&2
      exit 2
    else
      _shard_mfile="$_shard_mval"
    fi
  elif [[ ! -f "$_shard_mfile" ]]; then
    echo "[shard] no ${_shard_mfile##*/} manifest — positional assignment" >&2
    _shard_mfile=""
  fi
  unset _shard_mvar _shard_mset _shard_mval

  if [[ -n "$_shard_mfile" ]]; then
    _shard_mn=""
    while IFS= read -r _mline; do
      case "$_mline" in
        "# n="*) _shard_mn="${_mline#\# n=}"; break ;;
      esac
    done < "$_shard_mfile"
    if [[ ! "$_shard_mn" =~ ^[0123456789]{1,9}$ ]] || (( 10#${_shard_mn} != _SHARD_N )); then
      echo "[shard] manifest n='${_shard_mn:-<none>}' != SCRIPTS_SHARD N=${_SHARD_N} — positional assignment" >&2
    else
      _shard_mcount=0
      while IFS=$'\t' read -r _mlbl _mleg _mrest; do
        case "$_mlbl" in
          "" | "#"*) continue ;;
        esac
        if [[ -n "$_mrest" || ! "$_mleg" =~ ^[0123456789]{1,9}$ ]]; then
          echo "ERROR: ${_shard_mfile}: malformed row '${_mlbl}' — expected 'label<TAB>leg'" >&2
          echo "       with leg an integer in 1..${_shard_mn}. Regenerate:" >&2
          echo "         python3 scripts/regenerate-shard-manifest.py --write" >&2
          exit 2
        fi
        _mleg=$(( 10#${_mleg} ))
        if (( _mleg < 1 || _mleg > _shard_mn )); then
          echo "ERROR: ${_shard_mfile}: '$_mlbl' assigned to leg $_mleg outside 1..${_shard_mn}." >&2
          echo "       Regenerate: python3 scripts/regenerate-shard-manifest.py --write" >&2
          exit 2
        fi
        # Index loop, not `"${arr[@]}"`: an empty array's @-expansion is an unbound-
        # variable death under `set -u` on bash 3.2 (macOS's shipped shell).
        for (( _mdup = 0; _mdup < ${#_shard_m_labels[@]}; _mdup++ )); do
          if [[ "$_mlbl" == "${_shard_m_labels[_mdup]}" ]]; then
            echo "ERROR: ${_shard_mfile}: '$_mlbl' listed twice." >&2
            echo "       Regenerate: python3 scripts/regenerate-shard-manifest.py --write" >&2
            exit 2
          fi
        done
        _shard_m_labels+=("$_mlbl")
        _shard_m_legs+=("$_mleg")
        _shard_mcount=$(( _shard_mcount + 1 ))
      done < "$_shard_mfile"
      _shard_manifest_active=1
      echo "[shard] manifest assignment active: ${_shard_mcount} label(s) from ${_shard_mfile}" >&2
    fi
  fi
  unset _shard_mfile _shard_mn _mline _mlbl _mleg _mrest _mdup _shard_mcount
fi

# THE CARRIER IS CONSUMED HERE, AND MUST NOT BE INHERITED (#7902 review, P1).
#
# `SCRIPTS_SHARD` arrives as a JOB-LEVEL `env:` on ci.yml's test-scripts and
# test-scripts-heavy jobs, so it is in the
# environment of every step AND every descendant process. Four suites registered INTO the scripts
# group spawn a sandboxed copy of this runner with `TEST_GROUP=all` — they would inherit the
# variable, hit the refusal directly above, and exit 2 inside every arm. Measured on
# scripts/test-all-runtime-ceiling.test.sh: 23 passed / 0 failed unset, 8 passed / 15 FAILED with
# SCRIPTS_SHARD=1/3. Two of three legs red => test-scripts red => the required `test` check red.
#
# The decision is already made: `_SHARD_K` and `_SHARD_N` hold it, and nothing below reads the
# variable again (the zero-assignment refusal reports the parsed integers, not the raw value). So
# unset the carrier and let the parsed values speak. This is one edit at the point of coupling
# rather than `env -u SCRIPTS_SHARD` at N call sites, because the next suite that spawns this
# runner would otherwise have to remember — and the four that exist did not.
#
# It also closes a second hole for free: the sandbox builders splice out everything between
# `tc_acquire` and the epilogue, which is where the zero-assignment refusal lives. A sandbox could
# therefore carry the shard FILTER without the REFUSAL and print `0/0 suites passed` at exit 0.
# With the carrier gone, a sandbox is never sharded at all.
#
# Placement is load-bearing: AFTER the group-scope refusal above (which reads
# `${SCRIPTS_SHARD+x}`), never after the parse block — unsetting earlier makes that refusal dead
# code and reopens the silently-sharded-wrong-group case it exists to catch.
#
# `SOLEUR_SHARD_MANIFEST`/`SOLEUR_SHARD_MANIFEST_HEAVY` ride the same rule: the manifest
# is already loaded above, and a battery fixture path into a deleted $WORK must not be
# inherited by a nested runner.
unset SCRIPTS_SHARD SOLEUR_SHARD_MANIFEST SOLEUR_SHARD_MANIFEST_HEAVY

# `_ENUMERATE == 0` is a genuine exemption, not a hole: this refusal exists because concurrent
# full-gate runs inflate each other's timings, and an enumerate pass starts NO suite and takes
# NO lock, so it can inflate nothing. Without the exemption the shard-totality guard could not
# run from a spawned agent at all.
# Both affected modes are exempt. `TEST_GROUP=affected` (#8591) is the targeted-suite
# substitute this refusal prescribes, expressed mechanically instead of as hand-picked
# suite files; `--affected` (#8322) is minutes-scale by construction and contends on
# nothing the full-battery measurement cares about. When the `--affected` axis DEGRADES
# to full (undecidable diff, missing index, runner-changed), the degraded run is
# re-refused post-derivation at the sibling arm — this early site cannot see that
# verdict yet because `_diff_names` does not exist this high in the file.
if (( _ENUMERATE == 0 && _AFFECTED == 0 )) && [[ "${SOLEUR_SUBAGENT:-}" == "1" && "${SOLEUR_ALLOW_FULL_GATE:-}" != "1" && "$TEST_GROUP" != "affected" ]]; then
  echo "ERROR: refusing a full-gate run — SOLEUR_SUBAGENT=1 is set (TEST_GROUP=$TEST_GROUP)." >&2
  echo "" >&2
  echo "Spawned agents run only the suites targeting the files they were given. Concurrent" >&2
  echo "full-gate runs inflate each other's timings and corrupt the measurement. The lead runs" >&2
  echo "the gate once, after collecting fan-out work." >&2
  echo "" >&2
  echo "Run the affected set — what your diff actually reaches — instead:" >&2
  echo "    bash scripts/test-all.sh --affected" >&2
  echo "or the runner-selected diff scope:" >&2
  echo "    TEST_GROUP=affected bash scripts/test-all.sh" >&2
  echo "or the suite covering your files directly:" >&2
  echo "    bash <path/to/the/suite.test.sh>" >&2
  echo "" >&2
  echo "If you are the lead and this IS the sanctioned gate run, override explicitly:" >&2
  echo "    SOLEUR_ALLOW_FULL_GATE=1 bash scripts/test-all.sh --full" >&2
  # rc 4, deliberately NOT 3. #7424 assigned rc 3 the meaning "a suite was terminated —
  # unresolved, coverage not obtained", and that trichotomy is documented in one-shot/SKILL.md.
  # A refusal is the opposite claim (nothing ran, by design, and nothing is unresolved), so it
  # needs its own code; sharing 3 would make a refused run read as a killed suite. 1 is an
  # ordinary suite failure and 2 is a bad TEST_GROUP, so 4 is the next free value.
  exit 4
fi

# `affected` widens EVERY want_*, deliberately: the selection is not a shard — it happens
# per-suite at the run_suite chokepoint via _suite_affected, so all five registration
# families must still walk. Folding the filter into these predicates would decline whole
# groups silently (a `bun`-only diff would erase every scripts suite without a counted
# decline), which is exactly the "green that is not evidence" shape ADR-181 closes.
want_scripts() { [[ "$TEST_GROUP" == "all" || "$TEST_GROUP" == "scripts" || "$TEST_GROUP" == "affected" ]]; }
# `scripts-heavy` (#8006): the three cost-heaviest registrations live under this gate so
# ci.yml's dedicated test-scripts-heavy matrix partitions them one-per-leg. `all` must
# include them — dropping that arm would silently remove the most expensive suites from
# every full-gate run (ship Phase 4, lefthook, main-health-monitor).
want_scripts_heavy() { [[ "$TEST_GROUP" == "all" || "$TEST_GROUP" == "scripts-heavy" || "$TEST_GROUP" == "affected" ]]; }
want_bun()     { [[ "$TEST_GROUP" == "all" || "$TEST_GROUP" == "bun"     || "$TEST_GROUP" == "affected" ]]; }
want_webplat() { [[ "$TEST_GROUP" == "all" || "$TEST_GROUP" == "webplat" || "$TEST_GROUP" == "affected" ]]; }
# `infra` is reachable from `all` (so a default local run covers it when the diff is
# relevant) and from an explicit ask. It is NOT folded into `scripts`: that shard is a CI
# matrix job with no terraform/cloud-init toolchain, and registering an 87-suite runner
# into it would red a required check for want of a binary (#6454's exact shape). Under
# `affected` it registers too — its own `_infra_in_diff` gate still decides whether it
# actually runs, which is the distinction the group/not_in_diff skip reasons carry.
want_infra()   { [[ "$TEST_GROUP" == "all" || "$TEST_GROUP" == "infra"   || "$TEST_GROUP" == "affected" ]]; }

# --- Run Tests Per Directory ---
failed=0
suites=0
# Beside failed/suites deliberately, and required — but for a different reason
# than an earlier revision of this comment claimed. MEASURED 2026-08-11 (bash
# 5.3.9): with `killed` unset, `set -u` aborts at the FIRST read, which is the
# breakdown gate — ABOVE the terminal marker, not below it — and the run exits
# 1, not 0. So the failure mode is a loud abort with no terminal marker, not a
# silent false green. That shape is what work/SKILL.md reads as "a failure with
# no marker", which sends a reader hunting for [FAIL] lines that do not exist.
killed=0

# Classify a suite's exit code into exactly one of: ok | failed | killed.
#
# `killed` means SIGNAL-SHAPED, not "was killed by <signal>". $? cannot tell a
# signal death from a literal exit(128+N) — `bash -c 'exit 143'` also yields 143
# — so the class is a statement about the SHAPE of the status, and the rendered
# line says so. Naming a cause here would reintroduce, one layer up, the defect
# this whole change exists to remove.
#
# All three guards are load-bearing. Measured 2026-08-10, bash 5.3.9/Linux:
#   kill -l 0   -> "EXIT"  (rc 0)          so `rc > 128` is what excludes rc=128
#   kill -l 32  -> ""      (rc 0)          glibc-internal SIGCANCEL
#   kill -l 33  -> ""      (rc 0)          glibc-internal SIGSETXID
#                                          so `-n "$name"` is what excludes 160/161
#   kill -l 143 -> "TERM"                  it MASKS values > 64
# `kill -l` is therefore NOT a validity oracle. Anyone "simplifying away the
# redundant > 128 check because kill -l already bounds it" breaks the classifier.
#
# The numeric guard closes an INPUT-side false green: without it, `(( rc == 0 ))`
# on "" or " " evaluates TRUE and returns `ok` — the one class that increments no
# counter and emits no warning. Not reachable from today's run_suite (`local rc=0`
# guarantees numeric) but reachable from the suite that certifies this function.
suite_exit_class() {
  local rc="${1-}" name
  [[ "$rc" =~ ^[0-9]+$ ]] || { printf 'failed\n'; return 0; }   # fail CLOSED on a malformed rc
  (( rc == 0 )) && { printf 'ok\n'; return 0; }
  # `<= 192` is a legibility bound and is NOT load-bearing: the call passes
  # `kill -l $(( rc - 128 ))`, so for every rc in 193..255 the operand is 65..127,
  # which kill -l rejects — the `-n "$name"` guard already excludes it. Mutating
  # this to `rc > 128` leaves every table row byte-identical, so no test pins it.
  # It is kept to state the intended domain, not because a row proves it.
  if (( rc > 128 && rc <= 192 )); then
    name=$(kill -l $(( rc - 128 )) 2>/dev/null) || name=""
    [[ -n "$name" ]] && { printf 'killed\n'; return 0; }
  fi
  printf 'failed\n'
}

# Declared wall-clock budgets for suites known to be long. A `case`, not a
# `declare -A`: no initialization ordering to get right, no associative-array
# declaration at the top of a ~1000-line script, and zero churn at the 132
# run_suite call sites. Emits nothing for an undeclared label.
#
# A budget NEVER changes a suite's status or the runner's exit code. It exists so
# that a nine-minute suite is a STATED FACT rather than a surprise — which is the
# attribution half of what a reader needs when a long suite does not come back.
_suite_budget_ms() {
  case "$1" in
    # MEASURED 2026-08-11, both runs completing rc=0 on this 16-core host:
    #   860692ms  as run BY THIS RUNNER (TEST_TIMING_LOG), one sibling worktree
    #             running an individual suite concurrently
    #   1675430ms standalone, with three concurrent agent sessions on the box
    # Load alone moves it 1.9x, so a budget near either figure would fire on
    # ordinary busy runs and become noise. Declared at ~1.5x the HIGHEST observed.
    #
    # NOT derived from the incident's 560931ms: that is elapsed AT THE KILL,
    # roughly two thirds of the way in, so it is a lower bound on the duration
    # and useless as a budget.
    tests/scripts/registry-gate-mutation-battery) printf '2500000\n' ;;
    *) return 0 ;;
  esac
}

# Declines (ADR-181). Beside failed/killed for the same reason: a suite that was not run
# is not a suite that passed, and the denominator must still account for it.
skipped=0

# Affected-mode state (#8322). A DISTINCT counter, not folded into `skipped`:
# `skipped` carries relevance/incident/not_in_diff declines whose semantics
# ADR-181 already fixed; `_affected_declined` is the selection axis this file
# added, and the epilogue reports it separately so the two decline classes can
# never be summed into one misleading number. `_aff_sel`/`_aff_class` are the
# per-ORDINAL selection and label maps the derivation pre-pass fills;
# `_aff_ready` is the only flag the chokepoint consults, so every unset/empty
# state (full mode, degraded fallback, enumerate) defaults to SELECT — the
# fail-safe direction. Ordinal-indexed, never associative: bash 3.2.
# `_aff_label` is the divergence guard's source of truth: ordinal N must carry
# the same label in the enumerate child and the dispatch walk, else the map is
# shifted and every later selection bit belongs to a different suite.
_affected_declined=0
_aff_ready=0
_aff_fallback=""
_aff_sel=()
_aff_label=()

# --- Shard selection at the registration chokepoint (#7902, #8006) ---------------------------
#
# run_suite() and skip_suite() are the two chokepoints every group registration passes through,
# and EXACTLY ONE of them is called per registration site. A filter placed at both, BEFORE each
# increments `suites`, therefore partitions the group with no registration reachable twice and
# none reachable zero times. Totality is STRUCTURAL, not asserted: every registration receives
# a verdict regardless of how that verdict is computed.
#
# TWO ASSIGNMENT MODES, selected once at parse time (see the manifest block above):
#
#   MANIFEST — when the group's own table (scripts/suite-shard-legs.tsv for `scripts`,
#   suite-shard-legs-heavy.tsv for `scripts-heavy`) is present, declares n == _SHARD_N:
#   each label's leg is a table lookup produced OFFLINE from CI-measured durations
#   (sticky-LPT; scripts/regenerate-shard-manifest.py --group light|heavy). Labels the
#   table does not know fall back to a deterministic cksum hash — coverage and disjointness
#   never depend on the table being complete or current, and inserting a suite moves no
#   existing assignment. This mode is collation-INDEPENDENT: neither the table nor the hash
#   reads registration order.
#
#   POSITIONAL — the original mechanism, still the degrade for every shape the group's
#   manifest does not cover (absent file, n mismatch, an unrelated group,
#   `SOLEUR_SHARD_MANIFEST=off` / `SOLEUR_SHARD_MANIFEST_HEAVY=off`):
#   round-robin over the registration ordinal. It stays ordinal-based rather than hash-based
#   because ~198 registrations are hand-written imperative statements and ~24 name no bash
#   path at all (`python3 -m unittest`, `node --test`) — the ordinal is the one thing every
#   registration provably has, and it already spreads neighbouring (co-located, often slow)
#   suites across legs.
#
# A NON-SELECTION IS NOT A DECLINE. It must not increment `suites`, must not increment
# `skipped`, and must not reach the runtime-ceiling accounting below. A suite this leg was
# never asked to run is not coverage this leg failed to obtain; counting it as one would either
# push every leg to ADR-181's exit 3 (UNRESOLVED) or restate the "green over a battery that
# never ran" defect ADR-181 exists to have closed.
#
# WHICH leg a suite lands on under POSITIONAL mode is LOCALE-DEPENDENT; that it lands on
# exactly one is not. The ordinal comes from registration order, and the glob loop's order is
# shell glob expansion, which collates per LC_COLLATE — measured 2026-09-07, a `_`-prefixed
# filename sorts differently under en_US.UTF-8 than under the runners' C locale, and the two
# orders diverge from index 185. Totality and disjointness hold under ANY order, so this is
# not a correctness problem; it only means positional membership is not portable between
# machines. The manifest removes even that: a tabled label lands on its tabled leg under any
# locale, and a hash fallback is collation-free.
# SCOPE NOTE: this filter lives at the chokepoint, so it is GROUP-AGNOSTIC — with SCRIPTS_SHARD
# set and TEST_GROUP=all it would partition the webplat/bun/infra registrations too. That is not
# reachable today (the variable is bound only on ci.yml's test-scripts and test-scripts-heavy
# jobs, and main-health-monitor.yml's TEST_GROUP=all run does not set it), and the name says
# `SCRIPTS_` for that reason. Anyone binding it more widely must revisit this.
_shard_ordinal=0
_shard_assigned=0

_shard_selects() {
  if (( $# < 1 )); then
    echo "ERROR: _shard_selects requires the registration label as an argument." >&2
    echo "       The manifest lookup is keyed on it — a missing argument is a programming" >&2
    echo "       error, not a suite to place." >&2
    exit 2
  fi
  # Deleted-cwd liveness (#8761): the single chokepoint every registration
  # funnels through, in EVERY mode — a checkout deleted mid-walk is caught at
  # the next dispatch rather than completing over a truncated receipt set.
  [[ -d "$PWD" ]] || _wt_missing_die
  # Enumerate-scoped graceful deadline: at the wall the watchdog's 1s poll
  # usually wins the race; this layer's value is the named exit 4 and the
  # registration ordinal when a boundary lands first (the watchdog's signal
  # death carries neither). The watchdog remains the hard bound for a spin
  # that never reaches this check.
  if (( _ENUMERATE == 1 && SECONDS - ${_ENUM_T0:-0} > _ENUM_DEADLINE_S )); then
    echo "ERROR: enumerate deadline exceeded (${_ENUM_DEADLINE_S}s, SOLEUR_ENUM_DEADLINE_S) after ${_shard_ordinal} registrations walked" >&2
    echo "ERROR: enumerate deadline exceeded (${_ENUM_DEADLINE_S}s, SOLEUR_ENUM_DEADLINE_S) after ${_shard_ordinal} registrations walked"
    exit 4
  fi
  local label="$1"
  _shard_ordinal=$(( _shard_ordinal + 1 ))
  if (( _shard_manifest_active == 1 )); then
    # Manifest mode: the leg is a label LOOKUP, not an ordinal function. A label the
    # manifest does not table — a suite added since the last regeneration — hashes
    # onto a leg deterministically (POSIX cksum), so inserting a suite never moves an
    # existing assignment and assignment is collation-independent.
    local _leg=0 _mi
    for (( _mi = 0; _mi < ${#_shard_m_labels[@]}; _mi++ )); do
      if [[ "$label" == "${_shard_m_labels[_mi]}" ]]; then
        _leg=$(( 10#${_shard_m_legs[_mi]} ))
        break
      fi
    done
    if (( _leg == 0 )); then
      _leg=$(( ($(printf '%s' "$label" | cksum | cut -d' ' -f1) % _SHARD_N) + 1 ))
    fi
    if (( _leg != _SHARD_K )); then
      return 1
    fi
    _shard_assigned=$(( _shard_assigned + 1 ))
    return 0
  fi
  if (( _SHARD_N > 0 )) && (( (_shard_ordinal - 1) % _SHARD_N != _SHARD_K - 1 )); then
    return 1
  fi
  _shard_assigned=$(( _shard_assigned + 1 ))
  return 0
}

# Sentinel-prefixed so a consumer can extract the registration list from a stdout stream that
# also carries banners and interstitial prose. A bare label line would be indistinguishable
# from the surrounding noise.
_shard_enumerate_emit() {
  printf 'SUITE_REGISTRATION\t%s\n' "$1"
}

# Emit one SUITE_COMMAND record: label, then the argv verbatim, TAB-delimited.
# Refuses (exit 2) on an element containing a TAB or NEWLINE — see the record contract at the
# --enumerate-commands parse arm. A corrupt record read as a command list is worse than no
# record, because the consumer cannot tell it was corrupted.
_shard_enumerate_command_emit() {
  local label="$1"; shift
  local a
  for a in "$label" "$@"; do
    case "$a" in
      # `$'\t'` and `$'\n'`, NOT `"$(printf '\t')"`: the command-substitution form forks once per
      # argv element per registration. Measured END TO END from a valid repo root, three runs per
      # arm, two trials: 9.48s/9.29s before vs 6.20s/5.70s after, i.e. ~3.1s -> ~2.0s per
      # enumeration. (A micro-benchmark of the `case` alone shows 1.364s vs 0.009s per 2000
      # iterations; that ratio does NOT carry to the whole mode, which is why the figure quoted
      # here is the measured one. An earlier draft of this comment quoted the micro-benchmark and
      # implied ~18s per battery run.) The guard fans out ~35 enumerate children per invocation
      # and the mutation battery invokes the guard once per row (24) plus control.
      *$'\t'* | *$'\n'*)
        printf 'ERROR: --enumerate-commands cannot encode an argv element containing a TAB or NEWLINE (label=%s)\n' "$label" >&2
        exit 2
        ;;
    esac
  done
  printf 'SUITE_COMMAND\t%s' "$label"
  for a in "$@"; do printf '\t%s' "$a"; done
  printf '\n'
}

# One dispatch point per registration function, so each function keeps a single
# enumerate-mode conjunct line, and the mode choice lives here rather than being
# duplicated at both call sites.
_shard_enumerate_dispatch() {
  local label="$1"; shift
  if (( _EMIT_COMMANDS == 1 )); then
    _shard_enumerate_command_emit "$label" "$@"
  else
    _shard_enumerate_emit "$label"
  fi
}

_shard_enumerate_declined_dispatch() {
  if (( _EMIT_COMMANDS == 1 )); then
    _shard_enumerate_declined_emit "$1" "$2"
  else
    _shard_enumerate_emit "$1"
  fi
}

# skip_suite's third positional is a human RERUN string, not argv — a distinct record type so
# a consumer can never parse it as a command.
_shard_enumerate_declined_emit() {
  # Same contract refusal as _shard_enumerate_command_emit: a field-3 rerun
  # string carrying a TAB or NEWLINE corrupts the record for consumers that
  # split on TAB (the affected pre-pass reads field 2 as the label).
  local _e
  for _e in "$1" "$2"; do
    if [[ "$_e" == *$'\t'* || "$_e" == *$'\n'* ]]; then
      printf 'ERROR: --enumerate-commands cannot encode a declined-record field containing a TAB or NEWLINE (label=%s)\n' "$1" >&2
      exit 2
    fi
  done
  printf 'SUITE_COMMAND_DECLINED\t%s\t%s\n' "$1" "$2"
}

run_suite() {
  local label="$1"; shift
  _shard_selects "$label" || return 0
  # TEST_GROUP=affected selection lives HERE, after the shard filter consumed its ordinal
  # and before enumerate/exec diverge — the same chokepoint discipline _shard_selects
  # carries, so denominators and the command record stay honest in every mode. The
  # decline goes through the counted path skip_suite established (suites and skipped both
  # increment, a timing row is written, and enumerate mode emits a DECLINED record rather
  # than omitting the line) — an affected run must never read as a full battery.
  if [[ "$TEST_GROUP" == "affected" ]] && ! _suite_affected "$label" "$@"; then
    if (( _ENUMERATE == 1 )); then _shard_enumerate_declined_dispatch "$label" "$*"; return 0; fi
    suites=$((suites + 1))
    skipped=$((skipped + 1))
    _affected_declined=$((_affected_declined + 1))
    echo ""
    echo "[skip] $label (affected)"
    echo "      Nothing in this diff reaches it. Re-run with:"
    echo "        $*"
    echo ""
    printf '%s\t%d\tskip=%s\n' "$label" 0 "affected" >> "${TEST_TIMING_LOG:-/dev/null}"
    return 0
  fi
  if (( _ENUMERATE == 1 )); then
    if (( _PRINT_AFFECTED == 1 )); then _affected_emit_receipt "$label" "$@"; fi
    _shard_enumerate_dispatch "$label" "$@"; return 0
  fi
  suites=$((suites + 1))
  # DIVERGENCE GUARD (#8322): `_aff_sel` is keyed on the enumerate CHILD's
  # ordinal stream but indexed by THIS walk's `_shard_ordinal`. The glob loop
  # re-expands SUITE_GLOBS per pass, so a suite file created or deleted between
  # the two walks shifts every later ordinal and would decline suites carrying
  # another suite's bit — silent under-coverage. A label mismatch means the
  # whole map is suspect: drop it (the `:-1` default below then selects
  # everything remaining) and say so loudly — fail toward coverage.
  if (( _aff_ready == 1 )) && [[ "${_aff_label[$_shard_ordinal]:-}" != "$label" ]]; then
    _aff_ready=0
    printf 'AFFECTED_DIVERGENT\tordinal=%d map=%s dispatch=%s\n' \
      "$_shard_ordinal" "${_aff_label[$_shard_ordinal]:-<none>}" "$label"
    echo "[affected] WARN: enumerate/dispatch divergence at ordinal $_shard_ordinal — selection map dropped; every remaining suite runs" >&2
  fi
  # Affected decline (#8322). AFTER `suites++`, so a declined registration stays
  # in the denominator — the ADR-181 argument verbatim, one axis up. AFTER the
  # enumerate dispatch, so the record stream never contains a selection claim
  # the run never exercised. `_aff_sel` is keyed on `_shard_ordinal`, which
  # `_shard_selects` just incremented for this registration; `${...:-1}` makes
  # any gap in the map SELECT rather than decline — the fail-safe direction.
  if (( _aff_ready == 1 )) && [[ "${_aff_sel[$_shard_ordinal]:-1}" == "0" ]]; then
    # Both affected axes count the same way (#8591's chokepoint decline set the
    # shape): skipped + _affected_declined, so the epilogue's skipped term
    # carries either mode's declines and _affected_declined stays the per-axis
    # count the field, lever and NOTE read.
    skipped=$((skipped + 1))
    _affected_declined=$(( _affected_declined + 1 ))
    printf '[skip] %s (not-affected — the diff does not reach it)\n' "$label"
    printf '%s\t%d\tskip=not-affected\n' "$label" 0 >> "${TEST_TIMING_LOG:-/dev/null}"
    return 0
  fi
  # --- Runtime ceiling (#7869) ---------------------------------------------
  #
  # Once this run has been executing longer than the ceiling, start no further suite. An
  # orphaned run — one whose session has gone away — otherwise works through its whole suite
  # list holding the repo-global advisory lock, with nobody to read the result.
  #
  # AN EARLY `return`, NOT AN `exit`, AND THAT IS THE WHOLE DESIGN. The lock fd is inherited by
  # suite children (session-state.sh opens it with `exec {fd}>>`; bash sets no CLOEXEC and flock
  # binds to the open file description), so a mid-suite exit would release nothing. Freeing it
  # would mean tearing down descendants, and the only teardown reaching them is a process-group
  # signal — which this runner must not send, because it does not own its group: under lefthook
  # each hook command runs in its own group led by the `sh -c` wrapper lefthook supervises, and
  # under a bare git hook the leader is `git commit` itself. Returning at suite ENTRY sidesteps
  # the question: no suite child is live at that instant, so the ordinary exit closes the fd.
  #
  # THE DECLINE IS COUNTED. `suites` is incremented ABOVE this check, so a declined suite stays
  # in the denominator and is subtracted from the numerator — the terminal marker degrades to
  # `N-k/N` rather than reading a perfect `N/N` over a battery that never ran. ADR-181 records
  # that exact defect for relevance declines ("a green that is not evidence, produced by the very
  # change that added the gate"); an earlier revision of this block reproduced it.
  if (( _CEILING_S > 0 )); then
    local _elapsed_s=$(( "${EPOCHSECONDS:-0}" - _RUN_START_EPOCH ))
    if (( _elapsed_s >= _CEILING_S )); then
      _ceiling_declined=$(( _ceiling_declined + 1 ))
      printf '%s\t%d\tskip=runtime-ceiling\n' "$label" 0 >> "${TEST_TIMING_LOG:-/dev/null}"
      if (( _ceiling_tripped == 0 )); then
        _ceiling_tripped=1
        echo "" >&2
        echo "[contention] BANNER SOLEUR_TEST_ALL_RUNTIME_CEILING elapsed_s=${_elapsed_s} ceiling_s=${_CEILING_S} first_declined=${label} — this run has outlived the ceiling, so it is starting no further suite." >&2
        echo "             A run past the ceiling is treated as having no consumer. It exits 3 (UNRESOLVED): coverage was NOT obtained for the declined suites." >&2
        echo "             Raise TC_RUNTIME_CEILING_S if this run is legitimately long." >&2
      fi
      return 0
    fi
  fi
  local tmp_before=""
  if [[ -n "${TEST_TIMING_LOG:-}" ]]; then
    tmp_before=$(tc_tmp_entry_count)
  fi
  # Recorded so the repo-write boundary can NAME the suite in flight when a write happened,
  # instead of reporting "something in this run wrote to your repo" and leaving the reader the
  # same ~330-suite haystack the incident already cost someone once. One assignment per suite;
  # per-suite git snapshots would narrow it further and cost ~660 extra process spawns, which is
  # not worth it for a strictly-narrower answer.
  _repo_last_suite="$label"
  local start="${EPOCHREALTIME:-}"
  echo "--- $label ---"
  # Capture the exit code rather than testing it. `if ! "$@"` is a boolean test:
  # it discards WHICH non-zero the suite returned, which is precisely the
  # information needed to tell a terminated suite from a failed one.
  local rc=0
  "$@" || rc=$?
  # An ABORTING classifier is its own degradation and must not be absorbed into
  # the ordinary `failed` bucket: that would make a broken classifier — which can
  # mis-bucket every subsequent suite — indistinguishable from one honest test
  # failure, silently. It is routed to the same fail-closed arm as an
  # unrecognized class so it is counted FAILED and SAID OUT LOUD.
  local status="failed" cls_rc=0
  status="$(suite_exit_class "$rc" 2>/dev/null)" || cls_rc=$?
  if (( cls_rc != 0 )); then
    status="__aborted(rc=$cls_rc)__"
  fi
  case "$status" in
    ok)     ;;
    failed) failed=$((failed + 1)) ;;
    killed) killed=$((killed + 1)) ;;
    # Fail CLOSED. Without this arm an unrecognized class increments NEITHER
    # counter, and `$((suites - failed - killed))` then counts the suite as
    # PASSED — the exact false green this change exists to prevent.
    *)      echo "WARNING: suite_exit_class returned unrecognized class '$status' for rc=$rc (classifier exit=$cls_rc); counting as FAILED." >&2
            status="failed"; failed=$((failed + 1)) ;;
  esac
  # Integer math on EPOCHREALTIME ("seconds.microseconds") avoids a coreutils
  # `date +%N` dependency that macOS lacks. 10# forces base-10 parsing of the
  # microseconds substring (a leading zero would otherwise trigger octal).
  # The `*.*` glob guard rejects bash-3.x values (where EPOCHREALTIME is unset
  # and the captured value is empty or non-dotted) and exits elapsed_ms=0
  # gracefully instead of arithmetic-overflowing on `${start#*.}` returning
  # the whole string.
  local end="${EPOCHREALTIME:-}"
  local elapsed_ms=0
  if [[ "$start" == *.* && "$end" == *.* ]]; then
    local start_us=$(( ${start%.*} * 1000000 + 10#${start#*.} ))
    local end_us=$(( ${end%.*} * 1000000 + 10#${end#*.} ))
    elapsed_ms=$(( (end_us - start_us) / 1000 ))
  fi
  # Appended as a LABELED trailing field (`tmp_delta=<N>`), never as a bare
  # positional one: field 3 already carries the `FAIL` marker, so an unlabeled
  # append would be positionally ambiguous between the ok and FAIL shapes.
  local tmp_field=""
  if [[ -n "${TEST_TIMING_LOG:-}" && -n "$tmp_before" ]]; then
    tmp_field=$'\t'"tmp_delta=$(( $(tc_tmp_entry_count) - tmp_before ))"
  fi
  # Advisory only: never changes status, never changes the exit code.
  local budget_ms; budget_ms="$(_suite_budget_ms "$label")"
  if [[ -n "$budget_ms" ]] && (( elapsed_ms > budget_ms )); then
    echo "[budget] $label ran ${elapsed_ms}ms against its declared ${budget_ms}ms budget — expected-long suite, declared here so a long run is a stated fact rather than a surprise." >&2
  fi
  # `[ok]` and `[FAIL]` keep their EXACT current text. Every monitor, learning and
  # skill anchored on `^\[FAIL\]` must keep working byte-for-byte; the new class is
  # additive, never a re-spelling of an existing one.
  if [[ "$status" == "ok" ]]; then
    echo "[ok] $label (${elapsed_ms}ms)"
    printf '%s\t%d%s\n' "$label" "$elapsed_ms" "$tmp_field" >> "${TEST_TIMING_LOG:-/dev/null}"
  elif [[ "$status" == "killed" ]]; then
    # A declared budget is named HERE, on the one line where it changes the
    # reading: it tells the reader whether this suite's elapsed time was expected.
    # Without it "560931ms" is a bare number; with it, it is two thirds of a
    # declared 2500000ms budget, i.e. the kill was not this runner running long.
    # OUTSIDE the parenthetical, deliberately. main-health-monitor.yml anchors on
    # the exact shape `(exit=N, signal-shaped 128+n = SIGNAME, Nms)`; putting the
    # budget note inside it makes that grep miss and routes every terminated suite
    # to the generic "did not complete" arm. Measured — this comment exists because
    # the note was first written inside the parens and the monitor went blind.
    local _kb; _kb="$(_suite_budget_ms "$label")"
    local _bnote=""
    [[ -n "$_kb" ]] && _bnote=" This suite declares a ${_kb}ms budget, so compare the elapsed above against it before treating the duration as anomalous."
    echo "[KILLED] $label (exit=$rc, signal-shaped 128+$(( rc - 128 )) = SIG$(kill -l $(( rc - 128 )) 2>/dev/null), ${elapsed_ms}ms) — UNRESOLVED, not a failure: this runner did not measure what terminated it, and exit $rc is also what a suite calling exit($rc) reports.${_bnote}" >&2
    printf '%s\t%d\tKILLED%s\n' "$label" "$elapsed_ms" "$tmp_field" >> "${TEST_TIMING_LOG:-/dev/null}"
  else
    # rc 97 is the git-location tripwire (#7833), not an assertion failure. It means the runner
    # ABORTED before executing a single test because it started holding GIT_DIR (or a sibling), so
    # this suite's coverage was never obtained and the cause is the ENTRY POINT, not the diff. The
    # bare `[FAIL] <label> (<ms>)` line drops rc entirely, which made a tripwire abort
    # indistinguishable from a failed assertion — the tripwire's own rationale says 97 is
    # "distinctive… attributable at a glance", and that was not true of the one runner in this repo
    # that classifies exit codes.
    if (( rc == 97 )); then
      echo "[TRIPWIRE] $label (rc=97, ${elapsed_ms}ms) — the runner aborted on an inherited git-location environment; its coverage was NOT obtained. Fix the entry point that started it (see the FATAL block above for the exact unset), then re-run. This is not a failing assertion." >&2
      printf '%s\t%d\tTRIPWIRE%s\n' "$label" "$elapsed_ms" "$tmp_field" >> "${TEST_TIMING_LOG:-/dev/null}"
    else
      echo "[FAIL] $label (${elapsed_ms}ms)" >&2
      printf '%s\t%d\tFAIL%s\n' "$label" "$elapsed_ms" "$tmp_field" >> "${TEST_TIMING_LOG:-/dev/null}"
    fi
  fi
}

# A DECLINE IS A VERDICT, NOT AN ABSENCE (ADR-181).
#
# run_suite increments `suites` on ENTRY, so the older shape — wrapping the call in an `if` and
# echoing a notice on the else branch — silently removed the declined suite from the
# denominator. `N/N suites passed` then read IDENTICALLY whether a suite was deliberately gated
# or had been DE-REGISTERED, and the second is the #3366 class one level up: a suite running in
# zero runners behind a green summary. Counting the decline is what makes those two states
# distinguishable without reading the log body.
#
# A SIBLING of run_suite, deliberately NOT an option on it. scripts/lint-orphan-test-suites.sh
# anchors suite registration on the literal `run_suite ` token, and extracts the registered
# path from COMMAND position (the token after `bash`) on that line — so a
# `run_suite --skip-if-not-relevant "<paths>"` shape would let a path in the predicate list
# satisfy the registration check for a DIFFERENT suite than the one executed, and deleting that
# suite's real registration would still report `orphan test suites: none`. `skip_suite ` cannot
# match `^[[:space:]]*run_suite `, so it is invisible to that anchor by construction.
#
# $1 = label (must match the label the suite would have run under)
# $2 = machine-readable reason  $3 = the exact command that re-runs it
skip_suite() {
  local label="$1" reason="$2" rerun="$3"
  # The IDENTICAL filter run_suite carries, for the reason stated at _shard_selects: both
  # functions increment `suites`, so filtering only one makes per-leg denominators and the
  # epilogue's decline accounting disagree about how many registrations the leg owned.
  _shard_selects "$label" || return 0
  if (( _ENUMERATE == 1 )); then _shard_enumerate_declined_dispatch "$label" "$rerun"; return 0; fi
  suites=$((suites + 1))
  skipped=$((skipped + 1))
  echo ""
  echo "[skip] $label ($reason)"
  echo "      Nothing in this run is evidence for it. Re-run with:"
  echo "        $rerun"
  echo ""
  # LABELLED trailing field, never a bare positional one: field 3 already carries the `FAIL`
  # marker, so an unlabelled append would be positionally ambiguous across the ok, FAIL and
  # skip shapes. Same reasoning the tmp_delta= field above already applies.
  printf '%s\t%d\tskip=%s\n' "$label" 0 "$reason" >> "${TEST_TIMING_LOG:-/dev/null}"
}

# INFRA RELEVANCE DETECTION (#6730/#7014, converted from a boundary to a gate by #7103).
# This runner NOW COVERS apps/web-platform/infra/, by registering
# apps/web-platform/infra/run-registered-suites.sh as a nested suite (see the registration
# block near the end of this file). That runner DERIVES its list from
# .github/workflows/infra-validation.yml, so registering it — rather than globbing the
# suites — is what keeps this file and CI from forking.
#
# What survives from #6730/#7014 is the DETECTION, which now decides whether to RUN the
# infra runner instead of merely whether to print a notice about not running it. The
# original gap cost two sessions: a required check was RED behind a 223/223 green here
# (#6730), and an infra diff was validated by the wrong runner entirely (#6969) — both
# times "all tests pass" was read as evidence for infra the run never touched. A notice
# asking the reader to go run something else is a weaker fix than running it, which is why
# this became a gate.
#
# It still fires HERE rather than after the suites: the announcement is only actionable
# while there is still a decision to make, and at the end of a ~20-minute run the cost is
# already paid. A one-line restatement stays in the epilogue for readers who `tail` the log.
#
# Detection reads a VARIABLE, not a pipe into `grep -q`. Under this script's `set -o
# pipefail` a `producer | grep -q` pipeline reports non-zero when grep exits on a match
# while the producer is still writing — the producer takes SIGPIPE (141) and pipefail
# surfaces it — so the condition evaluates FALSE despite the match. What decides this is
# whether the producer's output exceeds the ~64 KiB pipe buffer, NOT where the match sits:
# measured on a 185-byte diff the old form matched correctly every time, and only went
# fail-open past roughly 1,300 changed paths. So the old form was not failing open on
# realistic diffs — but it made correctness a function of diff SIZE, and a herestring has
# no producer to kill. Do not generalise this to "an early match causes SIGPIPE"; that is
# the wrong rule and it was written here first.
#
# Detection failure is reported, never silently equated with "no infra in the diff". Both
# refs can legitimately fail to resolve (shallow clone, no `origin`, a fresh repo) and the
# earlier form's `2>/dev/null … || true` made that indistinguishable from a clean result —
# a fail-open sitting inside the very notice this block exists to deliver. Untracked files
# are included too: `git diff --name-only` never lists them, so a session that ADDS a new
# infra suite and runs this before committing got no notice at all.
#
# `grep -qF` without a `^` anchor, and `core.quotePath=false`: git C-quotes any path with
# non-ASCII or control characters onto a single leading-quote line, which moves the path
# off the start of the line and defeats an anchored match. Over-matching a path that merely
# CONTAINS the directory string errs toward showing the notice, which is the safe direction.
# The two refs answer DIFFERENT questions and only one of them is load-bearing. `HEAD` sees
# uncommitted work; `origin/main...HEAD` sees what the BRANCH changes, which is the question
# the notice is about. On a branch whose infra edits are already committed the HEAD diff is
# legitimately empty, so treating "either ref resolved" as success reports a confident
# no-infra verdict from the ref that could not have known — measured on a scratch repo with a
# committed infra file and no remote. Only the range ref's failure means "could not determine".
_diff_detect_ok=0
_diff_head_ok=0
_diff_names=""
if _diff_out="$(git -c core.quotePath=false diff --name-only HEAD 2>/dev/null)"; then
  _diff_head_ok=1
  _diff_names="${_diff_names}
${_diff_out}"
fi
if _diff_out="$(git -c core.quotePath=false diff --name-only origin/main...HEAD 2>/dev/null)"; then
  _diff_detect_ok=1
  _diff_names="${_diff_names}
${_diff_out}"
fi
# RENAME SOURCES. `--name-only` emits only the DESTINATION of a rename, so `git mv` on a declared
# predicate path leaves the OLD path — the one the array names — absent from the diff, and the
# battery declines on the single most destructive edit possible to its own SUT. `--name-status -M`
# emits `R100<TAB>old<TAB>new`, and since matching is substring-based over this whole blob, adding
# it makes BOTH paths matchable. (The narrow window this closes is a rename WITHOUT a matching
# array update; `lint-orphan-test-suites.sh` already reds loudly in the same run for that case, so
# it was never a silent green — this just stops the suite declining while that error prints.)
_diff_names="${_diff_names}
$(git -c core.quotePath=false diff --name-status -M HEAD 2>/dev/null || true)
$(git -c core.quotePath=false diff --name-status -M origin/main...HEAD 2>/dev/null || true)"
# WIDENED from `-- apps/web-platform/infra` to the union of every prefix the relevance
# predicates declare. The narrow form was correct while the only consumer was the infra notice;
# as a suite GATE it was a fail-open, because a brand-new UNTRACKED mutation target under
# scripts/ or .github/ was invisible here — so the session that ADDS a target and runs the gate
# before committing would have had the suite declined on the very diff that needed it.
_diff_names="${_diff_names}
$(git ls-files --others --exclude-standard -- "${TEST_RELEVANCE_PREFIXES[@]}" 2>/dev/null || true)"
# Affected mode ALSO appends the UNSCOPED untracked list (#8322): any untracked
# file can be an edge target — a brand-new suite file's own path is its
# self-edge, and a new file under a declared prefix must select the suite
# guarding that prefix. Scoped to the relevance prefixes, the affected axis
# would be blind to both. Expressed as a SECOND append rather than an if/else
# around the line above because test-all-infra-coverage-notice.test.sh
# extracts this assembly by awk range terminating at the first
# `git ls-files --others` line — reordering or wrapping the scoped line in a
# conditional truncates that extraction mid-statement. The scoped append under
# affected mode contributes only duplicates of what the unscoped one already
# lists, which substring matching makes a non-event.
# Under TEST_GROUP=affected the same untracked-files blind spot widens to the whole tree: a
# brand-new suite file or SUT that has never been `git add`ed must still select the suites
# covering it, and no curated prefix list enumerates "anywhere a test could live". Either
# affected axis trips the same unscoped append — as two separate blocks, because each
# axis's regression suite anchors on its own opener line, and the modes are now disjoint
# (TEST_GROUP=affected never arms _AFFECTED), so exactly one of these ever fires.
if (( _AFFECTED == 1 )); then
  _diff_names="${_diff_names}
$(git ls-files --others --exclude-standard 2>/dev/null || true)"
fi
if [[ "$TEST_GROUP" == "affected" ]]; then
  _diff_names="${_diff_names}
$(git ls-files --others --exclude-standard 2>/dev/null || true)"
fi

# Does this run's diff touch any of the given paths? Used to decline suites that guard code the
# diff does not reach. Substring match without a `^` anchor, matching the existing infra check:
# over-matching a path that merely CONTAINS the string errs toward RUNNING the suite, which is
# the safe direction.
#
# Reads a VARIABLE via a herestring, never `producer | grep -q`. Under this script's `set -o
# pipefail` that pipeline reports non-zero when grep exits on a match while the producer is
# still writing (SIGPIPE 141), which would make the condition evaluate FALSE despite the match —
# a fail-open whose likelihood scales with diff size. A herestring has no producer to kill.
_diff_touches() {
  # The two bypasses are UNCONDITIONAL early returns, not flags consulted later.
  #
  # Under CI a decline is therefore UNREACHABLE rather than merely detected. That is strictly
  # stronger than the assertion this replaced, and it is what keeps main-health-monitor green:
  # on `main` both diff refs resolve and return EMPTY, so _diff_detect_ok is 1 (the fail-SAFE
  # arm does not rescue it) and every gated suite would decline — an "assert no skips occurred"
  # design would have reddened that workflow every six hours.
  #
  # Written as explicit `if` blocks rather than `[[ … ]] && return 0`. Under this script's
  # `set -e` the short form's exit status depends on the CALL SITE — harmless inside an `if`
  # condition, an abort anywhere else — and a predicate that decides whether suites run must not
  # carry a landmine for the next caller.
  if [[ "${SOLEUR_TEST_FORCE_ALL:-}" == "1" ]]; then return 0; fi
  # --full (#8322): the whole battery is the ask, so no diff-based gate may
  # decline. Distinct from the FORCE_ALL arm above so the help text can name a
  # spelling an operator will actually find.
  if (( _FULL_GATE == 1 )); then return 0; fi
  if [[ -n "${CI:-}" ]]; then return 0; fi
  # Fail SAFE, not fail quiet: a diff the runner could not determine RUNS everything.
  #
  # BOTH arms, not just the range. The HEAD arm is what sees UNCOMMITTED work, and it can fail
  # independently — a sibling process holding `index.lock` while `git diff` refreshes the index is
  # the realistic case in this repo, where parallel worktrees are the documented workflow. With
  # only the range arm consulted, that failure is swallowed: the range looks clean, and the battery
  # declines on a working tree carrying exactly the edits it guards.
  if [[ "$_diff_detect_ok" == 0 || "$_diff_head_ok" == 0 ]]; then return 0; fi
  local p
  for p in "$@"; do
    # `[[ == ]]` with the operand quoted is a literal substring match — the
    # same semantics as the fixed-string grep it replaces, minus one fork +
    # herestring per edge per registration (the affected pre-pass calls this
    # ~440 times against multi-element edge sets).
    if [[ "$_diff_names" == *"$p"* ]]; then return 0; fi
  done
  return 1
}

# --- Affected classification (#8322) -----------------------------------------
#
# `_affected_classify <label> <argv...>` fills two globals: `_AC_CLASS` —
# `group` | `always_on` | `edge:<consumed|declared|derived>` | `unclassified` —
# and `_AC_EDGES`, the path set an `edge:*` class tests against `_diff_names`.
# The precedence order is load-bearing:
#
#   0. group — an explicit TEST_GROUP=<g> ask bypasses the affected axis
#      ENTIRELY: the operator named the group, so every registration that
#      reaches this point selects. Without this rung TEST_GROUP=infra would
#      edge-test the infra runner against a diff that does not touch infra,
#      decline it, and let `_infra_ran` record coverage for a suite that never
#      executed — the false-green this ordering exists to close.
#   1. always_on — verdict is a property of the whole tree, never of a diff.
#   2. consumed — the five relevance arrays are the affected edge: the diff
#      that makes the suite relevant is the diff that selects it.
#   3. declared — AFFECTED_<LABEL>_PATHS in scripts/lib/test-affected-paths.sh.
#   4. derived — argv literals, `-c` payload paths, name-stem conventions, and
#      the source/import closure of the suite file itself.
#
#   Rungs 2–3 UNION with rung 4 rather than replace it: a declared array
#   records only what derivation could not reach AT WRITE TIME, so a
#   dependency the suite gains afterwards must widen its edge set — never be
#   shadowed by the declaration into a silent decline. The label keeps
#   provenance; the edge set is declared ∪ derived.
#   5. unclassified — SELECTS anyway. A suite the derivation cannot reach runs
#      rather than skipping; the census linter is what makes that state loud.
#
# Bash 3.2: no `declare -A`, no `declare -n`. Edge arrays are resolved by NAME
# through eval (the linter uses the same idiom), and per-registration state is
# ordinal-indexed on `_shard_ordinal`.

_AC_CLASS=""
_AC_EDGES=()

_affected_in_list() {
  local _l="$1"; shift
  local _e
  for _e in "$@"; do
    if [[ "$_e" == "$_l" ]]; then return 0; fi
  done
  return 1
}

# Resolve an array by NAME into _AC_EDGES. eval is the bash-3.2-safe indirection;
# the element expansion is double-quoted inside so labels/edges containing
# spaces survive verbatim.
_affected_resolve_edges() {
  eval "_AC_EDGES=( \${$1[@]+\"\${$1[@]}\"} )"
}

# Append an edge if it resolves inside the repo and is not already present.
# `[[ -e ]]` is the whole test: argv words, `-c` payload tokens and resolved
# source/import paths are all filtered through it, so garbage never lands in
# the edge set and a DIRECTORY entry acts as a prefix edge under the substring
# match _diff_touches uses.
_affected_add_edge() {
  local _p="$1"
  [[ -n "$_p" && -e "$_p" ]] || return 0
  _affected_in_list "$_p" ${_AC_EDGES[@]+"${_AC_EDGES[@]}"} && return 0
  _AC_EDGES+=("$_p")
}

# Cheap relative-path normaliser: collapses `./` and `seg/../` enough to make
# `source ../lib/x.sh`-style references land repo-relative. Bounded loop, never
# recursive; a path that escapes the repo root is dropped by the caller's
# `-e` test (or by the leading-`/`/`..` rejection below).
_affected_normpath() {
  # Result via _NP, not stdout: this runs per extracted source line, and a
  # command-substitution call would fork once per line for a transform that is
  # pure bash except in the (rare) dotdot case.
  _NP="$1"
  _NP="${_NP#./}"
  local _i
  for _i in 1 2 3 4 5 6; do
    case "$_NP" in
      *../*|*/..)
        _NP="$(printf '%s' "$_NP" | sed -e 's|^\./||' -e 's|/\./|/|g' -e 's|[^/][^/]*/\.\./||g' -e 's|[^/][^/]*/\.\.$||')"
        ;;
      *) break ;;
    esac
  done
}

# The tail shared by both extraction passes: variable substitution, absolute/
# escape rejection, normalisation, dedup-add. A dotted name that resolves to
# nothing literal is read as a Python module (`from pkg.mod import x`,
# `import pkg.mod`) and re-tried as pkg/mod.py — Python imports are unquoted,
# which the quoted-import arms of the sed chain never see.
_affected_edge_token() {
  local _p="$1"
  # `$(dirname …)` substitutions run BEFORE the quote-strip: the token may
  # legitimately carry quotes inside `$(dirname "$0")`, and stripping first
  # would cut it to `$(dirname` — which is how these tokens arrive.
  _p="${_p//\$\(dirname \"\$\{BASH_SOURCE\[0\]\}\"\)/$_fdir}"
  _p="${_p//\$\(dirname \"\$0\"\)/$_fdir}"
  # `$(cd "$(dirname …)" && pwd -P)/rest` — the physical-path idiom — resolves
  # to the file's own directory too. The glob is greedy; on the single-`$(cd)`
  # tokens the extractor emits that is exactly the span to replace.
  _p="${_p//\$\(cd*pwd*-P\)/$_fdir}"
  _p="${_p//\$\(cd*pwd\)/$_fdir}"
  _p="${_p#\"}"; _p="${_p#\'}"
  _p="${_p%%[\"\']*}"
  _p="${_p//\$HERE/$_fdir}"
  _p="${_p//\$\{HERE\}/$_fdir}"
  _p="${_p//\$SCRIPT_DIR/$_fdir}"
  _p="${_p//\$\{SCRIPT_DIR\}/$_fdir}"
  _p="${_p//\$REPO_ROOT/.}"
  _p="${_p//\$\{REPO_ROOT\}/.}"
  _p="${_p//\$ROOT_DIR/.}"
  _p="${_p//\$\(dirname \"\$\{BASH_SOURCE\[0\]\}\"\)/$_fdir}"
  _p="${_p//\$\(dirname \"\$0\"\)/$_fdir}"
  _p="${_p#"$PWD"/}"
  case "$_p" in /*|../*|..|.) return 0 ;; esac
  _affected_normpath "$_p"; _p="$_NP"
  case "$_p" in ../*|..|.) return 0 ;; esac
  if [[ ! -e "$_p" && "$_p" =~ ^[a-zA-Z0-9_]+(\.[a-zA-Z0-9_]+)+$ ]]; then
    _p="$(printf '%s' "$_p" | tr '.' '/').py"
  fi
  _affected_buf_add "$_p"
}

# The source/import closure of one file: `source X`, `. X`, `from 'X'`,
# `import 'X'`, `import pkg.mod`, `require('X')`, plus variable-indirect
# invocations (`source "$GATE"`, `bash "$POLL"`, `python3 "$MOD"`) resolved
# against VAR=literal assignments in the same file — the tests/scripts
# harness convention carries its SUT behind exactly those names. `$HERE`,
# `$SCRIPT_DIR`, `$REPO_ROOT` and `$(dirname …)` resolve against the file's
# own directory; repo-root variables resolve to the runner's cwd
# (registrations run from the repo root).
# File-level memo: a file's edge set depends only on the file, but the closure
# walk revisits the same shared helpers (gate-suite-harness, test-helpers) once
# per suite — ~440 suites × ~10 shared files each re-scanned is the difference
# between seconds and minutes. Parallel arrays, not assoc: bash 3.2.
_FE_FILES=()
_FE_EDGES=()

# `_FE_BUF` is the per-file accumulator: _affected_file_edges_uncached and
# _affected_edge_token append through _affected_buf_add so the CACHE records
# the file's complete edge set — recording only what survived _AC_EDGES dedup
# would silently drop edges another suite already contributed, and replaying
# that for a later suite would under-edge it.
_FE_BUF=()
_affected_buf_add() {
  local _p="$1"
  [[ -n "$_p" && -e "$_p" ]] || return 0
  _affected_in_list "$_p" ${_FE_BUF[@]+"${_FE_BUF[@]}"} && return 0
  _FE_BUF+=("$_p")
}

# Substitute only the vars actually PRESENT in the string against the file's
# _vn/_vv map — a blind every-var sweep is ~60 expansions per token and was
# the dominant pre-pass cost. Re-loops so a value carrying another $VAR also
# resolves; the 12-iteration cap makes a self-referential value harmless.
_RV=""
_affected_resolve_vars() {
  _RV="$1"
  local _want _found _vi _iter=0
  while [[ "$_RV" =~ \$\{?([A-Za-z_][A-Za-z0-9_]*) ]] && (( _iter < 12 )); do
    _iter=$(( _iter + 1 ))
    _want="${BASH_REMATCH[1]}"
    _found=0
    for (( _vi=0; _vi<${#_vn[@]}; _vi++ )); do
      if [[ "${_vn[$_vi]}" == "$_want" ]]; then
        _RV="${_RV//\$${_want}/${_vv[$_vi]}}"
        _RV="${_RV//\$\{${_want}\}/${_vv[$_vi]}}"
        _found=1
        break
      fi
    done
    (( _found == 0 )) && break
  done
  # The while exits on a FALSE `=~` — status 1 — which under `set -e` aborts
  # any caller using this as a plain statement. Always return 0.
  return 0
}

_affected_file_edges() {
  local _f="$1"
  [[ -f "$_f" ]] || return 0
  local _ci
  for (( _ci=0; _ci<${#_FE_FILES[@]}; _ci++ )); do
    if [[ "${_FE_FILES[$_ci]}" == "$_f" ]]; then
      local _ce
      while IFS= read -r _ce; do
        _affected_add_edge "$_ce"
      done <<< "${_FE_EDGES[$_ci]}"
      return 0
    fi
  done
  _FE_BUF=()
  _affected_file_edges_uncached "$_f"
  local _j _joined=""
  for _j in ${_FE_BUF[@]+"${_FE_BUF[@]}"}; do
    _affected_add_edge "$_j"
    _joined+="$_j"$'\n'
  done
  _FE_FILES+=("$_f")
  _FE_EDGES+=("$_joined")
}

_affected_file_edges_uncached() {
  local _f="$1"
  local _fdir
  case "$_f" in */*) _fdir="${_f%/*}" ;; *) _fdir="." ;; esac
  local _p
  # One sed pass per FILE, not per line — the same -e chain, applied to the
  # stream. At ~440 registrations each fanning out through helpers, per-line
  # subshell+sed pairs were the pre-pass's dominant fork cost.
  while IFS= read -r _p; do
    _affected_edge_token "$_p"
  done < <(grep -hE '(^|[[:space:]])(source|\.)[[:space:]]+|from[[:space:]]+["'"'"']|require\(|import[[:space:]]+["'"'"']|import\(|load[[:space:]]+|^[[:space:]]*(import|from)[[:space:]]+[a-zA-Z0-9_.]' "$_f" 2>/dev/null | sed -E \
      -e "s/^.*(source|\.)[[:space:]]+['\"]?(\\\$\\(dirname[^)]*\\)[^'\"[:space:]]*).*/\2/" \
      -e "s/^.*(source|\.)[[:space:]]+['\"]?([^'\"[:space:]]+).*/\2/" \
      -e "s/^.*from[[:space:]]+['\"]([^'\"]+).*/\1/" \
      -e "s/^.*import[[:space:]]+['\"]([^'\"]+).*/\1/" \
      -e "s/^.*(require|import)\\(['\"]([^'\"]+).*/\2/" \
      -e "s/^.*load[[:space:]]+['\"]([^'\"]+).*/\1/" \
      -e "s|^[[:space:]]*from[[:space:]]+([a-zA-Z0-9_.]+)[[:space:]]+import[[:space:]].*|\1|" \
      -e "s|^[[:space:]]*import[[:space:]]+([a-zA-Z0-9_.]+).*|\1|")
  # Variable-indirect invocations. VAR=literal assignments are collected from
  # the same file (values keep their own $REPO_ROOT-style vars for
  # _affected_edge_token to resolve); invocation sites carrying a $VAR then
  # substitute against that map. Unresolvable vars die at the -e filter.
  local -a _vn=() _vv=()
  local _vl
  while IFS= read -r _vl; do
    # Greedy `"(.*)"` so a nested quote inside `$(dirname "$0")` survives —
    # `[^"]*` would cut the value at the inner quote. The unquoted fallback
    # stops at whitespace; `$(dirname "$0")`-style values are always quoted.
    if [[ "$_vl" =~ ^[[:space:]]*(export[[:space:]]+|declare[[:space:]]+-[a-zA-Z]+[[:space:]]+)*([A-Za-z_][A-Za-z0-9_]*)=\"(.*)\" ]]; then
      _vn+=("${BASH_REMATCH[2]}")
      _vv+=("${BASH_REMATCH[3]}")
    elif [[ "$_vl" =~ ^[[:space:]]*(export[[:space:]]+|declare[[:space:]]+-[a-zA-Z]+[[:space:]]+)*([A-Za-z_][A-Za-z0-9_]*)=([^[:space:]\"\'\']+) ]]; then
      _vn+=("${BASH_REMATCH[2]}")
      _vv+=("${BASH_REMATCH[3]}")
    fi
  done < <(grep -hE '^[[:space:]]*(export[[:space:]]+)?(declare[[:space:]]+-[a-zA-Z]+[[:space:]]+)?[A-Za-z_][A-Za-z0-9_]*=' "$_f" 2>/dev/null)
  # Pass 2: every WHITESPACE-SEPARATED token on an invocation line, not just
  # the first argv — `python3 - "$REPO_ROOT/lefthook.yml"` carries its edge in
  # position 2. `(`, `&`, `|` and `;` in the prefix class catch invocations
  # nested in command substitutions and pipelines. Vars resolve first so
  # `bash "$POLL"` lands its value.
  local _l _tok
  while IFS= read -r _l; do
    _affected_resolve_vars "$_l"; _l="$_RV"
    # `read -ra`, never `for tok in $_l`: a bare expansion would glob `*`-shaped
    # tokens (`find . -name "*.sh"`) against cwd into spurious edges. The
    # `/`-or-`$` early-out keeps the per-token substitution chain off the ~95%
    # of argv that are flags, numbers and keywords.
    local -a _toks=()
    IFS=' ' read -ra _toks <<< "$_l"
    for _tok in ${_toks[@]+"${_toks[@]}"}; do
      [[ "$_tok" == */* || "$_tok" == *\$* ]] || continue
      _affected_edge_token "$_tok"
    done
  done < <(grep -hE '(^|[[:space:](&|;])(source|\.|bash|sh|python3?|node|bun)[[:space:]]+["'"'"']?[^[:space:]]' "$_f" 2>/dev/null)
  # Pass 3: `$VAR/path` tokens ANYWHERE — the SUT path is often an argument two
  # positions deep, a heredoc payload, or a redirected operand no invocation
  # grep can see. Substitution resolves the vars pass 2 already collected;
  # tokens still carrying an unresolvable `$` die at the -e filter.
  while IFS= read -r _p; do
    _affected_resolve_vars "$_p"; _p="$_RV"
    _affected_edge_token "$_p"
  done < <(grep -ohE '\$[A-Za-z_{][A-Za-z0-9_}]*(/[A-Za-z0-9_.$}{-]+)+' "$_f" 2>/dev/null | sort -u)
}

# Derivation: argv literals + `-c` payload paths + name-stem + closure.
_affected_derive() {
  local _label="$1"; shift
  _AC_EDGES=()
  local _tok _suite_file="" _prev=""
  for _tok in "$@"; do
    case "$_prev" in
      -c|-ec|-lc)
        # A `-c` payload is a script string, not a path: word-split it and keep
        # the tokens that resolve — `cd apps/web-platform && npm run x` yields
        # the directory edge, which is the whole point of looking inside.
        local _w
        for _w in $_tok; do
          _w="${_w%\"}"; _w="${_w#\"}"; _w="${_w%\'}"; _w="${_w#\'}"
          _affected_add_edge "$_w"
        done
        ;;
    esac
    _prev="$_tok"
    case "$_tok" in
      /*)
        # An absolute path never substring-matches a repo-relative diff name —
        # adding it would mint a dead edge that can only decline.
        ;;
      *.sh|*.ts|*.tsx|*.mjs|*.js|*.py|*.rb)
        _affected_add_edge "$_tok"
        [[ -z "$_suite_file" && -f "$_tok" ]] && _suite_file="$_tok"
        ;;
      *.*)
        # Literal first (`config.yml` resolves as itself); THEN the
        # dotted-module reading (`tests.scripts.test_x` -> tests/scripts/…),
        # which only lands when the literal did not.
        _affected_add_edge "$_tok"
        if [[ ! -e "$_tok" && "$_tok" =~ ^[a-zA-Z0-9_]+(\.[a-zA-Z0-9_]+)+$ ]]; then
          local _mod; _mod="$(printf '%s' "$_tok" | tr '.' '/')"
          _affected_add_edge "$_mod"
          _affected_add_edge "$_mod.py"
          _affected_add_edge "$_mod.sh"
          [[ -z "$_suite_file" && -f "$_mod.py" ]] && _suite_file="$_mod.py"
        fi
        ;;
      *)
        # Any other token that happens to resolve (a directory operand like
        # `bun test plugins/soleur/`, an extensionless script) is an edge;
        # tokens that do not resolve are dropped by the -e test.
        _affected_add_edge "$_tok"
        ;;
    esac
  done
  if [[ -n "$_suite_file" ]]; then
    local _dir _base _stem
    case "$_suite_file" in */*) _dir="${_suite_file%/*}" ;; *) _dir="." ;; esac
    _base="${_suite_file##*/}"
    case "$_base" in
      *.test.sh)            _stem="${_base%.test.sh}.sh" ;;
      *.test.ts|*.test.tsx) _stem="${_base%.test.*}" ;;
      *.test.py)            _stem="${_base%.test.py}.py" ;;
      test-*.sh|test_*.sh)  _stem="${_base#test?}" ;;
      test-*.py|test_*.py)  _stem="${_base#test?}" ;;
      *)                    _stem="" ;;
    esac
    if [[ -n "$_stem" ]]; then
      # The SUT's extension does not have to match the test's — a .test.sh can
      # guard an .mjs/.ts/.py helper — so fan the bare stem across every SUT
      # extension this repo's suites actually target, at each conventional
      # location: same dir, the dir's lib/, repo scripts/, and the test/
      # sibling scripts/ dir (plugins/soleur/test/X ↔ plugins/soleur/scripts/X).
      # `-e` inside add_edge drops every candidate that does not exist.
      local _bare="${_stem%.*}"
      local _cand_dir
      for _cand_dir in "$_dir" "$_dir/lib" "scripts" "${_dir%/test}/scripts"; do
        local _ext
        for _ext in sh ts tsx mjs js py rb; do
          _affected_add_edge "$_cand_dir/$_bare.$_ext"
        done
      done
      _affected_add_edge "$_dir/$_stem"
      _affected_add_edge "$_dir/lib/$_stem"
      _affected_add_edge "scripts/$_stem"
    fi
    # Print-mode early-out: the receipt needs only the CLASS, and once any
    # non-self edge exists the class is edge:derived no matter what the
    # closure would add — the closure's only decision-relevant output is the
    # self-only/unclassified distinction. Skipping it here removes the whole
    # file-scan cost for suites whose argv/stem already prove reachability.
    # Execution mode keeps the full closure: selection needs the edge set.
    if (( _PRINT_AFFECTED == 1 )); then
      local _e _ns=0
      for _e in ${_AC_EDGES[@]+"${_AC_EDGES[@]}"}; do
        [[ "$_e" == "$_suite_file" ]] || { _ns=1; break; }
      done
      if (( _ns == 1 )); then _AC_SUITE_FILE="$_suite_file"; return 0; fi
    fi
    # Closure, bounded: follow source/import edges one level at a time.
    local -a _queue=("$_suite_file") _seen=("$_suite_file")
    local _depth=0
    while (( ${#_queue[@]} > 0 && _depth < 8 )); do
      # Deleted-cwd re-check inside the one multi-iteration site of a single
      # registration's classify (#8761) — same probe as _shard_selects.
      [[ -d "$PWD" ]] || _wt_missing_die
      _depth=$(( _depth + 1 ))
      local -a _next=()
      local _f
      for _f in "${_queue[@]}"; do
        local _pre_n=${#_AC_EDGES[@]}
        _affected_file_edges "$_f"
        local _i _new
        for (( _i=_pre_n; _i<${#_AC_EDGES[@]}; _i++ )); do
          _new="${_AC_EDGES[$_i]}"
          if [[ -f "$_new" ]] && ! _affected_in_list "$_new" "${_seen[@]+"${_seen[@]}"}"; then
            _seen+=("$_new"); _next+=("$_new")
          fi
        done
      done
      _queue=(${_next[@]+"${_next[@]}"})
    done
  fi
  # Exported for the classifier's self-only check: a derived edge set that
  # contains nothing but the suite's own file proves nothing about which
  # diffs reach it.
  _AC_SUITE_FILE="$_suite_file"
}

_affected_classify() {
  local _label="$1"; shift
  _AC_CLASS=""
  _AC_EDGES=()
  _AC_SUITE_FILE=""

  if [[ "$TEST_GROUP" != "all" ]]; then _AC_CLASS="group"; return 0; fi
  if _affected_in_list "$_label" ${ALWAYS_ON_SUITES[@]+"${ALWAYS_ON_SUITES[@]}"}; then
    _AC_CLASS="always_on"; return 0
  fi
  local _m
  for _m in ${AFFECTED_CONSUMED_EDGES[@]+"${AFFECTED_CONSUMED_EDGES[@]}"}; do
    if [[ "${_m%%|*}" == "$_label" ]]; then
      _affected_resolve_edges "${_m#*|}"
      _AC_CLASS="edge:consumed"; break
    fi
  done
  if [[ -z "$_AC_CLASS" ]]; then
    local _arr _u
    # One fork, not a tr|tr|sed pipeline — and the SAME normalisation the
    # census linter applies (uppercase, non-alnum to _, leading _ stripped): the
    # two must compute the same name for the same label or a declared array is
    # invisible to exactly one of them.
    _u="$(printf '%s' "$_label" | tr 'a-z' 'A-Z')"
    _u="${_u//[!A-Z0-9]/_}"
    _u="${_u#_}"
    _arr="AFFECTED_${_u}_PATHS"
    if declare -p "$_arr" >/dev/null 2>&1; then
      _affected_resolve_edges "$_arr"
      _AC_CLASS="edge:declared"
    fi
  fi
  if [[ -n "$_AC_CLASS" ]]; then
    # Union, not shadow: buffer the declared/consumed edges, derive the suite's
    # reachable set, then re-add the declared entries so the edge set is
    # declared ∪ derived. A suite that gains a dependency tomorrow selects on
    # it even though its array predates the dependency. In print mode the union
    # is skipped: the receipt carries only the class, and _AC_EDGES is read
    # nowhere on that path — the derive is the walk's entire cost.
    if (( _PRINT_AFFECTED == 0 )); then
      local _decl=( ${_AC_EDGES[@]+"${_AC_EDGES[@]}"} ) _e
      _affected_derive "$_label" "$@"
      for _e in ${_decl[@]+"${_decl[@]}"}; do _affected_add_edge "$_e"; done
    fi
    return 0
  fi
  _affected_derive "$_label" "$@"
  if (( ${#_AC_EDGES[@]} == 0 )); then _AC_CLASS="unclassified"; return 0; fi
  _AC_CLASS="edge:derived"
  # A derived edge set containing ONLY the suite's own file is derivation in
  # name only — it proves nothing about which diffs reach the suite (the SUT
  # was invoked through a subprocess or an unresolvable $VAR). Declining it
  # would be silent under-coverage: report it as unclassified so it selects
  # fail-safe AND the census flags it for a real declared edge.
  if [[ -n "${_AC_SUITE_FILE:-}" ]]; then
    local _e _nonself=0
    for _e in "${_AC_EDGES[@]}"; do
      [[ "$_e" == "$_AC_SUITE_FILE" ]] || { _nonself=1; break; }
    done
    (( _nonself == 0 )) && _AC_CLASS="unclassified"
  fi
  return 0
}

# Print-mode receipt. Emitted from the enumerate arm of run_suite so the census
# linter — and the mutation battery's arms — read the same classification the
# executing chokepoint would apply, without a second code path that could drift.
_affected_emit_receipt() {
  local _label="$1"; shift
  _affected_classify "$_label" "$@"
  printf 'AFFECTED_CLASS\t%s\t%s\n' "$_label" "$_AC_CLASS"
}

# --- TEST_GROUP=affected: mechanical diff-scoped selection -------------------------------
#
# The premise: a full local battery holds the repo-global advisory lock for ~45 minutes
# uncontended (and has measured 5787s contended), so three sessions working three unrelated
# diffs serialise into each other even though each only needs its own coverage. The skills
# already told agents to "run the shards your diff touches", but that left the mapping from
# diff to suites as hand-derived prose — the failure mode this file exists to remove is a
# paragraph of agent discretion standing where a mechanism belongs.
#
# `_suite_affected` is that mechanism. run_suite consults it once per registration, AFTER
# _shard_selects; a negative verdict takes the counted-decline path, so the summary keeps
# the declined suites in its denominator and prints each one as `[skip] (affected)`.
#
# The predicate answers one question: can any signal tie this suite to a changed path?
# FOUR signals, each one a distinct claim:
#
#   1. ARGV PATH CONTAINMENT — the suite's own file changed, or an argv element names a
#      path the diff touches (the `-live` linters carry their SUT and inputs in argv, e.g.
#      `python3 scripts/lint-rule-ids.py … AGENTS.md`, and `bun test plugins/soleur/`
#      carries its corpus dir as a prefix). Substring, same convention as _diff_touches:
#      over-matching runs the suite, which is the safe direction.
#   2. CONTENT REFERENCE — the suite file greps a changed path, its last two components,
#      or its basename when that basename is distinctive (multi-word stems only: a bare
#      `SKILL.md`/`index.ts` pattern would re-select most of the corpus and convert a
#      scoped run back into a battery). This is the strongest signal that a suite
#      exercises a differently-named SUT — the file has to mention what it drives.
#   3. STEM EQUALITY — the repo's test-naming conventions, normalised: `foo.test.sh`,
#      `test-foo.sh`, `test_foo.py` all stem to `foo`, matching a changed `foo.*`.
#   4. CENSUS BACKSTOP — a suite that enumerates repository state (git ls-files, tree
#      globbing, baseline ratchets, whole-diff assertions against origin/main) can never
#      be proven unaffected by a path match: its subject IS the repo. It always runs.
#
# …and three overrides, each declared rather than derived:
#
#   EXEMPT LABELS. Six registrations carry their own _diff_touches/_infra_in_diff gate at
#   the call site — a curated predicate strictly better-informed than a generic file
#   match. When such a gate says run, run_suite is called and this predicate must not
#   second-guess it; when it says no, skip_suite is called and this predicate never sees
#   the label. `apps/web-platform [repo-wide+component]` is exempt for the other reason:
#   it is never gated BY DESIGN (its subject is the repository — it exists to catch drift
#   in exactly the diffs that name no app file, the same class a path selector cannot
#   prove safe).
#
#   FAIL-SAFE. Same contract as _diff_touches: SOLEUR_TEST_FORCE_ALL, CI, or an
#   undeterminable diff each run everything. The CI arm matters even though no workflow
#   sets this group — if one ever does, the required matrix must not silently shrink.
#
#   UNDECIDABLE. An argv carrying no path-like token at all runs — a selector that cannot
#   name a suite's subject does not get to decline it.
#
# Deliberately NOT here: a hand-maintained suite→path map. The registration lines are the
# map — the selector reads the same argv the runner executes, so it cannot drift from what
# is registered, which is the property lint-orphan-test-suites.sh enforces for discovery.

# Normalise a basename to its subject stem: strip test-affixes and extensions so the
# repo's `foo.test.sh` / `test-foo.sh` / `test_foo.py` conventions all land on `foo`.
_aff_stem() {
  local b="${1##*/}"
  b="${b%.test.*}"                    # foo.test.sh -> foo
  b="${b%.*}"                         # foo.sh -> foo ; test_foo.py -> test_foo
  b="${b#test-}"; b="${b#test_}"      # test-foo -> foo ; test_foo -> foo
  b="${b%-test}"; b="${b%_test}"
  printf '%s' "$b"
}

# Fixed-string content-grep patterns derived from the diff (full path, last-two-components,
# distinctive basename) and the diff's stem set for signal 3. Built ONCE, not per-suite —
# the per-call cost of this predicate stays a couple of greps against ~500 registrations.
# Both are consumed only under TEST_GROUP=affected; declared unconditionally so a sandbox
# spliced before this block still has the variables bound under `set -u`.
_AFFECT_PATTERNS=""
_AFFECT_STEMS=""
if [[ "$TEST_GROUP" == "affected" ]]; then
  _affect_line="" _affect_tok="" _affect_dir="" _affect_stem_v=""
  while IFS= read -r _affect_line; do
    # `_diff_names` mixes bare paths (--name-only, ls-files) with `STATUS\tpath` and
    # `R100\told\tnew` rows (--name-status). Word-splitting keeps every path field and
    # drops the status tokens, which carry no `/` and no extension.
    # `read -a`, not `for tok in $line`: word-splitting without pathname expansion, so a
    # filename or argv token carrying a glob metacharacter cannot expand against cwd.
    _affect_words=()
    IFS=$' \t' read -r -a _affect_words <<< "$_affect_line" || true
    for _affect_tok in "${_affect_words[@]:-}"; do
      case "$_affect_tok" in
        */*|*.*) ;;
        *) continue ;;
      esac
      _AFFECT_PATTERNS="${_AFFECT_PATTERNS}${_affect_tok}
"
      _affect_dir="${_affect_tok%/*}"
      if [[ "$_affect_dir" != "$_affect_tok" ]]; then
        _AFFECT_PATTERNS="${_AFFECT_PATTERNS}${_affect_dir##*/}/${_affect_tok##*/}
"
      fi
      _affect_stem_v="$(_aff_stem "$_affect_tok")"
      _AFFECT_STEMS="${_AFFECT_STEMS}${_affect_stem_v}
"
      # Basename as a content pattern only when the stem carries a separator or digit —
      # `admin-merge-ready.sh` names its subject; `SKILL.md`/`index.ts`/`package.json`
      # would match suites that merely mention the generic name.
      case "$_affect_stem_v" in
        *[-_0-9]*) _AFFECT_PATTERNS="${_AFFECT_PATTERNS}${_affect_tok##*/}
" ;;
      esac
    done
  done <<<"$_diff_names"
fi

_suite_affected() {
  local label="$1"; shift
  # EXEMPT LABELS — see the design comment above. These either carry their own curated
  # gate upstream of run_suite, or are never gated by design.
  case "$label" in
    "tests/scripts/registry-gate-mutation-battery"|"apps/web-platform [unit]"|"apps/web-platform [repo-wide+component]"|"scripts/cf-tunnel-liveness-gate-mutations"|"plugins/soleur/test/c4-from-components.test.sh"|".github/scripts/test/run-all.sh"|"apps/web-platform/infra/run-registered-suites.sh")
      return 0 ;;
  esac
  # Explicit `if` blocks, never `[[ ]] && return 0` — same set -e call-site hazard as
  # _diff_touches documents.
  if [[ "${SOLEUR_TEST_FORCE_ALL:-}" == "1" ]]; then return 0; fi
  if [[ -n "${CI:-}" ]]; then return 0; fi
  if [[ "$_diff_detect_ok" == 0 || "$_diff_head_ok" == 0 ]]; then return 0; fi

  local a t stem saw_path=0
  local -a _words
  for a in "$@"; do
    # Split composite argv elements too — `env VAR= bash -c 'cd dir && …'` carries its
    # real path argument inside the -c payload. `read -a` word-splits WITHOUT pathname
    # expansion, so a payload containing a glob metacharacter cannot expand against cwd.
    _words=()
    while IFS=$' \t' read -r -a _words; do
    for t in "${_words[@]:-}"; do
      t="${t%\"}"; t="${t#\"}"; t="${t%\'}"; t="${t#\'}"; t="${t%;}"
      t="${t#./}"                       # git emits clean paths; ./x.sh never substring-matches x.sh
      case "$t" in
        -*|*=*) continue ;;   # flags and env assignments are never paths
        *[a-z_].[a-z_]*.[a-z_]*)
          # `python3 -m unittest tests.scripts.test_foo` carries a DOTTED module, not a
          # path — translate it so it lands in the same matching space as its file.
          if [[ "$t" != */* && "$t" != *.py && "$t" != *.ts && "$t" != *.sh && "$t" != *.mjs && "$t" != *.js && "$t" != *.md ]]; then
            t="${t//.//}.py"
          fi ;;
      esac
      case "$t" in
        */*|*.sh|*.py|*.ts|*.tsx|*.mjs|*.cjs|*.jsx|*.js|*.yml|*.yaml|*.json|*.jsonl|*.md|*.c4|*.likec4|*.tf|*.txt|test_*) ;;
        *) continue ;;
      esac
      saw_path=1
      # Signal 1 — argv path containment. Covers the suite file itself being in the
      # diff, SUT/fixture argv elements, and directory argv like `plugins/soleur/`
      # prefix-matching a diff path beneath it.
      if grep -qF -- "$t" <<<"$_diff_names"; then return 0; fi
      if [[ -d "$t" ]]; then
        # Directory argv (`bun test <dir>/`): the corpus is the tree, so a suite file
        # beneath it that NAMES a changed path selects the suite too.
        # `${var%$'\n'}` strips the trailing newline each append leaves: a herestring
        # adds one back, so the pattern list ends with an EMPTY LINE — and an empty
        # fixed-string pattern matches every line, silently disabling the signal.
        if [[ -n "$_AFFECT_PATTERNS" ]] \
          && grep -rqFf - -- "$t" <<<"${_AFFECT_PATTERNS%$'\n'}" 2>/dev/null; then return 0; fi
        continue
      fi
      if [[ -f "$t" ]]; then
        # Signal 4 — census backstop. A suite that enumerates repository state is
        # affected by construction; a path selector cannot prove it safe to decline.
        # The census set is deliberately broad and multi-language: shell enumerators
        # (git ls-files/ls-tree/diff/status, rg --files, find, glob-expanded for-loops,
        # baseline ratchets, origin/main comparisons) and the Python/JS equivalents the
        # -live linters actually use (rglob, os.walk/listdir/scandir, iterdir, subprocess,
        # globSync, readdirSync). Over-matching costs a suite run; under-matching here is
        # the false-decline class this signal exists to prevent — a corpus scanner declined
        # by a path match it could never satisfy.
        if grep -qE 'git ls-files|git grep|git ls-tree|git diff|git status|origin/main|baseline\.txt|rg --files|rg -l |find |for [a-zA-Z_]+ in [^|;]*\*|glob\.glob|rglob|os\.walk|os\.listdir|os\.scandir|iterdir|subprocess|readdirSync|globSync|readdir\(|fast-glob|tinyglobby' -- "$t"; then return 0; fi
        # Signal 2 — the suite file names a changed path: it exercises it. Same
        # empty-pattern-line hazard as the directory corpus grep above.
        if [[ -n "$_AFFECT_PATTERNS" ]] \
          && grep -qFf - -- "$t" <<<"${_AFFECT_PATTERNS%$'\n'}"; then return 0; fi
        # Signal 3 — stem convention: foo.test.sh ↔ foo.sh, test_foo.py ↔ foo.py.
        stem="$(_aff_stem "$t")"
        if [[ -n "$stem" ]] && grep -qxF -- "$stem" <<<"$_AFFECT_STEMS"; then return 0; fi
      fi
    done
    done <<<"$a"
  done
  # UNDECIDABLE — argv carried nothing path-like, so there is no signal to decline on.
  if (( saw_path == 0 )); then return 0; fi
  return 1
}

# Counted at the run_suite chokepoint, alongside but separate from `_relevance_declined`:
# the epilogue's FORCE_ALL lever names "relevance-gated" suites (the curated call sites
# that counter tracks), while an affected decline's honest recovery is the full battery.
_affected_declined=0

# Counted at the RELEVANCE call sites only. `skipped` also carries the infra runner's incident and
# not_in_diff declines, which SOLEUR_TEST_FORCE_ALL cannot force -- see the epilogue lever.
_relevance_declined=0

_infra_in_diff=0
# Two prefixes, not one. The infra guards assert against
# `.github/workflows/apply-web-platform-infra.yml` as well as against the `.tf`
# files -- `apex-single-node-replace.test.sh` reads its `-target=` allow-list --
# so a PR editing ONLY that workflow could drop an allow-list entry while this
# runner declined the whole infra suite as not-in-diff (#7640).
if grep -qF 'apps/web-platform/infra/' <<<"$_diff_names" \
  || grep -qF '.github/workflows/apply-web-platform-infra.yml' <<<"$_diff_names"; then
  _infra_in_diff=1
fi

if [[ "$_diff_detect_ok" == 0 ]]; then
  # Fail SAFE, not quiet: assume the boundary applies rather than assume it does not.
  _infra_in_diff=1
fi

# Observed, never predicted. Set ONLY where the runner is actually invoked; every coverage
# claim in this script keys off it.
_infra_ran=0
_infra_skip_reason=""

# --- Affected derivation pre-pass (#8322) ------------------------------------
#
# EXECUTION MODE ONLY — never under _ENUMERATE, which runs no suite and so can
# narrow nothing. The pre-pass answers, BEFORE the first suite starts, the two
# questions that decide whether the affected gate is even safe to apply:
#
#   * Is the selection TRUSTWORTHY? An undecidable diff, a missing index, an
#     edit to this file or to the declarations lib, or FORCE_ALL all degrade
#     the run to the full battery — announced as AFFECTED_FALLBACK, never
#     silently. A degraded run IS a full run: it re-faces both refusal arms at
#     the sibling check below, where tc_preamble's count now exists.
#   * What does each registration's ordinal select? One nested
#     `--enumerate-commands` self-call yields the live registration stream —
#     labels AND argv — in traversal order. Because _shard_selects ticks the
#     ordinal identically in both modes, stream record N maps to ordinal N,
#     and the chokepoint's `_aff_sel[$_shard_ordinal]` lookup is O(1).
#
# The pre-pass is also where the two PRE-EXECUTION refusals live: a declared
# always-on census below its floor means the index was gutted, and an
# effective selected set of zero means the run would certify a battery that
# never executes. Both exit 4 — "refused, nothing ran" — NOT 3, which #7424
# reserved for a suite TERMINATED mid-coverage.
_MIN_ALWAYS_ON_DECLARED=100
# An explicit non-`all` TEST_GROUP ask scopes the walk itself — every
# registration that reaches the chokepoint is in the named group and the
# classifier's `group` rung selects it unconditionally. The nested enumerate
# would buy nothing but a second ~440-registration walk.
if (( _AFFECTED == 1 && _ENUMERATE == 0 )) && [[ "$TEST_GROUP" == "all" ]]; then
  if [[ "${SOLEUR_TEST_FORCE_ALL:-}" == "1" ]]; then
    _aff_fallback="force-all"
  elif (( _AFF_LIB_OK == 0 )); then
    _aff_fallback="index-missing"
  elif [[ "$_diff_detect_ok" == "0" || "$_diff_head_ok" == "0" ]]; then
    _aff_fallback="undecidable-diff"
  elif grep -qF 'scripts/test-all.sh' <<<"$_diff_names" \
    || grep -qF 'scripts/lib/test-affected-paths.sh' <<<"$_diff_names"; then
    # The runner and the index are their own SUT: a diff touching either could
    # be narrowing the very selection this run is about to apply.
    _aff_fallback="runner-changed"
  elif (( ${#ALWAYS_ON_SUITES[@]} < _MIN_ALWAYS_ON_DECLARED )); then
    printf 'AFFECTED_UNRESOLVED\treason=below-floor declared=%d floor=%d\n' \
      "${#ALWAYS_ON_SUITES[@]}" "$_MIN_ALWAYS_ON_DECLARED"
    echo "ERROR: refusing affected-gate run — ALWAYS_ON_SUITES declares" >&2
    echo "       ${#ALWAYS_ON_SUITES[@]} suites, below the ${_MIN_ALWAYS_ON_DECLARED} floor." >&2
    echo "       The declarations lib looks gutted; run the whole battery instead:" >&2
    echo "         bash scripts/test-all.sh --full" >&2
    exit 4
  else
    _aff_enum_rc=0
    # `env -u SCRIPTS_SHARD` is load-bearing, not hygiene: under a shard the
    # child's stream would pack only shard-selected records as ordinals 1..k
    # while this walk's `_shard_ordinal` still runs 1..N — a silently shifted
    # map. The child enumerates the UNSHARDED stream so positions align; the
    # label guard at the chokepoint is the second line. stderr goes to a file
    # rather than /dev/null so `enumerate-unavailable` can name its cause.
    _aff_enum_err="$(mktemp "${TMPDIR:-/tmp}/test-all-enum-err.XXXXXX")"
    _aff_stream="$(SOLEUR_DISABLE_SESSION_STATE=1 env -u SCRIPTS_SHARD bash "${BASH_SOURCE[0]}" --enumerate-commands "$TEST_GROUP" 2>"$_aff_enum_err")" || _aff_enum_rc=$?
    if (( _aff_enum_rc != 0 )); then
      _aff_fallback="enumerate-unavailable"
      if [[ -s "$_aff_enum_err" ]]; then
        echo "[affected] enumerate child stderr (first 10 lines):" >&2
        sed -n '1,10p' "$_aff_enum_err" >&2
      fi
    else
      _aff_ordinal=0
      _aff_selected=0
      _aff_cmd_records=0
      while IFS= read -r _aff_line; do
        case "$_aff_line" in
          SUITE_COMMAND_DECLINED$'\t'*|SUITE_COMMAND$'\t'*)
            _aff_ordinal=$(( _aff_ordinal + 1 ))
            IFS=$'\t' read -ra _aff_fields <<< "$_aff_line"
            _aff_label[$_aff_ordinal]="${_aff_fields[1]}"
            [[ "$_aff_line" == SUITE_COMMAND$'\t'* ]] || continue
            _aff_cmd_records=$(( _aff_cmd_records + 1 ))
            _affected_classify "${_aff_fields[1]}" ${_aff_fields[@]+"${_aff_fields[@]:2}"}
            if [[ "$_AC_CLASS" == edge:* && ${#_AC_EDGES[@]} -gt 0 ]] \
              && ! _diff_touches ${_AC_EDGES[@]+"${_AC_EDGES[@]}"}; then
              _aff_sel[$_aff_ordinal]=0
            else
              _aff_sel[$_aff_ordinal]=1
              _aff_selected=$(( _aff_selected + 1 ))
            fi
            ;;
        esac
      done <<< "$_aff_stream"
      if (( _aff_selected == 0 )); then
        # The EFFECTIVE selected set, not the derived one: a run whose whole
        # reachable selection is empty would exit green having executed
        # nothing — the zero-coverage shape the shard guard already refuses.
        printf 'AFFECTED_UNRESOLVED\treason=zero-selected\n'
        echo "ERROR: refusing affected-gate run — the diff selects ZERO of the" >&2
        echo "       ${_aff_ordinal} reachable registrations. That is not a green gate; it is" >&2
        echo "       no gate. Run the whole battery:" >&2
        echo "         bash scripts/test-all.sh --full" >&2
        rm -f "$_aff_enum_err"
        exit 4
      fi
      _aff_ready=1
      # `not-affected` counts only SUITE_COMMAND records — DECLINED records are
      # relevance/incident declines decided inside the child and reported as
      # `skipped` in the epilogue, not as selection declines.
      echo "[affected] MODE=affected selected=${_aff_selected} not-affected=$(( _aff_cmd_records - _aff_selected )) of ${_aff_cmd_records} runnable registrations" >&2
    fi
    rm -f "$_aff_enum_err"
  fi
  if [[ -n "$_aff_fallback" ]]; then
    printf 'AFFECTED_FALLBACK\treason=%s\n' "$_aff_fallback"
    # Degraded is NOT `--full`: `_FULL_GATE` stays 0, so `not_in_diff`
    # relevance declines still apply — the banner must not claim otherwise.
    echo "[affected] MODE=full (degraded: ${_aff_fallback}) — selection declines disabled; relevance declines still apply." >&2
  fi
elif (( _ENUMERATE == 0 )); then
  if (( _AFFECTED == 1 )); then
    echo "[affected] MODE=affected (group-scoped: TEST_GROUP=$TEST_GROUP — every in-group registration selects)" >&2
  else
    echo "[affected] MODE=full" >&2
  fi
fi

# WHY THE want_infra CONJUNCT IS LOAD-BEARING. These notices used to key on `_infra_in_diff`
# alone — a fact about the DIFF — while the runner keys on `want_infra`, a fact about
# TEST_GROUP, and nothing coupled them. CI runs `test-all.sh webplat`, `bun` and `scripts`;
# want_infra is false in all three. So on every CI run of an infra-touching PR — exactly the
# case this phase exists for — three job logs affirmatively announced that the infra runner
# would be invoked, and it never was. That is strictly worse than what it replaced: the old
# text said "infra is NOT covered above", which was true in every group. Inverting the
# sentence without adding this conjunct turned a universally-true warning into a
# conditionally-false assurance.
if ! want_infra; then
  _infra_skip_reason="group"
  if [[ "$_infra_in_diff" == 1 ]]; then
    echo ""
    echo "NOTE: your diff touches apps/web-platform/infra/, but TEST_GROUP=$TEST_GROUP does"
    echo "      NOT include the infra runner. Nothing below is evidence for that directory."
    echo "      Cover it with either:"
    echo "        bash apps/web-platform/infra/run-registered-suites.sh"
    echo "        TEST_GROUP=infra bash scripts/test-all.sh"
    echo ""
  fi
elif [[ "$_diff_detect_ok" == 0 ]]; then
  echo ""
  echo "NOTE: could not determine this branch's diff (no origin/main, shallow clone, or a"
  echo "      fresh repo), so this runner cannot tell whether apps/web-platform/infra/ is"
  echo "      affected. Assuming it IS: the CI-registered infra runner will be invoked"
  echo "      below as a nested suite. This costs time on an irrelevant diff, which is the"
  echo "      safe direction — the unsafe one is a green that skipped it silently."
  echo "      Set SOLEUR_INCIDENT_SKIP=1 to skip it on an incident path — that skip is loud"
  echo "      and prints its re-run command."
  echo ""
elif [[ "$_infra_in_diff" == 1 ]]; then
  echo ""
  echo "NOTE: your diff touches apps/web-platform/infra/. The CI-registered infra runner"
  echo "      (apps/web-platform/infra/run-registered-suites.sh) will be invoked below as a"
  echo "      nested suite, so the summary DOES account for it. Set SOLEUR_INCIDENT_SKIP=1"
  echo "      to skip it on an incident path — that skip is loud and prints its re-run"
  echo "      command."
  echo ""
fi

# Contention preamble — emitted before the first `--- <suite> ---` line so a
# contended run is self-identifying and a false RED is never again diagnosed
# as a regression (AC1/AC2).
# NOT under --enumerate. tc_preamble is a full /proc walk (one awk per pid — MEASURED at 5.7s
# of an 8.2s enumerate pass, i.e. 70% of it) whose entire output is a capacity and contention
# verdict about running suites. An enumerate pass starts none and takes no lock, so every
# reading it produces is inapplicable, and the shard-totality guard invokes this path ~35 times
# per run (its fanned-out leg, altK, heavy, and probe enumerations). Skipping it takes that
# guard from 83s to ~25s.
#
# EXPRESSED AS A FUNCTION REDEFINITION, NOT AN `if` AROUND THE CALL — the call must stay at
# COLUMN 0. `scripts/test-all-killed-classification.test.sh` and
# `scripts/test-all-runtime-ceiling.test.sh` build their sandboxes by neutering this call with
# a `^tc_preamble` column-anchored `re.sub`, and unlike every neighbouring edit in those
# builders that substitution is NOT wrapped in their `sub_once()` assert — so indenting it makes
# both silently substitute nothing. Measured: the anchor matched 1 on origin/main and 0 once
# indented. The cost is not merely the ~5.7s walk per sandbox arm: killed-classification clears
# SOLEUR_ALLOW_FULL_GATE, so a live tc_preamble re-arms the sibling refusal INSIDE its
# sandboxes and their colour becomes a function of whether another gate run is in flight on the
# box. Same class as the splice-boundary and column-0-anchor breakages below.
if (( _ENUMERATE == 1 )); then
  tc_preamble() { :; }
  tc_tmp_entry_count() { printf '0\n'; }
fi
tc_preamble
_TC_RUN_START_ENTRIES=$(tc_tmp_entry_count)

# Orphaned-PROCESS probe (#7537), emitted with the contention banners because it
# answers the same question they do — "is something else on this box eating the
# capacity this run needs?" — for processes rather than for /tmp.
#
# REPORT ONLY. Nothing in this repo invokes `reap` automatically: the detector
# has never been observed firing on a real orphan, so the first strike is a
# READER'S judgment. This is the moment an actor is present and already reading
# stderr, which is what makes a report here a decision point rather than a
# declaration site.
#
# `timeout 10` AND `|| true` are both load-bearing and cover different failures:
# `|| true` covers a non-zero exit, and `timeout` covers what it cannot — an
# unresponsive NFS/FUSE/autofs mount puts readlink/stat in uninterruptible
# sleep, and a command that never returns is never rescued by `|| true`.
#
# EXCLUDE_PGID is passed EXPLICITLY rather than inferred: `timeout` runs its
# child in its own process group, so the probe computing its own pgid would get
# timeout's pid rather than this runner's, and this runner's command-
# substitution forks would not be excluded from its own reap set.
# Enumerate mode runs no suite and answers to a READER parsing records, so the
# probe's /proc walk and timeout are dead work there — the nested affected
# pre-pass pays it ~440 registrations upstream of any suite.
if [[ -z "${CI:-}" && $_ENUMERATE == 0 ]] && [[ -x scripts/orphan-process-reaper.sh || -f scripts/orphan-process-reaper.sh ]]; then
  _orphan_rc=0
  ORPHAN_REAPER_EXCLUDE_PGID="$(command ps -o pgid= -p $$ 2>/dev/null | tr -d ' ' || true)" \
    timeout 10 bash scripts/orphan-process-reaper.sh report || _orphan_rc=$?
  # The caller emits on a non-zero rc ITSELF. `|| true` hides the status, so
  # without this line "the detector did not run" is indistinguishable from "it
  # ran and found nothing" — and the second reads as an all-clear.
  if [[ "$_orphan_rc" != "0" ]]; then
    printf 'ORPHAN_SCAN valid=0 reason=rc%s\n' "$_orphan_rc"
  fi
  unset _orphan_rc
fi

# The capacity verdict (#7545), emitted BETWEEN the preamble and the lock —
# after the readings exist, before the wait that may consume them.
#
# It is built from the values tc_preamble just promoted, never from a second
# /proc walk: two walks are two non-atomic snapshots, and a run that printed
# CAPACITY_OK above SIBLING_RUN_DETECTED: 2 would be reporting on two different
# machines. One call site, because the runner has one top-level control flow.
#
# Changes NO exit code and blocks NO suite. Every run that completes today still
# completes; the only new thing is that it says what it measured.
tc_capacity_line >&2

# --- Sibling full-gate refusal (#7553) -------------------------------------------------------
#
# The SOLEUR_SUBAGENT refusal above binds to a condition an agent must DECLARE. Nothing in this
# repository sets that variable — measured across every occurrence: ADR prose, learnings, archived
# plans, two skill sentences, and tests that set it for their own arm. So its antecedent has never
# held in normal operation and the refusal has never fired for the case it was written for.
#
# This one binds to a condition the runner MEASURES. tc_preamble has already resolved how many
# OTHER worktrees are running test-all.sh (via /proc, excluding this run's own ancestors and
# process group), so no spawn-path cooperation is needed and there is no fail-open mode when some
# upstream harness changes an undocumented variable. It is also the arm CI can actually run: start
# a real sibling, assert the second invocation is refused.
#
# It fires HERE, AFTER tc_preamble (which computes the count) and BEFORE tc_acquire, deliberately.
# Refusing after tc_acquire would make a run that should never have started wait up to
# TC_LOCK_TIMEOUT (900 s) to be told so, and take the advisory lock a legitimate sibling is queued
# on. A refused run must cost nothing.
#
# ADDITIVE, not a replacement: the SOLEUR_SUBAGENT arm above is untouched and still exits 4.
# The count must be one THIS process measured. TC_SIBLING_RUN_COUNT is exported, so a nested
# test-all.sh inherits it — and a suite that drives this runner as its SUT neuters tc_preamble
# in its sandbox, so the inherited number describes a machine state the sandbox never looked
# at. Refusing on it turned every such suite red whenever any sibling happened to be running,
# for a reason unrelated to its subject. Measured PRE-STAMP — i.e. against the tree before the
# TC_SIBLING_RUN_COUNT_PID condition below existed — `TC_SIBLING_RUN_COUNT=4` alone took
# test-all-killed-classification from 77/0 to 40/37 and test-all-infra-coverage-notice from
# 118/0 to 38/81. Those two numbers are NOT reproducible at HEAD: re-running that A/B now
# returns 77/0 and 118/0, because the stamp is exactly what makes an inherited count inert.
# tc_preamble stamps TC_SIBLING_RUN_COUNT_PID with its own $$ and does not export it, so an
# inherited count carries no stamp and cannot refuse.
# Exempt under --enumerate for the same reason as the SOLEUR_SUBAGENT refusal above: an
# enumerate pass runs no suite, so it cannot contend with the sibling this refusal protects.
# Leaving it in force would make the shard-totality guard fail whenever any sibling gate ran,
# i.e. a guard whose colour depended on another worktree.
#
# The exemption is a CONJUNCT INSIDE the existing `[[ ]]`, not a new condition in front of it,
# so the statement still begins `if [[ "${TC_SIBLING_RUN_COUNT:-0}"` at column 0.
# plugins/soleur/test/fanout-suite-scope.test.sh anchors on exactly that prefix to assert this
# refusal precedes tc_acquire — deliberately, because a comment line cannot begin with `if [[`
# — and requires EXACTLY ONE match, so a leading condition silently takes the count to 0 and the
# ordering guard stops identifying any statement at all.
# Degraded-full re-check (#8322). The early SOLEUR_SUBAGENT arm exempts affected
# runs, but an affected run that DEGRADED to full above (undecidable diff,
# missing index, runner-changed, force-all) IS a full-gate run for contention
# purposes — so the refusal is re-evaluated HERE, post-derivation, where
# `_aff_fallback` now carries the verdict. Fires before tc_acquire like the
# primary arm, and for the same reason: a refused run must cost nothing.
if (( _AFFECTED == 1 && _ENUMERATE == 0 )) && [[ -n "$_aff_fallback" \
      && "${SOLEUR_SUBAGENT:-}" == "1" && "${SOLEUR_ALLOW_FULL_GATE:-}" != "1" ]]; then
  echo "ERROR: refusing a full-gate run — SOLEUR_SUBAGENT=1 is set, and affected selection" >&2
  echo "       degraded to the full battery (reason=${_aff_fallback}) (TEST_GROUP=$TEST_GROUP)." >&2
  echo "" >&2
  echo "Spawned agents run only the suites targeting the files they were given." >&2
  echo "Run the suite covering your files directly:" >&2
  echo "    bash <path/to/the/suite.test.sh>" >&2
  echo "" >&2
  echo "If you are the lead and this IS the sanctioned gate run, override explicitly:" >&2
  echo "    SOLEUR_ALLOW_FULL_GATE=1 bash scripts/test-all.sh --full" >&2
  exit 4
fi

# TEST_GROUP=affected is exempt here for the same reason as the SOLEUR_SUBAGENT refusal
# above: it is the targeted substitute this refusal prescribes, and it still queues on the
# advisory lock like any run — so an agent arriving mid-battery gets its scoped evidence
# serialised rather than refused outright (which would push it to lock-free per-file
# invocations, the very contention shape this refusal exists to prevent).
if [[ "${TC_SIBLING_RUN_COUNT:-0}" -gt 0 && "${TC_SIBLING_RUN_COUNT_PID:-}" == "$$" \
      && "$_ENUMERATE" == "0" \
      && "$TEST_GROUP" != "affected" \
      && "${SOLEUR_ALLOW_FULL_GATE:-}" != "1" \
      && ( "$_AFFECTED" == "0" || -n "$_aff_fallback" ) ]]; then
  echo "ERROR: refusing a full-gate run — ${TC_SIBLING_RUN_COUNT} sibling full-gate run(s) already in flight (TEST_GROUP=$TEST_GROUP)." >&2
  echo "" >&2
  echo "The offending worktree(s) are listed in the contention preamble above, under" >&2
  echo "'[contention] siblings:'. Concurrent full-gate runs inflate each other's timings, and on a" >&2
  echo "contended host push suites past their own timeouts — turning a green suite red for a reason" >&2
  echo "unrelated to your diff, so the next reader investigates a phantom." >&2
  echo "" >&2
  echo "Run the affected set — what your diff actually reaches — instead (it is exempt from" >&2
  echo "this refusal):" >&2
  echo "    bash scripts/test-all.sh --affected" >&2
  echo "or the runner-selected diff scope:" >&2
  echo "    TEST_GROUP=affected bash scripts/test-all.sh" >&2
  echo "or the suite covering your files directly:" >&2
  echo "    bash <path/to/the/suite.test.sh>" >&2
  echo "" >&2
  echo "Or wait for the sibling to finish. If you are the lead and this IS the sanctioned gate run," >&2
  echo "override explicitly:" >&2
  echo "    SOLEUR_ALLOW_FULL_GATE=1 bash scripts/test-all.sh --full" >&2
  # Same rc as the SOLEUR_SUBAGENT refusal: both mean REFUSED, nothing ran, nothing unresolved.
  # Deliberately NOT 3 — #7424 assigned 3 the meaning "a suite was terminated, coverage not
  # obtained", which is the opposite claim.
  exit 4
fi

# Advisory, self-announcing queue (#6789). Acquired INTERNALLY (not by a caller
# wrapping the script) so no invocation can forget it. It NEVER aborts — on
# timeout it proceeds with a named banner, so it cannot wedge a run. CI and the
# SOLEUR_DISABLE_SESSION_STATE kill switch are honoured inside tc_acquire.
# Declared BEFORE tc_acquire, i.e. OUTSIDE the region the two suites that drive this runner as
# their SUT replace wholesale. scripts/test-all-killed-classification.test.sh and its sibling
# splice their own fixture body between the lock-acquire call below and the epilogue, so a
# variable first assigned inside that window does not exist in their sandbox while the reader
# after it does — and under `set -u` that aborts the sandbox mid-run. Measured: it took AC2, AC3
# and AC8b red in a suite this branch does not otherwise touch. Exactly the shape of #7553's own
# regression, recorded in ADR-196 Decision 7.
#
# The anchors are NOT quoted verbatim here on purpose. Those fixtures locate the splice window by
# substring and require it to be UNIQUE; an earlier draft of this comment quoted the acquire call
# exactly, so the literal appeared twice and every sandbox build failed with
# "sandbox build failed: killed_only/none" — 40 passed, 51 failed, in a suite whose own code was
# untouched. A comment that names a token a parser keys on is part of that parser input
# (cq-assert-anchor-not-bare-token), which is this branch's own subject.
#
# Initialised to the NOT-MEASURED value, so a sandbox that drops the capture degrades to an
# honest "this run is not evidence" NOTE rather than either aborting or silently claiming a
# clean boundary.
# --- Runtime ceiling state (#7869) -----------------------------------------
#
# Declared HERE, at top level, deliberately: it is OUTSIDE the region that
# scripts/test-all-killed-classification.test.sh and its sibling replace
# wholesale. run_suite is defined above that region and survives into their
# sandboxes, so a variable it reads that were first assigned inside the window
# would be unbound there — and under `set -u` that aborts a suite this branch
# does not otherwise touch.
_RUN_START_EPOCH="${EPOCHSECONDS:-0}"
_ceiling_tripped=0
_ceiling_declined=0

# The ceiling is resolved ONCE, here, rather than re-parsed inside run_suite on each of its
# ~194 invocations. Three defects collapse into this single evaluation:
#
#   (a) OCTAL. `(( 08 ))` is a base-8 literal in bash and an ERROR; awk has no such rule. Two
#       consumers reading one knob through two parsers therefore DIVERGED on any zero-padded
#       value — `07200` meant 3712 s here and 7200 s to the sibling filter, and 3712 s is BELOW
#       the lowest runtime this repo records for a healthy contended run. A guard that curtails
#       healthy work is worse than no guard. `10#` forces base 10; the runner already uses that
#       idiom for EPOCHREALTIME microseconds and this code failed to carry it over.
#   (b) CI. `tc_acquire` exempts CI because a shard is already isolated, and the reasoning
#       applies with more force here: the ceiling's premise is "a run past it has no consumer",
#       and in a shard the consumer is the required `test` check. GitHub's default job timeout is
#       360 min against this 240 min ceiling, so unexempted it would fire FIRST and red a
#       required check on a run that was merely slow.
#   (c) SILENCE. The one path where the guard does nothing had no signal, so "armed" and
#       "disabled since someone exported a malformed value" were indistinguishable.
#
# 0 means DISABLED. Every branch below fails toward keep-running.
_CEILING_S=0
if [[ -n "${CI:-}" ]]; then
  : # Exempt, deliberately silent: it would fire on every CI run and carry no information.
elif [[ "${TC_RUNTIME_CEILING_S:-}" =~ ^[0-9]+$ ]] && (( 10#${TC_RUNTIME_CEILING_S} > 0 )); then
  _CEILING_S=$(( 10#${TC_RUNTIME_CEILING_S} ))
else
  echo "[contention] BANNER SOLEUR_TEST_ALL_CEILING_UNAVAILABLE value=${TC_RUNTIME_CEILING_S:-<unset>} — the runtime ceiling is DISABLED for this run; it will not stop starting suites however long it runs." >&2
fi

# Sampled either side of the infra run_suite call so a ceiling-declined suite cannot be
# recorded as covered. Declared here, with its siblings, for the same splice-window reason.
_infra_declined_before=0

_repo_guard_ok=0
_repo_state_before=""
_repo_last_suite="(none started)"
# Set by the end block once the boundary has been re-read and reported. Until then the EXIT trap
# below owns the verdict.
_repo_boundary_reported=0

# Before #7652 a run that ended before the end boundary emitted nothing — the runner armed no EXIT
# trap —
# and the escape most likely to end a run early is exactly the one that would suppress the
# verdict. So "no FATAL line" is indistinguishable from "clean", which is the reading that ships.
# This trap makes that absence speak for the signals bash can trap.
#
# STATED BECAUSE IT WOULD OTHERWISE BE OVER-READ: bash cannot trap SIGKILL, so an OOM-killed or
# `kill -9`'d run still emits nothing and still reads as silence. This closes the ordinary
# early-exit and timeout cases, not the whole class. Claiming otherwise here would be the same
# AP-021 defect the boundary exists to remove.
_repo_boundary_exit_note() {
  [[ "$_repo_boundary_reported" == 1 ]] && return 0
  [[ "$_repo_guard_ok" == 1 ]] || return 0
  echo "" >&2
  echo "NOTE: this run ended before the repo-write boundary was re-read, so it is NOT evidence" >&2
  echo "      that no suite wrote to your repository. The absence of a [FATAL] line above means" >&2
  echo "      the check did not run, not that it passed. Last suite started: ${_repo_last_suite}" >&2
}
# Free the incident sandbox this runner MINTED (ADR-129 rule (c)).
#
# Registered HERE, not at the allocation site: a later bare `trap ... EXIT` CLOBBERS an earlier one
# outright (measured -- it does not compose), so a trap up there would have looked correct and freed
# nothing. Skipped when the root was INHERITED: freeing an outer runner's sandbox mid-run would
# silently re-point every later suite at the operator's real ledger.
_soleur_refguard_cleanup() {
  # The hook dir is a mktemp copy, so lefthook's auto-install lands in /tmp instead of the
  # repository. Guarded on the name so a mis-set variable cannot rm an unrelated path.
  [[ -n "${_soleur_refguard_dir:-}" && "$_soleur_refguard_dir" == */soleur-refguard.* ]] \
    && rm -rf "$_soleur_refguard_dir"
  return 0
}

_soleur_inc_cleanup() {
  [[ -n "${_soleur_inc_owned:-}" && "$_soleur_inc_owned" == */soleur-inc-* ]] && rm -rf "$_soleur_inc_owned"
  # `return 0` is LOAD-BEARING, not tidiness. When the root was INHERITED,
  # _soleur_inc_owned is unset, so the `[[ ]] && rm` compound above returns 1 --
  # and this function is the LAST command of the EXIT trap. Under `set -e`
  # (line 2) that becomes the SCRIPT's exit status, so a fully successful run
  # exits 1. Measured:
  #     set -euo pipefail, owned UNSET -> rc=1
  #     set -euo pipefail, owned SET   -> rc=0
  # The inherited case is exactly the nested one -- any suite that drives
  # test-all.sh as its subject inherits the outer run's root -- so every such
  # suite saw rc=1 on a green run. That is what reddened
  # test-all-runtime-ceiling and test-all-killed-classification.
  return 0
}

# Watchdog disarm must live in the EXIT trap, not only at the enumerate
# terminator: every abnormal exit after arming — `_wt_missing_die` (the #8761
# primary path), the graceful deadline's exit 4, any mid-walk `exit`/`set -e`
# abort — would otherwise leak the watchdog subshell's `sleep` holding an
# inherited stdout pipe open until the deadline, blocking a `$( )`/pipe
# consumer for up to _ENUM_DEADLINE_S after the runner is gone. Guarded by
# `${_ENUM_WD_PID:-}` — exits before the arm site are no-ops.
_enum_wd_disarm() {
  if [[ -n "${_ENUM_WD_PID:-}" ]]; then
    kill "$_ENUM_WD_PID" 2>/dev/null || true
    # SIGTERM can be inherited MASKED — the watchdog's TERM trap then never
    # runs and a bare wait would block until the deadline fires (its TERM is
    # blocked too, and the KILL lands on a healthy run mid-trap). Poll ~2s —
    # a live trap exits in ms; a zombie answers kill -0, so it is excluded —
    # then escalate to SIGKILL, which no mask stops.
    local _d=0
    while (( _d < 20 )) \
      && kill -0 "$_ENUM_WD_PID" 2>/dev/null \
      && [[ "$(ps -o stat= -p "$_ENUM_WD_PID" 2>/dev/null)" != Z* ]]; do
      sleep 0.1; _d=$(( _d + 1 ))
    done
    kill -KILL "$_ENUM_WD_PID" 2>/dev/null || true
    wait "$_ENUM_WD_PID" 2>/dev/null || true
  fi
}
trap '_repo_boundary_exit_note; _soleur_refguard_cleanup; _soleur_inc_cleanup; _soleur_scratch_cleanup || true; _enum_wd_disarm' EXIT

# NOT under --enumerate. The shard-totality guard runs this path from inside a gate run that
# already holds this lock; blocking here would deadlock the gate on itself. An enumerate pass
# executes no suite, so it needs no serialization.
#
# EXPRESSED AS THE LIB'S OWN KILL SWITCH RATHER THAN AN `if` AROUND THE CALL, and that shape is
# load-bearing twice over:
#
#   * `scripts/test-all-killed-classification.test.sh` and `scripts/test-all-runtime-ceiling.test.sh`
#     build their sandboxes by splicing THIS FILE from just after the acquire statement below to
#     just before the epilogue call. An `if` wrapped around it puts its `fi` inside that removed
#     region, so every sandbox becomes an unterminated `if` — a bash syntax error at EOF, which
#     surfaces as dozens of unrelated-looking assertion failures rather than as anything naming
#     this line. Measured: 37 failures across those two suites.
#   * `plugins/soleur/test/fanout-suite-scope.test.sh` asserts refusal-before-acquire structurally
#     on that statement at column 0, deliberately anchored so a comment cannot satisfy it.
#     Indenting it breaks that guard's ability to see the ordering it protects.
#
# `tc_acquire` honours SOLEUR_DISABLE_SESSION_STATE=1 before anything else and returns 0 with a
# named LOCK_SKIPPED_DISABLED line, so this is the layer's documented exemption rather than a
# bypass — and the statement stays at column 0, unwrapped.
#
# NOTE FOR EDITORS: the acquire statement's full text and the epilogue call's full text are both
# UNIQUENESS-ASSERTED by those sandbox builders (`assert s.count(anchor) == 1`). Quoting either
# verbatim in a comment takes the count above one and breaks every sandbox build before a single
# assertion runs — which is why the prose above describes them instead of reproducing them.
if (( _ENUMERATE == 1 )); then SOLEUR_DISABLE_SESSION_STATE=1; fi

tc_acquire "test-all"

# --- ARM THE REF-STORE STATE PREDICATE (#7917, AP-025) --------------------------------------
# `scripts/battery-tag-authorship.test.sh` is a STATIC census: it enumerates the ways a
# tag-authoring command can be REACHED. AP-025 says a hazard that is a property of runtime STATE
# wants a self-refusal the artifact CARRIES, because a list of ways to reach a state cannot be
# proven complete — and that guard's header enumerates eight places where it is not. This arms
# the complement: a `reference-transaction` hook that refuses a refs/tags/* CREATE in THIS
# repository for the duration of the run, whatever spelling produced it.
#
# Env-scoped, so there is nothing to install and nothing to tear down: GIT_CONFIG_* is inherited
# by the whole process tree and dies with it. A suite that sets `-c core.hooksPath=…` per command
# still wins (command-line config outranks env), which is how the eleven suites that legitimately
# create tags in mktemp sandboxes stay unaffected — and they are unaffected anyway, because the
# hook compares --git-common-dir against THIS repo and ignores every other ref store.
#
# THE HOOK DIRECTORY HOLDS ONLY THIS HOOK, DELIBERATELY. `core.hooksPath` replaces the hooks
# directory wholesale, so the alternative — pointing it at a directory that also carries copies of
# `scripts/hooks/pre-commit` and `pre-push` — would start running those in EVERY fixture repo the
# battery creates, since the env config reaches fixtures too. A `git init` fixture has no hooks
# today; with a single-hook directory it still effectively has none, because this hook is inert for
# non-tag refs and for every ref store that is not this one. The cost of the narrow directory is
# that the operator's own hooks are displaced for git calls made DURING a gate run — which is a
# non-event, since a suite that commits to the live repository is the thing
# `scripts/lib/repo-write-boundary.sh` exists to catch.
#
# Skipped under --enumerate: no suite runs, and the mode's contract is that it takes no lock and
# changes no state.
if (( _ENUMERATE == 0 )); then
  _bt_common="$(git rev-parse --git-common-dir 2>/dev/null || true)"
  if [[ -n "$_bt_common" ]]; then
    case "$_bt_common" in /*) : ;; *) _bt_common="$PWD/$_bt_common" ;; esac
    _bt_common="$(cd "$_bt_common" 2>/dev/null && pwd -P || true)"
  fi
  # SHARED NAMESPACE, stated rather than engineered around: plugins/soleur/test/lib/git-fixture-env.sh
  # also writes the count-indexed GIT_CONFIG_* namespace (commit.gpgsign), and unconditionally, so
  # every fixture built through that chokepoint clobbers this arming — which is exactly why fixtures
  # stay hermetic under it. Benign at COUNT=1 on both sides; fragile above it. Do not build
  # indirection for this, just do not raise either count without reading the other.
  if [[ -n "$_bt_common" && -x scripts/hooks/battery-ref-guard/reference-transaction ]]; then
    # POINT core.hooksPath AT A RUN-SCOPED COPY, NEVER AT THE TRACKED DIRECTORY.
    #
    # An earlier revision pointed it straight at scripts/hooks/battery-ref-guard, which is a
    # TRACKED source path — and lefthook auto-installs into whatever core.hooksPath names. A full
    # gate run therefore ended with an untracked `pre-commit` sitting in the repository and the
    # write-boundary sentinel firing "[FATAL] A SUITE WROTE TO THE LIVE REPOSITORY", worktree
    # dimension. `scripts/lib/repo-write-boundary.sh` already excludes the contents of .git/hooks
    # "so `lefthook install` does not fire here"; redirecting hooksPath at a tracked path routed
    # around that exclusion and put the install where it DOES fire. Only a full gate run surfaces
    # this: nothing installs hooks during a single suite.
    #
    # A temp copy costs the "nothing to install, nothing to tear down" property the env-scoped
    # design started with. That property was not survivable, and a stray file in /tmp is a strictly
    # better failure than a stray file in the repository.
    _bt_hookdir="$(mktemp -d -t soleur-refguard.XXXXXXXX)" || _bt_hookdir=""
    if [[ -n "$_bt_hookdir" && -d "$_bt_hookdir" ]] \
       && cp scripts/hooks/battery-ref-guard/reference-transaction "$_bt_hookdir/" 2>/dev/null; then
      chmod +x "$_bt_hookdir/reference-transaction" 2>/dev/null || true
      _soleur_refguard_dir="$_bt_hookdir"
      export BATTERY_TAG_LIVE_COMMON_DIR="$_bt_common"
      export GIT_CONFIG_COUNT=1
      export GIT_CONFIG_KEY_0=core.hooksPath
      export GIT_CONFIG_VALUE_0="$_bt_hookdir"
    else
      printf 'WARNING: ref-store state predicate NOT armed (could not stage a run-scoped hook dir) — this run is guarded by the static census alone.\n' >&2
    fi
  else
    # Never silent: "the predicate is armed" and "the predicate could not arm" must not render
    # identically, or a disarmed run reads exactly like a protected one.
    printf 'WARNING: ref-store state predicate NOT armed (common-dir=%s, hook present=%s) — this run is guarded by the static census alone.\n' \
      "${_bt_common:-<unresolved>}" "$([[ -x scripts/hooks/battery-ref-guard/reference-transaction ]] && echo yes || echo no)" >&2
  fi
  unset _bt_common
fi

# AFTER tc_acquire, deliberately. A run that queued behind a sibling can wait up
# to TC_LOCK_TIMEOUT (3600 s) here, so a reading taken before the wait describes a
# machine state up to an hour stale and makes the start/end delta
# meaningless. Sampled at the moment this run actually begins doing work.
_emit_bytes_probe "__run_boundary_start__"

# --- REPO WRITE BOUNDARY (start) ---------------------------------------------------------
#
# This runner is READ-ONLY with respect to the repository it is run from. Nothing it registers
# may commit, check out, stage, or move a ref here. That is a property nobody was measuring,
# and on 2026-08-20 it was violated: a suite silenced its `git worktree add` failures and then
# ran `git add`/`git commit` in an unguarded subshell, so the commands executed in the CALLER
# CWD — the developer's live worktree. Four escapes across three sessions in under two hours;
# fixture commits landed on feature branches AND on local main, one worktree was checked out to
# main, and hours of uncommitted work were destroyed. Every suite reported green throughout.
#
# The site-level fix (a guard in that suite) is necessary and not sufficient: it protects the
# sites it covers, in the file it lives in. This is the BOUNDARY check, and it is deliberately
# characterised by the INVARIANT rather than by any fingerprint of that fixture. Detection by
# commit message, by the fixture's pinned committer date, or by author all key on incidental
# properties of today's escape and fail SILENTLY CLEAN against a future one that differs. "The
# gate wrote to the repo" does not.
#
# Sampled AFTER tc_acquire for the same reason the bytes probe is: a run that queued behind a
# sibling can wait here, and a reading taken before the wait describes a stale tree.
#
# Degrades OPEN. A missing or failing git must not wedge the gate — an unmeasurable boundary is
# reported at the end, never turned into a false RED.
# Skipped under _ENUMERATE: enumerate exits before the boundary epilogue, so
# the sampling subprocess would be dead work the nested affected pre-pass
# pays once per dispatch.
if (( _ENUMERATE == 0 )); then
  if _repo_state_before="$(_repo_state)"; then
    _repo_guard_ok=1
  fi
fi

# Pre-suite bash/python tests — scripts shard.
if want_scripts; then
  run_suite "tests/hooks/incidents" bash tests/hooks/test_incidents.sh
  run_suite "tests/hooks/emissions" bash tests/hooks/test_hook_emissions.sh
  # Registered explicitly (#8322): tests/hooks/ has no auto-discovery glob, and the
  # `test_<name>.sh` convention is outside lint-orphan-test-suites.sh's `*.test.sh`
  # producer, so an unregistered suite here gates nothing while reading as coverage.
  #
  # `tests/hooks/openhands-guardrails` was registered here until 2026-09-23 (ADR-245):
  # its suite tested the hand-ported `.openhands/` PreToolUse mirror, and both the mirror
  # and the suite are deleted. Keeping the registration would abort the runner on a
  # missing file; dropping it is the deletion, not a narrowing of coverage.
  run_suite "tests/hooks/drop-sentinel-parity" bash tests/hooks/test_drop_sentinel_parity.sh
  run_suite "tests/scripts/lint-rule-ids" python3 -m unittest tests.scripts.test_lint_rule_ids
  run_suite "scripts/lint-rule-ids-live" python3 scripts/lint-rule-ids.py --retired-file scripts/retired-rule-ids.txt --index-file AGENTS.md AGENTS.md AGENTS.rules.md
  # Hard-rule body-weakening gate (#6103, ADR-091): hermetic fixtures + a live
  # calibration (base HEAD → zero findings on the committed corpus). The real
  # merge-blocking gate is the standalone `rule-body-lint` ci.yml job with
  # --base <merge-base>; this live line is the calibration + orphan-suite guard.
  run_suite "tests/scripts/lint-rule-bodies" python3 -m unittest tests.scripts.test_lint_rule_bodies
  run_suite "scripts/lint-rule-bodies-live" python3 scripts/lint-rule-bodies.py --check --base HEAD
  # AGENTS B_ALWAYS rule-budget gate — CI-wired in #4599 (was lefthook pre-commit only).
  run_suite "scripts/lint-agents-rule-budget-live" python3 scripts/lint-agents-rule-budget.py AGENTS.md AGENTS.rules.md
  run_suite "scripts/lint-agents-rule-budget-unit" bash scripts/lint-agents-rule-budget.test.sh
  # The sync guard was lefthook-only, so a --no-verify commit bypassed it and
  # the byte-budget constant drifted across five artifacts unnoticed (#6461).
  # -live asserts the tree is in sync; -unit asserts the guard can still fail.
  run_suite "scripts/lint-agents-compound-sync-live" bash scripts/lint-agents-compound-sync.sh
  run_suite "scripts/lint-agents-compound-sync-unit" bash scripts/lint-agents-compound-sync.test.sh
  # Enforcement-tag parity — CI-wired in #7172 (was lefthook pre-commit only,
  # so main drifted to 13 unresolved tags with every local run green). -live
  # asserts the shipped corpus resolves AND that a non-zero number of tags was
  # actually scanned; -unit asserts the linter can still fail.
  run_suite "scripts/lint-agents-enforcement-tags-live" python3 scripts/lint-agents-enforcement-tags.py AGENTS.md AGENTS.rules.md
  run_suite "scripts/lint-agents-enforcement-tags-unit" bash scripts/lint-agents-enforcement-tags.test.sh
  # #8030 / PR #8175: rules migrated out of AGENTS.rules.md are invisible to every check that
  # reads that file. The live run checks each registry row's placement and body hash; the unit
  # suite is the mutation matrix. Registered explicitly — scripts/*.test.sh is not auto-globbed.
  run_suite "scripts/lint-migrated-rule-ids-live" bash scripts/lint-migrated-rule-ids.sh
  run_suite "scripts/lint-migrated-rule-ids-unit" bash scripts/lint-migrated-rule-ids.test.sh
  run_suite "scripts/lint-infra-no-human-steps" bash scripts/lint-infra-no-human-steps.test.sh
  # Doppler's API caps a doppler_* `description` at 255; the provider schema and `terraform plan`
  # do not, so a 273-char doppler_project.infra_privileged reddened every push apply after the
  # credential-tiering merge. -live asserts the real tree; -unit is the mutation matrix.
  run_suite "scripts/lint-doppler-description-length-live" python3 scripts/lint-doppler-description-length.py
  run_suite "scripts/lint-doppler-description-length-unit" bash scripts/lint-doppler-description-length.test.sh
  # markdownlint's guard (#7927). Registered EXPLICITLY for the reason spelled out
  # just below: `scripts/*.test.sh` is not in SUITE_GLOBS, so nothing discovers it.
  #
  # UNIT ONLY, exactly ONE line. The repo-wide sweep runs in its own CI job, not here:
  # a `-live` line would put a 1,345-file lint inside every shard of the required
  # `test` context, and the orphan linter treats a suite carrying BOTH a run_suite
  # line and a workflow `run:` step as double coverage.
  # scripts/markdown-lint.test.sh is DELIBERATELY NOT REGISTERED HERE, and the reason is
  # structural rather than preferential. It drives the real pinned binary through a
  # hermetic sandbox that symlinks node_modules; these legs install no node deps, so on
  # CI it would abort on a RED sandbox control. Guarding the registration behind
  # `if [[ -x node_modules/.bin/markdownlint ]]` looks like the fix and is not: this
  # file's registrations are parsed STATICALLY to derive the shard-totality reference, so
  # a conditional one is counted in the reference (385) and assigned to no leg (384) --
  # scripts-shard-totality-mutations calls that "runs nowhere while the required 'test'
  # check reports green", which is precisely the defect class it exists to catch, and it
  # caught this. A registration here must be unconditional or absent.
  #
  # It runs in the `markdown-lint` job of .github/workflows/pr-quality-guards.yml, which
  # does `npm ci --ignore-scripts` first. That is a runner lint-orphan-test-suites
  # recognises, and row W1e of the suite itself asserts the workflow still carries the
  # step, so deleting it reddens the suite rather than silently ending its coverage.
  # Locally: npm ci --ignore-scripts && bash scripts/markdown-lint.test.sh
  # Supabase Management API deprecation + host-pin assembly guard, and the
  # retained-log helper. Registered EXPLICITLY because neither directory is in
  # SUITE_GLOBS: `--print-suite-globs` lists `scripts/lib/*.test.sh` but not
  # `scripts/*.test.sh`, and `tests/scripts/` is absent entirely (its files are
  # also named `test-*.sh`, which a `*.test.sh` glob cannot match either way).
  # An unregistered suite there runs in zero runners and reads as passing (#7718).
  #
  # UNIT ONLY, AND THAT IS DELIBERATE. There is no `-live` line here, unlike the
  # sibling linters above. This shard runs inside the required `test` context, so
  # a `-live` run_suite would make the guard merge-blocking — which is exactly the
  # promotion this PR declined to make (see the guard header, ADR-197 and #7716).
  # Worth recording for whoever does promote it: this single line IS a promotion
  # path, and it bypasses the #6049 auto-fabrication trap that makes the
  # required-checks.txt route four coupled steps, because it adds no new
  # content-scoped gate NAME. The live run is advisory in `lint-bot-statuses`.
  run_suite "scripts/lint-supabase-deprecated-endpoints-unit" bash tests/scripts/test-lint-supabase-deprecated-endpoints.sh
  run_suite "tests/scripts/supabase-logs-query" bash tests/scripts/test-supabase-logs-query.sh

  run_suite "scripts/lint-credential-path-literals" bash scripts/lint-credential-path-literals.test.sh
  # #7136: a `run:` step reading a variable declared only on ANOTHER step. Part B of this
  # suite EXECUTES the shipped release-failure email body under both deploy branches — the
  # alert path that had never once delivered, because `set -u` killed it before the curl.
  run_suite "scripts/lint-workflow-step-env-refs" bash scripts/lint-workflow-step-env-refs.test.sh
  run_suite "scripts/lint-workflow-step-env-refs-live" python3 scripts/lint-workflow-step-env-refs.py
  # ADR-170. Both halves are required: the unit suite proves the RULE is right (its fixtures are
  # the executable spec), the live scan proves the TREE is clean. Either alone is satisfiable by
  # a detector that has stopped detecting -- a broken linter and a clean repo emit identical
  # output, which is why the unit suite carries a verify-the-verifier case that re-introduces
  # the real defect into a tree copy.
  run_suite "scripts/lint-workflow-errexit-capture" bash scripts/lint-workflow-errexit-capture.test.sh
  run_suite "scripts/lint-workflow-errexit-capture-live" python3 scripts/lint-workflow-errexit-capture.py
  # #7695 review: actionlint flags unparseable run: bodies, but lint-workflows.sh treats its rc=1 as
  # accepted (census tracked in #7042), so the class was green in CI. This one exits non-zero.
  run_suite "scripts/lint-workflow-run-body-syntax" python3 scripts/lint-workflow-run-body-syntax.py
  # ADR-191 (#7084). Same both-halves shape as the pair above, and for the same reason: after
  # this change the passing state of Guard 1 is "zero bun.lock found", which is byte-identical
  # to the output of a guard whose search is broken. The unit suites carry the anti-vacuity
  # floors and the must-PASS rows; the live scans prove the tree.
  #
  # Two guards rather than one: each one's floor has to be obviously matched to its own
  # enumeration (Guard 1 anchors on package-lock.json directories, Guard 2 on workflow files
  # AND matched install steps), and a single script hosting both would fail that name test for
  # half its job.
  run_suite "scripts/lint-dual-lockfile" bash scripts/lint-dual-lockfile.test.sh
  run_suite "scripts/lint-dual-lockfile-live" bash scripts/lint-dual-lockfile.sh
  run_suite "scripts/lint-workflow-install-sites" bash scripts/lint-workflow-install-sites.test.sh
  run_suite "scripts/lint-workflow-install-sites-live" bash scripts/lint-workflow-install-sites.sh
  # The wrapper the plan's `discoverability_test.command` contracts on. Registered
  # separately from the two guards it calls because what it can get wrong is its own:
  # reporting success while a guard beneath it reddened. preflight Check 10 matches on its
  # marker, so an unconditional marker would report a healthy invariant against any tree.
  run_suite "scripts/verify-lockfile-guards" bash scripts/verify-lockfile-guards.test.sh
  # The drain itself (#7084). Asserted from the committed lockfiles rather than from the
  # Dependabot API: this is deterministic, available at merge time, and needs no token the
  # workflow does not have. The alert COUNT is a lagging mirror of this same fact.
  run_suite "scripts/assert-dependabot-drain-live" python3 scripts/assert-dependabot-drain.py
  # ...and the guard's own guard (#1327). The live run above proves the tree is clean; it
  # cannot prove the assertion still has teeth. Both anti-vacuity floors there count ROWS,
  # so every CVE threshold in the table could be set to "0.0.0" and the live run still
  # exited 0. This suite mutates a sandbox copy and requires each mutation to RED with the
  # message that names its cause.
  run_suite "scripts/assert-dependabot-drain-unit" bash scripts/assert-dependabot-drain.test.sh
  # SIBLING gate (#7332): the same "captured a status nobody decided about" class, but in shell
  # SCRIPTS under `set -e` rather than Actions `run:` blocks. Separate anchor, separate
  # calibration -- the naive "a command-substitution assignment is a finding" rule found only
  # 2 of 17 sites for workflows and is the CORRECT rule here, which is why widening the sibling
  # would have meant each gate covering the other's blind spot badly.
  #
  # The live run carries a BASELINE of 216 pre-existing findings (206 abort-risk, 10
  # double-emit). The gate blocks NEW occurrences only; the baseline may shrink and must never
  # grow. Burn-down is tracked in the learning that ships with this gate. Registering it
  # baseline-free would have meant either a permanently red suite or a silently narrowed rule.
  # #8392 twin registration: the fixture suite pins the DETECTOR, the -live row runs
  # it over the repo. Registering only one makes a lint decoration.
  run_suite "scripts/lint-anthropic-content-position" bash scripts/lint-anthropic-content-position.test.sh
  run_suite "scripts/lint-anthropic-content-position-live" python3 scripts/lint-anthropic-content-position.py
  run_suite "scripts/lint-shell-capture-exit" bash scripts/lint-shell-capture-exit.test.sh
  run_suite "scripts/lint-shell-capture-exit-live" python3 scripts/lint-shell-capture-exit.py \
    --baseline scripts/lint-shell-capture-exit.baseline.txt
  # #7471, amended #7493: the published distribution manifest in jikig-ai/soleur-marketplace
  # is the only artifact in the delivery path no CI check here can reach DIRECTLY. Its SOURCE
  # is now reachable (Terraform owns the content; marketplace-manifest-guard validates it
  # pre-merge, and that repo now carries a PR-required ruleset), so the "no CI, no review, no
  # CODEOWNERS" framing this comment used to carry no longer holds.
  # scheduled-marketplace-drift.yml remains the only check on what is actually SERVED;
  # this suite is that guard's guard. Registered explicitly because
  # scripts/*.test.sh is NOT auto-globbed here — an unregistered gate never runs.
  run_suite "scripts/marketplace-drift-check" bash scripts/marketplace-drift-check.test.sh
  # #8160: the devin-docs-drift watcher's anchors fire on third-party doc text, so
  # a polarity inversion or a dead regex is invisible until the day the watch was
  # built for. This suite extracts the check step verbatim and drives both
  # directions — affirmative cloud claims MUST fire, negations MUST NOT.
  run_suite "scripts/devin-docs-drift-check" bash scripts/devin-docs-drift-check.test.sh
  # #7489: the legacy `soleur@soleur` marketplace entry carries client-side
  # `autoUpdate: true`, which cannot be revoked remotely — so the tracker's
  # closing condition is a claim about MACHINES, and the probe is how that claim
  # is made checkable rather than asserted. Guard 2's battery; registered
  # explicitly for the same reason as the suite above.
  run_suite "scripts/plugin-legacy-resolver-probe" bash scripts/plugin-legacy-resolver-probe.test.sh
  # #7490: the manifest suite above asserts the published POINTER is well-formed.
  # This one guards the assertion that following it actually DELIVERS the plugin --
  # complete, byte-correct at the delivered commit, and current. #7471 shipped 64
  # skill directories where 96 were expected with every metadata field reading
  # correct, which is the defect a manifest check structurally cannot see.
  run_suite "scripts/plugin-delivery-canary" bash scripts/plugin-delivery-canary.test.sh
  # Meta-guard over the two suites above: both end in an anti-vacuity floor, and
  # both originally enforced that floor by calling `fail` — the function whose
  # failure the floor exists to survive. This pins the fix by mutation (stub
  # `fail`, assert the floor still exits non-zero) rather than by inspection.
  # Registered explicitly: it lives under scripts/, which is not auto-globbed.
  run_suite "scripts/guard-vacuity-floor" bash scripts/guard-vacuity-floor.test.sh
  # Guard 4 (#7493): validates the manifest SOURCE that Terraform publishes, as opposed to the
  # sibling above which validates the PUBLISHED artifact. Neither subsumes the other — once the
  # drift workflow dispatches a reconcile, a bad SOURCE is republished daily while a
  # published-vs-source byte-diff reports in-sync, so the merge boundary is the only place that
  # loop can be broken.
  run_suite "scripts/marketplace-manifest-validate" bash scripts/marketplace-manifest-validate.test.sh
  # Guard 1 (#7493): the marketplace ruleset probe, driven against recorded ruleset-detail
  # fixtures. Its live mutations (flip enforcement, add a 4th bypass actor) cannot be performed
  # in CI, so fixtures are the only honest way to prove the probe reddens.
  run_suite "scripts/verify-marketplace-ruleset" bash scripts/verify-marketplace-ruleset.test.sh
  # ADR-140: Layer A encryption-posture detector (the mechanical resolver behind
  # the "encryption at rest + in transit" design-time gate). TS-1..8,15..17 +
  # the MB-1..MB-12 mutation battery (fixture-isolated, not suite-pass-count).
  run_suite "scripts/lint-encryption-posture" bash scripts/lint-encryption-posture.test.sh
  # The DPA Schedule 4 TOM-4 RLS-posture gate (CLO ruling 2026-09-15, #8197).
  # Schedule 4 becomes Annex II to the Module 2/3 SCCs on execution, so every
  # table name and predicate in it is a contractual representation. The -live
  # line runs the 22 assertions over the real migration corpus so a schema
  # change that falsifies the instrument reds CI; the .test.sh line is the
  # MB-0..MB-12 mutation battery proving each assertion can actually fail.
  run_suite "scripts/check-tom4-rls-posture" bash scripts/check-tom4-rls-posture.test.sh
  run_suite "scripts/check-tom4-rls-posture-live" bash scripts/check-tom4-rls-posture.sh
  # Guard Contract completeness gate (plan/SKILL.md §2.12, deepen-plan §4.11).
  # TS-1..TS-10 fixtures + the MB-1..MB-4 mutation battery. The -live line runs
  # the sweep over the real plans/ tree so a non-compliant Guard Contract landing
  # in a plan reds CI, not just the fixtures.
  run_suite "scripts/lint-guard-contract" bash scripts/lint-guard-contract.test.sh
  run_suite "scripts/lint-guard-contract-live" python3 scripts/lint-guard-contract.py
  # Window-derived closure assertions must DECLARE their assembly (per helper).
  # Enforces a declaration, not semantic completeness — no static checker can
  # prove a regex window equals its assembly. TS-1..TS-11 + MB-1..MB-2.
  run_suite "scripts/lint-window-closure-assertion" bash scripts/lint-window-closure-assertion.test.sh
  run_suite "scripts/lint-window-closure-assertion-live" python3 scripts/lint-window-closure-assertion.py \
    --allowlist scripts/lint-window-closure-assertion.allowlist.txt
  # rename-guard: allowlist->allowlist renames (the archive-kb shape) are exempt;
  # outside->allowlist still fails. TS-1..TS-6 + MB-1..MB-2.
  run_suite "scripts/rename-guard" bash scripts/rename-guard.test.sh
  run_suite "scripts/extract-api-spend" bash scripts/extract-api-spend.test.sh
  run_suite "scripts/domain-model-drift" bash scripts/domain-model-drift.test.sh
  # #6602: exit-code harness for the expenses verify_by expiry gate. Registered
  # explicitly — this runner enumerates by hand and scripts/*.test.sh is NOT in
  # the auto-glob below, so an unregistered suite is an ORPHAN that never gates
  # (the #5417 class). The gate authorizes a fail-loud financial-accuracy alarm,
  # so its arms returning the right exit codes is load-bearing coverage.
  run_suite "scripts/expenses-verify-by-check" bash scripts/expenses-verify-by-check.test.sh
  run_suite "scripts/sentry-issue" bash scripts/sentry-issue.test.sh
  run_suite "scripts/sentry-issue-discover" bash scripts/sentry-issue-discover.test.sh
  run_suite "scripts/content-publisher" bash scripts/test-content-publisher.sh
  # Registered by #6734. scripts/*.test.sh is NOT covered by any glob here (only
  # scripts/lib/*.test.sh is), so each one must be named explicitly. The first four below
  # had silently never run in any CI job; scripts/lint-orphan-test-suites.sh now fails
  # when a scripts/*.test.sh is missing from this list.
  # NOTE: "scripts/content-publisher" above is the LEGACY test-content-publisher.sh suite;
  # the residue harness below is a different file (content-publisher.test.sh). Both run.
  run_suite "scripts/content-publisher-residue" bash scripts/content-publisher.test.sh
  run_suite "scripts/skill-freshness-aggregate" bash scripts/skill-freshness-aggregate.test.sh
  run_suite "scripts/compound-promote" bash scripts/compound-promote.test.sh
  run_suite "scripts/lint-trap-tempfile-ownership" bash scripts/lint-trap-tempfile-ownership.test.sh
  run_suite "scripts/lint-shell-trace-credential-refusal" bash scripts/lint-shell-trace-credential-refusal.test.sh
  run_suite "scripts/betterstack-ingest-parity" bash scripts/betterstack-ingest-parity.test.sh
  # The SUITE above proves the lint behaves; this runs the lint over the repo
  # so a NEW violating script reds the REQUIRED `test` context. The ci.yml step
  # is the same check in an advisory job -- a credential guard a PR can merge
  # past red is theatre, and promoting that whole job is a pre-existing
  # follow-up noted in ci.yml rather than a path to fork here.
  run_suite "scripts/lint-shell-trace-credential-refusal-repo" python3 scripts/lint-shell-trace-credential-refusal.py
  # The Cloudflare token-drift detector's Access-service-token arm. Registered explicitly
  # for the same reason as its neighbours — scripts/*.test.sh is NOT auto-globbed — and
  # the omission would be especially apt here: the defect this suite pins is a detector
  # that reported a clean bill of health for a family it never enumerated, and an
  # unregistered suite is the same failure one level up.
  run_suite "scripts/check-cloudflare-token-drift" bash scripts/check-cloudflare-token-drift.test.sh
  # #6789: arms for the contention instrumentation + advisory queue that this
  # runner itself now uses. Registered explicitly — scripts/*.test.sh is NOT in
  # the auto-glob below, so an unregistered suite is an ORPHAN that gates
  # nothing (the #5417 class). lint-orphan-test-suites.sh enforces this line.
  run_suite "scripts/test-contention" bash scripts/test-contention.test.sh
  # Guard 1 for the #7869 runtime ceiling. Registered here rather than left to a
  # glob: nothing auto-discovers this directory, so an unregistered suite is
  # silently never gated — locally or in CI.
  run_suite "scripts/test-all-runtime-ceiling" bash scripts/test-all-runtime-ceiling.test.sh
  # #6789: arms for the tmpfs scratch reaper. It DELETES files, so every gate
  # (age/size/ownership/liveness/protected-path) is asserted in both directions.
  run_suite "scripts/tmpfs-guard" bash scripts/tmpfs-guard.test.sh
  # #7004: the tmp backlog purge + shared classifier. It MOVES operator files,
  # so every ladder rung (marker/schema/git/empty/prefix/protected/liveness)
  # is asserted in both directions under a sentinel base.
  run_suite "tests/scripts/tmp-purge" bash tests/scripts/test-tmp-purge.sh
  # #7004: the session allocator + Reaper 3 + quarantine drain. begin() exports
  # TMPDIR and holds an fd — every conjunct (dead/live owner, marker validity,
  # fail-closed bases/procfs, tmpfs-vs-disk disposal) is asserted both ways.
  run_suite "tests/scripts/scratch-session" bash tests/scripts/test-scratch-session.sh
  # #7537: the orphaned-PROCESS reaper. It SIGNALS processes, so every gate
  # (own-uid, unlinked cwd, unlinked fd/255, self-exclusion, mount/pid
  # namespace, age floor) is asserted in both directions here. Registered
  # explicitly for the same reason as its neighbours: scripts/*.test.sh is NOT
  # in the auto-glob below, so an unregistered suite is an ORPHAN that gates
  # nothing (the #5417 class). lint-orphan-test-suites.sh enforces this line.
  run_suite "scripts/orphan-process-reaper" bash scripts/orphan-process-reaper.test.sh
  # The mutation battery for the same detector. Both lines are needed for the
  # reason the legal-corpus pair below states: the behavioural suite proves the
  # detector can detect a planted orphan, and the battery is the only thing that
  # proves each of its GUARDS can be driven red. The preceding PR in this area
  # shipped nine guards that could not fail; measured here at ~90s for 36 rows.
  #
  # NOT registered as a live `report` run: that would be a second /proc walk per
  # launch, and a suite whose verdict depended on what else happened to be
  # running is cq-ac-must-not-depend-on-concurrent-sessions reproduced inside
  # the gate.
  run_suite "scripts/orphan-process-reaper-mutations" bash scripts/orphan-process-reaper-mutation.test.sh
  # The Incident-PIR hypothetical-paragraph strip's mutation battery (#7801). The
  # strip is a STATEFUL, ORDERED awk program, so a fixture suite alone cannot tell a
  # load-bearing rule from a decorative one — seven of its ten original fixtures pass on `main`.
  # Registered explicitly for the same reason as its neighbours: scripts/*.test.sh is
  # NOT auto-globbed, so an unregistered suite silently never gates.
  run_suite "scripts/ship-incident-pir-gate-mutations" bash scripts/ship-incident-pir-gate-mutation.test.sh
  # The two knowledge-base merge-driver batteries (#7935) are NOT registered here,
  # and that is the fix rather than an omission. They are named
  # `*-mutation.test.sh`, which is the convention every registered bash battery in
  # this repo already uses, so `SUITE_GLOBS`' `plugins/soleur/test/*.test.sh` entry
  # picks them up and `scripts/lint-orphan-test-suites.sh` (which walks `*.test.sh`)
  # can see them. An earlier revision named them `*.mutation.sh` and hand-registered
  # them with a comment explaining that nothing could auto-discover that spelling --
  # restating the hazard instead of deriving it away, and adding two more members to
  # the class #7942 tracks. Renaming closed it. Measured 17s + 6s.
  # The fstab ceiling applier. Every case drives a FIXTURE fstab through the
  # RAISE_TMPFS_FSTAB seam — the real /etc/fstab is never read or written, because a
  # test that touched it could leave the machine unbootable. Registered explicitly for
  # the same reason as its neighbours: scripts/*.test.sh is NOT auto-globbed, so an
  # unregistered suite is an ORPHAN that gates nothing.
  run_suite "scripts/raise-tmp-tmpfs-ceiling" bash scripts/raise-tmp-tmpfs-ceiling.test.sh
  # ADR-151 / #7012: arms for the rules-loader discoverability probe. The
  # NEGATIVE arms carry the weight — a probe that prints OK unconditionally is
  # indistinguishable from a working one. T6 additionally pins that preflight
  # Check 10 can still EXECUTE the plan's command, so a later "simplify it back
  # to a pipeline" edit fails here instead of silently un-verifying the probe.
  # Registered explicitly: scripts/*.test.sh is NOT auto-globbed by this runner.
  run_suite "scripts/rules-loader-stamp-probe" bash scripts/rules-loader-stamp-probe.test.sh
  run_suite "scripts/lint-orphan-test-suites" bash scripts/lint-orphan-test-suites.sh
  # Guard 1 (#7402). The LIVE line above points the linter at this working tree; this one is
  # its mutation battery, which builds a synthetic git repo and proves each of the eleven rows
  # reddens. Both are needed for the same reason the legal-corpus pair below states: the unit
  # suite proves the guard can detect a planted defect, the live line is the only thing that
  # ever points it at the real repo.
  #
  # NOT added to the linter's own REQUIRED_RUNNERS list: that array holds RUNNERS (files that
  # dispatch other suites), and a `.test.sh` is not one. The `scripts/*.test.sh` walk — now the
  # whole-repo walk — is what keeps THIS line honest.
  run_suite "scripts/lint-orphan-test-suites-mutations" bash scripts/lint-orphan-test-suites.test.sh
  # #7387 legal-corpus write-time gates. Each gate registers its unit suite AND a LIVE run
  # against the working tree: the unit suite proves the gate detects a planted defect in a
  # sandbox, the live line is the only thing that ever points it at the real corpus. The unit
  # lines are auto-enforced by lint-orphan-test-suites.sh; the live lines are enforced via its
  # REQUIRED_RUNNERS.
  #
  # check-tc-document-sha.sh is deliberately NOT registered here, and an earlier revision of
  # this block that did register it was wrong twice over. (a) It reintroduces #5780: that
  # script's TC_VERSION-bump bypass needs the step-scoped GITHUB_BASE_REF /
  # MERGE_GROUP_BASE_SHA that ci.yml gives the `tc-document-sha-guard` job and NOT this one
  # (`test-scripts` passes only GITHUB_TOKEN), so on the merge queue a legitimate stale-SHA +
  # TC_VERSION-bump PR would go green on its own required context and red here. (b) Its stated
  # rationale -- catching a normaliser weakening that "silently re-bases every drift
  # measurement" -- was measured false: weakening collapse() leaves that script green, because
  # it only detects ASYMMETRIC damage between the two normalisers. The engine pin in
  # scripts/lib/legal-normalise.test.sh is the detector for that, and it is fixture-anchored so
  # it cannot red on a legal edit.
  run_suite "scripts/lint-legal-scope-block-placement-unit" bash scripts/lint-legal-scope-block-placement.test.sh
  run_suite "scripts/lint-legal-scope-block-placement-live" bash scripts/lint-legal-scope-block-placement.sh
  run_suite "scripts/lint-legal-mirror-drift-baseline-unit" bash scripts/lint-legal-mirror-drift-baseline.test.sh
  run_suite "scripts/lint-legal-mirror-drift-baseline-live" bash scripts/lint-legal-mirror-drift-baseline.sh
  run_suite "scripts/tenant-dpa-register-guard-unit" bash scripts/tenant-dpa-register-guard.test.sh
  run_suite "scripts/tenant-dpa-register-guard-live" bash scripts/tenant-dpa-register-guard.sh count-signed
  run_suite "scripts/lint-legal-registers-unit" bash scripts/lint-legal-registers.test.sh
  # DELIBERATELY LIVE-ONLY (#7786). probe-legal-corpus-truth.sh has no `*.test.sh`
  # sibling, so lint-orphan-test-suites.sh does not require one; the unit arm with a
  # mutation matrix is owned by the follow-up filed at #7892. Registered here
  # rather than deferred because until now the probe was referenced ONLY by its own
  # docstring and its wrapper's exec -- it guarded nothing. It is what stops the
  # corrected off-host-log and journald-retention claims silently returning after
  # merge, which no other gate in this file can see: the mirror, SHA and parity gates
  # all assert AGREEMENT between a document and its mirror, and a claim that is
  # consistently wrong on both sides passes every one of them.
  run_suite "scripts/probe-legal-corpus-truth-live" bash scripts/probe-legal-corpus-truth.sh
  # BLOCKING as of 2026-09-07 (#7787, PR #7881). Promoted from advisory after one merge cycle;
  # the comment it replaced said "PROMOTION: delete the --advisory flag on the next line", which
  # would have become a false instruction the moment the flag was gone.
  #
  # EVIDENCE FOR THE PROMOTION, measured rather than assumed:
  #   - zero `::warning::lint-legal-registers` across the last 8 `main` CI runs, read from the
  #     run logs, not inferred from their conclusions;
  #   - `bash scripts/lint-legal-registers.sh` exits 0 on the promoting tree, 7/7 assertions
  #     [reading forward: 11/11 as of #7909, which added block (f). The 7 is the measurement
  #     this promotion decision rested on and stays as written];
  #   - two substantive legal amendments (#7803, #7838) landed inside the advisory window with no
  #     finding, so the register-scoped token predicate needed neither widening nor narrowing
  #     before promotion -- which was a precondition, not a nice-to-have.
  #
  # THE ASYMMETRY IS DELIBERATELY RETAINED AND MUST NOT BE "SIMPLIFIED AWAY". Under --advisory a
  # FINDING was a warning, but an "I cannot decide" (rc=2) stayed a hard failure. Promotion
  # removes the first half only. The `--advisory` parse arm, its --help string and the three
  # rc=2 assertions in lint-legal-registers.test.sh all stay: they pin that asymmetry, which is
  # what keeps a broken corpus distinguishable from a clean one.
  #
  # WHAT PROMOTION CHANGES ABOUT BLAST RADIUS -- stated because "the flag only affects this
  # invocation" is true of argv passthrough and false of the gate's reach. This suite sits in the
  # `scripts` shard, which the required `test` context depends on for EVERY PR, and it scans a
  # fixed 5-file array (4 at promotion; #7909 added the CCLA register) plus the whole
  # audits/ tree -- never the diff. After promotion, drift on
  # main reds every open PR and the merge queue, not only PRs touching the registers.
  run_suite "scripts/lint-legal-registers-live" bash scripts/lint-legal-registers.sh
  # WIRED HERE, NOT IN .github/ (#7717). check-pa-22.sh was written to guard the PA-22 register
  # entry and then ran in ZERO runners -- one of the five documented instances in
  # 2026-07-16-a-gate-that-proves-it-cannot-fail-open-shipped-its-own-proof-unwired.md. Wiring it
  # without driving it red would reproduce that learning rather than discharge it, so it was
  # mutation-tested at #7717, including by moving the TOMs row OUT of the PA-22 block: its
  # assertion (iv) uses an awk range whose terminator does not match the heading that actually
  # follows PA-22, so the range spans past Vendor Mapping and Cross-Cutting TOMs and a naive
  # inject-and-confirm passes. Art. 30 PA-31 §(g) and the 2026-07-31 DPIA memo cited
  # `git grep check-pa-22 .github/` as evidence it was unwired; that command still returns zero
  # and would have stayed literally true while its claim became false, so both were re-anchored
  # on a grep over THIS file.
  run_suite "scripts/check-pa-22-unit" bash scripts/check-pa-22.test.sh
  run_suite "scripts/check-pa-22-live" bash scripts/check-pa-22.sh
  # DECIDABILITY, not emptiness. `assert-empty` encoded a BUSINESS fact ("Jikigai has zero
  # tenants") as a passing test, so onboarding tenant #1 -- the day the guard finally matters --
  # would red the whole suite, and the under-pressure fix is to delete this line. `count-signed`
  # exits 0 on any readable register and 2 on one it cannot parse, which is the code property.
  run_suite "scripts/cron-artifact-age" bash scripts/cron-artifact-age.test.sh
  run_suite "scripts/watch-live-verify-pass" bash scripts/watch-live-verify-pass.test.sh
  run_suite "scripts/review-reminder-liveness" bash scripts/review-reminder-liveness.test.sh
  run_suite "scripts/zot-restart-loop-alarm" bash scripts/zot-restart-loop-alarm.test.sh
  # Guard 2 (#7500): the sink-side credential scrub before PUBLIC publication. Registered
  # explicitly because `scripts/*.test.sh` is NOT in SUITE_GLOBS -- an unregistered suite here
  # never gates, silently and greenly.
  run_suite "scripts/zot-restart-loop-alarm-scrub" bash scripts/zot-restart-loop-alarm-scrub.test.sh
  run_suite "scripts/followthrough-exec-bit" bash scripts/followthrough-exec-bit.test.sh
  # #6757: enforce the ${VAR:?}/${VAR?} ban in follow-through probes. Two explicit run_suite
  # lines because scripts/*.test.sh is NOT auto-globbed here — an unregistered suite is an
  # ORPHAN that gates nothing (#5417/#6734 class; lint-orphan-test-suites.sh FAILs on it).
  # -live runs the guard over the REAL tree (the actual gate); the .test.sh is the mutation
  # proof (both RED directions) that the guard can catch the banned form.
  run_suite "scripts/followthrough-varq-ban-live" bash scripts/lint-followthrough-varq-ban.sh
  run_suite "scripts/followthrough-varq-ban" bash scripts/lint-followthrough-varq-ban.test.sh
  # The differential oracle over every executable reader of the directive (#7490). Four copies
  # of the fence predicate cannot share code (two are prose an agent pastes; one is a hook that
  # must not `source` a repo file), so they are held in agreement by a walker instead.
  run_suite "scripts/followthrough-predicate-parity" bash scripts/followthrough-predicate-parity.test.sh
  # #7506: the callback-URL closure guard EXECUTES its shipped workflow step body under
  # `bash -e` (the shell Actions uses for a `run:` block with no `shell:` key). Registered
  # explicitly for the same reason as the two lines above — scripts/*.test.sh is not globbed,
  # and this suite existing-but-unregistered would gate exactly nothing, which is the failure
  # mode the guard it protects had in production.
  run_suite "scripts/follow-through-closure-guard" bash scripts/follow-through-closure-guard.test.sh
  # Was an ORPHAN until #6698 — the suite existed and passed locally but was
  # registered in no runner, so it gated nothing (exactly the class the comment
  # above warns about). It covers the sweeper's path-traversal/symlink rejection
  # AND the closed-set reopen path.
  run_suite "scripts/sweep-followthroughs" bash scripts/sweep-followthroughs.test.sh
  # #6462: exit-code harness for the zot soak's decision arms. Registered explicitly because
  # this runner enumerates suites by hand — an unregistered .test.sh is an ORPHAN that never
  # gates (the #5417 class). The soak authorizes an irreversible PAT revoke, so its arms
  # returning the right codes is not optional coverage.
  run_suite "scripts/zot-soak-6122-arms" bash scripts/followthroughs/zot-soak-6122.test.sh
  # #6616: exit-code harness for the host_name-mislabel follow-through's decision tree (identity,
  # liveness, TRANSIENT-not-PASS). Registered explicitly (orphan-suite class above) — its exit code
  # gates whether the sweeper auto-closes #6616, so a vacuous PASS regression must redden CI.
  run_suite "scripts/hostname-mislabel-web1-6616" bash scripts/followthroughs/hostname-mislabel-web1-6616.test.sh
  # #6475 (D-6): exit-code harness for the ci-deploy Sentry-POST-failure soak probe. Registered
  # explicitly (orphan-suite class above) — its exit code gates whether the sweeper auto-closes
  # #6475, and the probe's whole purpose is to be the fail-loud alarm, so a vacuous PASS (or a
  # false FAIL that pages a green codebase) must redden CI here.
  run_suite "scripts/ci-deploy-sentry-post-fail-6475" bash scripts/followthroughs/ci-deploy-sentry-post-fail-6475.test.sh
  # #8016: exit-code harness for the bwrap deploy-gate self-report soak. Registered explicitly
  # (orphan-suite class above). Its exit code decides whether the sweeper closes #8016 as an
  # environmental non-recurrence (0) or leaves it open on the next occurrence (1); the
  # load-bearing arms are FAIL-precedence over a liveness fault, SYSLOG_IDENTIFIER field
  # isolation against webhook contamination, and withholding the free-text bwrap_err from the
  # public issue comment. Mutation-proved at authoring (5/5 killed).
  run_suite "scripts/bwrap-probe-selfreport-8016" bash scripts/followthroughs/bwrap-probe-selfreport-8016.test.sh
  # #8651: exit-code harness for the web fresh-boot zot close probe. Registered EXPLICITLY
  # (scripts/followthroughs/*.test.sh is not in SUITE_GLOBS). Its exit code decides whether the
  # sweeper closes issue 8651 as completed — the observed-evidence condition zot-soak-6122.sh's
  # WEB_BLOCKER arm requires — so every sweeper exit code is driven by a fixture.
  run_suite "scripts/web-fresh-boot-zot-8651" bash scripts/followthroughs/web-fresh-boot-zot-8651.test.sh
  # #8036 1c: exit-code harness for the host-side-GHCR-retirement follow-through. Registered
  # EXPLICITLY — `scripts/followthroughs/*.test.sh` is not in SUITE_GLOBS, so a new probe's
  # harness gates nothing until this line exists (the orphan-suite class). Its exit code decides
  # #8036's closure. Load-bearing arms: the grade is a CONJUNCTION, never the pure absence the
  # operator's criterion literally stated (a host that never deploys emits no relogin_failed
  # either); the `swept=` token is the version discriminator rather than `deploy_ghcr_auth=none`,
  # which a freshly provisioned PRE-1c host also reads; `na` fails closed; and a row from a
  # non-ci-deploy producer quoting this very tracker's body is field-isolated out.
  run_suite "scripts/ghcr-read-retired-8036" bash scripts/followthroughs/ghcr-read-retired-8036.test.sh
  # #8097: exit-code harness for the SEND_FAILED-alert readback follow-through. Registered
  # explicitly (orphan-suite class above). Its exit code is the closure of #8097 (0 closes; 3 =
  # instrument did not answer / web-1 dark; 5 = a named cause for a human; 1 is NEVER emitted
  # because to the sweeper 1 reopens a human-closed issue). Load-bearing arms: the alert check
  # runs FIRST and a paused alert never touches the warehouse; the positive control is web-1
  # SCOPED (an inngest-only source is channel_dark, never row_absent); incident matching is
  # anchored on the row's own dt; raw incident objects are projected before they reach stdout.
  run_suite "scripts/send-failed-alert-probe-8097" bash scripts/followthroughs/send-failed-alert-probe-8097.test.sh
  # #8076: fixture harness for the run-report-exit first-contact follow-through. Registered
  # explicitly (orphan-suite class above). Its load-bearing arm is ROW SHAPE: the live Better
  # Stack row nests the pino payload under `.message` of the decoded `raw`, and the probe's
  # first draft read the top level, so AC18b could never FAIL (#8074 review). Every fixture is
  # the live shape; the control and the graded absence go through ONE decoder.
  run_suite "scripts/run-report-exit-first-contact-8076" bash scripts/followthroughs/run-report-exit-first-contact-8076.test.sh
  # #6297: exit-code harness for the Anthropic admin-key follow-through. Registered explicitly
  # (orphan-suite class above). Its load-bearing arm is CONTAMINATION: GitHub webhook payloads
  # ship into the same Better Stack source from the same app container, so a substring-matching
  # probe could PASS on an echo of the PR/issue body that merely QUOTES the marker and auto-close
  # #6297 while the key is still unminted. The suite mutation-proves that guard, so a regression
  # to structural matching must redden CI rather than silently false-close a tracker.
  run_suite "scripts/anthropic-admin-key-6297" bash scripts/followthroughs/anthropic-admin-key-6297.test.sh
  # #8281: exit-code harness for the compound-promote outcome soak. Registered explicitly
  # (orphan-suite class above). Same CONTAMINATION arm as 6297 one entry up: the probe's first
  # revision `grep -c`'d the marker name over undecoded rows, so an echo of the PR's own body
  # would have auto-closed #8281 with the weekly path dark. The suite also pins the DARKNESS
  # arm (no SOLEUR_CLAUDE_COST control ⇒ FAIL, never a clean zero), the trigger==cron
  # requirement (a manual fire cannot close it), and the rc-3 forwarding — whose first revision
  # `exit 3`'d inside a `$(...)` and so exited a subshell; the suite's case 7 caught it.
  run_suite "scripts/compound-promote-outcome-8281" bash scripts/followthroughs/compound-promote-outcome-8281.test.sh
  # #8611: exit-code harness for the 72h streaming rollback trigger (double-billed paid Claude
  # calls). Each FAIL arm is driven by one field; the dark-channel arm (0 markers ⇒ FAIL) pins
  # "could not measure" apart from a clean zero.
  run_suite "scripts/anthropic-double-bill-8611" bash scripts/followthroughs/anthropic-double-bill-8611.test.sh
  # #8151 AC-PM1: exit-code harness for the event-ship-merge merge-base verdict probe.
  # Registered explicitly (orphan-suite class above). Same CONTAMINATION arm as #6297/#8281:
  # every live Better Stack hit for the probe's marker strings has been a `"caller":"api"`
  # webhook receipt quoting an issue/PR body, so the probe decodes `.raw | .message` and drops
  # receipt-shaped rows before counting — an echo must never close the AC-PM1 tracker or fire
  # the defect alarm. The suite also pins FAIL-precedence over PASS, fault-to-TRANSIENT on each
  # of the three queries, and the missing-creds arm (TRANSIENT, never a spurious FAIL page).
  run_suite "scripts/ship-merge-mergebase-verdict-8151" bash scripts/followthroughs/ship-merge-mergebase-verdict-8151.test.sh
  # #8736: exit-code harness for the deploy-script-tests leg-duration soak probe (the
  # sharded structure's "under 10 min, measured over >=5 consecutive green runs" AC).
  # Registered explicitly (orphan-suite class above). Its exit code is the closure of
  # #8736 (0 closes; 1 = a qualifying leg breached the 600 s bound; 2 = NOT YET —
  # under-sampled, unclocked, or every run non-qualifying; 3 = gh failed). A run
  # qualifies ONLY when all six jobs (4 legs + fixed + done) are present, green, and
  # measured — a skipped leg is unmeasurable and fail-closed, never a green leg.
  run_suite "scripts/deploy-script-tests-legs-8736" bash scripts/followthroughs/deploy-script-tests-legs-8736.test.sh
  # #7220: exit-code harness for the ACTIVATION soak. Registered explicitly (orphan-suite class
  # above). Review found this probe returning exit 0 — which auto-closes the tracker — on a host
  # where reconciliation was BROKEN: it counted `action=failed reason=sudo_denied` rows, and the
  # sibling `SOLEUR_INFRA_CONFIG_RESTART_STDERR:` diagnostic rows, toward its PASS condition. So
  # the probe would have closed the issue on the evidence of its own recurrence. The suite pins
  # the action-vocabulary split and the freshness guard that a PASS now requires.
  run_suite "scripts/infra-config-activation-7220" bash scripts/followthroughs/infra-config-activation-7220.test.sh
  # Post-recut registry fill rate (#7341). Same failure family as the probe directly above, which
  # is why it is registered next to it: five separate fail-open defects, every one of which
  # produced a GREEN verdict. Two are worth pinning here. A 72h window straddling the recut fitted
  # one line through the old 100%-full volume and the new empty one, reporting a WIPE as a trend
  # (`PASS slope=-58.48pp/day`). And `boot_id=([0-9a-f-]+)` matched only a PREFIX of the token, so
  # two distinct boots compared equal and the scoping the whole check rests on was silently off.
  # Registration is explicit in this file, so an unregistered harness runs only when someone
  # invokes it by hand — which for a probe that auto-closes a tracker means the anti-vacuity floor
  # is decoration.
  run_suite "scripts/zot-fill-rate-7341" bash scripts/followthroughs/zot-fill-rate-7341.test.sh
  # #7500 zot_last_err redaction delivery watch (tracker #7960). Registered at birth rather than
  # after lint-orphan-test-suites.sh catches it: this probe is the only followthrough whose SUBJECT
  # is replaced mid-window by design (ADR-096 — the registry host is cloud-init-only, so delivery
  # IS a host replace), and nothing exercised a mixed-boot window before this harness.
  #
  # The suite asserts a BRANCH MARKER per case, not just an exit code, and that is load-bearing:
  # the probe has six distinct `exit 2` sites, so an exit-code-only suite collapses most of its
  # cases onto one integer. Measured — removing both `boot_id=unknown` guards leaves the exit code
  # at 2 and is caught ONLY by the marker. Measured on the first revision, which was exit-code
  # only: deleting the no-boot_id guard, deleting the trusted-region cut (while the forge
  # succeeded), and replacing the probe invocation with the expected value all left it 6/0 green.
  run_suite "scripts/zot-last-err-redact-7500" bash scripts/followthroughs/zot-last-err-redact-7500.test.sh
  # #8386 registry-host at-rest posture probe. Registered at birth, beside its sibling on the same
  # stream: the probe decides unattended whether to post a PUBLIC comment saying the registry
  # volume is mounted unencrypted, and whether the evidence is complete enough to flip a security
  # ledger row. It has 9 `exit 2`, 8 `exit 3` and 10 `exit 5` sites, so an exit-code-only suite
  # would collapse most of its cases onto three integers — the suite therefore pins a branch
  # marker per case and DERIVES its distinct-marker floor from the shipped probe.
  run_suite "scripts/registry-luks-live-8386" bash scripts/followthroughs/registry-luks-live-8386.test.sh
  # #8037 cosign verify-live probe. Registered explicitly (scripts/followthroughs/ matches no
  # glob). Its exit code closes #8037 (0), alarms on a host whose LATEST verdict is still
  # cosign_absent (1), or asks a human on a new failure class / anon_config=unavailable (5). The
  # load-bearing arms are SYSLOG_IDENTIFIER field isolation, latest-verdict grading, and
  # zero-hosts-never-PASS.
  run_suite "scripts/cosign-verify-live-8037" bash scripts/followthroughs/cosign-verify-live-8037.test.sh
  # #8296 ledger-vs-device property probe, enrolled on #8285. NOTIFY-ONLY: the suite pins that no
  # path exits 0 or 1, because a 0 would let the sweeper close the backstop-retirement tracker.
  run_suite "scripts/inngest-luks-property-8296" bash scripts/followthroughs/inngest-luks-property-8296.test.sh
  # #7761 cutover-flip rollout probe. Registered because lint-orphan-test-suites.sh caught it
  # unregistered: every assertion in it gated nothing, which for a probe that authorizes
  # closing a P1 security issue after a production host replace is the permanent silent no-op
  # its own header says it exists to retire. The suite pins the two properties that decide
  # whether the probe can be trusted: its query stub APPLIES the --grep the probe passes (a
  # stub that ignored it certified a probe whose grep matched none of the rows it counts), and
  # a post-boundary marker must carry the guard stamp only the post-fix script emits (without
  # it every observable is byte-identical to the pre-fix script, so a replace that delivered
  # nothing would report success).
  run_suite "scripts/inngest-cutover-flip-rollout-7761" bash scripts/followthroughs/inngest-cutover-flip-rollout-7761.test.sh
  # #7674 serving probe (#8015). This probe had NO suite at all while its exit code gated a P1
  # tracker AND, since probe_schema=8, decided whether a host counts as serving. Its fixtures are
  # double-encoded like the warehouse `raw` column: a harness whose seam sits above the decode
  # reproduces #7674's own 0/40-vs-40/40 measurement and passes while testing nothing.
  run_suite "scripts/inngest-host-not-serving-7674" bash scripts/followthroughs/inngest-host-not-serving-7674.test.sh
  # #6178 ADR-100 soak probe. The suite pins the never-0/never-1 invariant after every invocation
  # (0 closes, 1 reopens a tracker whose close releases four snapshots), an argv-asserting curl stub
  # that answers by requested id, the exact run-id pin on the explained groups, and a pinned clock.
  run_suite "scripts/inngest-soak-6178" bash scripts/followthroughs/inngest-soak-6178.test.sh
  # CPX22 invoice reconciliation (#7437). An operator-confirmed probe reads a production ledger
  # verdict out of free text a human typed, so the suite pins the two properties that decide
  # whether it can be trusted: the verdict is anchored at line start (an unanchored grep closes
  # the issue on a comment ASKING about it), and FAIL is evaluated before PASS (checking PASS
  # first let a retraction lose to the string it was retracting — the harness failed on the
  # original order). It also pins the accept-shape against the peers' `$`-anchored form, which
  # would reject the figure this issue requires the operator to state.
  run_suite "scripts/cpx22-invoice-reconcile-7431" bash scripts/followthroughs/cpx22-invoice-reconcile-7431.test.sh
  # Per-probe exit-code harness for the #5733 strand probe. `scripts/followthroughs/` is covered
  # by NO glob here (SUITE_GLOBS carries `scripts/lib/*.test.sh`, never this directory), so an
  # unregistered harness runs in zero runners and reads as passing. Its assembly is the probe
  # PLUS scripts/lib/trusted-verdict.sh: the lib's own matrix (auto-registered by the
  # `scripts/lib/*.test.sh` glob) cannot see a probe that sources the lib and then ignores its
  # result, and this suite cannot see a defect inside the lib — both halves are load-bearing.
  # Its sharpest row is the #6617 regression: a verdict from an author with PRIVATE org
  # membership must be honoured, which the `authorAssociation` mechanism it replaced could not do.
  run_suite "scripts/concierge-strand-754ee124-5733" bash scripts/followthroughs/concierge-strand-754ee124-5733.test.sh
  # Dedicated inngest host zot-primary boot readback (#7462/#7228). Two properties decide whether
  # this probe can be trusted to auto-close two P1 trackers, and both are pinned: PASS requires
  # `bootstrap-done` and not merely `inngest_zot`, because the pull half succeeding while nothing
  # installs IS the #7228 incident; and every count is taken from the DECODED `.stage` field, so a
  # row whose message merely echoes a stage name cannot supply it. The suite also pins the jq
  # stream shape — without `-R` + `fromjson?` one malformed warehouse line aborts the whole parse
  # and a clean PASS window reports as `channel_dark`, i.e. "the host never booted".
  run_suite "scripts/inngest-zot-boot-7462" bash scripts/followthroughs/inngest-zot-boot-7462.test.sh
  # Operator authorization for enrolling soleur-inngest as a zot client (#6500). This probe closes
  # the issue that GATES ADR-096 5.3b-i / 5.6 (#6500, CLOSED 2026-09-24), so the suite pins the two properties the #7437
  # sibling shipped wrong: the verdict is anchored at line start (an unanchored grep authorizes on
  # a comment ASKING about the criterion), and FAIL is evaluated before PASS (checking PASS first
  # lets a retraction lose to the string it retracts). Deliberately reads a HUMAN verdict rather
  # than telemetry — a green boot marker must not authorize a supply-chain retirement.
  run_suite "scripts/inngest-zot-client-authz-6500" bash scripts/followthroughs/inngest-zot-client-authz-6500.test.sh
  # (#8159 retired 2026-09-17 — issue closed; probe script + suite deleted per
  # the script's own RETIREMENT note.)
  # #8178's close criterion (git-data-boot-poll-8178.sh): PASS only on a post-merge git-data
  # dispatch whose boot poll ANSWERED — never on a boot_complete row, which was already true
  # before the fix. Pins the run anchor, the log-marker anchoring and the 2-vs-3 split.
  run_suite "scripts/git-data-boot-poll-8178" bash scripts/followthroughs/git-data-boot-poll-8178.test.sh
  # #8210's close criterion (git-data-reboot-evidence-landed-8210.sh). Since #8010 the probe is
  # four-state: it splits "the gate could not LOOK" (exit 3, rendered CANNOT ESTABLISH) out of
  # "the gate looked and the answer is no" (exit 2, NOT YET), keyed on the bracketed token of the
  # gate's verdict line. One arm per member of BOTH token sets, plus the never-0 invariant.
  run_suite "scripts/git-data-reboot-evidence-landed-8210" bash scripts/followthroughs/git-data-reboot-evidence-landed-8210.test.sh
  # #8450's close criterion (actions-queue-tail-8450.sh): PASS only on >=5
  # post-upgrade workflow_run runs with p95 deploy-arm wait < 15 min — never on
  # stale/empty/push-arm/queued-job samples, and never on an unmet precondition
  # (exit 0 would auto-close the issue). Explicit run_suite —
  # scripts/followthroughs/ is covered by no glob here.
  run_suite "scripts/actions-queue-tail-8450" bash scripts/followthroughs/actions-queue-tail-8450.test.sh
  # #8450 standing monitor core (scripts/actions-queue-health.sh): the verdict
  # logic behind scheduled-actions-queue-health.yml — live queue depth +
  # delivered-vs-entitled concurrency + median live queued age ->
  # HEALTHY/SATURATED/UNDER_ASSIGNED/UNKNOWN. Explicit run_suite —
  # scripts/*.test.sh is covered by no glob here.
  run_suite "scripts/actions-queue-health" bash scripts/actions-queue-health.test.sh
  # Inngest external-watchdog decision helpers (#6374/#6384/#6407). Registered here in #6407 —
  # these sourceable classifiers/gates were previously orphan suites (run only when invoked
  # manually), so a regression to the watchdog decision logic would have shipped with green CI.
  run_suite "scripts/inngest-liveness-classify" bash scripts/inngest-liveness-classify.test.sh
  run_suite "scripts/inngest-restart-age-gate" bash scripts/inngest-restart-age-gate.test.sh
  run_suite "scripts/inngest-restart-poll-classify" bash scripts/inngest-restart-poll-classify.test.sh
  run_suite "scripts/tunnel-connector-census" bash scripts/tunnel-connector-census.test.sh
  # #6512 Fix 2a: the seccomp-unenforced actionable-alert emitter (sourced by
  # apply-deploy-pipeline-fix.yml). Explicit run_suite — scripts/*.test.sh is not auto-globbed here.
  run_suite "scripts/seccomp-unenforced-alert" bash scripts/seccomp-unenforced-alert.test.sh
  run_suite "scripts/infra-config-red-alert" bash scripts/infra-config-red-alert.test.sh
  # Production version-drift alerter (#7091), sourced by scheduled-prod-version-drift.yml.
  # Explicit run_suite — scripts/*.test.sh is not auto-globbed here, and an unregistered
  # suite is the #5417 class: green CI over zero coverage.
  run_suite "scripts/prod-version-drift-check" bash scripts/prod-version-drift-check.test.sh
  # zot-mirror failure diagnosis (#7242 / ADR-166), sourced by reusable-release.yml AND by
  # .github/actions/cf-tunnel-registry-bridge/action.yml. Explicit run_suite — scripts/*.test.sh
  # is not auto-globbed here. Registration is also what gives this class BLOCKING enforcement:
  # `test-scripts` feeds the aggregate `test` job (ci.yml), which IS in the CI Required ruleset,
  # whereas the `lint-bot-statuses` job the other repo linters live in is advisory by design.
  run_suite "scripts/zot-mirror-diagnosis" bash scripts/zot-mirror-diagnosis.test.sh
  # (#8209, ADR-241) The tiered credential loader. It EXTRACTS the `run:` body out of
  # .github/actions/infra-credentials/action.yml with PyYAML and EXECUTES it under the
  # runner's own shell against a fail-closed `doppler` stub — a grep over that YAML pins
  # its spelling and can say nothing about what any arm DECIDES. Explicit run_suite:
  # .github/actions/**/*.test.sh is not in SUITE_GLOBS, so without this line the suite
  # runs in zero runners (the #5417 class: green CI over no coverage).
  run_suite "scripts/infra-credentials-loader" bash .github/actions/infra-credentials/infra-credentials.test.sh
  # APP_DOMAIN_BASE derivation, consumed by both D10 arms of registry-luks-recut and by
  # cf-tunnel-registry-bridge. It replaced a Doppler read of a secret that exists in no config
  # of the soleur project. Explicit run_suite — scripts/*.test.sh is not auto-globbed here.
  run_suite "scripts/derive-app-domain-base" bash scripts/derive-app-domain-base.test.sh
  # 2026-09-17: every no-SSH host read is gated on the doppler CLI, so a machine without the
  # binary makes an agent read "command not found" as "this session has no observability
  # access" and fall back to an hourly probe or to SSH. The suite's load-bearing case is the
  # unauthenticated/unknown split — a network fault must never route to a login flow. Explicit
  # run_suite — scripts/*.test.sh is not auto-globbed here.
  run_suite "scripts/ensure-doppler" bash scripts/ensure-doppler.test.sh
  # 2026-09-17: web-1 also emits SOLEUR_INNGEST_SERVER_PROBE with host_name=soleur-inngest-prd,
  # so a reader filtered on the marker (or on host_name) summarises the WRONG MACHINE while
  # looking correct. The load-bearing case is T2 — given only web-1 rows, stdout must be EMPTY.
  # Explicit run_suite — scripts/*.test.sh is not auto-globbed here.
  run_suite "scripts/inngest-host-state" bash scripts/inngest-host-state.test.sh
  # #7966: the rotation script had never completed a run (TARGETS exported after the check that
  # reads it). End-to-end against stub doppler/curl/docker; explicit, scripts/*.test.sh is not globbed.
  run_suite "scripts/rotate-supabase-db-credential" bash scripts/rotate-supabase-db-credential.test.sh
  # #7242: an alarm step that cannot run after an earlier failure cannot report the FIRE it
  # exists to report. Static gate over both alarm workflows — the condition is evaluated by
  # GitHub, so the YAML is the only artifact there is to test.
  run_suite "scripts/alarm-issue-filing-guard" bash scripts/alarm-issue-filing-guard.test.sh
  # A workflow that writes to the issue tracker must hold `issues: write`. Registered beside the
  # alarm guard because they are the same class one layer apart: that one checks an alarm step CAN
  # RUN, this one checks it CAN WRITE. The dispatcher's refusal artifact satisfied the first and
  # failed the second, silently, behind `|| true`.
  run_suite "scripts/lint-workflow-issue-write-scope" bash scripts/lint-workflow-issue-write-scope.test.sh
  # THE -live ARM IS THE GATE. The suite above only proves the lint BEHAVES correctly against
  # synthesized fixtures in $TMP; it never points the lint at `.github/workflows`, so without this
  # line a workflow carrying the exact shipped defect merges green and the lint catches nothing.
  # Every peer workflow lint is registered as this same pair (see lint-workflow-step-env-refs and
  # lint-workflow-errexit-capture above) — this one was registered once, which made it decoration.
  run_suite "scripts/lint-workflow-issue-write-scope-live" python3 scripts/lint-workflow-issue-write-scope.py
  # A `uses: ./…` step resolves from the runner's WORKSPACE, so its job must have run
  # actions/checkout first. scheduled-marketplace-drift.yml's checkout-free drift-check job ended
  # in one under `continue-on-error: true`: the runner could not resolve the composite, the step
  # went green, and the Sentry monitor recorded zero check-ins for 37 days. Same class as the two
  # lints above, one layer earlier: that the alarm step can even be FOUND. Both halves are
  # required — the unit suite proves the RULE is right, the -live arm proves the TREE is clean.
  run_suite "scripts/lint-workflow-local-action-checkout" bash scripts/lint-workflow-local-action-checkout.test.sh
  run_suite "scripts/lint-workflow-local-action-checkout-live" python3 scripts/lint-workflow-local-action-checkout.py
  # A DANGLING committed symlink breaks the GitHub Actions runner's repository-archive
  # extraction, so it fails `Set up job` for EVERY `$/…` and `owner/repo/path@ref` reference to
  # this repo — measured on run 35360150848. The check lives in its own file rather than inline:
  # `--enumerate-commands` encodes argv with TAB/NEWLINE delimiters and rejects a multi-line
  # `bash -c` body, which is how the first revision of this registration broke
  # `battery-tag-authorship` (an empty root set, refusing to classify).
  run_suite "scripts/no-dangling-committed-symlinks" bash scripts/no-dangling-committed-symlinks.test.sh
  # #7242 / ADR-166: no operator-facing CI message may name a cause the job did not measure.
  # Registered HERE rather than in the lint-bot-statuses job on purpose -- that job is
  # advisory (absent from required-checks.txt and the ruleset), and this defect has already
  # survived two non-blocking corrections. The suite invokes the lint, so a regression above
  # the committed .highwater reds the required `test` context.
  run_suite "scripts/lint-diagnosis-claims" bash scripts/lint-diagnosis-claims.test.sh
  # Dogfood Grok measure/bootstrap (#6545/#6546). Explicit run_suite — scripts/dogfood/
  # is not in the auto-glob; orphan suites are the #5417 class (green CI, zero coverage).
  run_suite "scripts/dogfood/grok-gpu-bootstrap" bash scripts/dogfood/grok-gpu-bootstrap.test.sh
  run_suite "scripts/dogfood/grok-measure" bash scripts/dogfood/grok-measure.test.sh
  # Stock preflight gate (#6453). Registered HERE because nothing auto-discovers
  # tests/scripts/ — the bash *.test.sh glob further down does NOT include it, and
  # infra-validation.yml only lists apps/web-platform/infra/*.test.sh. Without this line
  # the gate that stands between a -replace and a stranded fleet ships with zero coverage.
  run_suite "tests/scripts/stock-preflight-gate" bash tests/scripts/test-stock-preflight-gate.sh

  # (#6977) The git-data birth route's gates. NOTHING else runs these:
  # lint-orphan-test-suites.sh's producer is `git ls-files '*.test.sh'`, which the
  # `test-<name>.sh` convention used under tests/scripts/ does not match (#7402 widened that
  # walk from scripts/*.test.sh to the whole repo, but the SUFFIX convention is the producer's
  # scope and tests/scripts/ is deliberately outside it), and
  # apps/web-platform/infra/run-registered-suites.sh DERIVES its list by globbing
  # `apps/web-platform/infra/**/*.test.sh` (presence is registration), so a
  # tests/scripts/ suite is structurally invisible to both. These three run_suite lines
  # are the ONLY registration — an unregistered gate suite is silent AND green, which is
  # the exact shape that let a fail-open rung ship in #3366.
  run_suite "tests/scripts/plan-gate-preamble" bash tests/scripts/test-plan-gate-preamble.sh
  run_suite "tests/scripts/git-data-host-birth-gate" bash tests/scripts/test-git-data-host-birth-gate.sh
  run_suite "tests/scripts/betterstack-read-classify" bash tests/scripts/test-betterstack-read-classify.sh
  run_suite "tests/scripts/git-data-boot-signal-poll" bash tests/scripts/test-git-data-boot-signal-poll.sh
  run_suite "tests/scripts/git-data-birth-readiness-gate" bash tests/scripts/test-git-data-birth-readiness-gate.sh
  # (#7025) The rung-2 evidence-capture decision function. Registered HERE for the same
  # reason as every line around it: nothing auto-discovers tests/scripts/. This script is
  # what decides whether the file that RELEASES the birth interlock gets written, so an
  # unregistered — and therefore silent AND green — suite would leave that decision unproven
  # on every PR.
  run_suite "tests/scripts/git-data-rung2-evidence-capture" bash tests/scripts/test-git-data-rung2-evidence-capture.sh
  # (#5274, Guard 3) The rung-2 plan-shape chokepoint: the payload phase and replace arm may
  # replace only the host, never the dirtied plaintext volume or the LUKS volume. Registered
  # here for the reason above: nothing auto-discovers tests/scripts/.
  run_suite "tests/scripts/git-data-rung2-plan-shape" bash tests/scripts/test-git-data-rung2-plan-shape.sh
  # (#7226 / #5914, ADR-237) SSH host-key pinning guards. Registered HERE for the same
  # reason as the lines above: nothing auto-discovers tests/scripts/. Guard 1 (no unpinned
  # host-key option anywhere in the tree), its mutation harness, and Guard 7 (the
  # git-data-pin-redeploy.yml tracker that loads a rotated git-data pin into the app).
  run_suite "tests/scripts/no-tofu-ssh" bash tests/scripts/test-no-tofu-ssh.sh
  run_suite "tests/scripts/no-tofu-ssh-mutation" bash tests/scripts/test-no-tofu-ssh-mutation.sh
  run_suite "tests/scripts/dispatch-web-redeploy" bash tests/scripts/test-dispatch-web-redeploy.sh
  # Supabase advisor RLS gate (#3366). Registered HERE for the same reason as the
  # line above: nothing auto-discovers tests/scripts/. This is the harness that
  # proves the gate cannot silently pass (a 401 must not parse to a clean 0);
  # without this line that proof runs nowhere and the gate's entire value claim
  # is unverified on every PR — the exact defect the gate exists to catch.
  run_suite "tests/scripts/supabase-advisor-scan" bash tests/scripts/test-supabase-advisor-scan.sh
  # EU residency allow-set parity (#6453 review). {nbg1,fsn1,hel1} is replicated across three
  # terraform validations + the stock gate's default; nothing pinned them together, and the
  # gate's own suite overrides the value to stay hermetic, so the shipped default was asserted
  # nowhere. Drift makes the gate advise a location terraform rejects.
  run_suite "tests/scripts/eu-location-allowset-parity" bash tests/scripts/test-eu-location-allowset-parity.sh
  # betterstack-query.sh hot+archive UNION (#6288). remote() alone is the ~40-minute hot
  # window, so a hot-only query answers `--since 24h` with 40 minutes — no error, just a
  # short answer. That silently starved every soak gate built on it (#6288's needs 2h of
  # span and could never PASS). Hermetic: stubs curl, asserts SQL shape, never live rows.
  run_suite "tests/scripts/betterstack-query-archive" bash tests/scripts/test-betterstack-query-archive.sh
  # #7569 — the ingest-refusal discriminator and its cause-annotation probe. tests/scripts/ is
  # NOT auto-globbed by this runner, so an unregistered suite gates nothing, silently and
  # greenly. Both are registered here in the same commit that adds them.
  run_suite "tests/scripts/betterstack-absence-classifier" bash tests/scripts/test-betterstack-absence-classifier.sh
  run_suite "tests/scripts/betterstack-ingest-probe" bash tests/scripts/test-betterstack-ingest-probe.sh
  run_suite "tests/scripts/betterstack-roundtrip-latency" bash tests/scripts/test-betterstack-roundtrip-latency.sh
  run_suite "tests/scripts/rule-id-regex-parity" python3 -m unittest tests.scripts.test_rule_id_regex_parity
  run_suite "tests/scripts/rule-metrics-aggregate" bash tests/scripts/test-rule-metrics-aggregate.sh
  run_suite "scripts/rule-metrics-aggregate" bash scripts/rule-metrics-aggregate.test.sh
  # #8302 / ADR-229: the offline transition classifier and the SKILL.md byte ratchet;
  # #8325: the Sharp Edges turn-measurement script. scripts/lib/incidents-roots.test.sh
  # rides the scripts/lib/*.test.sh glob; these three do not sit under a globbed
  # directory, so they are registered here explicitly. This is the
  # ratchet SUITE's only registration: lint-orphan-test-suites.sh refuses double coverage,
  # so the ci.yml step that used to run it was removed. The ratchet LINT itself runs as a
  # step in the required `rule-body-lint` job, which is the depth-0 base it needs.
  run_suite "scripts/classify-workflow-transitions" bash scripts/classify-workflow-transitions.test.sh
  run_suite "scripts/measure-plan-sharp-edges-turns" bash scripts/measure-plan-sharp-edges-turns.test.sh
  # #8377 / ADR-235 — the regen-if-stale gate in front of the now-untracked KB index.
  # `scripts/*.test.sh` is not covered by SUITE_GLOBS (which reaches plugins/, .claude/hooks/,
  # apps/ and scripts/lib/ but never the bare scripts/ directory), so this explicit line is
  # the suite's ONLY registration. Without it it runs nowhere and gates nothing.
  run_suite "scripts/ensure-kb-index" bash scripts/ensure-kb-index.test.sh
  # THE GENERATOR AGAINST THE REAL TREE. `generate-kb-index.sh --check` used to do two jobs:
  # assert the committed index was fresh (moot once untracked) AND execute the generator over
  # the real ~9,500-file knowledge-base/ in the required `test-scripts` context. #8377 retired
  # the flag as if it did one job, and every surviving caller is `--soft` (WARN + exit 0), so a
  # regression that only manifests on real corpus content -- a frontmatter shape, a filename,
  # a collation edge -- would have been green in CI and reached the operator as "no prior art"
  # (#8384 review). Writes to a scratch dir, never the tree: this runner's boundary check
  # treats any repo write as a FATAL. Measured 3 s. Positive floors, not `-s`: a generator that
  # emitted a header and nothing else would pass an emptiness check. It is a FILE, not an
  # inline `bash -c '...'`: `--enumerate-commands` encodes each registration as one TSV row and
  # refuses an argv element containing a NEWLINE, so a multi-line inline body reds
  # battery-tag-authorship.test.sh ("refusing to classify against an empty root set").
  run_suite "scripts/generate-kb-index-live" bash scripts/generate-kb-index-live.test.sh
  run_suite "scripts/lint-skill-body-budget" bash scripts/lint-skill-body-budget.test.sh
  run_suite "tests/scripts/weakness-miner" bash tests/scripts/test-weakness-miner.sh
  run_suite "tests/scripts/audit-ruleset-bypass" bash tests/scripts/test-audit-ruleset-bypass.sh
  run_suite "tests/scripts/audit-bot-codeql-coverage" bash tests/scripts/test-audit-bot-codeql-coverage.sh
  # #7226 / ADR-237 Guard 3 (bash site): the SSH host-key pin writer shared by the CI bridge and
  # git-data-cutover.yml. tests/scripts/ is not globbed, so this line is its only registration.
  run_suite "tests/scripts/write-known-hosts" bash tests/scripts/test-write-known-hosts.sh
  # #7226: the web-1 pin capture script (refuses under CI; stubbed keyscan). scripts/*.test.sh is
  # not globbed, so this line is its only registration.
  run_suite "scripts/capture-web-1-host-key" bash scripts/capture-web-1-host-key.test.sh
  run_suite "tests/commands/sync-rule-prune" bash tests/commands/test-sync-rule-prune.sh
  run_suite "tests/commands/sync-domain-model" bash tests/commands/test-sync-domain-model.sh
  # tests/commands/ is registered by these explicit lines ONLY — there is no glob here, and
  # lint-orphan-test-suites.sh's whole-repo walk is keyed on the `*.test.sh` SUFFIX, which the
  # `test-<name>.sh` convention in this directory does not carry. That linter covers the
  # directory through a SEPARATE dedicated loop (#7442) rather than through its main walk; a
  # new suite added below without a run_suite line silently never gates.
  run_suite "tests/commands/sync-producer-reachability" bash tests/commands/test-sync-producer-reachability.sh
  run_suite "tests/scripts/kb-drift-walker" bash tests/scripts/test-kb-drift-walker.sh
  # Destroy-guard counters (apply-* workflow trio). Pre-existing gap from
  # #4420 closed in #4419 — without these in CI, a PR that mutates a filter
  # to gut its clauses passes review only through CODEOWNERS approval.
  run_suite "tests/scripts/destroy-guard-counter-github" bash tests/scripts/test-destroy-guard-counter.sh
  run_suite "tests/scripts/destroy-guard-counter-sentry" bash tests/scripts/test-destroy-guard-counter-sentry.sh
  run_suite "tests/scripts/destroy-guard-counter-web-platform" bash tests/scripts/test-destroy-guard-counter-web-platform.sh
  # Pre-apply entrypoint gate (#6767 / ADR-136). Registered HERE for the same
  # reason as the destroy-guard trio above: nothing auto-discovers tests/scripts/
  # (the bash *.test.sh glob further down covers only scripts/lib/*.test.sh etc.,
  # NOT tests/scripts/test-*.sh), so an unregistered suite is an ORPHAN that gates
  # nothing. This suite proves the fail-closed gate that stands between a
  # whole-list ruleset create and a clobbered live dashboard entrypoint.
  run_suite "tests/scripts/preapply-entrypoint-gate" bash tests/scripts/test-preapply-entrypoint-gate.sh
  # host image/apply coherence preflight (AC10b) — drives the standalone preflight
  # via its test seams (no docker/network/prod write). Registered here alongside
  # the destroy-guard trio: it is the host-agnostic coherence verifier the
  # host_creates HALT's pinned-image chain names (#6575).
  run_suite "tests/scripts/host-image-coherence-preflight" bash tests/scripts/test-host-image-coherence-preflight.sh
  # #6197: inngest-host-replace scoped-recreate destroy-guard (same sourced-gate shape the
  # web2-recreate gate used before #6575 deleted it).
  run_suite "tests/scripts/inngest-host-replace-gate" bash tests/scripts/test-inngest-host-replace-gate.sh
  # #7695 — the two guards on apply_target=inngest-volume-recut. NOTHING auto-discovers
  # tests/scripts/: the `*.test.sh` glob elsewhere in this file cannot match a `test-*` prefix, so
  # an unregistered suite here never gates and the failure is silent-and-green.
  run_suite "tests/scripts/inngest-volume-recut-gate" bash tests/scripts/test-inngest-volume-recut-gate.sh
  run_suite "tests/scripts/inngest-host-dark-gate" bash tests/scripts/test-inngest-host-dark-gate.sh
  # #6894 — ADR-142 Guard 3: the per-address plan-shape gate on the inngest-host dispatch (which
  # also creates the additive LUKS volume). Same orphan trap as above: nothing globs tests/scripts/test-*.sh.
  run_suite "tests/scripts/inngest-host-shape-gate" bash tests/scripts/test-inngest-host-shape-gate.sh
  # registry-host-replace scoped-recreate destroy-guard (5-target; preserves the zot store volume).
  run_suite "tests/scripts/registry-host-replace-gate" bash tests/scripts/test-registry-host-replace-gate.sh
  # #7542: vector-redeliver scoped-delivery gate. Unlike the -replace arms above it permits a bare
  # ["create"] as well as ["delete","create"] (a delivery, not a replace), and its no-op outcome is
  # SUCCESS rather than a refusal — so "nothing to redeliver" cannot be reported for a lone delete.
  run_suite "tests/scripts/vector-redeliver-gate" bash tests/scripts/test-vector-redeliver-gate.sh
  # #7542 WIRING (not logic), and the same split as the D10 pair below. The suite above proves the
  # gate DECIDES correctly; it cannot prove the vector_redeliver job calls it, calls it on the
  # artifact the apply consumes, or is gated on its verdict at all. It also pins the one property
  # no unit test can see: the CF Tunnel bridge must precede the plan, because the plan bakes
  # TF_VAR_ci_ssh_private_key and `apply <savedplan>` accepts no variable input. Registered
  # explicitly — nothing auto-discovers tests/scripts/ (#3366).
  run_suite "tests/scripts/vector-redeliver-wiring" bash tests/scripts/test-vector-redeliver-wiring.sh
  # registry-region-migrate destroy-guard (#6288; permits the registry's OWN store-volume replace across regions, forbids all out-of-scope destroys).
  run_suite "tests/scripts/registry-region-migrate-gate" bash tests/scripts/test-registry-region-migrate-gate.sh
  # registry-luks-recut destroy-guard (#6929). The INVERSE of registry-host-replace: it REQUIRES
  # the store volume to be replaced alongside its attachment and the host, so cloud-init meets a
  # fresh RAW device and luksFormats it. A preserved volume is the footgun that darks the
  # registry. Its suite also asserts the two gates DISAGREE on the same fixtures.
  run_suite "tests/scripts/registry-luks-recut-gate" bash tests/scripts/test-registry-luks-recut-gate.sh
  # D10 pre-destroy authorization gate (#6929 / #7277) — authorizes a destroy only on a restore
  # CI has just executed into an empty registry. Leads with a positive control.
  run_suite "tests/scripts/registry-pull-path-health" bash tests/scripts/test-registry-pull-path-health.sh
  # #7555. tests/scripts/ is NOT auto-globbed by this runner (the *.test.sh glob cannot match a
  # test-* prefix), so an unregistered suite here would run in ZERO runners, green and invisible.
  run_suite "tests/scripts/registry-replace-preflight" bash tests/scripts/test-registry-replace-preflight.sh
  # #8279. The dispatcher's derivation helper (which merged change does this run deliver, and
  # where is its verdict tracked). Same registration reason as the line above: tests/scripts/
  # is not globbed, so this explicit line is the suite's ONLY runner.
  run_suite "tests/scripts/registry-delivery-change" bash tests/scripts/test-registry-delivery-change.sh
  # Its mutation battery (~70 s, sandboxed copies, every row asserts it landed). Committed and
  # registered rather than left in a transcript, so its kills protect something tomorrow.
  run_suite "tests/scripts/registry-delivery-change-mutation-battery" bash tests/scripts/test-registry-delivery-change-mutation-battery.sh
  # MOVED to the scripts-heavy carve-out near the end of this file (#8006): at ~860 s the
  # registry-gate-mutation-battery is the single most expensive registration in the runner,
  # so the dedicated test-scripts-heavy matrix carries it one-suite-per-leg. Its
  # RELEVANCE-GATED (ADR-181) `_diff_touches` arm and provenance comment moved with it.
  # Registered explicitly, next to its D10 sibling. Nothing auto-discovers tests/scripts/: this
  # file's *.test.sh globs cannot match the `test-*` prefix, and scripts/lint-orphan-test-suites.sh
  # walks the whole repo but only for the `*.test.sh` SUFFIX, which this file does not carry. An
  # unregistered suite here runs in ZERO runners and is silent and green (#3366).
  run_suite "tests/scripts/registry-restore-from-ghcr" bash tests/scripts/test-registry-restore-from-ghcr.sh
  # D10 WIRING (not logic). The suites above prove the gate's logic; none of them proves the
  # workflow USES it. That gap is exactly how the gate shipped reading a Doppler secret which
  # exists in no config of the soleur project, aborting at PREPARE before it could reach its own
  # destroy-guard. A `run:` body is not executable by any of them, so this asserts the wiring
  # statically over both arms plus the composite action the restore leg runs inside.
  # Deliberately a separate file: the mutation battery sandboxes the D10 suite into a tree with
  # no .github/, so a workflow-reading row appended there would fail its baseline and harness_die.
  # Registered explicitly for the same reason as its neighbours — nothing auto-discovers
  # tests/scripts/ (#3366).
  run_suite "tests/scripts/registry-d10-workflow-wiring" bash tests/scripts/test-registry-d10-workflow-wiring.sh
  # D11 post-apply liveness poller (#6929) — requires a heartbeat TRANSITION, since the monitor
  # reports the dead host's residual `up` for ~90s and exposes no last_ping_at.
  run_suite "tests/scripts/registry-heartbeat-poll" bash tests/scripts/test-registry-heartbeat-poll.sh
  # (#7278) The read-only zot disk-inventory lever's two suites. Registered HERE for the same
  # reason as every line around them — nothing auto-discovers tests/scripts/, this file's
  # *.test.sh globs cannot match the `test-*` prefix, and lint-orphan-test-suites.sh's whole-repo
  # walk is keyed on that same suffix, so an unregistered suite here runs in ZERO runners while
  # looking covered.
  #
  # The FIRST is the enumerator: dedup-by-digest arithmetic against hand-computed literals, index
  # recursion, the partial/unreadable/empty-catalog verdict taxonomy, verb and egress confinement
  # measured at the wire by a recording origin, and secret masking. The number this lever exists
  # to produce is only as trustworthy as that arithmetic, and no other gate reads it.
  #
  # The SECOND is the round-trip gate, and it is separate on purpose: the pass condition was
  # deliberately extracted OUT of workflow YAML, where no test can reach it. Its primary case is
  # that a marker present with a DIFFERENT run_id must NOT pass, plus an arm requiring the gate to
  # FAIL when fed an undecoded fixture (Better Stack's `raw` column is double-encoded JSON, so a
  # bare grep silently returns nothing — a probe that can never pass, and therefore never fail).
  #
  # The workflow/composite-shape half of this feature is NOT here: it lives in
  # apps/web-platform/infra/registry-zot-inventory-workflow-guard.test.sh, which this runner
  # already covers through the CI-registered infra runner.
  run_suite "tests/scripts/zot-inventory" bash tests/scripts/test-zot-inventory.sh
  run_suite "tests/scripts/zot-inventory-assert-marker" bash tests/scripts/test-zot-inventory-assert-marker.sh
  run_suite "tests/scripts/zot-disk-sample" bash tests/scripts/test-zot-disk-sample.sh
  # (#7440) The zot CONTAINER-LOG channel's readback probe. Registered HERE for the same reason as
  # its #7278 siblings above: nothing auto-discovers tests/scripts/.
  #
  # ONLY this fixture suite belongs in this file. The shipper's own suite is an INFRA suite and its
  # registration point is its path under `apps/web-platform/infra/`, which
  # apps/web-platform/infra/run-registered-suites.sh derives by glob — adding it here instead
  # would run it in ZERO runners (#3366), silent and green.
  #
  # The probe is INERT UNTIL DISPATCHED (the registry host is cloud-init-only, so merging applies
  # nothing), which makes every one of its arms a false-green candidate: a probe that can never PASS
  # is indistinguishable from one correctly reporting a not-yet. Its highest-value case is the
  # FALSE-GREEN — a window holding nothing but SOLEUR_ZOT_DISK heartbeat rows whose zot_last_err
  # echoes `zotregistry.dev` must NOT pass. That is not hypothetical: it is the state production is
  # in right now, where a bare grep for that string returns 53 rows over 6h and every one is an echo.
  run_suite "tests/scripts/zot-log-channel-probe" bash tests/scripts/test-zot-log-channel-probe.sh
  # git-data-host-replace scoped-recreate destroy-guard (#6242; 5-target, preserves BOTH data volumes + LUKS passphrase by omission).
  run_suite "tests/scripts/git-data-host-replace-gate" bash tests/scripts/test-git-data-host-replace-gate.sh
  # git-data root-key create-gate arm (#8189, ADR-220, Guard 4), sourced by the replace and birth gates.
  run_suite "tests/scripts/git-data-root-key-arm" bash tests/scripts/test-git-data-root-key-arm.sh
  run_suite "tests/scripts/git-data-root-token-census" bash tests/scripts/test-git-data-root-token-census.sh
  run_suite "tests/scripts/infra-privileged-tier-census" bash tests/scripts/test-infra-privileged-tier-census.sh
  # workspaces-luks-cutover FIRST-PROVISION destroy-guard (#6604). Permits the +create of the
  # five #6593-authored workspaces_luks resources; ABORTs any touch of the live plaintext
  # /mnt/data volume/attachment or the web-1 server, any passphrase re-mint, any destroy/forget,
  # or anything out of scope. Registered HERE — nothing auto-discovers tests/scripts/.
  run_suite "tests/scripts/workspaces-luks-cutover-gate" bash tests/scripts/test-workspaces-luks-cutover-gate.sh
  run_suite "tests/scripts/workspaces-luks-recut-gate" bash tests/scripts/test-workspaces-luks-recut-gate.sh
  # web-host BIRTH gate (#6730) — the INVERSE of web2-retire-gate: requires exactly one
  # hcloud_server create, matching the dispatched host key, with zero destroys. It is the
  # only check on the one route granted the host_creates capability (a new dispatch job
  # inherits nothing from the per-PR apply's inline HALT), so every arm is load-bearing and
  # the suite mutation-proves each one. Registered HERE — nothing auto-discovers tests/scripts/.
  run_suite "tests/scripts/web-host-birth-gate" bash tests/scripts/test-web-host-birth-gate.sh
  # web-host REPLACE gate (#6969) — the SIBLING of the birth gate above and its opposite by
  # contract: exactly one delete+create of the dispatched host, both volume families and the
  # LUKS passphrase preserved by omission, plus positive requirements on the NIC, the volume
  # attachment and the fleet firewall re-attachment. Same "a new dispatch job inherits
  # nothing" reasoning, so the same mutation battery. Registered HERE for the same reason the
  # line above says — nothing auto-discovers tests/scripts/, and an unregistered suite is
  # silent AND green.
  run_suite "tests/scripts/web-host-replace-gate" bash tests/scripts/test-web-host-replace-gate.sh
  run_suite "tests/scripts/destroy-guard-regex-parity" bash tests/scripts/test-destroy-guard-regex-parity.sh
  run_suite "tests/scripts/destroy-guard-sentry-scope-guard" bash tests/scripts/test-destroy-guard-sentry-scope-guard.sh
  run_suite "tests/scripts/tenant-integration-gate-verdict" bash tests/scripts/test-tenant-integration-gate-verdict.sh
  # #7964 — the cross-ref dev-Supabase advisory mutex. Registered HERE for the
  # same reason: nothing under tests/scripts/ is auto-discovered, and an
  # unregistered mutex suite is silent AND green while the banners it pins
  # decide whether a contended run proceeds visibly or silently.
  run_suite "tests/scripts/dev-suite-mutex" bash tests/scripts/test-dev-suite-mutex.sh
  # The wiring gate is a separate suite for the same reason the D10 wiring
  # gate is separate: the unit suite stubs psql and cannot see YAML — only
  # this file asserts the workflow actually wires acquire/release/anchors.
  run_suite "tests/scripts/dev-suite-mutex-wiring" bash tests/scripts/test-dev-suite-mutex-wiring.sh
  # #8203 — the fail-closed verdict of the `vendor-pin-required` aggregator
  # (#5585 pattern instance #3). Registered HERE for the same reason: nothing
  # under tests/scripts/ is auto-discovered, and an unregistered verdict suite
  # is silent AND green while the allow-list it pins decides whether the #8181
  # NOTICE binding actually gates merges.
  run_suite "tests/scripts/vendor-pin-gate-verdict" bash tests/scripts/test-vendor-pin-gate-verdict.sh
  # #6589 — the Sentry full-root delete path. These three gate the contract that
  # makes `terraform destroy` reachable at all for infra/sentry/**: the absence of
  # address-scoping in the apply (the #6074/#4929 root cause), the fail-closed
  # aggregator verdict, and the squash-body emulation that decides whether a
  # pre-staged [ack-destroy] will actually reach the merge commit.
  run_suite "tests/scripts/sentry-destroy-counts" bash tests/scripts/test-sentry-destroy-counts.sh
  run_suite "tests/scripts/sentry-full-root-apply" bash tests/scripts/test-sentry-full-root-apply.sh
  run_suite "tests/scripts/sentry-destroy-gate-verdict" bash tests/scripts/test-sentry-destroy-gate-verdict.sh
  run_suite "tests/scripts/sentry-squash-ack-detect" bash tests/scripts/test-sentry-squash-ack-detect.sh
  run_suite "tests/scripts/sentry-create-gate" bash tests/scripts/test-sentry-create-gate.sh
  # #7650 Phase 2 — Guard A (create protection, now wired into BOTH workflow jobs)
  # and Guard B (the forget<->import bijection) for the sentry_alert adoption.
  # Registered HERE for the reason the neighbouring comments give and this suite
  # makes acute: nothing under tests/scripts/ is auto-discovered, and the guards
  # this suite covers are the only things standing between a one-character edit
  # and 27 live paging rules — including the GDPR Art. 33 breach alert — being
  # orphaned or duplicated. An unregistered suite here would read as green
  # forever while asserting nothing.
  run_suite "tests/scripts/sentry-alert-adoption-guards" bash tests/scripts/test-sentry-alert-adoption-guards.sh
  run_suite "tests/scripts/sentry-ac17-derived-counts" bash tests/scripts/test-sentry-ac17-derived-counts.sh
  # #7650 §2.9 — the live-fidelity probe. A fidelity probe compares a document to
  # itself for a living, and its degenerate implementation (return PASS) satisfies
  # every happy-path test anyone writes. This suite is one row per DRIFT CLASS the
  # probe's header claims to detect, so the claim is checked rather than asserted.
  # Hermetic: the live GET is replaced by SENTRY_FIXTURE_RULES throughout.
  run_suite "tests/scripts/sentry-alert-live-fidelity" bash tests/scripts/test-sentry-alert-live-fidelity.sh
  # #8050 — the PR-time reference gate and the `tf`/`reference` sides of the
  # projection module. The probe's reference is projected from the Terraform
  # plan; the committed copy the daily job reads is held equal to the plan by
  # this gate. G0 is the positive control; every mutation row asserts its own
  # literal, so "the gate always exits 1" cannot pass as coverage. Hermetic:
  # synthesized two-rule plan, no Terraform, no credentials.
  run_suite "tests/scripts/sentry-alert-reference-gate" bash tests/scripts/test-sentry-alert-reference-gate.sh
  # The drift workflow's VERDICT BRANCHING, extracted from the shipped YAML and
  # executed — never restated. Two of its three outcomes are silent when wrong: a
  # verdict that files nothing looks like a clean run, and a wrongly-closed issue
  # looks like a fixed one. Neither is visible in a green workflow list.
  run_suite "tests/scripts/sentry-alert-drift-workflow" bash tests/scripts/test-sentry-alert-drift-workflow.sh
  # Class D (live monitor with no .tf block) is the delete path's other half: the
  # full-root apply can only reclaim a monitor the config once declared. Its whole
  # value is the non-zero exit — registered here because nothing auto-discovers
  # tests/scripts/, and an unregistered suite would leave the gate's fail-closed
  # claim asserted nowhere.
  run_suite "tests/scripts/sentry-monitors-audit-class-d" bash tests/scripts/test-sentry-monitors-audit-class-d.sh
  # md->Slack-mrkdwn converter (scripts/md-to-mrkdwn.mjs). Runs under stock
  # ubuntu-latest node (no setup-node — same bare-`node` precedent as
  # secret-scan.yml). node --test ships in Node >=18.
  run_suite "scripts/md-to-mrkdwn" node --test scripts/md-to-mrkdwn.test.mjs
  # Gitleaks-allowlist parser harness (#7402). It shells out to `node` for the parser under
  # test, so it sits beside md-to-mrkdwn above under the same stock-node precedent rather than
  # in the bun shard. It ran in ZERO runners until now: `apps/web-platform/test/` is under no
  # glob in this file and appears in no workflow step, which is exactly the shape the widened
  # scripts/lint-orphan-test-suites.sh walk exists to surface. Measured 0.8 s, 18 assertions.
  run_suite "apps/web-platform/test/parse-gitleaks-allowlists" bash apps/web-platform/test/__synthesized__/parse-gitleaks-allowlists.test.sh
  # Board-status mapper (#7402). #7402's body claims board-status-sync.yml runs this suite;
  # that is REFUTED — the workflow runs scripts/board/set-board-status.sh, the SCRIPT, and
  # names the .test.sh nowhere. `scripts/board/` is covered by no glob here, so this explicit
  # line is the suite's only registration anywhere. Mocks `gh` on PATH; needs no token.
  run_suite "scripts/board/set-board-status" bash scripts/board/set-board-status.test.sh

  # EXPLICIT, because no glob in this file reaches it. The suite extracts the
  # `run:` bodies out of the two skill-security-scan workflows and EXECUTES them
  # under the shell GitHub Actions uses, so it is the only thing in the repo that
  # can tell "the gate blocked this input" from "the gate never looked" (#7629).
  run_suite "scripts/skill-security-scan-step-body" bash scripts/skill-security-scan-step-body.test.sh

  # EXPLICIT: scripts/followthroughs/ is covered by no glob here. (One further
  # companion from that directory, ccla-representative-icla-7922, is registered
  # in the `webplat` shard instead — it needs tsx, which this shard lacks.)
  # Drives the T5
  # skip-persistence probe against nine fixture samples through a fake `gh`,
  # with fixtures padded past the 64 KiB pipe buffer so the SIGPIPE race the
  # probe was losing matches to is actually reachable (#7574).
  run_suite "scripts/followthroughs/t5-skip-persistence-bound-7510" bash scripts/followthroughs/t5-skip-persistence-bound-7510.test.sh
fi

# Named bun-test entries — bun shard.
if want_bun; then
  run_suite "test/content-publisher" bun test test/content-publisher.test.ts
  run_suite "test/x-community" bun test test/x-community.test.ts
  run_suite "test/linkedin-community" bun test test/linkedin-community.test.ts
  run_suite "test/pre-merge-rebase" bun test test/pre-merge-rebase.test.ts
fi

# Vitest in apps/web-platform — webplat shard.
# VITEST_SHARD (e.g., "1/2") is forwarded to vitest --shard for matrix sharding
# in CI. When unset, vitest runs all files. The empty-string suppression via
# ${VAR:+...} keeps local invocation byte-identical.
#
# VITEST_SHARD is passed via env: to the inner bash so the inner shell expands
# it under its own quoting (single-quoted outer, double-quoted inner). This
# blocks shell-injection if a caller ever sets VITEST_SHARD to a value
# containing `;` or `$(…)`. The matrix literal in ci.yml is always `K/N`
# today, but the script is a public surface — defense in depth.
#
# Split into two suites (#7498) so the app-local half can be DECLINED on a diff
# that touches nothing in the app, while the repo-wide half still runs.
#
#   repo-wide  — subject is the repository (plugin scripts, workflow YAML, the
#                knowledge base). NEVER gated: these exist to catch drift in
#                exactly the diffs that touch no app file, so gating them would
#                decline them on the commits they guard.
#   unit +     — subject is the app. Gated on apps/web-platform/.
#   component
#
# 42 of the last 80 commits on origin/main (52%; 96/200 over 200) touch no
# apps/web-platform file, so the decline is the common case rather than an edge.
# The split is safe only because test/repo-wide-containment.test.ts proves no
# gated suite reads outside the app — without it a new repo-reading test would
# land in the gated project and be silently declined. That guard runs in the
# repo-wide project, so it is never gated by the thing it guards.
if want_webplat; then
  # --- Precondition: apps/web-platform deps present (#2398 arm of #8580) -----
  #
  # Every suite in this arm resolves a binary out of the app's install — the
  # vitest projects via `npm run test:ci`, and ccla-add plus its followthroughs
  # companion via `apps/web-platform/node_modules/.bin/tsx` (see the registration
  # comments below). With the app's node_modules absent, the arm does not fail
  # here — it fails DEEP, well inside the suite, as `vitest: not found` (#2398's
  # exact report), after the suite's own setup has already run. So the check
  # runs FIRST, at arm entry, and names the deterministic recovery.
  #
  # Three alternatives considered and rejected:
  #   * skip_suite — this runner is a gate; a declined webplat arm reports
  #     green-shaped output over coverage it never obtained (the ADR-181
  #     vacuity class). An unmet precondition is a REFUSAL, not a decline.
  #   * a sibling worktree's vitest — vitest.config.ts imports resolve
  #     against THIS checkout's tree, never the sibling's node_modules, so a
  #     borrowed binary still dies on config imports. Only an install in this
  #     worktree satisfies the arm.
  #   * a conditional registration — this file's run_suite sites are parsed
  #     STATICALLY for the shard-totality reference (see the markdown-lint
  #     registration comment in the scripts arm); gating one on install state
  #     counts it in the reference and assigns it to no leg.
  #
  # rc 2, the "this runner cannot run" class (missing prerequisite), not 4 —
  # 4 means "refused before anything ran", and under TEST_GROUP=all the
  # earlier groups HAVE already run by the time control reaches this block.
  # Exempt under --enumerate for the same reason the refusal guards above are:
  # an enumerate pass starts no suite and resolves no binary, and the
  # shard-totality guard enumerates on legs that install no node deps at all.
  # Exempt under SANDBOX_RECORD for the identical reason: the coverage-notice
  # suite's sandbox arms replace run_suite with a recorder, so no suite starts
  # and no binary resolves — refusing there would make every arm measure this
  # refusal instead of the gate under test (the CI test-scripts shard installs
  # no app deps, so the refusal would fire unconditionally).
  if (( _ENUMERATE == 0 )) && [[ -z "${SANDBOX_RECORD:-}" ]]; then
    # The arm's dependency set is vitest AND tsx (ccla-add + its followthroughs
    # companion exec tsx directly, per the comment above) — probing vitest alone
    # would let a partial install fail deep in exactly the way this guard exists
    # to prevent.
    _missing_webplat_bins=()
    for _b in vitest tsx; do
      [[ -x "apps/web-platform/node_modules/.bin/$_b" ]] || _missing_webplat_bins+=("$_b")
    done
    if (( ${#_missing_webplat_bins[@]} > 0 )); then
      echo "ERROR: refusing the webplat arm — apps/web-platform/node_modules is absent or incomplete." >&2
      echo "       Missing bin(s): ${_missing_webplat_bins[*]}. Every suite in this group resolves" >&2
      echo "       a binary from the app's install and would fail deep. Install the deps, then re-run:" >&2
      echo "           npm ci --ignore-scripts --prefix apps/web-platform" >&2
      exit 2
    fi
  fi

  # `component` runs ALWAYS, alongside repo-wide. #7498 evaluated gating it and
  # declined on measurement: at ~80 s it is a ~39 s expected saving, "statistically
  # the same quantity this PR already declined for the union predicate", and taking
  # it "would import a new fail-open surface to buy back exactly what was refused".
  #
  # #7666 gated it anyway, reasoning that the containment guard covers `component`
  # at zero marginal cost once it exists for `unit`. That reversed an explicit,
  # measured decision by the issue author on the strength of an argument about
  # cost, not about the risk the decision was made on — so it is reverted here.
  # The invariant the guard asserts (0 of 240 `.test.tsx` escape the app) is kept:
  # it is true and worth keeping true, it is simply no longer load-bearing.
  run_suite "apps/web-platform [repo-wide+component]" env VITEST_SHARD="${VITEST_SHARD:-}" \
    bash -c 'cd apps/web-platform && npm run test:ci -- --project repo-wide --project component ${VITEST_SHARD:+--shard="$VITEST_SHARD"} 2>&1'

  if _diff_touches "${WEBPLAT_APP_PATHS[@]}"; then
    run_suite "apps/web-platform [unit]" env VITEST_SHARD="${VITEST_SHARD:-}" \
      bash -c 'cd apps/web-platform && npm run test:ci -- --project unit ${VITEST_SHARD:+--shard="$VITEST_SHARD"} 2>&1'
  else
    _relevance_declined=$((_relevance_declined + 1))
    skip_suite "apps/web-platform [unit]" "relevance" \
      "cd apps/web-platform && npm run test:ci -- --project unit"
  fi

  # THE SHARD MATTERS, and the PATH is what keeps the surfaces disjoint.
  #
  # This suite drives `ccla-add.sh`, which resolves the roster validator through
  # `apps/web-platform/node_modules/.bin/tsx`. `test-scripts` is documented as
  # "bash + python3 + bun" and runs no `npm ci`, so that binary is absent there
  # and EVERY invocation dies at the script's own operator-fault exit 2 —
  # measured, 23 of 33 assertions red on CI run 34117976566 while the suite
  # passed locally, because a developer checkout has node_modules. It therefore
  # runs in THIS shard, whose job runs `npm ci` in apps/web-platform.
  #
  # It lives in `apps/cla-evidence/test/` rather than beside the script in
  # `apps/cla-evidence/scripts/` for one specific reason: that directory is a
  # SUITE_GLOBS entry, and a file matching both the glob and this explicit
  # registration is double-covered. `lint-orphan-test-suites.sh` refuses that,
  # correctly — the covered set is a union, so deleting this line would leave the
  # glob still reporting coverage while the `continue` that excluded it meant
  # nothing ran. An ack was the other option and would have been false: every
  # entry in DOUBLE_COVERED_ACK has BOTH surfaces genuinely running the suite.
  run_suite "apps/cla-evidence/test/ccla-add.test.sh" bash apps/cla-evidence/test/ccla-add.test.sh
  # EXPLICIT, and in THIS shard rather than `scripts`: scripts/followthroughs/ matches no
  # SUITE_GLOBS entry, and this companion needs apps/web-platform/node_modules/.bin/tsx to
  # run `resolveCoverageMapNoticeEpoch` as the authority its per-fixture parity arm compares
  # the probe against. The `test-scripts` shard installs no npm dependencies, so registering
  # it there would make the only cross-implementation check in the pair fail on a missing
  # binary rather than on a disagreement.
  run_suite "scripts/followthroughs/ccla-representative-icla-7922" bash scripts/followthroughs/ccla-representative-icla-7922.test.sh
fi

# plugins/soleur bun-test recursion + blog-link-validation — bun shard.
# Co-located because validate-blog-links.sh's link-check half reads _site/
# at the repo root, which plugins/soleur/test/marketing-content-drift.test.ts
# builds inside `bun test plugins/soleur/` (the drift-guard builds to
# mkdtemp, not _site). Suites run sequentially and the script self-builds
# when no site-dir is passed, so there is no live race today; co-location
# is defense against any future xargs-P attempt that would introduce one
# within a runner.
if want_bun; then
  run_suite "plugins/soleur" bun test plugins/soleur/
  run_suite "blog-link-validation" bash scripts/validate-blog-links.sh
  # frontmatter-strip three-way parity (#6794). The suite ALSO matches the
  # scripts-shard `scripts/lib/*.test.sh` glob below, but that shard has no bun,
  # so its strip.ts arm skip-gates there. Registering it here (bun guaranteed)
  # is what actually exercises strip.ts == strip.py == strip.sh in CI.
  run_suite "scripts/frontmatter-strip-parity" bash scripts/lib/frontmatter-strip.test.sh
fi

# Bash *.test.sh glob — scripts shard. (ci-deploy.test.sh runs in infra-validation.yml.)
# .claude/hooks/lib/*.test.sh added 2026-08-10 (#7409). Shell globs do NOT cross
# `/`, so the flat `.claude/hooks/*.test.sh` below never reached the `lib/`
# subdirectory: every suite there had NEVER gated CI. That is how the #5454
# vacuous-green class survived inside session-state.test.sh (34 KB, orphaned) —
# it relocates to plugins/soleur/test/ in this change, and this glob closes the
# hole for its remaining sibling, freeze-lock.test.sh (13 assertions, passing).
# Measured against every *.test.sh under any lib/ in the repo: after this line,
# zero orphans remain in that class. Do NOT check such coverage with Python
# `fnmatch` — its `*` DOES cross `/`, so it reports these files as already
# covered and falsifies the finding.
#
# .claude/hooks/*.test.sh added 2026-05-15 (#3799 prereq to #3789); covers the
# 8 hook tests that previously only the session-rules-loader entry pulled in.
if want_scripts; then
  # #7103 R3/R4/R5(b) + the R5(a) follow-up. These live in scripts/, which the glob below does
  # NOT cover (it reaches scripts/lib/*.test.sh, not scripts/*.test.sh), so each is registered
  # explicitly — an unregistered gate is the #3366 class, a suite whose whole claim is "this
  # cannot silently pass" running in zero runners.
  #
  # THE SHARD MATTERS. These were registered under want_bun, whose CI job (`test-bun`) installs
  # bun and node and nothing else. All four are bash, and two shell out to python3:
  # digest-oracle-guard.test.sh hard-exits 2 when `python3 -c 'import yaml'` fails, which
  # run_suite reports as a FAIL — a red required check for want of an interpreter its shard was
  # never documented to have. `test-scripts` is the job ci.yml describes as "bash + python3",
  # which is where the other 33 scripts/*.test.sh siblings already run.
  run_suite "scripts/betterstack-assert-absence" bash scripts/betterstack-assert-absence.test.sh
  run_suite "scripts/digest-oracle-guard" bash scripts/digest-oracle-guard.test.sh
  # Sandbox-only: copies scripts/ and .github/ into a mktemp -d, mutates the copies, and asserts
  # the working tree is unchanged when it finishes.
  # RELEVANCE-GATED (ADR-181), ~189 s. The battery COPIES all of scripts/ and .github/ into its
  # sandbox but only DEPENDS on the paths the predicate names; gating on the copy set would match
  # nearly every diff and never decline. Referenced by name — see the registry gate above.
  if _diff_touches "${CF_TUNNEL_BATTERY_PATHS[@]}"; then
    run_suite "scripts/cf-tunnel-liveness-gate-mutations" bash scripts/cf-tunnel-liveness-gate-mutations.test.sh
  else
    _relevance_declined=$((_relevance_declined + 1))
    skip_suite "scripts/cf-tunnel-liveness-gate-mutations" "relevance" \
      "bash scripts/cf-tunnel-liveness-gate-mutations.test.sh"
  fi
  # Pins that this runner's OWN infra coverage claim matches whether it actually invoked the
  # infra runner. Registered here rather than under want_bun for the same reason as above.
  run_suite "scripts/test-all-infra-coverage-notice" bash scripts/test-all-infra-coverage-notice.test.sh
  # Guards this file's own webplat split (#7498). Registered next to its
  # sibling: both assert shape properties of test-all.sh that nothing else
  # would notice rotting.
  run_suite "scripts/test-all-webplat-gate" bash scripts/test-all-webplat-gate.test.sh
  # Pins this runner's THREE-CLASS result taxonomy (#7424): a signal-shaped exit renders as
  # [KILLED], stays out of the failure count, and exits 3. Registered here rather than under
  # want_bun for the same reason as its neighbours — it shells out to python3 to build its
  # sandbox, and `test-scripts` is the shard documented as "bash + python3".
  run_suite "scripts/test-all-killed-classification" bash scripts/test-all-killed-classification.test.sh
  # The #7545 pre-launch capacity signal: the verdict, --capacity, the wait
  # heartbeat and re-sample, and the diff-justification report. Registered
  # EXPLICITLY beside its neighbours for the same reason they state — repo-root
  # `scripts/*.test.sh` is NOT in SUITE_GLOBS (which carries `scripts/lib/*.test.sh`
  # only), so an unregistered suite here runs in zero runners and stays green
  # forever. AC18 asserts this registration by its invoked PATH, not its label,
  # because the orphan linter derives coverage from the path.
  run_suite "scripts/test-all-capacity-signal" bash scripts/test-all-capacity-signal.test.sh
  # ADR-178/ADR-187 textual parity pin (#7429): the signal-shape classifier is inlined in three
  # runners, and this asserts the three copies still agree. Registered explicitly beside its
  # sibling above — scripts/*.test.sh is NOT auto-globbed here, and this suite arrived
  # unregistered, which the widened scripts/lint-orphan-test-suites.sh walk caught on its first
  # run against the branch. A parity pin nothing executes is three copies with no pin at all.
  # Measured 0.1 s, 32 assertions, bash-only.
  run_suite "scripts/suite-exit-class-parity" bash scripts/suite-exit-class-parity.test.sh
  run_suite "scripts/battery-tag-authorship" bash scripts/battery-tag-authorship.test.sh
  # #8231: `--enumerate` must not depend on a WORKING bun, only on the absence of a broken one.
  # Registered explicitly for the reason its neighbours state — repo-root `scripts/*.test.sh` is
  # NOT in SUITE_GLOBS, so an unregistered suite here runs in zero runners and stays green
  # forever. This one guards the producer for three consumers that fail closed on the enumerate
  # stream's record count, including `scripts/battery-tag-authorship` two lines above, which was
  # measured at exit 1 on a host whose only defect was an unpinned `mise` bun shim. bash-only.
  run_suite "scripts/test-all-enumerate-toolchain" bash scripts/test-all-enumerate-toolchain.test.sh
  # #8322: the affected gate's own mutation battery — flags, classification,
  # chokepoint declines, fallbacks, refusals. Runner-SUT suites are ALWAYS_ON in
  # the declarations lib (the runner is always its own SUT); registered
  # explicitly for the same reason as its neighbours — scripts/*.test.sh is not
  # auto-globbed.
  run_suite "scripts/test-all-affected" bash scripts/test-all-affected.test.sh
  # TEST_GROUP=affected (#8591) — this runner's diff-scoped selection mode, the
  # heuristic sibling of the --affected flag above. Registered explicitly beside
  # its neighbours for the reason they state: repo-root `scripts/*.test.sh` is
  # NOT in SUITE_GLOBS, so an unregistered suite runs in zero runners and stays
  # green forever. The suite drives sandbox copies against a fixture git repo,
  # so it never takes the real advisory lock.
  run_suite "scripts/test-all-group-affected" bash scripts/test-all-group-affected.test.sh
  run_suite "scripts/battery-ref-guard" bash scripts/battery-ref-guard.test.sh
  # MOVED: scripts/battery-tag-authorship-mutations now registers under want_scripts_heavy
  # in the carve-out near the end of this file (#8006).
  # The patterns are declared ONCE, at the top of this file, and published by
  # `--print-suite-globs` so scripts/lint-orphan-test-suites.sh reads the same list this loop
  # expands. Nested loop rather than one flat `for f in ${SUITE_GLOBS[@]}`: the flat form
  # depends on unquoted word-splitting, so a pattern containing a space would expand into two
  # broken patterns silently. Iteration order is unchanged (pattern 1's matches, then 2's, …),
  # so TEST_TIMING_LOG rows and suite ordering are byte-identical to the inline list this
  # replaced.
  for _suite_glob in "${SUITE_GLOBS[@]}"; do
  for f in $_suite_glob; do
    [[ -f "$f" ]] || continue
    # RELEVANCE-GATED (ADR-181) — declined on 96% of recent commits, and the only suite this loop
    # registers whose cost justifies a predicate. The justification is the SKIP RATE, not a
    # wall-clock figure: see the measurement caveat in scripts/lib/test-relevance-paths.sh, where
    # three reps of an unchanged tree spanned 23-91 s under sibling load. A per-file `if` rather
    # than a lookup table: bash 3.2 has no associative arrays and one gated member does not earn a
    # mapping.
    #
    # The label is written LITERALLY, not as "$f". skip_suite's contract is "$1 = label (must
    # match the label the suite would have run under)" and this loop's label IS the path, so the
    # two agree byte-for-byte — TEST_TIMING_LOG rows and any anchored reader stay stable.
    #
    # An `if` block, never `[[ … ]] && continue`: _diff_touches's own header forbids the short
    # form because under `set -e` its exit status depends on the call site.
    #
    # `run_suite "$f" bash "$f"` below is left byte-for-byte unchanged, so the glob's discovery
    # surface is untouched and the suite is still registered exactly once, by the glob.
    if [[ "$f" == "plugins/soleur/test/c4-from-components.test.sh" ]]; then
      if ! _diff_touches "${C4_PRODUCER_PATHS[@]}"; then
        _relevance_declined=$((_relevance_declined + 1))
        skip_suite "plugins/soleur/test/c4-from-components.test.sh" "relevance" \
          "bash plugins/soleur/test/c4-from-components.test.sh"
        continue
      fi
    fi
    run_suite "$f" bash "$f"
  done
  done
fi

# --- Nested CI-registered runners (#7103 R5(a)) -----------------------------------------
# Until now this file only NAMED these two runners, in comments and echo strings, while
# executing neither. That is the defect: a runner mentioned in a NOTE is not a runner that
# ran, and "all tests pass" was read as evidence for suites this file never invoked (#6730,
# #6969). Each registration counts as ONE suite at the aggregate level; the nested runner
# reports its own per-suite counts inside that line.
#
# The infra RUNNER is registered, never its suites individually (re-derive via
# `bash apps/web-platform/infra/run-registered-suites.sh --list`; the count moves
# with the directory). run-registered-suites.sh derives its list by globbing
# `apps/web-platform/infra/**/*.test.sh` (presence is registration) and reports
# untracked stragglers; enumerating the suites here would fork that list and
# recreate the very drift the derivation prevents.
#
# Do not hand-edit that count: `--list` prints it, and scripts/lint-orphan-test-suites.sh reads
# the same command for its infra registration surface, so the number above is checkable in one
# second rather than trusted.
if want_infra; then
  # Relevance gate (2.2). The infra runner is the expensive one, so a docs-only run should
  # not pay for it. Reuses the preamble's `_infra_in_diff` verdict rather than re-deriving
  # it, so the notice up top and the gate down here can never disagree — including its
  # fail-SAFE arm, where an undeterminable diff sets 1 and the runner RUNS.
  #
  # Every skip is LOUD and carries the exact re-run command. A silent skip would reproduce,
  # one level up, the same "green that is not evidence" this phase exists to close.
  if [[ "${SOLEUR_INCIDENT_SKIP:-0}" == "1" ]]; then
    # Named incident bypass (2.3). The relevance gate fires on exactly the paths an infra
    # hotfix must touch, so without a documented lever this lands minutes on the incident
    # path. The alternative was leaving TEST_GROUP as an undocumented escape hatch — which
    # silently drops far more than the infra runner and says so nowhere.
    _infra_skip_reason="incident"
    skip_suite "apps/web-platform/infra/run-registered-suites.sh" "incident" \
      "bash apps/web-platform/infra/run-registered-suites.sh"
  # `_FULL_GATE` (#8322) is the third conjunct: an explicit --full means the
  # whole battery, and the infra runner is part of it — declining it on a
  # clean diff would make `--full` silently mean "almost everything".
  elif [[ "$TEST_GROUP" == "infra" || "$_infra_in_diff" == 1 || "$_FULL_GATE" == 1 ]]; then
    # Sampled against BOTH decline counters: a ceiling decline AND an
    # affected-mode not-affected decline (#8322) each return 0 from run_suite
    # without executing, and either must keep _infra_ran at 0.
    _infra_declined_before=$(( _ceiling_declined + _affected_declined ))
    run_suite "apps/web-platform/infra/run-registered-suites.sh" bash "apps/web-platform/infra/run-registered-suites.sh"
    # THE ONLY site that may set this. Every downstream coverage claim reads it, so it records
    # what happened rather than what was predicted.
    #
    # CONTROL REACHING THIS LINE IS NOT EVIDENCE THE RUNNER RAN (#7869). A ceiling-declined
    # suite returns 0 from run_suite WITHOUT starting, so the unconditional form recorded
    # coverage for a suite that never executed — and the epilogue then printed
    # "apps/web-platform/infra/ IS covered above" over nothing, which is precisely the
    # predicted-vs-happened confusion the comment above exists to prevent. The decline
    # counter is sampled either side of the call because it is the only signal that
    # distinguishes the two, run_suite returning 0 in both cases.
    if (( _ceiling_declined + _affected_declined == _infra_declined_before )); then
      _infra_ran=1
    fi
  else
    _infra_skip_reason="not_in_diff"
    skip_suite "apps/web-platform/infra/run-registered-suites.sh" "not_in_diff" \
      "bash apps/web-platform/infra/run-registered-suites.sh"
  fi
fi

# --- SCRIPTS-HEAVY: THE COST CARVE-OUT (#8006) ----------------------------------------------
#
# The three cost-heaviest registrations are gated by want_scripts_heavy, not want_scripts:
# ci.yml runs them on a dedicated `test-scripts-heavy` matrix so each lands on its own leg,
# while the lighter scripts group fans out over six legs. TEST_GROUP=all still covers all
# three — want_scripts_heavy's `all` arm is what keeps the ship gate, the lefthook battery
# and main-health-monitor running them.
#
# The column-0 `if`/`fi` shape is load-bearing: scripts-shard-totality.test.sh's Guard 1b
# derives the heavy reference set from `^if want_scripts_heavy; then$` .. `^fi$` regions, so
# an inlined or indented gate leaves the reference EMPTY — and the guard reds, which is the
# intended fail-closed shape.
if want_scripts_heavy; then
  # The mutation battery for the registry-pull-path-health and registry-replace-preflight suites. Registered, not ad-hoc: its previous incarnations
  # lived in a session transcript, so their "15/15 caught" protected nothing the next day — and
  # when it was finally committed it found 15 of its mutations surviving, including a seam that
  # could replace the pass condition itself. It sandboxes its own copies of both SUTs, so it
  # neither mutates the worktree nor depends on suite ordering here (#7277).
  #
  # RELEVANCE-GATED (ADR-181). At ~860 s this is the single most expensive suite in the runner —
  # about 32% of a full local run — and it guards a script most PRs never touch. The predicate is
  # referenced BY NAME: no path literal may appear on a `run_suite` line, because
  # lint-orphan-test-suites.sh reads registration out of those lines and a `*.test.sh` literal
  # sitting there would be extracted as a registration, so an inline list would certify a
  # DIFFERENT suite than the one this gate executes. (Since #7402 the extraction is anchored on
  # the COMMAND — the token after `bash` — not on the whole line, which narrows but does not
  # remove the hazard: a path literal in command position is still read as a registration.)
  if _diff_touches "${REGISTRY_BATTERY_PATHS[@]}"; then
    run_suite "tests/scripts/registry-gate-mutation-battery" bash tests/scripts/test-registry-gate-mutation-battery.sh
  else
    _relevance_declined=$((_relevance_declined + 1))
    skip_suite "tests/scripts/registry-gate-mutation-battery" "relevance" \
      "bash tests/scripts/test-registry-gate-mutation-battery.sh"
  fi
  # Sits between its battery siblings by cost, not by theme: ~380 s measured on the CI leg,
  # which is what earns it a dedicated leg rather than a home in the light group.
  run_suite "scripts/battery-tag-authorship-mutations" bash scripts/battery-tag-authorship-mutations.test.sh
  # The guard-script fixture runner. Its own MIN_SUITES floor (11 as of #7429, which added the
  # signal-propagation guard as the 11th fixture suite) is what makes a silently empty run fail
  # rather than pass, so registering it here inherits that floor instead of re-implementing one.
  # The number is stated here for the reader; the runner is the authority — re-derive with
  # `grep '^MIN_SUITES=' .github/scripts/test/run-all.sh` rather than trusting this comment.
  #
  # THE FLOOR AND A DECLINE ARE DIFFERENT OUTCOMES. The floor still applies whenever the runner
  # runs, but it is not evaluated at all when the runner is DECLINED — nothing inside it executes.
  # What distinguishes "declined" from "ran and found nothing" is skip_suite's output, which names
  # the suite, the reason, and the exact re-run command. Reading the floor as coverage of a run
  # that never happened is the same green-that-is-not-evidence shape ADR-181 closes one level up.
  #
  # RELEVANCE-GATED (ADR-181) — declined on 56% of recent commits. `run_suite … bash
  # .github/scripts/test/run-all.sh` keeps its
  # command shape byte-for-byte because scripts/lint-orphan-test-suites.sh's REQUIRED_RUNNERS check
  # anchors on the COMMAND, not the label.
  if _diff_touches "${GITHUB_SCRIPTS_SUITE_PATHS[@]}"; then
    run_suite ".github/scripts/test/run-all.sh" bash .github/scripts/test/run-all.sh
  else
    _relevance_declined=$((_relevance_declined + 1))
    skip_suite ".github/scripts/test/run-all.sh" "relevance" \
      "bash .github/scripts/test/run-all.sh"
  fi
fi

# --- A LEG THAT OWNS NOTHING IS A FAIL, NOT A PASS (#7902) ----------------------------------
#
# Placed after the last registration site so it sees the final ordinal count, and BEFORE the
# enumerate terminator so it covers the enumerate and executing paths alike.
#
# The validator above rejects only SYNTACTIC malformation. Any `k/N` with k greater than the
# registration count is well-formed, in range, and matches no ordinal — measured, `376/376`
# assigns 0 of 375 and the executing path then prints `=== 0/0 suites passed ===` and exits 0,
# so `needs.test-scripts.result` is `success` and the required `test` check is GREEN over ZERO
# coverage. That is exactly the outcome the validator's own comment claims is prevented
# ("Falling back to running NOTHING would be worse still"), reachable through the environment
# rather than through the matrix literal — and SCRIPTS_SHARD is a job-level `env:` inherited by
# every step and child in that job, which is why this PR also had to clear it in
# scripts/lint-orphan-test-suites.sh.
#
# Bounding N does not cover it: 376/376 is inside every bound. Only counting the assignment does.
if (( _SHARD_N > 0 && _shard_assigned == 0 )); then
  echo "ERROR: SCRIPTS_SHARD=${_SHARD_K}/${_SHARD_N} assigned 0 of ${_shard_ordinal} registrations." >&2
  echo "       A leg that owns nothing would report success having run nothing. Refusing." >&2
  echo "       k must be <= the registration count; N must not exceed it either." >&2
  exit 2
fi

# --- Enumerate mode terminates HERE, after the last registration site (#7902) --------------
#
# Every registration has now passed the chokepoint, so the leg's assigned label list is
# complete. Nothing below this point concerns enumeration: the epilogue, the repo-write
# boundary delta and the summary all describe a run that EXECUTED suites, and this one
# executed none.
#
# The EXIT trap is cleared first: its note reports "the boundary check did not run", which is
# true and meaningless on a path that started no suite, and would read as a warning about a
# clean enumerate pass.
if (( _ENUMERATE == 1 )); then
  echo "[shard] enumerate complete: ${_shard_assigned} registration(s) assigned of ${_shard_ordinal} walked (k/N=${_SHARD_K}/${_SHARD_N})" >&2
  # Disarm the #8761 watchdog: the walk finished inside the deadline. Guarded —
  # an exit through a guard above skips arming; wait reaps the watchdog
  # subshell (its own TERM trap already killed the tracked sleep grandchild).
  _enum_wd_disarm
  # The wholesale `trap - EXIT` also bypasses the two cleanups the chain
  # carries — run them explicitly so an enumerate pass does not leak a
  # soleur-inc-*/soleur-refguard.* tmpdir per invocation.
  _soleur_refguard_cleanup
  _soleur_inc_cleanup
  trap - EXIT
  exit 0
fi

_emit_bytes_probe "__run_boundary_end__"
tc_epilogue "${_TC_RUN_START_ENTRIES:-0}"

# --- REPO WRITE BOUNDARY (end) -----------------------------------------------------------
#
# Compared as a DELTA, so a tree that was already dirty at the start is fine; what is forbidden
# is this run CHANGING it. Reported before the summary block so the marker stays the last
# `=== ` line (#6750), and counted into `failed` so the exit code carries it: a run that
# corrupted the repository is not a pass, whatever the suites said.
# Counted into the BREAKDOWN line alongside `skipped`, per ADR-181's decision that a new outcome
# class of this runner is "a counted verdict, not an absence". REPORT still changes no exit code —
# ADR-181's `skipped` is the precedent for exactly that shape — but an outcome visible only as
# stderr prose above a several-thousand-line log reads as silence, which is the polarity that ADR
# already rejected once.
_repo_observations=0
_repo_unmeasured_dims=0
if [[ "$_repo_guard_ok" == 1 ]]; then
  if _repo_state_after="$(_repo_state)"; then
    # Classified per dimension rather than as one boolean. A sibling worktree's branch advancing
    # and this worktree's HEAD moving under it are not the same event, and collapsing them makes
    # the FATAL line cry wolf on the common case until nobody reads it.
    _repo_verdict="$(repo_boundary_classify "$_repo_state_before" "$_repo_state_after" || true)"

    # A dimension that failed to capture at BOTH boundaries produces no UNMEASURABLE (the manifests
    # agree) and no body delta — so the verdict is empty and, before this, the entire block
    # including NOT INSPECTED was skipped. Silence is this runner's "clean" signal, so that read as
    # a clean bill of health over a check that never looked. Narrowed coverage must speak even when
    # there is no delta to report.
    _repo_narrowed=""
    while IFS=$'\t' read -r _d _st; do
      [[ -n "$_d" ]] || continue
      [[ "$_st" == "measured" ]] || _repo_narrowed="$_repo_narrowed $_d"
    done <<<"$(repo_boundary_manifest "$_repo_state_after"; repo_boundary_manifest "$_repo_state_before")"
    if [[ -z "$_repo_verdict" && -n "$_repo_narrowed" ]]; then
      echo "" >&2
      echo "NOTE: no repo-write delta was detected, but this run did NOT measure every dimension." >&2
      echo "      A clean boundary is not evidence about the ones it could not read:" >&2
      repo_boundary_render_not_inspected "$_repo_state_before" "$_repo_state_after" >&2
      _repo_unmeasured_dims=$(printf '%s' "$_repo_narrowed" | wc -w | tr -d ' ')
    fi

    if [[ -n "$_repo_verdict" ]]; then
      _repo_fatal="$(printf '%s\n' "$_repo_verdict" | { grep '^FATAL' || true; })"
      _repo_report="$(printf '%s\n' "$_repo_verdict" | { grep '^REPORT' || true; })"
      _repo_unmeasurable="$(printf '%s\n' "$_repo_verdict" | { grep '^UNMEASURABLE' || true; })"

      if [[ -n "$_repo_fatal" ]]; then
        failed=$((failed + 1))
        echo "" >&2
        echo "[FATAL] A SUITE WROTE TO THE LIVE REPOSITORY. This runner is read-only here." >&2
        echo "        Last suite started: ${_repo_last_suite}" >&2
        echo "        (the boundary is sampled exactly TWICE — once at the first suite and once" >&2
        echo "         here — so this names where the run had REACHED, not which suite wrote. No" >&2
        echo "         per-suite snapshot is taken, so the run has no evidence about any other" >&2
        echo "         individual suite.)" >&2
        echo "" >&2
        echo "        WHAT CHANGED:" >&2
        printf '%s\n' "$_repo_fatal" | while IFS=$'\t' read -r _sev _dim _detail; do
          echo "          [$_dim] $_detail" >&2
          echo "                 next: $(repo_boundary_next_action "$_dim" "$_detail")" >&2
        done
        echo "" >&2
        _rb_head_before="$(printf '%s\n' "$_repo_state_before" | sed -n 's/^head\t//p')"
        _rb_head_after="$(printf '%s\n' "$_repo_state_after"  | sed -n 's/^head\t//p')"
        if [[ -n "$_rb_head_before" && "$_rb_head_before" != "$_rb_head_after" ]]; then
          echo "        HEAD before: ${_rb_head_before}" >&2
          echo "        HEAD after : ${_rb_head_after}" >&2
          echo "        (good-sha is the BEFORE value; bad-sha is the AFTER value.)" >&2
        fi
        # The recovery recipe is HEAD/worktree surgery — a config, refs, or shallow FATAL has no
        # good-sha/bad-sha and nothing to restore, so printing the steps there would send the
        # operator through irrelevant ref surgery. The per-dimension `next:` line above carries
        # each of those dimensions' own remedy.
        if printf '%s\n' "$_repo_fatal" | grep -qE '^FATAL[[:space:]]+(head|worktree)'; then
          echo "        Committed work survives; UNCOMMITTED work may not. Recover in this order:" >&2
          echo "          1. git push origin <good-sha>:refs/heads/<branch>   # durability BEFORE local surgery" >&2
          echo "          2. git update-ref refs/heads/<branch> <good-sha> <bad-sha>   # compare-and-swap" >&2
          echo "          3. restore the checkout, then remove the fixture's files" >&2
          echo "        A suite whose fixture cd fails, or whose git -C operand is empty, runs git in" >&2
          echo "        the caller CWD (#7553/#7652)." >&2
        fi
      fi

      if [[ -n "$_repo_report" ]]; then
        echo "" >&2
        echo "[REPORT] A SHARED store changed in a way a sibling worktree routinely produces." >&2
        echo "         The per-line details below say which store and which member. This class" >&2
        echo "         increments nothing and changes no exit code; it is printed, and counted in" >&2
        echo "         the breakdown, so it is not mistaken for silence." >&2
        printf '%s\n' "$_repo_report" | while IFS=$'\t' read -r _sev _dim _detail; do
          echo "           [$_dim] $_detail" >&2
        done
        _repo_observations=$(printf '%s\n' "$_repo_report" | grep -c '^REPORT' || true)
        # `Last suite started` is deliberately NOT repeated here. The whole premise of this class
        # is that a suite of THIS run probably was not the cause, so naming one would point the
        # reader at an innocent label — the precise AP-021 shape this boundary exists to refuse.
        #
        # And attribution points at the set this run MEASURED, not at the [contention] preamble.
        # That preamble counts processes running test-all.sh — not sibling worktrees doing ordinary
        # git work, which is the population that produces this class — and the runner refuses with
        # rc=4 when it is non-zero, so at this point in the run it reads 0 on essentially every
        # invocation. A number that is zero exactly when it would matter is not attribution.
        echo "         Attribution: the branches this run measured as checked out elsewhere are" >&2
        echo "         listed below; \`git worktree list\` shows the current set." >&2
        printf '%s\n' "$_repo_state_before" | sed -n 's/^wt\t/           checked out elsewhere: /p' >&2
      fi

      if [[ -n "$_repo_unmeasurable" ]]; then
        echo "" >&2
        echo "[UNMEASURABLE] A dimension was captured at one boundary and not the other, so its" >&2
        echo "               delta is meaningless. This is neither clean nor dirty: the run is" >&2
        echo "               simply not evidence about it. Each line below names its own cause;" >&2
        echo "               the common one is [worktree], where git status refreshes the index" >&2
        echo "               and fails under index.lock contention that parallel worktrees produce." >&2
        printf '%s\n' "$_repo_unmeasurable" | while IFS=$'\t' read -r _sev _dim _detail; do
          echo "               [$_dim] $_detail" >&2
        done
      fi

      # Rendered FROM THE MANIFEST carried inside the snapshot — never from a literal list here.
      # If the lib narrows, this narrows with it, which is what stops a full-width claim from
      # sitting on top of a partial check.
      echo "" >&2
      echo "        INSPECTED (this is the whole of what was measured):" >&2
      repo_boundary_render_inspected "$_repo_state_before" "$_repo_state_after" >&2
      echo "        NOT INSPECTED (a clean boundary is not evidence about these):" >&2
      repo_boundary_render_not_inspected "$_repo_state_before" "$_repo_state_after" >&2
      echo "" >&2
      echo "        SCOPE, stated so it is not over-read: this covers runs of THIS runner only." >&2
      echo "        A suite invoked directly (bash path/to/x.test.sh), lefthook's pre-commit" >&2
      echo "        hook, and every other entry point are NOT inspected here. The per-site" >&2
      echo "        guards inside the suites are the protection; this is defence in depth over" >&2
      echo "        gate runs, and a clean run here is not evidence about those other paths." >&2
    fi
  else
    echo "" >&2
    echo "NOTE: the repo-write boundary could not be re-read; this run is not evidence that" >&2
    echo "      no suite wrote to the repository." >&2
  fi
else
  echo "" >&2
  echo "NOTE: the repo-write boundary was not measured (git could not read HEAD at run start);" >&2
  echo "      this run is not evidence that no suite wrote to the repository." >&2
fi
# Ownership of the verdict passes from the EXIT trap to this block, whatever the outcome above —
# including the degraded arms, which have already said their piece.
_repo_boundary_reported=1

# BREAKDOWN FIRST, TERMINAL MARKER LAST. The ordering is load-bearing, not cosmetic.
# Both lines are `=== ...`-shaped, and the documented lesson from #6750 is to match
# the runner's LAST emitted line and never a per-stage line that merely looks
# summary-shaped. Emitting the breakdown last would make a summary-shaped line that
# is NOT the terminal marker the final one — reintroducing that exact ambiguity in
# the one scenario (a killed run) where identifying completion correctly matters
# most. Ordering it first keeps both contracts at zero cost: byte-identical clean
# output, and `=== N/M suites passed ===` stays the last `===` line on every arm.
#
# ADR-181 adds `skipped` to the same breakdown rather than appending it to the marker.
# An earlier revision of this change DID append `(F failed, S skipped)` to the marker, which
# orphaned every anchored poll of it; the separate-line shape #7424 established keeps the marker
# byte-identical, so no reader is orphaned at all. Declines are counted in `suites` and excluded
# from the numerator: with skips in the denominator but not in `failed`, the numerator would
# report a gated suite as PASSED — a green that is not evidence, produced by the very change
# that added the gate.
if (( killed > 0 || skipped > 0 || _ceiling_declined > 0 || _affected_declined > 0 || ${_repo_observations:-0} > 0 || ${_repo_unmeasured_dims:-0} > 0 )); then
  # `_repo_observations` is APPENDED, never interleaved: every existing field keeps its position
  # so anchored readers of this line stay valid. Shown only when non-zero — a field that is 0 on
  # essentially every run carries no information, whereas `skipped` is routinely non-zero.
  _repo_obs_field=""
  if [[ "${_repo_observations:-0}" -gt 0 ]]; then
    _repo_obs_field=", ${_repo_observations} repo observation(s) (REPORT — not a verdict, exit code unchanged)"
  fi
  if [[ "${_repo_unmeasured_dims:-0}" -gt 0 ]]; then
    _repo_obs_field="${_repo_obs_field}, ${_repo_unmeasured_dims} boundary dimension(s) NOT MEASURED (this run is not evidence about them)"
  fi
  _ceiling_field=""
  if (( _ceiling_declined > 0 )); then
    _ceiling_field=", ${_ceiling_declined} declined (runtime ceiling — coverage not obtained)"
  fi
  _aff_field=""
  if (( _affected_declined > 0 )); then
    # #8322: a different axis with a different lever (--full, not FORCE_ALL) and
    # a different claim (the diff does not reach them). Since the merge both
    # decline paths fold into `skipped` for the numerator — the ADR-181 rule
    # this line already applies three ways — while this counter keeps the
    # per-axis tally the field and the lever read.
    _aff_field=", ${_affected_declined} not-affected (selection — diff does not reach them)"
  fi
  echo "=== $suites suites: $((suites - failed - killed - skipped - _ceiling_declined)) passed, $failed failed, $killed killed (unresolved — coverage not obtained), $skipped skipped (declined — not relevant to this diff)${_ceiling_field}${_aff_field}${_repo_obs_field} ==="
fi
# THE LEVER, PRINTED ONCE, ONLY WHEN IT CAN ACTUALLY HELP. SOLEUR_TEST_FORCE_ALL appeared exactly
# once in this runner -- inside _diff_touches's early return -- and was printed nowhere, while the
# infra runner advertises its own lever in two places. A decline is only safe while it stays
# actionable, so the recovery path belongs beside the count of declines.
#
# GATED ON RELEVANCE DECLINES, NOT ON `skipped`, and the wording says "relevance-gated" rather than
# "everything". Both were defects review caught, and they compound: `skipped` also counts the infra
# runner's incident/not_in_diff declines, which _diff_touches never sees, so the earlier form (a)
# claimed to recover a suite it cannot, and (b) still fired after the operator obeyed it -- printing
# the same advice verbatim on the next run, which is advice that does not terminate. Worst case was
# SOLEUR_INCIDENT_SKIP=1 on an incident path: the only decline is one the operator set deliberately,
# answered with an unrelated lever. The infra runner keeps advertising its own.
if (( _relevance_declined > 0 )); then
  echo "      To run every relevance-gated suite regardless of the diff:"
  echo "        SOLEUR_TEST_FORCE_ALL=1 bash scripts/test-all.sh"
fi
if (( _affected_declined > 0 )); then
  # #8322 lever, printed beside the decline count it recovers. `--full` is the
  # one spelling that survives a future rename of the selection axis; the
  # not-affected declines above are exactly what it re-includes.
  echo "      To run the suites this diff did not reach:"
  echo "        bash scripts/test-all.sh --full"
fi
# An affected run's declines are scope verdicts, and the same honesty rule applies one
# level up: the RUN itself must not read as the battery it replaced. The denominator
# already carries them; this line names the mode so a reader (or a poll grepping the
# terminal marker) can tell scoped evidence from the ship gate without counting skips.
if [[ "$TEST_GROUP" == "affected" ]]; then
  echo "NOTE: TEST_GROUP=affected — ${_affected_declined} suite(s) declined as unreachable from"
  echo "      this diff. This is scoped evidence, not the full battery; ship still requires"
  echo "      TEST_GROUP=all. To run everything: bash scripts/test-all.sh"
fi
echo "=== $((suites - failed - killed - skipped - _ceiling_declined))/$suites suites passed ==="

# Restatement of the PREAMBLE notice (#6730/#7014, re-pointed by #7103). Since the infra
# runner is now a REGISTERED nested suite, the thing worth restating inverted: it is no
# longer "the summary excludes infra" but "the summary includes it — unless it was skipped,
# in which case say so HERE too". A reader who `tail`s the log (the documented log-reading
# shape) must not have to infer which of those happened.
#
# Keyed on `_infra_ran`, which is set ONLY at the run_suite call site — an OBSERVED fact, not
# a predicted one. It previously keyed on `_infra_in_diff`, so the "IS covered above" line
# printed in the three CI shards where want_infra is false and the runner never executed, and
# the SOLEUR_INCIDENT_SKIP line attributed to the incident bypass any skip that happened for a
# different reason entirely (wrong TEST_GROUP, or a docs-only diff with the var incidentally
# set).
#
# Bare `$_infra_ran`, deliberately NOT `${_infra_ran:-0}`. The variable is set unconditionally
# at top level, so the default could only mask a future edit that removed that initialisation —
# and it would mask it by silently dropping every notice. Under `set -u` the bare form makes
# that edit fail loudly instead.
if [[ "$_infra_ran" == 1 ]]; then
  echo ""
  echo "NOTE (announced in the preamble): apps/web-platform/infra/ IS covered above, via the"
  echo "      nested apps/web-platform/infra/run-registered-suites.sh suite."
elif [[ "$_infra_skip_reason" == "incident" ]]; then
  echo ""
  echo "NOTE: apps/web-platform/infra/ was SKIPPED (SOLEUR_INCIDENT_SKIP=1)."
  echo "      Nothing above is evidence for it. Run the CI-registered suites:"
  echo "        bash apps/web-platform/infra/run-registered-suites.sh"
elif [[ "$_infra_skip_reason" == "group" && "$_infra_in_diff" == 1 ]]; then
  echo ""
  echo "NOTE: apps/web-platform/infra/ is NOT covered above — TEST_GROUP=$TEST_GROUP excludes"
  echo "      the infra runner, and your diff touches that directory. Run:"
  echo "        bash apps/web-platform/infra/run-registered-suites.sh"
elif [[ "$_infra_skip_reason" == "not_in_diff" ]]; then
  echo ""
  echo "NOTE: apps/web-platform/infra/ is NOT covered above (diff does not touch it)."
fi

if (( _ceiling_declined > 0 )); then
  echo ""
  echo "NOTE: this run crossed TC_RUNTIME_CEILING_S (${TC_RUNTIME_CEILING_S:-unset}s) and stopped"
  echo "      starting suites: declined_suites=${_ceiling_declined}. Nothing above is evidence"
  echo "      for them. This run exits 3 — UNRESOLVED, not green and not a failure."
fi

if [[ "$failed" -gt 0 ]]; then
  exit 1
elif (( killed > 0 )); then
  exit 3
elif (( _ceiling_declined > 0 )); then
  # A curtailed run must NOT be able to exit 0. Declined suites are otherwise an
  # ordinary green state on this runner (a relevance decline exits 0), so
  # without this arm a run that stopped part-way would reach the summary with
  # zero failures and certify a battery it never ran.
  exit 3
fi
