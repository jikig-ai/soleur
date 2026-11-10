#!/usr/bin/env bash
# Guard 1 (#9927 item 9 plan) -- the `sole-copy-protection-check` job of
# `.github/workflows/scheduled-terraform-drift.yml`.
#
# PROPERTY. The job is a two-row matrix (#10432): `inngest` (the Inngest store volume) and `web1` (the web-1 workspaces
# volume). For EACH row, a live Hetzner object carrying that row's name and pinned id whose `protection.delete` differs
# from that row's own committed Terraform declaration (beyond 90 minutes of that file's last commit), or that is absent
# or ambiguous, always produces that row's own issue and a red leg; a probe that could not read Hetzner (including one
# that produced no verdict at all) never reports clean; no row's request, pin, expected flag, grace, titles, clear step or
# email depends on the other row's data; the job is read-only, prints no write recipe, and never holds the read/write
# Hetzner token. The full table runs on the `inngest` entry; the web-1 table (W rows) covers every arm where a row value
# changes the outcome, the cross-entry rows (C) run both directions on one shared issue store, and use_entry is the oracle.
#
# HOW. Every step is EXTRACTED from the workflow by job id and step id (yaml.safe_load, never
# re-implemented here) and EXECUTED under stubs: the real scripts/lib/bearer-curl.sh sits behind a stub
# `curl` (the only seam), `doppler` and `gh` are stubs with strict argv models and a stateful issue store,
# and every `if:` / `env:` / `with:` expression is EVALUATED by plugins/soleur/test/lib/gha-expr.py (a
# reference to an output key a step does not publish is FATAL, not empty). The runner shell is
# `bash --noprofile --norc -e` with BASH_ENV/SHELLOPTS/BASHOPTS scrubbed: no `shell:` key means `-e` and
# no pipefail. Each case compares the WHOLE $GITHUB_OUTPUT of the probe and which later steps ran.
#
# COUNTING. The suite re-runs itself and counts its own `  pass: ` / `  FAIL: ` lines against the inner
# summary (conservation) and the FLOOR, so a helper that stops counting, or a deleted row, cannot turn
# the run green. Rows that need a weaker stub, a weaker comparison or a neutered helper (H1-H7) prove the suite can see
# them: end_row, invariants, want_steps, want_req and want_out each have a negative control. The invariants run for EVERY
# case of a multi-case row (fold_inv folds the earlier cases in; H7), not only the last one, and under the entry of the
# case they belong to (switch_entry folds before the constants move). H11-H15 are the negative controls of the matrix
# context, the issue-store id ban, use_entry and the N1c/N3 document bounds. FLOOR and TABLE_ROWS are the realized counts
# of the two-entry suite (250 assertions, 157 table rows). Edits to ADR-119, runbook 6604 and workspaces-luks.tf select
# this suite too (scripts/lib/test-affected-paths.sh), because N1c, N3 and WR1 read them.
#
# EQUIVALENT MUTANTS and known limits (each proven in a sandbox, none a gap in a row):
#   * exactly 90 minutes of age is deliberately unpinned (V3b brackets 89 and 91): the age is wall-clock.
#   * `tar xzf ... || true` is NOT equivalent: X17b feeds a verified tarball whose doppler member is missing.
#   * mawk is UNVERIFIED here (not installable on the authoring host): the suite runs the derivation under gawk --posix,
#     and the awk uses only POSIX features (index, sub, gsub, regex match).
#   * dropping the full-token terms (RWTOK, DOPTOK; TOK on argv) is EQUIVALENT: each full value contains its own 6-character
#     prefix term, which stays and is controlled (H5), so no leak can reach one without the other.
#   * a leak of a NON-prefix slice of a token (e.g. its last 8 characters) is a declared limit: the invariant scans the whole
#     value and its first 6 characters only.
#   * the Doppler tarball and `timeout` behaviour are exercised under stubs only (no network).
#
# Run: bash plugins/soleur/test/sole-copy-drift-check.test.sh
# Override the workflow under test (mutation proofs on a COPY): SOLE_COPY_DRIFT_WF=/path/to/copy.yml

set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

# ANTI-VACUITY FLOOR at the REALIZED count (the number here and the number the run prints must agree).
FLOOR=250
# Rows of the case table (every end_row call before the harness section), declared apart from the counters so
# deleting one is a diff here (H3).
TABLE_ROWS=157

if [[ -z "${_SC_DRIFT_INNER:-}" ]]; then
  _log=$(mktemp "$TMPDIR/sole-copy-drift.XXXXXX") || { printf 'FATAL: mktemp for the suite log\n' >&2; exit 2; }
  trap 'rm -f "$_log"' EXIT
  _SC_DRIFT_INNER=1 bash "${BASH_SOURCE[0]}" "$@" 2>&1 | tee "$_log"
  _rc=${PIPESTATUS[0]}
  _np=$(grep -c '^  pass: ' "$_log")
  _nf=$(grep -c '^  FAIL: ' "$_log")
  _summary=$(sed -n 's|^=== Results: \([0-9][0-9]*\)/\([0-9][0-9]*\) passed, \([0-9][0-9]*\) failed ===$|\1 \2 \3|p' "$_log")
  if [[ "$(grep -c . <<<"$_summary")" != "1" ]]; then
    printf 'FATAL: the inner run printed no single Results line (rc=%s) -- it died before finishing\n' "$_rc" >&2
    exit 2
  fi
  read -r _sp _st _sf <<<"$_summary"
  if [[ "$_sp" != "$_np" || "$_sf" != "$_nf" || "$_st" != "$((_np + _nf))" ]]; then
    printf 'FATAL: count conservation broken -- summary says %s/%s passed, %s failed; the output has %s pass lines and %s FAIL lines\n' \
      "$_sp" "$_st" "$_sf" "$_np" "$_nf" >&2
    exit 1
  fi
  if (( _np + _nf < FLOOR )); then
    printf 'FATAL: only %s assertions ran; expected >= %s.\n' "$((_np + _nf))" "$FLOOR" >&2
    exit 1
  fi
  if (( _nf > 0 )); then exit 1; fi
  if [[ "$_rc" != "0" ]]; then printf 'FATAL: inner run exited %s with no FAIL line\n' "$_rc" >&2; exit "$_rc"; fi
  exit 0
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
: "${REPO_ROOT:?repo root resolved empty}"
WF="${SOLE_COPY_DRIFT_WF:-$REPO_ROOT/.github/workflows/scheduled-terraform-drift.yml}"
LOADER="$REPO_ROOT/.github/actions/infra-credentials/action.yml"
LIBREAL="$REPO_ROOT/scripts/lib/bearer-curl.sh"
EXPRLIB="$REPO_ROOT/plugins/soleur/test/lib/gha-expr.py"
TFREAL="$REPO_ROOT/apps/web-platform/infra/inngest-redis-luks.tf"
RUNBOOK="$REPO_ROOT/knowledge-base/engineering/operations/runbooks/inngest-luks-cutover-6894.md"
TIERS="$REPO_ROOT/knowledge-base/engineering/operations/runbooks/infra-credential-tiers-8209.md"
SKILL="$REPO_ROOT/plugins/soleur/skills/postmerge/SKILL.md"
ADR119="$REPO_ROOT/knowledge-base/engineering/architecture/decisions/ADR-119-luks-at-rest-for-the-live-workspaces-volume.md"
RB6604="$REPO_ROOT/knowledge-base/engineering/operations/runbooks/workspaces-luks-cutover-6604.md"
TFWEB1="$REPO_ROOT/apps/web-platform/infra/workspaces-luks.tf"
JOB="sole-copy-protection-check"

PASS=0
FAIL=0
pass() { echo "  pass: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }
fatal() { echo "FATAL: $1" >&2; exit 2; }
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

for f in "$WF" "$LOADER" "$LIBREAL" "$EXPRLIB" "$TFREAL" "$RUNBOOK" "$TIERS" "$SKILL" "$ADR119" "$RB6604" "$TFWEB1"; do [[ -f "$f" ]] || fatal "missing $f"; done
command -v python3 >/dev/null || fatal "python3 not found"
python3 -I -c 'import yaml' 2>/dev/null || fatal "python3 yaml module not importable"
command -v jq >/dev/null || fatal "jq not found"

TMP=$(mktemp -d) || fatal "sandbox"
: "${TMP:?}"
trap 'rm -rf -- "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/x" "$TMP/lib" || fatal "mkdir"

# The runner's awk is mawk; use it when present, else gawk in POSIX mode, else whatever `awk` is.
if command -v mawk >/dev/null; then ln -s "$(command -v mawk)" "$TMP/bin/awk"; AWK_USED=mawk
elif command -v gawk >/dev/null; then printf '#!/bin/sh\nexec gawk --posix "$@"\n' > "$TMP/bin/awk"; chmod +x "$TMP/bin/awk"; AWK_USED="gawk --posix"
else AWK_USED="system awk"; fi

# POSITIVE CONTROL for the outer count (pass()/fail() each move their counter and print a countable line).
if ! ( PASS=0; FAIL=0
       pass "positive-control" > "$TMP/pc.out"; fail "positive-control" >> "$TMP/pc.out"
       [[ "$PASS" == 1 && "$FAIL" == 1 ]] || exit 1
       [[ "$(sed -n 1p "$TMP/pc.out")" == "  pass: positive-control" ]] || exit 1
       [[ "$(sed -n 2p "$TMP/pc.out")" == "  FAIL: positive-control" ]] || exit 1 ); then
  fatal "positive control -- pass()/fail() did not each move their counter and print the line the outer run counts"
fi
echo "=== sole-copy-protection-check (Guard 1); awk under test: $AWK_USED ==="

# ---------------------------------------------------------------------------------------------------------
# The python harness: extract / static shape + mutation table / execute the job.
# ---------------------------------------------------------------------------------------------------------
cat > "$TMP/h.py" <<'PYH' || fatal "write h.py"
import copy, importlib.util, json, os, re, subprocess, sys
import yaml

# The two include rows' Hetzner ids, plain literals (the runbook pin-bump lists are regenerated with git grep). id-placement allows
# each id exactly once in the job: as its own row's volume_id.
INNGEST_ID = "106903269"
WEB1 = "106443278"
IDS = {"inngest": INNGEST_ID, "web1": WEB1}
JOB_NAME = "sole-copy-protection-check (${{ matrix.entry }})"
ROW_KEYS = ["adr", "entry", "subject", "tf_file", "tf_resource", "volume_id"]
# The ONLY validation of row values (a pre-merge check over committed constants; the job has no runtime branch for them).
ROW_PAT = {"entry": r"[a-z0-9]{1,16}", "subject": r"[A-Za-z0-9][A-Za-z0-9 -]{0,39}",
           "tf_file": r"apps/web-platform/infra/[a-z0-9-]{1,64}\.tf", "tf_resource": r"[a-z0-9_]{1,64}",
           "volume_id": r"[1-9][0-9]{0,11}", "adr": r"ADR-[0-9]{1,4}"}
STEP_IDS = ["doppler_cli", "tf_commit", "probe", "file_finding", "file_unreadable", "clear", "notify", "gate"]
GH_STEPS = {"tf_commit", "file_finding", "file_unreadable", "clear"}

def region(lines, jobid):
    idx = [i for i, l in enumerate(lines) if re.match(r"^  %s:\s*$" % re.escape(jobid), l)]
    if len(idx) != 1:
        return None
    s = idx[0]
    while s > 0 and re.match(r"^  #", lines[s - 1]):
        s -= 1
    e = idx[0] + 1
    while e < len(lines) and not re.match(r"^  \S", lines[e]):
        e += 1
    return "".join(lines[s:e])

def cmd_extract(wf, jobid, out):
    raw = open(wf).read()
    doc = yaml.safe_load(raw)
    job = (doc.get("jobs") or {}).get(jobid)
    text = region(raw.splitlines(keepends=True), jobid)
    if not isinstance(job, dict) or not isinstance(job.get("steps"), list) or text is None:
        print("MISSING job %s" % jobid)
        return 4
    os.makedirs(out + "/steps", exist_ok=True)
    json.dump(job, open(out + "/job.json", "w"))
    json.dump(doc.get("permissions"), open(out + "/wfperm.json", "w"))
    json.dump(((job.get("strategy") or {}).get("matrix") or {}).get("include"), open(out + "/rows.json", "w"))
    open(out + "/jobtext.txt", "w").write(text)
    for s in job["steps"]:
        if s.get("id") and isinstance(s.get("run"), str):
            open("%s/steps/%s.sh" % (out, s["id"]), "w").write(s["run"])
    print("FOUND steps=%d ids=%s" % (len(job["steps"]), ",".join(str(s.get("id")) for s in job["steps"])))
    return 0

def sites(job):
    for s in job.get("steps", []):
        sid = s.get("id") or "?"
        for k in ("env", "with"):
            for ek, ev in (s.get(k) or {}).items():
                yield "%s.%s" % (sid, k), "%s=%s" % (ek, ev)
        for k in ("run", "if", "uses", "name"):
            if isinstance(s.get(k), str):
                yield "%s.%s" % (sid, k), s[k]
    for k, v in job.items():
        if k != "steps":
            yield "job.%s" % k, v if isinstance(v, str) else json.dumps(v)

def violations(job, text):
    v, steps = [], job.get("steps", [])
    st = {s.get("id"): s for s in steps if s.get("id")}
    ids = [s.get("id") for s in steps if s.get("id")]
    for i in STEP_IDS:
        if i not in st:
            v.append("missing-step:" + i)
    if len(ids) != len(set(ids)):
        v.append("duplicate-step-id")
    if job.get("if") != "github.ref == 'refs/heads/main'":
        v.append("job-if")
    for k in ("environment", "env", "continue-on-error", "container", "services"):
        if job.get(k):
            v.append("job-" + k)
    for s in steps:
        sid, uses = s.get("id") or "?", str(s.get("uses", ""))
        if "infra-credentials" in uses or "DopplerHQ/cli-action" in uses:
            v.append("loader-or-mutable-installer")
        env = s.get("env") or {}
        if "DOPPLER_TOKEN" in env and sid != "probe":
            v.append("doppler-token-outside-probe")
        if sid == "probe" and env.get("DOPPLER_TOKEN") != "${{ secrets.DOPPLER_TOKEN }}":
            v.append("probe-doppler-binding")
        for k in ("GH_TOKEN", "GITHUB_TOKEN"):
            if k in env and sid not in GH_STEPS:
                v.append("gh-token-outside:" + sid)
        for k in env:
            if re.search(r"HCLOUD_TOKEN(?!_READONLY)", k):
                v.append("rw-token-env")
        if s.get("continue-on-error") and sid != "notify":
            v.append("coe:" + sid)
        if isinstance(s.get("run"), str):
            if "${{" in s["run"]:
                v.append("expr-in-run:" + sid)
            if re.search(r"(^|\s)set\s+-[a-zA-Z]*x|xtrace|bash\s+-[a-zA-Z]*x", s["run"]):
                v.append("xtrace:" + sid)
    if "notify" in st and not st["notify"].get("continue-on-error"):
        v.append("notify-not-coe")
    if re.search(r"HCLOUD_TOKEN(?!_READONLY)", text) or re.search(r"HCLOUD_TOKEN(?!_READONLY)", json.dumps(job)):
        v.append("rw-token-named")
    v += matrix_shape(job) + id_placement(job, text)
    okloc = {("DOPPLER_TOKEN", "probe.env"), ("RESEND_API_KEY", "notify.with")}
    for loc, val in sites(job):
        for m in re.finditer(r"secrets\.([A-Za-z0-9_]+)", val):
            if (m.group(1), loc) not in okloc:
                v.append("secret:%s@%s" % (m.group(1), loc))
    for sid in ("file_finding", "file_unreadable", "clear", "notify", "gate"):
        if sid in st and "always()" not in str(st[sid].get("if", "")):
            v.append("no-always:" + sid)
    if "gate" in st and "exit 1" not in str(st["gate"].get("run", "")):
        v.append("gate-no-exit")
    runs = "\n".join(str(s.get("run", "")) for s in steps)
    live = [l for l in runs.splitlines() if not l.strip().startswith("#")]
    calls = [l for l in live if re.search(r"(^|[^_A-Za-z])bc_curl ", l)]
    if len(calls) != 1:
        v.append("bc_curl-count:%d" % len(calls))
    probe = str(st.get("probe", {}).get("run", ""))
    joined = re.sub(r"\\\n\s*", " ", probe)
    stmt = [l for l in joined.splitlines() if re.search(r"(^|[^_A-Za-z])bc_curl ", l) and not l.strip().startswith("#")]
    urls = [l.strip() for l in joined.splitlines() if re.match(r"\s*url=", l)]
    if urls != ['url="https://api.hetzner.cloud/v1/volumes?name=${name}&per_page=50"']:
        v.append("request-shape")
    if len(stmt) == 1:
        sl = stmt[0]
        if "'Authorization:Bearer :TOKEN'" not in sl or '"$url"' not in sl:
            v.append("request-shape")
        if re.search(r"\s(-X|--request|-d|--data\S*|-H|--header\S*|--json|-F|-T)(\s|=|$)", sl):
            v.append("request-method-or-header-flag")
    src = probe.find('source "${GITHUB_WORKSPACE:?}/scripts/lib/bearer-curl.sh"')
    first = probe.find("bc_curl scheduled-terraform-drift")
    tokrd = probe.find("doppler secrets get HCLOUD_TOKEN_READONLY")
    if src < 0 or first < 0 or not src < first:
        v.append("library-not-sourced-first")
    if tokrd < 0 or first < 0 or not tokrd < first:
        v.append("token-read-not-before-request")
    if len(re.findall(r"doppler secrets get", runs)) != 1:
        v.append("doppler-read-count")
    # Bounds, checkout hygiene, notify wiring and permissions (the wiring a green run never exercises).
    if job.get("timeout-minutes") != 10:
        v.append("job-timeout")
    for sid, mins in {"doppler_cli": 3, "tf_commit": 2, "probe": 3, "file_finding": 2, "file_unreadable": 2, "clear": 2}.items():
        if sid in st and st[sid].get("timeout-minutes") != mins:
            v.append("step-timeout:" + sid)
    if "permissions" in job:
        v.append("job-permissions")
    co = steps[0] if steps else {}
    if not str(co.get("uses", "")).startswith("actions/checkout@") or (co.get("with") or {}).get("persist-credentials") is not False:
        v.append("checkout-persist")
    if co.get("timeout-minutes") != 2:
        v.append("step-timeout:checkout")
    # The probe must not be skipped by a failed fail-open input (the commit-time read): no implicit success().
    if st.get("probe", {}).get("if") != "${{ !cancelled() && steps.doppler_cli.outcome == 'success' }}":
        v.append("probe-if")
    nf = st.get("notify", {})
    if nf.get("uses") != "./.github/actions/notify-ops-email":
        v.append("notify-uses")
    if sorted((nf.get("with") or {}).keys()) != ["body", "resend-api-key", "subject"]:
        v.append("notify-with-keys")
    if (nf.get("with") or {}).get("resend-api-key") != "${{ secrets.RESEND_API_KEY }}":
        v.append("notify-resend-key")
    # The probe's single-writer / backstop structure: the closed set of finish arguments, exactly two writers of
    # `verdict=` (finish, and the EXIT trap, which can only say could-not-read), and the trap installed first.
    pl = [l.strip() for l in probe.splitlines() if l.strip() and not l.strip().startswith("#")]
    for l in pl:
        for a in re.findall(r"\bfinish\s+([A-Za-z\"$_-]+)", l):
            if a not in ("could-not-read", "no-token", "volume-not-found", '"$verdict"'):
                v.append("finish-arg:" + a)
    if len([l for l in pl if "verdict=" in l and "printf" in l]) != 2:
        v.append("verdict-writer-count")
    # EVERY line that names $GITHUB_OUTPUT (printf, echo, tee, cat, a redirect, an alias) must be one of the two known sites.
    if [l for l in pl if "GITHUB_OUTPUT" in l] != ["printf 'verdict=could-not-read\\n' >> \"$GITHUB_OUTPUT\"", '} >> "$GITHUB_OUTPUT"']:
        v.append("output-writer-sites")
    onx = re.search(r"on_exit\(\) \{\n(.*?)\n\}", probe, re.S)
    if not onx or re.findall(r"verdict=([a-z-]+)", onx.group(1)) != ["could-not-read"]:
        v.append("exit-trap-verdict")
    if "trap on_exit EXIT" not in pl or not probe.find("trap on_exit EXIT") < probe.find("finish() {"):
        v.append("no-exit-trap")
    # The credential read: bounded, and the Doppler token gone from the environment right after it.
    ti = next((i for i, l in enumerate(pl) if l.startswith("TOKEN=")), -1)
    if ti < 0 or not pl[ti].startswith('TOKEN="$(timeout -k 5 60 doppler secrets get HCLOUD_TOKEN_READONLY '):
        v.append("doppler-read-timeout")
    if ti < 0 or ti + 1 >= len(pl) or pl[ti + 1] != "unset DOPPLER_TOKEN":
        v.append("doppler-token-not-unset")
    # The Doppler install: the exact verification line before the extraction, the PATH hand-off, bounded curl.
    dlr = str(st.get("doppler_cli", {}).get("run", ""))
    dl = [l.strip() for l in re.sub(r"\\\n\s*", " ", dlr).splitlines() if l.strip() and not l.strip().startswith("#")]
    sha = 'echo "${DOPPLER_CLI_SHA256}  $d/doppler.tar.gz" | sha256sum -c -'
    tari = next((i for i, l in enumerate(dl) if l.startswith("tar xzf")), -1)
    if dl.count(sha) != 1 or tari < 0 or dl.index(sha) > tari:
        v.append("doppler-sha-line")
    if 'echo "$d" >> "$GITHUB_PATH"' not in dl:
        v.append("doppler-path-handoff")
    if not any(l.startswith("curl ") and "--connect-timeout 20 --max-time 120" in l for l in dl):
        v.append("doppler-curl-bound")
    # The probe's worst case (kill-after + credential read + every attempt's request + the sleeps between) must stay
    # below its own step timeout, read from the literals so a bumped bound cannot slip past the backstop.
    pj = "\n".join(pl)
    mdp = re.search(r"timeout -k (\d+) (\d+) doppler secrets get", pj)
    atts, mts, sls = set(re.findall(r"attempt < (\d+)", pj)), re.findall(r"bc_curl [^\n]*? --max-time (\d+)", pj), re.findall(r"then sleep (\d+); fi", pj)
    if not mdp or len(atts) != 1 or len(mts) != 1 or len(sls) != 1:
        v.append("probe-budget-unparsed")
    else:
        n = int(next(iter(atts)))
        worst = int(mdp.group(1)) + int(mdp.group(2)) + n * int(mts[0]) + (n - 1) * int(sls[0])
        if worst >= int(st.get("probe", {}).get("timeout-minutes", 0)) * 60:
            v.append("probe-budget")
    return v

def rows_of(job):
    inc = ((job.get("strategy") or {}).get("matrix") or {}).get("include")
    return [r for r in inc if isinstance(r, dict)] if isinstance(inc, list) else []

def matrix_shape(job):
    # strategy is exactly {fail-fast: false, matrix: {include: [two rows]}}; each row has exactly ROW_KEYS, each value a string
    # matching its pattern; the entries are exactly inngest and web1; the job name carries the entry. See ADDING AN ENTRY in the
    # job comment before changing any of this.
    v = []
    st = job.get("strategy") if isinstance(job.get("strategy"), dict) else {}
    if sorted(st.keys()) != ["fail-fast", "matrix"]:
        v.append("matrix-shape:strategy-keys")
    if st.get("fail-fast", True) is not False:          # absent is the default, true
        v.append("matrix-shape:fail-fast")
    mx = st.get("matrix") if isinstance(st.get("matrix"), dict) else {}
    if list(mx.keys()) != ["include"]:
        v.append("matrix-shape:matrix-keys")
    inc = mx.get("include")
    if not isinstance(inc, list) or len(inc) != 2 or not all(isinstance(r, dict) for r in inc):
        v.append("matrix-shape:row-count")
    for r in rows_of(job):
        if sorted(r.keys()) != ROW_KEYS:
            v.append("matrix-shape:row-keys")
        for k, pat in ROW_PAT.items():
            if k in r and not (isinstance(r[k], str) and re.fullmatch(pat, r[k])):
                v.append("matrix-shape:value:" + k)
    if sorted(str(r.get("entry")) for r in rows_of(job)) != ["inngest", "web1"]:
        v.append("matrix-shape:entries")
    if job.get("name") != JOB_NAME:
        v.append("matrix-shape:job-name")
    return v

def id_placement(job, text):
    # Each id appears exactly once in the job's text and in its JSON, and that once is its own row's volume_id: no step
    # (run, env, with, if, name) and no comment names either id.
    v, js = [], json.dumps(job)
    for ent, vid in IDS.items():
        if text.count(vid) != 1 or js.count(vid) != 1:
            v.append("id-placement:count:" + ent)
        own = [r for r in rows_of(job) if r.get("entry") == ent]
        if len(own) != 1 or str(own[0].get("volume_id")) != vid:
            v.append("id-placement:row:" + ent)
        if any(not re.fullmatch(r'\s*volume_id:\s*"?%s"?\s*' % vid, l) for l in text.splitlines() if vid in l):
            v.append("id-placement:outside-row:" + ent)
    for s in job.get("steps", []):
        blob = json.dumps({k: s.get(k) for k in ("run", "env", "with", "if", "name")})
        for ent, vid in IDS.items():
            if vid in blob:
                v.append("id-placement:step:%s:%s" % (s.get("id") or "?", ent))
    return v

def setk(d, k, val):
    d[k] = val
    return d

def mutants():
    def step(j, sid):
        return next(s for s in j["steps"] if s.get("id") == sid)
    def step_first(j):
        return j["steps"][0]
    def drop(d, k):
        d.pop(k, None)
        return d
    def m_reorder(j, t):
        p = step(j, "probe")
        line = next(l for l in p["run"].splitlines() if "doppler secrets get HCLOUD_TOKEN_READONLY" in l)
        p["run"] = p["run"].replace(line + "\n", "") + "\n" + line + "\n"
        return j, t
    def m_url(j, t):
        p = step(j, "probe")
        p["run"] = p["run"].replace("?name=${name}&", "?")
        return j, t
    def m_two_requests(j, t):
        p = step(j, "probe")
        p["run"] = p["run"] + '\nbc_curl scheduled-terraform-drift \'Authorization:Bearer :TOKEN\' -- -sS "$url"\n'
        return j, t
    def m_secret(j, t):
        step(j, "notify")["env"] = {"X": "${{ secrets.DOPPLER_TOKEN_WRITE }}"}
        return j, t
    def row(j, ent):
        return next(r for r in j["strategy"]["matrix"]["include"] if r.get("entry") == ent)
    def m_row(ent, fn):
        def f(j, t):
            fn(row(j, ent))
            return j, t
        return f
    def m_strategy(fn):
        def f(j, t):
            fn(j["strategy"])
            return j, t
        return f
    def m_rename(r, a, b):
        r[b] = r.pop(a)
    def m_pin_literal(j, t):
        p = step(j, "probe")
        p["run"] = p["run"].replace('readonly VOLUME_ID_PIN="$PIN"', "readonly VOLUME_ID_PIN=" + INNGEST_ID)
        return j, t
    return [
        ("environment", "job-environment", lambda j, t: (setk(j, "environment", "infra-privileged"), t)),
        ("loader step", "loader-or-mutable-installer", lambda j, t: (j["steps"].insert(1, {"id": "x", "uses": "./.github/actions/infra-credentials"}) or j, t)),
        ("cli-action", "loader-or-mutable-installer", lambda j, t: (j["steps"].insert(1, {"id": "y", "uses": "DopplerHQ/cli-action@abc"}) or j, t)),
        ("DOPPLER_TOKEN beyond the probe", "doppler-token-outside-probe", lambda j, t: (step(j, "tf_commit").setdefault("env", {}).update({"DOPPLER_TOKEN": "${{ secrets.DOPPLER_TOKEN }}"}) or j, t)),
        ("GH_TOKEN in the probe", "gh-token-outside:probe", lambda j, t: (step(j, "probe")["env"].update({"GH_TOKEN": "${{ github.token }}"}) or j, t)),
        ("read/write token env", "rw-token-env", lambda j, t: (step(j, "file_finding")["env"].update({"HCLOUD_TOKEN": "x"}) or j, t)),
        ("read/write token named in a comment", "rw-token-named", lambda j, t: (j, t + "\n      # HCLOUD_TOKEN fallback\n")),
        ("other secret", "secret:DOPPLER_TOKEN_WRITE", m_secret),
        ("expression in a run body", "expr-in-run:gate", lambda j, t: (setk(step(j, "gate"), "run", step(j, "gate")["run"] + "\necho ${{ github.run_id }}") and j, t)),
        ("set -x", "xtrace:probe", lambda j, t: (setk(step(j, "probe"), "run", "set -x\n" + step(j, "probe")["run"]) and j, t)),
        ("gate continue-on-error", "coe:gate", lambda j, t: (setk(step(j, "gate"), "continue-on-error", True) and j, t)),
        ("filer continue-on-error", "coe:file_finding", lambda j, t: (setk(step(j, "file_finding"), "continue-on-error", True) and j, t)),
        ("gate deleted", "missing-step:gate", lambda j, t: (j.update(steps=[s for s in j["steps"] if s.get("id") != "gate"]) or j, t)),
        ("probe id renamed", "missing-step:probe", lambda j, t: (setk(step(j, "probe"), "id", "probe2") and j, t)),
        ("job if constant false", "job-if", lambda j, t: (setk(j, "if", "false"), t)),
        ("gate loses its exit", "gate-no-exit", lambda j, t: (setk(step(j, "gate"), "run", step(j, "gate")["run"].replace("exit 1", "exit 0")) and j, t)),
        ("filer loses always()", "no-always:file_finding", lambda j, t: (setk(step(j, "file_finding"), "if", "steps.probe.outputs.verdict == 'x'") and j, t)),
        ("token read after the request", "token-read-not-before-request", m_reorder),
        ("fallback read of the read/write name", "rw-token-named", lambda j, t: (setk(step(j, "probe"), "run", step(j, "probe")["run"] + '\nHCLOUD' + '_TOKEN="$(doppler secrets get HCLOUD' + '_TOKEN --plain)"\n') and j, t)),
        ("fail-fast true", "matrix-shape:fail-fast", m_strategy(lambda st: st.update({"fail-fast": True}))),
        ("fail-fast absent (the default is true)", "matrix-shape:fail-fast", m_strategy(lambda st: st.pop("fail-fast"))),
        ("a third row after the two compliant ones", "matrix-shape:row-count", m_strategy(lambda st: st["matrix"]["include"].append(dict(st["matrix"]["include"][-1], entry="web2")))),
        ("a missing row key", "matrix-shape:row-keys", m_row("web1", lambda r: r.pop("adr"))),
        ("a renamed row key", "matrix-shape:row-keys", m_row("web1", lambda r: m_rename(r, "tf_file", "tf_path"))),
        ("a duplicate entry", "matrix-shape:entries", m_row("web1", lambda r: r.update({"entry": "inngest"}))),
        ("an entry outside its pattern", "matrix-shape:value:entry", m_row("web1", lambda r: r.update({"entry": "web1;x"}))),
        ("a subject outside its pattern", "matrix-shape:value:subject", m_row("web1", lambda r: r.update({"subject": "web-1 $(id)"}))),
        ("a tf_file outside its pattern", "matrix-shape:value:tf_file", m_row("web1", lambda r: r.update({"tf_file": "apps/web-platform/infra/../x.tf"}))),
        ("a tf_resource with a metacharacter", "matrix-shape:value:tf_resource", m_row("web1", lambda r: r.update({"tf_resource": 'workspaces_luks"'}))),
        ("a volume_id with a leading zero", "matrix-shape:value:volume_id", m_row("web1", lambda r: r.update({"volume_id": "0" + WEB1}))),
        ("an adr outside its pattern", "matrix-shape:value:adr", m_row("web1", lambda r: r.update({"adr": "ADR-119x"}))),
        ("the job name without the entry", "matrix-shape:job-name", lambda j, t: (setk(j, "name", "sole-copy-protection-check"), t)),
        ("a pin literal in the probe", "id-placement", m_pin_literal),
        ("the web-1 id in a comment", "id-placement", lambda j, t: (j, t + "\n      # " + WEB1 + "\n")),
        ("the Inngest id in a step", "id-placement", lambda j, t: (setk(step(j, "gate"), "name", "gate " + INNGEST_ID) and j, t)),
        ("name filter dropped from the URL", "request-shape", m_url),
        ("method flag on the request", "request-method-or-header-flag", lambda j, t: (setk(step(j, "probe"), "run", step(j, "probe")["run"].replace("-sS --max-time", "-X GET -sS --max-time")) and j, t)),
        ("a second request site", "bc_curl-count", m_two_requests),
        ("job timeout removed", "job-timeout", lambda j, t: (drop(j, "timeout-minutes") and j, t)),
        ("probe step timeout removed", "step-timeout:probe", lambda j, t: (drop(step(j, "probe"), "timeout-minutes") and j, t)),
        ("doppler_cli step timeout removed", "step-timeout:doppler_cli", lambda j, t: (drop(step(j, "doppler_cli"), "timeout-minutes") and j, t)),
        ("tf_commit step timeout removed", "step-timeout:tf_commit", lambda j, t: (drop(step(j, "tf_commit"), "timeout-minutes") and j, t)),
        ("finding filer timeout removed", "step-timeout:file_finding", lambda j, t: (drop(step(j, "file_finding"), "timeout-minutes") and j, t)),
        ("could-not-perform filer timeout removed", "step-timeout:file_unreadable", lambda j, t: (drop(step(j, "file_unreadable"), "timeout-minutes") and j, t)),
        ("clear step timeout removed", "step-timeout:clear", lambda j, t: (drop(step(j, "clear"), "timeout-minutes") and j, t)),
        ("job-level permissions narrowed", "job-permissions", lambda j, t: (setk(j, "permissions", {"contents": "read"}), t)),
        ("checkout persists credentials", "checkout-persist", lambda j, t: (step_first(j)["with"].update({"persist-credentials": True}) or j, t)),
        ("notify action path changed", "notify-uses", lambda j, t: (setk(step(j, "notify"), "uses", "./.github/actions/notify-ops-emailx") and j, t)),
        ("notify loses its key", "notify-with-keys", lambda j, t: (drop(step(j, "notify").setdefault("with", {}), "resend-api-key") and j, t)),
        ("notify key is a literal", "notify-resend-key", lambda j, t: (step(j, "notify")["with"].update({"resend-api-key": "x"}) or j, t)),
        ("a second finish arm with a clean word", "finish-arg:matches-declared", lambda j, t: (setk(step(j, "probe"), "run", step(j, "probe")["run"].replace("*) fetched=1; break ;;", "204) finish matches-declared ;;\n                *) fetched=1; break ;;")) and j, t)),
        ("the EXIT trap removed", "no-exit-trap", lambda j, t: (setk(step(j, "probe"), "run", step(j, "probe")["run"].replace("trap on_exit EXIT\n", "")) and j, t)),
        ("the EXIT trap publishes a clean verdict", "exit-trap-verdict", lambda j, t: (setk(step(j, "probe"), "run", step(j, "probe")["run"].replace("printf 'verdict=could-not-read\\n'", "printf 'verdict=matches-declared\\n'")) and j, t)),
        ("a second verdict writer", "verdict-writer-count", lambda j, t: (setk(step(j, "probe"), "run", step(j, "probe")["run"].replace("trap on_exit EXIT\n", "trap on_exit EXIT\nprintf 'verdict=x\\n' >> \"$GITHUB_OUTPUT\"\n")) and j, t)),
        ("the credential read loses its timeout", "doppler-read-timeout", lambda j, t: (setk(step(j, "probe"), "run", step(j, "probe")["run"].replace("$(timeout -k 5 60 doppler secrets get", "$(doppler secrets get")) and j, t)),
        ("the credential read loses its kill-after", "doppler-read-timeout", lambda j, t: (setk(step(j, "probe"), "run", step(j, "probe")["run"].replace("$(timeout -k 5 60 doppler secrets get", "$(timeout 60 doppler secrets get")) and j, t)),
        ("checkout timeout removed", "step-timeout:checkout", lambda j, t: (drop(step_first(j), "timeout-minutes") and j, t)),
        ("probe back on the implicit success()", "probe-if", lambda j, t: (drop(step(j, "probe"), "if") and j, t)),
        ("the Hetzner request max-time raised past the step budget", "probe-budget", lambda j, t: (setk(step(j, "probe"), "run", step(j, "probe")["run"].replace("-sS --max-time 30", "-sS --max-time 60")) and j, t)),
        ("an echo writer of a clean verdict on the library-load failure path", "output-writer-sites", lambda j, t: (setk(step(j, "probe"), "run", step(j, "probe")["run"].replace('could not be loaded from the job checkout."\n  finish could-not-read', 'could not be loaded from the job checkout."\n  echo verdict=matches-declared >> "$GITHUB_OUTPUT"; published=1; exit 0')) and j, t)),
        ("an echo writer of a clean verdict on the mktemp failure path", "output-writer-sites", lambda j, t: (setk(step(j, "probe"), "run", step(j, "probe")["run"].replace('XXXXXX")" || finish could-not-read', 'XXXXXX")" || { echo verdict=matches-declared >> "$GITHUB_OUTPUT"; published=1; exit 0; }')) and j, t)),
        ("the Doppler token stays in the environment", "doppler-token-not-unset", lambda j, t: (setk(step(j, "probe"), "run", step(j, "probe")["run"].replace("unset DOPPLER_TOKEN\n", "")) and j, t)),
        ("the tarball verification commented out", "doppler-sha-line", lambda j, t: (setk(step(j, "doppler_cli"), "run", step(j, "doppler_cli")["run"].replace('echo "${DOPPLER_CLI_SHA256}', '# echo "${DOPPLER_CLI_SHA256}')) and j, t)),
        ("the tarball verification made optional", "doppler-sha-line", lambda j, t: (setk(step(j, "doppler_cli"), "run", step(j, "doppler_cli")["run"].replace("sha256sum -c -\n", "sha256sum -c - || true\n")) and j, t)),
        ("the PATH hand-off removed", "doppler-path-handoff", lambda j, t: (setk(step(j, "doppler_cli"), "run", step(j, "doppler_cli")["run"].replace('echo "$d" >> "$GITHUB_PATH"\n', "")) and j, t)),
        ("the install curl unbounded", "doppler-curl-bound", lambda j, t: (setk(step(j, "doppler_cli"), "run", step(j, "doppler_cli")["run"].replace(" --connect-timeout 20 --max-time 120", "")) and j, t)),
    ]

def cmd_shape(out, mode):
    job, text = json.load(open(out + "/job.json")), open(out + "/jobtext.txt").read()
    base = violations(job, text)
    if mode == "real":
        for x in base:
            print(x)
        return 0
    print("%s\tcontrol\tthe unmutated job has no violation (%s)" % ("PASS" if not base else "FAIL", ",".join(base) or "none"))
    n = 0
    for name, expect, fn in mutants():
        j, t = fn(copy.deepcopy(job), text)
        landed = json.dumps(j, sort_keys=True) != json.dumps(job, sort_keys=True) or t != text
        got = violations(j, t)
        ok = landed and any(g == expect or g.startswith(expect) for g in got)
        n += 1
        print("%s\t%s\t%s" % ("PASS" if ok else "FAIL", name, ("flagged %s" % expect) if ok else ("mutation did not land" if not landed else "not flagged: wanted %s, got %s" % (expect, got))))
    print("RESULT\t%d" % n)
    return 0

def cmd_run(specpath):
    spec = json.load(open(specpath))
    job = json.load(open(spec["job"]))
    sp = importlib.util.spec_from_file_location("gha_expr", spec["expr"])
    ge = importlib.util.module_from_spec(sp)
    sp.loader.exec_module(ge)
    case = spec["case"]
    os.makedirs(case + "/out", exist_ok=True)
    ctx = {"__job_status": "success"}
    ctx.update({"github." + k: v for k, v in spec["github"].items()})
    ctx.update({"secrets." + k: v for k, v in spec["secrets"].items()})
    # Exactly ONE include row is selected, by entry; zero or several is a harness error, never a guess.
    sel = [r for r in rows_of(job) if r.get("entry") == spec.get("entry")]
    if len(sel) != 1:
        sys.stderr.write("row selection: %d include rows carry entry %r (exactly one is required)\n" % (len(sel), spec.get("entry")))
        sys.exit(3)
    ctx.update({"matrix." + k: (v if isinstance(v, str) else str(v)) for k, v in sel[0].items()})
    declared = [s.get("id") for s in job["steps"] if s.get("id")]
    allowed, results = spec["allowed_outputs"], {}

    def bad(msg):
        sys.stderr.write("unresolvable reference: %s\n" % msg)
        sys.exit(3)

    def check(ref):
        p = ref.split(".")
        if p[0] == "secrets" and (len(p) != 2 or p[1] not in spec["secrets"]):
            bad(ref)
        if p[0] == "github" and ref not in ctx:
            bad(ref)
        if p[0] == "matrix" and (len(p) != 2 or ref not in ctx):
            bad(ref)
        if p[0] == "steps":
            if len(p) < 3 or p[1] not in declared:
                bad(ref)
            if p[2] == "outputs" and (len(p) != 4 or p[3] not in allowed.get(p[1], [])):
                bad(ref)
            if p[2] not in ("outputs", "outcome", "conclusion"):
                bad(ref)

    def refs(e):
        for m in re.finditer(r"(?<![A-Za-z0-9_.\-])((?:secrets|github|steps|matrix)(?:\.[A-Za-z0-9_\-]+)+)", re.sub(r"'(?:[^']|'')*'", "''", e)):
            check(m.group(1))

    def render(v):
        if not isinstance(v, str):
            return str(v)
        def sub(m):
            refs(m.group(1))
            return ge.evaluate("value", m.group(1), ctx)
        return re.sub(r"\$\{\{(.*?)\}\}", sub, v, flags=re.S)

    def evif(cond):
        if cond is None:
            return ge.evaluate("if", "success()", ctx) == "true"
        refs(str(cond))
        return ge.evaluate("if", str(cond), ctx) == "true"

    def read_out(path):
        d, heredoc = {}, False
        if os.path.exists(path):
            for ln in open(path).read().splitlines():
                k = ln.split("=", 1)[0]
                if "<<" in k:
                    heredoc = True
                elif "=" in ln:
                    d[k] = ln.split("=", 1)[1]
        return d, heredoc

    failed = False
    if job.get("if") is not None and ge.evaluate("if", job["if"], ctx) != "true":
        json.dump({"conclusion": "skipped", "entry": sel[0].get("entry"), "steps": {}}, open(case + "/result.json", "w"))
        return 0
    for s in job["steps"]:
        sid = s.get("id") or "anon"
        # A harness override (job_status: cancelled) models a cancelled run, which no stub can produce.
        ctx["__job_status"] = spec.get("job_status") or ("failure" if failed else "success")
        rec = {"ran": False, "outcome": "skipped", "rc": None}
        if evif(s.get("if")):
            rec["ran"] = True
            if "uses" in s:
                rec["outcome"] = "success"
                rec["with"] = {k: render(v) for k, v in (s.get("with") or {}).items()}
            elif sid in spec.get("no_run", []):
                rec["outcome"] = "success"
            else:
                env = dict(spec["base_env"])
                env.update({k: render(v) for k, v in (s.get("env") or {}).items()})
                env.update(spec.get("overrides", {}).get(sid, {}))
                outp = "%s/out/%s" % (case, sid)
                env.update(GITHUB_OUTPUT=outp, GITHUB_ENV=case + "/github_env", GITHUB_PATH=case + "/github_path", GITHUB_STEP_SUMMARY=case + "/summary", STEP_STDOUT="%s/%s.log" % (case, sid))
                body = spec.get("bodies", {}).get(sid) or "%s/steps/%s.sh" % (spec["x"], sid)
                with open(env["STEP_STDOUT"], "wb") as lg:
                    p = subprocess.run(["bash", "--noprofile", "--norc", "-e", body], env=env, stdout=lg, stderr=subprocess.STDOUT, timeout=120)
                rec["rc"] = p.returncode
                rec["outcome"] = "success" if p.returncode == 0 else "failure"
        # A harness override: record this step's outcome as given (e.g. cancelled, which no stub can produce).
        if sid in spec.get("force_outcome", {}):
            rec["outcome"] = spec["force_outcome"][sid]
        if rec["outcome"] == "failure" and not s.get("continue-on-error"):
            failed = True
        ctx["steps.%s.outcome" % sid] = rec["outcome"]
        ctx["steps.%s.conclusion" % sid] = "success" if (rec["outcome"] != "failure" or s.get("continue-on-error")) else "failure"
        outs, heredoc = read_out("%s/out/%s" % (case, sid)) if rec["ran"] else ({}, False)
        rec["heredoc"] = heredoc
        for k, val in outs.items():
            ctx["steps.%s.outputs.%s" % (sid, k)] = val
        results[sid] = rec
    json.dump({"conclusion": "failure" if failed else "success", "entry": sel[0].get("entry"), "steps": results}, open(case + "/result.json", "w"))
    return 0

if __name__ == "__main__":
    c = sys.argv[1]
    sys.exit({"extract": lambda: cmd_extract(*sys.argv[2:5]), "shape": lambda: cmd_shape(sys.argv[2], sys.argv[3]),
              "run": lambda: cmd_run(sys.argv[2])}[c]())
PYH

# ---------------------------------------------------------------------------------------------------------
# EXTRACTION FLOOR: the job and every step the contract names must be found, or nothing below means anything.
# ---------------------------------------------------------------------------------------------------------
_ex=$(python3 -I "$TMP/h.py" extract "$WF" "$JOB" "$TMP/x") || fatal "job '$JOB' not found in $WF (extractor floor: re-point the extractor, never delete the case)"
_ids=$(sed -n 's/.* ids=//p' <<<"$_ex")
_miss=""
for _i in doppler_cli tf_commit probe file_finding file_unreadable clear notify gate; do
  grep -qE "(^|,)${_i}(,|\$)" <<<"$_ids" || _miss+=" $_i"
done
[[ -z "$_miss" ]] || fatal "job '$JOB' lacks step id(s):$_miss (extractor floor)"
jq -e 'type == "array" and ([.[] | objects | .entry] | (index("inngest") != null and index("web1") != null))' "$TMP/x/rows.json" >/dev/null 2>&1 \
  || fatal "job '$JOB' lacks the matrix rows: strategy.matrix.include must carry the entries inngest and web1 (extractor floor; got $(head -c 120 "$TMP/x/rows.json"))"
pass "E1 extractor floor: job $JOB found with probe, tf_commit, doppler_cli, both filers, clear, notify and gate ($(tr ',' ' ' <<<"$_ids" | wc -w | tr -d ' ') steps) and the inngest and web1 include rows"

_e2bad=0
for _s in doppler_cli tf_commit probe file_finding file_unreadable clear gate; do
  _body="$TMP/x/steps/$_s.sh"
  if [[ -s "$_body" ]] && bash -n "$_body" 2>"$TMP/bashn.err"; then :; else _e2bad=1; fail "E2 step $_s: run body missing or does not parse with bash -n ($(head -c 160 "$TMP/bashn.err" 2>/dev/null))"; fi
done
if (( _e2bad == 0 )); then pass "E2 every run body parses with bash -n"; fi

# ---------------------------------------------------------------------------------------------------------
# STATIC SHAPE (Guard 1 rows 2, 12, 13): the real job is clean, and each in-process mutation is flagged.
# ---------------------------------------------------------------------------------------------------------
_sv=$(python3 -I "$TMP/h.py" shape "$TMP/x" real) || fatal "shape check crashed"
if [[ -z "$_sv" ]]; then pass "S1 the job shape is clean: no environment, loader, mutable installer, read/write token, stray secret, expression in a run body, xtrace or continue-on-error beyond notify"
else fail "S1 job shape violations: $(tr '\n' ' ' <<<"$_sv")$(grep -q '^matrix-shape' <<<"$_sv" && printf ' (matrix-shape: see ADDING AN ENTRY in the job comment)')"; fi
_sm=$(python3 -I "$TMP/h.py" shape "$TMP/x" mutants) || fatal "shape mutation table crashed"
_smn=0
while IFS=$'\t' read -r _v _row _msg; do
  [[ "$_v" == "RESULT" ]] && { _smn=$_row; continue; }
  if [[ "$_v" == "PASS" ]]; then pass "S2/$_row: $_msg"; else fail "S2/$_row: $_msg"; fi
done <<<"$_sm"
(( _smn >= 20 )) || fatal "the shape mutation table produced only $_smn rows"
# The job sets no `permissions:` (S1 pins that), so the filers inherit the WORKFLOW-level grant: they need issues: write.
if jq -e '. != null and .contents == "read" and .issues == "write"' "$TMP/x/wfperm.json" >/dev/null 2>&1; then pass "S3 the workflow-level permissions the filers inherit are contents: read and issues: write"
else fail "S3 workflow-level permissions are not contents: read + issues: write ($(head -c 120 "$TMP/x/wfperm.json" 2>/dev/null))"; fi

# ---------------------------------------------------------------------------------------------------------
# STUBS: curl (strict argv model), doppler, gh (stateful issue store), sleep.
# ---------------------------------------------------------------------------------------------------------
cat > "$TMP/bin/curl" <<'STUB' || fatal "write curl stub"
#!/usr/bin/env bash
# Models exactly what scripts/lib/bearer-curl.sh sends: --disable --noproxy '*' <caller args> --config -.
# Any argv it does not model is REFUSED (exit 64) and logged. The name= filter is applied from the URL.
rec="${CURL_REC:?}"
refuse() { printf 'refused: %s\n' "$*" >> "$rec.refused"; exit 64; }
n=$(( $(cat "$rec.n" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$rec.n"
printf '%s\0' "$@" > "$rec.$n.argv"
out=""; wfmt=""; url=""; cfg=0; args=("$@"); i=0
while (( i < ${#args[@]} )); do
  a="${args[$i]}"
  case "$a" in
    --disable|-sS) ;;
    --noproxy) i=$((i + 1)); [[ "${args[$i]:-}" == '*' ]] || refuse "noproxy ${args[$i]:-}" ;;
    --max-time) i=$((i + 1)); [[ "${args[$i]:-}" =~ ^[0-9]+$ ]] && (( args[i] >= 1 && args[i] <= 60 )) || refuse "max-time ${args[$i]:-}" ;;
    -o) i=$((i + 1)); out="${args[$i]:-}" ;;
    -w) i=$((i + 1)); wfmt="${args[$i]:-}" ;;
    --config) i=$((i + 1)); [[ "${args[$i]:-}" == "-" ]] || refuse "config"; cfg=1 ;;
    https://*) url="$a" ;;
    *) refuse "argv $a" ;;
  esac
  i=$((i + 1))
done
[[ "$wfmt" == '%{http_code}' && -n "$out" && "$cfg" == 1 && "$url" == https://api.hetzner.cloud/v1/volumes\?* ]] || refuse "shape url=$url w=$wfmt"
cat > "$rec.$n.stdin"
env > "$rec.$n.env"
printf 'curl %s stdout_bytes=%s url=%s\n' "$n" "$(wc -c < "${STEP_STDOUT:?}")" "$url" >> "$SEQ"
read -ra codes <<<"${CURL_CODES:-200}"
code="${codes[$((n - 1))]:-${codes[${#codes[@]}-1]}}"
if [[ "$code" == "T" ]]; then printf '000'; exit 7; fi
if [[ "$code" == "200" ]]; then
  nm="${url#*name=}"; nm="${nm%%&*}"
  if [[ -n "${CURL_FORCE:-}" ]]; then cat "$CURL_FORCE" > "$out"
  elif [[ -n "${CURL_RAW:-}" ]]; then cat "$CURL_RAW" > "$out"
  elif [[ -n "${CURL_NOFILTER:-}" ]]; then cat "${CURL_LISTING:?}" > "$out"
  else jq -c --arg n "$nm" '.volumes |= map(select(.name == $n)) | .meta.pagination.total_entries = (.volumes | length)' "${CURL_LISTING:?}" > "$out"; fi
else
  printf '{"error":{"code":"stub","message":"stub error"}}' > "$out"
fi
printf '%s' "$code"
STUB
cat > "$TMP/bin/doppler" <<'STUB' || fatal "write doppler stub"
#!/usr/bin/env bash
refuse() { printf 'refused: %s\n' "$*" >> "${SEQ%/*}/doppler.refused"; exit 64; }
[[ "${1:-}" == secrets && "${2:-}" == get && -n "${3:-}" ]] || refuse "argv $*"
nm="$3"; shift 3; plain=0
while (( $# )); do
  case "$1" in
    --plain) plain=1; shift ;;
    -p|--project) [[ "${2:-}" == soleur ]] || refuse "project"; shift 2 ;;
    -c|--config) [[ "${2:-}" == prd_terraform ]] || refuse "config"; shift 2 ;;
    *) refuse "flag $1" ;;
  esac
done
[[ "$plain" == 1 && "${DOPPLER_PROJECT:-}" == soleur && "${DOPPLER_CONFIG:-}" == prd_terraform && -n "${DOPPLER_TOKEN:-}" ]] || refuse "scope"
echo "doppler secrets get $nm" >> "$SEQ"
[[ "${DOPPLER_HANG:-}" == ignore-term ]] && { trap '' TERM; exec "${REAL_SLEEP:?}" 25; }
[[ "${DOPPLER_HANG:-}" == partial ]] && { printf 'partial-read-fragment'; exec "${REAL_SLEEP:?}" 25; }
[[ -n "${DOPPLER_HANG:-}" ]] && exec "${REAL_SLEEP:?}" 25
case "$nm" in
  HCLOUD_TOKEN_READONLY) [[ "${DOPPLER_FIX_RO:-}" == "__absent__" ]] && { echo "Doppler Error: Could not find requested secret" >&2; exit 1; }; printf '%s' "${DOPPLER_FIX_RO:-}" ;;
  HCLOUD_TOKEN) [[ -n "${DOPPLER_FIX_RW:-}" ]] || exit 1; printf '%s' "$DOPPLER_FIX_RW" ;;
  *) refuse "name $nm" ;;
esac
STUB
cat > "$TMP/bin/timeout" <<'STUB' || fatal "write timeout stub"
#!/usr/bin/env bash
# Records the bound the job asked for (and its kill-after, when given), then runs the REAL timeout (optionally with a
# shorter cap so a hang row is fast).
k=""
if [[ "${1:-}" == "-k" ]]; then [[ "${2:-}" =~ ^[0-9]+$ ]] || exit 64; k="$2"; shift 2; fi
[[ "${1:-}" =~ ^[0-9]+$ ]] || exit 64
echo "timeout $1 $2" >> "$SEQ"
if [[ -n "$k" ]]; then echo "timeout-k $k" >> "$SEQ"; fi
d="$1"; shift
if [[ -n "$k" ]]; then exec "${TIMEOUT_REAL:?}" -k "$k" "${TIMEOUT_CAP:-$d}" "$@"; fi
exec "${TIMEOUT_REAL:?}" "${TIMEOUT_CAP:-$d}" "$@"
STUB
cat > "$TMP/bin/sleep" <<'STUB' || fatal "write sleep stub"
#!/usr/bin/env bash
[[ "${1:-}" =~ ^[0-9]+$ ]] || exit 64
echo "sleep $1" >> "$SEQ"
STUB
cat > "$TMP/bin/gh" <<'STUB' || fatal "write gh stub"
#!/usr/bin/env bash
S="${SCEN:?}"; ST="$S/issues.json"
refuse() { printf 'refused: gh %s\n' "$*" >> "$S/gh.refused"; echo "stub gh: unsupported invocation" >&2; exit 64; }
# Like the real gh: an issue command resolves its repository from the checkout's .git, or from GH_REPO when there is none.
if [[ "${1:-}" == issue && ! -e "${GITHUB_WORKSPACE:-/nonexistent}/.git" && -z "${GH_REPO:-}" ]]; then refuse "no repository: no .git in the workspace and no GH_REPO ($*)"; fi
[[ -z "${GH_REPO:-}" || "$GH_REPO" == o/r ]] || refuse "GH_REPO=$GH_REPO"
save() { jq "$@" "$ST" > "$ST.tmp" && mv "$ST.tmp" "$ST"; }
case "${1:-} ${2:-}" in
  "issue list")
    shift 2; label=""; state=""; json=""; lim=30
    while (( $# )); do case "$1" in
      --label) label="$2"; shift 2 ;; --state) state="$2"; shift 2 ;; --limit) [[ "${2:-}" =~ ^[0-9]+$ ]] || refuse "limit"; lim="$2"; shift 2 ;;
      --json) json="$2"; shift 2 ;; *) refuse "issue list $1" ;; esac; done
    [[ "$json" == "number,title" && "$state" == open && -n "$label" ]] || refuse "issue list shape"
    echo "gh issue list" >> "$SEQ"
    [[ -n "${GH_LIST_FAIL:-}" ]] && { echo "stub: HTTP 502" >&2; exit 1; }
    jq -c --arg l "$label" --argjson lim "$lim" '[.[] | select(.state == "open" and (.labels | index($l))) | {number, title}] | reverse | .[0:$lim]' "$ST" ;;
  "issue create")
    shift 2; title=""; ms=""; bf=""; labels=()
    while (( $# )); do case "$1" in
      --title) title="$2"; shift 2 ;; --label) labels+=("$2"); shift 2 ;; --milestone) ms="$2"; shift 2 ;; --body-file) bf="$2"; shift 2 ;;
      *) refuse "issue create $1" ;; esac; done
    [[ -n "$title" && -f "$bf" ]] || refuse "issue create shape"
    for l in "${labels[@]}"; do case "$l" in infra-drift|action-required|priority/p1-high|priority/p2-medium) ;; *) echo "could not add label: '$l' not found" >&2; exit 1 ;; esac; done
    if [[ -n "$ms" ]]; then
      if [[ -n "${GH_NO_MILESTONE:-}" || "$ms" != "Post-MVP / Later" ]]; then echo "could not add to milestone '$ms': not found" >&2; exit 1; fi
    fi
    [[ -n "${GH_CREATE_FAIL:-}" ]] && { echo "stub: HTTP 500" >&2; exit 1; }
    n=$(jq 'map(.number) | (max // 0) + 1' "$ST")
    save --argjson n "$n" --arg t "$title" --argjson l "$(printf '%s\n' "${labels[@]}" | jq -R . | jq -sc .)" --arg m "$ms" --arg b "$(cat "$bf")" \
      --arg a "${GH_BOT_LOGIN:-app/github-actions}" '. + [{number: $n, title: $t, state: "open", labels: $l, milestone: $m, body: $b, author: $a, comments: []}]'
    echo "gh issue create #$n $title" >> "$SEQ"
    echo "https://github.com/o/r/issues/$n"
    [[ -n "${GH_CREATE_THEN_FAIL:-}" ]] && exit 1
    exit 0 ;;
  "issue comment")
    n="${3:-}"; shift 3; body=""
    while (( $# )); do case "$1" in --body) body="$2"; shift 2 ;; --body-file) body="$(cat "$2")"; shift 2 ;; *) refuse "issue comment $1" ;; esac; done
    [[ "$n" =~ ^[0-9]+$ && -n "$body" ]] || refuse "issue comment shape"
    [[ "$(jq -r --argjson n "$n" '.[] | select(.number == $n) | .state' "$ST")" == "closed" ]] && echo "comment on closed #$n" >> "$S/gh.violations"
    save --argjson n "$n" --arg b "$body" 'map(if .number == $n then .comments += [$b] else . end)'
    echo "gh issue comment #$n" >> "$SEQ" ;;
  "issue close")
    n="${3:-}"; shift 3; [[ "$n" =~ ^[0-9]+$ && $# -eq 0 ]] || refuse "issue close"
    save --argjson n "$n" 'map(if .number == $n then .state = "closed" else . end)'
    echo "gh issue close #$n" >> "$SEQ" ;;
  "issue view")
    n="${3:-}"; shift 3; filter=""
    while (( $# )); do case "$1" in --json) [[ "${2:-}" == author ]] || refuse "view json"; shift 2 ;; --jq) filter="$2"; shift 2 ;; *) refuse "issue view $1" ;; esac; done
    echo "gh issue view #$n" >> "$SEQ"
    [[ -n "${GH_VIEW_FAIL:-}" ]] && { echo "stub: HTTP 502" >&2; exit 1; }
    jq -r --argjson n "$n" '.[] | select(.number == $n) | {author: {login: .author}}' "$ST" | jq -r "$filter" ;;
  "api "*|"api")
    shift; ep="${1:-}"; shift; filter=""
    while (( $# )); do case "$1" in --jq) filter="$2"; shift 2 ;; *) refuse "api $1" ;; esac; done
    # Any declaration file under apps/web-platform/infra/; each path is served its OWN answer ($S/api.<file>.json).
    [[ "$ep" =~ ^repos/[^/]+/[^/]+/commits\?.*path=apps/web-platform/infra/([a-z0-9-]+)\.tf(\&|$) && "$ep" == *per_page=1* ]] || refuse "api endpoint $ep"
    pf="${BASH_REMATCH[1]}"
    echo "gh api commits path=$pf" >> "$SEQ"
    [[ -n "${GH_API_HANG:-}" ]] && exec "${REAL_SLEEP:?}" 25
    [[ -f "$S/api.$pf.json" ]] || { echo "stub: HTTP 404" >&2; exit 1; }
    jq -r "$filter" "$S/api.$pf.json" ;;
  *) refuse "$*" ;;
esac
STUB
cat > "$TMP/bin/date" <<'STUB' || fatal "write date shim"
#!/usr/bin/env bash
# A bare `date +%s` answers FAKE_NOW when a row pins the clock (V3b, WV3b: the 89/91-minute boundary must not depend on
# wall-clock drift under host load); every other call, and every call without FAKE_NOW, is the real date.
if [[ $# -eq 1 && "$1" == "+%s" && -n "${FAKE_NOW:-}" ]]; then printf '%s\n' "$FAKE_NOW"; exit 0; fi
exec "${REAL_DATE:?}" "$@"
STUB
chmod +x "$TMP/bin/curl" "$TMP/bin/doppler" "$TMP/bin/sleep" "$TMP/bin/gh" "$TMP/bin/timeout" "$TMP/bin/date" || fatal "chmod stubs"
cp "$LIBREAL" "$TMP/lib/bearer-curl.sh" || fatal "copy library"
cmp -s "$LIBREAL" "$TMP/lib/bearer-curl.sh" || fatal "library copy differs from the repo file"
REAL_PATH="$PATH"
TIMEOUT_REAL=$(command -v timeout) || fatal "timeout not found"
REAL_SLEEP=$(command -v sleep) || fatal "sleep not found"
REAL_DATE=$(command -v date) || fatal "date not found"

# ---------------------------------------------------------------------------------------------------------
# CASE MACHINERY
# ---------------------------------------------------------------------------------------------------------
# PER-ENTRY CONSTANTS: the suite's oracle for each include row, written independently of the workflow (the titles are
# spelled out, never built from the job's rows). use_entry OWNS every one of these names; nothing else assigns them, so a
# row that runs past a former assignment site cannot silently fall back to the other entry's values.
use_entry() { # use_entry inngest|web1
  case "${1-}" in
    inngest)
      ENTRY=inngest
      NAME=soleur-inngest-redis-store-luks
      VOL_ID=106903269
      TF_REL=apps/web-platform/infra/inngest-redis-luks.tf
      TF_RES=inngest_redis_luks
      SUBJ="Inngest store volume"
      ADR_ID=ADR-282
      OTHER_ID=106443278
      OTHER_NAME=soleur-web-platform-data-luks
      OTHER_ENTRY=web1
      TITLE_DIFF="infra: Inngest store volume delete protection differs from Terraform ($NAME)"
      TITLE_GONE="infra: Inngest store volume not found at Hetzner ($NAME)"
      TITLE_NOCRED="infra: the Inngest store volume protection check has no usable credential ($NAME)"
      TITLE_UNREAD="infra: the Inngest store volume protection check could not read Hetzner ($NAME)" ;;
    web1)
      ENTRY=web1
      NAME=soleur-web-platform-data-luks
      VOL_ID=106443278
      TF_REL=apps/web-platform/infra/workspaces-luks.tf
      TF_RES=workspaces_luks
      SUBJ="web-1 workspaces volume"
      ADR_ID=ADR-119
      OTHER_ID=106903269
      OTHER_NAME=soleur-inngest-redis-store-luks
      OTHER_ENTRY=inngest
      TITLE_DIFF="infra: web-1 workspaces volume delete protection differs from Terraform ($NAME)"
      TITLE_GONE="infra: web-1 workspaces volume not found at Hetzner ($NAME)"
      TITLE_NOCRED="infra: the web-1 workspaces volume protection check has no usable credential ($NAME)"
      TITLE_UNREAD="infra: the web-1 workspaces volume protection check could not read Hetzner ($NAME)" ;;
    *) fatal "use_entry: unknown entry '${1-}'" ;;
  esac
  TF_STEM="${TF_REL##*/}"; TF_STEM="${TF_STEM%.tf}"
  OK_KEYS="expected=true|name=$NAME"
}
use_entry inngest
# Each fixture token starts with a distinctive 6-character prefix, so the leak invariant can also catch a PARTIAL token
# (an `echo "${TOKEN:0:6}"` debug line) without matching the ordinary word "synthetic".
TOK="zq7ro-synthetic-ro_token.0123456789"
RWTOK="zq7rw-synthetic-rw_token.9876543210"
DOPTOK="zq7dp-synthetic-doppler_service.token0"
TOKPFX="${TOK:0:6}"; RWPFX="${RWTOK:0:6}"; DOPPFX="${DOPTOK:0:6}"
CANARY="LEAKCANARY_label_zz9"
ALLOWED_OUT='{"probe":["verdict","expected","live","volume_id","http","name","tf_age_min"],"tf_commit":["epoch"],"file_finding":[],"file_unreadable":[],"clear":[],"notify":["sent"],"gate":[],"doppler_cli":[]}'
CASE_N=0; SCEN_N=0; ROWS_RUN=0; CHK=""
NO_RUN='["doppler_cli"]'; GH_REF="refs/heads/main"; JOB_JSON="$TMP/x/job.json"; JOB_STATUS=""; FAKE_NOW=""
STUB_ENV=(); OVR=(); BODIES=(); FORCE=(); EXTRA_ENV=()

# PER-CASE INVARIANTS. A row may run several cases (new_case more than once). The invariants of every case but the last are
# folded in here, before the next case or scenario replaces it, and end_row adds them to the row's own check (H7).
INV_DONE=1; INV_ACC=""
fold_inv() {
  if [[ "$INV_DONE" == 0 && -n "${CASE:-}" && -d "${CASE:-}" ]]; then
    local _sv="$CHK"; CHK=""; invariants; INV_ACC+="$CHK"; CHK="$_sv"
  fi
  INV_DONE=1
}
switch_entry() { fold_inv; use_entry "$1"; }   # every table boundary that changes entry goes through here
new_scen() { fold_inv; SCEN_N=$((SCEN_N + 1)); SCEN="$TMP/scen.$SCEN_N"; mkdir -p "$SCEN" || fatal "mkdir scen"; echo '[]' > "$SCEN/issues.json"; }
vol() { jq -nc --argjson id "$1" --arg n "$2" --argjson p "$3" --arg c "$CANARY" '{id: $id, name: $n, size: 10, status: "available", protection: {delete: $p}, labels: {note: $c}}'; }
listing() { jq -nc '{volumes: ($ARGS.positional | map(fromjson)), meta: {pagination: {page: 1, per_page: 50, previous_page: null, next_page: null, last_page: 1, total_entries: ($ARGS.positional | length)}}}' --args "$@"; }
mk_tf() { # mk_tf <workspace> <name> <declared>  -- a synthesized declaration with the traps the awk must survive
  assert_fixture_dir "${1-}"
  local f="$1/$TF_REL"; assert_fixture_dir "$f"; mkdir -p "$(dirname "$f")" || fatal "mkdir tf"
  cat > "$f" <<TFEOF
# SYNTHESIZED FIXTURE.  # delete_protection = false
resource "random_password" "other" {
  length = 40
}

# name = "not-this-one"
resource "hcloud_volume" "$TF_RES" {
  # delete_protection = false
  name              = "$2"   # trailing comment
  size              = var.inngest_redis_volume_size
  location          = var.location
  delete_protection = $3 # trailing comment

  labels = {
    app = "synthetic"
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "hcloud_volume" "decoy" {
  name              = "decoy"
  delete_protection = false
}
TFEOF
}
set_api() { # set_api <live-true|false>  : the project listing = the target volume + the OTHER entry's real-shaped one
  assert_fixture_dir "${CASE-}"
  listing "$(vol "$VOL_ID" "${CASE_NAME:-$NAME}" "$1")" "$(vol "$OTHER_ID" "$OTHER_NAME" true)" > "$CASE/listing.json"
}
_now() { if [[ -n "${FAKE_NOW:-}" ]]; then printf '%s\n' "$FAKE_NOW"; else date +%s; fi; }
write_age() { # write_age <file-stem> <minutes|none|future>: the commits answer served for that declaration file
  rm -f "$SCEN/api.$1.json"
  local ep
  case "$2" in
    none) return 0 ;;
    future) ep=$(( $(_now) + 7200 )) ;;
    *) ep=$(( $(_now) - $2 * 60 - 10 )) ;;
  esac
  jq -nc --arg d "$(date -u -d "@$ep" +%Y-%m-%dT%H:%M:%SZ)" '[{commit: {committer: {date: $d}}}]' > "$SCEN/api.$1.json"
}
set_age() { AGE_MODE="$1"; write_age "$TF_STEM" "$1"; }   # set_age <minutes|none|future>: the CURRENT entry's file
set_age_other() { # set_age_other <minutes|none|future>: the OTHER entry's file (never the current one's AGE_MODE)
  local _e="$ENTRY" _stem
  use_entry "$OTHER_ENTRY"; _stem="$TF_STEM"; use_entry "$_e"
  write_age "$_stem" "$1"
}
new_case() {
  fold_inv; INV_DONE=0
  CASE_N=$((CASE_N + 1)); CASE="$TMP/c.$CASE_N"
  mkdir -p "$CASE/ws/scripts/lib" "$CASE/ws/.git" "$CASE/rt" "$CASE/out" || fatal "mkdir case"
  cp "$TMP/lib/bearer-curl.sh" "$CASE/ws/scripts/lib/bearer-curl.sh" || fatal "copy library into case"
  SEQ="$CASE/seq.log"; : > "$SEQ"; : > "$CASE/github_env"; : > "$CASE/summary"; : > "$CASE/github_path"
  CHK=""; NO_RUN='["doppler_cli"]'; GH_REF="refs/heads/main"; JOB_JSON="$TMP/x/job.json"; JOB_STATUS=""; STUB_ENV=("${EXTRA_ENV[@]}"); OVR=(); BODIES=(); FORCE=(); WS="$CASE/ws"; CASE_NAME="$NAME"; CODES=200; TOKEN_FIX="$TOK"; RW_FIX=""; CASE_TOK="$TOK"
  [[ -n "${SCEN:-}" ]] || new_scen
  mk_tf "$WS" "$NAME" true; set_api true; set_age 180
}
tf() { mk_tf "$WS" "$1" "$2"; CASE_NAME="$1"; set_api "${LIVE_NOW:-true}"; }
live() { LIVE_NOW="$1"; set_api "$1"; }
raw() { printf '%s' "$1" > "$CASE/raw.json"; STUB_ENV+=("CURL_RAW=$CASE/raw.json"); }
go() {
  local -a e=("PATH=$TMP/bin:$REAL_PATH" "HOME=$CASE" "RUNNER_TEMP=$CASE/rt" "GITHUB_WORKSPACE=$WS" "SEQ=$SEQ" "SCEN=$SCEN" "LC_ALL=C"
    "CURL_LISTING=$CASE/listing.json" "CURL_CODES=$CODES" "CURL_REC=$CASE/curl" "DOPPLER_FIX_RO=$TOKEN_FIX" "DOPPLER_FIX_RW=$RW_FIX"
    "GITHUB_SHA=0000000000000000000000000000000000000000" "GITHUB_RUN_ID=77" "GITHUB_REPOSITORY=o/r" "GITHUB_SERVER_URL=https://github.com"
    "TIMEOUT_REAL=$TIMEOUT_REAL" "REAL_SLEEP=$REAL_SLEEP" "REAL_DATE=$REAL_DATE")
  e+=("${STUB_ENV[@]}")
  local base ovr bod
  base=$(jq -n '[$ARGS.positional[] | capture("^(?<k>[^=]+)=(?<v>.*)$") | {key: .k, value: .v}] | from_entries' --args "${e[@]}")
  ovr=$(printf '%s\n' "${OVR[@]}" | jq -R 'select(length > 0) | capture("^(?<s>[^:]+):(?<k>[^=]+)=(?<v>.*)$")' | jq -s 'reduce .[] as $o ({}; .[$o.s][$o.k] = $o.v)')
  bod=$(printf '%s\n' "${BODIES[@]}" | jq -R 'select(length > 0) | capture("^(?<s>[^=]+)=(?<p>.*)$")' | jq -s 'reduce .[] as $o ({}; .[$o.s] = $o.p)')
  frc=$(printf '%s\n' "${FORCE[@]}" | jq -R 'select(length > 0) | capture("^(?<s>[^=]+)=(?<p>.*)$")' | jq -s 'reduce .[] as $o ({}; .[$o.s] = $o.p)')
  jq -n --arg job "$JOB_JSON" --arg entry "$ENTRY" --arg jst "$JOB_STATUS" --arg expr "$EXPRLIB" --arg case "$CASE" --arg x "$TMP/x" --argjson base "$base" --argjson ovr "$ovr" --argjson bod "$bod" --argjson frc "$frc" \
    --argjson allowed "$ALLOWED_OUT" --arg dop "$DOPTOK" --argjson norun "$NO_RUN" --arg ref "$GH_REF" \
    '{job: $job, entry: $entry, job_status: $jst, expr: $expr, case: $case, x: $x, base_env: $base, overrides: $ovr, bodies: $bod, force_outcome: $frc, allowed_outputs: $allowed, no_run: $norun,
      github: {ref: $ref, token: "synthetic-github-token", repository: "o/r", server_url: "https://github.com", run_id: "77"},
      secrets: {DOPPLER_TOKEN: $dop, RESEND_API_KEY: "synthetic-resend_key"}}' > "$CASE/spec.json" || fatal "write spec"
  local rc=0
  python3 -I "$TMP/h.py" run "$CASE/spec.json" > "$CASE/run.log" 2>&1 || rc=$?
  (( rc == 0 )) || fatal "job runner failed (rc=$rc): $(head -c 300 "$CASE/run.log")"
}
rs() { jq -r --arg s "$1" --arg f "$2" '.steps[$s][$f] | if . == null then "" else tostring end' "$CASE/result.json"; }
a() { [[ "$2" == "$3" ]] || CHK+=$'\n    '"$1: got '$2', want '$3'"; }
want_out() { # want_out "k=v|k=v"  (tf_age_min=N is implied while the age is numeric)
  local want got
  want="$1"; if [[ "$AGE_MODE" =~ ^[0-9]+$ ]]; then want+="|tf_age_min=N"; fi
  want=$(tr '|' '\n' <<<"$want" | LC_ALL=C sort)
  got=$(sed -E 's/^tf_age_min=[0-9]+$/tf_age_min=N/' "$CASE/out/probe" 2>/dev/null | LC_ALL=C sort)
  if [[ "${CMP_MODE:-full}" == "exit" ]]; then return 0; fi
  a "probe outputs" "$(tr '\n' '|' <<<"$got")" "$(tr '\n' '|' <<<"$want")"
}
want_steps() { # want_steps <finding> <unreadable> <clear> <notify> <gate-rc>  (ran|skip)
  local -a names=(file_finding file_unreadable clear notify); local i=0 w g
  for w in "$1" "$2" "$3" "$4"; do
    g=$(rs "${names[$i]}" ran); if [[ "$g" == true ]]; then g=ran; else g=skip; fi
    a "step ${names[$i]}" "$g" "$w"; i=$((i + 1))
  done
  a "gate rc" "$(rs gate rc)" "$5"
}
want_req() { a "requests made" "$(find "$CASE" -maxdepth 1 -name 'curl.*.argv' | wc -l | tr -d ' ')" "$1"; }
invariants() { # the checks every case owes, whatever it asserts
  local f argv url filt
  for f in "$CASE/curl.refused" "$CASE/doppler.refused" "$SCEN/gh.refused" "$SCEN/gh.violations"; do
    if [[ -s "$f" ]]; then CHK+=$'\n    '"stub refusal or violation: $(head -c 160 "$f" | tr '\n' ';')"; fi
  done
  if [[ -s "$CASE/github_env" ]]; then CHK+=$'\n    '"GITHUB_ENV is not empty (a token would persist into later steps)"; fi
  # The selected-entry invariant: the harness ran the include row of THIS case's entry (a no-op use_entry would otherwise turn
  # every web-1 case into a passing Inngest case).
  if [[ -f "$CASE/result.json" ]]; then a "selected include row" "$(jq -r '.entry // "none"' "$CASE/result.json")" "$ENTRY"; fi
  if [[ -f "$CASE/out/probe" ]] && grep -q '<<' "$CASE/out/probe"; then CHK+=$'\n    '"a heredoc-form output reached the probe's GITHUB_OUTPUT"; fi
  for f in "$CASE"/out/* "$CASE"/*.log "$CASE/summary" "$SCEN/issues.json"; do
    [[ -f "$f" ]] || continue
    filt=$(grep -v '^::add-mask::' "$f" || true)
    if grep -qF -e "$TOK" -e "$RWTOK" -e "$DOPTOK" -e "$TOKPFX" -e "$RWPFX" -e "$DOPPFX" -e "$OTHER_ID" -e "$CANARY" <<<"$filt"; then CHK+=$'\n    '"a token (or a 6-character prefix of one), the other volume's id or an API label reached $(basename "$f")"; fi
  done
  # NEITHER volume id may reach an issue title, body or comment (a public, notifying sink), whichever leg filed it.
  if [[ -f "$SCEN/issues.json" ]] && jq -r '.[] | .title, .body, (.comments[]?)' "$SCEN/issues.json" 2>/dev/null | grep -qF -e "$VOL_ID" -e "$OTHER_ID"; then
    CHK+=$'\n    '"a volume id reached an issue title, body or comment"
  fi
  for f in "$CASE"/curl.*.argv; do
    [[ -e "$f" ]] || continue
    argv=$(tr '\0' '\n' < "$f"); url=$(grep '^https://' <<<"$argv" || true)
    a "request URL" "$url" "https://api.hetzner.cloud/v1/volumes?name=${CASE_NAME}&per_page=50"
    if grep -qF -e "$TOK" -e "$RWTOK" -e "$TOKPFX" -e "$RWPFX" <<<"$argv"; then CHK+=$'\n    '"a token is on a request's argument list"; fi
    a "request credential channel" "$(cat "${f%.argv}.stdin")" "header = \"Authorization: Bearer ${CASE_TOK}\""
    if grep -qF -e "$OTHER_NAME" -e "$OTHER_ID" "$f" "${f%.argv}.stdin" "${f%.argv}.env" 2>/dev/null; then CHK+=$'\n    '"a request's argv, stdin or environment carries the other entry's name or id"; fi
  done
  # The commit-time read asks for THIS entry's declaration file, and nothing else.
  local _gp
  while IFS= read -r _gp; do
    [[ -n "$_gp" ]] || continue
    a "commits read path" "$_gp" "gh api commits path=$TF_STEM"
  done < <(grep '^gh api commits' "$SEQ" 2>/dev/null || true)
}
end_row() { invariants; CHK+="$INV_ACC"; INV_ACC=""; INV_DONE=1; ROWS_RUN=$((ROWS_RUN + 1)); if [[ -z "$CHK" ]]; then pass "$1 $2"; else fail "$1 $2$CHK"; fi; }
V="verdict="
warn_has() { grep -qF -- "$1" "$CASE/probe.log" || CHK+=$'\n    '"the warning annotation lacks '$1'"; }
add_unrelated() { # 36 NEWER open infra-drift issues of other titles (gh lists newest first, default limit 30): a list that is not asked for 100 hides the older one
  jq '. + [range(100; 136) | {number: ., title: ("infra: drift detected in web-platform \(.)"), state: "open", labels: ["infra-drift"], milestone: "", body: "", author: "app/github-actions", comments: []}]' "$SCEN/issues.json" > "$SCEN/i.tmp" && mv "$SCEN/i.tmp" "$SCEN/issues.json"
}

# errexit control + SHELLOPTS scrub: run bodies the way the runner does (-e, no pipefail)
printf 'false | true\nfalse\necho survived\n' > "$TMP/selftest.sh"
_pf=$(set -o pipefail; export SHELLOPTS; env -u BASH_ENV -u SHELLOPTS -u BASHOPTS bash --noprofile --norc -e "$TMP/selftest.sh" >/dev/null 2>&1; echo $?)
_ctl=$(set -o pipefail; export SHELLOPTS; bash --noprofile --norc -e "$TMP/selftest.sh" >/dev/null 2>&1; echo $?)
if [[ "$_pf" == 1 && "$_ctl" != 0 ]]; then pass "S0 the runner shell is -e without pipefail: 'false | true' passes, a bare false stops the body, and an exported SHELLOPTS is scrubbed"
else fail "S0 harness shell: scrubbed rc=$_pf (want 1), unscrubbed control rc=$_ctl"; fi
_x=$(python3 "$EXPRLIB" value "steps.probe.outputs.verdict == 'x'" '{}'); _y=$(python3 "$EXPRLIB" if "always() && steps.probe.outputs.verdict != 'a'" '{"__job_status":"failure"}'); _z=$(python3 "$EXPRLIB" if "steps.probe.outputs.verdict == 'a'" '{"__job_status":"failure","steps.probe.outputs.verdict":"a"}')
_mrc=0; python3 "$EXPRLIB" value "matrix.nope" '{}' >/dev/null 2>&1 || _mrc=$?
_mv=$(python3 "$EXPRLIB" value "matrix.entry" '{"matrix.entry":"web1"}' 2>/dev/null) || _mv="rc$?"
if [[ "$_x" == false && "$_y" == true && "$_z" == false && "$_mrc" == 3 && "$_mv" == web1 ]] && ! python3 "$EXPRLIB" if "a === b" '{}' >/dev/null 2>&1; then pass "S0b the expression interpreter: null != 'a' holds under always(), the implicit success() skips after a failure, unknown syntax is a harness error, an unknown matrix key is a harness error (exit 3) and a present one renders"
else fail "S0b interpreter self-test ($_x/$_y/$_z; unknown matrix key rc=$_mrc, want 3; matrix.entry='$_mv', want web1)"; fi

# ---------------------------------------------------------------------------------------------------------
echo "V: the verdict matrix (whole GITHUB_OUTPUT compared; which steps ran; gate exit)"
# ---------------------------------------------------------------------------------------------------------
new_scen
r_matches() { new_case; go; want_out "${V}matches-declared|$OK_KEYS|live=true|volume_id=$VOL_ID|http=200"; want_steps skip skip ran skip 0; a "conclusion" "$(rs gate outcome)" success; }
r_matches; end_row V1 "declared true, live true -> matches-declared: green, no filer, clear step runs, no email"
r_lifted() { new_case; live false; go; want_out "${V}lifted-outside-terraform|$OK_KEYS|live=false|volume_id=$VOL_ID|http=200"; want_steps ran skip skip ran 1; }
r_lifted; end_row V2 "declared true, live false, .tf unchanged for 3 h -> lifted-outside-terraform: finding filer, email, red gate"
new_case; live false; set_age 5; go; want_out "${V}lift-pending-apply|$OK_KEYS|live=false|volume_id=$VOL_ID|http=200"; want_steps skip skip skip skip 0
grep -q '^::warning::' "$CASE/probe.log" || CHK+=$'\n    '"no ::warning:: annotation"; [[ -s "$CASE/summary" ]] || CHK+=$'\n    '"no job-summary line"
warn_has "unprotected at Hetzner until the re-protect change applies"; grep -qF "until the re-protect change applies" "$CASE/summary" || CHK+=$'\n    '"the summary line lacks the verdict-specific text"
end_row V3 "declared true, live false, .tf changed 5 min ago -> lift-pending-apply: green with a warning and a summary line, no issue"
FAKE_NOW=$(date +%s)
new_case; STUB_ENV+=("FAKE_NOW=$FAKE_NOW"); live false; set_age 89; go; a "89 min" "$(sed -n 's/^verdict=//p' "$CASE/out/probe")" lift-pending-apply; _keep="$CHK"
new_case; STUB_ENV+=("FAKE_NOW=$FAKE_NOW"); live false; set_age 91; go; CHK+="$_keep"; a "91 min" "$(sed -n 's/^verdict=//p' "$CASE/out/probe")" lifted-outside-terraform
FAKE_NOW=""
end_row V3b "grace boundary on a pinned clock: 89 minutes is still pending, 91 minutes files (exactly 90 is deliberately NOT pinned)"
for _m in none future; do
  new_case; live false; set_age "$_m"; go; want_out "${V}lifted-outside-terraform|$OK_KEYS|live=false|volume_id=$VOL_ID|http=200"; want_steps ran skip skip ran 1
  end_row V3c "an unreadable (${_m}) .tf commit time fails open to lifted-outside-terraform"
done
new_case; live false; OVR+=("probe:TF_COMMIT_EPOCH=abc"); go; a "non-numeric epoch" "$(sed -n 's/^verdict=//p' "$CASE/out/probe")" lifted-outside-terraform
end_row V3d "a non-numeric TF_COMMIT_EPOCH fails open to lifted-outside-terraform"
new_case; tf "$NAME" false; live false; go; want_out "${V}unprotected-as-declared|expected=false|name=$NAME|live=false|volume_id=$VOL_ID|http=200"; want_steps skip skip skip skip 0
grep -q '^::warning::' "$CASE/probe.log" || CHK+=$'\n    '"no ::warning:: annotation"; [[ -s "$CASE/summary" ]] || CHK+=$'\n    '"no job-summary line"
warn_has "unprotected, as declared"
end_row V4 "declared false, live false (the sanctioned window) -> unprotected-as-declared: quiet, but warned every run"
r_lna() { new_case; tf "$NAME" false; live true; go; want_out "${V}lift-not-applied|expected=false|name=$NAME|live=true|volume_id=$VOL_ID|http=200"; want_steps skip skip skip skip 0; }
r_lna; warn_has "still protected at Hetzner although the declaration says unprotected"; grep -qF "is unprotected or" "$CASE/probe.log" && CHK+=$'\n    '"the warning still says the volume may be unprotected"
end_row V5 "declared false, live true -> lift-not-applied: green with a warning that says the volume IS protected"
vnf_reason() { # vnf_reason <reason>: the cause of volume-not-found is durable in the verdict line and in the job summary
  a "reason in the verdict line" "$(grep -c "^sole-copy-check verdict=volume-not-found .* reason=$1\$" "$CASE/probe.log")" 1
  a "reason in the summary line" "$(grep -c "(reason=$1)" "$CASE/summary")" 1
}
r_empty() { new_case; listing > "$CASE/listing.json"; go; want_out "${V}volume-not-found|$OK_KEYS|http=200"; want_steps ran skip skip ran 1; a "reason" "$(grep -o 'reason=[a-z-]*' "$CASE/probe.log" | head -1)" reason=zero; }
r_empty; vnf_reason zero; end_row V6 "an EMPTY listing is volume-not-found (an empty list is not a clean answer): finding filer, red"
r_two() { new_case; listing "$(vol "$VOL_ID" "$NAME" true)" "$(vol 5 "$NAME" false)" > "$CASE/listing.json"; go; want_out "${V}volume-not-found|$OK_KEYS|http=200"; want_steps ran skip skip ran 1; a "reason" "$(grep -o 'reason=[a-z-]*' "$CASE/probe.log" | head -1)" reason=many; }
r_two; vnf_reason many; end_row V7 "two volumes with the name (first compliant, second not) -> volume-not-found, never a read of the first"
new_case; listing "$(vol 5 "$NAME" true)" > "$CASE/listing.json"; go; want_out "${V}volume-not-found|$OK_KEYS|http=200"; want_steps ran skip skip ran 1
a "reason" "$(grep -o 'reason=[a-z-]*' "$CASE/probe.log" | head -1)" reason=id-mismatch; vnf_reason id-mismatch
end_row V8 "a same-name volume with another id (a planted read-only token in another project) is volume-not-found, never matches-declared"

echo "M: malformed or truncated answers never read as clean (no finding filer, could-not-perform filer, red)"
bad_body() { # bad_body <id> <description> <raw-body> [code]
  new_case; raw "$3"; go
  want_out "${V}could-not-read|$OK_KEYS|http=200"; want_steps skip ran skip skip 1
  end_row "$1" "$2 -> could-not-read"
}
bad_body M1 "next_page non-null" '{"volumes":[],"meta":{"pagination":{"next_page":2}}}'
bad_body M2 "next_page key absent" '{"volumes":[],"meta":{"pagination":{"page":1}}}'
bad_body M3 "meta absent" '{"volumes":[]}'
bad_body M4 "an empty object" '{}'
bad_body M5 "an error object with HTTP 200" '{"error":{"code":"x"}}'
bad_body M6 "a non-array volumes" '{"volumes":{},"meta":{"pagination":{"next_page":null}}}'
bad_body M7 "a non-JSON body" 'not json'
bad_body M8 "a JSON array" '[]'
_v1="$(vol "$VOL_ID" "$NAME" true)"
bad_body M9 "protection.delete null" "$(listing "$(jq -c '.protection.delete = null' <<<"$_v1")")"
bad_body M10 "protection missing" "$(listing "$(jq -c 'del(.protection)' <<<"$_v1")")"
bad_body M11 "protection.delete the string true" "$(listing "$(jq -c '.protection.delete = "true"' <<<"$_v1")")"
bad_body M12 "an id that is a string" "$(listing "$(jq -c '.id = "106903269"' <<<"$_v1")")"
bad_body M13 "an id with a newline" "$(listing "$(jq -c '.id = "106903269\n9"' <<<"$_v1")")"
new_case; STUB_ENV+=("CURL_NOFILTER=1"); listing "$(vol "$VOL_ID" "other-name" true)" > "$CASE/listing.json"; go
want_out "${V}could-not-read|$OK_KEYS|http=200"; want_steps skip ran skip skip 1
end_row M14 "the API answers with a volume whose name is not the one asked for -> could-not-read"
new_case; raw "$(jq -c '. + {extra: {a: 1}, links: []} | .volumes[0] |= (. + {server: null, created: "x"})' <<<"$(listing "$_v1")")"; go
want_out "${V}matches-declared|$OK_KEYS|live=true|volume_id=$VOL_ID|http=200"; want_steps skip skip ran skip 0
end_row M15 "must-pass: extra fields and reordered keys in the body"
new_case; raw '{"meta":{"pagination":{"next_page":null,"page":1}},"volumes":['"$_v1"']}'; go
want_out "${V}matches-declared|$OK_KEYS|live=true|volume_id=$VOL_ID|http=200"; want_steps skip skip ran skip 0
end_row M16 "must-pass: a listing whose next_page is explicitly null, keys reordered"

echo "H: HTTP, retries and credentials"
for _c in 404 500 429; do
  new_case; CODES="$_c"; go
  want_out "${V}could-not-read|$OK_KEYS|http=$_c"; want_steps skip ran skip skip 1
  if [[ "$_c" == 404 ]]; then want_req 1; else want_req 3; a "sleeps" "$(grep -c '^sleep 5$' "$SEQ")" 2; fi
  end_row "H1/$_c" "HTTP $_c -> could-not-read ($( [[ $_c == 404 ]] && echo 'no retry' || echo 'three attempts, 5 s apart'))"
done
new_case; CODES="503 503 200"; go; want_out "${V}matches-declared|$OK_KEYS|live=true|volume_id=$VOL_ID|http=200"; want_steps skip skip ran skip 0; want_req 3
end_row H2 "503, 503, 200 -> retried to a clean answer"
new_case; CODES="T 200"; go; want_out "${V}matches-declared|$OK_KEYS|live=true|volume_id=$VOL_ID|http=200"; want_steps skip skip ran skip 0; want_req 2
end_row H3 "one transport failure then 200 -> retried"
new_case; CODES="T"; go; want_out "${V}could-not-read|$OK_KEYS|http=000"; want_steps skip ran skip skip 1; want_req 3
end_row H4 "transport failure on every attempt -> could-not-read"
for _c in 401 403; do
  new_case; CODES="$_c"; go; want_out "${V}no-token|$OK_KEYS|http=$_c"; want_steps skip ran skip skip 1; want_req 1
  end_row "H5/$_c" "HTTP $_c -> no-token (the could-not-perform filer, red)"
done
new_case; TOKEN_FIX=""; go; want_out "${V}no-token|$OK_KEYS"; want_steps skip ran skip skip 1; want_req 0
a "marker for an EMPTY token" "$(grep -c SOLEUR_CREDENTIAL_REFUSED "$CASE/probe.log")" 0
end_row H6 "an empty token -> no-token with no request and no refusal marker"
new_case; TOKEN_FIX="__absent__"; go; want_out "${V}no-token|$OK_KEYS"; want_steps skip ran skip skip 1; want_req 0
end_row H7 "the secret is absent from the secret store -> no-token"
new_case; TOKEN_FIX='bad token"'; CASE_TOK='bad token"'; go; want_out "${V}no-token|$OK_KEYS"; want_steps skip ran skip skip 1; want_req 0
a "refusal marker" "$(grep -c '^SOLEUR_CREDENTIAL_REFUSED script=scheduled-terraform-drift' "$CASE/probe.log")" 1
end_row H8 "a shape-invalid token -> the library's marker, no-token and no request"
new_case; TOKEN_FIX="__absent__"; RW_FIX="$RWTOK"; go; want_out "${V}no-token|$OK_KEYS"; want_steps skip ran skip skip 1; want_req 0
a "doppler reads" "$(grep -c '^doppler secrets get' "$SEQ")" 1; a "read name" "$(grep '^doppler secrets get' "$SEQ")" "doppler secrets get HCLOUD_TOKEN_READONLY"
end_row H9 "only the read/write token exists: ONE read, of the read-only name; no fallback; no-token and no request"
new_case; go
_mask=$(grep -b '^::add-mask::' "$CASE/probe.log" | head -1 | cut -d: -f1); _first=$(sed -n 's/^curl 1 stdout_bytes=\([0-9]*\) .*/\1/p' "$SEQ")
if [[ -n "$_mask" && -n "$_first" ]] && (( _mask < _first )); then :; else CHK+=$'\n    '"the token was not masked before the first request (mask at ${_mask:-none}, request at ${_first:-none})"; fi
a "doppler line before the request" "$(grep -n -e '^doppler' -e '^curl' "$SEQ" | cut -d: -f2 | cut -d' ' -f1 | tr '\n' ' ')" "doppler curl "
end_row H10 "ordering: the token is read and masked before the first request"

echo "T: the .tf derivation (name and declared flag come from the file)"
for _n in soleur-alpha-store zz9-other-name; do
  new_case; tf "$_n" true; go; want_out "${V}matches-declared|expected=true|name=$_n|live=true|volume_id=$VOL_ID|http=200"; want_steps skip skip ran skip 0
  end_row "T1/$_n" "a different declared name flows into the request URL and the outputs (a hard-coded name would red)"
done
new_case; sed -i 's/^  delete_protection = true # trailing comment$/  delete_protection = false # was true/' "$WS/$TF_REL"; live false; go
want_out "${V}unprotected-as-declared|$(sed 's/true/false/' <<<"$OK_KEYS")|live=false|volume_id=$VOL_ID|http=200"
end_row T2 "a trailing comment and a commented-out opposite value are ignored (declared false read through them)"
tf_bad() { # tf_bad <id> <description> <sed-expression> [<expected ::error:: text>]
  new_case; mk_tf "$CASE/ref" "$NAME" true
  sed -i "$3" "$WS/$TF_REL"
  if cmp -s "$WS/$TF_REL" "$CASE/ref/$TF_REL"; then CHK+=$'\n    '"the mutation did not land"; fi
  go; want_out "${V}could-not-read"; want_steps skip ran skip skip 1; want_req 0
  if [[ -n "${4:-}" ]]; then grep -qF -e "$4" "$CASE/probe.log" || CHK+=$'\n    '"the ::error:: text lacks '$4'"; fi
  end_row "$1" "$2 -> could-not-read with no request"
}
tf_bad T3 "the resource renamed" 's/"inngest_redis_luks" {/"inngest_redis_luks_x" {/'
tf_bad T4 "delete_protection = var.x" 's/^  delete_protection = true.*$/  delete_protection = var.x/'
tf_bad T5 "a duplicated delete_protection" 's/^  location .*$/&\n  delete_protection = true/'
tf_bad T6 "name only inside labels" '/^  name  *= "soleur/d; s/app = "synthetic"/name = "other"/'
tf_bad T7 "no own delete_protection, only the next resource's decoy" '/^  delete_protection = true/d'
tf_bad T8 "an invalid name (uppercase)" 's/^  name  *= "[^"]*"/  name = "BAD_Name"/'
tf_bad T10 "a BLOCK-commented delete_protection = true on its own lines (Terraform would apply the default false)" 's|^  delete_protection = true.*$|  /*\n  delete_protection = true\n  */|' "a block-comment opener '/*' anywhere in the file"
tf_bad T11 "a block-commented decoy resource of the real name placed before the real one" 's|^resource "hcloud_volume" "inngest_redis_luks" {|/*\nresource "hcloud_volume" "inngest_redis_luks" {\n  name = "decoy"\n  delete_protection = false\n}\n*/\n&|'
new_case; ( cat >> "$WS/$TF_REL" <<< $'resource "hcloud_volume" "decoy2" {\n  delete_protection = false\n}' ); go
want_out "${V}matches-declared|$OK_KEYS|live=true|volume_id=$VOL_ID|http=200"
end_row T9 "a decoy delete_protection = false in a LATER resource does not leak into the block (bounded at its closing brace)"

echo "R: the real declaration file (independent derivation)"
_ind=$(python3 -I - "$TFREAL" <<'PYR'
import re, sys
t = open(sys.argv[1]).read()
m = re.search(r'resource\s+"hcloud_volume"\s+"inngest_redis_luks"\s*\{', t)
i, d, out = m.end(), 1, []
while d:
    c = t[i]
    d += (c == "{") - (c == "}")
    out.append(c)
    i += 1
blk, depth, top = "".join(out), 0, []
for ln in blk.splitlines():
    code = re.sub(r"\s*#.*$", "", ln)
    if depth == 0:
        top.append(code)
    depth += code.count("{") - code.count("}")
name = re.search(r'^\s*name\s*=\s*"([^"]+)"', "\n".join(top), re.M).group(1)
dp = re.search(r"^\s*delete_protection\s*=\s*(true|false)\s*$", "\n".join(top), re.M).group(1)
print("%s %s" % (name, dp))
PYR
) || fatal "independent derivation of the real .tf failed"
read -r _rname _rexp <<<"$_ind"
new_case; WS="$REPO_ROOT"; CASE_NAME="$_rname"; set_api "$_rexp"; go
_rverd=matches-declared; if [[ "$_rexp" == false ]]; then _rverd=unprotected-as-declared; fi
want_out "${V}${_rverd}|expected=$_rexp|name=$_rname|live=$_rexp|volume_id=$VOL_ID|http=200"
end_row R1 "the probe on the REAL checkout derives '$_rname' and declared=$_rexp exactly as an independent derivation does (never the literal)"
for _mut in rename var dup; do
  new_case; assert_fixture_dir "${WS-}"; _tf="$WS/$TF_REL"; assert_fixture_dir "$_tf"; mkdir -p "$(dirname "$_tf")"; cp "$TFREAL" "$_tf"
  case "$_mut" in
    rename) sed -i 's/resource "hcloud_volume" "inngest_redis_luks" {/resource "hcloud_volume" "inngest_redis_luks_x" {/' "$_tf" ;;
    var) sed -i '/^resource "hcloud_volume" "inngest_redis_luks" {/,/^}/ s/^  delete_protection = .*/  delete_protection = var.x/' "$_tf" ;;
    dup) sed -i '/^resource "hcloud_volume" "inngest_redis_luks" {/,/^}/ s/^  location .*/&\n  delete_protection = true/' "$_tf" ;;
  esac
  cmp -s "$_tf" "$TFREAL" && CHK+=$'\n    '"the mutation did not land"
  go; want_out "${V}could-not-read"; want_req 0
  end_row "R2/$_mut" "a mutant of the REAL file ($_mut) -> could-not-read, no request"
done

# ---------------------------------------------------------------------------------------------------------
echo "F: filers, lifecycle, partial failures (a stateful issue store; the whole job is run)"
# ---------------------------------------------------------------------------------------------------------
issues() { jq -r "$1" "$SCEN/issues.json"; }
new_scen
new_case; live false; go
a "issues filed" "$(issues 'length')" 1; a "title" "$(issues '.[0].title')" "$TITLE_DIFF"
a "labels" "$(issues '.[0].labels | sort | join(",")')" "action-required,infra-drift,priority/p1-high"; a "milestone" "$(issues '.[0].milestone')" "Post-MVP / Later"
a "body names the ADR" "$(issues '.[0].body' | grep -c 'ADR-282')" 1; a "body names the runbook heading" "$(issues '.[0].body' | grep -c 'Sole-copy protection and key loss')" 1
a "email subject" "$(jq -r '.steps.notify.with.subject' "$CASE/result.json" | grep -c '^\[INFRA')" 1; a "email body names the verdict" "$(jq -r '.steps.notify.with.body' "$CASE/result.json" | grep -c 'lifted-outside-terraform')" 1
a "email body names the finding filer outcome" "$(jq -r '.steps.notify.with.body' "$CASE/result.json" | grep -c 'finding filer <code>success</code>, could-not-perform filer <code>skipped</code>')" 1
a "resend-api-key renders to the secret" "$(jq -r '.steps.notify.with["resend-api-key"]' "$CASE/result.json")" synthetic-resend_key
FB=$(issues '.[0].body')
a "remedy names the 5c row and the runbook file" "$(grep -c 'table row `not-protected` in inngest-luks-cutover-6894.md' <<<"$FB")" 1; a "remedy names the dispatch" "$(grep -c '`manual-rerun` dispatch' <<<"$FB")" 1; a "remedy names the read-back" "$(grep -c 'read back `protected`' <<<"$FB")" 1
a "the decision line, exactly" "$(grep -cxF 'Decision record: ADR-282. Loss modes and the reviewed route: the runbook section "Sole-copy protection and key loss" in inngest-luks-cutover-6894.md.' <<<"$FB")" 1
a "email subject, exactly" "$(jq -r '.steps.notify.with.subject' "$CASE/result.json")" "[INFRA DRIFT] Inngest store volume protection check needs attention"
a "email body names the volume" "$(jq -r '.steps.notify.with.body' "$CASE/result.json" | grep -c '<strong>The twice-daily Inngest store volume protection check needs attention.</strong>')" 1
a "email body names the ADR" "$(jq -r '.steps.notify.with.body' "$CASE/result.json" | grep -c 'carries the facts and the pointers (ADR-282)')" 1
end_row F1 "first lifted run: ONE p1 issue with the exact title, labels, milestone, public-safe pointers and an actionable remedy; email subject, body (with the filer outcomes) and key rendered"
new_case; live false; go
a "issues after the second run" "$(issues 'length')" 1; a "comments" "$(issues '.[0].comments | length')" 1
a "comment is one line" "$(issues '.[0].comments[0]' | grep -c .)" 1
_c0=$(issues '.[0].comments[0]')
a "comment carries the run URL" "$(grep -c 'Run https://github.com/o/r/actions/runs/77:' <<<"$_c0")" 1; a "comment carries declared and live" "$(grep -c 'declared true; live false;' <<<"$_c0")" 1
a "comment carries the HTTP code" "$(grep -c 'HTTP 200\.$' <<<"$_c0")" 1
end_row F2 "second run while the condition holds: a one-line comment on the SAME issue, no duplicate"
new_case; go
a "cleared comment" "$(issues '.[0].comments | length')" 2; a "state" "$(issues '.[0].state')" closed
a "clear comment text" "$(issues '.[0].comments[1]' | grep -c 'cleared in run https://github.com/o/r/actions/runs/77: live equals declared')" 1
end_row F3 "a matches-declared run comments 'cleared in run' and closes the bot-authored issue"
new_case; live false; go
a "a closed issue is replaced, not reopened or commented" "$(issues 'length')" 2; a "new issue state" "$(issues '.[1].state')" open
end_row F4 "the condition returns after the issue was closed: a NEW issue, never a comment on the closed one"
save_state() { jq --arg a "$1" --argjson n "$2" 'map(if .number == $n then .author = $a else . end)' "$SCEN/issues.json" > "$SCEN/i.tmp" && mv "$SCEN/i.tmp" "$SCEN/issues.json"; }
save_state deruelle 2
new_case; go
a "human-authored issue is NOT commented (no comment every 12 h)" "$(issues '.[1].comments | length')" 0; a "and NOT closed" "$(issues '.[1].state')" open
a "a notice names it" "$(grep -c '^::notice::#2 was not opened by this workflow' "$CASE/clear.log")" 1
_keep="$CHK"; new_case; go; CHK+="$_keep"
a "still not commented after a second clean run" "$(issues '.[1].comments | length')" 0
end_row F5 "a human-authored open issue with the same title is neither commented nor closed on a clean run (a notice only, run after run)"
new_scen; new_case; CODES=500; go
a "title" "$(issues '.[0].title')" "$TITLE_UNREAD"; a "priority" "$(issues '.[0].labels | index("priority/p2-medium") != null')" true
a "no claim about the volume" "$(issues '.[0].body' | grep -ci 'protection is\|is protected\|is unprotected')" 0
want_steps skip ran skip skip 1
end_row F6 "HTTP 500 after retries: a p2 could-not-read issue, no email, red gate"
new_case; CODES=500; go; a "one issue" "$(issues 'length')" 1; a "comment per run" "$(issues '.[0].comments | length')" 1
end_row F7 "the outage persists: one comment per run, a stale issue cannot mask a changed signal"
new_case; CODES=401; go
a "second title, a new issue" "$(issues 'length')" 2; a "title" "$(issues '.[1].title')" "$TITLE_NOCRED"
a "points at step O5" "$(issues '.[1].body' | grep -c 'infra-credential-tiers-8209.md')" 1; a "names the DOPPLER_TOKEN scope" "$(issues '.[1].body' | grep -c 'DOPPLER_TOKEN')" 1
a "says O5 is operator-only and an agent stops" "$(issues '.[1].body' | grep -c 'Step O5 is operator-only.*an agent reports this issue and stops')" 1
end_row F8 "no-token files under its OWN title, naming step O5 and the DOPPLER_TOKEN scope, so an old outage does not hide it"
new_case; go
a "both could-not-perform issues closed by a clean run" "$(issues '[.[] | select(.state == "open")] | length')" 0
end_row F9 "a clean run clears both could-not-perform issues (bot-authored)"
new_scen
new_case; BODIES+=("probe=$TMP/exit1.sh"); printf 'exit 1\n' > "$TMP/exit1.sh"; go
a "an EMPTY verdict files the could-not-perform issue" "$(issues 'length')" 1; a "title" "$(issues '.[0].title')" "infra: the Inngest store volume protection check could not read Hetzner (name-unreadable)"
want_steps skip ran skip skip 1; a "no finding on a crash" "$(rs file_finding ran)" false
a "a (name-unreadable) title says no volume name could be read" "$(issues '.[0].body' | grep -c 'no volume name could be read from the declaration')" 1
end_row F10 "a probe that crashed (no verdict at all) still files and the gate is red: the complement of every other verdict set"
new_case; BODIES+=("probe=$TMP/bogus.sh"); printf 'echo verdict=bogus >> "$GITHUB_OUTPUT"\n' > "$TMP/bogus.sh"; go
want_steps skip ran skip skip 1
end_row F11 "an UNKNOWN verdict files the could-not-perform issue and the gate is red"
# Rendered bodies: only the named dynamic fields may differ between two renders, and no recipe vocabulary.
# The dispatch is named (`manual-rerun`) and never spelled: no gh, no `workflow run`, no apply_target, no -f key=value input, no apply workflow file.
recipe_vocab() { grep -qiE '\b(curl|hcloud|doppler|wget|gh)\b|workflow run|apply_target|-f [a-z_]+=|apply-[a-z0-9-]*\.yml|sole copy|only copy|106903269|106443278| -X |--request|change_protection|detach' <<<"$1" || grep -qE '\b(DELETE|PUT|POST|PATCH)\b' <<<"$1"; }
render_body() { # render_body <verdict> <suffix>: the probe is replaced by a body publishing these outputs, the REAL filers run
  new_scen; new_case
  printf 'printf "verdict=%%s\\nname=zzn%s\\nexpected=true\\nlive=false\\nhttp=40%s\\ntf_age_min=77%s\\n" "%s" >> "$GITHUB_OUTPUT"\n' "$2" "$2" "$2" "$1" > "$TMP/probe-$2.sh"
  BODIES+=("probe=$TMP/probe-$2.sh"); go; issues '.[0].body'
}
for _vd in lifted-outside-terraform volume-not-found no-token could-not-read; do
  _b1=$(render_body "$_vd" 1); _b2=$(render_body "$_vd" 2)
  _n1=$(sed -e 's/zzn1/@/g; s/401/@/g; s/771/@/g' <<<"$_b1" | sed -E 's|actions/runs/[0-9]+|@|'); _n2=$(sed -e 's/zzn2/@/g; s/402/@/g; s/772/@/g' <<<"$_b2" | sed -E 's|actions/runs/[0-9]+|@|')
  if [[ -z "$_b1" ]]; then CHK+=$'\n    '"no body was filed"; fi
  if [[ "$_n1" != "$_n2" ]]; then CHK+=$'\n    '"the body differs in more than the named fields"; fi
  if ! grep -q -e 'zzn1' -e 'HTTP code: 401' <<<"$_b1"; then CHK+=$'\n    '"neither the volume name nor the HTTP code is in the body (the render did not reach the filer)"; fi
  if recipe_vocab "$_b1"; then CHK+=$'\n    '"the body holds recipe vocabulary or the Hetzner id"; fi
  end_row "F12/$_vd" "the rendered filer body has only the named dynamic fields and no recipe vocabulary"
done
CHK=""; _inj_ok=1
for _inj in 'curl -sS -X DELETE https://api.hetzner.cloud/v1/volumes/1' 'hcloud volume detach 1' 'doppler secrets delete X' 'volume 106903269' 'volume 106443278' 'the only copy' \
  'Run gh workflow run apply-web-platform-infra.yml -f apply_target=manual-rerun.' 'gh issue close 3' 'then workflow run it' 'apply_target=manual-rerun' \
  'pass -f reason=x' 'the file apply-web-platform-infra.yml'; do
  recipe_vocab "$_b1"$'\n'"$_inj" || { _inj_ok=0; echo "    not flagged: $_inj"; }
done
recipe_vocab "$_b1" && _inj_ok=0
recipe_vocab "$_b1"$'\n'"the owner-approved manual-rerun dispatch of the per-merge apply" && { _inj_ok=0; echo "    the dispatch NAME alone must pass"; }
a "injected recipe lines are flagged and the real body is not" "$_inj_ok" 1
end_row F13 "the body checker flags an injected delete/detach/credential/id line and passes the real body"
echo "P: partial failures"
new_scen; new_case; live false; STUB_ENV+=("GH_CREATE_THEN_FAIL=1"); go
want_steps ran skip skip ran 1; a "filer outcome" "$(rs file_finding outcome)" failure; a "issue exists" "$(issues 'length')" 1
a "email body names the FAILED finding filer" "$(jq -r '.steps.notify.with.body' "$CASE/result.json" | grep -c 'finding filer <code>failure</code>')" 1
end_row P1 "gh issue create succeeds then the step exits non-zero: the step is red, the gate is red and the email fires"
new_case; live false; go; a "no duplicate on the next run" "$(issues 'length')" 1; a "commented" "$(issues '.[0].comments | length')" 1
end_row P2 "the next run finds the half-created issue and comments (no duplicate)"
new_scen; new_case; live false; STUB_ENV+=("GH_CREATE_FAIL=1"); go
want_steps ran skip skip ran 1; a "nothing filed" "$(issues 'length')" 0
end_row P3 "the filer fails outright: red gate, email fires"
new_scen; new_case; live false; STUB_ENV+=("GH_NO_MILESTONE=1"); go
a "filed without the milestone" "$(issues 'length')" 1; a "milestone" "$(issues '.[0].milestone')" ""; a "step" "$(rs file_finding outcome)" success
end_row P4 "a missing milestone: the p1 still files, without it"
new_scen; new_case; live false; STUB_ENV+=("GH_LIST_FAIL=1"); go
a "nothing created on a list failure" "$(issues 'length')" 0; a "step red" "$(rs file_finding outcome)" failure; want_steps ran skip skip ran 1
end_row P5 "gh issue list fails: nothing is created (no duplicate), the step is red, the gate is red"

echo "L: leakage, scope and ordering"
new_case; live false; go
a "request count" "$(find "$CASE" -maxdepth 1 -name 'curl.*.argv' | wc -l | tr -d ' ')" 1
end_row L1 "the stub's listing carried a label canary, the other volume's id and a token: none reached a stream, an output, the summary or an issue (see the invariants)"
new_case; STUB_ENV+=("CURL_NOFILTER=1"); go
a "unfiltered listing is not a clean answer" "$(sed -n 's/^verdict=//p' "$CASE/out/probe")" volume-not-found
end_row L2 "with the name= filter dropped the stub serves the unfiltered listing (the other volume among them) -> volume-not-found, proving the filter is what excludes it"

new_case; raw "not json $CANARY $TOK $RWTOK $OTHER_ID"; go
want_out "${V}could-not-read|$OK_KEYS|http=200"; want_steps skip ran skip skip 1
end_row L3 "a malformed body carrying a label, both tokens and the other volume's id is never echoed, filed or published"

# ---------------------------------------------------------------------------------------------------------
echo "X: bounds, the EXIT trap, wiring, title lifecycle, rendered fields, the validators (review round)"
# ---------------------------------------------------------------------------------------------------------
new_scen; new_case; STUB_ENV+=("DOPPLER_HANG=1" "TIMEOUT_CAP=2"); _t0=$SECONDS; go; _el=$((SECONDS - _t0))
want_out "${V}could-not-read|$OK_KEYS"; want_steps skip ran skip skip 1; want_req 0
a "the job asked for a 60 s bound on the read" "$(grep -c '^timeout 60 doppler$' "$SEQ")" 1
a "with a 5 s kill-after" "$(grep -c '^timeout-k 5$' "$SEQ")" 1
a "the error names the timeout" "$(grep -c '^::error::sole_copy_probe_doppler_timeout' "$CASE/probe.log")" 1
a "it does not say the credential is missing" "$(grep -c 'has no Hetzner Read token' "$CASE/probe.log")" 0
a "the could-not-perform body does not send the reader to the operator-only credential step" "$(issues '.[0].body' | grep -c 'Step O5 is operator-only')" 0
if (( _el < 2 || _el > 20 )); then CHK+=$'\n    '"the hanging read took ${_el}s; want 2..20 (the bound is not applied)"; fi
end_row X1 "a credential read that hangs is cut by timeout and reads as could-not-read, not no-token (a bounded wait; the outage is not filed as a missing credential)"
new_case; TOKEN_FIX="__absent__"; go
want_out "${V}no-token|$OK_KEYS"; want_steps skip ran skip skip 1; want_req 0
a "a fast failure is not a timeout" "$(grep -c 'sole_copy_probe_doppler_timeout' "$CASE/probe.log")" 0
a "it says the credential is missing" "$(grep -c '^::error::sole-copy-check has no Hetzner Read token' "$CASE/probe.log")" 1
end_row X1b "a credential read that fails fast (non-zero rc, empty) is still no-token: both sides of the timeout split are fixtured"
new_case; STUB_ENV+=("DOPPLER_HANG=ignore-term" "TIMEOUT_CAP=2"); _t0=$SECONDS; go; _el=$((SECONDS - _t0))
want_out "${V}could-not-read|$OK_KEYS"; want_steps skip ran skip skip 1; want_req 0
a "the error names the timeout (the kill-after path, rc 137)" "$(grep -c '^::error::sole_copy_probe_doppler_timeout' "$CASE/probe.log")" 1
if (( _el < 5 || _el > 15 )); then CHK+=$'\n    '"the read that ignores SIGTERM took ${_el}s; want 5..15 (the kill-after is not applied)"; fi
end_row X1c "a credential read that ignores SIGTERM is killed after the 5 s kill-after (rc 137) and still reads as could-not-read"
new_case; STUB_ENV+=("DOPPLER_HANG=partial" "TIMEOUT_CAP=2"); go
want_out "${V}could-not-read|$OK_KEYS"; want_steps skip ran skip skip 1; want_req 0
a "a read that printed a fragment and then stalled is a timeout, not a credential" "$(grep -c '^::error::sole_copy_probe_doppler_timeout' "$CASE/probe.log")" 1
a "it does not say the credential is missing" "$(grep -c 'has no Hetzner Read token' "$CASE/probe.log")" 0
end_row X1d "a credential read that printed part of a value and then stalled is still a timeout (rc 124), never graded on the fragment"
new_case; go
a "the request process never sees the Doppler token" "$(grep -c '^DOPPLER_TOKEN=' "$CASE/curl.1.env")" 0
a "control: the request environment was captured" "$(grep -c '^DOPPLER_PROJECT=soleur$' "$CASE/curl.1.env")" 1
end_row X2 "the Doppler token is unset right after its single read"
new_scen; new_case; set_age none; sed 's/^trap on_exit EXIT$/&\nkill -TERM $$/' "$TMP/x/steps/probe.sh" > "$CASE/probe-kill.sh"
a "the injected kill landed" "$(grep -c '^kill -TERM \$\$$' "$CASE/probe-kill.sh")" 1
BODIES+=("probe=$CASE/probe-kill.sh"); go
want_out "${V}could-not-read"; want_steps skip ran skip skip 1
a "the trap said so in the log" "$(grep -c 'probe ended without a verdict' "$CASE/probe.log")" 1
end_row X3 "the REAL probe terminated after its trap is set (a runner cancel or timeout): the EXIT trap publishes could-not-read, never clean"
new_scen; new_case; CODES=500; STUB_ENV+=("GH_LIST_FAIL=1"); go
want_steps skip ran skip ran 1; a "filer outcome" "$(rs file_unreadable outcome)" failure
a "email body names the failed could-not-perform filer" "$(jq -r '.steps.notify.with.body' "$CASE/result.json" | grep -c 'could-not-perform filer <code>failure</code>')" 1
end_row X4 "the could-not-perform filer fails: the email fires and names it (a dead issue channel is not silent)"
new_scen; new_case; live false; set_age 5; AGE_MODE=none; STUB_ENV+=("GH_API_HANG=1" "TIMEOUT_CAP=2"); _t0=$SECONDS; go; _el=$((SECONDS - _t0))
a "the commit-time read was bounded at 30 s" "$(grep -c '^timeout 30 gh$' "$SEQ")" 1
a "the step still succeeded" "$(rs tf_commit outcome)" success; a "the probe still ran" "$(rs probe ran)" true
want_out "${V}lifted-outside-terraform|$OK_KEYS|live=false|volume_id=$VOL_ID|http=200"; want_steps ran skip skip ran 1
if (( _el < 2 || _el > 20 )); then CHK+=$'\n    '"the hanging commit-time read took ${_el}s; want 2..20 (the bound is not applied)"; fi
end_row X18 "a commit-time read that hangs is cut by timeout 30, the step exits 0 and the probe runs with an unknown age: a lifted flag files (fail open)"
new_scen; new_case; live false; set_age 5; AGE_MODE=none; printf 'exit 1\n' > "$TMP/exit1.sh"; BODIES+=("tf_commit=$TMP/exit1.sh"); go
a "the commit-time step failed" "$(rs tf_commit outcome)" failure; a "the probe still ran (no implicit success())" "$(rs probe ran)" true
want_out "${V}lifted-outside-terraform|$OK_KEYS|live=false|volume_id=$VOL_ID|http=200"; want_steps ran skip skip ran 1
end_row X19 "the commit-time step itself fails: the probe still runs with an unknown age and a lifted flag files (the age lookup is fail open, never a skipped probe)"
new_scen; new_case; live false; go
new_case; STUB_ENV+=("GH_VIEW_FAIL=1"); go
a "the clear step is red" "$(rs clear outcome)" failure; a "the issue is still open" "$(issues '.[0].state')" open
a "and not commented on" "$(issues '.[0].comments | length')" 0
a "the error names the cause" "$(grep -c '^::error::sole_copy_clear_author_lookup_failed' "$CASE/clear.log")" 1
a "an unreadable author is not reported as 'not opened by this workflow'" "$(grep -c 'was not opened by this workflow' "$CASE/clear.log")" 0
want_steps skip skip ran ran 0
a "the email names the failed clear step" "$(jq -r '.steps.notify.with.body' "$CASE/result.json" | grep -c 'clear step <code>failure</code>')" 1
end_row X20 "the author lookup fails on a clean run: the clear step is red, the issue is left open and uncommented, and the email fires (a stale open issue behind a green gate is not silent)"
_acc=""
for _fs in file_finding file_unreadable clear; do
  for _fo in failure cancelled; do
    new_scen; new_case; CODES=500; FORCE+=("$_fs=$_fo"); go
    a "$_fs recorded as $_fo: notify fires although the verdict alone would not" "$(rs notify ran)" true
    _acc+="$CHK"
  done
done
new_scen; new_case; CODES=500; go; a "control: nothing forced, no email on a could-not-read verdict" "$(rs notify ran)" false
CHK+="$_acc"
end_row X21 "notify's failed or cancelled terms for each filer and for the clear step are each load-bearing (a harness override records the outcome; a control without it sends no email)"
new_scen; new_case; listing > "$CASE/listing.json"; go
a "vnf title" "$(issues '.[0].title')" "$TITLE_GONE"; a "vnf labels" "$(issues '.[0].labels | sort | join(",")')" "action-required,infra-drift,priority/p1-high"
a "reason pointer" "$(issues '.[0].body' | grep -c 'names the reason (zero, many or id-mismatch)')" 1
a "incident route" "$(issues '.[0].body' | grep -c 'soleur:incident')" 1; a "total loss section, in the named runbook file" "$(issues '.[0].body' | grep -c 'After a total loss.* in inngest-luks-cutover-6894.md')" 1
a "confirm before escalating" "$(issues '.[0].body' | grep -c '^Confirm the Hetzner listing first')" 1; a "escalate only if the volume is gone" "$(issues '.[0].body' | grep -c 'Only if the volume is gone, treat it as a total loss')" 1
end_row X5 "volume-not-found issue: exact title, p1 labels, the reason pointer and the incident route"
new_case; go
a "vnf issue closed by a matches-declared run" "$(issues '.[0].state')" closed
end_row X6 "a matches-declared run closes the volume-not-found issue"
new_scen
new_case; BODIES+=("probe=$TMP/exit1.sh"); go
new_case; BODIES+=("probe=$TMP/nononame.sh"); printf 'echo verdict=no-token >> "$GITHUB_OUTPUT"\n' > "$TMP/nononame.sh"; go
a "two (name-unreadable) issues" "$(issues 'length')" 2
a "title 1" "$(issues '.[0].title')" "infra: the Inngest store volume protection check could not read Hetzner (name-unreadable)"
a "title 2" "$(issues '.[1].title')" "infra: the Inngest store volume protection check has no usable credential (name-unreadable)"
_keep="$CHK"; new_case; go; CHK+="$_keep"
a "a matches-declared run closes both (name-unreadable) issues" "$(issues '[.[] | select(.state == "open")] | length')" 0
end_row X7 "the (name-unreadable) form of both could-not-perform titles is cleared by a matches-declared run"
new_scen; new_case; live false; go
FB=$(issues '.[0].body')
a "declared" "$(grep -c -- '- Declared in Terraform: true$' <<<"$FB")" 1; a "live" "$(grep -c -- '- Live at Hetzner: false$' <<<"$FB")" 1
a "run url" "$(grep -c -- '- Run: https://github.com/o/r/actions/runs/77$' <<<"$FB")" 1
a "age" "$(grep -cE -- '- Minutes since the declaration last changed on the default branch: [0-9]+$' <<<"$FB")" 1
a "verdict" "$(grep -c -- '- Check verdict: lifted-outside-terraform$' <<<"$FB")" 1; a "volume" "$(grep -c -- "- Volume: $NAME\$" <<<"$FB")" 1
a "no unplanned cross-link line" "$(grep -c 'Related open issue' <<<"$FB")" 0
end_row X8 "the finding body carries the verdict, volume, declared, live, age and a full run URL (every filer env value is wired)"
new_scen; new_case; CODES=401; go
UB=$(issues '.[0].body')
a "verdict" "$(grep -c -- '- Check verdict: no-token$' <<<"$UB")" 1; a "http" "$(grep -c -- '- HTTP code: 401$' <<<"$UB")" 1
a "run url" "$(grep -c -- '- Run: https://github.com/o/r/actions/runs/77$' <<<"$UB")" 1; a "ADR pointer" "$(grep -c 'ADR-282' <<<"$UB")" 1
a "closing text" "$(grep -c 'a matches-declared run closes it' <<<"$UB")" 1; a "no stale closing text" "$(grep -c 'a clean run closes it' <<<"$UB")" 0
_keep="$CHK"; new_scen; new_case; CODES=500; go; CHK+="$_keep"
a "could-not-read body names the closing verdict" "$(issues '.[0].body' | grep -c 'a matches-declared run closes it')" 1
a "could-not-read body points at the first failed or skipped step" "$(issues '.[0].body' | grep -c 'read the first failed or skipped step of the run (the probe, or an earlier step if the probe was skipped)')" 1
a "no stale pointer to the probe step alone" "$(issues '.[0].body' | grep -c 'read the probe step')" 0
a "a readable name carries no name-unreadable sentence" "$(issues '.[0].body' | grep -c 'no volume name could be read')" 0
end_row X9 "the could-not-perform bodies carry verdict, HTTP, run URL, the ADR pointer and the right closing text"
new_case; CODES="502 504 200"; go; want_out "${V}matches-declared|$OK_KEYS|live=true|volume_id=$VOL_ID|http=200"; want_steps skip skip ran skip 0; want_req 3
end_row X10 "502, 504, 200 -> retried to a clean answer"
for _c in 204 301 418; do
  new_case; CODES="$_c"; go; want_out "${V}could-not-read|$OK_KEYS|http=$_c"; want_steps skip ran skip skip 1; want_req 1
  end_row "X11/$_c" "HTTP $_c is no answer the job reads -> could-not-read after ONE request (no hidden clean arm)"
done
for _bl in github-actions 'github-actions[bot]' app/github-actions; do
  new_scen; new_case; live false; STUB_ENV+=("GH_BOT_LOGIN=$_bl"); go
  new_case; go
  a "closed for login $_bl" "$(issues '.[0].state')" closed
  end_row "X12/$_bl" "a matches-declared run closes an issue authored as $_bl"
done
_acc=""
for _lc in finding unreadable clear; do
  new_scen; new_case
  case "$_lc" in unreadable) CODES=500 ;; *) live false ;; esac
  go; add_unrelated
  new_case
  case "$_lc" in unreadable) CODES=500 ;; finding) live false ;; esac
  go
  case "$_lc" in
    clear) a "the older bot issue is closed past an unrelated newer one" "$(issues '.[0].state')" closed ;;
    *) a "$_lc: no duplicate behind 36 unrelated newer issues" "$(issues '[.[] | select(.title | startswith("infra: drift detected") | not)] | length')" 1; a "$_lc: commented on the existing one" "$(issues '.[0].comments | length')" 1 ;;
  esac
  _acc+="$CHK"
done
CHK="$_acc"
end_row X13 "the dedupe lists past 36 unrelated NEWER infra-drift issues (the stub honours --limit, defaults to 30 and lists newest first, so only --limit 100 reaches the old one): finding, could-not-perform and clear"
new_scen; new_case; GH_REF="refs/heads/feature"; live false; go
a "job skipped off main" "$(jq -r .conclusion "$CASE/result.json")" skipped; a "no step ran" "$(jq '.steps | length' "$CASE/result.json")" 0
a "no issue" "$(issues 'length')" 0; want_req 0; a "no output files" "$(find "$CASE/out" -type f | wc -l | tr -d ' ')" 0
end_row X14 "a dispatch off the default branch: every step is skipped and nothing is filed"
# Gross garbage, then a valid value with SUFFIX garbage (a dropped trailing $ would let it through), then PREFIX garbage (a dropped ^).
for _vv in "name=Bad Name" "expected=maybe" "live=perhaps" "volume_id=12;3" "http=2x0" "tf_age_min=-5" \
  "name=abc def" "expected=truex" "live=falsey" "http=2000" "tf_age_min=5x" \
  "name=Xabc" "expected=xtrue" "live=xfalse" "volume_id=x12" "http=x200" "tf_age_min=x5"; do
  _k="${_vv%%=*}"; _val="${_vv#*=}"
  new_case; set_age none; _pb="$TMP/x/steps/probe.sh"
  { sed '$d' "$_pb"; printf "%s='%s'\n" "$_k" "$_val"; tail -n 1 "$_pb"; } > "$CASE/probe-inj.sh"
  a "the last probe line is the final finish call" "$(tail -n 1 "$_pb")" 'finish "$verdict"'
  a "the injection landed" "$(grep -c "^$_k='" "$CASE/probe-inj.sh")" 1
  BODIES+=("probe=$CASE/probe-inj.sh"); go
  _wk=$(tr '|' '\n' <<<"expected=true|name=$NAME|live=true|volume_id=$VOL_ID|http=200" | grep -v "^${_k}=" | paste -sd'|')
  want_out "${V}could-not-read|$_wk"; want_steps skip ran skip skip 1
  end_row "X15/$_k=$_val" "a hostile $_k that reached finish is dropped and the verdict becomes could-not-read (the output validator)"
done
# The Doppler install step is EXECUTED under a stub curl (strict argv, bounded) with a real tarball and the real sha256sum.
mkdir -p "$TMP/dl/bin" "$TMP/dl/src" || fatal "mkdir dl"
printf '#!/bin/sh\necho stub-doppler\n' > "$TMP/dl/src/doppler"; chmod +x "$TMP/dl/src/doppler"
tar czf "$TMP/dl/doppler.tar.gz" -C "$TMP/dl/src" doppler || fatal "fixture tarball"
DL_SHA=$(sha256sum "$TMP/dl/doppler.tar.gz" | cut -d' ' -f1)
cat > "$TMP/dl/bin/curl" <<'STUB' || fatal "write dl curl stub"
#!/usr/bin/env bash
# The install step's curl: bounded, retried, silent-on-success; anything else is refused.
log="${CASE_DIR:?}/dl.argv"; printf '%s\n' "$*" >> "$log"
out=""; url=""; retry=0; ct=0; mt=0; args=("$@"); i=0
while (( i < ${#args[@]} )); do
  a="${args[$i]}"
  case "$a" in
    -fsSL) ;;
    --retry) i=$((i + 1)); [[ "${args[$i]:-}" == 3 ]] && retry=1 ;;
    --connect-timeout) i=$((i + 1)); [[ "${args[$i]:-}" == 20 ]] && ct=1 ;;
    --max-time) i=$((i + 1)); [[ "${args[$i]:-}" == 120 ]] && mt=1 ;;
    -o) i=$((i + 1)); out="${args[$i]:-}" ;;
    https://*) url="$a" ;;
    *) echo "dl curl stub: refused $a" >&2; exit 64 ;;
  esac
  i=$((i + 1))
done
[[ "$retry$ct$mt" == 111 ]] || { echo "dl curl stub: unbounded or unretried" >&2; exit 64; }
[[ "$url" == "https://github.com/DopplerHQ/cli/releases/download/${DOPPLER_CLI_VERSION:?}/doppler_${DOPPLER_CLI_VERSION}_linux_amd64.tar.gz" && -n "$out" ]] || { echo "dl curl stub: refused url" >&2; exit 64; }
cp "${DL_FIXTURE:?}" "$out"
STUB
chmod +x "$TMP/dl/bin/curl" || fatal "chmod dl curl"
printf '#!/bin/sh\n' > "$TMP/dl/src/other"; chmod +x "$TMP/dl/src/other"
tar czf "$TMP/dl/nomember.tar.gz" -C "$TMP/dl/src" other || fatal "fixture tarball without the doppler member"
NOMEMBER_SHA=$(sha256sum "$TMP/dl/nomember.tar.gz" | cut -d' ' -f1)
dl_case() { # dl_case <sha256> [<fixture tarball>]
  new_case; NO_RUN='[]'
  OVR+=("doppler_cli:PATH=$TMP/dl/bin:$REAL_PATH" "doppler_cli:DOPPLER_CLI_SHA256=$1" "doppler_cli:CASE_DIR=$CASE" "doppler_cli:DL_FIXTURE=${2:-$TMP/dl/doppler.tar.gz}")
  go
}
dl_case "$DL_SHA"
a "install step ran and succeeded" "$(rs doppler_cli outcome)" success
a "the binary was extracted" "$([[ -x "$CASE/rt/doppler-cli/doppler" ]] && echo yes || echo no)" yes
a "the tarball was removed" "$([[ -e "$CASE/rt/doppler-cli/doppler.tar.gz" ]] && echo yes || echo no)" no
a "the directory was handed to PATH" "$(cat "$CASE/github_path")" "$CASE/rt/doppler-cli"
a "the download was bounded and retried" "$(grep -c -e '--retry 3 --connect-timeout 20 --max-time 120' "$CASE/dl.argv")" 1
want_out "${V}matches-declared|$OK_KEYS|live=true|volume_id=$VOL_ID|http=200"; want_steps skip skip ran skip 0
end_row X16 "the Doppler install step run under a stub curl: verified, extracted, on PATH, bounded; the probe then runs"
dl_case "0000000000000000000000000000000000000000000000000000000000000000"
a "install step failed on a checksum mismatch" "$(rs doppler_cli outcome)" failure
a "the probe was skipped" "$(rs probe ran)" false
a "nothing was extracted" "$([[ -e "$CASE/rt/doppler-cli/doppler" ]] && echo yes || echo no)" no
a "nothing was handed to PATH" "$(grep -c . "$CASE/github_path")" 0
want_steps skip ran skip skip 1
end_row X17 "a tarball whose checksum does not match: the install step is red, nothing is extracted or put on PATH, the probe is skipped, the complement filer fires and the gate is red"
dl_case "$NOMEMBER_SHA" "$TMP/dl/nomember.tar.gz"
a "the checksum verified but the extraction failed: the install step is red" "$(rs doppler_cli outcome)" failure
a "the probe was skipped" "$(rs probe ran)" false
a "nothing was handed to PATH" "$(grep -c . "$CASE/github_path")" 0
want_steps skip ran skip skip 1
end_row X17b "a VERIFIED tarball that does not extract (the doppler member missing): the install step is red, nothing is put on PATH, the probe is skipped and the gate is red (an extraction failure is never swallowed)"

# ---------------------------------------------------------------------------------------------------------
echo "W: the web-1 workspaces volume entry (the arms where a row value changes the outcome; shared paths stay single-run)"
# ---------------------------------------------------------------------------------------------------------
switch_entry web1
new_scen
new_case; go; a "entry" "$ENTRY" web1
want_out "${V}matches-declared|$OK_KEYS|live=true|volume_id=$VOL_ID|http=200"; want_steps skip skip ran skip 0; want_req 1
end_row WV1 "web-1: declared true, live true -> matches-declared with the web-1 name and id; green, the clear step runs, no email"
r_wlifted() { new_case; live false; go; want_out "${V}lifted-outside-terraform|$OK_KEYS|live=false|volume_id=$VOL_ID|http=200"; want_steps ran skip skip ran 1; }
r_wlifted; end_row WV2 "web-1: declared true, live false, workspaces-luks.tf unchanged for 3 h -> lifted-outside-terraform: finding filer, email, red gate"
new_case; live false; set_age 5; go; want_out "${V}lift-pending-apply|$OK_KEYS|live=false|volume_id=$VOL_ID|http=200"; want_steps skip skip skip skip 0
warn_has "the web-1 workspaces volume is unprotected at Hetzner until the re-protect change applies"
grep -qF "the web-1 workspaces volume is unprotected at Hetzner until the re-protect change applies" "$CASE/summary" || CHK+=$'\n    '"the summary line lacks the web-1 subject"
end_row WV3 "web-1: workspaces-luks.tf changed 5 min ago -> lift-pending-apply, warned and summarized under the web-1 subject"
FAKE_NOW=$(date +%s)
new_case; STUB_ENV+=("FAKE_NOW=$FAKE_NOW"); live false; set_age 89; go; a "89 min" "$(sed -n 's/^verdict=//p' "$CASE/out/probe")" lift-pending-apply; _keep="$CHK"
new_case; STUB_ENV+=("FAKE_NOW=$FAKE_NOW"); live false; set_age 91; go; CHK+="$_keep"; a "91 min" "$(sed -n 's/^verdict=//p' "$CASE/out/probe")" lifted-outside-terraform
FAKE_NOW=""
end_row WV3b "web-1 grace boundary on its OWN file, on a pinned clock: 89 minutes is still pending, 91 minutes files"
new_case; tf "$NAME" false; live false; go; want_out "${V}unprotected-as-declared|expected=false|name=$NAME|live=false|volume_id=$VOL_ID|http=200"; want_steps skip skip skip skip 0
warn_has "the web-1 workspaces volume is unprotected, as declared"
end_row WV4 "web-1: declared false, live false -> unprotected-as-declared, warned under the web-1 subject"
new_case; tf "$NAME" false; live true; go; want_out "${V}lift-not-applied|expected=false|name=$NAME|live=true|volume_id=$VOL_ID|http=200"; want_steps skip skip skip skip 0
warn_has "the web-1 workspaces volume is still protected at Hetzner although the declaration says unprotected"
end_row WV5 "web-1: declared false, live true -> lift-not-applied, warned under the web-1 subject"
r_wempty() { new_case; listing > "$CASE/listing.json"; go; want_out "${V}volume-not-found|$OK_KEYS|http=200"; want_steps ran skip skip ran 1; }
r_wempty; vnf_reason zero; end_row WV6 "web-1: an EMPTY listing -> volume-not-found (reason zero): finding filer, red"
r_wid() { new_case; listing "$(vol "$OTHER_ID" "$NAME" true)" > "$CASE/listing.json"; go; want_out "${V}volume-not-found|$OK_KEYS|http=200"; want_steps ran skip skip ran 1; }
r_wid; vnf_reason id-mismatch; end_row WV8 "web-1: a same-name volume carrying the Inngest id -> volume-not-found reason=id-mismatch, never matches-declared"
for _n in soleur-alpha-store zz9-other-name; do
  new_case; tf "$_n" true; go; want_out "${V}matches-declared|expected=true|name=$_n|live=true|volume_id=$VOL_ID|http=200"; want_steps skip skip ran skip 0
  end_row "WT1/$_n" "web-1: a different declared name flows into the request URL and the outputs"
done
tf_bad WT3 "the web-1 resource renamed" "s/\"$TF_RES\" {/\"${TF_RES}_x\" {/"
_wind=$(python3 -I - "$REPO_ROOT/$TF_REL" "$TF_RES" <<'PYW'
import re, sys
t = open(sys.argv[1]).read()
ms = list(re.finditer(r'(?m)^resource\s+"hcloud_volume"\s+"%s"\s*\{\s*$' % re.escape(sys.argv[2]), t))
if len(ms) != 1:
    sys.exit("resource line matched %d times" % len(ms))
i, d, out = ms[0].end(), 1, []
while d:
    c = t[i]
    d += (c == "{") - (c == "}")
    out.append(c)
    i += 1
blk, depth, top = "".join(out), 0, []
for ln in blk.splitlines():
    code = re.sub(r"\s*#.*$", "", ln)
    if depth == 0:
        top.append(code)
    depth += code.count("{") - code.count("}")
name = re.search(r'^\s*name\s*=\s*"([^"]+)"', "\n".join(top), re.M).group(1)
dp = re.search(r"^\s*delete_protection\s*=\s*(true|false)\s*$", "\n".join(top), re.M).group(1)
print("%s %s" % (name, dp))
PYW
) || fatal "independent derivation of the real web-1 .tf failed"
read -r _wname _wexp <<<"$_wind"
new_case; WS="$REPO_ROOT"; CASE_NAME="$_wname"; set_api "$_wexp"; go
_wverd=matches-declared; if [[ "$_wexp" == false ]]; then _wverd=unprotected-as-declared; fi
want_out "${V}${_wverd}|expected=$_wexp|name=$_wname|live=$_wexp|volume_id=$VOL_ID|http=200"
a "the resource line of the real file" "$(grep -cE "^resource \"hcloud_volume\" \"$TF_RES\" \{\$" "$REPO_ROOT/$TF_REL")" 1
a "the real web-1 name" "$_wname" "$NAME"
end_row WR1 "the probe on the REAL workspaces-luks.tf derives '$_wname' and declared=$_wexp exactly as an independent derivation does (path and resource from use_entry, never from the rows)"
new_scen; new_case; live false; go
a "issues filed" "$(issues 'length')" 1; a "title" "$(issues '.[0].title')" "$TITLE_DIFF"
a "labels" "$(issues '.[0].labels | sort | join(",")')" "action-required,infra-drift,priority/p1-high"; a "milestone" "$(issues '.[0].milestone')" "Post-MVP / Later"
FB=$(issues '.[0].body')
a "lead names the web-1 volume" "$(grep -cxF 'The delete-protection flag of the web-1 workspaces volume at Hetzner does not match what the committed Terraform declares.' <<<"$FB")" 1
a "remedy names the dispatch" "$(grep -c 'the owner-approved `manual-rerun` dispatch of the per-merge apply' <<<"$FB")" 1
a "remedy names ADR-119 D1 and its addendum" "$(grep -cF 'SSH stage (ADR-119 D1, addendum of 2026-10-08)' <<<"$FB")" 1
a "remedy names the read-back subsection" "$(grep -cF 'read the flag back with "Read back the delete-protection flag (read-only token)" in workspaces-luks-cutover-6604.md.' <<<"$FB")" 1
a "remedy says an agent reports" "$(grep -cF 'An agent reports this and does not dispatch it unprompted.' <<<"$FB")" 1
a "the decision line, exactly" "$(grep -cxF 'Decision record: ADR-119 (D1 and the addendum of 2026-11-10). The read-back: "Read back the delete-protection flag (read-only token)" in workspaces-luks-cutover-6604.md.' <<<"$FB")" 1
a "nothing names the Inngest volume, its ADR or its runbook" "$(grep -ciE 'inngest|ADR-282|6894' <<<"$FB")" 0
a "email subject, exactly" "$(jq -r '.steps.notify.with.subject' "$CASE/result.json")" "[INFRA DRIFT] web-1 workspaces volume protection check needs attention"
a "email body names the web-1 volume" "$(jq -r '.steps.notify.with.body' "$CASE/result.json" | grep -c '<strong>The twice-daily web-1 workspaces volume protection check needs attention.</strong>')" 1
a "email body names ADR-119" "$(jq -r '.steps.notify.with.body' "$CASE/result.json" | grep -c 'carries the facts and the pointers (ADR-119)')" 1
a "email body names no Inngest pointer" "$(jq -r '.steps.notify.with.body' "$CASE/result.json" | grep -ciE 'inngest|ADR-282')" 0
end_row WF1 "web-1 first lifted run: ONE p1 issue with the web-1 title, labels, milestone, ADR-119 pointer, the web-1 remedy and read-back subsection; the email names the web-1 volume and ADR-119"
new_case; go
a "cleared comment" "$(issues '.[0].comments | length')" 1; a "state" "$(issues '.[0].state')" closed
end_row WF3 "web-1: a matches-declared run comments 'cleared in run' and closes the web-1 issue"
for _vd in lifted-outside-terraform volume-not-found no-token could-not-read; do
  # In THIS shell (not a command substitution), so the filed title is read from the render's own scenario and the render
  # cases' invariants fold into the row.
  render_body "$_vd" 1 > "$TMP/wf12.1"; _t1=$(issues '.[0].title')
  render_body "$_vd" 2 > "$TMP/wf12.2"; _b1=$(cat "$TMP/wf12.1"); _b2=$(cat "$TMP/wf12.2"); CHK=""
  _n1=$(sed -e 's/zzn1/@/g; s/401/@/g; s/771/@/g' <<<"$_b1" | sed -E 's|actions/runs/[0-9]+|@|'); _n2=$(sed -e 's/zzn2/@/g; s/402/@/g; s/772/@/g' <<<"$_b2" | sed -E 's|actions/runs/[0-9]+|@|')
  if [[ -z "$_b1" ]]; then CHK+=$'\n    '"no body was filed"; fi
  if [[ "$_n1" != "$_n2" ]]; then CHK+=$'\n    '"the body differs in more than the named fields"; fi
  if ! grep -q -e 'zzn1' -e 'HTTP code: 401' <<<"$_b1"; then CHK+=$'\n    '"neither the volume name nor the HTTP code is in the body (the render did not reach the filer)"; fi
  if recipe_vocab "$_b1"; then CHK+=$'\n    '"the body holds recipe vocabulary or a Hetzner id"; fi
  if grep -qi 'inngest' <<<"$_b1"; then CHK+=$'\n    '"the web-1 body names the Inngest volume"; fi
  a "the filed title is a web-1 title" "$(grep -c '^infra: \(the \)\{0,1\}web-1 workspaces volume ' <<<"$_t1")" 1
  end_row "WF12/$_vd" "web-1: the rendered filer body has only the named dynamic fields, no recipe vocabulary, no id and no Inngest wording"
done
new_scen; new_case; listing > "$CASE/listing.json"; go
a "vnf title" "$(issues '.[0].title')" "$TITLE_GONE"; a "vnf labels" "$(issues '.[0].labels | sort | join(",")')" "action-required,infra-drift,priority/p1-high"
a "lead" "$(issues '.[0].body' | grep -cxF 'Hetzner reports no single volume with the expected name and identity for the web-1 workspaces volume.')" 1
a "reason pointer" "$(issues '.[0].body' | grep -c 'names the reason (zero, many or id-mismatch)')" 1
a "confirm before escalating" "$(issues '.[0].body' | grep -c '^Confirm the Hetzner listing first')" 1
a "incident route and the ADR-119 loss modes" "$(issues '.[0].body' | grep -cF 'Only if the volume is gone, treat it as a total loss: use the `soleur:incident` skill and ADR-119 (addendum of 2026-10-08) for the loss modes.')" 1
a "no Inngest runbook section" "$(issues '.[0].body' | grep -c 'After a total loss')" 0
end_row WX5 "web-1 volume-not-found issue: the web-1 title, p1 labels, the reason pointer, soleur:incident and the ADR-119 loss modes"
new_scen
new_case; BODIES+=("probe=$TMP/exit1.sh"); go
new_case; BODIES+=("probe=$TMP/nononame.sh"); go
a "two (name-unreadable) issues" "$(issues 'length')" 2
a "title 1" "$(issues '.[0].title')" "infra: the web-1 workspaces volume protection check could not read Hetzner (name-unreadable)"
a "title 2" "$(issues '.[1].title')" "infra: the web-1 workspaces volume protection check has no usable credential (name-unreadable)"
_keep="$CHK"; new_case; go; CHK+="$_keep"
a "a web-1 matches-declared run closes both (name-unreadable) issues" "$(issues '[.[] | select(.state == "open")] | length')" 0
end_row WX7 "web-1: the (name-unreadable) form of both could-not-perform titles is filed under the web-1 subject and cleared by a web-1 clean run"
new_scen; new_case; CODES=401; go
UB=$(issues '.[0].body')
a "title" "$(issues '.[0].title')" "$TITLE_NOCRED"
a "names the web-1 volume" "$(grep -c "the web-1 workspaces volume's delete-protection flag" <<<"$UB")" 1
a "ADR pointer" "$(grep -cF 'Decision record: ADR-119.' <<<"$UB")" 1; a "no Inngest pointer" "$(grep -ciE 'inngest|ADR-282' <<<"$UB")" 0
_keep="$CHK"; new_scen; new_case; CODES=500; go; CHK+="$_keep"
a "could-not-read title" "$(issues '.[0].title')" "$TITLE_UNREAD"
a "could-not-read body names ADR-119" "$(issues '.[0].body' | grep -cF 'Decision record: ADR-119.')" 1
end_row WX9 "web-1 could-not-perform bodies (no-token, could-not-read) name the web-1 volume and ADR-119, never ADR-282"
switch_entry inngest
new_scen; new_case; live false; OVR+=("file_finding:VERDICT=bogus"); go
a "finding filer outcome (unknown verdict)" "$(rs file_finding outcome)" failure; a "finding filer rc" "$(rs file_finding rc)" 1
a "one slug line" "$(grep -c '^::error::sole_copy_finding_filer_unexpected_verdict' "$CASE/file_finding.log")" 1
a "the slug names entry:verdict" "$(grep '^::error::sole_copy_finding_filer_unexpected_verdict' "$CASE/file_finding.log" | grep -cF '(inngest:bogus)')" 1
a "no issue filed" "$(issues 'length')" 0
a "the email names the failed finding filer" "$(jq -r '.steps.notify.with.body' "$CASE/result.json" | grep -c 'finding filer <code>failure</code>')" 1
_keep="$CHK"
new_scen; new_case; live false; OVR+=("file_finding:ENTRY=zzz"); go; CHK+="$_keep"
a "finding filer outcome (unknown entry)" "$(rs file_finding outcome)" failure; a "finding filer rc" "$(rs file_finding rc)" 1
a "one slug line" "$(grep -c '^::error::sole_copy_finding_filer_unexpected_verdict' "$CASE/file_finding.log")" 1
a "the slug names entry:verdict" "$(grep '^::error::sole_copy_finding_filer_unexpected_verdict' "$CASE/file_finding.log" | grep -cF '(zzz:lifted-outside-terraform)')" 1
a "no issue filed" "$(issues 'length')" 0
a "the email names the failed finding filer" "$(jq -r '.steps.notify.with.body' "$CASE/result.json" | grep -c 'finding filer <code>failure</code>')" 1
end_row WX16 "the finding filer's catch-all: an unknown verdict and an unknown entry each print the slug with entry:verdict, file nothing, reach the email and fail the step"

# ---------------------------------------------------------------------------------------------------------
echo "C: cross-entry isolation (both directions; one shared issue store per row)"
# ---------------------------------------------------------------------------------------------------------
titles_of() { # titles_of <entry> [nu]: that entry's four titles, or (nu) its two (name-unreadable) forms; in a subshell
  use_entry "$1"
  if [[ "${2-}" == nu ]]; then printf '%s\n' "${TITLE_NOCRED/"($NAME)"/(name-unreadable)}" "${TITLE_UNREAD/"($NAME)"/(name-unreadable)}"
  else printf '%s\n' "$TITLE_DIFF" "$TITLE_GONE" "$TITLE_NOCRED" "$TITLE_UNREAD"; fi
}
seed_issue() { # seed_issue <title>: an open, bot-authored infra-drift issue (every filter the clear step applies would act on it)
  jq --arg t "$1" '. + [{number: ((map(.number) | max // 0) + 1), title: $t, state: "open", labels: ["infra-drift"], milestone: "", body: "seeded", author: "app/github-actions", comments: []}]' "$SCEN/issues.json" > "$SCEN/i.tmp" && mv "$SCEN/i.tmp" "$SCEN/issues.json"
}
seeded_open() { jq --arg b seeded '[.[] | select(.body == $b and .state == "open" and (.comments | length) == 0)] | length' "$SCEN/issues.json"; }
_acc=""
for _e in inngest web1; do
  switch_entry "$_e"; new_scen; new_case; go
  want_out "${V}matches-declared|$OK_KEYS|live=true|volume_id=$VOL_ID|http=200"; want_req 1
  a "$_e: the request names this entry's volume" "$(tr '\0' '\n' < "$CASE/curl.1.argv" | grep -c "name=${NAME}&")" 1
  a "$_e: the request never names the other entry's volume" "$(tr '\0' '\n' < "$CASE/curl.1.argv" | grep -c "$OTHER_NAME")" 0
  fold_inv; _acc+="$INV_ACC$CHK"; INV_ACC=""; CHK=""
done
CHK="$_acc"; end_row C1 "request isolation: each leg asks Hetzner for its own volume's name only (the listing holds both volumes)"
_acc=""
for _e in inngest web1; do
  switch_entry "$_e"; new_scen; new_case; listing "$(vol "$OTHER_ID" "$NAME" true)" > "$CASE/listing.json"; go
  want_out "${V}volume-not-found|$OK_KEYS|http=200"; want_steps ran skip skip ran 1; vnf_reason id-mismatch
  CHK="${CHK//$'\n    '/$'\n    '"$_e: "}"; fold_inv; _acc+="$INV_ACC$CHK"; INV_ACC=""; CHK=""
done
CHK="$_acc"; end_row C2 "id isolation: a same-name volume carrying the OTHER leg's id is volume-not-found reason=id-mismatch for each leg"
_acc=""
for _e in inngest web1; do
  switch_entry "$_e"; new_scen
  new_case; live false; set_age 180; set_age_other 5; go
  a "$_e: own file 3 h old, other file 5 min old -> files" "$(sed -n 's/^verdict=//p' "$CASE/out/probe")" lifted-outside-terraform
  a "$_e: the own file's commit time was served" "$(grep -c '^epoch=[0-9]' "$CASE/out/tf_commit" 2>/dev/null)" 1
  _ta=$(sed -n 's/^tf_age_min=//p' "$CASE/out/probe"); [[ "$_ta" =~ ^[0-9]+$ ]] && (( _ta >= 179 )) || CHK+=$'\n    '"$_e: the age is not the own file's (tf_age_min='$_ta', want >= 179)"
  fold_inv; _acc+="$INV_ACC$CHK"; INV_ACC=""; CHK=""
  new_case; live false; set_age 5; set_age_other 180; go
  a "$_e: own file 5 min old, other file 3 h old -> pending" "$(sed -n 's/^verdict=//p' "$CASE/out/probe")" lift-pending-apply
  fold_inv; _acc+="$INV_ACC$CHK"; INV_ACC=""; CHK=""
done
CHK="$_acc"; end_row C3 "grace isolation: each leg reads its own declaration file's commit time (the other file's recent commit neither opens nor closes the grace)"
_acc=""
for _e in inngest web1; do
  switch_entry "$_e"; _o="$OTHER_ENTRY"; new_scen
  while IFS= read -r _t; do seed_issue "$_t"; done < <(titles_of "$_o")
  new_case; go
  a "$_e clean run: the other leg's four issues stay open and uncommented" "$(seeded_open)" 4
  fold_inv; _acc+="$INV_ACC$CHK"; INV_ACC=""; CHK=""
  switch_entry "$_o"; new_case; go
  a "positive control: a clean $_o run closes its own four" "$(seeded_open)" 0
  fold_inv; _acc+="$INV_ACC$CHK"; INV_ACC=""; CHK=""
done
CHK="$_acc"; end_row C4 "clear isolation on one shared issue store: a clean run of one leg never closes the other leg's issues (and that leg's own clean run does)"
_acc=""
for _e in inngest web1; do
  switch_entry "$_e"; _o="$OTHER_ENTRY"; new_scen
  while IFS= read -r _t; do seed_issue "$_t"; done < <(titles_of "$_o" nu)
  new_case; go
  a "$_e clean run: the other leg's two (name-unreadable) issues stay open" "$(seeded_open)" 2
  fold_inv; _acc+="$INV_ACC$CHK"; INV_ACC=""; CHK=""
  switch_entry "$_o"; new_case; go
  a "positive control: a clean $_o run closes its own (name-unreadable) issues" "$(seeded_open)" 0
  fold_inv; _acc+="$INV_ACC$CHK"; INV_ACC=""; CHK=""
done
CHK="$_acc"; end_row C5 "(name-unreadable) isolation: the two forms are per-subject, so one leg's clean run leaves the other's open"
_acc=""
for _e in inngest web1; do
  switch_entry "$_e"; _o="$OTHER_ENTRY"; new_scen
  while IFS= read -r _t; do seed_issue "$_t"; done < <(titles_of "$_o" | sed -n '3,4p')
  new_case; CODES=500; go; new_case; CODES=401; go
  a "$_e could-not-perform: the other leg's two issues are not commented" "$(seeded_open)" 2
  a "$_e files its own could-not-read issue" "$(jq --arg t "$TITLE_UNREAD" '[.[] | select(.title == $t and .state == "open")] | length' "$SCEN/issues.json")" 1
  a "$_e files its own no-token issue" "$(jq --arg t "$TITLE_NOCRED" '[.[] | select(.title == $t and .state == "open")] | length' "$SCEN/issues.json")" 1
  fold_inv; _acc+="$INV_ACC$CHK"; INV_ACC=""; CHK=""
  switch_entry "$_o"; new_case; go
  a "positive control: a clean $_o run closes its own two" "$(seeded_open)" 0
  a "and leaves the $_e leg's two open" "$(jq '[.[] | select(.body != "seeded" and .state == "open")] | length' "$SCEN/issues.json")" 2
  fold_inv; _acc+="$INV_ACC$CHK"; INV_ACC=""; CHK=""
done
CHK="$_acc"; end_row C6 "could-not-perform isolation: each leg files and dedupes under its own two titles only"
jq '.strategy.matrix.include |= reverse' "$TMP/x/job.json" > "$TMP/x/job.swapped.json" || fatal "swap rows"
_acc=""; CHK=""
a "the swap landed" "$(jq -r '.strategy.matrix.include[0].entry' "$TMP/x/job.swapped.json")" "$(jq -r '.strategy.matrix.include[1].entry' "$TMP/x/job.json")"; _acc+="$CHK"; CHK=""
for _e in inngest web1; do
  switch_entry "$_e"; new_scen; new_case; JOB_JSON="$TMP/x/job.swapped.json"; go
  want_out "${V}matches-declared|$OK_KEYS|live=true|volume_id=$VOL_ID|http=200"; want_steps skip skip ran skip 0
  fold_inv; _acc+="$INV_ACC$CHK"; INV_ACC=""; CHK=""
done
CHK="$_acc"; end_row C8 "must-pass: the include rows in swapped order select the same data (row order carries no meaning)"
switch_entry inngest; _iall=$( { titles_of inngest; titles_of inngest nu; } )
switch_entry web1; new_scen
while IFS= read -r _t; do seed_issue "$_t"; done <<<"$_iall"
new_case; JOB_STATUS=cancelled; go
a "the probe is skipped on a cancelled leg" "$(rs probe ran)" false; a "the could-not-perform filer ran" "$(rs file_unreadable outcome)" success
a "every Inngest issue is untouched" "$(seeded_open)" 6
a "one new issue" "$(jq '[.[] | select(.body != "seeded")] | length' "$SCEN/issues.json")" 1
a "under the web-1 (name-unreadable) title" "$(jq -r '[.[] | select(.body != "seeded")][0].title' "$SCEN/issues.json")" "$(titles_of web1 nu | sed -n 2p)"
a "gate red" "$(rs gate rc)" 1
end_row C9 "a cancelled web-1 leg files only under the web-1 (name-unreadable) title and leaves every Inngest title alone"
new_scen; new_case; rm -rf -- "$WS/.git"; FORCE+=("anon=failure"); go
a "the checkout failed" "$(rs anon outcome)" failure; a "the probe is skipped" "$(rs probe ran)" false
a "the could-not-perform filer succeeded without a checkout" "$(rs file_unreadable outcome)" success
a "one p2 issue" "$(issues 'length')" 1; a "under the web-1 (name-unreadable) title" "$(issues '.[0].title')" "$(titles_of web1 nu | sed -n 2p)"
a "p2" "$(issues '.[0].labels | index("priority/p2-medium") != null')" true
end_row C10 "a web-1 leg whose checkout failed still files its p2 (name-unreadable) issue: the filers name the repository through GH_REPO"
switch_entry inngest

# ---------------------------------------------------------------------------------------------------------
echo "P: pins"
# ---------------------------------------------------------------------------------------------------------
_pin=$(jq -r '[.[] | objects | select(.entry == "inngest") | .volume_id] | if length == 1 then .[0] | tostring else "" end' "$TMP/x/rows.json")
_wpin=$(jq -r '[.[] | objects | select(.entry == "web1") | .volume_id] | if length == 1 then .[0] | tostring else "" end' "$TMP/x/rows.json")
_adr="$REPO_ROOT/knowledge-base/engineering/architecture/decisions/ADR-282-sole-copy-luks-volume-protection-set.md"
_rb=$(grep -F -e '--only-secrets HCLOUD_TOKEN_READONLY' "$RUNBOOK" | grep -o 'v1/volumes/[0-9]*' | sort -u | tr '\n' ' ')
if [[ -n "$_pin" && "$_pin" == "$(use_entry inngest; printf '%s' "$VOL_ID")" && -f "$_adr" ]] && grep -qF "Hetzner id $_pin" "$_adr" && grep -qF "$_pin" "$SKILL" && [[ "$_rb" == "v1/volumes/$_pin " ]]; then pass "N1 the inngest row's volume_id ($_pin) equals the id in ADR-282, in the postmerge skill's section-5c one-liner and in the runbook's section-5c one-liner"
else fail "N1 the inngest row's volume_id='$_pin' does not equal the suite's Inngest id / ADR-282 / postmerge skill / runbook one-liner id (runbook: '$_rb')"; fi
# N1b: the workflow carries exactly TWO comment-stripped pin literals (the two orphan sweeps), both equal to the inngest row's
# volume_id. A literal inside the sole-copy job itself is an id-placement violation (S1). An exact count, not a floor: a deleted
# copy (a sweep that no longer proves the volume is visible) must be red.
_pins=$(grep -v '^[[:space:]]*#' "$WF" | grep -E '^[[:space:]]*readonly VOLUME_ID_PIN=[0-9]+' | sed -E 's/^[[:space:]]*readonly VOLUME_ID_PIN=([0-9]+).*/\1/') || _pins=""
_npins=$(grep -c . <<<"$_pins") || _npins=0
_upins=$(sort -u <<<"$_pins")
if [[ -n "$_pin" && "$_npins" == 2 && "$_upins" == "$_pin" ]]; then pass "N1b the workflow carries exactly 2 VOLUME_ID_PIN literals (the two orphan sweeps), both equal to the inngest row's volume_id ${_pin}"
else fail "N1b the workflow carries ${_npins} VOLUME_ID_PIN literals with values [$(tr '\n' ' ' <<<"$_upins")], want exactly 2 equal to the inngest row's '${_pin}'"; fi
# N1c: the web1 row's pin is anchored OUTSIDE the workflow, to ADR-119's 2026-11-10 addendum (section-bounded: a mention anywhere
# else in the file cannot satisfy it) and to runbook 6604's read-only read-back line; and it differs from the inngest row's.
adr_section() { awk '/^## Addendum — 2026-11-10 \(#10432/{f=1; next} /^## /{f=0} f' "$1"; }
rb_section() { awk '/^## Read back the delete-protection flag \(read-only token\)$/{f=1; next} /^## /{f=0} f' "$1"; }
n1c() { # n1c <adr-119> <runbook-6604> <web1-pin> <inngest-pin>: prints one line per disagreement, nothing when all agree
  local _a _l _r
  _a=$(adr_section "$1" | grep -oE 'Hetzner id `?[0-9]+`?' | tr -d '`') || _a=""
  [[ "$(grep -c . <<<"$_a")" == 1 && "$_a" == "Hetzner id $3" ]] || printf 'ADR-119 addendum of 2026-11-10: want exactly one "Hetzner id %s", got [%s]\n' "$3" "$(tr '\n' ';' <<<"$_a")"
  _l=$(rb_section "$2" | grep -F -e '--only-secrets HCLOUD_TOKEN_READONLY') || _l=""
  _r=$(grep -oE 'v1/volumes/[0-9]+' <<<"$_l") || _r=""
  [[ "$(grep -c . <<<"$_l")" == 1 && "$(grep -c . <<<"$_r")" == 1 && "$_r" == "v1/volumes/$3" ]] || printf 'runbook 6604 read-back: want one read-only line naming exactly v1/volumes/%s, got %s line(s) [%s]\n' "$3" "$(grep -c . <<<"$_l")" "$(tr '\n' ';' <<<"$_r")"
  [[ -n "$3" && "$3" != "$4" ]] || printf 'the web1 pin is empty or equals the inngest pin (%s)\n' "$4"
}
_n1c=$(n1c "$ADR119" "$RB6604" "$_wpin" "$_pin")
if [[ -z "$_n1c" && "$_wpin" == "$(use_entry web1; printf '%s' "$VOL_ID")" ]]; then pass "N1c the web1 row's volume_id ($_wpin) equals the one 'Hetzner id' of ADR-119's 2026-11-10 addendum and the read-only read-back line of runbook 6604, and differs from the inngest row's"
else fail "N1c the web1 row's volume_id '$_wpin' is not anchored: ${_n1c:-it differs from the web-1 id of use_entry}"; fi
_dl=$(python3 -I - "$LOADER" "$TMP/x/job.json" <<'PYP'
import json, sys, yaml
steps = yaml.safe_load(open(sys.argv[1]))["runs"]["steps"]
ld = next(s for s in steps if "Install Doppler CLI" in str(s.get("name")))["env"]
jb = next(s for s in json.load(open(sys.argv[2]))["steps"] if s.get("id") == "doppler_cli")["env"]
print("same" if (ld["DOPPLER_CLI_VERSION"], ld["DOPPLER_CLI_SHA256"]) == (jb.get("DOPPLER_CLI_VERSION"), jb.get("DOPPLER_CLI_SHA256")) else "differs")
PYP
) || _dl=error
if [[ "$_dl" == same ]] && grep -qxF -- 'echo "${DOPPLER_CLI_SHA256}  $d/doppler.tar.gz" | sha256sum -c -' "$TMP/x/steps/doppler_cli.sh" && grep -qxF -- 'echo "$d" >> "$GITHUB_PATH"' "$TMP/x/steps/doppler_cli.sh"; then pass "N2 the job's Doppler CLI version and sha256 equal the loader's, and the tarball is verified with sha256sum -c"
else fail "N2 Doppler CLI pin: $_dl"; fi
# The read-back's command line (the one `doppler run` line of the subsection, so the outcome table and the prose may still name
# the flags and say it does not fall back): exactly one --only-secrets, naming the read-only token; the token to curl on stdin; no
# read/write name, no argv header, no fallback expansion.
rb_cmdline_ok() { # rb_cmdline_ok <runbook-6604>: 0 when the subsection's command line has that shape
  local l; l=$(rb_section "$1" | grep -E '^[[:space:]]*doppler run ') || return 1
  [[ "$(grep -c . <<<"$l")" == 1 && "$(grep -oF -e '--only-secrets' <<<"$l" | wc -l | tr -d ' ')" == 1 ]] || return 1
  grep -qF -e '--only-secrets HCLOUD_TOKEN_READONLY ' <<<"$l" || return 1
  grep -qF -e 'curl -sS --config -' <<<"$l" || return 1
  if grep -qE 'HCLOUD_TOKEN([^_]|$)' <<<"$l"; then return 1; fi
  if grep -qF -e '-H "Authorization' <<<"$l"; then return 1; fi
  if grep -qF -e ':-' <<<"$l"; then return 1; fi
  return 0
}
_ff=$(cat "$TMP/x/steps/file_finding.sh"); _fu=$(cat "$TMP/x/steps/file_unreadable.sh")
_n3=""
n3() { if ! "$@" >/dev/null 2>&1; then _n3+=" [$*]"; fi; }   # a failed pointer is named in the failure line
n3 grep -q '^## 5c\. Sole-copy protection and key loss$' "$RUNBOOK"
n3 grep -q '^### After a total loss' "$RUNBOOK"
n3 grep -q '^| `not-protected` (1) |' "$RUNBOOK"
n3 grep -q '^### Delivery route and ordering$' "$RUNBOOK"
n3 grep -qF 'the only delivery route is a `manual-rerun` dispatch of the' "$RUNBOOK"
n3 grep -q '^| O5 |' "$TIERS"
n3 test -f "$REPO_ROOT/plugins/soleur/skills/incident/SKILL.md"
n3 grep -qF 'Sole-copy protection and key loss' <<<"$_ff"
n3 grep -qF 'ADR-282' <<<"$_ff"
n3 grep -qF 'After a total loss' <<<"$_ff"
n3 grep -qF 'soleur:incident' <<<"$_ff"
n3 grep -qF 'table row \`not-protected\`' <<<"$_ff"
n3 grep -qF '\`manual-rerun\` dispatch' <<<"$_ff"
n3 grep -qF 'Decision record: ${ADR}.' <<<"$_fu"
n3 grep -qF 'infra-credential-tiers-8209.md' <<<"$_fu"
while IFS= read -r _ad; do
  n3 compgen -G "$REPO_ROOT/knowledge-base/engineering/architecture/decisions/${_ad:-none}-*.md"
done < <(jq -r '.[] | objects | .adr // "none"' "$TMP/x/rows.json")
n3 grep -qF 'D1 — the sole copy is protected in Terraform' "$ADR119"
n3 grep -q '^## Addendum (2026-10-08): the plaintext backstop is retired' "$ADR119"
n3 test "$(grep -cx '## Read back the delete-protection flag (read-only token)' "$RB6604")" = 1
n3 rb_cmdline_ok "$RB6604"
if [[ -z "$_n3" ]]; then pass "N3 every pointer the filer text makes resolves: ADR-282, runbook 5c, its not-protected row, the Delivery route text naming manual-rerun, After a total loss, the soleur:incident skill file, step O5 of infra-credential-tiers-8209.md, every row's ADR file, ADR-119 D1 and its 2026-10-08 addendum, runbook 6604's read-only read-back section and its command line"
else fail "N3 a filer pointer does not resolve:$_n3"; fi

# ---------------------------------------------------------------------------------------------------------
echo "H: harness rows -- the suite can see its own stub and its own comparison"
# ---------------------------------------------------------------------------------------------------------
new_scen   # a scenario of its own: nothing a table row left in the shared issue store (a stub refusal included) reaches these rows
_pre=$ROWS_RUN
listing "$(vol "$VOL_ID" "$NAME" true)" > "$TMP/force.json"
_h1=0
r_nextpage() { new_case; raw '{"volumes":[],"meta":{"pagination":{"next_page":2}}}'; go; want_out "${V}could-not-read|$OK_KEYS|http=200"; want_steps skip ran skip skip 1; }
for _r in r_lifted r_empty r_two r_nextpage; do
  EXTRA_ENV=("CURL_FORCE=$TMP/force.json"); "$_r"; _got="$CHK"; EXTRA_ENV=()
  if [[ -n "$_got" ]]; then _h1=$((_h1 + 1)); else echo "    $_r stayed green against a stub that always returns a matching fixture"; fi
done
INV_ACC=""; INV_DONE=1; use_entry web1
listing "$(vol "$VOL_ID" "$NAME" true)" > "$TMP/force.web1.json"
for _r in r_wlifted r_wempty r_wid; do
  EXTRA_ENV=("CURL_FORCE=$TMP/force.web1.json"); "$_r"; _got="$CHK"; EXTRA_ENV=()
  if [[ -n "$_got" ]]; then _h1=$((_h1 + 1)); else echo "    $_r stayed green against a stub that always returns a matching web-1 fixture"; fi
done
ROWS_RUN=$_pre; INV_ACC=""; INV_DONE=1; use_entry inngest
if [[ "$_h1" == 7 ]]; then pass "H1 a stub that always serves a matching fixture turns rows V2, V6, V7, M1 and the web-1 rows WV2, WV6, WV8 RED (the suite sees its own stub)"
else fail "H1 only $_h1 of 7 rows noticed a neutered stub"; fi
new_case; tf "$NAME" false; live true; go
CMP_MODE="exit"; want_out "${V}matches-declared"; _blind="$CHK"; CHK=""; CMP_MODE=full; want_out "${V}matches-declared|$OK_KEYS|live=true|volume_id=$VOL_ID|http=200"; _sees="$CHK"; CHK=""
if [[ -z "$_blind" && -n "$_sees" && "$(rs gate rc)" == 0 ]]; then pass "H2 lift-not-applied and matches-declared both exit 0 and differ only in outputs: an exit-code-only comparison is blind, the full comparison is not"
else fail "H2 output comparison self-test (blind='$_blind' sees='${_sees:+yes}')"; fi
if [[ "$ROWS_RUN" == "$TABLE_ROWS" ]]; then pass "H3 row conservation: the executed row count equals the declared TABLE_ROWS ($TABLE_ROWS)"
else fail "H3 executed $ROWS_RUN rows, declared TABLE_ROWS=$TABLE_ROWS"; fi
# NEGATIVE CONTROLS for the suite's own helpers. Each is fed a deliberately bad scenario inside a subshell (so no
# counter or CHK of the real run moves) and the verdict is reported with printf + exit, never through the helper
# under test. A helper that stops judging turns the matching row here RED.
_hb=$ROWS_RUN
_h4=$( PASS=0; FAIL=0; ROWS_RUN=0
  CHK=$'\n    boom'; end_row HX "negative" > "$TMP/h4.bad"
  [[ "$FAIL" == 1 && "$PASS" == 0 && "$ROWS_RUN" == 1 ]] || { printf 'a non-empty CHK did not count as one FAIL (pass=%s fail=%s)\n' "$PASS" "$FAIL"; exit 1; }
  [[ "$(sed -n 1p "$TMP/h4.bad")" == "  FAIL: HX negative"* ]] || { printf 'the FAIL line is not printed\n'; exit 1; }
  CHK=""; PASS=0; FAIL=0; end_row HX "positive" > "$TMP/h4.ok"
  [[ "$PASS" == 1 && "$FAIL" == 0 && "$(sed -n 1p "$TMP/h4.ok")" == "  pass: HX positive" ]] || { printf 'an empty CHK did not count as one pass\n'; exit 1; }
  CASE_N=$((CASE_N + 1)); new_case; echo "X=1" > "$CASE/github_env"; PASS=0; FAIL=0; end_row HX "invariants wired" > "$TMP/h4.inv"
  [[ "$FAIL" == 1 && "$PASS" == 0 ]] || { printf 'end_row did not run invariants(): a non-empty GITHUB_ENV passed\n'; exit 1; }
  printf 'ok' ) || _h4="exit"
if [[ "$_h4" == ok ]]; then pass "H4 end_row turns a non-empty CHK into a counted FAIL line and an empty one into a counted pass, and runs invariants()"
else fail "H4 end_row self-test: $_h4"; fi
ROWS_RUN=$_hb
_inv_fires() { # _inv_fires <setup-function>: 0 when invariants() reports something for the bad scenario (a fresh case dir each time)
  CASE_N=$((CASE_N + 1))
  ( new_case; "$1"; invariants; [[ -n "$CHK" ]] )
}
_iv_clean() { :; }
_iv_leak() { printf 'x %s y\n' "$TOK" > "$CASE/zz.log"; }
_iv_prefix() { printf 'dbg %s\n' "${TOK:0:6}" > "$CASE/zz.log"; }
_iv_rwleak() { printf 'x %s y\n' "$RWTOK" > "$CASE/zz.log"; }
_iv_rwprefix() { printf 'dbg %s\n' "$RWPFX" > "$CASE/zz.log"; }
_iv_dopleak() { printf 'x %s y\n' "$DOPTOK" > "$CASE/zz.log"; }
_iv_dopprefix() { printf 'dbg %s\n' "$DOPPFX" > "$CASE/zz.log"; }
_iv_argvprefix() { printf 'https://api.hetzner.cloud/v1/volumes?name=%s&per_page=50\0-H\0%s\0' "$CASE_NAME" "$TOKPFX" > "$CASE/curl.1.argv"; printf 'header = "Authorization: Bearer %s"' "$CASE_TOK" > "$CASE/curl.1.stdin"; }
_iv_argvrw() { printf 'https://api.hetzner.cloud/v1/volumes?name=%s&per_page=50\0-H\0%s\0' "$CASE_NAME" "$RWTOK" > "$CASE/curl.1.argv"; printf 'header = "Authorization: Bearer %s"' "$CASE_TOK" > "$CASE/curl.1.stdin"; }
_iv_argvrwprefix() { printf 'https://api.hetzner.cloud/v1/volumes?name=%s&per_page=50\0-H\0%s\0' "$CASE_NAME" "$RWPFX" > "$CASE/curl.1.argv"; printf 'header = "Authorization: Bearer %s"' "$CASE_TOK" > "$CASE/curl.1.stdin"; }
_iv_canary() { printf 'x %s y\n' "$CANARY" > "$CASE/summary"; }
_iv_ghenv() { echo "X=1" > "$CASE/github_env"; }
_iv_refused() { echo "refused: argv" > "$CASE/curl.refused"; }
_iv_heredoc() { printf 'verdict<<EOF\nx\nEOF\n' > "$CASE/out/probe"; }
_iv_url() { printf 'https://api.hetzner.cloud/v1/volumes?name=other&per_page=50\0' > "$CASE/curl.1.argv"; printf 'header = "Authorization: Bearer %s"' "$CASE_TOK" > "$CASE/curl.1.stdin"; }
_iv_cred() { printf 'https://api.hetzner.cloud/v1/volumes?name=%s&per_page=50\0' "$CASE_NAME" > "$CASE/curl.1.argv"; printf 'header = "Authorization: Bearer wrong"' > "$CASE/curl.1.stdin"; }
_iv_argvtok() { printf 'https://api.hetzner.cloud/v1/volumes?name=%s&per_page=50\0-H\0%s\0' "$CASE_NAME" "$TOK" > "$CASE/curl.1.argv"; printf 'header = "Authorization: Bearer %s"' "$CASE_TOK" > "$CASE/curl.1.stdin"; }
_iv_entry() { printf '{"entry":"%s","steps":{}}' "$OTHER_ENTRY" > "$CASE/result.json"; }
_iv_othername() { printf 'https://api.hetzner.cloud/v1/volumes?name=%s&per_page=50\0%s\0' "$CASE_NAME" "$OTHER_NAME" > "$CASE/curl.1.argv"; printf 'header = "Authorization: Bearer %s"' "$CASE_TOK" > "$CASE/curl.1.stdin"; }
_iv_otherid() { printf 'x %s y\n' "$OTHER_ID" > "$CASE/zz.log"; }
_iv_commits() { echo "gh api commits path=some-other-file" >> "$SEQ"; }
_iv_good() { printf 'https://api.hetzner.cloud/v1/volumes?name=%s&per_page=50\0' "$CASE_NAME" > "$CASE/curl.1.argv"; printf 'header = "Authorization: Bearer %s"' "$CASE_TOK" > "$CASE/curl.1.stdin"; }
_hv=""
for _f in _iv_leak _iv_prefix _iv_rwleak _iv_rwprefix _iv_dopleak _iv_dopprefix _iv_argvprefix _iv_argvrw _iv_argvrwprefix _iv_canary _iv_ghenv _iv_refused _iv_heredoc _iv_url _iv_cred _iv_argvtok _iv_entry _iv_othername _iv_otherid _iv_commits; do _inv_fires "$_f" || _hv+=" $_f"; done
for _f in _iv_clean _iv_good; do if _inv_fires "$_f"; then _hv+=" CONTROL:$_f"; fi; done
if [[ -z "$_hv" ]]; then pass "H5 invariants() flags a leaked token (read-only, read/write or Doppler), a 6-character prefix of each, a token or prefix on argv, a label canary, a non-empty GITHUB_ENV, a stub refusal, a heredoc output, a wrong request URL, a wrong credential channel, a token on argv, a result from another entry's row, the other entry's name on a request or id in a stream, and a commits read of another file, and stays quiet for a clean case"
else fail "H5 invariants self-test: not flagged or falsely flagged:$_hv"; fi
CASE_N=$((CASE_N + 1))
_h6=$( new_case; go
  CHK=""; want_steps skip skip ran skip 0; [[ -z "$CHK" ]] || { printf 'want_steps flagged the TRUE step set: %s\n' "$CHK"; exit 1; }
  CHK=""; want_steps ran ran ran ran 1; [[ -n "$CHK" ]] || { printf 'want_steps accepted a wrong step set\n'; exit 1; }
  CHK=""; want_steps skip skip ran skip 1; [[ -n "$CHK" ]] || { printf 'want_steps accepted a wrong gate rc\n'; exit 1; }
  CHK=""; want_req 1; [[ -z "$CHK" ]] || { printf 'want_req flagged the TRUE count\n'; exit 1; }
  CHK=""; want_req 5; [[ -n "$CHK" ]] || { printf 'want_req accepted a wrong count\n'; exit 1; }
  printf 'ok' ) || _h6="exit"
if [[ "$_h6" == ok ]]; then pass "H6 want_steps and want_req each accept the true value and flag a wrong one"
else fail "H6 want_steps / want_req self-test: $_h6"; fi

CASE_N=$((CASE_N + 10))
_h7=$( PASS=0; FAIL=0; ROWS_RUN=0; INV_ACC=""; INV_DONE=1
  new_case; echo "X=1" > "$CASE/github_env"
  new_case
  end_row HX "two-case row" > "$TMP/h7.out"
  [[ "$FAIL" == 1 && "$PASS" == 0 ]] || { printf 'a violation in the FIRST case of a two-case row was lost (pass=%s fail=%s)\n' "$PASS" "$FAIL"; exit 1; }
  PASS=0; FAIL=0; INV_ACC=""; INV_DONE=1
  new_case; new_case; end_row HX "clean two-case row" > "$TMP/h7.ok"
  [[ "$FAIL" == 0 && "$PASS" == 1 ]] || { printf 'a clean two-case row was flagged (pass=%s fail=%s)\n' "$PASS" "$FAIL"; exit 1; }
  printf 'ok' ) || _h7="exit"
if [[ "$_h7" == ok ]]; then pass "H7 the invariants run for EVERY case of a multi-case row, not only the last: a bad first case fails the row, a clean pair passes"
else fail "H7 per-case invariants self-test: $_h7"; fi
INV_ACC=""; INV_DONE=1

# H11: the matrix context is strict in BOTH the evaluator and the harness. Every verdict is reported with printf + exit, never through
# the helpers under test. H11b/H11c run against a COPY of the evaluator with its strict branch removed, so the harness's own check()
# is what is under test (otherwise the evaluator's strictness ends the run first and masks a check() that stopped looking).
mkdir -p "$TMP/h11" || fatal "mkdir h11"
_h11a=$( _r=0; python3 "$EXPRLIB" if "matrix.nope == 'x'" '{"matrix.entry":"web1"}' >/dev/null 2>&1 || _r=$?
  [[ "$_r" == 3 ]] || { printf 'an unknown matrix key in an if: exited %s, want 3\n' "$_r"; exit 1; }
  _v=$(python3 "$EXPRLIB" value "matrix.entry" '{"matrix.entry":"web1"}') || { printf 'a present matrix key did not render\n'; exit 1; }
  [[ "$_v" == web1 ]] || { printf 'matrix.entry rendered %s, want web1\n' "$_v"; exit 1; }
  _v=$(python3 "$EXPRLIB" value "steps.nope.outputs.x" '{}') || { printf 'an absent steps ref became an error (collateral strictness)\n'; exit 1; }
  [[ -z "$_v" ]] || { printf 'an absent steps ref rendered %s, want empty\n' "$_v"; exit 1; }
  printf 'ok' ) || _h11a="exit"
if [[ "$_h11a" == ok ]]; then pass "H11a the evaluator refuses an unknown matrix key (exit 3), renders a present one, and still renders an absent steps ref as empty"
else fail "H11a evaluator matrix strictness: $_h11a"; fi
grep -v 'strict-matrix' "$EXPRLIB" > "$TMP/h11/gha-expr-nostrict.py" || fatal "strip the strict branch"
h11_run() { # h11_run <evaluator> <env-expression> <entry> [<rows-json>]: runs a one-step job through the harness; prints rc, then stderr
  local d; d=$(mktemp -d "$TMP/h11/r.XXXXXX") || fatal "mktemp h11"
  printf 'printf "%%s" "$X" > "$OUT_X"\n' > "$d/s1.sh"
  local rows='[{"entry":"inngest","subject":"Inngest store volume"}]'; if [[ -n "${4-}" ]]; then rows="$4"; fi
  jq -n --arg v "$2" --argjson rows "$rows" \
    '{steps: [{id: "s1", run: "x", env: {X: $v}}], strategy: {"fail-fast": false, matrix: {include: $rows}}}' > "$d/job.json"
  jq -n --arg job "$d/job.json" --arg expr "$1" --arg case "$d/case" --arg x "$d" --arg entry "$3" --arg body "$d/s1.sh" --arg ox "$d/x.out" --arg path "$PATH" \
    '{job: $job, expr: $expr, case: $case, x: $x, entry: $entry, base_env: {PATH: $path, OUT_X: $ox}, overrides: {}, bodies: {s1: $body}, force_outcome: {}, allowed_outputs: {}, no_run: [], github: {}, secrets: {}}' > "$d/spec.json"
  local rc=0; python3 -I "$TMP/h.py" run "$d/spec.json" > "$d/stdout" 2> "$d/stderr" || rc=$?
  printf '%s\n' "$rc"; cat "$d/stderr"; [[ -f "$d/x.out" ]] && printf 'X=%s\n' "$(cat "$d/x.out")"
  return 0
}
_h11b=$( _s=$(python3 "$TMP/h11/gha-expr-nostrict.py" value "matrix.nope" '{}' 2>&1) || { printf 'the stripped evaluator is not runnable\n'; exit 1; }
  [[ -z "$_s" ]] || { printf 'the strict branch was not stripped (got %s)\n' "$_s"; exit 1; }
  cmp -s "$EXPRLIB" "$TMP/h11/gha-expr-nostrict.py" && { printf 'the strip did not land\n'; exit 1; }
  _o=$(h11_run "$TMP/h11/gha-expr-nostrict.py" '${{ matrix.nope }}' inngest)
  [[ "$_o" == $'3\nunresolvable reference: matrix.nope' ]] || { printf 'check() did not refuse matrix.nope on the stripped evaluator: [%s]\n' "$(tr '\n' '|' <<<"$_o")"; exit 1; }
  _o=$(h11_run "$EXPRLIB" '${{ matrix.nope }}' inngest); [[ "$(head -1 <<<"$_o")" == 3 ]] || { printf 'instrument control: the pristine harness did not exit 3\n'; exit 1; }
  _o=$(h11_run "$TMP/h11/gha-expr-nostrict.py" '${{ matrix.subject }}' inngest)
  [[ "$_o" == $'0\nX=Inngest store volume' ]] || { printf 'instrument control: a present key did not render on the stripped evaluator: [%s]\n' "$(tr '\n' '|' <<<"$_o")"; exit 1; }
  printf 'ok' ) || _h11b="exit"
if [[ "$_h11b" == ok ]]; then pass "H11b the harness's check() alone refuses a step env naming matrix.nope (exit 3, 'unresolvable reference: matrix.nope'); controls: pristine rc 3, a present key renders"
else fail "H11b check() matrix strictness: $_h11b"; fi
_h11c=$( _o=$(h11_run "$TMP/h11/gha-expr-nostrict.py" "\${{ matrix.entry == 'inngest' && matrix.nope == 'x' }}" inngest)
  [[ "$_o" == $'3\nunresolvable reference: matrix.nope' ]] || { printf 'the SECOND matrix ref of one expression was not checked: [%s]\n' "$(tr '\n' '|' <<<"$_o")"; exit 1; }
  printf 'ok' ) || _h11c="exit"
if [[ "$_h11c" == ok ]]; then pass "H11c a second matrix ref after a present first one is still refused (exit 3, the same stderr line)"
else fail "H11c second-member strictness: $_h11c"; fi
_h11d=$( _o=$(h11_run "$EXPRLIB" '${{ matrix.entry }}' zzz)
  [[ "$(head -1 <<<"$_o")" == 3 && "$_o" == *"row selection: 0 include rows"* ]] || { printf 'zero matching rows did not exit 3: [%s]\n' "$(tr '\n' '|' <<<"$_o")"; exit 1; }
  _o=$(h11_run "$EXPRLIB" '${{ matrix.entry }}' inngest '[{"entry":"inngest"},{"entry":"inngest"}]')
  [[ "$(head -1 <<<"$_o")" == 3 && "$_o" == *"row selection: 2 include rows"* ]] || { printf 'two matching rows did not exit 3: [%s]\n' "$(tr '\n' '|' <<<"$_o")"; exit 1; }
  _o=$(h11_run "$EXPRLIB" '${{ matrix.entry }}' web1 '[{"entry":"inngest"},{"entry":"web1"}]')
  [[ "$_o" == $'0\nX=web1' ]] || { printf 'control: one matching row did not render its entry: [%s]\n' "$(tr '\n' '|' <<<"$_o")"; exit 1; }
  printf 'ok' ) || _h11d="exit"
if [[ "$_h11d" == ok ]]; then pass "H11d the harness selects exactly one include row by entry: zero or two matches exit 3, one match renders that row"
else fail "H11d row selection: $_h11d"; fi
# H12: the issue-store id ban fires on a planted id (one leg; the ban does not depend on the leg).
_h12=""
_iv_issueid() { jq --arg b "body naming volume $VOL_ID" '. + [{number: 9, title: "t", state: "open", labels: ["infra-drift"], milestone: "", body: $b, author: "app/github-actions", comments: []}]' "$SCEN/issues.json" > "$SCEN/i.tmp" && mv "$SCEN/i.tmp" "$SCEN/issues.json"; }
_iv_commentid() { jq --arg c "comment naming $OTHER_ID" '. + [{number: 9, title: "t", state: "open", labels: ["infra-drift"], milestone: "", body: "b", author: "app/github-actions", comments: [$c]}]' "$SCEN/issues.json" > "$SCEN/i.tmp" && mv "$SCEN/i.tmp" "$SCEN/issues.json"; }
_iv_cleanissue() { jq '. + [{number: 9, title: "t", state: "open", labels: ["infra-drift"], milestone: "", body: "b", author: "app/github-actions", comments: ["c"]}]' "$SCEN/issues.json" > "$SCEN/i.tmp" && mv "$SCEN/i.tmp" "$SCEN/issues.json"; }
for _f in _iv_issueid _iv_commentid; do CASE_N=$((CASE_N + 1)); SCEN_N=$((SCEN_N + 1)); ( new_scen; new_case; "$_f"; invariants; [[ -n "$CHK" ]] ) || _h12+=" $_f"; done
CASE_N=$((CASE_N + 1)); SCEN_N=$((SCEN_N + 1)); if ( new_scen; new_case; _iv_cleanissue; invariants; [[ -n "$CHK" ]] ); then _h12+=" CONTROL:_iv_cleanissue"; fi
if [[ -z "$_h12" ]]; then pass "H12 invariants() reads the issue store: an id planted in an issue body or comment is flagged, a clean issue is not"
else fail "H12 issue-store id ban self-test: not flagged or falsely flagged:$_h12"; fi
# H13: use_entry web1 really switches the oracle (a no-op would turn every W case into a passing Inngest case).
_h13=$( use_entry web1
  [[ "$TITLE_DIFF" == "infra: web-1 workspaces volume "* && "$VOL_ID" == 106443278 && "$ENTRY" == web1 && "$TF_REL" == apps/web-platform/infra/workspaces-luks.tf && "$OTHER_ID" == 106903269 ]] \
    || { printf 'use_entry web1 left TITLE_DIFF=%s VOL_ID=%s ENTRY=%s\n' "$TITLE_DIFF" "$VOL_ID" "$ENTRY"; exit 1; }
  use_entry inngest
  [[ "$TITLE_DIFF" == "infra: Inngest store volume "* && "$VOL_ID" == 106903269 && "$ENTRY" == inngest ]] || { printf 'use_entry inngest did not switch back\n'; exit 1; }
  printf 'ok' ) || _h13="exit"
if [[ "$_h13" == ok ]]; then pass "H13 use_entry web1 sets the web-1 titles, id, file and other-entry id; use_entry inngest switches back"
else fail "H13 use_entry self-test: $_h13"; fi
# H14: N1c's section bounds. Each mutant is a COPY; the real documents are never edited. Each must make n1c report.
mkdir -p "$TMP/n1c" || fatal "mkdir n1c"
_h14=""
n1c_mut() { # n1c_mut <label> <adr-copy> <runbook-copy>: the copy must differ from the real file and n1c must report
  if cmp -s "$2" "$ADR119" && cmp -s "$3" "$RB6604"; then _h14+=" $1(did-not-land)"; return; fi
  [[ -n "$(n1c "$2" "$3" "$_wpin" "$_pin")" ]] || _h14+=" $1"
}
awk '{print} /^## Addendum — 2026-11-10 \(#10432/{print "The orphaned volume was Hetzner id 106406962."}' "$ADR119" > "$TMP/n1c/adr.two.md"
n1c_mut two-matches "$TMP/n1c/adr.two.md" "$RB6604"
awk '/^## Addendum — 2026-11-10 \(#10432/{print; f=1; next} /^## /{f=0} !f' "$ADR119" > "$TMP/n1c/adr.empty.md"
n1c_mut empty-addendum "$TMP/n1c/adr.empty.md" "$RB6604"
awk -v pin="$_wpin" '/^## Addendum — 2026-11-10 \(#10432/{f=1; print "Hetzner id " pin " (stated before the section)"; print; next} /^## /{f=0} f && /Hetzner id/{gsub(/Hetzner id `?[0-9]+`?/, "the volume")} {print}' "$ADR119" > "$TMP/n1c/adr.moved.md"
n1c_mut moved-outside-the-section "$TMP/n1c/adr.moved.md" "$RB6604"
awk '/^## Read back the delete-protection flag \(read-only token\)$/{print; f=1; next} /^## /{f=0} !f' "$RB6604" > "$TMP/n1c/rb.empty.md"
n1c_mut emptied-read-back-section "$ADR119" "$TMP/n1c/rb.empty.md"
if [[ -z "$_h14" ]]; then pass "H14 N1c goes RED on a copy with a second 'Hetzner id' in the addendum, an empty addendum, the id moved outside the section, and an emptied runbook read-back section"
else fail "H14 N1c section-bound self-test: not caught:$_h14"; fi
# H15: the read-back command-line check, one mutant per banned pattern (each on a copy; each must fail rb_cmdline_ok).
_h15=""
rb_mut() { # rb_mut <label> <sed-expression applied to the --only-secrets line of the read-back section>
  awk '/^## Read back the delete-protection flag \(read-only token\)$/{f=1} /^## /&&!/^## Read back the delete-protection flag/{f=0} {print (f && /^[ \t]*doppler run / ? "@@CMD@@" $0 : $0)}' "$RB6604" \
    | sed -e "/^@@CMD@@/{$2}" -e 's/^@@CMD@@//' > "$TMP/n1c/rb.$1.md"
  if cmp -s "$TMP/n1c/rb.$1.md" "$RB6604"; then _h15+=" $1(did-not-land)"; return; fi
  if rb_cmdline_ok "$TMP/n1c/rb.$1.md"; then _h15+=" $1"; fi
}
rb_mut second-only-secrets 's/--only-secrets HCLOUD_TOKEN_READONLY /--only-secrets HCLOUD_TOKEN_READONLY --only-secrets HCLOUD_TOKEN /'
rb_mut argv-header 's/curl -sS --config - /curl -sS -H "Authorization: Bearer $HCLOUD_TOKEN_READONLY" --config - /'
rb_mut fallback-expansion 's/"\$HCLOUD_TOKEN_READONLY" | curl/"${HCLOUD_TOKEN_READONLY:-$HCLOUD_TOKEN}" | curl/'
if [[ -z "$_h15" ]]; then pass "H15 the read-back command-line check fails a second --only-secrets of the read/write name, an argv bearer header and a fallback expansion (each on a copy)"
else fail "H15 read-back command-line self-test: not caught:$_h15"; fi

cmp -s "$LIBREAL" "$TMP/lib/bearer-curl.sh" || fail "Z0 the library copy drifted during the run"
echo ""
echo "=== Results: $PASS/$((PASS + FAIL)) passed, $FAIL failed ==="
if [[ "$FAIL" -gt 0 ]]; then exit 1; fi
