#!/usr/bin/env bash
# prepush-secret-scan.sh — local per-commit secret scan over the commits a push would publish.
#
# WHAT. Runs `gitleaks git` over `origin/main..HEAD` (non-merge commits, the range shape of the CI
# range arm in .github/workflows/secret-scan.yml, plus `--text`) BEFORE `git push`, so a secret-bearing
# commit is caught while its history is still local and fixable by rewriting an unpublished commit.
# CI cannot do that job: its scan starts at the PR, after the push, and a pushed SHA stays reachable
# (refs/pull/N/head) even after a force-push. A published secret cannot be cleared by a later "fix"
# commit either: the range scan reads every commit in the range, not the tip. Called by prose from
# `soleur:ship` before each of its pushes and from the review skill's pushes; the hook-level
# chokepoint (a git `pre-push`) is tracked in #11126.
#
# USAGE.   prepush-secret-scan.sh [--base REF] [--no-fetch]
#   --base REF   range base (default refs/remotes/origin/main). A SELECTOR, not a skip switch:
#                `--base HEAD` yields range=0. Must match ^[A-Za-z0-9._/-]+$ and not start with `-`;
#                it is resolved to a full commit SHA and ONLY that SHA reaches --log-opts.
#   --no-fetch   skip the best-effort `git fetch origin main` (offline probes, tests).
# No environment variable or file skips the scan. The only env knob is
# SOLEUR_PREPUSH_SCAN_TIMEOUT (integer seconds, 1..600, default 240; anything else falls back), and
# an expired bound is a STOP (44), never a skip. Worst case ~340s: run it with a Bash timeout of 400s.
#
# EXIT CONTRACT (the caller branches on this; ONLY 0 and 43 continue):
#   0   CLEAN      — rc 0 from gitleaks, a report of exactly `[]`, and no scan-error output.
#   1   FINDINGS   — STOP. Also what a `set -u` abort produces, which is the safe direction.
#   43  NOT_RUN    — the scan could not be attempted because the ENVIRONMENT lacks something (no
#                    gitleaks, no work tree, no tmpdir, unresolvable base, a shallow clone, no
#                    committed .gitleaks.toml). Record `secret-scan: not run (<reason>)` in the PR
#                    body and continue; CI's secret-scan.yml still gates the merge (not the publication).
#   44  INCOMPLETE — STOP, the operator decides (headless: abort like FINDINGS). The scan ran or was
#                    attempted and the range was NOT verified clean: timeout/OOM, rc >= 2, an empty
#                    report, a scanned-count mismatch, `ERR`/`fatal:` in an rc-0 scan (an unreadable
#                    object), an unreadable range, or no merge base in a non-shallow repo. Each of
#                    these can be induced by the PR's own content, so none may read as "continue".
#                    Any unexpected verdict also lands here.
#   any other value is a STOP too, including 127 (script not found: CLAUDE_PLUGIN_ROOT unset) and 64
#   (bad arguments). 43/44 are outside every status bash produces by accident (1 generic/`set -u`,
#   2 syntax, 126/127, 128+N), the reasoning of battery-owed.sh's 42.
#
# RECEIPT (stdout; the last line bar the NOT_RUN line below):
#   PREPUSH_SECRET_SCAN verdict=<CLEAN|FINDINGS|NOT_RUN|INCOMPLETE> base=<sha|none> head=<sha|none>
#     fetch=<ok|stale|skipped> range=<N> scanned=<M|?> cfg_changed=<0|1> cfg=<base|none>
#     published=<0|1|?> attr=<pinned|unpinned> gitleaks=<ver|none> reason=<token>
#   On NOT_RUN a final `secret-scan: not run (<reason>)` line follows: that is the PR-body line.
#   `scanned` is read best-effort from gitleaks' `N commits scanned.` line and cross-checked only
#   when it parses (a parse miss leaves `scanned=?` and does not block CLEAN, so output-format
#   drift cannot turn every run into INCOMPLETE). Findings print commit/file/line/rule id on stderr,
#   never the secret, the `Match` text or raw gitleaks output (which carries author emails).
#
# WHAT THE SCAN READS. The BASE's committed .gitleaks.toml and .gitleaksignore (cfg=base), never the
# working tree's and never the PR's, and never HEAD's when the base has none (that is NOT_RUN): a PR
# that widens, breaks or deletes its own config cannot scan itself clean. gitleaks is pointed at the
# repository's git dir, not the work tree, so a checked-out .gitleaksignore is not read either. A
# legitimate allowlist-adding PR therefore gets FINDINGS here; CI's `allowlist-diff` job (label or
# `Allowlist-Widened-By:` trailer) is the arbiter. `cfg_changed=1` says the range touches the config,
# .gitleaksignore or a root .gitattributes. An inline `gitleaks:allow` comment added by the PR is
# still honoured, exactly as in CI. gitleaks runs with GIT_ATTR_SOURCE=<empty tree>, `--text`, and the
# global/system git config replaced, so committed `-diff`/`binary` attributes, NUL-byte files and a
# user's diff.* settings cannot blind it (`--text` alone already defeats `.git/info/attributes`).
#
# LIMITATIONS (measured, documented rather than claimed away; CI's `gitleaks dir .` is the net):
#   - Merge commits: `--no-merges` mirrors CI's range arm and misses content that exists ONLY in a
#     conflict-resolution merge commit (rc 0; `-m` and `gitleaks dir` find it). A tip-tree scan
#     belongs to #11126.
#   - UTF-16 files are invisible here and to CI. git < 2.40 prints attr=unpinned (GIT_ATTR_SOURCE is
#     ignored there; `--text` still holds).
#   - An empty or unparseable base config, or a symlinked one, is NOT_RUN/INCOMPLETE, never a fallback.
#   - Version skew: CI pins gitleaks 8.24.2. A newer local rule pack can flag what CI accepts; that
#     is still a STOP (conservative) and the receipt prints the local version.
#   - Shallow clones with no merge base are NOT_RUN `no-merge-base`: scanning a truncated history
#     would attribute other commits to this PR.
#   - A push made by another script (pre-merge-rebase.sh, sync-pr-behind.sh) never reaches this
#     scan: only a git `pre-push` hook can see it (#11126).
#
# REMEDY: printed with FINDINGS, branched on whether a finding commit is already on origin; headless
# ship aborts and never rewrites history unasked, never edits .gitleaks.toml/.gitleaksignore, never
# adds an inline allow.

set -uo pipefail

# Drop empty and relative PATH entries first: `:/bin` or `./bin` would run a repo-local git, timeout,
# jq or env as the operator.
IFS=: read -ra _pe <<<"${PATH:-}"
_np=""
for _e in ${_pe[@]+"${_pe[@]}"}; do
  case "$_e" in /*) _np="${_np:+$_np:}$_e" ;; esac
done
[ -n "$_np" ] || _np=/usr/bin:/bin # an empty PATH would make bash search the current directory
PATH=$_np
export PATH

BASE_REF="refs/remotes/origin/main"
DO_FETCH=1

R_BASE=none
R_HEAD=none
R_FETCH=skipped
R_RANGE=0
R_SCANNED='?'
R_CFG=0
R_CFGSRC=none
R_PUB='?'
R_ATTR=unpinned
R_GL=none

TMP=""
# shellcheck disable=SC2329 # invoked through the EXIT trap
cleanup() {
  [[ -n "${TMP:-}" ]] || return 0
  rm -rf "${TMP:?}"
}
trap cleanup EXIT

usage_die() {
  printf 'usage: prepush-secret-scan.sh [--base REF] [--no-fetch]\n' >&2
  exit 64
}

# finish <CLEAN|FINDINGS|NOT_RUN|INCOMPLETE> <reason-token> — prints the receipt and exits. The only
# exit path for a verdict; the explicit `exit "$final_rc"` is the contract (never an implicit status).
# The default arm is a STOP: a mistyped or new verdict must never read as "continue".
finish() {
  local verdict=$1 reason=$2 final_rc
  case "$verdict" in
    CLEAN) final_rc=0 ;;
    FINDINGS) final_rc=1 ;;
    NOT_RUN) final_rc=43 ;;
    *) final_rc=44 ;;
  esac
  printf 'PREPUSH_SECRET_SCAN verdict=%s base=%s head=%s fetch=%s range=%s scanned=%s cfg_changed=%s cfg=%s published=%s attr=%s gitleaks=%s reason=%s\n' \
    "$verdict" "$R_BASE" "$R_HEAD" "$R_FETCH" "$R_RANGE" "$R_SCANNED" "$R_CFG" "$R_CFGSRC" "$R_PUB" "$R_ATTR" "$R_GL" "$reason"
  if [ "$verdict" = NOT_RUN ]; then
    printf 'WARN: secret-scan NOT RUN (%s): the commits were not scanned locally; CI secret-scan.yml gates the merge, not the publication. This is the sanctioned continue path: put the secret-scan: line below in the PR body; do not retry or install anything.\n' "$reason" >&2
    printf 'secret-scan: not run (%s)\n' "$reason"
  elif [ "$final_rc" -eq 44 ]; then
    printf 'STOP: secret-scan INCOMPLETE (%s): the range was NOT verified clean. Do not push; show the operator this reason (headless: abort like FINDINGS). The operator may push explicitly, never silently.\n' "$reason" >&2
  fi
  exit "$final_rc"
}

# san <string> <max-len> — ASCII allowlist for every printed field that comes from PR content or a
# possibly hostile toml: ANSI escapes, newlines and prompt-injection text must not reach the transcript.
san() {
  printf '%s' "$1" | LC_ALL=C tr -cd '[:alnum:]._/@+=-' | LC_ALL=C cut -c1-"$2"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --base)
      [ "$#" -ge 2 ] || usage_die
      BASE_REF=$2
      shift 2
      ;;
    --no-fetch)
      DO_FETCH=0
      shift
      ;;
    *) usage_die ;;
  esac
done

# ── 1. hardening: nothing ambient may redirect git or gitleaks ────────────────────────────────
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY \
  GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_TEMPLATE_DIR GIT_EXEC_PATH \
  GIT_EXTERNAL_DIFF GIT_REPLACE_REF_BASE GIT_DIFF_OPTS GIT_PAGER
for _v in $(compgen -e GITLEAKS_); do
  unset "$_v"
done
export GIT_NO_REPLACE_OBJECTS=1 GIT_TERMINAL_PROMPT=0 GIT_CONFIG_NOSYSTEM=1 GIT_ATTR_NOSYSTEM=1

# Refuse a git that lives under the current directory BEFORE running it (an in-repo shim would run as
# the operator); in-repo PATH entries are dropped below once the repository root is known.
_g=$(type -P git 2>/dev/null) || _g=""
[ -n "$_g" ] || finish NOT_RUN not-a-work-tree
_gd=$(cd -P "$(dirname "$_g")" 2>/dev/null && pwd -P) || _gd=""
_cwd=$(pwd -P)
case "$_gd/" in "$_cwd"/*) finish NOT_RUN git-in-repo ;; esac

TOP=$(git rev-parse --show-toplevel 2>/dev/null) || TOP=""
[ -n "$TOP" ] || finish NOT_RUN not-a-work-tree
TOPREAL=$(cd -P "$TOP" 2>/dev/null && pwd -P) || TOPREAL=$TOP

# Drop absolute PATH entries that live inside the repository (direnv PATH_add, node_modules/.bin):
# a PR could put a git, timeout, jq, env or gitleaks there. The first match wins, so filter, don't skip.
_np=""
IFS=: read -ra _pe <<<"$PATH"
for _e in ${_pe[@]+"${_pe[@]}"}; do
  _ed=$(cd -P "$_e" 2>/dev/null && pwd -P) || _ed=""
  case "$_ed/" in "$TOPREAL"/*) continue ;; esac
  _np="${_np:+$_np:}$_e"
done
[ -n "$_np" ] || _np=/usr/bin:/bin
PATH=$_np
export PATH
hash -r

umask 077
TMP=$(mktemp -d 2>/dev/null) || finish NOT_RUN tmpdir-unavailable

TO_CMD=()
if command -v timeout >/dev/null 2>&1; then
  TO_CMD=(timeout)
elif command -v gtimeout >/dev/null 2>&1; then
  TO_CMD=(gtimeout)
fi

# bounded <seconds> cmd... — exec-boundary deadline. A host with neither timeout nor gtimeout (stock
# macOS) runs unbounded rather than misreporting a runnable gitleaks as broken.
bounded() {
  local n=$1
  shift
  if [ "${#TO_CMD[@]}" -gt 0 ]; then
    "${TO_CMD[0]}" -k 5 "$n" "$@"
  else
    "$@"
  fi
}

SCAN_T=240
case "${SOLEUR_PREPUSH_SCAN_TIMEOUT:-}" in
  '' | *[!0-9]*) ;;
  *)
    if [ "${#SOLEUR_PREPUSH_SCAN_TIMEOUT}" -le 3 ] && [ "$SOLEUR_PREPUSH_SCAN_TIMEOUT" -ge 1 ] && [ "$SOLEUR_PREPUSH_SCAN_TIMEOUT" -le 600 ]; then
      SCAN_T=$SOLEUR_PREPUSH_SCAN_TIMEOUT
    fi
    ;;
esac

# ── 2. preconditions, each a NOT_RUN with a named reason ──────────────────────────────────────
GL=$(type -P gitleaks 2>/dev/null) || GL=""
[ -n "$GL" ] || finish NOT_RUN gitleaks-absent

# Resolve symlinks to the real file ONLY to refuse one that lives inside the repo (a PR-controlled
# shim would run attacker code under this script's identity). The program that RUNS is $GL as found:
# a version-manager shim is a symlink to a multi-call binary that picks the tool from argv[0], so
# executing the resolved target runs a different program.
_p=$GL
_hops=0
while [ -L "$_p" ]; do
  _hops=$((_hops + 1))
  [ "$_hops" -le 40 ] || finish NOT_RUN gitleaks-unrunnable
  _t=$(readlink "$_p")
  case "$_t" in
    /*) _p=$_t ;;
    *) _p="$(dirname "$_p")/$_t" ;;
  esac
done
_d=$(cd -P "$(dirname "$_p")" 2>/dev/null && pwd -P) || _d=""
[ -n "$_d" ] || finish NOT_RUN gitleaks-unrunnable
GLREAL="$_d/$(basename "$_p")"
case "$GLREAL" in
  "$TOPREAL"/* | "$TOP"/*) finish NOT_RUN gitleaks-in-repo ;;
esac

# Probe by RUNNING it, from a neutral cwd: `command -v` alone certifies an unpinned version-manager
# shim that resolves and exits non-zero. A bound expiry (124/137) is a load condition, not a broken
# install, so it gets one wider retry before it is called a timeout.
GLVER=$(cd / && bounded 10 "$GL" version 2>/dev/null </dev/null)
prc=$?
if [ "$prc" -eq 124 ] || [ "$prc" -eq 137 ]; then
  GLVER=$(cd / && bounded 60 "$GL" version 2>/dev/null </dev/null)
  prc=$?
  if [ "$prc" -eq 124 ] || [ "$prc" -eq 137 ]; then
    finish INCOMPLETE timeout
  fi
fi
[ "$prc" -eq 0 ] || finish NOT_RUN gitleaks-unrunnable
R_GL=$(printf '%s' "$GLVER" | sed -n '1p' | tr -cd '[:alnum:].-' | cut -c1-24)
[ -n "$R_GL" ] || R_GL=unknown

# GIT_ATTR_SOURCE needs git >= 2.40; an older git ignores it and the receipt says so.
read -r _gmaj _gmin <<<"$(git --version 2>/dev/null | sed -En 's/^git version ([0-9]+)\.([0-9]+).*/\1 \2/p')"
if [[ "${_gmaj:-}" =~ ^[0-9]+$ ]] && [[ "${_gmin:-}" =~ ^[0-9]+$ ]]; then
  if [ "$_gmaj" -gt 2 ] || { [ "$_gmaj" -eq 2 ] && [ "$_gmin" -ge 40 ]; }; then R_ATTR=pinned; fi
fi

# ── 3. refresh (best effort) ──────────────────────────────────────────────────────────────────
# A stale base can only WIDEN the range (over-scan), so a failed fetch is a state, not a failure.
# A locally advanced refs/remotes/origin/main (update-ref, branch -f) narrows it, which is why the
# receipt prints both SHAs unabbreviated. The explicit refspec also works in a single-branch clone,
# where a bare `git fetch origin main` leaves refs/remotes/origin/main untouched.
if [ "$DO_FETCH" -eq 1 ]; then
  if (cd "$TOP" && bounded 10 git fetch --no-tags -q origin '+refs/heads/main:refs/remotes/origin/main') </dev/null >/dev/null 2>&1; then
    R_FETCH=ok
  else
    R_FETCH=stale
  fi
fi

# ── 4. range ──────────────────────────────────────────────────────────────────────────────────
case "$BASE_REF" in
  -* | '') finish NOT_RUN base-unresolvable ;;
esac
[[ "$BASE_REF" =~ ^[A-Za-z0-9._/-]+$ ]] || finish NOT_RUN base-unresolvable # mut:baseregex
BASE_SHA=$(cd "$TOP" && git rev-parse --verify --quiet --end-of-options "${BASE_REF}^{commit}" 2>/dev/null) || BASE_SHA=""
HEAD_SHA=$(cd "$TOP" && git rev-parse --verify --quiet --end-of-options "HEAD^{commit}" 2>/dev/null) || HEAD_SHA=""
[[ "$BASE_SHA" =~ ^[0-9a-f]{40,64}$ ]] || finish NOT_RUN base-unresolvable
[[ "$HEAD_SHA" =~ ^[0-9a-f]{40,64}$ ]] || finish NOT_RUN head-unresolvable
R_BASE=$BASE_SHA
R_HEAD=$HEAD_SHA

# An unresolvable ref makes `gitleaks git` exit 0 with an empty report (measured), so the checks
# above are load-bearing. No merge base means an over-scan of main's history would be attributed to
# this PR: environmental in a shallow clone, but in a full clone it is an orphan or unrelated
# branch, which a PR can create on purpose, so that is a STOP.
if ! (cd "$TOP" && git merge-base "$BASE_SHA" "$HEAD_SHA") >/dev/null 2>&1; then
  if [ "$(cd "$TOP" && git rev-parse --is-shallow-repository 2>/dev/null)" = true ]; then
    finish NOT_RUN no-merge-base
  fi
  finish INCOMPLETE no-merge-base
fi

N=$(cd "$TOP" && git rev-list --count --no-merges "$BASE_SHA..$HEAD_SHA" 2>/dev/null) || N=""
[[ "$N" =~ ^[0-9]+$ ]] || finish INCOMPLETE range-unreadable
R_RANGE=$N
# E=1 means at least one commit in range ADDS lines: gitleaks reads added lines only, so a range of
# pure renames, deletions, mode changes or empty files legitimately scans 0 commits.
E=""
if (cd "$TOP" && git log --no-merges --format= --numstat --text "$BASE_SHA..$HEAD_SHA" 2>/dev/null) | awk '$1 ~ /^[0-9]+$/ && $1 > 0 { f = 1 } END { exit !f }'; then
  E=1
fi
CFG=$(cd "$TOP" && git diff --name-only "$BASE_SHA...$HEAD_SHA" -- .gitleaks.toml .gitleaksignore .gitattributes 2>/dev/null)
[ -z "$CFG" ] || R_CFG=1

# published=1 when part of the range is already on origin/<branch>: the remedy then starts with
# rotation, because a rewrite does not unpublish anything.
BR=$(cd "$TOP" && git symbolic-ref --quiet --short HEAD 2>/dev/null) || BR=""
RB=""
if [ -n "$BR" ] && [[ "$BR" =~ ^[A-Za-z0-9._/+@-]+$ ]]; then
  if RB=$(cd "$TOP" && git rev-parse --verify --quiet --end-of-options "refs/remotes/origin/${BR}^{commit}" 2>/dev/null); then
    U=$(cd "$TOP" && git rev-list --count --no-merges "$BASE_SHA..$HEAD_SHA" "^$RB" 2>/dev/null) || U=""
    if [[ "$U" =~ ^[0-9]+$ ]]; then
      if [ "$U" -lt "$N" ]; then R_PUB=1; else R_PUB=0; fi
    fi
  else
    R_PUB=0
  fi
fi

# The config the scan reads is the BASE's committed one and nothing else: a base without a usable
# config is NOT_RUN, never a fallback to HEAD's (the PR could ship its own allowlist).
if ! (cd "$TOP" && git show "$BASE_SHA:.gitleaks.toml") >"$TMP/gitleaks.toml" 2>/dev/null || [ ! -s "$TMP/gitleaks.toml" ]; then
  finish NOT_RUN gitleaks-toml-absent
fi
R_CFGSRC="base"
(cd "$TOP" && git show "$BASE_SHA:.gitleaksignore") >"$TMP/gitleaksignore" 2>/dev/null || : >"$TMP/gitleaksignore"

if [ "$N" -eq 0 ]; then
  R_SCANNED=0
  finish CLEAN empty-range
fi

# ── 5. scan ───────────────────────────────────────────────────────────────────────────────────
# Every git setting that changes what the patch stream shows is pinned on BOTH surfaces:
# GIT_CONFIG_PARAMETERS is read AFTER the GIT_CONFIG_COUNT list and beats it, so a count-only pin
# loses to `git -c color.diff=always` in the caller's environment, and a coloured patch hides `+`
# lines from gitleaks. We APPEND to whatever the caller exported. Prefix and attribute settings
# matter as much as colour: diff.noprefix drops the first path component and defeats the toml's
# path allowlists.
# The empty tree of THIS repository's object format (SHA-1 or SHA-256).
EMPTY_TREE=$(cd "$TOP" && git hash-object -t tree /dev/null 2>/dev/null)
[[ "$EMPTY_TREE" =~ ^[0-9a-f]{40,64}$ ]] || EMPTY_TREE=4b825dc642cb6eb9a060e54bf8d69288fbee4904
# gitleaks scans the git DIR, not the work tree: it reads a checked-out .gitleaksignore from the
# source it is pointed at, and the PR controls the work tree.
GITCOMMON=$(cd "$TOP" && gd=$(git rev-parse --git-common-dir 2>/dev/null) && cd "$gd" 2>/dev/null && pwd -P) || GITCOMMON=""
[ -n "$GITCOMMON" ] || finish INCOMPLETE range-unreadable
GL_PINS=(color.ui=never color.diff=never diff.noprefix=false diff.mnemonicPrefix=false diff.srcPrefix=a/ diff.dstPrefix=b/ core.attributesFile=/dev/null)
gl_cfg_n="${GIT_CONFIG_COUNT:-0}"
case "$gl_cfg_n" in '' | *[!0-9]*) gl_cfg_n=0 ;; esac
gl_cfg_n=$((10#$gl_cfg_n))
gl_params="${GIT_CONFIG_PARAMETERS:-}"
GLENV=(env)
for _i in "${!GL_PINS[@]}"; do
  _k=${GL_PINS[$_i]%%=*}
  _val=${GL_PINS[$_i]#*=}
  GLENV+=("GIT_CONFIG_KEY_$((gl_cfg_n + _i))=$_k" "GIT_CONFIG_VALUE_$((gl_cfg_n + _i))=$_val")
  gl_params="${gl_params:+$gl_params }'$_k'='$_val'"
done
GLENV+=(
  "GIT_CONFIG_COUNT=$((gl_cfg_n + ${#GL_PINS[@]}))" # mut:colorcount
  "GIT_CONFIG_PARAMETERS=$gl_params" # mut:colorparams
  "GIT_ATTR_SOURCE=$EMPTY_TREE"
  GIT_CONFIG_GLOBAL=/dev/null
  GIT_CONFIG_SYSTEM=/dev/null
)

# stdout and stderr are captured to $TMP and never echoed: raw gitleaks output carries author emails.
(
  cd "$TOP" &&
    bounded "$SCAN_T" "${GLENV[@]}" \
      "$GL" git \
      --redact \
      --no-banner \
      --exit-code 1 \
      --config "$TMP/gitleaks.toml" \
      --gitleaks-ignore-path "$TMP/gitleaksignore" \
      --report-format json \
      --report-path "$TMP/report.json" \
      "$GITCOMMON" \
      --log-opts="--no-merges --text ${BASE_SHA}..${HEAD_SHA}" # mut:range
) </dev/null >"$TMP/out" 2>"$TMP/err"
scan_rc=$?

# ── 6. verdict. The ORDER is part of the contract. ─────────────────────────────────────────────
if [ "$scan_rc" -eq 124 ] || [ "$scan_rc" -eq 137 ]; then
  finish INCOMPLETE timeout
fi
# A missing or zero-byte report is evaluated BEFORE any content branch, so rc 0 with no report can
# never reach CLEAN.
if [ ! -s "$TMP/report.json" ]; then
  finish INCOMPLETE empty-report # mut:emptyreport
fi
REPORT=$(tr -d ' \t\r\n' <"$TMP/report.json")

# Best-effort count of commits gitleaks says it read (anchored; the last match wins).
SCANNED=$(cat "$TMP/out" "$TMP/err" 2>/dev/null | sed -En -e 's/^([0-9]+) commits? scanned.*$/\1/p' -e 's/^.*[^0-9]([0-9]+) commits? scanned.*$/\1/p' | tail -n 1)
if [[ "$SCANNED" =~ ^[0-9]+$ ]]; then
  R_SCANNED=$SCANNED
fi

if [ "$scan_rc" -eq 0 ] && [ "$REPORT" = '[]' ]; then
  # gitleaks exits 0 with `[]` and a partial count when git could not read an object (measured):
  # its ERR / fatal lines are the only signal. Written to a file first so grep -q never SIGPIPEs sed.
  cat "$TMP/out" "$TMP/err" 2>/dev/null | sed -e "s/$(printf '\033')\[[0-9;]*m//g" >"$TMP/plain.log"
  if grep -qE '(^|[^A-Za-z])ERR([^A-Za-z]|$)|fatal:' "$TMP/plain.log"; then
    finish INCOMPLETE scan-errors
  fi
  if [[ "$SCANNED" =~ ^[0-9]+$ ]] && [ -n "$E" ]; then
    if [ "$SCANNED" -eq 0 ] || [ "$SCANNED" -gt "$N" ]; then
      finish INCOMPLETE scanned-mismatch
    fi
  fi
  finish CLEAN no-findings
fi

if [ "$scan_rc" -ne 0 ] && [ "$scan_rc" -ne 1 ]; then
  finish INCOMPLETE "gitleaks-rc-${scan_rc}"
fi

# rc 1 with a non-empty report is FINDINGS even when the report does not parse; rc 0 with a
# non-`[]` report is FINDINGS defensively.
printf 'secret-scan: FINDINGS in the commits this push would publish (%s..%s):\n' "${BASE_SHA:0:12}" "${HEAD_SHA:0:12}" >&2
total=""
if command -v jq >/dev/null 2>&1; then
  total=$(jq -r 'length' "$TMP/report.json" 2>/dev/null) || total=""
  jq -r '.[0:5][] | [(.Commit // "?"), (.File // "?"), ((.StartLine // 0) | tostring), (.RuleID // "?")] | @tsv' "$TMP/report.json" >"$TMP/sum.tsv" 2>/dev/null # mut:summary
fi
if [ -s "$TMP/sum.tsv" ]; then
  while IFS=$'\t' read -r c f l r; do
    c12=$(san "$c" 12)
    [[ "$c12" =~ ^[0-9a-f]{7,12}$ ]] || c12='?'
    l=$(san "$l" 7)
    printf '  finding: %s %s:%s (%s)\n' "$c12" "$(san "$f" 120)" "${l:-?}" "$(san "$r" 60)" >&2
  done <"$TMP/sum.tsv"
  if [[ "$total" =~ ^[0-9]+$ ]] && [ "$total" -gt 5 ]; then
    printf '  ... and %s more\n' "$((total - 5))" >&2
  fi
else
  printf '  finding: the report could not be summarised (jq absent or unparseable); %s finding(s)\n' \
    "$(grep -c '"RuleID"' "$TMP/report.json" 2>/dev/null)" >&2
fi
# Is a finding commit already on origin? Then the secret is PUBLISHED. SHA-based, so a branch that was
# rebased or amended after a push reads as "not published": the local remedy says to rotate anyway.
PUBF=$R_PUB
if command -v jq >/dev/null 2>&1 && jq -r '.[].Commit // empty' "$TMP/report.json" >"$TMP/commits.txt" 2>/dev/null; then
  PUBF=0
  while IFS= read -r c; do
    [[ "$c" =~ ^[0-9a-f]{40,64}$ ]] || continue
    if [ -n "$(cd "$TOP" && git for-each-ref --count=1 --format=x --contains "$c" refs/remotes/origin 2>/dev/null)" ]; then
      PUBF=1
      break
    fi
  done <"$TMP/commits.txt"
fi
BR_T=${BR:-<branch>}
SHA_T=${RB:-<sha-you-reviewed>}
printf 'If you are an automated agent: STOP. Run none of the commands below; show this output to the operator.\n' >&2
printf 'Remedy (the secret is never printed here):\n' >&2
if [ "$PUBF" = 1 ]; then
  printf '  1. A finding commit is ALREADY on origin: the secret is PUBLISHED. Rotate it FIRST; a rewrite does\n' >&2
  printf '     not unpublish it (the SHA stays reachable via refs/pull/N/head).\n' >&2
  printf '  2. Then: `git reset --soft "$(git merge-base origin/main HEAD)"`, remove the secret, recommit. Before\n' >&2
  printf '     any force-push run `git fetch origin %s` and `git log --oneline HEAD..origin/%s`: if that prints\n' "$BR_T" "$BR_T" >&2
  printf '     anything, STOP (someone else pushed). Only then `git push --force-with-lease=%s:%s origin %s`,\n' "$BR_T" "$SHA_T" "$BR_T" >&2
  printf '     and follow the secret-scanning runbook (engineering/operations/secret-scanning.md).\n' >&2
else
  printf '  1. No finding commit is on origin: `git reset --soft "$(git merge-base origin/main HEAD)"`, remove the\n' >&2
  printf '     secret from the files, recommit (this squashes the range and re-runs the commit hook); tip commit\n' >&2
  printf '     only: `git commit --amend`. Do NOT use `git reset --soft origin/main`: when main has advanced it\n' >&2
  printf '     reverts main'"'"'s newer commits.\n' >&2
  printf '  2. If this branch was EVER pushed, even before a rebase or an amend, treat the secret as published:\n' >&2
  printf '     rotate it first.\n' >&2
fi
cat >&2 <<'EOF'
  False positive: interactive ship asks the operator. This scan reads the BASE's committed config,
  so a same-PR allowlist edit does not apply here; CI's allowlist-diff job arbitrates it.
Headless ship aborts here: it never rewrites history, never edits .gitleaks.toml or .gitleaksignore
and never adds an inline `gitleaks:allow`.
EOF
finish FINDINGS secret-found
