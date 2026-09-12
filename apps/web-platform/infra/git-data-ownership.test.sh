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

# S3b — WRITER CENSUS, fail-closed (#8052 review: seven mutants on one axis). The last-writer
# model below parses exactly three writer forms: `chown O:G <path>`, `chmod NNNN <path>` and
# `install -o O -g G -m NNNN … <path>`. Any OTHER writer that names a guarded path — `chown -R`,
# `--recursive`, a symbolic `chmod g+w`, a `${VAR}` or absolute spelling, a chown over the parent
# `$GIT_DATA_ROOT` — would run after write_files, decide the real ownership, and be INVISIBLE to
# S4. So every chown/chmod/install line that mentions any spelling of a guarded path must be
# one the model parses, or the suite fails naming the line. The one legitimate exception is the
# `chown -h` of the $GIT_HOME/repositories symlink (it sets the LINK, not a guarded path).
_guard_re='(\$\{?GIT_HOME\}?|/home/git|\$\{?HOOKS_DIR\}?|\$\{?PRE_RECEIVE\}?|\$\{?REPO_ROOT\}?|\$\{?GIT_DATA_ROOT\}?|/mnt/git-data)'
_writers="$(grep -nE "^[[:space:]]*(chown|chmod|install)[[:space:]]" <<< "$BOOT_CODE" | grep -E "$_guard_re" || true)"
_unmodelled=""
while IFS= read -r _wl; do
  [ -n "$_wl" ] || continue
  _body="${_wl#*:}"
  if grep -qE '^[[:space:]]*chown[[:space:]]+-h[[:space:]]+"\$GIT_USER:\$GIT_USER"[[:space:]]+"\$GIT_HOME/repositories"[[:space:]]*$' <<< "$_body"; then continue; fi
  if grep -qE '^[[:space:]]*chown[[:space:]]+"?[A-Za-z0-9_$]+:[A-Za-z0-9_$]+"?[[:space:]]+"\$(GIT_HOME|GIT_HOME/\.ssh|GIT_HOME/\.ssh/authorized_keys|HOOKS_DIR|REPO_ROOT|PRE_RECEIVE)"[[:space:]]*$' <<< "$_body"; then continue; fi
  if grep -qE '^[[:space:]]*chmod[[:space:]]+[0-7]{4}[[:space:]]+"\$(GIT_HOME|GIT_HOME/\.ssh|GIT_HOME/\.ssh/authorized_keys|HOOKS_DIR|REPO_ROOT|PRE_RECEIVE)"[[:space:]]*$' <<< "$_body"; then continue; fi
  if grep -qE '^[[:space:]]*install[[:space:]]+-o[[:space:]]+[a-z]+[[:space:]]+-g[[:space:]]+[a-z]+[[:space:]]+-m[[:space:]]+[0-7]{4}[[:space:]]+"[^"]+"[[:space:]]+"\$PRE_RECEIVE"[[:space:]]*$' <<< "$_body"; then continue; fi
  _unmodelled+="${_wl}"$'\n'
done <<< "$_writers"
_n_writers="$(grep -c . <<< "$_writers" || true)"
if [ "$_n_writers" -lt 10 ]; then fail "S3b: writer census found only ${_n_writers} chown/chmod/install lines naming a guarded path — the census regex or the bootstrap changed shape" "$_writers"
elif [ -z "$_unmodelled" ]; then pass "S3b: every one of the ${_n_writers} ownership writers naming a guarded path is a form the last-writer model parses"
else fail "S3b: UNMODELLED ownership writer(s) — they run after write_files and S4 cannot see them" "$_unmodelled"; fi

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
# proves the ABSENCE of the reverted state rather than the presence of a chown line. The
# bootstrap's readback is a TABLE (`<path> <owner:group> <mode> <why>` rows fed to one loop),
# so each row is anchored as a whole-line table entry with a literal owner and mode; the
# `stat -c '%U:%G %a'` instrument must exist in the code that reads the table.
if grep -qF "stat -c '%U:%G %a'" <<< "$BOOT_CODE"; then pass "S6: the bootstrap reads ownership back with stat -c '%U:%G %a'"
else fail "S6: no stat -c '%U:%G %a' readback in the bootstrap"; fi
# Each row's `owner mode` must EQUAL what the last writer set (#8052 review: a table that
# disagrees with the chown lines FATALs every birth — a fail-closed outage no static row saw).
for p in '$GIT_HOME' '$GIT_HOME/.ssh' '$GIT_HOME/.ssh/authorized_keys' '$HOOKS_DIR' '$PRE_RECEIVE'; do
  _rowv="$(grep -E "^${p//\$/\\$} [a-z]+:[A-Za-z0-9_\$]+ [0-7]{3} " "$BOOTSTRAP" | head -1 | awk '{print $2, $3}')"
  _lm="$(_last_mode "$p")"
  _want="$(_norm "$(_last_owner "$p")") ${_lm: -3}"   # stat %a prints 3 digits; the chmod literal is 4
  if [ -z "$_rowv" ]; then fail "S6: no readback table row for $p in the bootstrap post-conditions"
  elif [ "$(_norm "$_rowv")" = "$_want" ]; then pass "S6: readback table row for $p equals its last writer ($_want)"
  else fail "S6: readback table row for $p says '$_rowv' but the last writer sets '$_want' — the boot would FATAL on a healthy host"; fi
done
# S6b — the model's premise ("git is in group git and no other") is asserted at boot, not assumed.
if grep -qE '^[[:space:]]*\[\[ "\$\(id -Gn "\$GIT_USER"\)" == "\$GIT_USER" \]\] \|\| ' <<< "$BOOT_CODE"; then pass "S6b: the bootstrap asserts the git account's group membership (the model's premise)"
else fail "S6b: nothing asserts id -Gn git == git at boot; a supplementary group makes the root:git 0750 model wrong"; fi

# S7 — the login shell is a REAL shell. sshd runs a forced `command=` as `<login shell> -c
# "<command>"`; git-shell refuses anything but its four built-ins (measured in the pinned
# image: rc=128 "fatal: unrecognized command"), so a git-shell login kills transport,
# provision and the Art. 17 erasure alike. The runtime arm creates its user with THIS shell,
# so R9 (a real forced command through sshd) is what proves it, and this row is what names it.
GIT_SHELL="$(awk '$0 ~ /^  - name: git[[:space:]]*$/ { want=1; next } want && $0 ~ /^    shell:/ { sub(/^    shell:[[:space:]]*/, ""); print; exit }' "$TEMPLATE")"
case "$GIT_SHELL" in
  /bin/sh|/bin/bash|/usr/bin/sh|/usr/bin/bash) pass "S7: the git user's login shell is a real shell ($GIT_SHELL) — forced commands can execute" ;;
  *) fail "S7: the git user's login shell is '${GIT_SHELL:-<unset>}' — a restricted or missing shell kills every forced command at '<shell> -c'" ;;
esac

# S7b — the shell readback runs AFTER the account-existence guard: under `set -eo pipefail` a
# `getent` on an absent account exits the bootstrap silently at the wrong line (#8052 review).
_ln_id="$(grep -nE '^id "\$GIT_USER" >/dev/null 2>&1 \|\| \{' <<< "$BOOT_CODE" | head -1 | cut -d: -f1)"
_ln_sh="$(grep -nE '^_git_shell="\$\(getent passwd "\$GIT_USER" \| cut -d: -f7\)"' <<< "$BOOT_CODE" | head -1 | cut -d: -f1)"
if [ -n "$_ln_id" ] && [ -n "$_ln_sh" ] && [ "$_ln_id" -lt "$_ln_sh" ]; then pass "S7b: the login-shell readback (line $_ln_sh) follows the 'user absent' FATAL guard (line $_ln_id)"
else fail "S7b: the shell readback is not downstream of the id guard (id=$_ln_id shell=$_ln_sh) — an absent account dies silently under pipefail"; fi
# S7c — the placeholder fence is installed only from a ROOT-owned staged file (/tmp is sticky
# and world-writable; a git-uid file there would become the root:root 0755 fence on a re-run).
if grep -qE '^[[:space:]]*\[\[ "\$\(stat -c %U "\$PLACEHOLDER_STAGED"\)" == root \]\] \|\| \{' <<< "$BOOT_CODE"; then pass "S7c: the staged placeholder must be root-owned before it is installed as the fence"
else fail "S7c: nothing asserts the staged placeholder in /tmp is root-owned before install"; fi

# S8 — the four defaults of the store's mount root and hook directory AGREE across the writer
# of record (the bootstrap) and the three forced-command wrappers (#8052 review: every wrapper
# row overrides the seam, so a typo in a production default would fail-close every push,
# provision and erasure with nothing red before birth).
_bs_root="$(sed -nE 's/^GIT_DATA_ROOT="([^"]+)".*$/\1/p' "$BOOTSTRAP" | head -1)"
_tpl_root="$(grep -oE 'mount[[:space:]]+[^[:space:]]+[[:space:]]+/mnt/git-data([[:space:]]|$)' "$TEMPLATE" | head -1 | awk '{print $3}')"
for w in git-data-provision.sh git-data-remove.sh git-data-transport-wrapper.sh; do
  _w_mnt="$(sed -nE 's/^MOUNT_ROOT="\$\{GIT_DATA_MOUNT_ROOT:-([^}]+)\}".*$/\1/p' "${DIR}/${w}" | head -1)"
  _w_repo="$(sed -nE 's/^REPO_ROOT="\$\{GIT_DATA_REPO_ROOT:-([^}]+)\}".*$/\1/p' "${DIR}/${w}" | head -1)"
  if [ -n "$_bs_root" ] && [ "$_w_mnt" = "$_bs_root" ] && [ "$_w_repo" = "${_bs_root}/repositories" ] && [ "$_tpl_root" = "$_bs_root" ]; then
    pass "S8: $w defaults (mount $_w_mnt, root $_w_repo) equal the bootstrap's GIT_DATA_ROOT and the template's mount target"
  else fail "S8: $w defaults disagree with the writer of record" "wrapper mount='$_w_mnt' root='$_w_repo' bootstrap='$_bs_root' template mount='$_tpl_root'"; fi
done
_w_hooks="$(sed -nE 's/^HOOKS_DIR="\$\{GIT_DATA_HOOKS_DIR:-([^}]+)\}".*$/\1/p' "${DIR}/git-data-transport-wrapper.sh" | head -1)"
if [ -n "$_bs_root" ] && [ "$_w_hooks" = "${_bs_root}/hooks" ]; then pass "S8: the transport wrapper's core.hooksPath pin ($_w_hooks) is the bootstrap's HOOKS_DIR"
else fail "S8: the transport wrapper pins core.hooksPath=$_w_hooks but the bootstrap's hooks dir is ${_bs_root}/hooks"; fi

# S9 — what ROOT trusts from git-owned bytes, pinned on the maintenance path (#8052 structural
# seat, measured in the pinned image): (a) root's gc names each repo on the command line
# (`-c safe.directory="$repo"`), because the system-wide `$REPO_ROOT/*` form needs git >= 2.46
# and 24.04 ships 2.43.0 — without it every weekly run fails every repo and reports success;
# (b) the gc lock is NOT under world-writable /var/lock, where a git-uid pre-created file makes
# root's open fail under fs.protected_regular; (c) the unit grants that path, not /var/lock.
_gc_code="$(_code "${DIR}/git-data-gc.sh")"
if grep -qE '^[[:space:]]*timeout -k 30 "\$REPO_TIMEOUT" git -c safe\.directory="\$repo" -C "\$repo" ' <<< "$_gc_code"; then pass "S9a: root's gc passes -c safe.directory=<repo> per command (effective on git 2.43)"
else fail "S9a: git-data-gc.sh runs git against git-owned repos without -c safe.directory=<repo> — on git 2.43 the system /* form matches nothing and every repo fails"; fi
if grep -qE '^LOCK="\$\{GIT_DATA_GC_LOCK:-/run/git-data-gc/lock\}"' <<< "$_gc_code" && ! grep -qE '/var/lock' <<< "$_gc_code"; then pass "S9b: the gc lock lives under the unit's RuntimeDirectory, not /var/lock"
else fail "S9b: git-data-gc.sh keeps its lock under a git-writable directory (/var/lock) or moved it somewhere unpinned"; fi
if grep -qxE 'RuntimeDirectory=git-data-gc' "${DIR}/git-data-gc.service" && ! grep -qE '^ReadWritePaths=.*(^|[[:space:]])/var/lock([[:space:]]|$)' "${DIR}/git-data-gc.service"; then pass "S9c: git-data-gc.service declares RuntimeDirectory=git-data-gc and no longer grants /var/lock"
else fail "S9c: git-data-gc.service does not declare RuntimeDirectory=git-data-gc, or still grants /var/lock"; fi

# ── RUNTIME ARM (pinned image) ──────────────────────────────────────────────────────
#
# Applies the literals the static arm extracted to a REAL /home/git and drives a real `git`
# principal. Ten rows; when docker is unavailable they are DECLARED skipped (counted in the
# floor, reported as such) — and under CI=true that is a failure, because the runner must
# provide the dependency (the rehearsal suite's _skip has the same contract).
RUNTIME_ROWS=10   # R1..R10; R9 runs a REAL forced command through sshd under the template's login shell
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
elif _missing="$(for v in _og_home _m_home _og_ssh _m_ssh _og_ak _m_ak _og_hooks _m_hooks _og_pr _m_pr _og_repo _m_repo; do [ -n "${!v}" ] || printf '%s ' "$v"; done)" && [ -n "$_missing" ]; then
  # Per-literal, not all-or-nothing: ONE empty literal would reach `chown "" path` in the
  # container and turn every R-row into a misleading rc (S4 already reds on it; this keeps the
  # runtime arm from reporting on a fixture it never built).
  fail "runtime arm: literal(s) not extracted from the bootstrap, nothing to apply: ${_missing}"
  SKIPPED=$((SKIPPED + RUNTIME_ROWS - 1))
else
  TMP="$(mktemp -d "${TMPDIR}/gdown.XXXXXX")"
  trap 'rm -rf "$TMP"' EXIT
  mkdir -p "$TMP/out"
  cat > "$TMP/drive.sh" <<'DRV'
set -u
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq >/dev/null 2>&1 && apt-get install -y -qq openssh-server openssh-client git >/dev/null 2>&1 || { echo "FIXTURE_APT_FAILED"; exit 100; }
useradd -m -s "${GIT_SHELL:?}" git || exit 2
mkdir -p /run/sshd /mnt/git-data/repositories /mnt/git-data/hooks
ssh-keygen -q -t ed25519 -N '' -f /tmp/k
mkdir -p /home/git/.ssh
# A REAL forced command, not /bin/true: under git-shell `<shell> -c /usr/local/bin/…` dies
# before any script runs, and only a command that must PRINT can show the difference.
printf '#!/bin/sh\necho "WRAPPER_RAN uid=$(id -u) cmd=[$SSH_ORIGINAL_COMMAND]"\n' > /usr/local/bin/git-data-probe-wrapper.sh; chmod 755 /usr/local/bin/git-data-probe-wrapper.sh
printf 'command="/usr/local/bin/git-data-probe-wrapper.sh",no-port-forwarding,no-X11-forwarding,no-agent-forwarding,no-pty %s\n' "$(cat /tmp/k.pub)" > /home/git/.ssh/authorized_keys
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
sshd_auth() { # $1 label — start sshd, run the forced command as git over publickey, record rc AND whether the wrapper ran
  /usr/sbin/sshd -D -p 2222 -o StrictModes=yes -o PasswordAuthentication=no -o 'AuthorizedKeysFile .ssh/authorized_keys' -E /tmp/sshd.log & pid=$!; sleep 1
  out=$(ssh -q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes -i /tmp/k -p 2222 git@127.0.0.1 ws1 2>&1); rc=$?
  case "$out" in *WRAPPER_RAN*) ran=1 ;; *) ran=0 ;; esac
  kill $pid 2>/dev/null; wait $pid 2>/dev/null; r "$1" "$rc"; r "${1}_ran" "$ran"; printf '%s=%s\n' "${1}_out" "$out" >> /out/rows
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
    -e OG_PR="$_og_pr" -e M_PR="$_m_pr" -e OG_REPO="$_og_repo" -e M_REPO="$_m_repo" -e GIT_SHELL="$GIT_SHELL" \
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
    _allow ssh_auth_shipped && [ "$(_rv ssh_auth_shipped_ran)" = 1 ] && pass "R9: sshd accepts the key at the shipped literals AND the forced command RUNS under the template's login shell ($GIT_SHELL)" || fail "R9: the forced command did not run through sshd (rc=$(_rv ssh_auth_shipped), ran=$(_rv ssh_auth_shipped_ran)) — unreadable map, StrictModes, or a login shell that refuses '<shell> -c'" "$(_rv ssh_auth_shipped_out | head -c 200)"
    _deny ssh_auth_control_0600 && pass "R10: NEGATIVE CONTROL — root:root 0600 is refused by sshd (R9 can fail)"     || fail "R10: the negative control was ACCEPTED — R9 proves nothing" "rc=$(_rv ssh_auth_control_0600)"
  elif grep -qx FIXTURE_APT_FAILED "$TMP/out/stdout" || [ "$DRC" = 125 ]; then
    _runtime_skip "container did not reach the fixture (docker rc=$DRC): $(tail -2 "$TMP/out/stdout" | tr '\n' ' ')"
  else
    fail "runtime arm: the driver did not complete (docker rc=$DRC)" "$(tail -5 "$TMP/out/stdout" | tr '\n' ' ')"
    SKIPPED=$((SKIPPED + RUNTIME_ROWS - 1))
  fi
fi

# ── FLOOR + LEDGER ─────────────────────────────────────────────────────────────────
# 2 (S1) + 1 (S2) + 2 (S3/S3b) + 6 (S4) + 1 (S5) + 7 (S6/S6b) + 3 (S7/S7b/S7c) + 4 (S8) + 3 (S9) + 10 runtime = 39. Skipped runtime rows
# count toward the floor (they were DECLARED), never toward passes.
# ADR-193 shape: the floor reports with `printf >&2` + `exit 1` INSIDE its own block, never
# through the pass()/fail() helpers it backstops — a neutered helper cannot disarm it, and the
# vacuity guard's mutant (the block alone, counters zeroed) must exit non-zero by itself.
_declared=${SKIPPED:-0}
_ran=$((passes + fails + _declared))
if [ "$_ran" -lt 39 ]; then
  printf 'FAIL ANTI-VACUITY: only %s assertions ran/declared, floor is 39 — arms were deleted, skipped, or the suite exited early.\n' "$_ran" >&2
  exit 1
fi
if [ "${#FAILURES[@]}" -ne "$fails" ]; then
  printf '  FAIL LEDGER: %s failures counted but %s recorded\n' "$fails" "${#FAILURES[@]}"; exit 1
fi
printf '\n=== git-data-ownership: %d passed, %d failed, %d skipped ===\n\n' "$passes" "$fails" "$SKIPPED"
exit $(( ${#FAILURES[@]} > 0 ))
