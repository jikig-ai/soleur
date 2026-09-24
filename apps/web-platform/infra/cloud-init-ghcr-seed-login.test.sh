#!/usr/bin/env bash
set -euo pipefail
# A pipe into `grep -q` SIGPIPEs its producer on an early match and pipefail reads it as
# FALSE (#7024); _qgrep reads all of its input instead.
_qgrep() { grep "$@" >/dev/null; }

# Regression guard for the fresh-boot seed pull, and (since #8036 item 1d / ADR-096 5.3b-i) the
# host-side GHCR boot residual-zero census (plan 2026-09-24-chore-retire-host-boot-ghcr-legs,
# Guard 1).
#
# HISTORY (why this file exists). The seed image became a PRIVATE GHCR package (#6005/#6011) and
# the seed pull ran ANONYMOUSLY, so every fresh boot 401'd at stage=pull; the fatal emit sourced
# its DSN from doppler, so the failure was invisible too. The fix baked a GHCR login ahead of the
# pull. #8651 made the pull zot-first by bake. #8036 1d then DELETED every GHCR arm: the read PAT
# is revoked (AP-016), so no GHCR login or pull could succeed. zot is the only boot read path.
#
# Asserts:
#   1. (INVERTED by #8036 1d) the zot login precedes the seed pull, and NO `docker login ghcr.io`
#      is left anywhere in cloud-init.yml code.
#   2. the seed-block fatal emit (on_err) prefers the BAKED ${sentry_dsn}.
#   3. server.tf passes sentry_dsn into the cloud-init templatefile AND variables.tf declares it.
#   4. (INVERTED by #8036 1d) the seed pull is ONE bounded zot pull, gated on the zot login; the
#      login-gated GHCR pull arm is gone.
#   G1. Guard 1 census over the three host boot files + the two .tf templatefile maps that render
#      them: no GHCR credential presented, no pull from anything but a zot-derived ref ($REF with
#      every REF= zot-derived, $ZIREF, the /run/soleur-image-ref sentinel, $IMAGE_REF only after
#      IMAGE_REF="$REF"; $IREF only as a `docker create` after IREF="$ZIREF", never pulled). Runs on
#      SOURCE bytes with comment lines stripped (in rendered bytes, IMAGE_REF='${image_name}'
#      becomes a ghcr.io literal, so it is a named exemption, like the IREF= pin carrier).

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CI="$DIR/cloud-init.yml"
SRV="$DIR/server.tf"
VARS="$DIR/variables.tf"
pass=0; fail=0
ok() { pass=$((pass + 1)); echo "[ok] $1"; }
no() { fail=$((fail + 1)); echo "[FAIL] $1" >&2; }
code() { grep -vE '^[[:space:]]*#' "$1"; }

# 1. zot login before the seed pull; no GHCR login at all.
# shellcheck disable=SC2016  # intentional: grep for the LITERAL $ZEP/$REF in the YAML.
login_ln=$(grep -nE 'timeout 60 docker login "\$ZEP"' "$CI" | head -1 | cut -d: -f1 || true)
# shellcheck disable=SC2016
pull_ln=$(grep -nE 'timeout 180 docker pull "\$REF"' "$CI" | head -1 | cut -d: -f1 || true)
if [ -n "$login_ln" ] && [ -n "$pull_ln" ] && [ "$login_ln" -lt "$pull_ln" ]; then
  ok "zot docker login (line $login_ln) precedes the seed pull (line $pull_ln)"
else
  no "the zot login must precede the seed pull — login='$login_ln' pull='$pull_ln' (zot has no anonymous read)"
fi
if code "$CI" | _qgrep -E 'docker[[:space:]]+login[^|;&]*ghcr\.io'; then
  no "a 'docker login ghcr.io' is back in cloud-init.yml code (#8036 1d: no host presents a GHCR credential at boot)"
else
  ok "no 'docker login ghcr.io' in cloud-init.yml code (#8036 1d)"
fi

# 1b. RETIRED by #8651 and asserted ABSENT: the seed login must NOT read GHCR_READ_* from doppler
# (tokenless by construction above the terminal `set -a` source, #6985).
if code "$CI" | _qgrep -E 'doppler secrets get GHCR_READ_(USER|TOKEN)'; then
  no "seed login must not fetch GHCR_READ_{USER,TOKEN} via doppler (tokenless by construction, #6985/#8651)"
else
  ok "seed login reads no GHCR_READ_* from doppler (#8651)"
fi

# 2. the fatal emit prefers the baked DSN.
if grep -qE "DSN='\\\$\{sentry_dsn\}'" "$CI"; then
  ok "on_err fatal emit prefers baked \${sentry_dsn} (fires without doppler)"
else
  no "on_err must prefer baked \${sentry_dsn} so the failure signal survives a broken doppler stage"
fi

# 3. templatefile var wired end-to-end (referenced ⟹ must be passed ⟹ must be declared).
if grep -qE '\$\{sentry_dsn\}' "$CI"; then ok "cloud-init.yml references \${sentry_dsn}"; else no "cloud-init.yml must reference \${sentry_dsn}"; fi
if grep -qE '^\s*sentry_dsn\s*=\s*var\.sentry_dsn' "$SRV"; then ok "server.tf passes sentry_dsn to the templatefile"; else no "server.tf must pass sentry_dsn = var.sentry_dsn (else templatefile() fails)"; fi
if grep -qE 'variable "sentry_dsn"' "$VARS"; then ok "variables.tf declares variable \"sentry_dsn\""; else no "variables.tf must declare variable \"sentry_dsn\""; fi

# 4. §1A RETIRED by #8651 and asserted ABSENT.
if code "$CI" | _qgrep -E 'ghcr_login_ok_refetch|until R[UT]=.*doppler'; then
  no "the dead §1A Doppler re-fetch arm is back (tokenless by construction, #6985/#8651)"
else
  ok "no §1A Doppler re-fetch arm (retired by #8651)"
fi
# INVERTED by #8036 1d: exactly ONE seed pull (the zot leg), gated on the zot login; the
# `"$GL" = ok` GHCR arm and its second `timeout 180 docker pull "$REF"` are gone.
npull=$(code "$CI" | grep -cE 'timeout 180 docker pull "\$REF"' || true)
if [ "$npull" = 1 ] && code "$CI" | _qgrep -E '\[ -n "\$REF" \] && \[ \$ZL = ok \] && while .*timeout 180 docker pull "\$REF"' \
   && ! code "$CI" | _qgrep -E '"\$GL"'; then
  ok "the seed pull is one zot pull gated on the zot login; no login-gated GHCR arm (#8036 1d)"
else
  no "the seed pull must be exactly one 'timeout 180 docker pull \"\$REF\"', gated on [ -n \"\$REF\" ] && [ \$ZL = ok ], with no \"\$GL\" GHCR arm (pulls=$npull)"
fi

# ── G1: host-side GHCR boot residual-zero census (Guard 1) ─────────────────────────────────────
WORK="$(mktemp -d "${TMPDIR:-/var/tmp}/ghcr-census.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
cat > "$WORK/census.py" <<'CENSUS_PY'
"""Guard 1 census. argv: <root> <boot files, comma-sep> <tf:template pairs, comma-sep>.

Prints one line per finding:
  SCANNED <file>                 a file that exists, is non-empty, and was read
  LOGINS <n> / PULLS <n>         docker login / docker pull|create sites seen across boot files
  MAPS <n>                       templatefile() maps swept across every .tf under <root>
  VIOL <file> <rule> <detail>    a violation (content-keyed, never line-numbered, so a
                                 mutation's NEW violation is a multiset difference)
Comment lines (first non-blank char '#') are stripped before any rule reads a line.
"""
import os, re, sys

root = sys.argv[1]
boot = [f for f in sys.argv[2].split(",") if f]
tfpairs = [p.split(":", 1) for p in sys.argv[3].split(",") if p]
out = []

def code_lines(path):
    return [l.rstrip("\n") for l in open(path) if not l.lstrip().startswith("#")]

FORBIDDEN = ["ghcr_read_", "soleur-ghcr-read", "app_ghcr_", "inngest_ghcr_fallback", "echo '${image_name}'"]
LOGIN_RE = re.compile(r"docker\s+login\s+(\"[^\"]*\"|'[^']*'|[^\s;|&)]+)")
ARG = r"(\"[^\"]*\"|'[^']*'|[^\s;|&)]+)"
PULL_RE = re.compile(r"docker\s+(pull|create)\s+(?:(?:-q|--quiet|--name\s+\S+|--platform\s+\S+)\s+)*" + ARG)
ASSIGN_RE = re.compile(r"(?<![A-Za-z0-9_$])(IREF|IMAGE_REF|ZIREF|REF)=(\"[^\"]*\"|'[^']*'|[^\s;]*)")
PIN_RE = re.compile(r"^\s*IREF=ghcr\.io/jikig-ai/soleur-inngest-bootstrap:v\d+\.\d+\.\d+@sha256:[0-9a-f]{64}\s*(#.*)?$")
IMAGE_NAME_OK = re.compile(r"^\s*IMAGE_REF='\$\{image_name\}'\s*$")
GHCR_OK_TOKENS = ("in ghcr.io/*@sha256:*)", "IMAGE_REF#ghcr.io/}")
ZOT_REF_VALUES = re.compile(r'^("\$ZEP/.*|)$')
ZOT_ZIREF_VALUES = re.compile(r'^"\$(ZURL|ZOT_EP)/.*')

logins = pulls = 0
for f in boot:
    p = os.path.join(root, f)
    if not (os.path.isfile(p) and os.path.getsize(p) > 0):
        continue
    out.append("SCANNED " + f)
    last = {}  # last assignment value seen for IREF / IMAGE_REF, in file order
    pins = 0
    for line in code_lines(p):
        s = line.strip()
        # (1) forbidden tokens
        for tok in FORBIDDEN:
            if tok in line:
                out.append("VIOL %s forbidden[%s] %s" % (f, tok, s))
        # (2) every docker login presents a zot credential, never a GHCR one
        for m in LOGIN_RE.finditer(line):
            logins += 1
            if m.group(1) not in ('"$ZEP"', '"$ZOT_EP"'):
                out.append("VIOL %s login-arg[%s] %s" % (f, m.group(1), s))
        # (3) pull/create sources + assignments, in column order within the line
        events = [(m.start(), "assign", m) for m in ASSIGN_RE.finditer(line)]
        events += [(m.start(), "pull", m) for m in PULL_RE.finditer(line)]
        for _, kind, m in sorted(events, key=lambda e: e[0]):
            if kind == "assign":
                var, val = m.group(1), m.group(2)
                last[var] = val
                if var == "REF" and not ZOT_REF_VALUES.match(val):
                    out.append("VIOL %s ref-assign[%s] %s" % (f, val, s))
                if var == "ZIREF" and not ZOT_ZIREF_VALUES.match(val):
                    out.append("VIOL %s ziref-assign[%s] %s" % (f, val, s))
                continue
            pulls += 1
            a = m.group(2)
            if a in ('"$REF"', '"$ZIREF"', '"$(cat /run/soleur-image-ref)"'):
                continue
            # $IREF is consumed (create) only after IREF="$ZIREF"; it is never PULLED — the only
            # bootstrap pull is of $ZIREF, and a pull of $IREF is how a GHCR-seeded ref (the pin
            # carrier, or a branch that skipped the reassign) reaches the registry.
            if a == '"$IREF"' and m.group(1) == "create" and last.get("IREF") == '"$ZIREF"':
                continue
            if a == '"$IMAGE_REF"' and last.get("IMAGE_REF") == '"$REF"':
                continue
            out.append("VIOL %s pull-src[%s:%s] %s" % (f, m.group(1), a, s))
        # (4) ${image_name} only as the IMAGE_REF='${image_name}' seed input
        if "${image_name}" in line and not IMAGE_NAME_OK.match(line):
            out.append("VIOL %s image_name %s" % (f, s))
        # (5) ghcr.io on a code line only as the IREF= pin carrier or the seed case pattern
        if PIN_RE.match(line):
            pins += 1
        else:
            rest = line
            for t in GHCR_OK_TOKENS:
                rest = rest.replace(t, "")
            if "ghcr.io" in rest:
                out.append("VIOL %s ghcr.io %s" % (f, s))
    # (6) the bump bot's contract: an inngest-bearing template carries exactly 2 refs (whole file,
    # comments included — a comment quoting a full ref would make the bot refuse) and 1 carrier
    text = open(p).read()
    if "soleur-inngest-bootstrap:v" in text or f in ("cloud-init.yml", "cloud-init-inngest.yml"):
        n = len(re.findall(r"jikig-ai/soleur-inngest-bootstrap:v[0-9]", text))
        if n != 2:
            out.append("VIOL %s bootstrap-ref-count[%d!=2]" % (f, n))
        if pins != 1:
            out.append("VIOL %s pin-carrier-count[%d!=1]" % (f, pins))

def maps(tfsrc):
    """Yield (template, body) for every templatefile("${path.module}/…", { … }) in code lines."""
    src = "\n".join(l for l in tfsrc.splitlines() if not l.lstrip().startswith(("#", "//")))
    for m in re.finditer(r'templatefile\(\s*"\$\{path\.module\}/(?:\.\./)*([^"]+)"\s*,\s*\{', src):
        i, depth = m.end(), 1
        while i < len(src) and depth:
            depth += {"{": 1, "}": -1}.get(src[i], 0); i += 1
        yield m.group(1), src[m.end():i - 1]

KEY_RE = re.compile(r"^\s*(ghcr_read_\w+)\s*=", re.M)
for tf, tpl in tfpairs:
    p = os.path.join(root, tf)
    if not (os.path.isfile(p) and os.path.getsize(p) > 0):
        continue
    bodies = [b for t, b in maps(open(p).read()) if t == tpl]
    if len(bodies) != 1 or not bodies[0].strip():
        out.append("VIOL %s map-not-found[%s n=%d]" % (tf, tpl, len(bodies)))
        continue
    out.append("SCANNED %s:%s" % (tf, tpl))
    for k in KEY_RE.findall(bodies[0]):
        out.append("VIOL %s tf-key[%s->%s]" % (tf, k, tpl))
# Every OTHER templatefile map in the root (git-data module, registry, grok, hooks, …) too.
nmaps = 0
for d, dirs, files in os.walk(root):
    dirs[:] = [x for x in dirs if x != ".terraform"]
    for fn in files:
        if not fn.endswith(".tf"):
            continue
        rel = os.path.relpath(os.path.join(d, fn), root)
        for tpl, body in maps(open(os.path.join(d, fn)).read()):
            nmaps += 1
            for k in KEY_RE.findall(body):
                out.append("VIOL %s sweep-key[%s->%s]" % (rel, k, tpl))
out += ["LOGINS %d" % logins, "PULLS %d" % pulls, "MAPS %d" % nmaps]
print("\n".join(out))
CENSUS_PY

BOOT_FILES="cloud-init.yml,soleur-host-bootstrap.sh,cloud-init-inngest.yml"
TF_PAIRS="server.tf:cloud-init.yml,inngest-host.tf:cloud-init-inngest.yml"
EXPECTED_SCANNED=$'SCANNED cloud-init.yml\nSCANNED soleur-host-bootstrap.sh\nSCANNED cloud-init-inngest.yml\nSCANNED server.tf:cloud-init.yml\nSCANNED inngest-host.tf:cloud-init-inngest.yml'
census() { python3 "$WORK/census.py" "$1" "${2-$BOOT_FILES}" "${3-$TF_PAIRS}"; }
viols() { grep '^VIOL ' || true; }

# dispatch_ok <census output>: scanned EXACTLY the expected files and found real call sites —
# never "0 scanned, 0 found" (a misspelled path or an empty list must go RED, not green).
dispatch_ok() {
  local c="$1" sc lg pl mp
  sc=$(grep '^SCANNED ' <<<"$c" || true)
  lg=$(sed -n 's/^LOGINS //p' <<<"$c"); pl=$(sed -n 's/^PULLS //p' <<<"$c"); mp=$(sed -n 's/^MAPS //p' <<<"$c")
  DWHY="scanned=[$(tr '\n' ' ' <<<"$sc")] logins=${lg:-?} pulls=${pl:-?} maps=${mp:-?}"
  [ "$sc" = "$EXPECTED_SCANNED" ] && [ "${lg:-0}" -ge 1 ] && [ "${pl:-0}" -ge 1 ] && [ "${mp:-0}" -ge 4 ]
}

C=$(census "$DIR")
if dispatch_ok "$C"; then ok "G1 dispatch: census scanned exactly the 3 boot files + 2 templatefile maps ($DWHY)"
else no "G1 dispatch: census must scan exactly the 3 boot files + the 2 .tf maps and find >=1 docker login, >=1 pull, >=4 maps ($DWHY)"; fi
for f in cloud-init.yml soleur-host-bootstrap.sh cloud-init-inngest.yml server.tf inngest-host.tf; do
  v=$(viols <<<"$C" | grep -F "VIOL $f " || true)
  if [ -z "$v" ]; then ok "G1: $f — 0 host-side GHCR boot residuals (login args zot-only, pull sources zot-derived)"
  else no "G1: $f carries host-side GHCR boot residuals:"; printf '        %s\n' "$v" >&2; fi
done
v=$(viols <<<"$C" | grep -F ' sweep-key[' || true)
if [ -z "$v" ]; then ok "G1: no templatefile() map anywhere in the infra root passes a ghcr_read_* key"
else no "G1: a templatefile() map passes a GHCR credential:"; printf '        %s\n' "$v" >&2; fi

# ── G1 mutation matrix (plan Guard 1). Each row mutates a SANDBOX copy and must add at least one
# NEW violation (multiset difference against the unmutated census) — so a row stays meaningful
# even while another file's baseline is red. Row 6 is the must-PASS harness row.
SB="$WORK/sb"
# The sandbox holds exactly what the census reads: the 3 boot files + every .tf under the root.
sandbox() {
  rm -rf "$SB"; mkdir -p "$SB"
  cp "$DIR/cloud-init.yml" "$DIR/soleur-host-bootstrap.sh" "$DIR/cloud-init-inngest.yml" "$SB/"
  (cd "$DIR" && find . -name '*.tf' -not -path '*/.terraform/*' -print0 | xargs -0 -I{} cp --parents {} "$SB/")
}
sandbox
BASE=$(census "$SB" | viols | sort)
[ "$BASE" = "$(census "$DIR" | viols | sort)" ] || { echo "[HARNESS] the sandbox census differs from the live census — the sandbox is missing an input" >&2; exit 2; }
new_viols() { comm -13 <(printf '%s\n' "$BASE") <(census "$SB" | viols | sort) | grep -v '^$' || true; }
# landed <file> : the mutation actually changed the sandbox file (else the row is a harness fault)
landed() { if cmp -s "$DIR/$1" "$SB/$1"; then echo "[HARNESS] mutation did not land in $1" >&2; exit 2; fi; }
mrow() {  # <label> <file>
  landed "$2"
  local n; n=$(new_viols)
  if [ -n "$n" ]; then ok "G1 mutation RED: $1 — $(head -1 <<<"$n" | cut -c1-110)"
  else no "G1 mutation SURVIVED: $1"; fi
  sandbox
}
py_edit() {  # <file> <python expr over s>; an anchor that is not there is a HARNESS fault (exit 2)
  python3 - "$SB/$1" "$2" <<'PY' || { echo "[HARNESS] mutation anchor not found in $1" >&2; exit 2; }
import sys
p, expr = sys.argv[1], sys.argv[2]
s = open(p).read()
o = eval(expr, {"s": s, "chr": chr})
open(p, "w").write(o)
PY
}
# 1: a GHCR login restored in the inngest template (after a compliant web file)
printf "    printf '%%s' \"\$T\" | docker login ghcr.io -u \"\$U\" --password-stdin\n" >> "$SB/cloud-init-inngest.yml"
mrow "1 docker login ghcr.io restored in cloud-init-inngest.yml" cloud-init-inngest.yml
# 2: || echo '${image_name}' restored on ONE of the three sentinel reads (the second member)
py_edit cloud-init.yml "(lambda k: s[:k] + s[k:].replace('\"\$(cat /run/soleur-image-ref)\"', '\"\$(cat /run/soleur-image-ref 2>/dev/null || echo ' + chr(39) + '\${image_name}' + chr(39) + ')\"', 1))(s.index('\"\$(cat /run/soleur-image-ref)\"') + 1)"
mrow "2 || echo '\${image_name}' restored on the 2nd of 3 sentinel reads" cloud-init.yml
# 3: ghcr_read_token back in inngest-host.tf's templatefile map only
py_edit inngest-host.tf "s.replace('templatefile(\"\${path.module}/cloud-init-inngest.yml\", {\n', 'templatefile(\"\${path.module}/cloud-init-inngest.yml\", {\n    ghcr_read_token = var.ghcr_read_token\n', 1)"
mrow "3 ghcr_read_token restored in inngest-host.tf's templatefile map" inngest-host.tf
# 4: the GHCR fallback put back as a pull of the pin carrier BEFORE IREF=\"\$ZIREF\" (web colocated block)
py_edit cloud-init.yml "(lambda i: s[:s.index(chr(10), i) + 1] + '    if ! docker pull \"\$ZIREF\"; then docker pull \"\$IREF\"; fi' + chr(10) + s[s.index(chr(10), i) + 1:])(s.index('    IREF=ghcr.io/'))"
mrow "4 pull of the IREF pin carrier before IREF=\"\$ZIREF\" (web colocated block)" cloud-init.yml
# 4b: same, second site: the dedicated inngest template
py_edit cloud-init-inngest.yml "(lambda i: s[:s.index(chr(10), i) + 1] + '    if ! docker pull \"\$ZIREF\"; then docker pull \"\$IREF\"; fi' + chr(10) + s[s.index(chr(10), i) + 1:])(s.index('    IREF=ghcr.io/'))"
mrow "4b pull of the IREF pin carrier before IREF=\"\$ZIREF\" (dedicated inngest template)" cloud-init-inngest.yml
# 5: dispatch rows — a misspelled path, and an empty list, must never read as "0 found, green"
sandbox
if dispatch_ok "$(census "$SB" "cloud-init.yml,soleur-host-bootstrap.sh,cloud-init-ingest.yml")"; then no "G1 mutation SURVIVED: 5 misspelled boot-file path"
else ok "G1 mutation RED: 5 misspelled boot-file path ($DWHY)"; fi
if dispatch_ok "$(census "$SB" "" "")"; then no "G1 mutation SURVIVED: 5b empty file list"
else ok "G1 mutation RED: 5b empty file list ($DWHY)"; fi
# 6 (must-PASS harness row): a comment naming the retired call form is not a call
printf '    # docker login ghcr.io was removed by #8036 1d\n' >> "$SB/cloud-init.yml"
landed cloud-init.yml
n=$(new_viols)
if [ -z "$n" ]; then ok "G1 harness PASS: 6 a comment line naming 'docker login ghcr.io' is stripped before the census"
else no "G1 harness: 6 a comment line was counted as code: $n"; fi
sandbox
# 7: a ghcr.io occurrence that is neither the pin carrier nor the seed case pattern
printf '    echo "fallback: ghcr.io/jikig-ai/soleur-web-platform"\n' >> "$SB/soleur-host-bootstrap.sh"
mrow "7 a stray ghcr.io code line in soleur-host-bootstrap.sh" soleur-host-bootstrap.sh
# 8: a third soleur-inngest-bootstrap ref (a re-homed comment quoting the full ref) breaks the bump bot
printf '  # was ghcr.io/jikig-ai/soleur-inngest-bootstrap:v1.1.37\n' >> "$SB/cloud-init.yml"
mrow "8 a comment quoting a 3rd full soleur-inngest-bootstrap ref (bump bot expects exactly 2)" cloud-init.yml

echo "=== cloud-init-ghcr-seed-login: $pass passed, $fail failed ==="
[ "$fail" -eq 0 ]
