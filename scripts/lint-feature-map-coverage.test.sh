#!/usr/bin/env bash
# Mutation battery for scripts/lint-feature-map-coverage.sh (#10399).
#
# WHY THIS FILE EXISTS. The sentinel's failure mode is SILENT: a producer that
# enumerates a subset of routes, a map parser that accepts a bare path token as
# coverage, or an exemption registry that tolerates a reason-less bullet all
# keep printing `ok` on a tree that deserves red -- byte-identical to healthy.
# Each row below builds a synthetic fixture repo that breaks ONE property and
# asserts the sentinel goes RED (or, for the must-PASS rows, stays green).
#
# THE FIXTURE IS A REAL GIT REPO, and small. The sentinel's producer is
# `git ls-files`, which enumerates NOTHING outside a work tree -- every row
# does `git init` + `git add -A` in a mktemp sandbox and drives the sentinel
# via its SOLEUR_FEATURE_MAP_ROOT seam. The seam itself is exercised rather
# than stubbed: the producer is the real `git` binary over the fixture index.
#
# MUTATORS FAIL CLOSED. `mutate` requires its anchor literal to occur EXACTLY
# ONCE in the mutated copy and exits 3 otherwise, so a drifted anchor aborts
# the harness instead of scoring a phantom kill against an unmutated file.
#
# ROWS are the plan's Guard-Contract matrix verbatim (12) plus the C0 control,
# plus two review-added rows (R13/R14) pinning the consumer-grammar tightening:
# R1 uncovered route, R2 map missing, R3 two uncovered routes both named,
# R4 renamed directory, R5 reason-less exemption, R6 zero-route producer,
# R7 tombstone entry, R8 stripped expects:, R9 contradictory classification,
# R10 de-headed entry, R11/R12 must-PASS (route-group stripping; `###`
# subsection + reasoned exemption staying green), R13 prose field-mention is
# not a field bullet, R14 fenced code block in the map.
set -uo pipefail

# git exports these when this runs as a lefthook hook; they would repoint every
# sandbox `git` call at the parent repo.
unset GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SUT="${LINT_FEATURE_MAP_TARGET_OVERRIDE:-$REPO_ROOT/scripts/lint-feature-map-coverage.sh}"
export TMPDIR="${TMPDIR:-/var/tmp}"
export LC_ALL=C

# The battery failing on an absent SUT is the RED state this file is written
# against first (tasks Phase 1.3): a guard that does not exist cannot be
# driven green.
if [[ ! -f "$SUT" ]]; then
  echo "feature-map battery: SUT absent at $SUT -- the guard does not exist (expected during RED)." >&2
  exit 1
fi

# Canonical fixture-dir guard (copied byte-for-byte from plugins/soleur/test/test-helpers.sh; fixture-dir-operand-assert.test.sh pins every copy).
assert_fixture_dir() {
  case "${1-}" in
    "") printf 'FATAL: fixture dir is EMPTY; git -C "" would operate on %s\n' "$PWD" >&2; exit 2 ;;
    */../*|*/..) printf 'FATAL: fixture dir %s contains ..; refusing\n' "$1" >&2; exit 2 ;;
    /proc/*|/sys/*|/dev/*) printf 'FATAL: fixture dir %s is a synthetic-fs path; refusing\n' "$1" >&2; exit 2 ;;
    /|//|/.) printf 'FATAL: fixture dir resolves to the filesystem root; refusing\n' >&2; exit 2 ;;
    /*) : ;;
    *)  printf 'FATAL: fixture dir %s is RELATIVE; refusing\n' "$1" >&2; exit 2 ;;
  esac
}

WORK="$(mktemp -d)"
assert_fixture_dir "$WORK"
trap 'rm -rf "$WORK"' EXIT

passed=0
failed=0
rows_run=0

ok()   { printf 'ok   %s\n' "$1"; passed=$((passed + 1)); }
notok(){ printf 'FAIL %s\n' "$1"; failed=$((failed + 1)); }

# mutate <sut-copy> <literal> <replacement> -- anchor must occur exactly once.
mutate() {
  local f="$1" lit="$2" rep="$3"
  assert_fixture_dir "$f"
  local n
  # `-e` pins the pattern: an anchor starting with `- ` (e.g. a map bullet)
  # would otherwise be parsed as grep's own options and count nothing.
  n="$(grep -cF -e "$lit" "$f")"
  if [[ "$n" != "1" ]]; then
    printf 'FATAL: mutate anchor occurs %s times (want 1): %s\n' "$n" "$lit" >&2
    exit 3
  fi
  local tmp="$f.mut"
  assert_fixture_dir "$tmp"
  # index()+substr() surgery, never sub(): sub() re-matches the anchor as an
  # ERE and can replace a different occurrence than the literal index() found.
  # ENVIRON, never -v: `awk -v lit='/page\.tsx$'` escape-processes the value,
  # so a backslashed anchor (`\.`) silently mutates to a different string and
  # the edit lands nowhere (measured: this battery's own R6 row).
  LIT="$lit" REP="$rep" awk '{
    lit=ENVIRON["LIT"]; rep=ENVIRON["REP"]
    i = index($0, lit)
    if (i) $0 = substr($0, 1, i - 1) rep substr($0, i + length(lit))
    print
  }' "$f" > "$tmp"
  mv "$tmp" "$f"
  grep -qF -e "$rep" "$f" || { printf 'FATAL: mutation did not land: %s\n' "$rep" >&2; exit 3; }
}

# mkmap <dir> -- a conforming map for the base fixture: three mapped routes
# (`/`, `/dashboard`, `/dashboard/chat`), one `###` subsection pinned inside
# the /dashboard entry body (an H3 must never parse as a route heading), and
# one reasoned exemption (`/setup-key`, with a backing page).
mkmap() {
  local d="$1"
  assert_fixture_dir "$d"
  cat > "$d/apps/web-platform/test/feature-map.md" <<'MD'
# Feature map

## `/`

- route: `/`
- entry: direct URL
- selectors: `Sign in to Soleur` heading
- expects: redirect boundary
- auth: anonymous
- gotchas: none

## `/dashboard`

- route: `/dashboard`
- entry: nav
- selectors: `workspace-context-band`
- expects: dashboard shell renders
- auth: bot
- gotchas: none

### Selector notes

`conversations-rail` lists threads.

## `/dashboard/chat`

- route: `/dashboard/chat`
- entry: rail nav
- selectors: `chat-index-resume`
- expects: conversation index renders
- auth: bot
- gotchas: none

## Deliberately unmapped

- `/setup-key` — onboarding-only API-key step, not a working surface
MD
}

# mkrepo <dir> -- a minimal fixture repo: four page.tsx files whose derived
# routes are `/`, `/dashboard`, `/dashboard/chat`, `/setup-key`; a conforming
# map; `git init` + `git add -A` so `git ls-files` sees the whole tree.
mkrepo() {
  local d="$1"
  assert_fixture_dir "$d"
  mkdir -p "$d/apps/web-platform/app/(dashboard)/dashboard/chat" \
           "$d/apps/web-platform/app/(auth)/setup-key" \
           "$d/apps/web-platform/test"
  printf 'export default function P() { return null; }\n' > "$d/apps/web-platform/app/page.tsx"
  printf 'export default function P() { return null; }\n' > "$d/apps/web-platform/app/(dashboard)/dashboard/page.tsx"
  printf 'export default function P() { return null; }\n' > "$d/apps/web-platform/app/(dashboard)/dashboard/chat/page.tsx"
  printf 'export default function P() { return null; }\n' > "$d/apps/web-platform/app/(auth)/setup-key/page.tsx"
  mkmap "$d"
  ( cd "$d" && git init -q && git add -A )
}

# run_sut <dir> -- rc is the verdict; output captured for token checks.
run_sut() {
  local d="$1"
  SOLEUR_FEATURE_MAP_ROOT="$d" bash "$SUT" > "$WORK/out" 2>&1
  echo $?
}

expect_red() {
  local name="$1" dir="$2" token="${3:-}"
  rows_run=$((rows_run + 1))
  local rc
  rc="$(run_sut "$dir")"
  # rc must be exactly 1 -- the sentinel's verdict exit. Any other non-zero
  # (2, 126, 127, 141) is instrument failure masquerading as a caught
  # mutation: abort the harness, do not count it as a kill.
  if [[ "$rc" != "0" && "$rc" != "1" ]]; then
    printf 'FATAL(harness): %s -- SUT exited %s, neither verdict rc (0|1)\n' "$name" "$rc" >&2
    cat "$WORK/out" >&2
    exit 3
  fi
  if [[ "$rc" == "0" ]]; then
    notok "$name -- expected RED, got exit 0"; cat "$WORK/out" >&2; return
  fi
  if [[ -n "$token" ]] && ! grep -qF "$token" "$WORK/out"; then
    notok "$name -- RED but missing token: $token"; cat "$WORK/out" >&2; return
  fi
  ok "$name"
}

expect_green() {
  local name="$1" dir="$2"
  rows_run=$((rows_run + 1))
  local rc
  rc="$(run_sut "$dir")"
  if [[ "$rc" != "0" ]]; then
    notok "$name -- expected GREEN, got exit $rc"; cat "$WORK/out" >&2; return
  fi
  grep -q 'feature-map-coverage: ok' "$WORK/out" || { notok "$name -- green but no ok summary"; cat "$WORK/out" >&2; return; }
  ok "$name"
}

# --- C0: control -- baseline fixture is green ----------------------------------
D="$WORK/c0"; mkrepo "$D"
expect_green "C0 baseline fixture green" "$D"

# --- R1: new page.tsx with no map entry -> RED naming the derived route --------
D="$WORK/r1"; mkrepo "$D"
mkdir -p "$D/apps/web-platform/app/(dashboard)/dashboard/new-widget"
printf 'export default function P() { return null; }\n' > "$D/apps/web-platform/app/(dashboard)/dashboard/new-widget/page.tsx"
( cd "$D" && git add -A )
expect_red "R1 uncovered route" "$D" "/dashboard/new-widget"
# Discriminating guard: the red must come through the coverage arm, not a
# tombstone/contradiction misclassification.
if ! grep -q 'UNCOVERED-ROUTE' "$WORK/out"; then
  notok "R1 fired without the coverage arm (UNCOVERED-ROUTE absent)"; cat "$WORK/out" >&2
fi

# --- R2: map file deleted entirely -> RED (fail-closed, not '0 checked') -------
D="$WORK/r2"; mkrepo "$D"
rm "$D/apps/web-platform/test/feature-map.md"
expect_red "R2 map file absent" "$D" "map file missing"

# --- R3: a SECOND unmapped page must also be named (no first-member stop) ------
D="$WORK/r3"; mkrepo "$D"
mkdir -p "$D/apps/web-platform/app/(dashboard)/dashboard/w1" "$D/apps/web-platform/app/(dashboard)/dashboard/w2"
printf 'export default function P() { return null; }\n' > "$D/apps/web-platform/app/(dashboard)/dashboard/w1/page.tsx"
printf 'export default function P() { return null; }\n' > "$D/apps/web-platform/app/(dashboard)/dashboard/w2/page.tsx"
( cd "$D" && git add -A )
rows_run=$((rows_run + 1))
rc="$(run_sut "$D")"
if [[ "$rc" == "0" ]]; then
  notok "R3 -- expected RED"; cat "$WORK/out" >&2
elif grep -q '/dashboard/w1' "$WORK/out" && grep -q '/dashboard/w2' "$WORK/out"; then
  ok "R3 names both uncovered routes"
else
  notok "R3 -- RED but did not name BOTH routes"; cat "$WORK/out" >&2
fi

# --- R4: rename a page directory -> derived route no longer matches map --------
D="$WORK/r4"; mkrepo "$D"
# mv + `git add -A` (not `git mv`): git mv on a directory rejects the source
# pathspec under some git versions ("fatal: bad source") -- the rename is an
# index update either way.
( cd "$D" && mv 'apps/web-platform/app/(dashboard)/dashboard/chat' 'apps/web-platform/app/(dashboard)/dashboard/chatx' && git add -A )
expect_red "R4 renamed dir derives new route" "$D" "/dashboard/chatx"

# --- R5: exemption bullet without a reason -> RED ------------------------------
D="$WORK/r5"; mkrepo "$D"
# Move /dashboard/chat's classification into Deliberately unmapped WITHOUT the
# ` -- <reason>` half: rewrite the map wholesale so the heading is gone and the
# bullet is malformed by construction.
cat > "$D/apps/web-platform/test/feature-map.md" <<'MD'
# Feature map

## `/`

- route: `/`
- entry: direct URL
- selectors: `Sign in to Soleur` heading
- expects: redirect boundary
- auth: anonymous
- gotchas: none

## `/dashboard`

- route: `/dashboard`
- entry: nav
- selectors: `workspace-context-band`
- expects: dashboard shell renders
- auth: bot
- gotchas: none

## Deliberately unmapped

- `/setup-key` — onboarding-only API-key step, not a working surface
- `/dashboard/chat`
MD
expect_red "R5 reason-less exemption bullet" "$D" "MALFORMED-EXEMPTION"

# --- R6: neuter the producer so zero routes derive -> RED (vacuity) ------------
D="$WORK/r6"; mkrepo "$D"
cp "$SUT" "$WORK/sut-r6.sh"
mutate "$WORK/sut-r6.sh" '/page\.tsx$' '/page\.tsx-never$'
# LINT_FEATURE_MAP_TARGET_OVERRIDE is a battery-side TEST-ONLY seam (read at
# this script's start to repoint $SUT); the sentinel itself reads only
# SOLEUR_FEATURE_MAP_ROOT. R6 runs the mutated copy directly.
SOLEUR_FEATURE_MAP_ROOT="$D" bash "$WORK/sut-r6.sh" > "$WORK/out" 2>&1; rc=$?
rows_run=$((rows_run + 1))
if [[ "$rc" == "0" ]]; then
  notok "R6 zero-route producer -- expected RED, got 0"; cat "$WORK/out" >&2
elif ! grep -q "ZERO" "$WORK/out"; then
  notok "R6 zero-route producer -- RED but missing the anti-vacuity arm's own error"; cat "$WORK/out" >&2
else
  ok "R6 zero-route producer"
fi

# --- R7: delete the page, keep the map entry -> RED (tombstone) ----------------
D="$WORK/r7"; mkrepo "$D"
( cd "$D" && rm 'apps/web-platform/app/(dashboard)/dashboard/chat/page.tsx' && git add -A )
expect_red "R7 tombstone map entry" "$D" "TOMBSTONE-ENTRY"

# --- R8: strip expects: from one mapped entry, heading intact -> RED -----------
D="$WORK/r8"; mkrepo "$D"
mutate "$D/apps/web-platform/test/feature-map.md" '- expects: conversation index renders' '- notes: none'
expect_red "R8 entry missing expects:" "$D" "INCOMPLETE-ENTRY"

# --- R9: route in BOTH mapped and unmapped sets -> RED (contradiction) ---------
D="$WORK/r9"; mkrepo "$D"
printf -- '- `/dashboard/chat` — documented exemption reason\n' >> "$D/apps/web-platform/test/feature-map.md"
expect_red "R9 contradictory classification" "$D" "CONTRADICTORY-ROUTE"

# --- R10: strip the ## prefix from a map heading -> RED (anchor, not token) ----
D="$WORK/r10"; mkrepo "$D"
mutate "$D/apps/web-platform/test/feature-map.md" '## `/dashboard/chat`' '`/dashboard/chat`'
expect_red "R10 de-headed entry" "$D" "/dashboard/chat"

# --- R11 (must-PASS): route-group stripping across every edge shape ------------
# `(dashboard)` strips to `/dashboard`, root `app/page.tsx` derives `/`, and
# `(public)/invite/[token]` derives the literal `/invite/[token]` -- all three
# must resolve, and the reasoned exemption for the dynamic route stays green.
D="$WORK/r11"; mkrepo "$D"
mkdir -p "$D/apps/web-platform/app/(public)/invite/[token]"
printf 'export default function P() { return null; }\n' > "$D/apps/web-platform/app/(public)/invite/[token]/page.tsx"
printf -- '- `/invite/[token]` — requires a valid invite token\n' >> "$D/apps/web-platform/test/feature-map.md"
( cd "$D" && git add -A )
expect_green "R11 route-group stripping + dynamic-segment exemption" "$D"

# --- R12 (must-PASS): ### subsection + reasoned exemption stay green -----------
# A `###` heading carrying route-shaped text is not a route heading (the
# mapped-set anchor is `^## `, never `^#`); the base fixture's `/setup-key`
# bullet already proves a reasoned exemption holds green.
D="$WORK/r12"; mkrepo "$D"
mutate "$D/apps/web-platform/test/feature-map.md" '### Selector notes' '### `/dashboard/ghost`'
expect_green "R12 H3 with route-shaped text not a route heading" "$D"

# --- R13: a prose mention of the field name is NOT the field bullet ------------
# The completeness arm is anchored to the `- selectors:`/`- expects:` bullet
# shape; rewriting both bullets of one entry into prose lines that still
# contain the field names must red BOTH fields (a bare-substring check would
# pass this fixture green).
D="$WORK/r13"; mkrepo "$D"
mutate "$D/apps/web-platform/test/feature-map.md" '- selectors: `chat-index-resume`' '- notes: selectors: inlined'
mutate "$D/apps/web-platform/test/feature-map.md" '- expects: conversation index renders' '- notes: expects: inlined'
expect_red "R13 prose field-mention is not a field bullet" "$D" "INCOMPLETE-ENTRY"
if ! grep -q 'selectors:' "$WORK/out" || ! grep -q 'expects:' "$WORK/out"; then
  notok "R13 -- RED but did not name BOTH missing fields"; cat "$WORK/out" >&2
fi

# --- R14: a fenced code block anywhere in the map -> RED ------------------------
# A `## \`/route\`` line inside a fence counts as a real entry under the
# line-anchored consumers; the guard fails closed on the fence itself rather
# than teaching three parsers to skip fence ranges. The fenced ghost also
# tombstones, so the discriminating token is FENCED-BLOCK, not the rc.
D="$WORK/r14"; mkrepo "$D"
cat >> "$D/apps/web-platform/test/feature-map.md" <<'MD'

```markdown
## `/dashboard/ghost`

- selectors: `x`
- expects: y
```
MD
expect_red "R14 fenced code block in map" "$D" "FENCED-BLOCK"

# --- Harness self-check -- deleting a row must red the battery -----------------
# EXACT count, not a floor: a `>=` bound admits deleting rows unnoticed, which
# is the defect this row exists to make visible. Bump DECLARED_ROWS in the same
# edit that adds or removes a row.
DECLARED_ROWS=16
rows_run=$((rows_run + 1))
if (( rows_run == DECLARED_ROWS )); then
  ok "battery executed ${rows_run}/${DECLARED_ROWS} rows (anti-vacuity)"
else
  notok "battery executed ${rows_run} rows, expected ${DECLARED_ROWS} -- a deleted or added row went unrecorded"
fi

echo "feature-map-coverage battery: ${passed} passed, ${failed} failed"
(( failed == 0 ))
