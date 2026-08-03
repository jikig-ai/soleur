#!/usr/bin/env bash
#
# Structural + behavioral gate for .github/workflows/workspaces-luks-verify.yml (#6808).
#
# WHY A DEDICATED SUITE. Adding a `schedule:` trigger to this workflow removes the human who was
# implicitly watching every previous run — every run in its history was a manual dispatch. While
# #6808 keeps WORKSPACES_LUKS_HEARTBEAT_URL unwired, this workflow is the ONLY automatic
# verification that web-1's /mnt/data is still on the LUKS mapper, and the published privacy,
# GDPR and data-protection documents assert that verification in the PRESENT TENSE. So the
# properties that matter are not "does the probe work" (the sibling suites cover that) but:
#
#   (1) Can the alarm actually FIRE? GitHub ANDs an implicit `success()` into any step `if:` that
#       contains no status function, so an alarm gated on a failing producer is unreachable on
#       exactly the runs it exists for. That defect is invisible to every green run.
#   (2) Is every exit site classified? An exit that emits no class is an outcome the alarm cannot
#       see — a silent failure wearing a green tab.
#   (3) Does the scheduled path stay read-only? A `schedule:` event supplies no inputs; the seed
#       branch must not be enterable, and a seeded scheduled run must be refused outright.
#
# EVERY structural assertion parses the file as YAML. A grep would pass VACUOUSLY here: this
# workflow's header comments discuss the schedule, the classes and the `always()` rationale at
# length, so a bare grep for any of them matches the prose describing it
# (cq-assert-anchor-not-bare-token).
#
# `bash -n` is run only on EXTRACTED `run:` bodies — `bash -n` on the .yml itself parses YAML as
# bash and proves nothing.
#
# The behavioral leg EXECUTES the extracted `run:` bodies under `bash -e` (what GitHub actually
# uses) against stubbed ssh/curl/tar on PATH. A stub that ignores argv would put the fixture seam
# above the code under test, so the ssh stub records its argv and the seed assertions read it.
set -euo pipefail

WF=".github/workflows/workspaces-luks-verify.yml"
[[ -f "$WF" ]] || { echo "FAIL - $WF not found (run from the repo root)"; exit 1; }

pass=0
fail=0
ok() { pass=$((pass + 1)); printf 'ok   - %s\n' "$1"; }
no() { fail=$((fail + 1)); printf 'FAIL - %s\n' "$1"; }

python3 -c 'import yaml' 2>/dev/null || pip3 install --quiet pyyaml

# TMPDIR default: a direct invocation of this suite (the inner loop while editing the workflow)
# inherits the bare machine-global /tmp tmpfs, where a sibling worktree's run can starve the
# sandbox and turn setup failures into confident wrong verdicts. test-all.sh and
# run-registered-suites.sh already default this; a direct run does not.
export TMPDIR="${TMPDIR:-/var/tmp}"
SCRATCH="$(mktemp -d -t wlv-wf.XXXXXXXX)"
trap 'rm -rf "$SCRATCH"' EXIT INT TERM HUP

# --- structural assertions, parsed as YAML -----------------------------------------------------
python3 - "$WF" "$SCRATCH" > "$SCRATCH/verdicts.tsv" <<'PY'
import sys, yaml, json, re

wf = yaml.safe_load(open(sys.argv[1]))
scratch = sys.argv[2]
verdicts = []

def check(name, cond, detail=""):
    # Strip tab/newline: the bash reader splits on tabs, so an embedded one would desync the loop
    # and manufacture a phantom verdict.
    d = str(detail)[:200].replace("\t", " ").replace("\n", " ").replace("\r", " ")
    verdicts.append(("ok" if cond else "FAIL", name.replace("\t", " "), d))

# --- a GitHub-expression evaluator for the subset these two conditions use ---------------------
# A SUBSTRING GREP IS NOT ENOUGH, and this is the whole reason the file exists. "always() is in the
# string" passes just as happily for an INVERTED class clause, for `||` where `&&` was meant, and
# for a condition that fires on every run including the green ones. Only evaluating the expression
# over the outcome x class grid can tell those apart from the correct one.
#
# Python's `and`/`or` short-circuit with the same value semantics GitHub uses for the
# `cond && 'a' || 'b'` ternary (both yield the last evaluated operand), so ONE evaluator covers the
# alarm's boolean `if:` and the heartbeat's string-valued `status:`.
#
# It fails CLOSED: any token it was not taught (a status function like failure(), a context path
# nobody translated) raises, and the caller turns that into a FAIL rather than a quiet pass.
_GHA_SUBS = [
    ("steps.reassert.outputs.outcome_class", "OUTCLASS"),
    ("steps.reassert.outcome", "OUTCOME"),
    ("github.event_name", "EVENT"),
    ("inputs.alarm_selftest", "SELFTEST"),
    ("always()", "True"),
    ("&&", " and "),
    ("||", " or "),
]

def gha_translate(expr):
    e = str(expr).strip()
    if e.startswith("${{"):
        e = e[3:]
    if e.endswith("}}"):
        e = e[:-2]
    # A YAML folded scalar (`if: >-`) KEEPS the newline before any more-indented continuation line,
    # so the raw string arrives multi-line and Python would reject the leading spaces as an indent.
    # GitHub does not care; collapse to one line before translating.
    e = " ".join(e.split())
    for a, b in _GHA_SUBS:
        e = e.replace(a, b)
    # Any surviving dotted identifier is a context reference this evaluator never learned, so every
    # verdict below would be about an expression we do not actually understand.
    leftover = re.search(r"[A-Za-z_][A-Za-z_0-9]*\.[A-Za-z_]", e)
    if leftover:
        raise ValueError("untranslated context reference: " + leftover.group(0))
    return e

def gha_eval(expr, **ctx):
    return eval(gha_translate(expr), {"__builtins__": {}}, ctx)  # noqa: S307 - fixed grammar, no external input

# The closed grid every assertion below quantifies over. 'skipped' is the one that matters most:
# it is what a Re-assert step that NEVER RAN looks like, and it leaves outcome_class empty.
OUTCOMES = ["success", "failure", "skipped", "cancelled"]
CLASSES = ["pass", "drift", "readiness", "unavailable", ""]

# `on` parses to the boolean True under YAML 1.1, hence the two-key lookup.
on = wf.get(True) or wf.get("on") or {}

# --- (A) the trigger pair ---------------------------------------------------------------------
check("workflow_dispatch is still present (the operator path must not be removed)",
      "workflow_dispatch" in on, sorted(on))
check("schedule: trigger exists", "schedule" in on, sorted(on))

crons = [c.get("cron") for c in (on.get("schedule") or [])]
check("exactly one cron entry", len(crons) == 1, crons)
cron = crons[0] if crons else ""
check("cron is a 5-field crontab expression", bool(re.fullmatch(r"\S+ \S+ \S+ \S+ \S+", str(cron))), cron)
# A daily-or-tighter cadence is what keeps the counsel attestation's 30-day claim_decay_trigger
# satisfied with margin. A month-field or day-of-month restriction would silently widen the gap.
if cron:
    f = str(cron).split()
    check("cron runs at least daily (day-of-month and month are unrestricted)",
          f[2] == "*" and f[3] == "*", cron)

# The dispatch input must be byte-identical in CONTRACT: still optional, still defaulting empty.
# A `required: true` here would break the scheduled path outright (schedule supplies no inputs).
seed = ((on.get("workflow_dispatch") or {}).get("inputs") or {}).get("seed_workspace_count") or {}
check("seed_workspace_count input still exists", bool(seed))
check("seed_workspace_count is NOT required (a schedule event supplies no inputs)",
      seed.get("required") is False, repr(seed.get("required")))
check("seed_workspace_count still defaults to empty (the read-only path)",
      seed.get("default") == "", repr(seed.get("default")))

# --- (B) permissions --------------------------------------------------------------------------
perms = wf.get("permissions") or {}
check("permissions.contents is read", perms.get("contents") == "read", repr(perms.get("contents")))
check("permissions.issues is write (contents:read alone cannot file an alarm)",
      perms.get("issues") == "write", repr(perms.get("issues")))

# --- (C) concurrency ---------------------------------------------------------------------------
conc = wf.get("concurrency") or {}
check("concurrency group is still the serializing one", conc.get("group") == "workspaces-luks-verify",
      repr(conc.get("group")))
check("cancel-in-progress stays false (a scheduled run must not cancel an operator dispatch)",
      conc.get("cancel-in-progress") is False, repr(conc.get("cancel-in-progress")))

jobs = wf.get("jobs") or {}
steps = (jobs.get("verify") or {}).get("steps") or []
check("the verify job has steps", len(steps) > 0, len(steps))

def by_name(frag):
    return [s for s in steps if frag.lower() in str(s.get("name", "")).lower()]

# --- (D) the producer step ---------------------------------------------------------------------
reassert = [s for s in steps if s.get("id") == "reassert"]
check("the Re-assert step carries id: reassert (the alarm gates on its outputs)", len(reassert) == 1,
      [s.get("name") for s in by_name("re-assert")])

# --- (E) the alarm step: the reachability contract ---------------------------------------------
alarm = by_name("alarm")
check("an alarm step exists", len(alarm) == 1, [s.get("name") for s in steps])
if alarm:
    cond = str(alarm[0].get("if", ""))
    # THE defect this suite exists to catch. GitHub ANDs an implicit success() into any `if:` with
    # no status function, so an alarm on a failing producer is unreachable without always().
    check("alarm if: contains always() (without it GitHub ANDs an implicit success())",
          "always()" in cond, cond)
    check("alarm if: does not rely on a bare failure() (the producer succeeds by design; it emits a class)",
          "failure()" not in cond, cond)
    check("alarm if: is scoped to scheduled runs", "github.event_name == 'schedule'" in cond, cond)
    check("alarm if: names the outcome_class output", "outcome_class" in cond, cond)
    check("alarm if: names steps.reassert (producer-status-first)", "steps.reassert" in cond, cond)
    check("alarm step is NOT continue-on-error (that would make every alarm advisory)",
          not alarm[0].get("continue-on-error"), alarm[0].get("continue-on-error"))

# --- (F) no green-close step (Decision 2) -------------------------------------------------------
# A close step would need its own anti-spam machinery and was cut on the simplicity panel. Assert
# its ABSENCE so a later reader does not re-add one without re-reading that decision.
close = [s for s in steps if "close" in str(s.get("name", "")).lower()]
check("no green-close step exists (Decision 2 — a green run files nothing and closes nothing)",
      len(close) == 0, [s.get("name") for s in close])

# --- (G) the Sentry check-in --------------------------------------------------------------------
hb = by_name("sentry")
check("a Sentry check-in step exists", len(hb) == 1, [s.get("name") for s in steps])
if hb:
    hcond = str(hb[0].get("if", ""))
    check("heartbeat is always()", "always()" in hcond, hcond)
    check("heartbeat is continue-on-error (a monitor outage must not red the verify)",
          bool(hb[0].get("continue-on-error")), hb[0].get("continue-on-error"))
    check("heartbeat is scoped to scheduled runs", "github.event_name == 'schedule'" in hcond, hcond)
    blob = json.dumps(hb[0])
    check("heartbeat status gates POSITIVELY on 'pass' (a negative gate inverts silently)",
          "'pass'" in blob or '"pass"' in blob, blob[:200])

# --- (G2) THE EVALUATED TRUTH TABLES ------------------------------------------------------------
# Everything above about these two expressions was a substring test. These are the assertions that
# can tell a correct condition from an inverted one. The eval is over a fixed, repo-controlled
# grammar with builtins stripped and an untranslated-token guard, so it executes no external input.
if alarm:
    cond = str(alarm[0].get("if", ""))
    try:
        wrong = []
        for outcome in OUTCOMES:
            for cls in CLASSES:
                fired = bool(gha_eval(cond, OUTCOME=outcome, OUTCLASS=cls,
                                      EVENT="schedule", SELFTEST=False))
                # The contract, stated once: a scheduled run alarms unless the producer SUCCEEDED
                # and classified the run a pass. Every other cell -- including the empty class a
                # step that never ran leaves behind -- must alarm.
                expected = not (outcome == "success" and cls == "pass")
                if fired != expected:
                    wrong.append(f"{outcome}/{cls or 'EMPTY'}: fired={fired} want={expected}")
        check("alarm if: evaluated over the full outcome x class grid fires on every cell except (success, pass)",
              not wrong, "; ".join(wrong[:4]) or "20 cells correct")
    except Exception as exc:  # noqa: BLE001 - an unparseable condition is a hard failure
        check("alarm if: is evaluable (an unknown token means the grid above proved nothing)",
              False, repr(exc))

    # Scope: a FAILED operator dispatch must file nothing. Dropping the event-name conjunct is
    # invisible to a substring check and turns every operator experiment into an issue.
    try:
        check("alarm if: does NOT fire on a failed operator dispatch (no spam on the manual path)",
              not gha_eval(cond, OUTCOME="failure", OUTCLASS="drift",
                           EVENT="workflow_dispatch", SELFTEST=False))
        check("alarm if: DOES fire for the dispatch-only selftest rehearsal (else it can never be proven live)",
              bool(gha_eval(cond, OUTCOME="success", OUTCLASS="selftest",
                            EVENT="workflow_dispatch", SELFTEST=True)))
    except Exception as exc:  # noqa: BLE001
        check("alarm if: scope cells are evaluable", False, repr(exc))

if hb:
    status_expr = str((hb[0].get("with") or {}).get("status", ""))
    check("the heartbeat declares a status expression", bool(status_expr), status_expr[:120])
    try:
        wrong = []
        for outcome in OUTCOMES:
            for cls in CLASSES:
                got = gha_eval(status_expr, OUTCOME=outcome, OUTCLASS=cls,
                               EVENT="schedule", SELFTEST=False)
                want = "ok" if (outcome == "success" and cls == "pass") else "error"
                if got != want:
                    wrong.append(f"{outcome}/{cls or 'EMPTY'}: got={got!r} want={want!r}")
        check("heartbeat status: evaluates to 'ok' ONLY on (success, pass) and 'error' everywhere else",
              not wrong, "; ".join(wrong[:4]) or "20 cells correct")
    except Exception as exc:  # noqa: BLE001
        check("heartbeat status: is evaluable", False, repr(exc))

# The two conditions must be exact complements over the grid: anything that alarms must also check
# in `error`, and anything that checks in `ok` must file nothing. A drift between them would let a
# class page the operator while the monitor stays green -- or the reverse.
if alarm and hb:
    try:
        split = []
        for outcome in OUTCOMES:
            for cls in CLASSES:
                fired = bool(gha_eval(str(alarm[0].get("if", "")), OUTCOME=outcome, OUTCLASS=cls,
                                      EVENT="schedule", SELFTEST=False))
                st = gha_eval(str((hb[0].get("with") or {}).get("status", "")),
                              OUTCOME=outcome, OUTCLASS=cls, EVENT="schedule", SELFTEST=False)
                if fired != (st == "error"):
                    split.append(f"{outcome}/{cls or 'EMPTY'}: alarm={fired} status={st!r}")
        check("the alarm condition and the heartbeat status are exact complements over the grid",
              not split, "; ".join(split[:4]) or "20 cells agree")
    except Exception as exc:  # noqa: BLE001
        check("alarm/heartbeat complement check is evaluable", False, repr(exc))

# --- (H) ops-email routing ----------------------------------------------------------------------
email = by_name("email")
if email:
    ecetera = str(email[0].get("if", ""))
    check("ops-email fires for drift and readiness", "drift" in ecetera and "readiness" in ecetera, ecetera)
    check("ops-email does NOT fire for unavailable (a bridge outage must not page)",
          "unavailable" not in ecetera, ecetera)

# --- (I) cron/monitor parity --------------------------------------------------------------------
try:
    tf = open("apps/web-platform/infra/sentry/cron-monitors.tf").read()
    m = re.search(r'workspaces_luks_verify.*?crontab\s*=\s*"([^"]+)"', tf, re.S)
    check("a sentry_cron_monitor for workspaces_luks_verify exists", bool(m))
    if m and cron:
        check("the Sentry monitor crontab equals the workflow cron (a drifted pair mis-sizes the margin)",
              m.group(1).strip() == str(cron).strip(), f"tf={m.group(1)} wf={cron}")
except FileNotFoundError:
    check("cron-monitors.tf is readable", False, "not found")

# --- (J) extract every run: body -----------------------------------------------------------------
n = 0
for jn, j in jobs.items():
    for s in (j.get("steps") or []):
        r = s.get("run")
        if not r:
            continue
        n += 1
        open(f"{scratch}/run-{n}.sh", "w").write(r)
        if s.get("id") == "reassert":
            open(f"{scratch}/reassert.sh", "w").write(r)
        if "alarm" in str(s.get("name", "")).lower():
            open(f"{scratch}/alarm.sh", "w").write(r)
check("extracted at least one run: body for syntax checking", n > 0, n)
check("extracted the reassert body for execution", __import__("os").path.exists(f"{scratch}/reassert.sh"))

# --- (K) the classifier must not ship to the host -------------------------------------------------
# The host bundle is a fixed two-file tar. A classifier that rode along would run on the host with
# the boot token in scope, which is a strictly larger blast radius than it needs.
ra = open(f"{scratch}/reassert.sh").read() if __import__("os").path.exists(f"{scratch}/reassert.sh") else ""
mt = re.search(r"tar czf - -C \"\$INFRA_DIR\" ([^\n|]+)", ra)
check("the host bundle file list is unchanged (classifier is not shipped to the host)",
      bool(mt) and "classify" not in mt.group(1), mt.group(1) if mt else "no tar line")

for v in verdicts:
    print("\t".join(v))
PY

while IFS=$'\t' read -r verdict name detail; do
  [[ -n "${verdict:-}" ]] || continue
  if [[ "$verdict" == "ok" ]]; then ok "$name"; else no "$name${detail:+ ($detail)}"; fi
done < "$SCRATCH/verdicts.tsv"

# --- bash -n on EXTRACTED run: bodies ------------------------------------------------------------
syntax_bad=0
extracted=0
for f in "$SCRATCH"/run-*.sh; do
  [[ -e "$f" ]] || continue
  extracted=$((extracted + 1))
  bash -n "$f" 2>/dev/null || syntax_bad=$((syntax_bad + 1))
done
if [[ "$extracted" -eq 0 ]]; then
  no "extracted ZERO run: bodies — the structural leg died before writing them; every behavioral assertion below would be vacuous"
elif [[ "$syntax_bad" -eq 0 ]]; then
  ok "every extracted run: body passes bash -n ($extracted bodies)"
else
  no "$syntax_bad of $extracted extracted run: body/bodies failed bash -n"
fi

# --- behavioral: drive the REAL reassert body to every outcome class -----------------------------
# The stub ssh records argv so the seed assertions can prove a scheduled run wrote nothing. A stub
# that ignored argv would put the fixture seam above the code under test.
if [[ ! -f "$SCRATCH/reassert.sh" ]]; then
  no "could not extract the reassert body — the classification contract is unverified"
else
  mkdir -p "$SCRATCH/bin" "$SCRATCH/infra"
  cp apps/web-platform/infra/luks-monitor.sh "$SCRATCH/infra/" 2>/dev/null || true
  cp apps/web-platform/infra/workspaces-luks-emit.sh "$SCRATCH/infra/" 2>/dev/null || true

  cat > "$SCRATCH/bin/tar" <<'EOS'
#!/usr/bin/env bash
exit 0
EOS
  cat > "$SCRATCH/bin/curl" <<'EOS'
#!/usr/bin/env bash
printf '%s' "${FIXTURE_HEALTH:-200}"
exit 0
EOS
  cat > "$SCRATCH/bin/sshstub" <<'EOS'
#!/usr/bin/env bash
# Records argv so the caller can prove what the workflow actually sent.
printf '%s\n' "$*" >> "${SSH_CALLS:-/dev/null}"
case "$*" in
  *mktemp*)   printf '%s\n' "/var/lib/workspaces-luks/wl-verify.XXXX"; exit 0 ;;
  # ORDER IS LOAD-BEARING. The baseline READ arm must precede the generic write arm: the read
  # command embeds the literal `WORKSPACES_COUNT=` inside its own grep pattern, so a generic
  # `*WORKSPACES_COUNT=*` placed first swallows it, FIXTURE_EXISTING_BASELINE becomes dead, and the
  # workflow's refuse-to-lower-baseline guard — which stops an operator converting a real shortfall
  # into a certified green — is left with zero coverage while the suite reports 69 green.
  *"grep -E '^WORKSPACES_COUNT='"*) printf '%s\n' "${FIXTURE_EXISTING_BASELINE:-}"; exit 0 ;;
  *WORKSPACES_COUNT=*) exit 0 ;;
  *tar\ xzf*) exit 0 ;;
esac
# The probe invocation: emit the fixture's log body, then exit the fixture's rc.
[[ -n "${FIXTURE_PROBE_LOG:-}" ]] && printf '%s\n' "$FIXTURE_PROBE_LOG"
exit "${FIXTURE_PROBE_RC:-0}"
EOS
  chmod +x "$SCRATCH/bin/tar" "$SCRATCH/bin/curl" "$SCRATCH/bin/sshstub"

  # Drive one fixture; echo the class the workflow emitted to GITHUB_OUTPUT.
  #
  # `drive` is invoked as `x=$(... drive)`, i.e. inside a COMMAND SUBSTITUTION — a subshell. Any
  # variable it assigns is discarded the moment the substitution closes, so a `LAST_CALLS=...` here
  # would read as working and be empty in the parent. The CALLER therefore owns the artifact paths
  # via $CALLS and drive only WRITES to them: the ssh-argv file, and a sibling `.rc` holding the
  # exit code. Anything the parent must observe has to travel through a file or through stdout.
  drive() {
    local rc=0
    local calls="${CALLS:-$SCRATCH/calls.default}"
    local out="$calls.out" genv="$calls.env"
    : > "$out"; : > "$genv"; : > "$calls"
    PATH="$SCRATCH/bin:$PATH" \
    SSH_CALLS="$calls" \
    GITHUB_OUTPUT="$out" GITHUB_ENV="$genv" \
    RUNNER_TEMP="$SCRATCH" INFRA_DIR="$SCRATCH/infra" \
    WEB_HOST_SSH="$SCRATCH/bin/sshstub" WEB_HOST="10.0.1.10" \
    WORKSPACES_LUKS_BOOT_TOKEN="dp.ct.fixture" \
    GITHUB_EVENT_NAME="${EV:-schedule}" \
    SEED_WORKSPACE_COUNT="${SEED:-}" \
    FIXTURE_PROBE_RC="${PRC:-0}" FIXTURE_PROBE_LOG="${PLOG:-}" \
    FIXTURE_HEALTH="${HEALTH:-200}" \
    FIXTURE_EXISTING_BASELINE="${EXISTING:-}" \
      bash -e "$SCRATCH/reassert.sh" >/dev/null 2>&1 || rc=$?
    printf '%s\n' "$rc" > "$calls.rc"
    sed -n 's/^outcome_class=//p' "$out" | tail -1
  }

  READYZ_OK='[luks-monitor] SOLEUR_WORKSPACES_READYZ ready=true writable=true populated=true workspace_count=8 expected=8'

  expect_class() { # expect_class <label> <expected> <actual>
    if [[ "$3" == "$2" ]]; then ok "$1 -> $2"; else no "$1 -> expected '$2', got '${3:-<none>}'"; fi
  }

  c_pass=$(PRC=0 PLOG="$READYZ_OK" HEALTH=200 drive)
  expect_class "POSITIVE CONTROL: healthy scheduled run" "pass" "$c_pass"

  c_drift=$(PRC=2 PLOG="" HEALTH=200 drive)
  expect_class "probe rc=2 (at-rest drift)" "drift" "$c_drift"

  c_short=$(PRC=3 PLOG='[luks-monitor] FAIL (workspace_count_shortfall) count=3' HEALTH=200 drive)
  expect_class "rc=3 workspace_count_shortfall" "readiness" "$c_short"

  c_notready=$(PRC=3 PLOG='[luks-monitor] FAIL (readyz_not_ready) ready=false' HEALTH=200 drive)
  expect_class "rc=3 readyz_not_ready" "readiness" "$c_notready"

  c_basemiss=$(PRC=3 PLOG='[luks-monitor] FAIL (workspace_count_baseline_missing)' HEALTH=200 drive)
  expect_class "rc=3 workspace_count_baseline_missing (probe-integrity, proves nothing)" "unavailable" "$c_basemiss"

  c_gatereg=$(PRC=3 PLOG='[luks-monitor] FAIL (readyz_gate_regression) http=403' HEALTH=200 drive)
  expect_class "rc=3 readyz_gate_regression (probe-integrity)" "unavailable" "$c_gatereg"

  c_mapper=$(PRC=3 PLOG='[luks-monitor] FAIL (mapper_path_override_refused)' HEALTH=200 drive)
  expect_class "rc=3 mapper_path_override_refused is a CONFIG fault, not a security finding" "unavailable" "$c_mapper"

  c_emptyreason=$(PRC=3 PLOG='[luks-monitor] FAIL () something' HEALTH=200 drive)
  expect_class "rc=3 with an unparseable reason fails closed toward the louder class" "readiness" "$c_emptyreason"

  c_255=$(PRC=255 PLOG="" HEALTH=200 drive)
  expect_class "rc=255 ssh transport failure proves nothing" "unavailable" "$c_255"

  c_127=$(PRC=127 PLOG="" HEALTH=200 drive)
  expect_class "rc=127 bundle/tooling failure proves nothing" "unavailable" "$c_127"

  c_silent=$(PRC=0 PLOG='[luks-monitor] nothing useful here' HEALTH=200 drive)
  expect_class "rc=0 but the verdict line is ABSENT (the #6807 silent-green shape)" "unavailable" "$c_silent"

  c_307=$(PRC=0 PLOG="$READYZ_OK" HEALTH=307 drive)
  expect_class "health 307 is STRUCTURAL (routing regression, actionable)" "readiness" "$c_307"

  c_521=$(PRC=0 PLOG="$READYZ_OK" HEALTH=521 drive)
  expect_class "health 521 after the full retry budget is an outage, not a finding" "unavailable" "$c_521"

  # --- read-only guarantee on the scheduled path ------------------------------------------------
  seed_calls="$SCRATCH/calls.seed-scheduled"
  c_seed_sched=$(EV=schedule SEED=9 CALLS="$seed_calls" PRC=0 PLOG="$READYZ_OK" drive)
  if [[ "$(cat "$seed_calls.rc" 2>/dev/null || echo 0)" -ne 0 ]]; then
    ok "a scheduled run carrying a seed is REFUSED (non-zero exit)"
  else
    no "a scheduled run carrying a seed was ACCEPTED — the scheduled path is not read-only"
  fi
  expect_class "a refused scheduled seed classifies as unavailable" "unavailable" "$c_seed_sched"
  if grep -q 'WORKSPACES_COUNT=' "$seed_calls" 2>/dev/null; then
    no "a scheduled run WROTE a baseline to the host — the scheduled path must never mutate state"
  else
    ok "a refused scheduled seed reached the host with NO WORKSPACES_COUNT= write"
  fi

  noseed_calls="$SCRATCH/calls.no-seed"
  c_noseed=$(EV=schedule SEED="" CALLS="$noseed_calls" PRC=0 PLOG="$READYZ_OK" drive)
  if grep -q 'WORKSPACES_COUNT=' "$noseed_calls" 2>/dev/null; then
    no "an ordinary scheduled run wrote a baseline (the empty seed entered the seed branch)"
  else
    ok "an ordinary scheduled run does not enter the seed branch (empty seed, no state write)"
  fi
  # The refusal must not cost the healthy path its verdict: a scheduled run with no seed still
  # classifies pass. Without this the no-seed fixture asserts only an absence, and a guard that
  # aborted every scheduled run would satisfy it.
  expect_class "an ordinary scheduled run still reaches a verdict" "pass" "$c_noseed"

  # REFUSE TO LOWER AN EXISTING BASELINE — the guard that stops an operator staring at a
  # workspace_count_shortfall from re-seeding down to the observed (shrunk) count and converting a
  # real sole-copy data-loss finding into a certified green. Reachable only now that the stub's
  # read arm is ordered ahead of its write arm.
  lower_calls="$SCRATCH/calls.seed-below-baseline"
  c_seed_lower=$(EV=workflow_dispatch SEED=5 EXISTING=8 CALLS="$lower_calls" PRC=0 PLOG="$READYZ_OK" drive)
  if [[ "$(cat "$lower_calls.rc" 2>/dev/null || echo 0)" -ne 0 ]]; then
    ok "a dispatch seed BELOW the existing baseline is refused (non-zero exit)"
  else
    no "a downward re-seed was ACCEPTED — a real shortfall can be certified green in one click"
  fi
  expect_class "a refused downward re-seed classifies as unavailable" "unavailable" "$c_seed_lower"
  if grep -qF "printf 'WORKSPACES_COUNT=%s" "$lower_calls" 2>/dev/null; then
    no "the refused downward re-seed still WROTE a baseline to the host"
  else
    ok "the refused downward re-seed reached the host with no baseline write"
  fi

  # The dispatch path must keep working — a seed on a manual dispatch is the supported operation.
  # Anchored on the WRITE construct, not on a bare `WORKSPACES_COUNT=9`: the workflow sends the
  # value as a separate printf argument (`printf 'WORKSPACES_COUNT=%s\n' '9'`), so the naive
  # concatenated form never appears in argv and the assertion would fail against a CORRECT
  # implementation. Both halves are required — the format string alone would also match the
  # refuse-to-lower READ that precedes it.
  disp_calls="$SCRATCH/calls.dispatch-seed"
  c_seed_disp=$(EV=workflow_dispatch SEED=9 CALLS="$disp_calls" PRC=0 PLOG="$READYZ_OK" drive)
  if grep -qF "printf 'WORKSPACES_COUNT=%s" "$disp_calls" 2>/dev/null \
     && grep -qF "'9' >> /var/lib/workspaces-luks/state" "$disp_calls" 2>/dev/null; then
    ok "POSITIVE CONTROL: a manual dispatch CAN still seed (the operator path is not broken)"
  else
    no "the manual seed path stopped working — the dispatch contract regressed"
  fi
  expect_class "a successful dispatch seed still reaches a verdict" "pass" "$c_seed_disp"

  # --- non-vacuity floor over the class space ----------------------------------------------------
  produced=$(printf '%s\n' "$c_pass" "$c_drift" "$c_short" "$c_basemiss" | sort -u | grep -c '[a-z]' || true)
  if [[ "$produced" -ge 4 ]]; then
    ok "the fixture set produced all four outcome classes (pass/drift/readiness/unavailable)"
  else
    no "the fixture set produced only $produced distinct classes — a battery that cannot produce every class proves nothing"
  fi
fi

# --- behavioral: the alarm body over a stubbed gh -------------------------------------------------
if [[ ! -f "$SCRATCH/alarm.sh" ]]; then
  no "could not extract the alarm body — the filing contract is unverified"
else
  cat > "$SCRATCH/bin/gh" <<'EOS'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${GH_CALLS:-/dev/null}"
case "$1 $2" in
  "label create") exit "${FIXTURE_LABEL_RC:-0}" ;;
  "issue list")   printf '%s' "${FIXTURE_ISSUE_LIST:-[]}"; exit 0 ;;
  # The prior body+comments of an already-open issue. This is what the anti-spam bound reads to
  # decide whether the reason CHANGED; without it the "unchanged reason does not re-comment"
  # contract could not be driven at all.
  "issue view")   printf '%s' "${FIXTURE_ISSUE_VIEW:-}"; exit 0 ;;
esac
exit 0
EOS
  chmod +x "$SCRATCH/bin/gh"

  alarm_drive() {
    local rc=0 calls="$SCRATCH/gh.$$"
    : > "$calls"
    PATH="$SCRATCH/bin:$PATH" GH_CALLS="$calls" \
    OUTCOME_CLASS="${CLASS:-}" REASON="${RSN:-none}" \
    FIXTURE_ISSUE_LIST="${LIST:-[]}" FIXTURE_ISSUE_VIEW="${VIEW:-}" \
    RUN_URL="https://example.invalid/run/1" GH_TOKEN="fixture" \
      bash -e "$SCRATCH/alarm.sh" >/dev/null 2>&1 || rc=$?
    LAST_GH="$calls"; LAST_ALARM_RC="$rc"
  }

  CLASS=drift RSN=blkid_not_luks alarm_drive
  # The alarm body runs under `set -euo pipefail`. An abort anywhere between classification and
  # `gh issue create` leaves a run that classified correctly and then filed NOTHING — silence on
  # the one run the alarm exists for. Assert the body completes, not merely that it started.
  if [[ "$LAST_ALARM_RC" -eq 0 ]]; then
    ok "the alarm body runs to completion under set -euo pipefail (no mid-step abort)"
  else
    no "the alarm body aborted (rc=$LAST_ALARM_RC) — it would classify correctly and file nothing"
  fi
  grep -q 'label create' "$LAST_GH" 2>/dev/null \
    && ok "the alarm creates its label idempotently before filing" \
    || no "the alarm never ran gh label create — a first fire on a fresh repo would fail"
  grep -q 'issue list' "$LAST_GH" 2>/dev/null \
    && ok "the alarm QUERIES for an existing issue before creating (dedupe, not spam)" \
    || no "the alarm creates without querying — every scheduled failure would open a new issue"

  # Extract the TITLE ONLY. Grepping the whole `issue create` argv would compare strings that
  # include a per-run mktemp path, so the distinctness check below would pass even if every class
  # produced an identical title — the exact vacuity this assertion exists to rule out.
  title_of() { sed -n 's/.*--title \(.*\) --label.*/\1/p' "$1" | head -1; }

  d_title=$(title_of "$LAST_GH")
  CLASS=readiness RSN=readyz_not_ready alarm_drive
  r_title=$(title_of "$LAST_GH")
  CLASS=unavailable RSN=ssh_transport alarm_drive
  u_title=$(title_of "$LAST_GH")
  CLASS=selftest RSN=alarm_selftest alarm_drive
  s_title=$(title_of "$LAST_GH")
  distinct=$(printf '%s\n%s\n%s\n%s\n' "$d_title" "$r_title" "$u_title" "$s_title" | sort -u | grep -c . || true)
  if [[ "$distinct" -ge 4 ]]; then
    ok "the four classes route to four DISTINCT issue titles"
  else
    no "the classes collapse to $distinct distinct title(s) — dedupe would merge unrelated findings"
  fi
  case "$s_title" in
    *SELF-TEST*) ok "the alarm_selftest rehearsal files under an unmistakable SELF-TEST title" ;;
    *) no "the selftest title ('$s_title') is not marked SELF-TEST — a rehearsal could be read as a real alarm" ;;
  esac

  # FAIL-CLOSED, asserted by TITLE IDENTITY rather than by grepping the argv for the word
  # "unavailable". An empty class is what a Re-assert step that never ran leaves behind, and the
  # property that matters is that it lands on the SAME issue the unavailable class does — which a
  # substring match anywhere in the argv (a label, a temp-file name) would claim without proving.
  CLASS="" RSN=none alarm_drive
  e_title=$(title_of "$LAST_GH")
  if [[ -n "$u_title" && "$e_title" == "$u_title" ]]; then
    ok "an EMPTY outcome_class fails closed to the same issue as unavailable"
  else
    no "an empty outcome_class filed '${e_title:-<nothing>}' but unavailable files '${u_title:-<nothing>}' — the fail-closed default is missing or routes elsewhere"
  fi

  # DEDUPE IS BY EXACT TITLE, so the fixture must carry the exact title the drift class files. An
  # arbitrary open issue (the earlier fixture used title "x") would leave the alarm correctly
  # CREATING, and the assertion would then fail against a correct implementation while passing
  # against one that comments on any open issue at all. Pinning the literal here is deliberate: the
  # title IS the dedupe key, so a title change must turn this suite red.
  DRIFT_TITLE='[ci/luks-verify] at-rest drift on /mnt/data'
  LIST="[{\"number\":1,\"title\":\"${DRIFT_TITLE}\"}]" CLASS=drift RSN=blkid_not_luks alarm_drive
  if grep -q 'issue comment' "$LAST_GH" 2>/dev/null && ! grep -q 'issue create' "$LAST_GH" 2>/dev/null; then
    ok "an open issue with the EXACT title is COMMENTED on, not re-created"
  else
    no "an existing open issue was re-created — the alarm spams on every scheduled failure"
  fi

  # The negative control the fixture above needs to mean anything: an open issue with a DIFFERENT
  # title must NOT suppress the filing. Without this, "dedupe by exact title" and "dedupe by any
  # open issue in the label" are indistinguishable, and the second would silently swallow the first
  # at-rest drift issue behind a standing readiness issue.
  LIST='[{"number":7,"title":"[ci/luks-verify] readiness or inventory failure"}]' CLASS=drift RSN=blkid_not_luks alarm_drive
  if grep -q 'issue create' "$LAST_GH" 2>/dev/null && ! grep -q 'issue comment' "$LAST_GH" 2>/dev/null; then
    ok "an open issue of a DIFFERENT class does not suppress a drift filing (dedupe is by exact title)"
  else
    no "a different-class open issue swallowed the drift filing — the legal re-evaluation trigger would never be filed"
  fi

  # ANTI-SPAM BOUND. Nothing here auto-closes, so a daily cadence against a standing issue would
  # accrete a comment a day. A repeat failure whose reason is UNCHANGED must stay silent.
  LIST="[{\"number\":1,\"title\":\"${DRIFT_TITLE}\"}]" VIEW='previously seen at ... reason=blkid_not_luks ...' \
    CLASS=drift RSN=blkid_not_luks alarm_drive
  if grep -q 'issue comment' "$LAST_GH" 2>/dev/null; then
    no "a repeat failure with an UNCHANGED reason still commented — the issue accretes ~365 comments a year"
  else
    ok "a repeat failure with an unchanged reason does NOT add another comment"
  fi

  # ...and the positive control for that bound: a CHANGED reason must still be reported, or the
  # anti-spam rule would silently swallow a genuine escalation.
  LIST="[{\"number\":1,\"title\":\"${DRIFT_TITLE}\"}]" VIEW='previously seen at ... reason=blkid_not_luks ...' \
    CLASS=drift RSN=mount_not_mapper alarm_drive
  if grep -q 'issue comment' "$LAST_GH" 2>/dev/null; then
    ok "a repeat failure with a CHANGED reason is still commented (the bound is not a mute button)"
  else
    no "a changed reason was suppressed — the anti-spam bound is swallowing real escalations"
  fi
fi

printf '\n%s passed, %s failed\n' "$pass" "$fail"

# NON-DEGENERACY FLOOR — mirrors WF_MIN_ASSERTIONS in the sibling cutover-workflow suite. A python
# leg that dies before emitting verdicts, or a behavioral block deleted wholesale, would otherwise
# leave this suite reporting "0 passed, 0 failed" and exiting 0 — the exact silent-green shape this
# workflow exists to prevent on the live surface.
WF_MIN_ASSERTIONS=40
if [[ "$pass" -lt "$WF_MIN_ASSERTIONS" ]]; then
  echo "FAIL - only $pass assertions ran (floor $WF_MIN_ASSERTIONS) — fewer verdicts than expected; a green run here would be vacuous"
  exit 1
fi
[[ "$fail" -eq 0 ]] || exit 1
