#!/usr/bin/env bash
# Fixture tests for .github/scripts/mint-inngest-bootstrap-tag.sh, the script that
# mint-inngest-bootstrap-tag.yml drives on every push to main that can change the
# soleur-inngest-bootstrap image (#4326, ADR-232 §8).
#
# WHY THIS SUITE EXISTS. A workflow cannot be dispatch-tested from a feature branch,
# so the YAML stays a thin driver and every decision lives in the script, verified
# here out of band against synthetic fixture repos (the same split as
# test-bump-inngest-bootstrap-pin.sh).
#
# STUBS. `git` is REAL, against a fixture working clone plus a bare fixture origin.
# `gh` is PATH-shimmed and replays the REST contracts the script depends on, rather
# than answering whatever it is asked:
#   - POST git/tags builds a REAL annotated tag object in the bare origin with
#     `git mktag`, and answers the documented multi-line body carrying BOTH the tag
#     object's `sha` and the commit's `object.sha`.
#   - POST git/refs runs `update-ref` in the bare origin with the posted SHA as-is:
#     422 `Reference already exists` is derived from the origin's state, and 422
#     `Object does not exist` from an unknown SHA.
#   - the dispatch POST prints nothing and exits 0 (a 204).
#   - an error exits 1 with the body on stdout and `gh: … (HTTP 422)` on stderr, as
#     real `gh` does. The `workflows`-permission text is SYNTHESIZED (GitHub's exact
#     wording is unverified): its row tests the classifier on this wording, and a
#     plain-422 negative control proves the class is not assigned to every 422.
#   - anything else (another subcommand, a GET, a missing `--input -`) exits 64.
#
# GUARD CONTRACT (plan §Guard Contract). Guard 1 = the image-input decision,
# Guard 2 = version allocation, Guard 3 = writer/checker parity and the
# workflow's credential shape. Script-mutation rows edit a TEMP COPY, prove the
# edit landed inside the target function, run the unmutated copy as a positive
# control, and count only rc 1 as caught (rc 2 is a broken instrument).
set -uo pipefail
export LC_ALL=C
export TMPDIR="${TMPDIR:-/var/tmp}"

REPO_ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
SCRIPT="$REPO_ROOT/.github/scripts/mint-inngest-bootstrap-tag.sh"
BUMP="$REPO_ROOT/.github/scripts/bump-inngest-bootstrap-pin.sh"
BUILD_WF="$REPO_ROOT/.github/workflows/build-inngest-bootstrap-image.yml"
MINT_WF="$REPO_ROOT/.github/workflows/mint-inngest-bootstrap-tag.yml"
CONSUMER="$REPO_ROOT/apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh"
COMPOSITE="$REPO_ROOT/.github/actions/mint-soleur-ai-app-token/action.yml"
for f in "$SCRIPT" "$BUMP" "$BUILD_WF" "$MINT_WF" "$CONSUMER" "$COMPOSITE"; do
  [[ -f "$f" ]] || { echo "FAIL: $f not found"; exit 1; }
done

# The shell fixture chokepoint (#7849): scrubs inherited GIT_*, pins a fixture
# identity and a discovery ceiling, and arms the #7833 git-location tripwire. The
# scrub is exported, so it also reaches the spawned mint script.
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
MIN_ASSERTIONS=373   # anti-vacuity floor = the green run's exact count; raise when adding rows, never lower it silently

pass() { echo "PASS [$1]"; PASS=$((PASS+1)); }
fail() { echo "FAIL [$1]: $2"; FAIL=$((FAIL+1)); }

# Instrument self-test: both helpers must move their counters, or every verdict
# below is unobservable. Reported with printf + exit, never through the helpers.
st_p=$PASS st_f=$FAIL
pass 'selftest.pass' >/dev/null
fail 'selftest.fail' 'expected' >/dev/null
if (( PASS != st_p + 1 || FAIL != st_f + 1 )); then
  printf 'FATAL [selftest]: pass()/fail() did not move their counters (pass %s->%s, fail %s->%s)\n' \
    "$st_p" "$PASS" "$st_f" "$FAIL"
  exit 2
fi
PASS=$st_p FAIL=$st_f

python3 -c 'import yaml' 2>/dev/null || pip3 install --quiet pyyaml 2>/dev/null || true
if ! python3 -c 'import yaml' 2>/dev/null; then
  printf 'FATAL: python3 with PyYAML is required for the Guard 3 workflow-shape rows\n'
  exit 2
fi

HEX_A=$(printf 'a%.0s' $(seq 1 64))
HEX_B=$(printf 'b%.0s' $(seq 1 64))
HEX_C=$(printf 'c%.0s' $(seq 1 64))
HEX_D=$(printf 'd%.0s' $(seq 1 64))
# Fake credentials: never a real token SHAPE (cq-test-fixtures-synthesized-only,
# and a real shape trips push protection).
TAG_TOK='fixture-tag-credential-0001'
DSP_TOK='fixture-dispatch-credential-0002'

# ---------------------------------------------------------------------------
# PATH-shimmed gh (see the header for the contracts it replays)
# ---------------------------------------------------------------------------
BIN="$TMP/bin"
mkdir -p "$BIN"
cat > "$BIN/gh" <<'STUB'
#!/usr/bin/env bash
set -uo pipefail
args=("$@")
printf 'gh %s | token=%s | debug=%s\n' "$*" "${GH_TOKEN:-}" "${GH_DEBUG:-}${DEBUG:-}" >> "${MOCK_GH_LOG:?unset}"
if [[ "${MOCK_GH_FORBID:-0}" == 1 ]]; then
  echo "gh-stub: FORBIDDEN call in a no-network row: $*" >&2; exit 99
fi
[[ "${args[0]:-}" == api ]] || { echo "gh-stub: unexpected subcommand: $*" >&2; exit 64; }
method="" input="" path=""
for ((i=1; i<${#args[@]}; i++)); do
  case "${args[$i]}" in
    --method|-X) method="${args[$((i+1))]:-}"; i=$((i+1)) ;;
    --input)     input="${args[$((i+1))]:-}"; i=$((i+1)) ;;
    -*) echo "gh-stub: unmodelled flag ${args[$i]}" >&2; exit 64 ;;
    *)  if [[ -z "$path" ]]; then path="${args[$i]}"; else echo "gh-stub: extra operand ${args[$i]}" >&2; exit 64; fi ;;
  esac
done
[[ "$method" == POST && "$input" == - ]] \
  || { echo "gh-stub: only POST --input - is modelled (method=$method input=$input)" >&2; exit 64; }
body=$(cat)
printf '%s\t%s\n' "$path" "$(jq -c . <<<"$body" 2>/dev/null || printf 'INVALID-JSON')" >> "${MOCK_GH_BODIES:?unset}"
O="${MOCK_ORIGIN:?unset}"
err422() {
  jq -n --arg m "$1" '{message: $m, documentation_url: "https://docs.github.com/rest", status: "422"}'
  printf 'gh: %s (HTTP 422)\n' "$1" >&2
  exit 1
}
case "$path" in
  repos/jikig-ai/soleur/git/tags)
    case "${MOCK_GH_TAGS_FAIL:-}" in
      workflows) err422 'refusing to allow a GitHub App to create or update workflow `.github/workflows/build-inngest-bootstrap-image.yml` without `workflows` permission' ;;
      plain)     err422 'Validation Failed' ;;
    esac
    tag=$(jq -r '.tag // empty' <<<"$body"); msg=$(jq -r '.message // empty' <<<"$body")
    obj=$(jq -r '.object // empty' <<<"$body"); typ=$(jq -r '.type // empty' <<<"$body")
    tn=$(jq -r '.tagger.name // empty' <<<"$body"); te=$(jq -r '.tagger.email // empty' <<<"$body")
    [[ "$typ" == commit ]] || err422 'Invalid request: type'
    [[ "$(git -C "$O" cat-file -t "$obj" 2>/dev/null)" == commit ]] || err422 'Object does not exist'
    [[ -n "$tag" && -n "$msg" && -n "$tn" && -n "$te" ]] || err422 'Invalid request'
    sha=$(printf 'object %s\ntype commit\ntag %s\ntagger %s <%s> %s +0000\n\n%s\n' \
      "$obj" "$tag" "$tn" "$te" "$(date +%s)" "$msg" | git -C "$O" mktag 2>/dev/null) || err422 'Invalid request: mktag'
    # A racer lands the same name between this tag object and the ref POST.
    [[ "${MOCK_GH_RACE_REF:-0}" == 1 ]] && git -C "$O" update-ref "refs/tags/$tag" "$obj"
    [[ "${MOCK_GH_TAG_WRONGSHA:-0}" == 1 ]] && sha=0123456789abcdef0123456789abcdef01234567
    jq -n --arg sha "$sha" --arg tag "$tag" --arg msg "$msg" --arg obj "$obj" --arg tn "$tn" --arg te "$te" '{
      node_id: "TAG_fixture", tag: $tag, sha: $sha,
      url: ("https://api.github.com/repos/jikig-ai/soleur/git/tags/" + $sha),
      message: $msg,
      tagger: {name: $tn, email: $te, date: "2026-09-27T00:00:00Z"},
      object: {type: "commit", sha: $obj, url: ("https://api.github.com/repos/jikig-ai/soleur/git/commits/" + $obj)},
      verification: {verified: false, reason: "unsigned", signature: null, payload: null}
    }'
    ;;
  repos/jikig-ai/soleur/git/refs)
    ref=$(jq -r '.ref // empty' <<<"$body"); sha=$(jq -r '.sha // empty' <<<"$body")
    [[ "$ref" == refs/tags/* ]] || err422 'Invalid request: ref'
    git -C "$O" cat-file -e "$sha" 2>/dev/null || err422 'Object does not exist'
    git -C "$O" rev-parse -q --verify "$ref" >/dev/null 2>&1 && err422 'Reference already exists'
    git -C "$O" update-ref "$ref" "$sha" || err422 'Invalid request: update-ref'
    jq -n --arg ref "$ref" --arg sha "$sha" '{
      ref: $ref, node_id: "REF_fixture",
      url: ("https://api.github.com/repos/jikig-ai/soleur/git/" + $ref),
      object: {sha: $sha, type: "tag", url: ("https://api.github.com/repos/jikig-ai/soleur/git/tags/" + $sha)}
    }'
    ;;
  repos/jikig-ai/soleur/actions/workflows/build-inngest-bootstrap-image.yml/dispatches)
    if [[ "${MOCK_GH_DISPATCH_FAIL:-0}" == 1 ]]; then
      jq -n '{message: "Server Error", status: "500"}'
      printf 'gh: Server Error (HTTP 500)\n' >&2
      exit 1
    fi
    exit 0
    ;;
  *) echo "gh-stub: unmodelled path $path" >&2; exit 64 ;;
esac
STUB
chmod +x "$BIN/gh"

# ---------------------------------------------------------------------------
# Fixture builders
# ---------------------------------------------------------------------------
FX_CARRIERS=()
for i in $(seq -w 1 13); do FX_CARRIERS+=("carrier-$i.sh"); done
FX_WF='.github/workflows/build-inngest-bootstrap-image.yml'
FX_INFRA='apps/web-platform/infra'

# Fixture and mutation TEXT that reads like a command (a `cp`, a redirect into
# $BUILD_DIR, a `git -C`) lives in this quoted heredoc, looked up by key: it is
# data written into fixture files, never executed here, and the P1b operand
# scanner (fixture-relative-assert) skips quoted-heredoc bodies.
FX_TEXT=$(cat <<'FXTEXT'
cp_fmt=          cp %s/%s "$BUILD_DIR/%s"
heredoc_open=          cat > "$BUILD_DIR/Dockerfile" <<DOCKERFILE
outside_cp=          cp scripts/outside.sh "$BUILD_DIR/outside.sh"
swap_sed=s#cp apps/web-platform/infra/carrier-13.sh "\$BUILD_DIR/carrier-13.sh"#cp apps/web-platform/infra/other.tf "$BUILD_DIR/other.tf"#
added_cp=          cp apps/web-platform/infra/carrier-14.sh "$BUILD_DIR/carrier-14.sh"
sel_anchor=BASE=$(git -C "$REPO_DIR" tag
sel_renamed=BASE_SEL=$(git -C "$REPO_DIR" tag
luks_cp=          cp apps/web-platform/infra/inngest-luks-cutover.timer
FXTEXT
)
fxt() { # fxt <key> — the literal stored under <key> in FX_TEXT
  awk -v k="$1" 'index($0, k "=") == 1 { print substr($0, length(k) + 2); f = 1; exit } END { if (!f) exit 1 }' <<<"$FX_TEXT" \
    || { printf 'FATAL: fixture text key %s missing\n' "$1" >&2; exit 2; }
}

# write_fixture_tree <dir> — the image's source tree in the real SHAPES: `cp`
# staging lines, one DOCKERFILE heredoc whose COPY lines name the same files, and
# the four pins in inngest.tf / vector.tf (plus the non-baked arm64 pin).
write_fixture_tree() {
  local d="$1" c
  assert_fixture_dir "$d"
  mkdir -p "$d/.github/workflows" "$d/$FX_INFRA"
  {
    printf '%s\n' 'name: Build inngest-bootstrap OCI image (fixture)' \
      '# Fixture: staging and recipe shapes mirror the real workflow.' \
      'on:' '  push:' '    tags:' "      - 'vinngest-v*.*.*'" \
      'jobs:' '  build:' '    runs-on: ubuntu-latest' '    steps:' \
      '      - name: Build + verify + push' '        run: |' \
      '          set -euo pipefail' '          BUILD_DIR=$(mktemp -d)'
    for c in "${FX_CARRIERS[@]}"; do
      # shellcheck disable=SC2059  # the format is fixture data from FX_TEXT
      printf "$(fxt cp_fmt)\n" "$FX_INFRA" "$c" "$c"
    done
    printf '%s\n' "$(fxt heredoc_open)" \
      '          FROM alpine:3.20' '          RUN apk add --no-cache bash curl' \
      '          ENV INNGEST_CLI_VERSION=${INNGEST_VERSION}'
    for c in "${FX_CARRIERS[@]}"; do printf '          COPY %s /%s\n' "$c" "$c"; done
    printf '%s\n' '          ENTRYPOINT ["/bin/bash", "-c", "/carrier-01.sh"]' \
      '          DOCKERFILE' '          docker build -t "$IMAGE:$TAG" "$BUILD_DIR"'
  } > "$d/$FX_WF"
  for c in "${FX_CARRIERS[@]}"; do printf '#!/bin/sh\necho %s v1\n' "$c" > "$d/$FX_INFRA/$c"; done
  printf 'locals {\n  inngest_cli_version = "v1.9.0"\n  inngest_cli_sha256  = "%s"\n}\n' "$HEX_A" > "$d/$FX_INFRA/inngest.tf"
  printf 'locals {\n  vector_version      = "0.40.0"\n  vector_sha256       = "%s"\n  vector_sha256_arm64 = "%s"\n}\n' \
    "$HEX_B" "$HEX_C" > "$d/$FX_INFRA/vector.tf"
  printf 'runcmd:\n  IREF=ghcr.io/jikig-ai/soleur-inngest-bootstrap:v1.1.40@sha256:%s\n' "$HEX_D" > "$d/$FX_INFRA/cloud-init.yml"
  printf 'resource "null_resource" "other" {}\n' > "$d/$FX_INFRA/other.tf"
}

# mf_new <name> [--no-tag] — fresh working clone on `main` whose base commit
# carries an annotated vinngest-v1.1.40 (as humans cut them), pushed with its tag
# to a bare origin, and fetched back so refs/remotes/origin/main exists.
# Sets F_REPO, F_ORIGIN and resets the gh logs and per-row env.
mf_new() {
  local name="$1"
  F_REPO="$TMP/$name/repo"
  F_ORIGIN="$TMP/$name/origin.git"
  mkdir -p "$F_REPO"
  assert_fixture_dir "$F_REPO"
  git init -q -b main "$F_REPO"
  git init -q --bare "$F_ORIGIN"
  write_fixture_tree "$F_REPO"
  git -C "$F_REPO" add -A
  git -C "$F_REPO" commit -qm 'base'
  [[ "${2:-}" == --no-tag ]] || git -C "$F_REPO" tag -a vinngest-v1.1.40 -m 'release v1.1.40'
  git -C "$F_REPO" remote add origin "$F_ORIGIN"
  git -C "$F_REPO" push -q origin main 'refs/tags/*:refs/tags/*' 2>/dev/null
  git -C "$F_REPO" fetch -q origin
  MOCK_GH_LOG="$TMP/$name/gh.log"; : > "$MOCK_GH_LOG"
  MOCK_GH_BODIES="$TMP/$name/gh.bodies"; : > "$MOCK_GH_BODIES"
  MINT_ENV=()
  MINT_BASH=()
  SUT="${SUT_OVERRIDE:-$SCRIPT}"
}

# mf_commit <msg> — commit everything and publish it as origin/main.
mf_commit() {
  assert_fixture_dir "$F_REPO"
  git -C "$F_REPO" add -A
  git -C "$F_REPO" commit -qm "$1" --allow-empty
  git -C "$F_REPO" push -q origin HEAD:refs/heads/main 2>/dev/null
  git -C "$F_REPO" fetch -q origin
}

# fx_carrier <basename> <text> — rewrite one carrier's content.
fx_carrier() { printf '#!/bin/sh\necho %s\n' "$2" > "$F_REPO/$FX_INFRA/$1"; }
# fx_pin <file> <name> <value> — rewrite one pin's value in place.
fx_pin() {
  sed -i -E "s/^([[:space:]]*$2[[:space:]]*=[[:space:]]*)\"[^\"]*\"/\1\"$3\"/" "$F_REPO/$FX_INFRA/$1"
}
fx_wf_sed() { sed -i -E "$1" "$F_REPO/$FX_WF"; }

# side_tag_on_origin <tag> [--annotate] — a tag on a side commit that exists ONLY
# on the bare origin: never merged into main, absent from the local clone.
side_tag_on_origin() {
  local tag="$1" s
  git -C "$F_REPO" checkout -q -b "side-$tag" main
  git -C "$F_REPO" commit -q --allow-empty -m "side $tag"
  s=$(git -C "$F_REPO" rev-parse HEAD)
  git -C "$F_REPO" checkout -q main
  git -C "$F_REPO" push -q origin "$s:refs/heads/side-$tag" 2>/dev/null
  if [[ "${2:-}" == --annotate ]]; then
    git -C "$F_REPO" tag -a "$tag" -m "side $tag" "$s"
  else
    git -C "$F_REPO" tag "$tag" "$s"
  fi
  git -C "$F_REPO" push -q origin "refs/tags/$tag" 2>/dev/null
  git -C "$F_REPO" tag -d "$tag" >/dev/null
  git -C "$F_REPO" branch -q -D "side-$tag"
}

# run_mint <label> <args...> — run the SUT against F_REPO. Every ambient
# credential and CI sink is scrubbed and re-supplied per row, so a CI run never
# appends to the real GITHUB_OUTPUT.
run_mint() {
  local label="$1"; shift
  LAST_OUT="$TMP/out.$label"; LAST_ERR="$TMP/err.$label"
  LAST_GOUT="$TMP/gout.$label"; LAST_GSUM="$TMP/gsum.$label"
  : > "$LAST_GOUT"; : > "$LAST_GSUM"
  LAST_RC=0
  env -u GITHUB_OUTPUT -u GITHUB_STEP_SUMMARY -u MINT_TAG_TOKEN -u MINT_DISPATCH_TOKEN \
      -u GH_TOKEN -u GITHUB_TOKEN -u GH_DEBUG -u DEBUG \
    PATH="$BIN:$PATH" MINT_REPO_DIR="$F_REPO" MINT_REPO=jikig-ai/soleur \
    MOCK_ORIGIN="$F_ORIGIN" MOCK_GH_LOG="$MOCK_GH_LOG" MOCK_GH_BODIES="$MOCK_GH_BODIES" \
    GITHUB_OUTPUT="$LAST_GOUT" GITHUB_STEP_SUMMARY="$LAST_GSUM" \
    ${MINT_ENV[@]+"${MINT_ENV[@]}"} \
    bash ${MINT_BASH[@]+"${MINT_BASH[@]}"} "$SUT" "$@" > "$LAST_OUT" 2> "$LAST_ERR" || LAST_RC=$?
}

# ---------------------------------------------------------------------------
# Assertions
# ---------------------------------------------------------------------------
a_eq() { # a_eq <id> <got> <want>
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "got '$2', want '$3'"; fi
}
# field <key> — the value of the SINGLE `key=` line on stdout, or a marker naming
# how many there were (a duplicated or missing result line is itself a failure).
field() {
  local n
  n=$(grep -c "^$1=" "$LAST_OUT" || true)
  if [[ "$n" != 1 ]]; then printf '<%s %s= lines>' "$n" "$1"; return 0; fi
  grep "^$1=" "$LAST_OUT" | cut -d= -f2-
}
gh_calls() { grep -c '^gh ' "$MOCK_GH_LOG" || true; }
gh_calls_to() { grep -c -- "$1" "$MOCK_GH_LOG" || true; }
origin_tags() {
  git -C "$F_ORIGIN" for-each-ref --format='%(refname:strip=2)' 'refs/tags/vinngest-v*' | sort -V | paste -sd, -
}
# expect <id> <rc> <result> <gh-calls> <origin-tags> — the four facts every row pins.
expect() {
  a_eq "$1:rc" "$LAST_RC" "$2"
  a_eq "$1:result" "$(field result)" "$3"
  a_eq "$1:gh-calls" "$(gh_calls)" "$4"
  a_eq "$1:origin-tags" "$(origin_tags)" "$5"
}
a_out_has() { # a_out_has <id> <literal> — stdout+stderr carries the literal
  if grep -qF -- "$2" "$LAST_OUT" "$LAST_ERR"; then pass "$1"; else fail "$1" "output lacks: $2"; fi
}
a_out_lacks() {
  if grep -qF -- "$2" "$LAST_OUT" "$LAST_ERR"; then fail "$1" "output carries forbidden: $2"; else pass "$1"; fi
}
# a_annotated <id> <tag> — the tag is an ANNOTATED tag object peeling to the
# fixture HEAD, tagged by github-actions[bot], whose message names #4326 and the
# commit. A lightweight tag fails the first check.
a_annotated() {
  local id="$1" t="$2" head
  head=$(git -C "$F_REPO" rev-parse HEAD)
  a_eq "$id:annotated" "$(git -C "$F_ORIGIN" cat-file -t "refs/tags/$t" 2>/dev/null)" tag
  a_eq "$id:peels-to-head" "$(git -C "$F_ORIGIN" rev-parse -q --verify "refs/tags/$t^{commit}" 2>/dev/null)" "$head"
  if git -C "$F_ORIGIN" cat-file -p "refs/tags/$t" 2>/dev/null | grep -qE '^tagger github-actions\[bot\] <41898282\+github-actions\[bot\]@users\.noreply\.github\.com> '; then
    pass "$id:tagger"
  else
    fail "$id:tagger" "tag $t is not tagged by github-actions[bot]"
  fi
  local msg
  msg=$(git -C "$F_ORIGIN" cat-file -p "refs/tags/$t" 2>/dev/null | sed '1,/^$/d')
  if grep -qF '#4326' <<<"$msg" && grep -qF "$head" <<<"$msg"; then
    pass "$id:message"
  else
    fail "$id:message" "tag message does not name #4326 and the commit"
  fi
}

# ===========================================================================
echo "=== Guard 1: image-input drift decision ==="
# ===========================================================================

# G1.baseline — HEAD is the tagged commit itself: nothing to mint.
mf_new g1-head-tagged
run_mint g1-head-tagged --dry-run
expect 'g1.head-tagged' 0 noop 0 vinngest-v1.1.40
a_eq 'g1.head-tagged:reason' "$(field reason)" head-tagged

# G1.unchanged — a later commit that changes no image input.
mf_new g1-unchanged
mf_commit 'docs only'
run_mint g1-unchanged --dry-run
expect 'g1.unchanged' 0 noop 0 vinngest-v1.1.40
a_eq 'g1.unchanged:reason' "$(field reason)" unchanged
a_eq 'g1.unchanged:base' "$(field base)" v1.1.40
a_eq 'g1.unchanged:changed-empty' "$(field changed)" ''
a_eq 'g1.unchanged:tags-local' "$(field tags)" local
# The noop summary lists every comparison made, so a skipped class is visible.
for cls in 'carriers:' 'pins:' 'recipe:'; do
  if grep -qF -- "$cls" "$LAST_GSUM"; then pass "g1.unchanged:summary-$cls"
  else fail "g1.unchanged:summary-$cls" "noop step summary does not list the $cls comparison"; fi
done

# G1 row 1 — only the LAST carrier changes, after twelve unchanged ones.
mf_new g1-r1
fx_carrier carrier-13.sh 'carrier-13 v2'
mf_commit 'change the last carrier'
run_mint g1-r1 --dry-run
expect 'g1.r1' 0 would-mint 0 vinngest-v1.1.40
a_eq 'g1.r1:changed' "$(field changed)" 'carrier:carrier-13.sh'
a_eq 'g1.r1:gout' "$(cat "$LAST_GOUT")" 'result=would-mint'
# ...and the same fixture through --tag: exactly one annotated tag, max+1.
MINT_ENV=(MINT_TAG_TOKEN="$TAG_TOK")
run_mint g1-r1-tag --tag
expect 'g1.r1-tag' 0 tagged 2 vinngest-v1.1.40,vinngest-v1.1.41
a_eq 'g1.r1-tag:tag' "$(field tag)" vinngest-v1.1.41
a_annotated 'g1.r1-tag' vinngest-v1.1.41
a_eq 'g1.r1-tag:gout' "$(paste -sd' ' "$LAST_GOUT")" 'tag=vinngest-v1.1.41 result=tagged'
a_eq 'g1.r1-tag:tag-token' "$(grep -c "git/tags .*| token=$TAG_TOK |" "$MOCK_GH_LOG" || true)" 1
a_eq 'g1.r1-tag:ref-token' "$(grep -c "git/refs .*| token=$TAG_TOK |" "$MOCK_GH_LOG" || true)" 1
# The ref POST carries the TAG OBJECT sha from the response (jq .sha), never the
# commit's object.sha that the same response also carries.
want_obj=$(git -C "$F_ORIGIN" rev-parse "refs/tags/vinngest-v1.1.41")
a_eq 'g1.r1-tag:ref-body' "$(awk -F'\t' '$1 ~ /git\/refs$/ {print $2}' "$MOCK_GH_BODIES")" \
  "{\"ref\":\"refs/tags/vinngest-v1.1.41\",\"sha\":\"$want_obj\"}"
a_eq 'g1.r1-tag:tag-body-object' "$(awk -F'\t' '$1 ~ /git\/tags$/ {print $2}' "$MOCK_GH_BODIES" | jq -r '.object + " " + .type + " " + .tag')" \
  "$(git -C "$F_REPO" rev-parse HEAD) commit vinngest-v1.1.41"

# G1 row 3b — only the FIRST carrier changes.
mf_new g1-r3b
fx_carrier carrier-01.sh 'carrier-01 v2'
mf_commit 'change the first carrier'
run_mint g1-r3b --dry-run
expect 'g1.r3b' 0 would-mint 0 vinngest-v1.1.40
a_eq 'g1.r3b:changed' "$(field changed)" 'carrier:carrier-01.sh'

# G1 row 3 — carriers identical, ONE pin changed; one case per pin.
for pin_case in "inngest.tf inngest_cli_version v1.9.1" "inngest.tf inngest_cli_sha256 $HEX_D" \
                "vector.tf vector_version 0.41.0" "vector.tf vector_sha256 $HEX_D"; do
  read -r pf pn pv <<<"$pin_case"
  mf_new "g1-r3-$pn"
  fx_pin "$pf" "$pn" "$pv"
  mf_commit "bump $pn"
  run_mint "g1-r3-$pn" --dry-run
  expect "g1.r3.$pn" 0 would-mint 0 vinngest-v1.1.40
  a_eq "g1.r3.$pn:changed" "$(field changed)" "pin:$pn"
done

# The arm64 Vector pin is not baked into the image: changing it alone is a noop.
mf_new g1-arm64
fx_pin vector.tf vector_sha256_arm64 "$HEX_A"
mf_commit 'bump arm64 only'
run_mint g1-arm64 --dry-run
expect 'g1.arm64-not-baked' 0 noop 0 vinngest-v1.1.40

# Empty Vector pins on BOTH sides are legal (the build skips Vector): noop.
# "Empty" means the line is ABSENT: the build step's sed needs one character
# between the quotes, so a literal "" would hand back the whole line.
mf_new g1-vector-empty
sed -i -E '/^[[:space:]]*vector_(version|sha256)[[:space:]]*=/d' "$F_REPO/$FX_INFRA/vector.tf"
mf_commit 'vector off'
git -C "$F_REPO" tag -a vinngest-v1.1.41 -m r
git -C "$F_REPO" push -q origin refs/tags/vinngest-v1.1.41 2>/dev/null
mf_commit 'later docs'
run_mint g1-vector-empty --dry-run
expect 'g1.vector-empty-both' 0 noop 0 vinngest-v1.1.40,vinngest-v1.1.41
a_eq 'g1.vector-empty-both:base' "$(field base)" v1.1.41

# G1 row 4 — the staging prefix is renamed, so HEAD's extractor finds 0 carriers:
# fatal at decide, never "nothing changed".
mf_new g1-r4
fx_wf_sed 's#cp apps/web-platform/infra/#cp apps/web-platform/infra2/#'
mf_commit 'rename staging prefix'
run_mint g1-r4 --dry-run
expect 'g1.r4' 1 error 0 vinngest-v1.1.40
a_eq 'g1.r4:stage' "$(field stage)" decide
a_eq 'g1.r4:reason' "$(field reason)" no-carriers

# G1 row 5 — a `cp` from outside apps/web-platform/infra/ with its COPY: the
# extractor cannot see it, and the cardinality refusal must.
mf_new g1-r5
fx_wf_sed "/carrier-13.sh \"/a\\$(fxt outside_cp)"
fx_wf_sed '/COPY carrier-13.sh/a\          COPY outside.sh /outside.sh'
mf_commit 'stage a file from outside infra'
run_mint g1-r5 --dry-run
expect 'g1.r5' 1 error 0 vinngest-v1.1.40
a_eq 'g1.r5:stage' "$(field stage)" decide
a_eq 'g1.r5:reason' "$(field reason)" cardinality

# Same COUNTS but different FILES (a cp swapped for another name) — cardinality.
mf_new g1-swap
fx_wf_sed "$(fxt swap_sed)"
mf_commit 'swap a staged file'
run_mint g1-swap --dry-run
expect 'g1.name-swap' 1 error 0 vinngest-v1.1.40
a_eq 'g1.name-swap:reason' "$(field reason)" cardinality

# G1 row 6 — the recipe changes inside the heredoc.
mf_new g1-r6
fx_wf_sed 's/FROM alpine:3.20/FROM alpine:3.21/'
mf_commit 'alpine bump'
run_mint g1-r6 --dry-run
expect 'g1.r6' 0 would-mint 0 vinngest-v1.1.40
a_eq 'g1.r6:changed' "$(field changed)" recipe

# G1 row 7 — a bump-PR merge only moves cloud-init pins: must-PASS noop (no loop).
mf_new g1-r7
sed -i "s/v1.1.40@sha256:$HEX_D/v1.1.41@sha256:$HEX_C/" "$F_REPO/$FX_INFRA/cloud-init.yml"
mf_commit 'chore(infra): bump inngest-bootstrap pin'
run_mint g1-r7 --dry-run
expect 'g1.r7' 0 noop 0 vinngest-v1.1.40
a_eq 'g1.r7:reason' "$(field reason)" unchanged

# G1 row 8 — comment-only edits OUTSIDE the heredoc, including comments that say
# DOCKERFILE: exactly one block, noop.
mf_new g1-r8
fx_wf_sed '/cat > "\$BUILD_DIR\/Dockerfile" <<DOCKERFILE/i\          # The DOCKERFILE recipe below is baked verbatim.\n          # DOCKERFILE'
fx_wf_sed '1a\# a header comment naming DOCKERFILE'
mf_commit 'comment-only build workflow edit'
run_mint g1-r8 --dry-run
expect 'g1.r8' 0 noop 0 vinngest-v1.1.40
if grep -qF '# The DOCKERFILE recipe' "$F_REPO/$FX_WF"; then pass 'g1.r8:precondition-comment-landed'
else fail 'g1.r8:precondition-comment-landed' 'fixture broken: comment not inserted'; fi

# Two heredoc blocks on HEAD: fatal (exactly one is required).
mf_new g1-two-blocks
printf '%s\n' '      - name: second' '        run: |' \
  "$(fxt heredoc_open)" '          FROM scratch' '          DOCKERFILE' >> "$F_REPO/$FX_WF"
mf_commit 'second heredoc'
run_mint g1-two-blocks --dry-run
expect 'g1.two-blocks' 1 error 0 vinngest-v1.1.40
a_eq 'g1.two-blocks:reason' "$(field reason)" recipe-blocks

# An unterminated heredoc on HEAD: fatal.
mf_new g1-unterminated
fx_wf_sed '/^          DOCKERFILE$/d'
mf_commit 'unterminated heredoc'
run_mint g1-unterminated --dry-run
expect 'g1.unterminated' 1 error 0 vinngest-v1.1.40
a_eq 'g1.unterminated:reason' "$(field reason)" recipe-blocks

# inngest_cli_version empty on HEAD: fatal (the build would refuse it anyway).
mf_new g1-pin-empty
sed -i -E '/^[[:space:]]*inngest_cli_version[[:space:]]*=/d' "$F_REPO/$FX_INFRA/inngest.tf"
mf_commit 'empty pin'
run_mint g1-pin-empty --dry-run
expect 'g1.inngest-pin-empty' 1 error 0 vinngest-v1.1.40
a_eq 'g1.inngest-pin-empty:reason' "$(field reason)" pin-empty

# Flow (i) — a carrier ADDED (cp + COPY + file).
mf_new g1-added
fx_wf_sed "/carrier-13.sh \"/a\\$(fxt added_cp)"
fx_wf_sed '/COPY carrier-13.sh/a\          COPY carrier-14.sh /carrier-14.sh'
fx_carrier carrier-14.sh 'carrier-14 v1'
mf_commit 'add a carrier'
run_mint g1-added --dry-run
expect 'g1.carrier-added' 0 would-mint 0 vinngest-v1.1.40
a_eq 'g1.carrier-added:changed' "$(field changed)" 'carrier-set:carrier-14.sh,recipe'

# Flow (i) — a carrier REMOVED (cp + COPY gone; the file itself stays).
mf_new g1-removed
fx_wf_sed '/carrier-07.sh/d'
mf_commit 'remove a carrier'
run_mint g1-removed --dry-run
expect 'g1.carrier-removed' 0 would-mint 0 vinngest-v1.1.40
a_eq 'g1.carrier-removed:changed' "$(field changed)" 'carrier-set:carrier-07.sh,recipe'

# Flow (l) — a revert to OLDER content still mints, and above the newer tag.
mf_new g1-revert
fx_carrier carrier-05.sh 'carrier-05 v2'
mf_commit 'v2'
git -C "$F_REPO" tag -a vinngest-v1.1.41 -m r
git -C "$F_REPO" push -q origin refs/tags/vinngest-v1.1.41 2>/dev/null
printf '#!/bin/sh\necho carrier-05.sh v1\n' > "$F_REPO/$FX_INFRA/carrier-05.sh"
mf_commit 'revert to v1 content'
MINT_ENV=(MINT_TAG_TOKEN="$TAG_TOK")
run_mint g1-revert --tag
expect 'g1.revert' 0 tagged 2 vinngest-v1.1.40,vinngest-v1.1.41,vinngest-v1.1.42
a_eq 'g1.revert:base' "$(field base)" v1.1.41
a_annotated 'g1.revert' vinngest-v1.1.42

# No merged tag at all: would-mint reason=no-base, and it is not an error.
mf_new g1-no-base --no-tag
mf_commit 'later'
run_mint g1-no-base --dry-run
expect 'g1.no-base' 0 would-mint 0 ''
a_eq 'g1.no-base:reason' "$(field reason)" no-base
a_eq 'g1.no-base:base' "$(field base)" ''

# Harness must-PASS (non-canonical input): a carrier change plus an unrelated .tf
# edit in one commit yields exactly one tag.
mf_new g1-harness
fx_carrier carrier-02.sh 'carrier-02 v2'
printf '# unrelated\n' >> "$F_REPO/$FX_INFRA/other.tf"
printf '\n# unrelated comment\n' >> "$F_REPO/$FX_INFRA/inngest.tf"
mf_commit 'carrier + unrelated tf'
MINT_ENV=(MINT_TAG_TOKEN="$TAG_TOK")
run_mint g1-harness --tag
expect 'g1.harness-one-tag' 0 tagged 2 vinngest-v1.1.40,vinngest-v1.1.41
a_eq 'g1.harness-one-tag:changed' "$(field changed)" 'carrier:carrier-02.sh'

# --tag on an unchanged tree ends noop and POSTs nothing.
mf_new g1-tag-noop
mf_commit 'docs'
MINT_ENV=(MINT_TAG_TOKEN="$TAG_TOK")
run_mint g1-tag-noop --tag
expect 'g1.tag-noop' 0 noop 0 vinngest-v1.1.40

# ===========================================================================
echo "=== Guard 2: version allocation above every tag ==="
# ===========================================================================

# g2_changed_fixture <name> — a fixture with one carrier changed on main.
g2_changed_fixture() {
  mf_new "$1"
  fx_carrier carrier-03.sh "carrier-03 $1"
  mf_commit "change for $1"
}

# G2 row 1 — an off-main v1.1.50 present ONLY on the remote: NEXT v1.1.51, BASE
# stays the merged v1.1.40.
g2_changed_fixture g2-r1
side_tag_on_origin vinngest-v1.1.50 --annotate
if git -C "$F_REPO" rev-parse -q --verify refs/tags/vinngest-v1.1.50 >/dev/null; then
  fail 'g2.r1:precondition-remote-only' 'fixture broken: v1.1.50 is in the local clone'
else pass 'g2.r1:precondition-remote-only'; fi
MINT_ENV=(MINT_TAG_TOKEN="$TAG_TOK")
run_mint g2-r1 --tag
expect 'g2.r1' 0 tagged 2 vinngest-v1.1.40,vinngest-v1.1.50,vinngest-v1.1.51
a_eq 'g2.r1:tag' "$(field tag)" vinngest-v1.1.51
a_eq 'g2.r1:base' "$(field base)" v1.1.40
a_annotated 'g2.r1' vinngest-v1.1.51

# G2 row 3 — v1.9.0 and v1.10.0 both exist: version sort, not lexical.
g2_changed_fixture g2-r3
side_tag_on_origin vinngest-v1.9.0
side_tag_on_origin vinngest-v1.10.0
MINT_ENV=(MINT_TAG_TOKEN="$TAG_TOK")
run_mint g2-r3 --tag
a_eq 'g2.r3:rc' "$LAST_RC" 0
a_eq 'g2.r3:tag' "$(field tag)" vinngest-v1.10.1

# G2 row 4 / flow (m) — a suffixed tag above the merged max counts.
g2_changed_fixture g2-r4
side_tag_on_origin vinngest-v1.2.0-rc1 --annotate
MINT_ENV=(MINT_TAG_TOKEN="$TAG_TOK")
run_mint g2-r4 --tag
a_eq 'g2.r4:rc' "$LAST_RC" 0
a_eq 'g2.r4:tag' "$(field tag)" vinngest-v1.2.1

# A four-part suffix (`.4`) counts at its X.Y.Z prefix.
g2_changed_fixture g2-dot4
side_tag_on_origin vinngest-v1.1.60.4
MINT_ENV=(MINT_TAG_TOKEN="$TAG_TOK")
run_mint g2-dot4 --tag
a_eq 'g2.dot4:tag' "$(field tag)" vinngest-v1.1.61

# G2 row 6 / flow (d) — a human tag on HEAD present ONLY on the origin: the
# pre-create re-read ends noop reason=concurrent-tag with ZERO POSTs.
g2_changed_fixture g2-r6
git -C "$F_REPO" tag -a vinngest-v1.1.41 -m 'human' HEAD
git -C "$F_REPO" push -q origin refs/tags/vinngest-v1.1.41 2>/dev/null
git -C "$F_REPO" tag -d vinngest-v1.1.41 >/dev/null
MINT_ENV=(MINT_TAG_TOKEN="$TAG_TOK")
run_mint g2-r6 --tag
expect 'g2.r6' 0 noop 0 vinngest-v1.1.40,vinngest-v1.1.41
a_eq 'g2.r6:reason' "$(field reason)" concurrent-tag

# G2 row 8 — a 7-digit component on the remote: fatal allocate, zero POSTs.
g2_changed_fixture g2-r8
side_tag_on_origin vinngest-v1.1.9999999
MINT_ENV=(MINT_TAG_TOKEN="$TAG_TOK")
run_mint g2-r8 --tag
expect 'g2.r8' 1 error 0 vinngest-v1.1.40,vinngest-v1.1.9999999
a_eq 'g2.r8:stage' "$(field stage)" allocate

# G2 row 7 — 422 "Reference already exists" (a racer lands the name between the
# tag object and the ref): fatal tag, exactly one git/refs POST.
g2_changed_fixture g2-r7
MINT_ENV=(MINT_TAG_TOKEN="$TAG_TOK" MOCK_GH_RACE_REF=1)
run_mint g2-r7 --tag
a_eq 'g2.r7:rc' "$LAST_RC" 1
a_eq 'g2.r7:result' "$(field result)" error
a_eq 'g2.r7:stage' "$(field stage)" tag
a_eq 'g2.r7:reason' "$(field reason)" http-422
a_eq 'g2.r7:one-ref-post' "$(gh_calls_to 'git/refs')" 1
a_out_lacks 'g2.r7:no-raw-body' 'Reference already exists'

# 422 Object does not exist (a response whose sha is unknown): fatal tag.
g2_changed_fixture g2-badsha
MINT_ENV=(MINT_TAG_TOKEN="$TAG_TOK" MOCK_GH_TAG_WRONGSHA=1)
run_mint g2-badsha --tag
expect 'g2.bad-object' 1 error 2 vinngest-v1.1.40
a_eq 'g2.bad-object:stage' "$(field stage)" tag

# R1 — tag creation refused for the missing `workflows` permission: a distinct
# reason, zero ref POSTs, raw body bytes never printed.
g2_changed_fixture g2-wfperm
MINT_ENV=(MINT_TAG_TOKEN="$TAG_TOK" MOCK_GH_TAGS_FAIL=workflows)
run_mint g2-wfperm --tag
expect 'g2.workflows-permission' 1 error 1 vinngest-v1.1.40
a_eq 'g2.workflows-permission:reason' "$(field reason)" workflows-permission
a_eq 'g2.workflows-permission:stage' "$(field stage)" tag
a_out_lacks 'g2.workflows-permission:no-raw-body' 'refusing to allow'
# Negative control: a plain 422 is NOT classified as the workflows permission.
g2_changed_fixture g2-plain422
MINT_ENV=(MINT_TAG_TOKEN="$TAG_TOK" MOCK_GH_TAGS_FAIL=plain)
run_mint g2-plain422 --tag
a_eq 'g2.plain-422:reason' "$(field reason)" http-422

# ===========================================================================
echo "=== Flow rows: dispatch, ancestry, credentials, xtrace ==="
# ===========================================================================

# Dispatch success: exactly one POST, main-ref body, the DISPATCH token only.
g2_changed_fixture fl-dispatch
MINT_ENV=(MINT_TAG_TOKEN="$TAG_TOK")
run_mint fl-dispatch-tag --tag
MINT_ENV=(MINT_DISPATCH_TOKEN="$DSP_TOK")
run_mint fl-dispatch --dispatch vinngest-v1.1.41
a_eq 'fl.dispatch:rc' "$LAST_RC" 0
a_eq 'fl.dispatch:result' "$(field result)" dispatched
a_eq 'fl.dispatch:one-post' "$(gh_calls_to '/dispatches')" 1
a_eq 'fl.dispatch:body' "$(awk -F'\t' '$1 ~ /dispatches$/ {print $2}' "$MOCK_GH_BODIES")" \
  '{"ref":"main","inputs":{"ref":"vinngest-v1.1.41"}}'
a_eq 'fl.dispatch:token' "$(grep -c "/dispatches .*| token=$DSP_TOK |" "$MOCK_GH_LOG" || true)" 1
a_eq 'fl.dispatch:no-tag-token-on-dispatch' "$(grep '/dispatches' "$MOCK_GH_LOG" | grep -c "$TAG_TOK" || true)" 0

# Flow (e) — a failed dispatch: fatal, exactly ONE POST (no retry), the exact
# `gh workflow run` remediation, and the tag is never deleted.
g2_changed_fixture fl-dispatch-fail
MINT_ENV=(MINT_TAG_TOKEN="$TAG_TOK")
run_mint fl-dispatch-fail-tag --tag
MINT_ENV=(MINT_DISPATCH_TOKEN="$DSP_TOK" MOCK_GH_DISPATCH_FAIL=1)
run_mint fl-dispatch-fail --dispatch vinngest-v1.1.41
a_eq 'fl.dispatch-fail:rc' "$LAST_RC" 1
a_eq 'fl.dispatch-fail:result' "$(field result)" error
a_eq 'fl.dispatch-fail:stage' "$(field stage)" dispatch
a_eq 'fl.dispatch-fail:one-post' "$(gh_calls_to '/dispatches')" 1
a_out_has 'fl.dispatch-fail:remediation' 'gh workflow run build-inngest-bootstrap-image.yml --ref main -f ref=vinngest-v1.1.41'
a_eq 'fl.dispatch-fail:tag-kept' "$(origin_tags)" vinngest-v1.1.40,vinngest-v1.1.41
a_out_lacks 'fl.dispatch-fail:never-delete' 'git push origin :refs/tags'

# --dispatch with a tag that fails the strict regex: fatal, zero POSTs.
bi=0
for bad in vinngest-v1.1 'vinngest-v1.1.41;x' v1.1.41 'vinngest-v1.1.41-rc1'; do
  bi=$((bi+1))
  mf_new "fl-badtag-$bi"
  MINT_ENV=(MINT_DISPATCH_TOKEN="$DSP_TOK")
  run_mint "fl-badtag-$bi" --dispatch "$bad"
  a_eq "fl.dispatch-invalid[$bad]:rc" "$LAST_RC" 1
  a_eq "fl.dispatch-invalid[$bad]:stage" "$(field stage)" dispatch
  a_eq "fl.dispatch-invalid[$bad]:no-post" "$(gh_calls)" 0
done

# --dispatch with a tag that is NOT on origin/main: fatal, zero POSTs.
mf_new fl-offmain
side_tag_on_origin vinngest-v1.1.50 --annotate
git -C "$F_REPO" fetch -q origin
MINT_ENV=(MINT_DISPATCH_TOKEN="$DSP_TOK")
run_mint fl-offmain --dispatch vinngest-v1.1.50
expect 'fl.dispatch-off-main' 1 error 0 vinngest-v1.1.40,vinngest-v1.1.50
a_eq 'fl.dispatch-off-main:reason' "$(field reason)" off-main

# --dispatch with a tag absent from the origin: fatal, zero POSTs.
mf_new fl-absent
MINT_ENV=(MINT_DISPATCH_TOKEN="$DSP_TOK")
run_mint fl-absent --dispatch vinngest-v1.1.77
expect 'fl.dispatch-absent' 1 error 0 vinngest-v1.1.40
a_eq 'fl.dispatch-absent:reason' "$(field reason)" tag-not-found

# Credential isolation inside the script: each mode refuses the OTHER token and
# requires its own; nothing is POSTed on a refusal.
g2_changed_fixture fl-iso-tag
MINT_ENV=(MINT_TAG_TOKEN="$TAG_TOK" MINT_DISPATCH_TOKEN="$DSP_TOK")
run_mint fl-iso-tag --tag
expect 'fl.iso-tag-sees-dispatch' 1 error 0 vinngest-v1.1.40
a_eq 'fl.iso-tag-sees-dispatch:stage' "$(field stage)" args
MINT_ENV=(MINT_TAG_TOKEN="$TAG_TOK" MINT_DISPATCH_TOKEN="$DSP_TOK")
run_mint fl-iso-dsp --dispatch vinngest-v1.1.40
expect 'fl.iso-dispatch-sees-tag' 1 error 0 vinngest-v1.1.40
MINT_ENV=()
run_mint fl-no-tok --tag
expect 'fl.tag-needs-token' 1 error 0 vinngest-v1.1.40
run_mint fl-no-dsp-tok --dispatch vinngest-v1.1.40
expect 'fl.dispatch-needs-token' 1 error 0 vinngest-v1.1.40
run_mint fl-usage --bogus
expect 'fl.usage' 1 error 0 vinngest-v1.1.40
a_eq 'fl.usage:stage' "$(field stage)" args

# --dry-run makes NO network call: gh is forbidden and origin points at a
# nonexistent path, so a stray ls-remote fails the row too.
g2_changed_fixture fl-offline
git -C "$F_REPO" remote set-url origin "$TMP/fl-offline/does-not-exist.git"
MINT_ENV=(MOCK_GH_FORBID=1)
run_mint fl-offline --dry-run
a_eq 'fl.dry-run-offline:rc' "$LAST_RC" 0
a_eq 'fl.dry-run-offline:result' "$(field result)" would-mint
a_eq 'fl.dry-run-offline:no-gh' "$(gh_calls)" 0

# --dry-run on a NON-main HEAD (a feature branch) works: there is no
# "HEAD reachable from origin/main" check to break it.
mf_new fl-branch
git -C "$F_REPO" checkout -q -b feat-x
fx_carrier carrier-04.sh 'carrier-04 on a branch'
git -C "$F_REPO" add -A && git -C "$F_REPO" commit -qm 'branch change'
run_mint fl-branch --dry-run
a_eq 'fl.dry-run-branch:rc' "$LAST_RC" 0
a_eq 'fl.dry-run-branch:result' "$(field result)" would-mint

# Ancestry — a shallow checkout is refused before resolution.
mf_new fl-shallow
mf_commit 'second'
SHALLOW="$TMP/fl-shallow/shallow"
git clone -q --depth 1 "file://$F_REPO" "$SHALLOW" 2>/dev/null
F_REPO="$SHALLOW"
a_eq 'fl.shallow:precondition' "$(git -C "$F_REPO" rev-parse --is-shallow-repository)" true
run_mint fl-shallow --dry-run
a_eq 'fl.shallow:rc' "$LAST_RC" 1
a_eq 'fl.shallow:stage' "$(field stage)" ancestry
a_out_has 'fl.shallow:wording' 'is-shallow-repository='

# Ancestry — an unreadable mid-history object (the walk reports on stderr only).
mf_new fl-walk
mf_commit c2; c2=$(git -C "$F_REPO" rev-parse HEAD)
mf_commit c3
git -C "$F_REPO" tag -a vinngest-v1.1.41 -m r HEAD
rm -f "$F_REPO/.git/objects/${c2:0:2}/${c2:2}"
if git -C "$F_REPO" cat-file -e "$c2" 2>/dev/null; then fail 'fl.walk:precondition' 'fixture broken: c2 still readable'
else pass 'fl.walk:precondition'; fi
run_mint fl-walk --dry-run
a_eq 'fl.walk:rc' "$LAST_RC" 1
a_eq 'fl.walk:stage' "$(field stage)" ancestry
a_out_has 'fl.walk:wording' 'unreadable history'

# xtrace refusal: `bash -x` with either credential set exits 78 BEFORE any traced
# command, and the canary value never appears in any output.
g2_changed_fixture fl-xtrace
MINT_BASH=(-x)
MINT_ENV=(MINT_TAG_TOKEN="$TAG_TOK")
run_mint fl-xtrace --tag
a_eq 'fl.xtrace-tag:rc' "$LAST_RC" 78
a_eq 'fl.xtrace-tag:result' "$(field result)" error
a_out_lacks 'fl.xtrace-tag:canary-absent' "$TAG_TOK"
a_eq 'fl.xtrace-tag:no-post' "$(gh_calls)" 0
MINT_ENV=(MINT_DISPATCH_TOKEN="$DSP_TOK")
run_mint fl-xtrace-d --dispatch vinngest-v1.1.40
a_eq 'fl.xtrace-dispatch:rc' "$LAST_RC" 78
a_out_lacks 'fl.xtrace-dispatch:canary-absent' "$DSP_TOK"
MINT_BASH=()

# Debug channels are scrubbed: GIT_TRACE output never lands in stderr, and gh
# never sees GH_DEBUG/DEBUG (both can echo request headers).
g2_changed_fixture fl-trace-env
MINT_ENV=(MINT_TAG_TOKEN="$TAG_TOK" GIT_TRACE=1 GIT_CURL_VERBOSE=1 GH_DEBUG=api DEBUG=1)
run_mint fl-trace-env --tag
a_eq 'fl.trace-env:rc' "$LAST_RC" 0
a_eq 'fl.trace-env:result' "$(field result)" tagged
a_eq 'fl.trace-env:gh-debug-unset' "$(grep -c '| debug=[^ ]' "$MOCK_GH_LOG" || true)" 0
a_eq 'fl.trace-env:git-trace-silent' "$(grep -c 'trace: ' "$LAST_ERR" || true)" 0
a_out_lacks 'fl.trace-env:canary-absent' "$TAG_TOK"

# Annotation payloads are percent-encoded: a newline in operator input cannot
# forge a second workflow command.
mf_new fl-encode
MINT_ENV=(MINT_DISPATCH_TOKEN="$DSP_TOK")
run_mint fl-encode --dispatch $'bad\n::error::forged'
a_eq 'fl.annotation-encoded:rc' "$LAST_RC" 1
a_eq 'fl.annotation-encoded:stage' "$(field stage)" dispatch
a_eq 'fl.annotation-encoded' "$(grep -c '^::error::forged' "$LAST_ERR" || true)" 0

# ===========================================================================
echo "=== Guard 3: writer/checker parity and workflow credential shape ==="
# ===========================================================================

sel_slice() { # file start-regex — the 3-line selector block
  RE="$2" awk '$0 ~ ENVIRON["RE"] {on=1} on {print} on && /\|\| true\)[[:space:]]*$/ {exit}' "$1"
}
sel_count() { RE="$2" awk '$0 ~ ENVIRON["RE"] {n++} END {print n+0}' "$1"; }
SEL_M_RE='^BASE=\$\(git -C "\$REPO_DIR" tag '
SEL_B_RE='^TARGET=\$\(git -C "\$REPO_DIR" tag '

# g3_parity <mint> <bump> <guard-a> <build-wf> — prints `OK <id>` / `BAD <id> <msg>`.
# Every BAD names the authority, the copies that must change with it, and a diff.
g3_parity() {
  local mint="$1" bump="$2" ga="$3" bwf="$4" n sm sb pair a m la lm na nm pin pat
  n=$(sel_count "$mint" "$SEL_M_RE")
  if [[ "$n" == 1 ]]; then echo "OK sel-one-start"
  else echo "BAD sel-one-start $n selector start line(s) in $mint, expected 1. Authority: $bump (AC6-IDENTICAL PIPELINE); copies: $mint (BASE=), $ga (AC6 LATEST_TAG=)"; fi
  sm=$(sel_slice "$mint" "$SEL_M_RE" | sed -e 's/^BASE=/SEL=/' -e 's/^[[:space:]]*//')
  sb=$(sel_slice "$bump" "$SEL_B_RE" | sed -e 's/^TARGET=/SEL=/' -e 's/^[[:space:]]*//')
  if [[ -n "$sm" && "$(grep -c '' <<<"$sm")" == 3 && "$sm" == "$sb" ]]; then echo "OK sel-byte-equal"
  else echo "BAD sel-byte-equal the merged-tag selector differs from its authority $bump (keep all three copies identical: $bump, $mint, $ga AC6): $(diff <(printf '%s\n' "$sb") <(printf '%s\n' "$sm") | tr '\n' '|')"; fi
  for pair in GA_CP_PATHS:CP_PATHS GA_COPY_NAMES:COPY_NAMES GA_TOTAL_COPY:TOTAL_COPY; do
    a="${pair%%:*}"; m="${pair##*:}"
    na=$(grep -cE "^[[:space:]]*${a}=" "$ga" || true)
    nm=$(grep -cE "^[[:space:]]*${m}=" "$mint" || true)
    la=$(grep -E "^[[:space:]]*${a}=" "$ga" | sed -E -e 's/^[[:space:]]+//' -e "s/^${a}=/X=/" -e 's/"\$GA_WF"/"$F"/g')
    lm=$(grep -E "^[[:space:]]*${m}=" "$mint" | sed -E -e 's/^[[:space:]]+//' -e "s/^${m}=/X=/" -e 's/"\$WF"/"$F"/g')
    if [[ "$na" == 1 && "$nm" == 1 && -n "$la" && "$la" == "$lm" ]]; then echo "OK carrier-$m"
    else echo "BAD carrier-$m the carrier extractor ${m} (found $nm) differs from Guard A's ${a} (found $na). Authority: $ga (Guard A); copy: $mint. diff: $(diff <(printf '%s\n' "$la") <(printf '%s\n' "$lm") | tr '\n' '|')"; fi
  done
  for pin in inngest_cli_version inngest_cli_sha256 vector_version vector_sha256; do
    pat="grep -E '^\\s*${pin}\\s*='"
    na=$(grep -cF -- "$pat" "$bwf" || true)
    nm=$(grep -cF -- "$pat" "$mint" || true)
    la=$(grep -F -- "$pat" "$bwf" | sed -E -e 's/^[[:space:]]+//' -e 's/^[A-Za-z_]+=\$\(//' \
      -e 's#apps/web-platform/infra/inngest\.tf#INNGEST_TF#' -e 's#apps/web-platform/infra/vector\.tf#VECTOR_TF#')
    lm=$(grep -F -- "$pat" "$mint" | sed -E -e 's/^[[:space:]]+//' -e 's/^[A-Za-z_]+=\$\(//' \
      -e 's#"\$ITF"#INNGEST_TF#' -e 's#"\$VTF"#VECTOR_TF#')
    if [[ "$na" == 1 && "$nm" == 1 && -n "$la" && "$la" == "$lm" ]]; then echo "OK pin-$pin"
    else echo "BAD pin-$pin the ${pin} extraction (found $nm) differs from the build step's (found $na). Authority: $bwf (Read pinned inngest-cli + vector versions); copy: $mint. diff: $(diff <(printf '%s\n' "$la") <(printf '%s\n' "$lm") | tr '\n' '|')"; fi
  done
  # The heredoc start line the mint looks for exists exactly once in the build workflow.
  n=$(grep -cE '^[[:space:]]*cat > "\$BUILD_DIR/Dockerfile" <<DOCKERFILE[[:space:]]*$' "$bwf" || true)
  if [[ "$n" == 1 ]]; then echo "OK recipe-one-block"
  else echo "BAD recipe-one-block $n DOCKERFILE heredoc start line(s) in $bwf, expected 1 (the mint's decide stage refuses anything else)"; fi
}

cat > "$TMP/g3_wf.py" <<'PY'
import fnmatch, json, re, sys
import yaml
mint_wf, build_wf = sys.argv[1], sys.argv[2]
out = []
def ok(i, m=None): out.append("OK " + i)
def bad(i, m): out.append("BAD " + i + " " + m)
AUTH = " (authority: .github/workflows/mint-inngest-bootstrap-tag.yml; the script's credential contract lives in .github/scripts/mint-inngest-bootstrap-tag.sh)"
raw = open(mint_wf).read()
try:
    doc = yaml.safe_load(raw)
except Exception as e:  # noqa: BLE001
    print("BAD parse " + str(e).replace("\n", " ")); sys.exit(0)
on = doc.get("on", doc.get(True)) or {}
if not isinstance(on, dict):
    on = {k: None for k in (on if isinstance(on, list) else [on])}
push = on.get("push") or {}
paths = push.get("paths") or []
(ok if push.get("branches") == ["main"] else bad)("push-main", "on.push.branches must be [main]" + AUTH)
(ok if "workflow_dispatch" in on else bad)("dispatch-trigger", "on.workflow_dispatch missing" + AUTH)
srcs = []
for line in open(build_wf):
    mm = re.match(r'^\s*cp\s+(\S+)\s+"\$BUILD_DIR/', line)
    if mm: srcs.append(mm.group(1))
if not srcs: bad("paths-cover-carriers", "no cp staging line found in " + build_wf)
unc = [s for s in srcs if not any(fnmatch.fnmatchcase(s, g) for g in paths)]
(ok if srcs and not unc else bad)("paths-cover-carriers", "cp source(s) no paths: glob covers: %s (authority: %s cp lines; copy: mint paths:)" % (unc, build_wf))
for req in (".github/workflows/build-inngest-bootstrap-image.yml", ".github/workflows/mint-inngest-bootstrap-tag.yml",
            ".github/scripts/mint-inngest-bootstrap-tag.sh", "apps/web-platform/infra/inngest.tf", "apps/web-platform/infra/vector.tf"):
    (ok if any(fnmatch.fnmatchcase(req, g) for g in paths) else bad)("paths-" + req.rsplit("/", 1)[-1], req + " is not covered by on.push.paths" + AUTH)
(ok if doc.get("permissions") == {"contents": "read"} else bad)("top-permissions", "top-level permissions must be exactly contents: read" + AUTH)
jobs = doc.get("jobs") or {}
job = jobs.get("mint") or {}
(ok if len(jobs) == 1 and job else bad)("one-mint-job", "expected exactly one job named mint" + AUTH)
(ok if str(job.get("if", "")).strip() == "github.ref == 'refs/heads/main'" else bad)("job-if-main", "job if must be github.ref == 'refs/heads/main'" + AUTH)
(ok if job.get("permissions") == {"contents": "write"} else bad)("job-permissions", "job permissions must be exactly contents: write" + AUTH)
conc = job.get("concurrency") or doc.get("concurrency") or {}
(ok if conc.get("group") == "inngest-bootstrap-automint" and conc.get("cancel-in-progress") is False else bad)("concurrency", "concurrency must be inngest-bootstrap-automint, cancel-in-progress false" + AUTH)
steps = job.get("steps") or []
def find(pred):
    for i, s in enumerate(steps):
        if pred(s): return i, s
    return -1, {}
ci, co = find(lambda s: str(s.get("uses", "")).startswith("actions/checkout@"))
w = co.get("with") or {}
(ok if ci == 0 else bad)("checkout-first", "the first step must be actions/checkout" + AUTH)
(ok if w.get("ref") == "main" else bad)("checkout-ref-main", "checkout must be ref: main (the tip, not github.sha)" + AUTH)
(ok if w.get("fetch-depth") == 0 and w.get("fetch-tags") is True and w.get("persist-credentials") is False else bad)("checkout-history", "checkout needs fetch-depth 0, fetch-tags true, persist-credentials false" + AUTH)
di, dec = find(lambda s: s.get("id") == "decide")
(ok if di > 0 and "--dry-run" in str(dec.get("run", "")) and not dec.get("env") else bad)("decide-step", "the decide step runs --dry-run with no env" + AUTH)
ti, tag = find(lambda s: s.get("name") == "Create tag")
ai, app = find(lambda s: str(s.get("uses", "")).endswith("mint-soleur-ai-app-token"))
xi, dsp = find(lambda s: s.get("name") == "Dispatch build")
(ok if tag.get("env") == {"MINT_TAG_TOKEN": "${{ github.token }}"} else bad)("tag-env", "Create tag env must be exactly MINT_TAG_TOKEN: ${{ github.token }}" + AUTH)
(ok if "--tag" in str(tag.get("run", "")) and "would-mint" in str(tag.get("if", "")) and tag.get("id") == "tag" else bad)("tag-step", "Create tag (id tag) runs --tag only when decide says would-mint" + AUTH)
de = dsp.get("env") or {}
(ok if de.get("MINT_DISPATCH_TOKEN") == "${{ steps.app.outputs.token }}" and "MINT_TAG_TOKEN" not in de and app.get("id") == "app" else bad)("dispatch-env", "Dispatch build env must bind MINT_DISPATCH_TOKEN to steps.app.outputs.token and nothing to MINT_TAG_TOKEN" + AUTH)
(ok if "--dispatch" in str(dsp.get("run", "")) else bad)("dispatch-step", "Dispatch build runs --dispatch" + AUTH)
(ok if 0 < ti < ai < xi else bad)("step-order", "order must be Create tag, then the App mint, then Dispatch build (the App token exists only after the tag)" + AUTH)
aw = app.get("with") or {}
try: perms = json.loads(str(aw.get("permissions", "")))
except Exception: perms = None  # noqa: BLE001
(ok if perms == {"actions": "write"} and aw.get("repositories") == "soleur" and str(aw.get("installation-id")) == "122213433" else bad)("app-scope", "the App mint must be scoped to permissions {\"actions\":\"write\"} and repositories soleur" + AUTH)
for i, s in enumerate(steps):
    txt = yaml.safe_dump(s)
    if "MINT_TAG_TOKEN" in txt and i != ti: bad("tag-token-isolated", "step %d (%s) references MINT_TAG_TOKEN" % (i, s.get("name")) + AUTH)
    if "MINT_DISPATCH_TOKEN" in txt and i != xi: bad("dispatch-token-isolated", "step %d (%s) references MINT_DISPATCH_TOKEN" % (i, s.get("name")) + AUTH)
    if re.search(r"github\.token|secrets\.GITHUB_TOKEN", txt) and i != ti: bad("github-token-isolated", "step %d (%s) references the job GITHUB_TOKEN" % (i, s.get("name")) + AUTH)
    u = str(s.get("uses", ""))
    if u and not u.startswith("./") and not re.search(r"@[0-9a-f]{40}$", u): bad("sha-pinned", "step %d uses %s, not a 40-hex SHA pin" % (i, u))
if not any(o.startswith("BAD tag-token-isolated") for o in out): ok("tag-token-isolated")
if not any(o.startswith("BAD dispatch-token-isolated") for o in out): ok("dispatch-token-isolated")
if not any(o.startswith("BAD github-token-isolated") for o in out): ok("github-token-isolated")
if not any(o.startswith("BAD sha-pinned") for o in out): ok("sha-pinned")
(bad if re.search(r"secrets\.[A-Za-z0-9_]*PAT\b|\b[A-Z0-9_]*_PAT\b", raw) else ok)("no-pat", "a PAT-named secret is referenced (hr-github-app-auth-not-pat)")
si, sl = find(lambda s: str(s.get("if", "")).strip() == "failure()")
(ok if si > xi and sl.get("continue-on-error") is True else bad)("slack-on-failure", "a final if: failure() Slack step with continue-on-error: true" + AUTH)
(ok if tag.get("timeout-minutes") and dsp.get("timeout-minutes") else bad)("step-timeouts", "Create tag and Dispatch build carry step timeouts" + AUTH)
print("\n".join(out))
PY
g3_wf() { python3 "$TMP/g3_wf.py" "$1" "$2" 2>&1 || echo "BAD python-crashed"; }

report() { # report <prefix> — pass/fail each OK/BAD line on stdin; counts rows
  local line n=0
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    n=$((n+1))
    case "$line" in
      OK\ *)  pass "$1.${line#OK }" ;;
      BAD\ *) local rest="${line#BAD }"; fail "$1.${rest%% *}" "${rest#* }" ;;
      *)      fail "$1.unparsed" "$line" ;;
    esac
  done
  REPORTED=$n
}
report g3.parity < <(g3_parity "$SCRIPT" "$BUMP" "$CONSUMER" "$BUILD_WF")
a_eq 'g3.parity:row-count' "$REPORTED" 10
report g3.wf < <(g3_wf "$MINT_WF" "$BUILD_WF")
if (( REPORTED >= 30 )); then pass 'g3.wf:row-count'; else fail 'g3.wf:row-count' "only $REPORTED workflow-shape rows reported"; fi

# Guard 3 mutation rows: mutate a TEMP copy; RED = at least one BAD line.
MUTDIR="$TMP/g3mut"; mkdir -p "$MUTDIR"
g3_mut() { # g3_mut <id> <which: mint|ga|bwf|mwf> <python-replace-old> <new>
  local id="$1" which="$2" src dst out nbad
  case "$which" in
    mint) src="$SCRIPT" ;; ga) src="$CONSUMER" ;; bwf) src="$BUILD_WF" ;; mwf) src="$MINT_WF" ;;
  esac
  dst="$MUTDIR/$id.$(basename "$src")"
  if ! python3 - "$src" "$dst" "$3" "$4" <<'PY'
import sys
src, dst, old, new = sys.argv[1:5]
s = open(src).read()
if s.count(old) < 1: sys.exit(2)
open(dst, "w").write(s.replace(old, new, 1))
PY
  then fail "$id:landed" "mutation anchor not found in $src"; return; fi
  if cmp -s "$src" "$dst"; then fail "$id:landed" "mutation produced an identical file"; return; fi
  pass "$id:landed"
  local m="$SCRIPT" g="$CONSUMER" b="$BUILD_WF" w="$MINT_WF"
  case "$which" in mint) m="$dst" ;; ga) g="$dst" ;; bwf) b="$dst" ;; mwf) w="$dst" ;; esac
  out=$( { g3_parity "$m" "$BUMP" "$g" "$b"; g3_wf "$w" "$b"; } )
  # A crashed or unparsed checker is a broken INSTRUMENT, never a kill.
  if grep -qE '^BAD (python-crashed|parse)|^Traceback' <<<"$out"; then
    fail "$id:caught" "instrument broken: the workflow checker crashed on the mutant"; return
  fi
  nbad=$(grep -c '^BAD ' <<<"$out" || true)
  if (( nbad > 0 )); then pass "$id:caught [$(grep '^BAD ' <<<"$out" | awk '{print $2}' | paste -sd, -)]"
  else fail "$id:caught" "mutant SURVIVED: every Guard 3 row stayed OK"; fi
}
g3_mut g3.m1-sort 'mint' '  | sort -V | tail -1 || true)' '  | sort | tail -1 || true)'
g3_mut g3.m2-guarda-regex 'ga' "cp apps/web-platform/infra/[A-Za-z0-9._-]+ '" "cp apps/web-platform/infra/[A-Za-z0-9._]+ '"
g3_mut g3.m3-no-selector 'mint' "$(fxt sel_anchor)" "$(fxt sel_renamed)"
g3_mut g3.m4-uncovered-cp 'bwf' "$(fxt luks_cp)" "$(fxt outside_cp)"$'\n'"$(fxt luks_cp)"
g3_mut g3.m5-tag-token-from-app 'mwf' 'MINT_TAG_TOKEN: ${{ github.token }}' 'MINT_TAG_TOKEN: ${{ steps.app.outputs.token }}'
g3_mut g3.m6-pat 'mwf' 'MINT_TAG_TOKEN: ${{ github.token }}' 'MINT_TAG_TOKEN: ${{ secrets.RELEASE_PAT }}'
g3_mut g3.m7a-tag-step-sees-dispatch 'mwf' 'MINT_TAG_TOKEN: ${{ github.token }}' $'MINT_TAG_TOKEN: ${{ github.token }}\n          MINT_DISPATCH_TOKEN: ${{ steps.app.outputs.token }}'
g3_mut g3.m7b-dispatch-step-sees-tag 'mwf' 'MINT_DISPATCH_TOKEN: ${{ steps.app.outputs.token }}' $'MINT_DISPATCH_TOKEN: ${{ steps.app.outputs.token }}\n          MINT_TAG_TOKEN: ${{ github.token }}'
g3_mut g3.m8a-checkout-sha 'mwf' '          ref: main' '          ref: ${{ github.sha }}'
g3_mut g3.m8b-no-job-if 'mwf' "    if: github.ref == 'refs/heads/main'" '    # (job if removed)'
g3_mut g3.m9-pin-pattern 'mint' "grep -E '^\\s*vector_sha256\\s*=' \"\$VTF\"" "grep -E '^\\s*vector_sha256.*=' \"\$VTF\""
g3_mut g3.m10-unscoped-app 'mwf' "permissions: '{\"actions\":\"write\"}'" "permissions: ''"

# ===========================================================================
echo "=== Composite scope-down (mint-soleur-ai-app-token) ==="
# ===========================================================================
# The composite's `run:` block, executed under the runner's composite shell with
# `doppler` and `curl` shimmed and a real synthesized RSA key. Pins both arms:
# empty inputs send NO -d (byte-identical to the pre-#4326 call); set inputs send
# exactly the scoped JSON body.
CDIR="$TMP/composite"; CBIN="$CDIR/bin"; mkdir -p "$CBIN"
awk '/^      run: \|[[:space:]]*$/ {on=1; next} on' "$COMPOSITE" | sed 's/^        //' > "$CDIR/run.sh"
if grep -qF 'INSTALL_TOKEN=$(curl -sS -X POST \' "$CDIR/run.sh"; then pass 'comp:extracted'
else fail 'comp:extracted' "could not extract the composite run block from $COMPOSITE"; fi
openssl genrsa 2048 > "$CDIR/key.pem" 2>/dev/null
cat > "$CBIN/doppler" <<STUB
#!/usr/bin/env bash
case "\$*" in
  *GITHUB_APP_ID*) printf '12345' ;;
  *GITHUB_APP_PRIVATE_KEY*) cat "$CDIR/key.pem" ;;
  *) exit 1 ;;
esac
STUB
cat > "$CBIN/curl" <<'STUB'
#!/usr/bin/env bash
{ printf -- '--call--\n'; printf '%s\n' "$@"; } >> "${CURL_LOG:?unset}"
printf '{"token":"fixture-installation-credential"}'
STUB
chmod +x "$CBIN/doppler" "$CBIN/curl"
run_comp() { # run_comp <label> <permissions> <repositories>
  CLOG="$CDIR/$1.curl"; COUT="$CDIR/$1.out"; : > "$CLOG"; : > "$COUT"
  CRC=0
  env -u SCOPE_PERMISSIONS -u SCOPE_REPOSITORIES PATH="$CBIN:$PATH" CURL_LOG="$CLOG" \
    DOPPLER_TOKEN=fixture DOPPLER_PROJECT=soleur DOPPLER_CONFIG=prd_terraform INSTALLATION_ID=122213433 \
    SCOPE_PERMISSIONS="$2" SCOPE_REPOSITORIES="$3" RUNNER_TEMP="$CDIR" GITHUB_OUTPUT="$COUT" \
    bash --noprofile --norc -eo pipefail "$CDIR/run.sh" > "$CDIR/$1.stdout" 2>&1 || CRC=$?
}
# data_arg — the value following -d/--data* in the logged argv, or NONE.
data_arg() { awk 'f {print; exit} $0 ~ /^(-d|--data|--data-raw|--data-binary)$/ {f=1} END {if (!f) print "NONE"}' "$CLOG"; }
run_comp default '' ''
a_eq 'comp.default:rc' "$CRC" 0
a_eq 'comp.default:no-data' "$(data_arg)" NONE
a_eq 'comp.default:one-call' "$(grep -c -- '^--call--$' "$CLOG" || true)" 1
a_eq 'comp.default:token-out' "$(cat "$COUT")" 'token=fixture-installation-credential'
run_comp scoped '{"actions":"write"}' soleur
a_eq 'comp.scoped:rc' "$CRC" 0
a_eq 'comp.scoped:body' "$(data_arg)" '{"repositories":["soleur"],"permissions":{"actions":"write"}}'
run_comp repos-only '' 'soleur, other'
a_eq 'comp.repos-only:body' "$(data_arg)" '{"repositories":["soleur","other"]}'
run_comp bad-json 'not json' soleur
a_eq 'comp.bad-json:refused' "$( (( CRC != 0 )) && echo yes || echo "no (rc=$CRC)")" yes
a_eq 'comp.bad-json:no-call' "$(grep -c -- '^--call--$' "$CLOG" || true)" 0
run_comp non-object '["actions"]' soleur
a_eq 'comp.non-object:refused' "$( (( CRC != 0 )) && echo yes || echo "no (rc=$CRC)")" yes

# ===========================================================================
echo "=== Script-mutation battery (temp copies) ==="
# ===========================================================================
# Each row: the mutation must LAND inside its target function of a temp copy;
# the unmutated copy is the positive control (verdict 0); the mutant must produce
# verdict 1. Verdict 2 means the instrument, not the SUT, is broken.
PRISTINE="$TMP/pristine-mint.sh"
cp "$SCRIPT" "$PRISTINE"

# verdict helpers: 0 = behaviour correct, 1 = wrong, 2 = instrument broken.
v_classify() { # v_classify <want-result> <want-field-key> <want-field-value>
  [[ "$LAST_RC" == 0 || "$LAST_RC" == 1 ]] || return 2
  [[ "$(grep -c '^result=' "$LAST_OUT" || true)" == 1 ]] || return 2
  [[ "$(field result)" == "$1" && "$(field "$2")" == "$3" ]] && return 0
  return 1
}
chk_last_carrier() {
  mf_new "$1"; fx_carrier carrier-13.sh "v2 $1"; mf_commit c
  run_mint "$1" --dry-run; v_classify would-mint changed 'carrier:carrier-13.sh'
}
chk_remote_only() {
  mf_new "$1"; fx_carrier carrier-03.sh "v2 $1"; mf_commit c
  side_tag_on_origin vinngest-v1.1.50 --annotate
  MINT_ENV=(MINT_TAG_TOKEN="$TAG_TOK"); run_mint "$1" --tag; v_classify tagged tag vinngest-v1.1.51
}
chk_lexical() {
  mf_new "$1"; fx_carrier carrier-03.sh "v2 $1"; mf_commit c
  side_tag_on_origin vinngest-v1.9.0; side_tag_on_origin vinngest-v1.10.0
  MINT_ENV=(MINT_TAG_TOKEN="$TAG_TOK"); run_mint "$1" --tag; v_classify tagged tag vinngest-v1.10.1
}
chk_suffix_annotated() {
  mf_new "$1"; fx_carrier carrier-03.sh "v2 $1"; mf_commit c
  side_tag_on_origin vinngest-v1.2.0-rc1 --annotate
  MINT_ENV=(MINT_TAG_TOKEN="$TAG_TOK"); run_mint "$1" --tag; v_classify tagged tag vinngest-v1.2.1
}
chk_concurrent() {
  mf_new "$1"; fx_carrier carrier-03.sh "v2 $1"; mf_commit c
  git -C "$F_REPO" tag -a vinngest-v1.1.41 -m human HEAD
  git -C "$F_REPO" push -q origin refs/tags/vinngest-v1.1.41 2>/dev/null
  git -C "$F_REPO" tag -d vinngest-v1.1.41 >/dev/null
  MINT_ENV=(MINT_TAG_TOKEN="$TAG_TOK"); run_mint "$1" --tag
  local rc=0; v_classify noop reason concurrent-tag || rc=$?
  (( rc == 0 )) && [[ "$(gh_calls)" != 0 ]] && rc=1   # zero POSTs is part of the property
  return "$rc"
}

# mut_row <id> <function> <old> <new> <check> [equivalent]
mut_row() {
  local id="$1" fn="$2" old="$3" new="$4" chk="$5" equiv="${6:-}" dst="$MUTDIR/$1.sh" rc
  if ! python3 - "$PRISTINE" "$dst" "$fn" "$old" "$new" <<'PY'
import re, sys
src, dst, fn, old, new = sys.argv[1:6]
s = open(src).read()
m = re.search(r"(?m)^" + re.escape(fn) + r"\(\) \{\n(.*?)^\}\n", s, re.S)
if not m: sys.exit(2)
body = m.group(1)
if body.count(old) != 1 or s.count(old) != 1: sys.exit(3)
s2 = s[:m.start(1)] + body.replace(old, new) + s[m.end(1):]
open(dst, "w").write(s2)
PY
  then fail "$id:landed" "mutation did not land inside $fn() exactly once"; return; fi
  cmp -s "$PRISTINE" "$dst" && { fail "$id:landed" "mutant identical to pristine"; return; }
  pass "$id:landed"
  SUT_OVERRIDE="$PRISTINE"; rc=0; "$chk" "$id-control" || rc=$?; unset SUT_OVERRIDE
  a_eq "$id:control-green" "$rc" 0
  SUT_OVERRIDE="$dst"; rc=0; "$chk" "$id-mutant" || rc=$?; unset SUT_OVERRIDE
  if [[ -n "$equiv" ]]; then
    # An EQUIVALENT mutant, labelled: no verdict changes. If it ever starts being
    # caught, the construct became load-bearing and this label must be revisited.
    a_eq "$id:equivalent-survives" "$rc" 0
    return
  fi
  case "$rc" in
    1) pass "$id:caught" ;;
    0) fail "$id:caught" "mutant SURVIVED" ;;
    *) fail "$id:caught" "instrument broken (verdict rc=$rc)" ;;
  esac
}
mut_row m.g1-hollow-comparator cmp_inputs \
  "if [[ -n \"\$1\" && \"\$1\" == \"\$2\" ]]; then printf 'same'; else printf 'differs'; fi" \
  "printf 'same'" chk_last_carrier
mut_row m.g2-local-tag-list list_remote_tags \
  "git -C \"\$REPO_DIR\" ls-remote --tags origin 'refs/tags/vinngest-v*'" \
  "git -C \"\$REPO_DIR\" for-each-ref --format='%(objectname) %(refname)' 'refs/tags/vinngest-v*'" chk_remote_only
mut_row m.g2-lexical-sort stage_allocate '| sort -V | tail -1)' '| sort | tail -1)' chk_lexical
mut_row m.g2-peel-strip stage_allocate "grep -v '\\^{}\$'" "cat" chk_suffix_annotated equivalent
mut_row m.g2-reorder-reread stage_tag \
  $'  precreate_reread     # step: re-read\n  post_tag_object      # step: tag object\n  post_tag_ref         # step: ref\n' \
  $'  post_tag_object      # step: tag object\n  post_tag_ref         # step: ref\n  precreate_reread     # step: re-read\n' chk_concurrent

cmp -s "$SCRIPT" "$PRISTINE" && pass 'm.sut-untouched' || fail 'm.sut-untouched' "the real script was modified by the battery"

# ---------------------------------------------------------------------------
echo ""
TOTAL=$((PASS + FAIL))
if (( TOTAL < MIN_ASSERTIONS )); then
  printf 'FAIL [anti-vacuity]: only %s assertions ran (floor %s) - the suite itself has been weakened.\n' "$TOTAL" "$MIN_ASSERTIONS"
  exit 1
fi
echo "Results: $PASS pass, $FAIL fail ($TOTAL assertions, floor $MIN_ASSERTIONS)"
[[ "$FAIL" -eq 0 ]]
