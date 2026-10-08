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
#     share a basename with a hop-1 member (a `touch`ed stub under `tests/hooks/`, not the real
#     emitter) reads as a spawn. Those sit in the outside set and hold its ceiling slightly high.
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
# `ok_chokepoints` is incremented by BOTH loops above, so the total is the two arrays summed.
# This read `${#CHOKEPOINTS[@]}` — an array that is never defined anywhere in this file, left over
# from the rename to CHOKEPOINT_FILES/PRELOAD_FILES. Under `set -u` that expansion ABORTS the
# command, so `verdict` was never called: the assertion did not fail, it silently CEASED TO EXIST,
# while MIN_CASES below still read 22 because the floor was set after the arm was already broken.
# The error went to stderr, which is why local runs looked green.
_chokepoint_total=$(( ${#CHOKEPOINT_FILES[@]} + ${#PRELOAD_FILES[@]} ))
rc=1; [ "$ok_chokepoints" -eq "$_chokepoint_total" ] && rc=0
verdict "$rc" "every chokepoint carries the export ($ok_chokepoints/$_chokepoint_total)"

# --- D2. THE SCRATCH SESSION IS BOUND BEFORE THE INCIDENT SANDBOX (#9117) -------------------------
# A runner chokepoint that allocates the incident sandbox must bind its per-process scratch root
# FIRST. Reversed, `soleur-inc-*` lands in the shared TMPDIR base and escapes the root -- so the
# property is about the WINDOW (call order), not about the call merely existing. The population is
# DERIVED from the registry above (every CHOKEPOINT_FILES member), not a second hand-kept list.
#
# EVERY MEMBER MUST BE ANALYZABLE. An earlier revision dispatched on the extension and `continue`d on
# an unknown one, so a 6th `.mjs`/`.js` chokepoint that armed the sandbox with no scratch call was
# green. Now: `.ts/.mts/.cts/.js/.mjs/.cjs` and `.py` are analyzed; `.sh` is exempt here (a shell
# chokepoint cannot bind a per-process root -- ADR-129 -- its half is MARKER-AT-CREATION, below);
# anything else is a FAIL, as is a member that makes no statement-position sandbox call.
#
# A CALL is a statement-position line (`name()` first on its line, as `ensureScratchSession();` and
# `ensure_scratch_session()` are written at every chokepoint). A definition, an import list, a line
# or block comment and a docstring that merely mention the name never satisfy -- or reorder -- the
# check. The scratch call must also be LIVE: not under an `if (false)` / `if False` / `while (0)`
# header and not nested deeper than the sandbox call (a function that is never called, an `if` that
# never runs). The scan is a brace-depth (ts/js) or indentation (py) walk, deliberately cheap.
cat > "$WORK/d2.awk" <<'AWK'
# awk -v kind=ts|py -v scr=<name> -v inc=<name> -f d2.awk <file>
# prints "<name> <line> <depth> <dead>" for the FIRST statement-position call of each name.
function indent(s) { match(s, /^[ \t]*/); return RLENGTH }
function isdead(s) { return (s ~ /(^|[^A-Za-z0-9_])(if|elif|while)[ \t]*\(?[ \t]*(false|False|0|None)[ \t]*\)?[ \t]*[{:]?[ \t]*$/) }
function record(name, depth, dead) { if (!(name in seen)) { seen[name] = 1; printf "%s %d %d %d\n", name, NR, depth, dead } }
function anydead(   k) { for (k = 1; k <= sp; k++) if (sd[k]) return 1; return 0 }
BEGIN { depth = 0; sp = 0; inblk = 0; indoc = 0 }
{
  line = $0
  if (kind == "py") {
    t = line; n = gsub(/"""/, "", t)
    if (indoc) { if (n % 2 == 1) indoc = 0; next }
    if (n % 2 == 1) { indoc = 1; next }
    sub(/#.*$/, "", line)
    if (line ~ /^[ \t]*$/) next
    ind = indent(line)
    while (sp > 0 && sh[sp] >= ind) sp--
    if (line ~ ("^[ \t]*" scr "\\(\\)")) record(scr, ind, anydead())
    if (line ~ ("^[ \t]*" inc "\\(\\)")) record(inc, ind, anydead())
    if (line ~ /:[ \t]*$/) { sp++; sh[sp] = ind; sd[sp] = isdead(line) }
    next
  }
  if (inblk) { if (line ~ /\*\//) { sub(/^.*\*\//, "", line); inblk = 0 } else next }
  gsub(/"[^"]*"/, "\"\"", line); gsub(/\047[^\047]*\047/, "\047\047", line); gsub(/`[^`]*`/, "``", line)
  while (line ~ /\/\*.*\*\//) sub(/\/\*.*\*\//, "", line)
  if (line ~ /\/\*/) { sub(/\/\*.*$/, "", line); inblk = 1 }
  sub(/\/\/.*$/, "", line)
  if (line ~ ("^[ \t]*" scr "\\(\\)")) record(scr, depth, anydead())
  if (line ~ ("^[ \t]*" inc "\\(\\)")) record(inc, depth, anydead())
  dead = isdead(line)
  for (i = 1; i <= length(line); i++) {
    c = substr(line, i, 1)
    if (c == "{") { sp++; sd[sp] = dead; depth++ }
    else if (c == "}") { if (sp > 0) sp--; depth-- }
  }
}
AWK
# _d2_file <root> <rel> -> prints a detail string; rc 0 = ok, 1 = BAD (including "cannot analyze").
_d2_file() {
  local root="$1" c="$2" kind scr inc out sl sd sdead il id
  [ -f "$root/$c" ] || { printf 'file is absent'; return 1; }
  case "$c" in
    *.ts|*.mts|*.cts|*.js|*.mjs|*.cjs) kind=ts; scr=ensureScratchSession;  inc=ensureIncidentSandbox ;;
    *.py)                              kind=py; scr=ensure_scratch_session; inc=ensure_incident_sandbox ;;
    *.sh) printf 'shell chokepoint: marker-at-creation is asserted below'; return 0 ;;
    *)    printf 'cannot analyze the extension of %s -- add support or remove it from the registry' "$c"; return 1 ;;
  esac
  out="$(awk -v kind="$kind" -v scr="$scr" -v inc="$inc" -f "$WORK/d2.awk" "$root/$c")"
  il="$(printf '%s\n' "$out" | awk -v n="$inc" '$1==n {print $2}')"
  id="$(printf '%s\n' "$out" | awk -v n="$inc" '$1==n {print $3}')"
  sl="$(printf '%s\n' "$out" | awk -v n="$scr" '$1==n {print $2}')"
  sd="$(printf '%s\n' "$out" | awk -v n="$scr" '$1==n {print $3}')"
  sdead="$(printf '%s\n' "$out" | awk -v n="$scr" '$1==n {print $4}')"
  [ -n "$il" ] || { printf 'no statement-position %s() call -- the order cannot be checked' "$inc"; return 1; }
  [ -n "$sl" ] || { printf 'scratch call %s() ABSENT (sandbox at line %s)' "$scr" "$il"; return 1; }
  [ "$sdead" = 0 ] || { printf 'scratch call at line %s sits under a dead branch' "$sl"; return 1; }
  [ "$sl" -lt "$il" ] || { printf 'scratch line %s is not before sandbox line %s' "$sl" "$il"; return 1; }
  [ "$sd" -le "$id" ] || { printf 'scratch call (line %s) is nested deeper (%s) than the sandbox call (%s): it may never run' "$sl" "$sd" "$id"; return 1; }
  printf 'scratch line %s depth %s, sandbox line %s depth %s' "$sl" "$sd" "$il" "$id"
  return 0
}
order_checked=0; n_analyzable=0
for c in "${CHOKEPOINT_FILES[@]}"; do
  case "$c" in *.sh) continue ;; esac
  n_analyzable=$((n_analyzable+1))
  detail="$(_d2_file "$REPO" "$c")"; rc=$?
  [ "$rc" = 0 ] && order_checked=$((order_checked+1))
  verdict "$rc" "scratch session is bound BEFORE the incident sandbox, live and at statement level: $c ($detail)"
done
rc=1; [ "$order_checked" -ge 4 ] && [ "$order_checked" -eq "$n_analyzable" ] && rc=0
verdict "$rc" "the call-order check passed over EVERY analyzable chokepoint ($order_checked of $n_analyzable, floor 4) -- 0 checked is a failure"

# CONTROLS, on COPIES in a private dir (the tree under test is never edited). Each mutation must LAND
# (a copy identical to its source aborts the suite) and each must be reported BAD.
_d2_copy() { # <name> <rel> <sed-expr|""> -> prints the copy root; aborts when the mutation is a no-op
  local r="$WORK/d2c.$1"
  mkdir -p "$r/$(dirname "$2")"
  if [ -n "$3" ]; then sed -e "$3" "$REPO/$2" > "$r/$2"; else cp "$REPO/$2" "$r/$2"; fi
  if [ -n "$3" ] && cmp -s "$REPO/$2" "$r/$2"; then printf '[FATAL] D2 control %s: the mutation did not land\n' "$1" >&2; exit 1; fi
  printf '%s' "$r"
}
_d2_new() { # <name> <rel> <content> -> prints the copy root
  local r="$WORK/d2c.$1"
  mkdir -p "$r/$(dirname "$2")"; printf '%b' "$3" > "$r/$2"; printf '%s' "$r"
}
r="$(_d2_new mjs-bad scripts/sixth-chokepoint.mjs 'import { ensureIncidentSandbox } from "./x.mjs";\nensureIncidentSandbox();\n')"
_d2_file "$r" scripts/sixth-chokepoint.mjs >/dev/null; rc=$?
verdict "$([ "$rc" != 0 ] && echo 0 || echo 1)" "control: a 6th .mjs chokepoint that arms the sandbox WITHOUT the scratch call is rejected"
r="$(_d2_new mjs-ok scripts/sixth-chokepoint.mjs 'ensureScratchSession();\nensureIncidentSandbox();\n')"
_d2_file "$r" scripts/sixth-chokepoint.mjs >/dev/null; rc=$?
verdict "$rc" "control: the same .mjs chokepoint WITH the call first is accepted (the analyzer supports .mjs, so the case above is not vacuous)"
r="$(_d2_new rb scripts/sixth-chokepoint.rb 'ensure_incident_sandbox()\n')"
_d2_file "$r" scripts/sixth-chokepoint.rb >/dev/null; rc=$?
verdict "$([ "$rc" != 0 ] && echo 0 || echo 1)" "control: a chokepoint with an extension the analyzer cannot read is a FAIL, not a skip"
r="$(_d2_copy dead-ts apps/web-platform/test/global-setup-git-tripwire.ts 's/^  ensureScratchSession();$/  if (false) {\n    ensureScratchSession();\n  }/')"
_d2_file "$r" apps/web-platform/test/global-setup-git-tripwire.ts >/dev/null; rc=$?
verdict "$([ "$rc" != 0 ] && echo 0 || echo 1)" "control: ensureScratchSession() wrapped in an if (false) block is rejected"
r="$(_d2_copy dead-py tests/conftest.py 's/^    ensure_scratch_session()\(.*\)$/    if False:\n        ensure_scratch_session()/')"
_d2_file "$r" tests/conftest.py >/dev/null; rc=$?
verdict "$([ "$rc" != 0 ] && echo 0 || echo 1)" "control: ensure_scratch_session() under an if False: block is rejected"
r="$(_d2_copy never-ts plugins/soleur/test/lib/git-tripwire.ts 's/^ensureScratchSession();$/function never() {\n  ensureScratchSession();\n}/')"
_d2_file "$r" plugins/soleur/test/lib/git-tripwire.ts >/dev/null; rc=$?
verdict "$([ "$rc" != 0 ] && echo 0 || echo 1)" "control: the call moved into a function nothing calls (deeper than the sandbox call) is rejected"
r="$(_d2_copy blockcmt-ts plugins/soleur/test/lib/git-tripwire.ts 's/^ensureScratchSession();$/\/*\nensureScratchSession();\n*\//')"
_d2_file "$r" plugins/soleur/test/lib/git-tripwire.ts >/dev/null; rc=$?
verdict "$([ "$rc" != 0 ] && echo 0 || echo 1)" "control: the call inside a block comment is rejected"
r="$(_d2_copy reorder-py tests/scripts/_git_fixture_env.py 's/^ensure_scratch_session()$/ensure_scratch_session_xx()/')"
_d2_file "$r" tests/scripts/_git_fixture_env.py >/dev/null; rc=$?
verdict "$([ "$rc" != 0 ] && echo 0 || echo 1)" "control: a deleted/renamed scratch call in a python chokepoint is rejected"

# The shell chokepoints cannot bind a per-process root (ADR-129: no new EXIT trap in a sourced lib), so
# their half of the property is MARKER-AT-CREATION: the sandbox dir must declare an owner right after
# its mktemp, so a replaced trap (#8659) or a SIGKILL leaves a reaper-eligible dir, not residue.
# Asserted on BEHAVIOUR: source the helper under a private TMPDIR and require the marker file in the
# EXACT `soleur-inc-*` directory it created. (The earlier check -- the call appears after the mktemp --
# stayed green for `soleur_scratch_mark_owned "$d/.claude"`, i.e. the wrong directory.)
SH_CHOKE=()
for c in "${CHOKEPOINT_FILES[@]}"; do case "$c" in *.sh) SH_CHOKE+=("$c") ;; esac; done
SH_CHOKE+=(.claude/hooks/lib/test-incident-sandbox.sh)
_marker_probe() { # <root> <rel-helper> -> rc 0 when the dir the helper created carries a valid marker
  local root="$1" rel="$2" tb out
  tb="$(mktemp -d "$WORK/mp.XXXXXX")" || return 1
  out="$(env -u INCIDENTS_REPO_ROOT -u SOLEUR_TEST_INCIDENT_ROOT -u SOLEUR_SCRATCH_SESSION_ROOT \
           -u SOLEUR_SCRATCH_BASE -u SOLEUR_SCRATCH_OWNER_PID TMPDIR="$tb" \
         bash -c '. "$1" >/dev/null 2>&1 || exit 90
                  d="${INCIDENTS_REPO_ROOT:-}"
                  case "$d" in "$2"/soleur-inc-*) : ;; *) echo "WRONG-PLACE:$d"; exit 91 ;; esac
                  [ -f "$d/.soleur-owned" ] || { echo NO-MARKER; exit 92; }
                  grep -qE "^pid=[0-9]+$" "$d/.soleur-owned" && grep -qx "schema=1" "$d/.soleur-owned" \
                    && grep -qE "^ns=pid:\[[0-9]+\]$" "$d/.soleur-owned" || { echo BAD-MARKER; exit 93; }
                  echo MARKED' _ "$root/$rel" "$tb" 2>&1)"
  [ "$out" = "MARKED" ]
}
for c in "${SH_CHOKE[@]}"; do
  _mk="$(_strip_line_comments "$REPO/$c" | grep -nE 'mktemp.*soleur-inc-' | head -1 | cut -d: -f1)"
  _mo="$(_strip_line_comments "$REPO/$c" | grep -nE 'soleur_scratch_mark_owned' | head -1 | cut -d: -f1)"
  rc=1; [ -n "$_mk" ] && [ -n "$_mo" ] && [ "$_mo" -gt "$_mk" ] && rc=0
  verdict "$rc" "sandbox dir is marked owned right after its mktemp: $c (mktemp line ${_mk:-<absent>}, mark line ${_mo:-<absent>})"
  _marker_probe "$REPO" "$c"; rc=$?
  verdict "$rc" "the marker file exists, well-formed, in the EXACT soleur-inc-* dir the helper created: $c"
done
# controls: the same probe on COPIES of each helper (plus the scratch-root lib they source by relative path)
for c in "${SH_CHOKE[@]}"; do
  r="$WORK/mpc.$(printf '%s' "$c" | tr '/.' '__')"
  mkdir -p "$r/scripts/lib" "$r/$(dirname "$c")"
  cp "$REPO/scripts/lib/scratch-root.sh" "$r/scripts/lib/scratch-root.sh"
  cp "$REPO/$c" "$r/$c"
  _marker_probe "$r" "$c"; rc=$?
  verdict "$rc" "control: an unmodified COPY of $c passes the marker probe (the copy mechanism works)"
  sed -e 's|\(soleur_scratch_mark_owned "\$[A-Za-z_]*\)"|\1/.claude"|' "$REPO/$c" > "$r/$c"
  if cmp -s "$REPO/$c" "$r/$c"; then printf '[FATAL] marker control: the wrong-target mutation did not land in %s\n' "$c" >&2; exit 1; fi
  _marker_probe "$r" "$c"; rc=$?
  verdict "$([ "$rc" != 0 ] && echo 0 || echo 1)" "control: marking the WRONG directory (\$dir/.claude) in a COPY of $c is detected"
done

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
    if _strip_line_comments "$tp" | grep -cE >/dev/null 'ensureIncidentSandbox[[:space:]]*\(' 2>/dev/null; then
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
# static parity reader that never spawns its subject, and a same-basename script under the
# hand-ported `.openhands/` mirror (that mirror was retired 2026-09-23, ADR-245, so that member
# no longer exists — the authoritative list of the CURRENT members is the enumeration below, not
# this paragraph, which describes the original measurement). They are LEFT IN rather than
# special-cased, because every carve-out is a place a real member can hide, and because a
# ratcheted ceiling reds on the next member either way.
# Ratcheted 4 -> 3 when the one TRUE POSITIVE this guard found was fixed:
# apps/web-platform/infra/supabase-advisor/scan-workflow.test.sh piped fixture content through
# .claude/hooks/new-scheduled-cron-prefer-inngest.sh with no chokepoint on its path -- invoked
# directly by infra-validation.yml, no bun preload, no vitest globalSetup, no test-helpers.sh. It
# now sources the sandbox helper.
#
# The remaining members are all OVER-COUNTS, verified individually rather than assumed:
#   scripts/test-jaccard-duplicates.sh        - a static parity reader, spawns nothing
#   tests/hooks/test_drop_sentinel_parity.sh  - a touched fixture stub, not the real emitter
#   plugins/soleur/test/hook-input-classification-mutation.test.sh - arrived from main 2026-09-08,
#                                               not in this PR's diff. Isolated BY LIB-COPY, the
#                                               same mechanism as tests/hooks/test_incidents.sh:
#                                               it populates $WORK/.claude/hooks/ from tracked
#                                               files and runs the COPIED suite, so
#                                               _incidents_repo_root()'s BASH_SOURCE fallback
#                                               resolves under $WORK. Measured against the
#                                               operator ledger: rc=0, delta 0 rows.
#   scripts/lib/test-affected-paths.sh        - arrived with #8322. Not a suite at all: a pure
#                                               declarations file, SOURCED by test-all.sh and
#                                               executing nothing itself. It matched hop 2 twice
#                                               over — its `test-*` basename fits the candidate
#                                               shape, and its AFFECTED_*_PATHS arrays quote the
#                                               basenames of seven hop-1 members
#                                               (grep-rewrite.sh, guardrails.sh, et al.) as DATA,
#                                               the quoted-path-literal shape the derivation keys
#                                               on. Nothing here can spawn: grep the file for a
#                                               command position and there is none.
# They are deliberately NOT carved out. Every carve-out is a place a real member can hide, and a
# ceiling reds on the next one either way.
#
# 3 -> 4 on 2026-09-09 for the entry above. The ceiling counts members; it does not certify them.
# 4 -> 5 for test-affected-paths.sh: a measured zero-leak member (a sourced data file that names
# emitter-reaching basenames as declaration literals, the same over-count class as the fixture
# stub and the parity reader).
# Raising it on a MEASURED zero-leak member is the intended use — silently carving one out is not.
#
# 5 -> 4 on 2026-09-24 (ADR-245 / #8306): the hand-ported `.openhands/` mirror was retired, and
# with it the same-basename over-count member described above. This value was MEASURED on the
# merged tree, not derived by subtracting one from main's 5 — the walk prints 4 and names them:
# hook-input-classification-mutation.test.sh, scripts/lib/test-affected-paths.sh (main's 4 -> 5
# entry), test-jaccard-duplicates.sh, test_drop_sentinel_parity.sh. Lowering is the ratchet's
# normal direction; the member is gone, not carved out.
OUTSIDE_CEILING=4
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

# --- trap composition survives a prior trap containing a single quote -------------------------
# `trap -p` prints the body in bash's OWN quoting, so an embedded single quote returns as the
# four-character sequence '\'' . Stripping the outer quotes with sed and re-wrapping in double
# quotes leaves those escapes unbalanced, and the resulting trap is a SYNTAX ERROR.
#
# MEASURED harm, before the fix: gdpr-gate-self-test.test.sh exited 2 having printed "ALL TESTS
# PASSED", on both the with-token and without-token CI paths.
#
# All three arms are kept, but only the PRIOR-TRAP arm is known to discriminate: driving this suite
# against the old composition reddens "the PRIOR trap still runs" and leaves the other two GREEN --
# in that probe the malformed string still removed the sandbox and still exited 0. So the leak arm
# is a REGRESSION GUARD, not evidence: the 971 stale soleur-inc- directories found on this machine
# are consistent with a trap that never runs, but this probe does not demonstrate that link, and
# the connection is recorded as unproven in #7889 rather than asserted here.
_tc_probe="$(mktemp -d -t tccheck-XXXXXX)"
cat > "$_tc_probe/suite.sh" <<'PROBE'
#!/usr/bin/env bash
set -uo pipefail
# a PRIOR trap whose body contains a single quote -- the shape that broke composition
trap 'printf "prior-ran bye'"'"'
"' EXIT
# The OWNED case must be forced. Under the gate this suite runs inside an outer test-all.sh that
# has already exported INCIDENTS_REPO_ROOT, and test-helpers.sh then HONOURS that root and
# allocates nothing -- so there is no sandbox of its own to remove. Asserting removal in that state
# asserts the opposite of the invariant (see test-all.sh: freeing an outer runner's sandbox
# mid-run would re-point every later suite at the operator's real ledger).
unset INCIDENTS_REPO_ROOT SOLEUR_TEST_INCIDENT_ROOT
source "$REPO_UNDER_TEST/plugins/soleur/test/test-helpers.sh" 2>/dev/null || exit 90
printf 'SB=%s
' "${SOLEUR_TEST_INCIDENT_ROOT:-<unset>}"
PROBE
_tc_out="$(cd "$REPO" && env REPO_UNDER_TEST="$REPO" bash "$_tc_probe/suite.sh" 2>&1)"
_tc_rc=$?
_tc_sb="$(printf '%s' "$_tc_out" | sed -n 's/^SB=//p')"

verdict "$([ "$_tc_rc" -eq 0 ] && echo 0 || echo 1)" \
  "composing over a prior trap with a single quote exits 0 (got rc=$_tc_rc)"
verdict "$(printf '%s' "$_tc_out" | grep -c >/dev/null 'prior-ran' && echo 0 || echo 1)" \
  "the PRIOR trap still runs after composition (not clobbered)"
verdict "$([ -n "$_tc_sb" ] && [ ! -d "$_tc_sb" ] && echo 0 || echo 1)" \
  "the sandbox is actually REMOVED — a trap that fails to parse never runs, and leaks it"

# The other direction, and the one CI actually exposed: with an INHERITED root the helper must
# allocate nothing and must NOT remove the outer runner's sandbox. Before this arm existed, the
# removal assertion above simply failed under the gate and read as a broken trap; the real
# behaviour was correct and the assertion was wrong.
_ti_outer="$(mktemp -d -t tcouter-XXXXXX)"; mkdir -p "$_ti_outer/.claude"
_ti_probe="$(mktemp -d -t tcinh-XXXXXX)"
cat > "$_ti_probe/suite.sh" <<'PROBE2'
#!/usr/bin/env bash
set -uo pipefail
source "$REPO_UNDER_TEST/plugins/soleur/test/test-helpers.sh" 2>/dev/null || exit 90
printf 'ROOT=%s\n' "${INCIDENTS_REPO_ROOT:-<unset>}"
PROBE2
_ti_out="$(cd "$REPO" && env REPO_UNDER_TEST="$REPO" INCIDENTS_REPO_ROOT="$_ti_outer" \
            SOLEUR_TEST_INCIDENT_ROOT="$_ti_outer" bash "$_ti_probe/suite.sh" 2>&1)"
_ti_root="$(printf '%s' "$_ti_out" | sed -n 's/^ROOT=//p')"
verdict "$([ "$_ti_root" = "$_ti_outer" ] && echo 0 || echo 1)" \
  "an INHERITED root is honoured, not replaced (got ${_ti_root:-<none>})"
verdict "$([ -d "$_ti_outer" ] && echo 0 || echo 1)" \
  "the OUTER runner's sandbox survives the inner suite's exit (freeing it would re-point later suites at the real ledger)"
rm -rf "$_ti_probe" "$_ti_outer"
unset _ti_probe _ti_out _ti_root _ti_outer

rm -rf "$_tc_probe"
unset _tc_probe _tc_out _tc_rc _tc_sb

printf '\n'
MIN_CASES=46
if [ "$CASES" -lt "$MIN_CASES" ]; then
  printf '[FATAL] vacuity floor: %d cases executed, expected at least %d\n' "$CASES" "$MIN_CASES" >&2; exit 1
fi
if [ $((PASS+FAIL)) -ne "$CASES" ]; then
  printf '[FATAL] accounting: PASS+FAIL=%d but CASES=%d\n' "$((PASS+FAIL))" "$CASES" >&2; exit 1
fi
if [ "$FAIL" -gt 0 ]; then printf 'FAILED: %d/%d\n' "$FAIL" "$CASES"; exit 1; fi
printf 'OK: %d/%d\n' "$PASS" "$CASES"
