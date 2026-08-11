#!/usr/bin/env bash
# Run every infra suite REGISTERED IN CI, locally and in parallel.
#
# READING THE OUTPUT: a failing suite prints `RED <path>`, not `FAIL`. A `grep FAIL` over this
# runner's log returns zero hits on a failing run and reads as clean — measured 2026-08-04 (#7220),
# where the summary said "1 failed" and the greps for FAIL came back empty. Match `^RED ` (or just
# read the trailing `N passed, M failed` line).
#
# WHY THIS EXISTS (#6730). These suites are registered as `run: bash …` steps in
# `.github/workflows/infra-validation.yml` — during #6730 a required check was RED
# behind a 223/223 green test-all, and the red was found by reading CI, not by
# testing locally. There was no local command that ran them; now there is.
#
# COVERAGE STATUS, CORRECTED (#7103 R5(a)). This header said "`scripts/test-all.sh`
# does not cover `apps/web-platform/infra/`" and that is no longer true: test-all.sh
# now invokes THIS FILE as a nested `run_suite`. The claim survived the change that
# falsified it because the sweep was indexed by file and never opened the file it
# had just started calling — the registered runner denying its own registration.
#
# What is true now, and the distinction matters: test-all.sh runs this runner only
# when `want_infra` holds (TEST_GROUP is `all` or `infra`) AND the diff touches this
# directory. CI's three shards (`webplat`, `bun`, `scripts`) satisfy neither, so a
# green run in those says nothing about infra — and test-all.sh now says so in its
# epilogue rather than claiming coverage it does not have. Read the log: it reports
# which of those happened, keyed on whether this runner actually ran.
#
# The suite list is DERIVED from infra-validation.yml rather than globbed off the
# directory, so this runner and CI cannot drift: a suite added to the workflow is
# picked up here automatically, and a suite that exists on disk but was never
# registered is reported as unregistered rather than silently counted as covered.
#
# Serial execution is not viable — 70 suites take well over ten minutes end to
# end. Parallelism is the difference between a gate people run and one they skip.
#
# TOOLING DEPENDENCY, recorded here because this is the auto-glob site (#7068).
# TWO registered suites need a real docker daemon:
#   - cloud-init-plugin-seed.test.sh    builds a small busybox fixture image (~2-4s in CI)
#   - git-data-runcmd-rehearsal.test.sh three `docker run --rm` invocations (~48-61s in CI,
#                                       the most expensive step in deploy-script-tests)
#
# Both self-skip with exit 0 when docker is missing or unreachable. The skip is NOT visible
# through this runner: the executor below captures each suite's output to a per-run log dir and
# prints `PASS`, so a docker-less laptop reports PASS for both while neither asserts anything
# — ~50-65s of coverage, silently absent. (An earlier version of this paragraph called it a
# "visible SKIP", which was false in the one file where it mattered most.)
#
# DIAGNOSTICS ON RED (#7376). Until 2026-08-10 the executor was
# `bash "{}" >/dev/null 2>&1` and printed only `PASS`/`RED`, so a CI failure carried no
# diagnostic output whatsoever — characterising the parallel flake took eight executions, and
# issue #7374 (filed by the health monitor) is 21 `PASS` lines and a count, naming no suite.
# Each suite's stdout+stderr now goes to its own file under a per-run log dir; on RED the
# parent prints a bounded excerpt ANCHORED ON THE SUITE'S OWN FAILURE MARKER — not a blind
# tail, because these suites do not stop at the first failed assertion (a failure at arm 5 of
# web-host-provisioner-parity-mutation's 43 is hundreds of lines from EOF, so a `tail` shows
# only trailing passes and destroys the one datum worth having).
#
# That is deliberate for local DX, and it is why CI does NOT rely on the skip:
# infra-validation.yml has a separate `docker info` assertion step that reds the job when the
# daemon is absent, rather than letting either suite pass vacuously. That step must stay
# ORDERED BEFORE both suites — today it precedes plugin-seed, and git-data-runcmd-rehearsal
# is later in the same job, so both are covered. That ordering is the invariant; it is not
# self-evident from either step. If you are debugging why a docker-dependent regression
# reproduced in CI but not locally, this is the reason.
#
# Docker is not the only external dependency, and an earlier version of this paragraph
# claimed it was ("every other registered suite needs only what a stock checkout has").
# Measured across the 86 derived suites (2026-07-30), by their own `command -v` preconditions:
#
#   docker      2   cloud-init-plugin-seed, git-data-runcmd-rehearsal
#   terraform   5   cloud-init-inngest-bootstrap, git-data-emit,
#                   git-data-render-strip-parity, git-data-runcmd-rehearsal, inngest
#   python3     5   canary-bundle-claim-check, git-data-emit,
#                   git-data-render-strip-parity, git-data-runcmd-rehearsal,
#                   workspaces-luks-g4-mutation
#   cloud-init  1   cloud-init-inngest-bootstrap
#   jq          3
#
# Every one of those self-skips with exit 0 when its tool is absent, and — per the paragraph
# above — this runner prints PASS for a skip. So on a bare checkout a green run here can be
# hiding a substantial share of the suite set. Re-derive this table rather than trusting it:
#   while read -r f; do grep -oE 'command -v [a-z0-9-]+' "$f"; done \
#     < <(bash apps/web-platform/infra/run-registered-suites.sh --list \
#         | sed -n 's|^  \(apps/.*\.test\.sh\)$|\1|p') | sort | uniq -c | sort -rn
#
# No derived suite invokes sudo (measured: 0) — see the derive-but-do-not-execute discussion
# in #7076 for why that matters.
#
# Usage:
#   bash apps/web-platform/infra/run-registered-suites.sh          # all suites
#   JOBS=12 bash apps/web-platform/infra/run-registered-suites.sh  # override width
#   bash apps/web-platform/infra/run-registered-suites.sh --list   # derive only, run nothing
#
# `--list` prints the derived suite list and the orphan report without executing
# anything. It exists so this script's own logic (derivation, the zero-guard, the
# orphan scan) is testable in under a second — a runner whose correctness could
# only be checked by a 25-minute full run would not, in practice, be checked.
# INFRA_WF overrides the workflow path for the same reason (fixtures).
#
# Exit 0 only when every registered suite passes.

set -uo pipefail

# Default TMPDIR to /var/tmp (disk-backed), mirroring scripts/test-all.sh.
#
# These suites are the heaviest bulk writers in the repo: several copy the whole
# 162 MB `.terraform` provider tree PER MUTATION, and `credential-persist-home-guard`
# alone makes ~13 such copies. Against the ~4 GiB /tmp tmpfs that exhausts the mount
# and the suite dies on `cp: No space left on device` — a RED that looks like a real
# regression and is really a full RAM disk. It reproduces with the runner completely
# idle, so it is capacity, not contention.
#
# test-all.sh already defaults this, but it points here — the ONE runner it structurally
# cannot cover — and that pointer used to land on a command still requiring a manual
# `TMPDIR=/var/tmp` prefix. Defaulting it there and not here left the footgun exactly
# where the hand-off sends you; #6977 removed it in both halves. (#7014 moved that
# pointer to test-all.sh's PREAMBLE, so it now arrives before the run is paid for; a
# one-line restatement stays in the epilogue for `tail` readers.)
#
# Respects an explicit caller value — CI or an operator pinning TMPDIR keeps it.
export TMPDIR="${TMPDIR:-/var/tmp}"

LIST_ONLY=0
[[ "${1:-}" == "--list" ]] && LIST_ONLY=1

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT" || exit 1

WF="${INFRA_WF:-.github/workflows/infra-validation.yml}"
[[ -f "$WF" ]] || { echo "FATAL: $WF not found — cannot derive the registered suite list." >&2; exit 2; }

# SOLEUR_INFRA_DIR is a TEST SEAM, sibling to INFRA_WF. Namespaced because a bare
# INFRA_DIR is already a workflow-level `env:` in apply-sentry-infra.yml and
# apply-deploy-pipeline-fix.yml — an unrelated job's env must not reach a test seam. The derivation regex below used to hardcode
# the `apps/web-platform/infra/` prefix, which meant a fixture suite could only be registered
# by physically creating an executable file IN THE LIVE INFRA DIRECTORY — while every sibling
# suite is reading that directory. That is precisely the collision #7376 is about, so the
# tests for this file could not be written without reproducing the bug they guard.
SOLEUR_INFRA_DIR="${SOLEUR_INFRA_DIR:-apps/web-platform/infra}"
# Escape it for the ERE below: a fixture root from `mktemp -d` carries `.` characters, which
# an unescaped interpolation would turn into "any character".
_DIR_ERE="$(printf '%s' "$SOLEUR_INFRA_DIR" | sed 's/[][\.^$*+?(){}|\\/]/\\&/g')"

mapfile -t SUITES < <(
  grep -oE "run: bash ${_DIR_ERE}/[A-Za-z0-9._-]+\.test\.sh" "$WF" \
    | sed 's/run: bash //' | sort -u
)

# A silent zero here would print "0 failed" and read as success — the exact
# false-green this runner exists to end.
(( ${#SUITES[@]} > 0 )) || {
  echo "FATAL: derived ZERO suites from $WF. The 'run: bash …' step shape changed;" >&2
  echo "       fix the extraction rather than trusting this run." >&2
  exit 2
}

# Report suites present on disk that NO workflow or script references. A test that
# nothing runs is not coverage, and it fails silently forever — the same
# false-assurance class as the test-all blind spot above, one level down.
#
# Advisory HERE, but no longer advisory ANYWHERE (#7068): every suite this block can print
# is a hard failure of .github/scripts/test/test-infra-suite-registration.sh, which runs in
# `guard-script-fixture-tests` — a REQUIRED, merge_group-triggered, path-filter-free check.
# The chain is exact: a suite is printed here only when its basename appears in no workflow,
# so no `run: bash <path>` step exists, so that gate's single-line check AND its any-shape
# fallback both fail. The gate's EXCLUSIONS escape does not rescue it either, because the
# exclusion arm independently requires an invocation to exist.
#
# So do not read a NOTE below as optional. This runner still declines to FAIL on it — its job
# is to run what CI runs, not to police the rest — but the merge will be blocked. Said
# explicitly because the previous wording ("Advisory, not a failure") was written before that
# gate existed and would now tell you registration is optional, which is the opposite of true.
#
# INFRA_ORPHAN_LIST is a TEST SEAM (#7376) that injects the CANDIDATE list only. The
# cross-reference below — one `git grep` per basename across workflows/ and scripts/, which is
# the logic worth testing — still runs for real. It exists because `git ls-files` is
# index-bound, so the only way to hand this function a candidate it will report was to create
# a file in the LIVE infra directory and `git add -N` it, mid-run, while every sibling suite
# read that same directory. See the T5 comment in run-registered-suites.test.sh.
report_orphans() {
  local -a orphans
  mapfile -t orphans < <(
    while IFS= read -r f; do
      [[ -n "$f" ]] || continue
      git grep -qF -- "$(basename "$f")" -- .github/workflows/ scripts/ || printf '%s\n' "$f"
    done < <(
      if [[ -n "${INFRA_ORPHAN_LIST:-}" ]]; then
        sort -u "$INFRA_ORPHAN_LIST"
      elif [[ "$SOLEUR_INFRA_DIR" == /* ]]; then
        # A fixture root (absolute, from `mktemp -d`) is outside the repo, so `git ls-files`
        # exits fatal on it. Emit no candidates rather than leaking that error into the run log,
        # where it reads as a real problem with the orphan scan — but SAY SO. A bare `:` here
        # made "scan skipped" byte-indistinguishable from "no orphans found", which is the
        # silent-degradation shape this same file goes out of its way to reject elsewhere.
        echo "NOTE: orphan scan skipped — SOLEUR_INFRA_DIR is outside the repo working tree." >&2
      else
        git ls-files "${SOLEUR_INFRA_DIR}/**/*.test.sh" "${SOLEUR_INFRA_DIR}/*.test.sh" | sort -u
      fi
    )
  )
  (( ${#orphans[@]} > 0 )) || return 0
  echo ""
  echo "NOTE: ${#orphans[@]} suite(s) on disk are referenced by NO workflow or script —"
  echo "      nothing runs them, in CI or here:"
  printf '  %s\n' "${orphans[@]}"
}

if (( LIST_ONLY )); then
  echo "Derived ${#SUITES[@]} registered infra suite(s) from ${WF}:"
  printf '  %s\n' "${SUITES[@]}"
  report_orphans
  exit 0
fi

# min(nproc, 6) — capped because several suites shell out to terraform/docker and
# oversubscribing turns a slow run into a flaky one.
_NPROC=$(nproc 2>/dev/null || echo 4)
JOBS="${JOBS:-$(( _NPROC < 6 ? _NPROC : 6 ))}"

# ── The instrument (#7376) ────────────────────────────────────────────────────
#
# SENTINEL. Every DIAGNOSTIC line the parent emits after xargs is prefixed with `SOLEUR| `.
#
# Three things after xargs are deliberately NOT prefixed, and the distinction is load-bearing:
# the summary count line (the monitor's `tail -30` must end on it — T6v pins this), the orphan
# report, and the `UNACCOUNTED  <path>` verdict lines (naming signal, see below). An earlier
# wording claimed EVERY line was prefixed, which is both false and the wrong inference to hand
# a future maintainer — it invites "completing" the rule by prefixing the summary, which would
# break the monitor. That is not cosmetic. 10 registered suites print `[FAIL]` at column 0, and main-health-monitor.yml
# greps `^RED |^\[FAIL\]` to build a PUBLIC issue body AND to derive its TITLE — so an
# unprefixed dumped `[FAIL]` during a TIMEOUT would title an issue with a cause the job never
# measured, the exact AP-021/ADR-166 defect #7371 removed. The prefix also gives the monitor a
# filter for its UNCONDITIONAL `tail -30` (it sits outside the `if [[ -n "$hits" ]]` block), so
# the published excerpt stays byte-identical to today's.
#
# WHY `SOLEUR| ` AND NOT A BARE `| `. The monitor's excerpt loop covers TWO captures, and both
# can carry this runner's output: the infra step invokes it directly, and the tests step runs
# scripts/test-all.sh, which invokes it as a NESTED suite (that is why JOBS: 1 is pinned on
# both steps, not one). So filtering only the infra capture would still leak dumped bytes
# through the tests half. But a blanket `^| ` filter on the tests capture is also wrong:
# scripts/expenses-verify-by-check.test.sh prints markdown tables at column 0
# (`| Service | Provider | …`), and stripping those deletes an existing signal from the public
# excerpt. A sentinel no shell output produces resolves both at once — verified zero
# occurrences repo-wide, and zero of the 93 registered suites emit it (pinned by T8b).
SENTINEL_PREFIX='SOLEUR| '

# MARKER_ERE — DERIVED FROM THE CORPUS, NEVER INTUITED, and pinned by T8a/T8c.
# Measured 2026-08-10 over all 93 registered suites (payload-start extraction, following
# `source`d helpers and embedded python):
#     ^\[FAIL\]                                    11/93
#     this ERE                                     93/93
# Re-derive rather than trusting those figures — they move with the extractor, and an earlier
# draft carried three that did not reproduce. The 11 includes web-host-provisioner-parity, whose
# marker is `print(f"[FAIL] …")` inside an embedded python heredoc: a shell-only scan reports 10
# and silently disagrees with the methodology stated one line above it.
# The shapes are `[FAIL] x`, `FAIL: x`, `FAIL - x`, `  FAIL x`, and `SETUP-FAIL: x`, emitted
# from five places: double-quoted echo/printf, SINGLE-quoted printf, an embedded python heredoc,
# a sourced helper, and a `SETUP-FAIL:` prefix. An earlier draft also carried `^no `, which
# matches NOTHING — it was taken from the `no()` helper's NAME rather than its output
# (`printf 'FAIL - %s\n'`).
MARKER_ERE='^[[:space:]]*(\[FAIL\]|[A-Z][A-Z0-9]*-FAIL|FAIL)([[:space:]:_-]|$)'

# Cap per RED suite. Binds AFTER selection — capping first would reinstate the blind tail this
# whole mechanism exists to avoid.
DUMP_CAP=40

# Seconds precision is sufficient: the discriminator it serves compares a suite against its
# solo baseline (2s vs 89s across the corpus), not against itself.
#
# EPOCHSECONDS, not EPOCHREALTIME: it is an integer, so it sidesteps the decimal-separator
# locale trap entirely. And NO bash-3 fallback — scripts/test-all.sh has one whose behaviour is
# to resolve elapsed to 0 SILENTLY, which would plant a silent-wrong-value in the only field
# that can answer "did this suite run far longer than its solo baseline?". This runner already
# requires bash 4+ (mapfile, above), so fail loud instead.
[[ -n "${EPOCHSECONDS:-}" ]] || {
  echo "FATAL: bash 5.0+ required (EPOCHSECONDS is unset) — refusing to record timings as 0." >&2
  exit 2
}

LOG="$(mktemp)" || { echo "FATAL: mktemp failed for the summary log (TMPDIR=$TMPDIR)" >&2; exit 2; }

# Age-reap older siblings before creating this run's dir. Retention-on-RED is deliberate, but
# nothing else reclaims these: ADR-133's tmpfs reaper scopes to /tmp while this runner exports
# TMPDIR=/var/tmp, and that ADR explicitly REJECTED count-based reaping — so this class is
# unreapable by construction unless the producer cleans up after itself. It accumulates fast
# because run-registered-suites.test.sh is itself a registered suite and drives this runner
# ~10x per invocation with deliberate REDs (measured: 414 dirs / 23 MB on the author's box
# before this reaper existed). Mirrors ADR-133's own `meta_dir` precedent.
find "${TMPDIR}" -maxdepth 1 -name 'infra-suites.*' -type d -mmin +720 \
  -exec rm -rf {} + 2>/dev/null || true

# Initialise BEFORE the trap references it: `set -u` is active, so an unset var inside the
# trap would abort the trap itself. The trap reaps the log dir too — the inline reap below
# only covers a clean green exit, so a timeout, Ctrl-C or OOM would otherwise leak it even on
# an otherwise-healthy run. SOLEUR_KEEP_LOGDIR is set on the retain path so a genuine failure
# keeps its evidence.
SOLEUR_SUITE_LOGDIR=""
SOLEUR_KEEP_LOGDIR=""
trap 'rm -f "${LOG:-}"; [[ -n "${SOLEUR_KEEP_LOGDIR:-}" ]] || rm -rf "${SOLEUR_SUITE_LOGDIR:-/nonexistent}"' EXIT
SOLEUR_SUITE_LOGDIR="$(mktemp -d -t infra-suites.XXXXXXXX)" || {
  echo "FATAL: mktemp -d failed for the per-suite log dir (TMPDIR=$TMPDIR)." >&2
  echo "       Refusing to run: every suite's capture would fail and the accounting" >&2
  echo "       assertion would then blame a vanished wrapper for a disk problem." >&2
  exit 2
}
export SOLEUR_SUITE_LOGDIR
SOLEUR_RUN_T0="$EPOCHSECONDS"; export SOLEUR_RUN_T0

echo "Running ${#SUITES[@]} registered infra suite(s) with -P ${JOBS}…"

# The child still emits `PASS <path>` / `RED  <path>` FIRST and in the same byte shape — every
# downstream consumer anchors on it.
#
# THE INVARIANT HAS TWO CLAUSES AND BOTH ARE LOAD-BEARING: (i) the summary line stays under
# PIPE_BUF (4096), and (ii) THE CHILDREN'S STDOUT REMAINS A PIPE. PIPE_BUF atomicity is a
# property of pipes and does not apply to regular files at all — "tidying" `| tee "$LOG"` into
# `> "$LOG"` while adding the per-suite file capture below is a natural-looking refactor that
# gives all four children one shared open file description, block-buffered flushes landing
# mid-line, and torn PASS/RED lines. scripts/generate-kb-index.sh shipped exactly that defect,
# in this repo, the same day this change was written, and fabricated ~14 corrupted values into
# a committed artifact that a validation gate then enforced. See
# knowledge-base/project/learnings/2026-08-10-pipe-buf-atomicity-does-not-apply-to-the-file-i-was-redirecting-into.md
#
# Capture order is `>"$f" 2>&1`, NEVER `2>&1 >"$f"`. Most suites write their failure marker to
# stderr — `for f in $(…--list…); do grep -cE '(echo|printf).*(FAIL|fail).*>&2' "$f"; done`
# sums to ~107 sites today (the exact figure moves with the predicate, which is why the command
# is here rather than a bare number). The inverted form sends stderr to the OLD stdout, loses
# every marker, and leaves the selector below finding nothing while looking perfectly healthy.
#
# The suite path is passed as `$1`, not interpolated into the script text. `xargs -I{}` does a
# textual substitution, so `s="{}"` would make a path containing `"`/`$`/backtick executable as
# code. The derivation regex constrains the basename today, but `$SOLEUR_INFRA_DIR` is caller-
# supplied, and this script body grew from one line to five.
printf '%s\n' "${SUITES[@]}" \
  | xargs -P "$JOBS" -I{} bash -c '
      s="$1"; key="${s//\//_}"
      st="$EPOCHSECONDS"
      bash "$s" >"$SOLEUR_SUITE_LOGDIR/$key.log" 2>&1; rc=$?
      printf "%s %s %s\n" "$rc" "$(( EPOCHSECONDS - st ))" "$(( st - SOLEUR_RUN_T0 ))" > "$SOLEUR_SUITE_LOGDIR/$key.meta"
      if (( rc == 0 )); then echo "PASS $s"; else echo "RED  $s"; fi
    ' _ {} \
  | tee "$LOG"

# `^RED ` / `^PASS ` WITH the trailing space, matching every downstream consumer. Nothing else
# reaches $LOG — it is fed only by the child summary lines above — but the two anchors used to
# disagree, and a log line that merely began "RED" would have been counted.
RED=$(grep -c '^RED ' "$LOG" || true)
PASS=$(grep -c '^PASS ' "$LOG" || true)

# ── Dump, from the PARENT, single-threaded, strictly after xargs and strictly before the
# final summary block (so the monitor's `tail -30` still ends on the count).
# Never from inside a child: multi-line concurrent writes are not atomic.
dump_reds() {
  local s key f m rc el off sel
  # Sorted, not completion order — a nondeterministic dump order makes two runs of the same
  # failure set incomparable, which is the whole problem this change exists to fix.
  while IFS= read -r s; do
    [[ -n "$s" ]] || continue
    key="${s//\//_}"; f="$SOLEUR_SUITE_LOGDIR/$key.log"; m="$SOLEUR_SUITE_LOGDIR/$key.meta"
    rc="?"; el="?"; off="?"
    [[ -s "$m" ]] && read -r rc el off < "$m"
    echo ""
    echo "--- RED: $s (rc=${rc} elapsed=${el}s start_offset=+${off}s) ---"
    dump_one "$f"
  done < <(grep '^RED ' "$LOG" | sed 's/^RED  *//' | LC_ALL=C sort)
}

# Excerpt one captured log. `grep`'s rc is inspected rather than swallowed: rc 2 is an ERROR
# (unreadable file, bad regex), and collapsing it into rc 1 would print the
# "no line matched the failure-marker ERE" label — naming a cause the run did not measure.
#
# The cap is a LINE cap; `cut` adds the byte bound it does not give. One 200 KB line passes
# `head -n 40` and `tail -30` intact, and GitHub's issue-body limit is 65,536 characters — so
# without this a single long line makes `gh issue create` fail and the monitor files NOTHING,
# silently losing its only job. `--no-group-separator` keeps grep's `--` markers out of the dump.
dump_one() {
  local f="$1" sel grc _capped
  # "no capture file" and "capture file is empty" are DIFFERENT facts and must not share a
  # message. Observed 2026-08-11: the log dir was removed mid-run (an operator editing this
  # script while a run held it open), and all 12 REDs reported "the suite produced no output at
  # all" — a cause the runner had not measured, on a run where the suites had in fact produced
  # plenty. Same AP-021 class the accounting block below is careful about.
  if [[ ! -e "$f" ]]; then
    echo "[selection: unavailable — no capture at ${f} (log dir removed mid-run, or the child never started)]"
    return 0
  fi
  if [[ ! -s "$f" ]]; then
    echo "[selection: none — the capture exists and is empty; the suite printed nothing]"
    return 0
  fi
  sel="$(grep -E -A3 --no-group-separator "$MARKER_ERE" "$f" 2>/dev/null)"; grc=$?
  case "$grc" in
    0) echo "[selection: marker-anchored]"
       # `mapfile -n`, NOT `printf … | head -n`. The pipe form makes the producer write the
       # whole selection into a consumer that exits after N lines, so `printf` takes SIGPIPE —
       # and since the dump block is now `2>&1`-captured, any shell that reports that write
       # error turns it into an extra prefixed line. Measured: 46 lines locally, 47 in CI, on a
       # cap the test derives from DUMP_CAP. `mapfile -n` reads at most N lines and never
       # writes past the cap, which also fixes the O(N) materialisation review flagged.
       local _capped=()
       mapfile -t -n "$DUMP_CAP" _capped <<<"$sel"
       printf '%s\n' "${_capped[@]}" | cut -c1-2000 ;;
    1) echo "[selection: fallback tail — no line matched the failure-marker ERE]"
       tail -n "$DUMP_CAP" "$f" 2>/dev/null | cut -c1-2000 ;;
    *) echo "[selection: unavailable — grep exited ${grc} reading the capture]" ;;
  esac
}

# ── Accounting. A child whose wrapping `bash -c` is KILLED (the OOM killer under -P 4) emits
# NEITHER `PASS` nor `RED`. Before this assertion existed RED was then 0, the runner exited 0,
# and the summary printed e.g. "91 passed, 0 failed (of 93)" — two numbers visibly disagreeing
# with nothing asserting they must match. A suite could vanish and the gate went green. That is
# a pre-existing false green, and it is the failure mode most likely to have masked evidence
# for the capacity hypothesis all along.
# `comm`, not 93 greps: it needs no per-path regex escaping (the escape idiom already exists
# once, for the derivation ERE, and a second copy is a second thing to get wrong).
UNACCOUNTED=()
if (( PASS + RED != ${#SUITES[@]} )); then
  mapfile -t UNACCOUNTED < <(
    comm -13 \
      <(sed -nE 's/^(PASS|RED) +//p' "$LOG" | LC_ALL=C sort -u) \
      <(printf '%s\n' "${SUITES[@]}" | LC_ALL=C sort -u)
  )
fi

# NAMING SIGNAL, DELIBERATELY UNPREFIXED — this is a VERDICT, not a diagnostic.
#
# The distinction is the whole reason the sentinel exists, and getting it wrong is how the
# first draft of this change broke: `ACCOUNTING FAILURE` was emitted inside the prefixed block,
# so the monitor's `grep -v '^SOLEUR| '` stripped it from the PUBLIC issue body. And because an
# unaccounted suite emits no `^RED ` line either, `HAS_FAIL_MARKER` stayed 0 and the monitor
# titled the issue "health check did not complete … usually a step or job timeout" — a cause the
# job never measured, on the exact failure mode this assertion was added to catch. That is the
# AP-021/ADR-166 defect #7371 exists to remove, re-armed by its own fix.
#
# So: suite NAMES go out unprefixed, in an anchor shape the monitor greps (mirroring `RED  `).
# The explanatory prose stays prefixed, below.
emit_unaccounted_names() {
  printf 'UNACCOUNTED  %s\n' "${UNACCOUNTED[@]}"
}

{
  dump_reds
  if (( ${#UNACCOUNTED[@]} > 0 )); then
    echo ""
    echo "ACCOUNTING FAILURE: ${#SUITES[@]} suites were dispatched but only $((PASS + RED)) reported."
    echo "The suite(s) named UNACCOUNTED above emitted neither PASS nor RED — their wrapping"
    echo "shell died (OOM kill, timeout, or a crash) before it could report."
    echo "Treat this as a FAILED run: those suites are unmeasured, not passing."
    # Their captured output still exists and is the only evidence of what they were doing when
    # they died — the failure mode most likely to have masked capacity evidence all along.
    for _s in "${UNACCOUNTED[@]}"; do
      echo ""
      echo "--- UNACCOUNTED: $_s (no rc — the wrapper never reported) ---"
      dump_one "${SOLEUR_SUITE_LOGDIR}/${_s//\//_}.log"
    done
  fi
  if (( RED > 0 || ${#UNACCOUNTED[@]} > 0 )); then
    echo ""
    echo "retained per-suite log dir: ${SOLEUR_SUITE_LOGDIR}"
    echo "(local repro only — a hosted runner is destroyed with its filesystem)"
  fi
# 2>&1 so the parent's OWN stderr is prefixed too. Without it a `tail:`/`read:` diagnostic, or
# bash's "ignored null byte in input" warning, lands at column 0 and rides into the public issue
# body — which would falsify the invariant this whole design rests on.
} 2>&1 | sed "s/^/${SENTINEL_PREFIX}/"

(( ${#UNACCOUNTED[@]} == 0 )) || emit_unaccounted_names

if (( RED == 0 && ${#UNACCOUNTED[@]} == 0 )); then
  rm -rf "$SOLEUR_SUITE_LOGDIR"
else
  SOLEUR_KEEP_LOGDIR=1
fi

report_orphans

echo ""
# The count line carries all THREE numbers. Reporting only passed/failed is what let
# "91 passed, 0 failed (of 93)" read as success while two suites had vanished.
echo "=== registered infra suites: ${PASS} passed, ${RED} failed, ${#UNACCOUNTED[@]} unaccounted (of ${#SUITES[@]}) ==="
(( RED == 0 && ${#UNACCOUNTED[@]} == 0 ))
