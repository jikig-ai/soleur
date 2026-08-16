#!/usr/bin/env bash
# Mutation battery for scripts/lint-workflow-install-sites.sh (Guard 2).
#
# Synthetic git repos, running the REAL guard. Rows 4 and 5 are the ones that matter most:
# row 4 pins the raw-string-vs-invocation discrimination (a guard that matches the raw
# string `bun install` fires on comments and log lines, i.e. REDs a correct tree, and a
# false-RED guard gets disabled), and row 5 pins the `npm ci --prefix` form that an
# extractor keyed only on `working-directory:` misses — one such site exists today.
set -euo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

GUARD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lint-workflow-install-sites.sh"
[[ -r "$GUARD" ]] || {
  echo "FATAL: guard not readable at $GUARD" >&2
  exit 2
}

passes=0
fails=0
asserted=0
pass() {
  passes=$((passes + 1))
  asserted=$((asserted + 1))
  echo "[ok] $*"
}
fail() {
  fails=$((fails + 1))
  asserted=$((asserted + 1))
  echo "[FAIL] $*" >&2
}

SANDBOX_ROOT=$(mktemp -d -t lint-wf-install.XXXXXXXX) || {
  echo "FATAL: mktemp failed" >&2
  exit 2
}
trap 'rm -rf "$SANDBOX_ROOT"' EXIT

# Builds a synthetic repo carrying `nwf` workflow files (to clear the >=40 file floor) and
# `nsteps` compliant install steps (to clear the >=20 step floor). Setup failures abort.
make_repo() {
  local name="$1"
  local nwf="${2:-45}"
  local nsteps="${3:-24}"
  local d="$SANDBOX_ROOT/$name"
  mkdir -p "$d/.github/workflows" || return 2
  git -C "$d" init -q -b main || return 2
  git -C "$d" config user.email t@t || return 2
  git -C "$d" config user.name t || return 2
  local i
  for ((i = 1; i <= nwf; i++)); do
    {
      printf 'name: wf%d\njobs:\n  build:\n    runs-on: ubuntu-latest\n    steps:\n' "$i"
      printf '      - name: checkout\n        uses: actions/checkout@v4\n'
      if ((i <= nsteps)); then
        printf '      - name: install\n        run: npm ci --ignore-scripts\n'
      fi
    } > "$d/.github/workflows/wf$i.yml" || return 2
  done
  git -C "$d" add -A || return 2
  printf '%s' "$d"
}

run_guard() {
  local repo="$1" out rc
  out=$(cd "$repo" && bash "$GUARD" 2>&1) || rc=$?
  rc=${rc:-0}
  printf '%s\n---RC:%d\n' "$out" "$rc"
}
guard_rc() { run_guard "$1" | sed -n 's/^---RC:\(.*\)$/\1/p'; }
guard_out() { run_guard "$1" | sed '/^---RC:/d'; }

expect_red() {
  local repo="$1" label="$2" needle="${3:-}" rc out
  rc=$(guard_rc "$repo")
  out=$(guard_out "$repo")
  if [[ "$rc" == "0" ]]; then
    fail "$label — expected RED, guard exited 0"
    return
  fi
  if [[ -n "$needle" && "$out" != *"$needle"* ]]; then
    fail "$label — RED but message did not name '$needle'"
    return
  fi
  pass "$label — RED${needle:+ naming '$needle'}"
}
expect_pass() {
  local repo="$1" label="$2" rc
  rc=$(guard_rc "$repo")
  if [[ "$rc" != "0" ]]; then
    fail "$label — expected PASS, guard exited $rc: $(guard_out "$repo" | head -4)"
    return
  fi
  pass "$label — PASS"
}

add_wf() { # repo, relative path, body
  local repo="$1" rel="$2"
  mkdir -p "$repo/$(dirname "$rel")"
  cat > "$repo/$rel"
  git -C "$repo" add -A
}

# --- CONTROL: a compliant repo must PASS, or every RED row below proves nothing. ---
CLEAN=$(make_repo clean) || {
  echo "FATAL: sandbox setup failed" >&2
  exit 2
}
expect_pass "$CLEAN" "CONTROL compliant repo (45 workflows, 24 npm ci --ignore-scripts steps)"

# --- Row 1: reintroduce `bun install`. ---
R1=$(make_repo row1)
add_wf "$R1" ".github/workflows/offender.yml" <<'YML'
name: offender
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - name: install
        run: bun install --frozen-lockfile
YML
expect_red "$R1" "row1 bun install reintroduced" "installs with bun"

# --- Row 2: a SECOND offending site after the first is compliant (whole-set). ---
R2=$(make_repo row2)
add_wf "$R2" ".github/workflows/second.yml" <<'YML'
name: second
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - name: ok
        run: npm ci --ignore-scripts
  b:
    runs-on: ubuntu-latest
    steps:
      - name: bad
        run: bun install --frozen-lockfile
YML
expect_red "$R2" "row2 second offender after a compliant first" "installs with bun"

# --- Row 3: drop --ignore-scripts. ---
R3=$(make_repo row3)
add_wf "$R3" ".github/workflows/bare.yml" <<'YML'
name: bare
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - name: install
        run: npm ci
YML
expect_red "$R3" "row3 --ignore-scripts dropped" "runs install scripts"

# --- Row 4: raw-string matching would fire here; invocation matching must NOT. ---
# This is the guard's own credibility row: comments and ::error:: strings naming
# `bun install` are legitimate on a correct post-conversion tree.
R4=$(make_repo row4)
add_wf "$R4" ".github/workflows/prose.yml" <<'YML'
name: prose
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      # This job used to run bun install --frozen-lockfile before ADR-191.
      - name: explain
        run: echo "bun install is no longer used here"
      - name: annotate
        run: |
          printf '%s\n' "::error::dependency-cruiser not found — run 'bun install'"
      - name: install
        run: npm ci --ignore-scripts
YML
expect_pass "$R4" "row4 comments/echo/::error:: naming 'bun install' do NOT redden a correct tree"

# ...and the discrimination must be real, not an accident of the fixture: the same file
# with an ACTUAL invocation added must redden.
add_wf "$R4" ".github/workflows/prose-plus.yml" <<'YML'
name: prose-plus
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - name: real
        run: bun install --frozen-lockfile
YML
expect_red "$R4" "row4b a real invocation beside the prose still REDs" "installs with bun"

# --- Row 5: the `npm ci --prefix <dir>` form must still be SEEN. ---
R5=$(make_repo row5)
add_wf "$R5" ".github/workflows/prefix.yml" <<'YML'
name: prefix
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - name: install
        run: npm ci --prefix apps/web-platform
YML
expect_red "$R5" "row5 npm ci --prefix form is seen (working-directory-keyed extractors miss it)" "runs install scripts"

# Row 5b: the `cd <dir> && npm ci` form (form 4) must also be seen.
R5B=$(make_repo row5b)
add_wf "$R5B" ".github/workflows/cdform.yml" <<'YML'
name: cdform
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - name: install
        run: cd apps/web-platform && npm ci
YML
expect_red "$R5B" "row5b 'cd <dir> && npm ci' form is seen" "runs install scripts"

# --- Row 6: setup-bun removed from a job that still runs bun (clause 3). ---
R6=$(make_repo row6)
add_wf "$R6" ".github/workflows/bunless.yml" <<'YML'
name: bunless
jobs:
  unit:
    runs-on: ubuntu-latest
    steps:
      - name: test
        run: bun test plugins/soleur/
YML
expect_red "$R6" "row6 job runs bun with no setup-bun" "no setup-bun step"

# Row 6b: the SAME job WITH setup-bun must PASS — otherwise clause 3 is vacuous, i.e. it
# would redden every bun-running job and the zero-violation reading on the real tree would
# mean nothing.
R6B=$(make_repo row6b)
add_wf "$R6B" ".github/workflows/bunok.yml" <<'YML'
name: bunok
jobs:
  unit:
    runs-on: ubuntu-latest
    steps:
      - name: setup
        uses: oven-sh/setup-bun@v2
      - name: test
        run: bun test plugins/soleur/
YML
expect_pass "$R6B" "row6b same job WITH setup-bun passes (clause 3 is not vacuous)"

# --- Row 7: step-matching broken → the STEP floor fires, not a silent green. ---
# 45 workflow files (clears the file floor) but zero install steps.
R7=$(make_repo row7 45 0)
expect_red "$R7" "row7 zero matched install steps" "below the floor of 20"

# --- Row 8: workflow glob matches nothing → the FILE floor fires. ---
R8=$(make_repo row8 5 5)
expect_red "$R8" "row8 workflow enumeration below the file floor" "below the floor of 40"

# --- Row 9: nested workflow + plugins shell script — the original scope defect. ---
R9=$(make_repo row9)
add_wf "$R9" "apps/web-platform/.github/workflows/nested.yml" <<'YML'
name: nested
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - name: install
        run: bun install --frozen-lockfile
YML
expect_red "$R9" "row9a NESTED .github/workflows is in scope" "apps/web-platform/.github/workflows/nested.yml"

R9B=$(make_repo row9b)
mkdir -p "$R9B/plugins/soleur/scripts"
printf '#!/usr/bin/env bash\nset -euo pipefail\nbun install --frozen-lockfile\n' > "$R9B/plugins/soleur/scripts/gate.sh"
git -C "$R9B" add -A
expect_red "$R9B" "row9b plugins/**/*.sh is in scope" "plugins/soleur/scripts/gate.sh"

# --- H2 must-PASS: a workflow with no install step at all. ---
H2=$(make_repo h2)
add_wf "$H2" ".github/workflows/noinstall.yml" <<'YML'
name: noinstall
jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - name: echo
        run: echo hello
YML
expect_pass "$H2" "H2 workflow with no install step (guard does not require one)"

# --- H3 must-PASS: the stated boundary is IMPLEMENTED, not merely described. ---
# The production Dockerfile deliberately runs `npm ci` WITHOUT --ignore-scripts, and
# composite actions under .github/actions/** are out of scope.
H3=$(make_repo h3)
printf 'FROM node:22\nRUN npm ci\nRUN npm ci --omit=dev\n' > "$H3/Dockerfile"
mkdir -p "$H3/.github/actions/thing"
printf 'runs:\n  using: composite\n  steps:\n    - run: bun install --frozen-lockfile\n      shell: bash\n' > "$H3/.github/actions/thing/action.yml"
git -C "$H3" add -A
expect_pass "$H3" "H3 Dockerfile bare 'npm ci' and .github/actions/** are out of scope"

# --- H1: the suite's own executed-assertion floor. ---
MIN_ASSERTIONS=16
if [[ $asserted -lt $MIN_ASSERTIONS ]]; then
  echo "[FAIL] H1 executed only ${asserted} assertion(s), below the floor of ${MIN_ASSERTIONS} — assertions were neutered or skipped" >&2
  fails=$((fails + 1))
fi

echo
echo "lint-workflow-install-sites.test.sh: ${passes} passed, ${fails} failed, ${asserted} assertion(s) executed (floor ${MIN_ASSERTIONS})"
[[ $fails -eq 0 ]] || exit 1
