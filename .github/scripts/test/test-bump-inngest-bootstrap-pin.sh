#!/usr/bin/env bash
# Fixture tests for .github/scripts/bump-inngest-bootstrap-pin.sh — the writer
# that build-inngest-bootstrap-image.yml's bump-cloud-init-pin job invokes to
# move the soleur-inngest-bootstrap cloud-init pin to the semver-max published
# vinngest-v* tag + registry-resolved digest (#8359).
#
# WHY THIS SUITE EXISTS. A workflow cannot be workflow_dispatch-tested from a
# feature branch (the same reason board-status-sync keeps its logic in a
# unit-tested script — see that file's header). The bump path is verified here
# out-of-band against synthetic fixture repos, and Guard 2 below pins the YAML
# wiring that feeds the script its inputs, so the two halves cannot silently
# drift apart.
#
# STUBS. `crane`, `gh`, and `sleep` are PATH-shimmed (sleep zeros the retry
# backoff — ~24s of real time the suite would otherwise burn inside a required
# merge-queue gate); git is REAL against fixture repos (the push remote is a
# local bare repo via BUMP_PUSH_URL). The gh stub derives a commit's
# "author.login" AND "commit.author.email" from its author EMAIL in the bare
# origin — the same mechanism GitHub uses — so the bot-vs-human tip check is
# exercised for real. MOCK_GH_UNLINKED=1 drops .author to null to exercise the
# email-fallback path; MOCK_GH_MERGE_FAIL=1 fails `gh pr merge`. A `|fork`
# suffix on a seeded PR row emits isCrossRepository:true + a non-bot author.
#
# GUARD CONTRACT (plan §Guard Contract). Guard 1 = behavior rows over the
# script's mutation matrix; Guard 2 = workflow-shape + regex-parity asserts over
# build-inngest-bootstrap-image.yml. MIN_ASSERTIONS is the suite's own
# anti-vacuity floor (#7068 discipline): a suite whose asserts were deleted can
# never green itself.
set -uo pipefail
export LC_ALL=C

REPO_ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
SCRIPT="$REPO_ROOT/.github/scripts/bump-inngest-bootstrap-pin.sh"
WORKFLOW="$REPO_ROOT/.github/workflows/build-inngest-bootstrap-image.yml"
CONSUMER="$REPO_ROOT/apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh"
[[ -f "$WORKFLOW" ]] || { echo "FAIL: $WORKFLOW not found"; exit 1; }
[[ -f "$CONSUMER" ]] || { echo "FAIL: $CONSUMER not found"; exit 1; }

# The shell fixture chokepoint (#7849): scrubs inherited GIT_* (a
# lefthook-launched run otherwise leaks GIT_AUTHOR_*/GIT_COMMITTER_* into
# fixture commits — measured: commits authored as the developer, not the bot),
# pins a deterministic fixture identity + ceiling, and arms the #7833
# git-location tripwire.
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
MIN_ASSERTIONS=150   # anti-vacuity floor — raise when adding rows, never lower it silently

pass() { echo "PASS [$1]"; PASS=$((PASS+1)); }
fail() { echo "FAIL [$1]: $2"; FAIL=$((FAIL+1)); }

# --- digest fixtures (64-hex fakes; content-free, shape-correct) -------------
DIG_OLD="sha256:$(printf 'a%.0s' $(seq 1 64))"
DIG_NEW="sha256:$(printf 'b%.0s' $(seq 1 64))"
DIG_NEWER="sha256:$(printf 'c%.0s' $(seq 1 64))"
BOT_EMAIL='273333864+soleur-ai[bot]@users.noreply.github.com'

# ---------------------------------------------------------------------------
# Fixture builders
# ---------------------------------------------------------------------------

# write_fixture_cloud_inits <repo_dir> <iref_tag> <iref_dig> <ziref_tag> <ziref_dig>
# Two files, two pin sites each, mirroring the real shapes: bare ghcr.io IREF
# and a variable-prefixed ZIREF ($ZURL in one file, $ZOT_EP in the other —
# Guard 1 row 7 exercises the two prefixes surviving the rewrite).
write_fixture_cloud_inits() {
  local dir="$1" it="$2" id="$3" zt="$4" zd="$5"
  assert_fixture_dir "$dir"
  mkdir -p "$dir/apps/web-platform/infra"
  cat > "$dir/apps/web-platform/infra/cloud-init.yml" <<EOF
# fixture cloud-init.yml
  runcmd:
    IREF=ghcr.io/jikig-ai/soleur-inngest-bootstrap:${it}@${id}
      ZIREF="\$ZURL/jikig-ai/soleur-inngest-bootstrap:${zt}@${zd}"
      if docker pull "\$ZIREF"; then IREF="\$ZIREF"; fi
EOF
  cat > "$dir/apps/web-platform/infra/cloud-init-inngest.yml" <<EOF
# fixture cloud-init-inngest.yml
  runcmd:
    IREF=ghcr.io/jikig-ai/soleur-inngest-bootstrap:${it}@${id}
      ZIREF="\$ZOT_EP/jikig-ai/soleur-inngest-bootstrap:${zt}@${zd}"
      if docker pull "\$ZIREF"; then IREF="\$ZIREF"; fi
EOF
}

# reset_state — fresh crane digest map, gh call log, and PR table. Called by
# new_fixture_repo so NO stub state leaks between scenarios (a digest left over
# from an earlier fixture is exactly how a "crane must fail" row false-greens).
reset_state() {
  MOCK_CRANE_MAP="$TMP/crane.$1.map"; : > "$MOCK_CRANE_MAP"
  MOCK_GH_LOG="$TMP/gh.$1.log";     : > "$MOCK_GH_LOG"
  MOCK_GH_PRS="$TMP/gh.$1.prs";     : > "$MOCK_GH_PRS"
  export MOCK_CRANE_MAP MOCK_GH_LOG MOCK_GH_PRS
}

# new_fixture_repo <name> — fresh git repo on `main` with vinngest tags.
# Sets globals: F_REPO (worktree), F_ORIGIN (bare push remote).
new_fixture_repo() {
  local name="$1"
  F_REPO="$TMP/$name/repo"
  F_ORIGIN="$TMP/$name/origin.git"
  mkdir -p "$F_REPO"
  git init -q -b main "$F_REPO"
  # Identity comes from git_fixture_env (env beats repo-local config), so no
  # user.name/user.email is set here: ambient caller env can never re-author a
  # fixture commit.
  git init -q --bare "$F_ORIGIN"
  reset_state "$name"
}

# fixture_commit <msg> — commit all pending changes in F_REPO as the fixture human.
fixture_commit() {
  git -C "$F_REPO" add -A
  git -C "$F_REPO" commit -qm "$1"
}

# seed_tag <vinngest-vX.Y.Z>
seed_tag() { git -C "$F_REPO" tag "$1"; }

# push_branch_to_origin <branch> <author-name> <author-email> — create (or
# overwrite) a branch on the bare origin carrying ONE commit by the given
# identity. Used to seed stale bot branches and human-tipped bot branches.
push_branch_to_origin() {
  local branch="$1" an="$2" ae="$3" sha
  git -C "$F_REPO" checkout -q -B "$branch" main
  git -C "$F_REPO" -c user.name="$an" -c user.email="$ae" \
    commit -q --allow-empty --author="$an <$ae>" -m "seed $branch"
  sha=$(git -C "$F_REPO" rev-parse HEAD)
  git -C "$F_REPO" push -qf "$F_ORIGIN" "HEAD:refs/heads/$branch"
  git -C "$F_REPO" checkout -q main
  printf '%s' "$sha"
}

# ---------------------------------------------------------------------------
# PATH-shimmed stubs
# ---------------------------------------------------------------------------

BIN="$TMP/bin"
mkdir -p "$BIN"

# crane — `crane digest <ref>` serves a per-tag digest map ($MOCK_CRANE_MAP:
# lines of `tag<TAB>digest`). Unknown tag => non-zero, like a 404 manifest.
cat > "$BIN/crane" <<'STUB'
#!/usr/bin/env bash
set -uo pipefail
if [[ "${1:-}" == "digest" && -n "${2:-}" ]]; then
  tag="${2##*:}"
  got=$(awk -F '\t' -v t="$tag" '$1 == t {print $2}' "${MOCK_CRANE_MAP:?unset}" 2>/dev/null | head -1)
  if [[ -n "$got" ]]; then printf '%s\n' "$got"; exit 0; fi
  echo "crane-stub: no digest for $2" >&2; exit 1
fi
echo "crane-stub: unhandled: $*" >&2; exit 1
STUB
chmod +x "$BIN/crane"

# sleep — the script's retry backoff is real wall-clock time (~24s across the
# crane-failure rows, inside a required merge-queue gate). Nothing in the
# script or suite needs a real sleep.
cat > "$BIN/sleep" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
chmod +x "$BIN/sleep"

# gh — records every call to $MOCK_GH_LOG (one line, whitespace flattened) and
# serves the PR surface the script uses. PR state lives in $MOCK_GH_PRS:
#   number|headRefName|url|headRefOid|state[|flags]   (state: open|closed;
#   flags: `fork` => isCrossRepository:true + author.login=fork-user)
# `gh api repos/<r>/commits/<sha>` resolves author.login from the commit's
# author email in $MOCK_ORIGIN (mirrors GitHub's email→login resolution):
# bot noreply => soleur-ai[bot]; anything else => fixture-human.
cat > "$BIN/gh" <<'STUB'
#!/usr/bin/env bash
set -uo pipefail
printf 'gh %s\n' "$*" | tr '\n' ' ' >> "${MOCK_GH_LOG:?unset}"
printf '\n' >> "$MOCK_GH_LOG"
args=("$@")
sub="${args[0]:-} ${args[1]:-}"
BOT_EMAIL='273333864+soleur-ai[bot]@users.noreply.github.com'

flag() { # flag <name> — value of a --flag arg
  local i
  for ((i=0; i<${#args[@]}; i++)); do
    [[ "${args[$i]}" == "$1" ]] && { printf '%s' "${args[$((i+1))]:-}"; return 0; }
  done
}

pr_json() { # emit one PR object from a state line
  local n="$1" h="$2" u="$3" o="$4" s="$5" fl="${6:-}"
  local xr=false al='soleur-ai[bot]'
  if [[ "$fl" == *fork* ]]; then xr=true; al='fork-user'; fi
  # |nullhead flag: GitHub emits headRefName:null for PRs whose head repo or
  # branch was deleted — the supersede jq must skip, not throw mid-pipe.
  if [[ "$fl" == *nullhead* ]]; then
    printf '{"number":%s,"headRefName":null,"url":"%s","headRefOid":"%s","state":"%s","isCrossRepository":%s,"author":{"login":"%s"}}' \
      "$n" "$u" "$o" "$s" "$xr" "$al"
    return
  fi
  printf '{"number":%s,"headRefName":"%s","url":"%s","headRefOid":"%s","state":"%s","isCrossRepository":%s,"author":{"login":"%s"}}' \
    "$n" "$h" "$u" "$o" "$s" "$xr" "$al"
}

case "$sub" in
  "pr list")
    # MOCK_GH_LIST_FAIL_ONCE=1: the FIRST list call dies transiently (marker
    # file arms once per fixture), exercising the script's tolerated-failure
    # and create-collision re-list paths.
    if [[ "${MOCK_GH_LIST_FAIL_ONCE:-0}" == "1" && ! -f "${MOCK_GH_PRS}.list-failed" ]]; then
      : > "${MOCK_GH_PRS}.list-failed"
      echo "mock transient pr list failure" >&2
      exit 1
    fi
    head="$(flag --head)"; want_state="$(flag --state)"; want_state="${want_state:-open}"
    out="["; first=1
    while IFS='|' read -r n h u o s fl; do
      [[ -z "$n" ]] && continue
      [[ "$s" == "$want_state" ]] || continue
      [[ -n "$head" && "$h" != "$head" ]] && continue
      [[ "$first" == 0 ]] && out+=","
      out+="$(pr_json "$n" "$h" "$u" "$o" "$s" "$fl")"; first=0
    done < "${MOCK_GH_PRS:?unset}"
    printf '%s]\n' "$out"
    ;;
  "pr create")
    # MOCK_GH_CREATE_COLLIDE=1: create exits 1 without writing a row —
    # GitHub's "a pull request for branch X already exists" shape.
    [[ "${MOCK_GH_CREATE_COLLIDE:-0}" == "1" ]] \
      && { echo "a pull request for branch already exists" >&2; exit 1; }
    head="$(flag --head)"; title="$(flag --title)"
    n=$(( $(wc -l < "$MOCK_GH_PRS" 2>/dev/null || echo 0) + 1 ))
    url="https://github.test/mock/pull/$n"
    oid=$(git --git-dir="${MOCK_ORIGIN:?unset}" rev-parse "refs/heads/$head" 2>/dev/null || echo "0")
    printf '%s|%s|%s|%s|open\n' "$n" "$head" "$url" "$oid" >> "$MOCK_GH_PRS"
    printf '%s\n' "$url"
    ;;
  "pr comment"|"pr merge")
    [[ "$sub" == "pr merge" && "${MOCK_GH_MERGE_FAIL:-0}" == "1" ]] && { echo "merge arm failed" >&2; exit 1; }
    exit 0
    ;;
  "pr close")
    n="${args[2]:-}"
    # [|] not \|: GNU sed treats \| in ERE as ALTERNATION, so a literal pipe
    # must come from a bracket expression. `open` is replaced in place so an
    # optional trailing |flags field survives.
    sed -i -E "s|^(${n}[|][^|]*[|][^|]*[|][^|]*[|])open|\1closed|" "$MOCK_GH_PRS"
    exit 0
    ;;
  "api "*)
    ep="${args[1]:-}"
    if [[ "$ep" =~ commits/([0-9a-f]{40})$ ]]; then
      sha="${BASH_REMATCH[1]}"
      em=$(git --git-dir="$MOCK_ORIGIN" log -1 --format='%ae' "$sha" 2>/dev/null || true)
      if [[ "$em" == "$BOT_EMAIL" ]]; then login='soleur-ai[bot]'
      elif [[ -n "$em" ]]; then login='fixture-human'
      else login=''
      fi
      # GitHub returns .author.login for a linked account and always carries
      # .commit.author.email (the raw header). MOCK_GH_UNLINKED=1 drops .author
      # to null so the script's email-fallback path is exercised for real.
      if [[ "${MOCK_GH_UNLINKED:-0}" == "1" ]]; then
        printf '{"author":null,"commit":{"author":{"email":"%s"}}}\n' "$em"
      else
        printf '{"author":{"login":"%s"},"commit":{"author":{"email":"%s"}}}\n' "$login" "$em"
      fi
      exit 0
    fi
    echo "gh-stub: unhandled api: $ep" >&2; exit 1
    ;;
  *)
    echo "gh-stub: unhandled: $*" >&2; exit 1
    ;;
esac
STUB
chmod +x "$BIN/gh"

export PATH="$BIN:$PATH"

# ---------------------------------------------------------------------------
# Run helpers
# ---------------------------------------------------------------------------

# run_bump <name> <extra-args...> — invoke the script against the current
# fixture with stub env. Captures stdout+stderr to $TMP/<name>.out, rc to
# LAST_RC, GITHUB_OUTPUT to $TMP/<name>.gout, summary to $TMP/<name>.summary.
run_bump() {
  local name="$1"; shift
  LAST_OUT="$TMP/$name.out"
  LAST_GOUT="$TMP/$name.gout"
  : > "$LAST_GOUT"
  env BUMP_REPO_DIR="$F_REPO" BUMP_PUSH_URL="$F_ORIGIN" \
      GH_TOKEN="fixture-installation-token" \
      MOCK_CRANE_MAP="$MOCK_CRANE_MAP" MOCK_GH_LOG="$MOCK_GH_LOG" \
      MOCK_GH_PRS="$MOCK_GH_PRS" MOCK_ORIGIN="$F_ORIGIN" \
      GITHUB_OUTPUT="$LAST_GOUT" GITHUB_STEP_SUMMARY="$TMP/$name.summary" \
      bash "$SCRIPT" "$@" > "$LAST_OUT" 2>&1
  LAST_RC=$?
}

gout_result() { sed -n 's/^result=//p' "$LAST_GOUT" | tail -1; }

# assert helpers --------------------------------------------------------------
assert_rc() { # name expected-rc
  if [[ "$LAST_RC" == "$2" ]]; then pass "$1"
  else fail "$1" "expected rc=$2, got $LAST_RC — $(tail -5 "$LAST_OUT" | tr '\n' '|')"; fi
}
assert_result() { # name expected-result
  local got; got=$(gout_result)
  if [[ "$got" == "$2" ]]; then pass "$1"
  else fail "$1" "expected result=$2, got '${got:-<none>}' — $(tail -5 "$LAST_OUT" | tr '\n' '|')"; fi
}
assert_out_has() { # name needle
  if grep -qF "$2" "$LAST_OUT"; then pass "$1"
  else fail "$1" "output lacks '$2' — $(tail -5 "$LAST_OUT" | tr '\n' '|')"; fi
}
assert_gh_called() { # name regex — some recorded gh call matches
  if grep -qE "$2" "$MOCK_GH_LOG" 2>/dev/null; then pass "$1"
  else fail "$1" "no gh call matching /$2/"; fi
}
assert_gh_not_called() { # name regex
  if grep -qE "$2" "$MOCK_GH_LOG" 2>/dev/null; then fail "$1" "unexpected gh call matching /$2/"
  else pass "$1"; fi
}

# all_four_refs <file...> — emit every soleur-inngest-bootstrap ref TOKEN (the
# full whitespace/quote-delimited token from the org path on) from the given
# files, one per line. Token-level extraction keeps residue like
# `v1.2.3rc1`-tails visible to the counts below.
all_four_refs() {
  grep -hoE "jikig-ai/soleur-inngest-bootstrap:[^[:space:]\"']*" "$@" | sort
}

assert_all_pins() { # name repo_dir tag digest — 4 refs, all == tag@digest, 2/file, distinct==1
  local name="$1" dir="$2" tag="$3" dig="$4"
  local f1="$dir/apps/web-platform/infra/cloud-init.yml"
  local f2="$dir/apps/web-platform/infra/cloud-init-inngest.yml"
  local want="jikig-ai/soleur-inngest-bootstrap:${tag}@${dig}"
  local n1 n2 tagonly distinct
  # -cxF counts WHOLE-LINE matches — a `…@sha256:…rc1` residue token does not
  # equal the target and cannot inflate the count.
  n1=$(grep -oE "jikig-ai/soleur-inngest-bootstrap:[^[:space:]\"']*" "$f1" | grep -cxF "$want" || true)
  n2=$(grep -oE "jikig-ai/soleur-inngest-bootstrap:[^[:space:]\"']*" "$f2" | grep -cxF "$want" || true)
  [[ "$n1" == "2" && "$n2" == "2" ]] && pass "$name:per-file-2" \
    || fail "$name:per-file-2" "counts $n1/$n2 (expected 2/2 at ${want})"
  tagonly=$(all_four_refs "$f1" "$f2" | grep -vcE '@sha256:' || true)
  [[ "$tagonly" == "0" ]] && pass "$name:no-tag-only" \
    || fail "$name:no-tag-only" "$tagonly tag-only ref(s) remain"
  distinct=$(all_four_refs "$f1" "$f2" | sort -u | wc -l | tr -d ' ')
  [[ "$distinct" == "1" ]] && pass "$name:distinct-1" \
    || fail "$name:distinct-1" "$distinct distinct refs: $(all_four_refs "$f1" "$f2" | sort -u | tr '\n' ',')"
}

assert_origin_branch() { # name branch ABSENT|present|not:<sha>|<sha>
  local name="$1" branch="$2" want="$3" got
  got=$(git --git-dir="$F_ORIGIN" rev-parse -q --verify "refs/heads/$branch" 2>/dev/null || true)
  case "$want" in
    ABSENT)
      [[ -z "$got" ]] && pass "$name" || fail "$name" "branch $branch exists on origin ($got)" ;;
    present)
      [[ -n "$got" ]] && pass "$name" || fail "$name" "branch $branch missing on origin" ;;
    not:*)
      [[ -n "$got" && "$got" != "${want#not:}" ]] && pass "$name" \
        || fail "$name" "branch $branch tip still ${want#not:} — push never landed" ;;
    *)
      [[ "$got" == "$want" ]] && pass "$name" \
        || fail "$name" "branch $branch tip $got != expected $want" ;;
  esac
}

assert_commit_meta() { # name branch msg-regex
  local name="$1" branch="$2" re="$3" subj ae
  subj=$(git --git-dir="$F_ORIGIN" log -1 --format='%s' "$branch" 2>/dev/null || true)
  ae=$(git --git-dir="$F_ORIGIN" log -1 --format='%ae' "$branch" 2>/dev/null || true)
  [[ "$subj" =~ $re ]] && pass "$name:subject" || fail "$name:subject" "subject '$subj' !~ /$re/"
  [[ "$ae" == "$BOT_EMAIL" ]] && pass "$name:bot-email" || fail "$name:bot-email" "author email '$ae'"
}

echo "=== Guard 1: script behavior ==="

# ---------------------------------------------------------------------------
# Row set A — happy path: pin v1.1.37@DIG_OLD, tags …v1.1.37 + v1.1.38, run
# with --signed-tag v1.1.38 --signed-digest DIG_NEW --mirror-status ok.
# ---------------------------------------------------------------------------
new_fixture_repo happy
write_fixture_cloud_inits "$F_REPO" v1.1.37 "$DIG_OLD" v1.1.37 "$DIG_OLD"
fixture_commit "pins at v1.1.37"
seed_tag vinngest-v1.1.37
seed_tag vinngest-v1.1.38
printf 'v1.1.38\t%s\n' "$DIG_NEW" >> "$MOCK_CRANE_MAP"
git -C "$F_REPO" push -q "$F_ORIGIN" main 2>/dev/null || git -C "$F_REPO" push -q "$F_ORIGIN" HEAD:refs/heads/main

run_bump happy --signed-tag v1.1.38 --signed-digest "$DIG_NEW" \
  --mirror-status ok --run-url https://github.test/runs/1
assert_rc     'g1.happy:exit' 0
assert_result 'g1.happy:result' opened
assert_all_pins 'g1.happy:pins' "$F_REPO" v1.1.38 "$DIG_NEW"
assert_origin_branch 'g1.happy:branch' 'soleur/inngest-pin-v1.1.38' present
assert_commit_meta 'g1.happy:commit' 'soleur/inngest-pin-v1.1.38' \
  'chore\(infra\): bump inngest-bootstrap pin v1\.1\.37 -> v1\.1\.38 \(vinngest-v1\.1\.38\)'
assert_gh_called 'g1.happy:pr-create' 'gh pr create '
assert_gh_called 'g1.happy:pr-create-base' 'gh pr create .* --base main'
assert_gh_called 'g1.happy:body-ref'     'Ref #8359'
assert_gh_called 'g1.happy:body-digest'  "$DIG_NEW"
assert_gh_called 'g1.happy:body-run'     'github.test/runs/1'
assert_gh_called 'g1.happy:body-adr'     'ADR-230'
assert_gh_called 'g1.happy:auto-merge'   'gh pr merge .* --auto --squash'
assert_gh_not_called 'g1.happy:no-close' 'gh pr close '
[[ -s "$TMP/happy.summary" ]] && pass 'g1.happy:summary' \
  || fail 'g1.happy:summary' "GITHUB_STEP_SUMMARY file empty — summary() never wrote"

# ---------------------------------------------------------------------------
# Row — noop: pins already at target@resolved → result=noop, zero writes.
# (Guard 1 row 6 anchor: pr create MUST NOT fire on a noop.)
# ---------------------------------------------------------------------------
new_fixture_repo noop
write_fixture_cloud_inits "$F_REPO" v1.1.38 "$DIG_NEW" v1.1.38 "$DIG_NEW"
fixture_commit "pins at v1.1.38"
seed_tag vinngest-v1.1.38
printf 'v1.1.38\t%s\n' "$DIG_NEW" >> "$MOCK_CRANE_MAP"
git -C "$F_REPO" push -q "$F_ORIGIN" HEAD:refs/heads/main

run_bump noop --signed-tag v1.1.38 --signed-digest "$DIG_NEW" --mirror-status ok
assert_rc     'g1.noop:exit' 0
assert_result 'g1.noop:result' noop
assert_gh_not_called 'g1.noop:no-pr-create' 'gh pr create '
assert_gh_not_called 'g1.noop:no-pr-any'    'gh pr '
assert_origin_branch 'g1.noop:no-branch' 'soleur/inngest-pin-v1.1.38' ABSENT
[[ -z $(git -C "$F_REPO" status --porcelain) ]] && pass 'g1.noop:clean-tree' \
  || fail 'g1.noop:clean-tree' "dirty: $(git -C "$F_REPO" status --porcelain | head -3)"

# ---------------------------------------------------------------------------
# Row 3 (mutation matrix): signed tag is NOT the semver-max — v1.1.38 signed
# while vinngest-v1.1.39 exists → the script targets v1.1.39, proving
# max-driven (not arg-driven) selection.
# ---------------------------------------------------------------------------
new_fixture_repo maxwins
write_fixture_cloud_inits "$F_REPO" v1.1.37 "$DIG_OLD" v1.1.37 "$DIG_OLD"
fixture_commit "pins at v1.1.37"
seed_tag vinngest-v1.1.38
seed_tag vinngest-v1.1.39
printf 'v1.1.39\t%s\n' "$DIG_NEWER" >> "$MOCK_CRANE_MAP"
git -C "$F_REPO" push -q "$F_ORIGIN" HEAD:refs/heads/main

run_bump maxwins --signed-tag v1.1.38 --signed-digest "$DIG_NEW" \
  --mirror-status ok --run-url https://github.test/runs/2
assert_rc     'g1.maxwins:exit' 0
assert_result 'g1.maxwins:result' opened
assert_all_pins 'g1.maxwins:pins' "$F_REPO" v1.1.39 "$DIG_NEWER"
assert_origin_branch 'g1.maxwins:branch' 'soleur/inngest-pin-v1.1.39' present
assert_out_has 'g1.maxwins:note' '::notice::signed tag v1.1.38'
# AC9/P2: signed tag ≠ target → mirror_status ok attests the WRONG tag; merge
# must NOT arm and a hold comment must explain why.
assert_gh_not_called 'g1.maxwins:no-merge'      'gh pr merge '
assert_gh_called     'g1.maxwins:hold-comment'  'gh pr comment '

# ---------------------------------------------------------------------------
# Row 5: signed digest ≠ crane-resolved while signed tag IS the max → halt.
# ---------------------------------------------------------------------------
new_fixture_repo mismatch
write_fixture_cloud_inits "$F_REPO" v1.1.37 "$DIG_OLD" v1.1.37 "$DIG_OLD"
fixture_commit "pins at v1.1.37"
seed_tag vinngest-v1.1.38
printf 'v1.1.38\t%s\n' "$DIG_NEW" >> "$MOCK_CRANE_MAP"

run_bump mismatch --signed-tag v1.1.38 --signed-digest "$DIG_OLD" \
  --mirror-status ok
[[ "$LAST_RC" != "0" ]] && pass 'g1.mismatch:nonzero' \
  || fail 'g1.mismatch:nonzero' "rc=0 — signed-vs-resolved mismatch not halted"
assert_result 'g1.mismatch:result' error
assert_out_has 'g1.mismatch:names-signed'   "$DIG_OLD"
assert_out_has 'g1.mismatch:names-resolved' "$DIG_NEW"
assert_gh_not_called 'g1.mismatch:no-pr' 'gh pr '
assert_origin_branch 'g1.mismatch:no-branch' 'soleur/inngest-pin-v1.1.38' ABSENT
[[ -z $(git -C "$F_REPO" status --porcelain) ]] && pass 'g1.mismatch:clean-tree' \
  || fail 'g1.mismatch:clean-tree' "dirty: $(git -C "$F_REPO" status --porcelain | head -3)"

# ---------------------------------------------------------------------------
# Row 5b: signed digest ≠ resolved while signed tag is NOT the max
# (mirror_only backfill of an older tag — the sign step re-signed the
# DISPATCHED tag). Must NOT halt: note + proceed to bump the max.
# ---------------------------------------------------------------------------
new_fixture_repo backfill
write_fixture_cloud_inits "$F_REPO" v1.1.37 "$DIG_OLD" v1.1.37 "$DIG_OLD"
fixture_commit "pins at v1.1.37"
seed_tag vinngest-v1.1.37
seed_tag vinngest-v1.1.38
printf 'v1.1.38\t%s\n' "$DIG_NEW" >> "$MOCK_CRANE_MAP"
git -C "$F_REPO" push -q "$F_ORIGIN" HEAD:refs/heads/main

run_bump backfill --signed-tag v1.1.37 --signed-digest "$DIG_OLD" \
  --mirror-status ok --run-url https://github.test/runs/3
assert_rc     'g1.backfill:exit' 0
assert_result 'g1.backfill:result' opened
assert_all_pins 'g1.backfill:pins' "$F_REPO" v1.1.38 "$DIG_NEW"
assert_out_has 'g1.backfill:note' 'v1.1.37'
# Same AC9/P2 gate as maxwins: a backfill's healthy mirror attests the OLDER
# dispatched tag, not the target — no arm, hold comment instead.
assert_gh_not_called 'g1.backfill:no-merge'     'gh pr merge '
assert_gh_called     'g1.backfill:hold-comment' 'gh pr comment '

# ---------------------------------------------------------------------------
# Row 1: partial prior bump — IREF already at target, ZIREF stale → all four
# converge; no tag-only ref survives.
# ---------------------------------------------------------------------------
new_fixture_repo partial
write_fixture_cloud_inits "$F_REPO" v1.1.38 "$DIG_NEW" v1.1.37 "$DIG_OLD"
fixture_commit "partial bump"
seed_tag vinngest-v1.1.38
printf 'v1.1.38\t%s\n' "$DIG_NEW" >> "$MOCK_CRANE_MAP"
git -C "$F_REPO" push -q "$F_ORIGIN" HEAD:refs/heads/main

run_bump partial --signed-tag v1.1.38 --signed-digest "$DIG_NEW" --mirror-status ok
assert_rc     'g1.partial:exit' 0
assert_result 'g1.partial:result' opened
assert_all_pins 'g1.partial:pins' "$F_REPO" v1.1.38 "$DIG_NEW"

# ---------------------------------------------------------------------------
# SpecFlow (h): a tag-only ref is upgraded to full tag+digest, never left bare.
# ---------------------------------------------------------------------------
new_fixture_repo tagonly
write_fixture_cloud_inits "$F_REPO" v1.1.37 "$DIG_OLD" v1.1.37 "$DIG_OLD"
# Strip the digest from the ZIREF site of one file → tag-only ref.
sed -i -E 's|(soleur-inngest-bootstrap:v1\.1\.37)@sha256:[0-9a-f]{64}|\1|' \
  "$F_REPO/apps/web-platform/infra/cloud-init-inngest.yml"
fixture_commit "tag-only ziref"
seed_tag vinngest-v1.1.38
printf 'v1.1.38\t%s\n' "$DIG_NEW" >> "$MOCK_CRANE_MAP"
git -C "$F_REPO" push -q "$F_ORIGIN" HEAD:refs/heads/main

run_bump tagonly --signed-tag v1.1.38 --signed-digest "$DIG_NEW" --mirror-status ok
assert_rc     'g1.tagonly:exit' 0
assert_all_pins 'g1.tagonly:pins' "$F_REPO" v1.1.38 "$DIG_NEW"

# ---------------------------------------------------------------------------
# Row 4: remote bot-branch tip carries a HUMAN commit → branch-has-manual-commits,
# no push, no PR.
# ---------------------------------------------------------------------------
new_fixture_repo humantip
write_fixture_cloud_inits "$F_REPO" v1.1.37 "$DIG_OLD" v1.1.37 "$DIG_OLD"
fixture_commit "pins at v1.1.37"
seed_tag vinngest-v1.1.38
printf 'v1.1.38\t%s\n' "$DIG_NEW" >> "$MOCK_CRANE_MAP"
git -C "$F_REPO" push -q "$F_ORIGIN" HEAD:refs/heads/main
# Seed the bot branch on origin with a HUMAN-tipped commit.
push_branch_to_origin 'soleur/inngest-pin-v1.1.38' 'fixture-human' 'human@example.test' >/dev/null

run_bump humantip --signed-tag v1.1.38 --signed-digest "$DIG_NEW" --mirror-status ok
assert_rc     'g1.humantip:exit' 0
assert_result 'g1.humantip:result' skipped
assert_out_has 'g1.humantip:marker' 'branch-has-manual-commits'
assert_gh_not_called 'g1.humantip:no-pr' 'gh pr '
# The human tip must still be the remote tip (not clobbered).
[[ $(git --git-dir="$F_ORIGIN" log -1 --format='%ae' 'soleur/inngest-pin-v1.1.38') == 'human@example.test' ]] \
  && pass 'g1.humantip:tip-preserved' || fail 'g1.humantip:tip-preserved' "human tip was force-pushed over"

# Same shape, BOT-tipped remote branch → force-push allowed through.
new_fixture_repo bottip
write_fixture_cloud_inits "$F_REPO" v1.1.37 "$DIG_OLD" v1.1.37 "$DIG_OLD"
fixture_commit "pins at v1.1.37"
seed_tag vinngest-v1.1.38
printf 'v1.1.38\t%s\n' "$DIG_NEW" >> "$MOCK_CRANE_MAP"
git -C "$F_REPO" push -q "$F_ORIGIN" HEAD:refs/heads/main
# Seed sha captured: %ae alone is vacuous here (the seed ALREADY carries the
# bot email) — the sha must MOVE and the new tip must be the bump commit.
seed_sha=$(push_branch_to_origin 'soleur/inngest-pin-v1.1.38' 'soleur-ai[bot]' "$BOT_EMAIL")

run_bump bottip --signed-tag v1.1.38 --signed-digest "$DIG_NEW" --mirror-status ok
assert_rc     'g1.bottip:exit' 0
assert_result 'g1.bottip:result' opened
assert_origin_branch 'g1.bottip:tip-advanced' 'soleur/inngest-pin-v1.1.38' "not:$seed_sha"
assert_commit_meta 'g1.bottip:commit' 'soleur/inngest-pin-v1.1.38' \
  'chore\(infra\): bump inngest-bootstrap pin v1\.1\.37 -> v1\.1\.38'
assert_gh_called 'g1.bottip:pr-create' 'gh pr create '

# Same shape again but GitHub links NO account to the tip commit (.author
# null): the script must fall back to .commit.author.email — a bot email still
# pushes, a human email still skips.
new_fixture_repo unlinkedbot
write_fixture_cloud_inits "$F_REPO" v1.1.37 "$DIG_OLD" v1.1.37 "$DIG_OLD"
fixture_commit "pins at v1.1.37"
seed_tag vinngest-v1.1.38
printf 'v1.1.38\t%s\n' "$DIG_NEW" >> "$MOCK_CRANE_MAP"
git -C "$F_REPO" push -q "$F_ORIGIN" HEAD:refs/heads/main
seed_sha=$(push_branch_to_origin 'soleur/inngest-pin-v1.1.38' 'soleur-ai[bot]' "$BOT_EMAIL")

MOCK_GH_UNLINKED=1 run_bump unlinkedbot --signed-tag v1.1.38 --signed-digest "$DIG_NEW" --mirror-status ok
assert_rc     'g1.unlinkedbot:exit' 0
assert_result 'g1.unlinkedbot:result' opened
assert_origin_branch 'g1.unlinkedbot:tip-advanced' 'soleur/inngest-pin-v1.1.38' "not:$seed_sha"

new_fixture_repo unlinkedhuman
write_fixture_cloud_inits "$F_REPO" v1.1.37 "$DIG_OLD" v1.1.37 "$DIG_OLD"
fixture_commit "pins at v1.1.37"
seed_tag vinngest-v1.1.38
printf 'v1.1.38\t%s\n' "$DIG_NEW" >> "$MOCK_CRANE_MAP"
git -C "$F_REPO" push -q "$F_ORIGIN" HEAD:refs/heads/main
push_branch_to_origin 'soleur/inngest-pin-v1.1.38' 'fixture-human' 'human@example.test' >/dev/null

MOCK_GH_UNLINKED=1 run_bump unlinkedhuman --signed-tag v1.1.38 --signed-digest "$DIG_NEW" --mirror-status ok
assert_rc     'g1.unlinkedhuman:exit' 0
assert_result 'g1.unlinkedhuman:result' skipped
assert_out_has 'g1.unlinkedhuman:marker' 'branch-has-manual-commits'
[[ $(git --git-dir="$F_ORIGIN" log -1 --format='%ae' 'soleur/inngest-pin-v1.1.38') == 'human@example.test' ]] \
  && pass 'g1.unlinkedhuman:tip-preserved' || fail 'g1.unlinkedhuman:tip-preserved' "unlinked human tip clobbered"

# ---------------------------------------------------------------------------
# Row — existing PR for the same branch: comment + result=existing, no 2nd PR.
# ---------------------------------------------------------------------------
new_fixture_repo existing
write_fixture_cloud_inits "$F_REPO" v1.1.37 "$DIG_OLD" v1.1.37 "$DIG_OLD"
fixture_commit "pins at v1.1.37"
seed_tag vinngest-v1.1.38
printf 'v1.1.38\t%s\n' "$DIG_NEW" >> "$MOCK_CRANE_MAP"
git -C "$F_REPO" push -q "$F_ORIGIN" HEAD:refs/heads/main
# First run opens the PR.
run_bump existing1 --signed-tag v1.1.38 --signed-digest "$DIG_NEW" --mirror-status ok
assert_result 'g1.existing:first' opened
# Second identical run must not stack a second PR. Back on `main` the pins are
# still at the OLD values — the PR is open but unmerged, which is exactly the
# state a second CI run meets.
git -C "$F_REPO" checkout -q main
run_bump existing2 --signed-tag v1.1.38 --signed-digest "$DIG_NEW" --mirror-status ok
assert_result 'g1.existing:second' existing
assert_gh_called 'g1.existing:comment' 'gh pr comment '
assert_gh_called 'g1.existing:merge-arm' 'gh pr merge '
[[ $(grep -c 'gh pr create ' "$MOCK_GH_LOG") == "1" ]] && pass 'g1.existing:one-create' \
  || fail 'g1.existing:one-create' "$(grep -c 'gh pr create ' "$MOCK_GH_LOG") pr create calls"

# ---------------------------------------------------------------------------
# Row — create collision: the tolerated first `pr list` failure hides an
# existing same-repo bot PR; `pr create` then reports "already exists". The
# script must re-list through the same filter and reuse it — result=existing,
# merge armed on the EXISTING number, no new PR row.
# ---------------------------------------------------------------------------
new_fixture_repo collide
write_fixture_cloud_inits "$F_REPO" v1.1.37 "$DIG_OLD" v1.1.37 "$DIG_OLD"
fixture_commit "pins at v1.1.37"
seed_tag vinngest-v1.1.38
printf 'v1.1.38\t%s\n' "$DIG_NEW" >> "$MOCK_CRANE_MAP"
git -C "$F_REPO" push -q "$F_ORIGIN" HEAD:refs/heads/main
# Pre-existing same-repo bot PR for the very branch this run will push — the
# first (head-filtered) list call fails transiently, so create collides with it.
collide_sha=$(git -C "$F_REPO" rev-parse HEAD)
printf '9|soleur/inngest-pin-v1.1.38|https://github.test/mock/pull/9|%s|open\n' "$collide_sha" >> "$MOCK_GH_PRS"

MOCK_GH_LIST_FAIL_ONCE=1 MOCK_GH_CREATE_COLLIDE=1 \
  run_bump collide --signed-tag v1.1.38 --signed-digest "$DIG_NEW" --mirror-status ok
assert_rc     'g1.collide:exit' 0
assert_result 'g1.collide:result' existing
assert_gh_called 'g1.collide:merge-own' 'gh pr merge 9 '
assert_gh_called 'g1.collide:relist' 'gh pr list .*--head soleur/inngest-pin-v1.1.38'
[[ $(wc -l < "$MOCK_GH_PRS") == "1" ]] && pass 'g1.collide:no-new-pr' \
  || fail 'g1.collide:no-new-pr' "state rows after collision: $(cat "$MOCK_GH_PRS")"

# ---------------------------------------------------------------------------
# AC9 — degraded mirror: PR opens, auto-merge NOT armed, hold comment lands.
# ---------------------------------------------------------------------------
new_fixture_repo degraded
write_fixture_cloud_inits "$F_REPO" v1.1.37 "$DIG_OLD" v1.1.37 "$DIG_OLD"
fixture_commit "pins at v1.1.37"
seed_tag vinngest-v1.1.38
printf 'v1.1.38\t%s\n' "$DIG_NEW" >> "$MOCK_CRANE_MAP"
git -C "$F_REPO" push -q "$F_ORIGIN" HEAD:refs/heads/main

run_bump degraded --signed-tag v1.1.38 --signed-digest "$DIG_NEW" --mirror-status degraded
assert_rc     'g1.degraded:exit' 0
assert_result 'g1.degraded:result' opened
assert_gh_called     'g1.degraded:pr-create' 'gh pr create '
assert_gh_not_called 'g1.degraded:no-merge'  'gh pr merge '
assert_gh_called     'g1.degraded:hold-comment' 'gh pr comment '

# ---------------------------------------------------------------------------
# AC9 — merge-arm failure is ::warning, never fatal.
# ---------------------------------------------------------------------------
new_fixture_repo mergefail
write_fixture_cloud_inits "$F_REPO" v1.1.37 "$DIG_OLD" v1.1.37 "$DIG_OLD"
fixture_commit "pins at v1.1.37"
seed_tag vinngest-v1.1.38
printf 'v1.1.38\t%s\n' "$DIG_NEW" >> "$MOCK_CRANE_MAP"
git -C "$F_REPO" push -q "$F_ORIGIN" HEAD:refs/heads/main

MOCK_GH_MERGE_FAIL=1 run_bump mergefail --signed-tag v1.1.38 \
  --signed-digest "$DIG_NEW" --mirror-status ok
assert_rc     'g1.mergefail:exit' 0
assert_result 'g1.mergefail:result' opened
assert_out_has 'g1.mergefail:warning' '::warning::'

# ---------------------------------------------------------------------------
# AC8 — supersede: open bot-authored pin PR for an OLDER target is closed with
# a Superseded-by comment; a human-tipped stale pin PR is left alone.
# ---------------------------------------------------------------------------
new_fixture_repo supersede
write_fixture_cloud_inits "$F_REPO" v1.1.37 "$DIG_OLD" v1.1.37 "$DIG_OLD"
fixture_commit "pins at v1.1.37"
seed_tag vinngest-v1.1.38
printf 'v1.1.38\t%s\n' "$DIG_NEW" >> "$MOCK_CRANE_MAP"
git -C "$F_REPO" push -q "$F_ORIGIN" HEAD:refs/heads/main
# Stale bot PR for the previous target.
old_sha=$(push_branch_to_origin 'soleur/inngest-pin-v1.1.37' 'soleur-ai[bot]' "$BOT_EMAIL")
printf '7|soleur/inngest-pin-v1.1.37|https://github.test/mock/pull/7|%s|open\n' "$old_sha" >> "$MOCK_GH_PRS"
# A null-headRefName PR (head repo deleted upstream) sits in the same list
# output — the supersede jq must skip it without aborting the sweep.
printf '6|deleted-head|https://github.test/mock/pull/6|%s|open|nullhead\n' "$old_sha" >> "$MOCK_GH_PRS"

run_bump supersede --signed-tag v1.1.38 --signed-digest "$DIG_NEW" --mirror-status ok
assert_rc 'g1.supersede:exit' 0
assert_gh_called 'g1.supersede:close'      'gh pr close 7'
assert_gh_called 'g1.supersede:comment'    'gh pr comment 7 .*Superseded by https://github.test/mock/pull/'
assert_gh_not_called 'g1.supersede:nullhead-skip' 'gh pr close 6'
grep -qE '^7\|[^|]*\|[^|]*\|[^|]*\|closed$' "$MOCK_GH_PRS" && pass 'g1.supersede:state-closed' \
  || fail 'g1.supersede:state-closed' "PR 7 not marked closed: $(cat "$MOCK_GH_PRS")"

# Same but the stale PR's branch tip is HUMAN → never closed.
new_fixture_repo supersede-human
write_fixture_cloud_inits "$F_REPO" v1.1.37 "$DIG_OLD" v1.1.37 "$DIG_OLD"
fixture_commit "pins at v1.1.37"
seed_tag vinngest-v1.1.38
printf 'v1.1.38\t%s\n' "$DIG_NEW" >> "$MOCK_CRANE_MAP"
git -C "$F_REPO" push -q "$F_ORIGIN" HEAD:refs/heads/main
old_sha=$(push_branch_to_origin 'soleur/inngest-pin-v1.1.37' 'fixture-human' 'human@example.test')
printf '8|soleur/inngest-pin-v1.1.37|https://github.test/mock/pull/8|%s|open\n' "$old_sha" >> "$MOCK_GH_PRS"

run_bump supersede-human --signed-tag v1.1.38 --signed-digest "$DIG_NEW" --mirror-status ok
assert_rc 'g1.supersede-human:exit' 0
assert_gh_not_called 'g1.supersede-human:no-close' 'gh pr close 8'
grep -qE '^8\|[^|]*\|[^|]*\|[^|]*\|open$' "$MOCK_GH_PRS" && pass 'g1.supersede-human:state-open' \
  || fail 'g1.supersede-human:state-open' "human-tipped PR 8 was closed"

# ---------------------------------------------------------------------------
# Fail-closed arg validation (AC/contract): malformed inputs die non-zero with
# no writes.
# ---------------------------------------------------------------------------
new_fixture_repo badargs
write_fixture_cloud_inits "$F_REPO" v1.1.37 "$DIG_OLD" v1.1.37 "$DIG_OLD"
fixture_commit "pins"
seed_tag vinngest-v1.1.38
printf 'v1.1.38\t%s\n' "$DIG_NEW" >> "$MOCK_CRANE_MAP"

run_bump badtag --signed-tag 'v1.1' --signed-digest "$DIG_NEW" --mirror-status ok
[[ "$LAST_RC" != "0" ]] && pass 'g1.badtag:nonzero' || fail 'g1.badtag:nonzero' "accepted tag 'v1.1'"
assert_gh_not_called 'g1.badtag:no-gh' 'gh pr '

run_bump baddig --signed-tag v1.1.38 --signed-digest 'sha256:xyz' --mirror-status ok
[[ "$LAST_RC" != "0" ]] && pass 'g1.baddig:nonzero' || fail 'g1.baddig:nonzero' "accepted digest 'sha256:xyz'"

run_bump badmirror --signed-tag v1.1.38 --signed-digest "$DIG_NEW" --mirror-status bogus
[[ "$LAST_RC" != "0" ]] && pass 'g1.badmirror:nonzero' || fail 'g1.badmirror:nonzero' "accepted mirror-status 'bogus'"

# crane unresolvable → fail closed at resolve, no writes.
new_fixture_repo noresolve
write_fixture_cloud_inits "$F_REPO" v1.1.37 "$DIG_OLD" v1.1.37 "$DIG_OLD"
fixture_commit "pins"
seed_tag vinngest-v1.1.38
# (crane map deliberately empty for v1.1.38)
run_bump noresolve --signed-tag v1.1.38 --signed-digest "$DIG_NEW" --mirror-status ok
[[ "$LAST_RC" != "0" ]] && pass 'g1.noresolve:nonzero' || fail 'g1.noresolve:nonzero' "crane failure not halted"
assert_origin_branch 'g1.noresolve:no-branch' 'soleur/inngest-pin-v1.1.38' ABSENT
[[ -z $(git -C "$F_REPO" status --porcelain) ]] && pass 'g1.noresolve:clean-tree' \
  || fail 'g1.noresolve:clean-tree' "dirty: $(git -C "$F_REPO" status --porcelain | head -3)"

# crane unresolvable for the semver-max while THIS run published a non-max tag:
# the max tag's own publish is still in flight, so the run DEFERS
# (result=skipped, rc 0) instead of erroring on a self-healing race. The
# error path is preserved for signed==target (noresolve above).
new_fixture_repo defer
write_fixture_cloud_inits "$F_REPO" v1.1.37 "$DIG_OLD" v1.1.37 "$DIG_OLD"
fixture_commit "pins"
seed_tag vinngest-v1.1.37
seed_tag vinngest-v1.1.38
# (crane map deliberately empty for v1.1.38 — its publish is in flight)
git -C "$F_REPO" push -q "$F_ORIGIN" HEAD:refs/heads/main
run_bump defer --signed-tag v1.1.37 --signed-digest "$DIG_OLD" --mirror-status ok
assert_rc     'g1.defer:exit' 0
assert_result 'g1.defer:result' skipped
assert_out_has 'g1.defer:warning' '::warning::'
assert_out_has 'g1.defer:self-heal' 'does not self-heal'
assert_origin_branch 'g1.defer:no-branch' 'soleur/inngest-pin-v1.1.38' ABSENT
assert_gh_not_called 'g1.defer:no-pr' 'gh pr '
[[ -z $(git -C "$F_REPO" status --porcelain) ]] && pass 'g1.defer:clean-tree' \
  || fail 'g1.defer:clean-tree' "dirty: $(git -C "$F_REPO" status --porcelain | head -3)"

# ---------------------------------------------------------------------------
# Review P2 (security): a FORK PR whose headRefName collides with the bump
# branch must never be selected — the script filters isCrossRepository +
# author.login, so it creates its own PR and arms --auto on THAT number.
# ---------------------------------------------------------------------------
new_fixture_repo forkpr
write_fixture_cloud_inits "$F_REPO" v1.1.37 "$DIG_OLD" v1.1.37 "$DIG_OLD"
fixture_commit "pins at v1.1.37"
seed_tag vinngest-v1.1.38
printf 'v1.1.38\t%s\n' "$DIG_NEW" >> "$MOCK_CRANE_MAP"
git -C "$F_REPO" push -q "$F_ORIGIN" HEAD:refs/heads/main
old_sha=$(push_branch_to_origin 'soleur/inngest-pin-v1.1.38' 'soleur-ai[bot]' "$BOT_EMAIL")
# A fork PR wearing the same headRefName — real `gh pr list --head` returns it.
printf '9|soleur/inngest-pin-v1.1.38|https://github.test/mock/pull/9|%s|open|fork\n' "$old_sha" >> "$MOCK_GH_PRS"

run_bump forkpr --signed-tag v1.1.38 --signed-digest "$DIG_NEW" --mirror-status ok
assert_rc     'g1.forkpr:exit' 0
assert_result 'g1.forkpr:result' opened
assert_gh_called     'g1.forkpr:created-own'    'gh pr create '
# The stub numbers the create response 2 (one seeded row); PR_NUM comes from
# the create URL — the merge arm must target it, never the fork's #9.
assert_gh_called     'g1.forkpr:merge-own'      'gh pr merge 2 '
assert_gh_not_called 'g1.forkpr:no-fork-merge'  'gh pr merge 9'
assert_gh_not_called 'g1.forkpr:no-fork-reuse'  'gh pr comment 9 .*Re-run of the automated pin bump'

# ---------------------------------------------------------------------------
# Review P2 (data-integrity): malformed refs — `v1.1.37rc1` and a 65-hex
# digest — must die at the bounded count check, never be rewritten into
# residue-carrying refs that pass every post-check.
# ---------------------------------------------------------------------------
new_fixture_repo residuetag
write_fixture_cloud_inits "$F_REPO" 'v1.1.37rc1' "$DIG_OLD" v1.1.37 "$DIG_OLD"
fixture_commit "malformed rc1 pin"
seed_tag vinngest-v1.1.38
printf 'v1.1.38\t%s\n' "$DIG_NEW" >> "$MOCK_CRANE_MAP"

run_bump residuetag --signed-tag v1.1.38 --signed-digest "$DIG_NEW" --mirror-status ok
[[ "$LAST_RC" != "0" ]] && pass 'g1.residuetag:nonzero' \
  || fail 'g1.residuetag:nonzero' "rc=0 — a v1.1.37rc1 ref was not refused"
assert_result 'g1.residuetag:result' error
assert_out_has 'g1.residuetag:marker' 'expected exactly 2'
assert_origin_branch 'g1.residuetag:no-branch' 'soleur/inngest-pin-v1.1.38' ABSENT
[[ -z $(git -C "$F_REPO" status --porcelain) ]] && pass 'g1.residuetag:clean-tree' \
  || fail 'g1.residuetag:clean-tree' "malformed ref was still rewritten"

new_fixture_repo residuedig
write_fixture_cloud_inits "$F_REPO" v1.1.37 "${DIG_OLD}f" v1.1.37 "$DIG_OLD"
fixture_commit "malformed 65-hex pin"
seed_tag vinngest-v1.1.38
printf 'v1.1.38\t%s\n' "$DIG_NEW" >> "$MOCK_CRANE_MAP"

run_bump residuedig --signed-tag v1.1.38 --signed-digest "$DIG_NEW" --mirror-status ok
[[ "$LAST_RC" != "0" ]] && pass 'g1.residuedig:nonzero' \
  || fail 'g1.residuedig:nonzero' "rc=0 — a 65-hex digest was not refused"
assert_out_has 'g1.residuedig:marker' 'expected exactly 2'

# ---------------------------------------------------------------------------
# Review P2 (code-quality): a valueless trailing flag must die at args, not
# spin the while loop until the job timeout (pre-fix behavior: rc=124 hang).
# ---------------------------------------------------------------------------
run_bump missingval --signed-tag
[[ "$LAST_RC" != "0" ]] && pass 'g1.missingval:nonzero' \
  || fail 'g1.missingval:nonzero' "rc=0 — valueless --signed-tag accepted"
assert_out_has 'g1.missingval:marker' 'missing value for --signed-tag'
assert_result 'g1.missingval:result' error

run_bump unknownarg --bogus x
[[ "$LAST_RC" != "0" ]] && pass 'g1.unknownarg:nonzero' \
  || fail 'g1.unknownarg:nonzero' "rc=0 — unknown arg accepted"
assert_out_has 'g1.unknownarg:marker' 'unknown argument: --bogus'

# GH_TOKEN absent + no BUMP_PUSH_URL → the x-access-token URL can't be built.
LAST_OUT="$TMP/missingtoken.out"; LAST_GOUT="$TMP/missingtoken.gout"; : > "$LAST_GOUT"
env -u GH_TOKEN BUMP_REPO_DIR="$F_REPO" GITHUB_OUTPUT="$LAST_GOUT" \
  bash "$SCRIPT" --signed-tag v1.1.38 --signed-digest "$DIG_NEW" \
  > "$LAST_OUT" 2>&1; LAST_RC=$?
[[ "$LAST_RC" != "0" ]] && pass 'g1.missingtoken:nonzero' \
  || fail 'g1.missingtoken:nonzero' "rc=0 — missing GH_TOKEN accepted"
assert_out_has 'g1.missingtoken:marker' 'GH_TOKEN'

LAST_OUT="$TMP/baddir.out"; LAST_GOUT="$TMP/baddir.gout"; : > "$LAST_GOUT"
env BUMP_REPO_DIR=/nonexistent-xyz GH_TOKEN=x GITHUB_OUTPUT="$LAST_GOUT" \
  bash "$SCRIPT" --signed-tag v1.1.38 --signed-digest "$DIG_NEW" \
  > "$LAST_OUT" 2>&1; LAST_RC=$?
[[ "$LAST_RC" != "0" ]] && pass 'g1.baddir:nonzero' \
  || fail 'g1.baddir:nonzero' "rc=0 — nonexistent BUMP_REPO_DIR accepted"
assert_out_has 'g1.baddir:marker' 'not a directory'

# ---------------------------------------------------------------------------
# Review P2 (security): GIT_TRACE*/GIT_CURL_VERBOSE must be scrubbed — they
# echo the credential-bearing push URL to stderr (same leak class the xtrace
# refusal exists for). Run in a subshell so the trace env cannot leak into the
# suite's own git calls.
# ---------------------------------------------------------------------------
new_fixture_repo gittrace
write_fixture_cloud_inits "$F_REPO" v1.1.37 "$DIG_OLD" v1.1.37 "$DIG_OLD"
fixture_commit "pins at v1.1.37"
seed_tag vinngest-v1.1.38
printf 'v1.1.38\t%s\n' "$DIG_NEW" >> "$MOCK_CRANE_MAP"
git -C "$F_REPO" push -q "$F_ORIGIN" HEAD:refs/heads/main

( export GIT_TRACE=1 GIT_CURL_VERBOSE=1
  run_bump gittrace --signed-tag v1.1.38 --signed-digest "$DIG_NEW" --mirror-status ok )
gt_rc=$?
[[ "$gt_rc" == "0" ]] && pass 'g1.gittrace:exit' \
  || fail 'g1.gittrace:exit' "rc=$gt_rc — $(tail -3 "$TMP/gittrace.out" | tr '\n' '|')"
if grep -q 'fixture-installation-token' "$TMP/gittrace.out"; then
  fail 'g1.gittrace:no-token' "GIT_TRACE leaked the push-URL token into output"
else
  pass 'g1.gittrace:no-token'
fi
if grep -qE '^(trace:|Run command|run_command)' "$TMP/gittrace.out"; then
  fail 'g1.gittrace:no-trace' "git trace lines present — GIT_TRACE not scrubbed"
else
  pass 'g1.gittrace:no-trace'
fi

echo ""
echo "=== Guard 2: workflow shape + regex parity ==="

check_wf() { # name needle — literal present
  if grep -qF -- "$2" "$WORKFLOW"; then pass "$1"
  else fail "$1" "workflow lacks literal: $2"; fi
}
check_wf_absent() { # name regex — must NOT match anywhere in the workflow
  if grep -qE -- "$2" "$WORKFLOW"; then fail "$1" "workflow contains forbidden /$2/"
  else pass "$1"; fi
}

# Slice the bump job block: `  bump-cloud-init-pin:` → next job key at the same
# indent or EOF. Job-level asserts quantify over THIS block, not the file. The
# terminator excludes the opener by its EXACT key (`^  bump-cloud-init-pin:`),
# not a substring — a `rebuild:`/`sub-bump:` key must not be absorbed.
BUMP_BLOCK=$(awk '/^  bump-cloud-init-pin:/{f=1} f&&/^  [a-zA-Z_][a-zA-Z0-9_-]*:/&&!/^  bump-cloud-init-pin:/{f=0} f' "$WORKFLOW")
[[ -n "$BUMP_BLOCK" ]] && pass 'g2.bump-job:exists' || fail 'g2.bump-job:exists' "no bump-cloud-init-pin job in workflow"

check_block() { # name needle
  if grep -qF -- "$2" <<<"$BUMP_BLOCK"; then pass "$1"
  else fail "$1" "bump-cloud-init-pin job lacks: $2"; fi
}
check_block_absent() { # name regex
  if grep -qE -- "$2" <<<"$BUMP_BLOCK"; then fail "$1" "bump-cloud-init-pin job contains forbidden /$2/"
  else pass "$1"; fi
}

check_block 'g2.bump:needs-build'            'needs: build'
check_block 'g2.bump:ref-main'               'ref: main'
check_block 'g2.bump:fetch-depth'            'fetch-depth: 0'
check_block 'g2.bump:fetch-tags'             'fetch-tags: true'
check_block 'g2.bump:persist-creds-false'    'persist-credentials: false'
# The concurrency literals must live inside the job's `concurrency:` mapping —
# a comment or unrelated step carrying the same text must not green them.
CONC_BLOCK=$(awk '/^    concurrency:/{f=1} f&&/^    [a-zA-Z_][a-zA-Z0-9_-]*:/&&!/^    concurrency:/{f=0} f' <<<"$BUMP_BLOCK")
if grep -qF 'group: inngest-pin-bump' <<<"$CONC_BLOCK" \
   && grep -qF 'cancel-in-progress: false' <<<"$CONC_BLOCK"; then
  pass 'g2.bump:concurrency-block'
else
  fail 'g2.bump:concurrency-block' "concurrency mapping wrong or absent: $(tr '\n' '|' <<<"$CONC_BLOCK")"
fi
check_block 'g2.bump:contents-read'          'contents: read'
# P1 (review): the package is private in GHCR and the build job's login does
# not cross job boundaries — the bump job must carry packages:read + its own
# GHCR login or `crane digest` fails on every live run.
check_block 'g2.bump:packages-read'          'packages: read'
check_block 'g2.bump:ghcr-login'             'docker/login-action'
check_block 'g2.bump:ghcr-registry'          'registry: ghcr.io'
check_block 'g2.bump:doppler-token-verify'   'DOPPLER_TOKEN'
# P3 (review): the inline App-JWT recipe is extracted to a composite action —
# the workflow wires the action, the recipe lives in the action file.
check_block 'g2.bump:mint-action'            'uses: ./.github/actions/mint-soleur-ai-app-token'
check_block 'g2.bump:mint-id'                'id: mint'
check_block 'g2.bump:mint-token-env'         'steps.mint.outputs.token'
check_block 'g2.bump:installation-id'        '122213433'
check_block 'g2.bump:script-invoked'         'bump-inngest-bootstrap-pin.sh'
# Binding-level asserts (not literal presence): a swapped or miswired value —
# digest into --signed-tag, a different token output — must fail here.
check_block 'g2.bump:env-tag-binding'        'TAG: ${{ needs.build.outputs.tag }}'
check_block 'g2.bump:env-digest-binding'     'SIGNED_DIGEST: ${{ needs.build.outputs.digest }}'
check_block 'g2.bump:env-mirror-binding'     'MIRROR_STATUS: ${{ needs.build.outputs.mirror_status }}'
check_block 'g2.bump:env-gh-token-binding'   'GH_TOKEN: ${{ steps.mint.outputs.token }}'
check_block 'g2.bump:invoke-signed-tag'      '--signed-tag "$TAG"'
check_block 'g2.bump:invoke-signed-digest'   '--signed-digest "$SIGNED_DIGEST"'
check_block 'g2.bump:invoke-mirror-status'   '--mirror-status "$MIRROR_STATUS"'
check_block 'g2.bump:invoke-run-url'         '--run-url "$RUN_URL"'
check_block 'g2.bump:failure-slack'          'SLACK_RELEASES_WEBHOOK_URL'
check_block 'g2.bump:timeout'                'timeout-minutes: 10'

# `if: failure()` + `continue-on-error: true` must live on the SLACK step
# specifically — a stray literal anywhere else in the job must not satisfy it.
slack_line=$(grep -n 'SLACK_RELEASES_WEBHOOK_URL' <<<"$BUMP_BLOCK" | head -1 | cut -d: -f1)
if [[ -z "$slack_line" ]]; then
  fail 'g2.bump:slack-step' "no SLACK_RELEASES_WEBHOOK_URL in the bump job"
else
  s_start=$(awk -v n="$slack_line" 'NR<=n && /^      - /{s=NR} END{print s+0}' <<<"$BUMP_BLOCK")
  s_end=$(awk -v n="$slack_line" 'NR>n && /^      - /{print NR-1; f=1; exit} END{if(!f) print NR}' <<<"$BUMP_BLOCK")
  SLACK_STEP=$(sed -n "${s_start},${s_end}p" <<<"$BUMP_BLOCK")
  grep -qF 'if: failure()' <<<"$SLACK_STEP" && pass 'g2.bump:slack-if-failure' \
    || fail 'g2.bump:slack-if-failure' "Slack step lacks if: failure()"
  grep -qF 'continue-on-error: true' <<<"$SLACK_STEP" && pass 'g2.bump:slack-continue-on-error' \
    || fail 'g2.bump:slack-continue-on-error' "Slack step lacks continue-on-error: true"
fi

# The extracted composite action must carry the JWT recipe verbatim — the same
# anchors the bump block used to pin when the recipe was inline.
ACTION="$REPO_ROOT/.github/actions/mint-soleur-ai-app-token/action.yml"
check_action() { # name needle
  if [[ -f "$ACTION" ]] && grep -qF -- "$2" "$ACTION"; then pass "$1"
  else fail "$1" "mint-soleur-ai-app-token action lacks: $2"; fi
}
check_action 'g2.action:exists'           "using: 'composite'"
check_action 'g2.action:doppler-config'   'prd_terraform'
check_action 'g2.action:app-id'           'GITHUB_APP_ID'
check_action 'g2.action:app-key'          'GITHUB_APP_PRIVATE_KEY'
check_action 'g2.action:b64url'           "b64url() { base64 -w 0 | tr '+/' '-_' | tr -d '=\\n'; }"
check_action 'g2.action:jwt-exchange'     'access_tokens'
check_action 'g2.action:openssl-sign'     'openssl dgst -sha256 -sign'
check_action 'g2.action:mask'             '::add-mask::'
check_action 'g2.action:token-output'     'steps.mint.outputs.token'
check_action 'g2.action:installation-id'  'installation-id'

# The script-invoking step must NOT carry continue-on-error, or if: failure()
# on the Slack step never fires. Slice THAT step: steps start at `      - `
# (6-space indent; run bodies are indented deeper, so the anchor cannot land
# inside a heredoc), bounded by the invocation line
# `bash .github/scripts/bump-inngest-bootstrap-pin.sh` — prose mentions of the
# script name in comments cannot produce one.
inv_line=$(grep -n 'bash .github/scripts/bump-inngest-bootstrap-pin.sh' <<<"$BUMP_BLOCK" | head -1 | cut -d: -f1)
if [[ -z "$inv_line" ]]; then
  fail 'g2.bump:no-continue-on-error' "no 'bash .github/scripts/bump-inngest-bootstrap-pin.sh' invocation in the bump job"
else
  step_start=$(awk -v n="$inv_line" 'NR<=n && /^      - /{s=NR} END{print s+0}' <<<"$BUMP_BLOCK")
  step_end=$(awk -v n="$inv_line" 'NR>n && /^      - /{print NR-1; f=1; exit} END{if(!f) print NR}' <<<"$BUMP_BLOCK")
  STEP_BLOCK=$(sed -n "${step_start},${step_end}p" <<<"$BUMP_BLOCK")
  # Anchored on the YAML KEY — a comment saying "no continue-on-error" inside
  # the step's run block must not trip this.
  if grep -qE '^\s*continue-on-error:' <<<"$STEP_BLOCK"; then
    fail 'g2.bump:no-continue-on-error' "script step carries continue-on-error — if: failure() can never fire"
  else
    pass 'g2.bump:no-continue-on-error'
  fi
  # A step-level timeout below the job's 10 is what converts a hung gh/git call
  # into a step FAILURE (reaching `if: failure()` Slack) instead of a job
  # `cancelled` that skips every remaining step — no result=, no notification.
  step_timeout=$(grep -oE 'timeout-minutes:[[:space:]]*[0-9]+' <<<"$STEP_BLOCK" | head -1 | grep -oE '[0-9]+')
  [[ -n "$step_timeout" && "$step_timeout" -lt 10 ]] && pass 'g2.bump:step-timeout' \
    || fail 'g2.bump:step-timeout' "script step timeout-minutes is '${step_timeout:-<absent>}', must be present and < job's 10"
fi

# AC5: no PAT anywhere in the workflow (precise literals — `dispatch` contains
# `pat`, so a bare substring grep is red on the compliant tree).
check_wf_absent 'g2.wf:no-gh-token-pat' 'GH_TOKEN_PAT'
check_wf_absent 'g2.wf:no-secrets-pat'  'secrets\.[A-Za-z_]*PAT'

# AC4: build-job outputs + the sign step's id/digest plumbing. The terminator
# excludes the opener by its exact key — a `rebuild:` job key must not be
# absorbed into the slice.
BUILD_BLOCK=$(awk '/^  build:/{f=1} f&&/^  [a-zA-Z_][a-zA-Z0-9_-]*:/&&!/^  build:/{f=0} f' "$WORKFLOW")
for lit in 'outputs:' 'tag:' 'digest:' 'mirror_status:' 'id: sign' 'digest=%s'; do
  if grep -qF -- "$lit" <<<"$BUILD_BLOCK"; then pass "g2.build:has-$lit"
  else fail "g2.build:has-$lit" "build job lacks literal: $lit"; fi
done
# The ${{ }} expression is written inside a single-quoted YAML scalar in the
# workflow — assert the wiring by its stable skeleton, not the exact text
# (YAML flow allows `${{` spacing variants).
if grep -qE 'digest:[[:space:]]*\$\{\{[[:space:]]*steps\.sign\.outputs\.digest[[:space:]]*\}\}' <<<"$BUILD_BLOCK"; then
  pass 'g2.build:digest-from-sign'
else
  fail 'g2.build:digest-from-sign' "outputs.digest not wired to steps.sign.outputs.digest"
fi

# Guard 2 row 5: regex parity — the script's tag-selection pipeline is
# AC6-identical. Both files must carry each literal stage.
for lit in "tag --list 'vinngest-v*'" "sed 's/^vinngest-//'" "sort -V" "tail -1" '^v[0-9]+\.[0-9]+\.[0-9]+$'; do
  if [[ -f "$SCRIPT" ]] && grep -qF -- "$lit" "$SCRIPT" && grep -qF -- "$lit" "$CONSUMER"; then
    pass "g2.parity:$lit"
  else
    fail "g2.parity:$lit" "pipeline literal missing from script or consumer"
  fi
done

# The script pushes ONLY via x-access-token (the minted installation token) —
# never a bare https or ssh remote.
if [[ -f "$SCRIPT" ]] && grep -qF 'x-access-token' "$SCRIPT"; then
  pass 'g2.script:x-access-token'
else
  fail 'g2.script:x-access-token' "script lacks the x-access-token push remote"
fi
# And the push URL must embed the token, not a hardcoded credential.
if [[ -f "$SCRIPT" ]] && grep -qE 'x-access-token:\$\{?GH_TOKEN' "$SCRIPT"; then
  pass 'g2.script:token-from-env'
else
  fail 'g2.script:token-from-env' "push URL does not source the token from GH_TOKEN env"
fi
# Script carries the CLA-allowlisted bot identity.
for lit in 'soleur-ai[bot]' '273333864+soleur-ai[bot]@users.noreply.github.com'; do
  if [[ -f "$SCRIPT" ]] && grep -qF -- "$lit" "$SCRIPT"; then pass "g2.script:$lit"
  else fail "g2.script:$lit" "script lacks identity literal: $lit"; fi
done

# ---------------------------------------------------------------------------
echo ""
TOTAL=$((PASS + FAIL))
if (( TOTAL < MIN_ASSERTIONS )); then
  echo "FAIL [anti-vacuity]: only $TOTAL assertions ran (floor $MIN_ASSERTIONS) — the suite itself has been weakened."
  FAIL=$((FAIL + 1))
fi
echo ""
echo "Results: $PASS pass, $FAIL fail"
[[ "$FAIL" -eq 0 ]]
