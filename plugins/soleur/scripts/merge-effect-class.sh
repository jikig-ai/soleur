#!/usr/bin/env bash
# merge-effect-class.sh --files-from <path|->   one changed path per line (list BOTH sides of a rename)
# merge-effect-class.sh --pr <N> [--repo OWNER/REPO]
# merge-effect-class.sh --print-witnesses       one concrete allowlisted path per allowlist entry
# merge-effect-class.sh --filter-allowed        stdin list -> the well-formed paths the allowlist admits
# merge-effect-class.sh --self-check            liveness signal only, NOT proof of the property
#
# Decides, from the files a pull request changes, whether merging it can fire a path-gated production
# workflow. Read-only: it writes only to a private temp directory, prints no file contents and, in the verdict
# modes, echoes no path (#10923, ADR-302).
#
# VERDICT. In the two verdict modes (--files-from, --pr) exactly one stdout line: `production-effecting` or
# `not-production-effecting`.
#   exit 0  not-production-effecting  (the ONLY way to read "not" from a verdict mode)
#   exit 1  production-effecting
#   exit 2  unusable input or usage; stdout is STILL `production-effecting`
# So a caller that reads only the exit status, or only stdout, cannot read "not" from a failure. `emit` is the
# one writer of a verdict line. The other modes (--help, --print-witnesses, --filter-allowed, --self-check)
# print no verdict line and may exit 0, so a caller must use a verdict mode. Residual: a SIGKILL between the
# stdout write and the exit leaves the verdict line without its exit status; callers compare BOTH.
#
# MEANING. `not-production-effecting` means "no path-gated production workflow fires from this file list",
# where "fires" means performs a production act through a path filter. It does NOT mean "no runtime effect"
# (scheduled crons reading knowledge-base/, build-time reads of root files and per-merge bookkeeping
# workflows are out of scope by design; see ADR-302). web-platform-release.yml's workflow_run arm runs after
# every main CI run; it is accepted because its inner path check decides whether it deploys, and the parity
# test models it by its own push.paths while pinning (via the P3/P1 assertions) that the two agree. The verdict
# authorizes nothing and is never evidence in an envelope `Gate:` or a receipt.
#
# ALLOWLIST (closed world). Every path, both sides of a rename, must be under knowledge-base/ or be a
# root-level *.md, except any path whose basename is AGENTS*.md, CLAUDE*.md or GEMINI*.md in any letter case
# and at any depth (agent-steering files steer every agent session). Everything else, including every
# unknown path and this script's own files, is effecting. The arrays below are the ONLY definition:
# is_allowed(), --print-witnesses and --filter-allowed all read them, and the CI parity test
# (plugins/soleur/test/merge-effect-class-parity.test.sh) checks them against the workflows.
#
# SCOPE. --files-from, --print-witnesses, --filter-allowed and --self-check are pure. The --files-from
# verdict is meaningful only for the Soleur repository, whose workflows the allowlist was checked against.
# --pr additionally requires the repo-owned .github/workflows/web-platform-release.yml, the ci-only list
# tracked at HEAD and (with --repo, an assertion about the current repository, not a selector) the current
# repository, else exit 2 reason=not-applicable. --pr judges the file list of one OPEN pull request to main
# for an interactive merge or ready; the caller must merge with --match-head-commit and the sha printed on
# stderr. Dispatches and not-yet-created revert PRs are out of scope. --self-check proves liveness only: its
# probes and the allowlist live in this one file. Test seams: MEC_CI_ONLY_LIST (--self-check only). The
# `# mut:<name>` markers are read by merge-effect-class.test.sh (and `# mut:widen` by the parity test); keep each
# on its own single line.
#
# --pr takes the fetch shape of admin-merge-ready.sh (`gh pr view`, then `gh api --paginate --slurp` of the
# files, shape-checked with `jq -e`, the count compared with `changedFiles`; the API caps at 3000). That
# script does not shape-validate previous_filename or scan for control characters; this one does, so a fix in
# either belongs in both.
#
# stderr: `merge-effect-class: <verdict> reason=<token>[ sha=<head sha>]`. Tokens: allowlisted,
# outside-allowlist, empty-list, bad-path, incomplete-list, list-unreadable, tool-missing, not-open,
# base-mismatch, head-moved, not-applicable, usage. No path text is ever echoed. This is deliberately not a
# SOLEUR_* marker: it runs on the user's own CLI and no hosted code reads it.
#
# Portable to bash 3.2: no mapfile, associative arrays, ${var,,} or sed -i. Needs jq (>= 1.5) and a gh that
# supports `--slurp` for --pr.
set -uo pipefail
export LC_ALL=C

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly HERE
readonly CI_ONLY_REL="plugins/soleur/scripts/merge-effect-class.ci-only.tsv"
readonly SENTINEL_REL=".github/workflows/web-platform-release.yml"
readonly MAX_FILES=3000

ALLOW_PREFIXES=("knowledge-base/")  # mut:widen
ALLOW_ROOT_EXT=(".md")
readonly ALLOW_ROOT_EXT

WORK=""
SHA_OUT=""
cleanup() {
  [[ -n "$WORK" ]] || return 0
  rm -rf "${WORK:?}"
}
trap cleanup EXIT

emit() { # emit <rc> <reason>
  local rc="$1" reason="$2" verdict="production-effecting" extra=""
  if [ "$rc" -eq 0 ]; then verdict="not-production-effecting"; fi # mut:exit2-not
  if [ -n "$SHA_OUT" ]; then extra=" sha=$SHA_OUT"; fi
  printf 'merge-effect-class: %s reason=%s%s\n' "$verdict" "$reason" "$extra" >&2
  printf '%s\n' "$verdict" || exit 2
  exit "$rc"
}

usage() {
  cat <<'EOF'
usage: merge-effect-class.sh --files-from <path|->
       merge-effect-class.sh --pr <N> [--repo OWNER/REPO]
       merge-effect-class.sh --print-witnesses
       merge-effect-class.sh --filter-allowed        (stdin list -> admitted paths)
       merge-effect-class.sh --self-check

Verdict modes (--files-from, --pr) print exactly one line, production-effecting or
not-production-effecting. Exit 0 ONLY for the second; exit 1 for the first; exit 2 for unusable input
(stdout is still production-effecting). The --files-from verdict is meaningful only for the Soleur
repository. --pr judges one OPEN pull request to main and needs the Soleur repository as the current
directory. For a local branch before a PR exists:
  git diff --name-only --no-renames origin/main...HEAD | merge-effect-class.sh --files-from -
(list both sides of a rename; this form has no head-sha binding, so it is advisory). --self-check is a
liveness signal, not proof of the property.
EOF
}

usage_error() {
  usage >&2
  emit 2 usage
}

# 0 when the path is malformed (the caller then exits 2); 1 when it is well formed.
is_bad_path() {
  local p="$1" seg rest
  if [ -z "$p" ]; then return 0; fi
  case "$p" in /* | \"*) return 0 ;; esac
  case "$p" in *[[:cntrl:]]* | *\\*) return 0 ;; esac
  case "$p" in */) return 0 ;; esac
  rest="$p"
  while :; do
    seg="${rest%%/*}"
    case "$seg" in '' | . | ..) return 0 ;; esac
    case "$rest" in */*) rest="${rest#*/}" ;; *) break ;; esac
  done
  return 1
}

is_allowed() {
  local p="$1" base="${1##*/}" pre ext
  case "$base" in
    [Aa][Gg][Ee][Nn][Tt][Ss]*.[Mm][Dd] | [Cc][Ll][Aa][Uu][Dd][Ee]*.[Mm][Dd] | [Gg][Ee][Mm][Ii][Nn][Ii]*.[Mm][Dd]) return 1 ;;
  esac
  for pre in "${ALLOW_PREFIXES[@]}"; do
    case "$p" in "$pre"?*) return 0 ;; esac
  done
  case "$p" in */*) return 1 ;; esac # mut:no-slash-guard
  for ext in "${ALLOW_ROOT_EXT[@]}"; do
    case "$p" in *"$ext") return 0 ;; esac
  done
  return 1
}

# The chokepoint. Every input gate runs before is_allowed(); `emit` is the only exit.
has_nul() { # $1 = file; 0 when it holds a NUL byte, 1 when not, 2 when the check itself failed
  local total stripped
  total="$(wc -c <"$1" | tr -d ' ')" || return 2
  stripped="$(tr -d '\000' <"$1" | wc -c | tr -d ' ')" || return 2
  [ "$total" != "$stripped" ]
}

classify_file() { # $1 = file holding one path per line
  local l n=0 m=0 all_ok=1 nul_rc=0
  # bash `read` drops NUL silently, so a NUL-joined pair of paths would be judged as one concatenated path.
  has_nul "$1" || nul_rc=$?
  case "$nul_rc" in 0) emit 2 bad-path ;; 1) ;; *) emit 2 list-unreadable ;; esac
  while IFS= read -r l || [ -n "$l" ]; do
    n=$((n + 1))
    if is_bad_path "$l"; then emit 2 bad-path; fi
  done <"$1"
  if [ "$n" -eq 0 ]; then emit 2 empty-list; fi
  while IFS= read -r l || [ -n "$l" ]; do
    m=$((m + 1))
    if is_allowed "$l"; then continue; fi # mut:first-only
    all_ok=0
  done <"$1"
  # The second pass must see every line the first pass saw; a pass that did not run (or stopped early) must
  # never default to "everything was allowed". Defensive: no fixture can make the second read of the same
  # regular file fail (it needs an I/O error between the two reads), so merge-effect-class.test.sh records this
  # guard under "accepted equivalent mutants" instead of pinning it.
  if [ "$m" -ne "$n" ]; then emit 2 list-unreadable; fi
  if [ "$all_ok" -eq 1 ]; then emit 0 allowlisted; fi
  emit 1 outside-allowlist
}

need() {
  local c
  for c in "$@"; do
    command -v "$c" >/dev/null 2>&1 || emit 2 tool-missing
  done
}

cmd_files_from() { # $1 = path or -
  WORK="$(mktemp -d)" || emit 2 list-unreadable
  if [ "$1" = "-" ]; then
    cat >"$WORK/list" || emit 2 list-unreadable
  else
    if [ ! -f "$1" ] || [ ! -r "$1" ]; then emit 2 list-unreadable; fi
    cp "$1" "$WORK/list" || emit 2 list-unreadable
  fi
  classify_file "$WORK/list" # mut:gutted
}

top_of_repo() {
  env -u GIT_DIR -u GIT_WORK_TREE -u GIT_CEILING_DIRECTORIES git rev-parse --show-toplevel 2>/dev/null
}

cmd_pr() { # $1 = PR number, $2 = --repo value or empty
  local n="$1" want_repo="$2" top have pr_json state base head head2 changed files_json nfiles cc_rc
  need gh jq git
  top="$(top_of_repo)" || emit 2 not-applicable
  if [ -z "$top" ] || [ ! -f "$top/$SENTINEL_REL" ]; then emit 2 not-applicable; fi
  env -u GIT_DIR -u GIT_WORK_TREE -u GIT_CEILING_DIRECTORIES git -C "$top" cat-file -e "HEAD:$CI_ONLY_REL" 2>/dev/null \
    || emit 2 not-applicable
  if [ -n "$want_repo" ]; then
    have="$(gh repo view --json nameWithOwner 2>/dev/null)" || emit 2 not-applicable
    have="$(jq -r '.nameWithOwner // empty' <<<"$have" 2>/dev/null)" || emit 2 not-applicable
    if [ -z "$have" ] || [ "$have" != "$want_repo" ]; then emit 2 not-applicable; fi
  fi
  WORK="$(mktemp -d)" || emit 2 list-unreadable

  pr_json="$(gh pr view "$n" --json state,baseRefName,headRefOid,changedFiles 2>/dev/null)" || emit 2 list-unreadable
  jq -e 'type == "object" and (.state | type) == "string" and (.baseRefName | type) == "string"
         and (.headRefOid | type) == "string"
         and (.changedFiles | type) == "number" and (.changedFiles | floor) == .changedFiles and .changedFiles >= 0' \
    <<<"$pr_json" >/dev/null 2>&1 || emit 2 list-unreadable
  state="$(jq -r '.state' <<<"$pr_json")" || emit 2 list-unreadable
  base="$(jq -r '.baseRefName' <<<"$pr_json")" || emit 2 list-unreadable
  head="$(jq -r '.headRefOid' <<<"$pr_json")" || emit 2 list-unreadable
  changed="$(jq -r '.changedFiles' <<<"$pr_json")" || emit 2 list-unreadable
  case "$changed" in '' | *[!0-9]*) emit 2 list-unreadable ;; esac
  # a run of digits too long for the shell's integer tests would make `[ -ge ]` error and skip the guard
  if [ "${#changed}" -gt 6 ]; then emit 2 list-unreadable; fi
  case "$head" in
    *[!0-9a-f]* | '') emit 2 list-unreadable ;;
  esac
  if [ "${#head}" -ne 40 ]; then emit 2 list-unreadable; fi
  SHA_OUT="$head"
  if [ "$state" != "OPEN" ]; then emit 2 not-open; fi
  if [ "$base" != "main" ]; then emit 2 base-mismatch; fi

  files_json="$(gh api --paginate --slurp "repos/{owner}/{repo}/pulls/$n/files?per_page=100" 2>/dev/null)" \
    || emit 2 list-unreadable
  jq -e 'type == "array" and all(.[]; type == "array")
         and ([.[][]] | all(type == "object" and (.filename | type) == "string" and (.filename | length) > 0
              and (.status | type) == "string"
              and ((.previous_filename // "") | type) == "string"
              and (if .status == "renamed" or .status == "copied"
                   then (.previous_filename | type) == "string" and (.previous_filename | length) > 0
                   else true end)))' \
    <<<"$files_json" >/dev/null 2>&1 || emit 2 list-unreadable
  nfiles="$(jq -r '[.[][]] | length' <<<"$files_json")" || emit 2 list-unreadable
  if [ "$changed" -ge "$MAX_FILES" ] || [ "$nfiles" -ne "$changed" ]; then emit 2 incomplete-list; fi
  cc_rc=0
  jq -e '[.[][] | (.filename, (.previous_filename // empty)) | explode | any(. < 32 or . == 127)] | any' \
    <<<"$files_json" >/dev/null 2>&1 || cc_rc=$?
  case "$cc_rc" in
    0) emit 2 bad-path ;;
    1) ;;
    *) emit 2 list-unreadable ;;
  esac
  jq -r '[.[][] | .filename, (.previous_filename // empty)] | .[]' <<<"$files_json" >"$WORK/list" || emit 2 list-unreadable # mut:drop-prev

  head2="$(gh pr view "$n" --json headRefOid 2>/dev/null)" || emit 2 list-unreadable
  head2="$(jq -r '.headRefOid // empty' <<<"$head2" 2>/dev/null)" || emit 2 list-unreadable
  if [ "$head2" != "$head" ]; then emit 2 head-moved; fi
  classify_file "$WORK/list"
}

cmd_print_witnesses() {
  local pre ext
  for pre in "${ALLOW_PREFIXES[@]}"; do printf '%s\n' "${pre}witness/deep.md"; done
  for ext in "${ALLOW_ROOT_EXT[@]}"; do printf '%s\n' "WITNESS${ext}"; done
  exit 0
}

cmd_filter_allowed() {
  local l nul_rc=0
  WORK="$(mktemp -d)" || exit 2
  cat >"$WORK/list" || exit 2
  has_nul "$WORK/list" || nul_rc=$?
  if [ "$nul_rc" -ne 1 ]; then
    echo "merge-effect-class: --filter-allowed refused its input (NUL byte or unreadable)" >&2
    exit 2
  fi
  while IFS= read -r l || [ -n "$l" ]; do
    if is_bad_path "$l"; then continue; fi
    if is_allowed "$l"; then printf '%s\n' "$l"; fi
  done <"$WORK/list"
  exit 0
}

probe_rc() { # $1 = newline-separated list text; prints the classify rc
  local f="$WORK/probe" rc=0
  printf '%s' "$1" >"$f"
  (classify_file "$f") >/dev/null 2>&1 || rc=$?
  printf '%s' "$rc"
}

cmd_self_check() {
  local list="${MEC_CI_ONLY_LIST:-$HERE/merge-effect-class.ci-only.tsv}" bad=0 rows
  WORK="$(mktemp -d)" || { echo "self-check=FAILED"; exit 1; }
  [ "$(probe_rc $'knowledge-base/a.md\n')" = "0" ] || bad=1
  [ "$(probe_rc $'apps/web-platform/x.ts\n')" = "1" ] || bad=1
  [ "$(probe_rc $'zzz-unknown-path\n')" = "1" ] || bad=1
  [ "$(probe_rc '')" = "2" ] || bad=1
  if [ ! -r "$list" ]; then
    bad=1
  else
    rows="$(awk -F'\t' '!/^#/ && NF > 0 { n++; if ($2 ~ /^[[:space:]]*$/) bad++ } END { printf "%d %d", n + 0, bad + 0 }' "$list")" || rows="0 1"
    [ "${rows%% *}" -ge 1 ] || bad=1
    [ "${rows##* }" -eq 0 ] || bad=1
  fi
  if [ "$bad" -eq 0 ]; then
    echo "self-check=ok"
    exit 0
  fi
  echo "self-check=FAILED"
  exit 1
}

# ── args ────────────────────────────────────────────────────────────────────────────────────────
MODE=""; ARG_PATH=""; ARG_PR=""; ARG_REPO=""
if [ "${1-}" = "--help" ] || [ "${1-}" = "-h" ]; then usage; exit 0; fi
while [ "$#" -gt 0 ]; do
  case "$1" in
    --files-from)
      [ -z "$MODE" ] && [ "$#" -ge 2 ] || usage_error
      MODE="files"; ARG_PATH="$2"; shift 2 ;;
    --pr)
      [ -z "$MODE" ] && [ "$#" -ge 2 ] || usage_error
      case "$2" in '' | *[!0-9]*) usage_error ;; esac
      MODE="pr"; ARG_PR="$2"; shift 2 ;;
    --repo)
      [ "$MODE" = "pr" ] && [ "$#" -ge 2 ] || usage_error
      case "$2" in
        */*/* | */ | /* | '' | *[!A-Za-z0-9._/-]*) usage_error ;;
        */*) ;;
        *) usage_error ;;
      esac
      ARG_REPO="$2"; shift 2 ;;
    --print-witnesses) [ -z "$MODE" ] || usage_error; MODE="witnesses"; shift ;;
    --filter-allowed) [ -z "$MODE" ] || usage_error; MODE="filter"; shift ;;
    --self-check) [ -z "$MODE" ] || usage_error; MODE="selfcheck"; shift ;;
    *) usage_error ;;
  esac
done

case "$MODE" in
  files) cmd_files_from "$ARG_PATH" ;;
  pr) cmd_pr "$ARG_PR" "$ARG_REPO" ;;
  witnesses) cmd_print_witnesses ;;
  filter) cmd_filter_allowed ;;
  selfcheck) cmd_self_check ;;
  *) usage_error ;;
esac
