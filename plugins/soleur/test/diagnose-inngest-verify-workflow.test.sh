#!/usr/bin/env bash
# diagnose-inngest-verify-workflow.test.sh -- shape gate for
# .github/workflows/diagnose-inngest-verify.yml, the dispatch-only, read-only diagnostic that
# reproduces the inngest host's cosign verify-blob invocation against the promoted config bundle
# in CI, with stderr visible (#10390 defect 3 — the host emits SOLEUR_INFRA_PULL_VERIFY_FAIL
# reason=signature with stderr swallowed, so the reject is honest but undebuggable).
#
# THE PROPERTIES UNDER TEST:
#   D1. The workflow is dispatch-only with exactly one input (`digest`, 64-hex default), carries
#       permissions {contents: read, packages: read} exactly, runs one job, no environment gate,
#       and owns its own concurrency group (never shares scheduled-vinngest-digest-freshness).
#       Asserted by PARSING the YAML — a grep would match the header prose.
#   D2. The run body reproduces the host invocation VERBATIM in shape: pinned cosign digest
#       57c0e93a… (v3.1.1), verify-blob, --network none, --trusted-root, --bundle, the pinned
#       identity regexp naming build-inngest-config-bundle.yml, and the actions OIDC issuer —
#       plus the A/B discriminators (0700 stage-dir arm, --network host arm).
#   D3. The step NEVER carries a verification-weakening flag — the AC10 ban
#       (--insecure-ignore-tlog / --insecure-ignore-sct / --key / --new-bundle-format) applies to
#       this file too, so the guard greps the whole workflow, comments included.
#   D4. Real stderr reaches $GITHUB_STEP_SUMMARY (bounded) — the point of the probe.
#
# Representative structural rows are re-run against MUTATED copies to show the analyzer goes red
# for the
# right reason (the escrow-workflow suite's convention).
#
# Every token here is synthetic (cq-test-fixtures-synthesized-only). The workflow is NEVER
# dispatched by this suite.
#
# Run: bash plugins/soleur/test/diagnose-inngest-verify-workflow.test.sh
# Registered by the plugins/soleur/test/*.test.sh glob in scripts/test-all.sh.
export TMPDIR="${TMPDIR:-/var/tmp}"
set -uo pipefail

SELF="${BASH_SOURCE[0]}"
SCRIPT_DIR="$(cd "$(dirname "$SELF")" && pwd)"
REPO="${DIAG_REPO_ROOT:-$(cd "$SCRIPT_DIR/../../.." && pwd)}"
WF="${DIAG_WF:-$REPO/.github/workflows/diagnose-inngest-verify.yml}"

passes=0
fails=0
ok() { passes=$((passes + 1)); echo "[ok] $1"; }
no() { fails=$((fails + 1)); echo "[FAIL] $1" >&2; }

assert_fixture_dir() {
  case "${1-}" in
    "") printf 'FATAL: fixture dir is EMPTY\n' >&2; exit 2 ;;
    */../*|*/..) printf 'FATAL: fixture dir %s contains ..; refusing\n' "$1" >&2; exit 2 ;;
    /proc/*|/sys/*|/dev/*) printf 'FATAL: fixture dir %s is a synthetic-fs path; refusing\n' "$1" >&2; exit 2 ;;
    /|//|/.) printf 'FATAL: fixture dir resolves to the filesystem root; refusing\n' >&2; exit 2 ;;
    /*) : ;;
    *)  printf 'FATAL: fixture dir %s is RELATIVE; refusing\n' "$1" >&2; exit 2 ;;
  esac
}

# --- INSTRUMENT SELF-TEST (ok/no own every verdict; drive both and require both counters to move)
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

# --- H3: the workflow must EXIST. A suite that finds nothing to check is RED, never "0 checked, pass"
if [[ ! -f "$WF" ]]; then
  printf '[FAIL] workflow-missing: %s does not exist (RED until the diagnostic workflow is added)\n' "$WF" >&2
  exit 1
fi

python3 -c 'import yaml' 2>/dev/null || { printf '[FATAL] INSTRUMENT: PyYAML is required\n' >&2; exit 2; }

SCR="$(mktemp -d "$TMPDIR/diag-verify.XXXXXXXX")" || { echo "mktemp failed" >&2; exit 2; }
assert_fixture_dir "$SCR"
trap 'rm -rf "${SCR:?}"' EXIT INT TERM HUP
mkdir -p "$SCR/mut"

# D1 — parsed-YAML structural rows. argv[2] is the mutation arm: "strip-environment" etc. The
# analyzer prints one TSV row per check; the driver turns any FAIL into a `no`.
cat > "$SCR/analyze.py" <<'PY'
import re, sys, yaml

path = sys.argv[1]
text = open(path).read()
try:
    wf = yaml.load(text, Loader=yaml.SafeLoader)
except Exception as e:
    print("D1-parse\tFAIL\tworkflow does not parse as YAML\t%s" % str(e)[:120].replace("\t", " ").replace("\n", " "))
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
chk("D1a", "triggers are exactly workflow_dispatch", set(on) == {"workflow_dispatch"}, sorted(on))
inputs = (wd or {}).get("inputs") or {}
digest = inputs.get("digest") or {}
chk("D1b", "one input `digest`, required, 64-hex default",
    set(inputs) == {"digest"} and digest.get("required") is True
    and isinstance(digest.get("default"), str) and re.fullmatch(r"[0-9a-f]{64}", digest["default"]) is not None,
    {k: inputs.get(k) for k in inputs})
RO = {"contents": "read", "packages": "read"}
jobs = wf.get("jobs") or {}
chk("D1c", "permissions are exactly {contents: read, packages: read} at workflow level, no job override",
    wf.get("permissions") == RO and all("permissions" not in j for j in jobs.values()),
    [wf.get("permissions")] + [j.get("permissions") for j in jobs.values()])
chk("D1d", "exactly one job", len(jobs) == 1, list(jobs))
job = next(iter(jobs.values())) if jobs else {}
chk("D1e", "the job carries no environment: gate (it mutates nothing)", "environment" not in job, job.get("environment"))
conc = wf.get("concurrency") or {}
grp = str(conc.get("group", ""))
chk("D1f", "its own concurrency group (not shared with the digest-freshness comparator)",
    grp != "" and grp != "scheduled-vinngest-digest-freshness" and "diagnose-inngest-verify" in grp, grp)

steps = job.get("steps") or []
co = [s for s in steps if str(s.get("uses", "")).startswith("actions/checkout@")]
chk("D1g", "one SHA-pinned checkout with persist-credentials: false",
    len(co) == 1 and re.fullmatch(r"actions/checkout@[0-9a-f]{40}", str(co[0]["uses"])) is not None
    and co[0].get("with") == {"persist-credentials": False},
    [s.get("uses") for s in steps if "uses" in s])
login = [s for s in steps if str(s.get("uses", "")).startswith("docker/login-action@")]
chk("D1h", "GHCR login via SHA-pinned docker/login-action using GITHUB_TOKEN",
    len(login) == 1 and re.fullmatch(r"docker/login-action@[0-9a-f]{40}", str(login[0]["uses"])) is not None
    and (login[0].get("with") or {}).get("registry") == "ghcr.io"
    and (login[0].get("with") or {}).get("password") == "${{ secrets.GITHUB_TOKEN }}",
    [s.get("uses") for s in steps])

def strip_comments(body):
    return "\n".join(l for l in str(body).splitlines() if not l.lstrip().startswith("#"))

code = "\n".join(strip_comments(s.get("run", "")) for s in steps if "run" in s)
chk("D2a", "run body carries the pinned cosign v3.1.1 digest",
    "57c0e93a829ae213ab4273b5bd31bc24812043183040882d7cc215a12b5a6870" in code)
for pin in ("verify-blob", "--network none", "--trusted-root", "--bundle",
            "--certificate-identity-regexp", "--certificate-oidc-issuer",
            "token.actions.githubusercontent.com", "build-inngest-config-bundle"):
    chk("D2b", "run body pins `%s`" % pin, pin in code)
chk("D2c", "the pulled bundle ref is digest-parameterized via the workflow input",
    "soleur-inngest-config@sha256:" in code and "inputs.digest" in text)
chk("D2e", "the digest input reaches the run body through env:, never a ${{ }} interpolation inside run:",
    "inputs.digest" not in code)
chk("D2d", "A/B discriminators present: a 0700 stage-dir arm and a --network host arm",
    "0700" in code and "--network host" in code)
chk("D4a", "stderr reaches the step summary (bounded)", "GITHUB_STEP_SUMMARY" in code)
chk("D4b", "the sigstore bundle inside the tarball is jq-inspected",
    re.search(r"(?<![A-Za-z0-9_.-])jq(?![A-Za-z0-9_-])", code) is not None
    and ".sigstore.json" in code)

for r in rows:
    print("%s\t%s\t%s\t%s" % r)
PY

# D3 — whole-file weakening-flag ban (comments included; the ban is on the bytes).
WEAK='--insecure-ignore-tlog|--insecure-ignore-sct|--key|--new-bundle-format'
if grep -nE -e "$WEAK" "$WF" >/dev/null 2>&1; then
  no "D3: workflow carries a verification-weakening flag spelling"
else
  ok "D3: no verification-weakening flag spelling anywhere in the file"
fi
# Negative control: the ban pattern must actually match a hostile line (matcher liveness).
printf 'cosign verify-blob --insecure-ignore-tlog x\n' > "$SCR/mut/hostile.txt"
assert_fixture_dir "$SCR/mut/hostile.txt"
grep -qE -e "$WEAK" "$SCR/mut/hostile.txt" \
  && ok "D3: ban pattern matches a hostile line" \
  || no "D3: ban pattern does not match --insecure-ignore-tlog (matcher dead)"

# Drive the analyzer over the real workflow.
python3 "$SCR/analyze.py" "$WF" > "$SCR/rows.tsv" 2>"$SCR/analyze.err" || {
  cat "$SCR/analyze.err" >&2
  no "analyzer crashed"
}
if [[ -f "$SCR/rows.tsv" ]]; then
  while IFS=$'\t' read -r id verdict name detail; do
    [[ -n "$id" ]] || continue
    if [[ "$verdict" == "ok" ]]; then ok "$id $name"; else no "$id $name ($detail)"; fi
  done < "$SCR/rows.tsv"
fi

# Mutation arm: a workflow that shares the comparator's concurrency group must go red on D1f.
sed 's/^  group: .*/  group: scheduled-vinngest-digest-freshness/' "$WF" > "$SCR/mut/shared-conc.yml" \
  && assert_fixture_dir "$SCR/mut/shared-conc.yml"
if grep -q 'group: scheduled-vinngest-digest-freshness' "$SCR/mut/shared-conc.yml"; then
  python3 "$SCR/analyze.py" "$SCR/mut/shared-conc.yml" > "$SCR/mut/rows.tsv" 2>/dev/null || true
  awk -F'\t' '$1=="D1f" && $2=="FAIL" {found=1} END{exit found?0:1}' "$SCR/mut/rows.tsv" \
    && ok "D1f mutation: shared concurrency group goes red" \
    || no "D1f mutation: shared concurrency group stayed green (row is vacuous)"
else
  no "D1f mutation arm could not build the mutated copy (sed found no group line)"
fi

# Mutation arm: a workflow that drops `packages: read` must go red on D1c.
sed '/^  packages: read$/d' "$WF" > "$SCR/mut/no-packages.yml" \
  && assert_fixture_dir "$SCR/mut/no-packages.yml"
python3 "$SCR/analyze.py" "$SCR/mut/no-packages.yml" > "$SCR/mut/rows2.tsv" 2>/dev/null || true
awk -F'\t' '$1=="D1c" && $2=="FAIL" {found=1} END{exit found?0:1}' "$SCR/mut/rows2.tsv" \
  && ok "D1c mutation: dropping packages:read goes red" \
  || no "D1c mutation: workflow without packages:read stayed green (row is vacuous)"

# D5 — the fix-round guard lines this suite's whole file exists to pin:
# errexit-guard on the verify arms (a bare docker run aborts the step on the
# failure the probe exists to capture), digest-shape validation, and the
# nonregular-member tar gate.
for pin in '|| rc=$?' 'BUNDLE_DIGEST" =~ ^(sha256:)?' 'tar -tzvf' 'END{exit found?0:1}'; do
  grep -qF "$pin" "$WF" && ok "D5: $pin" || no "D5: missing guard line: $pin"
done

MIN_ASSERTIONS=30
[ "$passes" -ge "$MIN_ASSERTIONS" ] \
  || { echo "FLOOR: ${passes} assertions < floor $MIN_ASSERTIONS — a block stopped running"; fails=$((fails+1)); }

echo "diagnose-inngest-verify-workflow.test.sh: ${passes} passed, ${fails} failed"
[ "$fails" -eq 0 ] || exit 1
