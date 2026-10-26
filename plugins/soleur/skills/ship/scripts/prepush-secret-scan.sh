#!/usr/bin/env bash
# prepush-secret-scan.sh — local per-commit secret scan over the commits a push would publish.
#
# WHAT. Runs `gitleaks git` over `origin/main..HEAD` (non-merge commits, the same range shape as
# the CI range arm in .github/workflows/secret-scan.yml) BEFORE `git push`, so a secret-bearing
# commit is caught while its history is still local and fixable by rewriting an unpublished commit.
# A published secret cannot be cleared by a later "fix" commit: the CI range scan reads every
# commit in the range, not the tip. Called from `soleur:ship` Phase 6 (the first push) and, by
# prose, before every later push in that skill; Phase 6.4 carries the pointer.
#
# USAGE.   prepush-secret-scan.sh [--base REF] [--no-fetch]
#   --base REF   range base (default refs/remotes/origin/main). A SELECTOR, not a skip switch:
#                `--base HEAD` yields range=0. Must match ^[A-Za-z0-9._/-]+$ and not start with `-`;
#                it is resolved to a full commit SHA and ONLY that SHA reaches --log-opts.
#   --no-fetch   skip the best-effort `git fetch origin main` (offline probes, tests).
# No environment variable or file skips the scan. The only env knob is
# SOLEUR_PREPUSH_SCAN_TIMEOUT (integer seconds, 1..600, default 120; anything else falls back).
#
# EXIT CONTRACT (the caller branches on this):
#   0   CLEAN     — rc 0 from gitleaks AND a report of exactly `[]`.
#   1   FINDINGS  — STOP. Also what a `set -u` abort produces, which is the safe direction.
#   43  NOT_RUN   — the scan did not or could not run: record `secret-scan: not run (<reason>)`
#                   in the PR body and continue (CI's secret-scan.yml is the load-bearing gate).
#   any other value is a STOP, including 127 (script not found: CLAUDE_PLUGIN_ROOT unset in a
#   cloud shell) and 64 (bad arguments). ONLY 0 and 43 continue. 43 is deliberately outside every
#   status bash produces by accident (1 generic/`set -u`, 2 syntax, 126/127, 128+N), the same
#   reasoning as battery-owed.sh's 42, so a crash can never read as "continue".
#
# RECEIPT (stdout, always the last line bar the NOT_RUN line below):
#   PREPUSH_SECRET_SCAN verdict=<CLEAN|FINDINGS|NOT_RUN> base=<sha|none> head=<sha|none>
#     fetch=<ok|stale|skipped> range=<N> scanned=<M|?> cfg_changed=<0|1> gitleaks=<ver|none> reason=<token>
#   On NOT_RUN a final `secret-scan: not run (<reason>)` line follows: that is the PR-body line.
#   `scanned` is read best-effort from gitleaks' `N commits scanned.` line and cross-checked only
#   when it parses (a parse miss leaves `scanned=?` and does not block CLEAN, so output-format
#   drift cannot turn every run into NOT_RUN). Findings print commit/file/line/rule id on stderr,
#   never the secret, the `Match` text or raw gitleaks output (which carries author emails).
#
# LIMITATIONS (measured, documented rather than claimed away; CI's `gitleaks dir .` is the net):
#   - Merge commits: `--no-merges` mirrors CI's range arm and misses content that exists ONLY in a
#     conflict-resolution merge commit (rc 0; `-m` and `gitleaks dir` find it). Not claimed covered.
#   - A path marked `-diff` in a gitattributes file yields no patch lines for gitleaks to read.
#     The commit hook re-scans such blobs; this script does not (the local-only vector is the
#     operator's own .git/info/attributes; committed attributes are covered by CI).
#   - The scan uses the working-tree .gitleaks.toml/.gitleaksignore (CI parity), so a PR that
#     widens its own allowlist can scan itself clean here. `cfg_changed=1` makes that visible;
#     CI's `allowlist-diff` job is the independent backstop. It is a visibility flag, not a gate.
#   - Version skew: CI pins gitleaks 8.24.2. A newer local rule pack can flag what CI accepts; that
#     is still a STOP (conservative) and the receipt prints the local version. False positives are
#     cleared with a per-rule allowlist in .gitleaks.toml (review applies), so the check cannot
#     deadlock a push.
#   - Shallow clones with no merge base (hosted ship) are NOT_RUN `no-merge-base`: scanning a
#     truncated history would attribute other commits to this PR.
#   - A huge blob or long range can force a timeout, which is NOT_RUN. Accepted (CI gates); the
#     NOT_RUN WARN on stderr is loud so it is not silent.
#
# REMEDY (printed with FINDINGS; headless ship aborts and never rewrites history unasked):
#   1. Commit still local: `git reset --soft origin/main`, remove the secret from the files and
#      recommit (squashes the range and re-runs the commit hook); tip commit only: `git commit --amend`.
#   2. Commit already on `origin`: the secret is published. Rotate it first, then reset as above,
#      then `git push --force-with-lease`, then follow knowledge-base/engineering/operations/secret-scanning.md.
#   3. False positive: add a per-rule allowlist to .gitleaks.toml (review applies) and re-run.

set -uo pipefail

BASE_REF="refs/remotes/origin/main"
DO_FETCH=1

R_BASE=none
R_HEAD=none
R_FETCH=skipped
R_RANGE=0
R_SCANNED='?'
R_CFG=0
R_GL=none

TMP=""
cleanup() {
  [[ -n "${TMP:-}" ]] || return 0
  rm -rf "${TMP:?}"
}
trap cleanup EXIT
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

usage_die() {
  printf 'usage: prepush-secret-scan.sh [--base REF] [--no-fetch]\n' >&2
  exit 64
}

# finish <CLEAN|FINDINGS|NOT_RUN> <reason-token> — prints the receipt and exits. The only exit
# path for a verdict; the explicit `exit "$final_rc"` is the contract (never an implicit status).
finish() {
  local verdict=$1 reason=$2 final_rc
  case "$verdict" in
    CLEAN) final_rc=0 ;;
    FINDINGS) final_rc=1 ;;
    *) final_rc=43 ;;
  esac
  printf 'PREPUSH_SECRET_SCAN verdict=%s base=%s head=%s fetch=%s range=%s scanned=%s cfg_changed=%s gitleaks=%s reason=%s\n' \
    "$verdict" "$R_BASE" "$R_HEAD" "$R_FETCH" "$R_RANGE" "$R_SCANNED" "$R_CFG" "$R_GL" "$reason"
  if [ "$verdict" = NOT_RUN ]; then
    printf 'WARN: secret-scan NOT RUN (%s): the commits were not scanned locally; CI secret-scan.yml remains the gate.\n' "$reason" >&2
    printf 'secret-scan: not run (%s)\n' "$reason"
  fi
  exit "$final_rc"
}

# san <string> <max-len> — ASCII allowlist for every printed field that comes from PR content or a
# possibly hostile toml: ANSI escapes, newlines and prompt-injection text must not reach the transcript.
san() {
  printf '%s' "$1" | tr -cd '[:alnum:]._/@+=-' | cut -c1-"$2"
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

TOP=$(git rev-parse --show-toplevel 2>/dev/null) || TOP=""
[ -n "$TOP" ] || finish NOT_RUN not-a-work-tree

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

SCAN_T=120
case "${SOLEUR_PREPUSH_SCAN_TIMEOUT:-}" in
  '' | *[!0-9]*) ;;
  *)
    if [ "${#SOLEUR_PREPUSH_SCAN_TIMEOUT}" -le 3 ] && [ "$SOLEUR_PREPUSH_SCAN_TIMEOUT" -ge 1 ] && [ "$SOLEUR_PREPUSH_SCAN_TIMEOUT" -le 600 ]; then
      SCAN_T=$SOLEUR_PREPUSH_SCAN_TIMEOUT
    fi
    ;;
esac

# ── 2. preconditions, each a NOT_RUN with a named reason ──────────────────────────────────────
[ -f "$TOP/.gitleaks.toml" ] || finish NOT_RUN gitleaks-toml-absent

GL=$(type -P gitleaks 2>/dev/null) || GL=""
[ -n "$GL" ] || finish NOT_RUN gitleaks-absent

# Resolve symlinks to the real file and refuse one that lives inside the repo: a PR-controlled
# shim would run attacker code under this script's identity.
_p=$GL
while [ -L "$_p" ]; do
  _t=$(readlink "$_p")
  case "$_t" in
    /*) _p=$_t ;;
    *) _p="$(dirname "$_p")/$_t" ;;
  esac
done
_d=$(cd -P "$(dirname "$_p")" 2>/dev/null && pwd -P) || _d=""
[ -n "$_d" ] || finish NOT_RUN gitleaks-unrunnable
GLREAL="$_d/$(basename "$_p")"
TOPREAL=$(cd -P "$TOP" 2>/dev/null && pwd -P) || TOPREAL=$TOP
case "$GLREAL" in
  "$TOPREAL"/* | "$TOP"/*) finish NOT_RUN gitleaks-in-repo ;;
esac

# Probe by RUNNING it, from a neutral cwd: `command -v` alone certifies an unpinned version-manager
# shim that resolves and exits non-zero. A bound expiry (124/137) is a load condition, not a broken
# install, so it gets one wider retry before it is called a timeout.
GLVER=$(cd / && bounded 10 "$GLREAL" version 2>/dev/null </dev/null)
prc=$?
if [ "$prc" -eq 124 ] || [ "$prc" -eq 137 ]; then
  GLVER=$(cd / && bounded 60 "$GLREAL" version 2>/dev/null </dev/null)
  prc=$?
  if [ "$prc" -eq 124 ] || [ "$prc" -eq 137 ]; then
    finish NOT_RUN timeout
  fi
fi
[ "$prc" -eq 0 ] || finish NOT_RUN gitleaks-unrunnable
R_GL=$(printf '%s' "$GLVER" | sed -n '1p' | tr -cd '[:alnum:].-' | cut -c1-24)
[ -n "$R_GL" ] || R_GL=unknown

# ── 3. refresh (best effort) ──────────────────────────────────────────────────────────────────
# A stale base can only WIDEN the range (over-scan), so a failed fetch is a state, not a failure.
# A locally advanced refs/remotes/origin/main (update-ref, branch -f) narrows it, which is why the
# receipt prints both SHAs unabbreviated.
if [ "$DO_FETCH" -eq 1 ]; then
  (cd "$TOP" && bounded 10 git fetch --no-tags -q origin main) </dev/null >/dev/null 2>&1
  if [ $? -eq 0 ]; then
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
# above are load-bearing. No merge base (depth-1 hosted clone) means an over-scan of main's cut-off
# history would be attributed to this PR.
(cd "$TOP" && git merge-base "$BASE_SHA" "$HEAD_SHA") >/dev/null 2>&1 || finish NOT_RUN no-merge-base

N=$(cd "$TOP" && git rev-list --count --no-merges "$BASE_SHA..$HEAD_SHA" 2>/dev/null) || N=""
[[ "$N" =~ ^[0-9]+$ ]] || finish NOT_RUN range-unreadable
R_RANGE=$N
# E non-empty means at least one commit in range carries a patch (an empty commit has none).
E=$(cd "$TOP" && git log --no-merges --format= --name-only "$BASE_SHA..$HEAD_SHA" 2>/dev/null)
CFG=$(cd "$TOP" && git diff --name-only "$BASE_SHA..$HEAD_SHA" -- .gitleaks.toml .gitleaksignore .gitattributes 2>/dev/null)
[ -z "$CFG" ] || R_CFG=1

if [ "$N" -eq 0 ]; then
  R_SCANNED=0
  finish CLEAN empty-range
fi

# ── 5. scan ───────────────────────────────────────────────────────────────────────────────────
# BOTH colour surfaces are pinned: GIT_CONFIG_PARAMETERS is read AFTER the GIT_CONFIG_COUNT list and
# beats it, so a count-only pin loses to `git -c color.diff=always` in the caller's environment, and a
# coloured patch hides `+` lines from gitleaks. We APPEND to whatever the caller exported.
gl_cfg_n="${GIT_CONFIG_COUNT:-0}"
case "$gl_cfg_n" in '' | *[!0-9]*) gl_cfg_n=0 ;; esac
GLENV=(
  env
  "GIT_CONFIG_COUNT=$((gl_cfg_n + 2))" # mut:colorcount
  "GIT_CONFIG_KEY_${gl_cfg_n}=color.ui"
  "GIT_CONFIG_VALUE_${gl_cfg_n}=never"
  "GIT_CONFIG_KEY_$((gl_cfg_n + 1))=color.diff"
  "GIT_CONFIG_VALUE_$((gl_cfg_n + 1))=never"
  "GIT_CONFIG_PARAMETERS=${GIT_CONFIG_PARAMETERS:+${GIT_CONFIG_PARAMETERS} }'color.ui'='never' 'color.diff'='never'" # mut:colorparams
)

# stdout and stderr are captured to $TMP and never echoed: raw gitleaks output carries author emails.
(
  cd "$TOP" &&
    bounded "$SCAN_T" "${GLENV[@]}" \
      "$GLREAL" git \
      --redact \
      --no-banner \
      --exit-code 1 \
      --config "$TOP/.gitleaks.toml" \
      --report-format json \
      --report-path "$TMP/report.json" \
      --log-opts="--no-merges ${BASE_SHA}..${HEAD_SHA}" # mut:range
) </dev/null >"$TMP/out" 2>"$TMP/err"
scan_rc=$?

# ── 6. verdict. The ORDER is part of the contract. ─────────────────────────────────────────────
if [ "$scan_rc" -eq 124 ] || [ "$scan_rc" -eq 137 ]; then
  finish NOT_RUN timeout
fi
# A missing or zero-byte report is evaluated BEFORE any content branch, so rc 0 with no report can
# never reach CLEAN.
if [ ! -s "$TMP/report.json" ]; then
  finish NOT_RUN empty-report # mut:emptyreport
fi
REPORT=$(tr -d ' \t\r\n' <"$TMP/report.json")

# Best-effort count of commits gitleaks says it read (anchored; the last match wins).
SCANNED=$(cat "$TMP/out" "$TMP/err" 2>/dev/null | sed -En -e 's/^([0-9]+) commits? scanned.*$/\1/p' -e 's/^.*[^0-9]([0-9]+) commits? scanned.*$/\1/p' | tail -n 1)
if [[ "$SCANNED" =~ ^[0-9]+$ ]]; then
  R_SCANNED=$SCANNED
fi

if [ "$scan_rc" -eq 0 ] && [ "$REPORT" = '[]' ]; then
  if [[ "$SCANNED" =~ ^[0-9]+$ ]] && [ -n "$E" ]; then
    if [ "$SCANNED" -eq 0 ] || [ "$SCANNED" -gt "$N" ]; then
      finish NOT_RUN scanned-mismatch
    fi
  fi
  finish CLEAN no-findings
fi

if [ "$scan_rc" -ne 0 ] && [ "$scan_rc" -ne 1 ]; then
  finish NOT_RUN "gitleaks-rc-$(san "$scan_rc" 3)"
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
  printf '  finding: the report could not be summarised (jq absent or unparseable); rule ids: %s\n' \
    "$(grep -c '"RuleID"' "$TMP/report.json" 2>/dev/null)" >&2
fi
cat >&2 <<'EOF'
Remedy (the secret is never printed here):
  1. Commit still local: `git reset --soft origin/main`, remove the secret from the files, recommit
     (this squashes the range and re-runs the commit hook); tip commit only: `git commit --amend`.
  2. Commit already on origin: the secret is PUBLISHED. Rotate it first, then reset as above, then
     `git push --force-with-lease`, then follow the secret-scanning runbook (engineering/operations/secret-scanning.md).
  3. False positive: add a per-rule allowlist to .gitleaks.toml (review applies) and re-run.
Interactive ship asks before rewriting history; headless ship aborts here and never rewrites it unasked.
EOF
finish FINDINGS secret-found
