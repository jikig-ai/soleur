#!/usr/bin/env bash
# Fixture tests for .github/scripts/bump-inngest-bootstrap-pin.sh — the writer
# that build-inngest-bootstrap-image.yml's bump-cloud-init-pin job invokes to
# move the soleur-inngest-bootstrap cloud-init pin to the semver-max vinngest-v*
# tag merged into main + registry-resolved digest (#8359, #8782).
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
# script's mutation matrix; Guard 2 = workflow-shape asserts over
# build-inngest-bootstrap-image.yml, plus the writer/checker selector
# byte-equality rows (#8782). MIN_ASSERTIONS is the suite's own
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
MIN_ASSERTIONS=586   # anti-vacuity floor = the green run's exact count; raise when adding rows, never lower it silently

pass() { echo "PASS [$1]"; PASS=$((PASS+1)); }
fail() { echo "FAIL [$1]: $2"; FAIL=$((FAIL+1)); }

# --- digest fixtures (64-hex fakes; content-free, shape-correct) -------------
DIG_OLD="sha256:$(printf 'a%.0s' $(seq 1 64))"
DIG_NEW="sha256:$(printf 'b%.0s' $(seq 1 64))"
DIG_NEWER="sha256:$(printf 'c%.0s' $(seq 1 64))"
# #9262: the bump authors as the soleur-infra App (bot user id 335404629). The
# soleur-ai identity it used before is LEGACY: a tip carrying it is not ours.
BOT_EMAIL='335404629+soleur-infra[bot]@users.noreply.github.com'
LEGACY_BOT_EMAIL='273333864+soleur-ai[bot]@users.noreply.github.com'

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
  # Every crane call is logged: refusal rows assert this log is EMPTY, which
  # proves the refusal fired BEFORE the registry was consulted (a reorder after
  # the digest loop would otherwise end `skipped`, green); exclusion rows
  # assert the off-main tag never appears in it.
  MOCK_CRANE_LOG="$TMP/crane.$1.log"; : > "$MOCK_CRANE_LOG"
  # digest<TAB>revision for `crane config`. run_bump fills in, for every digest
  # the map serves, the commit its tag names — the honest default ("every image
  # was built from its tag's commit"). A row overrides by writing first:
  # revision `-` = no label, `!json` = non-JSON config, `!fail` = crane error.
  MOCK_CRANE_CONFIG="$TMP/crane.$1.config"; : > "$MOCK_CRANE_CONFIG"
  MOCK_GH_LOG="$TMP/gh.$1.log";     : > "$MOCK_GH_LOG"
  MOCK_GH_PRS="$TMP/gh.$1.prs";     : > "$MOCK_GH_PRS"
  export MOCK_CRANE_MAP MOCK_CRANE_LOG MOCK_CRANE_CONFIG MOCK_GH_LOG MOCK_GH_PRS
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

# seed_tag_at <vinngest-vX.Y.Z> <rev> [--annotate] — a tag on ANY commit
# (side-branch commits, older main commits). The #8747 rows need annotated tags
# off main, which seed_tag (lightweight, on HEAD) cannot express.
seed_tag_at() {
  if [[ "${3:-}" == "--annotate" ]]; then
    git -C "$F_REPO" tag -a "$1" -m "release $1" "$2"
  else
    git -C "$F_REPO" tag "$1" "$2"
  fi
}

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
printf 'crane %s\n' "$*" >> "${MOCK_CRANE_LOG:?unset}"
if [[ "${1:-}" == "digest" && -n "${2:-}" ]]; then
  tag="${2##*:}"
  got=$(awk -F '\t' -v t="$tag" '$1 == t {print $2}' "${MOCK_CRANE_MAP:?unset}" 2>/dev/null | head -1)
  if [[ -n "$got" ]]; then printf '%s\n' "$got"; exit 0; fi
  echo "crane-stub: no digest for $2" >&2; exit 1
fi
if [[ "${1:-}" == "config" ]]; then
  ref="${!#}"; dig="${ref##*@}"
  rev=$(awk -F '\t' -v d="$dig" '$1 == d {print $2}' "${MOCK_CRANE_CONFIG:?unset}" 2>/dev/null | head -1)
  case "$rev" in
    "")     echo "crane-stub: no config for $ref" >&2; exit 1 ;;
    '!fail') echo "crane-stub: config fetch failed" >&2; exit 1 ;;
    '!json') printf 'not json\n'; exit 0 ;;
    -)      printf '{"config":{"Labels":{}}}\n'; exit 0 ;;
    *)      printf '{"config":{"Labels":{"org.opencontainers.image.revision":"%s"}}}\n' "$rev"; exit 0 ;;
  esac
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
#   flags: `fork` => isCrossRepository:true + author.login=fork-user;
#          `author=<login>` => that author.login)
# Without a flag a PR's author lists as `app/soleur-infra` — the form `gh pr list
# --json author` reports for a GitHub App (measured: {"is_bot":true,"login":
# "app/soleur-ai"} for the pre-#9262 pin PRs), never `<slug>[bot]` (#9262).
# `gh api repos/<r>/commits/<sha>` resolves author.login from the commit's
# author email in $MOCK_ORIGIN (mirrors GitHub's email→login resolution): the
# soleur-infra noreply => soleur-infra[bot]; the legacy soleur-ai noreply =>
# soleur-ai[bot]; anything else => fixture-human.
cat > "$BIN/gh" <<'STUB'
#!/usr/bin/env bash
set -uo pipefail
printf 'gh %s\n' "$*" | tr '\n' ' ' >> "${MOCK_GH_LOG:?unset}"
printf '\n' >> "$MOCK_GH_LOG"
args=("$@")
sub="${args[0]:-} ${args[1]:-}"
BOT_EMAIL='335404629+soleur-infra[bot]@users.noreply.github.com'
LEGACY_BOT_EMAIL='273333864+soleur-ai[bot]@users.noreply.github.com'

flag() { # flag <name> — value of a --flag arg
  local i
  for ((i=0; i<${#args[@]}; i++)); do
    [[ "${args[$i]}" == "$1" ]] && { printf '%s' "${args[$((i+1))]:-}"; return 0; }
  done
}

pr_json() { # emit one PR object from a state line
  local n="$1" h="$2" u="$3" o="$4" s="$5" fl="${6:-}"
  local xr=false al='app/soleur-infra'
  if [[ "$fl" == *fork* ]]; then xr=true; al='fork-user'; fi
  if [[ "$fl" =~ author=([^,]+) ]]; then al="${BASH_REMATCH[1]}"; fi
  # |armed flag: auto-merge already enabled on this PR (gh reports autoMergeRequest
  # as an object when armed, null otherwise).
  local am=null
  [[ "$fl" == *armed* ]] && am='{"enabledAt":"2026-09-30T00:00:00Z","mergeMethod":"SQUASH"}'

  # |nullhead flag: GitHub emits headRefName:null for PRs whose head repo or
  # branch was deleted — the supersede jq must skip, not throw mid-pipe.
  if [[ "$fl" == *nullhead* ]]; then
    printf '{"number":%s,"headRefName":null,"url":"%s","headRefOid":"%s","state":"%s","isCrossRepository":%s,"author":{"login":"%s"},"autoMergeRequest":%s}' \
      "$n" "$u" "$o" "$s" "$xr" "$al" "$am"
    return
  fi
  printf '{"number":%s,"headRefName":"%s","url":"%s","headRefOid":"%s","state":"%s","isCrossRepository":%s,"author":{"login":"%s"},"autoMergeRequest":%s}' \
    "$n" "$h" "$u" "$o" "$s" "$xr" "$al" "$am"
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
    # GitHub refuses a second OPEN same-repo PR for one head branch; a fork PR with a
    # colliding branch name does not block (different head repository).
    while IFS='|' read -r xn xh xu xo xs xfl; do
      [[ "$xs" == open && "$xh" == "$head" && "$xfl" != *fork* ]] \
        && { echo "a pull request for branch \"$head\" already exists" >&2; exit 1; }
    done < "$MOCK_GH_PRS"
    n=$(( $(wc -l < "$MOCK_GH_PRS" 2>/dev/null || echo 0) + 1 ))
    url="https://github.test/mock/pull/$n"
    oid=$(git --git-dir="${MOCK_ORIGIN:?unset}" rev-parse "refs/heads/$head" 2>/dev/null || echo "0")
    printf '%s|%s|%s|%s|open\n' "$n" "$head" "$url" "$oid" >> "$MOCK_GH_PRS"
    printf '%s\n' "$url"
    ;;
  "pr comment"|"pr merge")
    if [[ "$sub" == "pr merge" && " $* " == *" --disable-auto "* ]]; then
      [[ "${MOCK_GH_DISABLE_FAIL:-0}" == "1" ]] && { echo "disable auto-merge failed" >&2; exit 1; }
      exit 0
    fi
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
      if [[ "$em" == "$BOT_EMAIL" ]]; then login='soleur-infra[bot]'
      elif [[ "$em" == "$LEGACY_BOT_EMAIL" ]]; then login='soleur-ai[bot]'
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
#
# --signed-commit (#8747) is PREPENDED unless the row passes its own or sets
# NO_AUTO_SIGNED_COMMIT=1: the commit the signed tag points at (what the build
# job's `commit` output would carry), else HEAD. Prepending — not appending —
# keeps a row's own trailing-flag shape (`--signed-tag` with no value) intact.
run_bump() {
  local name="$1"; shift
  LAST_OUT="$TMP/$name.out"
  LAST_GOUT="$TMP/$name.gout"
  : > "$LAST_GOUT"
  local -a pre=()
  local a st="" prev="" has_sc=0
  for a in "$@"; do
    [[ "$prev" == "--signed-tag" ]] && st="$a"
    [[ "$a" == "--signed-commit" ]] && has_sc=1
    prev="$a"
  done
  # Auto-provenance: label every served digest with its tag's commit unless the
  # row already said otherwise (see reset_state).
  local mt md mc
  while IFS=$'\t' read -r mt md; do
    [[ -n "$mt" && -n "$md" ]] || continue
    awk -F '\t' -v d="$md" '$1 == d {f=1} END {exit !f}' "$MOCK_CRANE_CONFIG" 2>/dev/null && continue
    mc=$(git -C "$F_REPO" rev-parse -q --verify "refs/tags/vinngest-${mt}^{commit}" 2>/dev/null) || continue
    printf '%s\t%s\n' "$md" "$mc" >> "$MOCK_CRANE_CONFIG"
  done < "$MOCK_CRANE_MAP"
  if [[ "$has_sc" == 0 && "${NO_AUTO_SIGNED_COMMIT:-0}" != 1 ]]; then
    local sc
    sc=$(git -C "$F_REPO" rev-parse -q --verify "refs/tags/vinngest-${st}^{commit}" 2>/dev/null \
      || git -C "$F_REPO" rev-parse -q --verify 'HEAD^{commit}' 2>/dev/null || true)
    [[ -n "$sc" ]] && pre=(--signed-commit "$sc")
  fi
  env BUMP_REPO_DIR="$F_REPO" BUMP_PUSH_URL="$F_ORIGIN" \
      GH_TOKEN="fixture-installation-token" \
      MOCK_CRANE_MAP="$MOCK_CRANE_MAP" MOCK_CRANE_LOG="$MOCK_CRANE_LOG" \
      MOCK_CRANE_CONFIG="$MOCK_CRANE_CONFIG" \
      MOCK_GH_LOG="$MOCK_GH_LOG" \
      MOCK_GH_PRS="$MOCK_GH_PRS" MOCK_ORIGIN="$F_ORIGIN" \
      GITHUB_OUTPUT="$LAST_GOUT" GITHUB_STEP_SUMMARY="$TMP/$name.summary" \
      bash "$SCRIPT" "${pre[@]}" "$@" > "$LAST_OUT" 2>&1
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
assert_out_has() { # name needle — `--`: a needle may itself start with `--`
  if grep -qF -- "$2" "$LAST_OUT"; then pass "$1"
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
assert_gh_called 'g1.happy:body-adr'     'ADR-232'
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
# The recovery is an action a human can take (#9262) — never "reset the tip to a
# bot commit", which no human can author.
assert_out_has 'g1.humantip:recovery' 'dispatch the build once from main with mirror_only=true'
assert_out_has 'g1.humantip:recovery-delete' 'git push origin --delete soleur/inngest-pin-v1.1.38'
assert_out_has 'g1.humantip:recovery-held' 'the PR it opens is HELD'
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
seed_sha=$(push_branch_to_origin 'soleur/inngest-pin-v1.1.38' 'soleur-infra[bot]' "$BOT_EMAIL")

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
seed_sha=$(push_branch_to_origin 'soleur/inngest-pin-v1.1.38' 'soleur-infra[bot]' "$BOT_EMAIL")

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
# #9262 — the PR-author filter. `gh pr list --json author` reports an App author
# as `app/<slug>`, so the filter compares against BOT_PR_LOGIN (app/soleur-infra),
# never BOT_NAME: before #9262 it compared against `soleur-ai[bot]` and the
# reuse path never matched in production. A same-repo PR for the branch authored
# by the LEGACY App or by a human is NOT reused (it is not this identity's PR):
# the run falls through to `gh pr create`, which GitHub refuses for a second open
# same-repo PR on one head (the stub models that), the filtered re-list finds no
# soleur-infra PR, and the run dies at stage `pr` — loud, never a hijack of a PR
# someone else authored.
# ---------------------------------------------------------------------------
for who in 'app/soleur-ai:legacy-app' 'fixture-human:human'; do
  login="${who%%:*}"; lbl="${who##*:}"
  new_fixture_repo "author-$lbl"
  write_fixture_cloud_inits "$F_REPO" v1.1.37 "$DIG_OLD" v1.1.37 "$DIG_OLD"
  fixture_commit "pins at v1.1.37"
  seed_tag vinngest-v1.1.38
  printf 'v1.1.38\t%s\n' "$DIG_NEW" >> "$MOCK_CRANE_MAP"
  git -C "$F_REPO" push -q "$F_ORIGIN" HEAD:refs/heads/main
  printf '9|soleur/inngest-pin-v1.1.38|https://github.test/mock/pull/9|%s|open|author=%s\n' \
    "$(git -C "$F_REPO" rev-parse HEAD)" "$login" >> "$MOCK_GH_PRS"
  run_bump "author-$lbl" --signed-tag v1.1.38 --signed-digest "$DIG_NEW" --mirror-status ok
  [[ "$LAST_RC" != 0 ]] && pass "g1.author-$lbl:nonzero" || fail "g1.author-$lbl:nonzero" "a foreign-authored PR on the bot branch was accepted"
  assert_result  "g1.author-$lbl:result" error
  assert_out_has "g1.author-$lbl:stage" '::error::pr:'
  assert_out_has "g1.author-$lbl:names-filter" 'found no same-repo bot PR'
  assert_gh_called     "g1.author-$lbl:tried-create" 'gh pr create '
  assert_gh_not_called "g1.author-$lbl:not-reused" 'gh pr (comment|merge) 9 '
done

# #9262 — a pin branch whose tip is the LEGACY soleur-ai[bot] identity (left over
# from before the switch) is treated like a human tip: never force-pushed over.
new_fixture_repo legacytip
write_fixture_cloud_inits "$F_REPO" v1.1.37 "$DIG_OLD" v1.1.37 "$DIG_OLD"
fixture_commit "pins at v1.1.37"
seed_tag vinngest-v1.1.38
printf 'v1.1.38\t%s\n' "$DIG_NEW" >> "$MOCK_CRANE_MAP"
git -C "$F_REPO" push -q "$F_ORIGIN" HEAD:refs/heads/main
legacy_sha=$(push_branch_to_origin 'soleur/inngest-pin-v1.1.38' 'soleur-ai[bot]' "$LEGACY_BOT_EMAIL")
run_bump legacytip --signed-tag v1.1.38 --signed-digest "$DIG_NEW" --mirror-status ok
assert_rc      'g1.legacytip:exit' 0
assert_result  'g1.legacytip:result' skipped
assert_out_has 'g1.legacytip:marker' 'branch-has-manual-commits'
assert_origin_branch 'g1.legacytip:tip-preserved' 'soleur/inngest-pin-v1.1.38' "$legacy_sha"

# ---------------------------------------------------------------------------
# #9262 — `--mirror-only true` never arms auto-merge. The build's sign step
# re-resolves the tag and signs whatever it points at, and mirror_only skips the
# build's ancestry refusal, so a backfill cannot attest provenance: the PR opens
# HELD and says why, even when every other attestation (mirror ok, signed tag ==
# target, provenance bound) would have armed it. `false` and '' keep arming.
# ---------------------------------------------------------------------------
for mo in 'true:held' 'false:armed' ':armed'; do
  val="${mo%%:*}"; want="${mo##*:}"; lbl="mirror-only-${val:-empty}"
  new_fixture_repo "$lbl"
  write_fixture_cloud_inits "$F_REPO" v1.1.37 "$DIG_OLD" v1.1.37 "$DIG_OLD"
  fixture_commit "pins at v1.1.37"
  seed_tag vinngest-v1.1.38
  printf 'v1.1.38\t%s\n' "$DIG_NEW" >> "$MOCK_CRANE_MAP"
  git -C "$F_REPO" push -q "$F_ORIGIN" HEAD:refs/heads/main
  run_bump "$lbl" --signed-tag v1.1.38 --signed-digest "$DIG_NEW" --mirror-status ok --mirror-only "$val"
  assert_rc     "g1.$lbl:exit" 0
  assert_result "g1.$lbl:result" opened
  if [[ "$want" == held ]]; then
    assert_gh_not_called "g1.$lbl:no-merge" 'gh pr merge '
    assert_gh_called     "g1.$lbl:body-says-why" 'gh pr create .*mirror_only backfill cannot attest provenance'
    assert_gh_called     "g1.$lbl:hold-comment" 'gh pr comment .*mirror_only'
  else
    assert_gh_called "g1.$lbl:merge-armed" 'gh pr merge '
  fi
done
# The `existing` path re-lists a reusable PR: under mirror_only it is not armed either.
new_fixture_repo mirror-only-existing
write_fixture_cloud_inits "$F_REPO" v1.1.37 "$DIG_OLD" v1.1.37 "$DIG_OLD"
fixture_commit "pins at v1.1.37"
seed_tag vinngest-v1.1.38
printf 'v1.1.38\t%s\n' "$DIG_NEW" >> "$MOCK_CRANE_MAP"
git -C "$F_REPO" push -q "$F_ORIGIN" HEAD:refs/heads/main
printf '9|soleur/inngest-pin-v1.1.38|https://github.test/mock/pull/9|%s|open\n' "$(git -C "$F_REPO" rev-parse HEAD)" >> "$MOCK_GH_PRS"
run_bump mirror-only-existing --signed-tag v1.1.38 --signed-digest "$DIG_NEW" --mirror-status ok --mirror-only true
assert_result        'g1.mirror-only-existing:result' existing
assert_gh_called     'g1.mirror-only-existing:reused' 'gh pr comment 9 '
assert_gh_not_called 'g1.mirror-only-existing:no-merge' 'gh pr merge '
assert_gh_called     'g1.mirror-only-existing:hold-comment' 'gh pr comment 9 .*mirror_only backfill'
# An earlier full build ARMED auto-merge on the reused PR: a mirror_only run must
# disarm it (GitHub keeps auto-merge across a writer's push), and a failed disarm is
# fatal — the PR could otherwise merge on a mirror_only commit (#9262 review).
for arm in 'ok:0' 'fail:1'; do
  lbl="mirror-only-armed-${arm%%:*}"; dfail="${arm##*:}"
  new_fixture_repo "$lbl"
  write_fixture_cloud_inits "$F_REPO" v1.1.37 "$DIG_OLD" v1.1.37 "$DIG_OLD"
  fixture_commit "pins at v1.1.37"
  seed_tag vinngest-v1.1.38
  printf 'v1.1.38\t%s\n' "$DIG_NEW" >> "$MOCK_CRANE_MAP"
  git -C "$F_REPO" push -q "$F_ORIGIN" HEAD:refs/heads/main
  printf '9|soleur/inngest-pin-v1.1.38|https://github.test/mock/pull/9|%s|open|armed\n' "$(git -C "$F_REPO" rev-parse HEAD)" >> "$MOCK_GH_PRS"
  MOCK_GH_DISABLE_FAIL="$dfail" run_bump "$lbl" --signed-tag v1.1.38 --signed-digest "$DIG_NEW" --mirror-status ok --mirror-only true
  assert_gh_called     "g1.$lbl:disarms" 'gh pr merge 9 --repo [^ ]+ --disable-auto'
  assert_gh_not_called "g1.$lbl:never-arms" 'gh pr merge .*--auto --squash'
  if [[ "$dfail" == 0 ]]; then
    assert_rc     "g1.$lbl:exit" 0
    assert_result "g1.$lbl:result" existing
  else
    [[ "$LAST_RC" != 0 ]] && pass "g1.$lbl:nonzero" || fail "g1.$lbl:nonzero" "a failed disarm was tolerated"
    assert_result  "g1.$lbl:result" error
    assert_out_has "g1.$lbl:stage" '::error::pr:'
  fi
done
# The unarmed full-build path does NOT call --disable-auto (the disarm is scoped to
# mirror_only): a plain re-run of an armed PR keeps its arm.
new_fixture_repo armed-full-build
write_fixture_cloud_inits "$F_REPO" v1.1.37 "$DIG_OLD" v1.1.37 "$DIG_OLD"
fixture_commit "pins at v1.1.37"
seed_tag vinngest-v1.1.38
printf 'v1.1.38\t%s\n' "$DIG_NEW" >> "$MOCK_CRANE_MAP"
git -C "$F_REPO" push -q "$F_ORIGIN" HEAD:refs/heads/main
printf '9|soleur/inngest-pin-v1.1.38|https://github.test/mock/pull/9|%s|open|armed\n' "$(git -C "$F_REPO" rev-parse HEAD)" >> "$MOCK_GH_PRS"
run_bump armed-full-build --signed-tag v1.1.38 --signed-digest "$DIG_NEW" --mirror-status ok
assert_result        'g1.armed-full-build:result' existing
assert_gh_not_called 'g1.armed-full-build:no-disarm' 'disable-auto'
run_bump mirror-only-bad --signed-tag v1.1.38 --signed-digest "$DIG_NEW" --mirror-status ok --mirror-only yes
[[ "$LAST_RC" != 0 ]] && pass 'g1.mirror-only-bad:nonzero' || fail 'g1.mirror-only-bad:nonzero' "--mirror-only yes accepted"
assert_out_has 'g1.mirror-only-bad:stage' '::error::args:'
# A repeated flag is refused, never last-wins (a trailing `--mirror-only false`
# would otherwise cancel the hold).
run_bump mirror-only-dup --signed-tag v1.1.38 --signed-digest "$DIG_NEW" --mirror-status ok --mirror-only true --mirror-only false
[[ "$LAST_RC" != 0 ]] && pass 'g1.mirror-only-dup:nonzero' || fail 'g1.mirror-only-dup:nonzero' "a repeated --mirror-only was accepted"
assert_out_has 'g1.mirror-only-dup:names' 'duplicate argument: --mirror-only'
assert_result  'g1.mirror-only-dup:result' error
assert_out_has 'g1.mirror-only-dup:stage' '::error::args:'

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
old_sha=$(push_branch_to_origin 'soleur/inngest-pin-v1.1.37' 'soleur-infra[bot]' "$BOT_EMAIL")
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
old_sha=$(push_branch_to_origin 'soleur/inngest-pin-v1.1.38' 'soleur-infra[bot]' "$BOT_EMAIL")
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
  --signed-commit "$(git -C "$F_REPO" rev-parse HEAD)" \
  > "$LAST_OUT" 2>&1; LAST_RC=$?
[[ "$LAST_RC" != "0" ]] && pass 'g1.missingtoken:nonzero' \
  || fail 'g1.missingtoken:nonzero' "rc=0 — missing GH_TOKEN accepted"
assert_out_has 'g1.missingtoken:marker' 'GH_TOKEN'

LAST_OUT="$TMP/baddir.out"; LAST_GOUT="$TMP/baddir.gout"; : > "$LAST_GOUT"
env BUMP_REPO_DIR=/nonexistent-xyz GH_TOKEN=x GITHUB_OUTPUT="$LAST_GOUT" \
  bash "$SCRIPT" --signed-tag v1.1.38 --signed-digest "$DIG_NEW" \
  --signed-commit "$(git -C "$F_REPO" rev-parse HEAD)" \
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
echo "=== Guard 1b: merged-into-main selection + history refusals (#8747, #8782) ==="

# The #8747 incident shape: vinngest-v1.1.39 was cut on a commit that existed
# only on an unmerged PR branch, its publish opened a bump PR, and that PR
# merged main's pin onto unreviewed bytes. Since #8782 such a tag is EXCLUDED
# (assert_excluded: noop on the merged max, the off-main tag never reaches
# crane, no branch, no PR). Every REFUSAL row asserts the STOP POINT, not only
# result=error: the stage marker, an EMPTY crane log, an empty gh log and no
# bump branch on the origin. Every fixture first asserts its own precondition,
# so a fixture that accidentally tags main reds instead of passing vacuously.

# base_fixture <name> — pins at v1.1.37 on main, vinngest-v1.1.37 tagged there,
# main pushed to the bare origin. Leaves HEAD on main.
base_fixture() {
  new_fixture_repo "$1"
  write_fixture_cloud_inits "$F_REPO" v1.1.37 "$DIG_OLD" v1.1.37 "$DIG_OLD"
  fixture_commit "pins at v1.1.37"
  seed_tag vinngest-v1.1.37
  git -C "$F_REPO" push -q "$F_ORIGIN" HEAD:refs/heads/main
}

# side_commit <branch> <from-rev> <marker> — one commit on a side branch that
# touches a carrier-shaped file, then back to main. Prints the side sha.
side_commit() {
  local br="$1" from="$2" mark="$3" sha
  git -C "$F_REPO" checkout -q -B "$br" "$from"
  mkdir -p "$F_REPO/apps/web-platform/infra"
  printf '# %s\n' "$mark" >> "$F_REPO/apps/web-platform/infra/inngest-bootstrap.sh"
  fixture_commit "side: $mark"
  sha=$(git -C "$F_REPO" rev-parse HEAD)
  git -C "$F_REPO" checkout -q main
  printf '%s' "$sha"
}

# main_commit <marker> — advance main by one commit.
main_commit() {
  printf '# %s\n' "$1" >> "$F_REPO/apps/web-platform/infra/main-notes.txt"
  fixture_commit "main: $1"
}

precond_off_main() { # name tag — the fixture's own claim, measured
  local rc=0
  git -C "$F_REPO" merge-base --is-ancestor "refs/tags/$2^{commit}" HEAD 2>/dev/null || rc=$?
  [[ "$rc" == 1 ]] && pass "$1:precondition-off-main" \
    || fail "$1:precondition-off-main" "fixture broken: $2 ancestry rc=$rc, expected 1"
}
precond_on_main() { # name tag
  local rc=0
  git -C "$F_REPO" merge-base --is-ancestor "refs/tags/$2^{commit}" HEAD 2>/dev/null || rc=$?
  [[ "$rc" == 0 ]] && pass "$1:precondition-on-main" \
    || fail "$1:precondition-on-main" "fixture broken: $2 ancestry rc=$rc, expected 0"
}

assert_refused() { # name wording [stage] — the full stop-point contract of a refusal
  local name="$1" wording="$2" stage="${3:-ancestry}" branches
  [[ "$LAST_RC" != "0" ]] && pass "$name:nonzero" \
    || fail "$name:nonzero" "rc=0 — refusal did not fire: $(tail -3 "$LAST_OUT" | tr '\n' '|')"
  assert_result "$name:result" error
  assert_out_has "$name:${stage}-stage" "::error::${stage}:"
  assert_out_has "$name:wording" "$wording"
  [[ ! -s "$MOCK_CRANE_LOG" ]] && pass "$name:crane-not-called" \
    || fail "$name:crane-not-called" "crane was consulted before the refusal: $(tr '\n' '|' < "$MOCK_CRANE_LOG")"
  [[ ! -s "$MOCK_GH_LOG" ]] && pass "$name:gh-not-called" \
    || fail "$name:gh-not-called" "gh called: $(head -2 "$MOCK_GH_LOG" | tr '\n' '|')"
  branches=$(git --git-dir="$F_ORIGIN" for-each-ref --format='%(refname)' 'refs/heads/soleur/' 2>/dev/null)
  [[ -z "$branches" ]] && pass "$name:no-bump-branch" \
    || fail "$name:no-bump-branch" "origin carries: $branches"
}

# assert_excluded <name> <off-main-tag> — #8782: an off-main tag is never a
# candidate, so the run reconciles to the merged max (v1.1.37@DIG_OLD, which
# main already pins) and ends `noop`. The stop point is stronger than the old
# refusal's: the off-main tag never reaches crane, no branch and no PR exist,
# and every pin still reads v1.1.37.
assert_excluded() {
  local name="$1" off="$2" branches
  assert_rc     "$name:exit" 0
  assert_result "$name:result" noop
  assert_out_has "$name:target-merged-max" 'target=v1.1.37 '
  grep -qF -- ":$off" "$MOCK_CRANE_LOG" \
    && fail "$name:off-main-never-resolved" "crane was asked about $off: $(tr '\n' '|' < "$MOCK_CRANE_LOG")" \
    || pass "$name:off-main-never-resolved"
  assert_all_pins "$name:pins" "$F_REPO" v1.1.37 "$DIG_OLD"
  [[ ! -s "$MOCK_GH_LOG" ]] && pass "$name:gh-not-called" \
    || fail "$name:gh-not-called" "gh called: $(head -2 "$MOCK_GH_LOG" | tr '\n' '|')"
  branches=$(git --git-dir="$F_ORIGIN" for-each-ref --format='%(refname)' 'refs/heads/soleur/' 2>/dev/null)
  [[ -z "$branches" ]] && pass "$name:no-bump-branch" \
    || fail "$name:no-bump-branch" "origin carries: $branches"
}

# B1 — the #8747 shape: semver-max tag, annotated, on an unmerged side commit,
# with a digest SEEDED for it. Seeding the digest is load-bearing: a writer
# that reverted to `tag --list` would reach `opened` on v1.1.38 (loud), not a
# quiet `skipped`. Since #8782 the tag is EXCLUDED, not refused.
base_fixture anc-b1
s=$(side_commit pr-8741 main 'vector download retry')
seed_tag_at vinngest-v1.1.38 "$s" --annotate
printf 'v1.1.38\t%s\nv1.1.37\t%s\n' "$DIG_NEW" "$DIG_OLD" >> "$MOCK_CRANE_MAP"
precond_off_main 'g1b.B1' vinngest-v1.1.38
run_bump anc-b1 --signed-tag v1.1.38 --signed-digest "$DIG_NEW" --mirror-status ok
assert_excluded 'g1b.B1' v1.1.38

# B2 — the side branch is SQUASH-merged into main with byte-identical content.
# Content equality must not make the tag a candidate: it still names a commit
# main can never reach.
base_fixture anc-b2
s=$(side_commit pr-squash main 'squashed change')
git -C "$F_REPO" checkout -q "$s" -- apps/web-platform/infra/inngest-bootstrap.sh
fixture_commit "squash-merge of pr-squash"
seed_tag_at vinngest-v1.1.38 "$s" --annotate
printf 'v1.1.38\t%s\nv1.1.37\t%s\n' "$DIG_NEW" "$DIG_OLD" >> "$MOCK_CRANE_MAP"
precond_off_main 'g1b.B2' vinngest-v1.1.38
if git -C "$F_REPO" diff --quiet "refs/tags/vinngest-v1.1.38^{tree}" HEAD -- apps/web-platform/infra/inngest-bootstrap.sh; then
  pass 'g1b.B2:precondition-content-identical'
else
  fail 'g1b.B2:precondition-content-identical' "fixture broken: squash content differs"
fi
run_bump anc-b2 --signed-tag v1.1.38 --signed-digest "$DIG_NEW" --mirror-status ok
assert_excluded 'g1b.B2' v1.1.38

# B3 — the #8782 headline: this run published an ON-main tag while an off-main
# tag sits above it. Before #8782 the off-main tag was the target and this
# legitimate bump died at `ancestry`; now it is not a candidate, so the bump
# lands on the on-main tag. The PR branch is also a remote-tracking ref, the
# shape actions/checkout leaves.
base_fixture anc-b3
seed_tag vinngest-v1.1.38
s=$(side_commit pr-newer main 'newer unmerged')
seed_tag_at vinngest-v1.1.39 "$s" --annotate
git -C "$F_REPO" update-ref refs/remotes/origin/pr-newer "$s"
printf 'v1.1.38\t%s\nv1.1.39\t%s\n' "$DIG_NEW" "$DIG_NEWER" >> "$MOCK_CRANE_MAP"
precond_on_main 'g1b.B3' vinngest-v1.1.38
precond_off_main 'g1b.B3' vinngest-v1.1.39
run_bump anc-b3 --signed-tag v1.1.38 --signed-digest "$DIG_NEW" --mirror-status ok
assert_rc     'g1b.B3:exit' 0
assert_result 'g1b.B3:result' opened
assert_all_pins 'g1b.B3:pins' "$F_REPO" v1.1.38 "$DIG_NEW"
assert_gh_called 'g1b.B3:merge-armed' 'gh pr merge .* --auto --squash'
grep -qF -- ':v1.1.39' "$MOCK_CRANE_LOG" \
  && fail 'g1b.B3:off-main-never-resolved' "crane was asked about v1.1.39" \
  || pass 'g1b.B3:off-main-never-resolved'

# B4 — an OLDER off-main tag below an on-main semver-max: it is not a
# candidate, and the bump proceeds on the merged max.
base_fixture anc-b4
s=$(side_commit pr-old main 'old unmerged')
seed_tag_at vinngest-v1.1.38 "$s" --annotate
main_commit 'advance'
seed_tag_at vinngest-v1.1.39 HEAD --annotate
printf 'v1.1.39\t%s\n' "$DIG_NEWER" >> "$MOCK_CRANE_MAP"
precond_off_main 'g1b.B4' vinngest-v1.1.38
precond_on_main 'g1b.B4' vinngest-v1.1.39
run_bump anc-b4 --signed-tag v1.1.39 --signed-digest "$DIG_NEWER" --mirror-status ok
assert_rc     'g1b.B4:exit' 0
assert_result 'g1b.B4:result' opened
assert_all_pins 'g1b.B4:pins' "$F_REPO" v1.1.39 "$DIG_NEWER"

# B5 — a TRUE merge commit brings the side branch into main: the tagged side
# commit becomes reachable, so the bump proceeds.
base_fixture anc-b5
s=$(side_commit pr-merged main 'merged via merge commit')
seed_tag_at vinngest-v1.1.38 "$s" --annotate
main_commit 'main moves first'
git -C "$F_REPO" merge -q --no-ff -m "Merge pr-merged" pr-merged
printf 'v1.1.38\t%s\n' "$DIG_NEW" >> "$MOCK_CRANE_MAP"
precond_on_main 'g1b.B5' vinngest-v1.1.38
run_bump anc-b5 --signed-tag v1.1.38 --signed-digest "$DIG_NEW" --mirror-status ok
assert_rc     'g1b.B5:exit' 0
assert_result 'g1b.B5:result' opened

# B6 — the tag sits on an OLDER main commit and main has advanced 3 commits
# since; annotated and lightweight variants. Both proceed.
for kind in annotated lightweight; do
  base_fixture "anc-b6-$kind"
  tagged=$(git -C "$F_REPO" rev-parse HEAD)
  main_commit one; main_commit two; main_commit three
  if [[ "$kind" == annotated ]]; then
    seed_tag_at vinngest-v1.1.38 "$tagged" --annotate
  else
    seed_tag_at vinngest-v1.1.38 "$tagged"
  fi
  printf 'v1.1.38\t%s\n' "$DIG_NEW" >> "$MOCK_CRANE_MAP"
  precond_on_main "g1b.B6-$kind" vinngest-v1.1.38
  run_bump "anc-b6-$kind" --signed-tag v1.1.38 --signed-digest "$DIG_NEW" --mirror-status ok
  assert_rc     "g1b.B6-$kind:exit" 0
  assert_result "g1b.B6-$kind:result" opened
done

# B7 — the history walk cannot complete: main c1<-c2<-c3 with c2's object
# deleted, and the tag on a side commit off c1. `git tag --merged HEAD` then
# exits 0 with an EMPTY list and reports the damage only on stderr; the
# walk-stderr refusal names it before resolution.
base_fixture anc-b7
c1=$(git -C "$F_REPO" rev-parse HEAD)
main_commit c2; c2=$(git -C "$F_REPO" rev-parse HEAD)
main_commit c3
s=$(side_commit pr-corrupt "$c1" 'off c1')
seed_tag_at vinngest-v1.1.38 "$s" --annotate
printf 'v1.1.38\t%s\n' "$DIG_NEW" >> "$MOCK_CRANE_MAP"
rm -f "$F_REPO/.git/objects/${c2:0:2}/${c2:2}"
git -C "$F_REPO" rev-parse -q --verify 'refs/tags/vinngest-v1.1.38^{commit}' >/dev/null \
  && pass 'g1b.B7:precondition-tag-resolves' || fail 'g1b.B7:precondition-tag-resolves' "fixture broken"
git -C "$F_REPO" cat-file -e "$c2" 2>/dev/null \
  && fail 'g1b.B7:precondition-c2-absent' "fixture broken: c2 still readable" \
  || pass 'g1b.B7:precondition-c2-absent'
[[ -z "$(git -C "$F_REPO" tag --merged HEAD --list 'vinngest-v*' 2>/dev/null)" ]] \
  && pass 'g1b.B7:precondition-merged-set-empty' \
  || fail 'g1b.B7:precondition-merged-set-empty' "fixture broken: git tag --merged HEAD still lists tags on a corrupt walk"
run_bump anc-b7 --signed-tag v1.1.38 --signed-digest "$DIG_NEW" --mirror-status ok
assert_refused 'g1b.B7' 'reported an unreadable history'

# B7b — no vinngest-v* tag at all (a checkout without fetch-tags): refused at
# `resolve` with the fetch-tags remediation, before crane.
new_fixture_repo anc-b7b
write_fixture_cloud_inits "$F_REPO" v1.1.37 "$DIG_OLD" v1.1.37 "$DIG_OLD"
fixture_commit "pins at v1.1.37, no tags"
git -C "$F_REPO" push -q "$F_ORIGIN" HEAD:refs/heads/main
printf 'v1.1.38\t%s\n' "$DIG_NEW" >> "$MOCK_CRANE_MAP"
run_bump anc-b7b --signed-tag v1.1.38 --signed-digest "$DIG_NEW" --mirror-status ok
assert_refused 'g1b.B7b' 'no vinngest-v* tag is merged into' resolve
assert_out_has 'g1b.B7b:remediation' 'fetch-tags: true'

# B7c — the TRUNCATED shape: the tag sits ABOVE the missing object, so
# `--merged` still lists it (rc 0) while the walk below it is unreadable. The
# empty-set refusal cannot see this; only the walk-stderr refusal can.
base_fixture anc-b7c
main_commit c2; c2=$(git -C "$F_REPO" rev-parse HEAD)
main_commit c3
seed_tag_at vinngest-v1.1.38 HEAD --annotate
printf 'v1.1.38\t%s\n' "$DIG_NEW" >> "$MOCK_CRANE_MAP"
rm -f "$F_REPO/.git/objects/${c2:0:2}/${c2:2}"
[[ "$(git -C "$F_REPO" tag --merged HEAD --list 'vinngest-v*' 2>/dev/null)" == vinngest-v1.1.38 ]] \
  && pass 'g1b.B7c:precondition-truncated-set' \
  || fail 'g1b.B7c:precondition-truncated-set' "fixture broken: --merged HEAD is not exactly the tag above the break"
run_bump anc-b7c --signed-tag v1.1.38 --signed-digest "$DIG_NEW" --mirror-status ok
assert_refused 'g1b.B7c' 'reported an unreadable history'

# B7a — the tag exists (annotated tag object intact) but the COMMIT it points
# at is gone. `git tag --merged` silently drops it, so it is never a candidate:
# the run reconciles to the merged max and never asks the registry about it.
base_fixture anc-b7a
s=$(side_commit pr-gone main 'object will vanish')
seed_tag_at vinngest-v1.1.38 "$s" --annotate
git -C "$F_REPO" branch -q -D pr-gone
rm -f "$F_REPO/.git/objects/${s:0:2}/${s:2}"
printf 'v1.1.38\t%s\nv1.1.37\t%s\n' "$DIG_NEW" "$DIG_OLD" >> "$MOCK_CRANE_MAP"
[[ "$(git -C "$F_REPO" tag --list 'vinngest-v1.1.38')" == vinngest-v1.1.38 ]] \
  && pass 'g1b.B7a:precondition-tag-listed' || fail 'g1b.B7a:precondition-tag-listed' "fixture broken"
git -C "$F_REPO" rev-parse -q --verify 'refs/tags/vinngest-v1.1.38^{commit}' >/dev/null 2>&1 \
  && fail 'g1b.B7a:precondition-peel-fails' "fixture broken: tag still peels" \
  || pass 'g1b.B7a:precondition-peel-fails'
[[ "$(git -C "$F_REPO" tag --merged HEAD --list 'vinngest-v*' 2>/dev/null)" == vinngest-v1.1.37 ]] \
  && pass 'g1b.B7a:precondition-merged-set' \
  || fail 'g1b.B7a:precondition-merged-set' "fixture broken: --merged HEAD is not exactly vinngest-v1.1.37"
NO_AUTO_SIGNED_COMMIT=1 run_bump anc-b7a --signed-commit "$(git -C "$F_REPO" rev-parse HEAD)" \
  --signed-tag v1.1.38 --signed-digest "$DIG_NEW" --mirror-status ok
assert_excluded 'g1b.B7a' v1.1.38

# B8 — the peel must name refs/tags/ explicitly. The target vinngest-v1.1.38 is
# ON main, while `refs/vinngest-v1.1.38` points at an OFF-main side commit and
# shadows the bare name (git resolves refs/<name> before refs/tags/<name>). The
# explicit peel resolves the real tag and the bump opens; a peel regressed to
# the bare name resolves the side commit and dies at the --signed-commit
# binding.
base_fixture anc-b8
main_commit 'b8 target'
seed_tag_at vinngest-v1.1.38 HEAD --annotate
s=$(side_commit pr-shadow main 'shadow')
git -C "$F_REPO" update-ref refs/vinngest-v1.1.38 "$s"
printf 'v1.1.38\t%s\n' "$DIG_NEW" >> "$MOCK_CRANE_MAP"
[[ "$(git -C "$F_REPO" rev-parse -q --verify 'vinngest-v1.1.38^{commit}' 2>/dev/null)" == "$s" ]] \
  && pass 'g1b.B8:precondition-bare-name-shadowed' \
  || fail 'g1b.B8:precondition-bare-name-shadowed' "fixture broken: bare name does not resolve to the side commit"
precond_on_main 'g1b.B8' vinngest-v1.1.38
run_bump anc-b8 --signed-tag v1.1.38 --signed-digest "$DIG_NEW" --mirror-status ok
assert_rc     'g1b.B8:exit' 0
assert_result 'g1b.B8:result' opened
assert_out_has 'g1b.B8:provenance' 'provenance=bound'
assert_all_pins 'g1b.B8:pins' "$F_REPO" v1.1.38 "$DIG_NEW"

# B9 — a depth-1 clone with the tag at HEAD: without the early shallow
# refusal `--merged` lists it and crane gets called, which the empty-crane-log
# assertion reds.
base_fixture anc-b9
seed_tag_at vinngest-v1.1.38 HEAD --annotate
printf 'v1.1.38\t%s\n' "$DIG_NEW" >> "$MOCK_CRANE_MAP"
b9_clone="$TMP/anc-b9/shallow"
git clone -q --depth 1 "file://$F_REPO" "$b9_clone"
F_REPO="$b9_clone"
[[ "$(git -C "$F_REPO" rev-parse --is-shallow-repository)" == true ]] \
  && pass 'g1b.B9:precondition-shallow' || fail 'g1b.B9:precondition-shallow' "fixture broken: clone is not shallow"
[[ "$(git -C "$F_REPO" tag --list 'vinngest-v1.1.38')" == vinngest-v1.1.38 ]] \
  && pass 'g1b.B9:precondition-tag-present' || fail 'g1b.B9:precondition-tag-present' "fixture broken: tag not fetched"
run_bump anc-b9 --signed-tag v1.1.38 --signed-digest "$DIG_NEW" --mirror-status ok
assert_refused 'g1b.B9' 'is-shallow-repository='

# B9b (#8782) — the case that makes the shallow check run BEFORE resolution: the
# target sits BELOW the graft, so `git tag --merged HEAD` silently omits it
# (rc 0). Resolving first would pick a lower tag or none and misdiagnose it.
# The needle is unique to the moved check — `shallow` alone also appears in
# the `resolve` message.
base_fixture anc-b9b
main_commit one
seed_tag_at vinngest-v1.1.38 HEAD --annotate
main_commit two; main_commit three
git -C "$F_REPO" push -q "$F_ORIGIN" HEAD:refs/heads/main
printf 'v1.1.38\t%s\n' "$DIG_NEW" >> "$MOCK_CRANE_MAP"
b9b_clone="$TMP/anc-b9b/shallow"
git clone -q --depth 1 "file://$F_REPO" "$b9b_clone"
git -C "$b9b_clone" fetch -q --tags --depth 1 origin 2>/dev/null
F_REPO="$b9b_clone"
[[ "$(git -C "$F_REPO" rev-parse --is-shallow-repository)" == true ]] \
  && pass 'g1b.B9b:precondition-shallow' || fail 'g1b.B9b:precondition-shallow' "fixture broken: clone is not shallow"
[[ "$(git -C "$F_REPO" tag --list 'vinngest-v1.1.38')" == vinngest-v1.1.38 ]] \
  && pass 'g1b.B9b:precondition-tag-present' || fail 'g1b.B9b:precondition-tag-present' "fixture broken: tag not fetched"
grep -qxF vinngest-v1.1.38 <<<"$(git -C "$F_REPO" tag --merged HEAD --list 'vinngest-v*' 2>/dev/null)" \
  && fail 'g1b.B9b:precondition-merged-omits-target' "fixture broken: --merged HEAD still sees the target below the graft" \
  || pass 'g1b.B9b:precondition-merged-omits-target'
run_bump anc-b9b --signed-tag v1.1.38 --signed-digest "$DIG_NEW" --mirror-status ok
assert_refused 'g1b.B9b' 'cannot decide which vinngest-v* tags are merged'

# B10 — the re-pointed-tag race: the build signed commit X, and by bump time the
# tag names a DIFFERENT (on-main) commit. The digest cross-check cannot see
# this (both digests are the first build's), so the bump binds to the commit.
base_fixture anc-b10
built=$(git -C "$F_REPO" rev-parse HEAD)
main_commit 're-cut here'
seed_tag_at vinngest-v1.1.38 HEAD --annotate
printf 'v1.1.38\t%s\n' "$DIG_NEW" >> "$MOCK_CRANE_MAP"
precond_on_main 'g1b.B10' vinngest-v1.1.38
run_bump anc-b10 --signed-commit "$built" --signed-tag v1.1.38 --signed-digest "$DIG_NEW" --mirror-status ok
assert_refused 'g1b.B10' 'signed commit'
assert_out_has 'g1b.B10:names-built' "$built"

# B10b — the binding does NOT apply to a backfill of an older tag (signed tag
# is not the target), exactly as the digest cross-check does not.
base_fixture anc-b10b
seed_tag vinngest-v1.1.38
printf 'v1.1.38\t%s\n' "$DIG_NEW" >> "$MOCK_CRANE_MAP"
run_bump anc-b10b --signed-commit "$(printf '0%.0s' $(seq 1 40))" \
  --signed-tag v1.1.37 --signed-digest "$DIG_OLD" --mirror-status ok
assert_rc     'g1b.B10b:exit' 0
assert_result 'g1b.B10b:result' opened

# B11 — --signed-commit is REQUIRED and must be 40-hex: a pre-fix branch's
# workflow copy (which does not pass it) fails closed at args.
base_fixture anc-b11
seed_tag vinngest-v1.1.38
printf 'v1.1.38\t%s\n' "$DIG_NEW" >> "$MOCK_CRANE_MAP"
NO_AUTO_SIGNED_COMMIT=1 run_bump anc-b11-missing --signed-tag v1.1.38 --signed-digest "$DIG_NEW" --mirror-status ok
[[ "$LAST_RC" != 0 ]] && pass 'g1b.B11-missing:nonzero' || fail 'g1b.B11-missing:nonzero' "missing --signed-commit accepted"
assert_result  'g1b.B11-missing:result' error
assert_out_has 'g1b.B11-missing:stage' '::error::args:'
assert_out_has 'g1b.B11-missing:names-flag' '--signed-commit'
# #9262: a hand-pushed tag starts nothing, so the recovery is a dispatch from main.
assert_out_has 'g1b.B11-missing:recovery' 'then dispatch the build once from main'
run_bump anc-b11-bad --signed-commit 'abc123' --signed-tag v1.1.38 --signed-digest "$DIG_NEW" --mirror-status ok
[[ "$LAST_RC" != 0 ]] && pass 'g1b.B11-bad:nonzero' || fail 'g1b.B11-bad:nonzero' "malformed --signed-commit accepted"
assert_out_has 'g1b.B11-bad:stage' '::error::args:'
[[ ! -s "$MOCK_CRANE_LOG" ]] && pass 'g1b.B11:crane-not-called' || fail 'g1b.B11:crane-not-called' "crane called"


# B12 — the legacy state right after #8747 merged: main PINS an off-main tag.
# Since #8782 that tag can never be the target, so the state shows up as "the
# pin sits above every merged tag" — the same downgrade refusal as B13. It must
# say "do NOT delete" and must NOT print the delete command (deleting the pinned
# tag breaks AC6/GuardA/zot backfill and, repeated, walks the pin down).
new_fixture_repo anc-b12
write_fixture_cloud_inits "$F_REPO" v1.1.39 "$DIG_NEWER" v1.1.39 "$DIG_NEWER"
fixture_commit "pins at legacy off-main v1.1.39"
seed_tag vinngest-v1.1.25
git -C "$F_REPO" push -q "$F_ORIGIN" HEAD:refs/heads/main
s=$(side_commit pr-legacy main 'legacy off-main')
seed_tag_at vinngest-v1.1.39 "$s" --annotate
printf 'v1.1.25\t%s\nv1.1.39\t%s\n' "$DIG_OLD" "$DIG_NEWER" >> "$MOCK_CRANE_MAP"
git -C "$F_REPO" rev-parse -q --verify 'refs/tags/vinngest-v1.1.39^{commit}' >/dev/null \
  && pass 'g1b.B12:precondition-pinned-tag-resolves' \
  || fail 'g1b.B12:precondition-pinned-tag-resolves' "fixture broken: vinngest-v1.1.39 does not resolve"
precond_off_main 'g1b.B12' vinngest-v1.1.39
run_bump anc-b12 --signed-tag v1.1.25 --signed-digest "$DIG_OLD" --mirror-status ok
assert_refused 'g1b.B12' 'Refusing to author a downgrade' resolve
assert_out_has 'g1b.B12:do-not-delete' 'Do NOT delete or re-cut'
assert_out_has 'g1b.B12:recovery' 'then dispatch the build once from main'
grep -qF 'git push origin :refs/tags/vinngest-v1.1.39' "$LAST_OUT" \
  && fail 'g1b.B12:no-delete-command' "the refusal prints a command that deletes the live pin" \
  || pass 'g1b.B12:no-delete-command'

# B13 — the pinned tag was deleted (the cascade B12 prevents), so the
# semver-max remaining tag sits BELOW the pin: refuse the downgrade, before the
# registry is consulted.
new_fixture_repo anc-b13
write_fixture_cloud_inits "$F_REPO" v1.1.39 "$DIG_NEWER" v1.1.39 "$DIG_NEWER"
fixture_commit "pins at v1.1.39 whose tag is gone"
seed_tag vinngest-v1.1.25
git -C "$F_REPO" push -q "$F_ORIGIN" HEAD:refs/heads/main
printf 'v1.1.25\t%s\n' "$DIG_OLD" >> "$MOCK_CRANE_MAP"
run_bump anc-b13 --signed-tag v1.1.25 --signed-digest "$DIG_OLD" --mirror-status ok
assert_refused 'g1b.B13' 'Refusing to author a downgrade' resolve
assert_out_has 'g1b.B13:do-not-delete' 'Do NOT delete or re-cut'
assert_origin_branch 'g1b.B13:no-branch' 'soleur/inngest-pin-v1.1.25' ABSENT

# B14 — provenance: the tag was re-pointed onto main commit M, but the registry
# still holds the image built from the off-main commit X (a mirror_only run
# builds nothing). Ancestry and the commit binding both pass; the image's
# revision label is what refuses it.
base_fixture anc-b14
x=$(side_commit pr-stale main 'stale off-main build')
m=$(git -C "$F_REPO" rev-parse HEAD)
seed_tag_at vinngest-v1.1.38 "$m" --annotate
printf 'v1.1.38\t%s\n' "$DIG_NEW" >> "$MOCK_CRANE_MAP"
printf '%s\t%s\n' "$DIG_NEW" "$x" >> "$MOCK_CRANE_CONFIG"
precond_on_main 'g1b.B14' vinngest-v1.1.38
run_bump anc-b14 --signed-tag v1.1.38 --signed-digest "$DIG_NEW" --mirror-status ok
[[ "$LAST_RC" != 0 ]] && pass 'g1b.B14:nonzero' || fail 'g1b.B14:nonzero' "an image built from off-main $x was pinned"
assert_result  'g1b.B14:result' error
assert_out_has 'g1b.B14:stage' '::error::ancestry:'
assert_out_has 'g1b.B14:wording' "was built from commit $x"
assert_gh_not_called 'g1b.B14:no-gh' 'gh '
assert_origin_branch 'g1b.B14:no-branch' 'soleur/inngest-pin-v1.1.38' ABSENT

# B15 — provenance: an UNLABELLED image (legacy, pre-#8747) is pinned, but
# auto-merge is WITHHELD with a provenance hold.
base_fixture anc-b15
seed_tag vinngest-v1.1.38
printf 'v1.1.38\t%s\n' "$DIG_NEW" >> "$MOCK_CRANE_MAP"
printf '%s\t-\n' "$DIG_NEW" >> "$MOCK_CRANE_CONFIG"
run_bump anc-b15 --signed-tag v1.1.38 --signed-digest "$DIG_NEW" --mirror-status ok
assert_rc     'g1b.B15:exit' 0
assert_result 'g1b.B15:result' opened
assert_out_has 'g1b.B15:provenance' 'provenance=unlabeled'
assert_gh_not_called 'g1b.B15:no-merge' 'gh pr merge '
assert_gh_called     'g1b.B15:hold-comment' 'gh pr comment .*org.opencontainers.image.revision'

# B16 — provenance: a labelled image whose label matches is armed (the happy
# path, stated positively so a "never arm" mutant cannot pass B15 alone).
base_fixture anc-b16
seed_tag vinngest-v1.1.38
printf 'v1.1.38\t%s\n' "$DIG_NEW" >> "$MOCK_CRANE_MAP"
run_bump anc-b16 --signed-tag v1.1.38 --signed-digest "$DIG_NEW" --mirror-status ok
assert_result  'g1b.B16:result' opened
assert_out_has 'g1b.B16:provenance' 'provenance=bound'
assert_gh_called 'g1b.B16:merge-armed' 'gh pr merge .* --auto --squash'

# B17 — provenance: a malformed label, a non-JSON config and an unreadable
# config all refuse; the malformed label is never echoed (registry free text).
for shape in malformed json fail; do
  base_fixture "anc-b17-$shape"
  seed_tag vinngest-v1.1.38
  printf 'v1.1.38\t%s\n' "$DIG_NEW" >> "$MOCK_CRANE_MAP"
  case "$shape" in
    malformed) printf '%s\tNOT-A-SHA-injected\n' "$DIG_NEW" >> "$MOCK_CRANE_CONFIG" ;;
    json)      printf '%s\t!json\n' "$DIG_NEW" >> "$MOCK_CRANE_CONFIG" ;;
    fail)      printf '%s\t!fail\n' "$DIG_NEW" >> "$MOCK_CRANE_CONFIG" ;;
  esac
  run_bump "anc-b17-$shape" --signed-tag v1.1.38 --signed-digest "$DIG_NEW" --mirror-status ok
  [[ "$LAST_RC" != 0 ]] && pass "g1b.B17-$shape:nonzero" || fail "g1b.B17-$shape:nonzero" "config shape '$shape' was pinned"
  assert_out_has "g1b.B17-$shape:stage" '::error::ancestry:'
  assert_gh_not_called "g1b.B17-$shape:no-gh" 'gh '
done
grep -qF 'NOT-A-SHA-injected' "$TMP/anc-b17-malformed.out" \
  && fail 'g1b.B17-malformed:not-echoed' "the raw label reached the output" \
  || pass 'g1b.B17-malformed:not-echoed'

# B18 — a legacy BACKFILL: this run signed an OFF-main older tag (mirror_only
# of a v1.1.26..v1.1.39-style version) while the semver-max target is on main.
# Only the target is judged, so the bump proceeds.
base_fixture anc-b18
s=$(side_commit pr-legacy-backfill main 'legacy backfill')
seed_tag_at vinngest-v1.1.38 "$s" --annotate
main_commit 'advance'
seed_tag_at vinngest-v1.1.39 HEAD --annotate
printf 'v1.1.38\t%s\nv1.1.39\t%s\n' "$DIG_NEW" "$DIG_NEWER" >> "$MOCK_CRANE_MAP"
precond_off_main 'g1b.B18' vinngest-v1.1.38
run_bump anc-b18 --signed-tag v1.1.38 --signed-digest "$DIG_NEW" --mirror-status ok
assert_rc     'g1b.B18:exit' 0
assert_result 'g1b.B18:result' opened

# B19 — the script twin of the build step's I8: `--is-shallow-repository`
# printing NOTHING must refuse (fail closed), not read as "not shallow".
base_fixture anc-b19
seed_tag vinngest-v1.1.38
printf 'v1.1.38\t%s\n' "$DIG_NEW" >> "$MOCK_CRANE_MAP"
B19_BIN="$TMP/anc-b19/empty-shallow-bin"; mkdir -p "$B19_BIN"
B19_REAL_GIT=$(command -v git)
cat > "$B19_BIN/git" <<STUB
#!/usr/bin/env bash
for a in "\$@"; do [[ "\$a" == --is-shallow-repository ]] && exit 0; done
exec "$B19_REAL_GIT" "\$@"
STUB
chmod +x "$B19_BIN/git"
PATH="$B19_BIN:$PATH" run_bump anc-b19 --signed-tag v1.1.38 --signed-digest "$DIG_NEW" --mirror-status ok
assert_refused 'g1b.B19' 'is-shallow-repository='

# B20 (#8782) — selection is SEMVER, not lexical: v1.10.0 beats v1.9.0. Both
# digests are seeded, so a `sort -V` -> `sort` mutant fails legibly (noop on
# target=v1.9.0) instead of as a quiet `skipped`.
new_fixture_repo anc-b20
write_fixture_cloud_inits "$F_REPO" v1.9.0 "$DIG_OLD" v1.9.0 "$DIG_OLD"
fixture_commit "pins at v1.9.0"
seed_tag vinngest-v1.9.0
main_commit 'b20 advance'
seed_tag_at vinngest-v1.10.0 HEAD --annotate
git -C "$F_REPO" push -q "$F_ORIGIN" HEAD:refs/heads/main
printf 'v1.9.0\t%s\nv1.10.0\t%s\n' "$DIG_OLD" "$DIG_NEW" >> "$MOCK_CRANE_MAP"
run_bump anc-b20 --signed-tag v1.10.0 --signed-digest "$DIG_NEW" --mirror-status ok
assert_rc     'g1b.B20:exit' 0
assert_result 'g1b.B20:result' opened
assert_out_has 'g1b.B20:target' 'target=v1.10.0 '
assert_all_pins 'g1b.B20:pins' "$F_REPO" v1.10.0 "$DIG_NEW"

# B21 (#8782) — malformed names on main are never candidates, although each
# sorts above v1.1.40. One member per constraint of `^v[0-9]+\.[0-9]+\.[0-9]+$`:
# the trailing `$` (a pre-release, a four-part name), the escaped dots
# (v2x0x0), the leading `^` (vx-v9.9.9), and `+` over `*` (v.9.9). None has a
# seeded digest, so a mutant of that constraint reaches crane for it and ends
# `skipped` instead of `noop`.
new_fixture_repo anc-b21
write_fixture_cloud_inits "$F_REPO" v1.1.40 "$DIG_OLD" v1.1.40 "$DIG_OLD"
fixture_commit "pins at v1.1.40"
seed_tag vinngest-v1.1.40
for bad in v1.2.0-rc1 v1.2.0.1 v2x0x0 vx-v9.9.9 v.9.9; do seed_tag "vinngest-$bad"; done
git -C "$F_REPO" push -q "$F_ORIGIN" HEAD:refs/heads/main
printf 'v1.1.40\t%s\n' "$DIG_OLD" >> "$MOCK_CRANE_MAP"
run_bump anc-b21 --signed-tag v1.1.40 --signed-digest "$DIG_OLD" --mirror-status ok
assert_rc     'g1b.B21:exit' 0
assert_result 'g1b.B21:result' noop
for bad in v1.2.0-rc1 v1.2.0.1 v2x0x0 vx-v9.9.9 v.9.9; do
  grep -qF -- ":$bad" "$MOCK_CRANE_LOG" \
    && fail "g1b.B21:excluded-$bad" "crane was asked about $bad" \
    || pass "g1b.B21:excluded-$bad"
done

# B22 (#8782 review) — the DEDICATED-host file pins above the web host and above
# every merged tag. The downgrade refusal reads the higher of the two pins, so
# the bump never rewrites the dedicated host DOWN.
new_fixture_repo anc-b22
write_fixture_cloud_inits "$F_REPO" v1.1.37 "$DIG_OLD" v1.1.37 "$DIG_OLD"
sed -i 's/:v1\.1\.37@/:v1.1.39@/g' "$F_REPO/apps/web-platform/infra/cloud-init-inngest.yml"
fixture_commit "web pins v1.1.37, dedicated pins v1.1.39"
seed_tag vinngest-v1.1.37
seed_tag vinngest-v1.1.38
git -C "$F_REPO" push -q "$F_ORIGIN" HEAD:refs/heads/main
printf 'v1.1.38\t%s\n' "$DIG_NEW" >> "$MOCK_CRANE_MAP"
[[ "$(grep -c ':v1.1.39@' "$F_REPO/apps/web-platform/infra/cloud-init-inngest.yml")" == 2 ]] \
  && pass 'g1b.B22:precondition-dedicated-above' \
  || fail 'g1b.B22:precondition-dedicated-above' "fixture broken: dedicated file does not pin v1.1.39 twice"
run_bump anc-b22 --signed-tag v1.1.38 --signed-digest "$DIG_NEW" --mirror-status ok
assert_refused 'g1b.B22' 'main pins v1.1.39' resolve

# B23 (#8782 review) — a backfill of an OLDER tag whose target main already
# pins, with the registry failing. Nobody else's publish is in flight, so this
# is an error, never a green `skipped` deferral.
base_fixture anc-b23
seed_tag vinngest-v1.1.36
# (crane map deliberately empty: the registry cannot resolve the target)
run_bump anc-b23 --signed-tag v1.1.36 --signed-digest "$DIG_OLD" --mirror-status ok
[[ "$LAST_RC" != 0 ]] && pass 'g1b.B23:nonzero' || fail 'g1b.B23:nonzero' "registry failure on the pinned target was deferred"
assert_result  'g1b.B23:result' error
assert_out_has 'g1b.B23:stage' '::error::resolve:'
assert_out_has 'g1b.B23:names-crane' 'crane digest'
assert_out_has 'g1b.B23:remedy' 'republish vinngest-v1.1.37 (workflow_dispatch)'

# B24 (#8782 review) — this run signed an off-main tag ABOVE the merged-max
# target (not pinned), and the registry fails for the target. The target is
# OLDER than what was signed, so its publish finished long ago: error, not skip.
new_fixture_repo anc-b24
write_fixture_cloud_inits "$F_REPO" v1.1.36 "$DIG_OLD" v1.1.36 "$DIG_OLD"
fixture_commit "pins at v1.1.36"
seed_tag vinngest-v1.1.36
seed_tag vinngest-v1.1.37
git -C "$F_REPO" push -q "$F_ORIGIN" HEAD:refs/heads/main
s=$(side_commit pr-b24 main 'off-main signed')
seed_tag_at vinngest-v1.1.38 "$s" --annotate
precond_off_main 'g1b.B24' vinngest-v1.1.38
run_bump anc-b24 --signed-tag v1.1.38 --signed-digest "$DIG_NEW" --mirror-status ok
[[ "$LAST_RC" != 0 ]] && pass 'g1b.B24:nonzero' || fail 'g1b.B24:nonzero' "registry failure on an older target was deferred"
assert_result  'g1b.B24:result' error
assert_out_has 'g1b.B24:stage' '::error::resolve:'
# The merged target v1.1.37 is the one with no image, so the remedy names IT,
# never the signed tag: every later publish dies here until it is republished.
assert_out_has 'g1b.B24:remedy' 'republish vinngest-v1.1.37 (workflow_dispatch)'

echo ""
echo "=== Guard 2: workflow shape + selector byte-equality ==="

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
# P3 (review): the inline App-JWT recipe is extracted to a composite action —
# the workflow wires the action, the recipe lives in the action file.
check_block 'g2.bump:mint-id'                'id: mint'
check_block 'g2.bump:mint-token-env'         'steps.mint.outputs.token'
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
check_block 'g2.bump:invoke-mirror-only'     '--mirror-only "$MIRROR_ONLY"'
check_block 'g2.bump:env-mirror-only-binding' 'MIRROR_ONLY: ${{ inputs.mirror_only }}'
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
ACTION="$REPO_ROOT/.github/actions/mint-infra-app-token/action.yml"
check_action() { # name needle
  if [[ -f "$ACTION" ]] && grep -qF -- "$2" "$ACTION"; then pass "$1"
  else fail "$1" "mint-infra-app-token action lacks: $2"; fi
}
check_action 'g2.action:exists'           "using: 'composite'"
check_action 'g2.action:doppler-config'   '--project "$DOPPLER_SOURCE" --config prd'
check_action 'g2.action:doppler-default'  'default: soleur-infra-app'
check_action 'g2.action:app-id'           'doppler secrets get GITHUB_INFRA_APP_ID --plain'
check_action 'g2.action:app-key'          'doppler secrets get GITHUB_INFRA_APP_PRIVATE_KEY --plain'
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

# ---------------------------------------------------------------------------
# Guard 2b (#8747): the build job's publish-side ancestry refusal.
#
# SHAPE (S-rows) is read from the PARSED workflow, not grepped, so a comment
# cannot satisfy it; BEHAVIOUR (I-rows) executes the step's shipped `run:` body,
# sliced out of the YAML by step name, against git fixtures shaped like what
# actions/checkout@v4 leaves on a tag push with fetch-depth: 0 — HEAD detached,
# NO local branches, every branch (including the PR branch carrying an unmerged
# commit) as refs/remotes/origin/*, every tag fetched. The tested body IS the
# shipped body, so weakening it reds a row.
# ---------------------------------------------------------------------------
python3 -c 'import yaml' 2>/dev/null || pip3 install --quiet pyyaml 2>/dev/null || true
REFUSE_STEP='Refuse a commit that is not on main (#8747)'
RECORD_STEP='Record the built commit (#8747)'
REFUSE_BODY="$TMP/refuse-step.sh"
RECORD_BODY="$TMP/record-step.sh"
SHAPE_OUT="$TMP/shape.out"
SHAPE_PY="$TMP/shape.py"
cat > "$SHAPE_PY" <<'PY'
import re, sys, yaml
wf, refuse_name, record_name, refuse_out, record_out = sys.argv[1:6]
doc = yaml.safe_load(open(wf))
jobs = doc.get("jobs") or {}
build = jobs.get("build") or {}
bump = jobs.get("bump-cloud-init-pin") or {}
steps = build.get("steps") or []
names = [str(s.get("name", "")) for s in steps]
emitted = 0
def emit(key, ok, detail=""):
    global emitted
    emitted += 1
    print(f"{key}|{'ok' if ok else 'no'}|{detail}")
def idx(pred, seq=None):
    for i, s in enumerate(seq if seq is not None else steps):
        if pred(s):
            return i
    return -1
is_checkout = lambda s: str(s.get("uses", "")).startswith("actions/checkout@")
checkouts = [i for i, s in enumerate(steps) if is_checkout(s)]
emit("S11:build-exactly-one-checkout", len(checkouts) == 1, f"checkouts={checkouts}")
checkout_i = checkouts[0] if checkouts else -1
checkout = steps[checkout_i] if checkout_i >= 0 else {}
w = checkout.get("with") or {}
emit("S1:build-checkout-fetch-depth-0", w.get("fetch-depth") == 0, repr(w.get("fetch-depth")))
want_ref = "${{ github.event_name == 'workflow_dispatch' && format('refs/tags/{0}', inputs.ref) || '' }}"
emit("S7:dispatch-ref-exact", w.get("ref") == want_ref, repr(w.get("ref")))
refuse_hits = [i for i, n in enumerate(names) if n == refuse_name]
emit("S2:refuse-step-named-once", len(refuse_hits) == 1, f"hits={len(refuse_hits)}")
ri = refuse_hits[0] if refuse_hits else -1
refuse = steps[ri] if ri >= 0 else {}
body = str(refuse.get("run") or "")
emit("S2:refuse-body-nonempty", len(body.strip()) > 0, f"{len(body)} bytes")
open(refuse_out, "w").write(body)
emit("S9:refuse-if-exact", refuse.get("if") == "${{ !inputs.mirror_only }}", repr(refuse.get("if")))
emit("S12:refuse-id-ancestry", refuse.get("id") == "ancestry", repr(refuse.get("id")))
build_i = idx(lambda s: str(s.get("name", "")).startswith("Build + verify + push"))
mirror_i = idx(lambda s: str(s.get("name", "")).startswith("Mirror inngest image"))
emit("S3:refuse-before-build", 0 <= ri < build_i, f"refuse={ri} build={build_i}")
emit("S3:refuse-before-mirror", 0 <= ri < mirror_i, f"refuse={ri} mirror={mirror_i}")
emit("S3:refuse-after-checkout", 0 <= checkout_i < ri, f"checkout={checkout_i} refuse={ri}")
emit("S4:refuse-no-continue-on-error", "continue-on-error" not in refuse, repr(refuse.get("continue-on-error")))
emit("S4:build-job-no-continue-on-error", "continue-on-error" not in build, repr(build.get("continue-on-error")))
emit("S5:refuse-body-no-expression", "${{" not in body, "the body interpolates an expression")
env = refuse.get("env") or {}
emit("S5:refuse-env-tag", env.get("TAG") == "${{ steps.tag.outputs.tag }}", repr(env.get("TAG")))
emit("S5:refuse-env-head", env.get("HEAD_SHA") == "${{ steps.commit.outputs.commit }}", repr(env.get("HEAD_SHA")))
tag_i = idx(lambda s: s.get("id") == "tag")
emit("S6:refuse-after-resolve-tag", 0 <= tag_i < ri, f"tag={tag_i} refuse={ri}")
record_hits = [i for i, n in enumerate(names) if n == record_name]
emit("S6:record-step-named-once", len(record_hits) == 1, f"hits={len(record_hits)}")
rci = record_hits[0] if record_hits else -1
record = steps[rci] if rci >= 0 else {}
emit("S6:record-id-commit", record.get("id") == "commit", repr(record.get("id")))
emit("S6:record-before-refuse", 0 <= rci < ri, f"record={rci} refuse={ri}")
open(record_out, "w").write(str(record.get("run") or ""))
outs = build.get("outputs") or {}
emit("S6:build-output-commit", outs.get("commit") == "${{ steps.commit.outputs.commit }}", repr(outs.get("commit")))
bstep = steps[build_i] if build_i >= 0 else {}
emit("S13:build-env-revision", (bstep.get("env") or {}).get("REVISION") == "${{ steps.commit.outputs.commit }}",
     repr((bstep.get("env") or {}).get("REVISION")))
emit("S13:build-stamps-revision-label", 'docker build --label "org.opencontainers.image.revision=$REVISION"' in str(bstep.get("run") or ""), "")
slack = next((s for s in steps if s.get("name") == "Post to Slack (publish refused, #8747)"), {})
emit("S14:refused-slack-if-exact", slack.get("if") == "${{ failure() && steps.ancestry.outcome == 'failure' }}", repr(slack.get("if")))
bsteps = bump.get("steps") or []
bco = [s for s in bsteps if is_checkout(s)]
bw = (bco[0].get("with") or {}) if len(bco) == 1 else {}
emit("S10:bump-checkout-ref-main", len(bco) == 1 and bw.get("ref") == "main", repr(bw.get("ref")))
emit("S10:bump-checkout-full-history", bw.get("fetch-depth") == 0 and bw.get("fetch-tags") is True,
     repr((bw.get("fetch-depth"), bw.get("fetch-tags"))))
bstep2 = next((s for s in bsteps if s.get("name") == "Bump the cloud-init pin"), {})
benv = bstep2.get("env") or {}
emit("S8:bump-env-signed-commit", benv.get("SIGNED_COMMIT") == "${{ needs.build.outputs.commit }}", repr(benv.get("SIGNED_COMMIT")))
emit("S8:bump-passes-signed-commit", '--signed-commit "$SIGNED_COMMIT"' in str(bstep2.get("run") or ""), "")
# --- #9321: the bump job holds the main-only environment's NARROW secret ----
# Read from the PARSED job (a comment cannot satisfy it). Each step is compared to
# an EXACT dict AND its key set (name/timeout-minutes aside; ANY = present, value
# not pinned), so an added key, a second token or a widened value is a different
# step; one_minter/no_tier_a quantify over the whole job, because the step lookup
# returns the FIRST match and cannot see a second minter after a compliant one.
ANY = "<any>"
IGN = {"name", "timeout-minutes"}
def norm_env(j):
    e = j.get("environment")
    return e.get("name") if isinstance(e, dict) else e
def exact(st, want):
    got = {k: (ANY if (want[k] == ANY and st.get(k) is not None) else st.get(k)) for k in want}
    keys = set(st) - IGN
    return got == want and keys == {k for k, v in want.items() if v is not None}, f"got={got} keys={sorted(keys)}"
emit("S15:bump-job-parsed", "bump-cloud-init-pin" in jobs and bool(bump), "no bump-cloud-init-pin job in the parsed workflow")
emit("S16:bump-env-infra-privileged", norm_env(bump) == "infra-privileged", repr(bump.get("environment")))
vstep = next((s for s in bsteps if s.get("name") == "Verify DOPPLER_TOKEN_INFRA_APP present"), {})
emit("S17:bump-verify-exact", *exact(vstep, {"env": {"DOPPLER_TOKEN_CHECK": "${{ secrets.DOPPLER_TOKEN_INFRA_APP }}"}, "run": ANY, "if": None, "uses": None}))
mstep = next((s for s in bsteps if str(s.get("uses", "")).endswith("mint-infra-app-token")), {})
emit("S18:bump-mint-exact", *exact(mstep, {"id": "mint", "uses": "./.github/actions/mint-infra-app-token", "if": None, "env": None, "run": None,
     "with": {"doppler-token": "${{ secrets.DOPPLER_TOKEN_INFRA_APP }}", "installation-id": "166065653",
              "permissions": '{"contents":"write","pull_requests":"write"}', "repositories": "soleur"}}))
minters = [s for s in bsteps if str(s.get("uses", "")).endswith("mint-infra-app-token")]
emit("S19:bump-one-minter", len(minters) == 1, f"{len(minters)} mint-infra-app-token step(s)")
TIER_A_RE = r"secrets(\.DOPPLER_TOKEN|\[\s*['\"]+DOPPLER_TOKEN['\"]+\s*\])(?![A-Za-z0-9_])"
emit("S20:bump-no-tier-a", not re.search(TIER_A_RE, yaml.safe_dump({"job": bump, "env": doc.get("env"), "defaults": doc.get("defaults")})), "the bump job (or the workflow-level env/defaults) names the Tier-A secrets.DOPPLER_TOKEN")
# S25 (#9321): neither the bump job nor the workflow-level env/defaults names the BROAD
# Tier-B secret, in the dotted, bracket or whitespace spelling (whole serialised job, so an
# added step or env key is inside the window).
BROAD_RE = r"secrets(\s*\.\s*DOPPLER_TOKEN_INFRA_PRIVILEGED|\s*\[\s*['\"]+DOPPLER_TOKEN_INFRA_PRIVILEGED['\"]+\s*\])(?![A-Za-z0-9_])"
emit("S25:bump-no-broad-tier-b", not re.search(BROAD_RE, yaml.safe_dump({"job": bump, "env": doc.get("env"), "defaults": doc.get("defaults")})), "the bump job (or the workflow-level env/defaults) names the broad secrets.DOPPLER_TOKEN_INFRA_PRIVILEGED; it holds only DOPPLER_TOKEN_INFRA_APP")
on = doc.get("on", doc.get(True))
if isinstance(on, str): on_keys = {on}
elif isinstance(on, list): on_keys = set(on)
elif isinstance(on, dict): on_keys = set(on)
else: on_keys = set()
emit("S21:trigger-dispatch-only", on_keys == {"workflow_dispatch"}, f"on keys={sorted(map(str, on_keys))} (a tag-ref run is refused by the main-only environment; ADR-232 A5)")
# S22 parses the script invocation into an argv (a substring test is satisfied by a
# comment, and by a trailing `--mirror-only false` that would cancel the hold) and
# requires every flag exactly once, --mirror-only bound to "$MIRROR_ONLY".
import shlex
def bump_argv(run):
    for line in str(run or "").replace("\\\n", " ").splitlines():
        line = line.strip()
        if line.startswith("bash .github/scripts/bump-inngest-bootstrap-pin.sh"):
            try: return shlex.split(line, comments=True)
            except ValueError: return None
    return None
argv = bump_argv(bstep2.get("run")) or []
flags = [a for a in argv if a.startswith("--")]
mo_ok = argv.count("--mirror-only") == 1 and argv[argv.index("--mirror-only") + 1] == "$MIRROR_ONLY"
emit("S22:bump-passes-mirror-only", benv.get("MIRROR_ONLY") == "${{ inputs.mirror_only }}" and mo_ok and len(flags) == len(set(flags)), f"env={benv.get('MIRROR_ONLY')!r} argv={argv}")
# S23: the script step's env is EXACT, so no extra credential (the narrow Doppler
# token, a PAT) can ride in beside the App token.
want_env = {"GH_TOKEN": "${{ steps.mint.outputs.token }}", "TAG": "${{ needs.build.outputs.tag }}",
            "SIGNED_DIGEST": "${{ needs.build.outputs.digest }}", "SIGNED_COMMIT": "${{ needs.build.outputs.commit }}",
            "MIRROR_STATUS": "${{ needs.build.outputs.mirror_status }}", "MIRROR_ONLY": "${{ inputs.mirror_only }}",
            "RUN_URL": "${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}"}
emit("S23:bump-script-env-exact", benv == want_env, f"env keys={sorted(benv)}")
# S24: exactly the verify and mint steps name the narrow Doppler token.
tb = sorted(str(s.get("name")) for s in bsteps if "DOPPLER_TOKEN_INFRA_APP" in yaml.safe_dump(s))
emit("S24:infra-app-token-steps", tb == sorted(["Verify DOPPLER_TOKEN_INFRA_APP present", "Mint soleur-infra App token (contents+pull_requests write on soleur)"]), f"steps={tb}")
print(f"END|{emitted}")
PY
python3 "$SHAPE_PY" "$WORKFLOW" "$REFUSE_STEP" "$RECORD_STEP" "$REFUSE_BODY" "$RECORD_BODY" > "$SHAPE_OUT" 2>&1
shape_rc=$?
[[ "$shape_rc" == 0 ]] && pass 'g2b.shape:parser-ran' \
  || fail 'g2b.shape:parser-ran' "rc=$shape_rc — $(tail -3 "$SHAPE_OUT" | tr '\n' '|')"
shape_rows=0
shape_end=""
while IFS='|' read -r key verdict detail; do
  if [[ "$key" == END ]]; then shape_end="$verdict"; continue; fi
  [[ -n "$key" && "$key" == S* ]] || continue
  shape_rows=$((shape_rows + 1))
  [[ "$verdict" == ok ]] && pass "g2b.$key" || fail "g2b.$key" "${detail:-assertion false}"
done < "$SHAPE_OUT"
# The parser reports how many rows it emitted; a mismatch (or no END line)
# means it died part-way, which must not read as "the rows that ran were green".
[[ -n "$shape_end" && "$shape_rows" == "$shape_end" ]] && pass 'g2b.shape:row-count' \
  || fail 'g2b.shape:row-count' "parser reported END=${shape_end:-<none>}, parsed $shape_rows rows"

# --- #9262 bump-side mutation harness (plan Guard Contract, Guard 1) ---------
# Mutate a TEMP copy of the workflow, re-run the SAME shape parser on it, and
# require the named S-row to report `no`. Instrument control first: the
# unmodified copy must parse with every S-row ok, or a mutant "caught" on an
# already-red copy proves nothing.
SMUT="$TMP/shape-mut"; mkdir -p "$SMUT"
shape_on() { python3 "$SHAPE_PY" "$1" "$REFUSE_STEP" "$RECORD_STEP" "$SMUT/r.sh" "$SMUT/c.sh" 2>&1 || echo "CRASH|no|parser crashed"; }
cp "$WORKFLOW" "$SMUT/control.yml"
ctl=$(shape_on "$SMUT/control.yml")
if grep -qE '^S[0-9]+[^|]*\|no\||^CRASH' <<<"$ctl" || ! grep -q '^END|' <<<"$ctl"; then
  fail 'g2m.control:clean' "the unmodified workflow copy is not clean: $(grep -E '\|no\||^CRASH' <<<"$ctl" | cut -d'|' -f1 | paste -sd, -)"
else pass 'g2m.control:clean'; fi
shape_mut() { # shape_mut <id> <expected S-key prefix(es), comma list> <old> <new>
  local id="$1" keys="$2" dst="$SMUT/$1.yml" out k missed=""
  if ! python3 - "$WORKFLOW" "$dst" "$3" "$4" <<'PY'
import sys
src, dst, old, new = sys.argv[1:5]
s = open(src).read()
if s.count(old) != 1: sys.exit(2)
open(dst, "w").write(s.replace(old, new, 1))
PY
  then fail "g2m.$id:landed" "mutation anchor must match exactly once in the workflow"; return; fi
  pass "g2m.$id:landed"
  out=$(shape_on "$dst")
  if grep -q '^CRASH' <<<"$out"; then fail "g2m.$id:caught" "instrument broken: the shape parser crashed on the mutant"; return; fi
  IFS=',' read -ra want <<<"$keys"
  for k in "${want[@]}"; do grep -qE "^${k}[^|]*\|no\|" <<<"$out" || missed+="$k "; done
  [[ -z "$missed" ]] && pass "g2m.$id:caught [$keys]" || fail "g2m.$id:caught" "mutant SURVIVED on: $missed"
}
shape_mut env-removed 'S16' $'    environment: infra-privileged\n' ''
shape_mut verify-tier-a 'S17' 'DOPPLER_TOKEN_CHECK: ${{ secrets.DOPPLER_TOKEN_INFRA_APP }}' 'DOPPLER_TOKEN_CHECK: ${{ secrets.DOPPLER_TOKEN }}'
shape_mut perms-widened 'S18' $'permissions: \'{"contents":"write","pull_requests":"write"}\'' $'permissions: \'{"administration":"write","contents":"write","pull_requests":"write"}\''
shape_mut mint-continue-on-error 'S18' $'        id: mint\n' $'        id: mint\n        continue-on-error: true\n'
shape_mut tag-trigger-readded 'S21' $'\non:\n' $'\non:\n  push:\n    tags:\n      - \'vinngest-v*.*.*\'\n'
shape_mut second-minter 'S19,S20' $'          repositories: soleur\n' $'          repositories: soleur\n\n      - name: Second mint\n        id: mint2\n        uses: ./.github/actions/mint-infra-app-token\n        with:\n          doppler-token: ${{ secrets.DOPPLER_TOKEN }}\n          installation-id: "166065653"\n          permissions: \'{"contents":"write"}\'\n          repositories: soleur\n'
shape_mut workflow-env-tier-a 'S20' $'\npermissions:\n' $'\nenv:\n  LEAK: ${{ secrets.DOPPLER_TOKEN }}\npermissions:\n'
shape_mut bracket-tier-a 'S20' 'DOPPLER_TOKEN_CHECK: ${{ secrets.DOPPLER_TOKEN_INFRA_APP }}' $'DOPPLER_TOKEN_CHECK: ${{ secrets.DOPPLER_TOKEN_INFRA_APP }}\n          LEAK: ${{ secrets[\'DOPPLER_TOKEN\'] }}'
shape_mut mint-broad-tier-b 'S18,S25' 'doppler-token: ${{ secrets.DOPPLER_TOKEN_INFRA_APP }}' 'doppler-token: ${{ secrets.DOPPLER_TOKEN_INFRA_PRIVILEGED }}'
shape_mut verify-broad-tier-b 'S17,S25' 'DOPPLER_TOKEN_CHECK: ${{ secrets.DOPPLER_TOKEN_INFRA_APP }}' 'DOPPLER_TOKEN_CHECK: ${{ secrets.DOPPLER_TOKEN_INFRA_PRIVILEGED }}'
shape_mut bracket-broad-tier-b 'S25' 'DOPPLER_TOKEN_CHECK: ${{ secrets.DOPPLER_TOKEN_INFRA_APP }}' $'DOPPLER_TOKEN_CHECK: ${{ secrets.DOPPLER_TOKEN_INFRA_APP }}\n          LEAK: ${{ secrets[\'DOPPLER_TOKEN_INFRA_PRIVILEGED\'] }}'
shape_mut mirror-only-cancelled 'S22' '            --mirror-only "$MIRROR_ONLY"' '            --mirror-only "$MIRROR_ONLY" --mirror-only false'
shape_mut script-env-extra-token 'S23,S24' $'          GH_TOKEN: ${{ steps.mint.outputs.token }}\n' $'          GH_TOKEN: ${{ steps.mint.outputs.token }}\n          DOPPLER_TOKEN: ${{ secrets.DOPPLER_TOKEN_INFRA_APP }}\n'
shape_mut mirror-only-dropped 'S22' ' \'$'\n''            --mirror-only "$MIRROR_ONLY"' ''
# H1: point the job lookup at a name that does not exist — S15 must RED rather
# than the exact rows passing vacuously on an empty dict.
shape_mut job-renamed 'S15,S16,S18' $'  bump-cloud-init-pin:\n' $'  bump-cloud-init-pin-renamed:\n'
# H2 (must-PASS): the {name: ...} mapping form of the environment is the same binding.
python3 - "$WORKFLOW" "$SMUT/h2.yml" <<'PY'
import sys
src, dst = sys.argv[1:3]
s = open(src).read()
old = "    environment: infra-privileged\n"
assert s.count(old) == 1
open(dst, "w").write(s.replace(old, "    environment:\n      name: infra-privileged\n", 1))
PY
h2=$(shape_on "$SMUT/h2.yml")
if ! cmp -s "$WORKFLOW" "$SMUT/h2.yml" && ! grep -qE '\|no\||^CRASH' <<<"$h2" && grep -q '^END|' <<<"$h2"; then pass 'g2m.h2-env-mapping:passes'
else fail 'g2m.h2-env-mapping:passes' "mapping-form environment reddened: $(grep -E '\|no\||^CRASH' <<<"$h2" | cut -d'|' -f1 | paste -sd, -)"; fi

# --- behaviour harness ------------------------------------------------------
REAL_GIT=$(command -v git)
# harness_repo <name> — the actions/checkout shape: trunk c1<-c2 published as
# refs/remotes/origin/main, then HEAD detached and the local branch DELETED (a
# runner has no local `main`, so a body naming bare `main` must fail here).
# Sets H (the repo dir).
harness_repo() {
  H="$TMP/harness/$1"
  assert_fixture_dir "$H"
  mkdir -p "$H"
  git init -q -b trunk "$H"
  printf 'one\n' > "$H/f"; git -C "$H" add -A; git -C "$H" commit -qm c1
  printf 'two\n' >> "$H/f"; git -C "$H" add -A; git -C "$H" commit -qm c2
  git -C "$H" update-ref refs/remotes/origin/main trunk
  git -C "$H" checkout -q --detach
  git -C "$H" branch -q -D trunk
}
# h_main_commit <marker> — advance origin/main by one commit.
h_main_commit() {
  git -C "$H" checkout -q --detach refs/remotes/origin/main
  printf '%s\n' "$1" >> "$H/f"; git -C "$H" add -A; git -C "$H" commit -qm "main $1"
  git -C "$H" update-ref refs/remotes/origin/main HEAD
}
# h_side <from-rev> <marker> — one side commit, published as the PR branch
# refs/remotes/origin/pr-<marker> (actions/checkout fetches every branch, so the
# unmerged commit IS reachable from a remote-tracking ref). Prints its sha.
h_side() {
  git -C "$H" checkout -q --detach "$1"
  printf '%s\n' "$2" > "$H/side-$2"; git -C "$H" add -A; git -C "$H" commit -qm "side $2"
  git -C "$H" update-ref "refs/remotes/origin/pr-$2" HEAD
  git -C "$H" rev-parse HEAD
}
# run_step <name> <dir> <tag> <head_sha> — run the SHIPPED body the way the
# runner does (a `run:` with no `shell:` is `bash --noprofile --norc -eo
# pipefail`), HEAD detached at <head_sha> like the tag checkout.
# STEP_PATH_PREFIX (optional) is prepended to PATH.
run_step() {
  local name="$1" dir="$2" tag="$3" head="$4"
  assert_fixture_dir "$dir"
  STEP_OUT="$TMP/step.$name.out"
  STEP_SUMMARY="$TMP/step.$name.summary"; : > "$STEP_SUMMARY"
  git -C "$dir" checkout -q --detach "$head" 2>/dev/null
  ( cd "$dir" && env PATH="${STEP_PATH_PREFIX:+$STEP_PATH_PREFIX:}$PATH" TAG="$tag" HEAD_SHA="$head" \
      GITHUB_STEP_SUMMARY="$STEP_SUMMARY" \
      bash --noprofile --norc -eo pipefail "$REFUSE_BODY" ) > "$STEP_OUT" 2>&1
  STEP_RC=$?
}
# run_record <name> <dir> <rev> — the SHIPPED record body at <rev>; sets REC_RC
# and REC_COMMIT (what the step wrote to GITHUB_OUTPUT).
run_record() {
  local name="$1" dir="$2" rev="$3" out="$TMP/harness/$1.gout"
  assert_fixture_dir "$dir"
  : > "$out"
  git -C "$dir" checkout -q --detach "$rev" 2>/dev/null
  ( cd "$dir" && env GITHUB_OUTPUT="$out" bash --noprofile --norc -eo pipefail "$RECORD_BODY" ) > "$TMP/step.$name.rec" 2>&1
  REC_RC=$?
  REC_COMMIT=$(sed -n 's/^commit=//p' "$out")
}
step_rc() { # name expected
  [[ "$STEP_RC" == "$2" ]] && pass "$1" \
    || fail "$1" "rc=$STEP_RC, expected $2 — $(tail -3 "$STEP_OUT" | tr '\n' '|')"
}
step_has() { # name needle
  grep -qF -- "$2" "$STEP_OUT" && pass "$1" \
    || fail "$1" "step output lacks '$2' — $(tail -3 "$STEP_OUT" | tr '\n' '|')"
}
OFF_MAIN_MSG='is not an ancestor of main'

# I1 — HEAD on main's tip: passes and says so (log AND step summary).
harness_repo i1
c=$(git -C "$H" rev-parse refs/remotes/origin/main); git -C "$H" tag -a vinngest-v1.2.0 -m r "$c"
run_step i1 "$H" v1.2.0 "$c"
step_rc  'g2b.I1:on-main-rc0' 0
step_has 'g2b.I1:verdict' "verdict=on-main commit=$c"
grep -qF "verdict=on-main commit=$c" "$STEP_SUMMARY" && pass 'g2b.I1:summary' \
  || fail 'g2b.I1:summary' "step summary lacks the verdict"

# I2 — HEAD on an unmerged PR-branch commit off c1: refused, commit named, the
# refusal carries the stage prefix, the shared wording and the remediation.
harness_repo i2
c1=$(git -C "$H" rev-parse refs/remotes/origin/main~1)
s=$(h_side "$c1" i2); git -C "$H" tag -a vinngest-v1.2.0 -m r "$s"
run_step i2 "$H" v1.2.0 "$s"
step_rc  'g2b.I2:off-main-rc1' 1
step_has 'g2b.I2:stage' '::error::ancestry:'
step_has 'g2b.I2:wording' "$OFF_MAIN_MSG"
step_has 'g2b.I2:names-commit' "$s"
step_has 'g2b.I2:remediation-delete' 'git push origin :refs/tags/vinngest-v1.2.0'
step_has 'g2b.I2:remediation-local-delete' 'git tag -d vinngest-v1.2.0'
step_has 'g2b.I2:remediation-new-version' 'as a NEW version'
grep -qF "$OFF_MAIN_MSG" "$STEP_SUMMARY" && pass 'g2b.I2:summary' \
  || fail 'g2b.I2:summary' "step summary lacks the refusal"

# I3 — the PR-branch commit's content was squash-merged into main: still refused.
harness_repo i3
s=$(h_side refs/remotes/origin/main i3)
git -C "$H" checkout -q --detach refs/remotes/origin/main
git -C "$H" checkout -q "$s" -- side-i3; git -C "$H" commit -qm "squash i3"
git -C "$H" update-ref refs/remotes/origin/main HEAD
git -C "$H" tag -a vinngest-v1.2.0 -m r "$s"
run_step i3 "$H" v1.2.0 "$s"
step_rc  'g2b.I3:squash-rc1' 1
step_has 'g2b.I3:wording' "$OFF_MAIN_MSG"

# I4 — PR-branch commit off main's TIP. The argument-reversal mutant
# (`--is-ancestor origin/main HEAD`) answers 0 here; only the correct order
# refuses it.
harness_repo i4
s=$(h_side refs/remotes/origin/main i4); git -C "$H" tag -a vinngest-v1.2.0 -m r "$s"
run_step i4 "$H" v1.2.0 "$s"
step_rc  'g2b.I4:tip-side-rc1' 1
step_has 'g2b.I4:wording' "$OFF_MAIN_MSG"

# I5 — shallow clone: undecidable, refused with its own message.
harness_repo i5-src
git -C "$H" tag -a vinngest-v1.2.0 -m r refs/remotes/origin/main
git -C "$H" update-ref refs/heads/main refs/remotes/origin/main
i5="$TMP/harness/i5"
git clone -q --depth 1 "file://$H" "$i5"
run_step i5 "$i5" v1.2.0 "$(git -C "$i5" rev-parse HEAD)"
step_rc  'g2b.I5:shallow-rc1' 1
step_has 'g2b.I5:shallow-msg' 'shallow'

# I6 — corrupt history (c2 of c1<-c2<-c3 deleted, HEAD on a side commit off
# c1): merge-base exits 128 — reported as undecided, never as off-main.
harness_repo i6
c1=$(git -C "$H" rev-parse refs/remotes/origin/main~1); c2=$(git -C "$H" rev-parse refs/remotes/origin/main)
h_main_commit c3
s=$(h_side "$c1" i6); git -C "$H" tag -a vinngest-v1.2.0 -m r "$s"
rm -f "$H/.git/objects/${c2:0:2}/${c2:2}"
run_step i6 "$H" v1.2.0 "$s"
step_rc  'g2b.I6:corrupt-rc1' 1
step_has 'g2b.I6:undecided-msg' 'could not decide'
grep -qF "$OFF_MAIN_MSG" "$STEP_OUT" \
  && fail 'g2b.I6:not-off-main-msg' "an undecided walk was reported as off-main" \
  || pass 'g2b.I6:not-off-main-msg'

# I7 — the checkout is not the commit the local tag names (the checkout
# invariant broke): refused before any walk.
harness_repo i7
c=$(git -C "$H" rev-parse refs/remotes/origin/main)
git -C "$H" tag -a vinngest-v1.2.0 -m r "$(git -C "$H" rev-parse refs/remotes/origin/main~1)"
run_step i7 "$H" v1.2.0 "$c"
step_rc  'g2b.I7:mismatch-rc1' 1
step_has 'g2b.I7:mismatch-msg' 'checkout invariant'

# I8 — `--is-shallow-repository` prints NOTHING (a git that errors quietly):
# the check must refuse unless the answer is exactly `false`.
harness_repo i8
c=$(git -C "$H" rev-parse refs/remotes/origin/main); git -C "$H" tag -a vinngest-v1.2.0 -m r "$c"
EMPTY_SHALLOW_BIN="$TMP/harness/empty-shallow-bin"; mkdir -p "$EMPTY_SHALLOW_BIN"
cat > "$EMPTY_SHALLOW_BIN/git" <<STUB
#!/usr/bin/env bash
for a in "\$@"; do [[ "\$a" == --is-shallow-repository ]] && exit 0; done
exec "$REAL_GIT" "\$@"
STUB
chmod +x "$EMPTY_SHALLOW_BIN/git"
STEP_PATH_PREFIX="$EMPTY_SHALLOW_BIN" run_step i8 "$H" v1.2.0 "$c"
step_rc  'g2b.I8:empty-shallow-answer-rc1' 1
step_has 'g2b.I8:shallow-msg' 'shallow'

# I9 — no refs/remotes/origin/main (a checkout that did not fetch branches).
harness_repo i9
c=$(git -C "$H" rev-parse refs/remotes/origin/main); git -C "$H" tag -a vinngest-v1.2.0 -m r "$c"
git -C "$H" update-ref -d refs/remotes/origin/main
run_step i9 "$H" v1.2.0 "$c"
step_rc  'g2b.I9:no-origin-main-rc1' 1
step_has 'g2b.I9:no-origin-main-msg' 'origin/main'

# I10 — a tag on an OLDER main commit, main advanced since: passes. (A gate
# that only accepts main's tip — the documented "tag the squash-merge commit"
# flow after main moves on — would refuse this.)
harness_repo i10
old=$(git -C "$H" rev-parse refs/remotes/origin/main)
h_main_commit later1; h_main_commit later2
git -C "$H" tag -a vinngest-v1.2.0 -m r "$old"
run_step i10 "$H" v1.2.0 "$old"
step_rc  'g2b.I10:older-main-rc0' 0

# I11 — a PR-branch commit brought into main by a TRUE merge commit: passes
# (first-parent-only ancestry would refuse it).
harness_repo i11
s=$(h_side refs/remotes/origin/main~1 i11)
git -C "$H" checkout -q --detach refs/remotes/origin/main
git -C "$H" merge -q --no-ff -m "Merge pr-i11" "$s"
git -C "$H" update-ref refs/remotes/origin/main HEAD
git -C "$H" tag -a vinngest-v1.2.0 -m r "$s"
run_step i11 "$H" v1.2.0 "$s"
step_rc  'g2b.I11:true-merge-rc0' 0

# I12/I13 — the two steps CHAINED as the runner chains them: Record writes the
# checked-out commit, Refuse judges that value. At an older main commit the
# pair passes; at a PR-branch commit it refuses. (A Record step reading
# origin/main instead of HEAD passes a tip-only fixture and fails both here.)
harness_repo i12
old=$(git -C "$H" rev-parse refs/remotes/origin/main~1)
git -C "$H" tag -a vinngest-v1.2.0 -m r "$old"
run_record i12 "$H" "$old"
[[ "$REC_RC" == 0 && "$REC_COMMIT" == "$old" ]] && pass 'g2b.I12:record-writes-head' \
  || fail 'g2b.I12:record-writes-head' "rc=$REC_RC commit=${REC_COMMIT:-<none>} want $old"
run_step i12 "$H" v1.2.0 "$REC_COMMIT"
step_rc 'g2b.I12:chain-older-main-rc0' 0
harness_repo i13
s=$(h_side refs/remotes/origin/main~1 i13); git -C "$H" tag -a vinngest-v1.2.0 -m r "$s"
run_record i13 "$H" "$s"
[[ "$REC_RC" == 0 && "$REC_COMMIT" == "$s" ]] && pass 'g2b.I13:record-writes-head' \
  || fail 'g2b.I13:record-writes-head' "rc=$REC_RC commit=${REC_COMMIT:-<none>} want $s"
run_step i13 "$H" v1.2.0 "$REC_COMMIT"
step_rc  'g2b.I13:chain-side-rc1' 1
step_has 'g2b.I13:wording' "$OFF_MAIN_MSG"

# I14 — the build step resolves the tag by its FULL name, like the bump (B8):
# a `refs/vinngest-v1.2.0` ref pointing at main shadows the bare name. Unreachable
# on a runner (actions/checkout writes only heads/remotes/tags), pinned anyway so
# the two copies of the check cannot drift apart on this spelling.
harness_repo i14
m=$(git -C "$H" rev-parse refs/remotes/origin/main)
s=$(h_side refs/remotes/origin/main~1 i14); git -C "$H" tag -a vinngest-v1.2.0 -m r "$s"
git -C "$H" update-ref refs/vinngest-v1.2.0 "$m"
run_step i14 "$H" v1.2.0 "$m"
step_rc 'g2b.I14:bare-name-shadow-rc1' 1

# Selector byte-equality (#8782, ADR-232 §2): the writer's `TARGET=` block and
# AC6's `LATEST_TAG=` block must be the SAME 3-line pipeline once the variable
# name and the dir operand are normalized. The writer's block is exercised by
# the B rows above, so equality makes the checker behave identically. Blocks are
# found by structure (start line → first line ending `|| true)`), never by a
# literal grep a comment could satisfy. The start pattern goes through ENVIRON:
# `awk -v` processes backslash escapes and breaks the regex.
SEL_W_RE='^TARGET=\$\(git -C "\$REPO_DIR" tag '
SEL_C_RE='^LATEST_TAG=\$\(git -C "\$SCRIPT_DIR" tag '
sel_slice() { # file start-regex
  RE="$2" awk '$0 ~ ENVIRON["RE"] {on=1} on {print} on && /\|\| true\)[[:space:]]*$/ {exit}' "$1"
}
sel_count() { # file regex — lines matching
  RE="$2" awk '$0 ~ ENVIRON["RE"] {n++} END {print n+0}' "$1"
}
SEL_FIX="keep the two 3-line \`git tag --merged HEAD\` selector blocks identical, modulo name, dir operand and indentation (ADR-232 §2)"
for side in writer checker; do
  if [[ "$side" == writer ]]; then f="$SCRIPT"; re="$SEL_W_RE"; else f="$CONSUMER"; re="$SEL_C_RE"; fi
  n=$(sel_count "$f" "$re")
  [[ "$n" == 1 ]] && pass "g2.sel:$side-one-start" \
    || fail "g2.sel:$side-one-start" "$n selector start line(s) in $f, expected 1 — $SEL_FIX"
  slice=$(sel_slice "$f" "$re")
  lines=$(grep -c '' <<<"$slice")
  [[ -n "$slice" && "$lines" == 3 ]] && pass "g2.sel:$side-three-lines" \
    || fail "g2.sel:$side-three-lines" "selector slice is $lines line(s), expected 3 — $SEL_FIX"
  grep -qF -- "tag --merged HEAD --list 'vinngest-v*'" <<<"$slice" && pass "g2.sel:$side-merged-head" \
    || fail "g2.sel:$side-merged-head" "selector does not read tags merged into HEAD — $SEL_FIX"
  grep -qF -- 'sort -V' <<<"$slice" && pass "g2.sel:$side-sort-v" \
    || fail "g2.sel:$side-sort-v" "selector does not sort by version — $SEL_FIX"
done
# Directional normalization: each side may differ from the other ONLY by its
# own name and its own dir operand. A checker that used the writer's unset
# $REPO_DIR keeps it here and fails the diff.
sel_w=$(sel_slice "$SCRIPT" "$SEL_W_RE" | sed -e 's/^TARGET=/SEL=/' -e 's/"\$REPO_DIR"/"$DIR"/' -e 's/^[[:space:]]*//')
sel_c=$(sel_slice "$CONSUMER" "$SEL_C_RE" | sed -e 's/^LATEST_TAG=/SEL=/' -e 's/"\$SCRIPT_DIR"/"$DIR"/' -e 's/^[[:space:]]*//')
if [[ -n "$sel_w" && "$sel_w" == "$sel_c" ]]; then
  pass 'g2.sel:byte-equal'
else
  fail 'g2.sel:byte-equal' "writer and checker selectors differ — $SEL_FIX: $(diff <(printf '%s\n' "$sel_w") <(printf '%s\n' "$sel_c") | tr '\n' '|')"
fi
# Consumer wiring. Byte-equality covers only the 3 sliced lines, so pin what
# the checker DOES with them: exactly one write of LATEST_TAG anywhere (an
# `export`/`&&`/`read`/`printf -v` reassignment after the selector would
# otherwise swap the value unseen), and each pin assert is a WHOLE line directly
# under an `assert "` call (a substring match survives `|| true` appended inside
# the eval string).
n=$(sel_count "$CONSUMER" '^[[:space:]]*LATEST_TAG[+]?=|^[^#]*[^A-Za-z0-9_$]LATEST_TAG[+]?=|^[^#]*(read|printf -v|mapfile|readarray)[^#]*[[:space:]]LATEST_TAG([[:space:]]|$)')
[[ "$n" == 1 ]] && pass 'g2.sel:checker-one-write' \
  || fail 'g2.sel:checker-one-write' "$n write(s) of LATEST_TAG in $CONSUMER, expected exactly the selector"
for pv in PIN DED_PIN; do
  n=$(W="\"[[ '\$$pv' == '\$LATEST_TAG' ]]\"" awk '
    { t=$0; sub(/^[[:space:]]+/,"",t); sub(/[[:space:]]+$/,"",t)
      if (t==ENVIRON["W"] && prev ~ /^[[:space:]]*assert "/) n++; prev=$0 }
    END { print n+0 }' "$CONSUMER")
  [[ "$n" == 1 ]] && pass "g2.sel:checker-$pv-reads-selector" \
    || fail "g2.sel:checker-$pv-reads-selector" "$n whole-line assert(s) comparing \$$pv to \$LATEST_TAG, expected 1"
done
# The two CI arms that must FAIL rather than skip (shallow history, empty merged
# set) keep a literal "false" verdict inside the AC6 block.
n=$(awk '/^# --- AC6:/{on=1} /^# --- AC6b:/{on=0} on && /^[[:space:]]*assert "[^"]*" "false"[[:space:]]*$/{n++} END{print n+0}' "$CONSUMER")
[[ "$n" == 2 ]] && pass 'g2.sel:checker-ci-arms-fail' \
  || fail 'g2.sel:checker-ci-arms-fail' "$n AC6 CI arm(s) assert \"false\", expected 2 (shallow + empty merged set)"
# The checker mirrors the writer's walk_err refusal: a truncated --merged set
# (rc 0, stderr only) must reach the shallow/unreadable arm, never the drift
# diagnosis. Pin the stderr read and its use in that arm's condition, each as a
# whole code line inside the AC6 block.
for want in \
  "AC6_WALK_ERR=\$( (cd \"\$SCRIPT_DIR\" && git tag --merged HEAD --list 'vinngest-v*' 2>&1 >/dev/null) || true)" \
  'if [[ "$AC6_SHALLOW" != "false" || -n "$AC6_WALK_ERR" ]]; then'; do
  n=$(W="$want" awk '/^# --- AC6:/{on=1} /^# --- AC6b:/{on=0} on && $0==ENVIRON["W"]{n++} END{print n+0}' "$CONSUMER")
  [[ "$n" == 1 ]] && pass "g2.sel:checker-walk-err:${want:0:12}" \
    || fail "g2.sel:checker-walk-err:${want:0:12}" "$n whole-line match(es) in AC6 for: $want"
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
for lit in "BOT_NAME='soleur-infra[bot]'" "BOT_EMAIL='335404629+soleur-infra[bot]@users.noreply.github.com'" "BOT_PR_LOGIN='app/soleur-infra'"; do
  if [[ -f "$SCRIPT" ]] && grep -qF -- "$lit" "$SCRIPT"; then pass "g2.script:$lit"
  else fail "g2.script:$lit" "script lacks identity literal: $lit"; fi
done
# The bot identity must be on the CLA allowlist, or every pin PR it authors is stuck on
# CLA Required: derive BOT_NAME from the script and require it as a MEMBER of cla.yml's
# allowlist value (two files, one identity, #9262).
CLA_YML="$REPO_ROOT/.github/workflows/cla.yml"
bot_name=$(sed -n "s/^BOT_NAME='\\([^']*\\)'\$/\\1/p" "$SCRIPT" | head -1)
cla_list=$(sed -n 's/^[[:space:]]*allowlist:[[:space:]]*"\([^"]*\)"[[:space:]]*$/\1/p' "$CLA_YML" | head -1)
if [[ -n "$bot_name" && -n "$cla_list" && ",${cla_list}," == *",${bot_name},"* ]]; then pass 'g2.script:bot-on-cla-allowlist'
else fail 'g2.script:bot-on-cla-allowlist' "BOT_NAME='${bot_name:-<unparsed>}' is not a member of cla.yml allowlist '${cla_list:-<unparsed>}'"; fi

# Verdict-helper self-test (#8782 review): assert_excluded and assert_refused
# decide their rows' verdicts, so a neuter inside either (a check replaced by a
# bare `pass`) keeps every count and the floor intact. Each helper is driven in
# two HERMETIC bad states, each failing an exact, disjoint subset of its checks;
# the FAIL delta must equal that subset's size, so neutering any single check
# moves it. Output is discarded (an expected failure must not print a FAIL
# line) and the verdict is reported directly, never through the helpers.
st_run() { # <expected-delta> <label> <helper call...>
  local want="$1" label="$2" p0=$PASS f0=$FAIL got; shift 2
  { "$@"; } >/dev/null 2>&1
  got=$((FAIL - f0)); PASS=$p0 FAIL=$f0
  [[ "$got" == "$want" ]] && return 0
  printf 'FAIL [selftest:%s]: FAIL moved by %s, expected exactly %s\n' "$label" "$got" "$want"
  exit 1
}
LAST_OUT="$TMP/selftest.out"; LAST_GOUT="$TMP/selftest.gout"
# State A — the verdict checks fail, the side-effect checks pass: a clean
# fixture (pins v1.1.37@DIG_OLD, empty crane and gh logs, no bump branch).
base_fixture selftest-a
: > "$LAST_OUT"
printf 'result=error\n' > "$LAST_GOUT"; LAST_RC=1
st_run 3 excluded-verdict assert_excluded 'selftest.ex-a' v1.1.99   # exit, result, target
printf 'result=noop\n' > "$LAST_GOUT"; LAST_RC=0
st_run 4 refused-verdict assert_refused 'selftest.rf-a' 'wording absent' resolve   # nonzero, result, stage, wording
# State B — the verdict checks pass, the side-effect checks fail: pins moved
# to v1.1.38, the off-main tag reached crane, gh was called, a branch exists.
new_fixture_repo selftest-b
write_fixture_cloud_inits "$F_REPO" v1.1.38 "$DIG_NEW" v1.1.38 "$DIG_NEW"
fixture_commit "selftest-b"
git -C "$F_REPO" push -q "$F_ORIGIN" HEAD:refs/heads/main HEAD:refs/heads/soleur/selftest
printf 'crane digest ghcr.io/x:v1.1.99\n' > "$MOCK_CRANE_LOG"
printf 'gh pr list\n' > "$MOCK_GH_LOG"
printf 'target=v1.1.37 resolved=x\n::error::resolve: wording present\n' > "$LAST_OUT"
printf 'result=noop\n' > "$LAST_GOUT"; LAST_RC=0
st_run 4 excluded-side-effects assert_excluded 'selftest.ex-b' v1.1.99   # crane, per-file pins, gh, branch
printf 'result=error\n' > "$LAST_GOUT"; LAST_RC=1
st_run 3 refused-side-effects assert_refused 'selftest.rf-b' 'wording present' resolve   # crane, gh, branch
pass 'selftest:verdict-helpers-can-fail'
# The gh/output/result assertion helpers own their verdicts too: drive each once in
# the direction it must FAIL (delta 1) and once in the direction it must PASS
# (delta 0), so a helper rewritten to always pass (or always fail) is caught.
MOCK_GH_LOG="$TMP/selftest.ghlog"; printf 'gh pr create --head x\n' > "$MOCK_GH_LOG"
LAST_OUT="$TMP/selftest2.out"; printf 'hello needle world\n' > "$LAST_OUT"
LAST_GOUT="$TMP/selftest2.gout"; printf 'result=opened\n' > "$LAST_GOUT"; LAST_RC=0
st_run 1 gh-called-miss      assert_gh_called     'selftest.gc-miss' 'gh pr merge '
st_run 0 gh-called-hit       assert_gh_called     'selftest.gc-hit'  'gh pr create '
st_run 1 gh-not-called-hit   assert_gh_not_called 'selftest.gn-hit'  'gh pr create '
st_run 0 gh-not-called-miss  assert_gh_not_called 'selftest.gn-miss' 'gh pr merge '
st_run 1 out-has-miss        assert_out_has       'selftest.oh-miss' 'absent-token'
st_run 0 out-has-hit         assert_out_has       'selftest.oh-hit'  'needle'
st_run 1 result-miss         assert_result        'selftest.r-miss'  existing
st_run 0 result-hit          assert_result        'selftest.r-hit'   opened
st_run 1 rc-miss             assert_rc            'selftest.rc-miss' 1
st_run 0 rc-hit              assert_rc            'selftest.rc-hit'  0
pass 'selftest:gh-out-result-helpers-both-directions'

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
