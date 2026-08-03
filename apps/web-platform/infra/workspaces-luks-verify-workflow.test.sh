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
    FIXTURE_BASELINE_READ_RC="${READRC:-0}" \
    ALARM_SELFTEST="${SELFTEST:-}" \
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
  title_of() { sed -n 's/.*--title \(.*\)/\1/p' "$1" | head -1 | sed 's/ --label.*//'; }

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
# Set from the green count with a small slack for ordinary additions. Raise it when you add
# assertions; if this ever fires, the question is which block stopped running, not what number to
# lower it to.
WF_MIN_ASSERTIONS=114
if [[ "$pass" -lt "$WF_MIN_ASSERTIONS" ]]; then
  echo "FAIL - only $pass assertions ran (floor $WF_MIN_ASSERTIONS) — fewer verdicts than expected; a green run here would be vacuous"
  exit 1
fi
[[ "$fail" -eq 0 ]] || exit 1
