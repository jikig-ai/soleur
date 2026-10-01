#!/usr/bin/env bash
#
# Tests for the git-data in-band TRANSPORT allowlist forced-command wrapper
# (git-data-transport-wrapper.sh, Sub-PR 3.D / ADR-068 §6). Exercises: the two git
# server verbs (hyphen AND space forms) are ACCEPTED against a real per-workspace
# bare-repo path; every non-transport command (interactive shell, `git gc`, `rm`,
# chained `;`) is REJECTED; dot-path traversal, an escaping relative path, a symlink
# planted at the repo path, a nested (non-direct-child) path, and a non-existent repo
# are all REJECTED before any exec. Accept cases use the test-only EXEC_DRYRUN hook
# (sshd never passes it — `AcceptEnv LANG LC_*` cannot match the name, same posture as
# GIT_DATA_REPO_ROOT; #8043 F10) so we assert the canonicalized command WITHOUT a live
# git-upload-pack handshake. (#8043 review) The store-mounted guard the wrapper shares with
# provision/remove is exercised against a REAL mount (`stat -c %m` of the fixture root),
# not a stub, and the exec'd argv must carry the `core.hooksPath` pin.
#
# MUTATION meta-check: the reject inputs are ALSO run against an always-exit-0 stub
# wrapper; each MUST exit 0 there — proving the real wrapper's non-zero is what
# rejects them (a reject assertion that a broken wrapper would still "pass" has no
# teeth — the bash-gate-authoring foot-gun). Reject-by-design commands are captured
# in `$(… )` command-subs so `set -e` never aborts the harness.
#
# Run: bash apps/web-platform/infra/git-data-transport-wrapper.test.sh
# Presence under apps/web-platform/infra/ IS registration — derived and run by run-registered-suites.sh (#8736).

set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

# Refuses an empty, relative, root or synthetic-fs fixture dir (byte-identical copy; the
# fixture-dir-operand-assert suite pins every tracked copy).
assert_fixture_dir() {
  case "${1-}" in
    "") printf 'FATAL: fixture dir is EMPTY; git -C "" would operate on %s\n' "$PWD" >&2; exit 2 ;;
    */../*|*/..) printf 'FATAL: fixture dir %s contains ..; refusing\n' "$1" >&2; exit 2 ;;
    /proc/*|/sys/*|/dev/*) printf 'FATAL: fixture dir %s is a synthetic-fs path; refusing\n' "$1" >&2; exit 2 ;;
    /|//|/.) printf 'FATAL: fixture dir resolves to the filesystem root; refusing\n' >&2; exit 2 ;;
    /*) : ;;
    *)  printf 'FATAL: fixture dir %s is RELATIVE; refusing\n' "$1" >&2; exit 2 ;;
  esac
}
# The C1 rows below clean up through this rather than a bare `rm -rf "$root"`, so the P1b
# fixture-relative ratchet has a guard correlated with the operand and the new rows add no
# grandfathered residue to its baseline.
drop_fixture() { assert_fixture_dir "$1"; rm -rf "$1"; }

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WRAPPER="${DIR}/git-data-transport-wrapper.sh"

passes=0
fails=0
pass() { passes=$((passes + 1)); }
fail() { fails=$((fails + 1)); echo "FAIL: $1" >&2; }

[ -f "$WRAPPER" ] || { echo "FAIL: wrapper not found at $WRAPPER" >&2; exit 1; }

# Run the wrapper (DRYRUN so a valid command echoes instead of exec-ing real git).
# Echoes the exit code. Runs WITHOUT set -e propagation (reject cases exit 1 by design).
# $3 (optional) overrides the mount root; the default is the mount the fixture root sits on.
ERR="$(mktemp "${TMPDIR:-/tmp}/gdxport-err.XXXXXX")"
# (#8211, ADR-239) C1 store seams, derived from the real temp root — see the remove suite's
# runner for the derivation and the UUID-less-filesystem stub (identical block).
FM_REAL="$(command -v findmnt)" || { echo "FAIL SETUP: findmnt(8) not on PATH" >&2; exit 1; }
SEAMS="$(mktemp -d "${TMPDIR}/gdxport-seams.XXXXXX")"
trap 'rm -f "$ERR"; rm -rf "$SEAMS"' EXIT

# (#7849) The C1 rows build real bare repos, so this suite spawns a MUTATING git and owes the
# shared fixture-env builder. An inherited GIT_DIR retargets `git init` at the caller's real
# repository — cwd does not win that fight — so a raw environment here would act on the
# operator's checkout while reading exactly like a sandbox.
_GFE_LIB="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../../../plugins/soleur/test/lib" 2>/dev/null && pwd -P)/git-fixture-env.sh"
[ -f "$_GFE_LIB" ] && [ -r "$_GFE_LIB" ] \
  || { printf 'FAIL SETUP: fixture-env helper missing or unreadable at %s\n' "$_GFE_LIB" >&2; exit 1; }
# shellcheck source=../../../plugins/soleur/test/lib/git-fixture-env.sh
source "$_GFE_LIB"
MNT0="$(stat -c %m "$SEAMS")"
STORE_SRC="$(findmnt -n -o SOURCE --mountpoint "$MNT0")" || STORE_SRC=""
STORE_UUID="$(findmnt -n -o UUID --mountpoint "$MNT0")" || STORE_UUID=""
[ -n "$STORE_SRC" ] || { echo "FAIL SETUP: findmnt prints no SOURCE for $MNT0" >&2; exit 1; }
mkdir -p "$SEAMS/fm"; : > "$SEAMS/uuids"
if [ -z "$STORE_UUID" ]; then
  STORE_UUID="0b1d0000-8211-4000-8000-000000000001"
  printf '%s %s\n' "$MNT0" "$STORE_UUID" >> "$SEAMS/uuids"
  echo "NOTE: $MNT0 ($STORE_SRC) has no filesystem UUID — findmnt UUID stub in use for it"
fi
printf '/proc %s\n' "$STORE_UUID" >> "$SEAMS/uuids"
cat > "$SEAMS/fm/findmnt" <<STUB
#!/usr/bin/env bash
if [ "\$#" = 5 ] && [ "\$1 \$2 \$3 \$4" = "-n -o UUID --mountpoint" ]; then
  while read -r m u; do [ "\$m" = "\$5" ] && { printf '%s\n' "\$u"; exit 0; }; done < "$SEAMS/uuids"
fi
exec "$FM_REAL" "\$@"
STUB
chmod +x "$SEAMS/fm/findmnt"
printf '%s\n' "$STORE_UUID" > "$SEAMS/marker"
SPATH="$SEAMS/fm:$PATH"
dev_for() { findmnt -n -o SOURCE --mountpoint "$1" 2>/dev/null || true; }
run_wrap() {
  local root="$1" cmd="$2" mnt="${3:-}"
  [ -n "$mnt" ] || mnt="$(stat -c %m "$root")"
  env -i PATH="$SPATH" GIT_DATA_REPO_ROOT="$root" GIT_DATA_MOUNT_ROOT="$mnt" GIT_DATA_TRANSPORT_EXEC_DRYRUN=1 \
    GIT_DATA_STORE_DEVICE="$(dev_for "$mnt")" GIT_DATA_STORE_VERIFIED="$SEAMS/marker" \
    SSH_ORIGINAL_COMMAND="$cmd" bash "$WRAPPER" >/dev/null 2>"$ERR"
  echo $?
}
# Capture stdout of an accepted (dry-run) command.
run_wrap_out() {
  local root="$1" cmd="$2"
  env -i PATH="$SPATH" GIT_DATA_REPO_ROOT="$root" GIT_DATA_MOUNT_ROOT="$(stat -c %m "$root")" GIT_DATA_TRANSPORT_EXEC_DRYRUN=1 \
    GIT_DATA_STORE_DEVICE="$STORE_SRC" GIT_DATA_STORE_VERIFIED="$SEAMS/marker" \
    SSH_ORIGINAL_COMMAND="$cmd" bash "$WRAPPER" 2>/dev/null
}
# C1 variant: explicit seams, and NO dry-run — an accepted command really execs git, so the
# must-PASS row proves the exec was reached (upload-pack's ref advertisement on stdout).
# Stdin is one pkt-line flush ("0000"), which is what a client sends to end the negotiation:
# with /dev/null instead, upload-pack advertises and then dies rc 128 "the remote end hung up",
# so the accepted row could not be told apart from a refusal by exit code.
run_wrap_c1() {
  local root="$1" cmd="$2" dev="$3" marker="$4" path="${5:-$SPATH}"
  env -i PATH="$path" GIT_DATA_REPO_ROOT="$root" GIT_DATA_MOUNT_ROOT="$(stat -c %m "$root")" \
    GIT_DATA_HOOKS_DIR="$SEAMS/hooks" GIT_DATA_STORE_DEVICE="$dev" GIT_DATA_STORE_VERIFIED="$marker" \
    SSH_ORIGINAL_COMMAND="$cmd" bash "$WRAPPER" <"$SEAMS/flush" >"$SEAMS/out" 2>"$ERR"
  echo $?
}
printf '0000' > "$SEAMS/flush"

fresh_root() { mktemp -d "${TMPDIR:-/tmp}/gdxport.XXXXXX"; }
make_repo()  { mkdir -p "${1}/${2}.git"; }  # a plausible bare-repo dir so readlink -f resolves

# --- T1: git-upload-pack (hyphen form) on a real repo is ACCEPTED ---
root=$(fresh_root); make_repo "$root" "ws-1"
rc=$(run_wrap "$root" "git-upload-pack '${root}/ws-1.git'")
if [ "$rc" = "0" ]; then pass; else fail "T1 git-upload-pack hyphen: expected accept (0), got $rc"; fi
out=$(run_wrap_out "$root" "git-upload-pack '${root}/ws-1.git'")
case "$out" in *"DRYRUN-EXEC git -c core.hooksPath=/mnt/git-data/hooks upload-pack ${root}/ws-1.git"*) pass ;; *) fail "T1 expected canonicalized exec of upload-pack through the hooksPath pin, got: $out" ;; esac
rm -rf "$root"

# --- T2: git receive-pack (space form) on a real repo is ACCEPTED ---
root=$(fresh_root); make_repo "$root" "ws-2"
rc=$(run_wrap "$root" "git receive-pack '${root}/ws-2.git'")
if [ "$rc" = "0" ]; then pass; else fail "T2 git receive-pack space-form: expected accept (0), got $rc"; fi
out=$(run_wrap_out "$root" "git receive-pack '${root}/ws-2.git'")
case "$out" in *"DRYRUN-EXEC git -c core.hooksPath=/mnt/git-data/hooks receive-pack ${root}/ws-2.git"*) pass ;; *) fail "T2 expected canonicalized exec of receive-pack through the hooksPath pin, got: $out" ;; esac
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

# --- T8 (#8043 review, Guard 1 on the third forced command): an UNMOUNTED store is a
#     named refusal. The mount root is pointed at a plain directory. ---
root=$(fresh_root); make_repo "$root" "ws-unm"
unmounted="$(mktemp -d "${TMPDIR:-/tmp}/gdxport-unm.XXXXXX")"
if mountpoint -q "$unmounted"; then fail "T8 fixture: $unmounted is unexpectedly a mount point"; fi
rc=$(run_wrap "$root" "git-receive-pack '${root}/ws-unm.git'" "$unmounted")
if [ "$rc" != "0" ]; then pass; else fail "T8 unmounted store: expected refusal, got 0"; fi
if grep -q 'not mounted' "$ERR"; then pass; else fail "T8 unmounted store: refusal does not name the mount ($(head -c 200 "$ERR"))"; fi
rm -rf "$root" "$unmounted"

# --- T9 (#8043 review): a MOUNTED store whose repo root is NOT ON IT → refuse. /proc is a
#     mount on every Linux runner; the fixture root is not on it. ---
root=$(fresh_root); make_repo "$root" "ws-off"
rc=$(run_wrap "$root" "git-receive-pack '${root}/ws-off.git'" "/proc")
if [ "$rc" != "0" ]; then pass; else fail "T9 root off the store: expected refusal, got 0"; fi
if grep -q 'is not on the store' "$ERR"; then pass; else fail "T9 root off the store: refusal does not name the containment ($(head -c 200 "$ERR"))"; fi
rm -rf "$root"

# --- T10 (#8043 review): mountpoint(1) ABSENT from PATH → fails CLOSED, naming the
#     instrument (curated PATH of symlinks to everything else the wrapper needs). ---
root=$(fresh_root); make_repo "$root" "ws-noinst"
curated="$(mktemp -d "${TMPDIR:-/tmp}/gdxport-path.XXXXXX")"
for tool in bash readlink dirname stat git; do
  src="$(command -v "$tool")" && ln -s "$src" "${curated}/${tool}"
done
env -i PATH="$curated" GIT_DATA_REPO_ROOT="$root" GIT_DATA_MOUNT_ROOT="$(stat -c %m "$root")" GIT_DATA_TRANSPORT_EXEC_DRYRUN=1 \
  GIT_DATA_STORE_DEVICE="$STORE_SRC" GIT_DATA_STORE_VERIFIED="$SEAMS/marker" SSH_ORIGINAL_COMMAND="git-receive-pack '${root}/ws-noinst.git'" bash "$WRAPPER" >/dev/null 2>"$ERR"; rc=$?
if [ "$rc" != "0" ]; then pass; else fail "T10 mountpoint absent: expected fail-closed, got 0"; fi
if grep -qF 'mountpoint(1) not on PATH' "$ERR"; then pass; else fail "T10 mountpoint absent: refusal does not name the instrument ($(head -c 200 "$ERR"))"; fi
rm -rf "$root" "$curated"

# --- T11 (#8043 review): the hooksPath pin is a SEAM with the bootstrap's literal, and the
#     exec form is `git -c core.hooksPath=<dir> <verb>` — never the bare `git-<verb>` binary,
#     which would let a repo-local core.hooksPath (git-writable) outrank the root-owned fence. ---
root=$(fresh_root); make_repo "$root" "ws-pin"
out=$(env -i PATH="$SPATH" GIT_DATA_REPO_ROOT="$root" GIT_DATA_MOUNT_ROOT="$(stat -c %m "$root")" GIT_DATA_HOOKS_DIR="/srv/h" \
  GIT_DATA_STORE_DEVICE="$STORE_SRC" GIT_DATA_STORE_VERIFIED="$SEAMS/marker" \
  GIT_DATA_TRANSPORT_EXEC_DRYRUN=1 SSH_ORIGINAL_COMMAND="git-receive-pack '${root}/ws-pin.git'" bash "$WRAPPER" 2>/dev/null)
case "$out" in *"git -c core.hooksPath=/srv/h receive-pack ${root}/ws-pin.git"*) pass ;; *) fail "T11 hooksPath seam: expected the overridden pin in the exec argv, got: $out" ;; esac
if grep -qE '^exec git -c "core\.hooksPath=\$\{HOOKS_DIR\}" "\$\{verb#git-\}" "\$repo_real"$' "$WRAPPER"; then pass; else fail "T11 the live exec line does not pin core.hooksPath through git -c"; fi
rm -rf "$root"

# --- T12 (#8043 review): the CUTOVER FREEZE sentinel refuses transport (both verbs), via
#     the same GIT_DATA_CUTOVER_FREEZE seam the fence and the other wrappers carry. ---
root=$(fresh_root); make_repo "$root" "ws-frz"; : > "${root}/.frozen"
for v in git-upload-pack git-receive-pack; do
  rc=$(env -i PATH="$SPATH" GIT_DATA_REPO_ROOT="$root" GIT_DATA_MOUNT_ROOT="$(stat -c %m "$root")" GIT_DATA_CUTOVER_FREEZE="${root}/.frozen" \
    GIT_DATA_STORE_DEVICE="$STORE_SRC" GIT_DATA_STORE_VERIFIED="$SEAMS/marker" \
    GIT_DATA_TRANSPORT_EXEC_DRYRUN=1 SSH_ORIGINAL_COMMAND="$v '${root}/ws-frz.git'" bash "$WRAPPER" >/dev/null 2>"$ERR"; echo $?)
  if [ "$rc" != "0" ] && grep -q 'frozen for cutover' "$ERR"; then pass; else fail "T12 cutover freeze ($v): expected named refusal, got rc=$rc ($(head -c 120 "$ERR"))"; fi
done
if grep -qF 'cutover_freeze="${GIT_DATA_CUTOVER_FREEZE:-${MOUNT_ROOT}/.cutover-freeze}"' "$WRAPPER"; then pass; else fail "T12 the freeze sentinel default is not <mount root>/.cutover-freeze"; fi
rm -rf "$root"

# ── (#8211, ADR-239) C1 — transport only on a verified, mapper-served store (Guard 1) ─────
# Run WITHOUT the dry-run hook, so "accepted" means git really exec'd. Refusal is `reject`
# (exit 1) and the ORDER assertion is that git never ran: no ref advertisement on stdout.
# Return checked: git_fixture_env exports NOTHING when it refuses, so an unchecked call would
# build the fixture under the caller's own environment while reading like protection. The
# operand is the PARENT: "$1" is the bare repo git init is about to create.
fixture_bare() {
  git_fixture_env "$(dirname "$1")" || { printf 'FAIL SETUP: git_fixture_env refused %s\n' "$(dirname "$1")" >&2; exit 1; }
  git init --bare -q "$1" && git --git-dir="$1" symbolic-ref HEAD refs/heads/main
}
c1_refused() { # c1_refused <row> <rc> <anchor>
  if [ "$2" = "1" ]; then pass; else fail "$1: expected exit 1 (reject), got $2 ($(head -c 200 "$ERR"))"; fi
  if grep -qF "$3" "$ERR"; then pass; else fail "$1: refusal does not carry '$3' ($(head -c 200 "$ERR"))"; fi
  if [ ! -s "$SEAMS/out" ]; then pass; else fail "$1: ORDER — git was exec'd before (or despite) the store refusal"; fi
}
mkdir -p "$SEAMS/hooks"
# C1a MUST-PASS: the seam is the temp root's own --mountpoint SOURCE, the marker its UUID —
# upload-pack is exec'd and advertises (a bare repo with no refs still prints the flush/caps).
root=$(fresh_root); fixture_bare "${root}/ws-c1.git"
rc=$(run_wrap_c1 "$root" "git-upload-pack '${root}/ws-c1.git'" "$STORE_SRC" "$SEAMS/marker")
if [ "$rc" = "0" ]; then pass; else fail "C1a must-PASS: expected 0 with the store verified, got $rc ($(head -c 200 "$ERR"))"; fi
if [ -s "$SEAMS/out" ]; then pass; else fail "C1a must-PASS: upload-pack produced no advertisement — the exec was not reached"; fi
# C1b mismatch; C1c look-alikes derived from the real SOURCE; C1d marker absent; C1e marker
# for another volume; C1f findmnt(8) absent from a curated PATH that keeps mountpoint(1).
rc=$(run_wrap_c1 "$root" "git-upload-pack '${root}/ws-c1.git'" "/dev/mapper/git-data" "$SEAMS/marker")
c1_refused "C1b device mismatch" "$rc" "is not served by /dev/mapper/git-data"
for look in "${STORE_SRC%?}" "${STORE_SRC}-old"; do
  rc=$(run_wrap_c1 "$root" "git-upload-pack '${root}/ws-c1.git'" "$look" "$SEAMS/marker")
  c1_refused "C1c look-alike '$look'" "$rc" "is not served by $look"
done
rc=$(run_wrap_c1 "$root" "git-receive-pack '${root}/ws-c1.git'" "$STORE_SRC" "$SEAMS/no-such-marker")
c1_refused "C1d marker absent" "$rc" "store not verified"
printf '%s\n' "ffffffff-8211-4000-8000-00000000dead" > "$SEAMS/marker-other"
rc=$(run_wrap_c1 "$root" "git-receive-pack '${root}/ws-c1.git'" "$STORE_SRC" "$SEAMS/marker-other")
c1_refused "C1e marker UUID mismatch" "$rc" "store not verified"
curated="$(mktemp -d "${TMPDIR}/gdxport-path.XXXXXX")"
for tool in bash readlink dirname stat git head mountpoint; do
  src="$(command -v "$tool")" && ln -s "$src" "${curated}/${tool}"
done
rc=$(run_wrap_c1 "$root" "git-upload-pack '${root}/ws-c1.git'" "$STORE_SRC" "$SEAMS/marker" "$curated")
c1_refused "C1f findmnt absent" "$rc" "findmnt unavailable"
drop_fixture "$root"; drop_fixture "$curated"

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
# 33 -> 53 with the C1 store rows (#8211): C1a 2, C1b 3, C1c 2x3, C1d 3, C1e 3, C1f 3 = 20.
total=$((passes + fails))
if [ "$total" -lt 53 ]; then
  echo "FAIL: ran only ${total} assertions (<53) — suite did not execute fully" >&2
  exit 1
fi

echo "git-data-transport-wrapper: ${passes} passed, ${fails} failed (${total} assertions)"
[ "$fails" -eq 0 ]
