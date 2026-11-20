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
#      each be `sudo bash`-invoked inside `deploy-script-tests-fixed`. The exclusion
#      waives the RUNNER, never the invocation.
#   4. `deploy-script-tests-done` must exist and need both legs (and every dedicated
#      job, below) — it is the single verdict `notify-main-failure` reads.
#   5. The DEDICATED set (#12941: suites too slow for a k/N leg, which the runner drops
#      from every shard and from --enumerate but still runs unsharded) must each be
#      invoked, unmasked, by `bash <path>` in the job its DEDICATED_JOB_WHY value names
#      (`runs in the <job> job`); that job must run on a hosted runner with job-level
#      `permissions: contents: read` only, reference no `secrets.`, and check out with
#      `persist-credentials: false`; and main-health-monitor's `test-infra` leg must set
#      SOLEUR_INFRA_SKIP_DEDICATED=1. The shard/unsharded BEHAVIOUR of the drop is pinned
#      by apps/web-platform/infra/run-registered-suites.test.sh (T11k), which executes the
#      runner; this gate stays text-only.
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
# one level up. Each entry must cite a tracking issue, the same fail-closed discipline
# the old EXCLUSIONS array carried.
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
MHM_REL=".github/workflows/main-health-monitor.yml"
MHM="$REPO_ROOT/$MHM_REL"
MHM_INFRA_JOB="test-infra"
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
slice_job() {  # slice_job <job-name> [workflow-file, default $WF]
  awk -v job="  $1:" '
    $0 == job { injob = 1; next }
    injob && /^  [A-Za-z0-9_-]+:[[:space:]]*$/ { injob = 0 }
    injob { print }
  ' "${2:-$WF}" | grep -vE '^[[:space:]]*#' || true
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
RUNNER_RECORD=$(printf '%s\n' "$JOB_RAW" | awk -v RS='      - ' \
  '/run-registered-suites[.]sh/{print; exit}')
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
  rec=$(printf '%s\n' "$1" | awk -v RS='      - ' -v pat="$2" '$0 ~ pat {print; exit}')
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
while IFS= read -r base; do
  [[ -n "$base" ]] || continue
  if [[ -z "${TRACKED[$base]+x}" ]]; then
    err "PRIVILEGED_WHY in ${RUNNER_REL} lists '$base', which is not a tracked infra"
    err "  suite — a stale exclusion licenses a gap that is no longer real. Remove it."
    fails=$((fails + 1))
    continue
  fi
  # The exclusion waives the runner, never the invocation: it must be `sudo bash`ed
  # inside deploy-script-tests-fixed. Any shape inside that job counts (multi-line
  # `run: |` included — the sudo steps carry setup commands).
  base_re="${base//./[.]}"
  if ! grep -qE "(^|[[:space:]])sudo[[:space:]]+bash[[:space:]]+${INFRA_PREFIX}/([A-Za-z0-9._-]+/)*${base_re}([[:space:]]|$)" <<< "$FIXED_RAW"; then
    err "$base is PRIVILEGED (excluded from the runner, needs root) but is NOT"
    err "  sudo-invoked anywhere in the \`$FIXED_JOB\` job — so it runs in NO job."
    err "  Either restore its \`sudo bash\` step there, or delete it from PRIVILEGED_WHY"
    err "  and let the legs run it unprivileged (only if it no longer needs root)."
    fails=$((fails + 1))
  else
    # An unmasked invocation is what "runs" means — a `continue-on-error:` or
    # `if:` on the sudo step re-masks the coverage the invocation stands for.
    mask_check "$FIXED_RAW" "sudo[[:space:]]+bash[[:space:]]+${INFRA_PREFIX}/([A-Za-z0-9._-]+/)*${base_re}" \
      "the \`$FIXED_JOB\` sudo step for $base"
  fi
done < <(printf '%s\n' "${!PRIVILEGED[@]}" | LC_ALL=C sort)
unset base_re

# ── Arm 5: the dedicated set — derived from the RUNNER, invoked in its own job ─
# The exclusion waives the k/N legs, never the invocation: each DEDICATED_JOB_WHY entry
# must be `bash <full repo-relative path>`-invoked by a step of the job its value names,
# unmasked. Trailing ` # …` comments are stripped first, so an invocation written only
# in a comment never satisfies it (full-line comments are already gone in slice_job).
# A multi-line `run: |` block counts — the step may carry setup lines.
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
  DJOB_RAW=$(slice_job "$djob" | sed -E 's/[[:space:]]+#.*$//')
  if [[ -z "${DJOB_RAW//[[:space:]]/}" ]]; then
    err "$base is DEDICATED to job \`$djob\`, but $WF_REL has no such job — the suite"
    err "  is dropped from every leg and runs in NO CI job."
    fails=$((fails + 1))
    continue
  fi
  drel_re="${drel//./[.]}"
  inv_re="(^|[[:space:]])bash[[:space:]]+${drel_re}([[:space:]]|$)"
  if ! grep -qE "$inv_re" <<< "$DJOB_RAW"; then
    err "$base is DEDICATED (dropped from every k/N leg) but is NOT \`bash $drel\`-invoked"
    err "  in the \`$djob\` job — so it runs in NO CI job. Restore that step, or delete the"
    err "  DEDICATED_JOB_WHY entry and let the legs run it."
    fails=$((fails + 1))
    continue
  fi
  mask_check "$DJOB_RAW" "bash[[:space:]]+${drel_re}" "the \`$djob\` step for $base"

  # The job's own posture (#12941 Guard 2 row 9): a hosted runner, no secret, read-only.
  # The suite boots PRIVILEGED containers, so whatever the job holds, they can reach.
  if ! grep -qE '^    runs-on:[[:space:]]*ubuntu-[0-9]+\.[0-9]+[[:space:]]*$' <<< "$DJOB_RAW"; then
    err "the \`$djob\` job does not run on a pinned GitHub-hosted ubuntu-NN.NN runner —"
    err "  privileged containers on a self-hosted or shared runner reach that host."
    fails=$((fails + 1))
  fi
  if grep -qE 'secrets\.' <<< "$DJOB_RAW"; then
    err "the \`$djob\` job references \`secrets.\` — the rehearsal needs no credential, and"
    err "  anything bound in a job that boots privileged containers is readable from them."
    fails=$((fails + 1))
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
  if grep -qE 'uses:[[:space:]]*actions/checkout@' <<< "$DJOB_RAW" \
     && ! grep -qE '^[[:space:]]+persist-credentials:[[:space:]]*false[[:space:]]*$' <<< "$DJOB_RAW"; then
    err "the \`$djob\` job checks out without \`persist-credentials: false\` — the token"
    err "  would sit in .git/config on a disk its privileged containers can read."
    fails=$((fails + 1))
  fi
  unset _perm
done < <(printf '%s\n' "${!DEDICATED[@]}" | LC_ALL=C sort)
unset drel drel_re inv_re djob DJOB_RAW

# The monitor's unsharded infra leg must drop the dedicated set (CTO Q16: it runs at its
# step ceiling) — by the explicit marker on the step that runs the infra group.
if (( ${#DEDICATED[@]} > 0 )); then
  if [[ ! -f "$MHM" ]]; then
    err "$MHM_REL not found — cannot verify its \`$MHM_INFRA_JOB\` leg drops the dedicated suites."
    fails=$((fails + 1))
  else
    MHM_INFRA_RAW=$(slice_job "$MHM_INFRA_JOB" "$MHM" | sed -E 's/[[:space:]]+#.*$//')
    MHM_INFRA_STEP=$(printf '%s\n' "$MHM_INFRA_RAW" | awk -v RS='      - ' '/TEST_GROUP:[[:space:]]*infra/{print; exit}')
    if [[ -z "$MHM_INFRA_STEP" ]]; then
      err "could not find the \`TEST_GROUP: infra\` step in $MHM_REL's \`$MHM_INFRA_JOB\` job."
      fails=$((fails + 1))
    elif ! grep -qE "^[[:space:]]+SOLEUR_INFRA_SKIP_DEDICATED:[[:space:]]*(1|\"1\"|'1')[[:space:]]*$" <<< "$MHM_INFRA_STEP"; then
      err "$MHM_REL's \`$MHM_INFRA_JOB\` step does not set SOLEUR_INFRA_SKIP_DEDICATED=1 —"
      err "  the unsharded monitor run would boot the dedicated suites inside its step ceiling."
      fails=$((fails + 1))
    fi
  fi
fi

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
