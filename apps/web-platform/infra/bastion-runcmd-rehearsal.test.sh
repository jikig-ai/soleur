#!/usr/bin/env bash
# bastion-runcmd-rehearsal.test.sh — soleur-bastion's first boot, rehearsed under REAL cloud-init (#12941).
#
# PROPERTY. The rendered bastion user-data (bastion-cloud-init.yml through terraform's own
# templatefile, bastion-egress.sh base64-embedded), seeded as NoCloud and booted by real cloud-init
# with systemd as PID 1 in the pinned ubuntu:24.04 image, reaches `fresh_boot_ready` with no fatal;
# and each named boot fault class makes it report `fresh_boot_not_ready_<stage>` (or the named
# missing evidence) for the stage that owns the fault. A stub Sentry on its own container records the
# boot trail over https, across a real network hop and through the loaded nftables chain.
#
# WHAT A GREEN RUN PROVES: bootcmd, write_files, cc_ssh, apt_configure and every runcmd item ran on
# the rendered bytes; the apt stage completes with the baseline already written; the https sources
# survive apt_configure; egress_load loads the allowlist and the allowlisted paths work for root and
# _apt only; a stage failure reaches the stub with a detail naming the reason; the kernel-settle
# reboot branch re-runs runcmd once and ends ready. WHAT IT DOES NOT PROVE (divergences, CTO Q8):
#
#   divergence                                          leaves untested
#   names pinned with --add-host                        the resolver rows `ip daddr { 185.12.64.1,
#                                                       185.12.64.2 } udp/tcp dport 53` and real DNS
#                                                       under the loaded chain
#   NoCloud datasource, no metadata service             the `meta skuid 0 ip daddr 169.254.169.254
#                                                       tcp dport 80 accept` row, the Hetzner datasource
#   fixture CA, docker cp'd before start to             the real Sentry certificate chain
#     /usr/local/share/ca-certificates/brh.crt plus a
#     host-built bundle at /etc/ssl/certs (CTO Q23)
#   dummy linux-image-generic 999:0.0.0-1 and           the real kernel install and its ~895 MB download
#     linux-image-0.0.0-1-generic
#   /usr/local/sbin/uname and /usr/local/sbin/reboot    the real reboot and the real kernel string
#     shims (runcmd's PATH puts /usr/local/sbin first)
#   10.0.1.70/32 on lo (CTO Q21; the private_ip stage   the hot-attached Hetzner private NIC, and the
#     matches the address on any interface)             networkd file write_files installs for it
#   containers share the host boot_id (CTO Q24); the    `journalctl -b`'s per-boot scoping; on the real
#     same holds for `_egress_why`'s `-b               host it separates the settle reboot's two boots
#     _SYSTEMD_UNIT=` read (CTO Q29)
#   `container=docker`; systemd-sysctl, -binfmt,        nothing the template uses (it calls no sysctl,
#     -modules-load, -udevd, -udev-trigger masked;      modprobe or udev); timesyncd is NOT masked and
#     journald ReadKMsg=no (CTO Q21)                    skips itself (ConditionVirtualization=!container)
#   getty@, console-getty and getty.target masked       no getty runs on the real host's first boot path;
#     (CTO Q27; BRH_GETTY_UNMASKED refuses an image     under --privileged one would own the host's tty1
#     that lacks the masks, before any boot)
#   cloud-init from the archive (version printed)       whatever cloud-init the Hetzner image bakes
#   IMAGE_ASSUMED installed into the fixture            whether the Hetzner image really ships it
#   the empty-DSN render arm is not booted              it dies silently at egress_load by design; the
#                                                       birth interlock refuses an empty DSN
#
# TWO BASELINES (CTO Q10). Every row boots the MINIMAL image (IMAGE_ASSUMED only, built with
# --no-install-recommends so systemd's Recommends cannot add systemd-timesyncd and its user); row
# B1-C boots the CLOUD-FAITHFUL layer (CLOUD_IMAGE_PKGS, the packages of the public noble cloud image
# the template depends on). They catch opposite fault classes: the minimal image reds a template that
# relies on the image for a user its rules name (FA), the cloud image reds a template that breaks when
# a package it installs is already there (the M1 conffile class, reversed).
#
# ROWS. B1 healthy (+ B1-E egress probes, B1-P PartOf/refresh, P7 private-ip stanza), B2 reboot branch
# (two boots), M1 conffile, M2 preserve_sources_list removed, F1 egress_load fatal, F1-M flush removed,
# FA NTP user dropped, B1-C cloud-faithful. 9 boots in three waves of up to three.
#
# VERDICTS. PASS, FAIL, SKIP (a boot row declined by the archive, ADR-188; never a PASS, CTO Q7) or
# PARTIAL (a local subset). SKIP exits 0 only on GITHUB_EVENT_NAME pull_request or push, which gate
# nothing; any other event (a dispatched birth-gate run), or none under CI, turns it into
# `FAIL (BRH_SKIP_ON_GATE_EVENT)` (CTO Q28). CI means CI or GITHUB_ACTIONS is set. Under GitHub
# Actions every red exit leaves an `::error title=bastion-boot-rehearsal::` annotation: one per failed
# assertion, or one naming the verdict reason (a refusal, the floor, a gate-event SKIP) when none failed.
#
# LOCAL SUBSETS. BRH_STATIC_ONLY=1 boots nothing (the self-tests, the image checks, S0 and S1) but
# still builds the fixture images, so it needs the archive; BRH_ROWS=B1,F1 boots
# only the named rows. Both end `bastion-runcmd-rehearsal: PARTIAL (...)`, never PASS, and both are
# refused under CI (BRH_SUBSET_REFUSED). BRH_KEEP_TMP=1 keeps the work dir on a pass (it is always kept
# on a failure, with private keys and seed user-data deleted first). BRH_ARCHIVE_PIN=<ip> pins the
# archive names to an address (Test Scenario 4, refused under CI).
#
# MUTATION ANCHORS. The template lines this file edits for M1, M2, F1-M and FA live in the ANCHORS
# block below. A miss prints `BRH_ANCHOR_MISS:<row> anchor=...`: either the template line was reworded
# (update the anchor here) or the fix the row guards was reverted (FA's anchor is the FAULT-A apt line;
# bastion.test.sh egress row 23 reds that revert on substance).
#
# STALE RUNS. A run killed without its EXIT trap leaves `brh-<pid>-*` containers and networks and a
# `brh.*` work dir under ${SOLEUR_SCRATCH_BASE:-$TMPDIR} (the base the work dir is created in); the
# next run reaps containers and networks whose <pid> is dead and that are over an hour old (age from
# docker's own Created field: RFC 3339 for a container, `{{.Created.Unix}}` for a network, since
# `date -d` rejects the network's Go time form), under the subnet flock, and this user's work dirs
# there older than 12 h.
#
# Run: bash apps/web-platform/infra/bastion-runcmd-rehearsal.test.sh   (CI: job bastion-boot-rehearsal)
# pyramid-justified: e2e layer by necessity (CTO Q1, Q6): the two shipped faults (FAULT-A, nft refusing the user a package never installed; FAULT-B, the boilerplate fatal detail) were invisible to every static pin and reproduce only under real cloud-init, dpkg, nft and journald.
# Presence under apps/web-platform/infra/ IS registration — run-registered-suites.sh (#8736).
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016,SC2319  # single-quoted scripts expand in the containers; "$(cond; echo $?)" turns a condition into an rc argument
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$DIR/../../.." && pwd)"
SELF="$DIR/$(basename "${BASH_SOURCE[0]}")"
TPL="$DIR/bastion-cloud-init.yml"
EGRESS_SH="$DIR/bastion-egress.sh"
GD_SUITE="$DIR/git-data-runcmd-rehearsal.test.sh"
CREATE_WF="$ROOT/.github/workflows/bastion-host-create.yml"
TRAIL_READER="$DIR/scripts/fresh-host-boot-trail.sh"
APT_LIB="$DIR/lib/apt-bounded.sh"
TAB=$'\t'

# ── Constants (the budget is derived from these; CTO Q14) ───────────────────────────────────────
BOOT_CAP_S=150      # per boot: about 2x the slowest single boot measured (73 s)
BUILD_CAP_S=180     # both fixture images, cold
APT_BUDGET_S=150    # apt seconds shared by the two image builds (lib/apt-bounded.sh)
CLOUD_INIT_RECORDED=26.2
ROWS=(B1 B2 M1 M2 F1 F1-M FA B1-C)
WAVES=("B1 B2 M1" "M2 F1 F1-M" "FA B1-C")
declare -A ROW_BOOTS=([B1]=1 [B2]=2 [M1]=1 [M2]=1 [F1]=1 [F1-M]=1 [FA]=1 [B1-C]=1)
declare -A ROW_MODE=([B1]=settled [B2]=reboot [M1]=settled [M2]=settled [F1]=settled [F1-M]=settled [FA]=settled [B1-C]=settled)
declare -A ROW_IMG=([B1]=min [B2]=min [M1]=min [M2]=min [F1]=min [F1-M]=min [FA]=min [B1-C]=cloud)
# Assertions each row makes (its assert_* function); a row that makes a different number is a FAIL.
declare -A ROW_CASES=([B1]=21 [B2]=6 [M1]=4 [M2]=4 [F1]=3 [F1-M]=5 [FA]=2 [B1-C]=10)
STATIC_CASES=81

# IMAGE_ASSUMED — the declared contract with the Hetzner image (ADR-327 amendment) AND the minimal
# fixture's install list: packages the template uses but never installs, and the users its rules or
# its egress set name that come from the base system. systemd-timesyncd is deliberately NOT here: the
# template installs it (FAULT-A).
IMAGE_ASSUMED=(ca-certificates curl openssh-server iproute2)
IMAGE_ASSUMED_USERS=(root _apt systemd-network)
MIN_PKGS=(systemd systemd-sysv dbus cloud-init python3 openssl "${IMAGE_ASSUMED[@]}")
# CLOUD_IMAGE_PKGS — from noble-server-cloudimg-amd64.manifest, serial 20261017 (664 packages),
# retrieved 2026-11-20: the manifest's packages the template depends on or that own a user, unit or
# conffile it touches. Never fetched at run time; a refresh is a reviewed edit of this array.
CLOUD_IMAGE_PKGS=(apt ca-certificates cloud-init curl iproute2 nftables openssh-server systemd systemd-resolved systemd-timesyncd)

# The expected stage literals. The terminal three are anchored on bastion-host-create.yml's
# birth-readiness interlock below, so one diff cannot rename a stage in the template and here at once.
ST_READY=fresh_boot_ready
ST_FATAL=fresh_boot_not_ready_
ST_COMPLETE=cloud_init_complete
HEALTHY_TRAIL=(runcmd_start egress_load "$ST_COMPLETE" "$ST_READY")
REBOOT_TRAIL=(runcmd_start kernel_reboot runcmd_start egress_load "$ST_COMPLETE" "$ST_READY")
DSN="https://pubkey123@o1.ingest.de.sentry.io/4242"   # bastion.test.sh's fixture DSN
INGEST=o1.ingest.de.sentry.io

# ── ANCHORS (template lines the mutation rows edit; see the header) ─────────────────────────────
A_M1_FROM='  - path: /etc/soleur/bastion-nftables.conf
'
A_M1_TO='  - path: /etc/nftables.conf
'
A_M2_FROM='apt:
  preserve_sources_list: true
'
A_F1M_FROM='      if [ "$STAGE" = egress_load ]; then nft flush ruleset 2>/dev/null || :; fi
'
A_FA_FROM='curl linux-image-generic nftables systemd-timesyncd;'
A_FA_TO='curl linux-image-generic nftables;'

# ── Instrument (ADR-193) ───────────────────────────────────────────────────────────────────────
cases=0; passes=0; fails=0; SKIPPED_ASSERTIONS=0
# The verdict reads FAILURES (append-only), never a counter sum (#7565).
FAILURES=()
# Text from outside this file (container output, labels carrying it) reaches the log only through
# gha_defuse: `%` escaped and `::` defused, so no line, indented or not, can become a workflow command.
gha_defuse() { sed -e 's/%/%25/g' -e 's/::/: :/g'; }
gha_esc() { # one workflow-command-safe line: no newline, `%` escaped, `::` defused, 300 bytes at most
  printf '%s' "$1" | tr '\r\n' '  ' | gha_defuse | head -c 300
}
pass() { passes=$((passes + 1)); printf '  ok   %s\n' "$1"; }
fail() { fails=$((fails + 1)); FAILURES+=("$1"); printf 'FAIL: %s\n' "$1" | gha_defuse >&2; [ -z "${2:-}" ] || printf '%s\n' "$2" | head -c 1500 | gha_defuse | sed 's/^/      /' >&2; }
chk() { # <label> <rc> [detail]: one assertion, rc 0 is a pass
  cases=$((cases + 1))
  if [ "$2" -eq 0 ]; then pass "$1"; else fail "$1" "${3:-}"; fi
}
# A red exit with no failed assertion (a refusal, the floor, a gate-event SKIP) stores its reason;
# annotate() turns it into the run's one ::error annotation (the log carries the same FAIL line).
VERDICT_REASON=""
die_verdict() { VERDICT_REASON="$1"; printf 'bastion-runcmd-rehearsal: FAIL (%s)\n' "$1" >&2; exit 1; }
annotate() { # <rc>: under GitHub Actions, one ::error per failed assertion, else one naming the verdict reason
  local p
  { [ "$1" -ne 0 ] && [ -n "${GITHUB_ACTIONS:-}" ]; } || return 0
  if [ "${#FAILURES[@]}" -gt 0 ]; then
    for p in "${FAILURES[@]}"; do printf '::error title=bastion-boot-rehearsal::%s\n' "$(gha_esc "$p")"; done
  else
    printf '::error title=bastion-boot-rehearsal::%s\n' "$(gha_esc "${VERDICT_REASON:-exit $1 with no named reason (read the HARNESS:, FATAL: or INSTRUMENT: line above)}")"
  fi
}
trap 'annotate $?' EXIT   # replaced by cleanup (which calls annotate) once the work dir exists
_st="$( (pass x >/dev/null; fail y 2>/dev/null; printf '%s %s %s' "$passes" "$fails" "${#FAILURES[@]}") )"
if [ "$_st" != "1 1 1" ]; then printf 'FAIL INSTRUMENT: pass()/fail() self-test read "%s", expected "1 1 1"\n' "$_st" >&2
  VERDICT_REASON="INSTRUMENT: pass()/fail() self-test"; exit 1; fi

# ── Subsets and CI refusals (AC8) ──────────────────────────────────────────────────────────────
# CI is CI or GITHUB_ACTIONS: a step env `CI: ''` must not switch every refusal off.
is_ci() { [ -n "${CI:-}" ] || [ -n "${GITHUB_ACTIONS:-}" ]; }
# Only this script sets the subset floor; an inherited value would replace MIN_CASES on a full run.
PARTIAL=""; BRH_PARTIAL_MIN=""
if is_ci; then
  for v in BRH_ROWS BRH_STATIC_ONLY BRH_ARCHIVE_PIN; do
    if [ -n "${!v:-}" ]; then printf 'BRH_SUBSET_REFUSED: %s is set under CI; a partial or pinned run can never be read as proof\n' "$v" >&2
      die_verdict "BRH_SUBSET_REFUSED: $v under CI"; fi
  done
fi
# The refusal self-test below re-runs this file as a child with this set: a child that got past the
# refusals stops here, so a broken refusal can never recurse into another full run.
if [ -n "${BRH_REFUSAL_PROBE:-}" ]; then printf 'BRH_REFUSAL_PROBE: not refused\n' >&2; exit 3; fi
SELECTED=("${ROWS[@]}")
if [ -n "${BRH_STATIC_ONLY:-}" ]; then SELECTED=(); PARTIAL="static only"
elif [ -n "${BRH_ROWS:-}" ]; then
  SELECTED=(); IFS=',' read -r -a _want <<<"$BRH_ROWS"
  for r in "${_want[@]}"; do
    [ -n "${ROW_BOOTS[$r]:-}" ] || { printf 'HARNESS: BRH_ROWS names unknown row %s (rows: %s)\n' "$r" "${ROWS[*]}" >&2; exit 2; }
    SELECTED+=("$r")
  done
  PARTIAL="rows ${SELECTED[*]}"
fi
selected() { local s; for s in "${SELECTED[@]}"; do [ "$s" = "$1" ] && return 0; done; return 1; }

# ── Preconditions (CTO Q7) ─────────────────────────────────────────────────────────────────────
absent() {
  if is_ci; then printf 'BRH_TOOL_ABSENT:%s\n' "$1" >&2; die_verdict "BRH_TOOL_ABSENT:$1 under CI"; fi
  printf 'SKIP (loud): bastion-runcmd-rehearsal: %s absent\n' "$1"; exit 0
}
for t in docker terraform python3 ssh-keygen openssl dash curl flock ip; do command -v "$t" >/dev/null 2>&1 || absent "$t"; done
docker info >/dev/null 2>&1 || absent "docker-daemon"
DASH="$(command -v dash)"
python3 -c 'import yaml' 2>/dev/null || absent "python3-yaml"
for f in "$TPL" "$EGRESS_SH" "$GD_SUITE" "$CREATE_WF" "$TRAIL_READER" "$APT_LIB"; do
  [ -s "$f" ] || { printf 'HARNESS: missing %s\n' "$f" >&2; exit 2; }
done
# shellcheck source=lib/apt-bounded.sh
. "$APT_LIB"
# Canonical fixture-dir guard, copied byte-for-byte (fixture-dir-operand-assert pins every copy); it
# shadows lib/apt-bounded.sh's identical copy.
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


# The pinned base image, read from the git-data suite (provision-unit shape); rule-audit.yml watches it.
UBUNTU_BASE="$(sed -nE "s/^UBUNTU_BASE='(ubuntu:24\.04@sha256:[0-9a-f]{64})'\$/\1/p" "$GD_SUITE" 2>/dev/null | head -1)"
if [ -z "$UBUNTU_BASE" ]; then chk "pin: UBUNTU_BASE readable from git-data-runcmd-rehearsal.test.sh" 1 "no tag@sha256 pin found"
  die_verdict "no UBUNTU_BASE pin"; fi
chk "pin: UBUNTU_BASE read from git-data-runcmd-rehearsal.test.sh ($UBUNTU_BASE)" 0

# ── Work dir and the one EXIT trap ─────────────────────────────────────────────────────────────
umask 077
# The work dir and the stale-dir sweep share ONE base, so kept evidence outlives a session-root
# cleanup and the sweep sees every dir this suite made (git-data-runcmd-rehearsal's shape).
WORK_BASE="${SOLEUR_SCRATCH_BASE:-$TMPDIR}"
WORK="$(mktemp -d -p "$WORK_BASE" brh.XXXXXX)" || { printf 'HARNESS: mktemp failed under %s\n' "$WORK_BASE" >&2; exit 2; }
assert_fixture_dir "$WORK"
declare -A WPID=()
cleanup() {
  local rc=$? p ids keep="${BRH_KEEP_TMP:-}"
  for p in "${WPID[@]}"; do kill "$p" 2>/dev/null; done
  annotate "$rc"
  ids="$(docker ps -aq --filter "name=brh-$$-" 2>/dev/null)"
  # shellcheck disable=SC2086  # one container id per word
  [ -z "$ids" ] || docker rm -f $ids >/dev/null 2>&1
  docker network ls -q --filter "name=brh-$$-" 2>/dev/null | while read -r n; do docker network rm "$n" >/dev/null 2>&1; done
  if [ "$rc" -ne 0 ] || [ -n "$keep" ]; then
    assert_fixture_dir "$WORK"
    find "$WORK" -type f \( -name '*.key' -o -name '*.pem' -o -name 'user-data' -o -name 'hk' \) -delete 2>/dev/null
    grep -rlZ 'PRIVATE KEY' "$WORK" 2>/dev/null | xargs -0 rm -f 2>/dev/null
    printf 'bastion-runcmd-rehearsal: evidence kept at %s (private keys and seed user-data removed)\n' "$WORK" >&2
  else
    assert_fixture_dir "$WORK"
    rm -rf "$WORK"
  fi
  exit "$rc"
}
trap cleanup EXIT
printf 'NOTICE: bastion-runcmd-rehearsal starts privileged systemd containers\n'

# ── Stale-run reaper (resources of runs killed without their EXIT trap) ────────────────────────
LOCKF="${TMPDIR}/brh-subnets.lock"
pid_alive() { kill -0 "$1" 2>/dev/null || [ -d "/proc/$1" ]; }   # EPERM (another user's pid) is alive
stale_owner() { # <docker name> -> rc 0 when it is brh-<pid>-* and <pid> is not alive (never this run's)
  local p
  case "$1" in brh-[0-9]*-*) p="${1#brh-}"; p="${p%%-*}" ;; *) return 1 ;; esac
  case "$p" in *[!0-9]*|"") return 1 ;; esac
  [ "$p" != "$$" ] && ! pid_alive "$p"
}
old_enough() { # <epoch seconds | RFC 3339> -> rc 0 when over an hour old (a pid from another pid namespace can look dead)
  local c
  case "$1" in
    "") return 1 ;;
    *[!0-9]*) c="$(date -d "$1" +%s 2>/dev/null)" || return 1 ;;
    *) c="$1" ;;
  esac
  [ $(( $(date +%s) - c )) -ge 3600 ]
}
reap_stale() {
  local lk n c
  assert_fixture_dir "$LOCKF"
  exec {lk}>>"$LOCKF"
  flock -w 60 "$lk" || { printf 'BRH_SUBNET_BUSY: could not take %s for the stale-run reaper\n' "$LOCKF" >&2; exec {lk}>&-; return 0; }
  for n in $(docker ps -a --format '{{.Names}}' --filter name=brh- 2>/dev/null); do
    stale_owner "$n" || continue
    c="$(docker inspect -f '{{.Created}}' "$n" 2>/dev/null)"; old_enough "$c" || continue   # RFC 3339
    docker rm -f "$n" >/dev/null 2>&1 && printf 'reaped stale container %s\n' "$n"
  done
  for n in $(docker network ls --format '{{.Name}}' --filter name=brh- 2>/dev/null); do
    stale_owner "$n" || continue
    c="$(docker network inspect -f '{{.Created.Unix}}' "$n" 2>/dev/null)"; old_enough "$c" || continue   # epoch: date -d rejects the Go time form
    docker network rm "$n" >/dev/null 2>&1 && printf 'reaped stale network %s\n' "$n"
  done
  flock -u "$lk"; exec {lk}>&-
  assert_fixture_dir "$WORK_BASE"
  find "$WORK_BASE" -maxdepth 1 -type d -name 'brh.*' -user "$(id -u)" -mmin +720 \
    -exec rm -rf {} + 2>/dev/null || true
}
reap_stale
_dead="$(sh -c 'echo $$')"
_sr=1; if ! stale_owner "brh-$$-B1" && stale_owner "brh-$_dead-B1" && ! stale_owner "brh-x$_dead-B1" && ! stale_owner "zot-$_dead-B1" \
          && ! stale_owner "brh-1-B1"; then _sr=0; fi
chk "reaper: a dead pid's brh-<pid>-* is stale; this run's, pid 1's, and other names are not" "$_sr" "dead=$_dead"
# old_enough reads the two shapes reap_stale hands it: a network's {{.Created.Unix}} epoch and a
# container's RFC 3339 {{.Created}} (a format it cannot parse would leave every leaked network forever).
_now="$(date +%s)"; _oe() { if old_enough "$1"; then printf y; else printf n; fi; }
_r="$(_oe "$((_now - 7200))")$(_oe "$_now")$(_oe "")"
chk "reaper: old_enough on a network's {{.Created.Unix}} epoch (2 h old yes, now no, empty no)" "$([ "$_r" = ynn ]; echo $?)" "got $_r"
_r="$(_oe "$(date -u -d "@$((_now - 7200))" +%Y-%m-%dT%H:%M:%S.123456789Z)")$(_oe "$(date -u -d "@$_now" +%Y-%m-%dT%H:%M:%S.123456789Z)")"
chk "reaper: old_enough on a container's RFC 3339 {{.Created}} (2 h old yes, now no)" "$([ "$_r" = yn ]; echo $?)" "got $_r"

# ── Static checks over this file and the anchors (seconds) ─────────────────────────────────────
# Host containment (CTO Q21): no docker run/create in this file may share a host namespace or bind
# the host root. The pattern is assembled from pieces so this line is not itself a match.
ARGV_BAD_RE='--(network|net|pid|ipc|uts)[= ]'"ho""st"'|(-v|--volume)[= ]"?/:'
argv_scan() { # <file> -> rc 1 (and the offending statements) when any docker run/create breaks containment
  local bad
  bad="$(sed 's/^[[:space:]]*#.*$//' "$1" | sed -e ':a' -e '/\\$/{N;s/\\\n/ /;ba' -e '}' \
    | grep -E 'docker[[:space:]]+(run|create)[[:space:]]' | grep -E -- "$ARGV_BAD_RE")"
  [ -z "$bad" ] && return 0
  printf '%s\n' "$bad" | cut -c1-200 | head -3; return 1
}
_out="$(argv_scan "$SELF")"; chk "containment: no docker run/create here shares a host namespace or binds /" $? "$_out"
mutate() { # <row> <src> <dst> <from> <to>: exact single occurrence, or BRH_ANCHOR_MISS
  python3 - "$@" <<'PY'
import sys
row, src, dst, a, b = sys.argv[1:]
t = open(src).read()
if t.count(a) != 1:
    print("BRH_ANCHOR_MISS:%s anchor=%r (%d occurrences): the template line was reworded (update the anchor in bastion-runcmd-rehearsal.test.sh) or the fix this row guards was reverted" % (row, a[:100], t.count(a)))
    sys.exit(1)
open(dst, "w").write(t.replace(a, b))
PY
}
_from="--cgroup-parent=docker.slice -e contain""er=docker"
if _m="$(mutate static "$SELF" "$WORK/self-mut.sh" "$_from" "$_from --network ho""st")"; then
  argv_scan "$WORK/self-mut.sh" >/dev/null; _r=$?
  chk "containment control: a boot docker create given the host network is caught (Guard 1 row 13)" "$([ "$_r" -eq 1 ]; echo $?)" "scan rc=$_r"
else chk "containment control: a boot docker create given the host network is caught (Guard 1 row 13)" 1 "$_m"; fi
_lits="$(sed -nE 's/^[[:space:]]*for lit in ([a-z_ ]+); do.*/\1/p' "$CREATE_WF" | head -1)"
_anchor_rc=1
if [ "$_lits" = "$ST_READY $ST_FATAL $ST_COMPLETE" ] && grep -qF "\"$ST_READY\"" "$TRAIL_READER"; then _anchor_rc=0; fi
chk "anchor: the stage literals equal bastion-host-create.yml's interlock list and the strict reader's" "$_anchor_rc" "interlock list='$_lits'"

# ── Fixtures (synthesized per run; cq-test-fixtures-synthesized-only) ──────────────────────────
mkfixtures() {
  assert_fixture_dir "$WORK"
  mkdir -p "$WORK/k" "$WORK/pki" "$WORK/pki-srv" "$WORK/tf" "$WORK/rows" "$WORK/static" "$WORK/recipe" "$WORK/fake"
  ssh-keygen -q -t ed25519 -N '' -C fixture -f "$WORK/k/hk" || return 1
  openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -days 1 \
    -keyout "$WORK/pki/ca.key" -out "$WORK/pki/ca.crt" -subj '/CN=brh fixture CA' \
    -addext 'basicConstraints=critical,CA:TRUE,pathlen:0' -addext 'keyUsage=critical,keyCertSign,cRLSign' \
    -addext "nameConstraints=critical,permitted;DNS:$INGEST,permitted;DNS:decoy.example" >/dev/null 2>&1 || return 1
  openssl req -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -keyout "$WORK/pki-srv/srv.key" \
    -out "$WORK/pki/srv.csr" -subj "/CN=$INGEST" >/dev/null 2>&1 || return 1
  printf 'subjectAltName=DNS:%s,DNS:decoy.example\nextendedKeyUsage=serverAuth\nbasicConstraints=CA:FALSE\n' "$INGEST" > "$WORK/pki/srv.ext"
  openssl x509 -req -in "$WORK/pki/srv.csr" -CA "$WORK/pki/ca.crt" -CAkey "$WORK/pki/ca.key" -CAcreateserial \
    -days 1 -extfile "$WORK/pki/srv.ext" -out "$WORK/pki-srv/srv.crt" >/dev/null 2>&1 || return 1
  # docker cp keeps the mode, and apt's _apt sandbox user must read the bundle built from this CA.
  chmod 0644 "$WORK/pki/ca.crt"
}
mkfixtures || { printf 'HARNESS: fixture key/certificate generation failed\n' >&2; exit 2; }

# The predicates, the stub and the image recipe. Written once; the recipe text feeds the image tag.
write_helpers() {
  assert_fixture_dir "$WORK"
  cat > "$WORK/pred.py" <<'PY'
import difflib, json, re, sys, yaml
MSG = "soleur-cloud-init boot stage"
REASON = re.compile(r"\[bastion-egress\] FAIL:|: Error: ")

def load(path):
    try:
        lines = open(path, encoding="utf-8", errors="replace").read().splitlines()
    except OSError:
        return None, "capture missing"
    out = []
    for i, l in enumerate(lines, 1):
        if l.strip():
            try:
                out.append(json.loads(l))
            except ValueError:
                return None, "capture line %d is not JSON" % i
    return out, None

def events(path, src, hostid, port=None):
    """Every request from the bastion must be a well-formed accepted event; never stops early."""
    recs, err = load(path)
    if err:
        return None, err
    mine = [r for r in recs if r.get("src") == src]
    if not mine:
        return None, "no request from %s in the capture (%d lines in all)" % (src, len(recs))
    ev, bad = [], []
    for n, r in enumerate(mine, 1):
        why = []
        if r.get("verdict") != "accepted":
            why.append("stub verdict %s/%s" % (r.get("verdict"), r.get("why")))
        if r.get("method") != "POST":
            why.append("method %s" % r.get("method"))
        if r.get("path") != "/api/4242/store/":
            why.append("path %r" % r.get("path"))
        if r.get("key") != "pubkey123":
            why.append("sentry_key %r" % r.get("key"))
        if port is not None and r.get("port") != port:
            why.append("port %s" % r.get("port"))
        b = r.get("body")
        if not isinstance(b, dict):
            why.append("body is not JSON")
            t = {}
        else:
            t = b.get("tags") or {}
            if b.get("message") != MSG:
                why.append("message %r" % b.get("message"))
            if b.get("level") not in ("info", "fatal"):
                why.append("level %r" % b.get("level"))
            if not t.get("stage"):
                why.append("no stage tag")
            if t.get("host_name") != "soleur-bastion":
                why.append("host_name %r" % t.get("host_name"))
            if t.get("host_id") != hostid:
                why.append("host_id %r" % t.get("host_id"))
        if why:
            bad.append("request %d: %s" % (n, "; ".join(why)))
        else:
            ev.append((t["stage"], b["level"], t.get("detail", "")))
    if bad:
        return None, " | ".join(bad[:4])
    return ev, None

def detail_ok(d, has):
    if not REASON.search(d or ""):
        return "detail names no reason (only systemd boilerplate?): %r" % d
    if has and has not in d:
        return "detail lacks %r: %r" % (has, d)
    return None

def die(msg):
    print(msg); sys.exit(1)

def main(a):
    cmd = a[0]
    if cmd in ("trail", "fatal", "nofatal_last", "absent"):
        port = None
        rest = a[1:]
        if rest and rest[0] == "--port":
            port = int(rest[1]); rest = rest[2:]
        cap, src, hostid = rest[0], rest[1], rest[2]
        ev, err = events(cap, src, hostid, port)
        if err:
            die(err)
        stages = [e[0] for e in ev]
        fatals = [e for e in ev if e[1] == "fatal"]
        if cmd == "trail":
            want, counts = [], {}
            for x in rest[3:]:
                if x.startswith("count:"):
                    s, n = x[6:].split("=")
                    counts[s] = int(n)
                else:
                    want.append(x)
            if fatals:
                die("fatal event(s): %s detail=%r" % (fatals[0][0], fatals[0][2]))
            i = 0
            for s in stages:
                if i < len(want) and s == want[i]:
                    i += 1
            if i < len(want):
                die("trail %s lacks %s in order (wanted %s)" % (stages, want[i], want))
            if stages[-1] != want[-1]:
                die("the last event is %s, not %s" % (stages[-1], want[-1]))
            for s, n in counts.items():
                if stages.count(s) != n:
                    die("%s occurs %d times, wanted %d (trail %s)" % (s, stages.count(s), n, stages))
            print("trail ok: %s" % stages)
            return
        if cmd == "fatal":
            allowed = ["fresh_boot_not_ready_" + s for s in rest[3].split(",")]
            has = rest[4] if len(rest) > 4 else ""
            if not fatals:
                die("no fatal event (trail %s)" % stages)
            off = [f for f in fatals if f[0] not in allowed]
            if off:
                die("fatal at %s, wanted %s" % (off[0][0], allowed))
            if "fresh_boot_ready" in stages:
                die("fresh_boot_ready also sent (trail %s)" % stages)
            if has:
                e = detail_ok(fatals[-1][2], has)
                if e:
                    die(e)
            print("fatal ok: %s detail=%r" % (fatals[-1][0], fatals[-1][2]))
            return
        if cmd == "nofatal_last":
            if fatals:
                die("a fatal reached the stub: %s" % (fatals[0],))
            if stages[-1] != rest[3]:
                die("the capture ends at %s, not %s (trail %s)" % (stages[-1], rest[3], stages))
            print("no fatal; ends at %s" % stages[-1])
            return
        if cmd == "absent":
            hit = [s for s in rest[3:] if s in stages]
            if hit:
                die("present: %s (trail %s)" % (hit, stages))
            print("absent: %s" % rest[3:])
            return
    if cmd == "detail":
        e = detail_ok(a[1], a[2] if len(a) > 2 else "")
        if e:
            die(e)
        return
    if cmd == "probe":
        recs, err = load(a[1])
        if err:
            die(err)
        hit = [r for r in recs if r.get("src") == a[2] and r.get("path") == a[3]]
        if not hit:
            die("no request for %s from %s" % (a[3], a[2]))
        print("seen %d" % len(hit))
        return
    if cmd == "selftest":
        recs, err = load(a[1])
        if err:
            die(err)
        nb = [r for r in recs if r.get("src") != a[2] and r.get("port") == 443]
        rej = sorted(r.get("why") for r in nb if r.get("verdict") == "rejected")
        acc = [r for r in nb if r.get("verdict") == "accepted"]
        if rej != ["key", "method", "no_auth", "path"] or len(acc) != 1 or acc[0].get("body") != {"brh_selftest": 1}:
            die("neighbour requests: rejected=%s accepted=%d" % (rej, len(acc)))
        print("selftest ok")
        return
    if cmd == "last":
        recs, _ = load(a[1])
        mine = [r for r in (recs or []) if r.get("src") == a[2] and isinstance(r.get("body"), dict)]
        if not mine:
            print("last_stage=none (no event from the bastion)")
            return
        b = mine[-1]["body"]; t = b.get("tags") or {}
        fat = [m["body"] for m in mine if m["body"].get("level") == "fatal"]
        s = "last_stage=%s level=%s" % (t.get("stage"), b.get("level"))
        if fat:
            s += " fatal=%s detail=%r" % ((fat[-1].get("tags") or {}).get("stage"), (fat[-1].get("tags") or {}).get("detail"))
        print(s)
        return
    if cmd == "fatalstage":
        recs, _ = load(a[1])
        fat = [r["body"] for r in (recs or []) if r.get("src") == a[2] and isinstance(r.get("body"), dict) and r["body"].get("level") == "fatal"]
        if fat:
            print(((fat[-1].get("tags") or {}).get("stage") or "").replace("fresh_boot_not_ready_", ""))
        return
    if cmd in ("status", "status_ok", "datasource"):
        try:
            d = json.load(open(a[1]))
        except (OSError, ValueError):
            d = {}
        # `status` is the lifecycle (running/done/error); `extended_status` adds "degraded" for
        # recoverable warnings even WHILE running (the fixture lacks lsb_release), so it never ends a wait.
        s = str(d.get("status", "unknown"))
        if cmd == "status":
            print(s); return
        if cmd == "status_ok":
            if s != "done" or d.get("errors"):
                die("status=%s errors=%s" % (s, d.get("errors")))
            print("status done, errors []"); return
        blob = (str(d.get("datasource", "")) + " " + str(d.get("detail", ""))).lower()
        if "nocloud" not in blob:
            die("datasource %r detail %r" % (d.get("datasource"), d.get("detail")))
        print("datasource NoCloud"); return
    if cmd in ("sources_https", "sources_http"):
        t = open(a[1], errors="replace").read()
        body, _, rest = t.partition("--- d\n")
        listing, _, size = rest.partition("--- l\n")
        uris = [l.split(":", 1)[1].strip() for l in body.splitlines() if l.startswith("URIs:")]
        if cmd == "sources_http":
            if not uris or not all(u.startswith("http://") for u in uris):
                die("URIs %s are not all http://" % uris)
            print("rewritten to %s" % uris); return
        want = ["https://archive.ubuntu.com/ubuntu", "https://security.ubuntu.com/ubuntu"]
        if uris != want or listing.split() != ["ubuntu.sources"] or size.strip() != "0":
            die("URIs=%s sources.list.d=%s sources.list bytes=%s" % (uris, listing.split(), size.strip()))
        print("https sources only"); return
    if cmd == "extract":
        doc = yaml.safe_load(open(a[1]))
        items = [i for i in doc.get("runcmd", []) if isinstance(i, str)]
        out = a[2]
        open(out + "/joined.sh", "w").write("#!/bin/sh\n" + "\n".join(items) + "\n")
        open(out + "/joined-red.sh", "w").write("#!/bin/sh\n" + "\n".join(items) + "\nfi\n")
        fn, p7 = [], ""
        for it in items:
            ls = it.splitlines()
            for i, l in enumerate(ls):
                if l.startswith("_egress_why() {"):
                    for m in ls[i:]:
                        fn.append(m)
                        if m == "}":
                            break
                if l.startswith("i=0; until ip -4 -o addr show"):
                    p7 = l
        if fn and fn[-1] == "}":
            open(out + "/egress_why.sh", "w").write("\n".join(fn) + "\n")
        if p7:
            open(out + "/p7.sh", "w").write("D=/var/lib/brh/p7.detail\n" + p7 + "\n")
        return
    if cmd == "onelinediff":
        x = open(a[1]).read().splitlines(); y = open(a[2]).read().splitlines()
        d = [l for l in difflib.ndiff(x, y) if l[:2] in ("- ", "+ ")]
        if len(d) != 1 or not d[0].startswith("- ") or a[3] not in d[0]:
            die("diff is %s" % d[:4])
        print("exactly one deleted line: %s" % d[0][2:].strip()); return
    die("unknown predicate %s" % cmd)

main(sys.argv[1:])
PY
  cat > "$WORK/stub.py" <<'PY'
import http.server, json, re, ssl, sys, threading, time
OUT = sys.argv[1]
LOCK = threading.Lock()
def rec(d):
    with LOCK:
        with open(OUT + "/capture.log", "a") as f:
            f.write(json.dumps(d, sort_keys=True) + "\n"); f.flush()
class H(http.server.BaseHTTPRequestHandler):
    def _base(self, m):
        return {"t": time.time(), "port": self.server.server_port, "src": self.client_address[0], "method": m, "path": self.path}
    def _done(self, code, d):
        rec(d)
        self.send_response(code); self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", "2"); self.end_headers(); self.wfile.write(b"{}")
    def do_POST(self):
        d = self._base("POST")
        raw = self.rfile.read(int(self.headers.get("Content-Length") or 0)).decode("utf-8", "replace")
        auth = self.headers.get("X-Sentry-Auth") or ""
        m = re.search(r"sentry_key=([^,\s]+)", auth); d["key"] = m.group(1) if m else None
        try:
            d["body"] = json.loads(raw)
        except ValueError:
            d["body"] = None; d["raw"] = raw[:400]
        why = None
        if self.path != "/api/4242/store/": why = "path"
        elif not auth: why = "no_auth"
        elif d["key"] != "pubkey123": why = "key"
        elif d["body"] is None: why = "body"
        d["verdict"] = "rejected" if why else "accepted"
        if why: d["why"] = why
        self._done(400 if why else 200, d)
    def do_GET(self):
        d = self._base("GET"); d["verdict"] = "rejected"; d["why"] = "method"; self._done(405, d)
    def log_message(self, *a): pass
def serve(port, tls):
    s = http.server.ThreadingHTTPServer(("0.0.0.0", port), H)
    if tls:
        c = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER); c.load_cert_chain("/pki/srv.crt", "/pki/srv.key")
        s.socket = c.wrap_socket(s.socket, server_side=True)
    return s
a, b = serve(80, False), serve(443, True)
threading.Thread(target=a.serve_forever, daemon=True).start()
open(OUT + "/stub.ready", "w").write("1")
b.serve_forever()
PY
  cat > "$WORK/neighbour.sh" <<'SH'
c() { curl -sS -o /dev/null -w '%{http_code}' --cacert /brh/ca.crt --connect-timeout 3 -m 6 "$@" 2>/dev/null || :; }
A='X-Sentry-Auth: Sentry sentry_version=7, sentry_key=pubkey123'
U=https://o1.ingest.de.sentry.io
echo "wrongpath $(c -X POST -H "$A" -d '{}' "$U/api/9999/store/")"
echo "noauth $(c -X POST -d '{}' "$U/api/4242/store/")"
echo "wrongkey $(c -X POST -H 'X-Sentry-Auth: Sentry sentry_version=7, sentry_key=wrong' -d '{}' "$U/api/4242/store/")"
echo "get $(c "$U/api/4242/store/")"
echo "good $(c -X POST -H "$A" -d '{"brh_selftest":1}' "$U/api/4242/store/")"
if [ -n "${BRH_LIVE:-}" ]; then
  echo "live80 $(c http://o1.ingest.de.sentry.io:80/brh-live)"
  echo "livedecoy $(c https://decoy.example/brh-live)"
fi
SH
  cat > "$WORK/recipe/debs.sh" <<'SH'
set -e
mkdir -p /tmp/brh-debs
for p in linux-image-0.0.0-1-generic linux-image-generic; do
  d=/tmp/brh-debs/$p; mkdir -p "$d/DEBIAN"
  if [ "$p" = linux-image-generic ]; then v=999:0.0.0-1; dep='Depends: linux-image-0.0.0-1-generic'; else v=0.0.0-1; dep=''; fi
  { printf 'Package: %s\nVersion: %s\nArchitecture: all\nMaintainer: brh fixture <brh@invalid>\n' "$p" "$v"
    [ -z "$dep" ] || printf '%s\n' "$dep"
    printf 'Description: bastion rehearsal fixture (not a kernel)\n'; } > "$d/DEBIAN/control"
  dpkg-deb --build "$d" "/tmp/brh-debs/$p.deb" >/dev/null
done
SH
  cat > "$WORK/recipe/post.sh" <<'SH'
set -e
mkdir -p /usr/local/sbin /var/lib/brh /etc/brh /etc/systemd/journald.conf.d /var/log/journal
cat > /usr/local/sbin/uname <<'U'
#!/bin/sh
# brh shim: only `uname -r` is answered from the row's mode; everything else is the real uname.
if [ "$#" -eq 1 ] && [ "$1" = -r ]; then
  case "$(cat /etc/brh/uname-mode 2>/dev/null)" in
    settled) echo 0.0.0-1-generic; exit 0 ;;
    reboot) if [ -e /var/lib/soleur/kernel-settle ]; then echo 0.0.0-1-generic; else echo 0.0.0-0-generic; fi; exit 0 ;;
  esac
fi
exec /usr/bin/uname "$@"
U
cat > /usr/local/sbin/reboot <<'R'
#!/bin/sh
# brh shim: record the reboot, then power the container off; the harness `docker start`s boot two.
printf '%s reboot %s\n' "$(date +%s)" "$*" >> /var/lib/brh/reboot.log
exec /usr/bin/systemctl poweroff
R
chmod 0755 /usr/local/sbin/uname /usr/local/sbin/reboot
printf '[Journal]\nReadKMsg=no\n' > /etc/systemd/journald.conf.d/brh.conf
systemctl mask systemd-sysctl.service systemd-binfmt.service systemd-modules-load.service systemd-udevd.service systemd-udev-trigger.service getty@.service console-getty.service getty.target
rm -rf /var/lib/apt/lists/* /etc/ssh/ssh_host_*
cloud-init --version
SH
  # BRH_FAKE_HANG names the reads that hang (sync reason unit show-nft show-egress show-st).
  cat > "$WORK/fake/journalctl" <<'SH'
#!/bin/sh
printf 'journalctl %s\n' "$*" >> "$BRH_FAKE_LOG"
hang() { case " ${BRH_FAKE_HANG:-} " in *" $1 "*) exec sleep 30 ;; esac; }
case "$*" in
  "--sync") hang sync; exit 0 ;;
  "-b -u nftables.service -u bastion-egress.service --no-pager -o cat") hang reason; cat "$BRH_FAKE_JOURNAL"; exit 0 ;;
  "-b _SYSTEMD_UNIT=bastion-egress.service --no-pager -o cat") hang unit; cat "${BRH_FAKE_UNITOUT:-/dev/null}"; exit 0 ;;
esac
exit 3
SH
  cat > "$WORK/fake/systemctl" <<'SH'
#!/bin/sh
hang() { case " ${BRH_FAKE_HANG:-} " in *" $1 "*) exec sleep 30 ;; esac; }
case "$*" in
  "show -p Result --value nftables.service") hang show-nft; echo "$BRH_FAKE_NFT" ;;
  "show -p Result --value bastion-egress.service") hang show-egress; echo "$BRH_FAKE_EGRESS" ;;
  "show -p ExecMainStatus --value bastion-egress.service") hang show-st; echo "$BRH_FAKE_ST" ;;
  *) printf 'BADARGV systemctl %s\n' "$*" >> "$BRH_FAKE_LOG"; exit 3 ;;
esac
SH
  chmod 0700 "$WORK/fake/journalctl" "$WORK/fake/systemctl"
}
write_helpers
PRED="$WORK/pred.py"
pred() { python3 "$PRED" "$@" 2>&1; }

# ── Row verdict helpers (defined before any boot so the instrument self-test below drives them) ─
RB=()
rk() { # <label> <rc> [detail]: a row assertion, buffered until the row is classified (ADR-188)
  if [ "$2" -eq 0 ]; then RB+=("P${TAB}$1${TAB}"); else RB+=("F${TAB}$1${TAB}$(printf '%s' "${3:-}" | tr '\t\n' '  ' | head -c 900)"); fi
}
rf() { cat "$RD/f/$1" 2>/dev/null; }
rc_is() { [ "$(rf "$1")" = "$2" ]; }
row_stage() { # the stage a failed row died at: its fatal, else the apt process alive at the cap
  local s
  s="$(python3 "$PRED" fatalstage "$RD/capture-boot.log" "$SRC" 2>/dev/null)"
  if [ -z "$s" ] && [ "$(rf end)" = cap ]; then
    if grep -q ' update' "$RD/f/boot.cap-apt" "$RD/f/boot1.cap-apt" "$RD/f/boot2.cap-apt" 2>/dev/null; then s=apt_update
    elif grep -q ' install' "$RD/f/boot.cap-apt" "$RD/f/boot1.cap-apt" "$RD/f/boot2.cap-apt" 2>/dev/null; then s=apt_install; fi
  fi
  printf '%s' "$s"
}
row_brief() {
  local b
  b="$(python3 "$PRED" last "$RD/capture-boot.log" "$SRC" 2>/dev/null) end=$(rf end) elapsed=$(rf elapsed)s"
  [ -f "$RD/f/harness" ] && b="HARNESS: $(rf harness); $b"
  [ -f "$RD/f/deadline" ] && b="$(rf deadline); $b"
  [ "$(rf end)" = cap ] && b="BRH_BOOT_CAP:$ROW stage=$(row_stage) elapsed=$(rf elapsed); $b"
  printf '%s' "$b"
}
row_ctx() {
  printf '      %s journal reason: %s\n' "$ROW" "$(grep -aE '\[bastion-egress\] FAIL:|: Error: ' "$RD/journal.txt" 2>/dev/null | tail -n 3 | tr '\n' ' ' | head -c 400)"
  printf '      %s last 20 lines of cloud-init-output.log:\n' "$ROW"
  tail -n 20 "$RD/cloud-init-output.log" 2>/dev/null | sed -e 's/::/: :/g' -e 's/^/        | /'
}
SKIPPED_ROWS=(); ROWS_BOOTED=0; ROWS_SKIPPED_UNBOOTED=0
flush_row() {
  local n="${#RB[@]}" want="${ROW_CASES[$ROW]}" nf=0 e st lbl det brief stg
  for e in "${RB[@]}"; do [ "${e%%"$TAB"*}" = F ] && nf=$((nf + 1)); done
  if [ "$n" -ne "$want" ]; then chk "$ROW: the row made $n assertions, ROW_CASES says $want" 1; fi
  if [ "$nf" -gt 0 ] && grep -q 'Hash Sum mismatch' "$RD/cloud-init-output.log" 2>/dev/null; then
    chk "BRH_APT_MIRROR_INCONSISTENT:$ROW (apt Hash Sum mismatch; re-run, never a skip)" 1
  elif [ "$nf" -gt 0 ]; then
    stg="$(row_stage)"
    # M1's designed fatal is apt_install: it is an environment decline only when the conffile marker
    # (the property M1 exists for) is absent. Measured under an archive outage (Test Scenario 4):
    # `apt-get update` exits 0 on a dead mirror, so rows die at apt_install; the cloud-faithful image
    # already carries every package, so B1-C dies at apt_path (the M2 widening, same reason).
    [ "$ROW" = M1 ] && grep -q 'conffile prompt' "$RD/cloud-init-output.log" 2>/dev/null && stg=designed
    case "$stg" in
      apt_update|apt_install|apt_path)
        reprobe
        if [ "$PROBE_OK" -eq 0 ] || [ "$REPROBE_OK" -eq 0 ]; then
          cases=$((cases + n)); SKIPPED_ASSERTIONS=$((SKIPPED_ASSERTIONS + n)); SKIPPED_ROWS+=("$ROW")
          printf 'SKIP (loud): %s ADR-188: died at %s with the archive probe failing (first: %s; at classification: %s)\n' "$ROW" "$stg" "$PROBE_LINE" "$REPROBE_LINE"
          RB=(); return
        fi ;;
    esac
  fi
  brief="$(row_brief)"
  for e in "${RB[@]}"; do
    IFS="$TAB" read -r st lbl det <<<"$e"
    cases=$((cases + 1))
    if [ "$st" = P ]; then pass "$ROW: $lbl"; else fail "$ROW: $lbl [$brief]" "$det"; fi
  done
  [ "$nf" -eq 0 ] || row_ctx >&2
  RB=()
}
# Instrument self-test, part two: the verdict-owning helpers through their real dispatch (chk; rk ->
# flush_row), in a subshell, so this run's counters, ledger and case tally are untouched (the subshell
# is the unwind). Reported by printf + exit, never by the helpers under test.
_st="$( (cases=0; passes=0; fails=0; SKIPPED_ASSERTIONS=0; FAILURES=(); RB=(); SKIPPED_ROWS=()
  ROW=_st; ROW_CASES[_st]=2; RD="$WORK/st-none"; SRC=198.18.0.10
  chk st-a 0 >/dev/null 2>&1; chk st-b 1 >/dev/null 2>&1; rk st-p 0; rk st-f 1 d; flush_row >/dev/null 2>&1
  _f1="${FAILURES[1]:-}"
  printf '%s %s %s %s %s|%s|%s' "$cases" "$passes" "$fails" "$SKIPPED_ASSERTIONS" "${#RB[@]}" "${FAILURES[0]:-}" "${_f1%% \[*}") )"
if [ "$_st" != "4 2 2 0 0|st-b|_st: st-f" ]; then printf 'FAIL INSTRUMENT: chk/rk/flush_row self-test read "%s", expected "4 2 2 0 0|st-b|_st: st-f"\n' "$_st" >&2
  VERDICT_REASON="INSTRUMENT: chk/rk/flush_row self-test"; exit 1; fi

# ── SKIP on a gate event (CTO Q28) and the CI definition (B1), offline ─────────────────────────
# A SKIP exits 0 only on pull_request and push (they gate nothing; ADR-188); any other event, or
# none under CI, is a gate run and a SKIP there is a FAIL.
_skip_is_failure() { case "${GITHUB_EVENT_NAME-__unset__}" in __unset__) is_ci ;; pull_request|push) return 1 ;; *) return 0 ;; esac; }
_sk=""
for _c in "none|" "ci|CI=true" "gha|GITHUB_ACTIONS=true" "pr|GITHUB_EVENT_NAME=pull_request" "push|GITHUB_EVENT_NAME=push" \
          "dispatch|GITHUB_EVENT_NAME=workflow_dispatch" "schedule|GITHUB_EVENT_NAME=schedule" "empty|GITHUB_EVENT_NAME="; do
  _r="$( unset CI GITHUB_ACTIONS GITHUB_EVENT_NAME; [ -z "${_c#*|}" ] || export "${_c#*|}"; _skip_is_failure && echo yes || echo no )"
  _sk="$_sk ${_c%%|*}=$_r"
done
chk "verdict: SKIP fails on a gate event (dispatch, schedule, empty, or unset under CI) and not on pull_request/push" \
  "$([ "$_sk" = " none=no ci=yes gha=yes pr=no push=no dispatch=yes schedule=yes empty=yes" ]; echo $?)" "table:$_sk"
_o="$(env -i PATH="$PATH" HOME="${HOME:-/tmp}" CI= GITHUB_ACTIONS=true BRH_STATIC_ONLY=1 BRH_REFUSAL_PROBE=1 timeout 60 bash "$SELF" 2>&1)"; _r=$?
chk "CI refusals: GITHUB_ACTIONS=true with CI='' still refuses BRH_STATIC_ONLY (BRH_SUBSET_REFUSED, and its ::error annotation)" \
  "$([ "$_r" -eq 1 ] && printf '%s' "$_o" | grep -q '^BRH_SUBSET_REFUSED: BRH_STATIC_ONLY' \
    && printf '%s\n' "$_o" | grep -qx '::error title=bastion-boot-rehearsal::BRH_SUBSET_REFUSED: BRH_STATIC_ONLY under CI'; echo $?)" "rc=$_r $(head -c 400 <<<"$_o")"
# The annotation contract: a red exit with no failed assertion names its stored reason; failed
# assertions get one each; nothing on rc 0 or outside GitHub Actions; `::` and `%` are defused.
_r="$( GITHUB_ACTIONS=true; FAILURES=(); VERDICT_REASON='BRH_X: a::b 5%'; annotate 1; FAILURES=(f1 'f2::x'); annotate 1; annotate 0
  unset GITHUB_ACTIONS; annotate 1; fail 'l::m' 2>&1 >/dev/null )"
chk "verdict: annotate names the stored reason when no assertion failed, one ::error per failure otherwise; fail() defuses ::" \
  "$([ "$_r" = "$(printf '%s\n' '::error title=bastion-boot-rehearsal::BRH_X: a: :b 5%25' '::error title=bastion-boot-rehearsal::f1' \
    '::error title=bastion-boot-rehearsal::f2: :x' 'FAIL: l: :m')" ]; echo $?)" "got [$_r]"
# blk_extract <start-line prefix> <end-line ERE> <max lines>: this file's block from the ONE line that
# starts with the prefix through the first end line after it, or rc 1 and why. An eval'd block is never
# the rest of the file: a reworded end anchor or a block grown past the bound is a named red, no eval.
blk_extract() {
  BS="$1" BE="$2" BM="$3" awk '
    index($0, ENVIRON["BS"]) == 1 { starts++; if (!on && !done) on = 1 }
    on { buf = buf $0 "\n"; n++; if (n > 1 && $0 ~ ENVIRON["BE"]) { on = 0; done = 1 } }
    END {
      if (starts != 1) { printf "BLK_BAD: %d lines start with [%s] (expected 1)\n", starts, ENVIRON["BS"]; exit 1 }
      if (!done) { printf "BLK_BAD: no line matching /%s/ ends the block after [%s]\n", ENVIRON["BE"], ENVIRON["BS"]; exit 1 }
      if (n > ENVIRON["BM"] + 0) { printf "BLK_BAD: the block is %d lines, over its bound %d\n", n, ENVIRON["BM"]; exit 1 }
      printf "%s", buf
    }' "$SELF"
}
_lbl="floor: a full run ignores an inherited BRH_PARTIAL_MIN (the subset block resets it)"
if _blk="$(blk_extract '# ── Subsets and CI refusals' '^selected\(\) \{' 40)"; then
  _blk="$(printf '%s\n' "$_blk" | sed '$d')"
  _r="$( unset CI GITHUB_ACTIONS BRH_ROWS BRH_STATIC_ONLY BRH_ARCHIVE_PIN; BRH_PARTIAL_MIN=1; ROW_BOOTS=([B1]=1); ROWS=(B1)
    eval "$_blk" >/dev/null 2>&1; printf '[%s][%s]' "${PARTIAL-unset}" "${BRH_PARTIAL_MIN-unset}" )"
  chk "$_lbl" "$([ "$_r" = "[][]" ] && [ -n "$_blk" ]; echo $?)" "after the subset block: PARTIAL/BRH_PARTIAL_MIN=$_r"
else chk "$_lbl" 1 "$_blk"; fi
# CTO Q28 wiring: the verdict's own SKIP branch, run with one skipped row, reds on a dispatched gate run
# and stays SKIP (rc 0) on pull_request; pinning _skip_is_failure alone would pass an `if false` swap.
_lbl="verdict: the SKIP branch calls _skip_is_failure (workflow_dispatch: rc 1, BRH_SKIP_ON_GATE_EVENT; pull_request: rc 0, SKIP)"
if _vb="$(blk_extract 'if [ "${#SKIPPED_ROWS[@]}" -gt 0 ]; then' '^fi$' 20)"; then
  _vd="$( unset CI GITHUB_ACTIONS; export GITHUB_EVENT_NAME=workflow_dispatch; SKIPPED_ROWS=(B1); SELECTED=(B1); SKIPPED_ASSERTIONS=21
    eval "$_vb" 2>&1 )"; _vdr=$?
  _vp="$( unset CI GITHUB_ACTIONS; export GITHUB_EVENT_NAME=pull_request; SKIPPED_ROWS=(B1); SELECTED=(B1); SKIPPED_ASSERTIONS=21
    eval "$_vb" 2>&1 )"; _vpr=$?
  chk "$_lbl" "$([ "$_vdr" = 1 ] && printf '%s\n' "$_vd" | grep -qx 'BRH_SKIP_ON_GATE_EVENT: event=workflow_dispatch rows=B1' \
    && [ "$_vpr" = 0 ] && printf '%s\n' "$_vp" | grep -q '^bastion-runcmd-rehearsal: SKIP (1 of 1 boot rows skipped: B1;' \
    && ! printf '%s\n' "$_vp" | grep -q BRH_SKIP_ON_GATE_EVENT; echo $?)" "dispatch rc=$_vdr [$(head -c 300 <<<"$_vd")] pull_request rc=$_vpr [$(head -c 300 <<<"$_vp")]"
else chk "$_lbl" 1 "$_vb"; fi

# ── Offline predicate self-tests (no docker; run first) ────────────────────────────────────────
ev() { # <stage> <level> [host_name] [host_id] [path] [key] [detail] [port] [verdict] [message] [method]: one synthesized capture line
  python3 -c '
import json, sys
s, l, hn, hi, p, k, d, po, v, msg, m = sys.argv[1:]
print(json.dumps({"src": "198.18.0.10", "port": int(po), "method": m, "path": p, "key": k or None, "verdict": v,
  "body": {"message": msg, "level": l, "tags": {"stage": s, "host_id": hi, "detail": d, "host_name": hn}}}))' \
    "$1" "$2" "${3:-soleur-bastion}" "${4:-i-brh-T}" "${5:-/api/4242/store/}" "${6-pubkey123}" "${7:-}" "${8:-443}" "${9:-accepted}" \
    "${10:-soleur-cloud-init boot stage}" "${11:-POST}"
}
selftest_preds() {
  assert_fixture_dir "$WORK"
  local d="$WORK/pt" out rc
  mkdir -p "$d"
  { ev runcmd_start info; ev egress_load info; ev cloud_init_complete info; ev fresh_boot_ready info; } > "$d/healthy"
  { ev runcmd_start info; ev egress_load info; ev egress_load info; ev apt_path info; ev cloud_init_complete info; ev fresh_boot_ready info; } > "$d/extra"
  { ev runcmd_start info; ev kernel_reboot info; ev runcmd_start info; ev egress_load info; ev cloud_init_complete info; ev fresh_boot_ready info; } > "$d/b2"
  { cat "$d/healthy"; ev fresh_boot_not_ready_ssh_masked fatal; } > "$d/latefatal"
  { ev runcmd_start info; ev cloud_init_complete info; ev fresh_boot_ready info; } > "$d/noegress"
  { ev runcmd_start info; ev fresh_boot_ready info; ev egress_load info; ev cloud_init_complete info; } > "$d/order"
  { ev runcmd_start info; ev egress_load info soleur-web-1; ev cloud_init_complete info; ev fresh_boot_ready info; } > "$d/hostname"
  : > "$d/empty"
  { ev runcmd_start info; ev egress_load info soleur-bastion i-brh-T /api/9999/store/; ev cloud_init_complete info; ev fresh_boot_ready info; } > "$d/path"
  { ev runcmd_start info; ev egress_load info soleur-bastion i-brh-T /api/4242/store/ ""; ev cloud_init_complete info; ev fresh_boot_ready info; } > "$d/nokey"
  local T=(198.18.0.10 i-brh-T "${HEALTHY_TRAIL[@]}") B=(198.18.0.10 i-brh-T "${REBOOT_TRAIL[@]}" count:runcmd_start=2 count:kernel_reboot=1)
  out="$(pred trail "$d/healthy" "${T[@]}")"; chk "predicate must-PASS: the canonical healthy trail" $? "$out"
  out="$(pred trail "$d/extra" "${T[@]}")"; chk "predicate must-PASS: a healthy trail with extra info events between stages" $? "$out"
  out="$(pred trail "$d/b2" "${B[@]}")"; chk "predicate must-PASS: the B2 trail (kernel_reboot, two runcmd_start)" $? "$out"
  # Each must-RED row names the reason it must red for: pred.py exits 1 on an uncaught exception too,
  # so a bare rc 1 would pass a broken call.
  for c in "latefatal|fatal event(s): fresh_boot_not_ready_ssh_masked|fresh_boot_ready then a later fatal" \
           "noegress|lacks egress_load in order|a trail missing egress_load" \
           "order|lacks fresh_boot_ready in order|fresh_boot_ready before egress_load" \
           "hostname|host_name 'soleur-web-1'|a wrong host_name" \
           "empty|no request from 198.18.0.10 in the capture (0 lines in all)|an empty capture" \
           "path|path '/api/9999/store/'|a body posted to a wrong path" \
           "nokey|sentry_key None|a body without sentry_key=pubkey123"; do
    IFS='|' read -r _f _w _l <<<"$c"
    out="$(pred trail "$d/$_f" "${T[@]}")"; rc=$?
    chk "predicate must-RED: $_l" "$([ "$rc" -eq 1 ] && case "$out" in *"$_w"*) true ;; *) false ;; esac; echo $?)" "rc=$rc want [$_w] got $out"
  done
  # Every predicate a boot row's verdict rests on gets its own must-PASS/must-RED rows here: the live
  # rows are built to produce the expected verdict, so a neutered predicate would never red there.
  local FD='[bastion-egress] FAIL: lookup failed for nx-ingest.invalid (cloud-init); the loaded ruleset is unchanged'
  local TP=(198.18.0.10 i-brh-T "${HEALTHY_TRAIL[@]}") H=(198.18.0.10 i-brh-T)
  { ev runcmd_start info; ev egress_load info; ev fresh_boot_not_ready_egress_load fatal "" "" "" pubkey123 "$FD"; } > "$d/f1"
  { cat "$d/f1"; ev fresh_boot_ready info; } > "$d/fready"
  { ev runcmd_start info; ev egress_load info; } > "$d/endeg"
  { ev runcmd_start info; ev egress_load info "" "" "" pubkey123 "" 80; ev cloud_init_complete info; ev fresh_boot_ready info; } > "$d/port80"
  { ev runcmd_start info; ev egress_load info soleur-bastion i-brh-X; ev cloud_init_complete info; ev fresh_boot_ready info; } > "$d/hostid"
  { ev runcmd_start info; ev egress_load info "" "" "" pubkey123 "" 443 rejected; ev cloud_init_complete info; ev fresh_boot_ready info; } > "$d/rejected"
  { cat "$d/healthy"; ev egress_load info; } > "$d/infotail"
  { ev runcmd_start info; ev kernel_reboot info; ev runcmd_start info; ev runcmd_start info; ev egress_load info; ev cloud_init_complete info; ev fresh_boot_ready info; } > "$d/b2three"
  { ev runcmd_start info; ev egress_load warning; ev cloud_init_complete info; ev fresh_boot_ready info; } > "$d/level"
  { ev runcmd_start info; ev egress_load info "" "" "" pubkey123 "" 443 accepted "another message"; ev cloud_init_complete info; ev fresh_boot_ready info; } > "$d/message"
  { ev runcmd_start info; ev egress_load info "" "" "" pubkey123 "" 443 accepted "" GET; ev cloud_init_complete info; ev fresh_boot_ready info; } > "$d/method"
  out="$(pred fatal "$d/f1" "${H[@]}" egress_load 'lookup failed for nx-ingest.invalid')"; chk "predicate must-PASS: fatal at the wanted stage, detail naming the wanted reason" $? "$out"
  out="$(pred absent "$d/noegress" "${H[@]}" egress_load)"; chk "predicate must-PASS: absent on a trail without the stage" $? "$out"
  out="$(pred nofatal_last "$d/endeg" "${H[@]}" egress_load)"; chk "predicate must-PASS: nofatal_last on a fatal-free trail ending at egress_load" $? "$out"
  out="$(pred detail '/etc/nftables.conf:16:48-60: Error: User does not exist' 'User does not exist')"; chk "predicate must-PASS: detail on nft's real FAULT-A refusal" $? "$out"
  # Each must-RED row also names the reason it must red for, so a row that reds for another reason
  # (a malformed call, a missing file) is a FAIL, not a pass.
  for c in "fatal|healthy|egress_load|-|no fatal event|fatal: a trail with no fatal" \
           "fatal|f1|apt_install|-|fatal at fresh_boot_not_ready_egress_load|fatal: a fatal at a stage other than the wanted one" \
           "fatal|fready|egress_load|-|fresh_boot_ready also sent|fatal: a fatal followed by fresh_boot_ready" \
           "fatal|f1|egress_load|User does not exist|detail lacks|fatal: a detail naming a reason but not the wanted one" \
           "absent|healthy|egress_load|-|present:|absent: the stage is present" \
           "nofatal_last|f1|egress_load|-|a fatal reached the stub|nofatal_last: a fatal reached the stub"; do
    IFS='|' read -r _p _f _s _h _w _l <<<"$c"
    if [ "$_h" = - ]; then out="$(pred "$_p" "$d/$_f" "${H[@]}" "$_s")"; else out="$(pred "$_p" "$d/$_f" "${H[@]}" "$_s" "$_h")"; fi; rc=$?
    chk "predicate must-RED: $_l" "$([ "$rc" -eq 1 ] && case "$out" in *"$_w"*) true ;; *) false ;; esac; echo $?)" "rc=$rc want [$_w] got $out"
  done
  for c in "port80|port 80|an event on :80 under --port 443" "hostid|host_id 'i-brh-X'|an event with a wrong host_id" \
           "rejected|stub verdict rejected|an event the stub rejected" "infotail|the last event is egress_load|an info event after fresh_boot_ready" \
           "level|level 'warning'|an event at level warning" "message|message 'another message'|an event with another message" \
           "method|method GET|an event sent with GET"; do
    IFS='|' read -r _f _w _l <<<"$c"
    out="$(pred trail --port 443 "$d/$_f" "${TP[@]}")"; rc=$?
    chk "predicate must-RED: trail: $_l" "$([ "$rc" -eq 1 ] && case "$out" in *"$_w"*) true ;; *) false ;; esac; echo $?)" "rc=$rc want [$_w] got $out"
  done
  out="$(pred trail "$d/b2three" "${B[@]}")"; rc=$?
  chk "predicate must-RED: trail: three runcmd_start against count:runcmd_start=2" \
    "$([ "$rc" -eq 1 ] && case "$out" in *"runcmd_start occurs 3 times"*) true ;; *) false ;; esac; echo $?)" "rc=$rc got $out"
  # The prototype's real FAULT-A detail (CTO Q18: replaces the cut F1-D boot).
  out="$(pred detail 'Dependency failed for bastion-egress.service - soleur-bastion egress allowlist (#12866). Failed to start bastion-egress.service - soleur-bastion egress allowlist (#12866).' '')"; rc=$?
  chk "predicate must-RED: a detail carrying only systemd boilerplate (the real FAULT-A detail)" \
    "$([ "$rc" -eq 1 ] && case "$out" in *"detail names no reason"*) true ;; *) false ;; esac; echo $?)" "rc=$rc $out"
  out="$(pred nofatal_last "$d/healthy" "${H[@]}" egress_load)"; rc=$?
  chk "predicate must-RED: nofatal_last: a fatal-free trail that ends past egress_load" \
    "$([ "$rc" -eq 1 ] && case "$out" in *"the capture ends at fresh_boot_ready, not egress_load"*) true ;; *) false ;; esac; echo $?)" "rc=$rc $out"
  # The file predicates the boot rows read (status, datasource, apt sources), both ways.
  printf '{"status": "done", "errors": []}' > "$d/st-done"
  printf '{"status": "running", "errors": []}' > "$d/st-running"
  printf '{"status": "done", "errors": ["x"]}' > "$d/st-errors"
  printf '{"datasource": "nocloud", "detail": "DataSourceNoCloud [seed=/var/lib/cloud/seed/nocloud]"}' > "$d/ds-nocloud"
  printf '{"datasource": "", "detail": "DataSourceNone"}' > "$d/ds-none"
  _src() { printf 'Types: deb\nURIs: %s://archive.ubuntu.com/ubuntu\nSuites: noble\n\nTypes: deb\nURIs: %s://security.ubuntu.com/ubuntu\nSuites: noble-security\n--- d\n%b--- l\n0\n' "$1" "$2" "$3"; }
  _src https https 'ubuntu.sources\n' > "$d/src-https"; _src http http 'ubuntu.sources\n' > "$d/src-http"
  _src http https 'ubuntu.sources\n' > "$d/src-mixed"; _src https https 'extra.list\nubuntu.sources\n' > "$d/src-extra"
  for c in "status_ok|st-done|status done, errors []" "datasource|ds-nocloud|datasource NoCloud" \
           "sources_https|src-https|https sources only" "sources_http|src-http|rewritten to"; do
    IFS='|' read -r _p _f _w <<<"$c"
    out="$(pred "$_p" "$d/$_f")"; rc=$?
    chk "predicate must-PASS: $_p on $_f" "$([ "$rc" -eq 0 ] && case "$out" in *"$_w"*) true ;; *) false ;; esac; echo $?)" "rc=$rc got $out"
  done
  for c in "status_ok|st-running|status=running|status_ok: cloud-init still running" \
           "status_ok|st-errors|errors=['x']|status_ok: done with errors" \
           "datasource|ds-none|detail 'DataSourceNone'|datasource: DataSourceNone" \
           "sources_https|src-mixed|URIs=['http://archive.ubuntu.com/ubuntu'|sources_https: an http URI" \
           "sources_https|src-extra|sources.list.d=['extra.list', 'ubuntu.sources']|sources_https: another sources.list.d file" \
           "sources_http|src-https|are not all http://|sources_http: the https sources"; do
    IFS='|' read -r _p _f _w _l <<<"$c"
    out="$(pred "$_p" "$d/$_f")"; rc=$?
    chk "predicate must-RED: $_l" "$([ "$rc" -eq 1 ] && case "$out" in *"$_w"*) true ;; *) false ;; esac; echo $?)" "rc=$rc want [$_w] got $out"
  done
}
selftest_preds

# ── Renders (terraform templatefile; bastion.test.sh render() shape) ───────────────────────────
render() { # <template> <egress-sh> <out.yml> [sentry_ingest_host]
  assert_fixture_dir "$WORK"
  printf 'templatefile("%s", { host_name="soleur-bastion", sentry_dsn="%s", sentry_ingest_host="%s", private_ip="10.0.1.70", host_ssh_ed25519_private_key=file("%s"), host_ssh_ed25519_public_key=trimspace(file("%s")), bastion_egress_b64=base64encode(file("%s")) })\n' \
    "$1" "$DSN" "${4:-$INGEST}" "$WORK/k/hk" "$WORK/k/hk.pub" "$2" | terraform -chdir="$WORK/tf" console > "$3.raw" 2> "$3.err" || return 1
  python3 - "$3.raw" "$3" <<'PY'
import sys
L = open(sys.argv[1]).read().splitlines()
if L and L[0].lstrip().startswith("<<"): L = L[1:-1]
open(sys.argv[2], "w").write("\n".join(L) + "\n")
PY
  [ "$(head -1 "$3")" = "#cloud-config" ]
}
declare -A ROW_RENDER=()
do_renders() {
  assert_fixture_dir "$WORK"
  local R="$WORK/render" out
  mkdir -p "$R"
  if render "$TPL" "$EGRESS_SH" "$R/real.yml"; then
    chk "render: the real template renders through terraform console and starts with #cloud-config" 0
    ROW_RENDER[B1]="$R/real.yml"; ROW_RENDER[B2]="$R/real.yml"; ROW_RENDER[B1-C]="$R/real.yml"
  else chk "render: the real template renders through terraform console and starts with #cloud-config" 1 "$(head -c 400 "$R/real.yml.err")"; fi
  mrow() { # <row> <label> <from> <to> <name>
    if out="$(mutate "$1" "$TPL" "$R/$5.tpl" "$3" "$4")" && render "$R/$5.tpl" "$EGRESS_SH" "$R/$5.yml"; then
      chk "render $1: $2 (anchor landed, render ok)" 0; ROW_RENDER[$1]="$R/$5.yml"
    else chk "render $1: $2 (anchor landed, render ok)" 1 "$out $(head -c 300 "$R/$5.yml.err" 2>/dev/null)"; fi
  }
  mrow M1 "the baseline written at /etc/nftables.conf" "$A_M1_FROM" "$A_M1_TO" m1
  mrow M2 "apt preserve_sources_list deleted" "$A_M2_FROM" "" m2
  mrow FA "systemd-timesyncd dropped from the apt_install list" "$A_FA_FROM" "$A_FA_TO" fa
  if render "$TPL" "$EGRESS_SH" "$R/f1.yml" nx-ingest.invalid && out="$(python3 -c '
import sys
a = open(sys.argv[1]).read().splitlines(); b = open(sys.argv[2]).read().splitlines()
d = [(x, y) for x, y in zip(a, b) if x != y]
sys.exit(0 if len(a) == len(b) and len(d) == 1 and "SENTRY_INGEST_HOST=nx-ingest.invalid" in d[0][1] else 1)' "$R/real.yml" "$R/f1.yml")"; then
    chk "render F1: sentry_ingest_host=nx-ingest.invalid changes exactly the env line" 0; ROW_RENDER[F1]="$R/f1.yml"
  else chk "render F1: sentry_ingest_host=nx-ingest.invalid changes exactly the env line" 1 "$out"; fi
  if out="$(mutate F1-M "$TPL" "$R/f1m.tpl" "$A_F1M_FROM" "")" && render "$R/f1m.tpl" "$EGRESS_SH" "$R/f1m.yml" nx-ingest.invalid \
     && out="$(pred onelinediff "$R/f1.yml" "$R/f1m.yml" 'nft flush ruleset')"; then
    chk "render F1-M: differs from F1's render by exactly the deleted on_err flush line" 0 ; ROW_RENDER[F1-M]="$R/f1m.yml"
  else chk "render F1-M: differs from F1's render by exactly the deleted on_err flush line" 1 "$out"; fi
}
do_renders

# ── Offline _egress_why test (CTO Q19, Q15, Q24; no docker): the function from the render, dash ─
egress_why_test() {
  assert_fixture_dir "$WORK"
  local d="$WORK/ew" fn out rc i
  mkdir -p "$d"
  [ -n "${ROW_RENDER[B1]:-}" ] && python3 "$PRED" extract "${ROW_RENDER[B1]}" "$d" >/dev/null 2>&1
  fn="$d/egress_why.sh"
  run_ew() { # <fn-file> <journal-file> -> D's contents; reads EW_NFT EW_EGRESS EW_ST EW_UNITOUT EW_HANG EW_LC EW_OUTER EW_DIR
    local -a lc=()
    local w="${EW_DIR:-$d}"
    [ -z "${EW_LC:-}" ] || lc=(LC_ALL="$EW_LC")
    mkdir -p "$w"; : > "$w/log"; rm -f "$w/D"
    timeout "${EW_OUTER:-60}" env -i PATH="$WORK/fake:/usr/bin:/bin" "${lc[@]}" BRH_FAKE_LOG="$w/log" BRH_FAKE_JOURNAL="$2" \
      BRH_FAKE_NFT="${EW_NFT:-exit-code}" BRH_FAKE_EGRESS="${EW_EGRESS:-success}" BRH_FAKE_ST="${EW_ST:-0}" \
      BRH_FAKE_UNITOUT="${EW_UNITOUT:-/dev/null}" BRH_FAKE_HANG="${EW_HANG:-}" \
      "$DASH" -c '. "$1"; D="$2"; _egress_why' _ "$1" "$w/D" >/dev/null 2>&1
    echo "$?" > "$w/rc"
    cat "$w/D" 2>/dev/null
  }
  synced() { grep -n . "$d/log" | head -2 | tr '\n' ' ' | grep -qE '^1:journalctl --sync 2:journalctl -b '; }
  printf '%s\n' 'Starting bastion-egress.service - soleur-bastion egress allowlist (#12866)...' \
    '[bastion-egress] FAIL: lookup failed for nx-ingest.invalid (cloud-init); the loaded ruleset is unchanged' \
    'bastion-egress.service: Main process exited, code=exited, status=1/FAILURE' \
    'Failed to start bastion-egress.service - soleur-bastion egress allowlist (#12866).' > "$d/j-fail"
  printf '%s\n' '/etc/nftables.conf:16:48-60: Error: User does not exist' \
    'add rule inet soleur_bastion output meta skuid systemd-timesync udp dport 123 accept' \
    'nftables.service: Main process exited, code=exited, status=1/FAILURE' \
    'Dependency failed for bastion-egress.service - soleur-bastion egress allowlist (#12866).' > "$d/j-nft"
  { for i in 1 2; do printf '[bastion-egress] FAIL: %0150d\n' 0; done; } > "$d/j-long"
  printf '%s\n' 'Dependency failed for bastion-egress.service - soleur-bastion egress allowlist (#12866).' \
    'Failed to start bastion-egress.service.' > "$d/j-none"
  # Three reasons from both units, interleaved with boilerplate: exactly the LAST two, in order.
  printf '%s\n' '[bastion-egress] FAIL: lookup failed for a.invalid (cloud-init); the loaded ruleset is unchanged' \
    'bastion-egress.service: Main process exited, code=exited, status=1/FAILURE' \
    '/etc/nftables.conf:16:48-60: Error: User does not exist' \
    'nftables.service: Main process exited, code=exited, status=1/FAILURE' \
    '[bastion-egress] FAIL: lookup failed for b.invalid (cloud-init)' \
    'Failed to start bastion-egress.service - soleur-bastion egress allowlist (#12866).' > "$d/j-three"
  { printf '[bastion-egress] FAIL: '; printf '%0200d\n' 0; } > "$d/j-one-long"
  printf '%s\n' 'Starting bastion-egress.service: a note quoting [bastion-egress] FAIL: mid-line' \
    '[bastion-egress] FAIL: lookup failed for nx-ingest.invalid (cloud-init)' > "$d/j-mid"
  printf '[bastion-egress] FAIL: lookup failed for \377\376.invalid (cloud-init)\n' > "$d/j-bytes"
  printf '%s\n' 'bastion-egress.service: Starting' '/usr/local/sbin/bastion-egress.sh: line 57: RESOLVERS: unbound variable' > "$d/u-unbound"
  if [ ! -s "$fn" ]; then
    for i in "selects the [bastion-egress] FAIL: line after --sync" "selects nft's ': Error: ' refusal" "cuts at 180 bytes" \
             "no reason line -> why=no_reason_line nft=exit-code egress=success st=0 last=" "mutation RED: -b dropped" "mutation RED: --sync dropped" \
             "egress died outside die -> st and its own last output line" \
             "a hung journalctl --sync is cut and D still names the reason" "a hung reason read is cut and the fallback still names the cause" \
             "a hung nftables Result read -> nft=unread" "a hung egress Result read -> egress=unread" \
             "a hung ExecMainStatus read -> st=unread" "a hung last-line read -> last=unread" \
             "three reasons from both units -> exactly the last two" "one line over 180 bytes is cut to 180" \
             "a mid-line [bastion-egress] FAIL: is not a reason (^ anchor)" "non-UTF-8 bytes: byte-for-byte in C; the fallback under C.UTF-8"; do
      chk "_egress_why: $i" 1 "no _egress_why() { ... } function in the rendered runcmd (FAULT-B fix absent)"
    done
    return
  fi
  out="$(run_ew "$fn" "$d/j-fail")"; rc=1
  [ "$out" = "[bastion-egress] FAIL: lookup failed for nx-ingest.invalid (cloud-init); the loaded ruleset is unchanged " ] && synced && rc=0
  chk "_egress_why: selects the [bastion-egress] FAIL: line after --sync" "$rc" "D=[$out] argv=$(tr '\n' '|' < "$d/log")"
  out="$(run_ew "$fn" "$d/j-nft")"; rc=1
  [ "$out" = "/etc/nftables.conf:16:48-60: Error: User does not exist " ] && rc=0
  chk "_egress_why: selects nft's ': Error: ' refusal" "$rc" "D=[$out]"
  out="$(run_ew "$fn" "$d/j-long")"; rc=1
  [ "${#out}" -eq 180 ] && [ "${out:0:22}" = "[bastion-egress] FAIL:" ] && rc=0
  chk "_egress_why: cuts at 180 bytes" "$rc" "len=${#out}"
  # nftables refused (exit-code) and the egress unit never ran: real Result values (CTO Q29).
  out="$(run_ew "$fn" "$d/j-none")"; rc=1
  [ "$out" = "why=no_reason_line nft=exit-code egress=success st=0 last=" ] && rc=0
  chk "_egress_why: no reason line -> why=no_reason_line nft=exit-code egress=success st=0 last=" "$rc" "D=[$out]"
  local ul='/usr/local/sbin/bastion-egress.sh: line 57: RESOLVERS: unbound variable'
  out="$(EW_NFT=success EW_EGRESS=exit-code EW_ST=1 EW_UNITOUT="$d/u-unbound" run_ew "$fn" "$d/j-none")"; rc=1
  [ "$out" = "why=no_reason_line nft=success egress=exit-code st=1 last=${ul:0:60}" ] && rc=0
  chk "_egress_why: egress died outside die -> st and its own last output line" "$rc" "D=[$out]"
  # CTO Q29: every read is bounded and falls back. Each hang row hangs one read (30 s) under an outer
  # 25 s cap, so only `timeout 10` lets it finish; the six run side by side (one ~10 s wait in all).
  local fb='why=no_reason_line nft=exit-code egress=success st=0 last=' fl='[bastion-egress] FAIL: lookup failed for nx-ingest.invalid (cloud-init); the loaded ruleset is unchanged '
  local -a hp=() hrows=(
    "sync|j-fail|$fl|a hung journalctl --sync is cut and D still names the reason"
    "reason|j-fail|$fb|a hung reason read is cut and the fallback still names the cause"
    "show-nft|j-none|why=no_reason_line nft=unread egress=success st=0 last=|a hung nftables Result read -> nft=unread"
    "show-egress|j-none|why=no_reason_line nft=exit-code egress=unread st=0 last=|a hung egress Result read -> egress=unread"
    "show-st|j-none|why=no_reason_line nft=exit-code egress=success st=unread last=|a hung ExecMainStatus read -> st=unread"
    "unit|j-none|why=no_reason_line nft=exit-code egress=success st=0 last=unread|a hung last-line read -> last=unread")
  local hk hj hw hl
  for i in "${hrows[@]}"; do
    IFS='|' read -r hk hj hw hl <<<"$i"
    ( EW_HANG="$hk" EW_DIR="$d/hang-$hk" EW_OUTER=25 run_ew "$fn" "$d/$hj" > "$d/hang-$hk.out" ) &
    hp+=("$!")
  done
  wait "${hp[@]}"
  for i in "${hrows[@]}"; do
    IFS='|' read -r hk hj hw hl <<<"$i"
    out="$(cat "$d/hang-$hk.out")"; rc=1
    [ "$(cat "$d/hang-$hk/rc" 2>/dev/null)" = 0 ] && [ "$out" = "$hw" ] && rc=0
    chk "_egress_why: $hl" "$rc" "rc=$(cat "$d/hang-$hk/rc" 2>/dev/null) (124 = the outer cap: a read was not bounded) D=[$out]"
  done
  out="$(run_ew "$fn" "$d/j-three")"; rc=1
  [ "$out" = "/etc/nftables.conf:16:48-60: Error: User does not exist [bastion-egress] FAIL: lookup failed for b.invalid (cloud-init) " ] && rc=0
  chk "_egress_why: three reasons from both units -> exactly the last two" "$rc" "D=[$out]"
  out="$(run_ew "$fn" "$d/j-one-long")"; rc=1
  [ "${#out}" -eq 180 ] && [ "$out" = "$(head -c 180 "$d/j-one-long")" ] && rc=0
  chk "_egress_why: one line over 180 bytes is cut to 180" "$rc" "len=${#out}"
  out="$(run_ew "$fn" "$d/j-mid")"; rc=1
  [ "$out" = "[bastion-egress] FAIL: lookup failed for nx-ingest.invalid (cloud-init) " ] && rc=0
  chk "_egress_why: a mid-line [bastion-egress] FAIL: is not a reason (^ anchor)" "$rc" "D=[$out]"
  # In C the line passes byte for byte (tr and head are byte-oriented); under C.UTF-8 grep treats it as
  # binary and selects nothing, and the fallback still names the cause (journalctl -o cat prints such a
  # message as a blob placeholder on the real host, so this is the robustness edge, not the usual path).
  out="$(run_ew "$fn" "$d/j-bytes")"; rc=1
  local u8; u8="$(EW_LC=C.UTF-8 run_ew "$fn" "$d/j-bytes")"
  [ "$out" = "$(printf '[bastion-egress] FAIL: lookup failed for \377\376.invalid (cloud-init) ')" ] \
    && case "$u8" in "[bastion-egress] FAIL: "*|"why=no_reason_line nft="*) true ;; *) false ;; esac && rc=0
  chk "_egress_why: non-UTF-8 bytes: byte-for-byte in C; the fallback under C.UTF-8" "$rc" "C=[$(printf '%s' "$out" | od -An -c | tr -s ' ' | head -c 200)] C.UTF-8=[$u8]"
  if out="$(mutate ew "$fn" "$d/nob.sh" 'journalctl -b -u' 'journalctl -u')"; then
    out="$(run_ew "$d/nob.sh" "$d/j-fail")"; rc=1
    # Red for its reason: the un-scoped read is not this boot's (the fake refuses it), so no reason line.
    case "$out" in why=no_reason_line*) grep -qx 'journalctl -u nftables.service -u bastion-egress.service --no-pager -o cat' "$d/log" && rc=0 ;; esac
    chk "_egress_why: mutation RED: -b dropped" "$rc" "the mutant produced [$out] argv=$(tr '\n' '|' < "$d/log")"
  else chk "_egress_why: mutation RED: -b dropped" 1 "$out"; fi
  if out="$(mutate ew "$fn" "$d/nosync.sh" '  timeout 10 journalctl --sync 2>/dev/null || :
' '')"; then
    run_ew "$d/nosync.sh" "$d/j-fail" >/dev/null; rc=1
    # Red for its reason: the journal is read with no --sync before it.
    ! synced && ! grep -q -e '--sync' "$d/log" && head -1 "$d/log" | grep -q '^journalctl -b -u ' && rc=0
    chk "_egress_why: mutation RED: --sync dropped" "$rc" "argv=$(tr '\n' '|' < "$d/log")"
  else chk "_egress_why: mutation RED: --sync dropped" 1 "$out"; fi
}
egress_why_test

# ── Archive addresses and the ADR-188 corroboration probe ─────────────────────────────────────
resolve_public() { # <name> -> one public IPv4 (a private, loopback, link-local or benchmark answer is refused)
  local ip
  ip="$(getent ahostsv4 "$1" 2>/dev/null | awk '{print $1}' | sort -u | head -1)"
  python3 -c 'import ipaddress,sys; a=ipaddress.ip_address(sys.argv[1]); sys.exit(1 if (a.is_private or a.is_loopback or a.is_link_local or a.is_reserved) else 0)' "${ip:-0.0.0.0}" 2>/dev/null || return 1
  printf '%s' "$ip"
}
if [ -n "${BRH_ARCHIVE_PIN:-}" ]; then ARCHIVE_IP="$BRH_ARCHIVE_PIN"; SECURITY_IP="$BRH_ARCHIVE_PIN"
  printf 'NOTICE: BRH_ARCHIVE_PIN pins the archive names to %s (Test Scenario 4)\n' "$BRH_ARCHIVE_PIN"
else
  ARCHIVE_IP="$(resolve_public archive.ubuntu.com)"; SECURITY_IP="$(resolve_public security.ubuntu.com)"
fi
archive_probe() { # -> PROBE_LINE; rc 0 when both InRelease files answer 200 at the pinned addresses
  local a s
  a="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 15 --resolve "archive.ubuntu.com:443:${ARCHIVE_IP:-0.0.0.0}" https://archive.ubuntu.com/ubuntu/dists/noble/InRelease 2>&1 | tr '\n' ' ')"
  s="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 15 --resolve "security.ubuntu.com:443:${SECURITY_IP:-0.0.0.0}" https://security.ubuntu.com/ubuntu/dists/noble-security/InRelease 2>&1 | tr '\n' ' ')"
  PROBE_LINE="archive=$a security=$s (pinned ${ARCHIVE_IP:-none}/${SECURITY_IP:-none})"
  [ "$a" = 200 ] && [ "$s" = 200 ]
}
PROBE_OK=0; archive_probe && PROBE_OK=1
printf 'archive probe: %s\n' "$PROBE_LINE"
REPROBE_DONE=0; REPROBE_OK=0; REPROBE_LINE=""
reprobe() { # the classification-time probe (an outage that began mid-run), once
  [ "$REPROBE_DONE" -eq 1 ] && return
  REPROBE_DONE=1; archive_probe && REPROBE_OK=1; REPROBE_LINE="$PROBE_LINE"
}

# ── Fixture images (built once per run, reused by content tag) ─────────────────────────────────
DEADLINE_S=$BUILD_CAP_S
for w in "${WAVES[@]}"; do
  worst=0; for r in $w; do [ "${ROW_BOOTS[$r]}" -gt "$worst" ] && worst="${ROW_BOOTS[$r]}"; done
  DEADLINE_S=$((DEADLINE_S + worst * BOOT_CAP_S))
done
printf 'deadline: %ss = build cap %ss + per wave (worst row boots x %ss per boot)\n' "$DEADLINE_S" "$BUILD_CAP_S" "$BOOT_CAP_S"
WEEK="$(date -u +%G-W%V)"
IMG_MIN="brh-fixture:min-$( { printf '%s\n' "$UBUNTU_BASE" "${MIN_PKGS[*]}" "$WEEK"; cat "$WORK/recipe/debs.sh" "$WORK/recipe/post.sh"; } | sha256sum | cut -c1-12)"
IMG_CLOUD="brh-fixture:cloud-$(printf '%s\n' "$IMG_MIN" "${CLOUD_IMAGE_PKGS[*]}" "$WEEK" | sha256sum | cut -c1-12)"
T_BUILD0=$SECONDS
SKIP_ALL=""
build_images() {
  assert_fixture_dir "$WORK"
  local rc left kb root
  root="$(docker info --format '{{.DockerRootDir}}' 2>/dev/null)"
  kb="$(df -Pk "${root:-/}" 2>/dev/null | awk 'NR==2 {print $4}')"
  [ -n "$kb" ] || kb="$(df -Pk / | awk 'NR==2 {print $4}')"
  if [ "${kb:-0}" -lt 4194304 ]; then printf 'BRH_DISK_LOW: %s KB free under %s, 4 GB needed\n' "$kb" "${root:-/}" >&2
    is_ci && die_verdict BRH_DISK_LOW; fi
  if ! docker image inspect "$IMG_MIN" >/dev/null 2>&1; then
    docker rm -f "brh-$$-build" >/dev/null 2>&1
    gd_apt_state_arm "$WORK/aptstate" "$APT_BUDGET_S" || { echo "FIXTURE-FAIL: the shared apt budget could not be armed" >&2; exit 2; }
    timeout -k 10 "$BUILD_CAP_S" docker run --name "brh-$$-build" -v "$GD_APT_STATE:/work/apt" -v "$WORK/recipe:/recipe:ro" "$UBUNTU_BASE" bash -c '
      export DEBIAN_FRONTEND=noninteractive
      . /work/apt/apt-bounded.sh || exit 97
      bash /recipe/debs.sh || exit 96
      cd /tmp/brh-debs || exit 96
      gd_apt_install_bounded --no-install-recommends "$@" ./linux-image-0.0.0-1-generic.deb ./linux-image-generic.deb || exit $?
      bash /recipe/post.sh || exit 95
    ' _ "${MIN_PKGS[@]}" > "$WORK/build-min.log" 2>&1
    rc=$?
    gd_apt_state_summary
    if [ "$rc" -ne 0 ]; then
      docker rm -f "brh-$$-build" >/dev/null 2>&1
      BUILD_FAIL="minimal image build rc=$rc: $(gd_apt_out_tail "$WORK/build-min.log" 6 | tr '\n' ' ' | head -c 600)"
      [ "$rc" -eq 100 ] && BUILD_DECLINE=1
      return 1
    fi
    if ! docker commit "brh-$$-build" "$IMG_MIN" >/dev/null; then BUILD_FAIL="docker commit failed"; return 1; fi
    docker rm "brh-$$-build" >/dev/null
  fi
  if ! docker image inspect "$IMG_CLOUD" >/dev/null 2>&1; then
    left=$((BUILD_CAP_S - (SECONDS - T_BUILD0))); [ "$left" -lt 30 ] && left=30
    docker rm -f "brh-$$-buildc" >/dev/null 2>&1
    gd_apt_state_arm "$WORK/aptstate" "$APT_BUDGET_S" || { echo "FIXTURE-FAIL: the shared apt budget could not be armed" >&2; exit 2; }
    timeout -k 10 "$left" docker run --name "brh-$$-buildc" -v "$GD_APT_STATE:/work/apt" "$IMG_MIN" bash -c '
      export DEBIAN_FRONTEND=noninteractive
      . /work/apt/apt-bounded.sh || exit 97
      gd_apt_install_bounded --no-install-recommends "$@" || exit $?
      rm -rf /var/lib/apt/lists/* /etc/ssh/ssh_host_*
    ' _ "${CLOUD_IMAGE_PKGS[@]}" > "$WORK/build-cloud.log" 2>&1
    rc=$?
    gd_apt_state_summary
    if [ "$rc" -ne 0 ]; then
      docker rm -f "brh-$$-buildc" >/dev/null 2>&1
      BUILD_FAIL="cloud-faithful layer build rc=$rc: $(gd_apt_out_tail "$WORK/build-cloud.log" 6 | tr '\n' ' ' | head -c 600)"
      [ "$rc" -eq 100 ] && BUILD_DECLINE=1
      return 1
    fi
    if ! docker commit "brh-$$-buildc" "$IMG_CLOUD" >/dev/null; then BUILD_FAIL="docker commit failed"; return 1; fi
    docker rm "brh-$$-buildc" >/dev/null
  fi
  printf 'images: %s %s (built or reused in %ss)\n' "$IMG_MIN" "$IMG_CLOUD" "$((SECONDS - T_BUILD0))"
}
img_run() { # <image> <dir mounted at /x, read-only> <script>: a throwaway, networkless container
  docker run --rm --network none -v "$2:/x:ro" "$1" sh -c "$3"
}
BUILD_FAIL=""; BUILD_DECLINE=0
if ! build_images; then
  if [ "$BUILD_DECLINE" -eq 1 ] && { [ "$PROBE_OK" -eq 0 ] || { reprobe; [ "$REPROBE_OK" -eq 0 ]; }; }; then
    SKIP_ALL="image build declined by the archive ($BUILD_FAIL) with the archive probe failing: $PROBE_LINE ${REPROBE_LINE}"
  else
    chk "images: the fixture images build" 1 "$BUILD_FAIL"
    die_verdict "fixture image build: $(head -c 300 <<<"$BUILD_FAIL")"
  fi
fi

# ── Pre-arm image checks, S0 and S1 (CTO Q1, Q18, Q27) ────────────────────────────────────────────
if [ -z "$SKIP_ALL" ]; then
  assert_fixture_dir "$WORK"
  cp "${ROW_RENDER[B1]:-/dev/null}" "$WORK/static/user-data" 2>/dev/null
  python3 "$PRED" extract "$WORK/static/user-data" "$WORK/static" >/dev/null 2>&1
  _o="$(img_run "$IMG_MIN" "$WORK/static" '
    echo "BRH_CI_VERSION=$(cloud-init --version 2>&1)"
    echo "TSD=$(dpkg-query -W -f="\${Status}" systemd-timesyncd 2>/dev/null)"
    echo "TSU=$(getent passwd systemd-timesync)"
    cloud-init schema -c /x/user-data > /tmp/s0 2>&1; echo "S0_RC=$?"; sed -n "1,8s/^/S0| /p" /tmp/s0
    dash -n /x/joined.sh; echo "S1_RC=$?"
    dash -n /x/joined-red.sh > /tmp/s1r 2>&1; echo "S1RED_RC=$?"; echo "S1RED_MSG=$(head -c 200 /tmp/s1r | tr "\n" " ")"
    for u in getty@.service console-getty.service getty.target; do echo "GETTY $u $(readlink /etc/systemd/system/$u)"; done
    echo "BRH_PROBE_DONE=1"' 2>&1)"
  _v() { printf '%s\n' "$_o" | sed -n "s/^$1=//p" | head -1; }
  CI_VERSION="$(_v BRH_CI_VERSION)"; printf 'cloud-init in the fixture: %s\n' "$CI_VERSION"
  case "$CI_VERSION" in *" $CLOUD_INIT_RECORDED"*) : ;; *) printf 'BRH_CLOUD_INIT_VERSION_DRIFT: fixture cloud-init is "%s", recorded %s (a warning, not a failure)\n' "$CI_VERSION" "$CLOUD_INIT_RECORDED" ;; esac
  # An absence proves nothing unless the probe ran to its end: no sentinel is its own failure.
  _min_rc=1; _min_tok=BRH_IMAGE_PROBE_NO_EVIDENCE
  if [ "$(_v BRH_PROBE_DONE)" = 1 ]; then _min_tok=BRH_BASELINE_NOT_MINIMAL
    if ! _v TSD | grep -q 'install ok installed' && [ -z "$(_v TSU)" ]; then _min_rc=0; fi; fi
  chk "image: the minimal fixture has no systemd-timesyncd package and no systemd-timesync user" "$_min_rc" "$_min_tok: TSD=[$(_v TSD)] TSU=[$(_v TSU)] probe=[$(head -c 300 <<<"$_o")]"
  if [ "$_min_rc" -ne 0 ]; then printf '%s\n' "$_min_tok" >&2; die_verdict "$_min_tok: FA and the FAULT-A claim are void"; fi
  _c="$(img_run "$IMG_CLOUD" "$WORK/static" 'dpkg-query -W -f="\${Package} \${Status}\n" nftables systemd-timesyncd 2>&1
    for u in getty@.service console-getty.service getty.target; do echo "GETTY $u $(readlink /etc/systemd/system/$u)"; done')"
  _cl_rc=1; [ "$(printf '%s\n' "$_c" | grep -c ' install ok installed$')" -eq 2 ] && _cl_rc=0
  chk "image: the cloud-faithful fixture already carries nftables and systemd-timesyncd" "$_cl_rc" "BRH_CLOUD_NOT_FAITHFUL: $_c"
  if [ "$_cl_rc" -ne 0 ]; then printf 'BRH_CLOUD_NOT_FAITHFUL\n' >&2; die_verdict BRH_CLOUD_NOT_FAITHFUL; fi
  # CTO Q27: getty@tty1 is enabled in both images and its only guard (/dev/tty0) holds under
  # --privileged, so an unmasked getty would hang up and reset the real host's tty1 on every boot.
  _gt="$(printf '%s\n%s\n' "$_o" "$_c" | grep -cE '^GETTY (getty@\.service|console-getty\.service|getty\.target) /dev/null$')"
  chk "image: both fixtures mask getty@.service, console-getty.service and getty.target (no host-VT getty under --privileged)" \
    "$([ "$_gt" = 6 ]; echo $?)" "BRH_GETTY_UNMASKED: $(printf '%s\n%s\n' "$_o" "$_c" | grep '^GETTY' | tr '\n' ' ')"
  if [ "$_gt" != 6 ]; then printf 'BRH_GETTY_UNMASKED\n' >&2; die_verdict BRH_GETTY_UNMASKED; fi
  chk "S0: cloud-init schema accepts the render" "$([ "$(_v S0_RC)" = 0 ]; echo $?)" "$(printf '%s\n' "$_o" | grep '^S0' | head -10)"
  chk "S1: the joined runcmd items pass dash -n" "$([ "$(_v S1_RC)" = 0 ]; echo $?)" "rc=$(_v S1_RC)"
  chk "S1 control: a copy with an unbalanced fi fails dash -n on that fi" \
    "$({ [ "$(_v S1RED_RC)" = 2 ] || [ "$(_v S1RED_RC)" = 1 ]; } && _v S1RED_MSG | grep -qF 'Syntax error: "fi" unexpected'; echo $?)" "rc=$(_v S1RED_RC) $(_v S1RED_MSG)"
else
  printf 'SKIP (loud): S0/S1 and image checks: %s\n' "$SKIP_ALL"
  cases=$((cases + 6)); SKIPPED_ASSERTIONS=$((SKIPPED_ASSERTIONS + 6))
fi

# ── Per-row topology and evidence (background, three waves) ────────────────────────────────────
declare -A ROW_K=()
K_NEXT=1
route_busy() { # <k>: a non-default host route covers 198.18.k.0/24 (e.g. a fake-IP proxy)
  ip -4 route show 2>/dev/null | python3 -c '
import ipaddress, sys
k = sys.argv[1]; t = ipaddress.ip_network("198.18.%s.0/24" % k)
for l in sys.stdin:
    d = l.split()[0] if l.split() else ""
    if d in ("default", "0.0.0.0/0"): continue
    try:
        n = ipaddress.ip_network(d, strict=False)
    except ValueError:
        continue
    if n.overlaps(t): sys.exit(0)
sys.exit(1)' "$1"
}
alloc_net() { # <row>: a per-row docker network on a free 198.18.k.0/24, under a flock shared by concurrent runs
  local k lk
  assert_fixture_dir "$LOCKF"
  exec {lk}>>"$LOCKF"
  flock -w 60 "$lk" || { printf 'BRH_SUBNET_BUSY: could not take %s\n' "$LOCKF" >&2; return 1; }
  for k in $(seq "$K_NEXT" 250); do
    route_busy "$k" && continue
    if docker network create --subnet "198.18.$k.0/24" "brh-$$-$1" >/dev/null 2>&1; then
      ROW_K[$1]=$k; K_NEXT=$((k + 1)); flock -u "$lk"; exec {lk}>&-; return 0
    fi
  done
  flock -u "$lk"; exec {lk}>&-
  printf 'BRH_SUBNET_BUSY: no free 198.18.k.0/24 for row %s\n' "$1" >&2; return 1
}
start_stub() { # <net> <ip> <outdir> <name>
  docker run -d --name "$4" --network "$1" --ip "$2" -v "$WORK/stub.py:/brh/stub.py:ro" -v "$WORK/pki-srv:/pki:ro" -v "$3:/out" "$IMG_MIN" python3 /brh/stub.py /out >/dev/null || return 1
  local i; for i in $(seq 1 60); do [ -f "$3/stub.ready" ] && return 0; sleep 0.25; done; return 1
}
neighbour() { # <net> <out> [docker args...]: the stub self-test (and B1's liveness) from a non-loopback neighbour
  local net="$1" out="$2"; shift 2
  assert_fixture_dir "$out"
  docker run --rm --network "$net" "$@" -v "$WORK/pki/ca.crt:/brh/ca.crt:ro" -v "$WORK/neighbour.sh:/brh/n.sh:ro" "$IMG_MIN" sh /brh/n.sh > "$out" 2>&1
}
gather() { # <row>: boots the row and copies its evidence out; never a verdict (the parent asserts)
  local row="$1" RD="$WORK/rows/$1" C="brh-$$-$1" NET="brh-$$-$1" PFX="198.18.${ROW_K[$1]}" img="$IMG_MIN" st n
  assert_fixture_dir "$RD"
  [ "${ROW_IMG[$row]}" = cloud ] && img="$IMG_CLOUD"
  X() { docker exec "$C" "$@"; }
  fact() { X sh -c "$2" > "$RD/f/$1.out" 2>&1; echo "$?" > "$RD/f/$1.rc"; }
  [ -n "${ROW_RENDER[$row]:-}" ] || { echo "no render (its mutation did not land)" > "$RD/f/harness"; return 1; }
  cp "${ROW_RENDER[$row]}" "$RD/seed/user-data"
  printf 'instance-id: i-brh-%s\nlocal-hostname: soleur-bastion\n' "$row" > "$RD/seed/meta-data"
  printf '%s\n' "${ROW_MODE[$row]}" > "$RD/uname-mode"
  chmod 0755 "$RD/seed" "$RD/out" "$RD/decoy"; chmod 0644 "$RD/seed/user-data" "$RD/seed/meta-data" "$RD/uname-mode"
  start_stub "$NET" "$PFX.20" "$RD/out" "$C-stub" || { echo "the stub did not come up" > "$RD/f/harness"; return 1; }
  local -a nb=(--add-host "$INGEST:$PFX.20")
  if [ "$row" = B1 ]; then
    start_stub "$NET" "$PFX.21" "$RD/decoy" "$C-decoy" || { echo "the decoy did not come up" > "$RD/f/harness"; return 1; }
    nb+=(--add-host "decoy.example:$PFX.21" -e BRH_LIVE=1)
  fi
  neighbour "$NET" "$RD/f/selftest.out" "${nb[@]}"
  local -a ah=(--add-host "archive.ubuntu.com:$ARCHIVE_IP" --add-host "security.ubuntu.com:$SECURITY_IP" --add-host "$INGEST:$PFX.20")
  [ "$row" = B1 ] && ah+=(--add-host "decoy.example:$PFX.21")
  docker create --name "$C" --privileged --cgroupns=private --cgroup-parent=docker.slice -e container=docker \
    --network "$NET" --ip "$PFX.10" --tmpfs /run --tmpfs /run/lock --tmpfs /tmp "${ah[@]}" \
    -v "$RD/seed:/var/lib/cloud/seed/nocloud:ro" -v "$RD/uname-mode:/etc/brh/uname-mode:ro" \
    "$img" /lib/systemd/systemd > "$RD/f/create.out" 2>&1 || { echo "docker create failed: $(head -c 200 "$RD/f/create.out")" > "$RD/f/harness"; return 1; }
  [ "$(docker inspect -f '{{.HostConfig.NetworkMode}}' "$C")" = "$NET" ] || { echo shared > "$RD/f/netns"; return 1; }
  # CTO Q23: the fixture CA where update-ca-certificates keeps it, and a bundle that already carries it.
  docker cp "$C:/etc/ssl/certs/ca-certificates.crt" "$RD/sys-bundle.crt" >/dev/null 2>&1 || { echo "no system CA bundle in the image" > "$RD/f/harness"; return 1; }
  cat "$RD/sys-bundle.crt" "$WORK/pki/ca.crt" > "$RD/bundle.crt"; chmod 0644 "$RD/bundle.crt"
  if ! docker cp "$RD/bundle.crt" "$C:/etc/ssl/certs/ca-certificates.crt" >/dev/null \
     || ! docker cp "$WORK/pki/ca.crt" "$C:/usr/local/share/ca-certificates/brh.crt" >/dev/null; then
    echo "docker cp of the fixture CA failed" > "$RD/f/harness"; return 1
  fi
  boot_once() { # <tag>: start, contain, wait for a terminal cloud-init status, the container's exit or the cap
    local tag="$1" t0 i n0 n1
    docker start "$C" >/dev/null 2>"$RD/f/$tag.start.err" || { echo "docker start failed" > "$RD/f/harness"; return 1; }
    t0=$SECONDS
    for i in $(seq 1 60); do X true 2>/dev/null && break; sleep 0.25; done
    [ "$(X readlink /proc/1/ns/net 2>/dev/null)" != "$(readlink /proc/self/ns/net)" ] || { echo shared > "$RD/f/netns"; docker rm -f "$C" >/dev/null 2>&1; return 1; }
    X ip addr add 10.0.1.70/32 dev lo 2>/dev/null
    n0="$(X sh -c 'cat /var/lib/brh/reboot.log 2>/dev/null | wc -l' 2>/dev/null)"
    while :; do
      if [ "$(docker inspect -f '{{.State.Running}}' "$C" 2>/dev/null)" != true ]; then echo exited > "$RD/f/$tag.end"; break; fi
      X cloud-init status --format json > "$RD/f/$tag.status.json" 2>/dev/null
      case "$(python3 "$PRED" status "$RD/f/$tag.status.json")" in done|error|disabled)
        # The reboot shim's poweroff SIGTERMs cloud-final and cloud-init then records `done` while
        # the container is still going down (measured under load): a terminal status does not count
        # while a reboot this boot requested is in flight; the container's exit ends the wait.
        n1="$(X sh -c 'cat /var/lib/brh/reboot.log 2>/dev/null | wc -l' 2>/dev/null)"
        if [ -n "$n1" ] && [ "$n1" -le "${n0:-0}" ]; then echo terminal > "$RD/f/$tag.end"; break; fi ;;
      esac
      if [ $((SECONDS - t0)) -ge "$BOOT_CAP_S" ]; then
        echo cap > "$RD/f/$tag.end"
        X sh -c 'for p in /proc/[0-9]*; do tr "\0" " " < "$p/cmdline" 2>/dev/null; echo; done | grep -a "apt-ge[t] "' > "$RD/f/$tag.cap-apt" 2>&1
        break
      fi
      sleep 2
    done
    echo $((SECONDS - t0)) > "$RD/f/$tag.elapsed"
  }
  if [ "${ROW_MODE[$row]}" = reboot ]; then
    boot_once boot1 || return 1
    if [ "$(cat "$RD/f/boot1.end")" = exited ]; then
      docker cp "$C:/var/log/cloud-init-output.log" "$RD/cloud-init-output.boot1.log" >/dev/null 2>&1
      boot_once boot2 || return 1
    fi
    st=boot2; [ -f "$RD/f/boot2.end" ] || st=boot1
  else
    boot_once boot || return 1; st=boot
  fi
  cp "$RD/f/$st.status.json" "$RD/f/status.json" 2>/dev/null; cp "$RD/f/$st.end" "$RD/f/end"; cp "$RD/f/$st.elapsed" "$RD/f/elapsed"
  cp "$RD/out/capture.log" "$RD/capture-boot.log" 2>/dev/null
  docker cp "$C:/var/log/cloud-init-output.log" "$RD/cloud-init-output.log" >/dev/null 2>&1
  if [ "$(docker inspect -f '{{.State.Running}}' "$C" 2>/dev/null)" = true ]; then
    X journalctl -b --no-pager -o short-iso > "$RD/journal.txt" 2>&1
    X cloud-init status --long > "$RD/status-long.txt" 2>&1
    fact sources 'cat /etc/apt/sources.list.d/ubuntu.sources; echo "--- d"; ls -1A /etc/apt/sources.list.d; echo "--- l"; wc -c < /etc/apt/sources.list'
    fact pkgs 'dpkg-query -W -f="\${Package} \${Status}\n" curl nftables systemd-timesyncd'
    fact conf 'cmp /etc/nftables.conf /etc/soleur/bastion-nftables.conf'
    fact units 'for u in nftables.service bastion-egress.service bastion-egress.timer; do printf "%s %s %s\n" "$u" "$(systemctl is-active "$u")" "$(systemctl is-enabled "$u")"; done'
    fact ssh 'systemctl is-enabled ssh.service ssh.socket'
    fact users 'for u in '"${IMAGE_ASSUMED_USERS[*]}"' $(sed -n "s/.*meta skuid \([a-z_][a-z0-9_-]*\) .*/\1/p" /etc/nftables.conf 2>/dev/null | sort -u); do if getent passwd "$u" >/dev/null; then echo "$u ok"; else echo "$u MISSING"; fi; done'
    fact ruleset 'nft list ruleset'
    fact settle 'test -e /var/lib/soleur/kernel-settle'
    fact reboot 'cat /var/lib/brh/reboot.log'
  fi
  if [ "$row" = B1 ] && [ "$(cat "$RD/f/end")" = terminal ]; then
    # P7: the rendered private-ip stanza, run with the address present and after deleting it.
    if [ -s "$WORK/static/p7.sh" ]; then
      docker cp "$WORK/static/p7.sh" "$C:/var/lib/brh/p7.sh" >/dev/null 2>&1
      X timeout 5 sh /var/lib/brh/p7.sh >/dev/null 2>&1; echo "$?" > "$RD/f/p7.present.rc"
      X ip addr del 10.0.1.70/32 dev lo 2>/dev/null
      X timeout 5 sh /var/lib/brh/p7.sh >/dev/null 2>&1; echo "$?" > "$RD/f/p7.absent.rc"
      X ip addr add 10.0.1.70/32 dev lo 2>/dev/null
    fi
    # B1-E: one probe command for all five paths; OPEN = curl rc 0 and a stub line, CLOSED = rc 28.
    fact set 'nft list set inet soleur_bastion soleur_egress_allow'
    probe() { # <name> <user> <url>
      local -a as=()
      [ "$2" = root ] || as=(setpriv --reuid="$2" --regid=nogroup --clear-groups)
      X "${as[@]}" curl -sS -o /dev/null --connect-timeout 3 -m 5 "$3" > "$RD/f/probe-$1.err" 2>&1; echo "$?" > "$RD/f/probe-$1.rc"
    }
    probe root443 root "https://$INGEST/brh-probe/root443"
    probe apt443 _apt "https://$INGEST/brh-probe/apt443"
    probe nobody443 nobody "https://$INGEST/brh-probe/nobody443"
    probe root80 root "http://$INGEST:80/brh-probe/root80"
    probe decoy443 root "https://decoy.example/brh-probe/decoy443"
    # B1-P: a restart of nftables.service re-runs bastion-egress (PartOf=) and the set comes back.
    local inv0 inv1="" i got=0
    inv0="$(X systemctl show -p InvocationID --value bastion-egress.service 2>/dev/null)"
    X systemctl restart nftables.service > "$RD/f/restart.out" 2>&1
    for i in $(seq 1 10); do
      inv1="$(X systemctl show -p InvocationID --value bastion-egress.service 2>/dev/null)"
      if [ -n "$inv1" ] && [ "$inv1" != "$inv0" ] && X nft list set inet soleur_bastion soleur_egress_allow 2>/dev/null | grep -qF "$PFX.20"; then got=1; break; fi
      sleep 1
    done
    printf 'inv0=%s inv1=%s set_back=%s\n' "$inv0" "$inv1" "$got" > "$RD/f/partof.out"
    X systemctl start bastion-egress-refresh.service > "$RD/f/refresh.out" 2>&1; echo "$?" > "$RD/f/refresh.rc"
  fi
  if [ "$row" = F1-M ]; then fact emit "curl -sS -o /dev/null --connect-timeout 3 -m 5 https://$INGEST/brh-probe/f1m"; fi
  docker rm -f "$C" "$C-stub" "$C-decoy" >/dev/null 2>&1
  docker network rm "$NET" >/dev/null 2>&1
  touch "$RD/f/done"
}
run_wave() { # <rows...>
  local r alive
  for r in "$@"; do
    selected "$r" || continue
    assert_fixture_dir "$WORK"
    mkdir -p "$WORK/rows/$r/f" "$WORK/rows/$r/seed" "$WORK/rows/$r/out" "$WORK/rows/$r/decoy"
    if [ $((SECONDS - T_BUILD0)) -ge "$DEADLINE_S" ]; then echo "BRH_DEADLINE:$r (not started)" > "$WORK/rows/$r/f/deadline"; continue; fi
    alloc_net "$r" || die_verdict "BRH_SUBNET_BUSY:$r"
    ( gather "$r" ) > "$WORK/rows/$r/gather.log" 2>&1 &
    WPID[$r]=$!
  done
  while :; do
    alive=0
    for r in "$@"; do [ -n "${WPID[$r]:-}" ] && kill -0 "${WPID[$r]}" 2>/dev/null && alive=1; done
    [ "$alive" -eq 1 ] || break
    if [ $((SECONDS - T_BUILD0)) -ge "$DEADLINE_S" ]; then
      for r in "$@"; do
        if [ -n "${WPID[$r]:-}" ] && kill -0 "${WPID[$r]}" 2>/dev/null; then
          kill "${WPID[$r]}" 2>/dev/null; echo "BRH_DEADLINE:$r (killed at ${DEADLINE_S}s)" > "$WORK/rows/$r/f/deadline"
          docker rm -f "brh-$$-$r" "brh-$$-$r-stub" "brh-$$-$r-decoy" >/dev/null 2>&1
        fi
      done
      break
    fi
    sleep 2
  done
  wait
  for r in "$@"; do
    unset 'WPID[$r]'
    if [ -f "$WORK/rows/$r/f/netns" ]; then printf 'BRH_NETNS_SHARED:%s\n' "$r" >&2; die_verdict "BRH_NETNS_SHARED:$r"; fi
  done
}
if [ -z "$SKIP_ALL" ] && [ "${#SELECTED[@]}" -gt 0 ]; then
  for w in "${WAVES[@]}"; do
    # shellcheck disable=SC2086  # a wave is a space-separated row list
    run_wave $w
    printf 'wave [%s] done at %ss\n' "$w" "$((SECONDS - T_BUILD0))"
  done
fi

# ── Row verdicts (serial, in registry order; helpers defined above the boots) ──────────────────
selftest_rk() {
  local o; o="$(cat "$RD/f/selftest.out" 2>/dev/null)"; local rc=1 p
  if printf '%s\n' "$o" | grep -qxE 'wrongpath 4[0-9][0-9]' && printf '%s\n' "$o" | grep -qxE 'noauth 4[0-9][0-9]' \
     && printf '%s\n' "$o" | grep -qxE 'wrongkey 4[0-9][0-9]' && printf '%s\n' "$o" | grep -qxE 'get 4[0-9][0-9]' \
     && printf '%s\n' "$o" | grep -qx 'good 200' && p="$(pred selftest "$RD/capture-boot.log" "$SRC")"; then rc=0; fi
  rk "stub self-test: 4xx on the four bad requests, 200 on the good one, each logged" "$rc" "$o ${p:-}"
}
healthy_rk() { # the B1 check set, shared with B1-C (10 assertions)
  local out
  selftest_rk
  out="$(pred status_ok "$RD/f/status.json")"; rk "status done, errors []" $? "$out"
  out="$(pred trail --port 443 "$RD/capture-boot.log" "$SRC" "$HID" "${HEALTHY_TRAIL[@]}")"
  rk "trail runcmd_start, egress_load, cloud_init_complete, fresh_boot_ready in order; zero fatals; zero rejected; every event soleur-bastion/$HID on :443" $? "$out"
  out="$(pred datasource "$RD/f/status.json")"; rk "the datasource is NoCloud" $? "$out"
  out="$(pred sources_https "$RD/f/sources.out")"; rk "ubuntu.sources holds exactly the two https URIs and no other source file" $? "$out"
  rk "dpkg: curl, nftables and systemd-timesyncd installed" "$([ "$(grep -c ' install ok installed$' "$RD/f/pkgs.out" 2>/dev/null)" = 3 ]; echo $?)" "$(rf pkgs.out)"
  rk "/etc/nftables.conf equals /etc/soleur/bastion-nftables.conf" "$(rf conf.rc | grep -qx 0; echo $?)" "$(rf conf.out)"
  rk "nftables, bastion-egress and bastion-egress.timer active and enabled" "$([ "$(grep -cE '^[^ ]+ active enabled$' "$RD/f/units.out" 2>/dev/null)" = 3 ]; echo $?)" "$(rf units.out)"
  rk "ssh.service and ssh.socket masked" "$([ "$(grep -cx masked "$RD/f/ssh.out" 2>/dev/null)" = 2 ]; echo $?)" "$(rf ssh.out)"
  rk "every user the rules or IMAGE_ASSUMED name resolves (getent), systemd-timesync included" \
    "$(grep -q 'systemd-timesync ok' "$RD/f/users.out" 2>/dev/null && ! grep -q MISSING "$RD/f/users.out"; echo $?)" "$(rf users.out)"
}
closed() { [ "$(rf "probe-$1.rc")" = 28 ] && ! pred probe "$2" "$SRC" "/brh-probe/$1" >/dev/null; }
assert_B1() {
  healthy_rk
  rk "P7: the rendered private-ip stanza exits 0 with 10.0.1.70 on lo" "$(rc_is p7.present.rc 0; echo $?)" "rc=$(rf p7.present.rc)"
  rk "P7: ... and 124 (still waiting) after ip addr del" "$(rc_is p7.absent.rc 124; echo $?)" "rc=$(rf p7.absent.rc)"
  rk "B1-E liveness: from a neighbour, the stub's :80 and the decoy's :443 answer" \
    "$(grep -qxE 'live80 [1-5][0-9][0-9]' "$RD/f/selftest.out" && grep -qxE 'livedecoy [1-5][0-9][0-9]' "$RD/f/selftest.out"; echo $?)" "$(rf selftest.out)"
  rk "B1-E: soleur_egress_allow holds the pinned archive and security addresses and the stub" \
    "$(grep -qF "$ARCHIVE_IP" "$RD/f/set.out" && grep -qF "$SECURITY_IP" "$RD/f/set.out" && grep -qF "${SRC%.10}.20" "$RD/f/set.out"; echo $?)" "$(rf set.out)"
  rk "B1-E OPEN: root -> stub:443 (curl rc 0 and the stub logged it)" "$(rc_is probe-root443.rc 0 && pred probe "$RD/out/capture.log" "$SRC" /brh-probe/root443 >/dev/null; echo $?)" "rc=$(rf probe-root443.rc) $(rf probe-root443.err)"
  rk "B1-E OPEN: _apt -> stub:443 (curl rc 0 and the stub logged it)" "$(rc_is probe-apt443.rc 0 && pred probe "$RD/out/capture.log" "$SRC" /brh-probe/apt443 >/dev/null; echo $?)" "rc=$(rf probe-apt443.rc) $(rf probe-apt443.err)"
  rk "B1-E CLOSED: nobody -> stub:443 dropped (curl rc 28, nothing logged)" "$(closed nobody443 "$RD/out/capture.log"; echo $?)" "rc=$(rf probe-nobody443.rc) $(rf probe-nobody443.err)"
  rk "B1-E CLOSED: root -> stub:80 dropped (curl rc 28, nothing logged)" "$(closed root80 "$RD/out/capture.log"; echo $?)" "rc=$(rf probe-root80.rc) $(rf probe-root80.err)"
  rk "B1-E CLOSED: root -> decoy:443 dropped (curl rc 28, nothing logged)" "$(closed decoy443 "$RD/decoy/capture.log"; echo $?)" "rc=$(rf probe-decoy443.rc) $(rf probe-decoy443.err)"
  rk "B1-P: an nftables.service restart re-runs bastion-egress (new InvocationID) and the set is back within 10 s" "$(grep -q 'set_back=1' "$RD/f/partof.out" 2>/dev/null; echo $?)" "$(rf partof.out) $(rf restart.out)"
  rk "B1-P: bastion-egress-refresh.service exits 0" "$(rc_is refresh.rc 0; echo $?)" "rc=$(rf refresh.rc) $(rf refresh.out)"
}
assert_B1-C() { healthy_rk; }
assert_B2() {
  local out
  selftest_rk
  rk "the first boot took the reboot branch: reboot.log has exactly one line and the container stopped" \
    "$([ "$(grep -c reboot "$RD/f/reboot.out" 2>/dev/null)" = 1 ] && rc_is boot1.end exited; echo $?)" "reboot.log=[$(rf reboot.out)] boot1=$(rf boot1.end)"
  out="$(pred status_ok "$RD/f/status.json")"; rk "after docker start (boot two), status done, errors []" $? "$out"
  out="$(pred trail --port 443 "$RD/capture-boot.log" "$SRC" "$HID" "${REBOOT_TRAIL[@]}" count:runcmd_start=2 count:kernel_reboot=1)"
  rk "trail runcmd_start, kernel_reboot, runcmd_start, egress_load, cloud_init_complete, fresh_boot_ready; exactly 2 runcmd_start, 1 kernel_reboot; zero fatals" $? "$out"
  rk "/var/lib/soleur/kernel-settle exists" "$(rc_is settle.rc 0; echo $?)" "rc=$(rf settle.rc)"
  rk "the second boot ran on the settled kernel: boot one's cloud-init-output was copied and boot two ended terminal with no new reboot.log line" "$([ -s "$RD/cloud-init-output.boot1.log" ] && rc_is boot2.end terminal; echo $?)" "boot2=$(rf boot2.end)"
}
assert_M1() {
  local out
  selftest_rk
  out="$(pred fatal "$RD/capture-boot.log" "$SRC" "$HID" apt_install)"; rk "fatal fresh_boot_not_ready_apt_install" $? "$out"
  rk "cloud-init-output.log carries the dpkg conffile prompt" "$(grep -q 'conffile prompt' "$RD/cloud-init-output.log" 2>/dev/null; echo $?)"
  out="$(pred absent "$RD/capture-boot.log" "$SRC" "$HID" egress_load)"; rk "no egress_load event" $? "$out"
}
assert_M2() {
  local out
  selftest_rk
  out="$(pred sources_http "$RD/f/sources.out")"; rk "cc_apt_configure rewrote ubuntu.sources to http://" $? "$out"
  out="$(pred fatal "$RD/capture-boot.log" "$SRC" "$HID" apt_update,apt_install,apt_path)"; rk "a fatal at apt_update, apt_install or apt_path" $? "$out"
  out="$(pred absent "$RD/capture-boot.log" "$SRC" "$HID" "$ST_READY")"; rk "no fresh_boot_ready" $? "$out"
}
assert_F1() {
  local out
  selftest_rk
  out="$(pred fatal "$RD/capture-boot.log" "$SRC" "$HID" egress_load 'lookup failed for nx-ingest.invalid')"
  rk "fatal fresh_boot_not_ready_egress_load reached the stub (the flush ran); its detail names 'lookup failed for nx-ingest.invalid'" $? "$out"
  rk "the ruleset is empty after the fatal (on_err flushed it)" "$(rc_is ruleset.rc 0 && ! grep -q '^table' "$RD/f/ruleset.out"; echo $?)" "$(head -c 300 "$RD/f/ruleset.out" 2>/dev/null)"
}
assert_F1-M() {
  local out
  selftest_rk
  rk "status error" "$([ "$(pred status "$RD/f/status.json")" = error ]; echo $?)" "status=$(pred status "$RD/f/status.json")"
  out="$(pred nofatal_last "$RD/capture-boot.log" "$SRC" "$HID" egress_load)"; rk "no fatal reached the stub; the capture ends at egress_load" $? "$out"
  rk "the baseline's drop chain is still loaded and holds no stub address" \
    "$(grep -q 'chain output' "$RD/f/ruleset.out" 2>/dev/null && grep -q 'policy drop' "$RD/f/ruleset.out" && ! grep -qF "${SRC%.10}.20" "$RD/f/ruleset.out"; echo $?)" "$(head -c 300 "$RD/f/ruleset.out" 2>/dev/null)"
  rk "the emit path is blocked: root curl to the ingest host is dropped (rc 28)" "$(rc_is emit.rc 28; echo $?)" "rc=$(rf emit.rc) $(rf emit.out)"
}
assert_FA() {
  local out
  selftest_rk
  out="$(pred fatal "$RD/capture-boot.log" "$SRC" "$HID" egress_load 'User does not exist')"
  rk "fatal fresh_boot_not_ready_egress_load; its detail carries nft's 'User does not exist'" $? "$out"
}
for ROW in "${ROWS[@]}"; do
  selected "$ROW" || continue
  RD="$WORK/rows/$ROW"; SRC="198.18.${ROW_K[$ROW]:-0}.10"; HID="i-brh-$ROW"
  if [ -n "$SKIP_ALL" ]; then
    cases=$((cases + ROW_CASES[$ROW])); SKIPPED_ASSERTIONS=$((SKIPPED_ASSERTIONS + ROW_CASES[$ROW])); SKIPPED_ROWS+=("$ROW"); ROWS_SKIPPED_UNBOOTED=$((ROWS_SKIPPED_UNBOOTED + 1))
    printf 'SKIP (loud): %s %s\n' "$ROW" "$SKIP_ALL"; continue
  fi
  [ -s "$RD/cloud-init-output.log" ] && ROWS_BOOTED=$((ROWS_BOOTED + 1))
  "assert_$ROW"
  flush_row
done

# ── Verdict (ADR-193 floor and identity, ADR-188 skip accounting, CTO Q7/Q17/Q28) ───────────────
if is_ci; then
  _b1s=0; for r in "${SKIPPED_ROWS[@]}"; do [ "$r" = B1 ] && _b1s=1; done
  if [ "${#SKIPPED_ROWS[@]}" -gt 2 ] || [ "$_b1s" -eq 1 ]; then
    printf 'BRH_SKIP_CEILING: %d row(s) skipped (%s) under CI; the ceiling is 2 and B1 may never skip\n' "${#SKIPPED_ROWS[@]}" "${SKIPPED_ROWS[*]}" >&2
    die_verdict BRH_SKIP_CEILING
  fi
fi
if [ $((ROWS_BOOTED + ROWS_SKIPPED_UNBOOTED)) -ne "${#SELECTED[@]}" ]; then
  die_verdict "rows booted $ROWS_BOOTED + skipped unbooted $ROWS_SKIPPED_UNBOOTED != rows selected ${#SELECTED[@]}"
fi
if [ -n "$PARTIAL" ]; then
  BRH_PARTIAL_MIN=$STATIC_CASES; for r in "${SELECTED[@]}"; do BRH_PARTIAL_MIN=$((BRH_PARTIAL_MIN + ROW_CASES[$r])); done
fi
# 81 static assertions + 55 row assertions (B1 21, B2 6, M1 4, M2 4, F1 3, F1-M 5, FA 2, B1-C 10); a
# subset run (PARTIAL only) floors at BRH_PARTIAL_MIN, folded into the condition so the literal stays adjacent.
MIN_CASES=136
if [ $(( ${passes:-0} + ${fails:-0} + ${SKIPPED_ASSERTIONS:-0} )) -lt "${BRH_PARTIAL_MIN:-$MIN_CASES}" ]; then
  VERDICT_REASON="floor: too few assertions ran"
  printf 'bastion-runcmd-rehearsal: FAIL (only %d assertions ran or were skipped; floor %d)\n' "$(( ${passes:-0} + ${fails:-0} + ${SKIPPED_ASSERTIONS:-0} ))" "${BRH_PARTIAL_MIN:-$MIN_CASES}" >&2; exit 1
fi
if [ $((passes + fails + SKIPPED_ASSERTIONS)) -ne "$cases" ]; then
  VERDICT_REASON="accounting: passes + fails + skipped != cases"
  printf 'bastion-runcmd-rehearsal: FAIL (accounting: passes %d + fails %d + skipped %d != cases %d)\n' "$passes" "$fails" "$SKIPPED_ASSERTIONS" "$cases" >&2; exit 1
fi
gd_apt_state_summary
printf 'wall: %ss (deadline %ss)\n' "$SECONDS" "$DEADLINE_S"
if [ "${#FAILURES[@]}" -gt 0 ]; then
  printf 'bastion-runcmd-rehearsal: FAIL (%d of %d assertions failed)\n' "${#FAILURES[@]}" "$cases" >&2; exit 1
fi
if [ -n "$PARTIAL" ]; then printf 'bastion-runcmd-rehearsal: PARTIAL (%s; %d assertions, 0 failed)\n' "$PARTIAL" "$cases"; exit 0; fi
# A run that skipped any boot row is never a PASS (CTO Q7): it ends SKIP, naming the rows.
# A SKIP exits 0 only on pull_request and push (CTO Q28): on a gate event it is a FAIL.
if [ "${#SKIPPED_ROWS[@]}" -gt 0 ]; then
  if [ -n "${GITHUB_ACTIONS:-}" ]; then
    printf '::warning title=bastion-boot-rehearsal SKIP::%d of %d boot rows skipped (%s); this run is not a PASS (CTO Q7)\n' \
      "${#SKIPPED_ROWS[@]}" "${#SELECTED[@]}" "${SKIPPED_ROWS[*]}"
  fi
  printf 'bastion-runcmd-rehearsal: SKIP (%d of %d boot rows skipped: %s; %d assertions skipped, 0 failed)\n' \
    "${#SKIPPED_ROWS[@]}" "${#SELECTED[@]}" "${SKIPPED_ROWS[*]}" "$SKIPPED_ASSERTIONS"
  if _skip_is_failure; then
    printf 'BRH_SKIP_ON_GATE_EVENT: event=%s rows=%s\n' "${GITHUB_EVENT_NAME:-unset}" "${SKIPPED_ROWS[*]}" >&2
    die_verdict BRH_SKIP_ON_GATE_EVENT
  fi
  exit 0
fi
printf 'bastion-runcmd-rehearsal: PASS (%d assertions, 0 failed)\n' "$cases"
