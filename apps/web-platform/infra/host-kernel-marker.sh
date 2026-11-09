#!/usr/bin/env bash
# host-kernel-marker.sh --role <web|inngest|registry>
#
# Prints EXACTLY ONE line describing the running kernel of this host, for the SOLEUR_HOST_KERNEL periodic marker
# (#12007; consumed by plugins/soleur/skills/cve-exposure/scripts/host-state.sh and the host-kernel dead-man feeder):
#
#   SOLEUR_HOST_KERNEL v=1 role=<web|inngest|registry> kernel=<uname -r|unreadable> uptime_s=<uint|unknown> \
#     reboot_required=<0|1|unknown> sec_updates=<uint|unknown>[ host=<registry host id>]
#
# (one physical line; the backslash above is documentation only). ` host=` is printed ONLY for --role registry: the
# registry ships no journald identity, so the in-message host is its only isolation (the SOLEUR_ZOT_DISK precedent);
# the journald hosts are identified by the Vector-stamped host_name and a `host=` token on their rows is rejected.
#
# GRAMMAR PROMISES readers rely on:
#   - `kernel=<value>` is ALWAYS followed by a single space and `uptime_s=`, so a reader delimits the kernel without a
#     `$` anchor (the feeder's SQL builder refuses a bare `$`).
#   - `kernel=` carries a value only when `uname -r` matches the anchored shape the reader also pins
#     (^[0-9]+\.[0-9]+\.[0-9]+-[0-9]+-[a-z0-9-]+$); anything else (empty, multi-line, upper-case flavour, shell
#     metacharacters, a failed read) is the literal `unreadable`. No raw host-controlled string ever reaches the line.
#   - A measurement failure is a token value (`unknown` / `unreadable`), NEVER a non-zero exit: this runs from a timer
#     (and, once the registry emitter ships in its follow-up PR, #12386, from a cron wrapper), and a failing unit would turn a missing apt list into a journal storm. The only non-zero
#     exit is 64 (usage: bad or missing role), which prints nothing on stdout.
#
# sec_updates is DISPLAY ONLY. It counts `^Inst .*-security` lines of a SIMULATED `apt-get -s upgrade` over the LOCAL
# package lists (no `apt-get update`, no network, no lock), so a stale list undercounts; it never feeds kernel_state.
# It is bounded by `timeout` (default 20 s) and is `unknown` on any failure or timeout.
#
# ENVIRONMENT. PATH is set explicitly to the system directories only (no /usr/local: this runs as root and a planted
# /usr/local/bin/{uname,apt-get,timeout} must not be picked up) and includes /usr/sbin: cron and systemd both start
# without it (the 2026-07-15 blind-host learning), and a bare `command not found` would read as a dark host. LC_ALL=C
# pins apt's output.
#
# TEST SEAM. Honoured ONLY when HKM_TEST=1 (no unit sets it): HKM_STUB_BIN_DIR (prepended to PATH), HKM_PROC_UPTIME,
# HKM_REBOOT_FILE, HKM_APT_TIMEOUT_S. host-kernel-marker.test.sh proves the seam is inert without HKM_TEST=1.

export LC_ALL=C
readonly REGISTRY_HOST_ID='soleur-registry'
export PATH=/usr/sbin:/usr/bin:/sbin:/bin

UPTIME_FILE=/proc/uptime
REBOOT_FILE=/var/run/reboot-required
APT_TIMEOUT=20
if [[ "${HKM_TEST:-}" == 1 ]]; then
  if [[ -n "${HKM_STUB_BIN_DIR:-}" && -d "${HKM_STUB_BIN_DIR}" ]]; then PATH="${HKM_STUB_BIN_DIR}:${PATH}"; fi
  UPTIME_FILE="${HKM_PROC_UPTIME:-$UPTIME_FILE}"
  REBOOT_FILE="${HKM_REBOOT_FILE:-$REBOOT_FILE}"
  if [[ "${HKM_APT_TIMEOUT_S:-}" =~ ^[1-9][0-9]?$ ]]; then APT_TIMEOUT="$HKM_APT_TIMEOUT_S"; fi
fi

usage() {
  printf 'usage: host-kernel-marker.sh --role <web|inngest|registry>\n' >&2
  exit 64
}

role=""
role_seen=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --role)
      [[ $# -ge 2 && "$role_seen" -eq 0 ]] || usage
      role="$2"; role_seen=1; shift 2 ;;
    *) usage ;;
  esac
done
case "$role" in
  web | inngest | registry) : ;;
  *) usage ;;
esac

# kernel: only the anchored shape is ever printed.
kernel=unreadable
if k="$(uname -r 2>/dev/null)" && [[ "$k" =~ ^[0-9]+\.[0-9]+\.[0-9]+-[0-9]+-[a-z0-9-]+$ ]]; then
  kernel="$k"
fi

# uptime_s: integer part of the first /proc/uptime field.
uptime_s=unknown
up=""
{ read -r up _ < "$UPTIME_FILE"; } 2>/dev/null
if [[ "$up" =~ ^[0-9]{1,12}(\.[0-9]+)?$ ]]; then uptime_s="${up%%.*}"; fi

# reboot_required: marker file present -> 1; absent in a readable directory -> 0; unreadable directory -> unknown.
if [[ -e "$REBOOT_FILE" ]]; then
  reboot_required=1
elif [[ -d "${REBOOT_FILE%/*}" ]]; then
  reboot_required=0
else
  reboot_required=unknown
fi

# sec_updates: simulated upgrade over the local lists, bounded, display only.
sec_updates=unknown
if command -v timeout > /dev/null 2>&1 && command -v apt-get > /dev/null 2>&1; then
  if apt_out="$(timeout -k 2 "$APT_TIMEOUT" apt-get -s -o Debug::NoLocking=1 upgrade 2> /dev/null)"; then
    n="$(printf '%s\n' "$apt_out" | grep -c '^Inst .*-security')"
    if [[ "$n" =~ ^[0-9]{1,9}$ ]]; then sec_updates="$n"; fi
  fi
fi

line="SOLEUR_HOST_KERNEL v=1 role=${role} kernel=${kernel} uptime_s=${uptime_s} reboot_required=${reboot_required} sec_updates=${sec_updates}"

if [[ "$role" == registry ]]; then
  # The registry id is a CONSTANT, never whatever `hostname` prints: the helper (host-state.sh REGISTRY_HOST_ID) and the
  # dead-man feeder predicate pin this same literal, and a test asserts equality across all three.
  line="${line} host=${REGISTRY_HOST_ID}"
fi

printf '%s\n' "$line"
exit 0
