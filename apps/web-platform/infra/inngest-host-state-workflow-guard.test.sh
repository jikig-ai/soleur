#!/usr/bin/env bash
# Guard tests for the one-tap inngest host-state read (#8449 UC2).
#
# SUBJECT: .github/workflows/inngest-host-state.yml, a workflow_dispatch wrapper around
# scripts/inngest-host-state.sh. Two failure modes share this suite:
#
#   1. A LEAK. The repository is PUBLIC and the script prints unscrubbed journald text. The
#      workflow may put ONLY the rc, its meaning and the anchored VERDICT line in the log and the
#      step summary — never out.txt, and never as an artifact.
#   2. A GATE THAT LOOKS PRESENT AND DOES NOTHING. `run:` is `bash -e`, so a missing `|| rc=$?`
#      kills the step before the summary and the ::error:: line are written; a code missing from
#      the rc table renders an honest "the read failed" as "unknown"; a template expression in
#      `run:` turns a dispatcher's string into code.
#
# STATIC CHECKS ARE AGAINST PARSED YAML (a grep passes on a commented-out line). BEHAVIOURAL CHECKS
# EXECUTE the extracted `run:` body under `bash --noprofile --norc -eo pipefail` — the shell
# Actions injects — with the script stubbed to return every code the script's own `Exit codes:`
# header lists. The code set is DERIVED from that header, never hand-listed here, and it must be
# IDENTICAL to both the workflow's meaning table and its summary loop.
#
# The stub prints a canary on stdout and stderr, standing in for host text. The canary reaching
# the job log or the summary is the leak, measured rather than inferred from the source.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

WF="$REPO_ROOT/.github/workflows/inngest-host-state.yml"
HOST_SCRIPT="$REPO_ROOT/scripts/inngest-host-state.sh"
HEALTH_WF="$REPO_ROOT/.github/workflows/scheduled-inngest-health.yml"
INFRA_WF="$REPO_ROOT/.github/workflows/infra-validation.yml"
STEP_NAME="Read dedicated inngest host state"
CANARY="LEAK-CANARY-8449-host-journal-text"

# A skip is not a pass. TMPDIR is pinned so a runner with a tiny /tmp cannot turn the executed
# arms into a silent no-op.
export TMPDIR="${TMPDIR:-/var/tmp}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0
FAIL=0
assert() {
  local desc="$1" cond="$2"
  if eval "$cond"; then echo "  PASS: $desc"; PASS=$((PASS + 1));
  else echo "  FAIL: $desc"; echo "    cond: $cond"; FAIL=$((FAIL + 1)); fi
}

echo "=== inngest-host-state workflow guard tests (#8449 UC2) ==="

assert "workflow exists" "[[ -f '$WF' ]]"
assert "the wrapped script exists" "[[ -f '$HOST_SCRIPT' ]]"
assert "the pin-reference workflow exists" "[[ -f '$HEALTH_WF' ]]"
assert "infra-validation workflow exists" "[[ -f '$INFRA_WF' ]]"
for f in "$WF" "$HEALTH_WF" "$INFRA_WF"; do
  assert "YAML parses (pyyaml): ${f#"$REPO_ROOT/"}" \
    "python3 -c 'import yaml; yaml.safe_load(open(\"$f\"))'"
done

# ---------------------------------------------------------------------------
# The static probe. Parameterised by PATH so the mutation arms re-run it against a mutated copy.
# Prints yes/no for a boolean check, or a value for the extraction checks.
# ---------------------------------------------------------------------------
probe_wf() {
  python3 - "$1" "$2" "$HOST_SCRIPT" "$HEALTH_WF" "$STEP_NAME" <<'PY'
import re, sys, yaml

wf_path, check, script_path, health_path, step_name = sys.argv[1:6]
wf = yaml.safe_load(open(wf_path)) or {}
# `on` is YAML 1.1 truthy: pyyaml keys a bare `on:` as boolean True. Probe both spellings.
on = wf.get("on", wf.get(True)) or {}
jobs = wf.get("jobs") or {}
steps = [s for j in jobs.values() for s in (j.get("steps") or [])]
step = next((s for s in steps if s.get("name") == step_name), None) or {}
run = str(step.get("run", ""))
env = step.get("env") or {}
live = [l for l in run.splitlines() if not l.lstrip().startswith("#")]

def norm(v):
    return " ".join(str(v).split())

def inputs():
    return ((on.get("workflow_dispatch") or {}).get("inputs")) or {}

SHA = re.compile(r"^[A-Za-z0-9_.-]+/[A-Za-z0-9_./-]+@[0-9a-f]{40}$")

def uses_all_pinned():
    us = [str(s["uses"]) for s in steps if "uses" in s]
    return bool(us) and all(u.startswith("./") or SHA.match(u) for u in us)

def pins_match_health():
    h = yaml.safe_load(open(health_path)) or {}
    hp = {}
    for j in (h.get("jobs") or {}).values():
        for s in (j.get("steps") or []):
            u = str(s.get("uses", ""))
            if "@" in u:
                hp[u.split("@", 1)[0]] = u.split("@", 1)[1]
    mine = [str(s["uses"]) for s in steps if "@" in str(s.get("uses", ""))]
    # Every external action this workflow uses must be one the reference pins, at its pin.
    return bool(mine) and all(u.split("@", 1)[0] in hp and hp[u.split("@", 1)[0]] == u.split("@", 1)[1]
                              for u in mine)

# The invocation, anchored on the ACTUAL command line with its capture. A comment mentioning
# `|| rc=$?` cannot satisfy it (comments are dropped from `live`).
INVOKE = re.compile(r'^\s*bash scripts/inngest-host-state\.sh\b.*>\s*out\.txt 2>&1 \|\| rc=\$\?\s*$')
VERDICT_GREP = re.compile(r"""^\s*verdict="\$\(grep -m1 -E '(\^  VERDICT[^']*)' out\.txt \|\| true\)"\s*$""")
# THE ALLOW-LIST OF WAYS out.txt MAY APPEAR. Anything else that names it — `cat`, `head`,
# `tee`, a `>> $GITHUB_STEP_SUMMARY` of it, an upload path — is a leak of host text into a public
# log. An allow-list rather than a deny-list: the deny-list is the one that misses `sed -n p`.
ALLOWED_OUT = [
    INVOKE,
    VERDICT_GREP,
    re.compile(r'^\s*if \[ -f out\.txt \]; then\s*$'),
    re.compile(r'^\s*wrapper_fault="out\.txt is missing[^"$`]*"\s*$'),
]

def out_txt_allowlisted():
    hits = [l for l in live if "out.txt" in l]
    return bool(hits) and all(any(p.match(l) for p in ALLOWED_OUT) for l in hits)

def out_txt_only_in_read_step():
    for s in steps:
        if s is step:
            continue
        if "out.txt" in yaml.safe_dump(s):
            return False
    return True

def no_upload():
    return not any("upload-artifact" in str(s.get("uses", "")) for s in steps)

def verdict_regex():
    for l in live:
        m = VERDICT_GREP.match(l)
        if m:
            return m.group(1)
    return None

def header_codes():
    lines = open(script_path).read().splitlines()
    try:
        i = next(k for k, l in enumerate(lines) if l.strip() == "# Exit codes:")
    except StopIteration:
        return []
    codes = []
    for l in lines[i + 1:]:
        if not l.startswith("#") or l.strip() == "#":
            break
        m = re.match(r"^#\s{1,4}(\d+)\s+-\s", l)
        if m:
            codes.append(int(m.group(1)))
    return sorted(set(codes))

def case_codes():
    return sorted({int(m.group(1)) for l in live for m in [re.match(r"^\s*(\d+)\)\s+echo\b", l)] if m})

def loop_codes():
    for l in live:
        m = re.match(r"^\s*for c in ([\d ]+); do\s*$", l)
        if m:
            return sorted({int(x) for x in m.group(1).split()})
    return []

def marker_fmt():
    m = re.search(r'print\("(  VERDICT[^"]*)"', open(script_path).read())
    return m.group(1) if m else None

def marker_matches():
    fmt, rx = marker_fmt(), verdict_regex()
    if not fmt or not rx:
        return False
    rendered = [
        fmt % ("SERVING", "yes", ""),
        fmt % ("NOT SERVING", "no", ""),
        fmt % ("NOT SERVING", "no", "   AS OF 12m AGO — NOT NECESSARILY NOW"),
        fmt % ("SERVING", "yes", "   AS OF AN UNKNOWN TIME — the dt on this row did not parse"),
    ]
    return all(re.match(rx, r) for r in rendered)

def marker_rejects_error_scan():
    # The error-scan section prints `  <dt>  <free host text>`. Host text that merely CONTAINS
    # the marker must not be extractable as the verdict.
    rx = verdict_regex()
    return bool(rx) and not re.match(rx, "  2026-09-17 12:00:00    VERDICT        SERVING   SERVING=yes") \
        and not re.match(rx, "x  VERDICT        SERVING   SERVING=yes")

checks = {
    "dispatch_only": set(on) == {"workflow_dispatch"},
    "input_set": set(inputs()) == {"since", "include_errors"},
    "since_input": (inputs().get("since") or {}).get("type") == "string"
                   and str((inputs().get("since") or {}).get("default")) == "90m",
    "include_errors_default_false": (inputs().get("include_errors") or {}).get("type") == "boolean"
                   and (inputs().get("include_errors") or {}).get("default") is False,
    "permissions_exact": wf.get("permissions") == {"contents": "read"}
                   and not any("permissions" in j for j in jobs.values()),
    "concurrency": (wf.get("concurrency") or {}).get("group") == "inngest-host-state",
    "timeout_5": bool(jobs) and all(j.get("timeout-minutes") == 5 for j in jobs.values()),
    "step_found": bool(run),
    "no_expr_in_run": bool(steps) and not any("${{" in str(s.get("run", "")) for s in steps),
    "secrets_wired": all(norm(env.get(n, "")) == "${{ secrets.%s }}" % n for n in
                         ("BETTERSTACK_QUERY_HOST", "BETTERSTACK_QUERY_USERNAME", "BETTERSTACK_QUERY_PASSWORD")),
    "inputs_via_env": norm(env.get("SINCE", "")) == "${{ inputs.since }}"
                      and norm(env.get("INCLUDE_ERRORS", "")) == "${{ inputs.include_errors }}",
    "uses_all_pinned": uses_all_pinned(),
    "pins_match_health": pins_match_health(),
    "rc_capture": any(INVOKE.match(l) for l in live),
    "since_regex_checked": any(re.match(r'^\s*if \[\[ "\$SINCE" =~ \^\[0-9\]\+\[hmd\]\$ \]\]; then\s*$', l) for l in live),
    "out_txt_allowlisted": out_txt_allowlisted(),
    "out_txt_only_in_read_step": out_txt_only_in_read_step(),
    "no_upload": no_upload(),
    "marker_matches": marker_matches(),
    "marker_rejects_error_scan": marker_rejects_error_scan(),
    "header_floor": len(header_codes()) >= 7,
    "case_is_header": case_codes() == header_codes() and bool(header_codes()),
    "loop_is_header": loop_codes() == header_codes() and bool(header_codes()),
}
values = {
    "header_codes": " ".join(map(str, header_codes())),
    "run_body": run,
    "marker_fmt": marker_fmt() or "",
}
if check in values:
    sys.stdout.write(values[check])
else:
    print("yes" if checks[check] else "no")
PY
}

echo ""
echo "--- trigger, inputs, permissions, serialisation, pinning ---"
for c in dispatch_only input_set since_input include_errors_default_false permissions_exact \
         concurrency timeout_5 step_found secrets_wired inputs_via_env uses_all_pinned pins_match_health; do
  assert "static: $c" "[[ \$(probe_wf '$WF' $c) == 'yes' ]]"
done

echo ""
echo "--- injection, capture, leak surface ---"
for c in no_expr_in_run since_regex_checked rc_capture out_txt_allowlisted out_txt_only_in_read_step no_upload; do
  assert "static: $c" "[[ \$(probe_wf '$WF' $c) == 'yes' ]]"
done

echo ""
echo "--- the code set is DERIVED from the script header, and the table is identical to it ---"
CODES="$(probe_wf "$WF" header_codes)"
echo "  (derived from the script's Exit codes: header: $CODES)"
for c in header_floor case_is_header loop_is_header; do
  assert "codes: $c" "[[ \$(probe_wf '$WF' $c) == 'yes' ]]"
done

echo ""
echo "--- the verdict marker is checked against the SCRIPT, not restated ---"
for c in marker_matches marker_rejects_error_scan; do
  assert "marker: $c" "[[ \$(probe_wf '$WF' $c) == 'yes' ]]"
done

# ---------------------------------------------------------------------------
# EXECUTED ARMS. The `run:` body is extracted from the parsed YAML and run under the shell Actions
# uses, with scripts/inngest-host-state.sh replaced by a stub in a scratch cwd.
# ---------------------------------------------------------------------------
probe_wf "$WF" run_body > "$TMP/run.sh"
VERDICT_LINE="$(python3 -c 'import sys; print(sys.argv[1] % ("NOT SERVING", "no", "   AS OF 12m AGO — NOT NECESSARILY NOW"))' "$(probe_wf "$WF" marker_fmt)")"

# run_case <run.sh> <name> <stub rc> <since> <include_errors> <verdict line> <rm out.txt 0|1>
# Leaves $TMP/<name>/{log,summary.md,args,jrc}.
run_case() {
  local runsh="$1" name="$2" src="$3" since="$4" inc="$5" verdict="$6" rmout="$7" d jrc=0
  d="$TMP/$name"
  mkdir -p "$d/scripts"
  cat > "$d/scripts/inngest-host-state.sh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$STUB_ARGS"
echo "$STUB_CANARY stdout: free-form journald message from the host"
echo "$STUB_CANARY stderr: query tool stderr head" >&2
if [ -n "$STUB_VERDICT" ]; then printf '%s\n' "$STUB_VERDICT"; fi
if [ "$STUB_RM_OUT" = 1 ]; then rm -f out.txt; fi
exit "$STUB_RC"
STUB
  : > "$d/summary.md"
  (cd "$d" && env -i PATH="$PATH" SINCE="$since" INCLUDE_ERRORS="$inc" \
      GITHUB_STEP_SUMMARY="$d/summary.md" STUB_ARGS="$d/args" STUB_CANARY="$CANARY" \
      STUB_RC="$src" STUB_VERDICT="$verdict" STUB_RM_OUT="$rmout" \
      bash --noprofile --norc -eo pipefail "$runsh" > "$d/log" 2>&1) || jrc=$?
  echo "$jrc" > "$d/jrc"
}
jrc_of() { cat "$TMP/$1/jrc"; }
no_leak() { ! grep -qF -- "$CANARY" "$TMP/$1/log" && ! grep -qF -- "$CANARY" "$TMP/$1/summary.md"; }
# The stub DID print the canary into out.txt — so "absent from the log" is a measured absence,
# not a stub that never spoke.
canary_in_out() { grep -qF -- "$CANARY" "$TMP/$1/out.txt"; }

echo ""
echo "--- executed: every derived code, job exit + summary + ::error:: + no leak ---"
for code in $CODES; do
  n="code-$code"
  if [[ "$code" == 0 ]]; then v="$VERDICT_LINE"; else v=""; fi
  run_case "$TMP/run.sh" "$n" "$code" 90m false "$v" 0
  if [[ "$code" == 0 ]]; then
    assert "rc 0: job exits 0" "[[ \$(jrc_of $n) -eq 0 ]]"
    assert "rc 0: summary and log carry the VERDICT line rendered from the script's marker" \
      "grep -qxF -- \"\$VERDICT_LINE\" '$TMP/$n/summary.md' && grep -qxF -- \"\$VERDICT_LINE\" '$TMP/$n/log'"
    assert "rc 0: no ::error:: on a clean read" "! grep -qF '::error::' '$TMP/$n/log'"
  else
    assert "rc $code: job exits NON-zero" "[[ \$(jrc_of $n) -ne 0 ]]"
    assert "rc $code: log carries ::error::inngest-host-state rc=$code" \
      "grep -qF -- '::error::inngest-host-state rc=$code — ' '$TMP/$n/log'"
  fi
  assert "rc $code: summary names rc=$code with a DOCUMENTED meaning" \
    "grep -qF -- '**rc=$code** — ' '$TMP/$n/summary.md' && ! grep -qF -- 'header does not document' '$TMP/$n/summary.md'"
  assert "rc $code: the canary reached out.txt (the stub spoke) yet NOT the log or the summary" \
    "canary_in_out $n && no_leak $n"
done

assert "rc 4 reads as a finding: 'silence is not health'" \
  "grep -qF -- 'silence is not health' '$TMP/code-4/summary.md'"
assert "rc 6 reads as an instrument fault: 'says nothing about the host'" \
  "grep -qF -- 'says nothing about the host' '$TMP/code-6/summary.md'"
# The rendered table is the same set as the header, measured from the OUTPUT.
# `{ grep || true; }`: an empty table is an ANSWER (it fails the assert below), not a reason for
# `set -e` to kill the suite before it reports.
# shellcheck disable=SC2034  # read inside assert's eval
ROWS="$({ grep -oE '^\| [0-9]+ \|' "$TMP/code-0/summary.md" || true; } | tr -dc '0-9\n' | sort -n | paste -sd' ' -)"
assert "the rendered summary table's rows are exactly the derived code set ($CODES)" \
  "[[ \"\$ROWS\" == \"\$CODES\" ]]"

echo ""
echo "--- executed: the wrapper's own faults are non-zero too ---"
run_case "$TMP/run.sh" undoc 1 90m false "" 0
assert "an undocumented rc (1) exits non-zero with ::error:: and says so" \
  "[[ \$(jrc_of undoc) -ne 0 ]] && grep -qF -- '::error::inngest-host-state rc=1 — ' '$TMP/undoc/log' && grep -qF 'header does not document' '$TMP/undoc/summary.md'"
run_case "$TMP/run.sh" noverdict 0 90m false "" 0
assert "rc 0 with no VERDICT line exits non-zero (a green run must carry a verdict)" \
  "[[ \$(jrc_of noverdict) -ne 0 ]] && grep -qF '::error::' '$TMP/noverdict/log'"
run_case "$TMP/run.sh" noout 0 90m false "$VERDICT_LINE" 1
assert "rc 0 with out.txt missing exits non-zero" \
  "[[ \$(jrc_of noout) -ne 0 ]] && grep -qF 'out.txt is missing' '$TMP/noout/log'"

echo ""
echo "--- executed: inputs ---"
run_case "$TMP/run.sh" badsince 0 90 false "$VERDICT_LINE" 0
assert "since='90' (no unit) is refused as rc 2 and the script is NEVER invoked" \
  "[[ \$(jrc_of badsince) -ne 0 ]] && grep -qF '**rc=2** — ' '$TMP/badsince/summary.md' && [[ ! -e '$TMP/badsince/args' ]]"
# shellcheck disable=SC2016  # literal on purpose: the payload must NOT expand here
run_case "$TMP/run.sh" injsince 0 '1h$(touch pwned)' false "$VERDICT_LINE" 0
assert "since carrying a command substitution is refused, never executed, never echoed" \
  "[[ \$(jrc_of injsince) -ne 0 ]] && [[ ! -e '$TMP/injsince/pwned' ]] && [[ ! -e '$TMP/injsince/args' ]] && ! grep -qF 'touch pwned' '$TMP/injsince/log'"
run_case "$TMP/run.sh" noerr 0 45m false "$VERDICT_LINE" 0
assert "include_errors=false passes --since 45m --no-errors" \
  "[[ \"\$(paste -sd' ' '$TMP/noerr/args')\" == '--since 45m --no-errors' ]]"
run_case "$TMP/run.sh" witherr 0 2h true "$VERDICT_LINE" 0
assert "include_errors=true passes --since 2h and NOT --no-errors" \
  "[[ \"\$(paste -sd' ' '$TMP/witherr/args')\" == '--since 2h' ]]"

# ---------------------------------------------------------------------------
# MUTATION ARMS. A guard that has never been observed failing is indistinguishable from one that
# cannot fail. Each mutant is built from the REAL run body / workflow, its landing is asserted
# first (a mutation that did not land is a null result wearing a pass's clothes), then the arm
# that should catch it is required to go red.
# ---------------------------------------------------------------------------
echo ""
echo "--- mutation arms ---"

# M1: drop `|| rc=$?` — bash -e kills the step before the summary is written.
sed 's/ || rc=\$?$//' "$TMP/run.sh" > "$TMP/m1.sh"
assert "M1 landed: the mutant's invocation line has no || rc=\$? capture" \
  "! grep -qE '> out\\.txt 2>&1 \\|\\| rc=\\\$\\?\$' '$TMP/m1.sh' && grep -qE '^ *bash scripts/inngest-host-state\\.sh .*> out\\.txt 2>&1\$' '$TMP/m1.sh'"
run_case "$TMP/m1.sh" m1 6 90m false "" 0
assert "M1 caught: without the capture, rc 6 writes NO rc line to the summary" \
  "! grep -qF '**rc=6** — ' '$TMP/m1/summary.md'"

# M2: `cat out.txt` into the summary — the leak.
# shellcheck disable=SC2016  # literal on purpose: this is the mutant's source text
{ cat "$TMP/run.sh"; echo 'cat out.txt >> "$GITHUB_STEP_SUMMARY"'; } > "$TMP/m2.sh"
run_case "$TMP/m2.sh" m2 0 90m false "$VERDICT_LINE" 0
assert "M2 caught (executed): catting out.txt puts the canary in the summary" "! no_leak m2"
python3 - "$WF" "$TMP/m2.yml" "$STEP_NAME" <<'PY'
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1]))
for j in wf["jobs"].values():
    for s in j["steps"]:
        if s.get("name") == sys.argv[3]:
            s["run"] += "cat out.txt\n"
yaml.safe_dump(wf, open(sys.argv[2], "w"), sort_keys=False)
PY
assert "M2 caught (static): the out.txt allow-list rejects a bare cat" \
  "[[ \$(probe_wf '$TMP/m2.yml' out_txt_allowlisted) == 'no' ]]"

# M3: `${{ inputs.since }}` inside run:.
python3 - "$WF" "$TMP/m3.yml" "$STEP_NAME" <<'PY'
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1]))
for j in wf["jobs"].values():
    for s in j["steps"]:
        if s.get("name") == sys.argv[3]:
            s["run"] = s["run"].replace('--since "$SINCE"', '--since "${{ inputs.since }}"')
yaml.safe_dump(wf, open(sys.argv[2], "w"), sort_keys=False)
PY
assert "M3 landed: the mutant carries an inputs expression in run:" "grep -qF '\${{ inputs.since }}' '$TMP/m3.yml'"
assert "M3 caught: no_expr_in_run rejects it" "[[ \$(probe_wf '$TMP/m3.yml' no_expr_in_run) == 'no' ]]"

# M4: drop one code (6 — the one whose loss re-creates the "read failure as outage" defect).
python3 - "$WF" "$TMP/m4.yml" "$STEP_NAME" <<'PY'
import re, sys, yaml
wf = yaml.safe_load(open(sys.argv[1]))
for j in wf["jobs"].values():
    for s in j["steps"]:
        if s.get("name") == sys.argv[3]:
            s["run"] = "\n".join(l for l in s["run"].split("\n") if not re.match(r"^\s*6\)\s", l))
yaml.safe_dump(wf, open(sys.argv[2], "w"), sort_keys=False)
PY
assert "M4 caught (static): a code dropped from the meaning table breaks set identity" \
  "[[ \$(probe_wf '$TMP/m4.yml' case_is_header) == 'no' ]]"
probe_wf "$TMP/m4.yml" run_body > "$TMP/m4.sh"
run_case "$TMP/m4.sh" m4 6 90m false "" 0
assert "M4 caught (executed): rc 6 then renders as undocumented" \
  "grep -qF 'header does not document' '$TMP/m4/summary.md'"

echo ""
echo "--- CI wiring, asserted from PARSED YAML ---"
probe_infra() {
  python3 - "$INFRA_WF" "$1" <<'PY'
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1])) or {}
on = wf.get("on", wf.get(True)) or {}
job = (wf.get("jobs") or {}).get("deploy-script-tests") or {}
runs = [str(s.get("run", "")) for s in (job.get("steps") or [])]
pr_paths = list((on.get("pull_request") or {}).get("paths") or [])
checks = {
    # Literal single-line form: run-registered-suites.sh derives its execute set from it.
    "suite_registered": any(r.strip() == "bash apps/web-platform/infra/inngest-host-state-workflow-guard.test.sh" for r in runs),
    "wf_path": ".github/workflows/inngest-host-state.yml" in pr_paths,
    "script_path": "scripts/inngest-host-state.sh" in pr_paths,
}
print("yes" if checks[sys.argv[2]] else "no")
PY
}
assert "this suite is registered in deploy-script-tests as a literal \`run: bash <path>\` step" \
  "[[ \$(probe_infra suite_registered) == 'yes' ]]"
assert "inngest-host-state.yml is in infra-validation's pull_request.paths" \
  "[[ \$(probe_infra wf_path) == 'yes' ]]"
assert "scripts/inngest-host-state.sh is in infra-validation's pull_request.paths" \
  "[[ \$(probe_infra script_path) == 'yes' ]]"

echo ""
echo "=== Results: $PASS/$((PASS + FAIL)) passed ==="

# ANTI-VACUITY FLOOR. The only other gate is `FAIL > 0`, so removing the assert calls yields
# PASS=0 FAIL=0 and exit 0. Reported by printf + exit 1, never through assert(), so neutering
# the assertion machinery cannot disarm it. A FLOOR, never an equality: raise it in lockstep
# when assertions are added.
MIN_ASSERTIONS=80
if (( PASS + FAIL < MIN_ASSERTIONS )); then
  printf 'FAIL: only %d assertions ran, below the floor of %d. Treat this as UN-RUN, not as a pass.\n' \
    "$((PASS + FAIL))" "$MIN_ASSERTIONS"
  exit 1
fi

if (( FAIL > 0 )); then
  echo "FAIL: $FAIL test(s) failed"
  exit 1
fi
