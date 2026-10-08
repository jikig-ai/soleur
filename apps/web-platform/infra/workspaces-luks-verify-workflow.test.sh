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
# Created HERE, not inside the reassert leg, so that deleting a behavioral block reds on the
# non-degeneracy floor at the bottom — which names what went wrong — instead of dying under `set -e`
# at the next leg's `cat > "$SCRATCH/bin/gh"`. A suite whose deletion detector is an unrelated
# redirection failure is reporting the wrong thing.
mkdir -p "$SCRATCH/bin" "$SCRATCH/infra"

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

# GitHub performs LOOSE equality: when the operand types differ it coerces to Number, so `'' == 0`
# is TRUE there and FALSE in Python. Every other untranslatable token fails closed — `true`/`false`/
# `null` and the status functions all raise NameError against the stripped builtins — but a NUMERIC
# literal is valid Python, so a comparison against one would evaluate silently and WRONGLY. That is
# a false GREEN on the exact cell this file cares most about: an empty outcome_class (what a
# Re-assert step that never ran leaves behind) compares EQUAL to 0 in GitHub and UNEQUAL in Python,
# which is the difference between the alarm firing and the alarm being suppressed. Refuse to model
# any expression that compares against a bare numeric literal rather than pretending we can.
_NUMERIC_COMPARE = re.compile(r"(==|!=)\s*-?\d")

def gha_translate(expr):
    e = str(expr).strip()
    if e.startswith("${{"):
        e = e[3:]
    if e.endswith("}}"):
        e = e[:-2]
    if _NUMERIC_COMPARE.search(e):
        raise ValueError(
            "comparison against a numeric literal: GitHub coerces mismatched types to Number "
            "(so '' == 0 is TRUE) while Python does not — this evaluator cannot model it")
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
# EVERY member the producer can emit, derived by reading the emit_class call sites — `selftest` was
# missing, so the assertion named "the FULL outcome x class grid" quantified over 4 of 5 non-empty
# enum members. It is unreachable on a schedule event today (only ALARM_SELFTEST=true emits it, and
# a schedule supplies no inputs), which is exactly why leaving it out was invisible.
CLASSES = ["pass", "drift", "readiness", "unavailable", "selftest", ""]

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
    # ALL THREE date fields, not two. `f[4]` (day-of-week) is the one that actually turns daily
    # into weekly — `41 4 * * 1` passed the earlier two-field check while running once a week,
    # under an assertion whose own name promises "at least daily", and the tf/workflow crontab
    # parity check passes too when both files are changed together.
    check("cron runs at least daily (day-of-month, month AND day-of-week are unrestricted)",
          f[2] == "*" and f[3] == "*" and f[4] == "*", cron)

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
# BEHAVIOURAL, not a name substring. `"close" in step.name` is a proxy: re-adding the step under
# any other name ("Resolve the ci/luks-verify issue on a green run") satisfied it at full green.
# Assert the CAPABILITY is absent from every run body instead.
close = [s for s in steps if "close" in str(s.get("name", "")).lower()]
closers = [s.get("name") for s in steps if re.search(r"gh\s+issue\s+close", str(s.get("run", "")))]
check("no green-close step exists (Decision 2 — a green run files nothing and closes nothing)",
      len(close) == 0 and not closers, [s.get("name") for s in close] + closers)

# --- (G) the Sentry check-in --------------------------------------------------------------------
hb = by_name("sentry")
check("a Sentry check-in step exists", len(hb) == 1, [s.get("name") for s in steps])
if hb:
    hcond = str(hb[0].get("if", ""))
    check("heartbeat is always()", "always()" in hcond, hcond)
    check("heartbeat is continue-on-error (a monitor outage must not red the verify)",
          bool(hb[0].get("continue-on-error")), hb[0].get("continue-on-error"))
    check("heartbeat is scoped to scheduled runs", "github.event_name == 'schedule'" in hcond, hcond)
    # EVALUATED, not just grepped. The substring above still passes if someone appends
    # `|| inputs.alarm_selftest`, which is precisely the defect both the workflow header and
    # cron-monitors.tf name as load-bearing: "a manual dispatch must not be able to forge liveness
    # while the cron is dead." The alarm gets two dedicated dispatch-scope cells; this had none.
    try:
        forged = []
        for selftest in (False, True):
            for outcome in OUTCOMES:
                if gha_eval(hcond, OUTCOME=outcome, OUTCLASS="pass",
                            EVENT="workflow_dispatch", SELFTEST=selftest):
                    forged.append(f"dispatch/selftest={selftest}/{outcome}")
        check("heartbeat if: NEVER runs on a workflow_dispatch, selftest included "
              "(a dispatch must not forge liveness while the cron is dark)",
              not forged, "; ".join(forged[:4]) or "8 dispatch cells all suppressed")
    except Exception as exc:  # noqa: BLE001
        check("heartbeat if: dispatch-scope cells are evaluable", False, repr(exc))
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
        # The bool above is only the right model because the input is DECLARED `type: boolean`.
        # `inputs.<name>` preserves the declared type; `github.event.inputs.<name>` stringifies
        # everything, and GitHub casts any non-empty string to true — so under a string the
        # literal 'false' would be TRUTHY and every failed operator dispatch would file an issue.
        # The declared type is what makes the no-spam guarantee hold, so pin it here rather than
        # leaving it an unstated premise of this cell.
        selftest_input = ((on.get("workflow_dispatch") or {}).get("inputs") or {}).get("alarm_selftest") or {}
        check("alarm_selftest is declared type: boolean (a string-typed input makes the literal "
              "'false' truthy in GitHub, which would spam every failed operator dispatch)",
              selftest_input.get("type") == "boolean", repr(selftest_input.get("type")))
        check("alarm_selftest defaults to false", selftest_input.get("default") is False,
              repr(selftest_input.get("default")))
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
# EXISTENCE FIRST. `alarm` and `hb` each get an existence check before their `if:` assertions; this
# one did not, so deleting the ops-email step wholesale left every assertion below simply un-run
# and the suite green — drift and readiness silently lose their page entirely.
check("an ops-email step exists", len(email) == 1, [s.get("name") for s in steps])
if email:
    ecetera = str(email[0].get("if", ""))
    check("ops-email step carries id: ops_email (the alarm body records its outcome)",
          email[0].get("id") == "ops_email", email[0].get("id"))
    check("ops-email if: contains always() (without it GitHub ANDs an implicit success(), making "
          "the page unreachable on exactly the failing runs it exists for)",
          "always()" in ecetera, ecetera)
    # THE THIRD CONDITION-BEARING STEP, evaluated rather than grepped. Substring checks on this
    # `if:` are satisfied by an INVERTED condition — `!= 'drift' && != 'readiness'` still contains
    # both words and still lacks "unavailable" — which pages on every healthy night and stays
    # silent on the two classes the page exists for. That is failure mode (1) from this file's own
    # header, applied to the one step it had not been applied to.
    try:
        wrong = []
        for outcome in OUTCOMES:
            for cls in CLASSES:
                for event, selftest in (("schedule", False), ("workflow_dispatch", False),
                                        ("workflow_dispatch", True)):
                    fired = bool(gha_eval(ecetera, OUTCOME=outcome, OUTCLASS=cls,
                                          EVENT=event, SELFTEST=selftest))
                    expected = (event == "schedule" or selftest) and cls in ("drift", "readiness")
                    if fired != expected:
                        wrong.append(f"{event}/selftest={selftest}/{outcome}/{cls or 'EMPTY'}: "
                                     f"fired={fired} want={expected}")
        check("ops-email if: evaluated over outcome x class x event fires ONLY for drift/readiness "
              "on a schedule or selftest run",
              not wrong, "; ".join(wrong[:4]) or "72 cells correct")
    except Exception as exc:  # noqa: BLE001
        check("ops-email if: is evaluable", False, repr(exc))

# --- (I) cron/monitor parity --------------------------------------------------------------------
try:
    tf = open("apps/web-platform/infra/sentry/cron-monitors.tf").read()
    # ANCHORED ON THE RESOURCE HEADER, not on a bare token. `re.search` with `re.S` and a
    # non-greedy `.*?` took the first `crontab` following the FIRST textual occurrence of
    # `workspaces_luks_verify` ANYWHERE in a 1100-line file, comments included — so a future
    # comment mentioning the underscored name above some earlier resource would silently retarget
    # this assertion at a DIFFERENT monitor's crontab (cq-assert-anchor-not-bare-token).
    blk = re.search(r'^resource\s+"sentry_cron_monitor"\s+"workspaces_luks_verify"\s*\{(.*?)^\}',
                    tf, re.S | re.M)
    check("a sentry_cron_monitor resource block for workspaces_luks_verify exists", bool(blk))
    if blk:
        body = blk.group(1)
        m = re.search(r'crontab\s*=\s*"([^"]+)"', body)
        check("the monitor block declares a crontab", bool(m), body[:120])
        if m and cron:
            check("the Sentry monitor crontab equals the workflow cron (a drifted pair mis-sizes the margin)",
                  m.group(1).strip() == str(cron).strip(), f"tf={m.group(1)} wf={cron}")
        # SLUG PARITY. The pair has TWO fields that must agree, and only `crontab` was checked —
        # so a typo'd monitor-slug sent every check-in to a monitor that does not exist while the
        # real one paged "missed check-in" forever, at full green.
        tfname = re.search(r'\bname\s*=\s*"([^"]+)"', body)
        wf_slug = ((hb[0].get("with") or {}).get("monitor-slug") if hb else None)
        check("the workflow's monitor-slug equals the terraform monitor name",
              bool(tfname) and wf_slug == tfname.group(1),
              f"wf={wf_slug!r} tf={tfname.group(1) if tfname else None!r}")
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
# PIN THE EXACT LIST, not the absence of one word. `"classify" not in ...` let ANY file be added to
# the host bundle as long as its name did not contain "classify", under an assertion whose own name
# claims the list is "unchanged". The host runs this bundle with the prd_workspaces_luks boot token
# in scope, so what ships is a blast-radius decision, not a detail.
EXPECTED_BUNDLE = ["luks-monitor.sh", "workspaces-luks-emit.sh"]
_bundle = [t for t in (mt.group(1).split() if mt else []) if t != "\\"]
check("the host bundle ships EXACTLY the two probe scripts (nothing rides along into boot-token scope)",
      bool(mt) and sorted(_bundle) == sorted(EXPECTED_BUNDLE),
      " ".join(_bundle) if mt else "no tar line")

# --- (L) the issue-search API abstention, actually enforced ------------------------------------
# The workflow's dedupe comment says the flag that would reach the issue-search API is "deliberately
# absent from this file, comments included", and cited AC10 as the guard. AC10 is the /health
# structural-set parity check and has nothing to do with it — no assertion anywhere greped for the
# flag, so a real readability cost was paid for zero enforcement. This is that guard. It reads the
# RAW file (comments intact) on purpose: a prose mention would otherwise make it unable to
# distinguish "we use it" from "we explain why we do not".
raw_wf = open(sys.argv[1]).read()
check("the issue-search API flag is absent from the workflow, comments included "
      "(dedupe is label + exact title; that API can return empty under some token contexts)",
      "--search" not in raw_wf,
      [ln.strip()[:80] for ln in raw_wf.splitlines() if "--search" in ln][:2])

# --- (M) producer/consumer parity for the two classification allowlists -------------------------
# The at-rest allowlist is a POSITIVE gate, so its fail direction is "unrecognised -> unavailable".
# That is the safe direction for a false Article 32 claim, but it means a NEW at-rest reason added
# upstream and not added here would be silently UNDER-reported. A per-member spot-check can never
# detect a MISSING member, so derive both sets mechanically and compare.
try:
    lm = open("apps/web-platform/infra/luks-monitor.sh").read()
    produced = set(re.findall(r"emit_and_die\s+([a-z_]+)", lm))
    integrity = set(re.search(r"is_probe_integrity\(\)\s*\{.*?case.*?in\s*\n\s*([a-z_|]+)\)", ra, re.S).group(1).split("|"))
    at_rest = set(re.search(r"is_at_rest_drift\(\)\s*\{.*?case.*?in\s*\n\s*([a-z_|]+)\)", ra, re.S).group(1).split("|"))
    # Deliberately unclassified by EITHER list: both are reached only after mountpoint, mount-source
    # and mapper-node checks have all passed, so "cryptsetup cannot describe it" is a tooling/parse
    # fault rather than plaintext at rest. They fall through to `unavailable`, which still alarms.
    TOOLING_FAULTS = {"cryptsetup_status_missing", "mapper_device_link_missing"}
    unclassified = produced - integrity - at_rest - TOOLING_FAULTS
    check("every emit_and_die reason luks-monitor.sh can produce is classified by the workflow "
          "(a new at-rest reason must not silently fall through to unavailable)",
          not unclassified, sorted(unclassified))
    check("the at-rest allowlist contains no reason the producer cannot emit",
          not (at_rest - produced), sorted(at_rest - produced))
    check("the tooling-fault carve-out is exactly the two documented parse failures",
          TOOLING_FAULTS <= produced, sorted(TOOLING_FAULTS - produced))
except (FileNotFoundError, AttributeError) as exc:
    check("the classification allowlists are derivable from the workflow and luks-monitor.sh",
          False, repr(exc))

# --- (M2) THE EXIT-SITE MAP, asserted rather than sampled ---------------------------------------
# The header states "(2) Is every exit site classified?" as a governing property, and the workflow
# repeats it ("EVERY exit below is preceded by emit_class"). Both were prose: the behavioural
# battery drives 13 fixtures and happens to cover most exits, which is coverage-by-example, not the
# invariant — a new `|| { echo "::error::…"; exit 1; }` added anywhere passed every assertion.
#
# AC4's replacement verification (set-equality over messages and exit codes) was ALSO a one-time
# manual check with nothing committed, replacing an AC whose whole point was to hold across future
# edits. This is the committed form, and it asserts the property AC4 actually protects: an exit that
# emits no class is an outcome the alarm cannot distinguish from "the step never ran".
_lines = ra.splitlines()
_EXIT_RE = re.compile(r"(^|[;&|]|\bthen\s+|\{\s*)\s*exit\b")
_exit_sites = [(_i, _ln) for _i, _ln in enumerate(_lines)
               if _EXIT_RE.search(_ln) and not re.match(r"\s*#", _ln)]
_unclassified = []
for _i, _ln in enumerate(_lines):
    if (_i, _ln) not in _exit_sites:
        continue
    # SCOPE THE LOOKBACK, or the check is satisfied by an unrelated emit_class further up. A fixed
    # N-line window is exactly that mistake: stripping emit_class from an inline
    # `|| { echo …; exit 1; }` left a 6-line window still reaching the PREVIOUS guard's emit_class,
    # and the mutant survived. Two rules instead:
    #   - inline `{ …; exit N; }` one-liner  -> emit_class must be on THAT line; there is no
    #     preceding statement inside that block.
    #   - multi-line block                    -> walk back, stopping at any boundary (another exit,
    #     `fi`, `esac`, `;;`, `else`) so a sibling branch's emit_class cannot vouch for this one.
    _inline_block = bool(re.search(r"\{[^}]*\bexit\b", _ln))
    if _inline_block:
        if "emit_class" in _ln:
            continue
    else:
        if "emit_class" in _ln:
            continue
        _ok = False
        _j = _i - 1
        while _j >= 0 and _j > _i - 12:
            _prev = _lines[_j]
            if "emit_class" in _prev:
                _ok = True
                break
            # An `fi` directly above is NOT a boundary — it is a whole if/else whose arms may each
            # emit a class, which is the shape of the rc=3 and rc!=0 branches. Walk back to the
            # matching `if` (depth-tracked) and require EVERY arm to emit, so a block where only one
            # arm classifies still fails.
            if re.match(r"\s*fi\b", _prev):
                _depth, _k = 1, _j - 1
                while _k >= 0 and _depth:
                    if re.match(r"\s*fi\b", _lines[_k]):
                        _depth += 1
                    elif re.match(r"\s*if\b", _lines[_k]):
                        _depth -= 1
                    _k -= 1
                _blk = _lines[_k + 1:_j]
                _arms, _cur = [], []
                for _b in _blk:
                    if re.match(r"\s*(else|elif)\b", _b):
                        _arms.append(_cur); _cur = []
                    else:
                        _cur.append(_b)
                _arms.append(_cur)
                if len(_arms) >= 2 and all(any("emit_class" in _x for _x in _a) for _a in _arms):
                    _ok = True
                break
            if re.search(r"^\s*(esac|;;)\b|\bexit\b", _prev):
                break
            _j -= 1
        if _ok:
            continue
    _unclassified.append(f"L{_i + 1}: {_ln.strip()[:70]}")
check("EVERY exit site in the reassert body is preceded by an emit_class "
      "(an unclassified exit is indistinguishable from a step that never ran)",
      not _unclassified, _unclassified[:4])
# Non-vacuity control for the walk above: if the scan finds no exits at all it would pass trivially.
check("the exit-site scan actually found exit sites (a zero-exit parse would pass vacuously)",
      sum(1 for _ln in _lines if re.search(r"(^|[;&|]|\bthen\s+|\{\s*)\s*exit\b", _ln)
          and not re.match(r"\s*#", _ln)) >= 10,
      sum(1 for _ln in _lines if re.search(r"(^|[;&|]|\bthen\s+|\{\s*)\s*exit\b", _ln)))

# --- (N) the runbook triage table is the THIRD copy of the classifier, so gate it ---------------
# Every filed issue ends with "the verdict triage table maps every rc and reason to an
# outcome_class and an operator response, no SSH required." That was a UNIVERSAL claim over a
# hand-transcribed table that nothing compared against the producer — 18 reachable reasons had no
# row, four of which file the p0 type/security at-rest issue and sent the reader to a table whose
# nearest match prescribed a destructive re-cut. A claim in an alarm body is a promise made at the
# worst possible moment, so it gets a guard.
try:
    rb = open("knowledge-base/engineering/operations/runbooks/workspaces-luks-cutover-6604.md").read()
    lm_all = open("apps/web-platform/infra/luks-monitor.sh").read()
    emit_all = open("apps/web-platform/infra/workspaces-luks-emit.sh").read() if __import__("os").path.exists("apps/web-platform/infra/workspaces-luks-emit.sh") else ""
    reasons = set(re.findall(r"emit_(?:and|readiness_and)_die\s+([a-z_]+)", lm_all + emit_all))
    reasons |= set(re.findall(r"emit_class\s+\w+\s+([a-z_]+)", ra))
    reasons -= {"unparsed", "verified", "alarm_selftest"}   # sentinels, not diagnosable conditions
    absent = sorted(r for r in reasons if r not in rb)
    check("every reason the producer or workflow can emit has a row in the runbook triage table "
          "(the alarm body promises the table maps EVERY rc and reason)",
          not absent, absent)
except FileNotFoundError as exc:
    check("the runbook triage table is readable", False, repr(exc))

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
# (#7226) web-1 serving a key other than the pin: EVERY call fails the way OpenSSH does under
# StrictHostKeyChecking yes — its own text on stderr, its own rc 255. A forged ::error:: line rides
# along to prove the raw text stays inside the stop-commands span.
if [[ "${FIXTURE_HOSTKEY_FAIL:-0}" == 1 ]]; then
  printf '%s\n' '@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@' \
    '@    WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!     @' \
    '::error title=forged::verdict=pass' \
    'Host key verification failed.' >&2
  exit 255
fi
case "$*" in
  *mktemp*)   printf '%s\n' "/var/lib/workspaces-luks/wl-verify.XXXX"; exit 0 ;;
  # ORDER IS LOAD-BEARING. The baseline READ arm must precede the generic write arm, or a generic
  # `*WORKSPACES_COUNT=*` swallows it, FIXTURE_EXISTING_BASELINE goes dead, and the workflow's
  # refuse-to-lower-baseline guard — which stops an operator converting a real shortfall into a
  # certified green — is left with zero coverage while the suite reports green.
  #
  # THE SENTINEL IS THE POINT. This arm is anchored on the workflow's exact read command, so ANY
  # reformatting of that ssh string silently stops it matching and re-opens the shadow. Recording
  # STUB_BASELINE_READ lets the caller assert the arm was actually REACHED, which turns that
  # silent shadow into a red. Measured: changing the read from a `grep|tail|cut` pipeline to
  # `cat` did exactly this, mid-review.
  *"cat /var/lib/workspaces-luks/state"*)
    printf 'STUB_BASELINE_READ\n' >> "${SSH_CALLS:-/dev/null}"
    if [[ -n "${FIXTURE_BASELINE_READ_RC:-}" && "${FIXTURE_BASELINE_READ_RC}" != "0" ]]; then
      exit "${FIXTURE_BASELINE_READ_RC}"
    fi
    [[ -n "${FIXTURE_EXISTING_BASELINE:-}" ]] && printf 'WORKSPACES_COUNT=%s\n' "$FIXTURE_EXISTING_BASELINE"
    exit 0 ;;
  *WORKSPACES_COUNT=*) exit 0 ;;
  # Drain here too: `tar czf - | ssh ... "tar xzf -"` is the same producer->stub pipe as the probe's
  # (#7376). Today the tar stub emits nothing, so this cannot race; draining keeps it that way if a
  # fixture ever makes the tar stub write.
  *tar\ xzf*) cat >/dev/null; exit 0 ;;
  # (#8706) the informational unit-state read. Its own arm, so it never falls through to the probe
  # arm below (which would replay FIXTURE_PROBE_LOG and FIXTURE_PROBE_RC a second time). A forged
  # workflow command rides along to prove the line prefix keeps remote text inert.
  *"systemctl show"*)
    printf '%s\n' 'LoadState=loaded' 'UnitFileState=enabled' '::error title=forged-unit::verdict=pass'
    # The runner splits step output on CR as well as LF, so a CR-embedded command is a second line.
    printf 'ActiveState=x\r::error title=forged-cr::verdict=pass\n'
    exit "${FIXTURE_UNITSTATE_RC:-0}" ;;
esac
# The probe invocation: the workflow feeds it .env text on stdin (`printf ... | ssh ...`). Real ssh reads
# stdin to EOF, so this stub does too; a stub that exits without reading makes the producer take SIGPIPE
# (or EPIPE where SIGPIPE is ignored, as on CI) whenever the producer is scheduled late, and the
# pipeline status then reads as a probe failure under pipefail (#7376). FIXTURE_NO_DRAIN=1 restores the
# non-reading stub as the race rows' positive control. The sentinel is created AFTER stdin is closed (or
# just before the drain) so slow_printf can hand off deterministically.
if [[ "$*" == *luks-monitor.sh* ]]; then
  if [[ "${FIXTURE_NO_DRAIN:-0}" == 1 ]]; then
    exec 0<&-
    : > "${PROBE_SENTINEL:-/dev/null}"
  else
    : > "${PROBE_SENTINEL:-/dev/null}"
    # Keep what was read: the late-producer row asserts the .env text actually ARRIVED, which no
    # timing-based check can (a stub that stops draining but exits late looks identical).
    cat > "${PROBE_STDIN:-/dev/null}"
  fi
fi
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
  # The body runs with stdin from /dev/null so the ONLY pipes it sees are the workflow's own
  # (`printf | ssh`, `tar | ...`): an inherited open stdin would be drained by a stub arm and hang the
  # suite under a harness that leaves a pipe open (measured: `sleep 20 | timeout 8 bash <suite>` rc 124).
  drive() {
    local rc=0
    local calls="${CALLS:-$SCRATCH/calls.default}"
    local out="$calls.out" genv="$calls.env"
    : > "$out"; : > "$genv"; : > "$calls"; rm -f "$calls.sentinel" "$calls.sentinel.released" "$calls.probe-stdin"
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
    FIXTURE_BASELINE_READ_RC="${READRC:-0}" \
    ALARM_SELFTEST="${SELFTEST:-}" \
    FIXTURE_UNITSTATE_RC="${USRC:-0}" \
      FIXTURE_HOSTKEY_FAIL="${HKFAIL:-0}" \
      FIXTURE_NO_DRAIN="${NODRAIN:-0}" PROBE_SENTINEL="$calls.sentinel" PROBE_STDIN="$calls.probe-stdin" \
      bash -e "${REASSERT:-$SCRATCH/reassert.sh}" >"$calls.stdout" 2>&1 </dev/null || rc=$?
    printf '%s\n' "$rc" > "$calls.rc"
    sed -n 's/^outcome_class=//p' "$out" | tail -1
  }

  READYZ_OK='[luks-monitor] SOLEUR_WORKSPACES_READYZ ready=true writable=true populated=true workspace_count=8 expected=8'

  expect_class() { # expect_class <label> <expected> <actual>
    if [[ "$3" == "$2" ]]; then ok "$1 -> $2"; else no "$1 -> expected '$2', got '${3:-<none>}'"; fi
  }

  c_pass=$(PRC=0 PLOG="$READYZ_OK" HEALTH=200 drive)
  expect_class "POSITIVE CONTROL: healthy scheduled run" "pass" "$c_pass"

  # --- (#8706) the informational unit-state line: present, AFTER the probe, and verdict-neutral ---
  us_calls="$SCRATCH/calls.unitstate"
  c_us=$(CALLS="$us_calls" PRC=0 PLOG="$READYZ_OK" HEALTH=200 drive)
  # `|| true`: no match is an ANSWER here (the assertion below reports it), not a reason for this
  # `set -e` suite to die before it can say which line was missing.
  us_probe_ln="$(grep -n 'luks-monitor.sh' "$us_calls" | grep -v 'tar ' | head -1 | cut -d: -f1)" || true
  us_show_ln="$(grep -n 'systemctl show -p Id,LoadState,UnitFileState,ActiveState,LastTriggerUSec,Result,ExecMainStatus luks-monitor.timer luks-monitor.service' "$us_calls" | head -1 | cut -d: -f1)" || true
  if [[ -n "$us_probe_ln" && -n "$us_show_ln" && "$us_show_ln" -gt "$us_probe_ln" ]] \
     && grep -qxF '[unit-state] UnitFileState=enabled' "$us_calls.stdout"; then
    ok "#8706: the unit-state read runs AFTER the probe and prints prefixed [unit-state] lines"
  else
    no "#8706: the unit-state read is missing, precedes the probe, or is unprefixed (probe_ln=${us_probe_ln:-none} show_ln=${us_show_ln:-none})"
  fi
  if grep -q '^::error title=forged-unit' "$us_calls.stdout"; then
    no "#8706: remote unit-state text reached the log unprefixed — it could issue a workflow command"
  else
    ok "#8706: remote unit-state text is prefixed, so a forged ::workflow-command:: stays inert"
  fi
  if grep -q '^[[:space:]]*::error title=forged-cr' < <(tr '\r' '\n' < "$us_calls.stdout"); then
    no "#8706: a CR-embedded workflow command in remote unit-state text survives as its own runner line"
  else
    ok "#8706: a CR-embedded workflow command in remote unit-state text is stripped before the prefix"
  fi
  expect_class "#8706: the unit-state read does not change a healthy verdict" "pass" "$c_us"
  # Its OWN failure is swallowed: an unreachable/failed read must not move any class or exit path.
  for us_rc in 1 255; do
    c_usf=$(CALLS="$SCRATCH/calls.unitstate-fail-$us_rc" USRC="$us_rc" PRC=0 PLOG="$READYZ_OK" HEALTH=200 drive)
    expect_class "#8706: a unit-state read failing rc=$us_rc leaves a healthy run" "pass" "$c_usf"
    if [[ "$(cat "$SCRATCH/calls.unitstate-fail-$us_rc.rc")" == 0 ]]; then
      ok "#8706: a unit-state read failing rc=$us_rc leaves the step exit 0"
    else
      no "#8706: a unit-state read failing rc=$us_rc changed the step exit ($(cat "$SCRATCH/calls.unitstate-fail-$us_rc.rc"))"
    fi
    c_usd=$(CALLS="$SCRATCH/calls.unitstate-drift-$us_rc" USRC="$us_rc" PRC=1 PLOG='[luks-monitor] FAIL (mount_not_mapper) src=/dev/sdb' HEALTH=200 drive)
    expect_class "#8706: a unit-state read failing rc=$us_rc leaves an at-rest verdict" "drift" "$c_usd"
  done
  # Skipped on a transport failure: one bounded-ssh wait is enough when the tunnel is down.
  c_us255=$(CALLS="$SCRATCH/calls.unitstate-t255" PRC=255 PLOG="" HEALTH=200 drive)
  if [[ "$c_us255" == unavailable ]] && ! grep -q 'systemctl show' "$SCRATCH/calls.unitstate-t255"; then
    ok "#8706: the unit-state read is skipped on an rc-255 transport failure (class unchanged)"
  else
    no "#8706: the unit-state read ran on an rc-255 transport failure, or the class moved (${c_us255:-<none>})"
  fi

  # THE AT-REST CLASS REQUIRES A RECOGNISED REASON. This fixture used to be `PRC=2 PLOG=""`, i.e.
  # a non-zero rc with NO parseable reason — which pinned the old negative gate ("anything not
  # probe-integrity is drift") and so enshrined the defect that a bash SYNTAX ERROR (rc 2) filed a
  # p0 type/security issue asserting the published Article 32 claim false. Drive a real at-rest
  # verdict instead, and pin the reason through to the output.
  c_drift=$(PRC=1 PLOG='[luks-monitor] FAIL (mount_not_mapper) src=/dev/sdb' HEALTH=200 drive)
  expect_class "rc=1 mount_not_mapper is a recognised AT-REST verdict" "drift" "$c_drift"

  c_drift2=$(PRC=1 PLOG='[luks-monitor] FAIL (device_not_luks) blkid=ext4' HEALTH=200 drive)
  expect_class "rc=1 device_not_luks is a recognised AT-REST verdict" "drift" "$c_drift2"

  # THE FAIL DIRECTION OF THE ALLOWLIST. bash exits 2 on a syntax error or builtin misuse, and
  # luks-monitor.sh refuses exit 2 for readiness on exactly that reasoning. An unrecognised
  # reason — or none at all — must NOT earn the one class that asserts a legal claim.
  c_rc2=$(PRC=2 PLOG="" HEALTH=200 drive)
  expect_class "rc=2 with NO parseable reason is a can't-measure, NOT an at-rest finding" "unavailable" "$c_rc2"

  c_unknown=$(PRC=1 PLOG='[luks-monitor] FAIL (some_future_reason) x=1' HEALTH=200 drive)
  expect_class "an UNRECOGNISED rc=1 reason falls to unavailable, never to the legal class" "unavailable" "$c_unknown"

  # The two reasons deliberately NOT in the at-rest allowlist: both are reached only after the
  # mount/mapper chain has already passed, so they are tooling/parse faults, not plaintext.
  c_cryptstat=$(PRC=1 PLOG='[luks-monitor] FAIL (cryptsetup_status_missing)' HEALTH=200 drive)
  expect_class "rc=1 cryptsetup_status_missing is a tooling fault (mapper served the mount)" "unavailable" "$c_cryptstat"

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

  # --- (#7226, ADR-237) web-1 host-key mismatch: its own reason, never "transport, re-dispatch" ---
  # reason_of <calls> — the outcome_reason the run emitted.
  reason_of() { sed -n 's/^outcome_reason=//p' "$1.out" | tail -1; }
  HK_TITLE='::error title=workspaces-luks-verify::verdict=host_key_mismatch role=web'
  PLOG_HK=$'@    WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!     @\nHost key verification failed.'
  # hk_row <label> <want-reason> <calls-name> [VAR=value ...] — drive, then assert class + reason.
  hk_row() {
    local label="$1" want="$2" calls="$SCRATCH/calls.$3"; shift 3
    local c
    # shellcheck disable=SC2163  # "$@" is VAR=value pairs: exporting them IS the intent
    c=$(export "$@"; CALLS="$calls" HEALTH=200 drive)
    if [[ "$c" == unavailable && "$(reason_of "$calls")" == "$want" ]]; then ok "$label -> unavailable/$want"
    else no "$label -> expected unavailable/$want, got '${c:-<none>}'/'$(reason_of "$calls")'"; fi
  }
  # HKW1 — the FIRST ssh (the remote bundle dir) meets the changed key.
  hk_row "HKW1: web-1 changed host key on the first ssh" web_1_host_key_mismatch hkw1 HKFAIL=1 PRC=0 PLOG="$READYZ_OK"
  if grep -qxF "$HK_TITLE" "$SCRATCH/calls.hkw1.stdout" && [[ "$(cat "$SCRATCH/calls.hkw1.rc")" == 255 ]]; then
    ok "HKW1: emits '$HK_TITLE' and exits 255"
  else no "HKW1: the host_key_mismatch annotation or rc 255 is missing (rc=$(cat "$SCRATCH/calls.hkw1.rc"))"; fi
  # The raw ssh text (with its forged ::error::) is printed only INSIDE a stop-commands span.
  if awk '/^::stop-commands::/{tok=substr($0,18); inspan=1; next} inspan && $0 == "::" tok "::" {inspan=0; next}
          /forged/ && !inspan {bad=1} /forged/ && inspan {seen=1} END {exit !(seen && !bad)}' "$SCRATCH/calls.hkw1.stdout"; then
    ok "HKW1: the raw ssh stderr is printed inside a ::stop-commands:: span (forged ::error:: inert)"
  else no "HKW1: the raw ssh stderr was not confined to a stop-commands span"; fi
  # HKW2 — the PROBE call meets it (its stderr lands in the merged probe log).
  hk_row "HKW2: changed host key on the probe call (rc 255)" web_1_host_key_mismatch hkw2 PRC=255 PLOG="$PLOG_HK"
  # HKW3 — the phrase mid-line (remote output) on rc 255 is NOT ssh's verdict: still transport.
  hk_row "HKW3: host-key phrase mid-line on rc 255" ssh_transport_failure hkw3 PRC=255 PLOG="banner: Host key verification failed."
  # HKW4 — the text on a non-255 exit is the remote's, not ssh's: never host_key_mismatch.
  c_hkw4=$(CALLS="$SCRATCH/calls.hkw4" PRC=1 PLOG="$PLOG_HK" HEALTH=200 drive)
  if [[ "$(reason_of "$SCRATCH/calls.hkw4")" != web_1_host_key_mismatch && -n "$c_hkw4" ]]; then ok "HKW4: host-key text on rc 1 is not host_key_mismatch"
  else no "HKW4: host-key text on a non-255 exit picked host_key_mismatch"; fi
  # HKW5 — the plain transport failure keeps its own reason (must-PASS for the rc-255 branch).
  hk_row "HKW5: rc 255 with no host-key text" ssh_transport_failure hkw5 PRC=255 PLOG=""

  # MUTATIONS over a copy of the extracted body: each must turn its row RED, i.e. the mutant's
  # outcome_reason must DIFFER from the pristine body's on the same fixture (both are run here, so
  # the comparison cannot drift from the rows above).
  # hk_mutant <name> <sed -E expr> <calls-name> [VAR=value ...]
  hk_mutant() {
    local name="$1" expr="$2" cn="$3"; shift 3
    local m="$SCRATCH/reassert.$name.sh" want got
    sed -E "$expr" "$SCRATCH/reassert.sh" > "$m"
    if cmp -s "$m" "$SCRATCH/reassert.sh"; then no "M-$name: the mutation matched nothing"; return; fi
    # shellcheck disable=SC2163  # "$@" is VAR=value pairs: exporting them IS the intent
    (export "$@"; CALLS="$SCRATCH/calls.$cn-pristine" HEALTH=200 drive) >/dev/null
    # shellcheck disable=SC2163
    (export "$@"; CALLS="$SCRATCH/calls.$cn" REASSERT="$m" HEALTH=200 drive) >/dev/null
    want="$(reason_of "$SCRATCH/calls.$cn-pristine")"; got="$(reason_of "$SCRATCH/calls.$cn")"
    if [[ -n "$want" && "$got" != "$want" ]]; then ok "M-$name: the row goes RED against the mutant ($want -> ${got:-<none>})"
    else no "M-$name: the row stayed GREEN against the mutant (pristine=${want:-<none>} mutant=${got:-<none>})"; fi
  }
  hk_mutant no-probe-verdict '/^host_key_verdict "\$probe_rc" "\$probe_log"$/d' m-hkw2 PRC=255 PLOG="$PLOG_HK"
  hk_mutant no-first-verdict '0,/^host_key_verdict "\$ssh_rc" "\$ssh_err"$/{/^host_key_verdict "\$ssh_rc" "\$ssh_err"$/d}' m-hkw1 HKFAIL=1 PRC=0 PLOG="$READYZ_OK"
  hk_mutant unanchored 's/grep -cE .\^\(Host key/grep -cE '"'"'(Host key/' m-hkw3 PRC=255 PLOG="banner: Host key verification failed."
  hk_mutant no-rc-gate '/^  \[\[ "\$1" -eq 255 \]\] \|\| return 0$/d' m-hkw4 PRC=1 PLOG="$PLOG_HK"

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
  # ANTI-SHADOW CONTROL. Everything above is satisfied by a stub whose read arm never matched:
  # the guard would refuse for the WRONG reason (or not at all) and the assertions could not tell.
  # Assert the arm was REACHED, so a future reformatting of the workflow's read command reds here
  # instead of silently re-opening the shadow that already hid this guard once.
  if grep -q 'STUB_BASELINE_READ' "$lower_calls" 2>/dev/null; then
    ok "the baseline READ arm was actually reached (the stub is not shadowed)"
  else
    no "the stub's baseline READ arm was never reached — the refuse-to-lower assertions above are vacuous"
  fi

  # THE READ MUST FAIL CLOSED. `2>/dev/null || true` used to collapse "no baseline yet" into the
  # same empty string as "I could not read the baseline", and empty short-circuited the guard to
  # ALLOW — so one tunnel blip on the read, during exactly the incident that motivates re-seeding,
  # let a downward re-seed land. The write is a SEPARATE ssh invocation that can succeed after the
  # read failed, so this is not hypothetical.
  readfail_calls="$SCRATCH/calls.seed-read-failed"
  c_readfail=$(EV=workflow_dispatch SEED=5 READRC=255 CALLS="$readfail_calls" PRC=0 PLOG="$READYZ_OK" drive)
  if [[ "$(cat "$readfail_calls.rc" 2>/dev/null || echo 0)" -ne 0 ]]; then
    ok "a seed whose baseline READ failed is refused (cannot seed blind)"
  else
    no "a seed was accepted while the baseline read FAILED — the guard fails open on its own instrument"
  fi
  expect_class "a seed refused for an unreadable baseline classifies as unavailable" "unavailable" "$c_readfail"
  if grep -qF "printf 'WORKSPACES_COUNT=%s" "$readfail_calls" 2>/dev/null; then
    no "a seed WROTE a baseline after its own read failed — the write is a separate ssh and landed anyway"
  else
    ok "a seed whose read failed reached the host with no baseline write"
  fi

  # THE SEED-VALUE GUARD, which had zero fixtures. `0` is the dangerous one and the workflow says
  # why: `count -lt 0` is false for EVERY count, so a zero baseline is an absorbing green a total
  # wipe would pass. The width bound is the same hole one order up — POSIX `[` exits 2 above
  # INT64_MAX and, inside an `if` under `set -uo pipefail` with no `-e`, that reads as "not less
  # than", SKIPPING the comparison entirely.
  for bad in 0 abc -1 08 1e1 99999999999999999999; do
    bad_calls="$SCRATCH/calls.seed-bad-$RANDOM"
    c_bad=$(EV=workflow_dispatch SEED="$bad" CALLS="$bad_calls" PRC=0 PLOG="$READYZ_OK" drive)
    if [[ "$(cat "$bad_calls.rc" 2>/dev/null || echo 0)" -ne 0 ]] \
       && ! grep -qF "printf 'WORKSPACES_COUNT=%s" "$bad_calls" 2>/dev/null; then
      ok "seed '$bad' is refused and writes nothing"
    else
      no "seed '$bad' was ACCEPTED or wrote a baseline — a baseline that cannot fail"
    fi
    # The captured class is an assertion, not an unused variable: a refusal that emitted NO class
    # would leave the alarm unable to distinguish it from a step that never ran.
    expect_class "seed '$bad' refusal emits a class" "unavailable" "$c_bad"
  done

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

  # THE PRODUCER SIDE OF `selftest`. Every other fixture drives this class at the CONSUMER (the
  # alarm body, via CLASS=selftest); nothing drove the producer, so deleting the `ALARM_SELFTEST`
  # branch that EMITS it left the suite fully green while the rehearsal silently classified `pass`
  # — i.e. the self-test would prove the alarm reachable by never reaching it.
  st_calls="$SCRATCH/calls.selftest"
  c_selftest=$(EV=workflow_dispatch SELFTEST=true CALLS="$st_calls" PRC=0 PLOG="$READYZ_OK" drive)
  expect_class "an otherwise-healthy run with alarm_selftest=true classifies as selftest" "selftest" "$c_selftest"

  # (#7376) THE PRODUCER SIDE OF THE `printf | ssh` PIPE. The suite's stub used to exit without reading
  # stdin, so a printf scheduled after the stub had gone took SIGPIPE (rc 141) or, with SIGPIPE ignored as
  # on the CI runner, EPIPE (rc 1); under pipefail that became the probe rc, which is none of 0/3/127/255,
  # so the body classified `unavailable/unparsed` instead of `selftest` (run 37296532619). slow_printf
  # delays ONLY that printf until the stub has begun handling the probe call (a bounded ~5 s hand-off on
  # a sentinel the stub creates), which forces the late-producer ordering instead of hoping for CPU
  # contention. The hand-off is asserted, not assumed: slow_printf records whether it was released by the
  # sentinel or by its timeout, and the rows fail on a timeout. The rows run a REWRITTEN COPY of the
  # extracted production body that differs from it in exactly that one printf line (pinned below), so
  # they prove the STUB's stdin drain, not the production body; the unmutated rows above cover the
  # production body. Both rows run with SIGPIPE ignored, the CI disposition, on every host.
  slow_re="$SCRATCH/reassert.slow.sh"; slow_body="$SCRATCH/reassert.slowbody.sh"
  sed -E "s/^([[:space:]]*)printf 'DOPPLER_TOKEN/\1slow_printf 'DOPPLER_TOKEN/" "$SCRATCH/reassert.sh" > "$slow_body"
  {
    cat <<'EOS'
slow_printf() {
  local i=0
  while [[ ! -e "${PROBE_SENTINEL:-/nonexistent}" && "$i" -lt 100 ]]; do sleep 0.05; i=$((i + 1)); done
  # Record WHY the wait ended: a timeout means the hand-off never happened, which the rows below
  # turn into a failure instead of a silently weaker (timing-only) test.
  # Only when the path is set: an unset one must not turn into `/dev/null.released` (a write outside the
  # scratch dir when run as root); the rows then fail on the missing record, which is the loud outcome.
  if [[ -n "${PROBE_SENTINEL:-}" ]]; then
    if [[ -e "$PROBE_SENTINEL" ]]; then echo sentinel; else echo timeout; fi > "$PROBE_SENTINEL.released"
  fi
  # shellcheck disable=SC2059  # a transparent wrapper: the caller owns the format string
  printf "$@"
}
EOS
    cat "$slow_body"
  } > "$slow_re"
  slow_sites=$(grep -c "^slow_printf 'DOPPLER_TOKEN" "$slow_re" || true)
  # `diff` prints one `<` and one `>` per changed line: exactly one line may differ from production.
  slow_changed=$(diff "$SCRATCH/reassert.sh" "$slow_body" | grep -c '^[<>]' || true)
  if [[ "$slow_sites" == 1 && "$slow_changed" == 2 ]]; then
    ok "RACE: the producer-delay rewrite landed on exactly the one printf call site and changed nothing else"
  else
    no "RACE: the producer-delay rewrite did not land once (sites=$slow_sites changed_diff_lines=$slow_changed, want 1 and 2) — the race rows below would measure nothing"
  fi
  sp_calls="$SCRATCH/calls.slowprod"
  c_slow=$( (trap '' PIPE; EV=workflow_dispatch SELFTEST=true CALLS="$sp_calls" REASSERT="$slow_re" PRC=0 PLOG="$READYZ_OK" drive) )
  expect_class "RACE: a producer delayed past the stub's start still classifies selftest (the stub drains stdin)" "selftest" "$c_slow"
  # The row above cannot tell a drained stub from one that merely exits inside the poll window, so
  # assert the .env text actually ARRIVED, and that the hand-off was the sentinel and not the timeout.
  if grep -q '^DOPPLER_TOKEN=' "$sp_calls.probe-stdin" 2>/dev/null; then
    ok "RACE: the draining stub received the .env text the workflow piped to it"
  else
    no "RACE: the stub did not receive the piped .env text — it exited without reading stdin, so the row above is timing luck"
  fi
  if [[ "$(cat "$sp_calls.sentinel.released" 2>/dev/null)" == sentinel ]]; then
    ok "RACE: the late producer was released by the stub's sentinel (the hand-off happened)"
  else
    no "RACE: the late producer was released by its timeout, not the sentinel — the hand-off never happened, so the ordering was not forced"
  fi
  nd_calls="$SCRATCH/calls.nodrain"
  c_nodrain=$( (trap '' PIPE; EV=workflow_dispatch SELFTEST=true CALLS="$nd_calls" REASSERT="$slow_re" NODRAIN=1 PRC=0 PLOG="$READYZ_OK" drive) )
  nd_probe_rc="$(sed -n 's/^luks-monitor probe rc=//p' "$nd_calls.stdout" | tail -1)"
  if [[ "$c_nodrain" == unavailable && "$(reason_of "$nd_calls")" == unparsed \
        && "$nd_probe_rc" =~ ^[0-9]+$ && ! "$nd_probe_rc" =~ ^(0|3|127|255)$ \
        && "$(cat "$nd_calls.sentinel.released" 2>/dev/null)" == sentinel ]]; then
    ok "RACE CONTROL: the same late producer against a stub that never reads stdin fails (probe rc=$nd_probe_rc, unavailable/unparsed, released by sentinel)"
  else
    no "RACE CONTROL: the non-draining stub did not reproduce the failure (class=${c_nodrain:-<none>} reason=$(reason_of "$nd_calls") probe_rc=${nd_probe_rc:-<none>} released=$(cat "$nd_calls.sentinel.released" 2>/dev/null || echo none)) — the race rows above cannot fail"
  fi

  # `outcome_reason` PRODUCED, not just consumed. Every alarm fixture supplies RSN= at the consumer,
  # so deleting the reason printf from emit_class left the suite green while every alarm carried
  # reason=unknown — which makes the anti-spam bound compare unknown to unknown forever and swallow
  # a genuine escalation, the exact failure its own positive control exists to rule out.
  reason_out="$SCRATCH/calls.reason-produced.out"
  RSNCALLS="$SCRATCH/calls.reason-produced"
  _=$(CALLS="$RSNCALLS" PRC=1 PLOG='[luks-monitor] FAIL (mount_not_mapper) src=/dev/sdb' drive)
  if grep -q '^outcome_reason=mount_not_mapper$' "$reason_out" 2>/dev/null; then
    ok "emit_class PRODUCES outcome_reason alongside outcome_class"
  else
    no "outcome_reason was not emitted — every alarm would read reason=unknown and the anti-spam bound would swallow real escalations"
  fi

  # --- non-vacuity floor over the class space ----------------------------------------------------
  # Reads the classes produced by fixtures that are NOT individually pinned above, so it is a real
  # floor rather than a tautology. (The earlier form read four values each already asserted three
  # lines above it, so it could not fail while those passed.)
  produced=$(printf '%s\n' "$c_pass" "$c_drift" "$c_short" "$c_basemiss" "$c_selftest" "$c_rc2" \
    | sort -u | grep -c '[a-z]' || true)
  if [[ "$produced" -ge 5 ]]; then
    ok "the fixture set produced all five non-empty outcome classes (pass/drift/readiness/unavailable/selftest)"
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
# CAPTURE THE BODY, not just the argv. The issue BODY is built by a SECOND `case "$class"`, so the
# class can be corrupted in a way that leaves title and labels untouched and only the body wrong —
# e.g. the fail-closed `*)` arm set to `drift`, which files "could not verify — nothing proven"
# carrying the Article 32 legal-escalation paragraph. Title/label assertions cannot see that.
_prev=""
for _a in "$@"; do
  [[ "$_prev" == "--body-file" && -f "$_a" ]] && cat "$_a" > "${GH_BODY_CAPTURE:-/dev/null}"
  _prev="$_a"
done
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
    : > "$calls"; : > "$SCRATCH/gh.body"
    PATH="$SCRATCH/bin:$PATH" GH_CALLS="$calls" GH_BODY_CAPTURE="$SCRATCH/gh.body" \
    OUTCOME_CLASS="${CLASS:-}" REASON="${RSN:-none}" \
    FIXTURE_ISSUE_LIST="${LIST:-[]}" FIXTURE_ISSUE_VIEW="${VIEW:-}" \
    RUN_URL="https://example.invalid/run/1" GH_TOKEN="fixture" \
      bash -e "$SCRATCH/alarm.sh" >/dev/null 2>&1 </dev/null || rc=$?
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
  # if/else, not `A && ok || no`: under that form a failure in `ok` itself also runs `no`, which
  # would double-count and report a passing case as failed (SC2015).
  if grep -q 'label create' "$LAST_GH" 2>/dev/null; then
    ok "the alarm creates its label idempotently before filing"
  else
    no "the alarm never ran gh label create — a first fire on a fresh repo would fail"
  fi
  if grep -q 'issue list' "$LAST_GH" 2>/dev/null; then
    ok "the alarm QUERIES for an existing issue before creating (dedupe, not spam)"
  else
    no "the alarm creates without querying — every scheduled failure would open a new issue"
  fi
  # EVERY label the run will apply must be created, not just the umbrella one: `gh issue create`
  # exits non-zero on a `--label` naming a label that does not exist, and on this step that means
  # the alarm files NOTHING after classifying correctly.
  if [[ "$(grep -c 'label create' "$LAST_GH" 2>/dev/null || echo 0)" -ge 2 ]]; then
    ok "the alarm creates EVERY label it will apply (umbrella + class label), not just the first"
  else
    no "the alarm created fewer labels than it applies — a missing label makes gh issue create exit non-zero and file nothing"
  fi

  # Extract the TITLE ONLY. Grepping the whole `issue create` argv would compare strings that
  # include a per-run mktemp path, so the distinctness check below would pass even if every class
  # produced an identical title — the exact vacuity this assertion exists to rule out.
  # BOTH `.*` were greedy, so the capture ran to the LAST ` --label` and returned title PLUS
  # all-but-one label. The distinctness check below was then carried by the differing LABEL sets,
  # not by the titles — two classes could share a title and still count as distinct, which is the
  # exact vacuity the comment above says this extraction exists to rule out. Terminate on the
  # FIRST ` --label` instead.
  # `sed -n 1p` rather than `head -1`: under pipefail a reader that exits early (head) can SIGPIPE the
  # writer and abort this `set -e` suite when a log holds two or more --title lines (#7376 class).
  title_of() { sed -n 's/.*--title \(.*\)/\1/p' "$1" | sed -n 1p | sed 's/ --label.*//'; }

  # AC9d — SEVERITY ROUTING, which had ZERO assertions (the suite contained no occurrence of
  # `p0-critical` or `p1-high` at all). The contract is that the p0 goes where the USER DATA is, so
  # both `drift` and a `workspace_count_shortfall` carry p0-critical while other readiness reasons
  # carry p1-high. And because `labels` is consumed only by `gh issue create`, a shortfall that
  # dedupes onto an already-open readiness issue would take the comment path and never receive its
  # p0 — which is why the shortfall now has its own TITLE, asserted below.
  labels_of() { tr ' ' '\n' < "$1" | grep -A1 -- '--label' | grep -v -- '--label\|^--$' | sort -u | tr '\n' ' '; }

  CLASS=drift RSN=blkid_not_luks alarm_drive
  case "$(labels_of "$LAST_GH")" in
    *priority/p0-critical*) ok "drift carries priority/p0-critical" ;;
    *) no "drift did not carry priority/p0-critical (got: $(labels_of "$LAST_GH"))" ;;
  esac
  case "$(labels_of "$LAST_GH")" in
    *type/security*) ok "drift carries type/security (it is the claim-integrity class)" ;;
    *) no "drift did not carry type/security" ;;
  esac

  CLASS=readiness RSN=workspace_count_shortfall alarm_drive
  sf_title=$(title_of "$LAST_GH")
  case "$(labels_of "$LAST_GH")" in
    *priority/p0-critical*) ok "workspace_count_shortfall carries priority/p0-critical (irreversible sole-copy data loss)" ;;
    *) no "workspace_count_shortfall did NOT carry priority/p0-critical — data loss filed as a capacity fault (got: $(labels_of "$LAST_GH"))" ;;
  esac

  CLASS=readiness RSN=readyz_not_ready alarm_drive
  nr_title=$(title_of "$LAST_GH")
  case "$(labels_of "$LAST_GH")" in
    *priority/p1-high*) ok "a non-shortfall readiness reason carries priority/p1-high" ;;
    *) no "a non-shortfall readiness reason did not carry priority/p1-high" ;;
  esac
  # THE DEDUPE-DEMOTION GUARD. Same title for both readiness reasons meant severity rode a key it
  # did not own: whichever arrived FIRST created the issue, and the second only ever commented.
  if [[ -n "$sf_title" && "$sf_title" != "$nr_title" ]]; then
    ok "workspace_count_shortfall files under its OWN title, so a standing p1 readiness issue cannot demote it"
  else
    no "shortfall and readyz_not_ready share a title ('$sf_title') — the p0 is lost whenever the p1 issue is already open"
  fi

  # LABEL DISTINGUISHABILITY. `readiness`-other and `unavailable` used to carry byte-identical label
  # sets, so an agent triaging by label alone could not tell "the app cannot serve from the volume,
  # act now" from "nothing was proven, do NOT start a data-recovery procedure".
  CLASS=unavailable RSN=ssh_transport alarm_drive
  if [[ "$(labels_of "$LAST_GH")" != "$(CLASS=readiness RSN=readyz_not_ready alarm_drive; labels_of "$LAST_GH")" ]]; then
    ok "unavailable and readiness-other are distinguishable by LABEL alone (not only by title prose)"
  else
    no "unavailable and readiness carry identical labels — the class is unrecoverable from gh issue list --json labels"
  fi

  CLASS=drift RSN=blkid_not_luks alarm_drive
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
  e_body=$(cat "$SCRATCH/gh.body" 2>/dev/null || true)
  if [[ -n "$u_title" && "$e_title" == "$u_title" ]]; then
    ok "an EMPTY outcome_class fails closed to the same issue as unavailable"
  else
    no "an empty outcome_class filed '${e_title:-<nothing>}' but unavailable files '${u_title:-<nothing>}' — the fail-closed default is missing or routes elsewhere"
  fi
  # THE BODY, not just the title. The routing `case` and the BODY `case` are separate statements
  # keyed on the same variable, so setting the fail-closed arm's class to `drift` leaves the title
  # and labels of "could not verify — nothing proven" intact while the body gains the Article 32
  # legal-escalation paragraph. A dead SSH bridge would then file a claim-is-false finding. Assert
  # the class-specific prose, which is the only surface that moves.
  case "$e_body" in
    *"Nothing was proven, in either direction"*)
      ok "the empty-class body carries the 'nothing was proven' section" ;;
    *) no "the empty-class body is missing the 'nothing was proven' section (got: $(printf '%s' "$e_body" | head -c 80))" ;;
  esac
  case "$e_body" in
    *"Legal consequence"*|*"Article 32 claim is FALSE"*)
      no "an empty outcome_class filed a body asserting the Article 32 claim is FALSE — a dead bridge is not an at-rest finding" ;;
    *) ok "the empty-class body does NOT assert a legal consequence" ;;
  esac
  # And the positive control for that pair: the drift body MUST carry the legal paragraph, or the
  # assertion above is satisfied by a body template that lost it for every class.
  CLASS=drift RSN=blkid_not_luks alarm_drive
  case "$(cat "$SCRATCH/gh.body" 2>/dev/null || true)" in
    *"Legal consequence"*) ok "POSITIVE CONTROL: the drift body DOES carry the counsel re-evaluation trigger" ;;
    *) no "the drift body lost its legal-consequence section — the PR's stated justification is gone" ;;
  esac

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

# =====================================================================================================
# GUARD 3 — the web-2 soak-marker writer fails closed (#6931, ADR-143 R3).
#
# PROPERTY. WORKSPACES_LUKS_CUTOVER_AT exists in its Doppler config only while web-2's newest probe row is
# fresh and reports a LUKS-backed mount with an off-host header copy (and, to EARN it, a green readiness row
# the probe row is not older than: an INSTANCE-level join on AGE, plus the readiness row's luks_arm being formatted
# or opened (w2l_ready_arm; `noop` is refused). No reboot is required (owner decision 2026-10-07, ADR-263 addendum 2026-10-08),
# so the boot_ids of the two rows are not compared); negative evidence removes it, and a FAILED QUERY (or a
# Doppler fault) leaves it untouched.
#
# ASSEMBLY. (1) the `web2_marker` job, parsed with PyYAML: its job-level `if:`, permissions, the issue step,
# the Sentry check-in and its monitor are all EVALUATED over a grid, not grepped; (2) the job's marker step,
# EXTRACTED and EXECUTED under the runner's own shell (`bash --noprofile --norc -eo pipefail`) against a
# `doppler` and a `curl` stub that REFUSE every request they were not taught (exit 64) — the
# registry-host-replace-dispatch-verdict.test.sh precedent — through a REGISTERED battery of scenarios (the id
# set is asserted exactly, each scenario is its own assertion, and each asserts the outcome class and RED
# reason the step reported, not just its exit code); (3) a census of every file in the tree that names the
# key, outside an allow-list of the one writer and its read-only users; (4) lb-weight-gate.sh's READ of the
# same name, and that the format written is one the gate parses.
#
# MUTATION MATRIX (each row is applied to a sandbox copy of the code under test and MUST turn the battery
# RED; a mutation that lands nothing is itself a failure — a row that scored the baseline proves nothing):
#   1 write on a stale row (>26h)         2 write on luks=0 / a non-crypto_LUKS backing / a wrong mount source
#   3 skip the delete on negative evidence   4 write every run (overwrites the first-green start)
#   5 a writer anywhere in the tree (planted files; harmless variants stay green)
#   6 empty/unparseable body treated as a query failure   7 a failed query deletes the key, or the run passes
#   8 drop an escrow=ok requirement   9 the instance-level join (probe not older than readiness) dropped,
#   earning without a green readiness row, keeping that demands one, a rebirth not noticed on a kept marker
#   10 HARNESS: the doppler stub records nothing   11 MUST-PASS: an unknown extra field + a 25h age is GREEN
#   12-13 the not-live exemption widened / removed   14 host/ident/unit re-check dropped
#   15 a readiness predicate (ready, stage, unit, host) dropped   16 boot_id unknown crashes the judge
#   17 doppler set failure / read-back / token shape / read fault ignored   18 emit() a no-op
#   19 structural: job-level if, permissions, persisted credentials, check-in gates, slug typo
# =====================================================================================================
G3="$SCRATCH/g3"
mkdir -p "$G3/fx" "$G3/st"
G3_TF="apps/web-platform/infra/sentry/cron-monitors.tf"

# g3_sub <file> <old> <new> — replace exactly one occurrence; rc 1 when it did not land exactly once
"${G3_PYTHON:-/usr/bin/python3}" -c 'import yaml' 2>/dev/null || G3_PYTHON=python3
g3_sub() {
  "${G3_PYTHON:-/usr/bin/python3}" - "$1" "$2" "$3" <<'PY'
import sys
p, old, new = sys.argv[1:4]
s = open(p).read()
if s.count(old) != 1:
    sys.exit(1)
open(p, "w").write(s.replace(old, new))
PY
}

# --- structural, parsed as YAML; also extracts the step body ----------------------------------------
cat > "$G3/g3_struct_check.py" <<'PY'
import sys, yaml, re, itertools
wfp, out, tfp = sys.argv[1:4]
wf = yaml.safe_load(open(wfp))
rows = []
def check(name, cond, detail=""):
    d = str(detail)[:200].replace("\t", " ").replace("\n", " ").replace("\r", " ")
    rows.append(("ok" if cond else "FAIL", name.replace("\t", " "), d))

# A small evaluator for the subset of GitHub expressions the web2_marker job uses. It fails CLOSED: a token it
# was not taught (a status function, a context path nobody translated, a numeric comparison) raises.
SUBS = [("steps.marker.outputs.outcome", "MCLASS"), ("steps.marker.outcome", "MOUT"), ("github.event_name", "EVENT"),
        ("github.ref", "REF"), ("always()", "True"), ("&&", " and "), ("||", " or ")]
def ev(expr, **ctx):
    e = str(expr).strip()
    if e.startswith("${{"): e = e[3:]
    if e.endswith("}}"): e = e[:-2]
    if re.search(r"(==|!=)\s*-?\d", e): raise ValueError("numeric literal comparison")
    e = " ".join(e.split())
    for a, b in SUBS: e = e.replace(a, b)
    m = re.search(r"[A-Za-z_][A-Za-z_0-9]*\.[A-Za-z_]", e)
    if m: raise ValueError("untranslated context reference: " + m.group(0))
    return eval(e, {"__builtins__": {}}, ctx)  # noqa: S307 - fixed grammar, repo-controlled input

jobs = wf.get("jobs") or {}
job = jobs.get("web2_marker") or {}
check("G3 the web2_marker job exists", bool(job), sorted(jobs))
steps = job.get("steps") or []
marker = [s for s in steps if s.get("id") == "marker"]
check("G3 the marker step carries id: marker", len(marker) == 1, [s.get("name") for s in steps])
body = (marker[0].get("run") if marker else "") or ""
open(f"{out}/marker.sh", "w").write(body)
env = (marker[0].get("env") if marker else {}) or {}
alltext = " ".join(str(s.get("run", "")) + " " + str(s.get("uses", "")) for s in steps)
on = wf.get(True) or wf.get("on") or {}
cron = ((on.get("schedule") or [{}])[0] or {}).get("cron")

# (1) the job only ever runs with the write token on the default branch
jif = job.get("if")
check("G3 the job has a job-level if: (a dispatch from another ref must never run with the write token)", jif is not None, jif)
if jif is None:
    # keep the row count identical for a mutant that removes the if: (the mutation row compares row counts)
    check("G3 job if: evaluated over event x ref runs on a schedule and on a dispatch from refs/heads/main ONLY", False, "no job-level if")
else:
    wrong = []
    for e, ref in itertools.product(["schedule", "workflow_dispatch", "push"], ["refs/heads/main", "refs/heads/feature", "refs/heads/main-evil", "refs/tags/main", ""]):
        want = e == "schedule" or ref == "refs/heads/main"
        try:
            got = bool(ev(jif, EVENT=e, REF=ref))
        except Exception as exc:  # noqa: BLE001
            wrong.append(repr(exc)); break
        if got != want: wrong.append(f"{e}/{ref or 'EMPTY'}: ran={got} want={want}")
    check("G3 job if: evaluated over event x ref runs on a schedule and on a dispatch from refs/heads/main ONLY",
          not wrong, "; ".join(wrong[:3]) or "15 cells correct")
check("G3 the marker step is not continue-on-error (a failed run must be red)", not (marker[0].get("continue-on-error") if marker else True))
check("G3 the job declares a timeout", isinstance(job.get("timeout-minutes"), int), job.get("timeout-minutes"))
check("G3 the job holds contents: read and issues: write only (the issue step needs nothing else)",
      (job.get("permissions") or {}) == {"contents": "read", "issues": "write"}, job.get("permissions"))
co = [s for s in steps if str(s.get("uses", "")).startswith("actions/checkout@")]
check("G3 the checkout does not persist credentials (the sourced repo scripts run beside a live write token)",
      len(co) == 1 and (co[0].get("with") or {}).get("persist-credentials") is False, [c.get("with") for c in co])
check("G3 NO SSH leg: no bridge action and no WEB_HOST_SSH in the job",
      "cf-tunnel-ssh-bridge" not in alltext and "WEB_HOST_SSH" not in alltext and not re.search(r"\bssh\b", " ".join(str(s.get("run", "")) for s in steps)),
      "")
check("G3 no step name contains 'alarm' (the verify suite extracts its alarm body by that word, across every job)",
      not any("alarm" in str(s.get("name", "")).lower() for s in steps), [s.get("name") for s in steps])
check("G3 the write token comes from the dedicated secret and is the doppler CLI's DOPPLER_TOKEN env",
      env.get("DOPPLER_TOKEN") == "${{ secrets.DOPPLER_TOKEN_WORKSPACES_LUKS_MARKER }}", env.get("DOPPLER_TOKEN"))
check("G3 the Better Stack read credentials come from repo secrets, all three",
      all(env.get(k) == "${{ secrets.%s }}" % k for k in ("BETTERSTACK_QUERY_HOST", "BETTERSTACK_QUERY_USERNAME", "BETTERSTACK_QUERY_PASSWORD")), sorted(env))
check("G3 no ${{ }} inside the marker run body (a context value in run: is shell injection)", "${{" not in body, "")
check("G3 xtrace is refused on the credential-bearing step",
      bool(re.search(r"case \"\$-\" in \*x\*\)[^\n]*exit 78", body)), "")
check("G3 no token on any command line: no `DOPPLER_TOKEN=` assignment and no --token flag in the body",
      "DOPPLER_TOKEN=" not in body and "--token" not in body, "")
check("G3 the Doppler write and delete discard the CLI's stdout (it prints every remaining secret)",
      bool(re.search(r"doppler_call secrets set [^\n]*>/dev/null", body)) and bool(re.search(r"doppler_call secrets delete [^\n]*>/dev/null", body)), "")
check("G3 the marker is written only through the dedicated config (-c via W2L_MARKER_CONFIG), never prd",
      '-c "$W2L_MARKER_CONFIG"' in body and not re.search(r"-c\s+prd\b|--config\s+prd\b", body), "")
check("G3 write-if-absent is by a read of the key, never an unconditional set",
      bool(re.search(r'doppler_call secrets get "\$W2L_MARKER_NAME" --plain', body)), "")
check("G3 doppler_call() is defined exactly once and carries the redact + [doppler-stderr] prefix (#9613)",
      body.count("doppler_call()") == 1 and '[REDACTED-DOPPLER-TOKEN]' in body and '[doppler-stderr] ' in body, "")
check("G3 every secrets call routes through doppler_call — no bare `doppler secrets` remains (#9613)",
      not re.search(r'(?<!_)\bdoppler\s+secrets\b', body),
      [l.strip() for l in body.split("\n") if re.search(r'(?<!_)\bdoppler\s+secrets\b', l)][:2])
check("G3 the timestamp is ISO-8601 UTC", "date -u +%Y-%m-%dT%H:%M:%SZ" in body, "")

# (2) the alarm: one issue step, evaluated over the outcome x class x event grid
issue = [s for s in steps if "web-2 marker issue" in str(s.get("name", ""))]
check("G3 exactly one issue step exists", len(issue) == 1, [s.get("name") for s in steps])
OK_CLASSES = ("green", "not_live")
open(f"{out}/issue.sh", "w").write((issue[0].get("run") if issue else "") or "")
if issue:
    icond = str(issue[0].get("if", ""))
    check("G3 issue if: contains always() (without it GitHub ANDs an implicit success())", "always()" in icond, icond)
    check("G3 the issue step is not continue-on-error (that would make every alarm advisory)", not issue[0].get("continue-on-error"))
    check("G3 the issue step reads the marker step's outputs through step env, never inline in the run body",
          "${{" not in str(issue[0].get("run", "")) and "steps.marker.outputs.outcome" in str((issue[0].get("env") or {}).get("OUTCOME", "")), "")
    try:
        wrong = []
        for e, o, c in itertools.product(["schedule", "workflow_dispatch"], ["success", "failure", "skipped", "cancelled"],
                                         ["green", "not_live", "red", "red_delete_failed", "query_failed", ""]):
            fired = bool(ev(icond, EVENT=e, MOUT=o, MCLASS=c, REF="refs/heads/main"))
            want = e == "schedule" and not (o == "success" and c in OK_CLASSES)
            if fired != want: wrong.append(f"{e}/{o}/{c or 'EMPTY'}: fired={fired} want={want}")
        check("G3 issue if: fires on a scheduled run unless the marker step SUCCEEDED with green/not_live (an empty class alarms), never on a dispatch",
              not wrong, "; ".join(wrong[:3]) or "48 cells correct")
    except Exception as exc:  # noqa: BLE001
        check("G3 issue if: is evaluable", False, repr(exc))

# (3) the liveness check-in and its monitor
hbs = [s for s in steps if "sentry-heartbeat" in str(s.get("uses", ""))]
check("G3 exactly one Sentry check-in step exists", len(hbs) == 1, [s.get("name") for s in steps])
if hbs:
    hb = hbs[0]
    hcond = str(hb.get("if", ""))
    check("G3 the check-in is the LAST step of the job (no earlier step can leave it unreached)", bool(steps) and steps[-1] is hb, [s.get("name") for s in steps][-2:])
    check("G3 the check-in is continue-on-error (a monitor outage must not red the run)", bool(hb.get("continue-on-error")))
    check("G3 the check-in if: contains always()", "always()" in hcond, hcond)
    status = str((hb.get("with") or {}).get("status", ""))
    try:
        wrong, forged = [], []
        for o, c in itertools.product(["success", "failure", "skipped", "cancelled"], ["green", "not_live", "red", "red_delete_failed", "query_failed", ""]):
            want = "ok" if (o == "success" and c in OK_CLASSES) else "error"
            got = ev(status, MOUT=o, MCLASS=c, EVENT="schedule", REF="refs/heads/main")
            if got != want: wrong.append(f"{o}/{c or 'EMPTY'}: got={got!r} want={want!r}")
        for e in ("workflow_dispatch", "push"):
            if ev(hcond, EVENT=e, REF="refs/heads/main"): forged.append(e)
        if not ev(hcond, EVENT="schedule", REF="refs/heads/main"): forged.append("schedule suppressed")
        check("G3 check-in status gates POSITIVELY: 'ok' ONLY on (success, green|not_live), 'error' everywhere else",
              not wrong, "; ".join(wrong[:3]) or "24 cells correct")
        check("G3 check-in if: runs on a schedule and NEVER on a dispatch (a dispatch must not forge liveness)",
              not forged, ", ".join(forged) or "schedule only")
        # exact complement of the issue step's condition over the scheduled grid
        if issue:
            split = []
            for o, c in itertools.product(["success", "failure", "skipped", "cancelled"], ["green", "not_live", "red", "red_delete_failed", "query_failed", ""]):
                fired = bool(ev(str(issue[0].get("if", "")), EVENT="schedule", MOUT=o, MCLASS=c, REF="refs/heads/main"))
                if fired != (ev(status, MOUT=o, MCLASS=c, EVENT="schedule", REF="refs/heads/main") == "error"): split.append(f"{o}/{c or 'EMPTY'}")
            check("G3 the issue condition and the check-in status are exact complements over the scheduled grid", not split, ", ".join(split[:4]) or "24 cells agree")
    except Exception as exc:  # noqa: BLE001
        check("G3 check-in expressions are evaluable", False, repr(exc))
    slug = (hb.get("with") or {}).get("monitor-slug")
    try:
        tf = open(tfp).read()
        blk = re.search(r'^resource\s+"sentry_cron_monitor"\s+"workspaces_luks_verify_web2"\s*\{(.*?)^\}', tf, re.S | re.M)
        check("G3 a sentry_cron_monitor resource block for workspaces_luks_verify_web2 exists", bool(blk))
        if blk:
            nm = re.search(r'\bname\s*=\s*"([^"]+)"', blk.group(1)); ct = re.search(r'crontab\s*=\s*"([^"]+)"', blk.group(1))
            check("G3 the check-in's monitor-slug equals the terraform monitor name (a typo'd slug pages 'missed check-in' forever)",
                  bool(nm) and slug == nm.group(1), f"wf={slug!r} tf={nm.group(1) if nm else None!r}")
            check("G3 the monitor crontab equals the workflow cron", bool(ct) and str(cron).strip() == ct.group(1).strip(), f"wf={cron} tf={ct.group(1) if ct else None}")
    except FileNotFoundError:
        check("G3 cron-monitors.tf is readable", False, "not found")
for r in rows:
    print("\t".join(r))
PY
g3_struct() { "${G3_PYTHON:-/usr/bin/python3}" "$G3/g3_struct_check.py" "$1" "$2" "$G3_TF"; }
g3_struct "$WF" "$G3" > "$G3/verdicts.tsv"
g3_struct_rows="$(wc -l < "$G3/verdicts.tsv")"
while IFS=$'\t' read -r verdict name detail; do
  if [[ "$verdict" == "ok" ]]; then ok "$name"; else no "$name${detail:+ ($detail)}"; fi
done < "$G3/verdicts.tsv"

# MUTATION ROW 19 — the structural guards, each against a mutated COPY of the workflow: the mutant must still
# yield every row (not crash) and at least one FAIL row.
g3_smut() { # <label> <old> <new>
  local label="$1" old="$2" new="$3" f="$G3/st/wf-mut.yml" n bad
  cp "$WF" "$f"
  if ! g3_sub "$f" "$old" "$new"; then no "G3 mutation 19 ($label): the edit did not land exactly once in the workflow (a row that scored the baseline proves nothing)"; return; fi
  rm -f "$G3/st/rows.tsv"
  g3_struct "$f" "$G3/st" > "$G3/st/rows.tsv" 2>/dev/null || true
  n="$(wc -l < "$G3/st/rows.tsv")"; bad="$(grep -c '^FAIL' "$G3/st/rows.tsv" || true)"
  if [[ "$n" -ge "$g3_struct_rows" && "$bad" -ge 1 ]]; then ok "G3 mutation 19 ($label) -> RED ($bad structural row(s))"; else no "G3 mutation 19 ($label): rows=$n (want >=$g3_struct_rows) FAIL rows=$bad — the structural guards cannot see this defect"; fi
}
g3_smut "job-level if removed" $'    if: ${{ github.event_name == \'schedule\' || github.ref == \'refs/heads/main\' }}\n    runs-on: ubuntu-24.04\n    timeout-minutes: 10' $'    runs-on: ubuntu-24.04\n    timeout-minutes: 10'
g3_smut "job-level if widened to any ref" "|| github.ref == 'refs/heads/main' }}
    runs-on: ubuntu-24.04
    timeout-minutes: 10" "|| github.ref != '' }}
    runs-on: ubuntu-24.04
    timeout-minutes: 10"
g3_smut "issues: write removed from the job" $'      issues: write\n    steps:\n      - uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4.3.1\n        with:\n          # No git' $'    steps:\n      - uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4.3.1\n        with:\n          # No git'
g3_smut "persist-credentials: false removed" $'          persist-credentials: false\n\n      - name: Install Doppler CLI\n        uses: DopplerHQ/cli-action@5351693ec144fc7f7a2d30025061acfc3c53c47c # v4\n\n      - name: Judge web-2' $'\n      - name: Install Doppler CLI\n        uses: DopplerHQ/cli-action@5351693ec144fc7f7a2d30025061acfc3c53c47c # v4\n\n      - name: Judge web-2'
g3_smut "issue if: negative gate (== 'failure') instead of the negation of success" "steps.marker.outcome != 'success'
                  ||" "steps.marker.outcome == 'failure'
                  ||"
g3_smut "check-in not schedule-gated" "if: always() && github.event_name == 'schedule'
        continue-on-error: true
        uses: ./.github/actions/sentry-heartbeat
        with:
          monitor-slug: workspaces-luks-verify-web2" "if: always()
        continue-on-error: true
        uses: ./.github/actions/sentry-heartbeat
        with:
          monitor-slug: workspaces-luks-verify-web2"
g3_smut "check-in slug typo" "monitor-slug: workspaces-luks-verify-web2" "monitor-slug: workspaces-luks-verify-web3"
g3_smut "check-in status gates on a negative literal" "steps.marker.outputs.outcome == 'green' || steps.marker.outputs.outcome == 'not_live'" "steps.marker.outputs.outcome != 'red'"

if [[ ! -s "$G3/marker.sh" ]]; then
  no "G3 could not extract the web2_marker step body — every Guard 3 behavioural row below would be vacuous"
else
  if bash -n "$G3/marker.sh" 2>/dev/null; then ok "G3 the web2_marker body passes bash -n"; else no "G3 the web2_marker body fails bash -n"; fi

  G3_UUID_A=11111111-2222-3333-4444-555555555555
  G3_UUID_B=66666666-7777-8888-9999-aaaaaaaaaaaa
  G3_MARKER_PRIOR=2026-09-27T00:00:00Z
  G3_ISO_RE='^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$'

  # --- fixtures: synthesized rows in the shape the query returns (JSONEachRow, age_s server-computed) ----
  # Each probe fixture carries BOTH journal copies of the line (the logger copy, and the unit's stdout copy,
  # which is prefixed `[luks-monitor] `), exactly as a real run produces them.
  g3_row() { jq -cn --arg age "$1" --arg m "$2" --arg h "${3:-soleur-web-2}" --arg i "${4:-luks-monitor}" --arg u "${5-luks-monitor.service}" \
    '{dt: "2026-10-01 04:41:00.000", age_s: $age, message: $m, host_name: $h, ident: $i} + (if $u == "" then {} else {unit: $u} end)'; }
  g3_probe() { # age device mount escrow boot [extra] -> both copies
    local m="OK: /mnt/data is LUKS-backed (device_type=$2 mount_source=$3 escrow=$4 header=readable boot_id=$5${6:+ $6})"
    g3_row "$1" "$m"; g3_row "$(( $1 + 1 ))" "[luks-monitor] $m"
  }
  g3_ready() { # age luks escrow boot [ready] [arm] [KEY=VAL overrides...]
    local age="$1" luks="$2" escrow="$3" boot="$4" ready="${5:-1}" arm="${6:-formatted}" m kv; shift 6 2>/dev/null || shift $#
    declare -A f=([ready]="$ready" [stage]=cloud_init_complete [token]=1 [vector]=1 [volume]=1 [luks]="$luks" [luks_arm]="$arm" [escrow]="$escrow" [boot_id]="$boot" [host]=soleur-web-2 [reason]=none [boot_window_s]=900)
    for kv in "$@"; do f[${kv%%=*}]="${kv#*=}"; done
    m="SOLEUR_FRESH_BOOT_READY"
    for k in ready stage token vector volume luks luks_arm escrow boot_id host reason boot_window_s; do m="$m $k=${f[$k]}"; done
    jq -cn --arg age "$age" --arg m "$m" '{dt: "2026-09-28 04:00:00.000", age_s: $age, message: $m}'
  }
  FX="$G3/fx"
  LUKS=crypto_LUKS; MAP=/dev/mapper/workspaces
  g3_probe 3600 $LUKS $MAP ok $G3_UUID_A > "$FX/p_ok"
  g3_probe 90000 $LUKS $MAP ok $G3_UUID_A "x_new_field=1" > "$FX/p_extra25h"
  g3_probe 97200 $LUKS $MAP ok $G3_UUID_A > "$FX/p_stale27h"
  g3_probe 3600 ext4 $MAP ok $G3_UUID_A > "$FX/p_ext4"
  g3_probe 3600 $LUKS /dev/sdb ok $G3_UUID_A > "$FX/p_mount"
  g3_probe 3600 $LUKS $MAP missing $G3_UUID_A > "$FX/p_escrow"
  g3_probe 3600 $LUKS $MAP ok $G3_UUID_A "escrow=ok" > "$FX/p_dupkey"
  { g3_row 100 "FAIL (device_not_luks): device_type=ext4 mount_source=/dev/sdb mapper_present=no"; g3_probe 90000 $LUKS $MAP ok $G3_UUID_A; } > "$FX/p_failnewest"
  { g3_probe 3600 $LUKS $MAP ok $G3_UUID_A; g3_row 200000 "FAIL (device_not_luks): device_type=ext4 mount_source=/dev/sdb mapper_present=no"; } > "$FX/p_oldfail"
  g3_row 3600 "OK: /mnt/data is LUKS-backed (device_type=$LUKS mount_source=$MAP escrow=ok header=readable boot_id=$G3_UUID_A)" soleur-web-1 > "$FX/p_otherhost"
  g3_row 3600 "OK: /mnt/data is LUKS-backed (device_type=$LUKS mount_source=$MAP escrow=ok header=readable boot_id=$G3_UUID_A)" soleur-web-2 some-other-tag > "$FX/p_otherident"
  g3_row 3600 "OK: /mnt/data is LUKS-backed (device_type=$LUKS mount_source=$MAP escrow=ok header=readable boot_id=$G3_UUID_A)" soleur-web-2 luks-monitor "" > "$FX/p_nounit"
  g3_probe 3600 $LUKS $MAP ok unknown > "$FX/p_unk"
  g3_probe 3600 $LUKS $MAP ok $G3_UUID_A > "$FX/p_eq"
  g3_probe 3601 $LUKS $MAP ok $G3_UUID_A > "$FX/p_1s_older"
  g3_ready 259200 1 ok $G3_UUID_B > "$FX/r_ok"          # the readiness row is from the FIRST boot (B); the probe rows are from a later one (A): a reboot happened (still GREEN)
  g3_ready 259200 0 ok $G3_UUID_A > "$FX/r_luks0"
  g3_ready 259200 1 missing $G3_UUID_A > "$FX/r_escrow"
  g3_ready 259200 1 ok $G3_UUID_B > "$FX/r_boot_b"
  g3_ready 259200 1 ok $G3_UUID_A > "$FX/r_boot_a"    # the SAME boot as p_ok: no reboot, still GREEN (the rule needs none)
  g3_ready 259200 1 ok $G3_UUID_A 1 none > "$FX/r_armnone"
  g3_ready 259200 1 ok $G3_UUID_A 1 noop > "$FX/r_noop"      # w2l_ready_verdict tolerates noop; w2l_ready_arm (the marker rule) does not
  g3_ready 259200 1 ok $G3_UUID_A 1 opened > "$FX/r_opened"  # a fresh host that opened the existing LUKS container
  { g3_ready 300000 1 ok $G3_UUID_A 1 formatted; g3_ready 259200 1 ok $G3_UUID_A 1 noop; } > "$FX/r_old_fmt_new_noop"   # the NEWEST row decides: refused
  { g3_ready 300000 1 ok $G3_UUID_A 1 noop; g3_ready 259200 1 ok $G3_UUID_A 1 formatted; } > "$FX/r_old_noop_new_fmt"   # the NEWEST row decides: earned
  g3_ready 259200 1 ok $G3_UUID_A 0 formatted > "$FX/r_ready0"
  g3_ready 259200 1 ok $G3_UUID_A 1 formatted token=0 > "$FX/r_token0"
  g3_ready 259200 1 ok $G3_UUID_A 1 formatted vector=0 > "$FX/r_vector0"
  g3_ready 259200 1 ok $G3_UUID_A 1 formatted volume=0 > "$FX/r_volume0"
  g3_ready 259200 1 ok $G3_UUID_A 1 formatted stage=kernel_up > "$FX/r_stage"
  g3_ready 259200 1 ok $G3_UUID_A 1 formatted host=soleur-web-1 > "$FX/r_otherhost"
  g3_ready 259200 1 ok unknown > "$FX/r_unk"
  g3_ready 600 1 ok $G3_UUID_A > "$FX/r_newer"        # a rebirth: the readiness row is NEWER than p_ok (3600 s)
  g3_ready 3600 1 ok $G3_UUID_B > "$FX/r_eq"          # same age as p_ok
  : > "$FX/empty"
  printf '<html><body>502 Bad Gateway</body></html>\n' > "$FX/junk"

  # --- sandbox: the code under test + stubs that REFUSE what they were not taught (exit 64) ------------
  g3_sandbox() { # <name> -> path
    local d="$G3/sb-$1"
    rm -rf "$d"; mkdir -p "$d/scripts/lib" "$d/bin" "$d/home"
    cp scripts/betterstack-query.sh "$d/scripts/"
    cp scripts/lib/web2-luks-rows.sh scripts/lib/betterstack-read-classify.sh "$d/scripts/lib/"
    cp "$G3/marker.sh" "$d/marker.sh"
    cat > "$d/bin/curl" <<'EOS'
#!/usr/bin/env bash
# Stub for the ONE egress site (betterstack-query.sh run_sql). Refuses anything it was not taught.
url=""; user=""; data=""
while [[ $# -gt 0 ]]; do
  case "$1" in -u) user="$2"; shift 2 ;; -d) data="$2"; shift 2 ;; https://*) url="$1"; shift ;; *) shift ;; esac
done
# no secret-shaped variable (the marker write token above all) may reach the query child
if [[ -n "$(env | cut -d= -f1 | grep -E 'TOKEN|SECRET|KEY|CREDENTIAL|AUTH|^DOPPLER' || true)" ]]; then echo "curl stub: a secret-shaped variable leaked into the query child" >&2; exit 64; fi
case "$url" in "https://fixture-connect.betterstackdata.com?"*) : ;; *) echo "curl stub: REFUSED destination" >> "${CURL_LOG:-/dev/null}"; exit 64 ;; esac
[[ "$user" == fixture-user:fixture-pass ]] || { echo "curl stub: REFUSED credentials" >> "${CURL_LOG:-/dev/null}"; exit 64; }
printf '%s\n--END--\n' "$data" >> "${CURL_LOG:-/dev/null}"
case "${FIXTURE_BS_MODE:-ok}" in
  503) printf '%s\n' '{"error":"Service Unavailable"}'; exit 22 ;;
  429) printf '%s\n' '{"error":"Too Many Requests"}'; exit 22 ;;
  timeout) exit 28 ;;
  conn) exit 6 ;;
esac
case "$data" in
  *"'luks-monitor'"*) cat "$FIXTURE_PROBE" ;;
  *SOLEUR_FRESH_BOOT_READY*) cat "$FIXTURE_READY" ;;
  *) echo "curl stub: REFUSED query" >> "${CURL_LOG:-/dev/null}"; exit 64 ;;
esac
EOS
    cat > "$d/bin/doppler" <<'EOS'
#!/usr/bin/env bash
# Stub for the doppler CLI. Records every call (unless DOPPLER_STUB_MODE=norecord — the harness mutation),
# models the marker key as a state file, and REFUSES (exit 64) any call it was not taught.
[[ "${DOPPLER_STUB_MODE:-}" == norecord ]] || printf '%s\n' "$*" >> "${DOPPLER_LOG:-/dev/null}"
case "$*" in *"${DOPPLER_TOKEN:-@@none@@}"*) echo "doppler stub: the token appeared in argv" >&2; exit 64 ;; esac
[[ "${DOPPLER_TOKEN:-}" == dp.st.fixture0token ]] || { echo "doppler stub: wrong or absent DOPPLER_TOKEN" >&2; exit 64; }
verb="${1:-} ${2:-}"; key="${3:-}"
[[ "$key" == WORKSPACES_LUKS_CUTOVER_AT ]] || { echo "doppler stub: REFUSED key '$key'" >&2; exit 64; }
for need in " -p soleur " " -c prd_workspaces_luks_marker "; do
  case " $* " in *"$need"*) : ;; *) echo "doppler stub: REFUSED scope (missing$need)" >&2; exit 64 ;; esac
done
# Flag-surface model of the real CLI (v3.76.6): --no-interactive exists ONLY on
# `secrets set` (it skips the confirmation prompt); `secrets get` and
# `secrets delete` reject it with 'unknown flag'. #9429 ran four days red on
# exactly that — the flag sat in the shared marker_args and every read failed.
case "$verb" in
  "secrets set")
    case " $* " in *" --no-interactive "*) : ;; *) echo "doppler stub: set missing --no-interactive" >&2; exit 64 ;; esac ;;
  "secrets get"|"secrets delete")
    case " $* " in *" --no-interactive "*) echo "doppler stub: --no-interactive is a set-only flag (#9429)" >&2; exit 64 ;; esac ;;
esac
case "$verb" in
  "secrets get")
    # The fault carries a FOREIGN dp.st.* token shape so the redaction net is exercised end-to-end,
    # not merely the diagnostic's reachability (an unfiltered print would leak it).
    [[ "${FIXTURE_DOPPLER_GET_FAIL:-0}" == 1 ]] && { echo "Doppler Error: unable to reach the API (ref dp.st.foreign0fixture)" >&2; exit 1; }
    if [[ -f "$DOPPLER_STATE" ]]; then cat "$DOPPLER_STATE"; exit 0; fi
    echo "Doppler Error: Could not find requested secret: $key" >&2; exit 1 ;;
  "secrets set")
    v="$(cat)"
    [[ "${FIXTURE_DOPPLER_SET_FAIL:-0}" == 1 ]] && { echo "Doppler Error: write refused" >&2; exit 1; }
    [[ "${FIXTURE_DOPPLER_SET_DIVERGE:-0}" == 1 ]] && v="diverged-$v"
    [[ "${DOPPLER_STUB_MODE:-}" == norecord ]] || printf '%s' "$v" > "$DOPPLER_STATE"
    # the real CLI prints every remaining secret of the config to stdout
    echo "DUMPED_SECRET_SENTINEL=should-never-reach-the-run-log"; exit 0 ;;
  "secrets delete")
    case " $* " in *" --yes "*) : ;; *) echo "doppler stub: delete without --yes" >&2; exit 64 ;; esac
    [[ "${FIXTURE_DOPPLER_DELETE_FAIL:-0}" == 1 ]] && { echo "Doppler Error: delete refused" >&2; exit 1; }
    [[ "${FIXTURE_DELETE_INHERITED:-0}" == 1 ]] || rm -f "$DOPPLER_STATE"
    echo "DUMPED_SECRET_SENTINEL=should-never-reach-the-run-log"; exit 0 ;;
esac
echo "doppler stub: REFUSED verb '$verb'" >&2; exit 64
EOS
    # jq stub: the real jq, except that FIXTURE_JQ_BREAK=1 makes every program but the body-shape check crash (a broken runner)
    cat > "$d/bin/jq" <<'EOS'
#!/usr/bin/env bash
if [[ "${FIXTURE_JQ_BREAK:-0}" == 1 ]]; then case "$*" in *'type == "object"'*) : ;; *) echo "jq stub: broken runner" >&2; exit 3 ;; esac; fi
PATH=/usr/bin:/bin exec jq "$@"
EOS
    chmod +x "$d/bin/curl" "$d/bin/doppler" "$d/bin/jq"
    printf '%s' "$d"
  }

  # g3_scn <sandbox> <probe-file> <ready-file> <marker-initial|none> [ENV=VAL ...] -> G3_RC; files in the sandbox
  g3_scn() {
    local sb="$1" pf="$2" rf="$3" init="$4"; shift 4
    rm -f "$sb/state" "$sb/doppler.log" "$sb/curl.log" "$sb/out" "$sb/gh_out"
    : > "$sb/doppler.log"; : > "$sb/curl.log"; : > "$sb/gh_out"
    G3_RC=0
    [[ "$init" == none ]] || printf '%s' "$init" > "$sb/state"
    ( cd "$sb" && env -i PATH="$sb/bin:/usr/bin:/bin" HOME="$sb/home" GITHUB_WORKSPACE="$sb" GITHUB_OUTPUT="$sb/gh_out" \
        BETTERSTACK_QUERY_HOST=fixture-connect.betterstackdata.com BETTERSTACK_QUERY_USERNAME=fixture-user \
        BETTERSTACK_QUERY_PASSWORD=fixture-pass DOPPLER_TOKEN=dp.st.fixture0token \
        FIXTURE_PROBE="$pf" FIXTURE_READY="$rf" DOPPLER_STATE="$sb/state" DOPPLER_LOG="$sb/doppler.log" CURL_LOG="$sb/curl.log" \
        DOPPLER_STUB_MODE="${DOPPLER_STUB_MODE:-}" "$@" \
        bash --noprofile --norc -eo pipefail "$sb/marker.sh" > "$sb/out" 2>&1 ) || G3_RC=$?
  }
  g3_count() { grep -c -- "^secrets $2 " "$1/doppler.log" 2>/dev/null || true; }

  # g3_expect <label> <sandbox> <rc: 0|1|nz> <sets> <deletes> <final: none|same|iso|any> <init> <outcome> <reason>
  # Appends a line to G3_PROBLEMS for every violated expectation. A scenario whose expectation names calls
  # must see a RECORDED call: zero recorded calls under a non-empty expectation is the harness failing.
  g3_expect() {
    local label="$1" sb="$2" erc="$3" esets="$4" edels="$5" efinal="$6" init="$7" eout="$8" ereason="$9" sets dels got_o got_r
    sets="$(g3_count "$sb" set)"; dels="$(g3_count "$sb" delete)"
    case "$erc" in nz) [[ "$G3_RC" -ne 0 ]] || G3_PROBLEMS+=("$label: rc=0, expected non-zero");;
                   *) [[ "$G3_RC" -eq "$erc" ]] || G3_PROBLEMS+=("$label: rc=$G3_RC, expected $erc");; esac
    [[ "$sets" -eq "$esets" ]] || G3_PROBLEMS+=("$label: $sets set call(s), expected $esets")
    [[ "$dels" -eq "$edels" ]] || G3_PROBLEMS+=("$label: $dels delete call(s), expected $edels")
    if [[ "$(( esets + edels ))" -gt 0 && ! -s "$sb/doppler.log" ]]; then G3_PROBLEMS+=("$label: the doppler stub recorded ZERO calls (harness dead)"); fi
    case "$efinal" in
      none) [[ ! -e "$sb/state" ]] || G3_PROBLEMS+=("$label: marker present at the end, expected absent");;
      same) [[ "$(cat "$sb/state" 2>/dev/null)" == "$init" ]] || G3_PROBLEMS+=("$label: marker changed, expected it untouched");;
      iso)  [[ "$(cat "$sb/state" 2>/dev/null)" =~ $G3_ISO_RE ]] || G3_PROBLEMS+=("$label: marker is not ISO-8601 UTC");;
      any)  : ;;
    esac
    # the outcome CLASS and the RED REASON the step reported (the contract the issue and the check-in consume)
    got_o="$(sed -n 's/^outcome=//p' "$sb/gh_out" | tail -1)"; got_r="$(sed -n 's/^reason=//p' "$sb/gh_out" | tail -1)"
    [[ "$got_o" == "$eout" ]] || G3_PROBLEMS+=("$label: outcome=${got_o:-none}, expected $eout")
    [[ "$got_r" == "$ereason" ]] || G3_PROBLEMS+=("$label: reason=${got_r:-none}, expected $ereason")
    if grep -qE 'dp\.st\.[A-Za-z0-9._-]+' "$sb/out" "$sb/doppler.log" "$sb/curl.log" 2>/dev/null; then G3_PROBLEMS+=("$label: a dp.st.* token reached a log or a command line"); fi
    if grep -q 'DUMPED_SECRET_SENTINEL' "$sb/out" 2>/dev/null; then G3_PROBLEMS+=("$label: the CLI's secret dump reached the run log"); fi
  }

  # The battery: scenario id -> (probe, ready, init, expectation). Optional filter in G3_ONLY.
  # scn <id> <probe> <ready> <init> <rc> <sets> <dels> <final> <outcome> <reason> [ENV=VAL ...]
  #   G3_NOCALL=1 additionally requires that Doppler was never reached; G3_NEEDLE='x' that the run log says x.
  g3_battery() { # <sandbox>
    local sb="$1" P="$G3_MARKER_PRIOR"
    G3_PROBLEMS=(); G3_RES=(); G3_RAN=()
    # The filter names scenarios by their Sxx prefix (G3_ONLY may carry the full id).
    want() { local k="${1:0:3}" x; [[ -z "${G3_ONLY:-}" ]] && return 0; for x in $G3_ONLY; do [[ "${x:0:3}" == "$k" ]] && return 0; done; return 1; }
    scn() {
      local id="$1" pf="$2" rf="$3" init="$4" erc="$5" es="$6" ed="$7" ef="$8" eo="$9" er="${10}" before; shift 10
      want "$id" || return 0
      before="${#G3_PROBLEMS[@]}"
      g3_scn "$sb" "$FX/$pf" "$FX/$rf" "$init" "$@"
      g3_expect "$id" "$sb" "$erc" "$es" "$ed" "$ef" "$init" "$eo" "$er"
      if [[ -n "${G3_NOCALL:-}" && -s "$sb/doppler.log" ]]; then G3_PROBLEMS+=("$id: Doppler was reached: $(head -1 "$sb/doppler.log")"); fi
      if [[ -n "${G3_NEEDLE:-}" ]] && ! grep -qF -- "$G3_NEEDLE" "$sb/out"; then G3_PROBLEMS+=("$id: the run log lacks '$G3_NEEDLE'"); fi
      G3_RAN+=("$id")
      if [[ "${#G3_PROBLEMS[@]}" -eq "$before" ]]; then G3_RES+=("$id|ok"); else G3_RES+=("$id|${G3_PROBLEMS[$before]}"); fi
    }
    # --- GREEN: earn, keep, and the instance-level join ---------------------------------------------------
    scn S01-green-writes-once-when-absent      p_ok       r_ok      none 0 1 0 iso  green marker_written
    scn S02-green-never-rewrites-a-present-key p_ok       r_ok      "$P" 0 0 0 same green marker_kept
    scn S03-unknown-extra-field-and-25h-is-GREEN p_extra25h r_ok    none 0 1 0 iso  green marker_written
    scn S10-reboot-probe-boot-id-differs-from-readiness-is-GREEN p_ok r_boot_b none 0 1 0 iso green marker_written
    scn S13-readiness-aged-out-marker-present-keeps p_ok  empty     "$P" 0 0 0 same green marker_kept
    scn S31-readiness-defect-irrelevant-when-keeping p_ok r_luks0   "$P" 0 0 0 same green marker_kept
    scn S32-probe-age-equal-to-readiness-age-is-GREEN p_eq r_eq     none 0 1 0 iso  green marker_written
    scn S40-boot-id-unknown-on-both-rows-is-GREEN p_unk   r_unk     none 0 1 0 iso  green marker_written
    scn S41-old-FAIL-then-newer-OK-is-GREEN    p_oldfail  r_ok      none 0 1 0 iso  green marker_written
    scn S47-junk-readiness-body-leaves-a-kept-marker-alone p_ok junk "$P" 0 0 0 same green marker_kept
    # --- RED on the probe row: the key is deleted, the run is red ------------------------------------------
    scn S04-stale-27h           p_stale27h   r_ok  "$P" 1 0 1 none red probe_stale
    scn S05-backing-not-luks    p_ext4       r_ok  "$P" 1 0 1 none red probe_not_luks
    scn S07-mount-source        p_mount      r_ok  "$P" 1 0 1 none red probe_mount_source
    scn S08-probe-escrow        p_escrow     r_ok  "$P" 1 0 1 none red probe_escrow
    scn S11-empty-probe         empty        r_ok  "$P" 1 0 1 none red no_probe_row
    scn S12-junk-probe          junk         r_ok  "$P" 1 0 1 none red probe_body_unparseable
    scn S14-fail-row-newest     p_failnewest r_ok  "$P" 1 0 1 none red probe_fail_row
    scn S15-duplicate-key       p_dupkey     r_ok  "$P" 1 0 1 none red probe_malformed
    scn S48-other-host-row-is-not-evidence    p_otherhost  r_ok "$P" 1 0 1 none red probe_malformed
    scn S49-other-identifier-row-is-not-evidence p_otherident r_ok "$P" 1 0 1 none red probe_malformed
    scn S50-row-without-the-emitting-unit-is-not-evidence p_nounit r_ok "$P" 1 0 1 none red probe_malformed
    scn S30-rebirth-readiness-newer-than-probe-deletes-a-kept-marker p_ok r_newer "$P" 1 0 1 none red probe_predates_ready
    # --- RED on the readiness row (marker absent, so the readiness row is required) -------------------------
    scn S06-ready-luks0         p_ok r_luks0   none 1 0 0 none red ready_not_luks
    scn S09-ready-escrow        p_ok r_escrow  none 1 0 0 none red ready_escrow
    scn S16-luks-arm-none       p_ok r_armnone none 1 0 0 none red ready_luks_arm
    scn S18-junk-ready          p_ok junk      none 1 0 0 none red ready_body_unparseable
    scn S34-ready-0             p_ok r_ready0  none 1 0 0 none red ready_not_ready
    scn S35-token-0             p_ok r_token0  none 1 0 0 none red ready_unit
    scn S36-vector-0            p_ok r_vector0 none 1 0 0 none red ready_unit
    scn S37-volume-0            p_ok r_volume0 none 1 0 0 none red ready_unit
    scn S38-other-stage         p_ok r_stage   none 1 0 0 none red ready_stage
    scn S39-other-host          p_ok r_otherhost none 1 0 0 none red ready_host
    scn S17-red-key-absent      p_stale27h r_ok none 1 0 0 none red probe_stale
    scn S28-junk-body-marker-absent junk r_ok  none 1 0 0 none red probe_body_unparseable
    # --- NOT LIVE YET: a notice, not a daily red (marker absent, nothing certified, the gate closed) --------
    G3_NEEDLE='not live yet' scn S26-not-live-yet-no-probe-rows-marker-absent empty r_ok none 0 0 0 none not_live no_probe_row
    scn S27-no-ready-rows-marker-absent p_ok empty none 0 0 0 none not_live no_ready_row
    scn S29-probe-predates-ready-marker-absent p_ok r_newer none 0 0 0 none not_live probe_predates_ready
    scn S33-probe-one-second-older-than-ready-marker-absent p_1s_older r_eq none 0 0 0 none not_live probe_predates_ready
    # --- a FAILED QUERY (or credentials absent) touches nothing and never reaches Doppler ---------------------
    G3_NOCALL=1 scn S19-503     p_ok r_ok "$P" nz 0 0 same query_failed query FIXTURE_BS_MODE=503
    G3_NOCALL=1 scn S20-429     p_ok r_ok "$P" nz 0 0 same query_failed query FIXTURE_BS_MODE=429
    G3_NOCALL=1 scn S21-timeout p_ok r_ok "$P" nz 0 0 same query_failed query FIXTURE_BS_MODE=timeout
    G3_NOCALL=1 scn S22-conn    p_ok r_ok "$P" nz 0 0 same query_failed query FIXTURE_BS_MODE=conn
    G3_NOCALL=1 scn S23-no-creds p_ok r_ok "$P" nz 0 0 same query_failed BETTERSTACK_QUERY_PASSWORD_missing BETTERSTACK_QUERY_PASSWORD=
    G3_NOCALL=1 scn S46-no-write-token p_ok r_ok "$P" nz 0 0 same query_failed DOPPLER_TOKEN_missing DOPPLER_TOKEN=
    G3_NOCALL=1 scn S44-bad-token-shape p_ok r_ok "$P" nz 0 0 same query_failed token_shape 'DOPPLER_TOKEN=x$(id)'
    # --- Doppler faults ------------------------------------------------------------------------------------------
    scn S24-doppler-read-fault-on-green p_ok r_ok "$P" nz 0 0 same query_failed marker_read FIXTURE_DOPPLER_GET_FAIL=1
    scn S45-doppler-read-fault-on-red p_stale27h r_ok "$P" nz 0 0 same query_failed marker_read FIXTURE_DOPPLER_GET_FAIL=1
    # S55 — #9429: the fault arm must say WHY. The needle is the stub's own stderr line; without the
    # sanitized print in doppler_call() the run log names only the wrapper's "could not read" text.
    G3_NEEDLE='unable to reach the API' scn S55-marker-read-fault-is-self-describing p_ok r_ok "$P" nz 0 0 same query_failed marker_read FIXTURE_DOPPLER_GET_FAIL=1
    # S57/S58 — #9613: the helper wraps EVERY call, so the set and delete faults must reach the run
    # log sanitized too (the needle is each stub's own stderr line, carried by [doppler-stderr]).
    G3_NEEDLE='write refused' scn S57-set-fault-logs-the-sanitized-why p_ok r_ok none nz 1 0 none query_failed marker_write FIXTURE_DOPPLER_SET_FAIL=1
    G3_NEEDLE='delete refused' scn S58-delete-fault-logs-the-sanitized-why p_stale27h r_ok "$P" nz 0 1 same red_delete_failed probe_stale FIXTURE_DOPPLER_DELETE_FAIL=1
    # S56 — a key that EXISTS but carries an empty value must read absent: the gate downstream reads
    # empty as absent too, and 'present' here would freeze the soak at marker_kept forever.
    scn S56-empty-marker-value-reads-absent p_ok r_ok "" 0 1 0 iso green marker_written
    G3_NEEDLE="recheck reads 'present'" scn S25-delete-that-does-not-take-is-loud p_stale27h r_ok "$P" nz 0 1 same red_delete_failed probe_stale FIXTURE_DELETE_INHERITED=1
    scn S52-a-judge-fault-is-not-negative-evidence p_ok r_ok "$P" nz 0 0 same query_failed judge_error FIXTURE_JQ_BREAK=1
    G3_NEEDLE='deleting the marker FAILED' scn S51-delete-command-fails p_stale27h r_ok "$P" nz 0 1 same red_delete_failed probe_stale FIXTURE_DOPPLER_DELETE_FAIL=1
    scn S53-probe-boot-id-equal-to-readiness-is-GREEN p_ok r_boot_a none 0 1 0 iso green marker_written
    scn S54-readiness-boot-id-unknown-while-the-probe-is-known-is-GREEN p_ok r_unk none 0 1 0 iso green marker_written
    scn S59-readiness-luks-arm-noop-is-not-earned p_ok r_noop none 1 0 0 none red ready_luks_arm
    scn S60-readiness-luks-arm-opened-is-GREEN p_ok r_opened none 0 1 0 iso green marker_written
    scn S61-an-older-formatted-row-does-not-rescue-a-newer-noop-row p_ok r_old_fmt_new_noop none 1 0 0 none red ready_luks_arm
    scn S62-an-older-noop-row-does-not-block-a-newer-formatted-row p_ok r_old_noop_new_fmt none 0 1 0 iso green marker_written
    scn S42-doppler-set-fails    p_ok r_ok none nz 1 0 none query_failed marker_write FIXTURE_DOPPLER_SET_FAIL=1
    scn S43-read-back-mismatch   p_ok r_ok none nz 1 0 any  query_failed marker_readback FIXTURE_DOPPLER_SET_DIVERGE=1
  }
  G3_EXPECTED_IDS="S01 S02 S03 S04 S05 S06 S07 S08 S09 S10 S11 S12 S13 S14 S15 S16 S17 S18 S19 S20 S21 S22 S23 S24 S25 S26 S27 S28 S29 S30 S31 S32 S33 S34 S35 S36 S37 S38 S39 S40 S41 S42 S43 S44 S45 S46 S47 S48 S49 S50 S51 S52 S53 S54 S55 S56 S57 S58 S59 S60 S61 S62"

  # ---- PRISTINE: the battery must be clean on the code as shipped, and every scenario is its OWN assertion ----
  G3_SB="$(g3_sandbox pristine)"
  unset G3_ONLY
  g3_battery "$G3_SB"
  for r in "${G3_RES[@]}"; do
    if [[ "${r#*|}" == ok ]]; then ok "G3 ${r%%|*}"; else no "G3 ${r%%|*} violated: ${r#*|}"; fi
  done
  g3_got_ids="$(printf '%s\n' "${G3_RAN[@]}" | cut -c1-3 | sort -u | tr '\n' ' ')"
  g3_want_ids="$(tr ' ' '\n' <<<"$G3_EXPECTED_IDS" | sort -u | tr '\n' ' ')"
  if [[ "$g3_got_ids" == "$g3_want_ids" && "${#G3_RAN[@]}" -eq 62 ]]; then ok "G3 the registered scenario set ran exactly (62 ids, each once)"; else no "G3 the scenario set drifted: ran [$g3_got_ids] (${#G3_RAN[@]} runs), expected [$g3_want_ids]"; fi

  # the green scenario's two reads: host-scoped, unit-pinned, archive arm present, server-side age, no LIKE wildcard
  g3_scn "$G3_SB" "$FX/p_ok" "$FX/r_ok" none
  g3_sql="$(cat "$G3_SB/curl.log")"
  if [[ "$g3_sql" == *"JSONExtractString(raw,'host_name') = 'soleur-web-2'"* && "$g3_sql" == *"JSONExtractString(raw,'_SYSTEMD_UNIT') = 'luks-monitor.service'"* \
        && "$g3_sql" == *"s3Cluster(primary, t520508_soleur_inngest_vector_prd_3_s3)"* && "$g3_sql" == *"dateDiff('second', dt, now())"* \
        && "$g3_sql" == *"position(JSONExtractString(raw,'message'), ' host=soleur-web-2 ') > 0"* \
        && "$g3_sql" == *"startsWith(JSONExtractString(raw,'message'), 'SOLEUR_FRESH_BOOT_READY ')"* \
        && "$(grep -c -- '--END--' "$G3_SB/curl.log")" -eq 2 ]]; then
    ok "G3 the two reads are host-scoped, pin the emitting unit, include the archive arm, carry a server-side age and anchor the readiness marker without a LIKE wildcard"
  else
    no "G3 the Better Stack reads lost their host/unit predicate, their archive arm, the server-side age or the readiness anchor"
  fi
  if ! grep -E "LIKE '[^']*SOLEUR_FRESH" "$G3_SB/curl.log" >/dev/null; then ok "G3 no LIKE pattern carries the readiness marker name (its underscores are one-character wildcards in LIKE)"; else no "G3 the readiness marker is matched with LIKE again"; fi
  # the value written is one lb-weight-gate.sh parses (and the gate READS the same name)
  g3_written="$(cat "$G3_SB/state" 2>/dev/null)"
  g3_gate_re="$(sed -nE "s/^ISO_RE='(.*)'\$/\\1/p" apps/web-platform/infra/lb-weight-gate.sh)"
  if [[ -n "$g3_gate_re" && "$g3_written" =~ $g3_gate_re ]] && date -u -d "$g3_written" +%s >/dev/null 2>&1 \
     && grep -qF 'WS_MARKER="${WORKSPACES_LUKS_CUTOVER_AT-}"' apps/web-platform/infra/lb-weight-gate.sh; then
    ok "G3 the written marker matches lb-weight-gate.sh's own ISO_RE and parses, and the gate still reads WORKSPACES_LUKS_CUTOVER_AT"
  else
    no "G3 the marker format (${g3_written:-none}) is not one lb-weight-gate.sh parses, or the gate stopped reading the key"
  fi
  # xtrace refusal is behavioural, not just spelled: a traced run exits 78 before it touches anything
  g3_trc=0
  ( cd "$G3_SB" && env -i PATH="$G3_SB/bin:/usr/bin:/bin" HOME="$G3_SB/home" GITHUB_WORKSPACE="$G3_SB" GITHUB_OUTPUT="$G3_SB/gh_out" \
      BETTERSTACK_QUERY_HOST=fixture-connect.betterstackdata.com BETTERSTACK_QUERY_USERNAME=fixture-user BETTERSTACK_QUERY_PASSWORD=fixture-pass \
      DOPPLER_TOKEN=dp.st.fixture0token FIXTURE_PROBE="$FX/p_ok" FIXTURE_READY="$FX/r_ok" DOPPLER_STATE="$G3_SB/state" DOPPLER_LOG="$G3_SB/doppler.log" \
      bash --noprofile --norc -exo pipefail "$G3_SB/marker.sh" > "$G3_SB/trace.out" 2>&1 ) || g3_trc=$?
  if [[ "$g3_trc" -eq 78 ]] && ! grep -q 'dp.st.fixture0token' "$G3_SB/trace.out"; then ok "G3 a traced run is refused (rc 78) and the token is not echoed"; else no "G3 xtrace was not refused (rc $g3_trc) or the token was echoed"; fi

  # --- the census: no file in the TREE names the key outside the one writer and its read-only users ----------
  # OCCURRENCE-based, not verb-based: a file that names the key (any spelling a grep finds: the name itself in
  # any case, the helper's W2L_MARKER_NAME alias, a quote-split `WORKSPACES_LUKS_CUTOVER""_AT`, or the helper's
  # file name) in a CODE line is a finding unless it is allow-listed; an allow-listed READER that carries any write
  # verb (doppler secrets set/delete/upload, an HTTP write method in any spelling, the Doppler API host, an HCL
  # doppler_secret) is a finding too; and the one writer must hold exactly two write/delete sites.
  cat > "$G3/census.py" <<'PY'
import os, re, sys
root = sys.argv[1]
WRITER = ".github/workflows/workspaces-luks-verify.yml"
READERS = {"scripts/lib/web2-luks-rows.sh", "apps/web-platform/infra/lb-weight-gate.sh", "apps/web-platform/infra/lb-weight-gate-with-marker.sh",
           ".github/workflows/infra-validation.yml", "scripts/followthroughs/web2-luks-live-6931.sh",
           "scripts/lib/test-affected-paths.sh", "scripts/web2-rebirth-emptiness.sh", "scripts/web2-rebirth-never-pooled.sh", "scripts/web2-rebirth-ready-poll.sh",
           "scripts/web-host-reboot-evidence.sh"}
KEY = re.compile(r"workspaces_luks_cutover[\"'_]*at\b|w2l_marker_name|web2-luks-rows", re.I)
VERB = re.compile(r"doppler(?:_call)?\b[^\n]*\bsecrets\b[^\n]*\b(set|delete|upload)\b|resource\s+[\"']doppler_secret[\"']|api\.doppler\.com"
                  r"|/secrets?/(set|delete|upload)\b|/configs/config/secrets\b"
                  r"|-X\s*(POST|PUT|PATCH|DELETE)\b|--request[=\s]\s*(POST|PUT|PATCH|DELETE)\b"
                  r"|requests\.(post|put|patch|delete)\b|method[\"']?\s*[:=]\s*[\"'](POST|PUT|PATCH|DELETE)"
                  r"|\bcurl\b[^\n]*\s(-d|--data[a-z-]*|--json|-T|--upload-file)\b", re.I)
SKIP_DIRS = {".git", "node_modules", ".worktrees", ".terraform", "__pycache__", ".next", "dist", ".venv", "venv", "_site"}
EXT = (".yml", ".yaml", ".sh", ".bash", ".py", ".ts", ".tsx", ".js", ".mjs", ".cjs", ".tf", ".tfvars", ".service", ".rb", ".go", ".toml")
flagged, sites = [], 0
for dp, dn, fn in os.walk(root):
    dn[:] = [d for d in dn if d not in SKIP_DIRS]
    for f in fn:
        if not f.endswith(EXT) or ".test." in f:
            continue
        p = os.path.join(dp, f)
        rel = os.path.relpath(p, root)
        try:
            txt = open(p, encoding="utf-8", errors="replace").read()
        except OSError:
            continue
        # drop comment lines, then join backslash continuations so a verb and its operand are one line
        code = "\n".join(l for l in txt.split("\n") if not l.lstrip().startswith(("#", "//")))
        code = re.sub(r"\\\n\s*", " ", code)
        if not KEY.search(code):
            continue
        verbs = [m.group(0) for l in code.split("\n") for m in VERB.finditer(l)]
        if rel == WRITER:
            sites = len(verbs)
        elif rel in READERS:
            if verbs: flagged.append(rel)
        else:
            flagged.append(rel)
print("FLAGGED " + ",".join(sorted(flagged)))
print("ALLOWED_SITES %d" % sites)
PY
  g3_census() { "${G3_PYTHON:-/usr/bin/python3}" "$G3/census.py" "$1"; }
  g3_c="$(g3_census "$PWD")"
  if [[ "$(head -1 <<<"$g3_c")" == "FLAGGED " && "$g3_c" == *"ALLOWED_SITES 2"* ]]; then
    ok "G3 census: the whole tree names the key only in the one writer (exactly two write/delete sites) and its read-only users"
  else
    no "G3 census: $(printf '%s' "$g3_c" | tr '\n' ' ')"
  fi

  # =====================================================================================================
  # MUTATION ROWS — each against a fresh sandbox copy; the pristine files are never touched.
  # =====================================================================================================
  # g3_mut <row-label> <scenario ids> <file-in-sandbox> <old> <new>
  g3_mut() {
    local label="$1" ids="$2" rel="$3" old="$4" new="$5" sb
    sb="$(g3_sandbox "m$RANDOM")"
    if ! g3_sub "$sb/$rel" "$old" "$new"; then no "G3 mutation $label: the edit did not land exactly once in $rel (a row that scored the baseline proves nothing)"; return; fi
    # CONTROL FIRST: the mutant must still WORK on the plain green path, otherwise a syntax error or a jq
    # compile error would score as a caught defect (every scenario fails on a dead script).
    G3_ONLY="S01" g3_battery "$sb"
    if [[ "${#G3_PROBLEMS[@]}" -gt 0 ]]; then no "G3 mutation $label broke the CONTROL scenario S01 (${G3_PROBLEMS[0]}): it measured a dead mutant, not the defect"; rm -rf "$sb"; return; fi
    G3_ONLY="$ids" g3_battery "$sb"
    if [[ "${#G3_PROBLEMS[@]}" -gt 0 ]]; then ok "G3 mutation $label -> RED (${G3_PROBLEMS[0]%%:*})"; else no "G3 mutation $label stayed GREEN: the battery cannot see this defect"; fi
    rm -rf "$sb"
  }
  LIB=scripts/lib/web2-luks-rows.sh
  g3_mut "1 stale row (>26h) still writes"          "S04" $LIB $'        elif $r.age > $max then "RED reason=probe_stale"\n' ''
  g3_mut "2a non-crypto_LUKS backing still writes"   "S05" $LIB $'        elif ($r.f.device_type // "") != "crypto_LUKS" then "RED reason=probe_not_luks"\n' ''
  g3_mut "2b readiness luks=0 still writes"          "S06" $LIB $'        elif ($r.f.luks // "") != "1" then "RED reason=ready_not_luks"\n' ''
  g3_mut "2c wrong mount source still writes"        "S07" $LIB $'        elif ($r.f.mount_source // "") != "/dev/mapper/workspaces" then "RED reason=probe_mount_source"\n' ''
  g3_mut "3 delete skipped on negative evidence"     "S04" marker.sh $'doppler_call secrets delete "$W2L_MARKER_NAME" --yes "${marker_args[@]}" >/dev/null \\' 'true \'
  g3_mut "4 writes every run (first-green start overwritten)" "S02" marker.sh $'if [[ "$state" == present ]]; then\n      echo "marker already present' $'if false; then\n      echo "marker already present'
  g3_mut "6 empty body read as a query failure"      "S11" marker.sh $'if [[ "$qfail" -ne 0 ]]; then' $'[[ -s "$tmp/probe.jsonl" ]] || qfail=1\nif [[ "$qfail" -ne 0 ]]; then'
  g3_mut "7a failed query falls through and deletes" "S19" marker.sh $'if [[ "$qfail" -ne 0 ]]; then' 'if false; then'
  g3_mut "7b failed query passes the run"            "S20" marker.sh $'emit query_failed query\n  exit 1' $'emit query_failed query\n  exit 0'
  g3_mut "8a probe escrow=ok requirement dropped"    "S08" $LIB $'        elif ($r.f.escrow // "") != "ok" then "RED reason=probe_escrow"\n' ''
  g3_mut "8b readiness escrow=ok requirement dropped" "S09" $LIB $'        elif ($r.f.escrow // "") != "ok" then "RED reason=ready_escrow"\n' ''
  g3_mut "9a instance-level join dropped (a probe older than the readiness row certifies it)" "S29 S30 S33" $LIB \
    $'  if [[ "$ra" =~ ^[0-9]+$ ]] && (( pa > ra )); then printf \'RED reason=probe_predates_ready\\n\'; return 0; fi' ':'
  g3_mut "9b earning without a green readiness row"   "S06 S09 S27" $LIB $'    [[ "$rv" == GREEN* ]] || { printf \'%s\\n\' "$rv"; return 0; }' ':'
  g3_mut "9c keeping a marker demands a readiness row" "S13 S31 S47" $LIB $'  if [[ "$marker" == present ]]; then' '  if false; then'
  g3_mut "9d a rebirth is not noticed on a kept marker" "S30" $LIB $'    ra="$(w2l_ready_newest_age "$2")"' '    ra=""'
  g3_mut "11 strict fixed-field parser rejects the unknown extra field (must-pass row)" "S03" $LIB \
    'else {kind: "ok", age: $age, f: $f} end' 'else (if ($f | keys | length) > 5 then {kind: "junk", age: $age} else {kind: "ok", age: $age, f: $f} end) end'
  g3_mut "12 not-live exemption widened to every RED reason" "S17" marker.sh \
    $'if [[ "$state" == absent && ( "$reason" == no_probe_row || "$reason" == no_ready_row || "$reason" == probe_predates_ready ) ]]; then' $'if [[ "$state" == absent ]]; then'
  g3_mut "13 not-live exemption removed (a daily red before web-2 exists)" "S26 S27 S29" marker.sh \
    $'if [[ "$state" == absent && ( "$reason" == no_probe_row || "$reason" == no_ready_row || "$reason" == probe_predates_ready ) ]]; then' 'if false; then'
  g3_mut "13b not-live exemption no longer covers a probe older than the readiness row" "S29 S33" marker.sh \
    $' || "$reason" == probe_predates_ready ) ]]; then' $' ) ]]; then'
  g3_mut "14 host/identifier/unit re-check dropped" "S48 S49 S50" $LIB \
    'if (.host_name != $host or .ident != $ident or .unit != $unit or $age == null) then' 'if ($age == null) then'
  g3_mut "15a readiness ready=1 requirement dropped" "S34" $LIB $'        elif ($r.f.ready // "") != "1" then "RED reason=ready_not_ready"\n' ''
  g3_mut "15b readiness stage requirement dropped"   "S38" $LIB $'        elif ($r.f.stage // "") != "cloud_init_complete" then "RED reason=ready_stage"\n' ''
  g3_mut "15c readiness token/vector/volume requirement dropped" "S35 S36 S37" $LIB \
    $'        elif ($r.f.token // "") != "1" or ($r.f.vector // "") != "1" or ($r.f.volume // "") != "1" then "RED reason=ready_unit"\n' ''
  g3_mut "15d readiness host requirement dropped"    "S39" $LIB $'        elif ($r.f.host // "") != $host then "RED reason=ready_host"\n' ''
  g3_mut "16 an unreadable boot_id crashes the judge instead of being diagnostic only" "S40" $LIB \
    'if uuid then . else "unknown" end' 'if uuid then . else error("boot_id") end'
  g3_mut "17a a failed doppler set is ignored"        "S42" marker.sh \
    $'|| { echo "::error::writing the marker failed."; emit query_failed marker_write; exit 1; }' '|| true'
  g3_mut "17b the read-back check is dropped"         "S43" marker.sh \
    $'[[ "$got" == "$at" ]] || { echo "::error::the marker did not read back as written."; emit query_failed marker_readback; exit 1; }' ':'
  g3_mut "17c the token-shape check is dropped"       "S44" marker.sh $'[[ "$DOPPLER_TOKEN" =~ ^[A-Za-z0-9._-]+$ ]] || {' 'true || {'
  g3_mut "17d a Doppler read fault reads as an absent marker" "S24 S45" marker.sh \
    $'state="$(marker_state)" || { echo "::error::could not read the marker (Doppler fault). The marker was NOT touched."; emit query_failed marker_read; exit 1; }' 'state="$(marker_state)" || state=absent'
  g3_mut "22 the old reboot requirement is restored (the marker waits for a boot_id that differs)" "S40 S53 S54" $LIB \
    $'  if [[ "$marker" != present ]] && ! w2l_ready_arm "$2" >/dev/null; then printf \'RED reason=ready_luks_arm\\n\'; return 0; fi' \
    $'  if [[ "$marker" != present ]] && ! w2l_ready_arm "$2" >/dev/null; then printf \'RED reason=ready_luks_arm\\n\'; return 0; fi\n  if [[ "$marker" != present ]]; then pb="${pv#GREEN boot_id=}"; pb="${pb%% *}"; rb="${rv#GREEN boot_id=}"; rb="${rb%% *}"; if [[ -z "$pb" || -z "$rb" || "$pb" == unknown || "$rb" == unknown || "$pb" == "$rb" ]]; then printf \'RED reason=reboot_not_seen\\n\'; return 0; fi; fi'
  g3_mut "22b noop is accepted by the shared arm helper (the marker is earned on a noop boot)" "S59" $LIB \
    '[[ "$arm" == formatted || "$arm" == opened ]]' '[[ "$arm" == formatted || "$arm" == opened || "$arm" == noop ]]'
  g3_mut "22c the OLDEST readiness row decides the arm (an older formatted row rescues a newer noop one)" "S61 S62" $LIB \
    $'| .[0] // empty\n' $'| .[-1] // empty\n'
  g3_mut "17e a failed doppler delete is ignored"     "S51" marker.sh \
    $'|| { echo "::error::RED (${reason}) and deleting the marker FAILED."; emit red_delete_failed "$reason"; exit 1; }' '|| true'
  # row 18 — emit() is a no-op (the issue and the check-in would read an empty class). Its own CONTROL cannot be the
  # green path (the outcome assertion is what must fail), so the row demands that the green path now fails ON THE OUTCOME.
  g3_sb18="$(g3_sandbox m18)"
  if ! g3_sub "$g3_sb18/marker.sh" $'emit() { printf \'outcome=%s\\nreason=%s\\n\' "$1" "${2:-}" >> "${GITHUB_OUTPUT:-/dev/null}"; }' 'emit() { :; }'; then
    no "G3 mutation 18: the edit did not land exactly once"
  else
    G3_ONLY="S01" g3_battery "$g3_sb18" 2>/dev/null
    if [[ "${G3_PROBLEMS[*]:-}" == *"outcome=none, expected green"* ]]; then ok "G3 mutation 18 (emit() is a no-op) -> RED on the reported outcome class"; else no "G3 mutation 18: a silent emit() did not fail the green path (${G3_PROBLEMS[*]:-no problems})"; fi
  fi
  rm -rf "$g3_sb18"
  g3_mut "17f a judge fault is treated as negative evidence" "S52" marker.sh \
    $'if [[ "$reason" == *_judge_error ]]; then' 'if false; then'
  g3_mut "17g a marker read fault logs nothing about why" "S55" marker.sh \
    $'  printf \'%s\\n\' "$diag" | sed \'s/^/[doppler-stderr] /\' >&2' '  :'
  # 17h — the stub's flag model is load-bearing: folding the set-only flag back into
  # marker_args is the exact #9429 defect shape. It can't go through g3_mut (the defect
  # reds the control S01, which the harness would score as a dead mutant), so: land the
  # fold, run S01, and require the failure to carry the defect's own signature — the
  # stub's refusal reaching the log as marker_read — not generic breakage.
  g3_sb17h="$(g3_sandbox m17h)"
  if ! g3_sub "$g3_sb17h/marker.sh" 'marker_args=(-p "$W2L_MARKER_PROJECT" -c "$W2L_MARKER_CONFIG")' 'marker_args=(--no-interactive -p "$W2L_MARKER_PROJECT" -c "$W2L_MARKER_CONFIG")'; then
    no "G3 mutation 17h: the edit did not land exactly once"
  else
    G3_ONLY="S01" g3_battery "$g3_sb17h" 2>/dev/null
    if [[ "${G3_PROBLEMS[*]:-}" == *"reason=marker_read"* ]] && grep -qF 'set-only flag' "$g3_sb17h/out" 2>/dev/null; then
      ok "G3 mutation 17h (the set-only flag folded back into marker_args) -> RED marker_read via the stub's refusal"
    else
      no "G3 mutation 17h: the stub did not refuse the set-only flag on get (${G3_PROBLEMS[*]:-no problems})"
    fi
  fi
  rm -rf "$g3_sb17h"
  # row 20 — the query child keeps the marker write token. It cannot go through g3_mut (its CONTROL scenario is the green
  # path, which the leak itself breaks), so: the mutant must land, parse, and then fail the green path BECAUSE of the leak.
  g3_sb20="$(g3_sandbox m20)"
  if ! g3_sub "$g3_sb20/$LIB" 'env ${unset_args[@]+"${unset_args[@]}"} timeout' 'env timeout'; then
    no "G3 mutation 20: the edit did not land exactly once"
  else
    G3_ONLY="S01" g3_battery "$g3_sb20" 2>/dev/null
    if [[ "${#G3_PROBLEMS[@]}" -gt 0 ]] && grep -q 'secret-shaped variable leaked' "$g3_sb20/out"; then ok "G3 mutation 20 (the query child keeps the marker write token) -> RED (the curl stub saw it)"; else no "G3 mutation 20: a leaked write token did not fail the green path (${G3_PROBLEMS[*]:-no problems})"; fi
  fi
  rm -rf "$g3_sb20"
  # row 10 — HARNESS: a doppler stub that records nothing must fail the suite on zero recorded calls
  g3_sb10="$(g3_sandbox m10)"
  G3_ONLY="S01" DOPPLER_STUB_MODE=norecord g3_battery "$g3_sb10" 2>/dev/null
  if [[ "${#G3_PROBLEMS[@]}" -gt 0 && "${G3_PROBLEMS[*]}" == *"ZERO calls"* ]]; then ok "G3 mutation 10 (doppler stub records nothing) -> RED on zero recorded calls"; else no "G3 mutation 10: a stub that records nothing did not fail the battery (${G3_PROBLEMS[*]:-no problems})"; fi
  rm -rf "$g3_sb10"
  # row 21 — HARNESS: the registered-id assertion sees a scenario that stopped running
  g3_sb21="$(g3_sandbox m21)"
  G3_ONLY="$(tr ' ' '\n' <<<"$G3_EXPECTED_IDS" | grep -v '^S12$' | tr '\n' ' ')" g3_battery "$g3_sb21" 2>/dev/null
  g3_miss="$(printf '%s\n' "${G3_RAN[@]}" | cut -c1-3 | sort -u | tr '\n' ' ')"
  if [[ "$g3_miss" != "$g3_want_ids" ]]; then ok "G3 mutation 21 (one scenario skipped) -> the registered id set no longer matches"; else no "G3 mutation 21: a skipped scenario is invisible to the id-set check"; fi
  rm -rf "$g3_sb21"

  # row 5 — a writer ANYWHERE in the tree: the census must flag each planted shape, and leave the harmless ones green.
  # The synthetic root holds the real allow-listed files, so its clean state is the control.
  g3_cr="$G3/census-root"; rm -rf "$g3_cr"
  for f in .github/workflows/workspaces-luks-verify.yml .github/workflows/infra-validation.yml scripts/lib/web2-luks-rows.sh \
           scripts/followthroughs/web2-luks-live-6931.sh apps/web-platform/infra/lb-weight-gate.sh; do
    mkdir -p "$g3_cr/$(dirname "$f")"; cp "$f" "$g3_cr/$f"
  done
  g3_pc="$(g3_census "$g3_cr")"
  if [[ "$(head -1 <<<"$g3_pc")" == "FLAGGED " && "$g3_pc" == *"ALLOWED_SITES 2"* ]]; then ok "G3 mutation 5 control: the synthetic census root is clean (no finding, two writer sites)"; else no "G3 mutation 5 control: $(tr '\n' ' ' <<<"$g3_pc")"; fi
  g3_plant() { # <label> <relpath> <content> <flagged: yes|no>
    mkdir -p "$(dirname "$g3_cr/$2")"; printf '%s\n' "$3" > "$g3_cr/$2"
    g3_pc="$(g3_census "$g3_cr")"
    if [[ "$4" == yes ]]; then
      if [[ "$(head -1 <<<"$g3_pc")" == *"$2"* ]]; then ok "G3 mutation 5 ($1) -> RED (census flags $2)"; else no "G3 mutation 5 ($1): the census did not flag $2"; fi
    else
      if [[ "$(head -1 <<<"$g3_pc")" == "FLAGGED " ]]; then ok "G3 mutation 5 ($1) -> stays green (harmless)"; else no "G3 mutation 5 ($1): a harmless file was flagged: $(head -1 <<<"$g3_pc")"; fi
    fi
    rm -f "$g3_cr/$2"
  }
  g3_plant "a second workflow sets the key" .github/workflows/evil-set.yml $'jobs:\n  j:\n    steps:\n      - run: printf x | doppler secrets set WORKSPACES_LUKS_CUTOVER_AT -p soleur -c prd_workspaces_luks_marker >/dev/null' yes
  g3_plant "a second workflow deletes the key across a line continuation" .github/workflows/evil-del.yml $'jobs:\n  j:\n    steps:\n      - run: |\n          doppler secrets delete \\\n            WORKSPACES_LUKS_CUTOVER_AT --yes' yes
  g3_plant "a script writes the key through the API" scripts/evil-writer.sh $'#!/usr/bin/env bash\ncurl -X POST https://api.doppler.com/v3/configs/config/secrets -d \'{"secrets":{"WORKSPACES_LUKS_CUTOVER_AT":"x"}}\'' yes
  g3_plant "a script writes it via the shared helper's key name" scripts/evil-w2l.sh $'#!/usr/bin/env bash\nsource scripts/lib/web2-luks-rows.sh\ndoppler secrets set "$W2L_MARKER_NAME" x' yes
  g3_plant "a composite action writes it" .github/actions/evil/action.yml $'runs:\n  using: composite\n  steps:\n    - shell: bash\n      run: doppler -p soleur -c prd_workspaces_luks_marker secrets set WORKSPACES_LUKS_CUTOVER_AT=x' yes
  g3_plant "a plugin script writes it with global flags between doppler and secrets" plugins/soleur/scripts/evil.sh $'#!/usr/bin/env bash\ndoppler --token "$T" -p soleur secrets set WORKSPACES_LUKS_CUTOVER_AT=x' yes
  g3_plant "a server module writes it with fetch(method POST)" apps/web-platform/server/evil.ts $'await fetch("https://api.doppler.com/v3/configs/config/secrets", { method: "POST", body: JSON.stringify({ secrets: { WORKSPACES_LUKS_CUTOVER_AT: "x" } }) });' yes
  g3_plant "a Terraform doppler_secret writes it" apps/web-platform/infra/evil.tf $'resource "doppler_secret" "x" {\n  project = "soleur"\n  config  = "prd_workspaces_luks_marker"\n  name    = "WORKSPACES_LUKS_CUTOVER_AT"\n  value   = "2026-01-01T00:00:00Z"\n}' yes
  g3_plant "a python script writes it with requests.post" scripts/evil.py $'import requests\nrequests.post("https://api.doppler.com/v3/configs/config/secrets", json={"secrets": {"WORKSPACES_LUKS_CUTOVER_AT": "x"}})' yes
  g3_plant "curl --request=POST (no whitespace) writes it" scripts/evil-req.sh $'#!/usr/bin/env bash\ncurl --request=POST --data "{}" https://example.invalid/set?name=WORKSPACES_LUKS_CUTOVER_AT' yes
  g3_plant "the key spelled in lower case" scripts/evil-lower.sh $'#!/usr/bin/env bash\ndoppler secrets set workspaces_luks_cutover_at x' yes
  g3_plant "the key split by quotes so a literal grep for it finds nothing" scripts/evil-split.sh $'#!/usr/bin/env bash\nK="WORKSPACES_LUKS_CUTOVER""_AT"\ndoppler secrets set "$K" x' yes
  g3_plant "a write verb added to an allow-listed READER (the gate)" apps/web-platform/infra/lb-weight-gate.sh "$(cat apps/web-platform/infra/lb-weight-gate.sh)"$'\ndoppler secrets set OTHER_NAME x' yes
  cp apps/web-platform/infra/lb-weight-gate.sh "$g3_cr/apps/web-platform/infra/lb-weight-gate.sh"   # g3_plant removed the reader; put the real one back
  g3_plant "a comment that merely names the key" scripts/harmless-comment.sh $'#!/usr/bin/env bash\n# WORKSPACES_LUKS_CUTOVER_AT is written by the verify workflow, not here.\necho hello' no
  g3_plant "a write to a DIFFERENT secret" scripts/harmless-other.sh $'#!/usr/bin/env bash\ndoppler secrets set SOME_OTHER_SECRET x' no
  g3_plant "a test file that names the key (tests discuss it by design)" scripts/something.test.sh $'#!/usr/bin/env bash\necho WORKSPACES_LUKS_CUTOVER_AT' no
  g3_plant "a vendored dependency that names the key" node_modules/pkg/evil.js $'doppler secrets set WORKSPACES_LUKS_CUTOVER_AT x' no
  rm -rf "$g3_cr"


  # --- the issue step: its body EXECUTED over a stubbed gh (the alarm layer is behaviour, not just a condition) ----
  if [[ ! -s "$G3/issue.sh" ]]; then
    no "G3 could not extract the issue step body — every issue-step row below would be vacuous"
  else
    if bash -n "$G3/issue.sh" 2>/dev/null; then ok "G3 the issue step body passes bash -n"; else no "G3 the issue step body fails bash -n"; fi
    g3_isb() { # <name> -> sandbox: the step body, a gh stub that records every call and REFUSES unknown ones
      local d="$G3/isb-$1"
      rm -rf "$d"; mkdir -p "$d/bin" "$d/home"
      cp "$G3/issue.sh" "$d/issue.sh"
      cat > "$d/bin/gh" <<'EOS'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GH_LOG"
case "$1 $2" in
  "label create") exit 0 ;;
  "issue list") [[ "${FIXTURE_GH_LIST_FAIL:-0}" == 1 ]] && exit 1; if [[ -f "$FIXTURE_GH_LIST" ]]; then cat "$FIXTURE_GH_LIST"; else echo '[]'; fi; exit 0 ;;
  "issue view") if [[ -f "$FIXTURE_GH_VIEW" ]]; then cat "$FIXTURE_GH_VIEW"; fi; exit 0 ;;
  "issue create"|"issue comment"|"issue edit")
    prev=""; for a in "$@"; do [[ "$prev" == --body-file ]] && cat "$a" >> "$GH_BODY"; prev="$a"; done; exit 0 ;;
esac
echo "gh stub: REFUSED $*" >&2; exit 64
EOS
      chmod +x "$d/bin/gh"
      printf '%s' "$d"
    }
    # g3_irun <sandbox> <OUTCOME> <REASON> [ENV=VAL ...]
    g3_irun() {
      local d="$1" o="$2" r="$3"; shift 3
      : > "$d/gh.log"; : > "$d/body"; G3_IRC=0
      ( cd "$d" && env -i PATH="$d/bin:/usr/bin:/bin" HOME="$d/home" GH_TOKEN=fixture-gh GH_REPO=o/r OUTCOME="$o" REASON="$r" \
          MARKER_STEP_OUTCOME=failure RUN_URL=https://example.invalid/run GH_LOG="$d/gh.log" GH_BODY="$d/body" \
          FIXTURE_GH_LIST="$d/list" FIXTURE_GH_VIEW="$d/view" "$@" bash --noprofile --norc -eo pipefail issue.sh > "$d/out" 2>&1 ) || G3_IRC=$?
    }
    G3_T_RED='[ci/luks-verify-web2] web-2 LUKS evidence is RED'
    G3_T_UNAV='[ci/luks-verify-web2] could not judge web-2 - nothing proven'
    # g3_ibattery <sandbox> -> G3_IRES (id|ok or id|first problem); each scenario is its own assertion
    g3_ibattery() {
      local d="$1" before
      G3_IRES=()
      isc() { # <id> -> opens a scenario; closes with iend
        G3_IID="$1"; G3_IP=()
        rm -f "$d/list" "$d/view"
      }
      iend() {
        [[ "$G3_IRC" -eq 0 ]] || G3_IP+=("the step exited $G3_IRC (it must never fail the run it reports on): $(head -c 120 "$d/out")")
        if [[ "${#G3_IP[@]}" -eq 0 ]]; then G3_IRES+=("$G3_IID|ok"); else G3_IRES+=("$G3_IID|${G3_IP[0]}"); fi
      }
      icreated() { grep -qF -- "issue create --repo o/r --title $1 " "$d/gh.log"; }
      isc I1-red-files-the-RED-issue
        g3_irun "$d" red probe_stale
        icreated "$G3_T_RED" || G3_IP+=("no RED issue created: $(tr '\n' '|' < "$d/gh.log" | head -c 160)")
        grep -qF -- '--label luks/class-web2-red' "$d/gh.log" && grep -qF -- '--label priority/p1-high' "$d/gh.log" || G3_IP+=("RED labels missing")
        grep -qF -- 'reason=probe_stale' "$d/body" || G3_IP+=("the body lacks reason=probe_stale")
      iend
      isc I2-red_delete_failed-files-the-same-RED-issue
        g3_irun "$d" red_delete_failed probe_stale
        icreated "$G3_T_RED" || G3_IP+=("no RED issue created")
      iend
      isc I3-query_failed-files-the-unavailable-issue
        g3_irun "$d" query_failed marker_read
        icreated "$G3_T_UNAV" || G3_IP+=("no unavailable issue created")
        grep -qF -- '--label luks/class-web2-unavailable' "$d/gh.log" || G3_IP+=("unavailable label missing")
        ! grep -qF -- 'priority/p1-high' "$d/gh.log" || G3_IP+=("an unavailable run was filed at p1")
      iend
      isc I4-an-empty-class-fails-closed-to-unavailable
        g3_irun "$d" "" ""
        icreated "$G3_T_UNAV" || G3_IP+=("an empty class did not file the unavailable issue")
        grep -qF -- 'reason=unknown' "$d/body" || G3_IP+=("an empty reason was not recorded as unknown")
      iend
      isc I5-an-open-issue-that-already-records-the-reason-is-not-commented-again
        printf '[{"number":7,"title":"%s"}]' "$G3_T_RED" > "$d/list"; printf 'body reason=probe_stale\n' > "$d/view"
        g3_irun "$d" red probe_stale
        ! grep -q '^issue comment' "$d/gh.log" && ! grep -q '^issue create' "$d/gh.log" || G3_IP+=("a repeat reason commented or created again: $(tr '\n' '|' < "$d/gh.log" | head -c 160)")
      iend
      isc I6-a-changed-reason-is-commented
        printf '[{"number":7,"title":"%s"}]' "$G3_T_RED" > "$d/list"; printf 'body reason=probe_stale\n' > "$d/view"
        g3_irun "$d" red probe_not_luks
        grep -q '^issue comment 7 ' "$d/gh.log" || G3_IP+=("a changed reason was not commented")
        ! grep -q '^issue create' "$d/gh.log" || G3_IP+=("a duplicate issue was created beside the open one")
      iend
      isc I7-a-reason-with-shell-metacharacters-is-recorded-as-unknown
        g3_irun "$d" red 'x;touch /tmp/pwned'
        grep -qF -- 'reason=unknown' "$d/body" && ! grep -qF -- 'pwned' "$d/body" "$d/gh.log" || G3_IP+=("an unbounded reason reached the issue")
      iend
      isc I8-a-failing-dedupe-query-still-files-the-issue
        g3_irun "$d" red probe_stale FIXTURE_GH_LIST_FAIL=1
        icreated "$G3_T_RED" || G3_IP+=("a failed dedupe query filed nothing (fail OPEN is the contract)")
      iend
      isc I9-an-open-issue-of-the-OTHER-class-does-not-suppress-this-one
        printf '[{"number":9,"title":"%s"}]' "$G3_T_UNAV" > "$d/list"; printf 'reason=probe_stale\n' > "$d/view"
        g3_irun "$d" red probe_stale
        icreated "$G3_T_RED" || G3_IP+=("the unavailable issue swallowed a RED")
      iend
    }
    G3_ISB="$(g3_isb pristine)"
    g3_ibattery "$G3_ISB"
    for r in "${G3_IRES[@]}"; do
      if [[ "${r#*|}" == ok ]]; then ok "G3 issue step ${r%%|*}"; else no "G3 issue step ${r%%|*} violated: ${r#*|}"; fi
    done
    # MUTATION ROW 22 — the issue step's guards, each against a sandbox copy
    g3_imut() { # <label> <old> <new>
      local label="$1" old="$2" new="$3" d bad
      d="$(g3_isb "m$RANDOM")"
      if ! g3_sub "$d/issue.sh" "$old" "$new"; then no "G3 mutation 22 ($label): the edit did not land exactly once"; rm -rf "$d"; return; fi
      g3_ibattery "$d"
      bad="$(printf '%s\n' "${G3_IRES[@]}" | grep -vc '|ok$' || true)"
      if [[ "$bad" -ge 1 ]]; then ok "G3 mutation 22 ($label) -> RED ($bad issue-step scenario(s))"; else no "G3 mutation 22 ($label) stayed GREEN: the issue-step scenarios cannot see this defect"; fi
      rm -rf "$d"
    }
    g3_imut "the reason is not bounded before it reaches the issue" $'[[ "$reason" =~ ^[a-z0-9_]{1,64}$ ]] || reason=unknown' ':'
    g3_imut "the anti-spam bound is gone (every run comments)" $'if grep -qF -- "reason=${reason}" <<<"$prior"; then' 'if false; then'
    g3_imut "a failed dedupe query aborts instead of failing open" $'echo "::error::dedupe query failed (gh issue list) — filing without dedupe."' 'exit 1'
    g3_imut "an unknown or empty class files under the RED title instead of unavailable" 'title="[ci/luks-verify-web2] could not judge web-2 - nothing proven"' 'title="[ci/luks-verify-web2] web-2 LUKS evidence is RED"'
    g3_imut "dedupe ignores the title (any open ci/luks-verify issue absorbs the run)" $'map(select(.title == $t))' 'map(select(.title != ""))'
  fi

  # the pristine files were never edited by any row above
  if cmp -s "$G3/marker.sh" "$G3/sb-pristine/marker.sh" && cmp -s scripts/lib/web2-luks-rows.sh "$G3/sb-pristine/scripts/lib/web2-luks-rows.sh"; then
    ok "G3 the pristine step body and helper are byte-identical to the sandbox baseline after all mutation rows"
  else
    no "G3 a mutation row leaked into the pristine files"
  fi
fi

printf '\n%s passed, %s failed\n' "$pass" "$fail"

# NON-DEGENERACY FLOOR — DERIVED FROM THIS SUITE'S OWN GREEN RUN, not copied.
#
# It used to read 40, byte-identical to the sibling cutover-workflow suite. That sibling greens at
# 42, so 40 is a two-assertion slack THERE; here green is 108, so the same constant left 68
# assertions of slack and the floor could not do the job its own comment claimed. Measured against
# the pre-fix suite: deleting the entire evaluated truth-table block — this file's CENTRAL claim —
# reported "69 passed, 0 failed", exit 0; deleting both behavioral legs reported 41, exit 0. In
# other words 45% of the suite was deletable while it still reported success.
#
# EXACT, not "with slack": the floor equals the green count, so deleting ANY assertion reds the suite.
# Raise it, in the SAME edit, when you add assertions; if this ever fires, the question is which block
# stopped running, not what number to lower it to.
# History: #8706 132 -> 143; #6931 143 -> 184 (Guard 3), then Guard 3 review rework (51 registered scenarios
# each asserting rc, calls, final state, outcome and reason; structural rows evaluated over grids; the
# occurrence-based census with planted writers; mutation rows 1-21) -> 313; #7376 the producer-side
# SIGPIPE race rows (landing check, must-PASS late producer, non-draining-stub control) 313 -> 316; review:
# the drained-text and hand-off-by-sentinel rows 316 -> 318; #9372 the reboot-proof scenario (S53) and
# mutation row 22 318 -> 321 (measured green count after the rebase onto #9525, the ready-poll reader split and the S54 row).
# #9429: S55 (self-describing marker-read fault) + the set-only flag model + mutation row 17g 321 -> 323;
# review round 1: S56 (empty-value marker reads absent) + mutation row 17h 323 -> 325.
# 2026-10-08 (#9372, immutability not reboot): S59 (noop readiness arm refused) and S60 (opened) + mutation row 22b,
# with row 22 re-pointed at the old reboot requirement, 325 -> 332 (measured green count).
# Review round 1: S61/S62 (the NEWEST readiness row decides, both directions) + mutation row 22c, 332 -> 335.
WF_MIN_ASSERTIONS=335
if [[ "$pass" -lt "$WF_MIN_ASSERTIONS" ]]; then
  echo "FAIL - only $pass assertions ran (floor $WF_MIN_ASSERTIONS) — fewer verdicts than expected; a green run here would be vacuous"
  exit 1
fi
[[ "$fail" -eq 0 ]] || exit 1
