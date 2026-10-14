#!/usr/bin/env bash
# Behavioural suite for /usr/local/bin/soleur-inngest-nic-wait and the static networkd fallback
# /etc/systemd/network/99-soleur-private-fallback.network (#8539, plan
# knowledge-base/project/plans/2026-09-22-fix-inngest-private-nic-boot-race-plan.md, Guard 2 and
# Test Scenarios 1-17).
#
# WHAT IS UNDER TEST IS THE RENDERED BYTES. inngest-userdata-budget.sh renders
# cloud-init-inngest.yml with terraform's own templatefile() and applies
# local.inngest_rationale_strip (extracted from inngest-host.tf), which is what Hetzner stores and
# the host executes. The strip deletes `#`-prefixed lines INSIDE block scalars too, so reading the
# helper out of the source YAML would test bytes that never reach the host. The helper and the
# .network file are pulled from the rendered write_files with yaml.safe_load. A render or
# extraction failure aborts the suite (exit 2); it never skips.
#
# HOW THE HELPER IS DRIVEN. `env -i` with PATH = a per-case stub dir + a tools dir holding
# symlinks to the REAL grep/awk/sed/tr/cut/wc/readlink/basename/head/cat. Not /usr/bin: on a
# merged-/usr host /usr/bin/ip and /usr/bin/networkctl are real, so scenarios 6 and 7 ("missing
# from PATH") could not be expressed. Every stub logs its argv. The `ip` and `networkctl` stubs
# dispatch on their FULL argv and exit 64 on anything else (recorded in unexpected.log, which
# every scenario requires empty), so a changed query cannot silently hit a default branch.
# SOLEUR_NICWAIT_ROOT is the helper's seam for /proc and /sys reads.
#
# FIXTURE PROVENANCE.
#   * `networkctl --no-pager status <if>`: the systemd 255 per-link table. The row this helper
#     reads is TABLE_FIELD "Network File", whose value is the link's network file path or "n/a"
#     for an unmanaged link (systemd v255 src/network/networkctl.c, link_status_one). It is
#     right-aligned, hence the leading spaces.
#   * `networkctl --no-pager --no-legend list`: columns IDX LINK TYPE OPERATIONAL SETUP, rows as
#     recorded from real systemd 261 `networkctl list` (e.g. `  3 enp7s0 ether    off      unmanaged`).
#   * `ip -4 -o addr show`: iproute2 one-line form, `N: <if>    inet <a>/<p> ... <if>\       valid_lft ...`.
#
# Run: bash apps/web-platform/infra/inngest-nic-wait.test.sh
# Stub bodies and eval'd checks are single-quoted on purpose: they expand later, in the stub/check.
# shellcheck disable=SC2016
set -euo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

# NICWAIT_INFRA_DIR / NICWAIT_SUITE_BATTERY are this suite's OWN seams, used only by mutation
# row 10, which runs a copy of this file from outside the infra dir with the battery disabled.
SCRIPT_DIR="${NICWAIT_INFRA_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
RUN_BATTERY="${NICWAIT_SUITE_BATTERY:-1}"
SELF="${BASH_SOURCE[0]}"

PASS=0
FAIL=0
cases=0
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

die2() { printf '[FATAL] %s\n' "$1" >&2; exit 2; }
harness() { printf '[FATAL] HARNESS ERROR: %s\n' "$1" >&2; exit 2; }

# --- instrument self-test: pass() and fail() must each move their own counter ----------------
_p0=$PASS; _f0=$FAIL
pass "self-test: pass arm" >/dev/null
fail "self-test: fail arm" >/dev/null
if [[ "$PASS" -ne $((_p0 + 1)) || "$FAIL" -ne $((_f0 + 1)) ]]; then
  printf '[FATAL] instrument self-test: pass/fail did not record one pass and one fail (PASS %s->%s, FAIL %s->%s)\n' \
    "$_p0" "$PASS" "$_f0" "$FAIL" >&2
  exit 2
fi
PASS=0; FAIL=0

# Canonical fixture-root guard, copied BYTE-FOR-BYTE (fixture-relative-assert.test.sh pins this
# form; an inline `case` of my own is not recognised). Every write below lands under $WORK, and
# `rm -rf` on a relative or degenerate root is the accident it exists to refuse.
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

WORK="$(mktemp -d "$TMPDIR/inngest-nic-wait.XXXXXXXX")" || die2 "mktemp failed"
assert_fixture_dir "$WORK"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

echo "--- #8539: soleur-inngest-nic-wait + 99-soleur-private-fallback.network ---"

# --- 1. render (stripped) and extract -------------------------------------------------------
command -v terraform >/dev/null 2>&1 || die2 "terraform is not on PATH; the helper can only be extracted from the RENDERED user_data, so this suite cannot run (refusing to skip)"
command -v python3 >/dev/null 2>&1 || die2 "python3 is not on PATH (needed for yaml.safe_load extraction)"
python3 -c 'import yaml' 2>/dev/null || die2 "python3 has no yaml module (needed for yaml.safe_load extraction)"

RENDER="$WORK/rendered.yml"
BUDGET_RC=0
bash "$SCRIPT_DIR/inngest-userdata-budget.sh" "$RENDER" >"$WORK/budget.out" 2>&1 || BUDGET_RC=$?
# 0 = under cap, 1 = over cap (still rendered; the size gate is a separate job). 2 = unmeasurable.
if [[ "$BUDGET_RC" -ne 0 && "$BUDGET_RC" -ne 1 ]]; then
  cat "$WORK/budget.out" >&2
  die2 "inngest-userdata-budget.sh failed to render (rc=$BUDGET_RC)"
fi
[[ -s "$RENDER" ]] || { cat "$WORK/budget.out" >&2; die2 "the stripped render is empty"; }
[[ "$(head -n 1 "$RENDER")" == "#cloud-config" ]] || die2 "the stripped render does not start with #cloud-config"

HELPER="$WORK/soleur-inngest-nic-wait"
NETFILE="$WORK/99-soleur-private-fallback.network"
EXPFILE="$WORK/expected-ip"
python3 - "$RENDER" "$HELPER" "$NETFILE" "$EXPFILE" <<'PY' || die2 "extraction from the rendered write_files/runcmd failed"
import re, sys, yaml
render, helper, netfile, expfile = sys.argv[1:5]
doc = yaml.safe_load(open(render))
wf = doc.get("write_files") or []
def one(path):
    hits = [w for w in wf if w.get("path") == path]
    if len(hits) != 1:
        sys.exit("expected exactly one write_files entry for %s, found %d" % (path, len(hits)))
    return hits[0]
h = one("/usr/local/bin/soleur-inngest-nic-wait")
n = one("/etc/systemd/network/99-soleur-private-fallback.network")
if str(h.get("permissions")) != "0755":
    sys.exit("helper permissions are %r, expected '0755'" % h.get("permissions"))
open(helper, "w").write(h["content"])
open(netfile, "w").write(n["content"])
calls = []
for item in doc.get("runcmd") or []:
    if isinstance(item, str):
        m = re.fullmatch(r"/usr/local/bin/soleur-inngest-nic-wait (\S+) \|\| true", item.strip())
        if m:
            calls.append(m.group(1))
if len(calls) != 1:
    sys.exit("expected exactly one rendered runcmd call of the helper, found %d" % len(calls))
open(expfile, "w").write(calls[0])
PY
chmod +x "$HELPER"
[[ -s "$HELPER" ]] || die2 "extracted helper is empty"
[[ "$(head -n 1 "$HELPER")" == "#!/bin/sh" ]] || die2 "extracted helper does not start with #!/bin/sh"
sh -n "$HELPER" || die2 "extracted helper is not valid sh"
EXP_IP="$(cat "$EXPFILE")"
[[ "$EXP_IP" == "10.0.1.40" ]] || die2 "rendered helper argument is '$EXP_IP', expected the Terraform-bound 10.0.1.40"
PRISTINE="$WORK/helper.pristine"
cp "$HELPER" "$PRISTINE"

# --- tools dir (real utilities only; no ip / networkctl / sleep / systemctl) ---------------------
TOOLS="$WORK/tools"
mkdir -p "$TOOLS"
for t in grep awk sed tr cut wc readlink basename head cat; do
  real="$(command -v "$t")" || die2 "real '$t' not found"
  ln -s "$real" "$TOOLS/$t"
done
# The helper appends /usr/local/bin when it is not on PATH. Nothing there may shadow a stub.
for t in ip networkctl sleep soleur-boot-emit inngest-boot-phone-home.sh reboot poweroff shutdown halt systemctl curl date; do
  [[ ! -e "/usr/local/bin/$t" ]] || harness "/usr/local/bin/$t exists on this runner and would leak into the helper's PATH"
done

# --- stubs ---------------------------------------------------------------------------------------
STUBS="$WORK/stubs"
mkdir -p "$STUBS"
LOGLINE='{ printf "%s" "$(basename "$0")"; for a in "$@"; do printf " %s" "$a"; done; printf "\n"; } >> "$STUB_CASE/calls.log"'
write_stub() { # <name> <body>
  { printf '#!/bin/sh\n'; printf '%s\n' "$LOGLINE"; printf '%s\n' "$2"; } > "$STUBS/$1"
  chmod +x "$STUBS/$1"
}
# ip: full-argv dispatch. `-4 -o addr show` counts its own calls; the found line is included from
# call number (appear_after + 1) on, so appear_after=K models "present after K sleeps".
write_stub ip '
C="$STUB_CASE"
sig=""; for a in "$@"; do sig="$sig$a|"; done
rc=0; [ -f "$C/fx/ip_rc" ] && read -r rc < "$C/fx/ip_rc"
case "$sig" in
  "-4|-o|addr|show|")
    n=0; [ -f "$C/state/addr_calls" ] && read -r n < "$C/state/addr_calls"
    n=$((n + 1)); printf "%s\n" "$n" > "$C/state/addr_calls"
    if [ -f "$C/fx/ip_rc_seq" ]; then
      read -r seq < "$C/fx/ip_rc_seq"
      rc=$(printf "%s " $seq | cut -d" " -f"$n")
      [ -n "$rc" ] || rc=0
    fi
    [ "$rc" -eq 0 ] || exit "$rc"
    cat "$C/fx/addr_base"
    read -r k < "$C/fx/appear_after"
    if [ "$k" -ge 0 ] && [ "$n" -gt "$k" ]; then cat "$C/fx/addr_found"; fi
    exit 0 ;;
  "route|get|1.1.1.1|")
    [ "$rc" -eq 0 ] || exit "$rc"
    read -r d < "$C/fx/route_dev"
    printf "1.1.1.1 via 172.31.1.1 dev %s src 203.0.113.10 uid 0 \n    cache \n" "$d"
    exit 0 ;;
  "-4|-o|addr|show|dev|"*"|")
    [ "$rc" -eq 0 ] || exit "$rc"
    [ "$#" -eq 6 ] || { printf "ip %s\n" "$sig" >> "$C/unexpected.log"; exit 64; }
    f="$C/fx/addr_dev_$6"
    [ -f "$f" ] && cat "$f"
    exit 0 ;;
esac
printf "ip %s\n" "$sig" >> "$C/unexpected.log"
exit 64'
write_stub networkctl '
C="$STUB_CASE"
sig=""; for a in "$@"; do sig="$sig$a|"; done
case "$sig" in
  "--no-pager|status|"*"|")
    if [ "$#" -eq 3 ]; then
      f="$C/fx/nc_status_$3"
      if [ -f "$f" ]; then cat "$f"; exit 0; fi
      printf "Interface \"%s\" not found.\n" "$3" >&2; exit 1
    fi ;;
  "--no-pager|--no-legend|list|")
    cat "$C/fx/nc_list"; exit 0 ;;
esac
printf "networkctl %s\n" "$sig" >> "$C/unexpected.log"
exit 64'
write_stub sleep ':'
for s in reboot poweroff shutdown halt systemctl curl date; do write_stub "$s" ':'; done
# The two channels: one argv per line, fields tab-joined.
write_stub inngest-boot-phone-home.sh '{ printf "%s" "$1"; shift; for a in "$@"; do printf "\t%s" "$a"; done; printf "\n"; } >> "$STUB_CASE/bs.log"'
write_stub soleur-boot-emit '{ printf "%s" "$1"; shift; for a in "$@"; do printf "\t%s" "$a"; done; printf "\n"; } >> "$STUB_CASE/sentry.log"'

# --- case fixtures -------------------------------------------------------------------------------
BOOT_ID="3f2a9c1e-7b4d-4e8a-9c2b-1d5e6f7a8b9c"
BOOT8="3f2a9c1e"
CASE_N=0
C=""
ADDR_LO='1: lo    inet 127.0.0.1/8 scope host lo\       valid_lft forever preferred_lft forever'
ADDR_ETH0='2: eth0    inet 203.0.113.10/32 metric 100 scope global dynamic eth0\       valid_lft 85841sec preferred_lft 85841sec'
found_line() { # <if> <idx> [addr]
  printf '%s: %s    inet %s/32 metric 1024 scope global dynamic %s\\       valid_lft 86389sec preferred_lft 86389sec\n' \
    "$2" "$1" "${3:-$EXP_IP}" "$1"
}
new_case() { # <name>
  CASE_N=$((CASE_N + 1))
  C="$WORK/case.$CASE_N.$1"
  mkdir -p "$C/bin" "$C/fx" "$C/state" "$C/run" "$C/root/proc/sys/kernel/random" "$C/root/sys/class/net/lo"
  cp -p "$STUBS"/* "$C/bin/"
  printf '%s\n' "$BOOT_ID" > "$C/root/proc/sys/kernel/random/boot_id"
  printf '%s\n%s\n' "$ADDR_LO" "$ADDR_ETH0" > "$C/fx/addr_base"
  : > "$C/fx/addr_found"
  echo -1 > "$C/fx/appear_after"
  echo eth0 > "$C/fx/route_dev"
  printf '  1 lo     loopback carrier  unmanaged\n  2 eth0   ether    routable configured\n' > "$C/fx/nc_list"
  add_link eth0 virtio_net
}
add_link() { # <if> <driver|"">
  mkdir -p "$C/root/sys/class/net/$1/device"
  [[ -z "$2" ]] || ln -s "../../../../bus/pci/drivers/$2" "$C/root/sys/class/net/$1/device/driver"
}
nc_list_row() { printf '  %s %-6s ether    %-8s %s\n' "$1" "$2" "$3" "$4" >> "$C/fx/nc_list"; }
appear_after() { echo "$1" > "$C/fx/appear_after"; }
nc_status() { # <if> <network file path | n/a | NOLINE>
  local state="routable (configured)" nfline
  nfline="                Network File: $2"
  [[ "$2" == "n/a" ]] && state="off (unmanaged)"
  [[ "$2" == "NOLINE" ]] && { nfline=""; state="off (unmanaged)"; }
  {
    printf '● 3: %s\n' "$1"
    printf '                   Link File: /usr/lib/systemd/network/99-default.link\n'
    [[ -z "$nfline" ]] || printf '%s\n' "$nfline"
    printf '                       State: %s\n' "$state"
    printf '                Online state: online\n'
    printf '                        Type: ether\n'
    printf '                        Path: pci-0000:07:00.0\n'
    printf '                      Driver: virtio_net\n'
    printf '                  HW Address: 86:00:00:5a:1b:2c\n'
    printf '                         MTU: 1450 (min: 68, max: 65535)\n'
  } > "$C/fx/nc_status_$1"
}

# --- run + invariants ----------------------------------------------------------------------------
HUT="$HELPER"   # helper under test; the battery points it at a mutant
RC=0; BS_N=0; SE_N=0; BS_STAGE=""; BS_DETAIL=""; SE_STAGE=""; SE_LEVEL=""; SE_DETAIL=""; SE_ARGC=0; BS_ARGC=0
SLEEPS=0; ADDR_CALLS=0
runs=0
invariant_runs=0
snapshot_root() { (cd "$C/root" && find . -printf '%p %y %l\n' | LC_ALL=C sort && find . -type f -exec cat {} +) | md5sum; }
run_helper() { # <arg>
  local before after
  before="$(snapshot_root)"
  RC=0
  (cd "$C/run" && env -i PATH="$C/bin:$TOOLS" SOLEUR_NICWAIT_ROOT="$C/root" STUB_CASE="$C" \
    /bin/sh "$HUT" "$1") >"$C/out" 2>"$C/err" || RC=$?
  after="$(snapshot_root)"
  [[ "$before" == "$after" ]] && echo same > "$C/state/root" || echo changed > "$C/state/root"
  runs=$((runs + 1))
  touch "$C/calls.log" "$C/bs.log" "$C/sentry.log" "$C/unexpected.log"
  BS_N=$(wc -l < "$C/bs.log"); SE_N=$(wc -l < "$C/sentry.log")
  BS_STAGE=$(awk -F'\t' 'NR==1{print $1}' "$C/bs.log")
  BS_DETAIL=$(awk -F'\t' 'NR==1{print $2}' "$C/bs.log")
  BS_ARGC=$(awk -F'\t' 'NR==1{print NF}' "$C/bs.log")
  SE_STAGE=$(awk -F'\t' 'NR==1{print $1}' "$C/sentry.log")
  SE_LEVEL=$(awk -F'\t' 'NR==1{print $2}' "$C/sentry.log")
  SE_DETAIL=$(awk -F'\t' 'NR==1{print $3}' "$C/sentry.log")
  SE_ARGC=$(awk -F'\t' 'NR==1{print NF}' "$C/sentry.log")
  SLEEPS=$(awk '$1=="sleep"{n++} END{print n+0}' "$C/calls.log")
  ADDR_CALLS=0; [[ -f "$C/state/addr_calls" ]] && ADDR_CALLS=$(cat "$C/state/addr_calls")
  return 0
}

# ck <desc> <command...>: in the main pass, one verdict through pass()/fail() and one `cases`
# increment here at the call site; in QUIET (mutation) mode only SCEN_RED is set.
QUIET=0
SCEN_RED=0
RED_WHY=""
ck() {
  local d="$1"; shift
  if [[ "$QUIET" -eq 1 ]]; then
    "$@" || { SCEN_RED=1; RED_WHY="$RED_WHY | $d"; }
    return 0
  fi
  cases=$((cases + 1))
  if "$@"; then pass "$d"; else fail "$d"; fi
}
eq() { [[ "$1" == "$2" ]]; }
num() { [[ "$1" -eq "$2" ]]; }

# ck() SELF-TEST. The pass/fail check above proves the COUNTERS move; it says nothing about the
# helper that DECIDES which one to call. Every scenario assertion routes through ck(), so a ck()
# that always takes the pass branch is invisible to the counters, to the conservation check and
# to MIN_SCENARIO_CHECKS alike -- measured at review: 368 passed, 0 failed, exit 0, with every
# assertion neutered. Drive it with a predicate that MUST fail and require FAIL to move.
_ck_p=$PASS; _ck_f=$FAIL
ck "instrument self-test: ck() must be able to REJECT" eq "soleur-a" "soleur-b" >/dev/null
if [[ "$FAIL" -ne $((_ck_f + 1)) || "$PASS" -ne "$_ck_p" ]]; then
  printf '[FATAL] instrument self-test: ck() did not record a failure for a false predicate (PASS %s->%s, FAIL %s->%s)\n' \
    "$_ck_p" "$PASS" "$_ck_f" "$FAIL" >&2
  exit 1
fi
# The self-test spent one verdict and one case; unwind all three so the floors stay exact.
PASS=$_ck_p; FAIL=$_ck_f; cases=$((cases - 1))
detail_clean() { # <detail>: <=120, only A-Za-z0-9=.:_-, starts boot=<8>.
  local d="$1"
  [[ ${#d} -le 120 ]] && [[ "$d" =~ ^[A-Za-z0-9=.:_-]+$ ]] && [[ "$d" == "boot=$BOOT8."* ]]
}
no_forbidden() {
  ! awk '$1=="reboot"||$1=="poweroff"||$1=="shutdown"||$1=="halt"{f=1}
         $1=="systemctl"&&($2~/reboot|poweroff|halt|kexec/){f=1}
         $1=="networkctl"&&($0~/ reload/||$0~/ reconfigure/||$0~/ up/||$0~/ down/){f=1}
         END{exit !f}' "$C/calls.log"
}
file_empty() { [[ ! -s "$1" ]]; }
dir_empty() { [[ -z "$(ls -A "$1")" ]]; }

# Scenario 11's invariants, applied to EVERY helper run.
invariants() { # <tag>
  invariant_runs=$((invariant_runs + 1))
  ck "$1: exit 0 (fail-open)" num "$RC" 0
  ck "$1: exactly one Better Stack event (got $BS_N)" num "$BS_N" 1
  ck "$1: exactly one Sentry event (got $SE_N)" num "$SE_N" 1
  ck "$1: Better Stack call is <stage> <detail> (argc $BS_ARGC)" num "$BS_ARGC" 2
  ck "$1: Sentry call is <stage> <level> <detail> (argc $SE_ARGC)" num "$SE_ARGC" 3
  ck "$1: same stage on both channels" eq "$BS_STAGE" "$SE_STAGE"
  ck "$1: detail byte-identical on both channels" eq "$BS_DETAIL" "$SE_DETAIL"
  ck "$1: detail <=120 chars, charset A-Za-z0-9=.:_-, starts boot=$BOOT8. ('$SE_DETAIL')" detail_clean "$SE_DETAIL"
  ck "$1: level is info or warning" eval '[[ "$SE_LEVEL" == info || "$SE_LEVEL" == warning ]]'
  ck "$1: no reboot/poweroff/shutdown/networkctl reload|reconfigure in the call log" no_forbidden
  ck "$1: no stub saw an unexpected argv" file_empty "$C/unexpected.log"
  ck "$1: helper wrote no file in its cwd" dir_empty "$C/run"
  ck "$1: helper left the /proc,/sys test root untouched" eq "$(cat "$C/state/root")" same
}

# --- scenarios -----------------------------------------------------------------------------------
present_on_enp7s0() { # <appear_after> <network file>
  add_link enp7s0 virtio_net
  nc_list_row 3 enp7s0 routable configured
  found_line enp7s0 3 > "$C/fx/addr_found"
  appear_after "$1"
  nc_status enp7s0 "$2"
}
NETPLAN7=/run/systemd/network/10-netplan-enp7s0.network
FALLBACK=/etc/systemd/network/99-soleur-private-fallback.network

s1() {
  new_case s1; present_on_enp7s0 0 "$NETPLAN7"; run_helper "$EXP_IP"; invariants s1
  ck "s1: stage private_nic_ok" eq "$SE_STAGE" private_nic_ok
  ck "s1: level info" eq "$SE_LEVEL" info
  ck "s1: detail exact ('$SE_DETAIL')" eq "$SE_DETAIL" "boot=$BOOT8.waited_s=0.by=10-netplan-enp7s0.egress=eth0"
  ck "s1: 0 sleeps (got $SLEEPS)" num "$SLEEPS" 0
}
s2() {
  new_case s2; present_on_enp7s0 3 "$NETPLAN7"; run_helper "$EXP_IP"; invariants s2
  ck "s2: stage private_nic_ok" eq "$SE_STAGE" private_nic_ok
  ck "s2: level info" eq "$SE_LEVEL" info
  ck "s2: detail waited_s=6 by netplan ('$SE_DETAIL')" eq "$SE_DETAIL" "boot=$BOOT8.waited_s=6.by=10-netplan-enp7s0.egress=eth0"
  ck "s2: exactly 3 sleeps (got $SLEEPS)" num "$SLEEPS" 3
  ck "s2: exactly 4 address probes (got $ADDR_CALLS)" num "$ADDR_CALLS" 4
}
s3() {
  new_case s3; present_on_enp7s0 5 "$FALLBACK"; run_helper "$EXP_IP"; invariants s3
  ck "s3: stage private_nic_ok" eq "$SE_STAGE" private_nic_ok
  ck "s3: level warning (fallback healed a race)" eq "$SE_LEVEL" warning
  ck "s3: detail by=99-soleur-private-fallback ('$SE_DETAIL')" eq "$SE_DETAIL" "boot=$BOOT8.waited_s=10.by=99-soleur-private-fallback.egress=eth0"
  ck "s3: exactly 5 sleeps (got $SLEEPS)" num "$SLEEPS" 5
}
s3b() {
  new_case s3b; present_on_enp7s0 0 "$FALLBACK"; run_helper "$EXP_IP"; invariants s3b
  ck "s3b: stage private_nic_ok" eq "$SE_STAGE" private_nic_ok
  ck "s3b: level WARNING even at waited_s=0" eq "$SE_LEVEL" warning
  ck "s3b: detail ('$SE_DETAIL')" eq "$SE_DETAIL" "boot=$BOOT8.waited_s=0.by=99-soleur-private-fallback.egress=eth0"
}
s3c() {
  new_case s3c; present_on_enp7s0 0 "n/a"; run_helper "$EXP_IP"; invariants s3c
  ck "s3c: stage private_nic_ok" eq "$SE_STAGE" private_nic_ok
  ck "s3c: level info" eq "$SE_LEVEL" info
  ck "s3c: Network File n/a -> by=none ('$SE_DETAIL')" eq "$SE_DETAIL" "boot=$BOOT8.waited_s=0.by=none.egress=eth0"
  new_case s3c-noline; present_on_enp7s0 0 NOLINE; run_helper "$EXP_IP"; invariants s3c-noline
  ck "s3c: no Network File row at all -> by=none ('$SE_DETAIL')" eq "$SE_DETAIL" "boot=$BOOT8.waited_s=0.by=none.egress=eth0"
}
s4() {
  new_case s4
  add_link enp7s0 virtio_net; add_link docker0 ""; add_link veth1a2b3c4 ""; add_link br-0f3e9a1b ""
  nc_list_row 3 enp7s0 off unmanaged
  printf '4: docker0    inet 172.17.0.1/16 brd 172.17.255.255 scope global docker0\\       valid_lft forever preferred_lft forever\n' >> "$C/fx/addr_base"
  run_helper "$EXP_IP"; invariants s4
  ck "s4: stage private_nic_timeout" eq "$SE_STAGE" private_nic_timeout
  ck "s4: level warning" eq "$SE_LEVEL" warning
  ck "s4: detail links=enp7s0:unmanaged:virtio_net:nov4, docker/veth/br- excluded ('$SE_DETAIL')" \
    eq "$SE_DETAIL" "boot=$BOOT8.waited_s=150.links=enp7s0:unmanaged:virtio_net:nov4"
  ck "s4: exactly 75 sleeps (got $SLEEPS)" num "$SLEEPS" 75
  ck "s4: exactly 75 address probes (got $ADDR_CALLS)" num "$ADDR_CALLS" 75
}
s5() {
  new_case s5; add_link docker0 ""
  run_helper "$EXP_IP"; invariants s5
  ck "s5: stage private_nic_timeout" eq "$SE_STAGE" private_nic_timeout
  ck "s5: links=none ('$SE_DETAIL')" eq "$SE_DETAIL" "boot=$BOOT8.waited_s=150.links=none"
}
s6() {
  new_case s6-present; present_on_enp7s0 0 "$NETPLAN7"; rm "$C/bin/networkctl"
  run_helper "$EXP_IP"; invariants s6-present
  ck "s6: networkctl missing, present -> ok" eq "$SE_STAGE" private_nic_ok
  ck "s6: by=nonetworkctl ('$SE_DETAIL')" eq "$SE_DETAIL" "boot=$BOOT8.waited_s=0.by=nonetworkctl.egress=eth0"
  new_case s6-absent; add_link enp7s0 virtio_net; rm "$C/bin/networkctl"
  run_helper "$EXP_IP"; invariants s6-absent
  ck "s6: networkctl missing, absent -> timeout" eq "$SE_STAGE" private_nic_timeout
  ck "s6: links=nonetworkctl ('$SE_DETAIL')" eq "$SE_DETAIL" "boot=$BOOT8.waited_s=150.links=nonetworkctl"
}
s7() {
  new_case s7; present_on_enp7s0 0 "$NETPLAN7"; rm "$C/bin/ip"
  [[ -z "$(env -i PATH="$C/bin:$TOOLS:/usr/local/bin" /bin/sh -c 'command -v ip' || true)" ]] \
    || harness "s7: an 'ip' is still resolvable with the stub removed; scenario 7 would be vacuous"
  run_helper "$EXP_IP"; invariants s7
  ck "s7: ip missing -> private_nic_probe_fault" eq "$SE_STAGE" private_nic_probe_fault
  ck "s7: detail reason=noip ('$SE_DETAIL')" eq "$SE_DETAIL" "boot=$BOOT8.waited_s=0.reason=noip"
  ck "s7: 0 sleeps (got $SLEEPS)" num "$SLEEPS" 0
}
s8() {
  new_case s8; present_on_enp7s0 0 "$NETPLAN7"; echo 1 > "$C/fx/ip_rc"
  run_helper "$EXP_IP"; invariants s8
  ck "s8: ip rc=1 -> private_nic_probe_fault, not timeout" eq "$SE_STAGE" private_nic_probe_fault
  ck "s8: detail reason=iprc ('$SE_DETAIL')" eq "$SE_DETAIL" "boot=$BOOT8.waited_s=150.reason=iprc"
  ck "s8: the full budget was spent before faulting (got $SLEEPS)" num "$SLEEPS" 75
}
s9() {
  new_case s9; present_on_enp7s0 0 "$NETPLAN7"
  run_helper ""; invariants s9
  ck "s9: empty argument -> private_nic_probe_fault" eq "$SE_STAGE" private_nic_probe_fault
  ck "s9: detail reason=noarg ('$SE_DETAIL')" eq "$SE_DETAIL" "boot=$BOOT8.waited_s=0.reason=noarg"
}
s10() {
  new_case s10; add_link enp7s0 virtio_net; nc_list_row 3 enp7s0 routable configured
  found_line enp7s0 3 > "$C/fx/addr_found"; appear_after 0; nc_status enp7s0 "$NETPLAN7"
  found_line enp7s0 3 > "$C/fx/addr_dev_enp7s0"
  run_helper "10.0.1.4"; invariants s10
  ck "s10: expected 10.0.1.4 vs host 10.0.1.40 is NOT ok" eq "$SE_STAGE" private_nic_timeout
  ck "s10: links shows the configured v4 link ('$SE_DETAIL')" eq "$SE_DETAIL" "boot=$BOOT8.waited_s=150.links=enp7s0:configured:virtio_net:v4"
}
s11() {
  # Invariants ran on every helper run in this pass (13 checks each, all counted above).
  ck "s11: the invariant block ran on every helper run ($invariant_runs of $runs)" num "$invariant_runs" "$runs"
  ck "s11: and on at least 20 runs (non-vacuous)" eval '[[ "$runs" -ge 20 ]]'
}
s12() {
  local want="$WORK/phase2.network"
  cat > "$want" <<'NET'
[Match]
Driver=virtio_net
Name=!eth0

[Link]
RequiredForOnline=no

[Network]
DHCP=ipv4
LinkLocalAddressing=no
IPv6AcceptRA=no

[DHCPv4]
UseMTU=yes
UseDNS=no
UseDomains=no
UseHostname=no
UseNTP=no
SendHostname=no
RouteMetric=1024
NET
  ck "s12: rendered 99-soleur-private-fallback.network equals the plan's Phase 2 block byte-for-byte" cmp -s "$NETFILE" "$want"
}
split_ok() { # <detail>: splits cleanly on . and -- into key=value fields and link entries
  python3 - "$1" <<'PY'
import re, sys
d = sys.argv[1]
f = d.split(".")
if [x.split("=", 1)[0] for x in f] != ["boot", "waited_s", "links"]: sys.exit(1)
if not re.fullmatch(r"[A-Za-z0-9]{8}", f[0][5:]) or not f[1][9:].isdigit(): sys.exit(1)
ents = f[2][6:].split("--")
if ents[-1] == "cut": ents = ents[:-1]
if not ents or not all(re.fullmatch(r"[A-Za-z0-9_-]+:[A-Za-z0-9_-]+:[A-Za-z0-9_-]+:(v4|nov4)", e) for e in ents): sys.exit(1)
PY
}
s13() {
  local i
  new_case s13
  for i in 1 2 3 4 5; do add_link "enp7s0f${i}np0" virtio_net; nc_list_row "$((i + 2))" "enp7s0f${i}np0" off unmanaged; done
  run_helper "$EXP_IP"; invariants s13
  ck "s13: stage private_nic_timeout" eq "$SE_STAGE" private_nic_timeout
  ck "s13: detail <=120 (len ${#SE_DETAIL})" eval '[[ ${#SE_DETAIL} -le 120 ]]'
  ck "s13: detail ends --cut" eval '[[ "$SE_DETAIL" == *--cut ]]'
  ck "s13: detail starts boot=" eval '[[ "$SE_DETAIL" == boot=* ]]'
  ck "s13: detail splits cleanly on . and -- ('$SE_DETAIL')" split_ok "$SE_DETAIL"
  ck "s13: detail exact (two whole entries then --cut)" eq "$SE_DETAIL" \
    "boot=$BOOT8.waited_s=150.links=enp7s0f1np0:unmanaged:virtio_net:nov4--enp7s0f2np0:unmanaged:virtio_net:nov4--cut"
  ck "s13: byte-identical in both stubs' argv" eq "$BS_DETAIL" "$SE_DETAIL"
  new_case s13-two
  add_link enp7s0 virtio_net; add_link enp8s0 virtio_net
  nc_list_row 3 enp7s0 off unmanaged; nc_list_row 4 enp8s0 off unmanaged
  run_helper "$EXP_IP"; invariants s13-two
  ck "s13: two short links joined by -- uncut ('$SE_DETAIL')" eq "$SE_DETAIL" \
    "boot=$BOOT8.waited_s=150.links=enp7s0:unmanaged:virtio_net:nov4--enp8s0:unmanaged:virtio_net:nov4"
  ck "s13: two-link detail splits cleanly" split_ok "$SE_DETAIL"
}
s14() {
  new_case s14
  add_link enp7s0 virtio_net; add_link enp9s0 virtio_net
  nc_list_row 3 enp7s0 routable configured; nc_list_row 4 enp9s0 routable configured
  found_line enp7s0 3 172.16.0.5 >> "$C/fx/addr_base"
  found_line enp9s0 4 > "$C/fx/addr_found"; appear_after 0
  nc_status enp7s0 /run/systemd/network/10-netplan-enp7s0.network
  nc_status enp9s0 /run/systemd/network/10-netplan-enp9s0.network
  run_helper "$EXP_IP"; invariants s14
  ck "s14: stage private_nic_ok" eq "$SE_STAGE" private_nic_ok
  ck "s14: by= names the link HOLDING the address (enp9s0) ('$SE_DETAIL')" eq "$SE_DETAIL" "boot=$BOOT8.waited_s=0.by=10-netplan-enp9s0.egress=eth0"
}
s15() {
  new_case s15; add_link ens3 e1000; nc_list_row 3 ens3 off unmanaged
  run_helper "$EXP_IP"; invariants s15
  ck "s15: non-virtio link is still listed ('$SE_DETAIL')" eq "$SE_DETAIL" "boot=$BOOT8.waited_s=150.links=ens3:unmanaged:e1000:nov4"
}
s16() {
  new_case s16; present_on_enp7s0 0 "$NETPLAN7"; echo enp7s0 > "$C/fx/route_dev"
  run_helper "$EXP_IP"; invariants s16
  ck "s16: egress=enp7s0 ('$SE_DETAIL')" eq "$SE_DETAIL" "boot=$BOOT8.waited_s=0.by=10-netplan-enp7s0.egress=enp7s0"
  ck "s16: level warning (default route left eth0)" eq "$SE_LEVEL" warning
}
s17() {
  new_case s17; present_on_enp7s0 3 "$NETPLAN7"; run_helper "$EXP_IP"; invariants s17
  ck "s17: exactly 3 stubbed sleeps (got $SLEEPS)" num "$SLEEPS" 3
  ck "s17: waited_s=6 from the loop counter ('$SE_DETAIL')" eq "$SE_DETAIL" "boot=$BOOT8.waited_s=6.by=10-netplan-enp7s0.egress=eth0"
  ck "s17: every sleep is 'sleep 2'" eval '[[ "$(awk '"'"'$1=="sleep" && $0!="sleep 2"{n++} END{print n+0}'"'"' "$C/calls.log")" -eq 0 ]]'
  ck "s17: never reads the clock (no date call)" eval '[[ "$(awk '"'"'$1=="date"{n++} END{print n+0}'"'"' "$C/calls.log")" -eq 0 ]]'
}

# Harness rows (plan Guard 2): a must-RED edit and two must-PASS inputs.
h_sentry_noop() {
  new_case h-sentry-noop; present_on_enp7s0 0 "$NETPLAN7"
  printf '#!/bin/sh\nexit 0\n' > "$C/bin/soleur-boot-emit"
  run_helper "$EXP_IP"; invariants h-sentry-noop
}
h_eth1() {
  new_case h-eth1
  add_link eth1 virtio_net; add_link docker0 ""; add_link veth9f8e7d6 ""
  nc_list_row 3 eth1 routable configured
  {
    printf '4: docker0    inet 172.17.0.1/16 brd 172.17.255.255 scope global docker0\\       valid_lft forever preferred_lft forever\n'
    printf '5: br-5e4d3c2b1a09    inet 172.18.0.1/16 brd 172.18.255.255 scope global br-5e4d3c2b1a09\\       valid_lft forever preferred_lft forever\n'
    printf '7: veth9f8e7d6    inet 169.254.10.2/16 brd 169.254.255.255 scope global veth9f8e7d6\\       valid_lft forever preferred_lft forever\n'
  } >> "$C/fx/addr_base"
  found_line eth1 3 > "$C/fx/addr_found"; appear_after 0
  nc_status eth1 /run/systemd/network/10-netplan-eth1.network
  run_helper "$EXP_IP"; invariants h-eth1
  ck "h-eth1: must-PASS, address on eth1 among docker/veth/br lines ('$SE_DETAIL')" eq "$SE_DETAIL" "boot=$BOOT8.waited_s=0.by=10-netplan-eth1.egress=eth0"
}
h_whitespace() {
  new_case h-ws; present_on_enp7s0 0 "$NETPLAN7"
  printf '3:    enp7s0       inet    %s/32   metric 1024   scope global dynamic enp7s0\\       valid_lft 86389sec preferred_lft 86389sec   \n' "$EXP_IP" > "$C/fx/addr_found"
  run_helper "$EXP_IP"; invariants h-ws
  ck "h-ws: must-PASS, ip -o with extra whitespace ('$SE_DETAIL')" eq "$SE_DETAIL" "boot=$BOOT8.waited_s=0.by=10-netplan-enp7s0.egress=eth0"
}

# --- 2. shellcheck the extracted helper -----------------------------------------------------------
if command -v shellcheck >/dev/null 2>&1; then
  cases=$((cases + 1))
  if shellcheck -s sh "$HELPER" > "$WORK/shellcheck.out" 2>&1; then
    pass "shellcheck -s sh on the extracted helper is clean"
  else
    cat "$WORK/shellcheck.out"
    fail "shellcheck -s sh on the extracted helper"
  fi
else
  echo "  SKIP: shellcheck -s sh (shellcheck not installed; install it to run this check) ***"
fi

# --- 3. dispatch: Test Scenarios 1-17 (incl. 3b, 3c) + harness must-PASS rows --------------------
s8b() {
  # #8539 review: a TRANSIENT `ip` failure is not "the address is absent". The pre-fix helper
  # faulted on the FIRST non-zero rc, so a netlink hiccup at iteration 2 ended the wait at 4s of
  # a 150s budget and let the zot login run NIC-less -- the very failure this helper exists to
  # prevent. No fixture could express this before: fx/ip_rc was one static rc for every call.
  new_case s8b; present_on_enp7s0 3 "$NETPLAN7"; echo "1 1 0 0 0" > "$C/fx/ip_rc_seq"
  run_helper "$EXP_IP"; invariants s8b
  ck "s8b: a transient ip failure does NOT fault -- it converges" eq "$SE_STAGE" private_nic_ok
  ck "s8b: the wait continued past the failures (got $SLEEPS)" num "$SLEEPS" 3
  ck "s8b: detail reports the real wait ('$SE_DETAIL')" \
    eq "$SE_DETAIL" "boot=$BOOT8.waited_s=6.by=10-netplan-enp7s0.egress=eth0"
}

s8c() {
  # The DISCRIMINATING case for probe_ran, and the one my first fix shipped without: the
  # instrument fails transiently, RECOVERS, and the address is still genuinely absent. That is
  # a real timeout, not "could not measure" -- mislabelling it probe_fault would send the
  # operator to an instrument problem while the NIC is the problem (#6415, inverted).
  new_case s8c
  add_link enp7s0 virtio_net
  nc_list_row 3 enp7s0 off unmanaged
  echo "1 1 0" > "$C/fx/ip_rc_seq"
  run_helper "$EXP_IP"; invariants s8c
  ck "s8c: a RECOVERED instrument + absent address is a timeout, not a probe fault" \
    eq "$SE_STAGE" private_nic_timeout
  ck "s8c: detail names the link, not a reason= ('$SE_DETAIL')" \
    eq "$SE_DETAIL" "boot=$BOOT8.waited_s=150.links=enp7s0:unmanaged:virtio_net:nov4"
}

SCENARIOS=(s1 s2 s3 s3b s3c s4 s5 s6 s7 s8 s8b s8c s9 s10 s12 s13 s14 s15 s16 s17 h_eth1 h_whitespace s11)
DECLARED_SCENARIOS=23
scenarios_run=0
for s in "${SCENARIOS[@]}"; do
  echo "- $s"
  "$s"
  scenarios_run=$((scenarios_run + 1))
done

# Declared-scenario-count equality: a scenario dropped from the dispatch (or all of them) reds.
if [[ "$scenarios_run" -ne "$DECLARED_SCENARIOS" ]]; then
  printf '[FATAL] anti-vacuity floor: only %s scenarios ran, declared %s (declared-count equality)\n' "$scenarios_run" "$DECLARED_SCENARIOS" >&2
  exit 1
fi
# Conservation: every counted check produced exactly one verdict.
if [[ $((PASS + FAIL)) -ne "$cases" ]]; then
  printf '[FATAL] anti-vacuity floor: %s verdicts for %s checks — a verdict was discarded\n' "$((PASS + FAIL))" "$cases" >&2
  exit 1
fi
MIN_SCENARIO_CHECKS=382
if [[ "$cases" -lt $MIN_SCENARIO_CHECKS ]]; then
  printf '[FATAL] anti-vacuity floor: only %s scenario checks ran, expected at least %s\n' "$cases" "$MIN_SCENARIO_CHECKS" >&2
  exit 1
fi

# --- 4. Guard 2 mutation battery -------------------------------------------------------------------
if [[ "$RUN_BATTERY" == "1" ]]; then
  echo "--- Guard 2 mutation battery (each mutant must RED) ---"
  QUIET=0
  scen_red() { # <scenario>: returns 0 when the scenario is RED
    SCEN_RED=0; RED_WHY=""; QUIET=1
    "$1"
    QUIET=0
    [[ "$SCEN_RED" -eq 1 ]]
  }
  # Baseline: every scenario the battery uses is GREEN on the pristine copy, else a "killed"
  # verdict would mean nothing.
  HUT="$PRISTINE"
  for s in s1 s2 s3 s3b s4 s8 s9 s10 s13 s14 s15 s17; do
    if scen_red "$s"; then harness "baseline: scenario $s is RED on the PRISTINE helper:$RED_WHY"; fi
  done

  MUT="$WORK/helper.mutant"
  mutant_begin() { cp "$PRISTINE" "$MUT"; }
  mutant_sub() { # <old> <new> [count]
    OLD="$1" NEW="$2" CNT="${3:-1}" python3 - "$MUT" <<'PY' || harness "mutation did not land: '${1}' not found the expected number of times"
import os, sys
p = sys.argv[1]; s = open(p).read()
old, new, cnt = os.environ["OLD"], os.environ["NEW"], int(os.environ["CNT"])
if s.count(old) != cnt:
    sys.stderr.write("found %d occurrence(s) of %r, expected %d\n" % (s.count(old), old, cnt)); sys.exit(3)
open(p, "w").write(s.replace(old, new))
PY
  }
  rows_run=0
  mutant_end() { # <row label> <scenario...>
    local label="$1" s red=0 who=""; shift
    ! cmp -s "$PRISTINE" "$MUT" || harness "$label: the mutant is byte-identical to the pristine helper (mutation did not land)"
    sh -n "$MUT" || harness "$label: the mutant is not valid sh"
    HUT="$MUT"
    for s in "$@"; do
      if scen_red "$s"; then red=1; who="$who $s:${RED_WHY# | }"; fi
    done
    HUT="$HELPER"
    rows_run=$((rows_run + 1))
    cases=$((cases + 1))
    if [[ "$red" -eq 1 ]]; then pass "$label -> killed (RED on${who%%|*})"; else fail "$label -> SURVIVED (scenarios $* stayed green)"; fi
  }
  NL=$'\n'

  # POSITIVE CONTROL for mutant_end itself. Every row below routes its verdict through
  # mutant_end, which computes `red` and then chooses pass() or fail(). Forcing that choice made
  # all rows report "killed" with nothing behind them, at 368/0 green — invisible to the
  # counters, to the conservation check and to MUT_EXPECTED_ROWS. Drive it with a mutation that
  # changes bytes but not behaviour, so it MUST survive, and require mutant_end to say so.
  _me_f=$FAIL; _me_rows=$rows_run
  mutant_begin; mutant_sub 'W=$((i * 2))' 'W=$(( i * 2 ))'
  mutant_end "harness control: a semantically-neutral edit must be reported SURVIVED" s1 s2 s4 >/dev/null
  if [[ "$FAIL" -ne $((_me_f + 1)) ]]; then
    printf '[FATAL] harness: mutant_end did not report a surviving mutant — every "killed" below is unbacked\n' >&2
    exit 1
  fi
  FAIL=$_me_f; cases=$((cases - 1)); rows_run=$_me_rows

  mutant_begin; mutant_sub "emit private_nic_timeout warning \"\$BASE\$L\"${NL}exit 0" "emit private_nic_timeout warning \"\$BASE\$L\"${NL}exit 1"
  mutant_end "row 1: timeout arm exit 0 -> exit 1" s4 s13 s15
  mutant_begin; mutant_sub 'grep -qwF' 'grep -qF'
  mutant_end "row 2: grep -qwF -> grep -qF (10.0.1.4 vs 10.0.1.40)" s10
  mutant_begin; mutant_sub '"$i" -lt 75' '"$i" -lt 750'
  mutant_end "row 3: poll cap 75 -> 750" s4
  mutant_begin; mutant_sub 'found=1; break;' 'found=1;'
  mutant_end "row 4: remove break-on-found" s2 s17
  mutant_begin; mutant_sub 'found=1; break;' 'found=1; emit private_nic_ok info "boot=$BOOT.waited_s=0.by=loop.egress=loop"; break;'
  mutant_end "row 5: emit inside the poll loop and again after it" s1 s2
  mutant_begin; mutant_sub "emit private_nic_timeout warning \"\$BASE\$L\"" "reboot${NL}emit private_nic_timeout warning \"\$BASE\$L\""
  mutant_end "row 6: reboot in the timeout arm" s4
  mutant_begin; mutant_sub "emit private_nic_timeout warning \"\$BASE\$L\"" "networkctl reconfigure enp7s0${NL}emit private_nic_timeout warning \"\$BASE\$L\""
  mutant_end "row 6b: networkctl reconfigure in the timeout arm" s4
  mutant_begin; mutant_sub "[ -n \"\$EXP\" ] || fault noarg${NL}" ''
  mutant_end "row 7: remove the empty-argument guard" s9
  mutant_begin; mutant_sub '*) BY=$(basename "$NF" .network) ;;' '*) BY=10-netplan-enp7s0 ;;'
  mutant_end "row 8: fixed by= instead of the Network File basename" s1 s3 s3b s14
  mutant_begin; mutant_sub "[ \"\$rc\" -eq 0 ] && probe_ran=1${NL}" ''
  mutant_end "row 9: a failing ip is treated as absent (probe_ran never set)" s8c
  # #8539 review: the pre-fix shape faulted on the FIRST non-zero rc, so one netlink hiccup
  # ended the wait. Reverting to it must red the transient-recovery scenario, or the fix is
  # pinned by nothing.
  mutant_begin; mutant_sub "[ \"\$rc\" -eq 0 ] && probe_ran=1" "[ \"\$rc\" -eq 0 ] || { W=\$((i * 2)); fault iprc; }"
  mutant_end "row 9b: fault on the FIRST transient ip failure (the pre-fix defect)" s8b
  # row 10 is below (the suite's own dispatch).
  mutant_begin; mutant_sub '.waited_s=' ' waited_s=' 3
  mutant_end "row 11: join fields with a space instead of ." s13 s1 s9
  mutant_begin
  mutant_sub "sed 's/ /--/g'" "sed 's/ /,/g'"
  mutant_sub 'c="$L--$e"' 'c="$L,$e"'
  mutant_sub '"$BASE$c--cut"' '"$BASE$c,cut"'
  mutant_sub 'L="$L--cut"' 'L="$L,cut"'
  mutant_end "row 12: join link entries with ," s13
  mutant_begin; mutant_sub "IF=\$(printf '%s\\n' \"\$out\" | grep -wF -- \"\$EXP\" | head -n 1 | awk '{print \$2}')" \
    "IF=\$(printf '%s\\n' \"\$out\" | awk '\$2 != \"lo\" && \$2 != \"eth0\" {print \$2; exit}')"
  mutant_end "row 13: by= from the FIRST non-eth0 link" s14
  mutant_begin; mutant_sub 'if [ "$(len "$BASE$FULL")" -le 120 ]; then' 'if true; then'
  mutant_end "row 14: drop the helper-side 120-char cap" s13
  mutant_begin; mutant_sub "v=nov4${NL}" "[ \"\$dv\" = virtio_net ] || continue${NL}v=nov4${NL}"
  mutant_end "row 15: filter links= to virtio only" s15

  # Row 10: the suite's own dispatch runs zero scenarios -> the declared-count equality must RED.
  SUITE_MUT="$WORK/suite.mutant.sh"
  sed 's/^SCENARIOS=(.*)$/SCENARIOS=()/' "$SELF" > "$SUITE_MUT"
  ! cmp -s "$SELF" "$SUITE_MUT" || harness "row 10: the SCENARIOS=() mutation did not land on the suite copy"
  R10=0
  NICWAIT_INFRA_DIR="$SCRIPT_DIR" NICWAIT_SUITE_BATTERY=0 bash "$SUITE_MUT" >"$WORK/r10.out" 2>"$WORK/r10.err" || R10=$?
  rows_run=$((rows_run + 1))
  cases=$((cases + 1))
  if [[ "$R10" -ne 0 ]] && grep -q 'declared-count equality' "$WORK/r10.err"; then
    pass "row 10: zero-scenario dispatch -> killed (declared-count equality, rc=$R10)"
  else
    fail "row 10: zero-scenario dispatch -> SURVIVED (rc=$R10)"
  fi

  # Harness row: a soleur-boot-emit that records nothing must RED exactly-one-event (not 0 = 0).
  rows_run=$((rows_run + 1))
  cases=$((cases + 1))
  HUT="$HELPER"
  if scen_red h_sentry_noop && [[ "$RED_WHY" == *"exactly one Sentry event (got 0)"* ]]; then
    pass "harness: silent soleur-boot-emit stub -> exactly-one-event REDs (not 0 = 0)"
  else
    fail "harness: silent soleur-boot-emit stub did not red exactly-one-event (why:$RED_WHY)"
  fi

  MUT_EXPECTED_ROWS=18
  if [[ "$rows_run" -lt $MUT_EXPECTED_ROWS ]]; then
    printf '[FATAL] anti-vacuity floor: only %s mutation/harness rows ran, expected %s — a row was deleted\n' "$rows_run" "$MUT_EXPECTED_ROWS" >&2
    exit 1
  fi
fi

if [[ $((PASS + FAIL)) -ne "$cases" ]]; then
  printf '[FATAL] anti-vacuity floor: %s verdicts for %s checks — a verdict was discarded\n' "$((PASS + FAIL))" "$cases" >&2
  exit 1
fi

echo ""
echo "=== inngest-nic-wait: $PASS passed, $FAIL failed ($scenarios_run scenarios, ${rows_run:-0} battery rows) ==="
[[ "$FAIL" -eq 0 ]]
