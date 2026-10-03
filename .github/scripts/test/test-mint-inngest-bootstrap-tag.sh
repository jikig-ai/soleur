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
#   - DELETE installation/token (the post-dispatch revoke, no --input) prints
#     nothing and exits 0 (a 204); MOCK_GH_REVOKE_FAIL=1 makes it a 401.
#   - row knobs: MOCK_GH_TAG_MISMATCH (a git/tags response naming another tag),
#     MOCK_GH_REF_ELSEWHERE (git/refs points the ref at main~1, not the posted
#     object), MOCK_GH_REF_BREAK_ORIGIN (git/refs lands, then the origin becomes
#     unreachable, so the verify ls-remote fails), MOCK_GH_REF_HANG (git/refs
#     lands, then the call hangs until the row's timeout kills the SUT).
#   - an error exits 1 with the body on stdout and `gh: … (HTTP 422)` on stderr, as
#     real `gh` does. The `workflows`-permission text is SYNTHESIZED (GitHub's exact
#     wording is unverified): its row tests the classifier on this wording, and a
#     plain-422 negative control proves the class is not assigned to every 422.
#   - anything else (another subcommand, a GET, a missing `--input -` on a POST,
#     an unmodelled path) exits 64.
#
# GUARD CONTRACT (plan §Guard Contract). Guard 1 = the image-input decision,
# Guard 2 = version allocation, Guard 3 = writer/checker parity and the
# workflow's credential shape. Script-mutation rows edit a TEMP COPY, prove the
# edit landed inside the target function, run the unmutated copy as a positive
# control, and count only rc 1 as caught (rc 2 is a broken instrument).
set -uo pipefail
# LC_ALL=C here also reaches the SUT, so deleting the script's own
# `export LC_ALL=C` is an EQUIVALENT mutant in this suite (S8). That is accepted:
# every comparison the script makes sorts BOTH sides in the one process and
# locale, so ordering cannot flip a verdict, and the ASCII-only ranges it greps
# with ([A-Za-z0-9._-]) meet no non-ASCII name in any fixture or in the real tree.
# The script keeps the export for the runner, whose locale is not pinned.
export LC_ALL=C
export TMPDIR="${TMPDIR:-/var/tmp}"

REPO_ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
SCRIPT="$REPO_ROOT/.github/scripts/mint-inngest-bootstrap-tag.sh"
BUMP="$REPO_ROOT/.github/scripts/bump-inngest-bootstrap-pin.sh"
BUILD_WF="$REPO_ROOT/.github/workflows/build-inngest-bootstrap-image.yml"
MINT_WF="$REPO_ROOT/.github/workflows/mint-inngest-bootstrap-tag.yml"
CONSUMER="$REPO_ROOT/apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh"
COMPOSITE="$REPO_ROOT/.github/actions/mint-infra-app-token/action.yml"
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
MIN_ASSERTIONS=662   # anti-vacuity floor = the green run's exact count; raise when adding rows, never lower it silently

pass() { echo "PASS [$1]"; PASS=$((PASS+1)); }
fail() { echo "FAIL [$1]: $2"; FAIL=$((FAIL+1)); }
# (The instrument self-test runs below, once every verdict helper is defined.)

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
# The post-dispatch revoke: DELETE /installation/token, no body (a 204).
if [[ "$method" == DELETE && "$path" == installation/token && -z "$input" ]]; then
  if [[ "${MOCK_GH_REVOKE_FAIL:-0}" == 1 ]]; then
    jq -n '{message: "Bad credentials", status: "401"}'
    printf 'gh: Bad credentials (HTTP 401)\n' >&2
    exit 1
  fi
  exit 0
fi
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
    [[ "${MOCK_GH_TAG_MISMATCH:-0}" == 1 ]] && tag=vinngest-v9.9.9
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
    target="$sha"
    [[ "${MOCK_GH_REF_ELSEWHERE:-0}" == 1 ]] && target=$(git -C "$O" rev-parse refs/heads/main~1)
    git -C "$O" update-ref "$ref" "$target" || err422 'Invalid request: update-ref'
    # The ref landed; now the origin goes away, so the next ls-remote fails.
    [[ "${MOCK_GH_REF_BREAK_ORIGIN:-0}" == 1 ]] && mv "$O" "$O.unreachable"
    # The ref landed and the response never arrives: a hang the step timeout kills.
    [[ "${MOCK_GH_REF_HANG:-0}" == 1 ]] && sleep 8
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
  MINT_BASH=() MINT_WRAP=()
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

# side_tag_on_origin <tag> [--annotate] [--keep-local] — a tag on a side commit
# that is never merged into main. It exists ONLY on the bare origin unless
# --keep-local also leaves it in the local clone.
side_tag_on_origin() {
  local tag="$1" s keep=0
  [[ " $* " == *" --keep-local "* ]] && keep=1
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
  (( keep )) || git -C "$F_REPO" tag -d "$tag" >/dev/null
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
    ${MINT_WRAP[@]+"${MINT_WRAP[@]}"} bash ${MINT_BASH[@]+"${MINT_BASH[@]}"} "$SUT" "$@" > "$LAST_OUT" 2> "$LAST_ERR" || LAST_RC=$?
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
gout_has() { # gout_has <id> <line> — GITHUB_OUTPUT carries exactly this line
  if grep -qxF -- "$2" "$LAST_GOUT"; then pass "$1"; else fail "$1" "GITHUB_OUTPUT lacks line: $2 (has: $(paste -sd' ' "$LAST_GOUT"))"; fi
}

# ---------------------------------------------------------------------------
# Instrument self-test. Every verdict helper must move the counters in BOTH
# directions (a helper that always passes, or never counts, would make every row
# below unobservable), and field() must return a single value or a marker. A
# failure is reported with printf + exit 2, never through the helpers under test;
# the counters are unwound afterwards, so no self-test verdict reaches the total.
# ---------------------------------------------------------------------------
st_p0=$PASS st_f0=$FAIL st_mp=$PASS st_mf=$FAIL
st_die() { printf 'FATAL [selftest:%s]: %s\n' "$1" "$2"; exit 2; }
st_moved() { # st_moved <label> <want-pass-delta> <want-fail-delta> — since the last mark
  local dp=$((PASS - st_mp)) df=$((FAIL - st_mf))
  (( dp == $2 && df == $3 )) || st_die "$1" "counters moved +${dp}/+${df}, want +$2/+$3"
  st_mp=$PASS st_mf=$FAIL
}
LAST_OUT="$TMP/selftest.out"; LAST_ERR="$TMP/selftest.err"; LAST_GOUT="$TMP/selftest.gout"
printf 'result=selftest-value\n' > "$LAST_OUT"
printf 'selftest-stderr-canary\n' > "$LAST_ERR"
printf 'tag_state=unknown\n' > "$LAST_GOUT"
pass st >/dev/null;                          st_moved pass 1 0
fail st x >/dev/null;                        st_moved fail 0 1
a_eq st same same >/dev/null;                st_moved a_eq-equal 1 0
a_eq st got want >/dev/null;                 st_moved a_eq-differ 0 1
a_out_has st selftest-stderr-canary >/dev/null; st_moved a_out_has-present 1 0
a_out_has st absent-canary >/dev/null;       st_moved a_out_has-absent 0 1
a_out_lacks st absent-canary >/dev/null;     st_moved a_out_lacks-absent 1 0
a_out_lacks st selftest-stderr-canary >/dev/null; st_moved a_out_lacks-present 0 1
gout_has st tag_state=unknown >/dev/null;    st_moved gout_has-present 1 0
gout_has st tag_state=created >/dev/null;    st_moved gout_has-absent 0 1
report st < <(printf 'OK a\nBAD b why\n') >/dev/null; st_moved report-ok-bad 1 1
(( REPORTED == 2 )) || st_die report-count "REPORTED=${REPORTED}, want 2"
report st < <(printf 'neither ok nor bad\n') >/dev/null; st_moved report-unparsed 0 1
[[ "$(field result)" == selftest-value ]] || st_die field-single "field result gave '$(field result)'"
printf 'result=a\nresult=b\n' > "$LAST_OUT"
[[ "$(field result)" == '<2 result= lines>' ]] || st_die field-duplicate "field result gave '$(field result)'"
[[ "$(field absent)" == '<0 absent= lines>' ]] || st_die field-missing "field absent gave '$(field absent)'"
PASS=$st_p0 FAIL=$st_f0
unset LAST_OUT LAST_ERR LAST_GOUT REPORTED

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
# The provisional tag_state=unknown (written before the ref POST) is followed
# by created, and the last value wins.
a_eq 'g1.r1-tag:gout' "$(paste -sd' ' "$LAST_GOUT")" 'tag=vinngest-v1.1.41 tag_state=unknown tag=vinngest-v1.1.41 tag_state=created result=tagged'
a_eq 'g1.r1-tag:tag-state' "$(field tag_state)" created
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
a_eq 'g1.r5:reason' "$(field reason)" cardinality-count
# The error prints both name sets, so the drift is readable from the log.
a_out_has 'g1.r5:names-staged' 'staged (cp): {carrier-01.sh,'
a_out_has 'g1.r5:names-baked' 'outside.sh}'

# Same COUNTS but different FILES (a cp swapped for another name) — cardinality.
mf_new g1-swap
fx_wf_sed "$(fxt swap_sed)"
mf_commit 'swap a staged file'
run_mint g1-swap --dry-run
expect 'g1.name-swap' 1 error 0 vinngest-v1.1.40
a_eq 'g1.name-swap:reason' "$(field reason)" cardinality-names
a_out_has 'g1.name-swap:names-staged' 'carrier-12.sh,other.tf}'
a_out_has 'g1.name-swap:names-baked' 'carrier-12.sh,carrier-13.sh}'

# A COPY line the strict parser cannot read (three operands): its own reason.
mf_new g1-copy-unparsed
fx_wf_sed 's#COPY carrier-13.sh /carrier-13.sh#COPY carrier-13.sh extra /carrier-13.sh#'
mf_commit 'unparseable COPY'
run_mint g1-copy-unparsed --dry-run
expect 'g1.copy-unparsed' 1 error 0 vinngest-v1.1.40
a_eq 'g1.copy-unparsed:reason' "$(field reason)" copy-unparsed

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
a_out_has 'g1.unterminated:wording' 'an unterminated DOCKERFILE heredoc block'
a_out_lacks 'g1.unterminated:no-bad-count' 'carries bad '

# inngest_cli_version empty on HEAD: fatal (the build would refuse it anyway).
mf_new g1-pin-empty
sed -i -E '/^[[:space:]]*inngest_cli_version[[:space:]]*=/d' "$F_REPO/$FX_INFRA/inngest.tf"
mf_commit 'empty pin'
run_mint g1-pin-empty --dry-run
expect 'g1.inngest-pin-empty' 1 error 0 vinngest-v1.1.40
a_eq 'g1.inngest-pin-empty:reason' "$(field reason)" pin-empty

# S9 twin: inngest_cli_sha256 empty on HEAD is refused the same way.
mf_new g1-sha-empty
sed -i -E '/^[[:space:]]*inngest_cli_sha256[[:space:]]*=/d' "$F_REPO/$FX_INFRA/inngest.tf"
mf_commit 'empty sha pin'
run_mint g1-sha-empty --dry-run
expect 'g1.inngest-sha-empty' 1 error 0 vinngest-v1.1.40
a_eq 'g1.inngest-sha-empty:reason' "$(field reason)" pin-empty

# A chmod-only carrier change: COPY keeps the mode, so it is an image change.
mf_new g1-chmod
chmod +x "$F_REPO/$FX_INFRA/carrier-06.sh"
mf_commit 'chmod a carrier'
a_eq 'g1.chmod:precondition-mode' "$(git -C "$F_REPO" ls-tree HEAD -- "$FX_INFRA/carrier-06.sh" | awk '{print $1}')" 100755
run_mint g1-chmod --dry-run
expect 'g1.chmod-only' 0 would-mint 0 vinngest-v1.1.40
a_eq 'g1.chmod-only:changed' "$(field changed)" 'carrier:carrier-06.sh'

# S1 anchor: tag the base, change a carrier, then a docs-only commit on top. The
# decision still sees the carrier change, and the tag lands on the TIP.
mf_new g1-anchor
fx_carrier carrier-09.sh 'carrier-09 v2'
mf_commit 'change a carrier'
mf_commit 'docs only, on top'
run_mint g1-anchor --dry-run
expect 'g1.anchor' 0 would-mint 0 vinngest-v1.1.40
a_eq 'g1.anchor:changed' "$(field changed)" 'carrier:carrier-09.sh'
MINT_ENV=(MINT_TAG_TOKEN="$TAG_TOK")
run_mint g1-anchor-tag --tag
expect 'g1.anchor-tag' 0 tagged 2 vinngest-v1.1.40,vinngest-v1.1.41
a_annotated 'g1.anchor-tag' vinngest-v1.1.41

# S2 twin: a LOCAL-only suffixed tag on HEAD plus a carrier change. The suffixed
# name is neither a merged base (the selector wants X.Y.Z) nor a head-tagged
# noop (strict names only), and allocation reads the remote, so the intended
# outcome is a normal mint of v1.1.41 on HEAD.
mf_new g1-local-rc
fx_carrier carrier-08.sh 'carrier-08 v2'
mf_commit 'change a carrier'
git -C "$F_REPO" tag -a vinngest-v1.1.41-rc1 -m rc HEAD
run_mint g1-local-rc --dry-run
expect 'g1.local-rc' 0 would-mint 0 vinngest-v1.1.40
a_eq 'g1.local-rc:base' "$(field base)" v1.1.40
a_eq 'g1.local-rc:changed' "$(field changed)" 'carrier:carrier-08.sh'
MINT_ENV=(MINT_TAG_TOKEN="$TAG_TOK")
run_mint g1-local-rc-tag --tag
expect 'g1.local-rc-tag' 0 tagged 2 vinngest-v1.1.40,vinngest-v1.1.41

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

# S10 twin — the same off-main v1.1.50, but ALSO in the local clone: BASE is
# still the merged v1.1.40 (--merged HEAD excludes it), NEXT is v1.1.51.
g2_changed_fixture g2-r1-local
side_tag_on_origin vinngest-v1.1.50 --annotate --keep-local
a_eq 'g2.r1-local:precondition-local' "$(git -C "$F_REPO" rev-parse -q --verify refs/tags/vinngest-v1.1.50 >/dev/null && echo yes)" yes
MINT_ENV=(MINT_TAG_TOKEN="$TAG_TOK")
run_mint g2-r1-local --tag
expect 'g2.r1-local' 0 tagged 2 vinngest-v1.1.40,vinngest-v1.1.50,vinngest-v1.1.51
a_eq 'g2.r1-local:base' "$(field base)" v1.1.40

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

# S3 twin — the same, but the human tag is LIGHTWEIGHT (no ^{} line): the re-read
# must fall back to the direct line and still end noop with zero POSTs.
g2_changed_fixture g2-r6-light
git -C "$F_REPO" push -q origin HEAD:refs/tags/vinngest-v1.1.41 2>/dev/null
a_eq 'g2.r6-light:precondition-lightweight' "$(git -C "$F_ORIGIN" cat-file -t refs/tags/vinngest-v1.1.41)" commit
MINT_ENV=(MINT_TAG_TOKEN="$TAG_TOK")
run_mint g2-r6-light --tag
expect 'g2.r6-light' 0 noop 0 vinngest-v1.1.40,vinngest-v1.1.41
a_eq 'g2.r6-light:reason' "$(field reason)" concurrent-tag

# S4 twin — a SUFFIXED tag on HEAD, only on the origin: not a strict name, so
# not a concurrent mint. It still counts for allocation (1.1.41 -> 1.1.42).
g2_changed_fixture g2-r6-rc
git -C "$F_REPO" tag -a vinngest-v1.1.41-rc1 -m rc HEAD
git -C "$F_REPO" push -q origin refs/tags/vinngest-v1.1.41-rc1 2>/dev/null
git -C "$F_REPO" tag -d vinngest-v1.1.41-rc1 >/dev/null
MINT_ENV=(MINT_TAG_TOKEN="$TAG_TOK")
run_mint g2-r6-rc --tag
expect 'g2.r6-rc' 0 tagged 2 vinngest-v1.1.40,vinngest-v1.1.41-rc1,vinngest-v1.1.42
a_annotated 'g2.r6-rc' vinngest-v1.1.42

# G2 row 8 — a 7-digit component on the remote: fatal allocate, zero POSTs.
g2_changed_fixture g2-r8
side_tag_on_origin vinngest-v1.1.9999999
MINT_ENV=(MINT_TAG_TOKEN="$TAG_TOK")
run_mint g2-r8 --tag
expect 'g2.r8' 1 error 0 vinngest-v1.1.40,vinngest-v1.1.9999999
a_eq 'g2.r8:stage' "$(field stage)" allocate
a_eq 'g2.r8:reason' "$(field reason)" oversized-version

# S5 twins — a 7-digit MAJOR, then MINOR, component is refused the same way.
for big in vinngest-v1234567.1.1 vinngest-v1.1234567.1; do
  g2_changed_fixture "g2-r8-$big"
  side_tag_on_origin "$big"
  MINT_ENV=(MINT_TAG_TOKEN="$TAG_TOK")
  run_mint "g2-r8-$big" --tag
  a_eq "g2.r8[$big]:rc" "$LAST_RC" 1
  a_eq "g2.r8[$big]:reason" "$(field reason)" oversized-version
  a_eq "g2.r8[$big]:no-post" "$(gh_calls)" 0
done

# A zero-padded component names the same number as its unpadded twin: refused.
for padded in vinngest-v1.01.1 vinngest-v1.1.041; do
  g2_changed_fixture "g2-pad-$padded"
  side_tag_on_origin "$padded"
  MINT_ENV=(MINT_TAG_TOKEN="$TAG_TOK")
  run_mint "g2-pad-$padded" --tag
  a_eq "g2.leading-zero[$padded]:rc" "$LAST_RC" 1
  a_eq "g2.leading-zero[$padded]:stage" "$(field stage)" allocate
  a_eq "g2.leading-zero[$padded]:reason" "$(field reason)" leading-zero-version
  a_eq "g2.leading-zero[$padded]:no-post" "$(gh_calls)" 0
done

# allocate's ls-remote failing (origin unreachable) is its own fatal, not
# "no remote tags".
g2_changed_fixture g2-lsr-fail
git -C "$F_REPO" remote set-url origin "$TMP/g2-lsr-fail/does-not-exist.git"
MINT_ENV=(MINT_TAG_TOKEN="$TAG_TOK")
run_mint g2-lsr-fail --tag
a_eq 'g2.allocate-ls-remote-failed:rc' "$LAST_RC" 1
a_eq 'g2.allocate-ls-remote-failed:stage' "$(field stage)" allocate
a_eq 'g2.allocate-ls-remote-failed:reason' "$(field reason)" ls-remote-failed
a_eq 'g2.allocate-ls-remote-failed:no-post' "$(gh_calls)" 0

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
# The ref POST was attempted, so the tag MAY exist: the name survives the error.
gout_has 'g2.r7:gout-tag' tag=vinngest-v1.1.41
gout_has 'g2.r7:gout-tag-state' tag_state=unknown
a_eq 'g2.r7:tag-state' "$(field tag_state)" unknown

# S6 — the ref lands on something other than the posted tag object (main~1):
# verify refuses, and the name survives with tag_state=unknown.
g2_changed_fixture g2-ref-elsewhere
MINT_ENV=(MINT_TAG_TOKEN="$TAG_TOK" MOCK_GH_REF_ELSEWHERE=1)
run_mint g2-ref-elsewhere --tag
a_eq 'g2.ref-elsewhere:rc' "$LAST_RC" 1
a_eq 'g2.ref-elsewhere:stage' "$(field stage)" tag
a_eq 'g2.ref-elsewhere:reason' "$(field reason)" verify-failed
gout_has 'g2.ref-elsewhere:gout-tag' tag=vinngest-v1.1.41
gout_has 'g2.ref-elsewhere:gout-tag-state' tag_state=unknown
gout_has 'g2.ref-elsewhere:gout-result' result=error

# Verify's ls-remote fails after the ref landed: ls-remote-failed, never
# tag-not-found, and the name still survives.
g2_changed_fixture g2-verify-lsr
MINT_ENV=(MINT_TAG_TOKEN="$TAG_TOK" MOCK_GH_REF_BREAK_ORIGIN=1)
run_mint g2-verify-lsr --tag
[[ -d "$F_ORIGIN.unreachable" ]] && mv "$F_ORIGIN.unreachable" "$F_ORIGIN"
a_eq 'g2.verify-ls-remote-failed:rc' "$LAST_RC" 1
a_eq 'g2.verify-ls-remote-failed:stage' "$(field stage)" tag
a_eq 'g2.verify-ls-remote-failed:reason' "$(field reason)" ls-remote-failed
gout_has 'g2.verify-ls-remote-failed:gout-tag-state' tag_state=unknown
a_eq 'g2.verify-ls-remote-failed:origin-tags' "$(origin_tags)" vinngest-v1.1.40,vinngest-v1.1.41

# A hang after the ref landed: the step timeout SIGKILLs the script before die
# or finish runs. The name was recorded before the POST, so GITHUB_OUTPUT still
# names it with tag_state=unknown and no result line (the Slack "MAY exist" branch).
g2_changed_fixture g2-ref-hang
MINT_ENV=(MINT_TAG_TOKEN="$TAG_TOK" MOCK_GH_REF_HANG=1)
MINT_WRAP=(timeout -s KILL 3)
run_mint g2-ref-hang --tag
MINT_WRAP=()
a_eq 'g2.ref-hang:rc' "$LAST_RC" 137
a_eq 'g2.ref-hang:gout' "$(paste -sd' ' "$LAST_GOUT")" 'tag=vinngest-v1.1.41 tag_state=unknown'
a_eq 'g2.ref-hang:origin-tags' "$(origin_tags)" vinngest-v1.1.40,vinngest-v1.1.41

# S7 — a git/tags response describing ANOTHER tag: bad-response, no ref POST,
# and no tag_state (nothing can exist yet).
g2_changed_fixture g2-tag-mismatch
MINT_ENV=(MINT_TAG_TOKEN="$TAG_TOK" MOCK_GH_TAG_MISMATCH=1)
run_mint g2-tag-mismatch --tag
expect 'g2.tag-mismatch' 1 error 1 vinngest-v1.1.40
a_eq 'g2.tag-mismatch:reason' "$(field reason)" bad-response
a_eq 'g2.tag-mismatch:gout' "$(paste -sd' ' "$LAST_GOUT")" 'result=error'

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
a_eq 'g2.workflows-permission:gout' "$(paste -sd' ' "$LAST_GOUT")" 'result=error'
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
# The App token is revoked with itself, once, AFTER the dispatch POST.
a_eq 'fl.dispatch:revoke' "$(grep -c "^gh api --method DELETE installation/token | token=$DSP_TOK |" "$MOCK_GH_LOG" || true)" 1
a_eq 'fl.dispatch:revoke-after-post' "$(grep -E '/dispatches|installation/token' "$MOCK_GH_LOG" | awk '{print $5}' | paste -sd' ' -)" \
  'repos/jikig-ai/soleur/actions/workflows/build-inngest-bootstrap-image.yml/dispatches installation/token'

# A failed revoke is a warning: the dispatch happened and the run says so.
g2_changed_fixture fl-revoke-fail
MINT_ENV=(MINT_TAG_TOKEN="$TAG_TOK")
run_mint fl-revoke-fail-tag --tag
MINT_ENV=(MINT_DISPATCH_TOKEN="$DSP_TOK" MOCK_GH_REVOKE_FAIL=1)
run_mint fl-revoke-fail --dispatch vinngest-v1.1.41
a_eq 'fl.revoke-fail:rc' "$LAST_RC" 0
a_eq 'fl.revoke-fail:result' "$(field result)" dispatched
a_out_has 'fl.revoke-fail:warning' '::warning::dispatch: revoking the App installation token failed'

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
a_eq 'fl.dispatch-fail:revoked-anyway' "$(gh_calls_to 'installation/token')" 1
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

# --dispatch against an UNREACHABLE origin: ls-remote-failed, never
# tag-not-found (a network failure must not read as "the tag is gone").
mf_new fl-dispatch-lsr
git -C "$F_REPO" remote set-url origin "$TMP/fl-dispatch-lsr/does-not-exist.git"
MINT_ENV=(MINT_DISPATCH_TOKEN="$DSP_TOK")
run_mint fl-dispatch-lsr --dispatch vinngest-v1.1.40
a_eq 'fl.dispatch-ls-remote-failed:rc' "$LAST_RC" 1
a_eq 'fl.dispatch-ls-remote-failed:stage' "$(field stage)" dispatch
a_eq 'fl.dispatch-ls-remote-failed:reason' "$(field reason)" ls-remote-failed
a_eq 'fl.dispatch-ls-remote-failed:no-post' "$(gh_calls)" 0

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

# die() refuses a call without all three of <stage> <reason> <msg>: a TEMP COPY
# with one injected two-argument call reports stage=internal reason=die-usage
# instead of an error line with an empty message.
DIE2="$TMP/die2-mint.sh"
python3 - "$SCRIPT" "$DIE2" <<'PYDIE'
import re, sys
s = open(sys.argv[1]).read()
m = re.search(r"(?m)^die\(\) \{.*?^\}\n", s, re.S)
if not m: sys.exit(2)
open(sys.argv[2], "w").write(s[:m.end()] + 'die args two-args-only\n' + s[m.end():])
PYDIE
a_eq 'fl.die-needs-three-args:landed' "$(grep -c '^die args two-args-only$' "$DIE2" 2>/dev/null || true)" 1
SUT_OVERRIDE="$DIE2"; mf_new fl-die2; unset SUT_OVERRIDE
run_mint fl-die2 --dry-run
a_eq 'fl.die-needs-three-args:rc' "$LAST_RC" 1
a_eq 'fl.die-needs-three-args:stage' "$(field stage)" internal
a_eq 'fl.die-needs-three-args:reason' "$(field reason)" die-usage

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
  # The strict tag-name regex is the build's own "Validate dispatch ref" gate: a
  # name the mint accepts but the build refuses would tag and never publish.
  la=$(grep -oE '^[[:space:]]*if \[\[ ! "\$REF" =~ [^ ]+ \]\]' "$bwf" | sed -E 's/.*=~ ([^ ]+) \]\]$/\1/')
  lm=$(grep -E "^STRICT_TAG_RE='" "$mint" | sed -E "s/^STRICT_TAG_RE='(.*)'\$/\1/")
  na=$(grep -c . <<<"$la"); nm=$(grep -c . <<<"$lm")
  if [[ "$na" == 1 && "$nm" == 1 && -n "$la" && "$la" == "$lm" ]]; then echo "OK strict-tag-re"
  else echo "BAD strict-tag-re the mint's STRICT_TAG_RE ('${lm}', found $nm) differs from the build's Validate dispatch ref regex ('${la}', found $na). Authority: $bwf (Validate dispatch ref); copy: $mint STRICT_TAG_RE"; fi
  # The heredoc start line the mint looks for exists exactly once in the build workflow.
  n=$(grep -cE '^[[:space:]]*cat > "\$BUILD_DIR/Dockerfile" <<DOCKERFILE[[:space:]]*$' "$bwf" || true)
  if [[ "$n" == 1 ]]; then echo "OK recipe-one-block"
  else echo "BAD recipe-one-block $n DOCKERFILE heredoc start line(s) in $bwf, expected 1 (the mint's decide stage refuses anything else)"; fi
}

cat > "$TMP/g3_wf.py" <<'PY'
import fnmatch, json, os, re, sys
import yaml
mint_wf, build_wf, mint_sh, composite = sys.argv[1:5]
out = []
def ok(i, m=None): out.append("OK " + i)
def bad(i, m): out.append("BAD " + i + " " + m)
AUTH = " (authority: .github/workflows/mint-inngest-bootstrap-tag.yml; the script's credential contract lives in .github/scripts/mint-inngest-bootstrap-tag.sh)"
SCRIPT = "bash .github/scripts/mint-inngest-bootstrap-tag.sh"
WOULD = "steps.decide.outputs.result == 'would-mint'"
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
(ok if "apps/web-platform/infra/**" not in paths else bad)("paths-narrow", "on.push.paths must not be the whole infra/** tree (every Terraform edit would start a run)" + AUTH)
(ok if doc.get("permissions") == {"contents": "read"} else bad)("top-permissions", "top-level permissions must be exactly contents: read" + AUTH)
jobs = doc.get("jobs") or {}
job = jobs.get("mint") or {}
(ok if len(jobs) == 1 and job else bad)("one-mint-job", "expected exactly one job named mint" + AUTH)
(ok if str(job.get("if", "")).strip() == "github.ref == 'refs/heads/main'" else bad)("job-if-main", "job if must be github.ref == 'refs/heads/main'" + AUTH)
(ok if job.get("permissions") == {"contents": "write"} else bad)("job-permissions", "job permissions must be exactly contents: write" + AUTH)
# #9262: the job is bound to the main-only Tier-B environment. norm_env accepts the
# scalar and the {name: ...} mapping form (the census's env_arms does the same).
def norm_env(j):
    e = j.get("environment")
    return e.get("name") if isinstance(e, dict) else e
(ok if norm_env(job) == "infra-privileged" else bad)("job-env", "job environment must be infra-privileged (the main-only Tier-B environment, #9262), got %r%s" % (job.get("environment"), AUTH))
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
ii, inst = find(lambda s: str(s.get("uses", "")).startswith("DopplerHQ/cli-action@"))
ki, chk = find(lambda s: s.get("name") == "Verify DOPPLER_TOKEN_INFRA_APP present")
ai, app = find(lambda s: str(s.get("uses", "")).endswith("mint-infra-app-token"))
ti, tag = find(lambda s: s.get("name") == "Create tag")
xi, dsp = find(lambda s: s.get("name") == "Dispatch build")
# EXACT shape of every step that decides, holds a credential or writes: an `if`,
# `run` or `env` that merely CONTAINS the right words (a `|| true`, an extra env
# var, a widened condition) is a different step.
# ANY = "present, value not pinned" (a SHA-pinned `uses:` a Dependabot bump moves).
# The KEY SET is pinned too (#9262): every key other than name/timeout-minutes must
# be one `want` names as present, so an added continue-on-error / env / with is a
# different step even when every pinned value still matches.
ANY = "<any>"
KEYSET = True
IGNORED_KEYS = {"name", "timeout-minutes"}
def keyset_ok(st, want):
    return set(st) - IGNORED_KEYS == {k for k, v in want.items() if v is not None}
def exact(sid, st, want):
    got = {k: (ANY if (want[k] == ANY and st.get(k) is not None) else st.get(k)) for k in want}
    good = got == want and (keyset_ok(st, want) or not KEYSET)
    (ok if good else bad)(sid + "-exact", "%s must be exactly %s (key set %s), got %s (key set %s)%s" % (sid, json.dumps(want, sort_keys=True), sorted(k for k, v in want.items() if v is not None), json.dumps(got, sort_keys=True, default=str), sorted(set(st) - IGNORED_KEYS), AUTH))
exact("decide", dec, {"id": "decide", "if": None, "env": None, "run": SCRIPT + " --dry-run", "uses": None})
exact("doppler-install", inst, {"if": WOULD, "env": None, "run": None, "uses": ANY})
exact("doppler-check", chk, {"if": WOULD, "uses": None, "run": ANY,
                             "env": {"DOPPLER_TOKEN_CHECK": "${{ secrets.DOPPLER_TOKEN_INFRA_APP }}"}})
exact("app", app, {"id": "app", "if": WOULD, "env": None, "run": None, "uses": "./.github/actions/mint-infra-app-token",
                   "with": {"doppler-token": "${{ secrets.DOPPLER_TOKEN_INFRA_APP }}", "installation-id": "166065653",
                            "permissions": '{"actions":"write"}', "repositories": "soleur"}})
exact("tag", tag, {"id": "tag", "if": WOULD, "uses": None, "run": SCRIPT + " --tag",
                   "env": {"MINT_TAG_TOKEN": "${{ github.token }}"}})
exact("dispatch", dsp, {"if": "steps.tag.outputs.result == 'tagged'", "uses": None, "run": SCRIPT + ' --dispatch "$TAG"',
                        "env": {"MINT_DISPATCH_TOKEN": "${{ steps.app.outputs.token }}", "TAG": "${{ steps.tag.outputs.tag }}"}})
(ok if 0 < di < ii < ki < ai < ti < xi else bad)("step-order", "order must be Decide, Doppler install, token check, App mint, Create tag, Dispatch build: every credential exists BEFORE the tag, and the dispatch is the only step after it" + AUTH)
aw = app.get("with") or {}
try: perms = json.loads(str(aw.get("permissions", "")))
except Exception: perms = None  # noqa: BLE001
(ok if perms == {"actions": "write"} and aw.get("repositories") == "soleur" and str(aw.get("installation-id")) == "166065653" else bad)("app-scope", "the App mint must be scoped to permissions {\"actions\":\"write\"} and repositories soleur" + AUTH)
# Every steps.X.outputs.Y names a real step id and an output that step emits:
# the mint script's GITHUB_OUTPUT keys, or a local composite's declared outputs.
script_keys = set(re.findall(r"printf '([a-z_]+)=[^']*'[^\n]*>>\s*\"\$GITHUB_OUTPUT\"", open(mint_sh).read()))
comp_keys = set(((yaml.safe_load(open(composite)) or {}).get("outputs") or {}).keys())
emits = {}
for s in steps:
    if not s.get("id"): continue
    if SCRIPT in str(s.get("run", "")): emits[s["id"]] = script_keys
    elif str(s.get("uses", "")) == "./.github/actions/mint-infra-app-token": emits[s["id"]] = comp_keys
    else: emits[s["id"]] = set()
refs = re.findall(r"steps\.([A-Za-z0-9_-]+)\.outputs\.([A-Za-z0-9_-]+)", raw)
dangling = sorted({"%s.%s" % r for r in refs if r[1] not in emits.get(r[0], set())})
(ok if refs and script_keys >= {"result", "tag", "tag_state"} and not dangling else bad)("output-refs", "steps.X.outputs.Y reference(s) with no such step id or output key: %s (script writes %s; composite outputs %s)%s" % (dangling, sorted(script_keys), sorted(comp_keys), AUTH))
for i, s in enumerate(steps):
    txt = yaml.safe_dump(s)
    if "MINT_TAG_TOKEN" in txt and i != ti: bad("tag-token-isolated", "step %d (%s) references MINT_TAG_TOKEN" % (i, s.get("name")) + AUTH)
    if "MINT_DISPATCH_TOKEN" in txt and i != xi: bad("dispatch-token-isolated", "step %d (%s) references MINT_DISPATCH_TOKEN" % (i, s.get("name")) + AUTH)
    if "steps.app.outputs" in txt and i != xi: bad("app-token-isolated", "step %d (%s) reads the App token" % (i, s.get("name")) + AUTH)
    if re.search(r"github\.token|secrets\.GITHUB_TOKEN", txt) and i != ti: bad("github-token-isolated", "step %d (%s) references the job GITHUB_TOKEN" % (i, s.get("name")) + AUTH)
    u = str(s.get("uses", ""))
    if u and not u.startswith("./") and not re.search(r"@[0-9a-f]{40}$", u): bad("sha-pinned", "step %d uses %s, not a 40-hex SHA pin" % (i, u))
for rid in ("tag-token-isolated", "dispatch-token-isolated", "app-token-isolated", "github-token-isolated", "sha-pinned"):
    if not any(o.startswith("BAD " + rid + " ") for o in out): ok(rid)
# find() returns the FIRST match, so the exact rows alone cannot see a second minter
# appended after a compliant first one; count them. And no step anywhere in the job
# may name the Tier-A secrets.DOPPLER_TOKEN (the lookahead spares *_INFRA_APP) or the
# broad Tier-B secrets.DOPPLER_TOKEN_INFRA_PRIVILEGED (no-broad-tier-b, #9321).
minters = [s for s in steps if str(s.get("uses", "")).endswith("mint-infra-app-token")]
(ok if len(minters) == 1 else bad)("one-minter", "expected exactly one mint-infra-app-token step, found %d%s" % (len(minters), AUTH))
# Scans the job AND the workflow-level env/defaults (a workflow `env:` reaches every
# step), and both the dotted and the bracket spelling of the secret.
TIER_A_RE = r"secrets(\.DOPPLER_TOKEN|\[\s*['\"]+DOPPLER_TOKEN['\"]+\s*\])(?![A-Za-z0-9_])"
(bad if re.search(TIER_A_RE, yaml.safe_dump({"job": job, "env": doc.get("env"), "defaults": doc.get("defaults")})) else ok)("no-tier-a", "the mint job (or the workflow-level env/defaults) references the Tier-A secrets.DOPPLER_TOKEN; it holds only DOPPLER_TOKEN_INFRA_APP (#9321)" + AUTH)
# #9321: the job holds ONLY the narrow DOPPLER_TOKEN_INFRA_APP (it reads the two App
# values from soleur-infra-app/prd). The broad secrets.DOPPLER_TOKEN_INFRA_PRIVILEGED
# (the whole Tier-B project) must not appear anywhere in the job or the workflow-level
# env/defaults, in the dotted, bracket or whitespace spellings and in ANY letter case (secret
# names and the `secrets` context are case-insensitive in Actions, so re.I).
BROAD_RE = r"secrets(\s*\.\s*DOPPLER_TOKEN_INFRA_PRIVILEGED|\s*\[\s*['\"]+DOPPLER_TOKEN_INFRA_PRIVILEGED['\"]+\s*\])(?![A-Za-z0-9_])"
(bad if re.search(BROAD_RE, yaml.safe_dump({"job": job, "env": doc.get("env"), "defaults": doc.get("defaults")}), re.I) else ok)("no-broad-tier-b", "the mint job (or the workflow-level env/defaults) references the broad secrets.DOPPLER_TOKEN_INFRA_PRIVILEGED; it holds only the narrow DOPPLER_TOKEN_INFRA_APP (#9321)" + AUTH)
(bad if re.search(r"secrets\.[A-Za-z0-9_]*PAT\b|\b[A-Z0-9_]*_PAT\b", raw) else ok)("no-pat", "a PAT-named secret is referenced (hr-github-app-auth-not-pat)")
si, sl = find(lambda s: str(s.get("name", "")).startswith("Post to Slack"))
(ok if si == len(steps) - 1 and str(sl.get("if", "")).strip() == "failure() || cancelled()" and sl.get("continue-on-error") is True else bad)("slack-on-failure", "the LAST step is the Slack step, if: failure() || cancelled(), continue-on-error: true" + AUTH)
srun = str(sl.get("run", ""))
(ok if re.search(r"--max-time\s+15\b", srun) and re.search(r'\|\|\s*echo\s+"?000"?', srun) else bad)("slack-curl-bounded", "the Slack curl needs --max-time 15 and || echo 000 (the bump job's form)" + AUTH)
(ok if "steps.tag.outputs.tag_state" in str(sl.get("env", {})) and '"$TAG_STATE" == unknown' in srun and "ls-remote" in srun else bad)("slack-tag-unknown-branch", "the Slack step must carry a tag_state=unknown branch that says the tag MAY exist" + AUTH)
# Every step carries its own timeout, and they sum BELOW the job cap, so a hung
# step fails as a step and the Slack step still runs inside the cap.
jt = job.get("timeout-minutes")
st = [s.get("timeout-minutes") for s in steps]
missing = [s.get("name") or s.get("uses") or s.get("id") for s in steps if not isinstance(s.get("timeout-minutes"), int) or s.get("timeout-minutes") <= 0]
(ok if isinstance(jt, int) and not missing and sum(st) < jt else bad)("step-timeouts", "every step needs a positive timeout-minutes (missing: %s) summing below the job's %s (sum %s)%s" % (missing, jt, sum(t for t in st if isinstance(t, int)), AUTH))
print("\n".join(out))
PY
g3_wf() { python3 "$TMP/g3_wf.py" "$1" "$2" "${3:-$SCRIPT}" "${4:-$COMPOSITE}" 2>&1 || echo "BAD python-crashed"; }

report g3.parity < <(g3_parity "$SCRIPT" "$BUMP" "$CONSUMER" "$BUILD_WF")
a_eq 'g3.parity:row-count' "$REPORTED" 11
report g3.wf < <(g3_wf "$MINT_WF" "$BUILD_WF")
a_eq 'g3.wf:row-count' "$REPORTED" 40

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
if s.count(old) != 1: sys.exit(2)
open(dst, "w").write(s.replace(old, new, 1))
PY
  then fail "$id:landed" "mutation anchor must match exactly once in $src"; return; fi
  if cmp -s "$src" "$dst"; then fail "$id:landed" "mutation produced an identical file"; return; fi
  pass "$id:landed"
  local m="$SCRIPT" g="$CONSUMER" b="$BUILD_WF" w="$MINT_WF"
  case "$which" in mint) m="$dst" ;; ga) g="$dst" ;; bwf) b="$dst" ;; mwf) w="$dst" ;; esac
  out=$( { g3_parity "$m" "$BUMP" "$g" "$b"; g3_wf "$w" "$b" "$m"; } )
  # A crashed or unparsed checker is a broken INSTRUMENT, never a kill.
  if grep -qE '^BAD (python-crashed|parse)|^Traceback' <<<"$out"; then
    fail "$id:caught" "instrument broken: the workflow checker crashed on the mutant"; return
  fi
  nbad=$(grep -c '^BAD ' <<<"$out" || true)
  if (( nbad > 0 )); then pass "$id:caught [$(grep '^BAD ' <<<"$out" | awk '{print $2}' | paste -sd, -)]"
  else fail "$id:caught" "mutant SURVIVED: every Guard 3 row stayed OK"; fi
}
# Positive control (review #9453): g3_mut must be able to FAIL. A comment-only change to the workflow leaves every
# Guard 3 row OK, so g3_mut must record exactly one failure (`:caught`, "mutant SURVIVED"); subshell, printf + exit.
_g3="$( (g3_mut g3.st-must-reject 'mwf' $'    environment: infra-privileged\n' $'    environment: infra-privileged  # control\n' >/dev/null 2>&1; printf '%s' "$FAIL") )"
if [[ "$_g3" != "$((FAIL + 1))" ]]; then
  printf 'FAIL INSTRUMENT: g3_mut passed a mutant that no Guard 3 row sees (FAIL %s -> %s)\n' "$FAIL" "$_g3" >&2; exit 2
fi
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
g3_mut g3.m11-strict-re 'mint' "STRICT_TAG_RE='^vinngest-v[0-9]+\.[0-9]+\.[0-9]+\$'" "STRICT_TAG_RE='^vinngest-v[0-9]+\.[0-9]+\.[0-9]+(-rc[0-9]+)?\$'"
# W1-W6: mutants that CONTAIN the right words, which a substring check let live.
g3_mut g3.w1-decide-or-true 'mwf' 'run: bash .github/scripts/mint-inngest-bootstrap-tag.sh --dry-run' 'run: bash .github/scripts/mint-inngest-bootstrap-tag.sh --dry-run || true'
g3_mut g3.w2-tag-if-widened 'mwf' $'        id: tag\n        if: steps.decide.outputs.result == \'would-mint\'' $'        id: tag\n        if: steps.decide.outputs.result == \'would-mint\' || always()'
g3_mut g3.w3-dispatch-or-true 'mwf' 'mint-inngest-bootstrap-tag.sh --dispatch "$TAG"' 'mint-inngest-bootstrap-tag.sh --dispatch "$TAG" || true'
g3_mut g3.w4-dispatch-extra-env 'mwf' '          TAG: ${{ steps.tag.outputs.tag }}'$'\n''        run:' '          TAG: ${{ steps.tag.outputs.tag }}'$'\n''          GH_TOKEN: ${{ steps.app.outputs.token }}'$'\n''        run:'
g3_mut g3.w5-tag-or-true 'mwf' 'mint-inngest-bootstrap-tag.sh --tag' 'mint-inngest-bootstrap-tag.sh --tag || true'
g3_mut g3.w6-output-typo 'mwf' "if: steps.tag.outputs.result == 'tagged'" "if: steps.tag.outputs.results == 'tagged'"
g3_mut g3.w7-app-gated-on-tag 'mwf' $'        id: app\n        if: steps.decide.outputs.result == \'would-mint\'' $'        id: app\n        if: steps.tag.outputs.result == \'tagged\''
# An output typo in a step no exact-shape row covers: only output-refs sees it.
g3_mut g3.w6b-slack-output-typo 'mwf' '          TAG: ${{ steps.tag.outputs.tag }}'$'\n''          TAG_STATE:' '          TAG: ${{ steps.tag.outputs.tags }}'$'\n''          TAG_STATE:'
g3_mut g3.w8-slack-failure-only 'mwf' 'if: failure() || cancelled()' 'if: failure()'
g3_mut g3.w9-job-cap-below-sum 'mwf' '    timeout-minutes: 20' '    timeout-minutes: 10'
g3_mut g3.w10-no-tag-state-branch 'mwf' '          TAG_STATE: ${{ steps.tag.outputs.tag_state }}'$'\n' ''
g3_mut g3.w11-paths-whole-infra 'mwf' "      - 'apps/web-platform/infra/inngest*'" "      - 'apps/web-platform/infra/**'"
# #9262 re-tier rows (plan Guard Contract, Guard 1 mutation matrix rows 2, 5, 6, 7).
g3_mut g3.w12-app-continue-on-error 'mwf' '        uses: ./.github/actions/mint-infra-app-token' $'        continue-on-error: true\n        uses: ./.github/actions/mint-infra-app-token'
g3_mut g3.w13-app-tier-a-token 'mwf' 'doppler-token: ${{ secrets.DOPPLER_TOKEN_INFRA_APP }}' 'doppler-token: ${{ secrets.DOPPLER_TOKEN }}'
g3_mut g3.w14-env-not-tier-b 'mwf' '    environment: infra-privileged' '    environment: production'
g3_mut g3.w15-no-env 'mwf' $'    environment: infra-privileged\n' ''
g3_mut g3.w17-workflow-env-tier-a 'mwf' $'\npermissions:\n  contents: read\n' $'\nenv:\n  LEAK: ${{ secrets.DOPPLER_TOKEN }}\npermissions:\n  contents: read\n'
g3_mut g3.w18-bracket-tier-a 'mwf' 'DOPPLER_TOKEN_CHECK: ${{ secrets.DOPPLER_TOKEN_INFRA_APP }}' $'DOPPLER_TOKEN_CHECK: ${{ secrets.DOPPLER_TOKEN_INFRA_APP }}\n          LEAK: ${{ secrets[\'DOPPLER_TOKEN\'] }}'
g3_mut g3.w16b-second-minter-tier-b 'mwf' $'          repositories: soleur\n' $'          repositories: soleur\n      - name: Second mint\n        id: app2\n        if: steps.decide.outputs.result == \'would-mint\'\n        timeout-minutes: 1\n        uses: ./.github/actions/mint-infra-app-token\n        with:\n          doppler-token: ${{ secrets.DOPPLER_TOKEN_INFRA_APP }}\n          installation-id: "166065653"\n          permissions: \'{"administration":"write"}\'\n          repositories: soleur\n'
# ...and the row that catches it must be one-minter (the narrow token passes no-tier-a and no-broad-tier-b).
w16b_out=$(g3_wf "$MUTDIR/g3.w16b-second-minter-tier-b.$(basename "$MINT_WF")" "$BUILD_WF")
if grep -q '^BAD one-minter ' <<<"$w16b_out"; then pass 'g3.w16b:caught-by-one-minter'
else fail 'g3.w16b:caught-by-one-minter' "the second minter was not caught by one-minter"; fi
g3_mut g3.w16-second-minter 'mwf' $'          repositories: soleur\n' $'          repositories: soleur\n      - name: Second mint\n        id: app2\n        if: steps.decide.outputs.result == \'would-mint\'\n        timeout-minutes: 1\n        uses: ./.github/actions/mint-infra-app-token\n        with:\n          doppler-token: ${{ secrets.DOPPLER_TOKEN }}\n          installation-id: "166065653"\n          permissions: \'{"actions":"write"}\'\n          repositories: soleur\n'
# #9321 narrow-source rows. w19: the mint step's token regresses to the broad Tier-B
# secret. The exact-shape row AND no-broad-tier-b must both see it (explicit greps:
# g3_mut only requires at least one BAD).
g3_mut g3.w19-app-broad-token 'mwf' 'doppler-token: ${{ secrets.DOPPLER_TOKEN_INFRA_APP }}' 'doppler-token: ${{ secrets.DOPPLER_TOKEN_INFRA_PRIVILEGED }}'
w19_out=$(g3_wf "$MUTDIR/g3.w19-app-broad-token.$(basename "$MINT_WF")" "$BUILD_WF")
if grep -q '^BAD app-exact ' <<<"$w19_out"; then pass 'g3.w19:caught-by-app-exact'
else fail 'g3.w19:caught-by-app-exact' "the broad token in the mint step's with: was not caught by app-exact"; fi
if grep -q '^BAD no-broad-tier-b ' <<<"$w19_out"; then pass 'g3.w19:caught-by-no-broad-tier-b'
else fail 'g3.w19:caught-by-no-broad-tier-b' "the broad token in the mint step's with: was not caught by no-broad-tier-b"; fi
# The verify step's env regresses to the broad secret: its exact row and no-broad-tier-b.
g3_mut g3.w21-check-broad-token 'mwf' 'DOPPLER_TOKEN_CHECK: ${{ secrets.DOPPLER_TOKEN_INFRA_APP }}' 'DOPPLER_TOKEN_CHECK: ${{ secrets.DOPPLER_TOKEN_INFRA_PRIVILEGED }}'
w21_out=$(g3_wf "$MUTDIR/g3.w21-check-broad-token.$(basename "$MINT_WF")" "$BUILD_WF")
if grep -q '^BAD doppler-check-exact ' <<<"$w21_out"; then pass 'g3.w21:caught-by-doppler-check-exact'
else fail 'g3.w21:caught-by-doppler-check-exact' "the broad secret in the verify step was not caught by doppler-check-exact"; fi
if grep -q '^BAD no-broad-tier-b ' <<<"$w21_out"; then pass 'g3.w21:caught-by-no-broad-tier-b'
else fail 'g3.w21:caught-by-no-broad-tier-b' "the broad secret in the verify step was not caught by no-broad-tier-b"; fi
# w20: a NEW step (compliant otherwise: its own if and timeout, before Create tag so the
# last-step Slack row and the timeout sum stay green) names the broad secret in BRACKET
# spelling. No exact-shape row can see a new step, so ONLY no-broad-tier-b may redden.
g3_mut g3.w20-bracket-broad-extra-step 'mwf' $'\n      - name: Create tag\n' $'\n      - name: Extra step\n        if: steps.decide.outputs.result == \'would-mint\'\n        timeout-minutes: 1\n        env:\n          LEAK: ${{ secrets[\'DOPPLER_TOKEN_INFRA_PRIVILEGED\'] }}\n        run: \'true\'\n\n      - name: Create tag\n'
w20_out=$(g3_wf "$MUTDIR/g3.w20-bracket-broad-extra-step.$(basename "$MINT_WF")" "$BUILD_WF")
if [[ "$(grep '^BAD ' <<<"$w20_out" | awk '{print $2}' | paste -sd, -)" == "no-broad-tier-b" ]]; then pass 'g3.w20:caught-only-by-no-broad-tier-b'
else fail 'g3.w20:caught-only-by-no-broad-tier-b' "expected exactly one BAD row (no-broad-tier-b), got: $(grep '^BAD ' <<<"$w20_out" | awk '{print $2}' | paste -sd, -)"; fi

# w22 (#9321 review): a NEW step names the broad secret in LOWERCASE (`secrets.doppler_token_infra_privileged`
# resolves to the same secret). The regex was case-sensitive, so this passed every row; only no-broad-tier-b
# may redden (a new step is invisible to every exact-shape row).
g3_mut g3.w22-lowercase-broad-extra-step 'mwf' $'\n      - name: Create tag\n' $'\n      - name: Extra step\n        if: steps.decide.outputs.result == \'would-mint\'\n        timeout-minutes: 1\n        env:\n          LEAK: ${{ secrets.doppler_token_infra_privileged }}\n        run: \'true\'\n\n      - name: Create tag\n'
w22_out=$(g3_wf "$MUTDIR/g3.w22-lowercase-broad-extra-step.$(basename "$MINT_WF")" "$BUILD_WF")
if [[ "$(grep '^BAD ' <<<"$w22_out" | awk '{print $2}' | paste -sd, -)" == "no-broad-tier-b" ]]; then pass 'g3.w22:caught-only-by-no-broad-tier-b'
else fail 'g3.w22:caught-only-by-no-broad-tier-b' "expected exactly one BAD row (no-broad-tier-b), got: $(grep '^BAD ' <<<"$w22_out" | awk '{print $2}' | paste -sd, -)"; fi

# H2 (must-PASS, non-canonical): the {name: ...} mapping form of the environment is
# the same binding, so every row stays OK. A row that only accepted the scalar would
# RED here on a correct workflow.
env_map="$MUTDIR/g3.h2-env-mapping.$(basename "$MINT_WF")"
python3 - "$MINT_WF" "$env_map" <<'PY'
import sys
src, dst = sys.argv[1:3]
s = open(src).read()
old = "    environment: infra-privileged\n"
assert s.count(old) == 1
open(dst, "w").write(s.replace(old, "    environment:\n      name: infra-privileged\n", 1))
PY
h2_out=$(g3_wf "$env_map" "$BUILD_WF")
if cmp -s "$MINT_WF" "$env_map"; then fail 'g3.h2-env-mapping:landed' "mutation produced an identical file"
elif grep -q '^BAD ' <<<"$h2_out"; then fail 'g3.h2-env-mapping:passes' "mapping-form environment reddened: $(grep '^BAD ' <<<"$h2_out" | awk '{print $2}' | paste -sd, -)"
else pass 'g3.h2-env-mapping:passes'; fi

# H1b: the key-set half of exact() is load-bearing. With it switched off in a COPY of
# the checker, the continue-on-error mutant (w12) must pass app-exact; restore = the
# real checker above, which caught it.
sed 's/^KEYSET = True$/KEYSET = False/' "$TMP/g3_wf.py" > "$TMP/g3_wf_nokeyset.py"
if cmp -s "$TMP/g3_wf.py" "$TMP/g3_wf_nokeyset.py"; then fail 'g3.h1b-keyset-load-bearing' "KEYSET switch did not land in the checker copy"
else
  h1b_out=$(python3 "$TMP/g3_wf_nokeyset.py" "$MUTDIR/g3.w12-app-continue-on-error.$(basename "$MINT_WF")" "$BUILD_WF" "$SCRIPT" "$COMPOSITE" 2>&1 || echo "BAD python-crashed")
  if grep -qE '^BAD (app-exact|python-crashed)' <<<"$h1b_out" || ! grep -q '^OK app-exact$' <<<"$h1b_out"; then fail 'g3.h1b-keyset-load-bearing' "app-exact still RED (or absent) with the key-set half off: the half is not what catches w12"
  else pass 'g3.h1b-keyset-load-bearing'; fi
fi

# ===========================================================================
echo "=== Composite (mint-infra-app-token) ==="
# ===========================================================================
# The composite's `run:` block, executed under the runner's composite shell with
# `doppler` and `curl` shimmed and a real synthesized RSA key. One identity
# (soleur-infra), mandatory scoping, and (#9321) a source that is one of two named
# projects: the input `doppler-project` (default soleur-infra-app, validated against
# exactly soleur-infra-app and soleur-infra-privileged before any Doppler call). The
# source is named in ARGV so this stub can see it — the harness unsets DOPPLER_PROJECT
# and DOPPLER_CONFIG, so an env-var form would read nothing. The stub accepts ONE
# project per run (DOPPLER_EXPECT_PROJECT, default the narrow project), like a Doppler
# service token, which is bound to one project and refused for any other.
CDIR="$TMP/composite"; CBIN="$CDIR/bin"; mkdir -p "$CBIN"
extract_comp() { awk '/^      run: \|[[:space:]]*$/ {on=1; next} on' "$1" | sed 's/^        //'; }
extract_comp "$COMPOSITE" > "$CDIR/run.sh"
if grep -qF 'INSTALL_RESP=$(curl -sS --max-time 30 -X POST \' "$CDIR/run.sh"; then pass 'comp:extracted'
else fail 'comp:extracted' "could not extract the composite run block from $COMPOSITE"; fi
openssl genrsa 2048 > "$CDIR/key.pem" 2>/dev/null
# doppler: logs its argv, and refuses (exit 1) unless the argv carries exactly
# `--project $DOPPLER_EXPECT_PROJECT --config prd` (default soleur-infra-app) and names
# one of the two keys.
cat > "$CBIN/doppler" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "\${DOPPLER_LOG:?unset}"
case " \$* " in
  *" --project \${DOPPLER_EXPECT_PROJECT:-soleur-infra-app} --config prd "*) : ;;
  *) echo "doppler-stub: wrong project/config: \$*" >&2; exit 1 ;;
esac
case "\$1 \$2 \$3" in
  "secrets get GITHUB_INFRA_APP_ID") printf '12345' ;;
  "secrets get GITHUB_INFRA_APP_PRIVATE_KEY") cat "$CDIR/key.pem" ;;
  *) exit 1 ;;
esac
STUB
cat > "$CBIN/curl" <<'STUB'
#!/usr/bin/env bash
{ printf -- '--call--\n'; printf '%s\n' "$@"; } >> "${CURL_LOG:?unset}"
# CURL_FAIL=<rc>: the exchange POST dies at the transport layer (timeout/DNS).
[[ -n "${CURL_FAIL:-}" && " $* " == *" POST "* ]] && { echo "curl: (28) Operation timed out" >&2; exit "$CURL_FAIL"; }
# The revoke DELETE prints nothing.
[[ " $* " == *" DELETE "* ]] && exit 0
if [[ -n "${CURL_RESP:-}" ]]; then printf '%s' "$CURL_RESP"
else printf '%s' '{"token":"fixture-installation-credential"}'; fi
STUB
chmod +x "$CBIN/doppler" "$CBIN/curl"
# comp_default <action.yml> — the composite's `doppler-project` input default, which the
# runner substitutes for an omitted input; run_comp emulates that binding with it.
comp_default() { python3 -c 'import sys, yaml; print(((yaml.safe_load(open(sys.argv[1])).get("inputs") or {}).get("doppler-project") or {}).get("default", "NONE"))' "$1"; }
COMP_DEFAULT=$(comp_default "$COMPOSITE")
# run_comp <label> <permissions> <repositories> [response-json] [doppler-token] [installation-id] [run.sh]
run_comp() {
  CLOG="$CDIR/$1.curl"; COUT="$CDIR/$1.out"; DLOG="$CDIR/$1.doppler"; : > "$CLOG"; : > "$COUT"; : > "$DLOG"
  CRC=0
  env -u SCOPE_PERMISSIONS -u SCOPE_REPOSITORIES -u CURL_RESP -u DOPPLER_PROJECT -u DOPPLER_CONFIG ${CURL_FAIL:+CURL_FAIL="$CURL_FAIL"} \
    ${4:+CURL_RESP="$4"} PATH="$CBIN:$PATH" CURL_LOG="$CLOG" DOPPLER_LOG="$DLOG" \
    DOPPLER_TOKEN="${5-fixture}" INSTALLATION_ID="${6-166065653}" DOPPLER_SOURCE="${COMP_SOURCE-$COMP_DEFAULT}" \
    SCOPE_PERMISSIONS="$2" SCOPE_REPOSITORIES="$3" RUNNER_TEMP="$CDIR" GITHUB_OUTPUT="$COUT" \
    bash --noprofile --norc -eo pipefail "${7:-$CDIR/run.sh}" > "$CDIR/$1.stdout" 2>&1 || CRC=$?
}
calls() { grep -c -- '^--call--$' "$CLOG" || true; }
dcalls() { grep -c '' "$DLOG" || true; }
refused() { (( CRC != 0 )) && echo yes || echo "no (rc=$CRC)"; }
# data_arg — the value following -d/--data* in the logged argv, or NONE.
data_arg() { awk 'f {print; exit} $0 ~ /^(-d|--data|--data-raw|--data-binary)$/ {f=1} END {if (!f) print "NONE"}' "$CLOG"; }
# Scoped: the response must grant exactly the request (+ metadata:read) over
# repository_selection=selected, or no token is handed out.
R_OK='{"token":"fixture-installation-credential","permissions":{"actions":"write","metadata":"read"},"repository_selection":"selected","repositories":[{"name":"soleur"}]}'
run_comp scoped '{"actions":"write"}' soleur "$R_OK"
a_eq 'comp.scoped:rc' "$CRC" 0
a_eq 'comp.scoped:body' "$(data_arg)" '{"repositories":["soleur"],"permissions":{"actions":"write"}}'
a_eq 'comp.scoped:token-out' "$(cat "$COUT")" 'token=fixture-installation-credential'
a_eq 'comp.scoped:one-call' "$(calls)" 1
a_eq 'comp.scoped:not-revoked' "$(grep -cx 'https://api.github.com/installation/token' "$CLOG" || true)" 0
# The token call is bounded, on every path.
a_eq 'comp.scoped:max-time' "$(awk 'f {print; exit} $0 == "--max-time" {f=1}' "$CLOG")" 30
# The default source is the narrow project (read from the composite's own input default).
a_eq 'comp.scoped:default-source' "$COMP_DEFAULT" soleur-infra-app
# The source is the validated project: exactly these two reads, project and config in argv.
a_eq 'comp.scoped:doppler-argv' "$(cat "$DLOG")" $'secrets get GITHUB_INFRA_APP_ID --plain --project soleur-infra-app --config prd\nsecrets get GITHUB_INFRA_APP_PRIVATE_KEY --plain --project soleur-infra-app --config prd'
# Per-run evidence (runbook O4c): the identity, installation, granted scope and source.
a_eq 'comp.scoped:notice' "$(grep -c '^::notice title=app-token::app=soleur-infra installation=166065653 permissions={"actions":"write","metadata":"read"} source=soleur-infra-app/prd$' "$CDIR/scoped.stdout" || true)" 1
# The explicit broad source (the apply-github-infra caller's shape): reads that project
# (the stub expects it for this run) and succeeds; the notice names it.
DOPPLER_EXPECT_PROJECT=soleur-infra-privileged COMP_SOURCE=soleur-infra-privileged run_comp privileged '{"actions":"write"}' soleur "$R_OK"
a_eq 'comp.privileged:rc' "$CRC" 0
a_eq 'comp.privileged:token-out' "$(cat "$COUT")" 'token=fixture-installation-credential'
a_eq 'comp.privileged:doppler-argv' "$(cat "$DLOG")" $'secrets get GITHUB_INFRA_APP_ID --plain --project soleur-infra-privileged --config prd\nsecrets get GITHUB_INFRA_APP_PRIVATE_KEY --plain --project soleur-infra-privileged --config prd'
a_eq 'comp.privileged:notice-source' "$(grep -c ' source=soleur-infra-privileged/prd$' "$CDIR/privileged.stdout" || true)" 1
# An unlisted source (the Tier-A project, an empty value, a lookalike) is refused BEFORE
# any Doppler or GitHub call, and nothing is handed out.
for spec in 'unlisted:soleur' 'unlisted-empty:' 'unlisted-lookalike:soleur-infra-app2' 'unlisted-prefix:soleur-infra'; do
  lbl="${spec%%:*}"; val="${spec#*:}"
  COMP_SOURCE="$val" run_comp "$lbl" '{"actions":"write"}' soleur "$R_OK"
  a_eq "comp.$lbl:refused" "$(refused)" yes
  a_eq "comp.$lbl:no-doppler" "$(dcalls)" 0
  a_eq "comp.$lbl:no-call" "$(calls)" 0
  a_eq "comp.$lbl:no-token-out" "$(cat "$COUT")" ''
  a_eq "comp.$lbl:named" "$(grep -c '^::error::mint-infra-app-token: doppler-project must be' "$CDIR/$lbl.stdout" || true)" 1
done
# A token used against the wrong project is refused by Doppler itself (the stub models
# it): the broad project asked of a stub that expects the narrow one reads nothing.
COMP_SOURCE=soleur-infra-privileged run_comp wrong-project-token '{"actions":"write"}' soleur "$R_OK"
a_eq 'comp.wrong-project-token:refused' "$(refused)" yes
a_eq 'comp.wrong-project-token:no-token-out' "$(cat "$COUT")" ''
a_eq 'comp.wrong-project-token:named' "$(grep -c '^::error::mint-infra-app-token: GITHUB_INFRA_APP_ID not readable from Doppler soleur-infra-privileged/prd' "$CDIR/wrong-project-token.stdout" || true)" 1
a_eq 'comp.wrong-project-token:runbook-pointer' "$(grep -c 'see runbook infra-credential-tiers-8209.md §Release-job App source' "$CDIR/wrong-project-token.stdout" || true)" 1
run_comp scoped-no-meta '{"actions":"write"}' soleur '{"token":"fixture-installation-credential","permissions":{"actions":"write"},"repository_selection":"selected","repositories":[{"name":"soleur"}]}'
a_eq 'comp.scoped-no-metadata:rc' "$CRC" 0
run_comp scope-wider '{"actions":"write"}' soleur '{"token":"fixture-installation-credential","permissions":{"actions":"write","contents":"write","metadata":"read"},"repository_selection":"selected","repositories":[{"name":"soleur"}]}'
a_eq 'comp.scope-mismatch:refused' "$(refused)" yes
a_eq 'comp.scope-mismatch:no-token-out' "$(cat "$COUT")" ''
a_eq 'comp.scope-mismatch:named' "$(grep -c 'differ from the requested' "$CDIR/scope-wider.stdout" || true)" 1
# A refused grant still ISSUED a token: it is revoked (DELETE /installation/token).
a_eq 'comp.scope-mismatch:revoked' "$(grep -cx 'https://api.github.com/installation/token' "$CLOG" || true)" 1
run_comp scope-narrower '{"contents":"write","pull_requests":"write"}' soleur '{"token":"fixture-installation-credential","permissions":{"contents":"write","metadata":"read"},"repository_selection":"selected","repositories":[{"name":"soleur"}]}'
a_eq 'comp.scope-narrower:refused' "$(refused)" yes
a_eq 'comp.scope-narrower:no-token-out' "$(cat "$COUT")" ''
run_comp scope-all-repos '{"actions":"write"}' soleur '{"token":"fixture-installation-credential","permissions":{"actions":"write","metadata":"read"},"repository_selection":"all"}'
a_eq 'comp.selection-all:refused' "$(refused)" yes
a_eq 'comp.selection-all:no-token-out' "$(cat "$COUT")" ''
a_eq 'comp.selection-all:revoked' "$(grep -cx 'https://api.github.com/installation/token' "$CLOG" || true)" 1
# The two repository clauses, each ALONE: selection=all with the right repo list, and
# selection=selected over MORE repositories than requested — both refused.
run_comp sel-all-with-repos '{"actions":"write"}' soleur '{"token":"fixture-installation-credential","permissions":{"actions":"write","metadata":"read"},"repository_selection":"all","repositories":[{"name":"soleur"}]}'
a_eq 'comp.sel-all-with-repos:refused' "$(refused)" yes
a_eq 'comp.sel-all-with-repos:no-token-out' "$(cat "$COUT")" ''
run_comp repos-wider '{"actions":"write"}' soleur '{"token":"fixture-installation-credential","permissions":{"actions":"write","metadata":"read"},"repository_selection":"selected","repositories":[{"name":"soleur"},{"name":"other"}]}'
a_eq 'comp.repos-wider:refused' "$(refused)" yes
a_eq 'comp.repos-wider:no-token-out' "$(cat "$COUT")" ''
# metadata may only ever be read.
run_comp metadata-write '{"actions":"write"}' soleur '{"token":"fixture-installation-credential","permissions":{"actions":"write","metadata":"write"},"repository_selection":"selected","repositories":[{"name":"soleur"}]}'
a_eq 'comp.metadata-write:refused' "$(refused)" yes
a_eq 'comp.metadata-write:no-token-out' "$(cat "$COUT")" ''
# Mandatory inputs (#9262). Composite `required: true` is not enforced by the runner,
# and an UNSCOPED token of this App carries administration:write and secrets:write,
# so every empty input is refused before any Doppler read or network call. The two
# rows that used to assert the unscoped mint (comp.default, comp.repos-only) are the
# old contract, flipped deliberately.
for spec in 'default||' 'repos-only||soleur, other' 'perms-only|{"actions":"write"}|'; do
  IFS='|' read -r lbl perms repos <<<"$spec"
  run_comp "$lbl" "$perms" "$repos"
  a_eq "comp.$lbl:refused" "$(refused)" yes
  a_eq "comp.$lbl:no-call" "$(calls)" 0
  a_eq "comp.$lbl:no-doppler" "$(dcalls)" 0
  a_eq "comp.$lbl:no-token-out" "$(cat "$COUT")" ''
done
run_comp empty-token '{"actions":"write"}' soleur "$R_OK" ''
a_eq 'comp.empty-token:refused' "$(refused)" yes
a_eq 'comp.empty-token:no-doppler' "$(dcalls)" 0
a_eq 'comp.empty-token:no-call' "$(calls)" 0
run_comp empty-installation '{"actions":"write"}' soleur "$R_OK" fixture ''
a_eq 'comp.empty-installation:refused' "$(refused)" yes
a_eq 'comp.empty-installation:no-doppler' "$(dcalls)" 0
a_eq 'comp.empty-installation:no-call' "$(calls)" 0
run_comp bad-json 'not json' soleur
a_eq 'comp.bad-json:refused' "$(refused)" yes
a_eq 'comp.bad-json:no-call' "$(calls)" 0
run_comp non-object '["actions"]' soleur
a_eq 'comp.non-object:refused' "$(refused)" yes
# A failed exchange names GitHub's refusal, with every control character (CR/LF,
# DEL, C1 NEL) and U+2028/U+2029 turned into spaces and colon runs collapsed, so vendor
# text cannot open a second workflow command (the fixture tries to forge one).
run_comp exchange-refused '{"actions":"write"}' soleur '{"message":"Resource not accessible\r\n::notice title=forged::x\u2028::warning::y\u2029::error::z\u007f\u0085::debug::w","documentation_url":"https://docs.github.test"}'
a_eq 'comp.exchange-refused:refused' "$(refused)" yes
a_eq 'comp.exchange-refused:names-message' "$(grep -c '^::error::.*Resource not accessible' "$CDIR/exchange-refused.stdout" || true)" 1
a_eq 'comp.exchange-refused:no-forged-command' "$(grep -cE '^::(notice|warning)' "$CDIR/exchange-refused.stdout" || true)" 0
a_eq 'comp.exchange-refused:no-double-colon' "$(grep '^::error::' "$CDIR/exchange-refused.stdout" | sed 's/^::error:://' | grep -c '::' || true)" 0
a_eq 'comp.exchange-refused:no-token-out' "$(cat "$COUT")" ''
# The whole vendor message stays on ONE line: every separator became a space.
a_eq 'comp.exchange-refused:one-line' "$(grep -c 'Resource not accessible' "$CDIR/exchange-refused.stdout" || true)" 1
a_eq 'comp.exchange-refused:tail-kept' "$(grep -c 'Resource not accessible.*debug:w' "$CDIR/exchange-refused.stdout" || true)" 1
a_eq 'comp.exchange-refused:no-forged-anything' "$(grep -cE '^::(notice|warning|debug)|^::error::[^m]' "$CDIR/exchange-refused.stdout" || true)" 0
a_eq 'comp.exchange-refused:no-legacy-command' "$(grep -c '^##\[' "$CDIR/exchange-refused.stdout" || true)" 0
# A transport failure (curl rc 28) is annotated, never a bare errexit with only curl's stderr.
CURL_FAIL=28 run_comp transport-fail '{"actions":"write"}' soleur "$R_OK"
a_eq 'comp.transport-fail:refused' "$(refused)" yes
a_eq 'comp.transport-fail:annotated' "$(grep -c '^::error::mint-infra-app-token: the installation-token exchange did not complete (curl rc=28' "$CDIR/transport-fail.stdout" || true)" 1
a_eq 'comp.transport-fail:no-token-out' "$(cat "$COUT")" ''
# The composite's own shape, parsed: exactly one step whose keys are exactly
# {name,id,shell,env,run} (no if / continue-on-error — a soft-failed mint hands out an
# empty token and the tag step would still run), env bound to the four inputs, and the
# token output wired to that step. The run-block harness above cannot see any of this.
cat > "$CDIR/shape.py" <<'PY'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
steps = (d.get("runs") or {}).get("steps") or []
st = steps[0] if len(steps) == 1 else {}
want_env = {"DOPPLER_TOKEN": "${{ inputs.doppler-token }}", "INSTALLATION_ID": "${{ inputs.installation-id }}",
            "SCOPE_PERMISSIONS": "${{ inputs.permissions }}", "SCOPE_REPOSITORIES": "${{ inputs.repositories }}",
            "DOPPLER_SOURCE": "${{ inputs.doppler-project }}"}
ok = (len(steps) == 1 and set(st) == {"name", "id", "shell", "env", "run"} and st.get("id") == "mint"
      and st.get("shell") == "bash" and st.get("env") == want_env
      and ((d.get("outputs") or {}).get("token") or {}).get("value") == "${{ steps.mint.outputs.token }}"
      and set((d.get("inputs") or {})) == {"doppler-token", "doppler-project", "installation-id", "permissions", "repositories"}
      and ((d.get("inputs") or {}).get("doppler-project") or {}).get("required") is False)
print("OK" if ok else "BAD keys=%s env=%s" % (sorted(st), st.get("env")))
PY
comp_shape=$(python3 "$CDIR/shape.py" "$COMPOSITE")
a_eq 'comp.shape:exact' "$comp_shape" OK
comp_shape_mut() { # comp_shape_mut <id> <old> <new> — mutate a copy; the shape check must say BAD
  local cid="$1" cdst="$CDIR/action.shape-$1.yml" got
  python3 - "$COMPOSITE" "$cdst" "$2" "$3" <<'PY'
import sys
src, dst, old, new = sys.argv[1:5]
s = open(src).read()
if s.count(old) != 1: sys.exit(2)
open(dst, "w").write(s.replace(old, new, 1))
PY
  if [[ $? -ne 0 ]] || cmp -s "$COMPOSITE" "$cdst"; then fail "comp.shape-mut-$cid:landed" "anchor did not land"; return; fi
  got=$(python3 "$CDIR/shape.py" "$cdst")
  a_eq "comp.shape-mut-$cid:caught" "${got%% *}" BAD
}
comp_shape_mut continue-on-error $'      id: mint\n' $'      id: mint\n      continue-on-error: true\n'
comp_shape_mut env-swapped 'SCOPE_PERMISSIONS: ${{ inputs.permissions }}' 'SCOPE_PERMISSIONS: ${{ inputs.repositories }}'
comp_shape_mut output-rewired 'value: ${{ steps.mint.outputs.token }}' 'value: ${{ steps.other.outputs.token }}'
# comp_mut <id> <old> <new> [nth] — copy the composite with `old` replaced by `new`
# (every occurrence, or only the nth when given), extract its run block to
# $CDIR/run.mut-<id>.sh and leave the copy at $CDIR/action.mut-<id>.yml. The anchor must
# occur; a copy identical to the original is a broken instrument.
comp_mut() {
  local cid="$1" cdst="$CDIR/action.mut-$1.yml"
  python3 - "$COMPOSITE" "$cdst" "$2" "$3" "${4:-}" <<'PY'
import sys
src, dst, old, new, nth = sys.argv[1:6]
s = open(src).read()
n = s.count(old)
if n < 1: sys.exit(2)
if nth:
    i = -1
    for _ in range(int(nth)):
        i = s.find(old, i + 1)
        if i < 0: sys.exit(2)
    s = s[:i] + new + s[i + len(old):]
else:
    s = s.replace(old, new)
open(dst, "w").write(s)
PY
  if [[ $? -ne 0 ]] || cmp -s "$COMPOSITE" "$cdst"; then fail "comp.mut-$cid:landed" "the anchor did not land in the composite copy"; return 1; fi
  pass "comp.mut-$cid:landed"
  extract_comp "$cdst" > "$CDIR/run.mut-$cid.sh"
}
# M0 (Tier-A / wrong project): every `--project` argv moved to the Tier-A `soleur`
# project must turn the scoped row RED: the stub refuses it.
if comp_mut project '--project "$DOPPLER_SOURCE"' '--project soleur'; then
  run_comp mut-project '{"actions":"write"}' soleur "$R_OK" fixture 166065653 "$CDIR/run.mut-project.sh"
  a_eq 'comp.mut-project:caught' "$( (( CRC != 0 )) && [[ ! -s "$COUT" ]] && echo yes || echo "no (rc=$CRC, token-out=$(wc -c < "$COUT"))")" yes
fi
# M1: the composite's DEFAULT flipped to the broad project. The runner would hand that
# default to the run block; the stub (expecting the narrow project) refuses it, so the
# scoped default row must go RED: refused, no token out.
if comp_mut default-flip 'default: soleur-infra-app' 'default: soleur-infra-privileged'; then
  mut_default=$(comp_default "$CDIR/action.mut-default-flip.yml")
  a_eq 'comp.mut-default-flip:default-is-broad' "$mut_default" soleur-infra-privileged
  COMP_SOURCE="$mut_default" run_comp mut-default-flip '{"actions":"write"}' soleur "$R_OK" fixture 166065653 "$CDIR/run.mut-default-flip.sh"
  a_eq 'comp.mut-default-flip:caught' "$( (( CRC != 0 )) && [[ ! -s "$COUT" ]] && echo yes || echo "no (rc=$CRC, token-out=$(wc -c < "$COUT"))")" yes
fi
# M2: the allow-list widened to accept `soleur`: the unlisted-value row must go RED. The
# widened copy no longer refuses it BEFORE a Doppler call (the stub then refuses at the
# read, after logging it), so zero Doppler calls is the property that catches it.
if comp_mut allowlist-widened 'soleur-infra-app|soleur-infra-privileged)' 'soleur-infra-app|soleur-infra-privileged|soleur)'; then
  COMP_SOURCE=soleur run_comp mut-allowlist-widened '{"actions":"write"}' soleur "$R_OK" fixture 166065653 "$CDIR/run.mut-allowlist-widened.sh"
  a_eq 'comp.mut-allowlist-widened:caught' "$( (( $(dcalls) > 0 )) && echo yes || echo "no (dcalls=$(dcalls))")" yes
fi
# M3: `--config prd` dropped from the SECOND read only (nth-occurrence replacement; the
# stub then refuses the second read and the argv equality of the scoped row differs).
if comp_mut config-dropped-second ' --config prd 2>/dev/null' ' 2>/dev/null' 2; then
  run_comp mut-config-dropped-second '{"actions":"write"}' soleur "$R_OK" fixture 166065653 "$CDIR/run.mut-config-dropped-second.sh"
  a_eq 'comp.mut-config-dropped-second:caught' "$([[ "$(cat "$DLOG")" != "$(cat "$CDIR/scoped.doppler")" ]] && echo yes || echo no)" yes
  a_eq 'comp.mut-config-dropped-second:refused' "$(refused)" yes
fi

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
chk_chmod() {
  mf_new "$1"; chmod +x "$F_REPO/$FX_INFRA/carrier-06.sh"; mf_commit c
  run_mint "$1" --dry-run; v_classify would-mint changed 'carrier:carrier-06.sh'
}
chk_verify_lsr() {
  mf_new "$1"; fx_carrier carrier-03.sh "v2 $1"; mf_commit c
  MINT_ENV=(MINT_TAG_TOKEN="$TAG_TOK" MOCK_GH_REF_BREAK_ORIGIN=1); run_mint "$1" --tag
  [[ -d "$F_ORIGIN.unreachable" ]] && mv "$F_ORIGIN.unreachable" "$F_ORIGIN"
  v_classify error reason ls-remote-failed
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
mut_row m.g2-local-tag-list ls_remote \
  'git -C "$REPO_DIR" ls-remote --tags origin "$@"' \
  "git -C \"\$REPO_DIR\" for-each-ref --format='%(objectname) %(refname)' \"\$@\"" chk_remote_only
mut_row m.g2-lexical-sort stage_allocate '| sort -V | tail -1)' '| sort | tail -1)' chk_lexical
# EQUIVALENT, and why: without the filter the `^{}` peel lines stay in `names`.
# Their X.Y.Z prefix equals their own direct line's, so the prefix set (and the
# max, and NEXT) is unchanged; `grep -qxF NEXT` never equals a `...^{}` name; and
# a peel line's prefix is <= max < NEXT, so it never sorts above NEXT in the
# not-last check. The filter is hygiene: it keeps the name set equal to the set of
# refs, which is what the messages print.
mut_row m.g2-peel-strip stage_allocate "grep -v '\\^{}\$'" "cat" chk_suffix_annotated equivalent
mut_row m.g1-blob-only tree_entry 'print a[1] " " a[3]' 'print a[3]' chk_chmod
mut_row m.g2-verify-swallows-lsr ls_remote \
  'die "$stage" ls-remote-failed' '[[ "$stage" == tag ]] || die "$stage" ls-remote-failed' chk_verify_lsr
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
