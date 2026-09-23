#!/usr/bin/env bash
#
# Guard 1 (#8211, ADR-239) — ONLY A VERIFIED, MAPPER-SERVED STORE IS ACTED ON.
#
# PROPERTY. No store-acting payload proceeds unless /mnt/git-data is served by
# /dev/mapper/git-data and git-data-bootstrap.sh has written /etc/git-data/store-verified.
# "Mounted" is not "encrypted": the plaintext volume mounted at the same path passes every
# pre-existing guard, and an Art. 17 erasure answered over it reports success having erased
# nothing that the LUKS copy does not still hold.
#
# WHY A CENSUS AND NOT FOUR MORE ROWS IN FOUR SUITES. The script suites prove that the four
# scripts THEY know about refuse. They cannot see a FIFTH payload added to the render later,
# which is the way this class actually regresses. The population is therefore DERIVED from
# the render itself — the `file("${path.module}/../../…")` bindings in
# modules/git-data-userdata/main.tf, the same set the rung-2 birth gate hashes — and the
# derivation is checked against set identity AND a floor, so an extraction that silently
# stops finding payloads reds rather than reporting a clean census over nothing.
#
# WHO IS IN THE POPULATION, and why each exclusion is structural rather than a list:
#   * non-script payloads (`.service`, `.timer`) are units, not store actors — exempt by
#     EXTENSION. Today: git-data-gc.service, git-data-gc-failure.service, git-data-gc.timer,
#     git-data-luks-reopen.service, git-data-luks-reopen-failure.service,
#     git-data-luks-reopen.timer;
#   * git-data-bootstrap.sh is exempt BY NAME (plan): it CREATES the store and writes the
#     marker, so it cannot require its own marker;
#   * git-data-pre-receive-placeholder.sh is exempt BY NAME (plan): it is copied into
#     hooks/ and runs only under the transport wrapper, which asserts first;
#   * a payload that never reads the GIT_DATA_REPO_ROOT seam does not act on the bare-repo
#     store at all. git-data-luks-reopen.sh is that case: it OPENS and MOUNTS the volume, so
#     like the bootstrap it runs before a verified store exists. This is the plan's
#     "store-acting" qualifier made mechanical; the two named exemptions are kept as well,
#     and asserted to be real payloads, so neither reading can go stale unnoticed.
# The expected set is exactly the four wrappers, and a floor pairs with that identity.
#
# THE SECOND CHOKEPOINT is the sshd environment path. GIT_DATA_STORE_DEVICE,
# GIT_DATA_STORE_VERIFIED and GIT_DATA_MOUNT_ROOT are ENVIRONMENT variables, so a client that
# could set one would point the erasure at a store of its choosing. The rendered sshd_config
# must never widen AcceptEnv beyond LANG/LC_*, never set PermitUserEnvironment yes, and no
# authorized_keys line may carry environment=. The gc unit is the same hole from the other
# side — Doppler prd_git_data could inject a seam into git-data-gc.service — so its ExecStart
# must strip the seams with `env -u` AFTER doppler runs.
#
# ARMS.
#   A  population derivation from main.tf (floor + set identity)
#   B  the C1 store assertion in each derived payload, read COMMENT-STRIPPED, including the
#      ORDER (the device check precedes the first destructive op)
#   C  git-data-gc.service strips the four seams
#   D  the sshd environment path is closed
#   E  git-data-bootstrap.sh is the only writer under /etc/git-data, and its erasure-probe
#      seam GIT_DATA_REMOVE_BIN still defaults to /usr/local/bin/git-data-remove.sh
#   F  git-data-gc.sh RUNTIME: gc is the one store-acting script no suite executes, so its C1
#      rows live here (match, mismatch, look-alikes, marker absent, marker UUID mismatch,
#      findmnt absent, exit 1, and the order row: no maintenance ran)
#   G  the Guard 1 mutation matrix, rows 1-9, each against a TEMPORARY COPY, each required RED
#
# Harness conventions (plan › Guard Contract): every mutation row copies, mutates the copy,
# asserts the edit LANDED on the expected diff-line count, and requires the named check RED;
# a pristine copy is required GREEN first, so a harness that reds everything cannot pass;
# floors are reported with printf + exit, never through pass()/fail().
#
# Run: bash apps/web-platform/infra/git-data-store-device-census.test.sh
# Registered as a step in .github/workflows/infra-validation.yml.

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

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAIN_TF="${GDC_MAIN_TF:-$DIR/modules/git-data-userdata/main.tf}"
TEMPLATE="$DIR/cloud-init-git-data.yml"
BOOTSTRAP="$DIR/git-data-bootstrap.sh"
GC_SERVICE="$DIR/git-data-gc.service"
GC="$DIR/git-data-gc.sh"
REMOVE="$DIR/git-data-remove.sh"

passes=0; fails=0; MUTANTS_RUN=0
FAILURES=()
pass() { passes=$((passes + 1)); printf '  ok   %s\n' "$1"; }
fail() { FAILURES+=("$1"); fails=$((fails + 1)); printf '  FAIL %s\n       %s\n' "$1" "${2:-}"; }

# Instrument self-test (ADR-193): drive both helpers once in a subshell and require both
# counters to move, so a neutered helper cannot report a clean run.
_st="$( (pass x >/dev/null; fail y >/dev/null; printf '%s %s %s' "$passes" "$fails" "${#FAILURES[@]}") )"
if [ "$_st" != "1 1 1" ]; then
  printf 'FAIL INSTRUMENT: pass()/fail() self-test read "%s", expected "1 1 1"\n' "$_st" >&2; exit 1
fi

for f in "$MAIN_TF" "$TEMPLATE" "$BOOTSTRAP" "$GC_SERVICE" "$GC" "$REMOVE"; do
  [ -f "$f" ] || { printf 'FAIL SETUP: %s not found\n' "$f" >&2; exit 1; }
done

T="$(mktemp -d "${TMPDIR}/gdcensus.XXXXXX")" || { printf 'FAIL SETUP: mktemp -d failed\n' >&2; exit 1; }
assert_fixture_dir "$T"
trap 'rm -rf "$T"' EXIT

printf '\n=== git-data-store-device census (Guard 1) ===\n\n'

# Comment-stripped corpus: a whole-line `#` comment becomes an empty line, so prose quoting a
# construct cannot satisfy an anchor (matrix row 5).
_code() { sed 's/^[[:space:]]*#.*$//' "$1"; }
# EVERY `grep -q` below reads a HERE-STRING, never the tail of a pipe. `grep -q` exits at the
# first match, so `_code f | grep -q X` kills sed with SIGPIPE and `set -o pipefail` reports
# the pipeline as FAILED — a present check read as absent, intermittently, by file size.
BOOT_CODE="$(_code "$BOOTSTRAP")"

# ── ARM A — the population, DERIVED from the render ────────────────────────────────────────

# Every basename bound by file("${path.module}/../../X") in main.tf. The rung-2 birth gate
# derives its hash-input set the same way, so the census and the evidence hash cannot disagree
# about what the render ships.
derive_payloads() { grep -oE 'file\("\$\{path\.module\}/\.\./\.\./[^"]+"\)' "$1" | sed -E 's|.*/([^/"]+)"\)$|\1|' | sort -u; }

# The store-acting subset: script payloads, minus the two named exemptions, minus any payload
# that does not read the bare-repo root seam.
derive_store_set() { # derive_store_set <main.tf> <payload dir>
  local b
  while read -r b; do
    [ -n "$b" ] || continue
    case "$b" in *.sh) ;; *) continue ;; esac
    case "$b" in git-data-bootstrap.sh|git-data-pre-receive-placeholder.sh) continue ;; esac
    [ -f "${2}/${b}" ] || { printf 'MISSING:%s\n' "$b"; continue; }
    grep -q 'GIT_DATA_REPO_ROOT' <<< "$(_code "${2}/${b}")" || continue
    printf '%s\n' "$b"
  done < <(derive_payloads "$1") | sort -u
}

PAYLOADS="$(derive_payloads "$MAIN_TF")"
_pn=$(printf '%s\n' "$PAYLOADS" | grep -c .)
# Floor of 10 — the same ABORT floor the birth gate applies to this extraction. A regex that
# stops matching reports an empty census, which a set-identity check alone would read as
# "nothing to inspect" only if the expected set were also derived; it is not, but the floor
# makes the failure mode loud rather than arithmetic.
if [ "$_pn" -ge 10 ]; then pass "A1: main.tf binds $_pn file() payloads (floor 10)"
else fail "A1: the file() extraction found only $_pn payloads — the census would inspect almost nothing" "$PAYLOADS"; fi
for b in git-data-bootstrap.sh git-data-pre-receive-placeholder.sh; do
  if grep -qxF "$b" <<< "$PAYLOADS"; then pass "A2: the named exemption $b is a real payload (the exemption is not stale)"
  else fail "A2: $b is exempted by name but is no longer bound by file() in main.tf"; fi
done
_nonscript="$(printf '%s\n' "$PAYLOADS" | grep -v '\.sh$' | tr '\n' ' ')"
if [ -n "$_nonscript" ]; then pass "A3: non-script payloads exempted by extension: ${_nonscript% }"
else fail "A3: no non-script payload was found — the extension exemption is reading nothing"; fi
_nonacting="$(printf '%s\n' "$PAYLOADS" | grep '\.sh$' | grep -vxF -e git-data-bootstrap.sh -e git-data-pre-receive-placeholder.sh | while read -r b; do
  [ -f "${DIR}/${b}" ] && ! grep -q 'GIT_DATA_REPO_ROOT' <<< "$(_code "${DIR}/${b}")" && printf '%s\n' "$b"; done | tr '\n' ' ')"
if [ "${_nonacting% }" = "git-data-luks-reopen.sh" ]; then pass "A4: the only script payload excluded as not store-acting is git-data-luks-reopen.sh (it mounts the store)"
else fail "A4: the not-store-acting exclusion covers '${_nonacting% }', expected exactly git-data-luks-reopen.sh"; fi

EXPECTED_SET="$(printf '%s\n' git-data-gc.sh git-data-provision.sh git-data-remove.sh git-data-transport-wrapper.sh | sort)"
STORE_SET="$(derive_store_set "$MAIN_TF" "$DIR")"
_sn=$(printf '%s\n' "$STORE_SET" | grep -c .)
if [ "$STORE_SET" = "$EXPECTED_SET" ]; then pass "A5: the store-acting set is exactly the four wrappers"
else fail "A5: the derived store-acting set is not the expected four" "derived: $(printf '%s' "$STORE_SET" | tr '\n' ' ')"; fi
if [ "$_sn" -eq 4 ]; then pass "A6: store-acting floor: 4 payloads inspected"
else fail "A6: the census inspected $_sn store-acting payloads, floor and identity are 4"; fi

# ── ARM B — the C1 store assertion in each derived payload ─────────────────────────────────

# The first destructive operation of each wrapper, by name. A table and not a regex family:
# `_gc_run` is DEFINED above gc's mount guard and CALLED below it, so a textual "first
# destructive line" would read the definition and rate every ordering as correct. Each anchor
# is asserted present, so a rename reds here rather than silently emptying the order check.
destructive_anchor() {
  case "$1" in
    git-data-provision.sh)         printf 'git init --bare ' ;;
    git-data-remove.sh)            printf 'rm -rf --one-file-system ' ;;
    git-data-transport-wrapper.sh) printf 'exec git -c ' ;;
    git-data-gc.sh)                printf '_gc_run ' ;;
    *)                             printf '' ;;
  esac
}

# Prints the name of every C1 check MISSING from <script>, one per line. Empty output means
# compliant. Read on the COMMENT-STRIPPED body (matrix row 5).
store_check_gaps() { # store_check_gaps <script path> <basename>
  local f="$1" b="$2" C rootvar anchor mp dev mk destr
  C="$(_code "$f")"
  rootvar="$(printf '%s\n' "$C" | sed -nE 's/.*mountpoint -q "\$([A-Z_]+)".*/\1/p' | head -1)"
  if [ -z "$rootvar" ]; then printf 'mount-guard\n'; return 0; fi
  grep -qE '^STORE_DEVICE="\$\{GIT_DATA_STORE_DEVICE:-/dev/mapper/git-data\}"$' <<< "$C" || printf 'device-seam\n'
  grep -qE '^STORE_VERIFIED="\$\{GIT_DATA_STORE_VERIFIED:-/etc/git-data/store-verified\}"$' <<< "$C" || printf 'marker-seam\n'
  grep -qE '^command -v findmnt >/dev/null 2>&1 \|\| [a-z_]+ ' <<< "$C" || printf 'findmnt-available\n'
  # EQUALITY, and on the mount root this script actually guards. `[ x = y ]` cannot glob; a
  # `case`/`[[ == ]]` prefix rewrite (matrix row 6) fails this anchor.
  grep -qE "^\[ \"\\\$\(findmnt -n -o SOURCE --mountpoint \"\\\$${rootvar}\" 2>/dev/null\)\" = \"\\\$STORE_DEVICE\" \] \|\| " <<< "$C" || printf 'source-equality\n'
  grep -qE '^\[ -n "\$store_uuid" \] && \[ -s "\$STORE_VERIFIED" \] && \[ "\$\(head -n 1 "\$STORE_VERIFIED"\)" = "\$store_uuid" \] \|\| ' <<< "$C" || printf 'marker-uuid\n'
  anchor="$(destructive_anchor "$b")"
  if [ -z "$anchor" ]; then printf 'no-destructive-anchor\n'; return 0; fi
  mp=$(printf '%s\n' "$C" | grep -nF "mountpoint -q \"\$${rootvar}\"" | head -1 | cut -d: -f1)
  dev=$(printf '%s\n' "$C" | grep -n 'findmnt -n -o SOURCE --mountpoint' | head -1 | cut -d: -f1)
  mk=$(printf '%s\n' "$C" | grep -n 'head -n 1 "\$STORE_VERIFIED"' | head -1 | cut -d: -f1)
  destr=$(printf '%s\n' "$C" | grep -nF "$anchor" | head -1 | cut -d: -f1)
  [ -n "$destr" ] || { printf 'destructive-anchor-absent\n'; return 0; }
  [ -n "$dev" ] && [ -n "$mp" ] && [ "$dev" -gt "$mp" ] || printf 'order-after-mountpoint\n'
  [ -n "$dev" ] && [ "$dev" -lt "$destr" ] || printf 'order-before-destructive\n'
  [ -n "$mk" ] && [ "$mk" -lt "$destr" ] || printf 'marker-before-destructive\n'
}

while read -r b; do
  [ -n "$b" ] || continue
  _gaps="$(store_check_gaps "${DIR}/${b}" "$b" | tr '\n' ' ')"
  if [ -z "${_gaps// /}" ]; then pass "B: $b carries the whole C1 assertion, ahead of $(destructive_anchor "$b")"
  else fail "B: $b is missing C1 checks: ${_gaps% }"; fi
done <<< "$STORE_SET"

# ── ARM C — the gc unit strips the seams ───────────────────────────────────────────────────
# AFTER doppler, so a key in prd_git_data cannot survive into gc's environment. The four are
# the contract's; gc also strips GIT_DATA_ROOT, its own name for the mount seam, and that is
# asserted separately rather than folded in, so dropping it is visible.
_exec="$(grep -E '^ExecStart=' "$GC_SERVICE" | head -1)"
for v in GIT_DATA_STORE_DEVICE GIT_DATA_STORE_VERIFIED GIT_DATA_MOUNT_ROOT GIT_DATA_REPO_ROOT; do
  if grep -qF -- "-u $v" <<< "$_exec"; then pass "C: git-data-gc.service strips $v"
  else fail "C: git-data-gc.service ExecStart does not strip $v" "$_exec"; fi
done
if grep -qF -- '-u GIT_DATA_ROOT' <<< "$_exec"; then pass "C: git-data-gc.service also strips GIT_DATA_ROOT (gc's own mount seam)"
else fail "C: git-data-gc.service ExecStart does not strip GIT_DATA_ROOT" "$_exec"; fi
if grep -qE 'doppler run .*-- /usr/bin/env -u ' <<< "$_exec"; then pass "C: the env -u strip runs AFTER doppler run, so an injected seam is removed"
else fail "C: env -u does not sit between doppler run and the gc script" "$_exec"; fi

# ── ARM D — the sshd environment path is closed ────────────────────────────────────────────
# Comment-stripped, because the runcmd stage's own rationale quotes "AcceptEnv LANG LC_*" and a
# bare grep would read the prose as the directive.
sshd_env_gaps() { # sshd_env_gaps <cloud-init template>
  local C bad
  C="$(_code "$1")"
  bad="$(grep -E '^[[:space:]]*AcceptEnv[[:space:]]' <<< "$C" | tr -s ' ' | sed -E 's/^[[:space:]]*AcceptEnv[[:space:]]//' | tr ' ' '\n' | grep -vE '^(LANG|LC_\*|LC_[A-Z_]+|)$' | tr '\n' ' ')"
  [ -z "${bad// /}" ] || printf 'acceptenv-widened:%s\n' "${bad% }"
  grep -qE '^[[:space:]]*PermitUserEnvironment[[:space:]]+yes[[:space:]]*$' <<< "$C" && printf 'permituserenvironment-yes\n'
  local ak; ak="$(grep -E '^[[:space:]]*command="/usr/local/bin/git-data-' <<< "$C")"
  grep -q 'environment=' <<< "$ak" && printf 'authorized-keys-environment\n'
  return 0
}
_sgaps="$(sshd_env_gaps "$TEMPLATE" | tr '\n' ' ')"
if [ -z "${_sgaps// /}" ]; then pass "D1: the rendered sshd_config never widens AcceptEnv, never sets PermitUserEnvironment yes, and no authorized_keys line carries environment="
else fail "D1: the sshd client-environment path is open: ${_sgaps% }"; fi
# The lint above is a static read of the template; the host ENFORCES the same two facts from
# `sshd -T` at boot. Pin that the enforcement exists, so the lint cannot become the only reader.
if grep -qF 'permituserenvironment no' "$TEMPLATE"; then pass "D2: the boot sshd -T stage FATALs unless permituserenvironment reads no"
else fail "D2: the sshd -T stage no longer enforces permituserenvironment no"; fi
if grep -qF '$1=="acceptenv"' "$TEMPLATE"; then pass "D3: the boot sshd -T stage FATALs on any acceptenv value outside LANG/LC_*"
else fail "D3: the sshd -T stage no longer enforces the acceptenv subset"; fi
# The three forced-command keys carry no-user-rc, the last client-controlled execution path
# into the git account's environment.
_akn=$(grep -cE '^[[:space:]]*command="/usr/local/bin/git-data-[a-z-]+\.sh",.*,no-user-rc \$\{git_' "$TEMPLATE")
if [ "$_akn" -eq 3 ]; then pass "D4: all three authorized_keys entries carry no-user-rc"
else fail "D4: $_akn of 3 authorized_keys entries carry no-user-rc"; fi

# ── ARM E — one marker writer, and the probe's seam default ────────────────────────────────
# Every store-acting script READS /etc/git-data; none may write it. A write construct is a
# redirection, install, mv, cp, tee or truncation naming the marker or its directory.
_writers=""
while read -r b; do
  [ -n "$b" ] || continue
  if grep -qE '(> *"?\$STORE_VERIFIED|> *"?/etc/git-data|install -d[^|]*(\$STORE_VERIFIED|/etc/git-data)|(mv|cp|tee|truncate)[^|]*(\$STORE_VERIFIED|/etc/git-data))' <<< "$(_code "${DIR}/${b}")"; then
    _writers="${_writers}${b} "
  fi
done <<< "$STORE_SET"
if [ -z "${_writers// /}" ]; then pass "E1: no store-acting script writes under /etc/git-data — they only read the marker"
else fail "E1: these store-acting scripts write the marker they are supposed to verify: ${_writers% }"; fi
if grep -qE '^install -d -m0755 -o root -g root "\$\(dirname "\$STORE_VERIFIED"\)"$' <<< "$BOOT_CODE"; then pass "E2: git-data-bootstrap.sh creates the marker directory root:root 0755"
else fail "E2: the bootstrap does not create /etc/git-data with install -d -m0755 -o root -g root"; fi
if grep -qE '^mv -f "\$_marker_tmp" "\$STORE_VERIFIED"$' <<< "$BOOT_CODE"; then pass "E3: the bootstrap writes the marker atomically (temp file in the same directory, then mv -f)"
else fail "E3: the bootstrap's marker write is not the atomic temp-plus-mv form"; fi
_bootwrites=$(grep -cE '> *"?\$(_marker_tmp|STORE_VERIFIED)|^mv -f "\$_marker_tmp"' <<< "$BOOT_CODE")
if [ "$_bootwrites" -ge 2 ]; then pass "E4: git-data-bootstrap.sh is the single writer under /etc/git-data"
else fail "E4: the bootstrap's marker writer did not extract ($_bootwrites lines)"; fi
# The erasure probe's script seam (C5). git-data-bootstrap.sh is agent B's file; this row only
# reads it, so a default moved off /usr/local/bin/git-data-remove.sh reds here.
if grep -qF '${GIT_DATA_REMOVE_BIN:-/usr/local/bin/git-data-remove.sh}' <<< "$BOOT_CODE"; then pass "E5: the erasure probe's GIT_DATA_REMOVE_BIN default is /usr/local/bin/git-data-remove.sh"
else fail "E5: the bootstrap's GIT_DATA_REMOVE_BIN seam is absent or no longer defaults to /usr/local/bin/git-data-remove.sh"; fi
if grep -qE 'env -i PATH=/usr/bin:/bin SSH_ORIGINAL_COMMAND=boot-probe-0 [^ ]*runuser -u git --' <<< "$BOOT_CODE"; then pass "E6: the probe runs env -i BEFORE runuser, so no seam reaches the erasure it measures"
else fail "E6: the erasure probe does not place env -i ahead of runuser"; fi

# ── SEAM DERIVATION for the runtime arms ───────────────────────────────────────────────────
# Both seams are DERIVED from the real temp root — the `--mountpoint` SOURCE of the mount
# `stat -c %m` names (never -T; btrfs prints a [/subvol] suffix and a hand-typed device would
# be a second source of truth). A filesystem with no probe-able UUID (tmpfs, a runner whose /
# is /dev/root) cannot give the must-PASS row a real one; only then does a findmnt PATH stub
# answer UUID for that one mountpoint, and the suite SAYS SO.
FM_REAL="$(command -v findmnt)" || { printf 'FAIL SETUP: findmnt(8) not on PATH\n' >&2; exit 1; }
MNT0="$(stat -c %m "$T")"
STORE_SRC="$(findmnt -n -o SOURCE --mountpoint "$MNT0")" || STORE_SRC=""
STORE_UUID="$(findmnt -n -o UUID --mountpoint "$MNT0")" || STORE_UUID=""
[ -n "$STORE_SRC" ] || { printf 'FAIL SETUP: findmnt prints no SOURCE for %s\n' "$MNT0" >&2; exit 1; }
mkdir -p "$T/fm"; : > "$T/uuids"
if [ -z "$STORE_UUID" ]; then
  STORE_UUID="0b1d0000-8211-4000-8000-000000000001"
  printf '%s %s\n' "$MNT0" "$STORE_UUID" >> "$T/uuids"
  printf 'NOTE: %s (%s) has no filesystem UUID — findmnt UUID stub in use for it\n' "$MNT0" "$STORE_SRC"
fi
cat > "$T/fm/findmnt" <<STUB
#!/usr/bin/env bash
if [ "\$#" = 5 ] && [ "\$1 \$2 \$3 \$4" = "-n -o UUID --mountpoint" ]; then
  while read -r m u; do [ "\$m" = "\$5" ] && { printf '%s\n' "\$u"; exit 0; }; done < "$T/uuids"
fi
exec "$FM_REAL" "\$@"
STUB
chmod +x "$T/fm/findmnt"
printf '%s\n' "$STORE_UUID" > "$T/marker"
printf '%s\n' "ffffffff-8211-4000-8000-00000000dead" > "$T/marker-other"
SPATH="$T/fm:$PATH"
# A curated PATH that keeps every tool gc and remove need EXCEPT findmnt, so the findmnt rows
# anchor on the script's own refusal and not on bash's "command not found".
NOFM="$T/nofm"; mkdir -p "$NOFM"
for tool in bash readlink dirname basename stat head tail tr cut sed grep flock rm mv mkdir git timeout df mktemp mountpoint; do
  _src="$(command -v "$tool")" && ln -s "$_src" "${NOFM}/${tool}"
done
# The emit binary is a seam in both scripts; a stub records the argv so a refusal's emitted
# detail can be read without a network.
cat > "$T/emit" <<'EMIT'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$(dirname "$0")/emits"
EMIT
chmod +x "$T/emit"

# ── ARM F — git-data-gc.sh RUNTIME ─────────────────────────────────────────────────────────
# gc is the one store-acting script with no runtime suite of its own, so its C1 rows are here.
# Every seam gc writes through is redirected into the fixture (cursor, lock, emit), so a run
# never touches a real /run or the mount root the fixture sits on.
GCERR="$T/gc.err"
run_gc() { # run_gc <repo root> <device> <marker> [path]
  local root="$1" dev="$2" marker="$3" path="${4:-$SPATH}"
  rm -f "$T/emits"
  env -i PATH="$path" GIT_DATA_ROOT="$(stat -c %m "$root")" GIT_DATA_REPO_ROOT="$root" \
    GIT_DATA_GC_CURSOR="$T/cursor" GIT_DATA_GC_LOCK="$T/gc.lock" GIT_DATA_EMIT="$T/emit" \
    GIT_DATA_STORE_DEVICE="$dev" GIT_DATA_STORE_VERIFIED="$marker" \
    bash "$GC" >"$GCERR" 2>&1
  echo $?
}
gc_refused() { # gc_refused <row> <rc> <anchor>
  if [ "$2" = "1" ]; then pass "$1: refuses with exit 1 (git-data-gc-failure.service's OnFailure fires)"
  else fail "$1: expected exit 1, got $2" "$(tail -c 200 "$GCERR")"; fi
  if grep -qF "$3" "$GCERR"; then pass "$1: the FATAL names '$3'"
  else fail "$1: the FATAL does not carry '$3'" "$(tail -c 200 "$GCERR")"; fi
  if [ ! -e "$T/cursor" ]; then pass "$1: ORDER — no maintenance ran (no cursor written)"
  else fail "$1: ORDER — gc maintained repos before (or despite) the store refusal"; fi
}
GCROOT="$T/gcrepos"; mkdir -p "$GCROOT"
git init --bare -q "$GCROOT/ws-gc.git" && git --git-dir="$GCROOT/ws-gc.git" symbolic-ref HEAD refs/heads/main
# F1 MUST-PASS: the seam is the temp root's own --mountpoint SOURCE, the marker its UUID.
rm -f "$T/cursor"
rc=$(run_gc "$GCROOT" "$STORE_SRC" "$T/marker")
if [ "$rc" = "0" ]; then pass "F1 must-PASS: gc runs to completion on a verified, mapper-served store"
else fail "F1 must-PASS: expected 0 with the store verified, got $rc" "$(tail -c 300 "$GCERR")"; fi
if [ "$(cat "$T/cursor" 2>/dev/null)" = "ws-gc.git" ]; then pass "F1 must-PASS: the fixture repo was maintained (cursor advanced)"
else fail "F1 must-PASS: gc exited 0 without maintaining the fixture repo" "$(tail -c 300 "$GCERR")"; fi
# F2 mismatch; F3 look-alikes DERIVED from the real SOURCE; F4 marker absent; F5 marker for
# another volume; F6 findmnt(8) absent from a curated PATH that still has mountpoint(1).
rm -f "$T/cursor"
rc=$(run_gc "$GCROOT" "/dev/mapper/git-data" "$T/marker")
gc_refused "F2 device mismatch" "$rc" "is not served by /dev/mapper/git-data"
if grep -qF 'store=not_mapper' "$T/emits" 2>/dev/null; then pass "F2 device mismatch: the refusal emits stage gc fatal with store=not_mapper"
else fail "F2 device mismatch: no store=not_mapper emit" "$(cat "$T/emits" 2>/dev/null)"; fi
for look in "${STORE_SRC%?}" "${STORE_SRC}-old"; do
  rm -f "$T/cursor"
  rc=$(run_gc "$GCROOT" "$look" "$T/marker")
  gc_refused "F3 look-alike '$look'" "$rc" "is not served by $look"
done
rm -f "$T/cursor"
rc=$(run_gc "$GCROOT" "$STORE_SRC" "$T/no-such-marker")
gc_refused "F4 marker absent" "$rc" "store not verified"
rm -f "$T/cursor"
rc=$(run_gc "$GCROOT" "$STORE_SRC" "$T/marker-other")
gc_refused "F5 marker UUID mismatch" "$rc" "store not verified"
rm -f "$T/cursor"
rc=$(run_gc "$GCROOT" "$STORE_SRC" "$T/marker" "$NOFM")
gc_refused "F6 findmnt absent" "$rc" "findmnt unavailable"
rm -f "$T/cursor"

# ── ARM G — the Guard 1 mutation matrix (rows 1-9), each on a TEMPORARY COPY ───────────────

# A mutation harness that reds everything proves nothing, so the pristine copy is required
# GREEN through the very same path every mutant is judged on.
MUT="$T/mut"; mkdir -p "$MUT"
cp "$REMOVE" "$MUT/pristine-remove.sh"
_pg="$(store_check_gaps "$MUT/pristine-remove.sh" git-data-remove.sh | tr '\n' ' ')"
if [ -z "${_pg// /}" ]; then pass "G0 landed control: an UNMUTATED copy of git-data-remove.sh passes every C1 check"
else fail "G0 landed control: the harness reds a pristine copy — every mutant verdict below is meaningless" "${_pg% }"; fi

# BOTH diff sides are counted: an INSERTION (rows 7a/7b) has no `<` line at all, so a
# removed-only count would read "0 changed" for a mutation that landed perfectly.
_landed() { # _landed <row> <orig> <mutant> <expected differing diff lines>
  local n; n=$(diff "$2" "$3" | grep -cE '^[<>]')
  MUTANTS_RUN=$((MUTANTS_RUN + 1))
  if [ "$n" = "$4" ]; then pass "$1: the mutation landed ($n diff line(s))"
  else fail "$1: the mutation did NOT land as expected ($n diff lines, expected $4) — the row below proves nothing"; fi
}
_red() { # _red <row> <gap list> <expected gap name>
  if grep -qw "$3" <<< "$2"; then pass "$1: RED — the census reports '$3'"
  else fail "$1: the mutant passed the census; expected gap '$3', got '${2:-none}'"; fi
}

# Row 1 — delete the device check from git-data-remove.sh only.
M="$MUT/row1.sh"; sed -E '/^\[ "\$\(findmnt -n -o SOURCE --mountpoint/d' "$REMOVE" > "$M"
_landed "G row1 (delete the device check)" "$REMOVE" "$M" 1
_red "G row1 (delete the device check)" "$(store_check_gaps "$M" git-data-remove.sh | tr '\n' ' ')" "source-equality"

# Row 2 — break the main.tf extraction so it iterates zero payloads.
M2="$MUT/row2.tf"; sed 's|file("${path.module}|FILE_RENAMED("${path.module}|g' "$MAIN_TF" > "$M2"
MUTANTS_RUN=$((MUTANTS_RUN + 1))
_n2=$(derive_payloads "$M2" | grep -c .)
if [ "$_n2" -eq 0 ]; then pass "G row2 (extraction finds nothing): the mutation landed — 0 payloads derived"
else fail "G row2: the broken extraction still derived $_n2 payloads"; fi
if [ "$_n2" -lt 10 ] && [ "$(derive_store_set "$M2" "$DIR")" != "$EXPECTED_SET" ]; then pass "G row2: RED — the floor AND the set identity both fail on an empty extraction"
else fail "G row2: an empty extraction still satisfied the floor or the set identity"; fi

# Row 3 — a FIFTH store-acting payload, added after four compliant ones and carrying no check.
M3="$MUT/row3.tf"; PDIR="$T/payloads"; mkdir -p "$PDIR"
while read -r b; do [ -n "$b" ] && ln -sf "${DIR}/${b}" "${PDIR}/${b}"; done <<< "$PAYLOADS"
# The rogue is a PLAUSIBLE payload, not an obviously broken one: it carries the mount guard
# the four real wrappers carry, so the census has to reach the device check to reject it.
cat > "$PDIR/git-data-rogue.sh" <<'ROGUE'
#!/usr/bin/env bash
set -uo pipefail
REPO_ROOT="${GIT_DATA_REPO_ROOT:-/mnt/git-data/repositories}"
MOUNT_ROOT="${GIT_DATA_MOUNT_ROOT:-/mnt/git-data}"
mountpoint -q "$MOUNT_ROOT" || exit 1
rm -rf --one-file-system "$REPO_ROOT/${SSH_ORIGINAL_COMMAND}.git"
ROGUE
sed 's|    git_data_gc  |    git_data_rogue = replace(file("${path.module}/../../git-data-rogue.sh"), local.git_data_rationale_strip, "")\n    git_data_gc  |' "$MAIN_TF" > "$M3"
MUTANTS_RUN=$((MUTANTS_RUN + 1))
_n3=$(derive_payloads "$M3" | grep -c .)
if [ "$_n3" -eq $((_pn + 1)) ]; then pass "G row3 (a fifth store-acting payload): the mutation landed — $_n3 payloads bound"
else fail "G row3: the rogue payload was not added to main.tf ($_n3 payloads, expected $((_pn + 1)))"; fi
_s3="$(derive_store_set "$M3" "$PDIR")"
if [ "$_s3" != "$EXPECTED_SET" ] && grep -qx 'git-data-rogue.sh' <<< "$_s3"; then pass "G row3: RED — set identity rejects the fifth payload"
else fail "G row3: the fifth store-acting payload was not caught by set identity" "$(printf '%s' "$_s3" | tr '\n' ' ')"; fi
_red "G row3 (the rogue payload's own body)" "$(store_check_gaps "$PDIR/git-data-rogue.sh" git-data-remove.sh | tr '\n' ' ')" "source-equality"

# Row 4 — move the check BELOW `rm -rf` (an order row). The exit code stays 1, so only the
# order assertion can see it: the mutant refuses AFTER it has already erased the repository.
M4="$MUT/row4.sh"
awk '
  /^command -v findmnt/, /^\[ -n "\$store_uuid"/ { blk = blk $0 "\n"; next }
  { print }
  /^rm -rf --one-file-system/ { printf "%s", blk }
' "$REMOVE" > "$M4"
MUTANTS_RUN=$((MUTANTS_RUN + 1))
if [ "$(diff "$REMOVE" "$M4" | grep -cE '^[<>]')" = "8" ]; then pass "G row4 (check moved below rm -rf): the mutation landed (4 lines relocated)"
else fail "G row4: the relocation did not land" "$(diff "$REMOVE" "$M4" | head -8 | tr '\n' ' ')"; fi
_red "G row4 (check moved below rm -rf)" "$(store_check_gaps "$M4" git-data-remove.sh | tr '\n' ' ')" "order-before-destructive"
mkdir -p "$T/row4/ws-r4.git"
_rc4=$(env -i PATH="$SPATH" GIT_DATA_REPO_ROOT="$T/row4" GIT_DATA_MOUNT_ROOT="$(stat -c %m "$T")" \
  GIT_DATA_STORE_DEVICE="/dev/mapper/git-data" GIT_DATA_STORE_VERIFIED="$T/marker" \
  SSH_ORIGINAL_COMMAND="ws-r4" bash "$M4" >/dev/null 2>&1; echo $?)
if [ "$_rc4" = "1" ] && [ ! -e "$T/row4/ws-r4.git" ]; then pass "G row4: RED at runtime — the mutant still exits 1, having already erased the repository"
else fail "G row4: the relocated mutant did not demonstrate the erase-then-refuse shape (rc=$_rc4, repo present=$([ -e "$T/row4/ws-r4.git" ] && echo yes || echo no))"; fi

# Row 5 — the check survives only as a COMMENT.
M5="$MUT/row5.sh"; sed -E 's|^(\[ "\$\(findmnt -n -o SOURCE --mountpoint.*)$|# \1|' "$REMOVE" > "$M5"
_landed "G row5 (check only in a comment)" "$REMOVE" "$M5" 2
_red "G row5 (check only in a comment)" "$(store_check_gaps "$M5" git-data-remove.sh | tr '\n' ' ')" "source-equality"

# Row 6 — a PREFIX match instead of equality. The look-alike is derived from the real SOURCE,
# never a hand-typed /dev/mapper/git-data-old.
M6="$MUT/row6.sh"
# The delimiter is % and the two literal pipes are [|][|]: inside an ERE `s|…|…|`, GNU sed
# reads `\|` as alternation with an EMPTY branch, which matches every line and rewrites the
# whole file (measured — the landed check caught it at 153 lines).
sed -E 's%^\[ "\$\(findmnt -n -o SOURCE --mountpoint "\$MOUNT_ROOT" 2>/dev/null\)" = "\$STORE_DEVICE" \] [|][|] reject (.*)$%case "$(findmnt -n -o SOURCE --mountpoint "$MOUNT_ROOT" 2>/dev/null)" in "$STORE_DEVICE"*) ;; *) reject \1 ;; esac%' "$REMOVE" > "$M6"
_landed "G row6 (prefix match instead of equality)" "$REMOVE" "$M6" 2
_red "G row6 (prefix match instead of equality)" "$(store_check_gaps "$M6" git-data-remove.sh | tr '\n' ' ')" "source-equality"
mkdir -p "$T/row6/ws-r6.git"
_rc6=$(env -i PATH="$SPATH" GIT_DATA_REPO_ROOT="$T/row6" GIT_DATA_MOUNT_ROOT="$(stat -c %m "$T")" \
  GIT_DATA_STORE_DEVICE="${STORE_SRC%?}" GIT_DATA_STORE_VERIFIED="$T/marker" \
  SSH_ORIGINAL_COMMAND="ws-r6" bash "$M6" >/dev/null 2>&1; echo $?)
if [ "$_rc6" = "0" ] && [ ! -e "$T/row6/ws-r6.git" ]; then pass "G row6: RED at runtime — the prefix form ACCEPTS a look-alike device the equality form refuses"
else fail "G row6: the prefix mutant did not accept '${STORE_SRC%?}' (rc=$_rc6) — the look-alike fixture no longer demonstrates the difference"; fi

# Row 7 — the sshd client-environment path, opened three ways on a copy of the template.
M7a="$MUT/row7a.yml"; sed 's|^      AuthorizedKeysFile .ssh/authorized_keys$|      AuthorizedKeysFile .ssh/authorized_keys\n      AcceptEnv GIT_DATA_*|' "$TEMPLATE" > "$M7a"
_landed "G row7a (AcceptEnv widened)" "$TEMPLATE" "$M7a" 1
_red "G row7a (AcceptEnv widened)" "$(sshd_env_gaps "$M7a" | tr '\n' ' ')" "acceptenv-widened:GIT_DATA_*"
M7b="$MUT/row7b.yml"; sed 's|^      AuthorizedKeysFile .ssh/authorized_keys$|      AuthorizedKeysFile .ssh/authorized_keys\n      PermitUserEnvironment yes|' "$TEMPLATE" > "$M7b"
_landed "G row7b (PermitUserEnvironment yes)" "$TEMPLATE" "$M7b" 1
_red "G row7b (PermitUserEnvironment yes)" "$(sshd_env_gaps "$M7b" | tr '\n' ' ')" "permituserenvironment-yes"
M7c="$MUT/row7c.yml"; sed 's|^      command="/usr/local/bin/git-data-remove.sh",|      command="/usr/local/bin/git-data-remove.sh",environment="GIT_DATA_STORE_VERIFIED=/tmp/x",|' "$TEMPLATE" > "$M7c"
_landed "G row7c (authorized_keys environment=)" "$TEMPLATE" "$M7c" 2
_red "G row7c (authorized_keys environment=)" "$(sshd_env_gaps "$M7c" | tr '\n' ' ')" "authorized-keys-environment"

# Row 8 — drop the marker requirement from one script.
M8="$MUT/row8.sh"; sed -E '/^\[ -n "\$store_uuid" \]/d' "$REMOVE" > "$M8"
_landed "G row8 (marker requirement dropped)" "$REMOVE" "$M8" 1
_red "G row8 (marker requirement dropped)" "$(store_check_gaps "$M8" git-data-remove.sh | tr '\n' ' ')" "marker-uuid"
mkdir -p "$T/row8/ws-r8.git"
_rc8=$(env -i PATH="$SPATH" GIT_DATA_REPO_ROOT="$T/row8" GIT_DATA_MOUNT_ROOT="$(stat -c %m "$T")" \
  GIT_DATA_STORE_DEVICE="$STORE_SRC" GIT_DATA_STORE_VERIFIED="$T/no-such-marker" \
  SSH_ORIGINAL_COMMAND="ws-r8" bash "$M8" >/dev/null 2>&1; echo $?)
if [ "$_rc8" = "0" ] && [ ! -e "$T/row8/ws-r8.git" ]; then pass "G row8: RED at runtime — without the marker requirement an UNVERIFIED store is erased"
else fail "G row8: the marker-less mutant did not erase on an absent marker (rc=$_rc8)"; fi

# Row 9 — findmnt missing from PATH. The mutant drops the availability guard; the census must
# report it, and the REAL script must still refuse on the same curated PATH (the positive
# control, because an absent findmnt makes every read empty rather than permissive).
M9="$MUT/row9.sh"; sed -E '/^command -v findmnt >\/dev\/null 2>&1 \|\|/d' "$REMOVE" > "$M9"
_landed "G row9 (findmnt availability guard deleted)" "$REMOVE" "$M9" 1
_red "G row9 (findmnt availability guard deleted)" "$(store_check_gaps "$M9" git-data-remove.sh | tr '\n' ' ')" "findmnt-available"
mkdir -p "$T/row9/ws-r9.git"
_err9="$T/row9.err"
_rc9=$(env -i PATH="$NOFM" GIT_DATA_REPO_ROOT="$T/row9" GIT_DATA_MOUNT_ROOT="$(stat -c %m "$T")" \
  GIT_DATA_STORE_DEVICE="$STORE_SRC" GIT_DATA_STORE_VERIFIED="$T/marker" \
  SSH_ORIGINAL_COMMAND="ws-r9" bash "$REMOVE" >/dev/null 2>"$_err9"; echo $?)
if [ "$_rc9" = "1" ] && grep -qF 'findmnt unavailable' "$_err9" && [ -e "$T/row9/ws-r9.git" ]; then pass "G row9: the real script fails CLOSED with findmnt off PATH, naming its own instrument"
else fail "G row9: the real script did not fail closed on a findmnt-less PATH (rc=$_rc9)" "$(tail -c 200 "$_err9")"; fi

# ── FLOOR + LEDGER (ADR-193: reported with printf + exit, never through pass()/fail()) ─────
# MUTANT_FLOOR = the Guard 1 matrix rows this suite drives as landed mutations: rows 1, 2, 3,
# 4, 5, 6, 7a, 7b, 7c, 8, 9 = 11.
MUTANT_FLOOR=11
if [ "$MUTANTS_RUN" -lt "$MUTANT_FLOOR" ]; then
  printf 'FAIL MUTANT FLOOR: only %s mutants executed, floor is %s — a matrix row did not land or was deleted.\n' "$MUTANTS_RUN" "$MUTANT_FLOOR" >&2
  exit 1
fi
# Assertion FLOOR, measured by section and EXACT rather than a margin: removing an assertion
# on purpose costs one edit here. A 6 (A1, A2 x2, A3, A4, A5, A6 = 7 minus the single A2 pair
# counted once) -> measured 7; B 4 (one per derived payload); C 6; D 4; E 6; F 22 (must-PASS 2,
# six refusal rows x3 = 18, the not_mapper emit 1, and the second look-alike 1 is inside the
# 18); G 27 (landed control 1, rows 1/5/8/9 x2, row 2 x2, row 3 x3, row 4 x3, row 6 x3,
# rows 7a/7b/7c x2). Measured total: 76.
FLOOR=76
_ran=$((passes + fails))
if [ "$_ran" -lt "$FLOOR" ]; then
  printf 'FAIL ANTI-VACUITY: only %s assertions ran, floor is %s — cases were deleted, skipped, or the suite exited early.\n' "$_ran" "$FLOOR" >&2
  exit 1
fi
if [ "${#FAILURES[@]}" -ne "$fails" ]; then
  printf 'FAIL LEDGER: %s failures counted but %s recorded\n' "$fails" "${#FAILURES[@]}" >&2; exit 1
fi
printf '\n=== git-data-store-device-census: %d passed, %d failed, %d mutants ===\n\n' "$passes" "$fails" "$MUTANTS_RUN"
exit $(( ${#FAILURES[@]} > 0 ))
