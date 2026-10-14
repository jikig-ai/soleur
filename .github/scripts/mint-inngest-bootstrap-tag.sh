#!/usr/bin/env bash
# mint-inngest-bootstrap-tag.sh — when main can build a different
# soleur-inngest-bootstrap image than the newest vinngest-v* tag merged into it,
# cut the next vinngest-v* tag on main and dispatch the build from main (#4326,
# ADR-232 §8). Driven by .github/workflows/mint-inngest-bootstrap-tag.yml and
# fixture-tested by .github/scripts/test/test-mint-inngest-bootstrap-tag.sh.
#
# WHY. Since #8775 (ADR-232 §7) a vinngest-v* tag must sit on a commit reachable
# from main, so a carrier-changing PR can only be tagged after it merges; until
# then main's Guard A row stays red. This closes that window in CI.
#
# DECISION (stage decide). BASE = the semver-max vinngest-v* tag merged into HEAD
# (the AC6-identical selector below). Mint iff HEAD's image inputs differ from
# BASE's: the carriers (the union of both sides' `cp` staging lines), the four
# baked pins, and the Dockerfile heredoc. HEAD's own extraction is fail-closed —
# an extractor that finds nothing would compare equal and silently noop. Comparing
# against a TAG rather than the push's `before` SHA is what makes a run that was
# dropped, skipped, or failed BEFORE the tag stage (so nothing was published)
# self-heal on the next qualifying push. A failure at or after the ref POST does
# not self-heal: the tag may exist, so the next run's base is that tag and it
# decides noop. Recovery for that case is the runbook's post-POST `tag:` row.
#
# ALLOCATION (stage allocate). The next version is one patch above EVERY
# vinngest-v* tag on the remote (ADR-232 §7 "Version allocation"), merged or not,
# suffixed or not.
#
# CREDENTIALS. Two, never together:
#   --tag      reads MINT_TAG_TOKEN (the job's GITHUB_TOKEN; the App token is scoped
#              to actions:write only). The build workflow has no `push: tags` trigger
#              (#9262), so exactly one build runs: the dispatch below.
#   --dispatch reads MINT_DISPATCH_TOKEN (the soleur-infra App installation token,
#              scoped to actions:write on soleur; minted before the tag step so a
#              credential failure publishes nothing, and revoked after the POST).
# Each mode copies its token into a local variable, unsets the env vars, and binds
# it per call as `GH_TOKEN=… gh api`. `git ls-remote` needs no credential (the
# repository is public); a token-in-remote-URL form is never used.
#
# MODES
#   --dry-run          decide only: no network, no credential. Prints `tags=local`:
#                      on a laptop, run `git fetch --tags origin` first.
#   --tag              decide → allocate → tag; ends `result=tagged tag=<name>`.
#   --dispatch <tag>   dispatch only, exactly once (no retry: a retry after a lost
#                      2xx could start a second build and MOVE the digest).
#
# ENV (test seams): MINT_REPO_DIR (default cwd), MINT_REPO (owner/name, default
# $GITHUB_REPOSITORY or jikig-ai/soleur). GITHUB_OUTPUT / GITHUB_STEP_SUMMARY are
# honoured when set.
#
# RESULT CONTRACT — exactly one terminal line on STDOUT (preflight Check 10
# discards stderr): result=noop|would-mint|tagged|dispatched|error, preceded by
# base=/changed=/tags=/tag=/tag_state=/reason=/stage= lines as they apply.
# --dry-run exits 0 on both noop and would-mint. Stage-named fatals
# (::error::<stage>:) — args|ancestry|resolve|decide|allocate|tag|dispatch. Only
# `result`, the validated `tag` and `tag_state` reach GITHUB_OUTPUT. A `tag`
# stage failure AFTER the ref POST was attempted still writes tag=<name> and
# tag_state=unknown: the ref may exist, and the Slack step must say so.
set -uo pipefail

# xtrace refusal (#7797): both credentials would print under trace, as would an
# ambient GH_TOKEN/GITHUB_TOKEN (the per-call `GH_TOKEN=` binding names one). Must
# be the FIRST thing after `set` (lint-shell-trace-credential-refusal Rule A).
case "$-" in
  *x*)
    if [ -n "${GH_TOKEN:+x}${GITHUB_TOKEN:+x}${MINT_DISPATCH_TOKEN:+x}${MINT_TAG_TOKEN:+x}" ]; then
      printf '[FATAL] refusing to trace with a live credential set (see #7797)\n' >&2
      printf '::error::args: xtrace with a live credential set refused (see #7797)\n' >&2
      printf 'stage=args\nreason=xtrace\nresult=error\n'
      [[ -n "${GITHUB_OUTPUT:-}" ]] && printf 'result=error\n' >> "$GITHUB_OUTPUT"
      exit 78
    fi
    ;;
esac
export LC_ALL=C

# git's and gh's trace channels can echo request headers; scrub them (unset, never
# `=0`) so a debugging `env:` line cannot land a credential in the log.
unset GIT_TRACE GIT_TRACE_PACKET GIT_TRACE_PERFORMANCE GIT_TRACE_SETUP \
  GIT_TRACE_CURL GIT_TRACE_CURL_NO_DATA GIT_TRACE_REDACT GIT_TRACE2 \
  GIT_TRACE2_PERF GIT_TRACE2_EVENT GIT_CURL_VERBOSE GIT_HTTP_TRACE_AUTH_HEADER \
  GH_DEBUG DEBUG

WF_PATH='.github/workflows/build-inngest-bootstrap-image.yml'
BUILD_WF_FILE='build-inngest-bootstrap-image.yml'
INNGEST_TF_PATH='apps/web-platform/infra/inngest.tf'
VECTOR_TF_PATH='apps/web-platform/infra/vector.tf'
STRICT_TAG_RE='^vinngest-v[0-9]+\.[0-9]+\.[0-9]+$'
TAGGER_NAME='github-actions[bot]'
TAGGER_EMAIL='41898282+github-actions[bot]@users.noreply.github.com'

# Collected output fields, printed once each by finish().
F_BASE="" F_CHANGED="" F_TAGS="" F_TAG="" F_TAG_STATE="" F_REASON="" F_STAGE=""
MODE=""
# Set once the git/refs POST has been attempted: from then on the tag may exist.
REF_POSTED=""

# Percent-encode a workflow-command payload: `%`, `\r` and `\n`, so operator input
# can never forge a second `::error::` line.
enc() {
  local s="$1"
  s="${s//'%'/%25}"
  s="${s//$'\r'/%0D}"
  s="${s//$'\n'/%0A}"
  printf '%s' "$s"
}
summary() {
  [[ -n "${GITHUB_STEP_SUMMARY:-}" ]] && printf '%s\n' "$*" >> "$GITHUB_STEP_SUMMARY"
  return 0
}
finish() { # finish <result> — the terminal field block
  if [[ "$MODE" == dry-run || "$MODE" == tag ]]; then
    printf 'base=%s\nchanged=%s\n' "$F_BASE" "$F_CHANGED"
  fi
  [[ -n "$F_TAGS" ]] && printf 'tags=%s\n' "$F_TAGS"
  [[ -n "$F_TAG" ]] && printf 'tag=%s\n' "$F_TAG"
  [[ -n "$F_TAG_STATE" ]] && printf 'tag_state=%s\n' "$F_TAG_STATE"
  [[ -n "$F_REASON" ]] && printf 'reason=%s\n' "$F_REASON"
  [[ -n "$F_STAGE" ]] && printf 'stage=%s\n' "$F_STAGE"
  printf 'result=%s\n' "$1"
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    [[ -n "$F_TAG" && ( "$1" != error || "$F_TAG_STATE" == unknown ) ]] && printf 'tag=%s\n' "$F_TAG" >> "$GITHUB_OUTPUT"
    [[ -n "$F_TAG_STATE" ]] && printf 'tag_state=%s\n' "$F_TAG_STATE" >> "$GITHUB_OUTPUT"
    printf 'result=%s\n' "$1" >> "$GITHUB_OUTPUT"
  fi
  return 0
}
die() { # die <stage> <reason> <msg...> — all three are required
  if (( $# < 3 )); then
    set -- internal die-usage "die called with $# argument(s) (${*:-none}); it needs <stage> <reason> <msg>"
  fi
  F_STAGE="$1" F_REASON="$2"; shift 2
  printf '::error::%s: %s\n' "$F_STAGE" "$(enc "$*")" >&2
  if [[ -n "$REF_POSTED" ]]; then
    # The ref POST was attempted, so the tag may exist: name it, never hide it.
    F_TAG="$NEXT" F_TAG_STATE=unknown
  else
    F_TAG="" F_TAG_STATE=""
  fi
  finish error
  summary "### inngest-bootstrap auto-mint FAILED — stage \`${F_STAGE}\` (reason \`${F_REASON}\`)"$'\n\n'"$*"
  exit 1
}

# --- args --------------------------------------------------------------------
DISPATCH_TAG=""
case "${1:-}" in
  --dry-run) MODE=dry-run; shift ;;
  --tag)     MODE=tag; shift ;;
  --dispatch)
    MODE=dispatch
    [[ $# -ge 2 ]] || die args usage "--dispatch needs a tag name"
    DISPATCH_TAG="$2"; shift 2 ;;
  *) MODE=usage; die args usage "usage: $0 --dry-run | --tag | --dispatch <vinngest-vX.Y.Z> (got '${1:-}')" ;;
esac
[[ $# -eq 0 ]] || die args usage "unexpected argument: $1"

# Credential isolation: each mode takes ONLY its own token and refuses to run
# while the other one is visible — the workflow binds each to its own step.
TAG_TOK="" DISPATCH_TOK=""
case "$MODE" in
  tag)
    if [[ -n "${MINT_DISPATCH_TOKEN:-}" ]]; then
      unset MINT_TAG_TOKEN MINT_DISPATCH_TOKEN
      die args credential-isolation "--tag must not see MINT_DISPATCH_TOKEN (the App token belongs to the dispatch step only)"
    fi
    TAG_TOK="${MINT_TAG_TOKEN:-}"
    ;;
  dispatch)
    if [[ -n "${MINT_TAG_TOKEN:-}" ]]; then
      unset MINT_TAG_TOKEN MINT_DISPATCH_TOKEN
      die args credential-isolation "--dispatch must not see MINT_TAG_TOKEN (the GITHUB_TOKEN belongs to the tag step only)"
    fi
    DISPATCH_TOK="${MINT_DISPATCH_TOKEN:-}"
    ;;
esac
unset MINT_TAG_TOKEN MINT_DISPATCH_TOKEN GH_TOKEN GITHUB_TOKEN
[[ "$MODE" != tag || -n "$TAG_TOK" ]] || die args missing-credential "--tag needs MINT_TAG_TOKEN (the job's GITHUB_TOKEN)"
[[ "$MODE" != dispatch || -n "$DISPATCH_TOK" ]] || die args missing-credential "--dispatch needs MINT_DISPATCH_TOKEN (the soleur-infra App token)"

command -v git >/dev/null || die args missing-tool "git is required"
command -v jq >/dev/null || die args missing-tool "jq is required"
if [[ "$MODE" != dry-run ]]; then
  command -v gh >/dev/null || die args missing-tool "gh is required for --$MODE"
fi

REPO_DIR="${MINT_REPO_DIR:-.}"
REPO_DIR=$(cd "$REPO_DIR" 2>/dev/null && pwd) \
  || die args bad-repo-dir "MINT_REPO_DIR '${MINT_REPO_DIR:-}' is not a directory"
# `git -C ""` would silently retarget every call at the caller's cwd.
: "${REPO_DIR:?MINT_REPO_DIR resolved empty}"
git -C "$REPO_DIR" rev-parse --git-dir >/dev/null 2>&1 \
  || die args bad-repo-dir "MINT_REPO_DIR '$REPO_DIR' is not a git repository"
REPO="${MINT_REPO:-${GITHUB_REPOSITORY:-jikig-ai/soleur}}"
[[ "$REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || die args bad-repo "MINT_REPO '$REPO' is not owner/name"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# ls_remote <stage> <name> <pattern...> — `git ls-remote --tags origin`, the
# authoritative remote view (a tag cut elsewhere and never fetched still counts).
# stdout lands in $WORK/<name>.lsr, stderr in $WORK/<name>.lsr.err. A non-zero rc
# is a stage-named fatal: an unreachable origin must never read as "no such tag".
# Called directly, never inside $( ), so its die exits the script.
ls_remote() {
  local stage="$1" name="$2" rc=0
  shift 2
  [[ "$name" =~ ^[a-z]+$ ]] || die "$stage" ls-remote-usage "ls_remote: bad listing name '${name}'"
  git -C "$REPO_DIR" ls-remote --tags origin "$@" > "$WORK/$name.lsr" 2> "$WORK/$name.lsr.err" || rc=$?
  if [[ "$rc" -ne 0 ]]; then
    die "$stage" ls-remote-failed "git ls-remote --tags origin failed (rc=${rc}): $(tr '\n' ' ' < "$WORK/$name.lsr.err" | cut -c1-200)"
  fi
  return 0
}

# remote_peel <ls-remote-file> <tag-name> — the commit <tag-name> names in that
# listing: its `^{}` line for an annotated tag, else its direct line (a
# lightweight tag). Prints nothing when the name is absent. The one peel parser:
# dispatch, the pre-create re-read and the post-create verify all use it.
remote_peel() {
  awk -v want="refs/tags/$2" '
    $2 == want "^{}" { peel = $1 }
    $2 == want       { direct = $1 }
    END { if (peel != "") print peel; else if (direct != "") print direct }' "$1"
}

# --- dispatch (its own step and process) -------------------------------------
stage_dispatch() {
  local peeled rc=0 resp remediation
  remediation="gh workflow run ${BUILD_WF_FILE} --ref main -f ref=${DISPATCH_TAG}"
  [[ "$DISPATCH_TAG" =~ $STRICT_TAG_RE ]] \
    || die dispatch invalid-tag "'${DISPATCH_TAG}' is not a vinngest-vX.Y.Z tag name — refusing to dispatch"
  F_TAG="$DISPATCH_TAG"
  ls_remote dispatch dispatch "refs/tags/${DISPATCH_TAG}" "refs/tags/${DISPATCH_TAG}^{}"
  peeled=$(remote_peel "$WORK/dispatch.lsr" "$DISPATCH_TAG")
  [[ "$peeled" =~ ^[0-9a-f]{40}$ ]] \
    || die dispatch tag-not-found "${DISPATCH_TAG} does not exist on the origin — nothing to dispatch"
  git -C "$REPO_DIR" merge-base --is-ancestor "$peeled" refs/remotes/origin/main 2>/dev/null || rc=$?
  case "$rc" in
    0) : ;;
    1) die dispatch off-main "${DISPATCH_TAG} names commit ${peeled}, which is not on origin/main — the build would refuse it (#8747); refusing to dispatch" ;;
    *) die dispatch ancestry-unknown "cannot decide whether ${DISPATCH_TAG} (commit ${peeled}) is on origin/main (git rc=${rc}) — refusing to dispatch" ;;
  esac
  rc=0
  resp=$(jq -n --arg r "$DISPATCH_TAG" '{ref: "main", inputs: {ref: $r}}' \
    | GH_TOKEN="$DISPATCH_TOK" gh api --method POST \
        "repos/${REPO}/actions/workflows/${BUILD_WF_FILE}/dispatches" --input - 2> "$WORK/dispatch.err") || rc=$?
  # The token's one job is done, whatever the POST returned: revoke it now rather
  # than leave an actions:write credential live for its remaining hour.
  revoke_dispatch_token
  if [[ "$rc" -ne 0 ]]; then
    api_fail dispatch "$resp" "$WORK/dispatch.err" \
      "dispatching ${BUILD_WF_FILE} for ${DISPATCH_TAG} failed. The tag exists and is the merged max: do NOT delete or reuse it. Run exactly once: ${remediation}"
  fi
  echo "dispatched ${BUILD_WF_FILE} from main with inputs.ref=${DISPATCH_TAG}"
  summary "### inngest-bootstrap auto-mint"$'\n\n'"Dispatched \`${BUILD_WF_FILE}\` from \`main\` for \`${DISPATCH_TAG}\`."
  finish dispatched
  exit 0
}

# revoke_dispatch_token — DELETE /installation/token with the token itself.
# Best-effort: a failed revoke is a warning (the token still expires within the
# hour), never a reason to report a dispatch that happened as failed.
revoke_dispatch_token() {
  local rc=0
  GH_TOKEN="$DISPATCH_TOK" gh api --method DELETE installation/token \
    > /dev/null 2> "$WORK/revoke.err" || rc=$?
  if [[ "$rc" -eq 0 ]]; then
    echo "revoked the dispatch token"
  else
    printf '::warning::dispatch: revoking the App installation token failed (gh rc=%s); it expires on its own within the hour\n' "$rc" >&2
  fi
  return 0
}

# api_fail <stage> <stdout> <stderr-file> <message> — classify a failed `gh api`
# call. Prints a reason class and the body's byte length, never raw body bytes.
api_fail() {
  local stage="$1" out="$2" errf="$3" msg="$4" reason=api-error blen http
  blen=$(printf '%s' "$out" | wc -c | tr -d ' ')
  http=$(grep -oE '\(HTTP [0-9]{3}\)' "$errf" 2>/dev/null | tail -1 | tr -dc '0-9')
  if grep -qiE 'without .?workflows.? permission' <<<"$out" \
     || grep -qiE 'without .?workflows.? permission' "$errf" 2>/dev/null; then
    reason=workflows-permission
    msg="${msg} GitHub refused for a missing \`workflows\` permission (residual R1): hand-tag the merge commit per the inngest-server runbook, only if no vinngest-v* tag points at it yet."
  elif [[ -n "$http" ]]; then
    reason="http-${http}"
  fi
  die "$stage" "$reason" "${msg} (reason=${reason}, http=${http:-none}, response body ${blen} bytes)"
}

if [[ "$MODE" == dispatch ]]; then
  stage_dispatch
fi

# --- ancestry (history visibility): refuse before resolving -------------------
# `git tag --merged HEAD` exits 0 on a shallow checkout and silently drops every
# tag below the graft (measured, #8782), so resolving first could compare against
# a LOWER base — or none. Refused unless the answer is exactly `false`.
shallow=$(git -C "$REPO_DIR" rev-parse --is-shallow-repository 2>/dev/null || true)
[[ "$shallow" == "false" ]] \
  || die ancestry shallow "cannot decide which vinngest-v* tags are merged into HEAD: the checkout is shallow (is-shallow-repository='${shallow:-<empty>}') — the mint job needs fetch-depth: 0"
# A missing mid-history object is the same fail-open one level down: the walk
# still exits 0 and reports `error: Could not read <sha>` ONLY on stderr.
walk_err=$(git -C "$REPO_DIR" tag --merged HEAD --list 'vinngest-v*' 2>&1 >/dev/null || true)
[[ -z "$walk_err" ]] \
  || die ancestry unreadable-history "cannot decide which vinngest-v* tags are merged into HEAD: git tag --merged reported an unreadable history ($(tr '\n' ' ' <<<"$walk_err" | cut -c1-200)) — refusing rather than comparing against a truncated tag set"

# --- resolve: BASE = semver-max tag merged into HEAD ---------------------------
# AC6-IDENTICAL PIPELINE — test-mint-inngest-bootstrap-tag.sh's parity rows
# require this 3-line block to equal the bump script's TARGET= block (and so
# AC6's LATEST_TAG= block), modulo name, dir operand and indentation (ADR-232 §2).
BASE=$(git -C "$REPO_DIR" tag --merged HEAD --list 'vinngest-v*' 2>/dev/null \
  | sed 's/^vinngest-//' | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' \
  | sort -V | tail -1 || true)
HEAD_SHA=$(git -C "$REPO_DIR" rev-parse -q --verify 'HEAD^{commit}' 2>/dev/null) \
  || die resolve no-head "HEAD does not resolve to a commit"
F_BASE="$BASE"
BASE_SHA=""
if [[ -n "$BASE" ]]; then
  BASE_SHA=$(git -C "$REPO_DIR" rev-parse -q --verify "refs/tags/vinngest-${BASE}^{commit}" 2>/dev/null) \
    || die resolve base-unresolvable "refs/tags/vinngest-${BASE} does not resolve to a commit in this checkout"
fi

# --- decide ------------------------------------------------------------------
# cmp_inputs <idA> <idB> -> same|differs. THE comparison primitive: every input
# class routes through it, and the self-test below drives it over a known-same and
# a known-different pair, so a hollowed comparator fails loud instead of deciding
# `noop` for everything. An empty id (unresolvable) is never "same".
cmp_inputs() {
  if [[ -n "$1" && "$1" == "$2" ]]; then printf 'same'; else printf 'differs'; fi
}
hash_of() { git -C "$REPO_DIR" hash-object --stdin; }
# tree_entry <commit> <path> -> "<mode> <oid>", or empty when the path is absent.
tree_entry() {
  git -C "$REPO_DIR" ls-tree --full-tree "$1" -- "$2" 2>/dev/null | awk -F'\t' '{ split($1, a, " "); print a[1] " " a[3] }'
}

# extract_side <commit> <side> — read one side's image inputs into $WORK/<side>:
#   cp.list      carrier repo paths (the Guard A `cp` staging extractor)
#   copy.list    baked basenames (the COPY lines, parsed strictly)
#   copy.total   every COPY line, counted permissively
#   recipe.n     DOCKERFILE heredoc blocks found (starts), or `unterminated`
#   recipe.txt   the block's body
#   pin.<name>   the four baked pins (the build step's own patterns)
extract_side() {
  local commit="$1" dir="$WORK/$2" ITF VTF WF
  mkdir -p "$dir"
  WF="$dir/wf"; ITF="$dir/inngest.tf"; VTF="$dir/vector.tf"
  git -C "$REPO_DIR" show "${commit}:${WF_PATH}" > "$WF" 2>/dev/null || : > "$WF"
  git -C "$REPO_DIR" show "${commit}:${INNGEST_TF_PATH}" > "$ITF" 2>/dev/null || : > "$ITF"
  git -C "$REPO_DIR" show "${commit}:${VECTOR_TF_PATH}" > "$VTF" 2>/dev/null || : > "$VTF"
  # Carrier extractor: Guard A's GA_CP_PATHS line (cloud-init-inngest-bootstrap.test.sh),
  # byte-identical modulo name and file operand — a parity row pins it.
  CP_PATHS=$(grep -oE '^[[:space:]]*cp apps/web-platform/infra/[A-Za-z0-9._-]+ ' "$WF" 2>/dev/null | awk '{print $2}' | sort -u || true)
  COPY_NAMES=$(grep -E '^[[:space:]]*COPY [^ ]+ [^ ]+[[:space:]]*$' "$WF" 2>/dev/null | awk '{print $2}' | sort -u || true)
  TOTAL_COPY=$(grep -cE '^[[:space:]]*COPY ' "$WF" 2>/dev/null || true)
  printf '%s\n' "$CP_PATHS" | grep -v '^$' > "$dir/cp.list" || true
  printf '%s\n' "$COPY_NAMES" | grep -v '^$' > "$dir/copy.list" || true
  printf '%s\n' "${TOTAL_COPY:-0}" > "$dir/copy.total"
  # The recipe: from the `cat > "$BUILD_DIR/Dockerfile" <<DOCKERFILE` line to the
  # first following line that is exactly `DOCKERFILE` (a comment that merely says
  # DOCKERFILE never matches either anchor).
  awk -v out="$dir/recipe.txt" '
    /^[[:space:]]*cat > "\$BUILD_DIR\/Dockerfile" <<DOCKERFILE[[:space:]]*$/ { n++; on = 1; next }
    on && /^[[:space:]]*DOCKERFILE[[:space:]]*$/ { on = 0; closed++; next }
    on { print > out }
    END { if (n != closed) print "unterminated"; else print n + 0 }
  ' "$WF" > "$dir/recipe.n"
  [[ -f "$dir/recipe.txt" ]] || : > "$dir/recipe.txt"
  # Pin extractors: the build step's own grep -E patterns (a parity row pins each).
  p_iv=$(grep -E '^\s*inngest_cli_version\s*=' "$ITF" | sed -E 's/.*"([^"]+)".*/\1/' || true)
  p_is=$(grep -E '^\s*inngest_cli_sha256\s*=' "$ITF" | sed -E 's/.*"([^"]+)".*/\1/' || true)
  p_vv=$(grep -E '^\s*vector_version\s*=' "$VTF" | sed -E 's/.*"([^"]+)".*/\1/' || true)
  p_vs=$(grep -E '^\s*vector_sha256\s*=' "$VTF" | sed -E 's/.*"([^"]+)".*/\1/' || true)
  printf '%s' "$p_iv" > "$dir/pin.inngest_cli_version"
  printf '%s' "$p_is" > "$dir/pin.inngest_cli_sha256"
  printf '%s' "$p_vv" > "$dir/pin.vector_version"
  printf '%s' "$p_vs" > "$dir/pin.vector_sha256"
}

PINS=(inngest_cli_version inngest_cli_sha256 vector_version vector_sha256)

stage_decide() {
  local H="$WORK/head" B="$WORK/base" n_cp n_copy n_total n_recipe cp_names copy_names sets
  local st_a st_b p path in_h in_b id_h id_b
  local -a changed=()
  # Instrument self-test FIRST: a comparator that cannot say both words would
  # otherwise turn every decision into a silent noop.
  st_a=$(printf 'alpha\n' | hash_of); st_b=$(printf 'beta\n' | hash_of)
  if [[ "$(cmp_inputs "$st_a" "$st_a")" != same || "$(cmp_inputs "$st_a" "$st_b")" != differs \
        || "$(cmp_inputs "" "")" != differs ]]; then
    die decide comparator-selftest "the input comparator failed its self-test (it must report both 'same' and 'differs') — refusing to decide"
  fi

  extract_side "$HEAD_SHA" head
  n_cp=$(grep -c . "$H/cp.list" || true)
  n_copy=$(grep -c . "$H/copy.list" || true)
  n_total=$(cat "$H/copy.total")
  (( n_cp > 0 )) \
    || die decide no-carriers "HEAD's ${WF_PATH} stages no 'cp apps/web-platform/infra/<file>' carrier — the extractor found nothing, which would compare equal and silently noop; fix the extractor or the workflow"
  cp_names=$(xargs -n1 basename < "$H/cp.list" | sort -u | paste -sd, -)
  copy_names=$(paste -sd, - < "$H/copy.list")
  sets="staged (cp): {${cp_names}}; baked (COPY): {${copy_names}}"
  # One reason per condition, so the recovery row names the actual drift.
  [[ "$n_total" =~ ^[0-9]+$ ]] \
    || die decide copy-count-unreadable "could not count the COPY lines of HEAD's ${WF_PATH} (got '${n_total}')"
  (( n_copy == n_total )) \
    || die decide copy-unparsed "HEAD's ${WF_PATH} has ${n_total} COPY line(s) but only ${n_copy} parse as 'COPY <src> <dst>' — ${sets}"
  (( n_cp == n_total )) \
    || die decide cardinality-count "HEAD's ${WF_PATH} stages ${n_cp} carrier(s) from apps/web-platform/infra/ but bakes ${n_total} COPY line(s) — a carrier staged from outside apps/web-platform/infra/ is invisible to this extractor and to the workflow's paths filter — ${sets}"
  [[ "$cp_names" == "$copy_names" ]] \
    || die decide cardinality-names "HEAD's ${WF_PATH} stages and bakes the same number of files but not the same names — ${sets}"
  n_recipe=$(cat "$H/recipe.n")
  if [[ "$n_recipe" == unterminated ]]; then
    die decide recipe-blocks "HEAD's ${WF_PATH} carries an unterminated DOCKERFILE heredoc block (a start line with no closing DOCKERFILE line)"
  fi
  [[ "$n_recipe" == 1 ]] \
    || die decide recipe-blocks "HEAD's ${WF_PATH} carries ${n_recipe} DOCKERFILE heredoc block(s), expected exactly 1"
  [[ -s "$H/pin.inngest_cli_version" && -s "$H/pin.inngest_cli_sha256" ]] \
    || die decide pin-empty "inngest_cli_version or inngest_cli_sha256 is empty in HEAD's ${INNGEST_TF_PATH} — the build would refuse it"

  if [[ -n "$(git -C "$REPO_DIR" tag --points-at HEAD --list 'vinngest-v*' 2>/dev/null | grep -E "$STRICT_TAG_RE" || true)" ]]; then
    DECISION=noop; F_REASON=head-tagged
    summary "### inngest-bootstrap auto-mint"$'\n\n'"noop: HEAD already carries a vinngest-v* tag."
    return 0
  fi
  if [[ -z "$BASE" ]]; then
    DECISION=would-mint; F_REASON=no-base; F_CHANGED=all
    summary "### inngest-bootstrap auto-mint"$'\n\n'"would-mint: no vinngest-v* tag is merged into HEAD, so every input counts as changed."
    return 0
  fi

  extract_side "$BASE_SHA" base
  # Carriers over the UNION of both sides' staging lines: a carrier present on one
  # side only is itself a change (added or removed).
  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    in_h=0; in_b=0
    grep -qxF -- "$path" "$H/cp.list" && in_h=1
    grep -qxF -- "$path" "$B/cp.list" && in_b=1
    if (( in_h != in_b )); then
      changed+=("carrier-set:$(basename "$path")")
      continue
    fi
    # MODE plus blob: `COPY` preserves the file mode, so a chmod-only change
    # (a carrier losing its +x) is an image change too.
    id_h=$(tree_entry "$HEAD_SHA" "$path")
    id_b=$(tree_entry "$BASE_SHA" "$path")
    [[ "$(cmp_inputs "$id_h" "$id_b")" == same ]] || changed+=("carrier:$(basename "$path")")
  done < <(sort -u "$H/cp.list" "$B/cp.list")
  for p in "${PINS[@]}"; do
    id_h=$(hash_of < "$H/pin.$p"); id_b=$(hash_of < "$B/pin.$p")
    [[ "$(cmp_inputs "$id_h" "$id_b")" == same ]] || changed+=("pin:$p")
  done
  if [[ "$(cat "$B/recipe.n")" != 1 ]]; then
    changed+=("recipe")
  else
    id_h=$(hash_of < "$H/recipe.txt"); id_b=$(hash_of < "$B/recipe.txt")
    [[ "$(cmp_inputs "$id_h" "$id_b")" == same ]] || changed+=("recipe")
  fi

  F_CHANGED=$(IFS=,; printf '%s' "${changed[*]}")
  if (( ${#changed[@]} > 0 )); then
    DECISION=would-mint; F_REASON=inputs-changed
  else
    DECISION=noop; F_REASON=unchanged
  fi
  summary "### inngest-bootstrap auto-mint — ${DECISION} (base \`vinngest-${BASE}\`)" \
    $'\n\n'"- carriers: $(sort -u "$H/cp.list" "$B/cp.list" | grep -c .) compared" \
    $'\n'"- pins: ${#PINS[@]} compared (${PINS[*]})" \
    $'\n'"- recipe: DOCKERFILE heredoc compared" \
    $'\n'"- changed: ${F_CHANGED:-none}"
  return 0
}

DECISION=""
stage_decide
if [[ "$DECISION" == noop ]]; then
  [[ -z "$BASE" ]] || echo "::notice::base=vinngest-${BASE} — HEAD builds the same image inputs; nothing to mint. If vinngest-${BASE} has no build run, see the inngest-server runbook recovery table."
  [[ "$MODE" == dry-run ]] && F_TAGS=local
  finish noop
  exit 0
fi
if [[ "$MODE" == dry-run ]]; then
  F_TAGS=local
  finish would-mint
  exit 0
fi

# --- allocate: one patch above EVERY remote vinngest-v* tag --------------------
stage_allocate() {
  local names prefixes bad max x y z
  ls_remote allocate allocate 'refs/tags/vinngest-v*'
  names=$(awk '{print $2}' "$WORK/allocate.lsr" | grep -v '\^{}$' | sed 's#^refs/tags/##' || true)
  prefixes=$(printf '%s\n' "$names" | grep -oE '^vinngest-v[0-9]+\.[0-9]+\.[0-9]+' | sed 's/^vinngest-v//' || true)
  [[ -n "$prefixes" ]] \
    || die allocate no-remote-tags "the origin carries no vinngest-vX.Y.Z tag at all — refusing to invent a version series"
  bad=$(printf '%s\n' "$prefixes" | grep -vE '^[0-9]{1,6}\.[0-9]{1,6}\.[0-9]{1,6}$' | head -1 || true)
  [[ -z "$bad" ]] \
    || die allocate oversized-version "a remote tag carries a version component longer than 6 digits (vinngest-v${bad}) — refusing to allocate above it"
  # A zero-padded component (v1.01.2) names the same number as its unpadded twin,
  # so two distinct tags would sort as one version: refuse rather than guess.
  bad=$(printf '%s\n' "$prefixes" | grep -vE '^(0|[1-9][0-9]{0,5})(\.(0|[1-9][0-9]{0,5})){2}$' | head -1 || true)
  [[ -z "$bad" ]] \
    || die allocate leading-zero-version "a remote tag carries a zero-padded version component (vinngest-v${bad}) — refusing to allocate above it"
  max=$(printf '%s\n' "$prefixes" | sort -V | tail -1)
  IFS=. read -r x y z <<<"$max"
  NEXT="vinngest-v${x}.${y}.$((10#$z + 1))"
  [[ "$NEXT" =~ $STRICT_TAG_RE ]] || die allocate bad-next "allocated '${NEXT}', which is not vinngest-vX.Y.Z"
  if grep -qxF -- "$NEXT" <<<"$names"; then
    die allocate next-exists "allocated ${NEXT}, which already exists on the origin"
  fi
  [[ "$(printf '%s\n%s\n' "$names" "$NEXT" | grep -v '^$' | sort -V | tail -n 1)" == "$NEXT" ]] \
    || die allocate not-last "${NEXT} does not sort above every existing vinngest-v* name"
  echo "allocate: ${NEXT} (above remote max v${max}; base vinngest-${BASE:-<none>})"
}

# --- tag: annotated tag object + ref, with the job's GITHUB_TOKEN -------------
# precreate_reread — a strict vinngest-vX.Y.Z tag that already peels to HEAD on the
# origin means a human or a concurrent run tagged this commit: two tags on one
# commit would mean two builds, so end noop and create nothing.
precreate_reread() {
  local f="$WORK/reread.lsr" n hit=""
  ls_remote tag reread 'refs/tags/vinngest-v*'
  while IFS= read -r n; do
    [[ "$n" =~ $STRICT_TAG_RE ]] || continue
    if [[ "$(remote_peel "$f" "$n")" == "$HEAD_SHA" ]]; then hit="$n"; break; fi
  done < <(awk '$2 !~ /\^\{\}$/ { sub(/^refs\/tags\//, "", $2); print $2 }' "$f")
  if [[ -n "$hit" ]]; then
    echo "::notice::${hit} already points at ${HEAD_SHA} on the origin — a human or a concurrent run tagged it; creating nothing"
    F_REASON=concurrent-tag
    finish noop
    exit 0
  fi
}
post_tag_object() {
  local rc=0 resp run_url msg
  run_url="${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY:-$REPO}/actions/runs/${GITHUB_RUN_ID:-local}"
  msg=$(printf '%s\n\n%s\n%s\n%s\n%s\n' \
    "${NEXT}: auto-minted on main (#4326, ADR-232 §8)" \
    "commit: ${HEAD_SHA}" \
    "base: vinngest-${BASE:-<none>}" \
    "changed: ${F_CHANGED}" \
    "run: ${run_url}")
  resp=$(jq -n --arg tag "$NEXT" --arg message "$msg" --arg object "$HEAD_SHA" \
      --arg name "$TAGGER_NAME" --arg email "$TAGGER_EMAIL" --arg date "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      '{tag: $tag, message: $message, object: $object, type: "commit", tagger: {name: $name, email: $email, date: $date}}' \
    | GH_TOKEN="$TAG_TOK" gh api --method POST "repos/${REPO}/git/tags" --input - 2> "$WORK/tag.err") || rc=$?
  [[ "$rc" -eq 0 ]] || api_fail tag "$resp" "$WORK/tag.err" "creating the annotated tag object ${NEXT} failed; nothing was created, a re-run re-decides from a fresh re-read"
  # The response carries TWO shas: the tag object's (.sha) and the commit's
  # (.object.sha). The ref must point at the tag object, so read .sha with jq.
  TAG_OBJ=$(jq -r '.sha // empty' <<<"$resp" 2>/dev/null || true)
  [[ "$TAG_OBJ" =~ ^[0-9a-f]{40}$ ]] \
    || die tag bad-response "the git/tags response carried no tag-object sha (response body $(printf '%s' "$resp" | wc -c | tr -d ' ') bytes)"
  [[ "$(jq -r '.object.sha // empty' <<<"$resp" 2>/dev/null)" == "$HEAD_SHA" && "$(jq -r '.tag // empty' <<<"$resp" 2>/dev/null)" == "$NEXT" ]] \
    || die tag bad-response "the git/tags response does not describe ${NEXT} on ${HEAD_SHA}"
}
post_tag_ref() {
  local rc=0 resp
  # From here on the ref may exist whatever the POST reports (a lost 2xx), so
  # every later fatal names the tag with tag_state=unknown (see die).
  REF_POSTED=1
  # die() covers a reported failure; a HANG is killed by the step timeout before
  # die or finish can run. Record the name first so the Slack step still reads
  # "MAY exist" (not "before any tag") after a kill. finish appends the final
  # values later; for a repeated GITHUB_OUTPUT key the last line wins.
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    printf 'tag=%s\ntag_state=unknown\n' "$NEXT" >> "$GITHUB_OUTPUT"
  fi
  resp=$(jq -n --arg ref "refs/tags/${NEXT}" --arg sha "$TAG_OBJ" '{ref: $ref, sha: $sha}' \
    | GH_TOKEN="$TAG_TOK" gh api --method POST "repos/${REPO}/git/refs" --input - 2> "$WORK/ref.err") || rc=$?
  [[ "$rc" -eq 0 ]] || api_fail tag "$resp" "$WORK/ref.err" "creating refs/tags/${NEXT} failed. The ref MAY exist (a lost 2xx): check git ls-remote --tags origin refs/tags/${NEXT}; if it peels to ${HEAD_SHA} and no build run exists for it, dispatch once: gh workflow run ${BUILD_WF_FILE} --ref main -f ref=${NEXT}"
}
verify_tag() {
  local peeled
  ls_remote tag verify "refs/tags/${NEXT}" "refs/tags/${NEXT}^{}"
  peeled=$(remote_peel "$WORK/verify.lsr" "$NEXT")
  [[ "$peeled" == "$HEAD_SHA" ]] \
    || die tag verify-failed "refs/tags/${NEXT} does not peel to ${HEAD_SHA} on the origin after creation (got '${peeled:-<none>}')"
}
stage_tag() {
  precreate_reread     # step: re-read
  post_tag_object      # step: tag object
  post_tag_ref         # step: ref
  verify_tag
  # created overrides the provisional tag_state=unknown post_tag_ref recorded.
  F_TAG="$NEXT" F_TAG_STATE=created
  echo "tagged ${NEXT} -> ${HEAD_SHA}"
  summary "### inngest-bootstrap auto-mint"$'\n\n'"Tagged \`${NEXT}\` on \`${HEAD_SHA}\` (base \`vinngest-${BASE:-none}\`; changed: ${F_CHANGED})."
  finish tagged
  exit 0
}

NEXT="" TAG_OBJ=""
stage_allocate
stage_tag
