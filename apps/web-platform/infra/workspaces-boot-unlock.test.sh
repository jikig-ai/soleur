#!/usr/bin/env bash
# workspaces-boot-unlock.test.sh — the #9123 guard suite (plan Phase 2.1):
# a web-1 reboot converges to `mapper open + mapper mounted at /mnt/data + docker gated
# on that mount`, every failure class leaves a named-phase fatal row, and a HEALTHY boot
# never pages (the emit path is failure-only — workspaces_luks_emit hardcodes the sole
# paging op).
#
# Arms, mirroring git-data-luks-reopen.test.sh + luks-monitor-install.test.sh:
#   STATIC   — predicates over workspaces-luks-reopen.sh, the three units, the
#              terraform_data.workspaces_boot_unlock_install block and its writer locals
#              (HCL-decoded), the workflow -target= line, and the vector.toml tag.
#   WRITERS  — the five mutating locals are HCL-DECODED and EXECUTED under sh against a
#              stub PATH + a scratch filesystem tree: exit-17 freeze refusal, the fstab
#              exactly-one rule (trailing-slash normalized), the crypttab canonical line
#              (whitespace-tolerant foreign detection), the env-file shape, the
#              chattr-via-peek ordering (bind `|| exit 54` → symlink refusal → st_dev
#              assert → chattr → lsattr verify → umount loop; never chattr on the
#              mounted path), and the arm step's enable/420 s-bounded proof ordering.
#   RUNTIME  — the reopen script runs under a stub PATH (cryptsetup/findmnt/mountpoint/
#              systemctl/blockdev/realpath/doppler/logger/workspaces_luks_emit append
#              "<phase>|<stub>|<argv>" to calls.log): phase order, phase-file rows, the
#              noop-is-silent / success-never-pages property (AC9), and one failure
#              fixture per declared phase.
#   REPORTER — the -failure.service's /bin/sh -c body is extracted, its absolute paths
#              rewritten to the fixture, and run per failure fixture: exactly one emit
#              naming action=<phase>, the WL_* discriminating tags, action=unit on no
#              phase file, and the SOLEUR_*_SEND_FAILED mirror when the emit leg fails.
#   PRINT    — the before/after print locals are deny-list checked (no raw fstab/crypttab,
#              no journalctl, no env-file reads, every line guarded), executed against
#              scratch fixtures, and sha256-pinned (change-detector: the public apply log
#              gets only the security-reviewed bytes).
#
# Mutation rows live at the bottom. They mutate COPIES and re-run this file against them
# through the WBU_* overrides, so tracked files are never written. rc 1 = the mutation was
# caught; rc 2 = a broken instrument, never counted as a catch.
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$DIR/../../.." && pwd)"
SELF="$DIR/$(basename "${BASH_SOURCE[0]}")"
export WBU_LUKS_TF="${WBU_LUKS_TF:-$DIR/workspaces-luks.tf}"
export WBU_SCRIPT="${WBU_SCRIPT:-$DIR/workspaces-luks-reopen.sh}"
export WBU_UNIT="${WBU_UNIT:-$DIR/workspaces-luks-reopen.service}"
export WBU_REPORTER="${WBU_REPORTER:-$DIR/workspaces-luks-reopen-failure.service}"
export WBU_TIMER="${WBU_TIMER:-$DIR/workspaces-luks-reopen.timer}"
export WBU_EMIT_SH="${WBU_EMIT_SH:-$DIR/workspaces-luks-emit.sh}"
export WBU_WF="${WBU_WF:-$REPO/.github/workflows/apply-web-platform-infra.yml}"
export WBU_VECTOR="${WBU_VECTOR:-$DIR/vector.toml}"
# WBU_DISABLE_STUB is a suite-only instrument seam: the named stub is NOT created, so the
# runtime arm's stub census falls through to the real binary (cryptsetup exists at
# /usr/bin/cryptsetup on CI runners) and the suite must die rc 2 — never silently
# scoring a run that executed the host's cryptsetup.
export WBU_DISABLE_STUB="${WBU_DISABLE_STUB:-}"

pass=0; fail=0; FAILED=()
# verdict helper — $1 is an exit-status-style code: 0 means the assertion holds.
ok() { if [ "$1" -eq 0 ]; then pass=$((pass + 1)); printf '[ok] %s\n' "$2"; else fail=$((fail + 1)); FAILED+=("$2"); printf '[FAIL] %s%s\n' "$2" "${3:+ ($3)}"; fi; }
# unconditional failure recorder (verdicts TSV replay + mutation grading).
no() { fail=$((fail + 1)); FAILED+=("$1"); printf '[FAIL] %s\n' "$1"; }

# P1b (#7708) — byte-identical to every other tracked copy; the P1a suite pins that.
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

# INSTRUMENT SELF-TEST — both helpers must move their own counter before any verdict is trusted.
_p0=$pass; _f0=$fail
{ ok 0 "self-test"; no "self-test"; } >/dev/null
if [ "$pass" -ne $((_p0 + 1)) ] || [ "$fail" -ne $((_f0 + 1)) ] || [ "${#FAILED[@]}" -ne 1 ]; then
  printf '[FATAL] instrument self-test: ok()/no() did not each move their counter\n' >&2; exit 2
fi
pass=$_p0; fail=$_f0; FAILED=()

command -v python3 >/dev/null 2>&1 || { printf '[FATAL] python3 missing\n' >&2; exit 2; }
for f in "$WBU_LUKS_TF" "$WBU_SCRIPT" "$WBU_UNIT" "$WBU_REPORTER" "$WBU_TIMER" "$WBU_EMIT_SH" "$WBU_WF" "$WBU_VECTOR"; do
  [ -r "$f" ] || { printf '[FATAL] unreadable: %s\n' "$f" >&2; exit 2; }
done

SCRATCH="$(mktemp -d)"
assert_fixture_dir "$SCRATCH"
trap 'rm -rf "$SCRATCH"' EXIT
export WBU_SCRATCH="$SCRATCH"

# Drop comment lines AND ` #`-style inline trailers that sit outside quotes: a
# substring grep must never be satisfied by commented text (test-design review —
# the old grep-only strip left `code # trailer` lines whole). `#!` survives on
# purpose (a leading `#` whose next char is `!` after an all-blank prefix), and a
# `#` inside single/double quotes is data (the script's `see #7797` literal).
strip() {
  awk '{
    out=""; dq=0; sq=0; cut=0
    for (i=1; i<=length($0); i++) {
      ch=substr($0,i,1)
      if (ch=="\"" && !sq && (i==1 || substr($0,i-1,1)!="\\")) { dq=!dq; out=out ch; continue }
      if (ch==sprintf("%c",39) && !dq && (i==1 || substr($0,i-1,1)!="\\")) { sq=!sq; out=out ch; continue }
      if (ch=="#" && !dq && !sq) {
        nxt=(i<length($0)?substr($0,i+1,1):"")
        prv=(i>1?substr($0,i-1,1):"")
        if (nxt=="!" && (i==1 || out ~ /^[ \t]*$/)) { out=out ch; continue }
        if (i==1 || prv ~ /[ \t]/) { cut=1; break }
      }
      out=out ch
    }
    if (cut) sub(/[ \t]+$/,"",out)
    if (out != "" || $0 !~ /^[ \t]*#/) print out
  }' "$1"
}

VOLID=777001
PIN_DEV="/dev/disk/by-id/scsi-0HC_Volume_$VOLID"

# ==================================================================================
# PHASE A — decode the .tf block: resolve the writer/print locals, emit verdicts.
# ==================================================================================
rc=0
python3 - "$SCRATCH" > "$SCRATCH/verdicts.tsv" <<'PYEOF' || rc=$?
import os, re, sys, hashlib

E = os.environ
out = []
def check(name, cond, detail=""):
    out.append(("ok" if cond else "no", name, " ".join(str(detail).split())[:240]))
def fatal(msg):
    for v in out:
        print("\t".join(v))
    print("FATAL\t" + msg)
    sys.exit(2)

def strip(src):
    res = []
    for line in src.splitlines():
        buf, q, i = [], False, 0
        while i < len(line):
            ch = line[i]
            if ch == '"' and (i == 0 or line[i - 1] != "\\"):
                q = not q
            if not q and (ch == "#" or line.startswith("//", i)):
                break
            buf.append(ch); i += 1
        res.append("".join(buf))
    return "\n".join(res)

def balanced(src, start):
    depth, i = 1, start
    while i < len(src) and depth:
        depth += {"{": 1, "}": -1}.get(src[i], 0); i += 1
    return src[start:i - 1]

def block(src, kind, name):
    m = re.search(r'(?m)^resource\s+"%s"\s+"%s"\s*\{' % (re.escape(kind), re.escape(name)), src)
    return balanced(src, m.end()) if m else None

def provisioners(body):
    res = []
    for m in re.finditer(r'provisioner\s+"(file|remote-exec)"\s*\{', body):
        res.append((m.group(1), balanced(body, m.end())))
    return res

STR = r'"((?:[^"\\]|\\.)*)"'
def list_strings(text, start):
    depth, i = 1, start
    while i < len(text) and depth:
        c = text[i]
        if c == '"':
            j = i + 1
            while j < len(text) and text[j] != '"':
                j += 2 if text[j] == "\\" else 1
            i = j + 1; continue
        depth += {"[": 1, "]": -1}.get(c, 0); i += 1
    return re.findall(STR, text[start:i - 1])

def local_lists(src):
    res = {}
    for m in re.finditer(r'(?m)^locals\s*\{', src):
        body = balanced(src, m.end())
        for lm in re.finditer(r'(?m)^\s*([A-Za-z0-9_]+)\s*=\s*\[', body):
            res[lm.group(1)] = list_strings(body, lm.end())
    return res

def inline_local(pbody):
    m = re.search(r'(?m)^\s*inline\s*=\s*local\.([A-Za-z0-9_]+)\s*$', pbody)
    return m.group(1) if m else None

def hcl_unescape(s):
    res, i = [], 0
    while i < len(s):
        c = s[i]
        if c == "\\":
            n = s[i + 1] if i + 1 < len(s) else ""
            if n == "\\": res.append("\\")
            elif n == '"': res.append('"')
            elif n == "n": res.append("\n")
            else: fatal("unknown HCL escape \\%s in %r" % (n, s))
            i += 2; continue
        res.append(c); i += 1
    return "".join(res)

SCRATCH = sys.argv[1]
VOLID = "777001"
luks_raw = open(E["WBU_LUKS_TF"]).read()
luks = strip(luks_raw)
LOCALS = local_lists(luks)

def decode(lines):
    # The bytes the host runs: HCL-unescape, template-escape undo, volume-id substitute.
    return [hcl_unescape(c).replace("$${", "${").replace("%%{", "%{").replace(
        "${hcloud_volume.workspaces_luks.id}", VOLID) for c in lines]

NAMES = ["workspaces_boot_unlock_print", "workspaces_boot_unlock_envfile_writer",
         "workspaces_boot_unlock_crypttab_writer", "workspaces_boot_unlock_fstab_writer",
         "workspaces_boot_unlock_gate_writer", "workspaces_boot_unlock_arm",
         "workspaces_boot_unlock_post_state"]
DEC = {}
missing = [n for n in NAMES if not LOCALS.get(n)]
check("TF0 all seven workspaces_boot_unlock_* locals resolve", not missing, missing)
for n in NAMES:
    if LOCALS.get(n):
        DEC[n] = decode(LOCALS[n])
decdir = os.path.join(SCRATCH, "dec")
os.makedirs(decdir, exist_ok=True)
for n, lines in DEC.items():
    with open(os.path.join(decdir, n + ".sh"), "w") as fh:
        fh.write("\n".join(lines) + "\n")

res = block(luks, "terraform_data", "workspaces_boot_unlock_install")
check("TF1 terraform_data.workspaces_boot_unlock_install exists (exact header)", res is not None)
if res:
    check("TF2 depends_on serializes after BOTH monitor installers",
          re.search(r'depends_on\s*=\s*\[[^\]]*terraform_data\.luks_monitor_token_install', res) is not None
          and re.search(r'depends_on\s*=\s*\[[^\]]*terraform_data\.luks_monitor_install', res) is not None)
    tm = re.search(r'triggers_replace\s*=\s*sha256\(join\(",",\s*\[(.*?)\]\)\)', res, re.S)
    ops = tm.group(1) if tm else ""
    trig_files = set(re.findall(r'file\("\$\{path\.module\}/([^"]+)"\)', ops))
    want_files = {"workspaces-luks-reopen.sh", "workspaces-luks-reopen.service",
                  "workspaces-luks-reopen-failure.service", "workspaces-luks-reopen.timer"}
    check("TF3 triggers_replace hashes all four delivered files", trig_files == want_files, sorted(trig_files))
    unhashed = [n for n in NAMES if not re.search(r'join\("\\n",\s*local\.%s\)' % re.escape(n), ops)]
    check("TF4 every writer/print local is a trigger operand (an edit re-fires)", not unhashed, unhashed)
    conn = re.search(r'connection\s*\{([^}]*)\}', res)
    cb = conn.group(1) if conn else ""
    check("TF5 the connection dials web-1 as root with the pinned host key",
          re.search(r'(?m)^\s*host\s*=\s*hcloud_server\.web\["web-1"\]\.ipv4_address\s*$', cb) is not None
          and re.search(r'(?m)^\s*user\s*=\s*"root"\s*$', cb) is not None
          and re.search(r'(?m)^\s*host_key\s*=\s*local\.web_1_ssh_host_key\s*$', cb) is not None, cb[:160])
    check("TF6 inline scripts upload under /root, not world-readable /tmp",
          re.search(r'(?m)^\s*script_path\s*=\s*"/root/[^"]*%RAND%[^"]*"\s*$', cb) is not None)
    check("TF7 the volume-id precondition pins bare digits (interpolated into root-owned writers)",
          re.search(r'can\(regex\("\^\[0-9\]\+\$",\s*tostring\(hcloud_volume\.workspaces_luks\.id\)\)\)', res) is not None)
    check("TF8 no lifecycle.ignore_changes (a silenced installer is the defect class this closes)",
          "ignore_changes" not in res)
    provs = provisioners(res)
    seq = []
    for k, b in provs:
        if k == "file":
            m = re.search(r'destination\s*=\s*"([^"]+)"', b)
            seq.append("file:" + (m.group(1) if m else "?"))
        else:
            seq.append("exec:" + (inline_local(b) or "inline-literal"))
    want_seq = ["exec:workspaces_boot_unlock_print",
                "file:/usr/local/bin/workspaces-luks-reopen.sh",
                "file:/etc/systemd/system/workspaces-luks-reopen.service",
                "file:/etc/systemd/system/workspaces-luks-reopen-failure.service",
                "file:/etc/systemd/system/workspaces-luks-reopen.timer",
                "exec:workspaces_boot_unlock_crypttab_writer",
                "exec:workspaces_boot_unlock_envfile_writer",
                "exec:workspaces_boot_unlock_gate_writer",
                "exec:workspaces_boot_unlock_fstab_writer",
                "exec:workspaces_boot_unlock_arm",
                "exec:workspaces_boot_unlock_post_state"]
    # PINNED (#9123 review): crypttab first so an exit-32 refusal leaves the OLD
    # pin pair; gate BEFORE fstab so a mid-window abort stays fail-closed.
    check("TF9 provisioner order is print -> files -> crypttab -> envfile -> gate -> fstab -> arm -> post-state",
          seq == want_seq, seq)
    check("TF10 the before-print carries no freeze refusal (it must run even under a live freeze)",
          bool(DEC.get("workspaces_boot_unlock_print"))
          and not any("exit 17" in c for c in DEC["workspaces_boot_unlock_print"]))

FREEZE = re.compile(r'systemctl show -p SubState --value workspaces-luks-deadman\.timer.*!= waiting.*exit 17')
for n in ("workspaces_boot_unlock_envfile_writer", "workspaces_boot_unlock_crypttab_writer",
          "workspaces_boot_unlock_fstab_writer", "workspaces_boot_unlock_gate_writer",
          "workspaces_boot_unlock_arm"):
    lines = DEC.get(n, [])
    check("TF11 %s opens set -e then the exit-17 dead-man refusal" % n,
          len(lines) >= 2 and lines[0] == "set -e" and FREEZE.search(lines[1] or "") is not None,
          lines[:2])

all_decoded = [c for lines in DEC.values() for c in lines]
check("TF12 no doppler invocation anywhere in the installer (the key fetch is the unit's, at boot)",
      not any(re.search(r'\bdoppler\b', c) for c in all_decoded),
      [c[:80] for c in all_decoded if re.search(r'\bdoppler\b', c)])
check("TF13 no mention of the shared /etc/default/luks-monitor in any step (the unit is the read-only consumer)",
      not any("/etc/default/luks-monitor" in c for c in all_decoded),
      [c[:80] for c in all_decoded if "/etc/default/luks-monitor" in c])
check("TF14 docker is never restarted/stopped/disabled/masked by the installer (daemon-reload arms the drop-in)",
      not any(re.search(r'systemctl\b[^;|&]*\b(start|restart|stop|disable|mask|kill|try-restart|reload-or-restart)\b[^;|&]*\bdocker\b', c)
              for c in all_decoded),
      [c[:80] for c in all_decoded if re.search(r'\bdocker\b', c)])

ef = DEC.get("workspaces_boot_unlock_envfile_writer", [])
ef_txt = "\n".join(ef)
check("TF15 envfile writer emits the by-id pin + the scoped config name, 0600, umask 077",
      any("WORKSPACES_LUKS_DEV=/dev/disk/by-id/scsi-0HC_Volume_" in c and VOLID in c for c in ef)
      and any("WORKSPACES_DOPPLER_CONFIG=prd_workspaces_luks" in c for c in ef)
      and "umask 077" in ef_txt and "chmod 600" in ef_txt)
check("TF16 envfile writer refuses a symlink (exit 20) and the file gets NO token/key line",
      any("exit 20" in c and "-L" in c for c in ef)
      and not any(re.search(r'(DOPPLER_TOKEN|WORKSPACES_LUKS_KEY)\s*=', c) for c in ef))
check("TF17 envfile writer fixes the delivered modes (0755 script, 0644 units)",
      any(re.match(r'chmod 0755 /usr/local/bin/workspaces-luks-reopen\.sh$', c) for c in ef)
      and any("chmod 0644 /etc/systemd/system/workspaces-luks-reopen.service" in c for c in ef))

ct = DEC.get("workspaces_boot_unlock_crypttab_writer", [])
ct_txt = "\n".join(ct)
check("TF18 crypttab line is the pinned by-id `none luks,noauto` (noauto keeps ask-password out of boot ordering)",
      any(c == "LINE='workspaces /dev/disk/by-id/scsi-0HC_Volume_%s none luks,noauto'" % VOLID for c in ct))
check("TF19 crypttab writer is append-if-absent on ^[[:space:]]*workspaces[[:space:]] (leading whitespace IS live crypttab syntax), then asserts exactly-one AND canonical",
      any(re.search(r"grep -q '\^\[\[:space:\]\]\*workspaces\[\[:space:\]\]' \"\$c\".*\|\| printf '%s\\n' \"\$LINE\" >> \"\$c\"", c) for c in ct)
      and any('= 1 ] ||' in c and "exit 31" in c for c in ct)
      and any('grep -qxF "$LINE"' in c and "exit 32" in c for c in ct))
check("TF20 the crypttab line never carries `nofail` (a generated ask-password job would race the reopen unit)",
      not any("nofail" in c and "LINE=" in c for c in ct))

fs = DEC.get("workspaces_boot_unlock_fstab_writer", [])
check("TF21 fstab writer refuses symlink (40), absent (41), live-source-not-mapper (42)",
      any("-L" in c and "exit 40" in c for c in fs)
      and any(re.match(r'\[ -f "\$f" \]', c) and "exit 41" in c for c in fs)
      and any('= /dev/mapper/workspaces' in c and "exit 42" in c for c in fs))
check("TF22 fstab writer backups BEFORE the edit, comments every non-comment /mnt/data line (trailing-slash normalized on a COPY of $2), appends the canonical mapper+nofail line",
      any("cp -a" in c and ".bak" in c for c in fs)
      and any('boot-unlock-9123-superseded' in c for c in fs)
      and any('sub(/\\/+$/' in c and 'm == "/mnt/data"' in c for c in fs)
      and any("/dev/mapper/workspaces /mnt/data ext4 defaults,nofail 0 2" in c and "printf" in c for c in fs))
check("TF23 fstab writer asserts exactly-one (exit 44), the surviving entry is mapper+ext4+nofail (exit 45), the +1 line-count delta (exit 46) and the split chown (exit 47) all BEFORE mv (exit 46)",
      any('"$n" = 1' in c for c in fs) and any("exit 44" in c for c in fs)
      and any("nofail" in c and "exit 45" in c for c in fs)
      and any('"$n2" = "$((o + 1))"' in c and "exit 46" in c for c in fs)
      and any('chown root:root "$t"' in c and "exit 47" in c for c in fs)
      and any('chmod 644 "$t"' == c for c in fs)
      and any('mv "$t" "$f"' in c and "exit 46" in c for c in fs))
if fs:
    def idx_of(pred, xs):
        for i, c in enumerate(xs):
            if pred(c):
                return i
        return None
    i_cp = idx_of(lambda c: "cp -a" in c, fs)
    i_awk = idx_of(lambda c: "boot-unlock-9123-superseded" in c, fs)
    i_app = idx_of(lambda c: "defaults,nofail" in c and "printf" in c, fs)
    i_n = idx_of(lambda c: "exit 44" in c, fs)
    i_ch = idx_of(lambda c: 'chown root:root "$t"' in c, fs)
    i_mv = idx_of(lambda c: 'mv "$t" "$f"' in c, fs)
    check("TF24 fstab write order: backup < comment < append < count-assert < chown < mv",
          None not in (i_cp, i_awk, i_app, i_n, i_ch, i_mv)
          and i_cp < i_awk < i_app < i_n < i_ch < i_mv,
          (i_cp, i_awk, i_app, i_n, i_ch, i_mv))

gw = DEC.get("workspaces_boot_unlock_gate_writer", [])
check("TF25 the docker drop-in carries BOTH RequiresMountsFor=/mnt/data and After=workspaces-luks-reopen.service",
      any("RequiresMountsFor=/mnt/data" in c and "After=workspaces-luks-reopen.service" in c for c in gw))
check("TF26 the drop-in contents are asserted after write (exit 50/51)",
      any("exit 50" in c for c in gw) and any("exit 51" in c for c in gw))
check("TF26b the peek refuses a failed bind (`||` exit 54 — NEVER `&& flag`, which is errexit-immune), a symlink target (exit 55) and a non-rootfs peek (st_dev assert, exit 56)",
      any('mount --bind / "$p"' in c and "||" in c and "exit 54" in c for c in gw)
      and any('[ -L "$p/mnt/data" ]' in c and "exit 55" in c for c in gw)
      and any('stat -c %d "$p"' in c and 'stat -c %d /' in c and "exit 56" in c for c in gw))
check("TF26c the peek umount is a `while mountpoint -q` loop (a busy first umount retries), with a residue warning after",
      any('while mountpoint -q "$p"; do umount "$p"' in c and "trap" not in c for c in gw)
      and any('mountpoint -q "$p"' in c and "WARNING" in c for c in gw),
      [c for c in gw if "umount" in c or "mountpoint" in c])
check("TF27 chattr +i is applied ONLY through the bind peek (\"$p/mnt/data\") — never the mounted /mnt/data",
      any('chattr +i "$p/mnt/data"' in c for c in gw)
      and not any(re.search(r'chattr\s[^;]*/mnt/data', c) and 'chattr +i "$p/mnt/data"' not in c for c in gw),
      [c for c in gw if "chattr" in c])
if gw:
    i_bind = idx_of(lambda c: 'mount --bind / "$p"' in c, gw)
    i_sym = idx_of(lambda c: '[ -L "$p/mnt/data" ]' in c, gw)
    i_dev = idx_of(lambda c: 'stat -c %d "$p"' in c, gw)
    i_mk = idx_of(lambda c: '"$p/mnt/data"' in c and "mkdir" in c, gw)
    i_ch = idx_of(lambda c: "chattr +i" in c, gw)
    i_ls = idx_of(lambda c: "lsattr -d" in c, gw)
    i_um = idx_of(lambda c: 'while mountpoint -q "$p"; do umount "$p"' in c and "trap" not in c, gw)
    check("TF28 peek order is bind < symlink-refusal < st_dev-assert < mkdir < chattr < lsattr-verify < umount-loop",
          None not in (i_bind, i_sym, i_dev, i_mk, i_ch, i_ls, i_um)
          and i_bind < i_sym < i_dev < i_mk < i_ch < i_ls < i_um,
          (i_bind, i_sym, i_dev, i_mk, i_ch, i_ls, i_um))

ar = DEC.get("workspaces_boot_unlock_arm", [])
check("TF29 arm = daemon-reload, enable+is-enabled service, enable --now timer, a `timeout 420`-BOUNDED proof start (exit 63 on client-window non-convergence — killing the dbus client never kills the unit-side ladder), then SubState/Result/ExecMainStatus asserts",
      any(c == "systemctl daemon-reload" for c in ar)
      and any(c == "systemctl enable workspaces-luks-reopen.service" for c in ar)
      and any(c == "systemctl enable --now workspaces-luks-reopen.timer" for c in ar)
      and any("timeout 420 systemctl start workspaces-luks-reopen.service" in c
              and "||" in c and "exit 63" in c for c in ar)
      and any("SubState" in c and "exited" in c and "exit 60" in c for c in ar)
      and any("Result" in c and "success" in c and "exit 61" in c for c in ar)
      and any("ExecMainStatus" in c and "exit 62" in c for c in ar))

# ── Print integrity (plan Guard 3): guarded lines + deny list ────────────────────────
def subst_bodies(c):
    res, i = [], 0
    while True:
        j = c.find("$(", i)
        if j < 0:
            return res
        depth, k = 1, j + 2
        while k < len(c) and depth:
            depth += {"(": 1, ")": -1}.get(c[k], 0); k += 1
        res.append(c[j + 2:k - 1]); i = k

def guarded(c):
    # A line may neither fail the step nor taint the resource: it ends in `|| true`, it is a
    # `for ...; do ... || true; done` loop, it is a `;`-chain whose every clause is guarded,
    # a short-circuit `&&` chain, or an echo whose every top-level substitution carries its
    # own `|| echo …` / `|| true` fallback, or a literal single-quoted echo.
    c = c.strip()
    if re.search(r'\|\|\s*true$', c):
        return True
    if re.match(r'^for .+; do .*\|\| true; done\s*(\|\|\s*true)?$', c):
        return True
    # An if/else whose arms are pure prints: the condition (assignment/command
    # substitution + test) is errexit-immune and neither arm can fail the step —
    # the post-state peek-residue assert is this shape.
    if re.match(r'^if .+; then (echo|printf) .+; else (echo|printf) .+; fi\s*(\|\|\s*true)?$', c):
        return True
    if ";" in c:
        clauses = [x.strip() for x in c.split(";") if x.strip()]
        if clauses and all(re.search(r'\|\|\s*true$', x) or "&&" in x
                           or re.match(r'^[a-zA-Z_][a-zA-Z0-9_]*=', x) for x in clauses):
            return True
    if c.startswith("echo "):
        subs = subst_bodies(c)
        if not subs:
            return re.fullmatch(r"echo '[^']*'", c) is not None
        return all(re.search(r'\|\|\s*(?:echo\s|true\b)', s) for s in subs)
    return False

APPROVED = [
    # The ONLY sanctioned fstab read: a field-scoped awk select on mount point
    # == "/mnt/data" (either the bare $2 form or the trailing-slash-normalized
    # `m` copy the post-state print uses). `cat /etc/fstab` never qualifies.
    re.compile(r"awk '[^']* == \"/mnt/data\"[^']*' /etc/fstab[^\"]*"),
    # crypttab is reported as a COUNT only, over the whitespace-tolerant anchor
    # (leading whitespace is live crypttab syntax).
    re.compile(r"grep -c '\^\[\[:space:\]\]\*workspaces\[\[:space:\]\]' /etc/crypttab"),
    re.compile(r"systemctl show -p [A-Za-z,]+ docker\.service"),
    re.compile(r"sha256sum /etc/systemd/system/docker\.service\.d/10-workspaces-luks-mount\.conf"),
    re.compile(r"stat -c '%F %a %U' /etc/default/workspaces-luks-boot"),
    re.compile(r"systemd-analyze verify [a-z.\t -]*"),
    # Sanctioned self-cleanup (the ONE write a print step may perform): deletes
    # only this installer's own uploaded remote-exec payloads — /root's
    # tf-boot-unlock-*.sh is the script_path shape pinned by TF6.
    re.compile(r"find /root -maxdepth 1 -name 'tf-boot-unlock-\*\.sh' -delete \|\| true"),
]
FORBIDDEN = [
    ("journalctl", re.compile(r'\bjournalctl\b')),
    ("systemctl cat/status", re.compile(r'\bsystemctl(?:\s+-{1,2}[\w=.-]+)*\s+(?:cat|status)\b')),
    ("systemctl show with no -p", re.compile(r'\bsystemctl(?:\s+-{1,2}[\w=.-]+)*\s+show\b(?!\s+-p\s)')),
    ("raw ExecStart", re.compile(r'\bExecStart')),
    ("/etc/fstab outside the exact-field awk select", re.compile(r'/etc/fstab\b')),
    ("/etc/crypttab beyond a count", re.compile(r'/etc/crypttab\b')),
    ("/etc/default/luks-monitor at all", re.compile(r'/etc/default/luks-monitor\b')),
    ("apt-config", re.compile(r'\bapt-config\b')),
    ("docker mutation", re.compile(r'\bdocker\s+(?:stop|restart|kill|rm|inspect)\b|\bsystemctl\b[^;|&]*\b(start|restart|stop|disable|mask|kill|try-restart|reload-or-restart)\b[^;|&]*\bdocker\b')),
    # The print steps must be READ-ONLY in fact, not just in name: no shell
    # write/mutation verb may appear anywhere in a print line (review finding —
    # the old deny list only looked at WHAT was read, not whether the step
    # wrote). Two sanctioned exceptions exist ABOVE in APPROVED: the /run peek
    # housekeeping (mkdir/rmdir/mount/umount — transient) and the single
    # `find /root -name 'tf-boot-unlock-*.sh' -delete` self-cleanup of the
    # installer's own uploaded payloads. Anything else matching this pattern REDs.
    ("write verb", re.compile(r'\b(?:rm|mv|cp|tee)\s|\bsed\s+-i\b|>>|-delete\b')),
]
for lname in ("workspaces_boot_unlock_print", "workspaces_boot_unlock_post_state"):
    L = DEC.get(lname, [])
    check("P-%s the print has lines" % lname, len(L) >= 5, len(L))
    unguarded = [c[:100] for c in L if not guarded(c)]
    check("P-%s every print line is guarded (|| true / || echo / for-done-true / &&-chain) — a missing value can never fail the step" % lname,
          bool(L) and not unguarded, unguarded)
    leaks = []
    for c in L:
        residue = c
        for a in APPROVED:
            residue = a.sub("", residue)
        for label, rx in FORBIDDEN:
            if rx.search(residue):
                leaks.append("[%s] %s" % (label, c[:100]))
    check("P-%s no forbidden diagnostic or write verb reaches the public log (journalctl, bare show, raw fstab/crypttab/env, docker mutation, rm/mv/cp/tee/sed -i/>>/-delete)" % lname,
          not leaks, leaks)
    check("P-%s the print references no var./sensitive value and no live interpolation (output stays visible)" % lname,
          bool(LOCALS.get(lname)) and not any(("${" in c.replace("$${", "") or "%{" in c.replace("%%{", "") or re.search(r'\bvar\.', c))
                              for c in LOCALS.get(lname, [])))

bp = DEC.get("workspaces_boot_unlock_print", [])
check("P1 the before-print reads fstab /mnt/data only through the exact-field redacted select, and has_nofail is printed",
      any('awk \'$1 !~ /^#/ && $2 == "/mnt/data"' in c and "<redacted-device>" in c and "<redacted-options>" in c and "has_nofail=" in c for c in bp))
check("P2 the before-print reports crypttab as a COUNT on the whitespace-tolerant anchor, mapper presence, live source, deadman substate",
      any("grep -c '^[[:space:]]*workspaces[[:space:]]' /etc/crypttab" in c for c in bp)
      and any("/dev/mapper/workspaces" in c for c in bp)
      and any("workspaces-luks-deadman.timer" in c for c in bp))
check("P3 the before-print shows every delivered unit's state",
      any("workspaces-luks-reopen.service workspaces-luks-reopen-failure.service workspaces-luks-reopen.timer" in c for c in bp))
ps = DEC.get("workspaces_boot_unlock_post_state", [])
check("P4 the post-state re-reads fstab count + crypttab count + dropin sha256 + unit states",
      any("fstab-mnt-data-lines=" in c and "awk" in c for c in ps)
      and any("crypttab-workspaces-lines=" in c for c in ps)
      and any("dropin-sha256=" in c for c in ps)
      and any("systemctl show -p Id,LoadState,UnitFileState,ActiveState,SubState,Result" in c for c in ps))
check("P5 the post-state re-proves the covered inode via a SECOND peek (lsattr -d under a fresh bind)",
      any("workspaces-boot-unlock-peek-state" in c and "mount --bind" in c and "lsattr -d" in c for c in ps))
check("P5b the post-state asserts peek-residue via a findmnt TARGET scan (a leftover bind is reported, never silent)",
      any('peek-residue=' in c and "findmnt -n -o TARGET" in c for c in ps))
check("P6 the post-state runs systemd-analyze verify on the three delivered units",
      any("systemd-analyze verify workspaces-luks-reopen.service workspaces-luks-reopen-failure.service workspaces-luks-reopen.timer" in c for c in ps))
check("P7 the post-state shows RequiresMountsFor/After AND the Restart/StartLimit* policy on docker.service (the gate + the fails-then-retries evidence, read-only)",
      any(re.search(r'systemctl show -p RequiresMountsFor,After,Restart,StartLimitBurst,StartLimitIntervalSec docker\.service', c) for c in ps))

# Change-detector pins — the public apply log carries ONLY the security-reviewed bytes.
# Regenerate: read the actual= detail of the PIN rows after a deliberate print edit.
with open(os.path.join(SCRATCH, "pins.env"), "w") as fh:
    for lname in ("workspaces_boot_unlock_print", "workspaces_boot_unlock_post_state"):
        body = "\n".join(DEC.get(lname, [])) + "\n"
        fh.write("%s_SHA256=%s\n" % (lname.upper(), hashlib.sha256(body.encode()).hexdigest()))

for v in out:
    print("\t".join(v))
PYEOF
if [ "$rc" -ne 0 ]; then
  cat "$SCRATCH/verdicts.tsv" 2>/dev/null
  printf '[FATAL] the .tf checker exited %s — a broken instrument, not a verdict\n' "$rc" >&2
  exit 2
fi
_before=$((pass + fail)); verdict_lines=0
while IFS=$'\t' read -r v name detail; do
  [[ -n "${v:-}" ]] || continue
  verdict_lines=$((verdict_lines + 1))
  if [[ "$v" == ok ]]; then ok 0 "$name"; else no "$name${detail:+ ($detail)}"; fi
done < "$SCRATCH/verdicts.tsv"
if [[ $((pass + fail - _before)) -ne "$verdict_lines" ]]; then
  printf '[FATAL] %s verdicts read but the counters moved %s — ok()/no() tampered\n' "$verdict_lines" "$((pass + fail - _before))" >&2
  exit 2
fi
# shellcheck disable=SC1090
. "$SCRATCH/pins.env"

# ==================================================================================
# STATIC — the reopen script
# ==================================================================================
SCRIPT_BODY="$SCRATCH/script.body"; strip "$WBU_SCRIPT" > "$SCRIPT_BODY"

n=$(grep -cE '(^|[^[:alnum:]_./-])(mkfs(\.[a-z0-9]+)?|wipefs|blkdiscard|shred|dd)([[:space:]]|$)|cryptsetup[[:space:]]+(luksFormat|luksErase|erase|reencrypt)' "$SCRIPT_BODY" || true)
ok "$([ "$n" -eq 0 ]; echo $?)" "S1 script never formats/wipes (mkfs*/wipefs/blkdiscard/shred/dd/luksFormat/luksErase/reencrypt: $n)"
n=$(grep -cE '^\s*trap ' "$SCRIPT_BODY" || true)
ok "$([ "$n" -eq 0 ]; echo $?)" "S2 script sets no trap — the reporter unit is the single emitter (trap lines: $n)"
n=$(grep -cE '(^|[;&|({!][[:space:]]*|^[[:space:]]+)mount[[:space:]]' "$SCRIPT_BODY" || true)
ok "$([ "$n" -eq 0 ]; echo $?)" "S3 script never calls mount(8) — PID 1 mounts via the fstab unit (mount calls: $n)"
# Every external command must be a BARE name so the stub PATH intercepts it. The one allowed
# absolute literal is the emit-helper fallback path (a file check, not a command).
n=$(grep -c '/usr/local/bin/' "$SCRIPT_BODY" || true)
ok "$([ "$n" -eq 1 ] && grep -qF 'EMIT="/usr/local/bin/workspaces-luks-emit.sh"' "$SCRIPT_BODY"; echo $?)" \
  "S4 the only /usr/local/bin literal is the emit-helper path check (found $n)"
n=$(grep -cE '(^|[[:space:]])(set|(ba)?sh)[[:space:]]+-[a-z]*x' "$SCRIPT_BODY" || true)
ok "$([ "$n" -eq 0 ]; echo $?)" "S5 script never enables xtrace"
ok "$(grep -q 'exit 78' "$SCRIPT_BODY" && grep -q '\*x\*' "$SCRIPT_BODY"; echo $?)" "S5b script refuses to run under -x (exit 78, the #7797 credential guard)"
ok "$(grep -qE '^#!/bin/bash' "$WBU_SCRIPT"; echo $?)" "S6 script is bash (dash has no pipefail)"
ok "$(grep -qE '^set -euo pipefail' "$SCRIPT_BODY"; echo $?)" "S7 script runs under set -euo pipefail"
ok "$(grep -qE 'RUNDIR="\$\{WORKSPACES_REOPEN_RUNDIR:-/run/workspaces-luks-reopen\}"' "$SCRIPT_BODY"; echo $?)" "S8 RUNDIR seam defaults to /run/workspaces-luks-reopen"
ok "$(grep -qE 'DEVICE_WAIT="\$\{WORKSPACES_REOPEN_DEVICE_WAIT:-30\}"' "$SCRIPT_BODY"; echo $?)" "S9 DEVICE_WAIT seam defaults to 30"
ok "$(grep -qE 'WORKSPACES_LUKS_DEV.*\^/dev/disk/by-id/scsi-0HC_Volume_\[0-9\]\+\$' "$SCRIPT_BODY"; echo $?)" "S10 phase config asserts the device-pin shape"
ok "$(grep -qE 'WORKSPACES_DOPPLER_CONFIG.*\^\[a-z0-9_\]\+\$' "$SCRIPT_BODY"; echo $?)" "S11 phase config asserts the config-name shape"

# R9 — THE load-bearing static rows. The pinned form is `doppler secrets get
# WORKSPACES_LUKS_KEY --plain --config "$WORKSPACES_DOPPLER_CONFIG"`; `doppler run` /
# `doppler secrets download` on that config resolve the inherited root set (CWE-522).
ok "$(grep -qF 'doppler secrets get WORKSPACES_LUKS_KEY --plain --config "$WORKSPACES_DOPPLER_CONFIG"' "$SCRIPT_BODY"; echo $?)" \
  "S12 the key fetch is exactly 'doppler secrets get WORKSPACES_LUKS_KEY --plain --config \$WORKSPACES_DOPPLER_CONFIG' (R9)"
n=$(grep -cE 'doppler[[:space:]]+(run|secrets[[:space:]]+download)\b' "$SCRIPT_BODY" || true)
ok "$([ "$n" -eq 0 ]; echo $?)" "S13 no 'doppler run' / 'doppler secrets download' in the script body ($n)"
n=$(grep -c 'prd_workspaces_luks' "$SCRIPT_BODY" || true)
ok "$([ "$n" -eq 0 ]; echo $?)" "S14 the config name is never hardcoded in the script body — it comes from the env file ($n)"
ok "$(grep -qF "printf '%s' \"\$KEY\" | cryptsetup luksOpen --key-file - \"\$DEV\" \"\$MAPPER_NAME\"" "$SCRIPT_BODY"; echo $?)" \
  "S15 the passphrase reaches luksOpen on stdin via --key-file - (never argv)"
n=$(grep -cE 'luksOpen[^|]*\$KEY' "$SCRIPT_BODY" || true)
ok "$([ "$n" -eq 0 ]; echo $?)" "S15b \$KEY is never on the luksOpen argv ($n)"
ok "$(grep -qE '^unset KEY' "$SCRIPT_BODY"; echo $?)" "S16 KEY is unset after the open phase"
ok "$(grep -qxE '[[:space:]]*/mnt/data\) : ;;' "$SCRIPT_BODY"; echo $?)" "S17 phase target allowlists exactly /mnt/data"
ok "$(grep -qF 'expected exactly one' "$SCRIPT_BODY"; echo $?)" "S18 the script's own target phase asserts exactly-one fstab entry for the mapper"

PHASES=$(grep -oE '^\s*phase [a-z-]+' "$SCRIPT_BODY" | awk '{print $2}')
PHASE_COUNT=$(printf '%s\n' "$PHASES" | grep -c . || true)
ok "$([ "$PHASE_COUNT" -eq 10 ]; echo $?)" "S19 the script declares exactly 10 phases (found $PHASE_COUNT)"
EXPECTED_ORDER="config key device header open identity target mount identity-mount emit"
ok "$([ "$(printf '%s\n' "$PHASES" | tr '\n' ' ' | sed 's/ $//')" = "$EXPECTED_ORDER" ]; echo $?)" \
  "S20 phase order is exactly: $EXPECTED_ORDER" "$(printf '%s\n' "$PHASES" | tr '\n' ' ')"

ok "$(grep -qF 'workspaces-luks-emit.sh is absent or unreadable' "$SCRIPT_BODY" && grep -q 'exit 3' "$SCRIPT_BODY"; echo $?)" \
  "S21 the emit phase refuses exit 3 when the reporter's emit helper is absent (structural, not retried)"
ok "$(grep -qF 'logger -t workspaces-luks-reopen --' "$SCRIPT_BODY"; echo $?)" "S22 the success row is logger -t workspaces-luks-reopen (journald-only)"
n=$(grep -cE '\bworkspaces_luks_emit\b' "$SCRIPT_BODY" || true)
ok "$([ "$n" -eq 0 ]; echo $?)" "S23 the script NEVER calls workspaces_luks_emit — emit is the reporter's alone ($n)"
# The emit-channel structural check is UNCONDITIONAL (hoisted out of the noop
# gate: the installer's noop proof run also certifies the reporter's paging
# channel). Pin the topology: docker-gate `if` < its `fi` < `[ -r "$EMIT" ]` <
# the emit-logger `if` — i.e. the check sits between the two ACTION gates, at
# top level, on every arm.
_ng=$(grep -cF 'if [ "$ACTION" != noop ]' "$SCRIPT_BODY" || true)
_dg=$(grep -nF 'if [ "$ACTION" != noop ]' "$SCRIPT_BODY" | cut -d: -f1 | head -1)
_lg=$(grep -nF 'if [ "$ACTION" != noop ]' "$SCRIPT_BODY" | cut -d: -f1 | tail -1)
_em=$(grep -nF '[ -r "$EMIT" ]' "$SCRIPT_BODY" | cut -d: -f1 | head -1)
_fi=$(awk -v L="${_em:-0}" 'NR<L && /^fi[[:space:]]*$/ {g=NR} END{print g+0}' "$SCRIPT_BODY")
ok "$([ "$_ng" -eq 2 ] && [ -n "$_em" ] && [ "$_dg" -lt "$_fi" ] && [ "$_fi" -lt "$_em" ] && [ "$_em" -lt "$_lg" ]; echo $?)" \
  "S24 the emit-channel assert is UNCONDITIONAL — docker-gate < fi < [ -r EMIT ] < logger-gate (ng=$_ng dg=$_dg fi=$_fi em=$_em lg=$_lg)"
n=$(grep -cE 'RuntimeDirectory|ExecStart|EnvironmentFile' "$SCRIPT_BODY" || true)
ok "$([ "$n" -eq 0 ]; echo $?)" "S25 the script carries no unit directives (script-vs-unit separation: $n)"
# The ONE sanctioned docker command: `systemctl start docker.service`, the
# first line of the ACTION!=noop recovery arm (a dependency-failed docker does
# not re-queue once /mnt/data mounts). Any OTHER docker invocation — or the
# same one outside that arm — must RED here.
n=$(grep -oF 'docker.service' "$SCRIPT_BODY" | wc -l)
_dk=$(grep -nxF '  systemctl start docker.service 2>>"$LOG" \' "$SCRIPT_BODY" | cut -d: -f1)
_dg=$(awk -v L="${_dk:-0}" 'NR<L && /^if \[ "\$ACTION" != noop \]; then$/ {g=NR} END{print g+0}' "$SCRIPT_BODY")
ok "$([ "$n" -eq 2 ] && [ -n "$_dk" ] && [ "$_dg" -gt 0 ] && [ "$((_dk - _dg))" -eq 1 ]; echo $?)" \
  "S26 docker appears exactly twice — 'systemctl start docker.service' as the first line of an ACTION!=noop arm plus its nonfatal logger (any other docker call REDs; mentions=$n start=${_dk:-?} gate=${_dg:-0})"

# ==================================================================================
# STATIC — the reopen unit
# ==================================================================================
UNIT_BODY="$SCRATCH/unit.body"; strip "$WBU_UNIT" > "$UNIT_BODY"
unit_has() { grep -qxF -- "$2" "$1"; echo $?; }
u_section_of() { awk -v key="$2" '/^\[/{s=$0} $0==key{print s; exit}' "$1"; }

ok "$(unit_has "$UNIT_BODY" 'OnFailure=workspaces-luks-reopen-failure.service')" "U1 unit names the reporter via OnFailure="
ok "$([ "$(u_section_of "$UNIT_BODY" 'OnFailure=workspaces-luks-reopen-failure.service')" = "[Unit]" ]; echo $?)" "U1b OnFailure= is under [Unit] (ignored under [Service])"
ok "$(unit_has "$UNIT_BODY" 'Type=oneshot')" "U2 Type=oneshot"
ok "$(unit_has "$UNIT_BODY" 'RemainAfterExit=yes')" "U3 RemainAfterExit=yes"
ok "$(unit_has "$UNIT_BODY" 'Restart=on-failure')" "U4 Restart=on-failure (bounded retry, no in-script loop)"
ok "$(unit_has "$UNIT_BODY" 'RestartMode=direct')" "U5 RestartMode=direct — OnFailure fires once at convergence, not per attempt"
ok "$([ "$(u_section_of "$UNIT_BODY" 'RestartMode=direct')" = "[Service]" ]; echo $?)" "U5b RestartMode= is under [Service]"
ok "$(unit_has "$UNIT_BODY" 'RestartPreventExitStatus=3')" "U6 RestartPreventExitStatus=3 — the structural-emitter refusal is terminal on attempt 1"
ok "$(unit_has "$UNIT_BODY" 'RestartSec=60')" "U7 RestartSec=60"
_slb=$(grep -E '^StartLimitBurst=' "$UNIT_BODY" | sed -n '1p'); _sli=$(grep -E '^StartLimitIntervalSec=' "$UNIT_BODY" | sed -n '1p')
ok "$([ "$_slb" = "StartLimitBurst=5" ] && [ "$_sli" = "StartLimitIntervalSec=1h" ]; echo $?)" "U8 the ladder is 5 attempts / 1h (got '$_slb' '$_sli')"
ok "$([ "$(u_section_of "$UNIT_BODY" "$_slb")" = "[Unit]" ] && [ "$(u_section_of "$UNIT_BODY" "$_sli")" = "[Unit]" ]; echo $?)" "U8b StartLimitBurst/IntervalSec are under [Unit]"
ok "$(unit_has "$UNIT_BODY" 'Environment=HOME=/root')" "U9 HOME=/root (doppler dies without it)"
ok "$(unit_has "$UNIT_BODY" 'EnvironmentFile=-/etc/default/luks-monitor')" "U10 reads the shared env file (DOPPLER_TOKEN — READ-ONLY consumer)"
ok "$(unit_has "$UNIT_BODY" 'EnvironmentFile=-/etc/default/workspaces-luks-boot')" "U11 reads the installer's own env file (device pin + config name)"
ok "$(unit_has "$UNIT_BODY" 'RuntimeDirectory=workspaces-luks-reopen')" "U12 RuntimeDirectory=workspaces-luks-reopen"
ok "$(unit_has "$UNIT_BODY" 'RuntimeDirectoryPreserve=yes')" "U13 RuntimeDirectoryPreserve=yes — systemd removes the dir at final failure before OnFailure runs"
ok "$(unit_has "$UNIT_BODY" 'UMask=0077')" "U14 UMask=0077"
ok "$(unit_has "$UNIT_BODY" 'NoNewPrivileges=yes')" "U15 NoNewPrivileges=yes"
ok "$(unit_has "$UNIT_BODY" 'LimitCORE=0')" "U16 LimitCORE=0 — a crash must not dump the passphrase to /var/crash"
ok "$(unit_has "$UNIT_BODY" 'PrivateTmp=yes')" "U17 PrivateTmp=yes (confines the doppler cache dir)"
ok "$(unit_has "$UNIT_BODY" 'ExecStartPre=/bin/rm -f /run/workspaces-luks-reopen/action /run/workspaces-luks-reopen/log')" "U18 ExecStartPre clears the phase/log files per attempt"
ok "$(unit_has "$UNIT_BODY" 'ExecStart=/usr/local/bin/workspaces-luks-reopen.sh')" "U19 ExecStart is the bare script (no doppler run wrapper — the CWE-522 hole)"
ok "$(grep -qE '^TimeoutStartSec=[0-9]+$' "$UNIT_BODY"; echo $?)" "U20 TimeoutStartSec set"
ok "$(unit_has "$UNIT_BODY" 'SyslogIdentifier=workspaces-luks-reopen')" "U21 SyslogIdentifier=workspaces-luks-reopen — MUST equal the vector.toml tag"
ok "$(unit_has "$UNIT_BODY" 'After=network-online.target')" "U22 After=network-online.target"
ok "$(unit_has "$UNIT_BODY" 'Wants=network-online.target')" "U22b Wants=network-online.target"
ok "$(unit_has "$UNIT_BODY" 'WantedBy=multi-user.target')" "U23 WantedBy=multi-user.target"
n=$(grep -c 'RequiresMountsFor' "$UNIT_BODY" || true)
ok "$([ "$n" -eq 0 ]; echo $?)" "U24 the reopen unit carries NO RequiresMountsFor — Requires-strength belongs on docker.service, the consumer ($n)"
n=$(grep -cE 'doppler run|doppler secrets download' "$UNIT_BODY" || true)
ok "$([ "$n" -eq 0 ]; echo $?)" "U25 no doppler run/download in the unit (R9: the script fetches with secrets get --plain: $n)"
n=$(grep -c 'WORKSPACES_REOPEN_' "$UNIT_BODY" || true)
ok "$([ "$n" -eq 0 ]; echo $?)" "U26 no test seam set in the unit ($n)"

# ==================================================================================
# STATIC — the reporter unit
# ==================================================================================
REP_BODY="$SCRATCH/rep.body"; strip "$WBU_REPORTER" > "$REP_BODY"
ok "$(unit_has "$REP_BODY" 'Type=oneshot')" "R1 reporter Type=oneshot"
ok "$(unit_has "$REP_BODY" 'Environment=HOME=/root')" "R2 reporter HOME=/root"
ok "$(unit_has "$REP_BODY" 'EnvironmentFile=-/etc/default/luks-monitor')" "R3 reporter reads the shared env file (baked DSN + token)"
ok "$(unit_has "$REP_BODY" 'EnvironmentFile=-/etc/default/workspaces-luks-boot')" "R4 reporter reads the installer env file (config name)"
ok "$(unit_has "$REP_BODY" 'UMask=0077')" "R5 reporter UMask=0077"
ok "$(unit_has "$REP_BODY" 'PrivateTmp=yes')" "R6 reporter PrivateTmp=yes"
ok "$(unit_has "$REP_BODY" 'LimitCORE=0')" "R7 reporter LimitCORE=0"
ok "$(unit_has "$REP_BODY" 'SyslogIdentifier=workspaces-luks-reopen')" "R8 reporter SyslogIdentifier=workspaces-luks-reopen — its classification echo must ride the vector tag too"
ok "$(grep -qF '/run/workspaces-luks-reopen/action' "$REP_BODY"; echo $?)" "R9 reporter reads the phase file"
ok "$(grep -qF 'a=unit' "$REP_BODY"; echo $?)" "R10 reporter falls back to action=unit when no phase file exists"
ok "$(grep -qF 'boot_unlock_failed:' "$REP_BODY"; echo $?)" "R11 reason slug is boot_unlock_failed:<phase>"
ok "$(grep -qF 'WL_LEVEL=fatal' "$REP_BODY"; echo $?)" "R12 emit level is fatal"
ok "$(grep -qF 'timeout 90' "$REP_BODY"; echo $?)" "R13 the emit leg is timeout-bounded (a hang must not eat TimeoutStartSec)"
ok "$(grep -qF 'timeout 15' "$REP_BODY"; echo $?)" "R14 the doppler_reachable probe is timeout-bounded"
ok "$(grep -qF 'doppler secrets --only-names --config' "$REP_BODY"; echo $?)" "R15 the reachability probe is the NON-SECRET 'doppler secrets --only-names --config <scoped>' form (names listing proves reachability+scope; no value transits the probe)"
n=$(grep -c 'secrets get' "$REP_BODY" || true)
ok "$([ "$n" -eq 0 ]; echo $?)" "R15b the probe reads NO secret value — no 'secrets get' anywhere in the reporter ($n)"
ok "$(grep -qF 'sed "s/[[:cntrl:]]//g' "$REP_BODY" && grep -qF 'grep -iE "doppler error|unable to|failed|fatal|error" | tail -n 4' "$REP_BODY"; echo $?)" \
  "R15c the log tail ANSI-strips, then keyword-filters, then tail -n 4 (a raw tail would ship ANSI junk and noise)"
n=$(grep -cE 'doppler run|secrets download' "$REP_BODY" || true)
ok "$([ "$n" -eq 0 ]; echo $?)" "R16 no doppler run/download in the reporter ($n)"
for t in WL_MAPPER_PRESENT WL_CRYPTSETUP_UNIT_RESULT WL_MOUNTPOINT_OK WL_MOUNT_SOURCE WL_DOPPLER_REACHABLE WL_LUKS_OPEN_RESULT WL_REASON; do
  ok "$(grep -qF "$t=" "$REP_BODY"; echo $?)" "R17 reporter carries $t"
done
ok "$(grep -qF 'SOLEUR_WORKSPACES_LUKS_SEND_FAILED' "$REP_BODY"; echo $?)" "R18 the emit leg's failure mirrors to a crit SOLEUR_WORKSPACES_LUKS_SEND_FAILED row"
_rep_tmo=$(grep -oE '^TimeoutStartSec=[0-9]+' "$REP_BODY" | grep -oE '[0-9]+' | sed -n '1p')
ok "$([ -n "$_rep_tmo" ] && [ "$_rep_tmo" -ge 120 ]; echo $?)" "R19 reporter TimeoutStartSec (${_rep_tmo:-?}) covers the 90 s emit + 15 s probe + slack"
n=$(grep -c 'WORKSPACES_REOPEN_' "$WBU_TIMER" || true)
ok "$([ "$n" -eq 0 ]; echo $?)" "R20 no test seam set in the timer ($n)"

# ==================================================================================
# STATIC — the timer
# ==================================================================================
TIMER_BODY="$SCRATCH/timer.body"; strip "$WBU_TIMER" > "$TIMER_BODY"
ok "$(unit_has "$TIMER_BODY" 'OnUnitActiveSec=15min')" "T1 OnUnitActiveSec=15min — the standing retry after the start-limit window"
ok "$(unit_has "$TIMER_BODY" 'OnBootSec=15min')" "T2 OnBootSec=15min"
ok "$(unit_has "$TIMER_BODY" 'RandomizedDelaySec=120')" "T3 RandomizedDelaySec=120"
ok "$(unit_has "$TIMER_BODY" 'WantedBy=timers.target')" "T4 WantedBy=timers.target"
n=$(grep -c '^Persistent=' "$TIMER_BODY" || true)
ok "$([ "$n" -eq 0 ]; echo $?)" "T5 NO Persistent= — it only has an effect with OnCalendar=, which this timer does not use ($n)"
n=$(grep -c '^OnCalendar=' "$TIMER_BODY" || true)
ok "$([ "$n" -eq 0 ]; echo $?)" "T6 NO OnCalendar= — monotonic, so a long outage does not fire a burst ($n)"
n=$(grep -c '^Unit=' "$TIMER_BODY" || true)
ok "$([ "$n" -eq 0 ]; echo $?)" "T7 no explicit Unit= — triggers the namesake service by default ($n)"

# ==================================================================================
# STATIC — workflow -target= line + vector.toml tag
# ==================================================================================
n=$(grep -c -- '-target=terraform_data.workspaces_boot_unlock_install' "$WBU_WF" || true)
ok "$([ "$n" -eq 1 ]; echo $?)" "WF1 the SSH apply lists -target=terraform_data.workspaces_boot_unlock_install exactly once ($n)"
_l_mi=$(grep -n -- '-target=terraform_data.luks_monitor_install' "$WBU_WF" | sed -n '1p' | cut -d: -f1)
_l_wbu=$(grep -n -- '-target=terraform_data.workspaces_boot_unlock_install' "$WBU_WF" | sed -n '1p' | cut -d: -f1)
ok "$([ -n "$_l_mi" ] && [ -n "$_l_wbu" ] && [ "$_l_wbu" -gt "$_l_mi" ]; echo $?)" "WF2 the new target is ordered after luks_monitor_install (${_l_mi:-?} < ${_l_wbu:-?})"

# The vector tag: extract the host_scripts_journald include_matches.SYSLOG_IDENTIFIER list.
VEC_BLOCK=$(awk '/^\[sources\.host_scripts_journald\]/{f=1} f{print} f&&/^include_matches\.SYSLOG_IDENTIFIER/{l=1} l&&/\]/{exit}' "$WBU_VECTOR")
n=$(printf '%s\n' "$VEC_BLOCK" | grep -c '"workspaces-luks-reopen"' || true)
ok "$([ "$n" -eq 1 ]; echo $?)" "V1 vector.toml include_matches.SYSLOG_IDENTIFIER carries \"workspaces-luks-reopen\" exactly once ($n)"
ok "$(printf '%s\n' "$VEC_BLOCK" | grep -q '"luks-monitor"'; echo $?)" "V2 the same list still carries the sibling luks-monitor tag (extraction sanity)"

# systemd-analyze verify (present on systemd hosts; a failure here is a verdict, not a skip).
# The verify rc is checked SEPARATELY from the filtered output — a nonzero rc with
# only exempted noise still counts, and an absent binary emits an explicit [skip].
if command -v systemd-analyze >/dev/null 2>&1; then
  assert_fixture_dir "$SCRATCH"
  mkdir -p "$SCRATCH/units"
  cp "${WBU_UNIT:?}" "${WBU_REPORTER:?}" "${WBU_TIMER:?}" "${SCRATCH:?}/units/"
  _saout=$(cd "$SCRATCH/units" && systemd-analyze verify ./*.service ./*.timer 2>&1); _sarc=$?
  _saflt=$(printf '%s\n' "$_saout" | grep -vE 'Command /usr/local/bin/[a-z0-9-]+\.[a-z]+ is not executable' || true)
  n=$(printf '%s\n' "$_saflt" | grep -cE 'workspaces-luks-reopen[^:]*\.(service|timer):' || true)
  # rc is checked SEPARATELY from the filtered output: clean means every
  # diagnostic line was exempted (host-dependent exec-path presence) AND rc is
  # not a crash (>=128). A nonzero rc carrying ONLY exempted lines still passes —
  # the exemption is the reviewed shape; anything else is a verdict.
  ok "$([ "$n" -eq 0 ] && [ -z "$(printf '%s' "$_saflt" | tr -d '[:space:]')" ] && [ "$_sarc" -lt 128 ]; echo $?)" \
    "Y1 systemd-analyze verify clean over the three units (rc=$_sarc; exec-path presence warnings exempted: host-dependent, pinned statically by U19)" "rc=$_sarc ${_saout:0:400}"
else
  printf '[skip] Y1 systemd-analyze absent on this host — the U/T static rows still pin the unit shape\n'
fi

# ==================================================================================
# BEHAVIOURAL — the decoded writer/print locals run under sh + stub PATH + scratch fs
# ==================================================================================
mkdir -p "$SCRATCH/wbin"
wstub() {
  { printf '%s\n' '#!/bin/bash' 'printf "%s|%s\n" "$(basename "$0")" "$*" >> "${FX:?}/calls.log"; [ -f "${FX:?}/dark" ] && exit 1'; cat; } > "$SCRATCH/wbin/$1"
  chmod +x "$SCRATCH/wbin/$1"
}
wstub systemctl <<'EOF'
u=""; p=""; prev=""
for a in "$@"; do case "$prev" in -p) p="$a";; esac; prev="$a"; u="$a"; done
if [ "$1" = show ]; then
  case "$u:$p" in
    workspaces-luks-deadman.timer:SubState) cat "$FX/deadman_substate" 2>/dev/null || echo dead ;;
    workspaces-luks-reopen.service:SubState) cat "$FX/reopen_substate" 2>/dev/null || echo exited ;;
    workspaces-luks-reopen.service:Result) cat "$FX/reopen_result" 2>/dev/null || echo success ;;
    workspaces-luks-reopen.service:ExecMainStatus) cat "$FX/reopen_execstatus" 2>/dev/null || echo 0 ;;
    *) : ;;
  esac
  exit 0
fi
rc=$(cat "$FX/systemctl_rc" 2>/dev/null || echo 0)
if [ "$1" = start ] && [ -f "$FX/systemctl_rc_start" ]; then rc=$(cat "$FX/systemctl_rc_start"); fi
exit "$rc"
EOF
wstub findmnt <<'EOF'
# `findmnt -n -o TARGET <glob>` answers the peek-residue scan from $FX/peek_residue
# (absent/empty -> none); everything else is a SOURCE query -> $FX/live_source.
for a in "$@"; do
  [ "$a" = TARGET ] && { cat "$FX/peek_residue" 2>/dev/null; exit; }
done
cat "$FX/live_source" 2>/dev/null || echo /dev/mapper/workspaces; exit 0
EOF
wstub mount <<'EOF'
# `mount --bind / <peek>` makes the root tree visible under the peek — simulate by
# materialising the covered dir the writer then chattrs, UNLESS it already exists
# (a planted symlink is evidence for the writer's -L refusal, never followed).
# $FX/mount_rc fails the bind (the exit-54 arm); a success drops .bind-mounted,
# the flag the mountpoint stub reads.
if [ "$1" = "--bind" ]; then
  rc=$(cat "$FX/mount_rc" 2>/dev/null || echo 0)
  [ "$rc" -ne 0 ] && { echo "mount: bind $2 -> $3 failed" >&2; exit "$rc"; }
  [ -e "$3/mnt/data" ] || [ -L "$3/mnt/data" ] || mkdir -p "$3/mnt/data"
  : > "$3/.bind-mounted"
  exit 0
fi
exit 0
EOF
wstub mountpoint <<'EOF'
# `mountpoint -q <dir>`: "mounted" iff the mount stub left its .bind-mounted flag.
d="${@: -1}"
[ -f "$d/.bind-mounted" ] && exit 0
exit 32
EOF
wstub stat <<'EOF'
# `stat -c %d <path>` (the gate's peek-vs-root device-identity assert) is knobbed:
# $FX/dev_root / $FX/dev_peek override; default equal (the bind "landed"). Every
# other format falls through to the real stat.
if [ "$1" = "-c" ] && [ "$2" = "%d" ]; then
  case "$3" in
    /) v=$(cat "$FX/dev_root" 2>/dev/null) ;;
    *) v=$(cat "$FX/dev_peek" 2>/dev/null) ;;
  esac
  printf '%s\n' "${v:-42}"
  exit 0
fi
exec /usr/bin/stat "$@"
EOF
wstub umount <<'EOF'
# A successful umount clears the bind flag so the writer's `while mountpoint -q`
# loop terminates; a failed one keeps it (the loop's `|| break` then escapes).
rc=$(cat "$FX/umount_rc" 2>/dev/null || echo 0)
[ "$rc" -eq 0 ] && rm -f "$1/.bind-mounted"
exit "$rc"
EOF
wstub chattr <<'EOF'
rc=$(cat "$FX/chattr_rc" 2>/dev/null || echo 0)
exit "$rc"
EOF
wstub lsattr <<'EOF'
# `lsattr -d <path>` prints "<flags> <path>"; flags carry 'i' only when the fixture says so.
if [ -f "$FX/no_i" ]; then printf -- '--------------e----- %s\n' "${@: -1}"; else printf -- '----i--------e----- %s\n' "${@: -1}"; fi
exit 0
EOF
wstub chown <<'EOF'
rc=$(cat "$FX/chown_rc" 2>/dev/null || echo 0)
exit "$rc"
EOF
wstub systemd-analyze <<'EOF'
exit 0
EOF
wstub uptime <<'EOF'
echo '2026-09-28 00:00:00'
EOF
# Traps: these must never be invoked by ANY writer/print — a call lands in calls.log AND
# exits 99, so both the log row and the step's rc observe it.
for _t in cryptsetup doppler journalctl docker curl; do
  wstub "$_t" <<'EOF'
echo "FORBIDDEN CALL: $0 $*" >&2; exit 99
EOF
done

# rewrite_body <decoded-file> <fixture-dir>: map host paths into the fixture root.
# /tmp is rewritten FIRST — the fixture root lives under TMPDIR (whose path itself may
# contain /var/tmp or /tmp), so every later substitution must run on text that has no
# fixture paths in it yet.
rewrite_body() {
  local src="$1" d="$2"
  assert_fixture_dir "$d"
  sed -e "s#/tmp#$d/tmp#g" \
      -e "s#/etc/default/workspaces-luks-boot#$d/envfile#g" \
      -e "s#/etc/fstab#$d/fstab#g" \
      -e "s#/etc/crypttab#$d/crypttab#g" \
      -e "s#/etc/systemd/system#$d/systemd#g" \
      -e "s#/usr/local/bin#$d/bin#g" \
      -e "s#/run/workspaces-boot-unlock-peek#$d/peek#g" \
      -e "s#/var/run/reboot-required#$d/reboot-required#g" \
      -e "s#/root#$d/root#g" \
      "$src" > "$d/body.sh"
  # The rewrite must consume EVERY host path; a leftover means a write could escape the fixture.
  if grep -qE '/etc/fstab|/etc/crypttab|/etc/systemd|/usr/local/bin|/run/workspaces|/etc/default' "$d/body.sh"; then
    printf '[FATAL] path rewrite left a host path in %s\n' "$d/body.sh" >&2
    grep -nE '/etc/fstab|/etc/crypttab|/etc/systemd|/usr/local/bin|/run/workspaces|/etc/default' "$d/body.sh" >&2
    exit 2
  fi
}
WFX=""
new_wfixture() {  # $1 = name
  assert_fixture_dir "$SCRATCH"
  WFX="$SCRATCH/wfx-$1"; assert_fixture_dir "$WFX"
  rm -rf "$WFX"; mkdir -p "$WFX/bin" "$WFX/tmp" "$WFX/root" "$WFX/systemd"
  : > "$WFX/calls.log"
  # The envfile writer chmods delivered files — they must exist.
  : > "$WFX/bin/workspaces-luks-reopen.sh"
  : > "$WFX/systemd/workspaces-luks-reopen.service"
  : > "$WFX/systemd/workspaces-luks-reopen-failure.service"
  : > "$WFX/systemd/workspaces-luks-reopen.timer"
  chmod 0644 "$WFX/bin/workspaces-luks-reopen.sh"
  export FX="$WFX"
}
run_writer() {  # $1 = local name; reads $WFX; returns the body's rc
  rewrite_body "$SCRATCH/dec/$1.sh" "$WFX"
  ( env -i PATH="$SCRATCH/wbin:/usr/bin:/bin" HOME="$WFX" FX="$WFX" sh "$WFX/body.sh" > "$WFX/out" 2> "$WFX/err" )
}
# The writer's own normalized matcher: trailing slashes on a COPY of $2, so a
# `/mnt/data/` line counts as the same mount point.
fstab_counts() { awk '{ m=$2; sub(/\/+$/,"",m); if ($1 !~ /^#/ && m == "/mnt/data") n++ } END {print n+0}' "$1"; }

# --- exit-17 freeze refusal: EVERY mutating local refuses under a live dead-man ---------
# (listed in the pinned apply order: crypttab -> envfile -> gate -> fstab -> arm)
for _loc in crypttab_writer envfile_writer gate_writer fstab_writer arm; do
  new_wfixture "freeze-$_loc"; echo waiting > "$WFX/deadman_substate"
  run_writer "workspaces_boot_unlock_$_loc"; _rc=$?
  ok "$([ "$_rc" -eq 17 ]; echo $?)" "W-freeze[$_loc] refuses exit 17 while workspaces-luks-deadman.timer is SubState=waiting (rc=$_rc)" "$(head -3 "$WFX/err" "$WFX/out" 2>/dev/null)"
done
# …and the BEFORE-print still runs (read-only, must never be frozen out) even with every
# probe stub failing (the `dark` flag makes all wbin stubs exit 1 after recording).
new_wfixture freeze-print; echo waiting > "$WFX/deadman_substate"; touch "$WFX/dark"
run_writer workspaces_boot_unlock_print; _rc=$?
ok "$([ "$_rc" -eq 0 ]; echo $?)" "W-freeze[print] the before-print exits 0 under a live freeze with every probe failing (rc=$_rc)"

# --- envfile writer ----------------------------------------------------------------------
new_wfixture envfile-ok
run_writer workspaces_boot_unlock_envfile_writer; _rc=$?
ok "$([ "$_rc" -eq 0 ]; echo $?)" "W-envfile happy path exits 0 (rc=$_rc)" "$(tail -3 "$WFX/err")"
ok "$(grep -qxF "WORKSPACES_LUKS_DEV=$PIN_DEV" "$WFX/envfile" && grep -qxF 'WORKSPACES_DOPPLER_CONFIG=prd_workspaces_luks' "$WFX/envfile"; echo $?)" "W-envfile carries the by-id pin + the scoped config name"
ok "$([ "$(wc -l < "$WFX/envfile")" -eq 2 ]; echo $?)" "W-envfile has exactly 2 lines"
ok "$([ "$(stat -c %a "$WFX/envfile")" = 600 ]; echo $?)" "W-envfile is mode 0600"
n=$(grep -cE 'DOPPLER_TOKEN|WORKSPACES_LUKS_KEY' "$WFX/envfile" || true)
ok "$([ "$n" -eq 0 ]; echo $?)" "W-envfile carries NO token and NO passphrase ($n)"
ok "$([ "$(stat -c %a "$WFX/bin/workspaces-luks-reopen.sh")" = 755 ]; echo $?)" "W-envfile chmodded the delivered script 0755"
ok "$([ "$(stat -c %a "$WFX/systemd/workspaces-luks-reopen.timer")" = 644 ]; echo $?)" "W-envfile chmodded the units 0644"
ok "$([ "$(grep -c 'systemctl|' "$WFX/calls.log")" -ge 1 ]; echo $?)" "W-envfile consulted the dead-man first"
new_wfixture envfile-sym; ln -s "$WFX/victim" "$WFX/envfile"
run_writer workspaces_boot_unlock_envfile_writer; _rc=$?
ok "$([ "$_rc" -eq 20 ]; echo $?)" "W-envfile symlink refused exit 20 (rc=$_rc)"

# --- crypttab writer ----------------------------------------------------------------------
new_wfixture crypttab-absent
run_writer workspaces_boot_unlock_crypttab_writer; _rc=$?
ok "$([ "$_rc" -eq 0 ]; echo $?)" "W-crypttab absent file -> created + appended (rc=$_rc)" "$(tail -3 "$WFX/err")"
ok "$(grep -qxF "workspaces $PIN_DEV none luks,noauto" "$WFX/crypttab"; echo $?)" "W-crypttab the canonical by-id none luks,noauto line was appended"
new_wfixture crypttab-idem; printf 'workspaces %s none luks,noauto\nother UUID=x none luks\n' "$PIN_DEV" > "$WFX/crypttab"
run_writer workspaces_boot_unlock_crypttab_writer; _rc=$?
ok "$([ "$_rc" -eq 0 ] && [ "$(grep -c '^[[:space:]]*workspaces[[:space:]]' "$WFX/crypttab")" -eq 1 ]; echo $?)" "W-crypttab idempotent: still exactly one workspaces line (rc=$_rc)"
new_wfixture crypttab-indented; printf '  workspaces %s none luks,noauto\n' "$PIN_DEV" > "$WFX/crypttab"
run_writer workspaces_boot_unlock_crypttab_writer; _rc=$?
ok "$([ "$_rc" -eq 32 ] && [ "$(grep -c . "$WFX/crypttab")" -eq 1 ]; echo $?)" \
  "W-crypttab an INDENTED workspaces mapping is detected as foreign and refused exit 32 — never shadowed by a second line (rc=$_rc)"
new_wfixture crypttab-foreign; printf 'workspaces /dev/disk/by-label/workspaces_luks none luks,nofail\n' > "$WFX/crypttab"
run_writer workspaces_boot_unlock_crypttab_writer; _rc=$?
ok "$([ "$_rc" -eq 32 ]; echo $?)" "W-crypttab a foreign ^workspaces line is refused exit 32 — never coexisted with (rc=$_rc)"
new_wfixture crypttab-two; printf 'workspaces a none luks\nworkspaces b none luks\n' > "$WFX/crypttab"
run_writer workspaces_boot_unlock_crypttab_writer; _rc=$?
ok "$([ "$_rc" -eq 31 ]; echo $?)" "W-crypttab two ^workspaces lines refused exit 31 (rc=$_rc)"
new_wfixture crypttab-sym; ln -s "$WFX/victim" "$WFX/crypttab"
run_writer workspaces_boot_unlock_crypttab_writer; _rc=$?
ok "$([ "$_rc" -eq 30 ]; echo $?)" "W-crypttab symlink refused exit 30 (rc=$_rc)"

# --- fstab writer ----------------------------------------------------------------------
FSTAB_GLOB='# /etc/fstab: static
/dev/disk/by-id/scsi-0HC_Volume_* /mnt/data ext4 defaults 0 2
UUID=root / ext4 defaults 0 1
'
new_wfixture fstab-glob; printf '%s' "$FSTAB_GLOB" > "$WFX/fstab"
run_writer workspaces_boot_unlock_fstab_writer; _rc=$?
ok "$([ "$_rc" -eq 0 ]; echo $?)" "W-fstab glob-line fstab rewritten (rc=$_rc)" "$(tail -3 "$WFX/err")"
ok "$([ "$(fstab_counts "$WFX/fstab")" -eq 1 ]; echo $?)" "W-fstab exactly one non-comment /mnt/data entry"
ok "$(grep -qxF '/dev/mapper/workspaces /mnt/data ext4 defaults,nofail 0 2' "$WFX/fstab"; echo $?)" "W-fstab the surviving entry is the mapper+ext4+nofail line"
ok "$(grep -qE '^# boot-unlock-9123-superseded /dev/disk/by-id/scsi-0HC_Volume_\* ' "$WFX/fstab"; echo $?)" "W-fstab the superseded glob line is preserved COMMENTED (evidence, not deletion)"
ok "$(ls "$WFX"/fstab.boot-unlock-*.bak >/dev/null 2>&1; echo $?)" "W-fstab a backup was taken"
new_wfixture fstab-two; printf '/dev/sdx /mnt/data ext4 defaults 0 2\n/dev/sdy /mnt/data ext4 nofail 0 2\n' > "$WFX/fstab"
run_writer workspaces_boot_unlock_fstab_writer; _rc=$?
ok "$([ "$_rc" -eq 0 ] && [ "$(fstab_counts "$WFX/fstab")" -eq 1 ]; echo $?)" "W-fstab two pre-existing /mnt/data lines collapse to exactly one (rc=$_rc)"
new_wfixture fstab-trailslash; printf '/dev/sdx /mnt/data/ ext4 defaults 0 2\nUUID=root / ext4 defaults 0 1\n' > "$WFX/fstab"
run_writer workspaces_boot_unlock_fstab_writer; _rc=$?
ok "$([ "$_rc" -eq 0 ]; echo $?)" "W-fstab a trailing-slash '/mnt/data/' line is normalized into the comment step (rc=$_rc)" "$(tail -3 "$WFX/err")"
ok "$(grep -qF '# boot-unlock-9123-superseded /dev/sdx /mnt/data/ ext4' "$WFX/fstab"; echo $?)" "W-fstab the superseded trailing-slash line is preserved COMMENTED, byte-exact (the / stayed)"
ok "$([ "$(fstab_counts "$WFX/fstab")" -eq 1 ] && [ "$(wc -l < "$WFX/fstab")" -eq 3 ]; echo $?)" "W-fstab the rewrite is exactly +1 lines and one non-comment /mnt/data entry survives"
new_wfixture fstab-chownfail; printf 'x\n' > "$WFX/fstab"; echo 1 > "$WFX/chown_rc"
run_writer workspaces_boot_unlock_fstab_writer; _rc=$?
ok "$([ "$_rc" -eq 47 ]; echo $?)" "W-fstab a chown failure refuses exit 47 — split from chmod precisely so an && cannot errexit-immune it (rc=$_rc)" "$(tail -3 "$WFX/err")"
new_wfixture fstab-absent; rm -f "$WFX/fstab"
run_writer workspaces_boot_unlock_fstab_writer; _rc=$?
ok "$([ "$_rc" -eq 41 ]; echo $?)" "W-fstab absent fstab refused exit 41 (rc=$_rc)"
new_wfixture fstab-sym; ln -s "$WFX/victim" "$WFX/fstab"
run_writer workspaces_boot_unlock_fstab_writer; _rc=$?
ok "$([ "$_rc" -eq 40 ]; echo $?)" "W-fstab symlink refused exit 40 (rc=$_rc)"
new_wfixture fstab-notlive; printf 'x\n' > "$WFX/fstab"; echo /dev/sdz > "$WFX/live_source"
run_writer workspaces_boot_unlock_fstab_writer; _rc=$?
ok "$([ "$_rc" -eq 42 ]; echo $?)" "W-fstab refuses when the live /mnt/data source is not the mapper (rc=$_rc)"
# refuse-on-2+: an awk that passes the /mnt/data line through uncommented (a broken edit's
# output shape) — the writer's own post-edit assert must still fire.
new_wfixture fstab-twopost; printf '/dev/sdx /mnt/data ext4 defaults 0 2\n' > "$WFX/fstab"
printf '#!/bin/bash\nprintf "awk|%%s\\n" "$*" >> "${FX:?}/calls.log"\nwhile [ $# -gt 1 ]; do shift; done\ncat "$1"\n' > "$SCRATCH/wbin/awk"; chmod +x "$SCRATCH/wbin/awk"
run_writer workspaces_boot_unlock_fstab_writer; _rc=$?
ok "$([ "$_rc" -eq 44 ]; echo $?)" "W-fstab post-edit count != 1 refuses exit 44 even when the comment step misfires (rc=$_rc)"
rm -f "$SCRATCH/wbin/awk"   # restore real awk for the rest of the arm

# --- gate writer ----------------------------------------------------------------------
new_wfixture gate-ok
run_writer workspaces_boot_unlock_gate_writer; _rc=$?
ok "$([ "$_rc" -eq 0 ]; echo $?)" "W-gate happy path exits 0 (rc=$_rc)" "$(tail -3 "$WFX/err")"
_d="$WFX/systemd/docker.service.d/10-workspaces-luks-mount.conf"
ok "$(grep -qxF 'RequiresMountsFor=/mnt/data' "$_d" && grep -qxF 'After=workspaces-luks-reopen.service' "$_d"; echo $?)" "W-gate the drop-in carries RequiresMountsFor=/mnt/data AND After=workspaces-luks-reopen.service"
_b=$(grep -n 'mount|--bind' "$WFX/calls.log" | cut -d: -f1 | head -1)
_c=$(grep -n 'chattr|' "$WFX/calls.log" | cut -d: -f1 | head -1)
_l=$(grep -n 'lsattr|' "$WFX/calls.log" | cut -d: -f1 | head -1)
_u=$(grep -n 'umount|' "$WFX/calls.log" | cut -d: -f1 | head -1)
ok "$([ -n "$_b" ] && [ -n "$_c" ] && [ -n "$_l" ] && [ -n "$_u" ] && [ "$_b" -lt "$_c" ] && [ "$_c" -lt "$_l" ] && [ "$_l" -lt "$_u" ]; echo $?)" \
  "W-gate peek order: bind($_b) < chattr($_c) < lsattr($_l) < umount($_u)" "$(cat "$WFX/calls.log")"
ok "$(grep -qE "^chattr\|\+i .*/peek/mnt/data$" "$WFX/calls.log"; echo $?)" "W-gate chattr +i hit the PEEKED covered inode (*/peek/mnt/data)"
n=$(grep -cE 'chattr\|\+i /mnt/data( |$)' "$WFX/calls.log" || true)
ok "$([ "$n" -eq 0 ]; echo $?)" "W-gate chattr NEVER touched the mounted /mnt/data path ($n)"
new_wfixture gate-noi; touch "$WFX/no_i"
run_writer workspaces_boot_unlock_gate_writer; _rc=$?
ok "$([ "$_rc" -eq 53 ]; echo $?)" "W-gate lsattr without the i flag refuses exit 53 (rc=$_rc)"
new_wfixture gate-chattrfail; echo 1 > "$WFX/chattr_rc"
run_writer workspaces_boot_unlock_gate_writer; _rc=$?
ok "$([ "$_rc" -eq 52 ]; echo $?)" "W-gate a failing chattr refuses exit 52 (rc=$_rc)"
# THE review defect: `mount --bind ... && _m=1` was errexit-immune — a failed bind
# fell through and chattr'ed the bare scratch dir while printing success. The fix
# is `|| { exit 54; }`. Pin both sides: rc 54 AND chattr never ran.
new_wfixture gate-bindfail; echo 1 > "$WFX/mount_rc"
run_writer workspaces_boot_unlock_gate_writer; _rc=$?
ok "$([ "$_rc" -eq 54 ]; echo $?)" "W-gate a failed bind peek refuses exit 54 before anything mutates through it (rc=$_rc)" "$(tail -3 "$WFX/err")"
ok "$([ "$(grep -c 'chattr|' "$WFX/calls.log")" -eq 0 ]; echo $?)" "W-gate the failed bind NEVER reached chattr (the defect shape: chattr on the unverified scratch dir)" "$(cat "$WFX/calls.log")"
new_wfixture gate-symlink; mkdir -p "$WFX/peek/mnt"; ln -s "$WFX/victim" "$WFX/peek/mnt/data"
run_writer workspaces_boot_unlock_gate_writer; _rc=$?
ok "$([ "$_rc" -eq 55 ]; echo $?)" "W-gate a symlink peek target refuses exit 55 — chattr must never follow a link (rc=$_rc)"
ok "$([ "$(grep -c 'chattr|' "$WFX/calls.log")" -eq 0 ]; echo $?)" "W-gate the symlink refusal never reached chattr"
new_wfixture gate-stdev; echo 43 > "$WFX/dev_peek"
run_writer workspaces_boot_unlock_gate_writer; _rc=$?
ok "$([ "$_rc" -eq 56 ]; echo $?)" "W-gate a peek whose st_dev is not the root fs refuses exit 56 (rc=$_rc)"
ok "$([ "$(grep -c 'chattr|' "$WFX/calls.log")" -eq 0 ]; echo $?)" "W-gate the st_dev refusal never reached chattr"

# --- arm writer ----------------------------------------------------------------------
new_wfixture arm-ok
run_writer workspaces_boot_unlock_arm; _rc=$?
ok "$([ "$_rc" -eq 0 ]; echo $?)" "W-arm happy path exits 0 (rc=$_rc)" "$(tail -3 "$WFX/err")"
ok "$(grep -q '^systemctl|daemon-reload' "$WFX/calls.log" && grep -q 'systemctl|enable workspaces-luks-reopen.service' "$WFX/calls.log" && grep -q 'systemctl|enable --now workspaces-luks-reopen.timer' "$WFX/calls.log" && grep -q 'systemctl|start workspaces-luks-reopen.service' "$WFX/calls.log"; echo $?)" \
  "W-arm daemon-reload, service enable, timer --now enable, proof start — all recorded"
_a=$(grep -n 'systemctl|daemon-reload' "$WFX/calls.log" | cut -d: -f1 | head -1)
_s=$(grep -n 'systemctl|start workspaces-luks-reopen.service' "$WFX/calls.log" | cut -d: -f1 | head -1)
ok "$([ -n "$_a" ] && [ -n "$_s" ] && [ "$_a" -lt "$_s" ]; echo $?)" "W-arm daemon-reload precedes the proof start ($_a < $_s)"
new_wfixture arm-badproof; echo dead > "$WFX/reopen_substate"
run_writer workspaces_boot_unlock_arm; _rc=$?
ok "$([ "$_rc" -eq 60 ]; echo $?)" "W-arm a proof run not converging to exited refuses exit 60 (rc=$_rc)"
new_wfixture arm-badresult; echo failure > "$WFX/reopen_result"
run_writer workspaces_boot_unlock_arm; _rc=$?
ok "$([ "$_rc" -eq 61 ]; echo $?)" "W-arm Result != success refuses exit 61 (rc=$_rc)"
new_wfixture arm-badstatus; echo 7 > "$WFX/reopen_execstatus"
run_writer workspaces_boot_unlock_arm; _rc=$?
ok "$([ "$_rc" -eq 62 ]; echo $?)" "W-arm ExecMainStatus != 0 refuses exit 62 (rc=$_rc)"
new_wfixture arm-sysctlfail; echo 1 > "$WFX/systemctl_rc"
run_writer workspaces_boot_unlock_arm; _rc=$?
ok "$([ "$_rc" -ne 0 ]; echo $?)" "W-arm a failing systemctl (daemon-reload) exits non-zero under set -e (rc=$_rc)"
new_wfixture arm-prooftimeout; echo 1 > "$WFX/systemctl_rc_start"
run_writer workspaces_boot_unlock_arm; _rc=$?
ok "$([ "$_rc" -eq 63 ]; echo $?)" "W-arm a proof start that fails inside the 420 s timeout exits 63 — the client window non-convergence arm (rc=$_rc)" "$(tail -3 "$WFX/err")"
ok "$(grep -q 'systemctl|show -p SubState,Result,ExecMainStatus workspaces-luks-reopen.service' "$WFX/calls.log"; echo $?)" "W-arm the exit-63 arm dumps the unit's state before refusing"

# --- the print locals run clean under a populated fixture --------------------------------
new_wfixture print-ok; printf '%s' "$FSTAB_GLOB" > "$WFX/fstab"; printf 'workspaces %s none luks,noauto\n' "$PIN_DEV" > "$WFX/crypttab"
: > "$WFX/envfile"; mkdir -p "$WFX/systemd/docker.service.d"; : > "$WFX/systemd/docker.service.d/10-workspaces-luks-mount.conf"
run_writer workspaces_boot_unlock_print; _rc=$?
ok "$([ "$_rc" -eq 0 ]; echo $?)" "W-print[before] exits 0 and never taints the step (rc=$_rc)" "$(tail -3 "$WFX/err")"
ok "$(grep -q 'boot-unlock before' "$WFX/out" && grep -q 'crypttab-workspaces-lines=1' "$WFX/out" && grep -q 'has_nofail=no' "$WFX/out"; echo $?)" "W-print[before] emits the labelled fields incl. the redacted fstab select" "$(tail -5 "$WFX/out")"
ok "$([ "$(grep -c 'FORBIDDEN CALL' "$WFX/err")" -eq 0 ] && [ "$(grep -cE '^(cryptsetup|doppler|journalctl|docker|curl)\|' "$WFX/calls.log")" -eq 0 ]; echo $?)" "W-print[before] invoked no forbidden tool"
new_wfixture print-after; printf '/dev/mapper/workspaces /mnt/data ext4 defaults,nofail 0 2\n' > "$WFX/fstab"; printf 'workspaces %s none luks,noauto\n' "$PIN_DEV" > "$WFX/crypttab"
printf 'WORKSPACES_LUKS_DEV=x\n' > "$WFX/envfile"; mkdir -p "$WFX/systemd/docker.service.d"; printf '[Unit]\nRequiresMountsFor=/mnt/data\nAfter=workspaces-luks-reopen.service\n' > "$WFX/systemd/docker.service.d/10-workspaces-luks-mount.conf"
run_writer workspaces_boot_unlock_post_state; _rc=$?
ok "$([ "$_rc" -eq 0 ]; echo $?)" "W-print[after] exits 0 (rc=$_rc)" "$(tail -3 "$WFX/err")"
ok "$(grep -q 'fstab-mnt-data-lines=1' "$WFX/out" && grep -q 'crypttab-workspaces-lines=1' "$WFX/out" && grep -q 'covered-mnt-data-attrs=' "$WFX/out"; echo $?)" \
  "W-print[after] prints fstab=1, crypttab=1 and the second-peek lsattr row" "$(tail -5 "$WFX/out")"
ok "$(grep -q 'peek-residue=none' "$WFX/out"; echo $?)" "W-print[after] reports peek-residue=none when no leftover bind exists" "$(tail -5 "$WFX/out")"
ok "$([ "$(grep -cE '^(cryptsetup|doppler|journalctl|docker|curl)\|' "$WFX/calls.log")" -eq 0 ]; echo $?)" "W-print[after] invoked no forbidden tool"
new_wfixture print-residue; printf '/dev/mapper/workspaces /mnt/data ext4 defaults,nofail 0 2\n' > "$WFX/fstab"; printf 'workspaces %s none luks,noauto\n' "$PIN_DEV" > "$WFX/crypttab"
printf 'WORKSPACES_LUKS_DEV=x\n' > "$WFX/envfile"; mkdir -p "$WFX/systemd/docker.service.d"; printf '[Unit]\nRequiresMountsFor=/mnt/data\nAfter=workspaces-luks-reopen.service\n' > "$WFX/systemd/docker.service.d/10-workspaces-luks-mount.conf"
printf '%s\n' "$WFX/peek" > "$WFX/peek_residue"
run_writer workspaces_boot_unlock_post_state; _rc=$?
ok "$([ "$_rc" -eq 0 ]; echo $?)" "W-print[residue] exits 0 — residue is reported, the print never fails the apply (rc=$_rc)"
ok "$(grep -q 'peek-residue=PRESENT' "$WFX/out"; echo $?)" "W-print[residue] a leftover peek bind is reported as peek-residue=PRESENT (rc=$_rc)" "$(tail -5 "$WFX/out")"

# ==================================================================================
# RUNTIME — the reopen script under a stub PATH
# ==================================================================================
mkdir -p "$SCRATCH/bin"
STUB_PRELUDE='#!/bin/bash
case "${FX-}" in /*) : ;; *) printf "FATAL(stub): FX is not absolute\n" >&2; exit 2 ;; esac
_tag=$(head -n1 "$RUNDIR/action" 2>/dev/null | sed "s/^action=//")
printf "%s|%s|%s\n" "${_tag:-none}" "$(basename "$0")" "$*" >> "${FX:?}/calls.log"
'
mkstub() {
  if [ "$1" = "${WBU_DISABLE_STUB:-__none__}" ]; then return; fi
  { printf '%s' "$STUB_PRELUDE"; cat; } > "$SCRATCH/bin/$1"; chmod +x "$SCRATCH/bin/$1"
}

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
    rc=$(cat "$FX/status_rc" 2>/dev/null || echo 0)
    [ "$rc" -ne 0 ] && { echo "cryptsetup status $2 failed (rc=$rc)" >&2; exit "$rc"; }
    if [ -f "$FX/mapper_open" ]; then printf '/dev/mapper/%s is active.\n  type:    LUKS2\n  device:  %s\n' "$2" "$(cat "$FX/status_device" 2>/dev/null || echo "$STUB_DEV")"; exit 0
    else echo "Device $2 is not active." >&2; exit 4; fi ;;
  luksFormat) echo "FORMAT MUST NEVER RUN" >&2; exit 99 ;;
  *) echo "unexpected cryptsetup $*" >&2; exit 98 ;;
esac
EOF
mkstub findmnt <<'EOF'
if [ "$1" = "--fstab" ]; then
  [ -s "$FX/fstab_targets" ] || exit 1
  cat "$FX/fstab_targets"; exit 0
fi
# findmnt -n -o SOURCE <target>
[ -f "$FX/mounted" ] || exit 1
cat "$FX/mount_source" 2>/dev/null || echo /dev/mapper/workspaces
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
    p=""; prev=""; for a in "$@"; do case "$prev" in -p) p=$a;; esac; prev=$a; done
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
mkstub doppler <<'EOF'
# records `doppler <argv>`; mode from $FX/doppler_mode (ok|fail|empty|hang)
mode=$(cat "$FX/doppler_mode" 2>/dev/null || echo ok)
case "$mode" in
  fail) echo "Unable to read secret" >&2; exit 1 ;;
  empty) exit 0 ;;
  hang) exec /bin/sleep 200 ;;
esac
if [ "$1" = "secrets" ] && [ "$2" = "get" ]; then cat "$FX/doppler_key" 2>/dev/null || echo "stub-wluks-key-0000"; exit 0; fi
if [ "$1" = "secrets" ] && [ "$2" = "--only-names" ]; then printf 'WORKSPACES_LUKS_KEY\n'; exit 0; fi
echo "unexpected doppler $*" >&2; exit 98
EOF
mkstub logger <<'EOF'
exit 0
EOF
mkstub sleep <<'EOF'
exit 0
EOF
mkstub workspaces_luks_emit <<'EOF'
# The script must NEVER reach this (AC9 — emit is the reporter's). A call lands in
# emit.log AND calls.log so both reads see it, and exits nonzero: in the reporter arm a
# MISSING emit helper must still reach the `|| logger` SEND_FAILED arm — a success here
# would mask it.
printf 'EMIT %s\n' "$*" >> "$FX/emit.log"
exit 99
EOF
# FORMAT TRAPS — a script that calls one is the real tool's worst case; record + exit 99.
for _trap in mkfs mkfs.ext4 mkfs.xfs wipefs blkdiscard shred dd mount umount swapon cryptomount; do
  mkstub "$_trap" <<'EOF'
echo "FORMAT TRAP: $0 $*" >&2; exit 99
EOF
done

# Instrument gate (plan Guard 1 row 7): every stubbable external the script names must
# resolve to OUR stub — a fall-through would execute the host's real binary (cryptsetup
# exists at /usr/bin/cryptsetup on runners). A miss is a broken instrument -> exit 2,
# never a counted catch.
STUB_NAMES="blockdev cryptsetup findmnt mountpoint realpath systemctl journalctl doppler logger sleep workspaces_luks_emit mkfs mkfs.ext4 mkfs.xfs wipefs blkdiscard shred dd mount umount swapon cryptomount"
for c in $STUB_NAMES; do
  r=$(PATH="$SCRATCH/bin:/usr/bin:/bin" command -v "$c" 2>/dev/null || true)
  [ "$r" = "$SCRATCH/bin/$c" ] || { printf '[FATAL] instrument: %s resolves to %s, not the stub — refusing to run (rc 2)\n' "$c" "${r:-nothing}" >&2; exit 2; }
done
ok "$(PATH="$SCRATCH/bin:/usr/bin:/bin" command -v systemd-escape | grep -qx '/usr/bin/systemd-escape'; echo $?)" \
  "H1 systemd-escape resolves to the REAL binary (deliberately unstubbed — a stub would test itself)"

# Fixture runner. run_script copies the script-under-test into the fixture dir so the
# emit-helper sibling ($FX/workspaces-luks-emit.sh) is under the fixture's control —
# a copy, never the tracked file's directory.
FX=""; RUNDIR=""
new_fixture() {
  assert_fixture_dir "$SCRATCH"
  FX="$SCRATCH/fx-$1"; RUNDIR="$FX/run"
  assert_fixture_dir "$FX"; assert_fixture_dir "$RUNDIR"
  rm -rf "$FX"; mkdir -p "$FX" "$RUNDIR" "$FX/dev"
  : > "$FX/calls.log" "$FX/emit.log"
  printf '/mnt/data\n' > "$FX/fstab_targets"
  cp "$WBU_SCRIPT" "$FX/script.sh"
  cp "$WBU_EMIT_SH" "$FX/workspaces-luks-emit.sh"
  export FX RUNDIR
}
run_script() {
  ( env -i PATH="$SCRATCH/bin:/usr/bin:/bin" HOME=/root FX="$FX" RUNDIR="$RUNDIR" \
    STUB_DEV="${DEV_OVERRIDE:-$PIN_DEV}" \
    WORKSPACES_LUKS_DEV="${DEV_OVERRIDE:-$PIN_DEV}" \
    WORKSPACES_DOPPLER_CONFIG="${CFG_OVERRIDE:-prd_workspaces_luks}" \
    WORKSPACES_REOPEN_RUNDIR="$RUNDIR" WORKSPACES_REOPEN_DEVICE_WAIT=1 \
    bash "$FX/script.sh" > "$FX/stdout" 2> "$FX/stderr"; _r=$?; exit "$_r" ) 2>/dev/null
}
action_file() { head -n1 "$RUNDIR/action" 2>/dev/null | sed 's/^action=//'; }
calls_of() { grep -F -- "$1" "$FX/calls.log" || true; }
order_ok() {
  # Totality: an EMPTY or missing calls.log is "no instrumented call ever ran" —
  # that is a failed instrument, not a vacuously-ordered one. Answer 0 (bad).
  [ -s "$FX/calls.log" ] || { echo 0; return; }
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
key_absent() {
  # Totality: the predicate may only pass over a fixture that actually ran the
  # instrumented surface — an empty calls.log means nothing was recorded, and
  # "the key appears nowhere" must not be read off a run that never happened.
  [ -d "$FX" ] && [ -d "$RUNDIR" ] && [ -s "$FX/calls.log" ] || { echo 1; return; }
  ! grep -arqF --exclude=key_seen -- "stub-wluks-key-0000" "$FX" "$RUNDIR" 2>/dev/null; echo $?
}

# --- Scenario 1: closed mapper, target unmounted -> reopened ----------------------------------
new_fixture s1
run_script; rc=$?
ok "$([ "$rc" -eq 0 ]; echo $?)" "R1 closed+unmounted exits 0 (rc=$rc)" "$(cat "$FX/stderr")"
ok "$([ "$(calls_of "|cryptsetup|luksOpen" | grep -c "luksOpen --key-file - $PIN_DEV workspaces")" -eq 1 ]; echo $?)" "R1 luksOpen called once with --key-file - and the pinned device"
ok "$([ "$(cat "$FX/key_seen")" = "stub-wluks-key-0000" ]; echo $?)" "R1 the passphrase reached luksOpen on stdin, not argv"
ok "$(key_absent)" "R1n the passphrase appears in NO fixture artifact other than key_seen" "$(grep -arlF --exclude=key_seen -- 'stub-wluks-key-0000' "$FX" "$RUNDIR" 2>/dev/null)"
ok "$(calls_of "|systemctl|" | grep -cx 'mount|systemctl|start mnt-data.mount' >/dev/null; echo $?)" "R1 PID-1 mount started via the escaped fstab unit (mnt-data.mount)"
ok "$(grep -q 'emit|logger|-t workspaces-luks-reopen --' "$FX/calls.log" && grep -q 'action=reopened' "$FX/calls.log"; echo $?)" "R1 the success row is the logger journald line (action=reopened)"
ok "$([ ! -s "$FX/emit.log" ]; echo $?)" "R1 AC9: workspaces_luks_emit NEVER called on a successful reopen"
ok "$([ ! -e "$RUNDIR/action" ] && [ ! -e "$RUNDIR/log" ]; echo $?)" "R1 phase/log files removed on success"
ok "$([ "$(order_ok)" = 1 ]; echo $?)" "R1 ORDER: every stub call is tagged with a declared phase in declared order" "$(cat "$FX/calls.log")"
ok "$([ "$(grep -c '|luksFormat' "$FX/calls.log")" -eq 0 ]; echo $?)" "R1 luksFormat never called"
ok "$(grep -q '^header|cryptsetup|isLuks' "$FX/calls.log"; echo $?)" "R1 isLuks runs under tag header"
ok "$(grep -q '^open|cryptsetup|luksOpen' "$FX/calls.log"; echo $?)" "R1 luksOpen runs under tag open"
ok "$(grep -q '^mount|systemctl|start' "$FX/calls.log"; echo $?)" "R1 systemctl start runs under tag mount"
ok "$(grep -q '^identity-mount|findmnt|-n -o SOURCE' "$FX/calls.log"; echo $?)" "R1 findmnt SOURCE runs under tag identity-mount"
ok "$(grep -q "^key|doppler|secrets get WORKSPACES_LUKS_KEY --plain --config prd_workspaces_luks" "$FX/calls.log"; echo $?)" "R1 the key fetch ran under tag key in the R9 form"
ok "$([ "$(grep -cE '\|doppler\|(run|secrets download)' "$FX/calls.log")" -eq 0 ]; echo $?)" "R1 no doppler run/download call was ever made"

# --- Scenario 1e: emit helper absent on a real reopen -> exit 3 (structural refusal) ----------
new_fixture s1e; chmod 000 "$FX/workspaces-luks-emit.sh"
run_script; rc=$?
ok "$([ "$rc" -eq 3 ]; echo $?)" "R1e an unreadable emit helper exits 3 — terminal, never retried into the silent noop arm (rc=$rc)"
ok "$([ "$(action_file)" = emit ]; echo $?)" "R1e the phase file names emit (got '$(action_file)')"

# --- Scenario 2: open + mounted -> noop, fully silent -------------------------------------------
new_fixture s2; touch "$FX/mapper_open" "$FX/mounted"
run_script; rc=$?
ok "$([ "$rc" -eq 0 ]; echo $?)" "R2 noop exits 0 (rc=$rc)" "$(cat "$FX/stderr")"
ok "$([ "$(calls_of "|cryptsetup|luksOpen" | wc -l)" -eq 0 ]; echo $?)" "R2 no luksOpen"
ok "$([ "$(calls_of "|systemctl|" | grep -c 'systemctl|start ')" -eq 0 ]; echo $?)" "R2 no systemctl start"
ok "$([ ! -s "$FX/emit.log" ]; echo $?)" "R2 AC9: no emit on the noop path"
ok "$([ "$(calls_of "|logger|" | wc -l)" -eq 0 ]; echo $?)" "R2 noop is FULLY silent — not even the logger success row"
ok "$([ ! -e "$RUNDIR/action" ]; echo $?)" "R2 phase file removed"
ok "$(grep -q '^identity|realpath|' "$FX/calls.log"; echo $?)" "R2 device identity asserted on the noop path too"

# --- Scenario 2e: noop + unreadable emit helper -> exit 3 (the channel check is
# unconditional now — the noop proof run certifies the reporter's emit channel) ----
new_fixture s2e; touch "$FX/mapper_open" "$FX/mounted"; chmod 000 "$FX/workspaces-luks-emit.sh"
run_script; rc=$?
ok "$([ "$rc" -eq 3 ]; echo $?)" "R2e noop + unreadable emit helper exits 3 — the emit-channel assert runs on EVERY arm, noop included (rc=$rc)"
ok "$([ "$(action_file)" = emit ]; echo $?)" "R2e the phase file names emit (got '$(action_file)')"

# --- Scenario 3: open, unmounted -> mounted ------------------------------------------------------
new_fixture s3; touch "$FX/mapper_open"
run_script; rc=$?
ok "$([ "$rc" -eq 0 ]; echo $?)" "R3 open+unmounted exits 0 (rc=$rc)" "$(cat "$FX/stderr")"
ok "$(grep -q 'action=mounted' "$FX/calls.log"; echo $?)" "R3 action=mounted"
ok "$([ "$(calls_of "|cryptsetup|luksOpen" | wc -l)" -eq 0 ]; echo $?)" "R3 no luksOpen"
ok "$([ ! -s "$FX/emit.log" ]; echo $?)" "R3 AC9: no emit on the mounted-success path either"

# ==================================================================================
# RUNTIME — the reporter body (extracted from the unit, paths rewritten, run under sh)
# ==================================================================================
# Emit-helper stub the reporter's `. file; workspaces_luks_emit` sources: records the WL_*
# envelope to emit.log, honours $FX/emit_rc (nonzero -> the SEND_FAILED fallback) and
# $FX/emit_mode=hang (bounded by the body's timeout).
write_emit_stub() {
  cat > "$SCRATCH/bin/workspaces-luks-emit.sh" <<'EOF'
workspaces_luks_emit() {
  printf 'EMIT level=%s reason=%s mapper=%s cs=%s mok=%s ms=%s dr=%s open=%s\n' \
    "${WL_LEVEL:-}" "${WL_REASON:-}" "${WL_MAPPER_PRESENT:-}" "${WL_CRYPTSETUP_UNIT_RESULT:-}" \
    "${WL_MOUNTPOINT_OK:-}" "${WL_MOUNT_SOURCE:-}" "${WL_DOPPLER_REACHABLE:-}" "${WL_LUKS_OPEN_RESULT:-}" >> "${FX:?}/emit.log"
  if [ "$(cat "${FX:?}/emit_mode" 2>/dev/null)" = hang ]; then exec /bin/sleep 200; fi
  _rc=0; [ -r "${FX:?}/emit_rc" ] && _rc=$(cat "${FX:?}/emit_rc")
  return "$_rc"
}
EOF
}
write_emit_stub

# The body is a `/bin/sh -c '…'` payload with `\`-continued lines. The WL_* env-prefix
# assignments are prefixes of the `timeout 90` command — the continuations MUST be joined,
# not merely stripped, or the emit runs with no envelope.
BODY=$(awk '/^ExecStart=\/bin\/sh -c '"'"'/{f=1; sub(/^ExecStart=\/bin\/sh -c '"'"'/,"")} f{print} f&&/'"'"'$/{exit}' "$REP_BODY" | sed "s/'$//" | awk '{ line = $0; cont = (line ~ /\\$/); if (cont) sub(/\\$/, "", line); acc = acc line " "; if (!cont) { sub(/ $/, "", acc); print acc; acc = "" } }')
n_abs=$(printf '%s\n' "$BODY" | grep -o '/usr/local/bin/' | wc -l); n_run=$(printf '%s\n' "$BODY" | grep -o '/run/workspaces-luks-reopen' | wc -l)
n_dev=$(printf '%s\n' "$BODY" | grep -o '/dev/mapper/workspaces' | wc -l); n_to=$(printf '%s\n' "$BODY" | grep -c 'timeout 90 ' || true)
ok "$([ -n "$BODY" ] && [ "$n_abs" -ge 2 ] && [ "$n_run" -ge 2 ] && [ "$n_dev" -ge 1 ] && [ "$n_to" -eq 1 ]; echo $?)" \
  "REP body extracted (usr-local=$n_abs run-dir=$n_run devmap=$n_dev timeout90=$n_to)"
rep_body() {
  BODY2=$(printf '%s\n' "$BODY" | sed "s#/usr/local/bin/#$SCRATCH/bin/#g; s#/run/workspaces-luks-reopen#$RUNDIR#g; s#/dev/mapper/workspaces#$FX/devmap#g; s#timeout 90 #timeout 3 #g; s#timeout 15 #timeout 2 #g")
  n_left=$(printf '%s\n' "$BODY2" | grep -c '/usr/local/bin/\|/run/workspaces-luks-reopen\|timeout 90 \|/dev/mapper/workspaces' || true)
  ok "$([ "$n_left" -eq 0 ]; echo $?)" "REP body rewritten for $(basename "$FX") (left=$n_left)"
}
rep_run() { env -i PATH="$SCRATCH/bin:/usr/bin:/bin" FX="$FX" RUNDIR="$RUNDIR" WORKSPACES_DOPPLER_CONFIG=prd_workspaces_luks sh -c "$BODY2" > "$FX/rep.out" 2>&1; }

# --- Failure fixtures: one per declared phase, action file names THAT phase -------------------
FAILS=$(cat <<'EOF'
config-dev|export DEV_OVERRIDE=/dev/sdb|config|WORKSPACES_LUKS_DEV
config-cfg|export CFG_OVERRIDE='Prd;x'|config|WORKSPACES_DOPPLER_CONFIG
key-fail|echo fail > "$FX/doppler_mode"|key|WORKSPACES_LUKS_KEY is empty
key-empty|echo empty > "$FX/doppler_mode"|key|WORKSPACES_LUKS_KEY is empty
device|touch "$FX/device_absent"|device|absent
header|echo 1 > "$FX/isluks_rc"|header|rc=1
open|echo 2 > "$FX/luksopen_rc"|open|passphrase
open-status|echo 1 > "$FX/status_rc"|open|rc=1
open-sigterm|touch "$FX/luksopen_kill"|open|
identity|touch "$FX/mapper_open"; echo /dev/sdz > "$FX/status_device"|identity|/dev/sdz
target-none|: > "$FX/fstab_targets"|target|expected exactly one
target-two|printf '/mnt/a\n/mnt/data\n' > "$FX/fstab_targets"|target|expected exactly one
target-rogue|printf '/mnt/rogue\n' > "$FX/fstab_targets"|target|not /mnt/data
mount|touch "$FX/mapper_open"; echo 1 > "$FX/mount_start_rc"; printf 'wrong fs type, bad option, bad superblock\n' > "$FX/journal"|mount|bad superblock
identity-mount|touch "$FX/mounted" "$FX/mapper_open"; echo /dev/sdb1 > "$FX/mount_source"|identity-mount|/dev/sdb1
emit|chmod 000 "$FX/workspaces-luks-emit.sh"|emit|absent or unreadable
EOF
)
COVERED_PHASES=""
while IFS='|' read -r name setup phase needle; do
  [ -n "$name" ] || continue
  new_fixture "f-$name"
  unset DEV_OVERRIDE CFG_OVERRIDE
  eval "$setup"
  run_script; rc=$?
  unset DEV_OVERRIDE CFG_OVERRIDE
  ok "$([ "$rc" -ne 0 ]; echo $?)" "F[$name] exits non-zero (rc=$rc)" "$(tail -3 "$FX/stderr")"
  ok "$([ "$(action_file)" = "$phase" ]; echo $?)" "F[$name] action file names phase '$phase'" "got '$(action_file)'; calls: $(tr '\n' ';' < "$FX/calls.log")"
  ok "$([ "$(grep -cE '\|(luksFormat|luksErase|mkfs|wipefs|blkdiscard)' "$FX/calls.log")" -eq 0 ]; echo $?)" "F[$name] luksFormat/mkfs/wipefs never called"
  ok "$([ "$(grep -cE '\|doppler\|(run|secrets download)' "$FX/calls.log")" -eq 0 ]; echo $?)" "F[$name] no doppler run/download on the failure path"
  if [ -s "$FX/calls.log" ]; then
    ok "$(key_absent)" "F[$name] the passphrase is in no artifact the reporter could ship" "$(grep -arlF --exclude=key_seen -- 'stub-wluks-key-0000' "$FX" "$RUNDIR" 2>/dev/null)"
  else
    # Died before ANY instrumented call (the config-phase fixtures): the passphrase
    # was never fetched, so the honest assertion is that key_seen cannot exist.
    ok "$([ ! -e "$FX/key_seen" ]; echo $?)" "F[$name] died before any instrumented call — the passphrase was never fetched (no key_seen)"
  fi
  if [ "$phase" = emit ]; then
    ok "$([ "$rc" -eq 3 ]; echo $?)" "F[$name] the emit refusal is exit 3 (RestartPreventExitStatus pairing)"
  else
    ok "$([ ! -s "$FX/emit.log" ]; echo $?)" "F[$name] the script emits nothing on failure (the reporter does)"
  fi
  if [ -n "$needle" ]; then
    ok "$(grep -qF -- "$needle" "$RUNDIR/log" 2>/dev/null || grep -qF -- "$needle" "$FX/stderr"; echo $?)" "F[$name] log/stderr carries '$needle'" "log: $(cat "$RUNDIR/log" 2>/dev/null)"
  fi
  if [ "$name" = open-status ]; then
    # The open arm is exactly `-eq 4` — a non-4 status rc must die BEFORE any
    # luksOpen attempt (`-ne 0` would retry-open on a real error).
    ok "$([ "$(calls_of "|cryptsetup|luksOpen" | wc -l)" -eq 0 ]; echo $?)" "F[$name] a non-4 status rc dies BEFORE any luksOpen attempt"
  fi
  lt=$(last_tag); [ -z "$lt" ] && lt="$phase"
  li=$(printf '%s\n' "$PHASES" | grep -nx -- "$lt" | cut -d: -f1); pi=$(printf '%s\n' "$PHASES" | grep -nx -- "$phase" | cut -d: -f1)
  ok "$([ -n "$li" ] && [ "$li" -le "$pi" ]; echo $?)" "F[$name] no call tagged later than '$phase' (last tag '$lt')"
  COVERED_PHASES="$COVERED_PHASES $phase"

  # Composition: feed the reporter the files this fixture left. It must emit ONE fatal
  # naming the phase, with the discriminating WL_* tags.
  : > "$FX/emit.log"; rm -f "$FX/emit_rc" "$FX/emit_mode"; echo ok > "$FX/doppler_mode"
  touch "$FX/devmap"; echo exit-code > "$FX/result"; echo 1 > "$FX/exec_status"; echo 1 > "$FX/exec_code"; echo 2 > "$FX/nrestarts"
  rep_body; rep_run
  ok "$([ "$(grep -c '^EMIT ' "$FX/emit.log")" -eq 1 ]; echo $?)" "F[$name] reporter emitted exactly ONE fatal" "$(cat "$FX/emit.log" "$FX/rep.out" 2>/dev/null)"
  ok "$(grep -q "reason=boot_unlock_failed:$phase" "$FX/emit.log"; echo $?)" "F[$name] reporter carries reason=boot_unlock_failed:$phase"
  for t in "level=fatal" "result=exit-code,rc=1,code=1,restarts=2" "mapper=true" "dr=true"; do
    ok "$(grep -qF "$t" "$FX/emit.log"; echo $?)" "F[$name] reporter tag $t"
  done
  ok "$(grep -q 'workspaces-luks-reopen FAILED' "$FX/rep.out"; echo $?)" "F[$name] reporter printed the classification echo to stderr"
done <<< "$FAILS"
for p in $PHASES; do
  ok "$(printf '%s\n' $COVERED_PHASES | grep -cx -- "$p" >/dev/null; echo $?)" "COVERAGE: phase '$p' has a failure fixture"
done

# --- Reporter with NO files (unit-level failure: exec/start-timeout/ladder) --------------------
new_fixture r-unit; rep_body
echo start-limit-hit > "$FX/result"; echo 1 > "$FX/exec_status"; echo 1 > "$FX/exec_code"; echo 5 > "$FX/nrestarts"
rm -f "$FX/devmap"; echo fail > "$FX/doppler_mode"; rep_run
ok "$([ "$(grep -c '^EMIT ' "$FX/emit.log")" -eq 1 ]; echo $?)" "REP-unit exactly one emit with no phase file"
ok "$(grep -q 'reason=boot_unlock_failed:unit' "$FX/emit.log"; echo $?)" "REP-unit reason=boot_unlock_failed:unit"
ok "$(grep -q 'result=start-limit-hit' "$FX/emit.log"; echo $?)" "REP-unit result=start-limit-hit survives the ladder"
ok "$(grep -q 'dr=false' "$FX/emit.log"; echo $?)" "REP-unit doppler_reachable=false when the probe fails"

# --- Emit leg failure -> the SEND_FAILED mirror fires -------------------------------------------
new_fixture r-emitfail; rep_body
printf 'action=open\n' > "$RUNDIR/action"; echo exit-code > "$FX/result"; echo 1 > "$FX/exec_status"; echo 1 > "$FX/exec_code"; echo 0 > "$FX/nrestarts"
echo 1 > "$FX/emit_rc"; rep_run
ok "$([ "$(grep -c '^EMIT ' "$FX/emit.log")" -eq 1 ]; echo $?)" "REP-emitfail the emit was attempted"
ok "$(grep -q 'SOLEUR_WORKSPACES_LUKS_SEND_FAILED' "$FX/calls.log"; echo $?)" "REP-emitfail a failed emit leg mirrors to SOLEUR_WORKSPACES_LUKS_SEND_FAILED via logger"
new_fixture r-emitabsent; rep_body
printf 'action=mount\n' > "$RUNDIR/action"; rm -f "$SCRATCH/bin/workspaces-luks-emit.sh"; rep_run
ok "$(grep -q 'SOLEUR_WORKSPACES_LUKS_SEND_FAILED' "$FX/calls.log"; echo $?)" "REP-emitabsent a missing emit helper still mirrors SEND_FAILED" "$(cat "$FX/rep.out")"
write_emit_stub   # restore the emit stub for any later consumer

# --- A HUNG emit leg: the `timeout 90` bound (rewritten to 3 s here) must reach
# the SEND_FAILED mirror instead of eating the unit's TimeoutStartSec -----------
new_fixture r-emithang; rep_body
printf 'action=open\n' > "$RUNDIR/action"; echo exit-code > "$FX/result"; echo 1 > "$FX/exec_status"; echo 1 > "$FX/exec_code"; echo 0 > "$FX/nrestarts"
echo hang > "$FX/emit_mode"; rep_run
ok "$([ "$(grep -c '^EMIT ' "$FX/emit.log")" -eq 1 ]; echo $?)" "REP-emithang the emit was entered (one EMIT row) before hanging"
ok "$(grep -q 'SOLEUR_WORKSPACES_LUKS_SEND_FAILED' "$FX/calls.log"; echo $?)" "REP-emithang a HUNG emit leg is bounded and mirrors SEND_FAILED" "$(cat "$FX/rep.out")"
rm -f "$FX/emit_mode"

# --- A HUNG doppler reachability probe: bounded to dr=false ---------------------
new_fixture r-dophang; rep_body
printf 'action=config\n' > "$RUNDIR/action"; echo exit-code > "$FX/result"; echo 1 > "$FX/exec_status"; echo 1 > "$FX/exec_code"; echo 0 > "$FX/nrestarts"
touch "$FX/devmap"; echo hang > "$FX/doppler_mode"; rep_run
ok "$([ "$(grep -c '^EMIT ' "$FX/emit.log")" -eq 1 ]; echo $?)" "REP-dophang the emit still fired"
ok "$(grep -q 'dr=false' "$FX/emit.log"; echo $?)" "REP-dophang a HUNG doppler probe is bounded to dr=false by the 15 s timeout" "$(cat "$FX/emit.log")"

# --- The log tail: ANSI-stripped, keyword-filtered, last-4 — evidence shape -----
new_fixture r-logtail; rep_body
printf 'action=header\n' > "$RUNDIR/action"; echo exit-code > "$FX/result"; echo 1 > "$FX/exec_status"; echo 1 > "$FX/exec_code"; echo 0 > "$FX/nrestarts"
printf 'plain noise line\n\033[31mdoppler error: token expired\033[0m\nmore noise\n' > "$RUNDIR/log"
touch "$FX/devmap"; rep_run
ok "$(grep -q 'doppler error: token expired' "$FX/rep.out"; echo $?)" "REP-logtail the keyword-matched log line reaches stderr" "$(cat "$FX/rep.out")"
ok "$(! grep -q "$(printf '\033')" "$FX/rep.out"; echo $?)" "REP-logtail ANSI control bytes are stripped before the tail"
ok "$(! grep -q 'noise' "$FX/rep.out"; echo $?)" "REP-logtail non-matching lines are filtered out" "$(cat "$FX/rep.out")"

# ==================================================================================
# Print-sha pins (change-detector, the luks_monitor_forensic_print precedent): the public
# apply log carries ONLY the security-reviewed bytes.
# ==================================================================================
WBU_BEFORE_PRINT_SHA256="d88dccae3c8643f370788904b23711f8ffb8225b9e9b767470f115686902bafd"
WBU_POST_STATE_SHA256="6538c3aebe8b4fb2ab57ab1674710ccb3de1207b6b9a6e34bc9af2e014e5910d"
ok "$([ "$WORKSPACES_BOOT_UNLOCK_PRINT_SHA256" = "$WBU_BEFORE_PRINT_SHA256" ]; echo $?)" \
  "PIN the decoded before-print is byte-identical to the security-reviewed version" \
  "actual=$WORKSPACES_BOOT_UNLOCK_PRINT_SHA256 — an edit needs a security re-review and a pin update"
ok "$([ "$WORKSPACES_BOOT_UNLOCK_POST_STATE_SHA256" = "$WBU_POST_STATE_SHA256" ]; echo $?)" \
  "PIN the decoded post-state print is byte-identical to the security-reviewed version" \
  "actual=$WORKSPACES_BOOT_UNLOCK_POST_STATE_SHA256"

# ==================================================================================
# Mutation battery — copies only, via WBU_* overrides (never the tracked files)
# ==================================================================================
if [[ -z "${WBU_MUTANT:-}" && -z "${WBU_DISABLE_STUB:-}" ]]; then
  MUT="$SCRATCH/mut"; mkdir -p "$MUT"; assert_fixture_dir "$MUT"
  mut_rows=0
  mutate() {  # mutate <label> <want-rc> <env-var> <source> <python replace expr on s>
    local label="$1" want="$2" var="$3" src="$4" expr="$5" copy got
    copy="$MUT/$(basename "$src").$RANDOM$RANDOM"
    if ! MUT_SRC="$src" MUT_DST="$copy" MUT_EXPR="$expr" python3 - <<'PY'
import os, sys
s = open(os.environ["MUT_SRC"]).read()
t = eval(os.environ["MUT_EXPR"], {"s": s, "re": __import__("re")})
if t == s:
    print("mutation did not land", file=sys.stderr); sys.exit(3)
open(os.environ["MUT_DST"], "w").write(t)
PY
    then
      no "mutation $label: could not be applied (instrument)"; return
    fi
    got=0
    env "$var=$copy" WBU_MUTANT=1 bash "$SELF" >"$copy.log" 2>&1 || got=$?
    grade "$label" "$want" "$got" "$copy.log"
  }
  envmut() {  # envmut <label> <want-rc> <env assignment> — no file, an instrument seam
    local label="$1" want="$2" envv="$3" got
    got=0
    env "$envv" WBU_MUTANT=1 bash "$SELF" >"$MUT/envrun.log" 2>&1 || got=$?
    mut_rows=$((mut_rows + 1))
    if [[ "$got" != "$want" ]]; then
      no "mutation $label: want rc $want, got $got ($(tail -3 "$MUT/envrun.log" | tr '\n' ' '))"; return
    fi
    ok 0 "mutation $label -> rc $got"
  }
  grade() {
    local label="$1" want="$2" got="$3" log="$4" key exp
    key="${label%% *}"; exp="${EXPECT_FAIL[$key]:-}"
    mut_rows=$((mut_rows + 1))
    if [[ "$got" != "$want" ]]; then
      no "mutation $label: want rc $want, got $got (log $(tail -3 "$log" | tr '\n' ' '))"; return
    fi
    if [[ "$want" == 1 ]]; then
      if [[ -z "$exp" ]]; then no "mutation $label: no expected [FAIL] name registered (instrument)"; return; fi
      # HARNESS RULE (workspaces-luks-harness.sh): never pipe into a -q predicate — grep -q
      # exits on first match, the producer takes SIGPIPE, and pipefail turns "matched" into
      # "not found". -c reads the whole stream, so the rc cannot lie.
      if [ "$(grep -F '[FAIL]' "$log" | grep -cF -- "$exp" || true)" -eq 0 ]; then
        no "mutation $label: rc 1 but not through the named check [$exp]"; return
      fi
      # ONLY rows (the luks-monitor-install.test.sh mechanism): the named check must be
      # the SOLE failure — it proves no other row sees the edit.
      if [[ -n "${EXPECT_ONLY[$key]:-}" ]] && [[ "$(grep -c '^\[FAIL\]' "$log")" -ne 1 ]]; then
        no "mutation $label: [$exp] failed, but so did other rows (want it to be the only [FAIL])"; return
      fi
    fi
    ok 0 "mutation $label -> rc $got${exp:+ via [$exp]}"
  }
  declare -A EXPECT_FAIL=(
    [MT-1]="mapper+ext4+nofail" [MT-2]="refuses exit 17" [MT-3]="BOTH RequiresMountsFor"
    [MT-4]="no doppler invocation" [MT-5]="comments every non-comment" [MT-6]="exactly-one"
    [MT-7]="pinned by-id" [MT-8]="never carries" [MT-9]="ONLY through the bind peek"
    [MT-10]="systemd-analyze verify" [MT-11]="never restarted" [MT-12]="trigger operand"
    [MT-13]="NO token" [MT-14]="provisioner order" [MT-15]="INDENTED"
    [MT-16]="proof start" [MT-17]="exit 54" [MT-18]="exit 55" [MT-19]="exit 56"
    [MS-1]="secrets get WORKSPACES_LUKS_KEY" [MS-2]="unset after the open" [MS-3]="exit 3"
    [MS-4]="NEVER calls workspaces_luks_emit" [MS-5]="identity" [MS-6]="exactly /mnt/data"
    [MS-7]="never calls mount" [MS-8]="open-status" [MS-9]="R2e"
    [MS-10]="no systemctl start" [MS-11]="docker appears exactly twice"
    [MU-1]="OnFailure=" [MU-2]="RestartMode=direct"
    [MU-3]="RestartPreventExitStatus=3" [MU-4]="installer's own env file" [MU-5]="NO RequiresMountsFor"
    [MU-6]="SyslogIdentifier=workspaces-luks-reopen" [MR-1]="timeout-bounded" [MR-2]="fatal"
    [MTI-1]="OnUnitActiveSec=15min" [MWF-1]="exactly once" [MV-1]="exactly once"
    [MP-1]="guarded" [MP-2]="forbidden diagnostic" [MP-3]="byte-identical" [MP-4]="byte-identical"
    [MH-1]="provisioner order"
  )
  # Rows whose named check must be the ONLY failure — the edit is invisible to
  # every other row (the luks-monitor-install.test.sh EXPECT_ONLY mechanism).
  # MP-3 qualifies (print-line swap hits the sha pin alone); MP-4 does NOT —
  # its rename trips the pin AND P4 AND the after-print fixture.
  declare -A EXPECT_ONLY=([MP-3]=1)
  T="$WBU_LUKS_TF"; S="$WBU_SCRIPT"; UU="$WBU_UNIT"; RU="$WBU_REPORTER"; TI="$WBU_TIMER"; W="$WBU_WF"; V="$WBU_VECTOR"

  # ── .tf / writer mutations ──
  mutate "MT-1 drop nofail from the written fstab line" 1 WBU_LUKS_TF "$T" "s.replace('/dev/mapper/workspaces /mnt/data ext4 defaults,nofail 0 2', '/dev/mapper/workspaces /mnt/data ext4 defaults 0 2', 1)"
  mutate "MT-2 the freeze refusal dropped from the fstab writer" 1 WBU_LUKS_TF "$T" "$(cat <<'X'
re.sub(r'(workspaces_boot_unlock_fstab_writer = \[.*?); exit 17; \}', r'\g<1>; exit 99; }', s, count=1, flags=re.S)
X
)"
  mutate "MT-3 After= dropped from the docker drop-in" 1 WBU_LUKS_TF "$T" "$(cat <<'X'
s.replace('\\\\nAfter=workspaces-luks-reopen.service\\\\n', '\\\\n', 1)
X
)"
  mutate "MT-4 a doppler invocation appears in a writer (the apply log is not the boot channel)" 1 WBU_LUKS_TF "$T" "$(cat <<'X'
s.replace('    "echo \'boot-unlock arm: reopen service', '    "doppler run --config prd_workspaces_luks -- true",\n    "echo \'boot-unlock arm: reopen service', 1)
X
)"
  mutate "MT-5 the fstab writer's comment step removed (a stale /mnt/data line would survive)" 1 WBU_LUKS_TF "$T" "$(cat <<'X'
re.sub(r'(?m)^    "awk .*superseded.*\n', '', s, 1)
X
)"
  mutate "MT-6 the fstab exactly-one post-edit assert removed" 1 WBU_LUKS_TF "$T" "$(cat <<'X'
re.sub(r'(?m)^.*exit 44.*\n', '', s, 1)
X
)"
  mutate "MT-7 the crypttab LINE loses the pinned by-id device" 1 WBU_LUKS_TF "$T" "$(cat <<'X'
s.replace("LINE='workspaces /dev/disk/by-id/scsi-0HC_Volume_", "LINE='workspaces /dev/disk/by-label/workspaces_luks_x", 1)
X
)"
  mutate "MT-8 the crypttab line gains nofail" 1 WBU_LUKS_TF "$T" "s.replace(\"luks,noauto'\", \"luks,nofail'\", 1)"
  mutate "MT-9 chattr applied to the mounted /mnt/data (peek bypassed)" 1 WBU_LUKS_TF "$T" "$(cat <<'X'
s.replace('chattr +i \\"$p/mnt/data\\"', 'chattr +i /mnt/data', 1)
X
)"
  mutate "MT-10 the systemd-analyze verify row dropped from post-state" 1 WBU_LUKS_TF "$T" "$(cat <<'X'
re.sub(r'(?m)^    "systemd-analyze verify.*\n', '', s, 1)
X
)"
  mutate "MT-11 the arm step restarts docker" 1 WBU_LUKS_TF "$T" "$(cat <<'X'
s.replace('    "echo \'boot-unlock arm: reopen service', '    "systemctl restart docker.service",\n    "echo \'boot-unlock arm: reopen service', 1)
X
)"
  mutate "MT-12 the gate writer local dropped from triggers_replace" 1 WBU_LUKS_TF "$T" "$(cat <<'X'
s.replace('    join("\\n", local.workspaces_boot_unlock_gate_writer),\n', '', 1)
X
)"
  mutate "MT-13 the envfile writer plants a token line" 1 WBU_LUKS_TF "$T" "$(cat <<'X'
s.replace('    "printf \'WORKSPACES_DOPPLER_CONFIG=%s\\\\n\' \'prd_workspaces_luks\' >> \\"$t\\"",', '    "printf \'WORKSPACES_DOPPLER_CONFIG=%s\\\\n\' \'prd_workspaces_luks\' >> \\"$t\\"",\n    "printf \'DOPPLER_TOKEN=x\\\\n\' >> \\"$t\\"",', 1)
X
)"
  mutate "MT-14 the fstab writer runs BEFORE the gate writer (the fail-closed order inverted)" 1 WBU_LUKS_TF "$T" "$(cat <<'X'
s.replace('inline = local.workspaces_boot_unlock_gate_writer', 'inline = local.__WBU_SWAP__', 1).replace('inline = local.workspaces_boot_unlock_fstab_writer', 'inline = local.workspaces_boot_unlock_gate_writer', 1).replace('inline = local.__WBU_SWAP__', 'inline = local.workspaces_boot_unlock_fstab_writer', 1)
X
)"
  mutate "MT-15 the whitespace-tolerant crypttab anchor narrowed back to ^workspaces" 1 WBU_LUKS_TF "$T" "$(cat <<'X'
s.replace("^[[:space:]]*workspaces[[:space:]]", "^workspaces[[:space:]]")
X
)"
  mutate "MT-16 the proof start's client-side timeout-420 bound dropped" 1 WBU_LUKS_TF "$T" "$(cat <<'X'
s.replace('timeout 420 systemctl start', 'systemctl start', 1)
X
)"
  mutate "MT-17 the bind refusal weakened to an && chain (failed bind falls through to chattr — the review defect)" 1 WBU_LUKS_TF "$T" "$(cat <<'X'
s.replace('mount --bind / \\"$p\\" || { echo', 'mount --bind / \\"$p\\" && { echo', 1)
X
)"
  mutate "MT-18 the peek symlink refusal dropped" 1 WBU_LUKS_TF "$T" "$(cat <<'X'
re.sub(r'(?m)^.*exit 55.*\n', '', s, 1)
X
)"
  mutate "MT-19 the peek st_dev device-identity assert dropped" 1 WBU_LUKS_TF "$T" "$(cat <<'X'
re.sub(r'(?m)^.*exit 56.*\n', '', s, 1)
X
)"

  # ── script mutations ──
  mutate "MS-1 the key fetch rewritten to doppler run" 1 WBU_SCRIPT "$S" "$(cat <<'X'
s.replace('doppler secrets get WORKSPACES_LUKS_KEY --plain --config "$WORKSPACES_DOPPLER_CONFIG" 2>>"$LOG" || true', 'doppler run --config prd_workspaces_luks -- printenv WORKSPACES_LUKS_KEY 2>>"$LOG" || true', 1)
X
)"
  mutate "MS-2 unset KEY dropped (passphrase survives in the environment)" 1 WBU_SCRIPT "$S" "s.replace('unset KEY', 'true', 1)"
  mutate "MS-3 the emit refusal falls back to exit 1 (systemd retries the structural refusal)" 1 WBU_SCRIPT "$S" "s.replace('exit 3; }', 'exit 1; }', 1)"
  mutate "MS-4 the success path calls the emitter (AC9 broken)" 1 WBU_SCRIPT "$S" "s.replace('logger -t workspaces-luks-reopen --', 'workspaces_luks_emit; logger -t workspaces-luks-reopen --', 1)"
  mutate "MS-5 the identity assert neutered (any backing device passes)" 1 WBU_SCRIPT "$S" "s.replace('[ \"\$_rb\" = \"\$_rd\" ]', '[ -n \"\$_rb\" ]', 1)"
  mutate "MS-6 the target allowlist accepts any mountpoint" 1 WBU_SCRIPT "$S" "s.replace('/mnt/data) : ;;', '/mnt/anywhere) : ;;', 1)"
  mutate "MS-7 the script mounts the mapper directly" 1 WBU_SCRIPT "$S" "s.replace('systemctl start \"\$_munit\"', 'mount \"\$DEV\" \"\$TARGET\"', 1)"
  # The open-phase status check is `-eq 4` (rc 4 = "not active" -> open) with a
  # catch-all die on every OTHER nonzero rc. `-ne 0` would retry-open on a real
  # error — the dead-arm class the status_rc fixture closes.
  mutate "MS-8 the cryptsetup-status arm flipped from -eq 4 to -ne 0 (any error opens)" 1 WBU_SCRIPT "$S" "$(cat <<'X'
s.replace('elif [ "$_st" -eq 4 ]; then', 'elif [ "$_st" -ne 0 ]; then', 1)
X
)"
  # The emit-channel assert must run on the noop arm too — re-gating it under
  # ACTION!=noop is EXACTLY the regression the unconditional check fixes.
  mutate "MS-9 the emit-channel check re-gated under ACTION!=noop (noop skips it)" 1 WBU_SCRIPT "$S" "$(cat <<'X'
s.replace('[ -r "$EMIT" ]', '[ -r "$EMIT" ] || [ "$ACTION" = noop ]', 1)
X
)"
  mutate "MS-10 the docker recovery kick ungated (runs on the noop arm too)" 1 WBU_SCRIPT "$S" "$(cat <<'X'
s.replace('if [ "$ACTION" != noop ]; then\n  systemctl start docker.service', 'if true; then\n  systemctl start docker.service', 1)
X
)"
  mutate "MS-11 a second docker call planted next to the sanctioned one" 1 WBU_SCRIPT "$S" "$(cat <<'X'
s.replace('systemctl start docker.service 2>>"$LOG"', 'systemctl start docker.service 2>>"$LOG"; systemctl restart docker.service', 1)
X
)"

  # ── unit / reporter / timer / workflow / vector mutations ──
  mutate "MU-1 OnFailure dropped" 1 WBU_UNIT "$UU" "re.sub(r'(?m)^OnFailure=.*\n', '', s, 1)"
  mutate "MU-2 RestartMode=direct->normal (OnFailure per attempt, not at convergence)" 1 WBU_UNIT "$UU" "re.sub(r'(?m)^RestartMode=direct$', 'RestartMode=normal', s, 1)"
  mutate "MU-3 RestartPreventExitStatus=3 dropped" 1 WBU_UNIT "$UU" "re.sub(r'(?m)^RestartPreventExitStatus=3\n', '', s, 1)"
  mutate "MU-4 the workspaces-luks-boot env file dropped" 1 WBU_UNIT "$UU" "re.sub(r'(?m)^EnvironmentFile=-/etc/default/workspaces-luks-boot\n', '', s, 1)"
  mutate "MU-5 RequiresMountsFor added to the reopen unit (Requires-strength on the wrong unit)" 1 WBU_UNIT "$UU" "s.replace('OnFailure=workspaces-luks-reopen-failure.service', 'OnFailure=workspaces-luks-reopen-failure.service\nRequiresMountsFor=/mnt/data', 1)"
  mutate "MU-6 SyslogIdentifier renamed (tag diverges from vector.toml)" 1 WBU_UNIT "$UU" "s.replace('SyslogIdentifier=workspaces-luks-reopen', 'SyslogIdentifier=workspaces-reopen', 1)"
  mutate "MR-1 the emit timeout dropped (a wedged emit eats TimeoutStartSec)" 1 WBU_REPORTER "$RU" "s.replace('timeout 90 /bin/bash', '/bin/bash', 1)"
  mutate "MR-2 the emit level downgraded from fatal" 1 WBU_REPORTER "$RU" "s.replace('WL_LEVEL=fatal', 'WL_LEVEL=warning', 1)"
  mutate "MTI-1 OnUnitActiveSec dropped (the standing retry is gone)" 1 WBU_TIMER "$TI" "re.sub(r'(?m)^OnUnitActiveSec=15min\n', '', s, 1)"
  mutate "MWF-1 the -target line dropped from the workflow" 1 WBU_WF "$W" "re.sub(r'(?m)^\\s*-target=terraform_data\\.workspaces_boot_unlock_install[^\\n]*\\n', '', s, 1)"
  mutate "MV-1 the workspaces-luks-reopen tag dropped from vector.toml" 1 WBU_VECTOR "$V" "s.replace('  \"workspaces-luks-reopen\",\n', '', 1)"

  # ── print mutations ──
  mutate "MP-1 an unguarded substitution in the before-print" 1 WBU_LUKS_TF "$T" "$(cat <<'X'
s.replace('  workspaces_boot_unlock_print = [\n    "echo \'boot-unlock install', '  workspaces_boot_unlock_print = [\n    "echo \\"x=$(uptime -s)\\"",\n    "echo \'boot-unlock install', 1)
X
)"
  mutate "MP-2 the before-print dumps the raw crypttab" 1 WBU_LUKS_TF "$T" "$(cat <<'X'
s.replace('  workspaces_boot_unlock_print = [\n    "echo \'boot-unlock install', '  workspaces_boot_unlock_print = [\n    "cat /etc/crypttab || true",\n    "echo \'boot-unlock install', 1)
X
)"
  mutate "MP-3 two before-print lines swapped (only the pin sees it)" 1 WBU_LUKS_TF "$T" "$(cat <<'X'
(lambda L: s.replace(L[0] + '\n' + L[1], L[1] + '\n' + L[0], 1))(s[s.find('workspaces_boot_unlock_print = ['):].splitlines()[1:3])
X
)"
  mutate "MP-4 a post-state tag renamed (triangulated: the pin + P4 + the after-print fixture all see it)" 1 WBU_LUKS_TF "$T" "$(cat <<'X'
s.replace('fstab-mnt-data-lines', 'fstab-lines', 1)
X
)"

  # ── instrument rows ──
  envmut "MI-1 the cryptsetup stub missing (falls through to /usr/bin/cryptsetup)" 2 "WBU_DISABLE_STUB=cryptsetup"
  # Harmless reflows that MUST PASS — they pin the checks' anti-fragility.
  mutate "MH-1 writer lines reflowed but identical behaviour (must PASS)" 0 WBU_LUKS_TF "$T" "$(cat <<'X'
s.replace('"umask 077",\n    "f=/etc/default/workspaces-luks-boot",', '"umask 077; f=/etc/default/workspaces-luks-boot",', 1)
X
)"

  MUT_ROWS_EXPECTED=47
  if [[ "$mut_rows" -ne "$MUT_ROWS_EXPECTED" ]]; then
    printf 'FAIL - %s mutation rows ran, expected %s\n' "$mut_rows" "$MUT_ROWS_EXPECTED"
    exit 1
  fi
fi

printf '\n%s passed, %s failed\n' "$pass" "$fail"

# Anti-vacuity floor. The threshold sits on the line directly above its `if`. It is EXACT:
# 538 is the measured inner-run (WBU_MUTANT=1) assertion count, and the outer run
# adds the MUT_ROWS_EXPECTED mutation rows, so deleting any one check, not only a whole block,
# trips it. Adding a check means raising the floor here.
_wbu_mut_floor="${WBU_MUTANT:+0}"
MIN_ASSERTIONS=$((538 + ${_wbu_mut_floor:-47}))
if [[ "$pass" -lt "$MIN_ASSERTIONS" ]]; then
  printf 'FAIL - only %s assertions passed (floor %s) — a block stopped running\n' "$pass" "$MIN_ASSERTIONS"
  exit 1
fi
[[ "$fail" -eq 0 ]] || { printf 'failed: %s\n' "${FAILED[@]}"; exit 1; }
printf 'all assertions passed\n'
exit 0
