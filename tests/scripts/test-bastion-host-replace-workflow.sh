#!/usr/bin/env bash
# Wiring suite for the bastion REPLACE route's reusable body (#12879, ADR-327 step 2b; CTO ruling Q-R4).
#
# The gate, boot-verify and readiness libraries have their own suites. THIS suite pins that the
# workflow calls them the way their properties assume, in two ways:
#
#   STRUCTURE, from the PARSED workflow (python3 -I + yaml.safe_load, the way GitHub reads it):
#     1. the job's environment; no continue-on-error anywhere; no job-level if: (Q-R6); no run: block
#        interpolates ${{ }} (so the bodies executed below are the bytes the runner executes)
#     2. the step order by id (index comparisons), Require main first
#     3. the exact if: strings of the plan summary, toctou, boot_anchor, apply, verify, cancel_poweroff,
#        record_pin, summary and cleanup steps; no step before the plan summary carries an if:
#     4. comment-stripped, exactly one `terraform plan` and one `terraform apply` in the job (any flag
#        order, -chdir included); the apply's only positional argument is "$PLAN_DIR/tfplan"
#     5. every consumed steps.X.outputs.Y is written by step X (run text, the library it calls, or the
#        composite action's outputs:); every steps.X.outcome names a real step
#   BEHAVIOUR, by EXECUTING the real step bodies (extracted from the parsed workflow) under `env -i`
#   with a PATH that is ONLY a stub directory: stub terraform / doppler / curl / gh that record their
#   argv, a whitelist of real coreutils and jq, and a fake workspace whose gate and stock libraries
#   are recording stubs (boot-verify and bearer-curl are the real ones, so the TOCTOU re-read and the
#   cancel power-off run their real code against the stub curl). GITHUB_ACTIONS is never set, so the
#   libraries' test-only seams stay inert.
#     6. the main-only, tier_b, confirm and pin refusals exit non-zero; the confirm text never reaches
#        a workflow command; a gate ABORT and a stock refusal exit non-zero AND the stub log shows the
#        gate was called; every TOCTOU refusal (servers changed, firewall re-read, Q-R3) exits non-zero
#        and the success writes pre_ids from the FRESH read; the three private_key_* fields are masked
#        line by line; the cancel step records the library's own verdict (Q-R7) in BOTH workflows;
#        the summaries print one distinct line per cancel verdict and the Q-R7 next-dispatch lines.
#     7. mutation rows: one per wiring survivor the review found (SYNTHESIS section A) plus the Q-R3,
#        Q-R6 and Q-R7 changes. Each edits a temp copy EXACTLY ONCE (proved: count == 1 and the copy
#        differs) and must turn its named check RED. The unmutated control runs first and must be GREEN.
#
# Run: bash tests/scripts/test-bastion-host-replace-workflow.sh
# shellcheck disable=SC2016 # single-quoted programs and expected literals hold $-text on purpose
set -uo pipefail
unset GITHUB_ACTIONS
export TMPDIR="${TMPDIR:-/var/tmp}"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
RWF="$REPO/.github/workflows/bastion-host-replace.yml"
CWF="$REPO/.github/workflows/bastion-host-create.yml"
BASH_BIN="$(command -v bash)"
WORK="$(mktemp -d "${TMPDIR}/bhr-workflow.XXXXXXXX")"
trap 'rm -rf -- "$WORK"' EXIT

passes=0 fails=0 cases=0
pass() { cases=$((cases + 1)); passes=$((passes + 1)); printf '  ok   %s\n' "$1"; }
fail() { cases=$((cases + 1)); fails=$((fails + 1)); printf '  FAIL %s\n' "$1"; }

# ── Positive control: pass() and fail() each move their own counter and the case count ────────
pc="$(passes=0 fails=0 cases=0; pass x >/dev/null; fail y >/dev/null; printf '%s %s %s' "$passes" "$fails" "$cases")"
if [[ "$pc" == "1 1 2" ]]; then pass "positive control: pass() and fail() both move their counters"; else fail "positive control: pass()/fail() counters read '${pc}', want '1 1 2'"; fi

for f in "$RWF" "$CWF"; do
  if [[ -f "$f" ]]; then pass "workflow present: ${f#"$REPO"/}"; else fail "workflow present: ${f#"$REPO"/}"; fi
done

# ── The parsed-workflow helper ────────────────────────────────────────────────────────────────
PY="$WORK/wf.py"
cat > "$PY" <<'PY'
import os, re, sys, yaml
Loader = getattr(yaml, "CSafeLoader", yaml.SafeLoader)

def load(p):
    with open(p) as fh:
        return yaml.load(fh, Loader=Loader)

def job_of(doc, name):
    return ((doc or {}).get("jobs") or {}).get(name) or {}

def strip(run):
    return "\n".join(l for l in str(run or "").split("\n") if not l.lstrip().startswith("#"))

def logical(text):
    return re.sub(r"\\\n", " ", text)

def emit(cid, ok, detail=""):
    print(("OK %s" % cid) if ok else ("RED %s %s" % (cid, detail)).rstrip())

def extract(wf, job, outdir):
    os.makedirs(outdir, exist_ok=True)
    for st in job_of(load(wf), job).get("steps") or []:
        sid = st.get("id")
        if sid and "run" in st:
            with open(os.path.join(outdir, sid + ".sh"), "w") as fh:
                fh.write(str(st["run"]))
            with open(os.path.join(outdir, sid + ".wd"), "w") as fh:
                fh.write(str(st.get("working-directory") or ""))

ORDER = ["require_main", "creds", "tier_b", "validate", "readiness", "read", "plan", "plan_summary",
         "toctou", "boot_anchor", "apply", "verify", "cancel_poweroff", "record_pin", "summary", "cleanup"]
IFS = {
    "plan_summary": "always()",
    "toctou": "inputs.plan_only != true",
    "boot_anchor": "inputs.plan_only != true",
    "apply": "inputs.plan_only != true",
    "verify": "${{ !cancelled() && (steps.apply.outcome == 'success' || steps.apply.outcome == 'failure') && inputs.plan_only != true }}",
    "cancel_poweroff": "${{ cancelled() && steps.apply.outcome != 'skipped' && steps.verify.outcome != 'success' && inputs.plan_only != true }}",
    "record_pin": "${{ !cancelled() && steps.verify.outcome == 'success' }}",
    "summary": "always()",
    "cleanup": "always()",
}
TF = re.compile(r"(?<![\w./-])terraform((?:\s+-\S+)*)\s+(plan|apply)(?=\s|$)")

def walk_keys(node, key):
    if isinstance(node, dict):
        for k, v in node.items():
            if k == key:
                yield v
            yield from walk_keys(v, key)
    elif isinstance(node, list):
        for v in node:
            yield from walk_keys(v, key)

def written(st, repo):
    out = set()
    if "uses" in st and str(st["uses"]).startswith("./"):
        act = os.path.join(repo, str(st["uses"])[2:], "action.yml")
        if os.path.isfile(act):
            out |= set((load(act).get("outputs") or {}).keys())
    run = strip(st.get("run"))
    for line in run.split("\n"):
        if '"$GITHUB_OUTPUT"' in line:
            m = re.search(r"""(?:^|[\s'"])([A-Za-z_][A-Za-z0-9_]*)=""", line)
            if m:
                out.add(m.group(1))
    if re.search(r"(?m)^\s*bastion_boot_verify\s", run) and "scripts/lib/bastion-boot-verify.sh" in run:
        lib = os.path.join(repo, "scripts/lib/bastion-boot-verify.sh")
        for line in open(lib).read().split("\n"):
            if line.lstrip().startswith("#") or "GITHUB_OUTPUT" not in line:
                continue
            m = re.search(r"printf '([A-Za-z_][A-Za-z0-9_]*)=", line)
            if m:
                out.add(m.group(1))
    return out

def structural(wf, cwf, repo):
    try:
        doc = load(wf)
    except Exception as e:  # an unparseable mutant is RED on every structural row
        doc = {}
    job = job_of(doc, "bastion_host_replace")
    steps = job.get("steps") or []
    emit("S1-environment", job.get("environment") == "web-platform-infra-apply", repr(job.get("environment")))
    coe = list(walk_keys(doc, "continue-on-error"))
    emit("S1-no-continue-on-error", bool(job) and not coe, "%d continue-on-error key(s)" % len(coe))
    emit("S1-no-job-if", bool(job) and "if" not in job, repr(job.get("if")))
    expr = [s.get("id") or s.get("name") for s in steps if "${{" in str(s.get("run") or "")]
    emit("S1-run-no-expression", bool(steps) and not expr, repr(expr))
    ids = [s.get("id") for s in steps]
    bad = [i for i in ORDER if ids.count(i) != 1]
    emit("S2-ids", not bad, "missing or doubled: %r" % bad)
    emit("S2-require-main-first", bool(ids) and ids[0] == "require_main", repr(ids[:1]))
    pos = [ids.index(i) for i in ORDER if ids.count(i) == 1]
    emit("S2-order", not bad and pos == sorted(pos), "order %r" % [i for i in ids if i in ORDER])
    by = {s.get("id"): s for s in steps if s.get("id")}
    for sid, want in IFS.items():
        got = (by.get(sid) or {}).get("if")
        emit("S3-if-%s" % sid, got == want, "got %r" % got)
    cut = ids.index("plan_summary") if "plan_summary" in ids else len(ids)
    early = [s.get("id") or s.get("name") or s.get("uses") for s in steps[:cut] if "if" in s]
    emit("S3-no-if-before-plan-summary", bool(steps) and not early, repr(early))
    text = logical("\n".join(strip(s.get("run")) for s in steps))
    hits = [(m.group(2), m.end()) for m in TF.finditer(text)]
    plans = [h for h in hits if h[0] == "plan"]
    applies = [h for h in hits if h[0] == "apply"]
    emit("S4-one-plan", len(plans) == 1, "%d terraform plan invocation(s)" % len(plans))
    emit("S4-one-apply", len(applies) == 1, "%d terraform apply invocation(s)" % len(applies))
    pos_args = None
    if len(applies) == 1:
        rest = text[applies[0][1]:].split("\n", 1)[0]
        rest = re.split(r"\s\d*[>|;&]", rest)[0]
        pos_args = [t for t in rest.split() if not t.startswith("-")]
    emit("S4-apply-arg", pos_args == ['"$PLAN_DIR/tfplan"'], "positional %r" % pos_args)
    w = {s.get("id"): written(s, repo) for s in steps if s.get("id")}
    consumed, outcomes = [], []
    for s in steps:
        blob = " ".join(str(v) for v in [s.get("if", ""), s.get("env", ""), s.get("with", "")])
        consumed += re.findall(r"steps\.([A-Za-z0-9_-]+)\.outputs\.([A-Za-z0-9_-]+)", blob)
        outcomes += re.findall(r"steps\.([A-Za-z0-9_-]+)\.(?:outcome|conclusion)", blob)
    unwritten = sorted({"%s.%s" % c for c in consumed if c[1] not in w.get(c[0], set())})
    emit("S5-outputs", bool(consumed) and not unwritten, "consumed but never written: %r" % unwritten)
    unknown = sorted({o for o in outcomes if o not in w})
    emit("S5-outcomes", bool(outcomes) and not unknown, "unknown step ids: %r" % unknown)
    want_pre = "${{ steps.toctou.outputs.pre_ids }}"
    badenv = [sid for sid in ("verify", "cancel_poweroff", "summary") if ((by.get(sid) or {}).get("env") or {}).get("PRE_IDS") != want_pre]
    emit("S6-preids-env", not badenv, "PRE_IDS not bound from steps.toctou.outputs.pre_ids in %r" % badenv)
    pre = [l for l in strip((by.get("toctou") or {}).get("run")).split("\n") if re.match(r'\s*pre="\$\(jq ', l)]
    emit("S6-pre-from-fresh", len(pre) == 1 and pre[0].rstrip().endswith('"$fresh")"') and "hetzner-servers.json" not in pre[0], repr(pre))
    retired = [os.path.basename(p) for p in (wf, cwf) if "powered_off_or_absent" in open(p).read()]
    emit("S7-no-retired-cancel-token", not retired, repr(retired))

def once(src, dst, code):
    s = open(src).read()
    g = {"re": re, "s": s, "n": None}
    exec(code, g)
    if g["n"] != 1 or g["s"] == s:
        sys.exit(3)
    open(dst, "w").write(g["s"])

if __name__ == "__main__":
    cmd = sys.argv[1]
    if cmd == "extract":
        extract(sys.argv[2], sys.argv[3], sys.argv[4])
    elif cmd == "structural":
        structural(sys.argv[2], sys.argv[3], sys.argv[4])
    elif cmd == "mutate":
        once(sys.argv[2], sys.argv[3], sys.argv[4])
PY

# ── The stub PATH (used ALONE) and the fake workspaces ─────────────────────────────────────────
STUB="$WORK/bin"
mkdir -p "$STUB" "$WORK/home"
for t in jq grep head tail cat mktemp tr date rm sed awk seq sleep env dirname cut wc sort basename mkdir cp touch ls tee uniq; do
  p="$(command -v "$t")" || { fail "host tool $t is available for the stub PATH"; continue; }
  ln -s "$p" "$STUB/$t"
done
cat > "$STUB/terraform" <<EOF
#!${BASH_BIN}
printf 'terraform' >> "\$STUB_LOG"; printf ' %s' "\$@" >> "\$STUB_LOG"; printf '\n' >> "\$STUB_LOG"
args=("\$@"); i=0
while [[ "\${args[\$i]:-}" == -* ]]; do i=\$((i + 1)); done
sub="\${args[\$i]:-}"
case "\$sub" in
  plan)
    for a in "\$@"; do [[ "\$a" == -out=* ]] && : > "\${a#-out=}"; done
    exit "\${STUB_TF_PLAN_RC:-0}" ;;
  show)
    if [[ " \$* " == *" -json "* ]]; then cat "\$STUB_PLAN_JSON"; else echo "Plan: 1 to add, 1 to change, 1 to destroy."; fi ;;
  apply) exit "\${STUB_TF_APPLY_RC:-0}" ;;
  state) printf '%s\n' "\${STUB_STATE_LIST:-hcloud_server.bastion}" ;;
  output) exit 1 ;;
  *) exit 0 ;;
esac
EOF
cat > "$STUB/doppler" <<EOF
#!${BASH_BIN}
printf 'doppler' >> "\$STUB_LOG"; printf ' %s' "\$@" >> "\$STUB_LOG"; printf '\n' >> "\$STUB_LOG"
if [[ "\${1:-}" == run ]]; then
  while [[ \$# -gt 0 && "\$1" != -- ]]; do shift; done
  shift
  exec "\$@"
fi
exit 1
EOF
cat > "$STUB/gh" <<EOF
#!${BASH_BIN}
printf 'gh' >> "\$STUB_LOG"; printf ' %s' "\$@" >> "\$STUB_LOG"; printf '\n' >> "\$STUB_LOG"
EOF
cat > "$STUB/curl" <<EOF
#!${BASH_BIN}
out="" w="" url="" method=GET cfg=""
while [[ \$# -gt 0 ]]; do
  case "\$1" in
    -o) out="\$2"; shift 2 ;;
    -w) w="\$2"; shift 2 ;;
    -X) method="\$2"; shift 2 ;;
    --config) cfg="\$2"; shift 2 ;;
    --max-time|--noproxy) shift 2 ;;
    https://*) url="\$1"; shift ;;
    *) shift ;;
  esac
done
auth=no
if [[ "\$cfg" == - ]] && grep -q '^header = "Authorization: Bearer ' ; then auth=yes; fi
printf 'curl %s %s auth=%s\n' "\$method" "\$url" "\$auth" >> "\$STUB_LOG"
body_file="" body='{}' code=404
case "\$method \$url" in
  "GET https://api.hetzner.cloud/v1/servers?name=soleur-bastion") body_file="\${STUB_SERVERS:-}"; code="\${STUB_SERVERS_CODE:-200}" ;;
  "GET https://api.hetzner.cloud/v1/firewalls/"*) body_file="\${STUB_FW:-}"; code="\${STUB_FW_CODE:-200}" ;;
  "POST https://api.hetzner.cloud/v1/servers/"*"/actions/poweroff") body='{"action":{"id":7}}'; code=201 ;;
  "GET https://api.hetzner.cloud/v1/actions/7") body='{"action":{"status":"success"}}'; code=200 ;;
esac
[[ -n "\$body_file" && -f "\$body_file" ]] && body="\$(cat "\$body_file")"
if [[ -n "\$out" ]]; then printf '%s' "\$body" > "\$out"; else printf '%s' "\$body"; fi
printf '%b' "\${w//%\{http_code\}/\$code}"
EOF
chmod +x "$STUB/terraform" "$STUB/doppler" "$STUB/gh" "$STUB/curl"

mkws() { # <dir> <real|stubbv>: a fake GITHUB_WORKSPACE
  local ws="$1"
  mkdir -p "$ws/scripts/lib" "$ws/tests/scripts/lib" "$ws/apps/web-platform/infra"
  ln -s "$REPO/scripts/lib/bearer-curl.sh" "$ws/scripts/lib/bearer-curl.sh"
  if [[ "$2" == real ]]; then
    ln -s "$REPO/scripts/lib/bastion-boot-verify.sh" "$ws/scripts/lib/bastion-boot-verify.sh"
  else
    printf '%s\n' 'bastion_boot_verify() { printf "boot_verify %s: %s\n" "$#" "$*" >> "$STUB_LOG"; return "${STUB_BV_RC:-0}"; }' \
      '_bbv_poweroff() { printf "poweroff %s\n" "$*" >> "$STUB_LOG"; _BBV_POWEROFF=powered_off; }' > "$ws/scripts/lib/bastion-boot-verify.sh"
  fi
  printf '%s\n' 'tf_redact_random_ids() { cat; }' > "$ws/tests/scripts/lib/tf-redact-random-ids.sh"
  printf '%s\n' \
    'bastion_host_replace_gate() { printf "gate %s\n" "$*" >> "$STUB_LOG"; echo "stub gate rc=${STUB_GATE_RC:-0}"; return "${STUB_GATE_RC:-0}"; }' \
    'bastion_replace_next_dispatch() { printf "next_dispatch %s\n" "$*" >> "$STUB_LOG"; echo "next dispatch: STUB LINE"; }' \
    > "$ws/tests/scripts/lib/bastion-host-replace-gate.sh"
  printf '%s\n' \
    'stock_preflight_gate() { printf "stock %s cwd=%s\n" "$*" "$PWD" >> "$STUB_LOG"; return "${STUB_STOCK_RC:-0}"; }' \
    'stock_abort_closing() { printf "stock_abort_closing %s\n" "$1" >> "$STUB_LOG"; }' \
    'stock_recovery_report() { printf "stock_recovery_report %s\n" "$*" >> "$STUB_LOG"; }' \
    > "$ws/tests/scripts/lib/stock-preflight-gate.sh"
}
WS="$WORK/ws"; WSV="$WORK/wsv"
mkws "$WS" real; mkws "$WSV" stubbv

# ── Synthesized fixtures (cq-test-fixtures-synthesized-only) ──────────────────────────────────
FX="$WORK/fx"; mkdir -p "$FX"
srv() { # <id> [status] [ip] [name] [role]
  jq -cn --argjson id "$1" --arg st "${2:-running}" --arg ip "${3:-10.0.1.70}" --arg nm "${4:-soleur-bastion}" --arg rl "${5:-bastion}" \
    '{id: $id, name: $nm, labels: {role: $rl}, status: $st, private_net: [{network: 9001, ip: $ip, alias_ips: []}], public_net: {ipv4: null}, created: "2026-11-01T00:00:00Z"}'
}
docs() { jq -cn --argjson s "[$(IFS=,; echo "$*")]" '{servers: $s, meta: {pagination: {total_entries: ($s | length)}}}'; }
docs "$(srv 111)" > "$FX/s111.json"
docs > "$FX/s-none.json"
docs "$(srv 111 off)" > "$FX/s111-off.json"
docs "$(srv 112)" > "$FX/s112.json"
docs "$(srv 111 running 10.0.1.71)" > "$FX/s111-ip.json"
docs "$(srv 111 running 10.0.1.70 soleur-bastion web)" > "$FX/s111-role.json"
docs "$(srv 111 running 10.0.1.70 soleur-bastion-old)" > "$FX/s111-name.json"
docs "$(srv 111)" "$(srv 222)" > "$FX/s111-222.json"
docs "$(srv 222)" > "$FX/s222.json"
jq -c '.servers[0].public_net = {ipv4: {ip: "203.0.113.9"}} | .servers[0].created = "2026-11-02T00:00:00Z"' "$FX/s111.json" > "$FX/s111-unprojected.json"
fwdoc() { jq -cn --argjson t "[$(IFS=,; echo "$*")]" '{firewall: {id: 555, name: "soleur-bastion", rules: [], applied_to: $t}}'; }
fws() { printf '{"type":"server","server":{"id":%s}}' "$1"; }
FWL='{"type":"label_selector","label_selector":{"selector":"role=web"},"applied_to_resources":[]}'
fwdoc "$(fws 111)" > "$FX/fw111.json"
fwdoc > "$FX/fw-none.json"
fwdoc "$(fws 111)" "$FWL" > "$FX/fw111-label.json"
fwdoc "$(fws 999)" > "$FX/fw999.json"
fwdoc "$(fws 111)" "$(fws 999)" > "$FX/fw111-999.json"
echo '{}' > "$FX/fw-noarray.json"
# The plan JSON: the firewall a no-op with a known id; the host key's three private_key_* fields, multi-line.
KEYS='{"private_key_openssh": "SYNTH-OPENSSH-HEAD\nSYNTH-OPENSSH-LINE-A\nSYNTH-OPENSSH-LINE-B\nSYNTH-OPENSSH-TAIL\n",
       "private_key_pem": "SYNTH-PEM-HEAD\nSYNTH-PEM-LINE-A\nSYNTH-PEM-TAIL\n",
       "private_key_pem_pkcs8": "SYNTH-PEM-HEAD\nSYNTH-PKCS8-LINE-A\nSYNTH-PEM-TAIL\n"}'
jq -n --argjson k "$KEYS" '{format_version: "1.2",
  resource_changes: [
    {address: "hcloud_firewall.bastion", type: "hcloud_firewall", change: {actions: ["no-op"], before: {id: "555"}, after: {id: "555"}}},
    {address: "tls_private_key.bastion_host_ssh", type: "tls_private_key", change: {actions: ["no-op"], before: $k, after: $k}}],
  prior_state: {values: {root_module: {resources: [{address: "tls_private_key.bastion_host_ssh", values: $k}]}}}}' > "$FX/plan.json"
jq '(.resource_changes[] | select(.address == "hcloud_firewall.bastion") | .change.after) |= del(.id)' "$FX/plan.json" > "$FX/plan-nofwid.json"

# ── The step runner ───────────────────────────────────────────────────────────────────────────
LOG="$WORK/stub.log"; OUT="$WORK/step.out"; GO="$WORK/gh-output"; GS="$WORK/gh-summary"; GE="$WORK/gh-env"; RT="$WORK/runner-temp"
PD="$RT/bastion-replace.TESTDIR0"
mkdir -p "$RT"
STEPS=""
RS_RC=0 RS_OK=0
newpd() { # <saved-servers-doc> [plan-json]: a fresh plan directory
  rm -rf -- "$PD"; mkdir -p "$PD"
  cp "$1" "$PD/hetzner-servers.json"
  cp "${2:-$FX/plan.json}" "$PD/tfplan.json"
}
run_step() { # <id> <ws> VAR=value...: run the extracted step body as the runner would (bash -e, env -i, stub PATH)
  local id="$1" ws="$2" script wd cwd
  shift 2
  script="$STEPS/$id.sh"
  : > "$LOG"; : > "$GO"; : > "$GS"; : > "$GE"; : > "$OUT"
  RS_OK=0; RS_RC=127
  [[ -f "$script" ]] || return 0
  wd="$(cat "$STEPS/$id.wd")"
  case "$wd" in
    '') cwd="$ws" ;;
    '${{ env.INFRA_DIR }}') cwd="$ws/apps/web-platform/infra" ;;
    *) return 0 ;;
  esac
  RS_OK=1
  (cd "$cwd" && env -i PATH="$STUB" HOME="$WORK/home" GITHUB_WORKSPACE="$ws" GITHUB_OUTPUT="$GO" GITHUB_STEP_SUMMARY="$GS" \
    GITHUB_ENV="$GE" RUNNER_TEMP="$RT" INFRA_DIR=apps/web-platform/infra STUB_LOG="$LOG" "$@" "$BASH_BIN" -e "$script") > "$OUT" 2>&1
  RS_RC=$?
}
v() { # <check-id> <0|1 condition rc> [detail]: one verdict line
  if [[ "$2" -eq 0 && "$RS_OK" -eq 1 ]]; then echo "OK $1"; else echo "RED $1 rc=${RS_RC} ${3:-} $(tr '\n' ' ' < "$OUT" | head -c 300)"; fi
}
refused() { # <check-id> <message substring>: non-zero exit AND the named refusal printed AND no pre_ids written
  [[ "$RS_RC" -ne 0 ]] && grep -qF -- "$2" "$OUT" && ! grep -q '^pre_ids=' "$GO"
  v "$1" $? "(want a refusal naming '$2')"
}
logged() { grep -qF -- "$1" "$LOG"; }
po_line() { awk 'p { print; exit } /^A green run means/ { p = 1 }' "$GS"; }

# ── analyze <replace-wf> <create-wf> [group...]: every check, one OK/RED line each ──────────────
analyze() {
  local rwf="$1" cwf="$2" g groups
  shift 2
  groups="${*:-S M T V R P A Q B C D X}"
  STEPS="$WORK/steps.$$.$RANDOM"
  rm -rf -- "$STEPS"; python3 -I "$PY" extract "$rwf" bastion_host_replace "$STEPS" 2>/dev/null || true
  for g in $groups; do
    case "$g" in
      S) python3 -I "$PY" structural "$rwf" "$cwf" "$REPO" 2>&1 || echo "RED S-crash structural analyzer crashed" ;;
      M) run_step require_main "$WS" GITHUB_REF=refs/heads/feat-x
         refused M-branch-refused "Nothing was planned or destroyed."
         run_step require_main "$WS" GITHUB_REF=refs/heads/main
         [[ "$RS_RC" -eq 0 ]]; v M-main-passes $? ;;
      T) run_step tier_b "$WS" CRED_SOURCE=legacy
         refused T-legacy-refused "is HELD"
         run_step tier_b "$WS"
         refused T-unset-refused "is HELD"
         run_step tier_b "$WS" CRED_SOURCE=tier_b
         [[ "$RS_RC" -eq 0 ]]; v T-tier_b-passes $? ;;
      V) run_step validate "$WS" CONFIRM_RAW=REPLACE-bastio EXPECTED_ID_RAW=111
         refused V-confirm-refused "confirm must be exactly"
         run_step validate "$WS" CONFIRM_RAW=BIRTH-bastion EXPECTED_ID_RAW=111
         refused V-birth-token-refused "confirm must be exactly"
         run_step validate "$WS" "CONFIRM_RAW=x"$'\n'"::stop-commands::SYNTHTOKEN"$'\n'"::warning::INJECTED" EXPECTED_ID_RAW=111
         [[ "$RS_RC" -ne 0 ]] && ! grep -qE '^::(stop-commands|warning)::' "$OUT" && ! grep -qF SYNTHTOKEN "$OUT" && ! grep -qF INJECTED "$OUT"
         v V-confirm-never-echoed $? "(dispatch text reached a workflow command)"
         for bad in 0123 abc "12 3" 1234567890123 "" "111"$'\n'"222"; do
           run_step validate "$WS" CONFIRM_RAW=REPLACE-bastion "EXPECTED_ID_RAW=$bad"
           refused "V-pin-refused-$(printf '%s' "${bad:-empty}" | tr -c 'A-Za-z0-9' '_')" "expected_bastion_server_id must be"
         done
         run_step validate "$WS" CONFIRM_RAW=REPLACE-bastion EXPECTED_ID_RAW=111
         [[ "$RS_RC" -eq 0 ]]; v V-pin-passes $?
         run_step validate "$WS" CONFIRM_RAW=REPLACE-bastion EXPECTED_ID_RAW=none
         [[ "$RS_RC" -eq 0 ]]; v V-none-passes $? ;;
      R) rm -rf -- "$RT"/bastion-replace.*; mkdir -p "$RT"
         run_step read "$WS" HCLOUD_TOKEN=synthetichcloudtoken0 STUB_SERVERS="$FX/s111.json"
         rd="$(sed -n 's/^PLAN_DIR=//p' "$GE")"
         [[ "$RS_RC" -eq 0 && "$rd" == "$RT"/bastion-replace.* && -f "$rd/hetzner-servers.json" ]] && jq -e --slurpfile w "$FX/s111.json" '. == $w[0]' "$rd/hetzner-servers.json" >/dev/null \
           && logged "curl GET https://api.hetzner.cloud/v1/servers?name=soleur-bastion auth=yes" && grep -qF -- '- id `111`' "$GS"
         v R-read-saves-the-graded-document $?
         rm -rf -- "$RT"/bastion-replace.*
         run_step read "$WS" HCLOUD_TOKEN=synthetichcloudtoken0 STUB_SERVERS="$FX/s111.json" STUB_SERVERS_CODE=503
         [[ "$RS_RC" -ne 0 ]] && grep -qF "Hetzner server read FAILED" "$OUT" && grep -qF "Nothing was planned or destroyed." "$OUT"
         v R-read-failure-stops-before-the-plan $?
         rm -rf -- "$RT"/bastion-replace.*; mkdir -p "$RT" ;;
      P) local penv=(PLAN_DIR="$PD" CI_SSH_PUB=/tmp/ci_ssh_key.pub HCLOUD_TOKEN=synthetichcloudtoken0 DOPPLER_TOKEN=synthdoppler STUB_PLAN_JSON="$FX/plan.json")
         newpd "$FX/s111.json"; run_step plan "$WS" "${penv[@]}" EXPECTED_ID=111
         [[ "$RS_RC" -eq 0 ]] && logged "gate $PD/tfplan.json 111 $PD/hetzner-servers.json" && logged "stock tfplan.json cwd=$PD"
         v P-pass-calls-gate-and-stock $?
         grep -E '^terraform( -[^ ]+)* plan ' "$LOG" > "$WORK/plan-argv" || true
         [[ "$(wc -l < "$WORK/plan-argv")" -eq 1 ]] && grep -qF " -out=$PD/tfplan -replace=hcloud_server.bastion " "$WORK/plan-argv" \
           && [[ "$(grep -o -- ' -target=' "$WORK/plan-argv" | wc -l)" -eq 5 ]]
         v P-replace-arm-plans-replace $?
         ok=0
         for l in SYNTH-OPENSSH-LINE-A SYNTH-OPENSSH-LINE-B SYNTH-PEM-LINE-A SYNTH-PKCS8-LINE-A; do grep -qxF "::add-mask::$l" "$OUT" || ok=1; done
         v P-private-keys-masked "$ok" "(a private_key_* line was not masked)"
         newpd "$FX/s-none.json"; run_step plan "$WS" "${penv[@]}" EXPECTED_ID=none
         [[ "$RS_RC" -eq 0 ]] && ! grep -qF -- '-replace=' "$LOG"
         v P-recovery-arm-plans-no-replace $?
         newpd "$FX/s111.json"; run_step plan "$WS" "${penv[@]}" EXPECTED_ID=111 STUB_GATE_RC=1
         [[ "$RS_RC" -ne 0 ]] && logged "gate $PD/tfplan.json 111 $PD/hetzner-servers.json" && grep -qF 'gate ABORTED' "$OUT" && ! logged "stock "
         v P-gate-abort-stops $?
         newpd "$FX/s111.json"; run_step plan "$WS" "${penv[@]}" EXPECTED_ID=111 STUB_STOCK_RC=1
         [[ "$RS_RC" -ne 0 ]] && logged "gate $PD/tfplan.json" && logged "stock tfplan.json" && logged "stock_abort_closing bastion-host-replace"
         v P-stock-refusal-stops $?
         newpd "$FX/s111.json"; run_step plan "$WS" "${penv[@]}" EXPECTED_ID=111 STUB_TF_PLAN_RC=1
         [[ "$RS_RC" -ne 0 ]] && ! logged "gate "
         v P-plan-failure-stops $?
         newpd "$FX/s111.json"; run_step plan "$WS" "${penv[@]}" EXPECTED_ID=111 HCLOUD_TOKEN=
         [[ "$RS_RC" -ne 0 ]] && logged "gate " && ! logged "stock "
         v P-no-token-stops $? ;;
      A) newpd "$FX/s111.json"; run_step apply "$WS" PLAN_DIR="$PD" DOPPLER_TOKEN=synthdoppler
         [[ "$RS_RC" -eq 0 && "$(grep -c '^terraform' "$LOG")" -eq 1 ]] && grep -qxF "terraform apply -no-color -input=false $PD/tfplan" "$LOG"
         v A-applies-only-the-gated-plan $?
         newpd "$FX/s111.json"; run_step apply "$WS" PLAN_DIR="$PD" DOPPLER_TOKEN=synthdoppler STUB_TF_APPLY_RC=1
         [[ "$RS_RC" -ne 0 ]] && logged "stock_recovery_report bastion-host-replace $PD/tfplan.json --probe-state"
         v A-failed-apply-exits-1 $? ;;
      Q) local qenv=(PLAN_DIR="$PD" HCLOUD_TOKEN=synthetichcloudtoken0)
         toctou() { # <saved> <fresh> <fw> <pin> [plan] [VAR=...]
           local saved="$1" fresh="$2" fw="$3" pin="$4" plan="${5:-$FX/plan.json}"
           shift 5 2>/dev/null || shift $#
           newpd "$saved" "$plan"
           run_step toctou "$WS" "${qenv[@]}" EXPECTED_ID="$pin" STUB_SERVERS="$fresh" STUB_FW="$fw" "$@"
         }
         toctou "$FX/s111.json" "$FX/s111.json" "$FX/fw111.json" 111
         [[ "$RS_RC" -eq 0 && "$(cat "$GO")" == "pre_ids=111" ]] && logged "curl GET https://api.hetzner.cloud/v1/servers?name=soleur-bastion auth=yes" \
           && logged "curl GET https://api.hetzner.cloud/v1/firewalls/555 auth=yes"
         v Q-pass-writes-fresh-preids $?
         toctou "$FX/s111.json" "$FX/s111.json" "$FX/fw-none.json" 111
         [[ "$RS_RC" -eq 0 && "$(cat "$GO")" == "pre_ids=111" ]]; v Q-pass-firewall-unbound-on-replace $?
         toctou "$FX/s-none.json" "$FX/s-none.json" "$FX/fw-none.json" none
         [[ "$RS_RC" -eq 0 && "$(cat "$GO")" == "pre_ids=none" ]]; v Q-pass-recovery $?
         toctou "$FX/s111.json" "$FX/s111-unprojected.json" "$FX/fw111.json" 111
         [[ "$RS_RC" -eq 0 ]]; v Q-pass-unprojected-field-changed $?
         toctou "$FX/s111.json" "$FX/s111.json" "$FX/fw111.json" 111 "$FX/plan.json" STUB_SERVERS_CODE=503
         refused Q-servers-read-failure "TOCTOU re-read FAILED"
         local c
         for c in off:s111-off id:s112 ip:s111-ip role:s111-role name:s111-name count:s111-222; do
           toctou "$FX/s111.json" "$FX/${c#*:}.json" "$FX/fw111.json" 111
           refused "Q-changed-${c%%:*}" "the live bastion changed since the plan"
         done
         toctou "$FX/s111.json" "$FX/s111.json" "$FX/fw111.json" 111 "$FX/plan-nofwid.json"
         refused Q-firewall-id-unreadable "hcloud_firewall.bastion id did not read as a number"
         toctou "$FX/s111.json" "$FX/s111.json" "$FX/fw111.json" 111 "$FX/plan.json" STUB_FW_CODE=404
         refused Q-firewall-read-failure "TOCTOU firewall read FAILED"
         toctou "$FX/s111.json" "$FX/s111.json" "$FX/fw-noarray.json" 111
         refused Q-firewall-no-applied-to "TOCTOU firewall read FAILED"
         for c in label:fw111-label other:fw999 extra:fw111-999; do
           toctou "$FX/s111.json" "$FX/s111.json" "$FX/${c#*:}.json" 111
           refused "Q-firewall-${c%%:*}" "firewall is applied to a label selector or to a server other than the pin"
         done
         toctou "$FX/s-none.json" "$FX/s-none.json" "$FX/fw111.json" none
         refused Q-firewall-bound-on-recovery "firewall is applied to a label selector or to a server other than the pin" ;;
      B) run_step verify "$WSV" BOOT_TRAIL_SINCE=1700000000 APPLY_OUTCOME=failure PRE_IDS=111 STUB_BV_RC=1
         [[ "$RS_RC" -eq 1 ]] && grep -qxF "boot_verify 4: 1700000000 failure bastion-host-replace 111" "$LOG"
         v B-verify-passes-four-args-and-its-rc $?
         run_step verify "$WSV" BOOT_TRAIL_SINCE=1700000000 APPLY_OUTCOME=success PRE_IDS=none STUB_BV_RC=0
         [[ "$RS_RC" -eq 0 ]] && grep -qxF "boot_verify 4: 1700000000 success bastion-host-replace none" "$LOG"
         v B-verify-ready-exits-0 $? ;;
      C) cancel_rows C "$WS" ;;
      D) summary_rows ;;
      X) local XSTEPS="$WORK/xsteps.$$.$RANDOM" keep="$STEPS"
         python3 -I "$PY" extract "$cwf" bastion_host_create "$XSTEPS" 2>/dev/null || true
         STEPS="$XSTEPS"
         cancel_rows X "$WS"
         run_step verify "$WSV" BOOT_TRAIL_SINCE=1700000000 APPLY_OUTCOME=failure PRE_IDS=111 STUB_BV_RC=1
         [[ "$RS_RC" -eq 1 ]] && grep -qxF "boot_verify 4: 1700000000 failure bastion-host-create 111" "$LOG"
         v X-verify-passes-four-args-and-its-rc $?
         cancel_lines X
         STEPS="$keep" ;;
    esac
  done
}
cancel_rows() { # <prefix> <ws>: the cancel step records the library's own verdict (Q-R7)
  local p="$1" ws="$2" cenv=(HCLOUD_TOKEN=synthetichcloudtoken0)
  run_step cancel_poweroff "$ws" "${cenv[@]}" PRE_IDS= STUB_SERVERS="$FX/s111-222.json"
  [[ "$RS_RC" -ne 0 && "$(cat "$GO")" == "result=refused_no_preids" ]] && ! logged "curl POST"; v "$p-cancel-records-refused" $?
  run_step cancel_poweroff "$ws" "${cenv[@]}" PRE_IDS=111 STUB_SERVERS="$FX/s111-222.json"
  [[ "$RS_RC" -eq 0 && "$(cat "$GO")" == "result=powered_off" ]] && logged "curl POST https://api.hetzner.cloud/v1/servers/222/actions/poweroff auth=yes" \
    && ! logged "servers/111/actions"; v "$p-cancel-powers-off-the-new-server" $?
  run_step cancel_poweroff "$ws" "${cenv[@]}" PRE_IDS=111 STUB_SERVERS="$FX/s111.json"
  [[ "$RS_RC" -eq 0 && "$(cat "$GO")" == "result=old_untouched" ]] && ! logged "curl POST"; v "$p-cancel-records-old-untouched" $?
  run_step cancel_poweroff "$ws" "${cenv[@]}" PRE_IDS=none STUB_SERVERS="$FX/s-none.json"
  [[ "$RS_RC" -eq 0 && "$(cat "$GO")" == "result=absent" ]]; v "$p-cancel-records-absent" $?
  run_step cancel_poweroff "$ws" "${cenv[@]}" PRE_IDS=111 STUB_SERVERS="$FX/s111-222.json" STUB_SERVERS_CODE=500
  [[ "$RS_RC" -ne 0 && "$(cat "$GO")" == "result=failed" ]]; v "$p-cancel-records-failed" $?
}
cancel_lines() { # <prefix>: the summary prints one distinct line per cancel verdict; REFUSED is not FAILED
  local p="$1" r lines="" rl="" fl=""
  for r in powered_off absent old_untouched refused_no_preids failed; do
    run_step summary "$WS" PLAN_ONLY=false PLAN_OUTCOME=success APPLY_OUTCOME=cancelled VERIFY_OUTCOME=skipped CANCEL_POWEROFF="$r" RUN_STATUS=cancelled JOB_STATUS=cancelled
    lines+="$(po_line)"$'\n'
    [[ "$r" == refused_no_preids ]] && rl="$(po_line)"
    [[ "$r" == failed ]] && fl="$(po_line)"
  done
  [[ "$(grep -c . <<<"$lines")" -eq 5 && "$(sort -u <<<"$lines" | grep -c .)" -eq 5 ]] && ! grep -q 'no verdict recorded' <<<"$lines"
  v "$p-summary-one-line-per-cancel-verdict" $? "(lines: $(tr '\n' '|' <<<"$lines"))"
  [[ "$rl" == *REFUSED* && "$rl" != *FAILED* && "$fl" == *FAILED* ]]
  v "$p-summary-refused-is-not-failed" $? "(refused '$rl' failed '$fl')"
}
summary_rows() { # the replace summary's next-dispatch lines (Q-R7)
  local senv=(PLAN_ONLY=false RUN_STATUS=success PLAN_DIR="$PD" DOPPLER_TOKEN=synthdoppler HCLOUD_TOKEN=synthetichcloudtoken0 STUB_SERVERS="$FX/s222.json")
  newpd "$FX/s111.json"
  run_step summary "$WS" "${senv[@]}" PLAN_OUTCOME=success APPLY_OUTCOME=success VERIFY_OUTCOME=success SERVER_ID=333 POWEROFF_RESULT=not_needed
  [[ "$RS_RC" -eq 0 ]] && grep -qxF -- "- next dispatch: none needed — the replacement is READY as server 333; the next replace pins that id." "$GS" \
    && ! logged next_dispatch && ! logged "curl " && ! logged terraform && ! grep -qF 'gh workflow run' "$GS"
  v D-ready-needs-no-dispatch $?
  for o in "" skipped; do
    run_step summary "$WS" "${senv[@]}" PLAN_OUTCOME="$o" APPLY_OUTCOME=skipped VERIFY_OUTCOME=skipped RUN_STATUS=failure
    [[ "$RS_RC" -eq 0 ]] && grep -qxF -- "- next dispatch: nothing was read (the run stopped before the plan); fix the refusal above and re-dispatch." "$GS" \
      && ! logged next_dispatch && ! logged "curl " && ! logged terraform && ! grep -qF 'FAILED' "$OUT"
    v "D-stopped-before-plan-reads-nothing-${o:-empty}" $?
  done
  run_step summary "$WS" "${senv[@]}" PLAN_OUTCOME=success APPLY_OUTCOME=failure VERIFY_OUTCOME=failure POWEROFF_RESULT=powered_off PRE_IDS=111
  [[ "$RS_RC" -eq 0 ]] && logged "next_dispatch 111 $PD/hetzner-servers-after.json 1" && logged "terraform state list" && logged "curl GET https://api.hetzner.cloud/v1/servers?name=soleur-bastion"
  v D-failed-run-reads-fresh-for-next-dispatch $?
  cancel_lines D
}

# ── Control: the unmutated workflows, through the same machinery the mutants use ───────────────
echo "control (unmutated workflows)"
cp "$RWF" "$WORK/control-replace.yml"; cp "$CWF" "$WORK/control-create.yml"
CONTROL="$(analyze "$WORK/control-replace.yml" "$WORK/control-create.yml")"
n_ok="$(grep -c '^OK ' <<<"$CONTROL")"; n_red="$(grep -c '^RED ' <<<"$CONTROL")"; n_all="$(grep -c . <<<"$CONTROL")"
if [[ "$n_red" -eq 0 && "$n_ok" -eq "$n_all" && "$n_ok" -gt 0 ]]; then pass "the unmutated control is GREEN (${n_ok} checks)"; else fail "the unmutated control is GREEN (ok=${n_ok} red=${n_red} lines=${n_all})"; fi
dups="$(sed -E 's/^(OK|RED) ([^ ]+).*/\2/' <<<"$CONTROL" | sort | uniq -d | tr '\n' ' ')"
if [[ -z "$dups" ]]; then pass "every check id is printed once"; else fail "check ids printed more than once: ${dups}"; fi
MIN_CHECKS=92  # measured 2026-11-28: the literal number of control checks (never derived from the output)
if [[ "$n_all" -eq "$MIN_CHECKS" ]]; then pass "the control printed exactly ${MIN_CHECKS} checks"; else fail "the control printed ${n_all} checks, want exactly ${MIN_CHECKS}"; fi
echo "checks"
while IFS= read -r line; do
  [[ -n "$line" ]] || continue
  if [[ "$line" == "OK "* ]]; then pass "${line#OK }"; else fail "${line#RED }"; fi
done <<<"$CONTROL"

# ── Mutation rows (pin 7): each must turn its named check RED ─────────────────────────────────
echo "mutation rows"
MUT_N=0
mut() { # <label> <file: replace|create> <group> <check-id> <python: sets s and n (n = matches, must be 1)>
  local label="$1" which="$2" group="$3" want="$4" code="$5" r="$WORK/control-replace.yml" c="$WORK/control-create.yml" dst o
  MUT_N=$((MUT_N + 1))
  dst="$WORK/mut-$MUT_N.yml"
  if [[ "$which" == replace ]]; then
    python3 -I "$PY" mutate "$r" "$dst" "$code" 2>/dev/null && ! cmp -s "$r" "$dst" || { fail "mutation did not land exactly once: $label"; return; }
    o="$(analyze "$dst" "$c" "$group")"
  else
    python3 -I "$PY" mutate "$c" "$dst" "$code" 2>/dev/null && ! cmp -s "$c" "$dst" || { fail "mutation did not land exactly once: $label"; return; }
    o="$(analyze "$r" "$dst" "$group")"
  fi
  if grep -qE "^RED ${want}( |$)" <<<"$o"; then pass "mutation RED ($want): $label"; else fail "mutation SURVIVED ($want stayed green): $label"; fi
}
# once(a, b): replace the one occurrence of a with b; n counts occurrences.
O='def once(a, b):
    global s, n
    n = s.count(a); s = s.replace(a, b)
'
mut "Guard 2 the live read's failure ignored" replace R R-read-failure-stops-before-the-plan "$O"'once("_bbv_servers_doc \"$PLAN_DIR/hetzner-servers.json\")\" || rc=$?", "_bbv_servers_doc \"$PLAN_DIR/hetzner-servers.json\")\" || true")'
mut "Guard 2 the gate grades a document other than the saved read" replace P P-pass-calls-gate-and-stock "$O"'once("\"$EXPECTED_ID\" \"$PLAN_DIR/hetzner-servers.json\"; then", "\"$EXPECTED_ID\" \"$PLAN_DIR/hetzner-servers-toctou.json\"; then")'
mut "Guard 2 F4 the -replace array set on both arms" replace P P-recovery-arm-plans-no-replace "$O"'once("if [[ \"$EXPECTED_ID\" != none ]]; then\n            replace_args=", "if true; then\n            replace_args=")'
mut "W5 the gate call no-op'd (if ! : bastion_host_replace_gate)" replace P P-gate-abort-stops "$O"'once("if ! bastion_host_replace_gate \"", "if ! : bastion_host_replace_gate \"")'
mut "W2 the gate ABORT exit 1 -> true" replace P P-gate-abort-stops "$O"'once("| head -30 >&2\n            exit 1", "| head -30 >&2\n            true")'
mut "W3 continue-on-error on the plan step" replace S S1-no-continue-on-error "$O"'once("        id: plan\n", "        id: plan\n        continue-on-error: true\n")'
mut "W1 the apply if: gains always()" replace S S3-if-apply "$O"'once("        if: inputs.plan_only != true\n        id: apply\n", "        if: always() && inputs.plan_only != true\n        id: apply\n")'
mut "W12 a terraform -chdir=. plan inserted before the apply" replace S S4-one-plan "$O"'once("          if ! doppler run --preserve-env -p soleur -c prd_terraform --name-transformer tf-var -- \\\n            terraform apply", "          terraform -chdir=. plan -no-color -input=false -out=\"$PLAN_DIR/tfplan\"\n          if ! doppler run --preserve-env -p soleur -c prd_terraform --name-transformer tf-var -- \\\n            terraform apply")'
mut "W12b the same re-plan, executed" replace A A-applies-only-the-gated-plan "$O"'once("          if ! doppler run --preserve-env -p soleur -c prd_terraform --name-transformer tf-var -- \\\n            terraform apply", "          terraform -chdir=. plan -no-color -input=false -out=\"$PLAN_DIR/tfplan\"\n          if ! doppler run --preserve-env -p soleur -c prd_terraform --name-transformer tf-var -- \\\n            terraform apply")'
mut "the apply's plan argument widened (\"\$PLAN_DIR/tfplan\"2)" replace S S4-apply-arg "$O"'once("terraform apply -no-color -input=false \"$PLAN_DIR/tfplan\"", "terraform apply -no-color -input=false \"$PLAN_DIR/tfplan\"2")'
mut "W4 the TOCTOU compare refusal exit 1 -> true" replace Q Q-changed-off "$O"'once("read the id from its summary. Nothing applied.\"\n            exit 1", "read the id from its summary. Nothing applied.\"\n            true")'
mut "W11 the TOCTOU compare if false" replace Q Q-changed-id "$O"'once("if [[ \"$same\" != true ]]; then", "if false; then")'
mut "the TOCTOU projection narrowed back (no private_net)" replace Q Q-changed-ip "$O"'once(", private_net: [(.private_net // [])[] | {network, ip}]}", "}")'
mut "the TOCTOU projection narrowed back (no name)" replace Q Q-changed-name "$O"'once("{id, name, role: .labels.role,", "{id, role: .labels.role,")'
mut "m8 the TOCTOU fresh read swapped for the plan-time doc" replace Q Q-changed-off "$O"'once("rc=0; why=\"$(_bbv_servers_doc \"$fresh\")\" || rc=$?\n          if [[ \"$rc\" -ne 0 ]]; then\n            echo \"::error::bastion-host-replace: TOCTOU", "rc=0; cp \"$PLAN_DIR/hetzner-servers.json\" \"$fresh\"\n          if [[ \"$rc\" -ne 0 ]]; then\n            echo \"::error::bastion-host-replace: TOCTOU")'
mut "m10 pre_ids read from the plan-time doc" replace S S6-pre-from-fresh "$O"'once("else join(\" \") end'"'"' \"$fresh\")\"", "else join(\" \") end'"'"' \"$PLAN_DIR/hetzner-servers.json\")\"")'
mut "Q-R3 the firewall binding check if false" replace Q Q-firewall-label "$O"'once("if [[ \"$fw_ok\" != true ]]; then", "if false; then")'
mut "Q-R3 the firewall binding refusal exit 1 -> true" replace Q Q-firewall-other "$O"'once("Re-run plan_only. Nothing applied.\"\n            exit 1", "Re-run plan_only. Nothing applied.\"\n            true")'
mut "Q-R3 a recovery-arm firewall may hold the pin" replace Q Q-firewall-bound-on-recovery "$O"'once("$s == [] or ($pin != \"none\" and $s == [$pin])", "$s == [] or $s == [$pin] or $pin == \"none\"")'
mut "Q-R3 the firewall read failure ignored" replace Q Q-firewall-read-failure "$O"'once("if [[ \"$code\" != 200 ]] || ! jq -e", "if false && ! jq -e")'
mut "m4 the stock preflight neutered (&& false)" replace P P-stock-refusal-stops "$O"'once("if ! stock_preflight_gate tfplan.json; then", "if ! stock_preflight_gate tfplan.json && false; then")'
mut "W6 verify binds steps.toctou.outputs.pre_id" replace S S5-outputs "$O"'once("          BOOT_TRAIL_SINCE: ${{ steps.boot_anchor.outputs.epoch }}\n          PRE_IDS: ${{ steps.toctou.outputs.pre_ids }}", "          BOOT_TRAIL_SINCE: ${{ steps.boot_anchor.outputs.epoch }}\n          PRE_IDS: ${{ steps.toctou.outputs.pre_id }}")'
mut "W7 the TOCTOU output renamed preids= (structure)" replace S S5-outputs "$O"'once("printf '"'"'pre_ids=%s\\n'"'"' \"$pre\"", "printf '"'"'preids=%s\\n'"'"' \"$pre\"")'
mut "W7 the TOCTOU output renamed preids= (behaviour)" replace Q Q-pass-writes-fresh-preids "$O"'once("printf '"'"'pre_ids=%s\\n'"'"' \"$pre\"", "printf '"'"'preids=%s\\n'"'"' \"$pre\"")'
mut "W8 verify if: drops the failed-apply arm" replace S S3-if-verify "$O"'once(" || steps.apply.outcome == '"'"'failure'"'"') && inputs.plan_only != true }}", ") && inputs.plan_only != true }}")'
mut "W9 the mask printf neutered" replace P P-private-keys-masked "$O"'once("then printf '"'"'::add-mask::%s\\n'"'"' \"$line\"; fi; done <<<\"$keys\"", "then printf '"'"'%.0s'"'"' \"$line\"; fi; done <<<\"$keys\"")'
mut "W10 the mask jq selects numbers" replace P P-private-keys-masked "$O"'once("| .value | strings'"'"' \"$PLAN_DIR/tfplan.json\"", "| .value | numbers'"'"' \"$PLAN_DIR/tfplan.json\"")'
mut "m3 the tier_b check if false" replace T T-legacy-refused "$O"'once("if [[ \"$CRED_SOURCE\" != \"tier_b\" ]]; then", "if false; then")'
mut "m7 the confirm check if false" replace V V-confirm-refused "$O"'once("if [[ \"$CONFIRM_RAW\" != \"REPLACE-bastion\" ]]; then", "if false; then")'
mut "the pin check if false" replace V V-pin-refused-abc "$O"'once("if ! (LC_ALL=C; [[ \"$EXPECTED_ID_RAW\" =~", "if false && ! (LC_ALL=C; [[ \"$EXPECTED_ID_RAW\" =~")'
mut "security: the confirm text echoed into ::error::" replace V V-confirm-never-echoed "$O"'once("(the value given is not echoed: dispatch text never reaches a workflow command)", "(got '"'"'${CONFIRM_RAW}'"'"')")'
mut "Q-R6 the Require main refusal neutered" replace M M-branch-refused "$O"'once("[[ \"$GITHUB_REF\" == refs/heads/main ]] || {", "true || {")'
mut "Q-R6 the job-level if: restored" replace S S1-no-job-if "$O"'once("  bastion_host_replace:\n    runs-on:", "  bastion_host_replace:\n    if: github.ref == '"'"'refs/heads/main'"'"'\n    runs-on:")'
mut "pin 2 the anchor and apply swapped" replace S S2-order "$O"'a = s.index("      - name: Stamp boot-trail run anchor (bastion replace)")
b = s.index("      - name: Terraform apply (bastion replace)")
c = s.index("      - name: Verify the bastion boot")
s = s[:a] + s[b:c] + s[a:b] + s[c:]
n = 1'
mut "Q-R7 replace cancel records failed for a refusal" replace C C-cancel-records-refused "$O"'once("echo \"result=${_BBV_POWEROFF:-failed}\" >> \"$GITHUB_OUTPUT\"", "echo \"result=failed\" >> \"$GITHUB_OUTPUT\"")'
mut "Q-R7 replace cancel records a fixed success token" replace C C-cancel-records-absent "$O"'once("echo \"result=${_BBV_POWEROFF}\" >> \"$GITHUB_OUTPUT\"", "echo \"result=powered_off\" >> \"$GITHUB_OUTPUT\"")'
mut "Q-R7 a READY run still prints a dispatch line" replace D D-ready-needs-no-dispatch "$O"'once("elif [[ \"${APPLY_OUTCOME}/${VERIFY_OUTCOME}\" == success/success ]]; then", "elif false; then")'
mut "Q-R7 a run stopped before the plan still reads" replace D D-stopped-before-plan-reads-nothing-empty "$O"'once("if [[ \"${PLAN_OUTCOME:-skipped}\" == skipped ]]; then", "if [[ \"${PLAN_OUTCOME}\" == skipped ]]; then")'
mut "Q-R7 the replace summary loses its refused_no_preids cancel line" replace D D-summary-one-line-per-cancel-verdict "$O"'once("refused_no_preids) po=\"**power-off after a cancel REFUSED", "refused_no_preids_x) po=\"**power-off after a cancel REFUSED")'
mut "Q-R7 create cancel restores powered_off_or_absent" create X X-cancel-records-absent "$O"'once("echo \"result=${_BBV_POWEROFF}\" >> \"$GITHUB_OUTPUT\"", "echo \"result=powered_off_or_absent\" >> \"$GITHUB_OUTPUT\"")'
mut "Q-R7 create cancel records failed for a refusal" create X X-cancel-records-refused "$O"'once("echo \"result=${_BBV_POWEROFF:-failed}\" >> \"$GITHUB_OUTPUT\"", "echo \"result=failed\" >> \"$GITHUB_OUTPUT\"")'
mut "Q-R7 the create summary folds REFUSED into FAILED" create X X-summary-refused-is-not-failed "$O"'once("refused_no_preids) po=\"**power-off after a cancel REFUSED: the pre-apply id set was missing or malformed, so nothing was powered off.**", "refused_no_preids) po=\"**power-off after a cancel FAILED: the pre-apply id set was missing or malformed.**")'
mut "the retired token reappears in the create summary" create S S7-no-retired-cancel-token "$O"'once("            absent) po=\"Cancelled: no soleur-bastion server exists", "            powered_off_or_absent) po=\"x\" ;;\n            absent) po=\"Cancelled: no soleur-bastion server exists")'
mut "the create verify drops the pre-apply id set" create X X-verify-passes-four-args-and-its-rc "$O"'once(" bastion-host-create \"${PRE_IDS:-}\" || rc=$?", " bastion-host-create || rc=$?")'
MIN_MUT=44  # the literal number of mutation rows above
if [[ "$MUT_N" -eq "$MIN_MUT" ]]; then pass "exactly ${MIN_MUT} mutation rows ran"; else fail "${MUT_N} mutation rows ran, want ${MIN_MUT}"; fi

# ── Verdict ───────────────────────────────────────────────────────────────────────────────────
echo
MIN_CASES=143  # measured 2026-11-28: 1 control + 2 present + 3 control meta + MIN_CHECKS + MIN_MUT + 1
if [[ "$cases" -lt "$MIN_CASES" ]]; then
  printf 'test-bastion-host-replace-workflow: FAIL (only %d assertions ran; floor %d)\n' "$cases" "$MIN_CASES" >&2
  exit 1
fi
if [[ $((passes + fails)) -ne "$cases" ]]; then
  printf 'test-bastion-host-replace-workflow: FAIL (accounting: passes+fails=%d != cases=%d)\n' "$((passes + fails))" "$cases" >&2
  exit 1
fi
printf 'test-bastion-host-replace-workflow: %d passed, %d failed (%d assertions)\n' "$passes" "$fails" "$cases"
[[ "$fails" -eq 0 ]]
