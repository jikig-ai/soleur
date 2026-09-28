#!/usr/bin/env bash
#
# Structural + behavioral gate for .github/workflows/workspaces-luks-cutover.yml (#6588).
#
# WHY A DEDICATED SUITE: this workflow can delete user data and can perform an irreversible freeze
# on sole-copy data. Two properties are load-bearing and neither is expressible in the shell suites
# that cover workspaces-cutover.sh:
#
#   (1) The `environment:` gate expression. `dry_run` used to double as a proxy for "which mode",
#       and because `dry_run` DEFAULTS TO TRUE while the script's ROLLBACK block force-sets
#       DRY_RUN=0, `rollback=true` resolved to the UNGATED branch and performed a real
#       umount/close/restart behind nothing but a typo-guard token. The risk here is OPERAND
#       INVERSION, so the assertion is exact-string equality on the parsed value — that catches an
#       inversion without needing a GHA-semantics simulator.
#
#   (2) The pre-gate mode validation, asserted by EXECUTING the workflow's own extracted `run:`
#       body against input combinations — the real script, not a model of it.
#
# EVERY structural assertion parses the file as YAML. A grep would pass VACUOUSLY: the header
# comments discuss both the gate expression and the mode combinations at length, so a bare grep for
# the expression matches the prose that describes it (cq-assert-anchor-not-bare-token).
#
# `bash -n` is likewise run only on EXTRACTED `run:` bodies — `bash -n` on the .yml itself parses
# YAML as bash and proves nothing.
set -euo pipefail

WF=".github/workflows/workspaces-luks-cutover.yml"
[[ -f "$WF" ]] || { echo "FAIL - $WF not found (run from the repo root)"; exit 1; }

pass=0
fail=0
ok() { pass=$((pass + 1)); printf 'ok   - %s\n' "$1"; }
no() { fail=$((fail + 1)); printf 'FAIL - %s\n' "$1"; }

python3 -c 'import yaml' 2>/dev/null || pip3 install --quiet pyyaml

SCRATCH="$(mktemp -d -t wl-wf.XXXXXXXX)"
trap 'rm -rf "$SCRATCH"' EXIT INT TERM HUP

# --- structural assertions, parsed as YAML -----------------------------------------------------
# The python leg writes one TSV verdict per line; bash reports them. Splitting it this way keeps
# the reporting convention identical to the sibling suites while still parsing real YAML.
python3 - "$WF" "$SCRATCH" > "$SCRATCH/verdicts.tsv" <<'PY'
import sys, yaml, json

import re
wf = yaml.safe_load(open(sys.argv[1]))
wf_text = open(sys.argv[1]).read()
scratch = sys.argv[2]
verdicts = []

def check(name, cond, detail=""):
    # Strip tab/newline: the bash reader below splits on tabs, so an embedded one in a YAML value
    # would desync the loop and manufacture a phantom verdict.
    d = str(detail)[:160].replace("\t", " ").replace("\n", " ").replace("\r", " ")
    verdicts.append(("ok" if cond else "FAIL", name.replace("\t", " "), d))

jobs = wf.get("jobs") or {}
check("jobs are exactly preflight + cutover + wipe", set(jobs) == {"preflight", "cutover", "wipe"}, sorted(jobs))

# (1) the gate expression, EXACT — operand inversion is the real risk.
EXPECT = "${{ (!inputs.dry_run || inputs.clean_stray || inputs.rollback) && 'workspaces-luks-cutover' || '' }}"
got = (jobs.get("cutover") or {}).get("environment")
check("cutover environment expression is exactly the fail-closed form", got == EXPECT, repr(got))
for tok in ("!inputs.dry_run", "inputs.clean_stray", "inputs.rollback"):
    check(f"gate expression carries operand {tok}", tok in (got or ""))

# preflight is the ungated pre-gate job: an `environment:` key here would defeat its whole purpose,
# because a gate blocks a job BEFORE its first step runs.
check("preflight declares NO environment (must run before a reviewer is paged)",
      "environment" not in (jobs.get("preflight") or {}))
check("cutover needs preflight", (jobs.get("cutover") or {}).get("needs") == "preflight")

pf_text = json.dumps(jobs.get("preflight") or {})
check("preflight never references WORKSPACES_LUKS_BOOT_TOKEN (strictly less credential)",
      "WORKSPACES_LUKS_BOOT_TOKEN" not in pf_text)
check("preflight issues no rm (it is a read-only probe)", "rm -rf" not in pf_text)

steps = (jobs.get("cutover") or {}).get("steps") or []
lb = [s for s in steps if "Loopback" in str(s.get("name", ""))]
check("loopback validation gate step exists", len(lb) == 1)
if lb:
    cond = str(lb[0].get("if", ""))
    for tok in ("!inputs.dry_run", "!inputs.rollback", "!inputs.clean_stray"):
        check(f"loopback gate is scoped off {tok}", tok in cond, cond)

# `on` parses to the boolean True under YAML 1.1, hence the two-key lookup.
inp = ((wf.get(True) or wf.get("on") or {}).get("workflow_dispatch") or {}).get("inputs") or {}
cs = inp.get("clean_stray") or {}
check("clean_stray input exists", bool(cs))
check("clean_stray defaults to false (never the arm a dispatch falls into by omission)",
      cs.get("default") is False, repr(cs.get("default")))
desc = str(cs.get("description", ""))
check("clean_stray description names the AP-009 deviation at dispatch time", "AP-009" in desc)
check("clean_stray description states it deletes user data", "USER DATA" in desc.upper())

# CLEAN_STRAY must actually reach the host, or the mode is unreachable in production.
run_step = [s for s in steps if "Run workspaces-luks cutover" in str(s.get("name", ""))]
check("the Run step exists", len(run_step) == 1)
if run_step:
    body = str(run_step[0].get("run", ""))
    env = run_step[0].get("env") or {}
    check("CLEAN_STRAY is plumbed into the Run step env", "CLEAN_STRAY" in env)
    check("CLEAN_STRAY is written into the host .env printf", "CLEAN_STRAY=%s" in body)

# Extract every run: body so bash can syntax-check them, and the pre-gate step so bash can EXECUTE
# it against real input combinations.
n = 0
pregate_job = None
pregate_step = None
for jn, j in jobs.items():
    for s in (j.get("steps") or []):
        r = s.get("run")
        if not r:
            continue
        n += 1
        open(f"{scratch}/run-{n}.sh", "w").write(r)
        if "Validate dispatch" in str(s.get("name", "")):
            open(f"{scratch}/pregate.sh", "w").write(r)
            pregate_job, pregate_step = jn, s
check("extracted at least one run: body for syntax checking", n > 0, n)

# THE STEP WRAPPER, not just its body. The behavioral leg below executes the extracted `run:`
# script, which observes the shell and NOTHING around it — so moving the step into the gated
# `cutover` job, disabling it with `if: false`, or marking it continue-on-error all leave every
# behavioral assertion passing while the guard is inert or runs after a reviewer was paged.
check("the pre-gate step exists", pregate_step is not None)
if pregate_step is not None:
    check("the pre-gate runs in the UNGATED preflight job (a gated job would page the reviewer first)",
          pregate_job == "preflight", pregate_job)
    check("the pre-gate step is unconditional (no if:)", "if" not in pregate_step,
          pregate_step.get("if"))
    check("the pre-gate step is not continue-on-error (that would make every refusal advisory)",
          not pregate_step.get("continue-on-error"))

# `needs: preflight` alone does not prove a preflight FAILURE blocks the cutover: an
# `if: always()` on the job would run it anyway, after a refused dispatch. #6604 step 7 allows EXACTLY
# one job-level predicate — skip the job on a REAL wipe (that runs in the gated `wipe` job) — and it
# carries no status function, so GitHub's implicit success() still gates it on preflight.
CUT_IF = "${{ !(inputs.wipe_plaintext && !inputs.dry_run) }}"
check("cutover's only job-level if: is the real-wipe skip, exactly (a preflight failure still blocks it)",
      (jobs.get("cutover") or {}).get("if") == CUT_IF, (jobs.get("cutover") or {}).get("if"))
check("cutover's if: carries no status function (always()/failure()/cancelled() would bypass the preflight)",
      not re.search(r"always\(|failure\(|cancelled\(|success\(", str((jobs.get("cutover") or {}).get("if", ""))))

# Key-presence on the env is not enough: a hardcoded CLEAN_STRAY: '1' satisfies "in env" while
# sending the deletion flag to the host on EVERY dispatch.
if run_step:
    cs_env = str((run_step[0].get("env") or {}).get("CLEAN_STRAY", ""))
    check("CLEAN_STRAY env derives from inputs.clean_stray, not a hardcoded value",
          "inputs.clean_stray" in cs_env, cs_env)

# PATH PARITY. The workflow hardcodes /mnt/data-luks and /mnt/data (in the clean_stray input
# description and in the probe's env); the script derives them from ${WORKSPACES_STAGING:-...} /
# ${WORKSPACES_MOUNT:-...}. The workflow does NOT pass those vars in the .env, so the two agree
# only by coincidence. Change a script default and the approval banner would describe — and the
# probe would measure — a path different from the one the script deletes, with nothing failing.
import re
script = open("apps/web-platform/infra/workspaces-cutover.sh").read()
def _default(var):
    # e.g. STAGING="${WORKSPACES_STAGING:-/mnt/data-luks}" — the env var name differs from the
    # local, so match any override name rather than assuming they are the same.
    m = re.search(r'^%s="\$\{[A-Za-z_][A-Za-z0-9_]*:-([^}]+)\}"' % re.escape(var), script, re.M)
    return m.group(1) if m else None
script_staging = _default("STAGING")
script_mount = _default("MOUNT")
check("could read the script's STAGING/MOUNT defaults", bool(script_staging and script_mount),
      f"{script_staging} {script_mount}")
probe = [s for s in (jobs.get("preflight") or {}).get("steps") or []
         if "AP-009 deletion probe" in str(s.get("name", ""))]
check("the AP-009 probe step exists", len(probe) == 1)
if probe and script_staging and script_mount:
    penv = probe[0].get("env") or {}
    check("probe STAGING_PATH matches the script's $STAGING default",
          str(penv.get("STAGING_PATH")) == script_staging,
          f"workflow={penv.get('STAGING_PATH')} script={script_staging}")
    check("probe MOUNT_PATH matches the script's $MOUNT default",
          str(penv.get("MOUNT_PATH")) == script_mount,
          f"workflow={penv.get('MOUNT_PATH')} script={script_mount}")
    # Safe-by-literal, not by construction: the probe interpolates these into a single-quoted
    # remote shell string. They are constants today; a quote or metacharacter would escape it.
    for k in ("STAGING_PATH", "MOUNT_PATH"):
        v = str(penv.get(k, ""))
        check(f"probe {k} is a metacharacter-free literal (it is interpolated into a remote shell string)",
              bool(re.fullmatch(r"[A-Za-z0-9/_.-]+", v)), v)

# ── #6604 step 7 — the wipe wiring (Guards 2 and 6, structural) ─────────────────────────────────
wi = inp.get("wipe_plaintext") or {}
check("wipe_plaintext input is a boolean defaulting to false", wi.get("type") == "boolean" and wi.get("default") is False, repr(wi.get("default")))
wdesc = str(wi.get("description", ""))
for tok in ("AP-009", "dry_run", "approval"):
    check(f"wipe_plaintext description names {tok}", tok in wdesc)
pin_in = inp.get("expected_plaintext_volume_id") or {}
check("expected_plaintext_volume_id input exists as a string", pin_in.get("type") == "string", repr(pin_in.get("type")))
check("dry_run description no longer promises 'no wipe' without qualification", "no wipe zero" in str((inp.get("dry_run") or {}).get("description", "")))
# EVERY input reaches a run: body through env: only — never an inline ${{ inputs.* }} expansion.
inline = []
for jn, j in jobs.items():
    for st in (j.get("steps") or []):
        if "${{ inputs." in str(st.get("run", "")) or "${{inputs." in str(st.get("run", "")):
            inline.append(f"{jn}:{st.get('name')}")
check("no run: body interpolates ${{ inputs.* }} (untrusted input reaches shell only via env:)", not inline, inline)
# The first environment: line in the FILE is still cutover's (workspaces-luks-header.test.sh H17 reads it).
first_env = next((l.strip() for l in wf_text.splitlines() if re.match(r"^\s*environment:", l)), "")
check("the first environment: line in the file is still the cutover gate expression", first_env == "environment: " + EXPECT, first_env)
# cutover can only ever deliver a REHEARSAL of the wipe.
if run_step:
    cenv = run_step[0].get("env") or {}
    check("cutover delivers CONFIRM_WIPE = (wipe_plaintext && dry_run) exactly (never a destructive wipe)",
          cenv.get("CONFIRM_WIPE") == "${{ (inputs.wipe_plaintext && inputs.dry_run) && '1' || '0' }}", cenv.get("CONFIRM_WIPE"))
    cbody = str(run_step[0].get("run", ""))
    check("cutover's .env carries CONFIRM_WIPE then DRY_RUN as its LAST two lines",
          re.search(r"printf 'CONFIRM_WIPE=%s\\n' \"\$CONFIRM_WIPE\";\s*printf 'DRY_RUN=%s\\n' \"\$DRY_RUN\"\s*\)", cbody) is not None)
    check("cutover's .env is built one named printf per line (no multi-%s format)", not re.search(r"printf '[^']*%s[^']*%s", cbody))
    check("cutover's ::error:: guidance lists outcome wipe_aborted", "wipe_aborted" in cbody)
wj = jobs.get("wipe") or {}
check("wipe needs preflight", wj.get("needs") == "preflight", wj.get("needs"))
check("wipe runs ONLY on a real wipe dispatch (if: wipe_plaintext && !dry_run, exactly)",
      wj.get("if") == "${{ inputs.wipe_plaintext && !inputs.dry_run }}", wj.get("if"))
check("wipe's environment is UNCONDITIONAL workspaces-luks-cutover (census Guard 1; the one approval)",
      wj.get("environment") == "workspaces-luks-cutover", repr(wj.get("environment")))
check("wipe timeout-minutes is the fixed 240 ceiling", wj.get("timeout-minutes") == 240, wj.get("timeout-minutes"))
check("wipe permissions are exactly contents:read + actions:read",
      wj.get("permissions") == {"contents": "read", "actions": "read"}, wj.get("permissions"))
wsteps = wj.get("steps") or []
def sidx(pred):
    for i, st in enumerate(wsteps):
        if pred(st):
            return i
    return -1
i_loader = sidx(lambda st: st.get("uses") == "./.github/actions/infra-credentials")
i_pre = sidx(lambda st: st.get("id") == "pre")
i_bridge = sidx(lambda st: st.get("uses") == "./.github/actions/cf-tunnel-ssh-bridge")
i_host = sidx(lambda st: st.get("id") == "host")
i_api = sidx(lambda st: st.get("id") == "api")
check("wipe step order: loader < preconditions(pre) < bridge < host < api (Guard 6 #4: the write probe precedes web-1)",
      -1 not in (i_loader, i_pre, i_bridge, i_host, i_api) and i_loader < i_pre < i_bridge < i_host < i_api,
      (i_loader, i_pre, i_bridge, i_host, i_api))
pre_body = str(wsteps[i_pre].get("run", "")) if i_pre >= 0 else ""
for tok, why in (("PUT", "the write-capability probe"), ("disabled_manually", "the pause check"),
                 ("workspaces-luks-verify.yml", "the same-day verify run"), ("SOLEUR_WORKSPACES_READYZ ready=true", "the verify run's ready=true")):
    check(f"wipe preconditions step carries {why}", tok in pre_body)
if i_host >= 0:
    hs = wsteps[i_host]
    hbody = str(hs.get("run", ""))
    check("the host step runs on EVERY wipe (no if: — a hand-detached, never-wiped volume must be refused, never deleted)", "if" not in hs, hs.get("if"))
    check("the host step unsets HCLOUD_TOKEN first", re.match(r"\s*(set [^\n]*\n\s*)*unset HCLOUD_TOKEN", hbody) is not None)
    check("the host ssh keeps the tunnel alive through a silent zero (ServerAliveInterval)", "ServerAliveInterval=30" in hbody and "ServerAliveCountMax=10" in hbody)
    check("the host output is wrapped in ::stop-commands:: with a random token", "::stop-commands::" in hbody and "openssl rand -hex" in hbody)
    check("the host step delivers CONFIRM_WIPE=1 and DRY_RUN=0 (the only destructive delivery in the file)",
          "printf 'CONFIRM_WIPE=%s\\n' 1" in hbody and "printf 'DRY_RUN=%s\\n' 0" in hbody)
    check("the host step captures the ssh rc from PIPESTATUS, not from tee", "PIPESTATUS[0]" in hbody)
if i_bridge >= 0:
    check("the wipe bridge step blanks HCLOUD_TOKEN in its env", (wsteps[i_bridge].get("env") or {}).get("HCLOUD_TOKEN", None) == "")
# The wipe's API bodies (preflight classification, wipe preconditions, wipe detach/delete). The
# pre-existing LUKS-volume lookup in the cutover Run step is out of this scope and unchanged.
wipe_api_runs = " ".join(str(st.get("run", "")) for jn, j in jobs.items() for st in (j.get("steps") or [])
                         if (jn, st.get("id")) in (("preflight", "api"), ("wipe", "pre"), ("wipe", "api")))
check("the wipe API bodies were found (non-vacuity for the two rows below)", "api.hetzner.cloud" in wipe_api_runs)
check("no wipe API call uses curl -f/--fail (a 404 must be READ with -w, never turned into exit 22)",
      "curl" in wipe_api_runs and not re.search(r"curl[^\n]*\s(-f|--fail|-[a-zA-Z]*f[a-zA-Z]*)(\s|$)", wipe_api_runs))
check("no wipe API call puts the token on curl argv — it rides --config - on stdin",
      "--config -" in wipe_api_runs and "Authorization" not in re.sub(r"printf 'header = \"Authorization: Bearer %s\"[^']*'", "", wipe_api_runs))
# Extract the step bodies the behavioral legs below execute.
for (jn, sid, fn) in (("preflight", "api", "pf-api.sh"), ("wipe", "pre", "wipe-pre.sh"), ("wipe", "host", "wipe-host.sh"), ("wipe", "api", "wipe-api.sh")):
    hits = [st for st in (jobs.get(jn) or {}).get("steps") or [] if st.get("id") == sid]
    check(f"exactly one {jn} step with id {sid}", len(hits) == 1, len(hits))
    if len(hits) == 1:
        open(f"{scratch}/{fn}", "w").write(str(hits[0].get("run", "")))
if run_step:
    open(f"{scratch}/cutover-run.sh", "w").write(str(run_step[0].get("run", "")))

for v in verdicts:
    print("\t".join(v))
PY

while IFS=$'\t' read -r verdict name detail; do
  [[ -n "${verdict:-}" ]] || continue
  if [[ "$verdict" == "ok" ]]; then ok "$name"; else no "$name${detail:+ ($detail)}"; fi
done < "$SCRATCH/verdicts.tsv"

# --- bash -n on EXTRACTED run: bodies ----------------------------------------------------------
syntax_bad=0
for f in "$SCRATCH"/run-*.sh; do
  [[ -e "$f" ]] || continue
  bash -n "$f" 2>/dev/null || syntax_bad=$((syntax_bad + 1))
done
if [[ "$syntax_bad" -eq 0 ]]; then
  ok "every extracted run: body passes bash -n"
else
  no "$syntax_bad extracted run: body/bodies failed bash -n"
fi

# --- behavioral: the REAL pre-gate step against every input combination ------------------------
# This is the requirement-2 assertion that matters: a clean_stray dispatch must be UNABLE to ride
# the ungated dry_run=true arm. dry_run DEFAULTS TO TRUE, so the natural dispatch (tick clean_stray,
# change nothing else) is exactly the combination that must be refused.
if [[ ! -f "$SCRATCH/pregate.sh" ]]; then
  no "could not extract the pre-gate validation step — requirement-2 enforcement is unverified"
else
  gate_rc() {
    local rc=0
    CONFIRM="$1" DRY="$2" ROLLBACK_IN="$3" CLEAN_STRAY_IN="$4" \
      bash "$SCRATCH/pregate.sh" >/dev/null 2>&1 || rc=$?
    printf '%s' "$rc"
  }
  DEL="DELETE-STRAY-USER-DATA-AP-009"
  CUT="CUTOVER-WORKSPACES-LUKS"

  [[ "$(gate_rc "$DEL" true false true)" != "0" ]] \
    && ok "clean_stray + dry_run=true is REFUSED (requirement 2: not reachable from the ungated arm)" \
    || no "clean_stray rode the dry_run=true arm — requirement 2 is VIOLATED"

  [[ "$(gate_rc "$DEL" false true true)" != "0" ]] \
    && ok "clean_stray + rollback is REFUSED (rollback would silently win via its exit 0)" \
    || no "clean_stray + rollback was accepted — the rollback would run instead and report green"

  [[ "$(gate_rc "$CUT" false false true)" != "0" ]] \
    && ok "the cutover token cannot authorize a deletion (distinct token per destructive verb)" \
    || no "a muscle-memory cutover token reached the user-data deletion"

  [[ "$(gate_rc "$DEL" false false false)" != "0" ]] \
    && ok "the deletion token is rejected on a non-clean_stray dispatch (tokens are not interchangeable)" \
    || no "the deletion token authorized a non-deletion dispatch"

  [[ "$(gate_rc "$DEL" false false true)" == "0" ]] \
    && ok "POSITIVE CONTROL: the intended deletion dispatch is ACCEPTED (the gate is not refuse-everything)" \
    || no "the intended clean_stray dispatch was refused — the mode is unreachable and the cutover stays wedged"

  [[ "$(gate_rc "$CUT" true false false)" == "0" ]] \
    && ok "POSITIVE CONTROL: a normal rehearsal still passes" \
    || no "the pre-gate step broke the ordinary rehearsal dispatch"

  [[ "$(gate_rc "$CUT" false false false)" == "0" ]] \
    && ok "POSITIVE CONTROL: a normal real freeze still passes" \
    || no "the pre-gate step broke the ordinary freeze dispatch"

  [[ "$(gate_rc "$CUT" false true false)" == "0" ]] \
    && ok "POSITIVE CONTROL: an ordinary rollback still passes" \
    || no "the pre-gate step broke the rollback recovery dispatch"
fi


# --- #6604 step 7 — the pre-gate learns the wipe (exclusion FIRST, pin shape, its own token) --------
if [[ -f "$SCRATCH/pregate.sh" ]]; then
  gate_out() {  # <confirm> <dry> <rollback> <clean_stray> <wipe> <pin> [ack]
    local rc=0 out
    out="$(CONFIRM="$1" DRY="$2" ROLLBACK_IN="$3" CLEAN_STRAY_IN="$4" WIPE_IN="$5" PIN_IN="$6" ACK_IN="${7:-false}" \
      bash --noprofile --norc -eo pipefail "$SCRATCH/pregate.sh" 2>&1)" || rc=$?
    printf '%s|%s' "$rc" "$out"
  }
  WTOK="WIPE-PLAINTEXT-USER-DATA-AP-009"
  r="$(gate_out "$WTOK" true false true true 105149570)"
  [[ "${r%%|*}" != 0 && "$r" == *"mutually exclusive"* && "$r" != *"requires dry_run=false"* ]] \
    && ok "wipe + clean_stray + dry_run=true is refused on the EXCLUSION first (never an 'untick dry_run' hint)" \
    || no "wipe+clean_stray+dry_run not refused on exclusion first: ${r:0:200}"
  [[ "$(gate_out "$WTOK" false true false true 105149570)" != 0\|* ]] \
    && ok "wipe + rollback is refused" || no "wipe + rollback accepted"
  [[ "$(gate_out "$WTOK" true false false true 105149570 true)" != 0\|* ]] \
    && ok "wipe + rollback_ack_luks_writes is refused" || no "wipe + ack accepted"
  [[ "$(gate_out "$WTOK" true false false true "10514957x")" != 0\|* ]] \
    && ok "a non-numeric expected_plaintext_volume_id is refused" || no "a non-numeric pin was accepted"
  [[ "$(gate_out "$WTOK" true false false true "")" != 0\|* ]] \
    && ok "a wipe with an EMPTY pin is refused" || no "a wipe with an empty pin was accepted"
  [[ "$(gate_out "CUTOVER-WORKSPACES-LUKS" true false false false 105149570)" != 0\|* ]] \
    && ok "a pin on a NON-wipe dispatch is refused (a mis-filled field is surfaced, not ignored)" || no "a pin on a non-wipe dispatch was accepted"
  [[ "$(gate_out "CUTOVER-WORKSPACES-LUKS" true false false true 105149570)" != 0\|* ]] \
    && ok "the cutover token cannot authorize a wipe" || no "the cutover token authorized a wipe"
  [[ "$(gate_out "$WTOK" true false false false "")" != 0\|* ]] \
    && ok "the wipe token is rejected on a non-wipe dispatch" || no "the wipe token authorized a non-wipe dispatch"
  [[ "$(gate_out "$WTOK" true false false true 105149570)" == 0\|* ]] \
    && ok "POSITIVE CONTROL: the wipe rehearsal dispatch is accepted" || no "the wipe rehearsal was refused: $(gate_out "$WTOK" true false false true 105149570 | cut -c1-160)"
  [[ "$(gate_out "$WTOK" false false false true 105149570)" == 0\|* ]] \
    && ok "POSITIVE CONTROL: the real wipe dispatch is accepted (the environment approval is the authorization)" || no "the real wipe dispatch was refused"
  [[ "$(gate_out "CUTOVER-WORKSPACES-LUKS" true false false false "")" == 0\|* ]] \
    && ok "POSITIVE CONTROL: an ordinary rehearsal (wipe/pin absent) still passes" || no "the ordinary rehearsal broke"
fi

# ============================================================================================
# Behavioral legs for the wipe API/host steps: each EXTRACTED step body runs under GitHub's own
# `bash --noprofile --norc -eo pipefail`, against recording stubs on PATH. The curl stub prints what
# `-w '%{http_code}'` prints and — like real curl — exits 22 under -f on a >=400, so a body that
# reintroduced -f would take a 404 as a crash, not as an answer.
# ============================================================================================
BIN="$SCRATCH/bin"; FIX="$SCRATCH/fix"; mkdir -p "$BIN"
cat > "$BIN/curl" <<'STUB'
#!/usr/bin/env bash
method=GET out="" wfmt="" url="" fail=0 cfg=0 data=""
while [ $# -gt 0 ]; do
  case "$1" in
    -X) method="$2"; shift 2 ;;
    -o) out="$2"; shift 2 ;;
    -w) wfmt="$2"; shift 2 ;;
    --data) data="$2"; shift 2 ;;
    -H) shift 2 ;;
    --config) [ "$2" = - ] && cfg=1; shift 2 ;;
    --max-time) shift 2 ;;
    -sS|-s|-S) shift ;;
    -f|--fail|-fsS|-fs) fail=1; shift ;;
    https://*) url="$1"; shift ;;
    *) echo "STUB_UNKNOWN_FLAG curl $1" >> "$CURL_LOG"; exit 64 ;;
  esac
done
if [ "$cfg" = 1 ]; then cat >> "$CURL_CFG"; fi
path="${url#https://api.hetzner.cloud/v1}"
printf '%s %s%s\n' "$method" "$path" "${data:+ DATA=$data}" >> "$CURL_LOG"
key="$(printf '%s_%s' "$method" "$path" | tr -c 'A-Za-z0-9_\n' '_')"
n=0; [ -f "$FIX/$key.n" ] && n="$(cat "$FIX/$key.n")"; echo $((n + 1)) > "$FIX/$key.n"
i="$n"; while [ "$i" -ge 0 ] && [ ! -f "$FIX/$key.$i" ]; do i=$((i - 1)); done
if [ "$i" -lt 0 ]; then code=599; body='{"error":{"code":"stub_no_fixture"}}'
else code="$(head -n1 "$FIX/$key.$i")"; body="$(tail -n +2 "$FIX/$key.$i")"; fi
if [ -n "$out" ]; then printf '%s' "$body" > "$out"; else printf '%s' "$body"; fi
if [ "$fail" = 1 ] && [ "$code" -ge 400 ]; then exit 22; fi
[ -n "$wfmt" ] && printf '%s' "$code"
exit 0
STUB
cat > "$BIN/gh" <<'STUB'
#!/usr/bin/env bash
printf 'gh %s\n' "$*" >> "$GH_LOG"
case "$*" in
  *"actions/workflows/apply-web-platform-infra.yml"*) printf '{"state":"%s"}\n' "${GH_STATE_APPLY:-disabled_manually}" ;;
  *"actions/workflows/apply-deploy-pipeline-fix.yml"*) printf '{"state":"%s"}\n' "${GH_STATE_PIPELINE:-disabled_manually}" ;;
  "run list"*"--workflow apply-web-platform-infra.yml"*) printf '%s\n' "${GH_RUNS_APPLY:-[]}" ;;
  "run list"*"--workflow apply-deploy-pipeline-fix.yml"*) printf '%s\n' "${GH_RUNS_PIPELINE:-[]}" ;;
  "run list"*"--workflow workspaces-luks-verify.yml"*) printf '%s\n' "${GH_VERIFY_RUNS:-[]}" ;;
  "run view "*"--log"*) printf '%s\n' "${GH_VERIFY_LOG:-}" ;;
  *) echo "STUB_UNKNOWN gh $*" >> "$GH_LOG"; exit 64 ;;
esac
STUB
cat > "$BIN/ssh-stub" <<'STUB'
#!/usr/bin/env bash
cmd="${*: -1}"
printf 'ssh %s\n' "$*" >> "$SSH_LOG"
case "$cmd" in
  *"mktemp -d"*) printf '/var/lib/workspaces-luks/wl-cutover.TEST\n' ;;
  *"tar xzf"*) cat > /dev/null ;;
  *"workspaces-cutover.sh"*) cat > "$SSH_ENV_CAPTURE"; [ -f "${SSH_HOST_OUT:-/dev/null}" ] && cat "$SSH_HOST_OUT"; exit "${SSH_RC:-0}" ;;
  *) : ;;
esac
exit 0
STUB
printf '#!/usr/bin/env bash\nprintf "sleep %%s\\n" "$*" >> "${SLEEP_LOG:-/dev/null}"\n' > "$BIN/sleep"
printf '#!/usr/bin/env bash\nprintf "doppler %%s\\n" "$*" >> "${DOPPLER_LOG:-/dev/null}"\ncase "$*" in *HCLOUD_TOKEN_READONLY*) printf "%%s" "${RO_TOKEN-}"; [ -n "${RO_TOKEN-}" ] ;; *HCLOUD_TOKEN*) printf "%%s" "${RW_TOKEN-rw-token-synth}" ;; *) exit 64 ;; esac\n' > "$BIN/doppler"
chmod +x "$BIN"/*

VOL_ATTACHED='{"volume":{"id":105149570,"name":"soleur-web-platform-data","server":123931471,"size":20,"format":"ext4","protection":{"delete":false},"linux_device":"/dev/disk/by-id/scsi-0HC_Volume_105149570","created":"2026-05-01T00:00:00+00:00","labels":{"role":"workspaces"}}}'
VOL_DETACHED='{"volume":{"id":105149570,"name":"soleur-web-platform-data","server":null,"size":20,"format":"ext4","protection":{"delete":false},"linux_device":null,"created":"2026-05-01T00:00:00+00:00","labels":{"role":"workspaces"}}}'
SRV_BOTH='{"server":{"id":123931471,"name":"soleur-web-platform","volumes":[105149570,106443278]}}'
SRV_LUKS_ONLY='{"server":{"id":123931471,"name":"soleur-web-platform","volumes":[106443278]}}'
LOOKUP_ONE='{"volumes":[{"id":105149570,"name":"soleur-web-platform-data"}]}'
fx_reset() { rm -rf "$FIX"; mkdir -p "$FIX"; : > "$SCRATCH/curl.log"; : > "$SCRATCH/curl.cfg"; : > "$SCRATCH/gh.log"; : > "$SCRATCH/ssh.log"; : > "$SCRATCH/sleep.log"; }
fx() {  # <METHOD> <path> <seq-index> <code> <body>
  local key; key="$(printf '%s_%s' "$1" "$2" | tr -c 'A-Za-z0-9_\n' '_')"
  printf '%s\n%s' "$4" "$5" > "$FIX/$key.$3"
}
fx_happy_pre() {  # the world a correct pre-wipe dispatch sees
  fx GET "/servers/123931471" 0 200 "$SRV_BOTH"
  fx GET "/volumes/105149570" 0 200 "$VOL_ATTACHED"
  fx GET "/volumes?name=soleur-web-platform-data" 0 200 "$LOOKUP_ONE"
  fx PUT "/volumes/105149570" 0 200 "$VOL_ATTACHED"
}
# run_body <file> [VAR=value ...] -> BODY_RC, BODY_OUT (stdout+stderr), GHOUT (GITHUB_OUTPUT contents)
run_body() {
  local f="$1"; shift
  : > "$SCRATCH/gh_output"; : > "$SCRATCH/gh_summary"; : > "$SCRATCH/gh_env"
  BODY_RC=0
  BODY_OUT="$(env PATH="$BIN:$PATH" CURL_LOG="$SCRATCH/curl.log" CURL_CFG="$SCRATCH/curl.cfg" FIX="$FIX" \
    GH_LOG="$SCRATCH/gh.log" SSH_LOG="$SCRATCH/ssh.log" SLEEP_LOG="$SCRATCH/sleep.log" \
    GITHUB_OUTPUT="$SCRATCH/gh_output" GITHUB_STEP_SUMMARY="$SCRATCH/gh_summary" GITHUB_ENV="$SCRATCH/gh_env" \
    GITHUB_REPOSITORY="jikig-ai/soleur" REPO="jikig-ai/soleur" PIN="105149570" \
    PLAINTEXT_VOLUME_NAME="soleur-web-platform-data" WEB1_SERVER_ID="123931471" WEB1_SERVER_NAME="soleur-web-platform" \
    LUKS_VOLUME_ID="106443278" HCLOUD_TOKEN="hc-token-synth" \
    "$@" bash --noprofile --norc -eo pipefail "$f" 2>&1)" || BODY_RC=$?
  GHOUT="$(cat "$SCRATCH/gh_output")"
}
writes() { grep -cE '^(POST|PUT|DELETE) ' "$SCRATCH/curl.log" || true; }
mutations() { grep -cE '^(POST|DELETE) ' "$SCRATCH/curl.log" || true; }

# --- preflight `api`: classification (read-only; HCLOUD_TOKEN_READONLY-first) -------------------------
if [[ -f "$SCRATCH/pf-api.sh" ]]; then
  fx_reset; fx_happy_pre
  run_body "$SCRATCH/pf-api.sh" RO_TOKEN=ro-token-synth DOPPLER_TOKEN=dp-synth
  if [[ "$BODY_RC" == 0 && "$GHOUT" == *"api_state=attached"* && "$GHOUT" == *"size_bytes=21474836480"* && "$(writes)" == 0 ]] \
    && grep -q 'ro-token-synth' "$SCRATCH/curl.cfg" && ! grep -q 'token-synth' "$SCRATCH/curl.log"; then
    ok "PF1 preflight classifies attached, exports size_bytes = 20 GiB in bytes, writes nothing, and reads with the READ-ONLY token via --config (never argv)"
  else
    no "PF1 preflight attached classification wrong (rc=$BODY_RC out=[$GHOUT]) ${BODY_OUT:0:240}"
  fi
  grep -q 'soleur-web-platform-data' "$SCRATCH/gh_summary" && grep -q '105149570' "$SCRATCH/gh_summary" && grep -qi 'api_state' "$SCRATCH/gh_summary" \
    && ok "PF1b the approver banner (id, name, api_state) is written to the step summary before the gate" \
    || no "PF1b the approver banner is missing: $(head -c 200 "$SCRATCH/gh_summary")"
  fx_reset; fx_happy_pre; fx GET "/volumes/105149570" 0 200 "$VOL_DETACHED"
  run_body "$SCRATCH/pf-api.sh" RO_TOKEN=ro-token-synth
  [[ "$BODY_RC" == 0 && "$GHOUT" == *"api_state=detached"* ]] && ok "PF2 a detached pinned volume classifies detached" \
    || no "PF2 detached classification wrong (rc=$BODY_RC out=[$GHOUT]) ${BODY_OUT:0:200}"
  fx_reset; fx_happy_pre; fx GET "/volumes/105149570" 0 404 '{"error":{"code":"not_found"}}'; fx GET "/volumes?name=soleur-web-platform-data" 0 200 '{"volumes":[]}'
  run_body "$SCRATCH/pf-api.sh" RO_TOKEN=ro-token-synth
  [[ "$BODY_RC" != 0 && "$BODY_OUT" == *"workspaces-plaintext-forget.yml"* && "$GHOUT" != *"api_state="* ]] \
    && ok "PF3 absent (pin 404 + empty name lookup + presence proven) refuses and names the forget workflow as the remedy" \
    || no "PF3 absent not refused with the forget remedy (rc=$BODY_RC) ${BODY_OUT:0:200}"
  fx_reset; fx_happy_pre; fx GET "/servers/123931471" 0 404 '{"error":{"code":"not_found"}}'; fx GET "/volumes/105149570" 0 404 '{}'; fx GET "/volumes?name=soleur-web-platform-data" 0 200 '{"volumes":[]}'
  run_body "$SCRATCH/pf-api.sh" RO_TOKEN=ro-token-synth
  [[ "$BODY_RC" != 0 && "$BODY_OUT" != *"already deleted"* && "$GHOUT" != *"api_state="* ]] \
    && ok "PF4 a token that cannot see server 123931471 (another project) never reads '404' as 'absent'" \
    || no "PF4 a 404 from a blind token was read as absent (rc=$BODY_RC) ${BODY_OUT:0:200}"
  fx_reset; fx_happy_pre; fx GET "/servers/123931471" 0 200 '{"server":{"id":123931471,"name":"soleur-web-platform","volumes":[105149570]}}'
  run_body "$SCRATCH/pf-api.sh" RO_TOKEN=ro-token-synth
  [[ "$BODY_RC" != 0 ]] && ok "PF5 presence proof fails when the server's volumes lack the LUKS id 106443278" || no "PF5 presence proof passed without the LUKS volume"
  for mut in 'name|"soleur-web-platform-data-luks"' 'format|null' 'server|167390740' 'protection.delete|true' 'linux_device|"/dev/disk/by-id/scsi-0HC_Volume_106443278"'; do
    k="${mut%%|*}"; v="${mut#*|}"
    fx_reset; fx_happy_pre
    fx GET "/volumes/105149570" 0 200 "$(jq -c --argjson v "$v" ".volume.$k = \$v" <<<"$VOL_ATTACHED")"
    run_body "$SCRATCH/pf-api.sh" RO_TOKEN=ro-token-synth
    [[ "$BODY_RC" != 0 && "$GHOUT" != *"api_state="* ]] && ok "PF6 a pinned volume whose $k is $v is refused (named mismatch, no api_state)" \
      || no "PF6 a mismatched $k=$v was classified (rc=$BODY_RC out=[$GHOUT])"
  done
  fx_reset; fx_happy_pre; fx GET "/volumes?name=soleur-web-platform-data" 0 200 '{"volumes":[{"id":105149570},{"id":999}]}'
  run_body "$SCRATCH/pf-api.sh" RO_TOKEN=ro-token-synth
  [[ "$BODY_RC" != 0 ]] && ok "PF7 a name lookup returning two volumes is refused (the pin must be the ONLY one)" || no "PF7 an ambiguous name lookup was accepted"
  fx_reset; fx_happy_pre
  run_body "$SCRATCH/pf-api.sh" RO_TOKEN=ro-token-synth PIN=106443278
  [[ "$BODY_RC" != 0 ]] && ok "PF8 a pin equal to the LIVE LUKS id 106443278 is refused" || no "PF8 the LUKS id was accepted as the plaintext pin"
  fx_reset; fx_happy_pre; fx GET "/volumes/105149570" 0 500 '{"error":{"code":"server%error\r\n::add-mask::x"}}'
  run_body "$SCRATCH/pf-api.sh" RO_TOKEN=ro-token-synth
  [[ "$BODY_RC" != 0 && "$BODY_OUT" != *$'\n::add-mask::x'* ]] \
    && ok "PF9 a 500 is an error (never 'absent'), and API text reaches annotations only escaped (no injected workflow command)" \
    || no "PF9 a 500 was mishandled or its body injected a workflow command (rc=$BODY_RC) ${BODY_OUT:0:200}"
fi

# --- wipe `pre`: everything that must hold BEFORE web-1 is touched (Guard 6 #8/#9) -------------------
if [[ -f "$SCRATCH/wipe-pre.sh" ]]; then
  NOW_ISO="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  OLD_ISO="$(date -u -d '-30 hours' +%Y-%m-%dT%H:%M:%SZ)"
  VERIFY_OK="[{\"databaseId\":424242,\"createdAt\":\"$NOW_ISO\",\"headBranch\":\"main\",\"conclusion\":\"success\",\"event\":\"schedule\"}]"
  VERIFY_LOG_OK='verify	probe	[luks-monitor] SOLEUR_WORKSPACES_READYZ ready=true workspace_count=9 expected=8'
  pre_run() { run_body "$SCRATCH/wipe-pre.sh" API_STATE_PREFLIGHT=attached GH_VERIFY_RUNS="$VERIFY_OK" GH_VERIFY_LOG="$VERIFY_LOG_OK" "$@"; }
  fx_reset; fx_happy_pre; pre_run
  if [[ "$BODY_RC" == 0 ]] && grep -q '^PUT /volumes/105149570 DATA={"labels":{"role":"workspaces"}}$' "$SCRATCH/curl.log" && [[ "$(mutations)" == 0 ]]; then
    ok "W-PRE1 the preconditions pass on a paused, verified, write-capable world — the only write is the idempotent labels PUT, verbatim"
  else
    no "W-PRE1 happy preconditions failed (rc=$BODY_RC) ${BODY_OUT:0:240} curl=[$(tr '\n' '|' < "$SCRATCH/curl.log")]"
  fi
  fx_reset; fx_happy_pre; pre_run GH_STATE_APPLY=active
  [[ "$BODY_RC" != 0 && "$(writes)" == 0 ]] && ok "W-PRE2 (Guard 6 #8) apply-web-platform-infra.yml still active → refused before any write" || no "W-PRE2 an active apply workflow was accepted"
  fx_reset; fx_happy_pre; pre_run GH_RUNS_PIPELINE='[{"status":"queued"}]'
  [[ "$BODY_RC" != 0 && "$(writes)" == 0 ]] && ok "W-PRE3 (Guard 6 #8) a queued apply-deploy-pipeline-fix run → refused (disabling does not cancel a queued run)" || no "W-PRE3 a queued run was accepted"
  fx_reset; fx_happy_pre; pre_run GH_VERIFY_RUNS="[{\"databaseId\":1,\"createdAt\":\"$OLD_ISO\",\"headBranch\":\"main\",\"conclusion\":\"success\"}]"
  [[ "$BODY_RC" != 0 && "$(writes)" == 0 ]] && ok "W-PRE4 (Guard 6 #9) no successful verify run on main in the last 24h → refused before web-1" || no "W-PRE4 a stale verify run was accepted"
  fx_reset; fx_happy_pre; pre_run GH_VERIFY_LOG='[luks-monitor] SOLEUR_WORKSPACES_READYZ ready=false'
  [[ "$BODY_RC" != 0 ]] && ok "W-PRE5 a verify run whose log lacks ready=true → refused" || no "W-PRE5 a verify run without ready=true was accepted"
  fx_reset; fx_happy_pre; fx PUT "/volumes/105149570" 0 403 '{"error":{"code":"forbidden"}}'
  pre_run
  [[ "$BODY_RC" != 0 ]] && ok "W-PRE6 a read-only token 403s on the labels PUT HERE, before web-1 is touched" || no "W-PRE6 a 403 write probe was accepted"
  fx_reset; fx_happy_pre; fx GET "/volumes/105149570" 0 200 "$VOL_DETACHED"
  pre_run
  [[ "$BODY_RC" != 0 && "$(writes)" == 0 ]] && ok "W-PRE7 api_state changed since preflight (attached -> detached) → refused (the approval may have waited hours)" || no "W-PRE7 a changed api_state was accepted"
  fx_reset; fx_happy_pre; fx GET "/servers/123931471" 0 200 '{"server":{"id":123931471,"name":"soleur-web-platform","volumes":[105149570]}}'
  pre_run
  [[ "$BODY_RC" != 0 && "$(writes)" == 0 ]] && ok "W-PRE8 the presence proof runs in the gated job too" || no "W-PRE8 the gated job skipped the presence proof"
fi

# --- wipe `host`: the success-row parser and the host-output wrap (Guard 6 #1/#2/#3/#6/#7) -----------
if [[ -f "$SCRATCH/wipe-host.sh" ]]; then
  ROWP='SOLEUR_WORKSPACES_LUKS_WIPE feature=workspaces-luks op=workspaces-luks-wipe'
  host_run() {  # <api_state> <host-output-lines> [VAR=value ...]
    local st="$1" lines="$2"; shift 2
    printf '%s\n' "$lines" > "$SCRATCH/host.out"; : > "$SCRATCH/env.capture"; : > "$SCRATCH/ssh.log"
    run_body "$SCRATCH/wipe-host.sh" API_STATE="$st" WEB_HOST=10.0.1.10 WEB_HOST_SSH="$BIN/ssh-stub" \
      SSH_HOST_OUT="$SCRATCH/host.out" SSH_ENV_CAPTURE="$SCRATCH/env.capture" INFRA_DIR="apps/web-platform/infra" \
      WORKSPACES_LUKS_BOOT_TOKEN=boot-token-synth DOPPLER_TOKEN=dp-synth PLAINTEXT_SIZE_BYTES=21474836480 \
      LUKS_DEV_ID=106443278 "$@"
  }
  WIPED="$ROWP result=wiped arm=first_wipe volume_id=105149570 bytes=21474836480 readback=zero"
  host_run attached "[workspaces-cutover] zeroing
$WIPED"
  if [[ "$BODY_RC" == 0 && "$GHOUT" == *"result=wiped"* ]] \
    && [[ "$(tail -n 2 "$SCRATCH/env.capture" | tr '\n' ' ')" == "CONFIRM_WIPE=1 DRY_RUN=0 " ]] \
    && [[ -z "$(cut -d= -f1 "$SCRATCH/env.capture" | sort | uniq -d)" ]] && grep -q '^WORKSPACES_PLAINTEXT_DEV=/dev/disk/by-id/scsi-0HC_Volume_105149570$' "$SCRATCH/env.capture"; then
    ok "W-HOST1 one wiped row for the pin + ssh rc 0 → verdict wiped; the .env ends CONFIRM_WIPE=1, DRY_RUN=0 with no duplicate key"
  else
    no "W-HOST1 happy host step wrong (rc=$BODY_RC out=[$GHOUT]) env=[$(tr '\n' '|' < "$SCRATCH/env.capture" | sed 's/boot-token-synth/<tok>/')] ${BODY_OUT:0:200}"
  fi
  host_run detached "$ROWP result=already_wiped_detached arm=detached volume_id=105149570 wiped_at=1759000000"
  [[ "$BODY_RC" == 0 && "$GHOUT" == *"result=already_wiped_detached"* ]] && ok "W-HOST2 (Guard 6 H1) api_state=detached + already_wiped_detached → verdict for the API step" \
    || no "W-HOST2 detached + already_wiped_detached rejected (rc=$BODY_RC) ${BODY_OUT:0:200}"
  host_run attached "$WIPED
$WIPED"
  [[ "$BODY_RC" != 0 && "$GHOUT" != *"result="* ]] && ok "W-HOST3 (Guard 6 #1) two success rows (a replayed line) → the job fails before any API write" || no "W-HOST3 two success rows accepted"
  host_run attached "${WIPED/volume_id=105149570/volume_id=106443278}"
  [[ "$BODY_RC" != 0 ]] && ok "W-HOST4 (Guard 6 #2) a success row for another id → failed" || no "W-HOST4 a row for another id was accepted"
  host_run detached "$WIPED"
  [[ "$BODY_RC" != 0 ]] && ok "W-HOST5 (Guard 6 #3) api_state=detached with a wiped row → failed" || no "W-HOST5 detached+wiped accepted"
  host_run attached "$ROWP result=already_wiped_detached arm=detached volume_id=105149570"
  [[ "$BODY_RC" != 0 ]] && ok "W-HOST6 (Guard 6 #3) api_state=attached with already_wiped_detached → failed" || no "W-HOST6 attached+already_wiped_detached accepted"
  host_run attached "$WIPED" SSH_RC=1
  [[ "$BODY_RC" != 0 && "$GHOUT" != *"result="* ]] && ok "W-HOST7 (Guard 6 #6) exactly one success row but ssh rc 1 → failed" || no "W-HOST7 a non-zero ssh rc was accepted"
  host_run attached "  $WIPED"
  [[ "$BODY_RC" != 0 ]] && ok "W-HOST8 an indented (not column-0) success row does not parse" || no "W-HOST8 an indented row was accepted"
  host_run attached "$WIPED
::add-mask::host-line-injection"
  # awk, never grep, in these captures: this suite runs `set -e`, and grep's rc 1 on "no match" is an
  # ANSWER here (the fence is missing), not an error that should kill the suite.
  so="$(awk '/^::stop-commands::/ { print NR; exit }' <<<"$BODY_OUT")"
  tk="$(awk '/^::stop-commands::/ { sub(/^::stop-commands::/, ""); print; exit }' <<<"$BODY_OUT")"
  inj="$(awk '/^::add-mask::host-line-injection/ { print NR; exit }' <<<"$BODY_OUT")"
  rs="$(awk -v t="::${tk}::" '$0 == t { print NR; exit }' <<<"$BODY_OUT")"
  if [[ -n "$tk" && ${#tk} -ge 16 && -n "$so" && -n "$inj" && -n "$rs" && "$so" -lt "$inj" && "$inj" -lt "$rs" ]]; then
    ok "W-HOST9 (Guard 6 #7) host output streams inside ::stop-commands::<random token> … ::<token>:: — a host ::add-mask:: line is inert"
  else
    no "W-HOST9 the stop-commands wrap is missing or does not enclose the host output (so=$so inj=$inj rs=$rs tk=${#tk})"
  fi
  host_run attached "$WIPED" PLAINTEXT_SIZE_BYTES='1;touch /tmp/x'
  [[ "$BODY_RC" != 0 && ! -s "$SCRATCH/ssh.log" ]] \
    && ok "W-HOST10 a metacharacter in a .env value is refused BEFORE web-1 is reached (the host sources .env as shell)" \
    || no "W-HOST10 a metacharacter value reached the host (rc=$BODY_RC)"
fi

# --- wipe `api`: detach -> poll -> delete -> 404 -> server volumes == [LUKS] --------------------------
if [[ -f "$SCRATCH/wipe-api.sh" ]]; then
  fx_api() {  # attached world, detach action succeeds after N polls
    fx GET "/servers/123931471" 0 200 "$SRV_BOTH"
    fx GET "/servers/123931471" 2 200 "$SRV_LUKS_ONLY"
    fx GET "/volumes/105149570" 0 200 "$VOL_ATTACHED"
    fx GET "/volumes/105149570" 1 200 "$VOL_DETACHED"
    fx GET "/volumes/105149570" 2 404 '{"error":{"code":"not_found"}}'
    fx POST "/volumes/105149570/actions/detach" 0 201 '{"action":{"id":777,"status":"running"}}'
    fx GET "/actions/777" 0 200 '{"action":{"id":777,"status":"running"}}'
    fx GET "/actions/777" 2 200 '{"action":{"id":777,"status":"success"}}'
    fx DELETE "/volumes/105149570" 0 204 ''
  }
  api_run() { run_body "$SCRATCH/wipe-api.sh" API_STATE=attached HOST_RESULT=wiped "$@"; }
  fx_reset; fx_api; api_run
  if [[ "$BODY_RC" == 0 ]] && [[ "$(grep -c '^POST /volumes/105149570/actions/detach' "$SCRATCH/curl.log")" == 1 ]] \
    && [[ "$(grep -c '^DELETE /volumes/105149570' "$SCRATCH/curl.log")" == 1 ]] && ! grep -q 'hc-token-synth' "$SCRATCH/curl.log" \
    && grep -q 'hc-token-synth' "$SCRATCH/curl.cfg"; then
    ok "W-API1 attached: one detach, polled to success, one DELETE 204, final 404 and server volumes == [106443278]; token only on stdin"
  else
    no "W-API1 the API sequence failed (rc=$BODY_RC) ${BODY_OUT:0:240} curl=[$(tr '\n' '|' < "$SCRATCH/curl.log" | cut -c1-300)]"
  fi
  d_idx="$(awk '/^DELETE / { print NR; exit }' "$SCRATCH/curl.log")"; p_idx="$(awk '/^POST / { print NR; exit }' "$SCRATCH/curl.log")"
  [[ -n "$d_idx" && -n "$p_idx" && "$p_idx" -lt "$d_idx" ]] && ok "W-API1b the detach precedes the delete" || no "W-API1b delete not after detach (post=$p_idx delete=$d_idx)"
  fx_reset; fx_api; fx GET "/actions/777" 2 200 '{"action":{"id":777,"status":"running"}}'; fx GET "/actions/777" 70 200 '{"action":{"id":777,"status":"success"}}'
  api_run
  [[ "$BODY_RC" == 0 && "$(grep -c '^POST ' "$SCRATCH/curl.log")" == 1 ]] \
    && ok "W-API2 a detach still running past 300s keeps POLLING the same action — never a second POST (which would 'locked')" \
    || no "W-API2 a long detach re-POSTed or failed (rc=$BODY_RC posts=$(grep -c '^POST ' "$SCRATCH/curl.log"))"
  fx_reset; fx_api; fx GET "/actions/777" 2 200 '{"action":{"id":777,"status":"error"}}'
  api_run
  [[ "$BODY_RC" != 0 && "$(grep -c '^DELETE ' "$SCRATCH/curl.log")" == 0 ]] && ok "W-API3 a detach action in error → failed, no DELETE" || no "W-API3 a failed detach went on to DELETE"
  fx_reset; fx_api; fx GET "/volumes/105149570" 0 200 "$VOL_DETACHED"; fx GET "/volumes/105149570" 1 404 '{}'
  run_body "$SCRATCH/wipe-api.sh" API_STATE=detached HOST_RESULT=already_wiped_detached
  [[ "$BODY_RC" == 0 && "$(grep -c '^POST ' "$SCRATCH/curl.log")" == 0 && "$(grep -c '^DELETE ' "$SCRATCH/curl.log")" == 1 ]] \
    && ok "W-API4 detached: no detach, one DELETE" || no "W-API4 the detached arm misbehaved (rc=$BODY_RC) ${BODY_OUT:0:200}"
  fx_reset; fx_api
  api_run HOST_RESULT=already_wiped_detached
  [[ "$BODY_RC" != 0 && "$(mutations)" == 0 ]] && ok "W-API5 a host verdict that does not match api_state → failed before any API write" || no "W-API5 a mismatched host verdict reached the API"
  fx_reset; fx_api
  api_run HOST_RESULT=
  [[ "$BODY_RC" != 0 && "$(mutations)" == 0 ]] && ok "W-API6 no host verdict at all → no API write" || no "W-API6 an empty host verdict reached the API"
  fx_reset; fx_api; fx DELETE "/volumes/105149570" 0 404 '{"error":{"code":"not_found"}}'
  api_run
  [[ "$BODY_RC" == 0 ]] && ok "W-API7 a DELETE 404 is accepted once the presence proof re-runs green" || no "W-API7 DELETE 404 with a green presence proof failed (rc=$BODY_RC) ${BODY_OUT:0:200}"
  fx_reset; fx_api; fx DELETE "/volumes/105149570" 0 404 '{}'; fx GET "/servers/123931471" 1 404 '{}'
  api_run
  [[ "$BODY_RC" != 0 ]] && ok "W-API8 a DELETE 404 with the presence proof FAILING (blind token) is an error" || no "W-API8 a blind 404 was accepted as deleted"
  fx_reset; fx_api; fx GET "/servers/123931471" 2 200 "$SRV_BOTH"
  api_run
  [[ "$BODY_RC" != 0 ]] && ok "W-API9 the server still listing the plaintext volume after the delete → failed" || no "W-API9 final server volumes not asserted"
  fx_reset; fx_api
  api_run PIN=106443278
  [[ "$BODY_RC" != 0 && "$(mutations)" == 0 ]] && ok "W-API10 the pin equal to the LUKS id is re-checked in the API step → no write" || no "W-API10 the LUKS id reached the API step"
fi

printf '\n%s passed, %s failed\n' "$pass" "$fail"

# NON-DEGENERACY FLOOR — see the sibling rationale in workspaces-luks-staging.test.sh. A python
# leg that dies before emitting verdicts, or a `check()` block deleted wholesale, would otherwise
# leave this suite reporting "0 passed, 0 failed" and exiting 0.
WF_MIN_ASSERTIONS=133
if [[ "$pass" -lt "$WF_MIN_ASSERTIONS" ]]; then
  echo "FAIL - only $pass assertions ran (floor $WF_MIN_ASSERTIONS) — the structural leg produced fewer verdicts than expected; a green run here would be vacuous"
  exit 1
fi
[[ "$fail" -eq 0 ]] || exit 1
