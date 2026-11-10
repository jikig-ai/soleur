#!/usr/bin/env bash
# Suite for first-boot kernel currency on web hosts (#12008, ADR-326).
#
# PROPERTY. A web host born by create or replace installs the archive's generic kernel inside the
# bounded apt block, and the runcmd item RIGHT AFTER that block reboots it ONCE onto that kernel,
# before any item that is not safe to run twice (Doppler, docker, /mnt/data, LUKS). The reboot
# removes cloud-init's scripts_user semaphore so runcmd re-runs from item 1 on the new kernel; a
# root-disk marker makes a second mismatch a named fatal (stage=kernel_settle), never a loop.
#
# INSTRUMENT. cloud-init.yml is a templatefile() source, so the suite renders it through terraform
# (the `$${…}` escapes exist only in the render), parses the YAML, and extracts runcmd item 1 (the
# _emit/on_err/trap arm) JOINED with the settle item. All runcmd items run in ONE /bin/sh, so that
# join is the real execution context of the settle item. Host paths are rewritten into a sandbox;
# dpkg-query, uname, reboot, sleep, curl and docker are PATH stubs that refuse argv they were not
# taught. Every kernel string is SYNTHESIZED (0.0.0-N-generic): no real version appears here (ADR-322).
#
# ANTI-VACUITY. `cases` moves at the CALL SITE of every assertion helper, independently of
# pass()/fail(); the floor and the passes+fails==cases identity are reported by printf + exit 1,
# never through fail() (ADR-193).
set -uo pipefail

export TMPDIR="${TMPDIR:-/var/tmp}"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$DIR/cloud-init.yml"
BOOT="$DIR/soleur-host-bootstrap.sh"
TRAIL="$DIR/scripts/fresh-host-boot-trail.sh"
WF="$DIR/../../../.github/workflows/apply-web-platform-infra.yml"

cases=0
passes=0
fails=0
pass() { passes=$((passes + 1)); printf '[ok] %s\n' "$1"; }
fail() { fails=$((fails + 1)); printf '[FAIL] %s\n' "$1" >&2; }

# INSTRUMENT SELF-TEST: drive both verdict helpers once; refuse to continue unless both counters moved.
pass "instrument self-test (pass)"
fail "instrument self-test (fail) - EXPECTED, subtracted below"
if [[ "$passes" -ne 1 || "$fails" -ne 1 ]]; then
  printf '[FATAL] INSTRUMENT BROKEN: self-test left passes=%d fails=%d, expected 1/1.\n' "$passes" "$fails" >&2
  exit 2
fi
passes=0
fails=0

eq() { # <name> <actual> <expected>
  cases=$((cases + 1))
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1 (got [$2], want [$3])"; fi
}
ok() { # <name> <rc>: 0 = holds
  cases=$((cases + 1))
  if [[ "$2" -eq 0 ]]; then pass "$1"; else fail "$1"; fi
}

ST_P="$passes"; ST_F="$fails"; ST_C="$cases"
{
  eq "selftest eq (must fail)" a b
  ok "selftest ok (must fail)" 1
  eq "selftest eq (must pass)" a a
  ok "selftest ok (must pass)" 0
} > /dev/null 2>&1
if [[ "$fails" -ne $((ST_F + 2)) || "$passes" -ne $((ST_P + 2)) || "$cases" -ne $((ST_C + 4)) ]]; then
  printf '[FATAL] INSTRUMENT BROKEN: eq/ok self-test left passes=%d fails=%d cases=%d, expected +2/+2/+4.\n' "$passes" "$fails" "$cases" >&2
  exit 2
fi
passes="$ST_P"; fails="$ST_F"; cases="$ST_C"

harness() { printf '[HARNESS] %s\n' "$1" >&2; exit 2; }
for f in "$SRC" "$BOOT" "$TRAIL" "$WF"; do [[ -f "$f" ]] || harness "missing $f"; done

WORK="$(mktemp -d "${TMPDIR}/kernel-currency.XXXXXXXX")" || harness "mktemp failed"
trap 'rm -rf "${WORK:?}"' EXIT

# ── Budget rows (pure text; no render needed) ─────────────────────────────────────────────────
# The host's boot window and the trail's deadline move TOGETHER (deadline = window + 60 s), and the
# trail's worst case fits each job's timeout-minutes. Worst case, from the trail's own literals: the
# deadline applies until cloud_init_complete is seen, then CC_GRACE more, plus one more iteration
# (sleep + the curl --max-time bound). PRE_POLL_S is the create job's own declared pre-poll budget
# (digest ~1m + preflight pull ~3m + plan ~2m + apply ~5m, the comment above its timeout-minutes);
# a replace also destroys first, so it is given one more minute.
W=$(sed -n 's/^SOLEUR_FRESH_BOOT_WINDOW_SECONDS=\([0-9][0-9]*\)$/\1/p' "$BOOT" | head -1)
D=$(sed -n 's/^BOOT_TRAIL_DEADLINE_S=\([0-9][0-9]*\)$/\1/p' "$TRAIL" | head -1)
G=$(sed -n 's/^CC_GRACE="\${SOLEUR_BOOT_TRAIL_CC_GRACE:-\([0-9][0-9]*\)}"$/\1/p' "$TRAIL" | head -1)
SL=$(sed -n 's/^  sleep \([0-9][0-9]*\)$/\1/p' "$TRAIL" | head -1)
CM=$(sed -n 's/.*curl --disable --noproxy .\*. -s --max-time \([0-9][0-9]*\) -G .*/\1/p' "$TRAIL" | head -1)
job_timeout() { awk -v j="  $1:" '$0==j{f=1;next} f&&/^  [a-z_]+:$/{exit} f&&/^    timeout-minutes: [0-9]+$/{print $2; exit}' "$WF"; }
TC=$(job_timeout web_host_create); TR=$(job_timeout web_host_replace)
for v in W D G SL CM TC TR; do [[ "${!v}" =~ ^[0-9]+$ ]] || harness "budget operand $v unreadable ('${!v}')"; done
eq "budget: trail deadline = host boot window + 60 s (moved together)" "$D" "$((W + 60))"
ok "budget: the boot window covers the settle reboot (>= 1140 s)" "$([[ "$W" -ge 1140 ]]; echo $?)"
grep -qF 'DEADLINE=$(( SECONDS + BOOT_TRAIL_DEADLINE_S ))' "$TRAIL"; ok "budget: the poll deadline is computed from BOOT_TRAIL_DEADLINE_S" $?
grep -qF 'within ${BOOT_TRAIL_DEADLINE_S}s' "$TRAIL" && ! grep -qE 'within [0-9]+s \(the host' "$TRAIL"
ok "budget: the timeout ::error:: names the deadline variable, not a stale literal" $?
grep -qF "SOLEUR_FRESH_BOOT_WINDOW_SECONDS is ${W})" "$TRAIL"; ok "budget: the timeout ::error:: quotes the host's current window ($W s)" $?
PRE_POLL_S=660
WORST=$((D + G + SL + CM))
ok "budget: create worst case ($((PRE_POLL_S + WORST)) s) fits timeout-minutes $TC" "$([[ $((PRE_POLL_S + WORST)) -le $((TC * 60)) ]]; echo $?)"
ok "budget: replace worst case ($((PRE_POLL_S + 60 + WORST)) s) fits timeout-minutes $TR" "$([[ $((PRE_POLL_S + 60 + WORST)) -le $((TR * 60)) ]]; echo $?)"

# ── Raw-template structural rows ───────────────────────────────────────────────────────────────
SEM_PATH=/var/lib/cloud/instance/sem/config_scripts_user
eq "structural: the scripts_user semaphore path appears exactly once in cloud-init.yml" "$(grep -cF "$SEM_PATH" "$SRC")" 1
eq "structural: no top-level power_state: key" "$(grep -cE '^power_state:' "$SRC")" 0
eq "structural: no top-level packages: key (#6090: apt stays in instrumented runcmd)" "$(grep -cE '^(packages|package_update|package_upgrade|package_reboot_if_required):' "$SRC")" 0

# ── Render (terraform templatefile) ───────────────────────────────────────────────────────────
if ! command -v terraform >/dev/null 2>&1; then
  if [[ -n "${CI:-}" ]]; then
    printf 'kernel-currency: FAIL (terraform is absent under CI; the render-based half cannot run)\n' >&2; exit 1
  fi
  echo "[skip] terraform not installed locally; render-based rows not executed"
  printf 'kernel-currency: SKIP-PARTIAL (%d assertions, %d failed)\n' "$cases" "$fails"
  [[ "$fails" -eq 0 ]]; exit $?
fi
mkdir -p "$WORK/tf"
DSN="https://pubkey123@o1.ingest.de.sentry.io/4242"
printf 'templatefile("%s", { image_name="ghcr.io/x/y:v0", fail2ban_sshd_local_b64="x", host_scripts_content_hash="h", tunnel_token="tt", webhook_deploy_secret="w", doppler_token="d", sentry_dsn="%s", resend_api_key="r", ci_ssh_public_key_openssh="k", workspaces_volume_id="v", workspaces_luks_fresh_boot_token="lt", registry_endpoint="10.0.1.9:5000", web_colocate_inngest=false, web_tunnel_connector=false, host_name="soleur-web-2", private_ip="10.0.1.3", web_probes_token="t", expected_ip="10.0.1.3", web_host_key="web-2", zot_probe_repo="zr", betterstack_ingest_url="bs", soleur_doppler_token_env_b64="RE9QUExFUl9UT0tFTj1k", zot_pull_user="zot-pull", zot_pull_token="zz" })\n' \
  "$SRC" "$DSN" | terraform -chdir="$WORK/tf" console > "$WORK/r.raw" 2> "$WORK/r.err" \
  || harness "terraform render failed: $(head -c 400 "$WORK/r.err")"

# extract.py <raw-render> <sandbox> <out-script> <out-report>: validates the render as YAML, writes the
# joined item1+settle script with host paths rewritten, and a report of structural facts (key=value).
cat > "$WORK/extract.py" <<'PY'
import re, sys, yaml
L = open(sys.argv[1]).read().splitlines()
body = "\n".join(L[1:-1]) if (L and L[0].lstrip().startswith("<<")) else "\n".join(L)
doc = yaml.safe_load(body)
sb, out, rep = sys.argv[2], sys.argv[3], sys.argv[4]
items = doc["runcmd"]
S = [i if isinstance(i, str) else " ".join(i) for i in items]
def one(pred, name):
    hits = [k for k, i in enumerate(S) if pred(i)]
    if len(hits) != 1:
        print("extract: %s matched %d items" % (name, len(hits)), file=sys.stderr); sys.exit(2)
    return hits[0]
i1 = one(lambda i: "STAGE=runcmd_early" in i, "item1")
ia = one(lambda i: "STAGE=apt_install" in i, "apt")
ik = one(lambda i: "STAGE=kernel_settle" in i, "settle")
for need in ("_emit()", "on_err()", "trap on_err EXIT"):
    if need not in S[i1]:
        print("extract: item1 lacks " + need, file=sys.stderr); sys.exit(2)
def strip_comments(t):
    return "\n".join(l for l in t.splitlines() if not l.lstrip().startswith("#"))
# The idempotent allowlist: every item before the settle item is one of these, each exactly once.
ALLOW = [
    ("arm", lambda i: "STAGE=runcmd_early" in i and "trap on_err EXIT" in i),
    ("hosts_deny", lambda i: i.lstrip().startswith("for f in /etc/hosts /etc/cloud/templates/hosts.debian.tmpl;")),
    ("networkctl_reload", lambda i: i.startswith("networkctl reload ||")),
    ("sshd_restart", lambda i: i == "systemctl restart sshd"),
    ("apt", lambda i: "STAGE=apt_update" in i and "STAGE=apt_install" in i),
]
pre = S[:ik]
names = []
for i in pre:
    m = [n for n, p in ALLOW if p(i)]
    names.append(m[0] if len(m) == 1 else "UNLISTED:" + i.splitlines()[0][:60])
# Non-idempotent references before the settle item (comments stripped; the arm's on_err cleanup of the
# seed container runs only on a failure path and is removed exactly). `docker` is matched as a command
# word, so the hosts deny's docker.pkg.github.com (a name it blocks) is not a docker call.
forbid = re.compile(r"doppler|\bdocker\b(?![.-])|/mnt/data|luks|cloudflared", re.I)
bad = []
for i in pre:
    t = strip_comments(i).replace("docker rm -f soleur-hostscript-seed >/dev/null 2>&1 || true", "")
    if forbid.search(t):
        bad.append(t.splitlines()[0][:60] if t.strip() else "?")
apt = S[ia]
inst = [l for l in apt.splitlines() if "apt-get install" in l]
settle = S[ik]
def pos(t, s):
    return t.find(s)
with open(rep, "w") as r:
    r.write("settle_after_apt=%d\n" % (1 if ik == ia + 1 else 0))
    r.write("pre_names=%s\n" % ",".join(names))
    r.write("pre_forbidden=%d\n" % len(bad))
    r.write("apt_install_lines=%d\n" % len(inst))
    r.write("apt_install_has_kernel=%d\n" % (1 if inst and re.search(r"(^|\s)linux-image-generic(\s|$)", inst[0]) else 0))
    r.write("apt_install_bounded=%d\n" % (1 if inst and "until timeout 300 apt-get install" in inst[0] else 0))
    r.write("apt_install_repairs_dpkg=%d\n" % (1 if inst and re.search(r"; do .*dpkg --configure -a.*; done", inst[0]) else 0))
    r.write("top_power_state=%d\n" % (1 if "power_state" in doc else 0))
    r.write("top_packages=%d\n" % (1 if "packages" in doc else 0))
    r.write("marker_root_disk=%d\n" % (1 if "/var/lib/soleur/kernel-settle" in settle and "/run/" not in settle else 0))
    tr, rm, rb, em = pos(settle, "trap - EXIT"), pos(settle, "rm -f "), pos(settle, "; reboot "), pos(settle, "kernel_reboot info")
    r.write("order_ok=%d\n" % (1 if -1 not in (tr, rm, rb, em) and em < tr < rm < rb else 0))
    r.write("reboots_in_runcmd=%d\n" % sum(len(re.findall(r"(^|[;&|\s])(reboot|shutdown -r|systemctl reboot)(\s|;|$)", strip_comments(i), re.M)) for i in S))
script = "set -e\n" + S[i1] + "\n" + settle + "\necho __AFTER_SETTLE__\ntrap - EXIT\nexit 0\n"
for p in ("/var/lib/soleur", "/var/lib/cloud/", "/run/"):
    script = script.replace(p, sb + p)
resid = re.findall(r"(?:^|[^A-Za-z0-9_./-])/(?:var/lib/soleur|var/lib/cloud|run)/?", script, re.M)
if resid:
    print("extract: residual host paths after rewrite: %r" % resid[:3], file=sys.stderr); sys.exit(2)
open(out, "w").write(script)
PY
SB="$WORK/sb"
python3 "$WORK/extract.py" "$WORK/r.raw" "$SB" "$WORK/settle.sh" "$WORK/report" || harness "extraction failed"
rv() { sed -n "s/^$1=//p" "$WORK/report"; }

eq "structural: the settle item is the runcmd item right after the apt block" "$(rv settle_after_apt)" 1
eq "structural: every item before the settle item is on the idempotent allowlist, in order" "$(rv pre_names)" "arm,hosts_deny,networkctl_reload,sshd_restart,apt"
eq "structural: no Doppler/docker/mnt-data/LUKS/cloudflared reference before the settle item" "$(rv pre_forbidden)" 0
eq "structural: the apt block has exactly one apt-get install line" "$(rv apt_install_lines)" 1
eq "structural: linux-image-generic is on the bounded install line" "$(rv apt_install_has_kernel)" 1
eq "structural: the install line keeps its timeout bound" "$(rv apt_install_bounded)" 1
eq "structural: the install retry runs dpkg --configure -a before attempt 2" "$(rv apt_install_repairs_dpkg)" 1
eq "structural: rendered doc has no power_state key" "$(rv top_power_state)" 0
eq "structural: rendered doc has no packages key" "$(rv top_packages)" 0
eq "structural: the settle marker lives on the root disk (/var/lib/soleur), never /run" "$(rv marker_root_disk)" 1
eq "structural: settle order is emit kernel_reboot < trap - EXIT < semaphore removal < reboot" "$(rv order_ok)" 1
eq "structural: exactly one reboot call in all of runcmd" "$(rv reboots_in_runcmd)" 1

# ── Behaviour (stubbed) ────────────────────────────────────────────────────────────────────────
SH="$(command -v dash || command -v sh)"
BIN="$WORK/bin"; mkdir -p "$BIN"
cat > "$BIN/dpkg-query" <<'STUB'
#!/bin/sh
[ "$#" -eq 3 ] && [ "$1" = "-W" ] && [ "$2" = '-f=${Depends}' ] && [ "$3" = "linux-image-generic" ] || { echo "REFUSED dpkg-query $*" >> "$KC_CAP"; exit 64; }
[ "${KC_DPKG_RC:-0}" = 0 ] || exit "$KC_DPKG_RC"
if [ -n "$KC_TARGET" ]; then printf 'linux-image-%s, linux-firmware, intel-microcode' "$KC_TARGET"; else printf 'linux-firmware'; fi
STUB
cat > "$BIN/uname" <<'STUB'
#!/bin/sh
[ "$#" -eq 1 ] && [ "$1" = "-r" ] || { echo "REFUSED uname $*" >> "$KC_CAP"; exit 64; }
printf '%s\n' "$KC_UNAME"
STUB
# reboot: records the state the settle step must have reached BEFORE it (semaphore gone, marker
# written), then either kills its parent shell (a real reboot ends the script) or returns (a reboot
# that never happened, which must end in a named fatal rather than in the next runcmd item).
cat > "$BIN/reboot" <<'STUB'
#!/bin/sh
[ "$#" -eq 0 ] || { echo "REFUSED reboot $*" >> "$KC_CAP"; exit 64; }
s=absent; [ -e "$KC_SEM" ] && s=present
m=absent; [ -e "$KC_MARK" ] && m=present
echo "reboot sem=$s marker=$m" >> "$KC_CAP"
[ "${KC_REBOOT:-kill}" = kill ] && kill -KILL "$PPID"
exit 0
STUB
cat > "$BIN/sleep" <<'STUB'
#!/bin/sh
echo "sleep $*" >> "$KC_CAP"
STUB
cat > "$BIN/curl" <<'STUB'
#!/bin/sh
prev=""
for a in "$@"; do
  if [ "$prev" = "-d" ]; then
    st=$(printf '%s' "$a" | sed -n 's/.*"stage":"\([^"]*\)".*/\1/p'); lv=$(printf '%s' "$a" | sed -n 's/.*"level":"\([^"]*\)".*/\1/p')
    echo "emit $st $lv" >> "$KC_CAP"
  fi
  prev="$a"
done
exit 0
STUB
printf '#!/bin/sh\nexit 0\n' > "$BIN/docker"
chmod +x "$BIN/"*

# run_settle: sets R_RC R_OUT R_EMITS R_REBOOT R_SLEEP R_REFUSED; KC_SETTLE overrides the script text.
run_settle() {
  rm -rf "${SB:?}"; mkdir -p "$SB/var/lib/cloud/instance/sem" "$SB/run"
  local cap="$WORK/cap" sem="$SB$SEM_PATH" mark="$SB/var/lib/soleur/kernel-settle"
  : > "$cap"
  [[ "${KC_SEM_PRESENT:-1}" == 1 ]] && : > "$sem"
  if [[ "${KC_MARK_PRESENT:-0}" == 1 ]]; then mkdir -p "$SB/var/lib/soleur"; : > "$mark"; fi
  printf '%s' "${KC_SETTLE-$(cat "$WORK/settle.sh")}" > "$WORK/run.sh"
  R_OUT="$(PATH="$BIN:$PATH" KC_CAP="$cap" KC_SEM="$sem" KC_MARK="$mark" KC_TARGET="${KC_TARGET-0.0.0-2-generic}" \
    KC_UNAME="${KC_UNAME:-0.0.0-2-generic}" KC_DPKG_RC="${KC_DPKG_RC:-0}" KC_REBOOT="${KC_REBOOT:-kill}" \
    "$SH" "$WORK/run.sh" 2>/dev/null)"; R_RC=$?
  R_EMITS="$(sed -n 's/^emit \(.*\)$/\1/p' "$cap" | paste -sd';' -)"
  R_REBOOT="$(grep '^reboot ' "$cap" | paste -sd';' -)"
  R_SLEEP="$(grep -c '^sleep 600$' "$cap" || true)"
  R_REFUSED="$(grep -F 'REFUSED ' "$cap" | paste -sd';' -)"
  R_SEM=absent; [[ -e "$sem" ]] && R_SEM=present
  R_MARK=absent; [[ -e "$mark" ]] && R_MARK=present
  R_AFTER=0; [[ "$R_OUT" == *__AFTER_SETTLE__* ]] && R_AFTER=1
}
# summary line the cases compare against (one string per case keeps every field in one assertion).
summ() { printf 'rc=%s after=%s emits=[%s] reboot=[%s] sleep600=%s sem=%s marker=%s refused=[%s]' \
  "$R_RC" "$R_AFTER" "$R_EMITS" "$R_REBOOT" "$R_SLEEP" "$R_SEM" "$R_MARK" "$R_REFUSED"; }

FATAL_SETTLE="runcmd_start info;kernel_settle fatal"
case_match()      { KC_TARGET=0.0.0-2-generic KC_UNAME=0.0.0-2-generic run_settle; summ; }
case_reboot()     { KC_TARGET=0.0.0-2-generic KC_UNAME=0.0.0-1-generic run_settle; summ; }
case_second()     { KC_TARGET=0.0.0-2-generic KC_UNAME=0.0.0-1-generic KC_MARK_PRESENT=1 run_settle; summ; }
case_unreadable() { KC_DPKG_RC=1 KC_UNAME=0.0.0-1-generic run_settle; summ; }
case_empty()      { KC_TARGET='' KC_UNAME=0.0.0-1-generic run_settle; summ; }
case_nosem()      { KC_TARGET=0.0.0-2-generic KC_UNAME=0.0.0-1-generic KC_SEM_PRESENT=0 run_settle; summ; }
case_stuck()      { KC_TARGET=0.0.0-2-generic KC_UNAME=0.0.0-1-generic KC_REBOOT=return run_settle; summ; }

W_MATCH="rc=0 after=1 emits=[runcmd_start info] reboot=[] sleep600=0 sem=present marker=absent refused=[]"
W_REBOOT="rc=137 after=0 emits=[runcmd_start info;kernel_reboot info] reboot=[reboot sem=absent marker=present] sleep600=0 sem=absent marker=present refused=[]"
W_SECOND="rc=1 after=0 emits=[$FATAL_SETTLE] reboot=[] sleep600=0 sem=present marker=present refused=[]"
W_UNREAD="rc=1 after=0 emits=[$FATAL_SETTLE] reboot=[] sleep600=0 sem=present marker=absent refused=[]"
W_NOSEM="rc=1 after=0 emits=[$FATAL_SETTLE] reboot=[] sleep600=0 sem=absent marker=absent refused=[]"
W_STUCK="rc=1 after=0 emits=[runcmd_start info;kernel_reboot info;kernel_settle fatal] reboot=[reboot sem=absent marker=present] sleep600=1 sem=absent marker=present refused=[]"

eq "behaviour: running kernel = target -> no reboot, runcmd continues, no marker" "$(case_match)" "$W_MATCH"
eq "behaviour: mismatch, first pass -> marker, kernel_reboot info, semaphore removed BEFORE one reboot" "$(case_reboot)" "$W_REBOOT"
eq "behaviour: mismatch on the second pass (marker present) -> named fatal, no reboot" "$(case_second)" "$W_SECOND"
eq "behaviour: unreadable dpkg -> named fatal, no reboot" "$(case_unreadable)" "$W_UNREAD"
eq "behaviour: meta package with no linux-image dependency -> named fatal, no reboot" "$(case_empty)" "$W_UNREAD"
eq "behaviour: semaphore absent (cloud-init renamed it) -> named fatal, no reboot, no marker" "$(case_nosem)" "$W_NOSEM"
eq "behaviour: reboot returned without rebooting -> waits, then named fatal, never the next item" "$(case_stuck)" "$W_STUCK"

# ── Mutation rows (Guard 2) over the joined script ────────────────────────────────────────────
REAL="$(cat "$WORK/settle.sh")"
MUTATION_ROWS=0
mut_row() { # <name> <case-fn> <want> <from> <to>
  local name="$1" fn="$2" want="$3" from="$4" to="$5" mutated got
  MUTATION_ROWS=$((MUTATION_ROWS + 1))
  mutated="${REAL/"$from"/"$to"}"
  if [[ "$mutated" == "$REAL" ]]; then cases=$((cases + 1)); fail "mutation: $name did not land"; return; fi
  got="$(KC_SETTLE="$mutated" "$fn")"
  cases=$((cases + 1))
  if [[ "$got" != "$want" ]]; then pass "mutation: $name is caught by $fn"; else fail "mutation: $name SURVIVED $fn"; fi
}
mut_row "marker ignored (always reboot on mismatch)" case_second "$W_SECOND" '[ ! -e $M ] && ' ''
mut_row "semaphore-exists guard dropped" case_nosem "$W_NOSEM" ' && [ -f $S ]' ''
mut_row "empty target treated as a match" case_empty "$W_UNREAD" '[ -n "$K" ] || exit 1' ':'
mut_row "post-reboot fatal dropped (stuck reboot falls through)" case_stuck "$W_STUCK" 'sleep 600; on_err' 'sleep 600'
mut_row "semaphore not removed" case_reboot "$W_REBOOT" 'rm -f $S; ' ''
mut_row "marker not written" case_reboot "$W_REBOOT" ': > $M' ':'

echo
MIN_CASES=35
if [[ "$cases" -lt "$MIN_CASES" ]]; then
  printf 'kernel-currency: FAIL (only %d assertions ran; floor %d - the suite may have been truncated)\n' "$cases" "$MIN_CASES" >&2
  exit 1
fi
if [[ "$MUTATION_ROWS" -ne 6 ]]; then
  printf 'kernel-currency: FAIL (%d mutation rows ran, expected exactly 6)\n' "$MUTATION_ROWS" >&2
  exit 1
fi
if [[ $((passes + fails)) -ne "$cases" ]]; then
  printf 'kernel-currency: FAIL (accounting: passes+fails=%d != cases=%d; a verdict helper was neutered)\n' "$((passes + fails))" "$cases" >&2
  exit 1
fi
if [[ "$fails" -gt 0 ]]; then
  printf 'kernel-currency: FAIL (%d of %d assertions failed)\n' "$fails" "$cases" >&2
  exit 1
fi
printf 'kernel-currency: PASS (%d assertions, 0 failed)\n' "$cases"
