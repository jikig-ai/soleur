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
# ADR-193 #2: the verdict helpers touch ONLY the verdict counters. `asserted` (the CASE
# counter) moves at the CALL SITE instead. That is the whole difference between a
# conservation identity that catches a discarded verdict and one that cannot: a counter
# incremented inside both helpers moves WITH the verdict, so stubbing fail() drops the row
# AND its count together and `passes + fails == asserted` still holds under the exact fault
# it exists to catch.
pass() {
  passes=$((passes + 1))
  echo "[ok] $*"
}
fail() {
  fails=$((fails + 1))
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
  asserted=$((asserted + 1))
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
  asserted=$((asserted + 1))
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

# Row 6f: the invocation is inside a COMMAND SUBSTITUTION. This is the shape that actually
# shipped: #7566 replaced `Setup Bun` with `Setup Node.js` in cla-evidence.yml and left two
# `payload=$(bun run …)` call sites, breaking a REQUIRED pull_request_target check on every
# PR — and this lint reported OK against that tree (measured by restoring the broken file
# and re-running: `scanned 83 workflow file(s) … OK`).
#
# Clause 3 named the property "any step invoking `bun `" but matched only two positions: a
# `run:` line, and a line whose first token is `bun`. A command substitution is neither, so
# the property was wider than the pattern — the same defect class this file's own header
# describes for clause 1's invocation-vs-mention split, on the position axis instead.
R6SUBST=$(make_repo row6subst)
add_wf "$R6SUBST" ".github/workflows/bunsubst.yml" <<'YML'
name: bunsubst
jobs:
  record:
    runs-on: ubuntu-latest
    steps:
      - name: Setup Node.js
        uses: actions/setup-node@v4
      - name: build record
        run: |
          payload=$(bun run apps/web-platform/scripts/cla-evidence/build-record.ts) \
            || exit 1
          echo "$payload"
YML
expect_red "$R6SUBST" "row6subst bun inside a command substitution is an invocation" "no setup-bun step"

# Row 6g: the same job WITH setup-bun must still PASS, so 6f cannot be satisfied by a
# clause that reddens every command substitution.
R6SUBSTOK=$(make_repo row6substok)
add_wf "$R6SUBSTOK" ".github/workflows/bunsubstok.yml" <<'YML'
name: bunsubstok
jobs:
  record:
    runs-on: ubuntu-latest
    steps:
      - name: setup
        uses: oven-sh/setup-bun@v2
      - name: build record
        run: |
          payload=$(bun run apps/web-platform/scripts/cla-evidence/build-record.ts)
          echo "$payload"
YML
expect_pass "$R6SUBSTOK" "row6substok command substitution WITH setup-bun passes"

# Row 6h: a bun MENTION inside a quoted operator-facing string is not an invocation. Without
# this, widening the position set to "anywhere on the line" would redden every workflow that
# merely talks about bun in an ::error:: — the false-RED that gets a guard disabled.
R6MENTION=$(make_repo row6mention)
add_wf "$R6MENTION" ".github/workflows/bunmention.yml" <<'YML'
name: bunmention
jobs:
  advise:
    runs-on: ubuntu-latest
    steps:
      - name: advise
        run: |
          echo "::error::this repo no longer uses bun install; use npm ci instead"
YML
expect_pass "$R6MENTION" "row6mention a bun mention in a quoted string is not an invocation"

# Row 6c: setup-bun named only in a COMMENT must NOT count as a setup step. Clause 1
# distinguishes invocation from mention; clause 3 did not, and ci.yml carries exactly such
# a comment inside a job with no setup-bun of its own — so the clause was fail-open on the
# live tree, not merely in theory.
R6C=$(make_repo row6c)
add_wf "$R6C" ".github/workflows/buncomment.yml" <<'YML'
name: buncomment
jobs:
  unit:
    runs-on: ubuntu-latest
    steps:
      # NOTE for maintainers: keep actions/checkout and oven-sh/setup-bun pinned.
      - name: test
        run: bun test plugins/soleur/
YML
expect_red "$R6C" "row6c setup-bun named only in a comment does not satisfy clause 3" "no setup-bun step"

# Row 6d: a job key carrying a trailing comment must still open a job. When the unparsed
# key was a file's FIRST job, `job` stayed empty and every clause-3 rule was gated off —
# the whole file went invisible with no signal.
R6D=$(make_repo row6d)
add_wf "$R6D" ".github/workflows/buncomment2.yml" <<'YML'
name: buncomment2
jobs:
  unit: # the only job in this file
    runs-on: ubuntu-latest
    steps:
      - name: test
        run: bun test plugins/soleur/
YML
expect_red "$R6D" "row6d job key with a trailing comment is still parsed" "no setup-bun step"

# Row 6e: a QUOTED job key must also parse.
R6E=$(make_repo row6e)
add_wf "$R6E" ".github/workflows/bunquoted.yml" <<'YML'
name: bunquoted
jobs:
  "unit":
    runs-on: ubuntu-latest
    steps:
      - name: test
        run: bun test plugins/soleur/
YML
expect_red "$R6E" "row6e quoted job key is still parsed" "no setup-bun step"

# Row 6f: a chained command must be classified per SEGMENT. Anchoring on the head of the
# line made `npm ci --ignore-scripts && bun install` read as fully compliant.
R6F=$(make_repo row6f)
add_wf "$R6F" ".github/workflows/chained.yml" <<'YML'
name: chained
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - name: install
        run: npm ci --ignore-scripts && bun install --frozen-lockfile
YML
expect_red "$R6F" "row6f bun install chained after a compliant npm ci is seen" "installs with bun"

# Row 6g: an env-var prefix must not hide the invocation.
R6G=$(make_repo row6g)
add_wf "$R6G" ".github/workflows/envprefix.yml" <<'YML'
name: envprefix
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - name: install
        run: CI=1 NODE_ENV=test bun install --frozen-lockfile
YML
expect_red "$R6G" "row6g env-prefixed bun install is seen" "installs with bun"

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

# Row 9c: a `scripts/` directory that is NOT at the repo root. The previous class-2 arms
# were `scripts/*.sh | plugins/*.sh`, anchored at the root — a `case` glob's `*` matches
# `/`, so they covered arbitrary depth BELOW those two and missed every scripts/ directory
# elsewhere, leaving ~185 tracked scripts unscanned while the header named one exclusion.
R9C=$(make_repo row9c)
mkdir -p "$R9C/apps/web-platform/scripts"
printf '#!/usr/bin/env bash\nset -euo pipefail\nbun install --frozen-lockfile\n' > "$R9C/apps/web-platform/scripts/setup.sh"
git -C "$R9C" add -A
expect_red "$R9C" "row9c a non-root scripts/ directory is in scope" "apps/web-platform/scripts/setup.sh"

# Row 10: an ARRAY-ASSIGNMENT install must be seen. `VAR=(bun install …)` begins with the
# variable name after ltrim, so the head-anchored extractor could not see it — and
# worktree-manager.sh carries live examples on the /ship path.
R10=$(make_repo row10)
mkdir -p "$R10/scripts"
printf '#!/usr/bin/env bash\ncmd=(bun install --frozen-lockfile --cwd "$d")\n' > "$R10/scripts/wt.sh"
git -C "$R10" add -A
expect_red "$R10" "row10 array-assignment bun install is seen" "installs with bun"

# Row 10b: the per-line waiver suppresses exactly that line...
R10B=$(make_repo row10b)
mkdir -p "$R10B/scripts"
printf '#!/usr/bin/env bash\ncmd=(bun install --frozen-lockfile) # lint-workflow-install-sites: allow-bun\n' > "$R10B/scripts/wt.sh"
git -C "$R10B" add -A
expect_pass "$R10B" "row10b per-line allow-bun waiver suppresses its own line"

# Row 10c: ...and ONLY that line. A naked reintroduction in the same file must still RED,
# or the waiver would be a file-wide exemption wearing a per-line label.
R10C=$(make_repo row10c)
mkdir -p "$R10C/scripts"
printf '#!/usr/bin/env bash\ncmd=(bun install --frozen-lockfile) # lint-workflow-install-sites: allow-bun\nbun install --frozen-lockfile\n' > "$R10C/scripts/wt.sh"
git -C "$R10C" add -A
expect_red "$R10C" "row10c waiver is per-LINE: a naked sibling install still REDs" "installs with bun"

# Row 11: composite actions carry runs.steps[].run with workflow-step semantics.
R11=$(make_repo row11)
add_wf "$R11" ".github/actions/thing/action.yml" <<'YML'
name: thing
runs:
  using: composite
  steps:
    - run: bun install --frozen-lockfile
      shell: bash
YML
expect_red "$R11" "row11 composite action install is in scope" "installs with bun"

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
# The production Dockerfile deliberately runs `npm ci` WITHOUT --ignore-scripts and stays
# out of scope. Composite actions are NO LONGER a boundary -- row 11 asserts they are
# scanned -- so this row now pins only the Dockerfile half.
H3=$(make_repo h3)
printf 'FROM node:22\nRUN npm ci\nRUN npm ci --omit=dev\n' > "$H3/Dockerfile"
git -C "$H3" add -A
expect_pass "$H3" "H3 the production Dockerfile bare 'npm ci' stays out of scope"

# --- H1: the suite's own executed-assertion floor (ADR-193). ---
# The floor sits on PASSES, never on `asserted`: a floor on the case counter measures that
# assertions RAN and never that they CONCLUDED. Deleting
# the single line `fails=$((fails + 1))` from fail() left this suite reporting
# "5 passed, 0 failed, 16 assertion(s)" and exiting 0 with the guard fully neutered. The
# reconciliation catches that directly -- passes+fails must account for every assertion,
# so a counter that stops incrementing is a hard failure rather than a quiet one.
#
# Emitted WITHOUT routing through fail(), because a floor dispatched through the helper it
# backstops is disarmed by the same one-line edit it exists to catch.
#
# ORDER (ADR-193 #4): conservation runs FIRST. A neutered fail() deflates the pass count, so
# both checks trip on the same fault -- and whichever runs first names it. Conservation says
# "a verdict was discarded"; the floor would say the misleading "assertions were removed".
#
# The threshold binding sits DIRECTLY above the floor it binds, with no intervening block.
# scripts/guard-vacuity-floor.test.sh builds its mutant by slicing the floor `if` plus the
# contiguous simple assignments above it; with the conservation block in between, the slice
# stops at `fi`, MIN_ASSERTIONS is unbound, and the mutant dies at `set -u` BEFORE reaching
# the floor -- scored "not constructible", i.e. this floor would be asserted by nothing.
if [[ $((passes + fails)) -ne $asserted ]]; then
  printf '\n[FATAL] accounting: passes+fails (%d) != asserted (%d).\n' \
    "$((passes + fails))" "$asserted" >&2
  if [[ $((passes + fails)) -lt "$asserted" ]]; then
    printf '  An assertion was counted but its verdict was not recorded — that is what a neutered pass()/fail() looks like.\n' >&2
  else
    printf '  A verdict was recorded without a counted case — a call site is missing its increment (a harness bug, not a product failure).\n' >&2
  fi
  exit 1
fi
MIN_ASSERTIONS=26
if [[ $passes -lt $MIN_ASSERTIONS ]]; then
  echo "[FAIL] H1 only ${passes} assertion(s) PASSED, below the floor of ${MIN_ASSERTIONS} — assertions were neutered or skipped" >&2
  exit 1
fi

echo
echo "lint-workflow-install-sites.test.sh: ${passes} passed, ${fails} failed, ${asserted} assertion(s) executed (floor ${MIN_ASSERTIONS})"
[[ $fails -eq 0 ]] || exit 1
