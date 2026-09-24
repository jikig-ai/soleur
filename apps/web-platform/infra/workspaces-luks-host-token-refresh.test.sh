#!/usr/bin/env bash
#
# Gate for the #8632 boot-token REFRESH path:
#   - apps/web-platform/infra/luks-monitor-token-refresh.sh (runs ON web-1 as root), and
#   - the `refresh-host-token` job in .github/workflows/workspaces-luks-verify.yml that ships it.
#
# What must hold, and why each one matters:
#   (1) The host file keeps every non-token line (the baked SOLEUR_SENTRY_DSN is what lets a Doppler
#       outage still page) and ends with exactly ONE DOPPLER_TOKEN line, mode 600.
#   (2) The token travels on STDIN only. It never appears in ssh argv, stdout, stderr or the logger
#       call that reaches Better Stack.
#   (3) A refresh is only green when `systemctl start luks-monitor.service` exits 0 AND the unit's
#       Result is `success` — i.e. the daily probe demonstrably reads WORKSPACES_LUKS_KEY with the
#       new token. Writing the file is not the proof.
#   (4) The replace code is the SAME code workspaces-cutover.sh used to install the token, so the
#       two writers cannot drift (the rotation runbook on #8632 requires this).
#   (5) The job is dispatch-only and environment-gated, and the daily `verify` job is untouched:
#       no `needs`, no `environment`. A reviewer gate on the verify job would park every 04:41
#       cron run waiting for approval, which is the silence the Sentry Crons monitor pages on.
#
# The workflow half parses the YAML and EXECUTES the extracted `run:` body under GitHub's shell
# (`bash --noprofile --norc -eo pipefail`) against a stub ssh that records argv and stdin.
set -euo pipefail

WF=".github/workflows/workspaces-luks-verify.yml"
HELPER="apps/web-platform/infra/luks-monitor-token-refresh.sh"
CUTOVER="apps/web-platform/infra/workspaces-cutover.sh"
[[ -f "$WF" ]] || { echo "FAIL - $WF not found (run from the repo root)"; exit 1; }

pass=0
fail=0
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

python3 -c 'import yaml' 2>/dev/null || pip3 install --quiet pyyaml

export TMPDIR="${TMPDIR:-/var/tmp}"
SCRATCH="$(mktemp -d -t wl-token-refresh.XXXXXXXX)"
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
mkdir -p "$SCRATCH/bin"

# Synthesized and split across concatenation: a contiguous service-token-shaped literal trips GitHub
# push protection even though it is fake (cq-test-fixtures-synthesized-only).
TOKEN_PREFIX="dp."'st.'
NEW_TOKEN="${TOKEN_PREFIX}prd_workspaces_luks.FIXTURExNEWxTOKENxxxxxxxxxxxxxxxxxxxxxxxx"
OLD_TOKEN="${TOKEN_PREFIX}prd_workspaces_luks.FIXTURExOLDxTOKENxxxxxxxxxxxxxxxxxxxxxxxx"
DSN_LINE="SOLEUR_SENTRY_DSN=https://fixture@o0.ingest.example/1"
EXPECTED_SHA16="$(printf '%s' "$NEW_TOKEN" | sha256sum | cut -c1-16)"

# --- host helper ----------------------------------------------------------------------------------
# systemctl / journalctl / logger are PATH stubs. Each records its argv; systemctl answers by verb so
# a helper that queried the wrong thing (a different unit, a missing `start`) does not read a fixture.
cat > "$SCRATCH/bin/systemctl" <<'EOS'
#!/usr/bin/env bash
printf 'systemctl %s\n' "$*" >> "${STUB_CALLS:?}"
case "$*" in
  "cat luks-monitor.service") exit "${FIXTURE_UNIT_CAT_RC:-0}" ;;
  "start luks-monitor.service") exit "${FIXTURE_START_RC:-0}" ;;
  "show -p Result --value luks-monitor.service") printf '%s\n' "${FIXTURE_RESULT:-success}"; exit 0 ;;
esac
printf 'STUB-MISS systemctl %s\n' "$*" >&2
exit 64
EOS
cat > "$SCRATCH/bin/journalctl" <<'EOS'
#!/usr/bin/env bash
printf 'journalctl %s\n' "$*" >> "${STUB_CALLS:?}"
printf '%s\n' '[luks-monitor] FAIL (doppler_unreachable) fixture'
exit 0
EOS
cat > "$SCRATCH/bin/logger" <<'EOS'
#!/usr/bin/env bash
printf 'logger %s\n' "$*" >> "${STUB_CALLS:?}"
exit 0
EOS
chmod +x "$SCRATCH/bin/systemctl" "$SCRATCH/bin/journalctl" "$SCRATCH/bin/logger"

# run_helper <case> <stdin-token> [envfile-seed|__ABSENT__]; leaves $SCRATCH/<case>.{out,rc,calls,env}
run_helper() {
  local c="$1" tok="$2" seed="${3:-}"
  local envf="$SCRATCH/$c.env" rc=0
  : > "$SCRATCH/$c.calls"
  if [[ "$seed" != "__ABSENT__" ]]; then
    printf '%s' "$seed" > "$envf"
    chmod 644 "$envf"
  fi
  # The helper's target is a literal (it runs as root). Point a scratch COPY at the fixture file, and
  # refuse to run if the rewrite did not land — an unrewritten copy would target the real path.
  sed "s|^ENVF=\"/etc/default/luks-monitor\"\$|ENVF=\"$envf\"|" "$HELPER" > "$SCRATCH/$c.helper.sh"
  if ! grep -qxF "ENVF=\"$envf\"" "$SCRATCH/$c.helper.sh"; then
    printf 'FATAL: the ENVF rewrite did not land in the scratch copy of %s\n' "$HELPER" >&2
    exit 2
  fi
  printf '%s\n' "$tok" | PATH="$SCRATCH/bin:$PATH" STUB_CALLS="$SCRATCH/$c.calls" \
    FIXTURE_START_RC="${START_RC:-0}" FIXTURE_RESULT="${RESULT:-success}" \
    FIXTURE_UNIT_CAT_RC="${CAT_RC:-0}" \
    bash "$SCRATCH/$c.helper.sh" > "$SCRATCH/$c.out" 2>&1 || rc=$?
  printf '%s\n' "$rc" > "$SCRATCH/$c.rc"
}
rc_of() { cat "$SCRATCH/$1.rc"; }
token_lines() { grep -c '^DOPPLER_TOKEN=' "$SCRATCH/$1.env" || true; }
leaks() { # leaks <case> <token> -> count of artifacts carrying the token
  local n=0 f
  for f in "$SCRATCH/$1.out" "$SCRATCH/$1.calls"; do
    [[ -f "$f" ]] && grep -qF -- "$2" "$f" && n=$((n + 1))
  done
  printf '%s\n' "$n"
}

if [[ ! -f "$HELPER" ]]; then
  no "the host helper $HELPER exists"
else
  ok "the host helper $HELPER exists"
  bash -n "$HELPER" && ok "helper passes bash -n" || no "helper passes bash -n"

  # H1 — the positive control.
  run_helper h1 "$NEW_TOKEN" "$(printf '%s\nDOPPLER_TOKEN=%s\n' "$DSN_LINE" "$OLD_TOKEN")"
  [[ "$(rc_of h1)" == 0 ]] && ok "H1 healthy refresh exits 0" || no "H1 healthy refresh exits 0 (rc=$(rc_of h1): $(tail -3 "$SCRATCH/h1.out" | tr '\n' ' '))"
  [[ "$(token_lines h1)" == 1 ]] && ok "H1 exactly one DOPPLER_TOKEN line remains" || no "H1 exactly one DOPPLER_TOKEN line remains (got $(token_lines h1))"
  grep -qxF "DOPPLER_TOKEN=$NEW_TOKEN" "$SCRATCH/h1.env" && ok "H1 the token line carries the NEW token" || no "H1 the token line carries the NEW token"
  grep -qF "$OLD_TOKEN" "$SCRATCH/h1.env" && no "H1 the OLD token is gone from the file" || ok "H1 the OLD token is gone from the file"
  grep -qxF "$DSN_LINE" "$SCRATCH/h1.env" && ok "H1 the baked SOLEUR_SENTRY_DSN line is preserved" || no "H1 the baked SOLEUR_SENTRY_DSN line is preserved"
  [[ "$(stat -c %a "$SCRATCH/h1.env")" == 600 ]] && ok "H1 the file ends mode 600" || no "H1 the file ends mode 600 (got $(stat -c %a "$SCRATCH/h1.env"))"
  grep -qxF "systemctl start luks-monitor.service" "$SCRATCH/h1.calls" && ok "H1 the daily unit is started (the proof, not the write)" || no "H1 the daily unit is started"
  grep -qxF "systemctl show -p Result --value luks-monitor.service" "$SCRATCH/h1.calls" && ok "H1 the unit's Result is read back" || no "H1 the unit's Result is read back"
  grep -qxF "[luks-token-refresh] result=ok token_sha256_16=$EXPECTED_SHA16" "$SCRATCH/h1.out" && ok "H1 prints the ok verdict with the token's sha256 prefix" || no "H1 prints the ok verdict with the token's sha256 prefix"
  grep -qE '^logger .*SOLEUR_LUKS_HOST_TOKEN_REFRESH result=ok' "$SCRATCH/h1.calls" && ok "H1 the outcome reaches journald under the luks-monitor tag" || no "H1 the outcome reaches journald"
  grep -qE '^logger -t luks-monitor ' "$SCRATCH/h1.calls" && ok "H1 logger uses the vector-allowlisted luks-monitor tag" || no "H1 logger uses the luks-monitor tag"
  [[ "$(leaks h1 "$NEW_TOKEN")" == 0 ]] && ok "H1 the token appears in no output and no stub argv" || no "H1 the token leaked into output/argv"
  grep -q 'STUB-MISS' "$SCRATCH/h1.out" && no "H1 no stub was asked a question it does not model" || ok "H1 no stub was asked a question it does not model"

  # H2 — no EnvironmentFile: refuse, and do not create one.
  run_helper h2 "$NEW_TOKEN" "__ABSENT__"
  [[ "$(rc_of h2)" != 0 ]] && ok "H2 absent EnvironmentFile is refused" || no "H2 absent EnvironmentFile is refused"
  grep -q 'result=fail reason=envfile_absent' "$SCRATCH/h2.out" && ok "H2 names envfile_absent" || no "H2 names envfile_absent"
  [[ -e "$SCRATCH/h2.env" ]] && no "H2 no file is created" || ok "H2 no file is created"

  # H3 / H4 — an empty or wrong-shape token never reaches the file.
  seed="$(printf '%s\nDOPPLER_TOKEN=%s\n' "$DSN_LINE" "$OLD_TOKEN")"
  run_helper h3 "" "$seed"
  [[ "$(rc_of h3)" != 0 ]] && ok "H3 empty token is refused" || no "H3 empty token is refused"
  grep -q 'reason=token_empty' "$SCRATCH/h3.out" && ok "H3 names token_empty" || no "H3 names token_empty"
  grep -qxF "DOPPLER_TOKEN=$OLD_TOKEN" "$SCRATCH/h3.env" && ok "H3 the file is untouched" || no "H3 the file is untouched"
  run_helper h4 "dp.pt.personal-token-shape" "$seed"
  [[ "$(rc_of h4)" != 0 ]] && ok "H4 a non-service-token shape is refused" || no "H4 a non-service-token shape is refused"
  grep -q 'reason=token_shape_invalid' "$SCRATCH/h4.out" && ok "H4 names token_shape_invalid" || no "H4 names token_shape_invalid"
  grep -qxF "DOPPLER_TOKEN=$OLD_TOKEN" "$SCRATCH/h4.env" && ok "H4 the file is untouched" || no "H4 the file is untouched"
  run_helper h4b "dp.st.has space" "$seed"
  [[ "$(rc_of h4b)" != 0 ]] && ok "H4b a token with whitespace is refused" || no "H4b a token with whitespace is refused"

  # H5 — the unit fails with the new token: red, with the probe's own FAIL line surfaced.
  START_RC=1 run_helper h5 "$NEW_TOKEN" "$seed"
  [[ "$(rc_of h5)" != 0 ]] && ok "H5 a failing unit start reds the refresh" || no "H5 a failing unit start reds the refresh"
  grep -q 'reason=unit_start_failed' "$SCRATCH/h5.out" && ok "H5 names unit_start_failed" || no "H5 names unit_start_failed"
  grep -qF '[luks-monitor] FAIL (doppler_unreachable)' "$SCRATCH/h5.out" && ok "H5 surfaces the probe's own FAIL line from the journal" || no "H5 surfaces the probe's FAIL line"

  # H6 — start exits 0 but the unit's Result is not success: still red.
  RESULT=exit-code run_helper h6 "$NEW_TOKEN" "$seed"
  [[ "$(rc_of h6)" != 0 ]] && ok "H6 Result!=success reds the refresh even when start exited 0" || no "H6 Result!=success reds the refresh"
  grep -q 'reason=unit_result_not_success' "$SCRATCH/h6.out" && ok "H6 names unit_result_not_success" || no "H6 names unit_result_not_success"

  # H7 — no unit installed: refuse before writing.
  CAT_RC=1 run_helper h7 "$NEW_TOKEN" "$seed"
  [[ "$(rc_of h7)" != 0 ]] && ok "H7 an absent unit is refused" || no "H7 an absent unit is refused"
  grep -q 'reason=unit_absent' "$SCRATCH/h7.out" && ok "H7 names unit_absent" || no "H7 names unit_absent"
  grep -qxF "DOPPLER_TOKEN=$OLD_TOKEN" "$SCRATCH/h7.env" && ok "H7 the file is untouched" || no "H7 the file is untouched"

  # H8 — a file that never had a token line (DSN only) gets exactly one appended.
  run_helper h8 "$NEW_TOKEN" "$(printf '%s\n' "$DSN_LINE")"
  [[ "$(rc_of h8)" == 0 && "$(token_lines h8)" == 1 ]] && ok "H8 a DSN-only file gains exactly one token line" || no "H8 a DSN-only file gains exactly one token line"
fi

# --- (4) the replace code is the cutover's code -----------------------------------------------------
# Anchored on the two statements that do the work, whitespace-normalised. A paraphrase in either file
# (a different umask, a dropped grep -v, a chmod after mv) reds here.
python3 - "$CUTOVER" "$HELPER" > "$SCRATCH/parity.tsv" <<'PY'
import sys, re
def core(path):
    try:
        s = open(path).read()
    except FileNotFoundError:
        return None
    lines = [re.sub(r"\s+", " ", l.strip()) for l in s.splitlines()]
    a = [l for l in lines if l.startswith("( umask 077; { grep -v '^DOPPLER_TOKEN=' \"$ENVF\"")]
    b = [l for l in lines if l.startswith("&& mv \"${ENVF}.tmp\" \"$ENVF\" && chmod 600 \"$ENVF\"")]
    return (a, b)
c, h = core(sys.argv[1]), core(sys.argv[2])
if c is None or h is None:
    print("no\treplace-code parity: a file is missing")
else:
    print(("ok" if len(c[0]) == 1 and len(h[0]) == 1 else "no") + "\teach file carries exactly one replace statement")
    print(("ok" if c[0] == h[0] and c[0] else "no") + "\tthe replace statement is identical in the cutover and the helper")
    print(("ok" if len(c[1]) == 1 and len(h[1]) == 1 else "no") + "\teach file carries exactly one mv+chmod tail")
    print(("ok" if c[1] and h[1] and c[1][0].split(" ||")[0] == h[1][0].split(" ||")[0] else "no") + "\tthe mv+chmod tail is identical in both files")
PY
while IFS=$'\t' read -r v name; do
  [[ -n "${v:-}" ]] || continue
  if [[ "$v" == ok ]]; then ok "$name"; else no "$name"; fi
done < "$SCRATCH/parity.tsv"

# --- (5) the workflow job --------------------------------------------------------------------------
python3 - "$WF" "$SCRATCH" > "$SCRATCH/wf.tsv" <<'PY'
import sys, yaml, re
wf = yaml.safe_load(open(sys.argv[1])); scratch = sys.argv[2]
out = []
def check(name, cond, detail=""):
    out.append(("ok" if cond else "no", name, str(detail)[:200]))
on = wf.get(True) or wf.get("on") or {}
inp = ((on.get("workflow_dispatch") or {}).get("inputs") or {}).get("refresh_host_token") or {}
check("refresh_host_token input exists", bool(inp))
check("refresh_host_token is a boolean", inp.get("type") == "boolean", inp.get("type"))
check("refresh_host_token is NOT required (a schedule supplies no inputs)", inp.get("required") is False, inp.get("required"))
check("refresh_host_token defaults to false", inp.get("default") is False, repr(inp.get("default")))
jobs = wf.get("jobs") or {}
job = jobs.get("refresh-host-token") or {}
check("a refresh-host-token job exists", bool(job), sorted(jobs))
check("the refresh job is gated by the workspaces-luks-cutover environment",
      job.get("environment") == "workspaces-luks-cutover", job.get("environment"))
verify = jobs.get("verify") or {}
check("the daily verify job carries NO environment (a reviewer gate would park every cron run)",
      "environment" not in verify, verify.get("environment"))
check("the daily verify job carries NO needs (the cron path must not wait on the refresh job)",
      "needs" not in verify, verify.get("needs"))
check("the daily verify job carries NO job-level if", "if" not in verify, verify.get("if"))

# Evaluate the job `if:` over the event x input grid instead of grepping it. GitHub hands a
# schedule event no inputs, so the input is null there.
cond = str(job.get("if", ""))
expr = cond.strip()
m = re.fullmatch(r"\$\{\{(.*)\}\}", expr, re.S)
if m: expr = m.group(1)
py = expr.replace("&&", " and ").replace("||", " or ").replace("!=", " __NE__ ").replace("!", " not ").replace(" __NE__ ", " != ")
py = py.replace("github.event_name", "EV").replace("inputs.refresh_host_token", "INP")
def ev(e, i):
    return bool(eval(py, {"__builtins__": {}}, {"EV": e, "INP": i}))
try:
    grid = {(e, i): ev(e, i) for e in ("schedule", "workflow_dispatch", "push")
            for i in (None, False, True, "")}
    want = {k: (k[0] == "workflow_dispatch" and k[1] is True) for k in grid}
    check("the refresh job runs ONLY on a dispatch with refresh_host_token=true (evaluated over the grid)",
          grid == want, sorted(repr(k) for k in grid if grid[k] != want[k]))
except Exception as exc:
    check("the refresh job's if: is evaluable", False, repr(exc))

steps = job.get("steps") or []
names = [str(s.get("name", "")) for s in steps]
bridge = [s for s in steps if str(s.get("uses", "")).endswith("cf-tunnel-ssh-bridge")]
check("the refresh job opens the CF Tunnel SSH bridge", len(bridge) == 1, names)
if bridge:
    check("the bridge targets web-1's private address (single-sourced env)",
          str((bridge[0].get("with") or {}).get("server-ip")) == "${{ env.WEB_HOST_PRIVATE_IP }}",
          (bridge[0].get("with") or {}).get("server-ip"))
doppler_i = [i for i, s in enumerate(steps) if "DopplerHQ/cli-action" in str(s.get("uses", ""))]
bridge_i = [i for i, s in enumerate(steps) if str(s.get("uses", "")).endswith("cf-tunnel-ssh-bridge")]
check("the Doppler CLI is installed before the bridge (the bridge reads its key through it)",
      bool(doppler_i and bridge_i and doppler_i[0] < bridge_i[0]), (doppler_i, bridge_i))
refresh = [s for s in steps if s.get("id") == "refresh"]
check("exactly one step carries id: refresh", len(refresh) == 1, names)
if refresh:
    env = refresh[0].get("env") or {}
    check("the refresh step reads the boot token from the repo secret",
          env.get("WORKSPACES_LUKS_BOOT_TOKEN") == "${{ secrets.WORKSPACES_LUKS_BOOT_TOKEN }}",
          env.get("WORKSPACES_LUKS_BOOT_TOKEN"))
    body = str(refresh[0].get("run", ""))
    check("the token is never interpolated into the run: body", "secrets." not in body)
    open(f"{scratch}/refresh.sh", "w").write(body)
teardown = [s for s in steps if "tear down" in str(s.get("name", "")).lower()]
check("a bridge teardown step exists", len(teardown) == 1, names)
if teardown:
    check("the teardown runs always()", str(teardown[0].get("if", "")).strip() == "always()", teardown[0].get("if"))
    open(f"{scratch}/teardown.sh", "w").write(str(teardown[0].get("run", "")))
for v in out:
    print("\t".join(v))
PY
while IFS=$'\t' read -r v name detail; do
  [[ -n "${v:-}" ]] || continue
  if [[ "$v" == ok ]]; then ok "$name"; else no "$name${detail:+ ($detail)}"; fi
done < "$SCRATCH/wf.tsv"

# --- behavioural: the extracted refresh body against a stub ssh -------------------------------------
if [[ ! -f "$SCRATCH/refresh.sh" ]]; then
  no "could not extract the refresh body — its behaviour is unverified"
else
  bash -n "$SCRATCH/refresh.sh" && ok "the refresh body passes bash -n" || no "the refresh body passes bash -n"
  [[ -f "$SCRATCH/teardown.sh" ]] && { bash -n "$SCRATCH/teardown.sh" && ok "the teardown body passes bash -n" || no "the teardown body passes bash -n"; }
  mkdir -p "$SCRATCH/infra"
  cp "$HELPER" "$SCRATCH/infra/" 2>/dev/null || true
  cat > "$SCRATCH/bin/sshstub" <<'EOS'
#!/usr/bin/env bash
# Records argv AND stdin separately, so the test can prove the token rode stdin and never argv.
printf '%s\n' "$*" >> "${SSH_CALLS:?}"
case "$*" in
  *mktemp*) printf '%s\n' "/var/lib/workspaces-luks/wl-token.XXXX"; exit 0 ;;
  *"tar xzf"*) cat > /dev/null; exit 0 ;;
  *luks-monitor-token-refresh.sh*)
    cat >> "${SSH_STDIN:?}"
    [[ -n "${FIXTURE_HOST_OUT:-}" ]] && printf '%s\n' "$FIXTURE_HOST_OUT"
    exit "${FIXTURE_HOST_RC:-0}" ;;
esac
printf 'STUB-MISS ssh %s\n' "$*" >&2
exit 64
EOS
  cat > "$SCRATCH/bin/tar" <<'EOS'
#!/usr/bin/env bash
printf 'tar %s\n' "$*" >> "${SSH_CALLS:?}"
exit 0
EOS
  chmod +x "$SCRATCH/bin/sshstub" "$SCRATCH/bin/tar"

  drive_refresh() { # drive_refresh <case>; env FIXTURE_HOST_OUT / FIXTURE_HOST_RC / TOKEN_IN
    local c="$1" rc=0
    : > "$SCRATCH/$c.argv"; : > "$SCRATCH/$c.stdin"
    PATH="$SCRATCH/bin:$PATH" SSH_CALLS="$SCRATCH/$c.argv" SSH_STDIN="$SCRATCH/$c.stdin" \
      WEB_HOST_SSH="$SCRATCH/bin/sshstub" WEB_HOST="10.0.1.10" INFRA_DIR="$SCRATCH/infra" \
      WORKSPACES_LUKS_BOOT_TOKEN="${TOKEN_IN-$NEW_TOKEN}" \
      FIXTURE_HOST_OUT="${FIXTURE_HOST_OUT:-}" FIXTURE_HOST_RC="${FIXTURE_HOST_RC:-0}" \
      bash --noprofile --norc -eo pipefail "$SCRATCH/refresh.sh" > "$SCRATCH/$c.wout" 2>&1 || rc=$?
    printf '%s\n' "$rc" > "$SCRATCH/$c.wrc"
  }
  OK_LINE="[luks-token-refresh] result=ok token_sha256_16=$EXPECTED_SHA16"

  FIXTURE_HOST_OUT="$OK_LINE" drive_refresh w1
  [[ "$(cat "$SCRATCH/w1.wrc")" == 0 ]] && ok "W1 POSITIVE CONTROL: a host ok verdict with the matching hash is green" || no "W1 positive control is green (rc=$(cat "$SCRATCH/w1.wrc"): $(tail -3 "$SCRATCH/w1.wout" | tr '\n' ' '))"
  grep -qxF "$NEW_TOKEN" "$SCRATCH/w1.stdin" && ok "W1 the token reached the host on STDIN" || no "W1 the token reached the host on STDIN"
  grep -qF "$NEW_TOKEN" "$SCRATCH/w1.argv" && no "W1 the token never appears in ssh argv" || ok "W1 the token never appears in ssh argv"
  grep -qF "$NEW_TOKEN" "$SCRATCH/w1.wout" && no "W1 the token never appears in the job log" || ok "W1 the token never appears in the job log"
  grep -qE '^tar .*luks-monitor-token-refresh\.sh' "$SCRATCH/w1.argv" && ok "W1 ships the helper from the repo (no inline reimplementation)" || no "W1 ships the helper from the repo"
  grep -qE 'ConnectTimeout=15' "$SCRATCH/w1.argv" && ok "W1 every ssh is bounded (ConnectTimeout)" || no "W1 every ssh is bounded"
  grep -q 'STUB-MISS' "$SCRATCH/w1.wout" && no "W1 no ssh call fell outside the modelled set" || ok "W1 no ssh call fell outside the modelled set"

  FIXTURE_HOST_OUT="[luks-token-refresh] result=ok token_sha256_16=0000000000000000" drive_refresh w2
  [[ "$(cat "$SCRATCH/w2.wrc")" != 0 ]] && ok "W2 an ok verdict for a DIFFERENT token is red (the host holds the wrong value)" || no "W2 a hash mismatch is red"

  FIXTURE_HOST_OUT="[luks-token-refresh] result=fail reason=unit_start_failed" FIXTURE_HOST_RC=1 drive_refresh w3
  [[ "$(cat "$SCRATCH/w3.wrc")" != 0 ]] && ok "W3 a host failure is red" || no "W3 a host failure is red"
  grep -q 'unit_start_failed' "$SCRATCH/w3.wout" && ok "W3 the host's reason reaches the job log" || no "W3 the host's reason reaches the job log"

  FIXTURE_HOST_OUT="" FIXTURE_HOST_RC=0 drive_refresh w4
  [[ "$(cat "$SCRATCH/w4.wrc")" != 0 ]] && ok "W4 rc 0 with NO verdict line is red (never read silence as success)" || no "W4 a silent rc 0 is red"

  # W6 — a matching ok line but a non-zero exit (e.g. the transport dropped after the helper printed).
  # Unconfirmed is red; a re-dispatch is idempotent, a false green is not recoverable by anyone.
  FIXTURE_HOST_OUT="$OK_LINE" FIXTURE_HOST_RC=255 drive_refresh w6
  [[ "$(cat "$SCRATCH/w6.wrc")" != 0 ]] && ok "W6 an ok line under a non-zero exit is red (unconfirmed, re-dispatch)" || no "W6 an ok line under a non-zero exit is red"

  TOKEN_IN="" FIXTURE_HOST_OUT="$OK_LINE" drive_refresh w5
  [[ "$(cat "$SCRATCH/w5.wrc")" != 0 ]] && ok "W5 an unpublished boot-token secret is refused before any ssh" || no "W5 an empty secret is refused"
  [[ ! -s "$SCRATCH/w5.argv" ]] && ok "W5 no ssh was attempted without a token" || no "W5 no ssh was attempted without a token"
fi

printf '\n%s passed, %s failed\n' "$pass" "$fail"

# Anti-vacuity floor. Green is 72 assertions; the threshold sits on the line above its `if`.
MIN_ASSERTIONS=72
if [[ "$pass" -lt "$MIN_ASSERTIONS" ]]; then
  printf 'FAIL - only %s assertions passed (floor %s) — a block stopped running\n' "$pass" "$MIN_ASSERTIONS"
  exit 1
fi
[[ "$fail" -eq 0 ]] || exit 1
