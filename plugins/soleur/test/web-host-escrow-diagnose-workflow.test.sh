#!/usr/bin/env bash
# web-host-escrow-diagnose-workflow.test.sh -- shape + behaviour gate for
# .github/workflows/web-host-escrow-diagnose.yml, the dispatch-only, read-only diagnostic that runs the web-host escrow
# readiness check (`scripts/web-host-escrow-preflight.sh`) in CI so nobody has to run it by hand (#9377 C8, #9461).
#
# THE PROPERTIES UNDER TEST (plan Guard 1 and Guard 2):
#   G1. The workflow can never run Terraform, write to Doppler, GitHub or any store, widen its token beyond the loader's
#       export, or hand the provider token to anything but the preflight's environment. Asserted over every structural
#       channel by PARSING the YAML (a grep would match the prose), and each channel is mutated on a scratch copy to show
#       the analyzer goes red for the right reason.
#   G2. The job summary carries only scrubbed checker lines and a verdict that is a pure function of the preflight's exit
#       code plus the presence of the exact `live-ok` line. The extracted step body is EXECUTED under the shell GitHub gives
#       a `run:` step with no `shell:` key (`bash -e {0}`; the body sets pipefail itself) against the REAL preflight and the
#       REAL checker, on a PATH that holds only the tools they need, behind a Doppler stub that
#       refuses anything the check must not call (a stub of the preflight itself would prove the plan's spelling, not the
#       tool's contract: learning 2026-09-21-my-escrow-suite-stubbed-the-one-tool-that-would-have-refused-it.md).
#
# WHAT G1 ESTABLISHES, HONESTLY. A list of bad spellings is not a capability boundary (two review rounds each found a new
# spelling past it), so the check step's normalised body is PINNED by hash (S16): any edit to what the step runs, in any
# spelling, reds this suite and has to be re-pinned in the same diff, where a reviewer sees it. The S8-S10 word and regex nets
# stay as readable diagnostics for the OTHER steps and for the message a failing edit prints. The pin makes a change VISIBLE;
# it is not an integrity control, because one pull request can change the workflow and this suite together and no ruleset
# requires a review (ADR-241 D2 note).
#
# Every token here is a synthetic string (cq-test-fixtures-synthesized-only). The workflow is NEVER dispatched by this
# suite or by the PR that adds it.
#
# Run: bash plugins/soleur/test/web-host-escrow-diagnose-workflow.test.sh
# Registered by the plugins/soleur/test/*.test.sh glob in scripts/test-all.sh (presence is registration).
export TMPDIR="${TMPDIR:-/var/tmp}"
set -uo pipefail

SELF="${BASH_SOURCE[0]}"
SCRIPT_DIR="$(cd "$(dirname "$SELF")" && pwd)"
REPO="${DIAG_REPO_ROOT:-$(cd "$SCRIPT_DIR/../../.." && pwd)}"
WF="${DIAG_WF:-$REPO/.github/workflows/web-host-escrow-diagnose.yml}"
BIRTH="$REPO/knowledge-base/engineering/operations/runbooks/web-host-birth.md"
REPLACE="$REPO/knowledge-base/engineering/operations/runbooks/web-host-replace.md"

passes=0
fails=0
# S16: sha256 of the check step's normalised run body. A legitimate edit to the step changes this value: run the suite, copy the
# hash S16 prints, and say in the commit why the step changed.
BODY_PIN="136667fd44c33f2bb67d9f5be205f2119c8ae7eea7203325e038ae4c52909e31"
ok() { passes=$((passes + 1)); echo "[ok] $1"; }
no() { fails=$((fails + 1)); echo "[FAIL] $1" >&2; }

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

# --- INSTRUMENT SELF-TEST (ok/no own every verdict; drive both and require both counters to move) --------------------
selftest_ok_no() {
  local p0=$passes f0=$fails
  { ok "self-test"; no "self-test"; } >/dev/null 2>&1
  if [[ "$passes" -ne $((p0 + 1)) || "$fails" -ne $((f0 + 1)) ]]; then
    printf '[FATAL] instrument self-test: ok()/no() did not move their counters\n' >&2
    exit 2
  fi
  passes=$p0; fails=$f0
}
selftest_ok_no

# --- H3: the workflow must EXIST. A suite that finds nothing to check must be RED, never "0 checked, pass" -------------
if [[ ! -f "$WF" ]]; then
  printf '[FAIL] workflow-missing: %s does not exist (RED until the diagnostic workflow is added)\n' "$WF" >&2
  exit 1
fi

python3 -c 'import yaml' 2>/dev/null || { printf '[FATAL] INSTRUMENT: PyYAML is required\n' >&2; exit 2; }

SCR="$(mktemp -d "$TMPDIR/escrow-diagnose.XXXXXXXX")" || { echo "mktemp failed" >&2; exit 2; }
assert_fixture_dir "$SCR"
trap 'rm -rf "${SCR:?}"' EXIT INT TERM HUP
mkdir -p "$SCR/mut" "$SCR/stubbin" "$SCR/mock" "$SCR/home" "$SCR/root_real/scripts" "$SCR/root_fake/scripts"

# file_has / file_lacks own the "present" and "absent" verdicts of the rows below. Absence needs grep rc == 1 EXACTLY: rc 2 is
# an unreadable or missing file, which says nothing about absence and must FAIL.
file_has()   { grep -qF -- "$2" "$1"; }
file_lacks() { local r; grep -qF -- "$2" "$1"; r=$?; [[ "$r" -eq 1 ]]; }
_st="$SCR/selftest.txt"; _st_bad=""
printf 'alpha\nbeta\n' > "$_st"
file_has "$_st" "alpha"              || _st_bad+=" file_has(present)"
file_has "$_st" "gamma"              && _st_bad+=" file_has(absent)-must-fail"
file_lacks "$_st" "gamma"            || _st_bad+=" file_lacks(absent)"
file_lacks "$_st" "alpha"            && _st_bad+=" file_lacks(present)-must-fail"
file_lacks "$SCR/no-such.txt" "x" 2>/dev/null && _st_bad+=" file_lacks(unreadable)-must-fail"
if [[ -n "$_st_bad" ]]; then
  printf '[FATAL] instrument self-test: file helper(s) gave the wrong verdict:%s\n' "$_st_bad" >&2
  exit 2
fi

# =====================================================================================================================
# GUARD 1 -- structural analysis of the YAML (parsed), then the same analysis over mutated copies
# =====================================================================================================================
cat > "$SCR/analyze.py" <<'PY'
import hashlib, os, re, sys, yaml

path, bodyout = sys.argv[1], sys.argv[2]
text = open(path).read()

class _NoDupLoader(yaml.SafeLoader):
    pass

def _no_dup(loader, node, deep=False):
    seen = set()
    for k, _v in node.value:
        key = loader.construct_object(k, deep=deep)
        if key in seen:
            raise yaml.constructor.ConstructorError(None, None, "duplicate key %r" % (key,), k.start_mark)
        seen.add(key)
    return yaml.SafeLoader.construct_mapping(loader, node, deep)

_NoDupLoader.add_constructor(yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG, _no_dup)
try:
    wf = yaml.load(text, Loader=_NoDupLoader)
except Exception as e:  # a workflow that does not parse (or repeats a key) is a RED, not a skip
    print("S0\tFAIL\tthe workflow parses as YAML\t%s" % str(e)[:120].replace("\t", " ").replace("\n", " "))
    sys.exit(0)
wf = wf if isinstance(wf, dict) else {}
rows = []

def chk(i, name, cond, detail=""):
    rows.append((i, "ok" if cond else "FAIL", name, str(detail)[:150].replace("\t", " ").replace("\n", " ")))

on = wf.get(True, wf.get("on"))
if isinstance(on, str):
    on = {on: None}
elif isinstance(on, list):
    on = {k: None for k in on}
on = on if isinstance(on, dict) else {}
wd = on.get("workflow_dispatch")
chk("S1", "triggers are exactly workflow_dispatch with no inputs",
    set(on) == {"workflow_dispatch"} and not (isinstance(wd, dict) and wd.get("inputs")), sorted(on))
RO = {"contents": "read"}
jobs = wf.get("jobs") or {}
chk("S2", "effective permissions are exactly contents: read (workflow level, and any job level block)",
    wf.get("permissions") == RO and all(("permissions" not in j) or j["permissions"] == RO for j in jobs.values()),
    [wf.get("permissions")] + [j.get("permissions") for j in jobs.values()])
chk("S3", "exactly one job", len(jobs) == 1, list(jobs))
job = next(iter(jobs.values())) if jobs else {}
chk("S4", "the job's environment is infra-privileged", job.get("environment") == "infra-privileged", job.get("environment"))
steps = job.get("steps") or []

LOADER = "./.github/actions/infra-credentials"
loaders = [s for s in steps if str(s.get("uses", "")).startswith("./")]
chk("S5", "the loader step passes ONLY doppler-token-infra-privileged (no legacy token, no app-token opt-in)",
    len(loaders) == 1 and loaders[0].get("uses") == LOADER
    and loaders[0].get("with") == {"doppler-token-infra-privileged": "${{ secrets.DOPPLER_TOKEN_INFRA_PRIVILEGED }}"},
    [s.get("with") for s in loaders])
checkouts = [s for s in steps if str(s.get("uses", "")).startswith("actions/checkout@")]
uses_ok = all(
    str(s["uses"]).startswith("./") or str(s["uses"]) == "actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5"
    for s in steps if "uses" in s
)
chk("S6", "one SHA-pinned checkout with persist-credentials: false, and no other action",
    len(checkouts) == 1 and uses_ok and checkouts[0].get("with") == {"persist-credentials": False},
    [s.get("uses") for s in steps if "uses" in s])

def strip_comments(body):
    return "\n".join(l for l in str(body).splitlines() if not l.lstrip().startswith("#"))

runs = [str(s["run"]) for s in steps if "run" in s]
code = "\n".join(strip_comments(r) for r in runs)
PREFLIGHT = "bash scripts/web-host-escrow-preflight.sh"
pf = [i for i, s in enumerate(steps) if PREFLIGHT in strip_comments(s.get("run", ""))]
ic = next((i for i, s in enumerate(steps) if str(s.get("uses", "")).startswith("actions/checkout@")), -1)
il = next((i for i, s in enumerate(steps) if s.get("uses") == LOADER), -1)
chk("S7", "exactly one step runs the preflight, after the checkout and the loader",
    len(pf) == 1 and ic != -1 and il != -1 and ic < il < pf[0], (ic, il, pf))
# A denylist of spellings is not a capability boundary (an unlisted interpreter, encoder or copier passes it), so this is the
# wide net; the PATH-restricted execution below (c_* cases, no-foreign-command-*) is the capability check.
BAN = re.compile(r"(?<![A-Za-z0-9_.-])(terraform|tofu|doppler|gh|curl|wget|aws|ssh|scp|rsync|git|tee|python|python3|node|perl|ruby|php|lua|nc|ncat|socat|nslookup|dig|host|openssl|hcloud|docker|npm|npx|jq|rev|base64|base32|xxd|od|hexdump|printenv|env|eval|exec|source|cp|mv|dd|install|touch|ln|xargs|find|sh|zsh|dash|ksh|busybox|sudo|tar|zip|nohup|setsid|strace|mkfifo|truncate|mkdir|chmod|awk|sort)(?![A-Za-z0-9_-])")
hit = BAN.search(code)
bashes = re.findall(r"(?<![A-Za-z0-9_.-])bash(?![A-Za-z0-9_-])[^\n]*", code)
only_pf = len(bashes) == 1 and bashes[0].strip() == "bash scripts/web-host-escrow-preflight.sh 2>&1"
chk("S8", "no write-capable, interpreter, network or encoder command appears in any run body, and `bash` runs only the preflight",
    hit is None and only_pf, (hit.group(0) if hit else "") or bashes)
SINK = re.compile(r"GITHUB_ENV|GITHUB_OUTPUT|GITHUB_PATH|GITHUB_STATE|upload-artifact|actions/cache")
text_nc = strip_comments(text)
redirects = [m.group(2) for m in re.finditer(r"(\d*)>>?\|?\s*(&\d|&[^\s;|&)]+|[^\s;|&)]+)", code)]
bad_redirects = [t for t in redirects if t not in ("&1", "/dev/null", '"$GITHUB_STEP_SUMMARY"')]
summary_refs = code.count("GITHUB_STEP_SUMMARY")
chk("S9", "nothing persists a value: no GITHUB_ENV/OUTPUT/PATH write, no artifact or cache, only allow-listed redirects, exactly one summary writer",
    SINK.search(code) is None and SINK.search(text_nc) is None and not bad_redirects and summary_refs == 1
    and "/dev/tcp" not in code and "/dev/udp" not in code,
    (SINK.search(code) or SINK.search(text_nc) or "", bad_redirects, summary_refs))
# The provider token's NAME may appear exactly once in a run body: in the allowlist `case` pattern. Anywhere else (an expansion,
# an indirect read such as printenv/`${!x}`/compgen -v/declare -p/set, a /proc read) is a way for the value to reach a sink.
TOKNAME = re.compile(r"TF_VAR_doppler_token_tf|DOPPLER_TOKEN|doppler_token", re.I)
tok_lines = [l for l in code.splitlines() if TOKNAME.search(l)]
tok_ok = all(l.lstrip().startswith("case ") and "unset" in l for l in tok_lines) and len(tok_lines) <= 1
INDIRECT = re.compile(r"\$\{!|compgen\s+-[vA]|declare\s+-(?!Fx\b)[A-Za-z]*[pPxn]|typeset|(?:^|[;&|(])\s*(?:export|readonly)\b|(?:^|[;&|(])\s*set\s*(?:$|[;&|)])|/proc/|(?i:environ)|/dev/(?:tcp|udp)", re.M)
ind = INDIRECT.search(code)
chk("S10", "the provider token's name appears only in the allowlist pattern, and no run body reads the environment indirectly",
    tok_ok and ind is None, (tok_lines[:2], ind.group(0) if ind else ""))
chk("S11", "no ${{ }} expression is interpolated into a run body or a step name (the shell reads only its own environment)",
    all("${{" not in r for r in runs) and all("${{" not in str(s.get("name", "")) for s in steps), [r[:40] for r in runs if "${{" in r])
tm = job.get("timeout-minutes")
chk("S12", "the job carries a timeout-minutes of at most 15", isinstance(tm, int) and 0 < tm <= 15, tm)
BADKEYS = {"if", "continue-on-error", "shell", "working-directory", "env"}
chk("S13", "nothing is conditional, advisory, re-shelled or step-env'd, there is no concurrency/defaults/workflow env, the job keys are exactly environment/runs-on/timeout-minutes/steps on ubuntu-24.04, and a step carries only name/uses/with/run",
    set(job) == {"environment", "runs-on", "timeout-minutes", "steps"} and job.get("runs-on") == "ubuntu-24.04"
    and all(set(s) <= {"name", "uses", "with", "run"} for s in steps)
    and not any(k in s for s in steps for k in BADKEYS)
    and not any(k in job for k in ("if", "continue-on-error", "concurrency", "defaults", "env", "services", "container"))
    and not any(k in wf for k in ("concurrency", "defaults", "env")),
    [k for s in steps for k in BADKEYS if k in s])
trues = [l for l in code.splitlines() if "|| true" in l]
chk("S14", "`|| true` guards only the unset loop and the no-match grep (at most two lines)",
    len(trues) <= 2 and all(("unset " in l) or ("grep -E" in l) for l in trues), trues)
body = str(steps[pf[0]].get("run", "")) if len(pf) == 1 else ""
lines = [l for l in strip_comments(body).splitlines() if l.strip()]
chk("S15", "the check step captures the preflight rc with `|| rc=$?`, requires the exact live-ok line, and ends in exit \"$rc\"",
    bool(lines) and lines[-1].strip() == 'exit "$rc"' and "rc=0" in body and len(re.findall(r"\|\| rc=\$\?", body)) == 1
    and "escrow-split-contract:live-ok" in body, lines[-1:] if lines else "")
# S16: the check step's normalised body (comments and blank lines dropped, trailing blanks trimmed) is pinned by hash. Every
# word-list net above can be walked around by a new spelling; this cannot, because ANY edit to what the step runs moves it.
_prev = ""
_kept = []
for _l in str(body).splitlines():
    # a `#` line is a comment unless it continues a `\`-ended line (then it is part of the command)
    if _l.lstrip().startswith("#") and not _prev.rstrip(" \t").endswith("\\"):
        continue
    if _l.strip():
        _kept.append(_l.rstrip(" \t"))
    _prev = _l
norm = "\n".join(_kept)
got = hashlib.sha256(norm.encode()).hexdigest()
chk("S16", "the check step's normalised body equals its pin (re-pin BODY_PIN in this suite, in the same diff, after review)",
    got == os.environ.get("BODY_PIN", ""), "got " + got)
others = [str(s["run"]).strip() for i, s in enumerate(steps) if "run" in s and i not in pf]
chk("S17", "every other run step is a no-op (`true` or `:`)", all(o in ("true", ":") for o in others), others)
open(bodyout, "w").write(body)
for r in rows:
    print("\t".join(r))
PY

analyze() { # <workflow path> <body out>  -> TSV on stdout: id, ok|FAIL, name, detail
  BODY_PIN="$BODY_PIN" python3 "$SCR/analyze.py" "$1" "$2"
}
analyze "$WF" "$SCR/body.sh" > "$SCR/real.tsv" || { echo "[FATAL] INSTRUMENT: the analyzer crashed on the real workflow" >&2; exit 2; }
n_rows=$(wc -l < "$SCR/real.tsv")
[[ "$n_rows" -ge 15 ]] || { printf '[FATAL] INSTRUMENT: the analyzer produced %s rows on the real workflow (want >= 15)\n' "$n_rows" >&2; exit 2; }
while IFS=$'\t' read -r id verdict name detail; do
  [[ -n "${id:-}" ]] || continue
  if [[ "$verdict" == ok ]]; then ok "$id $name"; else no "$id $name (${detail:-})"; fi
done < "$SCR/real.tsv"
[[ -s "$SCR/body.sh" ]] || { echo "[FATAL] INSTRUMENT: no check-step body could be extracted" >&2; exit 2; }
BODY="$SCR/body.sh"

# mutate_wf <name> <python code operating on the workflow text `s`>: writes $SCR/mut/<name>.yml, rc 3 when the edit did not land.
mutate_wf() {
  python3 - "$WF" "$SCR/mut/$1.yml" "$2" <<'PY'
import sys
src, dst, code = sys.argv[1:4]
ns = {"s": open(src).read()}
before = ns["s"]
exec(code, ns)
if ns["s"] == before:
    sys.exit(3)
open(dst, "w").write(ns["s"])
PY
}
# expect_red <name> <analyzer id that must go FAIL> <python>: the mutation LANDED and the analyzer reds on that id.
expect_red() {
  local name="$1" want="$2" code="$3" rc=0
  mutate_wf "$name" "$code" || rc=$?
  if [[ "$rc" -ne 0 ]]; then no "mutation $name did not land (rc=$rc): the scratch edit changed nothing, so its row would measure the baseline"; return; fi
  analyze "$SCR/mut/$name.yml" "$SCR/mut/$name.body" > "$SCR/mut/$name.tsv" || { no "mutation $name: the analyzer crashed"; return; }
  if grep -q "^${want}"$'\t'"FAIL" "$SCR/mut/$name.tsv"; then ok "G1 mutation $name -> $want goes RED"; else no "G1 mutation $name -> $want stayed green"; fi
}
expect_red m1a-workflow-issues-write S2 "s = s.replace('permissions:\n  contents: read\n', 'permissions:\n  contents: read\n  issues: write\n', 1)"
expect_red m1b-job-issues-write S2 "s = s.replace('    timeout-minutes: 10\n', '    timeout-minutes: 10\n    permissions:\n      contents: read\n      issues: write\n', 1)"
expect_red m2-second-job S3 "s += '  second:\n    runs-on: ubuntu-24.04\n    steps:\n      - run: echo hi\n'"
expect_red m3a-schedule S1 "s = s.replace('on:\n  workflow_dispatch:\n', 'on:\n  schedule:\n    - cron: \"0 6 * * *\"\n  workflow_dispatch:\n', 1)"
expect_red m3b-pull-request S1 "s = s.replace('on:\n  workflow_dispatch:\n', 'on:\n  pull_request:\n  workflow_dispatch:\n', 1)"
expect_red m3c-dispatch-input S1 "s = s.replace('  workflow_dispatch:\n', '  workflow_dispatch:\n    inputs:\n      host:\n        required: false\n', 1)"
expect_red m4a-legacy-token S5 "a = '          doppler-token-infra-privileged: \${{ secrets.DOPPLER_TOKEN_INFRA_PRIVILEGED }}\n'; s = s.replace(a, a + '          doppler-token-legacy: \${{ secrets.DOPPLER_TOKEN }}\n', 1)"
expect_red m4b-app-token S5 "a = '          doppler-token-infra-privileged: \${{ secrets.DOPPLER_TOKEN_INFRA_PRIVILEGED }}\n'; s = s.replace(a, a + '          github-app-runtime-token: true\n', 1)"
expect_red m5a-terraform S8 "a = '          set -uo pipefail\n'; s = s.replace(a, a + '          terraform plan -input=false\n', 1)"
expect_red m5b-doppler-write S8 "a = '          set -uo pipefail\n'; s = s.replace(a, a + '          doppler secrets set SYNTH_KEY synth-value\n', 1)"
expect_red m5c-gh-api-post S8 "a = '          set -uo pipefail\n'; s = s.replace(a, a + '          gh api -X POST repos/o/r/issues\n', 1)"
expect_red m5d-curl-post S8 "a = '          set -uo pipefail\n'; s = s.replace(a, a + '          curl -X POST https://example.invalid/x\n', 1)"
expect_red m6a-github-env S9 "a = '          set -uo pipefail\n'; s = s.replace(a, a + '          echo SYNTH=1 >> \"\$GITHUB_ENV\"\n', 1)"
expect_red m6b-upload-artifact S9 "s += '      - uses: actions/upload-artifact@0000000000000000000000000000000000000000\n        with:\n          name: x\n          path: x\n'"
expect_red m6c-github-output S9 "a = '          set -uo pipefail\n'; s = s.replace(a, a + '          echo v=1 >> \"\$GITHUB_OUTPUT\"\n', 1)"
expect_red m6d-file-redirect S9 "a = '          set -uo pipefail\n'; s = s.replace(a, a + '          echo leak > /var/tmp/leak.txt\n', 1)"
expect_red m7a-token-expansion S10 "a = '          set -uo pipefail\n'; s = s.replace(a, a + '          : \"\${TF_VAR_doppler_token_tf}\"\n', 1)"
expect_red m7b-token-name-expansion S10 "a = '          set -uo pipefail\n'; s = s.replace(a, a + '          : \"\$DOPPLER_TOKEN_TF\"\n', 1)"
expect_red m5e-printenv-rev-to-summary S8 "i = s.rindex('          exit \"\$rc\"\n'); s = s[:i] + '          { printenv TF_VAR_doppler_token_tf || :; } | rev >> \"\$GITHUB_STEP_SUMMARY\"\n' + s[i:]"
expect_red m5f-python-exfil S8 "a = '          set -uo pipefail\n'; s = s.replace(a, a + '          ( python3 -c \"print(1)\" 2>/dev/null ) || :\n', 1)"
expect_red m5g-env-dump S8 "i = s.rindex('          exit \"\$rc\"\n'); s = s[:i] + '          env | cut -c1-40 >> \"\$GITHUB_STEP_SUMMARY\"\n' + s[i:]"
expect_red m5h-other-repo-script S8 "a = '          set -uo pipefail\n'; s = s.replace(a, a + '          bash scripts/check-web-host-escrow-config.sh --static >/dev/null 2>&1\n', 1)"
expect_red m6e-second-summary-writer S9 "i = s.rindex('          exit \"\$rc\"\n'); s = s[:i] + '          echo x >> \"\$GITHUB_STEP_SUMMARY\"\n' + s[i:]"
expect_red m7c-indirect-token-read S10 "a = '          set -uo pipefail\n'; s = s.replace(a, a + '          x=TF_VAR_doppler_token_tf; : \"\${!x}\"\n', 1)"
expect_red m7d-token-name-in-a-pipeline S10 "a = '          set -uo pipefail\n'; s = s.replace(a, a + '          : TF_VAR_doppler_token_tf\n', 1)"
expect_red m12-job-runs-on-self-hosted S13 "s = s.replace('runs-on: ubuntu-24.04', 'runs-on: [self-hosted, linux]', 1)"
expect_red m13-job-outputs S13 "s = s.replace('    timeout-minutes: 10\n', '    timeout-minutes: 10\n    outputs:\n      x: y\n', 1)"
expect_red m14-duplicate-permissions-key S0 "s = s.replace('permissions:\n  contents: read\n', 'permissions:\n  contents: write\npermissions:\n  contents: read\n', 1)"
expect_red m15-environment-production S4 "s = s.replace('environment: infra-privileged', 'environment: production', 1)"
expect_red m16-preflight-twice S7 "a = '      - name: Escrow readiness check (read-only)\n'; s += '      - run: bash scripts/web-host-escrow-preflight.sh\n'"
expect_red m17-timeout-60 S12 "s = s.replace('timeout-minutes: 10', 'timeout-minutes: 60', 1)"
expect_red m18-three-or-true S14 "a = '          set -uo pipefail\n'; s = s.replace(a, a + '          unset FOO || true\n          unset BAR || true\n          unset BAZ || true\n', 1)"
expect_red m19-exit-not-last S15 "i = s.rindex('          exit \"\$rc\"\n'); s = s[:i] + '          exit \"\$rc\"\n          :\n'"
expect_red m20-any-body-edit-moves-the-pin S16 "a = '          set -uo pipefail\n'; s = s.replace(a, a + '          : harmless\n', 1)"
expect_red m21-extra-run-step S17 "s += '      - run: echo hi\n'"
expect_red m22-awk-environ-spaced S10 "a = '          set -uo pipefail\n'; s = s.replace(a, a + '          awk \'BEGIN{for(k in ENVIRON) print k}\'\n', 1)"
expect_red m23-bare-export S10 "a = '          set -uo pipefail\n'; s = s.replace(a, a + '          export\n', 1)"
expect_red m24-redirect-clobber-pipe S9 "i = s.rindex('          exit \"\$rc\"\n'); s = s[:i] + '          printf x >| /var/tmp/leak.txt\n' + s[i:]"
expect_red m25-checkout-sha-swap S6 "s = s.replace('actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5', 'actions/checkout@0000000000000000000000000000000000000001', 1)"
expect_red m9-persist-credentials S6 "s = s.replace('        with:\n          persist-credentials: false\n', '', 1)"
expect_red m10-always-step S13 "a = '      - name: Escrow readiness check (read-only)\n'; s = s.replace(a, a + '        if: always()\n', 1)"
expect_red m11-expression-in-run S11 "a = '          set -uo pipefail\n'; s = s.replace(a, a + '          : \"\${{ github.ref_name }}\"\n', 1)"
# H2 must-PASS, non-canonical: comments reworded (one now mentions a Terraform plan), step names changed, and a no-op step added
# between the checkout and the loader. None of that is behaviour, so every analyzer row must stay green.
rc=0
mutate_wf h2-noncanonical "
import re
s = re.sub(r'^(\s*)# .*\$', r'\1# reworded comment that mentions a terraform plan -out=x', s, flags=re.M)
s = s.replace('name: Load infra credentials (tiered)', 'name: Load credentials', 1)
s = s.replace('          persist-credentials: false\n', '          persist-credentials: false\n      - run: \"true\"\n', 1)
s = s.replace('          set -uo pipefail\n', '          set -uo pipefail\n          # not GITHUB_ENV, and no terraform or printenv here\n', 1)
" || rc=$?
if [[ "$rc" -ne 0 ]]; then
  no "mutation h2-noncanonical did not land (rc=$rc)"
else
  analyze "$SCR/mut/h2-noncanonical.yml" "$SCR/mut/h2.body" > "$SCR/mut/h2.tsv" || no "H2: the analyzer crashed"
  if grep -q $'\tFAIL\t' "$SCR/mut/h2.tsv"; then no "G1 H2 a comment/name/no-op-step edit turned a row red ($(grep -m1 $'\tFAIL\t' "$SCR/mut/h2.tsv" | cut -f1,3))"; else ok "G1 H2 must-PASS: comment, step-name and no-op-step edits keep every row green"; fi
fi

# =====================================================================================================================
# GUARD 2 -- the extracted step body, EXECUTED, against the real preflight and checker behind a Doppler stub
# =====================================================================================================================
ENVTOK="dp.pt.SYNTHenvTOKEN0001aaaa"
# Canary values for the loader-shaped names planted by c_td_tfvar; held in variables so no secret-shaped name=value literal sits on one line.
CANARY_P="SYNTHcanaryTfvar0004"; CANARY_Q="SYNTHcanaryGh0005"; CANARY_R="SYNTHcanaryInfra0006"; CANARY_S="SYNTHcanaryAws0007"
LEAKTOK="dp.pt.SYNTHleakTOKEN0009zzzz"
STDERRTOK="dp.st.SYNTHstderrTOKEN0004dddd"
JWTLIKE="eyJhbGciOiJIUzI1NiJ9.SYNTHbase64payloadSYNTHbase64payload.sigSYNTHsigSYNTH"
SHA="0123456789abcdef0123456789abcdef01234567"
STUB="$SCR/stubbin"; MOCK="$SCR/mock"; HOME_D="$SCR/home"; SUM="$SCR/summary.md"; MOCK_LOG="$SCR/doppler.log"

# The Doppler stub. It models ONLY `secrets --only-names -p P -c C [--no-check-version]` and answers rc 64 to anything else (so
# a `doppler run`, a `secrets get` or a write cannot pass). A listing is granted only to the provider token. It logs argv, which
# kind of token authenticated, and the NAMES of canary variables visible in its environment (never a value). Per-case switches
# come from $HOME/mock.env because the step's allowlist removes every variable but PATH, HOME, TMPDIR, LANG and the one token.
cat > "$STUB/doppler" <<'STUB'
#!/usr/bin/env bash
. "${HOME}/mock.env"
printf 'ARGV %s\n' "$*" >> "$MOCK_LOG"
if [[ "${DOPPLER_TOKEN:-}" == "$MOCK_NAMES_TOK" ]]; then printf 'AUTH provider\n' >> "$MOCK_LOG"; else printf 'AUTH other\n' >> "$MOCK_LOG"; fi
{ compgen -e | grep -E '^(HCLOUD_TOKEN|SENTRY_AUTH_TOKEN|DOPPLER_TOKEN_INFRA_PRIVILEGED|TF_VAR_doppler_token_tf|TF_VAR_hcloud_token|GITHUB_TOKEN|AWS_SECRET_ACCESS_KEY|CANARY_[A-Z_]+)$' | sed 's/^/ENVSEEN /'; } >> "$MOCK_LOG" || true
{ declare -Fx | awk '{print "FNSEEN " $3}'; } >> "$MOCK_LOG" || true
[[ "${1:-}" == secrets ]] || { echo "STUB ERROR: unexpected subcommand '$*'" >&2; exit 64; }
shift
only=0; proj=""; cfg=""
while (($#)); do
  case "$1" in
    --only-names) only=1 ;;
    -p) proj="${2:-}"; shift ;;
    -c) cfg="${2:-}"; shift ;;
    --no-check-version) ;;
    *) echo "STUB ERROR: unexpected argument '$1'" >&2; exit 64 ;;
  esac
  shift
done
[[ "$only" == 1 && "$proj" == soleur && -n "$cfg" ]] || { echo "STUB ERROR: only 'secrets --only-names -p soleur -c <cfg>' is modelled" >&2; exit 64; }
if [[ "${DOPPLER_TOKEN:-}" != "$MOCK_NAMES_TOK" ]]; then
  printf 'Unable to fetch secret names\nDoppler Error: This token does not have access to requested config\n' >&2; exit 1
fi
if [[ -n "${MOCK_UNREADABLE_CFG:-}" && "$cfg" == "$MOCK_UNREADABLE_CFG" ]]; then
  printf 'Unable to fetch secret names\nDoppler Error: Could not find requested config\n' >&2; exit 1
fi
if [[ -n "${MOCK_NAMES_ERR:-}" && "$cfg" == prd_workspaces_luks_web ]]; then
  printf 'Unable to fetch secret names\nDoppler Error: %s\n' "$MOCK_NAMES_ERR" >&2; exit 1
fi
file="$MOCK_DIR/${cfg}.names"
[[ -f "$file" ]] || { printf 'Unable to fetch secret names\nDoppler Error: Could not find requested config\n' >&2; exit 1; }
printf 'NAME\n----\n'; cat "$file"
exit 0
STUB
chmod +x "$STUB/doppler"
# The fake checker (the preflight's sibling in root_fake): lets a row choose the exit code and the exact lines, which the real
# checker cannot be made to print (an unlisted exit code, injection text, a 200-line burst).
cat > "$SCR/root_fake/scripts/check-web-host-escrow-config.sh" <<'FAKE'
#!/usr/bin/env bash
. "${HOME}/mock.env"
printf 'CALLED %s\n' "$*" >> "$MOCK_LOG"
[[ -z "${FAKE_NOISE_FILE:-}" ]] || cat "$FAKE_NOISE_FILE"
[[ -z "${FAKE_HANG:-}" ]] || while :; do :; done
exit "${FAKE_RC:-0}"
FAKE
chmod +x "$SCR/root_fake/scripts/check-web-host-escrow-config.sh"
cp "$REPO/scripts/web-host-escrow-preflight.sh" "$SCR/root_real/scripts/web-host-escrow-preflight.sh"
cp "$REPO/scripts/check-web-host-escrow-config.sh" "$SCR/root_real/scripts/check-web-host-escrow-config.sh"
cp "$REPO/scripts/web-host-escrow-preflight.sh" "$SCR/root_fake/scripts/web-host-escrow-preflight.sh"
ROOT_REAL="$SCR/root_real"; ROOT_FAKE="$SCR/root_fake"

seed_names() {
  printf '%s\n' DOPPLER_PROJECT DOPPLER_ENVIRONMENT DOPPLER_CONFIG WORKSPACES_LUKS_KEY WORKSPACES_HEADER_BUCKET WORKSPACES_HEADER_R2_ENDPOINT WORKSPACES_HEADER_R2_ACCESS_KEY_ID WORKSPACES_HEADER_R2_SECRET_ACCESS_KEY SENTRY_DSN > "$MOCK/prd_workspaces_luks_web.names"
  printf '%s\n' DOPPLER_PROJECT DOPPLER_CONFIG SENTRY_DSN CF_API_TOKEN DATABASE_URL SOME_SECRET > "$MOCK/prd.names"
}
# The step runs on a PATH that holds ONLY the tools the real preflight, checker and stub need (symlinks in $SHIM) plus the
# Doppler stub. A command the workflow adds that is not one of them (python3, printenv, curl, rev, cp, ...) is not found, and a
# BASH_ENV hook (command_not_found_handle) logs its name even when the line redirects stderr and swallows the exit status, so
# a row can refuse it. This is a net over bare-name commands, NOT a boundary: an absolute path, `timeout`/`awk`/`sed` running a
# program of their own, or a branch that only runs when a CI-only variable is set all walk around it. S16 is the pin that
# closes those (any edit to the step's body moves it).
SHIM="$SCR/shim"; NF_LOG="$SCR/notfound.log"; mkdir -p "$SHIM"
for t in bash dirname mktemp tr sed grep head wc awk cat rm cut date timeout; do
  tp="$(type -P "$t" 2>/dev/null)"
  [[ "$tp" == /* ]] || { printf '[FATAL] INSTRUMENT: no executable %s on this machine to put on the step PATH\n' "$t" >&2; exit 2; }
  ln -sf "$tp" "$SHIM/$t"
done
printf 'command_not_found_handle() { printf "%%s\\n" "$1" >> %q; return 127; }\n' "$NF_LOG" > "$SCR/nf.env"
# bcase <root> [VAR=value ...]: run the step body from <root> with a rebuilt environment (env -i, so an ambient token of the
# machine running the suite can never leak into a row). $MOCKCFG (K=V lines) configures the stubs; RC, OUT and $SUM result.
MOCKCFG=""
bcase() {
  local root="$1"; shift
  : > "$SUM"; : > "$MOCK_LOG"; : > "$NF_LOG"
  { printf 'MOCK_LOG=%q\nMOCK_DIR=%q\nMOCK_NAMES_TOK=%q\n' "$MOCK_LOG" "$MOCK" "$ENVTOK"; printf '%s\n' "$MOCKCFG"; } > "$HOME_D/mock.env"
  OUT="$(cd "$root" && /usr/bin/env -i PATH="$STUB:$SHIM" HOME="$HOME_D" TMPDIR="$SCR" LANG=C.UTF-8 BASH_ENV="$SCR/nf.env" \
         GITHUB_STEP_SUMMARY="$SUM" GITHUB_SHA="$SHA" GITHUB_REF_NAME=main GITHUB_ACTOR=synth-actor \
         GITHUB_ACTIONS=true CI=true RUNNER_OS=Linux RUNNER_TEMP="$SCR" GITHUB_EVENT_NAME=workflow_dispatch GITHUB_RUN_ID=1 GITHUB_REPOSITORY=o/r "$@" \
         /usr/bin/bash --noprofile --norc -e "$BODY" 2>&1)"; RC=$?
  bchk "no-foreign-command-in-${FUNCNAME[1]}" "$([[ ! -s "$NF_LOG" ]] && echo 0 || echo 1)"
}
verdict_line() { sed -n '3p' "$SUM"; }
verdict_is() { [[ "$(verdict_line)" == "**$1"* ]]; }
leak_free() { # <token...>: no token byte, nor its reversed, base64 or hex form, in the job log, the summary, or the stub's log
  local t v core rcore hay nz
  for t in "$@"; do
    for v in "$t" "$(printf '%s' "$t" | rev)" "$(printf '%s' "$t" | base64 -w0)" "$(printf '%s' "$t" | od -An -tx1 | tr -d ' \n')"; do
      [[ "$OUT" != *"$v"* ]] || return 1
      file_lacks "$SUM" "$v" || return 1
      file_lacks "$MOCK_LOG" "$v" || return 1
    done
    core="$(printf '%s' "$t" | tr -cd 'A-Za-z0-9')"; rcore="$(printf '%s' "$core" | rev)"
    for hay in "$OUT" "$(cat "$SUM" 2>/dev/null)" "$(cat "$MOCK_LOG" 2>/dev/null)"; do
      nz="$(printf '%s' "$hay" | tr -cd 'A-Za-z0-9')"
      [[ "$nz" != *"$core"* && "$nz" != *"$rcore"* ]] || return 1
    done
  done
  return 0
}

BRES=(); B_EXEC=0
bchk() { # <id> <rc 0 = pass>
  [[ "${2-}" =~ ^[01]$ ]] || { printf '[FATAL] INSTRUMENT: bchk %s was given %q, not 0 or 1 (an empty result must not read as a pass)\n' "$1" "${2-}" >&2; exit 2; }
  B_EXEC=$((B_EXEC + 1))
  if [[ "$2" -eq 0 ]]; then BRES+=("$1"$'\t'ok); else BRES+=("$1"$'\t'FAIL); fi
}
rcz() { if "$@"; then echo 0; else echo 1; fi; }  # run a predicate, print 0/1 (so it can feed bchk without tripping errexit-less pipes)

c_rc0() {
  seed_names; MOCKCFG=""
  bcase "$ROOT_REAL" TF_VAR_doppler_token_tf="$ENVTOK"
  bchk rc0-exit "$([[ "$RC" -eq 0 ]] && echo 0 || echo 1)"
  bchk rc0-verdict "$(rcz verdict_is 'PASS (names only, necessary not sufficient): escrow-split-contract:live-ok')"
  bchk rc0-log-has-live-ok "$([[ "$OUT" == *'escrow-split-contract:live-ok'* ]] && echo 0 || echo 1)"
  bchk rc0-log-carries-the-verdict "$([[ "$OUT" == *'Verdict: PASS (names only, necessary not sufficient)'* ]] && echo 0 || echo 1)"
  bchk rc0-summary-has-live-ok "$(rcz file_has "$SUM" 'escrow-split-contract:live-ok')"
  bchk rc0-summary-time-sha-scope "$([[ "$(<"$SUM")" == *"SHA $SHA (ref main)"* && "$(<"$SUM")" == *'Valid at run time only'* && "$(<"$SUM")" =~ [0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9:]{8}\ UTC ]] && echo 0 || echo 1)"
  bchk rc0-no-token-leak "$(rcz leak_free "$ENVTOK")"
  bchk rc0-stub-saw-provider-token "$(rcz file_has "$MOCK_LOG" 'AUTH provider')"
  bchk rc0-stub-never-asked-for-a-value "$([[ "$(grep -c '^ARGV secrets --only-names' "$MOCK_LOG")" -ge 2 ]] && file_lacks "$MOCK_LOG" 'ARGV secrets get' && echo 0 || echo 1)"
  bchk rc0-stub-argv-is-only-name-listings "$([[ "$(grep '^ARGV ' "$MOCK_LOG" | grep -vc '^ARGV secrets --only-names -p soleur -c ')" -eq 0 ]] && echo 0 || echo 1)"
  bchk rc0-log-run-context "$([[ "$OUT" == *"Run-context: sha=$SHA actor=synth-actor utc="* ]] && file_has "$SUM" 'by synth-actor, SHA' && echo 0 || echo 1)"
}
c_rc1() {
  seed_names; MOCKCFG=""
  grep -vx WORKSPACES_HEADER_R2_ACCESS_KEY_ID "$MOCK/prd_workspaces_luks_web.names" > "$SCR/names.tmp" && mv "$SCR/names.tmp" "$MOCK/prd_workspaces_luks_web.names"
  bcase "$ROOT_REAL" TF_VAR_doppler_token_tf="$ENVTOK"
  bchk rc1-exit "$([[ "$RC" -eq 1 ]] && echo 0 || echo 1)"
  bchk rc1-verdict "$(rcz verdict_is 'FAIL: the escrow-split contract is violated')"
  bchk rc1-summary-has-fail-and-cause "$(file_has "$SUM" 'escrow-split-contract:FAIL missing in prd_workspaces_luks_web: WORKSPACES_HEADER_R2_ACCESS_KEY_ID' && file_has "$SUM" 'escrow-split-contract:CAUSE' && echo 0 || echo 1)"
  bchk rc1-annotation-kept-in-log "$([[ "$OUT" == *'::error::escrow-split-contract:FAIL missing'* ]] && echo 0 || echo 1)"
}
c_rc2() {
  seed_names; MOCKCFG=""
  bcase "$ROOT_REAL"
  bchk rc2-exit "$([[ "$RC" -eq 2 ]] && echo 0 || echo 1)"
  bchk rc2-verdict "$(rcz verdict_is 'NO TOKEN: ')"
  bchk rc2-checker-never-ran "$(file_lacks "$MOCK_LOG" 'ARGV secrets' && echo 0 || echo 1)"
}
c_rc3() {
  seed_names; MOCKCFG="MOCK_UNREADABLE_CFG=prd_workspaces_luks_web"
  bcase "$ROOT_REAL" TF_VAR_doppler_token_tf="$ENVTOK"
  bchk rc3-exit "$([[ "$RC" -eq 3 ]] && echo 0 || echo 1)"
  bchk rc3-verdict "$(rcz verdict_is 'UNREADABLE: ')"
  bchk rc3-log-carries-the-verdict "$([[ "$OUT" == *'Verdict: UNREADABLE: '* ]] && echo 0 || echo 1)"
  bchk rc3-summary-names-config-only "$(file_has "$SUM" 'escrow-split-contract:unreadable: config prd_workspaces_luks_web (vendor detail withheld' && file_has "$SUM" 'escrow-split-contract:NOTE' && file_lacks "$SUM" 'rc=1' && echo 0 || echo 1)"
}
c_rc78() {
  seed_names; MOCKCFG=""
  bcase "$ROOT_REAL" TF_VAR_doppler_token_tf="$ENVTOK" SHELLOPTS=xtrace
  bchk rc78-exit "$([[ "$RC" -eq 78 ]] && echo 0 || echo 1)"
  bchk rc78-verdict "$(rcz verdict_is 'UNEXPECTED exit 78: not ready')"
  bchk rc78-no-token-leak "$(rcz leak_free "$ENVTOK")"
}
c_rc124() {
  MOCKCFG="FAKE_RC=124"
  bcase "$ROOT_FAKE" TF_VAR_doppler_token_tf="$ENVTOK"
  bchk rc124-exit "$([[ "$RC" -eq 124 ]] && echo 0 || echo 1)"
  bchk rc124-verdict "$(rcz verdict_is 'UNEXPECTED exit 124: the check timed out')"
}
c_rc137() {
  MOCKCFG="FAKE_RC=137"
  bcase "$ROOT_FAKE" TF_VAR_doppler_token_tf="$ENVTOK"
  bchk rc137-exit "$([[ "$RC" -eq 137 ]] && echo 0 || echo 1)"
  bchk rc137-verdict "$(rcz verdict_is 'UNEXPECTED exit 137: the check timed out')"
}
c_rc7() {
  MOCKCFG="FAKE_RC=7"
  bcase "$ROOT_FAKE" TF_VAR_doppler_token_tf="$ENVTOK"
  bchk rc7-exit "$([[ "$RC" -eq 7 ]] && echo 0 || echo 1)"
  bchk rc7-verdict "$(rcz verdict_is 'UNEXPECTED exit 7: not ready')"
}
c_empty() {
  MOCKCFG="FAKE_RC=0"
  bcase "$ROOT_FAKE" TF_VAR_doppler_token_tf="$ENVTOK"
  bchk empty-exit-nonzero "$([[ "$RC" -eq 1 ]] && echo 0 || echo 1)"
  bchk empty-verdict "$(rcz verdict_is 'NOT READY: exit 0 without the live-ok line')"
  bchk empty-never-pass-text "$(file_lacks "$SUM" 'PASS (' && echo 0 || echo 1)"
}
c_token() {
  printf 'escrow-split-contract:FAIL stray %s here\nescrow-split-contract:live-ok-not\n' "$LEAKTOK" > "$SCR/noise.txt"
  MOCKCFG="FAKE_RC=1
FAKE_NOISE_FILE=$SCR/noise.txt"
  bcase "$ROOT_FAKE" TF_VAR_doppler_token_tf="$ENVTOK"
  bchk token-shape-absent-from-log-and-summary "$(rcz leak_free "$LEAKTOK" "$ENVTOK")"
  bchk token-redaction-marker-present "$([[ "$OUT" == *dp.REDACTED* ]] && file_has "$SUM" 'dp.REDACTED' && echo 0 || echo 1)"
}
c_stderr() {
  seed_names; MOCKCFG="MOCK_NAMES_ERR='$STDERRTOK and $JWTLIKE'"
  bcase "$ROOT_REAL" TF_VAR_doppler_token_tf="$ENVTOK"
  bchk stderr-exit "$([[ "$RC" -eq 3 ]] && echo 0 || echo 1)"
  bchk stderr-credential-shapes-absent "$(rcz leak_free "$STDERRTOK" "$JWTLIKE")"
  bchk stderr-detail-withheld-in-summary "$(file_has "$SUM" 'vendor detail withheld' && echo 0 || echo 1)"
}
c_inject() {
  printf '%s\n' 'escrow-split-contract:FAIL has ```<script>alert(1)</script>``` inside' '<img src=x onerror=alert(1)>' '::set-output name=pwn::1' 'escrow-split-contract:CAUSE ok' > "$SCR/noise.txt"
  MOCKCFG="FAKE_RC=1
FAKE_NOISE_FILE=$SCR/noise.txt"
  bcase "$ROOT_FAKE" TF_VAR_doppler_token_tf="$ENVTOK"
  bchk inject-html-and-directive-absent-from-summary "$(file_lacks "$SUM" '<img' && file_lacks "$SUM" '::set-output' && echo 0 || echo 1)"
  bchk inject-fence-cannot-be-closed "$([[ "$(tr -cd '`' < "$SUM" | wc -c)" -eq 6 ]] && echo 0 || echo 1)"
  bchk inject-prefixed-line-survives "$(file_has "$SUM" 'escrow-split-contract:CAUSE ok' && echo 0 || echo 1)"
}
c_cap() {
  { for i in $(seq 1 200); do printf 'escrow-split-contract:CAUSE line %s\n' "$i"; done; printf 'escrow-split-contract:CAUSE %s\n' "$(head -c 2000 /dev/zero | tr '\0' 'x')"; } > "$SCR/noise.txt"
  MOCKCFG="FAKE_RC=1
FAKE_NOISE_FILE=$SCR/noise.txt"
  bcase "$ROOT_FAKE" TF_VAR_doppler_token_tf="$ENVTOK"
  local n longest
  n=$(awk '/^```text$/{f=1;next} /^```$/{f=0} f' "$SUM" | wc -l)
  longest=$(awk '/^```text$/{f=1;next} /^```$/{f=0} f{ if (length($0)>m) m=length($0) } END{print m+0}' "$SUM")
  bchk cap-at-most-40-lines "$([[ "$n" -ge 1 && "$n" -le 40 ]] && echo 0 || echo 1)"
  bchk cap-at-most-600-chars "$([[ "$longest" -ge 1 && "$longest" -le 600 ]] && echo 0 || echo 1)"
}
c_canary() {
  seed_names; MOCKCFG=""
  bcase "$ROOT_REAL" TF_VAR_doppler_token_tf="$ENVTOK" HCLOUD_TOKEN=SYNTHcanaryHcloud0001 SENTRY_AUTH_TOKEN=SYNTHcanarySentry0002 CANARY_ONE=SYNTHcanaryOne0003
  bchk canary-allowlist-sees-the-provider-token "$(rcz file_has "$MOCK_LOG" 'ENVSEEN TF_VAR_doppler_token_tf')"
  bchk canary-other-tier-b-names-are-not-inherited "$(file_lacks "$MOCK_LOG" 'ENVSEEN HCLOUD_TOKEN' && file_lacks "$MOCK_LOG" 'ENVSEEN SENTRY_AUTH_TOKEN' && file_lacks "$MOCK_LOG" 'ENVSEEN CANARY_ONE' && echo 0 || echo 1)"
  bchk canary-values-absent-everywhere "$(rcz leak_free SYNTHcanaryHcloud0001 SYNTHcanarySentry0002 SYNTHcanaryOne0003)"
}
c_td_substring() { # the exact line, not a line that merely contains it
  printf '%s\n' 'escrow-split-contract:live-ok-not' > "$SCR/noise.txt"
  MOCKCFG="FAKE_RC=0
FAKE_NOISE_FILE=$SCR/noise.txt"
  bcase "$ROOT_FAKE" TF_VAR_doppler_token_tf="$ENVTOK"
  bchk td-substring-liveok-not-ready "$([[ "$RC" -eq 1 ]] && verdict_is 'NOT READY: exit 0 without the live-ok line' && echo 0 || echo 1)"
}
c_td_ctrl() { # the summary holds printable ASCII only, whatever the checker line carried
  printf 'escrow-split-contract:FAIL a\033[2Jb\rc\342\200\250d\tE\n' > "$SCR/noise.txt"
  MOCKCFG="FAKE_RC=1
FAKE_NOISE_FILE=$SCR/noise.txt"
  bcase "$ROOT_FAKE" TF_VAR_doppler_token_tf="$ENVTOK"
  bchk td-summary-printable-ascii-only "$([[ "$(LC_ALL=C tr -d '\n\040-\176' < "$SUM" | wc -c)" -eq 0 ]] && echo 0 || echo 1)"
}
c_td_tfvar() { # the loader exports every Tier-B secret as TF_VAR_<lowercase>, and the job has a GITHUB_TOKEN-class value too
  seed_names; MOCKCFG=""
  bcase "$ROOT_REAL" TF_VAR_doppler_token_tf="$ENVTOK" TF_VAR_hcloud_token="$CANARY_P" GITHUB_TOKEN="$CANARY_Q" DOPPLER_TOKEN_INFRA_PRIVILEGED="$CANARY_R" AWS_SECRET_ACCESS_KEY="$CANARY_S"
  bchk td-tfvar-and-github-token-not-inherited "$(file_has "$MOCK_LOG" 'ENVSEEN TF_VAR_doppler_token_tf' && file_lacks "$MOCK_LOG" 'ENVSEEN TF_VAR_hcloud_token' && file_lacks "$MOCK_LOG" 'ENVSEEN GITHUB_TOKEN' && file_lacks "$MOCK_LOG" 'ENVSEEN DOPPLER_TOKEN_INFRA_PRIVILEGED' && file_lacks "$MOCK_LOG" 'ENVSEEN AWS_SECRET_ACCESS_KEY' && echo 0 || echo 1)"
}
c_fn() { # an exported shell function is not a variable: the child must not inherit it
  seed_names; MOCKCFG=""
  bcase "$ROOT_REAL" TF_VAR_doppler_token_tf="$ENVTOK" 'BASH_FUNC_zzcanary%%=() { :; }'
  bchk fn-exported-function-not-inherited "$(file_has "$MOCK_LOG" 'AUTH provider' && file_lacks "$MOCK_LOG" 'FNSEEN zzcanary' && echo 0 || echo 1)"
}
# The runbook's own log command, run over a log shaped like GitHub's (job, step, timestamp prefix; the step's script echoed
# first, each line wrapped in ANSI colour): it must find the real verdict and must NOT match the echoed script source.
runbook_grep_pattern() { # <runbook>
  sed -n "s/.*gh run view \"\$ID\" --log | grep -E '\([^']*\)'.*/\1/p" "$1"
}
c_logshape() {
  seed_names; MOCKCFG=""
  grep -vx WORKSPACES_HEADER_R2_ACCESS_KEY_ID "$MOCK/prd_workspaces_luks_web.names" > "$SCR/names.tmp" && mv "$SCR/names.tmp" "$MOCK/prd_workspaces_luks_web.names"
  bcase "$ROOT_REAL" TF_VAR_doppler_token_tf="$ENVTOK"
  local pat log="$SCR/fake-run.log" ts='2026-10-04T00:00:00.0000000Z' pre
  pat="$(runbook_grep_pattern "$BIRTH")"
  pre="$(printf 'escrow-check\tEscrow readiness check (read-only)\t%s' "$ts")"
  { printf '%s ##[group]Run set -uo pipefail\n' "$pre"
    while IFS= read -r l; do printf '%s \033[36;1m%s\033[0m\n' "$pre" "$l"; done < "$BODY"
    printf '%s shell: /usr/bin/bash -e {0}\n%s ##[endgroup]\n' "$pre" "$pre"
    while IFS= read -r l; do printf '%s %s\n' "$pre" "$l"; done <<< "$OUT"; } > "$log"
  local hits; hits="$(grep -E -- "$pat" "$log")"
  bchk logshape-runbook-pattern-found "$([[ -n "$pat" ]] && echo 0 || echo 1)"
  bchk logshape-replace-holds-no-copy "$([[ -z "$(runbook_grep_pattern "$REPLACE")" ]] && echo 0 || echo 1)"
  bchk logshape-finds-the-real-verdict "$([[ "$hits" == *'Z Verdict: FAIL'* && "$hits" == *'Z Run-context: '* && "$hits" == *'Z escrow-split-contract:FAIL missing'* ]] && echo 0 || echo 1)"
  bchk logshape-never-matches-the-echoed-script "$([[ "$hits" != *'verdict="PASS'* && "$hits" != *"grep -qx"* && "$hits" != *'printf'* && "$hits" != *'live-ok'* ]] && echo 0 || echo 1)"
}
c_hang() { # NOT in ALL_CASES: it needs the body's timeout shortened (see body_expect_green g2-real-timeout)
  MOCKCFG="FAKE_RC=0
FAKE_HANG=1"
  bcase "$ROOT_FAKE" TF_VAR_doppler_token_tf="$ENVTOK"
  bchk hang-exit-124 "$([[ "$RC" -eq 124 ]] && echo 0 || echo 1)"
  bchk hang-verdict-and-summary "$(rcz verdict_is 'UNEXPECTED exit 124: the check timed out')"
  bchk hang-log-carries-the-verdict "$([[ "$OUT" == *'Verdict: UNEXPECTED exit 124'* ]] && echo 0 || echo 1)"
}
c_ref() {
  MOCKCFG="FAKE_RC=1"
  rm -f "$ROOT_FAKE/PWNED"
  bcase "$ROOT_FAKE" TF_VAR_doppler_token_tf="$ENVTOK" GITHUB_REF_NAME='main`$(touch PWNED)`<b>"'
  bchk ref-name-sanitised-and-never-executed "$([[ ! -e "$ROOT_FAKE/PWNED" ]] && file_lacks "$SUM" '`$(' && file_lacks "$SUM" '<b>' && file_has "$SUM" '(ref main' && echo 0 || echo 1)"
}
c_benign() {
  printf '%s\n' 'advisory: 3 prd-root name(s) are reachable from a web-class token (names withheld in CI)' 'escrow-split-contract:live-ok' > "$SCR/noise.txt"
  MOCKCFG="FAKE_RC=0
FAKE_NOISE_FILE=$SCR/noise.txt"
  bcase "$ROOT_FAKE" TF_VAR_doppler_token_tf="$ENVTOK"
  bchk benign-order-and-advisory-pass "$([[ "$RC" -eq 0 ]] && verdict_is 'PASS (names only, necessary not sufficient)' && file_has "$SUM" 'advisory: 3 prd-root' && echo 0 || echo 1)"
}
ALL_CASES=(c_rc0 c_rc1 c_rc2 c_rc3 c_rc78 c_rc124 c_rc137 c_rc7 c_empty c_token c_stderr c_inject c_cap c_canary c_td_substring c_td_ctrl c_td_tfvar c_fn c_logshape c_ref c_benign)
# The case LIST is pinned by name, not only by count: swapping one case for another keeps the count.
EXPECTED_CASES="c_rc0 c_rc1 c_rc2 c_rc3 c_rc78 c_rc124 c_rc137 c_rc7 c_empty c_token c_stderr c_inject c_cap c_canary c_td_substring c_td_ctrl c_td_tfvar c_fn c_logshape c_ref c_benign"
[[ "${ALL_CASES[*]}" == "$EXPECTED_CASES" ]] || { printf '[FAIL] H1 the behavioural case list changed: %s\n' "${ALL_CASES[*]}" >&2; exit 1; }

behave() { # <body file> [case functions...]: runs the cases, fills BRES and B_EXEC
  BODY="$1"; shift
  BRES=(); B_EXEC=0
  local c cases=("$@")
  [[ "${#cases[@]}" -gt 0 ]] || cases=("${ALL_CASES[@]}")
  for c in "${cases[@]}"; do "$c"; done
}
bres_failed() { printf '%s\n' "${BRES[@]}" | grep -cxF >/dev/null -- "$1"$'\t'FAIL; }

# INSTRUMENT SELF-TEST for the behavioural harness: leak_free must see a token in each of the three places, and a clean run.
OUT="clean"; : > "$SUM"; : > "$MOCK_LOG"
leak_free SYNTHself123 || { echo "[FATAL] INSTRUMENT: leak_free(clean) said leaked" >&2; exit 2; }
OUT="has S Y N T H s e l f - 1 2 3"; leak_free SYNTHself123 && { echo "[FATAL] INSTRUMENT: leak_free missed a spaced token" >&2; exit 2; }
OUT="has $(printf SYNTHself123 | rev)"; leak_free SYNTHself123 && { echo "[FATAL] INSTRUMENT: leak_free missed a reversed token" >&2; exit 2; }
OUT="has $(printf SYNTHself123 | base64 -w0)"; leak_free SYNTHself123 && { echo "[FATAL] INSTRUMENT: leak_free missed a base64 token" >&2; exit 2; }
OUT="has $(printf SYNTHself123 | od -An -tx1 | tr -d ' \n')"; leak_free SYNTHself123 && { echo "[FATAL] INSTRUMENT: leak_free missed a hex token" >&2; exit 2; }
OUT="has SYNTHself123"; leak_free SYNTHself123 && { echo "[FATAL] INSTRUMENT: leak_free missed a token in OUT" >&2; exit 2; }
OUT="clean"; echo SYNTHself123 > "$SUM"; leak_free SYNTHself123 && { echo "[FATAL] INSTRUMENT: leak_free missed a token in the summary" >&2; exit 2; }
: > "$SUM"; echo SYNTHself123 > "$MOCK_LOG"; leak_free SYNTHself123 && { echo "[FATAL] INSTRUMENT: leak_free missed a token in the stub log" >&2; exit 2; }
: > "$MOCK_LOG"; rm -f "$SUM"; leak_free SYNTHself123 2>/dev/null && { echo "[FATAL] INSTRUMENT: leak_free passed an unreadable summary" >&2; exit 2; }
: > "$SUM"

behave "$SCR/body.sh"
real_failed=0
for r in "${BRES[@]}"; do
  rid="${r%%$'\t'*}"; rv="${r#*$'\t'}"
  if [[ "$rv" == ok ]]; then ok "G2 $rid"; else no "G2 $rid (last run: rc=$RC out=${OUT:0:200})"; real_failed=$((real_failed + 1)); fi
done
# H1: the declared behavioural-case count is an EXACT pin. Deleting a case (say the rc 3 case) cannot pass by shrinking the suite.
EXPECTED_B=78
if [[ "$B_EXEC" -ne "$EXPECTED_B" ]]; then
  printf '[FAIL] H1 the behavioural suite executed %s checks, the pin is %s (a case was dropped, or one was added without moving the pin)\n' "$B_EXEC" "$EXPECTED_B" >&2
  exit 1
fi
ok "G2 H1 the behavioural check count equals its pin ($EXPECTED_B)"

# --- Guard 2 mutations: edit the step BODY on a scratch copy, re-run only the cases that must notice -------------------
mutate_body() { # <name> <python code operating on `s`>: rc 3 = did not land
  python3 - "$SCR/body.sh" "$SCR/mut/$1.sh" "$2" <<'PY'
import sys
src, dst, code = sys.argv[1:4]
ns = {"s": open(src).read()}
before = ns["s"]
exec(code, ns)
if ns["s"] == before:
    sys.exit(3)
open(dst, "w").write(ns["s"])
PY
}
body_expect_red() { # <name> <check id that must FAIL> <python> <cases...>
  local name="$1" want="$2" code="$3" rc=0; shift 3
  mutate_body "$name" "$code" || rc=$?
  if [[ "$rc" -ne 0 ]]; then no "body mutation $name did not land (rc=$rc)"; return; fi
  behave "$SCR/mut/$name.sh" "$@"
  if bres_failed "$want"; then ok "G2 body mutation $name -> $want goes RED"; else no "G2 body mutation $name -> $want stayed green"; fi
}
body_expect_green() { # <name> <python> <cases...>: the mutated body must still pass every check of the named cases
  local name="$1" code="$2" rc=0; shift 2
  mutate_body "$name" "$code" || rc=$?
  if [[ "$rc" -ne 0 ]]; then no "body mutation $name did not land (rc=$rc)"; return; fi
  behave "$SCR/mut/$name.sh" "$@"
  if printf '%s\n' "${BRES[@]}" | grep -c >/dev/null $'\tFAIL$'; then no "G2 body mutation $name: a check failed ($(grep -m1 $'\tFAIL$' <<<"$(printf '%s\n' "${BRES[@]}")" | cut -f1))"; else ok "G2 $name: the real timeout killed a stalled checker and the verdict still printed"; fi
}
body_expect_green g2-real-timeout "s = s.replace('timeout -k 10 240', 'timeout -k 10 1', 1)" c_hang
body_expect_red g2-no-redaction token-shape-absent-from-log-and-summary "s = '\n'.join(l for l in s.split('\n') if 'dp.REDACTED' not in l)" c_token
body_expect_red g2-widen-prefix-grep inject-html-and-directive-absent-from-summary "s = s.replace(\"grep -E '^(escrow-split-contract:|advisory: [0-9]+ )'\", \"grep -E '.'\", 1)" c_inject
body_expect_red g2-no-cap cap-at-most-40-lines "s = s.replace(\"| cut -c1-600 | sed -n '1,40p'\", '', 1)" c_cap
body_expect_red g2-rc3-says-pass rc3-verdict "s = s.replace('3) verdict=\"UNREADABLE:', '3) verdict=\"PASS (names only, necessary not sufficient): escrow-split-contract:live-ok', 1)" c_rc3
body_expect_red g2-exit-zero rc1-exit "i = s.rindex('exit \"\$rc\"'); s = s[:i] + 'exit 0' + s[i + len('exit \"\$rc\"'):]" c_rc1
body_expect_red g2-no-backtick-strip inject-fence-cannot-be-closed "s = s.replace(\" | tr -d '\`'\", '', 1)" c_inject
body_expect_red g2-default-arm-ready rc7-verdict "s = s.replace('UNEXPECTED exit \${rc}: not ready', 'PASS: ready', 1)" c_rc7
body_expect_red g2-empty-live-ok-keeps-rc0 empty-exit-nonzero "s = s.replace('without the live-ok line\"; rc=1', 'without the live-ok line\"', 1)" c_empty
body_expect_red g1-no-allowlist-loop canary-other-tier-b-names-are-not-inherited "s = s.replace('unset \"\$v\" 2>/dev/null || true', ':', 1)" c_canary
body_expect_red g1-no-unset-f fn-exported-function-not-inherited "s = s.replace('while read -r _k _t f; do unset -f \"\$f\" 2>/dev/null; done < <(declare -Fx)', ':', 1)" c_fn
body_expect_red g1-allowlist-keeps-tfvar td-tfvar-and-github-token-not-inherited "s = s.replace('case \"\$v\" in PATH|', 'case \"\$v\" in TF_VAR_*|PATH|', 1)" c_td_tfvar
body_expect_red g1-allowlist-keeps-github-token td-tfvar-and-github-token-not-inherited "s = s.replace('case \"\$v\" in PATH|', 'case \"\$v\" in GITHUB_TOKEN|PATH|', 1)" c_td_tfvar
body_expect_red g1-allowlist-keeps-key-suffix td-tfvar-and-github-token-not-inherited "s = s.replace('case \"\$v\" in PATH|', 'case \"\$v\" in *_KEY|*_SECRET|PATH|', 1)" c_td_tfvar
body_expect_red g2-live-ok-substring td-substring-liveok-not-ready "s = s.replace(\"grep -qx 'escrow-split-contract:live-ok'\", \"grep -q 'escrow-split-contract:live-ok'\", 1)" c_td_substring
body_expect_red g2-no-ascii-flatten td-summary-printable-ascii-only "s = s.replace(\"LC_ALL=C tr -c '\\\\n\\\\040-\\\\176' ' ' | \", '', 1)" c_td_ctrl
body_expect_red g2-foreign-command no-foreign-command-in-c_rc1 "i = s.rindex('exit \"\$rc\"'); s = s[:i] + '( python3 -c 1 2>/dev/null ) || :\\n' + s[i:]" c_rc1
body_expect_red g2-no-run-context rc0-log-run-context "s = s.replace(\"printf 'Run-context: sha=%s actor=%s utc=%s\\\\n'\", \"printf 'Ctx: sha=%s actor=%s utc=%s\\\\n'\", 1)" c_rc0
body_expect_red g1-allowlist-keeps-hcloud canary-other-tier-b-names-are-not-inherited "s = s.replace('TMPDIR|LANG|TF_VAR_doppler_token_tf)', 'TMPDIR|LANG|HCLOUD_TOKEN|TF_VAR_doppler_token_tf)', 1)" c_canary

# =====================================================================================================================
# Wording pins (doc-grep): the runbooks and the workflow say the same honest thing about what a green run means
# =====================================================================================================================
step0() { # <runbook>: the text of "### Step 0" up to the next heading of the same depth
  awk '/^### Step 0 /{f=1; print; next} f && /^### /{exit} f' "$1"
}
for rb in "$BIRTH" "$REPLACE"; do
  n="$(basename "$rb")"
  s0="$(step0 "$rb")"
  [[ -n "$s0" ]] || { no "W0 $n has no '### Step 0' section"; continue; }
  [[ "$s0" == *'web-host-escrow-diagnose.yml'* ]] && ok "W1 $n step 0 tells the reader to dispatch web-host-escrow-diagnose.yml" || no "W1 $n step 0 does not name the diagnostic workflow"
  [[ "$s0" == *'not sufficient'* ]] && ok "W2 $n step 0 says a green run is necessary, not sufficient" || no "W2 $n step 0 lost 'not sufficient'"
  [[ "$s0" == *'current `main` head'* ]] && ok "W3 $n step 0 ties a cited green run to the current main head" || no "W3 $n step 0 lost the current-main-head rule"
  [[ "$s0" == *'re-run'* || "$s0" == *'re-runs'* ]] && ok "W4 $n step 0 says the birth/replace jobs re-run the check" || no "W4 $n step 0 lost the re-run sentence"
  [[ "$s0" != *'nothing to run beforehand'* ]] && ok "W5 $n step 0 no longer says there is nothing to run beforehand" || no "W5 $n step 0 still says there is nothing to run beforehand"
  # The stale source: O10 evicted DOPPLER_TOKEN_TF from prd_terraform, so a command that reads it from there cannot work.
  if grep -E 'DOPPLER_TOKEN_TF[^|]*-c prd_terraform|-c prd_terraform[^|]*DOPPLER_TOKEN_TF' "$rb" | grep -c >/dev/null .; then no "W6 $n still reads DOPPLER_TOKEN_TF from prd_terraform"; else ok "W6 $n no longer reads DOPPLER_TOKEN_TF from prd_terraform"; fi
done
b0="$(step0 "$BIRTH")"
for key in 'PASS' 'NO TOKEN' 'FAIL' 'NOT READY' 'UNREADABLE' 'UNEXPECTED exit 124'; do
  [[ "$b0" == *"**$key"* ]] && ok "W9 the birth outcome table has a row for the $key verdict" || no "W9 the birth outcome table has no '**$key' row (the workflow prints that verdict)"
done
for phrase in 'do not birth on this alone' 'gh issue view 9377 --json comments' 'Usually the Tier-B project' 'Never copy web-1' 'Never run step O13' 'O12b' 'Doppler reported the config as not found' 'last** line'; do
  [[ "$b0" == *"$phrase"* ]] && ok "W10 the birth step 0 keeps '$phrase'" || no "W10 the birth step 0 lost '$phrase'"
done
[[ "$b0" != *'rotate the token (step O13)'* && "$b0" != *'Proceed only once'* && "$b0" != *'Proceed.'* ]] && ok "W11 the birth step 0 no longer sends an agent to rotate via O13 or says Proceed on a names-only PASS" || no "W11 the birth step 0 again says rotate-via-O13 or Proceed"
[[ "$(<"$BIRTH")" == *'soleur-infra-privileged'* ]] && ok "W7 the birth break-glass step 0 reads the token from soleur-infra-privileged" || no "W7 the birth break-glass step 0 does not name soleur-infra-privileged"
file_has "$WF" 'necessary not sufficient' && ok "W8 the workflow's PASS text says necessary not sufficient" || no "W8 the workflow's PASS text lost 'necessary not sufficient'"

# =====================================================================================================================
# H3 dispatch rows: the suite goes RED, as workflow-missing, when there is nothing to check
# =====================================================================================================================
if [[ -z "${DIAG_NO_RECURSE:-}" ]]; then
  EMPTY_TREE="$SCR/empty_tree"; mkdir -p "$EMPTY_TREE/.github/workflows"
  rc=0; out="$(DIAG_NO_RECURSE=1 DIAG_REPO_ROOT="$EMPTY_TREE" bash "$SELF" 2>&1)" || rc=$?
  if [[ "$rc" -ne 0 && "$out" == *workflow-missing* ]]; then ok "H3 a tree with ZERO workflow files is RED as workflow-missing"; else no "H3 an empty tree was not RED as workflow-missing (rc=$rc)"; fi
  rc=0; out="$(DIAG_NO_RECURSE=1 DIAG_WF="$REPO/.github/workflows/web-host-escrow-diagnose.RENAMED.yml" bash "$SELF" 2>&1)" || rc=$?
  if [[ "$rc" -ne 0 && "$out" == *workflow-missing* ]]; then ok "H3 the real tree with the workflow renamed is RED as workflow-missing"; else no "H3 a renamed workflow was not RED as workflow-missing (rc=$rc)"; fi
fi

selftest_ok_no   # ok()/no() re-checked after every row ran: a later redefinition cannot slip past the top-of-file check
printf '\n%s passed, %s failed\n' "$passes" "$fails"
# ANTI-VACUITY FLOOR (printf + exit, never through the helpers it backstops).
MIN_PASS=189
if [[ "$passes" -lt "$MIN_PASS" ]]; then
  printf '[FAIL] only %s assertions passed (floor %s): a row was dropped or stopped dispatching\n' "$passes" "$MIN_PASS" >&2
  exit 1
fi
[[ "$fails" -eq 0 ]]
