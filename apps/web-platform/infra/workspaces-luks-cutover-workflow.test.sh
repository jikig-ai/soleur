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
#   (3) Guard B3 (#6604 PR B): with the step-7 wipe retired, NO step in the file can detach, delete or
#       relabel a Hetzner volume, the jobs are exactly {preflight, cutover}, and cutover has no
#       job-level `if:`. The census scans every step whole and its step count is pinned exactly.
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

# Instrument self-test: both helpers must move their counter, or every verdict below is noise (an
# ok() that skips its increment starves the floor; a no() rerouted to ok() hides a real failure).
ok "instrument self-test (pass arm)" > /dev/null
no "instrument self-test (fail arm)" > /dev/null
if [[ "$pass" -ne 1 || "$fail" -ne 1 ]]; then
  printf 'FATAL: verdict helpers are broken (pass=%s fail=%s)\n' "$pass" "$fail"
  exit 2
fi
pass=0
fail=0

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

# check() self-test (must-FAIL probe, then must-PASS): a check() rerouted to always record "ok" — or
# to record nothing — would turn every structural row below green over a real regression. Exit 2
# before a single verdict is written; the probes are popped so they never reach the report.
check("SELFTEST must-FAIL probe", False, "x")
check("SELFTEST must-PASS probe", True)
if [v[0] for v in verdicts[-2:]] != ["FAIL", "ok"] or len(verdicts) != 2:
    print(f"FATAL: check() is broken (probe verdicts={verdicts[-2:]!r})", file=sys.stderr)
    sys.exit(2)
del verdicts[:]

jobs = wf.get("jobs") or {}

# ── Guard B3 (#6604 PR B) — no destructive Hetzner path remains in this workflow ─────────────────
# Step 7 retired web-1's plaintext volume; the gated `wipe` job that detached and deleted it, the
# preflight classification that fed it, and the separate state-forget workflow are gone. The property
# is FILE-WIDE: no job and no step may detach, delete or relabel a volume, or touch a server.
#
# ALLOWLIST, not a denylist of write spellings (a denylist is always one spelling short: a lower-case
# method, `hcloud --flag volume rm`, requests.delete, a composite action, a script on the runner).
# Exactly ONE step may name the Hetzner API or hcloud at all — "Run workspaces-luks cutover" — and T5
# below EXECUTES that step and proves its only Hetzner call is one GET. Every other step that names
# `api.hetzner.cloud`, `hcloud`, a `/volumes` or `/servers` path, or reads Doppler is RED. Local
# `uses:` is limited to the existing bridge action, whose body this census cannot read.
#
# Each step is judged on its EFFECTIVE text: the workflow `env:`, its job's `env:` and `defaults:`,
# and the step itself (json.dumps: run, env, with, uses, name). A URL in a job-level env and a
# `curl -X DELETE "$EP"` in the step are then still one write. Matching is inside that text, never
# per line, so a method on one line and its path on the next is still one write.
check("B3 jobs are exactly {preflight, cutover} (the gated `wipe` job is retired)",
      set(jobs) == {"preflight", "cutover"}, sorted(jobs))
for jn in ("preflight", "cutover"):
    check(f"B3 job `{jn}` carries no job-level if: (a failed preflight blocks cutover through the implicit success())",
          "if" not in (jobs.get(jn) or {}), (jobs.get(jn) or {}).get("if"))
HZ_STEP = ("cutover", "Run workspaces-luks cutover")
LOCAL_USES_OK = {"./.github/actions/cf-tunnel-ssh-bridge"}
# Naming the API at all, outside the allowlisted step. Case-insensitive: HCLOUD_TOKEN is the credential.
HZ_NAMED = re.compile(r"api\.hetzner\.cloud|hcloud|/volumes\b|/servers\b", re.I)
# Reading a secret through Doppler hands the step prd_terraform's write-capable HCLOUD_TOKEN.
DOPPLER_READ = re.compile(r"\bdoppler\s+(?:secrets|run)\b", re.I)
# A repo script EXECUTED ON THE RUNNER inside the token-holding step: its body is invisible here.
# Anchored at a line start, so the `bash "$REMOTE_DIR/workspaces-cutover.sh"` inside the ssh argument
# (it runs on web-1, which holds no HCLOUD_TOKEN) is not one.
RUNNER_SCRIPT = re.compile(r"^\s*(?:sudo\s+(?:-\S+\s+)*)?(?:(?:bash|sh|source|\.|python3?|node|bun|perl|ruby)\s+(?:-\S+\s+)*[\"']?[^\s\"'|;&<>]*[/.][^\s\"'|;&<>]*|\./\S+)", re.M)
# The denylist that still applies INSIDE the allowlisted step (T5 executes it; this is the static half).
HZ_TARGET = re.compile(r"/volumes\b|/servers\b|api\.hetzner\.cloud", re.I)
# The action endpoints are POST-only: naming one is a write whatever the method spelling.
HZ_ACTION = re.compile(r"/actions/(detach|attach|change_protection|resize|rebuild|reset|reboot|poweroff|shutdown|change_type|enable_rescue|create_image)\b", re.I)
# -X / --request with a write method — or with a VARIABLE method (`-X "$1"`, the retired hapi() shape),
# which can be any method at all. Case-sensitive flag: `-x "$f"` is a bash file test, not curl.
# json.dumps escapes quotes, hence the optional backslash before the quote.
HZ_FLAG_METHOD = re.compile(r"(?:-X|--request)(?:\s*|=)\\?[\"']?(?:(?i:DELETE|PUT|POST|PATCH)\b|\$)")
# A bare method token in ANY case (`hapi DELETE`, `hapi "put"`, `requests.delete(`), matched only in a
# step that names a Hetzner volume/server path or the API host. Never followed by a hyphen: prose such
# as "Post-incident" in a run: comment is not a method.
HZ_BARE_METHOD = re.compile(r"(?<![A-Za-z0-9_])(?i:DELETE|PUT|POST|PATCH)(?![A-Za-z0-9_-])")
# Any hcloud volume/server/IP verb but a read, after any global flags (`hcloud --poll-interval 1s volume
# detach`), including a variable verb (`hcloud volume "$VERB"`).
HZ_CLI = re.compile(r"\bhcloud\s+(?:--?[\w-]+(?:[= ](?!(?:volume|server|floating-ip|primary-ip)\b)[^\s-]\S*)?\s+)*(?:volume|server|floating-ip|primary-ip)\s+(?!(?:list|describe)\b)\S")
def hz_write(text):
    if HZ_ACTION.search(text) or HZ_CLI.search(text):
        return True
    return bool(HZ_TARGET.search(text) and (HZ_FLAG_METHOD.search(text) or HZ_BARE_METHOD.search(text)))
# The step text with REAL newlines. json.dumps turns a line break into the two characters `\n`, so a
# `\b` anchor at the start of a run: line (`\bhcloud`, `\bdoppler`, `^\s*bash`) never matched the
# second line of a step: `curl ...\nhcloud volume rm 1` read as `nhcloud`.
def flat(o):
    if isinstance(o, dict):
        return "\n".join(f"{k}\n{flat(v)}" for k, v in o.items())
    if isinstance(o, list):
        return "\n".join(flat(v) for v in o)
    return "" if o is None else str(o)
def census(doc):
    """-> (offenders, steps scanned, allowlisted steps found) for a parsed workflow document."""
    out, n, allowed = [], 0, 0
    for jn, j in (doc.get("jobs") or {}).items():
        j = j or {}
        for i, st in enumerate(j.get("steps") or []):
            n += 1
            tag = f"{jn}:{st.get('id') or st.get('name') or i}"
            eff = flat({"wf_env": doc.get("env"), "job_env": j.get("env"), "job_defaults": j.get("defaults"), "step": st})
            is_hz = (jn, str(st.get("name", ""))) == HZ_STEP
            allowed += is_hz
            uses = str(st.get("uses", ""))
            if uses.startswith("./") and uses not in LOCAL_USES_OK:
                out.append(f"{tag}: local action {uses} is not in the allowlist (its body is unscanned)")
            if not is_hz:
                if HZ_NAMED.search(eff):
                    out.append(f"{tag}: names the Hetzner API / hcloud outside the allowlisted step")
                if DOPPLER_READ.search(eff):
                    out.append(f"{tag}: reads Doppler (prd_terraform holds HCLOUD_TOKEN) outside the allowlisted step")
                continue
            if hz_write(eff):
                out.append(f"{tag}: the allowlisted step carries a Hetzner write")
            if RUNNER_SCRIPT.search(str(st.get("run", ""))):
                out.append(f"{tag}: the token-holding step executes a script on the runner")
    return out, n, allowed
hz_writers, census_steps, census_allowed = census(wf)
open(f"{scratch}/census-steps.txt", "w").write(str(census_steps))
check("B3 census: no step can name the Hetzner API, hcloud or Doppler outside the one allowlisted step, and that step carries no write",
      not hz_writers, hz_writers)
check("B3 census: the allowlisted step resolves exactly once (a rename would empty the allowlist silently)", census_allowed == 1, census_allowed)
# H1 (must-PASS) — the cutover Run step's read-only LUKS-device lookup reaches the Hetzner volumes API
# and is NOT a write: the census is exercised on a real Hetzner-touching step, not on an empty file.
_run = next((st for st in ((jobs.get("cutover") or {}).get("steps") or []) if "Run workspaces-luks cutover" in str(st.get("name", ""))), None)
_run_txt = flat(_run) if _run else ""
check("B3 H1: the cutover Run step reads /volumes on the Hetzner API (the census has a live target to judge)",
      "api.hetzner.cloud/v1/volumes" in _run_txt)
check("B3 H1: that read-only GET is not classified a write", bool(_run) and not hz_write(_run_txt))
# The classifier's own teeth, on synthesized step text (never on the live file): each spelling the
# retired code used or could have used must classify as a write.
for probe in ('hapi DELETE "/volumes/${PIN}"', 'hapi "DELETE" "/volumes/${PIN}"', 'hapi POST "/volumes/${PIN}/actions/detach"',
              'curl --request=DELETE https://api.hetzner.cloud/v1/volumes/1', 'curl -XDELETE https://api.hetzner.cloud/v1/volumes/1',
              'curl -X "$1" "https://api.hetzner.cloud/v1$2"', 'hapi PUT "/volumes/${PIN}" "$labels"', 'hcloud volume detach 1',
              'hcloud volume delete 1',
              # rvB-security B3 shapes: server writes (a server delete detaches its volumes), lower-case
              # methods, more hcloud verbs and global flags; rvB-tests W4/W5.
              # (the rebuild spelling is split in SOURCE only: cutover-inngest-workflow.test.sh G3 greps the whole tree
              # for it, and the runtime string the classifier sees is unchanged)
              'hapi DELETE "/servers/${ID}"', 'hapi POST "/servers/${ID}/actions/re' + 'build"', 'hcloud server delete soleur-web-1',
              'hapi delete "/volumes/1"', 'hcloud volume rm 1', 'hcloud --poll-interval 1s volume detach 106443278',
              'hcloud volume "$VERB" 106443278',
              "python3 -c \"import requests; requests.delete('https://api.hetzner.cloud/v1/volumes/'+V)\""):
    check(f"B3 census classifies {probe!r} as a write", hz_write(json.dumps({"run": probe})))
for probe in ("hcloud volume list -o json", "hcloud server describe soleur-web-1"):
    check(f"B3 census does NOT classify the read {probe!r} as a write (the classifier is not refuse-everything)",
          not hz_write(json.dumps({"run": probe})))

# B3 MUTATION BATTERY — each row plants ONE shape into a copy of the LIVE workflow and requires the
# census to name it. These are the shapes the per-step denylist census passed (rvB-tests W2/W7/W4/W5/W9,
# rvB-security B3): a target in job- or workflow-level env, a variable or lower-case verb, a non-curl
# client, a composite action, a script run on the runner, a Doppler read in another step.
import copy
def _step(doc, job, name):
    return next(s for s in doc["jobs"][job]["steps"] if s.get("name") == name)
VERIFY = ("cutover", "Verify required secrets present")
def _append(doc, where, line):
    s = _step(doc, *where); s["run"] = str(s.get("run", "")) + "\n" + line + "\n"
def m_w2(d):
    d["jobs"]["cutover"]["env"] = {"HZ_EP": "https://api.hetzner.cloud/v1/volumes/106443278"}
    _append(d, VERIFY, 'curl -fsS -X DELETE -H "Authorization: Bearer $T" "$HZ_EP"')
def m_w2_detach(d):
    d["jobs"]["cutover"]["env"] = {"EP": "https://api.hetzner.cloud/v1/volumes/106443278/actions/detach"}
    _append(d, VERIFY, 'curl -fsS -X POST "$EP"')
def m_w7(d):
    d["env"]["HZ_API"] = "https://api.hetzner.cloud/v1"
    _append(d, VERIFY, 'curl -X DELETE "$HZ_API/servers/$WEB1_ID"')
def m_defaults(d):
    d["jobs"]["cutover"]["defaults"] = {"run": {"working-directory": "/srv/api.hetzner.cloud"}}
def m_w4(d):
    _append(d, HZ_STEP, 'hcloud volume "$VERB" 106443278')
def m_w5(d):
    _append(d, VERIFY, "python3 -c \"import requests; requests.delete('https://api.hetzner.cloud/v1/volumes/'+V)\"")
def m_w9(d):
    d["jobs"]["cutover"]["steps"].insert(1, {"name": "detach", "uses": "./.github/actions/hz-detach"})
def m_script(d):
    _append(d, HZ_STEP, 'bash scripts/hz-detach.sh "$VID"')
def m_doppler(d):
    _append(d, VERIFY, "doppler run -p soleur -c prd_terraform -- bash scripts/hz-detach.sh")
def m_server_cli(d):
    _append(d, VERIFY, "hcloud server delete soleur-web-1")
for tag, mut in (("W2 job-level env URL + DELETE in another step", m_w2), ("W2b job-level env detach endpoint + POST", m_w2_detach),
                 ("W7 workflow-level env host + DELETE /servers", m_w7), ("job-level defaults naming the API", m_defaults),
                 ("W4 variable hcloud verb in the allowlisted step", m_w4), ("W5 requests.delete in another step", m_w5),
                 ("W9 an unlisted local composite action", m_w9), ("a runner-side script in the token-holding step", m_script),
                 ("a Doppler read + script in another step", m_doppler), ("hcloud server delete in another step", m_server_cli)):
    d = copy.deepcopy(wf); mut(d)
    got_off = census(d)[0]
    check(f"B3 mutation [{tag}] is named by the census", bool(got_off), got_off)
# Negative control: a harmless added step is NOT an offender (the allowlist is not refuse-everything).
d = copy.deepcopy(wf); d["jobs"]["cutover"]["steps"].insert(1, {"name": "harmless", "run": "echo hello"})
check("B3 mutation control: a harmless added step is not named", not census(d)[0], census(d)[0])

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

# `needs: preflight` alone does not prove a preflight FAILURE blocks the cutover: an `if: always()` on
# the job would run it anyway, after a refused dispatch. The Guard B3 rows above pin that cutover
# carries NO job-level `if:` at all (the #6604 step-7 real-wipe skip is retired), so GitHub's implicit
# success() is the only predicate.

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

# ── #6604 PR B — the step-7 wipe wiring is RETIRED (inverted rows) ───────────────────────────────
# The wipe inputs, the identity constants it bound to, the preflight classification outputs and the
# cutover job's CONFIRM_WIPE/pin/size plumbing are gone. Each is asserted ABSENT, so a partial revert
# (one input re-added, one .env line restored) is RED, not silently inert.
check("B3 dispatch inputs are exactly confirm/dry_run/rollback/rollback_ack_luks_writes/clean_stray (wipe_plaintext and expected_plaintext_volume_id retired)",
      set(inp) == {"confirm", "dry_run", "rollback", "rollback_ack_luks_writes", "clean_stray"}, sorted(inp))
wenv = wf.get("env") or {}
check("B3 workflow env carries no wipe identity constant (PLAINTEXT_VOLUME_*, WEB1_SERVER_*, LUKS_VOLUME_ID retired)",
      set(wenv) == {"INFRA_DIR", "CLOUDFLARED_VERSION", "CLOUDFLARED_SHA256", "WEB_HOST_PRIVATE_IP"}, sorted(wenv))
check("B3 preflight declares no outputs (the wipe's api_state/size_bytes classification is retired)",
      "outputs" not in (jobs.get("preflight") or {}), (jobs.get("preflight") or {}).get("outputs"))
check("B3 no step reads needs.preflight.outputs (nothing is left to read)", "needs.preflight.outputs" not in wf_text)
check("dry_run description no longer describes a wipe rehearsal", "wipe_plaintext" not in str((inp.get("dry_run") or {}).get("description", "")))
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
check("the cutover gate is the ONLY environment: line in the file (the unconditional `wipe` gate is retired)",
      sum(1 for l in wf_text.splitlines() if re.match(r"^\s*environment:", l)) == 1)
if run_step:
    cenv = run_step[0].get("env") or {}
    check("cutover's Run step env carries no CONFIRM_WIPE / PIN / PLAINTEXT_SIZE_BYTES",
          not ({"CONFIRM_WIPE", "PIN", "PLAINTEXT_SIZE_BYTES"} & set(cenv)), sorted(cenv))
    cbody = str(run_step[0].get("run", ""))
    check("cutover's .env writes no CONFIRM_WIPE and no WORKSPACES_PLAINTEXT_* line",
          not re.search(r"printf '(CONFIRM_WIPE|WORKSPACES_PLAINTEXT_[A-Z_]+)=", cbody))
    check("cutover's .env is built one named printf per line (no multi-%s format)", not re.search(r"printf '[^']*%s[^']*%s", cbody))
    check("cutover's ::error:: guidance names the tombstone outcome wipe_retired, never the retired `dry_run mode=wipe`",
          "wipe_retired" in cbody and "mode=wipe" not in cbody)
    # Guard 2's surviving half: DRY_RUN reaches the host as dry_run itself (a hardcoded '0' would turn
    # every ungated rehearsal into a real freeze).
    check("cutover delivers DRY_RUN = inputs.dry_run exactly",
          cenv.get("DRY_RUN") == "${{ inputs.dry_run && '1' || '0' }}", cenv.get("DRY_RUN"))
    open(f"{scratch}/cutover-run.sh", "w").write(cbody)

# The workflow-level env, as the behavioral legs' environment: the stubs run the bodies with the FILE's
# constants, never with values this suite injects.
with open(f"{scratch}/wf-env.txt", "w") as fh:
    for k, v in wenv.items():
        fh.write(f"{k}={v}\n")

# T5 behavioral input: the cutover Run step's env EVALUATED for a dispatch — the `A && 'x' || 'y'`
# expressions evaluated as GitHub does (both treat '' as false, '0' as true).
def gh_eval(expr, inputs, extra):
    m = re.fullmatch(r"\$\{\{\s*(.*?)\s*\}\}", str(expr))
    if not m:
        return str(expr)
    e = m.group(1)
    for k, v in extra.items():
        e = e.replace(k, repr(v))
    e = re.sub(r"inputs\.([a-z_]+)", lambda mm: repr(inputs.get(mm.group(1), "")), e)
    e = e.replace("&&", " and ").replace("||", " or ").replace("!", " not ")
    v = eval(e, {"__builtins__": {}}, {})
    return "" if v is False or v is None else ("true" if v is True else str(v))
if run_step:
    for tag, dry in (("rehearsal", True), ("freeze", False)):
        inputs = {"dry_run": dry, "rollback": False, "rollback_ack_luks_writes": False, "clean_stray": False}
        extra = {"env.WEB_HOST_PRIVATE_IP": str(wenv.get("WEB_HOST_PRIVATE_IP")),
                 "secrets.WORKSPACES_LUKS_BOOT_TOKEN": "dp.st.boot-token-synth", "secrets.DOPPLER_TOKEN": "dp.st.runner-synth"}
        with open(f"{scratch}/cutover-env-{tag}.txt", "w") as fh:
            for k, v in (run_step[0].get("env") or {}).items():
                fh.write(f"{k}={gh_eval(v, inputs, extra)}\n")

# ── #6604 PR B — the operator-facing text tells the truth once the plaintext is retired ──────────
# Guard 5 refuses every rollback once web-1's plaintext volume is gone, so the rollback input must not
# promise a remount, and the ::error:: guidance must name every outcome the host can write.
rb_desc = str((inp.get("rollback") or {}).get("description", ""))
check("rollback input description names the Guard 5 refusal instead of promising a plaintext remount",
      "refused_plaintext_wiped" in rb_desc and "remount the retained plaintext at /mnt/data + restart. Use if" not in rb_desc, rb_desc[:120])
_script_code = "\n".join(l for l in script.splitlines() if not l.lstrip().startswith("#"))
host_outcomes = set(re.findall(r"outcome=([a-z_]+)", _script_code)) | set(re.findall(r"_rollback_refuse\s+\S+\s+([a-z_]+)", _script_code))
check("could derive the host's outcome= vocabulary from workspaces-cutover.sh (>= 12 names)", len(host_outcomes) >= 12, sorted(host_outcomes))
if run_step:
    err = next((l for l in str(run_step[0].get("run", "")).splitlines() if "::error::workspaces-luks cutover exited" in l), "")
    globs = re.findall(r"\b([a-z_]+_)\*", err)
    missing = sorted(o for o in host_outcomes if not re.search(r"(?<![a-z_])" + o + r"(?![a-z_])", err) and not any(o.startswith(g) for g in globs))
    check("the cutover ::error:: outcome list names every outcome= the host script can write (incl. Guard 5's refused_*)", bool(err) and not missing, missing)
summ = [s for s in steps if s.get("name") == "Cutover summary"]
check("the Cutover summary step exists", len(summ) == 1)
if summ:
    open(f"{scratch}/summary.sh", "w").write(str(summ[0].get("run", "")))

for v in verdicts:
    print("\t".join(v))
PY

while IFS=$'\t' read -r verdict name detail; do
  [[ -n "${verdict:-}" ]] || continue
  if [[ "$verdict" == "ok" ]]; then ok "$name"; else no "$name${detail:+ ($detail)}"; fi
done < "$SCRATCH/verdicts.tsv"

# Guard B3 — the census scanned EVERY step. Pinned exactly, against an independent count of the
# file's step keys (one `run:` or `uses:` per step), so a census that skips a job or a step is RED.
B3_STEPS=15
b3_indep="$(grep -cE '^[[:space:]]+(- )?(run|uses):' "$WF" || true)"
b3_scanned="$(cat "$SCRATCH/census-steps.txt" 2>/dev/null || echo 0)"
if [[ "$b3_scanned" == "$b3_indep" && "$b3_indep" == "$B3_STEPS" ]]; then
  ok "B3 census scanned every step: ${b3_scanned} == independent run:/uses: count ${b3_indep} == pinned ${B3_STEPS}"
else
  no "B3 census step count drifted: scanned=${b3_scanned} independent=${b3_indep} pinned=${B3_STEPS}"
fi

# The workflow-level env: the bodies run with the FILE's constants (INFRA_DIR, the bridge pins, the
# web-1 address), never with values this suite injects — a typo in the workflow then fails here.
WF_ENV=()
while IFS= read -r l; do [[ -n "$l" ]] && WF_ENV+=("$l"); done < "$SCRATCH/wf-env.txt"
[[ "${#WF_ENV[@]}" -ge 4 ]] || no "INSTRUMENT: the workflow env could not be read from the YAML (${#WF_ENV[@]} vars)"

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


# --- #6604 PR B — the retired wipe token authorizes nothing ---------------------------------------
# The pre-gate ran under GitHub's own `bash --noprofile --norc -eo pipefail`, with the FILE's env.
if [[ -f "$SCRATCH/pregate.sh" ]]; then
  gate_out() {  # <confirm> <dry> <rollback> <clean_stray> [ack]
    local rc=0 out
    out="$(env "${WF_ENV[@]}" CONFIRM="$1" DRY="$2" ROLLBACK_IN="$3" CLEAN_STRAY_IN="$4" ACK_IN="${5:-false}" \
      bash --noprofile --norc -eo pipefail "$SCRATCH/pregate.sh" 2>&1)" || rc=$?
    printf '%s|%s' "$rc" "$out"
  }
  WTOK="WIPE-PLAINTEXT-USER-DATA-AP-009"
  [[ "$(gate_out "$WTOK" true false false)" != 0\|* ]] \
    && ok "the retired wipe token is refused on a rehearsal dispatch" || no "the retired wipe token authorized a rehearsal"
  [[ "$(gate_out "$WTOK" false false false)" != 0\|* ]] \
    && ok "the retired wipe token is refused on a real-freeze dispatch" || no "the retired wipe token authorized a freeze"
  [[ "$(gate_out "CUTOVER-WORKSPACES-LUKS" true false false)" == 0\|* ]] \
    && ok "POSITIVE CONTROL: an ordinary rehearsal passes under GitHub's own shell flags and the file's env" \
    || no "the ordinary rehearsal broke under GitHub's shell flags: $(gate_out "CUTOVER-WORKSPACES-LUKS" true false false | cut -c1-160)"
fi

# ============================================================================================
# Behavioral leg for the cutover Run step: the EXTRACTED body runs under GitHub's own
# `bash --noprofile --norc -eo pipefail`, against recording stubs on PATH. The curl stub prints what
# `-w '%{http_code}'` prints and — like real curl — exits 22 under -f on a >=400.
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
cat > "$BIN/ssh-stub" <<'STUB'
#!/usr/bin/env bash
cmd="${*: -1}"
printf 'ssh %s\n' "$*" >> "$SSH_LOG"
case "$cmd" in
  *"mktemp -d"*) printf '%s\n' "${SSH_MKTEMP_OUT-/var/lib/workspaces-luks/wl-cutover.TESTAB}" ;;
  *"tar xzf"*) cat > /dev/null; exit "${SSH_UPLOAD_RC:-0}" ;;
  *"workspaces-cutover.sh"*) cat > "$SSH_ENV_CAPTURE"; exit "${SSH_RC:-0}" ;;
  *) : ;;
esac
exit 0
STUB
printf '#!/usr/bin/env bash\nprintf "doppler %%s\\n" "$*" >> "${DOPPLER_LOG:-/dev/null}"\ncase "$*" in *HCLOUD_TOKEN_READONLY*) printf "%%s" "${RO_TOKEN-}"; [ -n "${RO_TOKEN-}" ] ;; *HCLOUD_TOKEN*) printf "%%s" "${RW_TOKEN-rw-token-synth}" ;; *) exit 64 ;; esac\n' > "$BIN/doppler"
chmod +x "$BIN"/*

fx_reset() { rm -rf "$FIX"; mkdir -p "$FIX"; : > "$SCRATCH/curl.log"; : > "$SCRATCH/curl.cfg"; : > "$SCRATCH/ssh.log"; : > "$SCRATCH/env.capture"; }
fx() {  # <METHOD> <path> <seq-index> <code> <body>
  local key; key="$(printf '%s_%s' "$1" "$2" | tr -c 'A-Za-z0-9_\n' '_')"
  printf '%s\n%s' "$4" "$5" > "$FIX/$key.$3"
}
# run_body <file> [VAR=value ...] -> BODY_RC, BODY_OUT (stdout+stderr)
run_body() {
  local f="$1"; shift
  : > "$SCRATCH/gh_output"; : > "$SCRATCH/gh_summary"; : > "$SCRATCH/gh_env"
  BODY_RC=0
  BODY_OUT="$(env PATH="$BIN:$PATH" CURL_LOG="$SCRATCH/curl.log" CURL_CFG="$SCRATCH/curl.cfg" FIX="$FIX" \
    SSH_LOG="$SCRATCH/ssh.log" SSH_ENV_CAPTURE="$SCRATCH/env.capture" \
    GITHUB_OUTPUT="$SCRATCH/gh_output" GITHUB_STEP_SUMMARY="$SCRATCH/gh_summary" GITHUB_ENV="$SCRATCH/gh_env" \
    GITHUB_REPOSITORY="jikig-ai/soleur" "${WF_ENV[@]}" \
    "$@" bash --noprofile --norc -eo pipefail "$f" 2>&1)" || BODY_RC=$?
}
writes() { grep -cE '^(POST|PUT|DELETE|PATCH) ' "$SCRATCH/curl.log" || true; }
fx_luks() { fx GET "/volumes?name=soleur-web-platform-data-luks" 0 200 '{"volumes":[{"id":106443278,"name":"soleur-web-platform-data-luks"}]}'; }

# --- T5 — the cutover job's delivery body, EXECUTED with the step env EVALUATED from the YAML ---------
if [[ -f "$SCRATCH/cutover-run.sh" && -f "$SCRATCH/cutover-env-rehearsal.txt" && -f "$SCRATCH/cutover-env-freeze.txt" ]]; then
  CENV=(); FENV=()
  while IFS= read -r l; do [[ -n "$l" ]] && CENV+=("$l"); done < "$SCRATCH/cutover-env-rehearsal.txt"
  while IFS= read -r l; do [[ -n "$l" ]] && FENV+=("$l"); done < "$SCRATCH/cutover-env-freeze.txt"
  RUN_ARGS=(WEB_HOST_SSH="$BIN/ssh-stub" RO_TOKEN=ro-token-synth)
  WANT_KEYS="DOPPLER_TOKEN WORKSPACES_LUKS_DEV ROLLBACK ROLLBACK_ACK_LUKS_WRITES CLEAN_STRAY DRY_RUN "
  fx_reset; fx_luks
  run_body "$SCRATCH/cutover-run.sh" "${CENV[@]}" "${RUN_ARGS[@]}"
  if [[ "$BODY_RC" == 0 ]] && [[ "$(cut -d= -f1 "$SCRATCH/env.capture" | tr '\n' ' ')" == "$WANT_KEYS" ]] \
    && grep -qx 'DRY_RUN=1' "$SCRATCH/env.capture" && grep -qx 'WORKSPACES_LUKS_DEV=/dev/disk/by-id/scsi-0HC_Volume_106443278' "$SCRATCH/env.capture" \
    && [[ "$(cat "$SCRATCH/gh_env")" == "REMOTE_DIR=/var/lib/workspaces-luks/wl-cutover.TESTAB" ]]; then
    ok "T5 the EXECUTED rehearsal delivery (env evaluated from the YAML) sends exactly the six .env keys, DRY_RUN=1 last — no CONFIRM_WIPE, no WORKSPACES_PLAINTEXT_*"
  else
    no "T5 the rehearsal delivery is wrong (rc=$BODY_RC keys=[$(cut -d= -f1 "$SCRATCH/env.capture" | tr '\n' ' ')]) ${BODY_OUT:0:240}"
  fi
  [[ "$(writes)" == 0 && "$(grep -c '^GET /volumes?name=soleur-web-platform-data-luks$' "$SCRATCH/curl.log")" == 1 ]] \
    && ok "B3 H1 (executed): the cutover body's only Hetzner call is ONE read-only GET of the LUKS volume by name" \
    || no "B3 H1 (executed): the cutover body made a Hetzner write or an unexpected call: $(tr '\n' '|' < "$SCRATCH/curl.log")"
  fx_reset; fx_luks
  run_body "$SCRATCH/cutover-run.sh" "${FENV[@]}" "${RUN_ARGS[@]}"
  [[ "$BODY_RC" == 0 && "$(tail -n 1 "$SCRATCH/env.capture")" == "DRY_RUN=0" && "$(writes)" == 0 ]] \
    && ok "T5b the EXECUTED real-freeze delivery (dry_run=false evaluated from the YAML) sends DRY_RUN=0 and makes no Hetzner write" \
    || no "T5b the freeze delivery is wrong (rc=$BODY_RC tail=[$(tail -n 1 "$SCRATCH/env.capture")]) ${BODY_OUT:0:200}"
  # The cutover job's delivery guards (S1, S3, F8), executed.
  fx_reset; fx_luks
  run_body "$SCRATCH/cutover-run.sh" "${CENV[@]}" "${RUN_ARGS[@]}" SSH_MKTEMP_OUT=$'/var/lib/workspaces-luks/wl-cutover.TESTAB\nBASH_ENV=$(echo INJECTED >&2)'
  [[ "$BODY_RC" != 0 && ! -s "$SCRATCH/gh_env" && ! -s "$SCRATCH/env.capture" ]] && ok "T5-S1 the cutover job refuses a multi-line REMOTE_DIR before it reaches GITHUB_ENV" \
    || no "T5-S1 the cutover job wrote a multi-line REMOTE_DIR (rc=$BODY_RC env=[$(head -c 120 "$SCRATCH/gh_env")])"
  fx_reset; fx_luks
  run_body "$SCRATCH/cutover-run.sh" "${CENV[@]/#WORKSPACES_LUKS_BOOT_TOKEN=*/WORKSPACES_LUKS_BOOT_TOKEN=dp.st.x\$(id)}" "${RUN_ARGS[@]}"
  [[ "$BODY_RC" != 0 && ! -s "$SCRATCH/env.capture" ]] && ok "T5-S3 the cutover job refuses a boot token with shell metacharacters before the .env is delivered" \
    || no "T5-S3 a metacharacter boot token was delivered by the cutover job (rc=$BODY_RC)"
  fx_reset; fx_luks
  run_body "$SCRATCH/cutover-run.sh" "${CENV[@]}" "${RUN_ARGS[@]}" SSH_UPLOAD_RC=1
  [[ "$BODY_RC" != 0 && ! -s "$SCRATCH/env.capture" && "$BODY_OUT" == *"bundle upload to web-1 failed"* ]] \
    && ok "T5-F8 the cutover job stops on a failed bundle upload ('nothing ran') before the main ssh" \
    || no "T5-F8 a failed upload went on in the cutover job (rc=$BODY_RC)"
  fx_reset; fx_luks
  run_body "$SCRATCH/cutover-run.sh" "${CENV[@]}" "${RUN_ARGS[@]}" SSH_RC=3
  [[ "$BODY_RC" == 3 && "$BODY_OUT" == *"::error::workspaces-luks cutover exited 3"* ]] \
    && ok "T5-RC a host failure surfaces the ssh rc unchanged with the outcome-row guidance" \
    || no "T5-RC the host rc was lost (rc=$BODY_RC) ${BODY_OUT:0:160}"
else
  no "T5 the cutover Run body or its evaluated env was not extracted — the delivery was not executed"
fi

# --- the Cutover summary reports the OUTCOME of a rollback, not the mode's intent -------------------
# Guard 5 refuses every rollback once the plaintext is retired; a summary keyed on the mode alone
# printed "remounted the retained plaintext" over that refusal. EXECUTED under GitHub's shell flags.
summary_of() {  # <job_status> -> the summary text a rollback dispatch writes
  : > "$SCRATCH/gh_summary"
  env ACTOR=synth DRY=true ROLLBACK_IN=true ACK_IN=false CLEAN_STRAY_IN=false JOB_STATUS="$1" RUN_URL=https://example.invalid/run \
    GITHUB_STEP_SUMMARY="$SCRATCH/gh_summary" bash --noprofile --norc -eo pipefail "$SCRATCH/summary.sh" >/dev/null 2>&1 || true
  cat "$SCRATCH/gh_summary"
}
if [[ -f "$SCRATCH/summary.sh" ]]; then
  s_fail="$(summary_of failure)"; s_ok="$(summary_of success)"
  [[ -n "$s_fail" && "$s_fail" != *remounted* && "$s_fail" == *"NOT completed"* && "$s_fail" == *refused_plaintext_wiped* ]] \
    && ok "the summary of a FAILED rollback says it did not complete and names the Guard 5 outcomes — never 'remounted'" \
    || no "the summary of a failed rollback misreports it: $(grep -m1 'Mode' <<<"$s_fail")"
  [[ "$s_ok" == *"Mode:** ROLLBACK"* && "$s_ok" == *rolled_back* && "$s_ok" != *"NOT completed"* ]] \
    && ok "the summary of a SUCCESSFUL rollback reports outcome=rolled_back" \
    || no "the summary of a successful rollback misreports it: $(grep -m1 'Mode' <<<"$s_ok")"
else
  no "the Cutover summary step body was not extracted — its rollback reporting is unverified"
fi

printf '\n%s passed, %s failed\n' "$pass" "$fail"

# NON-DEGENERACY FLOOR — see the sibling rationale in workspaces-luks-staging.test.sh. A python
# leg that dies before emitting verdicts, or a `check()` block deleted wholesale, would otherwise
# leave this suite reporting "0 passed, 0 failed" and exiting 0. The floor (WF_MIN_ASSERTIONS, 107) is
# a literal on the `if` itself and is reported by printf + exit 1, never through ok()/no(), so a
# neutered helper cannot silence the check that exists to notice it.
if [[ "$pass" -lt 107 ]]; then
  printf 'FAIL - WF_MIN_ASSERTIONS: only %s assertions passed (floor 107) — the structural leg produced fewer verdicts than expected; a green run here would be vacuous\n' "$pass"
  exit 1
fi
[[ "$fail" -eq 0 ]] || exit 1
