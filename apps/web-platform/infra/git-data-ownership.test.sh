#!/usr/bin/env bash
#
# Guard 3 (#8043 F7/F9): the git account cannot rewrite its own SSH authorization map — by
# editing it OR by replacing the directory holding it — cannot write the hook directory whose
# pre-receive fences its pushes, and can still TRAVERSE every one of those paths; the repo
# root stays git-writable; and sshd consults exactly one authorization file.
#
# TWO ARMS. The STATIC arm reads the LAST WRITER of each path — the bootstrap's own
# chown/chmod/install lines, which run in runcmd AFTER write_files and therefore decide the
# real ownership — and evaluates a stated model over the literals: the `git` principal is in
# group `git` and no other; a path is TRAVERSABLE by git iff (owner=git ∧ u+x) ∨ (group=git ∧
# g+x) ∨ o+x, WRITABLE by git iff the same with w, READABLE with r. `root:root 0750` and
# `root:git 0750` differ only in group, so a bare grep cannot rate them; the model can. The
# RUNTIME arm applies those same literals to a real /home/git in the pinned ubuntu-24.04 image,
# drives a real `git` principal through the denials, and proves sshd ACCEPTS the map at the
# shipped owner/mode — with a negative control (root:root 0600 -> denied, because sshd opens
# authorized_keys under the TARGET USER's uid), so the acceptance row is shown able to fail.
#
# Run: bash apps/web-platform/infra/git-data-ownership.test.sh
# Registered as a step in .github/workflows/infra-validation.yml.

set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="${DIR}/cloud-init-git-data.yml"
BOOTSTRAP="${DIR}/git-data-bootstrap.sh"
# Pinned base image — the same digest git-data-runcmd-rehearsal.test.sh spins (#7544).
UBUNTU_BASE='ubuntu:24.04@sha256:33ceb71981b602c1a7443a53469e4dba065f7503eab3078a2d7a57a2ab987517'

passes=0; fails=0; SKIPPED=0
FAILURES=()
pass() { passes=$((passes + 1)); printf '  ok   %s\n' "$1"; }
fail() { FAILURES+=("$1"); fails=$((fails + 1)); printf '  FAIL %s\n       %s\n' "$1" "${2:-}"; }

# Comment-stripped corpus: whole-line `#` comments become empty lines so a prose line quoting
# a construct cannot satisfy an anchor (cq-assert-anchor-not-bare-token).
_code() { sed 's/^[[:space:]]*#.*$//' "$1"; }
BOOT_CODE="$(_code "$BOOTSTRAP")"

printf '\n=== git-data-ownership (Guard 3) ===\n\n'

# ── STATIC ARM ─────────────────────────────────────────────────────────────────────

# S1 — the authorized_keys write_files entry: root-owned and 0644. Same awk the birth gate
# uses, so the two readers cannot disagree about which lines are "the entry's".
_ak_meta="$(awk '
  $0 ~ /^[[:space:]]*-[[:space:]]*path:[[:space:]]*\/home\/git\/\.ssh\/authorized_keys[[:space:]]*$/ { want=1; next }
  want && $0 ~ /^[[:space:]]*(owner|permissions):/ { print; n++ }
  want && n >= 2 { exit }
' "$TEMPLATE")"
if grep -qE "^[[:space:]]*owner:[[:space:]]*root:root[[:space:]]*$" <<< "$_ak_meta"; then
  pass "S1a: authorized_keys is declared owner: root:root (git cannot rewrite it in place)"
else fail "S1a: authorized_keys owner is not root:root" "$_ak_meta"; fi
# 0644, NOT 0600. sshd opens the file under the target user's uid (measured in the pinned
# image: root:root 0600 -> "Permission denied", every push refused). Readable is required.
if grep -qE "^[[:space:]]*permissions:[[:space:]]*'0644'[[:space:]]*$" <<< "$_ak_meta"; then
  pass "S1b: authorized_keys is 0644 — root-owned AND readable by the git uid sshd reads it as"
else fail "S1b: authorized_keys permissions are not '0644' (0600 under root:root bricks every push)" "$_ak_meta"; fi

# S2 — sshd consults exactly ONE authorization file. The stock 24.04 default is
# `.ssh/authorized_keys .ssh/authorized_keys2`; with .ssh root-owned nothing can create the
# second, so this pin is defence in depth against an ownership regression — but it must exist.
_hard="$(awk '
  $0 ~ /^[[:space:]]*-[[:space:]]*path:[[:space:]]*\/etc\/ssh\/sshd_config\.d\/01-hardening\.conf[[:space:]]*$/ { want=1; next }
  want && $0 ~ /^[[:space:]]*(owner|permissions):/ { exit }
  want { print }
' "$TEMPLATE")"
_n_akf="$(grep -cE '^[[:space:]]*AuthorizedKeysFile[[:space:]]+\.ssh/authorized_keys[[:space:]]*$' <<< "$_hard" || true)"
if [ "$_n_akf" = "1" ]; then pass "S2: 01-hardening.conf pins AuthorizedKeysFile .ssh/authorized_keys exactly once"
else fail "S2: AuthorizedKeysFile .ssh/authorized_keys appears ${_n_akf} time(s) in 01-hardening.conf, expected 1" "$_hard"; fi

# S3 — no RECURSIVE chown over .ssh in the bootstrap. It ran in runcmd, i.e. after
# write_files, so it was the LAST WRITER and reverted whatever owner: the template declared
# (learning 2026-03-20: a recursive chown placed after a targeted one silently reverts it).
if grep -qE '^[[:space:]]*chown[[:space:]]+-R[[:space:]].*\.ssh' <<< "$BOOT_CODE"; then
  fail "S3: the bootstrap still has a recursive chown over .ssh — it runs after write_files and reverts the root ownership" "$(grep -nE '^[[:space:]]*chown[[:space:]]+-R' <<< "$BOOT_CODE")"
else pass "S3: no recursive chown over .ssh survives in the bootstrap (the last writer no longer reverts the map)"; fi

# S4 — the last-writer model over the literals. For each path, the LAST `chown O:G <path>`
# and the LAST `chmod MODE <path>` in the comment-stripped bootstrap; `install -o O -g G -m
# MODE … <path>` counts as both. A path with no writer is a FAIL, not a pass: silence about
# ownership is the accident F8 records, not an assertion.
_last_owner() { # $1 = path literal as written in the bootstrap
  local p="$1" o
  o="$(grep -E "^[[:space:]]*chown[[:space:]]+[A-Za-z0-9_\$\"{}:.-]+[[:space:]]+.*\"?${p//\$/\\$}\"?([[:space:]]|$)" <<< "$BOOT_CODE" | grep -vE '^[[:space:]]*chown[[:space:]]+-' | tail -1 | sed -E 's/^[[:space:]]*chown[[:space:]]+//; s/[[:space:]].*$//')"
  [ -n "$o" ] || o="$(grep -E "^[[:space:]]*install[[:space:]]+.*\"?${p//\$/\\$}\"?[[:space:]]*$" <<< "$BOOT_CODE" | tail -1 | sed -E 's/.*-o[[:space:]]+([^[:space:]]+).*-g[[:space:]]+([^[:space:]]+).*/\1:\2/')"
  printf '%s' "$o"
}
_last_mode() {
  local p="$1" m
  m="$(grep -E "^[[:space:]]*chmod[[:space:]]+[0-7]{3,4}[[:space:]]+.*\"?${p//\$/\\$}\"?([[:space:]]|$)" <<< "$BOOT_CODE" | tail -1 | sed -E 's/^[[:space:]]*chmod[[:space:]]+//; s/[[:space:]].*$//')"
  [ -n "$m" ] || m="$(grep -E "^[[:space:]]*install[[:space:]]+.*\"?${p//\$/\\$}\"?[[:space:]]*$" <<< "$BOOT_CODE" | tail -1 | sed -E 's/.*-m[[:space:]]+([0-7]{3,4}).*/\1/')"
  printf '%s' "$m"
}
# Resolve the bootstrap's variable spellings to the principal names the model reasons about.
_norm() { sed -e 's/"//g' -e 's/\$GIT_USER/git/g' -e 's/\${GIT_USER}/git/g' <<< "$1"; }
# git_can <r|w|x> <owner:group> <mode(3-4 octal digits)> — the model, as stated in the header.
git_can() {
  local want="$1" og="$2" mode="$3" o g u gr ot bit
  o="${og%%:*}"; g="${og##*:}"; mode="${mode: -3}"
  u=${mode:0:1}; gr=${mode:1:1}; ot=${mode:2:1}
  case "$want" in r) bit=4 ;; w) bit=2 ;; x) bit=1 ;; esac
  { [ "$o" = git ] && (( (u & bit) != 0 )); } && return 0
  { [ "$g" = git ] && (( (gr & bit) != 0 )); } && return 0
  (( (ot & bit) != 0 )) && return 0
  return 1
}
_row() { # $1 label, $2 path literal, $3 expected: "trav,nowrite" | "write" | "nowrite,read" | "nowrite,exec"
  local label="$1" p="$2" want="$3" og m
  og="$(_norm "$(_last_owner "$p")")"; m="$(_last_mode "$p")"
  if [ -z "$og" ] || [ -z "$m" ]; then fail "$label: no last-writer chown/chmod found for $p in the bootstrap (owner='${og}' mode='${m}')"; return; fi
  local ok=1 why=""
  case ",$want," in
    *,trav,*)    git_can x "$og" "$m" || { ok=0; why+="not traversable by git; "; } ;;
  esac
  case ",$want," in
    *,nowrite,*) git_can w "$og" "$m" && { ok=0; why+="WRITABLE by git; "; } ;;
  esac
  case ",$want," in
    *,write,*)   git_can w "$og" "$m" || { ok=0; why+="not writable by git; "; } ;;
  esac
  case ",$want," in
    *,read,*)    git_can r "$og" "$m" || { ok=0; why+="not readable by git; "; } ;;
  esac
  case ",$want," in
    *,exec,*)    git_can x "$og" "$m" || { ok=0; why+="not executable by git; "; } ;;
  esac
  if [ "$ok" = 1 ]; then pass "$label ($og $m)"; else fail "$label — last writer sets $og $m: ${why}"; fi
}
_row "S4a: /home/git is traversable by git and not writable by it"           '$GIT_HOME'                       "trav,nowrite"
_row "S4b: /home/git/.ssh is traversable by git and not writable (no authorized_keys2 can be created)" '$GIT_HOME/.ssh' "trav,nowrite"
_row "S4c: authorized_keys is not writable by git and IS readable by it"     '$GIT_HOME/.ssh/authorized_keys'  "nowrite,read"
_row "S4d: \$HOOKS_DIR is traversable by git and not writable by it"          '$HOOKS_DIR'                      "trav,nowrite"
_row "S4e: the pre-receive fence is executable by git and not writable by it" '$PRE_RECEIVE'                    "nowrite,exec"
_row "S4f: \$REPO_ROOT stays git-writable (provisioning still works)"         '$REPO_ROOT'                      "write"

# S5 — the REPO_ROOT/HOOKS_DIR pair is no longer chowned/chmodded as ONE triple. The old
# `chown "$GIT_USER:$GIT_USER" "$REPO_ROOT" "$HOOKS_DIR"` applied one owner to both.
if grep -qE '^[[:space:]]*(chown|chmod)[[:space:]]+[^[:space:]]+[[:space:]]+"\$REPO_ROOT"[[:space:]]+"\$HOOKS_DIR"' <<< "$BOOT_CODE"; then
  fail "S5: REPO_ROOT and HOOKS_DIR are still set by one chown/chmod line — they need different owners" "$(grep -nE '"\$REPO_ROOT"[[:space:]]+"\$HOOKS_DIR"' <<< "$BOOT_CODE")"
else pass "S5: REPO_ROOT and HOOKS_DIR are owned separately (the triple is split)"; fi

# S6 — the post-condition READS BACK ownership with stat and compares LITERALS, so the boot
# proves the ABSENCE of the reverted state rather than the presence of a chown line. Anchored
# on the comparison construct (`<path>")" == "<user>:<group> <mode>"`), not on a helper name,
# so an inline `stat` and a wrapper function are both accepted; the `stat -c '%U:%G %a'`
# instrument must exist somewhere in the code.
if grep -qF "stat -c '%U:%G %a'" <<< "$BOOT_CODE"; then pass "S6: the bootstrap reads ownership back with stat -c '%U:%G %a'"
else fail "S6: no stat -c '%U:%G %a' readback in the bootstrap"; fi
for p in '$GIT_HOME' '$GIT_HOME/.ssh' '$GIT_HOME/.ssh/authorized_keys' '$HOOKS_DIR' '$PRE_RECEIVE'; do
  if grep -qE "\"${p//\$/\\$}\"\)\" == \"[a-z]+:[A-Za-z0-9_\$]+ [0-7]{3}\"" <<< "$BOOT_CODE"; then pass "S6: post-condition compares $p against a literal user:group mode"
  else fail "S6: no literal user:group mode comparison for $p in the bootstrap post-conditions"; fi
done

# ── RUNTIME ARM (pinned image) ──────────────────────────────────────────────────────
#
# Applies the literals the static arm extracted to a REAL /home/git and drives a real `git`
# principal. Ten rows; when docker is unavailable they are DECLARED skipped (counted in the
# floor, reported as such) — and under CI=true that is a failure, because the runner must
# provide the dependency (the rehearsal suite's _skip has the same contract).
RUNTIME_ROWS=10
_runtime_skip() {
  if [ "${CI:-}" = "true" ]; then
    fail "runtime arm: $1 — and CI=true, so this is a FAILURE: the runner must provide docker"
    exit 1
  fi
  SKIPPED=$((SKIPPED + RUNTIME_ROWS))
  printf '  SKIP runtime arm (%s rows): %s\n' "$RUNTIME_ROWS" "$1"
}
_og_home="$(_norm "$(_last_owner '$GIT_HOME')")";  _m_home="$(_last_mode '$GIT_HOME')"
_og_ssh="$(_norm "$(_last_owner '$GIT_HOME/.ssh')")"; _m_ssh="$(_last_mode '$GIT_HOME/.ssh')"
_og_ak="$(_norm "$(_last_owner '$GIT_HOME/.ssh/authorized_keys')")"; _m_ak="$(_last_mode '$GIT_HOME/.ssh/authorized_keys')"
_og_hooks="$(_norm "$(_last_owner '$HOOKS_DIR')")"; _m_hooks="$(_last_mode '$HOOKS_DIR')"
_og_pr="$(_norm "$(_last_owner '$PRE_RECEIVE')")"; _m_pr="$(_last_mode '$PRE_RECEIVE')"
_og_repo="$(_norm "$(_last_owner '$REPO_ROOT')")"; _m_repo="$(_last_mode '$REPO_ROOT')"

if ! command -v docker >/dev/null 2>&1; then _runtime_skip "docker absent"
elif ! docker info >/dev/null 2>&1; then _runtime_skip "docker daemon unreachable"
elif [ -z "$_og_home$_m_home$_og_ssh$_m_ssh$_og_ak$_m_ak$_og_hooks$_m_hooks$_og_pr$_m_pr$_og_repo$_m_repo" ]; then
  fail "runtime arm: no literals extracted from the bootstrap, nothing to apply"
  SKIPPED=$((SKIPPED + RUNTIME_ROWS - 1))
else
  TMP="$(mktemp -d "${TMPDIR}/gdown.XXXXXX")"
  trap 'rm -rf "$TMP"' EXIT
  mkdir -p "$TMP/out"
  cat > "$TMP/drive.sh" <<'DRV'
set -u
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq >/dev/null 2>&1 && apt-get install -y -qq openssh-server openssh-client git >/dev/null 2>&1 || { echo "FIXTURE_APT_FAILED"; exit 100; }
useradd -m -s /bin/sh git || exit 2
mkdir -p /run/sshd /mnt/git-data/repositories /mnt/git-data/hooks
ssh-keygen -q -t ed25519 -N '' -f /tmp/k
mkdir -p /home/git/.ssh
printf 'command="/bin/true",no-pty %s\n' "$(cat /tmp/k.pub)" > /home/git/.ssh/authorized_keys
printf '#!/bin/sh\nexit 0\n' > /tmp/pre-receive
apply() { chown "$1" "$3"; chmod "$2" "$3"; }
apply "$OG_HOME"  "$M_HOME"  /home/git
apply "$OG_SSH"   "$M_SSH"   /home/git/.ssh
apply "$OG_AK"    "$M_AK"    /home/git/.ssh/authorized_keys
apply "$OG_HOOKS" "$M_HOOKS" /mnt/git-data/hooks
apply "$OG_REPO"  "$M_REPO"  /mnt/git-data/repositories
install -o "${OG_PR%%:*}" -g "${OG_PR##*:}" -m "$M_PR" /tmp/pre-receive /mnt/git-data/hooks/pre-receive
echo "FIXTURE_OK"
r() { printf '%s=%s\n' "$1" "$2" >> /out/rows; }
su git -s /bin/sh -c 'echo x >> /home/git/.ssh/authorized_keys' 2>/dev/null; r append_ak $?
su git -s /bin/sh -c 'mv /home/git/.ssh /home/git/.ssh.old' 2>/dev/null; r mv_ssh $?
su git -s /bin/sh -c 'touch /home/git/authorized_keys2 2>/dev/null || touch /home/git/.ssh/authorized_keys2' 2>/dev/null; r create_ak2 $?
su git -s /bin/sh -c 'cat /home/git/.ssh/authorized_keys >/dev/null' 2>/dev/null; r read_ak $?
su git -s /bin/sh -c 'touch /mnt/git-data/hooks/x' 2>/dev/null; r write_hooks $?
su git -s /bin/sh -c 'echo x >> /mnt/git-data/hooks/pre-receive' 2>/dev/null; r write_pre_receive $?
su git -s /bin/sh -c '/mnt/git-data/hooks/pre-receive' 2>/dev/null; r exec_pre_receive $?
su git -s /bin/sh -c 'mkdir /mnt/git-data/repositories/ws.git' 2>/dev/null; r write_repo_root $?
sshd_auth() { # $1 label — start sshd, try publickey auth as git, record the outcome
  /usr/sbin/sshd -D -p 2222 -o StrictModes=yes -o PasswordAuthentication=no -o 'AuthorizedKeysFile .ssh/authorized_keys' -E /tmp/sshd.log & pid=$!; sleep 1
  ssh -q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes -i /tmp/k -p 2222 git@127.0.0.1 true 2>/dev/null; rc=$?
  kill $pid 2>/dev/null; wait $pid 2>/dev/null; r "$1" $rc
}
sshd_auth ssh_auth_shipped
# NEGATIVE CONTROL: root:root 0600 — sshd opens the map as the target user, so this must be
# refused. If it is accepted, the acceptance row above proves nothing.
chmod 0600 /home/git/.ssh/authorized_keys; chown root:root /home/git/.ssh/authorized_keys
sshd_auth ssh_auth_control_0600
echo "DRIVER_DONE"
DRV
  : > "$TMP/out/rows"
  docker run --rm \
    -e OG_HOME="$_og_home" -e M_HOME="$_m_home" -e OG_SSH="$_og_ssh" -e M_SSH="$_m_ssh" \
    -e OG_AK="$_og_ak" -e M_AK="$_m_ak" -e OG_HOOKS="$_og_hooks" -e M_HOOKS="$_m_hooks" \
    -e OG_PR="$_og_pr" -e M_PR="$_m_pr" -e OG_REPO="$_og_repo" -e M_REPO="$_m_repo" \
    -v "$TMP/drive.sh:/work/drive.sh:ro" -v "$TMP/out:/out" \
    "$UBUNTU_BASE" bash /work/drive.sh > "$TMP/out/stdout" 2>&1
  DRC=$?
  if grep -qx DRIVER_DONE "$TMP/out/stdout"; then
    _rv() { sed -n "s/^$1=//p" "$TMP/out/rows" | tail -1; }
    _deny() { [ -n "$(_rv "$1")" ] && [ "$(_rv "$1")" != "0" ]; }
    _allow() { [ "$(_rv "$1")" = "0" ]; }
    _deny append_ak        && pass "R1: git appending to ~/.ssh/authorized_keys is DENIED (rc=$(_rv append_ak))"        || fail "R1: git could append to its own authorization map" "rc=$(_rv append_ak)"
    _deny mv_ssh           && pass "R2: git replacing ~/.ssh is DENIED (rc=$(_rv mv_ssh))"                             || fail "R2: git could replace ~/.ssh" "rc=$(_rv mv_ssh)"
    _deny create_ak2       && pass "R3: git cannot create authorized_keys2 (rc=$(_rv create_ak2))"                     || fail "R3: git could create an authorized_keys2" "rc=$(_rv create_ak2)"
    _allow read_ak         && pass "R4: git can READ the map (sshd reads it as the git uid)"                           || fail "R4: git cannot read authorized_keys — sshd would refuse every key" "rc=$(_rv read_ak)"
    _deny write_hooks      && pass "R5: git writing into \$HOOKS_DIR is DENIED (rc=$(_rv write_hooks))"                 || fail "R5: git could write into the hooks directory" "rc=$(_rv write_hooks)"
    _deny write_pre_receive && pass "R6: git overwriting pre-receive is DENIED (rc=$(_rv write_pre_receive))"          || fail "R6: git could overwrite the fence it is fenced by" "rc=$(_rv write_pre_receive)"
    _allow exec_pre_receive && pass "R7: git can still EXECUTE pre-receive (receive-pack execs the hook)"              || fail "R7: git cannot execute the hook — every push would be rejected" "rc=$(_rv exec_pre_receive)"
    _allow write_repo_root && pass "R8: git can write \$REPO_ROOT (provisioning works)"                                  || fail "R8: git cannot write the repo root" "rc=$(_rv write_repo_root)"
    _allow ssh_auth_shipped && pass "R9: sshd ACCEPTS publickey auth for git with the shipped owner/mode literals"     || fail "R9: sshd refused the key at the shipped literals — the map is unreadable or StrictModes rejects it" "rc=$(_rv ssh_auth_shipped) $(grep -oE 'Authentication refused[^,]*|Permission denied' "$TMP/out/stdout" | head -1)"
    _deny ssh_auth_control_0600 && pass "R10: NEGATIVE CONTROL — root:root 0600 is refused by sshd (R9 can fail)"     || fail "R10: the negative control was ACCEPTED — R9 proves nothing" "rc=$(_rv ssh_auth_control_0600)"
  elif grep -qx FIXTURE_APT_FAILED "$TMP/out/stdout" || [ "$DRC" = 125 ]; then
    _runtime_skip "container did not reach the fixture (docker rc=$DRC): $(tail -2 "$TMP/out/stdout" | tr '\n' ' ')"
  else
    fail "runtime arm: the driver did not complete (docker rc=$DRC)" "$(tail -5 "$TMP/out/stdout" | tr '\n' ' ')"
    SKIPPED=$((SKIPPED + RUNTIME_ROWS - 1))
  fi
fi

# ── FLOOR + LEDGER ─────────────────────────────────────────────────────────────────
# 2 (S1) + 1 (S2) + 1 (S3) + 6 (S4) + 1 (S5) + 6 (S6) + 10 runtime = 27. Skipped runtime rows
# count toward the floor (they were DECLARED), never toward passes.
# ADR-193 shape: the floor reports with `printf >&2` + `exit 1` INSIDE its own block, never
# through the pass()/fail() helpers it backstops — a neutered helper cannot disarm it, and the
# vacuity guard's mutant (the block alone, counters zeroed) must exit non-zero by itself.
_declared=${SKIPPED:-0}
_ran=$((passes + fails + _declared))
if [ "$_ran" -lt 27 ]; then
  printf 'FAIL ANTI-VACUITY: only %s assertions ran/declared, floor is 27 — arms were deleted, skipped, or the suite exited early.\n' "$_ran" >&2
  exit 1
fi
if [ "${#FAILURES[@]}" -ne "$fails" ]; then
  printf '  FAIL LEDGER: %s failures counted but %s recorded\n' "$fails" "${#FAILURES[@]}"; exit 1
fi
printf '\n=== git-data-ownership: %d passed, %d failed, %d skipped ===\n\n' "$passes" "$fails" "$SKIPPED"
exit $(( ${#FAILURES[@]} > 0 ))
