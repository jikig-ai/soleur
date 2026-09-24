#!/usr/bin/env bash
# bump-inngest-bootstrap-pin.sh — move the soleur-inngest-bootstrap cloud-init
# pin to the semver-max published vinngest-v* tag + registry-resolved digest,
# and open (or reuse) the pin-bump PR. Invoked by the bump-cloud-init-pin job of
# build-inngest-bootstrap-image.yml after a successful publish (#8359, ADR-232).
#
# WHY THE TARGET MUST BE ON MAIN (#8747, ADR-232 §7). A tag cut on an open
# PR's commit built an image of unreviewed bytes and this script pinned it: the
# bump PR merged 93 minutes before its source PR did. The `ancestry` stage
# refuses a target whose commit main cannot reach, BEFORE the registry is
# consulted, and binds the pin to the commit the build actually built
# (--signed-commit). This is the authoritative check: the bump job runs main's
# copy of this script, while the build job's own refusal runs whatever copy of
# the workflow the tagged commit carries. Ancestry is an accident control, not a
# secret boundary.
#
# WHY THE TARGET IS THE SEMVER-MAX TAG, NEVER THE TRIGGERED TAG. The drift
# guard (AC6 in cloud-init-inngest-bootstrap.test.sh) compares the pin against
# `git tag --list 'vinngest-v*' | sort -V | tail -1` — the pipeline below is
# byte-identical, and a parity assert in the fixture suite pins it. A
# workflow_dispatch re-publish or mirror_only backfill of an OLDER tag must
# therefore bump to the max (or noop), never open a downgrade PR.
#
# AUTH. All GitHub writes go through the soleur-ai App installation token in
# GH_TOKEN (minted by the job's mint-soleur-ai-app-token composite step —
# hr-github-app-auth-not-pat).
# The push remote is https://x-access-token:${GH_TOKEN}@github.com/<repo>.git —
# GITHUB_TOKEN pushes don't fire pull_request events, so required checks would
# never run on the bump PR and auto-merge could never release it.
#
# INPUTS
#   --signed-tag <vX.Y.Z>       tag signed in this run (build job's tag output)
#   --signed-digest <sha256:..> digest the sign step resolved (build digest output)
#   --signed-commit <40-hex>    commit the build job checked out (build commit
#                               output) — REQUIRED, so a workflow copy that
#                               predates the binding fails closed at args
#   --mirror-status <ok|degraded|''>  zot mirror outcome (build mirror_status output)
#   --run-url <url>             publishing run URL, recorded in the PR body
#
# ENV
#   GH_TOKEN         soleur-ai installation token (required unless BUMP_PUSH_URL set)
#   REPO             owner/name (default: $GITHUB_REPOSITORY or jikig-ai/soleur)
#   BUMP_REPO_DIR    repo to rewrite (default: cwd) — the job checks out main
#   BUMP_PUSH_URL    push remote override (fixture suites point at a bare repo)
#   GITHUB_OUTPUT / GITHUB_STEP_SUMMARY — honored when set
#
# RESULT CONTRACT — exactly one terminal `result=` line, also written to
# $GITHUB_OUTPUT (the output-file write exists for the fixture suite; no job
# consumes it): opened | existing | noop | skipped | error.
# Stage-named fatals (::error::<stage>:) — args|resolve|ancestry|rewrite|push|pr.
# (merge-arm failures are ::warning by design — a withheld or failed auto-merge
# arm never fails the publish job. mint is likewise NOT a stage: the App-JWT
# mint happens in the workflow step and its failure is a job failure, never a
# script `die`.)
set -uo pipefail

# xtrace refusal (#7797): GH_TOKEN is a live installation token — a traced run
# would print it inside the push URL. Must be the FIRST thing after `set`
# (lint-shell-trace-credential-refusal Rule A: nothing traced may precede it,
# which is why `export LC_ALL=C` sits BELOW this block, not above).
case "$-" in
  *x*)
    if [ -n "${GH_TOKEN:+x}" ]; then
      printf '[FATAL] refusing to trace with a live credential set (see #7797)\n' >&2
      printf '::error::args: xtrace with a live credential set refused (see #7797)\n' >&2
      printf 'result=error\n'
      [[ -n "${GITHUB_OUTPUT:-}" ]] && printf 'result=error\n' >> "$GITHUB_OUTPUT"
      exit 78
    fi
    ;;
esac
export LC_ALL=C

# Same leak class as the xtrace refusal: git's own trace channels print the
# credential-bearing push URL to stderr (anonymization covers error messages
# only — verified: GIT_TRACE=1 echoes the full x-access-token URL). Scrub them
# unconditionally so a debugging `env:` line cannot land the live token in logs.
unset GIT_TRACE GIT_TRACE_PACKET GIT_TRACE_PERFORMANCE GIT_TRACE_SETUP \
  GIT_TRACE_CURL GIT_TRACE_CURL_NO_DATA GIT_TRACE_REDACT GIT_TRACE2 \
  GIT_TRACE2_PERF GIT_TRACE2_EVENT GIT_CURL_VERBOSE GIT_HTTP_TRACE_AUTH_HEADER

BOT_NAME='soleur-ai[bot]'
BOT_EMAIL='273333864+soleur-ai[bot]@users.noreply.github.com'
# Pin commit identity at ENV level, not only repo-local config: an ambient
# GIT_AUTHOR_*/GIT_COMMITTER_* inherited from the caller (hook shells leak
# these) would otherwise re-author the commit past `git config user.*`.
export GIT_AUTHOR_NAME="$BOT_NAME" GIT_AUTHOR_EMAIL="$BOT_EMAIL"
export GIT_COMMITTER_NAME="$BOT_NAME" GIT_COMMITTER_EMAIL="$BOT_EMAIL"
IMAGE='ghcr.io/jikig-ai/soleur-inngest-bootstrap'
ISSUE_REF='Ref #8359'
F_WEB='apps/web-platform/infra/cloud-init.yml'
F_DED='apps/web-platform/infra/cloud-init-inngest.yml'
# The anchor carries the org path (jikig-ai/…) and every match is bounded on
# BOTH sides: a ref must not be glued to identifier chars on the left
# (`pre-jikig-ai/…` is a different image name) nor continue on the right
# (`v1.2.3rc1`, `v1.2.3.4`, a 65-hex digest). An unbounded match would rewrite
# the well-formed prefix and leave corrupt residue that passes every count
# check — a silent, self-masking fixed point (data-integrity review, #8360).
ANCHOR='jikig-ai/soleur-inngest-bootstrap:v[0-9]+\.[0-9]+\.[0-9]+(@sha256:[0-9a-f]{64})?'
LEFT_B='(^|[^[:alnum:]_.@-])'        # the org path follows /, =, ", space or BOL
RIGHT_B='([^[:alnum:]_.:@=-]|$)'     # nothing may continue the tag or digest
BOUNDED="${LEFT_B}${ANCHOR}${RIGHT_B}"
# Token extraction for the noop/post checks: the full whitespace-or-quote
# delimited ref token, so leftover residue (`rc1`, a 65th hex char) fails the
# comparison instead of substring-matching into a false noop.
TOKRE="jikig-ai/soleur-inngest-bootstrap:[^[:space:]\"']*"

# Redirects go straight to the CI sink NAMES (GITHUB_OUTPUT /
# GITHUB_STEP_SUMMARY), never through an alias: fixture-scan's relative-operand
# rule exempts exactly those names, and an alias makes a CI sink read as a
# possibly-relative path.
emit_result() {
  printf 'result=%s\n' "$1"
  [[ -n "${GITHUB_OUTPUT:-}" ]] && printf 'result=%s\n' "$1" >> "$GITHUB_OUTPUT"
  return 0
}
summary() {
  [[ -n "${GITHUB_STEP_SUMMARY:-}" ]] && printf '%s\n' "$*" >> "$GITHUB_STEP_SUMMARY"
  return 0
}
die() { # die <stage> <msg...>
  local stage="$1"; shift
  printf '::error::%s: %s\n' "$stage" "$*" >&2
  emit_result error
  summary "### inngest-bootstrap pin bump FAILED — stage \`${stage}\`"$'\n\n'"$*"
  exit 1
}

# --- args -------------------------------------------------------------------
SIGNED_TAG="" SIGNED_DIGEST="" SIGNED_COMMIT="" MIRROR_STATUS="" RUN_URL=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --signed-tag|--signed-digest|--signed-commit|--mirror-status|--run-url)
      # A valueless trailing flag must die, not spin: `shift 2` at $#=1 fails
      # without consuming, and the while loop would re-match $1 forever
      # (no `set -e` here) — burning the job's whole timeout budget.
      [[ $# -ge 2 ]] || die args "missing value for $1"
      ;;
    *) die args "unknown argument: $1" ;;
  esac
  case "$1" in
    --signed-tag)    SIGNED_TAG="$2";    shift 2 ;;
    --signed-digest) SIGNED_DIGEST="$2"; shift 2 ;;
    --signed-commit) SIGNED_COMMIT="$2"; shift 2 ;;
    --mirror-status) MIRROR_STATUS="$2"; shift 2 ;;
    --run-url)       RUN_URL="$2";       shift 2 ;;
  esac
done
[[ "$SIGNED_TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] \
  || die args "--signed-tag must be vX.Y.Z (got '${SIGNED_TAG:-<empty>}')"
[[ "$SIGNED_DIGEST" =~ ^sha256:[0-9a-f]{64}$ ]] \
  || die args "--signed-digest must be sha256:<64 hex> (got '${SIGNED_DIGEST:-<empty>}')"
[[ "$SIGNED_COMMIT" =~ ^[0-9a-f]{40}$ ]] \
  || die args "--signed-commit must be a 40-hex commit (got '${SIGNED_COMMIT:-<empty>}') — a workflow copy that predates #8747 does not pass it; re-publish from a tag cut on main"
case "$MIRROR_STATUS" in
  ok|degraded|"") : ;;
  *) die args "--mirror-status must be ok|degraded|'' (got '$MIRROR_STATUS')" ;;
esac
command -v jq >/dev/null || die args "jq is required (gh JSON parsing)"
command -v gh >/dev/null || die args "gh is required (PR operations)"
command -v crane >/dev/null || die args "crane is required (registry digest resolution)"

REPO_DIR="${BUMP_REPO_DIR:-.}"
REPO_DIR=$(cd "$REPO_DIR" 2>/dev/null && pwd) \
  || die args "BUMP_REPO_DIR '${BUMP_REPO_DIR:-}' is not a directory"
# P1a guard (fixture-dir-operand-assert): provably non-empty before the
# `git -C "$REPO_DIR"` writes below — `git -C ""` would silently retarget them
# at the caller's cwd.
: "${REPO_DIR:?BUMP_REPO_DIR resolved empty}"
git -C "$REPO_DIR" rev-parse --git-dir >/dev/null 2>&1 \
  || die args "BUMP_REPO_DIR '$REPO_DIR' is not a git repository"
REPO="${REPO:-${GITHUB_REPOSITORY:-jikig-ai/soleur}}"
if [[ -n "${BUMP_PUSH_URL:-}" ]]; then
  PUSH_URL="$BUMP_PUSH_URL"
else
  [[ -n "${GH_TOKEN:-}" ]] \
    || die args "GH_TOKEN (soleur-ai installation token) is required for the push remote"
  PUSH_URL="https://x-access-token:${GH_TOKEN}@github.com/${REPO}.git"
fi

# --- resolve: semver-max tag + registry digest -------------------------------
# AC6-IDENTICAL PIPELINE — test-bump-inngest-bootstrap-pin.sh's parity asserts
# pin each literal against cloud-init-inngest-bootstrap.test.sh.
TARGET=$(git -C "$REPO_DIR" tag --list 'vinngest-v*' 2>/dev/null \
  | sed 's/^vinngest-//' | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' \
  | sort -V | tail -1 || true)
[[ -n "$TARGET" ]] \
  || die resolve "no vinngest-v* git tags reachable — checkout needs fetch-depth: 0 + fetch-tags: true"

# --- ancestry: the target's commit must be reachable from main (#8747) --------
# Runs BEFORE crane on purpose: an off-main semver-max tag whose publish was
# refused has no image, and the unresolved-digest arm below would call that
# "publish still in flight" and exit `skipped` — the wrong diagnosis, green.
# HEAD is the `ref: main` checkout the bump PR is based on.
target_on_main() {
  local tag="vinngest-${TARGET}" shallow tag_c rc=0 who
  # Refused unless the answer is exactly `false`: a cut-off history can report a
  # real ancestor as rc 1, and a git that errors quietly prints nothing.
  shallow=$(git -C "$REPO_DIR" rev-parse --is-shallow-repository 2>/dev/null || true)
  [[ "$shallow" == "false" ]] \
    || die ancestry "cannot decide whether ${tag} is on main: the checkout is shallow (is-shallow-repository='${shallow:-<empty>}') — a cut-off history can report a real ancestor as off-main; the bump job needs fetch-depth: 0"
  # refs/tags/ explicitly, never the bare name: git resolves refs/<name> before
  # refs/tags/<name>, so a bare lookup can be answered by a different ref.
  tag_c=$(git -C "$REPO_DIR" rev-parse -q --verify "refs/tags/${tag}^{commit}" 2>/dev/null) \
    || die ancestry "tag not found: refs/tags/${tag} does not resolve to a commit in this checkout"
  git -C "$REPO_DIR" merge-base --is-ancestor "$tag_c" HEAD 2>/dev/null || rc=$?
  case "$rc" in
    0) : ;;
    1)
      if [[ "$SIGNED_TAG" == "$TARGET" ]]; then
        who="${tag}, the tag this run published,"
      else
        who="the semver-max tag ${tag} (not vinngest-${SIGNED_TAG}, the tag this run published)"
      fi
      die ancestry "${who} is on commit ${tag_c}, which is not an ancestor of main — it was cut on an unmerged branch, and pinning it would ship unreviewed bytes (#8747). Delete it: git push origin :refs/tags/${tag} — then tag the squash-merge commit on main (git tag -a ${tag} <main-sha> -m '...' && git push origin ${tag}) and re-run this job."
      ;;
    *)
      die ancestry "could not decide whether ${tag} (commit ${tag_c}) is on main: git merge-base exited ${rc} — refusing rather than guessing"
      ;;
  esac
  # Bind to the commit the build BUILT. The digest cross-check cannot see a tag
  # re-pointed while its first run was in flight: both digests are that run's.
  if [[ "$SIGNED_TAG" == "$TARGET" && "$tag_c" != "$SIGNED_COMMIT" ]]; then
    die ancestry "${tag} now names commit ${tag_c}, but this run's build signed commit ${SIGNED_COMMIT} — the tag was re-pointed after the build; refusing to pin a digest built from a different commit. Re-publish ${tag}."
  fi
  echo "ancestry: ${tag} (commit ${tag_c}) is on main"
}
target_on_main

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
rc=0
for attempt in 1 2 3; do
  rc=0
  # Bounded per call: a stalled TLS connect otherwise burns the job budget.
  timeout 60 crane digest "$IMAGE:$TARGET" > "$WORK/digest" 2> "$WORK/digest.err" || rc=$?
  [[ "$rc" -eq 0 ]] && break
  [[ "$attempt" -lt 3 ]] && sleep $(( attempt * 2 ))
done
if [[ "$rc" -ne 0 ]]; then
  if [[ "$SIGNED_TAG" != "$TARGET" ]]; then
    # Defer, don't page: the semver-max tag is NEWER than the tag this run
    # published, so that tag's own publish is probably still in flight and its
    # bump will reconcile the pin. BUT a tag outlives a failed build — if that
    # publish died before pushing its image, this deferral does NOT self-heal:
    # every later non-max run skips here while the AC6 drift guard stays red
    # (main-health-monitor escalates to a ci/main-broken issue).
    echo "::warning::crane could not resolve ${IMAGE}:${TARGET} (signed=${SIGNED_TAG}) — deferring to that tag's own publish; if that publish is dead, republish vinngest-${TARGET} or delete the tag — this deferral does not self-heal"
    emit_result skipped
    summary "### inngest-bootstrap pin bump"$'\n\n'"Deferred: \`${TARGET}\` is ahead of this run's signed tag \`${SIGNED_TAG}\`; its own publish resolves the pin. If that publish died before pushing the image, republish \`vinngest-${TARGET}\` or delete the tag — deferral alone does not self-heal."
    exit 0
  fi
  die resolve "crane digest ${IMAGE}:${TARGET} failed after 3 attempts (rc=${rc}): $(tr '\n' ' ' < "$WORK/digest.err")"
fi
RESOLVED=$(grep -oE '^sha256:[0-9a-f]{64}$' "$WORK/digest" | head -1 || true)
[[ -n "$RESOLVED" ]] \
  || die resolve "${IMAGE}:${TARGET} did not resolve to a sha256 digest — refusing to pin an unparseable value"

# Tag-conditioned cross-check: the sign step re-signs the DISPATCHED tag, so a
# mirror_only backfill of a non-max tag legitimately signs a different digest.
# Only compare when the signed tag IS the semver-max target.
if [[ "$SIGNED_TAG" == "$TARGET" ]]; then
  [[ "$SIGNED_DIGEST" == "$RESOLVED" ]] \
    || die resolve "signed digest ${SIGNED_DIGEST} != registry-resolved ${RESOLVED} for ${TARGET} — sign/drift divergence is a stop-the-line event"
else
  echo "::notice::signed tag ${SIGNED_TAG} is not the semver-max target ${TARGET} (dispatch/mirror_only backfill) — skipping the signed-vs-resolved digest cross-check"
fi
echo "target=${TARGET} resolved=${RESOLVED}"

# --- rewrite: all four sites atomically --------------------------------------
for f in "$F_WEB" "$F_DED"; do
  [[ -f "$REPO_DIR/$f" ]] || die rewrite "missing $f"
  # Count MATCHES, not matching lines (grep -c counts lines): two refs on one
  # line must still count as two. The BOUNDED pattern refuses glued or
  # continued tokens (`pre-jikig-ai/…`, `v1.2.3rc1`, a 65-hex digest) — those
  # die here instead of being rewritten into corrupt refs.
  n=$(grep -oE "$BOUNDED" "$REPO_DIR/$f" | wc -l | tr -d ' ')
  [[ "$n" == "2" ]] \
    || die rewrite "$f carries $n well-formed soleur-inngest-bootstrap ref(s), expected exactly 2 — refusing a partial or over-broad rewrite"
done
NEWREF="jikig-ai/soleur-inngest-bootstrap:${TARGET}@${RESOLVED}"
OLD_TAG=$(grep -hoE 'jikig-ai/soleur-inngest-bootstrap:v[0-9]+\.[0-9]+\.[0-9]+' "$REPO_DIR/$F_WEB" | head -1 | sed 's/.*bootstrap://' || true)
[[ -n "$OLD_TAG" ]] || die rewrite "could not read the current pin tag from $F_WEB"

all_match=1
for f in "$F_WEB" "$F_DED"; do
  while IFS= read -r ref; do
    [[ "$ref" == "$NEWREF" ]] || all_match=0
  done < <(grep -hoE "$TOKRE" "$REPO_DIR/$f")
done
if [[ "$all_match" == "1" ]]; then
  echo "pin already at ${NEWREF} — nothing to do"
  emit_result noop
  summary "### inngest-bootstrap pin bump"$'\n\n'"Already at \`${NEWREF}\` — no PR needed."
  exit 0
fi

for f in "$F_WEB" "$F_DED"; do
  # `#` delimiter — the bounded pattern contains `|` alternations.
  sed -i -E "s#${LEFT_B}${ANCHOR}${RIGHT_B}#\1${NEWREF}\3#g" "$REPO_DIR/$f" \
    || die rewrite "sed failed on $f"
  # Token-equality post-check: every ref token must equal NEWREF exactly —
  # residue the bounded match left untouched fails here, loudly.
  n=$(grep -oE "$TOKRE" "$REPO_DIR/$f" | wc -l | tr -d ' ')
  converged=$(grep -oE "$TOKRE" "$REPO_DIR/$f" | grep -cxF "$NEWREF" || true)
  [[ "$n" == "2" && "$converged" == "2" ]] \
    || die rewrite "post-rewrite $f: ${converged}/${n} ref token(s) converged to ${NEWREF} — aborting before any commit"
done

# --- push: bot-identity commit + never-clobber-human check --------------------
BRANCH="soleur/inngest-pin-${TARGET}"
git -C "$REPO_DIR" config user.name "$BOT_NAME"
git -C "$REPO_DIR" config user.email "$BOT_EMAIL"
git -C "$REPO_DIR" checkout -qB "$BRANCH" \
  || die push "could not create branch $BRANCH"
git -C "$REPO_DIR" add -- "$F_WEB" "$F_DED" \
  || die push "git add failed"
git -C "$REPO_DIR" commit -qm \
  "chore(infra): bump inngest-bootstrap pin ${OLD_TAG} -> ${TARGET} (vinngest-${TARGET})" \
  || die push "git commit failed"

remote_tip=$(git -C "$REPO_DIR" ls-remote "$PUSH_URL" "refs/heads/${BRANCH}" 2>/dev/null | awk '{print $1}')
if [[ -n "$remote_tip" ]]; then
  # Never force-push over HUMAN work on a bot branch (fix-constraints-stage-b
  # rule): a maintainer's review-fix commit must not be clobbered. The commits
  # API returns .author.login for GitHub-linked authors and
  # .commit.author.email (the raw header) for unlinked ones — both feed the
  # bot check. An unresolvable tip is treated as human: fail-closed.
  tip_author=$(gh api "repos/${REPO}/commits/${remote_tip}" 2>/dev/null \
    | jq -r '.author.login // .commit.author.email // ""' 2>/dev/null || true)
  human_tip=0
  case "$tip_author" in
    "$BOT_NAME"|'github-actions[bot]'|"$BOT_EMAIL") : ;;
    *)  human_tip=1 ;;
  esac
  if [[ "$human_tip" == "1" ]]; then
    echo "::warning::branch-has-manual-commits: ${BRANCH} remote tip is not bot-authored (login='${tip_author:-<none>}') — push skipped. Reconcile: reset the tip to a soleur-ai[bot] commit or delete the branch, then re-run. Every ${TARGET} run re-skips while a non-bot tip stands; the AC6 drift guard stays red meanwhile (main-health-monitor escalates to a ci/main-broken issue)."
    emit_result skipped
    summary "### inngest-bootstrap pin bump"$'\n\n'"**branch-has-manual-commits** — \`${BRANCH}\` carries a non-bot tip; push skipped. Reconcile: reset the tip to a \`soleur-ai[bot]\` commit or delete the branch, then re-run — every \`${TARGET}\` run re-skips while a non-bot tip stands."
    exit 0
  fi
  lease="--force-with-lease=refs/heads/${BRANCH}:${remote_tip}"
else
  lease="--force-with-lease=refs/heads/${BRANCH}:"
fi
git -C "$REPO_DIR" push "$lease" "$PUSH_URL" "HEAD:refs/heads/${BRANCH}" \
  || die push "git push of ${BRANCH} failed"

# --- pr: create or reuse ------------------------------------------------------
# Same-repo, bot-authored PRs only: `gh pr list --head` matches headRefName on
# ANY repository including forks (the "owner:branch" syntax is unsupported —
# cli/cli#10945), so an unfiltered .[0] could select a fork PR with a colliding
# branch name and arm `gh pr merge --auto` on it.
if ! PR_LIST=$(gh pr list --repo "$REPO" --head "$BRANCH" --state open \
    --json url,number,author,isCrossRepository 2>/dev/null); then
  echo "::warning::gh pr list for ${BRANCH} failed — proceeding as if no open PR exists"
  PR_LIST='[]'
fi
PR_URL=$(jq -r --arg bot "$BOT_NAME" \
  '[.[] | select((.isCrossRepository | not) and (.author.login == $bot))][0].url // ""' \
  <<<"$PR_LIST" 2>/dev/null || true)
PR_NUM=$(jq -r --arg bot "$BOT_NAME" \
  '[.[] | select((.isCrossRepository | not) and (.author.login == $bot))][0].number // ""' \
  <<<"$PR_LIST" 2>/dev/null || true)

if [[ -n "$PR_URL" && -n "$PR_NUM" ]]; then
  gh pr comment "$PR_NUM" --repo "$REPO" \
    --body "Re-run of the automated pin bump for \`${TARGET}\` (publish run: ${RUN_URL:-n/a}) — refreshed the branch; no second PR needed." \
    || echo "::warning::comment on existing PR ${PR_NUM} failed"
  RESULT_KIND=existing
  echo "open PR already exists for ${BRANCH}: ${PR_URL}"
else
  body=$(printf '%s\n' \
    "$ISSUE_REF" \
    "" \
    "Automated pin bump for \`soleur-inngest-bootstrap\`, authored by the publishing workflow (ADR-232)." \
    "" \
    "- tag: \`${TARGET}\` (\`vinngest-${TARGET}\`)" \
    "- digest: \`${RESOLVED}\`" \
    "- publishing run: ${RUN_URL:-n/a}" \
    "- sites: 4 refs across \`apps/web-platform/infra/cloud-init.yml\` and \`apps/web-platform/infra/cloud-init-inngest.yml\`" \
    "- decision record: [ADR-232](https://github.com/jikig-ai/soleur/blob/main/knowledge-base/engineering/architecture/decisions/ADR-232-inngest-bootstrap-pin-bumps-are-authored-by-the-publish-workflow.md)")
  if [[ "$SIGNED_TAG" != "$TARGET" || "$MIRROR_STATUS" != "ok" ]]; then
    body+=$(printf '\n%s\n' "" \
      "Auto-merge is **not** armed: this publish's mirror status does not attest the target (signed=${SIGNED_TAG}, mirror_status=${MIRROR_STATUS:-unset}). Verify zot serves \`${RESOLVED}\` before merging — the dedicated inngest host cannot pull from GHCR (AP-016).")
  fi
  if ! PR_URL=$(gh pr create --repo "$REPO" --base main --head "$BRANCH" \
    --title "chore(infra): bump inngest-bootstrap pin to ${TARGET}" \
    --body "$body"); then
    # A tolerated `gh pr list` failure above can hide an existing PR, and
    # create then dies on "a pull request for branch X already exists". Re-list
    # once through the SAME same-repo/bot filter before calling it fatal — a
    # hidden collision is recoverable, an unfiltered retry is not.
    PR_LIST=$(gh pr list --repo "$REPO" --head "$BRANCH" --state open \
      --json url,number,author,isCrossRepository 2>/dev/null || echo '[]')
    PR_URL=$(jq -r --arg bot "$BOT_NAME" \
      '[.[] | select((.isCrossRepository | not) and (.author.login == $bot))][0].url // ""' \
      <<<"$PR_LIST" 2>/dev/null || true)
    PR_NUM=$(jq -r --arg bot "$BOT_NAME" \
      '[.[] | select((.isCrossRepository | not) and (.author.login == $bot))][0].number // ""' \
      <<<"$PR_LIST" 2>/dev/null || true)
    [[ -n "$PR_URL" && -n "$PR_NUM" ]] \
      || die pr "gh pr create failed for ${BRANCH} and the filtered re-list found no same-repo bot PR"
    RESULT_KIND=existing
    echo "reused ${PR_URL} (create reported a collision; filtered re-list found the existing PR)"
  else
    # The create-response URL is authoritative — re-listing would re-open the
    # cross-repo/colliding-name selection surface filtered above.
    PR_NUM="${PR_URL##*/}"
    RESULT_KIND=opened
    echo "opened ${PR_URL}"
  fi
fi

# Supersede open bot-authored pin PRs for OTHER targets — never a human-tipped
# branch (same never-clobber rule as the force-push check above).
if ! OPEN_PRS=$(gh pr list --repo "$REPO" --state open --limit 200 \
    --json number,headRefName,headRefOid 2>/dev/null); then
  echo "::warning::supersede sweep's gh pr list failed — stale pin PRs may be left open"
  OPEN_PRS='[]'
fi
while IFS='|' read -r n oid; do
  [[ -n "$n" && -n "$oid" ]] || continue
  author=$(gh api "repos/${REPO}/commits/${oid}" 2>/dev/null \
    | jq -r '.author.login // .commit.author.email // ""' 2>/dev/null || true)
  case "$author" in
    "$BOT_NAME"|'github-actions[bot]'|"$BOT_EMAIL")
      # Close first, comment second: a comment on a failed close would leave a
      # stale PR claiming it was superseded; a close-then-failed-comment just
      # leaves a closed PR unexplained.
      gh pr close "$n" --repo "$REPO" \
        || echo "::warning::supersede close of PR ${n} failed"
      gh pr comment "$n" --repo "$REPO" --body "Superseded by ${PR_URL}" \
        || echo "::warning::supersede comment on PR ${n} failed"
      echo "superseded stale pin PR #${n}"
      ;;
    *) echo "::warning::open pin PR #${n} has a non-bot tip (login='${author:-<none>}') — left open for a human" ;;
  esac
done < <(jq -r --arg b "$BRANCH" \
  '.[] | select(.headRefName != null) | select(.headRefName | startswith("soleur/inngest-pin-")) | select(.headRefName != $b) | "\(.number)|\(.headRefOid)"' \
  <<<"$OPEN_PRS" 2>/dev/null)

# --- merge: arm auto-merge iff the zot mirror attests THIS target -------------
# mirror_status attests the tag THIS run published (SIGNED_TAG). When the run
# published a non-max tag, `ok` says nothing about the max target's zot copy —
# arm only when the signed tag IS the target AND its mirror is healthy.
if [[ "$SIGNED_TAG" == "$TARGET" && "$MIRROR_STATUS" == "ok" ]]; then
  if [[ -n "$PR_NUM" ]]; then
    gh pr merge "$PR_NUM" --repo "$REPO" --auto --squash \
      || echo "::warning::auto-merge arm failed for ${PR_URL} — PR left open; the next publish's supersede sweep re-reports it"
  else
    echo "::warning::could not resolve PR number for ${PR_URL} — auto-merge not armed"
  fi
elif [[ -n "$PR_NUM" && "$RESULT_KIND" == "opened" ]]; then
  # Hold comment on a NEWLY opened PR only — on the `existing` path the re-run
  # comment already explains the refresh, and a mirror_only backfill series
  # would otherwise repost the identical hold text on every run.
  if [[ "$SIGNED_TAG" != "$TARGET" ]]; then
    hold_reason="this publish signed non-max tag \`${SIGNED_TAG}\`; the max tag's zot state is attested by its own publish"
  else
    hold_reason="the zot mirror reported \`mirror_status=${MIRROR_STATUS:-unset}\` for this publish"
  fi
  gh pr comment "$PR_NUM" --repo "$REPO" \
    --body "Auto-merge withheld: ${hold_reason}. Verify zot serves \`${RESOLVED}\` before merging — the dedicated inngest host cannot pull from GHCR (AP-016)." \
    || echo "::warning::mirror-hold comment on PR ${PR_NUM} failed"
fi

emit_result "$RESULT_KIND"
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  {
    echo "### inngest-bootstrap pin bump"
    echo ""
    echo "- result: \`${RESULT_KIND}\`"
    echo "- pin: \`${NEWREF}\`"
    echo "- branch: \`${BRANCH}\`"
    echo "- PR: ${PR_URL}"
    if [[ "$SIGNED_TAG" != "$TARGET" || "$MIRROR_STATUS" != "ok" ]]; then
      echo "- auto-merge: **withheld** (signed=${SIGNED_TAG} target=${TARGET} mirror_status=${MIRROR_STATUS:-unset})"
    fi
  } >> "$GITHUB_STEP_SUMMARY"
fi
exit 0
