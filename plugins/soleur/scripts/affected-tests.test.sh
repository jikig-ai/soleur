#!/usr/bin/env bash
# affected-tests.test.sh — the contract suite for the plugin-shipped stack-detecting
# affected test gate (#9307, deliverable 2).
#
# SUT: plugins/soleur/scripts/affected-tests.sh — invoked as
#   bash affected-tests.sh [--full] [--base <ref>] [--explain] [--self-check]
# from the ROOT of a synthesized fixture repository.
#
# PROPERTY. The gate exits 0 only when at least one selected test ran and passed (or the
# whole diff is inert and it printed NO_TESTS_AFFECTED); it refuses loudly (rc 4) on a
# vacuous/undecidable selection; it delegates --affected/--full ONLY to a repo runner that
# registers --print-selection at a case-label or usage-table position; it fails closed on
# malformed config; it emits `AFFECTED_GATE ran=X of=N skipped=Y mode=… reason=… stack=… ci=…`
# on EVERY run path. See the plan's Guard Contract for the mutation matrices this suite
# pins — each matrix row below is tagged [G<n>-<row>].
#
# ASSEMBLY. Every run happens inside a synthesized fixture repo (cq-test-fixtures-
# synthesized-only) under one mktemp root, behind PATH-shimmed fake runners
# (vitest/jest/pytest/go/nx/turbo/node/python3 + the package managers) that LOG every
# invocation to $CALLS and validate argv VALUES — an argv shape this suite does not
# prescribe is a stub miss (rc 64), never a silent success. Base refs come from minted
# refs/remotes/origin/* refs; the shallow-clone row uses a real file:// --depth 1 clone.
#
# INSTRUMENT FIDELITY (G1-11). Rows that claim "the runner ran" assert against the
# invocation ledger, never against exit codes alone — a fake that printed success
# without recording itself would turn those rows red. The `log_nonempty` check is
# itself self-tested against an empty ledger.
#
# cloud coverage: run_gate ALWAYS invokes the SUT with `env -u CLAUDE_PLUGIN_ROOT`, so
# every row exercises the no-plugin-root path (the gate resolves its libs by
# BASH_SOURCE; no in-gate resolver exists — ADR-179's three-arm diagnostic lives
# in commands/go.md, not here).
#
# Authoring note (work/SKILL.md): never `producer | grep -q` under pipefail — every rc is
# captured on its own line before it is inspected.

set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$DIR/../../.." && pwd)"
# AFFECTED_TESTS_SUT exists so the fixture plumbing itself can be smoke-tested
# against a stand-in without touching the real gate's path.
SUT="${AFFECTED_TESTS_SUT:-$DIR/affected-tests.sh}"

# assert_fixture_dir / git_fixture_env / print_results live here; sourcing arms the
# git-location tripwire (#7833) — this suite must never run with an inherited GIT_DIR.
# shellcheck source=plugins/soleur/test/test-helpers.sh
source "$DIR/../test/test-helpers.sh" || { echo "FATAL: could not source test-helpers.sh" >&2; exit 2; }
set +e -uo pipefail

TESTROOT="$(mktemp -d -t affected-gate.XXXXXXXX)" || { echo "FATAL: mktemp failed" >&2; exit 2; }
assert_fixture_dir "$TESTROOT"
trap 'rm -rf "$TESTROOT"' EXIT INT TERM HUP

WORLD="$TESTROOT/world"        # all fixture repos + remotes live under here
BIN="$TESTROOT/bin"           # PATH shims
CALLS="$TESTROOT/calls.log"  # the invocation ledger every row asserts on
RUNS="$TESTROOT/runs.tsv"    # per-run record: kind\trc\toutfile
mkdir -p "$WORLD/repos" "$BIN" "$TESTROOT/outs"
: > "$CALLS"; : > "$RUNS"

# Constructed git env: synthesized identity, isolated config, discovery ceiling pinned
# one level above $WORLD (ceiling = $TESTROOT), so no fixture git ever reads the
# operator's credentials, global config, or an ancestor repository.
git_fixture_env "$WORLD" || { echo "FATAL: git_fixture_env refused $WORLD" >&2; exit 2; }

# Host tool paths captured BEFORE the shim dir goes on PATH: the node/python3 shims
# delegate unrecognized argv to these so the SUT's own internal use keeps working.
REAL_NODE="$(command -v node || true)"
REAL_PY="$(command -v python3 || true)"
REAL_GIT="$(command -v git || true)"   # census-failure row: the git shim delegates here
BASEPATH="$PATH"

pass() { PASS=$((PASS + 1)); printf '  [ok] %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf '  [FAIL] %s\n' "$1" >&2; }

# Instrument self-test: both verdict helpers must move their counters.
_sp=$PASS; _sf=$FAIL
pass "instrument self-test" >/dev/null 2>&1
fail "instrument self-test" >/dev/null 2>&1
if (( PASS != _sp + 1 )) || (( FAIL != _sf + 1 )); then
  echo "[FATAL] instrument self-test failed" >&2; exit 1
fi
PASS=$_sp; FAIL=$_sf

[[ -f "$SUT" ]] || {
  printf '\n[FATAL] SUT missing at %s — nothing to test (expected RED while the gate is unwritten).\n' "$SUT" >&2
  exit 1
}

# ================================ fakes =======================================
# Every fake: logs `<basename>\t<argv>` to $FAKE_LOG, validates argv VALUES against
# FAKE_*_EXPECT / FAKE_*_MAXW env pins, exits 64 on an unrouted or mis-shaped call,
# and takes its verdict rc from FAKE_*_RC. Logging happens BEFORE validation so a row
# asserting "never called" cannot be laundered by a 64.

cat > "$BIN/vitest" <<'SHIM'
#!/usr/bin/env bash
[[ -n "${FAKE_LOG:-}" ]] || { echo "stub vitest: FAKE_LOG unset" >&2; exit 64; }
printf 'vitest\t%s\n' "$*" >> "$FAKE_LOG"
for a in "$@"; do case "$a" in --version|-V|-v) echo "4.1.11"; exit 0 ;; --help) echo "vitest 4.1.11"; exit 0 ;; esac; done
[[ -z "${FAKE_VITEST_SLEEP:-}" ]] || sleep "$FAKE_VITEST_SLEEP"
mode=full
for a in "$@"; do [[ "$a" == "related" ]] && mode=related; done
# `vitest related <files> --run` is the #9307 contract — the subcommand form, and the
# --run flag is mandatory on the affected path (watch mode would hang the gate).
if [[ "$mode" == "related" ]]; then
  case " $* " in
    *" --run "*) : ;;
    *) echo "stub vitest: 'related' without --run: $*" >&2; exit 64 ;;
  esac
fi
maxw=""; prev=""
for a in "$@"; do
  if [[ -n "$prev" ]]; then maxw="$a"; prev=""; continue; fi
  case "$a" in
    --maxWorkers|--max-workers|-w) prev="$a" ;;
    --maxWorkers=*|--max-workers=*|-w=*) maxw="${a#*=}" ;;
  esac
done
if [[ -n "${FAKE_VITEST_MAXW:-}" && "$maxw" != "$FAKE_VITEST_MAXW" ]]; then
  echo "stub vitest: --maxWorkers=${maxw:-<absent>} want $FAKE_VITEST_MAXW" >&2; exit 64
fi
for want in ${FAKE_VITEST_EXPECT:-}; do
  case " $* " in
    *"$want"*) : ;;
    *) echo "stub vitest: expected arg '$want' missing: $*" >&2; exit 64 ;;
  esac
done
# The empty-selection answer is scoped to `related`: a selector that finds nothing
# is not the same verdict as a full run that found nothing.
if [[ "$mode" == "related" && "${FAKE_VITEST_NOTESTS:-0}" == "1" ]]; then
  echo "No test files found"
  exit "${FAKE_VITEST_RC:-0}"
fi
# Honest tally: the reported count must equal the fixture's own test-file
# count — a constant here would let ran= diverge from of= and launder the
# unit-integrity rows (D7/D16/D19a pin file units).
_n="$(find . -type f \( -name '*.test.*' -o -name '*.spec.*' \) \
      -not -path './node_modules/*' 2>/dev/null | wc -l | tr -d ' ')"
[[ "$_n" =~ ^[0-9]+$ ]] && ((_n > 0)) || _n=1
echo "Test Files  $_n passed ($_n)"
exit "${FAKE_VITEST_RC:-0}"
SHIM

cat > "$BIN/jest" <<'SHIM'
#!/usr/bin/env bash
[[ -n "${FAKE_LOG:-}" ]] || { echo "stub jest: FAKE_LOG unset" >&2; exit 64; }
printf 'jest\t%s\n' "$*" >> "$FAKE_LOG"
for a in "$@"; do case "$a" in --version|-V|-v) echo "30.0.5"; exit 0 ;; --help) echo "jest 30.0.5"; exit 0 ;; esac; done
rel=0
for a in "$@"; do [[ "$a" == "--findRelatedTests" ]] && rel=1; done
if [[ "${FAKE_JEST_REQUIRE_RELATED:-0}" == "1" && "$rel" == "0" ]]; then
  echo "stub jest: expected --findRelatedTests in: $*" >&2; exit 64
fi
for want in ${FAKE_JEST_EXPECT:-}; do
  case " $* " in
    *"$want"*) : ;;
    *) echo "stub jest: expected arg '$want' missing: $*" >&2; exit 64 ;;
  esac
done
# Same honest-tally rule as the vitest stub — the __tests__ convention carries
# no .test./.spec. marker, so count the directory shape too (mirrors the
# adapter's census).
_n="$(find . -type f \( -name '*.test.*' -o -name '*.spec.*' \
      -o -path '*/__tests__/*' \) -not -path './node_modules/*' 2>/dev/null \
      | wc -l | tr -d ' ')"
[[ "$_n" =~ ^[0-9]+$ ]] && ((_n > 0)) || _n=1
echo "Test Suites: $_n passed, $_n total"
exit "${FAKE_JEST_RC:-0}"
SHIM

cat > "$BIN/pytest" <<'SHIM'
#!/usr/bin/env bash
[[ -n "${FAKE_LOG:-}" ]] || { echo "stub pytest: FAKE_LOG unset" >&2; exit 64; }
printf 'pytest\t%s\n' "$*" >> "$FAKE_LOG"
for a in "$@"; do
  case "$a" in --version|-V|--help) echo "pytest 8.3.0"; exit 0 ;; esac
done
for want in ${FAKE_PYTEST_EXPECT:-}; do
  case " $* " in
    *"$want"*) : ;;
    *) echo "stub pytest: expected arg '$want' missing: $*" >&2; exit 64 ;;
  esac
done
rc="${FAKE_PYTEST_RC:-0}"
if [[ "$rc" == "5" ]]; then echo "no tests collected"; exit 5; fi
# pytest's own tally line: `collected N items` (testmon adds `/ M deselected`)
# — the gate pins ran to FILE units, so this line is realism, not the counter.
_nitems="${FAKE_PYTEST_COLLECTED:-1}"
if [[ -n "${FAKE_PYTEST_DESELECTED:-}" ]]; then
  echo "collected $_nitems items / $FAKE_PYTEST_DESELECTED deselected"
else
  echo "collected $_nitems items"
fi
echo "=== $_nitems passed in 0.01s ==="
exit "$rc"
SHIM

cat > "$BIN/go" <<'SHIM'
#!/usr/bin/env bash
[[ -n "${FAKE_LOG:-}" ]] || { echo "stub go: FAKE_LOG unset" >&2; exit 64; }
printf 'go\t%s\n' "$*" >> "$FAKE_LOG"
cmd="${1:-}"
case "$cmd" in
  version) echo "go version go1.23.4 linux/amd64"; exit 0 ;;
  env)
    for a in "$@"; do
      case "$a" in GOMOD) printf '%s\n' "${FAKE_GO_GOMOD:-$PWD/go.mod}" ;; esac
    done
    exit 0 ;;
  list)
    # FAKE_GO_DIR/graph rows are pipe-form: `ImportPath|deps deps|TestImports|XTestImports`
    # — the same shape the real `go list -e -f` template emits.
    graph="${FAKE_GO_DIR:-}/graph"
    [[ -f "$graph" ]] || { echo "stub go: list with no FAKE_GO_DIR/graph" >&2; exit 64; }
    has_f=0; has_deps=0; targets=""
    prev=""
    for a in "$@"; do
      if [[ "$prev" == "-f" ]]; then has_f=1; prev=""; continue; fi
      case "$a" in
        list) : ;;
        -f) prev="-f" ;;
        -f*) has_f=1 ;;
        -deps) has_deps=1 ;;
        -*) : ;;
        *) targets="$targets $a" ;;
      esac
    done
    if (( has_f )); then
      if [[ "$targets" == *"/..."* || -z "${targets// /}" ]]; then
        while IFS= read -r line; do printf '%s\n' "$line"; done < "$graph"
      else
        # `go list -e -f '{{.ImportPath}}' <dir>` — a dir target (./x) resolves
        # to the graph row whose import path ENDS in it; `.` is the module root
        # (the shortest import path).
        for t in $targets; do
          td="${t#./}"
          if [[ "$td" == "." ]]; then
            awk -F'|' '{n=gsub(/\//,"/",$1); if(NR==1||n<min){min=n;best=$1}} END{if(best!="")print best; else exit 1}' "$graph" \
              || { echo "stub go: unknown dir $t" >&2; exit 64; }
          else
            awk -F'|' -v t="$td" 'length($1)>=length(t) && substr($1,length($1)-length(t)+1)==t{print $1; f=1} END{if(!f) exit 1}' "$graph" \
              || { echo "stub go: unknown dir $t" >&2; exit 64; }
          fi
        done
      fi
      exit 0
    fi
    if [[ "$targets" == *"/..."* || -z "${targets// /}" ]]; then
      awk -F'|' '{print $1}' "$graph"
      exit 0
    fi
    # named package(s): `go list -deps <pkg>` prints one import path per line
    # (target plus the deps the graph row declares); plain `go list <pkg>` prints it.
    for t in $targets; do
      [[ "$t" == "list" ]] && continue
      if (( has_deps )); then
        awk -F'|' -v t="$t" '$1==t{print $1; n=split($2,d," "); for(i=1;i<=n;i++) print d[i]; f=1} END{if(!f) exit 1}' "$graph" \
          || { echo "stub go: unknown package $t" >&2; exit 64; }
      else
        awk -F'|' -v t="$t" '$1==t{print $1; f=1} END{if(!f) exit 1}' "$graph" \
          || { echo "stub go: unknown package $t" >&2; exit 64; }
      fi
    done
    exit 0 ;;
  test)
    # `go test -p <n> [pkg …]` — emit the real `ok`/`?` per-package lines so
    # the adapter can count *_test.go files under each reported package.
    has_p=0; tgts=""; prev=""
    for a in "$@"; do
      if [[ -n "$prev" ]]; then prev=""; continue; fi
      case "$a" in
        -p|--parallel) prev="$a"; has_p=1 ;;
        -p=*|--parallel=*) has_p=1 ;;
        test) : ;;
        -*) : ;;
        *) tgts="$tgts $a" ;;
      esac
    done
    if [[ "${FAKE_GO_REQUIRE_P:-1}" == "1" && "$has_p" == "0" ]]; then
      echo "stub go: 'go test' without a -p worker cap: $*" >&2; exit 64
    fi
    for want in ${FAKE_GO_EXPECT:-}; do
      case " $* " in
        *"$want"*) : ;;
        *) echo "stub go: expected package '$want' not under test: $*" >&2; exit 64 ;;
      esac
    done
    [[ -n "${tgts// /}" ]] || tgts=" ./..."
    for t in $tgts; do
      if [[ "$t" == "./..." ]]; then
        awk '{print "ok\t"$1"\t0.01s"}' "${FAKE_GO_DIR:-}/graph" 2>/dev/null || true
      else
        printf 'ok\t%s\t0.01s\n' "$t"
      fi
    done
    exit "${FAKE_GO_TEST_RC:-0}" ;;
  *) echo "stub go: unrouted call: $*" >&2; exit 64 ;;
esac
SHIM

cat > "$BIN/nx" <<'SHIM'
#!/usr/bin/env bash
[[ -n "${FAKE_LOG:-}" ]] || { echo "stub nx: FAKE_LOG unset" >&2; exit 64; }
printf 'nx\t%s\n' "$*" >> "$FAKE_LOG"
for a in "$@"; do case "$a" in --version|-V|-v) echo "22.4.0"; exit 0 ;; esac; done
case " $* " in
  *" affected "*|*" affected"*)
    for want in ${FAKE_NX_EXPECT:-}; do
      case " $* " in
        *"$want"*) : ;;
        *) echo "stub nx: expected arg '$want' missing: $*" >&2; exit 64 ;;
      esac
    done
    # FAKE_NX_LINE controls the summary line — e.g. "… for 10 tasks" must NOT
    # read as a vacuous "0 tasks" verdict.
    echo "${FAKE_NX_LINE:-nx affected: ran target test}"
    exit "${FAKE_NX_RC:-0}" ;;
  *" run-many "*|*" run-many"*)
    echo "${FAKE_NX_FULL_LINE:-nx run-many: ran target test for 3 projects}"
    exit "${FAKE_NX_FULL_RC:-0}" ;;
  *" show "*)
    for p in ${FAKE_NX_PROJECTS:-webapp}; do printf '%s\n' "$p"; done
    exit 0 ;;
  *) echo "stub nx: unrouted call: $*" >&2; exit 64 ;;
esac
SHIM

cat > "$BIN/turbo" <<'SHIM'
#!/usr/bin/env bash
[[ -n "${FAKE_LOG:-}" ]] || { echo "stub turbo: FAKE_LOG unset" >&2; exit 64; }
printf 'turbo\t%s\n' "$*" >> "$FAKE_LOG"
for a in "$@"; do case "$a" in --version|-V|-v) echo "2.5.6"; exit 0 ;; esac; done
has_run=0; has_test=0
for a in "$@"; do
  [[ "$a" == "run" ]] && has_run=1
  [[ "$a" == "test" || "$a" == test* ]] && has_test=1
done
if [[ "$has_run" == "1" && "$has_test" == "1" ]]; then
  for want in ${FAKE_TURBO_EXPECT:-}; do
    case " $* " in
      *"$want"*) : ;;
      *) echo "stub turbo: expected arg '$want' missing: $*" >&2; exit 64 ;;
    esac
  done
  echo "turbo: tasks complete"
  exit "${FAKE_TURBO_RC:-0}"
fi
echo "stub turbo: unrouted call: $*" >&2
exit 64
SHIM

cat > "$BIN/node" <<'SHIM'
#!/usr/bin/env bash
[[ -n "${FAKE_LOG:-}" ]] || { echo "stub node: FAKE_LOG unset" >&2; exit 64; }
printf 'node\t%s\n' "$*" >> "$FAKE_LOG"
case "${1:-}" in --version|-v) echo "v22.11.0"; exit 0 ;; esac
# `node <path>/vitest.mjs <args>` / `node <path>/jest.js <args>` — the first arg
# whose basename names a tool becomes the tool call; the tool shim logs it.
args=("$@"); i=0
while (( i < ${#args[@]} )); do
  b="${args[i]##*/}"
  case "$b" in
    vitest*|vitest.mjs) exec vitest ${args[@]+"${args[@]:$((i+1))}"} ;;
    jest*|jest.js|jest-cli*) exec jest ${args[@]+"${args[@]:$((i+1))}"} ;;
  esac
  i=$((i+1))
done
[[ -n "${REAL_NODE:-}" ]] && exec "$REAL_NODE" "$@"
echo "stub node: unrouted call: $*" >&2
exit 64
SHIM

cat > "$BIN/python3" <<'SHIM'
#!/usr/bin/env bash
[[ -n "${FAKE_LOG:-}" ]] || { echo "stub python3: FAKE_LOG unset" >&2; exit 64; }
printf 'python3\t%s\n' "$*" >> "$FAKE_LOG"
# The gate probes with isolated mode (`python3 -I -c …`): consume leading
# single-letter interpreter flags before routing on the payload.
while [[ "${1:-}" == -[a-zA-Z] && "${1:-}" != "-c" && "${1:-}" != "-m" && "${1:-}" != "-V" ]]; do shift; done
# `python3 -m pytest <args>` runs the pytest shim.
if [[ "${1:-}" == "-m" && "${2:-}" == "pytest" ]]; then
  shift 2; exec pytest "$@"
fi
# Importability probes: `python3 -c 'import xdist'` (and find_spec spellings whose
# -c text names the module). Answers come from FAKE_PY_IMPORTABLE (space-separated
# module names that import cleanly); anything else delegates to the real python3 so
# the SUT's own config parsing keeps working.
if [[ "${1:-}" == "-c" && -n "${2:-}" ]]; then
  script="$2"
  mod=""
  if [[ "$script" =~ (^|[^A-Za-z_])(pytest_testmon|testmon)([^A-Za-z_]|$) ]]; then mod="testmon";
  elif [[ "$script" =~ (^|[^A-Za-z_])xdist([^A-Za-z_]|$) ]]; then mod="xdist";
  elif [[ "$script" =~ (^|[^A-Za-z_])pytest([^A-Za-z_]|$) ]]; then mod="pytest"; fi
  if [[ -n "$mod" ]]; then
    case " ${FAKE_PY_IMPORTABLE:-} " in
      *" $mod "*) exit 0 ;;
      *) exit 1 ;;
    esac
  fi
fi
case "${1:-}" in --version|-V) echo "Python 3.15.0"; exit 0 ;; esac
[[ -n "${REAL_PY:-}" ]] && exec "$REAL_PY" "$@"
echo "stub python3: unrouted call: $*" >&2
exit 64
SHIM

# The package-manager shims share one body: they log, then either exec through to a
# shimmed tool (`npx vitest related …` → the vitest shim re-logs and validates) or
# answer a `test`/`run test` invocation from FAKE_PM_TEST_RC.
PM_BODY='#!/usr/bin/env bash
name="$(basename "$0")"
[[ -n "${FAKE_LOG:-}" ]] || { echo "stub $name: FAKE_LOG unset" >&2; exit 64; }
printf "%s\t%s\n" "$name" "$*" >> "$FAKE_LOG"
args=("$@"); i=0
while (( i < ${#args[@]} )); do
  a="${args[i]}"
  case "$a" in
    -y|--yes|--|x|exec|dlx|-dlx) i=$((i+1)); continue ;;
    vitest@*|jest@*|nx@*|turbo@*) exec "${a%%@*}" ${args[@]+"${args[@]:$((i+1))}"} ;;
    vitest|jest|nx|turbo|pytest|go) exec "$a" ${args[@]+"${args[@]:$((i+1))}"} ;;
    run)
      nxt="${args[$((i+1))]:-}"
      [[ "$nxt" == "test" ]] && exit "${FAKE_PM_TEST_RC:-0}"
      i=$((i+2)); continue ;;
    test) exit "${FAKE_PM_TEST_RC:-0}" ;;
    install|i|add|remove|ci|create|init|info|view|ls|list|audit|outdated|pack|publish|version|whoami|pkg)
      exit 0 ;;
    *) i=$((i+1)) ;;
  esac
done
echo "stub $name: unrouted call: $*" >&2
exit 64
'
for _pm in npm npx pnpm yarn bun bunx; do
  printf '%s\n' "$PM_BODY" > "$BIN/$_pm"
done
chmod +x "$BIN"/*
unset _pm

# ============================ fixture builders ================================

# mk_repo <name> [default-branch] — repo at $WORLD/repos/<name> with a `feature`
# branch checked out. Base-ref resolution gets its refs WITHOUT a live remote:
# refs/remotes/origin/<br> + refs/remotes/origin/HEAD are minted directly, so
# `@{upstream}` fails (feature has none) and the origin/HEAD → origin/<br> arm wins.
mk_repo() { # prints the repo path
  local name="$1" br="${2:-main}" r
  r="$WORLD/repos/$name"
  mkdir -p "$r"
  printf 'fixture seed\n' > "$r/SEED.txt"
  git -C "$r" init -q -b "$br"
  git -C "$r" config user.email soleur-test@example.invalid
  git -C "$r" config user.name "Soleur Fixture"
  git -C "$r" config commit.gpgsign false
  printf '%s' "$r"
}

# seal_base <repo> — commit the seeded base, mint origin refs, move to `feature`.
seal_base() {
  local r="$1" br
  assert_fixture_dir "$r"
  # symbolic-ref, not rev-parse: HEAD is UNBORN until the commit below lands, and
  # rev-parse --abbrev-ref errors out there while symbolic-ref still reads the
  # branch HEAD points at.
  br="$(git -C "$r" symbolic-ref --short -q HEAD)"
  git -C "$r" add -A
  git -C "$r" commit -q -m "base"
  git -C "$r" update-ref "refs/remotes/origin/$br" HEAD
  git -C "$r" symbolic-ref refs/remotes/origin/HEAD "refs/remotes/origin/$br"
  git -C "$r" checkout -q -b feature
}

chg()        { local r="$1" f="$2"; mkdir -p "$r/$(dirname "$f")"; printf '%b\n' "${3:-change}" > "$r/$f"; }
commit_chg() { assert_fixture_dir "$1"; chg "$1" "$2" "${3:-change}"; git -C "$1" add -A; git -C "$1" commit -q -m "change: $2"; }

seed_js() { # <repo> — vitest stack: package.json, src, a test file, node_modules stub
  local r="$1"
  mkdir -p "$r/src" "$r/node_modules/.bin"
  cat > "$r/package.json" <<'JSON'
{
  "name": "fixture-js",
  "private": true,
  "scripts": { "test": "vitest run" },
  "devDependencies": { "vitest": "^4.0.0" }
}
JSON
  printf 'node_modules/\n' > "$r/.gitignore"
  printf 'export const a = 1;\n' > "$r/src/a.ts"
  printf 'import { test } from "vitest";\ntest("a", () => {});\n' > "$r/src/a.test.ts"
  ln -sf "$BIN/vitest" "$r/node_modules/.bin/vitest"
}

seed_js_nobin() { # <repo> — vitest stack but NO repo-local binary: used by the
                  # toolchain-missing row, where a .bin symlink would resolve the
                  # shim even on a stripped PATH.
  local r="$1"
  mkdir -p "$r/src"
  cat > "$r/package.json" <<'JSON'
{
  "name": "fixture-js",
  "private": true,
  "scripts": { "test": "vitest run" },
  "devDependencies": { "vitest": "^4.0.0" }
}
JSON
  printf 'node_modules/\n' > "$r/.gitignore"
  printf 'export const a = 1;\n' > "$r/src/a.ts"
  printf 'import { test } from "vitest";\ntest("a", () => {});\n' > "$r/src/a.test.ts"
}

seed_jest() { # <repo> — jest stack (jest.config.js present, no vitest config)
  local r="$1"
  mkdir -p "$r/src" "$r/node_modules/.bin"
  cat > "$r/package.json" <<'JSON'
{
  "name": "fixture-jest",
  "private": true,
  "scripts": { "test": "jest" },
  "devDependencies": { "jest": "^30.0.0" }
}
JSON
  printf 'node_modules/\n' > "$r/.gitignore"
  printf 'module.exports = {};\n' > "$r/jest.config.js"
  printf 'export const b = 1;\n' > "$r/src/b.ts"
  printf 'test("b", () => {});\n' > "$r/src/b.test.ts"
  ln -sf "$BIN/jest" "$r/node_modules/.bin/jest"
}

seed_python() { # <repo> — pytest stack
  local r="$1"
  mkdir -p "$r/src" "$r/tests"
  cat > "$r/pyproject.toml" <<'TOML'
[project]
name = "fixture-py"
[tool.pytest.ini_options]
testpaths = ["tests"]
TOML
  printf 'def f():\n    return 1\n' > "$r/src/mod.py"
  printf 'def test_a():\n    assert True\n' > "$r/tests/test_a.py"
}

seed_go() { # <repo> <graph-dir> — go.mod + packages; writes <graph-dir>/graph as
            # "pkg dep dep" lines the go shim answers `go list` from
  local r="$1" g="$2"
  mkdir -p "$r/internal/leaf" "$r/cmd/app" "$g"
  printf 'module example.com/m\n\ngo 1.23\n' > "$r/go.mod"
  printf 'package leaf\n\nfunc Leaf() int { return 1 }\n' > "$r/internal/leaf/leaf.go"
  printf 'package leaf\n\nimport "testing"\n\nfunc TestLeaf(t *testing.T) {}\n' > "$r/internal/leaf/leaf_test.go"
  printf 'package main\n\nimport _ "example.com/m/internal/leaf"\n\nfunc main() {}\n' > "$r/cmd/app/main.go"
  # Pipe-form rows: ImportPath|Imports|TestImports|XTestImports — the shape
  # `go list -e -f '{{.ImportPath}}|{{join .Imports " "}}|…'` emits.
  cat > "$g/graph" <<'GRAPH'
example.com/m/cmd/app|example.com/m/internal/leaf fmt||
example.com/m/internal/leaf|||
GRAPH
}

seed_nx()   { local r="$1"; seed_js "$r"; printf '{"npmScope":"fx","affected":{}}\n' > "$r/nx.json"; }
seed_turbo(){ local r="$1"; seed_js "$r"; printf '{"pipeline":{"test":{}}}\n' > "$r/turbo.json"; }

seed_ci() { # <repo> — a CI test workflow (must be committed in BASE: the workflows
            # dir is itself a built-in global_path)
  local r="$1"
  mkdir -p "$r/.github/workflows"
  cat > "$r/.github/workflows/ci.yml" <<'YML'
name: ci
on: pull_request
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - run: npm test
YML
}

write_config() { # <repo> <json>
  printf '%s\n' "$2" > "$1/.soleur-test-gate.json"
}

# The capability-positive runner (G2): registers --print-selection at BOTH the
# case-label position and the usage-table position, as scripts/test-all.sh does.
write_runner_capable() { # <repo>
  local r="$1"
  mkdir -p "$r/scripts"
  cat > "$r/scripts/test-all.sh" <<'RUNNER'
#!/usr/bin/env bash
printf 'test-all\t%s\n' "$*" >> "${FAKE_LOG:?}"
usage() {
  cat <<'USAGE'
Usage: bash scripts/test-all.sh [--affected] [--full]
  --affected          run the suites this diff selects
  --full              run the entire battery
  --print-selection   print the suites this diff selects; runs nothing
USAGE
}
for a in "$@"; do
  case "$a" in
    --print-selection) printf 'AFFECTED_SELECTED\tsuite\taffected\n'; exit 0 ;;
    --affected) exit "${FAKE_RUNNER_AFFECTED_RC:-${FAKE_RUNNER_RC:-0}}" ;;
    --full) exit "${FAKE_RUNNER_FULL_RC:-${FAKE_RUNNER_RC:-0}}" ;;
    --capacity) printf 'measured_runs=0\n'; exit 0 ;;
    --help|-h) usage; exit 0 ;;
    *) echo "runner stub: unexpected argv: $a" >&2; exit 64 ;;
  esac
done
exit "${FAKE_RUNNER_RC:-0}"
RUNNER
  chmod +x "$r/scripts/test-all.sh"
}

# Usage-table-only registration (G2-5 must-PASS): --print-selection appears ONLY as
# a usage-table row; the dispatch loop matches it through a conditional, not a
# case label. A probe that insists on the `)` case-label spelling misses this.
write_runner_usage_table() { # <repo>
  local r="$1"
  mkdir -p "$r/scripts"
  cat > "$r/scripts/test-all.sh" <<'RUNNER'
#!/usr/bin/env bash
printf 'test-all\t%s\n' "$*" >> "${FAKE_LOG:?}"
usage() {
  cat <<'USAGE'
Usage: bash scripts/test-all.sh [--affected] [--full]
  --affected          run the suites this diff selects
  --full              run the entire battery
  --print-selection   print the suites this diff selects; runs nothing
USAGE
}
for a in "$@"; do
  if [[ "$a" == "--print-selection" ]]; then
    printf 'AFFECTED_SELECTED\tsuite\taffected\n'; exit 0
  elif [[ "$a" == "--affected" ]]; then
    exit "${FAKE_RUNNER_AFFECTED_RC:-${FAKE_RUNNER_RC:-0}}"
  elif [[ "$a" == "--full" ]]; then
    exit "${FAKE_RUNNER_FULL_RC:-${FAKE_RUNNER_RC:-0}}"
  elif [[ "$a" == "--help" || "$a" == "-h" ]]; then
    usage; exit 0
  else
    echo "runner stub: unexpected argv: $a" >&2; exit 64
  fi
done
exit "${FAKE_RUNNER_RC:-0}"
RUNNER
  chmod +x "$r/scripts/test-all.sh"
}

# A foreign scripts/test-all.sh (G2-1): a same-named script that belongs to the
# user's repo, advertises nothing, and must NEVER receive Soleur flags.
write_runner_foreign() { # <repo>
  local r="$1"
  mkdir -p "$r/scripts"
  cat > "$r/scripts/test-all.sh" <<'RUNNER'
#!/usr/bin/env bash
printf 'foreign-runner\t%s\n' "$*" >> "${FAKE_LOG:-/dev/null}"
echo "ok"
exit 0
RUNNER
  chmod +x "$r/scripts/test-all.sh"
}

# Foreign + comment-only mention (G2-4): the flag text appears in a comment —
# never at a case-label or usage-table position.
write_runner_comment_mention() { # <repo>
  local r="$1"
  mkdir -p "$r/scripts"
  cat > "$r/scripts/test-all.sh" <<'RUNNER'
#!/usr/bin/env bash
# NOTE: --print-selection support is planned for a future release of this
# runner; until then it knows only how to run everything.
printf 'foreign-runner\t%s\n' "$*" >> "${FAKE_LOG:-/dev/null}"
echo "ok"
exit 0
RUNNER
  chmod +x "$r/scripts/test-all.sh"
}

# ============================ run + assert plumbing ===========================

reset_fakes() {
  : > "$CALLS"
  export FAKE_VITEST_RC=0 FAKE_VITEST_EXPECT="" FAKE_VITEST_MAXW="" FAKE_VITEST_NOTESTS=0 FAKE_VITEST_SLEEP=""
  export FAKE_JEST_RC=0 FAKE_JEST_EXPECT="" FAKE_JEST_REQUIRE_RELATED=0
  export FAKE_PYTEST_RC=0 FAKE_PYTEST_EXPECT=""
  export FAKE_PY_IMPORTABLE="pytest"
  export FAKE_GO_TEST_RC=0 FAKE_GO_EXPECT="" FAKE_GO_DIR="" FAKE_GO_GOMOD="" FAKE_GO_REQUIRE_P=1
  export FAKE_NX_RC=0 FAKE_NX_EXPECT="" FAKE_NX_PROJECTS="" FAKE_NX_LINE="" FAKE_NX_FULL_LINE="" FAKE_NX_FULL_RC=0
  export FAKE_PYTEST_COLLECTED="" FAKE_PYTEST_DESELECTED=""
  export FAKE_TURBO_RC=0 FAKE_TURBO_EXPECT=""
  export FAKE_RUNNER_RC=0 FAKE_RUNNER_AFFECTED_RC="" FAKE_RUNNER_FULL_RC=""
  export FAKE_PM_TEST_RC=0
  export FAKE_GIT_FAIL_OTHERS=0
}

RSEQ=0; RC=0; OUT=""
_run_gate() { # <PATH> <repo> <kind:gate|explain|selfcheck> [gate args…]
  local p="$1" repo="$2" kind="$3"; shift 3
  RSEQ=$((RSEQ + 1))
  ( cd "$repo" && env -u CLAUDE_PLUGIN_ROOT \
      PATH="$p" \
      FAKE_LOG="$CALLS" FAKE_DIR="$TESTROOT" \
      REAL_NODE="$REAL_NODE" REAL_PY="$REAL_PY" REAL_GIT="$REAL_GIT" \
      bash "$SUT" "$@" ) > "$TESTROOT/outs/$RSEQ.out" 2>&1
  RC=$?
  OUT="$(cat "$TESTROOT/outs/$RSEQ.out")"
  printf '%s\t%s\t%s\n' "$kind" "$RC" "$TESTROOT/outs/$RSEQ.out" >> "$RUNS"
}
run_gate()      { _run_gate "$BIN:$BASEPATH" "$@"; }
run_gate_path() { local p="$1"; shift; _run_gate "$p" "$@"; }

# --- verdict helpers ----------------------------------------------------------
want_rc() {
  if [[ "$RC" == "$1" ]]; then pass "$2"
  else fail "$2 — rc=$RC want=$1 :: $(tail -n 3 "$TESTROOT/outs/$RSEQ.out" 2>/dev/null | tr '\n' '|')"; fi
}
want_rc_in() { # <label> <rc> <rc>…
  local label="$1"; shift
  local want; for want in "$@"; do [[ "$RC" == "$want" ]] && { pass "$label"; return; }; done
  fail "$label — rc=$RC want one of {$*} :: $(tail -n 3 "$TESTROOT/outs/$RSEQ.out" 2>/dev/null | tr '\n' '|')"
}
want_out() { # <label> <ere>
  if grep -qE "$2" <<<"$OUT"; then pass "$1"
  else fail "$1 — output lacks /$2/ :: $(tail -n 5 "$TESTROOT/outs/$RSEQ.out" 2>/dev/null | tr '\n' '|')"; fi
}
want_no_out() { # <label> <ere>
  if grep -qE "$2" <<<"$OUT"; then fail "$1 — output unexpectedly matches /$2/"
  else pass "$1"; fi
}
want_call() { # <label> <ere> — the invocation ledger must show it
  if grep -qE "$2" "$CALLS"; then pass "$1"
  else fail "$1 — call log lacks /$2/ :: $(tr '\n' '|' < "$CALLS")"; fi
}
want_no_call() { # <label> <ere>
  if grep -qE "$2" "$CALLS"; then fail "$1 — call log unexpectedly matches /$2/ :: $(tr '\n' '|' < "$CALLS")"
  else pass "$1"; fi
}
log_nonempty() { [[ -s "${1:-$CALLS}" ]]; }

# AFFECTED_GATE marker field extractor: the LAST `AFFECTED_GATE ` line (the REFUSED
# and BUDGET_DEFERRED markers carry a `_` after GATE and never match the space).
gate_field() { # <field> -> value
  sed -n 's/^.*AFFECTED_GATE \(.*\)$/\1/p' <<<"$OUT" | tail -n 1 \
    | tr ' ' '\n' | sed -n "s/^$1=//p" | head -n 1
}
want_field() { # <label> <field> <expected-value-or-ere>
  local got; got="$(gate_field "$2")"
  if [[ "$got" =~ ^$3$ ]]; then pass "$1"
  else fail "$1 — marker field $2='$got' want /^$3$/ :: $(grep -oE 'AFFECTED_GATE .*' <<<"$OUT" | tail -n 1)"; fi
}

# ================================ ROWS =======================================

printf '\n=== affected-tests.sh contract suite (#9307) ===\n'

# --- A1. SHOULD-PASS control: vitest repo, scoped diff, selected run -----------
# The unmutated fixture must be green before any mutation-row verdict means
# anything; a red control poisons every row below it.
R_CONTROL="$(mk_repo js-basic)"; seed_js "$R_CONTROL"; seal_base "$R_CONTROL"
commit_chg "$R_CONTROL" src/util.ts 'export const u = 1;'
reset_fakes
run_gate "$R_CONTROL" gate
CONTROL_OK=0
[[ "$RC" == "0" ]] && CONTROL_OK=1
want_rc 0 "A1 control: vitest fixture exits 0"
want_out "A1 control: human sentence" "Ran [0-9]+ of the repo's [0-9]+ test files affected by this change: passed\."
want_call "A1 control: vitest invoked in related form" 'vitest.*related'
want_call "A1 control: --run on the related call" 'vitest.*related.*--run'
want_call "A1 control: the changed file reaches the selector" 'related.*util\.ts'
want_field "A1 control: mode" mode 'selected'
want_field "A1 control: stack named" stack '.+'
want_out "A1 control: machine marker shape" 'AFFECTED_GATE ran=[0-9-]+ of=[0-9-]+ skipped=[0-9-]+ mode='
if [[ "$CONTROL_OK" != "1" ]]; then
  printf '  [CONTROL-RED] the unmutated fixture failed — every verdict below is suspect\n' >&2
fi

# --- A2. --explain prints the selection and runs nothing -----------------------
reset_fakes
run_gate "$R_CONTROL" explain --explain
want_rc 0 "A2: --explain exits 0"
if [[ -s "$CALLS" ]]; then fail "A2: --explain invoked a runner: $(tr '\n' '|' < "$CALLS")"; else pass "A2: --explain ran nothing"; fi
# The marker alone always carries reason=/mode= — pin the EXPLAIN-only lines:
# the base dump, the per-path classification, and the SELECTION verdict.
want_out "A2: --explain prints the base dump" 'AFFECTED_EXPLAIN base='
want_out "A2: --explain lists per-path reasons" 'PATH src/util\.ts class=changed'
want_out "A2: --explain prints the selection verdict" 'SELECTION mode=selected reason='

# --- A3. --self-check ----------------------------------------------------------
reset_fakes
run_gate "$R_CONTROL" selfcheck --self-check
want_rc 0 "A3: --self-check exits 0"
want_out "A3: self-check marker" 'AFFECTED_GATE_SELF_CHECK ok'

# ============================ Guard 2 — capability probe =======================

# B1 [G2-2 inverse, G2-1 inverse]: a runner registering --print-selection at a
# case-label position IS delegated to, and the stack adapters stay dark.
R_CAP="$(mk_repo capable)"; write_runner_capable "$R_CAP"; seed_js "$R_CAP"; seal_base "$R_CAP"
commit_chg "$R_CAP" src/util.ts 'export const u = 1;'
reset_fakes
run_gate "$R_CAP" gate
want_rc 0 "B1: capability-positive runner delegates cleanly"
want_call "B1: runner received --affected" 'test-all.*--affected'
want_no_call "B1: adapters stay dark under delegation" 'vitest	'
want_out "B1: a delegated pass still prints the verdict line" 'affected-suite gate passed\.'

# B1b: --full passthrough hands --full to the same runner.
reset_fakes
run_gate "$R_CAP" gate --full
want_rc 0 "B1b: --full passthrough exits 0"
want_call "B1b: runner received --full" 'test-all.*--full'
want_no_call "B1b: --full never reaches an adapter" 'vitest	'

# B2 [G2-3]: test_command outranks even a capability-positive runner.
R_CUST="$(mk_repo custom-cmd)"; write_runner_capable "$R_CUST"; seed_js "$R_CUST"
mkdir -p "$R_CUST/scripts"
cat > "$R_CUST/scripts/custom.sh" <<'FIX'
#!/usr/bin/env bash
printf 'custom\tcwd=%s\n' "$PWD" >> "${FAKE_LOG:?}"
exit 0
FIX
chmod +x "$R_CUST/scripts/custom.sh"
write_config "$R_CUST" '{"test_command": "bash scripts/custom.sh"}'
seal_base "$R_CUST"
commit_chg "$R_CUST" src/util.ts 'export const u = 1;'
reset_fakes
run_gate "$R_CUST" gate
want_rc 0 "B2: test_command fixture exits 0"
want_call "B2: the custom command ran from the repo root" "custom	cwd=$R_CUST"
want_no_call "B2: test_command bypasses the repo runner" 'test-all	'
want_no_call "B2: test_command bypasses adapters" 'vitest	'
want_field "B2: mode=custom" mode 'custom'

# B2b: --explain under test_command must answer BEFORE the arm runs — the custom
# command IS the whole selection; explain emits mode=custom + the command, rc 0.
reset_fakes
run_gate "$R_CUST" explain --explain
want_rc 0 "B2b: --explain under test_command exits 0"
want_out "B2b: explain reports mode=custom" 'mode=custom'
want_out "B2b: the configured command is printed" 'bash scripts/custom\.sh'
want_no_call "B2b: explain ran nothing (no command, no runner, no adapter)" 'custom|test-all|vitest'

# B3 [G2-1]: a foreign same-named runner is never handed Soleur flags — the diff
# falls through to the stack adapter.
R_FOR="$(mk_repo foreign)"; write_runner_foreign "$R_FOR"; seed_js "$R_FOR"; seal_base "$R_FOR"
commit_chg "$R_FOR" src/util.ts 'export const u = 1;'
reset_fakes
run_gate "$R_FOR" gate
want_rc 0 "B3: foreign-runner repo still gates green via the adapter"
want_no_call "B3: foreign runner never invoked" 'foreign-runner|test-all'
want_call "B3: the JS adapter ran instead" 'vitest.*related'

# B4 [G2-4]: a comment-only mention of --print-selection is not a registration.
R_COM="$(mk_repo comment-mention)"; write_runner_comment_mention "$R_COM"; seed_js "$R_COM"; seal_base "$R_COM"
commit_chg "$R_COM" src/util.ts 'export const u = 1;'
reset_fakes
run_gate "$R_COM" gate
want_rc 0 "B4: comment-mention repo gates green via the adapter"
want_no_call "B4: comment mention is not a capability" 'foreign-runner|test-all'
want_call "B4: the JS adapter ran instead" 'vitest.*related'

# B5 [G2-5 must-PASS]: usage-table-only registration still delegates.
R_UT="$(mk_repo usage-table)"; write_runner_usage_table "$R_UT"; seed_js "$R_UT"; seal_base "$R_UT"
commit_chg "$R_UT" src/util.ts 'export const u = 1;'
reset_fakes
run_gate "$R_UT" gate
want_rc 0 "B5: usage-table-only registration delegates cleanly"
want_call "B5: runner received --affected" 'test-all.*--affected'
want_no_call "B5: adapters stay dark under delegation" 'vitest	'

# B6 — delegated runner exit-code mapping (contract: its 4 → 4 runner-refused,
# its 3 → 1 runner-signal; a plain 1 stays 1).
reset_fakes; export FAKE_RUNNER_AFFECTED_RC=4
run_gate "$R_CAP" gate
want_rc 4 "B6a: runner rc 4 maps to gate rc 4"
want_out "B6a: runner-refused reason" 'AFFECTED_GATE_REFUSED.*reason=runner-refused'

reset_fakes; export FAKE_RUNNER_AFFECTED_RC=3
run_gate "$R_CAP" gate
want_rc 1 "B6b: runner rc 3 maps to gate rc 1"
want_out "B6b: runner-signal reason" 'runner-signal'

reset_fakes; export FAKE_RUNNER_AFFECTED_RC=1
run_gate "$R_CAP" gate
want_rc 1 "B6c: runner rc 1 stays rc 1"

# A runner usage/refusal rc 2 is a REFUSAL, not a plain failure — it must map
# to rc 4 runner-refused the same as the runner's own 4.
reset_fakes; export FAKE_RUNNER_AFFECTED_RC=2
run_gate "$R_CAP" gate
want_rc 4 "B6d: runner rc 2 maps to gate rc 4"
want_out "B6d: runner-refused reason" 'AFFECTED_GATE_REFUSED.*reason=runner-refused'

# B7 — the Soleur repo itself delegates: --explain in the real tree must resolve
# to the repo runner or name its mode. Bounded at 120 s (the affected pre-pass is
# measured ~150 s contended on a busy host, seconds here). REAL_NODE/REAL_PY are
# passed exactly as run_gate does: the real repo carries a .soleur-test-gate.json,
# and the shimmed interpreters must delegate the config dump or the gate reads a
# fake-unparseable config and refuses — a harness artifact, not a gate defect.
reset_fakes
# Portability: bound with the gate's own affected_timeout chain (timeout →
# gtimeout → watchdog) — a bare `timeout` is absent on stock macOS.
# shellcheck source=plugins/soleur/scripts/lib/affected-tests/common.sh
source "$DIR/lib/affected-tests/common.sh"
( cd "$REPO_ROOT" && affected_timeout 120 \
    env -u CLAUDE_PLUGIN_ROOT PATH="$BIN:$BASEPATH" FAKE_LOG="$CALLS" \
    REAL_NODE="$REAL_NODE" REAL_PY="$REAL_PY" \
    bash "$SUT" --explain ) > "$TESTROOT/outs/live.out" 2>&1
RC=$?; OUT="$(cat "$TESTROOT/outs/live.out")"
printf 'explain\t%s\t%s\n' "$RC" "$TESTROOT/outs/live.out" >> "$RUNS"
want_rc 0 "B7: --explain in the Soleur repo exits 0"
# mode=/delegat as bare alternation legs are vacuous (every marker carries
# mode=): require the EXPLAIN-only emitters — a delegation line or the
# adapter-arm explain dump.
want_out "B7: live explain resolves to the repo runner or names its mode" 'SELECTION mode=delegated|SELECTION mode=(selected|full|custom|none)|AFFECTED_EXPLAIN base='

# B8 [arch-P1 regression]: the capability probe runs BEFORE the gate's inert/
# global classification — an all-inert diff under a capability-positive runner
# still delegates, because the runner's own classifier (and its always-on
# ratchets, which are live edges on AGENTS.md/SKILL.md diffs) is strictly
# better informed. The gate-side inert shortcut is the adapter arm's alone.
R_MD_RUNNER="$(mk_repo inert-delegated)"; write_runner_capable "$R_MD_RUNNER"; seal_base "$R_MD_RUNNER"
commit_chg "$R_MD_RUNNER" README.md 'docs only'
reset_fakes
run_gate "$R_MD_RUNNER" gate
want_rc 0 "B8: md-only diff delegates to the capable runner"
want_call "B8: runner received --affected on an inert diff" 'test-all.*--affected'
want_no_out "B8: the gate's inert shortcut does not preempt delegation" 'NO_TESTS_AFFECTED|reason=inert'
want_field "B8: delegated marker reason" reason 'delegated'

# B8b: a global-paths diff delegates the same way — the runner's classifier
# outranks the gate's global table; only an operator --full maps to --full.
R_GLOB_RUNNER="$(mk_repo global-delegated)"; write_runner_capable "$R_GLOB_RUNNER"; seal_base "$R_GLOB_RUNNER"
commit_chg "$R_GLOB_RUNNER" package.json '{"name":"x","scripts":{"test":"true"}}'
reset_fakes
run_gate "$R_GLOB_RUNNER" gate
want_rc 0 "B8b: global-paths diff delegates"
want_call "B8b: runner received --affected, not --full" 'test-all.*--affected'
want_no_call "B8b: the gate's global table did not force --full" 'test-all.*--full'

# B8c: --explain under a capable runner reports the delegation and runs
# nothing — not even --print-selection (the runner's own pre-pass has a cost).
reset_fakes
run_gate "$R_MD_RUNNER" explain --explain
want_rc 0 "B8c: --explain under a capable runner exits 0"
want_out "B8c: explain reports the delegation" 'mode=delegated|test-all\.sh'
want_no_call "B8c: explain invoked nothing" 'test-all'

# ============================ Guard 3 — config fails closed ===================

mk_cfg_repo() { # <name> <json> — vitest repo whose config is committed in the BASE
                # (a config sitting in the diff would itself be an unclassified change)
  local r; r="$(mk_repo "$1")"; seed_js "$r"; write_config "$r" "$2"; seal_base "$r"
  commit_chg "$r" src/util.ts 'export const u = 1;'
  printf '%s' "$r"
}

# C1 [G3-3]: malformed JSON → rc 4 bad-config.
R_BADJSON="$(mk_cfg_repo cfg-malformed '{')"
reset_fakes; run_gate "$R_BADJSON" gate
want_rc 4 "C1: malformed config refused"
want_out "C1: bad-config reason" 'AFFECTED_GATE_REFUSED.*reason=bad-config'

# C2 [G3-1, G3-4]: unknown key → rc 4, and the reason must NAME the key — a
# validator that greps key names but never reads values cannot emit it.
R_UNK="$(mk_cfg_repo cfg-unknown '{"surprise_key": 1}')"
reset_fakes; run_gate "$R_UNK" gate
want_rc 4 "C2: unknown key refused"
want_out "C2: reason names the key" 'bad-config.*surprise_key|surprise_key.*bad-config'

# C3 [G3-2]: wrong type → rc 4 bad-config key=<k>.
R_WT="$(mk_cfg_repo cfg-wrong-type '{"budget_seconds": "900"}')"
reset_fakes; run_gate "$R_WT" gate
want_rc 4 "C3: string budget_seconds refused"
want_out "C3: reason names the key" 'bad-config.*budget_seconds|budget_seconds.*bad-config'
R_WT2="$(mk_cfg_repo cfg-wrong-type2 '{"global_paths": "src/**"}')"
reset_fakes; run_gate "$R_WT2" gate
want_rc 4 "C3b: string global_paths refused"
want_out "C3b: reason names the key" 'bad-config.*global_paths|global_paths.*bad-config'

# C4 [G3-5 must-PASS]: config carrying only max_workers is valid and caps width.
R_MW="$(mk_cfg_repo cfg-maxw '{"max_workers": 3}')"
reset_fakes; export FAKE_VITEST_MAXW=3
run_gate "$R_MW" gate
want_rc 0 "C4: max_workers-only config accepted"
want_call "C4: --maxWorkers honoured at the cap" 'vitest.*[Mm]ax.?[Ww]orkers'

# C5: inert_paths REPLACES built-ins — docs/** is inert, README.md no longer is.
# Inert-only diff: build the fixture WITHOUT the src/util.ts change mk_cfg_repo
# bakes in — the config sits in the base and the sole post-base change is inert.
R_INERT="$(mk_repo cfg-inert)"; seed_js "$R_INERT"
write_config "$R_INERT" '{"inert_paths": ["docs/**"]}'; seal_base "$R_INERT"
commit_chg "$R_INERT" docs/guide.txt 'docs'
reset_fakes; run_gate "$R_INERT" gate
want_rc 0 "C5a: all-inert custom diff exits 0"
want_out "C5a: NO_TESTS_AFFECTED" 'NO_TESTS_AFFECTED'
want_out "C5a: inert_rule reported" 'inert_rule='
R_INERT2="$(mk_cfg_repo cfg-inert2 '{"inert_paths": ["docs/**"]}')"
commit_chg "$R_INERT2" README.md 'readme change'
reset_fakes; run_gate "$R_INERT2" gate
want_no_out "C5b: README.md is NOT inert once inert_paths replaces the built-ins" 'NO_TESTS_AFFECTED'
want_rc_in "C5b: replaced-inert README diff is refused or falls back to full" 0 4
# `reason=|mode=full` is vacuous — every marker carries reason=. Pin the named
# non-refusal reason set: on rc 0 the verdict must disclose WHY it ran what it ran.
if [[ "$RC" == "0" ]]; then
  want_out "C5b: fallback discloses a named reason" 'reason=(ok|empty-selection|empty-diff|census-degraded|global-paths|full-requested|no-selector|custom-command|delegated)'
fi

# C6: a global_paths hit (package.json is a built-in) forces the full command.
R_GLOB="$(mk_repo global-hit)"; seed_js "$R_GLOB"; seal_base "$R_GLOB"
cat > "$R_GLOB/package.json" <<'JSON'
{ "name": "fixture-js", "private": true, "scripts": { "test": "vitest run" },
  "devDependencies": { "vitest": "^4.0.0" }, "x": 1 }
JSON
assert_fixture_dir "$R_GLOB"; git -C "$R_GLOB" add -A; git -C "$R_GLOB" commit -q -m "bump package.json"
reset_fakes; run_gate "$R_GLOB" gate
want_rc 0 "C6: global-path diff exits 0 via the full command"
want_field "C6: mode=full" mode 'full'
want_no_call "C6: no related selector under a global hit" 'related'
# A bare 'vitest|npm|…' leg is satisfied by the toolchain's --version probe —
# pin the invocation SHAPE of a test run, never the probe.
want_call "C6: the full command did run" 'vitest	run |npm	test|pnpm	test|yarn	test|bun	test'

# C7 [G1-7]: vacuous test_command values → rc 4 vacuous-test-command, each
# spelling — INCLUDING the composition bypasses: a true-swallower tail
# (`|| true`, `; exit 0`, `| true`), exit-inside-subcommand, comment padding.
for _vac in 'true' ':' 'exit 0' 'echo' \
            'npm test || true' 'npm test || :' 'make test; exit 0' \
            'pytest && true' 'npm test | true' \
            "bash -c 'exit 0'" 'sh -c "exit 0"' 'true # comment' \
            'echo done; exit 0' 'env X=1 bash -c "exit 0"'; do
  _r="$(mk_cfg_repo "cfg-vac-$(printf '%s' "$_vac" | tr -c 'a-z0-9' '_' | head -c 40)" "{\"test_command\": \"$(printf '%s' "$_vac" | sed 's/"/\\"/g')\"}")"
  reset_fakes; run_gate "$_r" gate
  want_rc 4 "C7: test_command '$_vac' refused"
  want_out "C7: vacuous reason for '$_vac'" 'AFFECTED_GATE_REFUSED.*reason=vacuous-test-command'
done
unset _vac _r
# C7b must-PASS: a real command still runs — `echo` mid-command is not a
# swallower when the LAST segment is substantive.
R_VACOK="$(mk_cfg_repo cfg-vac-ok '{"test_command": "echo running && bash scripts/custom.sh"}')"
mkdir -p "$R_VACOK/scripts"
cat > "$R_VACOK/scripts/custom.sh" <<'FIX'
#!/usr/bin/env bash
printf 'custom\tcwd=%s\n' "$PWD" >> "${FAKE_LOG:?}"
exit 0
FIX
chmod +x "$R_VACOK/scripts/custom.sh"
assert_fixture_dir "$R_VACOK"; git -C "$R_VACOK" add -A; git -C "$R_VACOK" commit -q -m "add custom runner"
reset_fakes; run_gate "$R_VACOK" gate
want_rc 0 "C7b: substantive test_command accepted"
want_call "C7b: the custom command ran" 'custom	cwd='

# C8: non-positive budget_seconds / max_workers fail closed as bad-config — a
# zero budget would defer instantly and a non-positive width is nonsense.
R_CL1="$(mk_cfg_repo cfg-budget-zero '{"budget_seconds": 0}')"
reset_fakes; run_gate "$R_CL1" gate
want_rc 4 "C8a: budget_seconds=0 refused"
want_out "C8a: reason names the key" 'bad-config.*budget_seconds|budget_seconds.*bad-config'
R_CL2="$(mk_cfg_repo cfg-maxw-neg '{"max_workers": -2}')"
reset_fakes; run_gate "$R_CL2" gate
want_rc 4 "C8b: negative max_workers refused"
want_out "C8b: reason names the key" 'bad-config.*max_workers|max_workers.*bad-config'
want_out "C8b: refusal carries a remedy pointer" 'remedy:'

# C9: a match-everything inert_paths pattern is a permanent green — refused as
# bad-config, never silently applied. `*`/`**`/`**/*` and any pattern that
# matches an arbitrary probe path all fail closed.
_ipn=0
for _ip in '*' '**' '**/*' '*/**'; do
  _ipn=$((_ipn + 1))  # `**/*` and `*/**` both sanitise to `____` — index the name
  _r="$(mk_cfg_repo "cfg-inertstar-${_ipn}" "{\"inert_paths\": [\"$_ip\"]}")"
  reset_fakes; run_gate "$_r" gate
  want_rc 4 "C9: inert_paths '$_ip' refused"
  want_out "C9: refusal names inert_paths for '$_ip'" 'bad-config.*inert_paths|inert_paths.*bad-config'
  want_no_call "C9: nothing ran for '$_ip'" 'vitest	'
done
unset _ip _r _ipn
# C9b must-PASS: a real inert pattern still classifies (docs/** inert over a
# docs-only diff → NO_TESTS_AFFECTED, same shape as C5a).
R_INOK="$(mk_repo cfg-inert-ok)"; seed_js "$R_INOK"
write_config "$R_INOK" '{"inert_paths": ["docs/**", "notes.txt"]}'; seal_base "$R_INOK"
commit_chg "$R_INOK" docs/guide.md 'docs'
reset_fakes; run_gate "$R_INOK" gate
want_rc 0 "C9b: a non-total inert_paths set is accepted"
want_out "C9b: inert verdict" 'NO_TESTS_AFFECTED'

# C10: the jq config decoder actually DECODES — a jq-only host (no python3, no
# node on PATH) must still honour test_command. Literal NULs in the jq program
# were stripped by bash before this row existed; the pinned engine is real jq.
JQBIN="$TESTROOT/bin-jqonly"; mkdir -p "$JQBIN"
for _t in jq git bash env grep find sed awk sort sort tr cut head tail cat date \
          sleep ps getconf sysctl mktemp rm wc dirname basename uname comm ls \
          mkdir chmod touch printf od; do
  _p="$(command -v "$_t" 2>/dev/null || true)"
  [[ -n "$_p" && "$_p" != "$BIN"/* ]] && ln -sf "$_p" "$JQBIN/$_t"
done
for _t in vitest jest pytest go nx turbo npm npx pnpm yarn bun bunx; do
  ln -sf "$BIN/$_t" "$JQBIN/$_t"
done
if [[ -x "$JQBIN/jq" && -x "$JQBIN/git" && -x "$JQBIN/bash" ]]; then
  R_JQONLY="$(mk_repo jq-only)"; seed_js "$R_JQONLY"
  mkdir -p "$R_JQONLY/scripts"
  cat > "$R_JQONLY/scripts/custom.sh" <<'FIX'
#!/usr/bin/env bash
printf 'custom\tcwd=%s\n' "$PWD" >> "${FAKE_LOG:?}"
exit 0
FIX
  chmod +x "$R_JQONLY/scripts/custom.sh"
  write_config "$R_JQONLY" '{"test_command": "bash scripts/custom.sh"}'
  seal_base "$R_JQONLY"
  commit_chg "$R_JQONLY" src/util.ts 'export const u = 1;'
  reset_fakes
  run_gate_path "$JQBIN" "$R_JQONLY" gate
  want_rc 0 "C10: jq-only host parses the config"
  want_field "C10: jq decode reached the custom arm" mode 'custom'
  want_call "C10: the configured command ran" 'custom	cwd='
else
  fail "C10: cannot build the jq-only PATH fixture (missing jq/git/bash on host)"
fi
unset _t _p

# C10b: a top-level NON-OBJECT config must refuse identically on every decoder.
# py/node exit 3 on `[]`; a bare jq `to_entries` over `[]` decodes to ZERO
# records — a silent accept (no keys, no badkey) unless the jq arm checks
# `type == "object"` first. rc 4 bad-config is the contract.
if [[ -x "$JQBIN/jq" && -x "$JQBIN/git" && -x "$JQBIN/bash" ]]; then
  R_JQARR="$(mk_repo jq-array)"; seed_js "$R_JQARR"
  write_config "$R_JQARR" '[]'
  seal_base "$R_JQARR"
  commit_chg "$R_JQARR" src/util.ts 'export const u = 1;'
  reset_fakes
  run_gate_path "$JQBIN" "$R_JQARR" gate
  want_rc 4 "C10b: jq-only host refuses a top-level array config"
  want_out "C10b: bad-config reason" 'AFFECTED_GATE_REFUSED.*reason=bad-config'
fi

# ============================ Guard 1 — no vacuous green =======================

# D1: an all-inert diff (README.md only) is the ONLY rc-0-with-zero-tests path.
R_MD="$(mk_repo inert-md)"; seed_js "$R_MD"; seal_base "$R_MD"
commit_chg "$R_MD" README.md 'docs only'
reset_fakes; run_gate "$R_MD" gate
want_rc 0 "D1: docs-only diff exits 0"
want_out "D1: NO_TESTS_AFFECTED" 'NO_TESTS_AFFECTED'
want_out "D1: human inert line" 'No tests ran: docs-only change\.'
want_out "D1: inert_rule reported" 'inert_rule='
if [[ -s "$CALLS" ]]; then fail "D1: inert diff invoked a runner: $(tr '\n' '|' < "$CALLS")"; else pass "D1: inert diff ran nothing"; fi

# D2 [G1-3]: inert-then-code — a first-path inert shortcut would swallow src/util.ts.
R_MIX="$(mk_repo mixed)"; seed_js "$R_MIX"; seal_base "$R_MIX"
commit_chg "$R_MIX" README.md 'docs'
commit_chg "$R_MIX" src/util.ts 'export const u = 1;'
reset_fakes; run_gate "$R_MIX" gate
want_rc 0 "D2: mixed diff exits 0 via real selection"
want_no_out "D2: mixed diff is never inert" 'NO_TESTS_AFFECTED'
want_call "D2: the code file was selected" 'related.*util\.ts'

# D3 [G1-1]: the native selector returns nothing for a code diff → full fallback,
# never a zero-test green. rc 0 is acceptable ONLY with mode=full and a named
# reason; rc 4 is an acceptable loud refusal.
R_EMPTY="$(mk_repo empty-sel)"; seed_js "$R_EMPTY"; seal_base "$R_EMPTY"
commit_chg "$R_EMPTY" src/orphan.ts 'export const o = 1;'
reset_fakes; export FAKE_VITEST_NOTESTS=1
run_gate "$R_EMPTY" gate
if [[ "$RC" == "0" ]]; then
  pass "D3: empty selection resolved to a completed run"
  # Contract: the full command ran and the fallback is DISCLOSED. mode=full is
  # one spelling; mode=selected with reason=empty-selection is accepted too —
  # a bare green with no named reason is the only failure.
  want_out "D3: the empty-selection fallback is disclosed" 'reason=[^ ]*(empty|no.test|select)|mode=full'
elif [[ "$RC" == "4" ]]; then
  pass "D3: empty selection refused loudly (rc 4)"
else
  fail "D3: empty selection produced rc=$RC — a zero-test rc 0 is the Guard-1 defect"
fi

# D3b: an unclassifiable changed file (not inert, not global, not a test or source
# path) yields an empty native selection on the Python adapter → full fallback.
R_EMPTY2="$(mk_repo empty-sel-py)"; seed_python "$R_EMPTY2"; seal_base "$R_EMPTY2"
commit_chg "$R_EMPTY2" assets/logo.svg '<svg/>'
reset_fakes; run_gate "$R_EMPTY2" gate
if [[ "$RC" == "0" ]]; then
  want_call "D3b: pytest ran the suite" 'pytest	'
  # `reason=|mode=full` is vacuous — the disclosure must be a NAMED fallback
  # reason, not the mere presence of the marker's reason field.
  want_out "D3b: a named fallback reason is disclosed" 'reason=(empty-selection|no-selector)|mode=full'
else
  want_rc_in "D3b: unclassifiable diff is refused or falls back" 4
fi

# D4: tests exist but no stack resolves → rc 4 no-stack. The fixture file must
# match the test-file census shape (`*.test.*`) — a plain `.rb` name is
# invisible to it and would land on rc 7 no-tests instead, which is why the
# filename carries the marker.
R_RB="$(mk_repo no-stack)"; seal_base "$R_RB"
mkdir -p "$R_RB/test"; printf 'def test_w; end\n' > "$R_RB/test/test_widget.test.rb"
assert_fixture_dir "$R_RB"; git -C "$R_RB" add -A; git -C "$R_RB" commit -q -m "ruby tests"
reset_fakes; run_gate "$R_RB" gate
# Deterministic: the census sees a test file, no adapter resolves, no foreign
# runner → rc 4 reason=no-stack. Never a hedged 4-or-7.
want_rc 4 "D4: tests-exist-but-no-stack refuses (rc 4)"
want_out "D4: no-stack reason" 'AFFECTED_GATE_REFUSED.*reason=no-stack'
want_no_out "D4: never labelled passed" 'passed\.|tests verified'

# D5 [G1-2]: no runner on PATH at all → rc 4, never a silent 0. The fixture has
# no node_modules/.bin — a repo-local copy would resolve the shim anyway.
R_NOPATH="$(mk_repo no-path)"; seed_js_nobin "$R_NOPATH"; seal_base "$R_NOPATH"
commit_chg "$R_NOPATH" src/util.ts 'export const u = 1;'
reset_fakes
run_gate_path "/usr/bin:/bin" "$R_NOPATH" gate
want_rc 4 "D5: toolchain-missing PATH is refused"
want_out "D5: refusal emitted" 'AFFECTED_GATE_REFUSED'

# D6: no test suite detected at all → rc 7 with a disclosed note, never "passed".
R_NONE="$(mk_repo no-suite)"; seal_base "$R_NONE"
commit_chg "$R_NONE" src/plain.txt 'data'
reset_fakes; run_gate "$R_NONE" gate
want_rc 7 "D6: no test suite detected → rc 7"
want_no_out "D6: rc 7 is never labelled passed" 'passed\.|tests verified'

# D7: the changed set is committed ∪ staged ∪ unstaged ∪ untracked.
R_UN="$(mk_repo union)"; seed_python "$R_UN"; seal_base "$R_UN"
printf 'def test_a():\n    assert 1 + 1 == 2\n' > "$R_UN/tests/test_a.py"   # unstaged mod
assert_fixture_dir "$R_UN"; printf 'def test_b():\n    assert True\n' > "$R_UN/tests/test_b.py"; git -C "$R_UN" add tests/test_b.py  # staged
printf 'def test_c():\n    assert True\n' > "$R_UN/tests/test_c.py"   # untracked
reset_fakes; export FAKE_PYTEST_EXPECT="test_a.py test_b.py test_c.py"
run_gate "$R_UN" gate
want_rc 0 "D7: staged+unstaged+untracked union runs green"
want_call "D7: unstaged file selected" 'test_a\.py'
want_call "D7: staged file selected" 'test_b\.py'
want_call "D7: untracked file selected" 'test_c\.py'
# Unit integrity: ran/of both count test FILES — the 3 changed test files ran
# out of a 3-file census (pytest's `collected N items` is items, not the count).
want_field "D7: ran is in file units" ran '3'
want_field "D7: of is the repo census" of '3'

# D8: --base overrides resolution — only the LAST commit's files are selected.
R_BASE="$(mk_repo base-flag)"; seed_js "$R_BASE"; seal_base "$R_BASE"
commit_chg "$R_BASE" src/first.ts 'export const f = 1;'
commit_chg "$R_BASE" src/second.ts 'export const s = 1;'
reset_fakes
run_gate "$R_BASE" gate --base HEAD~1
want_rc 0 "D8: --base override exits 0"
_rel="$(grep 'related' "$CALLS" | head -n 1)"
if [[ "$_rel" == *second.ts* && "$_rel" != *first.ts* ]]; then
  pass "D8: selection is scoped to the --base ref"
else
  fail "D8: related argv not scoped to HEAD~1: $_rel"
fi
unset _rel
reset_fakes
run_gate "$R_BASE" gate --base refs/heads/definitely-missing
want_rc 4 "D8b: an unresolvable --base is refused"
want_out "D8b: refusal emitted" 'AFFECTED_GATE_REFUSED'

# D9: shallow clone whose one bounded deepen cannot recover a base → rc 4
# no-base-ref, never a silent full and never a silent empty.
R_SHSRC="$(mk_repo shallow-src)"; seed_js "$R_SHSRC"
assert_fixture_dir "$R_SHSRC"; git -C "$R_SHSRC" add -A; git -C "$R_SHSRC" commit -q -m "base"
R_SHALLOW="$WORLD/repos/shallow"
git clone -q --depth 1 "file://$R_SHSRC" "$R_SHALLOW" 2>/dev/null
git -C "$R_SHALLOW" config user.email soleur-test@example.invalid
git -C "$R_SHALLOW" config user.name "Soleur Fixture"
git -C "$R_SHALLOW" config commit.gpgsign false
git -C "$R_SHALLOW" remote set-url origin "$WORLD/remotes/definitely-missing.git"
while IFS= read -r _ref; do git -C "$R_SHALLOW" update-ref -d "$_ref"; done \
  < <(git -C "$R_SHALLOW" for-each-ref --format='%(refname)' refs/remotes/)
git -C "$R_SHALLOW" branch --unset-upstream 2>/dev/null || true
reset_fakes
run_gate "$R_SHALLOW" gate
want_rc 4 "D9: shallow clone with unrecoverable base is refused"
want_out "D9: no-base-ref reason" 'AFFECTED_GATE_REFUSED.*reason=no-base-ref'
want_no_out "D9: never a silent full on a dead base" 'mode=full'

# D9b [census legs]: a census leg that fails toward empty must NEVER silently
# narrow the selection — the untracked leg is the worst case (a dead
# `ls-files --others` drops every NEW test file). The contract: forced full +
# a disclosed reason=census-degraded. A scoped git shim fails ONLY the
# untracked leg, and only while armed — all other git calls delegate to the
# real binary.
GITFAILBIN="$TESTROOT/bin-gitfail"; mkdir -p "$GITFAILBIN"
ln -sf "$BIN"/* "$GITFAILBIN/"
cat > "$GITFAILBIN/git" <<'SHIM'
#!/usr/bin/env bash
if [[ "${FAKE_GIT_FAIL_OTHERS:-0}" == "1" ]]; then
  _ls=0; _oth=0
  for _a in "$@"; do
    [[ "$_a" == "ls-files" ]] && _ls=1
    [[ "$_a" == "--others" ]] && _oth=1
  done
  if (( _ls && _oth )); then
    echo "stub git: simulated ls-files --others failure" >&2
    exit 1
  fi
fi
exec "${REAL_GIT:?REAL_GIT unset}" "$@"
SHIM
chmod +x "$GITFAILBIN/git"
R_CFAIL="$(mk_repo census-degraded)"; seed_js "$R_CFAIL"; seal_base "$R_CFAIL"
commit_chg "$R_CFAIL" src/util.ts 'export const u = 1;'
# An UNTRACKED test file — exactly what a masked ls-files leg would drop.
printf 'import { test } from "vitest";\ntest("n", () => {});\n' > "$R_CFAIL/src/new.test.ts"
reset_fakes; export FAKE_GIT_FAIL_OTHERS=1
run_gate_path "$GITFAILBIN:$BASEPATH" "$R_CFAIL" gate
want_rc 0 "D9b: a failed untracked census leg degrades to full — never narrows"
want_field "D9b: mode=full" mode 'full'
want_out "D9b: census-degraded reason disclosed" 'reason=census-degraded'
want_call "D9b: the full command ran" 'vitest	run '
want_no_call "D9b: no related selection on a degraded census" 'related'

# ============================ adapters =========================================

# D15: jest — --findRelatedTests <files>; the __tests__ convention counts in of=.
R_JEST="$(mk_repo jest-repo)"; seed_jest "$R_JEST"
mkdir -p "$R_JEST/src/__tests__"; printf 'test("x", () => {});\n' > "$R_JEST/src/__tests__/x.js"
seal_base "$R_JEST"
commit_chg "$R_JEST" src/util.ts 'export const u = 1;'
reset_fakes; export FAKE_JEST_REQUIRE_RELATED=1
run_gate "$R_JEST" gate
want_rc 0 "D15: jest fixture exits 0"
want_call "D15: jest selector is --findRelatedTests" 'jest.*--findRelatedTests'
want_call "D15: the changed file reaches jest" 'findRelatedTests.*util\.ts'
want_field "D15: of= counts __tests__ files too" of '2'

# D16 [G1-9]: go — a leaf change must pull the reverse-dependency closure; the
# changed package alone is the mutation this row exists to refuse.
R_GO="$(mk_repo go-repo)"; seed_go "$R_GO" "$TESTROOT/go-graph"; seal_base "$R_GO"
commit_chg "$R_GO" internal/leaf/leaf.go 'package leaf\n\nfunc Leaf() int { return 2 }'
reset_fakes; export FAKE_GO_DIR="$TESTROOT/go-graph" FAKE_GO_EXPECT="internal/leaf cmd/app"
run_gate "$R_GO" gate
want_rc 0 "D16: go fixture exits 0"
want_call "D16: leaf package under test" 'go.*test.*internal/leaf'
want_call "D16: reverse dependent under test" 'go.*test.*cmd/app'
# Unit integrity: two PACKAGES ran but only one test FILE exists — ran is in
# file units like of= (packages≠files was the original unit-divergence defect).
want_field "D16: ran counts test files not packages" ran '1'
want_field "D16: of is the repo census" of '1'

# D17: nx.json wins over package.json.
R_NX="$(mk_repo nx-repo)"; seed_nx "$R_NX"; seal_base "$R_NX"
commit_chg "$R_NX" src/util.ts 'export const u = 1;'
reset_fakes; run_gate "$R_NX" gate
want_rc 0 "D17: nx fixture exits 0"
want_call "D17: nx affected ran" 'nx.*affected'
want_no_call "D17: vitest stays dark under nx" 'vitest	'

# D17b: a scheduler reporting "10 tasks" is NOT the vacuous "0 tasks" shape —
# an unanchored '0 tasks' grep matches inside the count and false-flags the run
# as empty, triggering a spurious full retry.
reset_fakes; export FAKE_NX_LINE="Successfully ran target test for 10 tasks"
run_gate "$R_NX" gate
want_rc 0 "D17b: nx '10 tasks' run exits 0"
want_call "D17b: nx affected ran" 'nx.*affected'
want_no_call "D17b: no vacuous full-retry on a real task count" 'nx.*run-many'

# D17c: a NUMERIC ran=0 (`0 successful` — a spelling the phrase grep misses) is
# vacuous the same as `0 tasks` → empty-selection full retry, never a pass.
reset_fakes; export FAKE_NX_LINE="Tasks: 0 successful" FAKE_NX_FULL_LINE="nx run-many: ran target test for 3 projects"
run_gate "$R_NX" gate
want_rc 0 "D17c: nx numeric-zero selection retries full"
want_call "D17c: the full retry ran" 'nx.*run-many'
want_out "D17c: the escalation is disclosed" 'empty-selection|mode=full'

# D18: turbo.json wins over package.json.
R_TB="$(mk_repo turbo-repo)"; seed_turbo "$R_TB"; seal_base "$R_TB"
commit_chg "$R_TB" src/util.ts 'export const u = 1;'
reset_fakes; run_gate "$R_TB" gate
want_rc 0 "D18: turbo fixture exits 0"
want_call "D18: turbo run test ran" 'turbo.*run.*test'
want_no_call "D18: vitest stays dark under turbo" 'vitest	'

# D10/D11: Python source diffs — pytest-testmon when importable, else full suite.
R_PYSRC="$(mk_repo py-src)"; seed_python "$R_PYSRC"; seal_base "$R_PYSRC"
commit_chg "$R_PYSRC" src/mod.py 'def f():\n    return 2'
reset_fakes; run_gate "$R_PYSRC" gate
want_rc 0 "D10: source diff without testmon runs the suite"
# 'pytest' bare matches the `python3 -c 'import pytest'` probe line too —
# anchor on the tool's own ledger slot.
want_call "D10: pytest invoked" 'pytest	'
want_field "D10: full-escalation ran equals the census" ran '1'
want_field "D10: census" of '1'
R_PYTM="$(mk_repo py-testmon)"; seed_python "$R_PYTM"; seal_base "$R_PYTM"
commit_chg "$R_PYTM" src/mod.py 'def f():\n    return 2'
reset_fakes; export FAKE_PY_IMPORTABLE="pytest testmon pytest_testmon"
run_gate "$R_PYTM" gate
want_rc 0 "D11: testmon-importable source diff exits 0"
# A bare `testmon` grep is satisfied by the import-PROBE ledger line
# (`python3 -I -c 'import pytest_testmon'`) — pin the RUN argv instead:
# `pytest\t--testmon …` (the pytest stub re-logs under either tool spelling).
want_call "D11: the testmon selection ran (--testmon argv, not the probe)" 'pytest	.*--testmon'
# testmon's file count is not derivable from `collected N / M deselected`
# (items, not files) — the honest marker is ran=-, and the pass verdict still
# prints because a real run happened.
want_field "D11: testmon ran is honestly unknown" ran '-'
want_out "D11: pass verdict prints despite opaque tally" 'affected-suite gate passed\.'

# D12/D13: pytest -n auto iff pytest-xdist imports, else serial with a reason.
R_PYXD="$(mk_repo py-xdist)"; seed_python "$R_PYXD"; seal_base "$R_PYXD"
commit_chg "$R_PYXD" tests/test_a.py 'def test_a():\n    assert 1 + 1 == 2'
reset_fakes; export FAKE_PY_IMPORTABLE="pytest xdist"
run_gate "$R_PYXD" gate
want_rc 0 "D12: xdist fixture exits 0"
want_call "D12: xdist parallelism enabled (-n auto or a width)" 'pytest.*-n(=| )?(auto|[0-9]+)'
R_PYSE="$(mk_repo py-serial)"; seed_python "$R_PYSE"; seal_base "$R_PYSE"
commit_chg "$R_PYSE" tests/test_a.py 'def test_a():\n    assert 1 + 1 == 2'
reset_fakes; export FAKE_PY_IMPORTABLE="pytest"
run_gate "$R_PYSE" gate
want_rc 0 "D13: serial fixture exits 0"
want_no_call "D13: no -n width without xdist" 'pytest.*-n(=| )'
if grep -qiE 'serial|xdist' <<<"$OUT"; then
  pass "D13: serial reason is stated"
else
  fail "D13: serial run without a stated reason"
fi

# D14 [G1-5]: pytest rc 5 (no tests collected) is NOT a pass.
R_PY5="$(mk_repo py-rc5)"; seed_python "$R_PY5"; seal_base "$R_PY5"
commit_chg "$R_PY5" tests/test_a.py 'def test_a():\n    assert 1 + 1 == 2'
reset_fakes; export FAKE_PYTEST_RC=5
run_gate "$R_PY5" gate
want_rc_in "D14: pytest rc 5 is never green" 1 4
want_no_out "D14: no 'passed' claim on an empty collection" 'Ran .* passed\.|tests verified'

# D24: a bare pyproject.toml is a Python-PROJECT marker, not a pytest-SUITE
# marker — without a pytest signal in a manifest and without test_*.py files,
# the py adapter must not claim the repo.
R_PYNO="$(mk_repo py-nosignal)"
printf '[project]\nname = "fixture-lib"\n' > "$R_PYNO/pyproject.toml"
mkdir -p "$R_PYNO/src"; printf 'def f():\n    return 1\n' > "$R_PYNO/src/lib.py"
seal_base "$R_PYNO"
commit_chg "$R_PYNO" src/lib.py 'def f():\n    return 2'
reset_fakes; run_gate "$R_PYNO" gate
want_rc 7 "D24: pytest-signal-free pyproject.toml is not a py detection"
want_no_call "D24: pytest never invoked" 'pytest	'

# D19 [G1-6]: multi-stack — an empty adapter cannot launder or sink the other.
R_MS="$(mk_repo multi-stack)"; seed_python "$R_MS"
seed_go "$R_MS" "$TESTROOT/go-graph-ms"
seal_base "$R_MS"
commit_chg "$R_MS" src/mod.py 'def f():\n    return 3'
reset_fakes; export FAKE_GO_DIR="$TESTROOT/go-graph-ms"
run_gate "$R_MS" gate
want_rc 0 "D19a: py-only diff in a py+go repo exits 0"
want_call "D19a: pytest ran" 'pytest	'
# Both adapters produce honest FILE counts on this path — `ran=-` (opaque
# tally) is a counted-path lie and must not satisfy this row.
want_out "D19a: the run is counted non-empty" 'AFFECTED_GATE ran=[1-9][0-9]* of=[1-9][0-9]*'
commit_chg "$R_MS" internal/leaf/leaf.go 'package leaf\n\nfunc Leaf() int { return 3 }'
reset_fakes; export FAKE_PYTEST_RC=1 FAKE_GO_DIR="$TESTROOT/go-graph-ms" FAKE_GO_EXPECT="internal/leaf cmd/app"
run_gate "$R_MS" gate
want_rc 1 "D19b: one failing stack dominates the aggregate (1 > 4 > 6 > 0)"

# ============================ budget + CI ======================================

# D20a [P6]: CI workflow detected + budget expires → rc 6 BUDGET_DEFERRED.
R_BUD="$(mk_repo budget-ci)"; seed_js "$R_BUD"; seed_ci "$R_BUD"
write_config "$R_BUD" '{"budget_seconds": 1}'
seal_base "$R_BUD"
commit_chg "$R_BUD" src/util.ts 'export const u = 1;'
reset_fakes; export FAKE_VITEST_SLEEP=5
run_gate "$R_BUD" gate
want_rc 6 "D20a: expired budget with CI detected defers"
want_out "D20a: deferral marker" 'AFFECTED_GATE_BUDGET_DEFERRED'
want_field "D20a: ci field names the workflow" ci '.*\.yml|.*workflows.*'

# D20b [G1-8]: a failure BEFORE expiry wins over deferral. A 1 s budget makes
# this racy (gate startup can eat the deadline before the run starts), so this
# arm gets a larger budget — the failure still lands first, deterministically.
R_BUDF="$(mk_repo budget-fail-first)"; seed_js "$R_BUDF"; seed_ci "$R_BUDF"
write_config "$R_BUDF" '{"budget_seconds": 120}'
seal_base "$R_BUDF"
commit_chg "$R_BUDF" src/util.ts 'export const u = 1;'
reset_fakes; export FAKE_VITEST_RC=1
run_gate "$R_BUDF" gate
want_rc 1 "D20b: failure before budget expiry is rc 1"
want_no_out "D20b: no deferral when a failure already landed" 'AFFECTED_GATE_BUDGET_DEFERRED'

# D20c [G1-4]: no CI detected → the budget is ignored and the run completes.
R_NOCI="$(mk_repo budget-noci)"; seed_js "$R_NOCI"
write_config "$R_NOCI" '{"budget_seconds": 1}'
seal_base "$R_NOCI"
commit_chg "$R_NOCI" src/util.ts 'export const u = 1;'
reset_fakes; export FAKE_VITEST_SLEEP=3
run_gate "$R_NOCI" gate
want_rc 0 "D20c: budget ignored without CI — run completes"
want_no_out "D20c: no deferral without CI" 'AFFECTED_GATE_BUDGET_DEFERRED'
# `ci=none` is unconditional on every no-CI run's marker — pin the upfront
# disclosure sentence itself, not the marker field.
if grep -qiE 'no CI test workflow detected|budget not enforced' <<<"$OUT"; then
  pass "D20c: the no-CI disregard is disclosed"
else
  fail "D20c: budget ignored without the upfront no-CI line"
fi

# D20d: budget_ci: true forces deferral eligibility without a workflow file.
R_BCI="$(mk_repo budget-ci-flag)"; seed_js "$R_BCI"
write_config "$R_BCI" '{"budget_ci": true, "budget_seconds": 1}'
seal_base "$R_BCI"
commit_chg "$R_BCI" src/util.ts 'export const u = 1;'
reset_fakes; export FAKE_VITEST_SLEEP=5
run_gate "$R_BCI" gate
want_rc 6 "D20d: budget_ci=true defers without a workflow file"
want_out "D20d: deferral marker" 'AFFECTED_GATE_BUDGET_DEFERRED'

# D20e [trigger anchor]: `push`/`pull_request` as a SUBSTRING inside a run:
# step is not a trigger declaration — `git push` and `pushd` in a deploy
# workflow must not arm the budget. The workflow below carries a real
# test-command shape too, so only the anchored `on:` check keeps this dark.
R_CIPUSH="$(mk_repo ci-push-substring)"; seed_js "$R_CIPUSH"
mkdir -p "$R_CIPUSH/.github/workflows"
cat > "$R_CIPUSH/.github/workflows/deploy.yml" <<'YML'
name: deploy
on: workflow_dispatch
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - run: npm test
      - run: git push origin main
      - run: pushd dist && ./publish.sh
YML
write_config "$R_CIPUSH" '{"budget_seconds": 1}'
seal_base "$R_CIPUSH"
commit_chg "$R_CIPUSH" src/util.ts 'export const u = 1;'
reset_fakes; export FAKE_VITEST_SLEEP=5
run_gate "$R_CIPUSH" gate
want_rc 0 "D20e: push-in-a-run-step is not a CI trigger — budget stays unarmed"
want_no_out "D20e: no deferral without a declared trigger" 'AFFECTED_GATE_BUDGET_DEFERRED'
want_field "D20e: ci field is none" ci 'none'
want_out "D20e: the no-CI disregard is disclosed" 'no CI test workflow detected'

# D20f [trigger anchor, positive]: flow-style `on: [push]` IS a declaration.
R_CIFLOW="$(mk_repo ci-flow)"; seed_js "$R_CIFLOW"
mkdir -p "$R_CIFLOW/.github/workflows"
cat > "$R_CIFLOW/.github/workflows/ci.yml" <<'YML'
name: ci
on: [push, workflow_dispatch]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - run: npm test
YML
write_config "$R_CIFLOW" '{"budget_seconds": 1}'
seal_base "$R_CIFLOW"
commit_chg "$R_CIFLOW" src/util.ts 'export const u = 1;'
reset_fakes; export FAKE_VITEST_SLEEP=5
run_gate "$R_CIFLOW" gate
want_rc 6 "D20f: flow-style on: [push] detects CI and defers"
want_out "D20f: deferral marker" 'AFFECTED_GATE_BUDGET_DEFERRED'
want_field "D20f: ci field names the workflow" ci '.*\.yml'

# D20g [trigger anchor, positive]: block-map `push:` key inside the `on:` block
# — and a block-sequence `- pull_request` entry — both declare triggers.
R_CIBLK="$(mk_repo ci-block)"; seed_js "$R_CIBLK"
mkdir -p "$R_CIBLK/.github/workflows"
cat > "$R_CIBLK/.github/workflows/ci.yml" <<'YML'
name: ci
on:
  push:
    branches: [main]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - run: npm test
YML
write_config "$R_CIBLK" '{"budget_seconds": 1}'
seal_base "$R_CIBLK"
commit_chg "$R_CIBLK" src/util.ts 'export const u = 1;'
reset_fakes; export FAKE_VITEST_SLEEP=5
run_gate "$R_CIBLK" gate
want_rc 6 "D20g: block-map push: trigger detects CI and defers"
want_out "D20g: deferral marker" 'AFFECTED_GATE_BUDGET_DEFERRED'

R_CISEQ="$(mk_repo ci-seq)"; seed_js "$R_CISEQ"
mkdir -p "$R_CISEQ/.github/workflows"
cat > "$R_CISEQ/.github/workflows/ci.yml" <<'YML'
name: ci
on:
  - pull_request
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - run: npm test
YML
write_config "$R_CISEQ" '{"budget_seconds": 1}'
seal_base "$R_CISEQ"
commit_chg "$R_CISEQ" src/util.ts 'export const u = 1;'
reset_fakes; export FAKE_VITEST_SLEEP=5
run_gate "$R_CISEQ" gate
want_rc 6 "D20h: block-sequence - pull_request trigger detects CI and defers"
want_out "D20h: deferral marker" 'AFFECTED_GATE_BUDGET_DEFERRED'

# ============================ --full + G1-12 ===================================

# D21: --full on an adapter repo bypasses selection.
reset_fakes; run_gate "$R_CONTROL" gate --full
want_rc 0 "D21: --full on the vitest fixture exits 0"
want_field "D21: mode=full" mode 'full'
want_no_call "D21: --full never runs the related selector" 'related'
# Bare tool-name legs are satisfied by the --version toolchain probe — pin the
# run argv shape (the ledger is `name<TAB>argv`).
want_call "D21: the full command ran" 'vitest	run |npm	test|pnpm	test|yarn	test|bun	test'

# D22 [G1-12 must-PASS]: pnpm workspace, vitest config in a subdirectory,
# non-default base branch (trunk, resolved via origin/HEAD).
R_PNPM="$(mk_repo pnpm-ws trunk)"
mkdir -p "$R_PNPM/packages/web/src" "$R_PNPM/node_modules/.bin"
printf 'packages:\n  - packages/*\n' > "$R_PNPM/pnpm-workspace.yaml"
cat > "$R_PNPM/package.json" <<'JSON'
{ "name": "fixture-pnpm", "private": true, "scripts": { "test": "vitest run" } }
JSON
cat > "$R_PNPM/packages/web/package.json" <<'JSON'
{ "name": "@fx/web", "private": true, "scripts": { "test": "vitest run" } }
JSON
printf 'export default { test: {} };\n' > "$R_PNPM/packages/web/vitest.config.ts"
printf 'export const w = 1;\n' > "$R_PNPM/packages/web/src/w.ts"
printf 'test("w", () => {});\n' > "$R_PNPM/packages/web/src/w.test.ts"
printf 'node_modules/\n' > "$R_PNPM/.gitignore"
ln -sf "$BIN/vitest" "$R_PNPM/node_modules/.bin/vitest"
seal_base "$R_PNPM"
commit_chg "$R_PNPM" packages/web/src/util.ts 'export const u = 1;'
reset_fakes; run_gate "$R_PNPM" gate
want_rc 0 "D22: pnpm-workspace / subdir-config / trunk-base fixture exits 0"
# A workspace may legitimately run the package's own test command rather than
# `vitest related`; what is NOT acceptable is a green run with nothing invoked
# or only a --version probe — pin the invocation shape, not the tool name.
want_call "D22: a runner executed (related selection or the package test command)" 'vitest	(run|related)|jest	.*findRelatedTests|npm	test|pnpm	test|yarn	test|bun	test'

# F1–F3 [pm arms]: the lockfile-detected package manager supplies the exec
# prefix when node_modules/.bin is absent — pnpm-lock.yaml → `pnpm exec`,
# yarn.lock → `yarn <tool>`, bun.lock → `npx --no-install` (the no-`bun x`
# rule: bunx auto-installs registry content, so it is never an exec prefix).
# Assert the prefix on the RUN argv — the --version probe shares the prefix.
seed_pm_repo() { # <name> <lockfile> — vitest stack, no .bin, pm lock committed
  local r; r="$(mk_repo "$1")"; seed_js_nobin "$r"
  printf '# fixture lock\n' > "$r/$2"
  seal_base "$r"; commit_chg "$r" src/util.ts 'export const u = 1;'
  printf '%s' "$r"
}
R_FPNPM="$(seed_pm_repo pm-pnpm pnpm-lock.yaml)"
reset_fakes; run_gate "$R_FPNPM" gate
want_rc 0 "F1: pnpm-lock fixture exits 0"
want_call "F1: pnpm exec prefix on the related run" 'pnpm	exec vitest related'
want_call "F1: vitest ran through the prefix" 'vitest	related'

R_FYARN="$(seed_pm_repo pm-yarn yarn.lock)"
reset_fakes; run_gate "$R_FYARN" gate
want_rc 0 "F2: yarn.lock fixture exits 0"
want_call "F2: yarn prefix on the related run" 'yarn	vitest related'
want_call "F2: vitest ran through the prefix" 'vitest	related'

R_FBUN="$(seed_pm_repo pm-bun bun.lock)"
reset_fakes; run_gate "$R_FBUN" gate
want_rc 0 "F3: bun.lock fixture exits 0"
want_call "F3: bun resolves via npx --no-install, never bun x" 'npx	--no-install vitest related'
want_no_call "F3: bun x is never an exec prefix" 'bun	x|bunx	'

# ============================ env-hygiene + aux modes ==========================

# E1: forged budget env must NOT launder a deferral. A caller exporting
# AFFECTED_BUDGET_ACTIVE=1 + a past AFFECTED_DEADLINE would make every bound
# expire instantly on the OLD code (`${VAR:-0}` inherited env); the gate now
# initialises both unconditionally and requires a detected CI for rc 6.
R_FORGE="$(mk_repo env-forge)"; seed_js "$R_FORGE"; seal_base "$R_FORGE"
commit_chg "$R_FORGE" src/util.ts 'export const u = 1;'
reset_fakes
( cd "$R_FORGE" && env -u CLAUDE_PLUGIN_ROOT \
    AFFECTED_BUDGET_ACTIVE=1 AFFECTED_DEADLINE=1 \
    PATH="$BIN:$BASEPATH" FAKE_LOG="$CALLS" FAKE_DIR="$TESTROOT" \
    REAL_NODE="$REAL_NODE" REAL_PY="$REAL_PY" \
    bash "$SUT" ) > "$TESTROOT/outs/forge.out" 2>&1
RC=$?; OUT="$(cat "$TESTROOT/outs/forge.out")"
printf 'gate\t%s\t%s\n' "$RC" "$TESTROOT/outs/forge.out" >> "$RUNS"
want_rc 0 "E1: forged budget env does not defer"
want_no_out "E1: no deferral marker" 'AFFECTED_GATE_BUDGET_DEFERRED'
want_call "E1: the run actually executed" 'vitest	(run|related)'

# E2: --self-check outside a git repo names the real cause, not no-base-ref.
reset_fakes
mkdir -p "$TESTROOT/not-a-repo"
( cd "$TESTROOT/not-a-repo" && env -u CLAUDE_PLUGIN_ROOT \
    PATH="$BIN:$BASEPATH" FAKE_LOG="$CALLS" FAKE_DIR="$TESTROOT" \
    bash "$SUT" --self-check ) > "$TESTROOT/outs/norepo.out" 2>&1
RC=$?; OUT="$(cat "$TESTROOT/outs/norepo.out")"
printf 'selfcheck\t%s\t%s\n' "$RC" "$TESTROOT/outs/norepo.out" >> "$RUNS"
want_rc 4 "E2: --self-check outside a repo refuses"
want_out "E2: reason is not-a-repo" 'reason=not-a-repo'

# E3: --self-check downgrades `ok` when a detected stack's toolchain is missing
# — a py repo on a PATH without pytest/python3 must not self-check green.
TLBIN="$TESTROOT/bin-toolless"; mkdir -p "$TLBIN"
for _t in git bash env grep find sed awk sort tr cut head tail cat date sleep \
          ps getconf sysctl mktemp rm wc dirname basename uname comm ls mkdir \
          chmod touch printf od jq node vitest jest nx turbo npm npx pnpm yarn bun; do
  _p="$(command -v "$_t" 2>/dev/null || true)"
  [[ -n "$_p" ]] && ln -sf "$_p" "$TLBIN/$_t"
done
R_SC_MISS="$(mk_repo selfcheck-missing)"; seed_python "$R_SC_MISS"; seal_base "$R_SC_MISS"
reset_fakes
run_gate_path "$TLBIN" "$R_SC_MISS" selfcheck --self-check
want_rc 4 "E3: missing toolchain self-check refuses"
want_out "E3: marker says toolchain-missing" 'AFFECTED_GATE_SELF_CHECK toolchain-missing|reason=toolchain-missing'

# E4: --help emits mode=help (contract vocabulary), not mode=none.
reset_fakes; run_gate "$R_CONTROL" gate --help
want_rc 0 "E4: --help exits 0"
want_field "E4: mode is help" mode 'help'

# ============================ portability (source scan) ========================
# The contract bans specific spellings in the gate source; scanned over the SUT and
# every adapter lib it ships, with comment-only lines excluded.

_PORT_FILES=("$SUT")
for _f in "$DIR"/lib/affected-tests/*.sh; do [[ -f "$_f" ]] && _PORT_FILES+=("$_f"); done
port_hits=0
# Banned spellings only: the self-match proc forms and the GNU-only flag shapes.
# `timeout`/`nproc` are deliberately NOT banned — they are legitimate rungs of the
# mandated affected_timeout / affected_ncpu chains; what the contract forbids is a
# bare DEPENDENCY on them, which the helper-name assertions below pin instead.
_BANNED='(pgrep|pkill)[[:space:]]+-[a-zA-Z]*f|ps[[:space:]][^|]*\|[[:space:]]*e?grep|sed[[:space:]][^|#]*-i([[:space:]]|$)|date[[:space:]]+-[a-zA-Z]*d|readlink[[:space:]]+-f|stat[[:space:]]+-[a-zA-Z]*c'
for _f in "${_PORT_FILES[@]}"; do
  _hits="$(grep -avE '^[[:space:]]*#' "$_f" | grep -anE "$_BANNED" || true)"
  if [[ -n "$_hits" ]]; then port_hits=$((port_hits + 1)); fail "D23: portability violation in $_f: $(head -n 3 <<<"$_hits" | tr '\n' '|')"; fi
done
[[ "$port_hits" == "0" ]] && pass "D23: no banned spellings (self-match proc scans, GNU-only flags) in gate sources"
# The mandated portability helpers exist under their contractual names
# (common.sh: affected_ncpu, affected_running_gates, affected_timeout, affected_emit).
_allsrc="$(cat "${_PORT_FILES[@]}" 2>/dev/null | tr -d "\0")"
for _h in affected_ncpu affected_running_gates affected_timeout; do
  if grep -aq "$_h" <<<"$_allsrc"; then pass "D23b: helper $_h present"
  else fail "D23b: contractual helper $_h missing from gate sources"; fi
done
# finish() is the contractual single exit site; the emit side may be a named
# helper or inline emission inside finish() — require finish() plus an emit path.
if grep -aq 'finish()' <<<"$_allsrc" && grep -aqi 'emit' <<<"$_allsrc"; then
  pass "D23b: finish() exit site and emit path present"
else
  fail "D23b: no finish() exit site or emit path found in gate sources"
fi
_head="$(sed -n '1,120p' "$SUT")"
if grep -qw 'git' <<<"$_head" && grep -qE 'getconf|sysctl' <<<"$_head" && grep -qE 'timeout|gtimeout' <<<"$_head"; then
  pass "D23c: the script header lists its external binaries"
else
  fail "D23c: header does not enumerate the external binaries it invokes"
fi
# Every `go list` invocation in the go adapter runs under a bound — an
# unbounded list can park the gate on module resolution (network fetch).
_golist_unb="$(grep -anE 'list -e' "$DIR/lib/affected-tests/go.sh" \
  | grep -av 'affected_timeout\|affected_bound' || true)"
if [[ -z "$_golist_unb" ]]; then
  pass "D23d: every go list call is bounded (affected_timeout/affected_bound)"
else
  fail "D23d: unbounded go list call in go.sh: $(head -n 3 <<<"$_golist_unb" | tr '\n' '|')"
fi
unset _f _hits _head _PORT_FILES port_hits _BANNED _allsrc _h _golist_unb

# ============================ cross-run contract ===============================
# G1-10: every run path emits the marker — a second exit site that fires before the
# emit leaves a run with no AFFECTED_GATE line, and these loops catch it.
# ALL recorded kinds are swept (gate AND explain AND selfcheck) — explain and
# self-check are exit paths too and must not slip a marker-less finish.
_xfail=0
while IFS=$'\t' read -r _kind _rc _of; do
  if ! grep -qE 'AFFECTED_GATE ' "$_of"; then
    _xfail=$((_xfail + 1)); fail "X1: run kind=$_kind rc=$_rc emitted no AFFECTED_GATE marker: $_of"
  fi
done < "$RUNS"
[[ "$_xfail" == "0" ]] && pass "X1: every run (gate/explain/selfcheck) emitted the AFFECTED_GATE marker (single finish() exit site)"
_badword=0
while IFS=$'\t' read -r _kind _rc _of; do
  if grep -qiE 'tests verified' "$_of"; then
    _badword=$((_badword + 1)); fail "X2: 'tests verified' wording emitted: $_of"
  fi
done < "$RUNS"
[[ "$_badword" == "0" ]] && pass "X2: no run ever says 'tests verified'"
# G1-11: "the runner ran" verdicts read the invocation ledger, never exit codes
# alone — prove the check itself bites on an empty ledger.
: > "$TESTROOT/empty-ledger.log"
if log_nonempty "$TESTROOT/empty-ledger.log"; then
  fail "X3: log_nonempty passed an empty ledger — the Guard-1-11 ledger check is blind"
else
  pass "X3: log_nonempty refuses an empty ledger"
fi
printf 'x\n' > "$TESTROOT/nonempty-ledger.log"
if log_nonempty "$TESTROOT/nonempty-ledger.log"; then
  pass "X3b: log_nonempty accepts a populated ledger"
else
  fail "X3b: log_nonempty refuses a populated ledger"
fi
unset _kind _rc _of _xfail _badword

print_results "${AFFECTED_TESTS_MIN_ASSERTIONS:-60}"


