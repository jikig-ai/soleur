#!/usr/bin/env bash
# Tests for scripts/lint-credential-path-literals.py.
#
# The guard fails a tracked doc that writes a home-relative RESOLVABLE path to a
# real credential file (the Claude Code file-path auto-attach trigger — see the
# SUT docstring). Assert on EXIT CODES, not summary literals. Each case writes a
# throwaway .md via `mktemp` + heredoc so NO committed file carries a real
# credential literal (the trigger string exists only transiently during the run,
# under scripts/ — outside the guard's plugins/**+knowledge-base/** scope).
#
# Exit contract: 0 clean (or advisory-only), 1 hard-fail violation(s), 2 arg/git.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/lint-credential-path-literals.py"

PASS=0
FAIL=0
TOTAL=0

pass() { echo "PASS: $1"; PASS=$((PASS + 1)); TOTAL=$((TOTAL + 1)); }
fail() {
  echo "FAIL: $1"
  echo "  detail: ${2:-}"
  FAIL=$((FAIL + 1))
  TOTAL=$((TOTAL + 1))
}

TMPDIR_TEST="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_TEST"' EXIT

# mkcase writes stdin to a fresh .md file and echoes its path.
CASE_N=0
mkcase() {
  CASE_N=$((CASE_N + 1))
  local f="$TMPDIR_TEST/case_${CASE_N}.md"
  cat > "$f"
  printf '%s' "$f"
}

# run_case <name> <expected_exit> <file>
run_case() {
  local name="$1" expected="$2" file="$3"
  local actual=0
  python3 "$SUT" "$file" >/dev/null 2>&1 || actual=$?
  if [[ "$actual" == "$expected" ]]; then
    pass "$name"
  else
    fail "$name" "expected exit=$expected actual=$actual"
  fi
}

# run_case_reports <name> <expected_exit> <needle> <file>
# Asserts the exit code AND that <needle> appears in the report (stdout+stderr).
run_case_reports() {
  local name="$1" expected="$2" needle="$3" file="$4"
  local actual=0 out
  out="$(python3 "$SUT" "$file" 2>&1)" || actual=$?
  if [[ "$actual" != "$expected" ]]; then
    fail "$name" "expected exit=$expected actual=$actual"
    return
  fi
  if grep -qF "$needle" <<<"$out"; then
    pass "$name"
  else
    fail "$name" "report did not mention '$needle'"
  fi
}

# The resolvable Doppler-config trigger is assembled at RUNTIME from fragments so
# this .test.sh file itself never contains the literal string (it is a tracked
# doc under scripts/, out of guard scope, but hygiene is cheap and exemplary).
TILDE_DOPPLER_DIR='~/.doppler'
DOPPLER_CFG_NAME=".$(printf 'doppler').yaml"
DOPPLER_HOME_PATH="${TILDE_DOPPLER_DIR}/${DOPPLER_CFG_NAME}"     # ~/.doppler/.doppler.yaml
SSH_KEY_PATH='~/.ssh/id_ed25519'
DOCKER_HOME_PATH='~/.docker/config.json'

# ---------------------------------------------------------------------------
# Positive (non-vacuity — REQUIRED). A resolvable home-relative credential path
# must FAIL. If any of these ever pass, the guard has gone vacuous.
# ---------------------------------------------------------------------------

# P1 — home-relative resolvable Doppler config path FAILS.
f="$(printf '# Doc\n\nThe CLI reads its token from `%s` on disk.\n' "$DOPPLER_HOME_PATH" | mkcase)"
run_case "P1 home-relative Doppler config path FAILS" 1 "$f"

# P2 — the BARE Doppler config filename FAILS (root project-pointer resolves it).
f="$(printf '# Doc\n\nEdit the `%s` file at the repo root.\n' "$DOPPLER_CFG_NAME" | mkcase)"
run_case "P2 bare Doppler config filename FAILS" 1 "$f"

# P3 — a ~/.ssh/ private key path FAILS.
f="$(printf '# Doc\n\nThe host key lives at `%s`.\n' "$SSH_KEY_PATH" | mkcase)"
run_case "P3 ssh private key path FAILS" 1 "$f"

# P4 — $HOME/ prefix form FAILS (equivalent resolvability to ~/).
f="$(printf '# Doc\n\nRead the netrc at `$HOME/.netrc` before the probe.\n' | mkcase)"
run_case "P4 \$HOME/.netrc path FAILS" 1 "$f"

# P5 — AWS creds under its credential dir FAILS.
f="$(printf '# Doc\n\nAWS keys sit in `~/.aws/credentials` on the box.\n' | mkcase)"
run_case "P5 ~/.aws/credentials path FAILS" 1 "$f"

# P6 — the reject-message read shape (report must name file+line + a recipe).
f="$(printf '# Doc\n\nexfil `%s`\n' "$DOPPLER_HOME_PATH" | mkcase)"
run_case_reports "P6 hard-fail report names the neutralization recipe" 1 "~/.doppler/" "$f"

# P7 — the ${HOME} BRACE form resolves like $HOME; an SSH key under it must FAIL
#      (it has no bare-filename fallback arm, unlike the Doppler config).
f="$(printf '# Doc\n\nkey at `${HOME}/.ssh/id_rsa`\n' | mkcase)"
run_case "P7 \${HOME} brace-form ssh key FAILS" 1 "$f"

# ---------------------------------------------------------------------------
# Negative — the NEUTRALIZED forms this PR introduced must PASS.
# ---------------------------------------------------------------------------

# N1 — the descriptive Doppler form (directory-only) PASSES.
f="$(printf '# Doc\n\nthe Doppler CLI config under `~/.doppler/`.\n' | mkcase)"
run_case "N1 directory-only ~/.doppler/ PASSES" 0 "$f"

# N2 — the descriptive readable-files list (no resolvable path) PASSES.
f="$(printf '# Doc\n\nthe Doppler CLI token, SSH private keys, netrc, git credentials, AWS credentials, the gcloud credentials database, and the Docker config are all readable.\n' | mkcase)"
run_case "N2 descriptive readable-files list PASSES" 0 "$f"

# N3 — the ssh directory + "private keys" prose (no id_* file) PASSES.
f="$(printf '# Doc\n\nSSH private keys under `~/.ssh/` stay reachable.\n' | mkcase)"
run_case "N3 ~/.ssh/ dir + prose PASSES" 0 "$f"

# N4 — the @<doppler-config> placeholder exfil shape PASSES.
f="$(printf '# Doc\n\na `curl --data-binary @<doppler-config>` exfiltration.\n' | mkcase)"
run_case "N4 @<doppler-config> placeholder PASSES" 0 "$f"

# ---------------------------------------------------------------------------
# Boundary — near-miss forms must NOT match (over-reach guards).
# ---------------------------------------------------------------------------

# B1 — ~/.doppler/ directory only (no filename) does NOT match.
f="$(printf '# Doc\n\nthe home Doppler directory (`~/.doppler/`).\n' | mkcase)"
run_case "B1 ~/.doppler/ dir-only no match" 0 "$f"

# B2 — a .pub public key does NOT match (private-key-only class).
f="$(printf '# Doc\n\nput `~/.ssh/id_ed25519.pub` in authorized_keys.\n' | mkcase)"
run_case "B2 id_ed25519.pub public key no match" 0 "$f"

# B3 — a suffixed/embedded Doppler name (.bak) does NOT match the bare filename.
BAK_NAME="app${DOPPLER_CFG_NAME}.bak"
f="$(printf '# Doc\n\nrestore from `%s` if needed.\n' "$BAK_NAME" | mkcase)"
run_case "B3 suffixed .bak embedded name no match" 0 "$f"

# B4 — a bare generic 'credentials' filename WITHOUT its ~/.aws/ dir no match
#      (the generic filename must never match outside its credential dir).
f="$(printf '# Doc\n\nrotate the `credentials` file in the vault.\n' | mkcase)"
run_case "B4 bare generic credentials filename no match" 0 "$f"

# ---------------------------------------------------------------------------
# Advisory — remote-host forms are REPORT-ONLY: exit 0 but listed in the report.
# ---------------------------------------------------------------------------

# A1 — a /home/deploy/-prefixed Docker config → exit 0 (advisory), but reported.
f="$(printf '# Runbook\n\nThe deploy host reads `/home/deploy/.docker/config.json`.\n' | mkcase)"
run_case_reports "A1 /home/deploy/ docker config is advisory (exit 0, reported)" 0 "advisory" "$f"

# A2 — a /root/-prefixed credential → exit 0 (advisory).
f="$(printf '# Runbook\n\nThe root user reads `/root/.aws/credentials` on the box.\n' | mkcase)"
run_case "A2 /root/ aws credentials is advisory (exit 0)" 0 "$f"

# ---------------------------------------------------------------------------
# --changed fail-closed when the merge base can't resolve → exit 2.
# ---------------------------------------------------------------------------
c_status=0
(
  set -e
  REPO="$TMPDIR_TEST/nogit"
  mkdir -p "$REPO"
  cd "$REPO"
  git init -q -b feature-only .
  git config user.email t@t && git config user.name t
  mkdir -p plugins/soleur/skills/x
  echo "# clean" > plugins/soleur/skills/x/SKILL.md
  git add -A && git commit -q -m init
  rc=0
  python3 "$SUT" --changed --base does-not-exist-ref >/dev/null 2>&1 || rc=$?
  [[ "$rc" == "2" ]]
) || c_status=$?
if [[ "$c_status" == "0" ]]; then
  pass "C1 --changed unresolvable base → exit 2"
else
  fail "C1 --changed unresolvable base → exit 2" "sub-shell status=$c_status"
fi

# ---------------------------------------------------------------------------
# --changed grandfathering: an UNCHANGED historical violation is NOT flagged,
# but a NEWLY-changed doc with the same violation IS.
# ---------------------------------------------------------------------------
g_status=0
(
  set -e
  REPO="$TMPDIR_TEST/gitgf"
  mkdir -p "$REPO"
  cd "$REPO"
  git init -q -b main .
  git config user.email t@t && git config user.name t
  mkdir -p knowledge-base/project/plans
  # Historical doc already carrying a resolvable path — committed on main.
  printf '# old\n\ntoken at `%s`\n' "$DOPPLER_HOME_PATH" \
    > knowledge-base/project/plans/old.md
  git add -A && git commit -q -m base
  git checkout -q -b feature
  # A NEW doc introduces the same violation on the feature branch.
  printf '# new\n\ntoken at `%s`\n' "$DOPPLER_HOME_PATH" \
    > knowledge-base/project/plans/new.md
  git add -A && git commit -q -m feat
  rc=0
  out="$(python3 "$SUT" --changed --base main 2>&1)" || rc=$?
  # Hard-fail on the CHANGED file, grandfather the UNCHANGED one.
  [[ "$rc" == "1" ]]
  grep -q 'new.md' <<<"$out"
  ! grep -q 'old.md' <<<"$out"
) || g_status=$?
if [[ "$g_status" == "0" ]]; then
  pass "C2 --changed grandfathers unchanged, flags changed"
else
  fail "C2 --changed grandfathers unchanged, flags changed" "sub-shell status=$g_status"
fi

# ---------------------------------------------------------------------------
# archive/ carve-out — a violation under **/archive/** is skipped in full-scan.
# ---------------------------------------------------------------------------
a_status=0
(
  set -e
  REPO="$TMPDIR_TEST/gitarch"
  mkdir -p "$REPO"
  cd "$REPO"
  git init -q -b main .
  git config user.email t@t && git config user.name t
  mkdir -p knowledge-base/archive
  printf '# archived\n\ntoken at `%s`\n' "$DOPPLER_HOME_PATH" \
    > knowledge-base/archive/old.md
  git add -A && git commit -q -m base
  rc=0
  python3 "$SUT" >/dev/null 2>&1 || rc=$?   # full-scan
  [[ "$rc" == "0" ]]
) || a_status=$?
if [[ "$a_status" == "0" ]]; then
  pass "C3 archive/ path excluded from full-scan"
else
  fail "C3 archive/ path excluded from full-scan" "sub-shell status=$a_status"
fi

# ---------------------------------------------------------------------------
# Minimum-cardinality guard (an empty/short run must not GREEN).
# ---------------------------------------------------------------------------
MIN_CASES=19
echo
echo "PASS=$PASS FAIL=$FAIL TOTAL=$TOTAL"
if [[ "$TOTAL" -lt "$MIN_CASES" ]]; then
  echo "GUARD FAIL: ran ${TOTAL} assertions, expected >= ${MIN_CASES}" >&2
  exit 2
fi
[[ "$FAIL" -eq 0 ]]
