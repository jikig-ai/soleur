#!/usr/bin/env bash
# cloud-init-web-zot-seed.test.sh — #8651: a fresh web host's seed pull is zot-first by BAKE.
#
# WHY THIS SUITE EXECUTES THE BLOCK instead of grepping it. The defect it guards was a property
# of the SHELL, not of the text: the seed block read ZOT_REGISTRY_URL with `doppler secrets get`
# after sourcing the token file with a bare `.`, which assigns a shell variable and exports
# nothing, so every call ran tokenless, answered empty, and the ref silently stayed on GHCR —
# whose read credential is revoked (AP-016). A grep for "zot login precedes the pull" was green
# the whole time (#6981 learning: a grep cannot pin a property of the shell that runs the text).
#
# So: render cloud-init.yml through terraform's own templatefile() (the escaping traps — `$${`,
# `%{` — only exist in the render), extract runcmd item 1 (_emit/on_err/the trap) JOINED with the
# daemon.json item and the host-script extraction item, rewrite /run and /etc paths into a
# sandbox, cut execution at STAGE=extract, and run it under dash with stubbed docker/ip/sleep/
# timeout/doppler/curl. Assertions read what the stubs RECORDED (argv, Sentry POST bodies, sleeps).
#
# Guards (plan 2026-09-23-fix-web-host-fresh-boot-zot-primary-plan.md §Guard Contract):
#   G1 zot-only without Doppler (no GHCR arm since #8036 1d); a zot failure names itself and
#      ends the boot; the token never leaks
#   G2 bounded, fail-open pre-pull private-NIC wait; every non-ready outcome is routed
#   G3 no Doppler invocation (and no xtrace) above the terminal block's exporting source
#   G4 the boot trail can say which registry served a fresh boot (--image-origin + job line)
# G1-G3 carry a mutation section (every mutation must turn its predicate RED); G4 and the
# cross-template parity block are behavioural/static rows without their own mutation battery.
#
# Exit: 0 all green, 1 an assertion failed, 2 a HARNESS failure (render/extract/mutation did
# not land). Under CI a missing terraform is a FAIL, never a skip.
set -uo pipefail

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
# A pipe into `grep -q` SIGPIPEs its producer on an early match and pipefail reads it as
# FALSE (#7024); _qgrep reads all of its input instead.
_qgrep() { grep "$@" >/dev/null; }
export TMPDIR="${TMPDIR:-/var/tmp}"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$DIR/cloud-init.yml"
SRV="$DIR/server.tf"
ALERTS="$DIR/sentry/issue-alerts.tf"
INNGEST_CI="$DIR/cloud-init-inngest.yml"
REPO="$(cd "$DIR/../../.." && pwd)"

pass=0; fail=0; skipped=0
ok() { pass=$((pass + 1)); echo "[ok] $1"; }
no() { fail=$((fail + 1)); echo "[FAIL] $1" >&2; }
harness() { echo "[HARNESS] $1" >&2; exit 2; }

# Instrument self-test: both helpers must move their counters, or every verdict below is void.
ok "instrument self-test (pass arm)" >/dev/null; no "instrument self-test (fail arm)" 2>/dev/null
[ "$pass" -eq 1 ] && [ "$fail" -eq 1 ] || { printf 'instrument self-test broken\n'; exit 2; }
pass=0; fail=0; skipped=0

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
SHELL_BIN="$(command -v dash || command -v sh)"

# Mutation table: key -> function(s) -> s'. Each must CHANGE the text (checked by the caller:
# exit 3 = did not land = HARNESS failure). Written from a quoted heredoc, so no shell escaping.
cat > "$WORK/muts.py" <<'MUTS_PY'
import sys
def move_zot_login_after_pull(s):
    i = s.index("\nZL=fail"); j = s.index("\n", s.index("done", i)); blk = s[i:j]
    s = s[:i] + s[j:]; k = s.index("\nprintf 'zot_login="); return s[:k] + blk + s[k:]
def move_zot_login_before_wait(s):
    i = s.index("\nZL=fail"); j = s.index("\n", s.index("done", i)); blk = s[i:j]
    s = s[:i] + s[j:]; k = s.index("\nNIC=probe_fault"); return s[:k] + blk + s[k:]
M = {
  # G3 — on the SOURCE template
  "g3_emit_dsn": lambda s: s.replace("DSN='${sentry_dsn}'\n        if", "DSN='${sentry_dsn}'\n        [ -n \"$DSN\" ] || DSN=$(doppler secrets get SENTRY_DSN --plain)\n        if", 1),
  "g3_seed_read": lambda s: s.replace("    ZEP='${registry_endpoint}'\n", "    ZEP='${registry_endpoint}'\n    X=$(doppler secrets get X --plain)\n", 1),
  "g3_no_anchor": lambda s: s.replace("    set -a; . /etc/default/webhook-deploy; set +a\n", "    . /etc/default/webhook-deploy\n", 1),
  "g3_colo_read": lambda s: s.replace("ZURL='${registry_endpoint}'", "ZURL=$(timeout 15 doppler secrets get ZOT_REGISTRY_URL --plain)", 1),
  "g3_dup_anchor": lambda s: s.replace("    STAGE=runcmd_early\n", "    STAGE=runcmd_early\n    set -a; . /etc/default/webhook-deploy; set +a\n", 1),
  "g3_dl_above": lambda s: s.replace("    ZEP='${registry_endpoint}'\n", "    ZEP='${registry_endpoint}'\n    soleur-doppler-download /tmp/x\n", 1),
  "g3_xtrace": lambda s: s.replace("    ZEP='${registry_endpoint}'\n", "    ZEP='${registry_endpoint}'\n    set -x\n", 1),
  "g3_doppler_flag": lambda s: s.replace("    ZEP='${registry_endpoint}'\n", "    ZEP='${registry_endpoint}'\n    ZX=$(doppler --silent secrets get X || true)\n", 1),
  "g3_setex": lambda s: s.replace("    ZEP='${registry_endpoint}'\n", "    ZEP='${registry_endpoint}'\n    set -e -x\n", 1),
  "g3_bashx": lambda s: s.replace("    ZEP='${registry_endpoint}'\n", "    ZEP='${registry_endpoint}'\n    bash -x /tmp/y\n", 1),
  "g3_xtrace_long": lambda s: s.replace("    ZEP='${registry_endpoint}'\n", "    ZEP='${registry_endpoint}'\n    set -o errexit -o xtrace\n", 1),
  # G1 — on the RENDERED, extracted script
  "g1_doppler_ep": lambda s: s.replace("ZEP='10.0.1.30:5000'", "ZEP=$(timeout 15 doppler secrets get ZOT_REGISTRY_URL --plain 2>/dev/null || true)", 1),
  "g1_v2_gate": lambda s: s.replace(" ;; esac\n", ' ;; esac\n    curl -s -o /dev/null --max-time 3 "http://$ZEP/v2/" || REF="$IMAGE_REF"\n', 1),
  "g1_reassign": lambda s: s.replace('\n[ -n "$REF" ] && [ $ZL = ok ] && while', '\nREF="$IMAGE_REF"\n[ -n "$REF" ] && [ $ZL = ok ] && while', 1),
  # #8036 1d: the GHCR arm is gone; these two put one back (a GHCR pull after the zot miss, and a
  # GHCR login in the seed item). Each must be caught by the predicate that owns the property.
  "g1_ghcr_pull_back": lambda s: s.replace('\nZ="zot=[', '\n[ $OK = 1 ] || { timeout 180 docker pull "$IMAGE_REF" >/dev/null 2>&1 && OK=1; }\nZ="zot=[', 1),
  "g1_ghcr_login_back": lambda s: s.replace("\nSTAGE=pull\nC=none", "\nprintf '%s' 'ght' | timeout 60 docker login ghcr.io -u 'ghu' --password-stdin >/dev/null 2>&1 || true\nSTAGE=pull\nC=none", 1),
  "g1_tag_to_zot": lambda s: s.replace("*@sha256:*)", "*)", 1),
  "g1_err_level": lambda s: s.replace('"$STAGE" fatal', '"$STAGE" error', 1),
  "g1_no_zot_leg": lambda s: s.replace("'nic=%s:%s %s pull_err: %s' \"$NIC\" \"$W\" \"$Z\"", "'nic=%s:%s pull_err: %s' \"$NIC\" \"$W\"", 1),
  "g1_login_after_pull": move_zot_login_after_pull,
  "g1_no_redact": lambda s: s.replace("sed -E 's#[A-Za-z0-9_+/-]{40,}#REDACTED#g'", "cat", 1),
  "g1_tail_first": lambda s: s.replace("printf 'nic=%s:%s %s pull_err: %s' \"$NIC\" \"$W\" \"$Z\" \"$T\"",
                                       "printf 'pull_err: %s nic=%s:%s %s' \"$T\" \"$NIC\" \"$W\" \"$Z\"", 1),
  "g1_tail_before_redact": lambda s: s.replace("| sed -E 's#[A-Za-z0-9_+/-]{40,}#REDACTED#g' | tail -c 100", "| tail -c 100 | sed -E 's#[A-Za-z0-9_+/-]{40,}#REDACTED#g'", 1),
  "g1_login_no_user": lambda s: s.replace(" -u 'zot-pull' --password-stdin", " --password-stdin", 1),
  "g1_login_unbounded": lambda s: s.replace("| timeout 60 docker login \"$ZEP\"", "| docker login \"$ZEP\"", 1),
  "g1_pull_ungated": lambda s: s.replace("[ $ZL = ok ] && while [ $ZN -lt 3 ]", "while [ $ZN -lt 3 ]", 1),
  "g1_login_once": lambda s: s.replace("while [ $n -lt 3 ]", "while [ $n -lt 1 ]", 1),
  "g1_drop_unreach": lambda s: s.replace("C=unreach ;;", ";;", 1),
  "g1_timeout_retries": lambda s: s.replace("[ $R = 124 ] && break; :;", ":;", 1),
  "g1_no_install": lambda s: s.replace(next(l for l in s.splitlines(True) if l.startswith("for f in soleur-stage-detail")), "", 1),
  "g2_no_break": lambda s: s.replace("{ NIC=ready; break; }", "{ NIC=ready; }", 1),
  "v_zep_empty": lambda s: s.replace("ZEP='10.0.1.30:5000'", "ZEP=''", 1),
  "v_nonghcr": lambda s: s.replace("IMAGE_REF='ghcr.io/jikig-ai/", "IMAGE_REF='docker.io/jikig-ai/"),
  "g1_answering_doppler": lambda s: s.replace("ZEP='10.0.1.30:5000'", "ZEP=$(timeout 15 doppler secrets get ZOT_REGISTRY_URL --plain)", 1),
  # G2
  "g2_ip_piped": lambda s: s.replace("O=$(ip -4 -o addr show 2>/dev/null) && { P=1; printf '%s\\n' \"$O\" | grep", "P=1; ip -4 -o addr show 2>/dev/null | { grep", 1),
  "g2_no_empty_guard": lambda s: s.replace('[ -n "$E" ] && while', "while", 1),
  "g2_body_skipped": lambda s: s.replace("while [ $i -lt 75 ]", "while false", 1),
  "g2_both_stages": lambda s: s.replace("private_nic_$NIC warning;", 'private_nic_$NIC warning; _emit "soleur-cloud-init boot stage" private_nic_probe_fault warning;', 1),
  "g2_renamed_stage": lambda s: s.replace("NIC=timeout", "NIC=wait_timeout", 1),
  "g2_wait_after_login": move_zot_login_before_wait,
  "g2_clock_loop": lambda s: s.replace("while [ $i -lt 75 ]; do", "D=$(( $(date +%s) + 150 )); while [ $(date +%s) -lt $D ]; do", 1),
  "g2_argv": lambda s: s.replace("ip -4 -o addr show", "ip -o link show", 1),
}
p, key = sys.argv[1], sys.argv[2]
s = open(p).read(); o = M[key](s)
if o == s:
    sys.exit(3)
open(p, "w").write(o)
MUTS_PY

# ── Guard 3 (static, needs no terraform): the Doppler census ──────────────────────────────────
# Counts doppler INVOCATIONS (`doppler secrets|run|configure`, `soleur-doppler-download`) on
# non-comment lines between `runcmd:` and the terminal block's single exporting source. A
# duplicated or missing anchor is an undefined span — reported as ERR, never as a count.
ANCHOR='set -a; . /etc/default/webhook-deploy; set +a'
census() {
  python3 - "$1" "$ANCHOR" <<'PY'
import re, sys
src = open(sys.argv[1]).read().splitlines()
anchor = sys.argv[2]
hits = [i for i, l in enumerate(src) if l.strip() == anchor]
if len(hits) != 1:
    print("ERR anchor_count=%d" % len(hits)); sys.exit(0)
try:
    start = next(i for i, l in enumerate(src) if l.startswith("runcmd:"))
except StopIteration:
    print("ERR no_runcmd"); sys.exit(0)
pat = re.compile(r"(^|[^A-Za-z0-9_-])doppler(\s+--?[A-Za-z][\w-]*(=\S+|\s+(?!secrets\b|run\b|configure\b)[^-\s]\S*)?)*\s+(secrets|run|configure)\b|soleur-doppler-download")
n = 0
for l in src[start:hits[0]]:
    if l.lstrip().startswith("#"):
        continue
    n += len(pat.findall(l))
print(n)
PY
}
xtrace_census() {
  grep -vE '^[[:space:]]*#' "$1" | grep -cE '(^|[;&|[:space:]])set([[:space:]]+-[[:alnum:]]+)*[[:space:]]+-[a-z]*x|(^|[;&|[:space:]])set[[:space:]].*-o[[:space:]]+xtrace|(^|[^[:alnum:]_])(ba|da)?sh[[:space:]]+-[a-z]*x' || true
}

c=$(census "$SRC")
[ "$c" = 0 ] && ok "G3: no doppler invocation in runcmd above the terminal exporting source (census=$c)" \
  || no "G3: doppler invocations above the terminal exporting source: census=$c (#6985 — tokenless by construction)"
xc=$(xtrace_census "$SRC")
[ "$xc" = 0 ] && ok "G3: no shell tracing anywhere in cloud-init.yml (baked tokens would print)" \
  || no "G3: shell tracing found ($xc) — set -x would print baked tokens into cloud-init-output.log"
# H1 known-positive: an injected call just above the anchor must count exactly 1.
cp "$SRC" "$WORK/g3.yml"
python3 - "$WORK/g3.yml" "$ANCHOR" <<'PY'
import sys
p, a = sys.argv[1], sys.argv[2]
s = open(p).read()
assert s.count(a) == 1, "anchor"
s = s.replace(a, "doppler secrets get X --plain\n    " + a)
open(p, "w").write(s)
PY
base=$(census "$SRC")
[ "$(census "$WORK/g3.yml")" = "$((base + 1))" ] && ok "G3 H1: known-positive injection above the anchor counts +1" \
  || no "G3 H1: census missed an injected doppler call (base=$base injected=$(census "$WORK/g3.yml"))"
# H2 regex reach: the pinned pre-change commit carries exactly the 11 call sites this PR removes.
if git -C "$REPO" cat-file -e 3aaaede525:apps/web-platform/infra/cloud-init.yml 2>/dev/null; then
  git -C "$REPO" show 3aaaede525:apps/web-platform/infra/cloud-init.yml > "$WORK/g3-base.yml"
  b=$(census "$WORK/g3-base.yml")
  [ "$b" = 11 ] && ok "G3 H2: census over the pinned pre-change file = 11 (regex reaches the real call forms)" \
    || no "G3 H2: census over 3aaaede525 = $b, expected 11"
else
  if [ -n "${CI:-}" ]; then no "G3 H2: pinned commit 3aaaede525 unavailable in CI (shallow checkout?)"
  else echo "[skip] G3 H2: 3aaaede525 not in this clone"; skipped=$((skipped + 1)); fi
fi
# H3 must-PASS: a comment mentioning the call form above the anchor is not a call.
python3 - "$SRC" "$WORK/g3c.yml" "$ANCHOR" <<'PY'
import sys
s = open(sys.argv[1]).read()
s = s.replace(sys.argv[3], "# doppler secrets get NOT_A_CALL\n    " + sys.argv[3])
open(sys.argv[2], "w").write(s)
PY
[ "$(census "$WORK/g3c.yml")" = "$(census "$SRC")" ] && ok "G3 H3: a comment naming the call form is not counted" \
  || no "G3 H3: census counted a comment line"

# G3 mutation matrix (on a sandbox copy of the SOURCE).
g3_mut() {  # <label> <key>
  cp "$SRC" "$WORK/m.yml"
  python3 "$WORK/muts.py" "$WORK/m.yml" "$2" || harness "G3 mutation did not land: $1"
  local r; r=$(census "$WORK/m.yml"); local x; x=$(xtrace_census "$WORK/m.yml")
  if [ "$r" != 0 ] || [ "$x" != 0 ]; then ok "G3 mutation RED: $1 (census=$r xtrace=$x)"
  else no "G3 mutation SURVIVED: $1"; fi
}
g3_mut "restore _emit's doppler SENTRY_DSN fallback" g3_emit_dsn
g3_mut "a doppler read inside the seed item" g3_seed_read
g3_mut "remove the terminal anchor" g3_no_anchor
g3_mut "a doppler ZURL read in the colocated-inngest item" g3_colo_read
g3_mut "duplicate the anchor into runcmd item 1" g3_dup_anchor
g3_mut "soleur-doppler-download above the anchor" g3_dl_above
g3_mut "set -x in the seed item" g3_xtrace
g3_mut "doppler with a flag before the subcommand" g3_doppler_flag
g3_mut "set -e -x (xtrace as a second flag)" g3_setex
g3_mut "bash -x invocation" g3_bashx
g3_mut "set -o errexit -o xtrace" g3_xtrace_long

# G1 row 10 (static): the pull token appears exactly once in the template, on stdin.
tokn=$(grep -c '\${zot_pull_token}' "$SRC" || true)
tokform=$(grep -cE "printf '%s' '\\\$\{zot_pull_token\}' \| .*docker login [^|]*--password-stdin" "$SRC" || true)
if [ "$tokn" = 1 ] && [ "$tokform" = 1 ]; then ok "G1: \${zot_pull_token} appears exactly once, piped to docker login --password-stdin"
else no "G1: \${zot_pull_token} must appear exactly once, in the printf | docker login --password-stdin form (n=$tokn form=$tokform)"; fi
grep -qE "docker login[^|]*( -p[[:space:]]| --password[[:space:]=])" "$SRC" && no "G1: a docker login passes a password on argv (-p/--password)" \
  || ok "G1: no docker login passes a password on argv (-p/--password)"
# #8036 1d (was: "GHCR_TOKEN is unset right after its login"): the seed item holds no GHCR
# credential at all — no GHCR_USER/GHCR_TOKEN variable, no ${ghcr_read_*} splice, no GHCR login.
if grep -vE '^[[:space:]]*#' "$SRC" | _qgrep -E 'GHCR_(USER|TOKEN)|\$\{ghcr_read_(user|token)\}|docker login ghcr\.io'; then
  no "G1: a GHCR credential or login is back in cloud-init.yml (#8036 1d: zot is the only boot read path)"
else ok "G1: cloud-init.yml carries no GHCR credential, variable or login (#8036 1d)"; fi
# Exactly three later runcmd readers take the seed's resolved ref (pull, plugin seed, docker run).
[ "$(grep -cF '$(cat /run/soleur-image-ref' "$SRC")" = 3 ] \
  && ok "G1: exactly 3 later readers use /run/soleur-image-ref" || no "G1: /run/soleur-image-ref readers = $(grep -cF '$(cat /run/soleur-image-ref' "$SRC"), want 3"
# The tail redaction class must cover the pull token's alphabet and length.
if python3 - "$DIR/zot-registry.tf" <<'PY'
import re, sys
s = open(sys.argv[1]).read()
m = re.search(r'resource "random_password" "zot_pull" \{(.*?)\n\}', s, re.S)
assert m, "no random_password.zot_pull"
b = m.group(1)
L = int(re.search(r'^\s*length\s*=\s*(\d+)', b, re.M).group(1))
sp = re.search(r'^\s*special\s*=\s*(\w+)', b, re.M)
assert L >= 40 and sp and sp.group(1) == "false", (L, sp and sp.group(1))
PY
then ok "G1: random_password.zot_pull is >=40 chars and special=false (inside the redaction class)"
else no "G1: random_password.zot_pull shape left the [A-Za-z0-9_+/-]{40,} redaction class — widen the sed"; fi
# #6438/#8539 (CTO ruling): the web host carries the inngest networkd fallback byte-for-byte, and
# reloads networkd early in runcmd — before the seed item's first private-net use.
if python3 - "$SRC" "$INNGEST_CI" <<'PY'
import sys
w, i = open(sys.argv[1]).read(), open(sys.argv[2]).read()
head = "  - path: /etc/systemd/network/99-soleur-private-fallback.network\n"
def blk(t):
    a = t.index(head); return t[a:t.index("    permissions: '0644'\n", a)]
assert blk(w) == blk(i), "fallback .network differs from inngest"
r = w.index("  - networkctl reload || { printf 'gate=reload' > /run/soleur-stage-detail; _emit ")
assert r < w.index("# BEGIN host-script extraction"), "reload after the seed item"
PY
then ok "G2: web write_files carries the inngest networkd fallback byte-identical, reloaded before the seed item"
else no "G2: the networkd fallback must match cloud-init-inngest.yml and be reloaded before the seed item"; fi


# AC12 (deterministic): the merge cannot touch a live web host — user_data stays ignored.
if python3 - "$SRV" <<'PY'
import re, sys
s = open(sys.argv[1]).read()
m = re.search(r'resource "hcloud_server" "web" \{', s)
assert m
depth, i = 1, m.end()
while depth and i < len(s):
    depth += {"{": 1, "}": -1}.get(s[i], 0); i += 1
body = s[m.end():i]
ic = re.search(r"ignore_changes\s*=\s*\[([^\]]*)\]", body)
assert ic and re.search(r"(^|[\s,])user_data([\s,]|$)", ic.group(1))
PY
then ok "AC12: hcloud_server.web lifecycle.ignore_changes still lists user_data (merge mutates no live host)"
else no "AC12: hcloud_server.web must keep user_data in ignore_changes — a merge would replace web-1"; fi

# Server.tf feeds the two new template vars from the in-root resources (no new root variable).
grep -qE '^\s*zot_pull_user\s*=\s*local\.zot_pull_user\s*$' "$SRV" \
  && grep -qE '^\s*zot_pull_token\s*=\s*random_password\.zot_pull\.result\s*$' "$SRV" \
  && [ "$(grep -cE '^\s*zot_pull_(user|token)\s*=' "$SRV")" = 2 ] \
  && ok "server.tf bakes zot_pull_user/zot_pull_token from local + random_password (inngest-host.tf precedent)" \
  || no "server.tf must pass zot_pull_user = local.zot_pull_user and zot_pull_token = random_password.zot_pull.result to the web template"

# ── Render (terraform templatefile) ───────────────────────────────────────────────────────────
if ! command -v terraform >/dev/null 2>&1; then
  if [ -n "${CI:-}" ]; then
    no "terraform is absent under CI — the behavioural half of this suite cannot run (a silent skip would be vacuous)"
  else
    echo "[skip] terraform not installed locally — behavioural guards G1/G2 not executed"
  fi
  echo "=== cloud-init-web-zot-seed: $pass passed, $fail failed ==="
  [ "$fail" -eq 0 ]; exit $?
fi
mkdir -p "$WORK/tf"
ZTOK="dkryFMT07elszGNU18fmtAHOV29gnuBIPW3ahovC"   # 40 alnum, non-repeating (random_password.zot_pull shape)
[ "${#ZTOK}" = 40 ] || harness "ZTOK must be 40 chars"
export ZOT_PW_EXP="$ZTOK"
# token_leak <files...> : any 12-char slice of the token in any file is a leak (a tail cut can
# leave less than the 40-char redaction pattern — which is why redaction must precede the cut).
token_leak() { local k; for ((k = 0; k <= ${#ZTOK} - 12; k++)); do grep -qF -- "${ZTOK:k:12}" "$@" 2>/dev/null && return 0; done; return 1; }
DIGEST="sha256:$(printf 'ab%.0s' $(seq 1 32))"
PINNED="ghcr.io/jikig-ai/soleur-web-platform:v9.9.9@$DIGEST"
DSN="https://pubkey123@o1.ingest.de.sentry.io/4242"
render() {  # <out> <image_name> <registry_endpoint> <private_ip> <colocate>
  printf 'templatefile("%s", { image_name="%s", fail2ban_sshd_local_b64="x", host_scripts_content_hash="h", tunnel_token="tt", webhook_deploy_secret="w", doppler_token="d", sentry_dsn="%s", resend_api_key="r", ci_ssh_public_key_openssh="k", workspaces_volume_id="v", registry_endpoint="%s", web_colocate_inngest=%s, web_tunnel_connector=false, host_name="soleur-web-2", private_ip="%s", web_probes_token="t", expected_ip="%s", web_host_key="web-2", zot_probe_repo="zr", betterstack_ingest_url="bs", soleur_doppler_token_env_b64="RE9QUExFUl9UT0tFTj1k", zot_pull_user="zot-pull", zot_pull_token="%s" })\n' \
    "$SRC" "$2" "$DSN" "$3" "$5" "$4" "$4" "$ZTOK" | terraform -chdir="$WORK/tf" console > "$1.raw" 2> "$1.err" \
    || harness "terraform render failed: $(head -c 400 "$1.err")"
  python3 - "$1.raw" "$1" <<'PY' || harness "render is not valid YAML"
import sys, yaml
L = open(sys.argv[1]).read().splitlines()
body = "\n".join(L[1:-1]) if (L and L[0].lstrip().startswith("<<")) else "\n".join(L)
yaml.safe_load(body)
open(sys.argv[2], "w").write(body + "\n")
PY
}
# extract <rendered> <sandbox-root> <out-script>: item1 + daemon.json item + seed item, cut at
# STAGE=extract, paths rewritten into the sandbox. Refuses (exit 2) on any missing construct.
extract() {
  python3 - "$1" "$2" "$3" <<'PY' || harness "extraction failed"
import re, sys, yaml
doc = yaml.safe_load(open(sys.argv[1]))
sb, out = sys.argv[2], sys.argv[3]
items = [i for i in doc["runcmd"] if isinstance(i, str)]
def one(pred, name):
    hits = [i for i in items if pred(i)]
    if len(hits) != 1:
        print("extract: %s matched %d items" % (name, len(hits)), file=sys.stderr); sys.exit(2)
    return hits[0]
item1 = one(lambda i: "STAGE=runcmd_early" in i, "item1")
daemon = one(lambda i: "/etc/docker/daemon.json" in i and "insecure-registries" in i, "daemon")
seed = one(lambda i: "HOST_SCRIPTS_HASH=" in i, "seed")
# All items run in ONE /bin/sh in list order; the harness joins only three of them, so the order
# it cannot execute is asserted instead: daemon.json written, docker restarted, THEN the seed.
if "systemctl restart docker" not in items or not (items.index(daemon) < items.index("systemctl restart docker") < items.index(seed)):
    print("extract: runcmd order must be daemon.json < systemctl restart docker < seed", file=sys.stderr); sys.exit(2)
for need in ("_emit()", "on_err()", "trap on_err EXIT"):
    if need not in item1:
        print("extract: item1 lacks " + need, file=sys.stderr); sys.exit(2)
cut = seed.find("\nSTAGE=extract\n")
if cut < 0:
    print("extract: no STAGE=extract cut point", file=sys.stderr); sys.exit(2)
seed = seed[:cut] + "\ntrap - EXIT\necho __CUT_REACHED__\nexit 0\necho __SENTINEL_AFTER_CUT__\n"
script = item1 + "\n" + daemon + "\n" + seed
for p in ("/run/", "/etc/default/", "/etc/docker/"):
    script = script.replace(p, sb + p)
resid = re.findall(r"(?:^|[^A-Za-z0-9_])/(?:run|etc/default|etc/docker)/", script, re.M)
if resid:
    print("extract: residual host paths after rewrite: %r" % resid[:3], file=sys.stderr); sys.exit(2)
open(out, "w").write(script)
PY
}

# ── Stubs ─────────────────────────────────────────────────────────────────────────────────────
BIN="$WORK/bin"; mkdir -p "$BIN"
IPC="$WORK/ipcalls"   # the ip stub's call counter; truncated by every run_seed
cat > "$BIN/docker" <<'STUB'
#!/bin/sh
# Stateful: a pull from registry R fails `unauthorized` unless `login R` succeeded earlier.
printf 'docker %s\n' "$*" >> "$CALLS"
reg() { case "$1" in ghcr.io/*) echo ghcr.io ;; *) echo "${1%%/*}" ;; esac; }
case "$1" in
  info|rm) exit 0 ;;
  login)
    R="$2"; pw=$(cat)
    printf 'login %s\n' "$R" >> "$ORDER"
    case "$R" in ghcr.io) want="${GHCR_LOGIN:-fail}"; eu=ghu; ep=ght ;; *) want="${ZOT_LOGIN:-ok}"; eu=zot-pull; ep="$ZOT_PW_EXP" ;; esac
    # The credential itself is checked: a login that drops -u, names the wrong user or pipes the
    # wrong secret fails exactly as zot/GHCR would, whatever the scenario wanted.
    { [ "$3" = "-u" ] && [ "$4" = "$eu" ] && [ "$pw" = "$ep" ]; } || want=fail
    if [ "$want" = ok ]; then echo "$R" >> "$STATE/logged"; echo "Login Succeeded"; exit 0; fi
    echo "Error response from daemon: login attempt failed: ${LOGIN_ERR:-unauthorized: incorrect username or password} pw=$pw${LOGIN_SFX:-}" >&2
    exit 1 ;;
  pull)
    R=$(reg "$2")
    printf 'pull %s\n' "$2" >> "$ORDER"
    if [ "${STATELESS:-0}" != 1 ] && ! grep -qxF "$R" "$STATE/logged" 2>/dev/null; then
      echo "Error response from daemon: unauthorized: authentication required" >&2; exit 1
    fi
    case "$R" in ghcr.io) want="${GHCR_PULL:-ok}"; rc="${GHCR_PULL_RC:-1}"; err="${GHCR_PULL_ERR:-denied}" ;;
      *) want="${ZOT_PULL:-ok}"; rc="${ZOT_PULL_RC:-1}"; err="${ZOT_PULL_ERR:-manifest unknown}" ;; esac
    [ "$want" = ok ] && { echo "Status: Downloaded"; exit 0; }
    echo "Error response from daemon: $err" >&2; exit "$rc" ;;
esac
exit 0
STUB
cat > "$BIN/sleep" <<'STUB'
#!/bin/sh
printf '%s\n' "$1" >> "$SLEEP_LOG"
exit 0
STUB
cat > "$BIN/timeout" <<'STUB'
#!/bin/sh
printf 'timeout %s %s\n' "$1" "$2" >> "$CALLS"
shift
exec "$@"
STUB
cat > "$BIN/doppler" <<'STUB'
#!/bin/sh
printf 'doppler %s\n' "$*" >> "$DOPPLER_LOG"
[ "${DOPPLER_MODE:-tokenless}" = answer ] && { echo 10.0.1.30:5000; exit 0; }
echo "Doppler Error: you must provide a token" >&2; exit 1
STUB
cat > "$BIN/curl" <<'STUB'
#!/bin/sh
case "$*" in *"/v2/"*) exit "${CURL_V2_RC:-7}" ;; esac
while [ $# -gt 0 ]; do [ "$1" = "-d" ] && { printf '%s\n' "$2" >> "$POST_LOG"; shift; }; shift; done
exit 0
STUB
chmod +x "$BIN"/*
make_ip() {  # <mode> [addr] [after] : present | converging | never | failing
  case "$1" in
    failing) printf '#!/bin/sh\nexit 1\n' > "$BIN/ip" ;;
    *) { echo '#!/bin/sh'
         echo "printf x >> '$IPC'"   # the call counter, baked as an absolute path under WORK
         echo 'if [ "$*" != "-4 -o addr show" ]; then echo "stub ip: unexpected argv: $*" >&2; exit 2; fi'
         echo 'echo "1: lo    inet 127.0.0.1/8 scope host lo"'
         echo 'echo "2: eth0    inet 203.0.113.9/32 scope global eth0"'
         case "$1" in
           present) echo "echo 'ip present' >> \"\$ORDER\"; echo \"3: enp7s0    inet $2/32 scope global enp7s0\"" ;;
           converging) echo "n=\$(wc -c < '$IPC' | tr -d ' ')"
                       echo "if [ \"\$n\" -gt $3 ]; then echo 'ip present' >> \"\$ORDER\"; echo \"3: enp7s0    inet $2/32 scope global enp7s0\"; else echo 'ip absent' >> \"\$ORDER\"; fi" ;;
           never) echo "echo 'ip absent' >> \"\$ORDER\"" ;;
         esac
         echo 'exit 0'
       } > "$BIN/ip" ;;
  esac
  chmod +x "$BIN/ip"
}

# run_seed <script> : executes under the stubs; sets RC and per-run log paths (L_*). Any
# pre-set env (ZOT_LOGIN, GHCR_LOGIN, ZOT_PULL, …) is passed through.
run_seed() {
  local sc="$1" r="$WORK/run.$RANDOM$RANDOM"
  mkdir -p "$r/state"
  local sb; sb="$(dirname "$sc")"
  rm -rf "${sb:?}/run" "${sb:?}/etc"; mkdir -p "$sb/run" "$sb/etc/default" "$sb/etc/docker"
  L_CALLS="$r/calls"; L_ORDER="$r/order"; L_SLEEP="$r/sleep"; L_POST="$r/post"; L_DOP="$r/doppler"
  L_IPC="$IPC"; L_OUT="$r/out"; L_SB="$sb"
  : > "$L_CALLS"; : > "$L_ORDER"; : > "$L_SLEEP"; : > "$L_POST"; : > "$L_DOP"; : > "$L_IPC"
  RC=0
  CALLS="$L_CALLS" ORDER="$L_ORDER" SLEEP_LOG="$L_SLEEP" POST_LOG="$L_POST" DOPPLER_LOG="$L_DOP" \
    STATE="$r/state" PATH="$BIN:/usr/bin:/bin" \
    /usr/bin/timeout 20 "$SHELL_BIN" "$sc" > "$L_OUT" 2>&1 || RC=$?
  [ "$RC" = 124 ] && harness "seed item ran past the 20 s harness bound (a clock-based wait, or a hang)"
  grep -q '__SENTINEL_AFTER_CUT__' "$L_OUT" && harness "execution passed the STAGE=extract cut"
  return 0
}
# post_field <stage> <field> : the named tag of the LAST Sentry POST with that stage ("" if none)
post_field() {
  python3 - "$L_POST" "$1" "$2" <<'PY'
import json, sys
v = ""
for line in open(sys.argv[1]):
    try: b = json.loads(line)
    except Exception: continue
    t = b.get("tags", {})
    if t.get("stage") == sys.argv[2]:
        v = t.get(sys.argv[3], b.get(sys.argv[3], ""))
print(v)
PY
}
post_count() { python3 - "$L_POST" "$1" <<'PY'
import json, sys
n = 0
for line in open(sys.argv[1]):
    try: n += json.loads(line).get("tags", {}).get("stage") == sys.argv[2]
    except Exception: pass
print(n)
PY
}
stages_emitted() { python3 - "$L_POST" <<'PY'
import json, sys
for line in open(sys.argv[1]):
    try: print(json.loads(line).get("tags", {}).get("stage", ""))
    except Exception: pass
PY
}
first_pull() { grep -m1 '^pull ' "$L_ORDER" | cut -d' ' -f2- || true; }
# every docker login/pull is the immediate child of `timeout N docker` with N at its bound
timeouts_ok() { python3 - "$L_CALLS" <<'PY'
import sys
L = open(sys.argv[1]).read().splitlines()
bad = [l for k, l in enumerate(L) if l.startswith(("docker login", "docker pull"))
       and (k == 0 or L[k - 1] != ("timeout 60 docker" if l.startswith("docker login") else "timeout 180 docker"))]
sys.exit(1 if bad or not any(l.startswith("docker pull") for l in L) else 0)
PY
}
sleeps2() { grep -cx 2 "$L_SLEEP" || true; }

# ── Renders ───────────────────────────────────────────────────────────────────────────────────
mk() {  # <name> <image> <endpoint> <private_ip> <colocate>
  mkdir -p "$WORK/$1/sb"
  render "$WORK/$1/r.yml" "$2" "$3" "$4" "$5"
  extract "$WORK/$1/r.yml" "$WORK/$1/sb" "$WORK/$1/sb/seed.sh"
}
mk def "$PINNED" 10.0.1.30:5000 10.0.1.11 false
mk tag "ghcr.io/jikig-ai/soleur-web-platform:latest" 10.0.1.30:5000 10.0.1.11 false
mk noip "$PINNED" 10.0.1.30:5000 "" false
mk ep99 "$PINNED" 10.0.1.99:5000 10.0.1.77 false
mk colo "$PINNED" 10.0.1.30:5000 10.0.1.11 true
ok "render+extract: 5 renders, item1+daemon+seed joined, zero residual host paths"
DEF="$WORK/def/sb/seed.sh"
ZREF="10.0.1.30:5000/jikig-ai/soleur-web-platform:v9.9.9@$DIGEST"
[ "$(grep -cF "$ZTOK" "$WORK/def/r.yml")" = 1 ] && ok "AC1: the rendered pull token appears exactly once" \
  || no "AC1: the rendered pull token must appear exactly once (got $(grep -cF "$ZTOK" "$WORK/def/r.yml"))"
[ "$(census "$WORK/colo/r.yml")" = 0 ] && ok "G3: colocated-inngest render has no doppler call above the anchor" \
  || no "G3: colocated-inngest render census=$(census "$WORK/colo/r.yml")"

# ── G1 predicates (return 0 = property holds) ─────────────────────────────────────────────────
# happy: digest pin, NIC present, zot ok → zot served, no doppler, no GHCR login or pull.
g1_happy() {
  make_ip present 10.0.1.11
  ZOT_LOGIN=ok ZOT_PULL=ok run_seed "$1"
  local why=""
  [ "$RC" = 0 ] || why="$why rc=$RC"
  grep -q __CUT_REACHED__ "$L_OUT" || why="$why cut-not-reached"
  [ "$(first_pull)" = "$ZREF" ] || why="$why first-pull=$(first_pull)"
  [ -s "$L_DOP" ] && why="$why doppler-spawned"
  [ "$(cat "$L_SB/run/soleur-image-ref" 2>/dev/null)" = "$ZREF" ] || why="$why image-ref-file"
  [ "$(post_count app_zot)" = 1 ] || why="$why app_zot-count=$(post_count app_zot)"
  local d; d=$(post_field app_zot detail)
  case "$d" in "zot_login=ok nic=ready:0 zot=[login=ok,n=1,cause=none]") ;; *) why="$why detail=[$d]" ;; esac
  [ "$(post_field app_zot host_name)" = soleur-web-2 ] || why="$why host_name"
  timeouts_ok || why="$why unbounded-docker-call"
  local f; for f in soleur-stage-detail soleur-pull.log soleur-zot-login.log; do
    [ "$(stat -c %a "$L_SB/run/$f" 2>/dev/null)" = 600 ] || why="$why mode-$f"; done
  grep -q '^login ghcr\.io' "$L_ORDER" && why="$why ghcr-login"
  [ "$(post_count app_ghcr_served)$(post_count app_ghcr_fallback)" = 00 ] || why="$why app_ghcr-emitted"
  grep -q 'insecure-registries' "$L_SB/etc/docker/daemon.json" 2>/dev/null || why="$why no-daemon.json"
  # order: zot login precedes the first pull (independent of the stateful stub — H4)
  local li pi; li=$(grep -n "^login 10.0.1.30:5000" "$L_ORDER" | head -1 | cut -d: -f1)
  pi=$(grep -n '^pull ' "$L_ORDER" | head -1 | cut -d: -f1)
  { [ -n "$li" ] && [ -n "$pi" ] && [ "$li" -lt "$pi" ]; } || why="$why login-not-before-pull"
  grep -q "^pull ghcr.io/" "$L_ORDER" && why="$why ghcr-pulled"
  token_leak "$L_POST" "$L_SB/run/soleur-stage-detail" "$L_OUT" && why="$why token-leak"
  G1WHY="$why"; [ -z "$why" ]
}
# zot miss: the zot pull fails (160-char error) → fatal stage=pull naming the zot leg, no GHCR leg.
LONGERR="manifest unknown: $(printf 'e%.0s' $(seq 1 142))"
g1_failboth() {
  make_ip present 10.0.1.11
  ZOT_LOGIN=ok ZOT_PULL=fail ZOT_PULL_ERR="$LONGERR" run_seed "$1"
  local why="" d
  [ "$RC" != 0 ] || why="$why rc=0"
  grep -q "^pull ghcr.io/" "$L_ORDER" && why="$why ghcr-pulled"
  d=$(post_field pull detail)
  [ "$(post_field pull message)" = "soleur-hostscript-seed failed" ] || why="$why no-fatal"
  # The seed-block fatal pages at level=fatal (the web_terminal_boot_fatal rule keys on it); an
  # on_err downgraded to error/warning would still POST, so the level is pinned, not the POST.
  [ "$(post_field pull level)" = fatal ] || why="$why level=[$(post_field pull level)]"
  [ "$(post_field pull host_name)" = soleur-web-2 ] || why="$why host_name"
  [ "${#d}" -le 200 ] || why="$why detail>200"
  timeouts_ok || why="$why unbounded-docker-call"
  case "$d" in "nic=ready:0 zot=[login=ok,n=3,cause=manifest] pull_err: "*) ;;
    *) why="$why detail=[$d]" ;; esac
  G1WHY="$why"; [ -z "$why" ]
}
# leak: a failing zot login whose (stub) error echoes the token — no 16-char slice of it may
# reach a Sentry body or the detail file. A partial slice counts: `tail -c` can cut the token
# below the 40-char redaction pattern, which is why redaction must run BEFORE the tail.
LOGIN_SFX=" $(printf '. %.0s' $(seq 1 39))"   # 79 chars: the 100-byte tail cuts INTO the token
g1_leak() {
  make_ip present 10.0.1.11
  ZOT_LOGIN=fail LOGIN_SFX="$LOGIN_SFX" run_seed "$1"
  local why=""
  [ "$RC" != 0 ] || why="$why rc=0"
  token_leak "$L_POST" "$L_SB/run/soleur-stage-detail" "$L_OUT" && why="$why token-leak"
  [ "$(grep -c '^login 10.0.1.30:5000$' "$L_ORDER")" = 3 ] || why="$why zot-logins=$(grep -c '^login 10.0.1.30:5000$' "$L_ORDER")"
  grep -q '^pull 10\.0\.1\.30:5000/' "$L_ORDER" && why="$why pulled-after-failed-login"
  [ "$(grep -cx 5 "$L_SLEEP")" = 2 ] || why="$why sleep5=$(grep -cx 5 "$L_SLEEP")"
  case "$(post_field pull detail)" in "nic=ready:0 zot=[login=fail,n=0,cause=auth] pull_err: "*) ;;
    *) why="$why detail=[$(post_field pull detail)]" ;; esac
  G1WHY="$why"; [ -z "$why" ]
}
# no fallback (INVERTED by #8036 1d; was the GHCR flip): a zot miss is terminal even when the
# stub would ACCEPT a GHCR login and serve the GHCR pull — no GHCR login, no GHCR pull, no
# app_ghcr_* beacon, no app_zot beacon, and a fatal stage=pull that ends the item.
g1_flip() {
  make_ip present 10.0.1.11
  ZOT_LOGIN=ok GHCR_LOGIN=ok ZOT_PULL=fail GHCR_PULL=ok run_seed "$1"
  local why=""
  [ "$RC" != 0 ] || why="$why rc=0"
  grep -q __CUT_REACHED__ "$L_OUT" && why="$why reached-extract"
  grep -q '^login ghcr\.io' "$L_ORDER" && why="$why ghcr-login"
  grep -q "^pull ghcr.io/" "$L_ORDER" && why="$why ghcr-pull"
  [ "$(post_count app_ghcr_fallback)$(post_count app_ghcr_served)$(post_count app_zot)" = 000 ] \
    || why="$why beacons=$(post_count app_ghcr_fallback)/$(post_count app_ghcr_served)/$(post_count app_zot)"
  [ "$(post_field pull message)" = "soleur-hostscript-seed failed" ] || why="$why no-fatal"
  [ -e "$L_SB/run/soleur-image-ref" ] && why="$why image-ref-written"
  G1WHY="$why"; [ -z "$why" ]
}
# causes: every zot failure text classifies to its cause (and a timeout stops the retries)
g1_causes() {
  local pair want rest err prc d why=""
  make_ip present 10.0.1.11
  for pair in "auth:unauthorized: authentication required:1" "auth:denied: requested access to the resource is denied:1" \
              "manifest:manifest unknown: manifest unknown:1" "unreach:dial tcp 10.0.1.30:5000: connect: no route to host:1" \
              "other:something new:1" "timeout:x:124"; do
    want="${pair%%:*}"; rest="${pair#*:}"; err="${rest%:*}"; prc="${rest##*:}"
    ZOT_LOGIN=ok ZOT_PULL=fail ZOT_PULL_ERR="$err" ZOT_PULL_RC="$prc" run_seed "$1"
    d=$(post_field pull detail)
    case "$want:$d" in timeout:*"n=1,cause=timeout]"*) ;; timeout:*) why="$why [$err]->$d" ;;
      *:*"n=3,cause=$want]"*) ;; *) why="$why [$err]->$d" ;; esac
  done
  G1WHY="$why"; [ -z "$why" ]
}
# tag-only ref never reaches plain-HTTP zot, and (#8036 1d) is pulled from nowhere else either:
# it fails loud with cause=unpinned and no pull at all.
g1_tag() {
  make_ip present 10.0.1.11
  ZOT_LOGIN=ok run_seed "$1"
  local why="" d
  grep -q '^pull 10\.0\.1\.30:5000/' "$L_ORDER" && why="$why tag-pulled-from-zot"
  grep -q '^pull ' "$L_ORDER" && why="$why pulled=$(grep -m1 '^pull ' "$L_ORDER")"
  [ "$RC" != 0 ] || why="$why rc=0"
  d=$(post_field pull detail)
  case "$d" in "nic=ready:0 zot=[login=ok,n=0,cause=unpinned] pull_err: "*) ;; *) why="$why detail=[$d]" ;; esac
  G1WHY="$why"; [ -z "$why" ]
}

g1_happy "$DEF" && ok "AC1/G1: digest pin → first pull is the baked zot ref, no doppler, no GHCR login, image-ref file = zot ref, app_zot detail zot_login=ok nic=ready:0 zot=[…], host_name tagged, login precedes pull, token never recorded" \
  || no "AC1/G1 happy path:$G1WHY"
grep -q __CUT_REACHED__ "$L_OUT" && ! grep -q __SENTINEL_AFTER_CUT__ "$L_OUT" \
  && ok "AC1: execution stops at the STAGE=extract cut (sentinel after it never prints)" || no "AC1: cut sentinel"
g1_failboth "$DEF" && ok "AC2/G1: zot miss → fatal stage=pull at level=fatal, ≤200-char detail, fixed fields first (zot leg only), no GHCR pull" \
  || no "AC2/G1 fail-both:$G1WHY"
g1_leak "$DEF" && ok "AC2/G1: a failing login that echoes the token leaks no slice of it into Sentry or the detail file" \
  || no "AC2/G1 leak:$G1WHY"
g1_flip "$DEF" && ok "AC2/G1: zot miss with a GHCR that WOULD answer → still terminal: no GHCR login/pull, no beacon, fatal stage=pull (#8036 1d)" \
  || no "AC2/G1 flip:$G1WHY"
g1_tag "$WORK/tag/sb/seed.sh" && ok "G1/6b: a tag-only ref is never pulled (not from plain-HTTP zot, not from GHCR); fatal names cause=unpinned" \
  || no "G1 tag-only:$G1WHY"
g1_causes "$DEF" && ok "AC2: auth/denied/manifest/unreach/other/timeout each classify; a timeout (rc 124) stops the zot retries at n=1" \
  || no "AC2 causes:$G1WHY"
# Variants (edits of the rendered item, not mutations): empty endpoint, a digest-pinned ref that is
# not on ghcr.io. (The empty-GHCR-creds variant retired with the GHCR leg, #8036 1d; its slot is
# the rendered-item residual row below.)
variant() { local m="$WORK/def/sb/var.sh"; cp "$DEF" "$m"; python3 "$WORK/muts.py" "$m" "$1" || harness "variant did not land: $1"; make_ip present 10.0.1.11; ZOT_LOGIN=ok run_seed "$m"; rm -f "$m"; }
if _qgrep -E 'ghcr_login|GHCR_|soleur-ghcr|"\$GL"|GP=' "$DEF"; then no "G1: the RENDERED seed item still carries a GHCR login leg (ghcr_login/GHCR_*/GL/GP)"
else ok "G1: the rendered seed item carries no GHCR login leg (no ghcr_login stage, GHCR_* var, GL/GP field, soleur-ghcr-* log)"; fi
variant v_zep_empty
{ ! grep -qx 'login ' "$L_ORDER" && ! grep -q '^pull ' "$L_ORDER" && case "$(post_field pull detail)" in *"zot=[login=fail,n=0,"*) true ;; *) false ;; esac; } \
  && ok "G1: an empty endpoint never reaches docker login (no default-index login with the zot token)" \
  || no "G1: empty endpoint: order=[$(tr '\n' ' ' < "$L_ORDER")] detail=[$(post_field pull detail)]"
variant v_nonghcr
{ ! grep -q '^pull 10\.0\.1\.30:5000/' "$L_ORDER" && case "$(post_field pull detail)" in *cause=unpinned*) true ;; *) false ;; esac; } \
  && ok "G1: a digest-pinned ref not on ghcr.io is never rewritten to zot (cause=unpinned)" \
  || no "G1: non-ghcr digest ref: detail=[$(post_field pull detail)]"
# G1 extract-order: moving daemon.json after the seed must be a harness refusal, not a green run.
python3 - "$WORK/def/r.yml" "$WORK/g1o.yml" <<'PY'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
rc = d["runcmd"]
k = next(i for i, x in enumerate(rc) if isinstance(x, str) and "/etc/docker/daemon.json" in x)
rc.append(rc.pop(k))
yaml.safe_dump(d, open(sys.argv[2], "w"))
PY
mkdir -p "$WORK/g1o"
( extract "$WORK/g1o.yml" "$WORK/g1o" "$WORK/g1o/s.sh" ) >/dev/null 2>&1 && no "G1: daemon.json moved after the seed item still extracted" \
  || ok "G1: daemon.json after the seed item (docker unaware of the plain-HTTP registry) is refused by order"
# H2 (non-canonical endpoint): keys on the baked endpoint, not the literal.
make_ip present 10.0.1.77
ZOT_LOGIN=ok run_seed "$WORK/ep99/sb/seed.sh"
[ "$(first_pull)" = "10.0.1.99:5000/jikig-ai/soleur-web-platform:v9.9.9@$DIGEST" ] && [ "$RC" = 0 ] \
  && ok "G1 H2: a non-canonical baked endpoint (10.0.1.99:5000) is the one pulled" \
  || no "G1 H2: endpoint 10.0.1.99 render pulled [$(first_pull)] rc=$RC"
# H3 (must-PASS): the (only) leg failing → non-zero AND the detail names the zot leg and no other.
ZOT_LOGIN=fail ZOT_PULL=fail run_seed "$DEF"
d=$(post_field pull detail)
case "$d" in *ghcr*) no "G1 H3: the fatal detail still names a GHCR leg: [$d]" ;;
  *"zot=[login=fail"*) [ "$RC" != 0 ] && ok "G1 H3: a failing zot leg exits non-zero and the detail names the zot leg (no GHCR leg)" || no "G1 H3: rc=0" ;;
  *) no "G1 H3: detail must name the zot leg, got [$d]" ;; esac

# ── G2 predicates ─────────────────────────────────────────────────────────────────────────────
g2_ready0() { make_ip present 10.0.1.11; run_seed "$1"
  local why=""; [ "$(sleeps2)" = 0 ] || why="$why sleeps=$(sleeps2)"
  stages_emitted | _qgrep '^private_nic_' && why="$why nic-emit-on-ready"
  case "$(post_field app_zot detail)" in *nic=ready:0*) ;; *) why="$why detail" ;; esac
  G2WHY="$why"; [ -z "$why" ]; }
g2_conv() { make_ip converging 10.0.1.11 10; run_seed "$1"
  local why=""; [ "$(sleeps2)" = 10 ] || why="$why sleeps=$(sleeps2)"
  stages_emitted | _qgrep '^private_nic_' && why="$why nic-emit-on-ready"
  case "$(post_field app_zot detail)" in *nic=ready:20*) ;; *) why="$why detail=[$(post_field app_zot detail)]" ;; esac
  G2WHY="$why"; [ -z "$why" ]; }
g2_never() { make_ip never; ZOT_LOGIN=fail LOGIN_ERR="dial tcp 10.0.1.30:5000: connect: no route to host" STATELESS=1 ZOT_PULL=fail ZOT_PULL_ERR="dial tcp 10.0.1.30:5000: connect: no route to host" run_seed "$1"
  local why=""; [ "$(sleeps2)" = 75 ] || why="$why sleeps=$(sleeps2)"
  [ "$(post_count private_nic_timeout)" = 1 ] || why="$why timeout-emits=$(post_count private_nic_timeout)"
  [ "$(post_count private_nic_probe_fault)" = 0 ] || why="$why probe_fault-too"
  grep -q '^login ' "$L_ORDER" || why="$why item-did-not-continue"
  case "$(post_field pull detail)" in nic=timeout:150*cause=unreach*) ;; *) why="$why fatal=[$(post_field pull detail)]" ;; esac
  G2WHY="$why"; [ -z "$why" ]; }
g2_fail() { make_ip failing; run_seed "$1"
  local why=""; [ "$(post_count private_nic_probe_fault)" = 1 ] || why="$why probe_fault=$(post_count private_nic_probe_fault)"
  [ "$(post_count private_nic_timeout)" = 0 ] || why="$why timeout-too"
  G2WHY="$why"; [ -z "$why" ]; }
g2_noip() { make_ip present 10.0.1.11; run_seed "$1"
  local why=""; [ "$(post_count private_nic_probe_fault)" = 1 ] || why="$why probe_fault=$(post_count private_nic_probe_fault)"
  G2WHY="$why"; [ -z "$why" ]; }
# every private_nic_* stage the item emits is routed by web_private_nic_boot_gate
g2_routed() { local s routed
  routed=$(awk '/resource "sentry_alert" "web_private_nic_boot_gate"/,/^}/' "$ALERTS" | grep -oE 'value = "private_nic_[a-z_]+"' | cut -d'"' -f2)
  [ -n "$routed" ] || harness "could not read web_private_nic_boot_gate stages"
  for fx in never failing; do make_ip "$fx"; ZOT_PULL=fail run_seed "$1"
    for s in $(stages_emitted | grep '^private_nic_' || true); do
      printf '%s\n' "$routed" | _qgrep -xF "$s" || { G2WHY=" unrouted=$s"; return 1; }
    done
  done
  for s in $(grep -vE '^[[:space:]]*#' "$SRC" | grep -oE 'private_nic_[a-z_]+' | sort -u); do
    printf '%s\n' "$routed" | _qgrep -xF "$s" || { G2WHY=" unrouted-literal=$s"; return 1; }
  done; G2WHY=""; }
g2_order() {  # the wait precedes the zot login: the login must come after the address appeared
  make_ip converging 10.0.1.11 3; run_seed "$1"
  local li pi; li=$(grep -n '^login 10.0.1.30' "$L_ORDER" | head -1 | cut -d: -f1)
  pi=$(grep -n '^ip present' "$L_ORDER" | head -1 | cut -d: -f1)
  [ -n "$li" ] && [ -n "$pi" ] && [ "$pi" -lt "$li" ]; }

g2_ready0 "$DEF" && ok "AC3/G2: address present → 0 sleeps, no private_nic_* emit, nic=ready:0" || no "AC3 ready:$G2WHY"
g2_conv "$DEF" && ok "AC3/G2: address on poll 10 → 10 sleeps, nic=ready:20, no emit" || no "AC3 converging:$G2WHY"
g2_never "$DEF" && ok "AC3/G2: never present → exactly 75×sleep 2, one private_nic_timeout, item continues, fatal nic=timeout:150 cause=unreach" || no "AC3 never:$G2WHY"
g2_fail "$DEF" && ok "AC3/G2: ip failing every call → one private_nic_probe_fault" || no "AC3 ip-failing:$G2WHY"
g2_noip "$WORK/noip/sb/seed.sh" && ok "AC3/G2: empty private_ip render → private_nic_probe_fault (grep -qwF '' matches everything)" || no "AC3 empty-ip:$G2WHY"
g2_routed "$DEF" && ok "G2: every private_nic_* stage emitted is routed by web_private_nic_boot_gate" || no "G2 routing:$G2WHY"
g2_order "$DEF" && ok "G2: the NIC wait precedes the zot login" || no "G2: zot login ran before the NIC wait"
make_ip present 10.0.1.77; run_seed "$WORK/ep99/sb/seed.sh"
[ "$(sleeps2)" = 0 ] && [ "$(post_count private_nic_timeout)" = 0 ] && ok "G2 H3: the wait keys on the rendered address (10.0.1.77), not a literal" \
  || no "G2 H3: rendered private_ip 10.0.1.77 not honoured"

# ── Mutation section (pristine copy per case; each must land; each must turn RED) ─────────────
mrow() {  # <label> <predicate> <key> [sandbox, default def]
  local src="$WORK/${4:-def}/sb/seed.sh" m="$WORK/${4:-def}/sb/mut.sh"
  cp "$src" "$m"
  python3 "$WORK/muts.py" "$m" "$3" || harness "mutation did not land: $1"
  G1WHY=""; G2WHY=""
  if "$2" "$m" 2>/dev/null; then no "mutation SURVIVED: $1"; else ok "mutation RED: $1 —${G1WHY}${G2WHY}"; fi
  rm -f "$m"
}
mrow "G1.1 endpoint read from doppler (tokenless)" g1_happy g1_doppler_ep
mrow "G1.2 a 3 s /v2/ gate in front of the zot ref" g1_happy g1_v2_gate
mrow "G1.4 a later REF=IMAGE_REF reassignment before the pull" g1_happy g1_reassign
mrow "G1.5 a GHCR pull re-added after the zot miss (the retired fallback)" g1_flip g1_ghcr_pull_back
mrow "G1.6 tag-only refs rewritten to zot" g1_tag g1_tag_to_zot tag
mrow "G1.7 fatal detail without the zot leg" g1_failboth g1_no_zot_leg
mrow "G1.8 zot login moved after the pull (reorder)" g1_happy g1_login_after_pull
mrow "G1.9 tails written without redaction" g1_leak g1_no_redact
mrow "G1.11 free-text tail before the fixed fields" g1_failboth g1_tail_first
mrow "G1.12 tail cut BEFORE redaction" g1_leak g1_tail_before_redact
mrow "G1.13 zot login drops -u" g1_happy g1_login_no_user
mrow "G1.14 timeout wrapper dropped from the zot login" g1_happy g1_login_unbounded
mrow "G1.15 zot pulls run after a failed login" g1_leak g1_pull_ungated
mrow "G1.16 zot login retries cut to 1" g1_leak g1_login_once
mrow "G1.17 a GHCR login re-added to the seed item" g1_happy g1_ghcr_login_back
mrow "G1.18 unreach cause arm dropped" g1_causes g1_drop_unreach
mrow "G1.19 a timeout does not stop the zot retries" g1_causes g1_timeout_retries
mrow "G1.20 /run pre-create (0600) dropped" g1_happy g1_no_install
mrow "G1.21 on_err's fatal emit downgraded to level=error" g1_failboth g1_err_level
# G1.3 guard's own dispatch: an extractor that matches no seed item must be a HARNESS failure.
python3 - "$WORK/def/r.yml" "$WORK/g13.yml" <<'PY'
import sys
s = open(sys.argv[1]).read().replace("HOST_SCRIPTS_HASH=", "HOST_SCRIPT_HASH_RENAMED=")
open(sys.argv[2], "w").write(s)
PY
mkdir -p "$WORK/g13"
( extract "$WORK/g13.yml" "$WORK/g13" "$WORK/g13/s.sh" ) >/dev/null 2>&1 && no "G1.3: an extractor matching no seed item passed" \
  || ok "G1.3: an extractor that matches no seed item is a harness failure, never 0 items executed"
# G1 H1: a doppler that ANSWERS must still red G1.1 through the spawn log, not the pull outcome.
m="$WORK/def/sb/h1.sh"; cp "$DEF" "$m"
python3 "$WORK/muts.py" "$m" g1_answering_doppler || harness "G1 H1 landing"
export DOPPLER_MODE=answer
if g1_happy "$m"; then no "G1 H1: an answering doppler hid the doppler read"
else case "$G1WHY" in *doppler-spawned*) ok "G1 H1: an answering doppler still reds via the spawn log";; *) no "G1 H1: red for the wrong reason:$G1WHY";; esac; fi
unset DOPPLER_MODE; rm -f "$m"
# G1 H4: a stateless docker stub must still red the reorder through the order assertion.
m="$WORK/def/sb/h4.sh"; cp "$DEF" "$m"
python3 "$WORK/muts.py" "$m" g1_login_after_pull || harness "G1 H4 landing"
export STATELESS=1
if g1_happy "$m"; then no "G1 H4: reorder survived a stateless stub"
else case "$G1WHY" in *login-not-before-pull*) ok "G1 H4: reorder reds via login-before-pull order even with a stateless stub";; *) no "G1 H4: wrong reason:$G1WHY";; esac; fi
unset STATELESS; rm -f "$m"
# G2
mrow "G2.1 ip piped into grep (a failing ip reads as absent)" g2_fail g2_ip_piped
mrow "G2.2 empty-address guard dropped" g2_noip g2_no_empty_guard noip
mrow "G2.3 wait body never runs" g2_never g2_body_skipped
mrow "G2.4 both non-ready stages emitted" g2_never g2_both_stages
mrow "G2.5 timeout stage renamed (unrouted)" g2_routed g2_renamed_stage
mrow "G2.6 zot login moved before the NIC wait" g2_order g2_wait_after_login
# G2.7: a clock-based loop under a no-op sleep spins for real time — the harness bound turns
# that into exit 2 (never a pass); run in a subshell so the harness exit is observable here.
m="$WORK/def/sb/g27.sh"; cp "$DEF" "$m"
python3 "$WORK/muts.py" "$m" g2_clock_loop || harness "G2.7 landing"
( g2_never "$m" ) >/dev/null 2>&1; r=$?
[ "$r" = 2 ] && ok "mutation RED: G2.7 counter replaced by a wall-clock deadline (harness bound → exit 2)" \
  || no "mutation SURVIVED or misreported: G2.7 clock loop (rc=$r, want 2)"
rm -f "$m"
# G2 H1: the probe's argv is pinned by the argv-validating stub (#6415).
mrow "G2 H1 probe argv changed (ip -o link show)" g2_ready0 g2_argv
mrow "G2.8 ready never breaks the wait" g2_conv g2_no_break

# ── Guard 4 (behavioural): the boot trail can surface which registry served a fresh boot ──────
TRAIL="$DIR/scripts/fresh-host-boot-trail.sh"
TB="$WORK/trailbin"; mkdir -p "$TB"
cat > "$TB/curl" <<'STUB'
#!/bin/sh
# Fixture Sentry. The org endpoint answers by the DECODED query: the image-origin read (project +
# host + the three stages) gets $ORG_FIX, the seed-fatal read (project + host + message) gets
# $FATAL_FIX, anything else is a 400 — so a read that asks the wrong question cannot pass.
out=""; url=""
while [ $# -gt 0 ]; do case "$1" in -o) out="$2"; shift ;; -w|-H|--max-time|--data-urlencode|--noproxy) shift ;; http*) url="$1" ;; esac; shift; done
printf '%s\n' "$url" >> "$CURL_LOG"
case "$url" in
  */organizations/*)
    q=$(printf '%s' "$url" | sed -n 's/.*[?&]query=\([^&]*\).*/\1/p' | python3 -c 'import sys,urllib.parse;print(urllib.parse.unquote(sys.stdin.read().strip()))')
    case "$q" in
      "project:web-platform host_name:soleur-web-2 stage:[app_zot,app_ghcr_served,app_ghcr_fallback]") cp "$ORG_FIX" "$out"; printf '%s' "${ORG_CODE:-200}" ;;
      'project:web-platform host_name:soleur-web-2 message:"soleur-hostscript-seed failed"') cp "$FATAL_FIX" "$out"; printf '200' ;;
      *) echo '{"detail":"stub: unexpected query"}' > "$out"; printf '400' ;;
    esac ;;
  *) cp "$PROJ_FIX" "$out"; printf '200' ;;
esac
STUB
chmod +x "$TB/curl"
org_rows() {  # <n> <stage> : n Discover rows, newest first
  python3 - "$1" "$2" <<'PY'
import json, sys
n, st = int(sys.argv[1]), sys.argv[2]
rows = [{"timestamp": "2026-09-24T10:%02d:00+00:00" % (59 - i), "stage": st, "host_name": "soleur-web-2",
         "detail": "zot_login=ok nic=ready:0"} for i in range(n)]
print(json.dumps({"data": rows}))
PY
}
trail_io() {  # runs --image-origin under the fixture; sets TRC/TOUT
  TRC=0; TOUT=$(PATH="$TB:$PATH" CURL_LOG="$WORK/curl.log" ORG_FIX="$WORK/org.json" FATAL_FIX="$WORK/fatal.json" PROJ_FIX="$WORK/proj.json" \
    bash "$TRAIL" --image-origin soleur-web-2 2>&1) || TRC=$?
}
: > "$WORK/curl.log"; echo '[]' > "$WORK/proj.json"
org_rows 1 app_zot > "$WORK/org.json"
echo '{"data":[{"timestamp":"2026-09-24T09:00:00+00:00","stage":"pull","host_name":"soleur-web-2","detail":"nic=ready:0"}]}' > "$WORK/fatal.json"
export SENTRY_ACTIONS_RO_TOKEN=x
trail_io
[ "$TRC" = 0 ] && grep -q '^image-origin: stage=app_zot host=soleur-web-2 time=2026-09-24T10:59:00Z' <<<"$TOUT" \
  && grep -qx 'seed-fatal: stage=pull host=soleur-web-2 time=2026-09-24T09:00:00Z detail=nic=ready:0' <<<"$TOUT" \
  && ok "G4: --image-origin prints the newest app_zot for the host (server-side query) and a seed-fatal line, exit 0" \
  || no "G4: --image-origin happy path: rc=$TRC out=$(head -c 300 <<<"$TOUT")"
grep -q 'host_name%3Asoleur-web-2' "$WORK/curl.log" && grep -q 'statsPeriod=14d' "$WORK/curl.log" \
  && ok "G4: the origin read filters server-side on host_name over 14d" || no "G4: origin query shape: $(head -c 300 "$WORK/curl.log")"
ORG_CODE=500 trail_io
[ "$TRC" = 2 ] && grep -q '^TRANSIENT:' <<<"$TOUT" && ok "G4: a non-200 read is TRANSIENT (exit 2), never 'nothing found'" || no "G4: non-200: rc=$TRC $TOUT"
org_rows 100 app_zot > "$WORK/org.json"; trail_io
[ "$TRC" = 2 ] && grep -q 'full page' <<<"$TOUT" && ok "G4: a full page is TRANSIENT (truncated), never a verdict" || no "G4: full page: rc=$TRC $TOUT"
echo '{"data":[]}' > "$WORK/org.json"; trail_io
[ "$TRC" = 1 ] && grep -q '^image-origin: stage=none' <<<"$TOUT" && ok "G4: no origin event → 'stage=none', exit 1" || no "G4: none: rc=$TRC $TOUT"
org_rows 1 app_zot > "$WORK/org.json"
BOOT_TRAIL_SINCE=1800000000 trail_io   # 2027 — newer than every fixture row
[ "$TRC" = 1 ] && grep -qx 'image-origin: stage=none host=- time=- detail=-' <<<"$TOUT" && grep -qx 'seed-fatal: stage=none host=- time=- detail=-' <<<"$TOUT" \
  && ok "G4: the run anchor (BOOT_TRAIL_SINCE) excludes older origin AND fatal rows" || no "G4: since: rc=$TRC $TOUT"
BOOT_TRAIL_SINCE=abc trail_io
[ "$TRC" = 2 ] && grep -q '^TRANSIENT:' <<<"$TOUT" && ok "G4: a non-epoch BOOT_TRAIL_SINCE is TRANSIENT, never an empty verdict" || no "G4: bad since: rc=$TRC $TOUT"
echo '{"data":[{"timestamp":1727170000,"stage":"app_zot","host_name":"soleur-web-2","detail":"x"}]}' > "$WORK/org.json"; trail_io
[ "$TRC" = 2 ] && grep -q '^TRANSIENT:.*projection' <<<"$TOUT" && ok "G4: a projection (jq) failure is TRANSIENT, never a blank verdict" || no "G4: jq failure: rc=$TRC $TOUT"
org_rows 1 app_zot > "$WORK/org.json"
unset SENTRY_ACTIONS_RO_TOKEN; trail_io
[ "$TRC" = 2 ] && grep -q '^TRANSIENT:' <<<"$TOUT" && ok "G4: unbound token → TRANSIENT exit 2" || no "G4: unbound token: rc=$TRC $TOUT"
# Job mode: 12 host events, newest fresh_boot_ready, OLDEST app_zot → past the 8-event slice. The
# origin line (separate server-side read) must still print app_zot, and the verdict stays green.
python3 - "$WORK/proj.json" <<'PY'
import json, sys
ev = []
for i in range(12):
    st = "fresh_boot_ready" if i == 0 else ("app_zot" if i == 11 else "boot_%d" % i)
    msg = "app image served by zot" if st == "app_zot" else "soleur-cloud-init boot stage"
    ev.append({"message": msg, "dateCreated": "2026-09-24T10:%02d:00Z" % (59 - i),
               "tags": [{"key": "stage", "value": st}, {"key": "host_name", "value": "soleur-web-2"},
                        {"key": "level", "value": "info"}]})
json.dump(ev, open(sys.argv[1], "w"))
PY
org_rows 1 app_zot > "$WORK/org.json"; : > "$WORK/summary.md"
jrc=0; jout=$(PATH="$TB:$PATH" CURL_LOG="$WORK/curl.log" ORG_FIX="$WORK/org.json" FATAL_FIX="$WORK/fatal.json" PROJ_FIX="$WORK/proj.json" \
  SENTRY_ACTIONS_RO_TOKEN=x JOB_STATUS=success WEB_HOST_KEY=web-2 DISPATCH_LABEL=web-host-replace \
  BOOT_TRAIL_SINCE=0 GITHUB_STEP_SUMMARY="$WORK/summary.md" bash "$TRAIL" 2>&1) || jrc=$?
if [ "$jrc" = 0 ] && grep -q 'image-origin (`soleur-web-2`.*stage=app_zot' <<<"$jout" && grep -q 'fresh_boot_ready' <<<"$jout" \
   && ! grep -q 'stage=`app_zot`' <<<"$jout"; then
  ok "G4/AC8: app_zot outside the 8-event slice still surfaces on the image-origin line; verdict unchanged (fresh_boot_ready)"
else no "G4/AC8 job mode: rc=$jrc $(grep -E 'image-origin|fresh_boot|app_zot' <<<"$jout" | head -5 | tr '\n' ' ')"; fi

# ── Guard 4, colocated site (#8036 1d): a zot miss in the gated colocated-inngest item is terminal ──
# The item is dead code while web_colocate_inngest=false, and is exercised here so that turning the
# toggle on cannot resurrect an unwatched GHCR arm. EXECUTED from the web_colocate_inngest=true
# render (never grepped: the property is order and lifetime), followed by a marker standing in for
# the next runcmd item — runcmd is ONE /bin/sh, so an `exit` in the item must end it.
C4="$WORK/c4"; mkdir -p "$C4/bin"
python3 - "$WORK/colo/r.yml" "$C4/item.sh" <<'PY' || harness "G4c: could not extract the colocated-inngest item from the colocate=true render"
import sys, yaml
items = [i for i in yaml.safe_load(open(sys.argv[1]))["runcmd"] if isinstance(i, str)]
hits = [i for i in items if "soleur-inngest-bootstrap-extract" in i]
if len(hits) != 1:
    sys.exit("G4c: %d colocated items" % len(hits))
open(sys.argv[2], "w").write(hits[0] + "\necho RUNCMD_CONTINUED\n")
PY
cat > "$C4/bin/docker" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >> "$C4_LOG"
case "$1" in
  pull) exit "${C4_PULL_RC:-0}" ;;
  cp) case "$3" in */inngest-bootstrap.sh) : > "$3" ;; esac ;;
esac
exit 0
STUB
assert_fixture_dir "$C4"
cat > "$C4/bin/soleur-boot-emit" <<'STUB'
#!/bin/sh
printf "emit %s\n" "$*" >> "$C4_LOG"
exit 0
STUB
cat > "$C4/bin/curl" <<'STUB'
#!/bin/sh
printf "curl %s\n" "$*" >> "$C4_LOG"
exit 7
STUB
# Records the bound, then runs the wrapped command (the docker stub) — so the log shows WHICH
# call was bounded. The colocated pull lost its 3 s /v2/ pre-check with 1d; the timeout is its
# only ceiling (the dedicated inngest template and the seed pull use the same 180 s).
cat > "$C4/bin/timeout" <<'STUB'
#!/bin/sh
printf "timeout %s " "$1" >> "$C4_LOG"
shift
exec "$@"
STUB
chmod +x "$C4/bin"/*
C4_ZIREF="10.0.1.30:5000/jikig-ai/soleur-inngest-bootstrap:"
c4_run() {  # <script> <pull rc> : sets C4RC, C4OUT; the call log is $C4/log
  : > "$C4/log"; C4RC=0
  C4OUT=$(C4_LOG="$C4/log" C4_PULL_RC="$2" PATH="$C4/bin:/usr/bin:/bin" TMPDIR="$C4" \
    /usr/bin/timeout 20 "$SHELL_BIN" "$1" 2>&1) || C4RC=$?
}
c4_miss() {  # the property: fatal emit (the only emit), non-zero, no later pull/create, runcmd ended
  c4_run "$1" "${C4_FORCE_RC:-1}"
  local why=""
  [ "$C4RC" != 0 ] || why="$why rc=0"
  grep -q RUNCMD_CONTINUED <<<"$C4OUT" && why="$why runcmd-continued"
  [ "$(grep '^emit ' "$C4/log" | tr '\n' '|')" = "emit inngest_pull_fatal fatal|" ] || why="$why emits=[$(grep '^emit ' "$C4/log" | tr '\n' '|')]"
  [ "$(grep -cE '^(timeout [0-9]+ )?pull ' "$C4/log")" = 1 ] || why="$why pulls=$(grep -cE '^(timeout [0-9]+ )?pull ' "$C4/log")"
  grep -q "^pull $C4_ZIREF" "$C4/log" || grep -q "^timeout 180 pull $C4_ZIREF" "$C4/log" || why="$why first-pull-not-zot"
  grep -q '^create ' "$C4/log" && why="$why create-after-miss"
  grep -q '^curl ' "$C4/log" && why="$why probe-on-resolution-path"
  G4WHY="$why"; [ -z "$why" ]
}
c4_hit() {  # zot hit: inngest_zot info, one pull, and every later consumer follows the zot ref
  c4_run "$1" 0
  local why=""
  [ "$C4RC" = 0 ] || why="$why rc=$C4RC"
  grep -q RUNCMD_CONTINUED <<<"$C4OUT" || why="$why runcmd-ended"
  [ "$(grep '^emit ' "$C4/log" | tr '\n' '|')" = "emit inngest_zot info|" ] || why="$why emits=[$(grep '^emit ' "$C4/log" | tr '\n' '|')]"
  [ "$(grep -cE '^(timeout [0-9]+ )?pull ' "$C4/log")" = 1 ] || why="$why pulls=$(grep -cE '^(timeout [0-9]+ )?pull ' "$C4/log")"
  grep -q "^timeout 180 pull $C4_ZIREF" "$C4/log" || why="$why pull-unbounded"
  grep -q "^create --name soleur-inngest-bootstrap-extract $C4_ZIREF" "$C4/log" || why="$why create-not-zot"
  grep -q "^inspect $C4_ZIREF" "$C4/log" || why="$why inspect-not-zot"
  grep -q 'ghcr\.io' "$C4/log" && why="$why ghcr-ref-used"
  G4WHY="$why"; [ -z "$why" ]
}
c4_miss "$C4/item.sh" && ok "G4c: colocated zot miss → soleur-boot-emit inngest_pull_fatal fatal (only emit), exit non-zero, no later pull/create, runcmd ends" \
  || no "G4c miss:$G4WHY"
c4_hit "$C4/item.sh" && ok "G4c: colocated zot hit → inngest_zot info, one pull bounded by timeout 180, create/inspect follow the zot ref, runcmd continues" \
  || no "G4c hit:$G4WHY"
c4_mut() {  # <label> <predicate> <python replace old> <new>
  cp "$C4/item.sh" "$C4/mut.sh"
  python3 - "$C4/mut.sh" "$3" "$4" <<'PY' || harness "G4c mutation did not land: $1"
import sys
p, a, b = sys.argv[1:4]
s = open(p).read()
if s.count(a) != 1:
    sys.exit(3)
open(p, "w").write(s.replace(a, b))
PY
  G4WHY=""
  if "$2" "$C4/mut.sh"; then no "G4c mutation SURVIVED: $1"; else ok "G4c mutation RED: $1 —$G4WHY"; fi
}
c4_mut "emit moved after the exit (unreachable)" c4_miss "soleur-boot-emit inngest_pull_fatal fatal; exit 1;" "exit 1; soleur-boot-emit inngest_pull_fatal fatal;"
c4_mut "emit level swapped to warning" c4_miss "inngest_pull_fatal fatal;" "inngest_pull_fatal warning;"
c4_mut "exit dropped (falls through to docker create)" c4_miss "inngest_pull_fatal fatal; exit 1;" "inngest_pull_fatal fatal; :;"
c4_mut "the GHCR fallback restored (pull of the IREF pin carrier after the miss)" c4_miss "inngest_pull_fatal fatal; exit 1;" 'inngest_ghcr_fallback warning; docker pull "$IREF";'
c4_mut "the /v2/ probe restored on the resolution path" c4_miss 'if timeout 180 docker pull "$ZIREF"; then' 'if curl -s -o /dev/null --max-time 3 "http://$ZURL/v2/" && timeout 180 docker pull "$ZIREF"; then'
c4_mut "timeout 180 dropped from the colocated zot pull (unbounded)" c4_hit 'if timeout 180 docker pull "$ZIREF"; then' 'if docker pull "$ZIREF"; then'
# Harness must-RED: a stub whose "failing" pull returns 0 never reaches the miss arm — the miss
# predicate must not pass by testing the hit arm twice.
if C4_FORCE_RC=0 c4_miss "$C4/item.sh"; then no "G4c harness: the miss predicate passed with the pull stubbed to succeed"
else ok "G4c harness RED: with the pull stubbed to succeed the miss predicate fails —$G4WHY"; fi

# ── Cross-template per-leg wording (NARROWED by #8036 1d) ────────────────────────────────────
# Before 1d the web fatal and the inngest oci-pull-ALL-LEGS-FAILED marker shared 'zot=[' 'ghcr=['
# 'not-attempted'. The GHCR leg is gone from both templates and the inngest ALL-LEGS bracket goes
# with it, so only 'zot=[' survives — in the web fatal detail. The two GHCR tokens are now
# residual-zero on BOTH sides (a re-added GHCR leg in either template reds here).
webcode=$(grep -vE '^[[:space:]]*#' "$SRC"); ingcode=$(grep -vE '^[[:space:]]*#' "$INNGEST_CI")
if grep -qF -- 'zot=[' <<<"$webcode"; then ok "parity: 'zot=[' names the zot leg in the web fatal detail"
else no "parity: 'zot=[' must appear in the code of cloud-init.yml (the per-leg fatal detail)"; fi
for tok in 'ghcr=[' 'not-attempted'; do
  if grep -qF -- "$tok" <<<"$webcode" || grep -qF -- "$tok" <<<"$ingcode"; then no "parity: GHCR per-leg token '$tok' is back in the code of cloud-init.yml or cloud-init-inngest.yml (#8036 1d)"
  else ok "parity: GHCR per-leg token '$tok' is in neither template's code (#8036 1d)"; fi
done

# Floor: the number of assertions must not silently shrink (a deleted block reads as green).
# #8036 1d: 91 → 99. Every retired GHCR row was replaced 1:1 by its residual-zero inverse, and the
# 8 G4c colocated-inngest rows were added BEFORE this restatement. 99 → 101 (PR #8708 review): the
# G1.21 on_err level=fatal mutation row and the G4c unbounded-colocated-pull mutation row.
MIN_ASSERTIONS=101
total=$((pass + fail + skipped))
if [ "$total" -lt "$MIN_ASSERTIONS" ]; then
  printf 'assertion floor: %d < %d — a block stopped asserting\n' "$total" "$MIN_ASSERTIONS"; exit 1
fi
echo "=== cloud-init-web-zot-seed: $pass passed, $fail failed ==="
[ "$fail" -eq 0 ]
