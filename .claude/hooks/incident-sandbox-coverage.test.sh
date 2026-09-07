#!/usr/bin/env bash
# Drift guard: no test in this repository can append a row to a resolved incident-ledger root.
#
# WHY A GUARD AND NOT JUST THE FIX. Measured 2026-09-03: 12 suites wrote 396 rows into the
# operator's live `.claude/.rule-incidents.jsonl` in a single sweep -- 316 from
# iac-plan-write-guard.test.sh alone. That file is what `compound` Phase 1.5 reads as deviation
# evidence and what `rule-metrics-aggregate.sh` keys its counters on, so the fixtures were being
# scored as real rule violations.
#
# WHAT CHANGED IN #7853. The first revision could only see one directory (`.claude/hooks/`) and one
# spelling of protection (sourcing `lib/test-incident-sandbox.sh`). Three suites outside that
# directory kept leaking -- `plugins/soleur/test/gdpr-gate-self-test.test.sh`,
# `plugins/soleur/test/gdpr-gate.test.ts` and `test/pre-merge-rebase.test.ts` -- and the guard
# reported clean over all three. The assembly below is repo-wide and derived.
#
# ------------------------------------------------------------------------------------------------
# THE ASSEMBLY
#
# (a) THE EMITTER CHOKEPOINTS, ENUMERATED, WITH THEIR OWN FLOOR. There are two definitions of
#     `emit_incident`: the bash one in `lib/incidents.sh` and its Python mirror in
#     `security_reminder_hook.py`. That mirror is why the emitter set gets a floor of its own: an
#     earlier revision derived its population by FILENAME PAIRING (`*.test.sh` whose sibling `*.sh`
#     emits), the mirror is a `.py`, and so it fell outside the population, kept writing the real
#     ledger, AND was invisible to the guard -- which used the same enumeration. A floor that only
#     counts members cannot see that loss, so the floor asserts one `.sh` emitter AND one `.py`.
#
# (b) THE POPULATION, IN TWO STRUCTURAL HOPS, FROM INVOCATION SHAPES -- NOT NAME MENTIONS.
#       hop 1: every executable that CALLS `emit_incident` (call shape: the identifier in command
#              position followed by an argument, or a Python call). Not "mentions the name".
#       hop 2: every test file that names a hop-1 member INSIDE A QUOTED PATH LITERAL ON A
#              NON-COMMENT LINE -- the shape a spawn target has in bash, TS and Python alike.
#     Each hop carries its own non-empty floor, because a derivation that silently returns nothing
#     leaves every check downstream of it vacuously green.
#
#     WHY NOT A NAME MENTION. Because a name-mention derivation SELF-INCLUDES: this file discusses
#     `security_reminder_hook.py`, `context-reviewed-gate.sh` and `gdpr-gate.sh` by name in the
#     prose you are reading, so a plain grep for hop-1 basenames finds it and enters the guard into
#     its own population. Two cases below pin that distinction: one asserts this file is NOT in the
#     shape-derived population, and one asserts a name-mention control DOES find it -- so the first
#     assertion is measuring the derivation, not an accident.
#
#     KNOWN FALSE NEGATIVE OF HOP 2. It sees the spawn target only when the target's basename is
#     spelled in the source. A suite that composes the path at runtime (`"$HOOKS/$name.sh"` with
#     `name` from a loop or a glob), that reaches an emitter transitively through an intermediary
#     that is not itself a hop-1 member, or that dispatches through a wrapper taking the hook name
#     as data, is invisible to it. Hop 2 therefore UNDER-counts, and the outside set below is a
#     lower bound on the residual, never a ceiling on it. The compensating control is dynamic:
#     the redirect and non-vacuity cases at the end, plus the entry-point belts in
#     `scripts/test-all.sh` and `.github/scripts/test/run-all.sh`.
#     It also over-counts occasionally, in the harmless direction: a fixture path that happens to
#     share a basename with a hop-1 member (`.openhands/hooks/guardrails.sh`, a `touch`ed stub)
#     reads as a spawn. Those sit in the outside set and hold its ceiling slightly high.
#
# (c) THE FIVE CHOKEPOINTS, EACH VERIFIED INDIVIDUALLY. The export that makes a whole runtime safe
#     at once. One verdict per file plus a count, so removing the export from any one of them reds
#     twice.
#
# (d) THE OUTSIDE SET, PRINTED, WITH A RATCHETED CEILING. The emitter-reaching suites that no
#     chokepoint protects. This set is NOT empty and the guard does not pretend otherwise: `bun
#     test` resolves `bunfig.toml` from the INVOCATION cwd, so a run started from a third directory
#     loads no preload; `python3 -m unittest` loads no `conftest.py`; and a suite that spawns with
#     an explicit `env:` object does not inherit its runner's export at all. The honest form of that
#     residual is a counted, printed, ratcheted-downward set -- not a claim of total coverage.
#
# WHY PROTECTION IS NOT "MENTIONS INCIDENTS_REPO_ROOT" FOR SHELL. Every one of the 12 polluting
# suites already mentioned the variable. They set it inline on SOME hook invocations and missed
# others, and partial isolation is indistinguishable from full isolation to a grep for the NAME.
# Sourcing the helper is sufficient and unforgettable: it exports before any case runs.
# The inline spelling IS accepted for `.ts` and `.py` suites, because those runtimes cannot source
# a bash helper -- and for a suite that spawns with an explicit `env:` object it is the ONLY
# spelling that works, since such a spawn replaces the environment its runner set up. That is
# exactly `test/pre-merge-rebase.test.ts`: covered by the root bunfig preload and leaking anyway.
# So an explicit-env suite does not get to claim preload coverage; it must carry the root itself.
set -uo pipefail

HERE="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO="$(cd -P "$HERE/../.." && pwd -P)"
SELF="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/$(basename "${BASH_SOURCE[0]}")"
WORK="$(mktemp -d -t inc-cov-XXXXXX)" || { printf '[FATAL] mktemp failed\n' >&2; exit 1; }
trap 'rm -rf "$WORK"' EXIT

PASS=0; FAIL=0; CASES=0
pass() { PASS=$((PASS+1)); printf '  PASS: %s\n' "$1"; }
fail() { FAIL=$((FAIL+1)); printf '  FAIL: %s\n' "$1"; }
verdict() { CASES=$((CASES+1)); if [ "$1" = "0" ]; then pass "$2"; else fail "$2"; fi; }

# --- POSITIVE CONTROL --------------------------------------------------------
_p=$PASS; _f=$FAIL
pass 'self-check: pass() increments (expected)'
fail 'self-check: fail() increments (EXPECTED, not a defect)'
if [ $((PASS-_p)) -ne 1 ] || [ $((FAIL-_f)) -ne 1 ]; then
  printf '[FATAL] verdict helpers are not counting\n' >&2; exit 1
fi
PASS=$_p; FAIL=$_f

# Repo file list, env-independent (no `git ls-files`: an inherited GIT_DIR would answer for the
# wrong repository, which is the #7840 failure mode this tree just closed).
find "$REPO" \
  \( -name node_modules -o -name .git -o -name .worktrees -o -name knowledge-base \
     -o -name dist -o -name .next -o -name .venv -o -name coverage \) -prune -o \
  -type f -print 2>/dev/null | sed "s#^$REPO/##" | sort > "$WORK/all.txt"

# --- A. THE EMITTER CHOKEPOINTS ---------------------------------------------
# Definition shape, column-anchored: `emit_incident() {` in bash, `def emit_incident(` in Python.
# The indented `emit_incident() { :; }` degradation stubs in gdpr-gate.sh and
# kb-domain-allowlist-guard.sh are deliberately NOT emitters -- they write nothing.
grep -E '\.(sh|py)$' "$WORK/all.txt" | sed "s#^#$REPO/#" \
  | xargs -r grep -lE '^(emit_incident\(\)|def emit_incident\()' 2>/dev/null \
  | sed "s#^$REPO/##" | sort > "$WORK/emitters.txt"
n_emit=$(wc -l < "$WORK/emitters.txt")
printf '\nEMITTER CHOKEPOINTS (%d):\n' "$n_emit"; sed 's/^/  /' "$WORK/emitters.txt"

rc=1; [ "$n_emit" -ge 2 ] && rc=0
verdict "$rc" "the emitter set is enumerated and non-empty ($n_emit definitions, floor 2)"

n_sh=$(grep -c '\.sh$' "$WORK/emitters.txt" || true)
n_py=$(grep -c '\.py$' "$WORK/emitters.txt" || true)
rc=1; [ "$n_sh" -ge 1 ] && [ "$n_py" -ge 1 ] && rc=0
verdict "$rc" "both emitter spellings are present (${n_sh} bash, ${n_py} python -- the mirror a filename-paired enumeration lost)"

EMITTER_SH="$REPO/$(grep '\.sh$' "$WORK/emitters.txt" | head -1)"

# --- B. HOP 1: executables that CALL an emitter ------------------------------
# Call shape, not name mention: the identifier in command position (line start, or after a
# `;`/`&`/`|`/`}`/`&&`/`||`) followed by whitespace and an argument -- which excludes both the
# definition (`emit_incident() {`) and `command -v emit_incident`. Python: a call at statement
# position, which excludes `def emit_incident(`.
SH_CALL='(^|[;&|}]|&&|\|\|)[[:space:]]*emit_incident[[:space:]]+["'"'"'$A-Za-z0-9_-]'
PY_CALL='^[[:space:]]*emit_incident\('
{ grep -E '\.sh$' "$WORK/all.txt" | sed "s#^#$REPO/#" | xargs -r grep -lE "$SH_CALL" 2>/dev/null
  grep -E '\.py$' "$WORK/all.txt" | sed "s#^#$REPO/#" | xargs -r grep -lE "$PY_CALL" 2>/dev/null
} | sed "s#^$REPO/##" | grep -vE '(\.test\.|(^|/)test[-_]|_test\.)' | sort -u > "$WORK/hop1.txt"
n_hop1=$(wc -l < "$WORK/hop1.txt")

rc=1; [ "$n_hop1" -ge 20 ] && rc=0
verdict "$rc" "hop 1 (executables reaching an emitter) is non-empty: $n_hop1, floor 20"

# --- C. HOP 2: test files that SPAWN a hop-1 member --------------------------
BASES=$(sed 's#.*/##' "$WORK/hop1.txt" | sort -u | sed 's/\./\\./g' | paste -sd'|')
[ -n "$BASES" ] || { printf '[FATAL] hop 1 produced no basenames\n' >&2; exit 1; }

grep -E '(\.test\.(sh|ts|tsx|py)$|(^|/)test[-_][^/]*\.(sh|py|ts)$|(^|/)[^/]*_test\.(py|ts)$)' \
  "$WORK/all.txt" > "$WORK/cand.txt"
n_cand=$(wc -l < "$WORK/cand.txt")

# The quoted-path-literal-on-a-non-comment-line shape. The leading clause rejects `#`, `//`, `*`
# and `/*` comment lines -- which is the whole difference between this and a name mention.
SHAPE="^[[:space:]]*(([^#/*[:space:]]|/[^/*]).*)?[\"'](|[^\"']*/)($BASES)[\"']"
sed "s#^#$REPO/#" "$WORK/cand.txt" | xargs -r grep -lE "$SHAPE" 2>/dev/null \
  | sed "s#^$REPO/##" | sort > "$WORK/hop2.txt"
n_hop2=$(wc -l < "$WORK/hop2.txt")

rc=1; [ "$n_hop2" -ge 25 ] && rc=0
verdict "$rc" "hop 2 (suites spawning an emitter-reaching executable) is non-empty: $n_hop2 of $n_cand test files, floor 25"

# The self-inclusion pair. `SELF_REL` is derived, so nothing here spells this file's own name.
SELF_REL="${SELF#$REPO/}"
rc=0; grep -qxF "$SELF_REL" "$WORK/hop2.txt" && rc=1
verdict "$rc" "the shape derivation does not enter this guard into its own population"

# Non-vacuity of the case above: prove the name-mention derivation WOULD, so that assertion is
# measuring the shape and not a file that simply mentions nothing.
sed "s#^#$REPO/#" "$WORK/cand.txt" | xargs -r grep -lE "($BASES)" 2>/dev/null \
  | sed "s#^$REPO/##" | sort > "$WORK/hop2-mentions.txt"
rc=1; grep -qxF "$SELF_REL" "$WORK/hop2-mentions.txt" && rc=0
verdict "$rc" "a name-mention derivation DOES self-include (so the case above is not vacuous)"

# --- D. THE FIVE CHOKEPOINTS -------------------------------------------------
# The export that makes an entire runtime safe at once. Uniform predicate: a non-comment line that
# either assigns INCIDENTS_REPO_ROOT or calls the sandbox helper.
# Each entry is a place a runner ARMS the sandbox, paired with the predicate that proves the ARMING
# happens there -- not merely that the file mentions the mechanism.
#
# Three corrections, all measured:
#   * `tests/scripts/_git_fixture_env.py` was ABSENT while ADR-205 names it "the real chokepoint for
#     python3 -m unittest, which loads no conftest.py". Deleting its call left this section 5/5 green
#     while the arm scripts/test-all.sh actually drives wrote the real ledger.
#   * Both `bunfig.toml` preloads were absent, so section C's claim "removing the export from any one
#     of them reds twice" was false for 3 of the 5 documented chokepoints.
#   * `tests/conftest.py` was checked with a name match satisfied by its own `def` line and by an
#     assignment INSIDE the function body, so deleting the `pytest_configure` call still passed.
#
# A preload is a REGISTRATION, not an export, so it needs its own predicate; a single regex over a
# heterogeneous list is what let three entries be satisfied by the wrong thing.
CHOKEPOINT_FILES=(
  "plugins/soleur/test/lib/git-tripwire.ts"
  "apps/web-platform/test/global-setup-git-tripwire.ts"
  "plugins/soleur/test/test-helpers.sh"
  "tests/conftest.py"
  "tests/scripts/_git_fixture_env.py"
)
CHOKEPOINT_PREDS=(
  'ensureIncidentSandbox\(\)'
  'ensureIncidentSandbox\(\)'
  'export[[:space:]]+INCIDENTS_REPO_ROOT'
  '^[[:space:]]+ensure_incident_sandbox\(\)'
  '^ensure_incident_sandbox\(\)'
)
# The two preload registrations, checked by their own predicate.
PRELOAD_FILES=(
  "bunfig.toml"
  "plugins/soleur/bunfig.toml"
)
PRELOAD_RE='^preload[[:space:]]*=[[:space:]]*\[[^]]*git-tripwire\.ts'
EXPORT_RE='^[[:space:]]*(([^#/*[:space:]]|/[^/*]).*)?(export[[:space:]]+INCIDENTS_REPO_ROOT|INCIDENTS_REPO_ROOT["'"'"']?\]?[[:space:]]*[:=]|ensureIncidentSandbox\(\)|ensure_incident_sandbox\(\))'
ok_chokepoints=0
# Comment-stripped so an explanatory paragraph naming the mechanism cannot satisfy the check, and
# `grep -c` rather than `grep -q` because a `-q` on a pipe under pipefail exits non-zero on SIGPIPE
# even when it matched.
_strip_line_comments() { sed -E 's@[[:space:]]*(#|//).*$@@' "$1"; }
for i in "${!CHOKEPOINT_FILES[@]}"; do
  c="${CHOKEPOINT_FILES[$i]}"; pred="${CHOKEPOINT_PREDS[$i]}"
  rc=1
  if [ -f "$REPO/$c" ]; then
    hits="$(_strip_line_comments "$REPO/$c" | grep -cE "$pred" || true)"
    [[ "${hits:-0}" -gt 0 ]] && { rc=0; ok_chokepoints=$((ok_chokepoints+1)); }
  fi
  verdict "$rc" "chokepoint ARMS the sandbox: $c"
done
for c in "${PRELOAD_FILES[@]}"; do
  rc=1
  if [ -f "$REPO/$c" ]; then
    hits="$(_strip_line_comments "$REPO/$c" | grep -cE "$PRELOAD_RE" || true)"
    [[ "${hits:-0}" -gt 0 ]] && { rc=0; ok_chokepoints=$((ok_chokepoints+1)); }
  fi
  verdict "$rc" "preload registers the arming module: $c"
done
rc=1; [ "$ok_chokepoints" -eq "${#CHOKEPOINTS[@]}" ] && rc=0
verdict "$rc" "every chokepoint carries the export ($ok_chokepoints/${#CHOKEPOINTS[@]})"

# --- E. THE OUTSIDE SET ------------------------------------------------------
# Preload/globalSetup coverage is DERIVED: a config's declared entry file must itself reach
# ensureIncidentSandbox for that config's directory to count as a covered root.
COVERED_ROOTS=()
while IFS= read -r cfg; do
  d="$(dirname "$REPO/$cfg")"
  while IFS= read -r t; do
    [ -n "$t" ] || continue
    tp="$d/${t#./}"
    [ -f "$tp" ] || continue
    # Anchored on the CALL form and on comment-stripped content, not on the bare name: this file's
    # own EXPORT_RE two screens up already does that, and a `grep -q <name>` here is satisfied by
    # the import line, by a `//` comment naming it, or by the very sentence above explaining it
    # (cq-assert-anchor-not-bare-token). A preload that imports the helper and never calls it is
    # exactly the shape this arm must not credit.
    if _strip_line_comments "$tp" | grep -qE 'ensureIncidentSandbox[[:space:]]*\(' 2>/dev/null; then
      COVERED_ROOTS+=("$d"); break
    fi
  done < <(grep -hoE '(preload|globalSetup)[[:space:]]*[:=][[:space:]]*\[[^]]*\]' "$REPO/$cfg" 2>/dev/null \
           | grep -oE '"[^"]+"' | tr -d '"')
done < <(grep -E '(bunfig\.toml|vitest\.config\.ts)$' "$WORK/all.txt")

: > "$WORK/outside.txt"
while IFS= read -r f; do
  p="$REPO/$f"; why=""
  # C1 -- the bash suite helper.
  grep -qE '^[[:space:]]*(source|\.)[[:space:]]+[^#]*test-incident-sandbox\.sh' "$p" 2>/dev/null && why="sandbox-helper"
  # C2 -- the plugin shell chokepoint.
  [ -z "$why" ] && grep -qE '^[[:space:]]*(source|\.)[[:space:]]+[^#]*test-helpers\.sh' "$p" 2>/dev/null && why="test-helpers"
  # C3 -- the python chokepoint: the IMPORT is what runs it under `python3 -m unittest`.
  [ -z "$why" ] && grep -qE '^[[:space:]]*(from|import)[[:space:]].*_git_fixture_env' "$p" 2>/dev/null && why="git-fixture-env"
  # C5 -- the inline root. Checked BEFORE preload coverage because it is the stronger claim.
  [ -z "$why" ] && grep -qE "$EXPORT_RE" "$p" 2>/dev/null && why="inline-root"
  # C4 -- preload/globalSetup coverage, forfeited by an explicit-env spawn.
  if [ -z "$why" ]; then
    case "$f" in
      *.ts|*.tsx|*.py)
        if grep -qE '^[[:space:]]*(([^#/*[:space:]]|/[^/*]).*)?(^|[^A-Za-z0-9_])env[[:space:]]*[:=][^=]' "$p" 2>/dev/null; then
          why=""   # explicit-env spawn: the runner's export never reaches the child
        else
          for r in "${COVERED_ROOTS[@]}"; do case "$p" in "$r"/*) why="preload"; break;; esac; done
        fi ;;
    esac
  fi
  if [ -z "$why" ]; then printf '%s\n' "$f" >> "$WORK/outside.txt"; fi
done < "$WORK/hop2.txt"
n_out=$(wc -l < "$WORK/outside.txt")

printf '\nOUTSIDE SET -- emitter-reaching suites protected by no chokepoint (%d):\n' "$n_out"
sed 's/^/  /' "$WORK/outside.txt"
printf '\n'

# RATCHET. Lower this number when a member is converted; never raise it to make the guard pass.
# Measured 2026-09-07 at 4. One is a true positive -- `scan-workflow.test.sh` spawns
# `new-scheduled-cron-prefer-inngest.sh`, which emits, with no chokepoint anywhere in its path.
# The other three are the harmless over-count described in the header: a `touch`ed fixture stub, a
# static parity reader that never spawns its subject, and a same-basename script under
# `.openhands/`. They are LEFT IN rather than special-cased, because every carve-out is a place a
# real member can hide, and because a ceiling of 4 reds on the fifth member either way.
# Ratcheted 4 -> 3 when the one TRUE POSITIVE this guard found was fixed:
# apps/web-platform/infra/supabase-advisor/scan-workflow.test.sh piped fixture content through
# .claude/hooks/new-scheduled-cron-prefer-inngest.sh with no chokepoint on its path -- invoked
# directly by infra-validation.yml, no bun preload, no vitest globalSetup, no test-helpers.sh. It
# now sources the sandbox helper.
#
# The three remaining members are all OVER-COUNTS, verified individually rather than assumed:
#   scripts/test-jaccard-duplicates.sh        - a static parity reader, spawns nothing
#   tests/hooks/test_drop_sentinel_parity.sh  - a touched fixture stub, not the real emitter
#   tests/hooks/test_openhands_guardrails.sh  - drives .openhands/hooks/guardrails.sh, which
#                                               contains ZERO emit_incident references; it matched
#                                               only on a basename shared with the .claude/ hook
# They are deliberately NOT carved out. Every carve-out is a place a real member can hide, and a
# ceiling of 3 reds on the fourth either way.
OUTSIDE_CEILING=3
rc=1; [ "$n_out" -le "$OUTSIDE_CEILING" ] && rc=0
verdict "$rc" "the outside set has not grown ($n_out, ceiling $OUTSIDE_CEILING)"

# --- F. THE HOOK-SUITE BLANKET ----------------------------------------------
# Every `.claude/hooks/*.test.sh` sources the helper, whether or not hop 2 saw it spawn anything.
# The helper is inert for a suite that never emits, so requiring it of all of them costs nothing
# and has no blind spot. ZERO, not a baseline: the tree was taken to zero deliberately.
missing=""; population=0
for t in "$HERE"/*.test.sh; do
  [ "$t" = "$SELF" ] && continue
  population=$((population+1))
  # Anchored on an executable `source`/`.` line, matching section E's C1 predicate in this same
  # file. The previous bare-token grep was satisfied by a COMMENT: verified, a file containing only
  # `# we deliberately do not source test-incident-sandbox.sh here` passed the blanket that stands
  # between 45 hook suites and the operator's real ledger.
  _f_hits="$(grep -cE '^[[:space:]]*(source|\.)[[:space:]]+[^#]*test-incident-sandbox\.sh' "$t" || true)"
  [[ "${_f_hits:-0}" -gt 0 ]] || missing="${missing} $(basename "$t")"
done
rc=1; [ -z "$missing" ] && rc=0
verdict "$rc" "every hook suite sources the sandbox helper${missing:+ (missing:$missing)}"

rc=1; [ "$population" -ge 40 ] && rc=0
verdict "$rc" "the hook-suite enumeration found a real population ($population suites, floor 40)"

# --- G. THE REDIRECT ACTUALLY WORKS -----------------------------------------
REAL="$REPO/.claude/.rule-incidents.jsonl"
existed=0; before=0
if [ -f "$REAL" ]; then existed=1; before=$(wc -l < "$REAL"); fi
( # shellcheck source=/dev/null
  . "$HERE/lib/test-incident-sandbox.sh"
  # shellcheck source=/dev/null
  . "$EMITTER_SH" 2>/dev/null || exit 0
  emit_incident sandbox-probe warn "probe" "cmd" ) >/dev/null 2>&1
still=0; after=0
if [ -f "$REAL" ]; then still=1; after=$(wc -l < "$REAL"); fi
rc=1; [ "$before" = "$after" ] && [ "$existed" = "$still" ] && rc=0
verdict "$rc" "an emit under the helper leaves the resolved ledger untouched ($before -> $after rows, exists $existed -> $still)"

# --- H. NON-VACUITY: without the helper, the same emit DOES land -------------
SB="$WORK/sink"; mkdir -p "$SB/.claude"
( INCIDENTS_REPO_ROOT="$SB" ; export INCIDENTS_REPO_ROOT
  # shellcheck source=/dev/null
  . "$EMITTER_SH" 2>/dev/null || exit 0
  emit_incident sandbox-probe warn "probe" "cmd" ) >/dev/null 2>&1
n=$(wc -l < "$SB/.claude/.rule-incidents.jsonl" 2>/dev/null || echo 0)
rc=1; [ "$n" -ge 1 ] && rc=0
verdict "$rc" "the same emit DOES write when pointed at a sandbox (the case above is not vacuous)"

# --- I. AC7: THE HELPER FAILS LOUD ------------------------------------------
# A sandbox helper whose failure path is `return 0` does not degrade to a lesser sandbox -- it
# restores the operator's real ledger, silently, while every static check for the variable's name
# still reports clean. So the failure direction must be refusal.
mkdir -p "$WORK/stub"
printf '#!/bin/sh\nexit 1\n' > "$WORK/stub/mktemp"; chmod +x "$WORK/stub/mktemp"
out=$(PATH="$WORK/stub:$PATH" bash -c '
  unset INCIDENTS_REPO_ROOT
  . "$1" 2>&1
  printf "SURVIVED root=[%s]\n" "${INCIDENTS_REPO_ROOT-<unset>}"' _ "$HERE/lib/test-incident-sandbox.sh" 2>&1)
rc=1
case "$out" in
  *SURVIVED*) rc=1 ;;
  *FATAL*) rc=0 ;;
esac
verdict "$rc" "with mktemp failing the helper aborts loudly instead of restoring the real sink"

printf '\n'
MIN_CASES=19
if [ "$CASES" -lt "$MIN_CASES" ]; then
  printf '[FATAL] vacuity floor: %d cases executed, expected at least %d\n' "$CASES" "$MIN_CASES" >&2; exit 1
fi
if [ $((PASS+FAIL)) -ne "$CASES" ]; then
  printf '[FATAL] accounting: PASS+FAIL=%d but CASES=%d\n' "$((PASS+FAIL))" "$CASES" >&2; exit 1
fi
if [ "$FAIL" -gt 0 ]; then printf 'FAILED: %d/%d\n' "$FAIL" "$CASES"; exit 1; fi
printf 'OK: %d/%d\n' "$PASS" "$CASES"
