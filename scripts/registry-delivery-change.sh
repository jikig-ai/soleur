#!/usr/bin/env bash
# Which merged change(s) does this registry-host-replace dispatcher run deliver? (#8279)
#
# The dispatcher (.github/workflows/registry-host-replace-dispatch.yml) fires on every push to
# main whose rendered cloud-init-registry.yml differs, but its delta gate compares against a
# DELIVERY WATERMARK — the head of the last SUCCESSFUL run — not against `github.event.before`.
# So one run's range routinely spans many unrelated merges (21, measured between the runs of
# 2026-09-17 and 2026-09-18), and "the change this run delivers" is NOT `github.sha`: it is the
# intersection of that range with the commits that touched the config path. This helper computes
# that intersection and attributes each candidate to the PR that introduced it, so the dispatch
# reason, the refusal artifact and its comment target can name the real change instead of a
# number frozen at the time the workflow was written (the #7555/#7556 defect).
#
# ── THE RANGE CONTRACT ──────────────────────────────────────────────────────────────────────
#   proven    the compare API says `before` is an ancestor of `after` (`status` ahead|identical)
#             and its `.commits` list is complete (total_commits <= 250 — the list is capped at
#             250 ONLY when the call carries no paging parameter; adding `per_page` switches the
#             endpoint to 30-per-page pagination and `.commits` silently becomes page 1, so the
#             compare call below deliberately passes NONE).
#   unproven  no watermark, compare failed, `diverged`/`behind`, > 250 commits, the path listing
#             failed — candidates degrade to [after] alone and `range_note` says why. Never an
#             error: a derivation failure must never turn a deliverable push into a red run.
#
# `identical` is a PROVEN range with zero commits (measured: `compare/X...X` returns
# `status=identical, total_commits=0, commits=[]`) — a manual re-fire at the watermark SHA. It
# falls through to the empty-intersection arm and needs no enum value of its own.
#
# EMPTY INTERSECTION ON A PROVEN RANGE yields NO PR. The gate can reach this helper when the
# compare's 300-file cap made it deliver "unproven", or on a manual re-fire, or on the workflow
# file's own registration push. Attributing to whatever merged last would post "PR #N is NOT live"
# on a PR that never touched the config — a new instance of the defect this helper removes.
#
# MERGE-COMMIT PRs need no special arm (measured on #6326): `commits?path=` applies git history
# simplification and returns the BRANCH commit, never the merge commit; the compare range lists
# both; `commits/<branch sha>/pulls` resolves to the PR; the dedupe below collapses a multi-commit
# branch to one PR, and the subject shown is the NEWEST branch commit's (not the PR title).
#
# THE SUBJECT FALLBACK IS ANCHORED TO THE SQUASH SUFFIX — `(#N)` at end of line only. The
# precedent in .github/workflows/reusable-release.yml uses `(?=\))` unanchored, which returns the
# FIRST parenthesised number: `fix: see (#7556) (#8301)` would post on #7556, and a direct push
# could name any issue in the repo as its tracker. Contributor-controlled text picks nothing here.
#
# THE TEST SEAM IS REFUSED ON THE PRODUCTION PATH. REGISTRY_DELIVERY_GH_CMD replaces `gh` for the
# unit suite; set inside GitHub Actions it could manufacture any attribution, so it exits 1 with a
# ::error:: — the same guard scripts/registry-replace-preflight.sh applies to its own seams.
#
# Output: six `key=value` lines, one each, in this order, on every non-refused arm:
#   range=proven|unproven
#   range_note=<why unproven / attribution caveats, `; `-joined; empty when nothing to say>
#   commits=<sha> <sha>      candidates oldest -> newest (empty on a proven empty intersection)
#   prs=<n> <n>              unique PR numbers, first-seen order (oldest -> newest)
#   unattributed=<sha> ...   candidates with no PR (direct push, no `(#N)` suffix)
#   summary=PR #N (<subject>); commit <sha7> (<subject>)   one line, control characters stripped,
#                                                            each subject capped at 200 characters
# Exit 0 on every arm the API can produce; 2 on a usage error; 1 on the seam refusal.
#
# Usage: scripts/registry-delivery-change.sh --repo <owner/name> --after <sha> [--before <sha>] [--path <file>]

set -uo pipefail

usage() {
  echo "usage: registry-delivery-change.sh --repo <owner/name> --after <sha> [--before <sha>] [--path <file>]" >&2
}

REPO=""; AFTER=""; BEFORE=""
CFG="apps/web-platform/infra/cloud-init-registry.yml"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)   REPO="${2:-}"; shift 2 ;;
    --after)  AFTER="${2:-}"; shift 2 ;;
    --before) BEFORE="${2:-}"; shift 2 ;;
    --path)   CFG="${2:-}"; shift 2 ;;
    -h|--help) sed -n '1,50p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "registry-delivery-change: unknown argument '$1'" >&2; usage; exit 2 ;;
  esac
done
if [[ -z "$REPO" || -z "$AFTER" ]]; then usage; exit 2; fi

if [[ -n "${GITHUB_ACTIONS:-}" && -n "${REGISTRY_DELIVERY_GH_CMD:-}" ]]; then
  echo "::error::registry-delivery-change: REGISTRY_DELIVERY_GH_CMD is set inside GitHub Actions. A seam on the production path can manufacture an attribution. Refusing." >&2
  exit 1
fi
GH="${REGISTRY_DELIVERY_GH_CMD:-gh}"

# Bounds the per-candidate /pulls lookups on a pathological range. A constant, not a flag: the
# per_page=100 on the path listing is the outer bound, and nothing legitimately needs more.
MAX_LOOKUPS=10

is_sha() { [[ "$1" =~ ^[0-9a-f]{40}$ ]]; }

NOTES=()
note() { NOTES+=("$1"); }

# One line: the first message line, with CR/LF, C0 controls, DEL and the U+2028/U+2029
# separators removed (cq-regex-unicode-separators-escape-only), then CAPPED at 200 characters.
# The cap is load-bearing: git does not bound a subject line, and workflow_dispatch inputs are
# capped at 65,535 characters in total (docs.github.com, workflow-syntax) — ten uncapped subjects
# in the dispatch `reason` could make `gh workflow run` fail, a red run that STICKS (the
# watermark does not advance, so every later push re-derives the same range).
clean_subject() {
  # LC_ALL=C so the byte-range bracket matches the UTF-8 bytes of U+2028/U+2029; under a UTF-8
  # locale sed reads them as one character and the bracket expression never matches.
  local s
  s="$(printf '%s' "$1" | head -n 1 | LC_ALL=C tr -d '\000-\037\177' | LC_ALL=C sed 's/\xe2\x80[\xa8\xa9]//g')"
  printf '%s' "${s:0:200}"
}

# Every SHA the helper places in a URL path is validated first; the API is trusted for shape,
# not for content. gh's own -f/-F encoding carries query fields; nothing is string-built.
api() { "$GH" api "$@" 2>/dev/null; }

RANGE="unproven"
CANDIDATES=()          # oldest -> newest
declare -A SUBJECT=()  # sha -> first message line (from the path listing)

if ! is_sha "$AFTER"; then
  # A malformed `after` can only come from a caller bug; it never reaches a URL. Degrade rather
  # than exit non-zero: the workflow's consumers default when the helper prints nothing useful.
  note "malformed --after"
elif [[ -z "$BEFORE" ]]; then
  note "no watermark"
  CANDIDATES=("$AFTER")
elif ! is_sha "$BEFORE"; then
  note "malformed --before"
  CANDIDATES=("$AFTER")
else
  crc=0
  # NO paging parameter here — see the header. `--jq` is not used on the raw call so the seam stub
  # can answer with plain JSON; every filter below is a static jq program.
  cmp_json="$(api "repos/${REPO}/compare/${BEFORE}...${AFTER}")" || crc=$?
  status=""; total=""
  if [[ "$crc" -eq 0 ]]; then
    status="$(printf '%s' "$cmp_json" | jq -r '.status // ""' 2>/dev/null || echo "")"
    total="$(printf '%s' "$cmp_json" | jq -r '.total_commits // 0' 2>/dev/null || echo 0)"
  fi
  if [[ "$crc" -ne 0 ]]; then
    note "compare rc=${crc}"
    CANDIDATES=("$AFTER")
  elif [[ "$status" != "ahead" && "$status" != "identical" ]]; then
    note "compare status ${status:-unreadable}"
    CANDIDATES=("$AFTER")
  elif [[ ! "$total" =~ ^[0-9]+$ || "$total" -gt 250 ]]; then
    note "compare .commits capped at 250 (total_commits=${total})"
    CANDIDATES=("$AFTER")
  else
    # Range set, validated sha by sha. A malformed entry is dropped and named, never interpolated.
    range_file="$(mktemp)"; trap 'rm -f "${range_file:-}" "${touch_file:-}"' EXIT
    malformed=0
    while IFS= read -r s; do
      [[ -n "$s" ]] || continue
      if is_sha "$s"; then printf '%s\n' "$s" >> "$range_file"; else malformed=$((malformed+1)); fi
    done < <(printf '%s' "$cmp_json" | jq -r '.commits[]?.sha // empty' 2>/dev/null || true)
    prc=0
    path_json="$(api -X GET "repos/${REPO}/commits" -f sha="$AFTER" -f path="$CFG" -F per_page=100)" || prc=$?
    if [[ "$prc" -ne 0 ]]; then
      note "path listing rc=${prc}"
      CANDIDATES=("$AFTER")
    else
      RANGE="proven"
      # The listing is newest -> oldest; keep it as a lookup and order candidates by the RANGE
      # (oldest -> newest), so a coalesced delivery reads in merge order.
      touch_file="$(mktemp)"
      # The message travels base64-encoded on one line: @tsv would re-escape the backslashes a
      # JSON-encoded subject already carries, and a subject with a `"` then fails to decode.
      while IFS=' ' read -r s m; do
        [[ -n "$s" ]] || continue
        is_sha "$s" || { malformed=$((malformed+1)); continue; }
        printf '%s\n' "$s" >> "$touch_file"
        SUBJECT["$s"]="$(printf '%s' "$m" | base64 -d 2>/dev/null || true)"
      done < <(printf '%s' "$path_json" | jq -r '.[]? | "\(.sha) \(.commit.message // "" | @base64)"' 2>/dev/null || true)
      while IFS= read -r s; do
        [[ -n "$s" ]] || continue
        grep -Fxq -- "$s" "$touch_file" && CANDIDATES+=("$s")
      done < "$range_file"
      if [[ "${#CANDIDATES[@]}" -eq 0 ]]; then
        note "no commit in range touched ${CFG}"
      fi
    fi
    # After BOTH loops: the path listing is validated too, and a note emitted between them
    # would miss its count.
    [[ "$malformed" -gt 0 ]] && note "malformed sha from API dropped (${malformed})"
  fi
fi

# Cap the lookups: keep the NEWEST MAX_LOOKUPS candidates.
if [[ "${#CANDIDATES[@]}" -gt "$MAX_LOOKUPS" ]]; then
  dropped=$(( ${#CANDIDATES[@]} - MAX_LOOKUPS ))
  CANDIDATES=("${CANDIDATES[@]: -$MAX_LOOKUPS}")
  note "${dropped} older candidate(s) not looked up (MAX_LOOKUPS=${MAX_LOOKUPS})"
fi

# resolve_pr_for_sha <sha> -> sets PR_OUT (the PR number, or empty) and BY_SUBJECT (1 when the
# anchored subject fallback attributed it). Called DIRECTLY, never as `$(...)`: a command
# substitution runs in a subshell and would discard BY_SUBJECT. The `/pulls` shape is verbatim
# from the repo's three single-SHA resolvers (reusable-release.yml et al.) —
# `.[0].number // empty`, then digit-validated.
resolve_pr_for_sha() {
  local sha="$1" n=""
  PR_OUT=""; BY_SUBJECT=0
  n="$(api "repos/${REPO}/commits/${sha}/pulls" | jq -r '.[0].number // empty' 2>/dev/null || true)"
  if [[ -n "$n" && "$n" =~ ^[0-9]+$ ]]; then PR_OUT="$n"; return 0; fi
  n="$(printf '%s' "${SUBJECT[$sha]:-}" | head -n 1 | tr -d '\r' | grep -oP '\(#\K\d+(?=\)$)' || true)"
  if [[ -n "$n" ]]; then BY_SUBJECT=1; PR_OUT="$n"; fi
  return 0
}

PRS=()            # first-seen order
declare -A PR_SUBJECT=()   # pr -> subject of the NEWEST commit attributed to it
UNATTR=()
declare -A UNATTR_SUBJECT=()
subject_noted=0
for sha in "${CANDIDATES[@]+"${CANDIDATES[@]}"}"; do
  if [[ -z "${SUBJECT[$sha]+x}" ]]; then
    # The [after]-only arms have no listing entry: read the commit itself for its subject.
    SUBJECT["$sha"]="$(api "repos/${REPO}/commits/${sha}" | jq -r '.commit.message // ""' 2>/dev/null || true)"
  fi
  subj="$(clean_subject "${SUBJECT[$sha]}")"
  resolve_pr_for_sha "$sha"; pr="$PR_OUT"
  if [[ -n "$pr" ]]; then
    if [[ "$BY_SUBJECT" -eq 1 && "$subject_noted" -eq 0 ]]; then
      note "PR #${pr} attributed by commit subject, not by the API"; subject_noted=1
    fi
    seen=0; for p in "${PRS[@]+"${PRS[@]}"}"; do [[ "$p" == "$pr" ]] && seen=1; done
    [[ "$seen" -eq 0 ]] && PRS+=("$pr")
    PR_SUBJECT["$pr"]="$subj"   # newest wins: candidates are walked oldest -> newest
  else
    UNATTR+=("$sha"); UNATTR_SUBJECT["$sha"]="$subj"
  fi
done

# Summary: one `PR #N (<subject>)` per PR, then one `commit <sha7> (<subject>)` per unattributed
# commit, `; `-joined. A proven empty intersection names the SHA and the watermark instead, so no
# arm produces an empty description and none names a PR that did not change the config.
parts=()
for p in "${PRS[@]+"${PRS[@]}"}"; do parts+=("PR #${p} (${PR_SUBJECT[$p]})"); done
for s in "${UNATTR[@]+"${UNATTR[@]}"}"; do parts+=("commit ${s:0:7} (${UNATTR_SUBJECT[$s]})"); done
if [[ "${#parts[@]}" -gt 0 ]]; then
  SUMMARY="$(IFS='; '; printf '%s' "${parts[*]}")"
elif [[ "$RANGE" == "proven" ]]; then
  SUMMARY="the ${CFG##*/} user_data at ${AFTER:0:7} (unchanged since the delivery watermark ${BEFORE:0:7})"
else
  SUMMARY="the ${CFG##*/} user_data at ${AFTER:0:7}"
fi
# Every part was cleaned and capped individually; the join and the fixed text carry nothing
# to strip, and a whole-summary cap would truncate a coalesced multi-PR summary.

printf 'range=%s\n' "$RANGE"
printf 'range_note=%s\n' "$(IFS='; '; printf '%s' "${NOTES[*]+"${NOTES[*]}"}")"
printf 'commits=%s\n' "${CANDIDATES[*]+"${CANDIDATES[*]}"}"
printf 'prs=%s\n' "${PRS[*]+"${PRS[*]}"}"
printf 'unattributed=%s\n' "${UNATTR[*]+"${UNATTR[*]}"}"
printf 'summary=%s\n' "$SUMMARY"
exit 0
