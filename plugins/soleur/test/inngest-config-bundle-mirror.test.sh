#!/usr/bin/env bash
# Guard for the zot mirror step of .github/workflows/build-inngest-config-bundle.yml (#7243).
#
# The defect (#6416 class): the mirror step was gated on `steps.zot_bridge.outcome == 'success'`,
# so a soft-failed Cloudflare-tunnel bridge SKIPPED the step and the run stayed green with no
# output, no annotation and no summary line. A bridge failing on every dispatch was
# indistinguishable from one that works.
#
# The fix: the step runs whenever the image build succeeded, receives the bridge result as the
# BRIDGE_OUTCOME env var and degrades loudly (outputs + ::warning:: + summary line, exit 0)
# when the bridge did not succeed or the crane install / copy fails. The step keeps
# continue-on-error: GHCR is authoritative and this workflow has no mirror-only mode.
#
# This suite parses the workflow as YAML (structural leg), extracts the REAL `run:` body by step
# name and executes it under `bash -eo pipefail` with PATH stubs (behavioural leg), then proves
# the guard itself is not vacuous by running the same evaluator over mutated copies of the
# workflow (mutation battery). Run via: bash plugins/soleur/test/inngest-config-bundle-mirror.test.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
WF="$REPO_ROOT/.github/workflows/build-inngest-config-bundle.yml"
STEP_NAME="Mirror bundle GHCR->zot (crane, digest-preserving)"

PASS=0
FAIL=0
fail() {
  echo "  FAIL: $1"
  FAIL=$((FAIL + 1))
}
pass() {
  echo "  pass: $1"
  PASS=$((PASS + 1))
}

SCRATCH_PARENT="${TMPDIR:-/var/tmp}"
TMP=$(mktemp -d "$SCRATCH_PARENT/soleur-bundle-mirror.XXXXXXXX") || { echo "FATAL: mktemp failed" >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT INT TERM HUP
[[ -d "$TMP" ]] || { echo "FATAL: scratch dir missing" >&2; exit 2; }

# Instrument self-test: both verdict helpers must move their own counter, or every later
# line below would be reporting through a helper that never records anything.
_st=$( PASS=0; FAIL=0; pass x >/dev/null; fail y >/dev/null; echo "$PASS$FAIL" )
if [[ "$_st" != "11" ]]; then
  printf 'FATAL: pass()/fail() did not each move their counter (got %s)\n' "$_st" >&2
  exit 1
fi

[[ -f "$WF" ]] || { echo "FATAL: workflow not found at $WF" >&2; exit 2; }
python3 -c 'import yaml' 2>/dev/null || { echo "FATAL: python3 pyyaml unavailable" >&2; exit 2; }

# ---------------------------------------------------------------------------
# Structural leg + body extraction (python, TSV verdicts: OK|BAD <tab> name).
# ---------------------------------------------------------------------------
cat > "$TMP/struct.py" <<'PY'
import re
import sys

import yaml

wf, name, body_out = sys.argv[1:4]
doc = yaml.safe_load(open(wf))
steps = []
job_ifs = []
for jname, job in doc["jobs"].items():
    if "if" in job:
        job_ifs.append(str(job["if"]))
    steps.extend(job.get("steps", []))


def v(ok, n):
    print(("OK" if ok else "BAD") + "\t" + n)


GATE = "steps.docker_build.outcome == 'success'"
hits = [i for i, s in enumerate(steps) if s.get("name") == name]
v(len(hits) == 1, "the mirror step is found exactly once by name (%d steps extracted)" % len(hits))
if len(hits) != 1:
    open(body_out, "w").write("")
    sys.exit(0)
mi = hits[0]
mirror = steps[mi]
v(mirror.get("id") == "zot_mirror", "the mirror step carries id zot_mirror")
mif = mirror.get("if")
v(mif is None or str(mif).strip() == GATE, "the mirror step gate is absent or exactly the docker_build success test")
leaks = [s.get("name", "?") for s in steps if "steps.zot_bridge" in str(s.get("if", ""))]
leaks += ["<job if>" for j in job_ifs if "steps.zot_bridge" in j]
v(not leaks, "no step-level or job-level if: reads steps.zot_bridge (%s)" % ",".join(leaks))
bridges = [s for s in steps if str(s.get("uses", "")).startswith("./.github/actions/cf-tunnel-registry-bridge")]
v(len(bridges) >= 1 and all(b.get("continue-on-error") is True for b in bridges),
  "every bridge-action step is continue-on-error: true (an implicit success() would skip the mirror)")
v(mirror.get("continue-on-error") is True, "the mirror step is continue-on-error: true (GHCR is authoritative)")
v(str((mirror.get("env") or {}).get("BRIDGE_OUTCOME", "")).strip() == "${{ steps.zot_bridge.outcome }}",
  "BRIDGE_OUTCOME is wired from the bridge step outcome, never conclusion")
bi = [i for i, s in enumerate(steps) if s.get("id") == "zot_bridge"]
v(len(bi) == 1 and bi[0] < mi, "the mirror step comes after the bridge step")
body = mirror.get("run", "")
v(len(re.findall(r"^\s*degraded\(\)\s*\{", body, re.M)) == 1, "degraded() is defined exactly once")
open(body_out, "w").write(body)
PY

# ---------------------------------------------------------------------------
# Deterministic stubs. Knobs are env vars; every call is logged to $STUB_LOG, never stdout.
# ---------------------------------------------------------------------------
STUBS="$TMP/bin"
mkdir -p "$STUBS"
cat > "$STUBS/curl" <<'STUB'
#!/usr/bin/env bash
echo "curl $*" >> "$STUB_LOG"
exit "${STUB_CURL_RC:-0}"
STUB
cat > "$STUBS/sha256sum" <<'STUB'
#!/usr/bin/env bash
# Read stdin first: a stub that exits unread lets the upstream echo take SIGPIPE under pipefail.
[ -t 0 ] || cat > /dev/null
echo "sha256sum $*" >> "$STUB_LOG"
exit "${STUB_SHA_RC:-0}"
STUB
cat > "$STUBS/sudo" <<'STUB'
#!/usr/bin/env bash
echo "sudo $*" >> "$STUB_LOG"
exit "${STUB_SUDO_RC:-0}"
STUB
cat > "$STUBS/sleep" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
cat > "$STUBS/crane" <<'STUB'
#!/usr/bin/env bash
echo "crane $*" >> "$STUB_LOG"
if [[ "${1:-}" == "copy" ]]; then
  n=0
  [[ -f "$STUB_COPY_COUNT" ]] && n=$(cat "$STUB_COPY_COUNT")
  n=$((n + 1))
  echo "$n" > "$STUB_COPY_COUNT"
  [[ "$n" -le "${STUB_CRANE_COPY_FAIL_N:-0}" ]] && exit 1
fi
exit 0
STUB
chmod +x "$STUBS"/*

REAL_PATH="$PATH"
EXPECT_SRC="ghcr.io/jikig-ai/soleur-inngest-config:v7"
EXPECT_DST="127.0.0.1:5000/jikig-ai/soleur-inngest-config:v7"

# run_arm <dir> <bridge-outcome|__unset__> [NAME=value knobs...]
# Executes the extracted body exactly as the runner does (bash -eo pipefail), SOURCED so a
# trailing sentinel proves whether degraded() left the shell (exit) or merely the function (return).
run_arm() {
  local d="$1" bridge="$2"
  shift 2
  mkdir -p "$d"
  : > "$d/gho"
  : > "$d/sum"
  : > "$d/log"
  rm -f "$d/copycount"
  local -a benv=()
  if [[ "$bridge" == "__unset__" ]]; then benv=(-u BRIDGE_OUTCOME); else benv=("BRIDGE_OUTCOME=$bridge"); fi
  local rc=0
  (
    env "${benv[@]}" "$@" IMAGE="ghcr.io/jikig-ai/soleur-inngest-config" VERSION="7" DIGEST="sha256:abc123" \
      GITHUB_OUTPUT="$d/gho" GITHUB_STEP_SUMMARY="$d/sum" STUB_LOG="$d/log" STUB_COPY_COUNT="$d/copycount" \
      PATH="$STUBS:$REAL_PATH" \
      bash --noprofile --norc -eo pipefail -c 'source "$1"; echo SENTINEL_REACHED' _ "$BODY_FILE" > "$d/stdout" 2>&1
  ) || rc=$?
  echo "$rc" > "$d/rc"
}

# count <fixed-string> <file> -> occurrences of whole lines equal to the string
count_eq() {
  local n
  n=$(grep -cxF -- "$1" "$2" 2>/dev/null) || true
  echo "${n:-0}"
}
# count_has <fixed-string> <file> -> lines containing the string
count_has() {
  local n
  n=$(grep -cF -- "$1" "$2" 2>/dev/null) || true
  echo "${n:-0}"
}
copies() {
  if [[ -f "$1/copycount" ]]; then cat "$1/copycount"; else echo 0; fi
}

# evaluate <workflow-file> <out-dir> <step-name> -> writes <out-dir>/verdicts (OK|BAD <tab> name)
evaluate() {
  local wf="$1" out="$2" name="$3"
  mkdir -p "$out"
  local vf="$out/verdicts"
  : > "$vf"
  python3 -I "$TMP/struct.py" "$wf" "$name" "$out/body.sh" >> "$vf" 2>"$out/struct.err"
  local chk_rc=$?
  [[ "$chk_rc" -eq 0 ]] || printf 'BAD\tstructural leg crashed (rc=%s)\n' "$chk_rc" >> "$vf"
  if [[ ! -s "$out/body.sh" ]]; then
    printf 'BAD\tno step body extracted, behavioural leg cannot run\n' >> "$vf"
    return 0
  fi
  if ! bash -n "$out/body.sh" 2>/dev/null; then
    printf 'BAD\tthe extracted body is not valid bash\n' >> "$vf"
    return 0
  fi
  local d="$out/arm"
  BODY_FILE="$out/body.sh"
  chk() { if [[ "$1" == "1" ]]; then printf 'OK\t%s\n' "$2" >> "$vf"; else printf 'BAD\t%s\n' "$2" >> "$vf"; fi; }
  # Reads a finished arm and asserts the degrade signal contract for <reason>.
  degraded_ok() { # <dir> <label> <reason> <expected-crane-copies>
    local a="$1" l="$2" r="$3" n="$4" ok=1
    [[ "$(cat "$a/rc")" == "0" ]] || ok=0
    [[ "$(count_eq "mirror_status=degraded" "$a/gho")" == "1" ]] || ok=0
    [[ "$(count_eq "mirror_reason=$r" "$a/gho")" == "1" ]] || ok=0
    [[ "$(count_eq "mirror_status=ok" "$a/gho")" == "0" ]] || ok=0
    [[ "$(count_has "::warning::zot mirror degraded" "$a/stdout")" == "1" ]] || ok=0
    [[ "$(count_has "zot mirror degraded" "$a/sum")" == "1" ]] || ok=0
    [[ "$(count_eq "SENTINEL_REACHED" "$a/stdout")" == "0" ]] || ok=0
    [[ "$(copies "$a")" == "$n" ]] || ok=0
    chk "$ok" "$l: exit 0, one degraded output, reason=$r, one warning, one summary line, $n crane copies, shell left via exit"
  }

  run_arm "$d/ok" success
  local ok=1
  [[ "$(cat "$d/ok/rc")" == "0" ]] || ok=0
  [[ "$(count_eq "mirror_status=ok" "$d/ok/gho")" == "1" ]] || ok=0
  [[ "$(count_has "::warning::" "$d/ok/stdout")" == "0" ]] || ok=0
  [[ "$(copies "$d/ok")" == "1" ]] || ok=0
  [[ "$(count_eq "crane copy $EXPECT_SRC $EXPECT_DST" "$d/ok/log")" == "1" ]] || ok=0
  chk "$ok" "bridge success: mirror_status=ok, no warning, one crane copy of the expected source and destination"

  run_arm "$d/failure" failure
  degraded_ok "$d/failure" "bridge failure" bridge_down 0
  local b
  for b in skipped "" cancelled __unset__; do
    run_arm "$d/b-${b:-empty}" "$b"
    degraded_ok "$d/b-${b:-empty}" "bridge '${b:-empty}'" bridge_down 0
  done

  run_arm "$d/copyfail" success STUB_CRANE_COPY_FAIL_N=99
  degraded_ok "$d/copyfail" "crane copy failing every time" copy 3

  run_arm "$d/copyflaky" success STUB_CRANE_COPY_FAIL_N=2
  ok=1
  [[ "$(cat "$d/copyflaky/rc")" == "0" ]] || ok=0
  [[ "$(count_eq "mirror_status=ok" "$d/copyflaky/gho")" == "1" ]] || ok=0
  [[ "$(count_has "::warning::" "$d/copyflaky/stdout")" == "0" ]] || ok=0
  [[ "$(copies "$d/copyflaky")" == "3" ]] || ok=0
  chk "$ok" "crane copy failing twice then succeeding: mirror_status=ok after 3 attempts, no warning"

  run_arm "$d/shabad" success STUB_SHA_RC=1
  degraded_ok "$d/shabad" "checksum mismatch" crane_install 0
  ok=1
  [[ "$(count_has "sudo " "$d/shabad/log")" == "0" ]] || ok=0
  chk "$ok" "checksum mismatch: nothing is extracted (sudo never invoked)"

  run_arm "$d/curlbad" success STUB_CURL_RC=22
  degraded_ok "$d/curlbad" "crane download failing" crane_install 0

  run_arm "$d/tarbad" success STUB_SUDO_RC=1
  degraded_ok "$d/tarbad" "crane extract failing" crane_install 0
}

# ---------------------------------------------------------------------------
# Mutation helper: apply one named mutation to a copy of the workflow.
# ---------------------------------------------------------------------------
cat > "$TMP/mutate.py" <<'PY'
import re
import sys

name, src, dst = sys.argv[1:4]
s = open(src).read()
MIRROR = "      - name: Mirror bundle GHCR->zot (crane, digest-preserving)\n"
BRIDGE = "      - name: Bridge to zot registry (CF Tunnel)\n"
TEARDOWN = "      - name: Tear down cloudflared registry bridge\n"


def must_sub(pattern, repl, text, flags=re.S):
    out, n = re.subn(pattern, repl, text, count=1, flags=flags)
    if n != 1:
        sys.exit(3)
    return out


if name == "regate-on-bridge":
    s = must_sub(r"(id: zot_mirror\n\s+if: ).*?\n", r"\1steps.zot_bridge.outcome == 'success'\n", s)
elif name == "bridge-loses-continue-on-error":
    s = must_sub(r"(id: zot_bridge\n\s+if: [^\n]*\n)\s+continue-on-error: true\n", r"\1", s)
elif name == "second-gated-step":
    extra = ("      - name: Late mirror note\n        if: steps.zot_bridge.outcome == 'success'\n"
             "        run: echo noted\n\n")
    s = must_sub(re.escape(TEARDOWN), lambda m: extra + TEARDOWN, s)
elif name == "env-uses-conclusion":
    s = must_sub(r"(BRIDGE_OUTCOME: \$\{\{ steps\.zot_bridge\.)outcome", r"\1conclusion", s)
elif name == "delete-bridge-branch":
    s = must_sub(r"\n\s*if \[\[ \"\$\{BRIDGE_OUTCOME:-\}\" != \"success\" \]\]; then\n[^\n]*\n\s*fi\n", "\n", s)
elif name == "degraded-returns":
    s = must_sub(r"(degraded\(\) \{.*?)exit 0", r"\1return 0", s)
elif name == "mirror-before-bridge":
    i_b, i_m, i_t = s.index(BRIDGE), s.index(MIRROR), s.index(TEARDOWN)
    s = s[:i_b] + s[i_m:i_t] + s[i_b:i_m] + s[i_t:]
elif name == "rename-step":
    s = must_sub(re.escape("- name: Mirror bundle GHCR->zot (crane"), "- name: Mirror bundle GHCR to zot (crane", s)
elif name == "drop-copy-route":
    s = must_sub(r"(retry crane copy [^\n]*?) \|\| degraded copy [^\n]*\n", r"\1\n", s)
elif name == "variant-no-if":
    s = must_sub(r"(id: zot_mirror\n)\s+if: [^\n]*\n", r"\1", s)
elif name == "variant-reworded":
    i_m, i_t = s.index(MIRROR), s.index(TEARDOWN)
    seg = re.sub(r"(\n\s+# [^\n]*)", r"\1 (reworded)", s[i_m:i_t])
    seg = must_sub(r"(\n\s+DIGEST: [^\n]*)(\n\s+BRIDGE_OUTCOME: [^\n]*)", r"\2\1", seg)
    s = s[:i_m] + seg + s[i_t:]
else:
    sys.exit(4)
open(dst, "w").write(s)
PY

# ---------------------------------------------------------------------------
# Canonical evaluation
# ---------------------------------------------------------------------------
echo "T1: canonical workflow passes every structural and behavioural check"
evaluate "$WF" "$TMP/canon" "$STEP_NAME"
CANON_RED=0
while IFS=$'\t' read -r verdict label; do
  if [[ "$verdict" == "OK" ]]; then pass "$label"; else fail "$label"; CANON_RED=1; fi
done < "$TMP/canon/verdicts"

# ---------------------------------------------------------------------------
# Mutation battery. Every mutation is asserted to CHANGE the workflow before the evaluator
# runs (a pattern that stopped matching would otherwise become a silent no-op that scores as
# "the guard held"), then the SAME evaluator must report at least one BAD check.
# ---------------------------------------------------------------------------
echo "T2: mutation battery (each mutant must differ from canonical and turn the evaluator RED)"
if [[ "$CANON_RED" -ne 0 ]]; then
  echo "  battery skipped: the canonical workflow is itself RED, so mutant verdicts would be meaningless"
else
  for m in regate-on-bridge bridge-loses-continue-on-error second-gated-step env-uses-conclusion \
    delete-bridge-branch degraded-returns mirror-before-bridge rename-step drop-copy-route; do
    mwf="$TMP/mut-$m.yml"
    mrc=0
    python3 -I "$TMP/mutate.py" "$m" "$WF" "$mwf" 2>/dev/null || mrc=$?
    if [[ "$mrc" -ne 0 ]]; then
      fail "mutation $m did not apply (rc=$mrc): the battery pattern drifted from the workflow"
      continue
    fi
    if cmp -s "$WF" "$mwf"; then
      fail "mutation $m produced a copy identical to canonical"
      continue
    fi
    evaluate "$mwf" "$TMP/mut-$m.out" "$STEP_NAME"
    bad=$(grep -c '^BAD' "$TMP/mut-$m.out/verdicts") || true
    if [[ "${bad:-0}" -gt 0 ]]; then
      pass "mutation $m is caught ($bad failing checks)"
    else
      fail "mutation $m SURVIVED: the evaluator stayed green on a broken workflow"
    fi
  done

  # Harness row: a wrong step name must fail on the empty extraction, never pass with zero arms.
  evaluate "$WF" "$TMP/wrongname.out" "No such step name"
  bad=$(grep -c '^BAD' "$TMP/wrongname.out/verdicts") || true
  if [[ "${bad:-0}" -gt 0 ]]; then
    pass "a wrong extractor step name reds the evaluator instead of passing with zero arms"
  else
    fail "a wrong extractor step name left the evaluator GREEN (the guard dispatches nothing)"
  fi

  # Must-pass non-canonical variants: a guard that rejects everything cannot pass these.
  for m in variant-no-if variant-reworded; do
    mwf="$TMP/mut-$m.yml"
    mrc=0
    python3 -I "$TMP/mutate.py" "$m" "$WF" "$mwf" 2>/dev/null || mrc=$?
    if [[ "$mrc" -ne 0 ]] || cmp -s "$WF" "$mwf"; then
      fail "variant $m did not produce a changed copy (rc=$mrc)"
      continue
    fi
    evaluate "$mwf" "$TMP/mut-$m.out" "$STEP_NAME"
    bad=$(grep -c '^BAD' "$TMP/mut-$m.out/verdicts") || true
    if [[ "${bad:-0}" -eq 0 ]]; then
      pass "non-canonical variant $m still passes (the guard accepts every contract-legal shape)"
    else
      fail "non-canonical variant $m was REJECTED ($bad failing checks)"
    fi
  done
fi

echo "=== Results: $PASS/$((PASS + FAIL)) passed, $FAIL failed ==="
# ANTI-VACUITY FLOOR. Equal to the green-run count: raise it in the same edit that adds a case. It sits
# directly above its `if` so guard-vacuity-floor can slice it.
MIN_ASSERTIONS=33
if (( PASS + FAIL < MIN_ASSERTIONS )); then
  echo "FATAL: only $((PASS + FAIL)) assertions ran (floor $MIN_ASSERTIONS); the suite did not execute what it claims to." >&2
  exit 1
fi
if [[ "$FAIL" -gt 0 ]]; then exit 1; fi
