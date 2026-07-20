#!/usr/bin/env bash
#
# Tests for the git-data in-band TRANSPORT allowlist forced-command wrapper
# (git-data-transport-wrapper.sh, Sub-PR 3.D / ADR-068 §6). Exercises: the two git
# server verbs (hyphen AND space forms) are ACCEPTED against a real per-workspace
# bare-repo path; every non-transport command (interactive shell, `git gc`, `rm`,
# chained `;`) is REJECTED; dot-path traversal, an escaping relative path, a symlink
# planted at the repo path, a nested (non-direct-child) path, and a non-existent repo
# are all REJECTED before any exec. Accept cases use the test-only EXEC_DRYRUN hook
# (sshd never passes it — AcceptEnv empty, same posture as GIT_DATA_REPO_ROOT) so we
# assert the canonicalized command WITHOUT a live git-upload-pack handshake.
#
# MUTATION meta-check: the reject inputs are ALSO run against an always-exit-0 stub
# wrapper; each MUST exit 0 there — proving the real wrapper's non-zero is what
# rejects them (a reject assertion that a broken wrapper would still "pass" has no
# teeth — the bash-gate-authoring foot-gun). Reject-by-design commands are captured
# in `$(… )` command-subs so `set -e` never aborts the harness.
#
# Run: bash apps/web-platform/infra/git-data-transport-wrapper.test.sh
# Registered as a step in .github/workflows/infra-validation.yml.

set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WRAPPER="${DIR}/git-data-transport-wrapper.sh"

passes=0
fails=0
pass() { passes=$((passes + 1)); }
fail() { fails=$((fails + 1)); echo "FAIL: $1" >&2; }

[ -f "$WRAPPER" ] || { echo "FAIL: wrapper not found at $WRAPPER" >&2; exit 1; }

# Run the wrapper (DRYRUN so a valid command echoes instead of exec-ing real git).
# Echoes the exit code. Runs WITHOUT set -e propagation (reject cases exit 1 by design).
run_wrap() {
  local root="$1" cmd="$2"
  env -i PATH="$PATH" GIT_DATA_REPO_ROOT="$root" GIT_DATA_TRANSPORT_EXEC_DRYRUN=1 \
    SSH_ORIGINAL_COMMAND="$cmd" bash "$WRAPPER" >/dev/null 2>&1
  echo $?
}
# Capture stdout of an accepted (dry-run) command.
run_wrap_out() {
  local root="$1" cmd="$2"
  env -i PATH="$PATH" GIT_DATA_REPO_ROOT="$root" GIT_DATA_TRANSPORT_EXEC_DRYRUN=1 \
    SSH_ORIGINAL_COMMAND="$cmd" bash "$WRAPPER" 2>/dev/null
}

fresh_root() { mktemp -d "${TMPDIR:-/tmp}/gdxport.XXXXXX"; }
make_repo()  { mkdir -p "${1}/${2}.git"; }  # a plausible bare-repo dir so readlink -f resolves

# --- T1: git-upload-pack (hyphen form) on a real repo is ACCEPTED ---
root=$(fresh_root); make_repo "$root" "ws-1"
rc=$(run_wrap "$root" "git-upload-pack '${root}/ws-1.git'")
if [ "$rc" = "0" ]; then pass; else fail "T1 git-upload-pack hyphen: expected accept (0), got $rc"; fi
out=$(run_wrap_out "$root" "git-upload-pack '${root}/ws-1.git'")
case "$out" in *"DRYRUN-EXEC git-upload-pack ${root}/ws-1.git"*) pass ;; *) fail "T1 expected canonicalized exec of git-upload-pack, got: $out" ;; esac
rm -rf "$root"

# --- T2: git receive-pack (space form) on a real repo is ACCEPTED ---
root=$(fresh_root); make_repo "$root" "ws-2"
rc=$(run_wrap "$root" "git receive-pack '${root}/ws-2.git'")
if [ "$rc" = "0" ]; then pass; else fail "T2 git receive-pack space-form: expected accept (0), got $rc"; fi
out=$(run_wrap_out "$root" "git receive-pack '${root}/ws-2.git'")
case "$out" in *"DRYRUN-EXEC git-receive-pack ${root}/ws-2.git"*) pass ;; *) fail "T2 expected canonicalized exec of git-receive-pack, got: $out" ;; esac
rm -rf "$root"

# --- T3: arbitrary / non-transport commands are REJECTED ---
root=$(fresh_root); make_repo "$root" "ws-3"
# shellcheck disable=SC2016 # these are LITERAL command strings under test — no expansion
for bad in \
  "" \
  "ls -la" \
  "git gc" \
  "rm -rf /" \
  "bash -i" \
  "git-upload-pack" \
  "scp -t /tmp/x" \
  "git-upload-pack '${root}/ws-3.git'; rm -rf /" \
  "git-upload-pack '${root}/ws-3.git' && id" \
  '$(id)' ; do
  rc=$(run_wrap "$root" "$bad")
  if [ "$rc" != "0" ]; then pass; else fail "T3 non-transport '$bad': expected reject (non-zero), got 0"; fi
done
rm -rf "$root"

# --- T4: dot-path traversal + escaping paths are REJECTED ---
root=$(fresh_root); make_repo "$root" "ws-4"
outside="$(mktemp -d "${TMPDIR:-/tmp}/gdxport-out.XXXXXX")"; make_repo "$outside" "evil"
for bad in \
  "git-upload-pack '${root}/../etc/passwd'" \
  "git-upload-pack '${root}/../$(basename "$outside")/evil.git'" \
  "git-receive-pack '../evil.git'" \
  "git-upload-pack '${outside}/evil.git'" ; do
  rc=$(run_wrap "$root" "$bad")
  if [ "$rc" != "0" ]; then pass; else fail "T4 traversal/escape '$bad': expected reject, got 0"; fi
done
rm -rf "$root" "$outside"

# --- T5: a symlink planted AT the repo path cannot redirect the verb outside ---
root=$(fresh_root)
outside="$(mktemp -d "${TMPDIR:-/tmp}/gdxport-sym.XXXXXX")"; make_repo "$outside" "target"
ln -s "${outside}/target.git" "${root}/ws-sym.git"  # resolves outside the root
rc=$(run_wrap "$root" "git-upload-pack '${root}/ws-sym.git'")
if [ "$rc" != "0" ]; then pass; else fail "T5 symlink repo path: expected reject, got 0"; fi
rm -rf "$root" "$outside"

# --- T6: a nested (non-direct-child) path under the root is REJECTED ---
root=$(fresh_root); mkdir -p "${root}/sub/ws-nested.git"
rc=$(run_wrap "$root" "git-upload-pack '${root}/sub/ws-nested.git'")
if [ "$rc" != "0" ]; then pass; else fail "T6 nested path: expected reject, got 0"; fi
rm -rf "$root"

# --- T7: a non-existent repo (readlink cannot resolve) is REJECTED ---
root=$(fresh_root)
rc=$(run_wrap "$root" "git-upload-pack '${root}/ws-absent.git'")
if [ "$rc" != "0" ]; then pass; else fail "T7 absent repo: expected reject, got 0"; fi
rm -rf "$root"

# --- MUTATION meta-check: the reject assertions have teeth ---
# An always-exit-0 stub stands in for a wrapper whose allowlist/canonicalize guard
# was removed. Representative reject inputs MUST exit 0 against it — i.e. WITHOUT the
# real guard they would sail through, so the T3/T4 `rc != 0` checks are meaningful.
stub="$(mktemp "${TMPDIR:-/tmp}/gdxport-stub.XXXXXX")"
printf '#!/usr/bin/env bash\nexit 0\n' > "$stub"
chmod +x "$stub"
mut_root=$(fresh_root)
for bad in "rm -rf /" "git-upload-pack '${mut_root}/../etc/passwd'"; do
  rc=$(env -i PATH="$PATH" SSH_ORIGINAL_COMMAND="$bad" bash "$stub" >/dev/null 2>&1; echo $?)
  if [ "$rc" = "0" ]; then pass; else fail "MUTATION: stub-accept did not exit 0 for '$bad' — reject assertion may have no teeth"; fi
done
rm -f "$stub"; rm -rf "$mut_root"

# --- Minimum-cardinality guard (a silent-empty extraction must fail loud) ---
total=$((passes + fails))
if [ "$total" -lt 22 ]; then
  echo "FAIL: ran only ${total} assertions (<22) — suite did not execute fully" >&2
  exit 1
fi

echo "git-data-transport-wrapper: ${passes} passed, ${fails} failed (${total} assertions)"
[ "$fails" -eq 0 ]
