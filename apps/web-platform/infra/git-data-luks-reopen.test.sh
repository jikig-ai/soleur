#!/usr/bin/env bash
# git-data-luks-reopen.test.sh — Guard 1 for #8210: the git-data LUKS mapper is reopened on
# EVERY boot from a Doppler-delivered key, backed by the pinned device, mounted by PID 1 at the
# fstab-named target, never formatted, and every failure is reported exactly once at fatal with
# the failing phase named.
#
# Two arms:
#   STATIC  — predicates over the script, both units, cloud-init, bootstrap, gc.service,
#             issue-alerts.tf and the module variables. Each has a mutation row that must RED.
#   RUNTIME — the script is run against a scratch PATH of stubs (cryptsetup, findmnt,
#             mountpoint, systemctl, journalctl, blockdev, realpath, git-data-emit) under the two
#             test seams (GIT_DATA_REOPEN_RUNDIR / GIT_DATA_REOPEN_DEVICE_WAIT). Every stub
#             appends "<current action tag>|<stub>|<argv>" to a per-fixture calls.log, so ORDER
#             rows assert the phase file is written BEFORE the phase runs (M15) and that the
#             declared phase order is what executes (M11). The reporter unit's `sh -c` body is
#             extracted, its absolute paths rewritten to the scratch dir, and fed the action/log
#             files each failure fixture left behind (composition rows).
#
# systemd-escape is deliberately NOT stubbed: it is present on every systemd host and stubbing
# it would make Scenario 1 test the stub.
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$DIR/git-data-luks-reopen.sh"
UNIT="$DIR/git-data-luks-reopen.service"
REPORTER="$DIR/git-data-luks-reopen-failure.service"
CLOUD_INIT="$DIR/cloud-init-git-data.yml"
BOOTSTRAP="$DIR/git-data-bootstrap.sh"
GC_UNIT="$DIR/git-data-gc.service"
ALERTS="$DIR/sentry/issue-alerts.tf"
MODULE="$DIR/modules/git-data-userdata"

passes=0
fails=0
pass() { passes=$((passes + 1)); }
fail() { fails=$((fails + 1)); echo "FAIL: $1" >&2; [ -n "${2:-}" ] && echo "      $2" >&2; }
ok() { if [ "$1" -eq 0 ]; then pass; else fail "$2" "${3:-}"; fi; }

for f in "$SCRIPT" "$UNIT" "$REPORTER" "$CLOUD_INIT" "$BOOTSTRAP" "$GC_UNIT" "$ALERTS" "$MODULE/variables.tf" "$MODULE/main.tf"; do
  [ -f "$f" ] || { echo "FAIL: missing $f" >&2; exit 1; }
done

SCRATCH="$(mktemp -d -t gdreopen.XXXXXXXX)"
trap 'rm -rf "$SCRATCH"' EXIT

# Drop comment lines the way the module's rationale strip does, so a static row can never be
# satisfied (or tripped) by prose. `#!` survives the strip on purpose.
strip() { grep -vE '^[[:space:]]*#([^!]|$)' "$1"; }

# =====================================================================================
# STATIC — the script
# =====================================================================================
SCRIPT_BODY="$SCRATCH/script.body"; strip "$SCRIPT" > "$SCRIPT_BODY"

n=$(grep -cE '^\s*(mkfs|cryptsetup luksFormat)' "$SCRIPT_BODY" || true)
ok "$((n != 0))" "S1 script never formats (mkfs/luksFormat lines: $n)"
n=$(grep -cE '^\s*trap ' "$SCRIPT_BODY" || true)
ok "$((n != 0))" "S2 script sets no trap — the reporter unit is the single emitter (trap lines: $n)"
n=$(grep -cE '(^|[;&|][[:space:]]*)mount[[:space:]]' "$SCRIPT_BODY" || true)
ok "$((n != 0))" "S3 script never calls mount(8) — PID 1 mounts via the fstab unit (mount calls: $n)"
n=$(grep -c '/usr/local/bin/' "$SCRIPT_BODY" || true)
ok "$((n != 0))" "S4 script names every external command bare, so a scratch PATH intercepts it (/usr/local/bin/ literals: $n)"
n=$(grep -cE 'git-data-emit .*(fatal|warning)' "$SCRIPT_BODY" || true)
ok "$((n != 0))" "S5 script emits no fatal/warning itself (M17) — lines: $n"
n=$(grep -cE '(^|[[:space:]])(set|(ba)?sh)[[:space:]]+-[a-z]*x' "$SCRIPT_BODY" || true)
ok "$((n != 0))" "S6 script never enables xtrace (M24)"
ok "$(grep -qE '^#!/bin/bash' "$SCRIPT"; echo $?)" "S7 script is bash (dash has no pipefail)"
ok "$(grep -qE '^set -euo pipefail' "$SCRIPT_BODY"; echo $?)" "S8 script runs under set -euo pipefail"
ok "$(grep -qE 'RUNDIR="\$\{GIT_DATA_REOPEN_RUNDIR:-/run/git-data-luks-reopen\}"' "$SCRIPT_BODY"; echo $?)" "S9 RUNDIR seam defaults to /run/git-data-luks-reopen"
ok "$(grep -qE 'DEVICE_WAIT="\$\{GIT_DATA_REOPEN_DEVICE_WAIT:-30\}"' "$SCRIPT_BODY"; echo $?)" "S10 DEVICE_WAIT seam defaults to 30"
ok "$(grep -qE 'GIT_DATA_LUKS_DEV.*\^/dev/disk/by-id/scsi-0HC_Volume_\[0-9\]\+\$' "$SCRIPT_BODY"; echo $?)" "S11 phase config asserts the device-pin shape (M23)"
ok "$(grep -qE 'GIT_DATA_DOPPLER_CONFIG.*\^\[a-z0-9_\]\+\$' "$SCRIPT_BODY"; echo $?)" "S11b phase config asserts the config-name shape (M23)"
n=$(grep -c 'doppler run --project soleur ' "$SCRIPT" || true)
ok "$((n != 0))" "S12 no 'doppler run --project soleur ' literal anywhere in the script (p_doppler_config_scope is not line-anchored)"

# Declared phase order — the runtime ORDER rows quantify over THIS list.
PHASES=$(grep -oE '^\s*phase [a-z-]+' "$SCRIPT_BODY" | awk '{print $2}')
PHASE_COUNT=$(printf '%s\n' "$PHASES" | grep -c . || true)
ok "$((PHASE_COUNT < 9))" "S13 the script declares >= 9 phases (found $PHASE_COUNT)"
EXPECTED_ORDER="config key device header open identity target mount identity-mount"
ok "$([ "$(printf '%s\n' "$PHASES" | tr '\n' ' ' | sed 's/ $//')" = "$EXPECTED_ORDER" ]; echo $?)" \
  "S14 phase order is exactly: $EXPECTED_ORDER" "got: $(printf '%s\n' "$PHASES" | tr '\n' ' ')"
# The success stage: the script's only info emit.
INFO_STAGE=$(grep -oE 'git-data-emit "[^"]*" [a-z_]+ info' "$SCRIPT_BODY" | awk '{print $(NF-1)}' | sort -u)
ok "$([ "$INFO_STAGE" = "luks_reopen_ok" ]; echo $?)" "S15 the success emit uses stage luks_reopen_ok (got '$INFO_STAGE')"
n=$(grep -cE 'GIT_DATA_LUKS_KEY' "$SCRIPT_BODY" || true)
_bad=$(grep -nE '\$+\{?GIT_DATA_LUKS_KEY' "$SCRIPT_BODY" \
  | grep -vE '\[[[:space:]]+-n[[:space:]]+"\$+\{?GIT_DATA_LUKS_KEY' \
  | grep -vE "printf '%s' \"\\\$+\{?GIT_DATA_LUKS_KEY" | grep -c . || true)
ok "$((_bad != 0))" "S16 every GIT_DATA_LUKS_KEY expansion is one of the two audited shapes (A28b)"

# =====================================================================================
# STATIC — the unit
# =====================================================================================
UNIT_BODY="$SCRATCH/unit.body"; strip "$UNIT" > "$UNIT_BODY"
unit_has() { grep -qF -- "$2" "$1"; echo $?; }
u_section_of() { awk -v key="$2" '/^\[/{s=$0} $0==key{print s; exit}' "$1"; }

ok "$(unit_has "$UNIT_BODY" 'OnFailure=git-data-luks-reopen-failure.service')" "U1 unit names the reporter via OnFailure= (M13)"
ok "$([ "$(u_section_of "$UNIT_BODY" 'OnFailure=git-data-luks-reopen-failure.service')" = "[Unit]" ]; echo $?)" "U1b OnFailure= is under [Unit] (it is ignored under [Service])"
ok "$(unit_has "$UNIT_BODY" 'Type=oneshot')" "U2 Type=oneshot"
ok "$(unit_has "$UNIT_BODY" 'RemainAfterExit=yes')" "U3 RemainAfterExit=yes"
ok "$(unit_has "$UNIT_BODY" 'Restart=on-failure')" "U4 Restart=on-failure (bounded retry, no in-script loop)"
ok "$(grep -qE '^StartLimitBurst=[0-9]+$' "$UNIT_BODY"; echo $?)" "U4b StartLimitBurst bounds the retry"
ok "$(unit_has "$UNIT_BODY" 'Environment=HOME=/root')" "U5 HOME=/root (doppler dies without it) (M3)"
ok "$(unit_has "$UNIT_BODY" 'EnvironmentFile=-/etc/default/git-data-doppler')" "U6 EnvironmentFile=-/etc/default/git-data-doppler (M2)"
ok "$(unit_has "$UNIT_BODY" 'Environment=TMPDIR=/run/git-data-luks-reopen')" "U7 TMPDIR on tmpfs (the emitter's _devalue mktemp must not touch the root disk)"
ok "$(unit_has "$UNIT_BODY" 'RuntimeDirectory=git-data-luks-reopen')" "U8 RuntimeDirectory=git-data-luks-reopen"
ok "$(unit_has "$UNIT_BODY" 'RuntimeDirectoryPreserve=yes')" "U9 RuntimeDirectoryPreserve=yes — measured: systemd removes the dir at final failure, before OnFailure runs (M19)"
ok "$(unit_has "$UNIT_BODY" 'UMask=0077')" "U10 UMask=0077"
ok "$(unit_has "$UNIT_BODY" 'NoNewPrivileges=yes')" "U11 NoNewPrivileges=yes"
ok "$(unit_has "$UNIT_BODY" 'PrivateTmp=yes')" "U12 PrivateTmp=yes"
ok "$(unit_has "$UNIT_BODY" 'ExecStartPre=/bin/rm -f /run/git-data-luks-reopen/action /run/git-data-luks-reopen/log')" "U13 ExecStartPre clears the phase/log files per attempt (M20)"
ok "$(unit_has "$UNIT_BODY" 'WantedBy=multi-user.target')" "U14 WantedBy=multi-user.target"
ok "$(unit_has "$UNIT_BODY" 'After=network-online.target')" "U15 After=network-online.target"
ok "$(grep -qE '^TimeoutStartSec=[0-9]+$' "$UNIT_BODY"; echo $?)" "U16 TimeoutStartSec set"
DOPPLER_FLAGS='--config "$GIT_DATA_DOPPLER_CONFIG" --only-secrets GIT_DATA_LUKS_KEY --only-secrets BETTERSTACK_LOGS_TOKEN --no-fallback --'
ok "$(grep -qF -- "ExecStart=/bin/sh -c 'exec /usr/local/bin/doppler run --project soleur $DOPPLER_FLAGS /usr/local/bin/git-data-luks-reopen.sh'" "$UNIT_BODY"; echo $?)" \
  "U17 ExecStart is the gc shape with templated --config + --only-secrets x2 + --no-fallback (M8/M9)"
for f in "$UNIT_BODY" "$(strip "$REPORTER" > "$SCRATCH/rep.body"; echo "$SCRATCH/rep.body")"; do
  n=$(grep -c 'prd_git_data' "$f" || true); ok "$((n != 0))" "U18 no hardcoded prd_git_data in $(basename "$f") (M9)"
  n=$(grep -c -- '--no-exit-on-missing-only-secrets' "$f" || true); ok "$((n != 0))" "U19 no --no-exit-on-missing-only-secrets in $(basename "$f") (M24)"
  n=$(grep -c 'GIT_DATA_REOPEN_' "$f" || true); ok "$((n != 0))" "U20 no test seam set in $(basename "$f") (M18)"
  n=$(grep -c -- '--no-fallback' "$f" || true); ok "$((n == 0))" "U21 --no-fallback present in $(basename "$f") (M8)"
done

# =====================================================================================
# STATIC — the reporter
# =====================================================================================
REP_BODY="$SCRATCH/rep.body"
ok "$(unit_has "$REP_BODY" 'Type=oneshot')" "R1 reporter Type=oneshot"
ok "$(unit_has "$REP_BODY" 'Environment=HOME=/root')" "R2 reporter HOME=/root"
ok "$(unit_has "$REP_BODY" 'Environment=TMPDIR=/dev/shm')" "R3 reporter TMPDIR=/dev/shm (not the unit's RuntimeDirectory)"
ok "$(unit_has "$REP_BODY" 'EnvironmentFile=-/etc/default/git-data-doppler')" "R4 reporter EnvironmentFile=-"
ok "$(unit_has "$REP_BODY" 'UMask=0077')" "R5 reporter UMask=0077"
ok "$(grep -qF '/run/git-data-luks-reopen/action' "$REP_BODY"; echo $?)" "R6 reporter reads the phase file"
ok "$(grep -qF 'action=unit' "$REP_BODY"; echo $?)" "R7 reporter falls back to action=unit"
ok "$(grep -qF 'luks_reopen fatal' "$REP_BODY"; echo $?)" "R8 reporter emits at stage luks_reopen level fatal"
ok "$(grep -qF "timeout 90 /usr/local/bin/doppler run --project soleur $DOPPLER_FLAGS \"\$@\" || \"\$@\"" "$REP_BODY"; echo $?)" \
  "R9 reporter's doppler arm is timeout-bounded with the same flags and a direct fallback arm (M21)"
for t in result= rc= code= restarts=; do
  ok "$(grep -qF "$t" "$REP_BODY"; echo $?)" "R10 reporter tags $t"
done
ok "$(grep -qE 'Doppler Error\|Unable to' "$REP_BODY"; echo $?)" "R11 reporter greps the unit journal for the doppler CLI's credential-free error lines when the log is absent"

# =====================================================================================
# STATIC — cloud-init wiring, bootstrap, gc.service, alerts, module
# =====================================================================================
# write_files entries
ci_perm_of() { awk -v p="$2" '$0 ~ "^  - path: "p"$"{f=1} f&&/permissions:/{gsub(/[^0-9]/,""); print; exit}' "$1"; }
ok "$([ "$(ci_perm_of "$CLOUD_INIT" /usr/local/bin/git-data-luks-reopen.sh)" = "0755" ]; echo $?)" "C1 script delivered 0755"
ok "$([ "$(ci_perm_of "$CLOUD_INIT" /etc/systemd/system/git-data-luks-reopen.service)" = "0644" ]; echo $?)" "C2 unit delivered 0644"
ok "$([ "$(ci_perm_of "$CLOUD_INIT" /etc/systemd/system/git-data-luks-reopen-failure.service)" = "0644" ]; echo $?)" "C3 reporter delivered 0644"
ok "$(grep -qE '^\s+\$\{indent\(6, git_data_luks_reopen\)\}' "$CLOUD_INIT"; echo $?)" "C4 script is the module-map interpolation"
ok "$(grep -qE '^\s+\$\{indent\(6, git_data_luks_reopen_service\)\}' "$CLOUD_INIT"; echo $?)" "C5 unit is the module-map interpolation"
ok "$(grep -qE '^\s+\$\{indent\(6, git_data_luks_reopen_failure_service\)\}' "$CLOUD_INIT"; echo $?)" "C6 reporter is the module-map interpolation"

# env lines: the exact content block of /etc/default/git-data-doppler
ENV_BLOCK=$(awk '/^  - path: \/etc\/default\/git-data-doppler$/{f=1;next} f&&/^    content: \|/{c=1;next} f&&c&&/^    [a-z]/{exit} f&&c{print}' "$CLOUD_INIT")
ok "$(printf '%s\n' "$ENV_BLOCK" | grep -qxF '      GIT_DATA_LUKS_DEV=/dev/disk/by-id/scsi-0HC_Volume_${git_data_luks_volume_id}'; echo $?)" "C7 env file carries the templated device pin"
ok "$(printf '%s\n' "$ENV_BLOCK" | grep -qxF '      GIT_DATA_DOPPLER_CONFIG=${doppler_config_name}'; echo $?)" "C8 env file carries the templated config name"
n=$(printf '%s\n' "$ENV_BLOCK" | grep -c 'GIT_DATA_LUKS_KEY' || true)
ok "$((n != 0))" "C9 the passphrase is never written to the env file (M6)"
n=$(printf '%s\n' "$ENV_BLOCK" | grep -c . || true)
ok "$((n != 6))" "C10 env file has exactly the 4 existing lines + 2 new (got $n)"

# runcmd arm item: exactly one enable --now, after LUKSEOF, before nftables and bootstrap
n=$(grep -c 'systemctl enable --now git-data-luks-reopen.service' "$CLOUD_INIT" || true)
ok "$((n != 1))" "C11 exactly one 'systemctl enable --now git-data-luks-reopen.service' in runcmd (got $n) (M1)"
L_ARM=$(grep -n 'systemctl enable --now git-data-luks-reopen.service' "$CLOUD_INIT" | head -1 | cut -d: -f1)
L_EOF=$(grep -nE '^    LUKSEOF$' "$CLOUD_INIT" | head -1 | cut -d: -f1)
L_NFT=$(grep -n 'STAGE=gitdata_nftables_metadata$' "$CLOUD_INIT" | head -1 | cut -d: -f1)
L_BOOT=$(grep -n 'STAGE=bootstrap$' "$CLOUD_INIT" | head -1 | cut -d: -f1)
ok "$([ -n "$L_ARM" ] && [ -n "$L_EOF" ] && [ "$L_ARM" -gt "$L_EOF" ]; echo $?)" "C12 arm item sits after the heredoc's closing LUKSEOF ($L_ARM > $L_EOF)"
ok "$([ -n "$L_ARM" ] && [ -n "$L_NFT" ] && [ "$L_ARM" -lt "$L_NFT" ]; echo $?)" "C13 arm item sits before STAGE=gitdata_nftables_metadata ($L_ARM < $L_NFT)"
ok "$([ -n "$L_ARM" ] && [ -n "$L_BOOT" ] && [ "$L_ARM" -lt "$L_BOOT" ]; echo $?)" "C14 arm item sits before STAGE=bootstrap so boot_complete measures it (M7)"
ok "$(grep -qE '^    STAGE=gitdata_luks_reopen_arm$' "$CLOUD_INIT"; echo $?)" "C15 arm item names STAGE=gitdata_luks_reopen_arm"
n=$(grep -c '_reopen_arm_detail' "$CLOUD_INIT" || true)
ok "$((n < 2))" "C16 arm item uses its own detail variable _reopen_arm_detail (R3(3b)(iii))"
# The template is a templatefile(): the shell `${STAGE}` is written `$${STAGE}` in the source.
n=$(awk -v a="$L_ARM" -v b="$L_NFT" 'NR>a && NR<b' "$CLOUD_INIT" | grep -cF '"$${STAGE}_warn" warning' || true)
ok "$((n != 1))" "C17 arm failure emits a WARNING at \${STAGE}_warn (got $n)"

# bootstrap: the measured boolean
BS_BODY="$SCRATCH/bs.body"; strip "$BOOTSTRAP" > "$BS_BODY"
ok "$(grep -qF '"luks_reopen_unit=${_reopen_unit}"' "$BS_BODY"; echo $?)" "B1 boot_complete carries luks_reopen_unit=\${_reopen_unit}"
n=$(grep -c 'luks_reopen_unit=yes' "$BS_BODY" || true)
ok "$((n != 0))" "B2 the boolean is never a literal yes (Guard 3 M1)"
ok "$(grep -qE 'systemctl is-enabled --quiet git-data-luks-reopen.service' "$BS_BODY"; echo $?)" "B3 the measurement queries is-enabled"
ok "$(grep -qE 'systemctl show -p Result --value git-data-luks-reopen.service.*= *success' "$BS_BODY"; echo $?)" "B4 the measurement requires Result=success"
L_MEAS=$(grep -n '_reopen_unit=yes' "$BS_BODY" | head -1 | cut -d: -f1)
L_EMIT=$(grep -n 'luks_reopen_unit=\${_reopen_unit}' "$BS_BODY" | head -1 | cut -d: -f1)
ok "$([ -n "$L_MEAS" ] && [ -n "$L_EMIT" ] && [ "$L_MEAS" -lt "$L_EMIT" ]; echo $?)" "B5 measurement precedes the emit (Guard 3 M4)"
n=$(grep -c 'cryptsetup luksOpen' "$BOOTSTRAP" || true)
ok "$((n != 1))" "B6 bootstrap §1b untouched: exactly one cryptsetup luksOpen (got $n)"

# gc.service ordering edge
GC_BODY="$SCRATCH/gc.body"; strip "$GC_UNIT" > "$GC_BODY"
ok "$(unit_has "$GC_BODY" 'Wants=git-data-luks-reopen.service')" "G1 gc.service Wants= the reopen (weekly standing retry) (M12)"
ok "$(unit_has "$GC_BODY" 'After=git-data-luks-reopen.service')" "G2 gc.service After= the reopen"

# Sentry routing: the success stage must be absent from every rule; the fatal stages present.
fatal_block() { awk '/^resource "sentry_alert" "git_data_boot_fatal"/{f=1} f{print} f&&/^}/{exit}' "$ALERTS"; }
warn_block() { awk '/^resource "sentry_alert" "git_data_boot_warning"/{f=1} f{print} f&&/^}/{exit}' "$ALERTS"; }
n=$(fatal_block | grep -v '^[[:space:]]*#' | grep -cE "\"$INFO_STAGE\"" || true)
ok "$((n != 0))" "A1 the success stage '$INFO_STAGE' is in NO fatal filter (the rule has no level condition) (M22)"
n=$(warn_block | grep -v '^[[:space:]]*#' | grep -c "$INFO_STAGE" || true)
ok "$((n != 0))" "A1b the success stage is in no warning filter either"
ok "$(fatal_block | grep -v '^[[:space:]]*#' | grep -qE 'value *= *"luks_reopen"'; echo $?)" "A2 luks_reopen routed in git_data_boot_fatal"
ok "$(fatal_block | grep -v '^[[:space:]]*#' | grep -qE 'value *= *"gitdata_luks_reopen_arm"'; echo $?)" "A3 gitdata_luks_reopen_arm routed in git_data_boot_fatal"
ok "$(warn_block | grep -v '^[[:space:]]*#' | grep -q 'gitdata_luks_reopen_arm_warn'; echo $?)" "A4 gitdata_luks_reopen_arm_warn routed in git_data_boot_warning"

# Module variables: validation blocks on the two values the env file carries
var_block() { awk -v v="$2" '$0 ~ "^variable \""v"\""{f=1} f{print} f&&/^}/{exit}' "$1"; }
ok "$(var_block "$MODULE/variables.tf" doppler_config_name | grep -q 'validation'; echo $?)" "V1 doppler_config_name carries a validation block (M23)"
ok "$(var_block "$MODULE/variables.tf" doppler_config_name | grep -qF '^[a-z0-9_]+$'; echo $?)" "V1b …pinning ^[a-z0-9_]+\$"
ok "$(var_block "$MODULE/variables.tf" git_data_luks_volume_id | grep -q 'validation'; echo $?)" "V2 git_data_luks_volume_id carries a validation block (M23)"
ok "$(var_block "$MODULE/variables.tf" git_data_luks_volume_id | grep -qF '^[0-9]+$'; echo $?)" "V2b …pinning ^[0-9]+\$"
# Module map roster: the three payloads are file()-bound on one line each.
for e in git_data_luks_reopen git_data_luks_reopen_service git_data_luks_reopen_failure_service; do
  ok "$(grep -qE "^\s*${e}\s*=\s*replace\(file\(\"\\$\{path\.module\}/\.\./\.\./git-data-luks-reopen[^\"]*\"\), local\.git_data_rationale_strip, \"\"\)" "$MODULE/main.tf"; echo $?)" "V3 module map binds $e"
done

# =====================================================================================
# systemd-analyze verify (present on every systemd host; skipped, not failed, elsewhere)
# =====================================================================================
if command -v systemd-analyze >/dev/null 2>&1; then
  mkdir -p "$SCRATCH/units"
  cp "$UNIT" "$REPORTER" "$GC_UNIT" "$DIR/git-data-gc-failure.service" "$SCRATCH/units/"
  out=$(systemd-analyze verify "$SCRATCH/units/git-data-luks-reopen.service" "$SCRATCH/units/git-data-luks-reopen-failure.service" "$SCRATCH/units/git-data-gc.service" "$SCRATCH/units/git-data-gc-failure.service" 2>&1 || true)
  n=$(printf '%s\n' "$out" | grep -cE 'git-data-(gc|luks-reopen)[^:]*\.service:' || true)
  ok "$((n != 0))" "Y1 systemd-analyze verify is clean over the four units" "$out"
fi

# =====================================================================================
# RUNTIME — stubs
# =====================================================================================
mkdir -p "$SCRATCH/bin"
# Every stub records "<action tag at call time>|<name>|<argv>" — the phase file is read at CALL
# time, which is what makes M15 (phase file written after the phase) observable as a wrong tag.
STUB_PRELUDE='#!/bin/bash
_tag=$(head -n1 "$RUNDIR/action" 2>/dev/null | sed "s/^action=//")
printf "%s|%s|%s\n" "${_tag:-none}" "$(basename "$0")" "$*" >> "$FX/calls.log"
'
mkstub() { { printf '%s' "$STUB_PRELUDE"; cat; } > "$SCRATCH/bin/$1"; chmod +x "$SCRATCH/bin/$1"; }

mkstub blockdev <<'EOF'
[ -f "$FX/device_absent" ] && { echo "blockdev: cannot open $2: No such file or directory" >&2; exit 1; }
cat "$FX/blockdev_size" 2>/dev/null || echo 1073741824
EOF
mkstub cryptsetup <<'EOF'
case "$1" in
  isLuks) rc=$(cat "$FX/isluks_rc" 2>/dev/null || echo 0); [ "$rc" -ne 0 ] && echo "Device $2 is not a valid LUKS device." >&2; exit "$rc" ;;
  luksOpen)
    cat > "$FX/key_seen"
    [ -f "$FX/luksopen_kill" ] && kill -TERM "$PPID"
    rc=$(cat "$FX/luksopen_rc" 2>/dev/null || echo 0)
    [ "$rc" -ne 0 ] && { echo "No key available with this passphrase." >&2; exit "$rc"; }
    echo 1 > "$FX/mapper_open"; exit 0 ;;
  status)
    if [ -f "$FX/mapper_open" ]; then printf '/dev/mapper/%s is active.\n  type:    LUKS2\n  device:  %s\n' "$2" "$(cat "$FX/status_device" 2>/dev/null || echo /dev/disk/by-id/scsi-0HC_Volume_100000002)"; exit 0
    else echo "Device $2 is not active." >&2; exit 4; fi ;;
  luksFormat) echo "FORMAT MUST NEVER RUN" >&2; exit 99 ;;
  *) echo "unexpected cryptsetup $*" >&2; exit 98 ;;
esac
EOF
mkstub findmnt <<'EOF'
if [ "$1" = "--fstab" ]; then
  [ -s "$FX/fstab_target" ] || exit 1
  cat "$FX/fstab_target"; exit 0
fi
# findmnt -n -o SOURCE <target>
[ -f "$FX/mounted" ] || exit 1
cat "$FX/mount_source" 2>/dev/null || echo /dev/mapper/git-data
EOF
mkstub mountpoint <<'EOF'
[ -f "$FX/mounted" ] && exit 0; exit 32
EOF
mkstub realpath <<'EOF'
b=$(basename "$1"); [ -f "$FX/realpath_$b" ] && { cat "$FX/realpath_$b"; exit 0; }; printf '%s\n' "$1"
EOF
mkstub systemctl <<'EOF'
case "$1" in
  daemon-reload) exit 0 ;;
  start) rc=$(cat "$FX/mount_start_rc" 2>/dev/null || echo 0); [ "$rc" -ne 0 ] && { echo "Job for $2 failed because the control process exited with error code." >&2; exit "$rc"; }; touch "$FX/mounted"; exit 0 ;;
  show)
    # systemctl show --value -p <P> <unit>   (script)   /  systemctl show -p Result --value <unit> (bootstrap)
    p=""; for a in "$@"; do case "$prev" in -p) p=$a;; esac; prev=$a; done
    case "$p" in
      NRestarts) cat "$FX/nrestarts" 2>/dev/null || echo 0 ;;
      Result) cat "$FX/result" 2>/dev/null || echo exit-code ;;
      ExecMainStatus) cat "$FX/exec_status" 2>/dev/null || echo 1 ;;
      ExecMainCode) cat "$FX/exec_code" 2>/dev/null || echo 1 ;;
      *) echo "" ;;
    esac; exit 0 ;;
  *) exit 0 ;;
esac
EOF
mkstub journalctl <<'EOF'
cat "$FX/journal" 2>/dev/null; exit 0
EOF
# Mirrors the real emitter's arg-4 contract (detail-file-or-literal): a readable file is
# replaced by its content, so a stale/absent path ships as the literal path — which is what
# the "not a path" rows catch (the #7204 trap).
mkstub git-data-emit <<'EOF'
m="${1:-}"; st="${2:-}"; lv="${3:-}"; d="${4:-}"
if [ -n "$d" ] && [ -r "$d" ] && [ -s "$d" ]; then d=$(tr '\n' ' ' < "$d"); fi
if [ "$#" -ge 4 ]; then shift 4; else shift "$#"; fi
printf '%s\n' "$m $st $lv ${d} $*" >> "$FX/emit.log"
exit 0
EOF
mkstub sleep <<'EOF'
exit 0
EOF
# doppler stub for the reporter arm: mode from $FX/doppler_mode (ok|fail|hang)
cat > "$SCRATCH/doppler" <<'EOF'
#!/bin/bash
printf 'doppler|%s\n' "$*" >> "$FX/calls.log"
mode=$(cat "$FX/doppler_mode" 2>/dev/null || echo ok)
case "$mode" in
  fail) echo "Unable to download secrets" >&2; exit 1 ;;
  hang) sleep 200; exit 1 ;;
esac
while [ "$#" -gt 0 ] && [ "$1" != "--" ]; do shift; done; shift
exec "$@"
EOF
chmod +x "$SCRATCH/doppler"
ln -s "$SCRATCH/bin/git-data-emit" "$SCRATCH/git-data-emit"

# H1 — positive stub census, derived from the script: every external command it names must
# resolve to OUR stub before any fixture runs (never a 127 mid-phase).
EXTERNALS=$(grep -oE '\b(cryptsetup|findmnt|mountpoint|systemctl|journalctl|blockdev|realpath|git-data-emit|sleep)\b' "$SCRIPT_BODY" | sort -u)
n_ext=$(printf '%s\n' "$EXTERNALS" | grep -c . || true)
ok "$((n_ext < 8))" "H1 the script names >= 8 stubbable externals (found $n_ext)"
for c in $EXTERNALS; do
  r=$(PATH="$SCRATCH/bin:$PATH" command -v "$c")
  ok "$([ "$r" = "$SCRATCH/bin/$c" ]; echo $?)" "H1 census: $c resolves to the stub" "resolved to $r"
done
ok "$(grep -qE '\bsystemd-escape\b' "$SCRIPT_BODY"; echo $?)" "H1b the script uses systemd-escape (real, not stubbed)"
ok "$([ ! -e "$SCRATCH/bin/systemd-escape" ]; echo $?)" "H1c systemd-escape is NOT stubbed"

# Fixture runner. $1 = name; the caller pre-populates $FX via `fx_*` helpers.
FX=""; RUNDIR=""
new_fixture() {
  FX="$SCRATCH/fx-$1"; RUNDIR="$FX/run"; rm -rf "$FX"; mkdir -p "$FX" "$RUNDIR"
  : > "$FX/calls.log"
  printf '/mnt/git-data-luks\n' > "$FX/fstab_target"
  export FX RUNDIR
}
run_script() {
  # Returns the script's rc; env is the production shape plus the two seams. Subshell so a
  # fixture that SIGTERMs the script does not print bash's "Terminated" job notice.
  ( env -i PATH="$SCRATCH/bin:/usr/bin:/bin" HOME=/root FX="$FX" RUNDIR="$RUNDIR" \
    GIT_DATA_LUKS_DEV="${DEV_OVERRIDE:-/dev/disk/by-id/scsi-0HC_Volume_100000002}" \
    GIT_DATA_DOPPLER_CONFIG="${CFG_OVERRIDE:-prd_git_data}" \
    GIT_DATA_LUKS_KEY="${KEY_OVERRIDE-stub-passphrase-0000}" \
    GIT_DATA_REOPEN_RUNDIR="$RUNDIR" GIT_DATA_REOPEN_DEVICE_WAIT=1 \
    bash "$SCRIPT" > "$FX/stdout" 2> "$FX/stderr"; _r=$?; exit "$_r" ) 2>/dev/null
}
action_file() { head -n1 "$RUNDIR/action" 2>/dev/null | sed 's/^action=//'; }
calls_of() { grep -F -- "$1" "$FX/calls.log" || true; }
# Every tag in calls.log must be a declared phase, in non-decreasing declared order.
order_ok() {
  local prev=-1 idx t
  while IFS='|' read -r t _ _; do
    [ "$t" = "none" ] && { echo 0; return; }
    idx=$(printf '%s\n' "$PHASES" | grep -nx -- "$t" | cut -d: -f1)
    [ -n "$idx" ] || { echo 0; return; }
    [ "$idx" -ge "$prev" ] || { echo 0; return; }
    prev=$idx
  done < "$FX/calls.log"
  echo 1
}
last_tag() { tail -n1 "$FX/calls.log" | cut -d'|' -f1; }

# --- Scenario 1: closed mapper, target unmounted → reopened -------------------------------
new_fixture s1
run_script; rc=$?
ok "$((rc != 0))" "S1 closed+unmounted exits 0 (rc=$rc)" "$(cat "$FX/stderr")"
ok "$([ "$(calls_of "|cryptsetup|luksOpen" | grep -c 'luksOpen --key-file - /dev/disk/by-id/scsi-0HC_Volume_100000002 git-data')" -eq 1 ]; echo $?)" "S1 luksOpen called once with --key-file - and the pinned device"
ok "$([ "$(cat "$FX/key_seen")" = "stub-passphrase-0000" ]; echo $?)" "S1 the passphrase reached luksOpen on stdin, not argv"
ok "$(calls_of "|systemctl|" | grep -q 'start mnt-git\\x2ddata\\x2dluks.mount'; echo $?)" "S1 PID-1 mount started via the escaped fstab unit (M10)"
ok "$(grep -q 'luks_reopen_ok info' "$FX/emit.log"; echo $?)" "S1 success emit at luks_reopen_ok/info"
ok "$(grep -q 'action=reopened' "$FX/emit.log"; echo $?)" "S1 action=reopened"
ok "$(grep -q 'target=/mnt/git-data-luks' "$FX/emit.log"; echo $?)" "S1 target= tag"
ok "$(grep -q 'restarts=0' "$FX/emit.log"; echo $?)" "S1 restarts= tag"
ok "$([ ! -e "$RUNDIR/action" ] && [ ! -e "$RUNDIR/log" ]; echo $?)" "S1 phase/log files removed on success"
ok "$(( $(order_ok) != 1 ))" "S1 ORDER: every stub call is tagged with a declared phase in declared order (M11/M15)" "$(cat "$FX/calls.log")"
ok "$([ "$(grep -c '|luksFormat' "$FX/calls.log")" -eq 0 ]; echo $?)" "S1 luksFormat never called"
# phase tags on the load-bearing calls
ok "$(grep -q '^header|cryptsetup|isLuks' "$FX/calls.log"; echo $?)" "S1 isLuks runs under tag header (H5)"
ok "$(grep -q '^open|cryptsetup|luksOpen' "$FX/calls.log"; echo $?)" "S1 luksOpen runs under tag open (H5)"
ok "$(grep -q '^mount|systemctl|start' "$FX/calls.log"; echo $?)" "S1 systemctl start runs under tag mount (H5)"
ok "$(grep -q '^identity-mount|findmnt|-n -o SOURCE' "$FX/calls.log"; echo $?)" "S1 findmnt SOURCE runs under tag identity-mount (M5)"

# --- Scenario 2: open + mounted (birth noop) → silent ----------------------------------------
new_fixture s2; touch "$FX/mapper_open" "$FX/mounted"
run_script; rc=$?
ok "$((rc != 0))" "S2 noop exits 0 (rc=$rc)" "$(cat "$FX/stderr")"
ok "$([ "$(calls_of "|cryptsetup|luksOpen" | wc -l)" -eq 0 ]; echo $?)" "S2 no luksOpen"
ok "$([ "$(calls_of "|systemctl|" | grep -c ' start ')" -eq 0 ]; echo $?)" "S2 no systemctl start"
ok "$([ ! -s "$FX/emit.log" ]; echo $?)" "S2 no emit on the noop path"
ok "$([ ! -e "$RUNDIR/action" ]; echo $?)" "S2 phase file removed"
ok "$(grep -q '^identity|realpath|' "$FX/calls.log"; echo $?)" "S2 device identity asserted on the noop path too (M16)"

# --- Scenario 3: open, unmounted → mounted ------------------------------------------------------
new_fixture s3; touch "$FX/mapper_open"
run_script; rc=$?
ok "$((rc != 0))" "S3 open+unmounted exits 0 (rc=$rc)" "$(cat "$FX/stderr")"
ok "$(grep -q 'action=mounted' "$FX/emit.log"; echo $?)" "S3 action=mounted"
ok "$([ "$(calls_of "|cryptsetup|luksOpen" | wc -l)" -eq 0 ]; echo $?)" "S3 no luksOpen"

# --- Scenario 4: post-cutover fstab target (must-PASS non-canonical, H3) ----------------------
new_fixture s4; printf '/mnt/git-data\n' > "$FX/fstab_target"
run_script; rc=$?
ok "$((rc != 0))" "S4 post-cutover target exits 0 (rc=$rc)" "$(cat "$FX/stderr")"
ok "$(calls_of "|systemctl|" | grep -q 'start mnt-git\\x2ddata.mount'; echo $?)" "S4 mount unit derived from fstab: mnt-git\\x2ddata.mount"
ok "$(grep -q 'target=/mnt/git-data' "$FX/emit.log"; echo $?)" "S4 target=/mnt/git-data"

# The reporter arm: extract the unit's `sh -c` body, rewrite its absolute paths to this
# fixture's scratch locations (asserting the counts went N -> 0), shorten the doppler timeout,
# and run it under sh with only the stubs on PATH.
BODY=$(awk '/^ExecStart=\/bin\/sh -c '"'"'/{f=1; sub(/^ExecStart=\/bin\/sh -c '"'"'/,"")} f{print} f&&/'"'"'$/{exit}' "$REP_BODY" | sed "s/'$//" | sed 's/\\$//')
n_abs=$(printf '%s\n' "$BODY" | grep -o '/usr/local/bin/' | wc -l); n_run=$(printf '%s\n' "$BODY" | grep -o '/run/git-data-luks-reopen' | wc -l)
n_to=$(printf '%s\n' "$BODY" | grep -c 'timeout 90 ' || true)
ok "$([ -n "$BODY" ] && [ "$n_abs" -ge 2 ] && [ "$n_run" -ge 2 ] && [ "$n_to" -eq 1 ]; echo $?)" "REP body extracted (abs=$n_abs run=$n_run timeout=$n_to)"
rep_body() {
  BODY2=$(printf '%s\n' "$BODY" | sed "s#/usr/local/bin/#$SCRATCH/#g; s#/run/git-data-luks-reopen#$RUNDIR#g; s#timeout 90 #timeout 3 #")
  n_left=$(printf '%s\n' "$BODY2" | grep -c '/usr/local/bin/\|/run/git-data-luks-reopen\|timeout 90 ' || true)
  ok "$((n_left != 0))" "REP body rewritten for $(basename "$FX") (left=$n_left)"
}
rep_run() { env -i PATH="$SCRATCH/bin:/usr/bin:/bin" FX="$FX" RUNDIR="$RUNDIR" GIT_DATA_DOPPLER_CONFIG=prd_git_data sh -c "$BODY2" > "$FX/rep.out" 2>&1; }

# --- Failure fixtures: one per phase, action file must name THAT phase ------------------------
# Each entry: name|setup-command|expected-phase|expected-detail-substring
FAILS=$(cat <<'EOF'
config-dev|DEV_OVERRIDE=/dev/sdb|config|GIT_DATA_LUKS_DEV
config-dev-flag|DEV_OVERRIDE=--help|config|GIT_DATA_LUKS_DEV
config-cfg|CFG_OVERRIDE='Prd;x'|config|GIT_DATA_DOPPLER_CONFIG
key|KEY_OVERRIDE=|key|GIT_DATA_LUKS_KEY
device|touch "$FX/device_absent"|device|absent
header-rc1|echo 1 > "$FX/isluks_rc"|header|rc=1
header-rc4|echo 4 > "$FX/isluks_rc"|header|rc=4
open|echo 2 > "$FX/luksopen_rc"|open|passphrase
open-sigterm|touch "$FX/luksopen_kill"|open|
identity|touch "$FX/mapper_open"; echo /dev/sdz > "$FX/status_device"|identity|/dev/sdz
target-none|: > "$FX/fstab_target"|target|fstab
target-two|printf '/mnt/a\n/mnt/b\n' > "$FX/fstab_target"|target|fstab
mount|echo 1 > "$FX/mount_start_rc"; printf 'wrong fs type, bad option, bad superblock\n' > "$FX/journal"|mount|bad superblock
identity-mount|touch "$FX/mounted"; echo /dev/sdb1 > "$FX/mount_source"|identity-mount|/dev/sdb1
EOF
)
COVERED_PHASES=""
while IFS='|' read -r name setup phase needle; do
  [ -n "$name" ] || continue
  new_fixture "f-$name"
  DEV_OVERRIDE=""; CFG_OVERRIDE=""; unset KEY_OVERRIDE
  eval "$setup"
  run_script; rc=$?
  unset DEV_OVERRIDE CFG_OVERRIDE KEY_OVERRIDE
  ok "$((rc == 0))" "F[$name] exits non-zero (rc=$rc)"
  ok "$([ "$(action_file)" = "$phase" ]; echo $?)" "F[$name] action file names phase '$phase'" "got '$(action_file)'; calls: $(tr '\n' ';' < "$FX/calls.log")"
  ok "$([ "$(grep -c '|luksFormat' "$FX/calls.log")" -eq 0 ]; echo $?)" "F[$name] luksFormat never called"
  ok "$([ ! -s "$FX/emit.log" ]; echo $?)" "F[$name] the script emits nothing on failure (the reporter does)"
  if [ -n "$needle" ]; then
    ok "$(grep -qF -- "$needle" "$RUNDIR/log"; echo $?)" "F[$name] log carries '$needle'" "log: $(cat "$RUNDIR/log")"
  fi
  # No stub call carries a tag LATER than the failing phase.
  lt=$(last_tag); [ -z "$lt" ] && lt="$phase"
  li=$(printf '%s\n' "$PHASES" | grep -nx -- "$lt" | cut -d: -f1); pi=$(printf '%s\n' "$PHASES" | grep -nx -- "$phase" | cut -d: -f1)
  ok "$([ -n "$li" ] && [ "$li" -le "$pi" ]; echo $?)" "F[$name] no call tagged later than '$phase' (last tag '$lt')"
  COVERED_PHASES="$COVERED_PHASES $phase"

  # Composition: feed the reporter the files this fixture left. It must emit ONE fatal naming P.
  : > "$FX/emit.log"; echo ok > "$FX/doppler_mode"
  echo exit-code > "$FX/result"; echo 1 > "$FX/exec_status"; echo 1 > "$FX/exec_code"; echo 2 > "$FX/nrestarts"
  rep_body; rep_run
  ok "$([ "$(grep -c 'luks_reopen fatal' "$FX/emit.log")" -eq 1 ]; echo $?)" "F[$name] reporter emitted exactly one luks_reopen fatal" "$(cat "$FX/emit.log" "$FX/rep.out")"
  ok "$(grep -q "action=$phase" "$FX/emit.log"; echo $?)" "F[$name] reporter carries action=$phase"
  for t in result=exit-code rc=1 code=1 restarts=2 unit=git-data-luks-reopen.service; do
    ok "$(grep -q "$t" "$FX/emit.log"; echo $?)" "F[$name] reporter tag $t"
  done
  d=$(awk -F'luks_reopen fatal ' '{print $2}' "$FX/emit.log" | awk '{print $1}')
  ok "$([ -n "$d" ] && [ "${d#/}" = "$d" ]; echo $?)" "F[$name] detail is the log CONTENT, not a path (M14)" "detail starts: $d"
  ok "$(grep -q '^doppler|run --project soleur --config prd_git_data --only-secrets GIT_DATA_LUKS_KEY --only-secrets BETTERSTACK_LOGS_TOKEN --no-fallback -- ' "$FX/calls.log"; echo $?)" "F[$name] reporter's doppler arm carries the templated config + flags"
done <<< "$FAILS"
for p in $PHASES; do
  ok "$(printf '%s\n' $COVERED_PHASES | grep -qx -- "$p"; echo $?)" "COVERAGE: phase '$p' has a failure fixture"
done

# --- Reporter with NO files (doppler run / exec / start-timeout class) ------------------------
new_fixture r-unit-journal; rep_body
echo start-limit-hit > "$FX/result"; echo 1 > "$FX/exec_status"; echo 1 > "$FX/exec_code"; echo 5 > "$FX/nrestarts"
printf 'Started git-data-luks-reopen.service.\nUnable to download secrets\n\033[31mDoppler Error:\033[0m Invalid Auth token\nFailed with result exit-code.\n' > "$FX/journal"
echo ok > "$FX/doppler_mode"; rep_run
ok "$([ "$(grep -c 'luks_reopen fatal' "$FX/emit.log")" -eq 1 ]; echo $?)" "R-unit exactly one fatal with no files" "$(cat "$FX/rep.out")"
ok "$(grep -q 'action=unit' "$FX/emit.log"; echo $?)" "R-unit action=unit"
ok "$(grep -q 'result=start-limit-hit' "$FX/emit.log"; echo $?)" "R-unit result=start-limit-hit survives"
ok "$(grep -q 'Doppler Error' "$FX/emit.log"; echo $?)" "R-unit detail is the journal's Doppler line (ANSI stripped)" "$(cat "$FX/emit.log")"
ok "$(! grep -q $'\033' "$FX/emit.log"; echo $?)" "R-unit NEGATIVE: no ANSI escape survives into the detail"

new_fixture r-unit-literal; rep_body
echo timeout > "$FX/result"; : > "$FX/journal"; echo ok > "$FX/doppler_mode"; rep_run
ok "$(grep -q 'the unit failed before the script wrote a detail' "$FX/emit.log"; echo $?)" "R-literal fixed literal when the journal has no doppler line"
ok "$(grep -q 'result=timeout' "$FX/emit.log"; echo $?)" "R-literal result=timeout"

new_fixture r-doppler-fail; rep_body
echo exit-code > "$FX/result"; echo fail > "$FX/doppler_mode"; printf 'action=open\n' > "$RUNDIR/action"; printf 'No key available with this passphrase.\n' > "$RUNDIR/log"; rep_run
ok "$([ "$(grep -c 'luks_reopen fatal' "$FX/emit.log")" -eq 1 ]; echo $?)" "R-dfail the direct arm fires exactly once when doppler run fails"
ok "$(grep -q 'action=open' "$FX/emit.log"; echo $?)" "R-dfail action=open from the phase file"

new_fixture r-doppler-hang; rep_body
echo exit-code > "$FX/result"; echo hang > "$FX/doppler_mode"; printf 'action=mount\n' > "$RUNDIR/action"; printf 'Job failed\n' > "$RUNDIR/log"
t0=$(date +%s); rep_run; t1=$(date +%s)
ok "$([ "$(grep -c 'luks_reopen fatal' "$FX/emit.log")" -eq 1 ]; echo $?)" "R-hang the direct arm fires once when doppler HANGS (timeout arm, M21)"
ok "$(( (t1 - t0) > 20 ))" "R-hang bounded by the timeout ($((t1 - t0))s)"

# --- M20: ExecStartPre clears a stale phase file ---------------------------------------------
new_fixture m20; printf 'action=identity-mount\n' > "$RUNDIR/action"; printf 'stale\n' > "$RUNDIR/log"
PRE=$(grep '^ExecStartPre=' "$UNIT_BODY" | sed 's/^ExecStartPre=//; s#/run/git-data-luks-reopen#'"$RUNDIR"'#g')
sh -c "$PRE"
ok "$([ ! -e "$RUNDIR/action" ] && [ ! -e "$RUNDIR/log" ]; echo $?)" "M20 ExecStartPre removes the stale action/log files"

# --- H2: the recorder is load-bearing (a stub that records nothing cannot pass S1) --------------
new_fixture h2; chmod -x "$SCRATCH/bin/git-data-emit"
run_script; rc=$?; chmod +x "$SCRATCH/bin/git-data-emit"
ok "$((rc == 0))" "H2 a success path whose emitter cannot run is NOT silent-green (rc=$rc)"

# =====================================================================================
# Instrument self-test + floor
# =====================================================================================
_can_p0=$passes; _can_f0=$fails
pass
fail "CANARY — instrument self-test, not a real failure" 2>/dev/null
if [ "$passes" -ne $((_can_p0 + 1)) ] || [ "$fails" -ne $((_can_f0 + 1)) ]; then
  echo "FAIL CANARY: pass()/fail() did not each move their counter by one" >&2
  exit 1
fi
passes=$_can_p0; fails=$_can_f0

MIN_ASSERTIONS=220
total=$((passes + fails))
if [ "$total" -lt "$MIN_ASSERTIONS" ]; then
  printf 'FAIL: ran only %s assertions (floor %s) — suite did not execute fully\n' "$total" "$MIN_ASSERTIONS" >&2
  exit 1
fi
echo "git-data-luks-reopen: ${passes} passed, ${fails} failed (${total} assertions)"
exit $(( fails > 0 ))
