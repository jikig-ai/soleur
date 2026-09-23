#!/usr/bin/env bash
# git-data-luks-reopen.test.sh — Guard 1 for #8210: the git-data LUKS mapper is reopened on
# EVERY boot from a Doppler-delivered key, backed by the pinned device, mounted by PID 1 at the
# fstab-named target, never formatted, and every exhausted ladder is reported exactly once at fatal with
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
cases=0
ok() { cases=$((cases + 1)); if [ "$1" -eq 0 ]; then pass; else fail "$2" "${3:-}"; fi; }

for f in "$SCRIPT" "$UNIT" "$REPORTER" "$CLOUD_INIT" "$BOOTSTRAP" "$GC_UNIT" "$ALERTS" "$MODULE/variables.tf" "$MODULE/main.tf"; do
  [ -f "$f" ] || { echo "FAIL: missing $f" >&2; exit 1; }
done

SCRATCH="$(mktemp -d -t gdreopen.XXXXXXXX)"
# The canonical operand guard (P1a/P1b, #7652/#7708), BYTE-IDENTICAL to the definition in
# plugins/soleur/test/test-helpers.sh — `fixture-dir-operand-assert.test.sh` compares them and
# reds on drift, because a helper that is re-derived per file is eventually re-derived wrongly
# (#7822). Inlined rather than sourced only because this suite lives under apps/web-platform/infra
# and is run standalone by infra-validation.yml; the drift arm is what keeps the copy honest.
# Every scratch write below interpolates a variable into a path, and `rm -rf ""` / `cp x ""` /
# `> "/action"` are what an empty or relative one produces — the trap on the next line is itself
# such a site. Asserted at the boundary, and again per fixture.
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
assert_fixture_dir "$SCRATCH"
trap 'assert_fixture_dir "$SCRATCH"; rm -rf "$SCRATCH"' EXIT

# Drop comment lines the way the module's rationale strip does, so a static row can never be
# satisfied (or tripped) by prose. `#!` survives the strip on purpose.
strip() { grep -vE '^[[:space:]]*#([^!]|$)' "$1"; }

# =====================================================================================
# STATIC — the script
# =====================================================================================
SCRIPT_BODY="$SCRATCH/script.body"; strip "$SCRIPT" > "$SCRIPT_BODY"

# Not `^\s*` — an indented, braced or `$(`-wrapped call is still a call (review: `{ mkfs.ext4
# … ; }` inside the mount branch passed the column-0 form). Any token boundary before the verb.
n=$(grep -cE '(^|[^[:alnum:]_./-])(mkfs(\.[a-z0-9]+)?|wipefs|blkdiscard|shred|dd)([[:space:]]|$)|cryptsetup[[:space:]]+(luksFormat|luksErase|erase|reencrypt)' "$SCRIPT_BODY" || true)
ok "$((n != 0))" "S1 script never formats/wipes (mkfs*/wipefs/blkdiscard/shred/dd/luksFormat/luksErase/reencrypt: $n)"
n=$(grep -cE '^\s*trap ' "$SCRIPT_BODY" || true)
ok "$((n != 0))" "S2 script sets no trap — the reporter unit is the single emitter (trap lines: $n)"
n=$(grep -cE '(^|[;&|({][[:space:]]*|^[[:space:]]+)mount[[:space:]]' "$SCRIPT_BODY" || true)
ok "$((n != 0))" "S3 script never calls mount(8), indented or not — PID 1 mounts via the fstab unit (mount calls: $n)"
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
# S11c — the fstab target is allowlisted to the ONE legal state (#8211: the mapper is born at
# /mnt/git-data). Without it the decrypted store follows whatever a garbled fstab append names,
# started by PID 1. The runtime rows target-legacy/target-rogue prove the refusal; this pins the arm.
ok "$(grep -qxE '[[:space:]]*/mnt/git-data\) : ;;' "$SCRIPT_BODY"; echo $?)" "S11c phase target allowlists exactly /mnt/git-data"
n=$(grep -c '/mnt/git-data-luks' "$SCRIPT_BODY" || true)
ok "$((n != 0))" "S11d the pre-#8211 /mnt/git-data-luks is named nowhere in the script body (got $n)"
n=$(grep -c 'doppler run --project soleur ' "$SCRIPT" || true)
ok "$((n != 0))" "S12 no 'doppler run --project soleur ' literal anywhere in the script (p_doppler_config_scope is not line-anchored)"

# Declared phase order — the runtime ORDER rows quantify over THIS list.
PHASES=$(grep -oE '^\s*phase [a-z-]+' "$SCRIPT_BODY" | awk '{print $2}')
PHASE_COUNT=$(printf '%s\n' "$PHASES" | grep -c . || true)
ok "$((PHASE_COUNT < 9))" "S13 the script declares >= 9 phases (found $PHASE_COUNT)"
EXPECTED_ORDER="config key device header open identity target mount identity-mount emit"
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
unit_has() { grep -qxF -- "$2" "$1"; echo $?; }
u_section_of() { awk -v key="$2" '/^\[/{s=$0} $0==key{print s; exit}' "$1"; }

ok "$(unit_has "$UNIT_BODY" 'OnFailure=git-data-luks-reopen-failure.service')" "U1 unit names the reporter via OnFailure= (M13)"
ok "$([ "$(u_section_of "$UNIT_BODY" 'OnFailure=git-data-luks-reopen-failure.service')" = "[Unit]" ]; echo $?)" "U1b OnFailure= is under [Unit] (it is ignored under [Service])"
ok "$(unit_has "$UNIT_BODY" 'Type=oneshot')" "U2 Type=oneshot"
ok "$(unit_has "$UNIT_BODY" 'RemainAfterExit=yes')" "U3 RemainAfterExit=yes"
ok "$(unit_has "$UNIT_BODY" 'Restart=on-failure')" "U4 Restart=on-failure (bounded retry, no in-script loop)"
ok "$(grep -qE '^StartLimitBurst=[0-9]+$' "$UNIT_BODY"; echo $?)" "U4b StartLimitBurst bounds the retry"
_slb=$(grep -E '^StartLimitBurst=' "$UNIT_BODY" | head -1); _sli=$(grep -E '^StartLimitIntervalSec=' "$UNIT_BODY" | head -1)
ok "$([ "$(u_section_of "$UNIT_BODY" "$_slb")" = "[Unit]" ] && [ "$(u_section_of "$UNIT_BODY" "$_sli")" = "[Unit]" ]; echo $?)" "U4c StartLimitBurst/IntervalSec are under [Unit] (ignored under [Service])"
# THE ONE-EMIT GUARANTEE IS RestartMode=direct. Measured on 261 (review): under the default
# RestartMode the unit transits `failed` before every auto-restart and OnFailure fires PER
# ATTEMPT (3 reporter runs for a 2-burst ladder); with direct it fires once, at convergence.
ok "$(unit_has "$UNIT_BODY" 'RestartMode=direct')" "U4d RestartMode=direct — OnFailure fires once per ladder, not once per attempt"
ok "$([ "$(u_section_of "$UNIT_BODY" 'RestartMode=direct')" = "[Service]" ]; echo $?)" "U4e RestartMode= is under [Service]"
# The emit phase's structural refusal exits 3 and MUST NOT be retried: a retry lands in the
# silent noop branch and erases the fault (review).
ok "$(unit_has "$UNIT_BODY" 'RestartPreventExitStatus=3')" "U4f RestartPreventExitStatus=3 — the structural-emitter refusal is terminal on attempt 1"
ok "$(grep -qE '^[[:space:]]*\*\) printf .*>> "\$\{LOG:\?\}"; exit 3 ;;' "$SCRIPT_BODY"; echo $?)" "U4g …and the script's refusal really exits 3 (the two literals agree)"
ok "$(unit_has "$UNIT_BODY" 'LimitCORE=0')" "U4h LimitCORE=0 — a crash must not write the passphrase to /var/crash on the root disk"
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
# The reporter's bound must exceed its Doppler arm's `timeout` plus the direct arm's worst case
# (90 + 53 = 143 s), or a hang kills the cgroup during the fallback — the exact class M21 closes.
_rep_tmo=$(grep -oE '^TimeoutStartSec=[0-9]+' "$REP_BODY" | grep -oE '[0-9]+' | head -1)
_rep_to=$(grep -oE 'timeout [0-9]+ /usr/local/bin/doppler' "$REP_BODY" | grep -oE '[0-9]+' | head -1)
ok "$([ -n "$_rep_tmo" ] && [ -n "$_rep_to" ] && [ "$_rep_tmo" -ge $((_rep_to + 53)) ]; echo $?)" "RU-tmo reporter TimeoutStartSec (${_rep_tmo:-?}) >= timeout (${_rep_to:-?}) + 53 s direct-arm worst case"
ok "$(unit_has "$REP_BODY" 'PrivateTmp=yes')" "RU-pt reporter PrivateTmp=yes — /etc/default/git-data-doppler points DOPPLER_CONFIG_DIR at /tmp/.doppler, and a planted .doppler.yaml there redirects api-host (review)"
ok "$(unit_has "$REP_BODY" 'LimitCORE=0')" "RU-core reporter LimitCORE=0"
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

# runcmd arm item. THE CENTRAL WIRE OF THIS PR, and its first three revisions were raw-file
# substring greps that a `#` prefix or an `$(echo …)` wrapper walked straight past (review:
# commenting out the enable line stayed 448/448). Three layers now: (1) the item's BODY is
# extracted (STAGE line to the next runcmd item) and comment-stripped; (2) the enable lines are
# pinned by their whole command-substitution SHAPE, anchored at line start, exactly once each;
# (3) the body is RUN under sh with a systemctl spy on PATH, so the assertion is that the
# spy recorded both enables with --no-block — a claim about behaviour, not a token.
ARM_RAW="$SCRATCH/arm.raw"; ARM_BODY="$SCRATCH/arm.body"
awk '/^    STAGE=gitdata_luks_reopen_arm$/{f=1} f&&/^  - \|$/{exit} f' "$CLOUD_INIT" > "$ARM_RAW"
grep -vE '^[[:space:]]*#' "$ARM_RAW" | grep -v '^[[:space:]]*$' > "$ARM_BODY"
n=$(grep -c . "$ARM_BODY" || true)
ok "$((n < 8))" "C11a the arm item's body was extracted and comment-stripped (got $n lines; floor 8)"
n=$(grep -cE '^    _arm_err="\$\(systemctl enable --now --no-block git-data-luks-reopen\.service 2>&1\)" \|\| _arm_rc=\$\?$' "$ARM_BODY" || true)
ok "$((n != 1))" "C11 exactly one '_arm_err=\$(systemctl enable --now --no-block …service 2>&1)\" || _arm_rc=\$?' as a STATEMENT in the arm item (got $n) (M1)"
n=$(grep -cE '^    _arm_err="\$\$\{_arm_err\}\$\(systemctl enable --now --no-block git-data-luks-reopen\.timer 2>&1\)" \|\| _arm_rc=\$\?$' "$ARM_BODY" || true)
ok "$((n != 1))" "C11t exactly one timer enable, --no-block, folded into the SAME _arm_rc (got $n)"
L_ARM_S=$(grep -n 'systemctl enable --now --no-block git-data-luks-reopen.service' "$ARM_BODY" | head -1 | cut -d: -f1)
L_ARM_T=$(grep -n 'systemctl enable --now --no-block git-data-luks-reopen.timer' "$ARM_BODY" | head -1 | cut -d: -f1)
ok "$([ -n "$L_ARM_T" ] && [ -n "$L_ARM_S" ] && [ "$L_ARM_T" -gt "$L_ARM_S" ]; echo $?)" "C11u the timer is armed after the unit, in the same item (service@$L_ARM_S timer@$L_ARM_T)"
n=$(grep -c 'enable --now' "$ARM_BODY" || true)
ok "$((n != 2))" "C11v exactly two enables in the item, and NEITHER blocks (got $n)"
n=$(grep -cE 'enable --now( |$)' "$ARM_BODY" | grep -v -- '--no-block' || true)
n=$(grep -E 'enable --now' "$ARM_BODY" | grep -vc -- '--no-block' || true)
ok "$((n != 0))" "C11w no enable WITHOUT --no-block — under RestartMode=direct a blocking start holds cloud-final for the whole ladder (got $n)"
# (3) RUNTIME: render the templatefile escapes and run the body with spies. The spy records
# argv; a second run makes the TIMER enable fail and asserts the warn emit fires with rc folded.
arm_run() {  # $1 = timer-enable rc for the spy
  local d="$SCRATCH/armrun"; rm -rf "$d"; mkdir -p "$d/bin" "$d/run"
  sed 's/\$\${/${/g' "$ARM_BODY" > "$d/body.sh"
  cat > "$d/bin/systemctl" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "$d/spy.log"
case "\$*" in *git-data-luks-reopen.timer*) exit $1 ;; esac
exit 0
EOF
  cat > "$d/bin/git-data-emit" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "$d/emit.log"
exit 0
EOF
  chmod +x "$d/bin/systemctl" "$d/bin/git-data-emit"
  # the item's absolute emitter path is rewritten to the spy; nothing else is
  sed -i "s#/usr/local/bin/git-data-emit#$d/bin/git-data-emit#; s#/run/git-data-luks-reopen-arm.err#$d/run/arm.err#" "$d/body.sh"
  ( cd "$d" && env -i PATH="$d/bin:/usr/bin:/bin" GIT_DATA_RUNCMD_DETAIL="$d/run/detail" sh "$d/body.sh" > "$d/out" 2>&1 ); echo $?
}
rc=$(arm_run 0)
ok "$((rc != 0))" "C11x the arm item RUNS under sh with the spies (rc=$rc)" "$(cat "$SCRATCH/armrun/out" 2>/dev/null)"
ok "$(grep -qx 'enable --now --no-block git-data-luks-reopen.service' "$SCRATCH/armrun/spy.log"; echo $?)" "C11y the systemctl spy RECORDED the unit enable, --no-block, exact argv"
ok "$(grep -qx 'enable --now --no-block git-data-luks-reopen.timer' "$SCRATCH/armrun/spy.log"; echo $?)" "C11z …and the timer enable, --no-block, exact argv"
ok "$([ ! -s "$SCRATCH/armrun/emit.log" ]; echo $?)" "C11aa healthy arm emits nothing"
rc=$(arm_run 1)
ok "$(grep -q 'gitdata_luks_reopen_arm_warn warning' "$SCRATCH/armrun/emit.log"; echo $?)" "C11ab a FAILED timer enable folds into _arm_rc and emits the \${STAGE}_warn WARNING (review: this fold was unpinned)" "$(cat "$SCRATCH/armrun/emit.log" "$SCRATCH/armrun/out" 2>/dev/null)"
ok "$(grep -q 'luks_reopen_unit=unarmed' "$SCRATCH/armrun/emit.log"; echo $?)" "C11ac …tagged luks_reopen_unit=unarmed"
TIMER="$DIR/git-data-luks-reopen.timer"
ok "$([ -s "$TIMER" ]; echo $?)" "T1 the timer unit file exists and is non-empty"
TIMER_BODY="$SCRATCH/timer.body"; strip "$TIMER" > "$TIMER_BODY"
ok "$(unit_has "$TIMER_BODY" 'OnUnitActiveSec=15min')" "T2 OnUnitActiveSec=15min — the standing retry cadence ADR-198 cites"
ok "$(unit_has "$TIMER_BODY" 'OnBootSec=15min')" "T3 OnBootSec=15min — the post-boot tick"
ok "$(unit_has "$TIMER_BODY" 'WantedBy=timers.target')" "T4 installed under timers.target"
n=$(grep -c '^Persistent=' "$TIMER_BODY" || true)
ok "$((n != 0))" "T5 NO Persistent= — systemd.timer(5): it only has an effect with OnCalendar=, which this timer does not use (got $n)"
n=$(grep -c '^OnCalendar=' "$TIMER_BODY" || true)
ok "$((n != 0))" "T6 NO OnCalendar= — monotonic so a long outage does not fire a burst (got $n)"
n=$(grep -c '^Unit=' "$TIMER_BODY" || true)
ok "$((n != 0))" "T7 no explicit Unit= — the timer triggers its namesake service by default (got $n)"
# T8 (was a >=2-mention count — count-as-placement, review): the timer's write_files entry is
# pinned by path, content binding and mode, like C1-C6 for its siblings.
ok "$(grep -qE '^  - path: /etc/systemd/system/git-data-luks-reopen\.timer$' "$CLOUD_INIT"; echo $?)" "T8 the timer is WRITTEN at /etc/systemd/system/git-data-luks-reopen.timer"
ok "$(grep -qF '${indent(6, git_data_luks_reopen_timer)}' "$CLOUD_INIT"; echo $?)" "T8b …bound to the git_data_luks_reopen_timer render variable"
ok "$([ "$(ci_perm_of "$CLOUD_INIT" /etc/systemd/system/git-data-luks-reopen.timer)" = "0644" ]; echo $?)" "T8c …mode 0644"
L_ARM=$(grep -n 'systemctl enable --now --no-block git-data-luks-reopen.service' "$CLOUD_INIT" | head -1 | cut -d: -f1)
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
ok "$(grep -qE 'systemctl show -p ActiveState --value git-data-luks-reopen.service.*= *active( |]|$)' "$BS_BODY"; echo $?)" "B4 the measurement requires ActiveState=active — the only terminal-success state of a RemainAfterExit oneshot"
n=$(grep -cE 'show -p Result --value git-data-luks-reopen.service.*success' "$BS_BODY" || true)
ok "$((n != 0))" "B4a NO Result=success read — measured on 261, Result resets to success the moment a RETRY starts (got $n)"
# B4b-B4d — THE WAIT IS THE MEASUREMENT, and the wait is DRIVEN, not grepped. The first revision
# pinned the loop's text (`activating`, a bound, an ordering); a `while` -> `if` rewrite and a
# `sleep 5` -> `:` busy loop both stayed green (review). Now the `_reopen_unit` block is
# extracted from the bootstrap and run under sh against a systemctl spy that answers
# `activating` N times and then a terminal state, with `sleep` spied too, so the assertions are
# about how many times it ASKED and what it CONCLUDED.
BS_WAIT="$SCRATCH/bs-wait.sh"
awk '/^_reopen_unit=no$/{f=1} f{print} f&&/^fi$/{exit}' "$BS_BODY" > "$BS_WAIT"
n=$(grep -c . "$BS_WAIT" || true)
ok "$((n < 8))" "B4b the _reopen_unit block was extracted (got $n lines; floor 8)"
wait_run() {  # $1 = how many `activating` answers before $2 = terminal state; $3 = is-enabled rc
  local d="$SCRATCH/waitrun"; rm -rf "$d"; mkdir -p "$d/bin"; printf '%s' "$1" > "$d/left"
  cat > "$d/bin/systemctl" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "$d/spy.log"
case "\$*" in
  *is-enabled*) exit $3 ;;
  *ActiveState*) l=\$(cat "$d/left"); if [ "\$l" -gt 0 ]; then echo activating; printf '%s' \$((l-1)) > "$d/left"; else echo "$2"; fi ;;
  *) echo unknown ;;
esac
EOF
  printf '#!/bin/sh\nprintf %%s\\n "sleep $*" >> "%s/spy.log"\n' "$d" > "$d/bin/sleep"
  chmod +x "$d/bin/systemctl" "$d/bin/sleep"
  ( env -i PATH="$d/bin:/usr/bin:/bin" sh -c ". $BS_WAIT; printf '%s' \"\$_reopen_unit\"" ) 2>"$d/err"
}
v=$(wait_run 3 active 0)
ok "$([ "$v" = yes ]; echo $?)" "B4c activating x3 then active, enabled -> yes (got '$v')" "$(cat "$SCRATCH/waitrun/err")"
n=$(grep -c '^sleep ' "$SCRATCH/waitrun/spy.log" || true)
ok "$((n != 3))" "B4d …and it SLEPT exactly 3 times between asks (got $n) — a busy loop or an if would read 0"
n=$(grep -c 'ActiveState' "$SCRATCH/waitrun/spy.log" || true)
ok "$((n < 4))" "B4e …asking ActiveState at least 4 times (3 activating + the terminal read; got $n)"
v=$(wait_run 3 failed 0)
ok "$([ "$v" = no ]; echo $?)" "B4f activating x3 then failed -> no (got '$v')"
v=$(wait_run 0 active 1)
ok "$([ "$v" = no ]; echo $?)" "B4g active but NOT enabled -> no (armed-for-next-boot-only is not armed) (got '$v')"
v=$(wait_run 0 inactive 0)
ok "$([ "$v" = no ]; echo $?)" "B4h a never-started unit (inactive) -> no, even though its Result would read success (got '$v')"
# the bound: more activating answers than the loop tolerates must still terminate, and read no
_wait_bound=$(grep -oE '_reopen_wait" -lt [0-9]+' "$BS_WAIT" | grep -oE '[0-9]+' | head -1)
ok "$([ -n "$_wait_bound" ] && [ "$_wait_bound" -gt 0 ] && [ "$_wait_bound" -le 600 ]; echo $?)" "B4i the wait is BOUNDED (got ${_wait_bound:-none}s; >0 and <=600)"
v=$(wait_run 200 active 0)
ok "$([ "$v" = no ]; echo $?)" "B4j a unit still activating past the bound reads no (fail-closed with the documented false-negative window) (got '$v')"
n=$(grep -c '^sleep ' "$SCRATCH/waitrun/spy.log" || true)
ok "$([ "$n" -ge 10 ] && [ "$n" -le 200 ]; echo $?)" "B4k …after sleeping bound/5 times, not 200 (got $n)"
L_MEAS=$(grep -n '_reopen_unit=yes' "$BS_BODY" | head -1 | cut -d: -f1)
L_EMIT=$(grep -n 'luks_reopen_unit=\${_reopen_unit}' "$BS_BODY" | head -1 | cut -d: -f1)
ok "$([ -n "$L_MEAS" ] && [ -n "$L_EMIT" ] && [ "$L_MEAS" -lt "$L_EMIT" ]; echo $?)" "B5 measurement precedes the emit (Guard 3 M4)"
n=$(grep -c 'cryptsetup luksOpen' "$BOOTSTRAP" || true)
ok "$((n != 1))" "B6 bootstrap §1b untouched: exactly one cryptsetup luksOpen (got $n)"

# gc.service ordering edge
GC_BODY="$SCRATCH/gc.body"; strip "$GC_UNIT" > "$GC_BODY"
# ORDERING ONLY. The `Wants=` was cut at review: it made a weekly maintenance timer an implicit
# retry driver for a boot-critical unit whose real failure has already paged, and re-fired that
# unit's OnFailure reporter every week. The NEGATIVE is asserted so it cannot drift back in.
ok "$(unit_has "$GC_BODY" 'After=git-data-luks-reopen.service')" "G1 gc.service orders After= the reopen"
n=$(grep -c '^Wants=git-data-luks-reopen.service' "$GC_BODY" || true)
ok "$((n != 0))" "G2 gc.service does NOT Wants= the reopen — ordering, not a retry driver (got $n)"

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
# Module map roster: the FOUR payloads are file()-bound on one line each (the timer was the
# fourth, and was missing from this roster — review).
for e in git_data_luks_reopen git_data_luks_reopen_service git_data_luks_reopen_failure_service git_data_luks_reopen_timer; do
  ok "$(grep -qE "^\s*${e}\s*=\s*replace\(file\(\"\\$\{path\.module\}/\.\./\.\./git-data-luks-reopen[^\"]*\"\), local\.git_data_rationale_strip, \"\"\)" "$MODULE/main.tf"; echo $?)" "V3 module map binds $e"
done

# =====================================================================================
# CROSS-HOST: the per-instance-luksOpen class, ratcheted across EVERY cloud-init
# =====================================================================================
# The git-history seat found this defect — `cryptsetup luksOpen` in cloud-init's per-instance
# `runcmd:` with a `nofail` fstab line, so the store is silently absent on every later boot —
# solved independently THREE times in this tree (registry #6895, inngest #7695, git-data
# #8210) with no importable helper and no gate, so each host re-derived it. This arm is the
# gate: for every cloud-init under infra/ that opens a LUKS mapper in runcmd, a systemd unit
# whose name carries `luks` and `open` must be WRITTEN by that same file and ENABLED by it.
# It does not prescribe the ordering shape (inngest's pre-network keyfile and git-data's
# network-online `doppler run` are both legitimate — ADR-115 records why); it prescribes only
# that a reopen exists. A host added tomorrow with the runcmd `luksOpen` and nothing else REDs
# here, with the three existing hosts named as the precedents to copy.
_ci_luks_hosts=0
for _ci in "$DIR"/cloud-init*.yml; do
  _n=$(grep -acE 'cryptsetup (luksOpen|open) ' "$_ci" || true)
  [ "${_n:-0}" -gt 0 ] || continue
  _ci_luks_hosts=$((_ci_luks_hosts + 1))
  _b=$(basename "$_ci")
  _unit=$(grep -aoE 'path: /etc/systemd/system/[a-z-]*luks[a-z-]*open[a-z-]*\.service' "$_ci" | head -1 | sed 's#.*/##')
  ok "$([ -n "$_unit" ]; echo $?)" "X1 $_b opens a LUKS mapper in runcmd and WRITES a boot-reopen unit (got '${_unit:-none}')" "precedents: git-data-luks-reopen.service, inngest-luks-open.service, registry-luks-open.service"
  if [ -n "$_unit" ]; then
    ok "$(grep -aqE "systemctl enable( --now)?( --no-block)? ${_unit}" "$_ci"; echo $?)" "X2 $_b ENABLES $_unit (a written unit nobody enables is the git-data defect in a new coat)"
    # Scoped to THAT unit's write_files entry (path line to the next `- path:`), not the whole
    # template — review: the first revision matched any inline unit's WantedBy=.
    _ublock="$(awk -v u="$_unit" '$0 ~ "^  - path: /etc/systemd/system/"u"$"{f=1;next} f&&/^  - path: /{exit} f' "$_ci")"
    if grep -aqE '^[[:space:]]*WantedBy=(multi-user|sysinit|local-fs)\.target' <<<"$_ublock"; then
      ok 0 "X3 $_b's $_unit carries an [Install] target inside ITS OWN write_files block"
    elif grep -aqF '${indent(' <<<"$_ublock"; then
      ok 0 "X3 $_b's $_unit is interpolated from a render variable (its [Install] is pinned by that unit's own suite)"
    else
      ok 1 "X3 $_b's $_unit has no [Install] target in its write_files block" "$_ublock"
    fi
  fi
done
ok "$((_ci_luks_hosts < 3))" "X4 the census found the three LUKS hosts this arm exists for (git-data, inngest, registry), got $_ci_luks_hosts — fewer means the grep drifted and X1-X3 ran over a NARROWER set"

# =====================================================================================
# systemd-analyze verify (present on every systemd host; skipped, not failed, elsewhere)
# =====================================================================================
if command -v systemd-analyze >/dev/null 2>&1; then
  assert_fixture_dir "$SCRATCH"
  mkdir -p "$SCRATCH/units"
  # EVERY operand guarded, sources included. All four are rooted at DIR, which is bound by
  # command substitution, so an empty one turns each into a read from the filesystem root.
  cp "${UNIT:?}" "${REPORTER:?}" "${GC_UNIT:?}" "${DIR:?}/git-data-gc-failure.service" "${DIR:?}/git-data-luks-reopen.timer" "${SCRATCH:?}/units/"
  out=$(systemd-analyze verify "$SCRATCH/units/git-data-luks-reopen.service" "$SCRATCH/units/git-data-luks-reopen-failure.service" "$SCRATCH/units/git-data-luks-reopen.timer" "$SCRATCH/units/git-data-gc.service" "$SCRATCH/units/git-data-gc-failure.service" 2>&1 || true)
  n=$(printf '%s\n' "$out" | grep -cE 'git-data-(gc|luks-reopen)[^:]*\.(service|timer):' || true)
  ok "$((n != 0))" "Y1 systemd-analyze verify is clean over the four units" "$out"
fi

# =====================================================================================
# RUNTIME — stubs
# =====================================================================================
mkdir -p "$SCRATCH/bin"
# Every stub records "<action tag at call time>|<name>|<argv>" — the phase file is read at CALL
# time, which is what makes M15 (phase file written after the phase) observable as a wrong tag.
STUB_PRELUDE='#!/bin/bash
case "${FX-}" in /*) : ;; *) printf "FATAL(stub): FX is not absolute\n" >&2; exit 2 ;; esac
_tag=$(head -n1 "$RUNDIR/action" 2>/dev/null | sed "s/^action=//")
printf "%s|%s|%s\n" "${_tag:-none}" "$(basename "$0")" "$*" >> "${FX:?}/calls.log"
'
mkstub() { { printf '%s' "$STUB_PRELUDE"; cat; } > "$SCRATCH/bin/$1"; chmod +x "$SCRATCH/bin/$1"; }

mkstub blockdev <<'EOF'
[ -f "$FX/device_absent" ] && { echo "blockdev: cannot open $2: No such file or directory" >&2; exit 1; }
cat "$FX/blockdev_size" 2>/dev/null || echo 1073741824
EOF
# FORMAT TRAPS. /usr/bin is on the scratch PATH (the script needs coreutils), so without these
# a `mkfs.ext4` added to the script would be the REAL one (review). Each records to calls.log
# under its phase tag and exits 99; the F-loop's "never called" row reads that record.
for _trap in mkfs mkfs.ext4 mkfs.xfs wipefs blkdiscard shred dd; do
  mkstub "$_trap" <<'EOF'
echo "FORMAT TRAP: $0 $*" >&2; exit 99
EOF
done
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
# `emit_rc` in the fixture: the emitter's own exit code (1 = transient POST failure, 2 =
# structural), so the script's tolerate-vs-refuse split can be driven from both sides.
[ -r "$FX/emit_rc" ] && exit "$(cat "$FX/emit_rc")"
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
  hang) exec /usr/bin/sleep 200 ;;
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
  assert_fixture_dir "$SCRATCH"
  FX="$SCRATCH/fx-$1"; RUNDIR="$FX/run"
  assert_fixture_dir "$FX"; assert_fixture_dir "$RUNDIR"
  rm -rf "$FX"; mkdir -p "$FX" "$RUNDIR"
  : > "$FX/calls.log"
  printf '/mnt/git-data\n' > "$FX/fstab_target"
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
# THE NEGATIVE HALF. The row above is satisfied by a script that ALSO puts the key on argv
# (review: appending it to the luksOpen argv passed 448/448). Every artifact the fixture
# produced — argv record, stdout, stderr, the run dir (what the reporter ships as detail) —
# must be free of it; only the stdin recorder may hold it.
# `--exclude` BEFORE `--`: after it, grep reads it as a file operand and the exclusion is silently
# not applied (measured: the row then FAILED on key_seen itself, which is the one file allowed).
key_absent() { ! grep -arqF --exclude=key_seen -- "stub-passphrase-0000" "$FX" "$RUNDIR" 2>/dev/null; echo $?; }
ok "$(key_absent)" "S1n the passphrase appears in NO fixture artifact other than key_seen (argv/stdout/stderr/run dir)" "$(grep -arlF --exclude=key_seen -- 'stub-passphrase-0000' "$FX" "$RUNDIR" 2>/dev/null)"
ok "$(calls_of "|systemctl|" | grep -qx 'mount|systemctl|start mnt-git\\x2ddata.mount'; echo $?)" "S1 PID-1 mount started via the escaped fstab unit (M10)"
ok "$(grep -q 'luks_reopen_ok info' "$FX/emit.log"; echo $?)" "S1 success emit at luks_reopen_ok/info"
ok "$(grep -q 'action=reopened' "$FX/emit.log"; echo $?)" "S1 action=reopened"
ok "$(grep -qE '(^| )target=/mnt/git-data( |$)' "$FX/emit.log"; echo $?)" "S1 target=/mnt/git-data tag (exact token)"
ok "$(grep -q 'restarts=0' "$FX/emit.log"; echo $?)" "S1 restarts= tag"
ok "$([ ! -e "$RUNDIR/action" ] && [ ! -e "$RUNDIR/log" ]; echo $?)" "S1 phase/log files removed on success"
ok "$(( $(order_ok) != 1 ))" "S1 ORDER: every stub call is tagged with a declared phase in declared order (M11/M15)" "$(cat "$FX/calls.log")"
ok "$([ "$(grep -c '|luksFormat' "$FX/calls.log")" -eq 0 ]; echo $?)" "S1 luksFormat never called"
# phase tags on the load-bearing calls
ok "$(grep -q '^header|cryptsetup|isLuks' "$FX/calls.log"; echo $?)" "S1 isLuks runs under tag header (H5)"
ok "$(grep -q '^open|cryptsetup|luksOpen' "$FX/calls.log"; echo $?)" "S1 luksOpen runs under tag open (H5)"
ok "$(grep -q '^mount|systemctl|start' "$FX/calls.log"; echo $?)" "S1 systemctl start runs under tag mount (H5)"
ok "$(grep -q '^identity-mount|findmnt|-n -o SOURCE' "$FX/calls.log"; echo $?)" "S1 findmnt SOURCE runs under tag identity-mount (M5)"

# --- Scenario 1e: the success emit FAILS after a real reopen → still exit 0 -----------------
# The emit is the last thing the script does and it is best-effort: a transient Sentry/DNS blip
# on the info row must not turn a healthy reopen into a failed unit (review finding: without
# `|| true` the phase file still read identity-mount, the ladder re-ran into the silent noop
# branch, and an exhausted ladder shipped a false action=identity-mount fatal).
new_fixture s1e; echo 1 > "$FX/emit_rc"
run_script; rc=$?
ok "$((rc != 0))" "S1e emit rc=1 after a real reopen still exits 0 (rc=$rc)" "$(cat "$FX/stderr")"
ok "$(grep -q 'action=reopened' "$FX/emit.log"; echo $?)" "S1e the emit was attempted (action=reopened reached the emitter)"
ok "$([ ! -e "$RUNDIR/action" ] && [ ! -e "$RUNDIR/log" ]; echo $?)" "S1e phase/log files still removed on success"
ok "$(grep -q 'luksOpen' "$FX/calls.log"; echo $?)" "S1e the fixture really reopened (luksOpen called)"

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
target-rogue|printf '/mnt/rogue\n' > "$FX/fstab_target"|target|not /mnt/git-data
target-legacy|printf '/mnt/git-data-luks\n' > "$FX/fstab_target"|target|'/mnt/git-data-luks', not
mount|echo 1 > "$FX/mount_start_rc"; printf 'wrong fs type, bad option, bad superblock\n' > "$FX/journal"|mount|bad superblock
identity-mount|touch "$FX/mounted"; echo /dev/sdb1 > "$FX/mount_source"|identity-mount|/dev/sdb1
emit|echo 2 > "$FX/emit_rc"|emit|structural
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
  ok "$([ "$(grep -cE '\|(luksFormat|luksErase|mkfs|wipefs|blkdiscard)' "$FX/calls.log")" -eq 0 ]; echo $?)" "F[$name] luksFormat/mkfs/wipefs never called"
  ok "$(key_absent)" "F[$name] the passphrase is in no artifact the reporter could ship" "$(grep -arlF --exclude=key_seen -- 'stub-passphrase-0000' "$FX" "$RUNDIR" 2>/dev/null)"
  if [ "$phase" = emit ]; then
    # The one phase whose failure IS an emit: the script attempted exactly its info row and the
    # emitter refused it structurally. Anything else in the log (a fatal, a second row) is wrong.
    ok "$([ "$(grep -c . "$FX/emit.log")" -eq 1 ] && grep -q 'luks_reopen_ok info' "$FX/emit.log"; echo $?)" "F[$name] the script attempted exactly its ONE info row and nothing else" "$(cat "$FX/emit.log")"
  else
    ok "$([ ! -s "$FX/emit.log" ]; echo $?)" "F[$name] the script emits nothing on failure (the reporter does)"
  fi
  if [ -n "$needle" ]; then
    ok "$(grep -qF -- "$needle" "$RUNDIR/log"; echo $?)" "F[$name] log carries '$needle'" "log: $(cat "$RUNDIR/log")"
  fi
  # No stub call carries a tag LATER than the failing phase.
  lt=$(last_tag); [ -z "$lt" ] && lt="$phase"
  li=$(printf '%s\n' "$PHASES" | grep -nx -- "$lt" | cut -d: -f1); pi=$(printf '%s\n' "$PHASES" | grep -nx -- "$phase" | cut -d: -f1)
  ok "$([ -n "$li" ] && [ "$li" -le "$pi" ]; echo $?)" "F[$name] no call tagged later than '$phase' (last tag '$lt')"
  COVERED_PHASES="$COVERED_PHASES $phase"

  # Composition: feed the reporter the files this fixture left. It must emit ONE fatal naming P.
  # The reporter's emitter must not inherit the script fixture's forced rc (the `emit` row).
  : > "$FX/emit.log"; rm -f "$FX/emit_rc"; echo ok > "$FX/doppler_mode"
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
# A RANGE, never a pin (wall-clock), and the lower bound is what proves the hang was REAL: the
# first revision's `sleep 200` resolved to the suite's own no-op sleep stub, so the timeout arm
# never ran and the row passed in 0-1 s with `timeout` stripped from the body (review).
ok "$([ $((t1 - t0)) -ge 2 ] && [ $((t1 - t0)) -le 20 ]; echo $?)" "R-hang bounded by the timeout: elapsed $((t1 - t0))s, want 2..20 (a hang that returned in 0 s was a stub, not a hang)"

# --- M20: ExecStartPre clears a stale phase file ---------------------------------------------
new_fixture m20; assert_fixture_dir "$RUNDIR"
printf 'action=identity-mount\n' > "$RUNDIR/action"; printf 'stale\n' > "$RUNDIR/log"
PRE=$(grep '^ExecStartPre=' "$UNIT_BODY" | sed 's/^ExecStartPre=//; s#/run/git-data-luks-reopen#'"$RUNDIR"'#g')
sh -c "$PRE"
ok "$([ ! -e "$RUNDIR/action" ] && [ ! -e "$RUNDIR/log" ]; echo $?)" "M20 ExecStartPre removes the stale action/log files"

# --- H2: the recorder is load-bearing (a stub that records nothing cannot pass S1) --------------
new_fixture h2; chmod -x "$SCRATCH/bin/git-data-emit"
run_script; rc=$?; chmod +x "$SCRATCH/bin/git-data-emit"
ok "$((rc == 0))" "H2 a success path whose emitter cannot run is NOT silent-green (rc=$rc)"
ok "$([ "$(action_file)" = emit ]; echo $?)" "H2 …and the phase file names emit, not the last real phase (was identity-mount)"

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

# ADR-193 §2/§3: the floor is checked against the CALL-SITE counter (`cases`, bumped by ok()
# before either verdict helper runs), and the two counts must agree — a verdict counter alone
# cannot see a call site that never reached a verdict (review). The two bindings sit DIRECTLY
# above the `if` with no comment between: guard-vacuity-floor builds its mutant from the floor
# block plus the contiguous simple assignments above it, and a comment breaks the run.
MIN_ASSERTIONS=470
total=$((passes + fails))
if [ "$cases" -lt "$MIN_ASSERTIONS" ]; then
  printf 'FAIL: ran only %s assertion call sites (floor %s) — suite did not execute fully\n' "$cases" "$MIN_ASSERTIONS" >&2
  exit 1
fi
if [ "$cases" -ne "$total" ]; then
  printf 'FAIL: call sites (%s) and verdicts (%s) disagree — an ok() reached neither pass nor fail\n' "$cases" "$total" >&2
  exit 1
fi
echo "git-data-luks-reopen: ${passes} passed, ${fails} failed (${total} assertions)"
exit $(( fails > 0 ))
