#!/usr/bin/env bash
# Fixture tests for .github/scripts/vinngest-digest-freshness.sh — the scheduled
# reconciler that compares, for EVERY vinngest-v* tag merged into HEAD, the tag's
# LIVE GHCR digest (crane) against the RECORDED digest derived from git pin
# history (the bump commits are the publish workflow's authored record) — #4699.
#
# WHY THIS SUITE EXISTS. The reconciler runs only on a weekly schedule /
# workflow_dispatch, so its verdict classes are verified here out-of-band
# against synthesized fixture repos + a PATH-stubbed crane — the
# test-bump-inngest-bootstrap-pin.sh pattern (git is REAL against fixture
# repos; crane and sleep are stubs). Guard 2 pins the workflow/script wiring
# shape so the two halves cannot silently drift apart.
#
# STUBS. `crane digest <ref>` serves a per-tag map ($MOCK_CRANE_MAP: lines of
# `tag<TAB>digest`); an unknown tag answers MANIFEST_UNKNOWN (the unresolvable
# class). MOCK_CRANE_FAIL=1 makes every call exit non-zero with a transport
# error (the unmeasurable class — never a content verdict).
# MOCK_CRANE_GARBAGE=1 exits 0 with an unparseable body (also unmeasurable).
#
# MIN_ASSERTIONS is the suite's own anti-vacuity floor (#7068 discipline): a
# suite whose asserts were deleted can never green itself.
set -uo pipefail
export LC_ALL=C

REPO_ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
SCRIPT="$REPO_ROOT/.github/scripts/vinngest-digest-freshness.sh"
WORKFLOW="$REPO_ROOT/.github/workflows/scheduled-vinngest-digest-freshness.yml"

# The shell fixture chokepoint (#7849): scrubs inherited GIT_* (a
# lefthook-launched run otherwise leaks GIT_AUTHOR_*/GIT_COMMITTER_* into
# fixture commits), pins a deterministic fixture identity + ceiling, and arms
# the #7833 git-location tripwire.
# shellcheck source=../../../plugins/soleur/test/lib/git-fixture-env.sh
source "$REPO_ROOT/plugins/soleur/test/lib/git-fixture-env.sh"

# Canonical copy — fixture-dir-operand-assert.test.sh asserts every inline
# definition is byte-identical to plugins/soleur/test/test-helpers.sh.
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

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
git_fixture_env "$TMP" || { echo "FATAL: git_fixture_env refused fixture root $TMP" >&2; exit 2; }

PASS=0
FAIL=0
MIN_ASSERTIONS=100  # anti-vacuity floor = the green run's exact count (75 on 2026-10-14 initial battery; 100 after the review fix-round arms J-M + Guard-2 pins); raise when adding rows, never lower it silently

pass() { echo "PASS [$1]"; PASS=$((PASS+1)); }
fail() { echo "FAIL [$1]: $2"; FAIL=$((FAIL+1)); }

# --- digest fixtures (64-hex fakes; content-free, shape-correct) -------------
DIG_1="sha256:$(printf 'a%.0s' $(seq 1 64))"
DIG_2="sha256:$(printf 'b%.0s' $(seq 1 64))"
DIG_1P="sha256:$(printf 'c%.0s' $(seq 1 64))"
DIG_2P="sha256:$(printf 'd%.0s' $(seq 1 64))"
DIG_3="sha256:$(printf 'e%.0s' $(seq 1 64))"

# ---------------------------------------------------------------------------
# Fixture builders
# ---------------------------------------------------------------------------

# write_fixture_cloud_inits <repo_dir> <tag> <digest> — both cloud-init pin
# files, two ref sites each, mirroring the real shapes (IREF ghcr.io + a
# variable-prefixed ZIREF). printf-built: no heredoc operators in this file.
write_fixture_cloud_inits() {
  local dir="$1" t="$2" d="$3"
  assert_fixture_dir "$dir"
  mkdir -p "$dir/apps/web-platform/infra"
  printf '%s\n' \
    '# fixture cloud-init.yml' \
    '  runcmd:' \
    "    IREF=ghcr.io/jikig-ai/soleur-inngest-bootstrap:${t}@${d}" \
    "      ZIREF=\"\$ZURL/jikig-ai/soleur-inngest-bootstrap:${t}@${d}\"" \
    > "$dir/apps/web-platform/infra/cloud-init.yml"
  printf '%s\n' \
    '# fixture cloud-init-inngest.yml' \
    '  runcmd:' \
    "    IREF=ghcr.io/jikig-ai/soleur-inngest-bootstrap:${t}@${d}" \
    "      ZIREF=\"\$ZOT_EP/jikig-ai/soleur-inngest-bootstrap:${t}@${d}\"" \
    > "$dir/apps/web-platform/infra/cloud-init-inngest.yml"
}

# reset_state <name> — fresh crane digest map + call log, so no stub state
# leaks between scenarios (a digest left over from an earlier fixture is
# exactly how a "crane must fail" row false-greens).
reset_state() {
  MOCK_CRANE_MAP="$TMP/crane.$1.map"; : > "$MOCK_CRANE_MAP"
  MOCK_CRANE_LOG="$TMP/crane.$1.log"; : > "$MOCK_CRANE_LOG"
  export MOCK_CRANE_MAP MOCK_CRANE_LOG
}

# new_fixture_repo <name> — fresh git repo on `main`. Sets F_REPO.
new_fixture_repo() {
  local name="$1"
  F_REPO="$TMP/$name/repo"
  mkdir -p "$F_REPO"
  git init -q -b main "$F_REPO"
  reset_state "$name"
}

fixture_commit() { git -C "$F_REPO" add -A && git -C "$F_REPO" commit -qm "$1"; }
seed_tag() { git -C "$F_REPO" tag "$1"; }
crane_serve() { printf '%s\t%s\n' "$1" "$2" >> "$MOCK_CRANE_MAP"; }

# ---------------------------------------------------------------------------
# PATH-shimmed stubs
# ---------------------------------------------------------------------------

BIN="$TMP/bin"
mkdir -p "$BIN"

# crane — `crane digest <ref>` serves the map; unknown tag => the 404-class
# failure (`MANIFEST_UNKNOWN`, the shape crane emits for a missing manifest);
# MOCK_CRANE_FAIL=1 => transport-class failure; MOCK_CRANE_GARBAGE=1 => rc 0
# with an unparseable body.
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -uo pipefail' \
  'printf "crane %s\n" "$*" >> "${MOCK_CRANE_LOG:?unset}"' \
  'if [[ "${MOCK_CRANE_FAIL:-0}" == "1" ]]; then' \
  '  echo "crane-stub: transport failure: connection refused" >&2; exit 1' \
  'fi' \
  'if [[ "${MOCK_CRANE_GARBAGE:-0}" == "1" ]]; then' \
  '  printf "totally not a digest\n"; exit 0' \
  'fi' \
  'if [[ "${1:-}" == "digest" && -n "${2:-}" ]]; then' \
  '  tag="${2##*:}"' \
  '  got=$(awk -F "\t" -v t="$tag" "\$1 == t {print \$2}" "${MOCK_CRANE_MAP:?unset}" 2>/dev/null | head -1)' \
  '  if [[ -n "$got" ]]; then printf "%s\n" "$got"; exit 0; fi' \
  '  echo "crane-stub: GET https://ghcr.io/v2/... : MANIFEST_UNKNOWN: manifest unknown" >&2; exit 1' \
  'fi' \
  'echo "crane-stub: unhandled: $*" >&2; exit 1' \
  > "$BIN/crane"
chmod +x "$BIN/crane"

# sleep — the script's retry backoff is real wall-clock time inside a required
# merge-queue gate; nothing here needs a real sleep.
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$BIN/sleep"
chmod +x "$BIN/sleep"

export PATH="$BIN:$PATH"

# ---------------------------------------------------------------------------
# Run helpers
# ---------------------------------------------------------------------------

# run_vdf <name> — invoke the script against the current fixture repo with stub
# env. stdout+stderr -> $TMP/<name>.out, rc -> LAST_RC, GITHUB_OUTPUT ->
# $TMP/<name>.gout, summary -> $TMP/<name>.summary.
run_vdf() {
  local name="$1"; shift
  LAST_OUT="$TMP/$name.out"
  LAST_GOUT="$TMP/$name.gout"
  LAST_SUMMARY="$TMP/$name.summary"
  : > "$LAST_GOUT"
  env VDF_REPO_DIR="$F_REPO" VDF_CRANE=crane \
      MOCK_CRANE_MAP="$MOCK_CRANE_MAP" MOCK_CRANE_LOG="$MOCK_CRANE_LOG" \
      MOCK_CRANE_FAIL="${MOCK_CRANE_FAIL:-0}" \
      MOCK_CRANE_GARBAGE="${MOCK_CRANE_GARBAGE:-0}" \
      GITHUB_OUTPUT="$LAST_GOUT" GITHUB_STEP_SUMMARY="$LAST_SUMMARY" \
      bash "$SCRIPT" "$@" > "$LAST_OUT" 2>&1
  LAST_RC=$?
}

gout_result() { sed -n 's/^result=//p' "$LAST_GOUT" | tail -1; }

assert_rc() { # name expected-rc
  if [[ "$LAST_RC" == "$2" ]]; then pass "$1"
  else fail "$1" "expected rc=$2, got $LAST_RC — $(tail -5 "$LAST_OUT" | tr '\n' '|')"; fi
}
assert_result() { # name expected-result
  local got; got=$(gout_result)
  if [[ "$got" == "$2" ]]; then pass "$1"
  else fail "$1" "expected result=$2, got '${got:-<none>}' — $(tail -5 "$LAST_OUT" | tr '\n' '|')"; fi
}
assert_out_has() { # name needle (fixed string)
  if grep -qF -- "$2" "$LAST_OUT"; then pass "$1"
  else fail "$1" "output lacks '$2' — $(tail -5 "$LAST_OUT" | tr '\n' '|')"; fi
}
assert_out_lacks() { # name needle (fixed string)
  if grep -qF -- "$2" "$LAST_OUT"; then fail "$1" "output carries forbidden '$2'"
  else pass "$1"; fi
}
# assert_row_count <name> <n> — exactly one verdict row per tag (header
# contract: "never zero rows, never a skipped tag"). Independent of which
# verdict any single row carries.
assert_row_count() { # name expected
  local got
  got=$(grep -cE '^tag=' "$LAST_OUT" 2>/dev/null || true)
  if [[ "$got" == "$2" ]]; then pass "$1"
  else fail "$1" "verdict rows=$got, expected $2 — $(tail -5 "$LAST_OUT" | tr '\n' '|')"; fi
}
# crane_calls <n> — the stub log counts every `crane digest` call; a preflight
# refusal must reach the assertion with ZERO network calls (refusal-before-
# network ordering), and the retry arm must show exactly the retried count.
crane_calls() { grep -c '^crane digest' "$MOCK_CRANE_LOG" 2>/dev/null || true; }
assert_crane_calls() { # name expected
  if [[ "$(crane_calls)" == "$2" ]]; then pass "$1"
  else fail "$1" "crane digest calls=$(crane_calls), expected $2"; fi
}
# verdict_row <name> <tag> <expected-verdict> — the per-tag row carries
# `tag=<T> verdict=<v>`; assert the verdict field exactly.
verdict_row() {
  local got
  got=$(grep -E "^tag=$2 " "$LAST_OUT" 2>/dev/null | sed -nE 's/.*verdict=([a-z-]+).*/\1/p' | head -1)
  if [[ "$got" == "$3" ]]; then pass "$1"
  else fail "$1" "tag $2 verdict '${got:-<absent>}', expected '$3' — $(tail -5 "$LAST_OUT" | tr '\n' '|')"; fi
}
# verdict_field <name> <tag> <field=expected> — one field on the tag's row.
verdict_field() {
  local row
  row=$(grep -E "^tag=$2 " "$LAST_OUT" 2>/dev/null | head -1 || true)
  if [[ "$row" == *"$3"* ]]; then pass "$1"
  else fail "$1" "tag $2 row lacks '$3' — $(tail -5 "$LAST_OUT" | tr '\n' '|')"; fi
}

echo "=== Guard 1: verdict classes over fixture pin history + stub crane ==="

# ---------------------------------------------------------------------------
# Arm A — two merged tags, both recorded, both unchanged -> result=ok exit 0.
# v9.9.1's NEWEST -G hit is the bump-AWAY commit (it was superseded by v9.9.2),
# so its recorded digest can only come from `hit^:` — the derivation edge.
# ---------------------------------------------------------------------------
new_fixture_repo happy
write_fixture_cloud_inits "$F_REPO" v9.9.1 "$DIG_1"
fixture_commit "bump pin to v9.9.1"
seed_tag vinngest-v9.9.1
write_fixture_cloud_inits "$F_REPO" v9.9.2 "$DIG_2"
fixture_commit "bump pin to v9.9.2"
seed_tag vinngest-v9.9.2
crane_serve v9.9.1 "$DIG_1"
crane_serve v9.9.2 "$DIG_2"
run_vdf happy
assert_rc 'A:all-unchanged-rc' 0
assert_result 'A:all-unchanged-result' ok
verdict_row 'A:v9.9.1-unchanged' v9.9.1 unchanged
verdict_row 'A:v9.9.2-unchanged' v9.9.2 unchanged
assert_out_has 'A:both-tags-classified' 'tags=2'
assert_row_count 'A:row-count' 2
assert_crane_calls 'A:crane-calls' 2
# The bump-AWAY edge, made explicit: v9.9.1's recorded digest is DIG_1, which
# lives ONLY in the `hit^:` tree (the newest -G hit's own tree carries v9.9.2).
# A `hit:`-only derivation reports never-recorded here and greens nothing.
verdict_field 'A:v9.9.1-recorded-from-hit-parent' v9.9.1 "recorded=$DIG_1"
verdict_field 'A:v9.9.2-recorded' v9.9.2 "recorded=$DIG_2"
assert_out_lacks 'A:no-warning' '::warning::'
assert_out_lacks 'A:no-error' '::error::'

# ---------------------------------------------------------------------------
# Arm B — a NON-pinned tag's digest moved: ::warning:: + exit 0 + findings.
# ---------------------------------------------------------------------------
reset_state moved-nonpinned
crane_serve v9.9.1 "$DIG_1P"   # live digest differs from the recorded one
crane_serve v9.9.2 "$DIG_2"
run_vdf moved-nonpinned
assert_rc 'B:nonpinned-moved-rc' 0
assert_result 'B:nonpinned-moved-result' findings
verdict_row 'B:v9.9.1-moved' v9.9.1 moved
verdict_row 'B:v9.9.2-unchanged' v9.9.2 unchanged
assert_out_has 'B:warning-annotation' '::warning::'
assert_out_lacks 'B:no-error-annotation' '::error::'

# ---------------------------------------------------------------------------
# Arm C — the PINNED tag's digest moved: ::error:: + exit 1 + findings.
# ---------------------------------------------------------------------------
reset_state moved-pinned
crane_serve v9.9.1 "$DIG_1"
crane_serve v9.9.2 "$DIG_2P"   # the pinned tag's digest moved
run_vdf moved-pinned
assert_rc 'C:pinned-moved-rc' 1
assert_result 'C:pinned-moved-result' findings
verdict_row 'C:v9.9.2-moved' v9.9.2 moved
assert_out_has 'C:error-annotation' '::error::'

# ---------------------------------------------------------------------------
# Arm D — the PINNED tag's manifest is gone (crane 404 class): exit 1.
# ---------------------------------------------------------------------------
reset_state unresolvable-pinned
crane_serve v9.9.1 "$DIG_1"
# v9.9.2 unserved -> stub answers MANIFEST_UNKNOWN
run_vdf unresolvable-pinned
assert_rc 'D:pinned-unresolvable-rc' 1
assert_result 'D:pinned-unresolvable-result' findings
verdict_row 'D:v9.9.2-unresolvable' v9.9.2 unresolvable
assert_out_has 'D:error-annotation' '::error::'

# ---------------------------------------------------------------------------
# Arm E — a merged tag with NO pin-history row: listed, never alarmed.
# ---------------------------------------------------------------------------
new_fixture_repo neverrec
write_fixture_cloud_inits "$F_REPO" v9.9.1 "$DIG_1"
fixture_commit "bump pin to v9.9.1"
seed_tag vinngest-v9.9.1
write_fixture_cloud_inits "$F_REPO" v9.9.2 "$DIG_2"
fixture_commit "bump pin to v9.9.2"
seed_tag vinngest-v9.9.2
printf 'marker\n' > "$F_REPO/README.md"
fixture_commit "unrelated change carrying the next tag"
seed_tag vinngest-v9.9.3    # merged, but no commit ever pinned v9.9.3
crane_serve v9.9.1 "$DIG_1"
crane_serve v9.9.2 "$DIG_2"
crane_serve v9.9.3 "$DIG_3"
run_vdf neverrec
assert_rc 'E:never-recorded-rc' 0
assert_result 'E:never-recorded-result' ok
verdict_row 'E:v9.9.3-never-recorded' v9.9.3 never-recorded
assert_out_lacks 'E:no-warning' '::warning::'
assert_out_lacks 'E:no-error' '::error::'

# ---------------------------------------------------------------------------
# Arm F — never-recorded AND unresolvable: the CONTENT verdict wins the row
# (CTO D4 amendment) -> unresolvable on a non-pinned tag: ::warning::, exit 0.
# ---------------------------------------------------------------------------
reset_state content-wins
crane_serve v9.9.1 "$DIG_1"
crane_serve v9.9.2 "$DIG_2"
# v9.9.3 has no pin history AND no live manifest.
run_vdf content-wins
assert_rc 'F:content-wins-rc' 0
assert_result 'F:content-wins-result' findings
verdict_row 'F:v9.9.3-unresolvable-not-never-recorded' v9.9.3 unresolvable
assert_out_has 'F:warning-annotation' '::warning::'
assert_out_lacks 'F:no-error-annotation' '::error::'

# ---------------------------------------------------------------------------
# Arm G — crane transport failure: the run is unmeasurable (exit 2), never a
# content verdict. A broken instrument must not print tag verdicts.
# ---------------------------------------------------------------------------
reset_state crane-down
crane_serve v9.9.1 "$DIG_1"
crane_serve v9.9.2 "$DIG_2"
MOCK_CRANE_FAIL=1 run_vdf crane-down
assert_rc 'G:crane-fail-rc' 2
assert_result 'G:crane-fail-result' unmeasurable
assert_out_lacks 'G:no-content-verdicts' 'verdict=unchanged'
assert_out_lacks 'G:no-moved-verdict' 'verdict=moved'
assert_crane_calls 'G:retry-loop-exercised' 3
unset MOCK_CRANE_FAIL
# rc 0 with an unparseable body is the same instrument class.
reset_state crane-garbage
crane_serve v9.9.1 "$DIG_1"
crane_serve v9.9.2 "$DIG_2"
MOCK_CRANE_GARBAGE=1 run_vdf crane-garbage
assert_rc 'G:crane-garbage-rc' 2
assert_result 'G:crane-garbage-result' unmeasurable
unset MOCK_CRANE_GARBAGE

# ---------------------------------------------------------------------------
# Arm H — empty merged-tag set: a named failure, never a vacuous green.
# ---------------------------------------------------------------------------
new_fixture_repo tagless
write_fixture_cloud_inits "$F_REPO" v9.9.1 "$DIG_1"
fixture_commit "initial"
run_vdf tagless
assert_rc 'H:empty-tag-set-rc' 2
assert_result 'H:empty-tag-set-result' unmeasurable
assert_out_lacks 'H:no-ok' 'verdict='
assert_crane_calls 'H:refusal-before-network' 0

# ---------------------------------------------------------------------------
# Arm I — the pin file is absent: nothing to grade severity against -> the
# could-not-measure class, not a content verdict.
# ---------------------------------------------------------------------------
new_fixture_repo nopin
write_fixture_cloud_inits "$F_REPO" v9.9.1 "$DIG_1"
fixture_commit "initial"
rm -f "$F_REPO/apps/web-platform/infra/cloud-init-inngest.yml"
fixture_commit "remove the dedicated pin file"
seed_tag vinngest-v9.9.1
crane_serve v9.9.1 "$DIG_1"
run_vdf nopin
assert_rc 'I:unreadable-pin-rc' 2
assert_result 'I:unreadable-pin-result' unmeasurable

# ---------------------------------------------------------------------------
# Arm J — a shallow checkout: `git tag --merged` drops tags below the graft
# silently (#8782), so the refusal must fire BEFORE selection and before any
# registry call. `git clone --depth` only honors depth over file://.
# ---------------------------------------------------------------------------
new_fixture_repo shallow-src
write_fixture_cloud_inits "$F_REPO" v9.9.1 "$DIG_1"
fixture_commit "bump pin to v9.9.1"
seed_tag vinngest-v9.9.1
write_fixture_cloud_inits "$F_REPO" v9.9.2 "$DIG_2"
fixture_commit "bump pin to v9.9.2"
seed_tag vinngest-v9.9.2
SHALLOW="$TMP/shallow-repo"
git clone -q --depth 1 "file://$F_REPO" "$SHALLOW" 2>/dev/null
F_REPO="$SHALLOW"
reset_state shallow
crane_serve v9.9.1 "$DIG_1"
crane_serve v9.9.2 "$DIG_2"
run_vdf shallow
assert_rc 'J:shallow-rc' 2
assert_result 'J:shallow-result' unmeasurable
assert_out_has 'J:shallow-named' 'is-shallow-repository'
assert_crane_calls 'J:refusal-before-network' 0

# ---------------------------------------------------------------------------
# Arm K — the pinned tag is not a member of the merged tag set: the lifecycle
# invariant broke (tag deleted/unpushed/off-history). Unmeasurable, not a
# silent ok — the pin's live digest would otherwise go unmeasured while the
# run reported clean.
# ---------------------------------------------------------------------------
new_fixture_repo pin-not-in-set
write_fixture_cloud_inits "$F_REPO" v9.9.2 "$DIG_2"
fixture_commit "bump pin to v9.9.2"
seed_tag vinngest-v9.9.1   # a merged tag exists, but the PIN (v9.9.2) is not among them
crane_serve v9.9.2 "$DIG_2"
run_vdf pin-not-in-set
assert_rc 'K:pin-not-in-set-rc' 2
assert_result 'K:pin-not-in-set-result' unmeasurable
assert_out_has 'K:membership-named' 'not a member of the merged vinngest-v* set'

# ---------------------------------------------------------------------------
# Arm L — divergent pins: the WEB-host file pins v9.9.1 while the dedicated
# file pins v9.9.2 (the #6536 divergence class). A moved digest on the
# web-pinned tag is ERROR-class — the sibling grades against both files.
# ---------------------------------------------------------------------------
new_fixture_repo divergent
mkdir -p "$F_REPO/apps/web-platform/infra"
printf '%s\n' \
  '# fixture cloud-init.yml' '  runcmd:' \
  "    IREF=ghcr.io/jikig-ai/soleur-inngest-bootstrap:v9.9.1@$DIG_1" \
  > "$F_REPO/apps/web-platform/infra/cloud-init.yml"
printf '%s\n' \
  '# fixture cloud-init-inngest.yml' '  runcmd:' \
  "    IREF=ghcr.io/jikig-ai/soleur-inngest-bootstrap:v9.9.2@$DIG_2" \
  > "$F_REPO/apps/web-platform/infra/cloud-init-inngest.yml"
fixture_commit "pin diverged: web v9.9.1, dedicated v9.9.2"
seed_tag vinngest-v9.9.1
seed_tag vinngest-v9.9.2
crane_serve v9.9.1 "$DIG_1P"   # web-pinned tag moved
crane_serve v9.9.2 "$DIG_2"
run_vdf divergent
assert_rc 'L:divergent-web-pin-moved-rc' 1
assert_result 'L:divergent-web-pin-moved-result' findings
verdict_row 'L:v9.9.1-moved-is-error-class' v9.9.1 moved
assert_out_has 'L:error-annotation' '::error::'

# ---------------------------------------------------------------------------
# Arm M — never-recorded on the PINNED tag: warn-class, never silent ok.
# The pin names a tag whose history never carried `<tag>@sha256:`.
# ---------------------------------------------------------------------------
new_fixture_repo pin-neverrec
mkdir -p "$F_REPO/apps/web-platform/infra"
# The pin line carries NO @digest, so `soleur-inngest-bootstrap:v9.9.3@` never
# appears in history — never-recorded by construction, on the pinned tag.
printf '%s\n' \
  '# fixture cloud-init.yml' '  runcmd:' \
  '    IREF=ghcr.io/jikig-ai/soleur-inngest-bootstrap:v9.9.3' \
  > "$F_REPO/apps/web-platform/infra/cloud-init.yml"
printf '%s\n' \
  '# fixture cloud-init-inngest.yml' '  runcmd:' \
  '    IREF=ghcr.io/jikig-ai/soleur-inngest-bootstrap:v9.9.3' \
  > "$F_REPO/apps/web-platform/infra/cloud-init-inngest.yml"
fixture_commit "pin v9.9.3 name-only (no recorded digest)"
seed_tag vinngest-v9.9.3
crane_serve v9.9.3 "$DIG_3"
run_vdf pin-neverrec
assert_rc 'M:pinned-never-recorded-rc' 0
assert_result 'M:pinned-never-recorded-result' findings
verdict_row 'M:v9.9.3-never-recorded' v9.9.3 never-recorded
assert_out_has 'M:warning-annotation' '::warning::'
assert_out_lacks 'M:no-error-annotation' '::error::'

echo ""
echo "=== Guard 2: workflow + script wiring shape ==="

assert_file() { # name path
  if [[ -r "$2" ]]; then pass "$1"; else fail "$1" "$2 not readable"; fi
}
file_has() { # name file needle — fixed-string membership in a FILE
  if grep -qF -- "$3" "$2" 2>/dev/null; then pass "$1"
  else fail "$1" "$2 lacks '$3'"; fi
}
file_lacks() { # name file needle
  if grep -qF -- "$3" "$2" 2>/dev/null; then fail "$1" "$2 carries forbidden '$3'"
  else pass "$1"; fi
}
file_has_re() { # name file regex
  if grep -qE -- "$3" "$2" 2>/dev/null; then pass "$1"
  else fail "$1" "$2 lacks /$3/"; fi
}

assert_file 'G2:workflow-exists' "$WORKFLOW"
file_has 'G2:wf-gate-override' "$WORKFLOW" 'gate-override: new-scheduled-cron-prefer-inngest'
file_has 'G2:wf-no-prd-secrets-verbatim' "$WORKFLOW" 'no prd secrets'
file_has_re 'G2:wf-scheduled' "$WORKFLOW" '^  schedule:'
file_has_re 'G2:wf-cron' "$WORKFLOW" 'cron:'
file_has 'G2:wf-dispatch' "$WORKFLOW" 'workflow_dispatch'
file_has 'G2:wf-fetch-depth' "$WORKFLOW" 'fetch-depth: 0'
file_has 'G2:wf-fetch-tags' "$WORKFLOW" 'fetch-tags: true'
file_has 'G2:wf-packages-read' "$WORKFLOW" 'packages: read'
file_has 'G2:wf-contents-read' "$WORKFLOW" 'contents: read'
file_has 'G2:wf-ghcr-login' "$WORKFLOW" 'docker/login-action'
file_has 'G2:wf-runs-script' "$WORKFLOW" 'vinngest-digest-freshness.sh'
# Anchored on the invocation inside the run block — a bare script-name grep
# would be satisfied by the workflow header's own comment naming the script.
file_has 'G2:wf-run-line' "$WORKFLOW" 'bash .github/scripts/vinngest-digest-freshness.sh || rc=$?'
# The gate-override's "no prd secrets" attestation is only real if nothing
# Doppler-flavored can appear under it — pin the invariant, not the comment.
file_lacks 'G2:wf-no-doppler' "$WORKFLOW" 'DOPPLER'
file_lacks 'G2:wf-no-prd-terraform' "$WORKFLOW" 'prd_terraform'
# Per-step timeouts so a hang is a step failure that still reaches the Slack
# step (the mint sibling's shape) — a job-level timeout would cancel silently.
file_has 'G2:wf-step-timeout-checkout' "$WORKFLOW" 'timeout-minutes: 3'
file_has 'G2:wf-step-timeout-vdf' "$WORKFLOW" 'timeout-minutes: 4'
file_has 'G2:wf-slack-secret' "$WORKFLOW" 'SLACK_RELEASES_WEBHOOK_URL'
# The Slack step must branch on the script's result= output, NEVER
# `if: failure()` — the warning-class findings path exits 0 (CTO D4).
file_has 'G2:wf-slack-on-result-output' "$WORKFLOW" 'outputs.result'
file_lacks 'G2:wf-no-failure-gate' "$WORKFLOW" 'if: failure()'
# The check lane is read-only (the check-inngest-bootstrap-build precedent).
file_lacks 'G2:wf-no-docker-push' "$WORKFLOW" 'docker push'
file_lacks 'G2:wf-no-packages-write' "$WORKFLOW" 'packages: write'
file_lacks 'G2:wf-no-id-token' "$WORKFLOW" 'id-token'

assert_file 'G2:script-exists' "$SCRIPT"
file_has 'G2:script-pipefail' "$SCRIPT" 'set -uo pipefail'
file_has 'G2:script-repo-seam' "$SCRIPT" 'VDF_REPO_DIR'
file_has 'G2:script-crane-seam' "$SCRIPT" 'VDF_CRANE'
file_has 'G2:script-image-seam' "$SCRIPT" 'VDF_IMAGE'
file_has_re 'G2:script-gitlog-G' "$SCRIPT" 'git .*log .*-G '
file_has_re 'G2:script-crane-digest' "$SCRIPT" 'digest '
file_has 'G2:script-result-ok' "$SCRIPT" 'emit_result ok'
file_has 'G2:script-result-findings' "$SCRIPT" 'emit_result findings'
file_has 'G2:script-result-unmeasurable' "$SCRIPT" 'emit_result unmeasurable'
# The selector must be ALL merged tags — the AC6 `tail -1` is exactly the blind
# spot being fixed. Pin its absence inside the selector block (anchored on the
# VDF_TAGS= write, never a bare `tag --merged` line — the walk_err preflight
# carries that token on a line that already ends `|| true)`).
SEL_BLOCK=$(awk '$0 ~ /^VDF_TAGS=/ {on=1} on {print} on && /\|\| true\)/ {exit}' "$SCRIPT" 2>/dev/null || true)
if [[ "$SEL_BLOCK" == *'tag --merged HEAD --list'* ]]; then pass 'G2:script-selector-present'; else fail 'G2:script-selector-present' 'no `git tag --merged HEAD` selector block found in the script'; fi
if [[ "$SEL_BLOCK" == *'tail -1'* ]]; then fail 'G2:script-selector-all-tags' 'the selector keeps AC6'"'"'s `tail -1` — the semver-max-only blind spot #4699 names'
else pass 'G2:script-selector-all-tags'; fi
if [[ "$SEL_BLOCK" == *'sort -V'* ]]; then pass 'G2:script-selector-sort-v'; else fail 'G2:script-selector-sort-v' 'selector does not sort by version'; fi

echo ""
TOTAL=$((PASS + FAIL))
echo "=== Results: $PASS/$TOTAL passed ==="
if [[ "$TOTAL" -lt "$MIN_ASSERTIONS" ]]; then
  printf 'FAIL: anti-vacuity floor: only %s assertions ran, expected >= %s\n' "$TOTAL" "$MIN_ASSERTIONS" >&2
  exit 1
fi
if (( FAIL > 0 )); then
  echo "FAIL: $FAIL test(s) failed"
  exit 1
fi
echo "OK"
