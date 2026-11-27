#!/usr/bin/env bash
# test-infra-suite-registration.sh -- fail when an infra *.test.sh is registered nowhere, or
# the sharded runner invocation that reaches it has been disconnected.
#
# WHY (#7068, re-shaped by #8736). Infra suites were once registered ONLY as explicit
# `run: bash …` steps in .github/workflows/infra-validation.yml, and this gate asserted that
# step shape. #8736 replaced ~146 serial named steps with a K=4 matrix whose legs all invoke
# apps/web-platform/infra/run-registered-suites.sh, and the runner now DERIVES its execute set
# by `git ls-files` glob: presence under apps/web-platform/infra/ IS registration (ADR-252).
#
# That makes the old per-suite step check tautological — every tracked suite is registered by
# construction — so what remains to gate is the CONNECTION, and the exceptions:
#
#   1. The `deploy-script-tests` matrix job must exist and invoke the runner with
#      SOLEUR_INFRA_SHARD wired from `matrix.leg`, with `fail-fast: false` — otherwise
#      one leg's failure cancels its siblings and coverage silently shrinks.
#   2. The runner step itself must carry NO `if:`/`continue-on-error:` — the masking
#      check, now scoped to the step that matters (artifact-upload steps legitimately
#      carry `if: failure()`/`always()`).
#   3. The PRIVILEGED set (suites that need root and therefore must NOT run under the
#      unprivileged runner — the derive-but-do-not-execute contract from #7076) must
#      each be `sudo bash`-invoked inside `deploy-script-tests-fixed`, as a whole command
#      line (not an `echo`, not `… || true`), in a step with no `if:`/`continue-on-error:`/
#      `shell:`/`set +e`, and no plain-scalar continuation line after a single-line `run:`
#      (YAML folds it into the command). The exclusion waives the RUNNER, never the
#      invocation. (Not allowlisted like item 5: the fixed job is a shared battery whose steps
#      change often.) RESIDUALS, stated so a later shape inside them is "covered by item 3":
#      inside a multi-line `run: |` block, other lines of the same step can still neutralise
#      the command (a `trap 'exit 0' EXIT`, an `if false; then … fi` wrapper, a `sudo()`
#      function); those steps are reviewed as code, not pinned here.
#   4. `deploy-script-tests-done` must exist and need both legs (and every dedicated
#      job, below) — it is the single verdict `notify-main-failure` reads.
#   5. The DEDICATED set (#12941, CTO Q25: suites that cannot ride a ship battery) is
#      derive-but-do-not-execute, like PRIVILEGED — the runner never executes them,
#      sharded or unsharded, and omits them from --enumerate. The claim is quantified over
#      an ALLOWLISTED job shape, not over the spellings a denylist happened to list. For
#      every DEDICATED_JOB_WHY entry, the job its value names (`runs in the <job> job`)
#      holds ONLY: job keys needs / if (one allowlisted value) / runs-on (a pinned hosted
#      ubuntu-NN.NN) / permissions (exactly `contents: read`) / timeout-minutes / steps;
#      steps at the canonical indentation; `uses:` steps of actions/checkout (`with:` =
#      exactly `persist-credentials: false`), hashicorp/setup-terraform and
#      actions/upload-artifact (the only one that may carry `if:`), each @<40-hex sha>; and
#      EXACTLY ONE `run:` step whose whole value is `bash <path>` and which holds only
#      name:/run:. Refused by name anywhere in the job: `shell:`, `defaults:`, `env:`,
#      `continue-on-error:`, `working-directory:`, `GITHUB_ENV`/`GITHUB_PATH`; and at the
#      workflow level `defaults:`. Every `${{ }}` in the job and the workflow env it
#      inherits is on an exact, case-insensitive allowlist; the `secrets` context in any
#      spelling, `github.token`, `github[`, `toJSON(github)` are refused; the workflow env
#      is held to its key allowlist. The suite's stem appears on exactly ONE
#      comment-stripped line of .github/workflows/** and .github/actions/** — that step.
#      Under that shape, a green gate means: the suite runs, unmasked, as CI hands it
#      over, in that job only, on a hosted runner, with no credential bound and no
#      persisted token. The runner's never-execute BEHAVIOUR is pinned by
#      apps/web-platform/infra/run-registered-suites.test.sh (T11k), which executes the
#      runner; this gate reads only the runner's derive-only `--list`.
#      RESIDUALS of item 5 (outside the allowlisted subset by construction, so a later
#      shape inside one of these is recorded here, not a new gate gap):
#        - What the allowlisted actions and the runner image DO: a SHA bump of checkout/
#          setup-terraform/upload-artifact, or a GitHub change to the ubuntu-NN.NN image
#          (docker, cloud-init, the default `bash -e` shell), changes behaviour this gate
#          never reads. Pin review and the suite's own refusals own those.
#        - The suite's BODY: an `exit 0` committed into the suite itself. Its own self-tests
#          and code review own that; this gate certifies the wiring, not the suite.
#        - Callers: infra-validation.yml has no `workflow_call` trigger today; if one is
#          added, a caller chooses triggers and inputs/`secrets: inherit` (the job still
#          references none). Triggers and paths filters are the existing asymmetry below.
#        - Constructed paths: a mention assembled at runtime (a glob over infra/*.test.sh,
#          string concatenation, `find`) in another job carries no stem token to count.
#          The runner is the only sanctioned glob, and it never executes this set.
#        - Runtime verdicts: a job-level `if:` that skips or a timeout that cancels the job
#          is read as non-success by deploy-script-tests-done (item 4), not by this gate.
#
# WHAT IT DOES *NOT* ASSERT, stated so no reader over-reads a green run:
#   - Whether a suite's VERDICT blocks merge. deploy-script-tests is advisory; promotion
#     is #6480's job, not this gate's.
#   - That infra-validation.yml runs at all for a given PR (paths-filtered, no
#     merge_group trigger) — same trigger asymmetry the old contract had.
#   - Manifest FRESHNESS: the gate asserts every suite-shard-legs.tsv row names
#     an executable suite with a leg inside the matrix's 1..N and that the
#     `# n=` header matches — stale/malformed rows and duplicate-row drift —
#     but not that the manifest is recently regenerated. A stale-but-valid
#     table degrades legs to a lopsided balance, never to a coverage loss:
#     untabled suites hash-fallback into a leg by design.
#
# The privileged and dedicated lists are read FROM THE RUNNER (its PRIVILEGED_WHY and
# DEDICATED_JOB_WHY maps, each parsed only inside its own `declare -A` block), never
# duplicated here — two lists over one set is the drift this file exists to prevent,
# one level up. The parse is then held EQUAL to the runner's own `--list` SKIP sets,
# so an entry the text parse cannot see fails here instead of vanishing from CI.
# Each entry must cite a tracking issue, the same fail-closed discipline the old
# EXCLUSIONS array carried.
#
# WHY IT LIVES HERE. The `test-*.sh` glob in run-all.sh feeds guard-script-fixture-tests --
# REQUIRED, merge_group-triggered, path-filter-free. So this gate is genuinely blocking while
# adding NO new required-check name. It honours that glob's BASH-ONLY contract verbatim
# (git + sed + grep + awk, reading YAML as text) -- no terraform, no cloud-init, no apt.
#
# Its own non-vacuity is pinned by a committed harness, not by a comment:
# test-infra-suite-registration-mutations.sh (same directory, so also auto-globbed).
# Every arm below has a mutation row there.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
WF_REL=".github/workflows/infra-validation.yml"
WF="$REPO_ROOT/$WF_REL"
RUNNER_REL="apps/web-platform/infra/run-registered-suites.sh"
RUNNER="$REPO_ROOT/$RUNNER_REL"
JOB="deploy-script-tests"
FIXED_JOB="deploy-script-tests-fixed"
DONE_JOB="deploy-script-tests-done"
INFRA_PREFIX="apps/web-platform/infra"

err() { echo "::error::infra-suite-registration: $1" >&2; }

if [[ ! -f "$WF" ]]; then
  err "$WF_REL not found -- cannot verify infra suite registration"
  exit 1
fi
if [[ ! -f "$RUNNER" ]]; then
  err "$RUNNER_REL not found -- the runner this gate asserts wiring FOR is missing"
  exit 1
fi

# Slice a job's YAML text (comment lines stripped — a commented-out invocation must
# never satisfy a check; that was the anti-vacuity core of the old gate too).
# Job-scoping is load-bearing: a whole-file scan cannot honestly say "runs in no CI job".
# The slice ends at ANY non-comment line at indent 2 or 0 — the next job header however it
# is spelled (`  next:  # note`, `  "next":`, `  next :`), or the end of the jobs map. A
# header-shape match (`^  name:$`) let a following job whose header carried a trailing
# comment be read as part of this one (#12941 review round 2, row H25). No line inside a job
# sits at indent 2: its keys are at 4 and block-scalar content is deeper than its key.
slice_job() {  # slice_job <job-name>
  awk -v job="  $1:" '
    $0 == job { injob = 1; next }
    injob && (/^  [^[:space:]#]/ || /^[^[:space:]#]/) { injob = 0 }
    injob { print }
  ' "$WF" | grep -vE '^[[:space:]]*#' || true
}

JOB_RAW=$(slice_job "$JOB")
FIXED_RAW=$(slice_job "$FIXED_JOB")
DONE_RAW=$(slice_job "$DONE_JOB")

fails=0

if [[ -z "${JOB_RAW//[[:space:]]/}" ]]; then
  err "could not slice the \`$JOB\` job out of $WF_REL -- the job was renamed, removed, or"
  err "  its indentation changed. This gate cannot make any claim; fix the slice, do not delete it."
  exit 1
fi
if [[ -z "${FIXED_RAW//[[:space:]]/}" ]]; then
  err "could not slice the \`$FIXED_JOB\` job out of $WF_REL -- the privileged suites and"
  err "  fixed checks have nowhere to run. Restore the job or remove the privileged set."
  exit 1
fi
if [[ -z "${DONE_RAW//[[:space:]]/}" ]]; then
  err "could not slice the \`$DONE_JOB\` job out of $WF_REL -- notify-main-failure reads"
  err "  that aggregator's result; without it a red leg alerts nobody."
  exit 1
fi

# ── Arm 1: the matrix job invokes the runner, sharded, fail-open-proof ────────
# The runner step is identified by its `run:` line, not its name — names are prose.
RUNNER_STEPS=$(printf '%s\n' "$JOB_RAW" | grep -cE "run: bash ${RUNNER_REL}[[:space:]]*$" || true)
if (( RUNNER_STEPS != 1 )); then
  err "the \`$JOB\` job contains ${RUNNER_STEPS} \`run: bash ${RUNNER_REL}\` invocations"
  err "  (expected exactly 1). The suite set executes through that one step; zero means"
  err "  no infra suite runs in CI, two means every suite runs twice."
  fails=$((fails + 1))
fi

# SOLEUR_INFRA_SHARD must be wired from the matrix leg ON THE RUNNER STEP — a
# job-wide grep alone passes if the env lands on a sibling step while the runner
# step runs the FULL set (4x the wall clock and a leg that LOOKS sharded).
# Herestring, not `printf | awk …exit`: awk exiting on the first match SIGPIPEs printf, and under
# pipefail + set -e that 141 kills the gate with no message (measured: rc=141 on rows A5-9/G2).
RUNNER_RECORD=$(awk -v RS='      - ' '/run-registered-suites[.]sh/{print; exit}' <<< "$JOB_RAW")
if ! grep -qE 'SOLEUR_INFRA_SHARD:[[:space:]]+\$\{\{[[:space:]]*matrix\.leg[[:space:]]*\}\}' \
     <<< "$RUNNER_RECORD"; then
  err "the \`$JOB\` runner step does not set SOLEUR_INFRA_SHARD from matrix.leg —"
  err "  without it every leg runs the FULL suite set."
  fails=$((fails + 1))
fi

# SOLEUR_INFRA_DIR narrows the runner's derived root — a fixture seam, never a
# CI knob. Setting it on the leg's env shrinks coverage while legs tile + green.
if grep -qE 'SOLEUR_INFRA_DIR:' <<< "$JOB_RAW"; then
  err "the \`$JOB\` job sets SOLEUR_INFRA_DIR — the fixture seam narrowing the"
  err "  derived suite root must never be wired into CI."
  fails=$((fails + 1))
fi
# Same class for the other derivation carriers on the runner step: MANIFEST=off
# or a narrowed path changes assignment silently; TIMINGS is legitimate (the
# feed), INFRA_DIR is not.
for _bad_env in SOLEUR_INFRA_MANIFEST INFRA_ORPHAN_LIST; do
  if grep -qE "${_bad_env}:" <<< "$RUNNER_RECORD"; then
    err "the \`$JOB\` runner step sets $_bad_env — a derivation seam must not be"
    err "  wired into the CI leg."
    fails=$((fails + 1))
  fi
done

# A matrix without legs, or legs that are not k/N strings, is a silent full-set run.
LEG_ROWS=$(printf '%s\n' "$JOB_RAW" | grep -cE 'leg:[[:space:]]*\[' || true)
if (( LEG_ROWS < 1 )) || ! grep -qE 'leg:[[:space:]]*\["1/[0-9]+"' <<< "$JOB_RAW"; then
  err "the \`$JOB\` job's matrix has no \`leg: [\"k/N\", ...]\` list — the legs and the"
  err "  runner's shard parser have drifted."
  fails=$((fails + 1))
fi
# A SECOND `leg:` key is a silent hijack: this gate reads the first list
# (head -1 below) but YAML executes the last — an appended `leg: ["5/5"]` after
# the valid list greens the gate while every leg runs one residue class.
if (( LEG_ROWS > 1 )); then
  err "the \`$JOB\` matrix declares $LEG_ROWS \`leg:\` keys — YAML executes the LAST"
  err "  while this check reads the first; one key, one list."
  fails=$((fails + 1))
fi

# LEG-SET TOTALITY (ADR-238 Decision 3 — totality is asserted against the declared
# list, never assumed). A `leg:` list that drops a value (["1/4","2/4","3/4"]) or
# duplicates one (["1/4","1/4","2/4","4/4"]) leaves a residue class executed by NO
# leg: every declared leg goes green, the runner's zero-assignment refusal never
# fires on a leg that was never invoked, and the aggregator sees only the rolled-up
# success — a silent coverage shrink behind a fully green pipeline. Parse every
# "k/N" entry: require a single shared N, distinct k values, and exactly N of them.
LEG_N=""; LEG_BAD=0
LEG_LINE=$(grep -oE 'leg:[[:space:]]*\[[^]]*\]' <<< "$JOB_RAW" | head -1 || true)
if [[ -n "$LEG_LINE" ]]; then
  mapfile -t LEGS < <(grep -oE '"[0-9]+/[0-9]+"' <<< "$LEG_LINE" | tr -d '"')
  declare -A LEG_SEEN=()
  for leg in "${LEGS[@]:-}"; do
    [[ -n "$leg" ]] || continue
    k="${leg%%/*}"; n="${leg##*/}"
    if [[ -z "$LEG_N" ]]; then LEG_N="$n"; elif [[ "$n" != "$LEG_N" ]]; then LEG_BAD=1; fi
    if [[ -n "${LEG_SEEN[$k]:-}" ]]; then LEG_BAD=1; else LEG_SEEN[$k]=1; fi
    # 10# pins: `08`/`09` are octal-shaped and arithmetic on them fails with a
    # misleading "value too great for base" instead of the verdict below.
    (( 10#$k >= 1 && 10#$k <= 10#$n )) || LEG_BAD=1
  done
  if (( LEG_BAD == 0 )) && [[ -n "$LEG_N" ]] && (( ${#LEGS[@]} == LEG_N )) \
     && (( ${#LEG_SEEN[@]} == LEG_N )); then
    : # totality holds: N distinct legs tiling 1..N
  else
    err "the \`$JOB\` leg list does not tile 1..N (declared: ${LEGS[*]:-none}) — a"
    err "  dropped or duplicated leg leaves part of the suite set executed by NO leg."
    fails=$((fails + 1))
  fi
fi

# fail-fast: false — a RED leg must not cancel its siblings; the aggregator needs
# every leg's verdict and a cancelled sibling's suites never ran (coverage, not
# just attribution).
if ! grep -qE 'fail-fast:[[:space:]]*false' <<< "$JOB_RAW"; then
  err "the \`$JOB\` matrix lacks \`fail-fast: false\` — one RED leg cancels the other"
  err "  three, and a quarter of the suite set silently never runs."
  fails=$((fails + 1))
fi

# ── Arm 2: masking — scoped to the suite-executing STEPS, not the jobs ────────
# The old gate asserted zero `if:`/`continue-on-error:` keys job-wide, because
# then every step was a suite and masking any step masked coverage. Now the
# load-bearing steps are the runner invocation, the fixed job's suite steps,
# and the aggregate step; upload steps legitimately carry `if: failure()`/
# `always()`. Assert each pinned step's own block is unmasked.
mask_check() {  # $1=job_raw $2=record-regex $3=label
  local rec
  rec=$(awk -v RS='      - ' -v pat="$2" '$0 ~ pat {print; exit}' <<< "$1")   # herestring: see RUNNER_RECORD
  [[ -z "$rec" ]] && return 0   # presence is asserted by the owning arm; mask-check what exists
  if grep -qE '^[[:space:]]+(continue-on-error|if):' <<< "$rec"; then
    err "$3 carries a \`continue-on-error:\`/\`if:\` key — masking a step this gate"
    err "  treats as load-bearing. Artifact-upload steps may carry \`if:\`; suite-"
    err "  executing and aggregate steps may not."
    fails=$((fails + 1))
  fi
}
mask_check "$JOB_RAW" 'run-registered-suites[.]sh' "the \`$JOB\` runner step"
mask_check "$DONE_RAW" 'MATRIX_RESULT|Aggregate deploy-script-tests results' \
  "the \`$DONE_JOB\` aggregate step"

# ── Arm 3: the privileged set — derived from the RUNNER, invoked via sudo ─────
# PRIVILEGED_WHY lives in run-registered-suites.sh — the single source of truth for
# "needs root, never run unprivileged". Parse its `[basename]="reason"` entries.
# The map must parse AND be non-empty: an empty map is a legitimate future state
# (no root suites), so the floor is "the block parsed at all", asserted by the
# per-suite loop below — a suite under a privileged basename with no map entry is
# just a normal suite, which is the #7076 hole in reverse and is caught by... the
# local run itself going red. What THIS gate pins is narrower: every map entry is
# a real tracked suite AND is sudo-invoked in the fixed job.
# Block-scoped map reader: the entries of ONE `declare -A <NAME>=(` block, up to its
# closing `)` at column 0. A whole-file scrape (the pre-#12941 shape) read every
# `  [x.test.sh]="..."` line in the runner as PRIVILEGED, so a second map's entry would
# have demanded a `sudo bash` step for a suite that never needs root.
map_entries() {  # map_entries <MAP_NAME>  -> "basename]=value" rows
  awk -v open="declare -A $1=(" '
    $0 == open { inmap = 1; next }
    inmap && /^\)/ { exit }
    inmap { print }
  ' "$RUNNER" | sed -n 's/^  \[\([A-Za-z0-9._-]*\.test\.sh\)\]="\(.*\)"$/\1]=\2/p'
}

declare -A PRIVILEGED=()
while IFS= read -r line; do
  base="${line%%]=*}"
  reason="${line#*]=}"
  [[ -n "$base" ]] || continue
  if ! grep -qE '#[1-9][0-9]*' <<< "$reason"; then
    err "privileged entry '$base' in ${RUNNER_REL}'s PRIVILEGED_WHY cites no tracking"
    err "  issue — an exclusion is a recorded decision, not a silent absorption."
    fails=$((fails + 1))
  fi
  PRIVILEGED["$base"]=1
done < <(map_entries PRIVILEGED_WHY)

# The sed above is format-pinned; a reformatted entry (trailing comment, a new
# indent) yields ZERO rows and makes every check below vacuously green — while
# the RUNNER's own map keeps excluding those suites from the legs. If the file
# still declares the map, zero parsed entries is a parse failure, not an empty
# set. (This gate is bash≥4 — declare -A/mapfile — by the same measured
# constraint test-all.sh documents for its own shard block being bash-3.)
if grep -qE 'PRIVILEGED_WHY=\(' "$RUNNER" && (( ${#PRIVILEGED[@]} == 0 )); then
  err "PRIVILEGED_WHY exists in ${RUNNER_REL} but parsed to ZERO entries —"
  err "  the sed pattern no longer matches the block's shape. Fix the parse;"
  err "  do not let an unparseable map read as an empty one."
  fails=$((fails + 1))
fi

# DEDICATED_JOB_WHY — same parse, same fail-closed floor, same issue citation; each
# value must also NAME its owning job (`runs in the <job> job`), which is where Arm 5
# looks for the invocation.
declare -A DEDICATED=()
declare -A DEDICATED_JOB_OF=()
while IFS= read -r line; do
  base="${line%%]=*}"
  reason="${line#*]=}"
  [[ -n "$base" ]] || continue
  if ! grep -qE '#[1-9][0-9]*' <<< "$reason"; then
    err "dedicated entry '$base' in ${RUNNER_REL}'s DEDICATED_JOB_WHY cites no tracking"
    err "  issue — an exclusion is a recorded decision, not a silent absorption."
    fails=$((fails + 1))
  fi
  if [[ -n "${PRIVILEGED[$base]+x}" ]]; then
    err "'$base' is in BOTH PRIVILEGED_WHY and DEDICATED_JOB_WHY — one exclusion kind per suite."
    fails=$((fails + 1))
  fi
  if [[ "$reason" =~ runs\ in\ the\ ([A-Za-z0-9_-]+)\ job ]]; then
    DEDICATED_JOB_OF["$base"]="${BASH_REMATCH[1]}"
  else
    err "dedicated entry '$base' in ${RUNNER_REL}'s DEDICATED_JOB_WHY names no owning job"
    err "  (expected the words 'runs in the <job> job') — the invocation check has nowhere to look."
    fails=$((fails + 1))
  fi
  DEDICATED["$base"]=1
done < <(map_entries DEDICATED_JOB_WHY)
if grep -qE 'DEDICATED_JOB_WHY=\(' "$RUNNER" && (( ${#DEDICATED[@]} == 0 )); then
  err "DEDICATED_JOB_WHY exists in ${RUNNER_REL} but parsed to ZERO entries —"
  err "  the sed pattern no longer matches the block's shape. Fix the parse;"
  err "  do not let an unparseable map read as an empty one."
  fails=$((fails + 1))
fi
# The jobs the dedicated set lives in (distinct, sorted) — Arm 4 requires each in the
# aggregator's needs:.
mapfile -t DEDICATED_JOBS < <(for b in "${!DEDICATED_JOB_OF[@]}"; do
  printf '%s\n' "${DEDICATED_JOB_OF[$b]}"; done | LC_ALL=C sort -u)

# Enumerate the tracked suite set — same HEAD-tree basis the runner uses
# (`git ls-tree -r` + suffix filter; the index would count staged-but-
# uncommitted files, which a fresh CI checkout never contains).
SUITES=()
while IFS= read -r f; do
  [[ -n "$f" ]] && SUITES+=("$f")
done < <(git -C "$REPO_ROOT" ls-tree -r --name-only HEAD -- "${INFRA_PREFIX}/" \
  | grep -E '\.test\.sh$' | LC_ALL=C sort -u)

# Minimum-cardinality guard: a broken enumeration yielding ZERO would pass every
# per-suite check below while certifying nothing. Ratcheted with the corpus
# (147 at last count — floor set at ~90%, never tightened upward automatically).
if (( ${#SUITES[@]} < 130 )); then
  err "enumerated only ${#SUITES[@]} infra suite(s) under ${INFRA_PREFIX} -- expected ~145."
  err "  The enumeration is broken; this gate cannot make any claim. Fix it, do not lower the floor."
  exit 1
fi

declare -A TRACKED=()
declare -A TRACKED_REL=()
for rel in "${SUITES[@]}"; do TRACKED["${rel##*/}"]=1; TRACKED_REL["$rel"]=1; done

# ── Map cross-check: the text parse above vs what the RUNNER evaluates ─────────
# map_entries is a format-pinned read; the runner's set is whatever bash evaluates. An
# entry the sed cannot see (a trailing `# comment`, single quotes, a `MAP[x]=` assignment
# after the block) is excluded from every leg by the runner while every check here stays
# green over it — the suite then runs in NO CI job (#12941 review, rows G9-G11). Three
# refusals, each fail-closed: (1) every non-blank, non-comment block line must parse;
# (2) the map is assigned at exactly one site, its `declare -A` line; (3) the parsed set
# (tracked members) EQUALS the runner's own `--list` `SKIP <kind>:` set — set equality,
# not a count, so a swap of one member for another cannot pass. `--list` derives only
# and runs nothing (bash + git ls-tree), so the bash-only contract above still holds.
_rl_rc=0
RUNNER_LIST=$(cd "$REPO_ROOT" && env -u SOLEUR_INFRA_DIR -u SOLEUR_INFRA_SHARD \
  -u SOLEUR_INFRA_MANIFEST INFRA_ORPHAN_LIST=/dev/null bash "$RUNNER" --list 2>&1) || _rl_rc=$?
if (( _rl_rc != 0 )); then
  err "\`bash ${RUNNER_REL} --list\` exited $_rl_rc — the runner's own exclusion sets cannot be"
  err "  read, so the parse below cannot be cross-checked: $(tail -2 <<< "$RUNNER_LIST" | tr '\n' ' ')"
  fails=$((fails + 1))
fi
map_crosscheck() {  # map_crosscheck <MAP_NAME> <list-kind> <assoc-name of the parsed set>
  local -n _parsed="$3"
  local _bad _sites _want _got _b
  _bad=$(awk -v open="declare -A $1=(" '
    $0 == open { inmap = 1; next }
    inmap && /^\)/ { exit }
    inmap && !/^[[:space:]]*(#|$)/ { print }
  ' "$RUNNER" | grep -vE '^  \[[A-Za-z0-9._-]*\.test\.sh\]=".*"$' || true)
  if [[ -n "$_bad" ]]; then
    err "$1 in ${RUNNER_REL} has block line(s) this gate cannot parse (the runner still"
    err "  honours them): $(head -3 <<< "$_bad" | tr '\n' '|') — one \`  [x.test.sh]=\"…\"\` per line."
    fails=$((fails + 1))
  fi
  _sites=$(grep -vE '^[[:space:]]*#' "$RUNNER" | grep -cE "(^|[^A-Za-z0-9_])$1(\[[^]]*\])?[+]?=" || true)
  if (( _sites != 1 )); then
    err "$1 is assigned at ${_sites} site(s) in ${RUNNER_REL} (expected 1, its \`declare -A\`"
    err "  block) — an entry added elsewhere is invisible to this gate's parse."
    fails=$((fails + 1))
  fi
  (( _rl_rc == 0 )) || return 0
  _want=$(for _b in "${!_parsed[@]}"; do
      if [[ -n "${TRACKED[$_b]+x}" ]]; then printf '%s\n' "$_b"; fi
    done | LC_ALL=C sort -u)
  _got=$(sed -n "s|^  SKIP $2: \([^ ]*\) .*|\1|p" <<< "$RUNNER_LIST" | sed 's|.*/||' | LC_ALL=C sort -u)
  if [[ "$_want" != "$_got" ]]; then
    err "the runner's \`--list\` SKIP $2 set differs from $1 as parsed here — runner:"
    err "  [$(tr '\n' ' ' <<< "$_got")] gate: [$(tr '\n' ' ' <<< "$_want")]. Fix the entry's shape."
    fails=$((fails + 1))
  fi
}
map_crosscheck PRIVILEGED_WHY privileged PRIVILEGED
map_crosscheck DEDICATED_JOB_WHY dedicated DEDICATED

# Manifest coherence: every row in the committed shard manifest must name an
# EXECUTABLE suite by its full repo-relative path (the set the runner's
# --enumerate emits — privileged basenames are derived but never tabled), with
# a leg inside 1..N of the matrix's own leg list. An off-set row is a balance
# wart the runner's hash fallback papers over — fail here so drift is
# surfaced, not silently absorbed. The `# n=` header must be the FIRST such
# line (the runner reads the first and degrades to positional on a mismatch —
# an earlier stale `# n=` satisfying a whole-file grep would hide exactly that
# degrade). Rows the runner rejects (duplicates, extra fields, non-integer or
# out-of-range legs) are rejected here too so the failure surfaces at the gate
# and not as four red legs.
MANIFEST="$REPO_ROOT/apps/web-platform/infra/suite-shard-legs.tsv"
if [[ -f "$MANIFEST" && -n "${LEG_N:-}" && "$LEG_BAD" -eq 0 ]]; then
  declare -A M_SEEN=()
  while IFS=$'\t' read -r mp mleg mrest; do
    case "$mp" in "" | "#"*) continue ;; esac
    if [[ -n "${PRIVILEGED[${mp##*/}]+x}" || -n "${DEDICATED[${mp##*/}]+x}" || -z "${TRACKED_REL[$mp]+x}" ]]; then
      err "suite-shard-legs.tsv assigns '$mp', which is not an executable infra"
      err "  suite on a leg (privileged, dedicated or untracked) — a stale/dead manifest row."
      err "  Regenerate: regenerate-shard-manifest.py --group infra --write"
      fails=$((fails + 1))
    elif [[ -n "$mrest" || ! "$mleg" =~ ^[0-9]+$ ]] || (( 10#$mleg < 1 || 10#$mleg > LEG_N )); then
      err "suite-shard-legs.tsv row for '$mp' is malformed ('$mleg' is not a leg"
      err "  in 1..$LEG_N or the row carries extra fields) — the runner exit-2s"
      err "  on this exact shape. Regenerate the manifest."
      fails=$((fails + 1))
    elif [[ -n "${M_SEEN[$mp]+x}" ]]; then
      err "suite-shard-legs.tsv assigns '$mp' twice — the runner exit-2s on a"
      err "  duplicate row. Regenerate the manifest."
      fails=$((fails + 1))
    fi
    M_SEEN[$mp]=1
  done < "$MANIFEST"
  # The runner reads the FIRST `# n=` line; match that read, not any member.
  _first_n=$(grep -m1 -E '^# n=[0-9]+$' "$MANIFEST" || true)
  if [[ "$_first_n" != "# n=${LEG_N}" ]]; then
    err "suite-shard-legs.tsv's first '# n=' header ('${_first_n:-none}') does not"
    err "  match the matrix's leg count ($LEG_N) — manifest and matrix have drifted."
    fails=$((fails + 1))
  fi
  unset _first_n
fi

# Durations-table coherence (#9232): apps/web-platform/infra/suite-durations.tsv
# is the committed duration source — CI regen writes it and the #8231 local
# scheduler re-packs from it offline. Same contract as the plugin-side lint:
# rows `label<TAB>ms<TAB>src` with src ∈ {measured,floor}, no duplicates, only
# leg-executable (tracked, non-privileged, non-dedicated) labels, and a label set equal to the
# sibling manifest's — a divergence means one consumer sees weight the other
# cannot place.
DURATIONS="$REPO_ROOT/apps/web-platform/infra/suite-durations.tsv"
if [[ -f "$MANIFEST" && -n "${LEG_N:-}" && "$LEG_BAD" -eq 0 ]]; then
  if [[ ! -f "$DURATIONS" ]]; then
    err "suite-durations.tsv absent at ${DURATIONS#$REPO_ROOT/} — the #8231"
    err "  local scheduler has no duration source. Regenerate:"
    err "  regenerate-shard-manifest.py --group infra --write"
    fails=$((fails + 1))
  else
    declare -A D_SEEN=()
    while IFS=$'\t' read -r dl dms dsrc drest; do
      case "$dl" in "" | "#"*) continue ;; esac
      if [[ -n "${PRIVILEGED[${dl##*/}]+x}" || -n "${DEDICATED[${dl##*/}]+x}" || -z "${TRACKED_REL[$dl]+x}" ]]; then
        err "suite-durations.tsv weights '$dl', which is not an executable infra"
        err "  suite on a leg (privileged, dedicated or untracked) — a stale/dead durations row."
        err "  Regenerate: regenerate-shard-manifest.py --group infra --write"
        fails=$((fails + 1))
      elif [[ -n "$drest" || ! "$dms" =~ ^[0-9]+$ || ( "$dsrc" != "measured" && "$dsrc" != "floor" && "$dsrc" != "estimate" ) ]]; then
        err "suite-durations.tsv row for '$dl' is malformed — expected"
        err "  'label<TAB>ms<TAB>src' with src in {measured,floor,estimate}."
        fails=$((fails + 1))
      elif [[ -n "${D_SEEN[$dl]+x}" ]]; then
        err "suite-durations.tsv weights '$dl' twice — a duplicate row."
        fails=$((fails + 1))
      fi
      D_SEEN[$dl]=1
    done < "$DURATIONS"
    # Label-set parity with the sibling manifest: either direction of
    # divergence leaves a consumer without its counterpart.
    _dur_keys=$(grep -vE '^[[:space:]]*(#|$)' "$DURATIONS" | cut -f1 | LC_ALL=C sort -u || true)
    _mf_keys=$(grep -vE '^[[:space:]]*(#|$)' "$MANIFEST" | cut -f1 | LC_ALL=C sort -u || true)
    if [[ "$_dur_keys" != "$_mf_keys" ]]; then
      err "suite-durations.tsv and suite-shard-legs.tsv cover different label"
      err "  sets — a label has weight in one and no placement in the other."
      err "  Regenerate: regenerate-shard-manifest.py --group infra --write"
      fails=$((fails + 1))
    fi
    unset _dur_keys _mf_keys
  fi
fi

# Iteration order pinned for diff-comparable logs (assoc traversal is
# hash-order; the runner pins LC_ALL=C for the same reason).
# Trailing ` # …` comments dropped (full-line ones already are): a `sudo bash <path>  # note`
# line is still the bare invocation, and a comment can never be one.
FIXED_NC=$(sed -E 's/[[:space:]]+#.*$//' <<< "$FIXED_RAW")
while IFS= read -r base; do
  [[ -n "$base" ]] || continue
  if [[ -z "${TRACKED[$base]+x}" ]]; then
    err "PRIVILEGED_WHY in ${RUNNER_REL} lists '$base', which is not a tracked infra"
    err "  suite — a stale exclusion licenses a gap that is no longer real. Remove it."
    fails=$((fails + 1))
    continue
  fi
  # The exclusion waives the runner, never the invocation: it must be `sudo bash`ed
  # inside deploy-script-tests-fixed, as a WHOLE command line — `run: sudo bash <path>`, or
  # a `run: |` line that is only `sudo bash <path>` (the sudo steps carry setup lines). A
  # mention is not an invocation: `echo sudo bash <path>` and `sudo bash <path> || true`
  # used to satisfy this (#12941 review round 2, rows P1/P2). The step is then selected by
  # that same anchored line, never by a looser pattern a decoy line could match first.
  base_re="${base//./[.]}"
  priv_re="sudo[[:space:]]+bash[[:space:]]+${INFRA_PREFIX}/([A-Za-z0-9._-]+/)*${base_re}"
  if ! grep -qE "^[[:space:]]+(run:[[:space:]]+)?${priv_re}[[:space:]]*$" <<< "$FIXED_NC"; then
    err "$base is PRIVILEGED (excluded from the runner, needs root) but is NOT"
    err "  invoked by a bare \`sudo bash <path>\` command line in the \`$FIXED_JOB\` job — so it"
    err "  runs in NO job. Either restore that step there, or delete it from PRIVILEGED_WHY"
    err "  and let the legs run it unprivileged (only if it no longer needs root)."
    fails=$((fails + 1))
  else
    # An unmasked invocation is what "runs" means — a `continue-on-error:` or `if:` on the
    # sudo step, a `shell:` override or a `set +e` before it re-masks the coverage.
    _prec="(^|\n)[[:space:]]*(run:[[:space:]]+)?${priv_re}[[:space:]]*(\n|$)"
    mask_check "$FIXED_NC" "$_prec" "the \`$FIXED_JOB\` sudo step for $base"
    _prow=$(awk -v RS='      - ' -v pat="$_prec" '$0 ~ pat {print; exit}' <<< "$FIXED_NC")
    if grep -qE '^[[:space:]]+shell:|set[[:space:]]+\+e' <<< "$_prow"; then
      err "the \`$FIXED_JOB\` sudo step for $base masks its exit (\`shell:\` or \`set +e\`)."
      fails=$((fails + 1))
    fi
    # A single-line `run: sudo bash <path>` followed by a DEEPER-indented line is a YAML
    # plain-scalar continuation: `    || true` on the next line folds into the command.
    if awk -v pat="^[[:space:]]+run:[[:space:]]+${priv_re}[[:space:]]*$" '
         hit { n = match($0, /[^ ]/); if (n > ind && $0 !~ /^[[:space:]]*$/) { bad = 1 } ; hit = 0 }
         $0 ~ pat { hit = 1; ind = match($0, /run:/) }
         END { exit bad ? 0 : 1 }' <<< "$FIXED_NC"; then
      err "the \`$FIXED_JOB\` sudo step for $base continues its single-line \`run:\` onto the"
      err "  next line (a YAML plain-scalar continuation folds e.g. \`|| true\` into the command)."
      fails=$((fails + 1))
    fi
  fi
done < <(printf '%s\n' "${!PRIVILEGED[@]}" | LC_ALL=C sort)
unset base_re priv_re _prec _prow

# ── Arm 5: the dedicated set — derived from the RUNNER, invoked in its own job ─
# Contract: header item 5. The job is held to an ALLOWLIST (every key, step kind, `with:` key,
# `if:` value and `${{ }}` expression it may contain is enumerated below), because the
# round-1 denylist kept losing to sibling spellings (#12941 review round 2: `shell: true {0}`,
# a `$GITHUB_ENV` pre-step, `toJson(secrets)`, a decoy step, `bash -x`, a composite action…).
# Everything is read comment-stripped: full-line comments, then trailing ` # …` (YAML's own
# plain-scalar comment rule), so text written only in a comment never satisfies a check.
WF_NC=$(grep -vE '^[[:space:]]*#' "$WF" | sed -E 's/[[:space:]]+#.*$//' || true)
# The workflow-level `env:` block in ANY style — its header line is kept, so a flow mapping
# (`env: { CI: '' }`) is read too — inherited by every job.
WF_ENV_RAW=$(awk '/^env:/ { inenv = 1; print; next } inenv && /^[^[:space:]#]/ { inenv = 0 } inenv { print }' \
  "$WF" | grep -vE '^[[:space:]]*#' | sed -E 's/[[:space:]]+#.*$//' || true)
# The allowlists — exactly what the job and the env it inherits hold today. Extending one is a
# deliberate edit to this file, reviewed as such; nothing else may appear.
DED_WF_ENV_KEYS=" TERRAFORM_VERSION TF_VAR_terraform_version "
DED_EXPR_RE='\$\{\{[[:space:]]*(env\.terraform_version|runner\.temp)[[:space:]]*\}\}'   # lowercased text
# The structural allowlist, one violation per output line. Job keys: needs, if, runs-on,
# permissions, timeout-minutes, steps. Steps at indent 6 (`      - `), their keys at 8, `with:`
# children at 10 — any other indentation is refused, never re-read (records split on the
# 6-space step prefix, so a re-indented job would merge steps). Step kinds: actions/checkout
# (`with:` = exactly `persist-credentials: false`), hashicorp/setup-terraform, and
# actions/upload-artifact (the only step that may carry `if:`), each @<40-hex sha>; plus
# EXACTLY ONE `run:` step whose value is exactly `bash <path>` and which holds only name:/run:.
# POSIX awk only (CI's ubuntu awk is mawk): no intervals, no `delete arr`.
# shellcheck disable=SC2016  # awk program text; the backticks are message punctuation
DED_SHAPE_AWK='
function viol(m) { print m }
function norm(s) { s = tolower(s); gsub(/[[:space:]]/, "", s); sub(/^\$\{\{/, "", s); sub(/\}\}$/, "", s); return s }
function withok(a, k) {
  if (a == "actions/checkout") return k == "persist-credentials"
  if (a == "hashicorp/setup-terraform") return k == "terraform_version" || k == "terraform_wrapper"
  if (a == "actions/upload-artifact") return k == "name" || k == "path" || k == "if-no-files-found" || k == "retention-days"
  return 0
}
function skey(l,   k, v) {
  if (l !~ /^[A-Za-z_-]+:/) { viol("step " nstep " line `" l "` is not a plain `key: value` step key"); cur = "bad"; return }
  k = l; sub(/:.*/, "", k); v = l; sub(/^[A-Za-z_-]+:[[:space:]]*/, "", v)
  if (k in sk) viol("step " nstep " declares `" k ":` twice")
  sk[k] = 1; sv[k] = v; cur = k
}
function wkey(l,   k, v) {
  if (l !~ /^[A-Za-z_-]+:/) { viol("step " nstep " `with:` line `" l "` is not a plain `key: value`"); wcur = ""; return }
  k = l; sub(/:.*/, "", k); v = l; sub(/^[A-Za-z_-]+:[[:space:]]*/, "", v)
  if (k in wk) viol("step " nstep " `with:` declares `" k ":` twice")
  wk[k] = 1; wv[k] = v; wcur = k
}
function finish(   k, act, pin) {
  if (!nstep || fin[nstep]) return
  fin[nstep] = 1
  if (("uses" in sk) == ("run" in sk)) viol("step " nstep " has " (("uses" in sk) ? "both" : "neither") " of uses:/run:")
  else if ("run" in sk) {
    nrun++
    for (k in sk) if (k != "name" && k != "run") viol("step " nstep " (the run: step) carries `" k ":` — it may hold only name: and run:")
    if (sv["run"] != "bash " drel) viol("step " nstep " runs `" sv["run"] "`, not exactly `bash " drel "`")
  } else {
    act = sv["uses"]; sub(/@.*/, "", act); pin = sv["uses"]; sub(/^[^@]*@/, "", pin)
    if ((act != "actions/checkout" && act != "hashicorp/setup-terraform" && act != "actions/upload-artifact") \
        || pin !~ /^[0-9a-f]+$/ || length(pin) != 40)
      viol("step " nstep " uses `" sv["uses"] "` — allowed: actions/checkout, hashicorp/setup-terraform, actions/upload-artifact, each @<40-hex sha>")
    for (k in sk) if (k != "name" && k != "uses" && k != "with" && k != "if") viol("step " nstep " (" act ") carries `" k ":` — it may hold only name:, uses:, with: and if:")
    if ("if" in sk) {
      if (act != "actions/upload-artifact") viol("step " nstep " (" act ") carries `if:` — only the upload-artifact step may")
      else if (norm(sv["if"]) != "failure()||cancelled()") viol("step " nstep " `if: " sv["if"] "` is not allowlisted (failure() || cancelled())")
    }
    if (("with" in sk) && sv["with"] != "") viol("step " nstep " `with:` is not a block mapping")
    for (k in wk) if (!withok(act, k)) viol("step " nstep " (" act ") `with:` key `" k ":` is not allowlisted")
    if (act == "actions/checkout" && wv["persist-credentials"] != "false") viol("step " nstep " (actions/checkout) lacks `persist-credentials: false` as a direct with: child")
  }
  split("", sk); split("", sv); split("", wk); split("", wv); cur = ""; wcur = ""
}
/^[[:space:]]*$/ { next }
{
  match($0, /^ */); i = RLENGTH; l = substr($0, i + 1); sub(/[[:space:]]+$/, "", l)
  if (i == 4) {
    finish()
    if (l ~ /^- /) { viol("a step at indent 4 — steps sit at indent 6 (`      - `), their keys at 8"); sec = "bad"; next }
    k = l; sub(/:.*/, "", k); v = l; sub(/^[A-Za-z_-]+:[[:space:]]*/, "", v)
    if (l !~ /^[A-Za-z_-]+:/ || (k != "needs" && k != "if" && k != "runs-on" && k != "permissions" && k != "timeout-minutes" && k != "steps")) {
      viol("job key `" l "` is not allowlisted (needs, if, runs-on, permissions, timeout-minutes, steps)"); sec = "bad"; next
    }
    if (k in jseen) viol("job key `" k ":` is declared twice")
    jseen[k] = 1; sec = k
    if (k == "if" && norm(v) != "needs.detect-changes.outputs.pr_duplicate!=\047true\047") viol("job `if: " v "` is not allowlisted")
    if (k == "steps" && v != "") viol("`steps:` is not a block sequence")
    next
  }
  if (sec == "bad") next
  if (sec == "permissions" && i == 6) next
  if (sec == "needs" && i == 6 && l ~ /^- [A-Za-z0-9_-]+$/) next
  if (sec == "steps" && i == 6 && l ~ /^- /) { finish(); nstep++; sub(/^- +/, "", l); skey(l); next }
  if (sec == "steps" && i == 8 && nstep && l !~ /^- /) { skey(l); next }
  if (sec == "steps" && i == 10 && cur == "with") { wkey(l); next }
  if (sec == "steps" && i > 10 && cur == "with" && wcur != "" && wv[wcur] ~ /^[|>][-+0-9]*$/) next
  viol("line at a non-canonical indentation or position (indent " i ", under `" sec ":`): `" l "`")
}
END { finish(); if (nrun != 1) viol("the job has " (nrun + 0) " run: step(s) (expected exactly 1, the bare invocation)") }
'
while IFS= read -r base; do
  [[ -n "$base" ]] || continue
  if [[ -z "${TRACKED[$base]+x}" ]]; then
    err "DEDICATED_JOB_WHY in ${RUNNER_REL} lists '$base', which is not a tracked infra"
    err "  suite — a stale exclusion licenses a gap that is no longer real. Remove it."
    fails=$((fails + 1))
    continue
  fi
  djob="${DEDICATED_JOB_OF[$base]:-}"
  [[ -n "$djob" ]] || continue   # reported above (no owning job named)
  drel=""
  for rel in "${SUITES[@]}"; do
    if [[ "${rel##*/}" == "$base" ]]; then drel="$rel"; break; fi
  done
  stem="${base%.test.sh}"
  DJOB_RAW=$(slice_job "$djob" | sed -E 's/[[:space:]]+#.*$//')
  if [[ -z "${DJOB_RAW//[[:space:]]/}" ]]; then
    err "$base is DEDICATED to job \`$djob\`, but $WF_REL has no such job — the suite"
    err "  is never executed by the runner and runs in NO CI job."
    fails=$((fails + 1))
    continue
  fi
  drel_re="${drel//./[.]}"
  # The invocation: the job's one mention of the suite is its whole `run:` value.
  anchor_re="^[[:space:]]+(- )?run: bash ${drel_re}[[:space:]]*$"
  _inv_n=$(grep -cF -- "$stem" <<< "$DJOB_RAW" || true)
  if (( _inv_n == 0 )); then
    err "$base is DEDICATED (never executed by the runner) but is NOT \`bash $drel\`-invoked"
    err "  in the \`$djob\` job — so it runs in NO CI job. Restore that step, or delete the"
    err "  DEDICATED_JOB_WHY entry and let the legs run it."
    fails=$((fails + 1))
    continue
  fi
  _anc_n=$(grep -cE "$anchor_re" <<< "$DJOB_RAW" || true)
  if (( _inv_n != 1 || _anc_n != 1 )); then
    err "the \`$djob\` job mentions \`$stem\` on ${_inv_n} line(s), and none or more than one"
    err "  is a bare \`run: bash $drel\` step — an echo, a wrapper or a second copy is not"
    err "  the one unmasked invocation this gate certifies."
    fails=$((fails + 1))
  fi
  # The step is selected by THAT anchor, never by a looser pattern a decoy line matches first.
  mask_check "$DJOB_RAW" "(^|\n)[[:space:]]*run: bash ${drel_re}[[:space:]]*(\n|$)" "the \`$djob\` step for $base"

  # SINGLE MENTION across every workflow and local action (CTO Q25): the suite's stem appears on
  # exactly ONE comment-stripped line of .github/workflows/** and .github/actions/** — the step
  # above. Matching the stem, not a `bash <path>` spelling, covers `./<path>`, a bare path,
  # `bash -x`, quotes, `${{ github.workspace }}/<path>`, `cd … && bash <basename>` and composite
  # actions alike. Trailing comments are NOT stripped here: ` #` inside a quoted string is not a
  # comment, so stripping could hide a real invocation, and a mention in a comment fails closed.
  _mentions=$(for d in "$REPO_ROOT/.github/workflows" "$REPO_ROOT/.github/actions"; do
      [[ -d "$d" ]] || continue
      find "$d" -type f | LC_ALL=C sort | while IFS= read -r f; do
        grep -vE '^[[:space:]]*#' "$f" | grep -F -- "$stem" | sed "s|^|${f#"$REPO_ROOT"/}: |" || true
      done
    done)
  _all_n=$(grep -c . <<< "$_mentions" || true)
  if (( _all_n != 1 )); then
    err "\`$stem\` is mentioned on ${_all_n} comment-stripped line(s) across .github/workflows and"
    err "  .github/actions (expected exactly 1, the \`$djob\` step): $(head -3 <<< "$_mentions" | tr '\n' '|')"
    err "  — any other mention can run it outside the job whose posture this gate checks."
    fails=$((fails + 1))
  fi

  # The structural allowlist (above).
  while IFS= read -r _v; do
    [[ -n "$_v" ]] || continue
    err "the \`$djob\` job is outside its allowlist: $_v"
    fails=$((fails + 1))
  done < <(awk -v drel="$drel" "$DED_SHAPE_AWK" <<< "$DJOB_RAW")
  # File-wide refusals, named so the message says what to remove (the allowlist above refuses
  # them too, by position). Each one re-routes or skips the suite while the step stays bare:
  # `shell: true {0}` runs /usr/bin/true, `defaults:` sets that for every step, `env:` reaches
  # the suite's CI refusals and BRH_* knobs, `working-directory:` moves the relative path,
  # `$GITHUB_ENV`/`$GITHUB_PATH` let an earlier step set env or shim `bash`.
  _refused=$(grep -oE "(^|[[:space:]{,])[\"']?(shell|defaults|env|continue-on-error|working-directory)[\"']?[[:space:]]*:" \
      <<< "$DJOB_RAW" | sed -E "s/^[[:space:]{,]*[\"']?//; s/[\"']?[[:space:]]*:\$/:/" | LC_ALL=C sort -u | tr '\n' ' ' || true)
  if [[ -n "$_refused" ]]; then
    err "the \`$djob\` job carries refused key(s): ${_refused% } — the job needs none of them."
    fails=$((fails + 1))
  fi
  _ghfile=$(grep -oiE 'GITHUB_(ENV|PATH)' <<< "$DJOB_RAW" | LC_ALL=C sort -u | tr '\n' ' ' || true)
  if [[ -n "$_ghfile" ]]; then
    err "the \`$djob\` job references ${_ghfile% } — an earlier step could set the suite's env"
    err "  or put a \`bash\` shim first on PATH for the step this gate certifies."
    fails=$((fails + 1))
  fi
  if grep -qE "^[\"']?defaults[\"']?[[:space:]]*:" <<< "$WF_NC"; then
    err "$WF_REL declares a workflow-level defaults: block — it applies to the \`$djob\` job"
    err "  (\`run: shell: true {0}\` would run no suite); declare defaults per job instead."
    fails=$((fails + 1))
  fi
  # A JOB-level `continue-on-error:` lets a failed job read as success to `needs:` (G3).
  if grep -qE '^    continue-on-error:' <<< "$DJOB_RAW"; then
    err "the \`$djob\` job carries a job-level \`continue-on-error:\` — the aggregator would"
    err "  read a red rehearsal as success."
    fails=$((fails + 1))
  fi

  # The job's own posture (#12941 Guard 2 row 8): a hosted runner, no secret, read-only.
  # The suite boots PRIVILEGED containers, so whatever the job holds, they can reach.
  if ! grep -qE '^    runs-on:[[:space:]]*ubuntu-[0-9]+\.[0-9]+[[:space:]]*$' <<< "$DJOB_RAW"; then
    err "the \`$djob\` job does not run on a pinned GitHub-hosted ubuntu-NN.NN runner —"
    err "  privileged containers on a self-hosted or shared runner reach that host."
    fails=$((fails + 1))
  fi
  # The workflow-level `env:` block reaches every job, so it is read with the job (G4/G5/G7/G8).
  # Expression contexts and function names are case-insensitive: read lowercased.
  _posture="$DJOB_RAW"$'\n'"$WF_ENV_RAW"
  _posture_lc=$(tr '[:upper:]' '[:lower:]' <<< "$_posture")
  if grep -qE '(^|[^a-z0-9_-])secrets([^a-z0-9_-]|$)|github\.token|github[[:space:]]*\[|tojson\([[:space:]]*github[[:space:]]*\)' \
       <<< "$_posture_lc"; then
    err "the \`$djob\` job (or the workflow env) references a credential (the \`secrets\` context in"
    err "  any spelling, \`github.token\`, \`github[\`, \`toJSON(github)\`; case-insensitive) — the rehearsal"
    err "  needs none, and anything bound in a job that boots privileged containers is readable from them."
    fails=$((fails + 1))
  fi
  _expr_left=$(sed -E "s/${DED_EXPR_RE}//g" <<< "$_posture_lc" | grep -oE '\$\{\{[^}]*(\}\})?' | head -3 | tr '\n' ' ' || true)
  if [[ -n "$_expr_left" ]]; then
    err "the \`$djob\` job (or the workflow env) holds \`\${{ }}\` expression(s) outside its allowlist"
    err "  (env.TERRAFORM_VERSION, runner.temp): ${_expr_left% }"
    fails=$((fails + 1))
  fi
  # `CI` keys every one of the suite's CI refusals; `BRH_*` are its narrowing knobs (G7/G8) —
  # block, flow (`{ CI: '' }`) or quoted (`"CI":`) keys alike.
  _knob=$(grep -oE "(^|[[:space:]{,])[\"']?(CI|GITHUB_ACTIONS|BRH_[A-Za-z0-9_]+)[\"']?[[:space:]]*:" <<< "$_posture" \
    | sed -E "s/^[[:space:]{,]*[\"']?//; s/[\"']?[[:space:]]*:\$//" | LC_ALL=C sort -u | tr '\n' ' ' || true)
  if [[ -n "$_knob" ]]; then
    err "the \`$djob\` job (or the workflow env) sets ${_knob% } — CI/GITHUB_ACTIONS turn the"
    err "  suite's CI refusals off and BRH_* narrow it; the job must run it as CI hands it over."
    fails=$((fails + 1))
  fi
  # The inherited workflow env is held to its key allowlist, block style, unquoted keys
  # (BASH_ENV, PATH or a quoted key would reach the suite with no knob name to refuse).
  if [[ -n "${WF_ENV_RAW//[[:space:]]/}" ]]; then
    _wfe_bad=$(awk -v keys="$DED_WF_ENV_KEYS" '
      NR == 1 { if ($0 !~ /^env:[[:space:]]*$/) print "header `" $0 "`"; next }
      /^[[:space:]]*$/ { next }
      $0 !~ /^  [A-Za-z_][A-Za-z0-9_]*:/ { print "line `" $0 "`"; next }
      { k = $0; sub(/^  /, "", k); sub(/:.*/, "", k); if (index(keys, " " k " ") == 0) print "key " k }
    ' <<< "$WF_ENV_RAW" | tr '\n' ';')
    if [[ -n "$_wfe_bad" ]]; then
      err "the workflow-level env the \`$djob\` job inherits is outside its allowlist (block style,"
      err "  keys:${DED_WF_ENV_KEYS% }): ${_wfe_bad%;} — set job-specific env on the job that needs it."
      fails=$((fails + 1))
    fi
  fi
  _perm=$(awk '
    /^    permissions:[[:space:]]*$/ { inp = 1; next }
    /^    permissions:/ { print "INLINE"; next }
    inp && /^      [A-Za-z-]+:/ { gsub(/[[:space:]]+/, ""); print; next }
    inp { inp = 0 }
  ' <<< "$DJOB_RAW" | LC_ALL=C sort)
  if [[ "$_perm" != "contents:read" ]]; then
    err "the \`$djob\` job's permissions are not exactly \`contents: read\` (got:"
    err "  '$(tr '\n' ' ' <<< "${_perm:-<none — inherits the workflow block>}")') — declare it on the job, read-only."
    fails=$((fails + 1))
  fi
  # Per checkout STEP, not job-wide: one compliant checkout must not cover a second (G6), and
  # the key counts only as a DIRECT `with:` child (indent 10) — the same text inside a block
  # scalar is not the key (H23). Records split on the canonical step prefix the allowlist pins.
  _ck_open=$(printf '%s\n' "$DJOB_RAW" | awk -v RS='      - ' '
    /uses:[[:space:]]*actions\/checkout@/ && !/\n          persist-credentials:[[:space:]]*false[[:space:]]*(\n|$)/ { n++ }
    END { print n + 0 }')
  if (( _ck_open > 0 )); then
    err "the \`$djob\` job has ${_ck_open} actions/checkout step(s) without \`persist-credentials: false\`"
    err "  — the token would sit in .git/config on a disk its privileged containers can read."
    fails=$((fails + 1))
  fi
  unset _perm _all_n _inv_n _anc_n _posture _posture_lc _knob _ck_open _mentions _refused _ghfile _expr_left _wfe_bad _v
done < <(printf '%s\n' "${!DEDICATED[@]}" | LC_ALL=C sort)
unset drel drel_re anchor_re djob DJOB_RAW stem WF_NC

# ── Arm 3b: test/infra suites must be invoked SOMEWHERE ──────────────────────
# apps/web-platform/test/infra/*.test.sh lives OUTSIDE the runner's glob and is
# not uniformly registered in this workflow — vector-pii-scrub runs in another
# workflow entirely. The invariant is the weaker one this domain actually has:
# every tracked suite there is `bash`-invoked by at least one workflow file.
# (Per-suite home-job scoping stays a lint-orphan-test-suites.sh concern — it
# owns the six-surface census; duplicating its bookkeeping here is the drift
# this rewrite exists to remove.)
TESTINFRA_PREFIX="apps/web-platform/test/infra"
WF_STRIPPED_ALL=$(for w in "$REPO_ROOT"/.github/workflows/*.yml; do
    grep -vE '^[[:space:]]*#' "$w"
  done)
while IFS= read -r rel; do
  [[ -n "$rel" ]] || continue
  # NOTE: herestrings, not `printf | grep -q` — under pipefail, grep -q exits on
  # first match and printf dies SIGPIPE (rc=141), which reads as "not found" here.
  # Measured: all six suites red-failed on a 1.4 MB stream.
  rel_re="${rel//./[.]}"
  # ` bash ` alone: `sudo bash <rel>` already contains a word-bounded `bash`.
  if ! grep -qE "(^|[[:space:]])bash[[:space:]]+${rel_re}([[:space:]]|$)" <<< "$WF_STRIPPED_ALL"; then
    err "$rel is a tracked ${TESTINFRA_PREFIX}/ suite invoked by NO workflow —"
    err "  the runner's glob does not reach that directory, so it runs nowhere."
    fails=$((fails + 1))
  fi
done < <(git -C "$REPO_ROOT" ls-tree -r --name-only HEAD -- "${TESTINFRA_PREFIX}/" \
  | grep -E '\.test\.sh$')

# ── Arm 4: the aggregator needs both legs and every dedicated job ─────────────
for need in "$JOB" "$FIXED_JOB" "${DEDICATED_JOBS[@]}"; do
  [[ -n "$need" ]] || continue
  # Membership, not substring: `deploy-script-tests` is a PREFIX of
  # `deploy-script-tests-fixed`, so a bare grep for the name is satisfied by the
  # sibling's entry — measured: dropping the matrix from needs: stayed green.
  # The job name must be followed by `]`, `,`, space, or end-of-line to count.
  # (`[] ,]` — a `]` first inside a bracket expression is a literal, not a close.)
  # The block scan covers BOTH YAML forms — `needs: [a, b]` and the list form
  # `needs:\n  - a\n  - b` (a bare `needs:`-line grep would miss the second).
  # Boundary = "not a job-name char" — `[`, space, `-`-bullet, `]`, `,` all
  # qualify, while a longer name containing the needle does not.
  if ! grep -A3 -E '^[[:space:]]+needs:' <<< "$DONE_RAW" \
       | grep -cE >/dev/null "(^|[^a-zA-Z0-9_-])${need}([^a-zA-Z0-9_-]|$)"; then
    err "\`$DONE_JOB\` does not list \`$need\` in its needs: — a leg can go red or"
    err "  be cancelled without the aggregator ever seeing it."
    fails=$((fails + 1))
  fi
done
if ! grep -qE 'if: always\(\)' <<< "$DONE_RAW"; then
  err "\`$DONE_JOB\` lacks \`if: always()\` — default needs: semantics render a"
  err "  cancelled/failed upstream as \`skipped\`, which some branch protection"
  err "  treats as success (fail-open)."
  fails=$((fails + 1))
fi

# The consumer side: notify-main-failure must read the AGGREGATE's result, not the
# matrix job's — a cancelled leg makes the matrix `cancelled`, and an alert
# condition pinned to the matrix's own result string silently restores the #8735
# blind spot (cancelled != failure under a `== "failure"` test).
NOTIFY_RAW=$(awk -v j="  notify-main-failure:" '
  $0 == j {injob=1; print; next}
  injob && /^  [a-zA-Z0-9_-]+:/ {exit}
  injob {print}
' "$WF" | grep -vE '^[[:space:]]*#')
if [[ -z "$NOTIFY_RAW" ]]; then
  err "could not slice the \`notify-main-failure\` job out of $WF_REL"
  fails=$((fails + 1))
elif ! grep -qE "needs\.deploy-script-tests-done\.result" <<< "$NOTIFY_RAW"; then
  err "\`notify-main-failure\` does not read \`needs.$DONE_JOB.result\` — a"
  err "  cancelled leg must reach the push-failure alert path via the aggregator."
  fails=$((fails + 1))
# The predicate's SHAPE, not just the token's presence: `!= 'success'` is the
# only reading that covers cancelled. `== 'failure'` contains the same token
# and silently re-blinds the #8735 class.
elif ! grep -qE "needs\.deploy-script-tests-done\.result[[:space:]]*!=[[:space:]]*'success'" <<< "$NOTIFY_RAW"; then
  err "\`notify-main-failure\` reads needs.$DONE_JOB.result with a predicate"
  err "  that is not \`!= 'success'\` — cancelled legs must alert, not just failures."
  fails=$((fails + 1))
fi

if (( fails > 0 )); then
  echo "infra suite registration: $fails failure(s)" >&2
  exit 1
fi

echo "infra suite registration: ${#SUITES[@]} suites covered by the ${JOB} matrix" \
     "(${#PRIVILEGED[@]} privileged -> sudo in ${FIXED_JOB};" \
     "${#DEDICATED[@]} dedicated -> ${DEDICATED_JOBS[*]:-no job}; presence under" \
     "${INFRA_PREFIX}/ IS registration)"
