#!/usr/bin/env bash
#
# Structural + behavioral + mutation gate for .github/workflows/apply-web-escrow-create.yml (#9377) and
# scripts/web-escrow-create-names.sh — the dispatch-only, create-only workflow that creates the web-class LUKS
# escrow resources (bucket, passphrase, three Doppler copies) while the push-apply is disabled.
#
# THE PROPERTY (Guard 1): the plan that is applied holds, apart from no-op and read entries, only entries whose
# address is one of the five escrow addresses and whose action list is exactly ["create"], and the shared
# destroy-guard output reads plan_ok true with all seven counters zero.
# THE PROPERTY (Guard 2): no doppler_secret create is applied while its name already exists live, and an
# unreadable listing is never read as "absent". No value of any secret reaches a log, summary or artifact.
#
# Structural rows parse the YAML (a grep would match the prose). Behavioral rows EXECUTE the extracted step
# bodies under GitHub's own `bash --noprofile --norc -eo pipefail`, against terraform and doppler stubs and the
# REAL shared jq filter. The mutation battery then applies one edit per row to a COPY of the workflow (or of the
# reader) and requires the named row to go RED while the pristine control is all green.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="${ESCROW_SUITE_REPO:-$(cd "$SCRIPT_DIR/../../.." && pwd)}"
WF_REL=".github/workflows/apply-web-escrow-create.yml"
READER_REL="scripts/web-escrow-create-names.sh"
FILTER_REL="tests/scripts/lib/destroy-guard-filter-web-platform.jq"
WF="$REPO/$WF_REL"
READER="$REPO/$READER_REL"
FILTER="$REPO/$FILTER_REL"
APPLY_WF="$REPO/.github/workflows/apply-web-platform-infra.yml"
HEADER_TF="$REPO/apps/web-platform/infra/workspaces-luks-header-web.tf"

pass=0
fail=0
ok() { pass=$((pass + 1)); printf 'ok   - %s\n' "$1"; }
no() { fail=$((fail + 1)); printf 'FAIL - %s\n' "$1"; }
# Instrument self-test: drive both verdicts once and refuse to continue unless both counters moved.
_st="$( pass=0; fail=0; ok x >/dev/null; no y >/dev/null; printf '%s/%s' "$pass" "$fail" )"
[[ "$_st" == "1/1" ]] || { printf 'INSTRUMENT FAIL - ok()/no() self-test got %s, want 1/1\n' "$_st"; exit 2; }

[[ -f "$WF" ]] || { no "the escrow-create workflow is missing at $WF_REL"; printf '\n%s passed, %s failed\n' "$pass" "$fail"; exit 1; }
[[ -f "$READER" ]] || { no "the names reader is missing at $READER_REL"; printf '\n%s passed, %s failed\n' "$pass" "$fail"; exit 1; }
python3 -c 'import yaml' 2>/dev/null || pip3 install --quiet pyyaml

SCRATCH="$(mktemp -d -t wl-escrow-create.XXXXXXXX)" || { printf 'INSTRUMENT FAIL - mktemp\n'; exit 2; }
trap 'rm -rf "$SCRATCH"' EXIT INT TERM HUP

# --- the structural analyzer (python, parsed YAML) -------------------------------------------------------
cat > "$SCRATCH/analyze.py" <<'PY'
import sys, re, yaml, json
wf_path, apply_path, tf_path, outdir = sys.argv[1:5]
text = open(wf_path).read()
wf = yaml.safe_load(text)
ap = yaml.safe_load(open(apply_path))
rows = []
def check(rid, name, cond, detail=""):
    d = str(detail)[:200].replace("\t", " ").replace("\n", " ")
    rows.append(("ok" if cond else "FAIL", rid, name + ((" (" + d + ")") if (not cond and d) else "")))

def strip_comments(s):
    return "\n".join(l for l in s.splitlines() if not l.lstrip().startswith("#"))

tf = open(tf_path).read()
ADDRS = [f"{t}.{n}" for t, n in re.findall(r'^resource\s+"([a-z_0-9]+)"\s+"([A-Za-z0-9_]+)"', tf, re.M)]
check("T0", "workspaces-luks-header-web.tf declares exactly the five escrow addresses", len(ADDRS) == 5, ADDRS)

on = wf.get(True) or wf.get("on") or {}
inp = ((on.get("workflow_dispatch") or {}).get("inputs")) or {}
check("T1", "workflow_dispatch is the ONLY trigger", set(on) == {"workflow_dispatch"}, sorted(on))
check("T2", "inputs are exactly confirm, reason, plan_only", set(inp) == {"confirm", "reason", "plan_only"}, sorted(inp))
po = inp.get("plan_only") or {}
check("T3", "plan_only is a boolean input defaulting to true", po.get("type") == "boolean" and po.get("default") is True, po)
conc = wf.get("concurrency") or {}
apply_group = (ap.get("concurrency") or {}).get("group")
check("T4", "workflow-level concurrency group is the apply workflow's literal terraform-apply-web-platform-host, cancel-in-progress false",
      conc.get("group") == apply_group == "terraform-apply-web-platform-host" and conc.get("cancel-in-progress") is False, f"{conc} vs {apply_group}")
jobs = wf.get("jobs") or {}
check("T5", "exactly one job `create`, environment infra-privileged", list(jobs) == ["create"] and (jobs.get("create") or {}).get("environment") == "infra-privileged", list(jobs))
job = jobs.get("create") or {}
check("T4b", "no job-level concurrency (the web-1-swap group is deliberately NOT taken)", "concurrency" not in job and "web-1-swap" not in strip_comments(text), job.get("concurrency"))
check("T6", "permissions are exactly contents: read", wf.get("permissions") == {"contents": "read"} and "permissions" not in job, wf.get("permissions"))
env = wf.get("env") or {}
aenv = ap.get("env") or {}
check("T7", "TERRAFORM_VERSION equals the apply workflow's and TF_VAR_terraform_version equals it",
      env.get("TERRAFORM_VERSION") == aenv.get("TERRAFORM_VERSION") and env.get("TF_VAR_terraform_version") == env.get("TERRAFORM_VERSION") and bool(env.get("TERRAFORM_VERSION")),
      f"{env.get('TERRAFORM_VERSION')} / {env.get('TF_VAR_terraform_version')} vs {aenv.get('TERRAFORM_VERSION')}")
check("T7b", "timeout-minutes is 15 and INFRA_DIR is apps/web-platform/infra", job.get("timeout-minutes") == 15 and env.get("INFRA_DIR") == "apps/web-platform/infra")
steps = job.get("steps") or []
def idx(pred):
    for i, st in enumerate(steps):
        if pred(st):
            return i
    return -1
ids = ("validate", "plan", "gate", "names", "apply", "reread", "summary")
pos = {sid: idx(lambda st, sid=sid: st.get("id") == sid) for sid in ids}
for sid in ids:
    check(f"T0-{sid}", f"exactly one step with id {sid}", sum(1 for st in steps if st.get("id") == sid) == 1)
i_loader = idx(lambda st: st.get("uses") == "./.github/actions/infra-credentials")
i_extract = idx(lambda st: st.get("name") == "Extract backend credentials")
i_init = idx(lambda st: st.get("name") == "Terraform init")
order = [pos["validate"], i_loader, i_extract, i_init, pos["plan"], pos["gate"], pos["names"], pos["apply"], pos["reread"], pos["summary"]]
check("T14", "step order: validate < loader < extract < init < plan < gate < names < apply < reread < summary",
      -1 not in order and order == sorted(order) and len(set(order)) == len(order), order)

runs = [st for st in steps if st.get("run")]
code = "\n".join(strip_comments(str(st["run"])) for st in runs)
tcode = strip_comments(text)
check("T8", "no cf-tunnel-ssh-bridge, no ci_ssh_private_key, no ssh/scp at command position (ssh-keygen for the dummy public key excepted)",
      "cf-tunnel-ssh-bridge" not in tcode and "ci_ssh_private_key" not in tcode and not re.search(r"(?<![\w.-])(ssh|scp|sftp|rsync)(?![-\w])", code))
verbs = set(re.findall(r"\bterraform\s+([a-z][a-z-]*)", code))
check("T9", "the only terraform verbs are init, plan, show, apply; no sentry-heartbeat; no gh call",
      verbs <= {"init", "plan", "show", "apply"} and {"init", "plan", "show", "apply"} <= verbs and "sentry-heartbeat" not in tcode and not re.search(r"(^|[;&|(]\s*)gh\s", code, re.M), sorted(verbs))
plan_run = str((steps[pos["plan"]] if pos["plan"] >= 0 else {}).get("run", ""))
plan_code = strip_comments(plan_run)
targets = re.findall(r"-target=(\S+)", plan_code)
check("T10", "the plan step has exactly five -target flags, equal to the five addresses of workspaces-luks-header-web.tf, no -replace, one -out=tfplan",
      sorted(targets) == sorted(ADDRS) and len(targets) == 5 and "-replace" not in tcode and len(re.findall(r"-out=tfplan\b", plan_code)) == 1, targets)
check("T10b", "exactly one `terraform plan`, one `terraform show -json tfplan`, one `terraform apply`",
      len(re.findall(r"terraform plan\b", code)) == 1 and len(re.findall(r"terraform show -json tfplan\b", code)) == 1 and len(re.findall(r"terraform apply\b", code)) == 1)
gate_run = str((steps[pos["gate"]] if pos["gate"] >= 0 else {}).get("run", ""))
gate_code = strip_comments(gate_run)
m = re.search(r"^\s*ALLOW_JSON='(\[[^']*\])'", gate_code, re.M)
try:
    allow = json.loads(m.group(1)) if m else []
except Exception:
    allow = []
check("T11", "the gate allow-set literal equals the same five addresses (and the plan step's targets)", sorted(allow) == sorted(ADDRS) == sorted(targets) and len(allow) == 5, allow)
CTRS = ["resource_deletes", "nested_deletes", "reboot_updates", "host_creates", "luks_passphrase_rotations", "undecidable_entries", "apex_move_orphans"]
mc = re.search(r'^\s*COUNTERS="([^"]*)"', gate_code, re.M)
got = mc.group(1).split() if mc else []
check("T13", "the gate reads plan_ok and exactly the seven shared counters, requiring each zero",
      sorted(got) == sorted(CTRS) and len(got) == 7 and "plan_ok" in gate_code and "destroy-guard-filter-web-platform.jq" in gate_code, got)
for sid in ("validate", "gate", "names"):
    st = next((x for x in steps if x.get("id") == sid), {})
    check(f"T12-{sid}", f"step `{sid}` carries no continue-on-error and no if: (a failed guard must end the job)", bool(st) and "continue-on-error" not in st and "if" not in st, {k: st.get(k) for k in ("if", "continue-on-error")})
hdr = "\n".join(l for l in text.split("\nname:")[0].splitlines())
check("T15", "the header states that first-create legality ends once a web-class volume is formatted (#9372 rebirth)",
      "first-create legality ends once a web-class volume is formatted (#9372 rebirth)" in hdr)
GUARD = "inputs.plan_only != true"
ifs = {str(st.get("id") or st.get("name")): st.get("if") for st in steps if "if" in st}
check("T16", "apply and reread carry exactly `if: inputs.plan_only != true`; summary carries `if: always()`; nothing else carries an if:",
      ifs == {"apply": GUARD, "reread": GUARD, "summary": "always()"}, ifs)
check("T17", "no step is ENABLED by plan_only (every plan_only reference in an if: is the subtractive != true form)",
      all(("plan_only" not in str(v)) or str(v) == GUARD for v in ifs.values()) and "plan_only == " not in tcode)
check("T18", "no hcloud_ token in any run body, target or env (no host in reach)", "hcloud_" not in tcode and "HCLOUD" not in tcode, [l for l in tcode.splitlines() if "hcloud" in l.lower()][:2])
check("T20a", "every run: step refuses to run under xtrace", all(re.search(r"case \$- in \*x\*\)", str(st["run"])) for st in runs), [st.get("name") for st in runs if not re.search(r"case \$- in \*x\*\)", str(st["run"]))])
check("T20b", "no run: body interpolates ${{ inputs.* }} (inputs reach the shell only through env:)", not any("${{ inputs." in str(st["run"]) for st in runs))
dr = [l for l in code.splitlines() if re.search(r"\bdoppler run\b", l)]
check("T20c", "every `doppler run` carries --preserve-env", len(dr) >= 3 and all("--preserve-env" in l for l in dr), dr)
check("T20d", "no artifact upload, no tee, no continue-on-error anywhere", "upload-artifact" not in tcode and not re.search(r"\btee\b", code) and "continue-on-error" not in tcode)
a_ex = next((st for st in ((ap.get("jobs") or {}).get("apply") or {}).get("steps") or [] if st.get("name") == "Extract backend credentials"), None)
ENVW = re.compile(r"^\s*(d1=|printf '(AWS_ACCESS_KEY_ID|AWS_SECRET_ACCESS_KEY)(=|<<)).*$", re.M)
if i_extract >= 0 and a_ex:
    mine_raw = str(steps[i_extract].get("run", ""))
    mine = ENVW.sub("", re.sub(r"^case \$- in \*x\*\).*\n", "", mine_raw)).strip()
    theirs = ENVW.sub("", str(a_ex.get("run", ""))).strip()
    check("T21", "Extract backend credentials is the apply job's step (after the xtrace prelude), except its GITHUB_ENV write",
          re.sub(r"\n\s*\n", "\n", mine) == re.sub(r"\n\s*\n", "\n", theirs) and steps[i_extract].get("env") == a_ex.get("env"))
    check("T21b", "the backend credentials reach GITHUB_ENV ONLY in the heredoc-delimiter form, never K=V",
          len(re.findall(r"printf '(AWS_ACCESS_KEY_ID|AWS_SECRET_ACCESS_KEY)<<%s\\n%s\\n%s\\n' \"\$d[12]\" \"\$(KEY_ID|SECRET)\" \"\$d[12]\" >> \"\$GITHUB_ENV\"", mine_raw)) == 2
          and not re.search(r"printf '(AWS_ACCESS_KEY_ID|AWS_SECRET_ACCESS_KEY)=%s", mine_raw))
else:
    check("T21", "Extract backend credentials step and the apply job's twin both exist", False)
if i_init >= 0:
    st = steps[i_init]
    check("T22", "Terraform init runs -input=false -lockfile=readonly in the main root",
          "terraform init -input=false -lockfile=readonly" in str(st.get("run", "")) and st.get("working-directory") == "${{ env.INFRA_DIR }}")
val_run = str((steps[pos["validate"]] if pos["validate"] >= 0 else {}).get("run", ""))
check("T23", "the reason is echoed to GITHUB_STEP_SUMMARY by the validate step", "GITHUB_STEP_SUMMARY" in val_run and "REASON" in val_run and "CREATE-WEB-ESCROW" in val_run)
apply_run = strip_comments(str((steps[pos["apply"]] if pos["apply"] >= 0 else {}).get("run", "")))
check("T24", "the apply step applies the saved plan tfplan with -auto-approve and no flag naming a resource",
      bool(re.search(r"terraform apply\b[^\n]*-auto-approve[^\n]*\btfplan\s*$", apply_run, re.M)) and "-target" not in apply_run and "-replace" not in apply_run, apply_run[-160:])
dop = [i for i, st in enumerate(steps) if re.search(r"\bdoppler secrets\b", strip_comments(str(st.get("run", ""))))]
check("T25", "no step reads Doppler names or values except the Extract backend credentials step (the reader script is the only names chokepoint)", dop == [i_extract], dop)
rd = [st.get("id") for st in steps if "web-escrow-create-names.sh" in str(st.get("run", ""))]
check("T26", "exactly the names and reread steps call the reader", sorted(rd) == ["names", "reread"], rd)
envok = all(((next((x for x in steps if x.get("id") == sid), {}).get("env") or {}).get("DOPPLER_TOKEN") == "${{ secrets.DOPPLER_TOKEN }}") for sid in ("plan", "names", "apply", "reread"))
check("T27", "plan, names, apply and reread carry env DOPPLER_TOKEN from secrets.DOPPLER_TOKEN (the Tier-A token the loader-less doppler run needs)", envok)
check("T28", "no unqualified encryption claim about web hosts anywhere in the file", not re.search(r"web-2 (is|will be) (LUKS|encrypted)|LUKS-backed", text, re.I))
check("T29", "the workflow never reads the Doppler value of any secret (no `doppler secrets get` / download outside Extract backend credentials)",
      all(not re.search(r"doppler secrets (get|download)", strip_comments(str(st.get("run", "")))) for i, st in enumerate(steps) if i != i_extract))
open(f"{outdir}/rows.tsv", "w").write("\n".join("\t".join(r) for r in rows) + "\n")
for sid in ids:
    st = next((x for x in steps if x.get("id") == sid), None)
    if st:
        open(f"{outdir}/{sid}.sh", "w").write(str(st.get("run", "")))
with open(f"{outdir}/wf-env.txt", "w") as fh:
    for k, v in env.items():
        fh.write(f"{k}={v}\n")
PY

# --- stubs ------------------------------------------------------------------------------------------
BIN="$SCRATCH/bin"; mkdir -p "$BIN"
cat > "$BIN/terraform" <<'STUB'
#!/usr/bin/env bash
printf 'terraform %s\n' "$*" >> "$TF_LOG"
case "${1:-} ${2:-}" in
  "show -json") cat "$TF_PLAN_JSON" ;;
  *) echo "STUB_UNKNOWN terraform $*" >> "$TF_LOG"; exit 64 ;;
esac
STUB
cat > "$BIN/doppler" <<'STUB'
#!/usr/bin/env bash
printf 'doppler %s\n' "$*" >> "$DOPPLER_LOG"
case "${1:-}" in
  run)
    shift
    while [ $# -gt 0 ] && [ "$1" != -- ]; do shift; done
    [ "${1:-}" = -- ] && shift
    exec env TF_VAR_doppler_token_tf="$STUB_PROVIDER_TOKEN" "$@" ;;
  secrets)
    [ "${2:-}" = --only-names ] || { echo "STUB_UNKNOWN doppler $*" >> "$DOPPLER_LOG"; exit 64; }
    case "$*" in *"-c prd_workspaces_luks_web"*) ;; *) echo "Doppler Error: wrong config" >&2; exit 1 ;; esac
    [ "${DOPPLER_TOKEN:-}" = "$STUB_PROVIDER_TOKEN" ] || { echo "Doppler Error: invalid token" >&2; exit 1; }
    case "${DOPPLER_MODE:-ok}" in
      fail) echo "Unable to fetch secret names" >&2; echo "Doppler Error: boom dp.st.abcdef0123456789" >&2; exit 1 ;;
      empty) exit 0 ;;
      nohdr) echo "something else entirely"; exit 0 ;;
      hdronly) printf '┌──────┐\n│ NAME │\n├──────┤\n└──────┘\n'; exit 0 ;;
      ok) printf '┌──────┐\n│ NAME │\n├──────┤\n'; while IFS= read -r n; do [ -n "$n" ] && printf '│ %s │\n' "$n"; done < "$DOPPLER_NAMES_FILE"; printf '└──────┘\n'; exit 0 ;;
    esac ;;
  *) echo "STUB_UNKNOWN doppler $*" >> "$DOPPLER_LOG"; exit 64 ;;
esac
STUB
chmod +x "$BIN"/*

SECRET='SUPER-SECRET-ESCROW-PASSPHRASE-SYNTH-9377'
ADDR_BUCKET='cloudflare_r2_bucket.workspaces_luks_header_web'
ADDR_PW='random_password.workspaces_luks_web'
ADDR_KEY='doppler_secret.workspaces_luks_web_key'
ADDR_HB='doppler_secret.workspaces_luks_web_header_bucket'
ADDR_EP='doppler_secret.workspaces_luks_web_header_r2_endpoint'
FIVE=("$ADDR_BUCKET|create" "$ADDR_PW|create" "$ADDR_KEY|create" "$ADDR_HB|create" "$ADDR_EP|create")
BASE=('doppler_config.workspaces_luks_web|no-op' 'doppler_service_token.workspaces_luks_fresh_boot_web|no-op' 'data.doppler_secrets.x|read')

# mkplan <out> "addr|verb[,verb]" ... — a REAL-shaped plan (no-op / read rows, create rows with `after` and
# unknowns). Special verbs: @null (actions null), @missing (no change object). "addr|" is an EMPTY action list.
mkplan() {
  local out="$1"; shift
  jq -n --arg secret "$SECRET" --args '
    def split_addr: (. | sub("^data\\."; "") | capture("^(?:module\\.[^.]+\\.)*(?<t>[a-z_0-9]+)\\.(?<n>[A-Za-z0-9_]+)"));
    { format_version: "1.2", terraform_version: "1.10.5",
      resource_changes: [ $ARGS.positional[] | split("|") | . as $p
        | ($p[0]) as $addr | ($p[1] // "") as $v
        | ($addr | split_addr) as $s
        | { address: $addr, mode: (if ($addr | startswith("data.")) then "data" else "managed" end), type: $s.t, name: $s.n, provider_name: "x" }
          + (if $v == "@missing" then {}
             else { change: { actions: (if $v == "@null" then null else ($v | split(",")) end),
                              before: null, after: { value: $secret }, after_unknown: { id: true } } } end) ] }' --args "$@" > "$out"
}

# --- one full run of the suite against a workflow copy and a workspace --------------------------------
# suite <workflow-file> <workspace-dir> <rows-file> : appends "ID<TAB>ok|FAIL<TAB>text" rows.
suite() {
  local wf="$1" ws="$2" ROWS="$3" od; od="$(mktemp -d "$SCRATCH/an.XXXXXX")"
  : > "$ROWS"
  R() { printf '%s\t%s\t%s\n' "$2" "$1" "$3" >> "$ROWS"; }          # R <ok|FAIL> <id> <text>
  chk() { [[ "$3" == 0 ]] && R ok "$1" "$2" || R FAIL "$1" "$2"; }   # chk <id> <text> <rc>
  python3 "$SCRATCH/analyze.py" "$wf" "$APPLY_WF" "$HEADER_TF" "$od" 2> "$od/py.err" || R FAIL "T-analyzer" "the analyzer crashed: $(head -c 200 "$od/py.err")"
  [[ -f "$od/rows.tsv" ]] && while IFS=$'\t' read -r v id name; do [[ -n "${v:-}" ]] && R "$v" "$id" "$name"; done < "$od/rows.tsv"
  local WF_ENV=(); local l
  [[ -f "$od/wf-env.txt" ]] && while IFS= read -r l; do [[ -n "$l" ]] && WF_ENV+=("$l"); done < "$od/wf-env.txt"
  local RT="$od/rt"; mkdir -p "$RT"
  # run_step <step-id> [VAR=value ...]: sets RC, OUT; the files GitHub would read live under $od.
  local RC OUT
  run_step() {
    local f="$od/$1.sh"; shift
    : > "$od/gh_output"; : > "$od/gh_summary"; : > "$od/gh_env"
    RC=0
    OUT="$(cd "$ws" && env PATH="$BIN:$PATH" TF_LOG="$od/tf.log" DOPPLER_LOG="$od/doppler.log" TF_PLAN_JSON="$od/plan.json" \
      DOPPLER_NAMES_FILE="$od/names.fix" STUB_PROVIDER_TOKEN=provider-synth-token DOPPLER_TOKEN=tier-a-synth-token \
      GITHUB_OUTPUT="$od/gh_output" GITHUB_STEP_SUMMARY="$od/gh_summary" GITHUB_ENV="$od/gh_env" GITHUB_WORKSPACE="$ws" RUNNER_TEMP="$RT" GITHUB_SERVER_URL=https://github.com GITHUB_REPOSITORY=jikig-ai/soleur GITHUB_RUN_ID=1 \
      "${WF_ENV[@]}" "$@" bash --noprofile --norc -eo pipefail "$f" 2>&1)" || RC=$?
  }
  leaked() { grep -qF "$SECRET" <<<"$OUT" || grep -qF "$SECRET" "$od/gh_output" "$od/gh_summary" "$od/gh_env" "$RT"/escrow-creates.txt "$RT"/escrow-names*.txt 2>/dev/null; }
  : > "$od/tf.log"; : > "$od/doppler.log"

  # ---- validate (typo-guard) ----
  if [[ -f "$od/validate.sh" ]]; then
    local r
    run_step validate CONFIRM_RAW=CREATE-WEB-ESCROW REASON_RAW="web-2 needs the escrow config (8609 R5)" PLAN_ONLY_RAW=true; r=$RC
    [[ "$r" == 0 ]] && grep -qF "web-2 needs the escrow config" "$od/gh_summary"; chk V1 "the exact confirm token + a reason pass, and the reason lands in the step summary" $?
    run_step validate CONFIRM_RAW=CREATE-WEB-ESCROW REASON_RAW="ok" PLAN_ONLY_RAW=false; r=$RC
    [[ "$r" == 0 ]] && grep -qiE "plan_only.*false" "$od/gh_summary"; chk V1b "plan_only is echoed to the summary" $?
    run_step validate CONFIRM_RAW=CREATE-WEB-ESCROW-X REASON_RAW="x" PLAN_ONLY_RAW=true; [[ "$RC" != 0 ]]; chk V2 "a wrong confirm token is refused" $?
    run_step validate CONFIRM_RAW=REPLACE-web-2 REASON_RAW="x" PLAN_ONLY_RAW=true; [[ "$RC" != 0 ]]; chk V2b "another workflow's confirm token is refused" $?
    run_step validate CONFIRM_RAW=CREATE-WEB-ESCROW REASON_RAW="   " PLAN_ONLY_RAW=true; [[ "$RC" != 0 ]]; chk V3 "a blank (whitespace-only) reason is refused" $?
    run_step validate CONFIRM_RAW=CREATE-WEB-ESCROW REASON_RAW="" PLAN_ONLY_RAW=true; [[ "$RC" != 0 ]]; chk V3b "an empty reason is refused" $?
    run_step validate CONFIRM_RAW=CREATE-WEB-ESCROW REASON_RAW=$'evil\n::error::injected\x1b[31m red' PLAN_ONLY_RAW=true
    [[ "$RC" == 0 ]] && ! grep -q $'\x1b' "$od/gh_summary" && ! grep -q '^::' "$od/gh_summary" && ! grep -q '^::error::injected' <<<"$OUT"; chk V4 "a reason with a newline and an escape sequence cannot inject a command or a control sequence" $?
  fi

  # ---- gate ----
  if [[ -f "$od/gate.sh" ]]; then
    gate() { # gate <plan-args...> ; sets RC OUT, creates file at $RT/escrow-creates.txt
      rm -f "$RT"/escrow-*; mkplan "$od/plan.json" "$@"; run_step gate
    }
    local want got
    gate "${BASE[@]}" "${FIVE[@]}"
    got="$(LC_ALL=C sort "$RT/escrow-creates.txt" 2>/dev/null | paste -sd, )"; want="$(printf '%s\n' "$ADDR_BUCKET" "$ADDR_PW" "$ADDR_KEY" "$ADDR_HB" "$ADDR_EP" | LC_ALL=C sort | paste -sd,)"
    [[ "$RC" == 0 && "$got" == "$want" ]]; chk G-happy "five creates among no-op/read entries pass, and the creates file holds exactly the five addresses (rc=$RC)" $?
    ! leaked; chk G-leak "the gate prints no plan value (a fixture value rides every create's after)" $?
    gate "$ADDR_PW|create" "${BASE[@]}" "$ADDR_KEY|create" "$ADDR_BUCKET|create"
    got="$(LC_ALL=C sort "$RT/escrow-creates.txt" 2>/dev/null | paste -sd, )"; want="$(printf '%s\n' "$ADDR_BUCKET" "$ADDR_PW" "$ADDR_KEY" | LC_ALL=C sort | paste -sd,)"
    [[ "$RC" == 0 && "$got" == "$want" ]]; chk G-subset "a subset of three creates in a different order passes and lists only those three" $?
    gate "${BASE[@]}"
    [[ "$RC" == 0 && -f "$RT/escrow-creates.txt" && ! -s "$RT/escrow-creates.txt" ]]; chk G-zero "zero non-no-op entries pass with an empty creates file" $?
    refuse() { # refuse <id> <text> <plan-args...>
      local id="$1" tx="$2"; shift 2; gate "$@"; [[ "$RC" != 0 ]]; chk "$id" "$tx" $?
    }
    refuse B-gate-config "a doppler_config create aborts" "${BASE[@]}" "${FIVE[@]}" 'doppler_config.workspaces_luks_web|create'
    grep -qiE "cannot (import|create)|import" <<<"$OUT"; chk B-gate-config-msg "the doppler_config abort names the next action (no import verb here; a reviewed change)" $?
    refuse B-gate-replace "a passphrase replace [delete,create] aborts" "${BASE[@]}" "$ADDR_PW|delete,create" "$ADDR_KEY|create"
    refuse B-gate-replace2 "a passphrase replace [create,delete] aborts" "${BASE[@]}" "$ADDR_PW|create,delete"
    refuse B-gate-delete "a bare delete of an allowed address aborts" "${BASE[@]}" "$ADDR_BUCKET|delete"
    refuse B-gate-forget "a forget of an allowed address aborts" "${BASE[@]}" "$ADDR_KEY|forget"
    refuse B-gate-update "an update of the key copy aborts" "${BASE[@]}" "$ADDR_KEY|update"
    refuse B-gate-update2 "a create+update on an allowed address (not exactly [create]) aborts" "${BASE[@]}" "$ADDR_KEY|create,update"
    refuse B-gate-second "five legal creates followed by one host create abort (the LAST entry is graded too)" "${BASE[@]}" "${FIVE[@]}" 'hcloud_server.web["web-2"]|create'
    refuse B-gate-second2 "one host create BEFORE five legal creates aborts" 'hcloud_server.web["web-2"]|create' "${FIVE[@]}"
    refuse B-gate-other-create "a create at an address outside the five that no counter can see (cloudflare_record.app) aborts" "${BASE[@]}" "${FIVE[@]}" 'cloudflare_record.app|create'
    refuse B-gate-second3 "five legal creates followed by an out-of-set create (invisible to every counter) abort: the LAST entry is graded by the allow-set" "${BASE[@]}" "${FIVE[@]}" 'cloudflare_record.app|create'
    refuse B-gate-second4 "an out-of-set create BEFORE five legal creates aborts" 'cloudflare_record.app|create' "${FIVE[@]}"
    refuse B-gate-bucket-update "an update of the bucket (no counter reads it) aborts" "${BASE[@]}" "$ADDR_BUCKET|update"
    refuse B-gate-bucket-createupdate "a [create,update] on the bucket (no counter reads it) aborts: the verb list must be exactly [create]" "${BASE[@]}" "$ADDR_BUCKET|create,update"
    refuse B-gate-bucket-updatecreate "an [update,create] on the bucket aborts" "${BASE[@]}" "$ADDR_BUCKET|update,create"
    refuse B-gate-other-update "an update at an address outside the five aborts" "${BASE[@]}" "$ADDR_KEY|create" 'doppler_config.workspaces_luks_web|update'
    refuse B-gate-indexed "an indexed spelling of an allowed address aborts" "${BASE[@]}" "random_password.workspaces_luks_web[\"web-2\"]|create"
    refuse B-gate-module "a module-prefixed spelling of an allowed address aborts" "${BASE[@]}" 'module.x.doppler_secret.workspaces_luks_web_key|create'
    refuse B-gate-token "the fresh-boot service token appearing as a create aborts" "${BASE[@]}" "$ADDR_KEY|create" 'doppler_service_token.workspaces_luks_fresh_boot_web|create'
    refuse B-gate-emptyactions "an entry with an EMPTY action list aborts" "${BASE[@]}" "$ADDR_KEY|create" 'hcloud_volume.workspaces|'
    refuse B-gate-nullactions "an entry with null actions aborts" "${BASE[@]}" "$ADDR_KEY|create" "$ADDR_PW|@null"
    refuse B-gate-nochange "an entry with no change object aborts" "${BASE[@]}" "$ADDR_PW|@missing"
    printf '{}' > "$od/plan.json"; rm -f "$RT"/escrow-*; run_step gate; [[ "$RC" != 0 ]]; chk B-gate-noarray "a plan JSON with no resource_changes array aborts (plan_ok)" $?
    printf '{"resource_changes":null}' > "$od/plan.json"; rm -f "$RT"/escrow-*; run_step gate; [[ "$RC" != 0 ]]; chk B-gate-nullarray "a plan JSON with resource_changes null aborts" $?
    # The counters block, driven independently of the allow-set through a stub filter.
    local good='{"plan_ok":true,"resource_deletes":0,"nested_deletes":0,"reboot_updates":0,"host_creates":0,"luks_passphrase_rotations":0,"undecidable_entries":0,"apex_move_orphans":0}'
    local realf="$ws/$FILTER_REL" c
    cp "$realf" "$od/real.jq"
    stubfilter() { printf '%s\n' "$1" > "$realf"; }
    stubfilter "$good"; gate "${BASE[@]}" "$ADDR_KEY|create"; [[ "$RC" == 0 ]]; chk G-ctr-control "the stub filter with all counters zero passes (control for the counter rows)" $?
    for c in resource_deletes nested_deletes reboot_updates host_creates luks_passphrase_rotations undecidable_entries apex_move_orphans; do
      stubfilter "$(jq -c --arg c "$c" '.[$c] = 1' <<<"$good")"; gate "${BASE[@]}" "$ADDR_KEY|create"; [[ "$RC" != 0 ]]; chk "B-gate-ctr-$c" "$c = 1 aborts even when the allow-set is clean" $?
      stubfilter "$(jq -c --arg c "$c" 'del(.[$c])' <<<"$good")"; gate "${BASE[@]}" "$ADDR_KEY|create"; [[ "$RC" != 0 ]]; chk "B-gate-ctrmiss-$c" "$c absent from the filter output aborts (null is not zero)" $?
    done
    stubfilter "$(jq -c '.plan_ok = false' <<<"$good")"; gate "${BASE[@]}" "$ADDR_KEY|create"; [[ "$RC" != 0 ]]; chk B-gate-planok "plan_ok false aborts" $?
    stubfilter "$(jq -c '.host_creates = ""' <<<"$good")"; gate "${BASE[@]}" "$ADDR_KEY|create"; [[ "$RC" != 0 ]]; chk B-gate-ctr-empty "an empty-string counter aborts (non-numeric is not zero)" $?
    cp "$od/real.jq" "$realf"
  fi

  # ---- T19: the reader reads names only ----
  local rcode; rcode="$(grep -v '^[[:space:]]*#' "$ws/$READER_REL" 2>/dev/null || true)"
  [[ -n "$rcode" ]] && ! grep -E 'doppler[[:space:]]+secrets' <<<"$rcode" | grep -qv -- '--only-names' \
    && ! grep -qE 'doppler[[:space:]]+(run|configs|projects|login|setup|me)\b|secrets[[:space:]]+(get|download|set|delete|upload)\b' <<<"$rcode"
  chk T19 "the reader only lists names (doppler secrets --only-names): no get, download, run or set verb" $?
  [[ "$(grep -cE '\bdoppler[[:space:]]+secrets[[:space:]]+--only-names\b' <<<"$rcode")" == 1 ]]; chk T19b "the reader has exactly one listing call" $?

  # ---- names (live precondition) + reader ----
  if [[ -f "$od/names.sh" ]]; then
    local INH=(SENTINEL_INHERITED_ALPHA SENTINEL_INHERITED_BETA DOPPLER_PROJECT DOPPLER_CONFIG)
    setnames() { printf '%s\n' "$@" > "$od/names.fix"; }
    names() { # names <creates...> ; env passed through $NENV array
      rm -f "$RT"/escrow-names*; printf '%s\n' "$@" > "$RT/escrow-creates.txt"; [[ "$#" == 0 ]] && : > "$RT/escrow-creates.txt"
      run_step names "${NENV[@]}"
    }
    local NENV=()
    setnames "${INH[@]}"
    names "$ADDR_BUCKET" "$ADDR_PW" "$ADDR_KEY" "$ADDR_HB" "$ADDR_EP"
    [[ "$RC" == 0 ]] && grep -q "WORKSPACES_LUKS_KEY" <<<"$OUT" && grep -qi "absent" <<<"$OUT"; chk N-absent "all three names absent: the precondition passes and reports each name's state (rc=$RC)" $?
    ! grep -q "SENTINEL_INHERITED" <<<"$OUT"; chk N-log "the step output carries none of the inherited names (the listing goes to a file, never the public log)" $?
    setnames "${INH[@]}" WORKSPACES_LUKS_KEY
    names "$ADDR_BUCKET" "$ADDR_PW" "$ADDR_KEY" "$ADDR_HB" "$ADDR_EP"
    [[ "$RC" != 0 ]] && grep -q "WORKSPACES_LUKS_KEY" <<<"$OUT"; chk B-names-present "the key name already exists live: abort, naming the secret name" $?
    ! grep -q "SENTINEL_INHERITED" <<<"$OUT"; chk B-names-log-fail "an aborting run also prints none of the inherited names" $?
    setnames "${INH[@]}" WORKSPACES_HEADER_BUCKET
    names "$ADDR_BUCKET" "$ADDR_PW" "$ADDR_KEY" "$ADDR_HB" "$ADDR_EP"; [[ "$RC" != 0 ]]; chk B-names-second "the bucket-name copy exists, the key copy does not: abort (every created copy is checked)" $?
    local pair a n
    for pair in "$ADDR_KEY=WORKSPACES_LUKS_KEY" "$ADDR_HB=WORKSPACES_HEADER_BUCKET" "$ADDR_EP=WORKSPACES_HEADER_R2_ENDPOINT"; do
      a="${pair%%=*}"; n="${pair##*=}"
      setnames "${INH[@]}" "$n"; names "$a"; [[ "$RC" != 0 ]]; chk "B-names-map-$n" "$a created while $n exists aborts" $?
      setnames "${INH[@]}" "$n"; names "$ADDR_BUCKET" "$ADDR_PW"; [[ "$RC" == 0 ]]; chk "N-map-unrelated-$n" "$n exists but its address is not being created: pass (the map is per address)" $?
    done
    setnames "${INH[@]}" WORKSPACES_LUKS_KEY WORKSPACES_HEADER_BUCKET WORKSPACES_HEADER_R2_ENDPOINT
    names "$ADDR_BUCKET" "$ADDR_PW"; [[ "$RC" == 0 ]]; chk N-nocopies "no doppler_secret is created: existing names are not an abort" $?
    names; [[ "$RC" == 0 ]]; chk N-zero "an empty creates file passes (the listing is still read)" $?
    setnames "${INH[@]}"
    NENV=(DOPPLER_MODE=fail); names "$ADDR_KEY"; [[ "$RC" != 0 ]]; chk B-names-unreadable "an unreadable listing (doppler exits 1) aborts and is never read as absent" $?
    ! grep -q "dp.st.abcdef0123456789" <<<"$OUT"; chk N-redact "a token shape in the CLI's stderr is redacted from the failure line" $?
    NENV=(DOPPLER_MODE=empty); names "$ADDR_KEY"; [[ "$RC" != 0 ]]; chk B-names-empty "an empty listing aborts (a failed read and an empty config look alike)" $?
    NENV=(DOPPLER_MODE=hdronly); names "$ADDR_KEY"; [[ "$RC" != 0 ]]; chk B-names-hdronly "a header-only listing aborts" $?
    NENV=(DOPPLER_MODE=nohdr); names "$ADDR_KEY"; [[ "$RC" != 0 ]]; chk B-names-nohdr "an unrecognised listing shape aborts" $?
    NENV=()
    # token plumbing: the reader fails closed with no provider token, and never uses the ambient Tier-A token.
    local rrc=0; ( cd "$ws" && env -u TF_VAR_doppler_token_tf PATH="$BIN:$PATH" DOPPLER_LOG="$od/doppler.log" STUB_PROVIDER_TOKEN=provider-synth-token DOPPLER_TOKEN=provider-synth-token DOPPLER_NAMES_FILE="$od/names.fix" bash "$READER_REL" "$od/direct.txt" >/dev/null 2>&1 ) || rrc=$?
    [[ "$rrc" == 2 ]]; chk N-token-unset "the reader exits 2 when TF_VAR_doppler_token_tf is unset (even if the ambient DOPPLER_TOKEN would work)" $?
    rrc=0; ( cd "$ws" && env PATH="$BIN:$PATH" DOPPLER_LOG="$od/doppler.log" TF_VAR_doppler_token_tf="" STUB_PROVIDER_TOKEN=provider-synth-token DOPPLER_TOKEN=provider-synth-token DOPPLER_NAMES_FILE="$od/names.fix" bash "$READER_REL" "$od/direct.txt" >/dev/null 2>&1 ) || rrc=$?
    [[ "$rrc" == 2 ]]; chk N-token-empty "the reader exits 2 when TF_VAR_doppler_token_tf is empty" $?
    rrc=0; ( cd "$ws" && env PATH="$BIN:$PATH" DOPPLER_LOG="$od/doppler.log" TF_VAR_doppler_token_tf="provider-synth-token" STUB_PROVIDER_TOKEN=provider-synth-token DOPPLER_TOKEN=tier-a-synth-token DOPPLER_NAMES_FILE="$od/names.fix" bash "$READER_REL" "$od/direct.txt" >"$od/direct.out" 2>&1 ) || rrc=$?
    [[ "$rrc" == 0 && -s "$od/direct.txt" && ! -s "$od/direct.out" ]]; chk N-reader-quiet "with the provider token the reader succeeds, writes names to the out-file only, and prints nothing to stdout/stderr" $?
    rrc=0; ( cd "$ws" && env -i PATH="$BIN:$PATH" HOME="$od" bash -x "$READER_REL" "$od/direct2.txt" >/dev/null 2>&1 ) || rrc=$?
    [[ "$rrc" == 78 ]]; chk N-xtrace "the reader refuses to run under xtrace" $?
  fi

  # ---- reread ----
  if [[ -f "$od/reread.sh" ]]; then
    local INH2=(SENTINEL_INHERITED_ALPHA DOPPLER_PROJECT)
    rr() { rm -f "$RT"/escrow-names*; run_step reread "$@"; }
    printf '%s\n' "${INH2[@]}" WORKSPACES_LUKS_KEY WORKSPACES_HEADER_BUCKET WORKSPACES_HEADER_R2_ENDPOINT > "$od/names.fix"
    rr
    [[ "$RC" == 0 ]] && grep -q "9377" <<<"$OUT" && grep -qiE "not terraform" <<<"$OUT" && ! grep -qiE "encrypted|LUKS-backed" <<<"$OUT" && ! grep -q "SENTINEL_INHERITED" <<<"$OUT"
    chk R-ok "the three Terraform names present: green, and the next step (the R2 mint, #9377, not Terraform) is printed with no encryption claim (rc=$RC)" $?
    grep -qE "WORKSPACES_HEADER_R2_ACCESS_KEY_ID.*(absent|missing|not yet)" <<<"$OUT" ; chk R-r2-absent "the two R2 names are reported absent, not failed" $?
    printf '%s\n' "${INH2[@]}" WORKSPACES_LUKS_KEY WORKSPACES_HEADER_BUCKET WORKSPACES_HEADER_R2_ENDPOINT WORKSPACES_HEADER_R2_ACCESS_KEY_ID WORKSPACES_HEADER_R2_SECRET_ACCESS_KEY > "$od/names.fix"
    rr; [[ "$RC" == 0 ]] && grep -qE "WORKSPACES_HEADER_R2_ACCESS_KEY_ID.*present" <<<"$OUT"; chk R-r2-present "the R2 names, when present, are reported present" $?
    local n
    for n in WORKSPACES_LUKS_KEY WORKSPACES_HEADER_BUCKET WORKSPACES_HEADER_R2_ENDPOINT; do
      printf '%s\n' "${INH2[@]}" WORKSPACES_LUKS_KEY WORKSPACES_HEADER_BUCKET WORKSPACES_HEADER_R2_ENDPOINT | grep -vx "$n" > "$od/names.fix"
      rr; [[ "$RC" != 0 ]]; chk "R-missing-$n" "$n missing after the apply fails the re-read" $?
    done
    printf '%s\n' "${INH2[@]}" > "$od/names.fix"; rr DOPPLER_MODE=fail; [[ "$RC" != 0 ]]; chk R-unreadable "an unreadable listing fails the re-read" $?
  fi

  # ---- summary ----
  if [[ -f "$od/summary.sh" ]]; then
    printf '%s\n' "$ADDR_KEY" > "$RT/escrow-creates.txt"; printf '{}' > "$RT/escrow-plan.json"; printf 'x' > "$ws/tfplan"
    local SENV=(O_VALIDATE=success O_PLAN=success O_GATE=success O_NAMES=success O_APPLY=skipped O_REREAD=skipped PLAN_ONLY_RAW=true)
    run_step summary "${SENV[@]}"
    [[ "$RC" == 0 ]] && grep -q "$ADDR_KEY" "$od/gh_summary" && ! leaked; chk S-ok "the summary lists the stage table and the creates, with no value" $?
    [[ ! -e "$RT/escrow-plan.json" && ! -e "$RT/escrow-creates.txt" && ! -e "$ws/tfplan" ]]; chk S-clean "the saved plan, the plan JSON and the creates file are removed" $?
    printf '%s\n' "$ADDR_KEY" > "$RT/escrow-creates.txt"
    run_step summary O_VALIDATE=success O_PLAN=success O_GATE= O_NAMES=success O_APPLY=skipped O_REREAD=skipped PLAN_ONLY_RAW=true; [[ "$RC" != 0 ]]; chk S-failclosed "an empty step outcome fails closed" $?
    printf '%s\n' "$ADDR_KEY" > "$RT/escrow-creates.txt"
    run_step summary O_VALIDATE=success O_PLAN=success O_GATE=failure O_NAMES=skipped O_APPLY=skipped O_REREAD=skipped PLAN_ONLY_RAW=true
    grep -q "failure" "$od/gh_summary"; chk S-failure "a failed gate is recorded in the stage table" $?
  fi
}

# --- the pristine control, graded row by row ----------------------------------------------------------
mkws() { # mkws <dir> <reader-file>
  rm -rf "$1"; mkdir -p "$1/scripts" "$1/tests/scripts/lib"
  cp "$2" "$1/$READER_REL"; cp "$FILTER" "$1/$FILTER_REL"
}
mkws "$SCRATCH/ws0" "$READER"
suite "$WF" "$SCRATCH/ws0" "$SCRATCH/control.tsv"
nrows=0
while IFS=$'\t' read -r id v text; do
  [[ -n "${id:-}" ]] || continue
  nrows=$((nrows + 1))
  if [[ "$v" == ok ]]; then ok "$id $text"; else no "$id $text"; fi
done < "$SCRATCH/control.tsv"
[[ "$nrows" -gt 0 ]] || no "INSTRUMENT: the suite produced no rows"

# --- the mutation battery ---------------------------------------------------------------------------
# One edit per row to a COPY of the workflow (or the reader); the named rows must go RED while the pristine control
# above stays green. Each edit is asserted to have landed (the source changed, with the exact changed-line count).
# Skipped when ESCROW_SUITE_NO_MUTANTS=1 (the instrument meta-mutant below runs a COPY of this file).
cat > "$SCRATCH/mutants.py" <<'PY'
import sys, os, re, difflib
wf_path, rd_path, outdir = sys.argv[1:4]
WF = open(wf_path).read()
RD = open(rd_path).read()
index = []
def emit(n, label, target, ids, lines, edit):
    s = WF if target == "wf" else RD
    o = s
    s = edit(s)
    assert s != o, f"{label}: the edit did not land"
    changed = sum(1 for l in difflib.ndiff(o.splitlines(), s.splitlines()) if l[:2] in ("+ ", "- "))
    ok = "yes" if (lines < 0 or changed == lines) else f"NO(changed={changed},want={lines})"
    d = f"{outdir}/{n}"
    os.makedirs(d, exist_ok=True)
    open(f"{d}/{'wf.yml' if target == 'wf' else 'reader.sh'}", "w").write(s)
    index.append(f"{n}\t{label}\t{target}\t{ids}\t{ok}")
def rep(old, new, cnt=1):
    def f(s):
        assert s.count(old) == cnt, (old, s.count(old))
        return s.replace(old, new)
    return f
def chain(*fs):
    def f(s):
        for g in fs:
            s = g(s)
        return s
    return f
def reorder(s):
    parts = s.split("\n      - name: ")
    ia = next(i for i, p in enumerate(parts) if p.startswith("Apply the saved plan"))
    ig = next(i for i, p in enumerate(parts) if p.startswith("Plan gate"))
    parts.insert(ig, parts.pop(ia))
    return "\n      - name: ".join(parts)
def drop_prelude_in_gate(s):
    i = s.index("id: gate")
    j = s.index('          case $- in *x*)', i)
    k = s.index("\n", j)
    return s[:j] + s[k + 1:]
def drop_lines(*needles):
    def f(s):
        out = []
        for l in s.split("\n"):
            if any(n in l for n in needles):
                continue
            out.append(l)
        return "\n".join(out)
    return f
def code_only(pat, new):
    def f(s):
        return "\n".join(l if l.lstrip().startswith("#") else re.sub(pat, new, l) for l in s.split("\n"))
    return f
M = []
a = M.append
# ---- Guard 1: the inverted create-only plan gate ----
a(("allow-sixth", "wf", "T11,B-gate-config", 2, rep('r2_endpoint"]\'', 'r2_endpoint","doppler_config.workspaces_luks_web"]\'')))
a(("verb-contains", "wf", "B-gate-bucket-createupdate,B-gate-bucket-updatecreate", 2, rep('\\$a == [\\"create\\"] and', '((\\$a // []) | index(\\"create\\")) != null and')))
a(("address-any", "wf", "B-gate-other-create,B-gate-indexed,B-gate-module,B-gate-token,B-gate-config", 2, rep('(\\$ad | IN(\\$allow[]))', 'true')))
a(("violation-continues", "wf", "B-gate-other-create,B-gate-config,B-gate-bucket-update", 2, rep("            exit 1\n          fi\n          jq -r", "            :\n          fi\n          jq -r")))
a(("first-entry-only", "wf", "B-gate-second3,B-gate-other-create", 2, rep('viol="$(jq -r --argjson allow "$ALLOW_JSON" "[.resource_changes[]?', 'viol="$(jq -r --argjson allow "$ALLOW_JSON" "[.resource_changes[0:1][]?')))
a(("no-plan-ok", "wf", "B-gate-noarray,B-gate-nullarray,B-gate-planok", 2, drop_lines("'.plan_ok' <<<\"$counts\")\" == true", "has no resource_changes array (plan_ok is not true)")))
a(("counter-dropped", "wf", "T13,B-gate-ctr-luks_passphrase_rotations,B-gate-ctrmiss-luks_passphrase_rotations", 2, rep(" luks_passphrase_rotations undecidable_entries", " undecidable_entries")))
a(("apply-above-gate", "wf", "T14", -1, reorder))
a(("apply-unguarded", "wf", "T16", 1, rep("        id: apply\n        if: inputs.plan_only != true\n", "        id: apply\n")))
a(("replace-flag", "wf", "T10", 1, rep("-out=tfplan \\\n", "-out=tfplan \\\n              -replace=random_password.workspaces_luks_web \\\n")))
a(("host-target", "wf", "T10,T18", 3, rep("-target=doppler_secret.workspaces_luks_web_header_r2_endpoint\n", "-target=doppler_secret.workspaces_luks_web_header_r2_endpoint \\\n              -target=hcloud_server.web\n")))
a(("allow-vs-targets", "wf", "T11,G-happy", 2, rep('"doppler_secret.workspaces_luks_web_header_bucket",', '')))
a(("gate-prelude-gone", "wf", "T20a", 1, drop_prelude_in_gate))
a(("preserve-env-gone", "wf", "T20c", 2, rep("doppler run --preserve-env -p soleur -c prd_terraform --name-transformer tf-var -- \\\n            terraform plan", "doppler run -p soleur -c prd_terraform --name-transformer tf-var -- \\\n            terraform plan")))
# ---- shared serializer, triggers, defaults, typo-guard ----
a(("group-renamed", "wf", "T4", 2, rep("group: terraform-apply-web-platform-host", "group: terraform-apply-escrow")))
a(("cancel-true", "wf", "T4", 2, rep("cancel-in-progress: false", "cancel-in-progress: true")))
a(("push-trigger", "wf", "T1", 2, rep("on:\n  workflow_dispatch:", "on:\n  push:\n    branches: [main]\n  workflow_dispatch:")))
a(("plan-only-default-false", "wf", "T3", 2, rep("        default: true", "        default: false")))
a(("confirm-unchecked", "wf", "V2,V2b", 2, rep('[[ "$CONFIRM_RAW" == "CREATE-WEB-ESCROW" ]] ||', 'true ||')))
a(("reason-unchecked", "wf", "V3,V3b", 2, rep('[[ -n "${reason// /}" ]] ||', 'true ||')))
a(("reason-unsanitized", "wf", "V4", 2, rep("reason=\"$(printf '%s' \"$REASON_RAW\" | LC_ALL=C tr -c '\\040-\\176' ' ')\"", 'reason="$REASON_RAW"')))
# ---- Guard 2: the names-only live precondition ----
a(("name-present-not-fatal", "wf", "B-names-present,B-names-second", 2, rep('[[ "$hit" -eq 0 ]] || exit 1', 'true')))
a(("unreadable-is-absent", "wf", "B-names-unreadable,B-names-empty,B-names-hdronly,B-names-nohdr", 2, rep('|| fail "the live names listing of prd_workspaces_luks_web is unreadable: an unreadable listing is never read as absent. Nothing was applied"', '|| true')))
a(("map-key-only", "wf", "B-names-second,B-names-map-WORKSPACES_HEADER_BUCKET,B-names-map-WORKSPACES_HEADER_R2_ENDPOINT", 2, drop_lines("header_bucket) printf", "header_r2_endpoint) printf")))
a(("map-swapped", "wf", "B-names-map-WORKSPACES_HEADER_BUCKET,B-names-map-WORKSPACES_HEADER_R2_ENDPOINT", 4, chain(rep("printf 'WORKSPACES_HEADER_BUCKET'", "printf 'SWAP_TMP'"), rep("printf 'WORKSPACES_HEADER_R2_ENDPOINT'", "printf 'WORKSPACES_HEADER_BUCKET'"), rep("printf 'SWAP_TMP'", "printf 'WORKSPACES_HEADER_R2_ENDPOINT'"))))
a(("listing-to-log", "wf", "N-log", 1, rep("          name_of() {", '          cat "$NAMES_FILE"\n          name_of() {')))
a(("reread-no-missing-check", "wf", "R-missing-WORKSPACES_LUKS_KEY,R-missing-WORKSPACES_HEADER_BUCKET,R-missing-WORKSPACES_HEADER_R2_ENDPOINT", 2, rep('[[ "$missing" -eq 0 ]] || fail "a Terraform-managed name is absent after the apply; do not proceed to the preflight"', 'true')))
a(("summary-open", "wf", "S-failclosed", 2, rep('[[ -z "$missing" ]] || { echo "::error::no outcome was recorded for:${missing}; failing closed"; exit 1; }', 'true')))
a(("summary-keeps-plan", "wf", "S-clean", 1, drop_lines('rm -f tfplan "$RUNNER_TEMP/escrow-plan.json"')))
# ---- the reader ----
a(("reader-value-verb", "reader", "T19", 1, rep("CFG=prd_workspaces_luks_web\n", "CFG=prd_workspaces_luks_web\ndoppler secrets get WORKSPACES_LUKS_KEY --plain >/dev/null 2>&1 || true\n")))
a(("reader-ambient-token", "reader", "N-absent,N-reader-quiet", 2, rep('DOPPLER_TOKEN="$TF_VAR_doppler_token_tf" doppler secrets', 'doppler secrets')))
a(("reader-unreadable-ok", "reader", "B-names-unreadable,B-names-empty,B-names-hdronly,B-names-nohdr", 6, code_only(r"exit 3\b", "exit 0")))
a(("reader-no-xtrace-guard", "reader", "N-xtrace", 2, rep('echo "[FATAL] refusing to run under xtrace (a provider token is in scope)" >&2; exit 78', 'true')))
a(("reader-token-optional", "reader", "N-token-unset,N-token-empty", 2, rep('if [[ -z "${TF_VAR_doppler_token_tf:-}" ]]; then', 'if false; then')))
a(("reader-stdout", "reader", "N-reader-quiet,N-log", 2, rep("printf '%s\\n' \"$names\" > \"$OUT_FILE\"", "printf '%s\\n' \"$names\" | tee \"$OUT_FILE\"")))
for i, (label, target, ids, lines, edit) in enumerate(M, 1):
    emit(i, label, target, ids, lines, edit)
open(f"{outdir}/index.tsv", "w").write("\n".join(index) + "\n")
PY
if [[ "${ESCROW_SUITE_NO_MUTANTS:-0}" != 1 ]]; then
  MUTD="$SCRATCH/mut"; mkdir -p "$MUTD"
  if python3 "$SCRATCH/mutants.py" "$WF" "$READER" "$MUTD" 2> "$MUTD/py.err"; then
    mut_one() {  # mut_one <n> <label> <target> <ids> -> $MUTD/<n>/verdict
      local n="$1" d="$MUTD/$1" wf="$WF" rd="$READER" id miss=""
      [[ "$3" == wf ]] && wf="$d/wf.yml" || rd="$d/reader.sh"
      mkws "$d/ws" "$rd"
      suite "$wf" "$d/ws" "$d/rows.tsv" >/dev/null 2>&1
      for id in ${4//,/ }; do
        awk -F'\t' -v id="$id" '$1 == id && $2 == "FAIL" { f = 1 } END { exit !f }' "$d/rows.tsv" || miss="$miss $id"
      done
      [[ -z "$miss" ]] && printf 'killed\n' > "$d/verdict" || printf 'SURVIVED (rows not RED:%s)\n' "$miss" > "$d/verdict"
    }
    MUT_PAR=6
    while IFS=$'\t' read -r n label target ids landed; do
      [[ -n "${n:-}" ]] || continue
      while [[ "$(jobs -rp | wc -l)" -ge "$MUT_PAR" ]]; do sleep 0.3; done
      mut_one "$n" "$label" "$target" "$ids" &
    done < "$MUTD/index.tsv"
    wait
    nmut=0
    while IFS=$'\t' read -r n label target ids landed; do
      [[ -n "${n:-}" ]] || continue
      nmut=$((nmut + 1))
      v="$(cat "$MUTD/$n/verdict" 2>/dev/null || echo 'NO VERDICT')"
      if [[ "$landed" == yes && "$v" == killed ]]; then ok "MUT $label: edit landed with the exact changed-line count, and ${ids//,/ + } went RED"
      else no "MUT $label: landed=$landed verdict=$v"; fi
    done < "$MUTD/index.tsv"
    [[ "$nmut" -ge 30 ]] || no "INSTRUMENT: the mutation battery ran only $nmut mutants (want at least 30)"
  else
    no "INSTRUMENT: mutation generation failed: $(head -c 300 "$MUTD/py.err")"
  fi
  # The instrument meta-mutant: a copy of THIS suite whose no() is neutered must refuse to run (exit 2).
  sed 's/^no() { fail=\$((fail + 1));/no() { :;/' "${BASH_SOURCE[0]}" > "$SCRATCH/neutered.sh"
  grep -q '^no() { :;' "$SCRATCH/neutered.sh" || no "INSTRUMENT: the no() neutering edit did not land"
  _mrc=0; ESCROW_SUITE_REPO="$REPO" ESCROW_SUITE_NO_MUTANTS=1 bash "$SCRATCH/neutered.sh" >/dev/null 2>&1 || _mrc=$?
  [[ "$_mrc" == 2 ]] && ok "MUT neutered-no(): the instrument self-test refuses to run (exit 2)" || no "MUT neutered-no(): exit $_mrc, want 2"
fi

printf '\n%s passed, %s failed\n' "$pass" "$fail"
# PASS FLOOR at the measured count.
WEB_ESCROW_MIN_PASS=169
if [[ "$pass" -lt "$WEB_ESCROW_MIN_PASS" ]]; then
  printf 'FAIL - only %s assertions passed (floor %s) — a row was dropped or stopped dispatching\n' "$pass" "$WEB_ESCROW_MIN_PASS"
  exit 1
fi
[[ "$fail" -eq 0 ]]
