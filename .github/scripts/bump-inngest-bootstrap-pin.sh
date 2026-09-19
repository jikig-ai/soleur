#!/usr/bin/env bash
# bump-inngest-bootstrap-pin.sh — move the soleur-inngest-bootstrap cloud-init
# pin to the semver-max published vinngest-v* tag + registry-resolved digest,
# and open (or reuse) the pin-bump PR. Invoked by the bump-cloud-init-pin job of
# build-inngest-bootstrap-image.yml after a successful publish (#8359, ADR-230).
#
# WHY THE TARGET IS THE SEMVER-MAX TAG, NEVER THE TRIGGERED TAG. The drift
# guard (AC6 in cloud-init-inngest-bootstrap.test.sh) compares the pin against
# `git tag --list 'vinngest-v*' | sort -V | tail -1` — the pipeline below is
# byte-identical, and a parity assert in the fixture suite pins it. A
# workflow_dispatch re-publish or mirror_only backfill of an OLDER tag must
# therefore bump to the max (or noop), never open a downgrade PR.
#
# AUTH. All GitHub writes go through the soleur-ai App installation token in
# GH_TOKEN (minted by the job's inline JWT step — hr-github-app-auth-not-pat).
# The push remote is https://x-access-token:${GH_TOKEN}@github.com/<repo>.git —
# GITHUB_TOKEN pushes don't fire pull_request events, so required checks would
# never run on the bump PR and auto-merge could never release it.
#
# INPUTS
#   --signed-tag <vX.Y.Z>       tag signed in this run (build job's tag output)
#   --signed-digest <sha256:..> digest the sign step resolved (build digest output)
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
# Stage-named fatals (::error::<stage>:) — args|resolve|rewrite|push|pr|merge.
# (mint is deliberately NOT a stage: the App-JWT mint happens in the workflow
# step and its failure is a job failure, never a script `die`.)
set -uo pipefail

# xtrace refusal (#7797): GH_TOKEN is a live installation token — a traced run
# would print it inside the push URL. Must be the FIRST thing after `set`
# (lint-shell-trace-credential-refusal Rule A: nothing traced may precede it,
# which is why `export LC_ALL=C` sits BELOW this block, not above).
case "$-" in
  *x*)
    if [ -n "${GH_TOKEN:+x}" ]; then
      printf '[FATAL] refusing to trace with a live credential set (see #7797)\n' >&2
      exit 78
    fi
    ;;
esac
export LC_ALL=C

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
ANCHOR='soleur-inngest-bootstrap:v[0-9]+\.[0-9]+\.[0-9]+(@sha256:[0-9a-f]{64})?'

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
SIGNED_TAG="" SIGNED_DIGEST="" MIRROR_STATUS="" RUN_URL=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --signed-tag)    SIGNED_TAG="${2:-}";    shift 2 ;;
    --signed-digest) SIGNED_DIGEST="${2:-}"; shift 2 ;;
    --mirror-status) MIRROR_STATUS="${2:-}"; shift 2 ;;
    --run-url)       RUN_URL="${2:-}";       shift 2 ;;
    *) die args "unknown argument: $1" ;;
  esac
done
[[ "$SIGNED_TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] \
  || die args "--signed-tag must be vX.Y.Z (got '${SIGNED_TAG:-<empty>}')"
[[ "$SIGNED_DIGEST" =~ ^sha256:[0-9a-f]{64}$ ]] \
  || die args "--signed-digest must be sha256:<64 hex> (got '${SIGNED_DIGEST:-<empty>}')"
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

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
rc=0
for attempt in 1 2 3; do
  rc=0
  crane digest "$IMAGE:$TARGET" > "$WORK/digest" 2> "$WORK/digest.err" || rc=$?
  [[ "$rc" -eq 0 ]] && break
  sleep $(( attempt * 2 ))
done
if [[ "$rc" -ne 0 ]]; then
  if [[ "$SIGNED_TAG" != "$TARGET" ]]; then
    # Defer, don't page: the semver-max tag is NEWER than the tag this run
    # published, so that tag's own publish is still in flight and its bump
    # will reconcile the pin. Erroring here alerts on a self-healing race.
    echo "::notice::crane could not resolve ${IMAGE}:${TARGET} (a newer tag's publish is still in flight; signed=${SIGNED_TAG}) — deferring to that publish's bump"
    emit_result skipped
    summary "### inngest-bootstrap pin bump"$'\n\n'"Deferred: \`${TARGET}\` is ahead of this run's signed tag \`${SIGNED_TAG}\`; its own publish resolves the pin."
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
  # line must still count as two.
  n=$(grep -oE "$ANCHOR" "$REPO_DIR/$f" | wc -l | tr -d ' ')
  [[ "$n" == "2" ]] \
    || die rewrite "$f carries $n soleur-inngest-bootstrap ref(s), expected exactly 2 — refusing a partial or over-broad rewrite"
done
NEWREF="soleur-inngest-bootstrap:${TARGET}@${RESOLVED}"
OLD_TAG=$(grep -hoE 'soleur-inngest-bootstrap:v[0-9]+\.[0-9]+\.[0-9]+' "$REPO_DIR/$F_WEB" | head -1 | sed 's/.*bootstrap://' || true)
[[ -n "$OLD_TAG" ]] || die rewrite "could not read the current pin tag from $F_WEB"

all_match=1
for f in "$F_WEB" "$F_DED"; do
  while IFS= read -r ref; do
    [[ "$ref" == "$NEWREF" ]] || all_match=0
  done < <(grep -hoE "$ANCHOR" "$REPO_DIR/$f")
done
if [[ "$all_match" == "1" ]]; then
  echo "pin already at ${NEWREF} — nothing to do"
  emit_result noop
  summary "### inngest-bootstrap pin bump"$'\n\n'"Already at \`${NEWREF}\` — no PR needed."
  exit 0
fi

for f in "$F_WEB" "$F_DED"; do
  sed -i -E "s|${ANCHOR}|${NEWREF}|g" "$REPO_DIR/$f" \
    || die rewrite "sed failed on $f"
  total=$(grep -oE 'soleur-inngest-bootstrap:v[0-9]+\.[0-9]+\.[0-9]+' "$REPO_DIR/$f" | wc -l | tr -d ' ')
  with_dig=$(grep -oE 'soleur-inngest-bootstrap:v[0-9]+\.[0-9]+\.[0-9]+@sha256:[0-9a-f]{64}' "$REPO_DIR/$f" | wc -l | tr -d ' ')
  [[ "$total" == "2" && "$with_dig" == "2" ]] \
    || die rewrite "post-rewrite $f: ${total} tag ref(s) / ${with_dig} digested ref(s), expected 2/2 — aborting before any commit"
done
distinct=$(grep -hoE 'soleur-inngest-bootstrap:v[0-9]+\.[0-9]+\.[0-9]+@sha256:[0-9a-f]{64}' \
  "$REPO_DIR/$F_WEB" "$REPO_DIR/$F_DED" | sort -u | wc -l | tr -d ' ')
[[ "$distinct" == "1" ]] \
  || die rewrite "post-rewrite refs diverge (${distinct} distinct) — aborting before any commit"

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
    echo "::warning::branch-has-manual-commits: ${BRANCH} remote tip is not bot-authored (login='${tip_author:-<none>}') — skipping push; reconcile manually"
    emit_result skipped
    summary "### inngest-bootstrap pin bump"$'\n\n'"**branch-has-manual-commits** — \`${BRANCH}\` carries a non-bot tip; push skipped. Reconcile the branch manually."
    exit 0
  fi
  lease="--force-with-lease=refs/heads/${BRANCH}:${remote_tip}"
else
  lease="--force-with-lease=refs/heads/${BRANCH}:"
fi
git -C "$REPO_DIR" push "$lease" "$PUSH_URL" "HEAD:refs/heads/${BRANCH}" \
  || die push "git push of ${BRANCH} failed"

# --- pr: create or reuse ------------------------------------------------------
if ! PR_LIST=$(gh pr list --repo "$REPO" --head "$BRANCH" --state open --json url,number 2>/dev/null); then
  echo "::warning::gh pr list for ${BRANCH} failed — proceeding as if no open PR exists"
  PR_LIST='[]'
fi
PR_URL=$(jq -r '.[0].url // ""' <<<"$PR_LIST" 2>/dev/null || true)
PR_NUM=$(jq -r '.[0].number // ""' <<<"$PR_LIST" 2>/dev/null || true)

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
    "Automated pin bump for \`soleur-inngest-bootstrap\`, authored by the publishing workflow (ADR-230)." \
    "" \
    "- tag: \`${TARGET}\` (\`vinngest-${TARGET}\`)" \
    "- digest: \`${RESOLVED}\`" \
    "- publishing run: ${RUN_URL:-n/a}" \
    "- sites: 4 refs across \`apps/web-platform/infra/cloud-init.yml\` and \`apps/web-platform/infra/cloud-init-inngest.yml\`")
  if [[ "$SIGNED_TAG" != "$TARGET" || "$MIRROR_STATUS" != "ok" ]]; then
    body+=$(printf '\n%s\n' "" \
      "Auto-merge is **not** armed: this publish's mirror status does not attest the target (signed=${SIGNED_TAG}, mirror_status=${MIRROR_STATUS:-unset}). Verify zot serves \`${RESOLVED}\` before merging — the dedicated inngest host cannot pull from GHCR (AP-016).")
  fi
  PR_URL=$(gh pr create --repo "$REPO" --base main --head "$BRANCH" \
    --title "chore(infra): bump inngest-bootstrap pin to ${TARGET}" \
    --body "$body") || die pr "gh pr create failed for ${BRANCH}"
  PR_NUM=$(gh pr list --repo "$REPO" --head "$BRANCH" --state open --json number 2>/dev/null \
    | jq -r '.[0].number // ""' 2>/dev/null || true)
  RESULT_KIND=opened
  echo "opened ${PR_URL}"
fi

# Supersede open bot-authored pin PRs for OTHER targets — never a human-tipped
# branch (same never-clobber rule as the force-push check above).
OPEN_PRS=$(gh pr list --repo "$REPO" --state open --limit 200 --json number,headRefName,headRefOid 2>/dev/null || echo '[]')
while IFS='|' read -r n oid; do
  [[ -n "$n" && -n "$oid" ]] || continue
  author=$(gh api "repos/${REPO}/commits/${oid}" 2>/dev/null \
    | jq -r '.author.login // .commit.author.email // ""' 2>/dev/null || true)
  case "$author" in
    "$BOT_NAME"|'github-actions[bot]'|"$BOT_EMAIL")
      gh pr comment "$n" --repo "$REPO" --body "Superseded by ${PR_URL}" \
        || echo "::warning::supersede comment on PR ${n} failed"
      gh pr close "$n" --repo "$REPO" \
        || echo "::warning::supersede close of PR ${n} failed"
      echo "superseded stale pin PR #${n}"
      ;;
    *) echo "::warning::open pin PR #${n} has a non-bot tip (login='${author:-<none>}') — left open for a human" ;;
  esac
done < <(jq -r --arg b "$BRANCH" \
  '.[] | select(.headRefName | startswith("soleur/inngest-pin-")) | select(.headRefName != $b) | "\(.number)|\(.headRefOid)"' \
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
elif [[ -n "$PR_NUM" ]]; then
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
