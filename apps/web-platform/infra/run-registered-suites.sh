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
# The suite list is DERIVED by filesystem glob over apps/web-platform/infra/
# (ADR-251) rather than scraped off the workflow's `run: bash` steps, so this
# runner and CI cannot drift — literally: presence IS registration, and a suite
# added on disk is picked up here AND by the deploy-script-tests matrix legs
# automatically. (The scrape this replaced could not see subdirectory or
# sudo-invoked suites — the #7076 blind spot.)
#
# Serial execution is not viable — 126 derived suites (as-of measurement
# 2026-09-21, the same vintage as the tooling table below; re-derive rather
# than trusting) take well over ten minutes end to end. Parallelism is the
# difference between a gate people run and one they skip.
#
# TOOLING DEPENDENCY, recorded here because this is the auto-glob site (#7068).
# FIVE registered suites consume docker — two as a whole-suite requirement, three
# for a docker-dependent arm that declines cleanly when the daemon is absent:
#   - cloud-init-plugin-seed.test.sh    builds a small busybox fixture image (~2-4s in CI)
#   - git-data-runcmd-rehearsal.test.sh 8 `docker run --rm` invocations from 6 source sites
#                                       (~48-61s in CI, the most expensive step in
#                                       deploy-script-tests). Was "three" — the same
#                                       hand-maintained quantity that had drifted to "four"
#                                       in the rehearsal itself; corrected together in #7565
#                                       so the two files cannot disagree again.
#   - git-data-cutover-access.test.sh   docker runtime arm (counted decline, rest of the
#                                       suite still runs)
#   - git-data-ownership.test.sh        docker runtime arm (same counted-decline shape)
#   - zot-config-deadlines.test.sh      digest acceptance pair — `docker run` zot verify +
#                                       negative control; the static relations and S4
#                                       battery need no docker
#
# On a non-CI host all five exit 0 when docker is missing or unreachable — the
# first two skip the suite outright; the other three print a SKIP verdict and
# count the declined assertions (`SKIP runtime arm` / `=== Skipped:`). Under CI
# four of the five fail closed on the same absence (the CI arm inside each gate);
# only plugin-seed skips unconditionally, relying on the workflow assert step
# ordered before it below. The skip is NOT visible
# through this runner: the executor below captures each suite's output to a per-run log dir and
# prints `PASS`, so a docker-less laptop reports PASS for all five — for the first two while
# neither asserts anything (~50-65s of coverage, silently absent), and for the three partial
# declines while their docker arms never adjudicate. (An earlier version of this paragraph
# called it a "visible SKIP", which was false in the one file where it mattered most.)
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
# daemon is absent, rather than letting any suite pass vacuously. That step must stay
# ORDERED BEFORE all five consumers — today it precedes plugin-seed, and
# git-data-runcmd-rehearsal, git-data-cutover-access, git-data-ownership, and
# zot-config-deadlines are all later in the same job, so all five are covered. That ordering
# is the invariant; it is not self-evident from either step. If you are debugging why a
# docker-dependent regression reproduced in CI but not locally, this is the reason.
#
# Docker is not the only external dependency, and an earlier version of this paragraph
# claimed it was ("every other registered suite needs only what a stock checkout has").
# Measured across the 126 derived suites (2026-09-21), by their own `command -v`
# preconditions (one count per suite per tool):
#
#   docker      5   cloud-init-plugin-seed, git-data-cutover-access,
#                   git-data-ownership, git-data-runcmd-rehearsal,
#                   zot-config-deadlines (digest arm only — declines, not a whole-suite skip)
#   terraform   9   cloud-init-inngest-bootstrap, generate-apex-rollback-pr, git-data-emit,
#                   git-data-render-strip-parity, git-data-runcmd-rehearsal,
#                   git-data-template-strip, inngest-boot-emitter, inngest,
#                   registry-userdata-budget
#   python3     7   canary-bundle-claim-check, git-data-emit,
#                   git-data-render-strip-parity, git-data-root-key,
#                   git-data-runcmd-rehearsal, git-data-rung2-rehearsal,
#                   workspaces-luks-g4-mutation
#   cloud-init  1   cloud-init-inngest-bootstrap
#   jq          8   canary-bundle-claim-check, ci-deploy,
#                   cosign-trusted-root-staleness, doppler-download-error-channel,
#                   git-data-root-key, inngest, registry-boot-guard, zot-log-shipper
#   curl        2   canary-bundle-claim-check, git-data-runcmd-rehearsal
#
#   (zot-config-deadlines also invokes python3 unconditionally — render/extract/
#    bogus-config synth — so a python3-less host REDs it loudly; the table counts
#    only suites that gate the tool behind `command -v`.)
#
# Most of those self-skip locally when their tool is absent — loud exceptions like
# git-data-rung2-rehearsal and git-data-root-key fail by design — and every CI-gated
# skip fails closed under CI. Per the paragraph above, this runner prints PASS for
# a local skip, so on a bare checkout a green run here can be hiding a substantial
# share of the suite set. The table is the curated precondition set: a raw
# `command -v` sweep also lists in-container and opportunistic uses (dash,
# ssh-keygen, timeout, nft, rsync) that are not host gates in the same sense.
# Re-derive the table rather than trusting it:
#   while read -r f; do grep -oE 'command -v [a-z0-9-]+' "$f"; done \
#     < <(bash apps/web-platform/infra/run-registered-suites.sh --list \
#         | sed -n 's|^  \(apps/.*\.test\.sh\)$|\1|p') | sort | uniq -c | sort -rn
#
# No EXECUTED suite invokes sudo — the three loopback suites that need root are
# derived but skipped by the PRIVILEGED bucket below and run in CI under `sudo
# bash` in deploy-script-tests-fixed (the derive-but-do-not-execute shape #7076
# asked for).
#
# Usage:
#   bash apps/web-platform/infra/run-registered-suites.sh          # all suites
#   JOBS=12 bash apps/web-platform/infra/run-registered-suites.sh  # override width
#   bash apps/web-platform/infra/run-registered-suites.sh --list   # derive only, run nothing
#   bash apps/web-platform/infra/run-registered-suites.sh --enumerate  # machine-readable set
#   SOLEUR_INFRA_SHARD=1/4 bash …/run-registered-suites.sh         # one CI leg's subset
#
# Environment seams (each documented at its use site):
#   SOLEUR_INFRA_DIR        suite-root override (test fixtures; default
#                           apps/web-platform/infra — in-repo = git ls-files,
#                           outside = find)
#   SOLEUR_INFRA_SHARD      k/N leg selector (malformed/out-of-range = exit 2)
#   SOLEUR_INFRA_MANIFEST   manifest override: `off`, or an absolute path —
#                           invalid forms fail closed
#   SOLEUR_INFRA_TIMINGS    per-suite timing feed path (label<TAB>ms<TAB>verdict;
#                           consumed by regenerate-shard-manifest.py --group infra)
#   SOLEUR_SUITE_TIMEOUT_*  per-suite bound override (test seam)
#   INFRA_ORPHAN_LIST       inject the untracked-scan candidate list (test seam)
#
# `--list` prints the derived suite list and the orphan report without executing
# anything. It exists so this script's own logic (derivation, the zero-guard, the
# orphan scan) is testable in under a second — a runner whose correctness could
# only be checked by a 25-minute full run would not, in practice, be checked.
# `--enumerate` prints `SUITE_REGISTRATION<TAB><path>` rows for the EXECUTE set
# (privileged excluded) — it is shard-insensitive by design: the manifest
# generator consumes the full set for its ⊆ lint.
#
# EXIT CONTRACT — THE SHAPE OF THE NON-ZERO IS LOAD-BEARING (#7429).
#
# Exit 0 only when every registered suite passes. Otherwise:
#
#   failed > 0  OR  UNACCOUNTED > 0   -> 1        an attributed verdict, or a suite that never
#                                                 reported at all (see D3 below)
#   killed > 0                        -> 128+N    the rc of a suite the kernel terminated,
#                                                 propagated VERBATIM
#   otherwise                         -> 0
#
# A suite terminated by a signal used to be flattened into "1" here, so scripts/test-all.sh's
# run_suite saw an ordinary failure and rendered `[FAIL]` — a line that says an assertion broke
# when none did. Propagating the observed 128+N lets run_suite's `suite_exit_class` render
# `[KILLED]` and exits 3 at top level. `failed` DOMINATES `killed`: a run with a real assertion
# failure exits 1 even if something was also terminated, mirroring ADR-177's top-level contract.
#
# OBSERVED RC ONLY. The rc propagated is one this runner READ from a suite's own `.meta` file.
# It is never fabricated: "signal-shaped" is a claim about a number that was observed, and a
# mimicked 137 would make `[KILLED]` a statement the runner cannot support.
#
# DETERMINISTIC MULTI-KILL RULE. With more than one terminated suite, two runs of the same
# failure must report the same number. The rule: the rc of the LEXICOGRAPHICALLY-FIRST KILLED
# SUITE KEY, where the key is the munged path (`${s//\//_}`) the child writes its `.meta` under,
# compared under `LC_ALL=C`. Not the suite PATH — `_` is 0x5F and sorts after `.` and after
# every uppercase letter, so the two orders diverge as soon as subdirectories are involved.
# (The parent walks `"$SOLEUR_SUITE_LOGDIR"/*.meta`; because every entry shares a prefix and a
# `.meta` suffix, sorting those paths under LC_ALL=C is the same order as sorting the keys.)
# The rule is scoped to SUITE kills, where every `.meta` is written and the killed set is
# stable. It does NOT extend to the shim-kill shape below, where the killed set itself varies.
#
# D3 — WHY AN UNACCOUNTED SUITE STILL EXITS 1, DELIBERATELY (#7429, AC9b).
#
# There are two distinct kill positions and only one of them lands in `killed`:
#
#   the SUITE dies      -> the shim survives, writes `.meta` with rc 128+N, prints `RED  <path>`
#                          -> counted in `killed`, rc propagated. xargs sees 0.
#   the SHIM dies       -> NO `.meta` is written and NEITHER `PASS` nor `RED` is printed
#                          -> the suite lands in UNACCOUNTED. xargs exits 125 and STOPS
#                             DISPATCHING, so an arbitrary number of never-started suites join
#                             it. Measured on this box, and it is the likeliest OOM shape:
#                             the shim is the process holding the suite.
#
# The xargs rc IS captured now (it used to be discarded by `| tee "$LOG"`) and it is REPORTED —
# 125 is xargs' documented "a child was killed by a signal", against 123 for "a child exited
# non-zero". So a reader is told a kill occurred rather than left to infer it. But the EXIT
# stays 1, for three reasons, none of which is "nobody thought about it":
#
#   1. The signal is not in this runner's observation channel. `.meta` is the only place a
#      concrete rc is ever read, and the killed shim wrote none. The signal number appears only
#      inside xargs' own localized stderr string ("terminated by signal 15"), and pinning an
#      exit contract to a translated message is worse than pinning it to nothing. Exiting a
#      mimicked 137 would violate the observed-rc-only rule above.
#   2. An unaccounted suite is UNMEASURED, not merely terminated. `[KILLED]`/exit-3 reports
#      "coverage not obtained for a named suite"; here the runner cannot even enumerate which
#      suites ran, because dispatch stopped. The accounting assertion below exists precisely to
#      make that RED, and 1 is the code that says so.
#   3. No reproducible rc exists for this shape anyway — which suites reach UNACCOUNTED varies
#      run to run, so the determinism rule above cannot be honoured here.
#
# If a future change gives the parent a per-suite record written BEFORE the suite runs (a
# dispatch marker, not a post-hoc `.meta`), this becomes decidable and should be revisited.

set -uo pipefail

# Version gate FIRST — the derivation below uses bash-4 features (mapfile,
# declare -A) and the timing code needs bash 5 (EPOCHSECONDS); on bash 3.2 the
# script would die at mapfile with `unbound variable` instead of this message.
[[ -n "${EPOCHSECONDS:-}" ]] || {
  echo "FATAL: bash 5.0+ required (EPOCHSECONDS is unset) — this runner needs a modern bash." >&2
  exit 2
}

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
case "${1:-}" in
  "") ;;
  --list) LIST_ONLY=1 ;;
  # --enumerate is the machine-readable SUITE_REGISTRATION form (handled after
  # derivation below); it must be accepted here or the refusal would fire first.
  --enumerate) ;;
  # Any other argument used to fall through to a FULL battery run (#8705: `--help` started all
  # 137 suites). Refuse instead: the only accepted arguments are --list and --enumerate.
  *) echo "usage: ${0##*/} [--list|--enumerate]" >&2; exit 64 ;;
esac

ROOT="$(git rev-parse --show-toplevel)"

# Session scratch root (#7004): allocate under the effective TMPDIR's base and
# export TMPDIR at it so every suite's mktemp lands inside an owned root a dead
# run can have reclaimed. `_SUITE_TMP_BASE` is the REAL base — under nesting
# inside test-all.sh, TMPDIR is already the parent's session root, so raw
# `$TMPDIR` would make the self-reap below enumerate inside a live root (the
# exact no-op the comment warns about). SOLEUR_SCRATCH_BASE is the parent's
# exported base when nested, unset standalone. `--list` skips begin — an
# enumerate run that exits before the trap installs would leak a marked root.
_SUITE_TMP_BASE="${SOLEUR_SCRATCH_BASE:-$TMPDIR}"
_SCRATCH_LIB="$ROOT/scripts/lib/scratch-root.sh"
if [[ -f "$_SCRATCH_LIB" ]]; then
  # shellcheck source=scripts/lib/scratch-root.sh
  source "$_SCRATCH_LIB" || true
fi
if (( LIST_ONLY == 0 )) && declare -F soleur_scratch_session_begin >/dev/null 2>&1; then
  soleur_scratch_session_begin "$_SUITE_TMP_BASE" || true
fi
declare -F _soleur_scratch_cleanup >/dev/null 2>&1 || _soleur_scratch_cleanup() { :; }
cd "$ROOT" || exit 1

# SOLEUR_INFRA_DIR is a TEST SEAM. Namespaced because a bare
# INFRA_DIR is already a workflow-level `env:` in apply-sentry-infra.yml and
# apply-deploy-pipeline-fix.yml — an unrelated job's env must not reach a test seam.
# A fixture root from `mktemp -d` lives OUTSIDE the repo, so the tests for this file
# never had to write into the live infra directory while sibling suites read it (#7376).
SOLEUR_INFRA_DIR="${SOLEUR_INFRA_DIR:-apps/web-platform/infra}"
[[ -d "$SOLEUR_INFRA_DIR" ]] || {
  echo "FATAL: SOLEUR_INFRA_DIR='$SOLEUR_INFRA_DIR' is not a directory — cannot glob" >&2
  echo "       the registered suite set." >&2
  exit 2
}

# Derivation is the FILESYSTEM GLOB, not a workflow `run: bash` scrape (ADR-251):
# presence under SOLEUR_INFRA_DIR IS registration — a suite on disk is in the
# execute set unless it carries a justified PRIVILEGED exclusion below. The scrape
# this replaced could not see subdirectory suites (its basename class excluded `/`)
# and made registration a second thing to remember — the #7076 blind spot, nine
# suites (6 subdir + 3 sudo) that CI ran but this runner never derived.
#
# `git ls-tree HEAD` is the source inside the repo: COMMITTED files only, so a
# scratch `.test.sh` nobody committed does not silently register, and the glob
# result is exactly what a fresh CI checkout will contain. `-r` recursion makes
# subdirectory suites visible. A caller-supplied fixture dir OUTSIDE the tree
# has no HEAD to consult and takes the filesystem arm.
if [[ "$SOLEUR_INFRA_DIR" == /* && "$SOLEUR_INFRA_DIR" != "$ROOT/"* ]]; then
  mapfile -t ALL_SUITES < <(find "$SOLEUR_INFRA_DIR" -type f -name '*.test.sh' | LC_ALL=C sort -u)
else
  # `git ls-tree HEAD`, not `git ls-files`: the index counts STAGED files, so a
  # `git add`ed-but-uncommitted suite would derive locally while being absent
  # from every CI checkout — the exact "on one laptop" defect the orphan report
  # exists to close. HEAD's tree is the committed set CI actually sees.
  # (ls-tree's pathspec is not a glob engine — list the prefix, filter the
  # suffix; `-r` recursion is what makes subdirectory suites visible.)
  mapfile -t ALL_SUITES < <(git ls-tree -r --name-only HEAD -- \
    "${SOLEUR_INFRA_DIR#"$ROOT"/}" | grep -E '\.test\.sh$' | LC_ALL=C sort -u)
fi

# A tracked SYMLINK is never a suite: the listing treats mode-120000 entries
# like files, and `bash "$s"` at dispatch follows the link silently — a symlink
# out of the repo executes out-of-repo content on a CI leg. Refuse, not skip:
# a silent skip would deregister the suite by name alone.
for _s in "${ALL_SUITES[@]}"; do
  if [[ -L "$_s" ]]; then
    echo "FATAL: '$_s' is a symlink — a suite is a real file, never a link." >&2
    echo "       Replace it with the file itself or remove it." >&2
    exit 2
  fi
  case "$_s" in
    *[[:space:]]*)
      echo "FATAL: suite path contains whitespace: '$_s' — per-suite capture keys" >&2
      echo "       and the manifest's label<TAB>leg format cannot carry it." >&2
      exit 2 ;;
  esac
done

# Two name-space invariants the machinery depends on, asserted once at derive
# time rather than degenerating per-suite:
#  (a) BASENAMES must be unique — PRIVILEGED_WHY is basename-keyed, so a second
#      `workspaces-luks-loopback.test.sh` in a subdirectory would inherit the
#      exclusion and run NOWHERE while the gate's sudo grep stayed satisfied by
#      the original's step.
#  (b) LOG KEYS must be unique — the shim munges a path to `a_b.test.sh` for its
#      .log/.meta/.trow files, so `infra/a/b.test.sh` and `infra/a_b.test.sh`
#      share one key: interleaved capture, a lost kill-rc, a dropped timing row.
(( ${#ALL_SUITES[@]} > 0 )) && {
  _dup="$(printf '%s\n' "${ALL_SUITES[@]##*/}" | LC_ALL=C sort | uniq -d | head -1)"
  [[ -z "$_dup" ]] || {
    echo "FATAL: duplicate suite basename '$_dup' — basenames must be unique across" >&2
    echo "       ${SOLEUR_INFRA_DIR} (PRIVILEGED_WHY and the registration gate key on them)." >&2
    exit 2
  }
  _dup="$(printf '%s\n' "${ALL_SUITES[@]//\//_}" | LC_ALL=C sort | uniq -d | head -1)"
  [[ -z "$_dup" ]] || {
    echo "FATAL: two suite paths munge to the same log key '$_dup' — per-suite" >&2
    echo "       .log/.meta/.trow files would collide. Rename one of them." >&2
    exit 2
  }
  unset _dup
}

# A silent zero here would print "0 failed" and read as success — the exact
# false-green this runner exists to end.
(( ${#ALL_SUITES[@]} > 0 )) || {
  echo "FATAL: derived ZERO suites from ${SOLEUR_INFRA_DIR}/*.test.sh." >&2
  echo "       If the directory moved, fix the glob; do not trust a run over nothing." >&2
  exit 2
}

# PRIVILEGED — derive-but-do-not-execute (#7076). These suites need root
# (loopback/dm devices, cryptsetup, mkfs) and run in CI via `sudo bash` steps in
# the deploy-script-tests-fixed job — the registration gate asserts that
# invocation exists ("the exclusion waives the runner, never the invocation").
# They are DERIVED here (presence = registration, so they stay counted and
# visible) but never invoked: a local host without passwordless sudo must not go
# permanently red on a suite it was never meant to run.
declare -A PRIVILEGED_WHY=(
  [git-data-plaintext-snapshot-loopback.test.sh]="dm-snapshot/mkfs evidence needs root (#5274)"
  [inngest-redis-luks-loopback.test.sh]="LUKS loopback blkid apparatus needs root (#7695)"
  [workspaces-luks-loopback.test.sh]="cryptsetup loopback needs root (#6588)"
)
PRIV_SUITES=()
SUITES=()
for _s in "${ALL_SUITES[@]}"; do
  if [[ -n "${PRIVILEGED_WHY[${_s##*/}]+x}" ]]; then
    PRIV_SUITES+=("$_s")
  else
    SUITES+=("$_s")
  fi
done
unset _s
_EXECUTABLE_N=${#SUITES[@]}

# SUITE_REGISTRATION enumerate — the machine-readable form the shard-manifest
# generator (`regenerate-shard-manifest.py --group infra`) consumes for its ⊆
# lint. Emits the EXECUTE set only: privileged suites are never timed by this
# runner, so tabling them would red the lint on a row no leg can produce.
if [[ "${1:-}" == "--enumerate" ]]; then
  printf 'SUITE_REGISTRATION\t%s\n' "${SUITES[@]}"
  exit 0
fi

# SOLEUR_INFRA_SHARD=k/N partitions the execute set across CI matrix legs.
# Parse contract mirrors SCRIPTS_SHARD in scripts/test-all.sh verbatim: unset =
# full set (local runs, main-health-monitor), set-but-malformed or out-of-range
# = exit 2 — never silently run everything or nothing.
_SHARD_K=0
_SHARD_N=0
if [[ -n "${SOLEUR_INFRA_SHARD+x}" ]]; then
  _shard_raw="${SOLEUR_INFRA_SHARD//[[:space:]]/}"
  # `[0123456789]`, not `[0-9]`: a collation-dependent class can match a fullwidth
  # digit that `10#` then fatals on — and bash RESUMES after the `if` with status
  # 0, leaving k/N=0/0, which reads as "not sharding" and runs the FULL set. An
  # enumerated class cannot be widened by collation. (Same contract as
  # SCRIPTS_SHARD's parser; see that comment block for the measured failure.)
  if [[ ! "$_shard_raw" =~ ^([0123456789]{1,9})/([0123456789]{1,9})$ ]]; then
    echo "ERROR: SOLEUR_INFRA_SHARD must be k/N with 1 <= k <= N (got: '${SOLEUR_INFRA_SHARD}')." >&2
    echo "       Unset it to run the full set. A malformed value is never inferred: it fails" >&2
    echo "       closed rather than silently running everything or nothing." >&2
    exit 2
  fi
  _SHARD_K=$(( 10#${BASH_REMATCH[1]} ))
  _SHARD_N=$(( 10#${BASH_REMATCH[2]} ))
  if (( _SHARD_N < 1 || _SHARD_K < 1 || _SHARD_K > _SHARD_N )); then
    echo "ERROR: SOLEUR_INFRA_SHARD must be k/N with 1 <= k <= N (got: '${SOLEUR_INFRA_SHARD}')." >&2
    echo "       Unset it to run the full set. A malformed value is never inferred: it fails" >&2
    echo "       closed rather than silently running everything or nothing." >&2
    exit 2
  fi
  echo "[shard] SOLEUR_INFRA_SHARD resolved k/N = ${_SHARD_K}/${_SHARD_N}"
fi

# Shard-assignment manifest (ADR-240 pattern): the committed
# apps/web-platform/infra/suite-shard-legs.tsv maps suite path -> leg from
# CI-measured durations (sticky-LPT via regenerate-shard-manifest.py --group
# infra). The runner only READS it — a missing/stale manifest degrades to the
# positional partition rather than failing, because coverage never depends on
# the table being present or current.
#
# SOLEUR_INFRA_MANIFEST overrides the default path (mutation-battery seam):
# `off` disables outright; set-but-empty, non-absolute, or missing all fail
# closed — an explicit override that cannot be honoured is a programming error,
# not a degrade. The DEFAULT path being absent IS a degrade.
_shard_manifest_active=0
_shard_m_labels=()
_shard_m_legs=()
if (( _SHARD_N > 0 )); then
  _shard_mfile="$ROOT/apps/web-platform/infra/suite-shard-legs.tsv"
  if [[ -n "${SOLEUR_INFRA_MANIFEST+x}" ]]; then
    _shard_mval="${SOLEUR_INFRA_MANIFEST-}"
    if [[ "$_shard_mval" == "off" ]]; then
      _shard_mfile=""
    elif [[ -z "$_shard_mval" ]]; then
      echo "ERROR: SOLEUR_INFRA_MANIFEST is set but empty." >&2
      echo "       Set it to an absolute manifest path, 'off', or unset it for the" >&2
      echo "       default $_shard_mfile." >&2
      exit 2
    elif [[ "$_shard_mval" != /* ]]; then
      echo "ERROR: SOLEUR_INFRA_MANIFEST must be an absolute path" >&2
      echo "       (got: '$_shard_mval') — this runner never normalises cwd." >&2
      exit 2
    elif [[ ! -f "$_shard_mval" ]]; then
      echo "ERROR: SOLEUR_INFRA_MANIFEST points at a file that does not exist:" >&2
      echo "       '$_shard_mval'" >&2
      exit 2
    else
      _shard_mfile="$_shard_mval"
    fi
  elif [[ ! -f "$_shard_mfile" ]]; then
    echo "[shard] no ${_shard_mfile##*/} manifest — positional assignment" >&2
    _shard_mfile=""
  fi

  if [[ -n "$_shard_mfile" ]]; then
    _shard_mn=""
    while IFS= read -r _mline; do
      case "$_mline" in
        "# n="*) _shard_mn="${_mline#\# n=}"; break ;;
      esac
    done < "$_shard_mfile"
    if [[ ! "$_shard_mn" =~ ^[0123456789]{1,9}$ ]] || (( 10#${_shard_mn} != _SHARD_N )); then
      echo "[shard] manifest n='${_shard_mn:-<none>}' != SOLEUR_INFRA_SHARD N=${_SHARD_N} — positional assignment" >&2
    else
      _shard_mcount=0
      while IFS=$'\t' read -r _mlbl _mleg _mrest; do
        case "$_mlbl" in
          "" | "#"*) continue ;;
        esac
        if [[ -n "$_mrest" || ! "$_mleg" =~ ^[0123456789]{1,9}$ ]]; then
          echo "ERROR: ${_shard_mfile}: malformed row '${_mlbl}' — expected 'suite-path<TAB>leg'" >&2
          echo "       with leg an integer in 1..${_shard_mn}. Regenerate:" >&2
          echo "         python3 scripts/regenerate-shard-manifest.py --group infra --write" >&2
          exit 2
        fi
        _mleg=$(( 10#${_mleg} ))
        if (( _mleg < 1 || _mleg > _shard_mn )); then
          echo "ERROR: ${_shard_mfile}: '$_mlbl' assigned to leg $_mleg outside 1..${_shard_mn}." >&2
          echo "       Regenerate: python3 scripts/regenerate-shard-manifest.py --group infra --write" >&2
          exit 2
        fi
        for (( _mdup = 0; _mdup < ${#_shard_m_labels[@]}; _mdup++ )); do
          if [[ "$_mlbl" == "${_shard_m_labels[_mdup]}" ]]; then
            echo "ERROR: ${_shard_mfile}: '$_mlbl' listed twice." >&2
            echo "       Regenerate: python3 scripts/regenerate-shard-manifest.py --group infra --write" >&2
            exit 2
          fi
        done
        _shard_m_labels+=("$_mlbl")
        _shard_m_legs+=("$_mleg")
        _shard_mcount=$(( _shard_mcount + 1 ))
      done < "$_shard_mfile"
      _shard_manifest_active=1
      echo "[shard] manifest assignment active: ${_shard_mcount} suite(s) from ${_shard_mfile}" >&2
    fi
  fi
  unset _shard_mfile _shard_mn _mline _mlbl _mleg _mrest _mdup _shard_mcount _shard_mval

  # Apply the partition. Manifest rows hit by label; an untabled suite (added
  # since the last regeneration) hashes deterministically (POSIX cksum), so an
  # insertion never moves an existing assignment and order is collation-free.
  # No manifest → positional round-robin over the sorted list.
  _assigned=()
  _ord=0
  for _s in "${SUITES[@]}"; do
    _ord=$(( _ord + 1 ))
    if (( _shard_manifest_active == 1 )); then
      _leg=0
      for (( _mi = 0; _mi < ${#_shard_m_labels[@]}; _mi++ )); do
        if [[ "$_s" == "${_shard_m_labels[_mi]}" ]]; then
          _leg=$(( 10#${_shard_m_legs[_mi]} ))
          break
        fi
      done
      (( _leg == 0 )) && _leg=$(( ($(printf '%s' "$_s" | cksum | cut -d' ' -f1) % _SHARD_N) + 1 ))
    else
      _leg=$(( (_ord - 1) % _SHARD_N + 1 ))
    fi
    (( _leg == _SHARD_K )) && _assigned+=("$_s")
  done
  SUITES=("${_assigned[@]}")
  unset _assigned _ord _s _leg _mi

  # Zero-assignment is a REFUSAL, not an empty green leg: a leg that owns
  # nothing would report "0 failed" and read as coverage.
  (( ${#SUITES[@]} > 0 )) || {
    echo "ERROR: shard ${_SHARD_K}/${_SHARD_N} owns ZERO of ${_EXECUTABLE_N} executable suites." >&2
    echo "       The partition (manifest or positional) assigned nothing to this leg — check" >&2
    echo "       SOLEUR_INFRA_SHARD and the manifest rather than trusting this run." >&2
    exit 2
  }
  echo "[shard] leg ${_SHARD_K}/${_SHARD_N} owns ${#SUITES[@]} of ${_EXECUTABLE_N} executable suites"
fi

# The carriers are consumed above — unset them so a suite that spawns a nested
# runner (run-registered-suites.test.sh re-executes this file) never inherits a
# partition it did not ask for (the #7902 lesson on SCRIPTS_SHARD). TIMINGS is
# captured first: this process still writes the feed at the end, but a nested
# runner must not scribble on the caller's artifact path mid-run.
_TIMINGS_OUT="${SOLEUR_INFRA_TIMINGS:-}"
# The feed is written to `_TIMINGS_OUT` by a bare `>` at end of run — a relative
# value would write into the repo cwd and a mistaken value would truncate an
# arbitrary writable file. Same contract as SOLEUR_INFRA_MANIFEST: absolute or
# absent.
if [[ -n "$_TIMINGS_OUT" && "$_TIMINGS_OUT" != /* ]]; then
  echo "ERROR: SOLEUR_INFRA_TIMINGS must be an absolute path" >&2
  echo "       (got: '$_TIMINGS_OUT') — this runner never normalises cwd." >&2
  exit 2
fi
unset SOLEUR_INFRA_SHARD SOLEUR_INFRA_MANIFEST SOLEUR_INFRA_TIMINGS

# Per-suite bound. The monolithic job's step-level `timeout-minutes` convention
# becomes the runner's responsibility in the sharded shape — a suite that stalls
# must RED NAMED, never cancel a leg anonymously. Resolved ONCE because this
# runner also executes on operator hosts, and stock macOS has no `timeout`
# (the `timeout`→`gtimeout`→absent order mirrors .claude/hooks/memory-backstop.sh).
TIMEOUT_BIN=""
for _t in timeout gtimeout; do
  if command -v "$_t" >/dev/null 2>&1; then
    TIMEOUT_BIN="$_t"; break
  fi
done
unset _t
if [[ -z "$TIMEOUT_BIN" ]]; then
  if [[ "${CI:-}" == "true" || "${GITHUB_ACTIONS:-}" == "true" ]]; then
    echo "FATAL: no per-suite bounder on PATH (tried: timeout, gtimeout) —" >&2
    echo "       bounds are mandatory under CI; a suite stall would cancel a leg" >&2
    echo "       anonymously. Install coreutils and re-run." >&2
    exit 2
  fi
  echo "NOTE: no timeout/gtimeout on PATH — suites run UNBOUNDED locally." >&2
fi
export SOLEUR_TIMEOUT_BIN="$TIMEOUT_BIN"

# Default bound + overrides. Default 360s is ~1.75x the heaviest measured suite
# (205 s, run 36037220776) — generous enough to never false-positive a healthy
# suite, small enough to bound a hang before the leg's timeout-minutes. The
# overrides carry forward the monolithic job's step-level `timeout-minutes`
# verbatim (x60); add an entry when a suite lands that legitimately exceeds the
# default. Keyed on the repo-relative suite path.
SOLEUR_SUITE_TIMEOUT_DEFAULT="${SOLEUR_SUITE_TIMEOUT_DEFAULT:-360}"
_SUITE_BOUNDS=(
  "apps/web-platform/infra/git-data-runcmd-rehearsal.test.sh=600"
  "apps/web-platform/infra/git-data-cutover-access.test.sh=600"
  "apps/web-platform/infra/git-data-ownership.test.sh=300"
  "apps/web-platform/infra/ci-deploy.test.sh=180"
  "apps/web-platform/infra/cloud-init-plugin-seed.test.sh=60"
  "apps/web-platform/infra/cloud-init-web-zot-seed.test.sh=300"
  "apps/web-platform/infra/registry-userdata-budget.test.sh=120"
  # These two carried no step-level bound in the serial job — the 35-min job
  # ceiling was their only bound. They are the 2nd/3rd-heaviest measured suites
  # (205 s / 197 s SERIAL, run 36037220776) and now run under -P4 contention,
  # where the #8688 incident measured docker-adjacent steps at 2.5-3x green on
  # degraded-runner days. 2.5x puts both over the 360 s default; pin them at
  # ~2.5x serial so a slow day renders as their own RED, not a leg timeout.
  "apps/web-platform/infra/infra-config-repush-mutation.test.sh=540"
  "apps/web-platform/infra/cloud-init-inngest-zot-pull-mutation.test.sh=540"
)
export SOLEUR_SUITE_TIMEOUTS="${_SUITE_BOUNDS[*]}"
export SOLEUR_SUITE_TIMEOUT_DEFAULT

# Report suite files on disk that the glob did NOT derive — under
# presence-is-registration that can only mean untracked (git ls-files returns
# tracked files only). An untracked suite never reaches a fresh CI checkout, so
# it is coverage that exists on exactly one laptop — the residual form of the
# "on disk, nothing runs it" defect this scan has always guarded.
#
# Advisory here; the registration gate enforces the tracked side (glob ==
# derived ∪ exclusions is exact by construction) — said plainly so a NOTE below
# is not read as optional. This runner declines to FAIL on it: its job is to
# run what CI runs.
#
# INFRA_ORPHAN_LIST is a TEST SEAM (#7376) that injects the CANDIDATE list only.
# The check itself — `git ls-files --error-unmatch`, which is the tracked-vs-not
# question being asserted — still runs for real. The seam exists because
# creating an untracked file in the LIVE infra directory mid-run collides with
# sibling suites reading that directory (#7376).
report_orphans() {
  local -a orphans
  mapfile -t orphans < <(
    while IFS= read -r f; do
      [[ -n "$f" ]] || continue
      git cat-file -e "HEAD:$f" >/dev/null 2>&1 || printf '%s\n' "$f"
    done < <(
      if [[ -n "${INFRA_ORPHAN_LIST:-}" ]]; then
        sort -u -- "$INFRA_ORPHAN_LIST"
      elif [[ "$SOLEUR_INFRA_DIR" == /* && "$SOLEUR_INFRA_DIR" != "$ROOT/"* ]]; then
        # A fixture root (absolute, from `mktemp -d`) is outside the repo, so the
        # untracked check has no index to consult. Emit no candidates rather than
        # leaking an error into the run log — but SAY SO: a silent skip is
        # byte-indistinguishable from "no orphans found".
        echo "NOTE: untracked-suite scan skipped — SOLEUR_INFRA_DIR is outside the repo working tree." >&2
      else
        find "$SOLEUR_INFRA_DIR" -type f -name '*.test.sh' | LC_ALL=C sort -u
      fi
    )
  )
  (( ${#orphans[@]} > 0 )) || return 0
  echo ""
  echo "NOTE: ${#orphans[@]} suite(s) on disk are NOT git-tracked — nothing runs them,"
  echo "      in CI or here (commit them, or they exist on exactly one machine):"
  printf '  %s\n' "${orphans[@]}"
}

if (( LIST_ONLY )); then
  echo "Derived ${#ALL_SUITES[@]} registered infra suite(s) from ${SOLEUR_INFRA_DIR}/*.test.sh:"
  printf '  %s\n' "${ALL_SUITES[@]}"
  if (( ${#PRIV_SUITES[@]} > 0 )); then
    echo ""
    echo "Privileged — derived but NOT executed here (${#PRIV_SUITES[@]}; CI runs them via"
    echo "'sudo bash' in deploy-script-tests-fixed):"
    for _s in "${PRIV_SUITES[@]}"; do
      printf '  SKIP privileged: %s — %s\n' "$_s" "${PRIVILEGED_WHY[${_s##*/}]}"
    done
  fi
  if (( _SHARD_N > 0 )); then
    echo ""
    echo "Shard ${_SHARD_K}/${_SHARD_N} execute set: ${#SUITES[@]} of ${_EXECUTABLE_N} suite(s):"
    printf '  %s\n' "${SUITES[@]}"
  else
    echo ""
    echo "Execute set: ${#SUITES[@]} suite(s)"
  fi
  report_orphans
  exit 0
fi

# min(nproc, 6) — capped because several suites shell out to terraform/docker and
# oversubscribing turns a slow run into a flaky one.
_NPROC=$(nproc 2>/dev/null || echo 4)
JOBS="${JOBS:-$(( _NPROC < 6 ? _NPROC : 6 ))}"
# `xargs -P 0` is GNU's UNBOUNDED mode — `JOBS=0` or a non-numeric value silently
# changes the parallelism contract rather than failing. Refuse them.
[[ "$JOBS" =~ ^[0-9]+$ ]] && (( JOBS >= 1 )) || {
  echo "FATAL: JOBS='$JOBS' is not a positive integer — xargs -P 0 means unbounded." >&2
  exit 2
}

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
# that can answer "did this suite run far longer than its solo baseline?". The version gate at
# the top of this file already refused anything below bash 5; EPOCHSECONDS is guaranteed here.
[[ -n "${EPOCHSECONDS:-}" ]] || exit 2

LOG="$(mktemp)" || { echo "FATAL: mktemp failed for the summary log (TMPDIR=$TMPDIR)" >&2; exit 2; }

# Age-reap older siblings before creating this run's dir. Retention-on-RED is deliberate, but
# nothing else reclaims these: ADR-133's tmpfs reaper scopes to /tmp while this runner exports
# TMPDIR=/var/tmp, and that ADR explicitly REJECTED count-based reaping — so this class is
# unreapable by construction unless the producer cleans up after itself. It accumulates fast
# because run-registered-suites.test.sh is itself a registered suite and drives this runner
# ~10x per invocation with deliberate REDs (measured: 414 dirs / 23 MB on the author's box
# before this reaper existed). Mirrors ADR-133's own `meta_dir` precedent.
find "${_SUITE_TMP_BASE}" -maxdepth 1 -name 'infra-suites.*' -type d -mmin +720 \
  -exec rm -rf {} + 2>/dev/null || true

# Initialise BEFORE the trap references it: `set -u` is active, so an unset var inside the
# trap would abort the trap itself. The trap reaps the log dir too — the inline reap below
# only covers a clean green exit, so a timeout, Ctrl-C or OOM would otherwise leak it even on
# an otherwise-healthy run. SOLEUR_KEEP_LOGDIR is set on the retain path so a genuine failure
# keeps its evidence.
SOLEUR_SUITE_LOGDIR=""
SOLEUR_KEEP_LOGDIR=""
trap 'rm -f "${LOG:-}"; [[ -n "${SOLEUR_KEEP_LOGDIR:-}" ]] || rm -rf "${SOLEUR_SUITE_LOGDIR:-/nonexistent}"; _soleur_scratch_cleanup 2>/dev/null || true' EXIT
# Logdir allocates at the BASE, not inside the session root: on RED the dir
# is retained as evidence (SOLEUR_KEEP_LOGDIR), and a root-scoped delete at
# EXIT would destroy exactly the artifact the retain path exists to keep.
# Base placement also keeps it inside the `infra-suites.*` self-reap above
# (12h floor) and the purge's signature row — bounded, attributable.
SOLEUR_SUITE_LOGDIR="$(mktemp -d -p "$_SUITE_TMP_BASE" infra-suites.XXXXXXXX)" || {
  echo "FATAL: mktemp -d failed for the per-suite log dir (TMPDIR=$TMPDIR)." >&2
  echo "       Refusing to run: every suite's capture would fail and the accounting" >&2
  echo "       assertion would then blame a vanished wrapper for a disk problem." >&2
  exit 2
}
# Deliberately NOT exported: the shim receives the path as argv ($2) so the
# counting dir never reaches a suite's environment.
SOLEUR_RUN_T0="$EPOCHSECONDS"; export SOLEUR_RUN_T0

if (( _SHARD_N > 0 )); then
  echo "Running ${#SUITES[@]} registered infra suite(s) (shard ${_SHARD_K}/${_SHARD_N} of ${_EXECUTABLE_N}) with -P ${JOBS}…"
else
  echo "Running ${#SUITES[@]} registered infra suite(s) with -P ${JOBS}…"
fi
if (( ${#PRIV_SUITES[@]} > 0 )); then
  echo "(${#PRIV_SUITES[@]} privileged suite(s) derived but not executed — CI runs them"
  echo " via 'sudo bash' in deploy-script-tests-fixed.)"
fi

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
#
# An EMPTY execute set must not reach xargs: `printf '%s\n' "${SUITES[@]}"` on an
# empty array emits one newline, and `-I{}` would run the shim once with s=""
# — a phantom suite with an empty log key. Reachable in fixtures where every
# derived basename is privileged.
(( ${#SUITES[@]} > 0 )) || {
  echo "FATAL: the execute set is empty — every derived suite is privileged." >&2
  echo "       Dispatching would fabricate a phantom suite; refusing." >&2
  exit 2
}
printf '%s\n' "${SUITES[@]}" \
  | xargs -P "$JOBS" -I{} bash -c '
      s="$1"; key="${s//\//_}"; logdir="$2"
      # logdir arrives as argv, not env: a suite must not see the counting dir
      # in its environment (a forgeable .meta/.trow write is a signal-shaped
      # lie). NOTE: no apostrophes inside this whole -c string — one truncates
      # argv and scrambles the shim (measured: `s: unbound variable`).
      # Per-suite bound: the override map arrives as one flat "path=secs" string
      # (assoc arrays do not export); keyed on the repo-relative path. rc=124 is
      # GNU timeout kill — it renders as RED below, naming the suite.
      bound="$SOLEUR_SUITE_TIMEOUT_DEFAULT"
      for kv in $SOLEUR_SUITE_TIMEOUTS; do
        # Literal compare — `case` would glob-match a suite path containing
        # `*`/`?`/`[` and bind the wrong bound. `${kv%%=*}` is the key half.
        [[ "${kv%%=*}" == "$s" ]] && bound="${kv##*=}"
      done
      st="$EPOCHSECONDS"
      # ONE call site for the suite itself — the bounder is a prefix, never a
      # second copy of the invocation (a mutated runner keeps the capture
      # discipline pinned on this exact line).
      if [[ -n "$SOLEUR_TIMEOUT_BIN" ]]; then
        set -- "$SOLEUR_TIMEOUT_BIN" -k 30 "$bound"
      else
        set --
      fi
      "$@" bash "$s" >"$logdir/$key.log" 2>&1; rc=$?
      printf "%s %s %s\n" "$rc" "$(( EPOCHSECONDS - st ))" "$(( st - SOLEUR_RUN_T0 ))" > "$logdir/$key.meta"
      # Per-suite timings row for the shard-manifest generator feed
      # (label<TAB>ms<TAB>verdict; FAIL rows are excluded by the generator — a
      # suite that did not finish carries a bound-hit timing, not a duration).
      verdict=FAIL; (( rc == 0 )) && verdict=PASS
      printf "%s\t%s\t%s\n" "$s" "$(( (EPOCHSECONDS - st) * 1000 ))" "$verdict" \
        > "$logdir/$key.trow"
      if (( rc == 0 )); then
        echo "PASS $s"
      else
        echo "RED  $s"
        # ::error annotation so the Actions run summary names the suite without
        # opening leg logs. `file=` is a structured property: strip CR/LF (line
        # injection) AND `:`,`,`,`%` (property/percent-escape injection) — a
        # committed filename is attacker-controlled in a fork PR.
        clean="$(printf %s "$s" | tr -d "\r\n:,%")"
        if (( rc == 124 )); then
          echo "::error file=$clean::suite exceeded its ${bound}s bound — see $key.log in the leg artifact"
        else
          echo "::error file=$clean::suite failed (rc=$rc) — see $key.log in the leg artifact"
        fi
      fi
    ' _ {} "$SOLEUR_SUITE_LOGDIR" \
  | tee "$LOG"

# READ IMMEDIATELY — PIPESTATUS is clobbered by the next command, and `$?` here is `tee`'s,
# which is why the xargs rc was previously lost. Index 1 is xargs (0=printf, 1=xargs, 2=tee).
# The only value with a defined meaning for this runner is 125: "a child was killed by a
# signal" — the shim-kill shape D3 in the header is about. 123 means a child exited non-zero,
# which the shim never does (its last command is an `echo`), so 123 here would itself be news.
XARGS_RC=${PIPESTATUS[1]}

# `^RED ` / `^PASS ` WITH the trailing space, matching every downstream consumer. Nothing else
# reaches $LOG — it is fed only by the child summary lines above — but the two anchors used to
# disagree, and a log line that merely began "RED" would have been counted.
RED=$(grep -c '^RED ' "$LOG" || true)
PASS=$(grep -c '^PASS ' "$LOG" || true)

# ── Signal classification, IN THE PARENT (#7429) ──────────────────────────────
#
# INLINED, NOT SOURCED FROM scripts/lib/ — ADR-177 §A3. run-registered-suites.test.sh sandboxes
# this file with a SINGLE-FILE `cp "$SUT" "$PRISTINE"` and then a python single-file MUTATOR.
# ADR-177 §A3 makes this fatal to SHARE, but not for the reason first recorded: the binding
# constraint is that run-registered-suites.test.sh drives a python SINGLE-FILE mutator over the
# copy, so the two rows that mutate the classifier BODY (drop-rc128-guard, drop-name-guard)
# could not be applied at all if it lived elsewhere. (The original reason — "a sourced lib
# would be absent from the copy" — does not follow: the runner cd's to $ROOT first, so a
# $ROOT-anchored source resolves fine. Corrected in ADR-187 at review; this copy is the
# propagation of that correction.) This body is a BOOLEAN predicate and is NOT
# byte-identical to the tri-state `suite_exit_class` in test-all.sh / run-all.sh -- the call
# site here already counts every non-zero child, so it needs "is this rc the killed subset?",
# not a three-way classification. `scripts/suite-exit-class-parity.test.sh` byte-compares only
# the two tri-state copies and pins THIS one behaviourally across the rc domain. Do not "restore
# parity" by copying the tri-state body in. Formerly this line said to keep it byte-identical to
# .github/scripts/test/run-all.sh so the parity pin can compare them.
#
# TWO guards, and both are load-bearing:
#   rc > 128      `kill -l 0` returns EXIT, so rc 128 would decode to a "signal" named EXIT.
#   -n "$name"    `kill -l 32` / `kill -l 33` exit 0 with EMPTY output (glibc's internal
#                 SIGCANCEL/SIGSETXID), and `kill -l 65`+ exits non-zero — both are rejected
#                 here, which is also why no `<= 192` upper bound is carried: ADR-177 records
#                 verbatim that the bound is NOT load-bearing and no test pins it.
# rc 124 stays UNKILLED on purpose: it is GNU `timeout`'s own exit, an attributed verdict by a
# named tool, and folding it in would lose exactly the attribution this change adds.
suite_rc_is_signal_shaped() {
  local rc="${1-}" name
  [[ "$rc" =~ ^[0-9]+$ ]] || return 1
  (( rc > 128 )) || return 1
  name=$(kill -l $(( rc - 128 )) 2>/dev/null) || return 1
  [[ -n "$name" ]]
}

# COUNTED HERE, IN THE PARENT — never inside dump_reds(). That function runs inside the
# `{ … } 2>&1 | sed …` block below, which is a PIPELINE SUBSHELL: a counter incremented there
# evaporates at the closing brace, and this repo has a 2026-07-27 learning about exactly that.
#
# LC_ALL=C on the glob, not just on the `comm` below: a bare glob's order is LC_COLLATE-
# dependent, and the multi-kill rule in the header is only reproducible if the walk is pinned.
#
# `killed` is a SUBSET of `RED`, never a re-partition of it. The child already prints `RED` for
# ANY non-zero rc including 137, so RED stays the total and `failed` is derived by subtraction.
# Keeping RED as the superset is what leaves the `RED  <path>` emit shape, the retention block
# and the summary line below untouched.
killed=0
kill_rc=0
while IFS= read -r _m; do
  [[ -s "$_m" ]] || continue
  _rc=""
  read -r _rc _ < "$_m" || true
  suite_rc_is_signal_shaped "$_rc" || continue
  killed=$(( killed + 1 ))
  (( kill_rc == 0 )) && kill_rc="$_rc"
done < <(shopt -s nullglob; printf '%s\n' "$SOLEUR_SUITE_LOGDIR"/*.meta | LC_ALL=C sort)

failed=$(( RED - killed ))
# Cannot happen — every signal-shaped rc is non-zero, so every killed suite is already a RED —
# but if it ever did, a negative `failed` would silently disarm the `failed > 0` arm below and
# turn a real failure green. Fail LOUD and fall back to the superset.
if (( failed < 0 )); then
  echo "INTERNAL: killed (${killed}) exceeds RED (${RED}) — counting every non-zero as failed." >&2
  failed=$RED
fi

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
    echo "The suite(s) named UNACCOUNTED above emitted neither PASS nor RED."
    # MEASURED, not guessed. The previous wording asserted "their wrapping shell died (OOM kill,
    # timeout, or a crash)" — three causes this runner had never measured, in the block a reader
    # trusts most (AP-021/ADR-166). The xargs rc is now captured, so the cause claim can be
    # sourced from an observation. See D3 in the header for why this still exits 1.
    if (( XARGS_RC == 125 )); then
      echo "MEASURED: xargs exited 125 — its documented code for \"a child was killed by a signal\","
      echo "so one of the wrapping \`bash -c\` shims was TERMINATED. WHICH signal, and by whom, is"
      echo "NOT measured here: the killed shim wrote no .meta, and the OOM killer is only the most"
      echo "common sender, not an observed one. xargs also STOPS DISPATCHING at that point, so some"
      echo "suites listed above may never have started rather than having died."
    else
      echo "MEASURED: xargs exited ${XARGS_RC}, not 125 — so no wrapping shim was reported killed by"
      echo "a signal, and the reporting gap is NOT explained by a terminated wrapper. Unmeasured."
    fi
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

# Per-suite timings feed for `regenerate-shard-manifest.py --group infra`: the
# caller sets SOLEUR_INFRA_TIMINGS to a writable path (CI legs point it at
# runner.temp and upload it as the suite-timings-infra-<k> artifact). Rows are
# each child's own `.trow` file, concatenated single-threaded strictly after
# xargs — never appended by the children (a shared open file description is not
# PIPE_BUF-atomic). UNACCOUNTED suites (shim killed, no .meta/.trow) and the
# privileged set get explicit `skip=` rows so the feed names the gap rather than
# omitting it; the generator's skip=/FAIL exclusions drop them from the balance.
# BEFORE the logdir reap below — the .trow files live under it.
if [[ -n "${_TIMINGS_OUT:-}" ]]; then
  {
    for _t in "$SOLEUR_SUITE_LOGDIR"/*.trow; do
      [[ -e "$_t" ]] || continue
      cat "$_t"
    done
    if (( ${#UNACCOUNTED[@]} > 0 )); then
      for _s in "${UNACCOUNTED[@]}"; do printf '%s\t0\tskip=unaccounted\n' "$_s"; done
    fi
    if (( ${#PRIV_SUITES[@]} > 0 )); then
      for _s in "${PRIV_SUITES[@]}"; do printf '%s\t0\tskip=privileged\n' "$_s"; done
    fi
  } > "${_TIMINGS_OUT}" || \
    echo "WARNING: could not write timings feed to ${_TIMINGS_OUT}" >&2
fi

if (( RED == 0 && ${#UNACCOUNTED[@]} == 0 )); then
  rm -rf "$SOLEUR_SUITE_LOGDIR"
else
  SOLEUR_KEEP_LOGDIR=1
fi

report_orphans

echo ""
# GATED ON killed > 0, and emitted BEFORE the summary, mirroring scripts/test-all.sh's own
# breakdown-line precedent. Both halves matter: gated, so a clean run's bytes are unchanged;
# before, so the monitor's `tail -30` still ENDS on the count line. Deliberately NOT shaped like
# `=== N suites: …` — main-health-monitor.yml anchors that exact shape for test-all.sh's own
# breakdown, and a second line matching it would corroborate a KILLED title from the wrong file.
if (( killed > 0 )); then
  echo "=== of the ${RED} counted \`failed\` below, ${killed} were TERMINATED BY A SIGNAL — unresolved, not assertion failures (propagating rc ${kill_rc} = SIG$(kill -l $(( kill_rc - 128 )) 2>/dev/null)) ==="
fi
# The count line carries all THREE numbers. Reporting only passed/failed is what let
# "91 passed, 0 failed (of 93)" read as success while two suites had vanished.
#
# THE `failed` LABEL IS IMPRECISE WHEN A SUITE WAS TERMINATED, AND IS KEPT ANYWAY. `RED` counts
# every non-zero child, so a killed suite is counted here among "failed". Correcting the label
# — or adding a fourth number — would break both of this line's exact-string consumers
# (run-registered-suites.test.sh T6v and plugins/soleur/test/main-health-monitor-workflow.test.sh),
# so the precision is carried by the gated line above instead. Keep this line BYTE-IDENTICAL.
echo "=== registered infra suites: ${PASS} passed, ${RED} failed, ${#UNACCOUNTED[@]} unaccounted (of ${#SUITES[@]}) ==="

# THE PROPAGATION (#7429). Precedence, and each arm's reason:
#   failed > 0        an attributed assertion failure dominates everything, per ADR-177.
#   UNACCOUNTED > 0   a suite that never reported is UNMEASURED — see D3 in the header for why
#                     this stays 1 even when xargs measured a shim kill.
#   killed > 0        propagate the observed 128+N so run_suite renders [KILLED], not [FAIL].
if (( failed > 0 || ${#UNACCOUNTED[@]} > 0 )); then
  exit 1
elif (( killed > 0 )); then
  exit "$kill_rc"
fi
exit 0
