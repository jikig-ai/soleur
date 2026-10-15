#!/usr/bin/env bash
# vinngest-digest-freshness.sh — the scheduled published-digest reconciler
# (#4699), driven weekly by .github/workflows/scheduled-vinngest-digest-freshness.yml.
#
# WHAT IT COMPARES. For EVERY vinngest-v* tag merged into HEAD — the AC6
# selector minus its `tail -1`, so all merged tags, never just the max — it
# reads:
#   RECORDED — the digest the pin carried when the tag was last pinned,
#     derived from git pin history: `git log -G 'soleur-inngest-bootstrap:<T>@'`
#     over the two cloud-init files. Every bump commit is the publish
#     workflow's authored, crane-resolved, cross-checked record
#     (bump-inngest-bootstrap-pin.sh), so pin history IS "what the build
#     workflow recorded" — no second ledger to maintain or drift. The newest
#     -G hit for a SUPERSEDED tag is the bump-AWAY commit, whose tree no
#     longer pins it — the digest is extracted from `hit:` first, then `hit^:`.
#   LIVE — `crane digest "$IMAGE:$T"` against GHCR, retried with a bounded
#     timeout and parsed fail-closed to ^sha256:[0-9a-f]{64}$.
# and emits exactly ONE verdict row per tag — never zero rows, never a skipped
# tag (an empty tag set is a named failure, not a vacuous pass).
#
# WHY. AC6 asserts pin == semver-max tag NAME; it cannot see a tag's GHCR
# *content* move. A non-`mirror_only` workflow_dispatch re-publish of an
# existing tag (the designed CVE-base-image-rebuild escape hatch) moves that
# tag's digest while "tag exists" stays true everywhere — on a non-pinned tag
# that is invisible until someone pins it, and on the PINNED tag it orphans
# the pin's @sha256 (GHCR keeps it as an untagged manifest; zot's 5-tag
# retention can evict it — the bounded fuse the build workflow's own header
# names). This reconciler is the detector that makes movement non-silent. It
# RECORDS and ALERTS, never refuses: digest-moving republishes are sanctioned;
# the response to `moved` on the pinned tag is a NEW tag (never a re-pin to
# the moved digest) — inngest-server.md §Bootstrap-image release.
#
# VERDICT CLASSES AND EXIT CONTRACT (ruling D4).
#   per tag:   unchanged | moved | never-recorded | unresolvable
#   run-level: unmeasurable — an INSTRUMENT failure (crane transport/auth, an
#              unreadable or truncated history, an empty merged-tag set, an
#              unreadable pin file). Could-not-measure is NEVER a content
#              verdict (the QUERY_UNAVAILABLE precedent in
#              inngest-config-drift.yml).
#   moved or unresolvable on a PINNED tag     -> ::error::, result=findings, exit 1
#              (pinned = pinned by EITHER pin file — the bump sibling grades
#              against the max over both because they can diverge, #6536)
#   moved or unresolvable on a non-pinned tag -> ::warning::, result=findings, exit 0
#   never-recorded on a pinned tag            -> ::warning::, result=findings, exit 0
#              (a pin with no history record is unmeasurable-by-construction)
#   never-recorded on a non-pinned tag        -> summary row only (a merged tag
#              superseded before its bump merged was legitimately never pinned)
#   unmeasurable                              -> ::error::, result=unmeasurable, exit 2
#   xtrace refused with a live credential set -> exit 78 (#7797 taxonomy)
# When a tag is both never-recorded AND unresolvable, the CONTENT verdict
# (unresolvable) wins the row — the recorded side governs only the comparison.
#
# RESULT CONTRACT — exactly one terminal `result=` line, also written to
# $GITHUB_OUTPUT when set: ok | findings | unmeasurable. The workflow's Slack
# step branches on THIS output, NEVER `if: failure()` — the warning-class
# findings path exits 0.
#
# ENV SEAMS (D10, the BUMP_REPO_DIR convention — this script never runs from
# an untrusted tree, so no argv gate):
#   VDF_REPO_DIR   repo to read pin history from (default: cwd). The scheduled
#                  workflow checks out `fetch-depth: 0` + `fetch-tags: true` —
#                  both are required: the selector reads `git tag --merged`
#                  (fail-open on shallow, refused below) and the derivation
#                  walks history.
#   VDF_CRANE      crane binary (default: crane) — the fixture battery
#                  PATH-stubs it.
#   VDF_IMAGE      image name (default: ghcr.io/jikig-ai/soleur-inngest-bootstrap)
#   GITHUB_OUTPUT / GITHUB_STEP_SUMMARY honored when set.
set -uo pipefail

# xtrace refusal (#7797): GHCR auth reaches crane through the docker config the
# workflow's login step wrote; a traced run would print registry traffic and any
# token the caller's env happens to carry. Must be the FIRST thing after `set`.
case "$-" in
  *x*)
    if [ -n "${GH_TOKEN:+x}" ] || [ -n "${GITHUB_TOKEN:+x}" ]; then
      printf '[FATAL] refusing to trace with a live credential set (see #7797)\n' >&2
      printf '::error::args: xtrace with a live credential set refused (see #7797)\n' >&2
      printf 'result=unmeasurable\n'
      [[ -n "${GITHUB_OUTPUT:-}" ]] && printf 'result=unmeasurable\n' >> "$GITHUB_OUTPUT"
      exit 78
    fi
    ;;
esac
export LC_ALL=C

# Same leak class as the xtrace refusal: git's trace channels print request
# lines to stderr. Scrub them unconditionally so a debugging `env:` line cannot
# land them in logs. Also scrub git's object-store/config redirection envs —
# a polluted env could aim the history reads at a different repo than the
# pin-file greps read ($REPO_DIR).
unset GIT_TRACE GIT_TRACE_PACKET GIT_TRACE_PERFORMANCE GIT_TRACE_SETUP \
  GIT_TRACE_CURL GIT_TRACE_CURL_NO_DATA GIT_TRACE_REDACT GIT_TRACE2 \
  GIT_TRACE2_PERF GIT_TRACE2_EVENT GIT_CURL_VERBOSE GIT_HTTP_TRACE_AUTH_HEADER \
  GIT_DIR GIT_WORK_TREE GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM GIT_CONFIG_PARAMETERS \
  GIT_CONFIG_COUNT GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL
for _gv in $(env | sed -n 's/^\(GIT_CONFIG_KEY_[A-Za-z0-9_]*\)=.*/\1/p') \
           $(env | sed -n 's/^\(GIT_CONFIG_VALUE_[A-Za-z0-9_]*\)=.*/\1/p'); do
  unset "$_gv"
done
unset _gv

F_WEB='apps/web-platform/infra/cloud-init.yml'
F_DED='apps/web-platform/infra/cloud-init-inngest.yml'
IMAGE="${VDF_IMAGE:-ghcr.io/jikig-ai/soleur-inngest-bootstrap}"
CRANE="${VDF_CRANE:-crane}"

# Redirects go straight to the CI sink NAMES (GITHUB_OUTPUT /
# GITHUB_STEP_SUMMARY), never through an alias — the fixture-scan
# relative-operand rule exempts exactly those names.
emit_result() {
  printf 'result=%s\n' "$1"
  [[ -n "${GITHUB_OUTPUT:-}" ]] && printf 'result=%s\n' "$1" >> "$GITHUB_OUTPUT"
  return 0
}
summary() {
  [[ -n "${GITHUB_STEP_SUMMARY:-}" ]] && printf '%s\n' "$*" >> "$GITHUB_STEP_SUMMARY"
  return 0
}
# unmeasurable <msg...> — the could-not-measure class: exit 2, ::error::, and
# NEVER a per-tag content verdict. An instrument failure must not read as
# "the tags are fine" (silent green) or as "the tag is gone" (a false finding).
unmeasurable() {
  printf '::error::unmeasurable: %s\n' "$*" >&2
  emit_result unmeasurable
  summary "### vinngest digest freshness — UNMEASURABLE"$'\n\n'"$*"
  exit 2
}

# --- instrument preflight ----------------------------------------------------
command -v git >/dev/null 2>&1 || unmeasurable "git is required (pin-history derivation)"
command -v "$CRANE" >/dev/null 2>&1 || unmeasurable "crane is required (live digest resolution) — VDF_CRANE='${CRANE}' is not on PATH"

REPO_DIR="${VDF_REPO_DIR:-.}"
REPO_DIR=$(cd "$REPO_DIR" 2>/dev/null && pwd) \
  || unmeasurable "VDF_REPO_DIR '${VDF_REPO_DIR:-}' is not a directory"
: "${REPO_DIR:?VDF_REPO_DIR resolved empty}"
git -C "$REPO_DIR" rev-parse --git-dir >/dev/null 2>&1 \
  || unmeasurable "VDF_REPO_DIR '$REPO_DIR' is not a git repository"

# `git tag --merged HEAD` exits 0 on a shallow checkout and silently drops
# every tag below the graft (measured, #8782), so a truncated tag set would be
# reconciled as truth. Refuse BEFORE selecting, like the bump does.
shallow=$(git -C "$REPO_DIR" rev-parse --is-shallow-repository 2>/dev/null || true)
[[ "$shallow" == "false" ]] \
  || unmeasurable "the checkout is shallow (is-shallow-repository='${shallow:-<empty>}') — git tag --merged cannot see tags below the graft; the workflow needs fetch-depth: 0"
walk_err=$(git -C "$REPO_DIR" tag --merged HEAD --list 'vinngest-v*' 2>&1 >/dev/null || true)
[[ -z "$walk_err" ]] \
  || unmeasurable "git tag --merged reported an unreadable history ($(tr '\n' ' ' < <(printf '%s' "$walk_err") | tr -d '[:cntrl:]' | cut -c1-200)) — refusing rather than reconciling a truncated tag set"

# The pinned tag SET, read from BOTH pin files — the bump sibling grades the
# downgrade refusal against the max over both because the files can diverge
# (#6536), so a tag pinned by EITHER file is error-class here. A pin readable
# from neither file is an instrument failure: severity cannot be graded.
for f in "$F_DED" "$F_WEB"; do
  [[ -f "$REPO_DIR/$f" ]] \
    || unmeasurable "pin file $f is absent — severity cannot be graded without it"
done
PINNED_TAGS=$(for f in "$F_DED" "$F_WEB"; do
  grep -oE 'soleur-inngest-bootstrap:v[0-9]+\.[0-9]+\.[0-9]+' "$REPO_DIR/$f" 2>/dev/null | sed -n '1p' | sed 's/.*://'
done | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -u || true)
[[ -n "$PINNED_TAGS" ]] \
  || unmeasurable "could not read a pinned tag from either pin file ($F_DED, $F_WEB) — verdict severity cannot be graded"
PINNED_SET=" $(printf '%s\n' "$PINNED_TAGS" | tr '\n' ' ')"
PINNED_CSV=$(printf '%s\n' "$PINNED_TAGS" | paste -sd, -)
is_pinned() { case "$PINNED_SET" in *" $1 "*) return 0 ;; *) return 1 ;; esac; }

# --- selector: AC6-IDENTICAL minus `tail -1` — ALL merged tags (D3) ---------
# The bump script's byte-equality convention applies modulo the one intended
# delta: this reconciler exists precisely because the semver-max-only read is
# the blind spot.
VDF_TAGS=$(git -C "$REPO_DIR" tag --merged HEAD --list 'vinngest-v*' 2>/dev/null \
  | sed 's/^vinngest-//' | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' \
  | sort -V || true)
[[ -n "$VDF_TAGS" ]] \
  || unmeasurable "no vinngest-v* tag is merged into HEAD — an empty selector is a broken checkout (fetch-tags: true missing or a tagless clone), never a green run"

# Every pinned tag must be a member of the reconciled set — a pin pointing at a
# tag that is absent, unmerged, or was deleted would otherwise get no row at
# all while the run reads ok. That is a broken lifecycle invariant, not a
# content verdict.
VDF_SET=" $(printf '%s\n' "$VDF_TAGS" | tr '\n' ' ')"
while IFS= read -r _pt; do
  [[ -n "$_pt" ]] || continue
  case "$VDF_SET" in
    *" $_pt "*) : ;;
    *) unmeasurable "pinned tag $_pt is not a member of the merged vinngest-v* set — the tag is deleted, unpushed, or points off history; the reconciler cannot grade severity" ;;
  esac
done < <(printf '%s\n' "$PINNED_TAGS")

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# recorded_digest <tag> — prints `sha256:<64hex>` and returns 0 when the pin
# history carries a record; rc 1 = never-recorded (no -G hit at all); rc 3 = a
# hit whose neither side still carries `<tag>@sha256:` (a history-read oddity
# the run reports as unmeasurable).
recorded_digest() {
  local tag="$1" re hit rev f d gerr
  re=$(printf '%s' "$tag" | sed 's/\./\\./g')
  # The -G walk reads blobs — a corruption class the tag --merged preflight
  # does not reach. A mid-walk failure is an instrument failure (rc 3), never
  # never-recorded; `--diff-merges=first-parent` so a merge-conflict edit that
  # silently touched a pin cannot evade the walk.
  hit=$(git -C "$REPO_DIR" log --format=%H -n1 --no-patch --diff-merges=first-parent -G "soleur-inngest-bootstrap:${re}@" -- "$F_WEB" "$F_DED" 2>"$WORK/g.err" || true)
  gerr=$(cat "$WORK/g.err" 2>/dev/null || true)
  [[ -z "$gerr" ]] || return 3
  [[ -n "$hit" ]] || return 1
  for rev in "$hit" "${hit}^"; do
    for f in "$F_WEB" "$F_DED"; do
      if git -C "$REPO_DIR" show "${rev}:${f}" > "$WORK/blob" 2>/dev/null; then
        d=$(grep -oE "soleur-inngest-bootstrap:${re}@sha256:[0-9a-f]{64}" "$WORK/blob" | grep -oE 'sha256:[0-9a-f]{64}' | sort -u || true)
        if [[ -n "$d" ]]; then
          # Two distinct recorded digests for the same tag in one file would
          # make head -1 arbitrary — a divergent pin state, not a digest.
          [[ "$(printf '%s\n' "$d" | wc -l)" -eq 1 ]] || return 3
          printf '%s\n' "$d"; return 0
        fi
      fi
    done
  done
  return 3
}

# live_resolve <tag> — prints `sha256:<64hex>` on a resolvable tag; rc 4 =
# unresolvable (the registry answered, the manifest is gone); rc 5 = instrument
# failure (transport/auth/timeout/unparseable body) -> the caller goes
# unmeasurable, never a content verdict.
live_resolve() {
  local tag="$1" rc attempt d
  for attempt in 1 2 3; do
    rc=0
    timeout 60 "$CRANE" digest "$IMAGE:$tag" > "$WORK/digest" 2> "$WORK/digest.err" || rc=$?
    [[ "$rc" -eq 0 ]] && break
    [[ "$attempt" -lt 3 ]] && sleep $(( attempt * 2 ))
  done
  if [[ "$rc" -ne 0 ]]; then
    # Only the registry's own body codes are CONTENT (the tag names nothing).
    # A bare "404"/"Not Found" in stderr can equally be a transport/front-door
    # failure mid-incident — those must stay INSTRUMENT (rc 5), never read as
    # the tag being gone.
    if grep -qE 'MANIFEST_UNKNOWN|NAME_UNKNOWN' "$WORK/digest.err" 2>/dev/null; then
      return 4
    fi
    return 5
  fi
  d=$(grep -oE '^sha256:[0-9a-f]{64}$' "$WORK/digest" | head -1 || true)
  [[ -n "$d" ]] || return 5
  printf '%s\n' "$d"
}

# --- reconcile ----------------------------------------------------------------
N_TAGS=0
FINDINGS_ERR=0
FINDINGS_WARN=0
: > "$WORK/table"
while IFS= read -r T; do
  [[ -n "$T" ]] || continue
  N_TAGS=$((N_TAGS + 1))

  rec="" rec_status=""
  if rec=$(recorded_digest "$T"); then
    rec_status=recorded
  else
    rrc=$?
    case "$rrc" in
      1) rec_status=never-recorded ;;
      *) unmeasurable "pin-history derivation failed for ${T}: a -G hit exists but neither the hit nor its parent carries 'soleur-inngest-bootstrap:${T}@sha256:'" ;;
    esac
  fi

  live=""
  if live=$(live_resolve "$T"); then
    live_status=resolved
  else
    lrc=$?
    case "$lrc" in
      4) live_status=unresolvable ;;
      *) unmeasurable "crane could not measure ${IMAGE}:${T} after 3 attempts (rc=${lrc}): $(tr '\n' ' ' < "$WORK/digest.err" | tr -d '[:cntrl:]' | cut -c1-200)" ;;
    esac
  fi

  # Content verdict wins over the recorded side: a tag whose manifest is gone
  # reports unresolvable whether or not pin history ever recorded it.
  case "$live_status" in
    unresolvable) verdict=unresolvable ;;
    resolved)
      case "$rec_status" in
        never-recorded) verdict=never-recorded ;;
        recorded)
          if [[ "$live" == "$rec" ]]; then verdict=unchanged; else verdict=moved; fi ;;
      esac ;;
  esac

  printf 'tag=%s verdict=%s recorded=%s live=%s\n' "$T" "$verdict" "${rec:-none}" "${live:-none}"
  printf '| `%s` | %s | `%s` | `%s` |\n' "$T" "$verdict" "${rec:-—}" "${live:-—}" >> "$WORK/table"

  case "$verdict" in
    never-recorded)
      if is_pinned "$T"; then
        printf '::warning::tag=%s verdict=never-recorded — the PINNED tag has no pin-history record (unmeasurable by construction): live digest %s. Check the pin history before assuming clean.\n' "$T" "${live:-<unresolvable>}"
        FINDINGS_WARN=1
      fi ;;
    moved|unresolvable)
      if is_pinned "$T"; then
        printf '::error::tag=%s verdict=%s — the PINNED tag %s: live digest %s vs recorded %s. The cloud-init pin is orphaned (zot retention can evict the untagged manifest); the response is a NEW tag, never a re-pin to moved content — inngest-server.md §Bootstrap-image release.\n' \
          "$T" "$verdict" "$T" "${live:-<unresolvable>}" "${rec:-<none>}"
        FINDINGS_ERR=1
      else
        printf '::warning::tag=%s verdict=%s — non-pinned tag: live digest %s vs recorded %s (a sanctioned re-publish moves a digest; the check exists so the movement is never silent).\n' \
          "$T" "$verdict" "${live:-<unresolvable>}" "${rec:-<none>}"
        FINDINGS_WARN=1
      fi ;;
  esac
done < <(printf '%s\n' "$VDF_TAGS")

printf 'tags=%s pinned=%s findings_err=%s findings_warn=%s\n' \
  "$N_TAGS" "$PINNED_CSV" "$FINDINGS_ERR" "$FINDINGS_WARN"

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  {
    printf '### vinngest published-digest freshness\n\n'
    printf 'Reconciler: live `crane digest` per merged `vinngest-v*` tag vs the digest its pin history recorded (the bump commits are the publish workflow'"'"'s authored record). Pinned tag(s): `%s`.\n\n' "$PINNED_CSV"
    printf '| tag | verdict | recorded | live |\n|---|---|---|---|\n'
    cat "$WORK/table"
  } >> "$GITHUB_STEP_SUMMARY"
fi

if (( FINDINGS_ERR == 1 )); then
  emit_result findings
  exit 1
fi
if (( FINDINGS_WARN == 1 )); then
  emit_result findings
  exit 0
fi
emit_result ok
exit 0
