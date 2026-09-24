#!/usr/bin/env bash
#
# Gate for the #8705 rotation of doppler_service_token.web_probes (Doppler "web-probes-read-*",
# soleur/prd, read), whose first token is held by retained web-1 snapshot image 411798619.
#
#   Guard 1 — every provisioner consumer of the key re-fires on rotation. Every reference to
#     doppler_service_token.web_probes in apps/web-platform/infra/*.tf sits in (a) a
#     resource "terraform_data" block whose OWN triggers_replace contains
#     sha256(doppler_service_token.web_probes.key), (b) the ONE web_probes_token argument of
#     resource "hcloud_server" "web" (the fresh-host templatefile), or (c) the defining block.
#     Anything else would keep the old key after a rotation, silently.
#   Guard 2 — the token keeps lifecycle { create_before_destroy = true }, so a failed create never
#     lands after the delete (no live token anywhere).
#   Guard 3 — scripts/web-probes-token-rotation-verify.sh prints ROTATED only on positive evidence.
#
# Rows grade RED only on checker exit 1 WITH the expected message; exit 2 is "instrument broken, not
# evidence" and fails the row. Every mutation is applied to a temp copy, block-scoped, and confirmed
# to have changed the copy before it is graded. C0 rows run the unmutated copy (a checker that always
# exits 1 would otherwise pass every RED row). The battery runs in the default invocation, so the one
# registered CI step executes it (#7942: a battery that runs in no gate).
#
# FLOOR NOTE: Guard 1's hash-bearing floor (4) encodes today's probe count — nic-guard, zot-consumer,
# inngest-consumer, git-data. Retiring a probe on purpose means editing that floor on purpose.
# Targeting of those installers in the post-bridge SSH stage is plugins/soleur/test/
# terraform-target-parity.test.ts Guard 1, not re-checked here.
#
# Run from the repo root: bash apps/web-platform/infra/web-probes-token-rotation.test.sh
set -euo pipefail

INFRA="apps/web-platform/infra"
VERIFY="$INFRA/scripts/web-probes-token-rotation-verify.sh"
LINT="scripts/lint-doppler-description-length.py"
SELF="$INFRA/web-probes-token-rotation.test.sh"
[[ -f "$INFRA/web-probe-read-token.tf" && -f "$LINT" ]] || { echo "FAIL - run from the repo root"; exit 1; }

pass=0
fail=0
cases=0
ok() { pass=$((pass + 1)); printf 'ok   - %s\n' "$1"; }
no() { fail=$((fail + 1)); printf 'FAIL - %s\n' "$1"; }

# Instrument self-test: both helpers must move their counter, or every verdict below is noise.
ok "instrument self-test (pass arm)" > /dev/null
no "instrument self-test (fail arm)" > /dev/null
if [[ "$pass" -ne 1 || "$fail" -ne 1 ]]; then
  printf 'FATAL: verdict helpers are broken (pass=%s fail=%s)\n' "$pass" "$fail"
  exit 2
fi
pass=0
fail=0

export TMPDIR="${TMPDIR:-/var/tmp}"
SCRATCH="$(mktemp -d -t wp-token-rotation.XXXXXXXX)"
trap 'rm -rf "$SCRATCH"' EXIT INT TERM HUP
# The canonical fixture-dir assertion, byte-equal to the definition in
# plugins/soleur/test/test-helpers.sh (that file also defines assert_eq/PASS/FAIL
# counters this suite owns itself, so it is copied rather than sourced).
# plugins/soleur/test/fixture-dir-operand-assert.test.sh compares every copy in the
# tree against that one with comments stripped — edit there, then re-sync here.
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
mkdir -p "$SCRATCH/pristine" "$SCRATCH/g3" "$SCRATCH/bin"
cp "$INFRA"/*.tf "$SCRATCH/pristine/"
CHECK="$SCRATCH/check.py"
MUT="$SCRATCH/mut.py"

# --- the checker ----------------------------------------------------------------------------------
# python3 check.py g1|g2 <dir> <lint.py>. Exit 0 PASS, 1 violation (named-block message), 2 instrument.
cat > "$CHECK" <<'PY'
import glob
import importlib.util
import os
import re
import sys

REF_PARTS = ("doppler_service_token", "web_probes")  # REF-MATCHER
REF_RE = re.compile(r"\b" + re.escape(REF_PARTS[0]) + r"\s*\.\s*" + re.escape(REF_PARTS[1]) + r"\b")
HASH_SEQ = [("ID", "sha256"), ("OPEN", "("), ("ID", REF_PARTS[0]), ("OTHER", "."),
            ("ID", REF_PARTS[1]), ("OTHER", "."), ("ID", "key"), ("CLOSE", ")")]
FLOOR_HASH = 4


def load(path):
    spec = importlib.util.spec_from_file_location("lint_doppler_description_length", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod.tokenize


def top_blocks(toks):
    """Top-level blocks as (labels, body tokens); tokens outside any block are returned as stray."""
    out, stray, k, n = [], [], 0, len(toks)
    while k < n:
        kind, val = toks[k][0], toks[k][1]
        if kind == "ID":
            j, labels = k + 1, [val]
            while j < n and toks[j][0] in ("ID", "STR"):
                labels.append(toks[j][1])
                j += 1
            if j < n and toks[j][:2] == ("OPEN", "{"):
                depth, b = 1, j + 1
                while b < n and depth:
                    if toks[b][0] == "OPEN":
                        depth += 1
                    elif toks[b][0] == "CLOSE":
                        depth -= 1
                    b += 1
                if depth:
                    raise ValueError(f"unclosed block {' '.join(labels)}")
                out.append((labels, toks[j + 1:b - 1]))
                k = b
                continue
        if kind != "NL":
            stray.append(toks[k])
        k += 1
    return out, stray


def references(body):
    """(filtered tokens, hits). NL is dropped inside ( and [ so a split reference still matches."""
    filt, depth = [], 0
    for t in body:
        if t[0] == "OPEN" and t[1] in "([":
            depth += 1
        elif t[0] == "CLOSE" and t[1] in ")]":
            depth = max(0, depth - 1)
        if t[0] == "NL" and depth > 0:
            continue
        filt.append(t)
    hits = []
    for i, t in enumerate(filt):
        if (t[:2] == ("ID", REF_PARTS[0]) and i + 2 < len(filt)
                and filt[i + 1][:2] == ("OTHER", ".") and filt[i + 2][:2] == ("ID", REF_PARTS[1])):
            hits.append(("id", i))
        elif t[0] == "STR" and t[3]:
            hits += [("str", i)] * len(REF_RE.findall(t[1]))
        elif t[0] == "HEREDOC":
            hits += [("heredoc", i)] * len(REF_RE.findall(t[1]))
    return filt, hits


def attribute(filt, name):
    """Expression tokens of a top-level attribute of this block body, or None."""
    depth = 0
    for k, t in enumerate(filt):
        if depth == 0 and t[:2] == ("ID", name) and k + 1 < len(filt) and filt[k + 1][0] == "EQ":
            expr, d = [], 0
            for u in filt[k + 2:]:
                if u[0] == "NL" and d == 0:
                    break
                if u[0] == "OPEN":
                    d += 1
                elif u[0] == "CLOSE":
                    d -= 1
                if u[0] != "NL":
                    expr.append(u)
            return expr
        if t[0] == "OPEN":
            depth += 1
        elif t[0] == "CLOSE":
            depth -= 1
    return None


def has_seq(expr, seq):
    pairs = [t[:2] for t in expr]
    return any(pairs[i:i + len(seq)] == seq for i in range(len(pairs) - len(seq) + 1))


def name_of(labels):
    if labels[0] in ("resource", "data") and len(labels) == 3:
        return ("data." if labels[0] == "data" else "") + f"{labels[1]}.{labels[2]}"
    return " ".join(labels)


def category(labels):
    if labels == ["resource", "doppler_service_token", "web_probes"]:
        return "definition"
    if labels == ["resource", "hcloud_server", "web"]:
        return "exception"
    if labels[:2] == ["resource", "terraform_data"] and len(labels) == 3:
        return "hash"
    return "other"


def block_problems(cat, name, filt, hits):
    if cat == "hash":
        expr = attribute(filt, "triggers_replace")
        if expr is None or not has_seq(expr, HASH_SEQ):
            return [f"G1 {name}: no sha256(doppler_service_token.web_probes.key) in triggers_replace"]
        return []
    if cat == "exception":
        if len(hits) == 1 and hits[0][0] == "id":
            i = hits[0][1]
            if i >= 2 and filt[i - 1][0] == "EQ" and filt[i - 2][:2] == ("ID", "web_probes_token"):
                return []
        return [f"G1 {name}: {len(hits)} reference(s); only the web_probes_token templatefile argument is allowed"]
    return [f"G1 {name}: reference outside the allowed blocks"]


def g1(root, tokenize):
    counts = {"hash": 0, "exception": 0, "definition": 0, "other": 0}
    violations = []
    for path in sorted(glob.glob(os.path.join(root, "*.tf"))):
        with open(path, encoding="utf-8") as fh:
            blocks, stray = top_blocks(tokenize(fh.read()))
        if references(stray)[1]:
            violations.append(f"G1 {os.path.basename(path)}: reference outside any block")
        for labels, body in blocks:
            cat = category(labels)
            if cat == "definition":
                counts["definition"] += 1
                continue
            filt, hits = references(body)
            if not hits:
                continue
            problems = block_problems(cat, name_of(labels), filt, hits)  # PER-BLOCK-CHECK
            if problems:
                violations += problems
            else:
                counts[cat] += 1
    print(f"G1 FLOORS hash={counts['hash']} exception={counts['exception']} definition={counts['definition']}")
    if counts["hash"] < FLOOR_HASH:
        violations.append(f"G1 floor: hash-bearing terraform_data blocks {counts['hash']} < {FLOOR_HASH}")
    if counts["exception"] != 1:
        violations.append(f"G1 floor: hcloud_server.web exception arguments {counts['exception']} != 1")
    if counts["definition"] != 1:
        violations.append(f"G1 floor: doppler_service_token.web_probes definitions {counts['definition']} != 1")
    for v in violations:
        print(v)
    return 1 if violations else 0


def g2(root, tokenize):
    defs = []
    for path in sorted(glob.glob(os.path.join(root, "*.tf"))):
        with open(path, encoding="utf-8") as fh:
            blocks, _ = top_blocks(tokenize(fh.read()))
        defs += [body for labels, body in blocks if labels == ["resource", "doppler_service_token", "web_probes"]]
    if len(defs) != 1:
        print(f"G2 doppler_service_token.web_probes: {len(defs)} definition(s), want exactly 1")
        return 1
    body, depth, k, found = defs[0], 0, 0, False
    while k < len(body):
        t = body[k]
        if depth == 0 and t[:2] == ("ID", "lifecycle") and k + 1 < len(body) and body[k + 1][:2] == ("OPEN", "{"):
            j, d = k + 2, 1
            while j < len(body) and d:
                u = body[j]
                if u[0] == "OPEN":
                    d += 1
                elif u[0] == "CLOSE":
                    d -= 1
                elif (d == 1 and u[:2] == ("ID", "create_before_destroy") and j + 2 < len(body)
                      and body[j + 1][0] == "EQ" and body[j + 2][:2] == ("ID", "true")):
                    found = True
                j += 1
            k = j
            continue
        if t[0] == "OPEN":
            depth += 1
        elif t[0] == "CLOSE":
            depth -= 1
        k += 1
    if not found:
        print("G2 doppler_service_token.web_probes: no lifecycle { create_before_destroy = true } in its own block")
        return 1
    print("G2 OK doppler_service_token.web_probes keeps create_before_destroy")
    return 0


try:
    guard, root, lint = sys.argv[1:4]
    tokenize = load(lint)
    sys.exit({"g1": g1, "g2": g2}[guard](root, tokenize))
except Exception as e:  # noqa: BLE001 - a broken instrument is exit 2, never evidence
    print(f"{sys.argv[1] if len(sys.argv) > 1 else '?'} INSTRUMENT {type(e).__name__}: {e}")
    sys.exit(2)
PY

# --- block-scoped mutations -----------------------------------------------------------------------
# python3 mut.py <copy-dir> <id>. Exit 3 when an anchor is missing or ambiguous (mutation did not apply).
cat > "$MUT" <<'PY'
import os
import sys

d, mid = sys.argv[1], sys.argv[2]
HASH = "nonsensitive(sha256(doppler_service_token.web_probes.key)),"
HDR = {
    "nic": 'resource "terraform_data" "private_nic_guard_install" {',
    "inngest": 'resource "terraform_data" "inngest_consumer_probe_install" {',
    "gitdata": 'resource "terraform_data" "git_data_probe_install" {',
    "server": 'resource "hcloud_server" "web" {',
    "def": 'resource "doppler_service_token" "web_probes" {',
}


def die(msg):
    print(f"MUTATION-ANCHOR: {msg}")
    sys.exit(3)


def rd(f):
    with open(os.path.join(d, f), encoding="utf-8") as fh:
        return fh.read().split("\n")


def wr(f, lines):
    with open(os.path.join(d, f), "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines))


def scope(lines, key):
    starts = [i for i, l in enumerate(lines) if l == HDR[key]]
    if len(starts) != 1:
        die(f"{key} header matched {len(starts)} times")
    for e in range(starts[0] + 1, len(lines)):
        if lines[e] == "}":
            return starts[0], e
    die(f"{key} has no closing brace")


def one(lines, s, e, pred, what):
    hits = [i for i in range(s, e + 1) if pred(lines[i])]
    if len(hits) != 1:
        die(f"{what}: {len(hits)} hits in scope")
    return hits[0]


def lifecycle(lines):
    s, e = scope(lines, "def")
    i = one(lines, s, e, lambda l: l == "  lifecycle {", "lifecycle open")
    if lines[i + 1] != "    create_before_destroy = true" or lines[i + 2] != "  }":
        die("lifecycle block is not the canonical three lines")
    return s, e, i


ROGUE = [
    'resource "terraform_data" "rogue_probe_install" {',
    '  triggers_replace = sha256(file("${path.module}/web-probe-read-token.tf"))',
    '  provisioner "remote-exec" {',
    '    inline = [',
    """      "printf 'DOPPLER_TOKEN=%s\\\\n' '${doppler_service_token.web_probes.key}' > /etc/default/rogue",""",
    '    ]',
    '  }',
    '}',
]
HEREDOC = [
    'resource "terraform_data" "heredoc_probe_install" {',
    '  triggers_replace = sha256("static")',
    '  provisioner "remote-exec" {',
    '    inline = [<<-EOT',
    "      printf 'DOPPLER_TOKEN=%s' '${doppler_service_token.web_probes.key}' > /etc/default/heredoc",
    '    EOT',
    '    ]',
    '  }',
    '}',
]
SPLIT = [
    'resource "terraform_data" "split_probe_install" {',
    '  triggers_replace = sha256("static")',
    '  input = (doppler_service_token',
    '  .web_probes.key)',
    '}',
]
SYNTH = [
    'resource "doppler_service_token" "synthetic" {',
    '  project = "soleur"',
    '  config  = "prd"',
    '  name    = "synthetic-fixture"',
    '  access  = "read"',
    '',
    '  lifecycle {',
    '    create_before_destroy = true',
    '  }',
    '}',
]

S, T = "server.tf", "web-probe-read-token.tf"
if mid == "g1r1":
    L = rd(S); s, e = scope(L, "gitdata"); del L[one(L, s, e, lambda l: l.strip() == HASH, "hash line")]; wr(S, L)
elif mid == "g1r3":
    wr(S, rd(S) + [""] + ROGUE)
elif mid == "g1r4":
    L = rd(S); s, e = scope(L, "gitdata"); i = one(L, s, e, lambda l: l.strip() == HASH, "hash line")
    L[i] = L[i].replace("nonsensitive(", "# nonsensitive(", 1); wr(S, L)
elif mid == "g1r5":
    wr(T, rd(T) + ["", "locals {", "  probe_tok = doppler_service_token.web_probes.key", "}"])
elif mid == "g1r6":
    wr(S, rd(S) + [""] + HEREDOC)
elif mid == "g1r7":
    L = rd(S); s, e = scope(L, "gitdata"); i = one(L, s, e, lambda l: l.strip() == HASH, "hash line")
    del L[i]
    j = one(L, s, e - 1, lambda l: l == "  ]))", "triggers_replace close")
    L.insert(j + 1, "  input = nonsensitive(sha256(doppler_service_token.web_probes.key))"); wr(S, L)
elif mid == "g1r8":
    L = rd(S); s, e = scope(L, "inngest"); del L[s:e + 1]; wr(S, L)
elif mid == "g1r9":
    L = rd(S); s, e = scope(L, "server")
    L[e:e] = ['  provisioner "remote-exec" {', '    inline = ["echo ${doppler_service_token.web_probes.key}"]', "  }"]
    wr(S, L)
elif mid == "g1r10":
    wr(S, rd(S) + [""] + SPLIT)
elif mid == "g1h1":
    L = rd(S); s, e = scope(L, "nic")
    a = one(L, s, e, lambda l: l == '  triggers_replace = sha256(join(",", [', "triggers_replace open")
    b = one(L, a, e, lambda l: l == "  ]))", "triggers_replace close")
    L[a:b + 1] = ["  triggers_replace = nonsensitive(sha256(doppler_service_token.web_probes.key))"]; wr(S, L)
elif mid == "g1s1":
    wr(T, rd(T) + ["", 'locals { x = "unterminated'])
elif mid == "g2r1":
    L = rd(T); s, e, i = lifecycle(L); del L[i:i + 3]; wr(T, L)
elif mid == "g2r2":
    L = rd(T); s, e, i = lifecycle(L); L[i + 1] = "    create_before_destroy = false"; wr(T, L)
elif mid == "g2r3":
    L = rd(T); s, e, i = lifecycle(L)
    for k in range(i, i + 3):
        L[k] = "#" + L[k]
    wr(T, L)
elif mid == "g2r4":
    L = rd(T); s, e = scope(L, "def"); L[s] = 'resource "doppler_service_token" "web_probes_renamed" {'; wr(T, L)
elif mid == "g2r5":
    L = rd(T); s, e, i = lifecycle(L); del L[i:i + 3]; wr(T, L + [""] + SYNTH)
elif mid == "g2r6":
    L = rd(T); s, e = scope(L, "def"); wr(T, L + [""] + L[s:e + 1])
elif mid == "g2h1a":
    L = rd(T); s, e, i = lifecycle(L); L[i:i + 3] = ["  lifecycle { create_before_destroy = true }"]; wr(T, L)
elif mid == "g2h1b":
    L = rd(T); s, e, i = lifecycle(L)
    L[i:i + 3] = ["  lifecycle {", "", "    create_before_destroy   =   true", "", "  }"]; wr(T, L)
else:
    die(f"unknown mutation {mid}")
PY

# A fresh copy of the pristine .tf set, optionally mutated. Prints the copy's path; exits 3 when the
# mutation's anchor is missing and 4 when the copy did not change (a mutation that did not apply
# grades the BASELINE, which is indistinguishable from a pass).
copy_tree() {
  local name="$1" mid="${2-}" d rc
  d="$SCRATCH/m-$name"
  assert_fixture_dir "$d"
  rm -rf "$d"
  mkdir -p "$d"
  cp "$SCRATCH/pristine"/*.tf "$d/"
  if [[ -n "$mid" ]]; then
    python3 "$MUT" "$d" "$mid" > "$d.mut.log" 2>&1 || return 3
    rc=0
    diff -rq "$SCRATCH/pristine" "$d" > /dev/null 2>&1 || rc=$?
    [[ "$rc" -eq 1 ]] || return 4
  fi
  printf '%s' "$d"
}

# g_row <label> <g1|g2> <mutation-id|-> <pass|red> [<regex the output must match>]
g_row() {
  local label="$1" guard="$2" mid="$3" want="$4" re="${5-}" d out rc
  [[ "$mid" == "-" ]] && mid=""
  rc=0
  d="$(copy_tree "$label" "$mid")" || rc=$?
  if [[ "$rc" -ne 0 ]]; then
    no "$label (mutation did not apply: rc=$rc)"
    return 0
  fi
  rc=0
  out="$(python3 "$CHECK" "$guard" "$d" "$LINT" 2>&1)" || rc=$?
  if [[ "$want" == pass ]]; then
    if [[ "$rc" -eq 0 ]]; then ok "$label"; else no "$label (want PASS; rc=$rc: ${out//$'\n'/ | })"; fi
  elif [[ "$rc" -eq 1 ]] && grep -qE -- "$re" <<< "$out"; then
    ok "$label"
  else
    no "$label (want exit 1 + /$re/; rc=$rc: ${out//$'\n'/ | })"
  fi
}

# --- Guard 1: the live tree and its floors --------------------------------------------------------
rc=0
out="$(python3 "$CHECK" g1 "$INFRA" "$LINT" 2>&1)" || rc=$?
cases=$((cases + 1))
if [[ "$rc" -eq 0 ]]; then ok "G1 live tree: every web_probes reference sits in an allowed block"; else no "G1 live tree (rc=$rc: ${out//$'\n'/ | })"; fi
f_hash=-1
f_exc=-1
f_def=-1
if [[ "$out" =~ G1\ FLOORS\ hash=([0-9]+)\ exception=([0-9]+)\ definition=([0-9]+) ]]; then
  f_hash="${BASH_REMATCH[1]}"
  f_exc="${BASH_REMATCH[2]}"
  f_def="${BASH_REMATCH[3]}"
fi
cases=$((cases + 1))
if [[ "$f_hash" -ge 4 ]]; then ok "G1 floor: hash-bearing terraform_data blocks = $f_hash (>= 4)"; else no "G1 floor: hash-bearing terraform_data blocks = $f_hash (want >= 4)"; fi
cases=$((cases + 1))
if [[ "$f_exc" -eq 1 ]]; then ok "G1 floor: hcloud_server.web exception arguments = $f_exc (== 1)"; else no "G1 floor: hcloud_server.web exception arguments = $f_exc (want 1)"; fi
cases=$((cases + 1))
if [[ "$f_def" -eq 1 ]]; then ok "G1 floor: doppler_service_token.web_probes definitions = $f_def (== 1)"; else no "G1 floor: doppler_service_token.web_probes definitions = $f_def (want 1)"; fi

# --- Guard 1: control, must-PASS, and the mutation battery ----------------------------------------
cases=$((cases + 1)); g_row "G1-C0 unmutated copy passes" g1 - pass
cases=$((cases + 1)); g_row "G1-H1 bare triggers_replace = nonsensitive(sha256(key)) passes" g1 g1h1 pass
cases=$((cases + 1)); g_row "G1-R1 hash deleted from git_data_probe_install" g1 g1r1 red '^G1 terraform_data\.git_data_probe_install: no sha256'
cases=$((cases + 1)); g_row "G1-R3 a fifth terraform_data interpolates the key with no hash" g1 g1r3 red '^G1 terraform_data\.rogue_probe_install: no sha256'
cases=$((cases + 1)); g_row "G1-R4 the hash moved into a comment" g1 g1r4 red '^G1 terraform_data\.git_data_probe_install: no sha256'
cases=$((cases + 1)); g_row "G1-R5 a locals alias of the key" g1 g1r5 red '^G1 locals: reference outside the allowed blocks'
cases=$((cases + 1)); g_row "G1-R6 the only reference is inside a heredoc" g1 g1r6 red '^G1 terraform_data\.heredoc_probe_install: no sha256'
cases=$((cases + 1)); g_row "G1-R7 the hash moved from triggers_replace into input" g1 g1r7 red '^G1 terraform_data\.git_data_probe_install: no sha256'
cases=$((cases + 1)); g_row "G1-R8 inngest_consumer_probe_install deleted" g1 g1r8 red '^G1 floor: hash-bearing terraform_data blocks 3 < 4'
cases=$((cases + 1)); g_row "G1-R9 a second reference inside hcloud_server.web" g1 g1r9 red '^G1 hcloud_server\.web: 2 reference'
cases=$((cases + 1)); g_row "G1-R10 a reference split across lines inside parentheses" g1 g1r10 red '^G1 terraform_data\.split_probe_install: no sha256'

# R1 must name exactly ONE block: the scoped delete must not bleed into the three identical siblings.
cases=$((cases + 1))
rc=0
d="$(copy_tree "G1-R1-count" g1r1)" || rc=$?
n=-1
if [[ "$rc" -eq 0 ]]; then
  out="$(python3 "$CHECK" g1 "$d" "$LINT" 2>&1)" || true
  n="$(grep -cE '^G1 terraform_data\.' <<< "$out" || true)"
fi
if [[ "$n" -eq 1 ]]; then ok "G1-R1 names exactly one block violation"; else no "G1-R1 names exactly one block violation (got $n, copy rc=$rc)"; fi

# R2: guard dispatch. An empty directory, and a matcher broken so it matches nothing, both trip the floors.
cases=$((cases + 1))
mkdir -p "$SCRATCH/empty"
rc=0
out="$(python3 "$CHECK" g1 "$SCRATCH/empty" "$LINT" 2>&1)" || rc=$?
if [[ "$rc" -eq 1 ]] && grep -qE '^G1 floor: hash-bearing terraform_data blocks 0 < 4' <<< "$out"; then
  ok "G1-R2a an empty directory trips the floors"
else
  no "G1-R2a an empty directory trips the floors (rc=$rc: ${out//$'\n'/ | })"
fi
cases=$((cases + 1))
sed 's/^REF_PARTS = ("doppler_service_token", "web_probes")  # REF-MATCHER$/REF_PARTS = ("no_such_type", "no_such_label")  # REF-MATCHER/' "$CHECK" > "$SCRATCH/check-broken.py"
rc=0
if cmp -s "$CHECK" "$SCRATCH/check-broken.py"; then
  no "G1-R2b a matcher that matches nothing trips the floors (mutation did not apply)"
else
  out="$(python3 "$SCRATCH/check-broken.py" g1 "$INFRA" "$LINT" 2>&1)" || rc=$?
  if [[ "$rc" -eq 1 ]] && grep -qE '^G1 floor: hash-bearing terraform_data blocks 0 < 4' <<< "$out"; then
    ok "G1-R2b a matcher that matches nothing trips the floors"
  else
    no "G1-R2b a matcher that matches nothing trips the floors (rc=$rc: ${out//$'\n'/ | })"
  fi
fi

# S1: a file the tokenizer cannot scan is exit 2 (instrument), never a pass and never a skip.
cases=$((cases + 1))
rc=0
d="$(copy_tree "G1-S1" g1s1)" || rc=$?
if [[ "$rc" -eq 0 ]]; then
  rc=0
  out="$(python3 "$CHECK" g1 "$d" "$LINT" 2>&1)" || rc=$?
  if [[ "$rc" -eq 2 ]] && grep -qE '^g1 INSTRUMENT ScanError' <<< "$out"; then ok "G1-S1 an unscannable file is exit 2 (ScanError), not a pass"; else no "G1-S1 an unscannable file is exit 2 (rc=$rc: ${out//$'\n'/ | })"; fi
else
  no "G1-S1 an unscannable file is exit 2 (mutation did not apply: rc=$rc)"
fi

# H2: the battery must be able to fail. Run a copy of THIS suite whose per-block check is stubbed to
# always return ok; the inner run must report the per-block rows as not caught.
if [[ -z "${WPTR_INNER:-}" ]]; then
  sed 's/^            problems = block_problems(cat, name_of(labels), filt, hits)  # PER-BLOCK-CHECK$/            problems = []  # PER-BLOCK-CHECK/' "$SELF" > "$SCRATCH/suite-stubbed.sh"
  cases=$((cases + 1))
  if cmp -s "$SELF" "$SCRATCH/suite-stubbed.sh"; then
    no "G1-H2 the per-block stub applied to the suite copy"
  else
    ok "G1-H2 the per-block stub applied to the suite copy"
  fi
  inner="$(WPTR_INNER=1 bash "$SCRATCH/suite-stubbed.sh" 2>&1 || true)"
  for r in R1 R3 R5 R6 R7 R9; do
    cases=$((cases + 1))
    if grep -qE "^FAIL - G1-$r " <<< "$inner"; then
      ok "G1-H2 with the per-block check stubbed, G1-$r is not caught"
    else
      no "G1-H2 with the per-block check stubbed, G1-$r is not caught (the row passes without the check it claims to test)"
    fi
  done
fi

# --- Guard 2 ---------------------------------------------------------------------------------------
cases=$((cases + 1))
rc=0
out="$(python3 "$CHECK" g2 "$INFRA" "$LINT" 2>&1)" || rc=$?
if [[ "$rc" -eq 0 ]]; then ok "G2 live tree: web_probes keeps create_before_destroy"; else no "G2 live tree (rc=$rc: ${out//$'\n'/ | })"; fi
cases=$((cases + 1)); g_row "G2-C0 unmutated copy passes" g2 - pass
cases=$((cases + 1)); g_row "G2-H1a lifecycle written on one line passes" g2 g2h1a pass
cases=$((cases + 1)); g_row "G2-H1b lifecycle spread across several lines passes" g2 g2h1b pass
cases=$((cases + 1)); g_row "G2-R1 lifecycle removed" g2 g2r1 red '^G2 doppler_service_token\.web_probes: no lifecycle'
cases=$((cases + 1)); g_row "G2-R2 create_before_destroy = false" g2 g2r2 red '^G2 doppler_service_token\.web_probes: no lifecycle'
cases=$((cases + 1)); g_row "G2-R3 lifecycle commented out" g2 g2r3 red '^G2 doppler_service_token\.web_probes: no lifecycle'
cases=$((cases + 1)); g_row "G2-R4 resource label renamed (0 definitions)" g2 g2r4 red '^G2 doppler_service_token\.web_probes: 0 definition'
cases=$((cases + 1)); g_row "G2-R5 lifecycle moved to a sibling resource in the same file" g2 g2r5 red '^G2 doppler_service_token\.web_probes: no lifecycle'
cases=$((cases + 1)); g_row "G2-R6 block duplicated (2 definitions)" g2 g2r6 red '^G2 doppler_service_token\.web_probes: 2 definition'

# --- Guard 3: the rotation verifier -------------------------------------------------------------
STUB_LOG="$SCRATCH/stub"
mkdir -p "$STUB_LOG"
# Recorders for the verifier's two external calls. curl writes a body chosen by WPTR_CURL_MODE and
# records its argv, whether the -K config carried the sentinel (positive control: the header WAS
# delivered, off argv) and whether DOPPLER_TOKEN_TF reached its environment.
cat > "$SCRATCH/bin/curl" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$STUB_LOG/curl.argv"
out=""
cfg=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o) out="$2"; shift 2 ;;
    -K) cfg="$2"; shift 2 ;;
    *) shift ;;
  esac
done
if [[ -n "$cfg" && -n "${WPTR_SENTINEL:-}" ]] && grep -qF -- "Authorization: Bearer $WPTR_SENTINEL" "$cfg"; then
  echo yes > "$STUB_LOG/curl.header"
else
  echo no > "$STUB_LOG/curl.header"
fi
if [[ -n "${DOPPLER_TOKEN_TF:-}" ]]; then echo yes > "$STUB_LOG/curl.env"; else echo no > "$STUB_LOG/curl.env"; fi
case "${WPTR_CURL_MODE:-}" in
  exit22) exit 22 ;;
  body401) printf '{"messages":["Invalid Auth token"],"success":false}' > "$out"; exit 0 ;;
  ok) cat -- "$WPTR_CURL_BODY" > "$out"; exit 0 ;;
esac
exit 64
SH
cat > "$SCRATCH/bin/doppler" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB_LOG/doppler.argv"
if [[ -n "${WPTR_DOPPLER_OUT:-}" && "$*" == *"--project soleur-infra-privileged --config prd "* ]]; then
  printf '%s' "$WPTR_DOPPLER_OUT"
  exit 0
fi
exit 1
SH
chmod +x "$SCRATCH/bin/curl" "$SCRATCH/bin/doppler"
export STUB_LOG

# Synthesized and split across concatenation: a contiguous service-token-shaped literal trips GitHub
# push protection even though it is fake (cq-test-fixtures-synthesized-only).
SENTINEL="dp."'pt.'"FIXTURExSENTINELxWPTRxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
ROTATED_JSON='{"success":true,"tokens":[{"slug":"aaaa1111-fixture","name":"github-ci-prd","created_at":"2026-03-29T09:00:00.000Z"},{"slug":"bbbb2222-fixture","name":"web-probes-read-2026-09-24","created_at":"2026-09-24T13:00:00.456Z"},{"slug":"cccc3333-fixture","name":"web-probes-read-2027-01-15","created_at":"2027-01-15T10:00:00.123Z"}]}'

# v_row <label> <json> <want-word> <want-rc> [verifier args...] — fixture mode.
v_row() {
  local label="$1" json="$2" word="$3" want="$4" f out rc
  shift 4
  f="$SCRATCH/g3/${label%% *}.json"
  assert_fixture_dir "$SCRATCH"
  printf '%s' "$json" > "$f"
  rc=0
  out="$(WEB_PROBES_TOKEN_LIST_JSON="$f" PATH="$SCRATCH/bin:$PATH" bash "$VERIFY" "$@" 2>&1)" || rc=$?
  if [[ "$rc" -eq "$want" && "$out" == "$word: "*" (fixture)" && "$out" != *$'\n'* ]]; then
    ok "$label"
  else
    no "$label (want $word exit $want, one line ending (fixture); rc=$rc: ${out//$'\n'/ | })"
  fi
}

cases=$((cases + 1)); v_row "G3-R1 an empty tokens array is inconclusive" '{"tokens": []}' UNAVAILABLE 2
cases=$((cases + 1)); v_row "G3-R2a an empty object is inconclusive" '{}' UNAVAILABLE 2
cases=$((cases + 1)); v_row "G3-R2b a non-JSON body is inconclusive" 'not json at all' UNAVAILABLE 2
cases=$((cases + 1)); v_row "G3-R3 the retired slug still listed after a compliant replacement" \
  '{"tokens":[{"slug":"bbbb2222-fixture","name":"web-probes-read-2026-09-24","created_at":"2026-09-24T13:00:00Z"},{"slug":"01941a89-fixture","name":"web-probes-read","created_at":"2026-07-18T11:33:56.040Z"}]}' STALE 1
cases=$((cases + 1)); v_row "G3-R4 the replacement predates the cut-off" \
  '{"tokens":[{"slug":"bbbb2222-fixture","name":"web-probes-read-2026-07-20","created_at":"2026-07-20T00:00:00Z"}]}' MISSING 1
cases=$((cases + 1)); v_row "G3-R5 no token carries the prefix" \
  '{"tokens":[{"slug":"aaaa1111-fixture","name":"github-ci-prd","created_at":"2026-09-24T13:00:00Z"}]}' MISSING 1
cases=$((cases + 1)); v_row "G3-R6 a token without a slug is schema drift" \
  '{"tokens":[{"name":"web-probes-read-2026-09-24","created_at":"2026-09-24T13:00:00Z"}]}' UNAVAILABLE 2
cases=$((cases + 1)); v_row "G3-R7 a replacement created exactly at the cut-off is not later" \
  '{"tokens":[{"slug":"bbbb2222-fixture","name":"web-probes-read-x","created_at":"2026-07-23T15:34:04.000Z"}]}' MISSING 1
cases=$((cases + 1)); v_row "G3-R7b a paged listing is inconclusive" \
  '{"page":1,"tokens":[{"slug":"bbbb2222-fixture","name":"web-probes-read-2026-09-24","created_at":"2026-09-24T13:00:00Z"}]}' UNAVAILABLE 2
cases=$((cases + 1)); v_row "G3-H1 rotated listing with unrelated tokens and millisecond stamps" "$ROTATED_JSON" ROTATED 0
cases=$((cases + 1)); v_row "G3-P1 --retired-slug is honoured" \
  '{"tokens":[{"slug":"feedf00d-fixture","name":"web-probes-read-2026-09-24","created_at":"2026-09-24T13:00:00Z"}]}' STALE 1 --retired-slug feedf00d
cases=$((cases + 1)); v_row "G3-P2 --name-prefix and --not-before are honoured" \
  '{"tokens":[{"slug":"bbbb2222-fixture","name":"other-probe-2026-09-24","created_at":"2026-09-24T13:00:00Z"}]}' ROTATED 0 --name-prefix other-probe- --not-before 2026-09-01T00:00:00Z

cases=$((cases + 1))
rc=0
out="$(bash "$VERIFY" --not-before yesterday 2>&1)" || rc=$?
if [[ "$rc" -eq 2 && "$out" == usage:* ]]; then ok "G3-P3 a malformed --not-before is a usage error (exit 2)"; else no "G3-P3 a malformed --not-before is a usage error (rc=$rc: ${out//$'\n'/ | })"; fi

cases=$((cases + 1))
if [[ ! -e "$STUB_LOG/curl.argv" && ! -e "$STUB_LOG/doppler.argv" ]]; then
  ok "G3-F1 fixture mode fetched no credential and made no request"
else
  no "G3-F1 fixture mode fetched no credential and made no request"
fi

# Live path through the stubs. l_row <label> <want-word> <want-rc> <curl-mode> [env...]
l_row() {
  local label="$1" word="$2" want="$3" mode="$4" out rc
  shift 4
  rm -f "$STUB_LOG"/curl.* "$STUB_LOG"/doppler.argv
  rc=0
  out="$(env -u WEB_PROBES_TOKEN_LIST_JSON -u DOPPLER_TOKEN_TF PATH="$SCRATCH/bin:$PATH" WPTR_SENTINEL="$SENTINEL" \
    WPTR_CURL_MODE="$mode" WPTR_CURL_BODY="$SCRATCH/g3/live-rotated.json" "$@" bash "$VERIFY" 2>&1)" || rc=$?
  if [[ "$rc" -eq "$want" && "$out" == "$word: "* && "$out" != *"(fixture)"* && "$out" != *$'\n'* ]]; then
    ok "$label"
  else
    no "$label (want $word exit $want, one live line; rc=$rc: ${out//$'\n'/ | })"
  fi
  LAST_OUT="$out"
}
assert_fixture_dir "$SCRATCH"
printf '%s' "$ROTATED_JSON" > "$SCRATCH/g3/live-rotated.json"

# R9 for each live run: the sentinel is in neither stdout nor stderr nor curl's argv, and never in
# curl's environment; the -K config DID carry it (so the absence is not vacuous).
leak_rows() {
  local tag="$1"
  cases=$((cases + 1))
  # The argv file must EXIST: a missing file makes grep exit 2, and `!` would read that as clean.
  if [[ -f "$STUB_LOG/curl.argv" && "$LAST_OUT" != *"$SENTINEL"* ]] && ! grep -qF -- "$SENTINEL" "$STUB_LOG/curl.argv"; then
    ok "G3-R9 $tag: the credential is in no output and no curl argument"
  else
    no "G3-R9 $tag: the credential leaked into output or curl argv"
  fi
  cases=$((cases + 1))
  local hdr env_seen
  hdr="$(cat "$STUB_LOG/curl.header" 2>/dev/null || true)"
  env_seen="$(cat "$STUB_LOG/curl.env" 2>/dev/null || true)"
  if [[ "$hdr" == yes && "$env_seen" == no ]]; then
    ok "G3-R9 $tag: the header reached curl on its -K descriptor, and DOPPLER_TOKEN_TF did not reach its environment"
  else
    no "G3-R9 $tag: header=${hdr:-<curl not run>} env=${env_seen:-<curl not run>} (want yes/no)"
  fi
}

cases=$((cases + 1)); l_row "G3-R8a live: curl exits 22" UNAVAILABLE 2 exit22 DOPPLER_TOKEN_TF="$SENTINEL"
leak_rows "R8a"
cases=$((cases + 1)); l_row "G3-R8b live: a 401 body" UNAVAILABLE 2 body401 DOPPLER_TOKEN_TF="$SENTINEL"
leak_rows "R8b"
cases=$((cases + 1)); l_row "G3-L1 live: a rotated listing is ROTATED with no fixture marker" ROTATED 0 ok DOPPLER_TOKEN_TF="$SENTINEL"
leak_rows "L1"
cases=$((cases + 1))
argv="$(cat "$STUB_LOG/curl.argv" 2>/dev/null || true)"
if [[ "$argv" == *$'--max-time\n10'* && "$argv" == *"https://api.doppler.com/v3/configs/config/tokens?project=soleur&config=prd"* && ! -e "$STUB_LOG/doppler.argv" ]]; then
  ok "G3-L1 curl carried --max-time 10 and the prd listing URL; doppler was not called with the env token set"
else
  no "G3-L1 curl argv / doppler call (argv: ${argv//$'\n'/ })"
fi

cases=$((cases + 1)); l_row "G3-L2 no credential resolvable is inconclusive" UNAVAILABLE 2 ok
cases=$((cases + 1))
dargv="$(cat "$STUB_LOG/doppler.argv" 2>/dev/null || true)"
first="${dargv%%$'\n'*}"
if [[ "$first" == *"--project soleur-infra-privileged --config prd "*"--timeout 10s"* \
   && "$dargv" == *$'\n'*"--project soleur --config prd_terraform "*"--timeout 10s"* && ! -e "$STUB_LOG/curl.argv" ]]; then
  ok "G3-L2 Tier-B soleur-infra-privileged/prd is tried first, then soleur/prd_terraform, each with --timeout; curl never ran"
else
  no "G3-L2 credential resolution order (doppler argv: ${dargv//$'\n'/ / })"
fi
cases=$((cases + 1)); l_row "G3-L3 the Tier-B credential drives the live read" ROTATED 0 ok WPTR_DOPPLER_OUT="$SENTINEL"
leak_rows "L3"

cases=$((cases + 1))
rc=0
out="$(env -u WEB_PROBES_TOKEN_LIST_JSON PATH="$SCRATCH/bin:$PATH" DOPPLER_TOKEN_TF="$SENTINEL" bash -x "$VERIFY" 2>&1)" || rc=$?
if [[ "$rc" -eq 78 && "$out" != *"$SENTINEL"* && "$out" == *"refusing to run under xtrace"* ]]; then
  ok "G3-X1 under bash -x the verifier refuses (exit 78) and prints no credential"
else
  no "G3-X1 under bash -x the verifier refuses (rc=$rc)"
fi

# One verdict function: each verdict word appears once outside comments, the Python has one
# sys.exit, and no code path exits 0 outside it (the shell only ever exits 2 by itself).
python3 - "$VERIFY" > "$SCRATCH/static.tsv" <<'PY'
import re
import sys

src = open(sys.argv[1], encoding="utf-8").read().split("\n")
code = [l for l in src if not re.match(r"\s*#", l)]
text = "\n".join(code)
out = []


def check(name, cond, detail=""):
    out.append(("ok" if cond else "no", name, str(detail)))


for word in ("ROTATED", "STALE", "MISSING", "UNAVAILABLE"):
    n = len(re.findall(r"\b" + word + r"\b", text))
    check(f"G3-S1 the verdict word {word} appears exactly once outside comments", n == 1, n)
check("G3-S2 sys.exit appears exactly once (inside verdict())", len(re.findall(r"sys\.exit\(", text)) == 1)
check("G3-S3 no code path exits 0 by itself", not re.search(r"\bexit\s+0\b|sys\.exit\(0\)", text))
shell_exits = re.findall(r"(?<![.\w])exit\s+(\S+)", text)
check("G3-S4 every shell-level exit is exit 2, or 78 for the xtrace refusal",
      bool(shell_exits) and all(e.strip(";") in ("2", "78") for e in shell_exits), shell_exits)
check("G3-S5 the Authorization header is built only by printf into curl -K",
      "-K <(printf 'header = \"Authorization: Bearer %s\"\\n' \"$T\")" in text
      and not any("curl" in l and "Authorization" in l for l in code))
first_read = next((i for i, l in enumerate(code) if "DOPPLER_TOKEN_TF" in l), -1)
refusal = next((i for i, l in enumerate(code) if l.strip() == '*x*) printf \'[FATAL] refusing to run under xtrace: this script handles a live credential and -x would print it (see #7797)\\n\' >&2; exit 78 ;;'), -1)
check("G3-S6 the script refuses xtrace before any credential is read", 0 <= refusal < first_read, (refusal, first_read))
check("G3-S7 the credentialed curl starts with --disable --noproxy '*'",
      any(l.strip().startswith("curl --disable --noproxy '*' ") for l in code))
for k, v, _ in out:
    print(f"{k}\t{v}\t")
PY
while IFS=$'\t' read -r v name _; do
  [[ -n "${v:-}" ]] || continue
  cases=$((cases + 1))
  if [[ "$v" == ok ]]; then ok "$name"; else no "$name"; fi
done < "$SCRATCH/static.tsv"

printf '\n%s passed, %s failed (%s cases)\n' "$pass" "$fail" "$cases"

# Every case graded exactly once: a row that returned without calling ok/no, or called both, is a
# broken row, not a result.
if [[ $((pass + fail)) -ne "$cases" ]]; then
  printf 'FAIL - verdict accounting: pass+fail=%s but %s cases ran\n' "$((pass + fail))" "$cases"
  exit 1
fi

# Anti-vacuity floor. The threshold sits on the line directly above its `if`.
MIN_ASSERTIONS=76
if [[ "$pass" -lt "$MIN_ASSERTIONS" ]]; then
  printf 'FAIL - only %s assertions passed (floor %s) — a block stopped running\n' "$pass" "$MIN_ASSERTIONS"
  exit 1
fi
[[ "$fail" -eq 0 ]] || exit 1
